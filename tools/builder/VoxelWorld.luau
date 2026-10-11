--!nonstrict
--[[
	VoxelWorld — the ground of World v3 «Остров Рыбаков» as a heightfield of square voxel
	columns (CellSize × CellSize studs, tops on a 2-stud grid). See tools/builder/DESIGN.md.

	Pure Luau (no Roblox instances): Ground.luau turns it into parts, bakeWater() into Terrain
	water voxels, and the other builders query it to place things on the ground.

	  local world = VoxelWorld.new(MapConfig)   -- computes every column (deterministic)
	  world:heightAt(x, z) -> number            -- top of the column under (x, z)
	  world:kindAt(x, z) -> string              -- "grass" | "meadow" | "path" | "sand" | "shallow" |
	                                               "seabed" | "deep" | "stone" | "snow" | "grassRock"
	  world:isWater(x, z) -> boolean            -- column top below WaterTop
	  world:surfaceAt(x, z) -> (top, kind, waterTop?)
	  world:slope(x, z) -> number               -- largest height step to a neighbour column (studs)
	  world:isReserved(x, z, margin?) -> boolean -- gameplay areas: no decoration here
	  world:baseFrame(i) -> CFrame-like data { angle, x, z } and world:toBaseLocal(i, x, z) -> lx, lz
	  world.landmarks[name] / world.gateways[i] / world.islets[i] -- sites for the decorators
	  world:bakeWater(SmoothGrid) -> grid       -- Terrain water voxels (lagoon, pond, ocean)

	Layout recap (r = distance from the lagoon centre):
	  r < HubPlazaRadius         hub plaza, flat GroundTop
	  .. HubRadius               hub beach (y = 2)
	  .. LagoonRadius            lagoon bed (−2 … −LagoonDepth)
	  .. PromenadeRadius         ring beach (y = 2)
	  .. +PromenadeWidth         promenade, flat GroundTop
	  beyond                     plots (flat), gateway plazas (flat), paths, hills, landmarks,
	                             outer coast (beach or cliff), ocean, islets
]]

local VoxelWorld = {}
VoxelWorld.__index = VoxelWorld

local sqrt, abs, floor, max, min = math.sqrt, math.abs, math.floor, math.max, math.min
local sin, cos, rad, deg, atan2 = math.sin, math.cos, math.rad, math.deg, math.atan2

-- Column kinds (index order is used by Ground.luau for merging and colours).
VoxelWorld.Kinds = { "grass", "meadow", "path", "sand", "shallow", "seabed", "deep", "stone", "snow", "grassRock" }
local KIND_INDEX = {}
for i, name in VoxelWorld.Kinds do
	KIND_INDEX[name] = i
end
VoxelWorld.KindIndex = KIND_INDEX

-- Height bands on hills.
local SNOW_LINE = 92
local STONE_LINE = 64
local ROCK_LINE = 28

--------------------------------------------------------------------------------
-- Math helpers
--------------------------------------------------------------------------------

local function clamp(x: number, a: number, b: number): number
	return if x < a then a elseif x > b then b else x
end

local function lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function smoothstep(e0: number, e1: number, x: number): number
	local t = clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Signed angle difference a - b in degrees, in (-180, 180].
local function angleDiff(a: number, b: number): number
	local d = (a - b) % 360
	if d > 180 then
		d -= 360
	end
	return d
end

local function polar(angle: number, r: number): (number, number)
	local a = rad(angle)
	return r * sin(a), r * cos(a)
end

-- Rounds to the nearest multiple of step.
local function snap(v: number, step: number): number
	return floor(v / step + 0.5) * step
end

--------------------------------------------------------------------------------
-- Deterministic Perlin noise (identical on every machine)
--------------------------------------------------------------------------------

local function makePermutation(seed: number): { number }
	local p = table.create(256, 0)
	for i = 0, 255 do
		p[i + 1] = i
	end
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	for i = 256, 2, -1 do
		state = (state * 48271) % 2147483647
		local j = state % i + 1
		p[i], p[j] = p[j], p[i]
	end
	local perm = table.create(512, 0)
	for i = 1, 512 do
		perm[i] = p[(i - 1) % 256 + 1]
	end
	return perm
