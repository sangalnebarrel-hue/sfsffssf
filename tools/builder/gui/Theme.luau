--[[
	Theme — the look of the HUD builders (tools/builder/gui/*): UI v5 «Симулятор», the juicy
	Roblox-simulator style of the user's reference (chunky saturated gradient buttons, a THICK
	outline in a dark shade of the button's own hue, a thin light rim inside it, bold white
	Montserrat Heavy text with a dark outline, outlined emoji icons, big italic numbers and huge
	outlined titles with no panel, translucent dark "glass" pills). No studs anywhere in the GUI:
	the LEGO look belongs to the map. Style guide and the full API: tools/builder/gui/STYLE.md.

	Colours, the font family and the shape numbers are NOT defined here: palette tokens, rarity
	and mutation styles, toast kinds, UIConfig.Font and UIConfig.Sim are read from
	src/ReplicatedStorage/Shared/Config/UIConfig.luau (a pure module), the same table the client
	(UiFx, controllers) uses at runtime.

	The "sim" anatomy (Theme.sim; UiFx.setCandy / faceOf / shine / press rely on it):
	  <Root>      any GuiObject, BackgroundTransparency 1; attributes CandyFace (the face's name,
	              "Face"; the base badge's is "Swatch"), CandyRadius, CandyStyle = "sim" | "glass"
	    Shadow    (opts.shadow) a soft Ink copy of the shape, a little lower, behind everything
	    Lip       the OUTLINE carrier: a full-size Frame that draws no fill (BackgroundColor3 =
	              the swatch's Lip, kept for readers), UICorner, UIStroke (Border, Round joins,
	              the Lip colour = the dark shade of the hue, BaseThickness UIConfig.Sim.Stroke)
	    Face      full size, white + UIGradient "Fill" (Rotation 90, Top → Bottom), UICorner
	      Gloss   (opts.gloss) a soft white highlight in the top half
	      Rim     the thin light rim just inside the outline (UIStroke, BorderStrokePosition Inner,
	              white at UIConfig.Sim.RimAlpha)
	      Shine   a hidden full-size overlay with a transparent UIGradient "Band" (UiFx.shine)
	    …content  Icon / Caption / Label at SZ.Content; overlays SZ.Overlay; text over them SZ.Top
	"glass" (Theme.glass, the reference's timer pill) is the same tree with a black face at
	UIConfig.Palette.Glass.Alpha transparency, the outline and the rim hidden; UiFx.setCandy turns
	a root between the two looks (a bright token → a solid sim plate, Glass → glass).

	Text: Montserrat Heavy (900), white with a dark Ink outline (UIStroke "Outline", Contextual);
	Italic = true (numbers, hints, floats) uses Montserrat Heavy Italic; a tiered label (Tier =
	"Title" | "Button" | "Body" | "Small", attribute TextTier; UiFx.fitText sizes it on the real
	screen) gets at least its tier's outline (TIER_OUTLINE). Shadow = true adds a darker twin
	"<Name>Shadow" a little lower (a sibling: with ZIndexBehavior Sibling a child would draw over
	its parent; UiFx keeps the twin in step).

	Compat (UI v3/v4 names that tools/builder/gui/Fishing.luau still calls until the fishing waves
	restyle it): brick / tile / roundPlate build sim plates (a dark tile becomes glass), topStud and
	studRow build NOTHING (they return a detached empty frame), studScale is 1, candyButton / pill /
	socket build the sim button / plate / a transparent icon holder; BZ = SZ, BRICK = the shape
	numbers with no side band (Lip 0).
]]

local U = require("../Util")

local Enum = U.Enum
local UDim = U.UDim
local UDim2 = U.UDim2
local Vector2 = U.Vector2
local roblox = U.roblox
local Color3 = roblox.Color3
local ColorSequence = roblox.ColorSequence
local ColorSequenceKeypoint = roblox.ColorSequenceKeypoint
local NumberSequence = roblox.NumberSequence
local NumberSequenceKeypoint = roblox.NumberSequenceKeypoint

-- The shared palette (same numbers as the client). Paths are relative to the repo root, like build.luau.
local UI = U.loadPure("src/ReplicatedStorage/Shared/Config/UIConfig.luau")

-- The UI font: Montserrat Heavy (900; Cyrillic) and its italic. The map's signs keep Util.FONT.
local FONT = roblox.Font.new(UI.Font.Family, Enum.FontWeight.Heavy)
local FONT_ITALIC = roblox.Font.new(UI.Font.Family, Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local MIN_TEXT = 12 -- never let TextScaled shrink text below this on phones
-- Pixels reserved at the screen bottom for the Roblox hotbar under the fishing widgets: 0 since
-- v3 — HudController switches the Backpack CoreGui off (the rod is taken with «ВЗЯТЬ»; a custom
-- hotbar comes with the shop stage). The widgets keep 16 px to the screen bottom (Gui.luau).
local HOTBAR = 0

local SIM = UI.Sim
local INK = UI.Ink
local WHITE = UI.White
local P = UI.Palette
-- Type scale: text size per tier in px at a 390 px tall screen (UiFx.fitText scales it up).
local TYPE = UI.Type
-- Outlines at 720 px (UiFx.fitStrokes: a phone gets ≈ 0.65 of it, text never under 2 px).
local STROKE = SIM.Stroke -- the shape outline of buttons and plates
local MINOR = SIM.MinorStroke -- chips, zone, needle, pips, the badge
-- Text outline per tier at 720 px (a tiered label gets at least this): ≈ 0.12 of the cap height,
-- like the reference's labels.
local TIER_OUTLINE = { Title = 3.5, Button = 3, Body = 2.5, Small = 2.5 }
local DISPLAY_OUTLINE = 4.5 -- big numbers and words (counter, price, «КЛЮЁТ!», floats)
local TITLE_OUTLINE = 8 -- the giant outlined titles (base banner name, rarity title)
local ICON_OUTLINE = 3 -- the Ink contour around emoji icons

-- ZIndex layers inside a sim root (ZIndexBehavior.Sibling: they only order siblings).
local SZ = {
	Behind = 0, -- the shadow, glow rings, rays (UiFx)
	Lip = 1, -- the outline
	Face = 2,
	Content = 3, -- icons, captions, labels
	Overlay = 5, -- cooldowns, locks
	Top = 6, -- text over overlays
}

-- Compat: the v3/v4 brick numbers Fishing.luau still reads (a sim face covers its root: no band).
local BRICK = {
	Lip = 0,
	TileLip = 0,
	Radius = SIM.Radius,
	TileRadius = SIM.PlateRadius,
	CapStop = UI.Brick.CapStop,
}

--------------------------------------------------------------------------------
-- Sequences, colours and gradients
--------------------------------------------------------------------------------

-- ColorSequence through the colours, evenly spaced (one colour → flat).
local function sequence(colors: { any }): any
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local points = {}
	for i, color in colors do
		table.insert(points, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(points)
end

-- NumberSequence from { {time, value}, ... }.
local function numbers(points: { { number } }): any
	local keypoints = {}
	for _, point in points do
		table.insert(keypoints, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keypoints)
end

local function lighten(color: any, k: number): any
	return color:Lerp(Color3.new(1, 1, 1), k)
end

local function darken(color: any, k: number): any
	return Color3.new(color.R * (1 - k), color.G * (1 - k), color.B * (1 - k))
end

-- Vertical gradient (light top → saturated bottom). Rotation 90 = top to bottom.
local function gradient(parent: any, top: any, bottom: any, rotation: number?, name: string?): any
	return U.new("UIGradient", {
		Name = name or "Fill",
		Color = ColorSequence.new(top, bottom),
		Rotation = rotation or 90,
	}, parent)
end

-- Gradient through several colours (rainbows, countdown bars).
local function multiGradient(parent: any, colors: { any }, rotation: number?, name: string?): any
	return U.new("UIGradient", {
		Name = name or "Fill",
		Color = sequence(colors),
		Rotation = rotation or 0,
	}, parent)
end

-- Resolves a look: a palette token name or a { Top, Bottom, Lip } table.
local function swatch(token: any): any
	if type(token) == "string" then
		local found = P[token]
		assert(found, `Theme: unknown palette token {token}`)
		return found
	end
	return token
end

-- A dark look (Night, Coal, Glass): a smooth tile in it becomes glass.
local function isDark(look: any): boolean
	local _, _, v = look.Top:ToHSV()
	return look.Alpha ~= nil or v < 0.42
end

--------------------------------------------------------------------------------
-- Small constructors
--------------------------------------------------------------------------------

local function corner(parent: any, scale: number)
	return U.new("UICorner", { CornerRadius = UDim.new(scale, 0) }, parent)
end

-- An outline (Ink by default). BaseThickness lets UiFx.fitStrokes scale it to the screen height.
local function stroke(parent: any, thickness: number, transparency: number?, color: any?)
	return U.new("UIStroke", {
		Color = color or INK,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Attributes = { BaseThickness = thickness },
	}, parent)
end

-- A dark contour around a label's glyphs (text or emoji): UIStroke "Outline", Contextual.
local function outline(parent: any, thickness: number, color: any?, transparency: number?): any
	return U.new("UIStroke", {
		Name = "Outline",
		Color = color or INK,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Attributes = { BaseThickness = thickness },
	}, parent)
end

--[[
	Text label: white Montserrat Heavy with a dark Ink outline, TextScaled.
	Extra keys (not Roblox properties):
	  Tier = "Title" | "Button" | "Body" | "Small" — the type scale (TYPE): attribute TextTier and a
	                            UITextSizeConstraint Max = TYPE[Tier], Min = Max - 2 (phone values;
	                            UiFx.fitText rescales them for the real screen). Wins over Max/MinTextSize.
	                            Give the label a box at least that tall and wide enough for its text.
	                            A tiered label is outlined at least TIER_OUTLINE[Tier] (unless
	                            Outline = false or TextStrokeTransparency = 1: dark text on a white chip);
	  MaxTextSize / MinTextSize — UITextSizeConstraint (MinTextSize defaults to 12 when MaxTextSize is set);
	  Outline = px            — the UIStroke "Outline" on the glyphs (Contextual) instead of TextStroke;
	  OutlineColor            — its colour (default Ink);
	  TextGradient = {a, b, …} — a vertical UIGradient "TextFill" on the text (white → gold …);
	  Italic = true           — Montserrat Heavy Italic (numbers, hints, floats);
	  Shadow = true           — a darker twin "<Name>Shadow" (a sibling) a little lower: the
	                            reference title's drop shadow.
]]
local function label(parent: any, name: string, props: { [string]: any }): any
	local base: { [string]: any } = {
		Name = name,
		BackgroundTransparency = 1,
		TextScaled = true,
		FontFace = FONT,
		TextColor3 = WHITE,
		TextStrokeColor3 = INK,
		TextStrokeTransparency = 0,
	}
	for key, value in props do
		base[key] = value
	end
	local tier = base.Tier
	local maxText = base.MaxTextSize
	local minText = base.MinTextSize or MIN_TEXT
	local thickness = base.Outline
	local outlineColor = base.OutlineColor
	local textGradient = base.TextGradient
	local italic = base.Italic
	local shadow = base.Shadow
	for _, key in
		{ "Tier", "MaxTextSize", "MinTextSize", "Outline", "OutlineColor", "TextGradient", "Italic", "Shadow" }
	do
		base[key] = nil
	end
	if italic then
		base.FontFace = FONT_ITALIC
	end
	if tier then
		assert(TYPE[tier], `Theme.label: unknown text tier {tier}`)
		maxText = TYPE[tier]
		minText = TYPE[tier] - 2
		if thickness ~= false and props.TextStrokeTransparency ~= 1 and TIER_OUTLINE[tier] then
			thickness = math.max(if type(thickness) == "number" then thickness else 0, TIER_OUTLINE[tier])
		end
	end
	if thickness and props.TextStrokeTransparency == nil then
		base.TextStrokeTransparency = 1 -- the UIStroke draws the outline
	end
	local inst = U.new("TextLabel", base, parent)
	if tier then
		inst:SetAttribute("TextTier", tier)
	end
	if maxText then
		U.new("UITextSizeConstraint", { MaxTextSize = maxText, MinTextSize = minText }, inst)
	end
	if thickness then
		outline(inst, thickness, outlineColor)
	end
	if textGradient then
		U.new("UIGradient", { Name = "TextFill", Color = sequence(textGradient), Rotation = 90 }, inst)
	end
	if shadow then
		-- The drop shadow: the same text in Ink a little lower, under the label (ZIndex − 1).
		local twin = inst:Clone()
		twin.Name = `{name}Shadow`
		twin.TextColor3 = INK
		twin.TextTransparency = 0.35
		twin.ZIndex = math.max(inst.ZIndex - 1, 0)
		twin.Active = false
		local size = inst.Size
		twin.Position = inst.Position + UDim2.new(0, 0, size.Y.Scale * 0.07, math.round(size.Y.Offset * 0.07))
		local fill = twin:FindFirstChild("TextFill")
		if fill then
			fill:Destroy()
		end
		local edge = twin:FindFirstChild("Outline")
		if edge then
			edge.Transparency = 0.35
		end
		twin:SetAttribute("TextTier", nil)
		twin:SetAttribute("ShadowOf", name)
		twin.Parent = parent
	end
	return inst
end

--[[
	Emoji icon: its own label, upright (Rotation 0 unless given), with a dark Ink contour around the
	emoji's shape (Outline = px at 720, default 3; false = none) — the reference's black-outlined
	icons. A faint glyph (TextTransparency > 0) gets no contour. (Sticker = the v3 key, read as
	Outline.)
]]
local function icon(parent: any, name: string, emoji: string, props: { [string]: any }?): any
	local base: { [string]: any } = {
		Text = emoji,
		TextStrokeTransparency = 1,
		Rotation = 0,
		ZIndex = SZ.Content,
	}
	local contour: any = nil
	for key, value in props or {} do
		if key == "Outline" or key == "Sticker" then
			contour = value
		else
			base[key] = value
		end
	end
	if contour == nil then
		contour = if (base.TextTransparency or 0) > 0 then false else ICON_OUTLINE
	elseif contour == true then
		contour = ICON_OUTLINE
	end
	local inst = label(parent, name, base)
	if contour then
		outline(inst, contour)
	end
	return inst
end

-- Overlay swept by UiFx.shine. Hidden (Visible = false: no full-size quad rasterised every frame)
-- until UiFx.shine shows it for the sweep; the band also waits out of sight (Offset.X = -1).
local function shine(face: any, radius: number): any
	local frame = U.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
		Visible = false,
	}, face)
	corner(frame, radius)
	U.new("UIGradient", {
		Name = "Band",
		Rotation = 20,
		Offset = Vector2.new(-1, 0),
		Transparency = numbers({
			{ 0, 1 },
			{ 0.36, 1 },
			{ 0.45, 0.55 },
			{ 0.5, 0.25 },
			{ 0.55, 0.55 },
			{ 0.64, 1 },
			{ 1, 1 },
		}),
	}, frame)
	return frame
end

-- Glass or solid: the same tree, two looks (UiFx.setCandy does the same at runtime).
local function applyLook(root: any, look: any)
	local face = root:FindFirstChild(root:GetAttribute("CandyFace") or "Face")
	local lip = root:FindFirstChild("Lip")
	local edge = lip and lip:FindFirstChildOfClass("UIStroke")
	local rim = face and face:FindFirstChild("Rim")
	local rimStroke = rim and rim:FindFirstChildOfClass("UIStroke")
	local glass = look.Alpha ~= nil
	if face then
		face.BackgroundTransparency = if glass then look.Alpha else 0
		local fill = face:FindFirstChild("Fill")
		if fill then
			fill.Color = ColorSequence.new(look.Top, look.Bottom)
		end
	end
	if lip then
		lip.BackgroundColor3 = look.Lip
	end
	if edge then
		edge.Color = look.Lip
		edge.Transparency = if glass then 1 else 0
	end
	if rimStroke then
		rimStroke.Transparency = if glass then 1 else SIM.RimAlpha
	end
	root:SetAttribute("CandyStyle", if glass then "glass" else "sim")
end

--[[
	Turns `root` into a sim surface (see the header) and returns the face.
	token: a palette token name ("Leaf") or { Top, Bottom, Lip [, Alpha] }; ignored when opts.color
	is set. opts:
	  radius        UICorner scale (default UIConfig.Sim.Radius: buttons and panels)
	  round         true → 0.5 (round buttons, pips, the badge)
	  stroke        the outline px at 720 (default UIConfig.Sim.Stroke; 0 = none)
	  rim           false: no light rim; or its px at 720 (default UIConfig.Sim.Rim)
	  color         a runtime colour instead of the token: the swatch UIConfig.swatchFor(color)
	  faceName      name of the face (default "Face"; the base badge calls it "Swatch")
	  shine         false: no Shine overlay
	  gloss         true: a soft white highlight in the top half of the face
	  shadow        true: a soft Ink drop shadow under the shape
	  transparency  BackgroundTransparency of the face (a glass look sets its own)
	  z             ZIndex of the Lip (face = z + 1; content at SZ.Content or higher)
]]
local function sim(root: any, token: any, opts: { [string]: any }?): any
	local o = opts or {}
	local radius = if o.round then 0.5 else (o.radius or SIM.Radius)
	local z = o.z or SZ.Lip
	local faceName = o.faceName or "Face"
	local look = if o.color then UI.swatchFor(o.color) else swatch(token)
	local thickness = if o.stroke == nil then STROKE else o.stroke

	root.BackgroundTransparency = 1
	root:SetAttribute("CandyFace", faceName)
	root:SetAttribute("CandyRadius", radius)
	root:SetAttribute("CandyStyle", "sim")

	if o.shadow then
		local drop = U.new("Frame", {
			Name = "Shadow",
			BackgroundColor3 = INK,
			BackgroundTransparency = SIM.ShadowAlpha,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, SIM.ShadowY),
			Size = UDim2.fromScale(1, 1),
			ZIndex = math.max(z - 1, 0),
			Active = false,
		}, root)
		corner(drop, radius)
		if thickness > 0 then
			stroke(drop, thickness, SIM.ShadowAlpha)
		end
	end
	local lip = U.new("Frame", {
		Name = "Lip",
		BackgroundColor3 = look.Lip,
		BackgroundTransparency = 1, -- the outline only: no fill under the face
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, root)
	corner(lip, radius)
	if thickness > 0 then
		stroke(lip, thickness, 0, look.Lip)
	end

	local face = U.new("Frame", {
		Name = faceName,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = o.transparency or 0,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z + 1,
	}, root)
	corner(face, radius)
	gradient(face, look.Top, look.Bottom)
	if o.gloss then
		local glossy = U.new("Frame", {
			Name = "Gloss",
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, if o.round then 0.07 else 0.08),
			Size = UDim2.fromScale(if o.round then 0.62 else 0.92, if o.round then 0.4 else 0.44),
			ZIndex = 1,
		}, face)
		corner(glossy, if o.round then 0.5 else math.min(0.5, radius * 2))
		U.new("UIGradient", {
			Name = "Fade",
			Rotation = 90,
			Transparency = numbers({ { 0, SIM.Gloss }, { 1, 1 } }),
		}, glossy)
	end
	local rimPx = if o.rim == false then 0 elseif type(o.rim) == "number" then o.rim else SIM.Rim
	if rimPx > 0 then
		local rim = U.new("Frame", {
			Name = "Rim",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 2,
			Active = false,
		}, face)
		corner(rim, radius)
		local ring = stroke(rim, rimPx, SIM.RimAlpha, WHITE)
		ring.BorderStrokePosition = Enum.BorderStrokePosition.Inner
	end
	if o.shine ~= false then
		shine(face, radius)
	end
	if look.Alpha ~= nil then
		applyLook(root, look)
	end
	return face
end

--[[
	The translucent dark pill of the reference's timer (hints, the action caption, grooves):
	Theme.sim in the Glass look (a black face at UIConfig.Palette.Glass.Alpha, no outline, no rim).
	opts as sim, plus alpha (the face's transparency) and edge (px at 720: a faint Ink outline —
	grooves cut into a panel; default none). Returns the face.
]]
local function glass(root: any, opts: { [string]: any }?): any
	local o = opts or {}
	local look = P.Glass
	if o.alpha then
		look = { Top = P.Glass.Top, Bottom = P.Glass.Bottom, Lip = P.Glass.Lip, Alpha = o.alpha }
	end
	local simOpts: { [string]: any } = { radius = o.radius or 0.5, shine = o.shine, z = o.z, stroke = o.edge or STROKE }
	local face = sim(root, look, simOpts)
	root:SetAttribute("CandyHome", "glass") -- (UiFx.setCandy: dark tokens keep it glass)
	if o.edge then
		local edge = root.Lip:FindFirstChildOfClass("UIStroke")
		edge.Color = INK
		edge.Transparency = o.edgeAlpha or 0.4
	end
	return face
end

--[[
	Sim TextButton with an Icon and / or a Caption, ready for UiFx.press / hover / shine / glowRing.
	props: any TextButton properties (Size, Position, AnchorPoint, LayoutOrder, Visible, …) plus
	  Layout   "row"    — the icon at the left end, the caption filling the rest («🛒 Магазин»);
	           "square" — the icon big in the middle, the caption ON the bottom edge (Home);
	           "round"  — a round button, the icon in the middle (captions are added by the caller);
	           "stack"  — the v3 layout: icon over caption on the face (default)
	  Icon (emoji), Caption (text), Tier (caption text tier), Radius, Square (UIAspectRatioConstraint 1),
	  MaxTextSize / MinTextSize (a caption without a Tier), SimOpts (extra Theme.sim opts),
	  Brick / CandyOpts (v3 keys: accepted, the studs ignored).
]]
local function simButton(parent: any, name: string, token: any, props: { [string]: any }): any
	local base: { [string]: any } = {
		Name = name,
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
	}
	local special = {
		Icon = true,
		Caption = true,
		Layout = true,
		Radius = true,
		Square = true,
		Tier = true,
		MaxTextSize = true,
		MinTextSize = true,
		SimOpts = true,
		CandyOpts = true,
		Brick = true,
	}
	for key, value in props do
		if not special[key] then
			base[key] = value
		end
	end
	local button = U.new("TextButton", base, parent)
	local layout = props.Layout or "stack"
	if props.Square or layout == "square" then
		U.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, button)
	end
	local simOpts: { [string]: any } = {
		radius = props.Radius,
		round = layout == "round",
	}
	for key, value in props.SimOpts or {} do
		simOpts[key] = value
	end
	if type(props.Brick) == "table" then
		simOpts.radius = props.Brick.radius or simOpts.radius
		simOpts.color = props.Brick.color
	end
	sim(button, token, simOpts)

	if layout == "row" then
		if props.Icon then
			icon(button, "Icon", props.Icon, {
				SizeConstraint = Enum.SizeConstraint.RelativeYY,
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0.05, 0.5),
				Size = UDim2.fromScale(0.78, 0.78),
				ZIndex = SZ.Content,
			})
		end
		if props.Caption then
			label(button, "Caption", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(0.95, 0.5),
				Size = UDim2.fromScale(if props.Icon then 0.66 else 0.88, 0.62),
				Text = props.Caption,
				ZIndex = SZ.Content,
				Tier = props.Tier,
				MaxTextSize = props.MaxTextSize or 26,
				MinTextSize = props.MinTextSize or MIN_TEXT,
			})
		end
	elseif layout == "square" or layout == "round" then
		if props.Icon then
			icon(button, "Icon", props.Icon, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, if props.Caption then 0.42 else 0.5),
				Size = UDim2.fromScale(0.62, 0.62),
				ZIndex = SZ.Content,
			})
		end
		if props.Caption then
			label(button, "Caption", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.86),
				Size = UDim2.fromScale(1.04, 0.28),
				Text = props.Caption,
				ZIndex = SZ.Content + 1,
				Tier = props.Tier,
				MaxTextSize = props.MaxTextSize or 24,
				MinTextSize = props.MinTextSize or MIN_TEXT,
			})
		end
	else
		if props.Icon then
			icon(button, "Icon", props.Icon, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, 0.38),
				Size = UDim2.fromScale(0.62, 0.56),
				ZIndex = SZ.Content,
			})
		end
		if props.Caption then
			label(button, "Caption", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, if props.Icon then 0.8 else 0.5),
				Size = UDim2.fromScale(0.9, if props.Icon then 0.28 else 0.6),
				Text = props.Caption,
				ZIndex = SZ.Content,
				Tier = props.Tier,
				MaxTextSize = props.MaxTextSize or 24,
				MinTextSize = props.MinTextSize or MIN_TEXT,
			})
		end
	end
	return button
end

--[[
	A transparent holder for an outlined emoji that overhangs a plate (the base flag, toast and
	hint icons, the trophy chip): a Frame (SizeConstraint RelativeYY, no fill) with the "Icon"
	filling it. emoji "" = an empty holder. props: Frame properties plus IconName (default
	"Icon"), IconOutline (px at 720, default 3).
]]
local function socket(parent: any, name: string, emoji: string, props: { [string]: any }?): any
	local base: { [string]: any } = {
		Name = name,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = SZ.Content,
	}
	local iconName, contour = "Icon", ICON_OUTLINE
	for key, value in props or {} do
		if key == "IconName" then
			iconName = value
		elseif key == "IconOutline" then
			contour = value
		else
			base[key] = value
		end
	end
	local frame = U.new("Frame", base, parent)
	if emoji ~= "" then
		icon(frame, iconName, emoji, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.92, 0.92),
			ZIndex = 2,
			Outline = contour,
		})
	end
	return frame
end

--[[
	A sim plate (Frame) with an outlined emoji overhanging its left end and a Label: badges,
	toasts, chips. props: Frame properties plus
	  Icon (emoji), IconScale (the icon's size as a share of the plate height, default 1.15),
	  Socket (true → the icon sits in a transparent holder "IconSocket"; else a direct "Icon"),
	  Text, Tier, Italic, MaxTextSize, LabelProps (extra Label properties), Radius (default
	  UIConfig.Sim.PlateRadius), Glass (true → a glass pill), Color (a runtime colour),
	  SimOpts (extra Theme.sim opts); the v3 keys Brick / CandyOpts are accepted.
]]
local function plate(parent: any, name: string, token: any, props: { [string]: any }): any
	local base: { [string]: any } = { Name = name, BackgroundTransparency = 1 }
	local special = {
		Icon = true,
		IconScale = true,
		Text = true,
		Tier = true,
		Italic = true,
		MaxTextSize = true,
		Socket = true,
		Color = true,
		Radius = true,
		Glass = true,
		SimOpts = true,
		CandyOpts = true,
		LabelProps = true,
		Brick = true,
	}
	for key, value in props do
		if not special[key] then
			base[key] = value
		end
	end
	local frame = U.new("Frame", base, parent)
	local brickOpts = if type(props.Brick) == "table" then props.Brick else {}
	local radius = props.Radius or brickOpts.radius or SIM.PlateRadius
	if props.Glass then
		glass(frame, { radius = radius })
	else
		local simOpts: { [string]: any } = { radius = radius, color = props.Color or brickOpts.color }
		for key, value in props.SimOpts or {} do
			simOpts[key] = value
		end
		sim(frame, token, simOpts)
	end
	local iconScale = props.IconScale or 1.15
	if props.Icon then
		if props.Socket then
			socket(frame, "IconSocket", props.Icon, {
				AnchorPoint = Vector2.new(0.3, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromScale(iconScale, iconScale),
				ZIndex = SZ.Content,
			})
		else
			icon(frame, "Icon", props.Icon, {
				SizeConstraint = Enum.SizeConstraint.RelativeYY,
				AnchorPoint = Vector2.new(0.32, 0.5),
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromScale(iconScale, iconScale),
				ZIndex = SZ.Content,
			})
		end
	end
	if props.Text then
		local labelProps: { [string]: any } = {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.95, 0.5),
			Size = UDim2.fromScale(if props.Icon then 0.76 else 0.9, 0.66),
			Text = props.Text,
			ZIndex = SZ.Content,
			Tier = props.Tier,
			Italic = props.Italic,
			MaxTextSize = props.MaxTextSize or 28,
		}
		for key, value in props.LabelProps or {} do
			labelProps[key] = value
		end
		label(frame, "Label", labelProps)
	end
	return frame
end

--[[
	The red «!» notification badge of the reference (a disc on a button's top-right corner):
	a round BadgeRed sim disc (outline 3 at 720, a thin rim) with a white «!». Hidden by default
	(UiFx.badgeBob pops it in and bobs it). props: Frame properties (default: centred on the
	host's top-right corner, half the host's height, at least 22 px).
]]
local function badge(parent: any, name: string?, props: { [string]: any }?): any
	local base: { [string]: any } = {
		Name = name or "Badge",
		Visible = false,
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.91, 0.16),
		Size = UDim2.fromScale(0.5, 0.5),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = SZ.Top + 1,
	}
	for key, value in props or {} do
		base[key] = value
	end
	local frame = U.new("Frame", base, parent)
	U.new("UISizeConstraint", { MinSize = Vector2.new(22, 22) }, frame)
	sim(frame, UI.BadgeRed, { round = true, stroke = 3, rim = 1.5, shine = false })
	label(frame, "Mark", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		Text = "!",
		Outline = 2.5,
		ZIndex = SZ.Content,
		MaxTextSize = 40,
		MinTextSize = MIN_TEXT, -- (the disc is ≥ 22 px: a 12 px «!» always fits)
	})
	return frame
end

--[[
	A panel-less stat like the reference's «👟 10» / «💵 $0»: a transparent Frame with an outlined
	emoji "Icon" on the left and a big italic white number "Label" (display outline, TextFill white
	→ white: HudController tints it). props: Frame properties plus Text, IconScale (1.2 of the
	height), MaxTextSize (48), MinTextSize (16), Color (the number's colour, default white).
]]
local function stat(parent: any, name: string, emoji: string, props: { [string]: any }): any
	local base: { [string]: any } = { Name = name, BackgroundTransparency = 1 }
	local special = { Text = true, IconScale = true, MaxTextSize = true, MinTextSize = true, Color = true }
	for key, value in props do
		if not special[key] then
			base[key] = value
		end
	end
	local frame = U.new("Frame", base, parent)
	local scale = props.IconScale or 1.2
	local glyph = icon(frame, "Icon", emoji, {
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.14, 0.5),
		Size = UDim2.fromScale(scale, scale),
		Rotation = -8,
		ZIndex = SZ.Content + 1,
	})
	corner(glyph, 0.5) -- (glow rings around the icon are round)
	label(frame, "Label", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.3, 0.5),
		Size = UDim2.fromScale(0.7, 1.05),
		Text = props.Text or "0",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = props.Color or WHITE,
		Italic = true,
		Outline = DISPLAY_OUTLINE,
		TextGradient = { WHITE, WHITE },
		ZIndex = SZ.Content,
		MaxTextSize = props.MaxTextSize or 48,
		MinTextSize = props.MinTextSize or 16,
	})
	return frame
end

--[[
	A huge outlined title with no panel («Украдите яйцо!» of the reference; the base banner's name,
	the rarity title): white (TextGradient = colours: a vertical TextFill), a thick Ink outline
	(Outline, default 8 at 720) and the drop-shadow twin. props: label properties.
]]
local function title(parent: any, name: string, props: { [string]: any }): any
	local base: { [string]: any } = {
		Outline = TITLE_OUTLINE,
		Shadow = true,
		MaxTextSize = 72,
		MinTextSize = 14,
	}
	for key, value in props do
		base[key] = value
	end
	return label(parent, name, base)
end

-- Gradient in the rarity's colours; Mythic gets rainbow keypoints (animate with UiFx.rainbow).
local function rarityGradient(parent: any, rarityId: string, rotation: number?): any
	local style = UI.Rarity[rarityId] or UI.Rarity.Common
	if style.Rainbow then
		local g = multiGradient(parent, UI.Rainbow, rotation or 0, "Fill")
		g:SetAttribute("Rainbow", true)
		return g
	end
	return gradient(parent, style.Top, style.Bottom, rotation or 90, "Fill")
end

--------------------------------------------------------------------------------
-- Compat: the v3 / v4 brick API that tools/builder/gui/Fishing.luau still calls. Every one of
-- them builds the sim look (no studs); the fishing waves replace the calls with sim / glass /
-- simButton / plate and then these go.
--------------------------------------------------------------------------------

-- Outline weights of the compat shapes: the big ones (the action disc, «СМОТАТЬ», the bite and
-- minigame panels, the catch card and its banner) get the chrome's chunky UIConfig.Sim.Stroke —
-- the most important button is the chunkiest, as in the reference (SIM-C1-03); the small ones
-- (tiles, chips, pills: the key chip, the price and weight chips, «НОВИНКА!») the minor outline.
local COMPAT_STROKE = MINOR

-- v3 brick / tile → a sim plate (studs, spec, lip ignored); a dark smooth tile → glass.
local function brick(root: any, token: any, opts: { [string]: any }?): any
	local o = opts or {}
	local tile = o.tile == true
	local look = if o.color then UI.swatchFor(o.color) else swatch(token)
	local radius = o.radius or (if tile then SIM.PlateRadius else SIM.Radius)
	if tile and isDark(look) then
		return glass(root, { radius = radius, shine = o.shine, z = o.z })
	end
	local thickness = o.stroke or (if tile then COMPAT_STROKE else STROKE)
	return sim(root, look, {
		radius = radius,
		stroke = thickness,
		faceName = o.faceName,
		shine = o.shine,
		z = o.z,
		rim = if thickness < 4 then 1.5 else nil,
	})
end

local function tile(root: any, token: any, opts: { [string]: any }?): any
	local o: { [string]: any } = { tile = true }
	for key, value in opts or {} do
		o[key] = value
	end
	return brick(root, token, o)
end

-- v4 round plate (the action button) → a round sim button (no raised stud), chunky outline + gloss.
local function roundPlate(button: any, token: any, opts: { [string]: any }?): any
	local o = opts or {}
	return sim(
		button,
		token,
		{ round = true, color = o.color, shine = o.shine, z = o.z, stroke = STROKE, gloss = true }
	)
end

-- v3 studs seen from above: nothing is drawn any more (a detached, empty frame is returned).
local function topStud(_parent: any, name: string, _props: { [string]: any }?): any
	return U.new("Frame", { Name = name, BackgroundTransparency = 1 })
end

local function studRow(_parent: any, props: { [string]: any }): any
	return U.new("Frame", { Name = props.Name or "StudRow", BackgroundTransparency = 1 })
end

local function studScale(_refHeight: number): number
	return 1
end

-- v1-v3 candy button → simButton (the "stack" layout unless given).
local function candyButton(parent: any, name: string, token: any, props: { [string]: any }): any
	local o: { [string]: any } = {}
	for key, value in props do
		o[key] = value
	end
	if o.Radius == nil then
		o.Radius = if o.Brick then SIM.Radius else SIM.PlateRadius
	end
	local simOpts: { [string]: any } = { stroke = STROKE }
	for key, value in o.SimOpts or {} do
		simOpts[key] = value
	end
	o.SimOpts = simOpts
	return simButton(parent, name, token, o)
end

-- v1-v3 pill → plate (chips: the minor outline, see COMPAT_STROKE).
local function pill(parent: any, name: string, token: any, props: { [string]: any }): any
	local o: { [string]: any } = {}
	for key, value in props do
		o[key] = value
	end
	local simOpts: { [string]: any } = { stroke = COMPAT_STROKE }
	for key, value in o.SimOpts or {} do
		simOpts[key] = value
	end
	o.SimOpts = simOpts
	return plate(parent, name, token, o)
end

return {
	U = U,
	UI = UI,
	P = P,
	TYPE = TYPE,
	SZ = SZ,
	INK = INK,
	WHITE = WHITE,
	FONT = FONT,
	FONT_ITALIC = FONT_ITALIC,
	MIN_TEXT = MIN_TEXT,
	HOTBAR = HOTBAR,
	STROKE = STROKE,
	MINOR = MINOR,
	TIER_OUTLINE = TIER_OUTLINE,
	DISPLAY_OUTLINE = DISPLAY_OUTLINE,
	TITLE_OUTLINE = TITLE_OUTLINE,
	ICON_OUTLINE = ICON_OUTLINE,
	sequence = sequence,
	numbers = numbers,
	lighten = lighten,
	darken = darken,
	gradient = gradient,
	multiGradient = multiGradient,
	swatch = swatch,
	corner = corner,
	stroke = stroke,
	outline = outline,
	label = label,
	icon = icon,
	shine = shine,
	sim = sim,
	glass = glass,
	simButton = simButton,
	plate = plate,
	badge = badge,
	stat = stat,
	title = title,
	rarityGradient = rarityGradient,
	-- compat (Fishing.luau until the fishing waves)
	BZ = SZ,
	BRICK = BRICK,
	brick = brick,
	tile = tile,
	roundPlate = roundPlate,
	topStud = topStud,
	studRow = studRow,
	studScale = studScale,
	socket = socket,
	candyButton = candyButton,
	pill = pill,
}
