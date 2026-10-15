#!/usr/bin/env python3
"""Eye-level camera presets of the micro-detail work, as render.py --persp arguments.

  python3 tools/preview/views.py [base] [name ...] [--parts parts.json]   # "name eye,target,fov" lines

Views of base `base` (default 1; the v3 ring: bases at r 312, 22.5 + k·45°, base-local -Z to the
lagoon, y 0 = GroundTop 4): spot_default (the fishing-spot follow camera: 12.5 studs behind, 18°
down), pier_walk, spot_left / spot_right / spot_back, spawn, yard_eye, yard_back, house_wall,
beach / beach2 / beach_low (the ring beach either side of the pier), lagoon_from_pier, and the
shared ring views promenade_walk(2), hub_plaza, hub_avenue, hub_beach, hub_shop. Example:

  ARGS=$(python3 tools/preview/views.py 1 spot_default pier_walk | awk '{print "--persp " $2}')
  python3 tools/preview/render.py parts.json --terrain smoothgrid.bin --out-dir out $ARGS

The presets keep their eyes out of the geometry of the current map (v3 fix W8: yard_back,
house_wall, hub_plaza, hub_shop and spot_right used to sit in a wall, the FishMarket, a shop or a
pavilion post). With --parts (export_parts.luau JSON) every eye is also checked like render.py's
ring preset: an eye inside (or within 1 stud of) a part steps along its view direction until it is
free (up to 40 studs), then stands on the surface found below at its preset height over the ground.
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
    for name, ang, back in (("spot_left", -75, 12), ("spot_right", 75, 8), ("spot_back", 180, 12)):
        a = math.radians(ang)
        dx, dz = math.sin(a), -math.cos(a)
        eye = L(f[0] - dx * back, f[1] + 3.5, f[2] - dz * back)
        out.append((name, arg(eye, L(f[0] + dx * 100, 2, f[2] + dz * 100))))
    out.append(("spawn", arg(L(0, 9.5, 48), L(0, 4, 0))))
    out.append(("yard_eye", arg(L(-40, 6, 30), L(30, 4, 100))))
    out.append(("yard_back", arg(L(0, 11, 125.5), L(0, 5, 30))))
    out.append(("house_wall", arg(L(-9, 10.5, 107), L(10, 8, 150))))
    ba = 22.5 + (b - 1) * 45
    out.append(("beach", arg(polar(ba + 9, 304, 7.5), polar(ba + 20, 298, 2.5))))
    out.append(("beach2", arg(polar(ba - 9, 304, 7.5), polar(ba - 20, 298, 2.5))))
    out.append(("beach_low", arg(polar(ba + 12, 300, 5), polar(ba + 18, 299, 2.5))))
    out.append(("lagoon_from_pier", arg(L(-14, 8, -74), L(-80, -2, -140))))
    out.append(("promenade_walk", arg(polar(10, 321, 10), polar(0, 321, 8))))
    out.append(("promenade_walk2", arg(polar(35, 321, 10), polar(45, 321, 8))))
    out.append(("hub_plaza", arg(polar(45, 70, 10), (0, 14, 0))))
    out.append(("hub_avenue", arg(polar(0, 140, 10), polar(0, 20, 8))))
    out.append(("hub_beach", arg(polar(30, 160, 8), polar(80, 165, 4))))
    out.append(("hub_shop", arg(polar(30, 48, 9), polar(45, 76, 9))))
    return out


def unblock(views_list, parts_json):
    """Moves every eye that is inside (or within 1 stud of) a part along its view direction until
    it is free, then onto the surface found below at its height over the ground (render.py's
    ring-preset rule). Prints a note on stderr for every eye it moved."""
    import json
    import os

    import numpy as np

    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import render

    with open(parts_json, "r", encoding="utf-8") as fh:
        scene = render.Scene(json.load(fh))
    out = []
    for name, v in views_list:
        n = [float(x) for x in v.split(",")]
        eye, target, fov = np.array(n[0:3]), np.array(n[3:6]), n[6]
        if render._inside_part(scene, eye, 1.0):
            lift = max(eye[1] - render._ground_y(scene, None, eye[0], eye[2], below=eye[1]), 2.0)
            d = target - eye
            d[1] = 0
            d /= max(np.linalg.norm(d), 1e-6)
            for step in np.arange(1.0, 41.0, 1.0):
                q = eye + d * step
                q[1] = render._ground_y(scene, None, q[0], q[2], below=eye[1] + 2) + lift
                if not render._inside_part(scene, q, 1.0):
                    print(f"[views] {name}: eye moved {step:.0f} studs out of the geometry", file=sys.stderr)
                    eye = q
                    break
            else:
                print(f"[views] {name}: eye still inside a part", file=sys.stderr)
        out.append((name, arg(tuple(eye), tuple(target), int(fov) if fov == int(fov) else fov)))
    return out


def main():
    argv = sys.argv[1:]
    parts_json = None
    if "--parts" in argv:
        i = argv.index("--parts")
        parts_json = argv[i + 1]
        del argv[i : i + 2]
    b = int(argv[0]) if argv else 1
    names = set(argv[1:])
    chosen = [(name, v) for name, v in views(b) if not names or name in names]
    if parts_json:
        chosen = unblock(chosen, parts_json)
    for name, v in chosen:
        print(name, v)


if __name__ == "__main__":
    main()
