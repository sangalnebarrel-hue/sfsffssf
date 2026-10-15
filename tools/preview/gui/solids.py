"""The 3D part of a world frame: the posed avatar, the bent rod, the held / leaping fish, the
FX parts and the ambient life, rasterized with render.py's z-buffer and composited against the
pier backdrop's own depth (gui/backdrop.py) — so what stands in front hides what is behind,
both ways, per pixel.

gui/world_capture.luau writes, per frame (frame["world"]):
  solids  [{cf: [x, y, z, R00..R22] (spot frame), s: [sx, sy, sz], c: [r, g, b], sh: shape,
            t?: transparency, m?: 1 (Neon)}]
  movers  [[id, x, y, z, R00..R22, transparency]]  map parts AmbientWorld moves (in view)
and once per dump (dump["scene"]):
  movers  [{s, c, sh, k (kind), m?, sf? (saved LEGO surfaces)}]  (index = id - 1)
  exclude [[x, y, z, sx, sy, sz]]  the movers at rest, world coordinates (the backdrop is
          rendered without them)
  waterY  the water surface, spot frame.
The spot frame is (right, up, forward) from the top of the player's FishingSpot; it maps onto
base 1's FishingSpot of the backdrop (Context: the export's ground and look), so the parts are
lit by render.py's sun, fogged by the place's atmosphere and graded like the backdrop.

Drawing (render(...)):
  * opaque parts: one z-buffer pass limited by the backdrop's depth (+ a hair of margin, so
    feet on the planks are not cut), render.py's face shading; LEGO studs only on movers that
    have them in the place (FX, ambient and avatar parts never get studs — RbxSim's
    Instance.new defaults to Studs on top, the world capture does not pass them on);
  * outlines like render.py's (where the visible part / face group changes), on the solid's
    side of a silhouette too, fading with distance;
  * transparent parts: every visible face blended far to near over the solids and the
    backdrop (the fish shadow, pulsing foam, the pillar);
  * under the water surface (camera above): mixed with the water colour by its opacity (+
    Fresnel) like render.py's terrain water, scaled by the ray's way under the surface
    (WATER_CLEAR): the shadow just under the bobber reads, deep things fade into the water;
  * fog and the place's colour grading, like the backdrop;
  * Neon parts: unlit, plus a soft glow around them.
Returns an RGBA layer at the supersampled size and the solids' opaque depth per output pixel
(for the occlusion of the 2D items in gui/world.py).
"""

import math
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import render as R  # noqa: E402  (tools/preview/render.py)

DEPTH_MARGIN = (0.03, 0.002)  # studs + share of the distance: ties with the backdrop go to the solid
GLOW_RADIUS = 4.0  # px (output) of the Neon glow
GLOW_ALPHA = 0.45
MAX_TRANSPARENT_FACES = 4000  # beyond this the farthest transparent faces are dropped
WATER_CLEAR = 6.0  # studs of way under the water until it tints a part fully (shallow = clearer)


class Context:
    """Where the spot frame sits in the backdrop's world and the place's look (gui/backdrop.py
    world_context): ground (the top of base 1's FishingSpot), M = [right up forward] columns,
    grade, fog, fog_tint, water colour / opacity."""

    def __init__(self, ground, look, grade=None, fog=(R.FOG_START, R.FOG_END), fog_tint=None,
                 water_color=(40, 120, 205), water_opacity=0.55):
        self.ground = np.asarray(ground, float)
        f = np.array([look[0], 0.0, look[2]], float)
        f /= np.linalg.norm(f)
        up = np.array([0.0, 1.0, 0.0])
        self.M = np.column_stack([np.cross(f, up), up, f])
        self.grade = grade
        self.fog = tuple(fog) if fog else None
        self.fog_tint = fog_tint
        self.water_color = np.asarray(water_color, np.float32)
        self.water_opacity = float(water_opacity)

    def point(self, v):
        return self.ground + self.M @ np.asarray(v, float)

    @staticmethod
    def from_json(d):
        tint = d.get("fog_tint")
        return Context(d["ground"], d["look"], d.get("grade"), d.get("fog") or (R.FOG_START, R.FOG_END),
                       (tint[0], np.asarray(tint[1], np.float32)) if tint else None,
                       d.get("water_color", (40, 120, 205)), d.get("water_opacity", 0.55))


def _as_list(v):
    if not v:
        return []
    return v if isinstance(v, list) else list(v.values())


