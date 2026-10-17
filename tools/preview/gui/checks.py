"""Automatic checks on gui_dump.luau frames: fill rate, layout safety, text floor.

All three work on one dumped frame (screen px, see tools/preview/README.md "GUI previews"):

fill_metric(objects, W, H) -> float  (RND-03)
    The GPU fill of the HUD in screens: the summed on-screen area of every visible quad divided
    by the screen area. A quad counts whenever Roblox would draw it, however transparent
    (effective transparency < 1): the background of a GuiObject, an image, a ViewportFrame, a
    text label (its box: the glyph quads of TextScaled text fill it), and each Border UIStroke
    (as the rect of the box grown by the stroke). Rotated quads are clipped to the screen and
    to the object's clip rect as polygons. 1.0 = one full screen of alpha-blended pixels.
    FILL_WARN (2.5) is the budget on 844x390 phones and on the small 667x375 phone (the oldest
    GPUs; FishingController shrinks the catch rays with the card there).

widgets(objects, W, H) / layout_findings(...)  (RND-02)
    Widgets are the visible children of a ScreenGui (HUD.Status, HUD.RightButtons, HUD.Toasts,
    ...) and of the containers in CONTAINERS (HUD.Fishing: ActionArea, Hint, BiteAlert,
    Minigame, CatchCard, ...). A widget's shape is the union of the rounded rects of what its
    objects draw — backgrounds, images, Border strokes (grown by their thickness) and, for a
    text label without a background, the ink box of its text — so overhanging icons and
    caption ribbons count and invisible containers do not. Skipped: transient effects (any
    path component starting with "Fx": FxRays, FxConfetti, FxCardOut ghosts...), full-screen
    layers (a widget covering >= 45 % of the screen: dims, ray holders) and the screen layers
    in LAYERS (the catch dim and rays: since v3 the dim on a phone is one side band that melts
    towards the fisher, under half the screen, but still no widget). Every pair of widgets
    and every widget against the CoreGui chrome (gui/backdrop.chrome_shapes: Jump, thumbstick,
    hotbar, top-bar buttons, desktop chat/player list) closer than MIN_GAP (16 px) is reported
    with the gap (negative = overlap depth) and the two closest points. Glow rings (FxRing)
    are reported separately when they reach into Jump or the thumbstick ("fx").

text_floor(objects)
    Visible text (not an effect, at rest: UIScale ~1) drawn smaller than TEXT_FLOOR (12 px
    TextSize after TextScaled fitting) — the STYLE.md readability floor.

selftest() checks the geometry on hand-made cases (python3 tools/preview/gui_render.py --selftest).
"""

import math

from . import text as T

FILL_WARN = 2.5
FILL_WARN_VIEWPORTS = {(844, 390), (667, 375)}
MIN_GAP = 16
TEXT_FLOOR = 12
FULLSCREEN_SHARE = 0.45
# ScreenGui children that are containers of widgets rather than widgets themselves; a dotted
# entry is a container inside one (the tank sheet's plate: its header, ✕, card strip and its own
# outline / face / strip are the widgets, though the sheet covers >= 45 % of a phone screen).
CONTAINERS = {"HUD": {"Fishing", "TankPanel", "TankPanel.Panel"}}
# Sheets (modal panels on the sheet shell, Controllers/Sheet): their widgets are checked against
# the rest of the HUD and the CoreGui, but not against each other (a sheet packs its rows tighter
# than 16 px) and not against what a modal sheet may cover (design §6.4: the idle action button);
# the thumbstick IS checked (the sheet keeps clear of it: a thumb that wants to walk would hit a
# sell button); never dropped as a full-screen layer.
SHEETS = {"HUD.TankPanel": {"HUD.Fishing.ActionArea"}}
# Screen layers (dims, ray holders) that are never widgets, whatever their size.
LAYERS = {"HUD.Fishing.CatchDim", "HUD.Fishing.CatchRays"}


# ---------------------------------------------------------------------------------------
# Polygons
# ---------------------------------------------------------------------------------------


def object_quad(o, grow=0.0):
    """Corners of an object's box (grown by `grow` px) after its rotation, clockwise."""
    cx, cy = o["x"] + o["w"] / 2, o["y"] + o["h"] / 2
    hw, hh = o["w"] / 2 + grow, o["h"] / 2 + grow
    r = math.radians(o.get("rot", 0) or 0)
    c, s = math.cos(r), math.sin(r)
    pts = []
    for dx, dy in ((-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)):
        pts.append((cx + dx * c - dy * s, cy + dx * s + dy * c))
    return pts


