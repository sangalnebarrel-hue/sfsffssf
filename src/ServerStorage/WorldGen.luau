--!strict
--[[
	WorldGen — процедурный рельеф мира «Рыбацкая долина».

	Огромное озеро в кольце снежных гор, остров-деревня в центре, ровные террасы под 8 баз,
	кольцевая дорога с тропинками к базам и мостам, три реки с водопадами со скал, валуны.

	Чистый Luau (без game/workspace): им пользуются
	  • сборщик места (Lune) — «запекает» рельеф прямо в Place1.rbxl (Terrain.SmoothGrid);
	  • MapService — как запасной вариант: если рельеф в файле вдруг пуст, генерирует его заново.

	Единицы: studs. Рельеф строится колонками 4×4 studs (размер вокселя Terrain).
	Материалы — строки с именами Enum.Material (Grass, Sand, Rock, ...).

	local gen = WorldGen.new(MapConfig)
	gen:build()                                  -- считает карту высот (≈1-2 c)
	gen:fillColumn(ix, iz, function(iy, material, occupancy) end)  -- воксели колонки снизу вверх
	gen:surfaceAt(x, z) -> (height, material, waterLevel?)          -- для расстановки декора
	gen:isReserved(x, z) -> boolean                                  -- базы, дороги, реки, деревня
]]

export type Boulder = { x: number, y: number, z: number, radius: number }

local WorldGen = {}
WorldGen.__index = WorldGen

local VOXEL = 4
local NO_WATER = -1e9
-- Water levels must sit on voxel boundaries (multiples of 4).
local UPPER_RIVER_WATER = 40
local UPPER_RIVER_BED = 34
WorldGen.UpperRiverWater = UPPER_RIVER_WATER

local sqrt, abs, floor, max, min = math.sqrt, math.abs, math.floor, math.max, math.min
local sin, cos, rad, deg, atan2 = math.sin, math.cos, math.rad, math.deg, math.atan2

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

--------------------------------------------------------------------------------
-- Deterministic Perlin noise (same results in Lune and in Roblox)
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
function WorldGen:noise(x: number, y: number): number
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

-- Fractal noise (several octaves), about [-1, 1].
function WorldGen:fbm(x: number, y: number, octaves: number): number
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

function WorldGen.new(cfg: any, seed: number?)
	local self = setmetatable({}, WorldGen)
	self.cfg = cfg
	self.perm = makePermutation(seed or 20261011)

	self.baseAngles = {}
	for i = 1, cfg.BaseCount do
		self.baseAngles[i] = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
	end

	-- Column grid: ix, iz in [-n, n-1]; column centre = 4·i + 2.
	self.n = math.ceil(cfg.WorldHalf / VOXEL)
	self.size = 2 * self.n
	self.built = false
	self.boulders = {} :: { Boulder }
	return self
end

-- Coordinates of (x, z) in the frame of a shore anchor at angle `a` and radius `radius`:
-- lz grows inland (away from the lake centre), lx sideways (right when facing the lake).
local function shoreLocal(x: number, z: number, a: number, radius: number): (number, number)
	local ar = rad(a)
	local ux, uz = sin(ar), cos(ar)
	local dx, dz = x - radius * ux, z - radius * uz
	local lz = dx * ux + dz * uz
	local lx = dx * cos(ar) - dz * sin(ar)
	return lx, lz
end
WorldGen.shoreLocal = shoreLocal

-- Smooth radial height of the valley floor (no hills): used by roads.
function WorldGen:valleyBase(r: number): number
	local cfg = self.cfg
	local t = smoothstep(cfg.LakeRadius + cfg.BeachWidth, cfg.ValleyRadius, r)
	return cfg.GroundTop + 10 * t ^ 1.5
end

