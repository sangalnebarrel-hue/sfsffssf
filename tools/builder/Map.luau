--[[
	Builds Workspace.Map — everything made of parts in World v3 «Остров Рыбаков»
	(see tools/builder/DESIGN.md). The ground comes from VoxelWorld (heightfield) via Ground.luau;
	the water is Terrain (baked separately in tools/build.luau). This module assembles:
	  Map.BaseSlots    8 invisible markers where the server clones the base template
	  Map.Ground       voxel ground (Ground.luau)
	  Map.Hub          the central island village (Hub.luau)
	  Map.Bridges      4 bridges hub ↔ promenade, a sell kiosk on      (Promenade.luau)
	                   each mid-span lookout
	  Map.Promenade    the ring walk along the lagoon                  (Promenade.luau)
	  Map.Gateways     4 themed plazas behind the bridge landings      (Gateways.luau)
	  Map.Landmarks    waterfall, windmill, giant tree, peaks          (Landmarks.luau)
	  Map.Lagoon       boats, buoys, lily pads, raft, swim platform,   (Coast.luau)
	                   sandbars
	  Map.Ocean        decorated islets, shipwreck, rock arch, whale   (Coast.luau)
	  Map.Sky          voxel clouds                                    (Coast.luau)
	  Map.Nature       forests, tree belts, palms, flowers, rocks,     (Nature.luau)
	                   set-pieces on the hills, coral reefs in the lagoon
	  Map.Boundaries   invisible ring wall in the ocean

	Part budget of the dressing (everything except Ground and Hub): DRESSING_BUDGET parts and
	LIGHT_BUDGET PointLights. Nature is built last (it keeps off what the others built) and gets
	whatever the other modules left over, but never less than NATURE_MIN: the build fails when the
	other modules leave less, and when the dressing as a whole goes over budget.

	Every part of the map ends up Locked (Studio clicks cannot move generated parts). Returns
	expectedAttachments for the build's self-check: the hub shops' and the bridge kiosks' prompt
	attachments.

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
local Props = require("./Props")

local Vector3 = U.Vector3

local DRESSING_BUDGET = 6300 -- parts (base slots, bridges, promenade, gateways, landmarks, water, sky, nature, walls)
local LIGHT_BUDGET = 40 -- PointLights of the dressing
local NATURE_MIN = 2500 -- parts Nature is guaranteed (the hills must look lush)

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
	local count = 24
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
	local kioskAttachments = Promenade.buildBridges(map, cfg, world)
	local lamps = Promenade.buildPromenade(map, cfg, world)
	Gateways.build(map, cfg, world)
	Landmarks.build(map, cfg, world)
	Coast.build(map, cfg, world)
	buildBoundaries(map, cfg)

	-- Nature fills the rest of the budget (at least NATURE_MIN).
	local used = 0
	local usedBy = {}
	for _, child in map:GetChildren() do
		if child.Name ~= "Ground" and child.Name ~= "Hub" then
			local p = stats(child)
			used += p
			table.insert(usedBy, `{child.Name} {p}`)
		end
	end
	-- (10 spare: Nature fills its budget up to the last few parts)
	if DRESSING_BUDGET - used < NATURE_MIN + 10 then
		local list = table.concat(usedBy, ", ")
		error(`map dressing leaves Nature {DRESSING_BUDGET - used} parts (< {NATURE_MIN} + 10); used: {list}`)
	end
	-- Props drop small details (fallen leaves, litter) only where the ground really is.
	Props.groundAt = function(x: number, z: number): number
		return world:heightAt(x, z)
	end
	local natureCounts = Nature.build(map, cfg, world, DRESSING_BUDGET - used)
	Props.groundAt = nil

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
	local natureParts = stats(map.Nature)
	print(`  map dressing: {totalParts} parts, {totalLights} lights ({table.concat(report, ", ")})`)
	-- (the headroom the other dressing still has before Nature would fall under its minimum)
	print(`  dressing headroom: {natureParts - NATURE_MIN - 10} parts (Nature {natureParts} / min {NATURE_MIN})`)
	if totalParts > DRESSING_BUDGET or totalLights > LIGHT_BUDGET then
		error(`map dressing over budget: {totalParts}/{DRESSING_BUDGET} parts, {totalLights}/{LIGHT_BUDGET} lights`)
	end
	if natureParts < NATURE_MIN then
		error(`Nature got only {natureParts} parts (< {NATURE_MIN})`)
	end

	-- The generator owns every part of the map: lock them all, so a stray click-drag in Studio
	-- cannot move one (the client's Spin / Bob animation is unaffected).
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") then
			d.Locked = true
		end
	end

	-- attachments the server binds prompts to (checked by the build's self-check): the hub's
	-- shops and the sell kiosks on the bridges
	local expected = table.clone(hub.expectedAttachments or {})
	for _, item in kioskAttachments or {} do
		table.insert(expected, item)
	end

	return {
		map = map,
		groundParts = ground.parts,
		natureCounts = natureCounts,
		budget = { dressing = DRESSING_BUDGET, lights = LIGHT_BUDGET, natureMin = NATURE_MIN },
		lamps = lamps,
		expectedAttachments = expected,
	}
end
