#!/usr/bin/env python3
"""Flat-screen KPI of rendered views (micro-detail work, see tools/preview/README.md).

Share of 40 x 40-px tiles with almost no edges (Sobel magnitude > 18 on < 1.5 % of the tile's
pixels) = big featureless surfaces in that view; the info box at the top is skipped. Printed for
the whole frame and for its lower half (the foreground, where flat decks and lawns show most).

  python3 tools/preview/flatness.py view1.png [view2.png ...]

Target (v3 detail): the fishing-spot view's lower half <= ~30 %.
"""

import sys

import numpy as np
from PIL import Image


def flat(path, tile=40, edge=18, share=0.015, top=130):
    im = np.asarray(Image.open(path).convert("L"), dtype=np.float32)
    gx = np.zeros_like(im)
    gy = np.zeros_like(im)
    gx[:, 1:-1] = im[:, 2:] - im[:, :-2]
    gy[1:-1, :] = im[2:, :] - im[:-2, :]
    mag = np.hypot(gx, gy)
    h, w = im.shape

    def count(y0):
        tot = flt = 0
        for y in range(y0, h - tile + 1, tile):
            for x in range(0, w - tile + 1, tile):
                tot += 1
                if (mag[y : y + tile, x : x + tile] > edge).mean() < share:
                    flt += 1
        return 100.0 * flt / max(tot, 1)

    return count(top), count(h // 2)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    for p in sys.argv[1:]:
        a, b = flat(p)
        print(f"{p.split('/')[-1]:32s} flat tiles {a:5.1f}%   lower half {b:5.1f}%")


if __name__ == "__main__":
    main()