end

local GRAD_X = { 1, -1, 1, -1, 1, -1, 0, 0 }
local GRAD_Y = { 1, 1, -1, -1, 0, 0, 1, -1 }

local function fade(t: number): number
	return t * t * t * (t * (t * 6 - 15) + 10)
end

-- 2D Perlin noise in about [-1, 1].
function VoxelWorld:noise(x: number, y: number): number
	local perm = self.perm
	local xi, yi = floor(x), floor(y)
	local xf, yf = x - xi, y - yi
	local X, Y = xi % 256, yi % 256
	local aa = perm[perm[X + 1] + Y + 1] % 8 + 1
	local ab = perm[perm[X + 1] + Y + 2] % 8 + 1
	local ba = perm[perm[X + 2] + Y + 1] % 8 + 1
	local bb = perm[perm[X + 2] + Y + 2] % 8 + 1
	local u, v = fade(xf), fade(yf)
	local n00 = GRAD_X[aa] * xf + GRAD_Y[aa] * yf
	local n10 = GRAD_X[ba] * (xf - 1) + GRAD_Y[ba] * yf
	local n01 = GRAD_X[ab] * xf + GRAD_Y[ab] * (yf - 1)
	local n11 = GRAD_X[bb] * (xf - 1) + GRAD_Y[bb] * (yf - 1)
	return lerp(lerp(n00, n10, u), lerp(n01, n11, u), v)
end

-- Fractal noise, about [-1, 1].
function VoxelWorld:fbm(x: number, y: number, octaves: number): number
	local total, amplitude, frequency, norm = 0, 1, 1, 0
	for _ = 1, octaves do
		total += self:noise(x * frequency, y * frequency) * amplitude
		norm += amplitude
		amplitude *= 0.5
		frequency *= 2.03
	end
	return total / norm
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

local DEFAULTS = {
	WaterTop = 0,
	GroundTop = 4,
	CellSize = 8,
	HubRadius = 150,
	HubPlazaRadius = 124,
	LagoonRadius = 296,
	LagoonDepth = 14,
	BeachWidth = 12,
	PromenadeRadius = 312,
	PromenadeWidth = 18,
	BaseCount = 8,
	BaseAngleOffset = 22.5,
	BaseRadius = 312,
	PlotFront = 18,
	PlotDepth = 150,
	PlotHalfWidth = 68,
	PlotMargin = 8,
	PierLength = 92,
	PierHalfWidth = 22,
	BridgeAngles = { 0, 90, 180, 270 },
	BridgeWidth = 18,
	GatewayRadius = 40,
	GatewayDistance = 372,
	RingOuterRadius = 640,
	HillHeight = 44,
	PathWidth = 12,
	Landmarks = {},
	OceanHalf = 1400,
	OceanDepth = 24,
	BoundaryRadius = 780,
	Islets = {},
}

function VoxelWorld.new(cfg: any, seed: number?)
	local self = setmetatable({}, VoxelWorld)
	local c = {}
	for key, value in DEFAULTS do
		c[key] = if cfg[key] ~= nil then cfg[key] else value
	end
	self.cfg = c
	self.perm = makePermutation(seed or 20261012)
	self.cell = c.CellSize
	self.n = math.ceil(c.OceanHalf / c.CellSize) -- columns ix, iz in [-n, n-1]
	self.size = 2 * self.n

	-- Bases: angle and slot position (slot = lagoon-side edge of the promenade).
	self.bases = {}
	for i = 1, c.BaseCount do
		local angle = c.BaseAngleOffset + (i - 1) * 360 / c.BaseCount
		local x, z = polar(angle, c.BaseRadius)
		self.bases[i] = { index = i, angle = angle, x = x, z = z }
	end

	-- Gateway plazas behind each bridge landing.
	self.gateways = {}
	for i, angle in c.BridgeAngles do
		local x, z = polar(angle, c.GatewayDistance)
		self.gateways[i] = { index = i, angle = angle, x = x, z = z, radius = c.GatewayRadius }
	end

	self:setupLandmarks()
	self:setupIslets()
	self:build()
	return self
