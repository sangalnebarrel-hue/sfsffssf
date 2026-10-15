#!/usr/bin/env python3
"""Contact sheets of the living world over time (tools/preview/ambient_dump.luau output).

For every dumped view (the fishing spot's camera, the pier walk, the hub ...):
  <view>_sheet.png   every frame (default 0.25 s apart) rendered with render.py's perspective
                     rasterizer (+ terrain water with --terrain), labelled with its time;
  <view>_motion.png  the first frame with everything that MOVED during the dump painted over it
                     (per-pixel max difference against the first frame, as a red overlay) and the
                     engine's numbers for that view (parts moved per frame, tiers, by kind);
  <view>_crop.png    (with --crop X,Y,W,H in output pixels) the same region of every frame side by
                     side, enlarged — for small motion (a flag, foam, a jumping fish).

Usage:
  python3 tools/preview/ambient_sheet.py IN.json OUT_DIR [--terrain smoothgrid.bin] [--size 960]
      [--cols 4] [--views spot,pier] [--crop spot:300,200,240,140] [--gif]
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render  # noqa: E402  (tools/preview/render.py)

SS = 2


def frame_parts(view, frame):
    by_id = {p["id"]: p for p in view["scene"]}
    extra = []
    for p in frame["parts"]:
        if "id" in p:
            by_id[p["id"]] = p
        else:
            extra.append(p)
    return [p for p in by_id.values() if p.get("transparency", 0) < 0.98] + extra


def render_frame(view, frame, args, w, h):
    scene = render.Scene({"parts": frame_parts(view, frame)})
    cam = render.PerspCamera(view["eye"], view["target"], view.get("fov", 70), w, h, SS)
    mesh = render._terrain_mesh_persp(args, cam)
    buf, _ = render.render_persp(render.with_terrain(scene, mesh), cam, outlines=True, fog=args.fog)
    return render.to_image(buf, SS)


def stats_lines(view):
    s = view.get("stats") or {}
    if not s:
        return []
    kinds = ", ".join(f"{k} {v:.1f}" for k, v in sorted(s.get("byKind", {}).items(), key=lambda kv: -kv[1]))
    return [
        f"engine: {s['moved']:.1f} parts moved + {s['writes']:.1f} props per frame (peak {s['peak']}, budget "
        f"{s['budget']}); items {s['updated']:.1f} updated, {s['culled']:.1f} culled per frame; "
        f"tiers near/mid/far {s['near']}/{s['mid']}/{s['far']}",
        f"by kind (parts+props per frame): {kinds}",
    ]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("out_dir")
    ap.add_argument("--terrain", default=None)
    ap.add_argument("--size", type=int, default=960, help="frame width in pixels (16:9)")
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--views", default="")
    ap.add_argument("--crop", action="append", default=[], help="view:x,y,w,h (frame pixels); repeatable")
    ap.add_argument("--zoom", type=float, default=2.0, help="crop enlargement")
    ap.add_argument("--gif", action="store_true", help="also write <view>.gif (real speed)")
    args = ap.parse_args()

    data = json.load(open(args.input))
    os.makedirs(args.out_dir, exist_ok=True)
    if data.get("water"):
        render.WATER_COLOR = np.array(data["water"]["color"], np.float32)
        render.WATER_OPACITY = float(min(max(1.0 - data["water"].get("transparency", 0.45) + 0.1, 0.3), 0.9))
        render.TERRAIN_COLORS["Water"] = tuple(int(c) for c in render.WATER_COLOR)
    render.GRADE = data.get("grade")
    args.fog = [render.FOG_START, render.FOG_END]
    if data.get("atmosphere"):
        fog, render.FOG_TINT = render.atmosphere_fog(data["atmosphere"])
        args.fog = list(fog)
    args.terrain_step = None
    args.terrain_field = None
    if args.terrain:
        import terrain_export

        args.terrain_field = render.TerrainField(terrain_export.load_heightfield(args.terrain))

    wanted = {v for v in args.views.split(",") if v}
    crops = {}
    for c in args.crop:
        name, box = c.split(":")
        crops[name] = [int(v) for v in box.split(",")]
    w = args.size
    h = int(round(w * 9 / 16))
    font = render._font(15)
    small = render._font(13)
    for view in data["views"]:
        name = view["name"]
        if wanted and name not in wanted:
            continue
        frames = view["frames"]
        images = []
        for frame in frames:
            images.append(render_frame(view, frame, args, w, h))
            print(f"[ambient_sheet] {name} t={frame['t']:.2f}", flush=True)

        # Contact sheet.
        cols = min(args.cols, len(images))
        rows = math.ceil(len(images) / cols)
        label_h, title_h = 20, 48
        sheet = Image.new("RGB", (cols * w, title_h + rows * (h + label_h)), (236, 241, 247))
        draw = ImageDraw.Draw(sheet)
        draw.text((8, 6), f"Living world — {name}: {len(images)} frames, as the client sees them", fill=(20, 24, 30), font=font)
        for k, line in enumerate(stats_lines(view)):
            draw.text((8, 24 + k * 0), line if k == 0 else "", fill=(60, 66, 80), font=small)
        for i, (im, frame) in enumerate(zip(images, frames)):
            col, row = i % cols, i // cols
            x0, y0 = col * w, title_h + row * (h + label_h)
            sheet.paste(im, (x0, y0 + label_h))
            draw.text((x0 + 6, y0 + 3), f"t = {frame['t']:.2f} s", fill=(20, 24, 30), font=small)
        sheet.save(os.path.join(args.out_dir, f"{name}_sheet.png"))

        # What moved: max per-pixel difference against the first frame, painted red.
        base = np.asarray(images[0], np.float32)
        diff = np.zeros(base.shape[:2], np.float32)
        for im in images[1:]:
            diff = np.maximum(diff, np.abs(np.asarray(im, np.float32) - base).max(axis=2))
        mask = np.clip((diff - 6) / 40, 0, 1)[..., None]
        red = np.array([255, 30, 60], np.float32)
        overlay = base * (1 - 0.75 * mask) + red * 0.75 * mask
        motion = Image.fromarray(overlay.astype(np.uint8))
        canvas = Image.new("RGB", (w, h + 60), (236, 241, 247))
        canvas.paste(motion, (0, 60))
        d = ImageDraw.Draw(canvas)
        moved = float((diff > 12).mean()) * 100
        d.text((8, 4), f"{name}: red = moved during {frames[-1]['t']:.2f} s ({moved:.1f}% of pixels)", fill=(20, 24, 30), font=small)
        for k, line in enumerate(stats_lines(view)):
            d.text((8, 22 + 18 * k), line, fill=(60, 66, 80), font=small)
        canvas.save(os.path.join(args.out_dir, f"{name}_motion.png"))

        if name in crops:
            x, y, cw, chh = crops[name]
            z = args.zoom
            tiles = [im.crop((x, y, x + cw, y + chh)).resize((int(cw * z), int(chh * z)), Image.LANCZOS) for im in images]
            tw, th = tiles[0].size
            strip = Image.new("RGB", (tw * min(len(tiles), args.cols), th * math.ceil(len(tiles) / args.cols) + 0), (236, 241, 247))
            for i, tile in enumerate(tiles):
                strip.paste(tile, ((i % args.cols) * tw, (i // args.cols) * th))
                ImageDraw.Draw(strip).text(((i % args.cols) * tw + 4, (i // args.cols) * th + 2), f"{frames[i]['t']:.2f}s", fill=(255, 255, 255), font=small)
            strip.save(os.path.join(args.out_dir, f"{name}_crop.png"))

        if args.gif and len(images) > 1:
            step = max(frames[1]["t"] - frames[0]["t"], 0.02)
            images[0].save(
                os.path.join(args.out_dir, f"{name}.gif"),
                save_all=True,
                append_images=images[1:],
                duration=int(step * 1000),
                loop=0,
            )
        print(f"[ambient_sheet] wrote {name}_sheet.png, {name}_motion.png")


if __name__ == "__main__":
    main()