def _clip_poly(poly, x0, y0, x1, y1):
    """Sutherland-Hodgman clip of a polygon to an axis-aligned rect."""

    def clip(pts, inside, cross):
        out = []
        n = len(pts)
        for i in range(n):
            a, b = pts[i], pts[(i + 1) % n]
            ia, ib = inside(a), inside(b)
            if ia:
                out.append(a)
            if ia != ib:
                out.append(cross(a, b))
        return out

    def cx(a, b, x):
        t = (x - a[0]) / (b[0] - a[0])
        return (x, a[1] + t * (b[1] - a[1]))

    def cy(a, b, y):
        t = (y - a[1]) / (b[1] - a[1])
        return (a[0] + t * (b[0] - a[0]), y)

    pts = poly
    for inside, cross in (
        (lambda p: p[0] >= x0, lambda a, b: cx(a, b, x0)),
        (lambda p: p[0] <= x1, lambda a, b: cx(a, b, x1)),
        (lambda p: p[1] >= y0, lambda a, b: cy(a, b, y0)),
        (lambda p: p[1] <= y1, lambda a, b: cy(a, b, y1)),
    ):
        if not pts:
            return []
        pts = clip(pts, inside, cross)
    return pts


def poly_area(pts):
    a = 0.0
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]
        x1, y1 = pts[(i + 1) % n]
        a += x0 * y1 - x1 * y0
    return abs(a) / 2


def visible_area(o, W, H, grow=0.0):
    """On-screen area of an object's (grown) quad, inside its clip rect."""
    x0, y0, x1, y1 = 0, 0, W, H
    clip = o.get("clip")
    if clip:
        x0, y0, x1, y1 = max(x0, clip[0]), max(y0, clip[1]), min(x1, clip[2]), min(y1, clip[3])
        if x1 <= x0 or y1 <= y0:
            return 0.0
    return poly_area(_clip_poly(object_quad(o, grow), x0, y0, x1, y1))


# ---------------------------------------------------------------------------------------
# Fill
# ---------------------------------------------------------------------------------------


def _text_shown(o):
    rec = o.get("text")
    return bool(rec and rec.get("s") and float(rec.get("tr", 0)) < 1 and rec.get("graphemes", -1) != 0)


def quads(o):
    """(kind, grow) of every quad Roblox draws for the object (see fill_metric)."""
    if float(o.get("alpha", 1)) <= 0:
        return []
    out = []
    if float(o.get("bgT", 1)) < 1:
        out.append(("bg", 0.0))
    if o.get("image") and float(o["image"].get("tr", 0)) < 1:
        out.append(("image", 0.0))
    if o.get("viewport") and float(o["viewport"].get("tr", 0)) < 1:
        out.append(("viewport", 0.0))
    if _text_shown(o):
        out.append(("text", 0.0))
    for st in o.get("strokes") or []:
        if st["target"] == "border" and float(st["tr"]) < 1 and float(st["t"]) > 0:
            grow = float(st["t"]) + max(0.0, float(st.get("offset", 0)))
            if st.get("pos") == "Center":
                grow = float(st["t"]) / 2 + float(st.get("offset", 0))
            elif st.get("pos") == "Inner":
                grow = float(st.get("offset", 0))
            out.append(("stroke", max(grow, 0.0)))
    return out


def fill_metric(objects, W, H, detail=False):
    """Fill in screens (see the module doc); with detail=True also {top-level path: screens}."""
    total = 0.0
    by = {}
    screen = float(W * H)
    for o in objects:
        for _, grow in quads(o):
            a = visible_area(o, W, H, grow) / screen
            total += a
            if detail:
                key = ".".join(o["path"].split(".")[:3])
                by[key] = by.get(key, 0.0) + a
    return (total, by) if detail else total


def fill_budget_applies(W, H):
    return (W, H) in FILL_WARN_VIEWPORTS


# ---------------------------------------------------------------------------------------
# Rounded-rect geometry
# ---------------------------------------------------------------------------------------


