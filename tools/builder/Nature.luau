--[[
	Nature — voxel forests, groves and undergrowth on the ring hills (Map.Nature), within a part
	budget given by Map.luau (whatever the other dressing left over).

	Candidates sit on a jittered 17-stud grid over the land between the promenade and the outer
	coast. A candidate is skipped on reserved ground (world:isReserved with a margin — plots,
	promenade, gateways, paths, landmark sites), on areas claimed by the dressing modules
	(Kit.isClaimed), in water and on steep columns (world:slope).

	Every candidate gets a category and a score; each category has a share of the budget and
	takes its best-scoring candidates first, so the trees end up in dense, contiguous groves
	where they are seen most (instead of a thin even sprinkle):
	  forest   score = grove noise (~120-stud blobs) + visibility (the ridge behind the plots,
	           r 470..600, frames every view from the hub) + a little jitter for ragged edges.
	           Species by a second noise (~260-stud blobs): cherry groves (pink) | autumn woods
	           (orange) | mixed green woods (oak, round, birch, pine); a blossom grove on the
	           waterfall mesa. Near the play area trees are detailed (13-16 parts), on the ridge
	           they are big lite trees (8-10 parts, scale 2.1-2.9).
	  pines    the mountains, snow-dusted high up (their own share, so they do not crowd out
	           the woods)
	  palms    the outer beaches and the coast belt
	  meadow   bushes and flower beds in the open meadows next to paths and plazas, red
	           mushrooms at the foot of forest trees
	  rocks    mossy boulders on the rocky upper slopes
	Returns counts per kind (printed by tools/build.luau).
]]

local U = require("./Util")
local Kit = require("./MapKit")

local sqrt, deg, atan2, floor = math.sqrt, math.deg, math.atan2, math.floor

local Nature = {}

-- Estimated parts per placement (upper bounds of the Props catalogue).
local COST = {
	full = 16,
	lite = 10,
	palm = 16,
	palmLite = 10,
	bush = 7,
	flowers = 5,
	boulder = 6,
	mushroom = 7,
}

-- Share of the budget per category.
local SHARE = { forest = 0.61, pines = 0.15, palms = 0.09, meadow = 0.12, rocks = 0.03 }

