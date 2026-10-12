#!/usr/bin/env python3
"""Preview renderer for parts exported by export_parts.luau.

Renders PNG previews of a Roblox place (no Studio needed):

  top    top-down map (looking down -Y, +X right, +Z down) with a stud grid
  iso    3D view from azimuth 45 deg (camera in the +X/+Z quadrant)
  iso2   3D view from azimuth 225 deg (camera in the -X/-Z quadrant)
  zoom   iso view around (x, z) with a radius; one image per --zoom argument
  persp  perspective "player eye" view with sky and distance fog; one image per
         --persp eye/target (or 6 automatic views with --persp-preset ring)

The first four are orthographic.

Usage:
  python3 tools/preview/render.py parts.json --out-dir out/ \
      [--views top,iso,iso2,zoom] [--zoom x,z,radius[,azimuth]]... [--size 1600]
  python3 tools/preview/render.py parts.json --out-dir out/ --terrain smoothgrid.bin \
      --persp ex,ey,ez,tx,ty,tz[,fov]... | --persp-preset ring
  (see --help and tools/preview/README.md for all options)

Rendering is a small numpy z-buffer rasterizer: every part becomes a convex
polygon mesh, back faces are culled and opaque faces are depth tested. The nearest
transparent surface in front of them (glass, water) is then blended once per pixel.
Images are supersampled and box-filtered down for anti-aliasing; thin dark outlines
come from edges in the per-pixel face-id buffer. The perspective view uses the same
passes on frustum-culled faces clipped at the near plane, with -1/distance as the
depth (linear in screen space).
"""

from __future__ import annotations

import argparse
import copy
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

# Smooth terrain (--terrain): colour per Roblox terrain material.
TERRAIN_COLORS = {
    "Grass": (90, 170, 60),
    "LeafyGrass": (80, 150, 50),
    "Sand": (230, 210, 150),
    "Rock": (120, 120, 125),
    "Slate": (100, 100, 110),
    "Ground": (130, 100, 70),
    "Mud": (90, 70, 50),
    "Snow": (245, 248, 255),
    "Glacier": (200, 230, 250),
    "Cobblestone": (160, 160, 155),
    "Pavement": (170, 170, 165),
    "Basalt": (60, 60, 65),
    "Sandstone": (200, 160, 110),
    "Limestone": (220, 215, 190),
    "Salt": (236, 236, 230),
    "Asphalt": (65, 65, 70),
    "Concrete": (175, 175, 170),
    "Brick": (165, 85, 65),
    "WoodPlanks": (160, 120, 75),
    "Ice": (175, 215, 245),
    "CrackedLava": (215, 90, 40),
    "Water": tuple(int(c) for c in WATER_COLOR),
}
TERRAIN_QUAD_PX = 5.0  # auto LOD: coarsest quad size (4, 8, 16... studs) still >= this many px
TERRAIN_JITTER = 0.04  # +- per-column brightness variation (reads as texture)
TERRAIN_SKIRT_SHADE = 0.8  # colour multiplier of the vertical walls at the terrain's edges


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
        self.face_water = water[owner]
        self.part_opacity = opacity
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
# Smooth terrain: a heightfield (terrain_export.py) turned into faces.
# --------------------------------------------------------------------------------------


def _shade(normal, color):
    """Same lighting as Scene: ambient + half-Lambert towards SUN."""
    shade = AMBIENT + (1 - AMBIENT) * (0.5 + 0.5 * (normal @ SUN))
    return (color * shade[:, None]).clip(0, 255).astype(np.float32)


def _pad_poly(pts):
    """(N, k, 3) polygons -> (N, MAX_POLY, 3) by repeating the last vertex."""
    k = pts.shape[1]
    return np.concatenate([pts, np.repeat(pts[:, -1:, :], MAX_POLY - k, axis=1)], axis=1)


def _row_runs(mask, key):
    """Horizontal runs of `mask` cells with equal `key`: arrays (row, col0, col1_exclusive)."""
    nx = mask.shape[1]
    same = np.zeros_like(mask)
    same[:, 1:] = mask[:, 1:] & mask[:, :-1] & (key[:, 1:] == key[:, :-1])
    flat_mask, flat_same = mask.ravel(), same.ravel()
    starts = np.nonzero(flat_mask & ~flat_same)[0]
    breaks = np.append(np.nonzero(~flat_same)[0], flat_mask.size)
    ends = breaks[np.searchsorted(breaks, starts, side="right")]
    return starts // nx, starts % nx, starts % nx + (ends - starts)


