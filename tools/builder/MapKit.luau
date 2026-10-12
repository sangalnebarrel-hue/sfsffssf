--[[
	MapKit — shared helpers of the World v3 map dressing modules (Promenade, Gateways,
	Landmarks, Nature, Coast; assembled by Map.luau). Style contract: tools/builder/DESIGN.md §1.

	  Kit.rng(seed)                     deterministic Park–Miller generator: r() in [0, 1),
	                                    r(a, b) in [a, b)
	  Kit.prop(name, ...)               calls Props.<name>(...) (errors if missing)
	  Kit.ground(world, x, z, yaw)      CFrame standing on the voxel column under (x, z), turned
	                                    by yaw degrees about +Y (yaw 0: a prop's front faces -Z)
	  Kit.facing(x, y, z, tx, tz)       CFrame at (x, y, z) whose front (-Z) looks at (tx, ?, tz)
	  Kit.angleDistance(a, b)           |a - b| in degrees, wrapped to [0, 180]
	  Kit.radial(angle, r, lx, lz)      world point of the radial frame: origin at radius r on the
	                                    ray `angle`, lz outwards, lx sideways (VoxelWorld.radialLocal)
	  Kit.builder(parent, name, cf)     local-frame block builder (see Builder below)
	  Kit.sign(part, face, text, ...)   big readable SurfaceGui text (Util.FONT, TextScaled)
	  Kit.light(part, range, ...)       PointLight (Range <= 16, no shadows), counted in Kit.lights
	  Kit.claim / Kit.isClaimed         areas taken by landmarks, gateways, … (Nature avoids them)
	  Kit.stairs(...)                   walkable 1-stud steps that follow the voxel ground
	  Kit.ramp(...)                     sloped walkable block between two top points (boardwalks,
	                                    or an invisible collider over visible steps)
	  Kit.rampPath(...)                 paved path over the voxel terraces: slabs + wedge ramps
	  Kit.lamp / Kit.flowerMeadow       cheap chunky lamp (4 parts), flower meadow (5 parts)
	  Kit.bench                         cheap chunky bench (4 parts)
	  Kit.flowerBed                     planted box: blooms on stems (2 + 2 per flower)
	  Kit.smoke / Kit.sparkles /        particle effects inside a part (no parts, low rates for
	  Kit.foam / Kit.petals             phones): campfire smoke, magic sparkles or fireflies, white
	                                    water foam / spray / mist, drifting petals

	Property presets (pass as `extra`): DECOR (tiny non-walkable details), NOSHADOW, NEON,
	NEON_DECOR. Builder parts are Locked (a stray drag in Studio cannot move generated dressing).
]]

local U = require("./Util")
local Props = require("./Props")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Enum = U.Enum
local Mat = Enum.Material

local rad, abs, floor, max, min = math.rad, math.abs, math.floor, math.max, math.min

local Kit = {}

Kit.C = Props.Colors
Kit.shade = Props.shade
Kit.lerpColor = Props.lerpColor

Kit.DECOR = { CanCollide = false, CastShadow = false, CanQuery = false }
Kit.NOSHADOW = { CastShadow = false }
Kit.NEON = { Material = Mat.Neon, CastShadow = false }
Kit.NEON_DECOR = { Material = Mat.Neon, CastShadow = false, CanCollide = false, CanQuery = false }

--------------------------------------------------------------------------------------------
-- Randomness, props, placement
--------------------------------------------------------------------------------------------

-- Park–Miller generator (exact in doubles). r() -> [0, 1), r(a, b) -> [a, b).
function Kit.rng(seed: number): (a: number?, b: number?) -> number
	local s = floor(abs(seed)) % 2147483646 + 1
	return function(a: number?, b: number?): number
		s = (s * 16807) % 2147483647
		local t = (s - 1) / 2147483646
		if a and b then
			return a + (b - a) * t
		end
		return t
	end
end

-- Props.<name>(...) with a clear error when the constructor does not exist.
function Kit.prop(name: string, ...: any): any
	local fn = (Props :: any)[name]
	if type(fn) ~= "function" then
		error(`Props.{name} is missing`)
	end
	return fn(...)
end

-- Ground CFrame on top of the voxel column under (x, z), turned by yaw degrees about Y.
function Kit.ground(world: any, x: number, z: number, yaw: number?): any
	return CFrame.new(x, world:heightAt(x, z), z) * CFrame.Angles(0, rad(yaw or 0), 0)
end

-- CFrame at (x, y, z) whose front (local -Z) looks horizontally towards (tx, tz).
function Kit.facing(x: number, y: number, z: number, tx: number, tz: number): any
	local p = Vector3.new(x, y, z)
	local t = Vector3.new(tx, y, tz)
	if (t - p).Magnitude < 1e-3 then
		return CFrame.new(p)
	end
	return CFrame.lookAt(p, t)
end

function Kit.angleDistance(a: number, b: number): number
	return abs(((a - b + 180) % 360) - 180)
end

-- World point (x, z) of the radial frame at `angle`: origin at radius r, lz outwards, lx to the
-- right of a viewer facing the lagoon (the same frame as VoxelWorld.radialLocal / bases).
function Kit.radial(angle: number, r: number, lx: number, lz: number): (number, number)
	local a = rad(angle)
	local ux, uz = math.sin(a), math.cos(a)
	-- radialLocal: lx = dx*uz - dz*ux, lz = dx*ux + dz*uz  =>  dx = lx*uz + lz*ux, dz = -lx*ux + lz*uz
	local x = (r + lz) * ux + lx * uz
	local z = (r + lz) * uz - lx * ux
	return x, z
end

-- CFrame of the radial frame (y up, local +Z outwards = away from the lagoon centre).
function Kit.radialCFrame(angle: number, r: number, lx: number, lz: number, y: number): any
	local x, z = Kit.radial(angle, r, lx, lz)
	return CFrame.new(x, y, z) * CFrame.Angles(0, rad(angle), 0)
end

--------------------------------------------------------------------------------------------
-- Lights and signs
--------------------------------------------------------------------------------------------

Kit.lights = 0

function Kit.light(part: any, range: number, brightness: number?, color: any?): any
	Kit.lights += 1
	return U.new("PointLight", {
		Name = "Light",
		Range = min(range, 16),
		Brightness = brightness or 1.4,
		Color = color or Kit.C.LightColor,
		Shadows = false,
	}, part)
end

-- Big readable sign text (DESIGN.md §1): Nunito ExtraBold, TextScaled; white text gets a dark
-- outline, dark text none. opts: pps (pixels per stud, default 32), size (0..1 of the face).
function Kit.sign(part: any, face: any, text: string, color: any?, stroke: any?, opts: { [string]: any }?): any
	local o = opts or {}
	local gui = U.new("SurfaceGui", {
		Name = "Sign" .. face.Name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = o.pps or 32,
		LightInfluence = 0.15,
		MaxDistance = o.maxDistance or 600,
	}, part)
	local label = U.new("TextLabel", {
		Name = "Text",
		AnchorPoint = U.Vector2.new(0.5, 0.5),
		Position = U.UDim2.fromScale(0.5, 0.5),
		Size = U.UDim2.fromScale(o.width or 0.92, o.height or 0.8),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = color or Kit.C.White,
	}, gui)
	if stroke then
		U.new("UIStroke", { Name = "Stroke", Color = stroke, Thickness = o.strokeThickness or 4 }, label)
	end
	return label
end

--------------------------------------------------------------------------------------------
-- Claims: areas the dressing modules occupy, so Nature keeps its trees off them
--------------------------------------------------------------------------------------------

local claims: { { x: number, z: number, r: number } } = {}

function Kit.resetClaims()
	table.clear(claims)
end

function Kit.claim(x: number, z: number, r: number)
	table.insert(claims, { x = x, z = z, r = r })
end

function Kit.isClaimed(x: number, z: number, margin: number?): boolean
	local m = margin or 0
	for _, c in claims do
		local dx, dz = x - c.x, z - c.z
		local rr = c.r + m
		if dx * dx + dz * dz < rr * rr then
			return true
		end
	end
	return false
end

-- Locks a part, or every part of a model (generated dressing: not draggable in Studio).
local function lock(inst: any): any
	if inst:IsA("BasePart") then
		inst.Locked = true
	else
		for _, d in inst:GetDescendants() do
			if d:IsA("BasePart") then
				d.Locked = true
			end
		end
	end
	return inst
end

--------------------------------------------------------------------------------------------
-- Builder: blocks in a local frame (y = 0 at cf, -Z = front), Model pivot = cf
--------------------------------------------------------------------------------------------

local Builder = {}
Builder.__index = Builder

function Kit.builder(parent: any, name: string, cf: any): any
	local self = setmetatable({}, Builder)
	self.model = U.model(parent, name)
	self.cf = cf
	self.first = nil
	return self
end

-- Axis-aligned (in the local frame) block between two corners.
function Builder:box(
	name: string,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	color: any,
	extra: { [string]: any }?
): any
	local size = Vector3.new(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))
	local centre = Vector3.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	local p = lock(U.part(self.model, name, size, self.cf * CFrame.new(centre), color, nil, extra))
	self.first = self.first or p
	return p
