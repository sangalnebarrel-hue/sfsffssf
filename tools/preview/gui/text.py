"""Text for the GUI preview renderer: fonts, colour emoji, Roblox-like layout and TextScaled fitting.

Metrics model (an approximation of Roblox's text engine, see tools/preview/README.md):
  * TextSize S is the height of one line in pixels: the font's ascent + descent (hhea) are
    scaled to S, so the em is S / 1.364 for Nunito; the baseline sits ascent * em below the
    line top; lines are S * LineHeight apart.
  * TextScaled picks the largest whole size <= max (UITextSizeConstraint.MaxTextSize, else 100)
    and >= min (MinTextSize, else 1) whose text, wrapped at spaces, fits the box without
    splitting a word; when nothing fits, the min size is used, words longer than the line are
    split and the text may overflow the box. TextScaled implies wrapping (as in Roblox).
  * Characters Nunito lacks (→, ★ ...) are drawn with a fallback font (DejaVu Sans Bold).
  * Colour emoji (Noto Color Emoji, a 109 px bitmap strike) are drawn at the text's em size
    (1.17 em tall box, 1.25 em advance) and are not tinted by TextColor3.
"""

import os
import re
import struct
from functools import lru_cache

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONT_DIR = os.path.join(os.path.dirname(HERE), "fonts")
NUNITO = os.path.join(FONT_DIR, "Nunito.ttf")
EMOJI_CANDIDATES = [
    os.environ.get("GUI_PREVIEW_EMOJI_FONT", ""),
    "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf",
    "/usr/share/fonts/noto/NotoColorEmoji.ttf",
    "/usr/share/fonts/google-noto-emoji/NotoColorEmoji.ttf",
    "/System/Library/Fonts/Apple Color Emoji.ttc",
]
EMOJI_STRIKE = 109  # the only size of Noto Color Emoji's bitmaps
REF = 256  # reference size (px em) for width measurements; widths scale linearly
DEFAULT_SCALED_MAX = 100

_warned = set()


def warn_once(msg):
    if msg not in _warned:
        _warned.add(msg)
        print(f"[gui_render] warning: {msg}")


# ---------------------------------------------------------------------------------------
# cmap coverage (which code points a font has), from the raw 'cmap' table
# ---------------------------------------------------------------------------------------


def _cmap_codepoints(path):
    data = open(path, "rb").read()
    if data[:4] == b"ttcf":
        data_off = struct.unpack(">I", data[12:16])[0]
    else:
        data_off = 0
    num = struct.unpack(">H", data[data_off + 4 : data_off + 6])[0]
    tables = {}
    for i in range(num):
        rec = data_off + 12 + 16 * i
        tag, _, off, ln = struct.unpack(">4sIII", data[rec : rec + 16])
        tables[tag] = (off, ln)
    off, _ = tables[b"cmap"]
    n = struct.unpack(">H", data[off + 2 : off + 4])[0]
    best = None
    for i in range(n):
        pid, eid, sub = struct.unpack(">HHI", data[off + 4 + 8 * i : off + 12 + 8 * i])
        fmt = struct.unpack(">H", data[off + sub : off + sub + 2])[0]
        if fmt == 12 and (best is None or best[0] != 12):
            best = (12, off + sub)
        elif fmt == 4 and best is None and pid in (0, 3):
            best = (4, off + sub)
    cps = set()
    if best is None:
        return cps
    fmt, p = best
    if fmt == 12:
        ngroups = struct.unpack(">I", data[p + 12 : p + 16])[0]
        for g in range(ngroups):
            start, end, _ = struct.unpack(">III", data[p + 16 + 12 * g : p + 28 + 12 * g])
            cps.update(range(start, end + 1))
    else:
        segx2 = struct.unpack(">H", data[p + 6 : p + 8])[0]
        ends = struct.unpack(f">{segx2 // 2}H", data[p + 14 : p + 14 + segx2])
        starts = struct.unpack(f">{segx2 // 2}H", data[p + 16 + segx2 : p + 16 + 2 * segx2])
        for s, e in zip(starts, ends):
            if s != 0xFFFF:
                cps.update(range(s, e + 1))
    return cps


@lru_cache(maxsize=None)
def emoji_font_path():
    for p in EMOJI_CANDIDATES:
        if p and os.path.isfile(p):
            return p
    warn_once("no colour emoji font found (set GUI_PREVIEW_EMOJI_FONT); emoji are drawn as boxes")
    return None


FALLBACK_CANDIDATES = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
]


@lru_cache(maxsize=None)
def fallback_font_path():
    for p in FALLBACK_CANDIDATES:
        if os.path.isfile(p):
            return p
    return None


@lru_cache(maxsize=None)
def coverage():
    text = _cmap_codepoints(NUNITO)
    ep = emoji_font_path()
    emoji = _cmap_codepoints(ep) if ep else set()
    fp = fallback_font_path()
    fallback = _cmap_codepoints(fp) if fp else set()
    return text, emoji, fallback