def rrect_distance(a, b):
    """(distance, point on a, point on b) between rounded rects (x0, y0, x1, y1, r); negative =
    overlap depth (approximate). Each rect is its core rect (shrunk by r) dilated by r."""
    ax0, ay0, ax1, ay1, ar = a
    bx0, by0, bx1, by1, br = b
    ar = max(0.0, min(ar, (ax1 - ax0) / 2, (ay1 - ay0) / 2))
    br = max(0.0, min(br, (bx1 - bx0) / 2, (by1 - by0) / 2))
    ca = (ax0 + ar, ay0 + ar, ax1 - ar, ay1 - ar)
    cb = (bx0 + br, by0 + br, bx1 - br, by1 - br)
    dx = max(cb[0] - ca[2], ca[0] - cb[2], 0.0)
    dy = max(cb[1] - ca[3], ca[1] - cb[3], 0.0)
    # closest points of the core rects
    if cb[0] > ca[2]:
        pax, pbx = ca[2], cb[0]
    elif ca[0] > cb[2]:
        pax, pbx = ca[0], cb[2]
    else:
        m = (max(ca[0], cb[0]) + min(ca[2], cb[2])) / 2
        pax = pbx = m
    if cb[1] > ca[3]:
        pay, pby = ca[3], cb[1]
    elif ca[1] > cb[3]:
        pay, pby = ca[1], cb[3]
    else:
        m = (max(ca[1], cb[1]) + min(ca[3], cb[3])) / 2
        pay = pby = m
    core = math.hypot(dx, dy)
    if core > 0:
        ux, uy = (pbx - pax) / core, (pby - pay) / core
        p = (pax + ux * ar, pay + uy * ar)
        q = (pbx - ux * br, pby - uy * br)
        return core - ar - br, p, q
    # Core rects overlap: depth along the axis of least overlap.
    ox = min(ca[2], cb[2]) - max(ca[0], cb[0])
    oy = min(ca[3], cb[3]) - max(ca[1], cb[1])
    return -(min(ox, oy) + ar + br), (pax, pay), (pbx, pby)


def shape_rrect(shape):
    if shape[0] == "circle":
        _, cx, cy, r = shape
        return (cx - r, cy - r, cx + r, cy + r, r)
    _, x0, y0, x1, y1, r = shape
    return (x0, y0, x1, y1, r)


def _aabb(pts):
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    return min(xs), min(ys), max(xs), max(ys)


def _clip_box(box, clip):
    if not clip:
        return box
    x0, y0, x1, y1 = max(box[0], clip[0]), max(box[1], clip[1]), min(box[2], clip[2]), min(box[3], clip[3])
    if x1 <= x0 or y1 <= y0:
        return None
    return (x0, y0, x1, y1)


def _rotated(o):
    r = float(o.get("rot", 0) or 0) % 360
    return 0.01 < r < 359.99


def text_ink_box(o):
    """Screen box of an object's laid-out text (rotation included) and its TextSize in px."""
    rec = o.get("text")
    if not rec:
        return None, 0
    pad = rec.get("pad") or [0, 0, 0, 0]
    tbw = max(o["w"] - pad[0] - pad[2], 0)
    tbh = max(o["h"] - pad[1] - pad[3], 0)
    lay = T.layout(rec, tbw, tbh, k=float(o.get("k", 1)))
    if lay is None:
        return None, 0
    x0, y0, x1, y1 = T.extents(lay, tbw)
    # object-local (box top-left = 0, 0) -> screen, about the box centre
    cx, cy = o["w"] / 2, o["h"] / 2
    corners = [(pad[0] + x0, pad[1] + y0), (pad[0] + x1, pad[1] + y0), (pad[0] + x1, pad[1] + y1),
               (pad[0] + x0, pad[1] + y1)]
    r = math.radians(float(o.get("rot", 0) or 0))
    c, s = math.cos(r), math.sin(r)
    ox, oy = o["x"] + cx, o["y"] + cy
    pts = [(ox + (x - cx) * c - (y - cy) * s, oy + (x - cx) * s + (y - cy) * c) for x, y in corners]
    return _aabb(pts), lay.size


