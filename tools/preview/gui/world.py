"""The 2D world items of a dumped frame, drawn over the backdrop and the solids and under the
HUD (RND-01).

gui/world_capture.luau records the client's world in RbxSim; the parts (the avatar, the rod,
fish, FX parts, ambient life) are solids drawn in 3D by gui/solids.py first. Everything else is
an item here, already projected with the backdrop's camera into screen px of the device
(frame["world"]["items"]), drawn far to near by their view depth `d` and hidden behind the
scene and the solids (Occluder):

  ribbon   {l, r, c[], a[], e}         a Beam or a Trail: left / right edge per sample
  dots     {p: [x, y, size, r, g, b, a], shape, e}   simulated ParticleEmitter particles
  gui      {objects}                   a BillboardGui laid out on screen (HUD objects)
  surface  {objects, size, quad}       a SurfaceGui: its canvas warped onto the face quad
  glow     {x, y, r, c, a}             a PointLight (and a SpotLight's source)
  poly     {pts, c, a, neon, dn}       a SpotLight's lit ground patch (stage 4: the siren);
                                       in dumps from before the solids also a lit part face
  highlight {polys, fc, fa, oc, oa, top}  a Highlight: its parts' projected boxes (hulled here),
                                       filled and ringed; top = AlwaysOnTop (never hidden)
and, in dumps from before the solids (still drawn):
  circle   {x, y, r, c, a, neon}       a Ball part
  fish     {fish, mutation, x, y, len, ang, box}     a fish model: docs/gear sprite

frame["world"]["marks"] = [{name, box, path?, hidden?}] are the x-ray annotations: drawn over
the HUD (dashed boxes, the leap arc) on timeline frames, and measured against the HUD's
opacity: coverage(...) = how much of each mark the HUD hides.

selftest() checks the perspective warp and the painters on synthetic items.
"""

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from . import paint as P
from . import text as T

XRAY = {"fish": (0, 229, 255), "fx": (255, 92, 230), "path": (0, 229, 255)}
COVER_ALPHA = 0.6  # HUD opacity from which a world pixel counts as hidden
HIGHLIGHT_OUTLINE = 1.5  # px (output) of a Highlight's outline ring (stage 4: the thief's mark)


class Occluder:
    """The opaque depth of the backdrop (gui/backdrop.py) merged with the frame's solids
    (gui/solids.py: the avatar, the rod, fish, FX parts, movers): an item pixel is hidden where
    the scene is nearer than the item's NEAREST point `dn` by a margin — conservative, so rings
    on the deck and splashes on the water are never cut; water itself does not occlude."""

    def __init__(self, depth, ss, origin):
        self.depth, self.ss, self.origin = depth, ss, origin

    @staticmethod
    def margin(z):
        return 0.5 + 0.05 * z

    def at(self, x, y):
        H, W = self.depth.shape
        xi, yi = int(x), int(y)
        if 0 <= xi < W and 0 <= yi < H:
            return float(self.depth[yi, xi])
        return math.inf

    def visible(self, x, y, z):
        return self.at(x, y) >= z - self.margin(z)

    def mask(self, im, X0, Y0, dn):
        """Clears the alpha of `im` (canvas px at X0, Y0) where the scene is in front of dn."""
        H, W = self.depth.shape
        h, w = im.height, im.width
        xs = np.floor((np.arange(w) + X0 + 0.5) / self.ss + self.origin[0]).astype(np.int64)
        ys = np.floor((np.arange(h) + Y0 + 0.5) / self.ss + self.origin[1]).astype(np.int64)
        inx = (xs >= 0) & (xs < W)
        iny = (ys >= 0) & (ys < H)
        sub = np.full((h, w), np.inf, np.float32)
        if inx.any() and iny.any():
            sub[np.ix_(iny, inx)] = self.depth[np.ix_(ys[iny], xs[inx])]
        hidden = sub < dn - self.margin(dn)
        if not hidden.any():
            return im
        a = np.asarray(im.split()[3]).copy()
        a[hidden] = 0
        im.putalpha(Image.fromarray(a, "L"))
        return im


def _rgba(c, a):
    return (int(c[0]), int(c[1]), int(c[2]), int(round(255 * max(0.0, min(1.0, a)))))


def _emit(c, e):
    """LightEmission brightens towards white (additive look without a real add blend)."""
    if not e:
        return c
    k = min(0.45, 0.3 * float(e))
    return [c[0] + (255 - c[0]) * k, c[1] + (255 - c[1]) * k, c[2] + (255 - c[2]) * k]