-- Shape before stamps: lake basin, beach, rolling valley, mountain ring, central island.
function WorldGen:naturalHeight(x: number, z: number): number
	local cfg = self.cfg
	local R, B, V, MR = cfg.LakeRadius, cfg.BeachWidth, cfg.ValleyRadius, cfg.MountainRadius
	local G = cfg.GroundTop
	local r = sqrt(x * x + z * z)
	-- Wavy natural shoreline.
	local rp = r - 10 * self:noise(x / 110 + 3.1, z / 110 - 7.7)

	local h
	if rp < R then
		local t = smoothstep(R * 0.3, R, rp)
		h = lerp(-cfg.LakeDepth, -2.5, t) + 1.8 * self:noise(x / 37, z / 37)
	elseif rp < R + B then
		h = lerp(-2.5, G, smoothstep(R, R + B, rp))
	else
		h = self:valleyBase(rp)
		-- Rolling hills, flat near the lake.
		local hills = self:fbm(x / 150 + 40, z / 150 + 9, 4) * 0.5 + 0.5
		h += hills * 20 * smoothstep(R + B + 30, V, rp)
		-- Mountain ring with ridges and peaks.
		if rp > V - 40 then
			local mt = smoothstep(V - 30, MR, rp)
			-- Broad ridges (low frequency) give big readable mountains; a little detail on top.
			local ridge = 1 - abs(self:fbm(x / 260 - 13, z / 260 + 21, 3))
			local peaks = 0.4 + 0.6 * ridge * ridge
			h += cfg.MountainHeight * mt ^ 1.35 * peaks
			h += 9 * self:fbm(x / 85 + 5, z / 85 + 5, 3) * mt
		end
	end

	-- Central island: flat plaza with gently sloping beaches.
	if r < cfg.HubRadius + 40 then
		local island = lerp(G, -7, smoothstep(cfg.HubPlazaRadius, cfg.HubRadius + 10, r))
		h = max(h, island)
	end
	return h
end

--------------------------------------------------------------------------------
-- Stamps: flatten areas for gameplay, carve rivers, raise waterfall cliffs
--------------------------------------------------------------------------------

-- Returns height, surface "kind" and water level (NO_WATER if dry).
function WorldGen:heightAt(x: number, z: number): (number, string, number)
	local cfg = self.cfg
	local G = cfg.GroundTop
	local R = cfg.LakeRadius
	local r = sqrt(x * x + z * z)
	local theta = deg(atan2(x, z))
	local h = self:naturalHeight(x, z)
	local kind = "natural"

	local roadR, roadHalf = cfg.RingRoadRadius, cfg.RoadWidth / 2
	local roadH = self:valleyBase(roadR)

	-- Central plaza.
	if r < cfg.HubPlazaRadius - 2 then
		kind = "plaza"
	end

	-- Base plots: flat terrace + sand beach in front + path to the ring road.
	local D, HW = cfg.BasePlotDepth, cfg.BasePlotHalfWidth
	for _, a in self.baseAngles do
		if abs(angleDiff(theta, a)) < 30 and r > R - 40 and r < roadR + 20 then
			local lx, lz = shoreLocal(x, z, a, cfg.BaseRadius)
			if abs(lx) < HW + 18 and lz > -22 and lz < D + 18 then
				local target = if lz >= 0 then G else lerp(-3, G, smoothstep(-14, 0, lz))
				local w = (1 - smoothstep(HW, HW + 16, abs(lx)))
					* (1 - smoothstep(D, D + 16, lz))
					* smoothstep(-22, -14, lz)
				h = lerp(h, target, w)
				if w > 0.6 then
					kind = if lz >= 0 then "plot" else "beach"
				end
			end
			-- Path from the back of the plot to the ring road.
			if abs(lx) < 12 and lz >= D - 2 and r < roadR + 2 then
				local roadLz = roadR - cfg.BaseRadius
				local target = lerp(G, roadH, smoothstep(D, roadLz, lz))
				local w = 1 - smoothstep(4, 10, abs(lx))
				h = lerp(h, target, w)
				if abs(lx) < 4.5 then
					kind = "road"
				end
			end
		end
	end

	-- Bridge landings on the shore + paths to the ring road.
	for _, a in cfg.BridgeAngles do
		if abs(angleDiff(theta, a)) < 12 and r > R - 30 and r < roadR + 4 then
			local lx, lz = shoreLocal(x, z, a, R)
			if abs(lx) < 26 and lz > -22 then
				local target = if lz >= -4
					then lerp(G, roadH, smoothstep(30, roadR - R, lz))
					else lerp(-3, G, smoothstep(-14, -4, lz))
				local w = (1 - smoothstep(10, 22, abs(lx))) * smoothstep(-22, -14, lz)
				h = lerp(h, target, w)
				if abs(lx) < 5 and lz > 2 then
					kind = "road"
				elseif w > 0.6 and lz < 2 then
					kind = "beach"
				end
			end
		end
	end

	-- Ring road around the lake.
	local dr = abs(r - roadR)
	if dr < roadHalf + 12 then
		local w = 1 - smoothstep(roadHalf, roadHalf + 12, dr)
		h = lerp(h, roadH, w)
		if dr < roadHalf then
			kind = "road"
		end
	end

	-- Rivers: waterfall cliff (mesa) + upper river, pool at the foot, lower river to the lake.
	local water = NO_WATER
	for _, a in cfg.Rivers do
		local d = angleDiff(theta, a)
		if abs(d) < 25 and r > R - 40 then
			local wobble = 3.5 * sin((r - R) / 38)
			local lat = r * rad(d - wobble) -- sideways distance from the river centreline
			local alat = abs(lat)
			local hw = cfg.RiverWidth / 2
			local fallR = cfg.ValleyRadius + 26 -- where the water drops from the cliff

			-- Mesa with a sheer cliff the waterfall drops from.
			if r > fallR - 8 and r < fallR + 110 and alat < 90 then
				local top = 46 + 3 * self:noise(x / 20, z / 20)
				local w = smoothstep(fallR - 6, fallR, r) * (1 - smoothstep(55, 85, alat))
				h = max(h, lerp(h, top, w))
			end

			if r <= fallR then
				-- Pool at the foot of the waterfall.
				local poolDist = sqrt(lat * lat + (r - (fallR - 12)) ^ 2)
				if poolDist < 26 then
					h = min(h, lerp(-6, h, smoothstep(14, 26, poolDist)))
					if poolDist < 22 then
						water = 0
					end
				end
				-- Lower river down to the lake.
				if alat < hw + 8 then
					h = min(h, lerp(-5, h, smoothstep(hw - 3, hw + 8, alat)))
					if alat < hw + 4 then
						water = 0
					end
					if alat < hw + 2 then
						kind = "river"
					end
				end
			elseif r < fallR + 170 then
				-- Upper river cut into the mesa and the mountains.
				if alat < hw + 6 then
					h = min(h, lerp(UPPER_RIVER_BED, h, smoothstep(hw - 4, hw + 6, alat)))
					if alat < hw + 2 then
						water = UPPER_RIVER_WATER
						kind = "river"
					end
				end
			end
		end
	end

	-- Lake water.
	if h < cfg.WaterTop and r < cfg.LakeRadius + cfg.BeachWidth + 20 then
		water = max(water, cfg.WaterTop)
	end
	if water ~= NO_WATER and h >= water then
		water = NO_WATER
	end
	return h, kind, water
