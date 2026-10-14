--[[
	Theme — the "Candy Splash" look of the HUD builders (tools/builder/gui/*). Style guide and the
	full API: tools/builder/gui/STYLE.md ("API").

	Colours are NOT defined here: the palette tokens, rarity and mutation styles and toast kinds are
	read from src/ReplicatedStorage/Shared/Config/UIConfig.luau (a pure module), the same table the
	client (UiFx, controllers) uses at runtime — one source of truth.

	A "candy" is a transparent root with this structure (UiFx relies on it):
	  <Root>        BackgroundTransparency 1; attributes CandyFace (name of the face), CandyRadius
	    Lip         Frame, full size, the dark bottom colour, UICorner, UIStroke (Ink) — the outline
	                of the whole shape; its bottom LIP fraction shows under the face (3D look)
	    Face        Frame, top (1 - LIP) of the root: white + UIGradient "Fill" (Top → Bottom), UICorner
	      Gloss     white band in the top ~45 % (UIGradient transparency 0.5 → 1): the "wet" look
	      Shine     full-size overlay with a transparent UIGradient "Band" for UiFx.shine
	    …content    Icon / Caption / Label (ZIndex above the face)
	A candy may also take a runtime colour (Theme.candy opts.color / UiFx.setCandy(root, Color3)):
	it becomes a clean swatch made from that colour (UIConfig.swatchFor), never a grey-tinted face.

	Text sizes come from the type scale TYPE (UIConfig.Type): label/pill/candyButton take a `Tier`
	("Title" | "Button" | "Body" | "Small"), stored as the TextTier attribute; at runtime
	UiFx.fitText (HudController) sets each tiered label's UITextSizeConstraint for the real screen.
]]

local U = require("../Util")

local Enum = U.Enum
local UDim = U.UDim
local UDim2 = U.UDim2
local Vector2 = U.Vector2
local roblox = U.roblox
local ColorSequence = roblox.ColorSequence
local ColorSequenceKeypoint = roblox.ColorSequenceKeypoint
local NumberSequence = roblox.NumberSequence
local NumberSequenceKeypoint = roblox.NumberSequenceKeypoint

-- The shared palette (same numbers as the client). Paths are relative to the repo root, like build.luau.
local UI = U.loadPure("src/ReplicatedStorage/Shared/Config/UIConfig.luau")

local FONT = U.FONT
local MIN_TEXT = 12 -- never let TextScaled shrink text below this on phones
-- Pixels from the screen bottom to the fishing widgets: clears the Roblox hotbar (see Gui.luau).
local HOTBAR = 74
-- Fraction of a candy's height taken by the lip under the face (STYLE.md: 6–8 %).
local LIP = 0.08
-- Outline thickness at 720 px screen height (UiFx.fitStrokes scales it to the real screen).
local STROKE = 3

local INK = UI.Ink
local WHITE = UI.White
local P = UI.Palette
-- Type scale: text size per tier in px at a 390 px tall screen (UiFx.fitText scales it up).
local TYPE = UI.Type

-- ZIndex layers inside a candy root (ZIndexBehavior.Sibling: they only order siblings).
local Z = {
	Behind = 0, -- glow rings, rays (UiFx)
	Lip = 1,
	Face = 2,
	Content = 3, -- icons, captions, labels
	Overlay = 5, -- cooldowns, locks
	Top = 6, -- text over overlays
}

--------------------------------------------------------------------------------
-- Sequences and gradients
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

--------------------------------------------------------------------------------
-- Small constructors
--------------------------------------------------------------------------------

local function corner(parent: any, scale: number)
	return U.new("UICorner", { CornerRadius = UDim.new(scale, 0) }, parent)
end

-- Dark outline (Ink). BaseThickness lets UiFx.fitStrokes scale it to the screen height.
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

--[[
	Text label: white Nunito ExtraBold with a dark Ink outline, TextScaled.
	Extra keys (not Roblox properties):
	  Tier = "Title" | "Button" | "Body" | "Small" — the type scale (TYPE): attribute TextTier and a
	                            UITextSizeConstraint Max = TYPE[Tier], Min = Max - 2 (phone values;
	                            UiFx.fitText rescales them for the real screen). Wins over Max/MinTextSize.
	                            Give the label a box at least that tall and wide enough for its text:
	                            long copy is shortened, never shrunk below the tier;
	  MaxTextSize / MinTextSize — UITextSizeConstraint (MinTextSize defaults to 12 when MaxTextSize is set);
	  Outline = px            — a thick UIStroke on the text (titles, captions) instead of TextStroke;
	  OutlineColor            — its colour (default Ink);
	  TextGradient = {a, b}   — a vertical UIGradient on the text (e.g. white → pale gold).
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
	local outline = base.Outline
	local outlineColor = base.OutlineColor
	local textGradient = base.TextGradient
	base.Tier = nil
	base.MaxTextSize = nil
	base.MinTextSize = nil
	base.Outline = nil
	base.OutlineColor = nil
	base.TextGradient = nil
	if tier then
		assert(TYPE[tier], `Theme.label: unknown text tier {tier}`)
		maxText = TYPE[tier]
		minText = TYPE[tier] - 2
	end
	if outline and props.TextStrokeTransparency == nil then
		base.TextStrokeTransparency = 1 -- the UIStroke draws the outline
	end
	local inst = U.new("TextLabel", base, parent)
	if tier then
		inst:SetAttribute("TextTier", tier)
	end
	if maxText then
		U.new("UITextSizeConstraint", { MaxTextSize = maxText, MinTextSize = minText }, inst)
	end
	if outline then
		U.new("UIStroke", {
			Name = "Outline",
			Color = outlineColor or INK,
			Thickness = outline,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			LineJoinMode = Enum.LineJoinMode.Round,
			Attributes = { BaseThickness = outline },
		}, inst)
	end
	if textGradient then
		gradient(inst, textGradient[1], textGradient[2], 90, "TextFill")
	end
	return inst
end

-- Emoji icon: its own label, no outline, slightly rotated for life (STYLE.md §1).
local function icon(parent: any, name: string, emoji: string, props: { [string]: any }?): any
	local base: { [string]: any } = {
		Text = emoji,
		TextStrokeTransparency = 1,
		Rotation = -8,
		ZIndex = Z.Content,
	}
	for key, value in props or {} do
		base[key] = value
	end
	return label(parent, name, base)
end

-- The white "wet" highlight in the top of a face.
local function gloss(face: any, radius: number, props: { [string]: any }?): any
	local base: { [string]: any } = {
		Name = "Gloss",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.07),
		Size = UDim2.fromScale(0.9, 0.44),
		ZIndex = 1,
	}
	for key, value in props or {} do
		base[key] = value
	end
	local frame = U.new("Frame", base, face)
	corner(frame, radius)
	U.new("UIGradient", {
		Name = "Fade",
		Rotation = 90,
		Transparency = numbers({ { 0, 0.42 }, { 0.6, 0.78 }, { 1, 1 } }),
	}, frame)
	return frame
end

-- Overlay swept by UiFx.shine. Hidden (Visible = false: no full-size quad rasterised every frame)
-- until UiFx.shine shows it for the sweep; the band also waits out of sight (Offset.X = -1).
local function shine(face: any, radius: number): any
	local frame = U.new("Frame", {
		Name = "Shine",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
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

--[[
	Turns `root` into a candy surface (see the header) and returns the face.
	token: a palette token name ("Leaf") or { Top, Bottom, Lip }; ignored when opts.color is set.
	opts:
	  radius        UICorner scale (default 0.5 = pill)
	  lip           lip fraction of the height (default 0.08)
	  stroke        outline px at 720p (default 3; 0 = none)
	  color         a runtime colour instead of the token: the swatch UIConfig.swatchFor(color)
	  transparency  BackgroundTransparency of face and lip (Night panels: 0.1)
	  faceName      name of the face (default "Face"; the base badge calls it "Swatch")
	  gloss, shine  false to leave them out (a Night candy gets the panel's thin, faint gloss)
	  z             ZIndex of the lip (face = z + 1; put content at z + 2 or higher)
]]
local function candy(root: any, token: any, opts: { [string]: any }?): any
	local o = opts or {}
	local radius = o.radius or 0.5
	local lip = o.lip or LIP
	local z = o.z or Z.Lip
	local transparency = o.transparency or 0
	local faceName = o.faceName or "Face"

	root.BackgroundTransparency = 1
	root:SetAttribute("CandyFace", faceName)
	root:SetAttribute("CandyRadius", radius)

	local look = if o.color then UI.swatchFor(o.color) else swatch(token)
	local lipFrame = U.new("Frame", {
		Name = "Lip",
		BackgroundColor3 = look.Lip,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, root)
	corner(lipFrame, radius)
	if (o.stroke or STROKE) > 0 then
		stroke(lipFrame, o.stroke or STROKE)
	end

	local face = U.new("Frame", {
		Name = faceName,
		BackgroundColor3 = WHITE,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1 - lip),
		ZIndex = z + 1,
	}, root)
	corner(face, radius)
	gradient(face, look.Top, look.Bottom)
	if o.gloss ~= false then
		local glossy = gloss(face, radius)
		if token == "Night" and not o.color then
			-- Dark glass (hint pill, ribbons, panels): a thin faint highlight, never a grey stripe.
			glossy.Size = UDim2.fromScale(0.94, 0.3)
			glossy.BackgroundTransparency = 0.75
		end
	end
	if o.shine ~= false then
		shine(face, radius)
	end
	return face
end

-- Round white "socket" holding an emoji (flag on the base badge, toast icons). emoji "" = an
-- empty socket (the icon is a sibling drawn over it, e.g. the catch counter's 🐟 "Icon").
local function socket(parent: any, name: string, emoji: string, props: { [string]: any }?): any
	local base: { [string]: any } = {
		Name = name,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = Z.Content,
	}
	local iconName = "Icon"
	for key, value in props or {} do
		if key == "IconName" then
			iconName = value
		else
			base[key] = value
		end
	end
	local frame = U.new("Frame", base, parent)
	corner(frame, 0.5)
	gradient(frame, WHITE, P.Cream.Bottom)
	stroke(frame, STROKE)
	if emoji ~= "" then
		icon(frame, iconName, emoji, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.72, 0.72),
			ZIndex = 2,
		})
	end
	return frame
end

--[[
	Candy TextButton with Icon and/or Caption, ready for UiFx.press / shine / glowRing.
	props: any TextButton properties (Size, Position, AnchorPoint, LayoutOrder, Visible, …) plus
	  Icon (emoji), Caption (text), Layout ("stack": icon over caption — square buttons;
	  "row": icon left, caption right — pills; default "stack"), Radius (default 0.3),
	  Square (true → UIAspectRatioConstraint 1), Tier (caption text tier, see label),
	  MaxTextSize / MinTextSize (caption without a Tier; MinTextSize defaults to 12),
	  CandyOpts (extra Theme.candy opts).
]]
local function candyButton(parent: any, name: string, token: any, props: { [string]: any }): any
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
		CandyOpts = true,
	}
	for key, value in props do
		if not special[key] then
			base[key] = value
		end
	end
	local button = U.new("TextButton", base, parent)
	if props.Square then
		U.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, button)
	end
	local radius = props.Radius or 0.3
	local candyOpts: { [string]: any } = { radius = radius }
	for key, value in props.CandyOpts or {} do
		candyOpts[key] = value
	end
	candy(button, token, candyOpts)

	local layout = props.Layout or "stack"
	local faceH = 1 - (candyOpts.lip or LIP)
	if layout == "stack" then
		if props.Icon then
			icon(button, "Icon", props.Icon, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, faceH * 0.38),
				Size = UDim2.fromScale(0.62, faceH * 0.56),
			})
		end
		if props.Caption then
			label(button, "Caption", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, faceH * (if props.Icon then 0.8 else 0.5)),
				Size = UDim2.fromScale(0.9, faceH * (if props.Icon then 0.28 else 0.6)),
				Text = props.Caption,
				Outline = 2,
				ZIndex = Z.Content,
				Tier = props.Tier,
				MaxTextSize = props.MaxTextSize or 24,
				MinTextSize = props.MinTextSize or MIN_TEXT,
			})
		end
	else
		if props.Icon then
			icon(button, "Icon", props.Icon, {
				SizeConstraint = Enum.SizeConstraint.RelativeYY,
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.13, faceH * 0.5),
				Size = UDim2.fromScale(faceH * 0.8, faceH * 0.8),
			})
		end
		if props.Caption then
			label(button, "Caption", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(0.94, faceH * 0.5),
				Size = UDim2.fromScale(if props.Icon then 0.7 else 0.88, faceH * 0.62),
				Text = props.Caption,
				Outline = 2,
				ZIndex = Z.Content,
				Tier = props.Tier,
				MaxTextSize = props.MaxTextSize or 26,
				MinTextSize = props.MinTextSize or MIN_TEXT,
			})
		end
	end
	return button
end

--[[
	Candy pill (Frame): an emoji Icon overhanging its left end and a centred Label.
	props: Frame properties plus Icon (emoji), IconScale (icon size as a fraction of the pill height,
	default 1.35), Text, Tier (label text tier, see label), MaxTextSize, Socket (true → the icon
	sits in a white round socket named "IconSocket"), Color (runtime colour mode), CandyOpts,
	LabelProps (extra Label properties).
]]
local function pill(parent: any, name: string, token: any, props: { [string]: any }): any
	local base: { [string]: any } = { Name = name, BackgroundTransparency = 1 }
	local special = {
		Icon = true,
		IconScale = true,
		Text = true,
		Tier = true,
		MaxTextSize = true,
		Socket = true,
		Color = true,
		CandyOpts = true,
		LabelProps = true,
	}
	for key, value in props do
		if not special[key] then
			base[key] = value
		end
	end
	local frame = U.new("Frame", base, parent)
	local candyOpts: { [string]: any } = { radius = 0.5, color = props.Color }
	for key, value in props.CandyOpts or {} do
		candyOpts[key] = value
	end
	candy(frame, token, candyOpts)
	local faceH = 1 - (candyOpts.lip or LIP)
	local iconScale = props.IconScale or 1.35
	if props.Icon then
		if props.Socket then
			socket(frame, "IconSocket", props.Icon, {
				AnchorPoint = Vector2.new(0.3, 0.5),
				Position = UDim2.fromScale(0, faceH * 0.5),
				Size = UDim2.fromScale(iconScale, iconScale),
			})
		else
			icon(frame, "Icon", props.Icon, {
				SizeConstraint = Enum.SizeConstraint.RelativeYY,
				AnchorPoint = Vector2.new(0.32, 0.44), -- sits a little low: "seated" on the pill
				Position = UDim2.fromScale(0, faceH * 0.5),
				Size = UDim2.fromScale(iconScale, iconScale),
				Rotation = -12,
			})
		end
	end
	if props.Text then
		local labelProps: { [string]: any } = {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.95, faceH * 0.5),
			Size = UDim2.fromScale(if props.Icon then 0.76 else 0.9, faceH * 0.66),
			Text = props.Text,
			Outline = 2,
			ZIndex = Z.Content,
			Tier = props.Tier,
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
	Panel (Frame): a Night glass panel by default (or any token), rounded, with lip and outline.
	props: Frame properties plus Token (default "Night"), Radius (default 0.16), CandyOpts.
]]
local function panel(parent: any, name: string, props: { [string]: any }): any
	local base: { [string]: any } = { Name = name, BackgroundTransparency = 1 }
	for key, value in props do
		if key ~= "Token" and key ~= "Radius" and key ~= "CandyOpts" then
			base[key] = value
		end
	end
	local frame = U.new("Frame", base, parent)
	local token = props.Token or "Night"
	local candyOpts: { [string]: any } = {
		radius = props.Radius or 0.16,
		lip = 0.05,
		transparency = if token == "Night" then 0.1 else 0,
		shine = false,
	}
	for key, value in props.CandyOpts or {} do
		candyOpts[key] = value
	end
	local face = candy(frame, token, candyOpts)
	local glossy = face:FindFirstChild("Gloss")
	if glossy and token ~= "Night" then -- (a Night candy already has the thin gloss)
		glossy.Size = UDim2.fromScale(0.94, 0.3) -- a panel only needs a thin highlight
		glossy.BackgroundTransparency = 0.3
	end
	return frame
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

return {
	U = U,
	UI = UI,
	P = P,
	TYPE = TYPE,
	Z = Z,
	INK = INK,
	WHITE = WHITE,
	FONT = FONT,
	MIN_TEXT = MIN_TEXT,
	HOTBAR = HOTBAR,
	LIP = LIP,
	STROKE = STROKE,
	sequence = sequence,
	numbers = numbers,
	gradient = gradient,
	multiGradient = multiGradient,
	swatch = swatch,
	corner = corner,
	stroke = stroke,
	label = label,
	icon = icon,
	gloss = gloss,
	shine = shine,
	candy = candy,
	socket = socket,
	candyButton = candyButton,
	pill = pill,
	panel = panel,
	rarityGradient = rarityGradient,
}