class _Region:
    """A small RGBA layer covering a screen bbox, composited onto the canvas at the end."""

    def __init__(self, canvas, ss, origin, x0, y0, x1, y1, pad=2):
        self.canvas, self.ss, self.origin = canvas, ss, origin
        X0 = int(math.floor((x0 - origin[0]) * ss)) - pad
        Y0 = int(math.floor((y0 - origin[1]) * ss)) - pad
        X1 = int(math.ceil((x1 - origin[0]) * ss)) + pad
        Y1 = int(math.ceil((y1 - origin[1]) * ss)) + pad
        X0, Y0 = max(X0, -4096), max(Y0, -4096)
        X1, Y1 = min(X1, canvas.width + 4096), min(Y1, canvas.height + 4096)
        self.ok = X1 > X0 and Y1 > Y0 and X1 > 0 and Y1 > 0 and X0 < canvas.width and Y0 < canvas.height
        if not self.ok:
            return
        # clip to the canvas (+ margin for blur)
        m = 64
        X0, Y0 = max(X0, -m), max(Y0, -m)
        X1, Y1 = min(X1, canvas.width + m), min(Y1, canvas.height + m)
        self.X0, self.Y0 = X0, Y0
        self.im = Image.new("RGBA", (X1 - X0, Y1 - Y0), (0, 0, 0, 0))
        self.draw = ImageDraw.Draw(self.im)

    def pt(self, x, y):
        return ((x - self.origin[0]) * self.ss - self.X0, (y - self.origin[1]) * self.ss - self.Y0)

    def done(self, occ=None, dn=None):
        if self.ok:
            if occ is not None and dn is not None:
                self.im = occ.mask(self.im, self.X0, self.Y0, dn)
            T.paste_rgba(self.canvas, self.im, self.X0, self.Y0)