end

-- Block with an explicit local CFrame.
function Builder:block(name: string, size: any, lcf: any, color: any, extra: { [string]: any }?): any
	local p = lock(U.part(self.model, name, size, self.cf * lcf, color, nil, extra))
	self.first = self.first or p
	return p
end

-- Upright cylinder (poles) from y0 to y1 at local (x, z).
function Builder:pole(
	name: string,
	d: number,
	x: number,
	z: number,
	y0: number,
	y1: number,
	color: any,
	extra: any?
): any
	local props: { [string]: any } = { Shape = Enum.PartType.Cylinder }
	if extra then
		for k, v in extra do
			props[k] = v
		end
	end
	local lcf = CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, rad(90))
	return self:block(name, Vector3.new(y1 - y0, d, d), lcf, color, props)
end

-- Sets PrimaryPart (default: the first part) and the pivot to the builder frame.
function Builder:finish(primary: any?): any
	local p = primary or self.first
	if p then
		self.model.PrimaryPart = p
		p.PivotOffset = p.CFrame:Inverse() * self.cf
	end
	return self.model
end

--------------------------------------------------------------------------------------------
-- Small shared structures
--------------------------------------------------------------------------------------------

--[[
	Chunky 4-part lamp (post, plate, Neon cube, cap) — the cheap sibling of Props.lampPost for
	long rows (promenade). Stands on cf; opts: height (default 8), trim (cap colour),
	post (colour), light = true.
]]
function Kit.lamp(parent: any, cf: any, opts: { [string]: any }?): any
	local o = opts or {}
	local C = Kit.C
	local h = o.height or 8
	local trim = o.trim or C.Navy
	local b = Kit.builder(parent, o.name or "Lamp", cf)
	local post = b:box("Post", -0.55, -0.4, -0.55, 0.55, h, 0.55, o.post or C.White)
	b:box("Plate", -1.3, h - 0.05, -1.3, 1.3, h + 0.45, 1.3, trim, Kit.NOSHADOW)
	local glow = b:box("Glow", -1.05, h + 0.4, -1.05, 1.05, h + 2.7, 1.05, C.Glow, Kit.NEON)
	b:box("Cap", -1.5, h + 2.65, -1.5, 1.5, h + 3.35, 1.5, trim, Kit.NOSHADOW)
	if o.light then
		Kit.light(glow, 16, 1.3)
	end
	return b:finish(post)
