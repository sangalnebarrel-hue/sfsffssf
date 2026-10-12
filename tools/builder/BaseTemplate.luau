--[[
	Builds ServerStorage.BaseTemplate — one player base: a fisherman's homestead on the green
	island (art direction v4, tools/builder/DESIGN.md §1 and §2 "Base-local frame"). BaseService
	clones it into the 8 slots and paints every part with attribute Accent = true in the base
	colour; the optional number attribute AccentShade (-1..1) gives lighter (> 0, towards white) or
	darker (< 0, darker in HSV) variants.

	Colour: the plot is built from calm Palette materials (lawn close to the island's grass, cobble
	and gravel paths, stone, wood, plaster). The base colour (Accent) is used sparingly, where it
	identifies the base from afar: the flag (with a lighter band), the roofs of the cottage, its
	dormer and porch, the smokehouse, the gate and the doghouse (a deep shade, AccentShade -0.28,
	with darker trims), the gate sign's frame, the shutters, the plates under the display cases,
	the signal mast's cap, the mailbox, the pier shelter's roof, the boat's sides, a light tint on
	the fishing spot and the SpawnPad itself — never on lawns, fences, decks, paving or whole
	walls. Any Accent part bigger than ~400 studs² uses a deep shade (<= -0.25; tested).

	Base-local frame (Root at the origin, y = 0 is GroundTop; the world builder provides flat
	grass under the plot):
	  -Z     towards the lagoon. lz 0..18 is the public promenade (the template places nothing
	         there except the start of the pier), lz 0..-PierLength (72) is the base's own pier
	         over the beach (sand, y = -2) and the water (y = -4).
	  +Z     inland: the plot x = -68..68, lz = 18..168.
	  +X/-X  sideways (+X is on the left of a player walking in through the gate).

	Layout (front to back; a cobble path runs on the centre line from the gate to the porch):
	  lz 18        roofed timber gate between two stone piers with lanterns: the name board
	               (SurfaceGui with OwnerLabel / BaseLabel on both faces) in an Accent frame under a
	               little Accent roof with a gold fish weathervane; a low stone-and-rail fence round
	               the sides, a tall hedge along the back
	  lz 22..50    front yard: the spawn square (cobble, light inner square, the SpawnPad in the base
	               colour), the flag (a 48-stud mast, the base's landmark) with the owner billboard,
	               the signal mast (Alarm), the mailbox; vegetable garden with three raised beds
	               (-X, gravel path), the doghouse (+X, gravel path)
	  lz 53..131   the aquarium court (cobble on a stone rim, light apron): the big tank in a timber
	               frame on a stone plinth (a calm reef inside) between two rows of six stone display
	               pedestals (Tank.Slots.Slot_1..12; odd numbers on the -X row, even on the +X row,
	               slots 1-2 nearest the gate); hedges along its sides; the well (-X) and the woodpile
	               (+X) in the side lawns, fruit trees
	  lz 131..166  the fisherman's cottage (stone base course, plaster walls with timber corners
	               and floor band, framed windows with shutters and flower boxes, a porch with
	               posts, rails and steps, a jettied gable roof in the base colour, chimney) with a
	               smokehouse annex (+X: timber, double doors, hoist beam, smoking pipe, a net);
	               work yard (+X: fish drying rack, rowboat on trestles, crates, barrels); seating
	               patio (-X: picnic table, bench, lantern)
	  lz 0..-50    plank pier with timber rails and lanterns, a moored boat that bobs (its bow line
	               tied to the last pier post)
	  lz -50..-72  end platform: the FishingSpot under open sky at its front edge (glints rise off
	               it), a shelter with an Accent roof and a bench over the rod rack on the -X side,
	               crates, barrel, lifebuoy
	Particles (no parts): chimney and smokehouse smoke, tank bubbles, the fishing spot's glints and
	the weathervane fish's sparkle (Props.fx).

	The guard dog (Model "Dog", stage 4 upgrade) is NOT on display: it sits by the doghouse with
	every part invisible (Transparency 1, CanCollide/CanQuery/CastShadow false) and the model
	attribute Unlocked = false. All its parts are opaque blocks: to show it (dog bought) set every
	BasePart's Transparency to 0 (keep CanCollide false) and Unlocked = true.

	Names the server code relies on (BaseService, DESIGN.md §2) — keep in sync:
	  Root, SpawnPad, FishingSpot, Tank.Glass.PromptAttachment, Alarm.Lamp, Dog (PrimaryPart),
	  Tank.Slots.Slot_N.{Pedestal.PromptAttachment, Pedestal.LabelGui.Label, Display.FishPoint}
	  (attribute SlotIndex), Flag.Pole.SignAttachment.OwnerSign.{OwnerLabel, BaseLabel},
	  Flag.Cloth (tests), Gate.Board.SignFront/SignBack.{OwnerLabel, BaseLabel}.

	Budget: <= 600 parts (8 bases at runtime; asserted below and in tests/stage1_bases.test.luau).
	Deterministic: variation comes from seeds, never math.random.
]]

local U = require("./Util")
local Props = require("./Props")
local P = require("./Palette")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Color3 = U.Color3
local Enum = U.Enum
local UDim2 = U.UDim2

local M = Enum.Material
local rad = math.rad

local BUDGET = 600

------------------------------------------------------------------------------------------
-- Colours (all from Palette.luau, DESIGN.md §1) and plot numbers
------------------------------------------------------------------------------------------

local C = {
	Lawn = P.GrassTop:Lerp(P.GrassTop3, 0.3), -- a kept lawn, a hair lighter than the island grass
	LawnStripe = P.GrassTop:Lerp(P.GrassTop2, 0.55), -- mowed stripes
	Hedge = P.Leaf1,
	HedgeTop = P.Leaf1:Lerp(P.Leaf2, 0.7),
	Path = P.Cobble,
	Gravel = P.SandDark:Lerp(P.Cobble, 0.45),
	Stone = P.Stone,
	StoneDark = P.StoneDark,
	StoneLight = P.StoneLight,
	Wood = P.Wood,
	WoodDark = P.WoodDark,
	WoodLight = P.WoodLight,
	Plank = P.Plank,
	Plaster = P.Plaster,
	Dirt = P.Dirt,
	Soil = P.DirtDark,
	Bark = P.Bark,
	CutWood = P.CutWood,
	Leaf0 = P.Leaf0,
	Leaf1 = P.Leaf1,
	Leaf2 = P.Leaf2,
	Leaf3 = P.Leaf3,
	Cabbage = P.Mint3,
	Pumpkin = P.Autumn0,
	Carrot = P.Autumn1,
	Iron = P.Iron,
	Gold = P.Gold,
	Cream = P.Cream,
	Rope = P.Rope,
	Ink = P.Dark, -- text, door holes, eyes (small dark details only)
	Glow = P.Glow, -- lantern cores (Neon)
	LightColor = P.LightColor,
	LampOff = P.Red:Lerp(P.Dark, 0.4), -- the alarm lamp when not alarmed (stage 4 lights it)
	WindowGlass = P.WindowBlue:Lerp(P.Glass, 0.35),
	Water = P.Water,
	FishSilver = P.StoneLight:Lerp(P.WindowBlue, 0.35), -- drying fish
	FishSilverDark = P.Stone:Lerp(P.WindowBlue, 0.35),
	-- aquarium: an almost clear glass, a deep sea backdrop, a calm reef
	TankGlass = P.Glass:Lerp(P.White, 0.55),
	SeaDeep = P.Water:Lerp(P.Navy, 0.45),
	ReefLight = P.WaterLight,
	Sand = P.SandDark:Lerp(P.Sand, 0.4),
	Kelp1 = P.Seaweed,
	Kelp2 = P.Leaf2,
	CoralPinkBase = P.Pink:Lerp(P.Purple, 0.3),
	CoralPink = P.Pink,
	CoralPinkTip = P.Blossom2,
	CoralOrangeBase = P.Autumn0,
	CoralOrange = P.Orange,
	CoralOrangeTip = P.GoldLight,
	SeaFan = P.Purple,
	BrainCoral = P.Yellow,
	Yellow = P.Yellow,
	Orange = P.Orange,
	Blue = P.Blue,
	White = P.White,
	Red = P.Red,
	RoofBlue = P.RoofBlue,
	RoofBrown = P.RoofBrown,
	Brick = P.Brick,
	Boat = P.BoatPaint[2],
	-- the hidden guard dog (shown in stage 4): a shiba in warm, calm tones
	Dog = P.Wood:Lerp(P.Orange, 0.55),
	DogCream = P.Cream,
	Tongue = P.Pink,
}

-- Accent shades (BaseService paints these parts in the base colour).
local ROOF = -0.28 -- roof slopes: a deep, natural shade of the base colour
local ROOF_TRIM = -0.45 -- fascias, ridges
local SHUTTER = -0.12
local PEDESTAL_TRIM = -0.3 -- the plate under each display case

-- Accent parts get this (shaded) grey in the template; BaseService repaints them.
local ACCENT_DEFAULT = Color3.fromRGB(200, 200, 200)
local WHITE = Color3.new(1, 1, 1)

-- Floor layers: the world's grass is at y = 0; no two floor layers are coplanar, and a slab lying
-- on another stands >= 0.15 above it (no shimmer from across the lagoon).
local LAWN = 0.2 -- plot lawn slab
local STRIPE = 0.35 -- mowed lawn stripes
local GRAVEL = 0.5 -- side paths, the work yard
local PATH = 0.65 -- the cobble main path, the seating patio
local PLAZA = 0.8 -- spawn square
local PLAZA_IN = 0.95 -- its light inner square (the SpawnPad sits on it)
local COURT_RIM = 0.8 -- aquarium court: stone rim
local COURT = 1.0 -- its cobble paving
local APRON = 1.15 -- light paving round the tank and up to it
local DECK = 0.6 -- pier and platform deck top
local PLANK = 0.75 -- plank strips on the decks

------------------------------------------------------------------------------------------
-- Part helpers
------------------------------------------------------------------------------------------

local function merge(a: { [string]: any }?, b: { [string]: any }?): { [string]: any }
	local out: { [string]: any } = {}
	for _, t in { a, b } do
		if t then
			for k, v in t do
				out[k] = v
			end
		end
	end
	return out
end

-- Same rule as BaseService: shade > 0 lerps towards white, < 0 darkens in HSV.
local function shadeColor(color: any, shade: number): any
	if shade > 0 then
		return color:Lerp(WHITE, math.min(shade, 1))
	elseif shade < 0 then
		local amount = math.min(-shade, 1)
		local h, s, v = color:ToHSV()
		if h > 0.02 and h < 0.2 then
			h -= 0.04 * amount
		end
		return U.Color3.fromHSV(h, math.min(1, s * (1 + 0.15 * amount)), v * (1 - 0.6 * amount))
	end
	return color
end

local DECOR = { CanCollide = false, CastShadow = false }
local NEON = { Material = M.Neon, CastShadow = false }
local NEON_DECOR = { Material = M.Neon, CastShadow = false, CanCollide = false }
local GLASS = { Material = M.Glass, Transparency = 0.3, CastShadow = false }

