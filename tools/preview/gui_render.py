#!/usr/bin/env python3
"""GUI preview renderer: draws HUD dumps (tools/preview/gui_dump.luau) as a player sees them.

  # the whole standard set (phone + desktop stills, animation sheets, overviews), ~1-2 min
  python3 tools/preview/gui_render.py --all --out /tmp/ui
  # some scenarios on some devices (dumps them first)
  python3 tools/preview/gui_render.py --scenario bite,catch_mythic --devices phone --sheets --out /tmp/ui
  # existing dumps
  python3 tools/preview/gui_render.py /tmp/ui/json/phone/bite.json --out /tmp/ui
  python3 tools/preview/gui_render.py --list

Output (in --out): <device>/<scenario>.png (the still; several stills: <scenario>@<t>.png),
<device>/<scenario>_sheet.png (animation contact sheet), overview_<device>.png (all stills),
json/<device>/<scenario>.json (the dumps). Full documentation: tools/preview/README.md,
section "GUI previews".
"""

import argparse
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

from PIL import Image, ImageDraw  # noqa: E402

from gui import backdrop as B  # noqa: E402
from gui import paint as P  # noqa: E402
from gui import text as T  # noqa: E402

STANDARD_DEVICES = ("phone", "desktop")
VIEWPORTS = {"phone": (844, 390), "tablet": (1024, 768), "desktop": (1280, 720), "console": (1920, 1080)}
CAPTION_H = 30
INK = (20, 24, 38)


def log(msg):
    print(f"[gui_render] {msg}", flush=True)


def lune_bin():
    return os.environ.get("LUNE_BIN", "/opt/tools/l11/lune")


# ---------------------------------------------------------------------------------------
# Rendering one frame
# ---------------------------------------------------------------------------------------

_bg_cache = {}


def get_backdrop(W, H, mode, place):
    key = (W, H, mode, place)
    if key not in _bg_cache:
        _bg_cache[key] = B.backdrop(W, H, mode, place)
    return _bg_cache[key]


def object_box(o):
    """Axis-aligned screen box (x0, y0, x1, y1) of an object, rotation included."""
    cx, cy = o["x"] + o["w"] / 2, o["y"] + o["h"] / 2
    r = math.radians(o.get("rot", 0))
    hw = abs(o["w"] / 2 * math.cos(r)) + abs(o["h"] / 2 * math.sin(r))
    hh = abs(o["w"] / 2 * math.sin(r)) + abs(o["h"] / 2 * math.cos(r))
    return cx - hw, cy - hh, cx + hw, cy + hh


def render_frame(dump, frame, opts, region=None):
    """RGB image of one frame: backdrop, HUD, CoreGui chrome. `region` = (x0, y0, x1, y1) crop."""
    W, H = dump["viewport"]
    ss = opts.ss
    x0, y0, x1, y1 = region or (0, 0, W, H)
    x0, y0 = int(math.floor(x0)), int(math.floor(y0))
    x1, y1 = int(math.ceil(x1)), int(math.ceil(y1))
    bg = get_backdrop(W, H, opts.bg, opts.place).crop((x0, y0, x1, y1))
    canvas = bg.resize(((x1 - x0) * ss, (y1 - y0) * ss), Image.BILINEAR).convert("RGBA")
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
    painter = P.Painter(ss)
    painter.paint(objects, canvas, origin=(x0, y0))
    if opts.chrome:
        if region:
            full = Image.new("RGBA", (W * ss, H * ss), (0, 0, 0, 0))
            B.draw_chrome(full, W, H, ss, dump.get("touch"), frame.get("tools"))
            canvas.alpha_composite(full.crop((x0 * ss, y0 * ss, x1 * ss, y1 * ss)))
        else:
            B.draw_chrome(canvas, W, H, ss, dump.get("touch"), frame.get("tools"))
    out = canvas.reduce(ss) if ss > 1 else canvas
    return out.convert("RGB")


def _font(px, weight=700):
    return T.text_font("Nunito", weight, px / 1.364)