local function smooth(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- How much a spot at radius r is seen from the play area (hub, bridges, promenade, bases).
local function visibility(r: number): number
	return 0.55 + 0.45 * smooth(380, 470, r) - 0.35 * smooth(600, 680, r)
end

function Nature.build(map: any, cfg: any, world: any, budget: number): { [string]: number }
	local nature = U.model(map, "Nature")
	local groups = {
		trees = U.model(nature, "Trees"),
		plants = U.model(nature, "Plants"),
		rocks = U.model(nature, "Rocks"),
	}
	local counts: { [string]: number } = {}
	local rng = Kit.rng(4242)
	local cell = 17
	local inner = cfg.PromenadeRadius + cfg.PromenadeWidth + 6
	local maxR = cfg.RingOuterRadius + 60

	-- the waterfall mesa top (seen from everywhere) gets a blossom grove instead of pines
	local fall = world.landmarks.Waterfall
	local function onMesa(x: number, z: number, h: number): boolean
		if not fall or h < fall.cliffTop - 16 then
			return false
		end
		local lx, lz = world.radialLocal(x, z, fall.angle, fall.radius)
		return lz > 6 and lz < fall.depth - 10 and math.abs(lx) < fall.halfWidth - 4
	end

	-- Pass 1: candidates by category
	local lists = { forest = {}, pines = {}, palms = {}, meadow = {}, rocks = {} }
	for gz = -maxR, maxR, cell do
		for gx = -maxR, maxR, cell do
			local x = gx + rng(-5, 5)
			local z = gz + rng(-5, 5)
			local jitter, roll, roll2 = rng(), rng(), rng()
			local r = sqrt(x * x + z * z)
			if r < inner or r > maxR then
				continue
			end
			local h, kind, water = world:surfaceAt(x, z)
			if water or world:isReserved(x, z, 5) or Kit.isClaimed(x, z, 3) or world:slope(x, z) > 4 then
				continue
			end
			local theta = deg(atan2(x, z)) % 360
			local toCoast = world:coastRadius(theta) - r
			local grove = world:noise(x / 120 + 70, z / 120 - 30)
			local biome = world:noise(x / 260 + 13, z / 260 + 41)
			local vis = visibility(r)
			local e: { [string]: any } = { x = x, z = z, h = h, r = r }

			if kind == "sand" then
				if r > 500 then
					e.kind, e.lite = "palm", r > 560
					e.cost = if e.lite then COST.palmLite else COST.palm
					e.score = vis + jitter
					table.insert(lists.palms, e)
				end
			elseif kind == "stone" or kind == "snow" then
				-- bare mountain: snowy pines (they rank below the greener slopes)
				e.kind, e.lite, e.snow, e.cost = "pine", true, true, COST.lite
				e.score = grove + 0.4 * jitter - 0.2
				table.insert(lists.pines, e)
			elseif toCoast < 40 and h <= 12 then
				e.kind, e.lite = "palm", r > 560
				e.cost = if e.lite then COST.palmLite else COST.palm
				e.score = vis + jitter - 0.3
				table.insert(lists.palms, e)
			else
				-- forest tree (species decided now, placement by score later)
				local species
				local mesa = onMesa(x, z, h)
				if mesa then
					species = if roll < 0.75 then "cherry" else "birch" -- a blossom grove on the mesa
				elseif h >= 44 then
					species = "pine"
				elseif biome > 0.24 then
					species = if roll < 0.8 then "cherry" else "birch"
				elseif biome < -0.24 then
					species = if roll < 0.7 then "autumn" elseif roll < 0.85 then "oak" else "pine"
				else
					species = if roll < 0.42
						then "oak"
						elseif roll < 0.6 then "round"
						elseif roll < 0.76 then "birch"
						else "pine"
				end
				local lite = r > 470 or (h >= 44 and not mesa)
				table.insert(if h >= 44 and not mesa then lists.pines else lists.forest, {
					x = x,
					z = z,
					kind = species,
					lite = lite,
					snow = h >= 76,
					cost = if lite then COST.lite else COST.full,
					score = grove + 0.55 * vis + 0.3 * jitter + (if mesa then 0.5 else 0),
				})
				-- open meadows: bushes and flowers (best near the paths and plazas: r small)
				if grove < -0.05 then
					local flowers = roll2 < 0.55
					table.insert(lists.meadow, {
						x = x,
						z = z,
						kind = if flowers then "flowers" else "bush",
						cost = if flowers then COST.flowers else COST.bush,
						score = -grove + (1 - smooth(340, 520, r)) + 0.3 * jitter,
					})
				end
				-- a red mushroom at the foot of some forest trees
				if grove > 0.15 and roll2 > 0.88 then
					table.insert(lists.meadow, {
						x = x + 4.5,
						z = z + 3.5,
						kind = "mushroom",
						cost = COST.mushroom,
						score = grove + 0.75 + 0.3 * jitter,
					})
				end
				if kind == "grassRock" and roll2 < 0.3 then
					table.insert(lists.rocks, {
						x = x,
						z = z,
						kind = "boulder",
						cost = COST.boulder,
						score = jitter + 0.5,
					})
				end
			end
		end
	end

	-- Pass 2: per category, best scores first, until its share of the budget is spent
	local thin = Kit.rng(9001)
	local partsBefore = U.partCount
	local taken: { { number } } = {}
	local function free(x: number, z: number, d: number): boolean
		for _, t in taken do
			local dx, dz = x - t[1], z - t[2]
			if dx * dx + dz * dz < d * d then
				return false
			end
		end
		return true
	end
	local function place(e: { [string]: any })
		local cf = Kit.ground(world, e.x, e.z, 0) -- props add quarter turns: forests stay on the grid
		local seed = floor(thin(1, 1e6))
		local scale = if e.lite then thin(2.1, 2.9) else thin(1.3, 1.75)
		local k = e.kind
		if k == "pine" then
			Kit.prop("pineTree", groups.trees, cf, {
				seed = seed,
				scale = scale,
				lite = e.lite,
				snow = e.snow,
				variant = if e.snow then 1 else nil,
			})
		elseif k == "oak" then
			Kit.prop("oakTree", groups.trees, cf, { seed = seed, scale = scale, lite = e.lite })
		elseif k == "round" then
			Kit.prop("roundTree", groups.trees, cf, { seed = seed, scale = scale, lite = e.lite, palette = "mixed" })
		elseif k == "birch" then
			Kit.prop("birchTree", groups.trees, cf, { seed = seed, scale = scale, lite = e.lite })
		elseif k == "cherry" then
			Kit.prop("cherryTree", groups.trees, cf, { seed = seed, scale = scale, lite = e.lite })
		elseif k == "autumn" then
			Kit.prop("autumnTree", groups.trees, cf, { seed = seed, scale = scale, lite = e.lite })
		elseif k == "palm" then
			Kit.prop("palmTree", groups.trees, cf, { seed = seed, scale = thin(1.3, 1.7), lite = e.lite })
		elseif k == "bush" then
			Kit.prop("bush", groups.plants, cf, { seed = seed, scale = thin(1.5, 2.3) })
		elseif k == "flowers" then
			Kit.flowerMeadow(groups.plants, cf, seed)
		elseif k == "mushroom" then
			Kit.prop("mushroom", groups.plants, cf, { seed = seed, scale = thin(1.4, 1.9) })
		elseif k == "boulder" then
			Kit.prop("boulder", groups.rocks, cf, { seed = seed, moss = thin() < 0.5 })
		end
		counts[k] = (counts[k] or 0) + 1
	end
	for _, name in { "forest", "pines", "palms", "meadow", "rocks" } do
		local list = lists[name]
		table.sort(list, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.x + a.z * 1e-3 < b.x + b.z * 1e-3
		end)
		local quota = budget * SHARE[name]
		local spent = 0
		local spacing = if name == "palms" then 14 elseif name == "forest" or name == "pines" then 0 else 9
		for _, e in list do
			if spent + e.cost > quota or U.partCount - partsBefore + e.cost > budget then
				continue
			end
			if spacing > 0 and not free(e.x, e.z, if e.kind == "mushroom" then 3 else spacing) then
				continue
			end
			local before = U.partCount
			place(e)
			spent += U.partCount - before
			table.insert(taken, { e.x, e.z })
		end
	end
	return counts
end

return Nature
