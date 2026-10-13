"""Backdrops and Roblox CoreGui chrome for the GUI preview renderer.

Backdrop ("pier", the default): a player-eye frame of the real map rendered by
tools/preview/render.py at the device resolution — the third-person camera 12.5 studs behind
a blocky stand-in avatar (classic R6 colours, bamboo rod in hand) standing on base 1's
FishingSpot and looking over the lagoon (vertical FOV 70, like the Roblox default camera).
Parts and terrain come from export_parts.luau / export_terrain.luau of the place; the
result is cached in tools/preview/gui/.cache/ (keyed by the place file and the resolution).
If that fails, docs/preview_pier.png is cropped instead. "plain" is a flat sky/sea gradient,
anything else is an image path (cover-fitted).

Chrome (drawn over the HUD, semi-transparent, like CoreGui above PlayerGui):
  * top bar (58 px): the Roblox menu button and the chat/"more" pill at the top-left; on
    desktop also the open chat window (top-left) and the player list (top-right);
  * the hotbar: 60 px slots centred, 5..65 px above the bottom, one per tool (number + name,
    a white frame on the equipped one);
  * touch devices: the classic thumbstick (bottom-left) and the Jump button: screens whose
    short side is <= 500 px: 70 px at 25..95 px from the right and 20..90 px from the bottom
    (thumbstick mirrored at 25..95 px from the left); bigger: 120 px at (W-170..W-50,
    H-210..H-90) (thumbstick at 60..180 px from the left).
"""

import hashlib
import json
import math
import os
import subprocess
import sys
import time

import numpy as np
from PIL import Image, ImageDraw

from . import text as T

HERE = os.path.dirname(os.path.abspath(__file__))
PREVIEW = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(PREVIEW))
CACHE = os.environ.get("GUI_PREVIEW_CACHE", os.path.join(HERE, ".cache"))
VERSION = 3  # bump when the camera/avatar changes
INSET = 58

# Camera: Roblox default third-person, focus on the head.
CAM_DISTANCE = 12.5
CAM_PITCH = 18.0  # degrees down
CAM_FOV = 70.0


def _log(msg):
    print(f"[gui_render] {msg}", flush=True)


# ---------------------------------------------------------------------------------------
# Stand-in avatar
# ---------------------------------------------------------------------------------------


def _norm(v):
    v = np.asarray(v, float)
    return v / np.linalg.norm(v)


def _part(name, pos, x_axis, y_axis, size, color, material="SmoothPlastic"):
    x_axis, y_axis = _norm(x_axis), _norm(y_axis)
    z_axis = np.cross(x_axis, y_axis)
    R = np.column_stack([x_axis, y_axis, z_axis])
    return {
        "name": name,
        "path": f"PreviewAvatar.{name}",
        "className": "Part",
        "shape": "Block",
        "cf": [float(pos[0]), float(pos[1]), float(pos[2])] + [float(v) for v in R.reshape(-1)],
        "size": [float(s) for s in size],
        "color": list(color),
        "transparency": 0,
        "material": material,
        "kind": "part",
    }


def avatar_parts(ground, fwd):
    """R6-style figure standing at `ground` (feet) facing `fwd`, rod in the right hand."""
    up = np.array([0.0, 1.0, 0.0])
    f = _norm([fwd[0], 0.0, fwd[2]])
    r = np.cross(f, up)  # character's right
    g = np.asarray(ground, float)
    yellow, blue, green, hair = (245, 205, 48), (13, 105, 172), (164, 189, 71), (92, 58, 33)
    parts = [
        _part("LeftLeg", g - r * 0.5 + up * 1.0, r, up, (1, 2, 1), green),
        _part("RightLeg", g + r * 0.5 + up * 1.0, r, up, (1, 2, 1), green),
        _part("Torso", g + up * 3.0, r, up, (2, 2, 1), blue),
        _part("LeftArm", g - r * 1.5 + up * 3.0, r, up, (1, 2, 1), yellow),
        _part("Head", g + up * 4.62, r, up, (1.25, 1.25, 1.25), yellow),
        _part("Hair", g + up * 5.2 - f * 0.08, r, up, (1.35, 0.3, 1.4), hair),
    ]
    # Right arm raised forward, holding the rod.
    a = math.radians(70)
    shoulder = g + r * 1.5 + up * 4.0
    arm_dir = -up * math.cos(a) + f * math.sin(a)
    parts.append(_part("RightArm", shoulder + arm_dir * 1.0, r, arm_dir, (1, 2, 1), yellow))
    hand = shoulder + arm_dir * 2.0
    rod_dir = _norm(f * math.cos(math.radians(38)) + up * math.sin(math.radians(38)))
    side = np.cross(rod_dir, r)
    parts.append(_part("Rod", hand + rod_dir * 3.6, r, rod_dir, (0.18, 8.0, 0.18), (196, 160, 82), "Wood"))
    parts.append(_part("Reel", hand + rod_dir * 0.6 - side * 0.2, r, rod_dir, (0.32, 0.32, 0.32), (60, 64, 72)))
    return parts