end

--[[
	Chunky 4-part bench (seat, back, two legs) — the cheap sibling of Props.bench (8 parts) for
	plazas and viewpoints. Stands on cf, the sitter faces -Z. opts: length (6), color (seat and
	back, default WoodLight), legs (default Wood), name.
]]
function Kit.bench(parent: any, cf: any, opts: { [string]: any }?): any
	local o = opts or {}
	local C = Kit.C
	local L = o.length or 6
	local wood = o.color or C.WoodLight
	local b = Kit.builder(parent, o.name or "Bench", cf)
	local seat = b:box("Seat", -L / 2, 1.5, -1, L / 2, 2.2, 1, wood)
	b:box("Back", -L / 2, 2.2, 0.55, L / 2, 4.3, 1.15, Kit.shade(wood, 0.9), Kit.NOSHADOW)
	for i, x in { -L / 2 + 0.4, L / 2 - 1.4 } do
		b:box(`Leg{i}`, x, -0.3, -0.8, x + 1, 1.5, 0.95, o.legs or C.Wood)
	end
	return b:finish(seat)
end

--[[
	Cheap flower meadow (5 parts): a low leafy mat with a darker leafy mound on it and three
	clumps of blooms half sunk into the leaves at different heights — a big splash of colour for
	its cost (Props.flowerPatch is 12 parts for four single flowers). Blooms poking out of
	foliage read as flowers from the side as well as from above (not as tiles on a plate).
]]
local MEADOW = { Kit.C.Red, Kit.C.Yellow, Kit.C.Pink, Kit.C.Purple, Kit.C.Orange, Kit.C.Blue, Kit.C.Blossom1 }