--[[
	Creates a part. `paint` is a Color3 for a plain part, or a number for an Accent part
	(the number is its AccentShade; 0 = the base colour itself). opts may hold any part
	property (Material, Transparency, CanCollide, Shape, ...) plus `wedge = true`.
	Small or thin parts never cast shadows (cheaper, and their shadows look noisy).
]]
local function make(parent: any, name: string, size: any, cf: any, paint: any, opts: { [string]: any }?): any
	local props = merge(opts, nil)
	local isWedge = props.wedge == true
	props.wedge = nil
	local color = paint
	if typeof(paint) == "number" then
		local attributes: { [string]: any } = { Accent = true }
		if paint ~= 0 then
			attributes.AccentShade = paint
		end
		props.Attributes = merge(props.Attributes, attributes)
		color = shadeColor(ACCENT_DEFAULT, paint)
	end
	if props.CastShadow == nil then
		local minSide = math.min(size.X, size.Y, size.Z)
		local maxSide = math.max(size.X, size.Y, size.Z)
		if minSide <= 0.5 or maxSide <= 2.2 then
			props.CastShadow = false
		end
	end
	local material = props.Material
	props.Material = nil
	if isWedge then
		return U.wedge(parent, name, size, cf, color, material, props)
	end
	return U.part(parent, name, size, cf, color, material, props)
end

-- Axis-aligned block from its min/max corners (template space; corners may come in any order).
local function span(
	parent: any,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	paint: any,
	opts: { [string]: any }?
): any
	local size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	return make(parent, name, size, CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), paint, opts)
end

-- Block centred at (x, y, z) of a local frame; size (sx, sy, sz).
local function box(
	parent: any,
	name: string,
	frame: any,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	paint: any,
	opts: { [string]: any }?
): any
	return make(parent, name, Vector3.new(sx, sy, sz), frame * CFrame.new(x, y, z), paint, opts)
end

-- Upright cylinder (axis along the frame's Y) centred at cf.
local function cylY(parent: any, name: string, d: number, h: number, cf: any, paint: any, opts: { [string]: any }?): any
	local props = merge(opts, { Shape = Enum.PartType.Cylinder })
	return make(parent, name, Vector3.new(h, d, d), cf * CFrame.Angles(0, 0, rad(90)), paint, props)
end

local function at(x: number, y: number, z: number): any
	return CFrame.new(x, y, z)
end

-- Frame at (x, y, z) whose local -Z (front) looks along yaw degrees (0 = -Z, 90 = -X, 180 = +Z,
-- -90 = +X).
local function facing(x: number, y: number, z: number, yaw: number): any
	return CFrame.new(x, y, z) * CFrame.Angles(0, rad(yaw), 0)
end

local IDENTITY = CFrame.new()

--[[
	Wedge filling the box [x0, x1] x [y0, y1] x [z0, z1] of `frame`, its slope descending
	towards `down` ("-z" | "+z" | "-x" | "+x"); the full upright face is on the opposite side.
]]
local function rampIn(
	parent: any,
	name: string,
	frame: any,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	down: string,
	paint: any,
	opts: { [string]: any }?
): any
	local w, h, d = math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0)
	local yaw, size
	if down == "-z" then
		yaw, size = 0, Vector3.new(w, h, d)
	elseif down == "+z" then
		yaw, size = 180, Vector3.new(w, h, d)
	elseif down == "-x" then
		yaw, size = 90, Vector3.new(d, h, w)
	else
		yaw, size = -90, Vector3.new(d, h, w)
	end
	local cf = frame * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2) * CFrame.Angles(0, rad(yaw), 0)
	return make(parent, name, size, cf, paint, merge(opts, { wedge = true }))
end

local function ramp(
	parent: any,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	down: string,
	paint: any,
	opts: { [string]: any }?
): any
	return rampIn(parent, name, IDENTITY, x0, x1, y0, y1, z0, z1, down, paint, opts)
end

-- Attachment on `part` placed at template-space CFrame `cf`; returns it and its offset
-- (reported to the post-build self-check in tools/build.luau).
local function attachAt(part: any, name: string, cf: any): (any, any)
	local rel = part.CFrame:Inverse() * cf
	local attachment = U.new("Attachment", { Name = name, CFrame = rel }, part)
	return attachment, rel.Position
end

------------------------------------------------------------------------------------------
-- Signs
------------------------------------------------------------------------------------------

local function surfaceGui(part: any, name: string, face: any, pixelsPerStud: number): any
	return U.new("SurfaceGui", {
		Name = name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = pixelsPerStud,
		LightInfluence = 0,
	}, part)
end

-- TextLabel filling a horizontal band [top, top + height] (scale) of its parent.
local function textBand(
	parent: any,
	name: string,
	text: string,
	color: any,
	top: number,
	height: number,
	stroke: boolean
): any
	return U.new("TextLabel", {
		Name = name,
		Position = UDim2.fromScale(0.04, top),
		Size = UDim2.fromScale(0.92, height),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = color,
		TextStrokeColor3 = C.Ink,
		TextStrokeTransparency = if stroke then 0 else 1,
	}, parent)
end

-- One-line text sign on a face of `part`.
local function plainText(part: any, face: any, text: string, color: any, stroke: boolean)
	local gui = surfaceGui(part, "Sign" .. face.Name, face, 40)
	textBand(gui, "Text", text, color, 0.1, 0.8, stroke)
end

------------------------------------------------------------------------------------------
-- Building kit: gable roofs, windows, lanterns
------------------------------------------------------------------------------------------

--[[
	Gable roof over the wall box x0..x1 x z0..z1 with its eaves at y0 and the ridge along X
	(alongX) or Z. e = eave overhang on the long sides, g = how far the roof runs past the gable
	walls, h = rise. Two Accent slopes, an eave fascia on each long side and a ridge beam (darker
	Accent), and on each end a gable triangle in `gable` colour standing in the plane of the roof's
	end (a jettied gable: the caller puts a beam under it); the roof's end shows as a thick band
	above the triangle. 9 parts. Returns the ridge height.
]]
local function gableRoof(
	parent: any,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	y0: number,
	h: number,
	e: number,
	g: number,
	alongX: boolean,
	gable: any
): number
	local top = y0 + h
	if alongX then
		local zc = (z0 + z1) / 2
		local half = (z1 - z0) / 2
		local hg = h * half / (half + e)
		ramp(parent, "Roof", x0 - g, x1 + g, y0, top, z0 - e, zc, "-z", ROOF)
		ramp(parent, "Roof", x0 - g, x1 + g, y0, top, zc, z1 + e, "+z", ROOF)
		span(parent, "Fascia", x0 - g - 0.2, x1 + g + 0.2, y0 - 0.4, y0 + 0.7, z0 - e - 0.3, z0 - e + 0.9, ROOF_TRIM)
		span(parent, "Fascia", x0 - g - 0.2, x1 + g + 0.2, y0 - 0.4, y0 + 0.7, z1 + e - 0.9, z1 + e + 0.3, ROOF_TRIM)
		span(parent, "Ridge", x0 - g - 0.3, x1 + g + 0.3, top - 0.6, top + 0.6, zc - 0.9, zc + 0.9, ROOF_TRIM)
		for _, xs in { { x0 - g - 0.1, x0 - g + 0.5 }, { x1 + g - 0.5, x1 + g + 0.1 } } do
			ramp(parent, "Gable", xs[1], xs[2], y0, y0 + hg, z0, zc, "-z", gable)
			ramp(parent, "Gable", xs[1], xs[2], y0, y0 + hg, zc, z1, "+z", gable)
		end
	else
		local xc = (x0 + x1) / 2
		local half = (x1 - x0) / 2
		local hg = h * half / (half + e)
		ramp(parent, "Roof", x0 - e, xc, y0, top, z0 - g, z1 + g, "-x", ROOF)
		ramp(parent, "Roof", xc, x1 + e, y0, top, z0 - g, z1 + g, "+x", ROOF)
		span(parent, "Fascia", x0 - e - 0.3, x0 - e + 0.9, y0 - 0.4, y0 + 0.7, z0 - g - 0.2, z1 + g + 0.2, ROOF_TRIM)
		span(parent, "Fascia", x1 + e - 0.9, x1 + e + 0.3, y0 - 0.4, y0 + 0.7, z0 - g - 0.2, z1 + g + 0.2, ROOF_TRIM)
		span(parent, "Ridge", xc - 0.9, xc + 0.9, top - 0.6, top + 0.6, z0 - g - 0.3, z1 + g + 0.3, ROOF_TRIM)
		for _, zs in { { z0 - g - 0.1, z0 - g + 0.5 }, { z1 + g - 0.5, z1 + g + 0.1 } } do
			ramp(parent, "Gable", x0, xc, y0, y0 + hg, zs[1], zs[2], "-x", gable)
			ramp(parent, "Gable", xc, x1, y0, y0 + hg, zs[1], zs[2], "+x", gable)
		end
	end
	return top
end

--[[
	Window on a wall. `wf`: frame at the window's centre on the wall's outer face, local -Z out of
	the wall, X along it. A dark timber frame proud of the wall and a glass panel; "simple" adds a
	mullion and a stone sill, "full" a mullion, Accent shutters and a flower box (`bloom`).
	small 2 / simple 4 / full 7 parts.
]]
local function window(parent: any, wf: any, w: number, h: number, kind: string, bloom: any?)
	box(parent, "WindowFrame", wf, 0, 0, -0.15, w + 0.9, h + 0.9, 0.3, C.WoodDark)
	box(parent, "Window", wf, 0, 0, -0.37, w, h, 0.14, C.WindowGlass, GLASS)
	if kind == "small" then
		return
	end
	box(parent, "Mullion", wf, 0, 0, -0.5, 0.35, h, 0.12, C.WoodDark, DECOR)
	if kind == "simple" then
		box(parent, "Sill", wf, 0, -h / 2 - 0.65, -0.45, w + 1.4, 0.4, 0.9, C.StoneLight)
		return
	end
	for _, sx in { -1, 1 } do
		box(parent, "Shutter", wf, sx * (w / 2 + 1.15), 0, -0.2, 1.4, h + 0.6, 0.4, SHUTTER)
	end
	box(parent, "FlowerBox", wf, 0, -h / 2 - 1.05, -0.6, w + 1.0, 1.1, 1.2, C.Wood)
	box(parent, "Flowers", wf, 0, -h / 2 - 0.2, -0.6, w + 0.4, 0.7, 0.8, bloom or P.Flowers[1], DECOR)
end

