--[[
	gui_dump.luau — runs HUD scenarios in RbxSim and dumps the player's PlayerGui as JSON for
	tools/preview/gui_render.py (see tools/preview/README.md, section "GUI previews").

	Usage (Lune 0.11, from the repo root):
	  lune run tools/preview/gui_dump.luau --device phone --scenario bite,catch_mythic --out DIR
	  lune run tools/preview/gui_dump.luau --device desktop --scenario all --sheets --bursts --out DIR
	  lune run tools/preview/gui_dump.luau --device phone --scenario catch_timeline --out DIR
	  lune run tools/preview/gui_dump.luau --list

	Options:
	  --device NAME      phone (844x390) | phone_notch (844x390, safe-area insets 47/47/21) |
	                     phone_small (667x375) | tablet (1024x768) | desktop (1280x720) | console
	  --scenario LIST    comma-separated names from gui_scenarios.luau and the built-in ones
	                     (BUILTIN below: the catch timelines), or "all" (the standard set)
	  --out DIR          writes DIR/<device>/<scenario>.json
	  --place FILE       default Place1.rbxl
	  --at T[,T...]      still times (seconds after the scenario's time 0) instead of its own
	  --sheets           also dump the scenario's animation-sheet frames (if it has a sheet)
	  --bursts           also dump the 30 fps burst of the first 0.8 s (BURSTS / the `burst` field)
	  --times A:B:FPS    sheet window override (implies --sheets for every scenario)
	  --no-stills        only sheet / burst / timeline frames
	  --check            compare this script's layout with the sim's AbsolutePosition/AbsoluteSize
	  --verbose          echo script output (SIM_VERBOSE)

	Scenario fields understood here (besides gui_scenarios.luau's name, desc, run, still, sheet,
	fresh, settle, standard): burst = true | false | { from, to, fps, roi, margin } (default
	0..0.8 s @ 30 fps), timeline = { from, to, fps, tail? } (full-screen frames for
	gui_render.py's _timeline composite, always dumped; tail = seconds kept after the last beat,
	default 0.7), worldView = true | { roi, margin, cell } (also a _world composite of the timeline
	frames without the HUD: the avatar and the world behind the widgets), xray = false (no x-ray
	boxes on the timeline), server = true (a second sim with the REAL
	FishingService: use h:playCatch), world = true (record the whole 3D world with
	gui/world_capture.luau; every other scenario records the own avatar only), ambient = false
	(a world scenario without the ambient life), beats / extraBeats (see DEFAULT_BEATS), during
	= function(h) (keeps playing while the frames are dumped: taps and waits after time 0 —
	every harness step of it is a step of the frame loop). Harness additions: h:shown(path),
	h:stateEvents(), h:stateAfter(count, state), h:forceFish(fish), h:playCatch(fish, opts) =
	h:readyReal(fish) + h:castAndHook(opts) + h:playMinigame(mg, opts), h:fixBiteDelay(s),
	h:clientModule(name), h:poseLikeBackdrop(), h.world (documented where they are defined).
	Stage 3 (the stub sim also switches off DataService, EconomyService, MarketService and
	TankService — STUBBED_SERVICES — and every player joins with the stage 3 defaults: DataMode
	"Ready", Money 0, Income 0, TankSlots 6, TankCount 0, SellRatePct 100, SellPlace ""):
	h:money(n, income10?), h:tank(list, opts?) (the own base's slot / tank / player attributes,
	written like TankService), h:tankEvent(kind, data), h:caught(fish, total, tank?).
	Every player is an R15 rig (RbxSim `rig = "R15"`) on base 1 (BaseConfig.RandomAssignment is
	switched off: the backdrop is base 1's pier); while a Tool is equipped the Animator stand-in
	holds the "toolnone" pose (FisherPoses.Hold), like Roblox's Animate script.

	Layout. RbxSim's AbsolutePosition/AbsoluteSize ignore UIScale, rotation and list-layout
	alignment, so this script lays the GUI out itself, following Roblox rules: UDim2 Size and
	Position, AnchorPoint, SizeConstraint, UISizeConstraint, UIAspectRatioConstraint
	(FitWithinMaxSize / ScaleWithParentSize + DominantAxis), UIPadding, UIListLayout
	(FillDirection, Horizontal/VerticalAlignment, Padding, SortOrder), UIGridLayout (CellSize,
	CellPadding, alignment, FillDirectionMaxCells), ScrollingFrame canvas, and then:
	  • UIScale scales the object and its whole subtree visually about the object's AnchorPoint
	    (offsets, corner radii, stroke thickness and text sizes included), nested scales multiply;
	  • Rotation turns the object and its subtree about the object's (scaled) centre;
	  • ClipsDescendants (and CanvasGroup) clip descendants to the object's screen rectangle,
	    ignored when the object or an ancestor is rotated (Roblox rule).
	Screen coordinates are real screen pixels: a ScreenGui that keeps the insets (IgnoreGuiInset
	false and ScreenInsets CoreUISafeInsets) starts at y = 58 and, on phone_notch, at x = 47 and
	ends 47 px from the right and 21 px from the bottom (see DEVICES / installSafeArea).
	Draw order: ScreenGuis by DisplayOrder; ZIndexBehavior Sibling: parent first, then
	children by ZIndex, ties in child order; Global: every object by ZIndex, ties in tree order.

	JSON (one file per device and scenario, version 2):
	  { version, scenario, desc, device, viewport = {W, H}, touch, inset, safe = {left, right,
	    bottom}, sheet / burst / timeline = { from, to, fps, roi, margin, tail? } | null,
	    world_view = { roi, margin } | null, xray = bool,
	    camera = { eye, focus, fov } | null (the capture's base camera: spot frame),
	    scene = { base, waterY, movers, exclude } | null (world_capture scene()),
	    beats = { { name, t } } | null, events = { { name, kind, t } } | null,
	    frames = { { t, still, sheet, burst, timeline, tools = { {name, equipped} },
	                 hotbar (false: the game switched the Backpack CoreGui off — no hotbar drawn),
	                 objects = { <object>... },
	                 world = { cam, items, solids, movers, marks } (world scenarios)
	                       | { solids } (the own avatar) } },
	    errors = {...}, warnings = {...} }
	  object (only effectively visible GuiObjects, in draw order; px = screen pixels):
	    path, class, name, z, x, y, w, h (the box before rotation; centre = x + w/2, y + h/2),
	    rot (degrees, accumulated), k (accumulated UIScale), clip {x0, y0, x1, y1}?, alpha (CanvasGroup),
	    bg {r, g, b}, bgT, radius (px)?, radii {tl, tr, br, bl}? (only when they differ),
	    border {size, color, mode}? (legacy, only without UICorner/UIStroke),
	    strokes { {color, t (px), offset (px, BorderOffset), tr, target "border"|"text",
	               pos "Outer"|"Center"|"Inner", join, grad?} },
	    grad {c = {{t, r, g, b}...}, a = {{t, v}...}, rot, off = {x, y}, type, tile, scale}?,
	    text {s, rich, c, tr, sc, st, scaled, size, wrap, xa, ya, font, weight, style, lh, min, max,
	          pad = {l, t, r, b} (px), trunc, graphemes}?,
	    image {src, c, tr, scale}?, viewport {models = {{name, fish, mutation, title, rarity}}, c, tr}?,
	    auto (AutomaticSize if not None — not applied, flagged)
	  world items: see tools/preview/gui/world.py.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Sim = require("../sim")
local SimMembers = require("../sim/members")
local SimPlayers = require("../sim/players")
local scenarios = require("./gui_scenarios")
local WorldCapture = require("./gui/world_capture")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

local INSET = 58
local FRAME = 1 / 60

-- The stub sim switches these services off ("return {}", like the client tests): the harness
-- plays the server (FishingState / Notify / TankEvent and the replicated attributes).
local STUBBED_SERVICES = { "FishingService", "DataService", "EconomyService", "MarketService", "TankService" }
-- Stage 3 state every stub-sim player joins with (what the real services would replicate once
-- the data is loaded: RemoteNames, «Состояние садка и денег»; the numbers from the place's
-- configs); scenarios change it with h:money / h:tank / player:SetAttribute.
local function stage3Defaults(sim: any): { [string]: any }
	local tank = sim:Require(sim:Find("ReplicatedStorage.Shared.Config.TankConfig"))
	local economy = sim:Require(sim:Find("ReplicatedStorage.Shared.Config.EconomyConfig"))
	return {
		DataMode = "Ready",
		Money = economy.StartMoney,
		Income = 0,
		TankSlots = tank.StartSlots,
		TankCount = 0,
		SellRatePct = economy.HomeRatePct,
		SellPlace = "",
	}
end

--[[
	Devices: an RbxSim input profile (tools/sim/players.luau: touch / keyboard / ...) plus the
	screen. `insets` = the device safe area in px (notch, home indicator) — modelled after
	Roblox's ScreenInsets.CoreUISafeInsets: a ScreenGui that keeps the insets (the HUD) is laid
	out in x = left .. W - right, y = 58 .. H - bottom (phone_notch: 750x311 of 844x390), and
	DeviceSafeInsets in x = left .. W - right, y = 0 .. H - bottom. RbxSim itself knows no
	insets, so installSafeArea() makes the sim's AbsoluteSize/AbsolutePosition of such
	ScreenGuis and their descendants follow them too (the controllers see the same layout).
	The CoreGui chrome (gui/backdrop.py) is drawn inside the safe area as well.
]]
type Device = { sim: string, viewport: { number }?, insets: { left: number, right: number, bottom: number }? }

local DEVICES: { [string]: Device } = {
	phone = { sim = "phone" }, -- 844x390, iPhone 12-15 class in landscape, no insets
	tablet = { sim = "tablet" }, -- 1024x768
	desktop = { sim = "desktop" }, -- 1280x720
	console = { sim = "console" }, -- 1920x1080
	phone_small = { sim = "phone", viewport = { 667, 375 } }, -- iPhone SE / 8 in landscape
	phone_notch = { sim = "phone", insets = { left = 47, right = 47, bottom = 21 } }, -- notch + home bar
}
local DEVICE_ORDER = { "phone", "phone_notch", "phone_small", "tablet", "desktop", "console" }
local DEFAULT_STILL = 0.6
local SETTLE = 4.2 -- seconds after the base assignment before a scenario runs (see `settle`)

--------------------------------------------------------------------------------
-- Arguments
--------------------------------------------------------------------------------

local function parseArgs(argv: { string })
	local opts = {
		device = "phone",
		scenarios = nil :: { string }?,
		out = nil :: string?,
		place = "Place1.rbxl",
		at = nil :: { number }?,
		sheets = false,
		bursts = false,
		times = nil :: { number }?,
		stills = true,
		check = false,
		verbose = false,
		list = false,
	}
	local i = 1
	local function value(): string
		i += 1
		local v = argv[i]
		if v == nil then
			error(`missing value after {argv[i - 1]}`)
		end
		return v
	end
	while i <= #argv do
		local a = argv[i]
		if a == "--device" then
			opts.device = value()
		elseif a == "--scenario" or a == "--scenarios" then
			opts.scenarios = string.split(value(), ",")
		elseif a == "--out" then
			opts.out = value()
		elseif a == "--place" then
			opts.place = value()
		elseif a == "--at" then
			local list = {}
			for _, part in string.split(value(), ",") do
				local v = tonumber(part)
				assert(v, `bad --at value {part}`)
				table.insert(list, v)
			end
			opts.at = list
		elseif a == "--sheets" then
			opts.sheets = true
		elseif a == "--bursts" then
			opts.bursts = true
		elseif a == "--times" then
			local parts = string.split(value(), ":")
			assert(#parts == 3, "--times A:B:FPS")
			opts.times = { assert(tonumber(parts[1])), assert(tonumber(parts[2])), assert(tonumber(parts[3])) }
			opts.sheets = true
		elseif a == "--no-stills" then
			opts.stills = false
		elseif a == "--check" then
			opts.check = true
		elseif a == "--verbose" or a == "-v" then
			opts.verbose = true
		elseif a == "--list" then
			opts.list = true
		else
			error(`unknown argument {a}`)
		end
		i += 1
	end
	return opts
end

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

-- Reads a property of a raw Lune instance; unknown/missing-default properties give `default`.
local function get(inst: any, key: string, default: any?): any
	local ok, v = pcall(function()
		return inst[key]
	end)
	if ok and v ~= nil then
		return v
	end
	return default
end

local function r2(v: number): number
	if v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return math.round(v * 100) / 100
end

local function rgb(c: any): { number }
	return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) }
end

local function enumName(v: any, default: string): string
	if typeof(v) == "EnumItem" then
		return v.Name
	end
	return default
end

local function childOfClass(inst: any, className: string): any?
	for _, c in inst:GetChildren() do
		if c.ClassName == className then
			return c
		end
	end
	return nil
end

local function pathOf(inst: any, root: any): string
	local names = {}
	local cur = inst
	while cur and cur ~= root do
		table.insert(names, 1, cur.Name)
		cur = cur.Parent
	end
	return table.concat(names, ".")
end

--------------------------------------------------------------------------------
-- Similarity transforms: p' = k * R(rot) * p + t (screen y points down, rot clockwise)
--------------------------------------------------------------------------------

type Xf = { k: number, c: number, s: number, tx: number, ty: number, rot: number }

local IDENTITY: Xf = { k = 1, c = 1, s = 0, tx = 0, ty = 0, rot = 0 }

local function apply(T: Xf, x: number, y: number): (number, number)
	return T.k * (T.c * x - T.s * y) + T.tx, T.k * (T.s * x + T.c * y) + T.ty
end

local function compose(A: Xf, B: Xf): Xf
	local tx, ty = apply(A, B.tx, B.ty)
	return {
		k = A.k * B.k,
		c = A.c * B.c - A.s * B.s,
		s = A.s * B.c + A.c * B.s,
		tx = tx,
		ty = ty,
		rot = A.rot + B.rot,
	}
end

local function scaleAbout(k: number, ax: number, ay: number): Xf
	return { k = k, c = 1, s = 0, tx = ax * (1 - k), ty = ay * (1 - k), rot = 0 }
end

local function rotateAbout(deg: number, cx: number, cy: number): Xf
	local r = math.rad(deg)
	local c, s = math.cos(r), math.sin(r)
	return { k = 1, c = c, s = s, tx = cx - (c * cx - s * cy), ty = cy - (s * cx + c * cy), rot = deg }
end

local function isRotated(T: Xf): boolean
	local r = T.rot % 360
	return r > 0.01 and r < 359.99
end

--------------------------------------------------------------------------------
-- Layout (natural coordinates: before UIScale/rotation of the object and its ancestors)
--------------------------------------------------------------------------------

type Rect = { x: number, y: number, w: number, h: number }

local function sizeOf(gui: any, pw: number, ph: number): (number, number)
	local size = get(gui, "Size", roblox.UDim2.new())
	local sx = size.X.Scale * pw + size.X.Offset
	local sy = size.Y.Scale * ph + size.Y.Offset
	local sc = get(gui, "SizeConstraint", Enum.SizeConstraint.RelativeXY)
	if sc == Enum.SizeConstraint.RelativeXX then
		sy = size.Y.Scale * pw + size.Y.Offset
	elseif sc == Enum.SizeConstraint.RelativeYY then
		sx = size.X.Scale * ph + size.X.Offset
	end
	local szc = childOfClass(gui, "UISizeConstraint")
	if szc then
		local mn, mx =
			get(szc, "MinSize", roblox.Vector2.zero), get(szc, "MaxSize", roblox.Vector2.new(math.huge, math.huge))
		sx = math.clamp(sx, mn.X, math.max(mn.X, mx.X))
		sy = math.clamp(sy, mn.Y, math.max(mn.Y, mx.Y))
	end
	local arc = childOfClass(gui, "UIAspectRatioConstraint")
	local ratio = arc and get(arc, "AspectRatio", 1) or 0
	if arc and ratio > 0 then
		local aspectType = get(arc, "AspectType", Enum.AspectType.FitWithinMaxSize)
		local dominant = get(arc, "DominantAxis", Enum.DominantAxis.Width)
		if aspectType == Enum.AspectType.ScaleWithParentSize then
			if dominant == Enum.DominantAxis.Width then
				sy = sx / ratio
			else
				sx = sy * ratio
			end
		elseif sx / math.max(sy, 1e-9) > ratio then
			sx = sy * ratio
		else
			sy = sx / ratio
		end
	end
	return math.max(sx, 0), math.max(sy, 0)
end

local function contentBox(gui: any, rect: Rect): Rect
	local pad = childOfClass(gui, "UIPadding")
	if not pad then
		return rect
	end
	local l = get(pad, "PaddingLeft", roblox.UDim.new())
	local r = get(pad, "PaddingRight", roblox.UDim.new())
	local t = get(pad, "PaddingTop", roblox.UDim.new())
	local b = get(pad, "PaddingBottom", roblox.UDim.new())
	local lp = l.Scale * rect.w + l.Offset
	local rp = r.Scale * rect.w + r.Offset
	local tp = t.Scale * rect.h + t.Offset
	local bp = b.Scale * rect.h + b.Offset
	return { x = rect.x + lp, y = rect.y + tp, w = math.max(rect.w - lp - rp, 0), h = math.max(rect.h - tp - bp, 0) }
end

local function visibleGuiChildren(parent: any): { any }
	local items = {}
	for _, c in parent:GetChildren() do
		if c:IsA("GuiObject") and get(c, "Visible", true) then
			table.insert(items, c)
		end
	end
	return items
end

local function sortForLayout(items: { any }, layout: any)
	local byName = get(layout, "SortOrder", Enum.SortOrder.LayoutOrder) == Enum.SortOrder.Name
	local index = {}
	for i, c in items do
		index[c] = i
	end
	table.sort(items, function(a, b)
		if byName then
			if a.Name ~= b.Name then
				return a.Name < b.Name
			end
			return index[a] < index[b]
		end
		local la, lb = get(a, "LayoutOrder", 0), get(b, "LayoutOrder", 0)
		if la ~= lb then
			return la < lb
		end
		return index[a] < index[b]
	end)
end

local function alignOffset(free: number, align: any, startItem: any, centerItem: any): number
	if align == startItem then
		return 0
	elseif align == centerItem then
		return free / 2
	end
	return free
end

-- Natural rects of the visible GuiObject children of `parent` inside `box`.
local function layoutChildren(parent: any, box: Rect): { [any]: Rect }
	local rects: { [any]: Rect } = {}
	local items = visibleGuiChildren(parent)
	local list = childOfClass(parent, "UIListLayout")
	local grid = childOfClass(parent, "UIGridLayout")
	if list then
		sortForLayout(items, list)
		local vertical = get(list, "FillDirection", Enum.FillDirection.Vertical) == Enum.FillDirection.Vertical
		local pad = get(list, "Padding", roblox.UDim.new())
		local padPx = pad.Scale * (if vertical then box.h else box.w) + pad.Offset
		local hAlign = get(list, "HorizontalAlignment", Enum.HorizontalAlignment.Left)
		local vAlign = get(list, "VerticalAlignment", Enum.VerticalAlignment.Top)
		local sizes = {}
		local total = 0
		for i, c in items do
			local w, h = sizeOf(c, box.w, box.h)
			sizes[i] = { w, h }
			total += (if vertical then h else w) + (if i > 1 then padPx else 0)
		end
		local along
		if vertical then
			along = box.y
				+ alignOffset(box.h - total, vAlign, Enum.VerticalAlignment.Top, Enum.VerticalAlignment.Center)
		else
			along = box.x
				+ alignOffset(box.w - total, hAlign, Enum.HorizontalAlignment.Left, Enum.HorizontalAlignment.Center)
		end
		for i, c in items do
			local w, h = sizes[i][1], sizes[i][2]
			if vertical then
				local x = box.x
					+ alignOffset(box.w - w, hAlign, Enum.HorizontalAlignment.Left, Enum.HorizontalAlignment.Center)
				rects[c] = { x = x, y = along, w = w, h = h }
				along += h + padPx
			else
				local y = box.y
					+ alignOffset(box.h - h, vAlign, Enum.VerticalAlignment.Top, Enum.VerticalAlignment.Center)
				rects[c] = { x = along, y = y, w = w, h = h }
				along += w + padPx
			end
		end
	elseif grid then
		sortForLayout(items, grid)
		local cell, cpad = get(grid, "CellSize", roblox.UDim2.new()), get(grid, "CellPadding", roblox.UDim2.new())
		local cw, ch = cell.X.Scale * box.w + cell.X.Offset, cell.Y.Scale * box.h + cell.Y.Offset
		local px, py = cpad.X.Scale * box.w + cpad.X.Offset, cpad.Y.Scale * box.h + cpad.Y.Offset
		local horizontal = get(grid, "FillDirection", Enum.FillDirection.Horizontal) == Enum.FillDirection.Horizontal
		local maxCells = get(grid, "FillDirectionMaxCells", 0)
		local fit = if horizontal
			then math.max(1, math.floor((box.w + px) / math.max(cw + px, 1) + 1e-6))
			else math.max(1, math.floor((box.h + py) / math.max(ch + py, 1) + 1e-6))
		if maxCells > 0 then
			fit = math.min(fit, maxCells)
		end
		local n = #items
		local cols = if horizontal then math.min(n, fit) else math.ceil(n / fit)
		local rows = if horizontal then math.ceil(n / fit) else math.min(n, fit)
		local blockW = math.max(cols * (cw + px) - px, 0)
		local blockH = math.max(rows * (ch + py) - py, 0)
		local hAlign = get(grid, "HorizontalAlignment", Enum.HorizontalAlignment.Left)
		local vAlign = get(grid, "VerticalAlignment", Enum.VerticalAlignment.Top)
		local x0 = box.x
			+ alignOffset(box.w - blockW, hAlign, Enum.HorizontalAlignment.Left, Enum.HorizontalAlignment.Center)
		local y0 = box.y
			+ alignOffset(box.h - blockH, vAlign, Enum.VerticalAlignment.Top, Enum.VerticalAlignment.Center)
		for i, c in items do
			local idx = i - 1
			local col = if horizontal then idx % fit else idx // fit
			local row = if horizontal then idx // fit else idx % fit
			rects[c] = { x = x0 + col * (cw + px), y = y0 + row * (ch + py), w = cw, h = ch }
		end
	else
		for _, c in items do
			local w, h = sizeOf(c, box.w, box.h)
			local pos = get(c, "Position", roblox.UDim2.new())
			local anchor = get(c, "AnchorPoint", roblox.Vector2.zero)
			rects[c] = {
				x = box.x + pos.X.Scale * box.w + pos.X.Offset - anchor.X * w,
				y = box.y + pos.Y.Scale * box.h + pos.Y.Offset - anchor.Y * h,
				w = w,
				h = h,
			}
		end
	end
	return rects
end

--------------------------------------------------------------------------------
-- Describing one object
--------------------------------------------------------------------------------

local function colorSeq(seq: any): { any }
	local out = {}
	for _, kp in seq.Keypoints do
		local c = kp.Value
		table.insert(out, { r2(kp.Time), math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) })
	end
	return out
end

local function numberSeq(seq: any): { any }
	local out = {}
	for _, kp in seq.Keypoints do
		table.insert(out, { r2(kp.Time), r2(kp.Value) })
	end
	return out
end

local function gradientOf(inst: any): any?
	local g = childOfClass(inst, "UIGradient")
	if not g or not get(g, "Enabled", true) then
		return nil
	end
	local off = get(g, "Offset", roblox.Vector2.zero)
	return {
		c = colorSeq(get(g, "Color", roblox.ColorSequence.new(roblox.Color3.new(1, 1, 1)))),
		a = numberSeq(get(g, "Transparency", roblox.NumberSequence.new(0))),
		rot = r2(get(g, "Rotation", 0)),
		off = { r2(off.X), r2(off.Y) },
		type = enumName(get(g, "Type", nil), "Linear"),
		tile = enumName(get(g, "TileMode", nil), "Clamp"),
		scale = r2(get(g, "Scale", 1)),
	}
end

local function isText(inst: any): boolean
	return inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")
end

local function strokesOf(inst: any, rect: Rect, k: number): ({ any }, boolean)
	local out = {}
	local border = false
	for _, s in inst:GetChildren() do
		if s.ClassName == "UIStroke" and get(s, "Enabled", true) then
			local mode = get(s, "ApplyStrokeMode", Enum.ApplyStrokeMode.Contextual)
			local target = if mode == Enum.ApplyStrokeMode.Contextual and isText(inst) then "text" else "border"
			if target == "border" then
				border = true
			end
			local thickness = get(s, "Thickness", 1)
			if get(s, "StrokeSizingMode", nil) == Enum.StrokeSizingMode.ScaledSize then
				thickness *= math.min(rect.w, rect.h) -- Thickness is a fraction of the shorter side
			end
			local bo = get(s, "BorderOffset", roblox.UDim.new())
			table.insert(out, {
				color = rgb(get(s, "Color", roblox.Color3.new())),
				t = r2(thickness * k),
				offset = r2((bo.Scale * math.min(rect.w, rect.h) + bo.Offset) * k),
				tr = r2(get(s, "Transparency", 0)),
				target = target,
				pos = enumName(get(s, "BorderStrokePosition", nil), "Outer"),
				join = enumName(get(s, "LineJoinMode", nil), "Round"),
				grad = gradientOf(s),
			})
		end
	end
	return out, border
end

local fishByTitle: { [string]: string } = {}

local function describeModel(model: any): any
	local title = model:GetAttribute("Title")
	return {
		name = model.Name,
		fish = if typeof(title) == "string" then fishByTitle[title] else nil,
		mutation = model:GetAttribute("Mutation"),
		title = title,
		rarity = model:GetAttribute("Rarity"),
		kind = model:GetAttribute("Kind"),
	}
end

local function describe(inst: any, rect: Rect, T: Xf, clip: { number }?, alpha: number, path: string): any
	local k = T.k
	local cx, cy = apply(T, rect.x + rect.w / 2, rect.y + rect.h / 2)
	local w, h = rect.w * k, rect.h * k
	local o: { [string]: any } = {
		path = path,
		class = inst.ClassName,
		name = inst.Name,
		z = get(inst, "ZIndex", 1),
		x = r2(cx - w / 2),
		y = r2(cy - h / 2),
		w = r2(w),
		h = r2(h),
		rot = r2(T.rot),
		k = r2(k * 1000) / 1000,
		clip = clip,
		alpha = r2(alpha),
		bg = rgb(get(inst, "BackgroundColor3", roblox.Color3.new(1, 1, 1))),
		bgT = r2(get(inst, "BackgroundTransparency", 0)),
	}
	local corner = childOfClass(inst, "UICorner")
	if corner then
		-- Lune's reflection database stores the four per-corner radii (CornerRadius sets all
		-- four); scale is a fraction of the shorter side, the radius is at most half of it.
		-- A loaded place has only the per-corner values; CornerRadius set at runtime (or in a
		-- builder before saving) is readable and wins over per-corner values left at the default.
		local short = math.min(rect.w, rect.h)
		local whole = get(corner, "CornerRadius", nil)
		local radii = {}
		for i, key in { "TopLeftRadius", "TopRightRadius", "BottomRightRadius", "BottomLeftRadius" } do
			local cr = get(corner, key, nil)
			if whole and (cr == nil or (cr.Scale == 0 and cr.Offset == 8)) then
				cr = whole
			end
			cr = cr or roblox.UDim.new(0, 8)
			radii[i] = r2(math.clamp(cr.Scale * short + cr.Offset, 0, short / 2) * k)
		end
		if radii[1] == radii[2] and radii[2] == radii[3] and radii[3] == radii[4] then
			o.radius = radii[1]
		else
			o.radius = math.max(radii[1], radii[2], radii[3], radii[4])
			o.radii = radii
		end
	end
	local strokes, borderStroke = strokesOf(inst, rect, k)
	if #strokes > 0 then
		o.strokes = strokes
	end
	local borderSize = get(inst, "BorderSizePixel", 0)
	if borderSize > 0 and not corner and not borderStroke and not inst:IsA("ScreenGui") then
		o.border = {
			size = r2(borderSize * k),
			color = rgb(get(inst, "BorderColor3", roblox.Color3.new())),
			mode = enumName(get(inst, "BorderMode", nil), "Outline"),
		}
	end
	o.grad = gradientOf(inst)
	local auto = get(inst, "AutomaticSize", nil)
	if auto and auto ~= Enum.AutomaticSize.None then
		o.auto = auto.Name
	end

	if isText(inst) then
		local text = get(inst, "Text", "")
		if text ~= "" then
			local font = get(inst, "FontFace", nil)
			local tsc = childOfClass(inst, "UITextSizeConstraint")
			local pad = childOfClass(inst, "UIPadding")
			local padPx = { 0, 0, 0, 0 }
			if pad then
				local l, t = get(pad, "PaddingLeft", roblox.UDim.new()), get(pad, "PaddingTop", roblox.UDim.new())
				local r, b = get(pad, "PaddingRight", roblox.UDim.new()), get(pad, "PaddingBottom", roblox.UDim.new())
				padPx = {
					r2((l.Scale * rect.w + l.Offset) * k),
					r2((t.Scale * rect.h + t.Offset) * k),
					r2((r.Scale * rect.w + r.Offset) * k),
					r2((b.Scale * rect.h + b.Offset) * k),
				}
			end
			local family = "SourceSans"
			local weight = 400
			local style = "Normal"
			if font then
				family = string.match(font.Family, "families/([%w_]+)%.json") or font.Family
				weight = (font.Weight and font.Weight.Value) or 400
				style = (font.Style and font.Style.Name) or "Normal"
			end
			o.text = {
				s = text,
				rich = get(inst, "RichText", false),
				c = rgb(get(inst, "TextColor3", roblox.Color3.new())),
				tr = r2(get(inst, "TextTransparency", 0)),
				sc = rgb(get(inst, "TextStrokeColor3", roblox.Color3.new())),
				st = r2(get(inst, "TextStrokeTransparency", 1)),
				scaled = get(inst, "TextScaled", false),
				size = get(inst, "TextSize", 14),
				wrap = get(inst, "TextWrapped", false),
				xa = enumName(get(inst, "TextXAlignment", nil), "Center"),
				ya = enumName(get(inst, "TextYAlignment", nil), "Center"),
				font = family,
				weight = weight,
				style = style,
				lh = get(inst, "LineHeight", 1),
				min = if tsc then get(tsc, "MinTextSize", 1) else nil,
				max = if tsc then get(tsc, "MaxTextSize", 100) else nil,
				pad = padPx,
				trunc = enumName(get(inst, "TextTruncate", nil), "None"),
				graphemes = get(inst, "MaxVisibleGraphemes", -1),
			}
		end
	end
	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		local image = get(inst, "Image", "")
		if image ~= "" then
			o.image = {
				src = image,
				c = rgb(get(inst, "ImageColor3", roblox.Color3.new(1, 1, 1))),
				tr = r2(get(inst, "ImageTransparency", 0)),
				scale = enumName(get(inst, "ScaleType", nil), "Stretch"),
			}
		end
	end
	if inst:IsA("ViewportFrame") then
		local models = {}
		for _, d in inst:GetDescendants() do
			if d:IsA("Model") and (d:GetAttribute("Title") ~= nil or d:GetAttribute("Kind") ~= nil) then
				table.insert(models, describeModel(d))
			end
		end
		o.viewport = {
			models = models,
			c = rgb(get(inst, "ImageColor3", roblox.Color3.new(1, 1, 1))),
			tr = r2(get(inst, "ImageTransparency", 0)),
		}
	end
	return o
end

--------------------------------------------------------------------------------
-- Dumping a PlayerGui
--------------------------------------------------------------------------------

-- The device safe area of the current device (see DEVICES), px.
local SAFE = { left = 0, right = 0, bottom = 0 }

-- Screen rect of a ScreenGui's content. IgnoreGuiInset = true is taken as DeviceSafeInsets
-- (Roblox: it overrides ScreenInsets and keeps only the device insets).
local function layerRect(gui: any, vw: number, vh: number): Rect
	local l, r, b = SAFE.left, SAFE.right, SAFE.bottom
	if gui:IsA("ScreenGui") then
		local ignore = get(gui, "IgnoreGuiInset", false)
		local insets = get(gui, "ScreenInsets", Enum.ScreenInsets.CoreUISafeInsets)
		if insets == Enum.ScreenInsets.None and not ignore then
			return { x = 0, y = 0, w = vw, h = vh }
		end
		if ignore or insets == Enum.ScreenInsets.DeviceSafeInsets then
			return { x = l, y = 0, w = vw - l - r, h = vh - b }
		end
		if insets == Enum.ScreenInsets.TopbarSafeInsets then
			return { x = l, y = 0, w = vw - l - r, h = INSET }
		end
	end
	return { x = l, y = INSET, w = vw - l - r, h = vh - INSET - b }
end

--[[
	RbxSim lays a ScreenGui out over the whole viewport below the top bar. On a device with
	insets (phone_notch) the HUD's CoreUISafeInsets area is smaller and shifted; this hook
	re-registers AbsoluteSize / AbsolutePosition of ScreenGuis (LayerCollector) and GuiObjects
	so that, for a player with insets, an inset-keeping layer and everything in it are measured
	inside the safe area: the sim's own layout runs against a viewport shrunk by the insets and
	the result is shifted right by the left inset. Camera.ViewportSize stays the full screen.
	Installed once, before the sim is created (RbxSim resolves members per class lazily).
]]
local playerInsets: { [any]: { left: number, right: number, bottom: number } } = {}

local function keepsInsets(real: any): boolean
	local cur = real
	while cur ~= nil and not cur:IsA("LayerCollector") do
		cur = cur.Parent
	end
	if cur == nil or not cur:IsA("ScreenGui") or get(cur, "IgnoreGuiInset", false) then
		return false
	end
	return get(cur, "ScreenInsets", Enum.ScreenInsets.CoreUISafeInsets) == Enum.ScreenInsets.CoreUISafeInsets
end

local safeAreaInstalled = false
local function installSafeArea()
	if safeAreaInstalled then
		return
	end
	safeAreaInstalled = true
	local original = SimMembers.new(nil)
	local function measured(sim: any, real: any, defs: any, key: string): any
		local player = sim.players:ownerOf(real)
		local ins = player and playerInsets[player]
		local st = player and sim.players.state[player]
		if not ins or not st or not keepsInsets(real) then
			return defs[key].get(sim, real, key)
		end
		local full = st.viewport
		st.viewport = roblox.Vector2.new(full.X - ins.left - ins.right, full.Y - ins.bottom)
		local ok, value = pcall(defs[key].get, sim, real, key)
		st.viewport = full
		if not ok then
			error(value, 0)
		end
		if key == "AbsolutePosition" then
			return value + roblox.Vector2.new(ins.left, 0)
		end
		return value
	end
	for _, className in { "GuiObject", "LayerCollector" } do
		local defs = original:resolve(className)
		SimMembers.define(className, {
			AbsoluteSize = SimMembers.prop(function(sim, real)
				return measured(sim, real, defs, "AbsoluteSize")
			end),
			AbsolutePosition = SimMembers.prop(function(sim, real)
				return measured(sim, real, defs, "AbsolutePosition")
			end),
		})
	end
end

local function intersect(a: { number }?, b: { number }): { number }
	if not a then
		return b
	end
	return { math.max(a[1], b[1]), math.max(a[2], b[2]), math.min(a[3], b[3]), math.min(a[4], b[4]) }
end

-- Axis-aligned screen box of a natural rect under T (T not rotated).
local function screenBox(T: Xf, r: Rect): { number }
	local x0, y0 = apply(T, r.x, r.y)
	local x1, y1 = apply(T, r.x + r.w, r.y + r.h)
	return { r2(math.min(x0, x1)), r2(math.min(y0, y1)), r2(math.max(x0, x1)), r2(math.max(y0, y1)) }
end

type Entry = { obj: any, z: number, order: number }

--[[
	Lays out and describes the GuiObjects under `gui` (a ScreenGui, BillboardGui or SurfaceGui)
	whose content box is `box` (screen px — or canvas px for a SurfaceGui), in draw order.
	Paths are relative to `pathRoot`. `layoutInfo` (optional) collects { rect, T } per object
	for --check. Used for the PlayerGui and, by gui/world_capture.luau, for billboards and
	surface GUIs in the world.
]]
local function dumpTree(gui: any, box: Rect, pathRoot: any, layoutInfo: { [any]: any }?): { any }
	local global = get(gui, "ZIndexBehavior", Enum.ZIndexBehavior.Sibling) == Enum.ZIndexBehavior.Global
	local entries: { Entry } = {}
	local counter = 0

	local function visit(parent: any, inBox: Rect, T: Xf, clip: { number }?, alpha: number)
		local rects = layoutChildren(parent, inBox)
		local kids = {}
		for i, c in parent:GetChildren() do
			if rects[c] then
				table.insert(kids, { c = c, i = i, z = get(c, "ZIndex", 1) })
			end
		end
		if not global then
			table.sort(kids, function(a, b)
				if a.z ~= b.z then
					return a.z < b.z
				end
				return a.i < b.i
			end)
		end
		for _, kid in kids do
			local c = kid.c
			local r = rects[c]
			local Tc = T
			local anchor = get(c, "AnchorPoint", roblox.Vector2.zero)
			local ax, ay = r.x + anchor.X * r.w, r.y + anchor.Y * r.h
			local uiScale = childOfClass(c, "UIScale")
			local s = if uiScale then get(uiScale, "Scale", 1) else 1
			local local_: Xf = IDENTITY
			if s ~= 1 then
				local_ = scaleAbout(s, ax, ay)
			end
			local rot = get(c, "Rotation", 0)
			if rot ~= 0 then
				local ccx, ccy = r.x + r.w / 2, r.y + r.h / 2
				local vcx, vcy = ax + s * (ccx - ax), ay + s * (ccy - ay)
				local_ = compose(rotateAbout(rot, vcx, vcy), local_)
			end
			if local_ ~= IDENTITY then
				Tc = compose(T, local_)
			end
			local a = alpha
			if c:IsA("CanvasGroup") then
				a *= 1 - get(c, "GroupTransparency", 0)
			end
			counter += 1
			local path = pathOf(c, pathRoot)
			table.insert(entries, {
				obj = describe(c, r, Tc, clip, a, path),
				z = kid.z,
				order = counter,
			})
			if layoutInfo then
				layoutInfo[c] = { rect = r, T = Tc }
			end
			local childClip = clip
			local clips = get(c, "ClipsDescendants", false) or c:IsA("CanvasGroup") or c:IsA("ScrollingFrame")
			if clips and not isRotated(Tc) then
				childClip = intersect(clip, screenBox(Tc, r))
			end
			local inner = contentBox(c, r)
			if c:IsA("ScrollingFrame") then
				local cs = get(c, "CanvasSize", roblox.UDim2.new())
				local cp = get(c, "CanvasPosition", roblox.Vector2.zero)
				inner = {
					x = inner.x - cp.X,
					y = inner.y - cp.Y,
					w = cs.X.Scale * inner.w + cs.X.Offset,
					h = cs.Y.Scale * inner.h + cs.Y.Offset,
				}
			end
			visit(c, inner, Tc, childClip, a)
		end
	end

	-- A UIScale directly under the layer scales everything about its top-left corner.
	local rootScale = childOfClass(gui, "UIScale")
	local T0 = IDENTITY
	local inner = contentBox(gui, box)
	if rootScale and get(rootScale, "Scale", 1) ~= 1 then
		local s = get(rootScale, "Scale", 1)
		T0 = scaleAbout(s, box.x, box.y)
		inner = { x = inner.x, y = inner.y, w = inner.w / s, h = inner.h / s }
	end
	visit(gui, inner, T0, nil, 1)
	if global then
		table.sort(entries, function(a, b)
			if a.z ~= b.z then
				return a.z < b.z
			end
			return a.order < b.order
		end)
	end
	local out = table.create(#entries)
	for i, e in entries do
		out[i] = e.obj
	end
	return out
end

local function dumpPlayerGui(playerGui: any, vw: number, vh: number): ({ any }, { [any]: any })
	local layers = {}
	for i, c in playerGui:GetChildren() do
		if c:IsA("ScreenGui") and get(c, "Enabled", true) then
			table.insert(layers, { gui = c, order = get(c, "DisplayOrder", 0), index = i })
		end
	end
	table.sort(layers, function(a, b)
		if a.order ~= b.order then
			return a.order < b.order
		end
		return a.index < b.index
	end)
	local out = {}
	local layoutInfo: { [any]: any } = {}
	for _, layer in layers do
		for _, obj in dumpTree(layer.gui, layerRect(layer.gui, vw, vh), playerGui, layoutInfo) do
			table.insert(out, obj)
		end
	end
	return out, layoutInfo
end

--------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------

local Harness = {}
Harness.__index = Harness

-- Every sim step of the harness goes through here (the world capture watches what appears).
-- Inside a scenario's `during` coroutine the step is handed to the frame loop instead.
function Harness:simStep(dt: number)
	if self.yieldSteps and coroutine.running() == self.yieldSteps then
		coroutine.yield(dt)
		return
	end
	self.sim:Step(dt)
	self:syncToolPose()
	local capture = self.world or self.avatarCapture
	if capture then
		capture:observe()
	end
end

--[[
	The Roblox Animate script plays "toolnone" (the right arm forward, the rod ≈35° up) while a
	Tool is equipped; RbxSim's Animator stand-in plays nothing, so the rod would hang down
	whenever FisherAnimController lets go of the arm (Hold → Linger → released). Here the
	stand-in holds FisherPoses.Hold (= toolnone) while a Tool is in the character.
]]
function Harness:syncToolPose()
	local character = self.player.Character
	if not character then
		return
	end
	local holding = character:FindFirstChildOfClass("Tool") ~= nil
	if holding == self.toolPose and character == self.poseCharacter then
		return
	end
	self.toolPose, self.poseCharacter = holding, character
	local pose = nil
	if holding then
		local ok, result = pcall(function()
			local controllers = "StarterPlayer.StarterPlayerScripts.Controllers"
			local rigModule = self.sim:Require(self.sim:Find(`{controllers}.FisherRig`))
			local poses = self.sim:Require(self.sim:Find(`{controllers}.FisherPoses`))
			local rig = rigModule.build(character)
			local out = {}
			for channel, a in (poses.Poses.Hold or {}) do
				local j = rig and rig.joints[channel]
				if j then
					out[j.instance.Name] = j.inv * rigModule.rot(a[1], a[2], a[3]) * j.rot
				end
			end
			return out
		end)
		pose = if ok then result else nil
	end
	self.sim:SetAnimatorPose(self.player, pose)
end

function Harness:step(dt: number?)
	self:simStep(dt or FRAME)
end

function Harness:advance(seconds: number, step: number?)
	local dt = step or FRAME
	local n = math.floor(seconds / dt + 1e-6)
	for _ = 1, n do
		self:simStep(dt)
	end
	local rest = seconds - n * dt
	if rest > 1e-6 then
		self:simStep(rest)
	end
end

function Harness:gui(path: string): any
	return self.sim:Gui(self.player, path)
end

function Harness:visible(path: string): boolean
	local inst = self:gui(path)
	if not inst then
		return false
	end
	local cur = inst
	while cur and cur:IsA("GuiObject") do
		if not cur.Visible then
			return false
		end
		cur = cur.Parent
	end
	if cur and cur:IsA("ScreenGui") then
		return cur.Enabled
	end
	return true
end

function Harness:waitFor(fn: () -> any, timeout: number?): any
	local deadline = self.sim:Time() + (timeout or 5)
	while true do
		local v = fn()
		if v then
			return v
		end
		if self.sim:Time() >= deadline then
			self:warn(`waitFor timed out after {timeout or 5} s`)
			return nil
		end
		self:simStep(FRAME)
	end
end

function Harness:waitVisible(path: string, timeout: number?): boolean
	local ok = self:waitFor(function()
		return self:visible(path)
	end, timeout)
	if not ok then
		self:warn(`{path} never became visible`)
	end
	return ok == true
end

function Harness:warn(message: string)
	table.insert(self.warnings, message)
	print(`[gui_dump] {self.scenario}/{self.device}: {message}`)
end

function Harness:click(path: string, _down: boolean?)
	local button = self:gui(path)
	if not button then
		self:warn(`click: {path} not found`)
		return
	end
	local ok, why = self.sim:CanClick(self.player, button)
	if not ok then
		self:warn(`click: {path} not clickable ({why}); forcing`)
	end
	self.sim:Click(self.player, button, { force = true })
	self:simStep(FRAME)
end

function Harness:press()
	self.sim:PressKey(self.player, Enum.KeyCode.F)
	self:simStep(FRAME)
end

function Harness:serverSays(state: string, data: any?)
	self.sim:Find("ReplicatedStorage.Remotes.FishingState"):FireClient(self.player, state, data)
	self:simStep(FRAME)
end

function Harness:notify(text: string, kind: string?)
	self.sim:Find("ReplicatedStorage.Remotes.Notify"):FireClient(self.player, text, kind or "info")
	self:simStep(FRAME)
end

function Harness:backpackRod(): any
	local backpack = self.player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil
	end
	for _, item in backpack:GetChildren() do
		if item:IsA("Tool") and item:GetAttribute("RodId") ~= nil then
			return item
		end
	end
	return nil
end

function Harness:giveRod(): any
	local existing = self:backpackRod()
	if existing then
		return existing
	end
	local template = self.sim:Find("ReplicatedStorage.Assets.Rods.RodBamboo")
	local rod = template:Clone()
	rod.Name = template:GetAttribute("DisplayName") or "Бамбуковая удочка"
	rod.Parent = self.player:FindFirstChildOfClass("Backpack")
	self.player:SetAttribute("RodId", "RodBamboo")
	self.player:SetAttribute("FishingState", "Idle")
	self.player:SetAttribute("FishCaught", self.player:GetAttribute("FishCaught") or 0)
	self:advance(0.05)
	return rod
end

function Harness:equipRod(): any
	local rod = self:backpackRod() or self:giveRod()
	self.sim:EquipTool(self.player, rod)
	self:advance(0.1)
	return rod
end

function Harness:base(): any
	local bases = self.sim.workspace:FindFirstChild("Bases")
	return bases and bases:FindFirstChild(`Base_{self.player:GetAttribute("BaseIndex")}`)
end

function Harness:spot(): any
	local base = self:base()
	return base and base:FindFirstChild("FishingSpot")
end

function Harness:standAtSpot()
	local spot = self:spot()
	if not spot then
		self:warn("no FishingSpot (no base?)")
		return
	end
	self.sim:Teleport(self.player, spot.Position + Vector3.new(0, 3, 0))
	self:advance(0.3)
end

function Harness:standFar()
	local spot, base = self:spot(), self:base()
	if not spot or not base then
		self:warn("no FishingSpot (no base?)")
		return
	end
	local inland = base:GetPivot().Position - spot.Position
	inland = Vector3.new(inland.X, 0, inland.Z)
	local dir = if inland.Magnitude > 1 then inland.Unit else Vector3.new(0, 0, 1)
	self.sim:Teleport(self.player, spot.Position + dir * 40 + Vector3.new(0, 3, 0))
	self:advance(0.3)
end

function Harness:config(name: string): any
	return self.sim:Require(self.sim:Find(`ReplicatedStorage.Shared.Config.{name}`))
end

function Harness:minigame(rarity: string, extra: { [string]: any }?)
	local cfg = self:config("FishingConfig")
	local rule = cfg.Minigame[rarity] or cfg.Minigame.Common
	local data = {
		Rarity = rarity,
		U0 = 0,
		Speed = rule.Speed,
		ZoneCenter = 0.6,
		ZoneWidth = rule.ZoneWidth,
		Hits = 0,
		HitsNeeded = rule.Hits,
		Timeout = cfg.MinigameTimeout,
	}
	for key, value in extra or {} do
		data[key] = value
	end
	self:serverSays("Minigame", data)
end

-- "Caught" { Fish, Total, Tank? } — tank (stage 3) is the TankResult the server sends with the
-- catch ({ Result = "stored" | "replaced" | "sold", Slot?, Uid?, Count, Slots, Replaced?, Price?,
-- First? }); nil = the old payload (the tank did not take the fish).
function Harness:caught(fish: { [string]: any }, total: number?, tank: { [string]: any }?)
	self:serverSays("Caught", { Fish = fish, Total = total or 1, Tank = tank })
end

--------------------------------------------------------------------------------
-- Stage 3: the tank and the money. In the stub sim DataService, EconomyService, MarketService and
-- TankService are switched off like FishingService (STUBBED_SERVICES): the harness plays them
-- through their replicated state (RemoteNames, «Состояние садка и денег») — every player joins
-- with stage3Defaults (loaded data, $0, an empty StartSlots tank, the home rate).
--------------------------------------------------------------------------------

-- The player's money (Player attribute Money) and, optionally, income (income10: tenths of a
-- coin per second → the Income attribute in $/s).
function Harness:money(n: number, income10: number?)
	self.player:SetAttribute("Money", n)
	if income10 ~= nil then
		self.player:SetAttribute("Income", income10 / 10)
	end
	self:simStep(FRAME)
end

-- The own base's tank, written like TankService does. list = { { Id, Kg?, Mutation?, Age?,
-- Slot?, Uid? } } is the WHOLE tank after the change (Slot defaults to the position in the list,
-- Age to 0 s in the tank). Every display Slot_1..MaxSlots gets its fish fields (FishUid, FishId,
-- Rarity, Mutation, Kg, Value, Income, GrowFrom = TankRules.AttrTime(now − Age); all nil on
-- "empty" / "locked"), then State ("fish" | "empty" | "locked" beyond opts.slots), then Event
-- LAST, in RemoteNames' «Состояние садка» format:
--   opts.event "mount" (default) — every display gets "<n>|mount|" (the tank mounting on a base);
--   "in" | "swap" | "sold" — only the display opts.at gets an Event (as on the server, which
--   writes just the slot that changed): "<n>|in|<its FishId>", "<n>|swap|<price>" (a new fish in
--   place of a sold one) or "<n>|sold|<price>" (the display is empty now). opts.at defaults to
--   the slot of the LAST fish in list for "in" / "swap" and is required for "sold"; price =
--   opts.price, else TankRules.SellPrice(value, Age, HomeRatePct) of opts.gone = { Id, Kg?,
--   Mutation?, Age? } (the fish that left).
-- The tank model gets Count / Slots / Income and the player TankCount / TankSlots / Income.
-- Returns the fish as written ({ Uid, Slot, Id, Rarity, Value, Income10, … }).
local slotEventSerial = 0
local SLOT_EVENTS = { mount = true, ["in"] = true, swap = true, sold = true }
function Harness:tank(list: { { [string]: any } }, opts: { [string]: any }?): { { [string]: any } }
	local base = self:base()
	local written = {}
	if not base then
		self:warn("h:tank: the player has no base")
		return written
	end
	local o = opts or {}
	local cfg = self:config("TankConfig")
	local rules = self.sim:Require(self.sim:Find("ReplicatedStorage.Shared.FishingRules"))
	local tankRules = self.sim:Require(self.sim:Find("ReplicatedStorage.Shared.TankRules"))
	local unlocked = math.min(o.slots or cfg.StartSlots, cfg.MaxSlots)
	local now = self.sim.workspace:GetServerTimeNow()
	local event = o.event or "mount"
	if not SLOT_EVENTS[event] then
		self:warn(`h:tank: unknown event «{event}» (mount | in | swap | sold)`)
		event = "mount"
	end
	local bySlot = {}
	local lastSlot = nil
	for i, spec in list do
		bySlot[spec.Slot or i] = spec
		lastSlot = spec.Slot or i
	end
	local at = o.at or (if event == "in" or event == "swap" then lastSlot else nil)
	if event ~= "mount" and not (at and at >= 1 and at <= cfg.MaxSlots) then
		self:warn(`h:tank: event «{event}» needs opts.at (the display it happened on)`)
	end
	local price = o.price
	if (event == "sold" or event == "swap") and price == nil then
		local gone = o.gone
		if gone and rules.GetFish(gone.Id) then
			local def = rules.GetFish(gone.Id)
			local value = rules.Price(gone.Id, gone.Kg or (def.MinKg + def.MaxKg) / 2, gone.Mutation)
			price = tankRules.SellPrice(value, gone.Age or 0, self:config("EconomyConfig").HomeRatePct)
		else
			self:warn(`h:tank: event «{event}» needs opts.price or opts.gone (the fish that left)`)
			price = 0
		end
	end
	local fields = { "FishUid", "FishId", "Rarity", "Mutation", "Kg", "Value", "Income", "GrowFrom" }
	local count, income10 = 0, 0
	for index = 1, cfg.MaxSlots do
		local slot = base.Tank.Slots:FindFirstChild(`Slot_{index}`)
		local spec = bySlot[index]
		if not slot then
			self:warn(`h:tank: no Slot_{index}`)
			continue
		end
		local state = if index > unlocked then "locked" elseif spec then "fish" else "empty"
		if state == "fish" and spec then
			local def = rules.GetFish(spec.Id)
			local kg = spec.Kg or (if def then (def.MinKg + def.MaxKg) / 2 else 1)
			local value, income = rules.Price(spec.Id, kg, spec.Mutation)
			local tenths = tankRules.Income10(income)
			local uid = spec.Uid or tankRules.UidOf(index)
			slot:SetAttribute("FishUid", uid)
			slot:SetAttribute("FishId", spec.Id)
			slot:SetAttribute("Rarity", if def then def.Rarity else "Common")
			slot:SetAttribute("Mutation", spec.Mutation)
			slot:SetAttribute("Kg", kg)
			slot:SetAttribute("Value", value)
			slot:SetAttribute("Income", tenths / 10)
			slot:SetAttribute("GrowFrom", tankRules.AttrTime(now - (spec.Age or 0)))
			count += 1
			income10 += tenths
			table.insert(written, {
				Uid = uid,
				Slot = index,
				Id = spec.Id,
				Rarity = if def then def.Rarity else "Common",
				Mutation = spec.Mutation,
				Kg = kg,
				Value = value,
				Income10 = tenths,
			})
		else
			for _, name in fields do
				slot:SetAttribute(name, nil)
			end
		end
		slot:SetAttribute("State", state)
		local detail = nil
		if event == "mount" then
			detail = ""
		elseif index == at then
			if event == "in" then
				detail = if spec then spec.Id else ""
				if not spec then
					self:warn(`h:tank: event «in» on Slot_{index}, but list has no fish there`)
				end
			else
				detail = string.format("%d", price)
			end
		end
		if detail ~= nil then
			slotEventSerial += 1
			slot:SetAttribute("Event", `{slotEventSerial}|{event}|{detail}`)
		end
	end
	base.Tank:SetAttribute("Count", count)
	base.Tank:SetAttribute("Slots", unlocked)
	base.Tank:SetAttribute("Income", income10 / 10)
	self.player:SetAttribute("TankCount", count)
	self.player:SetAttribute("TankSlots", unlocked)
	self.player:SetAttribute("Income", income10 / 10)
	self:simStep(FRAME)
	return written
