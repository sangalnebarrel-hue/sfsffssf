"""Colour emoji like Roblox draws them: Twemoji Mozilla (a COLRv0 TrueType font) rasterised here.

Roblox ships `content/fonts/TwemojiMozilla.ttf` and draws emoji with it: flat Twemoji shapes, no
outline. Pillow cannot draw COLR layers (the base glyphs are empty), so this module reads the font
itself — no fontTools needed:

  * cmap (format 12 / 4) → glyph id of the cluster's first code point (VS16 / VS15 are skipped;
    ZWJ and flag sequences fall back to their first code point);
  * COLR v0 → the glyph's layers (glyph id + palette index), CPAL palette 0 → their colours;
  * glyf / loca → each layer's quadratic outline, flattened to polygons and filled with the
    non-zero rule (per contour: its sign of area x inside), 4x supersampled, composited in order.

`bitmap(cluster, em_px)` returns (RGBA image, ascent px, advance px) for an em of `em_px` pixels,
the same contract as the old Noto strike: text.py scales it to the text's em and draws it on the
baseline. Metrics come from the font (advance 1 em, ascent 0.93 em, descent 0.18 em).
"""

import os
import struct
from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_PATH = os.path.join(os.path.dirname(HERE), "fonts", "TwemojiMozilla.ttf")
SUPER = 4  # supersampling of the layer masks
SKIP = {0xFE0F, 0xFE0E}
PAD = 2  # transparent margin (px at the requested em) around every bitmap


