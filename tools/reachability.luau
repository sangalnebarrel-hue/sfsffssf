--[[
	Walkability check on the baked terrain heightfield (no parts): BFS over 4-stud columns from
	the hub, where a step to a neighbour column is allowed if
	  • both are dry and the rise is ≤ MAX_STEP (walking/jumping), or
	  • either is water (swimming) and the dry side is ≤ MAX_EXIT above the water surface.
	Reports whether every base spawn, pier and tank is reachable, plus the largest unreachable
	dry patch inside the valley.
	Usage: lune run tools/reachability.luau
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local MapConfig = luau.load(fs.readFile("src/ReplicatedStorage/Shared/Config/MapConfig.luau"))()
local WorldGen = luau.load(fs.readFile("src/ServerStorage/WorldGen.luau"), { injectGlobals = true })()

local MAX_STEP = 5.5 -- default JumpPower 50 lifts ~7.2 studs; keep a margin
local MAX_EXIT = 4.5

local gen = WorldGen.new(MapConfig)
gen:build()
local n = gen.n

local function surface(ix: number, iz: number): (number, boolean)
	local h = gen:columnHeight(ix, iz)
	local w = gen:columnWater(ix, iz)
	if w == w and w > h + 0.5 then
		return w, true
	end
	return h, false
end

local function canStep(a: number, aWet: boolean, b: number, bWet: boolean): boolean
	if aWet or bWet then
		return b - a <= MAX_EXIT
	end
	return b - a <= MAX_STEP
end

local seen = {}
local function key(ix: number, iz: number): number
	return (iz + n) * 2 * n + (ix + n)
end
local function col(x: number): number
	return math.floor(x / 4)
end

local queue = { { col(0), col(0) } }
seen[key(col(0), col(0))] = true
local head = 1
local limit = MapConfig.BoundaryRadius - 4
while head <= #queue do
	local c = queue[head]
	head += 1
	local h, wet = surface(c[1], c[2])
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local nx, nz = c[1] + d[1], c[2] + d[2]
		local k = key(nx, nz)
		local x, z = nx * 4 + 2, nz * 4 + 2
		if not seen[k] and nx >= -n and nx < n and nz >= -n and nz < n and math.sqrt(x * x + z * z) < limit then
			local h2, wet2 = surface(nx, nz)
			if canStep(h, wet, h2, wet2) then
				seen[k] = true
				table.insert(queue, { nx, nz })
			end
		end
	end
end

local function reachable(x: number, z: number): boolean
	return seen[key(col(x), col(z))] == true
end

local function rotate(angle: number, lx: number, lz: number): (number, number)
	-- base local frame: +Z (lz) points away from the lake, origin at the slot (r = BaseRadius)
	local a = math.rad(angle)
	local ux, uz = math.sin(a), math.cos(a)
	local rx, rz = math.cos(a), -math.sin(a)
	local ox, oz = MapConfig.BaseRadius * ux, MapConfig.BaseRadius * uz
	return ox + ux * lz + rx * lx, oz + uz * lz + rz * lx
end

local bad = 0
for i = 1, MapConfig.BaseCount do
	local angle = MapConfig.BaseAngleOffset + (i - 1) * 360 / MapConfig.BaseCount
	local points = {
		spawn = { 0, 58 },
		gate = { 0, 84 },
		tank = { 9, -46 },
		shore = { 0, -8 },
		ringRoad = { 0, MapConfig.RingRoadRadius - MapConfig.BaseRadius },
	}
	local line = {}
	for name, p in points do
		local x, z = rotate(angle, p[1], p[2])
		local ok = reachable(x, z)
		if not ok then
			bad += 1
		end
		table.insert(line, `{name}={if ok then "ok" else "NO"}`)
	end
	table.sort(line)
	print(`base {i} ({angle}°): {table.concat(line, " ")}`)
end

-- Unreachable dry columns inside the valley (players could see but never get there).
local stranded = 0
for iz = -n, n - 1 do
	for ix = -n, n - 1 do
		local x, z = ix * 4 + 2, iz * 4 + 2
		local r = math.sqrt(x * x + z * z)
		if r < MapConfig.ValleyRadius and not seen[key(ix, iz)] then
			stranded += 1
		end
	end
end
print(`reachable columns: {head - 1}, unreachable inside valley (r<{MapConfig.ValleyRadius}): {stranded}`)
print(if bad == 0 then "ALL BASE POINTS REACHABLE" else `{bad} POINTS UNREACHABLE`)