function Kit.flowerMeadow(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "FlowerMeadow", cf * CFrame.Angles(0, rad(90 * floor(r(0, 3.99))), 0))
	local C = Kit.C
	local w, d = r(10, 13), r(7, 9)
	local mat = b:box("Leaves", -w / 2, -0.4, -d / 2, w / 2, 0.9, d / 2, C.Leaf2, Kit.DECOR)
	local mx, mz = r(-0.12, 0.12) * w, r(-0.12, 0.12) * d
	b:box("Mound", mx - w * 0.28, 0.5, mz - d * 0.3, mx + w * 0.28, 2.0, mz + d * 0.3, C.Leaf1, Kit.DECOR)
	local first = floor(r(1, #MEADOW + 0.99))
	local spots = {
		{ mx + r(-0.8, 0.8), mz + r(-0.6, 0.6), 1.4 },
		{ -w * 0.34, -d * 0.24, 0.6 },
		{ w * 0.34, d * 0.24, 0.6 },
	}
	for i, p in spots do
		-- three different saturated colours (white cubes read as sugar lumps, not flowers)
		local colour = MEADOW[(first + i * 2 - 1) % #MEADOW + 1]
		local s = r(1.7, 2.2)
		b:box(
			`Blooms{i}`,
			p[1] - s / 2,
			p[3],
			p[2] - s / 2,
			p[1] + s / 2,
			p[3] + s * 0.95,
			p[2] + s / 2,
			colour,
			Kit.DECOR
		)
	end
	return b:finish(mat)
end

--[[
	Planted flower bed (2 + 2 per flower parts): a box with a dark soil top and a row of blooms
	(2-stud cubes) on thin green stems at staggered heights — real flowers, not coloured tiles.
	Stands on cf (front = -Z). opts: width (8), depth (3.6), count (3), height (box, 1.4), box
	(colour, default WoodLight), colors (bloom list, default C.Flowers), seed, name.
]]
function Kit.flowerBed(parent: any, cf: any, opts: { [string]: any }?): any
	local o = opts or {}
	local C = Kit.C
	local r = Kit.rng(o.seed or 1)
	local w, d = o.width or 8, o.depth or 3.6
	local n = o.count or 3
	local hb = o.height or 1.4
	local colors = o.colors or C.Flowers
	local b = Kit.builder(parent, o.name or "FlowerBed", cf)
	local box = b:box("Box", -w / 2, -0.3, -d / 2, w / 2, hb, d / 2, o.box or C.WoodLight)
	b:box("Soil", -w / 2 + 0.4, hb - 0.4, -d / 2 + 0.4, w / 2 - 0.4, hb + 0.15, d / 2 - 0.4, C.DirtDark, Kit.NOSHADOW)
	local first = floor(r(1, #colors + 0.99))
	for i = 1, n do
		local x = -w / 2 + (i - 0.5) * w / n
		local z = r(-0.3, 0.3)
		local top = hb + 1.6 + ((i + first) % 3) * 0.7
		b:box(`Stem{i}`, x - 0.3, hb, z - 0.3, x + 0.3, top - 1.2, z + 0.3, C.Leaf1, Kit.DECOR)
		local c = colors[(first + i * 2) % #colors + 1]
		b:box(`Bloom{i}`, x - 1, top - 1.8, z - 1, x + 1, top, z + 1, c, Kit.DECOR)
	end
	return b:finish(box)
end

--[[
	Sloped walkable block whose top face runs from top point a to top point b (Vector3s) — a
	boardwalk ramp (visible) or, with opts.invisible, a collider over a flight of visible steps
	(walking up smoothly instead of hopping). opts: width (6), thick (1), color, name, extra.
]]
function Kit.ramp(parent: any, a: any, b: any, opts: { [string]: any }?): any
	local o = opts or {}
	local d = b - a
	local flat = Vector3.new(d.X, 0, d.Z)
	local run = flat.Magnitude
	local len = d.Magnitude
	local thick = o.thick or 1
	local yaw = math.atan2(-flat.X, -flat.Z) -- local -Z along a -> b
	local pitch = math.atan2(d.Y, run)
	local cf = CFrame.new((a + b) / 2) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
	local extra = o.extra
	if o.invisible then
		extra = { Transparency = 1, CastShadow = false, CanQuery = false }
	end
	return lock(
		U.part(
			parent,
			o.name or "Ramp",
			Vector3.new(o.width or 6, thick, len),
			cf * CFrame.new(0, -thick / 2, 0),
			o.color or Kit.C.WoodLight,
			nil,
			extra
		)
	)
end

--[[
	Paved path with ramps that follows the voxel terraces from point a to point b (Vector3, only
	X/Z used): one slab per flat run (its top `lift` over the highest ground across the path,
	reaching down into the lowest), and on every rise a Wedge ramp (2 studs long per stud of
	rise) at the end of the lower run, its tall back face 0.1 into the higher run's slab, so the
	climb is a walk with no steps to hop. Drops get a ramp the other way. Returns the Model.
	opts: width (7), lift (0.2), color (slabs), color2 (ramps), name, top (the last run is
	raised to at least this y: a path that ends on a platform), step (sampling, 0.5).
]]
function Kit.rampPath(parent: any, world: any, a: any, b: any, opts: { [string]: any }?): any
	local o = opts or {}
	local width = o.width or 7
	local lift = o.lift or 0.2
	local step = o.step or 0.5
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local dir = flat.Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local n = floor(flat.Magnitude / step)
	local start = Vector3.new(a.X, 0, a.Z)
	-- the ground under each station: the highest and the lowest across the path
	local hi, lo = {}, {}
	for i = 1, n do
		local c = start + dir * ((i - 0.5) * step)
		local h1, h0 = -math.huge, math.huge
		for _, f in { -0.45, 0, 0.45 } do
			local p = c + side * (f * width)
			local g = world:heightAt(p.X, p.Z)
			h1, h0 = max(h1, g), min(h0, g)
		end
		hi[i], lo[i] = h1, h0
	end
	-- runs of stations at the same height
	local runs = {}
	local i = 1
	while i <= n do
		local j, l = i, lo[i]
		while j < n and hi[j + 1] == hi[i] do
			j += 1
			l = min(l, lo[j])
		end
		table.insert(runs, { s0 = (i - 1) * step, s1 = j * step, h = hi[i], lo = l })
		i = j + 1
	end
	if o.top and #runs > 0 then
		runs[#runs].h = max(runs[#runs].h, o.top - lift)
	end
	local C = Kit.C
	local c1 = o.color or C.StoneLight
	local c2 = o.color2 or Kit.shade(c1, 0.93)
	local model = U.model(parent, o.name or "Path")
	local rot = CFrame.Angles(0, math.atan2(dir.X, dir.Z), 0) -- local +Z along the path
	local function at(s: number, y: number): any
		return CFrame.new(start.X + dir.X * s, y, start.Z + dir.Z * s) * rot
	end
	-- (every slab reaches 0.12 past its run into the neighbouring runs, so no slab end lies on a
	-- terrace riser of the voxel ground: a lower slab's end is buried in the higher cell, a higher
	-- slab's overhang is under the wedge ramp; the slabs themselves never meet, being at
	-- different heights)
	for k, r in runs do
		local top, bottom = r.h + lift, r.lo - 1
		local s0 = if k > 1 then r.s0 - 0.12 else r.s0
		local s1 = if k < #runs then r.s1 + 0.12 else r.s1
		U.part(model, `Slab{k}`, Vector3.new(width, top - bottom, s1 - s0), at((s0 + s1) / 2, (top + bottom) / 2), c1)
	end
	for k = 1, #runs - 1 do
		local r, q = runs[k], runs[k + 1]
		local dh = q.h - r.h
		local up = dh > 0
		local run = if up then r.s1 - r.s0 else q.s1 - q.s0
		local L = min(2 * abs(dh), run - 0.5)
		if L > 0.5 then
			-- back face 0.1 into the higher run's slab, the slope running down onto the lower run
			local s = if up then r.s1 + 0.1 - (L + 0.1) / 2 else q.s0 - 0.1 + (L + 0.1) / 2
			local y = min(r.h, q.h) + lift + abs(dh) / 2
			local cf = at(s, y) * (if up then CFrame.new() else CFrame.Angles(0, math.pi, 0))
			U.wedge(model, `Ramp{k}`, Vector3.new(width, abs(dh), L + 0.1), cf, c2)
		end
	end
	return lock(model)
end

--[[
	Walkable stairs that follow the voxel ground from point a to point b (Vector3, only X/Z
	used): stations every `tread` studs; the stair surface never drops below the ground and
	rises at most `rise` per station (so a 4-stud terrace step becomes four 1-stud steps that
	start early enough). Blocks are only placed where the stair is above the ground; each
	block reaches down into the lowest ground under it. When the first step would still be
	more than `rise` above the ground at a, the stairs start earlier (a moves back), so there is
	never a tall first riser. Returns the Model (nil if the ground was already smooth enough).
	opts: width (8), tread (2), rise (1), color, color2 (alternating), name, lift (0.2: tops
	sit a hair above the terrace tops so no faces are coplanar), pave (also lay slabs on the
	flat stretches between the steps: a continuous visible path), top (the last step's top is
	at least this y: stairs that end on a platform built over the ground).
]]
function Kit.stairs(parent: any, world: any, a: any, b: any, opts: { [string]: any }?): any
	local o = opts or {}
	local width = o.width or 8
	local tread = o.tread or 2
	local rise = o.rise or 1
	local lift = o.lift or 0.2
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local dir = flat.Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local function groundSpan(c: any, along: { number }): (number, number)
		local hi, lo = -math.huge, math.huge
		for _, f in { -0.45, 0, 0.45 } do
			for _, g in along do
				local p = c + side * (f * width) + dir * (g * tread)
				local hh = world:heightAt(p.X, p.Z)
				hi, lo = max(hi, hh), min(lo, hh)
			end
		end
		return hi, lo
	end
	local start = Vector3.new(a.X, 0, a.Z)
	local n: number, gLo: { number }, h: { number } = 1, {}, {}
	for _ = 1, 8 do
		local length = (Vector3.new(b.X, 0, b.Z) - start).Magnitude
		n = max(1, floor(length / tread))
		local gHi = {}
		gLo = {}
		for i = 1, n do
			gHi[i], gLo[i] = groundSpan(start + dir * ((i - 0.5) * tread), { -0.4, 0.4 })
		end
		-- the stair surface: at least the highest ground, at most `rise` below the next station
		h = table.clone(gHi)
		if o.top then
			h[n] = max(h[n], o.top - lift)
		end
		for i = n - 1, 1, -1 do
			h[i] = max(h[i], h[i + 1] - rise)
		end
		-- the ground just before the first step: move the start back while that riser is too tall
		local _, before = groundSpan(start - dir * tread * 0.5, { -0.2, 0.2 })
		local excess = h[1] - before - rise
		if excess <= 1e-6 then
			break
		end
		start -= dir * (tread * math.ceil(excess / rise))
	end
	a = start
	local model = U.model(parent, o.name or "Stairs")
	local C = Kit.C
	local c1 = o.color or C.StoneLight
	local c2 = o.color2 or Kit.shade(c1, 0.93)
	local yaw = math.atan2(dir.X, dir.Z) -- local +Z along the stairs
	local count = 0
	local i = 1
	while i <= n do
		-- merge stations with the same height into one block
		local j = i
		local lo = gLo[i]
		while j < n and h[j + 1] == h[i] do
			j += 1
			lo = min(lo, gLo[j])
		end
		local needed = o.pave == true
		for k = i, j do
			if h[k] > gLo[k] then
				needed = true
			end
		end
		if needed then
			local s0, s1 = (i - 1) * tread, j * tread
			local top = h[i] + lift
			local bottom = lo - 1
			local mid = Vector3.new(a.X, (top + bottom) / 2, a.Z) + dir * ((s0 + s1) / 2)
			count += 1
			U.part(
				model,
				`Step{count}`,
				Vector3.new(width, top - bottom, s1 - s0),
				CFrame.new(mid) * CFrame.Angles(0, yaw, 0),
				if count % 2 == 1 then c1 else c2
			)
		end
		i = j + 1
	end
	if count == 0 then
		model:Destroy()
		return nil
	end
	return lock(model)
end

--------------------------------------------------------------------------------------------
-- Particle effects: no parts, so they cost nothing of the part budget; rates stay low (phones).
-- Each takes the part to emit from (its volume with opts.box, else its top face) and returns
-- the ParticleEmitter.
--------------------------------------------------------------------------------------------

local R = U.roblox
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
local SPARKLE_TEX = "rbxasset://textures/particles/sparkles_main.dds"

local function seq(a: number, b: number, mid: number?): any
	local keys = { R.NumberSequenceKeypoint.new(0, a) }
	if mid then
		table.insert(keys, R.NumberSequenceKeypoint.new(0.5, mid))
	end
	table.insert(keys, R.NumberSequenceKeypoint.new(1, b))
	return R.NumberSequence.new(keys)
end

local function emitter(part: any, name: string, props: { [string]: any }, opts: { [string]: any }?): any
	local o = opts or {}
	if o.box then
		props.Shape = Enum.ParticleEmitterShape.Box
		props.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	end
	props.Name = name
	return U.new("ParticleEmitter", props, part)
end

--[[
	Soft grey smoke rising from a campfire or chimney: a few big slow puffs that grow and fade.
	opts: rate (2.5), size (start size, 1.6), rise (speed, 3), color.
]]
function Kit.smoke(part: any, opts: { [string]: any }?): any
	local o = opts or {}
	local s = o.size or 1.6
	return emitter(part, "Smoke", {
		Texture = SMOKE_TEX,
		Rate = o.rate or 2.5,
		Lifetime = R.NumberRange.new(3, 4.5),
		Speed = R.NumberRange.new((o.rise or 3) * 0.7, o.rise or 3),
		SpreadAngle = U.Vector2.new(10, 10),
		Acceleration = Vector3.new(0.6, 0.4, 0),
		Drag = 0.4,
		Size = seq(s, s * 3.6),
		Transparency = seq(0.35, 1, 0.6),
		RotSpeed = R.NumberRange.new(-20, 20),
		Rotation = R.NumberRange.new(0, 360),
		Color = R.ColorSequence.new(o.color or U.rgb(236, 236, 240)),
		LightInfluence = 0.6,
	}, o)
end

--[[
	Magic sparkles / fireflies: small glowing specks drifting out of the part (LightEmission 1).
	opts: rate (3), size (0.5), lifetime (max, 3), speed (max, 1.5), box (spawn in the part's
	volume), drift (upward acceleration, 0.4).
]]
function Kit.sparkles(part: any, color: any, opts: { [string]: any }?): any
	local o = opts or {}
	local s = o.size or 0.5
	local life = o.lifetime or 3
	local speed = o.speed or 1.5
	return emitter(part, "Sparkles", {
		Texture = SPARKLE_TEX,
		Rate = o.rate or 3,
		Lifetime = R.NumberRange.new(life * 0.6, life),
		Speed = R.NumberRange.new(speed * 0.3, speed),
		SpreadAngle = U.Vector2.new(180, 180),
		Acceleration = Vector3.new(0, o.drift or 0.4, 0),
		Drag = 0.5,
		Size = seq(s * 0.4, 0, s),
		Transparency = seq(0.1, 1, 0.2),
		Color = R.ColorSequence.new(color),
		LightEmission = 1,
		LightInfluence = 0,
	}, o)
end

--[[
	White water: foam tumbling off a waterfall lip, spray where it lands, mist over the pool.
	The part's face `dir` (Enum.NormalId, default Bottom) is where it goes. opts: rate (10),
	size (start, 1.4), grow (end size factor, 2.2), speed {min, max} (3, 5), lifetime {min, max}
	(0.7, 1.1), gravity (downward acceleration, 24), spread (degrees, 15), color, box (spawn in
	the part's volume: along a whole lip), transparency (start, 0.15), name.
]]
function Kit.foam(part: any, dir: any?, opts: { [string]: any }?): any
	local o = opts or {}
	local s = o.size or 1.4
	local sp = o.speed or { 3, 5 }
	local life = o.lifetime or { 0.7, 1.1 }
	local spread = o.spread or 15
	return emitter(part, o.name or "Foam", {
		Texture = SMOKE_TEX,
		EmissionDirection = dir or Enum.NormalId.Bottom,
		Rate = o.rate or 10,
		Lifetime = R.NumberRange.new(life[1], life[2]),
		Speed = R.NumberRange.new(sp[1], sp[2]),
		SpreadAngle = U.Vector2.new(spread, spread),
		Acceleration = Vector3.new(0, -(o.gravity or 24), 0),
		Drag = 0.6,
		Size = seq(s, s * (o.grow or 2.2)),
		Transparency = seq(o.transparency or 0.15, 1, 0.45),
		Rotation = R.NumberRange.new(0, 360),
		RotSpeed = R.NumberRange.new(-40, 40),
		Color = R.ColorSequence.new(o.color or Kit.C.Foam),
		LightEmission = 0.15,
		LightInfluence = 0.5,
	}, o)
end

--[[
	Petals drifting on the breeze from the part (blossom trees, a flower hill). opts: rate (3),
	color (Blossom1 -> Blossom2), wind (Vector3, sideways drift), box.
]]
function Kit.petals(part: any, opts: { [string]: any }?): any
	local o = opts or {}
	return emitter(part, "Petals", {
		Texture = SPARKLE_TEX,
		Rate = o.rate or 3,
		Lifetime = R.NumberRange.new(5, 8),
		Speed = R.NumberRange.new(0.5, 2),
		SpreadAngle = U.Vector2.new(180, 180),
		Acceleration = (o.wind or Vector3.new(1.4, 0, 0.6)) + Vector3.new(0, -0.6, 0),
		Drag = 0.3,
		Size = seq(0.55, 0.35),
		Transparency = seq(0, 1, 0.1),
		Rotation = R.NumberRange.new(0, 360),
		RotSpeed = R.NumberRange.new(-90, 90),
		Color = R.ColorSequence.new(o.color or Kit.C.Blossom1, o.color2 or Kit.C.Blossom2),
		LightEmission = 0.2,
		LightInfluence = 0.8,
	}, o)
end

return Kit