def parts_of(world, scene, ctx):
    """render.py part dicts (world coordinates of the backdrop) of a frame's solids + movers."""
    rows, meta = [], []
    for s in _as_list(world.get("solids")):
        rows.append(s["cf"])
        meta.append((s["s"], s["c"], s.get("sh", "Block"), float(s.get("t", 0) or 0), bool(s.get("m")), None))
    infos = _as_list((scene or {}).get("movers"))
    for m in _as_list(world.get("movers")):
        idx = int(m[0]) - 1
        if not (0 <= idx < len(infos)):
            continue
        info = infos[idx]
        rows.append(m[1:13])
        meta.append((info["s"], info["c"], info.get("sh", "Block"), float(m[13]) if len(m) > 13 else 0.0,
                     bool(info.get("m")), info.get("sf")))
    if not rows:
        return []
    cf = np.asarray(rows, float).reshape(-1, 12)
    pos = ctx.ground[None, :] + cf[:, :3] @ ctx.M.T
    rot = np.einsum("ij,njk->nik", ctx.M, cf[:, 3:].reshape(-1, 3, 3))
    out = []
    for i, (size, color, shape, t, neon, surfaces) in enumerate(meta):
        part = {
            "cf": [float(pos[i, 0]), float(pos[i, 1]), float(pos[i, 2])] + [float(v) for v in rot[i].reshape(-1)],
            "size": [float(v) for v in size],
            "color": [int(v) for v in color],
            "transparency": t,
            "shape": shape,
            "material": "Neon" if neon else "SmoothPlastic",
            "kind": "part",
        }
        if surfaces:
            part["surfaces"] = dict(surfaces)
        out.append(part)
    return out


def _grade(c, grade):
    """render.apply_grade on a float colour array (..., 3) in 0..255."""
    if not grade:
        return c
    x = c / 255.0 + grade.get("brightness", 0.0)
    x = (x - 0.5) * (1.0 + grade.get("contrast", 0.0)) + 0.5
    lum = x @ np.array([0.299, 0.587, 0.114], np.float32)
    x = lum[..., None] + (x - lum[..., None]) * (1.0 + grade.get("saturation", 0.0))
    x = x * (np.array(grade.get("tint", [255, 255, 255]), np.float32) / 255.0)
    return np.clip(x, 0, 1) * 255.0