def _bbox(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def _glow_under(canvas, ss, origin, pts, color, alpha, radius, occ=None, dn=None):
    x0, y0, x1, y1 = _bbox(pts)
    r = radius
    reg = _Region(canvas, ss, origin, x0 - r, y0 - r, x1 + r, y1 + r)
    if not reg.ok:
        return
    mask = Image.new("L", reg.im.size, 0)
    ImageDraw.Draw(mask).polygon([reg.pt(*p) for p in pts], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(r * ss / 2))
    arr = np.asarray(mask, np.float32) * alpha
    layer = np.zeros(reg.im.size[::-1] + (4,), np.uint8)
    layer[..., 0], layer[..., 1], layer[..., 2] = color[0], color[1], color[2]
    layer[..., 3] = np.clip(arr, 0, 255).astype(np.uint8)
    reg.im = Image.fromarray(layer, "RGBA")
    reg.done(occ, dn)


def _near(it):
    return float(it.get("dn", it.get("d", 0)))


def _poly(canvas, ss, origin, it, occ=None):
    pts = [tuple(p) for p in it["pts"]]
    if len(pts) < 3:
        return
    c = it["c"]
    if it.get("neon"):
        _glow_under(canvas, ss, origin, pts, c, 0.55 * it["a"], 5, occ, _near(it))
    x0, y0, x1, y1 = _bbox(pts)
    reg = _Region(canvas, ss, origin, x0, y0, x1, y1)
    if reg.ok:
        reg.draw.polygon([reg.pt(*p) for p in pts], fill=_rgba(c, it["a"]))
        reg.done(occ, _near(it))


def _circle(canvas, ss, origin, it, occ=None):
    x, y, r = it["x"], it["y"], max(it["r"], 0.6)
    if it.get("neon"):
        pts = [(x + r * math.cos(a), y + r * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 16, endpoint=False)]
        _glow_under(canvas, ss, origin, pts, it["c"], 0.55 * it["a"], 5, occ, _near(it))
    reg = _Region(canvas, ss, origin, x - r, y - r, x + r, y + r)
    if reg.ok:
        a0, b0 = reg.pt(x - r, y - r)
        a1, b1 = reg.pt(x + r, y + r)
        reg.draw.ellipse([a0, b0, a1, b1], fill=_rgba(it["c"], it["a"]))
        reg.done(occ, _near(it))


def _ribbon(canvas, ss, origin, it, occ=None):
    left, right = it["l"], it["r"]
    n = min(len(left), len(right))
    if n < 2:
        return
    x0, y0, x1, y1 = _bbox(list(left[:n]) + list(right[:n]))
    reg = _Region(canvas, ss, origin, x0, y0, x1, y1)
    if not reg.ok:
        return
    e = it.get("e", 0)
    zs = it.get("z") or []
    for i in range(n - 1):
        a = (it["a"][i] + it["a"][i + 1]) / 2
        if a <= 0.01:
            continue
        if occ is not None and i + 1 < len(zs):
            mx = (left[i][0] + left[i + 1][0] + right[i][0] + right[i + 1][0]) / 4
            my = (left[i][1] + left[i + 1][1] + right[i][1] + right[i + 1][1]) / 4
            if not occ.visible(mx, my, min(zs[i], zs[i + 1])):
                continue
        c = _emit(it["c"][i], e)
        quad = [reg.pt(*left[i]), reg.pt(*left[i + 1]), reg.pt(*right[i + 1]), reg.pt(*right[i])]
        reg.draw.polygon(quad, fill=_rgba(c, a))
    reg.done()


def _dots(canvas, ss, origin, it, occ=None):
    pts = it["p"]
    if not pts:
        return
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    big = max(p[2] for p in pts)
    reg = _Region(canvas, ss, origin, min(xs) - big, min(ys) - big, max(xs) + big, max(ys) + big)
    if not reg.ok:
        return
    shape = it.get("shape", "square")
    e = it.get("e", 0)
    for i, p in enumerate(pts):
        if occ is not None and len(p) > 7 and not occ.visible(p[0], p[1], p[7]):
            continue
        x, y = reg.pt(p[0], p[1])
        r = max(p[2], 1.2) * ss / 2
        col = _rgba(_emit(p[3:6], e), p[6])
        if shape == "spark":
            k = r * 0.32
            star = [(x, y - r), (x + k, y - k), (x + r, y), (x + k, y + k), (x, y + r), (x - k, y + k), (x - r, y),
                    (x - k, y - k)]
            reg.draw.polygon(star, fill=col)
        elif shape == "soft":
            soft = col[:3] + (int(col[3] * 0.55),)
            reg.draw.ellipse([x - r, y - r, x + r, y + r], fill=soft)
        else:  # confetti: small rotated squares
            ang = (i * 47) % 180
            ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
            sq = [(x + ca * dx - sa * dy, y + sa * dx + ca * dy) for dx, dy in ((-r, -r * 0.6), (r, -r * 0.6), (r, r * 0.6),
                                                                                   (-r, r * 0.6))]
            reg.draw.polygon(sq, fill=col)
    reg.done()


def _fish(canvas, ss, origin, it, occ=None):
    spr = P.fish_sprite(it["fish"], it.get("mutation"))
    if spr is None:
        return
    box = it.get("box") or [it["x"] - 10, it["y"] - 10, it["x"] + 10, it["y"] + 10]
    bw, bh = box[2] - box[0], box[3] - box[1]
    width = max(float(it.get("len", 0)) * 1.1, 0.75 * max(bw, bh), 4.0)
    ang = float(it.get("ang", 0))
    im = spr
    if abs(ang) > 90:  # nose to the left: mirror, then turn the rest of the way
        im = im.transpose(Image.FLIP_LEFT_RIGHT)
        ang = ang - 180 if ang > 0 else ang + 180
    scale = width * ss / im.width
    tw, th = max(1, int(im.width * scale)), max(1, int(im.height * scale))
    im = im.resize((tw, th), Image.LANCZOS)
    if abs(ang) > 0.5:
        im = im.rotate(-ang, resample=Image.BICUBIC, expand=True)
    cx = (it["x"] - origin[0]) * ss
    cy = (it["y"] - origin[1]) * ss
    X0, Y0 = int(round(cx - im.width / 2)), int(round(cy - im.height / 2))
    if occ is not None:
        im = occ.mask(im.convert("RGBA"), X0, Y0, _near(it))
    T.paste_rgba(canvas, im, X0, Y0)


def _glow(canvas, ss, origin, it, occ=None):
    r = max(it["r"], 2)
    reg = _Region(canvas, ss, origin, it["x"] - r, it["y"] - r, it["x"] + r, it["y"] + r)
    if not reg.ok:
        return
    w, h = reg.im.size
    cx, cy = reg.pt(it["x"], it["y"])
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.hypot(xx + 0.5 - cx, yy + 0.5 - cy) / (r * ss)
    a = np.clip(1 - d, 0, 1) ** 2 * it["a"] * 255
    layer = np.zeros((h, w, 4), np.uint8)
    layer[..., 0], layer[..., 1], layer[..., 2] = it["c"][0], it["c"][1], it["c"][2]
    layer[..., 3] = a.astype(np.uint8)
    reg.im = Image.fromarray(layer, "RGBA")
    reg.done(occ, _near(it))


def _hull(pts):
    """Convex hull (monotone chain) of [(x, y)...], counter-clockwise."""
    pts = sorted(set((float(p[0]), float(p[1])) for p in pts))
    if len(pts) < 3:
        return pts

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def _highlight(canvas, ss, origin, it, occ=None):
    """A Highlight (stage 4: the thief's mark): the union of its parts' projected boxes filled
    with fc at fa and ringed (HIGHLIGHT_OUTLINE px outside the union) with oc at oa; `top`
    (AlwaysOnTop) is never hidden, else the scene in front of the adornee hides it."""
    hulls = [_hull(p) for p in it.get("polys") or []]
    hulls = [h for h in hulls if len(h) >= 3]
    if not hulls:
        return
    allpts = [p for h in hulls for p in h]
    pad = HIGHLIGHT_OUTLINE + 2
    x0, y0, x1, y1 = _bbox(allpts)
    reg = _Region(canvas, ss, origin, x0 - pad, y0 - pad, x1 + pad, y1 + pad)
    if not reg.ok:
        return
    mask = Image.new("L", reg.im.size, 0)
    md = ImageDraw.Draw(mask)
    for h in hulls:
        md.polygon([reg.pt(*p) for p in h], fill=255)
    size = int(HIGHLIGHT_OUTLINE * ss) * 2 + 1
    ring = np.asarray(mask.filter(ImageFilter.MaxFilter(size)), np.float32) - np.asarray(mask, np.float32)
    inside = np.asarray(mask, np.float32) / 255.0
    ring = np.clip(ring, 0, 255) / 255.0
    fa, oa = float(it.get("fa", 0)), float(it.get("oa", 0))
    fc, oc = np.asarray(it.get("fc", (255, 0, 0)), np.float32), np.asarray(it.get("oc", (255, 255, 255)), np.float32)
    a_fill, a_ring = inside * fa, ring * oa
    a = a_fill + a_ring * (1 - a_fill)
    rgb = (fc[None, None, :] * a_fill[..., None] + oc[None, None, :] * (a_ring * (1 - a_fill))[..., None]) / \
        np.maximum(a, 1e-6)[..., None]
    layer = np.zeros(mask.size[::-1] + (4,), np.uint8)
    layer[..., :3] = np.clip(rgb, 0, 255).astype(np.uint8)
    layer[..., 3] = np.clip(a * 255, 0, 255).astype(np.uint8)
    reg.im = Image.fromarray(layer, "RGBA")
    reg.done(None if it.get("top") else occ, _near(it))


def perspective_coeffs(src, dst):
    """Coefficients for PIL's Image.PERSPECTIVE transform that maps output points `dst` to input
    points `src` (4 pairs)."""
    A, b = [], []
    for (x, y), (u, v) in zip(dst, src):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y])
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y])
        b += [u, v]
    return np.linalg.solve(np.array(A, float), np.array(b, float)).tolist()


