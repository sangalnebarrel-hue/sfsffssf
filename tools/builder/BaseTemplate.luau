--[[
	Builds ServerStorage.BaseTemplate — one player base: a fisherman's homestead on the green
	island with an aquarium court (art direction v4, tools/builder/DESIGN.md §1 and §2 "Base-local
	frame"). BaseService clones it into the 8 slots and paints every part with attribute
	Accent = true in the base colour (optional AccentShade -1..1: > 0 lighter, towards white;
	< 0 darker in HSV), and every part with WallTone = true in the base's own calm wall tone
	(BaseConfig.WallTones; optional WallShade, same rule), so the 8 houses differ.

	Colour: a lawn with darker mowing stripes, warm two-tone flagstone walks, cream limestone, plank
	decks, timber, warm stone and plaster in a dark / mid / light hierarchy (stone base course, warm
	limestone ground floor, plaster upper floor). The base colour (Accent) marks the base at a glance
	without flooding it: the roofs in a deep shade (house, tower, tackle shed -0.28, the six market
	bays of the display arcades -0.38; fascias and ridges darker), the doors; small full-colour
	accents — the leaping fish of the fountain, the flag, the stripe of the signal mast, a band on
	every display cabinet, the arcades' fish plaques, the gate sign's and the aquarium plaque's
	frames, the gate's lantern caps, the tackle shed's awning, the patio parasol, the mailbox, the
	boats' gunwales, the small SpawnPad. Any Accent part bigger than ~400 studs² uses a deep shade
	(<= -0.25; tested). The colour pops are jewel-tone flowers (Palette.Flowers via Props.flowerBed,
	window boxes), the aquarium's corals and fish, lanterns and the cyan light bars.

	Base-local frame (Root at the origin, y = 0 is GroundTop; the world builder provides flat
	grass under the plot):
	  -Z     towards the lagoon. lz 0..18 is the public promenade (the template places nothing
	         there except the start of the pier), lz 0..-PierLength (72) is the base's own pier.
	  +Z     inland: the plot x = -68..68, lz = 18..168.
	  +X/-X  sideways (+X is on the left of a player walking in through the gate).

	Layout (front to back, symmetric about the flagstone axis). The vista from the gate and the
	spawn runs over the fountain and the low aquarium to the house, which stands on a 4.5-stud
	terrace at its end.
	  lz 18        a timber gatehouse on the stone piers (posts with knee braces, the name board with
	               OwnerLabel/BaseLabel on both faces under a little roof, gold fish weathervane),
	               jewel flower beds; a stone-and-rail fence
	  lz 22..62    front yard: the spawn rose (a two-tone flagstone compass rose, a cream stone
	               rosette with a cobble rim round the small SpawnPad) framed by clipped shrubs and
	               two benches; the flag (the base's beacon) and the signal mast (Alarm, a mini
	               lighthouse in the base's stripes); the kitchen garden (-X: cabbages, ribbed
	               pumpkins, bean poles), the tackle shed (+X: a gable roof, a rack of painted rods, a
	               bait barrel, a wall lantern) and a rowing boat being repainted on trestles; on the
	               axis the court's centrepiece — a fountain whose leaping fish (in the base colour)
	               springs out of a stone basin; the guard dog and its kennel are hidden in the +X
	               front corner until the stage-4 upgrade
	  lz 54..121   the aquarium court: the big tank as a long, low pool of sea water on a bordered
	               flagstone terrace (cream sand and pebbles, a limestone castle, a reef with a
	               treasure chest, branching corals, kelp stacks, a shoal of fish round a big
	               clownfish, mullions, a timber rim and corner posts with lanterns, the «АКВАРИУМ»
	               plaque at its foot) between two covered fish markets of three gabled bays each
	               (a plank deck, timber posts and beam along a ~7-stud aisle, a gable end in the base
	               colour facing the court over each bay, a hanging lantern, a light ceiling; a solid
	               back wall of planks on a stone base course with pilasters, a band of windows and a
	               fish plaque outside) holding the 12 display aquariums (Tank.Slots.Slot_1..12: a
	               timber cabinet with a base-colour band, a brass rim, a clear water cube with sand
	               and a sprig of weed, a sea-blue backdrop against the wall and a glowing light bar
	               lighting the fish; odd slots in the -X arcade, slots 1-2 nearest the gate); low
	               hedges and potted topiaries between them; flagstone cross walks front and back
	  side strips  +X: the fry pond (an L of water in natural rim stones, lilies, reeds, a jetty
	               and a bench); -X: the net yard (two rope nets with floats drying on a frame over
	               a gravel bed, the well, a bench under the apple tree); fruit trees
	  lz 121..168  a 4.5-stud stone terrace (pilasters, stairs with lanterns, plank ramps): the
	               house — the base's main building (built at 1x, then scaled 1.15x about its back
	               wall), a T plan (warm limestone ground floor, half-timbered plaster upper floor in
	               the wall tone, two dormers, a cross-gabled front wing with a porch, a bench, a
	               balcony and a door in the base colour, window boxes, windows on every side, a back
	               door under a canopy) with a lookout tower (a clock face, a belvedere with head room
	               reached by a ladder, telescope, stepped Accent roof, pennant and fish weathervane);
	               the smokehouse (stone chimney, a net hung in folds, a lantern) and the work yard
	               with a woodpile and a fish-drying rack (+X), the seating patio (-X); a tall hedge
	               in three runs with two trellis arches at the back
	  lz 0..-72    plank pier with rails and lanterns, a moored boat that bobs, the end platform
	               with the FishingSpot, a shelter over a bench and the rod rack, crates, lifebuoy;
	               the pier micro-kit (PierKit: front-post lanterns framing the cast, tackle box,
	               stool, battens, rope coils, traps, net, drying fish, pennants, windsock, wind
	               chime, algae collars, potted plants) and one of four scenes per base
	               (PierKit.Scenes, attributes Variant / VariantOf: BaseService keeps only the base's
	               own); the yard micro-kit (YardKit) and roof tile courses (v3 detail)
	Moving details are marked for the client (Sway / SwayAxis / SwayPeriod, DESIGN.md §3): the flag's
	cloth, the weathervanes, the tower pennant and the pier kit's pennants, net, fish, buoys, chime
	and windsock; the boat bobs (Bob).
	Particles (no parts): chimney and smokehouse smoke, the fountain's spray, tank bubbles and the
	chest's glint, the fishing spot's glints, the weathervanes' sparkle (Props.fx).

	The guard dog (Model "Dog", stage 4 upgrade) is NOT on display: the dog and its kennel
	(Dog.DogHouse) have every part invisible (Transparency 1, CanCollide/CanQuery/CastShadow
	false) and the model attribute Unlocked = false. All parts are opaque blocks: to show them
	(dog bought) set every BasePart's Transparency to 0 and Unlocked = true.

	Names the server code relies on (BaseService, DESIGN.md §2) — keep in sync:
	  Root, SpawnPad, FishingSpot, Tank.Glass.PromptAttachment, Alarm.Lamp, Dog (PrimaryPart),
	  Tank.Slots.Slot_N.{Pedestal.PromptAttachment, Pedestal.LabelGui.Label, Display.FishPoint}
	  (attribute SlotIndex), Flag.Pole.SignAttachment.OwnerSign.{OwnerLabel, BaseLabel},
	  Flag.Cloth (tests), Gate.Board.SignFront/SignBack.{OwnerLabel, BaseLabel}.

	Budget: <= BUDGET parts per base at runtime (its own variant scenes only), <= TEMPLATE_BUDGET with
	every variant (asserted below and in tests/stage1_bases.test.luau; DESIGN.md §3).
	Deterministic: variation comes from seeds, never math.random.
]]

local U = require("./Util")
local Props = require("./Props")
local P = require("./Palette")
local Movers = require("./Movers")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Color3 = U.Color3
local Enum = U.Enum
local UDim2 = U.UDim2

local M = Enum.Material
local rad = math.rad

-- Part budgets (DESIGN.md §3): one base at runtime (its own variants only), and the template with
-- the scenes of every variant.
local BUDGET = 1060
local TEMPLATE_BUDGET = 1090

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
	FlagDark = P.FlagstoneDark:Lerp(P.CobbleDark, 0.6), -- the darker flags: they must read
	Limestone = P.Limestone, -- cream stone: terraces, kerbs, steps
	Gravel = P.SandDark:Lerp(P.Cobble, 0.45),
	Stone = P.Stone,
	StoneMid = P.Limestone:Lerp(P.Stone, 0.12), -- the house's ground floor: warm limestone, a step under the plaster
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
	PumpkinLight = P.Autumn2:Lerp(P.Orange, 0.5), -- the ribs
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
	Cabinet = P.Wood, -- display stands: warm timber, the brass rim and the base-colour band pop on it
	-- aquarium: bright sea water, light sand, a limestone castle and a coral reef
	TankGlass = tune(P.Water:Lerp(P.Cyan, 0.4):Lerp(P.WaterLight, 0.35), 1, 1.04), -- sea water (calm: S < 0.6)
	TankWater = tune(P.Water:Lerp(P.Cyan, 0.4), 1.08, 1.12), -- bright sea water ~ (55, 165, 205)
	DisplayWater = tune(P.Glass:Lerp(P.Cyan, 0.3), 1.3, 1.02), -- ~ (130, 200, 224): a clear sea tint
	Backdrop = tune(P.Water:Lerp(P.Cyan, 0.5), 1.05, 1.14), -- ~ (60, 176, 206)
	AquaGlow = tune(P.WaterLight:Lerp(P.Cyan, 0.2), 1.2, 1.1), -- Neon light bars ~ (120, 220, 240)
	ReefLight = P.WaterLight,
	Sand = P.Sand:Lerp(P.Foam, 0.35), -- cream aquarium sand
	Pebble = P.RockLight,
	PebbleWarm = P.SandDark:Lerp(P.Stone, 0.5),
	PebbleDark = P.RockMid,
	Castle = P.Limestone,
	CastleRoof = P.Flowers[1]:Lerp(P.Flowers[3], 0.4),
	Rock = P.RockLight, -- the reef's footing
	RockLight = P.Foam:Lerp(P.RockLight, 0.4),
	Kelp1 = P.Seaweed,
	Kelp2 = P.Leaf2,
	Kelp3 = P.LeafLight,
	CoralPinkBase = P.Flowers[3]:Lerp(P.Flowers[4], 0.3),
	CoralPink = P.Flowers[3],
	CoralRedBase = P.Flowers[1]:Lerp(P.Flowers[3], 0.25),
	CoralRed = P.Flowers[1]:Lerp(P.White, 0.12),
	CoralViolet = P.Flowers[4],
	CoralWhite = P.Flowers[5],
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
	-- the hidden guard dog (shown in stage 4): a shiba in warm, calm tones
	Dog = P.Wood:Lerp(P.Orange, 0.55),
	DogCream = P.Cream,
}

-- Accent shades (BaseService paints these parts in the base colour).
local ROOF = -0.28 -- roof slopes: a deep, natural shade of the base colour
local ROOF_TRIM = -0.45 -- fascias, ridges
local SHUTTER = -0.12

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
local TERRACE_Z = 121 -- the house terrace's front face
local FOUNTAIN_Z = 50 -- the fountain on the axis between the spawn rose and the aquarium

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
local GLASS = { Material = M.Glass, Transparency = 0.15, Reflectance = 0.15, CastShadow = false }
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

--[[
	Moving details (DESIGN.md §3 "Ambient attributes"; the client animates them, the builder only
	marks them): `Sway` = amplitude in degrees about the pivot's local axis `SwayAxis` ("X" | "Y" |
	"Z"), one swing every `SwayPeriod` seconds. On a Model the pivot is its PrimaryPart's pivot; on
	a BasePart it is CFrame * PivotOffset and the parts parented under it swing with it. `pivot` is
	the hang point (template space).
]]
local function sway(inst: any, pivot: any, amplitude: number, axis: string, period: number): any
	inst:SetAttribute("Sway", amplitude)
	inst:SetAttribute("SwayAxis", axis)
	inst:SetAttribute("SwayPeriod", period)
	local primary = if inst:IsA("BasePart") then inst else inst.PrimaryPart
	if not primary then
		for _, d in inst:GetDescendants() do
			if d:IsA("BasePart") then
				primary = d
				break
			end
		end
		inst.PrimaryPart = primary
	end
	primary.PivotOffset = primary.CFrame:Inverse() * pivot
	return inst
end

--[[
	Per-base variants (DESIGN.md §2 "Per-base variants"): a model kept only on the bases whose index
	i gives (i - 1) % of + 1 == k; BaseService destroys it on the others right after cloning, so the
	8 bases are not identical copies (tools/preview/export_parts.luau mirrors the rule).
]]
local function variant(parent: any, name: string, k: number, of: number): any
	local m = U.model(parent, name)
	m:SetAttribute("Variant", k)
	m:SetAttribute("VariantOf", of)
	return m
end

-- True when `inst` (or a variant ancestor below `root`) is dropped on base `index`.
local function droppedOn(inst: any, root: any, index: number): boolean
	local x = inst
	while x and x ~= root do
		local k, of = x:GetAttribute("Variant"), x:GetAttribute("VariantOf")
		if typeof(k) == "number" and typeof(of) == "number" and (index - 1) % of + 1 ~= k then
			return true
		end
		x = x.Parent
	end
	return false
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

-- (MaxDistance, v3 fix F4: a sign whose letters are a few pixels tall from the next base is
-- still laid out and drawn — its own draw call — unless it has a MaxDistance; default 120 studs)
local function surfaceGui(part: any, name: string, face: any, pixelsPerStud: number, maxDistance: number?): any
	return U.new("SurfaceGui", {
		Name = name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = pixelsPerStud,
		LightInfluence = 0,
		MaxDistance = maxDistance or 120,
	}, part)
end