end

-- Coordinates of (x, z) in a frame at `angle` (radial axis) anchored at radius `radius`:
-- lz grows outwards (away from the lagoon), lx sideways (to the right when facing the lagoon).
local function radialLocal(x: number, z: number, angle: number, radius: number): (number, number)
	local a = rad(angle)
	local ux, uz = sin(a), cos(a)
	local dx, dz = x - radius * ux, z - radius * uz
	local lz = dx * ux + dz * uz
	local lx = dx * uz - dz * ux
	return lx, lz
end
VoxelWorld.radialLocal = radialLocal

function VoxelWorld:toBaseLocal(i: number, x: number, z: number): (number, number)
	local b = self.bases[i]
	return radialLocal(x, z, b.angle, self.cfg.BaseRadius)
end

function VoxelWorld:setupLandmarks()
	local c = self.cfg
	self.landmarks = {}
	for _, def in c.Landmarks do
		local site = { name = def.Name, angle = def.Angle, radius = def.Radius }
		if def.Name == "Waterfall" then
			-- Cliff plateau from r = Radius outwards, pond at its foot.
			site.cliffTop = 44
			site.halfWidth = 56
			site.depth = 150
			site.pondR = def.Radius - 38
			site.pondRadius = 30
			site.pondBed = -6
		elseif def.Name == "Windmill" then
			site.hillRadius = 84
			site.topRadius = 18
			site.top = 36
		elseif def.Name == "GiantTree" then
			site.plateauRadius = 46
			site.top = 8
		elseif def.Name == "Peak" then
			site.mountainRadius = 150
			site.top = 116
		end
		site.x, site.z = polar(def.Angle, def.Radius)
		if site.pondR then
			site.pondX, site.pondZ = polar(def.Angle, site.pondR)
		end
		self.landmarks[def.Name] = site
	end
end

function VoxelWorld:setupIslets()
	self.islets = {}
	for i, def in self.cfg.Islets do
		local x, z = polar(def.Angle, def.Radius)
		self.islets[i] = { index = i, angle = def.Angle, x = x, z = z, size = def.Size, height = def.Height }
	end
end

--------------------------------------------------------------------------------
-- Zones
--------------------------------------------------------------------------------

-- Mean outer coastline radius at angle θ, wobbling.
function VoxelWorld:coastRadius(theta: number): number
	local t = rad(theta)
	return self.cfg.RingOuterRadius
		+ 26 * sin(3 * t + 1.3)
		+ 14 * sin(7 * t + 0.4)
		+ 10 * self:noise(cos(t) * 3 + 11, sin(t) * 3 - 7)
end

-- 0..1: how much of the outer coast at θ is a cliff (no beach).
function VoxelWorld:cliffiness(theta: number): number
	local t = rad(theta)
	return smoothstep(0.05, 0.35, self:noise(cos(t) * 2.2 + 40, sin(t) * 2.2 + 40))
end

-- Distance (studs) from (x, z) to the plot rectangle of base i incl. margin; 0 inside.
function VoxelWorld:plotDistance(i: number, x: number, z: number): number
	local c = self.cfg
	local lx, lz = self:toBaseLocal(i, x, z)
	local half = c.PlotHalfWidth + c.PlotMargin
	local front = c.PlotFront - c.PlotMargin
	local back = c.PlotFront + c.PlotDepth + c.PlotMargin
	local dx = max(abs(lx) - half, 0)
	local dz = max(front - lz, lz - back, 0)
	return sqrt(dx * dx + dz * dz)
end