def _surface(canvas, ss, origin, it, occ=None):
    cw, ch = it["size"]
    if cw < 1 or ch < 1 or not it.get("objects"):
        return
    k = min(1.0, 512.0 / max(cw, ch))
    src = Image.new("RGBA", (max(1, int(cw * k)), max(1, int(ch * k))), (0, 0, 0, 0))
    P.Painter(k).paint(it["objects"], src)
    quad = it["quad"]
    x0, y0, x1, y1 = _bbox(quad)
    X0 = int(math.floor((x0 - origin[0]) * ss))
    Y0 = int(math.floor((y0 - origin[1]) * ss))
    X1 = int(math.ceil((x1 - origin[0]) * ss))
    Y1 = int(math.ceil((y1 - origin[1]) * ss))
    if X1 - X0 < 1 or Y1 - Y0 < 1 or (X1 - X0) * (Y1 - Y0) > 25_000_000:
        return
    dst = [((p[0] - origin[0]) * ss - X0, (p[1] - origin[1]) * ss - Y0) for p in quad]
    corners = [(0, 0), (src.width, 0), (src.width, src.height), (0, src.height)]
    try:
        coeffs = perspective_coeffs(corners, dst)
    except np.linalg.LinAlgError:
        return
    out = src.transform((X1 - X0, Y1 - Y0), Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    # transform() samples outside the source as transparent black: keep only the quad
    mask = Image.new("L", out.size, 0)
    ImageDraw.Draw(mask).polygon(dst, fill=255)
    a = np.minimum(np.asarray(out.split()[3], np.uint16), np.asarray(mask, np.uint16)).astype(np.uint8)
    out.putalpha(Image.fromarray(a, "L"))
    if occ is not None:
        out = occ.mask(out, X0, Y0, _near(it))
    T.paste_rgba(canvas, out, X0, Y0)


def paint(canvas, world, ss, origin=(0, 0), depth=None):
    """Draw the world items (far to near) on an RGBA canvas at `ss` x the screen; `depth` =
    the backdrop's depth (screen px) for occlusion by the scene, or None."""
    items = sorted((world or {}).get("items") or [], key=lambda it: -float(it.get("d", 0)))
    painter = P.Painter(ss)
    occ = Occluder(depth, ss, origin) if depth is not None else None
    for it in items:
        k = it.get("k")
        try:
            if k == "poly":
                _poly(canvas, ss, origin, it, occ)
            elif k == "circle":
                _circle(canvas, ss, origin, it, occ)
            elif k == "ribbon":
                _ribbon(canvas, ss, origin, it, occ)
            elif k == "dots":
                _dots(canvas, ss, origin, it, occ)
            elif k == "fish":
                _fish(canvas, ss, origin, it, occ)
            elif k == "gui":
                if occ is None:
                    painter.paint(it.get("objects") or [], canvas, origin=origin)
                else:
                    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
                    painter.paint(it.get("objects") or [], layer, origin=origin)
                    T.paste_rgba(canvas, occ.mask(layer, 0, 0, _near(it)), 0, 0)
            elif k == "surface":
                _surface(canvas, ss, origin, it, occ)
            elif k == "glow":
                _glow(canvas, ss, origin, it, occ)
            elif k == "highlight":
                _highlight(canvas, ss, origin, it, occ)
        except (ValueError, ZeroDivisionError, OverflowError) as exc:  # a degenerate projection
            T.warn_once(f"world item {k} skipped: {exc}")


def coverage(hud, world, ss, origin=(0, 0)):
    """{mark name: share of its box hidden by the HUD} (HUD layer alpha >= COVER_ALPHA)."""
    out = {}
    alpha = np.asarray(hud.split()[3], np.float32) / 255.0
    H, W = alpha.shape
    for m in (world or {}).get("marks") or []:
        if m.get("hidden") or not m.get("box"):
            continue
        x0, y0, x1, y1 = m["box"]
        X0 = max(0, int((x0 - origin[0]) * ss))
        Y0 = max(0, int((y0 - origin[1]) * ss))
        X1 = min(W, int(math.ceil((x1 - origin[0]) * ss)))
        Y1 = min(H, int(math.ceil((y1 - origin[1]) * ss)))
        if X1 <= X0 or Y1 <= Y0:
            continue
        region = alpha[Y0:Y1, X0:X1]
        out[m["name"]] = round(float((region >= COVER_ALPHA).mean()), 2)
    return out


def _dashed_rect(d, box, color, width, dash=6):
    x0, y0, x1, y1 = box
    for (ax, ay), (bx, by) in (((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))):
        length = math.hypot(bx - ax, by - ay)
        n = max(1, int(length / dash))
        for i in range(0, n, 2):
            t0, t1 = i / n, min(1, (i + 1) / n)
            d.line([(ax + (bx - ax) * t0, ay + (by - ay) * t0), (ax + (bx - ax) * t1, ay + (by - ay) * t1)],
                   fill=color, width=width)


def xray(image, world, cover=None, scale=1.0):
    """Annotate a final RGB/RGBA image (screen px x `scale`): dashed boxes of the marks with
    their names and how much the HUD hides them, the leap arc as dots."""
    marks = (world or {}).get("marks") or []
    if not marks:
        return image
    im = image.convert("RGBA")
    over = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    font = T.text_font("Nunito", 800, max(9.0, 11 * scale) / 1.364 * 1.364)
    for m in marks:
        box = m.get("box")
        if not box:
            continue
        fishy = m["name"] in ("HeldFish", "Leap", "Dive") or m.get("path") is not None
        col = XRAY["fish"] if fishy else XRAY["fx"]
        path = m.get("path") or []
        for i, p in enumerate(path):
            if i % 2 == 0:
                x, y = p[0] * scale, p[1] * scale
                d.ellipse([x - 1.5, y - 1.5, x + 1.5, y + 1.5], fill=XRAY["path"] + (200,))
        if m.get("hidden"):
            continue
        b = [v * scale for v in box]
        _dashed_rect(d, b, col + (230,), max(1, int(round(1.5 * scale))))
        label = m["name"]
        if cover and m["name"] in cover:
            label += f" {int(round(cover[m['name']] * 100))}% under HUD"
        tw = font.getlength(label)
        ty = b[1] - 14 * scale if b[1] > 16 * scale else b[3] + 2
        d.rectangle([b[0], ty, b[0] + tw + 6, ty + 13 * scale], fill=(10, 14, 24, 190))
        d.text((b[0] + 3, ty + 1), label, font=font, fill=col + (255,))
    im.alpha_composite(over)
    return im


def selftest():
    # perspective: the identity quad maps onto itself
    c = perspective_coeffs([(0, 0), (10, 0), (10, 10), (0, 10)], [(0, 0), (10, 0), (10, 10), (0, 10)])
    assert all(abs(a - b) < 1e-9 for a, b in zip(c, [1, 0, 0, 0, 1, 0, 0, 0])), c
    canvas = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
    paint(canvas, {"items": [
        {"k": "poly", "pts": [[10, 10], [30, 10], [30, 30], [10, 30]], "c": [255, 0, 0], "a": 1, "d": 5},
        {"k": "circle", "x": 50, "y": 50, "r": 5, "c": [0, 255, 0], "a": 1, "d": 4},
        {"k": "ribbon", "l": [[60, 10], [90, 10]], "r": [[60, 14], [90, 14]], "c": [[0, 0, 255], [0, 0, 255]],
         "a": [1, 1], "d": 3},
        {"k": "dots", "p": [[20, 80, 4, 255, 255, 0, 1]], "shape": "square", "d": 2},
    ]}, 1)
    px = canvas.load()
    assert px[20, 20][:3] == (255, 0, 0), px[20, 20]
    assert px[50, 50][1] == 255, px[50, 50]
    assert px[75, 12][2] == 255, px[75, 12]
    assert px[20, 80][3] > 0, px[20, 80]
    # occlusion: a near wall over the left half hides a far square there, not a near one
    depth = np.full((100, 100), np.inf, np.float32)
    depth[:, :50] = 5.0
    c2 = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
    paint(c2, {"items": [
        {"k": "poly", "pts": [[30, 10], [70, 10], [70, 30], [30, 30]], "c": [255, 0, 0], "a": 1, "d": 20},
        {"k": "poly", "pts": [[30, 60], [70, 60], [70, 80], [30, 80]], "c": [0, 255, 0], "a": 1, "d": 3},
    ]}, 1, depth=depth)
    q = c2.load()
    assert q[40, 20][3] == 0 and q[60, 20][3] == 255, (q[40, 20], q[60, 20])
    assert q[40, 70][3] == 255, q[40, 70]
    # a Highlight: the union filled at fa, a ring outside it at oa; Occluded hides behind the
    # wall, AlwaysOnTop does not
    c3 = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
    hl = {"k": "highlight", "polys": [[[30, 40], [45, 40], [45, 60], [30, 60]], [[44, 40], [70, 40], [70, 60], [44, 60]]],
          "fc": [255, 0, 0], "fa": 0.3, "oc": [255, 0, 0], "oa": 1, "d": 20}
    paint(c3, {"items": [hl]}, 1, depth=depth)
    h = c3.load()
    assert h[40, 50][3] == 0 and 60 < h[60, 50][3] < 100, (h[40, 50], h[60, 50])  # hidden / fill 0.3
    assert h[71, 50][3] == 255 and h[60, 39][3] == 255, (h[71, 50], h[60, 39])  # the ring
    assert h[75, 50][3] == 0, h[75, 50]
    c4 = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
    paint(c4, {"items": [dict(hl, top=True)]}, 1, depth=depth)
    assert c4.load()[40, 50][3] > 60, c4.load()[40, 50]  # AlwaysOnTop: through the wall
    hud = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
    ImageDraw.Draw(hud).rectangle([0, 0, 49, 99], fill=(255, 255, 255, 255))
    cov = coverage(hud, {"marks": [{"name": "A", "box": [0, 0, 100, 100]}]}, 1)
    assert abs(cov["A"] - 0.5) < 0.01, cov
    return True
