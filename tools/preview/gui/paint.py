"""Paints a gui_dump.luau frame (a list of GuiObjects in draw order) onto an RGBA canvas.

Everything is drawn at `ss` x supersampling and anti-aliased with signed-distance coverage
(rounded rectangles, strokes); gui_render.py downsamples the canvas at the end.

Roblox rules followed here (see tools/preview/README.md "GUI previews" for the list):
  * UICorner radius is already in pixels in the dump (scale x the shorter side + offset, clamped
    to half of it); the background and Border strokes follow the rounded shape.
  * UIStroke (Border): Outer by default — the ring lies OUTSIDE the box, its outer corners
    rounded with radius r + thickness (round joins); Center / Inner when BorderStrokePosition
    says so. Its own UIGradient colours it across the object's box. Independent of
    BackgroundTransparency.
  * UIStroke on text (Contextual on a text object): an outline of the glyphs (and emoji) of the
    given thickness, under the fill. Legacy TextStroke: a thin outline (max(1, 0.045 * TextSize) px).
  * UIGradient (on the object): Color multiplies BackgroundColor3 and TextColor3, Transparency
    multiplies the opacity; t = 0.5 + (u - 0.5 - Offset.X) cos(Rotation) + (v - 0.5 - Offset.Y)
    sin(Rotation) in the object's normalised box, clamped to 0..1 (90 = top to bottom).
  * Legacy border (BorderSizePixel) only without UICorner/UIStroke; BorderMode Outline/Middle/Inset.
  * Rotation turns the whole object (box, strokes, text) about its centre; clip rectangles come
    from the dump (ClipsDescendants of unrotated ancestors).
  * ViewportFrame: the fish sprite docs/gear/<Fish>_iso.png (or _Gold/_Neon/_Rainbow.png),
    background keyed out, fitted and centred. ImageLabel images cannot be fetched: drawn as a
    soft glow tinted with ImageColor3.
"""

import math
import os

import numpy as np
from PIL import Image, ImageDraw

from . import text as T

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
GEAR_DIR = os.path.join(REPO, "docs", "gear")


# ---------------------------------------------------------------------------------------
# Sequences, gradients, coverage
# ---------------------------------------------------------------------------------------


def _seq_interp(kps, t, cols):
    ts = np.array([k[0] for k in kps], np.float32)
    vals = np.array([k[1 : 1 + cols] for k in kps], np.float32)
    out = np.empty(t.shape + (cols,), np.float32)
    for c in range(cols):
        out[..., c] = np.interp(t, ts, vals[:, c])
    return out


def gradient(grad, u, v, aspect=1.0):
    """(rgb multiplier 0..1 [H, W, 3], opacity multiplier [H, W]) of a UIGradient over u, v
    (the object's normalised box; aspect = width / height)."""
    r = math.radians(grad.get("rot", 0))
    ox, oy = grad.get("off", (0, 0))
    scale = float(grad.get("scale", 1) or 1)
    kind = grad.get("type", "Linear")
    qx, qy = u - 0.5 - ox, v - 0.5 - oy
    if kind == "Elliptical":  # ellipse fitted to the box: 0 at the centre, 1 at the edge midpoints
        t = 2 * np.hypot(qx, qy) / scale
    elif kind == "Radial":  # circle (in pixels) fitted to the shorter side
        px, py = qx * max(aspect, 1.0), qy * max(1.0 / aspect, 1.0)
        t = 2 * np.hypot(px, py) / scale
    elif kind == "Conical":  # angle around the centre, starting at Rotation, clockwise
        ang = np.arctan2(qy / max(aspect, 1e-6), qx) - r
        t = (ang / (2 * math.pi)) % 1.0
    else:
        t = 0.5 + (qx * math.cos(r) + qy * math.sin(r)) / scale
    tile = grad.get("tile", "Clamp")
    if tile == "Repeat":
        t = t % 1.0
    elif tile == "Mirror":
        t = 1.0 - np.abs((t % 2.0) - 1.0)
    t = np.clip(t, 0.0, 1.0).astype(np.float32)
    rgb = _seq_interp(grad["c"], t, 3) / 255.0
    a = 1.0 - _seq_interp(grad["a"], t, 1)[..., 0]
    return rgb, np.clip(a, 0.0, 1.0)