-- Radial path strips from the promenade to the landmarks: returns distance to the strip.
function VoxelWorld:pathDistance(x: number, z: number): number
	local c = self.cfg
	local best = math.huge
	for _, site in self.landmarks do
		local reach = if site.name == "Waterfall"
			then site.pondR - site.pondRadius
			elseif site.name == "Windmill" then site.radius - site.hillRadius + 4
			elseif site.name == "GiantTree" then site.radius - site.plateauRadius + 4
			else site.radius - site.mountainRadius + 12
		local lx, lz = radialLocal(x, z, site.angle, c.PromenadeRadius + c.PromenadeWidth)
		local along = clamp(lz, 0, reach - (c.PromenadeRadius + c.PromenadeWidth))
		local d = sqrt(lx * lx + (lz - along) ^ 2) - c.PathWidth / 2
		best = min(best, d)
	end
	return best
end

-- Distance to the nearest flat gameplay zone (promenade, plots, gateways, paths, pond yard).
function VoxelWorld:flatDistance(x: number, z: number, r: number): number
	local c = self.cfg
	local best = max(r - (c.PromenadeRadius + c.PromenadeWidth), 0)
	for i = 1, c.BaseCount do
		best = min(best, self:plotDistance(i, x, z))
	end
	for _, g in self.gateways do
		best = min(best, max(sqrt((x - g.x) ^ 2 + (z - g.z) ^ 2) - g.radius, 0))
	end
	best = min(best, max(self:pathDistance(x, z), 0))
	local fall = self.landmarks.Waterfall
	if fall then
		local lx, lz = radialLocal(x, z, fall.angle, fall.pondR)
		-- the yard around the pond, up to the cliff face
		local dx = max(abs(lx) - (fall.pondRadius + 14), 0)
		local dz = max(-(fall.pondRadius + 10) - lz, lz - (fall.radius - fall.pondR), 0)
		best = min(best, sqrt(dx * dx + dz * dz))
	end
	return best
end

--------------------------------------------------------------------------------
-- Height of one column
--------------------------------------------------------------------------------

-- Natural hill height (above GroundTop) on the ring land, before landmarks.
function VoxelWorld:hillHeight(x: number, z: number, r: number, theta: number, flat: number): number
	local c = self.cfg
	local coastR = self:coastRadius(theta)
	local cliff = self:cliffiness(theta)
	local rise = smoothstep(c.PromenadeRadius + c.PromenadeWidth, 470, r)
	-- Gentle slope down to a beach, or a steep fall into the sea where the coast is a cliff.
	local fallStart = lerp(coastR - 110, coastR - 26, cliff)
	local fallEnd = lerp(coastR - 18, coastR - 2, cliff)
	local fall = 1 - smoothstep(fallStart, fallEnd, r)
	local n = self:fbm(x / 210, z / 210, 2) * 0.5 + 0.5
	local ridge = 1 - abs(self:noise(x / 170 + 31, z / 170 - 17))
	local h = c.HillHeight * rise * fall * (0.3 + 0.7 * (0.6 * n + 0.4 * ridge))
	-- Keep gameplay areas flat and let hills grow away from them.
	return h * smoothstep(0, 40, flat)
end

