--[[
	Builds Workspace.Map — everything made of parts in the big "Fishing Valley" world.
	The terrain itself (lake, beaches, valley, mountains, rivers) is baked separately
	(tools/terrain/Bake.luau from src/ServerStorage/WorldGen.luau); this module places
	parts ON that terrain using the generator's height queries:
	  Map.BaseSlots   8 invisible markers where the server clones the base template
	  Map.Hub         the central island village (tools/builder/Hub.luau)
	  Map.Bridges     4 long bridges to the island + bridges where the ring road crosses rivers
	  Map.Waterfalls  falling water sheets at the river cliffs
	  Map.Nature      forests, bushes, flowers (scattered on terrain, away from gameplay areas)
	  Map.Road        lamp posts and signposts along the ring road
	  Map.Lake        boats and buoys on the lake
	  Map.Boundaries  invisible ring wall in front of the mountains

	Coordinates: angle θ (degrees, 0 = +Z) and radius r map to (r·sin θ, y, r·cos θ).
]]

local U = require("./Util")
local Props = require("./Props")
local buildHub = require("./Hub")

local Vector3 = U.Vector3
local CFrame = U.CFrame

local sin, rad, sqrt = math.sin, math.rad, math.sqrt

-- Deterministic random numbers (the world must be identical on every build).
local function makeRandom(seed: number)
	local state = seed
	return function(a: number?, b: number?): number
		state = (state * 48271) % 2147483647
		local t = state / 2147483647
		if a and b then
			return a + (b - a) * t
		end
		return t
	end
end

local function call(name: string, ...: any): any
	local fn = (Props :: any)[name]
	if type(fn) ~= "function" then
		error(`Props.{name} is missing`)
	end
	return fn(...)
end

-- Ground CFrame at (x, z) on the terrain surface (slightly sunk), facing yaw degrees.
local function groundCFrame(gen: any, x: number, z: number, yaw: number, sink: number?): any
	local h = gen:surfaceAt(x, z)
	return CFrame.new(x, h - (sink or 0.4), z) * CFrame.Angles(0, rad(yaw), 0)
end

local function angleDistance(a: number, b: number): number
	return math.abs(((a - b + 180) % 360) - 180)
end

--------------------------------------------------------------------------------

local function buildSlots(map: any, cfg: any)
	local slots = U.folder(map, "BaseSlots")
	for i = 1, cfg.BaseCount do
		local angle = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		U.marker(slots, `Slot_{i}`, Vector3.new(4, 0.2, 4), U.polarCFrame(angle, cfg.BaseRadius, cfg.GroundTop), {
			Attributes = { Index = i, Angle = angle },
		})
	end
end

local function buildBridges(map: any, cfg: any, gen: any)
	local bridges = U.model(map, "Bridges")
	local deckY = cfg.GroundTop + 0.6
	for i, angle in cfg.BridgeAngles do
		local from = U.polar(angle, cfg.HubPlazaRadius - 3, 0)
		local to = U.polar(angle, cfg.LakeRadius + 4, 0)
		local bridge = call("bridge", bridges, from, to, {
			deckY = deckY,
			width = cfg.BridgeWidth,
			bedY = -cfg.LakeDepth,
		})
		bridge.Name = `Bridge_{i}`
	end
	-- Ring road crossing each river.
	local roadR = cfg.RingRoadRadius
	for i, angle in cfg.Rivers do
		local centre = angle + 3.5 * sin((roadR - cfg.LakeRadius) / 38)
		local halfSpan = math.deg((cfg.RiverWidth / 2 + 12) / roadR)
		local from = U.polar(centre - halfSpan, roadR, 0)
		local to = U.polar(centre + halfSpan, roadR, 0)
		local deck = math.max((gen:surfaceAt(from.X, from.Z)), (gen:surfaceAt(to.X, to.Z))) + 0.6
		local bridge = call("bridge", bridges, from, to, { deckY = deck, width = cfg.RoadWidth - 2, bedY = -6 })
		bridge.Name = `RiverBridge_{i}`
	end
end

local function buildWaterfalls(map: any, cfg: any, gen: any)
	local falls = U.model(map, "Waterfalls")
	local fallR = cfg.ValleyRadius + 26
	for i, angle in cfg.Rivers do
		local function at(r: number, y: number)
			return U.polar(angle + 3.5 * sin((r - cfg.LakeRadius) / 38), r, y)
		end
		local top = at(fallR + 1, gen.UpperRiverWater or 40)
		local bottom = at(fallR - 7, 0)
		local fall = call("waterfall", falls, top, bottom, cfg.RiverWidth - 4)
		fall.Name = `Waterfall_{i}`
	end
end

