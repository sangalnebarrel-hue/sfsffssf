--[[
	gui_dump.luau — runs HUD scenarios in RbxSim and dumps the player's PlayerGui as JSON for
	tools/preview/gui_render.py (see tools/preview/README.md, section "GUI previews").

	Usage (Lune 0.11, from the repo root):
	  lune run tools/preview/gui_dump.luau --device phone --scenario bite,catch_mythic --out DIR
	  lune run tools/preview/gui_dump.luau --device desktop --scenario all --sheets --out DIR
	  lune run tools/preview/gui_dump.luau --list

	Options:
	  --device NAME      phone (844x390) | tablet (1024x768) | desktop (1280x720) | console
	  --scenario LIST    comma-separated names from gui_scenarios.luau, or "all" (the standard set)
	  --out DIR          writes DIR/<device>/<scenario>.json
	  --place FILE       default Place1.rbxl
	  --at T[,T...]      still times (seconds after the scenario's time 0) instead of its own
	  --sheets           also dump the scenario's animation-sheet frames (if it has a sheet)
	  --times A:B:FPS    sheet window override (implies --sheets for every scenario)
	  --no-stills        only sheet frames
	  --check            compare this script's layout with the sim's AbsolutePosition/AbsoluteSize
	  --verbose          echo script output (SIM_VERBOSE)

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
	Screen coordinates are real screen pixels: a ScreenGui that keeps the top-bar inset
	(IgnoreGuiInset false and ScreenInsets CoreUISafeInsets) starts at y = 58.
	Draw order: ScreenGuis by DisplayOrder; ZIndexBehavior Sibling: parent first, then
	children by ZIndex, ties in child order; Global: every object by ZIndex, ties in tree order.

	JSON (one file per device and scenario):
	  { version, scenario, desc, device, viewport = {W, H}, touch, inset, sheet = {...}|null,
	    frames = { { t, still, sheet, tools = { {name, equipped} }, objects = { <object>... } } },
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
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Sim = require("../sim")
local SimPlayers = require("../sim/players")
local scenarios = require("./gui_scenarios")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

local INSET = 58
local FRAME = 1 / 60
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

local function layerRect(gui: any, vw: number, vh: number): Rect
	if gui:IsA("ScreenGui") then
		local ignore = get(gui, "IgnoreGuiInset", false)
		local insets = get(gui, "ScreenInsets", Enum.ScreenInsets.CoreUISafeInsets)
		if ignore or insets == Enum.ScreenInsets.None or insets == Enum.ScreenInsets.DeviceSafeInsets then
			return { x = 0, y = 0, w = vw, h = vh }
		end
		if insets == Enum.ScreenInsets.TopbarSafeInsets then
			return { x = 0, y = 0, w = vw, h = INSET }
		end
	end
	return { x = 0, y = INSET, w = vw, h = vh - INSET }
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
		local gui = layer.gui
		local global = get(gui, "ZIndexBehavior", Enum.ZIndexBehavior.Sibling) == Enum.ZIndexBehavior.Global
		local entries: { Entry } = {}
		local counter = 0

		local function visit(parent: any, box: Rect, T: Xf, clip: { number }?, alpha: number)
			local rects = layoutChildren(parent, box)
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
				local path = pathOf(c, playerGui)
				table.insert(entries, {
					obj = describe(c, r, Tc, clip, a, path),
					z = kid.z,
					order = counter,
				})
				layoutInfo[c] = { rect = r, T = Tc }
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

		local root = layerRect(gui, vw, vh)
		-- A UIScale directly under a ScreenGui scales everything about its top-left corner.
		local rootScale = childOfClass(gui, "UIScale")
		local T0 = IDENTITY
		local box = contentBox(gui, root)
		if rootScale and get(rootScale, "Scale", 1) ~= 1 then
			local s = get(rootScale, "Scale", 1)
			T0 = scaleAbout(s, root.x, root.y)
			box = { x = box.x, y = box.y, w = box.w / s, h = box.h / s }
		end
		visit(gui, box, T0, nil, 1)
		if global then
			table.sort(entries, function(a, b)
				if a.z ~= b.z then
					return a.z < b.z
				end
				return a.order < b.order
			end)
		end
		for _, e in entries do
			table.insert(out, e.obj)
		end
	end
	return out, layoutInfo
end

--------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------

local Harness = {}
Harness.__index = Harness

function Harness:step(dt: number?)
	self.sim:Step(dt or FRAME)
end

function Harness:advance(seconds: number, step: number?)
	local dt = step or FRAME
	local n = math.floor(seconds / dt + 1e-6)
	for _ = 1, n do
		self.sim:Step(dt)
	end
	local rest = seconds - n * dt
	if rest > 1e-6 then
		self.sim:Step(rest)
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
		self.sim:Step(FRAME)
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
	self.sim:Step(FRAME)
end

function Harness:press()
	self.sim:PressKey(self.player, Enum.KeyCode.F)
	self.sim:Step(FRAME)
end

function Harness:serverSays(state: string, data: any?)
	self.sim:Find("ReplicatedStorage.Remotes.FishingState"):FireClient(self.player, state, data)
	self.sim:Step(FRAME)
end

function Harness:notify(text: string, kind: string?)
	self.sim:Find("ReplicatedStorage.Remotes.Notify"):FireClient(self.player, text, kind or "info")
	self.sim:Step(FRAME)
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

function Harness:caught(fish: { [string]: any }, total: number?)
	self:serverSays("Caught", { Fish = fish, Total = total or 1 })
end

--------------------------------------------------------------------------------
-- Scenario runner
--------------------------------------------------------------------------------

local function scenarioByName(name: string): any
	for _, s in scenarios do
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

local function sheetTimes(s: any, opts: any): ({ number }, any?)
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
		return {}, nil
	end
	local times = {}
	local n = math.floor((spec.to - spec.from) * spec.fps + 1e-6)
	for i = 0, n do
		table.insert(times, spec.from + i / spec.fps)
	end
	return times, spec
end

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

local function main()
	local opts = parseArgs(process.args)
	if opts.list then
		for _, s in scenarios do
			local sheet = if s.sheet then `  sheet {s.sheet.from}..{s.sheet.to} s @ {s.sheet.fps} fps` else ""
			local flag = if s.standard == false then " (not standard)" else ""
			print(`{s.name}{string.rep(" ", math.max(1, 20 - #s.name))}{s.desc}{sheet}{flag}`)
		end
		return
	end
	assert(opts.out, "--out DIR is required")
	local profile = SimPlayers.DEVICES[opts.device]
	assert(profile, `unknown device {opts.device}`)
	local vw, vh = profile.viewport[1], profile.viewport[2]

	local names = opts.scenarios or { "all" }
	local selected = {}
	for _, name in names do
		if name == "all" then
			for _, s in scenarios do
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
	local sim = Sim.new({ place = opts.place, verbose = opts.verbose })
	local fishingService = sim:Find("ServerScriptService.Services.FishingService")
	if fishingService then
		fishingService.Source = "return {}"
	end
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
	sim:StartServer()
	sim:Advance(0.5)

	local userId = 0
	local previous = nil
	for _, s in selected do
		local t0 = os.clock()
		if previous then
			sim:RemovePlayer(previous)
			sim:Advance(0.1)
		end
		sim:ClearErrors()
		userId += 1
		local player = sim:AddPlayer({
			UserId = 1000 + userId,
			Name = `Fisher{userId}`,
			DisplayName = "Рыбак",
			device = opts.device,
		})
		previous = player
		local h = setmetatable({
			sim = sim,
			player = player,
			device = opts.device,
			touch = profile.TouchEnabled,
			scenario = s.name,
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

		local okRun, runErr = pcall(s.run, h)
		if not okRun then
			h:warn(`run failed: {runErr}`)
		end

		local stills = if opts.stills then stillTimes(s, opts) else {}
		local sheet, spec = sheetTimes(s, opts)
		local marks: { [number]: { still: boolean, sheet: boolean } } = {}
		local times = {}
		local function mark(t: number, key: string)
			local q = math.round(t * 1000) / 1000
			if not marks[q] then
				marks[q] = { still = false, sheet = false }
				table.insert(times, q)
			end
			marks[q][key] = true
		end
		for _, t in stills do
			mark(t, "still")
		end
		for _, t in sheet do
			mark(t, "sheet")
		end
		table.sort(times)

		local playerGui = sim:Unwrap(player:FindFirstChildOfClass("PlayerGui"))
		local frames = {}
		local now = 0
		for _, t in times do
			if t > now then
				h:advance(t - now)
				now = t
			end
			local objects, info = dumpPlayerGui(playerGui, vw, vh)
			if opts.check then
				checkLayout(sim, info)
			end
			table.insert(frames, {
				t = t,
				still = marks[t].still,
				sheet = marks[t].sheet,
				tools = toolsOf(player),
				objects = objects,
			})
		end

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
		writeJson(`{outDir}/{s.name}.json`, {
			version = 1,
			scenario = s.name,
			desc = s.desc,
			device = opts.device,
			viewport = { vw, vh },
			touch = profile.TouchEnabled,
			inset = INSET,
			sheet = if spec
				then {
					from = spec.from,
					to = spec.to,
					fps = spec.fps,
					roi = spec.roi or {},
					margin = spec.margin or 0.04,
				}
				else nil,
			frames = frames,
			errors = errors,
			warnings = warnings,
		})
		print(
			string.format(
				"[gui_dump] %-20s %-8s %2d frame(s)  %.1fs%s",
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