-- Landmark terrain shapes; returns (height above GroundTop or nil, kind or nil, isPond).
function VoxelWorld:landmarkShape(x: number, z: number, flat: number, mflat: number): (number?, string?, boolean)
	-- big shapes use the coarse 16-stud grid (see column())
	local macro = 2 * self.cfg.CellSize
	local mx, mz = (floor(x / macro) + 0.5) * macro, (floor(z / macro) + 0.5) * macro
	local best: number? = nil
	local bestKind: string? = nil
	for _, site in self.landmarks do
		if site.name == "Waterfall" then
			local lx, lz = radialLocal(x, z, site.angle, site.radius)
			-- Plateau: lz in [0, depth], |lx| <= halfWidth with rounded back corners.
			if lz >= 0 and lz <= site.depth then
				local w = site.halfWidth - max(lz - site.depth + 40, 0) * 0.9
				if abs(lx) <= w then
					-- a chunky mesa: flat top, one terrace ledge along the sides and back
					local ledge = abs(lx) > w - 14 or lz > site.depth - 14
					local h = site.cliffTop - 4 - (if ledge then 12 else 0)
					if not best or h > best then
						best, bestKind = h, nil
					end
				end
			end
			local px, pz = x - site.pondX, z - site.pondZ
			local d = sqrt(px * px + pz * pz)
			if d < site.pondRadius then
				return site.pondBed - 4, "shallow", true -- pond bed (relative to GroundTop)
			elseif d < site.pondRadius + 8 then
				return -2, "sand", false -- sand rim (y = 2)
			end
		elseif site.name == "Windmill" then
			-- a ziggurat on the fine grid, gentle enough (<= 4 studs per column) to climb by jumping
			local d = sqrt((x - site.x) ^ 2 + (z - site.z) ^ 2)
			if d < site.hillRadius then
				local t = clamp((site.hillRadius - d) / (site.hillRadius - site.topRadius), 0, 1)
				return (site.top - 4) * t, if t >= 1 then "meadow" else nil, false
			end
		elseif site.name == "GiantTree" then
			local d = sqrt((x - site.x) ^ 2 + (z - site.z) ^ 2)
			if d < site.plateauRadius then
				return site.top - 4, "meadow", false
			end
		elseif site.name == "Peak" then
			local d = sqrt((mx - site.x) ^ 2 + (mz - site.z) ^ 2)
			if d < site.mountainRadius then
				local t = 1 - d / site.mountainRadius
				local shape = t ^ 1.35 + 0.08 * self:noise(mx / 40 + 5, mz / 40 + 9) * t
				-- the mountain foot never spills into plots or paths
				local h = (site.top - 4) * clamp(shape, 0, 1) * smoothstep(0, 30, mflat)
				if not best or h > best then
					best, bestKind = h, nil
				end
			end
		end
	end
	return best, bestKind, false
end

-- Windmill hill and giant tree plateau replace the natural hills (clean shapes).
function VoxelWorld:overridesHills(x: number, z: number): boolean
	local mill, tree = self.landmarks.Windmill, self.landmarks.GiantTree
	if mill and sqrt((x - mill.x) ^ 2 + (z - mill.z) ^ 2) < mill.hillRadius then
		return true
	end
	return tree ~= nil and sqrt((x - tree.x) ^ 2 + (z - tree.z) ^ 2) < tree.plateauRadius
end

-- Islet height (absolute) or nil: chunky stepped islands with a rounded-square outline
-- (few big rectangles = few parts), sand rim, 8-stud terraces.
function VoxelWorld:isletHeight(x: number, z: number): (number?, string?)
	for _, isle in self.islets do
		local dx, dz = abs(x - isle.x), abs(z - isle.z)
		-- L4 norm: a rounded square
		local d = (dx ^ 4 + dz ^ 4) ^ 0.25
		local radius = isle.size
		if d < radius then
			if d > radius - 16 then
				return 2, "sand"
			end
			local t = clamp((radius - 16 - d) / max(radius * 0.55, 1), 0, 1)
			return 4 + snap(isle.height * t, 8), nil
		elseif d < radius + 24 then
			return -4, "shallow"
		end
	end
	return nil, nil
end

-- Kind for a land column by its height (hills, islets).
local function landKind(top: number): string
	if top >= SNOW_LINE then
		return "snow"
	elseif top >= STONE_LINE then
		return "stone"
	elseif top >= ROCK_LINE then
		return "grassRock"
	end
	return "grass"
end