def with_caption(im, text):
    out = Image.new("RGB", (im.width, im.height + CAPTION_H), INK)
    out.paste(im, (0, 0))
    d = ImageDraw.Draw(out)
    d.text((10, im.height + CAPTION_H / 2), text, font=_font(17), fill=(235, 238, 245), anchor="lm")
    return out


# ---------------------------------------------------------------------------------------
# Stills, sheets, overview
# ---------------------------------------------------------------------------------------


def still_name(dump, frame, n_stills):
    if n_stills == 1:
        return f"{dump['scenario']}.png"
    return f"{dump['scenario']}@{frame['t']:.2f}.png"


def sheet_region(dump, frames):
    spec = dump.get("sheet") or {}
    W, H = dump["viewport"]
    roi = spec.get("roi") or []
    if not roi:
        return (0, 0, W, H)
    box = None
    for f in frames:
        for o in f["objects"]:
            if o["path"] in roi:
                b = object_box(o)
                box = b if box is None else (min(box[0], b[0]), min(box[1], b[1]), max(box[2], b[2]), max(box[3], b[3]))
    if box is None:
        return (0, 0, W, H)
    m = float(spec.get("margin", 0.04)) * H
    return (max(0, box[0] - m), max(0, box[1] - m), min(W, box[2] + m), min(H, box[3] + m))


