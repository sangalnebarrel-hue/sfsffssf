#!/usr/bin/env python3
"""Product shots of the voxel rods and fish exported by gear_export.luau.

    python3 tools/preview/gear_render.py gear.json --out-dir DIR [--bg F4F7FB] [--only ID ...]

Per model (ids from the specs), in DIR:
    <id>_side.png      orthographic side view on the cell grid (1 cell = 0.25 studs, a darker
                       line every 4 cells = 1 stud); head / tip points right
    <id>_front.png     orthographic view from the front (fish: the face; rods: down the tip)
    <id>_iso.png       3/4 view from above
    <id>_<Mutation>.png  fish only: 3/4 view of each mutation (Gold, Neon, Rainbow)
    <id>_bobber.png    rods only: 3/4 view of the bobber (float)
    sheet_<id>.png     everything above on one labelled sheet (for reviewing)
All views of one kind share one scale, so sizes compare 1:1 (a Mythic fish really is bigger).
Neon blocks get a soft glow, like Roblox's bloom on Neon parts.
"""

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render as R  # noqa: E402

# Light from the front-right-top, so the side (+Z) and front (+X) faces are both lit.
R.SUN = np.array([0.45, 1.0, 0.65]) / np.linalg.norm([0.45, 1.0, 0.65])
R.AMBIENT = 0.5
SS = 3
ISO_AZ, ISO_EL = 38.0, 24.0

# Fixed pixel budgets per view; the scale (px per stud) is shared by a kind.
VIEW = {
    "rod": {"side": (1500, 300), "front": (300, 300), "iso": (1100, 520), "bobber": (360, 360)},
    "fish": {"side": (1100, 560), "front": (560, 560), "iso": (900, 560), "mutation": (560, 360)},
}


def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) for i in (0, 2, 4)], np.float32)


def scene_of(parts):
    return R.Scene({"parts": parts})


def extents(parts):
    sc = scene_of(parts)
    return sc.aabb_min.min(0), sc.aabb_max.max(0)


def shoot(parts, forward, scale, size, bg, up_hint=(0, 1, 0), orbit=None, outlines=True):
    """Render parts centred in a size=(w, h) image at `scale` px/stud; returns (image, camera)."""
    R.BACKGROUND_TOP = bg
    R.BACKGROUND_BOTTOM = bg
    sc = scene_of(parts)
    lo, hi = sc.aabb_min.min(0), sc.aabb_max.max(0)
    centre = (lo + hi) / 2
    w, h = size
    if orbit:
        cam = R.Camera.orbit(orbit[0], orbit[1], centre, scale, w, h, SS)
    else:
        cam = R.Camera(forward, centre, scale, w, h, SS, up_hint)
    im = R.to_image(R.render(sc, cam, outlines=outlines), SS)
    glow = neon_glow(parts, cam, size, scale)
    if glow is not None:
        im = Image.fromarray(np.minimum(np.asarray(im, np.float32) + glow, 255).astype(np.uint8))
    return im, cam


def neon_glow(parts, cam, size, scale):
    neon = [p for p in parts if p.get("material") == "Neon"]
    if not neon:
        return None
    R.BACKGROUND_TOP = np.zeros(3, np.float32)
    R.BACKGROUND_BOTTOM = np.zeros(3, np.float32)
    # occluders black, neon parts in their colour
    dark = [dict(p, material="SmoothPlastic", color=[0, 0, 0]) for p in parts if p.get("material") != "Neon"]
    sc = scene_of(neon + dark)
    sc.face_rgb[~sc.face_unlit] = 0
    buf = R.render(sc, cam, outlines=False)
    im = R.to_image(buf, SS).filter(ImageFilter.GaussianBlur(radius=float(max(4.0, scale * 0.12))))
    return np.asarray(im, np.float32) * 0.6


def fit_scale(boxes, size, view_axes, margin=0.12):
    """Largest px/stud so every box (lo, hi) fits a view of `size` along view_axes (ix, iy)."""
    w, h = size
    best = math.inf
    for lo, hi in boxes:
        ext = hi - lo
        ex = ext[view_axes[0]] if not callable(view_axes[0]) else view_axes[0](ext)
        ey = ext[view_axes[1]] if not callable(view_axes[1]) else view_axes[1](ext)
        best = min(best, w * (1 - 2 * margin) / max(ex, 1e-3), h * (1 - 2 * margin) / max(ey, 1e-3))
    return best


def iso_extent_w(ext):
    az = math.radians(ISO_AZ)
    return abs(ext[0] * math.cos(az)) + abs(ext[2] * math.sin(az))


def iso_extent_h(ext):
    az, el = math.radians(ISO_AZ), math.radians(ISO_EL)
    depth = abs(ext[0] * math.sin(az)) + abs(ext[2] * math.cos(az))
    return ext[1] * math.cos(el) + depth * math.sin(el)


def draw_grid(im, cam, cell, bg):
    """Cell grid on the background of an orthographic side view (spec origin = world 0)."""
    a = np.asarray(im).copy()
    bgmask = np.all(a == np.round(bg).astype(np.uint8), axis=2)
    h, w = bgmask.shape
    ox, oy, _ = cam.project(np.zeros((1, 3)), ss=1)
    step = cell * cam.scale
    line = np.zeros((h, w), np.uint8)  # 0 none, 1 cell, 2 stud
    for axis, origin, n in ((0, ox[0], w), (1, oy[0], h)):
        k0 = math.floor(-origin / step) - 1
        k1 = math.ceil((n - origin) / step) + 1
        for k in range(k0, k1 + 1):
            p = int(round(origin + k * step))
            if 0 <= p < n:
                level = 2 if k % 4 == 0 else 1
                if axis == 0:
                    line[:, p] = np.maximum(line[:, p], level)
                else:
                    line[p, :] = np.maximum(line[p, :], level)
    shade = {1: 0.93, 2: 0.82}
    for level, f in shade.items():
        m = bgmask & (line == level)
        a[m] = (a[m].astype(np.float32) * f).astype(np.uint8)
    return Image.fromarray(a)


