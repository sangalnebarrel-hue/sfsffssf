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
	  Kit.lamp / Kit.flowerMeadow       cheap chunky lamp (4 parts), flower bed (5 parts)

	Property presets (pass as `extra`): DECOR (tiny non-walkable details), NOSHADOW, NEON,
	NEON_DECOR.
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
	local p = U.part(self.model, name, size, self.cf * CFrame.new(centre), color, nil, extra)
	self.first = self.first or p
	return p
end

-- Block with an explicit local CFrame.
function Builder:block(name: string, size: any, lcf: any, color: any, extra: { [string]: any }?): any
	local p = U.part(self.model, name, size, self.cf * lcf, color, nil, extra)
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
	Cheap flower meadow (5 parts): a dark leafy mat with four blocks of blooms on it — a big
	splash of colour for its cost (Props.flowerPatch is 12 parts for four single flowers).
]]
function Kit.flowerMeadow(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "FlowerMeadow", cf * CFrame.Angles(0, rad(90 * floor(r(0, 3.99))), 0))
	local C = Kit.C
	local w, d = r(10, 14), r(7, 10)
	local mat = b:box("Leaves", -w / 2, -0.4, -d / 2, w / 2, 0.8, d / 2, C.Leaf1, Kit.DECOR)
	local first = floor(r(1, #C.Flowers + 0.99))
	for i = 1, 4 do
		local colour = C.Flowers[(first + (i % 2) * 2 - 1) % #C.Flowers + 1]
		local s = r(2.2, 3.2)
		local x = (if i <= 2 then -1 else 1) * w * r(0.12, 0.3)
		local z = (if i % 2 == 1 then -1 else 1) * d * r(0.1, 0.25)
		b:box(`Blooms{i}`, x - s / 2, 0.6, z - s / 2, x + s / 2, 1.5 + i * 0.12, z + s / 2, colour, Kit.DECOR)
	end
	return b:finish(mat)
end

--[[
	Walkable stairs that follow the voxel ground from point a to point b (Vector3, only X/Z
	used): stations every `tread` studs; the stair surface never drops below the ground and
	rises at most `rise` per station (so a 4-stud terrace step becomes four 1-stud steps that
	start early enough). Blocks are only placed where the stair is above the ground; each
	block reaches down into the lowest ground under it. Returns the Model (nil if the ground
	was already smooth enough).
	opts: width (8), tread (2), rise (1), color, color2 (alternating), name, lift (0.2: tops
	sit a hair above the terrace tops so no faces are coplanar).
]]
function Kit.stairs(parent: any, world: any, a: any, b: any, opts: { [string]: any }?): any
	local o = opts or {}
	local width = o.width or 8
	local tread = o.tread or 2
	local rise = o.rise or 1
	local lift = o.lift or 0.2
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local length = flat.Magnitude
	local dir = flat.Unit
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local n = max(1, floor(length / tread))
	local gHi, gLo = {}, {}
	for i = 1, n do
		local c = Vector3.new(a.X, 0, a.Z) + dir * ((i - 0.5) * tread)
		local hi, lo = -math.huge, math.huge
		for _, f in { -0.45, 0, 0.45 } do
			for _, g in { -0.4, 0.4 } do
				local p = c + side * (f * width) + dir * (g * tread)
				local h = world:heightAt(p.X, p.Z)
				hi, lo = max(hi, h), min(lo, h)
			end
		end
		gHi[i], gLo[i] = hi, lo
	end
	-- the stair surface: at least the highest ground, at most `rise` below the next station
	local h = table.clone(gHi)
	for i = n - 1, 1, -1 do
		h[i] = max(h[i], h[i + 1] - rise)
	end
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
		local needed = false
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
	return model
end

return Kit