def rrect_sdf(X, Y, x0, y0, w, h, r):
    """Signed distance to a rounded rectangle (negative inside); r = one radius or
    (top-left, top-right, bottom-right, bottom-left)."""
    cx, cy = x0 + w / 2, y0 + h / 2
    lim = min(w / 2, h / 2)
    if isinstance(r, (tuple, list)):
        tl, tr, br, bl = (max(0.0, min(v, lim)) for v in r)
        r = np.where(X > cx, np.where(Y > cy, br, tr), np.where(Y > cy, bl, tl)).astype(np.float32)
    else:
        r = max(0.0, min(r, lim))
    qx = np.abs(X - cx) - (w / 2 - r)
    qy = np.abs(Y - cy) - (h / 2 - r)
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    inside = np.minimum(np.maximum(qx, qy), 0)
    return outside + inside - r


def cov(d):
    return np.clip(0.5 - d, 0.0, 1.0)


def rect_cov(X, Y, x0, y0, x1, y1):
    cx = np.clip(np.minimum(X - x0, x1 - X) + 0.5, 0, 1)
    cy = np.clip(np.minimum(Y - y0, y1 - Y) + 0.5, 0, 1)
    return cy * cx


# ---------------------------------------------------------------------------------------
# Premultiplied accumulation buffer for one object
# ---------------------------------------------------------------------------------------


class Layer:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.rgb = np.zeros((h, w, 3), np.float32)  # premultiplied
        self.a = np.zeros((h, w), np.float32)

    def over(self, rgb, a, region=None):
        """Composite colour `rgb` (H, W, 3 or 3-vector, 0..1) with opacity `a` over the layer."""
        if region is None:
            sl = (slice(None), slice(None))
        else:
            x0, y0, x1, y1 = region
            sl = (slice(y0, y1), slice(x0, x1))
        a = np.clip(a, 0, 1)
        ia = 1.0 - a
        self.rgb[sl] = np.asarray(rgb, np.float32) * a[..., None] + self.rgb[sl] * ia[..., None]
        self.a[sl] = a + self.a[sl] * ia

    def over_rgba(self, im, x, y):
        """Composite a straight-alpha RGBA PIL image at integer (x, y)."""
        arr = np.asarray(im, np.float32) / 255.0
        sx0, sy0 = max(0, -x), max(0, -y)
        dx0, dy0 = max(0, x), max(0, y)
        w = min(arr.shape[1] - sx0, self.w - dx0)
        h = min(arr.shape[0] - sy0, self.h - dy0)
        if w <= 0 or h <= 0:
            return
        part = arr[sy0 : sy0 + h, sx0 : sx0 + w]
        self.over(part[..., :3], part[..., 3], (dx0, dy0, dx0 + w, dy0 + h))

    def image(self, premultiplied=False):
        out = np.empty((self.h, self.w, 4), np.uint8)
        np.clip(self.rgb * 255 + 0.5, 0, 255, out=self.rgb)
        out[..., :3] = self.rgb
        out[..., 3] = np.clip(self.a * 255 + 0.5, 0, 255)
        im = Image.fromarray(out, "RGBa")
        return im if premultiplied else im.convert("RGBA")


# ---------------------------------------------------------------------------------------
# Sprites
# ---------------------------------------------------------------------------------------

_sprites = {}


def _grow(mask, seed):
    """Flood fill: the part of `mask` connected to `seed` (4-neighbourhood, numpy only)."""
    region = seed & mask
    while True:
        grown = region.copy()
        grown[1:, :] |= region[:-1, :]
        grown[:-1, :] |= region[1:, :]
        grown[:, 1:] |= region[:, :-1]
        grown[:, :-1] |= region[:, 1:]
        grown &= mask
        if (grown == region).all():
            return region
        region = grown