-- Flower bed: a soil box, leafy plants and two clumps of blooms on top (`bloom` and `bloom2`,
-- at the two ends of the bed's long side). 4 parts.
local function flowerBed(parent: any, x0: number, x1: number, z0: number, z1: number, bloom: any, bloom2: any)
	span(parent, "FlowerBed", x0, x1, 0, 0.8, z0, z1, C.Soil)
	span(parent, "Plants", x0 + 0.3, x1 - 0.3, 0.8, 1.6, z0 + 0.3, z1 - 0.3, C.Leaf2, DECOR)
	local alongX = (x1 - x0) >= (z1 - z0)
	for i, c in { bloom, bloom2 } do
		local a, b = if i == 1 then 0.12 else 0.56, if i == 1 then 0.44 else 0.9
		local h = if i == 1 then 2.3 else 2.1
		if alongX then
			span(parent, "Blooms", x0 + (x1 - x0) * a, x0 + (x1 - x0) * b, 1.5, h, z0 + 0.5, z1 - 0.5, c, DECOR)
		else
			span(parent, "Blooms", x0 + 0.5, x1 - 0.5, 1.5, h, z0 + (z1 - z0) * a, z0 + (z1 - z0) * b, c, DECOR)
		end
	end
end

-- Lantern post: a timber post with a glowing cube lantern under an iron cap. 3 parts.
local function lanternPost(parent: any, x: number, z: number, base: number, h: number, light: boolean?)
	span(parent, "LanternPost", x - 0.45, x + 0.45, base - 0.2, base + h, z - 0.45, z + 0.45, C.WoodDark)
	local glow =
		span(parent, "Lantern", x - 0.8, x + 0.8, base + h, base + h + 1.6, z - 0.8, z + 0.8, C.Glow, NEON_DECOR)
	span(parent, "LanternCap", x - 1.15, x + 1.15, base + h + 1.6, base + h + 2.2, z - 1.15, z + 1.15, C.Iron, DECOR)
	if light then
		U.new("PointLight", { Range = 14, Brightness = 1.1, Color = C.LightColor, Shadows = false }, glow)
	end
end

------------------------------------------------------------------------------------------
-- Ground: lawn, paths, spawn square, aquarium court
------------------------------------------------------------------------------------------

local SPAWN_Z = 36

local function buildGrounds(template: any, plot: any)
	local floor = U.model(template, "Grounds")
	local hw, front, back = plot.halfWidth, plot.front, plot.back

	-- Lawn over the whole plot (the fence and the hedge stand on it), with faint mowed stripes.
	span(floor, "Lawn", -hw + 0.4, hw - 0.4, -0.4, LAWN, front + 0.4, back - 0.4, C.Lawn)
	for z = front + 33, back - 44, 24 do
		span(floor, "LawnStripe", -hw + 1, hw - 1, LAWN - 0.1, STRIPE, z, z + 8, C.LawnStripe)
	end

	-- Cobble main path on the centre line, gate -> spawn square -> court -> porch steps.
	span(floor, "Path", -5, 5, 0, PATH, front, 131, C.Path)
	-- Gravel side paths: spawn square -> garden (-X) and -> doghouse (+X); the cross path in front
	-- of the cottage (court -> seating patio / work yard).
	span(floor, "GardenPath", -31, -11.9, 0, GRAVEL, 39, 43, C.Gravel)
	span(floor, "DogPath", 11.9, 44.4, 0, GRAVEL, 39, 43, C.Gravel)
	span(floor, "CrossPath", -41, 41, 0, GRAVEL, 131.2, 136.2, C.Gravel)

	-- Spawn square: cobble with a light inner square; the pad itself is built by buildSpawn.
	span(floor, "SpawnSquare", -12, 12, 0, PLAZA, SPAWN_Z - 11, SPAWN_Z + 11, C.Path)
	span(floor, "SpawnInner", -7.5, 7.5, 0, PLAZA_IN, SPAWN_Z - 7.5, SPAWN_Z + 7.5, C.StoneLight)

	-- Aquarium court: cobble on a darker stone rim, a light apron round the tank and up to it.
	span(floor, "CourtRim", -43.4, 43.4, 0, COURT_RIM, 52.6, 131.4, C.Stone, { CastShadow = true })
	span(floor, "Court", -42.2, 42.2, 0, COURT, 53.8, 130.2, C.Path)
	span(floor, "Apron", -16.6, 16.6, 0, APRON, 66, 117, C.StoneLight)
	span(floor, "Approach", -5, 5, 0, APRON, 53.4, 66.1, C.StoneLight)
	for _, sx in { -1, 1 } do
		local xa, xb = math.min(sx * 26.6, sx * 37.4), math.max(sx * 26.6, sx * 37.4)
		span(floor, "SlotRow", xa, xb, 0, APRON, 58.6, 124.4, C.StoneLight)
	end

	-- Flower beds just inside the gate.
	for _, sx in { -1, 1 } do
		local xa, xb = math.min(sx * 5.6, sx * 9.6), math.max(sx * 5.6, sx * 9.6)
		flowerBed(floor, xa, xb, 22.6, 24.9, P.Flowers[if sx < 0 then 3 else 2], P.Flowers[5])
	end
end

------------------------------------------------------------------------------------------
-- Fence (stone base course + timber rails) and the back hedge
------------------------------------------------------------------------------------------

local function buildFence(template: any, plot: any)
	local fence = U.model(template, "Fence")
	local hw, front, back = plot.halfWidth, plot.front, plot.back
	local line = hw - 1.4 -- side fence centre line
	local fz = front + 1.6 -- front fence centre line
	local hedgeZ = back - 3.4 -- the hedge's front face

	-- A straight run along X or Z: stone base from a0 to a1, two rails from a0 to r1 (inside the
	-- last post), posts.
	local function run(alongX: boolean, a0: number, a1: number, r1: number, c: number, posts: { number })
		local function blk(name: string, u0: number, u1: number, y0: number, y1: number, half: number, color: any)
			if alongX then
				span(fence, name, u0, u1, y0, y1, c - half, c + half, color)
			else
				span(fence, name, c - half, c + half, y0, y1, u0, u1, color)
			end
		end
		blk("StoneBase", a0, a1, 0, 1.5, 0.8, C.Stone)
		blk("RailLow", a0, r1, 2.3, 2.8, 0.25, C.Wood)
		blk("RailTop", a0, r1, 3.7, 4.3, 0.3, C.Wood)
		for _, u in posts do
			blk("Post", u - 0.55, u + 0.55, 0, 4.9, 0.55, C.WoodDark)
		end
	end

	-- Front, either side of the gate (the gate piers end at x = +-16).
	for _, sx in { -1, 1 } do
		local posts = {}
		for _, x in { 33, 50, line } do
			table.insert(posts, sx * x)
		end
		run(true, sx * 16, sx * (line + 0.8), sx * line, fz, posts)
	end
	-- Sides, from the front fence to the hedge.
	for _, sx in { -1, 1 } do
		local posts = {}
		local z0, z1 = fz + 0.55, hedgeZ
		local n = 7
		for i = 1, n do
			table.insert(posts, z0 + (z1 - z0) * i / n)
		end
		run(false, z0 - 0.55, z1, z1, sx * line, posts)
	end
	-- Tall clipped hedge along the back (behind the cottage), lighter on top.
	span(fence, "Hedge", -hw + 0.6, hw - 0.6, 0, 4.2, hedgeZ, back - 0.2, C.Hedge, { CastShadow = true })
	span(fence, "HedgeTop", -hw + 1, hw - 1, 4.2, 5, hedgeZ + 0.4, back - 0.6, C.HedgeTop, { CanCollide = false })
end

------------------------------------------------------------------------------------------
-- Entrance gate: stone piers, a timber frame with the owner's name board under a little roof
------------------------------------------------------------------------------------------

local function signFace(board: any, face: any)
	local gui = surfaceGui(board, "Sign" .. face.Name, face, 32)
	textBand(gui, "OwnerLabel", "Свободно", C.Ink, 0.08, 0.54, false)
	textBand(gui, "BaseLabel", "База", C.White, 0.64, 0.3, true)
end

local function buildGate(template: any, plot: any)
	local gate = U.model(template, "Gate")
	local z0 = plot.front
	local zc = z0 + 2.2
	for _, sx in { -1, 1 } do
		local lo, hi = math.min(sx * 11.4, sx * 16), math.max(sx * 11.4, sx * 16)
		local xm = (lo + hi) / 2
		span(gate, "Pier", lo, hi, 0, 8, z0, z0 + 4.4, C.Stone, { CastShadow = true })
		span(gate, "PierCap", lo - 0.4, hi + 0.4, 8, 9, z0 - 0.4, z0 + 4.8, C.StoneLight)
		local lamp = span(gate, "Lantern", xm - 0.9, xm + 0.9, 9, 10.9, zc - 0.9, zc + 0.9, C.Glow, NEON)
		span(gate, "LanternCap", xm - 1.3, xm + 1.3, 10.9, 11.6, zc - 1.3, zc + 1.3, C.Iron)
		if sx > 0 then
			U.new("PointLight", { Range = 16, Brightness = 1.1, Color = C.LightColor, Shadows = false }, lamp)
		end
		-- the timber frame's post, against the pier's inner face
		local px = sx * 10.7
		span(gate, "Post", px - 0.8, px + 0.8, 0, 15.2, zc - 0.8, zc + 0.8, C.WoodDark, { CastShadow = true })
	end
	span(gate, "Beam", -12.2, 12.2, 15.2, 16.6, zc - 1.1, zc + 1.1, C.WoodDark, { CastShadow = true })
	-- Name board (both faces) in an Accent frame, under a little Accent gable roof.
	span(gate, "BoardFrame", -9.6, 9.6, 16.2, 23.2, zc - 0.4, zc + 0.4, 0)
	local board = span(gate, "Board", -8.8, 8.8, 16.6, 22.8, zc - 0.6, zc + 0.6, C.Cream)
	signFace(board, Enum.NormalId.Front) -- faces the promenade
	signFace(board, Enum.NormalId.Back) -- faces the yard
	ramp(gate, "Roof", -11.6, 11.6, 23.2, 26, zc - 2.6, zc, "-z", ROOF, { CastShadow = true })
	ramp(gate, "Roof", -11.6, 11.6, 23.2, 26, zc, zc + 2.6, "+z", ROOF)
	span(gate, "Ridge", -11.8, 11.8, 25.5, 26.5, zc - 0.6, zc + 0.6, ROOF_TRIM)
	-- Gold fish weathervane on the ridge (the game's mascot), glinting now and then.
	span(gate, "VaneRod", -0.2, 0.2, 26.5, 27.6, zc - 0.2, zc + 0.2, C.Iron, DECOR)
	local fish = span(gate, "VaneFish", -2, 1.6, 27.6, 29.3, zc - 0.25, zc + 0.25, C.Gold, DECOR)
	span(gate, "VaneTail", 1.6, 2.8, 27.3, 29.6, zc - 0.2, zc + 0.2, C.Gold, DECOR)
	Props.fx(fish, "sparkle", { rate = 1, size = 1.2 })
end

------------------------------------------------------------------------------------------
-- Front yard: spawn pad, flag, signal mast, mailbox
------------------------------------------------------------------------------------------

local function buildSpawn(template: any)
	-- The pad: -Z (the lagoon) is the facing on spawn. Pure base colour (tests check it).
	span(template, "SpawnPad", -4, 4, PLAZA_IN, PLAZA_IN + 0.4, SPAWN_Z - 4, SPAWN_Z + 4, 0, { CastShadow = false })
end

-- The base's beacon: a tall white mast (the highest point of the base, seen across the lagoon)
-- with a big base-colour flag (a light band across it) and the owner billboard above it.
local function buildFlag(template: any): any
	local flag = U.model(template, "Flag")
	local fx, fz = -20, 31
	span(flag, "Plinth", fx - 2.6, fx + 2.6, 0, 1.2, fz - 2.6, fz + 2.6, C.Stone)
	span(flag, "PlinthTop", fx - 1.8, fx + 1.8, 1.2, 2.0, fz - 1.8, fz + 1.8, C.StoneLight)
	local poleBottom, poleTop = 2.0, 50
	local poleH = poleTop - poleBottom
	local pole = cylY(flag, "Pole", 1.1, poleH, at(fx, (poleTop + poleBottom) / 2, fz), C.Cream, { CastShadow = true })
	span(flag, "Finial", fx - 0.8, fx + 0.8, poleTop, poleTop + 1.6, fz - 0.8, fz + 0.8, C.Gold, DECOR)
	-- The flag flies towards +X (over the spawn square): cloth, a light band, a darker tail.
	local clothTop = poleTop - 0.8
	local cx = fx + 0.55 + 6
	make(flag, "Cloth", Vector3.new(12, 7, 0.5), at(cx, clothTop - 3.5, fz), 0, { CanCollide = false })
	make(flag, "ClothBand", Vector3.new(11.6, 1.6, 0.6), at(cx + 0.1, clothTop - 3.5, fz), 0.55, DECOR)
	make(
		flag,
		"ClothTip",
		Vector3.new(4.4, 5.8, 0.5),
		at(fx + 12.6 + 2.1, clothTop - 3.6, fz) * CFrame.Angles(0, rad(-12), 0),
		-0.18,
		{ CanCollide = false }
	)

	-- Owner sign above the mast (BaseService writes the owner name / base name).
	-- The pole is a cylinder (local X = up), so the offset is along local X.
	local signOffset = Vector3.new(poleH / 2 + 6.5, 0, 0)
	local attachment = U.new("Attachment", { Name = "SignAttachment", CFrame = CFrame.new(signOffset) }, pole)
	local sign = U.new("BillboardGui", {
		Name = "OwnerSign",
		Size = UDim2.new(16, 0, 5, 0), -- studs
		LightInfluence = 0,
		MaxDistance = 250,
		AlwaysOnTop = false,
	}, attachment)
	for _, spec in { { "OwnerLabel", "Свободно", 0, 0.6 }, { "BaseLabel", "База", 0.6, 0.4 } } do
		U.new("TextLabel", {
			Name = spec[1],
			Position = UDim2.fromScale(0, spec[3]),
			Size = UDim2.fromScale(1, spec[4]),
			BackgroundTransparency = 1,
			Text = spec[2],
			TextScaled = true,
			FontFace = U.FONT,
			TextColor3 = C.White,
			TextStrokeColor3 = C.Ink,
			TextStrokeTransparency = 0.2,
		}, sign)
	end
	return signOffset
end

-- Signal mast: stone foot, timber post, a platform carrying the alarm lamp (Alarm.Lamp, dark
-- until stage 4 lights it) under a small Accent cap, two iron horns and a bell.
local function buildAlarm(template: any)
	local alarm = U.model(template, "Alarm")
	local ax, az = 20, 31
	span(alarm, "Foot", ax - 2, ax + 2, 0, 1.2, az - 2, az + 2, C.Stone)
	span(alarm, "Post", ax - 0.7, ax + 0.7, 1.2, 13, az - 0.7, az + 0.7, C.WoodDark, { CastShadow = true })
	span(alarm, "Platform", ax - 2, ax + 2, 13, 13.6, az - 2, az + 2, C.Wood)
	span(alarm, "Lamp", ax - 1.3, ax + 1.3, 13.6, 16.2, az - 1.3, az + 1.3, C.LampOff, { CastShadow = false })
	span(alarm, "Cap", ax - 1.9, ax + 1.9, 16.2, 17, az - 1.9, az + 1.9, -0.2)
	span(alarm, "Finial", ax - 0.4, ax + 0.4, 17, 17.8, az - 0.4, az + 0.4, C.Iron, DECOR)
	for _, sx in { -1, 1 } do
		span(alarm, "Horn", ax + sx * 2, ax + sx * 3.2, 14.2, 15.4, az - 0.6, az + 0.6, C.Iron, DECOR)
	end
	span(alarm, "Bell", ax - 0.6, ax + 0.6, 11.4, 12.6, az - 1.9, az - 0.7, C.Gold, DECOR)
end

local function buildMailbox(template: any)
	local yard = U.model(template, "Mailbox")
	span(yard, "MailPost", 17.4, 18.2, 0, 3.6, 24.6, 25.4, C.WoodDark)
	span(yard, "Mailbox", 16.7, 18.9, 3.6, 5.3, 23.8, 26.2, 0)
end

------------------------------------------------------------------------------------------
-- Aquarium: the big tank and the 12 display pedestals
------------------------------------------------------------------------------------------

local TANK_HALF_X = 12
local TANK_Z0, TANK_Z1 = 71.5, 111.5
local TANK_BASE = APRON + 1.9 -- plinth top = glass bottom
local TANK_TOP = TANK_BASE + 11
local SLOT_ROW_X = 32
local SLOT_Z0, SLOT_PITCH = 64, 11

local function buildTank(template: any): (any, { any })
	local tank = U.model(template, "Tank")
	local hx = TANK_HALF_X
	local expected = {}

	-- Stone plinth with a lighter ledge.
	span(tank, "Plinth", -hx - 2, hx + 2, APRON - 0.1, TANK_BASE - 0.6, TANK_Z0 - 2, TANK_Z1 + 2, C.Stone)
	span(tank, "Ledge", -hx - 1.2, hx + 1.2, TANK_BASE - 0.6, TANK_BASE, TANK_Z0 - 1.2, TANK_Z1 + 1.2, C.StoneLight)

	-- The glass (one part = the whole water volume; fish swim inside it later): almost clear, so
	-- the reef keeps its colours from across the court.
	local glass = span(tank, "Glass", -hx, hx, TANK_BASE, TANK_TOP, TANK_Z0, TANK_Z1, C.TankGlass, {
		Material = M.Glass,
		Transparency = 0.72,
		CastShadow = false,
	})
	tank.PrimaryPart = glass
	-- Stage 3/4 prompts: in front of the tank's entrance end (towards the gate).
	local _, promptOffset = attachAt(glass, "PromptAttachment", at(0, APRON + 2, TANK_Z0 - 3))
	table.insert(expected, { root = "template", path = { "Tank", "Glass", "PromptAttachment" }, offset = promptOffset })

	-- Timber frame: corner and middle posts, a rim round the top edges.
	local postTop = TANK_TOP + 1
	local zm = (TANK_Z0 + TANK_Z1) / 2
	for _, sx in { -1, 1 } do
		for _, z in { TANK_Z0, zm, TANK_Z1 } do
			local w = if z == zm then 0.6 else 0.85
			span(tank, "Post", sx * hx - w, sx * hx + w, TANK_BASE, postTop, z - w, z + w, C.WoodDark)
		end
		span(tank, "Rim", sx * hx - 0.6, sx * hx + 0.6, TANK_TOP, TANK_TOP + 0.7, TANK_Z0, TANK_Z1, C.WoodDark)
	end
	for _, z in { TANK_Z0, TANK_Z1 } do
		span(tank, "Rim", -hx + 0.6, hx - 0.6, TANK_TOP, TANK_TOP + 0.7, z - 0.6, z + 0.6, C.WoodDark)
	end
	-- Name board standing on the rim of the entrance end.
	local signY = TANK_TOP + 0.7
	span(tank, "SignFrame", -7.6, 7.6, signY - 0.2, signY + 4.4, TANK_Z0 - 0.3, TANK_Z0 + 0.3, C.WoodDark)
	local board = span(tank, "SignBoard", -7, 7, signY + 0.3, signY + 3.9, TANK_Z0 - 0.5, TANK_Z0 + 0.5, C.WoodLight)
	plainText(board, Enum.NormalId.Front, "АКВАРИУМ", C.Ink, false)

	-- Inside: a sand bed and a deep-blue backdrop wall along the middle, so each long side reads as
	-- a lit reef aquarium (also when no fish are on display). The entrance end, seen from the
	-- spawn, is the show window: a little castle in the middle (it hides the backdrop's end), an
	-- open treasure chest and an orange coral either side of it, a yellow fish swimming across.
	-- Along the sides: branching corals, wavy kelp, columns of rising bubbles (particles), fish, a
	-- purple sea fan and a yellow brain coral. A soft PointLight on the backdrop lights it all.
	local s = TANK_BASE + 1 -- sand top
	local sand = span(tank, "Sand", -hx + 0.2, hx - 0.2, TANK_BASE, s, TANK_Z0 + 0.2, TANK_Z1 - 0.2, C.Sand, DECOR)
	local backdrop = span(tank, "Backdrop", -0.3, 0.3, s - 0.2, TANK_TOP - 0.6, 78.4, TANK_Z1 - 4, C.SeaDeep, DECOR)
	U.new("PointLight", { Range = 16, Brightness = 1, Color = C.ReefLight, Shadows = false }, backdrop)
	local function piece(
		name: string,
		x0: number,
		x1: number,
		y0: number,
		y1: number,
		z0: number,
		z1: number,
		paint: any
	)
		span(tank, name, x0, x1, s + y0, s + y1, z0, z1, paint, DECOR)
	end
	-- Branching coral: a fat base (w x 0.9w), a tall and a short arm, a light tip on the tall arm.
	-- (x, z) = the base's -X/-Z corner; flip puts the tall arm on the +X side.
	local function coral(x: number, z: number, w: number, high: number, base: any, arm: any, tip: any, flip: boolean)
		local d = w * 0.9
		local a = if flip then w - 2.3 else 0.3 -- tall arm (2 wide)
		local b = if flip then 0.4 else w - 2.0 -- short arm (1.6 wide)
		piece("Coral", x, x + w, -0.2, 2.6, z, z + d, base)
		piece("CoralArm", x + a, x + a + 2, 2.6, high, z + 0.8, z + 2.8, arm)
		piece("CoralArm", x + b, x + b + 1.6, 2.6, high - 2.6, z + d - 2, z + d - 0.4, arm)
		piece("CoralTip", x + a - 0.4, x + a + 2.4, high, high + 1.1, z + 0.4, z + 3.2, tip)
	end
	-- Wavy kelp: two stacked blocks shifted against each other.
	local function kelp(x: number, z: number, dx: number)
		piece("Kelp", x, x + 1.6, -0.2, 4.4, z, z + 1.6, C.Kelp1)
		piece("Kelp", x + dx, x + dx + 1.6, 4.2, 8.4, z + 0.3, z + 1.9, C.Kelp2)
	end
	-- Voxel fish: a body and a tall tail fin behind it. Swims along Z (dir = +1 towards +Z, -1
	-- towards -Z), or along X with acrossX (dir = +1 towards +X), showing its side to the spawn.
	local function fish(x: number, y: number, z: number, dir: number, body: any, tail: any, acrossX: boolean?)
		if acrossX then
			piece("Fish", x - 1.6, x + 1.6, y - 1, y + 1, z - 1.1, z + 1.1, body)
			local tx = x - dir * 2.3
			piece("FishTail", tx - 0.7, tx + 0.7, y - 1.2, y + 1.2, z - 0.25, z + 0.25, tail)
		else
			piece("Fish", x - 1.1, x + 1.1, y - 1, y + 1, z - 1.6, z + 1.6, body)
			local tz = z - dir * 2.3
			piece("FishTail", x - 0.25, x + 0.25, y - 1.2, y + 1.2, tz - 0.7, tz + 0.7, tail)
		end
	end
	-- A column of bubbles rising off the sand (particles: they move and cost no parts). They live
	-- at most 3 s (at most 2.8 studs/s), so they fade out under the glass top.
	local function bubbles(name: string, x: number, z: number)
		local attachment, offset = attachAt(sand, name, at(x, s + 0.4, z))
		Props.fx(attachment, "bubbles", { rate = 3, size = 1.5, lifetime = U.roblox.NumberRange.new(2.6, 3) })
		table.insert(expected, { root = "template", path = { "Tank", "Sand", name }, offset = offset })
	end

	-- The entrance end: castle, open treasure chest (-X), orange coral (+X), a yellow tang above.
	piece("Castle", -3, 3, -0.2, 6.6, 73.4, 78.8, C.StoneLight)
	piece("CastleRoof", -3.6, 3.6, 6.6, 7.8, 72.9, 79.3, C.RoofBlue)
	piece("CastleDoor", -1, 1, 0, 3.2, 73.2, 73.4, C.Ink)
	piece("Chest", -10.4, -5.8, -0.2, 2.6, 73.2, 76.8, C.Wood)
	piece("ChestGold", -10, -6.2, 2.6, 3.4, 73.6, 76.4, C.Gold)
	coral(5.8, 73.2, 5, 7.6, C.CoralOrangeBase, C.CoralOrange, C.CoralOrangeTip, true)
	fish(-6.4, 8.2, 80.5, 1, C.Yellow, C.Blue, true)
	-- -X side (seen from the odd slot row): pink coral, bubbles, kelp, clownfish, purple sea fan.
	coral(-10.6, 83, 5, 8.4, C.CoralPinkBase, C.CoralPink, C.CoralPinkTip, false)
	bubbles("BubblesWest", -3.2, 88.5)
	kelp(-4.6, 93, 0.5)
	fish(-7, 7.2, 97, -1, C.Orange, C.White)
	piece("SeaFan", -9, -8.2, -0.2, 7.4, 101, 108.5, C.SeaFan)
	-- +X side (seen from the even slot row): kelp, blue tang, bubbles, yellow brain coral.
	kelp(2.6, 81.5, -0.5)
	fish(6.6, 8, 90, 1, C.Blue, C.Yellow)
	bubbles("BubblesEast", 3, 99)
	piece("BrainCoral", 5.6, 10.4, -0.2, 2.8, 103.5, 108.5, C.BrainCoral)

	return tank, expected
end

-- One display pedestal: stone step and plinth, an Accent plate under the glass case, a timber
-- cap. Local frame: -Z faces the aisle.
local function buildSlot(slots: any, index: number, frame: any, expected: { any })
	local slot = U.model(slots, `Slot_{index}`)
	slot:SetAttribute("SlotIndex", index)
	local y0 = COURT
	box(slot, "Step", frame, 0, y0 + 0.5, 0, 9, 1, 9, C.Stone)
	local pedestal = box(slot, "Pedestal", frame, 0, y0 + 2.6, 0, 7, 3.2, 7, C.StoneLight, { CastShadow = true })
	box(slot, "Plate", frame, 0, y0 + 4.6, 0, 8.2, 0.8, 8.2, PEDESTAL_TRIM)
	local display = box(slot, "Display", frame, 0, y0 + 8.1, 0, 6.2, 6.2, 6.2, P.Glass, {
		Material = M.Glass,
		Transparency = 0.6,
		CastShadow = false,
	})
	box(slot, "Cap", frame, 0, y0 + 11.6, 0, 7.2, 0.8, 7.2, C.WoodDark)
	slot.PrimaryPart = pedestal

	-- The fish model floats in the centre of the display; prompts stand in front of the pedestal.
	local fishPoint = U.new("Attachment", { Name = "FishPoint", CFrame = CFrame.new() }, display)
	local _, promptOffset = attachAt(pedestal, "PromptAttachment", frame * at(0, y0 + 2.6, -5))
	local name = slot.Name
	table.insert(expected, {
		root = "template",
		path = { "Tank", "Slots", name, "Display", "FishPoint" },
		offset = fishPoint.CFrame.Position,
	})
	table.insert(expected, {
		root = "template",
		path = { "Tank", "Slots", name, "Pedestal", "PromptAttachment" },
		offset = promptOffset,
	})

	-- Label on the front face: "Пусто" until a fish is put on display.
	local gui = surfaceGui(pedestal, "LabelGui", Enum.NormalId.Front, 50)
	U.new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromScale(0.06, 0.12),
		Size = UDim2.fromScale(0.88, 0.76),
		BackgroundTransparency = 1,
		Text = "Пусто",
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = C.Ink,
	}, gui)
	-- Slot number on the pedestal's back face (seen from behind the row).
	plainText(pedestal, Enum.NormalId.Back, tostring(index), C.Ink, false)
end

local function buildSlots(tank: any, expected: { any })
	local slots = U.folder(tank, "Slots")
	for k = 1, 6 do
		local z = SLOT_Z0 + (k - 1) * SLOT_PITCH
		-- Odd slots on the -X row (front faces +X), even on the +X row (front faces -X).
		buildSlot(slots, 2 * k - 1, facing(-SLOT_ROW_X, 0, z, -90), expected)
		buildSlot(slots, 2 * k, facing(SLOT_ROW_X, 0, z, 90), expected)
	end
end

------------------------------------------------------------------------------------------
-- Doghouse + the hidden guard dog (stage 4 upgrade)
------------------------------------------------------------------------------------------

local DOG_X, DOG_Z = 49, 41

local function buildDogHouse(template: any)
	local house = U.model(template, "DogHouse")
	local f = facing(DOG_X, LAWN, DOG_Z, 90) -- the door looks towards -X (the gravel path)
	box(house, "Floor", f, 0, 0.3, 0, 7.6, 0.6, 7.6, C.WoodDark)
	box(house, "Walls", f, 0, 0.6 + 2.3, 0, 6.4, 4.6, 6.4, C.Wood)
	box(house, "DoorHole", f, 0, 0.6 + 1.6, -3.25, 2.6, 3.2, 0.2, C.Ink, DECOR)
	-- Gable roof in the base colour, ridge along the door axis.
	rampIn(house, "Roof", f, -4.2, 0, 5.2, 8.2, -4.2, 4.2, "-x", ROOF, { CastShadow = true })
	rampIn(house, "Roof", f, 0, 4.2, 5.2, 8.2, -4.2, 4.2, "+x", ROOF)
	box(house, "Ridge", f, 0, 8.0, 0, 1, 0.8, 8.8, ROOF_TRIM)
	local plate = box(house, "NamePlate", f, 0, 4.5, -3.35, 3.2, 1, 0.3, C.Cream, DECOR)
	plainText(plate, Enum.NormalId.Front, "ГАВ!", C.Ink, false)
	cylY(house, "Bowl", 1.9, 0.6, f * at(2.6, 0.3, -5), C.Iron, DECOR)
end

-- Blocky shiba lying by the doghouse; local -Z = where it looks. Hidden (see the header): every
-- part is invisible and takes no collisions, raycasts or shadows; Unlocked = false.
local function buildDog(template: any)
	local dog = U.model(template, "Dog")
	dog:SetAttribute("Unlocked", false)
	local S = 1.5
	local f = facing(DOG_X - 8, LAWN, DOG_Z - 4, 60) -- beside the doghouse door, looking at the path
	local HIDDEN = { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false }
	local function piece(
		name: string,
		x: number,
		y: number,
		z: number,
		sx: number,
		sy: number,
		sz: number,
		color: any
	): any
		return box(dog, name, f, x * S, y * S, z * S, sx * S, sy * S, sz * S, color, HIDDEN)
	end
	local body = piece("Body", 0, 1.35, 0.2, 1.6, 1.3, 2.4, C.Dog)
	piece("Chest", 0, 1.25, -1.05, 1.2, 0.9, 0.3, C.DogCream)
	piece("Head", 0, 2.5, -1.1, 1.9, 1.6, 1.6, C.Dog)
	piece("Muzzle", 0, 2.15, -2.1, 1.1, 0.65, 0.6, C.DogCream)
	piece("Nose", 0, 2.42, -2.45, 0.4, 0.28, 0.2, C.Ink)
	piece("Tongue", 0.15, 1.78, -2.38, 0.3, 0.32, 0.12, C.Tongue)
	for _, sx in { -1, 1 } do
		piece("Eye", sx * 0.46, 2.78, -1.93, 0.26, 0.36, 0.1, C.Ink)
		piece("Ear", sx * 0.6, 3.55, -1.05, 0.5, 0.62, 0.42, C.Dog)
		piece("FrontLeg", sx * 0.45, 0.4, -0.65, 0.5, 0.8, 0.5, C.DogCream)
		piece("BackLeg", sx * 0.45, 0.4, 1.0, 0.5, 0.8, 0.5, C.Dog)
	end
	piece("Tail", 0, 2.1, 1.5, 0.5, 0.7, 0.5, C.Dog)
	piece("TailTip", 0, 2.55, 1.25, 0.62, 0.5, 0.62, C.DogCream)
	piece("Collar", 0, 1.95, -0.8, 1.75, 0.36, 1.2, 0)
	dog.PrimaryPart = body
end

------------------------------------------------------------------------------------------
-- The fisherman's cottage and the smokehouse
------------------------------------------------------------------------------------------

local HOUSE_X0, HOUSE_X1, HOUSE_Z0, HOUSE_Z1 = -17, 17, 142, 162
local FLOOR = 3.0 -- ground floor level (porch deck top)

-- Returns the chimney smoke attachment's offset.
local function buildHouse(template: any): any
	local house = U.model(template, "House")
	local x0, x1, z0, z1 = HOUSE_X0, HOUSE_X1, HOUSE_Z0, HOUSE_Z1
	local wallTop = 15.6
	local eave = wallTop + 0.8
	local zc = (z0 + z1) / 2

	-- Stone base course with a light water-table ledge, plaster walls.
	span(house, "BaseCourse", x0 - 0.6, x1 + 0.6, 0, 2.4, z0 - 0.6, z1 + 0.6, C.Stone, { CastShadow = true })
	span(house, "Ledge", x0 - 0.9, x1 + 0.9, 2.4, 2.9, z0 - 0.9, z1 + 0.9, C.StoneLight)
	span(house, "Walls", x0, x1, 2.9, wallTop, z0, z1, C.Plaster, { CastShadow = true })
	-- Timber: corner posts, the floor band between the storeys, studs on the upper front, the
	-- wall plate (it runs out under the jettied gables).
	for _, x in { x0, x1 } do
		for _, z in { z0, z1 } do
			local xa = if x == x0 then x - 0.35 else x - 0.85
			local za = if z == z0 then z - 0.35 else z - 0.85
			span(house, "Corner", xa, xa + 1.2, 2.9, wallTop, za, za + 1.2, C.WoodDark)
		end
	end
	span(house, "FloorBand", x0 - 0.25, x1 + 0.25, 9, 9.8, z0 - 0.25, z1 + 0.25, C.WoodDark)
	for _, x in { -5.25, 5.25 } do
		span(house, "Stud", x - 0.4, x + 0.4, 9.8, wallTop, z0 - 0.25, z0, C.WoodDark)
	end
	span(house, "WallPlate", x0 - 1.2, x1 + 1.2, wallTop, eave, z0 - 0.3, z1 + 0.3, C.WoodDark, { CastShadow = true })

	-- Roof in the base colour: ridge along X, eaves 2.2 out, plaster gables jettied 1 out.
	gableRoof(house, x0, x1, z0, z1, eave, 10, 2.2, 1, true, C.Plaster)

	-- Gabled dormer on the front slope (over the porch), plaster with a small window.
	local dz0 = z0 + 2
	span(house, "Dormer", -3.6, 3.6, eave + 2, eave + 7.4, dz0, dz0 + 6.5, C.Plaster)
	window(house, at(0, eave + 5.4, dz0), 2.6, 2.2, "small")
	rampIn(house, "DormerRoof", IDENTITY, -4.4, 0, eave + 7.4, eave + 9.4, dz0 - 0.6, dz0 + 6.5, "-x", ROOF)
	rampIn(house, "DormerRoof", IDENTITY, 0, 4.4, eave + 7.4, eave + 9.4, dz0 - 0.6, dz0 + 6.5, "+x", ROOF)

	-- Chimney through the back slope, a lazy plume of smoke above it.
	local chimneyTop = 30.6
	span(house, "Chimney", 10, 13.4, wallTop, chimneyTop, zc + 2.5, zc + 5.9, C.StoneLight, { CastShadow = true })
	local cap = span(house, "ChimneyCap", 9.6, 13.8, chimneyTop, chimneyTop + 0.8, zc + 2.1, zc + 6.3, C.Stone)
	span(house, "ChimneyPot", 11.1, 12.3, chimneyTop + 0.8, chimneyTop + 2, zc + 3.6, zc + 4.8, C.Brick, DECOR)
	local smoke, smokeOffset = attachAt(cap, "SmokeAttachment", at(11.7, chimneyTop + 2.4, zc + 4.2))
	Props.fx(smoke, "smoke", { rate = 2.5 })

	-- Front (-Z): the door between two full windows; three windows upstairs.
	local front = function(x: number, y: number): any
		return at(x, y, z0)
	end
	span(house, "DoorFrame", -2.4, 2.4, 2.9, 9, z0 - 0.3, z0, C.WoodDark)
	span(house, "Door", -1.8, 1.8, 2.9, 8.4, z0 - 0.45, z0 - 0.25, C.Wood)
	span(house, "DoorWindow", -0.8, 0.8, 6.2, 7.6, z0 - 0.55, z0 - 0.4, C.WindowGlass, GLASS)
	span(house, "DoorKnob", 1, 1.5, 5.4, 5.9, z0 - 0.75, z0 - 0.4, C.Gold, DECOR)
	for _, sx in { -1, 1 } do
		window(house, front(sx * 11.8, 6), 3.2, 3.4, "full", if sx < 0 then P.Flowers[1] else P.Flowers[3])
	end
	for _, x in { -10.5, 0, 10.5 } do
		window(house, front(x, 12.9), 3.2, 3.2, "simple")
	end
	-- West gable wall (towards the seating patio): a full window downstairs; attic windows in both
	-- gables.
	window(house, facing(x0, 6, zc, 90), 3.2, 3.4, "full", P.Flowers[2])
	for _, sx in { -1, 1 } do
		local gx = if sx < 0 then x0 - 1.1 else x1 + 1.1
		window(house, facing(gx, 19.4, zc, -90 * sx), 2.4, 2.4, "small")
	end

	-- Porch: deck at floor level, two stone steps, posts, rails, a lean-to Accent roof with a
	-- fascia, a wall lantern by the door; flower beds either side.
	local pz0 = 134.6
	span(house, "Porch", -8, 8, 0, FLOOR, pz0, z0 - 0.1, C.Plank, { CastShadow = true })
	span(house, "Step", -4, 4, 0, 1, pz0 - 3.2, pz0 + 0.1, C.StoneLight)
	span(house, "Step", -4, 4, 0, 2, pz0 - 1.6, pz0 + 0.1, C.StoneLight)
	for _, sx in { -1, 1 } do
		local x = sx * 7.3
		span(house, "PorchPost", x - 0.5, x + 0.5, FLOOR, 8.4, pz0 + 0.2, pz0 + 1.2, C.Wood)
		-- front rail beside the steps and side rail back to the wall
		local xa, xb = math.min(sx * 4, sx * 6.8), math.max(sx * 4, sx * 6.8)
		span(house, "Rail", xa, xb, 5.2, 5.7, pz0 + 0.45, pz0 + 0.95, C.WoodLight)
		span(house, "RailLow", xa, xb, 4, 4.4, pz0 + 0.5, pz0 + 0.9, C.WoodLight)
		span(house, "Rail", x - 0.25, x + 0.25, 5.2, 5.7, pz0 + 1.2, z0 - 0.4, C.WoodLight)
		span(house, "RailLow", x - 0.2, x + 0.2, 4, 4.4, pz0 + 1.2, z0 - 0.4, C.WoodLight)
		-- flower bed against the base course
		local bx0, bx1 = math.min(sx * 9, sx * 15.6), math.max(sx * 9, sx * 15.6)
		flowerBed(house, bx0, bx1, z0 - 2.8, z0 - 1, P.Flowers[if sx < 0 then 4 else 2], P.Flowers[5])
	end
	ramp(house, "PorchRoof", -8.6, 8.6, 8.4, 10.6, pz0 - 0.6, z0 - 0.1, "-z", ROOF, { CastShadow = true })
	span(house, "PorchFascia", -8.8, 8.8, 8, 8.8, pz0 - 0.8, pz0 + 0.2, ROOF_TRIM)
	span(house, "LampBracket", 3.1, 3.7, 7.4, 7.8, z0 - 1.1, z0, C.Iron, DECOR)
	local lamp = span(house, "WallLamp", 2.9, 3.9, 6.3, 7.4, z0 - 1.1, z0 - 0.1, C.Glow, NEON_DECOR)
	U.new("PointLight", { Range = 14, Brightness = 1, Color = C.LightColor, Shadows = false }, lamp)
	return smokeOffset
end

-- The smokehouse (+X of the cottage): timber walls on a stone footing, gable to the front with a
-- hoist beam, big double doors, an iron smoking pipe, a net hung on its side.
-- Returns the smoke attachment's offset.
local function buildSmokehouse(template: any): any
	local shed = U.model(template, "Smokehouse")
	local x0, x1, z0, z1 = 21, 39, 144, 162
	local wallTop = 10
	local eave = wallTop + 0.8
	local xc = (x0 + x1) / 2
	span(shed, "Footing", x0 - 0.4, x1 + 0.4, 0, 1, z0 - 0.4, z1 + 0.4, C.Stone)
	span(shed, "Walls", x0, x1, 1, wallTop, z0, z1, C.Wood, { CastShadow = true })
	for _, x in { x0, x1 } do
		for _, z in { z0, z1 } do
			local xa = if x == x0 then x - 0.3 else x - 0.8
			local za = if z == z0 then z - 0.3 else z - 0.8
			span(shed, "Corner", xa, xa + 1.1, 1, wallTop, za, za + 1.1, C.WoodDark)
		end
	end
	span(shed, "WallPlate", x0 - 0.3, x1 + 0.3, wallTop, eave, z0 - 1.2, z1 + 1.2, C.WoodDark)
	gableRoof(shed, x0, x1, z0, z1, eave, 7, 1.8, 1, false, C.Wood)

	-- Double doors and the name board above them.
	span(shed, "DoorFrame", xc - 5, xc + 5, 1, 8.6, z0 - 0.3, z0, C.WoodDark)
	for _, sx in { -1, 1 } do
		local xa, xb = math.min(xc + sx * 0.1, xc + sx * 4.4), math.max(xc + sx * 0.1, xc + sx * 4.4)
		span(shed, "Door", xa, xb, 1, 8, z0 - 0.45, z0 - 0.25, C.WoodLight)
	end
	local board = span(shed, "Board", xc - 3.6, xc + 3.6, 8.7, 9.9, z0 - 0.4, z0, C.Cream)
	plainText(board, Enum.NormalId.Front, "КОПТИЛЬНЯ", C.Ink, false)
	-- Hoist beam out of the gable, a rope and a hook.
	span(shed, "HoistBeam", xc - 0.6, xc + 0.6, 14.4, 15.4, z0 - 4, z0 - 0.6, C.WoodDark)
	span(shed, "HoistRope", xc - 0.15, xc + 0.15, 11.6, 14.4, z0 - 3.5, z0 - 3.2, C.Rope, DECOR)
	span(shed, "HoistHook", xc - 0.5, xc + 0.5, 11, 11.6, z0 - 3.8, z0 - 2.9, C.Iron, DECOR)
	-- Iron smoking pipe through the east slope.
	span(shed, "Pipe", 34.4, 35.6, 13, 19.6, 154, 155.2, C.Iron)
	local cap = span(shed, "PipeCap", 34, 36, 19.6, 20.2, 153.6, 155.6, C.Iron)
	local smoke, smokeOffset = attachAt(cap, "SmokeAttachment", at(35, 20.6, 154.6))
	Props.fx(smoke, "smoke", { rate = 3 })
	-- A fishing net drying on the east wall (towards the work yard) with two floats.
	span(
		shed,
		"Net",
		x1 + 0.05,
		x1 + 0.3,
		3,
		8,
		147,
		157,
		C.Rope,
		{ Transparency = 0.35, CanCollide = false, CastShadow = false }
	)
	for _, z in { 149.5, 154.5 } do
		span(shed, "NetFloat", x1 + 0.3, x1 + 0.9, 7.2, 8.2, z - 0.5, z + 0.5, C.Cream, DECOR)
	end
	-- Lantern beside the doors.
	span(shed, "LampBracket", xc + 6, xc + 6.6, 7.4, 7.8, z0 - 1, z0, C.Iron, DECOR)
	span(shed, "WallLamp", xc + 5.8, xc + 6.8, 6.3, 7.4, z0 - 1, z0 - 0.1, C.Glow, NEON_DECOR)
	return smokeOffset
end

------------------------------------------------------------------------------------------
-- Garden, well, woodpile, work yard, seating patio, hedges, trees
------------------------------------------------------------------------------------------

-- Three raised vegetable beds in the front-left yard: cabbages, carrots, pumpkins.
local function buildGarden(template: any)
	local garden = U.model(template, "Garden")
	local z0, z1 = 25, 47
	local function bed(x: number)
		span(garden, "BedFrame", x - 3.6, x + 3.6, 0, 1.3, z0, z1, C.Wood)
		span(garden, "Soil", x - 2.9, x + 2.9, 1.3, 1.5, z0 + 0.7, z1 - 0.7, C.Soil)
	end
	-- cabbages
	bed(-56)
	for _, z in { 29.5, 36, 42.5 } do
		span(garden, "Cabbage", -57.3, -54.7, 1.5, 3.3, z - 1.3, z + 1.3, C.Cabbage, { CanCollide = false })
	end
	-- carrots: a row of feathery tops over a row of orange shoulders
	bed(-46)
	span(garden, "CarrotTops", -47.2, -44.8, 1.5, 2.8, z0 + 2, z1 - 2, C.Leaf3, DECOR)
	span(garden, "Carrots", -47.6, -44.4, 1.45, 1.85, z0 + 2.4, z1 - 2.4, C.Carrot, DECOR)
	-- pumpkins on a vine
	bed(-36)
	span(garden, "Vine", -36.5, -35.5, 1.5, 2.1, z0 + 1.6, z1 - 1.6, C.Leaf1, DECOR)
	for i, z in { 29.5, 36, 42.5 } do
		local x = -36 + (if i % 2 == 0 then 0.8 else -0.8)
		span(garden, "Pumpkin", x - 1.4, x + 1.4, 1.5, 3.6, z - 1.4, z + 1.4, C.Pumpkin, { CanCollide = false })
	end
	-- the sign at the yard end of the beds, read from the gate
	span(garden, "SignPost", -46.3, -45.7, 0, 3.4, 22.8, 23.6, C.WoodDark)
	local board = span(garden, "SignBoard", -49.2, -42.8, 3.2, 5.6, 22.5, 23.3, C.WoodLight)
	plainText(board, Enum.NormalId.Front, "ОГОРОД", C.Ink, false)
	-- rain barrel at the end of the beds
	cylY(garden, "RainBarrel", 2.6, 3.2, at(-31.2, LAWN + 1.6, 26.4), C.Wood, { CastShadow = true })
	cylY(garden, "BarrelHoop", 2.75, 0.4, at(-31.2, LAWN + 2.4, 26.4), C.Iron, DECOR)
end

-- Stone well with a little timber roof in the -X side lawn.
local function buildWell(template: any)
	local well = U.model(template, "Well")
	local wx, wz = -55, 92
	span(well, "Ring", wx - 3, wx + 3, 0, 2.8, wz - 3, wz + 3, C.StoneLight, { CastShadow = true })
	span(well, "Water", wx - 2.2, wx + 2.2, 2.75, 2.95, wz - 2.2, wz + 2.2, C.Water, DECOR)
	for _, sx in { -1, 1 } do
		span(well, "Post", wx + sx * 2.4 - 0.4, wx + sx * 2.4 + 0.4, 2.8, 8.6, wz - 0.4, wz + 0.4, C.WoodDark)
	end
	span(well, "Crossbar", wx - 3, wx + 3, 7, 7.6, wz - 0.3, wz + 0.3, C.Wood, DECOR)
	ramp(well, "Roof", wx - 4, wx + 4, 8.6, 10.8, wz - 3.4, wz, "-z", C.RoofBrown, { CastShadow = true })
	ramp(well, "Roof", wx - 4, wx + 4, 8.6, 10.8, wz, wz + 3.4, "+z", C.RoofBrown)
	span(well, "Rope", wx - 0.1, wx + 0.1, 5.8, 7, wz - 0.1, wz + 0.1, C.Rope, DECOR)
	span(well, "Bucket", wx - 0.6, wx + 0.6, 4.6, 5.8, wz - 0.6, wz + 0.6, C.Wood, DECOR)
end

-- Woodpile with a chopping stump in the +X side lawn.
local function buildWoodpile(template: any)
	local pile = U.model(template, "Woodpile")
	local px, pz = 57, 92
	span(pile, "Logs", px - 2, px + 2, LAWN - 0.1, 2.8, pz - 4.5, pz + 4.5, C.Bark, { CastShadow = true })
	span(pile, "LogEnds", px - 2.15, px + 2.15, LAWN, 2.6, pz - 4.3, pz + 4.3, C.CutWood, DECOR)
	span(pile, "LogsTop", px - 1.6, px + 1.6, 2.8, 4.3, pz - 3.5, pz + 3.5, C.Bark)
	Props.stump(pile, facing(px - 6.5, LAWN, pz + 1, 30), { seed = 5, axe = true })
end

-- Work yard behind the smokehouse corner: fish drying rack, a rowboat on trestles, crates, barrels.
local function buildWorkYard(template: any)
	local yard = U.model(template, "WorkYard")
	span(yard, "Yard", 41, 64.6, 0, GRAVEL, 128.4, 163.8, C.Gravel)
	-- Drying rack: two posts, a bar, a row of fish.
	local rz = 138
	for _, x in { 46.5, 59.5 } do
		span(yard, "RackPost", x - 0.5, x + 0.5, GRAVEL - 0.1, 7.6, rz - 0.5, rz + 0.5, C.WoodDark)
	end
	span(yard, "RackBar", 46.2, 59.8, 6.8, 7.4, rz - 0.35, rz + 0.35, C.Wood)
	-- fish hung by the tail: a tail fin under the bar, the body below it
	for i = 0, 3 do
		local x = 49 + i * 3.2
		local c = if i % 2 == 0 then C.FishSilver else C.FishSilverDark
		span(yard, "FishTail", x - 0.9, x + 0.9, 6.0, 6.8, rz - 0.2, rz + 0.2, c, DECOR)
		span(yard, "DriedFish", x - 0.7, x + 0.7, 3.4, 6.0, rz - 0.3, rz + 0.3, c, DECOR)
	end
	-- Rowboat up on two trestles for repairs (not on the water: it does not bob).
	for _, z in { 150.5, 157.5 } do
		span(yard, "Trestle", 51.4, 56.6, GRAVEL, 1.9, z - 0.4, z + 0.4, C.Wood)
		span(yard, "TrestleTop", 51, 57, 1.9, 2.5, z - 0.6, z + 0.6, C.WoodDark)
	end
	Props.rowboat(yard, at(54, 3.1, 154), { seed = 7, color = C.Boat, oars = false, bob = 0 })
	-- Crates and barrels by the smokehouse doors.
	Props.crate(yard, facing(43.6, GRAVEL, 144.6, 10), { seed = 1, size = 3 })
	Props.crate(yard, facing(43.4, GRAVEL + 3, 144.8, -8), { seed = 2, size = 2.4 })
	Props.barrel(yard, at(43.8, GRAVEL, 149.2), { seed = 4 })
	Props.barrel(yard, at(61.6, GRAVEL, 160.4), { seed = 6 })
end

-- Seating patio left of the cottage: picnic table, bench, lantern.
local function buildPatio(template: any)
	local patio = U.model(template, "Patio")
	span(patio, "Paving", -61, -40.6, 0, PATH, 139, 159, C.StoneLight)
	Props.picnicTable(patio, facing(-51, PATH, 147, 90), { seed = 1, cloth = C.Cream })
	Props.bench(patio, facing(-51, PATH, 155.6, 0), { seed = 2, color = C.WoodLight })
	lanternPost(patio, -42.4, 157.4, PATH, 6, true)
end

-- Low clipped hedges along the court's sides (gaps in the middle lead to the well and the
-- woodpile), lantern posts at the court's entrance and in its back corners.
local function buildHedgesAndLights(template: any)
	local green = U.model(template, "Hedges")
	for _, sx in { -1, 1 } do
		for _, zs in { { 57, 86 }, { 98, 127 } } do
			local xa, xb = math.min(sx * 44.6, sx * 47.4), math.max(sx * 44.6, sx * 47.4)
			span(green, "Hedge", xa, xb, 0, 2.6, zs[1], zs[2], C.Hedge)
			span(green, "HedgeTop", xa + 0.3, xb - 0.3, 2.6, 3.2, zs[1] + 0.3, zs[2] - 0.3, C.HedgeTop, DECOR)
		end
	end
	-- square timber planters with a clipped bush at the court's front corners
	for _, sx in { -1, 1 } do
		local x = sx * 39.6
		span(green, "Planter", x - 2.2, x + 2.2, COURT - 0.1, COURT + 1.6, 55.4, 59.8, C.Wood)
		span(green, "PlanterBush", x - 1.8, x + 1.8, COURT + 1.6, COURT + 4.6, 55.8, 59.4, C.Leaf2, DECOR)
	end
	local lights = U.model(template, "Lanterns")
	for _, sx in { -1, 1 } do
		lanternPost(lights, sx * 7.6, 50.6, LAWN, 5.6)
		lanternPost(lights, sx * 40.4, 128.4, COURT, 5.6)
	end