--[[
	Top (absolute y, multiple of 2) and kind of the column whose centre is (x, z).
]]
function VoxelWorld:column(x: number, z: number): (number, string)
	local c = self.cfg
	local G = c.GroundTop
	local r = sqrt(x * x + z * z)

	-- Hub island and lagoon.
	if r < c.HubPlazaRadius then
		return G, "grass"
	elseif r < c.HubRadius then
		return 2, "sand"
	elseif r < c.LagoonRadius then
		-- three depth bands: shallow sand at both shores, then a sandy slope, then the deep middle
		local d = min(r - c.HubRadius, c.LagoonRadius - r)
		if d < 10 then
			return -2, "shallow"
		elseif d < 28 then
			return -6, "seabed"
		end
		return -c.LagoonDepth, "deep"
	elseif r < c.PromenadeRadius - 5 then
		return 2, "sand" -- (cells reaching under the promenade deck are already GroundTop)
	end

	-- Hills, coast and sea are sampled on a coarser 16-stud grid: chunkier voxel steps and
	-- far fewer parts. Gameplay zones (flat) keep the fine grid.
	local macro = 2 * c.CellSize
	local mx, mz = (floor(x / macro) + 0.5) * macro, (floor(z / macro) + 0.5) * macro
	local mr = sqrt(mx * mx + mz * mz)
	local theta = deg(atan2(mx, mz)) % 360
	local coastR = self:coastRadius(theta)
	local cliff = self:cliffiness(theta)
	local beach = if cliff > 0.5 then 0 else 16

	-- Landmarks (the peak may run out into the sea, so check before the coast).
	local flat = if r < coastR + 200 then self:flatDistance(x, z, r) else math.huge
	local mflat = if r < coastR + 200 then self:flatDistance(mx, mz, mr) else math.huge
	local lh, lkind, pond = self:landmarkShape(x, z, flat, mflat)
	if pond then
		return G + snap(lh :: number, 2), lkind :: string
	end
	if lkind == "sand" then
		return 2, "sand" -- pond rim
	end

	if mr < coastR then
		if flat <= 0 then
			-- gameplay ground: always flat; paths are light dirt, the rest grass
			return G, if self:pathDistance(x, z) <= 0 then "path" else "grass"
		end
		local h = self:hillHeight(mx, mz, mr, theta, mflat)
		if lh and (lh > h or lkind == "meadow" or self:overridesHills(x, z)) then
			h = lh
		end
		local top = G + snap(h, 4)
		return top, lkind or landKind(top)
	end

	-- Peak running into the sea.
	if lh and lh > 2 then
		local top = G + snap(lh, 4)
		return top, lkind or landKind(top)
	end

	-- Outer beach, then the sea floor stepping down to the ocean depth.
	if mr < coastR + beach then
		return 2, "sand"
	end
	local isleTop, isleKind = self:isletHeight(mx, mz)
	local off = mr - coastR - beach
	local bed = if off < 16 then -2 elseif off < 48 then -8 elseif off < 96 then -16 else -c.OceanDepth
	if isleTop and isleTop > bed then
		if isleTop >= 4 then
			local top = snap(isleTop, 4)
			return top, isleKind or landKind(top)
		end
		return snap(isleTop, 2), isleKind or "shallow"
	end
	return bed, if bed > -6 then "shallow" elseif bed > -c.OceanDepth then "seabed" else "deep"
end

--------------------------------------------------------------------------------
-- Grid
--------------------------------------------------------------------------------

function VoxelWorld:index(ix: number, iz: number): number
	return (iz + self.n) * self.size + (ix + self.n)
end

function VoxelWorld:build()
	local n, size, cell = self.n, self.size, self.cell
	local count = size * size
	self.top = buffer.create(count * 2) -- i16 tops
	self.kind = buffer.create(count) -- u8 kind index
	for iz = -n, n - 1 do
		for ix = -n, n - 1 do
			local x, z = (ix + 0.5) * cell, (iz + 0.5) * cell
			local top, kind = self:column(x, z)
			local i = self:index(ix, iz)
			buffer.writei16(self.top, i * 2, top)
			buffer.writeu8(self.kind, i, KIND_INDEX[kind])
		end
	end
end

function VoxelWorld:cellOf(x: number, z: number): (number, number)
	local n = self.n
	return clamp(floor(x / self.cell), -n, n - 1), clamp(floor(z / self.cell), -n, n - 1)
end

function VoxelWorld:topAtCell(ix: number, iz: number): number
	local n = self.n
	ix, iz = clamp(ix, -n, n - 1), clamp(iz, -n, n - 1)
	return buffer.readi16(self.top, self:index(ix, iz) * 2)
end

function VoxelWorld:kindAtCell(ix: number, iz: number): string
	local n = self.n
	ix, iz = clamp(ix, -n, n - 1), clamp(iz, -n, n - 1)
	return VoxelWorld.Kinds[buffer.readu8(self.kind, self:index(ix, iz))]
