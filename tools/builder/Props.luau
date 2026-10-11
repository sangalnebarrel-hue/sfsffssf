--[[
	Props — library of reusable low-poly props for the world builder (trees, rocks, lamps, boats,
	piers, bridges, waterfalls, landmarks). Thousands of instances are scattered over the map,
	so every prop is lean (a part budget per prop is noted next to each constructor).

	Calling convention (all small props):
		Props.<name>(parent, cframe, opts?) -> Model
	  cframe  ground point + facing: the prop stands on cframe.Position, its front is cframe.LookVector
	          (local -Z). Boats/buoys: cframe.Position is on the water surface.
	  opts    optional table:
	          seed     number, deterministic variation (default: hashed from the position)
	          scale    uniform size multiplier (default 1)
	          variant  some props have named/numbered variants (see each constructor)
	          colour overrides: see each constructor (color, leaves, trunk, ...)
	The returned Model has PrimaryPart set to its main part, and PrimaryPart.PivotOffset is set so
	that the model pivot is exactly `cframe` (Model:PivotTo(newGroundCFrame) works at runtime).

	Big pieces take explicit points instead: Props.bridge(parent, fromPos, toPos, opts),
	Props.waterfall(parent, topPos, bottomPos, width, opts), Props.bunting(parent, a, b, opts),
	Props.fenceLine(parent, points, opts).

	Catalogue (parts per instance):
	  trees/plants  pineTree 9, roundTree 7-8, palmTree 10, bush 3, flowerPatch 6, rock 1-3,
	                stump 3, log 3, reeds 5, lilyPad 1-2, mushroom 3
	  furniture     lampPost 6, torch 3, bench 5, crate 3, crateStack 4, barrel 3,
	                fenceSegment 3-5, fenceLine, signpost 3, flowerBox 6, bunting 8, flagPole 4,
	                campfire 5, parasol 4
	  water         rowboat 12, sailboat 14, buoy 3, lifebuoy 4, dockSegment 6-8, fishingRodRack 6
	  big pieces    bridge (~150 per 150 studs), waterfall ~13, lighthouse 16, windmill 19,
	                watchtower 20
	  helpers       Props.Colors (shared palette), Props.makeRng(seed), Props.shade(c, f),
	                Props.lerpColor(a, b, t)

	No randomness from math.random: variation comes from a small Park–Miller generator seeded
	by opts.seed or by the position, so rebuilding the place gives identical output.
	Foliage, sails and flags have CanCollide = false; small details also CastShadow = false and
	CanQuery = false. Only lamps asked for (opts.light) get a PointLight (Range <= 16, no shadows).
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

--------------------------------------------------------------------------------------------
-- Palette (shared by the whole world so everything stays consistent)
--------------------------------------------------------------------------------------------

local C = {
	-- wood
	WoodLight = rgb(226, 178, 118), -- planks, seats, crates
	Wood = rgb(184, 128, 78), -- general timber
	WoodDark = rgb(124, 84, 54), -- posts, beams, frames
	WoodDeep = rgb(88, 60, 42), -- piles, shadows
	Bark = rgb(116, 80, 54),
	BarkDark = rgb(88, 62, 44),
	CutWood = rgb(238, 204, 150), -- fresh cut faces of stumps/logs
	PalmBark = rgb(196, 150, 98),
	PalmBarkDark = rgb(158, 114, 72),

	-- foliage (dark -> light)
	PineLeaves = { rgb(34, 96, 72), rgb(44, 120, 78), rgb(62, 146, 86), rgb(88, 170, 94) },
	Leaves = { rgb(68, 150, 62), rgb(98, 180, 70), rgb(138, 204, 82) },
	AutumnLeaves = { rgb(214, 96, 46), rgb(238, 146, 50), rgb(250, 196, 72) },
	BlossomLeaves = { rgb(236, 140, 182), rgb(248, 178, 206), rgb(255, 214, 230) },
	LimeLeaves = { rgb(120, 178, 54), rgb(156, 200, 62), rgb(196, 222, 90) },
	PalmLeaves = { rgb(58, 156, 74), rgb(86, 182, 78), rgb(118, 198, 84) },
	BushLeaves = { rgb(56, 132, 62), rgb(82, 160, 66), rgb(116, 186, 74) },
	Grass = rgb(98, 178, 72),
	GrassDark = rgb(72, 148, 60),

	-- flowers
	Flowers = {
		rgb(240, 72, 84), -- red
		rgb(255, 204, 64), -- yellow
		rgb(250, 124, 182), -- pink
		rgb(164, 112, 234), -- violet
		rgb(255, 250, 244), -- white
		rgb(255, 146, 64), -- orange
		rgb(96, 164, 252), -- blue
	},

	-- stone
	Rock = { rgb(112, 116, 126), rgb(136, 140, 148), rgb(160, 162, 168), rgb(184, 184, 186) },
	Moss = rgb(104, 152, 78),
	Snow = rgb(242, 247, 252),
	Stone = rgb(158, 156, 150), -- plinths, lamp bases, paving
	StoneDark = rgb(112, 110, 108),
	Sand = rgb(236, 214, 156),
	Soil = rgb(104, 74, 52),

	-- painted / built
	RoofRed = rgb(212, 74, 62),
	RoofBlue = rgb(68, 122, 200),
	RoofGreen = rgb(82, 152, 96),
	Plaster = rgb(248, 240, 222),
	White = rgb(250, 248, 244),
	Red = rgb(222, 64, 58),
	Metal = rgb(64, 66, 76),
	Iron = rgb(92, 94, 104),
	Gold = rgb(244, 196, 76),
	WindowBlue = rgb(70, 110, 160),

	-- light
	Glow = rgb(255, 214, 128), -- lantern glass (Neon)
	LightColor = rgb(255, 196, 120), -- PointLight colour
	Flame = rgb(255, 140, 40),
	FlameCore = rgb(255, 222, 96),

	-- fabric / rope
	Sail = rgb(250, 247, 238),
	Rope = rgb(214, 190, 140),
	Canvas = rgb(238, 226, 196),

	-- water
	Water = rgb(64, 156, 228),
	WaterLight = rgb(150, 212, 246),
	Foam = rgb(240, 250, 255),

	-- boat hull paints
	BoatPaint = {
		rgb(214, 70, 60), -- red
		rgb(54, 162, 172), -- teal
		rgb(66, 118, 198), -- blue
		rgb(240, 190, 64), -- yellow
		rgb(246, 244, 236), -- white
		rgb(92, 166, 92), -- green
	},
	-- bunting / flags (bright, in rainbow order)
	Festive = {
		rgb(236, 72, 72),
		rgb(255, 160, 50),
		rgb(255, 214, 64),
		rgb(96, 196, 96),
		rgb(72, 160, 240),
		rgb(166, 110, 230),
		rgb(250, 120, 180),
	},
}
Props.Colors = C

--------------------------------------------------------------------------------------------
-- Deterministic randomness
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

--------------------------------------------------------------------------------------------
-- Geometry helpers
--------------------------------------------------------------------------------------------

local UP = Vector3.new(0, 1, 0)
local RAD = math.rad

local function rot(x: number, y: number, z: number): any
	return CFrame.Angles(RAD(x), RAD(y), RAD(z))
end

-- CFrame at pos whose local +X points along xDir (for cylinders between two points).
local function frameX(pos: any, xDir: any, upHint: any?): any
	local x = xDir.Unit
	local up = upHint or UP
	if math.abs(x:Dot(up.Unit)) > 0.98 then
		up = Vector3.new(0, 0, 1)
	end
	local z = x:Cross(up).Unit
	local y = z:Cross(x).Unit
	return CFrame.fromMatrix(pos, x, y, z)
end

-- CFrame at pos whose local +Z points along zDir (for blocks/wedges between two points).
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

-- Common property sets.
local DECOR = { CanCollide = false, CastShadow = false, CanQuery = false } -- small, non-walkable details
local SOFT = { CanCollide = false } -- foliage, sails, flags: big enough to cast shadows
local NOSHADOW = { CastShadow = false }

--------------------------------------------------------------------------------------------
-- Build context: every prop is built in its own local frame (y = 0 is the ground,
-- -Z is the front) and in unscaled studs; the context applies scale and the world frame.
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
	self.count = 0
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

-- Local (unscaled) CFrame -> world CFrame.
function Ctx:world(lcf: any): any
	if self.s == 1 then
		return self.cf * lcf
	end
	return self.cf * (CFrame.new(lcf.Position * self.s) * lcf.Rotation)
end

function Ctx:worldPoint(p: any): any
	return self.cf * (p * self.s)
end

function Ctx:_add(className: string, name: string, size: any, lcf: any, color: any, material: any?, extra: any?): any
	self.count += 1
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
	return U.new(className, props, self.model)
end

function Ctx:block(name: string, size: any, lcf: any, color: any, material: any?, extra: any?): any
	return self:_add("Part", name, size, lcf, color, material, extra)
end

function Ctx:wedge(name: string, size: any, lcf: any, color: any, material: any?, extra: any?): any
	return self:_add("WedgePart", name, size, lcf, color, material, extra)
end

function Ctx:corner(name: string, size: any, lcf: any, color: any, material: any?, extra: any?): any
	return self:_add("CornerWedgePart", name, size, lcf, color, material, extra)
end

function Ctx:ball(name: string, d: number, pos: any, color: any, material: any?, extra: any?): any
	return self:_add(
		"Part",
		name,
		Vector3.new(d, d, d),
		CFrame.new(pos),
		color,
		material,
		merge({ Shape = Enum.PartType.Ball }, extra)
	)
end

-- Cylinder with its axis along local X of lcf.
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

-- Upright cylinder centred at pos.
function Ctx:cylY(name: string, d: number, h: number, pos: any, color: any, material: any?, extra: any?): any
	return self:cyl(name, d, h, CFrame.new(pos) * rot(0, 0, 90), color, material, extra)
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
	return self:cylY(name, d, y1 - y0, Vector3.new(x, (y0 + y1) / 2, z), color, material, extra)
end

-- Cylinder between two local points.
function Ctx:rod(name: string, a: any, b: any, d: number, color: any, material: any?, extra: any?): any
	local dir = b - a
	return self:cyl(name, d, dir.Magnitude, frameX((a + b) / 2, dir), color, material, extra)
end

-- Block between two local points (length along the segment), w across, h "up".
function Ctx:beam(
	name: string,
	a: any,
	b: any,
	w: number,
	h: number,
	color: any,
	material: any?,
	extra: any?,
	upHint: any?
): any
	local dir = b - a
	return self:block(name, Vector3.new(w, h, dir.Magnitude), frameZ((a + b) / 2, dir, upHint), color, material, extra)
end

-- Sets PrimaryPart + PivotOffset so the model pivot is the prop's ground CFrame.
function Ctx:finish(primary: any): any
	local model = self.model
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

local function pickColor(o: { [string]: any }, key: string, default: any): any
	local v = o[key]
	if v == nil then
		return default
	end
	return v
end

--------------------------------------------------------------------------------------------
-- TREES & PLANTS
--------------------------------------------------------------------------------------------

-- Square pyramid from 4 CornerWedges (one per quadrant, apexes meeting at the centre).
-- base = local centre of the base, a = half-width of the base, h = height, yaw in degrees.
local function pyramid(
	b: any,
	name: string,
	base: any,
	a: number,
	h: number,
	yaw: number,
	color: any,
	material: any?,
	extra: any?
)
	local first
	for q = 0, 3 do
		local cf = CFrame.new(base) * rot(0, yaw + q * 90, 0) * CFrame.new(-a / 2, h / 2, a / 2)
		local p = b:corner(`{name}{q + 1}`, Vector3.new(a, h, a), cf, color, material, extra)
		first = first or p
	end
	return first
end

local PINE_VARIANTS = {
	-- tall, dark old pine
	{ h = 31, a = 6.6, trunk = 2.0, colors = { 1, 2 } },
	-- medium pine
	{ h = 24, a = 5.6, trunk = 1.7, colors = { 2, 3 } },
	-- young bright fir
	{ h = 17, a = 4.6, trunk = 1.4, colors = { 3, 4 } },
}

--[[
	pineTree: stylised low-poly conifer — two stacked square pyramids (4 CornerWedges each,
	the upper one turned 45 deg so the silhouette is star-like from every side) on a trunk.
	9 parts. opts: variant 1..3 (tall dark / medium / young bright), snow = true (snow-capped
	top tier, for the mountains), leaves = { lower, upper } colours, trunk = colour.
]]
function Props.pineTree(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "PineTree", cf, opts, 11)
	local o = b.opts
	local v = PINE_VARIANTS[o.variant or b:int(1, 3)] or PINE_VARIANTS[2]
	b.s *= b:range(0.88, 1.12)
	b.cf = cf * rot(b:range(-2, 2), b:range(0, 360), b:range(-2, 2))

	local tint = b:range(0.94, 1.06)
	local leaves = o.leaves or { C.PineLeaves[v.colors[1]], C.PineLeaves[v.colors[2]] }
	local lower = shade(leaves[1], tint)
	local upper = shade(leaves[2] or leaves[1], tint)
	if o.snow then -- frosted: pale blue-green, whiter towards the top
		lower = lerpColor(lower, C.Snow, 0.32)
		upper = lerpColor(upper, C.Snow, 0.86)
	end
	local trunkColor = pickColor(o, "trunk", C.Bark)

	local H, A = v.h, v.a * b:range(0.92, 1.08)
	local trunk = b:column("Trunk", v.trunk, 0, 0, -1, H * 0.45, trunkColor, Mat.Wood)
	-- lower tier: wide skirt; upper tier: narrower, reaching the tip
	local y1 = H * 0.15
	local h1 = H * 0.54
	pyramid(b, "Lower", Vector3.new(0, y1, 0), A, h1, 0, lower, Mat.SmoothPlastic, SOFT)
	local y2 = y1 + h1 * 0.46
	pyramid(b, "Upper", Vector3.new(0, y2, 0), A * 0.7, H - y2, 45 + b:range(-8, 8), upper, Mat.SmoothPlastic, SOFT)
	return b:finish(trunk)
end

local ROUND_PALETTES = {
	green = "Leaves",
	autumn = "AutumnLeaves",
	blossom = "BlossomLeaves",
	lime = "LimeLeaves",
}

--[[
	roundTree: broadleaf — trunk with root flare and a side branch, 4-5 overlapping ball canopies.
	<= 8 parts. opts: palette = "green" (default) | "autumn" | "blossom" | "lime" | "mixed"
	(mixed: mostly green, sometimes autumn/lime by seed), leaves = {c1, c2, c3}, trunk = colour.
]]
function Props.roundTree(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "RoundTree", cf, opts, 23)
	local o = b.opts
	local palName = o.palette or "green"
	if palName == "mixed" then
		local r = b.rand()
		palName = r < 0.6 and "green" or (r < 0.8 and "lime" or "autumn")
	end
	local pal = o.leaves or C[ROUND_PALETTES[palName] or "Leaves"]
	local trunkColor = pickColor(o, "trunk", C.Bark)
	b.s *= b:range(0.85, 1.15)
	local yaw = b:range(0, 360)
	b.cf = cf * rot(0, yaw, 0)

	local trunkH = b:range(6.5, 8)
	local top = Vector3.new(b:range(-0.5, 0.5), trunkH, b:range(-0.5, 0.5))
	local trunk = b:rod("Trunk", Vector3.new(0, -0.8, 0), top, 2.0, trunkColor, Mat.Wood)
	local branchEnd = Vector3.new(3.2, trunkH * 0.92, 0.4)
	b:rod("Branch", Vector3.new(0.2, trunkH * 0.5, 0), branchEnd, 0.8, trunkColor, Mat.Wood)

	-- Canopy: one big central ball, side balls around it (one sits on the branch).
	local mainD = b:range(8.5, 9.8)
	local cy = trunkH + mainD * 0.32
	b:ball("Canopy", mainD, Vector3.new(top.X, cy, top.Z), pal[2], Mat.SmoothPlastic, SOFT)
	b:ball("CanopyBranch", b:range(5.2, 6.2), branchEnd + Vector3.new(0.6, 1.1, 0), pal[1], Mat.SmoothPlastic, SOFT)
	local n = b:int(2, 3)
	local a0 = b:range(70, 110)
	for i = 1, n do
		local a = RAD(a0 + (i - 1) * (250 / n) + b:range(-15, 15))
		local rr = b:range(3.0, 3.8)
		local d = b:range(5.4, 6.8)
		local col = (i % 2 == 1) and pal[3] or pal[1]
		b:ball(
			`Canopy{i}`,
			d,
			Vector3.new(top.X + rr * math.cos(a), cy + b:range(-1.6, 1.4), top.Z + rr * math.sin(a)),
			col,
			Mat.SmoothPlastic,
			SOFT
		)
	end
	-- Small crown on top for a rounder silhouette.
	b:ball(
		"CanopyTop",
		b:range(5, 5.8),
		Vector3.new(top.X + 0.4, cy + mainD * 0.38, top.Z - 0.3),
		pal[3],
		Mat.SmoothPlastic,
		SOFT
	)
	return b:finish(trunk)
end

--[[
	palmTree: curved 3-segment banded trunk, 6 drooping wedge fronds, coconuts. 10 parts.
	opts: leaves = {c1, c2}, trunk = colour, lean = degrees of the top segment (default ~26).
]]
function Props.palmTree(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "PalmTree", cf, opts, 37)
	local o = b.opts
	b.s *= b:range(0.88, 1.12)
	b.cf = cf * rot(0, b:range(0, 360), 0)
	local pal = o.leaves or C.PalmLeaves
	local bark = pickColor(o, "trunk", C.PalmBark)
	local barkDark = shade(bark, 0.8)

	local lean = o.lean or b:range(18, 30)
	local angles = { lean * 0.25, lean * 0.6, lean }
	local lens = { 5.4, 5.2, 5.0 }
	local diam = { 1.7, 1.45, 1.25 }
	local p = Vector3.new(0, -0.8, 0)
	local first
	for i = 1, 3 do
		local a = RAD(angles[i])
		local dir = Vector3.new(math.sin(a), math.cos(a), 0)
		local q = p + dir * lens[i]
		local seg =
			b:rod(`Trunk{i}`, p - dir * 0.3, q + dir * 0.3, diam[i], (i % 2 == 1) and bark or barkDark, Mat.Wood)
		first = first or seg
		p = q
	end
	local top = p + Vector3.new(0, 0.3, 0)

	local frondCount = 6
	local a0 = b:range(0, 60)
	for k = 1, frondCount do
		local az = RAD(a0 + (k - 1) * (360 / frondCount) + b:range(-12, 12))
		local droop = RAD(b:range(28, 46))
		local len = b:range(9, 10.5)
		local h = Vector3.new(math.cos(az), 0, math.sin(az))
		local dir = h * math.cos(droop) - UP * math.sin(droop)
		local side = UP:Cross(dir).Unit
		local zAxis = -dir
		local xAxis = side:Cross(zAxis).Unit
		local center = top + dir * (len / 2)
		-- roll the blade around its axis so it is also visible from the side
		local roll = RAD((k % 2 == 0) and 30 or -30)
		local lcf = CFrame.fromMatrix(center, xAxis, side, zAxis) * CFrame.Angles(0, 0, roll)
		b:wedge(`Frond{k}`, Vector3.new(0.25, 3.2, len), lcf, pal[1 + (k % #pal)], Mat.SmoothPlastic, SOFT)
	end
	b:ball("Coconuts", 1.5, top - Vector3.new(-0.3, 0.9, 0.2), rgb(112, 76, 44), Mat.SmoothPlastic, DECOR)
	return b:finish(first)
end

--[[
	bush: 3 overlapping balls in 2-3 greens. 3 parts. opts: leaves = {c1, c2, c3}, berries = colour
	(the smallest ball becomes a flowering colour).
]]
function Props.bush(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Bush", cf, opts, 41)
	local o = b.opts
	b.s *= b:range(0.8, 1.2)
	b.cf = cf * rot(0, b:range(0, 360), 0)
	local pal = o.leaves or C.BushLeaves
	local main = b:ball("Bush", b:range(4.2, 4.8), Vector3.new(0, 1.2, 0), pal[2], Mat.SmoothPlastic, SOFT)
	b:ball("Bush2", b:range(3.2, 3.6), Vector3.new(2.0, 0.8, 0.7), pal[1], Mat.SmoothPlastic, SOFT)
	b:ball("Bush3", b:range(2.7, 3.1), Vector3.new(-1.5, 0.75, -1.2), o.berries or pal[3], Mat.SmoothPlastic, DECOR)
	return b:finish(main)
end

--[[
	flowerPatch: a grass tuft dome with 5 flower heads. 6 parts.
	opts: colors = {c1, c2} (default: a random pair from Colors.Flowers).
]]
function Props.flowerPatch(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "FlowerPatch", cf, opts, 53)
	local o = b.opts
	b.cf = cf * rot(0, b:range(0, 360), 0)
	local c1 = o.colors and o.colors[1] or b:pick(C.Flowers)
	local c2 = o.colors and o.colors[2] or b:pick({ C.Flowers[5], C.Flowers[2], b:pick(C.Flowers) })
	local tuft = b:ball("Tuft", 2.6, Vector3.new(0, -0.35, 0), C.GrassDark, Mat.SmoothPlastic, DECOR)
	local spots = {
		Vector3.new(0, 1.15, 0),
		Vector3.new(0.85, 0.85, 0.3),
		Vector3.new(-0.6, 0.85, 0.7),
		Vector3.new(-0.5, 0.8, -0.8),
		Vector3.new(0.55, 0.75, -0.85),
	}
	for i, pos in spots do
		local j = Vector3.new(b:range(-0.15, 0.15), b:range(0, 0.25), b:range(-0.15, 0.15))
		b:ball(`Flower{i}`, (i == 1) and 0.95 or 0.75, pos + j, (i % 2 == 1) and c1 or c2, Mat.SmoothPlastic, DECOR)
	end
	return b:finish(tuft)
end

--[[
	rock: boulder made of two blocks turned 45 deg to each other with different tilts (a faceted,
	irregular silhouette) + a pebble or a snow/moss cap. 1-3 parts.
	opts: count = 1..3, snow = true (white cap), moss = true (green cap), color = base grey.
]]
function Props.rock(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Rock", cf, opts, 67)
	local o = b.opts
	b.cf = cf * rot(0, b:range(0, 360), 0)
	local base = o.color or b:pick({ C.Rock[1], C.Rock[2], C.Rock[2], C.Rock[3] })
	local count = o.count or ((o.snow or o.moss) and 3 or b:pick({ 2, 2, 3 }))

	-- main: a taller tilted chunk; Rock2: a wider, lower slab turned 45 deg under/beside it
	local sx, sy, sz = b:range(4.0, 5.4), b:range(3.8, 5.0), b:range(3.6, 4.8)
	local mainCf = CFrame.new(0, sy * 0.25, 0) * rot(b:range(-22, 22), 0, b:range(-22, 22))
	local main = b:block("Rock", Vector3.new(sx, sy, sz), mainCf, base, Mat.Slate)
	if count >= 2 then
		local a = RAD(b:range(0, 360))
		b:block(
			"Rock2",
			Vector3.new(sx * b:range(0.9, 1.1), sy * b:range(0.55, 0.7), sz * b:range(0.95, 1.1)),
			CFrame.new(1.7 * math.cos(a), sy * 0.12, 1.7 * math.sin(a))
				* rot(b:range(-16, 16), 45 + b:range(-8, 8), b:range(-16, 16)),
			shade(base, b:range(0.9, 0.97)),
			Mat.Slate
		)
	end
	if count >= 3 then
		if o.snow or o.moss then
			-- cap lying on the top face of the main block
			b:block(
				"RockCap",
				Vector3.new(sx * 0.78, 0.6, sz * 0.78),
				mainCf * CFrame.new(0, sy / 2 + 0.12, 0),
				o.snow and C.Snow or C.Moss,
				Mat.SmoothPlastic,
				NOSHADOW
			)
		else
			local a = RAD(b:range(0, 360))
			local d = math.max(sx, sz) * 0.62 + 0.4
			local ps = b:range(1.5, 2.2)
			b:block(
				"Pebble",
				Vector3.new(ps * 1.25, ps * 0.85, ps),
				CFrame.new(d * math.cos(a), ps * 0.2, d * math.sin(a))
					* rot(b:range(-20, 20), b:range(0, 90), b:range(-20, 20)),
				shade(base, 0.88),
				Mat.Slate
			)
		end
	end
	return b:finish(main)
end

--[[
	stump: cut stump with a fresh-cut top ring and one root. 3 parts.
]]
function Props.stump(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Stump", cf, opts, 71)
	b.cf = cf * rot(0, b:range(0, 360), 0)
	b.s *= b:range(0.85, 1.15)
	local main = b:column("Stump", 2.6, 0, 0, -0.5, 1.5, C.Bark, Mat.Wood)
	b:column("CutFace", 2.1, 0, 0, 1.4, 1.6, C.CutWood, Mat.Wood, DECOR)
	b:wedge("Root", Vector3.new(0.9, 1.0, 1.5), CFrame.new(0, 0.2, -1.55) * rot(0, 0, 0), C.BarkDark, Mat.Wood, DECOR)
	return b:finish(main)
end

--[[
	log: fallen log lying along local X with light end caps. 3 parts. opts: length (default 6).
]]
function Props.log(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Log", cf, opts, 73)
	local o = b.opts
	b.cf = cf * rot(0, b:range(-25, 25), 0)
	local len = o.length or b:range(5.5, 7.5)
	local d = b:range(1.6, 2.1)
	local main = b:cyl("Log", d, len, CFrame.new(0, d * 0.42, 0), C.Bark, Mat.Wood)
	b:cyl("EndA", d * 0.78, 0.2, CFrame.new(len / 2 + 0.03, d * 0.42, 0), C.CutWood, Mat.Wood, DECOR)
	b:cyl("EndB", d * 0.78, 0.2, CFrame.new(-len / 2 - 0.03, d * 0.42, 0), C.CutWood, Mat.Wood, DECOR)
	return b:finish(main)
end

--[[
	reeds: shore reeds / cattails, 3 stalks + 2 brown heads. 5 parts. Stand in shallow water too.
]]
function Props.reeds(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Reeds", cf, opts, 79)
	b.cf = cf * rot(0, b:range(0, 360), 0)
	local first
	local spots = { Vector3.new(0, 0, 0), Vector3.new(0.9, 0, 0.4), Vector3.new(-0.5, 0, 0.8) }
	local tops = {}
	for i, p in spots do
		local h = b:range(3.4, 5.2)
		local tip = p + Vector3.new(b:range(-0.6, 0.6), h, b:range(-0.6, 0.6))
		local stalk =
			b:beam(`Stalk{i}`, p - Vector3.new(0, 1, 0), tip, 0.22, 0.22, C.GrassDark, Mat.SmoothPlastic, DECOR)
		first = first or stalk
		tops[i] = { p = p, tip = tip }
	end
	for i = 1, 2 do
		local t = tops[i]
		local dir = (t.tip - t.p).Unit
		b:rod(`Cattail{i}`, t.tip - dir * 1.6, t.tip - dir * 0.4, 0.5, rgb(120, 78, 46), Mat.SmoothPlastic, DECOR)
	end
	return b:finish(first)
end

--[[
	lilyPad: floating pad (+ a pink flower on some). 1-2 parts. cframe on the water surface.
]]
function Props.lilyPad(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "LilyPad", cf, opts, 83)
	local o = b.opts
	b.s *= b:range(0.8, 1.25)
	local lift = b:range(0, 0.12) -- neighbouring pads never share a top plane
	local pad = b:column("Pad", 2.6, 0, 0, -0.05 - lift, 0.12 + lift, C.Leaves[1], Mat.SmoothPlastic, DECOR)
	if o.flower == true or (o.flower == nil and b.rand() < 0.4) then
		b:ball("Flower", 0.8, Vector3.new(0.3, 0.35, -0.2), rgb(250, 160, 200), Mat.SmoothPlastic, DECOR)
	end
	return b:finish(pad)
end

--[[
	mushroom: cute stem + two-step red cap. 3 parts. opts: color (cap).
]]
function Props.mushroom(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Mushroom", cf, opts, 89)
	local o = b.opts
	b.s *= b:range(0.7, 1.3)
	local cap = o.color or b:pick({ C.Red, C.Red, rgb(240, 150, 60), rgb(200, 150, 110) })
	local stem = b:column("Stem", 0.8, 0, 0, -0.3, 1.3, C.Plaster, Mat.SmoothPlastic, DECOR)
	b:column("Cap", 2.2, 0, 0, 1.2, 1.75, cap, Mat.SmoothPlastic, DECOR)
	b:column("CapTop", 1.3, 0, 0, 1.7, 2.1, shade(cap, 1.08), Mat.SmoothPlastic, DECOR)
	return b:finish(stem)
end

--------------------------------------------------------------------------------------------
-- LIGHTS & STREET FURNITURE
--------------------------------------------------------------------------------------------

-- Lantern box hanging from / standing on a point: cap + Neon glass + bottom plate. 3 parts.
-- `top` is the local point where the top of the cap is.
local function lantern(b: any, top: any, k: number, withLight: boolean?, prefix: string?): any
	local pre = prefix or ""
	b:block(
		pre .. "LanternCap",
		Vector3.new(1.7, 0.45, 1.7) * k,
		CFrame.new(top - Vector3.new(0, 0.225 * k, 0)),
		C.Metal,
		Mat.Metal,
		NOSHADOW
	)
	local glass = b:block(
		pre .. "LanternGlass",
		Vector3.new(1.15, 1.55, 1.15) * k,
		CFrame.new(top - Vector3.new(0, (0.4 + 0.775) * k, 0)),
		C.Glow,
		Mat.Neon,
		DECOR
	)
	b:block(
		pre .. "LanternBase",
		Vector3.new(1.45, 0.35, 1.45) * k,
		CFrame.new(top - Vector3.new(0, (0.4 + 1.5 + 0.175) * k, 0)),
		C.Metal,
		Mat.Metal,
		NOSHADOW
	)
	if withLight then
		light(glass, 14, 1.6)
	end
	return glass
end

--[[
	lampPost: stone foot, wooden post, arm towards the front (-Z) with a hanging lantern
	(Neon glass). 6 parts. opts: light = true adds a PointLight (use on a few key lamps),
	height (default 10).
]]
function Props.lampPost(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "LampPost", cf, opts, 97)
	local o = b.opts
	local h = o.height or 10
	b:block("Foot", Vector3.new(1.8, 1.2, 1.8), CFrame.new(0, 0.4, 0), C.Stone, Mat.Slate)
	local post = b:block("Post", Vector3.new(0.8, h, 0.8), CFrame.new(0, 0.5 + h / 2, 0), C.WoodDark, Mat.Wood)
	b:block("Arm", Vector3.new(0.5, 0.5, 3.0), CFrame.new(0, h - 0.2, -1.6), C.WoodDark, Mat.Wood, NOSHADOW)
	lantern(b, Vector3.new(0, h - 0.4, -2.45), 1, o.light == true)
	return b:finish(post)
end

--[[
	torch: stick, dark wrap, glowing flame. 3 parts. opts: light = true (PointLight),
	fire = true (adds a small Fire effect — use sparingly).
]]
function Props.torch(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Torch", cf, opts, 101)
	local o = b.opts
	local h = o.height or 4.6
	local stick = b:column("Stick", 0.45, 0, 0, -0.8, h, C.WoodDark, Mat.Wood, NOSHADOW)
	b:column("Wrap", 0.85, 0, 0, h - 0.5, h + 0.2, C.Metal, Mat.Metal, DECOR)
	local flame = b:block(
		"Flame",
		Vector3.new(0.8, 0.8, 0.8),
		CFrame.new(0, h + 0.55, 0) * rot(45, 0, 35),
		C.Flame,
		Mat.Neon,
		DECOR
	)
	if o.light then
		light(flame, 12, 1.4, rgb(255, 160, 80))
	end
	if o.fire then
		U.new("Fire", { Size = 2, Heat = 4, Color = C.Flame, SecondaryColor = C.FlameCore }, flame)
	end
	return b:finish(stick)
end

--[[
	bench: plank seat on two slab legs, a tilted backrest resting on the seat with a dark top rail;
	you sit facing -Z. 5 parts. opts: length (default 6), color (planks).
]]
function Props.bench(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Bench", cf, opts, 103)
	local o = b.opts
	local L = o.length or 6
	local wood = o.color or C.WoodLight
	local seat = b:block("Seat", Vector3.new(L, 0.45, 1.9), CFrame.new(0, 1.95, 0), wood, Mat.WoodPlanks)
	for i, x in { -L / 2 + 0.6, L / 2 - 0.6 } do
		b:block(`Leg{i}`, Vector3.new(0.5, 1.85, 1.7), CFrame.new(x, 0.85, 0), C.WoodDark, Mat.Wood)
	end
	local tilt = rot(12, 0, 0)
	local up = (tilt * CFrame.new(0, 1, 0)).Position
	local bottom = Vector3.new(0, 2.15, 0.78)
	b:block("Back", Vector3.new(L - 0.2, 1.4, 0.3), CFrame.new(bottom + up * 0.7) * tilt, wood, Mat.WoodPlanks)
	b:block(
		"BackRail",
		Vector3.new(L + 0.1, 0.28, 0.5),
		CFrame.new(bottom + up * 1.5) * tilt,
		C.WoodDark,
		Mat.Wood,
		NOSHADOW
	)
	return b:finish(seat)
end

--[[
	crate: wooden crate with a dark frame along the edges. 3 parts. opts: size (default 3), color.
]]
function Props.crate(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Crate", cf, opts, 107)
	local o = b.opts
	local s = o.size or 3
	b.cf = cf * rot(0, b:range(-8, 8), 0)
	local panel = o.color or C.WoodLight
	local frame = shade(panel, 0.62)
	local core = b:block("Crate", Vector3.new(s, s, s), CFrame.new(0, s / 2, 0), frame, Mat.Wood)
	b:block("SidePanels", Vector3.new(s + 0.1, s * 0.76, s + 0.1), CFrame.new(0, s / 2, 0), panel, Mat.WoodPlanks)
	b:block("TopPanel", Vector3.new(s * 0.78, s + 0.1, s * 0.78), CFrame.new(0, s / 2, 0), panel, Mat.WoodPlanks)
	return b:finish(core)
end

--[[
	crateStack: two crates, a small one on top and a sack. 4 parts.
]]
function Props.crateStack(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "CrateStack", cf, opts, 109)
	b.cf = cf * rot(0, b:range(0, 360), 0)
	local c1 = C.WoodLight
	local c2 = shade(C.Wood, 1.05)
	local main = b:block(
		"CrateA",
		Vector3.new(3, 3, 3),
		CFrame.new(-1.6, 1.5, 0) * rot(0, b:range(-6, 6), 0),
		c1,
		Mat.WoodPlanks
	)
	b:block(
		"CrateB",
		Vector3.new(2.6, 2.6, 2.6),
		CFrame.new(1.45, 1.22, 0.3) * rot(0, b:range(10, 25), 0),
		c2,
		Mat.WoodPlanks
	)
	b:block(
		"CrateTop",
		Vector3.new(2.2, 2.2, 2.2),
		CFrame.new(-1.3, 4.1, 0.1) * rot(0, b:range(20, 40), 0),
		shade(c1, 0.92),
		Mat.WoodPlanks
	)
	b:ball("Sack", 2.2, Vector3.new(0.6, 0.75, -2.0), C.Canvas, Mat.Fabric)
	return b:finish(main)
end

--[[
	barrel: wooden barrel with two metal hoops. 3 parts. opts: color.
]]
function Props.barrel(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Barrel", cf, opts, 113)
	local o = b.opts
	local body = b:column("Barrel", 2.6, 0, 0, -0.1, 3.4, o.color or C.Wood, Mat.Wood)
	b:column("HoopLow", 2.76, 0, 0, 0.55, 0.9, C.Metal, Mat.Metal, NOSHADOW)
	b:column("HoopHigh", 2.76, 0, 0, 2.35, 2.7, C.Metal, Mat.Metal, NOSHADOW)
	return b:finish(body)
end

--[[
	fenceSegment: rustic fence centred on cframe, running along local X. Posts at the ends
	(+ a middle post when longer than 10) and two rails in front of them. <= 5 parts.
	opts: length (default 8), posts = "both" | "start" | "end" | "none" (for chaining),
	height (default 3.4), color (rails).
]]
function Props.fenceSegment(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Fence", cf, opts, 127)
	local o = b.opts
	local L = o.length or 8
	local h = o.height or 3.4
	local posts = o.posts or "both"
	local rail = o.color or C.Wood
	local main =
		b:block("RailTop", Vector3.new(L - 0.1, 0.45, 0.3), CFrame.new(0, h * 0.78, -0.42), rail, Mat.WoodPlanks)
	b:block("RailLow", Vector3.new(L - 0.1, 0.45, 0.3), CFrame.new(0, h * 0.38, -0.42), rail, Mat.WoodPlanks)
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
		b:block(`Post{i}`, Vector3.new(0.7, h + 1, 0.7), CFrame.new(x, (h - 1) / 2, 0), C.WoodDark, Mat.Wood)
	end
	return b:finish(main)
end

--[[
	fenceLine: fence along a polyline of world points (ground level), no doubled posts.
	opts are passed to fenceSegment (height, color). Returns a Model containing the segments.
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
			posts = (i == #points - 1) and "both" or "start",
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

local function addSignText(part: any, face: any, text: string, color: any)
	local gui = U.new("SurfaceGui", {
		Name = "SignGui" .. face.Name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0.2,
	}, part)
	U.new("TextLabel", {
		Name = "Text",
		AnchorPoint = U.Vector2.new(0.5, 0.5),
		Position = U.UDim2.fromScale(0.5, 0.5),
		Size = U.UDim2.fromScale(0.9, 0.8),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = color,
	}, gui)
end

--[[
	signpost: post + board (text on both sides) + a little roof plank. 3 parts.
	opts: text (default "→"), textColor, color (board), width (default 5).
]]
function Props.signpost(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Signpost", cf, opts, 131)
	local o = b.opts
	local w = o.width or 5
	local post = b:block("Post", Vector3.new(0.6, 6.4, 0.6), CFrame.new(0, 2.4, 0), C.WoodDark, Mat.Wood)
	local board =
		b:block("Board", Vector3.new(w, 1.8, 0.35), CFrame.new(0, 4.3, -0.45), o.color or C.WoodLight, Mat.WoodPlanks)
	b:block(
		"BoardCap",
		Vector3.new(w + 0.4, 0.3, 0.75),
		CFrame.new(0, 5.33, -0.42),
		C.RoofRed,
		Mat.SmoothPlastic,
		NOSHADOW
	)
	local text = o.text or "→"
	local tc = o.textColor or rgb(90, 56, 34)
	addSignText(board, Enum.NormalId.Front, text, tc)
	if o.twoSided ~= false then
		addSignText(board, Enum.NormalId.Back, text, tc)
	end
	return b:finish(post)
end

--[[
	flowerBox: wooden planter with greenery and 4 flower heads. 6 parts.
	opts: length (default 4), colors = {c1, c2}.
]]
function Props.flowerBox(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "FlowerBox", cf, opts, 137)
	local o = b.opts
	local L = o.length or 4
	local c1 = o.colors and o.colors[1] or b:pick(C.Flowers)
	local c2 = o.colors and o.colors[2] or b:pick(C.Flowers)
	local box = b:block("Box", Vector3.new(L, 1.2, 1.4), CFrame.new(0, 0.6, 0), C.Wood, Mat.WoodPlanks)
	b:block("Greens", Vector3.new(L - 0.3, 0.7, 1.1), CFrame.new(0, 1.35, 0), C.Leaves[2], Mat.SmoothPlastic, DECOR)
	for i = 1, 4 do
		local x = -L / 2 + 0.3 + (L - 0.6) * (i - 0.5) / 4
		b:ball(
			`Flower{i}`,
			0.8,
			Vector3.new(x, 1.8 + b:range(-0.05, 0.15), b:range(-0.25, 0.25)),
			(i % 2 == 1) and c1 or c2,
			Mat.SmoothPlastic,
			DECOR
		)
	end
	return b:finish(box)
end

--[[
	bunting: festive pennant string between two world points with a gentle sag:
	2 rope segments + 6 triangular pennants. 8 parts. opts: sag (default 8% of length),
	colors (list).
]]
function Props.bunting(parent: any, fromPos: any, toPos: any, opts: { [string]: any }?): any
	local o = opts or {}
	local mid = (fromPos + toPos) / 2
	local d = toPos - fromPos
	local L = d.Magnitude
	local flat = Vector3.new(d.X, 0, d.Z)
	local cf = CFrame.lookAt(mid, mid + (flat.Magnitude > 0.01 and flat or Vector3.new(0, 0, -1)))
	local b = begin(parent, "Bunting", cf, o, 139)
	b.cf = CFrame.new() -- build directly in world space
	b.s = 1
	local sag = o.sag or L * 0.08
	local low = mid - Vector3.new(0, sag, 0)
	local first = b:beam("RopeA", fromPos, low, 0.14, 0.14, C.Rope, Mat.SmoothPlastic, DECOR)
	b:beam("RopeB", low, toPos, 0.14, 0.14, C.Rope, Mat.SmoothPlastic, DECOR)
	local colors = o.colors or C.Festive
	local n = 6
	local size = math.clamp(L / (n + 1) * 0.62, 1.0, 2.6)
	local offset = b:int(0, #colors - 1)
	for i = 1, n do
		local t = i / (n + 1)
		local p, q
		if t <= 0.5 then
			p = fromPos + (low - fromPos) * (t * 2)
			q = low - fromPos
		else
			p = low + (toPos - low) * ((t - 0.5) * 2)
			q = toPos - low
		end
		local along = q.Unit
		local yAxis = (along + UP).Unit -- local +Y
		local zAxis = (along - UP).Unit -- local +Z
		local xAxis = yAxis:Cross(zAxis).Unit
		-- Wedge's hypotenuse lies on the rope; the right-angle corner hangs down.
		local legLen = size / math.sqrt(2)
		b:wedge(
			`Pennant{i}`,
			Vector3.new(0.08, legLen, legLen),
			CFrame.fromMatrix(p - Vector3.new(0, 0.2, 0), xAxis, yAxis, zAxis),
			colors[1 + (offset + i - 1) % #colors],
			Mat.Fabric,
			DECOR
		)
	end
	return b:finish(first)
end

--[[
	flagPole: pole with a gold knob and a flag pointing along local +X. 4 parts.
	opts: height (default 12), color (flag).
]]
function Props.flagPole(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "FlagPole", cf, opts, 149)
	local o = b.opts
	local h = o.height or 12
	b:column("Foot", 1.4, 0, 0, -0.4, 0.6, C.Stone, Mat.Slate)
	local pole = b:column("Pole", 0.4, 0, 0, 0, h, C.White, Mat.SmoothPlastic)
	b:ball("Knob", 0.7, Vector3.new(0, h + 0.25, 0), C.Gold, Mat.SmoothPlastic, DECOR)
	b:block(
		"Flag",
		Vector3.new(3.6, 2.2, 0.1),
		CFrame.new(1.95, h - 1.4, 0) * rot(0, b:range(-12, 12), 0),
		o.color or b:pick(C.Festive),
		Mat.Fabric,
		SOFT
	)
	return b:finish(pole)
end

--[[
	campfire: stone ring, two crossed logs, flame. 5 parts. opts: light = true, fire = true.
]]
function Props.campfire(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Campfire", cf, opts, 151)
	local o = b.opts
	local ring = b:column("Stones", 3.6, 0, 0, -0.3, 0.35, C.StoneDark, Mat.Slate)
	b:column("Ash", 2.6, 0, 0, 0.3, 0.45, rgb(60, 52, 48), Mat.SmoothPlastic, DECOR)
	b:cyl("LogA", 0.7, 3.0, CFrame.new(0, 0.7, 0) * rot(0, 30, 18), C.Bark, Mat.Wood, DECOR)
	b:cyl("LogB", 0.7, 3.0, CFrame.new(0, 0.75, 0) * rot(0, -60, -18), C.BarkDark, Mat.Wood, DECOR)
	local flame =
		b:block("Flame", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 1.35, 0) * rot(45, 20, 35), C.Flame, Mat.Neon, DECOR)
	if o.light then
		light(flame, 14, 1.6, rgb(255, 160, 80))
	end
	if o.fire then
		U.new("Fire", { Size = 3, Heat = 6, Color = C.Flame, SecondaryColor = C.FlameCore }, flame)
	end
	return b:finish(ring)
end

--[[
	parasol: beach umbrella (pole + two-step striped canopy). 4 parts. opts: color.
]]
function Props.parasol(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Parasol", cf, opts, 157)
	local o = b.opts
	local col = o.color or b:pick({ C.Red, C.RoofBlue, rgb(255, 196, 60), rgb(60, 180, 170) })
	b.cf = cf * rot(b:range(-6, 6), 0, b:range(-6, 6))
	local pole = b:column("Pole", 0.3, 0, 0, -1, 6.4, C.White, Mat.SmoothPlastic, NOSHADOW)
	b:column("Canopy", 7, 0, 0, 5.6, 6.1, col, Mat.Fabric, SOFT)
	b:column("CanopyMid", 4.6, 0, 0, 6.05, 6.55, C.White, Mat.Fabric, SOFT)
	b:column("CanopyTop", 2.2, 0, 0, 6.5, 6.95, col, Mat.Fabric, SOFT)
	return b:finish(pole)
end

--------------------------------------------------------------------------------------------
-- WATER THINGS
--------------------------------------------------------------------------------------------

--[[
	Shared hull: solid body + two flat bow wedges (pointed bow towards -Z) + painted gunwale
	planks (2 sides, 2 bow, transom). 8 parts. Returns the body.
	L = overall length, W = beam, bowLen = length of the pointed part, y0 = hull bottom,
	deckY = top of the solid body (inside floor), rimY = top of the gunwale.
]]
local function hull(
	b: any,
	L: number,
	W: number,
	bowLen: number,
	y0: number,
	deckY: number,
	rimY: number,
	paint: any,
	wood: any
): any
	local hw = W / 2
	local stern = L / 2
	local bowStart = -L / 2 + bowLen -- z where the pointed bow begins
	local bodyLen = stern - bowStart
	local body = b:block(
		"Hull",
		Vector3.new(W, deckY - y0, bodyLen),
		CFrame.new(0, (y0 + deckY) / 2, (stern + bowStart) / 2),
		wood,
		Mat.WoodPlanks
	)
	local bowCz = bowStart - bowLen / 2
	local by = (y0 + deckY) / 2
	local bh = deckY - y0
	b:wedge(
		"BowR",
		Vector3.new(bh, hw, bowLen),
		CFrame.fromMatrix(
			Vector3.new(hw / 2, by, bowCz),
			Vector3.new(0, -1, 0),
			Vector3.new(1, 0, 0),
			Vector3.new(0, 0, 1)
		),
		wood,
		Mat.WoodPlanks
	)
	b:wedge(
		"BowL",
		Vector3.new(bh, hw, bowLen),
		CFrame.fromMatrix(
			Vector3.new(-hw / 2, by, bowCz),
			Vector3.new(0, 1, 0),
			Vector3.new(-1, 0, 0),
			Vector3.new(0, 0, 1)
		),
		wood,
		Mat.WoodPlanks
	)
	-- painted gunwale planks
	local t = 0.32
	local ph = rimY - (deckY - 0.3)
	local py = (rimY + deckY - 0.3) / 2
	local z0, z1 = bowStart - 0.15, stern - 0.075
	for i, sx in { -1, 1 } do
		b:block(
			i == 1 and "SideL" or "SideR",
			Vector3.new(t, ph, z1 - z0),
			CFrame.new(sx * (hw - 0.04), py, (z0 + z1) / 2),
			paint,
			Mat.WoodPlanks
		)
	end
	local tip = Vector3.new(0, py, -L / 2 - 0.15)
	for i, sx in { -1, 1 } do
		local a = Vector3.new(sx * (hw - 0.04), py, bowStart)
		local dir = (tip - a)
		local len = dir.Magnitude + 0.35
		local center = a + dir.Unit * (len / 2 - 0.12)
		b:block(
			i == 1 and "BowSideL" or "BowSideR",
			Vector3.new(t + 0.06 * i, ph + 0.12 * i, len),
			frameZ(center, dir),
			paint,
			Mat.WoodPlanks
		)
	end
	b:block(
		"Transom",
		Vector3.new(W + 0.5, ph + 0.06, t),
		CFrame.new(0, py + 0.07, stern + 0.02),
		paint,
		Mat.WoodPlanks
	)
	return body
end

--[[
	rowboat: painted hull, two seats, two oars. 12 parts. cframe on the water surface, bow = -Z.
	opts: color (paint, default random from Colors.BoatPaint), oars = false (no oars).
]]
function Props.rowboat(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Rowboat", cf, opts, 163)
	local o = b.opts
	local paint = o.color or b:pick(C.BoatPaint)
	local body = hull(b, 9.2, 3.6, 3.3, -0.55, 0.35, 1.25, paint, C.Wood)
	b:block("SeatFront", Vector3.new(3.3, 0.25, 1.0), CFrame.new(0, 0.85, -0.6), C.WoodLight, Mat.WoodPlanks, NOSHADOW)
	b:block("SeatBack", Vector3.new(3.3, 0.25, 1.1), CFrame.new(0, 0.85, 2.7), C.WoodLight, Mat.WoodPlanks, NOSHADOW)
	if o.oars ~= false then
		for i, sx in { -1, 1 } do
			-- oar resting in the oarlock, blade dipping towards the water behind the boat
			local a = Vector3.new(sx * 1.1, 1.15, 0.6)
			local c = Vector3.new(sx * 4.6, -0.1, 3.4)
			b:beam(`Oar{i}`, a, c, 0.55, 0.14, C.WoodLight, Mat.Wood, DECOR, Vector3.new(0, 1, 0))
		end
	end
	return b:finish(body)
end

--[[
	sailboat: bigger hull with a cabin, mast, boom, white main sail + jib, red pennant on top.
	14 parts. cframe on the water surface, bow = -Z.
	opts: color (hull paint), sailColor, swing (main sail angle, degrees).
]]
function Props.sailboat(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Sailboat", cf, opts, 167)
	local o = b.opts
	local paint = o.color or b:pick(C.BoatPaint)
	local sail = o.sailColor or C.Sail
	local L, W = 17, 6.4
	local deckY = 0.9
	local body = hull(b, L, W, 5.6, -0.9, deckY, 1.9, paint, C.WoodLight)
	local mastZ = -1.6
	local mastH = 17
	b:column("Mast", 0.55, 0, mastZ, deckY - 0.2, deckY + mastH, C.WoodDark, Mat.Wood)
	local swing = RAD(o.swing or b:range(-22, 22))
	local boomY = deckY + 2.4
	local boomLen = 8.6
	local pivot = CFrame.new(0, 0, mastZ) * CFrame.Angles(0, swing, 0)
	-- Main sail: wedge with its right angle at the mast foot (above the boom), hypotenuse = leech.
	local sailH = mastH - 3.2
	b:wedge(
		"MainSail",
		Vector3.new(0.12, sailH, boomLen - 0.6),
		pivot * CFrame.new(0, boomY + 0.25 + sailH / 2, (boomLen - 0.6) / 2 + 0.3) * CFrame.Angles(0, math.pi, 0),
		sail,
		Mat.Fabric,
		SOFT
	)
	-- Jib: right angle at the mast front at deck level, hypotenuse = forestay to the bow.
	local jibH = mastH - 5
	local jibL = 5.4
	b:wedge(
		"Jib",
		Vector3.new(0.12, jibH, jibL),
		CFrame.new(0, deckY + 0.6 + jibH / 2, mastZ - 0.45 - jibL / 2) * CFrame.Angles(0, swing * 0.5, 0),
		shade(sail, 0.96),
		Mat.Fabric,
		SOFT
	)
	b:block(
		"Pennant",
		Vector3.new(0.08, 0.8, 1.8),
		CFrame.new(0, deckY + mastH - 0.5, mastZ + 1.0),
		C.Red,
		Mat.Fabric,
		DECOR
	)
	b:block("Cabin", Vector3.new(3.6, 1.6, 3.4), CFrame.new(0, deckY + 0.75, 3.4), C.Plaster, Mat.SmoothPlastic)
	b:block(
		"CabinRoof",
		Vector3.new(4.0, 0.35, 3.8),
		CFrame.new(0, deckY + 1.7, 3.4),
		paint,
		Mat.SmoothPlastic,
		NOSHADOW
	)
	return b:finish(body)
end

--[[
	buoy: red float, white band, red top. 3 parts. cframe on the water surface.
	opts: color (default red), light = true (top glows).
]]
function Props.buoy(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Buoy", cf, opts, 173)
	local o = b.opts
	local col = o.color or C.Red
	b.cf = cf * rot(b:range(-6, 6), 0, b:range(-6, 6))
	local body = b:column("Float", 2.6, 0, 0, -0.8, 0.7, col, Mat.SmoothPlastic)
	b:column("Band", 2.0, 0, 0, 0.65, 1.6, C.White, Mat.SmoothPlastic, NOSHADOW)
	b:ball(
		"Top",
		1.3,
		Vector3.new(0, 1.95, 0),
		o.light and C.Glow or col,
		o.light and Mat.Neon or Mat.SmoothPlastic,
		DECOR
	)
	return b:finish(body)
end

--[[
	lifebuoy: ring mounted on a post/wall: cframe = ring centre, front (-Z) facing out.
	Red/white square ring. 4 parts.
]]
function Props.lifebuoy(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Lifebuoy", cf, opts, 179)
	local o = b.opts
	local red = o.color or C.Red
	local main = b:block("RingTop", Vector3.new(2.6, 0.6, 0.5), CFrame.new(0, 1.0, 0), red, Mat.SmoothPlastic, DECOR)
	b:block("RingBottom", Vector3.new(2.6, 0.6, 0.5), CFrame.new(0, -1.0, 0), red, Mat.SmoothPlastic, DECOR)
	b:block("RingLeft", Vector3.new(0.5, 1.5, 0.36), CFrame.new(-1.0, 0, 0), C.White, Mat.SmoothPlastic, DECOR)
	b:block("RingRight", Vector3.new(0.5, 1.5, 0.36), CFrame.new(1.0, 0, 0), C.White, Mat.SmoothPlastic, DECOR)
	return b:finish(main)
end

--[[
	dockSegment: pier section. cframe = top centre of the deck; it runs along local Z.
	Deck (WoodPlanks) + 2 side stringers + 4 corner piles (sticking up as bollards) + a cross
	brace. <= 8 parts. opts: length (12), width (8), depth (how far piles reach below the deck, 12),
	piles = "both" (default) | "front" (-Z end only) | "back" (+Z end only) | false (no piles) —
	chain segments with "front" so joints don't get doubled piles.
]]
function Props.dockSegment(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Dock", cf, opts, 181)
	local o = b.opts
	local L = o.length or 12
	local W = o.width or 8
	local depth = o.depth or 12
	local deck = b:block("Deck", Vector3.new(W, 0.6, L), CFrame.new(0, -0.3, 0), C.WoodLight, Mat.WoodPlanks)
	local sh = b:range(0.8, 1.05) -- stringer depth varies per segment (no shared planes at joints)
	for i, sx in { -1, 1 } do
		b:block(
			`Stringer{i}`,
			Vector3.new(0.6, sh, L - 0.1),
			CFrame.new(sx * (W / 2 - 0.15), -0.4 - sh / 2, 0),
			C.WoodDark,
			Mat.Wood
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
				-- uneven pile tops look natural and keep joined segments from z-fighting
				b:column(`Pile{j}_{i}`, 1.1, sx * (W / 2 + 0.45), z, -depth, b:range(0.9, 1.4), C.WoodDeep, Mat.Wood)
			end
		end
		local bz = zs[#zs]
		b:beam(
			"Brace",
			Vector3.new(-(W / 2 + 0.45), -1.2, bz),
			Vector3.new(W / 2 + 0.45, -math.min(depth - 1, 4.5), bz),
			0.5,
			0.6,
			C.WoodDark,
			Mat.Wood,
			NOSHADOW
		)
	end
	return b:finish(deck)
end

--[[
	fishingRodRack: two posts + crossbar with 3 rods leaning on it (facing -Z). 6 parts.
]]
function Props.fishingRodRack(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "RodRack", cf, opts, 191)
	local main
	for i, x in { -2.3, 2.3 } do
		local p = b:block(`Post{i}`, Vector3.new(0.5, 4.4, 0.5), CFrame.new(x, 1.7, 0), C.WoodDark, Mat.Wood)
		main = main or p
	end
	b:block("Bar", Vector3.new(5.4, 0.4, 0.45), CFrame.new(0, 3.5, -0.1), C.Wood, Mat.Wood, NOSHADOW)
	local rodColors = { rgb(214, 70, 60), rgb(240, 190, 64), rgb(66, 118, 198) }
	for i = 1, 3 do
		local x = -1.5 + (i - 1) * 1.5
		local a = Vector3.new(x, 0.1, -1.25)
		local c = Vector3.new(x + b:range(-0.3, 0.3), 7.6, 1.8)
		b:beam(`Rod{i}`, a, c, 0.2, 0.2, rodColors[i], Mat.SmoothPlastic, DECOR)
	end
	return b:finish(main)
end

--------------------------------------------------------------------------------------------
-- BIG PIECES
--------------------------------------------------------------------------------------------

--[[
	bridge(parent, fromPos, toPos, opts): long flat wooden walkway between two points.
	Deck top at opts.deckY (default 4), width opts.width (10), piles down to opts.bedY (-14).
	Railings both sides, lantern posts every ~opts.lanternSpacing (24) on both sides with
	PointLights on every other pair (opts.lights = false: none), timber gates at both ends
	(default on bridges >= 40 studs; opts.gates = true/false forces it), opts.bunting = true adds pennant strings across the deck at the
	lantern pairs (+8 parts each, opts.buntingEvery = 2 for every other pair).
	Deck in ~16-stud sections, continuous rails, so a 160-stud bridge is ~150 parts.
]]
function Props.bridge(parent: any, fromPos: any, toPos: any, opts: { [string]: any }?): any
	local o = opts or {}
	local deckY = o.deckY or 4
	local W = o.width or 10
	local bedY = o.bedY or -14
	local bedLocal = bedY - deckY -- local y is relative to the deck top
	local waterLocal = (o.waterY or 0) - deckY
	local a = Vector3.new(fromPos.X, deckY, fromPos.Z)
	local c = Vector3.new(toPos.X, deckY, toPos.Z)
	local L = (c - a).Magnitude
	local mid = (a + c) / 2
	-- local -Z points from `from` to `to`; local z runs from +L/2 (from) to -L/2 (to).
	local cf = CFrame.lookAt(mid, c)
	local b = begin(parent, "Bridge", cf, o, 197)
	b.s = 1
	local hw = W / 2
	local deckT = 0.9
	local wood = o.color or C.WoodLight

	-- deck in sections of ~16 studs with alternating plank tones (rhythm without per-plank parts)
	local nsec = math.max(1, math.floor(L / 16 + 0.5))
	local secL = L / nsec
	local deck
	for k = 0, nsec - 1 do
		local z = L / 2 - secL * (k + 0.5)
		local part = b:block(
			`Deck{k + 1}`,
			Vector3.new(W, deckT, secL),
			CFrame.new(0, -deckT / 2, z),
			(k % 2 == 0) and wood or shade(wood, 0.9),
			Mat.WoodPlanks
		)
		deck = deck or part
	end
	-- edge kerbs and stringers
	for i, sx in { -1, 1 } do
		b:block(
			`Kerb{i}`,
			Vector3.new(0.92, 0.35, L - 0.1),
			CFrame.new(sx * (hw - 0.34), 0.12, 0),
			C.WoodDark,
			Mat.Wood,
			NOSHADOW
		)
		b:block(
			`Stringer{i}`,
			Vector3.new(0.9, 1.4, L - 0.4),
			CFrame.new(sx * (hw - 0.2), -deckT - 0.6, 0),
			C.WoodDark,
			Mat.Wood
		)
	end

	-- pile bents
	local bentStep = o.bentSpacing or 16
	local nb = math.max(1, math.floor((L - 4) / bentStep + 0.5))
	local step = (L - 4) / nb
	for k = 0, nb do
		local z = L / 2 - 2 - k * step
		local cap = -deckT - 1.3 - 0.45
		b:block(`Cap{k}`, Vector3.new(W + 1.8, 1.0, 1.3), CFrame.new(0, cap, z), C.WoodDark, Mat.Wood)
		for i, sx in { -1, 1 } do
			b:column(`Pile{k}_{i}`, 1.4, sx * (hw - 0.1), z, bedLocal, cap + 0.2, C.WoodDeep, Mat.Wood)
		end
		local s = (k % 2 == 0) and 1 or -1
		b:beam(
			`Brace{k}`,
			Vector3.new(-s * (hw - 0.1), cap - 0.6, z + 0.75),
			Vector3.new(s * (hw - 0.1), math.max(bedLocal + 1, waterLocal - 1.5), z + 0.75),
			0.45,
			0.6,
			C.WoodDark,
			Mat.Wood,
			NOSHADOW
		)
	end

	-- railings: continuous rails, posts every ~8 studs, lantern posts every ~24
	local railH = 3.4
	for i, sx in { -1, 1 } do
		local x = sx * (hw - 0.4)
		b:block(`HandRail{i}`, Vector3.new(0.4, 0.4, L), CFrame.new(x, railH, 0), wood, Mat.WoodPlanks)
		b:block(
			`MidRail{i}`,
			Vector3.new(0.26, 0.3, L - 0.3),
			CFrame.new(x, railH * 0.5, 0),
			C.Wood,
			Mat.Wood,
			NOSHADOW
		)
	end
	local lanternStep = o.lanternSpacing or 24
	local nl = math.max(1, math.floor(L / lanternStep + 0.5))
	local lstep = L / nl
	local postStep = lstep / math.max(1, math.floor(lstep / 8 + 0.5))
	local np = math.floor(L / postStep + 0.5)
	local lightsOn = o.lights ~= false
	local gates = o.gates
	if gates == nil then
		gates = L >= 40 -- short river crossings look better without gates
	end
	local lanternIndex = 0
	for k = 0, np do
		local z = L / 2 - k * postStep
		z = math.clamp(z, -L / 2 + 0.5, L / 2 - 0.5)
		local dist = k * postStep
		local isLantern = math.abs(dist / lstep - math.floor(dist / lstep + 0.5)) < 0.01
		if gates and (k == 0 or k == np) then
			isLantern = false -- the gates carry their own lanterns
		end
		if isLantern then
			lanternIndex += 1
		end
		for i, sx in { -1, 1 } do
			local x = sx * (hw - 0.4)
			if isLantern then
				local top = railH + 4.6
				b:block(
					`LampPost{k}_{i}`,
					Vector3.new(0.9, top + 0.5, 0.9),
					CFrame.new(x, (top - 0.5) / 2, z),
					C.WoodDark,
					Mat.Wood
				)
				-- lantern standing on top of the post
				local lt = Vector3.new(x, top - 0.05 + 2.25 * 0.9, z)
				lantern(b, lt, 0.9, lightsOn and (lanternIndex % 2 == 1) and i == 1, `L{k}_{i}`)
			else
				b:block(
					`RailPost{k}_{i}`,
					Vector3.new(0.6, railH + 0.75, 0.6),
					CFrame.new(x, (railH - 0.05) / 2, z),
					C.WoodDark,
					Mat.Wood
				)
			end
		end
	end

	-- optional festive bunting across the bridge between opposite lantern posts
	if o.bunting then
		local k = 0
		local d = lstep
		while d < L - 1 do
			local z = L / 2 - d
			local top = railH + 4.0
			local pa = b:worldPoint(Vector3.new(-(hw - 0.4), top, z))
			local pb = b:worldPoint(Vector3.new(hw - 0.4, top, z))
			k += 1
			Props.bunting(b.model, pa, pb, { seed = k, sag = 1.2, name = `Bunting{k}` })
			d += lstep * (o.buntingEvery or 1)
		end
	end

	-- gates at both ends: two tall posts, a crossbeam with a little roof
	if gates then
		for e, z in { L / 2 - 0.7, -L / 2 + 0.7 } do
			local gh = 11
			for i, sx in { -1, 1 } do
				b:block(
					`GatePost{e}_{i}`,
					Vector3.new(1.2, gh + 0.5, 1.2),
					CFrame.new(sx * (hw + 0.4), (gh - 1.5) / 2, z),
					C.WoodDark,
					Mat.Wood
				)
			end
			b:block(`GateBeam{e}`, Vector3.new(W + 3.6, 1.0, 1.4), CFrame.new(0, gh - 1.4, z), C.Wood, Mat.Wood)
			b:block(
				`GateTie{e}`,
				Vector3.new(W + 0.6, 0.6, 0.9),
				CFrame.new(0, gh - 3.0, z),
				C.WoodDark,
				Mat.Wood,
				NOSHADOW
			)
			-- lantern hanging under the tie beam, lit
			lantern(b, Vector3.new(0, gh - 3.25, z), 1.1, lightsOn, `Gate{e}`)
			b:wedge(
				`GateRoofA{e}`,
				Vector3.new(W + 5, 1.3, 1.6),
				CFrame.new(0, gh - 0.3, z - 0.8),
				C.RoofRed,
				Mat.SmoothPlastic
			)
			b:wedge(
				`GateRoofB{e}`,
				Vector3.new(W + 5, 1.3, 1.6),
				CFrame.new(0, gh - 0.3, z + 0.8) * rot(0, 180, 0),
				C.RoofRed,
				Mat.SmoothPlastic
			)
		end
	end
	return b:finish(deck)
end

--[[
	waterfall(parent, topPos, bottomPos, width, opts): stylised falling sheet from the lip
	(topPos, centre of the river at the edge) to the plunge point (bottomPos, pool surface).
	Layered translucent sheets + white streaks + a curling crest + a foam ring with puffs,
	optional cheap mist ParticleEmitter (opts.mist = false to disable). ~13 parts
	(opts.streaks, opts.puffs change the counts).
	opts.flow = horizontal Vector3 the water flows towards (default: from top to bottom, or
	towards the lake centre (0,0,0) when the fall is vertical).
]]
function Props.waterfall(parent: any, topPos: any, bottomPos: any, width: number, opts: { [string]: any }?): any
	local o = opts or {}
	local W = width
	local drop = topPos - bottomPos
	local up = drop.Unit
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
	local n = (flow - up * flow:Dot(up)).Unit -- sheet front normal (downstream)
	local zAxis = -n
	local xAxis = up:Cross(zAxis).Unit
	local H = drop.Magnitude
	local center = (topPos + bottomPos) / 2
	local cf = CFrame.fromMatrix(center, xAxis, up, zAxis)
	local b = begin(parent, "Waterfall", cf, o, 211)
	b.s = 1
	local rand = b.rand

	local sheetExtra = { CanCollide = false, CastShadow = false, CanQuery = false }
	-- Upper sheet against the cliff; the lower sheet is wider and stands a bit forward, so the
	-- fall seems to spread and bulge as it drops. Local y: +H/2 = lip, -H/2 = pool surface.
	local split = H * 0.45 -- height of the lower sheet
	local back = b:block(
		"Sheet",
		Vector3.new(W, H - split + 1.2, 1.2),
		CFrame.new(0, H / 2 + 0.7 - (H - split + 1.2) / 2, 0),
		rgb(72, 164, 232),
		Mat.SmoothPlastic,
		sheetExtra
	)
	b:block(
		"SheetLow",
		Vector3.new(W * 1.1, split + 0.6, 1.2),
		CFrame.new(0, -H / 2 - 0.3 + (split + 0.6) / 2, -0.55),
		rgb(84, 174, 236),
		Mat.SmoothPlastic,
		sheetExtra
	)
	b:block(
		"SheetFront",
		Vector3.new(W * 0.8, H - 1.6, 0.5),
		CFrame.new(W * 0.04, -0.4, -1.45),
		C.WaterLight,
		Mat.Glass,
		merge(sheetExtra, { Transparency = 0.35 })
	)
	-- white streaks of different widths and lengths
	local streaks = o.streaks or 4
	for i = 1, streaks do
		local x = (-0.4 + 0.8 * (i - 0.5) / streaks + (rand() - 0.5) * 0.1) * W
		local len = H * (0.45 + 0.45 * rand())
		local y = -H / 2 + len / 2 + rand() * (H - len) * 0.5
		b:block(
			`Streak{i}`,
			Vector3.new(math.max(0.7, W * (0.04 + 0.05 * rand())), len, 0.3),
			CFrame.new(x, y, -1.95 - 0.07 * i),
			C.Foam,
			Mat.SmoothPlastic,
			sheetExtra
		)
	end
	-- crest: water curling over the lip
	b:block(
		"Crest",
		Vector3.new(W + 0.4, 1.1, 3.4),
		CFrame.new(0, H / 2 - 0.2, 0.4) * rot(-28, 0, 0),
		rgb(120, 196, 240),
		Mat.SmoothPlastic,
		merge(sheetExtra, { Transparency = 0.1 })
	)
	-- foam at the bottom: built in a level frame at the plunge point, -Z downstream
	local fwd = Vector3.new(n.X, 0, n.Z)
	fwd = fwd.Magnitude > 0.01 and fwd.Unit or flow
	b.cf = CFrame.lookAt(bottomPos, bottomPos + fwd)
	local foam = b:column(
		"Foam",
		W * 1.25,
		0,
		-W * 0.22,
		-0.25,
		0.4,
		C.Foam,
		Mat.SmoothPlastic,
		merge(sheetExtra, { Transparency = 0.25 })
	)
	b:column(
		"FoamInner",
		W * 0.8,
		0,
		-W * 0.05,
		-0.2,
		0.75,
		C.Foam,
		Mat.SmoothPlastic,
		merge(sheetExtra, { Transparency = 0.15 })
	)
	local puffs = o.puffs or 3
	for i = 1, puffs do
		local x = (-0.36 + 0.72 * (i - 0.5) / puffs + (rand() - 0.5) * 0.1) * W
		local d = W * (0.26 + 0.1 * rand())
		b:ball(
			`Puff{i}`,
			d,
			Vector3.new(x, d * 0.12, -0.6 - rand() * 1.4),
			C.Foam,
			Mat.SmoothPlastic,
			merge(sheetExtra, { Transparency = 0.1 })
		)
	end
	b.cf = cf
	if o.mist ~= false then
		U.new("ParticleEmitter", {
			Name = "Mist",
			Rate = 6,
			Lifetime = roblox.NumberRange.new(1.6, 2.6),
			Speed = roblox.NumberRange.new(2, 5),
			SpreadAngle = U.Vector2.new(50, 50),
			Size = roblox.NumberSequence.new({
				roblox.NumberSequenceKeypoint.new(0, W * 0.25),
				roblox.NumberSequenceKeypoint.new(1, W * 0.5),
			}),
			Transparency = roblox.NumberSequence.new({
				roblox.NumberSequenceKeypoint.new(0, 0.55),
				roblox.NumberSequenceKeypoint.new(1, 1),
			}),
			Color = roblox.ColorSequence.new(C.Foam),
			Acceleration = Vector3.new(0, 2, 0),
			LightEmission = 0.1,
			EmissionDirection = Enum.NormalId.Top,
		}, foam)
	end
	return b:finish(back)
end

--[[
	lighthouse: red/white striped tapering tower on a stone plinth, gallery with parapet,
	glowing lantern room (Neon + PointLight), stepped red roof, door and windows. 16 parts.
	opts: light = false (no PointLight), stripe = colour (default red).
]]
function Props.lighthouse(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Lighthouse", cf, opts, 223)
	local o = b.opts
	local red = o.stripe or C.Red
	local plinth = b:column("Plinth", 15, 0, 0, -1.5, 2, C.Stone, Mat.Slate)
	local y = 2
	local bandH = 5.6
	local radii = {}
	for i = 1, 5 do
		local d = 10.4 - (i - 1) * 0.8
		radii[i] = d / 2
		b:column(`Band{i}`, d, 0, 0, y - 0.05, y + bandH, (i % 2 == 1) and C.White or red, Mat.SmoothPlastic)
		y += bandH
	end
	local top = y -- 30
	b:column("Gallery", 10.6, 0, 0, top - 0.05, top + 0.8, C.Metal, Mat.Metal)
	b:column("Parapet", 9.6, 0, 0, top + 0.75, top + 1.9, C.White, Mat.SmoothPlastic)
	local glass = b:column("Lantern", 5.2, 0, 0, top + 1.0, top + 5.0, C.Glow, Mat.Neon, NOSHADOW)
	b:column("RoofBase", 6.8, 0, 0, top + 4.95, top + 5.8, red, Mat.SmoothPlastic)
	b:column("Roof", 4.8, 0, 0, top + 5.75, top + 7.0, red, Mat.SmoothPlastic)
	b:column("RoofTop", 2.6, 0, 0, top + 6.95, top + 8.1, red, Mat.SmoothPlastic)
	b:ball("Finial", 1.1, Vector3.new(0, top + 8.5, 0), C.Metal, Mat.Metal, NOSHADOW)
	b:block(
		"Door",
		Vector3.new(2.6, 4.0, 1.2),
		CFrame.new(0, 2 + 2.0, -(radii[1] - 0.25)),
		C.WoodDark,
		Mat.WoodPlanks,
		NOSHADOW
	)
	b:block(
		"Window1",
		Vector3.new(1.4, 2.0, 1.0),
		CFrame.new(0, 2 + bandH * 2.5, -(radii[3] - 0.15)),
		C.WindowBlue,
		Mat.SmoothPlastic,
		NOSHADOW
	)
	b:block(
		"Window2",
		Vector3.new(1.4, 2.0, 1.0),
		CFrame.new(0, 2 + bandH * 3.5, radii[4] - 0.15),
		C.WindowBlue,
		Mat.SmoothPlastic,
		NOSHADOW
	)
	if o.light ~= false then
		light(glass, 16, 2.5, rgb(255, 220, 150))
	end
	return b:finish(plinth)
end

--[[
	windmill: stone foot, plaster tower with a wooden gallery, gabled cap, 4 sails turned to the
	front (-Z). 19 parts. opts: roof = colour, bladeAngle = degrees.
]]
function Props.windmill(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Windmill", cf, opts, 227)
	local o = b.opts
	local roof = o.roof or C.RoofRed
	local foot = b:column("Foot", 13, 0, 0, -1, 1.6, C.Stone, Mat.Slate)
	b:column("TowerLow", 10.6, 0, 0, 1.5, 11, C.Plaster, Mat.SmoothPlastic)
	b:column("Gallery", 13.4, 0, 0, 10.6, 11.4, C.WoodDark, Mat.WoodPlanks)
	b:column("TowerHigh", 9.0, 0, 0, 11.3, 20, C.Plaster, Mat.SmoothPlastic)
	-- cap: timber box + gable roof (ridge along Z, towards the sails)
	b:block("CapBox", Vector3.new(8.4, 2.6, 10), CFrame.new(0, 21.2, -0.4), C.Wood, Mat.WoodPlanks)
	local rw, rh, rl = 5.0, 3.6, 11.4
	b:wedge(
		"RoofL",
		Vector3.new(rl, rh, rw),
		CFrame.new(-rw / 2, 22.5 + rh / 2, -0.4) * rot(0, 90, 0),
		roof,
		Mat.SmoothPlastic
	)
	b:wedge(
		"RoofR",
		Vector3.new(rl, rh, rw),
		CFrame.new(rw / 2, 22.5 + rh / 2, -0.4) * rot(0, -90, 0),
		roof,
		Mat.SmoothPlastic
	)
	b:block("Door", Vector3.new(3.0, 4.6, 1.0), CFrame.new(0, 3.95, -5.05), C.WoodDark, Mat.WoodPlanks, NOSHADOW)
	b:block(
		"Window1",
		Vector3.new(1.6, 2.0, 1.0),
		CFrame.new(-2.6, 7.4, -4.55) * rot(0, 30, 0),
		C.WindowBlue,
		Mat.SmoothPlastic,
		NOSHADOW
	)
	b:block(
		"Window2",
		Vector3.new(1.6, 2.0, 1.0),
		CFrame.new(0, 15.6, -4.25),
		C.WindowBlue,
		Mat.SmoothPlastic,
		NOSHADOW
	)
	-- sails
	local hubZ = -7.4
	local hubY = 21.4
	b:cyl("Hub", 1.8, 2.8, CFrame.new(0, hubY, hubZ + 0.9) * rot(0, 90, 0), C.Metal, Mat.Metal)
	local a0 = o.bladeAngle or b:range(0, 90)
	for k = 1, 4 do
		local a = RAD(a0 + (k - 1) * 90)
		local dir = Vector3.new(math.cos(a), math.sin(a), 0)
		local side = Vector3.new(-math.sin(a), math.cos(a), 0)
		local spanLen = 12
		b:beam(
			`Spar{k}`,
			Vector3.new(0, hubY, hubZ - 0.2) + dir * 0.6,
			Vector3.new(0, hubY, hubZ - 0.2) + dir * spanLen,
			0.45,
			0.45,
			C.WoodDark,
			Mat.Wood,
			NOSHADOW,
			Vector3.new(0, 0, 1)
		)
		local c = Vector3.new(0, hubY, hubZ - 0.45) + dir * (spanLen * 0.58 + 0.6) + side * 1.45
		b:block(
			`Sail{k}`,
			Vector3.new(2.5, spanLen * 0.78, 0.15),
			CFrame.fromMatrix(c, side, dir, Vector3.new(0, 0, 1)),
			C.Sail,
			Mat.Fabric,
			SOFT
		)
	end
	return b:finish(foot)
end

--[[
	watchtower: four leaning legs, cross braces, a plank platform with a parapet, a ladder and a
	pyramid-ish roof (two wedges + cap). 20 parts. opts: roof = colour, height (platform, 14).
]]
function Props.watchtower(parent: any, cf: any, opts: { [string]: any }?): any
	local b = begin(parent, "Watchtower", cf, opts, 229)
	local o = b.opts
	local H = o.height or 14
	local roof = o.roof or C.RoofBlue
	local baseHalf, topHalf = 4.2, 3.2
	local first
	for i, p in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local a = Vector3.new(p[1] * baseHalf, -1, p[2] * baseHalf)
		local t = Vector3.new(p[1] * topHalf, H + 5.6, p[2] * topHalf)
		local leg = b:beam(`Leg{i}`, a, t, 0.9, 0.9, C.WoodDark, Mat.Wood)
		first = first or leg
	end
	-- braces on the four sides (X shapes are too costly: one diagonal per side)
	local by0, by1 = 1.5, H - 1.2
	local hb0 = baseHalf - (baseHalf - topHalf) * (by0 + 1) / (H + 6.6)
	local hb1 = baseHalf - (baseHalf - topHalf) * (by1 + 1) / (H + 6.6)
	for i, side in { { 1, 0 }, { 0, 1 }, { -1, 0 }, { 0, -1 } } do
		local nx, nz = side[1], side[2]
		local tx, tz = -nz, nx
		local a = Vector3.new(nx * hb0 + tx * hb0, by0, nz * hb0 + tz * hb0)
		local c = Vector3.new(nx * hb1 - tx * hb1, by1, nz * hb1 - tz * hb1)
		b:beam(`Brace{i}`, a, c, 0.45, 0.45, C.Wood, Mat.Wood, NOSHADOW)
	end
	local ph = topHalf + 0.9
	b:block("Platform", Vector3.new(ph * 2 + 0.6, 0.6, ph * 2 + 0.6), CFrame.new(0, H, 0), C.WoodLight, Mat.WoodPlanks)
	-- parapet: 4 plank walls
	for i, side in { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
		local isZ = side[1] == 0
		local size = isZ and Vector3.new(ph * 2 + 0.6, 1.6, 0.35) or Vector3.new(0.35, 1.6, ph * 2 - 0.1)
		b:block(
			`Wall{i}`,
			size,
			CFrame.new(side[1] * (ph + 0.12), H + 1.1, side[2] * (ph + 0.12)),
			C.Wood,
			Mat.WoodPlanks
		)
	end
	-- roof: two gable wedges + a ridge cap
	local rw = ph + 1.2
	b:wedge("RoofA", Vector3.new(rw * 2, 2.6, rw), CFrame.new(0, H + 6.0 + 1.3, -rw / 2), roof, Mat.SmoothPlastic)
	b:wedge(
		"RoofB",
		Vector3.new(rw * 2, 2.6, rw),
		CFrame.new(0, H + 6.0 + 1.3, rw / 2) * rot(0, 180, 0),
		roof,
		Mat.SmoothPlastic
	)
	b:block(
		"RoofSlab",
		Vector3.new(rw * 2 + 0.2, 0.5, rw * 2 + 0.2),
		CFrame.new(0, H + 5.85, 0),
		shade(roof, 0.8),
		Mat.SmoothPlastic
	)
	-- ladder: two rails at the front
	for i, x in { -0.8, 0.8 } do
		b:beam(
			`Ladder{i}`,
			Vector3.new(x, -0.5, -baseHalf - 1.6),
			Vector3.new(x, H + 0.2, -ph - 0.5),
			0.3,
			0.3,
			C.WoodDark,
			Mat.Wood,
			NOSHADOW
		)
	end
	b:column("FlagPole", 0.25, 0, 0, H + 8.0, H + 11.6, C.WoodDark, Mat.Wood, DECOR)
	b:block("Flag", Vector3.new(0.1, 1.4, 2.4), CFrame.new(0, H + 10.8, 1.25), C.Red, Mat.Fabric, DECOR)
	return b:finish(first)
end

return Props