end

-- Voxel tree from the prop library (layered dark / mid / light canopy, "lite + compact").
local function tree(parent: any, x: number, z: number, s: number, seed: number, palette: string, fruit: any?)
	Props.roundTree(parent, at(x, LAWN, z), {
		seed = seed,
		scale = s,
		lite = true,
		compact = true,
		palette = palette,
		fruit = fruit,
		name = "Tree",
	})
end

local function buildTrees(template: any)
	local green = U.model(template, "Trees")
	tree(green, -59, 64, 1.35, 11, "green", C.Red) -- apple tree by the well
	tree(green, -59, 118, 1.45, 13, "green")
	tree(green, 59, 66, 1.4, 12, "green")
	tree(green, 59, 116, 1.45, 14, "green")
	tree(green, -61, 132, 1.3, 15, "green") -- shades the patio
	tree(green, 60, 50, 1.15, 16, "mint") -- behind the doghouse
end

------------------------------------------------------------------------------------------
-- Pier, end platform, shelter, props, boat
------------------------------------------------------------------------------------------

local PIER_HALF = 8 -- walkway deck x = +-8
local PLATFORM_DEPTH = 22 -- the end platform: from the pier's end (lz = -PierLength) 22 studs inland
local PLAT_HALF = 20 -- platform x = +-20