class Font:
    def __init__(self, path):
        self.data = data = open(path, "rb").read()
        num = struct.unpack(">H", data[4:6])[0]
        self.tables = {}
        for i in range(num):
            tag, _, off, ln = struct.unpack(">4sIII", data[12 + 16 * i : 28 + 16 * i])
            self.tables[tag.decode("latin-1")] = (off, ln)
        head = self.tables["head"][0]
        self.upm = struct.unpack(">H", data[head + 18 : head + 20])[0]
        self.loca_long = struct.unpack(">h", data[head + 50 : head + 52])[0] == 1
        hhea = self.tables["hhea"][0]
        self.ascent, self.descent = struct.unpack(">hh", data[hhea + 4 : hhea + 8])
        self.num_hmetrics = struct.unpack(">H", data[hhea + 34 : hhea + 36])[0]
        maxp = self.tables["maxp"][0]
        self.num_glyphs = struct.unpack(">H", data[maxp + 4 : maxp + 6])[0]
        self.cmap = self._read_cmap()
        self.layers = self._read_colr()
        self.palette = self._read_cpal()

    # -- tables ------------------------------------------------------------------------------

    def _read_cmap(self):
        data = self.data
        off = self.tables["cmap"][0]
        n = struct.unpack(">H", data[off + 2 : off + 4])[0]
        best = None
        for i in range(n):
            pid, eid, sub = struct.unpack(">HHI", data[off + 4 + 8 * i : off + 12 + 8 * i])
            fmt = struct.unpack(">H", data[off + sub : off + sub + 2])[0]
            if fmt == 12 and (best is None or best[0] != 12):
                best = (12, off + sub)
            elif fmt == 4 and best is None and pid in (0, 3):
                best = (4, off + sub)
        out = {}
        if best is None:
            return out
        fmt, p = best
        if fmt == 12:
            ngroups = struct.unpack(">I", data[p + 12 : p + 16])[0]
            for g in range(ngroups):
                start, end, gid = struct.unpack(">III", data[p + 16 + 12 * g : p + 28 + 12 * g])
                for cp in range(start, end + 1):
                    out[cp] = gid + (cp - start)
            return out
        segx2 = struct.unpack(">H", data[p + 6 : p + 8])[0]
        seg = segx2 // 2
        ends = struct.unpack(f">{seg}H", data[p + 14 : p + 14 + segx2])
        starts = struct.unpack(f">{seg}H", data[p + 16 + segx2 : p + 16 + 2 * segx2])
        deltas = struct.unpack(f">{seg}h", data[p + 16 + 2 * segx2 : p + 16 + 3 * segx2])
        ro_base = p + 16 + 3 * segx2
        ranges = struct.unpack(f">{seg}H", data[ro_base : ro_base + segx2])
        for i in range(seg):
            for cp in range(starts[i], ends[i] + 1):
                if cp == 0xFFFF:
                    continue
                if ranges[i] == 0:
                    gid = (cp + deltas[i]) & 0xFFFF
                else:
                    at = ro_base + 2 * i + ranges[i] + 2 * (cp - starts[i])
                    gid = struct.unpack(">H", data[at : at + 2])[0]
                    if gid:
                        gid = (gid + deltas[i]) & 0xFFFF
                if gid:
                    out[cp] = gid
        return out

    def _read_colr(self):
        if "COLR" not in self.tables:
            return {}
        data = self.data
        off = self.tables["COLR"][0]
        _, nbase, base_off, layer_off, _ = struct.unpack(">HHIIH", data[off : off + 14])
        out = {}
        for i in range(nbase):
            at = off + base_off + 6 * i
            gid, first, count = struct.unpack(">HHH", data[at : at + 6])
            layers = []
            for j in range(first, first + count):
                lat = off + layer_off + 4 * j
                layers.append(struct.unpack(">HH", data[lat : lat + 4]))
            out[gid] = layers
        return out

    def _read_cpal(self):
        if "CPAL" not in self.tables:
            return []
        data = self.data
        off = self.tables["CPAL"][0]
        _, nentries, _, _, rec_off = struct.unpack(">HHHHI", data[off : off + 12])
        first = struct.unpack(">H", data[off + 12 : off + 14])[0]
        out = []
        for i in range(nentries):
            at = off + rec_off + 4 * (first + i)
            b, g, r, a = data[at : at + 4]
            out.append((r, g, b, a))
        return out

    def advance(self, gid):
        off = self.tables["hmtx"][0]
        i = min(gid, self.num_hmetrics - 1)
        return struct.unpack(">H", self.data[off + 4 * i : off + 4 * i + 2])[0]

    def _glyph_range(self, gid):
        data = self.data
        loca = self.tables["loca"][0]
        if self.loca_long:
            a, b = struct.unpack(">II", data[loca + 4 * gid : loca + 4 * gid + 8])
        else:
            a, b = struct.unpack(">HH", data[loca + 2 * gid : loca + 2 * gid + 4])
            a, b = a * 2, b * 2
        glyf = self.tables["glyf"][0]
        return glyf + a, b - a

    def contours(self, gid):
        """The glyph's contours as lists of (x, y, on_curve) in font units (simple glyphs only)."""
        data = self.data
        at, length = self._glyph_range(gid)
        if length <= 0:
            return []
        n = struct.unpack(">h", data[at : at + 2])[0]
        if n <= 0:
            return []  # composite glyphs: Twemoji Mozilla has none
        p = at + 10
        ends = struct.unpack(f">{n}H", data[p : p + 2 * n])
        p += 2 * n
        ilen = struct.unpack(">H", data[p : p + 2])[0]
        p += 2 + ilen
        npts = ends[-1] + 1
        flags = []
        while len(flags) < npts:
            f = data[p]
            p += 1
            flags.append(f)
            if f & 8:
                r = data[p]
                p += 1
                flags.extend([f] * r)
        flags = flags[:npts]
        xs, ys = [], []
        v = 0
        for f in flags:
            if f & 2:
                d = data[p]
                p += 1
                v += d if f & 16 else -d
            elif not f & 16:
                v += struct.unpack(">h", data[p : p + 2])[0]
                p += 2
            xs.append(v)
        v = 0
        for f in flags:
            if f & 4:
                d = data[p]
                p += 1
                v += d if f & 32 else -d
            elif not f & 32:
                v += struct.unpack(">h", data[p : p + 2])[0]
                p += 2
            ys.append(v)
        out, start = [], 0
        for end in ends:
            out.append([(xs[i], ys[i], bool(flags[i] & 1)) for i in range(start, end + 1)])
            start = end + 1
        return out


