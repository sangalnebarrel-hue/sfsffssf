#!/usr/bin/env python3
"""Detail density per map zone, and an emptiness heat map (micro-detail work).

Reads the parts JSON of export_parts.luau (bases simulated). The map is cut into 8 x 8-stud
cells; a cell counts as filled when a dressing part with a footprint under 64 studs² touches it
(the ground, floor slabs and big parts do not count). Prints per zone (pier corridors, plots, hub
plaza / beach, bridges, lagoon, beach ring, promenade, gateway/landmark band, hills): area, parts,
small parts (largest side <= 3 studs) per 1 000 studs² and the share of empty cells.

  python3 tools/preview/density.py parts.json [--heatmap out.png]

--heatmap draws the cells top-down (+X right, +Z down, like render.py's top view): RED = empty in a
close-up zone, dim = empty elsewhere. Targets (v3 detail): lagoon and beach ring <= ~70 % empty.
The zone geometry assumes the v3 ring (bases at r 312, 22.5 + k·45°).
"""

import argparse
import collections
import json
import math

import numpy as np

CELL = 8
RADIUS = 700


def aabb(p):
    x, y, z = p["cf"][:3]
    rot = np.array(p["cf"][3:]).reshape(3, 3)
    e = np.abs(rot) @ (np.array(p["size"]) / 2)
    return x - e[0], x + e[0], z - e[2], z + e[2]


def base_local(i, x, z):
    a = math.radians(22.5 + (i - 1) * 45)
    sx, sz = 312 * math.sin(a), 312 * math.cos(a)
    dx, dz = x - sx, z - sz
    return dx * math.cos(a) - dz * math.sin(a), dx * math.sin(a) + dz * math.cos(a)


def zone(x, z):
    r = math.hypot(x, z)
    th = math.degrees(math.atan2(x, z)) % 360
    for i in range(1, 9):
        lx, lz = base_local(i, x, z)
        if -72 <= lz <= 0 and abs(lx) <= 22:
            return "pier"
        if 18 <= lz <= 168 and abs(lx) <= 68:
            return "plot"
    if r < 158:
        return "hub_plaza"
    if r < 185:
        return "hub_beach"
    near_bridge = any(min(abs(th - b), 360 - abs(th - b)) < math.degrees(12 / max(r, 1)) for b in (0, 90, 180, 270))
    if r < 296:
        return "bridge" if near_bridge else "lagoon"
    if r < 312:
        return "beach_ring"
    if r < 330:
        return "promenade"
    if r < 480:
        return "band"
    if r < 640:
        return "hills"
    return "ocean"


ZONES = ["pier", "plot", "hub_plaza", "hub_beach", "bridge", "lagoon", "beach_ring", "promenade", "band", "hills"]
HOT = {"pier", "beach_ring", "promenade", "lagoon", "hub_beach", "hub_plaza", "plot"}
BASE = {
    "pier": (150, 110, 70), "plot": (110, 170, 90), "hub_plaza": (190, 170, 130), "hub_beach": (220, 200, 150),
    "bridge": (170, 130, 90), "lagoon": (70, 150, 190), "beach_ring": (225, 205, 150), "promenade": (200, 150, 110),
    "band": (140, 180, 120), "hills": (120, 150, 110), "ocean": (40, 90, 140),
}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("parts")
    ap.add_argument("--heatmap")
    args = ap.parse_args()
    parts = json.load(open(args.parts))["parts"]
    n = 2 * RADIUS // CELL
    filled = np.zeros((n, n), bool)
    stats = collections.defaultdict(collections.Counter)
    for p in parts:
        if p["transparency"] >= 0.98:
            continue
        x0, x1, z0, z1 = aabb(p)
        zn = zone((x0 + x1) / 2, (z0 + z1) / 2)
        st = stats[zn]
        st["parts"] += 1
        if p["path"].startswith("Workspace.Map.Ground"):
            continue
        if (x1 - x0) * (z1 - z0) >= 64:
            continue
        st["dressing"] += 1
        if max(p["size"]) <= 3:
            st["micro"] += 1
        for gx in range(int((x0 + RADIUS) // CELL), int((x1 + RADIUS) // CELL) + 1):
            for gz in range(int((z0 + RADIUS) // CELL), int((z1 + RADIUS) // CELL) + 1):
                if 0 <= gx < n and 0 <= gz < n:
                    filled[gz, gx] = True
    area, empty = collections.Counter(), collections.Counter()
    zones = {}
    for gz in range(n):
        for gx in range(n):
            x, z = gx * CELL - RADIUS + CELL / 2, gz * CELL - RADIUS + CELL / 2
            if math.hypot(x, z) > RADIUS:
                continue
            zn = zone(x, z)
            zones[(gx, gz)] = zn
            area[zn] += 1
            if not filled[gz, gx]:
                empty[zn] += 1
    print(f"{'zone':12s} {'area st2':>9s} {'parts':>6s} {'decor':>6s} {'small':>6s} {'small/1k st2':>12s} {'empty cells':>11s}")
    for zn in ZONES:
        a = area[zn] * CELL * CELL
        st = stats[zn]
        print(
            f"{zn:12s} {a:9d} {st['parts']:6d} {st['dressing']:6d} {st['micro']:6d}"
            f" {1000 * st['micro'] / max(a, 1):12.2f} {100 * empty[zn] / max(area[zn], 1):10.0f}%"
        )
    if args.heatmap:
        from PIL import Image, ImageDraw

        px = 5
        img = Image.new("RGB", (n * px, n * px + 40), (30, 30, 36))
        dr = ImageDraw.Draw(img)
        for (gx, gz), zn in zones.items():
            c = BASE[zn]
            if not filled[gz, gx]:
                c = (235, 60, 60) if zn in HOT else tuple(int(v * 0.55) for v in c)
            dr.rectangle([gx * px, gz * px, gx * px + px - 1, gz * px + px - 1], fill=c)
        dr.text((10, n * px + 12), "8x8-stud cells: RED = empty in a close-up zone, dim = empty elsewhere. +X right, +Z down.", fill=(240, 240, 240))
        img.save(args.heatmap)
        print("heat map:", args.heatmap)


if __name__ == "__main__":
    main()