FONT_PATH = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"  # has Cyrillic


def font(size):
    try:
        return ImageFont.truetype(FONT_PATH, size)
    except OSError:
        return R._font(size)


def label(im, text, size=24):
    d = ImageDraw.Draw(im)
    R._text(d, (14, 10), text, font(size))
    return im


def sheet(tiles, title, bg):
    """Lay out [(image, caption), ...] rows: first tile full width, the rest in a row below."""
    pad = 18
    first, rest = tiles[0], tiles[1:]
    row_w = sum(t[0].size[0] for t in rest) + pad * (len(rest) - 1) if rest else 0
    row_h = max((t[0].size[1] for t in rest), default=0)
    W = max(first[0].size[0], row_w) + 2 * pad
    H = 64 + first[0].size[1] + (row_h + pad if rest else 0) + 2 * pad
    out = Image.new("RGB", (W, H), tuple(int(v) for v in bg))
    d = ImageDraw.Draw(out)
    R._text(d, (pad, 14), title, font(30))
    y = 64
    out.paste(label(first[0].copy(), first[1]), (pad, y))
    y += first[0].size[1] + pad
    x = pad
    for im, cap in rest:
        out.paste(label(im.copy(), cap, 22), (x, y))
        x += im.size[0] + pad
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("gear_json")
    ap.add_argument("--out-dir", required=True)
    ap.add_argument("--bg", default="F4F7FB", help="background colour RRGGBB")
    ap.add_argument("--only", nargs="*", default=None, help="render only these ids")
    args = ap.parse_args(argv)
    bg = hex_rgb(args.bg)
    data = json.load(open(args.gear_json))
    cell = data.get("cell", 0.25)
    os.makedirs(args.out_dir, exist_ok=True)

    models = data["models"]
    by_id = {}
    for m in models:
        by_id.setdefault(m["id"], {})[m["variant"]] = m

    # One scale per kind and view, from the biggest model of that kind.
    scales = {}
    for kind in ("rod", "fish"):
        base = [v["base"] for v in by_id.values() if v["base"]["kind"] == kind]
        if not base:
            continue
        boxes = [extents(m["parts"]) for m in base]
        V = VIEW[kind]
        scales[kind] = {
            "side": fit_scale(boxes, V["side"], (0, 1), 0.06),
            "front": fit_scale(boxes, V["front"], (2, 1)),
            "iso": fit_scale(boxes, V["iso"], (iso_extent_w, iso_extent_h), 0.08),
        }
        if kind == "fish":
            scales[kind]["mutation"] = fit_scale(boxes, V["mutation"], (iso_extent_w, iso_extent_h), 0.08)
        else:
            bob = [extents(v["bobber"]["parts"]) for v in by_id.values() if "bobber" in v]
            scales[kind]["bobber"] = min(
                fit_scale(bob, V["bobber"], (iso_extent_w, iso_extent_h), 0.15), scales[kind]["side"] * 2.5
            )

    for mid, variants in by_id.items():
        if args.only and mid not in args.only:
            continue
        base = variants["base"]
        kind = base["kind"]
        V, S = VIEW[kind], scales[kind]
        parts = base["parts"]
        side, cam = shoot(parts, (0, 0, -1), S["side"], V["side"], bg)
        side = draw_grid(side, cam, cell, bg)
        front, _ = shoot(parts, (-1, 0, 0), S["front"], V["front"], bg)
        iso, _ = shoot(parts, None, S["iso"], V["iso"], bg, orbit=(ISO_AZ, ISO_EL))
        side.save(f"{args.out_dir}/{mid}_side.png")
        front.save(f"{args.out_dir}/{mid}_front.png")
        iso.save(f"{args.out_dir}/{mid}_iso.png")
        tiles = [(side, f"сбоку · сетка 1 клетка = {cell:g} стада"), (front, "спереди"), (iso, "3/4")]
        if kind == "fish":
            for mut in ("Gold", "Neon", "Rainbow"):
                if mut in variants:
                    im, _ = shoot(variants[mut]["parts"], None, S["mutation"], V["mutation"], bg, orbit=(ISO_AZ, ISO_EL))
                    im.save(f"{args.out_dir}/{mid}_{mut}.png")
                    tiles.append((im, mut))
            title = f"{base['title']} · {base['rarity']} · {base['blockCount']} блоков · длина {base['length']:g} кл."
        else:
            if "bobber" in variants:
                im, _ = shoot(variants["bobber"]["parts"], None, S["bobber"], V["bobber"], bg, orbit=(ISO_AZ, ISO_EL))
                im.save(f"{args.out_dir}/{mid}_bobber.png")
                tiles.append((im, "поплавок"))
            title = f"{base['title']} · уровень {base['tier']} · {base['blockCount']} блоков · длина {base['length']:g} кл."
        sheet(tiles, title, bg).save(f"{args.out_dir}/sheet_{mid}.png")
        print(f"[gear] {mid}: {base['blockCount']} blocks -> {args.out_dir}/sheet_{mid}.png")


if __name__ == "__main__":
    main()