JOINERS = {0x200D, 0xFE0F, 0xFE0E, 0x20E3}


def _is_modifier(cp):
    return 0x1F3FB <= cp <= 0x1F3FF or 0xE0020 <= cp <= 0xE007F


def _wants_emoji(cp, nxt):
    text_cps, emoji_cps, _ = coverage()
    if cp not in emoji_cps:
        return False
    if nxt == 0xFE0F:
        return True
    if cp in text_cps or cp < 0x2000:
        return False  # the text font has it (digits, #, *, ©, arrows ...)
    return True


def _kind(cp):
    text_cps, _, fb = coverage()
    if cp in text_cps or cp < 0x20 or chr(cp).isspace() or cp not in fb:
        return "text"
    return "fb"  # missing in Nunito: drawn with a fallback font (DejaVu Sans Bold), like Roblox does


def clusters(s):
    """Split text into [(kind, text)] with kind 'text' | 'fb' (fallback font) | 'emoji';
    emoji are whole graphemes."""
    cps = [ord(c) for c in s]
    out = []
    i = 0
    n = len(cps)
    while i < n:
        cp = cps[i]
        nxt = cps[i + 1] if i + 1 < n else None
        if _wants_emoji(cp, nxt):
            j = i + 1
            if 0x1F1E6 <= cp <= 0x1F1FF and j < n and 0x1F1E6 <= cps[j] <= 0x1F1FF:
                j += 1  # flag
            while j < n:
                if cps[j] in JOINERS or _is_modifier(cps[j]):
                    if cps[j] == 0x200D and j + 1 < n:
                        j += 2
                    else:
                        j += 1
                else:
                    break
            out.append(("emoji", s[i:j]))
            i = j
        else:
            kind = _kind(cp)
            if out and out[-1][0] == kind:
                out[-1] = (kind, out[-1][1] + s[i])
            else:
                out.append((kind, s[i]))
            i += 1
    return out


# ---------------------------------------------------------------------------------------
# Fonts
# ---------------------------------------------------------------------------------------


@lru_cache(maxsize=256)
def text_font(family, weight, px):
    """ImageFont for a Roblox family/weight at `px` em pixels (Nunito for every family)."""
    if family not in ("Nunito",):
        warn_once(f"font family {family!r} is drawn with Nunito")
    f = ImageFont.truetype(NUNITO, max(1.0, round(px * 4) / 4))
    try:
        f.set_variation_by_axes([max(200, min(1000, weight))])
    except Exception:  # not a variable font
        pass
    return f


@lru_cache(maxsize=64)
def fallback_font(px):
    p = fallback_font_path()
    return ImageFont.truetype(p, max(1.0, round(px * 4) / 4)) if p else text_font("Nunito", 700, px)


@lru_cache(maxsize=None)
def line_metrics():
    """(ascent, descent) of Nunito per em."""
    f = ImageFont.truetype(NUNITO, 1000)
    a, d = f.getmetrics()
    return a / 1000.0, d / 1000.0


@lru_cache(maxsize=None)
def _emoji_font():
    p = emoji_font_path()
    return ImageFont.truetype(p, EMOJI_STRIKE) if p else None


