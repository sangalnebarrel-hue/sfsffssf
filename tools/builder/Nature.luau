--[[
	Nature — voxel forests, groves, palms, undergrowth and rocks on the ring hills, the
	mountains and the outer beaches (Map.Nature), within the part budget Map.luau gives it
	(whatever the other dressing left over; Map.luau guarantees a minimum).

	Every spot is checked against the voxel ground: no reserved ground (world:isReserved —
	plots, promenade, gateways, paths, the peak trail and summit, landmark sites), no "path"
	columns under the footprint, no areas claimed by the dressing modules (Kit.isClaimed), no
	water, and the whole trunk / bush / rock footprint stands on one flat column top (nothing
	overhangs a terrace step). Objects keep their distance: two trees at least 0.9 × (sum of
	canopy radii) apart (1.0 between different kinds: no trunk ever pokes through a neighbour's
	canopy), small things clear of trunks and of each other.

	Passes, each with its share of the budget (unspent parts carry over to the next one):
	  coast   clusters of 2-3 palms (cheap far palms, a Props lite one in every other cluster)
	          every ~70 studs of the outer beaches, beach props between them (parasol with a
	          towel, sandcastle, starfish), warm light rocks with grassy caps at the water's
	          edge, rocks in the surf below the cliffs
	  pines   up to 16 pines on each mountain's flanks and grassRock band, snow-dusted higher up
	  groves  dense groves of 5-9 trees (grove centres ~80 studs apart, taken round-robin over
	          the 16 sectors of 22.5° so every hill sector gets its woods, most visible first);
	          one family per grove by height and a ~260-stud biome noise: cherry (pink),
	          autumn (orange / gold), mixed green (oak, round, birch, pine), pines up high, a
	          blossom grove on the waterfall mesa
	  decor   small cheap colour where people walk: flower clusters (a leafy tuft and 3-5
	          flowers on stems), bushes and rock groups along both sides of the radial paths,
	          round the plots, the gateway plazas and the landmark sites; flower meadows on the
	          waterfall mesa and in the giant tree's meadow
	  lips    bushes, flower clumps and small rocks along the terrace edges that face the
	          promenade (the slopes everybody looks at)
	  rocks   mossy boulders and rock clusters on the rocky upper slopes
	  fill    single trees / bushes / rocks wherever a hill spot is still > 36 studs from
	          anything, then more groves, then flower clusters on open lawns with what is left
	Level of detail by distance to the play area (plots, promenade, gateways, paths): full Props
	trees (13-16 parts) within ~26 studs, Props lite trees (8-10) within ~60, beyond that the
	cheap 5-part trees built here (Nature.farTree; Coast.luau uses them on the islets too), at
	most FAR_CAP of them: the far hills keep their woods while the parts go to detail people
	see up close. The biggest canopy block of every tree casts a shadow; small foliage does not.
	Returns counts per kind (printed by tools/build.luau).
]]

local U = require("./Util")
local Kit = require("./MapKit")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local C = Kit.C

local sqrt, deg, atan2, floor, abs, min, max = math.sqrt, math.deg, math.atan2, math.floor, math.abs, math.min, math.max
local sin, cos, rad = math.sin, math.cos, math.rad

local Nature = {}