def object_shapes(o):
    """Rounded rects (x0, y0, x1, y1, r) of what an object draws (see widgets())."""
    alpha = float(o.get("alpha", 1))
    if alpha < 0.05:
        return []
    out = []
    radius = float(o.get("radius") or 0)
    # A rotated object is measured by its axis-aligned box — except a circle (a round button, a
    # pip swaying with its plate): turning it changes nothing, its corners must not count.
    rot = _rotated(o) and not (abs(o["w"] - o["h"]) < 0.5 and radius >= min(o["w"], o["h"]) / 2 - 0.5)

    def add(grow, r):
        if rot:
            box = _aabb(object_quad(o, grow))
            r = 0.0
        else:
            box = (o["x"] - grow, o["y"] - grow, o["x"] + o["w"] + grow, o["y"] + o["h"] + grow)
        box = _clip_box(box, o.get("clip"))
        if box and box[2] - box[0] > 0.5 and box[3] - box[1] > 0.5:
            out.append((box[0], box[1], box[2], box[3], r))

    solid = (1 - float(o.get("bgT", 1))) * alpha >= 0.1
    if solid or (o.get("image") and float(o["image"].get("tr", 0)) < 0.9) or (
        o.get("viewport") and float(o["viewport"].get("tr", 0)) < 0.9
    ):
        add(0.0, radius)
    for st in o.get("strokes") or []:
        if st["target"] == "border" and float(st["tr"]) < 0.9 and float(st["t"]) > 0:
            grow = float(st["t"]) + max(0.0, float(st.get("offset", 0)))
            if st.get("pos") == "Center":
                grow = float(st["t"]) / 2
            elif st.get("pos") == "Inner":
                grow = 0.0
            add(grow, radius + grow)
    if not solid and _text_shown(o) and float(o["text"].get("tr", 0)) < 0.9:
        box, _ = text_ink_box(o)
        if box:
            grow = max([float(st["t"]) for st in o.get("strokes") or [] if st["target"] == "text"] + [0.0])
            box = _clip_box((box[0] - grow, box[1] - grow, box[2] + grow, box[3] + grow), o.get("clip"))
            if box:
                out.append((box[0], box[1], box[2], box[3], 0.0))
    return out


# ---------------------------------------------------------------------------------------
# Widgets and the layout pass
# ---------------------------------------------------------------------------------------


def widget_of(path):
    """(widget path, part kind) of an object path: kind "solid", "fx" (a glow ring) or None."""
    parts = path.split(".")
    if len(parts) < 2:
        return None, None
    containers = CONTAINERS.get(parts[0], ())
    if ".".join(parts[1:]) in containers:
        return None, None  # a container itself
    depth = 2
    for d in range(len(parts) - 1, 1, -1):  # the deepest container the path is in
        if ".".join(parts[1:d]) in containers:
            depth = d + 1
            break
    if len(parts) < depth:
        return None, None  # a container itself
    root = ".".join(parts[:depth])
    if root in LAYERS:
        return None, None  # a screen layer (the catch dim, its rays)
    if parts[depth - 1].startswith("Fx"):
        return None, None  # a transient effect at the top (confetti, ghosts, fly-ins)
    for name in parts[depth:]:
        if name.startswith("FxRing"):
            return root, "fx"
        if name.startswith("Fx"):
            return root, None
    return root, "solid"


def widgets(objects, W, H):
    """{widget path: {"parts": [rrect...], "fx": [rrect...], "box": (x0, y0, x1, y1)}}."""
    out = {}
    for o in objects:
        root, kind = widget_of(o["path"])
        if not root or not kind:
            continue
        shapes = object_shapes(o)
        if not shapes:
            continue
        w = out.setdefault(root, {"parts": [], "fx": []})
        w["parts" if kind == "solid" else "fx"].extend(shapes)
    for name in list(out):
        w = out[name]
        if not w["parts"]:
            del out[name]
            continue
        x0 = min(p[0] for p in w["parts"])
        y0 = min(p[1] for p in w["parts"])
        x1 = max(p[2] for p in w["parts"])
        y1 = max(p[3] for p in w["parts"])
        w["box"] = (x0, y0, x1, y1)
        vis = (min(x1, W) - max(x0, 0)) * (min(y1, H) - max(y0, 0))
        if vis >= FULLSCREEN_SHARE * W * H and not sheet_of(name):
            del out[name]  # a full-screen layer (dim, rays), not a widget
    return out


def sheet_of(widget):
    """The sheet (a SHEETS key) a widget path belongs to, or None."""
    for sheet in SHEETS:
        if widget == sheet or widget.startswith(sheet + "."):
            return sheet
    return None


def _exempt(a, b):
    """True when the pair is not judged: two widgets of one sheet, or a sheet over what it may
    cover (SHEETS)."""
    sa, sb = sheet_of(a), sheet_of(b)
    if sa and sa == sb:
        return True
    if sa and b in SHEETS[sa]:
        return True
    if sb and a in SHEETS[sb]:
        return True
    return False