def _key_background(im):
    """RGBA copy of a gear render with its flat light background made transparent. The
    renders' Neon glow (a pale halo; a ViewportFrame has no bloom) goes with the background:
    pale, unsaturated pixels connected to the border are removed, a 1 px rim is softened."""
    arr = np.asarray(im.convert("RGB"), np.float32)
    bg = arr[0, 0]
    dist = np.sqrt(((arr - bg) ** 2).sum(-1))
    sat = arr.max(-1) - arr.min(-1)
    pale = (dist < 20) | ((sat < 42) & (arr.mean(-1) > 205))
    seed = np.zeros(pale.shape, bool)
    seed[0, :] = seed[-1, :] = seed[:, 0] = seed[:, -1] = True
    flood = _grow(pale, seed)
    alpha = np.where(flood, 0.0, 1.0)
    near = np.zeros_like(flood)
    near[1:, :] |= flood[:-1, :]
    near[:-1, :] |= flood[1:, :]
    near[:, 1:] |= flood[:, :-1]
    near[:, :-1] |= flood[:, 1:]
    rim = near & ~flood
    alpha = np.where(rim, np.clip(np.minimum(dist, sat * 2) / 80.0, 0.3, 1.0), alpha)
    out = np.dstack([arr, alpha * 255]).astype(np.uint8)
    res = Image.fromarray(out, "RGBA")
    bbox = res.getbbox()
    return res.crop(bbox) if bbox else res


def fish_sprite(fish, mutation):
    key = (fish, mutation)
    if key in _sprites:
        return _sprites[key]
    names = []
    if mutation and mutation != "Normal":
        names.append(f"{fish}_{mutation}.png")
    names.append(f"{fish}_iso.png")
    sprite = None
    for n in names:
        p = os.path.join(GEAR_DIR, n)
        if os.path.isfile(p):
            cache_dir = os.environ.get("GUI_PREVIEW_CACHE", os.path.join(HERE, ".cache"))
            cached = os.path.join(cache_dir, f"sprite_{os.path.getmtime(p):.0f}_{n}")
            if os.path.isfile(cached):
                sprite = Image.open(cached).convert("RGBA")
            else:
                sprite = _key_background(Image.open(p))
                try:
                    os.makedirs(cache_dir, exist_ok=True)
                    sprite.save(cached)
                except OSError:
                    pass
            break
    if sprite is None:
        T.warn_once(f"no sprite for fish {fish!r} in docs/gear")
    _sprites[key] = sprite
    return sprite


def _glow(w, h, color):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.hypot((xx + 0.5 - w / 2) / (w / 2), (yy + 0.5 - h / 2) / (h / 2))
    a = np.clip(1 - d, 0, 1) ** 1.6
    arr = np.dstack([np.broadcast_to(np.array(color, np.float32), (h, w, 3)), a * 255]).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


# ---------------------------------------------------------------------------------------
# Painting one object
# ---------------------------------------------------------------------------------------


def _rgb(c):
    return np.array(c, np.float32) / 255.0


