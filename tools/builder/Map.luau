--[[
	Builds Workspace.Map — everything made of parts in World v3 «Остров Рыбаков»
	(see tools/builder/DESIGN.md). The ground comes from VoxelWorld (heightfield) via Ground.luau;
	the water is Terrain (baked separately in tools/build.luau). This module assembles:
	  Map.BaseSlots    8 invisible markers where the server clones the base template
	  Map.Ground       voxel ground (Ground.luau)
	  Map.Hub          the central island village (Hub.luau)
	  Map.Bridges      4 bridges hub ↔ promenade                      (Promenade.luau)
	  Map.Promenade    the ring walk along the lagoon                  (Promenade.luau)
	  Map.Gateways     4 themed plazas behind the bridge landings      (Gateways.luau)
	  Map.Landmarks    waterfall, windmill, giant tree, peaks          (Landmarks.luau)
	  Map.Lagoon       boats, buoys, lily pads, raft, sandbar          (Coast.luau)
	  Map.Ocean        decorated islets, shipwreck, rock arch, whale   (Coast.luau)
	  Map.Sky          voxel clouds                                    (Coast.luau)
	  Map.Nature       forests, palms, flowers, rocks on the hills     (Nature.luau)
	  Map.Boundaries   invisible ring wall in the ocean

	Part budget of the dressing (everything except Ground and Hub): DRESSING_BUDGET. Nature is
	built last and gets whatever the other modules left over.

	Coordinates: angle θ (degrees, 0 = +Z) and radius r map to (r·sin θ, y, r·cos θ).
]]

local U = require("./Util")
local Kit = require("./MapKit")
local buildHub = require("./Hub")
local buildGround = require("./Ground")
local Promenade = require("./Promenade")
local Gateways = require("./Gateways")
local Landmarks = require("./Landmarks")
local Coast = require("./Coast")
local Nature = require("./Nature")

local Vector3 = U.Vector3

local DRESSING_BUDGET = 4000 -- parts (base slots, bridges, promenade, gateways, landmarks, water, sky, nature, walls)
local LIGHT_BUDGET = 40 -- PointLights of the dressing

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

-- Parts and PointLights under a Map child (for the budget report).
local function stats(root: any): (number, number)
	local parts, lights = 0, 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
		elseif d:IsA("PointLight") then
			lights += 1
		end
	end
	return parts, lights
end

--------------------------------------------------------------------------------

return function(game: any, cfg: any, world: any)
	local workspace = game:GetService("Workspace")
	local map = U.new("Model", { Name = "Map" }, workspace)

	buildSlots(map, cfg)
	local ground = buildGround(map, world)
	local hub = buildHub(map, cfg, world)

	Kit.resetClaims()
	Promenade.buildBridges(map, cfg)
	local lamps = Promenade.buildPromenade(map, cfg, world)
	Gateways.build(map, cfg, world)
	Landmarks.build(map, cfg, world)
	Coast.build(map, cfg, world)
	buildBoundaries(map, cfg)

	-- Nature fills the rest of the budget.
	local used = 0
	for _, child in map:GetChildren() do
		if child.Name ~= "Ground" and child.Name ~= "Hub" then
			used += (stats(child))
		end
	end
	local natureCounts = Nature.build(map, cfg, world, DRESSING_BUDGET - used)

	-- Budget report (printed with the build stats).
	local report, totalParts, totalLights = {}, 0, 0
	for _, child in map:GetChildren() do
		if child.Name ~= "Ground" and child.Name ~= "Hub" then
			local p, l = stats(child)
			totalParts += p
			totalLights += l
			table.insert(report, `{child.Name} {p}` .. (if l > 0 then `/{l}L` else ""))
		end
	end
	print(`  map dressing: {totalParts} parts, {totalLights} lights ({table.concat(report, ", ")})`)
	if totalParts > DRESSING_BUDGET or totalLights > LIGHT_BUDGET then
		error(`map dressing over budget: {totalParts}/{DRESSING_BUDGET} parts, {totalLights}/{LIGHT_BUDGET} lights`)
	end

	return {
		map = map,
		groundParts = ground.parts,
		natureCounts = natureCounts,
		lamps = lamps,
		expectedAttachments = hub.expectedAttachments or {},
	}
end