def _block_reduce(a, f, fill):
    """(nz, nx) -> (ceil(nz/f), f, ceil(nx/f), f) view padded with `fill`."""
    nz, nx = a.shape
    a = np.pad(a, ((0, (-nz) % f), (0, (-nx) % f)), constant_values=fill)
    return a.reshape(a.shape[0] // f, f, a.shape[1] // f, f)


class TerrainField:
    """Column heightfield of the terrain (see terrain_export.py) and its meshes.

    The surface is drawn smooth: every corner of the column grid takes the mean top
    of the (up to four) columns around it, each column becomes two triangles (flat
    columns are merged into row quads), and vertical walls close the terrain where
    it ends. Water is a translucent sheet at its surface height (with walls at its
    edges). Coarser levels of detail average 2x2, 4x4... columns.
    """

    def __init__(self, hf):
        self.origin = np.asarray(hf["origin"], float)
        self.step = float(hf["step"])
        self.top = np.asarray(hf["top"], np.float32)
        self.bottom = np.asarray(hf["bottom"], np.float32)
        self.water = np.asarray(hf["water"], np.float32)
        self.material = np.asarray(hf["material"], np.int16)
        names = list(hf["materials"])
        self.palette = np.array([TERRAIN_COLORS.get(n, (200, 0, 200)) for n in names], np.float32)
        self.columns = int(np.isfinite(self.top).sum())
        self.wet_columns = int(np.isfinite(self.water).sum())
        self._cache = {}

    @property
    def empty(self):
        return self.columns == 0 and self.wet_columns == 0

    def bounds(self):
        """World AABB (lo, hi) of the columns holding terrain or water."""
        used = np.isfinite(self.top) | np.isfinite(self.water)
        rows, cols = np.nonzero(used.any(1))[0], np.nonzero(used.any(0))[0]
        ox, oz, s = self.origin[0], self.origin[1], self.step
        heights = np.concatenate([self.top[np.isfinite(self.top)], self.water[np.isfinite(self.water)]])
        floor = self.bottom[np.isfinite(self.bottom)]
        ylo = float(floor.min()) if len(floor) else float(heights.min())
        lo = np.array([ox + cols[0] * s, ylo, oz + rows[0] * s])
        hi = np.array([ox + (cols[-1] + 1) * s, float(heights.max()), oz + (rows[-1] + 1) * s])
        return lo, hi

    def surface_near(self, x, z, radius):
        """Visible surface heights (top or water, whichever is higher) of the columns
        whose centres lie within `radius` of (x, z)."""
        s = self.step
        nz, nx = self.top.shape
        cx = self.origin[0] + (np.arange(nx) + 0.5) * s
        cz = self.origin[1] + (np.arange(nz) + 0.5) * s
        inside = (cx[None, :] - x) ** 2 + (cz[:, None] - z) ** 2 <= radius**2
        surf = np.fmax(self.top, self.water)
        return surf[inside & np.isfinite(surf)]

    def lod(self, px_per_stud, forced=None):
        """Quad size in studs: `forced` (rounded to a multiple of the column size), or
        the smallest power-of-two multiple of the column size whose quads cover at
        least TERRAIN_QUAD_PX output pixels (finer detail would not be visible)."""
        if forced:
            return self.step * max(1, round(float(forced) / self.step))
        step = self.step
        while step * px_per_stud < TERRAIN_QUAD_PX and step < 64:
            step *= 2
        return step

    def _level(self, step, crop):
        """Heightfield arrays at `step` studs per column, optionally cropped to the
        XZ rectangle crop=(xmin, zmin, xmax, zmax)."""
        f = max(1, round(step / self.step))
        top, bottom, water, material = self.top, self.bottom, self.water, self.material
        ox, oz = self.origin
        if crop is not None:
            nz, nx = top.shape
            ix0 = int(np.clip(np.floor((crop[0] - ox) / self.step / f) * f, 0, nx))
            ix1 = int(np.clip(np.ceil((crop[2] - ox) / self.step / f) * f, 0, nx))
            iz0 = int(np.clip(np.floor((crop[1] - oz) / self.step / f) * f, 0, nz))
            iz1 = int(np.clip(np.ceil((crop[3] - oz) / self.step / f) * f, 0, nz))
            top, bottom = top[iz0:iz1, ix0:ix1], bottom[iz0:iz1, ix0:ix1]
            water, material = water[iz0:iz1, ix0:ix1], material[iz0:iz1, ix0:ix1]
            ox, oz = ox + ix0 * self.step, oz + iz0 * self.step
        if f > 1 and top.size:
            t = _block_reduce(top, f, np.nan)
            fin = np.isfinite(t)
            n = fin.sum((1, 3))
            with np.errstate(invalid="ignore", divide="ignore"):
                top_d = np.where(fin, t, 0).sum((1, 3)) / n
            top_d = np.where(n > 0, top_d, np.nan).astype(np.float32)
            b = _block_reduce(bottom, f, np.inf).min((1, 3))
            bottom = np.where(np.isfinite(b), b, np.nan).astype(np.float32)
            w = _block_reduce(water, f, -np.inf).max((1, 3))
            water = np.where(np.isfinite(w), w, np.nan).astype(np.float32)
            m = _block_reduce(material, f, -1)
            best = np.full(top_d.shape, -1, np.int16)
            best_n = np.zeros(top_d.shape, int)
            for slot in np.unique(m[m >= 0]):
                cnt = (m == slot).sum((1, 3))
                better = cnt > best_n
                best[better], best_n[better] = slot, cnt[better]
            top, material = top_d, best
        return np.array([ox, oz]), f * self.step, top, bottom, water, material

    def mesh(self, step, crop=None, hole=None, match=None):
        """Faces of the terrain at `step` studs per quad (the last four are cached).

        crop=(xmin, zmin, xmax, zmax) limits the mesh to that rectangle; hole=(...)
        leaves out the surface of the columns inside that rectangle (it must be aligned
        to this level's quads), so a finer level can fill it; solid terrain gets walls
        (skirts) along the hole's edge. match=STUDS makes the corners on the edge of
        `crop` follow the surface of that coarser level (which has the hole), so the
        two levels meet without cracks."""

        def rect(r):
            return None if r is None else tuple(round(float(c), 3) for c in r)

        key = (float(step), rect(crop), rect(hole), match)
        if key not in self._cache:
            while len(self._cache) >= 4:
                self._cache.pop(next(iter(self._cache)))
            self._cache[key] = self._build(step, crop, hole, match)
        return self._cache[key]

    def _corner_heights(self, top):
        """Grid-corner heights: mean top of the present columns around each corner."""
        T = np.pad(top, 1, constant_values=np.nan)
        around = np.stack([T[:-1, :-1], T[:-1, 1:], T[1:, :-1], T[1:, 1:]])
        fin = np.isfinite(around)
        n = fin.sum(0)
        with np.errstate(invalid="ignore", divide="ignore"):
            V = np.where(fin, around, 0).sum(0) / n
        return V.astype(np.float64)

    def _match_edges(self, V, origin, s, coarse):
        """Corners on the outer edge of a cropped level take the surface height of the
        `coarse` level there (bilinear in its corner grid = linear along its quad
        edges), so the finer level ends exactly on the coarser level's surface."""
        nz1, nx1 = V.shape
        x0, z0 = origin
        x1, z1 = x0 + (nx1 - 1) * s, z0 + (nz1 - 1) * s
        corg, cs, ctop, _, _, _ = self._level(coarse, (x0 - coarse, z0 - coarse, x1 + coarse, z1 + coarse))
        if ctop.size == 0:
            return V
        Vc = self._corner_heights(ctop)
        edge = np.zeros(V.shape, bool)
        edge[0, :] = edge[-1, :] = edge[:, 0] = edge[:, -1] = True
        a, b = np.nonzero(edge)
        u = (x0 + b * s - corg[0]) / cs
        v = (z0 + a * s - corg[1]) / cs
        j0 = np.clip(np.floor(u).astype(int), 0, Vc.shape[1] - 2)
        i0 = np.clip(np.floor(v).astype(int), 0, Vc.shape[0] - 2)
        fu, fv = np.clip(u - j0, 0, 1), np.clip(v - i0, 0, 1)
        h = (
            Vc[i0, j0] * (1 - fu) * (1 - fv)
            + Vc[i0, j0 + 1] * fu * (1 - fv)
            + Vc[i0 + 1, j0] * (1 - fu) * fv
            + Vc[i0 + 1, j0 + 1] * fu * fv
        )
        out = V.copy()
        out[a, b] = np.where(np.isfinite(h) & np.isfinite(V[a, b]), h, V[a, b])
        return out

    def sample_points(self, step=16.0):
        """Mesh vertices at a coarse level (for framing the 3D views)."""
        m = self.mesh(max(step, self.step))
        return m["poly"][:, :4, :].reshape(-1, 3) if len(m["poly"]) else np.zeros((0, 3))

    def _build(self, step, crop, hole=None, match=None):
        origin, s, top, bottom, water, material = self._level(step, crop)
        nz, nx = top.shape
        polys, colors, kinds, outward = [], [], [], []  # per batch: (N, MAX_POLY, 3), ...
        counts = []
        X = origin[0] + np.arange(nx + 1) * s
        Z = origin[1] + np.arange(nz + 1) * s
        solid = np.isfinite(top)
        mat = np.where(material >= 0, material, 0)
        # Columns that get surface faces (all but those inside `hole`).
        keep = np.ones((nz, nx), bool)
        if hole is not None:
            cx, cz = (X[:-1] + X[1:]) / 2, (Z[:-1] + Z[1:]) / 2
            keep = ~(
                ((cx > hole[0]) & (cx < hole[2]))[None, :] & ((cz > hole[1]) & (cz < hole[3]))[:, None]
            )

        # Corner heights: mean top of the present columns around each corner.
        V = self._corner_heights(top)
        if match is not None and crop is not None and top.size:
            V = self._match_edges(V, origin, s, float(match))

        jz, jx = np.indices((nz, nx))
        jitter = 1 + TERRAIN_JITTER * (((jx * 73856093) ^ (jz * 19349663)) % 1009 / 504.0 - 1)
        base_color = self.palette[mat] * jitter[..., None]

        v00, v10, v01, v11 = V[:-1, :-1], V[:-1, 1:], V[1:, :-1], V[1:, 1:]
        flat = solid & (np.maximum.reduce([v00, v10, v01, v11]) - np.minimum.reduce([v00, v10, v01, v11]) < 1e-3)

        # Flat columns: merged row quads.
        if (flat & keep).any():
            key = np.where(flat, np.round(np.nan_to_num(v00) * 1000).astype(np.int64) * 32 + mat, -1)
            r, c0, c1 = _row_runs(flat & keep, key)
            y = v00[r, c0]
            quad = np.stack(
                [
                    np.stack([X[c0], y, Z[r]], 1),
                    np.stack([X[c1], y, Z[r]], 1),
                    np.stack([X[c1], y, Z[r + 1]], 1),
                    np.stack([X[c0], y, Z[r + 1]], 1),
                ],
                1,
            )
            polys.append(_pad_poly(quad))
            counts.append(np.full(len(r), 4))
            colors.append(base_color[r, c0])
            kinds.append(np.zeros(len(r), np.int8))
            outward.append(np.tile([0.0, 1.0, 0.0], (len(r), 1)))

        # One-column ridges and channels (higher or lower than both neighbours along x
        # or z): a fan of four triangles through the column centre at its exact
        # height, so they keep their true height instead of being averaged away.
        # Cliff edges are not extrema and stay smooth (no saw-tooth rims).
        mean = (v00 + v10 + v01 + v11) / 4
        tc = top.astype(np.float64)
        Tq = np.pad(tc, 1, constant_values=np.nan)
        extremum = np.zeros_like(solid)
        for a, b in ((Tq[1:-1, :-2], Tq[1:-1, 2:]), (Tq[:-2, 1:-1], Tq[2:, 1:-1])):
            a, b = np.where(np.isfinite(a), a, tc), np.where(np.isfinite(b), b, tc)
            extremum |= (tc > np.maximum(a, b) + 0.5) | (tc < np.minimum(a, b) - 0.5)
        fan = solid & ~flat & extremum & (np.abs(top - mean) > 0.25) & keep
        i, j = np.nonzero(fan)
        if len(i):
            p00 = np.stack([X[j], v00[i, j], Z[i]], 1)
            p10 = np.stack([X[j + 1], v10[i, j], Z[i]], 1)
            p01 = np.stack([X[j], v01[i, j], Z[i + 1]], 1)
            p11 = np.stack([X[j + 1], v11[i, j], Z[i + 1]], 1)
            pc = np.stack([X[j] + s / 2, top[i, j].astype(np.float64), Z[i] + s / 2], 1)
            for pa, pb in ((p00, p10), (p10, p11), (p11, p01), (p01, p00)):
                polys.append(_pad_poly(np.stack([pa, pb, pc], 1)))
                counts.append(np.full(len(i), 3))
                colors.append(base_color[i, j])
                kinds.append(np.zeros(len(i), np.int8))
                outward.append(np.tile([0.0, 1.0, 0.0], (len(i), 1)))

        # Other sloped columns: two triangles, split along the flatter diagonal.
        i, j = np.nonzero(solid & ~flat & ~fan & keep)
        if len(i):
            p00 = np.stack([X[j], v00[i, j], Z[i]], 1)
            p10 = np.stack([X[j + 1], v10[i, j], Z[i]], 1)
            p01 = np.stack([X[j], v01[i, j], Z[i + 1]], 1)
            p11 = np.stack([X[j + 1], v11[i, j], Z[i + 1]], 1)
            diag = (np.abs(v00 - v11) <= np.abs(v10 - v01))[i, j][:, None, None]
            t1 = np.where(diag, np.stack([p00, p10, p11], 1), np.stack([p00, p10, p01], 1))
            t2 = np.where(diag, np.stack([p00, p11, p01], 1), np.stack([p10, p11, p01], 1))
            polys += [_pad_poly(t1), _pad_poly(t2)]
            counts += [np.full(len(i), 3)] * 2
            colors += [base_color[i, j]] * 2
            kinds += [np.zeros(len(i), np.int8)] * 2
            outward += [np.tile([0.0, 1.0, 0.0], (len(i), 1))] * 2

        # Walls where the terrain ends (no column next to it), and skirts (surface
        # colour) along the edge of a hole that a finer level fills.
        Sp = np.pad(solid & keep, 1, constant_values=False)
        Hp = np.pad(solid & ~keep, 1, constant_values=False)
        floor = np.where(np.isfinite(bottom), bottom, top)
        walls = (
            # (neighbour present, neighbour in hole, edge corner a, edge corner b, outward)
            (Sp[:-2, 1:-1], Hp[:-2, 1:-1], (0, 0), (0, 1), (0.0, 0.0, -1.0)),  # -Z edge
            (Sp[2:, 1:-1], Hp[2:, 1:-1], (1, 0), (1, 1), (0.0, 0.0, 1.0)),  # +Z edge
            (Sp[1:-1, :-2], Hp[1:-1, :-2], (0, 0), (1, 0), (-1.0, 0.0, 0.0)),  # -X edge
            (Sp[1:-1, 2:], Hp[1:-1, 2:], (0, 1), (1, 1), (1.0, 0.0, 0.0)),  # +X edge
        )
        for neighbour, in_hole, a, b, out in walls:
            i, j = np.nonzero(solid & keep & ~neighbour)
            if not len(i):
                continue
            shade = np.where(in_hole[i, j], 1.0, TERRAIN_SKIRT_SHADE)[:, None]
            ya, yb, yf = V[i + a[0], j + a[1]], V[i + b[0], j + b[1]], floor[i, j].astype(np.float64)
            pa = np.stack([X[j + a[1]], ya, Z[i + a[0]]], 1)
            pb = np.stack([X[j + b[1]], yb, Z[i + b[0]]], 1)
            qb = np.stack([X[j + b[1]], np.minimum(yf, yb - 0.01), Z[i + b[0]]], 1)
            qa = np.stack([X[j + a[1]], np.minimum(yf, ya - 0.01), Z[i + a[0]]], 1)
            polys.append(_pad_poly(np.stack([pa, pb, qb, qa], 1)))
            counts.append(np.full(len(i), 4))
            colors.append(base_color[i, j] * shade)
            kinds.append(np.zeros(len(i), np.int8))
            outward.append(np.tile(out, (len(i), 1)))

        # Water: sheets at the surface (merged along rows), walls at open edges.
        wet = np.isfinite(water) & ~(water < np.where(solid, top, -np.inf) - 0.05)
        if (wet & keep).any():
            level = np.where(wet, np.round(water.astype(np.float64), 2), np.nan)
            r, c0, c1 = _row_runs(wet & keep, np.where(wet, np.round(level * 100), 0).astype(np.int64))
            y = level[r, c0]
            quad = np.stack(
                [
                    np.stack([X[c0], y, Z[r]], 1),
                    np.stack([X[c1], y, Z[r]], 1),
                    np.stack([X[c1], y, Z[r + 1]], 1),
                    np.stack([X[c0], y, Z[r + 1]], 1),
                ],
                1,
            )
            polys.append(_pad_poly(quad))
            counts.append(np.full(len(r), 4))
            colors.append(np.tile(WATER_COLOR, (len(r), 1)))
            kinds.append(np.ones(len(r), np.int8))
            outward.append(np.tile([0.0, 1.0, 0.0], (len(r), 1)))
            Wp = np.pad(wet, 1, constant_values=False)
            Tp = np.pad(np.where(solid, top, -np.inf), 1, constant_values=-np.inf)
            sides = (
                (Wp[:-2, 1:-1], Tp[:-2, 1:-1], (0, 0), (0, 1), (0.0, 0.0, -1.0)),
                (Wp[2:, 1:-1], Tp[2:, 1:-1], (1, 0), (1, 1), (0.0, 0.0, 1.0)),
                (Wp[1:-1, :-2], Tp[1:-1, :-2], (0, 0), (1, 0), (-1.0, 0.0, 0.0)),
                (Wp[1:-1, 2:], Tp[1:-1, 2:], (0, 1), (1, 1), (1.0, 0.0, 0.0)),
            )
            for nwet, ntop, a, b, out in sides:
                i, j = np.nonzero(wet & keep & ~nwet & (ntop < level - 0.05))
                if not len(i):
                    continue
                y = level[i, j]
                lowest = np.where(solid[i, j], top[i, j], np.where(np.isfinite(bottom[i, j]), bottom[i, j], y - 4))
                lowest = np.minimum(lowest.astype(np.float64), y - 0.01)
                pa = np.stack([X[j + a[1]], y, Z[i + a[0]]], 1)
                pb = np.stack([X[j + b[1]], y, Z[i + b[0]]], 1)
                qb = np.stack([X[j + b[1]], lowest, Z[i + b[0]]], 1)
                qa = np.stack([X[j + a[1]], lowest, Z[i + a[0]]], 1)
                polys.append(_pad_poly(np.stack([pa, pb, qb, qa], 1)))
                counts.append(np.full(len(i), 4))
                colors.append(np.tile(WATER_COLOR, (len(i), 1)))
                kinds.append(np.ones(len(i), np.int8))
                outward.append(np.tile(out, (len(i), 1)))

        if not polys:
            return {"poly": np.zeros((0, MAX_POLY, 3)), "count": np.zeros(0, int), "step": s}
        poly = np.concatenate(polys)
        kind = np.concatenate(kinds)
        out = np.concatenate(outward)
        normal = _newell(poly)
        normal[np.einsum("ni,ni->n", normal, out) < 0] *= -1
        count = np.concatenate(counts)
        color = np.concatenate(colors).astype(np.float32)
        centroid = np.where((count == 4)[:, None], poly[:, :4].mean(1), poly[:, :3].mean(1))
        return {
            "poly": poly,
            "count": count,
            "normal": normal,
            "centroid": centroid,
            "rgb": _shade(normal, color),
            "water": kind == 1,
            "step": s,
        }


def with_terrain(scene, mesh):
    """A shallow copy of `scene` whose face arrays also hold the terrain faces (after the
    part faces, so face indices of parts are unchanged)."""
    if mesh is None or len(mesh["poly"]) == 0:
        return scene
    out = copy.copy(scene)
    n = len(mesh["poly"])
    gbase = int(scene.group.max()) + 1 if len(scene.group) else 0
    out.poly = np.concatenate([scene.poly, mesh["poly"]])
    out.count = np.concatenate([scene.count, mesh["count"]])
    out.normal = np.concatenate([scene.normal, mesh["normal"]])
    out.centroid = np.concatenate([scene.centroid, mesh["centroid"]])
    # One outline group for land and one for water: outlines only at silhouettes.
    out.group = np.concatenate([scene.group, np.where(mesh["water"], gbase + 1, gbase).astype(np.int32)])
    out.face_rgb = np.concatenate([scene.face_rgb, mesh["rgb"]])
    out.face_opacity = np.concatenate(
        [scene.face_opacity, np.where(mesh["water"], WATER_OPACITY, 1.0).astype(np.float32)]
    )
    out.face_bias = np.concatenate([scene.face_bias, np.zeros(n)])
    out.face_water = np.concatenate([scene.face_water, mesh["water"]])
    return out


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
        # Edge functions in coordinates local to each face's bounding box: small
        # float32 values keep shared edges watertight (no pixel gaps between the
        # triangles of a terrain mesh, even far from the image origin).
        xs = g[None, None, :]  # (1, 1, T) pixel centres
        ys = g[None, :, None]  # (1, T, 1)
        inside = (xs < (self.x1[faces] - x0)[:, None, None]) & (ys < (self.y1[faces] - y0)[:, None, None])
        sign = self.sign[faces]
        cnt = self.count[faces]
        rows = np.arange(len(faces))
        vx, vy = self.px[faces] - x0[:, None], self.py[faces] - y0[:, None]
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


# Colour grading of the place (its ColorCorrectionEffect, exported by export_parts.luau), applied
# to every rendered image so previews show the colours Studio shows. None = no grading.
GRADE = None


def apply_grade(im, grade):
    """Approximates Roblox's ColorCorrectionEffect: brightness, contrast, saturation, tint."""
    c = np.asarray(im, np.float32) / 255.0
    c = c + grade.get("brightness", 0.0)
    c = (c - 0.5) * (1.0 + grade.get("contrast", 0.0)) + 0.5
    lum = c @ np.array([0.299, 0.587, 0.114], np.float32)
    c = lum[..., None] + (c - lum[..., None]) * (1.0 + grade.get("saturation", 0.0))
    c = c * (np.array(grade.get("tint", [255, 255, 255]), np.float32) / 255.0)
    return Image.fromarray((c.clip(0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def to_image(buf, ss):
    """Box-filter the supersampled buffer down to the output size (copies the data)."""
    im = Image.fromarray(buf, "RGB")
    im = im.reduce(ss) if ss > 1 else im.copy()
    return apply_grade(im, GRADE) if GRADE else im


# --------------------------------------------------------------------------------------
# Perspective ("player eye") camera and renderer
# --------------------------------------------------------------------------------------

PERSP_FOV = 70.0  # default vertical field of view (Roblox default camera)
PERSP_ASPECT = 9 / 16  # image height / width
NEAR_PLANE = 0.3  # studs; polygons are clipped here
FAR_PLANE = 30000.0  # faces entirely farther away are dropped
GUARD_BAND = 2.0  # polygons are clipped to GUARD_BAND x the view frustum (keeps coords small)
SKY_HORIZON = np.array([212, 229, 244], np.float32)
SKY_ZENITH = np.array([84, 142, 218], np.float32)
FOG_START, FOG_END = 300.0, 1500.0  # fog starts at START, is 90% at END (studs)
FOG_TINT = None  # (weight, rgb) from the place's Atmosphere (set in main)


def atmosphere_fog(atm):
    """Fog distances and tint from a Roblox Atmosphere (rough fit: denser/hazier = closer fog)."""
    density, haze = max(atm.get("density", 0.3), 0.02), atm.get("haze", 0.0)
    end = min(max(1500.0 * (0.25 / density) / (1.0 + 1.5 * haze), 400.0), 4000.0)
    tint = (min(0.25 + 0.5 * haze, 0.8), np.array(atm.get("color", [199, 199, 199]), np.float32))
    return (0.25 * end, end), tint
OUTLINE_FADE = (60.0, 400.0)  # outlines fade from full strength to none over this distance
WATER_FRESNEL = 0.85  # extra opacity / sky reflection of water at grazing angles


class PerspCamera:
    """Pinhole camera at `eye` looking at `target` (no roll), vertical FOV in degrees."""

    def __init__(self, eye, target, fov_deg, width, height, ss):
        self.eye = np.asarray(eye, float)
        self.target = np.asarray(target, float)
        f = self.target - self.eye
        f = f / np.linalg.norm(f) if np.linalg.norm(f) > 1e-9 else np.array([0.0, 0, -1])
        r = np.cross(f, (0.0, 1.0, 0.0))
        if np.linalg.norm(r) < 1e-6:  # looking straight up/down: +X right
            r = np.array([1.0, 0, 0])
        r /= np.linalg.norm(r)
        self.f, self.r, self.u = f, r, np.cross(r, f)
        self.fov = float(fov_deg)
        self.width, self.height, self.ss = width, height, ss
        self.tan_v = math.tan(math.radians(self.fov) / 2)
        self.tan_h = self.tan_v * width / height

    def focal(self, ss=None):
        """Focal length in pixels (at supersampling `ss`, default the camera's)."""
        return self.height * (self.ss if ss is None else ss) / 2 / self.tan_v

    @property
    def heading(self):
        """Azimuth of the view direction in degrees (0 = +Z, 90 = +X)."""
        return math.degrees(math.atan2(self.f[0], self.f[2])) % 360

    @property
    def pitch(self):
        return math.degrees(math.asin(max(-1.0, min(1.0, self.f[1]))))

    def project(self, pts, ss=None):
        """World points (..., 3) -> pixel x, y and view depth (distance along the view axis)."""
        ss = self.ss if ss is None else ss
        rel = np.asarray(pts, float) - self.eye
        x, y, z = rel @ self.r, rel @ self.u, rel @ self.f
        fp = self.focal(ss)
        with np.errstate(divide="ignore", invalid="ignore"):
            px = self.width * ss / 2 + fp * x / z
            py = self.height * ss / 2 - fp * y / z
        return px, py, z


def _clip_polys(V, count, s):
    """Clip convex polygons to the half-space s >= 0 (Sutherland-Hodgman, vectorized).

    V: (M, K, 3) vertices padded by repeating the last one, count: (M,) vertex counts,
    s: (M, K) signed distances of the vertices. Returns the clipped vertices (same
    padding, at most count + 1 of them, so K must exceed the largest count) and counts
    (< 3 = nothing left)."""
    M, K, _ = V.shape
    j = np.arange(K)[None, :]
    nxt = np.where(j + 1 >= count[:, None], 0, j + 1)
    rows = np.arange(M)[:, None]
    Vn, sn = V[rows, nxt], s[rows, nxt]
    valid = j < count[:, None]
    cur_in, nxt_in = s >= 0, sn >= 0
    cross = valid & (cur_in != nxt_in)
    with np.errstate(divide="ignore", invalid="ignore"):
        t = np.where(cross, s / (s - sn), 0.0)
    out = np.empty((M, 2 * K, 3))
    out[:, 0::2] = V
    out[:, 1::2] = V + t[..., None] * (Vn - V)
    ok = np.empty((M, 2 * K), bool)
    ok[:, 0::2] = valid & cur_in
    ok[:, 1::2] = cross
    order = np.argsort(~ok, axis=1, kind="stable")[:, :K]  # valid entries first, in order
    n = ok.sum(1)
    pick = np.take_along_axis(order, np.minimum(j, np.maximum(n - 1, 0)[:, None]), 1)
    return np.take_along_axis(out, pick[..., None], 1), n


def _persp_faces(scene, cam, W, H, fp):
    """Front faces inside the view frustum, clipped to the near plane and a guard band,
    projected to (supersampled) pixels. Returns (faces, px, py, count, A, B, C, nc):
    original face indices, padded pixel polygons, vertex counts, the screen-space
    depth plane depth = A*x + B*y + C (depth = -1/t, t = distance along the view axis,
    smaller = closer, linear in screen space) and the camera-space normals."""
    eye = cam.eye
    k = np.einsum("ni,ni->n", scene.normal, scene.centroid - eye)  # < 0: eye in front
    faces = np.nonzero((k < -1e-3) & (scene.face_opacity > 0))[0]
    rel = scene.poly[faces] - eye
    x, y, z = rel @ cam.r, rel @ cam.u, rel @ cam.f
    tx, ty = cam.tan_h, cam.tan_v
    outside = (
        (z < NEAR_PLANE).all(1)
        | (z > FAR_PLANE).all(1)
        | (x > z * tx).all(1)
        | (-x > z * tx).all(1)
        | (y > z * ty).all(1)
        | (-y > z * ty).all(1)
    )
    inside = np.nonzero(~outside)[0]
    faces, x, y, z = faces[inside], x[inside], y[inside], z[inside]
    count = scene.count[faces].astype(np.int64)

    # Clip: near plane, then the four guard-band planes (each adds at most one vertex).
    gx, gy = GUARD_BAND * tx, GUARD_BAND * ty
    planes = ((0, 0, 1, -NEAR_PLANE), (-1, 0, gx, 0), (1, 0, gx, 0), (0, -1, gy, 0), (0, 1, gy, 0))
    K = MAX_POLY + len(planes)
    V = np.empty((len(faces), K, 3))
    V[:, :MAX_POLY] = np.stack([x, y, z], -1)
    V[:, MAX_POLY:] = V[:, MAX_POLY - 1 : MAX_POLY]
    alive = np.ones(len(faces), bool)
    for plane in planes:
        s = V @ np.asarray(plane[:3], float) + plane[3]
        need = np.nonzero(alive & (s < 0).any(1))[0]
        if len(need):
            V[need], count[need] = _clip_polys(V[need], count[need], s[need])
            alive[need] = count[need] >= 3
    faces, V, count = faces[alive], V[alive], count[alive]

    px = W / 2 + fp * V[..., 0] / V[..., 2]
    py = H / 2 - fp * V[..., 1] / V[..., 2]
    n = scene.normal[faces]
    nc = np.stack([n @ cam.r, n @ cam.u, n @ cam.f], 1)
    kk = k[faces] - scene.face_bias[faces]  # Baseplate-sized parts pushed back slightly
    A = -nc[:, 0] / (fp * kk)
    B = nc[:, 1] / (fp * kk)
    C = -(nc[:, 2] - nc[:, 0] * W / (2 * fp) + nc[:, 1] * H / (2 * fp)) / kk
    return faces, px, py, count, A, B, C, nc


def _sky(sin_elevation):
    """Sky colour (..., 3) for view rays with the given sine of their elevation."""
    g = np.clip(sin_elevation / 0.6, 0, 1) ** 0.7
    return SKY_HORIZON + (SKY_ZENITH - SKY_HORIZON) * g[..., None]


def _fog_amount(dist, fog):
    """0 (clear) .. 1 (only fog) for distances in studs; fog = (start, end) or None."""
    if not fog:
        return np.zeros_like(dist)
    start, end = fog
    t = np.clip((dist - start) / max(end - start, 1e-6), 0, None)
    return 1 - np.exp(-2.3 * t**1.5)


def render_persp(scene, cam: PerspCamera, outlines=True, fog=(FOG_START, FOG_END)):
    """Rasterize the scene in perspective into a supersampled (H*ss, W*ss, 3) uint8 array.

    Same passes as render() (opaque z-buffer, then the nearest transparent surface
    blended once), with depth = -1/distance (linear in screen space). Background is a
    sky gradient; colours fade into the sky colour with distance (fog), outlines fade
    out with distance. Returns (image, info); info["zbuf"] is the opaque depth buffer
    (valid until the next render).
    """
    ss = cam.ss
    W, H = cam.width * ss, cam.height * ss
    fp = cam.focal(ss)
    faces, px, py, count, A, B, C, nc = _persp_faces(scene, cam, W, H, fp)

    x0 = np.floor(px.min(1)).clip(0, W).astype(np.int64)
    x1 = np.ceil(px.max(1)).clip(0, W).astype(np.int64)
    y0 = np.floor(py.min(1)).clip(0, H).astype(np.int64)
    y1 = np.ceil(py.max(1)).clip(0, H).astype(np.int64)
    area = (px * np.roll(py, -1, 1) - py * np.roll(px, -1, 1)).sum(1)
    sel = (x1 > x0) & (y1 > y0) & (np.abs(area) > 1e-9)
    sign = np.where(area > 0, 1.0, -1.0)

    raster = _Rasterizer(px, py, sign, A, B, C, count, x0, x1, y0, y1, W, H)
    opacity = scene.face_opacity[faces]
    opaque = np.nonzero(sel & (opacity >= 0.999))[0]
    transparent = np.nonzero(sel & (opacity < 0.999))[0]

    zbuf = _buffer("p_zbuf", (H, W), np.float32)
    zbuf.fill(np.inf)
    fidx = _buffer("p_fidx", (H, W), np.int32)
    fidx.fill(-1)
    _depth_pass(raster, opaque, zbuf, fidx)

    if outlines:  # where the visible smoothing group changes (sky = -1)
        groups = np.concatenate([[-1], scene.group[faces]]).astype(np.int32)
        ids = _buffer("p_ids", (H, W), np.int32)
        np.take(groups, fidx + 1, out=ids)
        edge = _buffer("p_edge", (H, W), bool)
        edge[:, -1] = False
        np.not_equal(ids[:, :-1], ids[:, 1:], out=edge[:, :-1])
        edge[:-1, :] |= ids[:-1, :] != ids[1:, :]
        edge &= ids >= 0

    if len(transparent):
        tz = _buffer("p_tz", (H, W), np.float32)
        tz.fill(np.inf)
        tf = _buffer("p_tf", (H, W), np.int32)
        tf.fill(-1)
        _depth_pass(raster, transparent, tz, tf, limit=zbuf)

    # Shade in row chunks: sky, face colour, outlines, transparent layer, fog.
    table = scene.face_rgb[faces].astype(np.float32)
    water = scene.face_water[faces] if hasattr(scene, "face_water") else np.zeros(len(faces), bool)
    X = ((np.arange(W, dtype=np.float32) + 0.5) - W / 2) / fp
    Yall = (H / 2 - (np.arange(H, dtype=np.float32) + 0.5)) / fp
    img = _buffer("p_img", (H, W, 3), np.uint8)
    fade0, fade1 = OUTLINE_FADE
    for r0 in range(0, H, 128):
        r1 = min(H, r0 + 128)
        Y = Yall[r0:r1, None]
        norm = np.sqrt(1 + X[None, :] ** 2 + Y**2)  # |ray| for a unit view-axis step
        sky = _sky((cam.f[1] + X[None, :] * cam.r[1] + Y * cam.u[1]) / norm)
        f_ = fidx[r0:r1]
        hit = f_ >= 0
        col = sky.copy()
        col[hit] = table[f_[hit]]
        dist = np.full(hit.shape, np.inf, np.float32)
        dist[hit] = -norm[hit] / zbuf[r0:r1][hit]
        if outlines:
            e = edge[r0:r1]
            if e.any():
                w = np.clip((fade1 - dist[e]) / (fade1 - fade0), 0, 1)
                col[e] *= (1 - (1 - OUTLINE_FACTOR) * w)[:, None]
        if len(transparent):
            t_ = tf[r0:r1]
            th = t_ >= 0
            if th.any():
                face = t_[th]
                a = opacity[face].astype(np.float32)
                rgb = table[face]
                wm = water[face]
                if wm.any():  # Fresnel: water turns opaque and reflects the sky at grazing angles
                    gx = np.broadcast_to(X[None, :], th.shape)[th]
                    gy = np.broadcast_to(Y, th.shape)[th]
                    cos = np.abs(nc[face, 0] * gx + nc[face, 1] * gy + nc[face, 2]) / norm[th]
                    F = np.where(wm, (1 - np.clip(cos, 0, 1)) ** 5 * WATER_FRESNEL, 0).astype(np.float32)
                    a = a + (1 - a) * F
                    rgb = rgb + (sky[th] - rgb) * (0.6 * F)[:, None]
                col[th] = col[th] * (1 - a)[:, None] + rgb * a[:, None]
                dist[th] = np.minimum(dist[th], -norm[th] / tz[r0:r1][th])
        fogged = np.isfinite(dist)
        if fog and fogged.any():
            f = _fog_amount(dist[fogged], fog)[:, None]
            target = sky[fogged]
            if FOG_TINT is not None:  # the place's Atmosphere colour, more of it with more haze
                target = target + (FOG_TINT[1] - target) * FOG_TINT[0]
            col[fogged] += (target - col[fogged]) * f
        img[r0:r1] = (col + 0.5).clip(0, 255).astype(np.uint8)
    info = {"zbuf": zbuf, "faces": int(sel.sum()), "total": len(scene.count)}
    return img, info


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


def _terrain_mesh(args, px_per_stud, crop=None):
    """Terrain faces for a view (None without --terrain) at the level of detail that
    suits `px_per_stud` final-image pixels per stud."""
    field = getattr(args, "terrain_field", None)
    if field is None or field.empty:
        return None
    return field.mesh(field.lod(px_per_stud, args.terrain_step), crop)


def _terrain_line(args, mesh):
    field = getattr(args, "terrain_field", None)
    if field is None:
        return []
    if mesh is None:
        return ["terrain: empty"]
    steps = "/".join(f"{st:g}" for st in mesh["steps"]) if "steps" in mesh else f"{mesh['step']:g}"
    line = (
        f"terrain: {field.columns} columns ({field.wet_columns} with water), "
        f"{steps}-stud quads, {len(mesh['poly'])} faces"
    )
    return [line]


def view_top(scene, args):
    lo, hi = _bounds(scene, args)
    center = (lo + hi) / 2
    center[1] = hi[1] + 10
    width, height, scale = _fit(hi[0] - lo[0], hi[2] - lo[2], args.size)
    cam = Camera.top(center, scale, width, height, args.ss)
    mesh = _terrain_mesh(args, scale)
    im = to_image(render(with_terrain(scene, mesh), cam, outlines=not args.no_outlines), args.ss)
    box = draw_title(
        im,
        [
            "TOP  (looking down -Y;  +X right, +Z down)",
            f"x {lo[0]:.0f}..{hi[0]:.0f}   z {lo[2]:.0f}..{hi[2]:.0f}   y {lo[1]:.0f}..{hi[1]:.0f}",
            _stats_line(scene),
        ]
        + _terrain_line(args, mesh),
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
    field = getattr(args, "terrain_field", None)
    if field is not None and not field.empty and not args.bounds:
        tp = field.sample_points()
        tp = tp[np.all((tp >= lo - 1e-3) & (tp <= hi + 1e-3), 1)]
        pts = np.concatenate([pts, tp]) if len(pts) else tp
    if args.bounds or len(pts) == 0:
        pts = np.array([[x, y, z] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
    rel = pts - center
    sx, sy = rel @ probe.r, rel @ probe.u
    # Re-centre on the projected box so it is not offset in the frame.
    center = center + probe.r * (sx.max() + sx.min()) / 2 + probe.u * (sy.max() + sy.min()) / 2
    width, height, scale = _fit(sx.max() - sx.min(), sy.max() - sy.min(), args.size)
    cam = Camera.orbit(azimuth, args.elevation, center, scale, width, height, args.ss)
    crop = (lo[0], lo[2], hi[0], hi[2]) if args.bounds else None
    mesh = _terrain_mesh(args, scale, crop)
    im = to_image(render(with_terrain(scene, mesh), cam, outlines=not args.no_outlines), args.ss)
    draw_axis_gizmo(im, cam)
    if not args.no_labels:
        draw_slot_labels(im, cam, scene)
    font = _font(15)
    _scale_bar(ImageDraw.Draw(im, "RGBA"), scale, (14, im.size[1] - 20), font)
    draw_title(
        im,
        [f"{title}  (orthographic, azimuth {azimuth:g} deg, elevation {args.elevation:g} deg)", _stats_line(scene)]
        + _terrain_line(args, mesh),
    )
    return im


def view_zoom(scene, args, x, z, radius, azimuth):
    # Keep parts whose XZ footprint is near the zoom disc so unrelated geometry in
    # front of it does not block the view (Baseplate-sized parts are always kept).
    # Terrain is cropped to the same square around the centre.
    keep_r = radius * args.zoom_cull if args.zoom_cull > 0 else float("inf")
    dx = np.maximum(np.maximum(scene.aabb_min[:, 0] - x, x - scene.aabb_max[:, 0]), 0)
    dz = np.maximum(np.maximum(scene.aabb_min[:, 2] - z, z - scene.aabb_max[:, 2]), 0)
    near = np.hypot(dx, dz) <= keep_r
    # Vertical centre: halfway between the floor (low percentile of the part tops and
    # terrain surface in the disc) and the tallest thing there, limited so tall things
    # don't push the floor out of the frame.
    inside = near & scene.content & (np.hypot(dx, dz) <= radius)
    tops = scene.aabb_max[inside, 1]
    field = getattr(args, "terrain_field", None)
    if field is not None and not field.empty:
        tops = np.concatenate([tops, field.surface_near(x, z, radius)])
    if len(tops):
        floor = float(np.percentile(tops, 10))
        y = (floor + min(float(tops.max()), floor + radius)) / 2
    else:
        y = 0.0

    face_filter = near[scene.owner]
    width = args.size
    height = int(round(args.size * 0.75))
    scale = width / (2 * radius)
    crop = None if math.isinf(keep_r) else (x - keep_r, z - keep_r, x + keep_r, z + keep_r)
    mesh = _terrain_mesh(args, scale, crop)
    if mesh is not None:
        face_filter = np.concatenate([face_filter, np.ones(len(mesh["poly"]), bool)])
    cam = Camera.orbit(azimuth, args.elevation, np.array([x, y, z]), scale, width, height, args.ss)
    im = to_image(
        render(with_terrain(scene, mesh), cam, outlines=not args.no_outlines, face_filter=face_filter), args.ss
    )
    draw_axis_gizmo(im, cam)
    if not args.no_labels:
        draw_slot_labels(im, cam, scene)
    _scale_bar(ImageDraw.Draw(im, "RGBA"), scale, (14, im.size[1] - 20), _font(15))
    draw_title(
        im,
        [
            f"ZOOM  centre ({x:g}, {y:.1f}, {z:g})  radius {radius:g}  azimuth {azimuth:g} deg",
            f"{int(near.sum())} of {len(scene.parts)} parts shown (cull radius {keep_r:g})",
        ]
        + _terrain_line(args, mesh),
    )
    return im


def _merge_meshes(meshes):
    """One terrain mesh dict from several (levels of detail)."""
    meshes = [m for m in meshes if m is not None and len(m["poly"])]
    if not meshes:
        return None
    out = {k: np.concatenate([m[k] for m in meshes]) for k in ("poly", "count", "normal", "centroid", "rgb", "water")}
    out["steps"] = sorted({float(m["step"]) for m in meshes})
    out["step"] = out["steps"][0]
    return out


def _terrain_mesh_persp(args, cam):
    """Terrain faces for a perspective view: nested square rings of detail around the
    eye. Each level (4, 8, 16, ... studs) covers the distance where its quads still
    span >= TERRAIN_QUAD_PX pixels; the next coarser level fills the rest (with a hole
    where the finer one is). --terrain-step forces one level everywhere."""
    field = getattr(args, "terrain_field", None)
    if field is None or field.empty:
        return None
    if args.terrain_step:
        m = field.mesh(field.lod(1.0, args.terrain_step))
        return _merge_meshes([m])
    lo, hi = field.bounds()
    ox, oz = field.origin
    ex, ez = cam.eye[0], cam.eye[2]
    k = cam.focal(1)  # final-image pixels per stud at 1 stud distance
    step, hole, meshes = field.step, None, []
    while True:
        reach = step * k / TERRAIN_QUAD_PX
        coarse = 2 * step

        def snap(v, o, up):
            return o + (math.ceil if up else math.floor)((v - o) / coarse) * coarse

        rect = (snap(ex - reach, ox, False), snap(ez - reach, oz, False),
                snap(ex + reach, ox, True), snap(ez + reach, oz, True))
        last = step >= 64 or (rect[0] <= lo[0] and rect[1] <= lo[2] and rect[2] >= hi[0] and rect[3] >= hi[2])
        overlaps = rect[0] < hi[0] and rect[2] > lo[0] and rect[1] < hi[2] and rect[3] > lo[2]
        if last or overlaps:
            meshes.append(field.mesh(step, None if last else rect, hole, None if last else coarse))
        if last:
            break
        hole, step = rect, coarse
    return _merge_meshes(meshes)


def draw_persp_slot_labels(im, cam, scene, zbuf, fog):
    """Numbered base-slot markers; faint when hidden behind something or far away."""
    if not scene.slots:
        return
    draw = ImageDraw.Draw(im, "RGBA")
    font = _font(16)
    ss = cam.ss
    for slot in scene.slots:
        p = np.array(slot["cf"][:3], float) + (0, 3, 0)
        x, y, z = cam.project(p, ss=1)
        if not (z > NEAR_PLANE and 0 <= x < im.size[0] and 0 <= y < im.size[1]):
            continue
        dist = float(np.linalg.norm(p - cam.eye))
        if fog and dist > fog[1] * 1.2:
            continue
        zx, zy = min(int(x * ss), zbuf.shape[1] - 1), min(int(y * ss), zbuf.shape[0] - 1)
        visible = not (zbuf[zy, zx] < 0 and -1 / zbuf[zy, zx] < z - 4)
        alpha = 230 if visible else 110
        col = tuple(int(c) for c in slot.get("color", [255, 255, 255]))
        rad = 13 if dist < 400 else 10
        draw.ellipse([x - rad, y - rad, x + rad, y + rad], fill=col + (alpha,), outline=(20, 20, 20, alpha), width=2)
        _text(draw, (x, y), str(slot["index"]), font, fill=(20, 24, 30, alpha), anchor="mm")


def view_persp(scene, args, spec, n):
    eye, target, fov, label = spec
    width = args.size
    height = int(round(args.size * PERSP_ASPECT))
    cam = PerspCamera(eye, target, fov, width, height, args.ss)
    mesh = _terrain_mesh_persp(args, cam)
    buf, info = render_persp(with_terrain(scene, mesh), cam, outlines=not args.no_outlines, fog=args.fog)
    im = to_image(buf, args.ss)
    if not args.no_labels:
        draw_persp_slot_labels(im, cam, scene, info["zbuf"], args.fog)
    fog = f"fog {args.fog[0]:g}..{args.fog[1]:g} studs" if args.fog else "no fog"
    title = f"PERSP {n}" + (f"  {label}" if label else "")
    draw_title(
        im,
        [
            title,
            f"eye ({eye[0]:.0f}, {eye[1]:.0f}, {eye[2]:.0f})  ->  target ({target[0]:.0f}, {target[1]:.0f}, {target[2]:.0f})",
            f"heading {cam.heading:.0f} deg (0 = +Z, 90 = +X), pitch {cam.pitch:.0f} deg, "
            f"vertical FOV {fov:g} deg, {fog}",
            _stats_line(scene) + f"; {info['faces']} of {info['total']} faces in view",
        ]
        + _terrain_line(args, mesh),
    )
    return im


# --------------------------------------------------------------------------------------
# Perspective presets
# --------------------------------------------------------------------------------------


def _vertical_hits(scene, x, z):
    """(ymin, ymax) of each part's box along the vertical line through (x, z); NaN = miss."""
    n = len(scene.parts)
    if n == 0:
        return np.zeros(0), np.zeros(0)
    half = scene.size / 2
    a = np.einsum("nji,nj->ni", scene.rot, np.array([x, 0.0, z]) - scene.pos)  # R^T d
    b = scene.rot[:, 1, :]  # R^T e_y
    lo, hi = np.full(n, -np.inf), np.full(n, np.inf)
    ok = np.ones(n, bool)
    with np.errstate(divide="ignore", invalid="ignore"):
        for i in range(3):
            small = np.abs(b[:, i]) < 1e-9
            ok &= ~small | (np.abs(a[:, i]) <= half[:, i])
            t1 = (-half[:, i] - a[:, i]) / b[:, i]
            t2 = (half[:, i] - a[:, i]) / b[:, i]
            lo = np.where(small, lo, np.maximum(lo, np.minimum(t1, t2)))
            hi = np.where(small, hi, np.minimum(hi, np.maximum(t1, t2)))
    ok &= lo <= hi
    return np.where(ok, lo, np.nan), np.where(ok, hi, np.nan)


def _ground_y(scene, field, x, z, below=1e9):
    """Highest surface (part top, terrain or water) at (x, z) that is not above `below`."""
    best = -np.inf
    _, top = _vertical_hits(scene, x, z)
    solid = np.isfinite(top) & (top <= below)
    if len(top):
        solid &= (scene.part_opacity > 0.3) | scene.water
    if solid.any():
        best = float(top[solid].max())
    if field is not None and not field.empty:
        ix = int(math.floor((x - field.origin[0]) / field.step))
        iz = int(math.floor((z - field.origin[1]) / field.step))
        if 0 <= iz < field.top.shape[0] and 0 <= ix < field.top.shape[1]:
            surf = float(np.fmax(field.top[iz, ix], field.water[iz, ix]))
            if math.isfinite(surf) and surf <= below:
                best = max(best, surf)
    return best if math.isfinite(best) else 0.0


def _inside_part(scene, p, margin=1.0):
    """Is point p inside (or within `margin` of) any non-water part's box?"""
    if len(scene.parts) == 0:
        return False
    local = np.einsum("nji,nj->ni", scene.rot, np.asarray(p, float) - scene.pos)
    inside = np.all(np.abs(local) <= scene.size / 2 + margin, 1) & ~scene.water
    return bool(inside.any())


def _slot_frame(scene, slot):
    """Slot position, rotation and the z range (slot-local, -Z = front, the look
    direction) of the base parts placed on it (default -30..30 without a base)."""
    cf = np.asarray(slot["cf"], float)
    pos, rot = cf[:3], cf[3:].reshape(3, 3)
    mine = np.nonzero(scene.is_base & np.array([p.get("baseIndex") == slot.get("index") for p in scene.parts], bool))[0]
    if len(mine) == 0:
        return pos, rot, -30.0, 30.0
    rl = np.einsum("ji,njk->nik", rot, scene.rot[mine])  # part rotation in slot space
    centre = (scene.pos[mine] - pos) @ rot  # R^T (p - pos)
    half = np.einsum("nij,nj->ni", np.abs(rl), scene.size[mine] / 2)
    return pos, rot, float((centre[:, 2] - half[:, 2]).min()), float((centre[:, 2] + half[:, 2]).max())


def _bridge_axes(scene):
    """Bridges (parts whose path has a segment containing "bridge"), as (inner, outer)
    end points of their long horizontal axis, inner = the end nearer the origin."""
    groups = {}
    for i, p in enumerate(scene.parts):
        if p.get("kind") == "base":
            continue
        segs = p.get("path", "").split(".")
        hits = [j for j, sgm in enumerate(segs) if "bridge" in sgm.lower()]
        if hits:
            groups.setdefault(".".join(segs[: hits[-1] + 1]), []).append(i)
    axes = []
    for idx in groups.values():
        lo, hi = scene.aabb_min[idx].min(0), scene.aabb_max[idx].max(0)
        ext = hi - lo
        if max(ext[0], ext[2]) > HUGE_EXTENT or max(ext[0], ext[2]) < 20:
            continue
        c = (lo + hi) / 2
        d = np.array([ext[0] / 2, 0, 0]) if ext[0] >= ext[2] else np.array([0, 0, ext[2] / 2])
        a, b = c - d, c + d
        a[1] = b[1] = 0.0
        if np.hypot(a[0], a[2]) > np.hypot(b[0], b[2]):
            a, b = b, a
        axes.append((a, b))
    return axes


def _azimuth(v):
    return math.atan2(v[0], v[2])  # radians, 0 = +Z, pi/2 = +X


def _heading(az):
    return np.array([math.sin(az), 0.0, math.cos(az)])


def _angle_diff(a, b):
    return abs((a - b + math.pi) % (2 * math.pi) - math.pi)


def ring_preset(scene, field):
    """Six player-eye views of a ring map whose lagoon centre is the origin:
    (label, eye, target) tuples. Positions come from the slots and the geometry."""
    slots = sorted(scene.slots, key=lambda sl: sl.get("index", 0))
    sp = np.array([sl["cf"][:3] for sl in slots], float).reshape(-1, 3)
    ring_r = float(np.median(np.hypot(sp[:, 0], sp[:, 2]))) if len(sp) else 300.0
    a_slot1 = _azimuth(sp[0]) if len(sp) else 0.0
    bridges = _bridge_axes(scene)
    if bridges:  # the bridge closest to slot 1
        a_hub = min((_azimuth(b) for _, b in bridges), key=lambda a: _angle_diff(a, a_slot1))
    elif len(sp) > 1:  # halfway to the neighbouring slot
        other = min((_azimuth(p) for p in sp[1:]), key=lambda a: _angle_diff(a, a_slot1))
        a_hub = a_slot1 + ((other - a_slot1 + math.pi) % (2 * math.pi) - math.pi) / 2
    else:
        a_hub = 0.0
    views = []

    def free(p):
        return not _inside_part(scene, p, 1.0)

    # 1. Hub centre, eye height ~12, looking out along a_hub at the ring.
    d = _heading(a_hub)
    eye = None
    for r in np.arange(12.0, 60.0, 2.0):
        q = d * r
        q[1] = _ground_y(scene, field, q[0], q[2], below=30) + 8
        if free(q):
            eye = q
            break
    eye = eye if eye is not None else d * 12 + (0, 12, 0)
    views.append(("hub centre, looking out at the ring", eye, d * ring_r + (0, 8, 0)))

    # 2. On a bridge (the next one round), near its outer end, looking back at the hub.
    if bridges:
        inner, outer = min(bridges, key=lambda ab: _angle_diff(_azimuth(ab[1]), a_hub + math.pi / 2))
    else:
        inner, outer = _heading(a_hub + math.pi / 2) * ring_r * 0.45, _heading(a_hub + math.pi / 2) * ring_r * 0.95
    eye = inner + (outer - inner) * 0.75
    eye[1] = _ground_y(scene, field, eye[0], eye[2], below=40) + 7
    views.append(("on a bridge, looking back at the hub", eye, np.array([0.0, 14.0, 0.0])))

    # 3. Front of slot 1's plot (its -Z side, towards the lagoon), looking at the lagoon.
    if len(sp):
        pos0, rot0, zmin, zmax = _slot_frame(scene, slots[0])
        eye = None
        for back in (3, 6, 10, 1, 14):
            for side in (0, 3, -3, 6, -6, 10, -10):
                q = pos0 + rot0 @ np.array([side, 0.0, zmin + back])
                q[1] = _ground_y(scene, field, q[0], q[2], below=pos0[1] + 25) + 6
                if free(q):
                    eye = q
                    break
            if eye is not None:
                break
        if eye is None:
            eye = pos0 + rot0 @ np.array([0.0, 6.0, zmin])
        views.append((f"front of plot {slots[0].get('index', 1)}, looking at the lagoon", eye,
                      np.array([0.0, 6.0, 0.0])))

        # 4. High above the base opposite slot 1: behind its back edge at y = 60, looking
        #    down over the whole plot towards the lagoon.
        k = int(np.argmax([_angle_diff(_azimuth(p), a_slot1) for p in sp])) if len(sp) > 1 else 0
        posk, rotk, zmin, zmax = _slot_frame(scene, slots[k])
        eye = posk + rotk @ np.array([0.0, 0.0, zmax + 26])
        eye[1] = 60.0
        target = posk + rotk @ np.array([0.0, 0.0, (zmin + zmax) / 2])
        views.append((f"high above base {slots[k].get('index', k + 1)}", eye, target))

    # 5. From the ocean, eye height 40, looking at the island.
    content = scene.content & ~scene.water & ~scene.is_base & (scene.aabb_max[:, 1] > 0)
    if content.any():
        c = (scene.aabb_min[content] + scene.aabb_max[content]) / 2
        island_r = float(np.percentile(np.hypot(c[:, 0], c[:, 2]), 90))
    else:
        island_r = ring_r * 2
    dist = island_r + 350
    if field is not None and not field.empty:
        tlo, thi = field.bounds()
        dist = min(dist, float(min(-tlo[0], -tlo[2], thi[0], thi[2])) - 60)
    dist = max(dist, ring_r * 1.5)
    eye = None
    for step_ in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8, -8, 9, -9, 10, -10, 11, -11, 12]:
        q = _heading(a_slot1 + math.radians(15) * step_) * dist
        dx = np.maximum(np.maximum(scene.aabb_min[:, 0] - q[0], q[0] - scene.aabb_max[:, 0]), 0)
        dz = np.maximum(np.maximum(scene.aabb_min[:, 2] - q[2], q[2] - scene.aabb_max[:, 2]), 0)
        near = scene.content & ~scene.water & (scene.aabb_max[:, 1] > -1) & (np.hypot(dx, dz) < 220)
        if not near.any():
            eye = q
            break
    eye = eye if eye is not None else _heading(a_slot1) * dist
    eye[1] = max(40.0, _ground_y(scene, field, eye[0], eye[2]) + 15)
    views.append(("from the ocean, looking at the island", eye, np.array([0.0, 12.0, 0.0])))

    # 6. High overview.
    eye = _heading(a_hub + math.pi / 4) * ring_r * 2
    eye[1] = 350.0
    views.append(("high overview", eye, np.array([0.0, 0.0, 0.0])))
    return views


def _bounds(scene, args):
    lo, hi = scene.frame_box(args.frame)
    field = getattr(args, "terrain_field", None)
    if field is not None and not field.empty:
        tlo, thi = field.bounds()
        if len(scene.parts) and scene.content.any():
            lo, hi = np.minimum(lo, tlo), np.maximum(hi, thi)
        else:  # only Baseplate-sized parts (or none): frame the terrain
            lo, hi = tlo, thi
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


def _parse_persp(text):
    vals = [float(v) for v in text.split(",")]
    if len(vals) not in (6, 7):
        raise argparse.ArgumentTypeError("--persp expects ex,ey,ez,tx,ty,tz[,fov]")
    return vals


def _parse_fog(text):
    vals = [float(v) for v in text.split(",")]
    if len(vals) != 2 or vals[1] <= vals[0]:
        raise argparse.ArgumentTypeError("--fog expects start,end with end > start")
    return vals


def _parse_bounds(text):
    vals = [float(v) for v in text.split(",")]
    if len(vals) != 4:
        raise argparse.ArgumentTypeError("--bounds expects xmin,zmin,xmax,zmax")
    return vals


def main(argv=None):
    ap = argparse.ArgumentParser(description="Render preview PNGs from export_parts.luau JSON.")
    ap.add_argument("parts_json", help='export_parts.luau JSON, or "-" for none (terrain only)')
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--views", default=None,
                    help="comma list of top,iso,iso2,zoom,persp (default: top,iso,iso2,zoom; "
                         "persp alone when --persp/--persp-preset is given)")
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
    ap.add_argument("--terrain", metavar="FILE",
                    help="also draw smooth terrain: heightfield .npz/.json from terrain_export.py, "
                         "or a raw SmoothGrid .bin from export_terrain.luau")
    ap.add_argument("--terrain-step", type=float, default=None, metavar="STUDS",
                    help="terrain quad size (4 = native voxel columns); default: automatic per view")
    ap.add_argument("--persp", action="append", type=_parse_persp, default=[], metavar="EX,EY,EZ,TX,TY,TZ[,FOV]",
                    help="perspective view: eye and look-at target in studs, vertical FOV in degrees "
                         f"(default {PERSP_FOV:g}); repeatable -> persp_1.png, persp_2.png, ...")
    ap.add_argument("--persp-preset", choices=("ring",), default=None,
                    help="ring: 6 player-eye views of the ring map (hub, bridge, plot front, above a base, "
                         "ocean, overview), after any --persp views")
    ap.add_argument("--fog", type=_parse_fog, default=[FOG_START, FOG_END], metavar="START,END",
                    help=f"persp distance fog: starts at START studs, 90%% at END (default {FOG_START:g},{FOG_END:g})")
    ap.add_argument("--no-fog", action="store_true", help="persp: no distance fog")
    ap.add_argument("--no-grade", action="store_true",
                    help="ignore the place's colour grading (ColorCorrectionEffect) exported with the parts")
    # Allow "--zoom -57,-57,30" (argparse would read the value as an option).
    argv = list(sys.argv[1:] if argv is None else argv)
    for i in range(len(argv) - 1):
        if argv[i] in ("--zoom", "--bounds", "--persp") and argv[i + 1].startswith("-"):
            argv[i : i + 2] = [f"{argv[i]}={argv[i + 1]}", ""]
    args = ap.parse_args([a for a in argv if a != ""])
    if args.no_fog:
        args.fog = None
    if args.views is None:
        args.views = "persp" if (args.persp or args.persp_preset) else "top,iso,iso2,zoom"

    if args.parts_json == "-":  # terrain only
        data = {"parts": [], "slots": []}
    else:
        with open(args.parts_json, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    os.makedirs(args.out_dir, exist_ok=True)
    global GRADE, WATER_COLOR, WATER_OPACITY, FOG_TINT
    GRADE = None if args.no_grade else data.get("grade")
    if GRADE:
        print(f"[render] colour grading from the place: {GRADE}")
    if data.get("water"):  # the place's terrain water
        WATER_COLOR = np.array(data["water"]["color"], np.float32)
        WATER_OPACITY = float(min(max(1.0 - data["water"].get("transparency", 0.45) + 0.1, 0.3), 0.9))
        TERRAIN_COLORS["Water"] = tuple(int(c) for c in WATER_COLOR)
    if data.get("atmosphere") and args.fog == [FOG_START, FOG_END]:  # no explicit --fog
        args.fog, FOG_TINT = atmosphere_fog(data["atmosphere"])
        args.fog = list(args.fog)
        print(f"[render] fog from the place's Atmosphere: {args.fog[0]:.0f}..{args.fog[1]:.0f} studs")

    t0 = time.time()
    scene = Scene(data)
    print(f"[render] {len(scene.parts)} parts -> {len(scene.count)} faces ({time.time() - t0:.2f}s)")
    args.terrain_field = None
    if args.terrain:
        t = time.time()
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import terrain_export

        args.terrain_field = TerrainField(terrain_export.load_heightfield(args.terrain))
        f = args.terrain_field
        print(
            f"[render] terrain {f.top.shape[1]}x{f.top.shape[0]} columns, {f.columns} solid,"
            f" {f.wet_columns} with water ({time.time() - t:.2f}s)"
        )

    views = [v.strip() for v in args.views.split(",") if v.strip()]
    for view in views:
        if view not in ("top", "iso", "iso2", "zoom", "persp"):
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
                    lo, hi = _bounds(scene, args)
                    c = (lo + hi) / 2
                    targets = [[c[0], c[2], max(float((hi - lo)[[0, 2]].max()) / 4, 10.0)]]
            for n, target in enumerate(targets, 1):
                t = time.time()
                x, z, radius = target[:3]
                az = target[3] if len(target) > 3 else 45.0
                save(f"zoom_{n}.png", view_zoom(scene, args, x, z, radius, az), t)
        elif view == "persp":
            specs = []
            for v in args.persp:
                specs.append((np.array(v[:3]), np.array(v[3:6]), v[6] if len(v) > 6 else PERSP_FOV, ""))
            if args.persp_preset == "ring" or not specs:
                for label, eye, target in ring_preset(scene, args.terrain_field):
                    specs.append((eye, target, PERSP_FOV, label))
            for n, spec in enumerate(specs, 1):
                t = time.time()
                eye, target = spec[0], spec[1]
                print(f"[render] persp_{n}: eye ({eye[0]:.1f}, {eye[1]:.1f}, {eye[2]:.1f}) -> target "
                      f"({target[0]:.1f}, {target[1]:.1f}, {target[2]:.1f}) fov {spec[2]:g}  {spec[3]}")
                save(f"persp_{n}.png", view_persp(scene, args, spec, n), t)
    print(f"[render] done in {time.time() - t0:.2f}s")


if __name__ == "__main__":
    main()
