--[[
	Props — the voxel prop library of World v3 (style contract: tools/builder/DESIGN.md §1).

	Every prop is built from chunky, axis-aligned blocks in bright saturated colours with
	2-3 shades of one hue ("voxel shading": dark undersides / mid bodies / light tops),
	SmoothPlastic everywhere, Neon for glowing accents. Cylinders only for thin round things
	(poles, barrels), balls nowhere. Thousands of props are scattered over the map, so every
	prop is lean: the part budget is noted next to each constructor.

	Calling convention (all small props):
		Props.<name>(parent, cframe, opts?) -> Model
	  cframe  ground point + facing: the prop stands on cframe.Position, its front is
	          cframe.LookVector (local -Z). Boats, buoys, lily pads, whales, arches: cframe.Position
	          is on the water surface. Floating things (cloud, hotAirBalloon): their bottom.
	  opts    optional table:
	          seed     number, deterministic variation (default: hashed from the position)
	          scale    uniform size multiplier (default 1)
	          variant  some props have named/numbered variants (see each constructor)
	          name     Model name override
	          lite     trees only: fewer parts for background forests (oak/cherry/autumn/round
	                   8, birch 8, pine 8-10, palm 10)
	          compact  broadleaf trees: dark/light canopy layers as single blocks (-2 parts)
	          colour overrides: see each constructor (color, leaves, trunk, ...)
	The returned Model has PrimaryPart set to its main part, and PrimaryPart.PivotOffset is set so
	that the model pivot is exactly `cframe` (Model:PivotTo(newGroundCFrame) works at runtime).

	Big pieces take explicit points instead:
		Props.bridge(parent, fromPos, toPos, opts)            deck top at opts.deckY
		Props.waterfall(parent, topPos, bottomPos, width, opts)
		Props.bunting(parent, a, b, opts)                     flags on a sagging rope
		Props.fenceLine(parent, points, opts)                 fence along a polyline

	Catalogue (parts per instance):
	  trees      oakTree 13-16, roundTree 13-16, cherryTree 15, autumnTree 15,
	             birchTree 12, pineTree 11-14, palmTree 16, giantTree 101 (landmark)
	  plants     bush 4-7, flowerPatch 12, mushroom 7, giantMushroom 14-16, lilyPad 2-4,
	             reeds 7, stump 4-6, log 3, flowerClump 3, berryBush 3 (cheap decor)
	  rocks      rock 1-4 (3-4 by default), boulder 5-6, rockPair 3, crystalCluster 10,
	             rockArch 23-33
	  furniture  lampPost 7, doubleLamp 12, torch 4, bench 8, picnicTable 10, crate 4,
	             crateStack 12, barrel 4, hayBale 3, fenceSegment <= 12, fenceLine, signpost 4-5,
	             billboard 9, flowerBox 7, planter 6-8, bunting <= 16, flagPole 6, campfire 10,
	             parasol 6, beachChair 7, cooler 4, treasureChest 7-9, anchor 10,
	             fishStatue 18, lifebuoy 4, fishingRodRack 11
	  water      rowboat 14, sailboat 21, motorboat 17, buoy 4, dockSegment 9-11, shipwreck 63,
	             whale 44
	  big        bridge (~8 per 10 studs + ~30), waterfall 12-22, lighthouse 28, windmill 40
	             (spinning "Blades"), watchtower 43, ferrisWheel 105 (spinning "Wheel"),
	             hotAirBalloon 19, cloud 7-8
	  helpers    Props.Colors (shared palette, DESIGN.md §1 names), Props.makeRng(seed),
	             Props.shade(c, f), Props.lerpColor(a, b, t), Props.tones(c) -> {dark, mid, light},
	             Props.groundAt = function(x, z) -> y (optional ground probe, see broadleaf),
	             Props.waterTop (water level, default 0: boats/buoys on it bob),
	             Props.fx(partOrAttachment, kind, opts) / Props.fxAt(part, worldCFrame, kind, opts)
	             -> ParticleEmitter (smoke, spray, foam, mist, sparkle, fireflies, bubbles, petals,
	             embers, flame; see "Particle effects")

	Spinning parts: windmill, ferrisWheel and lighthouse put the moving geometry in a child Model
	("Blades", "Wheel", "Beacon") with a number attribute Spin (degrees per second). Its pivot is
	the hub; the spin axis is the pivot's LookVector. A client script can do
	    model:PivotTo(model:GetPivot() * CFrame.Angles(0, 0, math.rad(spin * dt))).
	Ferris-wheel gondolas are Models with attribute KeepUpright = true (re-level them after
	turning the wheel). Every part of a spinning group has CanCollide = CanQuery = CanTouch =
	false: only the client moves it, so it must never shove a player.
	Bobbing: rowboat, sailboat, motorboat and buoy standing on the water get the Model attributes
	Bob (amplitude) and BobPeriod; the client (AmbientController) lifts and rolls them gently.
	Particles (no parts): campfire embers + smoke, crystal glints, glowing giant mushrooms' and
	the giant tree's fireflies, its blossom petals, the whale's spout spray, the balloon burner
	flame, the open treasure chest's glints, the waterfall's mist and foam.

	No randomness from math.random: variation comes from a small Park–Miller generator seeded
	by opts.seed or by the position, so rebuilding the place gives identical output.
	Foliage and tiny details have CanCollide = CastShadow = CanQuery = false, except the biggest
	canopy / frond blocks of each tree, which cast the tree's shadow. PointLights (Range
	<= 16, no shadows) only where documented: lamps/torches/campfires with opts.light, crystals
	with opts.light, the lighthouse, glowing giant mushrooms, some bridge lanterns and the room
	lanterns of the windmill and the treehouse.
	Every prop runs a z-fight guard when finished (see deconflict below): coplanar faces of
	differently coloured overlapping blocks are nudged apart by 0.1 stud.
]]

local U = require("./Util")

local Enum = U.Enum
local Vector3 = U.Vector3
local CFrame = U.CFrame
local Color3 = U.Color3
local rgb = U.rgb
local Mat = Enum.Material
local roblox = U.roblox

local Props = {}

-- Optional ground probe function(x, z) -> top y of the ground (e.g. VoxelWorld:heightAt), set
-- once by the map builder: trees then drop fallen-leaf litter that would hang over a step.
Props.groundAt = nil :: ((number, number) -> number)?

-- World water level (DESIGN.md WaterTop): boats and buoys standing on it bob (see bobbing below).
Props.waterTop = 0

--------------------------------------------------------------------------------------------
-- Palette (DESIGN.md §1 names first; extra shades and legacy names below)
--------------------------------------------------------------------------------------------

local C: { [string]: any } = {
	GrassTop = rgb(124, 222, 66), -- the ground's grass caps (Ground.luau)
	GrassTop2 = rgb(106, 206, 56),
	GrassTop3 = rgb(146, 234, 82),
	Dirt = rgb(170, 116, 70),
	DirtDark = rgb(136, 90, 56),
	Sand = rgb(255, 228, 152),
	SandDark = rgb(236, 200, 124),
	SandWet = rgb(240, 212, 140),
	Stone = rgb(158, 166, 180),
	StoneDark = rgb(120, 128, 144),
	StoneLight = rgb(196, 202, 212),
	Snow = rgb(248, 252, 255),
	Wood = rgb(204, 138, 78),
	WoodDark = rgb(150, 94, 52),
	WoodLight = rgb(236, 184, 120),
	-- foliage: bright candy greens (hue ~115-128°, the grass is ~100°), a step darker and less
	-- yellow than the grass, so trees, hedges and bushes stand out against the lawns and hills
	-- without reading as dark teal blobs (only the small tips/caps get close to the grass)
	Leaf1 = rgb(58, 166, 64),
	Leaf2 = rgb(84, 194, 76),
	Leaf3 = rgb(116, 216, 98),
	Pine1 = rgb(36, 140, 84),
	Pine2 = rgb(50, 166, 96),
	Pine3 = rgb(76, 192, 110),
	Blossom1 = rgb(255, 150, 200),
	Blossom2 = rgb(255, 190, 225),
	Autumn1 = rgb(255, 150, 40),
	Autumn2 = rgb(255, 196, 60),
	Red = rgb(255, 72, 72),
	Orange = rgb(255, 148, 40),
	Yellow = rgb(255, 212, 50),
	Lime = rgb(156, 236, 60),
	Cyan = rgb(40, 216, 224),
	Blue = rgb(64, 150, 255),
	Purple = rgb(168, 96, 255),
	Pink = rgb(255, 104, 184),
	White = rgb(252, 252, 250),
	Cream = rgb(255, 244, 220),
	Glass = rgb(150, 230, 255),

	-- extra shades
	Leaf0 = rgb(46, 146, 56), -- deepest foliage shade (undersides)
	LeafLight = rgb(150, 228, 112), -- sunlit tips (small pieces only)
	Mint1 = rgb(44, 164, 92), -- jade broadleaf variety (a touch cooler than Leaf)
	Mint2 = rgb(72, 198, 112),
	Mint3 = rgb(136, 228, 150),
	BirchLeaf1 = rgb(60, 166, 70), -- fresh but still darker than the grass
	BirchLeaf2 = rgb(92, 196, 84),
	BirchLeaf3 = rgb(140, 222, 112),
	Pine0 = rgb(32, 132, 80), -- conifers (Pine0-3) are the only cool, deep greens
	PineLight = rgb(112, 206, 124), -- young fir tips
	Blossom0 = rgb(240, 110, 172), -- deep pink (undersides)
	Autumn0 = rgb(240, 96, 40), -- red-orange (undersides)
	Palm1 = rgb(40, 164, 72),
	Palm2 = rgb(70, 196, 80),
	Palm3 = rgb(124, 224, 100),
	Bark = rgb(164, 104, 60),
	BarkDark = rgb(124, 78, 46),
	CutWood = rgb(255, 214, 150), -- fresh cut faces of stumps/logs
	PalmBark = rgb(224, 172, 104),
	PalmBarkDark = rgb(186, 132, 78),
	Birch = rgb(250, 248, 238),
	BirchDark = rgb(64, 60, 64),
	Coconut = rgb(138, 88, 48),
	Gold = rgb(255, 200, 40),
	GoldLight = rgb(255, 234, 120),
	Iron = rgb(86, 100, 128), -- metal details (small)
	Navy = rgb(44, 64, 116), -- dark contrast trims (small)
	Dark = rgb(36, 36, 48), -- eyes, pupils, outlines
	WindowBlue = rgb(70, 140, 230),
	Glow = rgb(255, 226, 120), -- lantern cores (Neon)
	LightColor = rgb(255, 210, 140), -- PointLight colour
	Flame = rgb(255, 120, 30),
	FlameCore = rgb(255, 222, 70),
	Water = rgb(60, 170, 240),
	WaterLight = rgb(140, 220, 255),
	Foam = rgb(240, 252, 255),
	Sail = rgb(255, 252, 244),
	Rope = rgb(236, 210, 150),
	Canvas = rgb(250, 236, 200),
	CloudShade = rgb(222, 236, 252),
	Seaweed = rgb(70, 190, 110),
	-- rocks and boulders: a light lavender grey (lighter and softer than the cliff Stone), so a
	-- rock on a lime lawn reads as a bright voxel boulder under its moss cap, not a concrete block
	RockDark = rgb(156, 156, 180),
	RockMid = rgb(190, 190, 204),
	RockLight = rgb(222, 222, 234),
	Straw = rgb(244, 202, 86), -- hay bales
	StrawLight = rgb(255, 230, 138),
	Twine = rgb(190, 122, 58),

	-- lists
	Flowers = {
		rgb(255, 72, 72), -- red
		rgb(255, 212, 50), -- yellow
		rgb(255, 104, 184), -- pink
		rgb(168, 96, 255), -- violet
		rgb(252, 252, 250), -- white
		rgb(255, 148, 40), -- orange
		rgb(64, 150, 255), -- blue
	},
	BoatPaint = {
		rgb(255, 72, 72), -- red
		rgb(40, 200, 210), -- teal
		rgb(64, 150, 255), -- blue
		rgb(255, 200, 50), -- yellow
		rgb(252, 252, 250), -- white
		rgb(88, 204, 72), -- green
		rgb(255, 104, 184), -- pink
	},
	Festive = { -- bunting / flags / gondolas, rainbow order
		rgb(255, 72, 72),
		rgb(255, 148, 40),
		rgb(255, 212, 50),
		rgb(88, 204, 72),
		rgb(40, 216, 224),
		rgb(64, 150, 255),
		rgb(168, 96, 255),
		rgb(255, 104, 184),
	},
}

-- Legacy (World v2) names, mapped onto the v3 palette so old callers keep working.
C.Leaves = { C.Leaf1, C.Leaf2, C.Leaf3 }
C.PineLeaves = { C.Pine0, C.Pine1, C.Pine2, C.Pine3 }
C.AutumnLeaves = { C.Autumn0, C.Autumn1, C.Autumn2 }
C.BlossomLeaves = { C.Blossom0, C.Blossom1, C.Blossom2 }
C.LimeLeaves = { C.Leaf2, C.Lime, C.LeafLight }
C.PalmLeaves = { C.Palm1, C.Palm2, C.Palm3 }
C.BushLeaves = { C.Leaf0, C.Leaf1, C.Leaf2 }
C.Grass = C.GrassTop
C.GrassDark = C.GrassTop2
C.Rock = { C.RockDark, C.RockMid, C.RockMid, C.RockLight }
C.Moss = C.Leaf2 -- rock and boulder caps: a step darker than the lawns they stand on
C.Soil = C.DirtDark
C.WoodDeep = C.BarkDark
C.RoofRed = rgb(240, 76, 64)
C.RoofBlue = rgb(64, 132, 240)
C.RoofGreen = rgb(72, 180, 96)
C.Plaster = C.Cream
C.Metal = C.Iron

Props.Colors = C

--------------------------------------------------------------------------------------------
-- Deterministic randomness and colour helpers
--------------------------------------------------------------------------------------------

-- Park–Miller "minimal standard" generator. Products stay < 2^53, so it is exact in doubles.
local function makeRng(seed: number): () -> number
	local s = math.floor(math.abs(seed)) % 2147483646 + 1
	local function nextValue(): number
		s = (s * 16807) % 2147483647
		return (s - 1) / 2147483646
	end
	nextValue()
	nextValue()
	return nextValue
end
Props.makeRng = makeRng

-- Seed from a position (so identical calls at different places differ).
local function positionSeed(p: any, salt: number): number
	local x = math.floor(p.X * 4 + 0.5)
	local y = math.floor(p.Y * 4 + 0.5)
	local z = math.floor(p.Z * 4 + 0.5)
	return (x * 73856 + y * 19349 + z * 83492 + salt * 7919) % 2147483646
end

local function lerpColor(a: any, b: any, t: number): any
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
Props.lerpColor = lerpColor

local function shade(c: any, f: number): any
	return Color3.new(math.clamp(c.R * f, 0, 1), math.clamp(c.G * f, 0, 1), math.clamp(c.B * f, 0, 1))
end
Props.shade = shade

-- Three shades of one colour for voxel shading: { dark, mid, light }.
local function tones(c: any): { any }
	return { shade(c, 0.8), c, lerpColor(c, C.White, 0.3) }
end
Props.tones = tones

--------------------------------------------------------------------------------------------
-- Geometry helpers
--------------------------------------------------------------------------------------------

local UP = Vector3.new(0, 1, 0)
local RAD = math.rad

local function rot(x: number, y: number, z: number): any
	return CFrame.Angles(RAD(x), RAD(y), RAD(z))
end

-- CFrame at pos whose local +Z points along zDir (for blocks between two points).
local function frameZ(pos: any, zDir: any, upHint: any?): any
	local z = zDir.Unit
	local up = upHint or UP
	if math.abs(z:Dot(up.Unit)) > 0.98 then
		up = Vector3.new(1, 0, 0)
	end
	local x = up:Cross(z).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(pos, x, y, z)
end

local function merge(a: { [string]: any }?, b: { [string]: any }?): { [string]: any }
	local out = {}
	if a then
		for k, v in a do
			out[k] = v
		end
	end
	if b then
		for k, v in b do
			out[k] = v
		end
	end
	return out
end

-- Common property sets (passed as `extra`; Material in extra overrides SmoothPlastic).
local DECOR = { CanCollide = false, CastShadow = false, CanQuery = false } -- tiny, non-walkable details
local FOLIAGE = DECOR -- leaves, petals, sails, flags
-- the biggest canopy / frond blocks of a tree: still not walkable, but they cast the shadow that
-- grounds the tree (one or two parts per tree, cheap with ShadowMap lighting)
local FOLIAGE_SHADOW = { CanCollide = false, CastShadow = true, CanQuery = false }
local NOSHADOW = { CastShadow = false }
local NEON = { Material = Mat.Neon, CastShadow = false }
local NEON_DECOR = merge(DECOR, { Material = Mat.Neon })

--------------------------------------------------------------------------------------------
-- Build context: every prop is built in its own local frame (y = 0 is the ground, -Z is the
-- front) and in unscaled studs; the context applies scale and the world frame.
--------------------------------------------------------------------------------------------

local Ctx = {}
Ctx.__index = Ctx

local function begin(parent: any, name: string, cf: any, opts: { [string]: any }?, salt: number): any
	local o = opts or {}
	local self = setmetatable({}, Ctx)
	self.opts = o
	self.pivot = cf
	self.cf = cf
	self.s = o.scale or 1
	self.rand = makeRng(o.seed and (o.seed * 7 + salt * 104729) or positionSeed(cf.Position, salt))
	self.model = U.model(parent, o.name or name)
	self.target = self.model -- where new parts go (child Models for spinning groups)
	return self
end

function Ctx:range(a: number, b: number): number
	return a + (b - a) * self.rand()
end

function Ctx:int(a: number, b: number): number
	return math.min(b, a + math.floor(self.rand() * (b - a + 1)))
end

function Ctx:pick(list: { any }): any
	return list[math.min(#list, 1 + math.floor(self.rand() * #list))]
end

function Ctx:chance(p: number): boolean
	return self.rand() < p
end

-- Local (unscaled) CFrame -> CFrame relative to self.cf with the scale applied.
function Ctx:scaled(lcf: any): any
	if self.s == 1 then
		return lcf
	end
	return CFrame.new(lcf.Position * self.s) * lcf.Rotation
end

-- Local (unscaled) CFrame -> world CFrame.
function Ctx:world(lcf: any): any
	return self.cf * self:scaled(lcf)
end

function Ctx:worldPoint(p: any): any
	return self.cf * (p * self.s)
end

-- Builds the following parts in a sub-frame (local lcf); returns the frame to restore.
function Ctx:push(lcf: any): any
	local old = self.cf
	self.cf = self.cf * self:scaled(lcf)
	return old
end

function Ctx:pop(old: any)
	self.cf = old
end

-- Following parts go into a child Model `name` (until ungroup()).
function Ctx:group(name: string): any
	local m = U.model(self.model, name)
	self.target = m
	return m
end

function Ctx:ungroup()
	self.target = self.model
end

-- Sets a child model's PrimaryPart and makes its pivot the local CFrame `pivotLocal`.
function Ctx:finishGroup(m: any, primary: any, pivotLocal: any)
	m.PrimaryPart = primary
	primary.PivotOffset = primary.CFrame:Inverse() * self:world(pivotLocal)
end

function Ctx:_add(className: string, name: string, size: any, lcf: any, color: any, material: any?, extra: any?): any
	local props = merge({
		Name = name,
		Size = size * self.s,
		CFrame = self:world(lcf),
		Color = color,
		Material = material or Mat.SmoothPlastic,
		Anchored = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		CanTouch = false,
	}, extra)
	U.partCount += 1
	return U.new(className, props, self.target)
end

-- Axis-aligned block centred at (x, y, z) with size (sx, sy, sz) — the voxel workhorse.
function Ctx:vox(
	name: string,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	color: any,
	extra: any?
): any
	return self:_add("Part", name, Vector3.new(sx, sy, sz), CFrame.new(x, y, z), color, nil, extra)
end

-- Axis-aligned block between two corners (any order).
function Ctx:span(
	name: string,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	color: any,
	extra: any?
): any
	return self:vox(
		name,
		(x0 + x1) / 2,
		(y0 + y1) / 2,
		(z0 + z1) / 2,
		math.abs(x1 - x0),
		math.abs(y1 - y0),
		math.abs(z1 - z0),
		color,
		extra
	)
end

-- Block with an explicit local CFrame (rotated pieces of rotating groups, ropes).
function Ctx:block(name: string, size: any, lcf: any, color: any, material: any?, extra: any?): any
	return self:_add("Part", name, size, lcf, color, material, extra)
end

-- Cylinder with its axis along local X of lcf (thin round things only).
function Ctx:cyl(name: string, d: number, len: number, lcf: any, color: any, material: any?, extra: any?): any
	return self:_add(
		"Part",
		name,
		Vector3.new(len, d, d),
		lcf,
		color,
		material,
		merge({ Shape = Enum.PartType.Cylinder }, extra)
	)
end

-- Upright cylinder from y0 to y1 at (x, z).
function Ctx:column(
	name: string,
	d: number,
	x: number,
	z: number,
	y0: number,
	y1: number,
	color: any,
	material: any?,
	extra: any?
): any
	return self:cyl(name, d, y1 - y0, CFrame.new(x, (y0 + y1) / 2, z) * rot(0, 0, 90), color, material, extra)
end

-- Block between two local points (length along the segment), w across, h "up".
function Ctx:beam(name: string, a: any, b: any, w: number, h: number, color: any, extra: any?, upHint: any?): any
	local dir = b - a
	return self:block(name, Vector3.new(w, h, dir.Magnitude), frameZ((a + b) / 2, dir, upHint), color, nil, extra)
end

--[[
	Invisible climbable TrussPart (the Humanoid climbs it; the visible ladder is decoration).
	Roblox snaps truss sizes to 2-stud steps, so its world size is exactly 2 x 2n x 2 whatever
	the prop's scale: (x, z) = local centre of the footprint, from local y0 up to at least y1.
]]
function Ctx:truss(name: string, x: number, z: number, y0: number, y1: number): any
	local s = self.s
	local len = math.max(2, math.ceil((y1 - y0) * s / 2 - 1e-6) * 2)
	return self:_add(
		"TrussPart",
		name,
		Vector3.new(2 / s, len / s, 2 / s),
		CFrame.new(x, y0 + len / s / 2, z),
		C.Wood,
		nil,
		{ Transparency = 1, CastShadow = false }
	)
end

-- "Plus" shaped pair of blocks: a rounded-corner voxel slab (canopies, balloon, tiers).
-- (x, z) centre, y0..y1 height, w = full width, k = how much the corners are cut (0..1).
function Ctx:cross(
	name: string,
	x: number,
	y0: number,
	z: number,
	y1: number,
	wx: number,
	wz: number,
	k: number,
	color: any,
	extra: any?
): any
	local a = self:span(name, x - wx / 2, y0, z - wz * k / 2, x + wx / 2, y1, z + wz * k / 2, color, extra)
	-- the second block is a hair taller so the two never share a top/bottom plane
	self:span(name .. "B", x - wx * k / 2, y0 - 0.04, z - wz / 2, x + wx * k / 2, y1 + 0.04, z + wz / 2, color, extra)
	return a
end

--[[
	Z-fight guard: overlapping blocks of one prop that share a face plane pointing the same way
	and look different (colour / material / transparency) flicker in Roblox. Random jitter makes
	such coincidences rare but not impossible, so after building, the shared face of the smaller
	block of every such pair is pushed 0.1 stud outwards (the block grows on that side only, so
	it never starts overlapping its other neighbours). Only blocks axis-aligned with `frame` are
	checked (rotating groups are skipped); contacts thinner than 0.12 stud are ignored; the
	PrimaryPart of a child model (spinning group hub, gondola pin) is never moved.
]]
local NUDGE = 0.1
local TOUCH = 0.07 -- faces closer than this count as coplanar
local MIN_OVERLAP = 0.12
local function deconflict(model: any, frame: any)
	local boxes = {}
	for _, p in model:GetDescendants() do
		if p.ClassName == "Part" and p.Shape == Enum.PartType.Block then
			local c = { frame:ToObjectSpace(p.CFrame):GetComponents() }
			-- c[4 + 3i + j] = component of the part's axis j along the frame's axis i
			local axisOf, signOf = {}, {}
			local aligned = true
			for i = 0, 2 do
				for j = 0, 2 do
					local v = c[4 + i * 3 + j]
					if math.abs(math.abs(v) - 1) < 1e-3 then
						axisOf[i + 1] = j + 1
						signOf[i + 1] = if v > 0 then 1 else -1
					end
				end
				if not axisOf[i + 1] then
					aligned = false
					break
				end
			end
			if aligned then
				local size = p.Size
				local sz = { size.X, size.Y, size.Z }
				local lo, hi = {}, {}
				for i = 1, 3 do
					local h = sz[axisOf[i]] / 2
					lo[i], hi[i] = c[i] - h, c[i] + h
				end
				table.insert(boxes, {
					part = p,
					lo = lo, -- extents along the frame axes
					hi = hi,
					axisOf = axisOf, -- frame axis i -> part size component
					signOf = signOf, -- +1 when that part axis points along +frame axis i
					volume = sz[1] * sz[2] * sz[3],
					look = `{p.Color}|{p.Material}|{p.Transparency}`,
					pinned = p.Parent ~= model and p.Parent.PrimaryPart == p,
				})
			end
		end
	end
	-- grows bx by NUDGE on its `dir` (-1 = min, +1 = max) face along frame axis i
	local function push(bx: any, i: number, dir: number)
		local a = bx.axisOf[i]
		local unit = Vector3.new(if a == 1 then 1 else 0, if a == 2 then 1 else 0, if a == 3 then 1 else 0)
		bx.part.Size += unit * NUDGE
		bx.part.CFrame *= CFrame.new(unit * (NUDGE / 2 * dir * bx.signOf[i]))
		if dir > 0 then
			bx.hi[i] += NUDGE
		else
			bx.lo[i] -= NUDGE
		end
	end
	-- a push can create a new coincidence further along, so repeat a few passes
	for _ = 1, 4 do
		local pushed = false
		for a = 1, #boxes do
			local A = boxes[a]
			local alo, ahi = A.lo, A.hi
			for b = a + 1, #boxes do
				local B = boxes[b]
				local blo, bhi = B.lo, B.hi
				-- only overlapping boxes that look different can z-fight
				if
					A.look ~= B.look
					and math.min(ahi[1], bhi[1]) - math.max(alo[1], blo[1]) > -TOUCH
					and math.min(ahi[2], bhi[2]) - math.max(alo[2], blo[2]) > -TOUCH
					and math.min(ahi[3], bhi[3]) - math.max(alo[3], blo[3]) > -TOUCH
				then
					for i = 1, 3 do
						local j, k = i % 3 + 1, (i + 1) % 3 + 1
						local overlapJ = math.min(ahi[j], bhi[j]) - math.max(alo[j], blo[j])
						local overlapK = math.min(ahi[k], bhi[k]) - math.max(alo[k], blo[k])
						if overlapJ > MIN_OVERLAP and overlapK > MIN_OVERLAP then
							-- push the smaller block, but never a child model's PrimaryPart (its
							-- pivot is already set)
							local small = if A.volume < B.volume then A else B
							if small.pinned then
								small = if small == A then B else A
							end
							if not small.pinned and math.abs(alo[i] - blo[i]) < TOUCH then
								push(small, i, -1)
								pushed = true
							end
							if not small.pinned and math.abs(ahi[i] - bhi[i]) < TOUCH then
								push(small, i, 1)
								pushed = true
							end
						end
					end
				end
			end
		end
		if not pushed then
			break
		end
	end
end

-- Sets PrimaryPart + PivotOffset so the model pivot is the prop's ground CFrame (and runs the
-- z-fight guard).
function Ctx:finish(primary: any): any
	local model = self.model
	deconflict(model, self.pivot)
	model.PrimaryPart = primary
	primary.PivotOffset = primary.CFrame:Inverse() * self.pivot
	return model
