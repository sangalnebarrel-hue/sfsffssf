--[[
	Builds ServerStorage.BaseTemplate — one player base: a fisherman's homestead on the green
	island with an aquarium court (art direction v4, tools/builder/DESIGN.md §1 and §2 "Base-local
	frame"). BaseService clones it into the 8 slots and paints every part with attribute
	Accent = true in the base colour (optional AccentShade -1..1: > 0 lighter, towards white;
	< 0 darker in HSV), and every part with WallTone = true in the base's own calm wall tone
	(BaseConfig.WallTones; optional WallShade, same rule), so the 8 houses differ.

	Colour: a lawn with darker mowing stripes, warm two-tone flagstone walks, cream limestone, plank
	decks, timber, warm stone and plaster in a dark / mid / light hierarchy (stone base course, warm
	stone ground floor, plaster upper floor). The base colour (Accent) marks the base at a glance
	without flooding it: the roofs in a deep shade (house and tower -0.28, the two display arcades
	-0.38 with -0.5 battens; fascias and ridges darker), the doors; small full-colour accents — the
	flag, the arcade banners and eave boards, a band on every display cabinet, the gate sign's and
	the aquarium plaque's frames, the tackle shed's awning, the patio parasol, the mailbox, the boat,
	the small SpawnPad. Any Accent part bigger than ~400 studs² uses a deep shade (<= -0.25; tested).
	The colour pops are jewel-tone flowers (Palette.Flowers via Props.flowerBed, window boxes,
	flowering hedges), the aquarium's corals and fish, lanterns and the cyan light bars.

	Base-local frame (Root at the origin, y = 0 is GroundTop; the world builder provides flat
	grass under the plot):
	  -Z     towards the lagoon. lz 0..18 is the public promenade (the template places nothing
	         there except the start of the pier), lz 0..-PierLength (72) is the base's own pier.
	  +Z     inland: the plot x = -68..68, lz = 18..168.
	  +X/-X  sideways (+X is on the left of a player walking in through the gate).

	Layout (front to back, symmetric about the flagstone axis). The vista from the gate and the
	spawn runs over the low aquarium to the house, which stands on a 4.5-stud terrace at its end:
	nothing on the axis rises above the line from the spawn eye to the house's upper floor.
	  lz 18        roofed timber gate between stone piers (name board with OwnerLabel/BaseLabel on
	               both faces, gold fish weathervane), jewel flower beds; a stone-and-rail fence
	               with posts every ~17 studs
	  lz 22..54    front yard: the spawn rose (a two-tone flagstone compass rose, a cream stone
	               rosette with a cobble rim round the small SpawnPad, a gold fish inlay) framed by
	               flowering clipped hedges and two benches; the flag (the base's beacon) and the
	               signal mast (Alarm); the kitchen garden (-X: cabbages, pumpkins, bean poles), the
	               tackle shed (+X: rods, bait barrel, an awning) and a sitting spot with stepping
	               stones to the fry pond; the guard dog and its kennel are hidden here until the
	               stage-4 upgrade
	  lz 54..121   the aquarium court: the big tank as a long, low pool of bright sea water on a
	               flagstone terrace (a sea-blue gravel floor and back wall, a limestone castle,
	               coral reef, kelp, big bright fish, timber rim and corner posts with lanterns, the
	               «АКВАРИУМ» plaque at its foot) between two open display galleries (plank deck,
	               timber posts, a stone parapet with a flower box at the back so the displays show
	               from the side strips, a lean-to roof in the base colour over a light plank
	               ceiling, hanging lanterns, banners) holding the 12 display aquariums
	               (Tank.Slots.Slot_1..12: a timber cabinet with a base-colour band, a brass rim, a
	               bright water cube with sand, a sea-blue backdrop and a glowing light bar; odd
	               slots in the -X gallery, slots 1-2 nearest the gate); flower borders and potted
	               topiaries between them; flagstone cross walks front and back
	  side strips  +X: the fry pond (an L of water in kerbs and rim stones, lilies, reeds, a jetty
	               and a bench); -X: the net yard (green nets drying with floats, a fish rack under
	               a canvas lean-to, crab traps, the well, an upturned boat on trestles under repair,
	               lobster pots); fruit trees
	  lz 122..168  a 4.5-stud stone terrace (stairs with lanterns, plank ramps): the house — the
	               base's main building, a T plan (warm stone ground floor, plaster upper floor in
	               the wall tone, two dormers, a cross-gabled front wing with a porch, a balcony and
	               a door in the base colour, window boxes, windows on every side) with a lookout tower
	               (belvedere reached by a ladder, telescope, stepped Accent roof, fish weathervane);
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

	Budget: <= 860 parts (8 bases at runtime; asserted below and in tests/stage1_bases.test.luau).
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

local BUDGET = 860

------------------------------------------------------------------------------------------
-- Colours (all from Palette.luau, DESIGN.md §1) and plot numbers
------------------------------------------------------------------------------------------

-- A palette colour with its HSV saturation and value scaled (a livelier water tint, ...).
local function tune(color: any, sMul: number, vMul: number): any
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.clamp(s * sMul, 0, 1), math.clamp(v * vMul, 0, 1))
end

local C = {
	Lawn = P.GrassTop:Lerp(P.GrassTop3, 0.3), -- a kept lawn, a hair lighter than the island grass
	LawnStripe = P.GrassTop2:Lerp(P.GrassTop, 0.3), -- the darker mowing stripes
	Hedge = P.Leaf1,
	HedgeTop = P.Leaf1:Lerp(P.Leaf2, 0.7),
	Topiary = P.Leaf0:Lerp(P.Leaf1, 0.5),
	Flag = P.Flagstone, -- walks: light flags with darker ones set in
	FlagDark = P.FlagstoneDark:Lerp(P.CobbleDark, 0.45), -- the darker flags: they must read
	Limestone = P.Limestone, -- cream stone: terraces, kerbs, steps
	Gravel = P.SandDark:Lerp(P.Cobble, 0.45),
	Stone = P.Stone,
	StoneMid = P.Stone:Lerp(P.StoneLight, 0.35), -- the house's ground floor: a step darker than the plaster
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
	Ink = P.Dark, -- text, door holes, eyes (small dark details only)
	Glow = P.Glow, -- lantern cores (Neon)
	LightColor = P.LightColor,
	LampOff = P.Red:Lerp(P.Dark, 0.4), -- the alarm lamp when not alarmed (stage 4 lights it)
	WindowGlass = P.WindowBlue:Lerp(P.Cloud, 0.2), -- a bright sky-blue pane
	Water = P.Water,
	PondWater = P.Water:Lerp(P.WaterLight, 0.3),
	PondBed = P.Water:Lerp(P.Navy, 0.45),
	FishSilver = P.WindowBlue:Lerp(P.StoneLight, 0.45), -- drying fish
	FishSilverDark = P.WindowBlue:Lerp(P.Stone, 0.3),
	Cabinet = P.WoodLight:Lerp(P.CutWood, 0.35), -- display stands
	-- aquarium: bright sea water, light sand, a limestone castle and a coral reef
	TankGlass = tune(P.Water:Lerp(P.Cyan, 0.4):Lerp(P.WaterLight, 0.35), 1, 1.04), -- sea water (calm: S < 0.6)
	TankWater = tune(P.Water:Lerp(P.Cyan, 0.4), 1.08, 1.12), -- bright sea water ~ (55, 165, 205)
	DisplayWater = tune(P.Glass:Lerp(P.Cyan, 0.08), 1.25, 1.07), -- ~ (168, 222, 238)
	Backdrop = tune(P.Water:Lerp(P.Cyan, 0.5), 1.05, 1.14), -- ~ (60, 176, 206)
	AquaGlow = tune(P.WaterLight:Lerp(P.Cyan, 0.2), 1.2, 1.1), -- Neon light bars ~ (120, 220, 240)
	ReefLight = P.WaterLight,
	Sand = P.Sand:Lerp(P.Foam, 0.5), -- pale aquarium sand
	SeaFloor = tune(P.Water:Lerp(P.Cyan, 0.5), 1.05, 1.05), -- the tank's sea-blue gravel
	Castle = P.Limestone,
	CastleRoof = P.RoofTerracotta,
	Rock = P.RockLight, -- the reef's footing
	RockLight = P.Foam:Lerp(P.RockLight, 0.4),
	Kelp1 = P.Seaweed,
	Kelp2 = P.Leaf2,
	CoralPinkBase = P.Flowers[3]:Lerp(P.Flowers[4], 0.3),
	CoralPink = P.Flowers[3],
	CoralOrangeBase = P.Flowers[6]:Lerp(P.Autumn0, 0.3),
	CoralOrange = P.Flowers[6],
	CoralViolet = P.Flowers[4],
	BrainCoral = P.Flowers[2],
	Yellow = P.Yellow,
	Orange = P.Orange,
	Blue = P.Blue,
	White = P.White,
	Red = P.Red,
	RoofBlue = P.RoofBlue,
	RoofBrown = P.RoofBrown,
	Terracotta = P.RoofTerracotta, -- flower pots
	Rope = P.Rope,
	NetRope = P.Seaweed:Lerp(P.Navy, 0.3), -- drying nets: a fisherman's green in two tones
	NetRopeLight = P.Seaweed:Lerp(P.Mint2, 0.4),
	Brick = P.Brick,
	CobbleDark = P.CobbleDark,
	Boat = P.BoatPaint[2],
	Fry = P.Orange,
	-- the hidden guard dog (shown in stage 4): a shiba in warm, calm tones
	Dog = P.Wood:Lerp(P.Orange, 0.55),
	DogCream = P.Cream,
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
local STRIPE = 0.35 -- the darker mowing stripes laid on the lawn
local PATH = 0.5 -- flagstone walks (their darker flags stand 0.15 proud)
local ROSE = 0.75 -- spawn compass rose: dark square
local ROSE_TOP = 0.9 -- its light star
local RING = 1.05 -- the stone rosette round the pad
local ARC_DECK = 0.9 -- display arcades' plank deck
local TANK_TERRACE = 1.2 -- the aquarium's flagstone terrace
local TERRACE = 4.5 -- the house terrace (lawn top): the house stands high at the end of the vista
local DECK = 0.6 -- pier and platform deck top
local PLANK = 0.75 -- plank strips on the decks

local SPAWN_Z = 36
local TERRACE_Z = 122 -- the house terrace's front face

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
local GLASS = { Material = M.Glass, Transparency = 0.15, CastShadow = false }
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

-- Garden bench (seat on a leg block, a back rest) in frame `f` standing on y0; local -Z is where
-- the sitter looks. 3 parts.
local function bench(parent: any, f: any, y0: number, len: number)
	box(parent, "BenchLegs", f, 0, y0 + 0.6, 0.1, len - 1.2, 1.2, 0.9, C.WoodDark)
	box(parent, "BenchSeat", f, 0, y0 + 1.45, 0, len, 0.5, 1.9, C.WoodLight)
	box(parent, "BenchBack", f, 0, y0 + 2.7, 0.8, len, 1.7, 0.4, C.Wood)
end

-- Two-tone clipped shrub: a dark body and a lighter top block set off-centre. 2 parts.
local function shrub(parent: any, x: number, y: number, z: number, w: number, h: number, flip: number)
	span(parent, "Shrub", x - w / 2, x + w / 2, y - 0.2, y + h, z - w * 0.42, z + w * 0.42, C.Leaf1, {
		CanCollide = false,
	})
	local tx = x + flip * w * 0.12
	span(
		parent,
		"ShrubTop",
		tx - w * 0.3,
		tx + w * 0.3,
		y + h - 0.1,
		y + h + 1,
		z - w * 0.26,
		z + w * 0.26,
		C.Leaf3,
		DECOR
	)
end

-- Terracotta pot with a leafy ball and a bloom on top, standing on y0. 3 parts.
local function pottedPlant(parent: any, x: number, y0: number, z: number, bloom: any)
	span(parent, "Pot", x - 0.9, x + 0.9, y0, y0 + 1.5, z - 0.9, z + 0.9, C.Terracotta)
	span(parent, "PotLeaves", x - 1.1, x + 1.1, y0 + 1.4, y0 + 2.9, z - 1.1, z + 1.1, C.Leaf2, DECOR)
	span(parent, "PotBloom", x - 0.55, x + 0.45, y0 + 2.8, y0 + 3.5, z - 0.45, z + 0.55, bloom, DECOR)
end

-- Jewel-tone bloom pairs (Palette.Flowers: 1 red, 2 yellow, 3 pink, 4 violet, 5 white, 6 orange,
-- 7 blue) for the base's beds, boxes and baskets: the plot's colour pops.
local FL = P.Flowers
local JEWELS = {
	{ FL[1], FL[5] },
	{ FL[3], FL[4] },
	{ FL[2], FL[6] },
	{ FL[7], FL[5] },
	{ FL[6], FL[1] },
	{ FL[4], FL[3] },
}

------------------------------------------------------------------------------------------
-- Ground: lawn with mowing stripes, flagstone walks, the compass-rose spawn square
------------------------------------------------------------------------------------------

local ROSE_R = 6.5 -- half the spawn rose's dark square

local function buildGrounds(template: any, plot: any)
	local floor = U.model(template, "Grounds")
	local hw, front = plot.halfWidth, plot.front

	-- Lawn over the whole plot (the fence, the hedge and the house terrace stand on it).
	span(floor, "Lawn", -hw + 0.4, hw - 0.4, -0.4, LAWN, front + 0.4, plot.back - 0.4, C.Lawn)
	-- Mowing stripes: darker 8-stud bands running inland (Grow a Garden style); the outer ones run
	-- down the side strips to the house terrace.
	for _, sx in { -1, 1 } do
		for _, st in { { 8, 16, 54 }, { 24, 32, 54 }, { 40, 48, TERRACE_Z }, { 56, 64, TERRACE_Z } } do
			local xa, xb = mirror(sx, st[1], st[2])
			span(floor, "Stripe", xa, xb, LAWN - 0.1, STRIPE, front + 0.4, st[3] - 0.2, C.LawnStripe, FLAT)
		end
	end

	-- The axis: gate -> spawn rose -> aquarium court (no flags where the rose covers the walk).
	flagWalk(floor, "Walk", -5, 5, front + 0.2, 54, PATH, 6, function(u: number): boolean
		local z = front + 0.2 + u
		return z > SPAWN_Z - 10 and z < SPAWN_Z + 10
	end)
	-- Cross walks in front of and behind the aquarium terrace, joining the arcade decks.
	flagWalk(floor, "CrossWalk", -22.2, 22.2, 54, 60, PATH, 11)
	span(floor, "BackWalk", -22.2, 22.2, PATH - 0.45, PATH, 114, 120, C.Flag, FLAT)
	-- Side walks from the spawn rose to the kitchen garden (-X) and the tackle shed (+X).
	span(floor, "GardenWalk", -31, -6, PATH - 0.45, PATH, 34, 38, C.Flag, FLAT)
	span(floor, "ShedWalk", 6, 45.6, PATH - 0.45, PATH, 34, 38, C.Flag, FLAT)

	-- Spawn rose: a dark square under a light star (an eight-point compass rose); the stone rosette
	-- round the pad is in buildSpawn.
	local R = ROSE_R
	span(floor, "Rose", -R, R, PATH - 0.3, ROSE, SPAWN_Z - R, SPAWN_Z + R, C.FlagDark, FLAT)
	make(
		floor,
		"RoseStar",
		Vector3.new(2 * R - 0.6, ROSE_TOP - ROSE + 0.3, 2 * R - 0.6),
		at(0, (ROSE - 0.3 + ROSE_TOP) / 2, SPAWN_Z) * CFrame.Angles(0, rad(45), 0),
		C.Flag,
		FLAT
	)
	-- a gold fish inlaid in the rose between the pad and the gate
	local fz = SPAWN_Z - 5.6
	span(floor, "RoseFish", -1.6, 1, ROSE_TOP - 0.2, ROSE_TOP + 0.15, fz - 0.7, fz + 0.7, C.Gold, FLAT)
	span(floor, "RoseFishTail", 1, 2.1, ROSE_TOP - 0.2, ROSE_TOP + 0.15, fz - 1.1, fz + 1.1, C.Gold, FLAT)

	-- Flower beds just inside the gate: two rows of jewel blooms on stems over the leaves.
	for _, sx in { -1, 1 } do
		local pair = if sx < 0 then JEWELS[1] else JEWELS[2]
		flowerBed(floor, sx * 8.6, LAWN, front + 6.6, 6, 3.6, pair, { spacing = 1.6, max = 4 })
	end

	-- A low parterre round the rose: flowering clipped hedge blocks at its corners (jewel blooms
	-- on top), a bench either side looking at the rose.
	for _, sx in { -1, 1 } do
		local pair = if sx < 0 then JEWELS[3] else JEWELS[6]
		for i, zz in { { 25.5, 29.5 }, { 42.5, 46.5 } } do
			local xa, xb = mirror(sx, 9.5, 16)
			span(floor, "Parterre", xa, xb, LAWN - 0.1, 1.9, zz[1], zz[2], C.Hedge, { CanCollide = false })
			local zc = (zz[1] + zz[2]) / 2
			for j, bx in { 11.3, 14.2 } do
				local x = sx * bx
				local dz = if (i + j) % 2 == 0 then -0.6 else 0.7
				local c = pair[(i + j) % 2 + 1]
				span(floor, "HedgeBloom", x - 0.6, x + 0.6, 1.75, 2.5, zc + dz - 0.6, zc + dz + 0.6, c, DECOR)
			end
		end
		bench(floor, facing(sx * 22.5, LAWN, 41.6, 90 * sx), LAWN, 5.4)
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

	-- Front, either side of the gate (the gate piers end at x = +-16): posts every ~17 studs.
	for _, sx in { -1, 1 } do
		local posts = {}
		for i = 1, 3 do
			table.insert(posts, sx * (16 + (line - 16) * i / 3))
		end
		run(true, sx * 16, sx * (line + 0.8), sx * line, fz, posts, 0, 0)
	end
	-- Sides: from the front fence to the terrace (posts every ~17 studs); a hedge along the
	-- terrace's sides.
	for _, sx in { -1, 1 } do
		local z0 = fz + 0.55
		local posts = {}
		for i = 1, 5 do
			table.insert(posts, z0 + (TERRACE_Z - z0) * i / 5)
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
	-- A cream stone rosette (an eight-point star of two squares) with a dark cobble rim round the
	-- pad, set into the compass rose.
	local grounds = template:FindFirstChild("Grounds")
	local z = SPAWN_Z
	make(
		grounds,
		"Rosette",
		Vector3.new(7.4, RING - ROSE_TOP + 0.3, 7.4),
		at(0, (ROSE_TOP - 0.3 + RING) / 2, z) * CFrame.Angles(0, rad(45), 0),
		C.Limestone,
		FLAT
	)
	span(grounds, "RosetteRim", -2.75, 2.75, RING - 0.2, RING + 0.15, z - 2.75, z + 2.75, C.CobbleDark, FLAT)
	-- The pad: -Z (the lagoon) is the facing on spawn. Pure base colour (tests check it), a small
	-- 4-stud field.
	span(template, "SpawnPad", -2, 2, RING - 0.05, RING + 0.35, z - 2, z + 2, 0, {
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
-- The aquarium: a long, low show tank of bright sea water on its terrace
------------------------------------------------------------------------------------------

local TANK_HALF_X = 12
local TANK_Z0, TANK_Z1 = 69, 107
local TANK_BASE = TANK_TERRACE + 1.4 -- plinth top = glass bottom
local TANK_TOP = TANK_BASE + 6 -- low: from the spawn the house shows over it

local function buildTank(template: any): (any, { any })
	local tank = U.model(template, "Tank")
	local hx = TANK_HALF_X
	local expected = {}

	-- The court's centre: a flagstone terrace, a warm stone plinth with a cream ledge.
	span(tank, "Terrace", -16, 16, -0.2, TANK_TERRACE, 62, 114, C.Flag, { CastShadow = true })
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
		{ CastShadow = true }
	)
	span(tank, "Ledge", -hx - 0.8, hx + 0.8, TANK_BASE - 0.6, TANK_BASE, TANK_Z0 - 0.8, TANK_Z1 + 0.8, C.Limestone)

	-- The glass (one part: the whole volume; fish swim inside it later) with a light aqua tint, the
	-- bright sea water inside it and a painted sea-blue back wall at the far end (the tank reads
	-- blue from the gate and the house does not show through it).
	local glass = span(tank, "Glass", -hx, hx, TANK_BASE, TANK_TOP, TANK_Z0, TANK_Z1, C.TankGlass, {
		Material = M.Glass,
		Transparency = 0.6,
		CastShadow = false,
	})
	tank.PrimaryPart = glass
	local w = 0.3
	span(
		tank,
		"BackWall",
		-hx + w,
		hx - w,
		TANK_BASE,
		TANK_TOP - 0.3,
		TANK_Z1 - w - 0.4,
		TANK_Z1 - w,
		C.Backdrop,
		DECOR
	)
	-- Stage 3/4 prompts: in front of the tank's entrance end (towards the gate).
	local _, promptOffset = attachAt(glass, "PromptAttachment", at(0, TANK_TERRACE + 2, TANK_Z0 - 3))
	table.insert(expected, { root = "template", path = { "Tank", "Glass", "PromptAttachment" }, offset = promptOffset })

	-- Timber frame: corner posts (lanterns on the front pair), a rim round the top with light bars
	-- under it; nothing else breaks the water.
	for _, sx in { -1, 1 } do
		for _, z in { TANK_Z0, TANK_Z1 } do
			local x = sx * hx
			local lit = z == TANK_Z0 -- lanterns on the front posts, towards the gate
			local top = if lit then TANK_TOP + 1.3 else TANK_TOP + 0.7
			span(tank, "Post", x - 0.85, x + 0.85, TANK_BASE - 0.6, top, z - 0.85, z + 0.85, C.Wood, {
				CastShadow = true,
			})
			if lit then
				span(tank, "Lantern", x - 0.7, x + 0.7, top, top + 1.5, z - 0.7, z + 0.7, C.Glow, NEON_DECOR)
				span(tank, "LanternCap", x - 1.1, x + 1.1, top + 1.5, top + 2.1, z - 1.1, z + 1.1, C.Iron, DECOR)
			end
		end
		span(
			tank,
			"Rim",
			sx * hx - 0.6,
			sx * hx + 0.6,
			TANK_TOP,
			TANK_TOP + 0.7,
			TANK_Z0 + 0.85,
			TANK_Z1 - 0.85,
			C.Wood
		)
		local lx = sx * (hx - 0.9)
		span(
			tank,
			"LightBar",
			lx - 0.25,
			lx + 0.25,
			TANK_TOP - 0.5,
			TANK_TOP - 0.1,
			TANK_Z0 + 1.2,
			TANK_Z1 - 1.2,
			C.AquaGlow,
			NEON_DECOR
		)
	end
	for _, z in { TANK_Z0, TANK_Z1 } do
		span(tank, "Rim", -hx + 0.85, hx - 0.85, TANK_TOP, TANK_TOP + 0.7, z - 0.6, z + 0.6, C.Wood)
	end

	-- The «АКВАРИУМ» plaque at the foot of the glass, facing the gate: a cream board in a frame of
	-- the base colour (kept low: nothing over the tank hides the house from the spawn).
	local pz = TANK_Z0 - 2.05
	span(tank, "SignFrame", -7.6, 7.6, TANK_TERRACE - 0.1, TANK_BASE + 1, pz - 0.35, pz + 0.35, 0)
	local board = span(tank, "SignBoard", -7, 7, TANK_TERRACE + 0.2, TANK_BASE + 0.7, pz - 0.5, pz + 0.1, C.Cream)
	plainText(board, Enum.NormalId.Front, "АКВАРИУМ", C.Ink, false)

	-- Inside: light sand, a coral reef in the front corners and on a rock in the middle, kelp, a
	-- limestone castle at the back, a shoal of big bright fish, columns of rising bubbles
	-- (particles). A PointLight on the reef lights it all.
	local s = TANK_BASE + 0.7 -- sand top
	local sand = span(tank, "Sand", -hx + 0.2, hx - 0.2, TANK_BASE, s, TANK_Z0 + 0.2, TANK_Z1 - 0.2, C.SeaFloor, DECOR)
	span(tank, "SandBank", -8.5, 8.5, s - 0.3, s + 0.35, 94, 105.5, C.Sand, DECOR)
	-- the water line: a light surface just under the rim
	span(
		tank,
		"WaterSurface",
		-hx + 0.35,
		hx - 0.35,
		TANK_TOP - 0.5,
		TANK_TOP - 0.25,
		TANK_Z0 + 0.35,
		TANK_Z1 - 0.35,
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
	-- castle at the back: a keep, two towers with terracotta caps, a door
	piece("Castle", -3.2, 3.2, -0.2, 2.6, 97, 102, C.Castle)
	for _, sx in { -1, 1 } do
		local xa, xb = mirror(sx, 2.8, 5.4)
		piece("CastleTower", xa, xb, -0.2, 3.5, 96.6, 102.4, C.Castle)
		piece("TowerRoof", xa - 0.4, xb + 0.4, 3.5, 4.3, 96.2, 102.8, C.CastleRoof)
	end
	piece("CastleDoor", -0.9, 0.9, 0, 2, 96.8, 97, C.Ink)
	-- reef rock in the middle
	local reef = piece("Reef", -6, 4, -0.2, 1.4, 82, 92, C.Rock)
	piece("Reef", -4, 2, 1.4, 2.4, 83.5, 90, C.RockLight)
	U.new("PointLight", { Range = 16, Brightness = 2, Color = C.ReefLight, Shadows = false }, reef)
	-- corals: branching pink and orange in the front corners, violet and yellow on the reef, a
	-- yellow brain coral by the castle
	piece("Coral", -10.8, -6.4, -0.2, 2, 73, 77.4, C.CoralPinkBase)
	piece("CoralArm", -10, -7.6, 2, 4.2, 74, 76.2, C.CoralPink)
	piece("Coral", 6.4, 10.8, -0.2, 2, 73, 77.4, C.CoralOrangeBase)
	piece("CoralArm", 7.4, 9.8, 2, 4.4, 74.2, 76.4, C.CoralOrange)
	piece("FanCoral", -2.6, -0.4, 2.4, 4.4, 85.4, 86.6, C.CoralViolet)
	piece("Coral", 0.6, 2.6, 2.4, 3.6, 87.6, 89.6, C.BrainCoral)
	piece("BrainCoral", 7, 11, -0.2, 1.8, 98, 103, C.CoralPink)
	-- kelp
	piece("Kelp", -9.8, -8.2, -0.2, 4.4, 95, 96.6, C.Kelp1)
	piece("Kelp", 8.4, 9.8, -0.2, 4, 86, 87.4, C.Kelp2)
	-- fish: a body and a tall tail fin; most swim across the tank (their profile shows from the gate)
	for _, f in
		{
			{ -4, 2.8, 74.6, true, 1, 3.6, FL[2], FL[7] },
			{ 5, 1.5, 80, true, -1, 3, FL[6], FL[5] },
			{ -7, 3.3, 89, false, 1, 3.2, FL[7], FL[2] },
			{ 3, 3.6, 84.5, true, -1, 3.2, FL[1], FL[5] },
			{ 7.6, 2.4, 93, false, -1, 2.8, FL[4], FL[2] },
			{ -7.4, 2, 100.5, true, 1, 2.8, FL[3], FL[5] },
		}
	do
		local x, y, z, alongX, dir, len = f[1], s + f[2], f[3], f[4], f[5], f[6]
		local h = len * 0.6
		local tx = x - dir * (len / 2 + 0.45) -- the tail behind the body
		if alongX then
			span(tank, "Fish", x - len / 2, x + len / 2, y - h / 2, y + h / 2, z - 0.6, z + 0.6, f[7], DECOR)
			span(tank, "FishTail", tx - 0.45, tx + 0.45, y - h * 0.65, y + h * 0.65, z - 0.25, z + 0.25, f[8], DECOR)
		else
			local tz = z - dir * (len / 2 + 0.45)
			span(tank, "Fish", x - 0.6, x + 0.6, y - h / 2, y + h / 2, z - len / 2, z + len / 2, f[7], DECOR)
			span(tank, "FishTail", x - 0.25, x + 0.25, y - h * 0.65, y + h * 0.65, tz - 0.45, tz + 0.45, f[8], DECOR)
		end
	end
	-- columns of bubbles (particles: they move and cost no parts); they live at most 3 s
	for _, b in { { "BubblesWest", -3.6, 92 }, { "BubblesEast", 3.4, 80 } } do
		local attachment, offset = attachAt(sand, b[1], at(b[2], s + 0.4, b[3]))
		Props.fx(attachment, "bubbles", { rate = 3, size = 1.5, lifetime = U.roblox.NumberRange.new(2.6, 3) })
		table.insert(expected, { root = "template", path = { "Tank", "Sand", b[1] }, offset = offset })
	end

	return tank, expected
end

------------------------------------------------------------------------------------------
-- Display arcades and the 12 display aquariums
------------------------------------------------------------------------------------------

local ARC_IN, ARC_WALL = 22, 40 -- each arcade: deck from |x| = 22 (the aisle) to its back parapet
local ARC_Z0, ARC_Z1 = 54, 121
local ARC_EAVE = 16 -- the lean-to roof's front (low) edge: high, so the displays sit in daylight
local ARC_TOP = 19.5 -- its back (high) edge, over the open back
local ARC_POSTS = { ARC_Z0 + 1, 77.5, 99.5, ARC_Z1 - 1 }
local PARAPET = 3 -- the open back's stone parapet (its coping on top)
local SLOT_ROW_X = 30
local SLOT_Z0, SLOT_PITCH = 61, 11

-- One display aquarium: a timber cabinet with a band of the base colour, a brass rim, a cube of
-- bright water with a sand floor, a sea-blue backdrop and a glowing light bar
-- along its top (the fish floats in its centre). Local frame: -Z faces the aisle. The label
-- (owner's fish or "Пусто") and the slot number are on the cabinet's front.
local function buildSlot(slots: any, index: number, frame: any, expected: { any })
	local slot = U.model(slots, `Slot_{index}`)
	slot:SetAttribute("SlotIndex", index)
	local y0 = ARC_DECK
	local pedestal = box(slot, "Pedestal", frame, 0, y0 + 1.7, 0, 6.8, 3.4, 6.8, C.Cabinet, { CastShadow = true })
	local top = y0 + 3.4
	box(slot, "Band", frame, 0, top - 0.25, -3.45, 7, 0.5, 0.3, 0.1, DECOR)
	box(slot, "Rim", frame, 0, top + 0.3, 0, 7.4, 0.6, 7.4, C.Gold)
	local base = top + 0.6
	local display = box(slot, "Display", frame, 0, base + 3.1, 0, 6.2, 6.2, 6.2, C.DisplayWater, {
		Material = M.Glass,
		Transparency = 0.45,
		CastShadow = false,
	})
	box(slot, "Sand", frame, 0, base + 0.35, 0, 5.8, 0.7, 5.8, C.Sand, DECOR)
	-- a sea-blue backdrop on the back pane (the fish reads against it)
	box(slot, "Backdrop", frame, 0, base + 3.2, 3.05, 6.6, 6.4, 0.5, C.Backdrop, DECOR)
	-- the light bar along the top front edge
	box(slot, "LightBar", frame, 0, base + 6.35, -2.95, 6.4, 0.3, 0.35, C.AquaGlow, NEON_DECOR)
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
		Position = UDim2.fromScale(0.06, 0.44),
		Size = UDim2.fromScale(0.88, 0.48),
		BackgroundTransparency = 1,
		Text = "Пусто",
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = C.Ink,
	}, gui)
	U.new("TextLabel", {
		Name = "Number",
		Position = UDim2.fromScale(0.3, 0.17),
		Size = UDim2.fromScale(0.4, 0.25),
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

-- The two arcades either side of the aquarium: open timber galleries. A plank deck, timber posts
-- and beam along the aisle and along the open back (over a stone parapet with a cream coping, so
-- the displays show from the side strips), a lean-to roof in a deep shade of the base colour
-- (darker battens, a lighter eave board), lanterns hanging between the display pairs, banners in
-- the base colour, a flower box on the parapet, a light plank ceiling.
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
		-- the open back: a stone parapet with a cream coping between stone pillars, timber posts
		-- carrying the wall plate (the roof's high beam)
		xa, xb = X(ARC_WALL - 0.3, ARC_WALL + 1.7)
		span(arc, "Parapet", xa, xb, -0.2, PARAPET, ARC_Z0 + 0.3, ARC_Z1 - 0.3, C.Stone, { CastShadow = true })
		xa, xb = X(ARC_WALL - 0.6, ARC_WALL + 2)
		span(arc, "Coping", xa, xb, PARAPET, PARAPET + 0.5, ARC_Z0 + 0.3, ARC_Z1 - 0.3, C.Limestone)
		local plateBottom = ARC_EAVE - 1.1
		xa, xb = X(ARC_WALL - 0.2, ARC_WALL + 1.6)
		span(arc, "WallPlate", xa, xb, plateBottom, ARC_EAVE, ARC_Z0 + 0.3, ARC_Z1 - 0.3, C.WoodDark)
		xa, xb = X(ARC_WALL - 0.6, ARC_WALL + 2)
		for _, z in { ARC_Z0, ARC_Z1 } do
			span(arc, "Pillar", xa, xb, -0.2, ARC_EAVE, z - 1.3, z + 1.3, C.Stone, { CastShadow = true })
		end
		xa, xb = X(ARC_WALL + 0.1, ARC_WALL + 1.3)
		for _, z in { ARC_POSTS[2], ARC_POSTS[3] } do
			span(arc, "BackPost", xa, xb, PARAPET + 0.5, plateBottom, z - 0.6, z + 0.6, C.Wood, { CastShadow = true })
		end
		-- posts and the front beam
		local beamBottom = ARC_EAVE - 1.2
		xa, xb = X(ARC_IN + 0.4, ARC_IN + 1.6)
		for _, z in ARC_POSTS do
			span(arc, "Post", xa, xb, ARC_DECK, beamBottom, z - 0.6, z + 0.6, C.Wood, { CastShadow = true })
		end
		xa, xb = X(ARC_IN + 0.2, ARC_IN + 1.8)
		span(arc, "Beam", xa, xb, beamBottom, ARC_EAVE, ARC_Z0 - 0.4, ARC_Z1 + 0.4, C.WoodDark)
		-- lean-to roof in a deep shade of the base colour, its slope down towards the aisle; darker
		-- battens over the posts, a lighter eave board
		xa, xb = X(ARC_IN - 0.8, ARC_WALL + 2.2)
		local down = if sx > 0 then "-x" else "+x"
		ramp(arc, "Roof", xa, xb, ARC_EAVE, ARC_TOP, ARC_Z0 - 1.2, ARC_Z1 + 1.2, down, -0.38, ROOF_OPTS)
		for _, z in { ARC_POSTS[2], ARC_POSTS[3] } do
			ramp(arc, "RoofBatten", xa, xb, ARC_EAVE + 0.3, ARC_TOP + 0.3, z - 0.8, z + 0.8, down, -0.5, DECOR)
		end
		xa, xb = X(ARC_IN - 1.2, ARC_IN - 0.4)
		span(arc, "Fascia", xa, xb, ARC_EAVE - 0.5, ARC_EAVE + 0.7, ARC_Z0 - 1.4, ARC_Z1 + 1.4, FASCIA, DECOR)
		-- a light plank ceiling under the roof (the gallery is bright inside)
		xa, xb = X(ARC_IN + 1.8, ARC_WALL - 0.2)
		span(arc, "Ceiling", xa, xb, ARC_EAVE - 0.35, ARC_EAVE - 0.05, ARC_Z0 - 0.4, ARC_Z1 + 0.4, C.WoodLight, FLAT)
		-- lanterns between the display pairs; banners on the middle posts, facing the aisle
		for i, z in { 66.5, 88.5, 110.5 } do
			hangLantern(arc, sx * (ARC_IN + 1), beamBottom, z, i == 2)
		end
		xa, xb = X(ARC_IN + 0.05, ARC_IN + 0.4)
		for _, z in { ARC_POSTS[2], ARC_POSTS[3] } do
			span(arc, "Banner", xa, xb, 7.2, 12.6, z - 1.2, z + 1.2, 0, DECOR)
		end
		-- a flower box on the parapet's middle bay
		local pair = if sx < 0 then JEWELS[5] else JEWELS[2]
		flowerBed(arc, sx * (ARC_WALL + 0.7), PARAPET + 0.5, (ARC_POSTS[2] + ARC_POSTS[3]) / 2, 14, 1.6, pair, {
			alongZ = true,
			kerb = C.Wood,
			stems = false,
			spacing = 2.6,
			max = 5,
		})
	end
end

-- Lawn borders between the aquarium terrace and the arcades: a long bed of jewel blooms and a
-- clipped topiary (two stepped tiers in a terracotta pot) at the court's entrance.
local function buildCourtGarden(template: any)
	local garden = U.model(template, "CourtGarden")
	for _, sx in { -1, 1 } do
		local pair = if sx < 0 then JEWELS[3] else JEWELS[1]
		flowerBed(garden, sx * 19, LAWN, 89, 26, 3.2, pair, { alongZ = true, stems = false, spacing = 2.6, max = 9 })
		for _, z in { 66 } do
			local x = sx * 19
			span(garden, "TopiaryPot", x - 1.4, x + 1.4, LAWN - 0.1, 1.8, z - 1.4, z + 1.4, C.Terracotta)
			span(garden, "Topiary", x - 1.5, x + 1.5, 1.8, 4.2, z - 1.5, z + 1.5, C.Topiary, DECOR)
			span(garden, "Topiary", x - 1, x + 1, 4.2, 6, z - 1, z + 1, C.Leaf3, DECOR)
		end
	end
end

------------------------------------------------------------------------------------------
-- The guard dog and its kennel (stage 4 upgrade): hidden
------------------------------------------------------------------------------------------

local DOG_X, DOG_Z = 31, 47
local HIDDEN = { Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false }

-- Blocky shiba lying by its kennel; local -Z = where it looks. Hidden (see the header): every
-- part is invisible and takes no collisions, raycasts or shadows; Unlocked = false.
local function buildDog(template: any)
	local dog = U.model(template, "Dog")
	dog:SetAttribute("Unlocked", false)
	-- the kennel (the door looks towards -X, the spawn rose)
	local kennel = U.model(dog, "DogHouse")
	local k = facing(DOG_X, LAWN, DOG_Z, 90)
	box(kennel, "Walls", k, 0, 0.6 + 2.3, 0, 6.4, 5.2, 6.4, C.Wood, HIDDEN)
	box(kennel, "DoorHole", k, 0, 0.6 + 1.6, -3.25, 2.6, 3.2, 0.2, C.Ink, HIDDEN)
	rampIn(kennel, "Roof", k, -4.2, 0, 5.2, 8.2, -4.2, 4.2, "-x", ROOF, HIDDEN)
	rampIn(kennel, "Roof", k, 0, 4.2, 5.2, 8.2, -4.2, 4.2, "+x", ROOF, HIDDEN)

	local S = 1.5
	local f = facing(DOG_X - 6.5, LAWN, DOG_Z + 1.5, 70) -- beside the kennel door, looking at the rose
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
	for _, sx in { -1, 1 } do
		piece("Eye", sx * 0.46, 2.78, -1.93, 0.26, 0.36, 0.1, C.Ink)
		piece("Ear", sx * 0.6, 3.55, -1.05, 0.5, 0.62, 0.42, C.Dog)
	end
	piece("FrontLegs", 0, 0.4, -0.65, 1.4, 0.8, 0.5, C.DogCream)
	piece("BackLegs", 0, 0.4, 1.0, 1.4, 0.8, 0.5, C.Dog)
	piece("Tail", 0, 2.25, 1.45, 0.6, 0.9, 0.6, C.DogCream)
	piece("Collar", 0, 1.95, -0.8, 1.75, 0.36, 1.2, 0)
	dog.PrimaryPart = body
end

------------------------------------------------------------------------------------------
-- The house terrace, the house with its lookout tower, the smokehouse
------------------------------------------------------------------------------------------

-- A 4.5-stud stone terrace across the back of the plot (lawn on top, limestone coping): the house
-- stands high at the end of the vista from the gate. Central stairs with lanterns on their
-- cheeks, plank ramps at the side strips, a flagstone walk along its front.
local function buildTerrace(template: any, plot: any)
	local terrace = U.model(template, "Terrace")
	local hw, back = plot.halfWidth - 2.4, plot.back - 0.2
	local z0 = TERRACE_Z
	span(terrace, "Retaining", -hw, hw, -0.2, TERRACE - 0.2, z0, back, C.Stone, { CastShadow = true })
	span(terrace, "TerraceLawn", -hw + 0.2, hw - 0.2, TERRACE - 0.4, TERRACE, z0 + 0.6, back - 0.2, C.Lawn, FLAT)
	span(terrace, "Coping", -hw - 0.2, hw + 0.2, TERRACE - 0.5, TERRACE + 0.15, z0 - 0.6, z0 + 0.6, C.Limestone)
	-- central stairs: four 1.1-stud steps
	local run = 5.2
	for i = 1, 4 do
		span(terrace, "Step", -7, 7, -0.2, i * 1.1, z0 - run + (i - 1) * run / 4, z0 + 0.1, C.Limestone)
	end
	for _, sx in { -1, 1 } do
		local xa, xb = mirror(sx, 7, 8.4)
		span(terrace, "StairCheek", xa, xb, -0.2, TERRACE + 0.6, z0 - run - 0.2, z0 + 0.6, C.Limestone)
		local lx = sx * 7.7
		local lz = z0 - run / 2
		span(
			terrace,
			"Lantern",
			lx - 0.7,
			lx + 0.7,
			TERRACE + 0.6,
			TERRACE + 2.2,
			lz - 0.7,
			lz + 0.7,
			C.Glow,
			NEON_DECOR
		)
		span(
			terrace,
			"LanternCap",
			lx - 0.95,
			lx + 0.95,
			TERRACE + 2.2,
			TERRACE + 2.7,
			lz - 0.95,
			lz + 0.95,
			C.Iron,
			DECOR
		)
		-- plank ramp up from the side strip
		local ra, rb = mirror(sx, 44, 50)
		ramp(terrace, "Ramp", ra, rb, -0.2, TERRACE, z0 - 9, z0 + 0.05, "-z", C.Plank)
	end
	-- the walk along the terrace's front: stairs -> porch, patio (-X), work yard (+X)
	flagWalk(terrace, "TerraceWalk", -56, 56, z0 + 0.6, z0 + 4.4, TERRACE + 0.3, 22, function(u: number): boolean
		return math.abs(-56 + u) < 9
	end)
end

local MAIN_X, MAIN_Z0, MAIN_Z1 = 24, 140, 160 -- the house's main block
local WING_X, WING_Z0 = 10, 132 -- the front wing (x = +-10, from lz 132 to the main block)
local GF_TOP = 12 -- ground-floor stone walls top (the floor band above)
local UF_BOT = 12.8 -- upper floor plaster from here
local WALL_TOP = 20
local EAVE = 20.8
local GY, UY = 8.8, 16.4 -- window centres: ground floor, upper floor

-- Window box with two blooms under a window centred at (x, y) on the front wall z. 3 parts.
local function windowBox(parent: any, x: number, y: number, z: number, w: number, pair: { any })
	span(parent, "WindowBox", x - w / 2 - 0.5, x + w / 2 + 0.5, y - 1.1, y, z - 1.2, z, C.Wood)
	span(parent, "Bloom", x - w / 4 - 0.75, x - w / 4 + 0.55, y - 0.2, y + 0.7, z - 1.05, z - 0.25, pair[1], DECOR)
	span(parent, "Bloom", x + w / 4 - 0.55, x + w / 4 + 0.65, y - 0.25, y + 0.6, z - 1, z - 0.3, pair[2], DECOR)
end

-- Returns the chimney smoke attachment's offset.
local function buildHouse(template: any): any
	local house = U.model(template, "House")
	local F = TERRACE
	local x0, x1, z0, z1 = -MAIN_X, MAIN_X, MAIN_Z0, MAIN_Z1
	local zc = (z0 + z1) / 2

	-- Main block: a dark stone base course, a warm stone ground floor, a timber floor band, the
	-- plaster upper floor (the base's wall tone) with timber corners, the wall plate, a gable roof
	-- in the base colour (ridge along X, plaster gables jettied 1 out).
	span(house, "BaseCourse", x0 - 0.6, x1 + 0.6, F - 0.2, F + 1.4, z0 - 0.6, z1 + 0.6, C.Stone, { CastShadow = true })
	span(house, "GroundWalls", x0, x1, F + 1.4, GF_TOP, z0, z1, C.StoneMid, { CastShadow = true })
	span(house, "FloorBand", x0 - 0.3, x1 + 0.3, GF_TOP, UF_BOT, z0 - 0.3, z1 + 0.3, C.WoodDark)
	span(house, "Walls", x0, x1, UF_BOT, WALL_TOP, z0, z1, WALL, { CastShadow = true })
	for _, x in { x0, x1 } do
		for _, z in { z0, z1 } do
			local xa = if x == x0 then x - 0.35 else x - 0.85
			local za = if z == z0 then z - 0.35 else z - 0.85
			span(house, "Corner", xa, xa + 1.2, UF_BOT, WALL_TOP, za, za + 1.2, C.Wood)
		end
	end
	span(house, "WallPlate", x0 - 1.2, x1 + 1.2, WALL_TOP, EAVE, z0 - 0.3, z1 + 0.3, C.WoodDark, { CastShadow = true })
	local mainRise = 11
	gableRoof(house, x0, x1, z0, z1, EAVE, mainRise, 2.2, 1, true, WALL)
	local slope = mainRise / (zc - (z0 - 2.2)) -- rise per stud of the main slopes

	-- Chimney through the back slope, a lazy plume of smoke above it.
	local chimneyTop = EAVE + mainRise + 2
	span(house, "Chimney", 13, 16.4, WALL_TOP, chimneyTop, zc + 2.5, zc + 5.9, C.StoneLight, { CastShadow = true })
	local cap = span(house, "ChimneyCap", 12.6, 16.8, chimneyTop, chimneyTop + 0.8, zc + 2.1, zc + 6.3, C.Stone)
	local smoke, smokeOffset = attachAt(cap, "SmokeAttachment", at(14.7, chimneyTop + 2.4, zc + 4.2))
	Props.fx(smoke, "smoke", { rate = 2.5 })

	-- Two dormers on the front slope either side of the wing: a plaster face with a window under a
	-- little gable roof in the base colour.
	for _, sx in { -1, 1 } do
		local da, db = mirror(sx, 14.4, 19.6)
		local dc = sx * 17
		local dTop = EAVE + 5.8
		span(house, "Dormer", da, db, EAVE, dTop, z0, z0 + 6.5, WALL, { CastShadow = true })
		window(house, at(dc, EAVE + 3.6, z0), 2, 2, "small")
		local dEnd = (z0 - 2.2) + (dTop + 2.2 - EAVE) / slope + 0.6
		ramp(house, "DormerRoof", dc - 3, dc, dTop, dTop + 2.2, z0 - 0.8, dEnd, "-x", ROOF, { CastShadow = true })
		ramp(house, "DormerRoof", dc, dc + 3, dTop, dTop + 2.2, z0 - 0.8, dEnd, "+x", ROOF, { CastShadow = true })
	end

	-- Front wing (a cross gable facing the gate): same storeys, its roof running into the main one.
	local wx, wz0 = WING_X, WING_Z0
	span(house, "WingCourse", -wx - 0.6, wx + 0.6, F - 0.2, F + 1.4, wz0 - 0.6, z0, C.Stone)
	span(house, "WingGround", -wx, wx, F + 1.4, GF_TOP, wz0, z0 + 0.2, C.StoneMid, { CastShadow = true })
	span(house, "WingBand", -wx - 0.3, wx + 0.3, GF_TOP, UF_BOT, wz0 - 0.3, z0, C.WoodDark)
	span(house, "WingWalls", -wx, wx, UF_BOT, WALL_TOP, wz0, z0 + 0.2, WALL, { CastShadow = true })
	for _, sx in { -1, 1 } do
		local xa = if sx < 0 then -wx - 0.35 else wx - 0.85
		span(house, "Corner", xa, xa + 1.2, UF_BOT, WALL_TOP, wz0 - 0.35, wz0 + 0.85, C.Wood)
	end
	local wg, we, wrise = 1.8, 1.6, 8
	span(house, "WingPlate", -wx - 0.3, wx + 0.3, WALL_TOP, EAVE, wz0 - wg - 0.2, z0, C.WoodDark)
	local mainEaveZ = z0 - 2.2
	local wtop = EAVE + wrise
	local wzEnd = mainEaveZ + wrise / slope -- where the wing ridge meets the main slope
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
	window(house, at(0, EAVE + 2.6, wz0 - wg - 0.1), 2.4, 2.2, "small")

	-- Porch under a balcony at the wing's front: plank deck, two posts, the balcony with rails and a
	-- planted box, the front door (base colour), the balcony door, a wall lamp, a bench.
	local pz0 = wz0 - 5
	span(house, "Porch", -8, 8, F - 0.2, F + 0.8, pz0, wz0, C.Plank, { CastShadow = true })
	local by = UF_BOT + 0.1 -- balcony floor top
	for _, sx in { -1, 1 } do
		local pa, pb = mirror(sx, 7, 7.8)
		span(house, "PorchPost", pa, pb, F + 0.8, GF_TOP + 0.1, pz0 + 0.3, pz0 + 1.1, C.Wood, { CastShadow = true })
		local na, nb = mirror(sx, 7.7, 8.4)
		span(house, "Newel", na, nb, by, by + 3.2, pz0 - 0.2, pz0 + 0.5, C.Wood)
		local ra, rb = mirror(sx, 7.75, 8.25)
		span(house, "BalconyRail", ra, rb, by + 2.4, by + 2.9, pz0 + 0.5, wz0, C.WoodLight)
	end
	span(house, "Balcony", -8.3, 8.3, GF_TOP + 0.1, by, pz0 - 0.3, wz0 - 0.05, C.Wood, { CastShadow = true })
	span(house, "BalconyRail", -7.7, 7.7, by + 2.4, by + 2.9, pz0 - 0.15, pz0 + 0.35, C.WoodLight)
	span(house, "BalconyBox", -5, 5, by + 1.5, by + 2.4, pz0 - 0.9, pz0 - 0.15, C.Wood, DECOR)
	span(house, "BoxLeaves", -4.7, 4.7, by + 2.4, by + 2.8, pz0 - 0.8, pz0 - 0.25, C.Leaf2, DECOR)
	for i, x in { -3, 1.7 } do
		local c = if i == 2 then FL[5] else FL[1]
		span(house, "Bloom", x, x + 1.3, by + 2.6, by + 3.4, pz0 - 0.9, pz0 - 0.15, c, DECOR)
	end
	span(house, "DoorFrame", -2.4, 2.4, F + 0.8, F + 7.6, wz0 - 0.3, wz0, C.WoodDark)
	span(house, "Door", -1.8, 1.8, F + 0.8, F + 7, wz0 - 0.45, wz0 - 0.25, -0.3)
	span(house, "DoorWindow", -0.8, 0.8, F + 4.6, F + 6, wz0 - 0.55, wz0 - 0.4, C.WindowGlass, GLASS)
	span(house, "DoorKnob", 1, 1.5, F + 3.4, F + 3.9, wz0 - 0.75, wz0 - 0.4, C.Gold, DECOR)
	span(house, "BalconyDoor", -1.9, 1.9, by - 0.1, by + 4.9, wz0 - 0.3, wz0, C.WoodDark)
	span(house, "BalconyGlass", -1.4, 1.4, by, by + 4.4, wz0 - 0.45, wz0 - 0.25, C.WindowGlass, GLASS)
	local lamp = span(house, "WallLamp", 2.7, 3.7, F + 4.9, F + 6, wz0 - 1.1, wz0 - 0.1, C.Glow, NEON_DECOR)
	U.new("PointLight", { Range = 14, Brightness = 1, Color = C.LightColor, Shadows = false }, lamp)
	span(house, "PorchBench", -7.4, -4.6, F + 0.8, F + 1.9, wz0 - 2.2, wz0 - 1, C.WoodLight)

	-- Windows on every side.
	for _, sx in { -1, 1 } do
		-- wing front: simple windows either side of the door; small ones upstairs
		window(house, at(sx * 6.2, GY, wz0), 2.4, 3.4, "small")
		window(house, at(sx * 5.6, UY, wz0), 2.2, 2.8, "small")
		-- main front either side of the wing: full windows (shutters, window box) downstairs, a
		-- window with a window box upstairs
		local pair = if sx < 0 then JEWELS[1] else JEWELS[2]
		window(house, at(sx * 17, GY, z0), 3, 3.4, "full", pair[1], pair[2])
		window(house, at(sx * 17, UY, z0), 3, 2.8, "small")
		windowBox(house, sx * 17, UY - 1.85, z0, 3, if sx < 0 then JEWELS[3] else JEWELS[4])
		-- gable sides: a simple window downstairs, a small one upstairs
		local gx = sx * MAIN_X
		window(house, facing(gx, GY, zc - 4, -90 * sx), 3, 3.2, "simple")
		window(house, facing(gx, UY, zc + 4, -90 * sx), 2.6, 2.6, "small")
	end
	-- back (towards the hedge and the hill): a back door in the base colour, two windows upstairs
	for _, x in { -14, 14 } do
		window(house, facing(x, UY, z1, 180), 2.6, 2.6, "small")
	end
	span(house, "BackDoorFrame", 2.6, 6.8, F + 1.4, F + 8, z1, z1 + 0.3, C.WoodDark)
	span(house, "BackDoor", 3.1, 6.3, F + 1.4, F + 7.5, z1 + 0.25, z1 + 0.45, -0.3)

	-- Lookout tower at the front-left corner: stone shaft, timber bands, slit windows, an open
	-- belvedere with rails and a telescope, a stepped roof in the base colour, a fish weathervane.
	-- A ladder on its outer face climbs to the belvedere (an invisible TrussPart, rails and rungs).
	local tx0, tx1, tz0, tz1 = -32.5, -23.5, 131, z0 + 0.4
	local tcx, tcz = (tx0 + tx1) / 2, (tz0 + tz1) / 2
	local bf = 30 -- belvedere floor (bottom)
	span(house, "TowerBase", tx0 - 0.6, tx1 + 0.6, F - 0.2, F + 1.6, tz0 - 0.6, tz1, C.Stone, { CastShadow = true })
	span(house, "Tower", tx0, tx1, F + 1.6, bf, tz0, tz1, C.StoneLight, { CastShadow = true })
	span(house, "TowerBand", tx0 - 0.3, tx1 + 0.3, GF_TOP, UF_BOT, tz0 - 0.3, tz1, C.WoodDark)
	span(house, "TowerBand", tx0 - 0.3, tx1 + 0.3, WALL_TOP, EAVE, tz0 - 0.3, tz1, C.WoodDark)
	for _, y in { UY - 2, 25.2 } do
		window(house, at(tcx, y, tz0), 1.8, 2.6, "small")
	end
	window(house, facing(tx1, 25.2, tcz - 1.5, -90), 1.8, 2.6, "small")
	span(house, "Belvedere", tx0 - 1.2, tx1 + 1.2, bf, bf + 1, tz0 - 1.2, tz1 + 0.8, C.Wood, { CastShadow = true })
	local bt = bf + 6.6 -- roof base
	local px0, px1, pz0b, pz1b = tx0 - 0.6, tx1 + 0.6, tz0 - 0.6, tz1 + 0.2
	for _, x in { px0, px1 } do
		for _, z in { pz0b, pz1b } do
			span(house, "BelvederePost", x - 0.45, x + 0.45, bf + 1, bt, z - 0.45, z + 0.45, C.WoodDark)
		end
	end
	-- rails on three sides; the ladder arrives on the open -X side
	span(house, "BelvedereRail", px0, px1, bf + 3.2, bf + 3.7, pz0b - 0.2, pz0b + 0.2, C.WoodLight)
	span(house, "BelvedereRail", px0, px1, bf + 3.2, bf + 3.7, pz1b - 0.2, pz1b + 0.2, C.WoodLight)
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
	-- the ladder: rails from the terrace to above the belvedere floor, rungs, the climbable truss
	local lx = tx0 - 1.9
	for _, dz in { -1.1, 1.1 } do
		span(house, "LadderRail", lx - 0.25, lx + 0.25, F - 0.2, bf + 3.6, tcz + dz - 0.25, tcz + dz + 0.25, C.WoodDark)
	end
	local y = F + 2
	while y < bf do
		span(house, "Rung", lx - 0.2, lx + 0.2, y, y + 0.35, tcz - 0.9, tcz + 0.9, C.Wood, DECOR)
		y += 4.6
	end
	local trussH = math.ceil((bf + 3 - F) / 2) * 2
	U.partCount += 1
	U.new("TrussPart", {
		Name = "LadderTruss",
		Size = Vector3.new(2, trussH, 2),
		CFrame = at(lx - 0.6, F + trussH / 2, tcz),
		Anchored = true,
		Transparency = 1,
		CastShadow = false,
		CanTouch = false,
		Color = C.Wood,
	}, house)

	y = bt
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

	-- Planted beds along the main front either side of the wing.
	for _, sx in { -1, 1 } do
		local pair = if sx < 0 then JEWELS[5] else JEWELS[6]
		flowerBed(house, sx * 17, F, z0 - 2.6, 9, 2.4, pair, { stems = false, spacing = 1.8, max = 4 })
	end
	return smokeOffset
end

-- The smokehouse (+X of the house, on the terrace): timber walls on a stone footing, gable to the
-- front with a hoist beam, double doors, an iron smoking pipe, a net hung on its side.
-- Returns the smoke attachment's offset.
local function buildSmokehouse(template: any): any
	local shed = U.model(template, "Smokehouse")
	local F = TERRACE
	local x0, x1, z0, z1 = 30, 43, 144, 158
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
	span(shed, "Pipe", 39.4, 40.6, eave + 2, pipeTop, 151, 152.2, C.Iron)
	local cap = span(shed, "PipeCap", 39, 41, pipeTop, pipeTop + 0.6, 150.6, 152.6, C.Iron)
	local smoke, smokeOffset = attachAt(cap, "SmokeAttachment", at(40, pipeTop + 1, 151.6))
	Props.fx(smoke, "smoke", { rate = 3 })
	-- A fishing net drying on the east wall (towards the work yard) with an orange float.
	span(shed, "Net", x1 + 0.05, x1 + 0.3, F + 2.6, F + 7.6, 146, 156, C.NetRope, {
		CanCollide = false,
		CastShadow = false,
	})
	span(shed, "NetFloat", x1 + 0.3, x1 + 0.9, F + 6.8, F + 7.8, 150.5, 151.5, FL[6], DECOR)
	-- Lantern beside the doors.
	span(shed, "WallLamp", xc + 5.4, xc + 6.4, F + 6.3, F + 7.4, z0 - 1, z0 - 0.1, C.Glow, NEON_DECOR)
	return smokeOffset
end

-- Work yard in front of the smokehouse: a woodpile, a chopping stump, a sawhorse, a crate.
local function buildWorkYard(template: any)
	local yard = U.model(template, "WorkYard")
	local F = TERRACE
	span(yard, "Yard", 47, 61.5, F - 0.2, F + 0.3, 136, 154, C.Gravel, FLAT)
	span(yard, "Logs", 57.4, 61.4, F + 0.2, F + 3, 140, 150, C.Bark, { CastShadow = true })
	span(yard, "LogEnds", 57.25, 61.55, F + 0.3, F + 2.8, 140.2, 149.8, C.CutWood, DECOR)
	span(yard, "LogsTop", 57.8, 61, F + 3, F + 4.5, 141, 149, C.Bark)
	Props.stump(yard, facing(52.5, F + 0.3, 143, 30), { seed = 5, axe = true })
	-- sawhorse with a log on it
	span(yard, "SawhorseLegs", 50, 50.8, F + 0.3, F + 2.4, 147.2, 151.8, C.WoodDark)
	span(yard, "SawhorseLegs", 54.2, 55, F + 0.3, F + 2.4, 147.2, 151.8, C.WoodDark)
	span(yard, "SawLog", 49, 56, F + 2.4, F + 3.6, 148.9, 150.1, C.Bark)
	Props.crate(yard, facing(48.8, F + 0.3, 139, 10), { seed = 1, size = 3 })
end

-- Seating patio by the tower: flagstones edged by low stone planters, a trestle table with two
-- benches under a parasol in the base colour, a potted plant, a lantern post.
local function buildPatio(template: any)
	local patio = U.model(template, "Patio")
	local F = TERRACE
	local top = F + 0.3
	span(patio, "Paving", -53, -37, F - 0.2, top, 130.5, 143, C.Flag, FLAT)
	span(patio, "Planter", -55.4, -53, F - 0.2, F + 1.4, 130.5, 145.4, C.Stone)
	span(patio, "PlanterLeaves", -55.1, -53.3, F + 1.4, F + 2.3, 130.8, 145.1, C.Leaf1, DECOR)
	span(patio, "Planter", -53, -38, F - 0.2, F + 1.4, 143, 145.4, C.Stone)
	span(patio, "PlanterLeaves", -52.8, -38.3, F + 1.4, F + 2.3, 143.3, 145.1, C.Leaf1, DECOR)
	for i, z in { 133.5, 139.5 } do
		span(
			patio,
			"PlanterBloom",
			-54.8,
			-53.6,
			F + 2.1,
			F + 2.9,
			z - 0.6,
			z + 0.6,
			FL[if i == 1 then 1 else 2],
			DECOR
		)
	end
	local cx, cz = -45, 136.5
	span(patio, "TableTop", cx - 3.6, cx + 3.6, top + 2.4, top + 3, cz - 1.7, cz + 1.7, C.WoodLight)
	for _, sx in { -1, 1 } do
		local x = cx + sx * 2.6
		span(patio, "Trestle", x - 0.4, x + 0.4, top, top + 2.4, cz - 1.3, cz + 1.3, C.WoodDark)
		local z = cz + sx * 3
		span(patio, "BenchSeat", cx - 3.4, cx + 3.4, top + 1.2, top + 1.7, z - 0.7, z + 0.7, C.WoodLight)
		span(patio, "BenchLegs", cx - 2.8, cx + 2.8, top, top + 1.2, z - 0.4, z + 0.4, C.WoodDark)
	end
	cylY(patio, "ParasolPole", 0.4, 7.4, at(cx, top + 3.7, cz), C.Cream, DECOR)
	span(patio, "Parasol", cx - 3.8, cx + 3.8, top + 6.2, top + 6.9, cz - 3.8, cz + 3.8, 0, { CanCollide = false })
	span(patio, "ParasolTop", cx - 1.6, cx + 1.6, top + 6.9, top + 7.5, cz - 1.6, cz + 1.6, 0.6, DECOR)
	lanternPost(patio, -38.4, 141.6, top, 6, true)
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

-- The fry pond: an L of water inside cream kerbs and chunky rim stones, lilies, reeds, the fry, a
-- little plank jetty with a bench at its end, the sign.
local function buildFryPond(template: any)
	local pond = U.model(template, "FryPond")
	local rim = 1.2
	-- water: the long arm (x 46.2..61.8, lz 67.2..98.8) and the short arm round the corner
	local A = { 45 + rim, 63 - rim, 66 + rim, 100 - rim }
	local B = { 52.2, 63 - rim, 100 - rim, 106 - rim }
	for _, r in { A, B } do
		span(pond, "PondBed", r[1], r[2], -0.3, 0.4, r[3], r[4], C.PondBed, FLAT)
		span(pond, "Water", r[1], r[2], 0.45, 0.8, r[3], r[4], C.PondWater, {
			Transparency = 0.3,
			CanCollide = false,
			CastShadow = false,
		})
	end
	-- cream kerbs on the front, the inner corner and the back; chunky stones along the long sides
	span(pond, "Kerb", 45, 63, -0.2, 1, 66, 66 + rim, C.Limestone)
	span(pond, "Kerb", 45, 52.2, -0.2, 1, 100 - rim, 100, C.Limestone)
	span(pond, "Kerb", 51, 52.2, -0.2, 1, 100, 106, C.Limestone)
	span(pond, "Kerb", 52.2, 63, -0.2, 1, 106 - rim, 106, C.Limestone)
	span(pond, "RimStone", 44.6, 46.2, -0.2, 1.6, 66 + rim, 81.4, C.Stone, { CastShadow = true })
	span(pond, "RimStone", 44.8, 46.2, -0.2, 1.1, 85.6, 100 - rim, C.StoneLight)
	span(pond, "RimStone", 61.8, 63.4, -0.2, 1.3, 66 + rim, 86, C.StoneLight)
	span(pond, "RimStone", 61.8, 63.2, -0.2, 1.8, 86, 106 - rim, C.Stone, { CastShadow = true })
	Props.lilyPad(pond, at(50, 0.8, 72.5), { seed = 3, flower = true })
	Props.lilyPad(pond, at(57, 0.8, 101.5), { seed = 5, flower = true })
	reeds(pond, 47.6, 0.4, 96.4)
	reeds(pond, 60.2, 0.4, 69.2)
	for _, f in { { 55, 74, 0 }, { 56.6, 75.4, 1 } } do
		local fx, fz = f[1], f[2]
		if f[3] == 0 then
			span(pond, "Fry", fx - 0.6, fx + 0.6, 0.5, 0.75, fz - 0.25, fz + 0.25, C.Fry, DECOR)
		else
			span(pond, "Fry", fx - 0.25, fx + 0.25, 0.5, 0.75, fz - 0.6, fz + 0.6, C.Fry, DECOR)
		end
	end
	-- little plank jetty from the west side, a bench at its land end looking over the water
	span(pond, "Jetty", 44.6, 53, 0.9, 1.4, 81.6, 85.4, C.Plank)
	for _, z in { 81.9, 85.1 } do
		span(pond, "JettyPost", 52.2, 53, 0.4, 2.6, z - 0.4, z + 0.4, C.WoodDark)
	end
	bench(pond, facing(43.4, LAWN, 89.2, -90), LAWN, 4.4)
	-- the sign by the front kerb
	span(pond, "SignPost", 47.7, 48.3, 0, 3.4, 66 - 2, 66 - 1.2, C.WoodDark)
	local board = span(pond, "SignBoard", 45, 51, 3.2, 5.4, 66 - 2.2, 66 - 1.4, C.WoodLight)
	plainText(board, Enum.NormalId.Front, "МАЛЬКИ", C.Ink, false)
end

-- The net yard: a gravel yard with a drying frame (two opaque nets with a float line), the fish
-- drying rack, crab traps, the well, and a boat under repair (an upturned rowing boat on trestles
-- beside a stack of lobster pots, a canvas lean-to over the rack).
local function buildNetYard(template: any)
	local yard = U.model(template, "NetYard")
	span(yard, "Yard", -63, -45, -0.2, 0.45, 62, 101, C.Gravel, FLAT)
	-- net-drying frame: three posts and a pole, two nets with a float line along their foot
	local nx = -54
	for _, z in { 66, 77, 88 } do
		span(yard, "NetPost", nx - 0.45, nx + 0.45, 0, 9.2, z - 0.45, z + 0.45, C.WoodDark, { CastShadow = true })
	end
	span(yard, "NetPole", nx - 0.3, nx + 0.3, 8.4, 9, 65.4, 88.6, C.Wood)
	-- the nets hang over the pole in bunched folds of two greens, floats tied along their foot
	for i, f in
		{ { 66.6, 71.6, 3.4, 0.35 }, { 71.8, 76.6, 2.6, 0.55 }, { 77.4, 82.4, 3.8, 0.4 }, { 82.6, 87.4, 2.9, 0.6 } }
	do
		local c = if i % 2 == 1 then C.NetRope else C.NetRopeLight
		span(yard, "Net", nx - f[4], nx + f[4], f[3], 8.4, f[1], f[2], c, { CanCollide = false, CastShadow = false })
	end
	for i, z in { 72.4, 81.6 } do
		span(
			yard,
			"NetFloat",
			nx - 0.75,
			nx + 0.75,
			2.2,
			3.2,
			z - 0.55,
			z + 0.55,
			if i == 1 then FL[6] else FL[1],
			DECOR
		)
	end
	-- fish drying rack under a canvas lean-to: two posts, a bar, two fish hung by the tail
	local rz = 98
	for _, x in { -60, -48 } do
		span(yard, "RackPost", x - 0.45, x + 0.45, 0, 7.6, rz - 0.45, rz + 0.45, C.WoodDark)
	end
	span(yard, "RackBar", -60.3, -47.7, 6.8, 7.4, rz - 0.35, rz + 0.35, C.Wood)
	ramp(yard, "Canvas", -61, -47, 7.4, 8.6, rz - 3.2, rz + 0.6, "-z", P.Canvas, { CanCollide = false })
	for i, x in { -56, -52 } do
		local c = if i % 2 == 1 then C.FishSilver else C.FishSilverDark
		span(yard, "FishTail", x - 0.9, x + 0.9, 6, 6.8, rz - 0.2, rz + 0.2, c, DECOR)
		span(yard, "DriedFish", x - 0.7, x + 0.7, 3.2, 6, rz - 0.3, rz + 0.3, c, DECOR)
	end
	-- crab traps stacked by the nets
	span(yard, "CrabTrap", -49.6, -46.4, LAWN - 0.1, 2.4, 64.4, 67.6, C.WoodLight)
	-- stone well with a little timber roof
	local wx, wz = -49, 108
	span(yard, "WellRing", wx - 3, wx + 3, 0, 2.8, wz - 3, wz + 3, C.StoneLight, { CastShadow = true })
	span(yard, "WellWater", wx - 2.2, wx + 2.2, 2.75, 2.95, wz - 2.2, wz + 2.2, C.Water, DECOR)
	for _, sx in { -1, 1 } do
		span(yard, "WellPost", wx + sx * 2.4 - 0.4, wx + sx * 2.4 + 0.4, 2.8, 8.6, wz - 0.4, wz + 0.4, C.WoodDark)
	end
	span(yard, "Crossbar", wx - 3, wx + 3, 7, 7.6, wz - 0.3, wz + 0.3, C.Wood, DECOR)
	ramp(yard, "WellRoof", wx - 4, wx + 4, 8.6, 10.8, wz - 3.4, wz, "-z", C.RoofBrown, { CastShadow = true })
	ramp(yard, "WellRoof", wx - 4, wx + 4, 8.6, 10.8, wz, wz + 3.4, "+z", C.RoofBrown)
	span(yard, "Bucket", wx - 0.6, wx + 0.6, 4.6, 5.8, wz - 0.6, wz + 0.6, C.Wood, DECOR)
	-- boat repair: an upturned rowing boat (keel up, a painted gunwale band) on two trestles
	local bx, bz0, bz1 = -60, 106.5, 117.5
	for _, z in { bz0 + 2.2, bz1 - 2.2 } do
		span(yard, "Trestle", bx - 3, bx + 3, 0, 2.4, z - 0.4, z + 0.4, C.WoodDark)
	end
	span(yard, "Gunwale", bx - 2.5, bx + 2.5, 2.4, 3.1, bz0, bz1, -0.1)
	ramp(yard, "UpturnedHull", bx - 2.3, bx, 3.1, 5, bz0 + 0.3, bz1 - 0.4, "-x", C.WoodLight, { CastShadow = true })
	ramp(yard, "UpturnedHull", bx, bx + 2.3, 3.1, 5, bz0 + 0.3, bz1 - 0.4, "+x", C.WoodLight, { CastShadow = true })
	span(yard, "Keel", bx - 0.35, bx + 0.35, 4.8, 5.4, bz0 + 0.5, bz1 - 0.1, C.WoodDark)
	-- lobster pots stacked beside it
	span(yard, "LobsterPot", -55.6, -52.8, LAWN - 0.1, 2.3, 113, 115.6, C.Wood)
	span(yard, "LobsterPot", -55.6, -52.8, LAWN - 0.1, 2.3, 116.2, 118.8, C.WoodLight)
end

-- The empty front corner by the tackle shed: a sitting spot (a bench looking over the court, a
-- lantern, a clipped shrub) and stepping stones from the shed walk to the fry pond.
local function buildSitOut(template: any)
	local spot = U.model(template, "SitOut")
	bench(spot, facing(58, LAWN, 51, 90), LAWN, 5.4)
	lanternPost(spot, 60.6, 56.4, LAWN, 5)
	shrub(spot, 60.4, LAWN, 45.4, 4, 2.4, 1)
	for i, p in { { 45.8, 43 }, { 47, 50.4 }, { 47.6, 57.8 } } do
		local w = if i % 2 == 0 then 2.4 else 2.8
		span(spot, "SteppingStone", p[1] - w / 2, p[1] + w / 2, LAWN - 0.1, PATH, p[2] - 1.1, p[2] + 1.1, C.Flag, FLAT)
	end
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
	cylY(props, "Barrel", 2.8, 3.4, at(16.6, DECK + 1.7, pierEnd + 7.6), C.WoodDark)
	-- Lifebuoy hanging on the outside of the left rail: a red ring (a square block) with a white band.
	local bx, bz = -(PLAT_HALF + 1.35), pierEnd + 8
	span(props, "Lifebuoy", bx - 0.3, bx + 0.3, DECK + 0.9, DECK + 3.9, bz - 1.5, bz + 1.5, C.Red, DECOR)
	span(props, "LifebuoyBand", bx - 0.35, bx + 0.35, DECK + 2.1, DECK + 2.7, bz - 1.55, bz + 1.55, C.White, DECOR)
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
	buildSitOut(template)
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