@lru_cache(maxsize=512)
def emoji_bitmap(cluster):
    """RGBA bitmap of one emoji at the 109 px strike: (image, ascent_px, advance_px)."""
    f = _emoji_font()
    if f is None:
        im = Image.new("RGBA", (136, 128), (0, 0, 0, 0))
        ImageDraw.Draw(im).rectangle([20, 10, 116, 118], outline=(255, 255, 255, 220), width=8)
        return im, 101, 136
    asc, desc = f.getmetrics()
    adv = f.getlength(cluster)
    im = Image.new("RGBA", (int(adv) + 4, asc + desc + 4), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((0, asc), cluster, font=f, embedded_color=True, anchor="ls")
    return im, asc, adv


@lru_cache(maxsize=4096)
def _ref_width(family, weight, s):
    return text_font(family, weight, REF).getlength(s)


@lru_cache(maxsize=1024)
def _ref_width_fb(s):
    return fallback_font(REF).getlength(s)


def _emoji_adv_per_em():
    f = _emoji_font()
    return (f.getlength("\U0001f3a3") if f else 136) / EMOJI_STRIKE


def paste_rgba(dst, src, x, y):
    """alpha_composite `src` onto `dst` at (x, y), clipped to `dst` (negative x/y allowed)."""
    sx0, sy0 = max(0, -x), max(0, -y)
    dx0, dy0 = max(0, x), max(0, y)
    w = min(src.width - sx0, dst.width - dx0)
    h = min(src.height - sy0, dst.height - dy0)
    if w > 0 and h > 0:
        dst.alpha_composite(src, (dx0, dy0), (sx0, sy0, sx0 + w, sy0 + h))


# ---------------------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------------------

_TAG = re.compile(r"<[^>]*>")


def plain_text(rec):
    s = rec["s"]
    if rec.get("rich"):
        s = re.sub(r"<br\s*/?>", "\n", s)
        s = _TAG.sub("", s)
        s = s.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"').replace("&apos;", "'")
        s = s.replace("&amp;", "&")
    return s


class Token:
    __slots__ = ("parts", "w_em", "space")

    def __init__(self, parts, w_em, space):
        self.parts = parts  # [(kind, text, w_em)]
        self.w_em = w_em
        self.space = space  # a whitespace token


def tokenize(s, family, weight):
    """Paragraphs of tokens (words and spaces), widths in em."""
    eadv = _emoji_adv_per_em()
    paras = []
    for para in s.split("\n"):
        toks = []
        # A no-break space (U+00A0) glues words as in Roblox: it stays inside the word token.
        for piece in re.findall(r"[^\S ]+|(?:\S| )+", para):
            parts = []
            total = 0.0
            for kind, txt in clusters(piece):
                if kind == "emoji":
                    w = eadv
                elif kind == "fb":
                    w = _ref_width_fb(txt) / REF
                else:
                    w = _ref_width(family, weight, txt) / REF
                parts.append((kind, txt, w))
                total += w
            toks.append(Token(parts, total, piece.isspace() and " " not in piece))
        paras.append(toks)
    return paras


def _split_long(tok, max_em):
    """Break a word wider than the line into pieces (per grapheme)."""
    pieces, cur, cur_w = [], [], 0.0
    for kind, txt, w in tok.parts:
        units = [(kind, txt, w)] if kind == "emoji" else [(kind, ch, None) for ch in txt]
        for k2, t2, w2 in units:
            if w2 is None:
                w2 = w * (len(t2) / max(len(txt), 1))
            if cur and cur_w + w2 > max_em:
                pieces.append(Token(cur, cur_w, False))
                cur, cur_w = [], 0.0
            cur.append((k2, t2, w2))
            cur_w += w2
    if cur:
        pieces.append(Token(cur, cur_w, False))
    return pieces


def wrap(paras, max_em, wrap_on, info=None):
    """Lines (lists of tokens) for a line width of max_em; trailing spaces are dropped.
    info["broken"] is set when a word had to be split across lines."""
    lines = []
    for toks in paras:
        if not wrap_on:
            lines.append(list(toks))
            continue
        line, w = [], 0.0
        for tok in toks:
            if tok.space:
                if line:
                    line.append(tok)
                    w += tok.w_em
                continue
            if tok.w_em > max_em + 1e-6:
                if info is not None:
                    info["broken"] = True
                for piece in _split_long(tok, max_em):
                    if line and w + piece.w_em > max_em + 1e-6:
                        lines.append(line)
                        line, w = [], 0.0
                    line.append(piece)
                    w += piece.w_em
                continue
            if line and w + tok.w_em > max_em + 1e-6:
                while line and line[-1].space:
                    w -= line.pop().w_em
                lines.append(line)
                line, w = [], 0.0
            line.append(tok)
            w += tok.w_em
        while line and line[-1].space:
            line.pop()
        lines.append(line)
    return lines


def line_width(line):
    return sum(t.w_em for t in line)


class Layout:
    def __init__(self, size, em, lines, block_w, block_h, x0, y0, lh, xa, family, weight):
        self.size = size  # TextSize (line height, px)
        self.em = em
        self.lines = lines
        self.block_w = block_w
        self.block_h = block_h
        self.x0 = x0  # block origin inside the text box
        self.y0 = y0
        self.lh = lh
        self.xa = xa
        self.family = family
        self.weight = weight


def layout(rec, box_w, box_h, k=1.0):
    """Lay out a text record in a box (screen px). `k` = accumulated UIScale: fitting happens
    in unscaled pixels (constraints are in those) and the result is scaled by k."""
    s = plain_text(rec)
    if not s:
        return None
    asc, desc = line_metrics()
    per_line = asc + desc
    family, weight = rec.get("font", "Nunito"), int(rec.get("weight", 400))
    lh = float(rec.get("lh", 1) or 1)
    paras = tokenize(s, family, weight)
    nat_w, nat_h = box_w / max(k, 1e-6), box_h / max(k, 1e-6)

    def measure(size, wrap_on, info=None):
        em = size / per_line
        lines = wrap(paras, nat_w / em if em > 0 else 1e9, wrap_on, info)
        width = max((line_width(l) for l in lines), default=0) * em
        height = len(lines) * size * lh
        return lines, width, height

    if rec.get("scaled"):
        hi = int(rec.get("max") or DEFAULT_SCALED_MAX)
        lo = max(1, int(rec.get("min") or 1))
        hi = max(hi, lo)

        def fits(size):
            # A size fits when every word fits on a line (no word is split) and the lines fit
            # the box; only the min-size fallback below splits words (and may overflow).
            info = {}
            lines, width, height = measure(size, True, info)
            return not info.get("broken") and width <= nat_w + 0.5 and height <= nat_h + 0.5

        if fits(hi):
            size = hi
        elif not fits(lo):
            size = lo
        else:
            a, b = lo, hi  # fits(a) and not fits(b)
            while b - a > 1:
                mid = (a + b) // 2
                if fits(mid):
                    a = mid
                else:
                    b = mid
            size = a
        lines, width, height = measure(size, True)
    else:
        size = float(rec.get("size", 14))
        lines, width, height = measure(size, bool(rec.get("wrap")))

    # Truncation (TextTruncate AtEnd / SplitWord) of the last visible line.
    if rec.get("trunc", "None") != "None" and not rec.get("scaled"):
        em = size / per_line
        max_lines = max(1, int((nat_h + 0.5) // (size * lh))) if rec.get("wrap") else 1
        if len(lines) > max_lines or width > nat_w + 0.5:
            lines = lines[:max_lines]
            last = lines[-1]
            ell = _ref_width(family, weight, "…") / REF
            while last and line_width(last) + ell > nat_w / em:
                last = last[:-1]
            last.append(Token([("text", "…", ell)], ell, False))
            width = max(line_width(l) for l in lines) * em
            height = len(lines) * size * lh

    size_px = size * k
    em_px = size_px / per_line
    block_w = width * k
    block_h = height * k
    ya = rec.get("ya", "Center")
    if ya == "Top":
        y0 = 0.0
    elif ya == "Bottom":
        y0 = box_h - block_h
    else:
        y0 = (box_h - block_h) / 2
    return Layout(size_px, em_px, lines, block_w, block_h, 0.0, y0, lh, rec.get("xa", "Center"), family, weight)


def line_positions(lay, box_w):
    """[(x_left, baseline_y, line)] relative to the text box."""
    asc, _ = line_metrics()
    out = []
    for i, line in enumerate(lay.lines):
        w = line_width(line) * lay.em
        if lay.xa == "Left":
            x = 0.0
        elif lay.xa == "Right":
            x = box_w - w
        else:
            x = (box_w - w) / 2
        top = lay.y0 + i * lay.size * lay.lh
        out.append((x, top + asc * lay.em, line))
    return out


def extents(lay, box_w):
    """Bounding box (x0, y0, x1, y1) of the laid-out text relative to the text box."""
    asc, desc = line_metrics()
    xs0, xs1 = [], []
    for x, _, line in line_positions(lay, box_w):
        xs0.append(x)
        xs1.append(x + line_width(line) * lay.em)
    if not xs0:
        return 0, 0, 0, 0
    top = lay.y0 - 0.15 * lay.em  # emoji and accents (Ё, Й) poke a little above the line box
    bottom = lay.y0 + lay.block_h + 0.2 * lay.em
    return min(xs0) - 0.1 * lay.em, top, max(xs1) + 0.1 * lay.em, bottom


def draw(lay, box_w, mask, emoji_layer, ox, oy, graphemes=-1):
    """Draw glyphs into `mask` (L image, 255 = ink) and emoji into `emoji_layer` (RGBA),
    with the text box's top-left at (ox, oy) in those images. `graphemes` >= 0 limits the
    number of visible graphemes (MaxVisibleGraphemes)."""
    d = ImageDraw.Draw(mask)
    font = text_font(lay.family, lay.weight, lay.em)
    fb = fallback_font(lay.em)
    eadv = _emoji_adv_per_em()
    left = graphemes if graphemes is not None and graphemes >= 0 else None
    for x, base, line in line_positions(lay, box_w):
        cx = ox + x
        by = oy + base
        for tok in line:
            for kind, txt, w in tok.parts:
                if left is not None and left <= 0:
                    return
                if kind == "emoji":
                    im, asc_e, _ = emoji_bitmap(txt)
                    f = lay.em / EMOJI_STRIKE
                    tw, th = max(1, int(round(im.width * f))), max(1, int(round(im.height * f)))
                    scaled = im.resize((tw, th), Image.LANCZOS)
                    paste_rgba(emoji_layer, scaled, int(round(cx)), int(round(by - asc_e * f)))
                    if left is not None:
                        left -= 1
                    cx += eadv * lay.em
                else:
                    if left is not None and len(txt) > left:
                        txt = txt[:left]
                    if not txt.isspace():
                        d.text((cx, by), txt, font=fb if kind == "fb" else font, fill=255, anchor="ls")
                    if left is not None:
                        left -= len(txt)
                    cx += w * lay.em