# ---------------------------------------------------------------------------------------
# Pier backdrop via render.py
# ---------------------------------------------------------------------------------------


def _place_key(place):
    st = os.stat(place)
    return hashlib.sha1(f"{os.path.abspath(place)}|{st.st_size}|{st.st_mtime_ns}|{VERSION}".encode()).hexdigest()[:12]


def _lune():
    return os.environ.get("LUNE_BIN", "/opt/tools/l11/lune")


def _export(place, key):
    os.makedirs(CACHE, exist_ok=True)
    parts = os.path.join(CACHE, f"parts_{key}.json")
    grid = os.path.join(CACHE, f"smoothgrid_{key}.bin")
    if not os.path.isfile(parts):
        subprocess.run([_lune(), "run", "tools/preview/export_parts.luau", place, parts], cwd=REPO, check=True,
                       stdout=subprocess.DEVNULL)
    if not os.path.isfile(grid):
        subprocess.run([_lune(), "run", "tools/preview/export_terrain.luau", place, grid], cwd=REPO, check=True,
                       stdout=subprocess.DEVNULL)
    return parts, grid


def _spot_camera(data):
    """(feet position, forward) of base 1's fishing spot (the slot's look vector)."""
    spot = None
    for p in data["parts"]:
        if p.get("baseIndex") == 1 and p["path"].endswith("BaseTemplate.FishingSpot"):
            spot = p
            break
    slot = data["slots"][0] if data.get("slots") else None
    if spot is None or slot is None:
        raise RuntimeError("no FishingSpot of base 1 in the export")
    cf = spot["cf"]
    ground = np.array([cf[0], cf[1] + spot["size"][1] / 2, cf[2]])
    R = np.array(slot["cf"][3:]).reshape(3, 3)
    look = -R[:, 2]
    return ground, look


