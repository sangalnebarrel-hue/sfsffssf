#!/usr/bin/env python3
"""GUI preview renderer: draws HUD dumps (tools/preview/gui_dump.luau) as a player sees them.

  # the whole standard set (phone + desktop stills and animation sheets, 30 fps bursts on the
  # phone, overviews) plus the layout-safety / fill / text checks on 5 devices, ~10 min
  python3 tools/preview/gui_render.py --all --out /tmp/ui
  # some scenarios on some devices (dumps them first)
  python3 tools/preview/gui_render.py --scenario bite,catch_mythic --devices phone --sheets --out /tmp/ui
  # the timelines: real sessions with the 3D world (the posed avatar, FX, ambient life) under
  # the HUD, a beat ruler per frame (catches, fishing_timeline, trophy_hold, lost_fish, ambient_pier)
  python3 tools/preview/gui_render.py --timeline --out /tmp/ui
  # existing dumps
  python3 tools/preview/gui_render.py /tmp/ui/json/phone/bite.json --out /tmp/ui
  python3 tools/preview/gui_render.py --list
  python3 tools/preview/gui_render.py --selftest

Output (in --out): <device>/<scenario>.png (the still; several stills: <scenario>@<t>.png),
<device>/<scenario>_sheet.png (animation contact sheet), <device>/<scenario>_burst.png (the
first 0.8 s at 30 fps), <device>/<scenario>_timeline.png (timelines), <scenario>_world.png
(the timeline without the HUD), <scenario>_motion.png (what moved, still camera), <device>/
<scenario>_layout.png (a still with its layout-safety findings drawn), overview_<device>.png,
checks.txt / checks.json (fill per frame, layout safety, text floor), json/<device>/
<scenario>.json (the dumps). Full documentation: tools/preview/README.md, "GUI previews".
"""

import argparse
import copy
import json
import math
import multiprocessing
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402
from PIL import Image, ImageDraw, ImageFilter  # noqa: E402

from gui import backdrop as B  # noqa: E402
from gui import checks as C  # noqa: E402
from gui import paint as P  # noqa: E402
from gui import solids as S  # noqa: E402
from gui import text as T  # noqa: E402
from gui import world as WD  # noqa: E402

STANDARD_DEVICES = ("phone", "desktop")
# Dumped by --all for the layout-safety / fill / text checks only (no images unless a still fails).
SAFETY_DEVICES = ("phone_notch", "phone_small", "tablet")
TIMELINE_DEVICES = ("phone",)
VIEWPORTS = {
    "phone": (844, 390),
    "phone_notch": (844, 390),
    "phone_small": (667, 375),
    "tablet": (1024, 768),
    "desktop": (1280, 720),
    "console": (1920, 1080),
}
CAPTION_H = 30
INK = (20, 24, 38)
RULER_H = 40
TIMELINE_TAIL = 0.7  # timeline composites end this long after the last beat
BEAT_COLORS = [
    (255, 210, 63), (255, 107, 107), (94, 234, 212), (129, 161, 255), (255, 155, 230), (167, 243, 108),
    (255, 170, 80), (200, 160, 255), (120, 220, 255), (255, 240, 160), (255, 130, 170), (150, 255, 200),
    (230, 230, 230), (255, 200, 120), (180, 200, 255), (210, 255, 140),
]


def log(msg):
    print(f"[gui_render] {msg}", flush=True)


def lune_bin():
    return os.environ.get("LUNE_BIN", "/opt/tools/l11/lune")


def as_list(v):
    """Lune encodes an empty table as {}: lists may come back as dicts."""
    if not v:
        return []
    return v if isinstance(v, list) else list(v.values())


# ---------------------------------------------------------------------------------------
# Rendering one frame
# ---------------------------------------------------------------------------------------

_bg_cache = {}
_ctx_cache = {}


def frame_camera(dump, frame):
    w = frame.get("world") or {}
    return w.get("cam") or dump.get("camera")


def backdrop_variant(dump, frame):
    """(avatar, exclude) of a frame's backdrop: a frame with solids draws the real avatar (and,
    in world dumps, the movers) itself — the backdrop leaves them out; older dumps get the
    blocky stand-in."""
    w = frame.get("world")
    if not w or "solids" not in w:
        return True, None
    scene = dump.get("scene") or {}
    exclude = as_list(scene.get("exclude")) if isinstance(scene, dict) else []
    return False, (exclude or None)


def get_backdrop(W, H, opts, cam=None, avatar=True, exclude=None):
    """(image, depth or None, depth_ss or None) of the backdrop for a camera and variant (see
    gui/backdrop.py)."""
    key = (W, H, opts.bg, opts.place, B.camera_key(cam), avatar, B.exclude_key(exclude))
    if key not in _bg_cache:
        _bg_cache[key] = B.backdrop(W, H, opts.bg, opts.place, cam, avatar=avatar, exclude=exclude, layers=True)
    return _bg_cache[key]


def world_context(opts):
    if opts.place not in _ctx_cache:
        try:
            _ctx_cache[opts.place] = B.world_context(opts.place)
        except Exception as exc:  # no export: the solids cannot be placed
            T.warn_once(f"world context failed ({exc}); solids not drawn")
            _ctx_cache[opts.place] = None
    return _ctx_cache[opts.place]


def object_box(o):
    """Axis-aligned screen box (x0, y0, x1, y1) of an object, rotation included."""
    cx, cy = o["x"] + o["w"] / 2, o["y"] + o["h"] / 2
    r = math.radians(o.get("rot", 0))
    hw = abs(o["w"] / 2 * math.cos(r)) + abs(o["h"] / 2 * math.sin(r))
    hh = abs(o["w"] / 2 * math.sin(r)) + abs(o["h"] / 2 * math.cos(r))
    return cx - hw, cy - hh, cx + hw, cy + hh


