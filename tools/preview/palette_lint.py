#!/usr/bin/env python3
"""Palette lint: how loud is the map? (art direction v4, tools/builder/Palette.luau)

    python3 tools/preview/palette_lint.py parts.json [--top 25] [--group-depth 3]

Reads export_parts.luau JSON and measures colour by visible surface area (each part's top face
plus its four sides; underwater ground and invisible parts are skipped):
  * loud area: saturation > 0.6 and value > 0.8 (HSV) — the "candy" colours the art direction
    keeps to small accents;
  * neon area: material Neon;
  * grey area: saturation < 0.15 (snow, white trims and glass excluded: value > 0.92) — too much of
    it reads as unpainted default parts (the v4 overcorrection);
  * per group (Map.<child>.<child> and the bases), the share of loud and grey area, mean value,
    and the biggest loud parts.
Targets (art direction v4): loud 1–4 % of the map (accents exist, nothing big is candy), grey <= 9 %.
Exit code 1 when a single loud part is larger than --max-loud-part studs² (default 400), when the
whole map is louder than 6 % or greyer than 12 %.
"""

import argparse
import colorsys
import json
import sys
from collections import defaultdict

LOUD_S, LOUD_V = 0.6, 0.8
GREY_S, WHITE_V = 0.15, 0.92


def hsv(c):
    return colorsys.rgb_to_hsv(c[0] / 255, c[1] / 255, c[2] / 255)


def area(p):
    """Top face + four sides of the part's box (bottoms are rarely seen)."""
    x, y, z = p["size"]
    return x * z + 2 * y * (x + z)


def group_of(path, depth):
    if path.startswith("VirtualBase"):
        rest = path.split(":", 1)[1].split(".")  # ServerStorage.BaseTemplate.X.Y
        return "Base." + ".".join(rest[2 : 2 + max(depth - 2, 1)])
    parts = path.split(".")
    if parts[:2] == ["Workspace", "Map"]:
        return ".".join(parts[2 : 2 + depth - 1]) or "Map"
    return ".".join(parts[: depth])


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("parts_json")
    ap.add_argument("--top", type=int, default=25, help="list this many of the biggest loud parts")
    ap.add_argument("--group-depth", type=int, default=2, help="group by this many path levels below Map")
    ap.add_argument("--max-loud-part", type=float, default=400.0, help="fail above this loud area (studs²)")
    ap.add_argument("--only", default=None, help="only parts whose path contains this text")
    args = ap.parse_args(argv)
    data = json.load(open(args.parts_json))

    total = loud = neon = grey = 0.0
    groups = defaultdict(lambda: [0.0, 0.0, 0.0, 0.0, 0.0])  # area, loud, neon, grey, value*area
    louds = []
    for p in data["parts"]:
        path = p.get("path", "")
        if args.only and args.only not in path:
            continue
        if p.get("kind") == "water" or p.get("transparency", 0) >= 0.9 or ".Underwater." in path:
            continue
        a = area(p)
        h, s, v = hsv(p["color"])
        g = groups[group_of(path, args.group_depth)]
        total += a
        g[0] += a
        g[4] += v * a
        if p.get("material") == "Neon":
            neon += a
            g[2] += a
        elif s > LOUD_S and v > LOUD_V:
            loud += a
            g[1] += a
            louds.append((a, path, p["size"], p["color"]))
        elif s < GREY_S and v <= WHITE_V and p.get("material") != "Glass" and p.get("transparency", 0) < 0.3:
            grey += a
            g[3] += a

    T = max(total, 1)
    print(
        f"visible area {total:,.0f} studs²: loud {100 * loud / T:.1f}% (target 1–4), grey {100 * grey / T:.1f}% "
        f"(target <= 9), neon {100 * neon / T:.2f}%"
    )
    print("\ngroups (loud % / grey % / mean value):")
    rows = sorted(groups.items(), key=lambda kv: -kv[1][0])
    for name, (a, l, n, gr, va) in rows[:28]:
        print(f"  {name:48s} loud {100 * l / a:5.1f}%  grey {100 * gr / a:5.1f}%  value {va / a:4.2f}  ({a:,.0f} studs²)")
    louds.sort(reverse=True)
    print(f"\nbiggest loud parts (S > {LOUD_S}, V > {LOUD_V}):")
    for a, path, size, color in louds[: args.top]:
        print(f"  {a:8.0f}  {path}  size {[round(x, 1) for x in size]}  rgb{tuple(color)}")
    status = 0
    worst = louds[0][0] if louds else 0
    if worst > args.max_loud_part:
        print(f"\nFAIL: a loud part covers {worst:.0f} studs² (> {args.max_loud_part:g})")
        status = 1
    if not args.only and loud / T > 0.06:
        print(f"FAIL: the map is too loud ({100 * loud / T:.1f}% > 6%)")
        status = 1
    if not args.only and grey / T > 0.12:
        print(f"FAIL: the map is too grey ({100 * grey / T:.1f}% > 12%)")
        status = 1
    if not args.only and loud / T < 0.01:
        print(f"WARN: hardly any accent colour ({100 * loud / T:.2f}% < 1%) — is the map getting dull?")
    if status == 0:
        print("\nOK")
    return status


if __name__ == "__main__":
    sys.exit(main())
