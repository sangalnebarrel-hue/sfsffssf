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
VoxelWorld.Kinds =
	{ "grass", "meadow", "path", "sand", "shallow", "seabed", "deep", "stone", "snow", "grassRock", "mesa" }
local KIND_INDEX = {}
for i, name in VoxelWorld.Kinds do
	KIND_INDEX[name] = i
end
VoxelWorld.KindIndex = KIND_INDEX

-- Height bands on hills.
-- Largest step between neighbouring dry columns after relaxation (one jump).
local MAX_STEP = 4

local SNOW_LINE = 104
local STONE_LINE = 84
local ROCK_LINE = 72

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
	HubRadius = 185,
	HubPlazaRadius = 158,
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
	RingOuterRadius = 600,
	HillHeight = 60,
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
			site.cliffTop = 56
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
		elseif string.sub(def.Name, 1, 4) == "Peak" then
			-- snowy mountains on the outer ring; only the main "Peak" gets a path to its foot
			site.peak = true
			site.mountainRadius = def.Size or 150
			site.top = def.Height or 116
			site.path = def.Name == "Peak"
		end
		site.x, site.z = polar(def.Angle, def.Radius)
		if site.peak and site.path then
			self:setupTrail(site)
		end
		if site.pondR then
			site.pondX, site.pondZ = polar(def.Angle, site.pondR)
		end
		self.landmarks[def.Name] = site
	end
end

