#!/usr/bin/env python3
"""Preview renderer for parts exported by export_parts.luau.

Renders orthographic PNG previews of a Roblox place (no Studio needed):

  top    top-down map (looking down -Y, +X right, +Z down) with a stud grid
  iso    3D view from azimuth 45 deg (camera in the +X/+Z quadrant)
  iso2   3D view from azimuth 225 deg (camera in the -X/-Z quadrant)
  zoom   iso view around (x, z) with a radius; one image per --zoom argument

Usage:
  python3 tools/preview/render.py parts.json --out-dir out/ \
      [--views top,iso,iso2,zoom] [--zoom x,z,radius[,azimuth]]... [--size 1600]
  (see --help and tools/preview/README.md for all options)

Rendering is a small numpy z-buffer rasterizer: every part becomes a convex
polygon mesh, back faces are culled and opaque faces are depth tested. The nearest
transparent surface in front of them (glass, water) is then blended once per pixel.
Images are supersampled and box-filtered down for anti-aliasing; thin dark outlines
come from edges in the per-pixel face-id buffer.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import time

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# --------------------------------------------------------------------------------------
# Look & feel
# --------------------------------------------------------------------------------------

BACKGROUND_TOP = np.array([196, 214, 232], np.float32)
BACKGROUND_BOTTOM = np.array([226, 233, 240], np.float32)
WATER_COLOR = np.array([40, 120, 205], np.float32)
WATER_OPACITY = 0.55
SUN = np.array([-0.5, 1.0, 0.25])  # world-space direction towards the sun
SUN /= np.linalg.norm(SUN)
AMBIENT = 0.40  # shade = AMBIENT + (1 - AMBIENT) * half-lambert(n . sun)
OUTLINE_FACTOR = 0.62  # colour multiplier on outline pixels
ELEVATION_DEG = 35.0
HUGE_EXTENT = 1000.0  # parts wider than this are ignored when framing (Baseplate)

MAX_POLY = 16  # max vertices per face (cylinder caps)
CYL_SEGMENTS = 16
SPHERE_STACKS, SPHERE_SLICES = 6, 10


# --------------------------------------------------------------------------------------
# Unit meshes. Vertices are scaled per part by a "half extent" vector, faces are
# vertex index lists (any cyclic order; normals are oriented outward later) and each
# face carries a smoothing group: faces in the same group share an outline id.
# --------------------------------------------------------------------------------------


def _block_mesh():
    verts = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    faces = [[0, 1, 3, 2], [4, 6, 7, 5], [0, 4, 5, 1], [2, 3, 7, 6], [0, 2, 6, 4], [1, 5, 7, 3]]
    return np.array(verts, float), faces, list(range(6))


def _wedge_mesh():
    # Full bottom and full back (+Z) face; slope from the top-back edge down to the
    # bottom-front edge, i.e. it faces -Z/+Y.
    verts = [(-1, -1, -1), (1, -1, -1), (-1, -1, 1), (1, -1, 1), (-1, 1, 1), (1, 1, 1)]
    faces = [[0, 1, 3, 2], [2, 3, 5, 4], [0, 1, 5, 4], [0, 2, 4], [1, 3, 5]]
    return np.array(verts, float), faces, list(range(5))


def _corner_wedge_mesh():
    # Rectangular base with the apex above the (+X, -Z) corner: vertical faces at +X
    # and -Z, sloped faces towards -X and +Z.
    verts = [(-1, -1, -1), (1, -1, -1), (1, -1, 1), (-1, -1, 1), (1, 1, -1)]
    faces = [[0, 1, 2, 3], [0, 1, 4], [1, 2, 4], [2, 3, 4], [3, 0, 4]]
    return np.array(verts, float), faces, list(range(5))


def _cylinder_mesh(n=CYL_SEGMENTS):
    # Axis along local X (Roblox convention). Scale = (length/2, r, r).
    ang = np.arange(n) * 2 * math.pi / n
    ring = np.stack([np.cos(ang), np.sin(ang)], 1)
    verts = [(-1, c, s) for c, s in ring] + [(1, c, s) for c, s in ring]
    sides = [[k, (k + 1) % n, n + (k + 1) % n, n + k] for k in range(n)]
    faces = sides + [list(range(n)), list(range(n, 2 * n))]
    return np.array(verts, float), faces, [0] * n + [1, 2]


def _sphere_mesh(stacks=SPHERE_STACKS, slices=SPHERE_SLICES):
    verts = [(0, 1, 0)]
    for i in range(1, stacks):
        phi = math.pi * i / stacks
        for j in range(slices):
            th = 2 * math.pi * j / slices
            verts.append((math.sin(phi) * math.cos(th), math.cos(phi), math.sin(phi) * math.sin(th)))
    verts.append((0, -1, 0))
    bottom = len(verts) - 1

    def ring(i, j):
        return 1 + (i - 1) * slices + (j % slices)

    faces = []
    for j in range(slices):
        faces.append([0, ring(1, j), ring(1, j + 1)])
        faces.append([bottom, ring(stacks - 1, j + 1), ring(stacks - 1, j)])
    for i in range(1, stacks - 1):
        for j in range(slices):
            faces.append([ring(i, j), ring(i, j + 1), ring(i + 1, j + 1), ring(i + 1, j)])
    return np.array(verts, float), faces, [0] * len(faces)


MESHES = {
    "Block": _block_mesh(),
    "Wedge": _wedge_mesh(),
    "CornerWedge": _corner_wedge_mesh(),
    "Cylinder": _cylinder_mesh(),
    "Ball": _sphere_mesh(),
}


def _half_extents(shape, size):
    """Per-part scale applied to the unit mesh (Roblox sizing rules)."""
    if shape == "Cylinder":
        r = np.minimum(size[:, 1], size[:, 2]) / 2
        return np.stack([size[:, 0] / 2, r, r], 1)
    if shape == "Ball":
        r = size.min(1) / 2
        return np.stack([r, r, r], 1)
    return size / 2


# --------------------------------------------------------------------------------------
# Scene: all faces of all parts as padded polygon arrays.
# --------------------------------------------------------------------------------------


class Scene:
    """Parts from the JSON turned into one flat list of convex faces plus per-part data."""

    def __init__(self, data):
        self.parts = data.get("parts", [])
        self.slots = data.get("slots", [])
        self._build()

    def _build(self):
        parts = self.parts
        n = len(parts)
        cf = np.array([p["cf"] for p in parts], float).reshape(n, 12)
        size = np.array([p["size"] for p in parts], float).reshape(n, 3)
        pos = cf[:, :3]
        rot = cf[:, 3:].reshape(n, 3, 3)  # row-major: world = R @ local + p
        self.pos, self.rot, self.size = pos, rot, size
        kinds = [p.get("kind", "part") for p in parts]

        # World AABBs (used for framing and zoom culling).
        half = np.einsum("nij,nj->ni", np.abs(rot), size / 2)
        self.aabb_min, self.aabb_max = pos - half, pos + half

        # Per-part material.
        color = np.array([p.get("color", [163, 162, 165]) for p in parts], np.float32).reshape(n, 3)
        opacity = np.array([1.0 - float(p.get("transparency", 0)) for p in parts], np.float32)
        unlit = np.array([p.get("material") == "Neon" for p in parts], bool)
        water = np.array([k == "water" for k in kinds], bool)
        color[water] = WATER_COLOR
        opacity[water] = WATER_OPACITY
        unlit[water] = False

        polys, counts, normals, centroids, groups, owners = [], [], [], [], [], []
        group_base = 0
        shape_of = np.array([p.get("shape", "Block") for p in parts])
        special = [s for s in MESHES if s != "Block"]
        for shape, (uverts, faces, fgroups) in MESHES.items():
            if shape == "Block":  # blocks and any unknown shape
                idx = np.nonzero(~np.isin(shape_of, special))[0]
            else:
                idx = np.nonzero(shape_of == shape)[0]
            if len(idx) == 0:
                continue
            scale = _half_extents(shape, size[idx])
            local = uverts[None, :, :] * scale[:, None, :]
            world = np.einsum("nij,nvj->nvi", rot[idx], local) + pos[idx][:, None, :]
            center = world.mean(1)  # strictly inside the convex mesh
            ngroups = max(fgroups) + 1
            for f, fg in zip(faces, fgroups):
                k = len(f)
                padded = f + [f[-1]] * (MAX_POLY - k)  # repeating a vertex is harmless
                poly = world[:, padded, :]
                cen = world[:, f, :].mean(1)
                nrm = _newell(poly)
                flip = np.einsum("ni,ni->n", nrm, cen - center) < 0
                nrm[flip] *= -1
                polys.append(poly)
                counts.append(np.full(len(idx), k))
                normals.append(nrm)
                centroids.append(cen)
                groups.append(group_base + np.arange(len(idx)) * ngroups + fg)
                owners.append(idx)
            group_base += len(idx) * ngroups

        if polys:
            self.poly = np.concatenate(polys).astype(np.float64)
            self.count = np.concatenate(counts)
            self.normal = np.concatenate(normals)
            self.centroid = np.concatenate(centroids)
            self.group = np.concatenate(groups).astype(np.int32)
            owner = np.concatenate(owners)
        else:
            self.poly = np.zeros((0, MAX_POLY, 3))
            self.count = np.zeros(0, int)
            self.normal = np.zeros((0, 3))
            self.centroid = np.zeros((0, 3))
            self.group = np.zeros(0, np.int32)
            owner = np.zeros(0, int)
        self.owner = owner
        self.face_color = color[owner]
        self.face_opacity = opacity[owner]
        self.face_unlit = unlit[owner]
        # Depth bias (studs) so content flush with a Baseplate-sized slab wins ties.
        ext = self.aabb_max - self.aabb_min
        self.content = (ext[:, 0] < HUGE_EXTENT) & (ext[:, 2] < HUGE_EXTENT)
        self.face_bias = np.where(self.content[owner], 0.0, 0.05)

        # Lighting is view independent: precompute shaded face colours.
        ndotl = self.normal @ SUN
        shade = AMBIENT + (1 - AMBIENT) * (0.5 + 0.5 * ndotl)
        lit = self.face_color * shade[:, None]
        neon = np.minimum(self.face_color * 1.1 + 25, 255)
        self.face_rgb = np.where(self.face_unlit[:, None], neon, lit).clip(0, 255).astype(np.float32)

        self.stats = {k: kinds.count(k) for k in sorted(set(kinds))}
        self.water = water
        self.is_base = np.array([k == "base" for k in kinds], bool)

    def frame_box(self, mode="auto"):
        """World AABB (lo, hi) that views are framed on.

        all:  every part except Baseplate-sized ones (>= HUGE_EXTENT wide).
        auto: like "all", but also ignores water and the outermost 1% of part extents
              (e.g. a few big ocean-floor slabs around an island), then re-adds every
              simulated base so bases are never cut off.
        """
        if len(self.parts) == 0:
            return np.array([-50.0, -5, -50]), np.array([50.0, 5, 50])
        keep = self.content.copy() if self.content.any() else np.ones(len(self.parts), bool)
        if mode == "all":
            return self.aabb_min[keep].min(0), self.aabb_max[keep].max(0)
        if (keep & ~self.water).any():
            keep &= ~self.water
        lo = np.quantile(self.aabb_min[keep], 0.01, axis=0, method="lower")
        hi = np.quantile(self.aabb_max[keep], 0.99, axis=0, method="higher")
        if self.is_base.any():
            lo = np.minimum(lo, self.aabb_min[self.is_base].min(0))
            hi = np.maximum(hi, self.aabb_max[self.is_base].max(0))
        return lo, hi

    def vertices_within(self, lo, hi):
        """Mesh vertices of the parts lying completely inside the box (tight 3D framing)."""
        eps = 1e-3
        inside = np.all(self.aabb_min >= lo - eps, 1) & np.all(self.aabb_max <= hi + eps, 1)
        return self.poly[inside[self.owner]].reshape(-1, 3)


def _newell(poly):
    """Unit normals of (N, k, 3) polygons (Newell's method; robust for padded polygons)."""
    nxt = np.roll(poly, -1, axis=1)
    x, y, z = poly[..., 0], poly[..., 1], poly[..., 2]
    nx_, ny_, nz_ = nxt[..., 0], nxt[..., 1], nxt[..., 2]
    n = np.stack(
        [((y - ny_) * (z + nz_)).sum(1), ((z - nz_) * (x + nx_)).sum(1), ((x - nx_) * (y + ny_)).sum(1)], 1
    )
    length = np.linalg.norm(n, axis=1, keepdims=True)
    return n / np.maximum(length, 1e-12)


# --------------------------------------------------------------------------------------
# Camera: orthographic, defined by forward/right/up and a world-space centre.
# --------------------------------------------------------------------------------------


class Camera:
    """Orthographic camera: forward/right/up basis, centre point and pixels per stud."""

    def __init__(self, forward, center, scale, width, height, ss, up_hint=(0, 1, 0)):
        f = np.asarray(forward, float)
        f /= np.linalg.norm(f)
        r = np.cross(f, up_hint)
        if np.linalg.norm(r) < 1e-6:  # looking straight down: +X right, -Z up
            r = np.array([1.0, 0, 0])
        r /= np.linalg.norm(r)
        u = np.cross(r, f)
        self.f, self.r, self.u = f, r, u
        self.center = np.asarray(center, float)
        self.scale = scale  # final-image pixels per stud
        self.width, self.height, self.ss = width, height, ss

    @staticmethod
    def top(center, scale, width, height, ss):
        cam = Camera((0, -1, 0), center, scale, width, height, ss)
        cam.r, cam.u = np.array([1.0, 0, 0]), np.array([0, 0, -1.0])  # +Z points down
        return cam

    @staticmethod
    def orbit(azimuth_deg, elevation_deg, center, scale, width, height, ss):
        """Camera on a sphere around `center`: azimuth from +Z towards +X, elevation up."""
        az, el = math.radians(azimuth_deg), math.radians(elevation_deg)
        eye = np.array([math.sin(az) * math.cos(el), math.sin(el), math.cos(az) * math.cos(el)])
        return Camera(-eye, center, scale, width, height, ss)

    def project(self, pts, ss=None):
        """World points (..., 3) -> pixel x, y and depth (smaller = closer)."""
        s = self.scale * (self.ss if ss is None else ss)
        w = self.width * (self.ss if ss is None else ss)
        h = self.height * (self.ss if ss is None else ss)
        rel = pts - self.center
        x = rel @ self.r * s + w / 2
        y = -(rel @ self.u) * s + h / 2
        d = rel @ self.f
        return x, y, d


# --------------------------------------------------------------------------------------
# Rasterizer
# --------------------------------------------------------------------------------------


_POOL = {}


def _buffer(name, shape, dtype):
    """Reusable scratch buffers: big fresh allocations are dominated by page faults."""
    n = int(np.prod(shape))
    buf = _POOL.get(name)
    if buf is None or buf.size < n or buf.dtype != dtype:
        buf = np.empty(n, dtype)
        _POOL[name] = buf
    return buf[:n].reshape(shape)


def render(scene: Scene, cam: Camera, outlines=True, face_filter=None):
    """Rasterize the scene into a supersampled (H*ss, W*ss, 3) uint8 array.

    Pass 1 z-buffers opaque faces (storing a face index per pixel), pass 2 finds the
    nearest transparent surface in front of that, which is blended once. Blending a
    single layer keeps water made of many adjacent volumes free of seams.
    """
    ss = cam.ss
    W, H = cam.width * ss, cam.height * ss
    s = cam.scale * ss
    F = len(scene.count)

    # Colour table: one entry per face, then one background-gradient entry per row.
    t = np.linspace(0, 1, H, dtype=np.float32)[:, None]
    bg_rows = BACKGROUND_TOP * (1 - t) + BACKGROUND_BOTTOM * t
    table = np.concatenate([scene.face_rgb, bg_rows]).round().clip(0, 255).astype(np.uint8)

    zbuf = _buffer("zbuf", (H, W), np.float32)
    zbuf.fill(np.inf)
    fidx = _buffer("fidx", (H, W), np.int32)
    fidx[:] = (F + np.arange(H, dtype=np.int32))[:, None]  # background = row entry

    sel = np.ones(F, bool) if face_filter is None else face_filter.copy()
    # Back-face culling (also drops edge-on faces whose depth plane is unstable).
    nf = scene.normal @ cam.f
    sel &= nf < -1e-4

    px, py, _ = cam.project(scene.poly)
    x0 = np.floor(px.min(1)).clip(0, W).astype(np.int64)
    x1 = np.ceil(px.max(1)).clip(0, W).astype(np.int64)
    y0 = np.floor(py.min(1)).clip(0, H).astype(np.int64)
    y1 = np.ceil(py.max(1)).clip(0, H).astype(np.int64)
    sel &= (x1 > x0) & (y1 > y0)

    # Polygon winding in screen space (so "inside" is always the same side).
    area = (px * np.roll(py, -1, 1) - py * np.roll(px, -1, 1)).sum(1)
    sel &= np.abs(area) > 1e-9
    sign = np.where(area > 0, 1.0, -1.0)

    # Depth plane d = A*x + B*y + C in pixel space (orthographic => linear).
    # Baseplate-sized parts are pushed back slightly so flush content wins ties.
    nr, nu = scene.normal @ cam.r, scene.normal @ cam.u
    k = np.einsum("ni,ni->n", scene.normal, scene.centroid - cam.center)
    with np.errstate(divide="ignore", invalid="ignore"):
        A = -nr / (s * nf)
        B = nu / (s * nf)
        C = (k + nr * W / (2 * s) - nu * H / (2 * s)) / nf + scene.face_bias

    raster = _Rasterizer(px, py, sign, A, B, C, scene.count, x0, x1, y0, y1, W, H)
    opaque = np.nonzero(sel & (scene.face_opacity >= 0.999))[0]
    transparent = np.nonzero(sel & (scene.face_opacity < 0.999) & (scene.face_opacity > 0.0))[0]

    _depth_pass(raster, opaque, zbuf, fidx)
    img = _buffer("img", (H, W, 3), np.uint8)
    np.take(table, fidx, axis=0, out=img, mode="clip")

    # Outlines where the visible smoothing group changes (background = -1).
    if outlines:
        groups = np.concatenate([scene.group, np.full(H, -1, np.int32)])
        ids = _buffer("ids", (H, W), np.int32)
        np.take(groups, fidx, out=ids, mode="clip")
        edge = _buffer("edge", (H, W), bool)
        edge[:, -1] = False
        np.not_equal(ids[:, :-1], ids[:, 1:], out=edge[:, :-1])
        edge[:-1, :] |= ids[:-1, :] != ids[1:, :]
        edge &= ids >= 0
        img[edge] = (img[edge] * OUTLINE_FACTOR).astype(np.uint8)

    if len(transparent):
        tz = _buffer("tz", (H, W), np.float32)
        tz.fill(np.inf)
        tf = _buffer("tf", (H, W), np.int32)
        tf.fill(-1)
        _depth_pass(raster, transparent, tz, tf, limit=zbuf)
        # Blend in row chunks to keep temporaries small (page faults are expensive).
        keep = scene.face_opacity[:, None].astype(np.float32)
        tint = scene.face_rgb * keep + 0.5
        keep = 1 - keep
        for r0 in range(0, H, 256):
            rows = tf[r0 : r0 + 256]
            hit = rows >= 0
            if not hit.any():
                continue
            face = rows[hit]
            sub = img[r0 : r0 + 256]
            sub[hit] = (sub[hit] * keep[face] + tint[face]).astype(np.uint8)
    return img


def _depth_pass(raster, faces, zbuf, fidx, limit=None):
    """Keep the nearest of `faces` per pixel in zbuf/fidx (and in front of `limit`)."""
    zflat, fflat = zbuf.reshape(-1), fidx.reshape(-1)
    lflat = None if limit is None else limit.reshape(-1)
    for item in raster.cover(faces):
        if item[0] == "block":  # one strip of a big face
            _, i, r0, r1, c0, c1, mask, depth = item
            zsub = zbuf[r0:r1, c0:c1]
            m = depth < zsub
            if limit is not None:
                m &= depth < limit[r0:r1, c0:c1]
            if mask is not None:
                m &= mask
            np.copyto(zsub, depth, where=m)
            np.copyto(fidx[r0:r1, c0:c1], np.int32(i), where=m)
        else:  # pixel fragments of many small faces
            _, pix, depth, face = item
            keep = depth < zflat[pix]
            if lflat is not None:
                keep &= depth < lflat[pix]
            pix, depth, face = pix[keep], depth[keep], face[keep]
            np.minimum.at(zflat, pix, depth)
            win = depth == zflat[pix]
            fflat[pix[win]] = face[win]


class _Rasterizer:
    """Convex polygon coverage.

    Small faces are bucketed by bounding-box size and evaluated with edge functions on
    a T x T pixel grid per face in one vectorized pass (yielding pixel fragments).
    Faces larger than the biggest bucket are scan-converted one at a time: per-row
    [left, right] spans from the edges, emitted in horizontal strips (blocks).
    """

    BUCKETS = (4, 8, 16, 32, 64)
    CHUNK_PIXELS = 1 << 20  # max faces*T*T elements per vectorized chunk
    STRIP_PIXELS = 1 << 19  # max pixels per strip of a big face

    def __init__(self, px, py, sign, A, B, C, count, x0, x1, y0, y1, W, H):
        self.px, self.py, self.sign = px, py, sign
        self.A, self.B, self.C = A, B, C
        self.count = count
        self.x0, self.x1, self.y0, self.y1 = x0, x1, y0, y1
        self.W, self.H = W, H

    def cover(self, faces):
        """Yield ("frag", pix, depth, face) batches and ("block", ...) strips."""
        if len(faces) == 0:
            return
        span = np.maximum(self.x1[faces] - self.x0[faces], self.y1[faces] - self.y0[faces])
        bucket = np.searchsorted(self.BUCKETS, span)  # len(BUCKETS) = too big for a bucket
        for b, T in enumerate(self.BUCKETS):
            group = faces[bucket == b]
            if len(group) == 0:
                continue
            group = group[np.argsort(self.count[group], kind="stable")]  # similar vertex counts
            step = max(1, self.CHUNK_PIXELS // (T * T))
            for start in range(0, len(group), step):
                yield self._batch(group[start : start + step], T)
        for i in faces[bucket == len(self.BUCKETS)]:
            yield from self._blocks(int(i))

    def _batch(self, faces, T):
        g = np.arange(T, dtype=np.float32) + 0.5
        x0, y0 = self.x0[faces], self.y0[faces]
        fx0, fy0 = x0.astype(np.float32), y0.astype(np.float32)
        xs = (fx0[:, None] + g[None, :])[:, None, :]  # (F, 1, T) pixel centres
        ys = (fy0[:, None] + g[None, :])[:, :, None]  # (F, T, 1)
        inside = (xs < self.x1[faces][:, None, None]) & (ys < self.y1[faces][:, None, None])
        sign = self.sign[faces]
        cnt = self.count[faces]
        rows = np.arange(len(faces))
        vx, vy = self.px[faces], self.py[faces]
        for j in range(int(cnt.max())):
            # Edge j -> j+1, closing back to vertex 0. Past a face's own vertex count the
            # padded vertex equals the last one, so this just repeats the closing edge.
            nxt = np.where(j + 1 >= cnt, 0, j + 1)
            ax, ay = vx[:, j], vy[:, j]
            ex = (sign * (vx[rows, nxt] - ax)).astype(np.float32)[:, None, None]
            ey = (sign * (vy[rows, nxt] - ay)).astype(np.float32)[:, None, None]
            ax = ax.astype(np.float32)[:, None, None]
            ay = ay.astype(np.float32)[:, None, None]
            inside &= ex * (ys - ay) - ey * (xs - ax) >= -1e-3
        fi, gy, gx = np.nonzero(inside)
        depth = (
            self.A[faces][fi] * (fx0[fi] + gx + 0.5)
            + self.B[faces][fi] * (fy0[fi] + gy + 0.5)
            + self.C[faces][fi]
        )
        pix = (y0[fi] + gy) * self.W + (x0[fi] + gx)
        return "frag", pix, depth.astype(np.float32), faces[fi].astype(np.int32)

    def _blocks(self, i):
        """Yield ("block", i, r0, r1, c0, c1, mask|None, depth) strips covering face i."""
        a, b, c, d = int(self.x0[i]), int(self.x1[i]), int(self.y0[i]), int(self.y1[i])
        n = int(self.count[i])
        vx, vy, sign = self.px[i, :n], self.py[i, :n], self.sign[i]

        # Per-row span of pixel centres inside the polygon (intersection of half-planes).
        ys = np.arange(c, d, dtype=np.float64) + 0.5
        left = np.full(d - c, -np.inf)
        right = np.full(d - c, np.inf)
        for j in range(n):
            ax, ay = vx[j], vy[j]
            ex, ey = sign * (vx[(j + 1) % n] - ax), sign * (vy[(j + 1) % n] - ay)
            # inside: ex*(y-ay) - ey*(x-ax) >= 0
            if ey > 1e-12:
                np.minimum(right, ax + ex * (ys - ay) / ey, out=right)
            elif ey < -1e-12:
                np.maximum(left, ax + ex * (ys - ay) / ey, out=left)
            elif ex != 0:
                right[ex * (ys - ay) < 0] = -np.inf  # horizontal edge: whole rows outside
        jl = np.ceil(np.clip(left - 0.5 - 1e-6, a - 1, b)).astype(np.int64)
        jr = np.floor(np.clip(right - 0.5 + 1e-6, a - 1, b)).astype(np.int64)
        jl = np.maximum(jl, a)
        jr = np.minimum(jr, b - 1)
        rows = np.nonzero(jl <= jr)[0]
        if len(rows) == 0:
            return

        cols = np.arange(a, b)
        xs = cols.astype(np.float32) + 0.5
        A, B, C = np.float32(self.A[i]), np.float32(self.B[i]), np.float32(self.C[i])
        step = max(1, self.STRIP_PIXELS // max(1, b - a))
        for s0 in range(int(rows[0]), int(rows[-1]) + 1, step):
            s1 = min(int(rows[-1]) + 1, s0 + step)
            sl, sr = jl[s0:s1], jr[s0:s1]
            if (sl == a).all() and (sr == b - 1).all():
                mask = None  # strip fully covered
            else:
                mask = (cols[None, :] >= sl[:, None]) & (cols[None, :] <= sr[:, None])
            yss = ys[s0:s1].astype(np.float32)
            depth = (A * xs)[None, :] + (B * yss)[:, None] + C
            yield "block", i, c + s0, c + s1, a, b, mask, depth


def to_image(buf, ss):
    """Box-filter the supersampled buffer down to the output size (copies the data)."""
    im = Image.fromarray(buf, "RGB")
    return im.reduce(ss) if ss > 1 else im.copy()


# --------------------------------------------------------------------------------------
# Overlays (grid, labels, legend)
# --------------------------------------------------------------------------------------


def _font(size):
    try:
        return ImageFont.load_default(size=size)
    except TypeError:  # very old Pillow without scalable default font
        return ImageFont.load_default()


def _text(draw, xy, text, font, fill=(20, 24, 30), stroke=(255, 255, 255), anchor="la"):
    draw.text(xy, text, font=font, fill=fill, stroke_width=2, stroke_fill=stroke, anchor=anchor)


def _nice_step(target):
    """Smallest 'nice' stud distance (8, 16, 32, 64...) at least `target` studs."""
    step = 8
    while step < target:
        step *= 2
    return step


def draw_top_overlay(im, cam, avoid):
    draw = ImageDraw.Draw(im, "RGBA")
    W, H = im.size
    font = _font(15)
    # Inverse mapping pixel -> world for grid extents.
    half_w, half_h = W / 2 / cam.scale, H / 2 / cam.scale
    xmin, xmax = cam.center[0] - half_w, cam.center[0] + half_w
    zmin, zmax = cam.center[2] - half_h, cam.center[2] + half_h

    def wx(x):
        return (x - cam.center[0]) * cam.scale + W / 2

    def wz(z):
        return (z - cam.center[2]) * cam.scale + H / 2

    # Minor lines every 16 studs (if not too dense), major every 32.
    for step, color in ((16, (255, 255, 255, 40)), (32, (255, 255, 255, 95))):
        if step * cam.scale < 6:
            continue
        for gx in np.arange(math.ceil(xmin / step) * step, xmax + 1e-6, step):
            draw.line([(wx(gx), 0), (wx(gx), H)], fill=color, width=1)
        for gz in np.arange(math.ceil(zmin / step) * step, zmax + 1e-6, step):
            draw.line([(0, wz(gz)), (W, wz(gz))], fill=color, width=1)
    # Axes through the origin.
    if xmin <= 0 <= xmax:
        draw.line([(wx(0), 0), (wx(0), H)], fill=(200, 40, 40, 140), width=1)
    if zmin <= 0 <= zmax:
        draw.line([(0, wz(0)), (W, wz(0))], fill=(40, 70, 200, 140), width=1)
    # Coordinate labels along the top and left edges.
    label_step = _nice_step(70 / cam.scale)
    for gx in np.arange(math.ceil(xmin / label_step) * label_step, xmax + 1e-6, label_step):
        if wx(gx) > avoid[2] + 4 and wx(gx) < W - 50:
            _text(draw, (wx(gx) + 3, 4), f"x={gx:g}", font)
    for gz in np.arange(math.ceil(zmin / label_step) * label_step, zmax + 1e-6, label_step):
        if wz(gz) > avoid[3] + 4 and wz(gz) < H - 60:
            _text(draw, (4, wz(gz) + 2), f"z={gz:g}", font)

    # Axis legend (bottom right).
    ox, oy = W - 110, H - 110
    draw.rectangle([ox - 10, oy - 10, W - 10, H - 10], fill=(255, 255, 255, 190))
    draw.line([(ox, oy + 10), (ox + 60, oy + 10)], fill=(200, 30, 30, 255), width=3)
    draw.polygon([(ox + 70, oy + 10), (ox + 58, oy + 4), (ox + 58, oy + 16)], fill=(200, 30, 30, 255))
    _text(draw, (ox + 20, oy + 16), "+X", font, fill=(200, 30, 30))
    draw.line([(ox + 4, oy + 10), (ox + 4, oy + 70)], fill=(30, 60, 210, 255), width=3)
    draw.polygon([(ox + 4, oy + 80), (ox - 2, oy + 68), (ox + 10, oy + 68)], fill=(30, 60, 210, 255))
    _text(draw, (ox + 12, oy + 50), "+Z", font, fill=(30, 60, 210))

    _scale_bar(draw, cam.scale, (14, H - 20), font)
    return im


def _scale_bar(draw, px_per_stud, origin, font):
    studs = _nice_step(120 / px_per_stud)
    length = studs * px_per_stud
    x, y = origin
    label = f"{studs} studs  ({px_per_stud:.2f} px/stud)"
    box_w = max(length, draw.textlength(label, font=font))
    draw.rectangle([x - 6, y - 30, x + box_w + 8, y + 8], fill=(255, 255, 255, 190))
    draw.line([(x, y), (x + length, y)], fill=(20, 20, 20, 255), width=3)
    draw.line([(x, y - 6), (x, y + 2)], fill=(20, 20, 20, 255), width=2)
    draw.line([(x + length, y - 6), (x + length, y + 2)], fill=(20, 20, 20, 255), width=2)
    _text(draw, (x, y - 26), label, font)


def draw_axis_gizmo(im, cam):
    draw = ImageDraw.Draw(im, "RGBA")
    W, H = im.size
    font = _font(15)
    ox, oy = W - 80, H - 80
    draw.ellipse([ox - 62, oy - 62, ox + 62, oy + 62], fill=(255, 255, 255, 170))
    axes = (((1, 0, 0), "+X", (200, 30, 30)), ((0, 1, 0), "+Y", (30, 150, 40)), ((0, 0, 1), "+Z", (30, 60, 210)))
    for vec, label, col in axes:
        v = np.array(vec, float)
        dx, dy = float(v @ cam.r), -float(v @ cam.u)
        ex, ey = ox + dx * 45, oy + dy * 45
        draw.line([(ox, oy), (ex, ey)], fill=col + (255,), width=3)
        _text(draw, (ox + dx * 58, oy + dy * 58), label, font, fill=col, anchor="mm")


def draw_slot_labels(im, cam, scene):
    if not scene.slots:
        return
    draw = ImageDraw.Draw(im, "RGBA")
    font = _font(16)
    for slot in scene.slots:
        p = np.array(slot["cf"][:3], float)
        x, y, _ = cam.project(p, ss=1)
        if not (0 <= x < im.size[0] and 0 <= y < im.size[1]):
            continue
        col = tuple(int(c) for c in slot.get("color", [255, 255, 255]))
        draw.ellipse([x - 13, y - 13, x + 13, y + 13], fill=col + (230,), outline=(20, 20, 20, 255), width=2)
        _text(draw, (x, y), str(slot["index"]), font, anchor="mm")


def draw_title(im, lines):
    """Draw the info box in the top-left corner; returns its rectangle."""
    draw = ImageDraw.Draw(im, "RGBA")
    font = _font(16)
    width = max(draw.textlength(line, font=font) for line in lines)
    box = (6, 6, 18 + width, 12 + 21 * len(lines))
    draw.rectangle(box, fill=(255, 255, 255, 190))
    for i, line in enumerate(lines):
        _text(draw, (12, 10 + 21 * i), line, font)
    return box


# --------------------------------------------------------------------------------------
# Views
# --------------------------------------------------------------------------------------


def _fit(extent_w, extent_h, size, min_aspect=0.5, max_aspect=1.6, margin=0.06):
    """Pick image width/height and px-per-stud so the extent fits with a margin."""
    extent_w, extent_h = max(extent_w, 1e-3), max(extent_h, 1e-3)
    aspect = min(max(extent_h / extent_w, min_aspect), max_aspect)
    width = size
    height = int(round(size * aspect))
    scale = min(width / extent_w, height / extent_h) * (1 - 2 * margin)
    return width, height, scale


def view_top(scene, args):
    lo, hi = _bounds(scene, args)
    center = (lo + hi) / 2
    center[1] = hi[1] + 10
    width, height, scale = _fit(hi[0] - lo[0], hi[2] - lo[2], args.size)
    cam = Camera.top(center, scale, width, height, args.ss)
    im = to_image(render(scene, cam, outlines=not args.no_outlines), args.ss)
    box = draw_title(
        im,
        [
            "TOP  (looking down -Y;  +X right, +Z down)",
            f"x {lo[0]:.0f}..{hi[0]:.0f}   z {lo[2]:.0f}..{hi[2]:.0f}   y {lo[1]:.0f}..{hi[1]:.0f}",
            _stats_line(scene),
        ],
    )
    draw_top_overlay(im, cam, box)
    if not args.no_labels:
        draw_slot_labels(im, cam, scene)
    return im


def view_orbit(scene, args, azimuth, title):
    lo, hi = _bounds(scene, args)
    center = (lo + hi) / 2
    probe = Camera.orbit(azimuth, args.elevation, center, 1.0, 1, 1, 1)
    pts = scene.vertices_within(lo, hi)  # tight fit around the geometry in the box
    if args.bounds or len(pts) == 0:
        pts = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
    rel = pts - center
    sx, sy = rel @ probe.r, rel @ probe.u
    # Re-centre on the projected box so it is not offset in the frame.
    center = center + probe.r * (sx.max() + sx.min()) / 2 + probe.u * (sy.max() + sy.min()) / 2
    width, height, scale = _fit(sx.max() - sx.min(), sy.max() - sy.min(), args.size)
    cam = Camera.orbit(azimuth, args.elevation, center, scale, width, height, args.ss)
    im = to_image(render(scene, cam, outlines=not args.no_outlines), args.ss)
    draw_axis_gizmo(im, cam)
    if not args.no_labels:
        draw_slot_labels(im, cam, scene)
    font = _font(15)
    _scale_bar(ImageDraw.Draw(im, "RGBA"), scale, (14, im.size[1] - 20), font)
    draw_title(
        im,
        [f"{title}  (orthographic, azimuth {azimuth:g} deg, elevation {args.elevation:g} deg)", _stats_line(scene)],
    )
    return im


def view_zoom(scene, args, x, z, radius, azimuth):
    # Keep parts whose XZ footprint is near the zoom disc so unrelated geometry in
    # front of it does not block the view (Baseplate-sized parts are always kept).
    keep_r = radius * args.zoom_cull if args.zoom_cull > 0 else float("inf")
    dx = np.maximum(np.maximum(scene.aabb_min[:, 0] - x, x - scene.aabb_max[:, 0]), 0)
    dz = np.maximum(np.maximum(scene.aabb_min[:, 2] - z, z - scene.aabb_max[:, 2]), 0)
    near = np.hypot(dx, dz) <= keep_r
    # Vertical centre: halfway between the floor (low percentile of the part tops in
    # the disc) and the tallest part there, limited so tall things don't push the
    # floor out of the frame.
    inside = near & scene.content & (np.hypot(dx, dz) <= radius)
    if inside.any():
        tops = scene.aabb_max[inside, 1]
        floor = float(np.percentile(tops, 10))
        y = (floor + min(float(tops.max()), floor + radius)) / 2
    else:
        y = 0.0

    face_filter = near[scene.owner]
    width = args.size
    height = int(round(args.size * 0.75))
    scale = width / (2 * radius)
    cam = Camera.orbit(azimuth, args.elevation, np.array([x, y, z]), scale, width, height, args.ss)
    im = to_image(render(scene, cam, outlines=not args.no_outlines, face_filter=face_filter), args.ss)
    draw_axis_gizmo(im, cam)
    if not args.no_labels:
        draw_slot_labels(im, cam, scene)
    _scale_bar(ImageDraw.Draw(im, "RGBA"), scale, (14, im.size[1] - 20), _font(15))
    draw_title(
        im,
        [
            f"ZOOM  centre ({x:g}, {y:.1f}, {z:g})  radius {radius:g}  azimuth {azimuth:g} deg",
            f"{int(near.sum())} of {len(scene.parts)} parts shown (cull radius {keep_r:g})",
        ],
    )
    return im


def _bounds(scene, args):
    lo, hi = scene.frame_box(args.frame)
    if args.bounds:
        xmin, zmin, xmax, zmax = args.bounds
        lo = np.array([xmin, lo[1], zmin], float)
        hi = np.array([xmax, hi[1], zmax], float)
    return lo.astype(float), hi.astype(float)


def _stats_line(scene):
    kinds = ", ".join(f"{k}={v}" for k, v in scene.stats.items())
    return f"{len(scene.parts)} parts ({kinds}), {len(scene.slots)} base slots"


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------


def _parse_zoom(text):
    vals = [float(v) for v in text.split(",")]
    if len(vals) not in (3, 4):
        raise argparse.ArgumentTypeError("--zoom expects x,z,radius[,azimuth]")
    return vals


def _parse_bounds(text):
    vals = [float(v) for v in text.split(",")]
    if len(vals) != 4:
        raise argparse.ArgumentTypeError("--bounds expects xmin,zmin,xmax,zmax")
    return vals


def main(argv=None):
    ap = argparse.ArgumentParser(description="Render preview PNGs from export_parts.luau JSON.")
    ap.add_argument("parts_json")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--views", default="top,iso,iso2,zoom", help="comma list of top,iso,iso2,zoom")
    ap.add_argument("--zoom", action="append", type=_parse_zoom, default=[], metavar="X,Z,R[,AZ]",
                    help="zoom target (repeatable); default: first base slot")
    ap.add_argument("--size", type=int, default=1600, help="output width in pixels")
    ap.add_argument("--ss", type=int, default=2, help="supersampling factor")
    ap.add_argument("--elevation", type=float, default=ELEVATION_DEG)
    ap.add_argument("--bounds", type=_parse_bounds, help="frame xmin,zmin,xmax,zmax instead of auto")
    ap.add_argument("--frame", choices=("auto", "all"), default="auto",
                    help="auto: frame the play area (ignores water and outlying slabs); all: everything")
    ap.add_argument("--zoom-cull", type=float, default=2.0,
                    help="zoom: hide parts farther than radius*FACTOR from the centre (0 = off)")
    ap.add_argument("--no-outlines", action="store_true")
    ap.add_argument("--no-labels", action="store_true")
    # Allow "--zoom -57,-57,30" (argparse would read the value as an option).
    argv = list(sys.argv[1:] if argv is None else argv)
    for i in range(len(argv) - 1):
        if argv[i] in ("--zoom", "--bounds") and argv[i + 1].startswith("-"):
            argv[i : i + 2] = [f"{argv[i]}={argv[i + 1]}", ""]
    args = ap.parse_args([a for a in argv if a != ""])

    with open(args.parts_json, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    os.makedirs(args.out_dir, exist_ok=True)

    t0 = time.time()
    scene = Scene(data)
    print(f"[render] {len(scene.parts)} parts -> {len(scene.count)} faces ({time.time() - t0:.2f}s)")

    views = [v.strip() for v in args.views.split(",") if v.strip()]
    for view in views:
        if view not in ("top", "iso", "iso2", "zoom"):
            sys.exit(f"unknown view: {view}")

    def save(name, im, started):
        path = os.path.join(args.out_dir, name)
        im.save(path)
        print(f"[render] {name:10s} {im.size[0]}x{im.size[1]} ({time.time() - started:.2f}s) -> {path}")

    for view in views:
        t = time.time()
        if view == "top":
            save("top.png", view_top(scene, args), t)
        elif view == "iso":
            save("iso.png", view_orbit(scene, args, 45.0, "ISO"), t)
        elif view == "iso2":
            save("iso2.png", view_orbit(scene, args, 225.0, "ISO2"), t)
        elif view == "zoom":
            targets = list(args.zoom)
            if not targets:
                if scene.slots:
                    p = scene.slots[0]["cf"]
                    targets = [[p[0], p[2], 40.0]]
                else:
                    lo, hi = scene.frame_box(args.frame)
                    c = (lo + hi) / 2
                    targets = [[c[0], c[2], max(float((hi - lo)[[0, 2]].max()) / 4, 10.0)]]
            for n, target in enumerate(targets, 1):
                t = time.time()
                x, z, radius = target[:3]
                az = target[3] if len(target) > 3 else 45.0
                save(f"zoom_{n}.png", view_zoom(scene, args, x, z, radius, az), t)
    print(f"[render] done in {time.time() - t0:.2f}s")


if __name__ == "__main__":
    main()