-- Deck slab (top at `top`) with raised plank strips (4 studs wide, every 8; 0.1 short of the
-- deck's ends): along Z for the walkway, across (along X) for the platform. z0 < z1.
local function deck(parent: any, halfWidth: number, z0: number, z1: number, across: boolean, top: number)
	span(parent, "Deck", -halfWidth, halfWidth, DECK - 1.2, top, z0, z1, C.Plank)
	local flat = { CastShadow = false }
	local strip = C.Plank:Lerp(C.Wood, 0.45)
	if across then
		local z = z0 + 2
		while z + 4 <= z1 - 1 do
			span(parent, "Planks", -halfWidth + 0.1, halfWidth - 0.1, DECK - 0.2, PLANK, z, z + 4, strip, flat)
			z += 8
		end
	else
		local x = -halfWidth + 2
		while x + 4 <= halfWidth - 2 + 0.01 do
			span(parent, "Planks", x, x + 4, DECK - 0.2, PLANK, z0 + 0.1, z1 - 0.1, strip, flat)
			x += 8
		end
	end
end

-- Returns the z of the walkway's last post pair (the boat's bow line is tied to it).
local function buildPier(template: any, pierEnd: number, pileBottom: number): number
	local PIER_END = pierEnd + PLATFORM_DEPTH -- walkway ends, platform begins
	local pier = U.model(template, "Pier")
	local hw = PIER_HALF
	-- (the walkway slab sits 0.14 under the promenade tiles it runs into: no shared plane)
	deck(pier, hw, PIER_END, 0, false, DECK - 0.1)
	-- Timber kerbs along both edges.
	for _, sx in { -1, 1 } do
		span(pier, "Kerb", sx * hw, sx * (hw + 1.2), DECK - 1.4, DECK + 0.6, PIER_END, 0, C.WoodDark)
	end
	-- Posts double as piles, evenly along the walkway (the last pair just short of the platform's
	-- back kerbs); the two end pairs carry lanterns.
	local px = hw + 0.6
	local zs = {}
	local n = 4
	for i = 1, n do
		zs[i] = -3 + (PIER_END + 2.5 + 3) * (i - 1) / (n - 1)
	end
	for i, z in zs do
		local lantern = i == 1 or i == #zs
		local top = if lantern then DECK + 6 else DECK + 4.2
		for _, sx in { -1, 1 } do
			local x = sx * px
			span(pier, "Post", x - 1, x + 1, pileBottom, top, z - 1, z + 1, C.WoodDark)
			if lantern then
				span(pier, "Lantern", x - 0.8, x + 0.8, top, top + 1.6, z - 0.8, z + 0.8, C.Glow, NEON_DECOR)
				span(pier, "LanternCap", x - 1.2, x + 1.2, top + 1.6, top + 2.2, z - 1.2, z + 1.2, C.Iron, DECOR)
			end
		end
	end
	-- Timber rails from the first to the last post.
	for _, sx in { -1, 1 } do
		local x = sx * px
		span(pier, "Rail", x - 0.5, x + 0.5, DECK + 3.2, DECK + 4.0, zs[n], zs[1], C.Wood)
		span(pier, "RailLow", x - 0.35, x + 0.35, DECK + 1.6, DECK + 2.2, zs[n], zs[1], C.WoodLight)
	end

	-- End platform (its front kerb ends exactly at the end of the pier corridor).
	local plat = U.model(template, "Platform")
	local z0, z1 = pierEnd + 1.2, PIER_END
	deck(plat, PLAT_HALF, z0, z1, true, DECK)
	local e = PLAT_HALF
	span(plat, "Kerb", -e - 1.2, e + 1.2, DECK - 1.4, DECK + 0.6, pierEnd, z0, C.WoodDark)
	for _, sx in { -1, 1 } do
		span(plat, "Kerb", sx * e, sx * (e + 1.2), DECK - 1.4, DECK + 0.6, z0, z1, C.WoodDark)
		span(plat, "Kerb", sx * (hw + 1.2), sx * (e + 1.2), DECK - 1.4, DECK + 0.6, z1, z1 + 1.2, C.WoodDark)
	end
	-- Piles and rails (the front middle stays open for casting). The back corner piles stop 0.1
	-- short of the deck's and side kerbs' back ends (no shared end planes).
	local pe = e + 0.6
	local zf, zb = z0 + 0.4, z1 - 1.1
	for _, p in
		{
			{ -pe, zf },
			{ pe, zf },
			{ -pe, zb },
			{ pe, zb },
			{ -pe, (zf + z1) / 2 },
			{ pe, (zf + z1) / 2 },
			{ -9, zf },
			{ 9, zf },
		}
	do
		span(plat, "Post", p[1] - 1, p[1] + 1, pileBottom, DECK + 4.2, p[2] - 1, p[2] + 1, C.WoodDark)
	end
	for _, sx in { -1, 1 } do
		span(plat, "Rail", sx * pe - 0.5, sx * pe + 0.5, DECK + 3.2, DECK + 4, zf, zb, C.Wood)
		span(plat, "Rail", sx * 9, sx * pe, DECK + 3.2, DECK + 4, zf - 0.5, zf + 0.5, C.Wood)
	end
	return zs[n]