def render_frame(dump, frame, opts, region=None, xray=False):
    """(RGB image, coverage) of one frame: backdrop, world FX, HUD, CoreGui chrome (and the
    x-ray of the world marks). `region` = (x0, y0, x1, y1) crop. coverage = {mark: share of
    its box the HUD hides} for world frames, else {}."""
    W, H = dump["viewport"]
    ss = opts.ss
    x0, y0, x1, y1 = region or (0, 0, W, H)
    x0, y0 = int(math.floor(x0)), int(math.floor(y0))
    x1, y1 = int(math.ceil(x1)), int(math.ceil(y1))
    cam = frame_camera(dump, frame)
    avatar, exclude = backdrop_variant(dump, frame)
    bg, depth, depth_ss = get_backdrop(W, H, opts, cam, avatar, exclude)
    canvas = bg.crop((x0, y0, x1, y1)).resize(((x1 - x0) * ss, (y1 - y0) * ss), Image.BILINEAR).convert("RGBA")
    world = frame.get("world")
    if world and opts.world:
        # the 3D part (avatar, rod, fish, FX parts, ambient life) with a z-buffer against the
        # backdrop's depth, then the 2D items hidden behind both
        ctx = world_context(opts) if world.get("solids") or world.get("movers") else None
        if ctx is not None and opts.bg in ("pier", None):
            layer, sdepth = S.render(world, dump.get("scene"), cam or B.default_camera(), ctx, W, H, ss, depth_ss)
            if layer is not None:
                canvas.alpha_composite(layer.crop((x0 * ss, y0 * ss, x1 * ss, y1 * ss)))
                depth = sdepth if depth is None else np.minimum(depth, sdepth)
        WD.paint(canvas, world, ss, origin=(x0, y0), depth=depth)
    objects = frame["objects"]
    if region:
        keep = []
        for o in objects:
            bx0, by0, bx1, by1 = object_box(o)
            pad = 40 + max([st["t"] for st in o.get("strokes") or []] + [0])
            if bx1 + pad < x0 or by1 + pad < y0 or bx0 - pad > x1 or by0 - pad > y1:
                if not o.get("text"):
                    continue
            keep.append(o)
        objects = keep
    hud = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    if opts.hud:
        P.Painter(ss).paint(objects, hud, origin=(x0, y0))
    cover = WD.coverage(hud, world, ss, origin=(x0, y0)) if world else {}
    canvas.alpha_composite(hud)
    safe = tuple(dump.get("safe") or (0, 0, 0))
    if opts.chrome:
        if region:
            full = Image.new("RGBA", (W * ss, H * ss), (0, 0, 0, 0))
            B.draw_chrome(full, W, H, ss, dump.get("touch"), frame.get("tools"), safe=safe)
            canvas.alpha_composite(full.crop((x0 * ss, y0 * ss, x1 * ss, y1 * ss)))
        else:
            B.draw_chrome(canvas, W, H, ss, dump.get("touch"), frame.get("tools"), safe=safe)
    out = canvas.reduce(ss) if ss > 1 else canvas
    if xray and world and not region:
        out = WD.xray(out, world, cover)
    return out.convert("RGB"), cover


def _font(px, weight=700):
    return T.text_font("Nunito", weight, px / 1.364)


def with_caption(im, text):
    out = Image.new("RGB", (im.width, im.height + CAPTION_H), INK)
    out.paste(im, (0, 0))
    d = ImageDraw.Draw(out)
    d.text((10, im.height + CAPTION_H / 2), text, font=_font(17), fill=(235, 238, 245), anchor="lm")
    return out


# ---------------------------------------------------------------------------------------
# Checks (RND-02 layout safety, RND-03 fill, text floor)
# ---------------------------------------------------------------------------------------


def frame_checks(dump, frame, layout=True):
    W, H = dump["viewport"]
    fill, by = C.fill_metric(frame["objects"], W, H, detail=True)
    res = {"t": frame["t"], "fill": round(fill, 2), "fill_by": {k: round(v, 2) for k, v in by.items() if v >= 0.05}}
    if layout:
        chrome = B.chrome_shapes(W, H, dump.get("touch"), as_list(frame.get("tools")) or None,
                                 tuple(dump.get("safe") or (0, 0, 0)))
        found, ws = C.layout_findings(frame["objects"], W, H, chrome)
        res["layout"] = found
        res["widgets"] = {name: w["box"] for name, w in ws.items()}
        res["text"] = C.text_floor(frame["objects"])
    return res


def checks_caption(dev, W, H, name, t):
    return (f"{dev} {W}×{H} · {name} · {t:.2f} s · gaps < {C.MIN_GAP} px: red < 8, amber, pink = glow ring; "
            f"yellow = text < {C.TEXT_FLOOR} px")


