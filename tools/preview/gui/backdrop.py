"""Backdrops and Roblox CoreGui chrome for the GUI preview renderer.

Backdrop ("pier", the default): a player-eye frame of the real map rendered by
tools/preview/render.py at the device resolution — the third-person camera 12.5 studs behind
a blocky stand-in avatar (classic R6 colours, bamboo rod in hand) standing on base 1's
FishingSpot and looking over the lagoon (vertical FOV 70, like the Roblox default camera).
World dumps (gui/world_capture.luau) carry their camera per frame in the spot frame (right,
up, forward from the top of the FishingSpot): Humanoid.CameraOffset moves it, and the
backdrop is rendered for that camera (default_camera() is the one without an offset).
Parts and terrain come from export_parts.luau / export_terrain.luau of the place; the
image and the opaque depth buffer (for the world FX occlusion) are cached in
tools/preview/gui/.cache/ (keyed by the place file, the resolution and the camera). If that
fails, docs/preview_pier.png is cropped instead. "plain" is a flat sky/sea gradient,
anything else is an image path (cover-fitted).

Chrome (drawn over the HUD, semi-transparent, like CoreGui above PlayerGui); the shapes come
from chrome_shapes(), which the layout-safety check (gui/checks.py) uses too:
  * top bar (58 px): the Roblox menu button and the chat/"more" pill at the top-left; on
    desktop also the open chat window (top-left) and the player list (top-right);
  * the hotbar: 60 px slots centred, 5..65 px above the bottom, one per tool (number + name,
    a white frame on the equipped one);
  * touch devices: the classic thumbstick (bottom-left) and the Jump button: screens whose
    short side is <= 500 px: 70 px at 25..95 px from the right and 20..90 px from the bottom
    (thumbstick mirrored at 25..95 px from the left); bigger: 120 px at (W-170..W-50,
    H-210..H-90) (thumbstick at 60..180 px from the left);
  * a device with safe-area insets (phone_notch): all of it inside the safe area (an
    assumption to verify on a real phone), plus the rounded screen corners, the sensor
    housing on the left and the home indicator.
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


def default_camera():
    """The backdrop camera in the spot frame: {"eye", "focus": [right, up, forward] studs from
    the top of the FishingSpot, "fov"} — what gui/world_capture.luau writes into world dumps."""
    p = math.radians(CAM_PITCH)
    focus = [0.0, 4.6, 0.0]
    eye = [0.0, focus[1] + CAM_DISTANCE * math.sin(p), -CAM_DISTANCE * math.cos(p)]
    return {"eye": eye, "focus": focus, "fov": CAM_FOV}


def camera_key(cam):
    """'' for the default camera, else a short tag for the cache file name."""
    if not cam:
        return ""
    d = default_camera()
    vals = [round(float(v), 2) for v in list(cam["eye"]) + list(cam["focus"]) + [cam.get("fov", CAM_FOV)]]
    ref = [round(float(v), 2) for v in d["eye"] + d["focus"] + [d["fov"]]]
    if all(abs(a - b) < 0.02 for a, b in zip(vals, ref)):
        return ""
    return "_cam" + hashlib.sha1(repr(vals).encode()).hexdigest()[:8]


def render_pier(W, H, place, ss=2, cam=None):
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
    fwd = np.array([look[0], 0, look[2]])
    fwd /= np.linalg.norm(fwd)
    up = np.array([0.0, 1.0, 0.0])
    right = np.cross(fwd, up)
    spec = cam or default_camera()

    def world(v):
        return ground + right * v[0] + up * v[1] + fwd * v[2]

    cam = R.PerspCamera(world(spec["eye"]), world(spec["focus"]), float(spec.get("fov", CAM_FOV)), W, H, ss)
    mesh = R._terrain_mesh_persp(args, cam)
    buf, info = R.render_persp(R.with_terrain(scene, mesh), cam, outlines=True, fog=args.fog)
    # Opaque depth per output pixel (view-axis distance, inf = sky; water does not count): the
    # nearest of each ss x ss block, for the world FX occlusion (gui/world.py).
    z = -1.0 / np.asarray(info["zbuf"], np.float32)
    z[~np.isfinite(z)] = np.inf
    depth = z.reshape(H, ss, W, ss).min(axis=(1, 3)).astype(np.float32)
    return R.to_image(buf, ss).convert("RGB"), depth


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


def backdrop(W, H, mode="pier", place=None, cam=None, with_depth=False):
    """The background image for a W x H screen; `cam` = a camera in the spot frame (see
    default_camera; world dumps carry one per frame: Humanoid.CameraOffset moves it).
    with_depth=True returns (image, depth) — depth (H, W) float32 view distance of the opaque
    scene (stand-in avatar, pier, map; inf = sky) or None for non-pier backdrops."""
    if mode == "plain":
        im, depth = plain(W, H), None
    elif mode not in ("pier", None):
        im, depth = cover(Image.open(mode).convert("RGB"), W, H), None
    else:
        im, depth = _pier(W, H, place or os.path.join(REPO, "Place1.rbxl"), cam)
    return (im, depth) if with_depth else im


def _pier(W, H, place, cam):
    try:
        key = _place_key(place)
        path = os.path.join(CACHE, f"bg_{W}x{H}_{key}{camera_key(cam)}.png")
        zpath = path[:-4] + "_depth.npy"
        if os.path.isfile(path) and os.path.isfile(zpath):
            return Image.open(path).convert("RGB"), np.load(zpath)
        t = time.time()
        im, depth = render_pier(W, H, place, cam=cam if camera_key(cam) else None)
        os.makedirs(CACHE, exist_ok=True)
        im.save(path)
        np.save(zpath, depth)
        _log(f"pier backdrop {W}x{H}{camera_key(cam)} rendered in {time.time() - t:.1f}s -> {path}")
        return im, depth
    except Exception as exc:  # no Lune, no place, renderer error...
        T.warn_once(f"pier backdrop failed ({exc}); using docs/preview_pier.png")
        return _fallback(W, H), None


# ---------------------------------------------------------------------------------------
# CoreGui chrome
# ---------------------------------------------------------------------------------------


def _font(px):
    return T.text_font("Nunito", 700, px / 1.364)


HOTBAR_SLOT, HOTBAR_GAP, HOTBAR_BOTTOM = 60, 5, 5


def chrome_shapes(W, H, touch, tools, safe=(0, 0, 0)):
    """The CoreGui widgets as shapes in screen px: {name: shape}; shape = ("rrect", x0, y0, x1,
    y1, radius) or ("circle", cx, cy, r). `safe` = device insets (left, right, bottom): the
    chrome stays inside the device safe area (an assumption — verify on a notched phone).
    Used both to draw the chrome and by the layout-safety pass (gui/checks.py)."""
    sl, sr, sb = safe
    out = {
        "Menu": ("rrect", sl + 12, 7, sl + 56, 51, 22),
        "ChatPill": ("rrect", sl + 64, 7, sl + 156, 51, 22),
    }
    if not touch:
        out["ChatWindow"] = ("rrect", sl + 8, INSET + 4, sl + 368, INSET + 184, 8)
        out["PlayerList"] = ("rrect", W - sr - 178, 4, W - sr - 8, 74, 8)
    n = max(1, len(tools or []))
    total = n * HOTBAR_SLOT + (n - 1) * HOTBAR_GAP
    x0 = W / 2 - total / 2
    y1 = H - sb - HOTBAR_BOTTOM
    out["Hotbar"] = ("rrect", x0, y1 - HOTBAR_SLOT, x0 + total, y1, 8)
    if touch:
        small = min(W, H) <= 500
        size = 70 if small else 120
        jx, jy = (W - sr - 95, H - sb - 90) if small else (W - sr - 170, H - sb - 210)
        tx, ty = (sl + 25, H - sb - 90) if small else (sl + 60, H - sb - 210)
        out["Jump"] = ("circle", jx + size / 2, jy + size / 2, size / 2)
        out["Thumbstick"] = ("circle", tx + size / 2, ty + size / 2, size / 2)
    return out


def draw_chrome(canvas, W, H, ss, touch, tools, opacity=0.8, safe=(0, 0, 0)):
    """Draw the CoreGui overlay on an RGBA canvas of W*ss x H*ss (inside the safe area)."""
    over = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(over)
    s = ss
    A = lambda a: int(round(255 * a * opacity))  # noqa: E731
    dark = (24, 26, 32)
    tools = tools or [{"name": "Бамбуковая удочка", "equipped": False}]
    shapes = chrome_shapes(W, H, touch, tools, safe)
    sl = safe[0]

    def rr(box, r, fill=None, outline=None, width=1):
        d.rounded_rectangle([v * s for v in box], radius=r * s, fill=fill, outline=outline, width=int(width * s))

    # Top bar: menu button + the chat/more pill (2024 "unibar" style).
    rr(shapes["Menu"][1:5], 22, fill=dark + (A(0.55),))
    cx, cy = sl + 34, 29
    # Roblox logo: a tilted square with a hole
    pts = [(cx + 11 * math.cos(math.radians(a + 15)), cy + 11 * math.sin(math.radians(a + 15))) for a in (0, 90, 180, 270)]
    d.polygon([(x * s, y * s) for x, y in pts], fill=(255, 255, 255, A(0.9)))
    hole = [(cx + 3.2 * math.cos(math.radians(a + 15)), cy + 3.2 * math.sin(math.radians(a + 15))) for a in (0, 90, 180, 270)]
    d.polygon([(x * s, y * s) for x, y in hole], fill=dark + (A(0.9),))
    rr(shapes["ChatPill"][1:5], 22, fill=dark + (A(0.55),))
    # chat bubble
    rr((sl + 76, 17, sl + 100, 37), 6, outline=(255, 255, 255, A(0.9)), width=2.2)
    d.polygon([((sl + 82) * s, 36 * s), ((sl + 82) * s, 43 * s), ((sl + 89) * s, 36 * s)], fill=(255, 255, 255, A(0.9)))
    for i in range(3):
        x = sl + 120 + i * 9
        d.ellipse([(x - 2.2) * s, (29 - 2.2) * s, (x + 2.2) * s, (29 + 2.2) * s], fill=(255, 255, 255, A(0.9)))

    if not touch:
        # Chat window (open by default on desktop) and the player list.
        cw = shapes["ChatWindow"]
        rr(cw[1:5], 8, fill=(30, 33, 40, A(0.28)), outline=(255, 255, 255, A(0.25)), width=1)
        d.text(((cw[1] + 12) * s, (INSET + 152) * s), "Чат", font=_font(15 * s), fill=(255, 255, 255, A(0.6)))
        pl = shapes["PlayerList"]
        rr(pl[1:5], 8, fill=(30, 33, 40, A(0.5)))
        d.text(((pl[1] + 12) * s, 12 * s), "Игроки", font=_font(14 * s), fill=(255, 255, 255, A(0.75)))
        rr((pl[1] + 6, 34, pl[3] - 6, 66), 6, fill=(255, 255, 255, A(0.12)))
        d.text(((pl[1] + 16) * s, 42 * s), "Рыбак", font=_font(15 * s), fill=(255, 255, 255, A(0.9)))

    # Hotbar.
    slot, gap = HOTBAR_SLOT, HOTBAR_GAP
    x0, y0 = shapes["Hotbar"][1], shapes["Hotbar"][2]
    for i, tool in enumerate(tools):
        x = x0 + i * (slot + gap)
        rr((x, y0, x + slot, y0 + slot), 8, fill=(30, 33, 40, A(0.6)))
        if tool.get("equipped"):
            rr((x, y0, x + slot, y0 + slot), 8, outline=(255, 255, 255, A(0.95)), width=2.5)
        d.text(((x + 5) * s, (y0 + 3) * s), str(i + 1), font=_font(13 * s), fill=(255, 255, 255, A(0.85)))
        _wrapped(d, tool.get("name", "?"), (x + 4) * s, (y0 + 15) * s, (slot - 8) * s, (slot - 18) * s,
                 _font(11.5 * s), (255, 255, 255, A(0.95)))

    if touch:
        _, kx, ky, rad = shapes["Thumbstick"]
        size = rad * 2
        d.ellipse([(kx - rad) * s, (ky - rad) * s, (kx + rad) * s, (ky + rad) * s], fill=(20, 22, 28, A(0.35)),
                  outline=(255, 255, 255, A(0.45)), width=int(2 * s))
        k = size * 0.4
        d.ellipse([(kx - k / 2) * s, (ky - k / 2) * s, (kx + k / 2) * s, (ky + k / 2) * s], fill=(255, 255, 255, A(0.45)))
        _, cx, cy, rad = shapes["Jump"]
        d.ellipse([(cx - rad) * s, (cy - rad) * s, (cx + rad) * s, (cy + rad) * s], fill=(20, 22, 28, A(0.35)),
                  outline=(255, 255, 255, A(0.55)), width=int(2 * s))
        a = size * 0.18
        d.line([((cx - a) * s, (cy + a * 0.5) * s), (cx * s, (cy - a * 0.6) * s), ((cx + a) * s, (cy + a * 0.5) * s)],
               fill=(255, 255, 255, A(0.85)), width=int(max(2, size * 0.06) * s), joint="curve")
    if any(safe):
        # A notched phone: rounded screen corners, the sensor housing on the left edge and the
        # home indicator — what the safe-area insets keep the HUD away from.
        corner = Image.new("L", canvas.size, 255)
        ImageDraw.Draw(corner).rounded_rectangle([0, 0, W * s - 1, H * s - 1], radius=40 * s, fill=0)
        d.bitmap((0, 0), corner, fill=(0, 0, 0, 255))
        if safe[0] > 0:
            d.rounded_rectangle([-12 * s, (H / 2 - 105) * s, 30 * s, (H / 2 + 105) * s], radius=16 * s,
                                fill=(0, 0, 0, 255))
        if safe[2] > 0:
            d.rounded_rectangle([(W / 2 - 67) * s, (H - 9) * s, (W / 2 + 67) * s, (H - 4) * s], radius=3 * s,
                                fill=(255, 255, 255, 220))
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
