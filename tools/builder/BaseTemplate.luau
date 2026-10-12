--[[
	Builds ServerStorage.BaseTemplate — one player base: a fisherman's homestead on the green
	island with an aquarium court (art direction v4, tools/builder/DESIGN.md §1 and §2 "Base-local
	frame"). BaseService clones it into the 8 slots and paints every part with attribute
	Accent = true in the base colour (optional AccentShade -1..1: > 0 lighter, towards white;
	< 0 darker in HSV), and every part with WallTone = true in the base's own calm wall tone
	(BaseConfig.WallTones; optional WallShade, same rule), so the 8 houses differ.

	Colour: lawn, warm two-tone flagstone walks, cream limestone, plank decks, timber, plaster.
	The base colour (Accent) marks the base from afar without flooding it: the roofs (deep shade,
	AccentShade -0.28, darker fascias and ridges) of the house, its lookout tower, the aquarium
	pavilion and the two display arcades; small full-colour accents — the flag, the arcade banners,
	the gate sign's frame, the tackle shed's awning, the patio parasol, the mailbox, the SpawnPad.
	Any Accent part bigger than ~400 studs² uses a deep shade (<= -0.25; tested).

	Base-local frame (Root at the origin, y = 0 is GroundTop; the world builder provides flat
	grass under the plot):
	  -Z     towards the lagoon. lz 0..18 is the public promenade (the template places nothing
	         there except the start of the pier), lz 0..-PierLength (72) is the base's own pier.
	  +Z     inland: the plot x = -68..68, lz = 18..168.
	  +X/-X  sideways (+X is on the left of a player walking in through the gate).

	Layout (front to back, symmetric about the flagstone axis):
	  lz 18        roofed timber gate between stone piers (name board with OwnerLabel/BaseLabel on
	               both faces, gold fish weathervane), flower beds; a stone-and-rail fence
	  lz 22..54    front yard: the spawn rose (a two-tone flagstone compass rose with a cream ring
	               round the SpawnPad), the flag (the base's beacon) and the signal mast (Alarm);
	               the kitchen garden (-X: cabbages, pumpkins, bean poles), the tackle shed
	               (+X: rods, bait barrel, an awning); the guard dog and its kennel are hidden here
	               until the stage-4 upgrade
	  lz 54..120   the aquarium court, a cloister: the big tank as a timber pavilion on a limestone
	               terrace (tinted water, a castle and a reef inside, mullions, a gabled roof with a
	               cupola and the «АКВАРИУМ» board) between two display arcades (plank deck, plaster
	               back wall, lean-to roof on posts, hanging lanterns, banners) holding the 12
	               display aquariums (Tank.Slots.Slot_1..12: a timber cabinet, a brass rim, a framed
	               water cube with sand; odd slots in the -X arcade, slots 1-2 nearest the gate);
	               flower borders between them; flagstone cross walks front and back
	  side strips  +X: the fry pond (kerb, lilies, reeds, little jetty); -X: the net yard (drying
	               nets, fish rack, crab traps, the well); fruit trees
	  lz 124..168  a 3-stud stone terrace (stairs and plank ramps): the house — the base's main
	               building, a T plan (stone ground floor, plaster upper floor in the wall tone,
	               a cross-gabled front wing with porch and balcony, windows on every side) with a
	               lookout tower (belvedere, telescope, stepped Accent roof, fish weathervane);
	               the smokehouse and the work yard (+X), the seating patio (-X); hedge at the back
	  lz 0..-72    plank pier with rails and lanterns, a moored boat that bobs, the end platform
	               with the FishingSpot, a shelter over a bench and the rod rack, crates, lifebuoy
	Particles (no parts): chimney and smokehouse smoke, tank bubbles, the fishing spot's glints,
	the weathervanes' sparkle (Props.fx).

	The guard dog (Model "Dog", stage 4 upgrade) is NOT on display: the dog and its kennel
	(Dog.DogHouse) have every part invisible (Transparency 1, CanCollide/CanQuery/CastShadow
	false) and the model attribute Unlocked = false. All parts are opaque blocks: to show them
	(dog bought) set every BasePart's Transparency to 0 and Unlocked = true.

	Names the server code relies on (BaseService, DESIGN.md §2) — keep in sync:
	  Root, SpawnPad, FishingSpot, Tank.Glass.PromptAttachment, Alarm.Lamp, Dog (PrimaryPart),
	  Tank.Slots.Slot_N.{Pedestal.PromptAttachment, Pedestal.LabelGui.Label, Display.FishPoint}
	  (attribute SlotIndex), Flag.Pole.SignAttachment.OwnerSign.{OwnerLabel, BaseLabel},
	  Flag.Cloth (tests), Gate.Board.SignFront/SignBack.{OwnerLabel, BaseLabel}.

	Budget: <= 800 parts (8 bases at runtime; asserted below and in tests/stage1_bases.test.luau).
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

local BUDGET = 1000

------------------------------------------------------------------------------------------
-- Colours (all from Palette.luau, DESIGN.md §1) and plot numbers
------------------------------------------------------------------------------------------

local C = {
	Lawn = P.GrassTop:Lerp(P.GrassTop3, 0.3), -- a kept lawn, a hair lighter than the island grass
	Hedge = P.Leaf1,
	HedgeTop = P.Leaf1:Lerp(P.Leaf2, 0.7),
	Topiary = P.Leaf0:Lerp(P.Leaf1, 0.5),
	Flag = P.Flagstone, -- walks: light flags with darker ones set in
	FlagDark = P.FlagstoneDark,
	Limestone = P.Limestone, -- cream stone: terraces, kerbs, steps
	Gravel = P.SandDark:Lerp(P.Cobble, 0.45),
	Stone = P.Stone,
	StoneDark = P.StoneDark,
	StoneLight = P.StoneLight,
	Wood = P.Wood,
	WoodDark = P.WoodDark,
	WoodLight = P.WoodLight,
	Plank = P.Plank,
	Plaster = P.Plaster,
	Soil = P.DirtDark,
	Bark = P.Bark,
	CutWood = P.CutWood,
	Leaf0 = P.Leaf0,
	Leaf1 = P.Leaf1,
	Leaf2 = P.Leaf2,
	Leaf3 = P.Leaf3,
	CabbageOuter = P.Mint1:Lerp(P.Leaf1, 0.4),
	CabbageHeart = P.Mint3,
	Pumpkin = P.Autumn0:Lerp(P.Orange, 0.45),
	Bean = P.Lime,
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
	PondWater = P.Water:Lerp(P.WaterLight, 0.3),
	PondBed = P.Water:Lerp(P.Navy, 0.45),
	FishSilver = P.WindowBlue:Lerp(P.StoneLight, 0.45), -- drying fish
	FishSilverDark = P.WindowBlue:Lerp(P.Stone, 0.3),
	Cabinet = P.WoodLight:Lerp(P.CutWood, 0.35), -- display stands
	-- aquarium: water-tinted glass, sand, a castle and a reef
	TankGlass = P.Glass:Lerp(P.Cyan, 0.25), -- a clear sea-green tint
	DisplayWater = P.WaterLight:Lerp(P.Cyan, 0.3),
	SeaDeep = P.Water:Lerp(P.Navy, 0.3),
	ReefLight = P.WaterLight,
	Sand = P.SandDark:Lerp(P.Sand, 0.4),
	Castle = P.Sand, -- a sandcastle with terracotta turrets: warm through the tinted glass
	CastleRoof = P.RoofTerracotta,
	Rock = P.Stone, -- the reef: warm sandstone
	RockLight = P.StoneLight,
	Kelp1 = P.Seaweed,
	Kelp2 = P.Leaf2,
	CoralPinkBase = P.Pink:Lerp(P.Purple, 0.3),
	CoralPink = P.Pink,
	CoralOrangeBase = P.Autumn0,
	CoralOrange = P.Orange,
	BrainCoral = P.Gold,
	Yellow = P.Yellow,
	Orange = P.Orange,
	Blue = P.Blue,
	White = P.White,
	Red = P.Red,
	RoofBlue = P.RoofBlue,
	RoofBrown = P.RoofBrown,
	Shingle = P.RoofBrown:Lerp(P.Wood, 0.35), -- the arcades' timber shingles
	ShingleDark = P.RoofBrown:Lerp(P.WoodDark, 0.5),
	Brick = P.Brick,
	Boat = P.BoatPaint[2],
	Fry = P.Orange,
	-- the hidden guard dog (shown in stage 4): a shiba in warm, calm tones
	Dog = P.Wood:Lerp(P.Orange, 0.55),
	DogCream = P.Cream,
	Tongue = P.Pink,
}

-- Accent shades (BaseService paints these parts in the base colour).
local ROOF = -0.28 -- roof slopes: a deep, natural shade of the base colour
local ROOF_TRIM = -0.45 -- fascias, ridges
local SHUTTER = -0.12
local FASCIA = -0.15 -- the arcades' eave boards: a line of the base colour under neutral roofs

-- Accent parts get this (shaded) grey in the template; BaseService repaints them.
local ACCENT_DEFAULT = Color3.fromRGB(200, 200, 200)
local WHITE = Color3.new(1, 1, 1)

-- Plaster walls painted in the base's wall tone (BaseConfig.WallTones): pass WALL (or
-- wallTone(shade)) as the paint of a part.
local function wallTone(shade: number): { wall: number }
	return { wall = shade }
end
local WALL = wallTone(0)

-- Floor layers: the world's grass is at y = 0; no two floor layers are coplanar, and a slab lying
-- on another stands >= 0.15 above it (no shimmer from across the lagoon).
local LAWN = 0.2 -- plot lawn slab
local PATH = 0.5 -- flagstone walks (their darker flags stand 0.15 proud)
local ROSE = 0.75 -- spawn compass rose: dark square
local ROSE_TOP = 0.9 -- its light diamond
local RING = 1.05 -- cream ring round the pad
local ARC_DECK = 0.9 -- display arcades' plank deck
local TANK_TERRACE = 1.2 -- the aquarium's limestone terrace
local TERRACE = 3.0 -- the house terrace (lawn top)
local DECK = 0.6 -- pier and platform deck top
local PLANK = 0.75 -- plank strips on the decks

local SPAWN_Z = 36
local TERRACE_Z = 124 -- the house terrace's front face

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
		if h > 0.02 and h < 0.2 and amount > 0.3 then
			h -= 0.04 * (amount - 0.3) / 0.7 -- light shades keep their hue (yellow stays yellow)
		end
		return U.Color3.fromHSV(h, math.min(1, s * (1 + 0.15 * amount)), v * (1 - 0.6 * amount))
	end
	return color
end

local DECOR = { CanCollide = false, CastShadow = false }
local NEON = { Material = M.Neon, CastShadow = false }
local NEON_DECOR = { Material = M.Neon, CastShadow = false, CanCollide = false }
local GLASS = { Material = M.Glass, Transparency = 0.3, CastShadow = false }
local FLAT = { CastShadow = false }
-- Roofs over walkways never collide or take raycasts (the camera never pops in against them).
local ROOF_OPTS = { CanCollide = false, CanQuery = false, CastShadow = true }

--[[
	Creates a part. `paint` is a Color3 for a plain part, a number for an Accent part (the number
	is its AccentShade; 0 = the base colour itself), or WALL / wallTone(shade) for a plaster wall in
	the base's wall tone. opts may hold any part property (Material, Transparency, CanCollide,
	Shape, ...) plus `wedge = true`. Small or thin parts never cast shadows (cheaper, and their
	shadows look noisy).
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
	elseif typeof(paint) == "table" then
		local attributes: { [string]: any } = { WallTone = true }
		if paint.wall ~= 0 then
			attributes.WallShade = paint.wall
		end
		props.Attributes = merge(props.Attributes, attributes)
		color = shadeColor(C.Plaster, paint.wall)
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

-- min/max of a pair of mirrored coordinates (sx * a, sx * b).
local function mirror(sx: number, a: number, b: number): (number, number)
	return math.min(sx * a, sx * b), math.max(sx * a, sx * b)
end

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
-- Building kit: gable roofs, windows, lanterns, flower beds, flagstone walks
------------------------------------------------------------------------------------------

--[[
	Gable roof over the wall box x0..x1 x z0..z1 with its eaves at y0 and the ridge along X
	(alongX) or Z. e = eave overhang on the long sides, g = how far the roof runs past the gable
	walls, h = rise. Two Accent slopes, an eave fascia on each long side and a ridge beam (darker
	Accent), and on each end a gable triangle in `gable` paint standing in the plane of the roof's
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
		ramp(parent, "Roof", x0 - g, x1 + g, y0, top, z0 - e, zc, "-z", ROOF, { CastShadow = true })
		ramp(parent, "Roof", x0 - g, x1 + g, y0, top, zc, z1 + e, "+z", ROOF, { CastShadow = true })
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
		ramp(parent, "Roof", x0 - e, xc, y0, top, z0 - g, z1 + g, "-x", ROOF, { CastShadow = true })
		ramp(parent, "Roof", xc, x1 + e, y0, top, z0 - g, z1 + g, "+x", ROOF, { CastShadow = true })
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
	mullion and a stone sill, "full" a mullion, Accent shutters and a window box with two blooms
	(`bloom` and `bloom2`). small 2 / simple 4 / full 8 parts.
]]
local function window(parent: any, wf: any, w: number, h: number, kind: string, bloom: any?, bloom2: any?)
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
	box(parent, "WindowBox", wf, 0, -h / 2 - 1.05, -0.6, w + 1.0, 1.1, 1.2, C.Wood)
	box(parent, "Bloom", wf, -w / 4 - 0.1, -h / 2 + 0.1, -0.65, 1.3, 0.8, 0.8, bloom or P.Flowers[1], DECOR)
	box(parent, "Bloom", wf, w / 4 + 0.1, -h / 2 + 0.05, -0.55, 1.2, 0.7, 0.8, bloom2 or C.Cream, DECOR)
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

-- Lantern hanging under a beam whose underside is at `top`: an iron cap and a glowing cube. 2 parts.
local function hangLantern(parent: any, x: number, top: number, z: number, light: boolean?)
	span(parent, "LanternCap", x - 0.85, x + 0.85, top - 0.5, top, z - 0.85, z + 0.85, C.Iron, DECOR)
	local glow = span(parent, "Lantern", x - 0.6, x + 0.6, top - 1.8, top - 0.5, z - 0.6, z + 0.6, C.Glow, NEON_DECOR)
	if light then
		U.new("PointLight", { Range = 14, Brightness = 1, Color = C.LightColor, Shadows = false }, glow)
	end
end

-- Planted flower bed (Props.flowerBed: kerb, soil, leafy mound, flowers on stems) centred at
-- (x, y, z), its width along X (or along Z when alongZ).
local function flowerBed(
	parent: any,
	x: number,
	y: number,
	z: number,
	width: number,
	depth: number,
	colors: { any },
	opts: { [string]: any }?
): any
	local cf = if opts and opts.alongZ then facing(x, y, z, 90) else at(x, y, z)
	local o = merge({ width = width, depth = depth, colors = colors, seed = math.floor(x * 7 + z * 13) }, opts)
	o.alongZ = nil
	return Props.flowerBed(parent, cf, o)
end

--[[
	Two-tone flagstone walk: a light slab (top `top`) with darker flags set into it (0.15 proud)
	every `step` studs along its length, alternating between its two halves (centred when narrow).
	skip(u) -> true leaves out the flag at distance u from the walk's start. 1 + n parts.
]]
local function flagWalk(
	parent: any,
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	top: number,
	step: number,
	skip: ((number) -> boolean)?
): any
	local base = span(parent, name, x0, x1, top - 0.45, top, z0, z1, C.Flag, FLAT)
	local alongX = (x1 - x0) >= (z1 - z0)
	local len = if alongX then x1 - x0 else z1 - z0
	local wid = if alongX then z1 - z0 else x1 - x0
	local n = math.max(1, math.floor(len / step))
	local first = (len - (n - 1) * step) / 2
	local flagLen = math.min(step * 0.55, 3.6)
	for i = 0, n - 1 do
		local u = first + i * step
		if skip and skip(u) then
			continue
		end
		local w0, w1
		if wid >= 5.5 then
			local half = wid / 2
			if i % 2 == 0 then
				w0, w1 = 0.5, half - 0.3
			else
				w0, w1 = half + 0.3, wid - 0.5
			end
		else
			w0, w1 = 0.6, wid - 0.6
		end
		local a0, a1 = u - flagLen / 2, u + flagLen / 2
		if alongX then
			span(parent, name .. "Flag", x0 + a0, x0 + a1, top - 0.3, top + 0.15, z0 + w0, z0 + w1, C.FlagDark, FLAT)
		else
			span(parent, name .. "Flag", x0 + w0, x0 + w1, top - 0.3, top + 0.15, z0 + a0, z0 + a1, C.FlagDark, FLAT)
		end
	end
	return base
end

------------------------------------------------------------------------------------------
-- Ground: lawn, flagstone walks, the compass-rose spawn square
------------------------------------------------------------------------------------------

local function buildGrounds(template: any, plot: any)
	local floor = U.model(template, "Grounds")
	local hw, front, back = plot.halfWidth, plot.front, plot.back

	-- Lawn over the whole plot (the fence, the hedge and the house terrace stand on it).
	span(floor, "Lawn", -hw + 0.4, hw - 0.4, -0.4, LAWN, front + 0.4, back - 0.4, C.Lawn)

	-- The axis: gate -> spawn rose -> aquarium court (no flags where the rose covers the walk).
	flagWalk(floor, "Walk", -5, 5, front + 0.2, 54, PATH, 6, function(u: number): boolean
		local z = front + 0.2 + u
		return z > SPAWN_Z - 14 and z < SPAWN_Z + 14
	end)
	-- Cross walks in front of and behind the aquarium terrace, joining the arcade decks.
	flagWalk(floor, "CrossWalk", -22.2, 22.2, 54, 60, PATH, 8.8)
	flagWalk(floor, "BackWalk", -22.2, 22.2, 114, 120, PATH, 8.8)
	-- Side walks from the spawn rose to the kitchen garden (-X) and the tackle shed (+X).
	flagWalk(floor, "GardenWalk", -31, -9.5, 34, 38, PATH, 10)
	flagWalk(floor, "ShedWalk", 9.5, 45.6, 34, 38, PATH, 11)

	-- Spawn rose: a dark square under a light diamond (an eight-point compass rose), a cream
	-- ring round the pad (buildSpawn).
	span(floor, "Rose", -9, 9, PATH - 0.3, ROSE, SPAWN_Z - 9, SPAWN_Z + 9, C.FlagDark, FLAT)
	make(
		floor,
		"RoseStar",
		Vector3.new(17, ROSE_TOP - ROSE + 0.3, 17),
		at(0, (ROSE - 0.3 + ROSE_TOP) / 2, SPAWN_Z) * CFrame.Angles(0, rad(45), 0),
		C.Flag,
		FLAT
	)
	span(floor, "SpawnRing", -4.4, 4.4, ROSE, RING, SPAWN_Z - 4.4, SPAWN_Z + 4.4, C.Cream, FLAT)
	-- a gold fish inlaid in the rose's front point (towards the gate)
	local fz = SPAWN_Z - 8.6
	span(floor, "RoseFish", -1.8, 1.2, ROSE_TOP - 0.2, ROSE_TOP + 0.15, fz - 0.8, fz + 0.8, C.Gold, FLAT)
	span(floor, "RoseFishTail", 1.2, 2.4, ROSE_TOP - 0.2, ROSE_TOP + 0.15, fz - 1.2, fz + 1.2, C.Gold, FLAT)

	-- Flower beds just inside the gate.
	for _, sx in { -1, 1 } do
		local pair = if sx < 0 then Props.bloomPairs[2] else Props.bloomPairs[4]
		flowerBed(floor, sx * 8.4, LAWN, front + 6.4, 5.4, 2.6, pair, { spacing = 1.6, max = 3 })
	end
end

------------------------------------------------------------------------------------------
-- Fence (stone base course + timber rails) and the back hedge
------------------------------------------------------------------------------------------

local function buildFence(template: any, plot: any)
	local fence = U.model(template, "Fence")
	-- (the house terrace is walled by a clipped hedge on three sides)
	local hw, front, back = plot.halfWidth, plot.front, plot.back
	local line = hw - 1.4 -- side fence centre line
	local fz = front + 1.6 -- front fence centre line
	local hedgeZ = back - 3.4 -- the hedge's front face

	-- A straight run along X or Z standing on y0: stone base (from `base`) from a0 to a1, two
	-- rails from a0 to r1 (inside the last post), posts.
	local function run(
		alongX: boolean,
		a0: number,
		a1: number,
		r1: number,
		c: number,
		posts: { number },
		y0: number,
		base: number
	)
		local function blk(name: string, u0: number, u1: number, ya: number, yb: number, half: number, color: any)
			if alongX then
				span(fence, name, u0, u1, ya, yb, c - half, c + half, color)
			else
				span(fence, name, c - half, c + half, ya, yb, u0, u1, color)
			end
		end
		blk("StoneBase", a0, a1, base, y0 + 1.5, 0.8, C.Stone)
		blk("RailLow", a0, r1, y0 + 2.3, y0 + 2.8, 0.25, C.Wood)
		blk("RailTop", a0, r1, y0 + 3.7, y0 + 4.3, 0.3, C.Wood)
		for _, u in posts do
			blk("Post", u - 0.55, u + 0.55, y0, y0 + 4.9, 0.55, C.WoodDark)
		end
	end

	-- Front, either side of the gate (the gate piers end at x = +-16).
	for _, sx in { -1, 1 } do
		run(true, sx * 16, sx * (line + 0.8), sx * line, fz, { sx * 41, sx * line }, 0, 0)
	end
	-- Sides: from the front fence to the terrace; a hedge along the terrace's sides.
	for _, sx in { -1, 1 } do
		local z0 = fz + 0.55
		local posts = {}
		for i = 1, 3 do
			table.insert(posts, z0 + (TERRACE_Z - z0) * i / 3)
		end
		run(false, z0 - 0.55, TERRACE_Z, TERRACE_Z, sx * line, posts, 0, 0)
		local ha, hb = mirror(sx, hw - 3.4, hw - 0.6)
		span(
			fence,
			"SideHedge",
			ha,
			hb,
			-0.2,
			TERRACE + 5.4,
			TERRACE_Z + 0.3,
			hedgeZ + 0.4,
			C.Hedge,
			{ CastShadow = true }
		)
	end
	-- Tall clipped hedge along the back (behind the house), lighter on top.
	span(fence, "Hedge", -hw + 0.6, hw - 0.6, TERRACE - 0.2, TERRACE + 5.4, hedgeZ, back - 0.2, C.Hedge, {
		CastShadow = true,
	})
	span(fence, "HedgeTop", -hw + 1, hw - 1, TERRACE + 5.4, TERRACE + 6.2, hedgeZ + 0.4, back - 0.6, C.HedgeTop, {
		CanCollide = false,
	})
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
		local lo, hi = mirror(sx, 11.4, 16)
		local xm = (lo + hi) / 2
		span(gate, "Pier", lo, hi, 0, 8, z0, z0 + 4.4, C.Stone, { CastShadow = true })
		span(gate, "PierCap", lo - 0.4, hi + 0.4, 8, 9, z0 - 0.4, z0 + 4.8, C.Limestone)
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
	span(template, "SpawnPad", -3.2, 3.2, RING - 0.2, RING + 0.3, SPAWN_Z - 3.2, SPAWN_Z + 3.2, 0, {
		CastShadow = false,
	})
end

-- The base's beacon: a tall white mast (the highest point of the base, seen across the lagoon)
-- with a big base-colour flag (a light band across it) and the owner billboard above it.
local function buildFlag(template: any): any
	local flag = U.model(template, "Flag")
	local fx, fz = -20, 31
	span(flag, "Plinth", fx - 2.6, fx + 2.6, 0, 1.2, fz - 2.6, fz + 2.6, C.Stone)
	span(flag, "PlinthTop", fx - 1.8, fx + 1.8, 1.2, 2.0, fz - 1.8, fz + 1.8, C.Limestone)
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
-- Aquarium pavilion: the big tank on its terrace
------------------------------------------------------------------------------------------

local TANK_HALF_X = 12
local TANK_Z0, TANK_Z1 = 69, 107
local TANK_BASE = TANK_TERRACE + 2 -- plinth top = glass bottom
local TANK_TOP = TANK_BASE + 11
local PAV_EAVE = 18.6 -- the pavilion roof's eaves

local function buildTank(template: any): (any, { any })
	local tank = U.model(template, "Tank")
	local hx = TANK_HALF_X
	local expected = {}

	-- The court's centre: a limestone terrace with a step at the front, a stone plinth with a
	-- light ledge.
	span(tank, "Terrace", -16, 16, -0.2, TANK_TERRACE, 62, 114, C.Limestone, { CastShadow = true })
	span(
		tank,
		"Plinth",
		-hx - 1.6,
		hx + 1.6,
		TANK_TERRACE - 0.1,
		TANK_BASE - 0.6,
		TANK_Z0 - 1.6,
		TANK_Z1 + 1.6,
		C.Stone,
		{
			CastShadow = true,
		}
	)
	span(tank, "Ledge", -hx - 0.8, hx + 0.8, TANK_BASE - 0.6, TANK_BASE, TANK_Z0 - 0.8, TANK_Z1 + 0.8, C.StoneLight)

	-- The glass (one part = the whole water volume; fish swim inside it later), tinted like water.
	local glass = span(tank, "Glass", -hx, hx, TANK_BASE, TANK_TOP, TANK_Z0, TANK_Z1, C.TankGlass, {
		Material = M.Glass,
		Transparency = 0.55,
		CastShadow = false,
	})
	tank.PrimaryPart = glass
	-- Stage 3/4 prompts: in front of the tank's entrance end (towards the gate).
	local _, promptOffset = attachAt(glass, "PromptAttachment", at(0, TANK_TERRACE + 2, TANK_Z0 - 3))
	table.insert(expected, { root = "template", path = { "Tank", "Glass", "PromptAttachment" }, offset = promptOffset })

	-- Timber pavilion: corner and middle posts up to the eaves, mullions between them, a rim round
	-- the glass top, wall plates and tie beams carrying a gabled roof with a cupola.
	local plateY = PAV_EAVE - 0.8
	local zm = (TANK_Z0 + TANK_Z1) / 2
	for _, sx in { -1, 1 } do
		for _, z in { TANK_Z0, zm, TANK_Z1 } do
			local w = if z == zm then 0.6 else 0.85
			span(tank, "Post", sx * hx - w, sx * hx + w, TANK_BASE, plateY, z - w, z + w, C.WoodDark, {
				CastShadow = true,
			})
		end
		for _, z in { (TANK_Z0 + zm) / 2, (zm + TANK_Z1) / 2 } do
			span(
				tank,
				"Mullion",
				sx * hx - 0.3,
				sx * hx + 0.3,
				TANK_BASE,
				TANK_TOP,
				z - 0.3,
				z + 0.3,
				C.WoodDark,
				DECOR
			)
		end
		span(tank, "Rim", sx * hx - 0.6, sx * hx + 0.6, TANK_TOP, TANK_TOP + 0.7, TANK_Z0, TANK_Z1, C.WoodDark)
		span(tank, "Plate", sx * hx - 0.9, sx * hx + 0.9, plateY, PAV_EAVE, TANK_Z0 - 2, TANK_Z1 + 2, C.WoodDark)
	end
	for _, z in { TANK_Z0, TANK_Z1 } do
		span(tank, "Rim", -hx + 0.6, hx - 0.6, TANK_TOP, TANK_TOP + 0.7, z - 0.6, z + 0.6, C.WoodDark)
	end
	for _, z in { TANK_Z0 - 1.3, TANK_Z1 + 1.3 } do
		span(tank, "TieBeam", -hx - 0.9, hx + 0.9, plateY - 0.05, PAV_EAVE - 0.05, z - 0.7, z + 0.7, C.WoodDark)
	end
	local ridge = gableRoof(tank, -hx - 0.85, hx + 0.85, TANK_Z0, TANK_Z1, PAV_EAVE, 5.6, 1.6, 1.6, false, WALL)
	-- cupola on the ridge (the pavilion's silhouette from the gate)
	span(tank, "Cupola", -1.7, 1.7, ridge - 1, ridge + 2, zm - 1.7, zm + 1.7, C.WoodLight)
	span(tank, "CupolaRoof", -2.5, 2.5, ridge + 2, ridge + 2.8, zm - 2.5, zm + 2.5, ROOF_TRIM)
	span(tank, "CupolaTop", -1.5, 1.5, ridge + 2.8, ridge + 3.8, zm - 1.5, zm + 1.5, ROOF)
	-- Name board hanging under the front tie beam, over the glass: read from the gate.
	local sz = TANK_Z0 - 1.3
	span(tank, "SignFrame", -8.2, 8.2, TANK_TOP + 1.1, plateY - 0.05, sz - 0.25, sz + 0.25, C.WoodDark)
	local board = span(tank, "SignBoard", -7.6, 7.6, TANK_TOP + 1.5, plateY - 0.45, sz - 0.45, sz + 0.45, C.Cream)
	plainText(board, Enum.NormalId.Front, "АКВАРИУМ", C.Ink, false)

	-- Inside: sand, a little castle with two towers at the entrance end (the show window seen from
	-- the gate), a reef of stacked rocks in the middle, corals, kelp, fish, columns of rising
	-- bubbles (particles). A soft PointLight on the reef lights it all.
	local s = TANK_BASE + 0.9 -- sand top
	local sand = span(tank, "Sand", -hx + 0.2, hx - 0.2, TANK_BASE, s, TANK_Z0 + 0.2, TANK_Z1 - 0.2, C.Sand, DECOR)
	-- the water line: a light surface just under the rim
	span(
		tank,
		"WaterSurface",
		-hx + 0.15,
		hx - 0.15,
		TANK_TOP - 1,
		TANK_TOP - 0.6,
		TANK_Z0 + 0.15,
		TANK_Z1 - 0.15,
		C.ReefLight,
		{
			Transparency = 0.35,
			CanCollide = false,
			CanQuery = false,
			CastShadow = false,
		}
	)
	local function piece(
		name: string,
		x0: number,
		x1: number,
		y0: number,
		y1: number,
		z0: number,
		z1: number,
		paint: any
	): any
		return span(tank, name, x0, x1, s + y0, s + y1, z0, z1, paint, DECOR)
	end
	-- castle
	piece("Castle", -3, 3, -0.2, 4.2, 72.6, 77, C.Castle)
	for _, sx in { -1, 1 } do
		local xa, xb = mirror(sx, 2.8, 5.2)
		piece("CastleTower", xa, xb, -0.2, 6.6, 72.2, 77.4, C.Castle)
		piece("TowerRoof", xa - 0.4, xb + 0.4, 6.6, 7.6, 71.8, 77.8, C.CastleRoof)
		local ma, mb = mirror(sx, 0.9, 2.4)
		piece("Merlon", ma, mb, 4.2, 5.2, 72.6, 73.8, C.Castle)
	end
	piece("CastleDoor", -0.9, 0.9, 0, 2.8, 72.4, 72.6, C.Ink)
	-- reef
	local reef = piece("Reef", -5, 4, -0.2, 2.8, 84, 93, C.Rock)
	piece("Reef", -3.4, 2.6, 2.8, 5, 85.4, 91.6, C.RockLight)
	U.new("PointLight", { Range = 16, Brightness = 1, Color = C.ReefLight, Shadows = false }, reef)
	-- branching corals and a brain coral
	piece("Coral", -10.6, -7, -0.2, 2.4, 79, 82.6, C.CoralPinkBase)
	piece("CoralArm", -10, -8.2, 2.4, 6.4, 79.8, 81.6, C.CoralPink)
	piece("Coral", 7, 10.6, -0.2, 2.4, 79, 82.6, C.CoralOrangeBase)
	piece("CoralArm", 8.4, 10.2, 2.4, 6.8, 79.8, 81.6, C.CoralOrange)
	piece("BrainCoral", 5.6, 10, -0.2, 2.6, 99.5, 104, C.BrainCoral)
	-- kelp: two stacked blocks shifted against each other
	piece("Kelp", -9.6, -8, -0.2, 7.6, 95, 96.6, C.Kelp1)
	piece("Kelp", 7.6, 9.2, -0.2, 6.4, 90.5, 92.1, C.Kelp2)
	-- fish: a body and a tall tail fin; the yellow tang crosses the show window
	piece("Fish", -8, -4.8, 7.2, 9.2, 79.4, 81.6, C.Yellow)
	piece("FishTail", -9.4, -8, 7, 9.4, 80.25, 80.75, C.Blue)
	piece("Fish", -8.1, -5.9, 5.6, 7.6, 97.4, 100.6, C.Orange)
	piece("FishTail", -7.25, -6.75, 5.4, 7.8, 100.6, 102, C.White)
	piece("Fish", 5.5, 7.7, 7, 9, 86.4, 89.6, C.Blue)
	piece("FishTail", 6.35, 6.85, 6.8, 9.2, 85, 86.4, C.Yellow)
	-- columns of bubbles (particles: they move and cost no parts); they live at most 3 s
	for _, b in { { "BubblesWest", -3.6, 96 }, { "BubblesEast", 3.4, 82 } } do
		local attachment, offset = attachAt(sand, b[1], at(b[2], s + 0.4, b[3]))
		Props.fx(attachment, "bubbles", { rate = 3, size = 1.5, lifetime = U.roblox.NumberRange.new(2.6, 3) })
		table.insert(expected, { root = "template", path = { "Tank", "Sand", b[1] }, offset = offset })
	end

	return tank, expected
end

------------------------------------------------------------------------------------------
-- Display arcades and the 12 display aquariums
------------------------------------------------------------------------------------------

local ARC_IN, ARC_WALL = 22, 40 -- each arcade: deck from |x| = 22 (the aisle) to its back wall
local ARC_Z0, ARC_Z1 = 54, 123
local ARC_EAVE = 13.2 -- the lean-to roof's front (low) edge
local ARC_TOP = 16.6 -- its back (high) edge, against the wall
local ARC_POSTS = { ARC_Z0 + 1, 77.5, 99.5, ARC_Z1 - 1 }
local SLOT_ROW_X = 32
local SLOT_Z0, SLOT_PITCH = 61, 11

-- One display aquarium: a timber cabinet, a brass rim, a cube of tinted water with a sand floor,
-- a deep-sea backdrop and timber corner posts (the fish floats in its centre). Local frame: -Z faces the
-- aisle. The label (owner's fish or "Пусто") and the slot number are on the cabinet's front.
local function buildSlot(slots: any, index: number, frame: any, expected: { any })
	local slot = U.model(slots, `Slot_{index}`)
	slot:SetAttribute("SlotIndex", index)
	local y0 = ARC_DECK
	local pedestal = box(slot, "Pedestal", frame, 0, y0 + 1.7, 0, 6.8, 3.4, 6.8, C.Cabinet, { CastShadow = true })
	local top = y0 + 3.4
	box(slot, "Rim", frame, 0, top + 0.3, 0, 7.4, 0.6, 7.4, C.Gold)
	local base = top + 0.6
	local display = box(slot, "Display", frame, 0, base + 3.1, 0, 6.2, 6.2, 6.2, C.DisplayWater, {
		Material = M.Glass,
		Transparency = 0.5,
		CastShadow = false,
	})
	box(slot, "Sand", frame, 0, base + 0.35, 0, 5.8, 0.7, 5.8, C.Sand, DECOR)
	-- a deep-sea backdrop on the back pane (the fish reads against it) and the front corner posts
	box(slot, "Backdrop", frame, 0, base + 3.2, 3.05, 6.6, 6.4, 0.5, C.SeaDeep, DECOR)
	for _, sx in { -1, 1 } do
		box(slot, "Frame", frame, sx * 3.05, base + 3.2, -3.05, 0.5, 6.4, 0.5, C.WoodDark, DECOR)
	end
	slot.PrimaryPart = pedestal

	-- The fish model floats in the centre of the display; prompts stand in front of the cabinet.
	local fishPoint = U.new("Attachment", { Name = "FishPoint", CFrame = CFrame.new() }, display)
	local _, promptOffset = attachAt(pedestal, "PromptAttachment", frame * at(0, y0 + 1.7, -5))
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

	-- Label on the front face: "Пусто" until a fish is put on display; the slot number above it.
	local gui = surfaceGui(pedestal, "LabelGui", Enum.NormalId.Front, 50)
	U.new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromScale(0.06, 0.4),
		Size = UDim2.fromScale(0.88, 0.5),
		BackgroundTransparency = 1,
		Text = "Пусто",
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = C.Ink,
	}, gui)
	U.new("TextLabel", {
		Name = "Number",
		Position = UDim2.fromScale(0.3, 0.06),
		Size = UDim2.fromScale(0.4, 0.3),
		BackgroundTransparency = 1,
		Text = `№{index}`,
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = C.WoodDark,
	}, gui)
end

local function buildSlots(tank: any, expected: { any })
	local slots = U.folder(tank, "Slots")
	for k = 1, 6 do
		local z = SLOT_Z0 + (k - 1) * SLOT_PITCH
		-- Odd slots in the -X arcade (front faces +X), even in the +X arcade (front faces -X).
		buildSlot(slots, 2 * k - 1, facing(-SLOT_ROW_X, 0, z, -90), expected)
		buildSlot(slots, 2 * k, facing(SLOT_ROW_X, 0, z, 90), expected)
	end
end

-- The two arcades either side of the aquarium: plank deck, a plaster back wall (in the base's
-- wall tone) on a stone course between stone pillars, timber posts and beam, a shingled lean-to
-- roof with an eave board in the base colour, lanterns hanging between the display pairs, banners
-- in the base colour, windows outside.
local function buildArcades(template: any)
	local arcades = U.model(template, "Arcades")
	for _, sx in { -1, 1 } do
		local arc = U.model(arcades, if sx < 0 then "West" else "East")
		local function X(a: number, b: number): (number, number)
			return mirror(sx, a, b)
		end
		local xa, xb = X(ARC_IN, ARC_WALL + 0.2)
		span(arc, "Deck", xa, xb, -0.2, ARC_DECK, ARC_Z0, ARC_Z1, C.Plank, FLAT)
		xa, xb = X(ARC_IN - 0.4, ARC_IN + 0.6)
		span(arc, "DeckEdge", xa, xb, -0.2, ARC_DECK + 0.15, ARC_Z0 - 0.2, ARC_Z1 + 0.2, C.WoodDark, FLAT)
		-- back wall
		local wa, wb = X(ARC_WALL, ARC_WALL + 1.4)
		span(arc, "Wall", wa, wb, 0, ARC_TOP + 0.2, ARC_Z0 + 0.3, ARC_Z1 - 0.3, WALL, { CastShadow = true })
		xa, xb = X(ARC_WALL - 0.3, ARC_WALL + 1.7)
		span(arc, "WallCourse", xa, xb, -0.2, 2.4, ARC_Z0 + 0.3, ARC_Z1 - 0.3, C.Stone)
		xa, xb = X(ARC_WALL - 0.25, ARC_WALL + 1.65)
		span(arc, "WallBand", xa, xb, 9, 9.8, ARC_Z0 + 0.3, ARC_Z1 - 0.3, C.WoodDark)
		xa, xb = X(ARC_WALL - 0.4, ARC_WALL + 1.8)
		span(arc, "WallPlate", xa, xb, ARC_TOP + 0.2, ARC_TOP + 1, ARC_Z0 + 0.3, ARC_Z1 - 0.3, C.WoodDark)
		xa, xb = X(ARC_WALL - 0.6, ARC_WALL + 2)
		for _, z in { ARC_Z0, ARC_Z1 } do
			span(arc, "Pillar", xa, xb, -0.2, ARC_TOP + 1.6, z - 1.3, z + 1.3, C.Stone, { CastShadow = true })
		end
		xa, xb = X(ARC_WALL + 0.6, ARC_WALL + 2)
		for _, z in { ARC_POSTS[2], ARC_POSTS[3] } do
			span(arc, "Pilaster", xa, xb, -0.2, ARC_TOP + 0.4, z - 0.9, z + 0.9, C.StoneLight)
		end
		-- posts and the front beam
		local beamBottom = ARC_EAVE - 1.2
		xa, xb = X(ARC_IN + 0.4, ARC_IN + 1.6)
		for _, z in ARC_POSTS do
			span(arc, "Post", xa, xb, ARC_DECK, beamBottom, z - 0.6, z + 0.6, C.WoodDark, { CastShadow = true })
		end
		xa, xb = X(ARC_IN + 0.2, ARC_IN + 1.8)
		span(arc, "Beam", xa, xb, beamBottom, ARC_EAVE, ARC_Z0 - 0.4, ARC_Z1 + 0.4, C.WoodDark)
		-- lean-to roof, its slope down towards the aisle, and a fascia along the eave
		xa, xb = X(ARC_IN - 0.8, ARC_WALL)
		local down = if sx > 0 then "-x" else "+x"
		ramp(arc, "Roof", xa, xb, ARC_EAVE, ARC_TOP, ARC_Z0 - 1.2, ARC_Z1 + 1.2, down, C.Shingle, ROOF_OPTS)
		for _, z in { ARC_POSTS[2], ARC_POSTS[3] } do
			ramp(arc, "RoofBatten", xa, xb, ARC_EAVE + 0.3, ARC_TOP + 0.3, z - 0.8, z + 0.8, down, C.ShingleDark, DECOR)
		end
		xa, xb = X(ARC_IN - 1.2, ARC_IN - 0.4)
		span(arc, "Fascia", xa, xb, ARC_EAVE - 0.5, ARC_EAVE + 0.7, ARC_Z0 - 1.4, ARC_Z1 + 1.4, FASCIA, DECOR)
		-- lanterns between the display pairs; banners on the middle posts, facing the aisle
		for i, z in { 66.5, 88.5, 110.5 } do
			hangLantern(arc, sx * (ARC_IN + 1), beamBottom, z, i == 2)
		end
		xa, xb = X(ARC_IN + 0.05, ARC_IN + 0.4)
		for _, z in { ARC_POSTS[2], ARC_POSTS[3] } do
			span(arc, "Banner", xa, xb, 6.2, 11.4, z - 1.2, z + 1.2, 0, DECOR)
		end
		-- windows in the wall's outer face (towards the side strips), a climbing rose by the middle one
		for _, z in { 66.5, 88.5, 110.5 } do
			window(arc, facing(sx * (ARC_WALL + 1.4), 12.8, z, -90 * sx), 2.6, 3, "small")
		end
		xa, xb = X(ARC_WALL + 1.3, ARC_WALL + 2)
		span(arc, "Climber", xa, xb, 2.2, 14.4, 90.6, 95.4, C.Leaf1, DECOR)
		xa, xb = X(ARC_WALL + 1.3, ARC_WALL + 1.9)
		span(arc, "Climber", xa, xb, 14.2, 16.4, 85.4, 94.4, C.Leaf2, DECOR)
		xa, xb = X(ARC_WALL + 1.8, ARC_WALL + 2.4)
		span(arc, "Rose", xa, xb, 8.6, 9.6, 92.4, 93.4, P.Flowers[3], DECOR)
		span(arc, "Rose", xa, xb, 14.8, 15.8, 87.2, 88.2, C.Cream, DECOR)
	end
end

-- Lawn borders between the aquarium terrace and the arcades: a long flower bed and a clipped
-- topiary cube each.
local function buildCourtGarden(template: any)
	local garden = U.model(template, "CourtGarden")
	for _, sx in { -1, 1 } do
		local pair = if sx < 0 then Props.bloomPairs[3] else Props.bloomPairs[1]
		flowerBed(garden, sx * 19, LAWN, 88, 26, 3.2, pair, { alongZ = true, stems = false, spacing = 2.6, max = 9 })
		span(garden, "Topiary", sx * 19 - 1.5, sx * 19 + 1.5, LAWN - 0.1, 3.4, 64.5, 67.5, C.Topiary)
	end
end

------------------------------------------------------------------------------------------
-- The guard dog and its kennel (stage 4 upgrade): hidden
------------------------------------------------------------------------------------------

local DOG_X, DOG_Z = 30, 46
local HIDDEN = { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false }

-- Blocky shiba lying by its kennel; local -Z = where it looks. Hidden (see the header): every
-- part is invisible and takes no collisions, raycasts or shadows; Unlocked = false.
local function buildDog(template: any)
	local dog = U.model(template, "Dog")
	dog:SetAttribute("Unlocked", false)
	-- the kennel (the door looks towards -X, the spawn rose)
	local kennel = U.model(dog, "DogHouse")
	local k = facing(DOG_X, LAWN, DOG_Z, 90)
	box(kennel, "Floor", k, 0, 0.3, 0, 7.6, 0.6, 7.6, C.WoodDark, HIDDEN)
	box(kennel, "Walls", k, 0, 0.6 + 2.3, 0, 6.4, 4.6, 6.4, C.Wood, HIDDEN)
	box(kennel, "DoorHole", k, 0, 0.6 + 1.6, -3.25, 2.6, 3.2, 0.2, C.Ink, HIDDEN)
	rampIn(kennel, "Roof", k, -4.2, 0, 5.2, 8.2, -4.2, 4.2, "-x", ROOF, HIDDEN)
	rampIn(kennel, "Roof", k, 0, 4.2, 5.2, 8.2, -4.2, 4.2, "+x", ROOF, HIDDEN)

	local S = 1.5
	local f = facing(DOG_X - 8, LAWN, DOG_Z - 4, 60) -- beside the kennel door, looking at the rose
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
-- The house terrace, the house with its lookout tower, the smokehouse
------------------------------------------------------------------------------------------

-- A 3-stud stone terrace across the back of the plot (lawn on top, limestone coping), central
-- stairs with lanterns on their cheeks, plank ramps at the side strips, a flagstone walk along
-- its front.
local function buildTerrace(template: any, plot: any)
	local terrace = U.model(template, "Terrace")
	local hw, back = plot.halfWidth - 2.4, plot.back - 0.2
	local z0 = TERRACE_Z
	span(terrace, "Retaining", -hw, hw, -0.2, TERRACE - 0.2, z0, back, C.Stone, { CastShadow = true })
	span(terrace, "TerraceLawn", -hw + 0.2, hw - 0.2, TERRACE - 0.4, TERRACE, z0 + 0.6, back - 0.2, C.Lawn, FLAT)
	span(terrace, "Coping", -hw - 0.2, hw + 0.2, TERRACE - 0.5, TERRACE + 0.15, z0 - 0.6, z0 + 0.6, C.Limestone)
	-- central stairs: three 1-stud steps
	for i = 1, 3 do
		span(terrace, "Step", -7, 7, -0.2, i, z0 - 4 + (i - 1) * 4 / 3, z0 + 0.1, C.Limestone)
	end
	for _, sx in { -1, 1 } do
		local xa, xb = mirror(sx, 7, 8.4)
		span(terrace, "StairCheek", xa, xb, -0.2, TERRACE + 0.6, z0 - 4.2, z0 + 0.6, C.Limestone)
		local lx = sx * 7.7
		span(
			terrace,
			"LanternCap",
			lx - 0.95,
			lx + 0.95,
			TERRACE + 2.2,
			TERRACE + 2.7,
			z0 - 3.55,
			z0 - 1.65,
			C.Iron,
			DECOR
		)
		span(
			terrace,
			"Lantern",
			lx - 0.7,
			lx + 0.7,
			TERRACE + 0.6,
			TERRACE + 2.2,
			z0 - 3.3,
			z0 - 1.9,
			C.Glow,
			NEON_DECOR
		)
		-- plank ramp up from the side strip
		local ra, rb = mirror(sx, 49, 55)
		ramp(terrace, "Ramp", ra, rb, -0.2, TERRACE, z0 - 7, z0 + 0.05, "-z", C.Plank)
	end
	-- the walk along the terrace's front: stairs -> porch, patio (-X), work yard (+X)
	flagWalk(terrace, "TerraceWalk", -58, 58, z0 + 0.6, z0 + 4.4, TERRACE + 0.3, 16, function(u: number): boolean
		return math.abs(-58 + u) < 9
	end)
end

local MAIN_X, MAIN_Z0, MAIN_Z1 = 20, 146, 163.6 -- the house's main block
local WING_X, WING_Z0 = 9, 138 -- the front wing (x = +-9, from lz 138 to the main block)
local GF_TOP = 10.6 -- ground-floor stone walls top (the floor band above)
local UF_BOT = 11.4 -- upper floor plaster from here
local WALL_TOP = 17
local EAVE = 17.8

-- Returns the chimney smoke attachment's offset.
local function buildHouse(template: any): any
	local house = U.model(template, "House")
	local F = TERRACE
	local x0, x1, z0, z1 = -MAIN_X, MAIN_X, MAIN_Z0, MAIN_Z1
	local zc = (z0 + z1) / 2

	-- Main block: stone base course, a warm stone ground floor, a timber floor band, the plaster
	-- upper floor (the base's wall tone) with timber corners, the wall plate, a gable roof in the
	-- base colour (ridge along X, plaster gables jettied 1 out).
	span(house, "BaseCourse", x0 - 0.6, x1 + 0.6, F - 0.2, F + 1.4, z0 - 0.6, z1 + 0.6, C.Stone, { CastShadow = true })
	span(house, "GroundWalls", x0, x1, F + 1.4, GF_TOP, z0, z1, C.StoneLight, { CastShadow = true })
	span(house, "FloorBand", x0 - 0.3, x1 + 0.3, GF_TOP, UF_BOT, z0 - 0.3, z1 + 0.3, C.WoodDark)
	span(house, "Walls", x0, x1, UF_BOT, WALL_TOP, z0, z1, WALL, { CastShadow = true })
	for _, x in { x0, x1 } do
		for _, z in { z0, z1 } do
			local xa = if x == x0 then x - 0.35 else x - 0.85
			local za = if z == z0 then z - 0.35 else z - 0.85
			span(house, "Corner", xa, xa + 1.2, UF_BOT, WALL_TOP, za, za + 1.2, C.WoodDark)
		end
	end
	span(house, "WallPlate", x0 - 1.2, x1 + 1.2, WALL_TOP, EAVE, z0 - 0.3, z1 + 0.3, C.WoodDark, { CastShadow = true })
	local mainRise = 9.5
	gableRoof(house, x0, x1, z0, z1, EAVE, mainRise, 2.2, 1, true, WALL)

	-- Chimney through the back slope, a lazy plume of smoke above it.
	local chimneyTop = 31.6
	span(house, "Chimney", 11, 14.4, WALL_TOP, chimneyTop, zc + 2.5, zc + 5.9, C.StoneLight, { CastShadow = true })
	local cap = span(house, "ChimneyCap", 10.6, 14.8, chimneyTop, chimneyTop + 0.8, zc + 2.1, zc + 6.3, C.Stone)
	local smoke, smokeOffset = attachAt(cap, "SmokeAttachment", at(12.7, chimneyTop + 2.4, zc + 4.2))
	Props.fx(smoke, "smoke", { rate = 2.5 })

	-- Front wing (a cross gable facing the gate): same storeys, its roof running into the main one.
	local wx, wz0 = WING_X, WING_Z0
	span(house, "WingCourse", -wx - 0.6, wx + 0.6, F - 0.2, F + 1.4, wz0 - 0.6, z0, C.Stone)
	span(house, "WingGround", -wx, wx, F + 1.4, GF_TOP, wz0, z0 + 0.2, C.StoneLight, { CastShadow = true })
	span(house, "WingBand", -wx - 0.3, wx + 0.3, GF_TOP, UF_BOT, wz0 - 0.3, z0, C.WoodDark)
	span(house, "WingWalls", -wx, wx, UF_BOT, WALL_TOP, wz0, z0 + 0.2, WALL, { CastShadow = true })
	for _, sx in { -1, 1 } do
		local xa = if sx < 0 then -wx - 0.35 else wx - 0.85
		span(house, "Corner", xa, xa + 1.2, UF_BOT, WALL_TOP, wz0 - 0.35, wz0 + 0.85, C.WoodDark)
	end
	local wg, we, wrise = 1.8, 1.6, 7.4
	span(house, "WingPlate", -wx - 0.3, wx + 0.3, WALL_TOP, EAVE, wz0 - wg - 0.2, z0, C.WoodDark)
	local mainEaveZ = z0 - 2.2
	local wtop = EAVE + wrise
	local wzEnd = mainEaveZ + wrise * (zc - mainEaveZ) / mainRise -- where the wing ridge meets the main slope
	ramp(house, "WingRoof", -wx - we, 0, EAVE, wtop, wz0 - wg, wzEnd, "-x", ROOF, { CastShadow = true })
	ramp(house, "WingRoof", 0, wx + we, EAVE, wtop, wz0 - wg, wzEnd, "+x", ROOF, { CastShadow = true })
	for _, sx in { -1, 1 } do
		local fa, fb = mirror(sx, wx + we - 0.9, wx + we + 0.3)
		span(house, "Fascia", fa, fb, EAVE - 0.4, EAVE + 0.7, wz0 - wg - 0.2, mainEaveZ + 0.3, ROOF_TRIM)
	end
	span(house, "Ridge", -0.9, 0.9, wtop - 0.6, wtop + 0.6, wz0 - wg - 0.3, wzEnd, ROOF_TRIM)
	local hg = wrise * wx / (wx + we)
	ramp(house, "Gable", -wx, 0, EAVE, EAVE + hg, wz0 - wg - 0.1, wz0 - wg + 0.5, "-x", WALL)
	ramp(house, "Gable", 0, wx, EAVE, EAVE + hg, wz0 - wg - 0.1, wz0 - wg + 0.5, "+x", WALL)
	window(house, at(0, EAVE + 2.4, wz0 - wg - 0.1), 2.2, 2, "small")

	-- Porch under a balcony at the wing's front: plank deck, two posts, the balcony with rails and a
	-- planted box, the front door, the balcony door, a wall lamp, a bench.
	local pz0 = wz0 - 5
	span(house, "Porch", -7.6, 7.6, F - 0.2, F + 0.8, pz0, wz0, C.Plank, { CastShadow = true })
	local by = UF_BOT + 0.1 -- balcony floor top
	for _, sx in { -1, 1 } do
		local pa, pb = mirror(sx, 6.6, 7.4)
		span(house, "PorchPost", pa, pb, F + 0.8, GF_TOP + 0.1, pz0 + 0.3, pz0 + 1.1, C.Wood, { CastShadow = true })
		local na, nb = mirror(sx, 7.3, 8.0)
		span(house, "Newel", na, nb, by, by + 3.2, pz0 - 0.2, pz0 + 0.5, C.Wood)
		local ra, rb = mirror(sx, 7.35, 7.85)
		span(house, "BalconyRail", ra, rb, by + 2.4, by + 2.9, pz0 + 0.5, wz0, C.WoodLight)
	end
	span(house, "Balcony", -7.9, 7.9, GF_TOP + 0.1, by, pz0 - 0.3, wz0 - 0.05, C.Wood, { CastShadow = true })
	span(house, "BalconyRail", -7.3, 7.3, by + 2.4, by + 2.9, pz0 - 0.15, pz0 + 0.35, C.WoodLight)
	span(house, "BalconyBox", -4.6, 4.6, by + 1.5, by + 2.4, pz0 - 0.9, pz0 - 0.15, C.Wood, DECOR)
	span(house, "BoxLeaves", -4.3, 4.3, by + 2.4, by + 2.8, pz0 - 0.8, pz0 - 0.25, C.Leaf2, DECOR)
	span(house, "Bloom", -3.3, -1.9, by + 2.6, by + 3.4, pz0 - 0.9, pz0 - 0.15, P.Flowers[3], DECOR)
	span(house, "Bloom", 1.9, 3.3, by + 2.6, by + 3.3, pz0 - 0.85, pz0 - 0.2, C.Cream, DECOR)
	span(house, "DoorFrame", -2.4, 2.4, F + 0.8, 10, wz0 - 0.3, wz0, C.WoodDark)
	span(house, "Door", -1.8, 1.8, F + 0.8, 9.4, wz0 - 0.45, wz0 - 0.25, C.Wood)
	span(house, "DoorWindow", -0.8, 0.8, 7.0, 8.4, wz0 - 0.55, wz0 - 0.4, C.WindowGlass, GLASS)
	span(house, "DoorKnob", 1, 1.5, 6.2, 6.7, wz0 - 0.75, wz0 - 0.4, C.Gold, DECOR)
	span(house, "BalconyDoor", -1.9, 1.9, by - 0.1, 16.2, wz0 - 0.3, wz0, C.WoodDark)
	span(house, "BalconyGlass", -1.4, 1.4, by, 15.7, wz0 - 0.45, wz0 - 0.25, C.WindowGlass, GLASS)
	span(house, "LampBracket", 2.9, 3.5, 8.3, 8.7, wz0 - 1.1, wz0, C.Iron, DECOR)
	local lamp = span(house, "WallLamp", 2.7, 3.7, 7.2, 8.3, wz0 - 1.1, wz0 - 0.1, C.Glow, NEON_DECOR)
	U.new("PointLight", { Range = 14, Brightness = 1, Color = C.LightColor, Shadows = false }, lamp)
	span(house, "PorchBench", -7.2, -4.6, F + 0.8, F + 1.9, wz0 - 2.2, wz0 - 1, C.WoodLight)

	-- Windows on every side.
	for _, sx in { -1, 1 } do
		-- wing front: simple windows either side of the door; small ones upstairs; one per side
		window(house, at(sx * 6, 7.2, wz0), 2.4, 3.2, "simple")
		window(house, at(sx * 5.4, 14.2, wz0), 2.2, 2.6, "small")
		-- main front either side of the wing: full windows (shutters, window box), simple upstairs
		local blooms = if sx < 0 then { P.Flowers[1], C.Cream } else { P.Flowers[3], C.Cream }
		window(house, at(sx * 14.5, 7.2, z0), 3, 3.4, "full", blooms[1], blooms[2])
		window(house, at(sx * 14.5, 14.2, z0), 3, 2.8, "small")
		-- gable sides: a simple window downstairs, small ones upstairs and in the gable
		local gx = sx * MAIN_X
		window(house, facing(gx, 7.2, zc, -90 * sx), 3, 3.2, "simple")
		window(house, facing(sx * (MAIN_X + 1.1), 20.6, zc, -90 * sx), 2.4, 2.4, "small")
	end
	-- back (towards the hill path): a back door and small windows on both floors
	for _, x in { -12, 13 } do
		window(house, facing(x, 7.2, z1, 180), 2.6, 3, "small")
	end
	for _, x in { -9, 9 } do
		window(house, facing(x, 14.2, z1, 180), 2.4, 2.6, "small")
	end
	span(house, "BackDoorFrame", 2.6, 6.8, F + 1.4, 9.6, z1, z1 + 0.3, C.WoodDark)
	span(house, "BackDoor", 3.1, 6.3, F + 1.4, 9.1, z1 + 0.25, z1 + 0.45, C.Wood)

	-- Lookout tower at the front-left corner: stone shaft, timber bands, slit windows, an open
	-- belvedere with rails and a telescope, a stepped roof in the base colour, a fish weathervane.
	local tx0, tx1, tz0, tz1 = -28, -19, 137, z0 + 0.4
	local tcx, tcz = (tx0 + tx1) / 2, (tz0 + tz1) / 2
	span(house, "TowerBase", tx0 - 0.6, tx1 + 0.6, F - 0.2, F + 1.6, tz0 - 0.6, tz1, C.Stone, { CastShadow = true })
	span(house, "Tower", tx0, tx1, F + 1.6, 24, tz0, tz1, C.StoneLight, { CastShadow = true })
	span(house, "TowerBand", tx0 - 0.3, tx1 + 0.3, GF_TOP, UF_BOT, tz0 - 0.3, tz1, C.WoodDark)
	span(house, "TowerBand", tx0 - 0.3, tx1 + 0.3, WALL_TOP, EAVE, tz0 - 0.3, tz1, C.WoodDark)
	for _, y in { 7.4, 14.2, 20.6 } do
		window(house, at(tcx, y, tz0), 1.8, 2.6, "small")
	end
	window(house, facing(tx0, 17.4, tcz, 90), 1.8, 2.6, "small")
	local bf = 24
	span(house, "Belvedere", tx0 - 1.2, tx1 + 1.2, bf, bf + 1, tz0 - 1.2, tz1 + 0.8, C.Wood, { CastShadow = true })
	local bt = bf + 6.6 -- roof base
	local px0, px1, pz0b, pz1b = tx0 - 0.6, tx1 + 0.6, tz0 - 0.6, tz1 + 0.2
	for _, x in { px0, px1 } do
		for _, z in { pz0b, pz1b } do
			span(house, "BelvederePost", x - 0.45, x + 0.45, bf + 1, bt, z - 0.45, z + 0.45, C.WoodDark)
		end
	end
	span(house, "BelvedereRail", px0, px1, bf + 3.2, bf + 3.7, pz0b - 0.2, pz0b + 0.2, C.WoodLight)
	span(house, "BelvedereRail", px0, px1, bf + 3.2, bf + 3.7, pz1b - 0.2, pz1b + 0.2, C.WoodLight)
	span(house, "BelvedereRail", px0 - 0.2, px0 + 0.2, bf + 3.2, bf + 3.7, pz0b, pz1b, C.WoodLight)
	span(house, "BelvedereRail", px1 - 0.2, px1 + 0.2, bf + 3.2, bf + 3.7, pz0b, pz1b, C.WoodLight)
	span(house, "TelescopeStand", tcx + 1.6, tcx + 2.2, bf + 1, bf + 3.4, tz0 + 1.2, tz0 + 1.8, C.WoodDark, DECOR)
	make(
		house,
		"Telescope",
		Vector3.new(0.8, 0.8, 3.6),
		at(tcx + 1.9, bf + 3.9, tz0 + 1.2) * CFrame.Angles(rad(-18), rad(20), 0),
		C.Gold,
		DECOR
	)
	local y = bt
	for i, layer in
		{ { 14.4, 1, ROOF_TRIM }, { 12.4, 1.4, ROOF }, { 9.8, 1.4, -0.16 }, { 7, 1.4, ROOF }, { 4, 1.4, ROOF_TRIM } }
	do
		local w = layer[1]
		span(house, "TowerRoof", tcx - w / 2, tcx + w / 2, y, y + layer[2], tcz - w / 2, tcz + w / 2, layer[3], {
			CastShadow = i <= 2,
		})
		y += layer[2]
	end
	span(house, "VaneRod", tcx - 0.2, tcx + 0.2, y, y + 3, tcz - 0.2, tcz + 0.2, C.Iron, DECOR)
	local fish = span(house, "VaneFish", tcx - 2, tcx + 1.6, y + 3, y + 4.7, tcz - 0.25, tcz + 0.25, C.Gold, DECOR)
	span(house, "VaneTail", tcx + 1.6, tcx + 2.8, y + 2.7, y + 5, tcz - 0.2, tcz + 0.2, C.Gold, DECOR)
	Props.fx(fish, "sparkle", { rate = 1, size = 1.2 })

	-- Planted beds along the main front, either side of the wing.
	for _, sx in { -1, 1 } do
		local pair = if sx < 0 then Props.bloomPairs[1] else Props.bloomPairs[3]
		flowerBed(house, sx * 14.5, F, z0 - 2.6, 8, 2.2, pair, { stems = false, max = 4 })
	end
	return smokeOffset
end

-- The smokehouse (+X of the house, on the terrace): timber walls on a stone footing, gable to the
-- front with a hoist beam, double doors, an iron smoking pipe, a net hung on its side.
-- Returns the smoke attachment's offset.
local function buildSmokehouse(template: any): any
	local shed = U.model(template, "Smokehouse")
	local F = TERRACE
	local x0, x1, z0, z1 = 27, 41, 146, 160
	local wallTop = F + 8.6
	local eave = wallTop + 0.8
	local xc = (x0 + x1) / 2
	span(shed, "Footing", x0 - 0.4, x1 + 0.4, F - 0.2, F + 1, z0 - 0.4, z1 + 0.4, C.Stone)
	span(shed, "Walls", x0, x1, F + 1, wallTop, z0, z1, C.Wood, { CastShadow = true })
	span(shed, "WallPlate", x0 - 0.3, x1 + 0.3, wallTop, eave, z0 - 1.2, z1 + 1.2, C.WoodDark)
	gableRoof(shed, x0, x1, z0, z1, eave, 6, 1.6, 1, false, C.Wood)

	-- Double doors and the name board above them.
	span(shed, "DoorFrame", xc - 4.6, xc + 4.6, F + 1, F + 8.2, z0 - 0.3, z0, C.WoodDark)
	for _, sx in { -1, 1 } do
		local xa, xb = math.min(xc + sx * 0.1, xc + sx * 4), math.max(xc + sx * 0.1, xc + sx * 4)
		span(shed, "Door", xa, xb, F + 1, F + 7.6, z0 - 0.45, z0 - 0.25, C.WoodLight)
	end
	local board = span(shed, "Board", xc - 3.6, xc + 3.6, F + 8.3, wallTop - 0.1, z0 - 0.4, z0, C.Cream)
	plainText(board, Enum.NormalId.Front, "КОПТИЛЬНЯ", C.Ink, false)
	-- Iron smoking pipe through the east slope.
	local pipeTop = eave + 8.4
	span(shed, "Pipe", 36.4, 37.6, eave + 2, pipeTop, 153, 154.2, C.Iron)
	local cap = span(shed, "PipeCap", 36, 38, pipeTop, pipeTop + 0.6, 152.6, 154.6, C.Iron)
	local smoke, smokeOffset = attachAt(cap, "SmokeAttachment", at(37, pipeTop + 1, 153.6))
	Props.fx(smoke, "smoke", { rate = 3 })
	-- A fishing net drying on the east wall (towards the work yard) with two floats.
	span(shed, "Net", x1 + 0.05, x1 + 0.3, F + 2.6, F + 7.6, 148, 158, C.Rope, {
		Transparency = 0.35,
		CanCollide = false,
		CastShadow = false,
	})
	span(shed, "NetFloat", x1 + 0.3, x1 + 0.9, F + 6.8, F + 7.8, 152.5, 153.5, C.Cream, DECOR)
	-- Lantern beside the doors.
	span(shed, "WallLamp", xc + 5.4, xc + 6.4, F + 6.3, F + 7.4, z0 - 1, z0 - 0.1, C.Glow, NEON_DECOR)
	return smokeOffset
end

-- Work yard in front of the smokehouse: a woodpile, a chopping stump, a crate.
local function buildWorkYard(template: any)
	local yard = U.model(template, "WorkYard")
	local F = TERRACE
	span(yard, "Yard", 44, 62, F - 0.2, F + 0.3, 134, 160, C.Gravel, FLAT)
	span(yard, "Logs", 57.4, 61.4, F + 0.2, F + 3, 141, 151, C.Bark, { CastShadow = true })
	span(yard, "LogEnds", 57.25, 61.55, F + 0.3, F + 2.8, 141.2, 150.8, C.CutWood, DECOR)
	span(yard, "LogsTop", 57.8, 61, F + 3, F + 4.5, 142, 150, C.Bark)
	Props.stump(yard, facing(53, F + 0.3, 146, 30), { seed = 5, axe = true })
	Props.crate(yard, facing(47.4, F + 0.3, 157.4, 10), { seed = 1, size = 3 })
end

-- Seating patio by the tower: flagstones, a trestle table with two benches under a parasol in the
-- base colour, a lantern post.
local function buildPatio(template: any)
	local patio = U.model(template, "Patio")
	local F = TERRACE
	local top = F + 0.3
	span(patio, "Paving", -58, -34, F - 0.2, top, 131, 147, C.Flag, FLAT)
	local cx, cz = -46, 139
	span(patio, "TableTop", cx - 3.6, cx + 3.6, top + 2.4, top + 3, cz - 1.7, cz + 1.7, C.WoodLight)
	for _, sx in { -1, 1 } do
		local x = cx + sx * 2.6
		span(patio, "Trestle", x - 0.4, x + 0.4, top, top + 2.4, cz - 1.3, cz + 1.3, C.WoodDark)
		local z = cz + sx * 3
		span(patio, "BenchSeat", cx - 3.4, cx + 3.4, top + 1.2, top + 1.7, z - 0.7, z + 0.7, C.WoodLight)
		span(patio, "BenchLegs", cx - 2.8, cx + 2.8, top, top + 1.2, z - 0.4, z + 0.4, C.WoodDark)
	end
	cylY(patio, "ParasolPole", 0.4, 7.4, at(cx, top + 3.7, cz), C.Cream, DECOR)
	span(patio, "Parasol", cx - 3.8, cx + 3.8, top + 6.2, top + 6.9, cz - 3.8, cz + 3.8, 0.12, { CanCollide = false })
	lanternPost(patio, -36, 145.4, top, 6, true)
end

------------------------------------------------------------------------------------------
-- Front yard: kitchen garden (-X), tackle shed (+X)
------------------------------------------------------------------------------------------

-- Two raised beds (cabbages; pumpkins on a vine), two bean poles, a sign, a rain barrel.
local function buildGarden(template: any)
	local garden = U.model(template, "Garden")
	local z0, z1 = 26, 47
	local function bed(xa: number, xb: number)
		span(garden, "BedFrame", xa, xb, 0, 1.3, z0, z1, C.Wood)
		span(garden, "Soil", xa + 0.7, xb - 0.7, 1.3, 1.5, z0 + 0.7, z1 - 0.7, C.Soil)
	end
	-- cabbages: dark outer leaves round a light heart
	bed(-61, -51)
	for i, z in { 30, 35.5, 41, 46.5 - 2.2 } do
		local x = -56 + (if i % 2 == 0 then 1.6 else -1.6)
		span(garden, "Cabbage", x - 1.6, x + 1.6, 1.5, 2.9, z - 1.6, z + 1.6, C.CabbageOuter, { CanCollide = false })
		span(garden, "CabbageHeart", x - 0.9, x + 0.9, 2.6, 3.7, z - 0.9, z + 0.9, C.CabbageHeart, DECOR)
	end
	-- pumpkins on a vine: a body and a stalk
	bed(-48, -39)
	span(garden, "Vine", -44, -43, 1.5, 2.1, z0 + 1.6, z1 - 1.6, C.Leaf1, DECOR)
	for i, z in { 30.5, 36.5, 42.5 } do
		local x = -43.5 + (if i % 2 == 0 then 1.6 else -1.6)
		span(garden, "Pumpkin", x - 1.5, x + 1.5, 1.5, 3.7, z - 1.5, z + 1.5, C.Pumpkin, { CanCollide = false })
		span(garden, "Stalk", x - 0.3, x + 0.3, 3.7, 4.4, z - 0.3, z + 0.3, C.Leaf0, DECOR)
	end
	-- two bean poles: a tall stake, the vine climbing it, a few flowers
	for i, z in { z0 + 5, z1 - 5 } do
		local x = -35
		span(garden, "BeanPole", x - 0.2, x + 0.2, 0, 8.4, z - 0.2, z + 0.2, C.WoodDark, DECOR)
		local h = if i == 1 then 6.2 else 5.4
		span(garden, "Beans", x - 0.9, x + 0.9, 0.2, h, z - 0.9, z + 0.9, if i == 1 then C.Leaf2 else C.Leaf1, DECOR)
		span(
			garden,
			"BeanFlowers",
			x - 1.1,
			x - 0.1,
			h - 2.2,
			h - 1.3,
			z - 1.1,
			z - 0.1,
			if i == 1 then C.White else C.Bean,
			DECOR
		)
	end
	-- the sign at the yard end of the beds, read from the gate
	span(garden, "SignPost", -46.3, -45.7, 0, 3.4, z0 - 2.4, z0 - 1.6, C.WoodDark)
	local board = span(garden, "SignBoard", -49.2, -42.8, 3.2, 5.6, z0 - 2.6, z0 - 1.8, C.WoodLight)
	plainText(board, Enum.NormalId.Front, "ОГОРОД", C.Ink, false)
	-- rain barrel at the end of the beds
	cylY(garden, "RainBarrel", 2.6, 3.2, at(-31.4, LAWN + 1.6, 28), C.Wood, { CastShadow = true })
end

-- Tackle shed: a timber hut with a stepped roof, a door under an awning in the base colour, a
-- window, a name board facing the gate, rods leaning on its front, a bait barrel and a crate.
local function buildTackleShed(template: any)
	local shed = U.model(template, "TackleShed")
	local x0, x1, z0, z1 = 46, 58, 28, 38
	local xc, zc = (x0 + x1) / 2, (z0 + z1) / 2
	span(shed, "Footing", x0 - 0.4, x1 + 0.4, -0.2, 0.9, z0 - 0.4, z1 + 0.4, C.Stone)
	span(shed, "Walls", x0, x1, 0.9, 8.5, z0, z1, C.Wood, { CastShadow = true })
	-- stepped roof (three layers, the ridge along X)
	span(shed, "Roof", x0 - 1, x1 + 1, 8.5, 9.7, z0 - 1.2, z1 + 1.2, C.RoofBrown, { CastShadow = true })
	span(shed, "Roof", x0 - 0.6, x1 + 0.6, 9.7, 10.9, z0 + 1, z1 - 1, C.RoofBrown:Lerp(C.WoodDark, 0.3))
	span(shed, "Roof", x0 - 0.3, x1 + 0.3, 10.9, 12.1, zc - 1.6, zc + 1.6, C.RoofBrown)
	-- door (towards the walk from the spawn rose) under an awning
	span(shed, "Door", x0 - 0.25, x0 + 0.05, 0.9, 6.9, 34.6, 37.4, C.WoodDark)
	ramp(shed, "Awning", x0 - 2.6, x0, 7.1, 8.3, 33.8, 38.2, "-x", 0, { CanCollide = false })
	window(shed, facing(x0, 4.6, 31, 90), 2, 2.2, "small")
	local board = span(shed, "Board", xc - 4, xc + 4, 5.6, 7.8, z0 - 0.4, z0, C.Cream)
	plainText(board, Enum.NormalId.Front, "СНАСТИ", C.Ink, false)
	-- rods leaning on the front wall (towards the gate), a bait barrel, a crate
	for i, x in { 48.6, 50.4, 55.6 } do
		local lean = if i == 3 then -10 else 8 + i * 2
		make(
			shed,
			"Rod",
			Vector3.new(0.3, 8.4, 0.3),
			at(x, 4.1, z0 - 0.9) * CFrame.Angles(rad(-9), 0, rad(lean)),
			if i == 2 then C.WoodDark else C.WoodLight,
			DECOR
		)
	end
	cylY(shed, "BaitBarrel", 2.4, 3, at(44.2, LAWN + 1.5, 30), C.WoodDark, { CastShadow = true })
	span(shed, "Crate", 59.2, 62, LAWN - 0.1, 2.8, 33.6, 36.4, C.WoodLight)
end

------------------------------------------------------------------------------------------
-- Side strips: fry pond (+X), net yard with the well (-X); fruit trees
------------------------------------------------------------------------------------------

-- Small reed clump: two stalks and a cattail. 3 parts.
local function reeds(parent: any, x: number, y: number, z: number)
	span(parent, "Reed", x - 0.25, x + 0.25, y, y + 4.2, z - 0.25, z + 0.25, C.Leaf0, DECOR)
	span(parent, "Reed", x + 0.5, x + 0.95, y, y + 3.2, z + 0.3, z + 0.75, C.Leaf1, DECOR)
	span(parent, "Cattail", x - 0.35, x + 0.35, y + 3.2, y + 4.6, z - 0.35, z + 0.35, P.Coconut, DECOR)
end

local function buildFryPond(template: any)
	local pond = U.model(template, "FryPond")
	local x0, x1, z0, z1 = 45, 63, 66, 100
	local rim = 1.2
	span(pond, "Kerb", x0, x1, -0.2, 1, z0, z0 + rim, C.Limestone)
	span(pond, "Kerb", x0, x1, -0.2, 1, z1 - rim, z1, C.Limestone)
	span(pond, "Kerb", x0, x0 + rim, -0.2, 1, z0 + rim, z1 - rim, C.Limestone)
	span(pond, "Kerb", x1 - rim, x1, -0.2, 1, z0 + rim, z1 - rim, C.Limestone)
	local wx0, wx1, wz0, wz1 = x0 + rim, x1 - rim, z0 + rim, z1 - rim
	span(pond, "PondBed", wx0, wx1, -0.3, 0.4, wz0, wz1, C.PondBed, FLAT)
	span(pond, "Water", wx0, wx1, 0.45, 0.8, wz0, wz1, C.PondWater, {
		Transparency = 0.3,
		CanCollide = false,
		CastShadow = false,
	})
	Props.lilyPad(pond, at(50, 0.8, 72.5), { seed = 3, flower = true })
	Props.lilyPad(pond, at(52, 0.8, 95), { seed = 5, flower = true })
	reeds(pond, 47.6, 0.4, 97.2)
	reeds(pond, 60.6, 0.4, 69.2)
	for _, f in { { 55, 74, 0 }, { 56.6, 75.4, 1 } } do
		local fx, fz = f[1], f[2]
		if f[3] == 0 then
			span(pond, "Fry", fx - 0.6, fx + 0.6, 0.5, 0.75, fz - 0.25, fz + 0.25, C.Fry, DECOR)
		else
			span(pond, "Fry", fx - 0.25, fx + 0.25, 0.5, 0.75, fz - 0.6, fz + 0.6, C.Fry, DECOR)
		end
	end
	-- little plank jetty from the west kerb
	span(pond, "Jetty", x0 - 1, 52.6, 0.9, 1.4, 81.6, 85.4, C.Plank)
	for _, z in { 81.9, 85.1 } do
		span(pond, "JettyPost", 52, 52.8, 0.4, 2.4, z - 0.4, z + 0.4, C.WoodDark)
	end
	-- the sign by the front kerb
	span(pond, "SignPost", 47.7, 48.3, 0, 3.4, z0 - 2, z0 - 1.2, C.WoodDark)
	local board = span(pond, "SignBoard", 45, 51, 3.2, 5.4, z0 - 2.2, z0 - 1.4, C.WoodLight)
	plainText(board, Enum.NormalId.Front, "МАЛЬКИ", C.Ink, false)
end

local function buildNetYard(template: any)
	local yard = U.model(template, "NetYard")
	span(yard, "Yard", -63, -45, -0.2, 0.45, 62, 101, C.Gravel, FLAT)
	-- net-drying frame: three posts and a pole, two nets with floats
	local nx = -54
	for _, z in { 66, 77, 88 } do
		span(yard, "NetPost", nx - 0.45, nx + 0.45, 0, 9.2, z - 0.45, z + 0.45, C.WoodDark, { CastShadow = true })
	end
	span(yard, "NetPole", nx - 0.3, nx + 0.3, 8.4, 9, 65.4, 88.6, C.Wood)
	for _, zs in { { 66.5, 76.5 }, { 77.5, 87.5 } } do
		span(yard, "Net", nx - 0.12, nx + 0.12, 2.4, 8.4, zs[1], zs[2], C.Rope, {
			Transparency = 0.35,
			CanCollide = false,
			CastShadow = false,
		})
	end
	for i, z in { 71.5, 82.5 } do
		span(yard, "NetFloat", nx - 0.5, nx + 0.5, 2.1, 2.9, z - 0.5, z + 0.5, if i == 1 then C.Cream else C.Red, DECOR)
	end
	-- fish drying rack: two posts, a bar, three fish hung by the tail
	local rz = 98
	for _, x in { -60, -48 } do
		span(yard, "RackPost", x - 0.45, x + 0.45, 0, 7.6, rz - 0.45, rz + 0.45, C.WoodDark)
	end
	span(yard, "RackBar", -60.3, -47.7, 6.8, 7.4, rz - 0.35, rz + 0.35, C.Wood)
	for i, x in { -56, -52 } do
		local c = if i % 2 == 1 then C.FishSilver else C.FishSilverDark
		span(yard, "FishTail", x - 0.9, x + 0.9, 6, 6.8, rz - 0.2, rz + 0.2, c, DECOR)
		span(yard, "DriedFish", x - 0.7, x + 0.7, 3.2, 6, rz - 0.3, rz + 0.3, c, DECOR)
	end
	-- crab traps stacked by the nets
	span(yard, "CrabTrap", -49.6, -46.4, LAWN - 0.1, 2.4, 64.4, 67.6, C.WoodLight)
	-- stone well with a little timber roof
	local wx, wz = -51, 108
	span(yard, "WellRing", wx - 3, wx + 3, 0, 2.8, wz - 3, wz + 3, C.StoneLight, { CastShadow = true })
	span(yard, "WellWater", wx - 2.2, wx + 2.2, 2.75, 2.95, wz - 2.2, wz + 2.2, C.Water, DECOR)
	for _, sx in { -1, 1 } do
		span(yard, "WellPost", wx + sx * 2.4 - 0.4, wx + sx * 2.4 + 0.4, 2.8, 8.6, wz - 0.4, wz + 0.4, C.WoodDark)
	end
	span(yard, "Crossbar", wx - 3, wx + 3, 7, 7.6, wz - 0.3, wz + 0.3, C.Wood, DECOR)
	ramp(yard, "WellRoof", wx - 4, wx + 4, 8.6, 10.8, wz - 3.4, wz, "-z", C.RoofBrown, { CastShadow = true })
	ramp(yard, "WellRoof", wx - 4, wx + 4, 8.6, 10.8, wz, wz + 3.4, "+z", C.RoofBrown)
	span(yard, "Bucket", wx - 0.6, wx + 0.6, 4.6, 5.8, wz - 0.6, wz + 0.6, C.Wood, DECOR)
end

-- Voxel tree from the prop library (layered dark / mid / light canopy, "lite + compact").
local function tree(parent: any, x: number, y: number, z: number, s: number, seed: number, palette: string, fruit: any?)
	Props.roundTree(parent, at(x, y, z), {
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
	tree(green, -61, LAWN, 57, 1.35, 11, "green", C.Red) -- apple tree by the garden
	tree(green, 61, LAWN, 112, 1.4, 14, "mint")
	tree(green, -58, TERRACE, 157, 1.35, 15, "green") -- shades the back of the patio
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
	-- back kerbs); the outer pair carries lanterns.
	local px = hw + 0.6
	local zs = {}
	local n = 4
	for i = 1, n do
		zs[i] = -3 + (PIER_END + 2.5 + 3) * (i - 1) / (n - 1)
	end
	for i, z in zs do
		local lantern = i == #zs
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
	for i, layer in { { 15, 1.2, ROOF_TRIM }, { 11.4, 1.4, ROOF }, { 7.8, 1.4, 0 }, { 3.6, 1.4, ROOF_TRIM } } do
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
	buildArcades(template)
	buildCourtGarden(template)
	buildDog(template)
	buildTerrace(template, plot)
	local smokeOffset = buildHouse(template)
	local shedSmokeOffset = buildSmokehouse(template)
	buildWorkYard(template)
	buildPatio(template)
	buildGarden(template)
	buildTackleShed(template)
	buildFryPond(template)
	buildNetYard(template)
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