-- The owner's name in the LEGO-brick UI style («Кирпичики», tools/builder/gui/STYLE.md): Nunito
-- Heavy, white fading to cream, a thick round Ink outline (sticker letters that read on any base
-- colour and across the lagoon).
local SIGN_FONT = U.Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.Heavy)
local SIGN_INK = Color3.fromRGB(21, 23, 28) -- UIConfig.Ink
local SIGN_CREAM = Color3.fromRGB(255, 241, 201)
local function stickerText(label: any, outline: number)
	label.FontFace = SIGN_FONT
	label.TextColor3 = C.White
	label.TextStrokeTransparency = 1
	U.new("UIStroke", {
		Name = "Outline",
		Color = SIGN_INK,
		Thickness = outline,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
	U.new("UIGradient", {
		Name = "Cream",
		Rotation = 90,
		Color = U.roblox.ColorSequence.new(C.White, SIGN_CREAM),
	}, label)
end
-- The base's name in its colour (BaseService sets TextColor3) with an Ink outline.
local function baseNameText(label: any, outline: number)
	label.FontFace = SIGN_FONT
	label.TextStrokeTransparency = 1
	U.new("UIStroke", {
		Name = "Outline",
		Color = SIGN_INK,
		Thickness = outline,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, label)
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
-- Tile courses on a roof slope (v3 detail): `n` thin strips of a darker shade lying on the wedge's
-- slope, parallel to the eave (a big roof seen from a lookout is no longer one flat slab). n parts.
local function roofCourses(parent: any, wedge: any, n: number)
	local s = wedge.Size
	local normal = Vector3.new(0, s.Z, -s.Y).Unit -- the slope's outward normal (wedge space)
	local L = math.sqrt(s.Y * s.Y + s.Z * s.Z)
	for i = 1, n do
		local t = i / (n + 1)
		local p = Vector3.new(0, -s.Y / 2 + t * s.Y, -s.Z / 2 + t * s.Z) + normal * 0.09
		local cf = wedge.CFrame * CFrame.fromMatrix(p, Vector3.new(1, 0, 0), normal)
		make(parent, "RoofCourse", Vector3.new(s.X - 0.2, 0.16, math.min(0.7, L / (3 * n))), cf, ROOF - 0.12, DECOR)
	end
end

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
	gable: any,
	courses: number?
): number
	local top = y0 + h
	local function slope(wedge: any)
		if courses then
			roofCourses(parent, wedge, courses)
		end
	end
	if alongX then
		local zc = (z0 + z1) / 2
		local half = (z1 - z0) / 2
		local hg = h * half / (half + e)
		slope(ramp(parent, "Roof", x0 - g, x1 + g, y0, top, z0 - e, zc, "-z", ROOF, { CastShadow = true }))
		slope(ramp(parent, "Roof", x0 - g, x1 + g, y0, top, zc, z1 + e, "+z", ROOF, { CastShadow = true }))
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
		slope(ramp(parent, "Roof", x0 - e, xc, y0, top, z0 - g, z1 + g, "-x", ROOF, { CastShadow = true }))
		slope(ramp(parent, "Roof", xc, x1 + e, y0, top, z0 - g, z1 + g, "+x", ROOF, { CastShadow = true }))
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
	-- (whole studs: 135 x 149, its stud rows in phase with the stripes', v3 fix W4)
	span(floor, "Lawn", -hw + 0.5, hw - 0.5, -0.4, LAWN, front + 0.5, plot.back - 0.5, C.Lawn)
	-- Mowing stripes: darker 8-stud bands running inland (Grow a Garden style); the outer ones run
	-- down the side strips to the house terrace.
	for _, sx in { -1, 1 } do
		for _, st in { { 8.5, 16.5, 54 }, { 24.5, 32.5, 54 }, { 40.5, 48.5, TERRACE_Z }, { 56.5, 64.5, TERRACE_Z } } do
			local xa, xb = mirror(sx, st[1], st[2])
			span(floor, "Stripe", xa, xb, LAWN - 0.1, STRIPE, front + 1.5, st[3] - 0.5, C.LawnStripe, FLAT)
		end
	end

	-- The axis: gate -> spawn rose -> fountain plaza -> cross walk -> aquarium terrace (no flags
	-- where the rose covers the walk).
	local plazaZ0, plazaZ1 = FOUNTAIN_Z - 6.8, FOUNTAIN_Z + 6.5
	flagWalk(floor, "Walk", -5, 5, front + 0.2, plazaZ0, PATH, 6, function(u: number): boolean
		local z = front + 0.2 + u
		return z > SPAWN_Z - 10 and z < SPAWN_Z + 10
	end)
	-- the fountain plaza: a light square with a darker border (the basin stands in it)
	span(floor, "Plaza", -8.4, 8.4, PATH - 0.45, PATH, plazaZ0, plazaZ1, C.Flag, FLAT)
	-- Cross walks in front of and behind the aquarium terrace, joining the arcade decks.
	flagWalk(floor, "CrossWalk", -22.2, 22.2, plazaZ1, plazaZ1 + 4, PATH, 11)
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

	-- Flower beds just inside the gate: jewel blooms on stems over the leaves.
	for _, sx in { -1, 1 } do
		local pair = if sx < 0 then JEWELS[1] else JEWELS[2]
		flowerBed(floor, sx * 8.6, LAWN, front + 6.6, 6, 3.6, pair, { spacing = 1.35, max = 5 })
	end

	-- Clipped two-tone shrubs at the rose's corners, a bench either side looking at the rose, a
	-- clipped shrub in the -X front corner (the +X corner keeps the hidden kennel's spot).
	for _, sx in { -1, 1 } do
		shrub(floor, sx * 11.6, LAWN, SPAWN_Z - 8.4, 3.4, 1.9, -sx)
		shrub(floor, sx * 11.6, LAWN, SPAWN_Z + 8.6, 3.8, 2.3, sx)
		bench(floor, facing(sx * 22.5, 0, 41.6, 90 * sx), LAWN, 5.4)
	end
	shrub(floor, -33, LAWN, 23.6, 4.2, 2.2, -1)
end

-- The court's centrepiece on the axis: a stepped stone basin of bright water with a leaping fish in
-- the base colour springing out of a splash, a jet of water from its mouth (spray particles).
local function buildFountain(template: any)
	local fountain = U.model(template, "Fountain")
	local z = FOUNTAIN_Z
	local half = 5.2
	local wallTop, rimTop = 1.5, 2.3
	span(fountain, "Basin", -half, half, PATH - 0.2, wallTop, z - half, z + half, C.Stone, { CastShadow = true })
	-- the rim: a cream coping on all four sides
	local r = 0.9
	span(fountain, "Rim", -half - 0.2, half + 0.2, wallTop - 0.1, rimTop, z - half - 0.2, z - half + r, C.Limestone)
	span(fountain, "Rim", -half - 0.2, half + 0.2, wallTop - 0.1, rimTop, z + half - r, z + half + 0.2, C.Limestone)
	span(fountain, "Rim", -half - 0.2, -half + r, wallTop - 0.1, rimTop, z - half + r, z + half - r, C.Limestone)
	span(fountain, "Rim", half - r, half + 0.2, wallTop - 0.1, rimTop, z - half + r, z + half - r, C.Limestone)
	local water = span(
		fountain,
		"Water",
		-half + r,
		half - r,
		wallTop - 0.2,
		wallTop + 0.35,
		z - half + r,
		z + half - r,
		C.PondWater,
		{
			CanCollide = false,
			CastShadow = false,
		}
	)
	-- the column with a gold cap, foam round its foot and a splash on its top
	local cx = 1.4
	span(fountain, "Column", cx - 1.1, cx + 1.1, wallTop, 3.4, z - 1.1, z + 1.1, C.Limestone, { CastShadow = true })
	span(fountain, "ColumnCap", cx - 1.5, cx + 1.5, 3.4, 3.9, z - 1.5, z + 1.5, C.Gold)
	span(fountain, "Foam", cx - 2, cx + 2, wallTop + 0.3, wallTop + 0.65, z - 2, z + 2, C.White, DECOR)
	span(fountain, "Splash", cx - 1, cx + 1, 3.9, 5, z - 1, z + 1, C.Foam, {
		Transparency = 0.25,
		CanCollide = false,
		CastShadow = false,
	})

	-- The leaping fish (the base colour), its tail in the splash, its head up towards -X: a body
	-- with a pale belly, a tapering head with big eyes, a forked tail, fins.
	local k = 0.85
	local f = at(-1.6, 7.5, z) * CFrame.Angles(0, 0, rad(-38))
	local function fish(name: string, x: number, y: number, sx: number, sy: number, sz: number, paint: any)
		return box(fountain, name, f, x * k, y * k, 0, sx * k, sy * k, sz * k, paint, { CanCollide = false })
	end
	fish("FishBody", 0, 0, 5.6, 3.6, 2.4, 0)
	fish("FishBelly", 0.2, -1.4, 4.8, 1.2, 2.55, 0.5)
	fish("FishHead", -3.5, -0.1, 1.6, 2.8, 2.1, 0.12)
	fish("FishTail", 3.4, 0, 1.6, 2, 1.4, -0.12)
	fish("FishTailUp", 4.6, 1.5, 1.4, 2.8, 0.8, -0.32)
	fish("FishTailDown", 4.6, -1.5, 1.4, 2.8, 0.8, -0.32)
	fish("FishDorsal", -0.3, 2.3, 3.2, 1.2, 0.6, -0.32)
	fish("FishFins", -1, -0.9, 1.4, 0.8, 3.6, -0.32)
	fish("FishEye", -3.4, 0.6, 1.1, 1.1, 2.35, C.White)
	fish("FishPupil", -3.6, 0.65, 0.6, 0.7, 2.5, C.Ink)
	-- a jet of water out of its mouth, sparkling spray at its end
	local jet = box(fountain, "Jet", f, -5.9 * k, -0.2 * k, 0, 2.6, 0.6, 0.6, C.ReefLight, {
		Transparency = 0.35,
		CanCollide = false,
		CastShadow = false,
	})
	Props.fx(jet, "spray", { rate = 6 })
	Props.fx(water, "spray", { rate = 4, name = "BasinSpray" })
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
		blk("StoneBase", a0, a1, base, y0 + (if alongX then 1.5 else 1.42), 0.8, C.Stone)
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
		run(true, sx * 16, sx * (line + 0.7), sx * line, fz, posts, 0, 0)
	end
	-- Sides: from the front fence to the terrace (posts every ~25 studs); a hedge along the
	-- terrace's sides.
	for _, sx in { -1, 1 } do
		local z0 = fz + 0.55
		local posts = {}
		for i = 1, 4 do
			table.insert(posts, z0 + (TERRACE_Z - z0) * i / 4)
		end
		run(false, z0 - 0.55, TERRACE_Z, TERRACE_Z, sx * line, posts, 0, 0)
		local ha, hb = mirror(sx, hw - 3.4, hw - 0.6)
		span(fence, "SideHedge", ha, hb, -0.2, TERRACE + 5.4, TERRACE_Z + 0.3, hedgeZ, C.Hedge, { CastShadow = true })
	end
	-- Tall clipped hedge along the back (behind the house), lighter on top, in three runs with two
	-- timber trellis arches between them, blossom over their beams.
	local archX, archHalf = 40, 2.6
	local runs =
		{ { -hw + 0.6, -archX - archHalf }, { -archX + archHalf, archX - archHalf }, { archX + archHalf, hw - 0.6 } }
	for _, r in runs do
		span(fence, "Hedge", r[1], r[2], TERRACE - 0.2, TERRACE + 5.4, hedgeZ, back - 0.2, C.Hedge, {
			CastShadow = true,
		})
		span(
			fence,
			"HedgeTop",
			r[1] + 0.4,
			r[2] - 0.4,
			TERRACE + 5.4,
			TERRACE + 6.2,
			hedgeZ + 0.4,
			back - 0.6,
			C.HedgeTop,
			{
				CanCollide = false,
			}
		)
	end
	local zc = (hedgeZ + back) / 2
	for i, sx in { -1, 1 } do
		local x = sx * archX
		for _, dx in { -archHalf + 0.5, archHalf - 0.5 } do
			span(
				fence,
				"ArchPost",
				x + dx - 0.5,
				x + dx + 0.5,
				TERRACE - 0.2,
				TERRACE + 7.6,
				zc - 0.5,
				zc + 0.5,
				C.WoodLight
			)
		end
		span(
			fence,
			"ArchBeam",
			x - archHalf - 0.6,
			x + archHalf + 0.6,
			TERRACE + 7.6,
			TERRACE + 8.4,
			zc - 1.2,
			zc + 1.2,
			C.Wood
		)
		local bloom = if i == 1 then P.Blossom1 else FL[5]:Lerp(FL[3], 0.35)
		span(
			fence,
			"ArchBlooms",
			x - archHalf - 0.2,
			x + archHalf + 0.2,
			TERRACE + 8.3,
			TERRACE + 9.5,
			zc - 1.6,
			zc + 1.4,
			bloom,
			DECOR
		)
	end
end

------------------------------------------------------------------------------------------
-- Entrance gate: stone piers, a timber frame with the owner's name board under a little roof
------------------------------------------------------------------------------------------

local function signFace(board: any, face: any)
	local gui = surfaceGui(board, "Sign" .. face.Name, face, 32)
	-- (v3 fix WOW-5: the brick UI's sticker letters, like the owner sign over the flag)
	stickerText(textBand(gui, "OwnerLabel", "Свободно", C.White, 0.08, 0.54, false), 4)
	baseNameText(textBand(gui, "BaseLabel", "База", C.White, 0.64, 0.3, false), 3)
end

local function buildGate(template: any, plot: any)
	local gate = U.model(template, "Gate")
	local z0 = plot.front
	local zc = z0 + 2.2
	local beamBottom = 16.2
	for _, sx in { -1, 1 } do
		local lo, hi = mirror(sx, 11.4, 16)
		span(gate, "Pier", lo, hi, 0, 8, z0, z0 + 4.4, C.Stone, { CastShadow = true })
		span(gate, "PierCap", lo - 0.4, hi + 0.4, 8, 9, z0 - 0.4, z0 + 4.8, C.Limestone)
		-- the gatehouse post stands on the pier's inner half, the lantern on its outer half
		local px = sx * 12.5
		span(gate, "Post", px - 0.9, px + 0.9, 9, beamBottom, zc - 0.9, zc + 0.9, C.WoodDark, { CastShadow = true })
		local lx = sx * 14.9
		local lamp = span(gate, "Lantern", lx - 0.8, lx + 0.8, 9, 10.7, zc - 0.8, zc + 0.8, C.Glow, NEON)
		span(gate, "LanternCap", lx - 1.1, lx + 1.1, 10.7, 11.3, zc - 1.1, zc + 1.1, -0.3)
		if sx > 0 then
			U.new("PointLight", { Range = 16, Brightness = 1.1, Color = C.LightColor, Shadows = false }, lamp)
		end
		-- a knee brace from the post up under the beam: an upside-down wedge, its full faces against
		-- the post and under the beam
		local braceCf = at(sx * 10.4, beamBottom - 1.2, zc)
			* CFrame.Angles(0, rad(90 * sx), 0)
			* CFrame.Angles(0, 0, rad(180))
		make(gate, "Brace", Vector3.new(1, 2.4, 2.4), braceCf, C.WoodDark, { wedge = true })
	end
	span(gate, "Beam", -14, 14, beamBottom, beamBottom + 1.4, zc - 1.1, zc + 1.1, C.WoodDark, { CastShadow = true })
	-- Name board (both faces) in an Accent frame, under a little Accent gable roof.
	local bTop = beamBottom + 1.4
	span(gate, "BoardFrame", -7.8, 7.8, bTop - 0.4, bTop + 6.4, zc - 0.4, zc + 0.4, 0)
	local board = span(gate, "Board", -7.1, 7.1, bTop, bTop + 6, zc - 0.6, zc + 0.6, C.Cream)
	signFace(board, Enum.NormalId.Front) -- faces the promenade
	signFace(board, Enum.NormalId.Back) -- faces the yard
	local rTop = bTop + 6.4
	ramp(gate, "Roof", -10, 10, rTop, rTop + 2.8, zc - 3.2, zc, "-z", ROOF, { CastShadow = true })
	ramp(gate, "Roof", -10, 10, rTop, rTop + 2.8, zc, zc + 3.2, "+z", ROOF)
	span(gate, "Ridge", -10.2, 10.2, rTop + 2.3, rTop + 3.3, zc - 0.6, zc + 0.6, ROOF_TRIM)
	-- Gold fish weathervane on the ridge (the game's mascot), glinting now and then.
	local vy = rTop + 3.3
	span(gate, "VaneRod", -0.2, 0.2, vy, vy + 1.1, zc - 0.2, zc + 0.2, C.Iron, DECOR)
	local fish = span(gate, "VaneFish", -2, 1.6, vy + 1.1, vy + 2.8, zc - 0.25, zc + 0.25, C.Gold, DECOR)
	span(gate, "VaneTail", 1.6, 2.8, vy + 0.8, vy + 3.1, zc - 0.2, zc + 0.2, C.Gold, DECOR)
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

	-- Owner sign above the mast (BaseService writes the owner name / base name), a LEGO brick in
	-- the «Кирпичики» UI style (v3 fix WOW-5): a plate in the base colour (Accent GUI objects:
	-- BaseService paints their BackgroundColor3) with a thick Ink outline, a darker lip and three
	-- studs on top; the owner's name in white sticker letters, the base's name in its colour on a
	-- cream tile. Studs + pixels (10 x 3.2 studs + 150 x 52 px): readable across the lagoon
	-- (MaxDistance 500), the labels stay direct children of OwnerSign (BaseService finds them).
	-- The pole is a cylinder (local X = up), so the offset is along local X.
	local signOffset = Vector3.new(poleH / 2 + 6.5, 0, 0)
	local attachment = U.new("Attachment", { Name = "SignAttachment", CFrame = CFrame.new(signOffset) }, pole)
	local sign = U.new("BillboardGui", {
		Name = "OwnerSign",
		Size = UDim2.new(10, 150, 3.2, 52), -- studs + px
		LightInfluence = 0,
		MaxDistance = 500,
		AlwaysOnTop = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, attachment)
	local function accent(frame: any, shade: number?): any
		frame:SetAttribute("Accent", true)
		if shade then
			frame:SetAttribute("AccentShade", shade)
		end
		return frame
	end
	local function corner(frame: any, scale: number)
		U.new("UICorner", { CornerRadius = U.UDim.new(scale, 0) }, frame)
	end
	local function ink(frame: any, thickness: number)
		U.new("UIStroke", {
			Name = "Outline",
			Color = SIGN_INK,
			Thickness = thickness,
			ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			LineJoinMode = Enum.LineJoinMode.Round,
		}, frame)
	end
	-- studs on top (behind the plate: only their round tops show)
	for i, x in { 0.2, 0.5, 0.8 } do
		local stud = accent(
			U.new("Frame", {
				Name = `Stud{i}`,
				AnchorPoint = U.Vector2.new(0.5, 0),
				Position = UDim2.fromScale(x, 0),
				Size = UDim2.fromScale(0.13, 0.3),
				BackgroundColor3 = C.Cream,
				BorderSizePixel = 0,
				ZIndex = 1,
			}, sign),
			0.12
		)
		corner(stud, 0.35)
		ink(stud, 2.5)
	end
	local plate = accent(U.new("Frame", {
		Name = "Plate",
		Position = UDim2.fromScale(0, 0.14),
		Size = UDim2.fromScale(1, 0.86),
		BackgroundColor3 = C.Cream,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, sign))
	corner(plate, 0.22)
	ink(plate, 3)
	local lip = accent(
		U.new("Frame", {
			Name = "Lip",
			AnchorPoint = U.Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0.2),
			BackgroundColor3 = C.Cream,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, plate),
		-0.35
	)
	corner(lip, 0.5)
	local tile = U.new("Frame", {
		Name = "Tile",
		Position = UDim2.fromScale(0.08, 0.56),
		Size = UDim2.fromScale(0.84, 0.31),
		BackgroundColor3 = SIGN_CREAM:Lerp(C.White, 0.5),
		BorderSizePixel = 0,
		ZIndex = 4,
	}, sign)
	corner(tile, 0.5)
	ink(tile, 2)
	local owner = U.new("TextLabel", {
		Name = "OwnerLabel",
		Position = UDim2.fromScale(0.06, 0.17),
		Size = UDim2.fromScale(0.88, 0.38),
		BackgroundTransparency = 1,
		Text = "Свободно",
		TextScaled = true,
		ZIndex = 5,
	}, sign)
	stickerText(owner, 3.5)
	local baseName = U.new("TextLabel", {
		Name = "BaseLabel",
		Position = UDim2.fromScale(0.11, 0.575),
		Size = UDim2.fromScale(0.78, 0.27),
		BackgroundTransparency = 1,
		Text = "База",
		TextScaled = true,
		TextColor3 = C.White,
		ZIndex = 5,
	}, sign)
	baseNameText(baseName, 2)
	return signOffset
end

-- Signal mast, a mini lighthouse: stone foot, a white mast with two stripes in the base colour, a
-- gallery carrying the siren lamp (Alarm.Lamp: glass, dark until stage 4 lights it) with an iron
-- cage band under a stepped dome in the base colour, a bell.
local function buildAlarm(template: any)
	local alarm = U.model(template, "Alarm")
	local ax, az = 20, 31
	span(alarm, "Foot", ax - 2, ax + 2, 0, 1.2, az - 2, az + 2, C.Stone)
	span(alarm, "Post", ax - 0.7, ax + 0.7, 1.2, 13, az - 0.7, az + 0.7, C.Cream, { CastShadow = true })
	-- the mast in the base's stripes, a mini lighthouse
	span(alarm, "Stripe", ax - 0.8, ax + 0.8, 7.4, 9.6, az - 0.8, az + 0.8, 0)
	span(alarm, "Platform", ax - 2, ax + 2, 13, 13.6, az - 2, az + 2, C.Wood)
	-- the siren: a glass lamp (dark until stage 4 lights it) with an iron cage band, under a
	-- stepped dome in the base colour
	span(alarm, "Lamp", ax - 1.3, ax + 1.3, 13.6, 16.2, az - 1.3, az + 1.3, C.LampOff, {
		Material = M.Glass,
		Transparency = 0.2,
		Reflectance = 0.1,
		CastShadow = false,
	})
	span(alarm, "Cage", ax - 1.45, ax + 1.45, 14.7, 15.1, az - 1.45, az + 1.45, C.Iron, DECOR)
	span(alarm, "Cap", ax - 1.9, ax + 1.9, 16.2, 16.9, az - 1.9, az + 1.9, -0.2)
	span(alarm, "Dome", ax - 1.1, ax + 1.1, 16.9, 17.6, az - 1.1, az + 1.1, 0.25, DECOR)
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

	-- The court's centre: a flagstone terrace with a border of darker flags, a warm stone plinth
	-- with a cream ledge.
	local tx, tz0, tz1 = 16, 62, 114
	span(tank, "Terrace", -tx, tx, -0.2, TANK_TERRACE, tz0, tz1, C.Flag, { CastShadow = true })
	local bw, bTop = 1.4, TANK_TERRACE + 0.15
	span(
		tank,
		"TerraceBorder",
		-tx + 0.3,
		tx - 0.3,
		TANK_TERRACE - 0.3,
		bTop,
		tz0 + 0.3,
		tz0 + 0.3 + bw,
		C.FlagDark,
		FLAT
	)
	span(
		tank,
		"TerraceBorder",
		-tx + 0.3,
		tx - 0.3,
		TANK_TERRACE - 0.3,
		bTop,
		tz1 - 0.3 - bw,
		tz1 - 0.3,
		C.FlagDark,
		FLAT
	)
	for _, sx in { -1, 1 } do
		local xa, xb = mirror(sx, tx - 0.3 - bw, tx - 0.3)
		span(tank, "TerraceBorder", xa, xb, TANK_TERRACE - 0.3, bTop, tz0 + 0.3 + bw, tz1 - 0.3 - bw, C.FlagDark, FLAT)
	end
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

	-- The glass (one part: the whole volume; fish swim inside it later) with a sea-water tint, and a
	-- low sea-blue back wall at the far end behind the reef rocks (the water reads from both ends).
	local glass = span(tank, "Glass", -hx, hx, TANK_BASE, TANK_TOP, TANK_Z0, TANK_Z1, C.TankGlass, {
		Material = M.Glass,
		Transparency = 0.72,
		CastShadow = false,
	})
	tank.PrimaryPart = glass
	local w = 0.3
	span(tank, "BackWall", -hx + w, hx - w, TANK_BASE, TANK_TOP - 1.4, TANK_Z1 - w - 0.4, TANK_Z1 - w, C.Backdrop, {
		Transparency = 0.25,
		CanCollide = false,
		CastShadow = false,
	})
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
		-- two mullions divide each long side into three panes
		for _, z in { TANK_Z0 + (TANK_Z1 - TANK_Z0) / 3, TANK_Z0 + (TANK_Z1 - TANK_Z0) * 2 / 3 } do
			span(
				tank,
				"Mullion",
				sx * hx - 0.35,
				sx * hx + 0.35,
				TANK_BASE,
				TANK_TOP,
				z - 0.3,
				z + 0.3,
				C.WoodDark,
				DECOR
			)
		end
		local lx = sx * (hx - 0.9)
		span(
			tank,
			"LightBar",
			lx - 0.25,
			lx + 0.25,
			TANK_TOP - 0.6,
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

	-- Inside: cream sand with pebbles, a reef rock in the middle with a treasure chest beside it,
	-- branching corals in the front corners, kelp stacks reaching the surface, a limestone castle at
	-- the back against a skyline of reef rocks, a shoal of bright fish round one big clownfish,
	-- columns of rising bubbles (particles). A PointLight on the reef lights it all.
	local s = TANK_BASE + 0.7 -- sand top
	local sand = span(tank, "Sand", -hx + 0.2, hx - 0.2, TANK_BASE, s, TANK_Z0 + 0.2, TANK_Z1 - 0.2, C.Sand, DECOR)
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
	-- pebbles on the sand
	for i, p in { { -5.2, 73.2, 1.3 }, { -2.2, 95.6, 1.2 } } do
		local c = if i % 3 == 1 then C.Pebble elseif i % 3 == 2 then C.PebbleWarm else C.PebbleDark
		piece("Pebble", p[1] - p[3] / 2, p[1] + p[3] / 2, -0.15, p[3] * 0.5, p[2] - p[3] * 0.4, p[2] + p[3] * 0.4, c)
	end
	-- castle at the back: a keep, two towers with terracotta caps
	piece("Castle", -3.2, 3.2, -0.2, 2.6, 97, 102, C.Castle)
	for _, sx in { -1, 1 } do
		local xa, xb = mirror(sx, 2.8, 5.4)
		piece("CastleTower", xa, xb, -0.2, 3.5, 96.6, 102.4, C.Castle)
		piece("TowerRoof", xa - 0.4, xb + 0.4, 3.5, 4.3, 96.2, 102.8, C.CastleRoof)
	end
	-- reef rock in the middle, a treasure chest at its front corner
	local reef = piece("Reef", -6, 4, -0.2, 1.4, 82, 92, C.Rock)
	piece("Reef", -4, 2, 1.4, 2.4, 83.5, 90, C.RockLight)
	U.new("PointLight", { Range = 16, Brightness = 2, Color = C.ReefLight, Shadows = false }, reef)
	local cx, cz = 6.6, 80.6
	piece("Chest", cx - 1.3, cx + 1.3, -0.1, 1.4, cz - 0.9, cz + 0.9, C.WoodDark)
	piece("ChestLid", cx - 1.35, cx + 1.35, 1.3, 2.9, cz + 0.6, cz + 1.05, C.Wood)
	piece("ChestBand", cx - 0.3, cx + 0.3, -0.05, 1.45, cz - 0.95, cz + 0.95, C.Gold)
	local gold = piece("ChestGold", cx - 1.05, cx + 1.05, 1.3, 1.85, cz - 0.7, cz + 0.6, C.GoldLight)
	Props.fx(gold, "sparkle", { rate = 1.5, size = 0.8 })
	-- corals (colours that stay bright through the water): branching pink and red in the front
	-- corners (a stem with arms of different heights), a violet fan and a white coral on the reef,
	-- a pink brain coral by the castle
	for _, c in
		{
			{ -8.6, 75.2, C.CoralPinkBase, C.CoralPink, 1 },
			{ 8.8, 75.6, C.CoralRedBase, C.CoralRed, -1 },
		}
	do
		local x, z, d = c[1], c[2], c[5]
		piece("Coral", x - 0.9, x + 0.9, -0.2, 2.8, z - 0.9, z + 0.9, c[3])
		piece("CoralArm", x + d * 0.6, x + d * 2.4, 1.8, 5, z - 0.7, z + 0.7, c[4])
		piece("CoralArm", x - d * 2.3, x - d * 0.5, 1.2, 3.8, z - 0.6, z + 0.7, c[4])
	end
	piece("FanCoral", -2.6, -0.4, 2.4, 4.4, 85.4, 86.6, C.CoralViolet)
	piece("Coral", 0.6, 2.6, 2.4, 3.6, 87.6, 89.6, C.CoralWhite)
	piece("BrainCoral", 7, 10.6, -0.2, 1.8, 98, 102.6, C.CoralPink)
	-- kelp: stacks of offset blocks in two greens reaching up to the water line
	for _, k in { { -9, 96, 1 }, { 9.4, 87.2, -1 } } do
		local x, z, d = k[1], k[2], k[3]
		piece("Kelp", x - 0.8, x + 0.8, -0.2, 2.2, z - 0.7, z + 0.7, C.Kelp1)
		piece("Kelp", x + d * 0.3 - 0.7, x + d * 0.3 + 0.7, 2.1, 4, z - 0.6, z + 0.6, C.Kelp2)
		piece("Kelp", x - d * 0.2 - 0.6, x - d * 0.2 + 0.6, 3.9, 5.2, z - 0.5, z + 0.5, C.Kelp3)
	end
	-- fish: a body, a tail fin, a dorsal fin and an eye; two sizes, most swim across the tank (their
	-- profile shows from the gate)
	for _, f in
		{
			{ -4.4, 2.9, 77.2, true, 1, 4.2, FL[7], FL[2] },
			{ 6.4, 1.8, 86.2, true, -1, 3, FL[5], FL[1] },
			{ -7.4, 3.1, 90, false, 1, 4, FL[2], FL[7] },
			{ 4.2, 3.3, 94, true, -1, 3, FL[3], FL[5] },
		}
	do
		local x, y, z, alongX, dir, len = f[1], s + f[2], f[3], f[4], f[5], f[6]
		local h, wd = len * 0.6, len * 0.32
		local function fishPart(name: string, u: number, v: number, su: number, sv: number, sw: number, c: any)
			-- u along the fish (+ towards its head), v up
			if alongX then
				span(
					tank,
					name,
					x + dir * u - su / 2,
					x + dir * u + su / 2,
					y + v - sv / 2,
					y + v + sv / 2,
					z - sw / 2,
					z + sw / 2,
					c,
					DECOR
				)
			else
				span(
					tank,
					name,
					x - sw / 2,
					x + sw / 2,
					y + v - sv / 2,
					y + v + sv / 2,
					z + dir * u - su / 2,
					z + dir * u + su / 2,
					c,
					DECOR
				)
			end
		end
		fishPart("Fish", 0, 0, len, h, wd, f[7])
		fishPart("FishTail", -len / 2 - 0.4, 0, 0.8, h * 1.25, wd * 0.45, f[8])
		fishPart("FishFin", -len * 0.08, h / 2 + 0.25, len * 0.45, 0.5, wd * 0.4, f[8])
		fishPart("FishEye", len * 0.3, h * 0.12, 0.4, 0.4, wd + 0.12, C.Ink)
	end
	-- the star of the tank: a big clownfish (orange with white bands) over the reef, facing the gate
	local fx, fy, fz = -1.4, s + 2.3, 78.6
	span(tank, "HeroFish", fx - 3, fx + 3, fy - 1.6, fy + 1.6, fz - 0.95, fz + 0.95, C.Orange, DECOR)
	span(tank, "HeroStripe", fx - 1.5, fx - 0.7, fy - 1.7, fy + 1.7, fz - 1.05, fz + 1.05, C.White, DECOR)
	span(tank, "HeroStripe", fx + 1, fx + 1.7, fy - 1.4, fy + 1.4, fz - 1.05, fz + 1.05, C.White, DECOR)
	span(tank, "HeroTail", fx + 3, fx + 4.1, fy - 1.7, fy + 1.7, fz - 0.35, fz + 0.35, C.Orange, DECOR)
	span(tank, "HeroFin", fx - 1, fx + 1.4, fy + 1.6, fy + 2.4, fz - 0.3, fz + 0.3, C.Orange, DECOR)
	span(tank, "HeroEye", fx - 2.5, fx - 1.8, fy + 0.15, fy + 0.85, fz - 1.07, fz + 1.07, C.Ink, DECOR)
	-- columns of bubbles (particles: they move and cost no parts); they live at most 3 s
	for _, b in { { "BubblesWest", -3.6, 92 }, { "BubblesEast", 6.6, 80.6 } } do
		local attachment, offset = attachAt(sand, b[1], at(b[2], s + 0.4, b[3]))
		Props.fx(attachment, "bubbles", { rate = 3, size = 1.5, lifetime = U.roblox.NumberRange.new(2.6, 3) })
		table.insert(expected, { root = "template", path = { "Tank", "Sand", b[1] }, offset = offset })
	end

	return tank, expected
end

------------------------------------------------------------------------------------------
-- Display arcades and the 12 display aquariums
------------------------------------------------------------------------------------------

local ARC_IN, ARC_WALL = 22, 37 -- each arcade: deck from |x| = 22 (the aisle) to its back wall
local ARC_Z0, ARC_Z1 = 54.5, 120.5
local ARC_EAVE = 13.5 -- the market bays' eaves (the wall plate and the aisle beam)
local WALL_T = 1.5 -- the back wall's thickness
local SLOT_ROW_X = 33.5
local SLOT_Z0, SLOT_PITCH = 60.5, 11
-- Three gabled market bays per arcade (two displays each): z range and ridge rise; the middle bay
-- stands a little taller.
local BAYS = { { 55.5, 76.5, 6 }, { 77.5, 98.5, 7.2 }, { 99.5, 120.5, 6 } }
local ARC_POSTS = { 56.1, 77, 99, 119.8 }

-- One display aquarium: a timber cabinet with a band of the base colour along its top, a brass rim,
-- a cube of clear sea water on cream sand with a pebble and a sprig of weed, a sea-blue backdrop
-- flush against the arcade's back wall and a glowing light bar along its top that lights the fish
-- (it floats in the centre). Local frame: -Z faces the aisle. The label (owner's fish or "Пусто")
-- and the slot number are on the cabinet's front, under the band.
local function buildSlot(slots: any, index: number, frame: any, expected: { any })
	local slot = U.model(slots, `Slot_{index}`)
	slot:SetAttribute("SlotIndex", index)
	local y0 = ARC_DECK
	local pedestal = box(slot, "Pedestal", frame, 0, y0 + 1.7, 0, 6.8, 3.4, 6.8, C.Cabinet, { CastShadow = true })
	local top = y0 + 3.4
	box(slot, "Band", frame, 0, top - 0.5, -3.45, 7, 0.9, 0.3, -0.1, DECOR)
	box(slot, "Rim", frame, 0, top + 0.3, 0, 7, 0.6, 7, C.Gold)
	local base = top + 0.6
	local display = box(slot, "Display", frame, 0, base + 3.1, 0, 6.2, 6.2, 6.2, C.DisplayWater, {
		Material = M.Glass,
		Transparency = 0.66,
		CastShadow = false,
	})
	box(slot, "Sand", frame, 0, base + 0.35, 0, 5.8, 0.7, 5.8, C.Sand, DECOR)
	-- a sprig of weed in a back corner (it never hides the fish in the centre)
	local side = if index % 4 < 2 then 1 else -1
	box(slot, "Weed", frame, side * 2.1, base + 2, 2, 0.7, 2.6, 0.7, C.Kelp2, DECOR)
	-- a sea-blue backdrop on the back pane (the fish reads against it), flush with the back wall
	box(slot, "Backdrop", frame, 0, base + 3.2, 3.15, 6.6, 6.4, 0.5, C.Backdrop, DECOR)
	-- the light bar along the top front edge, lighting the fish under the roof
	local bar = box(slot, "LightBar", frame, 0, base + 6.35, -2.95, 6.4, 0.3, 0.35, C.AquaGlow, NEON_DECOR)
	U.new("SurfaceLight", {
		Face = Enum.NormalId.Bottom,
		Range = 8,
		Brightness = 1.5,
		Angle = 120,
		Color = C.LightColor,
		Shadows = false,
	}, bar)
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
	-- (30 px per stud and drawn only within 60 studs: 12 of these per base, v3 fix F4)
	local gui = surfaceGui(pedestal, "LabelGui", Enum.NormalId.Front, 30, 60)
	U.new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromScale(0.06, 0.52),
		Size = UDim2.fromScale(0.88, 0.42),
		BackgroundTransparency = 1,
		Text = "Пусто",
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = C.White,
		TextStrokeColor3 = C.Ink,
		TextStrokeTransparency = 0.1,
	}, gui)
	U.new("TextLabel", {
		Name = "Number",
		Position = UDim2.fromScale(0.3, 0.29),
		Size = UDim2.fromScale(0.4, 0.22),
		BackgroundTransparency = 1,
		Text = `№{index}`,
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = C.Cream,
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

-- The two arcades either side of the aquarium: covered fish markets of three gabled bays each. A
-- plank deck, timber posts and a beam along the aisle; a solid back wall (plank, on a stone base
-- course, timber pilasters outside and a fish plaque in the base colour on the middle bay) that
-- the displays' backdrops stand against; over each bay a gable roof in a deep shade of the base
-- colour, its ridge running across the arcade so a gable end faces the court, a darker ridge cap,
-- a lantern hanging at the bay's centre. Small gaps between the bays give the row its rhythm.
local function buildArcades(template: any)
	local arcades = U.model(template, "Arcades")
	for _, sx in { -1, 1 } do
		local arc = U.model(arcades, if sx < 0 then "West" else "East")
		local function X(a: number, b: number): (number, number)
			return mirror(sx, a, b)
		end
		local xa, xb = X(ARC_IN, ARC_WALL)
		span(arc, "Deck", xa, xb, -0.2, ARC_DECK, ARC_Z0, ARC_Z1, C.Plank, FLAT)
		xa, xb = X(ARC_IN - 0.4, ARC_IN + 0.6)
		span(arc, "DeckEdge", xa, xb, -0.2, ARC_DECK + 0.15, ARC_Z0 - 0.2, ARC_Z1 + 0.2, C.WoodDark, FLAT)
		-- the back wall up to the eaves, its stone base course and timber pilasters outside
		local wo = ARC_WALL + WALL_T -- the wall's outer face
		xa, xb = X(ARC_WALL, wo)
		span(arc, "BackWall", xa, xb, -0.2, ARC_EAVE, ARC_Z0, ARC_Z1, C.WoodLight, { CastShadow = true })
		xa, xb = X(wo - 0.1, wo + 0.2)
		span(arc, "WindowBand", xa, xb, 10.2, 12.4, ARC_Z0 + 2, ARC_Z1 - 2, C.WindowGlass, GLASS)
		xa, xb = X(wo - 0.2, wo + 0.6)
		span(arc, "BaseCourse", xa, xb, -0.2, 3.4, ARC_Z0 - 0.3, ARC_Z1 + 0.3, C.Stone)
		xa, xb = X(wo - 0.2, wo + 0.7)
		for _, z in ARC_POSTS do
			span(arc, "Pilaster", xa, xb, 3.4, ARC_EAVE, z - 0.6, z + 0.6, C.WoodDark)
		end
		-- a fish plaque in the base colour on the middle bay, seen from the side strip
		local pz = (BAYS[2][1] + BAYS[2][2]) / 2
		xa, xb = X(wo - 0.1, wo + 0.35)
		span(arc, "Plaque", xa, xb, 5.4, 9.8, pz - 3.8, pz + 3.8, C.Cream, DECOR)
		xa, xb = X(wo + 0.3, wo + 0.6)
		span(arc, "PlaqueFish", xa, xb, 6.7, 8.5, pz - 0.6 * sx - 1.6, pz - 0.6 * sx + 1.6, 0, DECOR)
		span(arc, "PlaqueTail", xa, xb, 6.3, 8.9, pz + 1.55 * sx - 0.55, pz + 1.55 * sx + 0.55, -0.25, DECOR)
		-- posts and the beam along the aisle
		local beamBottom = ARC_EAVE - 1.2
		xa, xb = X(ARC_IN + 0.4, ARC_IN + 1.6)
		for _, z in ARC_POSTS do
			span(arc, "Post", xa, xb, ARC_DECK, beamBottom, z - 0.6, z + 0.6, C.Wood, { CastShadow = true })
		end
		xa, xb = X(ARC_IN + 0.2, ARC_IN + 1.8)
		span(arc, "Beam", xa, xb, beamBottom, ARC_EAVE, ARC_Z0, ARC_Z1, C.WoodDark)
		-- a light plank ceiling under the bays (the market hall is bright inside)
		xa, xb = X(ARC_IN + 1.8, ARC_WALL)
		local ceiling =
			span(arc, "Ceiling", xa, xb, ARC_EAVE - 0.35, ARC_EAVE - 0.05, ARC_Z0, ARC_Z1, C.WoodLight, FLAT)
		ceiling:SetAttribute("StudsBottom", true) -- (the LEGO underside over the aisle: Studs.luau)
		-- the market bays: two roof slopes (a solid prism whose gable end faces the court), a ridge
		-- cap, a lantern hanging from the beam at the bay's centre
		local ra, rb = X(ARC_IN - 0.9, wo + 0.8)
		for i, bay in BAYS do
			local z0, z1, rise = bay[1], bay[2], bay[3]
			local zc = (z0 + z1) / 2
			local top = ARC_EAVE + rise
			ramp(arc, "Roof", ra, rb, ARC_EAVE, top, z0, zc, "-z", -0.38, ROOF_OPTS)
			ramp(arc, "Roof", ra, rb, ARC_EAVE, top, zc, z1, "+z", -0.38, ROOF_OPTS)
			span(arc, "Ridge", ra - 0.2, rb + 0.2, top - 0.5, top + 0.5, zc - 0.7, zc + 0.7, ROOF_TRIM, DECOR)
			hangLantern(arc, sx * (ARC_IN + 1), beamBottom, zc, i == 2)
		end
	end
end

-- Lawn borders between the aquarium terrace and the arcades: a low clipped hedge along each side
-- and a clipped topiary (two stepped tiers in a terracotta pot) at the court's entrance.
local function buildCourtGarden(template: any)
	local garden = U.model(template, "CourtGarden")
	for _, sx in { -1, 1 } do
		local x = sx * 19
		local xa, xb = mirror(sx, 17.4, 19.8)
		span(garden, "LowHedge", xa, xb, LAWN - 0.1, 1.7, 69, 111, C.Hedge, { CanCollide = false })
		local z = 64.6
		span(garden, "TopiaryPot", x - 1.4, x + 1.4, LAWN - 0.1, 1.8, z - 1.4, z + 1.4, C.Terracotta)
		span(garden, "Topiary", x - 1.5, x + 1.5, 1.8, 4.2, z - 1.5, z + 1.5, C.Topiary, DECOR)
		span(garden, "Topiary", x - 1, x + 1, 4.2, 6, z - 1, z + 1, C.Leaf3, DECOR)
	end
end

------------------------------------------------------------------------------------------
-- The guard dog and its kennel (stage 4 upgrade): hidden
------------------------------------------------------------------------------------------

local DOG_X, DOG_Z = 36, 25 -- the kennel in the +X front corner (the dog lies by its door)
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
		span(terrace, "StairCheek", xa, xb, -0.2, TERRACE + 0.6, z0 - run - 0.2, z0 + 0.7, C.Limestone)
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
		-- darker stone pilasters break up the long retaining wall
		for _, px in { 15, 57 } do
			local pa, pb = mirror(sx, px - 0.8, px + 0.8)
			span(terrace, "Pilaster", pa, pb, -0.2, TERRACE + 0.35, z0 - 1.2, z0 + 0.2, C.StoneDark)
		end
	end
	-- the walk along the terrace's front: stairs -> porch, patio (-X), work yard (+X)
	flagWalk(terrace, "TerraceWalk", -56, 56, z0 + 0.6, z0 + 4.4, TERRACE + 0.3, 37, function(u: number): boolean
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
-- The house is built at these numbers, then scaled up about the middle of its back wall (it grows
-- forwards to the terrace's front and upwards): the base's main building, big from the gate.
local HOUSE_SCALE = 1.15
local HOUSE_ANCHOR_Z = 161

-- Uniform scale of every part (and attachment) of `model` about `anchor`.
local function scaleModel(model: any, anchor: any, k: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local cf = d.CFrame
			d.Size = d.Size * k
			d.CFrame = CFrame.new(anchor + (cf.Position - anchor) * k) * cf.Rotation
			local po = d.PivotOffset
			d.PivotOffset = CFrame.new(po.Position * k) * po.Rotation
		elseif d:IsA("Attachment") then
			local acf = d.CFrame
			d.CFrame = CFrame.new(acf.Position * k) * acf.Rotation
		end
	end
end

-- Wall lantern: an iron bracket out of the wall, a glowing glass box under an iron cap. `wf`: frame
-- on the wall's outer face, local -Z out of the wall. 3 parts; returns the glass.
local function wallLantern(parent: any, wf: any): any
	box(parent, "LampBracket", wf, 0, 0.9, -0.6, 0.3, 0.3, 1.2, C.Iron, DECOR)
	local glow = box(parent, "WallLamp", wf, 0, 0, -1.05, 0.9, 1.2, 0.9, C.Glow, NEON_DECOR)
	box(parent, "LampCap", wf, 0, 0.75, -1.05, 1.3, 0.35, 1.3, C.Iron, DECOR)
	return glow
end

-- Window box with two blooms under a window centred at (x, y) on the front wall z. 3 parts.
local function windowBox(parent: any, x: number, y: number, z: number, w: number, pair: { any })
	span(parent, "WindowBox", x - w / 2 - 0.5, x + w / 2 + 0.5, y - 1.1, y, z - 1.2, z, C.Wood)
	span(parent, "Bloom", x - w / 4 - 0.75, x - w / 4 + 0.55, y - 0.2, y + 0.7, z - 1.05, z - 0.25, pair[1], DECOR)
	span(parent, "Bloom", x + w / 4 - 0.55, x + w / 4 + 0.65, y - 0.25, y + 0.6, z - 1, z - 0.3, pair[2], DECOR)
end

-- Returns the chimney smoke attachment's offset (after the scaling).
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
	gableRoof(house, x0, x1, z0, z1, EAVE, mainRise, 2.2, 1, true, WALL, 3)
	local slope = mainRise / (zc - (z0 - 2.2)) -- rise per stud of the main slopes

	-- Chimney through the back slope, a lazy plume of smoke above it.
	local chimneyTop = EAVE + mainRise + 2
	span(house, "Chimney", 13, 16.4, WALL_TOP, chimneyTop, zc + 2.5, zc + 5.9, C.StoneLight, { CastShadow = true })
	local cap = span(house, "ChimneyCap", 12.6, 16.8, chimneyTop, chimneyTop + 0.8, zc + 2.1, zc + 6.3, C.Stone)
	local smoke = attachAt(cap, "SmokeAttachment", at(14.7, chimneyTop + 2.4, zc + 4.2))
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
	local lamp = wallLantern(house, at(3.4, F + 5.3, wz0 - 0.3))
	U.new("PointLight", { Range = 14, Brightness = 1, Color = C.LightColor, Shadows = false }, lamp)
	bench(house, facing(-5.6, 0, wz0 - 1.4, 0), F + 0.8, 3.6)

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
		-- half-timbering: dark studs framing the upper floor's bays
		for _, x in { 11.7, 21.9 } do
			local xa, xb = mirror(sx, x - 0.45, x + 0.45)
			span(house, "Stud", xa, xb, UF_BOT, WALL_TOP, z0 - 0.3, z0 + 0.2, C.WoodDark)
		end
		-- gable sides: a simple window downstairs, a small one upstairs
		local gx = sx * MAIN_X
		window(house, facing(gx, GY, zc - 4, -90 * sx), 3, 3.2, "simple")
		window(house, facing(gx, UY, zc + 4, -90 * sx), 2.6, 2.6, "small")
	end
	-- back (seen from the hill behind the plot): four windows upstairs, a back door in the base
	-- colour under a little canopy, a step
	for _, x in { -18, -6, 6, 18 } do
		window(house, facing(x, UY, z1, 180), 2.6, 2.6, "small")
	end
	span(house, "BackDoorFrame", -2.2, 2.2, F + 1.4, F + 7.4, z1, z1 + 0.3, C.WoodDark)
	span(house, "BackDoor", -1.7, 1.7, F + 1.4, F + 7, z1 + 0.25, z1 + 0.45, -0.3)
	ramp(house, "BackCanopy", -3.2, 3.2, F + 8.3, F + 9.7, z1, z1 + 2.6, "+z", ROOF, { CastShadow = true })
	span(house, "BackStep", -2.6, 2.6, F - 0.2, F + 1.1, z1 + 0.6, z1 + 2.2, C.Limestone)

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
	window(house, at(tcx, UY - 1.4, tz0), 1.8, 2.6, "small")
	-- a clock face under the belvedere, towards the gate
	span(house, "ClockFrame", tcx - 1.9, tcx + 1.9, 23.6, 27.4, tz0 - 0.35, tz0 + 0.2, C.Gold)
	span(house, "Clock", tcx - 1.4, tcx + 1.4, 24.1, 26.9, tz0 - 0.5, tz0, C.Cream)
	span(house, "ClockHand", tcx - 0.12, tcx + 0.12, 25.4, 26.6, tz0 - 0.6, tz0 - 0.45, C.Ink, DECOR)
	span(house, "ClockHand", tcx - 0.12, tcx + 0.9, 25.38, 25.62, tz0 - 0.6, tz0 - 0.45, C.Ink, DECOR)
	window(house, facing(tx1, 25.2, tcz - 1.5, -90), 1.8, 2.6, "small")
	span(house, "Belvedere", tx0 - 1.2, tx1 + 1.2, bf, bf + 1, tz0 - 1.2, tz1 + 0.8, C.Wood, { CastShadow = true })
	local bt = bf + 8.6 -- roof base (head room for the avatar and its camera on the belvedere)
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
		y += 8.4
	end

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
	span(house, "Pennant", tcx + 0.2, tcx + 2.6, y + 0.5, y + 1.6, tcz - 0.1, tcz + 0.1, 0, DECOR)
	local fish = span(house, "VaneFish", tcx - 2, tcx + 1.6, y + 3, y + 4.7, tcz - 0.25, tcz + 0.25, C.Gold, DECOR)
	span(house, "VaneTail", tcx + 1.6, tcx + 2.8, y + 2.7, y + 5, tcz - 0.2, tcz + 0.2, C.Gold, DECOR)
	Props.fx(fish, "sparkle", { rate = 1, size = 1.2 })

	-- Planted beds along the main front either side of the wing.
	for _, sx in { -1, 1 } do
		local pair = if sx < 0 then JEWELS[5] else JEWELS[6]
		flowerBed(house, sx * 17, F, z0 - 2.6, 9, 2.4, pair, { spacing = 2.6, max = 2 })
	end

	-- Scale the whole house up about the middle of its back wall's foot.
	local k = HOUSE_SCALE
	scaleModel(house, Vector3.new(0, F, HOUSE_ANCHOR_Z), k)
	-- The climbable truss (its size stays on the 2-stud grid) beside the scaled ladder, reaching 3
	-- studs over the belvedere floor.
	local trussH = math.ceil((bf + 3 - F) * k / 2) * 2
	U.partCount += 1
	U.new("TrussPart", {
		Name = "LadderTruss",
		Size = Vector3.new(2, trussH, 2),
		CFrame = at(lx * k - 0.6, F + trussH / 2, HOUSE_ANCHOR_Z + (tcz - HOUSE_ANCHOR_Z) * k),
		Anchored = true,
		Transparency = 1,
		CastShadow = false,
		CanTouch = false,
		Color = C.Wood,
	}, house)
	return smoke.CFrame.Position
end

-- The smokehouse (+X of the house, at the front of the terrace): timber walls on a stone footing,
-- the gable to the court, double doors under the name board, a stone chimney with a cap, a net
-- hung in three folds on its side, a wall lantern by the doors. Returns the smoke attachment's
-- offset.
local SMOKE_X0, SMOKE_X1, SMOKE_Z0, SMOKE_Z1 = 35, 48, 128.5, 142.5

local function buildSmokehouse(template: any): any
	local shed = U.model(template, "Smokehouse")
	local F = TERRACE
	local x0, x1, z0, z1 = SMOKE_X0, SMOKE_X1, SMOKE_Z0, SMOKE_Z1
	local wallTop = F + 8.6
	local eave = wallTop + 0.8
	local xc = (x0 + x1) / 2
	span(shed, "Footing", x0 - 0.4, x1 + 0.4, F - 0.2, F + 1, z0 - 0.4, z1 + 0.4, C.Stone)
	span(shed, "Walls", x0, x1, F + 1, wallTop, z0, z1, C.Wood, { CastShadow = true })
	span(shed, "WallPlate", x0 - 0.3, x1 + 0.3, wallTop, eave, z0 - 1.2, z1 + 1.2, C.WoodDark)
	gableRoof(shed, x0, x1, z0, z1, eave, 6, 1.6, 1, false, C.WoodLight, 2)

	-- Double doors and the name board above them.
	span(shed, "DoorFrame", xc - 4.6, xc + 4.6, F + 1, F + 8.2, z0 - 0.3, z0, C.WoodDark)
	for _, sx in { -1, 1 } do
		local xa, xb = math.min(xc + sx * 0.1, xc + sx * 4), math.max(xc + sx * 0.1, xc + sx * 4)
		span(shed, "Door", xa, xb, F + 1, F + 7.6, z0 - 0.45, z0 - 0.25, C.WoodLight)
	end
	local board = span(shed, "Board", xc - 3.6, xc + 3.6, F + 8.3, wallTop - 0.1, z0 - 0.4, z0, C.Cream)
	plainText(board, Enum.NormalId.Front, "КОПТИЛЬНЯ", C.Ink, false)
	-- Stone chimney through the east slope, smoke curling out under its cap.
	local cx, cz = x1 - 3.2, z1 - 4
	local top = eave + 8
	span(shed, "Chimney", cx - 1.3, cx + 1.3, wallTop - 1, top, cz - 1.3, cz + 1.3, C.StoneLight, { CastShadow = true })
	local cap = span(shed, "ChimneyCap", cx - 1.7, cx + 1.7, top, top + 0.7, cz - 1.7, cz + 1.7, C.StoneDark)
	local smoke, smokeOffset = attachAt(cap, "SmokeAttachment", at(cx, top + 1.2, cz))
	Props.fx(smoke, "smoke", { rate = 3 })
	-- A fishing net drying on the east wall (towards the work yard) in three folds of two greens,
	-- an orange float on the middle one.
	for i, f in { { z0 + 2, z0 + 5.2, F + 3.4 }, { z0 + 5.4, z0 + 8.8, F + 4.6 }, { z0 + 9, z0 + 12.2, F + 2.6 } } do
		span(
			shed,
			"Net",
			x1 + 0.05,
			x1 + 0.35,
			f[3],
			F + 7.6,
			f[1],
			f[2],
			if i == 2 then C.NetRopeLight else C.NetRope,
			{
				CanCollide = false,
				CastShadow = false,
			}
		)
	end
	span(shed, "NetFloat", x1 + 0.3, x1 + 0.9, F + 5, F + 6, z0 + 6.6, z0 + 7.6, FL[6], DECOR)
	-- Lantern beside the doors.
	wallLantern(shed, at(xc + 5.6, F + 6.4, z0))
	return smokeOffset
end

-- Work yard beside the smokehouse: a gravel yard with the woodpile against the hedge, a chopping
-- stump with its axe and a rack of fish drying in the smoke's lee.
local function buildWorkYard(template: any)
	local yard = U.model(template, "WorkYard")
	local F = TERRACE
	span(yard, "Yard", 50, 62.5, F - 0.2, F + 0.3, 127, 150, C.Gravel, FLAT)
	span(yard, "Logs", 58.6, 62.4, F + 0.2, F + 3, 136, 148, C.Bark, { CastShadow = true })
	span(yard, "LogEnds", 58.45, 62.55, F + 0.3, F + 2.8, 136.2, 147.8, C.CutWood, DECOR)
	span(yard, "LogsTop", 59, 62, F + 3, F + 4.5, 137, 147, C.Bark)
	-- a chopping stump with an axe in it
	span(yard, "Stump", 53.2, 55.8, F + 0.2, F + 2, 144.2, 146.8, C.Bark)
	span(yard, "CutFace", 53.5, 55.5, F + 1.95, F + 2.15, 144.5, 146.5, C.CutWood, DECOR)
	make(
		yard,
		"Axe",
		Vector3.new(0.3, 2.6, 0.3),
		at(54.9, F + 3.1, 145.5) * CFrame.Angles(0, 0, rad(-20)),
		C.WoodLight,
		DECOR
	)
	-- the drying rack: two posts, a bar, three fish hung by their tails
	local rz = 132
	for _, x in { 51.2, 59.8 } do
		span(yard, "RackPost", x - 0.45, x + 0.45, F, F + 7.6, rz - 0.45, rz + 0.45, C.WoodDark)
	end
	span(yard, "RackBar", 50.9, 60.1, F + 6.8, F + 7.4, rz - 0.35, rz + 0.35, C.Wood)
	for i, x in { 53.4, 55.5, 57.6 } do
		local c = if i % 2 == 1 then C.FishSilver else C.FishSilverDark
		local h = if i == 2 then 3.4 else 2.8
		span(yard, "FishTail", x - 0.8, x + 0.8, F + 6, F + 6.8, rz - 0.2, rz + 0.2, c, DECOR)
		span(yard, "DriedFish", x - 0.65, x + 0.65, F + 6 - h, F + 6, rz - 0.3, rz + 0.3, c, DECOR)
	end
end

-- Seating patio by the tower: flagstones edged by low stone planters, a trestle table with two
-- benches under a parasol in the base colour, a lantern post.
local function buildPatio(template: any)
	local patio = U.model(template, "Patio")
	local F = TERRACE
	local top = F + 0.3
	span(patio, "Paving", -60, -44, F - 0.2, top, 128.5, 143, C.Flag, FLAT)
	span(patio, "Planter", -62.4, -60, F - 0.2, F + 1.4, 128.5, 145.4, C.Stone)
	span(patio, "PlanterLeaves", -62.1, -60.3, F + 1.4, F + 2.3, 128.8, 145.1, C.Leaf1, DECOR)
	span(patio, "Planter", -60, -45, F - 0.2, F + 1.4, 143, 145.4, C.Stone)
	span(patio, "PlanterLeaves", -59.8, -45.3, F + 1.4, F + 2.3, 143.3, 145.1, C.Leaf1, DECOR)
	for i, z in { 131.5, 137.5 } do
		span(
			patio,
			"PlanterBloom",
			-61.8,
			-60.6,
			F + 2.1,
			F + 2.9,
			z - 0.6,
			z + 0.6,
			FL[if i == 1 then 1 else 2],
			DECOR
		)
	end
	local cx, cz = -52, 135.5
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
	lanternPost(patio, -45.4, 140.6, top, 6, true)
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
	-- cabbages: a wide ring of dark outer leaves round a tall light heart
	bed(-61, -51)
	for i, z in { 30, 35.5, 41, 46.5 - 2.2 } do
		local x = -56 + (if i % 2 == 0 then 1.6 else -1.6)
		span(garden, "Cabbage", x - 1.7, x + 1.7, 1.5, 2.6, z - 1.7, z + 1.7, C.CabbageOuter, { CanCollide = false })
		span(garden, "CabbageHeart", x - 1.05, x + 1.05, 2.3, 3.9, z - 1.05, z + 1.05, C.CabbageHeart, DECOR)
	end
	-- pumpkins on a vine: two crossed slices in two oranges (a round, ribbed body) and a curly stalk
	bed(-48.3, -39)
	span(garden, "Vine", -44, -43, 1.5, 2.1, z0 + 1.6, z1 - 1.6, C.Leaf1, DECOR)
	for i, z in { 30.5, 36.5, 42.5 } do
		local x = -43.5 + (if i % 2 == 0 then 1.6 else -1.6)
		local s = if i == 2 then 1.15 else 1
		span(garden, "Pumpkin", x - 1.6 * s, x + 1.6 * s, 1.5, 1.5 + 2 * s, z - 1.05 * s, z + 1.05 * s, C.Pumpkin, {
			CanCollide = false,
		})
		span(
			garden,
			"PumpkinRib",
			x - 1.05 * s,
			x + 1.05 * s,
			1.45,
			1.6 + 2.15 * s,
			z - 1.6 * s,
			z + 1.6 * s,
			C.PumpkinLight,
			DECOR
		)
		make(
			garden,
			"Stalk",
			Vector3.new(0.45, 1, 0.45),
			at(x + 0.15, 1.6 + 2.15 * s + 0.35, z) * CFrame.Angles(0, 0, rad(-25)),
			C.Leaf0,
			DECOR
		)
	end
	-- two bean poles: a thin stake, leaves climbing it in staggered tufts, pods and white flowers
	for i, z in { z0 + 5, z1 - 5 } do
		local x = -35
		span(garden, "BeanPole", x - 0.15, x + 0.15, 0, 8.6, z - 0.15, z + 0.15, C.WoodDark, DECOR)
		local d = if i == 1 then 1 else -1
		span(garden, "BeanLeaves", x - 1.1, x + 0.5, 0.2, 2.6, z - 0.9 * d - 0.5, z - 0.9 * d + 0.9, C.Leaf1, DECOR)
		span(garden, "BeanLeaves", x - 0.4, x + 1.1, 2.4, 4.8, z + 0.6 * d - 0.6, z + 0.6 * d + 0.7, C.Leaf2, DECOR)
		span(garden, "BeanLeaves", x - 0.9, x + 0.5, 4.6, 6.8, z - 0.4 * d - 0.6, z - 0.4 * d + 0.6, C.Leaf3, DECOR)
		span(garden, "BeanPods", x + 0.6, x + 1.0, 1.2, 3.4, z - 0.8 * d - 0.2, z - 0.8 * d + 0.2, C.Bean, DECOR)
	end
	-- the sign at the yard end of the beds, read from the gate
	span(garden, "SignPost", -46.3, -45.7, 0, 3.4, z0 - 2.4, z0 - 1.6, C.WoodDark)
	local board = span(garden, "SignBoard", -49.2, -42.8, 3.2, 5.6, z0 - 2.6, z0 - 1.8, C.WoodLight)
	plainText(board, Enum.NormalId.Front, "ОГОРОД", C.Ink, false)
	-- rain barrel at the end of the beds
	cylY(garden, "RainBarrel", 2.6, 3.2, at(-31.4, LAWN + 1.6, 28), C.Wood, { CastShadow = true })
end

-- Tackle shed: a timber hut on a stone footing under a gable roof in the base colour (the gable
-- with the name board faces the gate), a door under an awning towards the spawn, a window, a
-- wall lantern, a rack of painted rods outside, a bait barrel and a crate.
local function buildTackleShed(template: any)
	local shed = U.model(template, "TackleShed")
	local x0, x1, z0, z1 = 46, 58, 28, 38
	local xc = (x0 + x1) / 2
	local wallTop = 8.2
	span(shed, "Footing", x0 - 0.4, x1 + 0.4, -0.2, 0.9, z0 - 0.4, z1 + 0.4, C.Stone)
	span(shed, "Walls", x0, x1, 0.9, wallTop, z0, z1, C.Wood, { CastShadow = true })
	gableRoof(shed, x0, x1, z0, z1, wallTop, 4.6, 1.3, 1.1, false, C.WoodLight, 2)
	-- door (towards the walk from the spawn rose) under an awning, a lantern beside it
	span(shed, "Door", x0 - 0.25, x0 + 0.05, 0.9, 6.9, 34.6, 37.4, C.WoodDark)
	ramp(shed, "Awning", x0 - 2.6, x0, 6.9, 7.9, 33.8, 38.2, "-x", 0, { CanCollide = false })
	wallLantern(shed, facing(x0, 5.4, 33, 90))
	window(shed, facing(x0, 4.6, 30.6, 90), 2, 2.2, "small")
	-- the name board in the gable, facing the gate
	local board = span(shed, "Board", xc - 2.5, xc + 2.5, wallTop + 0.4, wallTop + 2.2, z0 - 1.6, z0 - 1.2, C.Cream)
	plainText(board, Enum.NormalId.Front, "СНАСТИ", C.Ink, false)
	-- a rack of painted rods on the front wall (towards the gate), a bait barrel, a crate
	local rz = z0 - 1.1
	for _, x in { 48.6, 55.4 } do
		span(shed, "RackPost", x - 0.35, x + 0.35, 0, 4.6, rz - 0.35, rz + 0.35, C.WoodDark)
	end
	span(shed, "RackBar", 48.2, 55.8, 3.6, 4.2, rz - 0.4, rz + 0.4, C.WoodLight)
	for i, rod in { { 50, P.Festive[1] }, { 52, P.Festive[2] }, { 54, P.Festive[4] } } do
		make(
			shed,
			"Rod",
			Vector3.new(0.3, 8.6, 0.3),
			at(rod[1], 4.4, rz - 0.1) * CFrame.Angles(rad(-6), 0, rad(if i == 2 then 0 else (i - 2) * 5)),
			rod[2],
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

-- The fry pond: an L of water inside chunky natural stones of two greys (one steps into the
-- water), lilies, reeds, a little plank jetty with a bench at its end, the sign.
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
	-- chunky rim stones of varied heights all round (the jetty's gap on the west side)
	for i, st in
		{
			{ 44.8, 55.2, 65.6, 67.4, 1.2 },
			{ 55, 63.4, 65.4, 67.3, 1.8 },
			{ 44.4, 46.4, 67, 81.4, 1.5 },
			{ 44.6, 46.3, 85.6, 98.8, 1 },
			{ 44.8, 52.6, 98.6, 100.6, 1.4 },
			{ 50.8, 52.5, 100.4, 106.2, 1.9 },
			{ 52.4, 63.4, 104.6, 106.6, 1.1 },
			{ 61.6, 63.8, 67, 104.9, 1.5 },
		}
	do
		local c = if i % 2 == 1 then P.RockLight else P.RockMid
		span(pond, "RimStone", st[1], st[2], -0.2, st[5], st[3], st[4], c, { CastShadow = st[5] > 1.4 })
	end
	Props.lilyPad(pond, at(50, 0.8, 72.5), { seed = 3, flower = true })
	Props.lilyPad(pond, at(57, 0.8, 101.5), { seed = 5, flower = true })
	reeds(pond, 47.6, 0.4, 96.4)
	reeds(pond, 60.2, 0.4, 69.2)
	-- little plank jetty from the west side, a bench at its land end looking over the water
	span(pond, "Jetty", 44.6, 52.9, 0.9, 1.4, 81.6, 85.4, C.Plank)
	for _, z in { 81.9, 85.1 } do
		span(pond, "JettyPost", 52.2, 53, 0.4, 2.6, z - 0.4, z + 0.4, C.WoodDark)
	end
	bench(pond, facing(42.4, 0, 89.2, -90), LAWN, 4.4)
	-- the sign by the front stones
	span(pond, "SignPost", 47.7, 48.3, 0, 3.4, 66 - 2.2, 66 - 1.4, C.WoodDark)
	local board = span(pond, "SignBoard", 45, 51, 3.2, 5.4, 66 - 2.4, 66 - 1.6, C.WoodLight)
	plainText(board, Enum.NormalId.Front, "МАЛЬКИ", C.Ink, false)
end

-- The net yard: a drying frame on a gravel bed (two rope nets with a grid of light ropes, floats
-- along their foot), the well, lobster pots by it, a bench under the apple tree.
local function buildNetYard(template: any)
	local yard = U.model(template, "NetYard")
	span(yard, "Yard", -60, -48, -0.2, 0.45, 62.5, 93, C.Gravel, FLAT)
	-- net-drying frame: three posts and a pole
	local nx = -54
	for _, z in { 66, 77, 88 } do
		span(yard, "NetPost", nx - 0.45, nx + 0.45, 0, 9.2, z - 0.45, z + 0.45, C.WoodDark, { CastShadow = true })
	end
	span(yard, "NetPole", nx - 0.3, nx + 0.3, 8.4, 9, 65.4, 88.6, C.Wood)
	-- two nets hanging from the pole: see-through mesh panels with a grid of lighter ropes
	local netBottom = 2.6
	for _, p in { { 66.6, 76.4 }, { 77.6, 87.4 } } do
		span(yard, "Net", nx - 0.1, nx + 0.1, netBottom, 8.4, p[1], p[2], C.NetRope, {
			Transparency = 0.45,
			CanCollide = false,
			CastShadow = false,
		})
		for _, t in { 0.5 } do
			local z = p[1] + (p[2] - p[1]) * t
			span(yard, "NetRope", nx - 0.18, nx + 0.18, netBottom, 8.4, z - 0.12, z + 0.12, C.NetRopeLight, DECOR)
		end
	end
	for _, y in { 4.6, 6.6 } do
		span(yard, "NetRope", nx - 0.18, nx + 0.18, y - 0.12, y + 0.12, 66.6, 87.4, C.NetRopeLight, DECOR)
	end
	for i, z in { 69.4, 73.8, 80.4, 84.8 } do
		local c = if i % 2 == 1 then FL[6] else C.Cream
		span(yard, "NetFloat", nx - 0.5, nx + 0.5, netBottom - 0.4, netBottom + 0.5, z - 0.5, z + 0.5, c, DECOR)
	end
	-- stone well with a little timber roof
	local wx, wz = -50, 104
	span(yard, "WellRing", wx - 3, wx + 3, 0, 2.8, wz - 3, wz + 3, C.StoneLight, { CastShadow = true })
	span(yard, "WellWater", wx - 2.2, wx + 2.2, 2.75, 2.95, wz - 2.2, wz + 2.2, C.Water, DECOR)
	for _, sx in { -1, 1 } do
		span(yard, "WellPost", wx + sx * 2.4 - 0.4, wx + sx * 2.4 + 0.4, 2.8, 8.6, wz - 0.4, wz + 0.4, C.WoodDark)
	end
	span(yard, "Crossbar", wx - 3, wx + 3, 7, 7.6, wz - 0.3, wz + 0.3, C.Wood, DECOR)
	ramp(yard, "WellRoof", wx - 4, wx + 4, 8.6, 10.8, wz - 3.4, wz, "-z", C.RoofBrown, { CastShadow = true })
	ramp(yard, "WellRoof", wx - 4, wx + 4, 8.6, 10.8, wz, wz + 3.4, "+z", C.RoofBrown)
	span(yard, "Bucket", wx - 0.6, wx + 0.6, 4.6, 5.8, wz - 0.6, wz + 0.6, C.Wood, DECOR)
	-- a bench in the apple tree's shade, looking over the court
	bench(yard, facing(-56.6, 0, 61.6, -90), LAWN, 4.6)
end

-- The front yard's vignette (+X, between the spawn rose and the tackle shed): a rowing boat being
-- repainted on two trestles, a fresh band of the base colour along its gunwale, paint pots on the
-- grass; a lantern post by the fry pond's corner.
local function buildBoatRepair(template: any)
	local boat = U.model(template, "BoatRepair")
	local z = 47
	for _, x in { 31, 37.4 } do
		span(boat, "Trestle", x - 0.45, x + 0.45, 0, 2.2, z - 2.8, z + 2.8, C.WoodDark)
	end
	span(boat, "Hull", 29.4, 38.8, 2.2, 3.4, z - 1.4, z + 1.4, C.WoodLight, { CastShadow = true })
	for _, sz in { -1, 1 } do
		local za, zb = z + sz * 1.3, z + sz * 2.1
		span(boat, "HullSide", 28.9, 39.3, 3, 5, math.min(za, zb), math.max(za, zb), C.Cream, { CastShadow = true })
		za, zb = z + sz * 1.2, z + sz * 2.25
		span(boat, "Gunwale", 28.7, 39.5, 5, 5.5, math.min(za, zb), math.max(za, zb), -0.05)
	end
	-- the bow: two wedges laid on their sides, tapering to a point
	-- (each wedge's right-angle corner on the hull's end and centre line, its slope the bow's side)
	for _, sz in { -1, 1 } do
		local bowCf = CFrame.fromMatrix(
			Vector3.new(27.9, 4.3, z + sz * 0.7),
			Vector3.new(0, sz, 0),
			Vector3.new(0, 0, sz),
			Vector3.new(1, 0, 0)
		)
		make(boat, "Bow", Vector3.new(2.6, 1.4, 2.2), bowCf, C.Cream, { wedge = true })
	end
	span(boat, "Stern", 39.2, 40, 3, 5.4, z - 2, z + 2, C.WoodDark)
	cylY(boat, "PaintPot", 1.3, 1.3, at(33.2, LAWN + 0.6, z + 4.1), 0, DECOR)
	lanternPost(boat, 60.6, 56.4, LAWN, 5)
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
-- The shelter on the platform's -X side (v3 fix W1: 2.5 studs further out and 6 inland than
-- before): its post centres x PAV_X0 / PAV_X1, z pierEnd + PAV_Z0 / PAV_Z1. Seen from the default
-- follow camera behind the spot (base-local (0, 9.5, -55.6), 18° down) the front-right post
-- (-12.5, -60.5) stands just outside a phone's frame (2.16:1, vertical FOV 70: ±56.6° across at
-- eye level, less towards the deck), so it no longer cuts a brown diagonal through the lagoon;
-- only the roof's corner shows top-left. (The back-left post keeps 0.1 off the corner pile.)
local PAV_X0, PAV_X1 = -PLAT_HALF + 1.2, -12.5
local PAV_Z0, PAV_Z1 = 11.5, 21

-- Deck slab (top at `top`) with raised plank strips (4 studs wide, every 8) lying on its top:
-- along Z for the walkway (from z0 to plankEnd, default z1), across (along X) for the platform,
-- the whole width (v3 fix W4: whole-stud plank faces; the strips' ends only touch the deck's
-- sides at its top edge, no shared face area). z0 < z1.
-- Plank strip tones (zero-part variety, v3 detail): weathered boards in three tones by turns, so the
-- long runs of deck do not read as one flat colour.
local PLANK_TONES = {
	C.Plank:Lerp(C.Wood, 0.45),
	C.Plank:Lerp(C.Wood, 0.62),
	C.Plank:Lerp(C.WoodLight, 0.3),
}
local plankTone = 0

local function deck(
	parent: any,
	halfWidth: number,
	z0: number,
	z1: number,
	across: boolean,
	top: number,
	plankEnd: number?
)
	span(parent, "Deck", -halfWidth, halfWidth, DECK - 1.2, top, z0, z1, C.Plank)
	local flat = { CastShadow = false }
	local function strip(): any
		plankTone += 1
		return PLANK_TONES[(plankTone - 1) % #PLANK_TONES + 1]
	end
	if across then
		local z = z0 + 2
		while z + 4 <= z1 - 1 do
			span(parent, "Planks", -halfWidth, halfWidth, top, PLANK, z, z + 4, strip(), flat)
			z += 8
		end
	else
		local x = -halfWidth + 2
		while x + 4 <= halfWidth - 2 + 0.01 do
			span(parent, "Planks", x, x + 4, top, PLANK, z0, plankEnd or z1, strip(), flat)
			x += 8
		end
	end
end

-- Returns the z of the walkway's last post pair (the boat's bow line is tied to it).
local function buildPier(template: any, pierEnd: number, pileBottom: number): number
	local PIER_END = pierEnd + PLATFORM_DEPTH -- walkway ends, platform begins
	local pier = U.model(template, "Pier")
	local hw = PIER_HALF
	-- (the walkway slab sits 0.14 under the promenade tiles it runs into: no shared plane; its
	-- planks stop a stud short of the promenade's edge, so they never run in under its flags)
	deck(pier, hw, PIER_END, 0, false, DECK - 0.1, -1)
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
	local z0, z1 = pierEnd + 1, PIER_END -- (40 x 21: whole studs)
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
	local zf, zb = z0 + 0.6, z1 - 1.1 -- (front posts at -70.4: the PierKit lanterns stand on them)
	for _, p in
		{
			{ -pe, zf },
			{ pe, zf },
			{ -pe, zb },
			{ pe, zb },
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
	local x0, x1 = PAV_X0, PAV_X1 -- post centres
	local z0, z1 = pierEnd + PAV_Z0, pierEnd + PAV_Z1
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
	-- (v3 fix W4: the ring 7 x 7 round the 5 x 5 mat — exactly one ring of whole studs; the mat is a
	-- smooth LEGO tile, Studs = false. The server reads only FishingSpot.Position.)
	local sz = pierEnd + 4.5
	local plat = template:FindFirstChild("Platform")
	span(plat, "SpotRing", -3.5, 3.5, DECK, PLANK + 0.15, sz - 3.5, sz + 3.5, C.Cream, { CanCollide = false })
	local spot = span(template, "FishingSpot", -2.5, 2.5, DECK, PLANK + 0.3, sz - 2.5, sz + 2.5, 0.35, {
		CastShadow = false,
	})
	spot:SetAttribute("Studs", false)
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
	-- Rod rack on the left of the platform, under the shelter behind its bench.
	local rx, rz = (PAV_X0 + PAV_X1) / 2, pierEnd + PAV_Z1 - 3.5
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

--[[
	Pier micro-kit (v3 detail): the fisherman's clutter that frames the cast and fills the 1 640
	studs² of deck the owner looks at most. Two lanterns on the front posts frame the open middle;
	beside the spot a tackle box in the base colour and a stool; battens across the walkway every 8
	studs, rope coils, a stack of fish traps, a net with floats over the right rail and fish drying
	under it, a basket of the catch, a crab pot on a line, a string of pennants in the base colour
	across the walkway's end, a pennant on the shelter's roof, a windsock, a shell wind chime under
	the roof, two buoys hung on the walkway posts, algae collars on the piles at the waterline and
	potted plants at the pier's root. One of four little scenes per base (variants by base index).
	Rules (tests/stage1_bases.test.luau): every part is decor (no collisions, raycasts, touches,
	shadows); nothing in the walkway's middle lane (|x| <= 4.5); nothing above y 7 within 13 studs
	of the fishing spot and nothing over 1.5 tall right behind the player (|x| <= 7, z -67..-55, the
	follow camera); nothing above the water in the cast clear zone (x -6..16, z -72..-115).
]]
local KIT = { CanCollide = false, CanQuery = false, CastShadow = false }
local KIT_NEON = { Material = M.Neon, CanCollide = false, CanQuery = false, CastShadow = false }

local function buildPierDressing(template: any, pierEnd: number, waterY: number, lastPostZ: number)
	local kit = U.model(template, "PierKit")
	local frontZ = pierEnd + 1.6 -- the front posts' centres (-70.4)
	local sz = pierEnd + 4.5 -- the fishing spot

	-- Lanterns on the two front posts: they frame the cast (no PointLight: the shelter has one).
	local lanterns = U.model(kit, "Lanterns")
	for _, sx in { -1, 1 } do
		local x, top = sx * 9, DECK + 4.2
		span(lanterns, "Lantern", x - 0.7, x + 0.7, top, top + 1.4, frontZ - 0.7, frontZ + 0.7, C.Glow, KIT_NEON)
		span(
			lanterns,
			"LanternCap",
			x - 1.05,
			x + 1.05,
			top + 1.4,
			top + 1.9,
			frontZ - 1.05,
			frontZ + 1.05,
			C.Iron,
			KIT
		)
	end

	-- Dark battens across the walkway every 8 studs (a rhythm on the long plank run), 0.06 proud of
	-- the plank strips.
	local walk = U.model(kit, "Walkway")
	for i = 0, 5 do
		local z = -6 - i * 8
		span(walk, "Batten", -7.9, 7.9, DECK - 0.15, PLANK + 0.06, z - 0.25, z + 0.25, C.WoodDark, KIT)
	end
	-- a rope coil by the kerb near the root, two buoys hung on the outer faces of the middle posts
	cylY(walk, "RopeCoil", 2.2, 0.5, at(6.3, DECK - 0.1 + 0.25, -10), C.Rope, KIT)
	cylY(walk, "RopeCoilHole", 0.9, 0.56, at(6.3, DECK - 0.1 + 0.28, -10), P.Twine, KIT)
	for i, sx in { -1, 1 } do
		local x = sx * (PIER_HALF + 1.85)
		local buoy = U.model(walk, "HungBuoy")
		make(
			buoy,
			"Buoy",
			Vector3.new(1.3, 1.3, 1.3),
			at(x, 2.4, -32.7),
			C.Red,
			merge(KIT, { Shape = Enum.PartType.Ball })
		)
		span(buoy, "BuoyBand", x - 0.7, x + 0.7, 2.25, 2.55, -33.4, -32.0, C.White, KIT)
		sway(buoy, at(x, 3.3, -32.7), 5, "Z", 2.6 + 0.3 * i)
	end
	-- potted plants on both sides of the pier's root (pot, bush, a jewel bloom)
	for i, sx in { -1, 1 } do
		local x, z = sx * 6.6, -3.6
		span(walk, "Pot", x - 0.8, x + 0.8, DECK - 0.1, DECK + 1.2, z - 0.8, z + 0.8, C.Terracotta, KIT)
		span(walk, "PotBush", x - 1.0, x + 1.0, DECK + 1.2, DECK + 2.5, z - 1.0, z + 1.0, C.Leaf1, KIT)
		local bx = x - 0.3 * sx
		span(
			walk,
			"PotBloom",
			bx - 0.4,
			bx + 0.4,
			DECK + 2.5,
			DECK + 2.95,
			z - 0.4,
			z + 0.4,
			FL[if i == 1 then 1 else 3],
			KIT
		)
	end
	-- a string of pennants across the walkway's end, between the lantern caps (above head height):
	-- two sagging rope halves, pennants in the base colour, cream and yellow by turns
	local pennants = U.model(walk, "Pennants")
	local y0, ymid, pz = DECK + 7.9, DECK + 7.1, lastPostZ
	for _, sx in { -1, 1 } do
		local a = Vector3.new(sx * 8.2, y0, pz)
		local b = Vector3.new(0, ymid, pz)
		make(pennants, "Rope", Vector3.new(0.15, 0.15, (a - b).Magnitude), CFrame.lookAt((a + b) / 2, b), C.Rope, KIT)
	end
	for i, x in { -5.6, -2.8, 0, 2.8, 5.6 } do
		local y = ymid + (y0 - ymid) * (math.abs(x) / 8.2) - 0.05
		local paint = if i % 2 == 1 then 0 elseif i == 2 then C.Cream else C.Yellow
		span(pennants, "Pennant", x - 0.55, x + 0.55, y - 1.0, y, pz - 0.08, pz + 0.08, paint, KIT)
		span(pennants, "PennantTip", x - 0.25, x + 0.25, y - 1.45, y - 0.98, pz - 0.08, pz + 0.08, paint, KIT)
	end
	sway(pennants, at(0, y0, pz), 6, "X", 2.2)

	-- The platform.
	local plat = U.model(kit, "Platform")
	-- beside the spot: a tackle box in the base colour (light lid, iron handle) and a stool
	span(plat, "TackleBox", -6.4, -4.2, DECK, DECK + 1.1, sz - 2.7, sz - 1.3, 0, KIT)
	span(plat, "TackleLid", -6.5, -4.1, DECK + 1.1, DECK + 1.4, sz - 2.8, sz - 1.2, 0.35, KIT)
	span(plat, "TackleHandle", -5.7, -4.9, DECK + 1.4, DECK + 1.7, sz - 2.1, sz - 1.9, C.Iron, KIT)
	cylY(plat, "StoolSeat", 1.8, 0.35, at(-8.1, PLANK + 1.75, sz + 1.3), C.WoodLight, KIT)
	span(plat, "StoolLeg", -8.45, -7.75, PLANK, PLANK + 1.6, sz + 0.95, sz + 1.65, C.WoodDark, KIT)
	-- a stack of wicker fish traps in the back-right corner
	local trap, band = P.Straw:Lerp(P.Twine, 0.5), P.Twine:Lerp(C.Ink, 0.3)
	span(plat, "Trap", 16.6, 19.4, DECK, DECK + 1.8, -55.4, -51.6, trap, KIT)
	span(plat, "TrapBand", 16.5, 19.5, DECK + 0.7, DECK + 1.1, -55.5, -51.5, band, KIT)
	span(plat, "Trap", 16.9, 19.1, DECK + 1.8, DECK + 3.3, -55.0, -52.0, P.Straw:Lerp(P.Twine, 0.35), KIT)
	span(plat, "TrapBand", 16.8, 19.2, DECK + 2.3, DECK + 2.7, -55.1, -51.9, band, KIT)
	-- a rope coil by the back kerb, a basket of the catch between the crates and the spot
	cylY(plat, "RopeCoil", 2.4, 0.5, at(12.5, DECK + 0.25, -52.6), C.Rope, KIT)
	cylY(plat, "RopeCoilHole", 1.0, 0.56, at(12.5, DECK + 0.28, -52.6), P.Twine, KIT)
	cylY(plat, "Basket", 2.0, 1.2, at(9.2, DECK + 0.6, -62.4), P.Twine:Lerp(P.Straw, 0.4), KIT)
	cylY(plat, "BasketRim", 2.2, 0.25, at(9.2, DECK + 1.15, -62.4), P.Twine:Lerp(C.Ink, 0.25), KIT)
	make(
		plat,
		"BasketFish",
		Vector3.new(0.45, 0.75, 1.5),
		at(9.0, DECK + 1.55, -62.4) * CFrame.Angles(0, rad(25), rad(10)),
		C.FishSilver,
		KIT
	)
	make(
		plat,
		"BasketFish",
		Vector3.new(0.45, 0.7, 1.35),
		at(9.55, DECK + 1.5, -62.0) * CFrame.Angles(0, rad(-40), rad(-8)),
		C.Orange:Lerp(C.StoneLight, 0.3),
		KIT
	)
	-- a net hung over the right rail to dry, with three floats; three fish drying under the rail
	local rx = PLAT_HALF + 0.6 -- the rail's centre line (x 20.6)
	local net = U.model(plat, "Net")
	span(net, "NetHang", rx + 0.55, rx + 0.85, DECK + 0.75, DECK + 4.1, -66, -59.5, C.NetRope, KIT)
	for i, z in { -65, -62.75, -60.5 } do
		span(
			net,
			"NetFloat",
			rx + 0.8,
			rx + 1.4,
			DECK + 0.6,
			DECK + 1.2,
			z - 0.3,
			z + 0.3,
			if i == 2 then C.White else C.Orange,
			KIT
		)
	end
	sway(net, at(rx + 0.7, DECK + 4.0, -62.75), 3, "Z", 3.2)
	local fish = U.model(plat, "DryingFish")
	for i, z in { -57.5, -56, -54.5 } do
		span(
			fish,
			"DryFish",
			rx - 0.15,
			rx + 0.15,
			DECK + 1.65,
			DECK + 3.15,
			z - 0.4,
			z + 0.4,
			if i == 2 then C.FishSilverDark else C.FishSilver,
			KIT
		)
	end
	sway(fish, at(rx, DECK + 3.2, -56), 6, "Z", 2.4)
	-- a crab pot on a line off the front-right corner (outside the cast clear zone, x > 16)
	span(plat, "PotLine", 17.9, 18.1, waterY + 0.5, DECK + 0.6, pierEnd - 0.3, pierEnd - 0.1, C.Rope, KIT)
	span(
		plat,
		"CrabPot",
		17.0,
		19.0,
		waterY - 0.4,
		waterY + 0.9,
		pierEnd - 1.6,
		pierEnd + 0.2 - 0.6,
		P.Twine:Lerp(P.Straw, 0.3),
		KIT
	)
	-- algae collars at the waterline on the platform's piles
	for _, p in
		{
			{ -PLAT_HALF - 0.6, frontZ },
			{ PLAT_HALF + 0.6, frontZ },
			{ -9, frontZ },
			{ 9, frontZ },
			{ -PLAT_HALF - 0.6, -51.1 },
			{ PLAT_HALF + 0.6, -51.1 },
		}
	do
		span(
			plat,
			"Algae",
			p[1] - 1.15,
			p[1] + 1.15,
			waterY - 0.5,
			waterY + 0.35,
			p[2] - 1.15,
			p[2] + 1.15,
			P.Seaweed:Lerp(C.WoodDark, 0.45),
			KIT
		)
	end
	-- a windsock on the back-right post (striped orange and white, blown inland)
	local sock = U.model(plat, "Windsock")
	local wx, wz, wtop = PLAT_HALF + 0.6, -51.1, DECK + 4.2
	cylY(sock, "SockPole", 0.4, 6.8, at(wx, wtop + 3.4, wz), C.Iron, KIT)
	local wy = wtop + 6.1
	span(sock, "Sock", wx - 0.6, wx + 0.6, wy - 0.6, wy + 0.6, wz + 0.2, wz + 1.6, C.Orange, KIT)
	span(sock, "Sock", wx - 0.5, wx + 0.5, wy - 0.55, wy + 0.45, wz + 1.6, wz + 2.8, C.White, KIT)
	span(sock, "Sock", wx - 0.4, wx + 0.4, wy - 0.5, wy + 0.3, wz + 2.8, wz + 3.9, C.Orange, KIT)
	sock.PrimaryPart = sock:FindFirstChild("SockPole")
	sway(sock, at(wx, wy, wz), 12, "Y", 3.6)
	-- the shelter: a pennant on its roof and a shell wind chime under its front edge
	local roofTop = DECK + 10 + 1.2 + 1.4 + 1.4 + 1.4
	local xc, zc = (PAV_X0 + PAV_X1) / 2, pierEnd + (PAV_Z0 + PAV_Z1) / 2
	span(plat, "RoofMast", xc - 0.15, xc + 0.15, roofTop, roofTop + 3.4, zc - 0.15, zc + 0.15, C.WoodDark, KIT)
	local flag = span(plat, "RoofFlag", xc - 0.05, xc + 0.05, roofTop + 2.1, roofTop + 3.2, zc + 0.15, zc + 2.3, 0, KIT)
	sway(flag, at(xc, roofTop + 2.6, zc + 0.15), 10, "Y", 2.0)
	local chime = U.model(plat, "WindChime")
	local cy, cz = DECK + 10, pierEnd + PAV_Z0 - 0.9 -- (just in front of the front posts)
	span(chime, "ChimeBar", xc - 0.9, xc + 0.9, cy - 0.25, cy, cz - 0.1, cz + 0.1, C.WoodDark, KIT)
	for i, x in { xc - 0.6, xc, xc + 0.6 } do
		local drop = if i == 2 then 1.5 else 1.1
		span(
			chime,
			"Shell",
			x - 0.22,
			x + 0.22,
			cy - drop - 0.5,
			cy - drop,
			cz - 0.22,
			cz + 0.22,
			if i == 2 then P.Pink:Lerp(C.Cream, 0.5) else C.Cream,
			KIT
		)
	end
	sway(chime, at(xc, cy, cz), 7, "X", 1.8)

	-- One of four little scenes per base on the free deck at the front right (x 8..15).
	local scenes = U.model(kit, "Scenes")
	-- 1: crab pots stacked by the rail, a striped buoy lying on its side
	local v1 = variant(scenes, "CrabPots", 1, 4)
	local pot = P.Twine:Lerp(P.Straw, 0.3)
	span(v1, "CrabPot", 10.0, 12.4, DECK, DECK + 1.5, sz - 3.2, sz - 0.8, pot, KIT)
	span(v1, "CrabPotRim", 9.9, 12.5, DECK + 1.2, DECK + 1.5, sz - 3.3, sz - 0.7, band, KIT)
	span(v1, "CrabPot", 10.3, 12.1, DECK + 1.5, DECK + 2.7, sz - 2.9, sz - 1.1, pot, KIT)
	make(
		v1,
		"LyingBuoy",
		Vector3.new(1.8, 1.2, 1.2),
		at(13.6, DECK + 0.6, sz + 0.2) * CFrame.Angles(0, rad(20), 0),
		C.Red,
		merge(KIT, { Shape = Enum.PartType.Cylinder })
	)
	make(
		v1,
		"LyingBuoyBand",
		Vector3.new(0.5, 1.26, 1.26),
		at(13.6, DECK + 0.6, sz + 0.2) * CFrame.Angles(0, rad(20), 0),
		C.White,
		merge(KIT, { Shape = Enum.PartType.Cylinder })
	)
	-- 2: a heap of green net with floats, a float basket
	local v2 = variant(scenes, "NetHeap", 2, 4)
	span(v2, "NetHeap", 9.6, 13.4, DECK, DECK + 0.8, sz - 3.0, sz + 0.2, C.NetRope, KIT)
	span(v2, "NetHeap", 10.2, 12.6, DECK + 0.8, DECK + 1.4, sz - 2.4, sz - 0.4, C.NetRopeLight, KIT)
	span(v2, "NetFloat", 11.0, 11.7, DECK + 1.4, DECK + 2.0, sz - 1.8, sz - 1.1, C.Orange, KIT)
	cylY(v2, "FloatBasket", 1.9, 1.3, at(14.2, DECK + 0.65, sz - 1.4), P.Straw:Lerp(P.Twine, 0.3), KIT)
	make(
		v2,
		"GlassFloat",
		Vector3.new(0.9, 0.9, 0.9),
		at(14.1, DECK + 1.45, sz - 1.3),
		P.Cyan:Lerp(C.White, 0.3),
		merge(KIT, { Shape = Enum.PartType.Ball })
	)
	-- 3: flower boxes on the two front rails (the owner's garden afloat)
	local v3 = variant(scenes, "RailFlowers", 3, 4)
	for i, sx in { -1, 1 } do
		local x, y = sx * 14.8, DECK + 4.0
		span(v3, "RailBox", x - 2.4, x + 2.4, y, y + 0.9, frontZ - 0.55, frontZ + 0.55, C.Wood, KIT)
		span(v3, "RailGreens", x - 2.1, x + 2.1, y + 0.9, y + 1.4, frontZ - 0.4, frontZ + 0.4, C.Leaf2, KIT)
		local pair = JEWELS[i + 2]
		span(v3, "RailBloom", x - 1.3, x - 0.6, y + 1.3, y + 1.85, frontZ - 0.3, frontZ + 0.3, pair[1], KIT)
		span(v3, "RailBloom", x + 0.5, x + 1.2, y + 1.3, y + 1.85, frontZ - 0.3, frontZ + 0.3, pair[2], KIT)
	end
	-- 4: an anchor and a coil of chain by the crates, two oars leaning on them
	local v4 = variant(scenes, "Anchor", 4, 4)
	span(v4, "AnchorShank", 11.6, 12.2, DECK, DECK + 0.4, sz - 3.4, sz + 0.4, C.Iron, KIT)
	span(v4, "AnchorStock", 10.2, 13.6, DECK, DECK + 0.4, sz - 3.0, sz - 2.5, C.Iron:Lerp(C.Ink, 0.25), KIT)
	span(v4, "AnchorFluke", 10.6, 13.2, DECK, DECK + 0.5, sz + 0.3, sz + 0.9, C.Iron, KIT)
	cylY(v4, "Chain", 1.6, 0.45, at(9.6, DECK + 0.22, sz - 0.6), C.Iron:Lerp(C.StoneLight, 0.3), KIT)
	for i, x in { 11.6, 12.9 } do
		make(
			v4,
			"Oar",
			Vector3.new(0.35, 6.2, 0.6),
			at(x, DECK + 2.9, pierEnd + 10.6) * CFrame.Angles(rad(-18 + 4 * i), 0, rad(6 - 6 * i)),
			C.WoodLight,
			KIT
		)
	end
end

--[[
	Yard micro-kit (v3 detail): small finds in the yard's empty corners — a wheelbarrow in the work
	yard, a watering can by the rain barrel, a bird house (its roof in the base colour; no bird) on
	a pole in the -X side strip, stepping stones across the lawn from the garden walk towards the
	net yard and grass tufts at the feet of the fence posts and the new things. All decor (no
	collisions, raycasts, touches or shadows). 25 parts.
]]
local function buildYardDressing(template: any)
	local yard = U.model(template, "YardKit")
	-- the wheelbarrow, resting in the work yard (gravel top TERRACE + 0.3), its handles inland
	local top = TERRACE + 0.3
	span(yard, "BarrowTray", 52.9, 55.1, top + 1.0, top + 1.9, 137.6, 140.6, C.Boat, KIT)
	make(
		yard,
		"BarrowWheel",
		Vector3.new(0.4, 1.3, 1.3),
		at(54, top + 0.65, 137.3),
		C.Ink:Lerp(C.Iron, 0.5),
		merge(KIT, { Shape = Enum.PartType.Cylinder })
	)
	for _, x in { 53.15, 54.85 } do
		span(yard, "BarrowHandle", x - 0.13, x + 0.13, top + 1.35, top + 1.6, 140.4, 143.0, C.WoodLight, KIT)
	end
	span(yard, "BarrowLeg", 53.1, 54.9, top, top + 1.0, 140.2, 140.5, C.WoodDark, KIT)
	-- a watering can by the rain barrel at the garden's end
	span(yard, "WateringCan", -29.6, -28.4, LAWN, LAWN + 1.1, 30.0, 31.2, P.RoofGreen, KIT)
	make(
		yard,
		"CanSpout",
		Vector3.new(1.4, 0.25, 0.25),
		at(-30.1, LAWN + 1.0, 30.6) * CFrame.Angles(0, 0, rad(-35)),
		P.RoofGreen,
		KIT
	)
	span(yard, "CanHandle", -29.1, -28.9, LAWN + 1.1, LAWN + 1.6, 30.2, 31.0, C.Iron, KIT)
	-- a bird house on a pole (an empty one: DESIGN.md §1 — no animals on display)
	span(yard, "BirdPole", -62.2, -61.8, LAWN, LAWN + 6, 103.8, 104.2, C.WoodDark, KIT)
	span(yard, "BirdHouse", -62.8, -61.2, LAWN + 6, LAWN + 7.6, 103.2, 104.8, C.WoodLight, KIT)
	span(yard, "BirdRoof", -63.2, -60.8, LAWN + 7.6, LAWN + 8.1, 102.8, 105.2, ROOF + 0.1, KIT)
	span(yard, "BirdHole", -61.25, -61.15, LAWN + 6.5, LAWN + 7.0, 103.75, 104.25, C.Ink, KIT)
	-- stepping stones from the garden walk towards the net yard
	for i, p in
		{ { -33.5, 40.5, 8 }, { -36.5, 44.5, -12 }, { -38.8, 49.0, 15 }, { -42.5, 51.6, -6 }, { -46.6, 53.6, 10 } }
	do
		make(
			yard,
			"SteppingStone",
			Vector3.new(1.9, 0.3, 1.5),
			at(p[1], LAWN + 0.1, p[2]) * CFrame.Angles(0, rad(p[3]), 0),
			if i % 2 == 0 then C.Flag else C.Limestone,
			KIT
		)
	end
	-- grass tufts at the feet of the front fence posts and of the new things
	local tufts = {
		{ -50.6, 20.6 },
		{ -33.6, 20.6 },
		{ 33.4, 20.6 },
		{ 50.4, 20.6 },
		{ -61.0, 104.9 },
		{ -62.9, 103.0 },
		{ -27.9, 30.0 },
		{ -35.2, 42.6 },
	}
	for i, t in tufts do
		span(
			yard,
			"GrassTuft",
			t[1] - 0.55,
			t[1] + 0.55,
			LAWN - 0.05,
			LAWN + 0.85,
			t[2] - 0.45,
			t[2] + 0.45,
			if i % 2 == 0 then C.Leaf2 else C.Leaf3,
			KIT
		)
	end
end

--[[
	Moving details of the buildings (DESIGN.md §3 "Ambient attributes"), marked after the house is
	scaled: the flag's cloth (its band and tip ride on it) flutters about the mast, the tower's
	pennant about the vane rod, the two gold fish weathervanes (tail riding on the fish) turn to and
	fro about their rods.
]]
local function tagAmbient(template: any)
	local flag = template:FindFirstChild("Flag")
	local cloth = flag and flag:FindFirstChild("Cloth")
	local pole = flag and flag:FindFirstChild("Pole")
	if cloth and pole then
		for _, name in { "ClothBand", "ClothTip" } do
			local part = flag:FindFirstChild(name)
			if part then
				part.Parent = cloth
			end
		end
		local edge = cloth.CFrame * Vector3.new(-cloth.Size.X / 2, 0, 0)
		sway(cloth, CFrame.new(edge), 7, "Y", 2.6)
	end
	for _, holder in { template:FindFirstChild("Gate"), template:FindFirstChild("House") } do
		local rod = holder and holder:FindFirstChild("VaneRod")
		if not rod then
			continue
		end
		local r = rod.CFrame.Position
		local fish, tail = holder:FindFirstChild("VaneFish"), holder:FindFirstChild("VaneTail")
		if fish then
			if tail then
				tail.Parent = fish
			end
			sway(fish, CFrame.new(r.X, fish.CFrame.Position.Y, r.Z), 25, "Y", 7)
		end
		local pennant = holder:FindFirstChild("Pennant")
		if pennant then
			sway(pennant, CFrame.new(r.X, pennant.CFrame.Position.Y, r.Z), 12, "Y", 2.2)
		end
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
	plankTone = 0

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
	buildFountain(template)
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
	buildBoatRepair(template)
	buildTrees(template)
	local lastPostZ = buildPier(template, pierEnd, pileBottom)
	buildPavilion(template, pierEnd)
	buildPierProps(template, pierEnd)
	buildPierDressing(template, pierEnd, waterY, lastPostZ)
	buildYardDressing(template)
	tagAmbient(template)
	buildBoat(template, waterY, lastPostZ)
	-- Everything the client moves (the boat's Bob, the Sway details) neither collides nor takes
	-- raycasts or touches (Movers.luau).
	Movers.quiet(template)

	local count = 0
	for _, d in template:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	assert(count == U.partCount - partsBefore, "BaseTemplate: parts created outside Util.part")
	-- parts of one base at runtime (the variants of the other bases dropped): the biggest of the 8
	local perBase = 0
	for index = 1, mapCfg.BaseCount or 8 do
		local n = 0
		for _, d in template:GetDescendants() do
			if d:IsA("BasePart") and not droppedOn(d, template, index) then
				n += 1
			end
		end
		perBase = math.max(perBase, n)
	end
	assert(perBase <= BUDGET, `BaseTemplate: {perBase} parts per base, budget {BUDGET}`)
	assert(count <= TEMPLATE_BUDGET, `BaseTemplate: {count} parts with every variant, budget {TEMPLATE_BUDGET}`)

	table.insert(expected, { root = "template", path = { "Flag", "Pole", "SignAttachment" }, offset = signOffset })
	table.insert(
		expected,
		{ root = "template", path = { "House", "ChimneyCap", "SmokeAttachment" }, offset = smokeOffset }
	)
	table.insert(
		expected,
		{ root = "template", path = { "Smokehouse", "ChimneyCap", "SmokeAttachment" }, offset = shedSmokeOffset }
	)
	return {
		template = template,
		partCount = count, -- with every variant
		perBaseParts = perBase, -- one base at runtime (the biggest of the 8)
		budget = BUDGET,
		-- Verified by the post-build self-check in tools/build.luau (path from the template root).
		expectedAttachments = expected,
	}
end