end

-- The fishing spot sits in the open middle of the platform's front edge: nothing hangs over the
-- player or over the follow camera behind them. Beside it, on the -X side of the platform, a
-- shelter over the rod rack and a bench: timber posts, a stepped Accent roof (it never collides
-- or takes raycasts, so the camera never pops in against it) and a lantern under it.
local function buildPavilion(template: any, pierEnd: number)
	local pav = U.model(template, "Pavilion")
	local x0, x1 = -PLAT_HALF + 1, -10 -- post centres
	local z0, z1 = pierEnd + 5.5, pierEnd + 17.5
	local postTop = DECK + 10
	for _, x in { x0, x1 } do
		for _, z in { z0, z1 } do
			span(pav, "Post", x - 0.7, x + 0.7, DECK, postTop, z - 0.7, z + 0.7, C.Wood)
		end
	end
	local xc, zc = (x0 + x1) / 2, (z0 + z1) / 2
	local y = postTop
	for i, layer in { { 15, 1.2, ROOF_TRIM }, { 11.4, 1.4, ROOF }, { 7.8, 1.4, -0.18 }, { 3.6, 1.4, ROOF_TRIM } } do
		local w, d = layer[1], layer[1] + 2.4 -- a touch longer along the platform than across it
		local opts = { CastShadow = i <= 2, CanCollide = false, CanQuery = false }
		span(pav, "Roof", xc - w / 2, xc + w / 2, y, y + layer[2], zc - d / 2, zc + d / 2, layer[3], opts)
		y += layer[2]
	end
	local lamp = span(pav, "Lantern", xc - 0.9, xc + 0.9, postTop - 2, postTop, zc - 0.9, zc + 0.9, C.Glow, NEON_DECOR)
	U.new("PointLight", { Range = 16, Brightness = 1.2, Color = C.LightColor, Shadows = false }, lamp)
	-- A bench under the roof, looking out over the lagoon (the rod rack stands behind it), and a
	-- name board between the back posts, read from the pier.
	span(pav, "BenchSeat", xc - 3, xc + 3, DECK, DECK + 1.8, zc - 3.4, zc - 1.6, C.WoodLight)
	span(pav, "BenchBack", xc - 3, xc + 3, DECK + 1.8, DECK + 4.2, zc - 1.6, zc - 1, C.Wood)
	local board = span(pav, "Board", x0 + 0.7, x1 - 0.7, postTop - 2.4, postTop, z1 - 0.25, z1 + 0.25, C.Cream)
	plainText(board, Enum.NormalId.Back, "РЫБАЛКА", C.Ink, false)

	-- Where the owner stands to fish (stage 2 checks the distance to this part): a light tint of
	-- the base colour in a cream ring, with glints rising off it so the spot catches the eye.
	local sz = pierEnd + 4.5
	local plat = template:FindFirstChild("Platform")
	span(plat, "SpotRing", -3.4, 3.4, DECK, PLANK + 0.15, sz - 3.4, sz + 3.4, C.Cream, { CanCollide = false })
	local spot = span(template, "FishingSpot", -2.6, 2.6, DECK, PLANK + 0.3, sz - 2.6, sz + 2.6, 0.35, {
		CastShadow = false,
	})
	Props.fx(spot, "sparkle", {
		name = "Glints",
		rate = 2.5,
		spread = 25,
		speed = U.roblox.NumberRange.new(1.5, 3),
		color = U.roblox.ColorSequence.new(C.White, P.WaterLight),
	})
	-- The catch of the day: a wooden bucket beside the spot with a fish tail sticking out.
	cylY(plat, "Bucket", 2, 1.9, at(5.6, DECK + 0.95, sz - 1.2), C.Wood, DECOR)
	make(
		plat,
		"BucketFish",
		Vector3.new(0.4, 1.6, 1.2),
		at(5.5, DECK + 2.3, sz - 1.1) * CFrame.Angles(0, rad(30), rad(14)),
		C.FishSilver,
		DECOR
	)