end

local function light(parentPart: any, range: number, brightness: number?, color: any?)
	return U.new("PointLight", {
		Name = "Light",
		Range = math.min(range, 16),
		Brightness = brightness or 1.6,
		Color = color or C.LightColor,
		Shadows = false,
	}, parentPart)
end

--[[
	Particle effects (ParticleEmitters cost no parts). Props.fx(parent, kind, opts?) adds a tuned
	emitter to `parent`: a BasePart (particles start anywhere in the part, moving along
	opts.direction, default Top) or an Attachment (they start at that point; use Props.fxAt to
	make one at a world point). Rates stay low for phones. Voxel kinds use square particles (no
	texture); smoke and mist use the soft built-in smoke puff, sparkles the built-in star.
	kinds:
	  smoke      soft white-grey puffs drifting up and downwind (chimneys, campfires)   rate 2
	  spray      water droplets shot up that fall back (fountains, spouts, whales)      rate 16
	  foam       white cubes churning at a waterline (falls, rapids, splashes)          rate 8
	  mist       big soft white puffs (the foot of a waterfall)                         rate 5
	  sparkle    glinting stars (gold, crystals, magic)                                 rate 3
	  fireflies  tiny glowing yellow-green squares wandering slowly                     rate 2
	  bubbles    small light-blue squares rising straight up (aquariums, ponds)        rate 4
	  petals     pink squares tumbling down on the wind (blossom trees, flower hills)    rate 3
	  embers     tiny glowing orange squares rising from a fire                         rate 4
	  flame      a short flickering burner flame (balloon burners, braziers)            rate 10
	opts: rate, size (multiplies the sizes), speed (NumberRange or number), lifetime (NumberRange),
	color (Color3 or ColorSequence), spread (degrees), accel (Vector3), direction (NormalId),
	lightEmission, name. Returns the ParticleEmitter.
]]
local NR, NS, NSK, CS = roblox.NumberRange, roblox.NumberSequence, roblox.NumberSequenceKeypoint, roblox.ColorSequence
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_SQUARE = "" -- no texture: Roblox draws plain square particles (the voxel look)

local function seq(points: { { number } }, k: number?): any
	local out = {}
	for _, p in points do
		table.insert(out, NSK.new(p[1], p[2] * (k or 1)))
	end
	return NS.new(out)
end

local FX = {
	smoke = {
		Texture = TEX_SMOKE,
		Rate = 2,
		Lifetime = NR.new(4, 6),
		Speed = NR.new(2, 3.5),
		Spread = 12,
		Size = { { 0, 1.6 }, { 1, 5.5 } },
		Transparency = { { 0, 0.35 }, { 0.7, 0.75 }, { 1, 1 } },
		Color = CS.new(rgb(250, 250, 252), rgb(214, 218, 228)),
		Acceleration = Vector3.new(0.9, 0.25, 0.35),
		Drag = 0.3,
		RotSpeed = NR.new(-25, 25),
		Rotation = NR.new(0, 360),
	},
	spray = {
		Texture = TEX_SQUARE,
		Rate = 16,
		Lifetime = NR.new(0.7, 1.0),
		Speed = NR.new(10, 14),
		Spread = 12,
		Size = { { 0, 0.7 }, { 1, 0.25 } },
		Transparency = { { 0, 0.05 }, { 0.8, 0.3 }, { 1, 1 } },
		Color = CS.new(C.Foam, rgb(160, 228, 255)),
		Acceleration = Vector3.new(0, -30, 0),
		RotSpeed = NR.new(-90, 90),
		Rotation = NR.new(0, 90),
		LightEmission = 0.2,
	},
	foam = {
		Texture = TEX_SQUARE,
		Rate = 8,
		Lifetime = NR.new(0.8, 1.4),
		Speed = NR.new(2.5, 4.5),
		Spread = 55,
		Size = { { 0, 1.1 }, { 1, 0.3 } },
		Transparency = { { 0, 0.1 }, { 0.7, 0.35 }, { 1, 1 } },
		Color = CS.new(C.White, C.Foam),
		Acceleration = Vector3.new(0, -7, 0),
		RotSpeed = NR.new(-60, 60),
		Rotation = NR.new(0, 90),
		LightEmission = 0.15,
	},
	mist = {
		Texture = TEX_SMOKE,
		Rate = 5,
		Lifetime = NR.new(1.8, 2.8),
		Speed = NR.new(2, 4.5),
		Spread = 50,
		Size = { { 0, 3 }, { 1, 6.5 } },
		Transparency = { { 0, 0.5 }, { 1, 1 } },
		Color = CS.new(rgb(236, 250, 255)),
		Acceleration = Vector3.new(0, 1.8, 0),
		RotSpeed = NR.new(-15, 15),
		Rotation = NR.new(0, 360),
		LightEmission = 0.1,
	},
	sparkle = {
		Texture = TEX_SPARKLE,
		Rate = 3,
		Lifetime = NR.new(0.8, 1.4),
		Speed = NR.new(0.4, 1.4),
		Spread = 180,
		Size = { { 0, 0.2 }, { 0.3, 1.1 }, { 1, 0 } },
		Transparency = { { 0, 0 }, { 1, 0.4 } },
		Color = CS.new(rgb(255, 246, 180), C.Gold),
		RotSpeed = NR.new(-120, 120),
		Rotation = NR.new(0, 360),
		LightEmission = 1,
	},
	fireflies = {
		Texture = TEX_SQUARE,
		Rate = 2,
		Lifetime = NR.new(4, 6.5),
		Speed = NR.new(0.4, 1.0),
		Spread = 180,
		Size = { { 0, 0 }, { 0.15, 0.4 }, { 0.85, 0.4 }, { 1, 0 } },
		Transparency = { { 0, 0 }, { 0.5, 0.3 }, { 1, 0 } },
		Color = CS.new(rgb(230, 255, 130), rgb(170, 255, 110)),
		Acceleration = Vector3.new(0, 0.15, 0),
		LightEmission = 1,
	},
	bubbles = {
		Texture = TEX_SQUARE,
		Rate = 4,
		Lifetime = NR.new(2.8, 3.4),
		Speed = NR.new(2.2, 2.8),
		Spread = 6,
		Size = { { 0, 0.3 }, { 1, 0.55 } },
		Transparency = { { 0, 0.15 }, { 0.8, 0.35 }, { 1, 1 } },
		Color = CS.new(rgb(236, 252, 255), rgb(190, 238, 255)),
		LightEmission = 0.35,
	},
	petals = {
		Texture = TEX_SQUARE,
		Rate = 3,
		Lifetime = NR.new(5, 7),
		Speed = NR.new(1, 2.2),
		Spread = 180,
		Size = { { 0, 0.45 }, { 1, 0.45 } },
		Transparency = { { 0, 0 }, { 0.85, 0 }, { 1, 1 } },
		Color = CS.new(C.Blossom1, C.Blossom2),
		Acceleration = Vector3.new(1.4, -0.7, 0.5),
		Drag = 0.2,
		RotSpeed = NR.new(-120, 120),
		Rotation = NR.new(0, 360),
	},
	embers = {
		Texture = TEX_SQUARE,
		Rate = 4,
		Lifetime = NR.new(1, 2),
		Speed = NR.new(3, 5.5),
		Spread = 16,
		Size = { { 0, 0.35 }, { 1, 0 } },
		Transparency = { { 0, 0 }, { 1, 0.3 } },
		Color = CS.new(C.FlameCore, C.Flame),
		Acceleration = Vector3.new(0.4, 1.2, 0),
		Drag = 0.8,
		RotSpeed = NR.new(-180, 180),
		LightEmission = 1,
	},
	flame = {
		Texture = TEX_FIRE,
		Rate = 10,
		Lifetime = NR.new(0.3, 0.5),
		Speed = NR.new(3, 5),
		Spread = 8,
		Size = { { 0, 1.2 }, { 1, 0.2 } },
		Transparency = { { 0, 0.1 }, { 1, 1 } },
		Color = CS.new(C.FlameCore, C.Flame),
		RotSpeed = NR.new(-60, 60),
		Rotation = NR.new(0, 360),
		LightEmission = 1,
	},
}

-- Default instance name for an effect: "Smoke", "Fireflies", ...
local function fxName(kind: string, opts: { [string]: any }?): string
	return (opts and opts.name) or (kind:sub(1, 1):upper() .. kind:sub(2))
end

function Props.fx(parent: any, kind: string, opts: { [string]: any }?): any
	local spec = FX[kind]
	assert(spec, `Props.fx: unknown kind {kind}`)
	local o = opts or {}
	local k = o.size or 1
	local speed = o.speed or spec.Speed
	local color = o.color or spec.Color
	local spread = o.spread or spec.Spread
	return U.new("ParticleEmitter", {
		Name = fxName(kind, o),
		Texture = spec.Texture,
		Rate = o.rate or spec.Rate,
		Lifetime = o.lifetime or spec.Lifetime,
		Speed = if typeof(speed) == "number" then NR.new(speed) else speed,
		SpreadAngle = U.Vector2.new(spread, spread),
		Size = seq(spec.Size, k),
		Transparency = seq(spec.Transparency),
		Color = if typeof(color) == "Color3" then CS.new(color) else color,
		Acceleration = o.accel or spec.Acceleration or Vector3.new(0, 0, 0),
		Drag = spec.Drag or 0,
		RotSpeed = spec.RotSpeed or NR.new(0),
		Rotation = spec.Rotation or NR.new(0),
		LightEmission = o.lightEmission or spec.LightEmission or 0,
		EmissionDirection = o.direction or Enum.NormalId.Top,
	}, parent)
end

-- Props.fx on a new Attachment of `part` at the world CFrame (or point) `at`; returns the emitter.
function Props.fxAt(part: any, at: any, kind: string, opts: { [string]: any }?): any
	local cf = if typeof(at) == "Vector3" then CFrame.new(at) else at
	local name = fxName(kind, opts) .. "Attachment"
	local attachment = U.new("Attachment", { Name = name, CFrame = part.CFrame:Inverse() * cf }, part)
	return Props.fx(attachment, kind, opts)
end

-- A spinning group (windmill blades, ferris wheel) is turned by CFrame on every client: its parts
-- never collide, are never raycast against and never fire Touched, so the turning geometry can't
-- shove or fling a player (the static frame round it stays solid).
local function ghost(m: any)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

local function pickColor(o: { [string]: any }, key: string, default: any): any
	local v = o[key]
	if v == nil then
		return default
	end
	return v
end

-- Big readable sign text (DESIGN.md §1): Nunito ExtraBold, TextScaled, optional dark outline.
local function addSignText(part: any, face: any, text: string, color: any, stroke: any?)
	local gui = U.new("SurfaceGui", {
		Name = "SignGui" .. face.Name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0.2,
	}, part)
	local label = U.new("TextLabel", {
		Name = "Text",
		AnchorPoint = U.Vector2.new(0.5, 0.5),
		Position = U.UDim2.fromScale(0.5, 0.5),
		Size = U.UDim2.fromScale(0.9, 0.78),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = color,
	}, gui)
	if stroke then
		U.new("UIStroke", { Name = "Stroke", Color = stroke, Thickness = 4 }, label)
	end
	return label
end

-- Random 90-degree turn: props stay aligned with the voxel grid of their caller's frame.
local function quarterTurn(b: any): any
	return rot(0, 90 * b:int(0, 3), 0)
end

--------------------------------------------------------------------------------------------
-- TREES
--------------------------------------------------------------------------------------------

--[[
	Shared broadleaf tree: square trunk with root blocks and a branch, and a voxel "ball" canopy:
	three rounded ("plus"-shaped) layers — dark bottom, wide mid, light top — a cap and two bumps
	(one low and dark, one high and light) that break the silhouette. The wide mid layer casts the
	tree's shadow. With opts.lite the roots, bumps, branch and litter are left out (8 parts: trunk
	+ canopy only; fruit only when opts.fruit asks for it). opts.compact: the dark and the light
	layer are single blocks instead of "plus" pairs (2 parts fewer, e.g. lite + compact = 6).
	Fallen leaves sit close to the trunk and are dropped where Props.groundAt (when set) says the
	ground under them is not at the tree's foot.
	p: trunkW, trunkH (canopy bottom), R (canopy half-width), H (canopy height),
	   pal {dark, mid, light}, trunk, trunkDark, fruit (colour | nil), litter (colour of fallen
	   leaves/petals | nil), crownScale, branch = false.
]]
local function broadleaf(b: any, p: { [string]: any }): any
	local tw, th = p.trunkW, p.trunkH
	local pal = p.pal
	local dark, mid, lightC = pal[1], pal[2], pal[3]
	local lite = b.opts.lite == true
	local trunk = b:span("Trunk", -tw / 2, -1, -tw / 2, tw / 2, th + 2.5, tw / 2, p.trunk)

	-- two root blocks on neighbouring sides
	local sides = { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } }
	local s0 = b:int(1, 4)
	for i = 1, if lite then 0 else 2 do
		local sd = sides[(s0 + i - 2) % 4 + 1]
		local out = 1.0
		local cx, cz = sd[1] * (tw / 2 + out / 2 - 0.05), sd[2] * (tw / 2 + out / 2 - 0.05)
		local sx = if sd[1] ~= 0 then out else tw * 0.55
		local sz = if sd[2] ~= 0 then out else tw * 0.55
		b:vox(`Root{i}`, cx, 0.35, cz, sx, 1.6 - i * 0.3, sz, p.trunkDark, NOSHADOW)
	end

	-- canopy: a voxel "ball" of three rounded layers (dark bottom, wide mid, light top) + cap
	local R, H = p.R, p.H
	local hA, hB, hC = H * 0.26, H * 0.4, H * 0.24
	local y0 = th
	local function jit(): number
		return b:range(-0.45, 0.45)
	end
	local compact = b.opts.compact == true
	-- a layer: a rounded "plus" pair, or one block cut to the plus' inner square when compact
	local function layer(name: string, x: number, ya: number, z: number, yb: number, w: number, k: number, col: any)
		if compact then
			local h = w * (1 + k) / 4
			b:span(name, x - h, ya, z - h, x + h, yb, z + h, col, FOLIAGE)
		else
			b:cross(name, x, ya, z, yb, w, w, k, col, FOLIAGE)
		end
	end
	local ax, az = jit(), jit()
	layer("CanopyLow", ax, y0, az, y0 + hA + 0.3, 2 * R * 0.8, 0.7, dark)
	local bx, bz = jit(), jit()
	local yB0, yB1 = y0 + hA, y0 + hA + hB
	b:cross("Canopy", bx, yB0, bz, yB1, 2 * R, 2 * R, 0.72, mid, FOLIAGE_SHADOW)
	local cx, cz = bx + jit(), bz + jit()
	local wc = 2 * R * (p.crownScale or 0.74)
	local yC1 = yB1 + hC
	layer("CanopyTop", cx, yB1 - 0.25, cz, yC1, wc, 0.7, lightC)
	local capW = wc * 0.48
	local kx, kz = cx + jit(), cz + jit()
	b:span(
		"Cap",
		kx - capW / 2,
		yC1 - 0.2,
		kz - capW / 2,
		kx + capW / 2,
		yC1 + H * 0.12,
		kz + capW / 2,
		lerpColor(lightC, C.White, 0.15),
		FOLIAGE
	)

	-- bumps breaking the silhouette: one low & dark, one high & light, on different sides
	local a0 = b:int(0, 3) * 90
	local bumps = { { a0, yB0 + hB * 0.3, dark }, { a0 + 180 + b:range(-50, 50), yB1 - hB * 0.15, lightC } }
	for i, bm in if lite then {} else bumps do
		local a = RAD(bm[1] + b:range(-25, 25))
		local d = R * 0.98
		local s = R * b:range(0.62, 0.78)
		b:vox(`Bump{i}`, bx + d * math.sin(a), bm[2], bz + d * math.cos(a), s, hB * 0.62, s, bm[3], FOLIAGE)
	end

	-- fruit: small bright cubes on the faces of the middle layer
	local function addFruit()
		local spots = { { 1, 0.35 }, { -0.4, 1 }, { -1, -0.5 } }
		for i, sp in spots do
			local fx, fz
			if math.abs(sp[1]) == 1 then
				fx, fz = bx + sp[1] * (R + 0.15), bz + sp[2] * R * 0.55
			else
				fx, fz = bx + sp[1] * R * 0.55, bz + sp[2] * (R + 0.15)
			end
			b:vox(`Fruit{i}`, fx, yB0 + hB * (0.3 + 0.2 * i), fz, 1.1, 1.1, 1.1, p.fruit, DECOR)
		end
	end

	if lite then
		if p.fruit and b.opts.fruit then
			addFruit()
		end
		return trunk
	end

	-- a branch under the low bump
	if p.branch ~= false then
		local a = RAD(a0)
		local sx, sz = math.sin(a), math.cos(a)
		local len = R * 0.75
		local by = th - 1.4
		if math.abs(sx) > math.abs(sz) then
			local sg = if sx > 0 then 1 else -1
			b:span("Branch", sg * (tw / 2 - 0.2), by, -0.45, sg * (tw / 2 + len), by + 0.9, 0.45, p.trunk, NOSHADOW)
		else
			local sg = if sz > 0 then 1 else -1
			b:span("Branch", -0.45, by, sg * (tw / 2 - 0.2), 0.45, by + 0.9, sg * (tw / 2 + len), p.trunk, NOSHADOW)
		end
	end

	if p.fruit then
		addFruit()
	end

	-- litter: fallen petals / leaves on the ground under the canopy, near the trunk
	if p.litter then
		local footY = b.cf.Position.Y
		for i = 1, 2 do
			local a = RAD(a0 + 70 + i * 150)
			local d = tw / 2 + b:range(0.8, 1.4) -- right beside the trunk, between the roots
			local lx, lz = d * math.sin(a), d * math.cos(a)
			local wp = b:worldPoint(Vector3.new(lx, 0, lz))
			if not Props.groundAt or math.abs(Props.groundAt(wp.X, wp.Z) - footY) < 0.25 then
				b:vox(`Litter{i}`, lx, 0.07, lz, 1.6, 0.14, 1.6, p.litter, DECOR)
			end
		end
	end
	return trunk
end

local function treeSize(b: any)
	b.s *= b:range(0.9, 1.1)
	b.cf = b.cf * quarterTurn(b)
end

--[[
	oakTree: the classic voxel tree — chunky trunk, roots, a branch, a rounded block canopy in
	three greens. 13-16 parts. opts: leaves = {dark, mid, light}, trunk = colour,
	fruit = colour | true (red apples) | false (default: apples on ~1 in 5 trees, by seed).
]]
function Props.oakTree(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "OakTree", cf, opts, 19)
	local o = b.opts
	treeSize(b)
	local fruit = o.fruit
	if fruit == nil then
		fruit = b:chance(0.2)
	end
	local trunk = broadleaf(b, {
		trunkW = b:range(2.4, 2.8),
		trunkH = b:range(5, 6),
		R = b:range(5, 5.8),
		H = b:range(8.6, 9.6),
		pal = o.leaves or { C.Leaf1, C.Leaf2, C.Leaf3 },
		trunk = pickColor(o, "trunk", C.Bark),
		trunkDark = C.BarkDark,
		fruit = if fruit == true then C.Red elseif fruit == false then nil else fruit,
	})
	return b:finish(trunk)
end

--[[
	cherryTree: pink blossom tree, wider and flatter canopy, a few fallen petals. 15 parts.
	opts: leaves, trunk.
]]
function Props.cherryTree(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "CherryTree", cf, opts, 29)
	local o = b.opts
	treeSize(b)
	local trunk = broadleaf(b, {
		trunkW = b:range(2.2, 2.6),
		trunkH = b:range(4.6, 5.4),
		R = b:range(5.6, 6.2),
		H = b:range(7.4, 8.2),
		pal = o.leaves or { C.Blossom0, C.Blossom1, C.Blossom2 },
		trunk = pickColor(o, "trunk", rgb(150, 92, 72)),
		trunkDark = rgb(118, 70, 56),
		litter = C.Blossom1,
		crownScale = 0.78,
	})
	return b:finish(trunk)
end

--[[
	autumnTree: orange / yellow / red-orange broadleaf with fallen leaves. 15 parts.
	opts: leaves, trunk.
]]
function Props.autumnTree(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "AutumnTree", cf, opts, 31)
	local o = b.opts
	treeSize(b)
	local trunk = broadleaf(b, {
		trunkW = b:range(2.3, 2.7),
		trunkH = b:range(5, 6),
		R = b:range(4.8, 5.5),
		H = b:range(9, 10),
		pal = o.leaves or { C.Autumn0, C.Autumn1, C.Autumn2 },
		trunk = pickColor(o, "trunk", C.Bark),
		trunkDark = C.BarkDark,
		litter = C.Autumn1,
	})
	return b:finish(trunk)
end

local ROUND_PALETTES = {
	green = { C.Leaf1, C.Leaf2, C.Leaf3 },
	mint = { C.Mint1, C.Mint2, C.Mint3 },
	autumn = { C.Autumn0, C.Autumn1, C.Autumn2 },
	blossom = { C.Blossom0, C.Blossom1, C.Blossom2 },
	lime = { C.Leaf2, C.Lime, C.LeafLight }, -- close to the grass: only for small accents
}

--[[
	roundTree (v2 name): a broadleaf voxel tree with a named palette. 13-16 parts.
	opts: palette = "green" (default) | "mint" | "autumn" | "blossom" | "lime" | "mixed" (mostly
	green, sometimes mint/autumn by seed), leaves = {dark, mid, light}, trunk, fruit.
]]
function Props.roundTree(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "RoundTree", cf, opts, 23)
	local o = b.opts
	local palName = o.palette or "green"
	if palName == "mixed" then
		local r = b.rand()
		palName = if r < 0.6 then "green" elseif r < 0.8 then "mint" else "autumn"
	end
	treeSize(b)
	local trunk = broadleaf(b, {
		trunkW = b:range(2.3, 2.8),
		trunkH = b:range(5, 6),
		R = b:range(4.8, 5.8),
		H = b:range(8.4, 9.6),
		pal = o.leaves or ROUND_PALETTES[palName] or ROUND_PALETTES.green,
		trunk = pickColor(o, "trunk", C.Bark),
		trunkDark = C.BarkDark,
		fruit = if o.fruit == true then C.Red else o.fruit,
		litter = if palName == "autumn" then C.Autumn1 elseif palName == "blossom" then C.Blossom1 else nil,
	})
	return b:finish(trunk)
end

--[[
	birchTree: tall slim white trunk with dark bark marks, a narrow three-layer canopy in fresh
	greens (the mid layer casts the shadow). 12 parts. opts: leaves = {dark, mid, light}, trunk.
]]
function Props.birchTree(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "BirchTree", cf, opts, 43)
	local o = b.opts
	treeSize(b)
	local pal = o.leaves or { C.BirchLeaf1, C.BirchLeaf2, C.BirchLeaf3 }
	local tw = b:range(1.6, 1.9)
	local th = b:range(8, 9.5) -- canopy bottom
	local trunk = b:span("Trunk", -tw / 2, -1, -tw / 2, tw / 2, th + 2.5, tw / 2, pickColor(o, "trunk", C.Birch))
	-- dark bark marks sticking out of the trunk faces
	local faces = { { 1, 0 }, { 0, -1 }, { -1, 0 }, { 0, 1 } }
	for i, f in if o.lite then {} else faces do
		local yy = 1.2 + i * 1.6 + b:range(-0.3, 0.3)
		local w = tw * 0.6
		local sx = if f[1] ~= 0 then 0.24 else w
		local sz = if f[2] ~= 0 then 0.24 else w
		local off = tw / 2 + 0.06
		local shift = if i % 2 == 0 then 0.2 else -0.2
		b:vox(
			`Mark{i}`,
			f[1] * off + (if f[1] == 0 then shift else 0),
			yy,
			f[2] * off + (if f[2] == 0 then shift else 0),
			sx,
			0.5,
			sz,
			C.BirchDark,
			DECOR
		)
	end
	-- tall narrow canopy: dark low layer, mid layer, light top layer, cap
	local R = b:range(3.6, 4.1)
	local y0 = th
	b:cross("CanopyLow", 0, y0, 0, y0 + 2.6, 2 * R * 0.82, 2 * R * 0.82, 0.7, pal[1], FOLIAGE)
	local ox, oz = b:range(-0.4, 0.4), b:range(-0.4, 0.4)
	b:cross("Canopy", ox, y0 + 2.3, oz, y0 + 6.6, 2 * R, 2 * R, 0.72, pal[2], FOLIAGE_SHADOW)
	local tx, tz = ox + b:range(-0.4, 0.4), oz + b:range(-0.4, 0.4)
	b:cross("CanopyTop", tx, y0 + 6.4, tz, y0 + 9.2, 2 * R * 0.72, 2 * R * 0.72, 0.7, pal[3], FOLIAGE)
	b:span(
		"Cap",
		tx - R * 0.35,
		y0 + 9.0,
		tz - R * 0.35,
		tx + R * 0.35,
		y0 + 10.2,
		tz + R * 0.35,
		lerpColor(pal[3], C.White, 0.2),
		FOLIAGE
	)
	return b:finish(trunk)