end

--------------------------------------------------------------------------------
-- Heightfield
--------------------------------------------------------------------------------

function WorldGen:index(ix: number, iz: number): number
	return (iz + self.n) * self.size + (ix + self.n)
end

-- Computes heights, water and surface materials for every column.
function WorldGen:build()
	local n, size = self.n, self.size
	local count = size * size
	self.height = buffer.create(count * 4)
	self.water = buffer.create(count * 4)
	self.kind = table.create(count, "natural")
	for iz = -n, n - 1 do
		for ix = -n, n - 1 do
			local x, z = ix * VOXEL + 2, iz * VOXEL + 2
			local h, kind, water = self:heightAt(x, z)
			local i = self:index(ix, iz)
			buffer.writef32(self.height, i * 4, h)
			buffer.writef32(self.water, i * 4, water)
			self.kind[i + 1] = kind
		end
	end
	self.built = true
	self:placeBoulders()
end

function WorldGen:columnHeight(ix: number, iz: number): number
	local n = self.n
	ix = clamp(ix, -n, n - 1)
	iz = clamp(iz, -n, n - 1)
	return buffer.readf32(self.height, self:index(ix, iz) * 4)
end

function WorldGen:columnWater(ix: number, iz: number): number
	return buffer.readf32(self.water, self:index(ix, iz) * 4)
end

-- Steepness (rise per stud) at a column.
function WorldGen:slope(ix: number, iz: number): number
	local dx = self:columnHeight(ix + 1, iz) - self:columnHeight(ix - 1, iz)
	local dz = self:columnHeight(ix, iz + 1) - self:columnHeight(ix, iz - 1)
	return sqrt(dx * dx + dz * dz) / (2 * VOXEL)
end