def _closest(parts_a, parts_b, limit):
    best = None
    for a in parts_a:
        for b in parts_b:
            # cheap reject on boxes
            if max(b[0] - a[2], a[0] - b[2], b[1] - a[3], a[1] - b[3]) > limit:
                continue
            d, p, q = rrect_distance(a, b)
            if best is None or d < best[0]:
                best = (d, p, q)
    return best


def short(path):
    """HUD.Fishing.ActionArea -> ActionArea (for reports)."""
    return path.split(".")[-1]


def layout_findings(objects, W, H, chrome, min_gap=MIN_GAP):
    """Pairs closer than min_gap: [{"a", "b", "gap", "p", "q", "kind"}], kind "widget"
    (two HUD widgets), "chrome" (a widget and a CoreGui widget) or "fx" (a glow ring in a
    touch control). `chrome` = gui/backdrop.chrome_shapes(...)."""
    ws = widgets(objects, W, H)
    names = sorted(ws)
    found = []
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            if _exempt(a, b):
                continue
            res = _closest(ws[a]["parts"], ws[b]["parts"], min_gap)
            if res and res[0] < min_gap:
                found.append({"a": a, "b": b, "gap": round(res[0], 1), "p": res[1], "q": res[2], "kind": "widget"})
        for cname, shape in chrome.items():
            if _exempt(a, cname):
                continue
            rr = shape_rrect(shape)
            res = _closest(ws[a]["parts"], [rr], min_gap)
            if res and res[0] < min_gap:
                found.append({"a": a, "b": cname, "gap": round(res[0], 1), "p": res[1], "q": res[2], "kind": "chrome"})
            if cname in ("Jump", "Thumbstick") and ws[a]["fx"]:
                res = _closest(ws[a]["fx"], [rr], 0)
                if res and res[0] < 0:
                    found.append({"a": a, "b": cname, "gap": round(res[0], 1), "p": res[1], "q": res[2], "kind": "fx"})
    found.sort(key=lambda f: f["gap"])
    return found, ws


def text_floor(objects, floor=TEXT_FLOOR):
    """[{path, px, text, box}] of visible, resting text drawn below `floor` px."""
    out = []
    for o in objects:
        root, kind = widget_of(o["path"])
        if kind != "solid" or not _text_shown(o):
            continue
        if float(o.get("alpha", 1)) < 0.5 or float(o["text"].get("tr", 0)) > 0.5:
            continue
        k = float(o.get("k", 1))
        if abs(k - 1) > 0.05:
            continue  # mid-animation (pop, slam): judged at rest
        box, size = text_ink_box(o)
        if box and 0 < size < floor - 0.25:
            out.append({"path": o["path"], "px": round(size, 1), "text": T.plain_text(o["text"])[:30],
                        "box": [round(v, 1) for v in box]})
    return out


def format_finding(f):
    kind = {"widget": "widgets", "chrome": "vs CoreGui", "fx": "glow ring in"}[f["kind"]]
    gap = f["gap"]
    if gap < 0:
        amount = "overlap <1 px" if gap > -1 else f"overlap {-gap:.0f} px"
    else:
        amount = f"gap {gap:.0f} px"
    return f"{short(f['a'])} / {short(f['b'])}: {amount} ({kind})"


# ---------------------------------------------------------------------------------------
# Self-test
# ---------------------------------------------------------------------------------------