def _flatten(contour, steps=6):
    """A closed quadratic TrueType contour as a polygon [(x, y)] (implied on-curve midpoints)."""
    pts = contour
    n = len(pts)
    if n < 2:
        return []
    # Start on an on-curve point (or the midpoint of two off-curve ones).
    first = next((i for i in range(n) if pts[i][2]), None)
    if first is None:
        a, b = pts[0], pts[1]
        start = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        seq = pts[1:] + pts[:1]
    else:
        start = (pts[first][0], pts[first][1])
        seq = pts[first + 1 :] + pts[:first]
    poly = [start]
    cur = start
    ctrl = None
    for x, y, on in seq + [(start[0], start[1], True)]:
        if on:
            if ctrl is None:
                poly.append((x, y))
            else:
                for k in range(1, steps + 1):
                    t = k / steps
                    mt = 1 - t
                    poly.append(
                        (
                            mt * mt * cur[0] + 2 * mt * t * ctrl[0] + t * t * x,
                            mt * mt * cur[1] + 2 * mt * t * ctrl[1] + t * t * y,
                        )
                    )
                ctrl = None
            cur = (x, y)
        else:
            if ctrl is not None:
                mid = ((ctrl[0] + x) / 2, (ctrl[1] + y) / 2)
                for k in range(1, steps + 1):
                    t = k / steps
                    mt = 1 - t
                    poly.append(
                        (
                            mt * mt * cur[0] + 2 * mt * t * ctrl[0] + t * t * mid[0],
                            mt * mt * cur[1] + 2 * mt * t * ctrl[1] + t * t * mid[1],
                        )
                    )
                cur = mid
            ctrl = (x, y)
    return poly


def _area(poly):
    s = 0.0
    for i in range(len(poly)):
        x0, y0 = poly[i - 1]
        x1, y1 = poly[i]
        s += x0 * y1 - x1 * y0
    return s / 2


@lru_cache(maxsize=None)
def font():
    return Font(FONT_PATH) if os.path.isfile(FONT_PATH) else None


def available():
    return font() is not None


def codepoints():
    f = font()
    return set(f.cmap) if f else set()


def glyph_for(cluster):
    f = font()
    if f is None:
        return None
    for ch in cluster:
        cp = ord(ch)
        if cp in SKIP or cp == 0x200D:
            continue
        gid = f.cmap.get(cp)
        if gid is not None:
            return gid
        return None
    return None


def adv_per_em():
    return 1.0  # every Twemoji glyph is one em wide


def _layer_alpha(f, gid, scale, ox, base, w, h):
    """Coverage (h x w float array, 0..1) of one glyph at `scale` px per unit, supersampled."""
    S = SUPER
    acc = np.zeros((h * S, w * S), np.int16)
    for contour in f.contours(gid):
        poly = _flatten(contour)
        if len(poly) < 3:
            continue
        sign = 1 if _area(poly) > 0 else -1
        pts = [((ox + x * scale) * S, (base - y * scale) * S) for x, y in poly]
        m = Image.new("L", (w * S, h * S), 0)
        ImageDraw.Draw(m).polygon(pts, fill=1)
        acc += sign * np.asarray(m, np.int16)
    filled = (acc != 0).astype(np.float32)
    return filled.reshape(h, S, w, S).mean(axis=(1, 3))


@lru_cache(maxsize=512)
def bitmap(cluster, em_px):
    """(RGBA image, ascent px, advance px) of the emoji at an em of `em_px` px, or None."""
    f = font()
    gid = glyph_for(cluster)
    if f is None or gid is None:
        return None
    scale = em_px / f.upm
    adv = f.advance(gid) * scale
    asc = f.ascent * scale
    pad = PAD
    w = int(np.ceil(adv)) + 2 * pad
    h = int(np.ceil((f.ascent - f.descent) * scale)) + 2 * pad
    base = pad + asc
    rgb = np.zeros((h, w, 3), np.float32)
    alpha = np.zeros((h, w), np.float32)
    layers = f.layers.get(gid) or [(gid, 0xFFFF)]
    for lgid, pidx in layers:
        a = _layer_alpha(f, lgid, scale, pad, base, w, h)
        if pidx == 0xFFFF or pidx >= len(f.palette):
            col, ca = (0.0, 0.0, 0.0), 1.0
        else:
            r, g, b, ca = f.palette[pidx]
            col, ca = (r / 255.0, g / 255.0, b / 255.0), ca / 255.0
        a = a * ca
        # straight-alpha "over"
        out_a = a + alpha * (1 - a)
        safe = np.where(out_a > 1e-6, out_a, 1)
        for c in range(3):
            rgb[..., c] = (col[c] * a + rgb[..., c] * alpha * (1 - a)) / safe
        alpha = out_a
    im = np.dstack([rgb, alpha[..., None]])
    img = Image.fromarray((np.clip(im, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    return img, base, adv