-- Surface material of a column (top layer).
function WorldGen:surfaceMaterial(ix: number, iz: number): string
	local cfg = self.cfg
	local i = self:index(ix, iz)
	local h = buffer.readf32(self.height, i * 4)
	local water = buffer.readf32(self.water, i * 4)
	local kind = self.kind[i + 1]
	local x, z = ix * VOXEL + 2, iz * VOXEL + 2
	local r = sqrt(x * x + z * z)
	local slope = self:slope(ix, iz)
	local patch = self:noise(x / 45 + 17, z / 45 - 31)

	if water > NO_WATER then
		if kind == "river" and water > 20 then
			return "Slate"
		end
		return if h > -7 then "Sand" elseif patch > 0.15 then "Mud" else "Ground"
	elseif kind == "plaza" then
		return "Cobblestone"
	elseif kind == "road" then
		return if r < cfg.LakeRadius + 6 then "Sand" else "Ground"
	elseif kind == "beach" or (h < 2.6 and r < cfg.LakeRadius + cfg.BeachWidth + 30) then
		return "Sand"
	elseif kind == "river" then
		return "Sand"
	elseif h > cfg.SnowLine + 18 * patch and slope < 1.4 then
		return "Snow"
	elseif slope > 1.35 then
		return if h > 70 then "Slate" else "Rock"
	elseif slope > 0.95 then
		return "Rock"
	elseif h > 110 + 20 * patch then
		return if patch > 0.25 then "Rock" else "Ground"
	elseif h > 60 + 15 * patch then
		return if patch > 0.1 then "Grass" else "LeafyGrass" -- alpine meadows
	elseif kind == "plot" then
		return "Grass"
	end
	return if patch > 0.22 then "LeafyGrass" else "Grass"
end

-- What lies under the surface layer.
local SUBSURFACE = {
	Grass = "Ground",
	LeafyGrass = "Ground",
	Ground = "Ground",
	Cobblestone = "Ground",
	Sand = "Sandstone",
	Mud = "Ground",
	Snow = "Rock",
	Rock = "Rock",
	Slate = "Slate",
}

-- Big rocks scattered over the valley (terrain spheres).
function WorldGen:placeBoulders()
	local cfg = self.cfg
	local state = 977
	local function rand(): number
		state = (state * 48271) % 2147483647
		return state / 2147483647
	end
	local attempts = 0
	while #self.boulders < 46 and attempts < 2000 do
		attempts += 1
		local a = rand() * 360
		local r = lerp(cfg.LakeRadius + 50, cfg.ValleyRadius + 60, rand())
		local x, z = r * sin(rad(a)), r * cos(rad(a))
		if not self:isReserved(x, z, 14) then
			local h = self:surfaceAt(x, z)
			local radius = lerp(3.5, 8.5, rand() ^ 1.7)
			table.insert(self.boulders, { x = x, y = h - radius * 0.35, z = z, radius = radius })
		end
	end
end

--------------------------------------------------------------------------------
-- Queries for decor placement
--------------------------------------------------------------------------------

-- Surface height, material and water level (nil if dry) at a world point.
function WorldGen:surfaceAt(x: number, z: number): (number, string, number?)
	assert(self.built, "WorldGen:build() first")
	local ix, iz = floor(x / VOXEL), floor(z / VOXEL)
	-- Bilinear height between column centres.
	local fx, fz = x / VOXEL - 0.5, z / VOXEL - 0.5
	local x0, z0 = floor(fx), floor(fz)
	local tx, tz = fx - x0, fz - z0
	local h = lerp(
		lerp(self:columnHeight(x0, z0), self:columnHeight(x0 + 1, z0), tx),
		lerp(self:columnHeight(x0, z0 + 1), self:columnHeight(x0 + 1, z0 + 1), tx),
		tz
	)
	local n = self.n
	if ix < -n or ix >= n or iz < -n or iz >= n then
		return h, "Rock", nil
	end
	local water = self:columnWater(ix, iz)
	return h, self:surfaceMaterial(ix, iz), if water > NO_WATER then water else nil
end

