#!/usr/bin/env python3
"""Eye-level camera presets of the micro-detail work, as render.py --persp arguments.

  python3 tools/preview/views.py [base] [name ...]     # prints "name eye,target,fov" lines

Views of base `base` (default 1; the v3 ring: bases at r 312, 22.5 + k·45°, base-local -Z to the
lagoon, y 0 = GroundTop 4): spot_default (the fishing-spot follow camera: 12.5 studs behind, 18°
down), pier_walk, spot_left / spot_right / spot_back, spawn, yard_eye, yard_back, house_wall,
beach / beach2 / beach_low (the ring beach either side of the pier), lagoon_from_pier, and the
shared ring views promenade_walk(2), hub_plaza, hub_avenue, hub_beach, hub_shop. Example:

  ARGS=$(python3 tools/preview/views.py 1 spot_default pier_walk | awk '{print "--persp " $2}')
  python3 tools/preview/render.py parts.json --terrain smoothgrid.bin --out-dir out $ARGS
"""

import math
import sys


def base_point(i, lx, ly, lz):
    a = math.radians(22.5 + (i - 1) * 45)
    sx, sz = 312 * math.sin(a), 312 * math.cos(a)
    X = (math.cos(a), -math.sin(a))
    Z = (math.sin(a), math.cos(a))
    return (sx + lx * X[0] + lz * Z[0], 4 + ly, sz + lx * X[1] + lz * Z[1])


def polar(theta, r, y):
    a = math.radians(theta)
    return (r * math.sin(a), y, r * math.cos(a))


def arg(eye, target, fov=70):
    return ",".join(f"{v:.1f}" for v in (*eye, *target)) + f",{fov}"


def views(b):
    L = lambda *p: base_point(b, *p)  # noqa: E731
    out = []
    f = (0, 1.03 + 4.6, -67.5)  # the follow camera's focus over the fishing spot
    cam = (0, f[1] + 12.5 * math.sin(math.radians(18)), f[2] + 12.5 * math.cos(math.radians(18)))
    tgt = (0, f[1] - 100 * math.tan(math.radians(18)), f[2] - 100)
    out.append(("spot_default", arg(L(*cam), L(*tgt))))
    out.append(("pier_walk", arg(L(0, 9.5, -6), L(0, 4, -60))))
    for name, ang in (("spot_left", -75), ("spot_right", 75), ("spot_back", 180)):
        a = math.radians(ang)
        dx, dz = math.sin(a), -math.cos(a)
        out.append((name, arg(L(f[0] - dx * 12, f[1] + 3.5, f[2] - dz * 12), L(f[0] + dx * 100, 2, f[2] + dz * 100))))
    out.append(("spawn", arg(L(0, 9.5, 48), L(0, 4, 0))))
    out.append(("yard_eye", arg(L(-40, 6, 30), L(30, 4, 100))))
    out.append(("yard_back", arg(L(30, 6, 150), L(-20, 4, 40))))
    out.append(("house_wall", arg(L(-30, 6, 112), L(10, 8, 150))))
    ba = 22.5 + (b - 1) * 45
    out.append(("beach", arg(polar(ba + 9, 304, 7.5), polar(ba + 20, 298, 2.5))))
    out.append(("beach2", arg(polar(ba - 9, 304, 7.5), polar(ba - 20, 298, 2.5))))
    out.append(("beach_low", arg(polar(ba + 12, 300, 5), polar(ba + 18, 299, 2.5))))
    out.append(("lagoon_from_pier", arg(L(-14, 8, -74), L(-80, -2, -140))))
    out.append(("promenade_walk", arg(polar(10, 321, 10), polar(0, 321, 8))))
    out.append(("promenade_walk2", arg(polar(35, 321, 10), polar(45, 321, 8))))
    out.append(("hub_plaza", arg(polar(45, 110, 10), (0, 14, 0))))
    out.append(("hub_avenue", arg(polar(0, 140, 10), polar(0, 20, 8))))
    out.append(("hub_beach", arg(polar(30, 160, 8), polar(80, 165, 4))))
    out.append(("hub_shop", arg(polar(60, 120, 9), polar(40, 70, 10))))
    return out


def main():
    b = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    names = set(sys.argv[2:])
    for name, v in views(b):
        if not names or name in names:
            print(name, v)


if __name__ == "__main__":
    main()