--[[
	The main peak's trail: a spiral ledge carved into the mountain from its lagoon-facing foot up
	to a flat summit, climbing TRAIL_SLOPE per stud, so it is all 4-stud steps (one jump each).
	site.trail = { {x, z, h}, ... } (h above GroundTop, every ~2 studs); site.summitRadius,
	site.summitTop (absolute y of the flat summit).
]]
local TRAIL_SLOPE = 0.42
local TRAIL_HALF_WIDTH = 9 -- at least two columns wide, so diagonal bends stay connected
function VoxelWorld:setupTrail(site: any)
	local R, H = site.mountainRadius, site.top - self.cfg.GroundTop
	local theta0 = atan2(-site.x, -site.z) -- start on the side facing the lagoon
	local trail = {}
	local d, psi, sinceLast = R - 2, 0, 99
	local step = 0.004
	while d > 20 do
		local t = 1 - d / R
		local slopeOut = H * 1.35 * t ^ 0.35 / R -- |dh/dd| of the mountain profile
		local dd = TRAIL_SLOPE * d / slopeOut * step
		d -= dd
		psi += step
		sinceLast += sqrt((d * step) ^ 2 + dd * dd)
		if sinceLast >= 2 then
			sinceLast = 0
			local h = H * (1 - d / R) ^ 1.35
			table.insert(trail, { site.x + d * sin(theta0 + psi), site.z + d * cos(theta0 + psi), h })
		end
	end
	site.trail = trail
	site.summitRadius = 22
	site.summitTop = self.cfg.GroundTop + snap(trail[#trail][3], 4)
end

-- Height (above GroundTop) of the trail ledge at (x, z), or nil when (x, z) is off the trail.
function VoxelWorld:trailHeight(site: any, x: number, z: number): number?
	local best, bestH = TRAIL_HALF_WIDTH * TRAIL_HALF_WIDTH, nil
	for _, p in site.trail do
		local dx, dz = x - p[1], z - p[2]
		local d2 = dx * dx + dz * dz
		if d2 < best then
			best, bestH = d2, p[3]
		end
	end
	return bestH
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
		if site.peak and not site.path then
			continue
		end
		local reach = if site.name == "Waterfall"
			then site.pondR - site.pondRadius
			elseif site.name == "Windmill" then site.radius - site.hillRadius - 4 -- the hill's own steps take over
			elseif site.name == "GiantTree" then site.radius - site.plateauRadius - 6 -- the stair props take over
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
	-- The windmill hill and the giant tree meadow stay the local high points: the natural hills
	-- step down towards them instead of walling them in.
	local mill, tree = self.landmarks.Windmill, self.landmarks.GiantTree
	if mill then
		local d = sqrt((x - mill.x) ^ 2 + (z - mill.z) ^ 2)
		h *= 0.35 + 0.65 * smoothstep(mill.hillRadius + 8, mill.hillRadius + 110, d)
	end
	if tree then
		local d = sqrt((x - tree.x) ^ 2 + (z - tree.z) ^ 2)
		h *= smoothstep(tree.plateauRadius + 8, tree.plateauRadius + 110, d)
	end
	-- Keep gameplay areas flat and let hills grow away from them.
	return h * smoothstep(0, 90, flat)
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
		elseif site.peak then
			if site.trail then
				-- flat summit and the carved spiral trail (fine grid)
				local fd = sqrt((x - site.x) ^ 2 + (z - site.z) ^ 2)
				if fd < site.summitRadius then
					return site.summitTop - self.cfg.GroundTop, "snow", false
				end
				local th = if fd < site.mountainRadius then self:trailHeight(site, x, z) else nil
				if th then
					return snap(th, 4), "path", false
				end
			end
			local d = sqrt((mx - site.x) ^ 2 + (mz - site.z) ^ 2)
			if d < site.mountainRadius then
				local t = 1 - d / site.mountainRadius
				local shape = t ^ 1.35 + 0.08 * self:noise(mx / 40 + 5, mz / 40 + 9) * t
				-- the mountain foot never spills into plots or paths
				local h = (site.top - 4) * clamp(shape, 0, 1) * smoothstep(0, 30, mflat)
				if site.summitTop then
					-- nothing outside the flat summit may rise above it
					h = min(h, site.summitTop - self.cfg.GroundTop - 4)
				end
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

-- Kind of a mountain column: grass foot, stone flanks above y 24 (grey strata, not dirt), bare
-- rock and then snow towards the top; the snow line follows each peak's own height.
function VoxelWorld:peakKind(x: number, z: number, top: number): string
	local site, best = nil, math.huge
	for _, s in self.landmarks do
		if s.peak then
			local d = (x - s.x) ^ 2 + (z - s.z) ^ 2
			if d < best then
				site, best = s, d
			end
		end
	end
	local peakTop = if site then (site.summitTop or site.top) else 116
	local snowLine = max(peakTop - 36, 80)
	if top >= snowLine then
		return "snow"
	elseif top >= snowLine - 20 then
		return "stone"
	elseif top > 24 then
		return "grassRock"
	end
	return "grass"
end

-- Inside the waterfall mesa footprint?
function VoxelWorld:onMesa(x: number, z: number): boolean
	local fall = self.landmarks.Waterfall
	if not fall then
		return false
	end
	local lx, lz = radialLocal(x, z, fall.angle, fall.radius)
	return lz >= 0 and lz <= fall.depth and abs(lx) <= fall.halfWidth
end

-- Islet height (absolute) or nil: a rounded-square island (few big rectangles = few parts)
-- with a wide sand rim, a broad grassy shelf and, on the bigger ones, one raised plateau.
function VoxelWorld:isletHeight(x: number, z: number): (number?, string?)
	for _, isle in self.islets do
		local dx, dz = abs(x - isle.x), abs(z - isle.z)
		-- L4 norm: a rounded square
		local d = (dx ^ 4 + dz ^ 4) ^ 0.25
		local radius = isle.size
		if d < radius then
			if d > radius - 28 then
				return 2, "sand"
			end
			local inner = radius - 28
			if d < inner * 0.55 and isle.height > 12 then
				return 4 + snap(isle.height, 8), nil -- the plateau
			elseif d < inner * 0.8 and isle.height > 28 then
				return 4 + snap(isle.height * 0.5, 8), nil -- a terrace below it
			end
			return 4, nil -- grassy shelf above the beach
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
	Top (absolute y, multiple of 2) and kind of the column whose centre is (x, z), plus `locked`
	for columns the slope relaxation in build() must keep (mesa cliffs, mountains).
]]
function VoxelWorld:column(x: number, z: number): (number, string, boolean?, boolean?)
	local c = self.cfg
	local G = c.GroundTop
	local r = sqrt(x * x + z * z)

	-- Hub island and lagoon.
	if r < c.HubPlazaRadius then
		return G, "grass"
	elseif r < c.HubRadius then
		return 2, "sand"
	elseif r < c.LagoonRadius then
		-- three depth bands (on the 16-stud grid: fewer parts): shallow sand at both shores,
		-- then a sandy slope, then the deep middle
		local m = 2 * c.CellSize
		local lx, lz = (floor(x / m) + 0.5) * m, (floor(z / m) + 0.5) * m
		local lr = sqrt(lx * lx + lz * lz)
		local d = min(lr - c.HubRadius, c.LagoonRadius - lr)
		if d < 12 then
			return -2, "shallow"
		elseif d < 30 then
			return -6, "seabed"
		end
		return -c.LagoonDepth, "deep"
	elseif r < c.PromenadeRadius + 2 then
		-- the beach runs under the promenade's lagoon edge (its sea wall hides the step)
		return 2, "sand"
	end

	-- Hills, coast and sea are sampled on a coarser 16-stud grid: chunkier voxel steps and
	-- far fewer parts. Gameplay zones (flat) keep the fine grid.
	local macro = 2 * c.CellSize
	local mx, mz = (floor(x / macro) + 0.5) * macro, (floor(z / macro) + 0.5) * macro
	local mr = sqrt(mx * mx + mz * mz)
	local theta = deg(atan2(mx, mz)) % 360
	local coastR = self:coastRadius(theta)
	local cliff = self:cliffiness(theta)
	local beach = if cliff > 0.5 then 0 else 28 -- two 16-stud sand cells on open coasts

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
		local locked = false
		local shaped = false -- height comes from a landmark shape, not the natural hills
		local forced = lkind == "meadow" or lkind == "path" or lkind == "snow" -- landmark ground wins
		if lh and (lh > h or forced or self:overridesHills(x, z)) then
			shaped = true
			-- mesa and mountains keep their cliffs; the windmill/tree shapes are gentle anyway
			locked = lkind ~= "meadow" and not self:overridesHills(x, z)
			h = lh
		end
		-- Sea cliffs: where the coast is rocky, its last 24 studs stand at least 12 above the water
		-- as warm sandstone (instead of a lawn running into the sea).
		if cliff > 0.5 and not shaped and coastR - mr < 24 then
			h = max(h, 12)
			shaped, locked, lkind = true, true, "mesa"
		end
		local top = G + snap(h, 4)
		local kind = lkind or landKind(top)
		if locked and self:onMesa(x, z) and (kind == "grassRock" or kind == "grass") then
			kind = "mesa" -- grass cap on warm sandstone cliffs
		elseif locked and kind ~= "mesa" and kind ~= "path" and kind ~= "meadow" then
			kind = self:peakKind(x, z, top) -- mountains: stone sides, snow caps
		end
		-- natural hills (sampled on the 16-stud grid) are relaxed block-wise in build()
		return top, kind, locked, not shaped
	end

	-- Peak running into the sea.
	if lh and lh > 2 then
		local top = G + snap(lh, 4)
		return top, lkind or landKind(top), true
	end

	-- Outer beach (an upper dune row at y 3, then y 2: 1-stud steps, no jumps), then the sea
	-- floor stepping down to the ocean depth.
	if mr < coastR + beach then
		return if mr < coastR + 12 then 3 else 2, "sand"
	end
	-- the open sea is sampled on a 32-stud grid (nobody sees its floor in detail)
	local big = 4 * c.CellSize
	local bx, bz = (floor(x / big) + 0.5) * big, (floor(z / big) + 0.5) * big
	local br = sqrt(bx * bx + bz * bz)
	local isleTop, isleKind = self:isletHeight(if br > 1000 then bx else mx, if br > 1000 then bz else mz)
	local off = br - self:coastRadius(deg(atan2(bx, bz)) % 360) - beach
	local bed = if off < 20 then -2 elseif off < 60 then -8 elseif off < 120 then -16 else -c.OceanDepth
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
	local locked = buffer.create(count)
	local hill = buffer.create(count)
	for iz = -n, n - 1 do
		for ix = -n, n - 1 do
			local x, z = (ix + 0.5) * cell, (iz + 0.5) * cell
			local top, kind, lock, isHill = self:column(x, z)
			local i = self:index(ix, iz)
			buffer.writei16(self.top, i * 2, top)
			buffer.writeu8(self.kind, i, KIND_INDEX[kind])
			buffer.writeu8(locked, i, if lock then 1 else 0)
			buffer.writeu8(hill, i, if isHill and top >= 2 then 1 else 0)
		end
	end
	self:relaxBlocks(hill)
	self:relaxSlopes(locked)
	self:fillPits()
