--[[
	Builds Workspace.Map — everything made of parts in World v3 «Остров Рыбаков»
	(see tools/builder/DESIGN.md). The ground comes from VoxelWorld (heightfield) via Ground.luau;
	the water is Terrain (baked separately in tools/build.luau). This module places on top:
	  Map.BaseSlots    8 invisible markers where the server clones the base template
	  Map.Ground       voxel ground (Ground.luau)
	  Map.Hub          the central island village (Hub.luau)
	  Map.Bridges      4 bridges hub ↔ promenade
	  Map.Promenade    the ring walkway along the lagoon with lamps
	  Map.Nature       trees, bushes, flowers on the hills (away from gameplay areas)
	  Map.Lagoon       boats and buoys
	  Map.Boundaries   invisible ring wall in the ocean

	Coordinates: angle θ (degrees, 0 = +Z) and radius r map to (r·sin θ, y, r·cos θ).
]]

local U = require("./Util")
local Props = require("./Props")
local buildHub = require("./Hub")
local buildGround = require("./Ground")

local Vector3 = U.Vector3
local CFrame = U.CFrame

local sqrt, rad = math.sqrt, math.rad

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

-- Ground CFrame at (x, z) on top of the voxel column, facing yaw degrees.
local function groundCFrame(world: any, x: number, z: number, yaw: number): any
	return CFrame.new(x, world:heightAt(x, z), z) * CFrame.Angles(0, rad(yaw), 0)
end

local function angleDistance(a: number, b: number): number
	return math.abs(((a - b + 180) % 360) - 180)
end

--------------------------------------------------------------------------------

local function buildSlots(map: any, cfg: any)
	local slots = U.folder(map, "BaseSlots")
	for i = 1, cfg.BaseCount do
		local angle = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		-- polarCFrame faces the slot's −Z towards the lagoon centre
		U.marker(slots, `Slot_{i}`, Vector3.new(4, 0.2, 4), U.polarCFrame(angle, cfg.BaseRadius, cfg.GroundTop), {
			Attributes = { Index = i, Angle = angle },
		})
	end
end

local function buildBridges(map: any, cfg: any)
	local bridges = U.model(map, "Bridges")
	for i, angle in cfg.BridgeAngles do
		local from = U.polar(angle, cfg.HubPlazaRadius - 6, 0)
		local to = U.polar(angle, cfg.PromenadeRadius + 2, 0)
		local bridge = call("bridge", bridges, from, to, {
			deckY = cfg.GroundTop + 0.6,
			width = cfg.BridgeWidth,
			bedY = -cfg.LagoonDepth,
		})
		bridge.Name = `Bridge_{i}`
	end
end

-- The promenade: a ring of plank deck segments along the lagoon, with lamps on the water side.
local function buildPromenade(map: any, cfg: any, world: any)
	local promenade = U.model(map, "Promenade")
	local deck = U.model(promenade, "Deck")
	local inner = cfg.PromenadeRadius
	local outer = inner + cfg.PromenadeWidth
	local mid = (inner + outer) / 2
	local segments = 96
	local step = 360 / segments
	local colors = { U.rgb(236, 184, 120), U.rgb(222, 166, 104) }
	for k = 0, segments - 1 do
		local a = k * step
		local length = 2 * outer * math.tan(rad(step / 2)) + 0.6
		U.part(
			deck,
			"Deck",
			Vector3.new(length, 0.6, cfg.PromenadeWidth),
			U.polarCFrame(a, mid, cfg.GroundTop + 0.3),
			colors[k % 2 + 1]
		)
	end
	local lamps = U.model(promenade, "Lamps")
	local placed = 0
	for k = 0, 47 do
		local a = k * 7.5 + 3.75
		local clear = true
		for _, b in cfg.BridgeAngles do
			if angleDistance(a, b) < 4 then
				clear = false
			end
		end
		for i = 1, cfg.BaseCount do
			if angleDistance(a, cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount) < 5 then
				clear = false -- pier entrance
			end
		end
		if clear then
			local p = U.polar(a, inner + 1.5, 0)
			call("lampPost", lamps, CFrame.new(p.X, cfg.GroundTop + 0.6, p.Z) * CFrame.Angles(0, rad(a), 0), {
				light = k % 2 == 0,
			})
			placed += 1
		end
	end
	return placed