-- Share of the budget per pass (the rest of a pass's share carries over).
local SHARE = { coast = 0.2, pines = 0.09, groves = 0.26, decor = 0.19, lips = 0.05, rocks = 0.04, fill = 0.17 }
-- Most cheap 5-part far trees on the island (the far hills are seen through the haze).
local FAR_CAP = 100

local FOLIAGE = Kit.DECOR
local BEACH_ROCK = Kit.lerpColor(C.StoneLight, C.SandDark, 0.4) -- warm light rocks on the sand
local CANOPY = { CanCollide = false, CanQuery = false, CastShadow = true } -- the one shadow block

-- Leaf palettes {dark, mid, light}: deeper greens than the lime grass so woods read as woods,
-- but bright and warm (hue ~120-125°, no blue-green slabs on the far hills).
local GREEN = { U.rgb(56, 164, 70), U.rgb(78, 188, 80), U.rgb(114, 214, 96) }
local BUSH = { U.rgb(46, 150, 66), GREEN[2], GREEN[3] }
local PAL = {
	green = GREEN,
	lime = { GREEN[2], GREEN[3], C.Lime },
	cherry = { C.Blossom0, C.Blossom1, C.Blossom2 },
	autumn = { C.Autumn0, C.Autumn1, C.Autumn2 },
	gold = { C.Autumn1, C.Autumn2, C.Yellow },
	palm = { C.Palm1, C.Palm2, C.Palm3 },
}

-- Canopy half-width (studs at scale 1, incl. the Props size jitter) per tree kind.
local CANOPY_R = {
	oak = 6.2,
	round = 6.2,
	cherry = 6.8,
	autumn = 6.0,
	birch = 4.5,
	pine = 5.6,
	palm = 7.4,
	far = 6.0,
	farPine = 5.0,
	farPalm = 5.2,
}
-- Trunk half-width (studs at scale 1, incl. jitter and roots).
local TRUNK_R = { full = 2.6, lite = 1.6, far = 1.4 }

local function smooth(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

--------------------------------------------------------------------------------------------
-- Cheap far trees (5 parts) and the flower clump
--------------------------------------------------------------------------------------------

--[[
	Nature.farTree(parent, cf, kind, scale, seed): a 5-part voxel tree for far hills and islets
	(the silhouettes of the Props trees with fewer blocks).
	  "green" | "lime" | "cherry" | "autumn" | "gold"  trunk and a three-step pyramid: a wide
	                                                   dark base, a mid "plus" of two blocks
	                                                   (the shadow caster), a small light top
	  "pine" | "snowPine"   trunk, a stepped cone of three tiers (dark to light) and a tip
	  "palm"                two bent trunk segments, crown, two crossed fronds
	cf stands on the ground (front -Z). Model pivot = cf.
]]
function Nature.farTree(parent: any, cf: any, kind: string, s: number, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "FarTree", cf * CFrame.Angles(0, rad(90 * floor(r(0, 3.99))), 0))
	local function box(name: string, x0, y0, z0, x1, y1, z1, color, extra)
		return b:box(name, x0 * s, y0 * s, z0 * s, x1 * s, y1 * s, z1 * s, color, extra)
	end
	local trunk
	if kind == "pine" or kind == "snowPine" then
		-- a stepped cone: three tiers getting narrower and lighter, a small tip
		local snow = kind == "snowPine"
		local w = r(8.6, 9.8)
		trunk = box("Trunk", -0.8, -1 / s, -0.8, 0.8, 4, 0.8, C.Bark)
		local skirt = if snow then Kit.lerpColor(C.Snow, C.Glass, 0.15) else C.Pine1
		box("Tier1", -w / 2, 2.4, -w / 2, w / 2, 6.2, w / 2, skirt, CANOPY)
		local w2 = w * 0.68
		box("Tier2", -w2 / 2, 6.0, -w2 / 2, w2 / 2, 9.8, w2 / 2, if snow then C.Pine1 else C.Pine2, FOLIAGE)
		local w3 = w * 0.4
		box("Tier3", -w3 / 2, 9.6, -w3 / 2, w3 / 2, 13.0, w3 / 2, if snow then skirt else C.Pine3, FOLIAGE)
		local w4 = w * 0.16
		box("Tip", -w4 / 2, 12.8, -w4 / 2, w4 / 2, 14.6, w4 / 2, if snow then C.Snow else C.PineLight, FOLIAGE)
	elseif kind == "palm" then
		local lean = r(1.2, 2.0)
		trunk = box("Trunk1", -1.0, -1 / s, -1.0, 1.0, 5.6, 1.0, C.PalmBark)
		box("Trunk2", lean - 0.8, 5.5, -0.8, lean + 0.8, 10.4, 0.8, C.PalmBarkDark)
		box("Crown", lean - 1.4, 9.6, -1.4, lean + 1.4, 11.4, 1.4, C.Palm1, FOLIAGE)
		local L = r(4.6, 5.2)
		box("FrondX", lean - L, 10.9, -1.1, lean + L, 11.9, 1.1, C.Palm2, CANOPY)
		box("FrondZ", lean - 1.1, 10.7, -L, lean + 1.1, 11.7, L, C.Palm3, FOLIAGE)
	else
		local pal = PAL[kind] or PAL.green
		local R = r(5.0, 5.8)
		local th = r(4.6, 5.4)
		trunk = box("Trunk", -1.2, -1 / s, -1.2, 1.2, th + 2, 1.2, if kind == "cherry" then C.BarkDark else C.Bark)
		-- a stepped pyramid (widths ~ 1 : 0.76 : 0.38); every side face of one block stays
		-- >= 0.3 stud from its neighbours' (no z-fight)
		local lw = R * 0.95
		box("CanopyLow", -lw, th, -lw, lw, th + 3.4, lw, pal[1], FOLIAGE)
		local ox, oz = r(-0.3, 0.3), r(-0.3, 0.3)
		local a, c = R * 0.74, R * 0.5
		box("Canopy", ox - a, th + 3.0, oz - c, ox + a, th + 6.6, oz + c, pal[2], CANOPY)
		box("CanopyB", ox - c, th + 2.96, oz - a, ox + c, th + 6.64, oz + a, pal[2], CANOPY)
		local tw = R * 0.38
		local tx, tz = ox + r(-0.2, 0.2), oz + r(-0.2, 0.2)
		box("CanopyTop", tx - tw, th + 6.3, tz - tw, tx + tw, th + 9.4, tz + tw, pal[3], FOLIAGE)
	end
	return b:finish(trunk)
end

-- Flower clump (5 parts): a leafy tuft with two tall flowers on stems, two colours.
local function flowerClump(parent: any, cf: any, s: number, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "Flowers", cf * CFrame.Angles(0, rad(90 * floor(r(0, 3.99))), 0))
	local tuft = b:box("Tuft", -1.9 * s, -0.3, -1.6 * s, 1.9 * s, 1.1 * s, 1.6 * s, BUSH[2], FOLIAGE)
	local first = floor(r(1, #C.Flowers + 0.99))
	for i, spot in { { -0.8, -0.4, 2.6 }, { 0.9, 0.5, 3.3 } } do
		local x, z, h = spot[1] * s, spot[2] * s, spot[3] * s
		b:box(`Stem{i}`, x - 0.3, 1.0 * s, z - 0.3, x + 0.3, h, z + 0.3, BUSH[1], FOLIAGE)
		local colour = C.Flowers[(first + (i - 1) * 2 - 1) % #C.Flowers + 1]
		local w = 1.0 * s
		b:box(`Bloom{i}`, x - w, h - 0.1, z - w, x + w, h + 1.5 * s, z + w, colour, FOLIAGE)
	end
	return b:finish(tuft)
end

-- Bright bloom colours for the flower clusters (no white: it reads as sugar lumps).
local BLOOMS = { C.Red, C.Yellow, C.Pink, C.Purple, C.Orange, C.Blue }

--[[
	Flower cluster (1 + 2 per flower parts): a leafy tuft in the middle and n flowers (a stem
	and a 1.4-1.7 stud bloom) round it in one or two colours. ok(x, z) says whether a flower
	may stand at that world point (the same flat column, no path); spots that fail are skipped.
]]
local function flowerCluster(parent: any, cf: any, n: number, seed: number, ok: (number, number) -> boolean): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "FlowerCluster", cf)
	local tw = r(1.5, 2.0)
	local tuft = b:box("Tuft", -tw, -0.3, -tw * 0.8, tw, r(0.8, 1.2), tw * 0.8, BUSH[2], FOLIAGE)
	local c1 = BLOOMS[floor(r(1, #BLOOMS + 0.99))]
	local c2 = if r() < 0.5 then c1 else BLOOMS[floor(r(1, #BLOOMS + 0.99))]
	local a0 = r(0, 360)
	local k = 0
	for i = 1, n + 2 do
		if k >= n then
			break
		end
		local a = rad(a0 + i * 360 / (n + 1) + r(-15, 15))
		local d = r(2.6, 4.2)
		local x, z = d * sin(a), d * cos(a)
		local p = cf * Vector3.new(x, 0, z)
		if ok(p.X, p.Z) then
			k += 1
			local h = r(1.3, 2.6)
			b:box(`Stem{k}`, x - 0.25, -0.1, z - 0.25, x + 0.25, h, z + 0.25, BUSH[1], FOLIAGE)
			local w = r(0.7, 0.85)
			b:box(
				`Bloom{k}`,
				x - w,
				h - 0.2,
				z - w,
				x + w,
				h - 0.2 + 2 * w,
				z + w,
				if k % 2 == 0 then c2 else c1,
				FOLIAGE
			)
		end
	end
	return b:finish(tuft)
end

-- Beach props: a parasol with a towel (4 parts), a sandcastle with a flag (4), a starfish (2).
local function beachProp(parent: any, cf: any, kind: string, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "BeachProp", cf * CFrame.Angles(0, rad(r(0, 360)), 0))
	local first
	if kind == "parasol" then
		local cols = { { C.Red, C.Cyan }, { C.Blue, C.Yellow }, { C.Pink, C.Lime }, { C.Orange, C.Blue } }
		local pair = cols[floor(r(1, #cols + 0.99))]
		first = b:pole("Pole", 0.5, 0, 0, -0.6, 7.0, C.White, Kit.NOSHADOW)
		b:box("Canopy", -3.4, 6.3, -3.4, 3.4, 7.2, 3.4, pair[1])
		b:box("CanopyTop", -1.7, 7.15, -1.7, 1.7, 7.9, 1.7, C.White, Kit.NOSHADOW)
		b:box("Towel", 1.0, 0, -1.4, 3.6, 0.16, 4.0, pair[2], FOLIAGE)
	elseif kind == "sandcastle" then
		local wet = Kit.lerpColor(C.SandDark, C.Wood, 0.15)
		first = b:box("Base", -2.2, -0.3, -2.2, 2.2, 1.4, 2.2, wet)
		b:box("Tower", -1.2, 1.4, -1.2, 1.2, 3.4, 1.2, Kit.lerpColor(C.Sand, C.White, 0.3))
		b:box("Turret", -0.6, 3.4, -0.6, 0.6, 4.4, 0.6, wet)
		b:box("Flag", 0.6, 3.7, -0.1, 1.7, 4.4, 0.1, C.Red, FOLIAGE)
	else
		local col = if r() < 0.5 then C.Pink else C.Orange
		first = b:box("ArmA", -1.3, 0, -0.4, 1.3, 0.3, 0.4, col, FOLIAGE)
		b:box("ArmB", -0.4, 0.02, -1.3, 0.4, 0.32, 1.3, col, FOLIAGE)
	end
	return b:finish(first)
end

--------------------------------------------------------------------------------------------
-- Placement helpers
--------------------------------------------------------------------------------------------

-- Spatial hash of the placed objects.
local HASH = 32
local function hashKey(x: number, z: number): number
	return (floor(x / HASH) + 200) * 1000 + floor(z / HASH) + 200
end

function Nature.build(map: any, cfg: any, world: any, budget: number): { [string]: number }
	local nature = U.model(map, "Nature")
	local groups = {
		trees = U.model(nature, "Trees"),
		plants = U.model(nature, "Plants"),
		rocks = U.model(nature, "Rocks"),
	}
	local counts: { [string]: number } = {}
	local G = cfg.GroundTop
	local inner = cfg.PromenadeRadius + cfg.PromenadeWidth + 6
	local maxR = cfg.RingOuterRadius + 70
	local partsBefore = U.partCount
	local function spentAll(): number
		return U.partCount - partsBefore
	end

	-- placed objects: { x, z, canopy (trees) or 0, rad (footprint), fam }
	local placed: { [number]: { { any } } } = {}
	local function addPlaced(x: number, z: number, canopy: number, radius: number, fam: string)
		local k = hashKey(x, z)
		placed[k] = placed[k] or {}
		table.insert(placed[k], { x, z, canopy, radius, fam })
	end
	-- Can an object (canopy radius `canopy` for a tree, 0 otherwise; footprint `radius`) stand
	-- at (x, z)?
	local function fits(x: number, z: number, canopy: number, radius: number, fam: string): boolean
		local reach = max(canopy, radius) + 40
		local n = math.ceil(reach / HASH)
		local cx, cz = floor(x / HASH), floor(z / HASH)
		for ix = cx - n, cx + n do
			for iz = cz - n, cz + n do
				local list = placed[(ix + 200) * 1000 + iz + 200]
				if list then
					for _, o in list do
						local dx, dz = x - o[1], z - o[2]
						local d = sqrt(dx * dx + dz * dz)
						local need
						if canopy > 0 and o[3] > 0 then
							-- palms may cross fronds; other trees only touch within a grove
							local k = if fam ~= o[5] then 1.0 elseif fam == "palm" then 0.42 else 0.9
							need = k * (canopy + o[3])
						elseif canopy > 0 then
							need = 0.5 * canopy + o[4]
						elseif o[3] > 0 then
							need = 0.5 * o[3] + radius
						else
							need = radius + o[4]
						end
						if d < need then
							return false
						end
					end
				end
			end
		end
		return true
	end
	-- Distance from (x, z) to the nearest placed object (capped at `cap`).
	local function nearest(x: number, z: number, cap: number): number
		local best = cap
		local n = math.ceil(cap / HASH)
		local cx, cz = floor(x / HASH), floor(z / HASH)
		for ix = cx - n, cx + n do
			for iz = cz - n, cz + n do
				local list = placed[(ix + 200) * 1000 + iz + 200]
				if list then
					for _, o in list do
						local dx, dz = x - o[1], z - o[2]
						best = min(best, sqrt(dx * dx + dz * dz))
					end
				end
			end
		end
		return best
	end

	-- The ground under a footprint of half-width `half` round (x, z) is one dry column top h.
	local function flatAt(x: number, z: number, half: number): number?
		local h, _, water = world:surfaceAt(x, z)
		if water then
			return nil
		end
		for _, d in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
			if world:heightAt(x + d[1] * half, z + d[2] * half) ~= h then
				return nil
			end
		end
		return h
	end
	-- No "path" column (radial paths, the peak trail) under the footprint of half-width `half`.
	local function offPath(x: number, z: number, half: number): boolean
		if world:kindAt(x, z) == "path" then
			return false
		end
		for _, d in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } } do
			if world:kindAt(x + d[1] * half, z + d[2] * half) == "path" then
				return false
			end
		end
		return true
	end
	-- Free land: not reserved, not claimed (canopy may not reach into a claimed area either),
	-- no path under the object or its canopy's inner half.
	local function freeLand(x: number, z: number, reach: number): boolean
		return not world:isReserved(x, z, max(5, reach * 0.6))
			and not Kit.isClaimed(x, z, max(3, reach * 0.7))
			and offPath(x, z, max(3, reach * 0.5))
	end

	-- Detail level by distance to the play area: "full" | "lite" | "far".
	local function detail(x: number, z: number): string
		if world:isReserved(x, z, 26) then
			return "full"
		elseif world:isReserved(x, z, 60) then
			return "lite"
		end
		return "far"
	end

	-- Moves fallen leaves / petals of a Props tree onto the ground under each piece (they are
	-- laid out for flat ground); a piece over a step or water is dropped.
	local function settleLitter(model: any)
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and string.sub(p.Name, 1, 6) == "Litter" then
				local pos = p.CFrame.Position
				local h = flatAt(pos.X, pos.Z, p.Size.X / 2)
				if h then
					p.CFrame = CFrame.new(pos.X, h + p.Size.Y / 2 + 0.02, pos.Z) * p.CFrame.Rotation
				else
					p:Destroy()
				end
			end
		end
	end
	-- The biggest canopy blocks cast the tree's shadow.
	local SHADOW_PARTS = { Canopy = true, CanopyB = true, Skirt1 = true, Skirt1B = true, FrondX = true, FrondZ = true }
	local function shadows(model: any)
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and SHADOW_PARTS[p.Name] then
				p.CastShadow = true
			end
		end
	end

	-- Upper bound of the parts one placement may take (never overshoot the budget).
	local COST =
		{ full = 16, lite = 10, far = 5, bush = 7, flowers = 5, rock = 4, boulder = 6, cluster = 11, meadow = 5 }
	local farTrees = 0
	local function affordable(n: number): boolean
		return spentAll() + n <= budget
	end

	local seedRng = Kit.rng(9001)
	local function count(k: string)
		counts[k] = (counts[k] or 0) + 1
	end

	-- Places a tree of `kind` ("oak" | "round" | "birch" | "cherry" | "autumn" | "gold" |
	-- "pine" | "snowPine" | "palm") at (x, z) if it fits; `level` = "full" | "lite" | "far".
	-- Returns the parts spent (0 = not placed).
	local function tree(x: number, z: number, kind: string, level: string, fam: string): number
		local s
		if level == "full" then
			s = seedRng(1.35, 1.7)
		elseif level == "lite" then
			s = seedRng(1.9, 2.4)
		else
			s = seedRng(2.0, 2.6)
		end
		local seed = floor(seedRng(1, 1e6))
		local pine = kind == "pine" or kind == "snowPine"
		local canopy
		if level == "far" then
			canopy = (if pine then CANOPY_R.farPine elseif kind == "palm" then CANOPY_R.farPalm else CANOPY_R.far) * s
		else
			local base = if kind == "snowPine" then "pine" elseif kind == "gold" then "autumn" else kind
			canopy = (CANOPY_R[base] or 6.2) * s * (if level == "full" and not pine then 1.15 else 1)
		end
		if level == "far" and kind ~= "palm" and farTrees >= FAR_CAP then
			return 0
		end
		if not affordable(COST[level]) or not freeLand(x, z, canopy) then
			return 0
		end
		local h = flatAt(x, z, TRUNK_R[level] * s)
		if not h or not fits(x, z, canopy, 0, fam) then
			return 0
		end
		local before = U.partCount
		local cf = CFrame.new(x, h, z) -- props add quarter turns: forests stay on the grid
		if level == "far" then
			Nature.farTree(
				groups.trees,
				cf,
				if kind == "oak" or kind == "round" or kind == "birch" then "green" else kind,
				s,
				seed
			)
		else
			local lite = level == "lite"
			local m
			if pine then
				m = Kit.prop(
					"pineTree",
					groups.trees,
					cf,
					{ seed = seed, scale = s, lite = lite, snow = kind == "snowPine" }
				)
			elseif kind == "oak" then
				m = Kit.prop("oakTree", groups.trees, cf, { seed = seed, scale = s, lite = lite })
			elseif kind == "round" then
				m = Kit.prop("roundTree", groups.trees, cf, { seed = seed, scale = s, lite = lite, palette = "mixed" })
			elseif kind == "birch" then
				m = Kit.prop("birchTree", groups.trees, cf, { seed = seed, scale = s, lite = lite })
			elseif kind == "cherry" then
				m = Kit.prop("cherryTree", groups.trees, cf, { seed = seed, scale = s, lite = lite })
			elseif kind == "gold" then
				m = Kit.prop("autumnTree", groups.trees, cf, { seed = seed, scale = s, lite = lite, leaves = PAL.gold })
			elseif kind == "palm" then
				m = Kit.prop("palmTree", groups.trees, cf, { seed = seed, scale = s * 0.85, lite = lite })
			else
				m = Kit.prop("autumnTree", groups.trees, cf, { seed = seed, scale = s, lite = lite })
			end
			settleLitter(m)
			shadows(m)
		end
		addPlaced(x, z, canopy, 0, fam)
		count(kind)
		if level == "far" then
			count("far")
			if kind ~= "palm" then
				farTrees += 1
			end
		end
		return U.partCount - before
	end

	-- Small things: "bush" | "flowers" | "cluster" | "meadow" | "rock" | "boulder" (footprint
	-- radius by kind and size). opts: scale, gap (extra clearance), margin (distance kept from
	-- reserved ground; default by size, small decor may hug the paths and plots), count (rock
	-- blocks / cluster flowers), moss, snow, color (rocks), berries (bushes).
	local function small(x: number, z: number, kind: string, opts: { [string]: any }?): number
		local o = opts or {}
		local seed = floor(seedRng(1, 1e6))
		local s = o.scale or 1
		local radius = if kind == "bush"
			then 2.6 * s
			elseif kind == "flowers" then 2.2 * s
			elseif kind == "cluster" then 4.6
			elseif kind == "meadow" then 6.6
			elseif kind == "boulder" then 5.6 * s
			else 2.8 * s
		if not affordable(COST[kind]) then
			return 0
		end
		local margin = o.margin or max(5, radius * 0.6)
		local claimMargin = if kind == "cluster" or kind == "meadow" then 1.5 else max(3, radius * 0.7)
		if world:isReserved(x, z, margin) or Kit.isClaimed(x, z, claimMargin) or not offPath(x, z, radius) then
			return 0
		end
		-- (a cluster's flowers check their own columns: only its tuft needs flat ground)
		local h = flatAt(x, z, if kind == "cluster" then 2.2 else radius * 0.9)
		if not h or not fits(x, z, 0, radius + (o.gap or 1), kind) then
			return 0
		end
		local before = U.partCount
		local cf = CFrame.new(x, h, z)
		if kind == "bush" then
			Kit.prop("bush", groups.plants, cf, { seed = seed, scale = s, berries = o.berries, leaves = BUSH })
		elseif kind == "flowers" then
			flowerClump(groups.plants, cf, s, seed)
		elseif kind == "cluster" then
			flowerCluster(groups.plants, cf, o.count or 4, seed, function(px: number, pz: number): boolean
				return world:heightAt(px, pz) == h
					and world:kindAt(px, pz) ~= "path"
					and not world:isReserved(px, pz, 0.5)
			end)
		elseif kind == "meadow" then
			Kit.flowerMeadow(groups.plants, cf, seed)
		elseif kind == "boulder" then
			Kit.prop(
				"boulder",
				groups.rocks,
				cf,
				{ seed = seed, scale = s, moss = o.moss, snow = o.snow, color = o.color }
			)
		else
			Kit.prop(
				"rock",
				groups.rocks,
				cf,
				{ seed = seed, scale = s, count = o.count, moss = o.moss, snow = o.snow, color = o.color }
			)
		end
		addPlaced(x, z, 0, radius, kind)
		count(kind)
		return U.partCount - before
	end

	--------------------------------------------------------------------------------------------
	-- Sites: a jittered 8-stud grid over the land between the promenade and the outer coast
	--------------------------------------------------------------------------------------------
	-- (sites hugging a gameplay area, within 5 studs of reserved ground, go to edgeSites: only
	-- the small decor uses them)
	local rng = Kit.rng(4242)
	local sites = {}
	local edgeSites = {}
	local cell = 8
	for gz = -maxR, maxR, cell do
		for gx = -maxR, maxR, cell do
			local x = gx + rng(-2.5, 2.5)
			local z = gz + rng(-2.5, 2.5)
			local jitter = rng()
			local r = sqrt(x * x + z * z)
			if r < cfg.PromenadeRadius + cfg.PromenadeWidth or r > maxR then
				continue
			end
			local h, kind, water = world:surfaceAt(x, z)
			if water or h < 2 or kind == "path" or world:isReserved(x, z, 1.5) or Kit.isClaimed(x, z, 1.5) then
				continue
			end
			local edge = r < inner or world:isReserved(x, z, 5) or Kit.isClaimed(x, z, 3)
			local theta = deg(atan2(x, z)) % 360
			table.insert(if edge then edgeSites else sites, {
				x = x,
				z = z,
				h = h,
				r = r,
				kind = kind,
				theta = theta,
				sector = floor(theta / 22.5) % 16,
				jitter = jitter,
				grove = world:noise(x / 120 + 70, z / 120 - 30),
				biome = world:noise(x / 260 + 13, z / 260 + 41),
			})
		end
	end

	local peaks = {}
	for _, site in world.landmarks do
		if site.peak then
			table.insert(peaks, site)
		end
	end
	table.sort(peaks, function(a, b)
		return a.angle < b.angle
	end)
	local fall = world.landmarks.Waterfall
	local function onMesa(x: number, z: number, h: number): boolean
		if not fall or h < G + fall.cliffTop - 8 then
			return false
		end
		local lx, lz = world.radialLocal(x, z, fall.angle, fall.radius)
		return lz > 6 and lz < fall.depth - 10 and abs(lx) < fall.halfWidth - 4
	end
	local function nearPeak(x: number, z: number, pad: number): boolean
		for _, p in peaks do
			local dx, dz = x - p.x, z - p.z
			if dx * dx + dz * dz < (p.mountainRadius + pad) ^ 2 then
				return true
			end
		end
		return false
	end

	-- Family of a grove at a site and the kind of each of its trees.
	local function family(s: { [string]: any }): string
		if onMesa(s.x, s.z, s.h) then
			return "blossom"
		elseif s.h >= G + 60 or (s.h >= G + 32 and nearPeak(s.x, s.z, 20)) then
			return "pines"
		elseif s.biome > 0.2 then
			return "cherry"
		elseif s.biome < -0.2 then
			return "autumn"
		end
		return "green"
	end
	local function speciesOf(fam: string, roll: number, h: number): string
		if fam == "pines" then
			return if h >= G + 88 then "snowPine" else "pine"
		elseif fam == "blossom" then
			return if roll < 0.75 then "cherry" else "birch"
		elseif fam == "cherry" then
			return if roll < 0.75 then "cherry" elseif roll < 0.9 then "birch" else "round"
		elseif fam == "autumn" then
			return if roll < 0.5 then "autumn" elseif roll < 0.75 then "gold" elseif roll < 0.9 then "oak" else "pine"
		end
		return if roll < 0.38 then "oak" elseif roll < 0.6 then "round" elseif roll < 0.78 then "birch" else "pine"
	end
	-- Detailed pines and broadleaf trees only where detail allows; far pines on the mountains.
	local carry = 0
	local function quota(name: string): number
		return budget * SHARE[name] + carry
	end
	local function finishPass(q: number, spent: number)
		carry = max(0, q - spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 1: coast — palm clusters, beach props and rock groups along the outer beaches, rocks
	-- below the cliffs
	--------------------------------------------------------------------------------------------
	do
		local q = quota("coast")
		local spent = 0
		local crng = Kit.rng(777)
		-- the outer coast every 2°: the beach band (dry sand at y 2) on each ray
		local samples = {}
		for k = 0, 179 do
			local theta = k * 2 + crng(-0.4, 0.4)
			local coastR = world:coastRadius(theta)
			local ux, uz = sin(rad(theta)), cos(rad(theta))
			local sandIn, sandOut = nil, nil
			for r = coastR - 40, coastR + 30, 2 do
				local h, kind, water = world:surfaceAt(r * ux, r * uz)
				if kind == "sand" and not water and h == 2 then
					sandIn = sandIn or r
					sandOut = r
				end
			end
			table.insert(samples, {
				k = k,
				theta = theta,
				ux = ux,
				uz = uz,
				coastR = coastR,
				sandIn = sandIn,
				sandOut = sandOut,
				beach = sandIn ~= nil and sandOut - sandIn >= 6,
			})
		end
		-- slots along the ring: a palm cluster every 3 beach samples (~70 studs), a beach prop or
		-- a rock group half-way to the next one, a rock in the surf at every fifth cliff sample
		local slots = {}
		local since = 99
		local clusters = 0
		for _, smp in samples do
			if smp.beach then
				if since >= 3 then
					clusters += 1
					table.insert(slots, { kind = "palms", s = smp, n = clusters })
					since = 0
				else
					since += 1
					if since == 2 then
						table.insert(slots, { kind = "extra", s = smp, n = clusters })
					end
				end
			else
				since += 1
				if smp.k % 5 == 0 then
					table.insert(slots, { kind = "surf", s = smp, n = smp.k })
				end
			end
		end
		-- every other cluster first, then the rest, then the extras: a short budget thins the
		-- beach evenly instead of leaving its last stretch bare
		local RANK = { palms = 0, extra = 2, surf = 3 }
		local function rank(slot: any): number
			return RANK[slot.kind] + (if slot.kind == "palms" and slot.n % 2 == 0 then 1 else 0)
		end
		table.sort(slots, function(a, b)
			if rank(a) ~= rank(b) then
				return rank(a) < rank(b)
			end
			return a.s.k < b.s.k
		end)
		local props = { "parasol", "sandcastle", "parasol", "starfish" }
		local nProps = 0
		for _, slot in slots do
			if spent >= q then
				break
			end
			local smp = slot.s
			local ux, uz = smp.ux, smp.uz
			local tx, tz = -uz, ux
			if slot.kind == "palms" then
				-- a palm on the inner half of the beach (a detailed one in every other cluster) and
				-- one or two cheap palms beside it
				local width = smp.sandOut - smp.sandIn
				local r = smp.sandIn + min(5, width * 0.35)
				local x, z = r * ux, r * uz
				local used = tree(x, z, "palm", if slot.n % 2 == 0 then "lite" else "far", "palm")
				local sides = if slot.n % 2 == 0 then { 1, -1 } else { if slot.n % 4 < 2 then 1 else -1 }
				for _, side in sides do
					local off = crng(12, 15) * side
					local out = crng(-1, min(6, width * 0.5))
					used += tree(x + tx * off + ux * out, z + tz * off + uz * out, "palm", "far", "palm")
				end
				spent += used
			elseif slot.kind == "extra" then
				local r = (smp.sandIn + smp.sandOut) / 2
				local x, z = r * ux, r * uz
				if slot.n % 2 == 1 then
					-- a beach prop on the open sand
					local h = flatAt(x, z, 3.6)
					if h and affordable(4) and fits(x, z, 0, 4.5, "prop") then
						local before = U.partCount
						nProps += 1
						local kind = props[(nProps - 1) % #props + 1]
						beachProp(groups.plants, CFrame.new(x, h, z), kind, floor(crng(1, 1e6)))
						addPlaced(x, z, 0, 4, "prop")
						count(kind)
						spent += U.partCount - before
					end
				else
					-- warm light rocks with grassy caps at the water's edge
					local re = smp.sandOut - 3
					local opts = { scale = crng(1.1, 1.6), gap = 3, color = BEACH_ROCK, moss = true, count = 3 }
					local used = small(re * ux, re * uz, "rock", opts)
					if used > 0 then
						used += small(
							re * ux + tx * 6,
							re * uz + tz * 6,
							"rock",
							{ scale = crng(0.7, 1.0), count = 2, color = BEACH_ROCK, gap = 0.5 }
						)
					end
					spent += used
				end
			else
				-- cliff coast: a rock in the surf at the cliff foot
				for r = smp.coastR - 20, smp.coastR + 40, 2 do
					local h, _, water = world:surfaceAt(r * ux, r * uz)
					if water and h >= -4 and affordable(COST.rock) then
						local seed = floor(crng(1, 1e6))
						local before = U.partCount
						Kit.prop(
							"rock",
							groups.rocks,
							CFrame.new(r * ux, h, r * uz),
							{ seed = seed, scale = crng(1.4, 2.0), count = 3, color = BEACH_ROCK, moss = true }
						)
						addPlaced(r * ux, r * uz, 0, 4, "rock")
						count("surfRock")
						spent += U.partCount - before
						break
					end
				end
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 2: pines on the mountains (flanks and the grassRock band; snow-dusted up high)
	--------------------------------------------------------------------------------------------
	do
		local q = quota("pines")
		local spent = 0
		local perPeak = {}
		for i, p in peaks do
			local list = {}
			for _, s in sites do
				local dx, dz = s.x - p.x, s.z - p.z
				local d = sqrt(dx * dx + dz * dz)
				if d < p.mountainRadius + 10 and s.h >= G + 20 and s.h < G + 100 then
					table.insert(
						list,
						{ s = s, score = s.grove * 0.6 + s.jitter + (if s.kind == "grassRock" then 0.4 else 0) }
					)
				end
			end
			table.sort(list, function(a, b)
				if a.score ~= b.score then
					return a.score > b.score
				end
				return a.s.x + a.s.z * 1e-3 < b.s.x + b.s.z * 1e-3
			end)
			perPeak[i] = list
		end
		-- round-robin over the mountains so each gets its share
		local idx = {}
		local placedOn = {}
		for i in peaks do
			idx[i], placedOn[i] = 1, 0
		end
		local progress = true
		while progress and spent < q do
			progress = false
			for i in peaks do
				local list = perPeak[i]
				while idx[i] <= #list and placedOn[i] < 16 do
					local s = list[idx[i]].s
					idx[i] += 1
					local kind = if s.h >= G + 84 then "snowPine" else "pine"
					local level = if world:isReserved(s.x, s.z, 70) then "lite" else "far"
					local used = tree(s.x, s.z, kind, level, "pines")
					if used > 0 then
						spent += used
						placedOn[i] += 1
						progress = true
						break
					end
				end
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 3: groves
	--------------------------------------------------------------------------------------------
	-- how much a spot at radius r is seen from the play area (hub, bridges, promenade, bases)
	local function visibility(r: number): number
		return 0.55 + 0.45 * smooth(380, 470, r) - 0.35 * smooth(600, 680, r)
	end
	local centres = {}
	do
		local order = {}
		for _, s in sites do
			if s.kind ~= "sand" and s.kind ~= "snow" and s.kind ~= "stone" then
				table.insert(order, { s = s, score = visibility(s.r) + 0.35 * s.grove + 0.25 * s.jitter })
			end
		end
		table.sort(order, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.s.x + a.s.z * 1e-3 < b.s.x + b.s.z * 1e-3
		end)
		local taken = {}
		for _, e in order do
			local ok = true
			for _, c in taken do
				local dx, dz = e.s.x - c.x, e.s.z - c.z
				if dx * dx + dz * dz < 80 * 80 then
					ok = false
					break
				end
			end
			if ok then
				table.insert(taken, e.s)
			end
		end
		-- round-robin over the 16 sectors, best first in each
		local bySector = {}
		for k = 0, 15 do
			bySector[k] = {}
		end
		for _, c in taken do
			table.insert(bySector[c.sector], c)
		end
		local round = 1
		local any = true
		while any do
			any = false
			for k = 0, 15 do
				local c = bySector[k][round]
				if c then
					table.insert(centres, c)
					any = true
				end
			end
			round += 1
		end
	end
	-- sites within 46 studs of each centre (closest first, ragged edges)
	local siteHash = {}
	for _, s in sites do
		local k = hashKey(s.x, s.z)
		siteHash[k] = siteHash[k] or {}
		table.insert(siteHash[k], s)
	end
	local function sitesNear(x: number, z: number, radius: number): { any }
		local out = {}
		local n = math.ceil(radius / HASH)
		local cx, cz = floor(x / HASH), floor(z / HASH)
		for ix = cx - n, cx + n do
			for iz = cz - n, cz + n do
				local list = siteHash[(ix + 200) * 1000 + iz + 200]
				if list then
					for _, s in list do
						local dx, dz = s.x - x, s.z - z
						local d = sqrt(dx * dx + dz * dz)
						if d < radius then
							table.insert(out, { s = s, d = d + 14 * s.jitter })
						end
					end
				end
			end
		end
		table.sort(out, function(a, b)
			if a.d ~= b.d then
				return a.d < b.d
			end
			return a.s.x + a.s.z * 1e-3 < b.s.x + b.s.z * 1e-3
		end)
		return out
	end
	local nextCentre = 1
	local groveCount = 0
	local function groves(q: number): number
		local spent = 0
		while nextCentre <= #centres and spent < q do
			local c = centres[nextCentre]
			nextCentre += 1
			local fam = family(c)
			local target = 5 + floor(c.jitter * 4.99)
			local planted = 0
			for _, e in sitesNear(c.x, c.z, 46) do
				if planted >= target or spent >= q then
					break
				end
				local s = e.s
				if s.kind ~= "sand" and s.kind ~= "snow" then
					-- the waterfall mesa top always blossoms, whatever grove reaches it
					local f = if onMesa(s.x, s.z, s.h) then "blossom" else fam
					local kind = speciesOf(f, (s.jitter * 7.31) % 1, s.h)
					local used = tree(s.x, s.z, kind, detail(s.x, s.z), fam)
					if used > 0 then
						spent += used
						planted += 1
					end
				end
			end
			if planted > 0 then
				groveCount += 1
			end
		end
		return spent
	end
	do
		local q = quota("groves")
		finishPass(q, groves(q))
	end

	--------------------------------------------------------------------------------------------
	-- Pass 4: decor — flower clusters, bushes and rock groups hugging the paths, plots, gateway
	-- plazas and landmark sites; flower meadows on the waterfall mesa and the giant tree's meadow
	--------------------------------------------------------------------------------------------
	local drng = Kit.rng(6060)
	-- One decor group at site s: mostly a flower cluster, sometimes a bush or a rock group (a
	-- mossy rock with a small one beside it). `margin` = distance kept from reserved ground.
	-- `meadows` = share of flower meadows (open lawns: a big splash of colour seen from afar;
	-- where the ground is too small for one, a cluster).
	local function decorGroup(s: { [string]: any }, margin: number, meadows: number): number
		local roll = drng()
		if roll < meadows then
			local used = small(s.x, s.z, "meadow", { margin = margin, gap = 2 })
			if used > 0 then
				return used
			end
			return small(s.x, s.z, "cluster", { count = 4, margin = margin, gap = 1 })
		elseif roll < 0.64 then
			return small(s.x, s.z, "cluster", { count = 3 + floor(drng() * 2.99), margin = margin, gap = 1 })
		elseif roll < 0.84 then
			local berries = if drng() < 0.6 then BLOOMS[floor(drng(1, #BLOOMS + 0.99))] else false
			return small(s.x, s.z, "bush", { scale = drng(1.1, 1.5), margin = margin + 1, gap = 1, berries = berries })
		end
		local used = small(s.x, s.z, "rock", { scale = drng(1.0, 1.4), moss = true, count = 3, margin = margin + 2 })
		if used > 0 then
			local a = drng(0, 2 * math.pi)
			used += small(
				s.x + 5.5 * sin(a),
				s.z + 5.5 * cos(a),
				"rock",
				{ scale = drng(0.6, 0.8), count = 2, margin = margin + 2, gap = 0.2 }
			)
		end
		return used
	end
	do
		local q = quota("decor")
		local spent = 0
		-- flower meadows: the waterfall mesa top and the ring round the giant tree's plateau
		local beds = {}
		local giant = world.landmarks.GiantTree
		for _, s in sites do
			if onMesa(s.x, s.z, s.h) then
				table.insert(beds, { s = s, score = s.jitter })
			elseif giant then
				local d = sqrt((s.x - giant.x) ^ 2 + (s.z - giant.z) ^ 2)
				if d > giant.plateauRadius + 4 and d < 110 then
					table.insert(beds, { s = s, score = s.jitter })
				end
			end
		end
		table.sort(beds, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.s.x + a.s.z * 1e-3 < b.s.x + b.s.z * 1e-3
		end)
		local nBeds = 0
		for _, e in beds do
			if nBeds >= 14 or spent >= q * 0.3 then
				break
			end
			if nearest(e.s.x, e.s.z, 16) >= 16 then
				local used = small(e.s.x, e.s.z, "meadow", { gap = 2 })
				if used > 0 then
					nBeds += 1
					spent += used
				end
			end
		end
		-- groups within ~14 studs of a path, plot, gateway or landmark site, the paths first
		local list = {}
		for _, group in { edgeSites, sites } do
			for _, s in group do
				if s.kind ~= "sand" and s.kind ~= "snow" and s.kind ~= "stone" and world:isReserved(s.x, s.z, 14) then
					local onPathSide = world:pathDistance(s.x, s.z) < 16
					table.insert(list, { s = s, score = s.jitter + (if onPathSide then 0.7 else 0) })
				end
			end
		end
		table.sort(list, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.s.x + a.s.z * 1e-3 < b.s.x + b.s.z * 1e-3
		end)
		for _, e in list do
			if spent >= q then
				break
			end
			if nearest(e.s.x, e.s.z, 15) >= 15 then
				spent += decorGroup(e.s, 1.5, 0)
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 5: terrace lips facing the promenade — bushes, flower clumps, small rocks
	--------------------------------------------------------------------------------------------
	do
		local q = quota("lips")
		local spent = 0
		local list = {}
		for _, s in sites do
			if s.kind == "grass" and s.h > G and s.r < 600 then
				-- the column one step towards the lagoon is lower: s is on a lip
				local ux, uz = s.x / s.r, s.z / s.r
				local lower = world:heightAt(s.x - ux * 8, s.z - uz * 8)
				if lower <= s.h - 4 then
					table.insert(list, { s = s, score = (1 - smooth(340, 600, s.r)) + 0.6 * s.jitter })
				end
			end
		end
		table.sort(list, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.s.x + a.s.z * 1e-3 < b.s.x + b.s.z * 1e-3
		end)
		local lrng = Kit.rng(31337)
		for _, e in list do
			if spent >= q then
				break
			end
			local s = e.s
			local roll = lrng()
			-- keep lip things at least 16 studs apart so they line the edges instead of piling up
			if nearest(s.x, s.z, 16) >= 16 then
				if roll < 0.45 then
					spent += small(s.x, s.z, "bush", {
						scale = lrng(1.3, 1.8),
						berries = C.Flowers[floor(lrng(1, #C.Flowers + 0.99))],
						gap = 2,
					})
				elseif roll < 0.85 then
					spent += small(s.x, s.z, "flowers", { scale = lrng(1.2, 1.6), gap = 2 })
				else
					spent += small(s.x, s.z, "rock", { scale = lrng(0.9, 1.3), moss = true, gap = 2 })
				end
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 6: boulders and rock clusters on the rocky upper slopes
	--------------------------------------------------------------------------------------------
	do
		local q = quota("rocks")
		local spent = 0
		local list = {}
		for _, s in sites do
			if s.kind == "grassRock" or s.kind == "stone" or (s.kind == "grass" and s.h >= G + 44) then
				table.insert(list, { s = s, score = s.jitter + (if s.kind == "grassRock" then 0.3 else 0) })
			end
		end
		table.sort(list, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.s.x + a.s.z * 1e-3 < b.s.x + b.s.z * 1e-3
		end)
		local rrng = Kit.rng(2024)
		for _, e in list do
			if spent >= q then
				break
			end
			local s = e.s
			if nearest(s.x, s.z, 30) >= 30 then
				local snow = s.h >= G + 92
				if rrng() < 0.5 then
					spent += small(s.x, s.z, "boulder", { scale = rrng(0.9, 1.2), moss = not snow, snow = snow })
				else
					spent += small(s.x, s.z, "rock", { scale = rrng(1.2, 1.7), moss = not snow, snow = snow })
				end
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 7: fill — whatever hill spot is still far from everything gets a single tree, a
	-- bush or a rock (half of the pass); then more groves, then decor on open lawns with the
	-- rest of the budget
	--------------------------------------------------------------------------------------------
	do
		local q = quota("fill")
		local spent = 0
		local order = {}
		for _, s in sites do
			if s.kind ~= "sand" and s.kind ~= "snow" then
				table.insert(order, s)
			end
		end
		table.sort(order, function(a, b)
			if a.jitter ~= b.jitter then
				return a.jitter > b.jitter
			end
			return a.x + a.z * 1e-3 < b.x + b.z * 1e-3
		end)
		local frng = Kit.rng(5150)
		for _, s in order do
			if spent >= q * 0.5 then
				break
			end
			if nearest(s.x, s.z, 36) >= 36 then
				local roll = frng()
				local fam = family(s)
				if roll < 0.6 then
					spent += tree(s.x, s.z, speciesOf(fam, frng(), s.h), detail(s.x, s.z), fam)
				elseif roll < 0.82 then
					spent += small(s.x, s.z, "bush", { scale = frng(1.4, 2.0) })
				else
					spent += small(s.x, s.z, "rock", { scale = frng(1.0, 1.5), moss = frng() < 0.5 })
				end
			end
		end
		-- under half of what is left for more groves, the rest (and whatever the groves cannot place:
		-- far ones stop at FAR_CAP) for decor groups on open lawns and slopes, the ones nearest
		-- the play area first, until the budget is spent
		local left = budget - spentAll()
		if left > 0 then
			spent += groves(left * 0.45)
		end
		local lawns = {}
		for _, s in sites do
			if (s.kind == "grass" or s.kind == "meadow") and s.h < G + 60 then
				local near = if world:isReserved(s.x, s.z, 40)
					then 1
					elseif world:isReserved(s.x, s.z, 90) then 0.5
					else 0
				table.insert(lawns, { s = s, score = near + 0.6 * s.jitter })
			end
		end
		table.sort(lawns, function(a, b)
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.s.x + a.s.z * 1e-3 < b.s.x + b.s.z * 1e-3
		end)
		for _, e in lawns do
			if not affordable(COST.cluster) then
				break
			end
			if nearest(e.s.x, e.s.z, 16) >= 16 then
				decorGroup(e.s, 5, 0.4)
			end
		end
	end

	counts.groves = groveCount
	return counts
end

return Nature