end

local function buildPierProps(template: any, pierEnd: number)
	local props = U.model(template, "PierProps")
	-- Rod rack on the left of the platform.
	local rx, rz = -15, pierEnd + 14
	for _, dx in { -3, 3 } do
		span(props, "RackPost", rx + dx - 0.4, rx + dx + 0.4, DECK, DECK + 5.4, rz - 0.4, rz + 0.4, C.Wood)
	end
	span(props, "RackBar", rx - 3.6, rx + 3.6, DECK + 4.2, DECK + 5, rz - 0.5, rz + 0.5, C.WoodDark)
	local rod = at(rx - 1, DECK + 3.6, rz - 0.6) * CFrame.Angles(rad(-12), 0, rad(8))
	make(props, "Rod", Vector3.new(0.3, 7.4, 0.3), rod, C.WoodLight, DECOR)
	-- Crates and a barrel on the right.
	span(props, "Crate", 11, 15, DECK, DECK + 4, pierEnd + 11, pierEnd + 15, C.Wood)
	span(props, "Crate", 15.6, 18.6, DECK, DECK + 3, pierEnd + 12, pierEnd + 15, C.WoodLight)
	span(props, "Crate", 12, 14.6, DECK + 4, DECK + 6.6, pierEnd + 12, pierEnd + 14.6, C.WoodLight)
	cylY(props, "Barrel", 2.8, 3.4, at(16.6, DECK + 1.7, pierEnd + 7.6), C.WoodDark)
	-- Lifebuoy hanging on the outside of the left rail (square ring, red and white).
	local bx, bz = -(PLAT_HALF + 1.35), pierEnd + 8
	for i, s in { { 0, 1.1 }, { 0, -1.1 }, { 1.1, 0 }, { -1.1, 0 } } do
		local col = if i <= 2 then C.Red else C.White
		local dy, dz = s[1], s[2]
		local sy = if dz == 0 then 0.8 else 3
		local sz = if dz == 0 then 1.4 else 0.8
		local y = DECK + 2.4 + dy
		span(
			props,
			"Lifebuoy",
			bx - 0.3,
			bx + 0.3,
			y - sy / 2,
			y + sy / 2,
			bz + dz - sz / 2,
			bz + dz + sz / 2,
			col,
			DECOR
		)
	end