end

--[[
	Pit filling: a dry column sunk 4+ studs below at least 6 of its 8 neighbours (left over where
	landmark shapes, paths and relaxed hills meet) is raised to the lowest of those neighbours.
]]
function VoxelWorld:fillPits()
	local size = self.size
	local tops, kinds = self.top, self.kind
	for _ = 1, 4 do
		local changed = false
		for iz = 1, size - 2 do
			for ix = 1, size - 2 do
				local i = iz * size + ix
				local h = buffer.readi16(tops, i * 2)
				if h >= 2 then
					local higher, lowest = 0, math.huge
					for dz = -1, 1 do
						for dx = -1, 1 do
							if dx ~= 0 or dz ~= 0 then
								local hj = buffer.readi16(tops, (i + dz * size + dx) * 2)
								if hj >= h + 4 then
									higher += 1
									lowest = min(lowest, hj)
								end
							end
						end
					end
					if higher >= 6 then
						buffer.writei16(tops, i * 2, lowest)
						-- take the look of a raised neighbour (grass/meadow/stone…)
						for _, j in { i - 1, i + 1, i - size, i + size } do
							if buffer.readi16(tops, j * 2) == lowest then
								buffer.writeu8(kinds, i, buffer.readu8(kinds, j))
								break
							end
						end
						changed = true
					end
				end
			end
		end
		if not changed then
			break
		end
	end