def draw_findings(im, chk):
    """A copy of a still with its checks drawn: the widget boxes (thin), red/amber/pink lines
    between the closest points with the gap in px, yellow boxes around text under the floor."""
    out = im.convert("RGBA")
    over = Image.new("RGBA", out.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    f = _font(13, 800)
    small = _font(11, 700)
    for name, box in (chk.get("widgets") or {}).items():
        d.rectangle(list(box), outline=(255, 255, 255, 110), width=1)
        d.text((box[0] + 2, box[1] + 1), C.short(name), font=small, fill=(255, 255, 255, 150))
    for tf in chk.get("text") or []:
        x0, y0, x1, y1 = tf["box"]
        d.rectangle([x0 - 1, y0 - 1, x1 + 1, y1 + 1], outline=(255, 226, 64, 255), width=2)
        d.text((x0, y1 + 2), f"{tf['px']:g} px", font=small, fill=(255, 226, 64, 255))
    for fd in chk.get("layout") or []:
        col = (255, 59, 48) if fd["gap"] < 8 else (255, 176, 32)
        if fd["kind"] == "fx":
            col = (255, 92, 230)
        (px, py), (qx, qy) = fd["p"], fd["q"]
        d.line([(px, py), (qx, qy)], fill=col + (255,), width=3)
        for x, y in ((px, py), (qx, qy)):
            d.ellipse([x - 4, y - 4, x + 4, y + 4], outline=col + (255,), width=2)
        label = f"{fd['gap']:.0f}px {C.short(fd['a'])}/{C.short(fd['b'])}"
        mx, my = (px + qx) / 2, (py + qy) / 2
        tw = f.getlength(label)
        bx = min(max(mx - tw / 2 - 4, 2), out.width - tw - 10)
        by = min(max(my - 22, 2), out.height - 20)
        d.rectangle([bx, by, bx + tw + 8, by + 18], fill=(10, 14, 24, 220))
        d.text((bx + 4, by + 1), label, font=f, fill=col + (255,))
    out.alpha_composite(over)
    return out.convert("RGB")


# ---------------------------------------------------------------------------------------
# Sheets, rulers, timeline
# ---------------------------------------------------------------------------------------


def still_name(dump, frame, n_stills):
    if n_stills == 1:
        return f"{dump['scenario']}.png"
    return f"{dump['scenario']}@{frame['t']:.2f}.png"


def roi_region(dump, frames, spec):
    W, H = dump["viewport"]
    roi = as_list((spec or {}).get("roi"))
    if not roi:
        return (0, 0, W, H)
    box = None
    # { frac = { x0, y0, x1, y1 } } — a fixed part of the screen (world FX: the bobber, the line)
    for r in roi:
        if isinstance(r, dict) and isinstance(r.get("frac"), list) and len(r["frac"]) == 4:
            fx = r["frac"]
            b = (fx[0] * W, fx[1] * H, fx[2] * W, fx[3] * H)
            box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    for f in frames:
        for o in f["objects"]:
            if o["path"] in roi:
                b = object_box(o)
                box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    if box is None:
        return (0, 0, W, H)
    m = float(spec.get("margin", 0.04)) * H
    return (max(0, box[0] - m), max(0, box[1] - m), min(W, box[2] + m), min(H, box[3] + m))


def beat_list(dump):
    return [b for b in as_list(dump.get("beats")) if isinstance(b, dict)]


def draw_ruler(d, x, y, w, t, t0, t1, beats, fill=None, cover=None, prev_t=None):
    """A beat ruler under a cell: the window t0..t1, the beats as numbered ticks, the frame
    time as a white cursor; the beats since the previous cell and the frame's numbers."""
    d.rectangle([x, y, x + w, y + RULER_H], fill=(12, 15, 26))
    ax0, ax1 = x + 10, x + w - 10
    ay = y + 13

    def tx(v):
        return ax0 + (ax1 - ax0) * (v - t0) / max(t1 - t0, 1e-6)

    d.line([(ax0, ay), (ax1, ay)], fill=(90, 98, 120), width=2)
    for s in range(int(math.ceil(t0)), int(math.floor(t1)) + 1):
        d.line([(tx(s), ay - 4), (tx(s), ay + 4)], fill=(120, 128, 150), width=1)
    small = _font(10, 800)
    for i, b in enumerate(beats):
        if not (t0 - 1e-6 <= b["t"] <= t1 + 1e-6):
            continue
        col = BEAT_COLORS[i % len(BEAT_COLORS)]
        bx = tx(b["t"])
        passed = b["t"] <= t + 1e-6
        d.polygon([(bx - 4, ay - 10), (bx + 4, ay - 10), (bx, ay - 3)], fill=col if passed else (70, 76, 92))
    cx = tx(min(max(t, t0), t1))
    d.line([(cx, ay - 9), (cx, ay + 9)], fill=(255, 255, 255), width=2)
    new = [b["name"] for b in beats if (prev_t is None and b["t"] <= t + 1e-6) or (prev_t is not None and prev_t < b["t"] <= t + 1e-6)]
    info = []
    if fill is not None:
        info.append(f"fill {fill:.1f}x")
    for k, v in (cover or {}).items():
        if v >= 0.05:
            info.append(f"{k} {int(round(v * 100))}% hidden")
    left = ("» " + ", ".join(new)) if new else ""
    d.text((x + 6, y + RULER_H - 11), left[:60], font=small, fill=(255, 226, 120), anchor="lm")
    right = " · ".join(info)
    d.text((x + w - 6, y + RULER_H - 11), right, font=small, fill=(200, 210, 230), anchor="rm")


def legend_text(beats):
    return "   ".join(f"{i + 1}·{b['name']} {b['t']:.2f}" for i, b in enumerate(beats))


def grid_sheet(title, subtitle, cells, cell_w, ruler=None, max_w=2300):
    """cells = [(t, image, extra)], extra = {fill, cover}; ruler = (t0, t1, beats) or None."""
    if not cells:
        return None
    iw, ih = cells[0][1].size
    f = cell_w / iw
    cw, ch = int(round(iw * f)), int(round(ih * f))
    pad = 10
    title_h = 52 if not subtitle else 74
    rh = RULER_H if ruler else 0
    n = len(cells)
    cols = max(1, min(n, (max_w - pad) // (cw + pad)))
    if n > cols and cols >= 4 and n / cols < 2:  # avoid a lonely last row
        cols = math.ceil(n / 2)
    rows = math.ceil(n / cols)
    W = pad + cols * (cw + pad)
    H = title_h + pad + rows * (ch + rh + pad)
    out = Image.new("RGB", (W, H), INK)
    d = ImageDraw.Draw(out)
    d.text((pad, 26), title, font=_font(19), fill=(240, 242, 248), anchor="lm")
    if subtitle:
        d.text((pad, 54), subtitle, font=_font(14), fill=(255, 226, 120), anchor="lm")
    tag_font = _font(15)
    prev = None
    for i, (t, im, extra) in enumerate(cells):
        cx = pad + (i % cols) * (cw + pad)
        cy = title_h + pad + (i // cols) * (ch + rh + pad)
        out.paste(im.resize((cw, ch), Image.LANCZOS), (cx, cy))
        label = f"{t:.2f} s"
        if extra.get("fill") is not None and not ruler:
            label += f" · fill {extra['fill']:.1f}x"
        tw = tag_font.getlength(label)
        d.rounded_rectangle([cx + 4, cy + 4, cx + 14 + tw, cy + 26], radius=6, fill=(20, 24, 38))
        d.text((cx + 9, cy + 15), label, font=tag_font, fill=(255, 255, 255), anchor="lm")
        if ruler:
            draw_ruler(d, cx, cy + ch, cw, t, ruler[0], ruler[1], ruler[2], extra.get("fill"), extra.get("cover"),
                       prev)
        prev = t
    return out


MOTION_THRESHOLD = 28  # colour difference (0..255, any channel) that counts as "moved"


def motion_map(cells, title):
    """The first cell with every pixel that changed in any later cell painted red (the world
    view of a still camera: swaying flags, the turning windmill, a jumping fish, gulls…), with
    the share of the frame that moved."""
    base_im = cells[0][1].convert("RGB")
    base = np.asarray(base_im, np.int16)
    mask = np.zeros(base.shape[:2], bool)
    for _, im, _ in cells[1:]:
        mask |= np.abs(np.asarray(im.convert("RGB"), np.int16) - base).max(2) > MOTION_THRESHOLD
    m = Image.fromarray((mask * 255).astype(np.uint8), "L").filter(ImageFilter.MaxFilter(3))
    a = np.asarray(m, np.float32)[..., None] / 255.0 * 0.62
    out = (base * (1 - a) + np.array([255, 40, 60], np.float32) * a).clip(0, 255).astype(np.uint8)
    im = Image.fromarray(out, "RGB")
    head = 34
    sheet = Image.new("RGB", (im.width, im.height + head), INK)
    sheet.paste(im, (0, head))
    d = ImageDraw.Draw(sheet)
    d.text((10, head / 2), f"{title} · {mask.mean() * 100:.1f}% of the frame moved", font=_font(15),
           fill=(240, 242, 248), anchor="lm")
    return sheet


def cell_width(region, kind):
    rw, rh = region[2] - region[0], region[3] - region[1]
    if kind == "timeline":
        return 430
    # sheets: about 560 px wide; small regions are enlarged (up to 2x) so details stay readable
    f = min(max(560 / rw, 0.3), 2.0)
    if rh * f > 420:
        f = max(420 / rh, 0.3)
    return int(round(rw * f))


# ---------------------------------------------------------------------------------------
# One dump: jobs (rendered in a pool) and the assembly of its images
# ---------------------------------------------------------------------------------------

_dumps = {}


def load_dump(path):
    if path not in _dumps:
        with open(path, "r", encoding="utf-8") as fh:
            _dumps[path] = json.load(fh)
    return _dumps[path]


def _render_job(args):
    key, path, index, region, xray, opts = args
    dump = load_dump(path)
    im, cover = render_frame(dump, dump["frames"][index], opts, region, xray)
    return key, im, cover


def _render_indexed(args):
    k, job = args
    return k, _render_job(job)


def plan_dump(path, opts, report):
    """Render jobs of one dump: [(key, path, frame index, region, xray, opts)] and the layout of
    its outputs (what goes where). A check-only device renders only its first still with layout
    findings (drawn as _layout.png)."""
    dump = load_dump(path)
    frames = dump["frames"]
    jobs, layout = [], {"stills": [], "sheets": {}, "check": None}
    render_stills = dump["device"] in opts.render_devices
    if not render_stills:
        for i in sorted(report["frames"]):
            if report["frames"][i].get("layout") or report["frames"][i].get("text"):
                jobs.append((("check", i), path, i, None, False, opts))
                layout["check"] = i
                break
        return jobs, layout
    for i, f in enumerate(frames):
        if f.get("still") and render_stills:
            jobs.append((("still", i), path, i, None, False, opts))
            layout["stills"].append(i)
    W, H = dump["viewport"]
    for kind in ("sheet", "burst", "timeline"):
        idx = [i for i, f in enumerate(frames) if f.get(kind)]
        if not idx or not render_stills:
            continue
        spec = dump.get(kind) or {}
        if kind == "timeline" and not as_list(spec.get("roi")):
            region = None  # timelines are full screen unless they name a region
        else:
            region = roi_region(dump, [frames[i] for i in idx], spec)
        full = region is None or (region[0] <= 0 and region[1] <= 0 and region[2] >= W and region[3] >= H)
        xray = (kind == "timeline" or (kind == "burst" and bool(dump.get("timeline")))) and dump.get("xray", True)
        for i in idx:
            jobs.append(((kind, i), path, i, None if full else region, xray and full, opts))
        layout["sheets"][kind] = {"frames": idx, "region": region or (0, 0, W, H)}
    # world_view: the timeline's frames once more without the HUD and the chrome — the avatar and
    # the world behind the widgets
    wv = dump.get("world_view")
    idx = [i for i, f in enumerate(frames) if f.get("timeline")] or [i for i, f in enumerate(frames) if f.get("still")]
    if wv and idx and render_stills:
        region = roi_region(dump, [frames[i] for i in idx], wv if isinstance(wv, dict) else {})
        full = region[0] <= 0 and region[1] <= 0 and region[2] >= W and region[3] >= H
        bare = copy.copy(opts)
        bare.hud, bare.chrome = False, False
        for i in idx:
            jobs.append((("worldview", i), path, i, None if full else region, False, bare))
        layout["sheets"]["worldview"] = {"frames": idx, "region": region}
    return jobs, layout


def assemble_dump(path, layout, images, opts, report):
    """Writes the stills, sheets, overlays of one dump; returns [(kind, device, scenario, file)]."""
    dump = load_dump(path)
    W, H = dump["viewport"]
    dev, name = dump["device"], dump["scenario"]
    out_dir = os.path.join(opts.out, dev)
    os.makedirs(out_dir, exist_ok=True)
    results = []
    frames = dump["frames"]
    stills = layout["stills"]
    if layout.get("check") is not None:
        i = layout["check"]
        chk = report["frames"][i]
        im, _ = images[("check", i)]
        ov = with_caption(draw_findings(im, chk), checks_caption(dev, W, H, name, chk["t"]))
        path_out = os.path.join(out_dir, f"{name}_layout.png")
        ov.save(path_out)
        results.append(("layout", dev, name, path_out))
    for i in stills:
        f = frames[i]
        im, _ = images[("still", i)]
        chk = report["frames"].get(i, {})
        if chk.get("layout") or chk.get("text"):
            ov = draw_findings(im, chk)
            ov_name = f"{name}_layout.png" if len(stills) == 1 else f"{name}@{f['t']:.2f}_layout.png"
            ov = with_caption(ov, checks_caption(dev, W, H, name, f["t"]))
            ov.save(os.path.join(out_dir, ov_name))
            results.append(("layout", dev, name, os.path.join(out_dir, ov_name)))
        if opts.caption:
            fill = chk.get("fill")
            extra = f" · fill {fill:.1f}x" if fill is not None else ""
            im = with_caption(im, f"{dev} {W}×{H}  ·  {name}  ·  t = {f['t']:.2f} s{extra}  ·  {dump.get('desc', '')}")
        sname = still_name(dump, f, len(stills))
        im.save(os.path.join(out_dir, sname))
        results.append(("still", dev, name, os.path.join(out_dir, sname)))
    beats = beat_list(dump)
    for kind, info in layout["sheets"].items():
        timed = kind in ("timeline", "worldview")
        spec = dump.get("timeline" if kind == "worldview" else kind) or {}
        region = info["region"]
        cells = []
        idx = info["frames"]
        if timed and beats:
            # nothing happens after the last beat: keep its `tail` (TIMELINE_TAIL s) of it
            end = max(b["t"] for b in beats) + float(spec.get("tail") or TIMELINE_TAIL)
            idx = [i for i in idx if frames[i]["t"] <= end] or idx[:1]
        for i in idx:
            im, cover = images[(kind, i)]
            cells.append((frames[i]["t"], im, {"fill": report["frames"].get(i, {}).get("fill"), "cover": cover}))
        rw, rh = region[2] - region[0], region[3] - region[1]
        what = {"sheet": "animation", "burst": "burst", "timeline": "timeline",
                "worldview": "the world without the HUD"}[kind]
        title = (f"{name} — {what} — {dump.get('desc', '')}   ·   {dev} {W}×{H}   ·   "
                 f"{spec.get('from', 0):g}..{spec.get('to', 0):g} s @ {spec.get('fps', 0):g} fps")
        if region != (0, 0, W, H):
            title += f"   ·   region {int(region[0])},{int(region[1])} {int(rw)}×{int(rh)} px"
        ruler = None
        subtitle = None
        if beats and kind in ("burst", "timeline", "worldview"):
            ruler = (float(spec.get("from", 0)), float(spec.get("to", 1)), beats)
            subtitle = "beats: " + legend_text(beats)
        full = region == (0, 0, W, H) or (region[0] <= 0 and region[1] <= 0 and region[2] >= W and region[3] >= H)
        width = cell_width(region, "timeline") if timed and full else cell_width(region, "sheet" if timed else kind)
        own = dump.get("world_view") if kind == "worldview" else spec
        if isinstance(own, dict) and own.get("cell"):
            width = int(own["cell"])
        sheet = grid_sheet(title, subtitle, cells, width, ruler)
        sname = f"{name}_world.png" if kind == "worldview" else f"{name}_{kind}.png"
        sheet.save(os.path.join(out_dir, sname))
        results.append((kind, dev, name, os.path.join(out_dir, sname)))
        if kind == "worldview" and len(cells) > 1:
            cams = {B.camera_key(frame_camera(dump, frames[i])) for i in idx}
            if len(cams) == 1:  # a still camera: what moved over the clip, in one image
                mname = f"{name}_motion.png"
                motion_map(cells, f"{name} — what moved in {cells[0][0]:.2f}..{cells[-1][0]:.2f} s (red), "
                                  f"the world without the HUD · {dev} {W}×{H}").save(os.path.join(out_dir, mname))
                results.append(("motion", dev, name, os.path.join(out_dir, mname)))
        if opts.gif and kind in ("burst", "timeline", "worldview"):
            fps = float(spec.get("fps", 10))
            gif = [c[1].convert("P", palette=Image.ADAPTIVE) for c in cells]
            gname = sname[:-4] + ".gif"
            gif[0].save(os.path.join(out_dir, gname), save_all=True, append_images=gif[1:],
                        duration=int(round(1000 / fps)), loop=0)
            results.append((kind + "_gif", dev, name, os.path.join(out_dir, gname)))
    return results


def dump_report(path, opts):
    """Checks of every frame of a dump (fill on all; layout and text floor on the stills)."""
    dump = load_dump(path)
    rep = {"device": dump["device"], "scenario": dump["scenario"], "viewport": dump["viewport"], "frames": {},
           "beats": beat_list(dump), "errors": as_list(dump.get("errors"))}
    for i, f in enumerate(dump["frames"]):
        rep["frames"][i] = frame_checks(dump, f, layout=bool(f.get("still")))
    for e in rep["errors"]:
        log(f"{dump['scenario']}/{dump['device']}: script error: {e}")
    auto = sorted({o["path"] for f in dump["frames"] for o in f["objects"] if o.get("auto")})
    if auto:
        log(f"{dump['scenario']}/{dump['device']}: AutomaticSize is not applied (drawn at Size): {', '.join(auto[:5])}")
    return rep


def overview(device, items, opts):
    """All stills of a device in one image (thumbnails with names)."""
    if not items:
        return None
    thumbs = []
    for scenario, path in items:
        im = Image.open(path).convert("RGB")
        if opts.caption:
            im = im.crop((0, 0, im.width, im.height - CAPTION_H))
        thumbs.append((scenario, im))
    tw = 420
    th = int(round(thumbs[0][1].height * tw / thumbs[0][1].width))
    cols = 5 if len(thumbs) > 12 else 4
    rows = math.ceil(len(thumbs) / cols)
    pad, label_h, title_h = 10, 24, 46
    out = Image.new("RGB", (pad + cols * (tw + pad), title_h + rows * (th + label_h + pad) + pad), INK)
    d = ImageDraw.Draw(out)
    W, H = VIEWPORTS.get(device, (0, 0))
    d.text((pad, title_h / 2), f"HUD stills — {device} {W}×{H}  ({len(thumbs)} states)", font=_font(20),
           fill=(240, 242, 248), anchor="lm")
    f = _font(15)
    for i, (scenario, im) in enumerate(thumbs):
        x = pad + (i % cols) * (tw + pad)
        y = title_h + (i // cols) * (th + label_h + pad)
        out.paste(im.resize((tw, th), Image.LANCZOS), (x, y))
        d.text((x + 2, y + th + label_h / 2 + 1), scenario, font=f, fill=(225, 230, 240), anchor="lm")
    path = os.path.join(opts.out, f"overview_{device}.png")
    out.save(path)
    return path


# ---------------------------------------------------------------------------------------
# The checks report
# ---------------------------------------------------------------------------------------


def write_report(reports, opts):
    """checks.txt (for people) and checks.json (for tools); prints the summary."""
    lines = []
    warn_fill = []
    by_dev = {}
    for rep in reports:
        by_dev.setdefault(rep["device"], []).append(rep)
    js = []
    for dev in sorted(by_dev, key=lambda d: list(VIEWPORTS).index(d) if d in VIEWPORTS else 99):
        reps = sorted(by_dev[dev], key=lambda r: r["scenario"])
        W, H = reps[0]["viewport"]
        budget = C.fill_budget_applies(W, H)
        lines.append(f"== {dev} {W}x{H} ==")
        for rep in reps:
            frames = rep["frames"]
            if not frames:
                continue
            peak_i = max(frames, key=lambda i: frames[i]["fill"])
            peak = frames[peak_i]
            fills = sorted(frames[i]["fill"] for i in frames)
            median = fills[len(fills) // 2]
            stills = [frames[i] for i in sorted(frames) if "layout" in frames[i]]
            flag = ""
            if budget and peak["fill"] > C.FILL_WARN:
                flag = f"  << over the {C.FILL_WARN}x budget"
                warn_fill.append((rep["scenario"], dev, peak["fill"], peak["t"]))
            top = ", ".join(f"{k} {v:.1f}" for k, v in sorted(peak["fill_by"].items(), key=lambda kv: -kv[1])[:3])
            lines.append(f"{rep['scenario']}: fill peak {peak['fill']:.2f}x at {peak['t']:.2f} s ({top}), "
                         f"median {median:.2f}x over {len(fills)} frame(s){flag}")
            for st in stills:
                for fd in st["layout"]:
                    lines.append(f"    t={st['t']:.2f} layout: {C.format_finding(fd)}")
                for tf in st["text"]:
                    lines.append(f"    t={st['t']:.2f} text {tf['px']:g} px < {C.TEXT_FLOOR}: {tf['path']} «{tf['text']}»")
            if rep["beats"]:
                lines.append("    beats: " + legend_text(rep["beats"]))
            js.append({
                "device": dev,
                "scenario": rep["scenario"],
                "fill": [{"t": frames[i]["t"], "fill": frames[i]["fill"]} for i in sorted(frames)],
                "fill_peak": peak["fill"],
                "fill_median": median,
                "layout": [{"t": st["t"], "findings": [{k: fd[k] for k in ("a", "b", "gap", "kind")} for fd in st["layout"]],
                            "text": [{k: tf[k] for k in ("path", "px", "text")} for tf in st["text"]]} for st in stills],
                "beats": rep["beats"],
            })
        lines.append("")
    with open(os.path.join(opts.out, "checks.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines))
    with open(os.path.join(opts.out, "checks.json"), "w", encoding="utf-8") as fh:
        json.dump(js, fh, ensure_ascii=False, indent=1)
    n_layout = sum(len(st["findings"]) for r in js for st in r["layout"])
    n_text = sum(len(st["text"]) for r in js for st in r["layout"])
    for scenario, dev, fill, t in sorted(warn_fill, key=lambda w: -w[2]):
        log(f"WARNING fill {fill:.1f}x > {C.FILL_WARN}x on {dev}: {scenario} at {t:.2f} s")
    log(f"checks: {n_layout} layout finding(s) under {C.MIN_GAP} px, {n_text} text(s) under {C.TEXT_FLOOR} px, "
        f"{len(warn_fill)} fill warning(s) -> {os.path.join(opts.out, 'checks.txt')}")


# ---------------------------------------------------------------------------------------
# Dumping (Lune) in parallel
# ---------------------------------------------------------------------------------------


def list_scenarios():
    res = subprocess.run([lune_bin(), "run", "tools/preview/gui_dump.luau", "--list"], cwd=REPO,
                         capture_output=True, text=True, check=True)
    names, standard, timelines = [], [], []
    for line in res.stdout.splitlines():
        if not line.strip():
            continue
        name = line.split()[0]
        names.append(name)
        if "(not standard)" not in line:
            standard.append(name)
        if " timeline " in line:
            timelines.append(name)
    return names, standard, timelines, res.stdout


def run_dumps(work, opts):
    """work = [(device, [scenarios], sheets: bool, bursts: bool)] -> dump paths."""
    json_dir = os.path.join(opts.out, "json")
    os.makedirs(json_dir, exist_ok=True)
    jobs = []
    total = sum(len(w[1]) for w in work)
    for dev, scenarios, sheets, bursts in work:
        share = max(1, round(opts.jobs * len(scenarios) / max(total, 1)))
        chunks = [scenarios[i::share] for i in range(share)]
        for chunk in chunks:
            if chunk:
                jobs.append((dev, chunk, sheets, bursts))
    t0 = time.time()
    running, pending, failed = [], list(jobs), False
    while pending or running:
        while pending and len(running) < opts.jobs:
            dev, chunk, sheets, bursts = pending.pop(0)
            cmd = [lune_bin(), "run", "tools/preview/gui_dump.luau", "--device", dev, "--scenario", ",".join(chunk),
                   "--out", json_dir, "--place", opts.place]
            if sheets:
                cmd.append("--sheets")
            if bursts:
                cmd.append("--bursts")
            if opts.at:
                cmd += ["--at", opts.at]
            if opts.times:
                cmd += ["--times", opts.times]
            running.append((dev, chunk, subprocess.Popen(cmd, cwd=REPO, stdout=subprocess.PIPE,
                                                         stderr=subprocess.STDOUT, text=True)))
        dev, chunk, p = running.pop(0)
        out, _ = p.communicate()
        for line in out.splitlines():
            if opts.verbose or "script error" in line or "never became" in line or "failed" in line \
                    or "timed out" in line or "not found" in line or "not clickable" in line or "playCatch" in line:
                print(line)
        if p.returncode != 0:
            failed = True
            log(f"gui_dump failed on {dev} ({','.join(chunk)}):\n{out[-2000:]}")
    log(f"dumped {total} scenario-device pair(s) in {time.time() - t0:.1f}s")
    if failed:
        sys.exit(1)
    return [os.path.join(json_dir, w[0], f"{s}.json") for w in work for s in w[1]]


# ---------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------


def main(argv=None):
    ap = argparse.ArgumentParser(description="Render HUD previews from RbxSim dumps (see tools/preview/README.md).")
    ap.add_argument("dumps", nargs="*", help="gui_dump.luau JSON files to render (no dumping)")
    ap.add_argument("--out", help="output directory")
    ap.add_argument("--all", action="store_true",
                    help="the standard set: every standard scenario, stills + sheets on phone and desktop, the "
                         "bursts on phone, plus the checks on phone_notch, phone_small and tablet")
    ap.add_argument("--scenario", "--scenarios", help="comma-separated scenario names (dumps them first)")
    ap.add_argument("--timeline", "--timelines", action="store_true",
                    help="the catch timelines (real server, world FX, beat rulers); default device phone")
    ap.add_argument("--devices", "--device", default=None,
                    help="comma-separated: phone,phone_notch,phone_small,tablet,desktop,console (default phone,desktop)")
    ap.add_argument("--sheets", action="store_true", help="also dump/render animation sheets (always on with --all)")
    ap.add_argument("--bursts", action="store_true",
                    help="also the 30 fps bursts of the first 0.8 s (slams, stamps, pops, catches) on every "
                         "device (--all: on the first device)")
    ap.add_argument("--no-checks-devices", dest="safety", action="store_false",
                    help="with --all: skip the extra check-only devices")
    ap.add_argument("--at", help="still times, e.g. 0.2,0.6 (instead of each scenario's own)")
    ap.add_argument("--times", help="sheet window A:B:FPS for every scenario (implies --sheets)")
    ap.add_argument("--ss", type=int, default=2, help="supersampling factor (default 2)")
    ap.add_argument("--bg", default="pier", help="pier (default) | plain | an image path")
    ap.add_argument("--no-chrome", dest="chrome", action="store_false", help="no Roblox CoreGui overlay")
    ap.add_argument("--no-world", dest="world", action="store_false", help="world dumps: no world FX under the HUD")
    ap.add_argument("--no-hud", dest="hud", action="store_false", help="only the backdrop, the world FX and the chrome")
    ap.add_argument("--no-caption", dest="caption", action="store_false", help="no caption bar under stills")
    ap.add_argument("--no-overview", dest="overview", action="store_false")
    ap.add_argument("--gif", action="store_true", help="also animated GIFs of the bursts and timelines")
    ap.add_argument("--place", default=os.path.join(REPO, "Place1.rbxl"))
    ap.add_argument("--jobs", type=int, default=max(1, min(8, os.cpu_count() or 2)))
    ap.add_argument("--list", action="store_true", help="list the scenarios")
    ap.add_argument("--selftest", action="store_true", help="check the renderer's geometry and checks, then exit")
    ap.add_argument("-v", "--verbose", action="store_true")
    opts = ap.parse_args(argv)
    if opts.times:
        opts.sheets = True

    if opts.selftest:
        C.selftest()
        WD.selftest()
        S.selftest()
        log("selftest ok (gui/checks.py, gui/world.py, gui/solids.py)")
        return
    if opts.list:
        print(list_scenarios()[3], end="")
        return
    if not opts.out:
        ap.error("--out is required")
    opts.out = os.path.abspath(opts.out)
    os.makedirs(opts.out, exist_ok=True)
    t0 = time.time()

    default_devices = TIMELINE_DEVICES if opts.timeline and not (opts.all or opts.scenario) else STANDARD_DEVICES
    devices = [d for d in (opts.devices or ",".join(default_devices)).split(",") if d]
    for d in devices:
        if d not in VIEWPORTS:
            ap.error(f"unknown device {d} ({', '.join(VIEWPORTS)})")
    opts.render_devices = set(devices)
    if opts.all or opts.scenario or opts.timeline:
        if not os.path.isfile(opts.place):
            sys.exit(f"{opts.place} not found — build it first: /opt/tools/l11/lune run tools/build.luau")
        names, standard, timelines, _ = list_scenarios()
        scenarios = []
        if opts.all:
            opts.sheets = True
            scenarios += standard
        if opts.scenario:
            wanted = [s for s in opts.scenario.split(",") if s]
            unknown = [s for s in wanted if s not in names]
            if unknown:
                sys.exit(f"unknown scenario(s): {', '.join(unknown)} (see --list)")
            scenarios += [s for s in wanted if s not in scenarios]
        # --all: bursts on the first device (phones first), unless --bursts asks for every device
        work = [(dev, list(scenarios), opts.sheets, opts.bursts or (opts.all and k == 0))
                for k, dev in enumerate(devices) if scenarios]
        if opts.timeline:
            for dev in devices:
                work.append((dev, [s for s in timelines if s not in scenarios], True, True))
        if opts.all and opts.safety:
            work += [(dev, list(standard), False, False) for dev in SAFETY_DEVICES if dev not in devices]
        work = [w for w in work if w[1]]
        dumps = run_dumps(work, opts)
    else:
        dumps = opts.dumps
        if not dumps:
            ap.error("give dump files, --scenario, --timeline or --all")
        opts.render_devices = {load_dump(p)["device"] for p in dumps}

    # Backdrops once (cached on disk), before forking the workers.
    cams = set()
    for path in dumps:
        dump = load_dump(path)
        W, H = dump["viewport"]
        if dump["device"] not in opts.render_devices:
            continue
        for f in dump["frames"]:
            cam = frame_camera(dump, f)
            avatar, exclude = backdrop_variant(dump, f)
            key = (W, H, B.camera_key(cam), avatar, B.exclude_key(exclude))
            if key not in cams:
                cams.add(key)
                get_backdrop(W, H, opts, cam, avatar, exclude)
            if f.get("world") and (f["world"].get("solids") or f["world"].get("movers")):
                world_context(opts)

    t1 = time.time()
    reports = [dump_report(p, opts) for p in dumps]
    plans = [plan_dump(p, opts, rep) for p, rep in zip(dumps, reports)]
    jobs = [j for js, _ in plans for j in js]
    # Frames come back in any order; a dump's images are assembled (and freed) as soon as all
    # of them are in. Full-screen frames first, so the pool ends evenly.
    order = sorted(range(len(jobs)), key=lambda k: (jobs[k][3] is not None, jobs[k][0][0] == "still"))
    left = {}
    for js, _ in plans:
        for j in js:
            left[j[1]] = left.get(j[1], 0) + 1
    by_path = {p: (layout, rep) for (_, layout), p, rep in zip(plans, dumps, reports)}
    images, flat = {}, []

    def collect(result, path):
        key, im, cover = result
        images.setdefault(path, {})[key] = (im, cover)
        left[path] -= 1
        if left[path] == 0:
            layout, rep = by_path[path]
            flat.extend(assemble_dump(path, layout, images.pop(path), opts, rep))

    if opts.jobs > 1 and len(jobs) > 1:
        with multiprocessing.get_context("fork").Pool(opts.jobs) as pool:
            for k, result in pool.imap_unordered(_render_indexed, [(k, jobs[k]) for k in order], chunksize=1):
                collect(result, jobs[k][1])
    else:
        for k in order:
            collect(_render_job(jobs[k]), jobs[k][1])
    for path in dumps:  # dumps without any image (e.g. a check-only device with no findings)
        if path not in left:
            layout, rep = by_path[path]
            flat.extend(assemble_dump(path, layout, {}, opts, rep))
    counts = {}
    for r in flat:
        counts[r[0]] = counts.get(r[0], 0) + 1
    log("rendered " + ", ".join(f"{v} {k}(s)" for k, v in sorted(counts.items())) + f" in {time.time() - t1:.1f}s")
    if opts.overview and (opts.all or len(dumps) > 3):
        for dev in sorted(opts.render_devices):
            rank = {load_dump(p)["scenario"]: k for k, p in enumerate(dumps)}  # the scenario list order
            items = sorted(((r[2], r[3]) for r in flat if r[0] == "still" and r[1] == dev),
                           key=lambda it: (rank.get(it[0], 1e9), it[1]))
            p = overview(dev, items, opts)
            if p:
                log(f"overview -> {p}")
    write_report(reports, opts)
    log(f"done in {time.time() - t0:.1f}s -> {opts.out}")
    # A script error means the previews show a broken game: say so loudly and fail.
    broken = [f"{r['scenario']}/{r['device']}" for r in reports if r["errors"]]
    if broken:
        log(f"SCRIPT ERRORS in {len(broken)} dump(s): {', '.join(broken[:8])}"
            + (" …" if len(broken) > 8 else "") + " — these previews are not the real game")
        sys.exit(2)


if __name__ == "__main__":
    main()