end

-- Little rowing boat moored at the right side of the pier, halfway out, its bow line tied to the
-- pier's last post. It bobs on the water: the client (AmbientController) lifts and rolls every
-- Model with a number attribute Bob about its pivot (here the hull's centre on the waterline); the
-- line bobs with it, its far end sunk 0.5 into the post, so it slides along the post's face.
local function buildBoat(template: any, waterY: number, postZ: number)
	local boat = U.model(template, "Boat")
	local f = facing(15, waterY, -34, 4)
	boat.PrimaryPart = box(boat, "Hull", f, 0, 0, 0, 4.6, 1.6, 10, C.WoodLight)
	boat:SetAttribute("Bob", 0.25)
	boat:SetAttribute("BobPeriod", 3.4)
	for _, sx in { -1, 1 } do
		box(boat, "Side", f, sx * 2.7, 0.9, 0.3, 0.8, 2.4, 10.6, -0.15)
	end
	-- (the stern's ends sink into the sides: no end face shares the hull's side planes)
	box(boat, "Stern", f, 0, 0.9, 5.2, 5.4, 2.4, 0.8, C.Cream)
	box(boat, "Bow", f, 0, 0.9, -5.6, 3.6, 2.4, 1.6, C.Cream)
	box(boat, "BowTip", f, 0, 1.1, -6.8, 2, 2.2, 1, C.Cream)
	box(boat, "Seat", f, 0, 1.3, 1.6, 4.6, 0.5, 1.6, C.Wood)
	box(boat, "Oar", f, 0.6, 1.0, -1.8, 0.4, 0.3, 7, C.WoodDark, DECOR)
	-- Bow line from the bow tip to the pier post's outer face, under the kerb.
	local from = (f * at(-0.5, 1.9, -6.6)).Position
	local to = Vector3.new(PIER_HALF + 1.1, waterY + 2.75, postZ)
	local line = CFrame.lookAt((from + to) / 2, to)
	make(boat, "BowLine", Vector3.new(0.25, 0.25, (to - from).Magnitude), line, C.Rope, DECOR)
end

------------------------------------------------------------------------------------------

return function(game: any, mapCfg: any)
	local serverStorage = game:GetService("ServerStorage")
	local template = U.new("Model", { Name = "BaseTemplate" }, serverStorage)
	local partsBefore = U.partCount

	local root = U.marker(template, "Root", Vector3.new(2, 0.2, 2), CFrame.new(0, 0, 0))
	template.PrimaryPart = root

	local front = mapCfg.PlotFront or 18
	local plot = {
		halfWidth = mapCfg.PlotHalfWidth or 68,
		front = front,
		back = front + (mapCfg.PlotDepth or 150),
	}
	local pierEnd = -(mapCfg.PierLength or 72)
	local waterY = (mapCfg.WaterTop or 0) - (mapCfg.GroundTop or 4) -- local water surface (-4)
	local pileBottom = waterY - 16 -- y = -20: below the lagoon bed under the pier

	buildGrounds(template, plot)
	buildFence(template, plot)
	buildGate(template, plot)
	buildSpawn(template)
	local signOffset = buildFlag(template)
	buildAlarm(template)
	buildMailbox(template)
	local tank, expected = buildTank(template)
	buildSlots(tank, expected)
	buildDogHouse(template)
	buildDog(template)
	local smokeOffset = buildHouse(template)
	local shedSmokeOffset = buildSmokehouse(template)
	buildGarden(template)
	buildWell(template)
	buildWoodpile(template)
	buildWorkYard(template)
	buildPatio(template)
	buildHedgesAndLights(template)
	buildTrees(template)
	local lastPostZ = buildPier(template, pierEnd, pileBottom)
	buildPavilion(template, pierEnd)
	buildPierProps(template, pierEnd)
	buildBoat(template, waterY, lastPostZ)

	local count = 0
	for _, d in template:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	assert(count == U.partCount - partsBefore, "BaseTemplate: parts created outside Util.part")
	assert(count <= BUDGET, `BaseTemplate: {count} parts, budget {BUDGET}`)

	table.insert(expected, { root = "template", path = { "Flag", "Pole", "SignAttachment" }, offset = signOffset })
	table.insert(
		expected,
		{ root = "template", path = { "House", "ChimneyCap", "SmokeAttachment" }, offset = smokeOffset }
	)
	table.insert(
		expected,
		{ root = "template", path = { "Smokehouse", "PipeCap", "SmokeAttachment" }, offset = shedSmokeOffset }
	)
	return {
		template = template,
		partCount = count,
		budget = BUDGET,
		-- Verified by the post-build self-check in tools/build.luau (path from the template root).
		expectedAttachments = expected,
	}
end