def selftest():
    def near(a, b, eps=1e-6):
        assert abs(a - b) < eps, (a, b)

    # rect distances
    d, p, q = rrect_distance((0, 0, 10, 10, 0), (20, 0, 30, 10, 0))
    near(d, 10)
    near(p[0], 10)
    near(q[0], 20)
    d, _, _ = rrect_distance((0, 0, 10, 10, 0), (13, 14, 20, 20, 0))
    near(d, 5)
    # circles (rounded squares with r = half side): centre distance - radii
    d, _, _ = rrect_distance((0, 0, 10, 10, 5), (20, 0, 30, 10, 5))
    near(d, 10)
    d, _, _ = rrect_distance((0, 0, 10, 10, 5), (20, 20, 30, 30, 5))
    near(d, math.hypot(20, 20) - 10)
    d, _, _ = rrect_distance((0, 0, 10, 10, 0), (5, 5, 20, 20, 0))
    near(d, -5)
    # fill: a full-screen frame = 1, a half-transparent one too, a 45-degree square clipped
    obj = {"path": "HUD.A", "x": 0, "y": 0, "w": 100, "h": 50, "bgT": 0.5, "alpha": 1}
    near(fill_metric([obj], 100, 50), 1.0)
    obj2 = dict(obj, bgT=1)
    near(fill_metric([obj2], 100, 50), 0.0)
    rot = {"path": "HUD.B", "x": 40, "y": 15, "w": 20, "h": 20, "rot": 45, "bgT": 0}
    near(fill_metric([rot], 100, 50), 400 / 5000, 1e-6)
    off = {"path": "HUD.C", "x": -50, "y": 0, "w": 100, "h": 50, "bgT": 0}
    near(fill_metric([off], 100, 50), 0.5)
    stroked = {"path": "HUD.D", "x": 10, "y": 10, "w": 10, "h": 10, "bgT": 1,
               "strokes": [{"target": "border", "t": 2, "tr": 0, "pos": "Outer"}]}
    near(fill_metric([stroked], 100, 50), 14 * 14 / 5000)
    # widgets: Fx subtrees, containers and full-screen layers
    # a rotated circle is still a circle (no square corners); a rotated square grows to its box
    disc = {"x": 0, "y": 0, "w": 20, "h": 20, "radius": 10, "rot": 30, "bgT": 0}
    assert object_shapes(disc) == [(0, 0, 20, 20, 10.0)], object_shapes(disc)
    square = dict(disc, radius=0, rot=45)
    near(object_shapes(square)[0][2] - object_shapes(square)[0][0], 20 * math.sqrt(2), 1e-6)
    assert widget_of("HUD.Fishing.ActionArea.ActionButton.Face") == ("HUD.Fishing.ActionArea", "solid")
    assert widget_of("HUD.Fishing.ActionArea.ActionButton.FxRing") == ("HUD.Fishing.ActionArea", "fx")
    assert widget_of("HUD.Fishing.BiteAlert.FxRays.Ray1") == ("HUD.Fishing.BiteAlert", None)
    assert widget_of("HUD.FxConfetti.Piece") == (None, None)
    assert widget_of("HUD.Fishing") == (None, None)
    # the tank sheet: its plate is a container of widgets (header, ✕, card strip, its outline)
    assert widget_of("HUD.TankPanel") == (None, None)
    assert widget_of("HUD.TankPanel.Panel") == (None, None)
    assert widget_of("HUD.TankPanel.Panel.Header.Title") == ("HUD.TankPanel.Panel.Header", "solid")
    assert widget_of("HUD.TankPanel.Panel.Cards.Card1.Sell.Face") == ("HUD.TankPanel.Panel.Cards", "solid")
    assert widget_of("HUD.TankPanel.Panel.Lip") == ("HUD.TankPanel.Panel.Lip", "solid")
    assert sheet_of("HUD.TankPanel.Panel.Close") == "HUD.TankPanel" and sheet_of("HUD.Status") is None
    assert _exempt("HUD.TankPanel.Panel.Header", "HUD.TankPanel.Panel.Close")
    assert _exempt("HUD.TankPanel.Panel.Cards", "HUD.Fishing.ActionArea")
    assert not _exempt("HUD.TankPanel.Panel.Cards", "Thumbstick")
    assert not _exempt("HUD.TankPanel.Panel.Cards", "Jump")
    assert not _exempt("HUD.TankPanel.Panel.Header", "HUD.Status")
    assert widget_of("HUD.Status.BaseBadge") == ("HUD.Status", "solid")
    objs = [
        {"path": "HUD.Fishing.CatchDim", "x": 0, "y": 0, "w": 100, "h": 100, "bgT": 0.3},
        {"path": "HUD.Fishing.Hint", "x": 10, "y": 10, "w": 20, "h": 10, "bgT": 0},
        {"path": "HUD.Fishing.ActionArea.ActionButton", "x": 40, "y": 10, "w": 20, "h": 20, "bgT": 0,
         "radius": 10},
    ]
    ws = widgets(objs, 100, 100)
    assert set(ws) == {"HUD.Fishing.Hint", "HUD.Fishing.ActionArea"}, ws
    found, _ = layout_findings(objs, 100, 100, {"Jump": ("circle", 75, 20, 10)})
    gaps = {(f["a"], f["b"]): f["gap"] for f in found}
    near(gaps[("HUD.Fishing.ActionArea", "HUD.Fishing.Hint")], 10)
    near(gaps[("HUD.Fishing.ActionArea", "Jump")], 5)
    return True