end

local function buildNature(map: any, cfg: any, world: any)
	local nature = U.model(map, "Nature")
	local trees = U.model(nature, "Trees")
	local plants = U.model(nature, "Plants")
	local random = makeRandom(4242)
	local counts = { pine = 0, round = 0, palm = 0, bush = 0, flowers = 0 }

	-- Jittered grid: one candidate per cell, so forests are dense but never overlap.
	local cell = 24
	local maxR = cfg.RingOuterRadius + 60
	for gz = -maxR, maxR, cell do
		for gx = -maxR, maxR, cell do
			local x = gx + random(-cell * 0.35, cell * 0.35)
			local z = gz + random(-cell * 0.35, cell * 0.35)
			local r = sqrt(x * x + z * z)
			if r > cfg.PromenadeRadius and r < maxR and not world:isReserved(x, z, 4) then
				local h, kind = world:surfaceAt(x, z)
				local soft = kind == "grass" or kind == "meadow" or kind == "grassRock"
				local flatEnough = world:slope(x, z) <= 4
				local grove = world:noise(x / 160 + 70, z / 160 - 30) * 0.5 + 0.5
				if soft and flatEnough and h > 2 and random() < 0.15 + 0.6 * grove then
					local cf = groundCFrame(world, x, z, random(0, 360))
					local opts = { seed = math.floor(random(1, 100000)), scale = random(0.9, 1.3) }
					if h <= 8 and r > cfg.RingOuterRadius - 80 and random() < 0.6 then
						call("palmTree", trees, cf, opts)
						counts.palm += 1
					elseif h > 24 or random() < 0.4 then
						call("pineTree", trees, cf, opts)
						counts.pine += 1
					else
						call("roundTree", trees, cf, opts)
						counts.round += 1
					end
				elseif soft and flatEnough and random() < 0.12 then
					local opts = { seed = math.floor(random(1, 100000)) }
					if random() < 0.5 then
						call("bush", plants, groundCFrame(world, x, z, random(0, 360)), opts)
						counts.bush += 1
					else
						call("flowerPatch", plants, groundCFrame(world, x, z, random(0, 360)), opts)
						counts.flowers += 1
					end
				end
			end
		end
	end
	return counts
end

local function buildLagoon(map: any, cfg: any)
	local lagoon = U.model(map, "Lagoon")
	local random = makeRandom(777)
	for k = 0, 3 do
		local a = 45 + k * 90 + random(-6, 6)
		local p = U.polar(a, random(190, 240), 0)
		local cf = CFrame.new(p.X, 0, p.Z) * CFrame.Angles(0, rad(random(0, 360)), 0)
		call(if k % 2 == 0 then "sailboat" else "rowboat", lagoon, cf, { seed = k + 1 })
	end
	for k = 0, 15 do
		local p = U.polar(k * 22.5 + 11.25, (cfg.HubRadius + cfg.LagoonRadius) / 2, 0)
		call("buoy", lagoon, CFrame.new(p.X, 0, p.Z), { seed = k })
	end
end

local function buildBoundaries(map: any, cfg: any)
	local walls = U.folder(map, "Boundaries")
	local count = 48
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

return function(game: any, cfg: any, world: any)
	local workspace = game:GetService("Workspace")
	local map = U.new("Model", { Name = "Map" }, workspace)

	buildSlots(map, cfg)
	local ground = buildGround(map, world)
	local hub = buildHub(map, cfg, world)
	buildBridges(map, cfg)
	local lamps = buildPromenade(map, cfg, world)
	local natureCounts = buildNature(map, cfg, world)
	buildLagoon(map, cfg)
	buildBoundaries(map, cfg)

	return {
		map = map,
		groundParts = ground.parts,
		natureCounts = natureCounts,
		lamps = lamps,
		expectedAttachments = hub.expectedAttachments or {},
	}
end