def _upsample_depth(bg_depth_ss, Hs, Ws):
    """The backdrop's view distance at the render's supersampled size (nearest)."""
    if bg_depth_ss is None:
        return np.full((Hs, Ws), np.inf, np.float32)
    d = np.asarray(bg_depth_ss, np.float32)
    d = np.where(d > 0, d, np.inf).astype(np.float32)  # (an empty pixel is the sky)
    if d.shape == (Hs, Ws):
        return d
    ys = (np.arange(Hs) * d.shape[0] // Hs).clip(0, d.shape[0] - 1)
    xs = (np.arange(Ws) * d.shape[1] // Ws).clip(0, d.shape[1] - 1)
    return d[np.ix_(ys, xs)]


def render(world, scene, cam_spec, ctx, W, H, ss, bg_depth_ss=None):
    """(layer RGBA Image at W*ss x H*ss or None, opaque depth (H, W) float32 or None) of a world
    frame's solids. cam_spec = {eye, focus, fov} in the spot frame; bg_depth_ss = the
    backdrop's view distance per supersampled pixel (inf = sky; None = nothing to hide behind)."""
    parts = parts_of(world, scene, ctx)
    if not parts:
        return None, None
    sc = R.Scene({"parts": parts})
    eye, focus = ctx.point(cam_spec["eye"]), ctx.point(cam_spec["focus"])
    cam = R.PerspCamera(eye, focus, float(cam_spec.get("fov", 70)), W, H, ss)
    Ws, Hs = W * ss, H * ss
    fp = cam.focal(ss)
    faces, px, py, count, A, B, C, nc = R._persp_faces(sc, cam, Ws, Hs, fp)
    if len(faces) == 0:
        return None, None
    x0 = np.floor(px.min(1)).clip(0, Ws).astype(np.int64)
    x1 = np.ceil(px.max(1)).clip(0, Ws).astype(np.int64)
    y0 = np.floor(py.min(1)).clip(0, Hs).astype(np.int64)
    y1 = np.ceil(py.max(1)).clip(0, Hs).astype(np.int64)
    area = (px * np.roll(py, -1, 1) - py * np.roll(px, -1, 1)).sum(1)
    sel = (x1 > x0) & (y1 > y0) & (np.abs(area) > 1e-9)
    if not sel.any():
        return None, None
    # Work in the window the faces cover (+ the glow), aligned to whole output pixels: an
    # avatar is a tenth of the screen. Window coordinates: pixel - (GX, GY); the depth plane
    # A*x + B*y + C shifts with them.
    pad = int(math.ceil(GLOW_RADIUS * ss * 3)) if sc.face_unlit[faces][sel].any() else ss
    GX = max(0, (int(x0[sel].min()) - pad) // ss * ss)
    GY = max(0, (int(y0[sel].min()) - pad) // ss * ss)
    GX1 = min(Ws, -(-(int(x1[sel].max()) + pad) // ss) * ss)
    GY1 = min(Hs, -(-(int(y1[sel].max()) + pad) // ss) * ss)
    Ww, Hw = GX1 - GX, GY1 - GY
    sign = np.where(area > 0, 1.0, -1.0)
    raster = R._Rasterizer(px - GX, py - GY, sign, A, B, C + A * GX + B * GY, count, (x0 - GX).clip(0, Ww),
                           (x1 - GX).clip(0, Ww), (y0 - GY).clip(0, Hw), (y1 - GY).clip(0, Hw), Ww, Hw)
    opacity = sc.face_opacity[faces]
    opaque = np.nonzero(sel & (opacity >= 0.999))[0]
    transparent = np.nonzero(sel & (opacity < 0.999))[0]

    bg = _upsample_depth(bg_depth_ss, Hs, Ws)[GY:GY1, GX:GX1]
    with np.errstate(divide="ignore"):
        limit = (-1.0 / (bg + DEPTH_MARGIN[0] + DEPTH_MARGIN[1] * bg)).astype(np.float32)
    zbuf = np.full((Hw, Ww), np.inf, np.float32)
    fidx = np.full((Hw, Ww), -1, np.int32)
    R._depth_pass(raster, opaque, zbuf, fidx, limit=limit)

    table = sc.face_rgb[faces].astype(np.float32)
    hit = fidx >= 0
    # premultiplied colour and alpha of the layer
    P = np.zeros((Hw, Ww, 3), np.float32)
    Aa = np.zeros((Hw, Ww), np.float32)
    P[hit] = table[fidx[hit]]
    Aa[hit] = 1.0

    # per-pixel ray (unit step along the view axis)
    X = ((np.arange(Ww, dtype=np.float32) + GX + 0.5) - Ws / 2) / fp
    Y = (Hs / 2 - (np.arange(Hw, dtype=np.float32) + GY + 0.5)) / fp

    # LEGO studs (movers that have them)
    stud = sc.face_stud[faces]
    if R.STUDS_ON and hit.any() and (stud > 0).any():
        fh = fidx[hit]
        sm = stud[fh] > 0
        if sm.any():
            yy, xx = np.nonzero(hit)
            yy, xx, fs = yy[sm], xx[sm], fh[sm]
            gx, gy = X[xx].astype(np.float64), Y[yy].astype(np.float64)
            t = -1.0 / zbuf[yy, xx].astype(np.float64)
            ray = cam.f[None, :] + gx[:, None] * cam.r[None, :] + gy[:, None] * cam.u[None, :]
            Pw = cam.eye[None, :] + t[:, None] * ray
            uvm = sc.face_uv[faces][fs]
            uu = (uvm[:, 0:3] * Pw).sum(1) + uvm[:, 3]
            vv = (uvm[:, 4:7] * Pw).sum(1) + uvm[:, 7]
            rl = np.linalg.norm(ray, axis=1)
            cos = np.abs((sc.normal[faces][fs] * ray).sum(1)) / rl
            cell_px = fp * np.sqrt(np.maximum(cos, 1e-3)) / (t * rl * ss)
            P[yy, xx] *= R.stud_mult(uu, vv, stud[fs], cell_px)[:, None]

    # outlines: where the visible face group changes (render.py's rule), and all around a
    # silhouette on the solid's side
    groups = np.concatenate([[-1], sc.group[faces]]).astype(np.int32)
    ids = groups[fidx + 1]
    edge = np.zeros((Hw, Ww), bool)
    edge[:, :-1] |= ids[:, :-1] != ids[:, 1:]
    edge[:-1, :] |= ids[:-1, :] != ids[1:, :]
    sil = np.zeros((Hw, Ww), bool)
    sil[:, 1:] |= ids[:, :-1] < 0
    sil[1:, :] |= ids[:-1, :] < 0
    edge = (edge | sil) & hit
    if edge.any():
        ey, ex = np.nonzero(edge)
        norm = np.sqrt(1 + X[ex] ** 2 + Y[ey] ** 2)
        dist = -norm / zbuf[ey, ex]
        f0, f1 = R.OUTLINE_FADE
        w = np.clip((f1 - dist) / (f1 - f0), 0, 1)
        P[ey, ex] *= (1 - (1 - R.OUTLINE_FACTOR) * w)[:, None]

    # transparent faces, far to near, over the solids and the backdrop
    tz = np.full((Hw, Ww), np.inf, np.float32)  # nearest transparent depth (-1/t)
    if len(transparent):
        rel = sc.centroid[faces[transparent]] - cam.eye
        order = transparent[np.argsort(-(rel @ cam.f))]
        if len(order) > MAX_TRANSPARENT_FACES:
            order = order[-MAX_TRANSPARENT_FACES:]
        front = np.minimum(zbuf, limit)
        Pf, Af, tf = P.reshape(-1, 3), Aa.reshape(-1), tz.reshape(-1)
        ff = front.reshape(-1)
        for i in order:
            a = float(opacity[i])
            c = table[i]
            for item in raster.cover(np.array([i])):
                if item[0] == "block":
                    _, _, r0, r1, c0, c1, mask, depth = item
                    m = depth < front[r0:r1, c0:c1]
                    if mask is not None:
                        m &= mask
                    rr, cc = np.nonzero(m)
                    pix = (rr + r0) * Ww + (cc + c0)
                    dep = depth[rr, cc]
                else:
                    _, pix, dep, _ = item
                    keep = dep < ff[pix]
                    pix, dep = pix[keep], dep[keep]
                if len(pix) == 0:
                    continue
                Pf[pix] = c[None, :] * a + Pf[pix] * (1 - a)
                Af[pix] = a + Af[pix] * (1 - a)
                tf[pix] = np.minimum(tf[pix], dep)

    any_px = Aa > 0.002
    if not any_px.any():
        return None, None
    yy, xx = np.nonzero(any_px)
    a = Aa[yy, xx]
    col = P[yy, xx] / a[:, None]
    zt = np.minimum(zbuf[yy, xx], tz[yy, xx])
    t = -1.0 / zt  # view-axis distance of the nearest drawn surface
    gx, gy = X[xx], Y[yy]
    norm = np.sqrt(1 + gx * gx + gy * gy)
    ray_y = cam.f[1] + gx * cam.r[1] + gy * cam.u[1]
    sky = R._sky(ray_y / norm)
    # under the water surface: the water's colour over it (camera above the water)
    water_y = ctx.ground[1] + float((world.get("waterY") if world.get("waterY") is not None
                                     else (scene or {}).get("waterY", -1e9)))
    if cam.eye[1] > water_y:
        wy = cam.eye[1] + t * ray_y
        under = wy < water_y - 0.02
        if under.any():
            cosw = np.abs(ray_y[under]) / norm[under]
            F = (1 - np.clip(cosw, 0, 1)) ** 5 * R.WATER_FRESNEL
            # the water absorbs along the ray's way under the surface: a fish shadow half a
            # stud down reads clearly, the lagoon bed (the backdrop) is fully tinted
            path = (water_y - wy[under]) / np.maximum(cosw, 0.05)
            absorb = ctx.water_opacity * np.clip(path / WATER_CLEAR, 0.15, 1.0)
            aw = absorb + (1 - absorb) * F
            wc = ctx.water_color[None, :] + (sky[under] - ctx.water_color[None, :]) * (0.6 * F)[:, None]
            col[under] = col[under] * (1 - aw)[:, None] + wc * aw[:, None]
    # fog (the place's atmosphere), then the colour grading
    if ctx.fog:
        f = R._fog_amount(t * norm, ctx.fog)[:, None]
        target = sky
        if ctx.fog_tint is not None:
            target = target + (np.asarray(ctx.fog_tint[1], np.float32) - target) * ctx.fog_tint[0]
        col = col + (target - col) * f
    col = _grade(col, ctx.grade)

    layer = np.zeros((Hw, Ww, 4), np.uint8)
    layer[yy, xx, :3] = (col + 0.5).clip(0, 255).astype(np.uint8)
    layer[yy, xx, 3] = (a * 255 + 0.5).clip(0, 255).astype(np.uint8)
    im = Image.fromarray(layer, "RGBA")

    # Neon glow under the layer
    unlit = sc.face_unlit[faces]
    if hit.any() and unlit.any():
        neon = hit & unlit[np.maximum(fidx, 0)]
        if neon.any():
            g = np.zeros((Hw, Ww, 4), np.uint8)
            g[neon, :3] = layer[neon, :3]
            g[neon, 3] = 255
            glow = Image.fromarray(g, "RGBA").filter(ImageFilter.GaussianBlur(GLOW_RADIUS * ss))
            ga = np.asarray(glow, np.float32)
            alpha = ga[..., 3] / 255.0
            rgb = ga[..., :3] / np.maximum(alpha, 1e-3)[..., None]
            out = np.zeros((Hw, Ww, 4), np.uint8)
            out[..., :3] = rgb.clip(0, 255).astype(np.uint8)
            out[..., 3] = (np.minimum(alpha * 2.0, 1.0) * GLOW_ALPHA * 255).astype(np.uint8)
            base = Image.fromarray(out, "RGBA")
            base.alpha_composite(im)
            im = base

    full = Image.new("RGBA", (Ws, Hs), (0, 0, 0, 0))
    full.paste(im, (GX, GY))
    # the solids' opaque depth per output pixel (nearest of each ss x ss block)
    d = np.full((Hw, Ww), np.inf, np.float32)
    d[hit] = -1.0 / zbuf[hit]
    depth = np.full((H, W), np.inf, np.float32)
    depth[GY // ss:GY1 // ss, GX // ss:GX1 // ss] = d.reshape(Hw // ss, ss, Ww // ss, ss).min(axis=(1, 3))
    return full, depth


def selftest():
    """A red cube in front of a wall half way: hidden on the wall side only; a part under the
    water gets the water's colour; a Neon part glows; outlines on the silhouette."""
    ctx = Context([0, 0, 0], [0, 0, 1], water_color=(0, 0, 255), water_opacity=0.5)
    cam = {"eye": [0, 0, -10], "focus": [0, 0, 0], "fov": 70}
    ident = [1, 0, 0, 0, 1, 0, 0, 0, 1]
    world = {"solids": [{"cf": [0, 0, 0] + ident, "s": [2, 2, 2], "c": [255, 0, 0], "sh": "Block"}], "waterY": -100}
    W = H = 64
    bg = np.full((H * 2, W * 2), np.inf, np.float32)
    bg[:, :W] = 5.0  # a wall 5 studs from the camera over the left half
    im, depth = render(world, None, cam, ctx, W, H, 2, bg)
    a = np.asarray(im)  # (the cube is ±10 px around the centre of the 128 px layer)
    assert a[H, W + 5, 3] == 255 and a[H, W + 5, 0] > 150, a[H, W + 5]  # right half: the cube
    assert a[H, W - 5, 3] == 0, a[H, W - 5]  # left half: behind the wall
    assert abs(depth[H // 2, W // 2 + 2] - 9.0) < 0.2, depth[H // 2, W // 2 + 2]  # its front face
    # water: the same cube below the surface (the camera above it) is bluer
    world["waterY"] = 4
    im2, _ = render(world, None, {"eye": [0, 8, -10], "focus": [0, 0, 0], "fov": 70}, ctx, W, H, 2, None)
    p = np.asarray(im2)[H, W]
    assert p[2] > p[0] * 0.5 and p[3] == 255, p
    # neon glows past its edges, transparent faces blend
    world = {"solids": [{"cf": [0, 0, 0] + ident, "s": [2, 2, 2], "c": [0, 255, 0], "sh": "Ball", "m": 1},
                        {"cf": [3, 0, 0] + ident, "s": [2, 2, 2], "c": [255, 255, 255], "sh": "Block", "t": 0.5}],
             "waterY": -100}
    im3, _ = render(world, None, cam, ctx, W, H, 2, None)
    q = np.asarray(im3)
    r_px = int(1.0 * (H * 2 / 2) / math.tan(math.radians(35)) / 10)  # the ball's radius in px
    assert q[H, W + r_px + 3, 3] > 0, q[H, W + r_px + 3]  # glow just outside the ball
    x_t = W + int(3.0 * (H * 2 / 2) / math.tan(math.radians(35)) / 9)
    assert 100 < q[H, x_t, 3] < 160, q[H, x_t]  # the half-transparent cube
    return True