end

function VoxelWorld:heightAt(x: number, z: number): number
	return self:topAtCell(self:cellOf(x, z))
end

function VoxelWorld:kindAt(x: number, z: number): string
	return self:kindAtCell(self:cellOf(x, z))
end

function VoxelWorld:isWater(x: number, z: number): boolean
	return self:heightAt(x, z) < self.cfg.WaterTop
end

function VoxelWorld:surfaceAt(x: number, z: number): (number, string, number?)
	local ix, iz = self:cellOf(x, z)
	local top = self:topAtCell(ix, iz)
	local water = if top < self.cfg.WaterTop then self.cfg.WaterTop else nil
	return top, self:kindAtCell(ix, iz), water
end

-- Largest absolute height step from the column under (x, z) to its 4 neighbours.
function VoxelWorld:slope(x: number, z: number): number
	local ix, iz = self:cellOf(x, z)
	local h = self:topAtCell(ix, iz)
	local s = 0
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		s = max(s, abs(self:topAtCell(ix + d[1], iz + d[2]) - h))
	end
	return s
end

-- True if (x, z) is in (or within margin of) a gameplay area or landmark site.
function VoxelWorld:isReserved(x: number, z: number, margin: number?): boolean
	local c = self.cfg
	local m = margin or 0
	local r = sqrt(x * x + z * z)
	if r < c.PromenadeRadius + c.PromenadeWidth + m then
		return true -- hub, lagoon, beaches, promenade
	end
	for i = 1, c.BaseCount do
		if self:plotDistance(i, x, z) < c.PlotMargin + m then
			return true
		end
	end
	for _, g in self.gateways do
		if sqrt((x - g.x) ^ 2 + (z - g.z) ^ 2) < g.radius + m then
			return true
		end
	end
	if self:pathDistance(x, z) < m + 2 then
		return true
	end
	for _, site in self.landmarks do
		local siteRadius = if site.name == "Waterfall"
			then nil
			elseif site.name == "Windmill" then site.topRadius + 4
			elseif site.name == "GiantTree" then site.plateauRadius
			else nil
		if siteRadius and sqrt((x - site.x) ^ 2 + (z - site.z) ^ 2) < siteRadius + m then
			return true
		end
		if site.name == "Waterfall" then
			local d = sqrt((x - site.pondX) ^ 2 + (z - site.pondZ) ^ 2)
			if d < site.pondRadius + 14 + m then
				return true
			end
		end
	end
	return false
end

-- Lowest and highest column tops.
function VoxelWorld:heightRange(): (number, number)
	local lo, hi = math.huge, -math.huge
	for i = 0, self.size * self.size - 1 do
		local t = buffer.readi16(self.top, i * 2)
		lo, hi = min(lo, t), max(hi, t)
	end
	return lo, hi
end

--------------------------------------------------------------------------------
-- Terrain water
--------------------------------------------------------------------------------

--[[
	Fills Terrain water voxels (4-stud voxels) above every column whose top is below WaterTop,
	up to WaterTop. Returns the SmoothGrid instance (tools/terrain/SmoothGrid.luau).
]]
function VoxelWorld:bakeWater(SmoothGrid: any): any
	local grid = SmoothGrid.new()
	local water = SmoothGrid.Slots.Water
	local n, cell = self.n, self.cell
	local per = cell // 4 -- voxel columns per cell side
	local surface = self.cfg.WaterTop // 4 -- first voxel layer above the water
	for iz = -n, n - 1 do
		for ix = -n, n - 1 do
			local top = self:topAtCell(ix, iz)
			if top < self.cfg.WaterTop then
				local fromY = floor(top / 4)
				for vy = fromY, surface - 1 do
					for dz = 0, per - 1 do
						for dx = 0, per - 1 do
							grid:set(ix * per + dx, vy, iz * per + dz, water, 1)
						end
					end
				end
			end
		end
	end
	return grid
end

return VoxelWorld