local function buildNature(map: any, cfg: any, gen: any)
	local nature = U.model(map, "Nature")
	local trees = U.model(nature, "Trees")
	local plants = U.model(nature, "Plants")
	local random = makeRandom(4242)
	local beachR = cfg.LakeRadius + cfg.BeachWidth
	local counts = { pine = 0, round = 0, palm = 0, bush = 0, flowers = 0 }

	-- Jittered grid: one candidate per cell, so forests are dense but never overlap.
	local cell = 26
	local maxR = cfg.BoundaryRadius + 30
	for gz = -maxR, maxR, cell do
		for gx = -maxR, maxR, cell do
			local x = gx + random(-cell * 0.4, cell * 0.4)
			local z = gz + random(-cell * 0.4, cell * 0.4)
			local r = sqrt(x * x + z * z)
			if r > beachR + 4 and r < maxR and not gen:isReserved(x, z, 3) then
				local h, material = gen:surfaceAt(x, z)
				local slope = gen:slope(math.floor(x / 4), math.floor(z / 4))
				local soft = material == "Grass" or material == "LeafyGrass" or material == "Ground"
				-- Thick groves (noise) in the valley, sparser higher up the mountains.
				local grove = gen:noise(x / 160 + 70, z / 160 - 30) * 0.5 + 0.5
				local chance = if r < cfg.ValleyRadius then 0.2 + 0.65 * grove else 0.5 * (1 - (h - 40) / 140)
				if soft and slope < 0.75 and h < 150 and random() < chance then
					local cf = groundCFrame(gen, x, z, random(0, 360))
					local opts = { seed = math.floor(random(1, 100000)), scale = random(0.85, 1.3) }
					if r < beachR + 40 and random() < 0.6 then
						call("palmTree", trees, cf, opts)
						counts.palm += 1
					elseif h > 28 or random() < 0.45 then
						opts.scale *= 1.1
						call("pineTree", trees, cf, opts)
						counts.pine += 1
					else
						call("roundTree", trees, cf, opts)
						counts.round += 1
					end
				elseif soft and slope < 0.5 and r < cfg.ValleyRadius and random() < 0.25 then
					local opts = { seed = math.floor(random(1, 100000)) }
					if random() < 0.55 then
						call("bush", plants, groundCFrame(gen, x, z, random(0, 360), 0.6), opts)
						counts.bush += 1
					else
						call("flowerPatch", plants, groundCFrame(gen, x, z, random(0, 360), 0.2), opts)
						counts.flowers += 1
					end
				end
			end
		end
	end
	return counts
end

local function buildRoad(map: any, cfg: any, gen: any)
	local road = U.model(map, "Road")
	local roadR = cfg.RingRoadRadius
	local edge = roadR - cfg.RoadWidth / 2 - 2.5 -- inner (lake-side) edge of the road
	local placed = 0
	for k = 0, 47 do
		local a = k * 7.5 + 3.75
		local clear = true
		for _, river in cfg.Rivers do
			if angleDistance(a, river) < 7 then
				clear = false -- river bridges here
			end
		end
		for _, b in cfg.BridgeAngles do
			if angleDistance(a, b) < 3 then
				clear = false -- bridge path junction
			end
		end
		for i = 1, cfg.BaseCount do
			if angleDistance(a, cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount) < 3 then
				clear = false -- base path junction
			end
		end
		if clear then
			local p = U.polar(a, edge, 0)
			call("lampPost", road, groundCFrame(gen, p.X, p.Z, a + 180, 0.2), { light = k % 3 == 0 })
			placed += 1
		end
	end
	-- Signposts where the bridge paths meet the ring road.
	for _, angle in cfg.BridgeAngles do
		local p = U.polar(angle + 3.2, edge - 1, 0)
		call("signpost", road, groundCFrame(gen, p.X, p.Z, angle + 180, 0.2), { text = "ОСТРОВ" })
	end
	return placed
end

local function buildLake(map: any, cfg: any)
	local lake = U.model(map, "Lake")
	local random = makeRandom(777)
	-- Boats between the bridges (on the diagonals there are no piers or bridges).
	for k = 0, 3 do
		local a = 45 + k * 90 + random(-8, 8)
		local p = U.polar(a, random(115, 160), 0)
		local cf = CFrame.new(p.X, 0, p.Z) * CFrame.Angles(0, rad(random(0, 360)), 0)
		call(if k % 2 == 0 then "sailboat" else "rowboat", lake, cf, { seed = k + 1 })
	end
	-- A ring of buoys around the deep middle of the lake.
	for k = 0, 11 do
		local p = U.polar(k * 30 + 15, 100, 0)
		call("buoy", lake, CFrame.new(p.X, 0, p.Z), { seed = k })
	end
end

local function buildBoundaries(map: any, cfg: any)
	local walls = U.folder(map, "Boundaries")
	local count = 32
	local R = cfg.BoundaryRadius
	local width = 2 * R * math.tan(math.pi / count) + 4
	for k = 0, count - 1 do
		U.part(
			walls,
			"Wall",
			Vector3.new(width, 600, 4),
			U.polarCFrame(k * 360 / count, R, 250),
			U.rgb(255, 255, 255),
			nil,
			{
				Transparency = 1,
				CanQuery = false,
				CastShadow = false,
				Locked = true,
			}
		)
	end
end

--------------------------------------------------------------------------------

return function(game: any, cfg: any, gen: any)
	local workspace = game:GetService("Workspace")
	local map = U.new("Model", { Name = "Map" }, workspace)

	buildSlots(map, cfg)
	local hub = buildHub(map, cfg)
	buildBridges(map, cfg, gen)
	buildWaterfalls(map, cfg, gen)
	local natureCounts = buildNature(map, cfg, gen)
	local lamps = buildRoad(map, cfg, gen)
	buildLake(map, cfg)
	buildBoundaries(map, cfg)

	return {
		map = map,
		natureCounts = natureCounts,
		lamps = lamps,
		expectedAttachments = hub.expectedAttachments or {},
	}
end