end

--[[
	Block-wise slope relaxation of the natural hills (they are sampled on 16-stud blocks of
	2×2 columns): a block may stand at most MAX_STEP above any dry neighbour (block or fixed
	column), so the hills become climbable 4-stud terraces and the blocks stay whole (few parts).
]]
function VoxelWorld:relaxBlocks(hill: buffer)
	local n, size = self.n, self.size
	local tops, kinds = self.top, self.kind
	local b0 = -((n + 1) // 2) -- lowest block index (world block = floor(ix / 2))
	local bsize = n + 1
	local function blockOf(ix: number): number
		return ix // 2 - b0
	end
	local nb = bsize * bsize
	-- relaxable blocks: every column inside is a natural hill column
	local height = table.create(nb, -1)
	local relaxable = table.create(nb, true)
	local fixedCap = table.create(nb, math.huge)
	for iz = -n, n - 1 do
		for ix = -n, n - 1 do
			local b = blockOf(iz) * bsize + blockOf(ix) + 1
			local i = (iz + n) * size + (ix + n)
			if buffer.readu8(hill, i) == 1 then
				height[b] = max(height[b], buffer.readi16(tops, i * 2))
			else
				relaxable[b] = false
			end
		end
	end
	-- caps from fixed dry columns next to a relaxable block
	local function snapDown(h: number): number
		return floor(h / 4) * 4
	end
	for iz = -n, n - 1 do
		for ix = -n, n - 1 do
			local b = blockOf(iz) * bsize + blockOf(ix) + 1
			if relaxable[b] and height[b] >= 0 then
				for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local jx, jz = ix + d[1], iz + d[2]
					if jx >= -n and jx < n and jz >= -n and jz < n then
						local b2 = blockOf(jz) * bsize + blockOf(jx) + 1
						if b2 ~= b and not relaxable[b2] then
							local h2 = buffer.readi16(tops, ((jz + n) * size + (jx + n)) * 2)
							if h2 >= 2 then
								fixedCap[b] = min(fixedCap[b], snapDown(h2 + MAX_STEP))
							end
						end
					end
				end
			end
		end
	end
	-- chamfer sweeps over the block grid
	local function relax(b: number, b2: number): boolean
		if not relaxable[b2] or height[b2] < 2 then
			return false
		end
		local limit = height[b2] + MAX_STEP
		if height[b] > limit then
			height[b] = limit
			return true
		end
		return false
	end
	for b = 1, nb do
		if relaxable[b] and height[b] > fixedCap[b] then
			height[b] = fixedCap[b]
		end
	end
	for _ = 1, 64 do
		local changed = false
		for bz = 0, bsize - 1 do
			for bx = 0, bsize - 1 do
				local b = bz * bsize + bx + 1
				if relaxable[b] then
					if bx > 0 and relax(b, b - 1) then
						changed = true
					end
					if bz > 0 and relax(b, b - bsize) then
						changed = true
					end
				end
			end
		end
		for bz = bsize - 1, 0, -1 do
			for bx = bsize - 1, 0, -1 do
				local b = bz * bsize + bx + 1
				if relaxable[b] then
					if bx < bsize - 1 and relax(b, b + 1) then
						changed = true
					end
					if bz < bsize - 1 and relax(b, b + bsize) then
						changed = true
					end
				end
			end
		end
		if not changed then
			break
		end
	end
	-- write back
	for iz = -n, n - 1 do
		for ix = -n, n - 1 do
			local b = blockOf(iz) * bsize + blockOf(ix) + 1
			if relaxable[b] and height[b] >= 0 then
				local i = (iz + n) * size + (ix + n)
				if buffer.readi16(tops, i * 2) ~= height[b] then
					buffer.writei16(tops, i * 2, height[b])
					buffer.writeu8(kinds, i, KIND_INDEX[landKind(height[b])])
				end
			end
		end
	end
end

--[[
	Slope relaxation: on dry land every column may rise at most MAX_STEP above any dry
	neighbour, so all hills are climbable 4-stud terraces (one jump each) instead of 8-12-stud
	walls. Only lowers columns; locked ones (mesa cliffs, mountains) and the sea floor are kept.
	Chamfer sweeps (forward + backward) until nothing changes.
]]
function VoxelWorld:relaxSlopes(locked: buffer)
	local size = self.size
	local tops, kinds = self.top, self.kind
	local function relax(i: number, j: number): boolean
		local hj = buffer.readi16(tops, j * 2)
		if hj < 2 then
			return false -- water does not hold the land up (sea cliffs stay)
		end
		local hi = buffer.readi16(tops, i * 2)
		if hi > hj + MAX_STEP and buffer.readu8(locked, i) == 0 then
			local h = hj + MAX_STEP
			buffer.writei16(tops, i * 2, h)
			-- recolour by the new height (hills only; gameplay kinds are flat and never lowered)
			local kind = VoxelWorld.Kinds[buffer.readu8(kinds, i)]
			if kind == "grass" or kind == "grassRock" or kind == "stone" or kind == "snow" then
				buffer.writeu8(kinds, i, KIND_INDEX[landKind(h)])
			end
			return true
		end
		return false
	end
	for _ = 1, 64 do
		local changed = false
		for iz = 0, size - 1 do
			for ix = 0, size - 1 do
				local i = iz * size + ix
				if ix > 0 and relax(i, i - 1) then
					changed = true
				end
				if iz > 0 and relax(i, i - size) then
					changed = true
				end
			end
		end
		for iz = size - 1, 0, -1 do
			for ix = size - 1, 0, -1 do
				local i = iz * size + ix
				if ix < size - 1 and relax(i, i + 1) then
					changed = true
				end
				if iz < size - 1 and relax(i, i + size) then
					changed = true
				end
			end
		end
		if not changed then
			break
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
		if site.trail then
			-- the carved peak trail and the flat summit stay clear
			if sqrt((x - site.x) ^ 2 + (z - site.z) ^ 2) < site.summitRadius + m then
				return true
			end
			local d2max = (TRAIL_HALF_WIDTH + m) ^ 2
			for _, p in site.trail do
				if (x - p[1]) ^ 2 + (z - p[2]) ^ 2 < d2max then
					return true
				end
			end
		end
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
