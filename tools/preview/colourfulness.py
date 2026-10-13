#!/usr/bin/env python3
"""Hasler–Süsstrunk colourfulness of rendered previews (art direction v4 check).

    python3 tools/preview/colourfulness.py DIR/persp_*.png

Scale: 33 moderately, 45 averagely, 59 quite, 82 highly, 109 extremely colourful.
Target for the map's player and overview views: about 75–105 — "highly" colourful like the
reference simulators, below the eye-searing v3 (115–136). The info box at the top is skipped.
"""

import sys

import numpy as np
from PIL import Image


def colourfulness(path, skip_rows=130):
    a = np.asarray(Image.open(path).convert("RGB"), np.float32)[skip_rows:]
    rg = a[..., 0] - a[..., 1]
    yb = 0.5 * (a[..., 0] + a[..., 1]) - a[..., 2]
    return float(np.hypot(rg.std(), yb.std()) + 0.3 * np.hypot(rg.mean(), yb.mean()))


if __name__ == "__main__":
    for p in sys.argv[1:]:
        c = colourfulness(p)
        verdict = "dull" if c < 70 else "garish" if c > 110 else "ok"
        print(f"{c:6.1f}  {verdict:6s}  {p}")
