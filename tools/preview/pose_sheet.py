#!/usr/bin/env python3
"""Contact sheet of the fisher animation (tools/preview/pose_dump.luau output).

Every frame is drawn twice with render.py's perspective rasterizer:
  game  the Roblox default camera the fisher's own player has while fishing: 12.5 studs behind
        the focus (HumanoidRootPart + 1.5 up + Humanoid.CameraOffset), 18 deg down, FOV 70 —
        the GUI previews' camera; other players see him from about here too;
  side  from his right, 15 studs away, level with the chest (rod angle, lean, crouch).
The dumped parts are what a WATCHER's client sees (client-local joint poses, bent rod, bobber,
leaping / held fish), with the pier around and a water plane.

Usage:
  python3 tools/preview/pose_sheet.py IN.json OUT.png [--cols 5] [--cell 360x250] [--views game,side]
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

DISTANCE, PITCH, FOV = 12.5, 18.0, 70.0
SIDE_DISTANCE = 15.0
SS = 2


def _vec(v):
    return np.asarray(v, float)


def cameras(frame):
    focus = _vec(frame["focus"])
    look = _vec(frame["look"])
    look = look / max(np.linalg.norm(look), 1e-9)
    right = _vec(frame["right"])
    pitch = math.radians(PITCH)
    direction = look * math.cos(pitch) + np.array([0.0, -math.sin(pitch), 0.0])
    game = (focus - direction * DISTANCE, focus)
    root = _vec(frame.get("root", focus - np.array([0.0, 2.5, 0.0])))
    side_target = root + look * 2.5 + np.array([0.0, 1.2, 0.0])
    side = (side_target + right * SIDE_DISTANCE + np.array([0.0, 1.0, 0.0]), side_target)
    views = {"game": game, "side": side}
    close = frame.get("close")
    if close:  # fx_dump.luau: a close-up camera per frame (eye, target, fov)
        views["close"] = (_vec(close["eye"]), _vec(close["target"]))
    return views


# The side view shows only the fisher, his rod and FX on a plain deck (the pier would hide him).
def side_scene(frame):
    root = _vec(frame.get("root", frame["focus"]))
    deck = {
        "name": "Deck",
        "shape": "Block",
        "cf": [root[0], root[1] - 3.5, root[2], 1, 0, 0, 0, 1, 0, 0, 0, 1],
        "size": [10, 1, 10],
        "color": [176, 132, 92],
        "transparency": 0,
    }
    water = {
        "name": "Water",
        "kind": "water",
        "shape": "Block",
        "cf": [root[0], root[1] - 5.5, root[2], 1, 0, 0, 0, 1, 0, 0, 0, 1],
        "size": [200, 1, 200],
        "color": [40, 120, 205],
        "transparency": 0.45,
    }
    return [deck, water]


def draw_cell(scene_parts, frame, view, w, h):
    eye, target = cameras(frame)[view]
    static = scene_parts if view in ("game", "close") else side_scene(frame)
    scene = render.Scene({"parts": static + frame["parts"]})
    fov = FOV if view == "game" else 50.0
    if view == "close":
        fov = float(frame["close"].get("fov", 50.0))
    cam = render.PerspCamera(eye, target, fov, w, h, SS)
    buf, _ = render.render_persp(scene, cam, outlines=True, fog=(400.0, 2000.0))
    return render.to_image(buf, SS)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input")
    ap.add_argument("output")
    ap.add_argument("--cols", type=int, default=5)
    ap.add_argument("--cell", default="360x250")
    ap.add_argument("--views", default="game,side")
    ap.add_argument("--only", default="", help="comma-separated frame labels (substring match)")
    args = ap.parse_args()

    data = json.load(open(args.input))
    w, h = (int(v) for v in args.cell.split("x"))
    views = [v for v in args.views.split(",") if v]
    frames = data["frames"]
    if args.only:
        keys = [k.strip() for k in args.only.split(",")]
        frames = [f for f in frames if any(k in f["label"] for k in keys)]
    scene_parts = data["scene"]["parts"]
    cols = min(args.cols, len(frames))
    rows = math.ceil(len(frames) / cols)
    label_h = 18
    cell_h = h * len(views) + label_h
    title_h = 30
    sheet = Image.new("RGB", (cols * w, title_h + rows * cell_h), (236, 241, 247))
    draw = ImageDraw.Draw(sheet)
    font = render._font(14)
    small = render._font(12)
    if data["mode"] == "fx":
        heading = (f"Fishing world FX (fx_dump.luau, {data['rig']}) — views: {', '.join(views)} "
                   "(close = a close-up of the segment). As the fisher's own client sees it.")
    else:
        heading = (f"Fisher animation ({data['mode']}, {data['rig']}) — top: default camera behind the fisher; "
                   "bottom: side view from his right. As another player's client sees it.")
    draw.text((8, 7), heading, fill=(20, 24, 30), font=font)
    for i, frame in enumerate(frames):
        col, row = i % cols, i // cols
        x0, y0 = col * w, title_h + row * cell_h
        for v, view in enumerate(views):
            im = draw_cell(scene_parts, frame, view, w, h)
            sheet.paste(im, (x0, y0 + label_h + v * h))
        phase = frame.get("phase", "")
        bend = frame.get("bend")
        extra = ""
        if phase and data["mode"] == "timeline":
            extra = f"  [{phase}" + (f", rod {bend:.0f}°" if bend is not None and bend > 1 else "") + "]"
        draw.text((x0 + 6, y0 + 2), f"{i + 1}. {frame['label']}{extra}", fill=(20, 24, 30), font=small)
        draw.rectangle([x0, y0, x0 + w - 1, y0 + cell_h - 1], outline=(180, 188, 200))
    sheet.save(args.output)
    print(f"wrote {args.output} ({len(frames)} frames)")


if __name__ == "__main__":
    main()