def render_pier(W, H, place, ss=2):
    sys.path.insert(0, PREVIEW)
    import render as R  # tools/preview/render.py
    import terrain_export

    key = _place_key(place)
    parts_path, grid_path = _export(place, key)
    with open(parts_path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    ground, look = _spot_camera(data)
    data["parts"] = data["parts"] + avatar_parts(ground, look)
    data["slots"] = []
    R.GRADE = data.get("grade")
    fog = [R.FOG_START, R.FOG_END]
    if data.get("water"):
        R.WATER_COLOR = np.array(data["water"]["color"], np.float32)
        R.WATER_OPACITY = float(min(max(1.0 - data["water"].get("transparency", 0.45) + 0.1, 0.3), 0.9))
        R.TERRAIN_COLORS["Water"] = tuple(int(c) for c in R.WATER_COLOR)
    if data.get("atmosphere"):
        fog, R.FOG_TINT = R.atmosphere_fog(data["atmosphere"])
    scene = R.Scene(data)

    class Args:
        pass

    args = Args()
    args.terrain_field = R.TerrainField(terrain_export.load_heightfield(grid_path))
    args.terrain_step = None
    args.fog = list(fog)
    focus = ground + np.array([0, 4.6, 0])
    fwd = np.array([look[0], 0, look[2]])
    fwd /= np.linalg.norm(fwd)
    p = math.radians(CAM_PITCH)
    eye = focus - fwd * CAM_DISTANCE * math.cos(p) + np.array([0, CAM_DISTANCE * math.sin(p), 0])
    cam = R.PerspCamera(eye, focus, CAM_FOV, W, H, ss)
    mesh = R._terrain_mesh_persp(args, cam)
    buf, _ = R.render_persp(R.with_terrain(scene, mesh), cam, outlines=True, fog=args.fog)
    return R.to_image(buf, ss).convert("RGB")


def _fallback(W, H):
    src = Image.open(os.path.join(REPO, "docs", "preview_pier.png")).convert("RGB")
    src = src.crop((0, 120, src.width, src.height))  # below the info box
    return cover(src, W, H)


def cover(im, W, H):
    s = max(W / im.width, H / im.height)
    tw, th = int(math.ceil(im.width * s)), int(math.ceil(im.height * s))
    im = im.resize((tw, th), Image.LANCZOS)
    x0, y0 = (tw - W) // 2, (th - H) // 2
    return im.crop((x0, y0, x0 + W, y0 + H))


def plain(W, H):
    y = np.linspace(0, 1, H, dtype=np.float32)[:, None, None]
    sky0, sky1 = np.array([118, 180, 238]), np.array([196, 228, 250])
    sea0, sea1 = np.array([70, 170, 200]), np.array([30, 110, 160])
    top = sky0 + (sky1 - sky0) * (y / 0.45)
    bot = sea0 + (sea1 - sea0) * ((y - 0.45) / 0.55)
    arr = np.where(y < 0.45, top, bot)
    arr = np.broadcast_to(arr, (H, W, 3))
    return Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGB")


def backdrop(W, H, mode="pier", place=None):
    """The background image for a W x H screen."""
    if mode == "plain":
        return plain(W, H)
    if mode not in ("pier", None):
        return cover(Image.open(mode).convert("RGB"), W, H)
    place = place or os.path.join(REPO, "Place1.rbxl")
    try:
        key = _place_key(place)
        path = os.path.join(CACHE, f"bg_{W}x{H}_{key}.png")
        if os.path.isfile(path):
            return Image.open(path).convert("RGB")
        t = time.time()
        im = render_pier(W, H, place)
        os.makedirs(CACHE, exist_ok=True)
        im.save(path)
        _log(f"pier backdrop {W}x{H} rendered in {time.time() - t:.1f}s -> {path}")
        return im
    except Exception as exc:  # no Lune, no place, renderer error...
        T.warn_once(f"pier backdrop failed ({exc}); using docs/preview_pier.png")
        return _fallback(W, H)


# ---------------------------------------------------------------------------------------
# CoreGui chrome
# ---------------------------------------------------------------------------------------


def _font(px):
    return T.text_font("Nunito", 700, px / 1.364)


def draw_chrome(canvas, W, H, ss, touch, tools, opacity=0.8):
    """Draw the CoreGui overlay on an RGBA canvas of W*ss x H*ss."""
    over = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    s = ss
    A = lambda a: int(round(255 * a * opacity))  # noqa: E731
    dark = (24, 26, 32)

    def rr(box, r, fill=None, outline=None, width=1):
        d.rounded_rectangle([v * s for v in box], radius=r * s, fill=fill, outline=outline, width=int(width * s))

    # Top bar: menu button + the chat/more pill (2024 "unibar" style).
    rr((12, 7, 56, 51), 22, fill=dark + (A(0.55),))
    cx, cy = 34, 29
    # Roblox logo: a tilted square with a hole
    pts = [(cx + 11 * math.cos(math.radians(a + 15)), cy + 11 * math.sin(math.radians(a + 15))) for a in (0, 90, 180, 270)]
    d.polygon([(x * s, y * s) for x, y in pts], fill=(255, 255, 255, A(0.9)))
    hole = [(cx + 3.2 * math.cos(math.radians(a + 15)), cy + 3.2 * math.sin(math.radians(a + 15))) for a in (0, 90, 180, 270)]
    d.polygon([(x * s, y * s) for x, y in hole], fill=dark + (A(0.9),))
    rr((64, 7, 156, 51), 22, fill=dark + (A(0.55),))
    # chat bubble
    rr((76, 17, 100, 37), 6, outline=(255, 255, 255, A(0.9)), width=2.2)
    d.polygon([(82 * s, 36 * s), (82 * s, 43 * s), (89 * s, 36 * s)], fill=(255, 255, 255, A(0.9)))
    for i in range(3):
        x = 120 + i * 9
        d.ellipse([(x - 2.2) * s, (29 - 2.2) * s, (x + 2.2) * s, (29 + 2.2) * s], fill=(255, 255, 255, A(0.9)))

    if not touch:
        # Chat window (open by default on desktop) and the player list.
        rr((8, INSET + 4, 368, INSET + 184), 8, fill=(30, 33, 40, A(0.28)), outline=(255, 255, 255, A(0.25)), width=1)
        d.text((20 * s, (INSET + 152) * s), "Чат", font=_font(15 * s), fill=(255, 255, 255, A(0.6)))
        rr((W - 178, 4, W - 8, 74), 8, fill=(30, 33, 40, A(0.5)))
        d.text(((W - 166) * s, 12 * s), "Игроки", font=_font(14 * s), fill=(255, 255, 255, A(0.75)))
        rr((W - 172, 34, W - 14, 66), 6, fill=(255, 255, 255, A(0.12)))
        d.text(((W - 162) * s, 42 * s), "Рыбак", font=_font(15 * s), fill=(255, 255, 255, A(0.9)))

    # Hotbar.
    tools = tools or [{"name": "Бамбуковая удочка", "equipped": False}]
    n = len(tools)
    slot, gap = 60, 5
    total = n * slot + (n - 1) * gap
    x0 = W / 2 - total / 2
    y0 = H - 65
    for i, tool in enumerate(tools):
        x = x0 + i * (slot + gap)
        rr((x, y0, x + slot, y0 + slot), 8, fill=(30, 33, 40, A(0.6)))
        if tool.get("equipped"):
            rr((x, y0, x + slot, y0 + slot), 8, outline=(255, 255, 255, A(0.95)), width=2.5)
        d.text(((x + 5) * s, (y0 + 3) * s), str(i + 1), font=_font(13 * s), fill=(255, 255, 255, A(0.85)))
        _wrapped(d, tool.get("name", "?"), (x + 4) * s, (y0 + 15) * s, (slot - 8) * s, (slot - 18) * s,
                 _font(11.5 * s), (255, 255, 255, A(0.95)))

    if touch:
        small = min(W, H) <= 500
        size = 70 if small else 120
        jx, jy = (W - 95, H - 90) if small else (W - 170, H - 210)
        tx, ty = (25, H - 90) if small else (60, H - 210)
        # thumbstick
        d.ellipse([tx * s, ty * s, (tx + size) * s, (ty + size) * s], fill=(20, 22, 28, A(0.35)),
                  outline=(255, 255, 255, A(0.45)), width=int(2 * s))
        k = size * 0.4
        kx, ky = tx + size / 2, ty + size / 2
        d.ellipse([(kx - k / 2) * s, (ky - k / 2) * s, (kx + k / 2) * s, (ky + k / 2) * s], fill=(255, 255, 255, A(0.45)))
        # jump
        d.ellipse([jx * s, jy * s, (jx + size) * s, (jy + size) * s], fill=(20, 22, 28, A(0.35)),
                  outline=(255, 255, 255, A(0.55)), width=int(2 * s))
        cx, cy, a = jx + size / 2, jy + size / 2, size * 0.18
        d.line([((cx - a) * s, (cy + a * 0.5) * s), (cx * s, (cy - a * 0.6) * s), ((cx + a) * s, (cy + a * 0.5) * s)],
               fill=(255, 255, 255, A(0.85)), width=int(max(2, size * 0.06) * s), joint="curve")
    canvas.alpha_composite(over)


def _wrapped(d, text, x, y, w, h, font, fill):
    words = text.split()
    lines, cur = [], ""
    for wd in words:
        trial = (cur + " " + wd).strip()
        if font.getlength(trial) <= w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = wd
    if cur:
        lines.append(cur)
    asc, desc = font.getmetrics()
    lh = asc + desc * 0.6
    ty = y + (h - lh * len(lines)) / 2
    for line in lines:
        lw = font.getlength(line)
        d.text((x + (w - lw) / 2, ty), line, font=font, fill=fill)
        ty += lh