end

local PINE_VARIANTS = {
	-- tall dark old pine
	{ h = 27, w = 11, layers = 4, trunk = 2.0, colors = { "Pine0", "Pine1", "Pine3" } },
	-- medium pine
	{ h = 21, w = 9.4, layers = 4, trunk = 1.8, colors = { "Pine1", "Pine2", "Pine3" } },
	-- young bright fir
	{ h = 15, w = 7.6, layers = 3, trunk = 1.5, colors = { "Pine1", "Pine2", "PineLight" } },
}

--[[
	pineTree: voxel conifer — layers of a wide dark rounded "skirt" with a narrower body on top,
	getting smaller and lighter towards the tip, so the silhouette zig-zags like branch tiers; the
	bottom skirt casts the shadow. 11-14 parts. opts: variant 1..3 (tall dark / medium / young bright), snow = true (white
	skirts = snow on the branches, for the mountains), leaves = { skirt, body, top } colours,
	trunk = colour.
]]
function Props.pineTree(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "PineTree", cf, opts, 11)
	local o = b.opts
	local v = PINE_VARIANTS[o.variant or b:int(1, 3)] or PINE_VARIANTS[2]
	treeSize(b)
	local leaves = o.leaves or { C[v.colors[1]], C[v.colors[2]], C[v.colors[3]] }
	local tw = v.trunk
	local base = v.h * 0.14
	local trunk = b:span("Trunk", -tw / 2, -1, -tw / 2, tw / 2, base + 2, tw / 2, pickColor(o, "trunk", C.Bark))

	local n = v.layers
	local layerH = (v.h - base - 1.6) / n
	local y = base
	for i = 0, n - 1 do
		local t = i / (n - 1)
		local w = v.w * (1 - 0.62 * t)
		local ox, oz = 0, 0 -- centred tiers: skirts and bodies never share a face plane
		local skirtC = if o.snow then lerpColor(C.Snow, C.Glass, 0.15) else shade(leaves[1], 1 + 0.12 * t)
		local bodyC = lerpColor(leaves[2], leaves[3], t)
		local hs = math.max(1.2, layerH * 0.34)
		local skirtX = if i == 0 then FOLIAGE_SHADOW else FOLIAGE -- the widest skirt casts the shadow
		if o.lite then
			local sw = w * 0.88
			b:span(`Skirt{i + 1}`, ox - sw / 2, y, oz - sw / 2, ox + sw / 2, y + hs, oz + sw / 2, skirtC, skirtX)
		else
			b:cross(`Skirt{i + 1}`, ox, y, oz, y + hs, w, w, 0.66, skirtC, skirtX)
		end
		local bw = w * 0.76 -- clear of the skirt cross's narrow block (no near-coplanar sides)
		b:span(
			`Body{i + 1}`,
			ox - bw / 2,
			y + hs - 0.1,
			oz - bw / 2,
			ox + bw / 2,
			y + layerH + 0.15,
			oz + bw / 2,
			bodyC,
			FOLIAGE
		)
		y += layerH
	end
	local tipC = if o.snow then C.Snow else lerpColor(leaves[3], C.White, 0.15)
	b:span("Tip", -0.8, y + 0.1, -0.8, 0.8, y + 1.7, 0.8, tipC, FOLIAGE)
	return b:finish(trunk)
end

--[[
	palmTree: segmented trunk of 3 offset blocks bending to one side (alternating two shades), a
	dark crown block, block fronds (the two long ones cast the shadow) and two coconuts. 16 parts. opts: variant = 1 ("umbrella":
	a plus of long fronds with drooping tips + 4 light diagonal fronds) | 2 ("arched": 4 fronds
	stepping down twice, light -> dark), default by seed; leaves = {dark, mid, light},
	trunk = colour, lean = studs the crown is offset sideways (default 1.4..2.2).
]]
function Props.palmTree(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "PalmTree", cf, opts, 37)
	local o = b.opts
	treeSize(b)
	local pal = o.leaves or { C.Palm1, C.Palm2, C.Palm3 }
	local variant = if o.lite then 1 else o.variant or b:int(1, 2)
	local bark = pickColor(o, "trunk", C.PalmBark)
	local barkDark = shade(bark, 0.83)

	-- trunk: 3 segments, each thinner, shifted along +X on a curve
	local lean = o.lean or b:range(1.4, 2.2)
	local heights = { b:range(5.2, 5.8), b:range(4.4, 4.9), b:range(4.0, 4.5) }
	local shifts = { 0, 0.45, 1.0 }
	local y = -1
	local first, tx
	for i = 1, 3 do
		local w = 2.0 - (i - 1) * 0.25
		local x = lean * shifts[i]
		local seg = b:span(
			`Trunk{i}`,
			x - w / 2,
			y,
			-w / 2,
			x + w / 2,
			y + heights[i] + 0.05,
			w / 2,
			if i % 2 == 1 then bark else barkDark
		)
		first = first or seg
		y += heights[i]
		tx = x
	end

	b:span("Crown", tx - 1.4, y - 0.8, -1.4, tx + 1.4, y + 1.0, 1.4, pal[1], FOLIAGE)
	local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	local fw, ft = 2.1, 0.9
	if variant == 1 then
		-- "umbrella": the plus of two long fronds, drooping tips, light diagonal fronds
		local L = b:range(4.4, 5.0)
		b:span("FrondX", tx - L, y + 0.55, -fw / 2, tx + L, y + 0.55 + ft, fw / 2, pal[2], FOLIAGE_SHADOW)
		b:span("FrondZ", tx - fw / 2, y + 0.6, -L, tx + fw / 2, y + 0.6 + ft, L, pal[2], FOLIAGE_SHADOW)
		for i, d in dirs do
			-- drooping tip: hangs from the end of the blade, one step lower
			local reach = L + 1.2
			local sx = if d[1] ~= 0 then 3.0 else 1.8
			local sz = if d[2] ~= 0 then 3.0 else 1.8
			-- (its top sits 0.1+ inside the blade above it: FrondX starts at y + 0.55, FrondZ at + 0.6)
			local top = y + 0.75 - (i % 2) * 0.05
			b:vox(`FrondTip{i}`, tx + d[1] * reach, top - 0.65, d[2] * reach, sx, 1.3, sz, shade(pal[2], 0.86), FOLIAGE)
		end
		for i, d in if o.lite then {} else { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
			-- grows out of the crown's corner (its inner corner sits inside the crown)
			local dd = 2.7
			b:vox(`FrondDiag{i}`, tx + d[1] * dd, y + 0.35 - (i % 2) * 0.12, d[2] * dd, 3.0, 0.8, 3.0, pal[3], FOLIAGE)
		end
	else
		-- "arched": short light plus, then two steps down per frond (mid green, dark tip)
		local L = b:range(3.0, 3.4)
		b:span("FrondX", tx - L, y + 0.55, -fw / 2, tx + L, y + 0.55 + ft, fw / 2, pal[3], FOLIAGE_SHADOW)
		b:span("FrondZ", tx - fw / 2, y + 0.6, -L, tx + fw / 2, y + 0.6 + ft, L, pal[3], FOLIAGE_SHADOW)
		for i, d in dirs do
			local lift = (i % 2) * 0.05
			local function seg(name: string, from: number, len: number, w: number, top: number, col: any)
				local c = from + len / 2
				local sx = if d[1] ~= 0 then len else w
				local sz = if d[2] ~= 0 then len else w
				b:vox(name, tx + d[1] * c, top - ft / 2, d[2] * c, sx, ft, sz, col, FOLIAGE)
			end
			seg(`FrondMid{i}`, L - 0.3, 2.6, 1.9, y + 0.6 + lift, pal[2])
			seg(`FrondTip{i}`, L + 2.0, 2.2, 1.5, y - 0.25 + lift, pal[1])
		end
	end
	if o.lite then
		return b:finish(first)
	end
	-- coconuts under the crown
	b:vox("Coconut1", tx + 1.0, y - 1.2, 0.6, 1.2, 1.2, 1.2, C.Coconut, DECOR)
	b:vox("Coconut2", tx - 0.5, y - 1.35, -1.0, 1.1, 1.1, 1.1, shade(C.Coconut, 0.88), DECOR)
	return b:finish(first)
end

--[[
	giantTree: the landmark tree, ~82 studs tall at scale 1 (Landmarks scales it up): a massive
	10-stud trunk with bark ridges and stepped roots, three branches tucked under a huge, bright
	4-layer canopy (~58 studs, ~70 with its bumps) with pink blossom clusters and 8 Neon lanterns
	hanging under its rim. A treehouse deck wraps the trunk at y 28 with a hut on the front (-Z),
	right under the canopy: a room you walk into through an open door on its right side (glowing
	windows, a rug, a window seat, a treasure chest, a lantern with a PointLight) under a stepped
	roof. A chunky stair of 20 steps wraps once round the trunk from the front-right corner up to
	the deck, a yellow slide runs from the deck's front-left corner down to the meadow (~20 studs
	out in front of the trunk) and a long rope swing hangs under the deck. 101 parts.
	opts: leaves = {dark, mid, light}, treehouse = false (no deck/hut/stair/swing),
	roof = colour (hut roof).
]]

function Props.giantTree(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "GiantTree", cf, opts, 47)
	local o = b.opts
	-- a brighter palette than the woods: it lights up from across the lagoon
	local pal = o.leaves or { C.Leaf1, C.Leaf2, rgb(132, 228, 92) }
	local dark, mid, lightC = pal[1], pal[2], pal[3]
	local bark, barkDark = C.Bark, C.BarkDark
	local T = 5 -- trunk half-width

	-- trunk (up into the canopy) with bark ridges
	local trunk = b:span("Trunk", -T, -2, -T, T, 46, T, bark)
	for i, f in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local off = T + 0.05
		local sx = if f[1] ~= 0 then 0.5 else 1.6
		local sz = if f[2] ~= 0 then 0.5 else 1.6
		local shift = (i - 2.5) * 1.2
		b:vox(
			`Ridge{i}`,
			f[1] * off + (if f[1] == 0 then shift else 0),
			14 + i * 2,
			f[2] * off + (if f[2] == 0 then shift else 0),
			sx,
			16,
			sz,
			barkDark,
			NOSHADOW
		)
	end
	-- roots: two steps out on three sides (the stair starts on the +X side)
	for i, f in { { 0, 1 }, { -1, 0 }, { 0, -1 } } do
		local shift = if i % 2 == 0 then 1 else -1
		local function root(name: string, out: number, y: number, depth: number, w: number, h: number, color: any)
			local x = f[1] * out + (if f[1] == 0 then shift else 0)
			local z = f[2] * out + (if f[2] == 0 then shift else 0)
			local sx = if f[1] ~= 0 then depth else w
			local sz = if f[2] ~= 0 then depth else w
			b:vox(name, x, y, z, sx, h, sz, color)
		end
		root(`RootIn{i}`, T + 1.5, 1.5, 3.4, 4, 6, bark)
		root(`RootOut{i}`, T + 4.4, 0, 3, 3.2, 3, barkDark)
	end
	-- three thick branches reaching out under the canopy (none on the front: the hut is there)
	b:span("Branch1", T - 0.2, 40.6, -1.2, 21, 43, 1.2, bark, NOSHADOW)
	b:span("Branch2", -21, 40.6, -1.2, -T + 0.2, 43, 1.2, bark, NOSHADOW)
	b:span("Branch3", -1.2, 40.6, T - 0.2, 1.2, 43, 21, bark, NOSHADOW)

	-- canopy: a big voxel ball of rounded layers, dark underside to a light crown
	b:cross("CanopyLow", 0, 42, 0, 51, 44, 44, 0.7, dark, FOLIAGE)
	b:cross("Canopy", 0.5, 50.6, -0.5, 64, 58, 58, 0.72, mid, FOLIAGE_SHADOW)
	b:cross("CanopyTop", 1.5, 63.6, -1.2, 73, 44, 44, 0.7, lightC, FOLIAGE)
	b:cross("CanopyCrown", 0, 72.6, 1, 79, 26, 26, 0.68, lerpColor(lightC, C.White, 0.1), FOLIAGE)
	b:span("Cap", -3, 78.6, -2.5, 4, 82, 4.5, lerpColor(lightC, C.White, 0.25), FOLIAGE)
	-- bumps round the canopy edge (low = dark on the sides, mid on the corners, light up high);
	-- they leave the 8 lantern spots under the rim free
	local bumps = {
		{ 28, 48, 0, 12, dark },
		{ -28, 49, 1, 12, dark },
		{ 0, 47.5, 28, 11, dark },
		{ -1, 48, -27.5, 12, dark },
		{ 23, 57, 23, 11, mid },
		{ -23, 58, -23, 11, mid },
		{ 23.5, 57.5, -22.5, 11, mid },
		{ 18, 68, -8, 10, C.Blossom1 }, -- two of the high bumps are blossom puffs
		{ -17, 67, 8, 10, lightC },
		{ 6, 69, 18, 9, C.Blossom2 },
	}
	for i, c in bumps do
		b:vox(`Bump{i}`, c[1], c[2], c[3], c[4], c[4] * 0.9, c[4], c[5], FOLIAGE)
	end
	-- pink blossom clusters on the crown and the canopy sides (the "magic" touch)
	local blossoms = {
		{ 11.5, 73.4, -11.5, 4.5, 1.8, 4.5 },
		{ -13, 73.4, 11, 4.5, 1.8, 4.5 },
		{ 24.2, 68, 5, 2.4, 3.6, 4.4 },
		{ -29.2, 56, 12, 2.4, 3.6, 4.4 },
		{ -11, 59, -30.2, 4.4, 3.6, 2.4 },
		{ 12, 57, 29.2, 4.4, 3.6, 2.4 },
	}
	for i, c in blossoms do
		local bloom = b:vox(
			`Blossom{i}`,
			c[1],
			c[2],
			c[3],
			c[4],
			c[5],
			c[6],
			if i % 2 == 1 then C.Blossom1 else C.Blossom2,
			FOLIAGE
		)
		if i == 4 or i == 6 then
			-- petals drifting off the two low side clusters
			Props.fx(bloom, "petals", { rate = 2, size = b.s })
		end
	end
	-- fireflies wandering in the shade under the canopy (the back and both sides; the hut is
	-- on the front)
	for _, p in { { 15, 12 }, { -16, 6 }, { 2, 18 } } do
		Props.fxAt(trunk, b:world(CFrame.new(p[1], 36, p[2])), "fireflies", { rate = 1.5, size = 1.4 * b.s })
	end
	-- 8 glowing lanterns hanging straight under the wide middle layer, round the rim
	for i = 0, 7 do
		local a = RAD(22.5 + 45 * i)
		local lx, lz = 25 * math.sin(a), 25 * math.cos(a)
		b:span(`Lantern{i + 1}`, lx - 1, 47.4, lz - 1, lx + 1, 50.7, lz + 1, C.Glow, NEON_DECOR)
	end

	if o.treehouse ~= false then
		-- the deck: four slabs round the trunk; the stair comes up through the gap on the
		-- right-back (x 0..14, z -0.7..14)
		local deckY = 28
		local d0 = deckY - 1.2
		b:span("Deck", -14, d0, -17, 14, deckY, -T, C.WoodLight) -- front, carries the hut
		b:span("DeckLeft", -14, d0, -T, -T, deckY, 14, C.WoodLight)
		b:span("DeckBack", -T, d0, T, 0, deckY, 14, C.WoodLight)
		b:span("DeckRight", T, d0, -T, 14, deckY, -0.7, C.WoodLight)
		b:span("Beam1", -14, d0 - 1.2, -11.5, 14, d0, -9.5, C.Wood, NOSHADOW)
		b:span("Beam2", -14, d0 - 1.2, -1, 14, d0, 1, C.Wood, NOSHADOW)
		b:span("RailLeft", -14, deckY, -17, -13.2, deckY + 1.8, 14, C.Wood)
		b:span("RailBack", -13.2, deckY, 13.2, 0, deckY + 1.8, 14, C.Wood)
		b:span("RailRight", 13.2, deckY, -17, 14, deckY + 1.8, -0.7, C.Wood)
		-- the hut on the front of the deck, facing the lagoon: a room (walls 0.8 thick) under a
		-- stepped roof just under the canopy, glowing windows through the front wall, an open
		-- doorway on its right side (towards the stair) with the door swung out; inside a rug, a
		-- window seat, a treasure chest and a lantern with a PointLight
		local roofC = o.roof or C.Red
		local Y = deckY
		b:span("HutWalls", -9, Y, -16, 9, Y + 8, -15.2, C.Cream) -- the front wall
		b:span("HutBack", -9, Y, -8.3, 9, Y + 8, -7.5, C.Cream)
		b:span("HutLeft", -9, Y, -15.2, -8.2, Y + 8, -8.3, C.Cream)
		b:span("HutRightA", 8.2, Y, -15.2, 9, Y + 8, -13.6, C.Cream)
		b:span("HutRightB", 8.2, Y, -10, 9, Y + 8, -8.3, C.Cream)
		b:span("HutLintel", 8.2, Y + 5.6, -13.6, 9, Y + 8, -10, C.Cream)
		b:span("HutRoof1", -10.5, Y + 8, -17.5, 10.5, Y + 9.4, -6, roofC)
		b:span("HutRoof2", -8.5, Y + 9.4, -16, 8.5, Y + 10.8, -7.5, lerpColor(roofC, C.White, 0.25))
		b:span("HutRoof3", -5.5, Y + 10.8, -14.5, 5.5, Y + 12, -9, roofC)
		b:span("HutDoor", 9, Y + 0.1, -14, 12.4, Y + 5.5, -13.6, C.Orange, NOSHADOW)
		for i, x in { -4.3, 4.3 } do
			b:span(`HutWindow{i}`, x - 1.8, Y + 3, -16.3, x + 1.8, Y + 6, -15.1, C.Glow, NEON_DECOR)
		end
		b:span("HutRug", -5, Y, -13.6, 3, Y + 0.15, -9.3, C.Pink, DECOR)
		b:span("HutSeat", 1.6, Y, -15.2, 7.2, Y + 1.6, -13.8, C.WoodLight)
		b:span("HutChest", -7.9, Y, -10.3, -5.1, Y + 1.8, -8.3, C.Wood)
		b:span("HutChestLid", -8.1, Y + 1.8, -10.5, -4.9, Y + 2.5, -8.3, C.Gold, NOSHADOW)
		local lamp = b:span("HutLantern", -0.8, Y + 6.3, -12.55, 0.8, Y + 8, -10.95, C.Glow, NEON_DECOR)
		light(lamp, 14, 1.3)
		-- the fun way down: a yellow slide from the front-left corner of the deck to the meadow
		-- (bed, red rails, a leg, a landing pad)
		local xc = -11.4
		local top, foot = Vector3.new(xc, Y, -17), Vector3.new(xc, 0.4, -37.5)
		local dir = (foot - top).Unit
		local n = Vector3.new(0, -dir.Z, dir.Y) -- the slope's upward normal
		b:beam("SlideBed", top - n * 0.4 - dir * 0.6, foot - n * 0.4 + dir * 0.5, 3.4, 0.8, C.Yellow)
		for i, sx in { -1, 1 } do
			local off = Vector3.new(sx * 1.95, 0, 0)
			b:beam(`SlideRail{i}`, top + n * 0.5 + off, foot + n * 0.5 + off, 0.5, 1.4, C.Red, NOSHADOW)
		end
		local midZ = (top.Z + foot.Z) / 2
		local midY = (top.Y + foot.Y) / 2
		b:span("SlideLeg", xc - 0.6, -0.5, midZ - 0.6, xc + 0.6, midY - 0.6, midZ + 0.6, C.Wood, NOSHADOW)
		b:span("SlidePad", xc - 2.2, -0.3, foot.Z - 3.5, xc + 2.2, 0.45, foot.Z + 0.4, C.Orange)
		-- the stair: 20 chunky steps (1.4 up each, 3.1 apart) on a square loop 5..10.5 out from
		-- the trunk centre, once round the trunk; the top step is flush with the deck
		local c = 7.75
		local corners = {
			Vector3.new(c, 0, -c),
			Vector3.new(-c, 0, -c),
			Vector3.new(-c, 0, c),
			Vector3.new(c, 0, c),
		}
		local function along(s: number): (any, any)
			local p = Vector3.new(c, 0, -2)
			local i = 1
			while true do
				local seg = corners[(i - 1) % 4 + 1] - p
				if s <= seg.Magnitude then
					return p + seg.Unit * s, seg.Unit
				end
				s -= seg.Magnitude
				p += seg
				i += 1
			end
		end
		for k = 0, 19 do
			local p, dir = along(k * 3.1)
			local alongX = math.abs(dir.X) > 0.5
			local sx = if alongX then 3.6 else 5.5
			local sz = if alongX then 5.5 else 3.6
			local top = 1.4 * (k + 1)
			b:vox(`Step{k + 1}`, p.X, top - 0.7, p.Z, sx, 1.4, sz, if k % 2 == 0 then C.WoodLight else C.Wood, NOSHADOW)
		end
		-- a long rope swing under the left side of the deck
		local sx, sz = -12, 3
		b:span("SwingRopeA", sx - 1.4, 2, sz - 0.1, sx - 1.2, d0, sz + 0.1, C.Rope, DECOR)
		b:span("SwingRopeB", sx + 1.2, 2, sz - 0.1, sx + 1.4, d0, sz + 0.1, C.Rope, DECOR)
		b:span("SwingSeat", sx - 1.8, 1.6, sz - 0.7, sx + 1.8, 2.1, sz + 0.7, C.Red)
	end
	return b:finish(trunk)
end

--------------------------------------------------------------------------------------------
-- PLANTS
--------------------------------------------------------------------------------------------