-- True where gameplay areas are (no trees/rocks there): bases, roads, rivers, plaza, bridges, water.
function WorldGen:isReserved(x: number, z: number, margin: number?): boolean
	local cfg = self.cfg
	local m = margin or 0
	local r = sqrt(x * x + z * z)
	local theta = deg(atan2(x, z))
	if r < cfg.LakeRadius + cfg.BeachWidth + m then
		return true -- lake, island, beach
	end
	if abs(r - cfg.RingRoadRadius) < cfg.RoadWidth / 2 + 4 + m then
		return true
	end
	for _, a in self.baseAngles do
		if abs(angleDiff(theta, a)) < 35 then
			local lx, lz = shoreLocal(x, z, a, cfg.BaseRadius)
			if abs(lx) < cfg.BasePlotHalfWidth + 6 + m and lz < cfg.BasePlotDepth + 8 + m then
				return true
			end
			if abs(lx) < 8 + m and lz < cfg.RingRoadRadius - cfg.BaseRadius + 8 then
				return true
			end
		end
	end
	for _, a in cfg.BridgeAngles do
		if abs(angleDiff(theta, a)) < 15 then
			local lx = select(1, shoreLocal(x, z, a, cfg.LakeRadius))
			if abs(lx) < 12 + m then
				return true
			end
		end
	end
	for _, a in cfg.Rivers do
		local d = angleDiff(theta, a)
		if abs(d) < 25 then
			local wobble = 3.5 * sin((r - cfg.LakeRadius) / 38)
			local lat = abs(r * rad(d - wobble))
			if lat < cfg.RiverWidth / 2 + 10 + m then
				return true
			end
			local fallR = cfg.ValleyRadius + 26
			if r > fallR - 40 and r < fallR + 12 and lat < 34 + m then
				return true -- pool and cliff edge
			end
		end
	end
	if r > cfg.BoundaryRadius - 10 then
		return true
	end
	return false
end

--------------------------------------------------------------------------------
-- Voxels
--------------------------------------------------------------------------------

-- Vertical voxel range of the world (iy: voxel y index, voxel spans 4·iy .. 4·iy+4 studs).
function WorldGen:voxelRangeY(): (number, number)
	local cfg = self.cfg
	return floor(-cfg.LakeDepth / VOXEL) - 3, math.ceil((cfg.MountainHeight + 80) / VOXEL)
end

-- Calls emit(iy, material, occupancy) for every non-air voxel of a column, bottom to top.
-- occupancy is 0..1 (fraction of the voxel filled).
function WorldGen:fillColumn(ix: number, iz: number, emit: (number, string, number) -> ())
	assert(self.built, "WorldGen:build() first")
	local i = self:index(ix, iz)
	local h = buffer.readf32(self.height, i * 4)
	local water = buffer.readf32(self.water, i * 4)
	local surface = self:surfaceMaterial(ix, iz)
	local below = SUBSURFACE[surface] or "Ground"

	-- Solid down to below the lowest neighbour, so cliffs have no holes; deeper is never seen.
	local lowest = min(
		h,
		self:columnHeight(ix - 1, iz),
		self:columnHeight(ix + 1, iz),
		self:columnHeight(ix, iz - 1),
		self:columnHeight(ix, iz + 1)
	)
	local yMin = self:voxelRangeY()
	local bottom = max(yMin, floor((lowest - 10) / VOXEL))
	local underwater = water > NO_WATER

	local x, z = ix * VOXEL + 2, iz * VOXEL + 2
	local topIndex = floor(h / VOXEL)
	for iy = bottom, topIndex do
		local y0 = iy * VOXEL
		local fill = clamp((h - y0) / VOXEL, 0, 1)
		if underwater and fill > 0 then
			fill = 1 -- no air pockets under water
		end
		if fill > 0.02 then
			local depth = h - (y0 + VOXEL)
			local material = if depth < 3 then surface elseif depth < 14 then below else "Rock"
			emit(iy, material, fill)
		end
	end

	-- Boulders crossing this column.
	for _, b in self.boulders do
		local dx, dz = x - b.x, z - b.z
		local d2 = dx * dx + dz * dz
		if d2 < (b.radius + 2) ^ 2 then
			local halfChord = sqrt(max(0, b.radius * b.radius - d2))
			if halfChord > 0 then
				for iy = floor((b.y - halfChord) / VOXEL), floor((b.y + halfChord) / VOXEL) do
					local yc = iy * VOXEL + 2
					local inside = halfChord - abs(yc - b.y)
					local fill = clamp(inside / VOXEL + 0.5, 0, 1)
					if fill > 0.05 and yc > h - 2 then
						emit(iy, "Rock", fill)
					end
				end
			end
		end
	end

	-- Water above the bed (starts right above the last emitted solid voxel).
	if underwater then
		local topFill = clamp((h - topIndex * VOXEL) / VOXEL, 0, 1)
		local firstWater = if topFill > 0.02 then topIndex + 1 else topIndex
		local fromIy = max(firstWater, bottom)
		for iy = fromIy, floor(water / VOXEL) - 1 do
			emit(iy, "Water", 1)
		end
	end
end

return WorldGen