end

-- TankEvent (kind, data) to this client: "Open" | "Sold" | "Stored" | "Denied" (RemoteNames).
function Harness:tankEvent(kind: string, data: { [string]: any }?)
	self.sim:Find("ReplicatedStorage.Remotes.TankEvent"):FireClient(self.player, kind, data or {})
	self:simStep(FRAME)
end

--------------------------------------------------------------------------------
-- Real-server play (scenarios with `server = true`: FishingService is live)
--------------------------------------------------------------------------------

-- The FishingState events this client got, oldest first: { { time, state, data } }.
function Harness:stateEvents(): { any }
	local out = {}
	for _, e in self.sim:ClientEventsFor(self.player, "FishingState") do
		table.insert(out, { time = e.time, state = e.args[1], data = e.args[2] })
	end
	return out
end

-- Every roll of FishingService gives this fish ({ Id, Mutation?, Kg? }; Kg defaults to the
-- middle of the species' range); returns the full FishData.
function Harness:forceFish(fish: { [string]: any }): { [string]: any }
	assert(self.server, "h:forceFish needs a scenario with server = true")
	local rules = self.sim:Require(self.sim:Find("ReplicatedStorage.Shared.FishingRules"))
	local def = rules.GetFish(fish.Id)
	assert(def, `unknown fish {fish.Id}`)
	local kg = fish.Kg or math.round((def.MinKg + def.MaxKg) / 2 * 100) / 100
	local value, income = rules.Price(fish.Id, kg, fish.Mutation)
	local data = {
		Id = fish.Id,
		Rarity = def.Rarity,
		Mutation = fish.Mutation,
		Kg = kg,
		Value = value,
		Income = income,
	}
	local service = self.sim:Require(self.sim:Find("ServerScriptService.Services.FishingService"))
	service.RollFishForTest = function()
		return table.clone(data)
	end
	return data
end

-- The character on the own FishingSpot facing the lagoon (world scenarios), where the capture's
-- camera expects the fisher: the line, the cast, the leap and the held fish are in the frame.
function Harness:poseLikeBackdrop()
	if self.world then
		self.world:pose()
	end
end

local ACTION = "HUD.Fishing.ActionArea.ActionButton"

-- The first FishingState `state` after the first `count` events, or nil.
function Harness:stateAfter(count: number, state: string): any
	for i, e in self:stateEvents() do
		if i > count and e.state == state then
			return e
		end
	end
	return nil
end

-- Real-server play, step 1: every roll gives `fish`; onto the own FishingSpot (posed for the
-- camera), rod in hand, 0.4 s to settle. Returns the FishData.
function Harness:readyReal(fish: { [string]: any }): { [string]: any }
	local data = self:forceFish(fish)
	self:standAtSpot()
	self:equipRod()
	self:poseLikeBackdrop()
	self:advance(0.4)
	return data
end

-- Step 2: tap «ЗАБРОСИТЬ», wait for the bite, tap «ПОДСЕЧЬ!» after `opts.reaction` s (0.3).
-- Returns the "Minigame" event { time, state, data } (nil + a warning if it did not come).
function Harness:castAndHook(opts: { [string]: any }?): any
	local o = opts or {}
	local count = #self:stateEvents()
	self:click(ACTION)
	local bite = self:waitFor(function()
		return self:stateAfter(count, "Bite")
	end, 15)
	if not bite then
		self:warn("playCatch: no bite")
		return nil
	end
	self:advance(o.reaction or 0.3)
	count = #self:stateEvents()
	self:click(ACTION)
	local mg = self:waitFor(function()
		return self:stateAfter(count, "Minigame")
	end, 2)
	if not mg then
		self:warn("playCatch: the hook did not start the minigame")
	end
	return mg
end

-- Step 3: win the minigame `mg` — before each hit wait for the needle to cross the zone at
-- `opts.aim` (-1..1 of the half-width, 0 = the centre) and tap. With `opts.miss` the first tap
-- is made where the needle is well OUTSIDE the zone (a lost fish), not before `opts.after` s
-- of the minigame. Returns right after the winning (or missing) tap.
function Harness:playMinigame(mg: any, opts: { [string]: any }?)
	local o = opts or {}
	local rules = self.sim:Require(self.sim:Find("ReplicatedStorage.Shared.FishingRules"))
	local cfg = mg.data
	local center = cfg.ZoneCenter
	local hits = cfg.Hits or 0
	local earliest = mg.time + math.max(0.4, o.after or 0)
	while hits < cfg.HitsNeeded do
		local from = math.max(self.sim:Time(), earliest) - mg.time
		local goal = center + (o.aim or 0) * cfg.ZoneWidth / 2
		local target = nil
		for k = 0, 240 * 8 do
			local t = from + k / 240
			local needle = rules.Needle(cfg.U0, cfg.Speed, t)
			local ok = if o.miss
				then math.abs(needle - center) > cfg.ZoneWidth * 1.2
				else math.abs(needle - goal) < 0.012
			if ok then
				target = t
				break
			end
		end
		if not target then
			self:warn("playCatch: the needle never reaches the zone")
			return
		end
		self:advance(math.max(0, mg.time + target - self.sim:Time() - FRAME / 2))
		hits += 1
		local count = #self:stateEvents()
		self:click(ACTION)
		if hits >= cfg.HitsNeeded or o.miss then
			return
		end
		local reply = self:waitFor(function()
			local events = self:stateEvents()
			return if #events > count then events[#events] else nil
		end, 1)
		if not reply or reply.state ~= "Zone" then
			self:warn(`playCatch: tap {hits} was not a hit ({reply and reply.state or "no answer"})`)
			return
		end
		center = reply.data.ZoneCenter
		earliest = self.sim:Time() + 0.3
	end
end

--[[
	A whole catch with the real server, played like a person: readyReal (onto the own
	FishingSpot, rod in hand), castAndHook (tap «ЗАБРОСИТЬ», wait for the bite, tap «ПОДСЕЧЬ!»
	after `opts.reaction` s), playMinigame (`opts.aim`, `opts.miss`, `opts.after`). Returns right
	after the WINNING tap (make it the scenario's time 0) with the FishData; a miss or a
	timeout is a warning.
]]
function Harness:playCatch(fish: { [string]: any }, opts: { [string]: any }?): { [string]: any }
	local data = self:readyReal(fish)
	local mg = self:castAndHook(opts)
	if mg then
		self:playMinigame(mg, opts)
	end
	return data
end

-- The bite comes `seconds` after the bobber lands (FishingConfig.BiteDelay on the server, for
-- timelines of a fixed length); gui_dump restores it after the scenario.
function Harness:fixBiteDelay(seconds: number)
	local cfg = self.sim:Require(self.sim:Find("ReplicatedStorage.Shared.Config.FishingConfig"))
	if not self.biteDelaySaved then
		self.biteDelaySaved = { cfg.BiteDelay.Min, cfg.BiteDelay.Max }
	end
	cfg.BiteDelay.Min, cfg.BiteDelay.Max = seconds, seconds
end

function Harness:restoreBiteDelay()
	local saved = self.biteDelaySaved
	if saved then
		local cfg = self.sim:Require(self.sim:Find("ReplicatedStorage.Shared.Config.FishingConfig"))
		cfg.BiteDelay.Min, cfg.BiteDelay.Max = saved[1], saved[2]
		self.biteDelaySaved = nil
	end
end

-- The local player's own client controller module (FishingFxController, AmbientController …).
function Harness:clientModule(name: string): any?
	local scripts = self.player:FindFirstChildOfClass("PlayerScripts")
	local module = scripts and self.sim:Find(`Controllers.{name}`, scripts)
	if not module then
		return nil
	end
	local ok, result = pcall(function()
		return self.sim:Require(module, self.player)
	end)
	return if ok then result else nil
end

-- The GuiObject at `path` is on screen: Visible up the chain, its ScreenGui enabled, not
-- scaled to nothing (UIScale), not faded out (its own background or text, and CanvasGroups).
function Harness:shown(path: string): boolean
	local inst = self:gui(path)
	if not inst or not self:visible(path) then
		return false
	end
	local cur = inst
	while cur and cur:IsA("GuiObject") do
		local scale = cur:FindFirstChildOfClass("UIScale")
		if scale and scale.Scale < 0.05 then
			return false
		end
		if cur:IsA("CanvasGroup") and cur.GroupTransparency > 0.95 then
			return false
		end
		cur = cur.Parent
	end
	local bg = inst.BackgroundTransparency < 0.95
	local text = (inst:IsA("TextLabel") or inst:IsA("TextButton")) and inst.Text ~= "" and inst.TextTransparency < 0.95
	local image = (inst:IsA("ImageLabel") or inst:IsA("ImageButton")) and inst.ImageTransparency < 0.95
	if bg or text or image or inst:IsA("ViewportFrame") then
		return true
	end
	-- a container (no look of its own) is shown when it holds GuiObjects
	return inst:FindFirstChildWhichIsA("GuiObject") ~= nil
end

--------------------------------------------------------------------------------
-- Beats: when each moment of a scenario happened (the ruler of timelines and bursts)
--------------------------------------------------------------------------------

--[[
	A beat spec (scenario field `beats` replaces DEFAULT_BEATS, `extraBeats` adds to them):
	  { name, appear = path | { paths } }   first time one of the GuiObjects is shown (h:shown)
	  { name, appearNamed = "FxFlash" }      first time a GuiObject with this name is shown
	  { name, disappear = path }             first time it is hidden after having been shown
	  { name, change = path }                first time its Text differs from the start
	  { name, settle = path }                when its Text last changed (a count-up landing)
	  { name, state = "Caught" }             the client got this FishingState event
	  { name, event = "HeldFish", kind? }    world FX (world = true): a FishingFx child or the
	                                         HeldFish "appear"s (default) / "disappear"s, or a
	                                         FishingFxController signal (kind "signal")
	  { name, fn = function(h) -> bool }     anything else
	The first beat that has fired is kept (one time per beat).
]]
local DEFAULT_BEATS = {
	{ name = "caught", state = "Caught" },
	{ name = "win", appearNamed = "FxMinigameWin" },
	{ name = "leap", event = "Leap" },
	{ name = "landing", event = "OwnFishLanded", kind = "signal" },
	{ name = "held", event = "HeldFish" },
	{ name = "flash", appearNamed = "FxFlash" },
	{ name = "shock", appearNamed = "FxShockGlow" }, -- the ring itself is only a UIStroke
	{ name = "title", appear = "HUD.Fishing.TitleSlam" },
	{ name = "card", appear = "HUD.Fishing.CatchCard" },
	{ name = "banner", appear = "HUD.Fishing.CatchCard.Banner.RarityLabel" },
	{ name = "name", appear = "HUD.Fishing.CatchCard.NameLabel" },
	{ name = "new", appear = "HUD.Fishing.CatchCard.NewStamp" },
	{ name = "chips", appear = "HUD.Fishing.CatchCard.InfoLabel.Weight" },
	{ name = "price", settle = "HUD.Fishing.CatchCard.InfoLabel.Price.Label" },
	{
		name = "mutation",
		appear = { "HUD.Fishing.CatchCard.MutationLabel", "HUD.Fishing.CatchCard.MutationStamp" },
	},
	{ name = "pillar", event = "PillarCore" },
	{ name = "close", disappear = "HUD.Fishing.CatchCard" },
	{ name = "fly", appearNamed = "FxFly" },
	{ name = "+1", change = "HUD.Status.CatchCounter.Label" },
	{ name = "held gone", event = "HeldFish", kind = "disappear" },
	-- the rest of the loop (bursts of bites, hits and misses)
	{ name = "bite", state = "Bite" },
	{ name = "zone", state = "Zone" },
	{ name = "word", appearNamed = "FxFloat" },
	{ name = "lost", state = "Lost" },
	{ name = "miss ghost", appearNamed = "FxMinigameMiss" },
}

local Beats = {}
Beats.__index = Beats

function Beats.new(h: any, specs: { any }, capture: any?): any
	local self = setmetatable({ h = h, specs = specs, capture = capture, fired = {}, state = {}, t0 = 0 }, Beats)
	for _, spec in specs do
		local st = {}
		self.state[spec.name] = st
		local path = spec.change or spec.settle
		if path then
			local inst = h:gui(path)
			st.text = inst and inst.Text or nil
			st.lastChange = nil
		end
	end
	return self
end

local function asList(v: any): { any }
	return if type(v) == "table" then v else { v }
end

-- Names of the shown GuiObjects wanted by pending appearNamed beats (one pass per step).
function Beats:shownNames(): { [string]: boolean }
	local wanted = {}
	for _, spec in self.specs do
		if spec.appearNamed and self.fired[spec.name] == nil then
			wanted[spec.appearNamed] = true
		end
	end
	local out = {}
	local h = self.h
	local playerGui = h.player:FindFirstChildOfClass("PlayerGui")
	if not playerGui or next(wanted) == nil then
		return out
	end
	local rawGui = h.sim:Unwrap(playerGui)
	for _, d in rawGui:GetDescendants() do
		if wanted[d.Name] and not out[d.Name] and d:IsA("GuiObject") then
			if h:shown(pathOf(d, rawGui)) then
				out[d.Name] = true
			end
		end
	end
	return out
end

function Beats:step(t: number)
	local h = self.h
	local named: { [string]: boolean }? = nil
	for _, spec in self.specs do
		local name = spec.name
		local st = self.state[name]
		if spec.settle then
			local inst = h:gui(spec.settle)
			local text = inst and inst.Text or nil
			if text ~= st.text then
				st.text = text
				st.lastChange = t
			end
		end
		if self.fired[name] ~= nil then
			continue
		end
		local hit = false
		if spec.appear then
			for _, path in asList(spec.appear) do
				if h:shown(path) then
					hit = true
				end
			end
		elseif spec.appearNamed then
			named = named or self:shownNames()
			hit = named[spec.appearNamed] == true
		elseif spec.disappear then
			local now = h:shown(spec.disappear)
			if now then
				st.seen = true
			elseif st.seen then
				hit = true
			end
		elseif spec.change then
			local inst = h:gui(spec.change)
			hit = inst ~= nil and inst.Text ~= st.text
		elseif spec.state then
			for _, e in h:stateEvents() do
				if e.state == spec.state and e.time >= self.t0 - 0.25 then
					self.fired[name] = math.max(0, e.time - self.t0)
					break
				end
			end
		elseif spec.event then
			local kind = spec.kind or "appear"
			for _, e in (if self.capture then self.capture:eventList() else {}) do
				if e.name == spec.event and e.kind == kind and e.t >= -0.25 then
					self.fired[name] = math.max(0, e.t)
					break
				end
			end
		elseif spec.fn then
			local ok, v = pcall(spec.fn, h)
			hit = ok and v == true
		end
		if hit then
			self.fired[name] = t
		end
	end
end

-- Time 0 of the scenario (right after `run`): FishingState events from 0.25 s before it count.
function Beats:start()
	self.t0 = self.h.sim:Time()
end

-- { { name, t } } sorted by time (settle beats: when the text last changed).
function Beats:result(): { any }
	local out = {}
	for _, spec in self.specs do
		local t = self.fired[spec.name]
		if spec.settle then
			t = self.state[spec.name].lastChange
		end
		if t ~= nil then
			table.insert(out, { name = spec.name, t = math.round(t * 1000) / 1000 })
		end
	end
	table.sort(out, function(a, b)
		return a.t < b.t
	end)
	return out
end

--------------------------------------------------------------------------------
-- Built-in scenarios: catch timelines (real server + world FX) and the burst list
--------------------------------------------------------------------------------

-- Scenarios that get a 30 fps burst sheet of their first 0.8 s with --bursts (slams, stamps,
-- pops, the catch); a scenario's own `burst` field (a spec, true or false) wins.
local BURSTS = {
	bite = true,
	take_rod = true,
	hit = true,
	hit_perfect = true,
	hit_super = true,
	miss = true,
	catch_common = true,
	catch_legendary = true,
	catch_mythic = true,
	catch_gold = true,
	catch_rainbow = true,
	catch_close = true,
}
local BURST_DEFAULT = { from = 0, to = 0.8, fps = 30 }

local function timelineScenario(name: string, desc: string, fish: { [string]: any }, length: number): any
	return {
		name = name,
		desc = desc,
		server = true,
		world = true,
		standard = false,
		still = { 0.9, 2.0 },
		timeline = { from = 0, to = length, fps = 6 },
		burst = { from = 0, to = 0.8, fps = 30, roi = {} },
		run = function(h: any)
			h:playCatch(fish)
		end,
	}
end

-- Not in gui_scenarios.luau: they need the real FishingService and the world capture.
local BUILTIN = {
	timelineScenario(
		"catch_timeline",
		"Real Legendary catch (Акулёнок) from the winning tap: leap, landing, title, card beats, close, trophy replay — world FX under the HUD",
		{ Id = "SharkPup" },
		8
	),
	timelineScenario(
		"catch_timeline_common",
		"Real Common catch (Карасик) from the winning tap, world FX under the HUD",
		{ Id = "Crucian" },
		5.5
	),
	timelineScenario(
		"catch_timeline_mythic",
		"Real Mythic Rainbow catch (Рыба-дракон) from the winning tap, world FX under the HUD",
		{ Id = "DragonFish", Mutation = "Rainbow" },
		9
	),
	-- v3 [preview]: what a player sees in the 3D world around the HUD — the real posed avatar,
	-- the bent rod, the line from its tip, the held fish's flop, the shadow, ambient life.
	{
		name = "fishing_timeline",
		desc = "A whole real catch with the avatar (Epic Рыба-меч), from the tap «ЗАБРОСИТЬ»: wind-up and throw, the wait, the bite, the strike, the fight with the bent rod and the taut line, the winning tap, the leap, both arms up with the fish, the card",
		server = true,
		world = true,
		standard = false,
		still = { 0.25, 4.6 },
		timeline = { from = 0, to = 9.5, fps = 4 },
		worldView = { roi = { { frac = { 0.17, 0.06, 0.87, 0.94 } } } }, -- the fisher, rod, line, bobber
		burst = false,
		extraBeats = {
			{
				-- the release: the bobber leaves the tip at CastTime (FisherAnimController "Release")
				name = "throw",
				fn = function(h: any): boolean
					local castTime = h.player:GetAttribute("CastTime")
					return typeof(castTime) == "number" and h.sim:Time() >= castTime - 1e-3
				end,
			},
			{ name = "waiting", state = "Waiting" },
			{ name = "minigame", state = "Minigame" },
		},
		run = function(h: any)
			h:fixBiteDelay(2.6)
			h:readyReal({ Id = "Swordfish" })
		end,
		during = function(h: any)
			local mg = h:castAndHook()
			if mg then
				h:playMinigame(mg, { after = 0.9 })
			end
		end,
	},
	{
		name = "trophy_hold",
		desc = "After the card: the Legendary trophy over the head — it bobs and flops (FishLife), the nameplate beside it, both arms hold it up",
		server = true,
		world = true,
		standard = false,
		still = { 0.3, 1.5 },
		timeline = { from = 0, to = 3.2, fps = 5, roi = { { frac = { 0.25, 0.1, 0.78, 0.82 } } } },
		xray = false,
		burst = false,
		beats = { { name = "held gone", event = "HeldFish", kind = "disappear" } },
		run = function(h: any)
			h:playCatch({ Id = "SharkPup" })
			h:waitVisible("HUD.Fishing.CatchCard", 4)
			h:waitFor(function()
				return not h:shown("HUD.Fishing.CatchCard")
			end, 12)
			h:advance(0.4)
		end,
	},
	{
		name = "lost_fish",
		desc = "A lost fish: the Rare fight goes on, then a tap outside the zone — «МИМО!», the line flashes red and goes slack, the shadow flees, the fisher slumps and shakes his head",
		server = true,
		world = true,
		standard = false,
		still = { 0.5, 1.4 },
		timeline = { from = 0, to = 3.4, fps = 8, tail = 2.2 }, -- (the slump and head shake after the miss)
		worldView = { roi = { { frac = { 0.17, 0.1, 0.87, 0.94 } } } }, -- the panel hides the fisher
		burst = false,
		run = function(h: any)
			h:readyReal({ Id = "Puffer" })
			h.minigame = h:castAndHook()
		end,
		during = function(h: any)
			if h.minigame then
				h:playMinigame(h.minigame, { miss = true, after = 0.7 })
			end
		end,
	},
	{
		name = "ambient_pier",
		desc = "The living world from the pier tip, nothing else happening: a fish jumps, the pier gull swoops, schools under the surface, dragonflies, foam rings, swaying flags, the turning windmill",
		world = true,
		standard = false,
		still = { 2.0 },
		timeline = { from = 0, to = 6, fps = 4, tail = 6 },
		worldView = { cell = 700 }, -- (the same frames without the HUD: all the water in view)
		xray = false,
		burst = false,
		beats = {
			{
				name = "jump",
				fn = function(h: any): boolean
					local ambient = h:clientModule("AmbientController")
					return ambient ~= nil and ambient.Water.jumping ~= nil and ambient.Water.jumping ~= false
				end,
			},
			{
				name = "swoop",
				fn = function(h: any): boolean
					local ambient = h:clientModule("AmbientController")
					return ambient ~= nil and ambient.Critters.swooping == true
				end,
			},
		},
		run = function(h: any)
			h:standAtSpot()
			h:equipRod()
			h:poseLikeBackdrop()
			h:advance(2.5) -- the rod in hand, the Ready / Hold motion settled
			local ambient = h:clientModule("AmbientController")
			if ambient then
				h.sim:Run(function()
					ambient.SwoopSoon()
				end, h.player)
			end
		end,
		during = function(h: any)
			h:advance(1.2)
			local ambient = h:clientModule("AmbientController")
			if ambient then
				h.sim:Run(function()
					ambient.JumpSoon()
				end, h.player)
			end
			h:advance(6)
		end,
	},
}

--------------------------------------------------------------------------------
-- Scenario runner
--------------------------------------------------------------------------------

-- --check: this script's layout against RbxSim's AbsolutePosition/AbsoluteSize. They differ by
-- design under UIScale, Rotation and list/grid layouts with alignment (RbxSim ignores those).
local function checkLayout(sim: any, info: { [any]: any })
	local rows = {}
	local count = 0
	for inst, entry in info do
		local proxy = sim:Wrap(inst)
		local ok, pos = pcall(function()
			return proxy.AbsolutePosition
		end)
		if ok then
			local size = proxy.AbsoluteSize
			local r = entry.rect
			local x0, y0 = apply(entry.T, r.x, r.y)
			local w, h = r.w * entry.T.k, r.h * entry.T.k
			local d = math.max(math.abs(x0 - pos.X), math.abs(y0 - pos.Y), math.abs(w - size.X), math.abs(h - size.Y))
			count += 1
			if d > 0.5 then
				table.insert(rows, {
					d = d,
					text = string.format(
						"  %6.1f px  %s  ours (%.1f, %.1f %.1fx%.1f)  sim (%.1f, %.1f %.1fx%.1f)",
						d,
						inst:GetFullName(),
						x0,
						y0,
						w,
						h,
						pos.X,
						pos.Y,
						size.X,
						size.Y
					),
				})
			end
		end
	end
	table.sort(rows, function(a, b)
		return a.d > b.d
	end)
	print(`[gui_dump] --check: {count} objects compared, {#rows} differ by more than 0.5 px`)
	for i = 1, math.min(#rows, 12) do
		print(rows[i].text)
	end
end

-- Is the Roblox hotbar on (StarterGui:SetCoreGuiEnabled(Backpack / All, false) switches it off)?
local function hotbarOn(sim: any): boolean
	local states = sim.coreGui or {}
	return states[tostring(Enum.CoreGuiType.Backpack)] ~= false and states[tostring(Enum.CoreGuiType.All)] ~= false
end

-- Hotbar contents for the CoreGui overlay: Backpack tools, then the one in hand.
local function toolsOf(player: any): { any }
	local list = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	local seen = {}
	local function add(tool: any, equipped: boolean)
		if not seen[tool] then
			seen[tool] = true
			table.insert(list, { name = tool.Name, equipped = equipped })
		end
	end
	if character then
		for _, item in character:GetChildren() do
			if item:IsA("Tool") then
				add(item, true)
			end
		end
	end
	if backpack then
		for _, item in backpack:GetChildren() do
			if item:IsA("Tool") then
				add(item, false)
			end
		end
	end
	return list
end

local function writeJson(path: string, data: any)
	fs.writeFile(path, serde.encode("json", data, false))
end

local function allScenarios(): { any }
	local list = table.clone(scenarios)
	for _, s in BUILTIN do
		table.insert(list, s)
	end
	return list
end

local function scenarioByName(name: string): any
	for _, s in allScenarios() do
		if s.name == name then
			return s
		end
	end
	return nil
end

local function stillTimes(s: any, opts: any): { number }
	if opts.at then
		return opts.at
	end
	if type(s.still) == "table" then
		return s.still
	end
	return { s.still or DEFAULT_STILL }
end

local function windowTimes(spec: any): { number }
	local times = {}
	local n = math.floor((spec.to - spec.from) * spec.fps + 1e-6)
	for i = 0, n do
		table.insert(times, spec.from + i / spec.fps)
	end
	return times
end

local function sheetSpec(s: any, opts: any): any?
	local spec = s.sheet
	if opts.times then
		spec = {
			from = opts.times[1],
			to = opts.times[2],
			fps = opts.times[3],
			roi = spec and spec.roi or {},
			margin = spec and spec.margin,
		}
	end
	if not spec or not opts.sheets then
		return nil
	end
	return spec
end

-- The burst window: a scenario's own `burst`, else BURSTS (with --bursts); timelines always.
local function burstSpec(s: any, opts: any): any?
	local own = s.burst
	if own == false then
		return nil
	end
	if not (opts.bursts or s.timeline) then
		return nil
	end
	if own == nil and not BURSTS[s.name] then
		return nil
	end
	local spec = if type(own) == "table" then own else {}
	local roi = spec.roi or (s.sheet and s.sheet.roi) or {}
	return {
		from = spec.from or BURST_DEFAULT.from,
		to = spec.to or BURST_DEFAULT.to,
		fps = spec.fps or BURST_DEFAULT.fps,
		roi = roi,
		margin = spec.margin or (s.sheet and s.sheet.margin) or 0.04,
	}
end

local function main()
	local opts = parseArgs(process.args)
	if opts.list then
		for _, s in allScenarios() do
			local sheet = if s.sheet then `  sheet {s.sheet.from}..{s.sheet.to} s @ {s.sheet.fps} fps` else ""
			if s.timeline then
				sheet ..= `  timeline {s.timeline.from}..{s.timeline.to} s @ {s.timeline.fps} fps`
			end
			local flag = if s.standard == false then " (not standard)" else ""
			print(`{s.name}{string.rep(" ", math.max(1, 22 - #s.name))}{s.desc}{sheet}{flag}`)
		end
		return
	end
	assert(opts.out, "--out DIR is required")
	local device = DEVICES[opts.device]
	assert(device, `unknown device {opts.device} ({table.concat(DEVICE_ORDER, ", ")})`)
	local profile = SimPlayers.DEVICES[device.sim]
	local viewport = device.viewport or profile.viewport
	local vw, vh = viewport[1], viewport[2]
	local insets = device.insets
	if insets then
		SAFE = table.clone(insets)
	end
	installSafeArea()
	WorldCapture.installHooks()

	local names = opts.scenarios or { "all" }
	local selected = {}
	for _, name in names do
		if name == "all" then
			for _, s in allScenarios() do
				if s.standard ~= false then
					table.insert(selected, s)
				end
			end
		else
			local s = scenarioByName(name)
			assert(s, `unknown scenario {name} (try --list)`)
			table.insert(selected, s)
		end
	end

	local outDir = `{opts.out}/{opts.device}`
	if not fs.isDir(outDir) then
		fs.writeDir(outDir)
	end

	local started = os.clock()
	-- Two sims, made on first use: the stub one (FishingService off, the harness plays the
	-- server) and the real one (server = true scenarios).
	local sims: { [boolean]: any } = {}
	local previous: { [any]: any } = {}
	local function simFor(real: boolean): any
		local sim = sims[real]
		if sim then
			return sim
		end
		sim = Sim.new({ place = opts.place, verbose = opts.verbose })
		if not real then
			for _, name in STUBBED_SERVICES do
				local service = sim:Find(`ServerScriptService.Services.{name}`)
				if service then
					service.Source = "return {}"
				end
			end
		end
		-- Every scenario's player gets base 1 (one player at a time): the backdrop IS base 1's
		-- pier, and the world capture's movers / exclusion list are base 1's surroundings.
		local baseConfig = sim:Find("ReplicatedStorage.Shared.Config.BaseConfig")
		if baseConfig then
			baseConfig.Source =
				string.gsub(baseConfig.Source, "RandomAssignment%s*=%s*true", "RandomAssignment = false")
		end
		if next(fishByTitle) == nil then
			local fishRoot = sim:Find("ReplicatedStorage.Assets.Fish")
			if fishRoot then
				for _, folder in fishRoot:GetChildren() do
					for _, model in folder:GetChildren() do
						local title = model:GetAttribute("Title")
						if typeof(title) == "string" then
							fishByTitle[title] = folder.Name
						end
					end
				end
			end
		end
		sim:StartServer()
		sim:Advance(0.5)
		sims[real] = sim
		return sim
	end

	local userId = 0
	for _, s in selected do
		local t0 = os.clock()
		local sim = simFor(s.server == true)
		if previous[sim] then
			sim:RemovePlayer(previous[sim])
			sim:Advance(0.1)
		end
		sim:ClearErrors()
		userId += 1
		local player = sim:AddPlayer({
			UserId = 1000 + userId,
			Name = `Fisher{userId}`,
			DisplayName = "Рыбак",
			device = device.sim,
			viewport = roblox.Vector2.new(vw, vh),
			rig = "R15", -- FisherAnimController poses it; the world capture draws it
		})
		previous[sim] = player
		if insets then
			playerInsets[sim:Unwrap(player)] = insets
		end
		if s.server ~= true then
			-- The stub sim plays the stage 3 services: the data is loaded, an empty tank.
			for name, value in stage3Defaults(sim) do
				player:SetAttribute(name, value)
			end
		end
		local h = setmetatable({
			sim = sim,
			player = player,
			device = opts.device,
			touch = profile.TouchEnabled,
			scenario = s.name,
			server = s.server == true,
			warnings = {},
		}, Harness)
		if not s.fresh then
			h:waitFor(function()
				local index = player:GetAttribute("BaseIndex")
				return typeof(index) == "number"
					and index > 0
					and player.Character ~= nil
					and sim:Gui(player, "HUD") ~= nil
			end, 10)
			-- Let the welcome toast («Твоя база — …», 3.5 s + fade) go away; coarse steps are
			-- fine for tweens and timers and much cheaper.
			h:advance(s.settle or SETTLE, 1 / 8)
		else
			h:waitFor(function()
				return sim:Gui(player, "HUD") ~= nil
			end, 5)
		end

		-- The world capture: everything for `world = true`, else only the own avatar (drawn on
		-- the FishingSpot at the default camera; see gui/world_capture.luau).
		local capture = nil
		local spot, base = h:spot(), h:base()
		if spot and base then
			local ok, made = pcall(WorldCapture.new, {
				sim = sim,
				player = player,
				W = vw,
				H = vh,
				spot = spot,
				look = base:GetPivot().LookVector,
				dumpTree = dumpTree,
				fishByTitle = fishByTitle,
				mode = if s.world then "world" else "avatar",
				ambient = s.ambient ~= false,
			})
			if ok then
				capture = made
				if s.world then
					h.world = capture
				else
					h.avatarCapture = capture -- its follow camera is kept up during `run` too
				end
			else
				h:warn(`world capture failed to start: {made}`)
			end
		elseif s.world then
			h:warn("world = true, but the player has no base / FishingSpot: no world capture")
		end

		local stills = if opts.stills then stillTimes(s, opts) else {}
		local sheet = sheetSpec(s, opts)
		local burst = burstSpec(s, opts)
		local timeline = s.timeline
		local marks: { [number]: { [string]: boolean } } = {}
		local times = {}
		local function mark(t: number, key: string)
			local q = math.round(t * 1000) / 1000
			if not marks[q] then
				marks[q] = {}
				table.insert(times, q)
			end
			marks[q][key] = true
		end
		for _, t in stills do
			mark(t, "still")
		end
		for key, spec in { sheet = sheet, burst = burst, timeline = timeline } do
			if spec then
				for _, t in windowTimes(spec) do
					mark(t, key)
				end
			end
		end
		table.sort(times)

		local beatSpecs = s.beats
		if beatSpecs == nil and (burst or timeline or s.extraBeats) then
			beatSpecs = DEFAULT_BEATS
		end
		if beatSpecs and s.extraBeats then
			beatSpecs = table.clone(beatSpecs)
			for _, b in s.extraBeats do
				table.insert(beatSpecs, b)
			end
		end
		local beats = if beatSpecs then Beats.new(h, beatSpecs, capture) else nil

		local okRun, runErr = pcall(s.run, h)
		if not okRun then
			h:warn(`run failed: {runErr}`)
		end
		-- time 0 of the scenario
		if beats then
			beats:start()
		end
		if capture then
			pcall(capture.begin, capture)
		end
		-- `during`: the scenario keeps playing (taps, waits) while the frames are dumped — a
		-- coroutine whose every harness step (h:advance, h:click, h:waitFor …) is a step of
		-- this loop (see Harness:simStep).
		local during = nil
		if s.during then
			during = coroutine.create(function()
				s.during(h)
			end)
			h.yieldSteps = during
		end
		local pending = 0 -- seconds the `during` coroutine still waits for

		local playerGui = sim:Unwrap(player:FindFirstChildOfClass("PlayerGui"))
		local frames = {}
		local now = 0
		local function stepTo(target: number)
			while now < target - 1e-6 do
				if during and pending <= 1e-9 then
					local ok, request = coroutine.resume(during)
					if not ok then
						h:warn(`during failed: {request}`)
						during = nil
					elseif coroutine.status(during) == "dead" then
						during = nil
					else
						pending = tonumber(request) or FRAME
					end
				end
				local dt = math.min(FRAME, target - now)
				if pending > 1e-9 then
					dt = math.min(dt, pending)
				end
				sim:Step(dt)
				now += dt
				pending = math.max(0, pending - dt)
				h:syncToolPose()
				if capture then
					local ok, err = pcall(capture.step, capture, dt)
					if not ok then
						h:warn(`world capture failed: {err}`)
						capture = nil
					end
				end
				if beats then
					beats:step(now)
				end
			end
		end
		for _, t in times do
			stepTo(t)
			local objects, info = dumpPlayerGui(playerGui, vw, vh)
			if opts.check then
				checkLayout(sim, info)
			end
			local frame: { [string]: any } = {
				t = t,
				still = marks[t].still == true,
				sheet = marks[t].sheet == true,
				burst = marks[t].burst == true,
				timeline = marks[t].timeline == true,
				tools = toolsOf(player),
				hotbar = hotbarOn(sim),
				objects = objects,
			}
			if not capture and not s.world then
				-- (a fresh player gets the base during the scenario: the avatar from then on)
				local spotNow, baseNow = h:spot(), h:base()
				if spotNow and baseNow then
					local ok, made = pcall(WorldCapture.new, {
						sim = sim,
						player = player,
						W = vw,
						H = vh,
						spot = spotNow,
						look = baseNow:GetPivot().LookVector,
						dumpTree = dumpTree,
						fishByTitle = fishByTitle,
						mode = "avatar",
					})
					capture = if ok then made else nil
				end
			end
			if capture then
				local ok, world = pcall(capture.frame, capture)
				if ok then
					frame.world = world
				else
					h:warn(`world frame failed: {world}`)
				end
			elseif not s.world then
				frame.world = { solids = {} } -- no avatar yet: the backdrop without the stand-in
			end
			table.insert(frames, frame)
		end
		if beats and #times > 0 then
			-- a little past the last frame, so a beat right at the end still lands
			stepTo(now + 0.1)
		end
		h.yieldSteps = nil
		h:restoreBiteDelay() -- (the real sim is shared by the next server scenarios)

		local errors = {}
		for _, e in sim.Errors do
			table.insert(errors, `[{e.context}] {e.message}`)
		end
		for _, e in errors do
			print(`[gui_dump] {s.name}/{opts.device}: script error {e}`)
		end
		local warnings = h.warnings
		for _, w in sim.Warnings do
			table.insert(warnings, `[{w.context}] {w.message}`)
		end
		local function window(spec: any?): any?
			if not spec then
				return nil
			end
			return {
				from = spec.from,
				to = spec.to,
				fps = spec.fps,
				roi = spec.roi or {},
				margin = spec.margin or 0.04,
				tail = spec.tail,
			}
		end
		local worldView = nil
		if s.worldView then
			local spec = if type(s.worldView) == "table" then s.worldView else {}
			worldView = { roi = spec.roi or {}, margin = spec.margin or 0, cell = spec.cell }
		end
		writeJson(`{outDir}/{s.name}.json`, {
			version = 2,
			scenario = s.name,
			desc = s.desc,
			device = opts.device,
			viewport = { vw, vh },
			touch = profile.TouchEnabled,
			inset = INSET,
			safe = { SAFE.left, SAFE.right, SAFE.bottom },
			sheet = window(sheet),
			burst = window(burst),
			timeline = window(timeline),
			world_view = worldView,
			xray = s.xray ~= false,
			camera = if capture then capture:camera() else nil,
			scene = if capture then capture:scene() else nil,
			beats = if beats then beats:result() else nil,
			events = if capture then capture:eventList() else nil,
			frames = frames,
			errors = errors,
			warnings = warnings,
		})
		print(
			string.format(
				"[gui_dump] %-22s %-11s %3d frame(s)  %.1fs%s",
				s.name,
				opts.device,
				#frames,
				os.clock() - t0,
				if #errors > 0 then `  {#errors} script error(s)` else ""
			)
		)
	end
	print(string.format("[gui_dump] %d scenario(s) on %s in %.1fs", #selected, opts.device, os.clock() - started))
end

main()
