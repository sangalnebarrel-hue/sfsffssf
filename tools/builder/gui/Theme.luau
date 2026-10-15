--[[
	Theme — the look of the HUD builders (tools/builder/gui/*): UI v3 «Кирпичики» (toy bricks with
	studs, heavy CAPS text, thick Ink outlines) on top of the v1/v2 "candy" helpers. Style guide
	and the full API: tools/builder/gui/STYLE.md ("API").

	Colours and the brick's proportions are NOT defined here: palette tokens, rarity and mutation
	styles, toast kinds and UIConfig.Brick are read from src/ReplicatedStorage/Shared/Config/
	UIConfig.luau (a pure module), the same table the client (UiFx, controllers) uses at runtime.

	A "candy" (legacy v1/v2: no widget uses it any more since the fishing widgets became bricks in
	UI v4; Theme.panel still builds one) is a transparent root (UiFx relies on this structure):
	  <Root>        BackgroundTransparency 1; attributes CandyFace (name of the face), CandyRadius
	    Lip         Frame, full size, the dark bottom colour, UICorner, UIStroke (Ink) — the outline
	                of the whole shape; its bottom LIP fraction shows under the face (3D look)
	    Face        Frame, top (1 - LIP) of the root: white + UIGradient "Fill" (Top → Bottom), UICorner
	      Gloss     white band in the top ~45 % (UIGradient transparency 0.5 → 1): the "wet" look
	      Shine     full-size overlay with a transparent UIGradient "Band" for UiFx.shine
	    …content    Icon / Caption / Label (ZIndex above the face, Z.Content)
	A "brick" (Theme.brick / Theme.tile) is the same contract with the brick anatomy
	(attribute CandyStyle = "brick" | "tile"; layers BZ — content goes at BZ.Content):
	  <Root>
	    Studs       Frame holder (ZIndex BZ.Studs, behind the Lip): Stud1..n front-view studs on the
	                top edge — UICorner, horizontal UIGradient "Fill", Ink UIStroke, attribute
	                CandyStud = "front"; the brick's outline cuts their bottoms off
	    Lip         the side band: the bottom UIConfig.Brick.Lip (16 %) of the height
	    Face        UIGradient "Fill" with a light cap: {0: Top + CapLight, CapStop: Top, 1: Bottom}
	      Spec      a small white glint at the top left (no Gloss band)
	      Shine     as on a candy
	A candy may also take a runtime colour (opts.color / UiFx.setCandy(root, Color3)): it becomes
	a clean swatch made from that colour (UIConfig.swatchFor), never a grey-tinted face.
	UiFx.setCandy recolours bricks too (cap, side band, studs).

	Text: Nunito Heavy (900), white with a thick Ink outline; a tiered label (Tier = "Title" |
	"Button" | "Body" | "Small", the TextTier attribute; UiFx.fitText sizes it on the real screen)
	gets at least its tier's outline (TIER_OUTLINE).
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

-- The UI font: Nunito Heavy (Black 900; Cyrillic). The map's signs keep Util.FONT (ExtraBold).
local FONT = roblox.Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Heavy)
local MIN_TEXT = 12 -- never let TextScaled shrink text below this on phones
-- Pixels from the screen bottom to the fishing widgets: clears the Roblox hotbar (see Gui.luau).
local HOTBAR = 74
-- Fraction of a candy's height taken by the lip under the face (legacy candies: 8 %).
local LIP = 0.08
-- Outline thickness at 720 px screen height (UiFx.fitStrokes scales it to the real screen):
-- 4 → 2.5 px on a phone (bricks, tiles, sockets). Legacy candies (the fishing widgets until UI v4
-- rebuilds them as bricks) keep 3: their layout gaps to the CoreGui were tuned with it.
local STROKE = 4
local CANDY_STROKE = 3
-- Text outline per tier at 720 px (a tiered label gets at least this; phones floor at 2.5 px).
local TIER_OUTLINE = { Title = 4.5, Button = 4, Body = 3.5, Small = 3 }

local BRICK = UI.Brick
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
-- … and inside a brick root: its studs need a layer behind the side band.
local BZ = {
	Behind = 0,
	Studs = 1,
	Lip = 2,
	Face = 3,
	Content = 4,
	Overlay = 6,
	Top = 7,
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

-- A brick face: a light cap on top (the brick's top surface seen from a little above), then
-- Top → Bottom. UiFx.setCandy builds the same sequence at runtime.
local function capSequence(look: any): any
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighten(look.Top, BRICK.CapLight)),
		ColorSequenceKeypoint.new(BRICK.CapStop * 0.5, lighten(look.Top, BRICK.CapLight)),
		ColorSequenceKeypoint.new(BRICK.CapStop, look.Top),
		ColorSequenceKeypoint.new(1, look.Bottom),
	})
end

-- The body colour of a stud (seen from the front it is the brick's plastic, lit from the left).
local function studBody(look: any): any
	return look.Top:Lerp(look.Bottom, 0.3)
end

-- Horizontal light → body → shade (front stud); UiFx.setCandy builds the same.
local function studSequence(look: any): any
	local body = studBody(look)
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, lighten(body, BRICK.StudLight)),
		ColorSequenceKeypoint.new(0.45, body),
		ColorSequenceKeypoint.new(1, darken(body, BRICK.StudShade)),
	})
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
	Text label: white Nunito Heavy with a dark Ink outline, TextScaled.
	Extra keys (not Roblox properties):
	  Tier = "Title" | "Button" | "Body" | "Small" — the type scale (TYPE): attribute TextTier and a
	                            UITextSizeConstraint Max = TYPE[Tier], Min = Max - 2 (phone values;
	                            UiFx.fitText rescales them for the real screen). Wins over Max/MinTextSize.
	                            Give the label a box at least that tall and wide enough for its text:
	                            long copy is shortened, never shrunk below the tier. A tiered label is
	                            outlined at least TIER_OUTLINE[Tier] (unless Outline = false or
	                            TextStrokeTransparency = 1: dark text on a white tile);
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
		if outline ~= false and props.TextStrokeTransparency ~= 1 and TIER_OUTLINE[tier] then
			outline = math.max(if type(outline) == "number" then outline else 0, TIER_OUTLINE[tier])
		end
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

--[[
	Emoji icon: its own label, upright (Rotation 0: only stamps and the banner flag tilt), no Ink
	outline (in game emoji are flat Twemoji). Extra key Sticker = true (or a px number): a white
	"sticker" rim (UIStroke "Sticker", Contextual, BaseThickness 3) around the emoji's shape, so a
	free-standing icon reads as a sticker on its brick.
]]
local function icon(parent: any, name: string, emoji: string, props: { [string]: any }?): any
	local base: { [string]: any } = {
		Text = emoji,
		TextStrokeTransparency = 1,
		Rotation = 0,
		ZIndex = Z.Content,
	}
	local sticker = nil
	for key, value in props or {} do
		if key == "Sticker" then
			sticker = value
		else
			base[key] = value
		end
	end
	local inst = label(parent, name, base)
	if sticker then
		local px = if type(sticker) == "number" then sticker else 3
		U.new("UIStroke", {
			Name = "Sticker",
			Color = WHITE,
			Thickness = px,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
			LineJoinMode = Enum.LineJoinMode.Round,
			Attributes = { BaseThickness = px },
		}, inst)
	end
	return inst
end

-- The white "wet" highlight in the top of a face (legacy candies).
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

-- A brick's glint: a small white rounded dash at the top left of the face (opts x / y / w / h
-- as fractions of the face; UIConfig.Brick.Spec*).
local function spec(face: any, opts: { [string]: any }?): any
	local o = opts or {}
	local frame = U.new("Frame", {
		Name = "Spec",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = BRICK.SpecAlpha,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(o.x or BRICK.SpecX, o.y or BRICK.SpecY),
		Size = UDim2.fromScale(o.w or BRICK.SpecW, o.h or BRICK.SpecH),
		ZIndex = 1,
	}, face)
	corner(frame, 0.5)
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
	  stroke        outline px at 720p (default 3 — CANDY_STROKE; 0 = none)
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
	if (o.stroke or CANDY_STROKE) > 0 then
		stroke(lipFrame, o.stroke or CANDY_STROKE)
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

--[[
	Front-view studs on the top edge of a brick root: a "Studs" holder (ZIndex z, behind the
	Lip) with Stud1..n. opts:
	  studs      count (1 … UIConfig.Brick.MaxStuds)
	  studArea   { x0, x1 } — the part of the width they spread over (default { 0, 1 }; e.g. clear
	             of a flag tile overhanging the left end)
	  studScale  size multiplier (default 1: StudW × StudH of the brick's HEIGHT; a tall 2x2 brick
	             wants ~0.6)
	Each stud: AnchorPoint (0.5, StudShow) at the top edge (the rest hides behind the brick),
	SizeConstraint RelativeYY, UICorner, UIStroke Ink, horizontal UIGradient "Fill", attribute
	CandyStud = "front". UiFx.setStuds builds the same at runtime.
]]
local function studs(root: any, look: any, z: number, opts: { [string]: any }): any
	local count = math.clamp(math.floor(opts.studs or 0), 0, BRICK.MaxStuds)
	local holder = U.new("Frame", {
		Name = "Studs",
		BackgroundTransparency = 1,
		Active = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = z,
	}, root)
	local area = opts.studArea or { 0, 1 }
	local scale = opts.studScale or 1
	holder:SetAttribute("StudArea", Vector2.new(area[1], area[2]))
	holder:SetAttribute("StudScale", scale)
	local sequence_ = studSequence(look)
	for i = 1, count do
		local stud = U.new("Frame", {
			Name = `Stud{i}`,
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, BRICK.StudShow),
			Position = UDim2.fromScale(area[1] + (area[2] - area[1]) * (i - 0.5) / count, 0),
			Size = UDim2.fromScale(BRICK.StudW * scale, BRICK.StudH * scale),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			ZIndex = 1,
			Attributes = { CandyStud = "front" },
		}, holder)
		corner(stud, 0.3)
		stroke(stud, BRICK.StudStroke)
		U.new("UIGradient", { Name = "Fill", Color = sequence_, Rotation = 0 }, stud)
	end
	return holder
end

--[[
	A toy brick (see the header): returns the face. token as for candy. opts:
	  studs, studArea, studScale  front-view studs (see studs; default none)
	  tile         true → a smooth tile: TileLip / TileRadius, no studs (CandyStyle "tile")
	  lip, radius  default UIConfig.Brick.Lip / Radius (tile: TileLip / TileRadius)
	  stroke       outline px at 720p (default 4)
	  color        a runtime colour (UIConfig.swatchFor)
	  faceName     name of the face (default "Face")
	  spec         false: no glint; or { x, y, w, h } (fractions of the face) to move it
	  shine        false: no Shine overlay
	  z            ZIndex of the Lip (default BZ.Lip; studs at z - 1, face z + 1, content z + 2)
]]
local function brick(root: any, token: any, opts: { [string]: any }?): any
	local o = opts or {}
	local tile = o.tile == true
	local radius = o.radius or (if tile then BRICK.TileRadius else BRICK.Radius)
	local lip = o.lip or (if tile then BRICK.TileLip else BRICK.Lip)
	local z = o.z or BZ.Lip
	local faceName = o.faceName or "Face"
	local look = if o.color then UI.swatchFor(o.color) else swatch(token)

	root.BackgroundTransparency = 1
	root:SetAttribute("CandyFace", faceName)
	root:SetAttribute("CandyRadius", radius)
	root:SetAttribute("CandyStyle", if tile then "tile" else "brick")

	if not tile and (o.studs or 0) > 0 then
		studs(root, look, z - 1, o)
	end
	local lipFrame = U.new("Frame", {
		Name = "Lip",
		BackgroundColor3 = look.Lip,
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
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1 - lip),
		ZIndex = z + 1,
	}, root)
	corner(face, radius)
	U.new("UIGradient", { Name = "Fill", Color = capSequence(look), Rotation = 90 }, face)
	if o.spec ~= false then
		spec(face, if type(o.spec) == "table" then o.spec else nil)
	end
	if o.shine ~= false then
		shine(face, radius)
	end
	return face
end

-- A smooth tile: a brick without studs (toasts, hints, chips).
local function tile(root: any, token: any, opts: { [string]: any }?): any
	local o: { [string]: any } = { tile = true }
	for key, value in opts or {} do
		o[key] = value
	end
	return brick(root, token, o)
end

--[[
	A round stud seen from above (plates: the minigame baseplate, the card; pips): a darker
	"shadow" disc (the Frame itself, attribute CandyStud = "top") with its lit "Cap" offset up and
	left (UIGradient "Fill" light → shade, diagonal). 2 Frames + 2 UICorners + 1 UIGradient, no
	stroke. props: Frame properties (Position, Size, AnchorPoint, ZIndex, SizeConstraint …) plus
	Token / Color (default Cream).
]]
local function topStud(parent: any, name: string, props: { [string]: any }?): any
	local base: { [string]: any } = {
		Name = name,
		BorderSizePixel = 0,
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Attributes = { CandyStud = "top" },
	}
	local token: any = "Cream"
	for key, value in props or {} do
		if key == "Token" then
			token = value
		elseif key == "Color" then
			token = UI.swatchFor(value)
		else
			base[key] = value
		end
	end
	local look = swatch(token)
	base.BackgroundColor3 = darken(look.Top, 0.35)
	local disc = U.new("Frame", base, parent)
	corner(disc, 0.5)
	local cap = U.new("Frame", {
		Name = "Cap",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.42, 0.38),
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, disc)
	corner(cap, 0.5)
	U.new("UIGradient", {
		Name = "Fill",
		Rotation = 45,
		Color = ColorSequence.new(lighten(look.Top, BRICK.TopLight), darken(look.Top, BRICK.TopShade)),
	}, cap)
	return disc
end

--[[
	A row (or rows) of top-down studs over a plate: a "StudRow" holder in `parent` covering
	props.Area = { x0, y0, x1, y1 } (fractions of the parent), Count studs per row, Rows rows
	(default 1), each Size (diameter, a fraction of the holder's HEIGHT per row; default 0.6).
	props.Token / Color as topStud, props.ZIndex for the holder. Returns the holder.
]]
local function studRow(parent: any, props: { [string]: any }): any
	local area = props.Area or { 0, 0, 1, 1 }
	local count = math.max(1, props.Count or 6)
	local rows = math.max(1, props.Rows or 1)
	local holder = U.new("Frame", {
		Name = props.Name or "StudRow",
		BackgroundTransparency = 1,
		Active = false,
		Position = UDim2.fromScale(area[1], area[2]),
		Size = UDim2.fromScale(area[3] - area[1], area[4] - area[2]),
		ZIndex = props.ZIndex or 1,
	}, parent)
	local d = (props.Size or 0.6) / rows
	for r = 1, rows do
		for i = 1, count do
			topStud(holder, `Stud{(r - 1) * count + i}`, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale((i - 0.5) / count, (r - 0.5) / rows),
				Size = UDim2.fromScale(d, d),
				Token = props.Token,
				Color = props.Color,
			})
		end
	end
	return holder
end

--[[
	A round plate seen from above (the action button, v4): `button` becomes a round brick
	(CandyStyle "brick", radius 0.5, its side band 0.1 deep) with a raised centre stud "Stud" on
	the face (opts.stud = diameter share, default 0.66; opts.studY = its centre, a share of the
	face's height, default 0.52): a darker side disc (attribute CandyStud = "raised") holding its
	lit "Cap" (UIGradient "Fill", Top → Bottom) a little higher, Ink outline. Put the icon at
	BZ.Content on the button (it sits on the stud: centre y = (1 − lip) × studY of the button).
	Returns the face.
]]
local function roundPlate(button: any, token: any, opts: { [string]: any }?): any
	local o = opts or {}
	local look = if o.color then UI.swatchFor(o.color) else swatch(token)
	local face = brick(button, token, {
		radius = 0.5,
		lip = o.lip or 0.1,
		color = o.color,
		spec = { x = 0.2, y = 0.12, w = 0.16, h = 0.07 },
		shine = o.shine,
		z = o.z,
	})
	local d = o.stud or 0.66
	local stud = U.new("Frame", {
		Name = "Stud",
		BackgroundColor3 = look.Lip:Lerp(look.Bottom, 0.4),
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, o.studY or 0.52),
		Size = UDim2.fromScale(d, d),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 1,
		Attributes = { CandyStud = "raised" },
	}, face)
	corner(stud, 0.5)
	stroke(stud, BRICK.StudStroke)
	local cap = U.new("Frame", {
		Name = "Cap",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 0.92),
		ZIndex = 1,
	}, stud)
	corner(cap, 0.5)
	U.new("UIGradient", {
		Name = "Fill",
		Rotation = 90,
		Color = ColorSequence.new(lighten(look.Top, 0.2), look.Bottom),
	}, cap)
	return face
end

--[[
	A white "socket" holding an emoji: a 1x1 round white tile (white → light grey disc, Ink
	outline, a thin inner "Rim" ring) — the flag of the base banner, toast and hint icons, the
	trophy chip. emoji "" = an empty socket (the icon is a sibling drawn over it).
	props: Frame properties plus IconName (default "Icon"); Rotation 0 unless given.
]]
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
	local rim = U.new("Frame", {
		Name = "Rim",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.8),
		ZIndex = 1,
	}, frame)
	corner(rim, 0.5)
	stroke(rim, 1.5, 0.2, P.Slate.Top)
	if emoji ~= "" then
		icon(frame, iconName, emoji, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.52),
			Size = UDim2.fromScale(0.88, 0.88),
			ZIndex = 2,
		})
	end
	return frame
end

--[[
	Candy (or brick) TextButton with Icon and/or Caption, ready for UiFx.press / shine / glowRing.
	props: any TextButton properties (Size, Position, AnchorPoint, LayoutOrder, Visible, …) plus
	  Icon (emoji), Caption (text), Layout ("stack": icon over caption — square buttons;
	  "row": icon left, caption right — pills; default "stack"), Radius (default 0.3),
	  Square (true → UIAspectRatioConstraint 1), Tier (caption text tier, see label),
	  MaxTextSize / MinTextSize (caption without a Tier; MinTextSize defaults to 12),
	  CandyOpts (extra Theme.candy opts), Brick (true or Theme.brick opts: a brick button — its
	  content goes at BZ.Content).
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
		Brick = true,
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
	local faceH, content
	if props.Brick then
		local brickOpts: { [string]: any } = { radius = props.Radius }
		for key, value in (if type(props.Brick) == "table" then props.Brick else {}) do
			brickOpts[key] = value
		end
		brick(button, token, brickOpts)
		faceH = 1 - (brickOpts.lip or (if brickOpts.tile then BRICK.TileLip else BRICK.Lip))
		content = BZ.Content
	else
		local candyOpts: { [string]: any } = { radius = props.Radius or 0.3 }
		for key, value in props.CandyOpts or {} do
			candyOpts[key] = value
		end
		candy(button, token, candyOpts)
		faceH = 1 - (candyOpts.lip or LIP)
		content = Z.Content
	end

	local layout = props.Layout or "stack"
	if layout == "stack" then
		if props.Icon then
			icon(button, "Icon", props.Icon, {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, faceH * 0.38),
				Size = UDim2.fromScale(0.62, faceH * 0.56),
				ZIndex = content,
			})
		end
		if props.Caption then
			label(button, "Caption", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.5, faceH * (if props.Icon then 0.8 else 0.5)),
				Size = UDim2.fromScale(0.9, faceH * (if props.Icon then 0.28 else 0.6)),
				Text = props.Caption,
				Outline = 2,
				ZIndex = content,
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
				ZIndex = content,
			})
		end
		if props.Caption then
			label(button, "Caption", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.fromScale(0.94, faceH * 0.5),
				Size = UDim2.fromScale(if props.Icon then 0.7 else 0.88, faceH * 0.62),
				Text = props.Caption,
				Outline = 2,
				ZIndex = content,
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
	LabelProps (extra Label properties), Brick (true or Theme.brick opts: a brick / tile "pill"
	— content at BZ.Content, the icon upright).
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
		Brick = true,
	}
	for key, value in props do
		if not special[key] then
			base[key] = value
		end
	end
	local frame = U.new("Frame", base, parent)
	local faceH, content
	if props.Brick then
		local brickOpts: { [string]: any } = { color = props.Color }
		for key, value in (if type(props.Brick) == "table" then props.Brick else {}) do
			brickOpts[key] = value
		end
		brick(frame, token, brickOpts)
		faceH = 1 - (brickOpts.lip or (if brickOpts.tile then BRICK.TileLip else BRICK.Lip))
		content = BZ.Content
	else
		local candyOpts: { [string]: any } = { radius = 0.5, color = props.Color }
		for key, value in props.CandyOpts or {} do
			candyOpts[key] = value
		end
		candy(frame, token, candyOpts)
		faceH = 1 - (candyOpts.lip or LIP)
		content = Z.Content
	end
	local iconScale = props.IconScale or 1.35
	if props.Icon then
		if props.Socket then
			socket(frame, "IconSocket", props.Icon, {
				AnchorPoint = Vector2.new(0.3, 0.5),
				Position = UDim2.fromScale(0, faceH * 0.5),
				Size = UDim2.fromScale(iconScale, iconScale),
				ZIndex = content,
			})
		else
			icon(frame, "Icon", props.Icon, {
				SizeConstraint = Enum.SizeConstraint.RelativeYY,
				AnchorPoint = Vector2.new(0.32, 0.44), -- sits a little low: "seated" on the pill
				Position = UDim2.fromScale(0, faceH * 0.5),
				Size = UDim2.fromScale(iconScale, iconScale),
				Rotation = if props.Brick then 0 else -12,
				ZIndex = content,
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
			ZIndex = content,
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
	BZ = BZ,
	INK = INK,
	WHITE = WHITE,
	FONT = FONT,
	MIN_TEXT = MIN_TEXT,
	HOTBAR = HOTBAR,
	LIP = LIP,
	BRICK = BRICK,
	STROKE = STROKE,
	CANDY_STROKE = CANDY_STROKE,
	TIER_OUTLINE = TIER_OUTLINE,
	sequence = sequence,
	numbers = numbers,
	lighten = lighten,
	darken = darken,
	gradient = gradient,
	multiGradient = multiGradient,
	swatch = swatch,
	capSequence = capSequence,
	studSequence = studSequence,
	corner = corner,
	stroke = stroke,
	label = label,
	icon = icon,
	gloss = gloss,
	spec = spec,
	shine = shine,
	candy = candy,
	brick = brick,
	tile = tile,
	topStud = topStud,
	studRow = studRow,
	roundPlate = roundPlate,
	socket = socket,
	candyButton = candyButton,
	pill = pill,
	panel = panel,
	rarityGradient = rarityGradient,
}