--[[
	bush: rounded leaf block with a light top and a dark side block, often with berries/flowers.
	4-7 parts. opts: leaves = {dark, mid, light}, berries = colour | false (default: by seed).
]]
function Props.bush(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Bush", cf, opts, 41)
	local o = b.opts
	b.s *= b:range(0.85, 1.2)
	b.cf = cf * quarterTurn(b)
	local pal = o.leaves or { C.Leaf0, C.Leaf1, C.Leaf2 }
	local w = b:range(4.0, 4.6)
	local main = b:cross("Bush", 0, -0.3, 0, 2.8, w, w * 0.9, 0.7, pal[2], FOLIAGE)
	b:span("BushTop", -w * 0.3 + 0.3, 2.7, -w * 0.28, w * 0.3 + 0.3, 3.75, w * 0.24, pal[3], FOLIAGE)
	b:vox("BushSide", w * 0.5, 0.75, 0.45, w * 0.48, 2.1, w * 0.5, pal[1], FOLIAGE)
	local berries = o.berries
	if berries == nil then
		berries = if b:chance(0.5) then b:pick({ C.Red, C.Pink, C.Yellow, C.Purple, C.White }) else false
	end
	if berries then
		local spots = {
			Vector3.new(-w * 0.2, 1.6, -w * 0.45 - 0.05),
			Vector3.new(-w * 0.5 - 0.05, 1.2, w * 0.15),
			Vector3.new(w * 0.15, 3.8, -0.1),
		}
		for i, p in spots do
			b:vox(`Berry{i}`, p.X, p.Y, p.Z, 0.8, 0.8, 0.8, berries, DECOR)
		end
	end
	return b:finish(main)
end

--[[
	flowerPatch: 4 voxel flowers on short stems — a flat petal block with a cube centre on top,
	two colours. No grass. 12 parts. opts: colors = {c1, c2} (default: a pair from Colors.Flowers).
]]
function Props.flowerPatch(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "FlowerPatch", cf, opts, 53)
	local o = b.opts
	b.s *= 1.3
	b.cf = cf * quarterTurn(b)
	local c1 = o.colors and o.colors[1] or b:pick(C.Flowers)
	local c2 = o.colors and o.colors[2] or b:pick(C.Flowers)
	if c2 == c1 then
		c2 = C.Flowers[(table.find(C.Flowers, c1) or 1) % #C.Flowers + 1]
	end
	local spots = {
		{ 0.0, 0.0, 2.0 },
		{ 1.5, 0.6, 1.4 },
		{ -1.1, 1.1, 1.6 },
		{ 0.4, -1.4, 1.2 },
	}
	local first
	for i, s in spots do
		local x = s[1] + b:range(-0.25, 0.25)
		local z = s[2] + b:range(-0.25, 0.25)
		local h = s[3] + b:range(-0.15, 0.25)
		local stem = b:span(`Stem{i}`, x - 0.17, -0.2, z - 0.17, x + 0.17, h, z + 0.17, C.Leaf1, DECOR)
		first = first or stem
		local col = if i % 2 == 1 then c1 else c2
		local pw = if i == 1 then 1.35 else 1.1
		b:vox(`Petals{i}`, x, h + 0.25, z, pw, 0.5, pw, col, DECOR)
		local centre = if col == C.Yellow or col == C.Flowers[2] then C.White else C.Yellow
		b:vox(`Centre{i}`, x, h + 0.62, z, pw * 0.45, 0.3, pw * 0.45, centre, DECOR)
	end
	return b:finish(first)
end

--[[
	mushroom: cream stem, fat red cap with a raised top and white dots. 7 parts.
	opts: color (cap), dots (colour).
]]
function Props.mushroom(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Mushroom", cf, opts, 89)
	local o = b.opts
	b.s *= b:range(0.8, 1.25)
	b.cf = cf * quarterTurn(b)
	local cap = o.color or b:pick({ C.Red, C.Red, C.Orange, C.Pink })
	local dots = o.dots or C.White
	local stem = b:span("Stem", -0.6, -0.2, -0.6, 0.6, 1.9, 0.6, C.Cream, DECOR)
	b:span("Cap", -1.7, 1.7, -1.7, 1.7, 2.9, 1.7, cap, DECOR)
	b:span("CapTop", -1.15, 2.85, -1.15, 1.15, 3.45, 1.15, cap, DECOR)
	b:vox("Dot1", 1.72, 2.3, -0.5, 0.2, 0.6, 0.6, dots, DECOR)
	b:vox("Dot2", -0.6, 2.3, -1.72, 0.6, 0.6, 0.2, dots, DECOR)
	b:vox("Dot3", 0.4, 3.47, 0.3, 0.6, 0.12, 0.6, dots, DECOR)
	b:vox("Dot4", -1.0, 2.92, 1.1, 0.5, 0.12, 0.5, dots, DECOR)
	return b:finish(stem)
end

--[[
	giantMushroom: a mushroom you can stand under: tall stem with a ring, a stepped 16-stud cap,
	cream gills and big dots (Neon when opts.glow). 14-16 parts.
	opts: color (cap, default Red), dots, glow = true (purple cap, glowing cyan dots), height (stem).
]]
function Props.giantMushroom(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "GiantMushroom", cf, opts, 97)
	local o = b.opts
	b.s *= b:range(0.92, 1.08)
	b.cf = cf * quarterTurn(b)
	local glow = o.glow == true
	local cap = o.color or (if glow then C.Purple else C.Red)
	local dots = o.dots or (if glow then C.Cyan else C.White)
	local dotExtra = if glow then NEON_DECOR else DECOR
	local h = o.height or 11
	local stem = b:span("Stem", -1.6, -0.5, -1.6, 1.6, h + 0.5, 1.6, C.Cream)
	b:span("StemBase", -2.2, -0.5, -2.2, 2.2, 1.6, 2.2, lerpColor(C.Cream, C.Sand, 0.5))
	b:span("Ring", -2.4, h * 0.6, -2.4, 2.4, h * 0.6 + 0.8, 2.4, C.White, NOSHADOW)
	b:span("Gills", -6.6, h - 0.3, -6.6, 6.6, h + 0.5, 6.6, C.Cream, NOSHADOW)
	b:cross("Cap", 0, h + 0.4, 0, h + 3.4, 15, 15, 0.76, cap)
	b:cross("CapTop", 0, h + 3.3, 0, h + 5.2, 10, 10, 0.72, lerpColor(cap, C.White, 0.12))
	b:span("CapCrown", -2.6, h + 5.1, -2.6, 2.6, h + 6.1, 2.6, cap)
	local spots = {
		{ 7.52, h + 1.9, -2, "x" },
		{ -7.52, h + 1.6, 1.5, "x" },
		{ 2.5, h + 2.0, -7.52, "z" },
		{ -1.5, h + 1.7, 7.52, "z" },
		{ -2.2, h + 5.22, -2.0, "y" },
		{ 3.0, h + 5.22, 1.4, "y" },
	}
	for i, s in spots do
		local sx = if s[4] == "x" then 0.25 else 1.6
		local sy = if s[4] == "y" then 0.2 else 1.6
		local sz = if s[4] == "z" then 0.25 else 1.6
		b:vox(`Dot{i}`, s[1], s[2], s[3], sx, sy, sz, dots, dotExtra)
	end
	if glow and o.light ~= false then
		light(stem, 14, 1.2, C.Cyan)
	end
	if glow and o.fireflies ~= false then
		-- fireflies drifting under the cap on both sides of the stem
		for _, x in { -4.5, 4.5 } do
			Props.fxAt(stem, b:world(CFrame.new(x, h - 2.5, -x * 0.4)), "fireflies", { rate = 1, size = b.s })
		end
	end
	return b:finish(stem)
end

--[[
	lilyPad: floating pad of two crossed green slabs, sometimes with a pink flower. 2-4 parts.
	cframe on the water surface. opts: flower = true/false (default: by seed).
]]
function Props.lilyPad(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "LilyPad", cf, opts, 83)
	local o = b.opts
	b.s *= b:range(0.85, 1.25)
	b.cf = cf * quarterTurn(b)
	local lift = b:range(0, 0.1) -- neighbouring pads never share a top plane
	local pad = b:span("Pad", -1.5, -0.1 + lift, -1.0, 1.5, 0.12 + lift, 1.0, C.Leaf1, DECOR)
	b:span("Pad2", -1.0, -0.1 + lift, -1.5, 0.6, 0.16 + lift, 1.5, C.Leaf2, DECOR)
	if o.flower == true or (o.flower == nil and b:chance(0.45)) then
		b:vox("Flower", 0.5, 0.45 + lift, 0.3, 0.9, 0.6, 0.9, C.Pink, DECOR)
		b:vox("FlowerCentre", 0.5, 0.8 + lift, 0.3, 0.4, 0.2, 0.4, C.Yellow, DECOR)
	end
	return b:finish(pad)
end

--[[
	reeds: chunky shore reeds — 4 green stalks, 2 brown cattail heads and a leaf blade. 7 parts.
	Stand in shallow water too.
]]
function Props.reeds(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Reeds", cf, opts, 79)
	b.cf = cf * quarterTurn(b)
	local first
	local spots = { { 0, 0 }, { 0.9, 0.5 }, { -0.6, 0.8 }, { 0.3, -0.8 } }
	local tops = {}
	for i, p in spots do
		local h = b:range(3.4, 5.4)
		local col = if i % 2 == 1 then C.Leaf1 else C.Leaf0
		local stalk = b:span(`Stalk{i}`, p[1] - 0.22, -1, p[2] - 0.22, p[1] + 0.22, h, p[2] + 0.22, col, DECOR)
		first = first or stalk
		tops[i] = { p[1], h, p[2] }
	end
	for i = 1, 2 do
		local t = tops[i]
		b:vox(`Cattail{i}`, t[1], t[2] - 0.6, t[3], 0.7, 1.5, 0.7, rgb(150, 92, 52), DECOR)
	end
	b:span("Leaf", -1.3, -0.5, 0.1, -0.95, 2.6, 0.9, C.Leaf2, DECOR)
	return b:finish(first)
end

--[[
	stump: cut stump with a light cut face, two root blocks, sometimes an axe. 4-6 parts.
	opts: axe = true/false (default: by seed).
]]
function Props.stump(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Stump", cf, opts, 71)
	local o = b.opts
	b.cf = cf * quarterTurn(b)
	b.s *= b:range(0.85, 1.15)
	local main = b:span("Stump", -1.4, -0.5, -1.4, 1.4, 1.6, 1.4, C.Bark)
	b:span("CutFace", -1.1, 1.55, -1.1, 1.1, 1.72, 1.1, C.CutWood, DECOR)
	b:span("Root1", 1.3, -0.3, -0.5, 2.1, 0.6, 0.5, C.BarkDark, DECOR)
	b:span("Root2", -0.4, -0.3, -2.1, 0.5, 0.5, -1.3, C.BarkDark, DECOR)
	if o.axe == true or (o.axe == nil and b:chance(0.35)) then
		b:span("AxeHandle", 0.1, 1.7, -0.15, 0.4, 3.9, 0.15, C.WoodLight, DECOR)
		b:span("AxeHead", -0.1, 1.5, -0.1, 0.6, 2.2, 1.1, C.StoneLight, DECOR)
	end
	return b:finish(main)
end

--[[
	log: fallen block log along local X with light end faces. 3 parts. opts: length (default 6).
]]
function Props.log(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Log", cf, opts, 73)
	local o = b.opts
	local len = o.length or b:range(5.5, 7.5)
	local d = b:range(1.6, 2.0)
	local main = b:vox("Log", 0, d / 2 - 0.1, 0, len, d, d, C.Bark)
	b:vox("EndA", len / 2 + 0.05, d / 2 - 0.1, 0, 0.12, d * 0.75, d * 0.75, C.CutWood, DECOR)
	b:vox("EndB", -len / 2 - 0.05, d / 2 - 0.1, 0, 0.12, d * 0.75, d * 0.75, C.CutWood, DECOR)
	return b:finish(main)
end

-- Bright bloom colours for the cheap flower decor (no white: it reads as sugar lumps).
local BLOOMS = { C.Red, C.Yellow, C.Pink, C.Purple, C.Orange, C.Blue }

--[[
	flowerClump: cheap meadow decor — a leafy tuft with two big voxel blooms of two colours
	poking out of its top. 3 parts, all non-colliding. opts: colors = {c1, c2} (default: a pair
	by seed), leaves (tuft colour).
]]
function Props.flowerClump(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "FlowerClump", cf, opts, 251)
	local o = b.opts
	b.s *= b:range(0.9, 1.2)
	b.cf = cf * quarterTurn(b)
	local c1 = o.colors and o.colors[1] or b:pick(BLOOMS)
	local c2 = o.colors and o.colors[2] or b:pick(BLOOMS)
	if c2 == c1 then
		c2 = BLOOMS[(table.find(BLOOMS, c1) or 1) % #BLOOMS + 1]
	end
	local tw = b:range(1.6, 1.9)
	local tuft = b:span("Tuft", -tw, -0.3, -tw * 0.8, tw, 1.1, tw * 0.8, o.leaves or C.Leaf1, FOLIAGE)
	b:span("BloomA", -tw * 0.5 - 0.7, 0.75, -0.95, -tw * 0.5 + 0.7, 2.2, 0.45, c1, DECOR)
	b:span("BloomB", tw * 0.45 - 0.55, 0.8, -0.2, tw * 0.45 + 0.55, 1.95, 0.9, c2, DECOR)
	return b:finish(tuft)
end

--[[
	berryBush: cheap decor — a two-tone leaf block with a bar of berries straight through it (a
	berry pokes out of the front and one out of the back). 3 parts, all non-colliding.
	opts: leaves = {dark, mid, light}, berries = colour (default by seed).
]]
function Props.berryBush(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "BerryBush", cf, opts, 257)
	local o = b.opts
	b.s *= b:range(0.9, 1.15)
	b.cf = cf * quarterTurn(b)
	local pal = o.leaves or { C.Leaf0, C.Leaf1, C.Leaf2 }
	local berry = o.berries or b:pick({ C.Red, C.Red, C.Pink, C.Purple, C.Blue })
	local w, h, d = b:range(3.6, 4.2), b:range(2.4, 2.9), b:range(3.2, 3.8)
	local bush = b:span("Bush", -w / 2, -0.3, -d / 2, w / 2, h, d / 2, pal[2], FOLIAGE)
	local ox = b:range(-0.3, 0.3)
	b:span("BushTop", ox - w * 0.32, h - 0.1, -d * 0.3, ox + w * 0.32, h + 0.9, d * 0.3, pal[3], FOLIAGE)
	b:vox("Berries", -w * 0.2, h * 0.6, 0, 0.8, 0.8, d + 0.3, berry, DECOR)
	return b:finish(bush)
end

--------------------------------------------------------------------------------------------
-- ROCKS
--------------------------------------------------------------------------------------------

-- Stone shades of a rock: { dark, mid, light } — the light lavender rock greys by default, or
-- shades of opts.color (a cream or sandy rock).
local function rockTones(color: any?): { any }
	if color then
		return { shade(color, 0.82), color, lerpColor(color, C.White, 0.35) }
	end
	return { C.RockDark, C.RockMid, C.RockLight }
end

--[[
	rock: a small rounded voxel boulder in light lavender-grey stone, built like the tree canopies:
	a "plus" of two crossed blocks (rounded corners seen from above), a lighter, smaller block on
	top of it, off-centre, and a moss cap draped over the highest block (a band of Moss
	overhanging it all round). 1-4 parts: count 1 = one block, 2 = the rounded body, 3 = body +
	moss cap (or, without a cap, the top block), 4 = body + top block + moss cap (or a dark pebble
	at its foot). Default 3-4. opts: count, moss = false (no cap), snow = true (snow cap),
	color (body; the other stone shades follow it).
]]
function Props.rock(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Rock", cf, opts, 67)
	local o = b.opts
	b.cf = cf * quarterTurn(b)
	local t = rockTones(o.color)
	local capped = o.snow == true or o.moss ~= false
	local count = o.count or b:pick({ 3, 3, 4 })
	local sx, sy, sz = b:range(3.8, 4.8), b:range(2.2, 2.9), b:range(3.6, 4.4)
	local k = 0.68 -- how far the corners are cut
	local main = b:vox("Rock", 0, sy / 2 - 0.4, 0, sx, sy, sz * k, t[2])
	if count >= 2 then
		-- the cross block is a hair taller, so the two tops never share a plane
		b:vox("RockB", 0, sy / 2 - 0.38, 0, sx * k, sy + 0.04, sz, t[2])
	end
	local top = sy - 0.36 -- top of the highest block so far
	local tx, tz, tw, td = b:range(-0.3, 0.3), b:range(-0.3, 0.3), sx * 0.62, sz * 0.62
	if count >= 4 or (count == 3 and not capped) then
		-- a lighter block on top, off-centre, sunk 0.2 into the body
		tw, td = sx * b:range(0.5, 0.6), sz * b:range(0.5, 0.6)
		tx = (sx * k - tw) / 2 * b:range(0.3, 1) * (if b:chance(0.5) then 1 else -1)
		tz = (sz * k - td) / 2 * b:range(0.3, 1) * (if b:chance(0.5) then 1 else -1)
		local th = b:range(1.2, 1.7)
		b:vox("RockTop", tx, top - 0.2 + th / 2, tz, tw, th, td, lerpColor(t[2], t[3], 0.7))
		top += th - 0.2
	end
	if count >= 3 and capped then
		local cap = if o.snow then C.Snow else C.Moss
		b:vox("RockCap", tx, top + 0.08, tz, tw + 0.3, 0.76, td + 0.3, cap, NOSHADOW)
	elseif count >= 4 then
		local side = if b:chance(0.5) then 1 else -1
		b:vox("Pebble", side * (sx * k / 2 + 0.9), 0.2, b:range(-0.25, 0.25) * sz, 1.5, 1.0, 1.3, t[1], DECOR)
	end
	return b:finish(main)
end

--[[
	boulder: a big voxel rock (~8-11 studs) — a light lavender-grey body on a dark foot band, a
	taller, lighter block standing in one of its corners (out over its side) under a draped moss
	cap with a light moss tuft on top, and a dark broken-off chunk at its foot. 6 parts.
	opts: color (body; the other stone shades follow it), moss = false (a light stone top instead
	of the moss), snow = true (snow cap).
]]
function Props.boulder(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Boulder", cf, opts, 61)
	local o = b.opts
	b.s *= b:range(0.9, 1.15)
	b.cf = cf * quarterTurn(b)
	local t = rockTones(o.color)
	local w, d = b:range(8, 9.5), b:range(7, 8.5)
	local main = b:span("Boulder", -w / 2, -1, -d / 2, w / 2, 4.2, d / 2, t[2])
	b:span("Skirt", -w / 2 - 0.7, -1, -d / 2 + 0.9, w / 2 + 0.6, 1.5, d / 2 - 1.1, t[1])
	-- the upper block: a tall stone standing in one corner of the body, out over its side
	local uw, ud = w * b:range(0.3, 0.35), d * b:range(0.32, 0.38)
	local ux = (if b:chance(0.5) then 1 else -1) * (w / 2 - uw + b:range(0.3, 0.7))
	local uz = (if b:chance(0.5) then 1 else -1) * (d / 2 - ud - b:range(0.2, 0.8))
	b:span("Upper", ux - uw, -0.6, uz - ud, ux + uw, 6.8, uz + ud, lerpColor(t[2], t[3], 0.7))
	b:span("Chunk", -w * 0.25, -0.8, -d / 2 - 1.5, w * 0.15, 2.1, -d / 2 + 0.5, t[1])
	if o.snow or o.moss ~= false then
		local cap = if o.snow then C.Snow else C.Moss
		local tuft = if o.snow then C.Snow else C.Leaf3
		b:span("Cap", ux - uw - 0.2, 6.25, uz - ud - 0.2, ux + uw + 0.2, 7.3, uz + ud + 0.2, cap, NOSHADOW)
		local tx, tz = ux + b:range(-0.8, 0.8), uz + b:range(-0.8, 0.8)
		b:span("Tuft", tx - uw * 0.5, 7.2, tz - ud * 0.45, tx + uw * 0.5, 8.0, tz + ud * 0.45, tuft, NOSHADOW)
	else
		b:span("Top", ux - w * 0.2 + 0.5, 6.7, uz - d * 0.2, ux + w * 0.2 + 0.5, 7.8, uz + d * 0.22, t[3])
	end
	return b:finish(main)
end

--[[
	rockPair: cheap decor — a mossy rock with a light pebble rock beside it. 3 parts.
	opts: color (body; the other stone shades follow it), moss = false, snow = true.
]]
function Props.rockPair(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "RockPair", cf, opts, 263)
	local o = b.opts
	b.s *= b:range(0.85, 1.2)
	b.cf = cf * quarterTurn(b)
	local t = rockTones(o.color)
	local w, h, d = b:range(3.2, 4.0), b:range(2.4, 3.2), b:range(2.8, 3.4)
	local x0, x1 = -w / 2 - 0.7, w / 2 - 0.7
	local main = b:span("Rock", x0, -0.4, -d / 2, x1, h, d / 2, t[2])
	-- the cap covers the outer two thirds and hangs over three sides (moss on one shoulder)
	local cap = if o.snow then C.Snow elseif o.moss == false then t[3] else C.Moss
	b:span("RockCap", x0 - 0.15, h - 0.5, -d / 2 - 0.15, x0 + w * 0.66, h + 0.4, d / 2 + 0.15, cap, NOSHADOW)
	local pz = b:range(-0.6, 0.6)
	b:span("Pebble", x1 - 0.2, -0.3, pz - 1.0, x1 + 1.9, b:range(1.2, 1.6), pz + 1.0, t[3], DECOR)
	return b:finish(main)
end

--[[
	crystalCluster: glowing Neon crystal columns with stepped tips on a dark rock base.
	10 parts. opts: color = "cyan" | "purple" | "pink" | Color3 (default by seed),
	light = true (PointLight).
]]
function Props.crystalCluster(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "CrystalCluster", cf, opts, 101)
	local o = b.opts
	b.s *= b:range(0.9, 1.15)
	b.cf = cf * quarterTurn(b)
	local named = { cyan = C.Cyan, purple = C.Purple, pink = C.Pink }
	local col = if typeof(o.color) == "string" then named[o.color] else o.color
	col = col or b:pick({ C.Cyan, C.Purple })
	local second = lerpColor(col, C.White, 0.45)
	local base = b:span("Base", -2.6, -0.6, -2.2, 2.6, 1.0, 2.2, rgb(96, 88, 132))
	b:span("Base2", -1.4, -0.6, -3.2, 2.0, 0.6, -1.8, rgb(78, 72, 112), NOSHADOW)
	local cols = {
		{ 0, 0, 1.8, 7.5 },
		{ 1.7, 0.8, 1.3, 5 },
		{ -1.6, -0.4, 1.4, 4.2 },
		{ 0.6, -1.6, 1.0, 3.2 },
		{ -0.8, 1.5, 1.1, 3.6 },
	}
	for i, c in cols do
		local w = c[3]
		local h = c[4] * b:range(0.9, 1.1)
		local cc = if i % 2 == 1 then col else second
		b:span(`Crystal{i}`, c[1] - w / 2, 0.8, c[2] - w / 2, c[1] + w / 2, 0.8 + h, c[2] + w / 2, cc, NEON)
		if i <= 3 then
			local tw = w * 0.55
			b:span(
				`Tip{i}`,
				c[1] - tw / 2,
				0.8 + h - 0.05,
				c[2] - tw / 2,
				c[1] + tw / 2,
				0.8 + h + w * 0.7,
				c[2] + tw / 2,
				second,
				NEON_DECOR
			)
		end
	end
	if o.light then
		light(base, 14, 1.4, col)
	end
	if o.sparkle ~= false then
		-- glints round the tallest crystal's tip
		local tip = b:world(CFrame.new(0, 0.8 + 7.5 * 0.85, 0))
		Props.fxAt(base, tip, "sparkle", { rate = 3, size = b.s, color = CS.new(C.White, second) })
	end
	return b:finish(base)
end

--[[
	rockArch: big natural stone arch standing in the sea (cframe on the water surface; spans
	along local X, ~37 x 37 studs). Stepped legs going down to y = -14 with seaweed and foam at
	the waterline, a lintel with two corbel steps rounding the opening, a light top, a grass cap
	hanging over the edges with a little palm and a flowering bush, moss on the ledges. 33 parts.
	opts: color (stone), grass = false (bare rock: 23 parts).
]]
function Props.rockArch(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "RockArch", cf, opts, 103)
	local o = b.opts
	local t = tones(o.color or C.Stone)
	local mid2 = lerpColor(t[2], t[3], 0.45)
	local gap, legW, D = 16, 9, 11
	local first
	for i, sgn in { -1, 1 } do
		local inner = sgn * gap / 2
		local outer = sgn * (gap / 2 + legW)
		-- foot: wide dark block from the sea bed to just above the water
		local foot = b:span(`Foot{i}`, inner - sgn * 1.2, -14, -D / 2 - 1.6, outer + sgn * 1.8, 2.2, D / 2 + 1.4, t[1])
		first = first or foot
		b:span(`Lower{i}`, inner, 2.0, -D / 2, outer, 11, D / 2, t[2])
		b:span(`Upper{i}`, inner + sgn * 0.8, 10.8, -D / 2 + 0.7, outer + sgn * 0.8, 20.6, D / 2 - 0.5, t[2])
		-- a light ledge on the outside
		b:span(`Ledge{i}`, outer - sgn * 1.5, 6, -D / 2 + 1.5, outer + sgn * 1.8, 9.5, D / 2 - 2.5, mid2)
		b:span(`Moss{i}`, outer - sgn * 1.3, 9.45, -D / 2 + 1.8, outer + sgn * 1.6, 9.9, D / 2 - 3.2, C.GrassTop, DECOR)
		-- seaweed along the waterline on the front, foam cubes at the foot
		b:span(
			`Seaweed{i}`,
			inner + sgn * 1,
			-0.6,
			-D / 2 - 1.75,
			outer - sgn * 1,
			1.4,
			-D / 2 - 1.45,
			C.Seaweed,
			DECOR
		)
		b:vox(`FoamA{i}`, outer + sgn * 2.8, 0.2, -2, 2.2, 1.0, 2.6, C.Foam, DECOR)
		b:vox(`FoamB{i}`, inner - sgn * 2.0, 0.15, D / 2 + 0.7, 1.8, 0.9, 2.0, C.Foam, DECOR)
		-- two corbel steps under the lintel round the opening
		b:span(`Corbel{i}`, inner - sgn * 2.6, 16.5, -D / 2 + 0.9, inner + sgn * 1.0, 20.6, D / 2 - 0.9, t[2])
		b:span(`Corbel2{i}`, inner - sgn * 4.8, 18.8, -D / 2 + 1.2, inner - sgn * 2.4, 20.6, D / 2 - 1.2, t[2])
	end
	-- lintel, its lighter top and a dark chunk
	local W = gap + 2 * legW
	b:span("Lintel", -W / 2 + 0.4, 20.4, -D / 2 + 0.3, W / 2 - 1.2, 26.4, D / 2 - 0.2, t[2])
	b:span("LintelTop", -W / 2 + 2.4, 26.2, -D / 2 + 1.2, W / 2 - 3.6, 28.4, D / 2 - 1.0, mid2)
	b:span("Chunk", W / 2 - 6.5, 25.8, -D / 2 + 0.8, W / 2 - 1.6, 27.6, D / 2 - 2.2, t[1])
	if o.grass ~= false then
		-- grass cap hanging over the edges, a small palm, a bush with a flower
		b:span("Grass", -W / 2 + 2.9, 28.2, -D / 2 + 1.6, W / 2 - 4.1, 29.1, D / 2 - 1.4, C.GrassTop)
		b:span("GrassDrip1", -W / 2 + 3, 26.6, -D / 2 + 1.0, -W / 2 + 6.5, 29.0, -D / 2 + 1.7, C.GrassTop2, DECOR)
		b:span("GrassDrip2", W / 2 - 9, 26.5, D / 2 - 1.2, W / 2 - 5.5, 29.0, D / 2 - 0.5, C.GrassTop2, DECOR)
		local px = 4
		b:span("PalmTrunk1", px - 0.8, 29, -0.8, px + 0.8, 33, 0.8, C.PalmBark)
		b:span("PalmTrunk2", px - 0.1, 32.9, -0.7, px + 1.3, 36.4, 0.7, C.PalmBarkDark)
		b:span("PalmFrondX", px + 0.6 - 4.4, 36.3, -0.9, px + 0.6 + 4.4, 37.1, 0.9, C.Palm2, FOLIAGE)
		b:span("PalmFrondZ", px + 0.6 - 0.9, 36.35, -4.4, px + 0.6 + 0.9, 37.15, 4.4, C.Palm1, FOLIAGE)
		b:vox("Bush", -6, 30.4, 0.5, 3.6, 2.6, 3.2, C.Leaf1, FOLIAGE)
		b:vox("BushTop", -5.6, 32, 0.2, 2.2, 1.0, 2.0, C.Leaf3, FOLIAGE)
		b:vox("Flower", -4.0, 31.9, -1.3, 0.9, 0.9, 0.9, C.Pink, DECOR)
	end
	return b:finish(first)
end

--------------------------------------------------------------------------------------------
-- LIGHTS & STREET FURNITURE
--------------------------------------------------------------------------------------------

-- Cube lantern standing on local point (x, y, z): plate + Neon core + cap (+ knob). 3-4 parts.
-- k = size factor. Returns the glowing core.
local function cubeLantern(
	b: any,
	prefix: string,
	x: number,
	y: number,
	z: number,
	k: number,
	trim: any,
	withLight: boolean?,
	noKnob: boolean?
): any
	b:vox(prefix .. "Plate", x, y + 0.2 * k, z, 2.4 * k, 0.4 * k, 2.4 * k, trim, NOSHADOW)
	local core = b:vox(prefix .. "Glow", x, y + 1.4 * k, z, 1.8 * k, 2.0 * k, 1.8 * k, C.Glow, NEON)
	b:vox(prefix .. "Cap", x, y + 2.7 * k, z, 2.7 * k, 0.6 * k, 2.7 * k, trim, NOSHADOW)
	if not noKnob then
		b:vox(prefix .. "Knob", x, y + 3.25 * k, z, 1.0 * k, 0.5 * k, 1.0 * k, trim, DECOR)
	end
	if withLight then
		light(core, 16, 1.6)
	end
	return core
end

--[[
	lampPost: chunky voxel street lamp — stone foot, thick post, collar and a big cube lantern
	with a Neon core. 7 parts. opts: light = true (PointLight, use on a few key lamps),
	height (post, default 8), color (lantern trim, default Navy), post (post colour).
]]
function Props.lampPost(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "LampPost", cf, opts, 97)
	local o = b.opts
	local h = o.height or 8
	local trim = o.color or C.Navy
	b:span("Foot", -1.2, -0.4, -1.2, 1.2, 1.0, 1.2, C.StoneLight)
	local post = b:span("Post", -0.5, 0.9, -0.5, 0.5, h, 0.5, o.post or C.WoodDark)
	b:span("Collar", -0.9, h - 0.6, -0.9, 0.9, h, 0.9, trim, NOSHADOW)
	cubeLantern(b, "", 0, h - 0.05, 0, 1.25, trim, o.light == true)
	return b:finish(post)
end

--[[
	doubleLamp: post with a crossbar carrying two cube lanterns. 12 parts.
	opts: light = true (one PointLight), height (default 9), color (trim), post.
]]
function Props.doubleLamp(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "DoubleLamp", cf, opts, 99)
	local o = b.opts
	local h = o.height or 9
	local trim = o.color or C.Navy
	b:span("Foot", -1.3, -0.4, -1.3, 1.3, 1.0, 1.3, C.StoneLight)
	local post = b:span("Post", -0.55, 0.9, -0.55, 0.55, h + 1.6, 0.55, o.post or C.WoodDark)
	b:span("Bar", -3.4, h - 0.6, -0.45, 3.4, h + 0.2, 0.45, o.post or C.WoodDark, NOSHADOW)
	b:span("Top", -0.8, h + 1.6, -0.8, 0.8, h + 2.2, 0.8, trim, DECOR)
	cubeLantern(b, "L", -3.0, h + 0.15, 0, 0.95, trim, o.light == true)
	cubeLantern(b, "R", 3.0, h + 0.15, 0, 0.95, trim, false)
	return b:finish(post)
end

--[[
	torch: stick, iron bowl, Neon flame cubes. 4 parts. opts: light = true (PointLight),
	fire = true (adds a small Fire effect — use sparingly), height (default 4.6).
]]
function Props.torch(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Torch", cf, opts, 101)
	local o = b.opts
	local h = o.height or 4.6
	local stick = b:span("Stick", -0.3, -0.8, -0.3, 0.3, h, 0.3, C.WoodDark, NOSHADOW)
	b:span("Bowl", -0.65, h - 0.2, -0.65, 0.65, h + 0.4, 0.65, C.Iron, NOSHADOW)
	local flame = b:vox("Flame", 0, h + 0.85, 0, 0.9, 1.0, 0.9, C.Flame, NEON_DECOR)
	b:vox("FlameCore", 0.1, h + 1.45, 0.05, 0.5, 0.6, 0.5, C.FlameCore, NEON_DECOR)
	if o.light then
		light(flame, 12, 1.4, rgb(255, 170, 90))
	end
	if o.fire then
		U.new("Fire", { Size = 2, Heat = 4, Color = C.Flame, SecondaryColor = C.FlameCore }, flame)
	end
	return b:finish(stick)
end

--[[
	bench: two-plank seat (alternating shades), two legs, a two-plank backrest on posts; you sit
	facing -Z. 8 parts. opts: length (default 6), color (planks), legs (colour).
]]
function Props.bench(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Bench", cf, opts, 103)
	local o = b.opts
	local L = o.length or 6
	local wood = o.color or C.WoodLight
	local wood2 = shade(wood, 0.9)
	local legs = o.legs or C.WoodDark
	local seat = b:span("Seat", -L / 2, 1.6, -0.9, L / 2, 2.1, -0.02, wood)
	b:span("Seat2", -L / 2, 1.62, 0.02, L / 2, 2.08, 0.9, wood2)
	for i, x in { -L / 2 + 0.8, L / 2 - 0.8 } do
		b:span(`Leg{i}`, x - 0.4, 0, -0.85, x + 0.4, 1.62, 0.85, legs)
		b:span(`BackPost{i}`, x - 0.3, 2.0, 0.55, x + 0.3, 4.2, 1.05, legs, NOSHADOW)
	end
	b:span("Back", -L / 2, 2.5, 0.6, L / 2, 3.2, 1.0, wood, NOSHADOW)
	b:span("Back2", -L / 2, 3.45, 0.62, L / 2, 4.1, 0.98, wood2, NOSHADOW)
	return b:finish(seat)
end

--[[
	picnicTable: plank top with a red cloth runner, block legs, two bench seats and a little
	basket. 10 parts. opts: color (planks), cloth (colour).
]]
function Props.picnicTable(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "PicnicTable", cf, opts, 107)
	local o = b.opts
	local wood = o.color or C.WoodLight
	local L = 6.4
	local top = b:span("Top", -L / 2, 2.6, -1.6, L / 2, 3.1, 1.6, wood)
	b:span("Cloth", -1.6, 3.08, -1.75, 1.6, 3.2, 1.75, o.cloth or C.Red, NOSHADOW)
	for i, x in { -L / 2 + 0.9, L / 2 - 0.9 } do
		b:span(`Leg{i}`, x - 0.45, 0, -0.6, x + 0.45, 2.62, 0.6, C.WoodDark)
		b:span(`Foot{i}`, x - 0.45, 0, -3.2, x + 0.45, 1.25, 3.2, C.WoodDark)
	end
	b:span("SeatA", -L / 2, 1.2, -3.4, L / 2, 1.65, -2.2, shade(wood, 0.92))
	b:span("SeatB", -L / 2, 1.2, 2.2, L / 2, 1.65, 3.4, shade(wood, 0.92))
	b:span("Basket", 1.6, 3.15, -0.6, 2.8, 3.95, 0.5, C.Wood, DECOR)
	b:span("Apple", 0.6, 3.15, 0.3, 1.2, 3.75, 0.9, C.Red, DECOR)
	return b:finish(top)
end

-- Framed crate centred at (x, y0..y0+s, z): dark core + 3 slightly bigger light panels, so all
-- 12 edges read as a dark frame. 4 parts. Returns the core.
local function framedCrate(b: any, name: string, x: number, y0: number, z: number, s: number, panel: any): any
	local frame = shade(panel, 0.66)
	local t = s * 0.14
	local yc = y0 + s / 2
	local core = b:vox(name, x, yc, z, s, s, s, frame)
	b:vox(name .. "PanelX", x, yc, z, s + 0.1, s - 2 * t, s - 2 * t, panel, NOSHADOW)
	b:vox(name .. "PanelZ", x, yc, z, s - 2 * t, s - 2 * t, s + 0.1, panel, NOSHADOW)
	b:vox(name .. "PanelY", x, yc, z, s - 2 * t, s + 0.1, s - 2 * t, lerpColor(panel, C.White, 0.12), NOSHADOW)
	return core
end

--[[
	crate: framed wooden crate (dark edges, light panels). 4 parts. opts: size (default 3), color.
]]
function Props.crate(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Crate", cf, opts, 107)
	local o = b.opts
	local core = framedCrate(b, "Crate", 0, 0, 0, o.size or 3, o.color or C.WoodLight)
	return b:finish(core)
end

--[[
	crateStack: three framed crates — two side by side, one on top; one is painted. 12 parts.
	opts: color (painted crate).
]]
function Props.crateStack(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "CrateStack", cf, opts, 109)
	local o = b.opts
	b.cf = cf * quarterTurn(b)
	local painted = o.color or b:pick({ C.Cyan, C.Red, C.Blue, C.Yellow })
	local main = framedCrate(b, "CrateA", -1.6, 0, 0, 3, C.WoodLight)
	framedCrate(b, "CrateB", 1.5, 0, 0.3, 2.6, painted)
	framedCrate(b, "CrateTop", -1.2, 3, 0.15, 2.2, shade(C.WoodLight, 0.94))
	return b:finish(main)
end

--[[
	barrel: wooden barrel with two iron hoops and a lighter lid. 4 parts. opts: color.
]]
function Props.barrel(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Barrel", cf, opts, 113)
	local o = b.opts
	local wood = o.color or C.Wood
	local body = b:column("Barrel", 2.6, 0, 0, -0.1, 3.4, wood)
	b:column("HoopLow", 2.78, 0, 0, 0.5, 0.9, C.Iron, nil, NOSHADOW)
	b:column("HoopHigh", 2.78, 0, 0, 2.4, 2.8, C.Iron, nil, NOSHADOW)
	b:column("Lid", 2.1, 0, 0, 3.35, 3.5, lerpColor(wood, C.White, 0.25), nil, DECOR)
	return b:finish(body)
end

--[[
	hayBale: cheap farm decor — a straw block along local X with a light top layer and a twine
	band round its middle. 3 parts. opts: length (default 4.4), color (straw).
]]
function Props.hayBale(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "HayBale", cf, opts, 269)
	local o = b.opts
	local L = o.length or 4.4
	local straw = o.color or C.Straw
	local bale = b:span("Bale", -L / 2, -0.2, -1.4, L / 2, 2.3, 1.4, straw)
	b:span("BaleTop", -L / 2 + 0.15, 2.3, -1.25, L / 2 - 0.15, 2.8, 1.25, lerpColor(straw, C.StrawLight, 0.8), NOSHADOW)
	b:span("Twine", -0.3, -0.1, -1.55, 0.3, 2.95, 1.55, C.Twine, DECOR)
	return b:finish(bale)
end

--[[
	fenceSegment: chunky picket fence centred on cframe, running along local X: two rails, thick
	posts with coloured caps at the ends (+ a middle post when longer than 10) and pickets
	between. <= 12 parts. opts: length (default 8), posts = "both" | "start" | "end" | "none"
	(for chaining), height (default 3.4), color (pickets/rails, default White), trim (cap
	colour, default Red), style = "picket" (default) | "rail" (rustic: wooden posts + 2 rails).
]]
function Props.fenceSegment(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Fence", cf, opts, 127)
	local o = b.opts
	local L = o.length or 8
	local h = o.height or 3.4
	local posts = o.posts or "both"
	local rustic = o.style == "rail"
	local main = o.color or (if rustic then C.Wood else C.White)
	local postC = if rustic then C.WoodDark else main
	local trim = o.trim or (if rustic then C.WoodLight else C.Red)
	local rail = b:span("RailTop", -L / 2, h * 0.68, -0.15, L / 2, h * 0.68 + 0.5, 0.35, main)
	b:span("RailLow", -L / 2, h * 0.24, -0.15, L / 2, h * 0.24 + 0.5, 0.35, main)
	local xs = {}
	if posts == "both" or posts == "start" then
		table.insert(xs, -L / 2)
	end
	if posts == "both" or posts == "end" then
		table.insert(xs, L / 2)
	end
	if L > 10 then
		table.insert(xs, 0)
	end
	for i, x in xs do
		b:span(`Post{i}`, x - 0.5, -0.6, -0.5, x + 0.5, h + 0.4, 0.5, postC)
		if i <= 2 then
			b:span(`Cap{i}`, x - 0.65, h + 0.4, -0.65, x + 0.65, h + 0.85, 0.65, trim, NOSHADOW)
		end
	end
	if not rustic then
		-- pickets in front of the rails, every ~1.6 studs between the posts
		local n = math.clamp(math.floor(L / 1.6) - 1, 0, 12 - 2 - #xs * 2 + (if #xs > 2 then 1 else 0))
		local step = L / (n + 1)
		for k = 1, n do
			local x = -L / 2 + k * step
			if L <= 10 or math.abs(x) > 0.9 then
				b:span(`Picket{k}`, x - 0.35, -0.3, -0.45, x + 0.35, h, -0.15, main, NOSHADOW)
			end
		end
	end
	return b:finish(rail)
end

--[[
	fenceLine: fence along a polyline of world points (ground level), no doubled posts.
	opts are passed to fenceSegment (height, color, trim, style). Returns a Model of segments.
]]
function Props.fenceLine(parent: any, points: { any }, opts: { [string]: any }?): any
	local model = U.model(parent, (opts and opts.name) or "FenceLine")
	for i = 1, #points - 1 do
		local a, c = points[i], points[i + 1]
		local mid = (a + c) / 2
		local d = c - a
		local flat = Vector3.new(d.X, 0, d.Z)
		local cf = CFrame.fromMatrix(mid, flat.Unit, UP, flat.Unit:Cross(UP))
		local o = merge(opts, {
			length = flat.Magnitude,
			posts = if i == #points - 1 then "both" else "start",
			seed = i,
			name = `Fence{i}`,
		})
		local seg = Props.fenceSegment(model, cf, o)
		if not model.PrimaryPart then
			model.PrimaryPart = seg.PrimaryPart
		end
	end
	return model
end

--[[
	signpost: chunky post with a cap + a framed board with big text on both sides. 4-5 parts.
	opts: text (default "→"), textColor, color (board), trim (frame/cap colour), width (default 5),
	arrow = "left" | "right" (stepped arrow tip on that end, as seen from the front).
]]
function Props.signpost(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Signpost", cf, opts, 131)
	local o = b.opts
	local w = o.width or 5
	local trim = o.trim or C.Red
	local post = b:span("Post", -0.45, -0.8, -0.45, 0.45, 6.2, 0.45, C.WoodDark)
	b:span("PostCap", -0.65, 6.2, -0.65, 0.65, 6.7, 0.65, trim, NOSHADOW)
	b:span("Frame", -w / 2 - 0.25, 3.25, -0.95, w / 2 + 0.25, 5.75, -0.45, trim)
	local board = b:span("Board", -w / 2, 3.45, -1.05, w / 2, 5.55, -0.35, o.color or C.Cream)
	if o.arrow == "left" or o.arrow == "right" then
		-- stepped arrow tip on one end of the board
		local sg = if o.arrow == "right" then -1 else 1 -- the viewer's right is local -X
		b:span("ArrowTip", sg * (w / 2 + 0.2), 3.75, -1.0, sg * (w / 2 + 1.1), 5.25, -0.4, trim, NOSHADOW)
	end
	local text = o.text or "→"
	local tc = o.textColor or rgb(96, 56, 30)
	addSignText(board, Enum.NormalId.Front, text, tc)
	if o.twoSided ~= false then
		addSignText(board, Enum.NormalId.Back, text, tc)
	end
	return b:finish(post)
end

--[[
	billboard(parent, cframe, {text, color, width, height}): big sign board on two thick posts,
	facing -Z. Trim frame, Neon rim strips top and bottom, a coloured cap; white text with a dark
	outline on the front. 9 parts. opts: text, color (board, default Blue), trim (default White),
	rim (Neon colour, default Yellow), width (default 16), height (default 6), lift (board bottom
	above the ground, default 3), textColor, back = true (text on the back as well).
]]
function Props.billboard(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Billboard", cf, opts, 133)
	local o = b.opts
	local W = o.width or 16
	local H = o.height or 6
	local y0 = o.lift or 3
	local boardC = o.color or C.Blue
	local trim = o.trim or C.White
	local rim = o.rim or C.Yellow
	local first
	for i, x in { -W / 2 + 1.6, W / 2 - 1.6 } do
		local p = b:span(`Post{i}`, x - 0.75, -1, 0.2, x + 0.75, y0 + H - 0.4, 1.7, C.WoodDark)
		first = first or p
		b:span(`Foot{i}`, x - 1.1, -0.4, -0.15, x + 1.1, 0.8, 2.05, C.StoneLight, NOSHADOW)
	end
	b:span("Frame", -W / 2 - 0.6, y0 - 0.6, -0.4, W / 2 + 0.6, y0 + H + 0.6, 0.25, trim)
	local board = b:span("Board", -W / 2, y0, -0.6, W / 2, y0 + H, 0.1, boardC)
	b:span("RimTop", -W / 2 - 0.6, y0 + H + 0.6, -0.5, W / 2 + 0.6, y0 + H + 1.0, 0.25, rim, NEON)
	b:span("RimBottom", -W / 2 - 0.6, y0 - 1.0, -0.5, W / 2 + 0.6, y0 - 0.6, 0.25, rim, NEON)
	b:span("Cap", -W / 2 - 1.0, y0 + H + 1.0, -0.8, W / 2 + 1.0, y0 + H + 1.7, 0.6, shade(boardC, 0.8))
	local text = o.text or "РЫБАЛКА"
	addSignText(board, Enum.NormalId.Front, text, o.textColor or C.White, C.Navy)
	if o.back then
		addSignText(board, Enum.NormalId.Back, text, o.textColor or C.White, C.Navy)
	end
	return b:finish(first)
end

--[[
	flowerBox: painted planter box with a light rim, greenery and 4 cube flowers. 7 parts.
	opts: length (default 4), colors = {c1, c2}, color (box).
]]
function Props.flowerBox(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "FlowerBox", cf, opts, 137)
	local o = b.opts
	local L = o.length or 4
	local c1 = o.colors and o.colors[1] or b:pick(C.Flowers)
	local c2 = o.colors and o.colors[2] or b:pick(C.Flowers)
	local boxC = o.color or C.Wood
	local box = b:span("Box", -L / 2, 0, -0.7, L / 2, 1.2, 0.7, boxC)
	b:span("Rim", -L / 2 - 0.15, 1.15, -0.85, L / 2 + 0.15, 1.45, 0.85, lerpColor(boxC, C.White, 0.3), NOSHADOW)
	b:span("Greens", -L / 2 + 0.25, 1.2, -0.5, L / 2 - 0.25, 1.95, 0.5, C.Leaf1, DECOR)
	for i = 1, 4 do
		local x = -L / 2 + 0.3 + (L - 0.6) * (i - 0.5) / 4
		local z = if i % 2 == 0 then 0.18 else -0.18
		b:vox(`Flower{i}`, x, 2.1 + (i % 2) * 0.12, z, 0.75, 0.6, 0.75, if i % 2 == 1 then c1 else c2, DECOR)
	end
	return b:finish(box)
end

--[[
	planter: square raised bed (4 studs) with a light rim and soil, planted with a bush,
	flowers or a topiary cube on a stick. 6-8 parts.
	opts: variant = "bush" | "flowers" | "topiary" (default by seed), color (box), colors.
]]
function Props.planter(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Planter", cf, opts, 139)
	local o = b.opts
	local variant = o.variant or b:pick({ "bush", "flowers", "topiary" })
	local boxC = o.color or b:pick({ C.White, C.Cream, C.Wood, C.Blue })
	local box = b:span("Box", -2, 0, -2, 2, 1.8, 2, boxC)
	b:span("Rim", -2.25, 1.75, -2.25, 2.25, 2.15, 2.25, shade(boxC, 0.82), NOSHADOW)
	b:span("Soil", -1.7, 1.8, -1.7, 1.7, 2.05, 1.7, C.DirtDark, DECOR)
	if variant == "topiary" then
		b:span("Stick", -0.25, 2.0, -0.25, 0.25, 4.4, 0.25, C.WoodDark, NOSHADOW)
		b:cross("Topiary", 0, 4.2, 0, 6.6, 3.0, 3.0, 0.72, C.Leaf1, FOLIAGE)
		b:span("TopiaryTop", -1.0, 6.5, -1.0, 1.0, 7.1, 1.0, C.Leaf3, FOLIAGE)
	elseif variant == "flowers" then
		local cs = o.colors or { b:pick(C.Flowers), b:pick(C.Flowers) }
		b:span("Greens", -1.5, 2.0, -1.5, 1.5, 2.8, 1.5, C.Leaf1, FOLIAGE)
		for i, p in { { -0.8, -0.8 }, { 0.8, -0.6 }, { -0.6, 0.8 }, { 0.8, 0.8 } } do
			b:vox(`Flower{i}`, p[1], 3.05, p[2], 0.85, 0.6, 0.85, cs[(i - 1) % 2 + 1], DECOR)
		end
	else
		b:span("Bush", -1.5, 2.0, -1.5, 1.5, 4.0, 1.5, C.Leaf1, FOLIAGE)
		b:span("BushTop", -1.0, 3.9, -0.8, 0.9, 4.8, 1.1, C.Leaf3, FOLIAGE)
		b:vox("Berry", 1.52, 3.2, -0.5, 0.5, 0.6, 0.6, C.Red, DECOR)
	end
	return b:finish(box)
end

--[[
	bunting: colourful flags on a rope between two world points with a gentle sag:
	2 rope segments + n voxel banners (a flag block with a short tip block). <= 16 parts.
	opts: sag (default 8% of length), colors (list), count (flags, default by length, 3..7).
]]
function Props.bunting(parent: any, fromPos: any, toPos: any, opts: { [string]: any }?): any
	local o = opts or {}
	local mid = (fromPos + toPos) / 2
	local d = toPos - fromPos
	local L = d.Magnitude
	local flat = Vector3.new(d.X, 0, d.Z)
	local along = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(1, 0, 0)
	local cf = CFrame.lookAt(mid, mid + along)
	local b = begin(parent, "Bunting", cf, o, 139)
	b.cf = CFrame.new() -- build directly in world space
	b.s = 1
	local sag = o.sag or L * 0.08
	local low = mid - Vector3.new(0, sag, 0)
	local first = b:beam("RopeA", fromPos, low, 0.18, 0.18, C.Rope, DECOR)
	b:beam("RopeB", low, toPos, 0.18, 0.18, C.Rope, DECOR)
	local colors = o.colors or C.Festive
	local n = o.count or math.clamp(math.floor(L / 3.2), 3, 7)
	local size = math.clamp(L / (n + 1) * 0.7, 1.0, 2.4)
	local offset = b:int(0, #colors - 1)
	local zAxis = along:Cross(UP).Unit
	for i = 1, n do
		local t = i / (n + 1)
		local p
		if t <= 0.5 then
			p = fromPos + (low - fromPos) * (t * 2)
		else
			p = low + (toPos - low) * ((t - 0.5) * 2)
		end
		local col = colors[1 + (offset + i - 1) % #colors]
		local top = p - Vector3.new(0, 0.05, 0)
		-- wide upper block + narrow lower block = a stepped pennant
		local h1, h2 = size * 0.8, size * 0.3
		b:block(
			`Flag{i}`,
			Vector3.new(size, h1, 0.2),
			CFrame.fromMatrix(top - Vector3.new(0, h1 / 2, 0), along, UP, zAxis),
			col,
			nil,
			DECOR
		)
		b:block(
			`FlagTip{i}`,
			Vector3.new(size * 0.55, h2, 0.2),
			CFrame.fromMatrix(top - Vector3.new(0, h1 + h2 / 2 - 0.02, 0), along, UP, zAxis),
			col,
			nil,
			DECOR
		)
	end
	return b:finish(first)
end

--[[
	flagPole: stone base, white pole, gold top cube and a two-colour voxel flag pointing along
	local +X. 6 parts. opts: height (default 12), color (flag), stripe (colour, default White).
]]
function Props.flagPole(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "FlagPole", cf, opts, 149)
	local o = b.opts
	local h = o.height or 12
	local flagC = o.color or b:pick(C.Festive)
	b:span("Base", -1.0, -0.4, -1.0, 1.0, 0.8, 1.0, C.StoneLight)
	local pole = b:column("Pole", 0.5, 0, 0, 0.7, h, C.White)
	b:vox("Top", 0, h + 0.35, 0, 0.9, 0.9, 0.9, C.Gold, DECOR)
	b:span("Flag", 0.25, h - 3.2, -0.1, 4.6, h - 0.4, 0.1, flagC, FOLIAGE)
	b:span("Stripe", 0.25, h - 2.15, -0.13, 4.62, h - 1.45, 0.13, o.stripe or C.White, FOLIAGE)
	b:span("FlagTail", 4.6, h - 2.6, -0.1, 5.4, h - 1.0, 0.1, flagC, FOLIAGE)
	return b:finish(pole)
end

--[[
	campfire: ring of stone cubes, two crossed block logs, Neon flame cubes, rising embers and a
	thin smoke trail (particles). 10 parts.
	opts: light = true (PointLight), fire = true (Fire effect), smoke = false (no particles).
]]
function Props.campfire(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Campfire", cf, opts, 151)
	local o = b.opts
	local ring
	local stones = { { 1.6, 0 }, { -1.6, 0.2 }, { 0.2, 1.6 }, { -0.1, -1.6 }, { 1.2, 1.2 }, { -1.2, -1.1 } }
	for i, s in stones do
		local w = if i % 2 == 0 then 1.0 else 1.2
		local stone = b:vox(`Stone{i}`, s[1], 0.3, s[2], w, 0.9, w, if i % 3 == 0 then C.StoneLight else C.Stone)
		ring = ring or stone
	end
	b:vox("LogA", 0, 0.35, 0, 3.0, 0.7, 0.75, C.Bark, DECOR)
	b:vox("LogB", 0, 0.9, 0, 0.75, 0.7, 3.0, C.BarkDark, DECOR)
	local flame = b:vox("Flame", 0, 1.9, 0, 1.6, 2.0, 1.6, C.Flame, NEON_DECOR)
	b:vox("FlameCore", 0.15, 3.2, -0.1, 0.9, 1.3, 0.9, C.FlameCore, NEON_DECOR)
	if o.light then
		light(flame, 14, 1.6, rgb(255, 170, 90))
	end
	if o.fire then
		U.new("Fire", { Size = 3, Heat = 6, Color = C.Flame, SecondaryColor = C.FlameCore }, flame)
	end
	if o.smoke ~= false then
		-- glowing embers out of the flames, a thin trail of smoke above them
		Props.fx(flame, "embers", { size = b.s })
		Props.fxAt(flame, b:world(CFrame.new(0, 4.2, 0)), "smoke", { size = b.s * 0.8, rate = 1.5 })
	end
	return b:finish(ring)
end

--[[
	parasol: beach umbrella — base, white pole, three-step striped canopy, knob. 6 parts.
	opts: color (canopy, default by seed).
]]
function Props.parasol(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Parasol", cf, opts, 157)
	local o = b.opts
	local col = o.color or b:pick({ C.Red, C.Blue, C.Yellow, C.Cyan, C.Pink, C.Orange })
	b:span("Base", -0.7, -0.3, -0.7, 0.7, 0.3, 0.7, C.White, NOSHADOW)
	local pole = b:column("Pole", 0.35, 0, 0, 0, 6.6, C.White, nil, NOSHADOW)
	b:span("Canopy", -3.6, 5.3, -3.6, 3.6, 5.9, 3.6, col, FOLIAGE)
	b:span("CanopyMid", -2.5, 5.85, -2.5, 2.5, 6.45, 2.5, C.White, FOLIAGE)
	b:span("CanopyTop", -1.4, 6.4, -1.4, 1.4, 7.0, 1.4, col, FOLIAGE)
	b:vox("Knob", 0, 7.25, 0, 0.6, 0.5, 0.6, C.White, DECOR)
	return b:finish(pole)
end

--[[
	beachChair: deck chair with a striped seat and a stepped (reclined) backrest, facing -Z.
	7 parts. opts: color (stripes, default by seed).
]]
function Props.beachChair(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "BeachChair", cf, opts, 159)
	local o = b.opts
	local col = o.color or b:pick({ C.Red, C.Blue, C.Cyan, C.Pink, C.Orange })
	local frame = C.WoodLight
	local main = b:span("RailL", -1.5, 0.6, -2.4, -1.2, 0.9, 2.2, frame)
	b:span("RailR", 1.2, 0.6, -2.4, 1.5, 0.9, 2.2, frame)
	b:span("LegFront", -1.5, 0, -2.4, 1.5, 0.65, -2.0, frame, NOSHADOW)
	b:span("LegBack", -1.5, 0, 1.0, 1.5, 0.65, 1.4, frame, NOSHADOW)
	b:span("Seat", -1.2, 0.7, -2.3, 1.2, 0.95, 0.9, col)
	b:span("BackLow", -1.2, 0.9, 0.9, 1.2, 2.2, 1.35, C.White)
	b:span("BackHigh", -1.2, 2.1, 1.3, 1.2, 3.4, 1.75, col)
	return b:finish(main)
end

--[[
	cooler: bright cooler box with a white lid and handle. 4 parts. opts: color.
]]
function Props.cooler(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Cooler", cf, opts, 161)
	local o = b.opts
	local col = o.color or b:pick({ C.Blue, C.Red, C.Cyan })
	local body = b:span("Body", -1.2, 0, -0.8, 1.2, 1.5, 0.8, col)
	b:span("Lid", -1.3, 1.45, -0.9, 1.3, 1.95, 0.9, C.White, NOSHADOW)
	b:span("Handle", -0.7, 1.9, -0.15, 0.7, 2.25, 0.15, C.White, DECOR)
	b:span("Stripe", -1.22, 0.5, -0.82, 1.22, 0.8, 0.82, lerpColor(col, C.White, 0.45), DECOR)
	return b:finish(body)
end

--[[
	treasureChest: wooden chest with gold bands and lock. Open (default): the lid stands up at the
	back and a glowing pile of gold with gems fills it. 7-9 parts. opts: open = false.
]]
function Props.treasureChest(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "TreasureChest", cf, opts, 163)
	local o = b.opts
	local body = b:span("Body", -1.8, 0, -1.2, 1.8, 1.8, 1.2, C.Wood)
	for i, x in { -1.15, 1.15 } do
		b:span(`Band{i}`, x - 0.22, -0.02, -1.27, x + 0.22, 1.85, 1.27, C.Gold, NOSHADOW)
	end
	b:span("Lock", -0.35, 0.9, -1.4, 0.35, 1.7, -1.15, C.GoldLight, DECOR)
	if o.open == false then
		b:span("Lid", -1.85, 1.8, -1.25, 1.85, 2.5, 1.25, C.WoodDark)
		b:span("LidTop", -1.85, 2.45, -0.75, 1.85, 2.95, 0.75, C.WoodDark)
		b:span("LidBand", -0.25, 1.8, -1.3, 0.25, 3.0, 1.3, C.Gold, NOSHADOW)
	else
		b:span("Lid", -1.85, 1.8, 1.0, 1.85, 4.2, 1.6, C.WoodDark)
		local gold = b:span("Gold", -1.6, 1.4, -1.0, 1.6, 2.3, 1.0, C.Gold, NEON_DECOR)
		Props.fx(gold, "sparkle", { rate = 2, size = b.s })
		b:span("GoldTop", -0.9, 2.25, -0.6, 0.8, 2.7, 0.6, C.GoldLight, NEON_DECOR)
		b:vox("Gem1", -1.0, 2.5, -0.3, 0.6, 0.6, 0.6, C.Red, DECOR)
		b:vox("Gem2", 1.0, 2.45, 0.2, 0.55, 0.55, 0.55, C.Cyan, DECOR)
	end
	return b:finish(body)
end

--[[
	anchor: big decorative anchor standing on its crown: shaft, stock, ring, arms and flukes.
	10 parts. opts: color (default Navy), ring (colour, default Gold).
]]
function Props.anchor(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Anchor", cf, opts, 167)
	local o = b.opts
	local col = o.color or C.Navy
	local ring = o.ring or C.Gold
	local shaft = b:span("Shaft", -0.55, 0, -0.55, 0.55, 8.2, 0.55, col)
	b:span("Stock", -2.4, 6.6, -0.45, 2.4, 7.4, 0.45, col)
	b:span("RingL", -0.95, 8.0, -0.25, -0.45, 9.6, 0.25, ring, NOSHADOW)
	b:span("RingR", 0.45, 8.0, -0.25, 0.95, 9.6, 0.25, ring, NOSHADOW)
	b:span("RingTop", -0.95, 9.5, -0.25, 0.95, 10.0, 0.25, ring, NOSHADOW)
	b:span("Crown", -3.4, 0, -0.6, 3.4, 1.1, 0.6, col)
	for i, sgn in { -1, 1 } do
		b:span(`Arm{i}`, sgn * 3.4 - 0.55, 0.9, -0.55, sgn * 3.4 + 0.55, 3.0, 0.55, col)
		b:span(`Fluke{i}`, sgn * 3.4 - 0.9 + sgn * 0.3, 2.6, -0.75, sgn * 3.4 + 0.9 + sgn * 0.3, 3.6, 0.75, col)
	end
	return b:finish(shaft)
end

--[[
	fishStatue: big chunky voxel fish (~11 studs) on a two-tier pedestal: body, lighter belly,
	head, open-tail V, dorsal and side fins, big cartoon eyes and lips. 18 parts.
	opts: color (fish, default Orange), belly, pedestal (colour), trim (pedestal band, Gold).
]]
function Props.fishStatue(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "FishStatue", cf, opts, 171)
	local o = b.opts
	local col = o.color or C.Orange
	local t = tones(col)
	local belly = o.belly or lerpColor(col, C.Cream, 0.6)
	local ped = o.pedestal or C.StoneLight
	local base = b:span("Pedestal", -3.2, -0.5, -3.2, 3.2, 1.2, 3.2, ped)
	b:span("PedestalMid", -2.5, 1.2, -2.5, 2.5, 4.2, 2.5, lerpColor(ped, C.White, 0.3))
	b:span("PedestalTop", -2.9, 4.2, -2.9, 2.9, 5.0, 2.9, o.trim or C.Gold)
	b:span("Stand", -0.5, 5.0, -0.5, 0.5, 6.4, 0.5, C.Iron, NOSHADOW)
	-- the fish lies along X (head at -X), side view towards -Z; centre line y = 9
	local y = 9
	b:span("Body", -3.6, y - 2.4, -1.5, 2.6, y + 2.4, 1.5, t[2])
	b:span("Belly", -3.4, y - 2.9, -1.35, 2.2, y - 1.0, 1.35, belly)
	b:span("Head", -5.6, y - 1.8, -1.3, -3.5, y + 1.9, 1.3, t[3])
	b:span("Lips", -6.3, y - 0.9, -0.8, -5.5, y + 0.1, 0.8, C.Pink)
	b:span("TailStem", 2.5, y - 1.2, -0.9, 4.4, y + 1.2, 0.9, t[2])
	b:span("TailUp", 4.0, y + 0.4, -0.5, 5.6, y + 3.4, 0.5, t[1])
	b:span("TailDown", 4.0, y - 3.2, -0.5, 5.6, y - 0.2, 0.5, t[1])
	b:span("Dorsal", -2.0, y + 2.3, -0.4, 1.4, y + 3.8, 0.4, t[1])
	b:span("FinL", -1.8, y - 1.6, -2.1, 0.0, y - 0.6, -1.4, t[1], NOSHADOW)
	b:span("FinR", -1.8, y - 1.6, 1.4, 0.0, y - 0.6, 2.1, t[1], NOSHADOW)
	for i, sz in { -1, 1 } do
		b:span(`Eye{i}`, -5.4, y - 0.1, sz * 1.2, -3.6, y + 1.7, sz * 1.45, C.White, DECOR)
		b:span(`Pupil{i}`, -5.2, y + 0.1, sz * 1.42, -4.3, y + 1.1, sz * 1.56, C.Dark, DECOR)
	end
	return b:finish(base)
end

--[[
	lifebuoy: square red/white ring mounted on a wall or post: cframe = ring centre, front (-Z)
	facing out. 4 parts. opts: color (default Red).
]]
function Props.lifebuoy(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Lifebuoy", cf, opts, 179)
	local o = b.opts
	local red = o.color or C.Red
	local main = b:span("RingTop", -1.5, 0.8, -0.35, 1.5, 1.6, 0.35, red, DECOR)
	b:span("RingBottom", -1.5, -1.6, -0.35, 1.5, -0.8, 0.35, red, DECOR)
	b:span("RingLeft", -1.5, -0.8, -0.3, -0.7, 0.8, 0.3, C.White, DECOR)
	b:span("RingRight", 0.7, -0.8, -0.3, 1.5, 0.8, 0.3, C.White, DECOR)
	return b:finish(main)
end

--[[
	fishingRodRack: base plank, two posts, a top bar; three bright rods standing in it, each
	with a reel, and a tackle box. 11 parts. Faces -Z.
]]
function Props.fishingRodRack(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "RodRack", cf, opts, 191)
	local main = b:span("Base", -2.9, 0, -0.9, 2.9, 0.6, 0.9, C.WoodDark)
	for i, x in { -2.5, 2.5 } do
		b:span(`Post{i}`, x - 0.3, 0.6, -0.3, x + 0.3, 4.8, 0.3, C.Wood)
	end
	b:span("Bar", -2.9, 3.8, -0.75, 2.9, 4.4, -0.25, C.Wood, NOSHADOW)
	local rodColors = { C.Red, C.Yellow, C.Blue }
	for i = 1, 3 do
		local x = -1.4 + (i - 1) * 1.4
		b:span(`Rod{i}`, x - 0.15, 0.5, -0.65, x + 0.15, 8.2, -0.35, rodColors[i], DECOR)
		b:span(`Reel{i}`, x - 0.4, 1.8, -1.05, x + 0.4, 2.5, -0.6, C.White, DECOR)
	end
	b:span("Tackle", -0.6, 0.6, -0.8, 0.6, 1.3, 0.2, C.Cyan, NOSHADOW)
	return b:finish(main)
end

--------------------------------------------------------------------------------------------
-- WATER THINGS
--------------------------------------------------------------------------------------------

--[[
	Bobbing: the client (AmbientController) gently lifts and rolls every Model with a number
	attribute Bob (amplitude, studs; BobPeriod in seconds) about its pivot, which for boats and
	buoys is the waterline point. opts.bob = amplitude (0 or false: keep still), opts.bobPeriod.
	Default: they bob when their cframe stands on the water (within 1 stud of Props.waterTop), so
	a boat on trestles or on a beach stays put.
]]
local function bobbing(b: any, amplitude: number, period: number)
	local o = b.opts
	local a = o.bob
	if a == nil then
		a = if math.abs(b.pivot.Position.Y - Props.waterTop) <= 1 then amplitude else 0
	end
	if typeof(a) == "number" and a > 0 then
		b.model:SetAttribute("Bob", a)
		b.model:SetAttribute("BobPeriod", o.bobPeriod or period)
	end
end

--[[
	Shared voxel hull, bow towards -Z: floor slab, painted side walls, transom, a two-step
	pointed bow and white gunwale trims. 8 parts. Returns the floor.
	L = overall length, W = beam, y0 = hull bottom, deckY = inside floor, rimY = gunwale top.
]]
local function voxelHull(
	b: any,
	L: number,
	W: number,
	y0: number,
	deckY: number,
	rimY: number,
	paint: any,
	trim: any
): any
	local hw = W / 2
	local bowLen = L * 0.26
	local zb = -L / 2 + bowLen -- where the pointed bow begins
	local wall = 0.55
	local floor = b:span("Hull", -hw + 0.3, y0 + 0.4, zb + 0.05, hw - 0.3, deckY, L / 2 - 0.3, C.WoodLight)
	b:span("SideL", -hw, y0 + 0.2, zb, -hw + wall, rimY, L / 2, paint)
	b:span("SideR", hw - wall, y0 + 0.2, zb, hw, rimY, L / 2, paint)
	b:span("Transom", -hw + 0.12, y0 + 0.3, L / 2 - wall, hw - 0.12, rimY - 0.1, L / 2 + 0.1, shade(paint, 0.85))
	b:span("Bow1", -hw * 0.74, y0 + 0.35, zb - bowLen * 0.55, hw * 0.74, rimY + 0.05, zb + 0.3, paint)
	b:span("Bow2", -hw * 0.4, y0 + 0.7, -L / 2, hw * 0.4, rimY + 0.15, zb - bowLen * 0.5, paint)
	b:span("TrimL", -hw - 0.08, rimY - 0.02, zb - 0.1, -hw + wall + 0.08, rimY + 0.3, L / 2 + 0.08, trim, NOSHADOW)
	b:span("TrimR", hw - wall - 0.08, rimY - 0.02, zb - 0.1, hw + 0.08, rimY + 0.3, L / 2 + 0.08, trim, NOSHADOW)
	return floor
end

--[[
	rowboat: voxel hull, two seats, two oars with yellow blades resting along the sides.
	14 parts. cframe on the water surface, bow = -Z. opts: color (paint, default from
	Colors.BoatPaint), oars = false, bob / bobPeriod (see bobbing).
]]
function Props.rowboat(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Rowboat", cf, opts, 163)
	local o = b.opts
	local paint = o.color or b:pick(C.BoatPaint)
	local trim = if paint == C.BoatPaint[5] then C.Blue else C.White
	local floor = voxelHull(b, 9.6, 4.0, -0.8, 0.2, 1.3, paint, trim)
	b:span("SeatFront", -1.5, 0.75, -1.4, 1.5, 1.05, -0.5, C.WoodLight, NOSHADOW)
	b:span("SeatBack", -1.5, 0.75, 2.4, 1.5, 1.05, 3.4, C.WoodLight, NOSHADOW)
	if o.oars ~= false then
		for i, sx in { -1, 1 } do
			b:span(`Oar{i}`, sx * 2.05 - 0.15, 1.6, -2.6, sx * 2.05 + 0.15, 1.85, 3.0, C.WoodDark, DECOR)
			b:span(`Blade{i}`, sx * 2.05 - 0.3, 1.55, 3.0, sx * 2.05 + 0.3, 1.9, 4.6, C.Yellow, DECOR)
		end
	end
	bobbing(b, 0.3, 2.8)
	return b:finish(floor)
end

--[[
	sailboat: bigger voxel hull with a cabin (windows), a mast, a boom, a stepped (triangular)
	main sail with a coloured stripe, a stepped jib and a pennant. 21 parts. cframe on the water
	surface, bow = -Z. opts: color (hull paint), sailColor, stripe (sail stripe colour), bob /
	bobPeriod (see bobbing).
]]
function Props.sailboat(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Sailboat", cf, opts, 167)
	local o = b.opts
	local paint = o.color or b:pick(C.BoatPaint)
	local trim = if paint == C.BoatPaint[5] then C.Blue else C.White
	local sail = o.sailColor or C.Sail
	local stripe = o.stripe or (if paint == C.BoatPaint[5] then C.Red else paint)
	local L, W = 17, 6.4
	local deckY = 0.9
	local floor = voxelHull(b, L, W, -1.2, deckY, 2.0, paint, trim)
	-- cabin
	b:span("Cabin", -1.9, deckY, 1.6, 1.9, deckY + 2.2, 5.4, C.Cream)
	b:span("CabinRoof", -2.2, deckY + 2.15, 1.3, 2.2, deckY + 2.75, 5.7, paint, NOSHADOW)
	b:span("Windows", -1.95, deckY + 0.9, 2.6, 1.95, deckY + 1.6, 4.4, C.WindowBlue, DECOR)
	-- mast and boom
	local mz = -1.4
	local mastH = 16
	b:span("Mast", -0.35, deckY, mz - 0.35, 0.35, deckY + mastH, mz + 0.35, C.White)
	b:span("Boom", -0.25, deckY + 2.2, mz, 0.25, deckY + 2.7, mz + 8.2, C.WoodDark, NOSHADOW)
	-- main sail: 4 steps getting shorter towards the top
	local sy = deckY + 2.7
	local stepH = (mastH - 3.6) / 4
	for i = 1, 4 do
		local len = 7.8 * (1 - (i - 1) * 0.24)
		local col = if i == 2 then stripe else sail
		local th = if i % 2 == 0 then 0.18 else 0.12 -- neighbours never share a side plane
		b:span(`Sail{i}`, -th, sy, mz + 0.35, th, sy + stepH + 0.02, mz + 0.35 + len, col, FOLIAGE)
		sy += stepH
	end
	-- jib: 3 steps in front of the mast
	local jy = deckY + 1.2
	local jH = (mastH - 5) / 3
	for i = 1, 3 do
		local len = 5.4 * (1 - (i - 1) * 0.33)
		b:span(`Jib{i}`, -0.1, jy, mz - 0.35 - len, 0.1, jy + jH + 0.02, mz - 0.35, sail, FOLIAGE)
		jy += jH
	end
	b:span("Pennant", -0.08, deckY + mastH - 1.2, mz + 0.35, 0.08, deckY + mastH - 0.2, mz + 2.4, C.Red, DECOR)
	bobbing(b, 0.35, 4)
	return b:finish(floor)
end

--[[
	motorboat: sporty voxel hull with a racing stripe, a white front deck, a glass windshield, a
	console, a bench and an outboard motor. 17 parts. cframe on the water surface, bow = -Z.
	opts: color (hull paint), stripe (colour), bob / bobPeriod (see bobbing).
]]
function Props.motorboat(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Motorboat", cf, opts, 169)
	local o = b.opts
	local paint = o.color or b:pick({ C.White, C.Red, C.Blue, C.Yellow })
	local stripe = o.stripe or (if paint == C.White then C.Blue else C.White)
	local L, W = 12, 5
	local floor = voxelHull(b, L, W, -0.9, 0.3, 1.5, paint, C.White)
	b:span("StripeL", -W / 2 - 0.12, 0.1, -L / 2 + 3.4, -W / 2 + 0.2, 0.7, L / 2 + 0.12, stripe, DECOR)
	b:span("StripeR", W / 2 - 0.2, 0.1, -L / 2 + 3.4, W / 2 + 0.12, 0.7, L / 2 + 0.12, stripe, DECOR)
	b:span("FrontDeck", -W / 2 + 0.3, 1.2, -L / 2 + 1.6, W / 2 - 0.3, 1.7, -1.2, C.White)
	b:span(
		"Windshield",
		-W / 2 + 0.6,
		1.6,
		-1.35,
		W / 2 - 0.6,
		2.9,
		-1.05,
		C.Glass,
		merge(DECOR, { Material = Mat.Glass, Transparency = 0.35 })
	)
	b:span("Console", 0.4, 0.3, -0.9, 1.7, 1.8, 0.1, C.Navy, NOSHADOW)
	b:span("Wheel", 0.75, 1.8, -0.75, 1.35, 2.3, -0.55, C.Dark, DECOR)
	b:span("Bench", -W / 2 + 0.6, 0.3, 2.6, W / 2 - 0.6, 1.4, 4.2, C.Cream, NOSHADOW)
	b:span("Motor", -0.6, -0.8, L / 2, 0.6, 2.4, L / 2 + 1.2, C.Dark)
	b:span("MotorCap", -0.7, 2.2, L / 2 - 0.1, 0.7, 2.9, L / 2 + 1.3, stripe, NOSHADOW)
	bobbing(b, 0.3, 3.2)
	return b:finish(floor)
end

--[[
	buoy: voxel buoy — coloured float, white band, coloured top and a Neon lamp. 4 parts.
	cframe on the water surface. opts: color (default Red), light = true (PointLight), bob /
	bobPeriod (see bobbing).
]]
function Props.buoy(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Buoy", cf, opts, 173)
	local o = b.opts
	local col = o.color or C.Red
	local body = b:span("Float", -1.4, -1.0, -1.4, 1.4, 0.8, 1.4, col)
	b:span("Band", -1.05, 0.75, -1.05, 1.05, 1.6, 1.05, C.White, NOSHADOW)
	b:span("Top", -0.75, 1.55, -0.75, 0.75, 2.6, 0.75, col, NOSHADOW)
	local lamp = b:vox("Lamp", 0, 2.95, 0, 0.7, 0.7, 0.7, C.Glow, NEON_DECOR)
	if o.light then
		light(lamp, 12, 1.2)
	end
	bobbing(b, 0.25, 2.4)
	return b:finish(body)
end

--[[
	dockSegment: pier section. cframe = top centre of the deck; it runs along local Z.
	Chunky planks across (alternating shades) + 2 side stringers + 4 square piles sticking up as
	bollards + a cross brace. 9-11 parts. opts: length (12), width (8), depth (how far piles
	reach below the deck, 12), piles = "both" (default) | "front" (-Z end only) | "back"
	(+Z end only) | false (no piles) — chain segments with "front" so joints don't get doubled.
]]
function Props.dockSegment(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Dock", cf, opts, 181)
	local o = b.opts
	local L = o.length or 12
	local W = o.width or 8
	local depth = o.depth or 12
	local n = math.max(1, math.floor(L / 3 + 0.5))
	local pl = L / n
	local deck
	for k = 0, n - 1 do
		local z0 = -L / 2 + k * pl
		local p =
			b:span(`Plank{k + 1}`, -W / 2, -0.7, z0, W / 2, 0, z0 + pl, if k % 2 == 0 then C.WoodLight else C.Wood)
		deck = deck or p
	end
	local sh = b:range(0.9, 1.1) -- stringer depth varies per segment (no shared planes at joints)
	for i, sx in { -1, 1 } do
		b:span(
			`Stringer{i}`,
			sx * W / 2 - 0.35,
			-0.7 - sh,
			-L / 2 + 0.05,
			sx * W / 2 + 0.35,
			-0.65,
			L / 2 - 0.05,
			C.WoodDark
		)
	end
	local piles = o.piles
	if piles == nil or piles == true then
		piles = "both"
	end
	if piles then
		local zs = {}
		if piles == "both" or piles == "front" then
			table.insert(zs, -(L / 2 - 0.9))
		end
		if piles == "both" or piles == "back" then
			table.insert(zs, L / 2 - 0.9)
		end
		for j, z in zs do
			for i, sx in { -1, 1 } do
				local top = b:range(1.0, 1.3) -- uneven bollard tops, no shared planes
				b:span(
					`Pile{j}_{i}`,
					sx * (W / 2 + 0.75) - 0.7,
					-depth,
					z - 0.7,
					sx * (W / 2 + 0.75) + 0.7,
					top,
					z + 0.7,
					C.WoodDark
				)
			end
		end
		local bz = zs[#zs]
		b:span("Brace", -W / 2 - 0.2, -2.6, bz - 0.3, W / 2 + 0.2, -1.9, bz + 0.3, C.Wood, NOSHADOW)
	end
	return b:finish(deck)
end

--[[
	shipwreck: big broken pirate ship (~46 studs) half-sunk and listing: a dark hull with a
	painted band and a jagged hole, a stepped bow with a bowsprit, a raised stern castle with
	lit windows, a broken main mast with a torn sail, a fore mast with a black flag, cargo,
	glowing treasure, seaweed and foam cubes at the waterline. 63 parts. cframe on the water
	surface, bow = -Z. opts: band (colour of the hull band, default Red), sink (default 2.6).
]]
function Props.shipwreck(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Shipwreck", cf, opts, 193)
	local o = b.opts
	local hullC = rgb(150, 96, 62)
	local hullD = rgb(116, 72, 46)
	local deckC = C.WoodLight
	local band = o.band or C.Red
	local L, W = 44, 13
	local hw = W / 2
	local sink = o.sink or 2.6

	-- foam cubes along the waterline (level frame)
	local foam = {
		{ -hw - 1.6, -12, 2.4 },
		{ -hw - 1.2, 2, 2.0 },
		{ -hw - 1.4, 14, 2.2 },
		{ hw + 2.2, -9, 2.2 },
		{ hw + 2.6, 4, 2.6 },
		{ hw + 1.8, 15, 1.8 },
		{ 1, -L / 2 - 1, 2.4 },
		{ -2, L / 2 + 1.5, 2.0 },
	}
	for i, f in foam do
		b:vox(`Foam{i}`, f[1], 0.15, f[2], f[3], f[3] * 0.5, f[3], C.Foam, DECOR)
	end

	-- the ship itself: sunk and listed (rolled to starboard, bow up)
	local old = b:push(CFrame.new(0, -sink, 0) * rot(-5, 0, -9))
	local zb = -L / 2 + 9 -- bow start
	local y0, deckY, rimY = -5, 3, 5.5
	local keel = b:span("Hull", -hw + 0.6, y0, zb + 0.1, hw - 0.6, deckY - 0.6, L / 2 - 6, hullD)
	-- port side wall: full, with the painted band
	b:span("SidePort", -hw, y0 + 0.5, zb, -hw + 0.8, rimY, L / 2, hullC)
	b:span("BandPort", -hw - 0.1, rimY - 1.6, zb - 0.1, -hw + 0.9, rimY - 0.7, L / 2 + 0.2, band, NOSHADOW)
	-- starboard side wall: broken into pieces of uneven height with a hole in the middle
	b:span("SideStbd1", hw - 0.8, y0 + 0.5, zb, hw, rimY, zb + 9, hullC)
	b:span("SideStbd2", hw - 0.8, y0 + 0.5, zb + 9, hw, rimY - 3.2, zb + 13, hullC)
	b:span("SideStbd3", hw - 0.8, y0 + 0.5, zb + 13, hw, 0.4, zb + 18, hullC)
	b:span("SideStbd4", hw - 0.8, y0 + 0.5, zb + 18, hw, rimY - 1.8, zb + 22, hullC)
	b:span("SideStbd5", hw - 0.8, y0 + 0.5, zb + 22, hw, rimY, L / 2, hullC)
	b:span("BandStbd1", hw - 0.9, rimY - 1.6, zb - 0.1, hw + 0.1, rimY - 0.7, zb + 9.1, band, NOSHADOW)
	b:span("BandStbd2", hw - 0.9, rimY - 1.6, zb + 21.9, hw + 0.1, rimY - 0.7, L / 2 + 0.2, band, NOSHADOW)
	-- planks sticking out of the hole
	b:span("BrokenPlank1", hw - 0.3, 0.2, zb + 13.5, hw + 1.4, 0.8, zb + 15.5, hullC, NOSHADOW)
	b:span("BrokenPlank2", hw - 0.4, -1.8, zb + 15.8, hw + 1.1, -1.2, zb + 17.5, hullD, NOSHADOW)
	-- deck in two pieces with a gap
	b:span("DeckA", -hw + 0.8, deckY - 0.6, zb - 1, hw - 0.8, deckY, zb + 12, deckC)
	b:span("DeckB", -hw + 0.8, deckY - 0.6, zb + 16, hw - 0.8, deckY, L / 2 - 0.8, shade(deckC, 0.92))
	-- stern transom
	b:span("Transom", -hw, y0 + 0.5, L / 2 - 0.8, hw, rimY + 6, L / 2 + 0.1, hullC)
	-- bow: three steps + bowsprit + figure trim
	b:span("Bow1", -hw * 0.75, y0 + 1, zb - 4, hw * 0.75, rimY + 0.6, zb + 0.5, hullC)
	b:span("Bow2", -hw * 0.48, y0 + 2, zb - 7, hw * 0.48, rimY + 1.2, zb - 3.8, hullC)
	b:span("Bow3", -hw * 0.22, y0 + 3.5, zb - 9, hw * 0.22, rimY + 1.8, zb - 6.8, hullD)
	b:span("BowBand", -hw * 0.76, rimY - 1.6, zb - 4.1, hw * 0.76, rimY - 0.7, zb + 0.3, band, NOSHADOW)
	b:span("Bowsprit", -0.4, rimY + 1.6, zb - 15, 0.4, rimY + 2.4, zb - 8, C.WoodDark, NOSHADOW)
	-- stern castle with lit windows and a railing
	local sc0 = L / 2 - 11
	b:span("Castle", -hw + 0.8, deckY, sc0, hw - 0.8, rimY + 5, L / 2 - 0.6, hullC)
	b:span("CastleDeck", -hw + 0.5, rimY + 5, sc0 - 0.3, hw - 0.5, rimY + 5.6, L / 2, deckC)
	b:span("CastleBand", -hw + 0.7, rimY + 3.6, sc0 - 0.1, hw - 0.7, rimY + 4.4, L / 2 - 0.5, band, NOSHADOW)
	for i, x in { -3.6, 0, 3.6 } do
		b:span(`Window{i}`, x - 1.0, rimY + 1.6, L / 2 - 0.1, x + 1.0, rimY + 3.2, L / 2 + 0.25, C.Glow, NEON_DECOR)
	end
	b:span("CastleDoor", -1.4, deckY, sc0 - 0.25, 1.4, deckY + 4, sc0 + 0.2, hullD, NOSHADOW)
	b:span("CastleRail", -hw + 0.5, rimY + 5.6, L / 2 - 0.6, hw - 0.5, rimY + 6.8, L / 2, hullD, NOSHADOW)
	b:span("Lantern", -0.6, rimY + 6.8, L / 2 - 1.4, 0.6, rimY + 8.2, L / 2 - 0.2, C.Glow, NEON_DECOR)
	-- broken main mast with a yard and a torn sail
	local mz = zb + 13
	b:span("MainMast", -0.8, deckY - 0.5, mz - 0.8, 0.8, deckY + 15, mz + 0.8, C.WoodDark)
	b:span("MainMastTop", -0.6, deckY + 15, mz - 0.5, 0.4, deckY + 16.4, mz + 0.6, C.WoodDark, NOSHADOW)
	b:span("Yard", -8, deckY + 12.4, mz - 1.4, 8, deckY + 13.2, mz - 0.8, C.WoodDark, NOSHADOW)
	b:span("SailA", -7, deckY + 5.5, mz - 1.3, -2.2, deckY + 12.4, mz - 1.0, C.Sail, FOLIAGE)
	b:span("SailB", -2.2, deckY + 8.6, mz - 1.3, 2.6, deckY + 12.4, mz - 1.0, C.Canvas, FOLIAGE)
	b:span("SailC", 2.6, deckY + 4.2, mz - 1.3, 6.6, deckY + 12.4, mz - 1.0, C.Sail, FOLIAGE)
	-- the broken-off top of the main mast lying across the deck and over the side
	b:span("FallenMast", -hw - 6, deckY, mz + 2.2, hw - 1, deckY + 1.4, mz + 3.6, shade(C.WoodDark, 1.1))
	-- fore mast with a crow's nest and a black flag
	local fz = zb + 3
	b:span("ForeMast", -0.6, deckY - 0.5, fz - 0.6, 0.6, deckY + 20, fz + 0.6, C.WoodDark)
	b:span("Nest", -1.6, deckY + 15, fz - 1.6, 1.6, deckY + 16.6, fz + 1.6, hullC)
	b:span("Flag", 0.6, deckY + 16.8, fz - 0.1, 5.4, deckY + 19.8, fz + 0.1, C.Dark, FOLIAGE)
	b:span("Skull", 2.4, deckY + 17.8, fz - 0.2, 3.6, deckY + 19.0, fz + 0.2, C.White, DECOR)
	b:span("SkullEyes", 2.6, deckY + 18.3, fz - 0.25, 3.4, deckY + 18.6, fz + 0.25, C.Dark, DECOR)
	-- cargo on deck
	b:span("Crate1", -4.6, deckY, zb + 5, -2.0, deckY + 2.6, zb + 7.6, C.WoodLight)
	b:span("Crate1Frame", -4.7, deckY + 1.1, zb + 4.9, -1.9, deckY + 1.5, zb + 7.7, C.WoodDark, NOSHADOW)
	b:column("Barrel1", 2.4, 3.2, zb + 6, deckY, deckY + 3, C.Wood)
	b:column("Barrel1Hoop", 2.6, 3.2, zb + 6, deckY + 1.9, deckY + 2.3, C.Iron, nil, NOSHADOW)
	b:span("Chest", -2.0, deckY, L / 2 - 15.5, 1.6, deckY + 1.8, L / 2 - 13.2, C.Wood)
	b:span("ChestGold", -1.8, deckY + 1.75, L / 2 - 15.3, 1.4, deckY + 2.4, L / 2 - 13.4, C.Gold, NEON_DECOR)
	-- cannons poking out of the port side
	for i, z in { zb + 6, zb + 18 } do
		b:span(`Cannon{i}`, -hw - 1.6, rimY - 3.6, z - 0.5, -hw + 0.2, rimY - 2.6, z + 0.5, C.Dark, NOSHADOW)
	end
	-- seaweed and barnacles on the hull
	b:span("Seaweed1", -hw - 0.25, y0 + 2, zb + 3, -hw + 0.1, deckY - 1.2, zb + 4.2, C.Seaweed, DECOR)
	b:span("Seaweed2", -hw - 0.25, y0 + 1, zb + 20, -hw + 0.1, deckY - 2, zb + 21.4, C.Lime, DECOR)
	b:span("Seaweed3", hw - 0.1, y0 + 1.5, zb + 25, hw + 0.25, deckY - 1.6, zb + 26.2, C.Seaweed, DECOR)
	b:span("Barnacles", -hw - 0.2, deckY - 3.4, zb + 9, -hw + 0.1, deckY - 2.6, zb + 11.5, C.StoneLight, DECOR)
	b:pop(old)

	-- loose cargo floating around
	b:column("FloatBarrel", 2.4, hw + 6, -6, -1.2, 1.0, C.Wood)
	b:span("FloatCrate", -hw - 8, -1.4, 6, -hw - 5.4, 0.9, 8.6, C.WoodLight)
	return b:finish(keel)
end

--[[
	whale: big friendly cartoon whale surfacing (~32 studs long): body with a darker back and a
	cream belly, head and snout, smile, big eyes, pink cheeks, flippers at the waterline, spots,
	a water spout from the blowhole, the tail raised behind with its flukes up, foam cubes
	around. 44 parts. cframe on the water surface, head towards -Z. opts: color (body).
]]
function Props.whale(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Whale", cf, opts, 197)
	local o = b.opts
	local col = o.color or rgb(70, 140, 240)
	local back = shade(col, 0.8)
	local lightC = lerpColor(col, C.White, 0.35)
	local belly = C.Cream

	-- body (head towards -Z); the waterline (y = 0) is at about a third of the body height
	local body = b:span("Body", -5, -3.2, -9, 5, 4.6, 9, col)
	b:span("Back", -4.2, 4.5, -7.6, 4.2, 5.5, 7.4, back)
	b:span("Head", -4.7, -2.8, -12.8, 4.7, 4.2, -8.8, col)
	b:span("HeadTop", -3.9, 4.1, -12.2, 3.9, 5.0, -8.7, back)
	b:span("Snout", -4.1, -2.2, -13.8, 4.1, 3.4, -12.7, lerpColor(col, C.White, 0.1))
	b:span("Belly", -4.5, -4.2, -13.2, 4.5, -1.2, 7, belly)
	-- face on both sides: smile, big eye with a pupil, pink cheek
	for i, sx in { -1, 1 } do
		b:span(`Mouth{i}`, sx * 4.6, 0.3, -13.0, sx * 4.85, 0.8, -9.6, C.Navy, DECOR)
		b:span(`Eye{i}`, sx * 4.62, 1.2, -12.2, sx * 4.92, 3.6, -9.9, C.White, DECOR)
		b:span(`Pupil{i}`, sx * 4.88, 1.7, -11.5, sx * 5.02, 3.1, -10.4, C.Dark, DECOR)
		b:span(`Cheek{i}`, sx * 4.62, 0.9, -9.7, sx * 4.86, 1.5, -8.85, C.Pink, DECOR)
		-- flipper lying at the waterline
		b:span(`Flipper{i}`, sx * 5, -0.5, -6.2, sx * 8.8, 0.45, -2.6, back)
	end
	b:span("Dorsal", -0.8, 5.4, 3.5, 0.8, 6.6, 6.6, back)
	for i, p in { { -2, -4 }, { 1.8, 0.5 }, { -0.6, 4.8 } } do
		b:span(`Spot{i}`, p[1] - 0.8, 5.48, p[2] - 0.8, p[1] + 0.8, 5.62, p[2] + 0.8, lightC, DECOR)
	end
	-- blowhole with a water spout
	b:span("Blowhole", -0.55, 4.96, -10.7, 0.55, 5.1, -9.7, C.Navy, DECOR)
	local spout = merge(DECOR, { Transparency = 0.1 })
	-- spout: a column, a white head and four jets falling outwards, droplets below them
	local sz0 = -10.2
	b:span("Spout", -0.7, 5.05, sz0 - 0.7, 0.7, 9.8, sz0 + 0.7, C.WaterLight, spout)
	local head = b:vox("SpoutHead", 0, 10.2, sz0, 2.0, 1.4, 2.0, C.Foam, spout)
	-- droplets keep spurting out of the spout head and rain down round it
	Props.fx(head, "spray", { rate = 14, size = 1.3 * b.s, spread = 35, speed = NR.new(7, 11) })
	for i, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local sx = if d[1] ~= 0 then 1.8 else 1.0
		local sz = if d[2] ~= 0 then 1.8 else 1.0
		b:vox(
			`Jet{i}`,
			d[1] * 1.7,
			9.6,
			sz0 + d[2] * 1.7,
			sx,
			0.9,
			sz,
			if i % 2 == 0 then C.WaterLight else C.Foam,
			spout
		)
		b:vox(`Drop{i}`, d[1] * 3.1, 8.2 + (i % 2) * 0.4, sz0 + d[2] * 3.1, 0.8, 0.8, 0.8, C.Foam, DECOR)
	end
	-- tail rising out of the water behind, flukes up
	b:span("TailStock", -2.8, -1.8, 8.8, 2.8, 3.4, 13.5, col)
	b:span("TailRise", -1.8, 2.8, 12.2, 1.8, 8.2, 15.2, col)
	b:span("Flukes", -6.8, 7.8, 12.4, 6.8, 9.2, 16.4, back)
	b:span("FlukeTipL", -8.4, 8.6, 12.8, -5.8, 10.2, 16.0, back)
	b:span("FlukeTipR", 5.8, 8.6, 12.8, 8.4, 10.2, 16.0, back)
	-- foam cubes around the body at the waterline
	local foam = {
		{ -6.4, -8, 2.2 },
		{ 6.3, -9.5, 1.8 },
		{ -6.0, 2, 1.6 },
		{ 6.2, 4, 2.0 },
		{ -3.5, 10.5, 1.6 },
		{ 3.8, 11, 1.8 },
		{ 0.5, -15, 2.0 },
		{ -3.8, -14, 1.4 },
	}
	for i, f in foam do
		b:vox(`Foam{i}`, f[1], 0.2, f[2], f[3], f[3] * 0.55, f[3], C.Foam, DECOR)
	end
	return b:finish(body)
end

--------------------------------------------------------------------------------------------
-- BIG PIECES
--------------------------------------------------------------------------------------------

--[[
	bridge(parent, fromPos, toPos, opts): chunky voxel bridge between two points.
	Deck top at opts.deckY (default 4), width opts.width (10), support piles down to opts.bedY
	(-14). Deck of ~4-stud planks across the bridge with alternating shades, edge kerbs,
	stringers; thick block posts every ~opts.postSpacing (10) with continuous top and mid rails;
	every third post carries a cube lantern (PointLights on every other lantern on one side;
	opts.lights = false: none); pile bents every ~opts.bentSpacing (20); entrance arches at both
	ends with a stepped roof and lanterns (default on bridges >= 40 studs; opts.gates forces it);
	opts.signText puts a sign board under each arch; opts.bunting = true strings flags across
	the deck at the lantern pairs (opts.buntingEvery = 2 for every other pair).
	opts.style = "wood" (default) | "stone"; opts.color (deck), opts.roof (arch roof colour).
	About 8 parts per 10 studs + ~30 (rails, kerbs, arches): a 180-stud bridge is ~175 parts.
]]
function Props.bridge(parent: any, fromPos: any, toPos: any, opts: { [string]: any }?): any
	local o = opts or {}
	local deckY = o.deckY or 4
	local W = o.width or 10
	local bedY = o.bedY or -14
	local bedLocal = bedY - deckY -- local y is relative to the deck top
	local stone = o.style == "stone"
	local a = Vector3.new(fromPos.X, deckY, fromPos.Z)
	local c = Vector3.new(toPos.X, deckY, toPos.Z)
	local L = (c - a).Magnitude
	local mid = (a + c) / 2
	-- local -Z points from `from` to `to`; local z runs from +L/2 (from) to -L/2 (to).
	local cf = CFrame.lookAt(mid, c)
	local b = begin(parent, "Bridge", cf, o, 197)
	b.s = 1
	local hw = W / 2
	local deckT = 1.2

	-- colours: the walked-on frame (kerbs, stringers, posts, rails) stays light and warm; the dark
	-- shade is kept for the piles under the deck; the pile caps take a pastel of the roof colour
	local deckA, deckB, kerbC, postC, railC, pileC, capC, roofC, archC
	if stone then
		deckA = o.color or C.StoneLight
		deckB = lerpColor(deckA, C.Stone, 0.45)
		kerbC, postC, railC, pileC = C.Stone, C.Stone, C.StoneLight, C.StoneDark
		roofC = o.roof or C.Blue
		capC = C.Stone
		archC = C.StoneLight
	else
		deckA = o.color or C.WoodLight
		deckB = lerpColor(deckA, C.Wood, 0.45)
		kerbC, postC, railC, pileC = C.Wood, C.White, C.Wood, C.WoodDark
		roofC = o.roof or C.Red
		capC = lerpColor(roofC, C.White, 0.6)
		archC = C.Wood
	end

	-- deck: planks across the bridge, alternating shades
	local np = math.max(1, math.floor(L / (o.plankLength or 4) + 0.5))
	local pl = L / np
	local deck
	for k = 0, np - 1 do
		local z1 = L / 2 - k * pl
		local p = b:span(`Deck{k + 1}`, -hw, -deckT, z1 - pl, hw, 0, z1, if k % 2 == 0 then deckA else deckB)
		deck = deck or p
	end
	-- kerbs on the deck edges and stringers under them
	for i, sx in { -1, 1 } do
		b:span(`Kerb{i}`, sx * hw - sx * 1.1, -0.15, -L / 2 + 0.1, sx * hw + sx * 0.25, 0.55, L / 2 - 0.1, kerbC)
		b:span(
			`Stringer{i}`,
			sx * hw - sx * 1.6,
			-deckT - 1.2,
			-L / 2 + 0.2,
			sx * hw - sx * 0.2,
			-deckT + 0.01,
			L / 2 - 0.2,
			kerbC
		)
	end

	-- pile bents
	local bentStep = o.bentSpacing or 20
	local nb = math.max(1, math.floor((L - 6) / bentStep + 0.5))
	local step = (L - 6) / nb
	for k = 0, nb do
		local z = L / 2 - 3 - k * step
		local capTop = -deckT - 1.2
		if stone then
			b:span(`Pier{k}`, -hw * 0.55, bedLocal, z - 1.8, hw * 0.55, capTop - 1.2, z + 1.8, pileC)
			b:span(`PierCap{k}`, -hw - 0.6, capTop - 1.25, z - 2.2, hw + 0.6, capTop + 0.01, z + 2.2, capC)
		else
			for i, sx in { -1, 1 } do
				local x = sx * (hw - 1.2)
				b:span(`Pile{k}_{i}`, x - 0.9, bedLocal, z - 0.9, x + 0.9, capTop - 1.0, z + 0.9, pileC)
			end
			b:span(`Cap{k}`, -hw - 0.6, capTop - 1.05, z - 1.0, hw + 0.6, capTop + 0.01, z + 1.0, capC)
		end
	end

	-- railings: continuous rails, thick posts every ~10 studs, a cube lantern on every third
	local railH = 3.6
	for i, sx in { -1, 1 } do
		local x = sx * (hw - 0.45)
		b:span(`TopRail{i}`, x - 0.45, railH, -L / 2, x + 0.45, railH + 0.7, L / 2, railC)
		b:span(`MidRail{i}`, x - 0.3, railH * 0.45, -L / 2, x + 0.3, railH * 0.45 + 0.55, L / 2, railC, NOSHADOW)
	end
	local postStep = o.postSpacing or 10
	local npost = math.max(1, math.floor(L / postStep + 0.5))
	local ps = L / npost
	local lightsOn = o.lights ~= false
	local gates = o.gates
	if gates == nil then
		gates = L >= 40 -- short river crossings look better without gates
	end
	local lanternPairs = {}
	local lanternCount = 0
	for k = 0, npost do
		local z = math.clamp(L / 2 - k * ps, -L / 2 + 0.7, L / 2 - 0.7)
		local atEnd = k == 0 or k == npost
		local isLantern = k % 3 == 0 and not (gates and atEnd)
		if isLantern then
			lanternCount += 1
			table.insert(lanternPairs, z)
		end
		for i, sx in { -1, 1 } do
			local x = sx * (hw - 0.45)
			if isLantern then
				b:span(`LampPost{k}_{i}`, x - 0.8, 0, z - 0.8, x + 0.8, railH + 2.0, z + 0.8, postC)
				local withLight = lightsOn and i == 1 and lanternCount % 2 == 1
				cubeLantern(b, `L{k}_{i}`, x, railH + 1.95, z, 0.85, roofC, withLight, true)
			else
				b:span(`Post{k}_{i}`, x - 0.7, 0, z - 0.7, x + 0.7, railH + 1.2, z + 0.7, postC)
			end
		end
	end

	-- optional festive bunting across the deck between opposite lantern posts
	if o.bunting then
		local every = o.buntingEvery or 1
		for k, z in lanternPairs do
			if (k - 1) % every == 0 then
				local top = railH + 1.6
				local pa = b:worldPoint(Vector3.new(-(hw - 0.45), top, z))
				local pb = b:worldPoint(Vector3.new(hw - 0.45, top, z))
				Props.bunting(b.model, pa, pb, { seed = k, sag = 1.0, name = `Bunting{k}` })
			end
		end
	end

	-- entrance arches at both ends: pillars on stone feet, beams, a stepped roof, lanterns
	if gates then
		for e, z in { L / 2 - 1.6, -L / 2 + 1.6 } do
			local px = hw + 1.4
			for i, sx in { -1, 1 } do
				b:span(
					`ArchFoot{e}_{i}`,
					sx * px - 1.8,
					-deckT - 0.6,
					z - 1.8,
					sx * px + 1.8,
					1.2,
					z + 1.8,
					C.StoneLight
				)
				b:span(`ArchPillar{e}_{i}`, sx * px - 1.2, 1.2, z - 1.2, sx * px + 1.2, 11.6, z + 1.2, archC)
				-- lantern tucked into the corner of the pillar and the tie beam (touching both)
				b:vox(`ArchLamp{e}_{i}`, sx * (px - 1.7), 8.75, z, 1.1, 1.4, 1.0, C.Glow, NEON_DECOR)
			end
			b:span(`ArchBeam{e}`, -px - 2.2, 10.4, z - 1.6, px + 2.2, 12.2, z + 1.6, roofC)
			b:span(`ArchTie{e}`, -px + 1.2, 9.4, z - 0.9, px - 1.2, 10.45, z + 0.9, archC, NOSHADOW)
			b:span(`ArchRoof1{e}`, -px - 3.2, 12.2, z - 2.4, px + 3.2, 13.4, z + 2.4, roofC)
			b:span(`ArchRoof2{e}`, -px - 1.2, 13.4, z - 1.8, px + 1.2, 14.6, z + 1.8, lerpColor(roofC, C.White, 0.25))
			b:span(`ArchRoof3{e}`, -px + 2.6, 14.6, z - 1.1, px - 2.6, 15.6, z + 1.1, roofC)
			if lightsOn then
				light(b.model:FindFirstChild(`ArchLamp{e}_1`), 14, 1.4)
			end
			if o.signText then
				local board = b:span(`ArchSign{e}`, -W * 0.3, 7.0, z - 0.5, W * 0.3, 9.45, z + 0.5, C.Cream, NOSHADOW)
				addSignText(board, Enum.NormalId.Front, o.signText, C.Navy)
				addSignText(board, Enum.NormalId.Back, o.signText, C.Navy)
			end
		end
	end
	return b:finish(deck)
end

--[[
	waterfall(parent, topPos, bottomPos, width, opts): voxel falling water from the lip (topPos,
	centre of the river at the edge) to the plunge point (bottomPos, pool surface). A stepped
	sheet: 1-4 sections stepping from the lip towards the bottom point, each split into 2-3
	columns of different light blues (vertical stripes read as falling water), white streaks, a
	white crest at the lip, a foam slab with white / light-blue cubes at the bottom and an
	optional cheap mist emitter (opts.mist = false to disable). 12-22 parts, all non-colliding,
	slightly transparent (opts.transparency, default 0.08).
	opts.flow = horizontal Vector3 the water flows towards (default: from top to bottom, or
	towards the world centre when the fall is vertical).
]]
function Props.waterfall(parent: any, topPos: any, bottomPos: any, width: number, opts: { [string]: any }?): any
	local o = opts or {}
	local W = width
	local flow = o.flow
	if not flow then
		local h = Vector3.new(bottomPos.X - topPos.X, 0, bottomPos.Z - topPos.Z)
		if h.Magnitude > 1 then
			flow = h
		elseif Vector3.new(topPos.X, 0, topPos.Z).Magnitude > 1 then
			flow = Vector3.new(-topPos.X, 0, -topPos.Z)
		else
			flow = Vector3.new(0, 0, -1)
		end
	end
	flow = Vector3.new(flow.X, 0, flow.Z).Unit
	-- level frame at the plunge point, local -Z = downstream, +Y up
	local cf = CFrame.lookAt(bottomPos, bottomPos + flow)
	local b = begin(parent, "Waterfall", cf, o, 211)
	b.s = 1
	local topL = cf:PointToObjectSpace(topPos) -- the lip in local space (z > 0: upstream)
	local H = topL.Y
	local zTop = topL.Z
	local sheet = merge(DECOR, { Transparency = o.transparency or 0.08 })
	local shades = { rgb(96, 196, 255), rgb(150, 224, 255), rgb(118, 210, 255) }

	-- sheet: m vertical sections stepping from the lip towards the plunge point, each split into
	-- columns of different blues (vertical stripes read as falling water)
	local m = math.clamp(math.ceil(math.abs(zTop) / 2.5), 1, 4)
	local cols = if W >= 8 then 3 else 2
	local colW = W / cols
	local first
	local fronts = {}
	for s = 0, m - 1 do
		local yHi = H - s * H / m + (if s == 0 then 0.5 else 0.6)
		local yLo = H - (s + 1) * H / m - (if s == m - 1 then 0.4 else 0)
		local zc = zTop * (1 - (s + 0.5) / m)
		local depth = math.max(1.8, math.abs(zTop) / m + 1.4)
		fronts[s] = { zc - depth / 2, yLo, yHi }
		for c = 0, cols - 1 do
			local x0 = -W / 2 + c * colW
			local fwd = if c % 2 == 1 then -0.35 else 0
			local col = lerpColor(shades[c % #shades + 1], C.White, s * 0.05)
			local p = b:span(
				`Sheet{s + 1}_{c + 1}`,
				x0,
				yLo,
				zc - depth / 2 + fwd,
				x0 + colW + 0.01 * c,
				yHi + 0.013 * c,
				zc + depth / 2 + fwd,
				col,
				sheet
			)
			first = first or p
		end
	end
	-- white streaks on the front of the top and the bottom section
	for i, s in { 0, m - 1 } do
		local f = fronts[s]
		local x = (if i == 1 then -0.18 else 0.22) * W
		local y0 = f[2] + (f[3] - f[2]) * (if i == 1 then 0.25 else 0)
		b:span(`Streak{i}`, x - 0.45, y0, f[1] - 0.75, x + 0.45, f[3] - 0.3, f[1] + 0.2, C.Foam, sheet)
	end
	-- crest curling over the lip
	local f0 = fronts[0]
	b:span("Crest", -W / 2 - 0.3, H - 0.3, f0[1] - 0.4, W / 2 + 0.3, H + 0.9, zTop + 1.5, C.Foam, DECOR)
	-- foam at the bottom: a light slab and a row of white / light-blue cubes
	local foam = b:span("Foam", -W * 0.7, -0.35, -W * 0.5, W * 0.7, 0.45, 1.2, rgb(200, 240, 255), sheet)
	local puffs = o.puffs or 5
	for i = 1, puffs do
		local x = (-0.5 + (i - 0.5) / puffs) * W * 1.2
		local sz = W * b:range(0.17, 0.25)
		local z = b:range(-W * 0.3, 0.3)
		b:vox(`Puff{i}`, x, sz * 0.42, z, sz, sz, sz, if i == 2 then C.WaterLight else C.Foam, DECOR)
	end
	if o.mist ~= false then
		-- soft mist rising from the plunge pool and white foam cubes churning on it
		Props.fx(foam, "mist", { size = W / 12 })
		Props.fx(foam, "foam", { rate = 10, size = math.clamp(W / 8, 0.8, 2) })
	end
	return b:finish(first)
end

--[[
	lighthouse: voxel red/white striped square tower (~40 studs) on a stone plinth: 6 tapering
	bands, door with a frame, windows, a navy gallery with a red parapet, a lantern room with
	white corner posts round a turning Neon lens panel (child Model "Beacon", attribute Spin), a
	stepped red roof and a gold top. 28 parts.
	opts: light = false (no PointLight), stripe = colour (default Red), spin (degrees per second,
	default 40).
]]

function Props.lighthouse(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Lighthouse", cf, opts, 223)
	local o = b.opts
	local red = o.stripe or C.Red
	-- the plinth reaches well below the ground, so it also fills a terrace step under one side
	local plinth = b:span("Plinth", -7, -6.5, -7, 7, 1, 7, C.StoneLight)
	b:span("Base", -5.6, 0.9, -5.6, 5.6, 3, 5.6, C.Stone)
	local y = 3
	local bandH = 4.5
	local widths = {}
	for i = 0, 5 do
		local w = 9.6 - i * 0.6
		widths[i + 1] = w
		b:span(`Band{i + 1}`, -w / 2, y - 0.02, -w / 2, w / 2, y + bandH, w / 2, if i % 2 == 0 then red else C.White)
		y += bandH
	end
	local top = y -- 30
	b:span("Gallery", -5.6, top, -5.6, 5.6, top + 1, 5.6, C.Navy)
	b:span("ParapetF", -5.6, top + 1, -5.6, 5.6, top + 2.4, -5.1, red, NOSHADOW)
	b:span("ParapetB", -5.6, top + 1, 5.1, 5.6, top + 2.4, 5.6, red, NOSHADOW)
	b:span("ParapetL", -5.6, top + 1, -5.1, -5.1, top + 2.4, 5.1, red, NOSHADOW)
	b:span("ParapetR", 5.1, top + 1, -5.1, 5.6, top + 2.4, 5.1, red, NOSHADOW)
	-- the lamp: a glowing lens panel turning in the lantern room (child Model "Beacon", Spin =
	-- degrees per second about the vertical); it sweeps between the corner posts
	local beacon = b:group("Beacon")
	local glass = b:span("Lantern", -2.0, top + 1.1, -0.9, 2.0, top + 5.3, 0.9, C.Glow, NEON)
	b:ungroup()
	b:finishGroup(beacon, glass, CFrame.new(0, top + 3.2, 0) * rot(90, 0, 0))
	beacon:SetAttribute("Spin", o.spin or 40)
	ghost(beacon)
	for i, p in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		b:vox(`Post{i}`, p[1] * 2.6, top + 3.2, p[2] * 2.6, 0.7, 4.4, 0.7, C.White, NOSHADOW)
	end
	b:span("Roof1", -3.8, top + 5.4, -3.8, 3.8, top + 6.6, 3.8, red)
	b:span("Roof2", -2.8, top + 6.6, -2.8, 2.8, top + 7.8, 2.8, lerpColor(red, C.White, 0.2))
	b:span("Roof3", -1.7, top + 7.8, -1.7, 1.7, top + 8.8, 1.7, red)
	b:vox("Top", 0, top + 9.4, 0, 1.0, 1.2, 1.0, C.Gold, DECOR)
	-- door with a frame on the front of the bottom band
	local fz = -widths[1] / 2
	b:span("DoorFrame", -1.9, 3, fz - 0.3, 1.9, 8.2, fz + 0.2, C.White)
	b:span("Door", -1.3, 3, fz - 0.45, 1.3, 7.4, fz + 0.1, C.Blue)
	-- windows on alternating faces
	local winSpots = { { 2, "front" }, { 3, "right" }, { 4, "back" }, { 5, "left" } }
	for i, s in winSpots do
		local w = widths[s[1]]
		local yy = 3 + (s[1] - 0.5) * bandH
		local h = w / 2
		if s[2] == "front" then
			b:span(`Window{i}`, -0.8, yy - 1, -h - 0.15, 0.8, yy + 1, -h + 0.1, C.WindowBlue, NOSHADOW)
		elseif s[2] == "back" then
			b:span(`Window{i}`, -0.8, yy - 1, h - 0.1, 0.8, yy + 1, h + 0.15, C.WindowBlue, NOSHADOW)
		elseif s[2] == "right" then
			b:span(`Window{i}`, h - 0.1, yy - 1, -0.8, h + 0.15, yy + 1, 0.8, C.WindowBlue, NOSHADOW)
		else
			b:span(`Window{i}`, -h - 0.15, yy - 1, -0.8, -h + 0.1, yy + 1, 0.8, C.WindowBlue, NOSHADOW)
		end
	end
	if o.light ~= false then
		light(glass, 16, 2.5, rgb(255, 220, 150))
	end
	return b:finish(plinth)
end

--[[
	windmill: stone base, three stepped cream tower tiers with wooden trim bands, windows, a
	stepped red cap, and 4 lattice sails. The bottom tier is a hollow room you can walk into: an
	open doorway in a wooden frame (the blue door stands open), a millstone, flour sacks and a
	glowing lantern (with a PointLight) inside. The sails are in a child Model "Blades" (attribute
	Spin = degrees per second, opts.spin, default 24; pivot = hub, LookVector = axis); they never
	collide. 40 parts. opts: roof = colour, spin, bladeAngle (degrees, default 45).
]]
function Props.windmill(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Windmill", cf, opts, 227)
	local o = b.opts
	local roof = o.roof or C.Red
	local base = b:span("Base", -6.5, -1.5, -6.5, 6.5, 1.5, 6.5, C.StoneLight)
	-- the bottom tier: four walls 1 thick on the base (its floor), the doorway (2.8 wide, 5 high)
	-- in the front wall; the trim band above is the room's ceiling
	b:span("Tower1", -5, 1.4, 4, 5, 10, 5, C.Cream)
	b:span("Tower1L", -5, 1.4, -4, -4, 10, 4, C.Cream)
	b:span("Tower1R", 4, 1.4, -4, 5, 10, 4, C.Cream)
	b:span("Tower1FL", -5, 1.4, -5, -1.5, 10, -4, C.Cream)
	b:span("Tower1FR", 1.5, 1.4, -5, 5, 10, -4, C.Cream)
	b:span("Tower1FTop", -1.5, 6.6, -5, 1.5, 10, -4, C.Cream)
	b:span("DoorFrame", -2.1, 6.5, -5.3, 2.1, 7.2, -4.9, C.Wood)
	b:span("DoorJambL", -2.1, 1.5, -5.3, -1.4, 6.5, -4.9, C.Wood)
	b:span("DoorJambR", 1.4, 1.5, -5.3, 2.1, 6.5, -4.9, C.Wood)
	-- the door stands wide open against the right jamb
	b:span("Door", 2.1, 1.6, -7.9, 2.45, 6.4, -5.3, C.Blue, NOSHADOW)
	-- inside: a millstone, two flour sacks in the corner, a lantern on the back wall
	b:column("Millstone", 4.4, 0.6, 1.0, 1.5, 2.6, C.Stone)
	b:span("Sack1", -3.9, 1.5, 1.6, -1.9, 3.7, 3.9, C.Canvas)
	b:span("Sack2", -3.8, 1.5, -0.8, -2.0, 3.1, 1.3, lerpColor(C.Canvas, C.Wood, 0.25))
	local lamp = b:span("Lantern", -0.7, 6.2, 3.5, 0.7, 7.8, 4.0, C.Glow, NEON)
	light(lamp, 14, 1.4)
	b:span("Trim1", -5.4, 9.6, -5.4, 5.4, 10.6, 5.4, C.Wood)
	b:span("Tower2", -4.3, 10.5, -4.3, 4.3, 17, 4.3, C.Cream)
	b:span("Trim2", -4.7, 16.6, -4.7, 4.7, 17.6, 4.7, C.Wood)
	b:span("Tower3", -3.6, 17.5, -3.6, 3.6, 21.2, 3.6, C.Cream)
	b:span("Roof1", -4.8, 21, -4.8, 4.8, 22.4, 4.8, roof)
	b:span("Roof2", -3.7, 22.4, -3.7, 3.7, 23.8, 3.7, roof)
	b:span("Roof3", -2.5, 23.8, -2.5, 2.5, 25.2, 2.5, lerpColor(roof, C.White, 0.2))
	b:span("Roof4", -1.3, 25.2, -1.3, 1.3, 26.4, 1.3, roof)
	b:vox("Vane", 0, 27.2, 0, 0.5, 1.6, 0.5, C.Gold, DECOR)
	b:span("Window1", -1, 12.2, -4.55, 1, 14.6, -4.2, C.WindowBlue, NOSHADOW)
	-- the side windows go through the walls (seen from inside the room too)
	b:span("Window2", 3.9, 4.6, -1, 5.25, 7.0, 1, C.WindowBlue, NOSHADOW)
	b:span("Window3", -5.25, 4.6, -1, -3.9, 7.0, 1, C.WindowBlue, NOSHADOW)
	b:span("Balcony", -3.2, 9.9, -6.4, 3.2, 10.6, -5.2, C.WoodDark, NOSHADOW)

	-- spinning blades
	local blades = b:group("Blades")
	blades:SetAttribute("Spin", o.spin or 24)
	local hubLocal = CFrame.new(0, 19.2, -4.6)
	local old = b:push(hubLocal * rot(0, 0, o.bladeAngle or 45))
	local hub = b:span("Hub", -1.3, -1.3, -1.3, 1.3, 1.3, 1.0, C.Red)
	b:span("HubCap", -0.6, -0.6, -1.9, 0.6, 0.6, -1.25, C.Gold, DECOR)
	b:span("ArmX", -13, -0.45, -1.0, 13, 0.45, -0.3, C.WoodDark, NOSHADOW)
	b:span("ArmY", -0.45, -13, -1.05, 0.45, 13, -0.25, C.WoodDark, NOSHADOW)
	-- each sail on the trailing side of its arm (its inner edge tucked 0.1 into the arm, so it
	-- stays attached while it turns), with a lattice bar across it
	local sails = {
		{ 2.4, 12.5, 0.35, 3.6, "x" },
		{ -12.5, -2.4, -3.6, -0.35, "x" },
		{ -3.6, -0.35, 2.4, 12.5, "y" },
		{ 0.35, 3.6, -12.5, -2.4, "y" },
	}
	for i, s in sails do
		b:span(`Sail{i}`, s[1], s[3], -0.85, s[2], s[4], -0.5, C.White, FOLIAGE)
		if s[5] == "x" then
			local xm = (s[1] + s[2]) / 2
			b:span(`Lattice{i}`, xm - 0.25, s[3], -1.05, xm + 0.25, s[4], -0.8, C.Red, DECOR)
		else
			local ym = (s[3] + s[4]) / 2
			b:span(`Lattice{i}`, s[1], ym - 0.25, -1.05, s[2], ym + 0.25, -0.8, C.Red, DECOR)
		end
	end
	b:pop(old)
	b:ungroup()
	b:finishGroup(blades, hub, hubLocal)
	ghost(blades)
	return b:finish(base)
end

--[[
	watchtower: four thick legs with a brace ring, a plank platform with a parapet (gap for the
	ladder), corner posts carrying a stepped roof with a flag, a lantern on a cord, and a climbable
	ladder (invisible TrussPart + rails and rungs). 44 parts at the default height.
	opts: roof = colour (default Blue), height (platform, 14).
]]
function Props.watchtower(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Watchtower", cf, opts, 229)
	local o = b.opts
	local H = o.height or 14
	local roof = o.roof or C.Blue
	local first
	for i, p in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		-- legs reach 5 studs into the ground, so a leg over a terrace step still stands on it
		local leg = b:vox(`Leg{i}`, p[1] * 3.8, (H - 5) / 2, p[2] * 3.8, 1.4, H + 5, 1.4, C.WoodDark)
		first = first or leg
		b:vox(`Foot{i}`, p[1] * 3.8, 0, p[2] * 3.8, 2.2, 1.2, 2.2, C.StoneLight, NOSHADOW)
	end
	local by = H * 0.42
	b:span("BraceF", -3.8, by, -4.1, 3.8, by + 0.8, -3.5, C.Wood, NOSHADOW)
	b:span("BraceB", -3.8, by, 3.5, 3.8, by + 0.8, 4.1, C.Wood, NOSHADOW)
	b:span("BraceL", -4.1, by + 0.05, -3.8, -3.5, by + 0.85, 3.8, C.Wood, NOSHADOW)
	b:span("BraceR", 3.5, by + 0.05, -3.8, 4.1, by + 0.85, 3.8, C.Wood, NOSHADOW)
	b:span("Platform", -5.2, H, -5.2, 5.2, H + 0.8, 5.2, C.WoodLight)
	-- parapet: back, sides, front split around the ladder
	local pc = C.Wood
	b:span("WallB", -5.2, H + 0.8, 4.7, 5.2, H + 2.4, 5.2, pc)
	b:span("WallL", -5.2, H + 0.8, -4.7, -4.7, H + 2.4, 4.7, pc)
	b:span("WallR", 4.7, H + 0.8, -4.7, 5.2, H + 2.4, 4.7, pc)
	b:span("WallFA", -5.2, H + 0.8, -5.2, -1.4, H + 2.4, -4.7, pc)
	b:span("WallFB", 1.4, H + 0.8, -5.2, 5.2, H + 2.4, -4.7, pc)
	b:span("WallTrim", -5.4, H + 2.4, 4.6, 5.4, H + 2.8, 5.4, roof, NOSHADOW)
	-- roof posts + stepped roof
	for i, p in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		b:vox(`RoofPost{i}`, p[1] * 4.6, H + 4.2, p[2] * 4.6, 0.7, 6.8, 0.7, C.WoodDark, NOSHADOW)
	end
	local ry = H + 7.4
	b:span("Roof1", -6.4, ry, -6.4, 6.4, ry + 1.2, 6.4, roof)
	b:span("Roof2", -4.8, ry + 1.2, -4.8, 4.8, ry + 2.4, 4.8, lerpColor(roof, C.White, 0.22))
	b:span("Roof3", -3.2, ry + 2.4, -3.2, 3.2, ry + 3.6, 3.2, roof)
	b:span("Roof4", -1.6, ry + 3.6, -1.6, 1.6, ry + 4.6, 1.6, lerpColor(roof, C.White, 0.22))
	b:span("FlagPole", -0.2, ry + 4.6, -0.2, 0.2, ry + 8.4, 0.2, C.White, DECOR)
	b:span("Flag", 0.2, ry + 6.4, -0.1, 3.0, ry + 8.2, 0.1, C.Red, FOLIAGE)
	b:vox("Lantern", 0, ry - 1.2, 0, 1.2, 1.4, 1.2, C.Glow, NEON_DECOR)
	b:span("LanternCord", -0.1, ry - 0.55, -0.1, 0.1, ry + 0.1, 0.1, C.Iron, DECOR)
	-- ladder at the front gap: an invisible TrussPart (2 studs, from the ground to 3 studs above
	-- the deck) that the Humanoid climbs, dressed as rails reaching back to the platform edge and
	-- dense rungs on its outer face
	local lz0 = -5.2 - 2 / b.s -- the truss' outer face (it is 2 studs deep)
	b:truss("LadderTruss", 0, (lz0 - 5.2) / 2, -0.3, H + 0.8 + 3 / b.s)
	for i, x in { -1.25, 1.25 } do
		b:span(`LadderRail{i}`, x - 0.2, -0.3, lz0, x + 0.2, H + 2.6, -5.2, C.WoodDark, NOSHADOW)
	end
	local rungs = math.max(3, math.floor((H + 0.8) / 1.5))
	for k = 1, rungs do
		local yy = k * (H + 0.8) / (rungs + 1)
		b:span(`Rung{k}`, -1.05, yy - 0.15, lz0, 1.05, yy + 0.15, lz0 + 0.35, C.WoodLight, DECOR)
	end
	return b:finish(first)
end

--[[
	ferrisWheel: rainbow ferris wheel (R = 18, hub ~25 studs up) on a two-tower support with a
	coloured base deck. The wheel — two rainbow rims of 16 segments, spokes, Neon bulbs and 8
	hanging gondolas — is the child Model "Wheel" (attribute Spin, default 8 deg/s; pivot = hub,
	LookVector = axis). Gondolas are Models with attribute KeepUpright = true. The wheel's parts
	never collide (the client turns it); an invisible static "WheelGuard" closes its lower part.
	105 parts. opts: radius (default 18), spin, deck (base colour).
]]
function Props.ferrisWheel(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "FerrisWheel", cf, opts, 233)
	local o = b.opts
	local R = o.radius or 18
	local hubY = R + 7
	local depth = 2.6 -- rims at z = ±depth
	-- base + support towers (front and back of the wheel)
	local base = b:span("Base", -R * 0.75, -0.6, -8, R * 0.75, 1.0, 8, C.StoneLight)
	b:span("Deck", -R * 0.7, 0.95, -7.5, R * 0.7, 1.3, 7.5, o.deck or C.Cyan, NOSHADOW)
	for i, sz in { -1, 1 } do
		local z = sz * (depth + 2.2)
		b:span(`LegL{i}`, -7.6, 1.0, z - 0.8, -6.0, hubY - 3, z + 0.8, C.White)
		b:span(`LegR{i}`, 6.0, 1.0, z - 0.8, 7.6, hubY - 3, z + 0.8, C.White)
		b:span(`Cross{i}`, -7.6, hubY - 4.4, z - 0.7, 7.6, hubY - 3, z + 0.7, C.Red)
		b:span(`Head{i}`, -1.0, hubY - 3, z - 0.8, 1.0, hubY + 1.2, z + 0.8, C.White)
		b:span(`Brace{i}`, -7.6, hubY * 0.4, z - 0.6, 7.6, hubY * 0.4 + 1.0, z + 0.6, C.Red, NOSHADOW)
	end
	b:span("Axle", -0.7, hubY - 0.7, -(depth + 3.0), 0.7, hubY + 0.7, depth + 3.0, C.Navy, NOSHADOW)
	-- ticket booth
	b:span("Booth", R * 0.45, 1.3, -7.4, R * 0.45 + 4, 5.3, -4.4, C.Cream)
	b:span("BoothRoof", R * 0.45 - 0.5, 5.3, -7.9, R * 0.45 + 4.5, 6.1, -3.9, C.Red, NOSHADOW)

	-- the wheel
	local wheel = b:group("Wheel")
	wheel:SetAttribute("Spin", o.spin or 8)
	local hubLocal = CFrame.new(0, hubY, 0)
	local old = b:push(hubLocal)
	local hub = b:span("Hub", -2.2, -2.2, -(depth + 0.8), 2.2, 2.2, depth + 0.8, C.Red)
	local N = 16
	local segLen = 2 * R * math.sin(math.pi / N) + 0.9
	for k = 0, N - 1 do
		local th = (k + 0.5) * 2 * math.pi / N
		local col = C.Festive[(math.floor(k / 2)) % #C.Festive + 1]
		local pos = Vector3.new(R * math.cos(th), R * math.sin(th), 0)
		-- neighbouring segments overlap at the joints: odd ones are 0.2 thicker, so their front
		-- and back faces never share a plane with the even ones (no flicker on the turning wheel)
		local thick = if k % 2 == 1 then 1.0 else 0.8
		for j, sz in { -1, 1 } do
			b:block(
				`Rim{k}_{j}`,
				Vector3.new(segLen, 1.2, thick),
				CFrame.new(pos + Vector3.new(0, 0, sz * depth)) * CFrame.Angles(0, 0, th + math.pi / 2),
				col,
				nil,
				NOSHADOW
			)
		end
		-- a bulb at every joint of the front rim
		local tj = k * 2 * math.pi / N
		b:block(
			`Bulb{k}`,
			Vector3.new(0.8, 0.8, 0.5),
			CFrame.new((R + 0.1) * math.cos(tj), (R + 0.1) * math.sin(tj), -depth - 0.55) * CFrame.Angles(0, 0, tj),
			C.Glow,
			nil,
			NEON_DECOR
		)
	end
	for k = 0, 3 do
		local th = k * math.pi / 4
		for j, sz in { -1, 1 } do
			b:block(
				`Spoke{k}_{j}`,
				Vector3.new(2 * R, 0.6, 0.5),
				CFrame.new(0, 0, sz * depth) * CFrame.Angles(0, 0, th),
				C.White,
				nil,
				NOSHADOW
			)
		end
	end
	-- gondolas hanging from pins between the rims
	for k = 0, 7 do
		local th = k * math.pi / 4 + math.pi / 8
		local px, py = R * math.cos(th), R * math.sin(th)
		local g = U.model(wheel, `Gondola_{k + 1}`)
		g:SetAttribute("KeepUpright", true)
		b.target = g
		local col = C.Festive[k % #C.Festive + 1]
		local pin = b:span("Pin", px - 0.3, py - 0.3, -depth, px + 0.3, py + 0.3, depth, C.Navy, DECOR)
		b:span("Hanger", px - 0.25, py - 2.2, -0.25, px + 0.25, py, 0.25, C.Navy, DECOR)
		b:span("Cabin", px - 1.8, py - 5.4, -1.6, px + 1.8, py - 2.2, 1.6, col, NOSHADOW)
		b:span("Roof", px - 2.1, py - 2.5, -1.9, px + 2.1, py - 1.9, 1.9, C.White, NOSHADOW)
		g.PrimaryPart = pin
		b.target = wheel
	end
	b:pop(old)
	b:ungroup()
	b:finishGroup(wheel, hub, hubLocal)
	ghost(wheel)
	-- the turning wheel never collides: an invisible static wall round its lower part keeps players
	-- on the deck from walking into the gondolas sweeping past
	b:span("WheelGuard", -R * 0.8, 1.3, -(depth + 1.2), R * 0.8, 12, depth + 1.2, C.White, {
		Transparency = 1,
		CastShadow = false,
		CanQuery = false,
	})
	return b:finish(base)
end

--[[
	hotAirBalloon: floating decor — a rainbow-striped voxel envelope (rounded "plus" tiers), ropes,
	a wicker basket with a rim and a glowing burner. cframe = bottom of the basket (in the air).
	19 parts, all non-colliding. opts: colors (list, bottom to top).
]]
function Props.hotAirBalloon(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "HotAirBalloon", cf, opts, 239)
	local o = b.opts
	b.s *= 1.3
	local cs = o.colors
	if not cs then
		local k = b:int(0, #C.Festive - 1)
		cs = {}
		for i = 1, 6 do
			cs[i] = C.Festive[(k + i - 1) % #C.Festive + 1]
		end
	end
	local basket = b:span("Basket", -1.8, 0, -1.8, 1.8, 2.4, 1.8, C.WoodLight, DECOR)
	b:span("Rim", -2.1, 2.2, -2.1, 2.1, 2.8, 2.1, C.WoodDark, DECOR)
	for i, p in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		b:span(
			`Rope{i}`,
			p[1] * 1.7 - 0.1,
			2.8,
			p[2] * 1.7 - 0.1,
			p[1] * 1.7 + 0.1,
			8.6,
			p[2] * 1.7 + 0.1,
			C.Rope,
			DECOR
		)
	end
	local burner = b:vox("Burner", 0, 4.4, 0, 1.0, 1.2, 1.0, C.Flame, NEON_DECOR)
	Props.fx(burner, "flame", { rate = 8, size = b.s })
	-- two thin diagonal bars from rope to rope hold the burner
	b:beam("BurnerBarA", Vector3.new(-1.7, 4.4, -1.7), Vector3.new(1.7, 4.4, 1.7), 0.2, 0.2, C.Iron, DECOR)
	b:beam("BurnerBarB", Vector3.new(-1.7, 4.4, 1.7), Vector3.new(1.7, 4.4, -1.7), 0.2, 0.2, C.Iron, DECOR)
	b:span("Neck", -2.0, 8.4, -2.0, 2.0, 10.2, 2.0, cs[1], DECOR)
	local tiers = { { 10, 13, 8 }, { 13, 17.5, 12 }, { 17.5, 21.5, 11.4 }, { 21.5, 23.8, 8.4 } }
	for i, t in tiers do
		b:cross(`Tier{i}`, 0, t[1], 0, t[2], t[3], t[3], 0.7, cs[i + 1], DECOR)
	end
	b:span("Top", -2.2, 23.7, -2.2, 2.2, 24.6, 2.2, cs[6] or cs[1], DECOR)
	return b:finish(basket)
end

--[[
	cloud: big floating voxel cloud — a flat rounded white body with a light-blue shaded
	underside, two puffs on top and puffs at the ends. cframe = bottom centre. 7-8 parts,
	CanCollide/CastShadow/CanQuery = false.
	opts: size (length along local X, default 36 by seed 30..44).
]]
function Props.cloud(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Cloud", cf, opts, 241)
	local o = b.opts
	local L = o.size or b:range(30, 44)
	local D = L * b:range(0.42, 0.52)
	local h = L * 0.1
	-- flat white body (rounded "plus") with a shaded underside, rounded puffs on top, end puffs
	local base = b:cross("Body", -L * 0.01, 0, 0, h * 1.3, L * 0.78, D * 0.82, 0.72, C.White, DECOR)
	b:span("Under", -L * 0.3, -h * 0.3, -D * 0.28, L * 0.28, 0.05, D * 0.28, C.CloudShade, DECOR)
	local x1 = b:range(-0.2, -0.08) * L
	b:cross("Puff1", x1, h * 1.2, D * 0.01, h * 1.2 + L * 0.15, L * 0.38, D * 0.7, 0.7, C.White, DECOR)
	local x2 = b:range(0.12, 0.2) * L
	b:span("Puff2", x2 - L * 0.14, h * 1.15, -D * 0.26, x2 + L * 0.14, h * 1.15 + L * 0.1, D * 0.28, C.White, DECOR)
	b:span("PuffEndL", -L * 0.5, h * 0.2, -D * 0.22, -L * 0.36, h * 1.15, D * 0.2, C.White, DECOR)
	if b:chance(0.6) then
		b:span("PuffEndR", L * 0.34, h * 0.25, -D * 0.18, L * 0.48, h * 1.1, D * 0.22, C.White, DECOR)
	end
	return b:finish(base)
end

return Props