def contact_sheet(dump, cells, region, opts):
    """Grid of (time, image) cells with a title bar."""
    rw, rh = region[2] - region[0], region[3] - region[1]
    # Cells about 560 px wide: small regions are enlarged (up to 2x) so details stay readable
    # when the sheet is viewed scaled down.
    f = min(max(560 / rw, 0.3), 2.0)
    if rh * f > 420:
        f = max(420 / rh, 0.3)
    cw, ch = int(round(rw * f)), int(round(rh * f))
    pad, title_h = 10, 50
    n = len(cells)
    cols = max(1, min(n, (2300 - pad) // (cw + pad)))
    if n > cols and cols >= 4 and n / cols < 2:  # avoid a lonely last row
        cols = math.ceil(n / 2)
    rows = math.ceil(n / cols)
    W = pad + cols * (cw + pad)
    H = title_h + pad + rows * (ch + pad)
    out = Image.new("RGB", (W, H), INK)
    d = ImageDraw.Draw(out)
    spec = dump.get("sheet") or {}
    vw, vh = dump["viewport"]
    title = (
        f"{dump['scenario']} — {dump.get('desc', '')}   ·   {dump['device']} {vw}×{vh}   ·   "
        f"{spec.get('from', 0):g}..{spec.get('to', 0):g} s @ {spec.get('fps', 0):g} fps   ·   "
        f"region {int(region[0])},{int(region[1])} {int(rw)}×{int(rh)} px"
    )
    d.text((pad, title_h / 2 + 2), title, font=_font(19), fill=(240, 242, 248), anchor="lm")
    tag_font = _font(15)
    for i, (t, im) in enumerate(cells):
        cx = pad + (i % cols) * (cw + pad)
        cy = title_h + pad + (i // cols) * (ch + pad)
        out.paste(im.resize((cw, ch), Image.LANCZOS), (cx, cy))
        label = f"{t:.2f} s"
        tw = tag_font.getlength(label)
        d.rounded_rectangle([cx + 4, cy + 4, cx + 14 + tw, cy + 26], radius=6, fill=(20, 24, 38))
        d.text((cx + 9, cy + 15), label, font=tag_font, fill=(255, 255, 255), anchor="lm")
    return out


def render_dump(path, opts):
    """Renders the stills and the sheet of one dump; returns [(kind, device, scenario, file)]."""
    with open(path, "r", encoding="utf-8") as fh:
        dump = json.load(fh)
    W, H = dump["viewport"]
    out_dir = os.path.join(opts.out, dump["device"])
    os.makedirs(out_dir, exist_ok=True)
    results = []
    stills = [f for f in dump["frames"] if f.get("still")]
    for f in stills:
        im = render_frame(dump, f, opts)
        if opts.caption:
            im = with_caption(
                im, f"{dump['device']} {W}×{H}  ·  {dump['scenario']}  ·  t = {f['t']:.2f} s  ·  {dump.get('desc', '')}"
            )
        name = still_name(dump, f, len(stills))
        im.save(os.path.join(out_dir, name))
        results.append(("still", dump["device"], dump["scenario"], os.path.join(out_dir, name)))
    sheet_frames = [f for f in dump["frames"] if f.get("sheet")]
    if sheet_frames:
        region = sheet_region(dump, sheet_frames)
        cells = [(f["t"], render_frame(dump, f, opts, region)) for f in sheet_frames]
        sheet = contact_sheet(dump, cells, region, opts)
        name = f"{dump['scenario']}_sheet.png"
        sheet.save(os.path.join(out_dir, name))
        results.append(("sheet", dump["device"], dump["scenario"], os.path.join(out_dir, name)))
    for e in dump.get("errors") or []:
        log(f"{dump['scenario']}/{dump['device']}: script error: {e}")
    auto = sorted({o["path"] for f in dump["frames"] for o in f["objects"] if o.get("auto")})
    if auto:
        log(f"{dump['scenario']}/{dump['device']}: AutomaticSize is not applied (drawn at Size): {', '.join(auto[:5])}")
    return results


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
# Dumping (Lune) in parallel
# ---------------------------------------------------------------------------------------


def list_scenarios():
    res = subprocess.run([lune_bin(), "run", "tools/preview/gui_dump.luau", "--list"], cwd=REPO,
                         capture_output=True, text=True, check=True)
    names, standard = [], []
    for line in res.stdout.splitlines():
        if not line.strip():
            continue
        name = line.split()[0]
        names.append(name)
        if "(not standard)" not in line:
            standard.append(name)
    return names, standard, res.stdout


def run_dumps(devices, scenarios, opts):
    json_dir = os.path.join(opts.out, "json")
    os.makedirs(json_dir, exist_ok=True)
    jobs = []
    per_device = max(1, opts.jobs // max(1, len(devices)))
    for dev in devices:
        chunks = [scenarios[i::per_device] for i in range(per_device)]
        for chunk in chunks:
            if chunk:
                jobs.append((dev, chunk))
    procs = []
    t0 = time.time()
    for dev, chunk in jobs:
        cmd = [lune_bin(), "run", "tools/preview/gui_dump.luau", "--device", dev, "--scenario", ",".join(chunk),
               "--out", json_dir, "--place", opts.place]
        if opts.sheets:
            cmd.append("--sheets")
        if opts.at:
            cmd += ["--at", opts.at]
        if opts.times:
            cmd += ["--times", opts.times]
        procs.append((dev, chunk, subprocess.Popen(cmd, cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                                   text=True)))
    failed = False
    for dev, chunk, p in procs:
        out, _ = p.communicate()
        for line in out.splitlines():
            if opts.verbose or "script error" in line or "never became" in line or "failed" in line \
                    or "timed out" in line or "not found" in line or "not clickable" in line or "scenario(s)" in line:
                print(line)
        if p.returncode != 0:
            failed = True
            log(f"gui_dump failed on {dev} ({','.join(chunk)}):\n{out[-2000:]}")
    log(f"dumped {len(scenarios)} scenario(s) x {len(devices)} device(s) in {time.time() - t0:.1f}s")
    if failed:
        sys.exit(1)
    return [os.path.join(json_dir, dev, f"{s}.json") for dev in devices for s in scenarios]


def _render_job(args):
    path, opts = args
    return render_dump(path, opts)


# ---------------------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------------------


def main(argv=None):
    ap = argparse.ArgumentParser(description="Render HUD previews from RbxSim dumps (see tools/preview/README.md).")
    ap.add_argument("dumps", nargs="*", help="gui_dump.luau JSON files to render (no dumping)")
    ap.add_argument("--out", help="output directory")
    ap.add_argument("--all", action="store_true", help="the standard set: every standard scenario, stills + sheets")
    ap.add_argument("--scenario", "--scenarios", help="comma-separated scenario names (dumps them first)")
    ap.add_argument("--devices", "--device", default=None, help="comma-separated: phone,tablet,desktop (default phone,desktop)")
    ap.add_argument("--sheets", action="store_true", help="also dump/render animation sheets (always on with --all)")
    ap.add_argument("--at", help="still times, e.g. 0.2,0.6 (instead of each scenario's own)")
    ap.add_argument("--times", help="sheet window A:B:FPS for every scenario (implies --sheets)")
    ap.add_argument("--ss", type=int, default=2, help="supersampling factor (default 2)")
    ap.add_argument("--bg", default="pier", help="pier (default) | plain | an image path")
    ap.add_argument("--no-chrome", dest="chrome", action="store_false", help="no Roblox CoreGui overlay")
    ap.add_argument("--no-caption", dest="caption", action="store_false", help="no caption bar under stills")
    ap.add_argument("--no-overview", dest="overview", action="store_false")
    ap.add_argument("--place", default=os.path.join(REPO, "Place1.rbxl"))
    ap.add_argument("--jobs", type=int, default=max(1, min(8, os.cpu_count() or 2)))
    ap.add_argument("--list", action="store_true", help="list the scenarios")
    ap.add_argument("-v", "--verbose", action="store_true")
    opts = ap.parse_args(argv)
    if opts.times:
        opts.sheets = True

    if opts.list:
        print(list_scenarios()[2], end="")
        return
    if not opts.out:
        ap.error("--out is required")
    opts.out = os.path.abspath(opts.out)
    os.makedirs(opts.out, exist_ok=True)
    t0 = time.time()

    devices = [d for d in (opts.devices or ",".join(STANDARD_DEVICES)).split(",") if d]
    for d in devices:
        if d not in VIEWPORTS:
            ap.error(f"unknown device {d}")
    if opts.all or opts.scenario:
        if not os.path.isfile(opts.place):
            sys.exit(f"{opts.place} not found — build it first: /opt/tools/l11/lune run tools/build.luau")
        names, standard, _ = list_scenarios()
        if opts.all:
            opts.sheets = True
            scenarios = standard
        else:
            scenarios = [s for s in opts.scenario.split(",") if s]
            unknown = [s for s in scenarios if s not in names]
            if unknown:
                sys.exit(f"unknown scenario(s): {', '.join(unknown)} (see --list)")
        dumps = run_dumps(devices, scenarios, opts)
    else:
        dumps = opts.dumps
        if not dumps:
            ap.error("give dump files, --scenario or --all")

    # Backdrops once (cached on disk), before forking the workers.
    for path in dumps:
        with open(path, "r", encoding="utf-8") as fh:
            head = json.load(fh)
        W, H = head["viewport"]
        get_backdrop(W, H, opts.bg, opts.place)

    t1 = time.time()
    if opts.jobs > 1 and len(dumps) > 1:
        with multiprocessing.get_context("fork").Pool(opts.jobs) as pool:
            results = pool.map(_render_job, [(p, opts) for p in dumps], chunksize=1)
    else:
        results = [render_dump(p, opts) for p in dumps]
    flat = [r for rs in results for r in rs]
    log(f"rendered {sum(1 for r in flat if r[0] == 'still')} still(s) and "
        f"{sum(1 for r in flat if r[0] == 'sheet')} sheet(s) in {time.time() - t1:.1f}s")
    if opts.overview and (opts.all or len(dumps) > 3):
        for dev in devices:
            items = [(r[2], r[3]) for r in flat if r[0] == "still" and r[1] == dev]
            p = overview(dev, items, opts)
            if p:
                log(f"overview -> {p}")
    log(f"done in {time.time() - t0:.1f}s -> {opts.out}")


if __name__ == "__main__":
    main()