class Painter:
    def __init__(self, ss=2):
        self.ss = ss
        self.stats = {"objects": 0, "drawn": 0}

    def paint(self, objects, canvas, origin=(0, 0)):
        """Draw the objects on `canvas` (RGBA, ss x size); `origin` = screen px of its top-left."""
        for o in objects:
            self.stats["objects"] += 1
            res = self.object_layer(o)
            if res is None:
                continue
            im, dx, dy = res
            dx -= int(round(origin[0] * self.ss))
            dy -= int(round(origin[1] * self.ss))
            clip = o.get("clip")
            if clip:
                im = self._apply_clip(im, dx, dy, clip, origin)
                if im is None:
                    continue
            T.paste_rgba(canvas, im, dx, dy)
            self.stats["drawn"] += 1

    def _apply_clip(self, im, dx, dy, clip, origin):
        s = self.ss
        x0 = int(round((clip[0] - origin[0]) * s)) - dx
        y0 = int(round((clip[1] - origin[1]) * s)) - dy
        x1 = int(round((clip[2] - origin[0]) * s)) - dx
        y1 = int(round((clip[3] - origin[1]) * s)) - dy
        if x1 <= 0 or y1 <= 0 or x0 >= im.width or y0 >= im.height or x1 <= x0 or y1 <= y0:
            return None
        if x0 <= 0 and y0 <= 0 and x1 >= im.width and y1 >= im.height:
            return im
        mask = Image.new("L", im.size, 0)
        ImageDraw.Draw(mask).rectangle([max(x0, 0), max(y0, 0), min(x1, im.width) - 1, min(y1, im.height) - 1], fill=255)
        r, g, b, a = im.split()
        a = Image.fromarray((np.asarray(a, np.uint16) * np.asarray(mask, np.uint16) // 255).astype(np.uint8), "L")
        return Image.merge("RGBA", (r, g, b, a))

    def _draws_anything(self, o):
        if o.get("text") or o.get("viewport") or o.get("image"):
            return True
        if o.get("bgT", 1) < 0.999:
            return True  # (a legacy border is only drawn with a visible background)
        for st in o.get("strokes") or []:
            if st["tr"] < 0.999 and st["t"] > 0:
                return True
        return False

    def object_layer(self, o):
        """(RGBA image, x, y) of one object in canvas pixels, or None."""
        s = self.ss
        alpha = float(o.get("alpha", 1))
        if alpha <= 0.001 or not self._draws_anything(o):
            return None
        w, h = o["w"] * s, o["h"] * s
        if w < 0.01 or h < 0.01:
            return None
        rot = float(o.get("rot", 0)) % 360
        rotated = 0.01 < rot < 359.99

        # Fast path: a flat, unrotated rectangle (full-screen dims, flashes, plain panels).
        if (
            not rotated
            and o.get("radius") is None
            and not o.get("grad")
            and not o.get("strokes")
            and not o.get("border")
            and not o.get("text")
            and not o.get("viewport")
            and not o.get("image")
        ):
            x0, y0 = int(round(o["x"] * s)), int(round(o["y"] * s))
            x1, y1 = int(round((o["x"] + o["w"]) * s)), int(round((o["y"] + o["h"]) * s))
            a = int(round(255 * (1 - float(o.get("bgT", 1))) * alpha))
            if x1 <= x0 or y1 <= y0 or a <= 0:
                return None
            return Image.new("RGBA", (x1 - x0, y1 - y0), tuple(int(c) for c in o["bg"]) + (a,)), x0, y0

        # Extents in object-local pixels (origin = the box's top-left).
        margin = 2.0
        for st in o.get("strokes") or []:
            if st["target"] == "border":
                margin = max(margin, (st["t"] + max(0.0, float(st.get("offset", 0)))) * s + 2)
        if o.get("border"):
            margin = max(margin, o["border"]["size"] * s + 2)
        ex0, ey0, ex1, ey1 = -margin, -margin, w + margin, h + margin

        lay = None
        tbox = None
        rec = o.get("text")
        if rec:
            pad = rec.get("pad") or [0, 0, 0, 0]
            tbx, tby = pad[0] * s, pad[1] * s
            tbw, tbh = max(w - (pad[0] + pad[2]) * s, 0), max(h - (pad[1] + pad[3]) * s, 0)
            lay = T.layout(rec, tbw, tbh, k=float(o.get("k", 1)) * s)
            if lay is not None:
                tbox = (tbx, tby, tbw, tbh)
                tx0, ty0, tx1, ty1 = T.extents(lay, tbw)
                grow = 2 + max([st["t"] * s for st in o.get("strokes") or [] if st["target"] == "text"] + [0])
                grow += max(1.0, 0.045 * lay.size)
                ex0 = min(ex0, tbx + tx0 - grow)
                ey0 = min(ey0, tby + ty0 - grow)
                ex1 = max(ex1, tbx + tx1 + grow)
                ey1 = max(ey1, tby + ty1 + grow)

        X0, Y0 = o["x"] * s, o["y"] * s  # the box's top-left on the canvas
        if not rotated:
            lx0 = math.floor(X0 + ex0)
            ly0 = math.floor(Y0 + ey0)
            lw = math.ceil(X0 + ex1) - lx0
            lh = math.ceil(Y0 + ey1) - ly0
            bx, by = X0 - lx0, Y0 - ly0  # the box's top-left inside the layer
        else:
            # Layer centred on the box centre so that rotate(expand=True) turns about it.
            half_w = max(w / 2 - ex0, ex1 - w / 2)
            half_h = max(h / 2 - ey0, ey1 - h / 2)
            lw = int(math.ceil(2 * half_w)) + 2
            lh = int(math.ceil(2 * half_h)) + 2
            bx, by = lw / 2 - w / 2, lh / 2 - h / 2
            lx0 = ly0 = 0
        if lw <= 0 or lh <= 0 or lw * lh > 40_000_000:
            return None

        L = Layer(lw, lh)
        xs = np.arange(lw, dtype=np.float32) + 0.5
        ys = np.arange(lh, dtype=np.float32) + 0.5
        X = xs[None, :]
        Y = ys[:, None]
        u = (X - bx) / w
        v = (Y - by) / h
        grad = o.get("grad")
        aspect = w / h
        grad_rgb, grad_a = (gradient(grad, u, v, aspect) if grad else (None, None))
        radius = float(o.get("radius") or 0) * s
        rounded = o.get("radius") is not None and radius > 0
        if rounded and o.get("radii"):
            radius = tuple(float(v) * s for v in o["radii"])
        d = None

        def sdf():
            nonlocal d
            if d is None:
                d = rrect_sdf(X, Y, bx, by, w, h, radius) if rounded else None
            return d

        def shape_cov(offset):
            """Coverage of the box grown by `offset` px (negative = shrunk)."""
            if rounded:
                return cov(sdf() - offset)
            return rect_cov(X, Y, bx - offset, by - offset, bx + w + offset, by + h + offset)

        # Background.
        bgT = float(o.get("bgT", 1))
        if bgT < 0.999:
            c = shape_cov(0)
            col = _rgb(o["bg"])
            a = (1 - bgT) * alpha * c
            if grad is not None:
                L.over(col * grad_rgb, a * grad_a)
            else:
                L.over(col, a)

        # Legacy border (no UICorner, no Border UIStroke).
        b = o.get("border")
        if b and bgT < 0.999:
            t = b["size"] * s
            mode = b.get("mode", "Outline")
            lo, hi = {"Outline": (0, t), "Middle": (-t / 2, t / 2), "Inset": (-t, 0)}.get(mode, (0, t))
            ring = np.clip(
                rect_cov(X, Y, bx - hi, by - hi, bx + w + hi, by + h + hi)
                - rect_cov(X, Y, bx - lo, by - lo, bx + w + lo, by + h + lo),
                0,
                1,
            )
            L.over(_rgb(b["color"]), ring * (1 - bgT) * alpha)

        # Viewport sprite / image.
        vp = o.get("viewport")
        if vp:
            for m in vp.get("models") or []:
                if not m.get("fish"):
                    continue
                spr = fish_sprite(m["fish"], m.get("mutation"))
                if spr is None:
                    continue
                pad = 0.06
                scale = min(w * (1 - 2 * pad) / spr.width, h * (1 - 2 * pad) / spr.height)
                tw, th = max(1, int(spr.width * scale)), max(1, int(spr.height * scale))
                im = spr.resize((tw, th), Image.LANCZOS)
                tint = vp.get("c", [255, 255, 255])
                vt = float(vp.get("tr", 0))
                if tint != [255, 255, 255] or vt > 0 or alpha < 1:
                    arr = np.asarray(im, np.float32)
                    arr[..., :3] *= np.array(tint, np.float32) / 255.0
                    arr[..., 3] *= (1 - vt) * alpha
                    im = Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA")
                L.over_rgba(im, int(round(bx + (w - tw) / 2)), int(round(by + (h - th) / 2)))
        img = o.get("image")
        if img:
            gw, gh = max(1, int(w)), max(1, int(h))
            glow = _glow(gw, gh, img.get("c", [255, 255, 255]))
            if img.get("tr", 0) > 0 or alpha < 1:
                arr = np.asarray(glow, np.float32)
                arr[..., 3] *= (1 - img.get("tr", 0)) * alpha
                glow = Image.fromarray(arr.astype(np.uint8), "RGBA")
            L.over_rgba(glow, int(round(bx)), int(round(by)))

        # Border strokes.
        for st in o.get("strokes") or []:
            if st["target"] != "border" or st["tr"] >= 0.999 or st["t"] <= 0:
                continue
            t = st["t"] * s
            pos = st.get("pos", "Outer")
            if pos == "Center":
                lo, hi = -t / 2, t / 2
            elif pos == "Inner":
                lo, hi = -t, 0
            else:
                lo, hi = 0, t
            off = float(st.get("offset", 0)) * s  # BorderOffset: positive moves the ring outwards
            ring = np.clip(shape_cov(hi + off) - shape_cov(lo + off), 0, 1)
            col = _rgb(st["color"])
            a = ring * (1 - st["tr"]) * alpha
            if st.get("grad"):
                srgb, sa = gradient(st["grad"], u, v, aspect)
                L.over(col * srgb, a * sa)
            else:
                L.over(col, a)

        # Text.
        if lay is not None:
            self._text(L, o, rec, lay, tbox, bx, by, u, v, grad, alpha, aspect)

        im = L.image(premultiplied=rotated)
        if rotated:
            im = im.rotate(-rot, resample=Image.BICUBIC, expand=True).convert("RGBA")
            cx, cy = X0 + w / 2, Y0 + h / 2
            return im, int(round(cx - im.width / 2)), int(round(cy - im.height / 2))
        return im, lx0, ly0

    def _text(self, L, o, rec, lay, tbox, bx, by, u, v, grad, alpha, aspect):
        s = self.ss
        tbx, tby, tbw, _ = tbox
        ox, oy = bx + tbx, by + tby
        mask = Image.new("L", (L.w, L.h), 0)
        emoji = Image.new("RGBA", (L.w, L.h), (0, 0, 0, 0))
        T.draw(lay, tbw, mask, emoji, ox, oy, rec.get("graphemes", -1))
        fill = np.asarray(mask, np.float32) / 255.0
        ea = np.asarray(emoji, np.float32) / 255.0
        ink = np.maximum(fill, ea[..., 3])
        text_a = (1 - float(rec.get("tr", 0))) * alpha
        if text_a <= 0.001:
            return

        # UIStroke outlines (Contextual), then the legacy TextStroke, under the fill.
        for st in o.get("strokes") or []:
            if st["target"] != "text" or st["tr"] >= 0.999 or st["t"] <= 0:
                continue
            ring = dilate(ink, st["t"] * s)
            col = _rgb(st["color"])
            a = ring * (1 - st["tr"]) * text_a
            if st.get("grad"):
                srgb, sa = gradient(st["grad"], u, v, aspect)
                L.over(col * srgb, a * sa)
            else:
                L.over(col, a)
        st_tr = float(rec.get("st", 1))
        if st_tr < 0.999:
            ring = dilate(ink, max(1.0, 0.045 * lay.size))
            L.over(_rgb(rec.get("sc", [0, 0, 0])), ring * (1 - st_tr) * text_a)

        col = _rgb(rec.get("c", [0, 0, 0]))
        if grad is not None:
            grgb, ga = gradient(grad, u, v, aspect)
            L.over(col * grgb, fill * text_a * ga)
        else:
            L.over(col, fill * text_a)
        if ea[..., 3].max() > 0:
            L.over(ea[..., :3], ea[..., 3] * text_a)


def dilate(a, r):
    """Grey-scale dilation of `a` by a disc of radius r (pixels) — outlines of glyph masks."""
    if r <= 0:
        return a
    out = a.copy()
    R = int(math.ceil(r))
    h, w = a.shape
    for dy in range(-R, R + 1):
        for dx in range(-R, R + 1):
            dist = math.hypot(dx, dy)
            if dist > r + 0.5 or (dx == 0 and dy == 0):
                continue
            weight = min(1.0, r + 0.5 - dist)
            src = a[max(0, -dy) : h - max(0, dy), max(0, -dx) : w - max(0, dx)]
            dst = out[max(0, dy) : h - max(0, -dy), max(0, dx) : w - max(0, -dx)]
            np.maximum(dst, src * weight, out=dst)
    return out
