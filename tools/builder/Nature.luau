--[[
	Nature — voxel forests, tree belts, palms, undergrowth, rocks and little country set-pieces
	on the ring hills, the mountains and the outer beaches (Map.Nature), within the part budget
	Map.luau gives it (whatever the other dressing left over; Map.luau guarantees a minimum).

	Every spot is checked against the voxel ground and the dressing already built: no reserved
	ground (world:isReserved — plots, promenade, gateways, paths, the peak trail and summit,
	landmark sites), no "path" columns under the footprint, no areas claimed by the dressing
	modules (Kit.isClaimed), no water, the whole trunk / bush / rock footprint on one flat column
	top, no tree canopy cutting into a higher terrace or a stone column round it, and nothing
	overlapping a part of the bridges, promenade, gateways, landmarks or the water decor (their
	bounding boxes are hashed first). Objects keep their distance: two trees of one grove at
	least 0.8 × (sum of canopy radii) apart (their crowns merge into one wood), along x or z
	too (1.0 between different groups, 0.62 between palms: fronds may cross), small things
	clear of trunks and of each other.

	Art direction v4 (DESIGN.md §1): a predominantly green island — woods of oaks, round trees,
	birches and pines in natural, slightly different greens (all Palette tokens), with bushes on
	the wood edges. Blossom and autumn colours appear only as accent groves in three deliberate
	spots (ACCENT): cherries on the waterfall mesa, an autumn orchard on the hills behind the farm
	gateway (θ 0) and a few russet trees on the red-rock mesas' ledges — together under ACCENT_CAP
	trees (well under 10 % of the trees). Flowers are the island's small colour pops: the Palette's
	jewel tones (Props.bloomPairs) in harmonious pairs (one colour and a white partner, or two
	neighbouring hues), one pair per clump or bed; no rainbow rows. No figures (people,
	scarecrows, animals).

	Most of the budget goes into trees grouped into woods (5-part voxel trees, Nature.farTree):
	groves of 5-9 trees with a bush or two on their edge, belts behind the plots, woods of 5-8
	trees on the visible crests, and more groves where the land is still open. Nothing grows on
	the far side of a mountain (beyond r 640, behind its summit: no view reaches it). The outer
	beaches and cliff tops, seen from the hill viewpoints, get small scenes of island life. The
	lawns between stay open: small
	decor (2-5 parts: flower clumps, bushes, rocks with a moss cap and a bush beside them, hay
	bales, short fence runs, voxel cacti on the mesas) lines the paths and the terrace lips in
	spaced groups instead of being scattered everywhere, and a few set-pieces of 5-10 parts
	(pumpkin patch, picnic blanket, bee boxes, log pile, mushroom ring, raised flower beds, bush
	clumps) sit on the biggest lawns.

	Up on a mountain its style picks the trees: pines on the snow peaks (snow-dusted only there),
	plain pines and round trees on the green hill, palms and green round trees on the red-rock
	mesas (at most MESA_TREES on each ochre top, with a few cacti and terracotta boulders).

	Passes: lagoon, show and wedges first, then the shared passes, each with its share of the
	budget left after the first three (unspent parts carry over to the next one):
	  lagoon  12 calm coral patches on the lagoon's sandy slope beside the piers and bridges
	          (an irregular sand pad, coral fingers in terracotta / sand / sage, seaweed, a rock, a
	          starfish, one small pink tip, bubbles; nothing above y -4), then 2-3 surface
	          features a quadrant: a moored houseboat, a floating fish-farm ring, a rocky islet
	          with a perch; the water in front of the piers and along the bridges stays clear,
	          the surface features keep out of every pier's casting cone
	  show    the lawns between two plots at the peak trail and the giant tree (seen first from
	          the promenade): an avenue of detailed pines framing the peak trail, then raised
	          flower beds (one colour pair each), bush clumps and boulder groups on the voxel grid
	  wedges  the hills behind the gateway plazas: clumps of two or three trees in the
	          district's theme (a farm orchard with one golden tree a clump, birches behind the
	          garden, palms by the harbour, pines round the camp) on the terrace lips either side
	          of the climb, each with a bush
	  shore   4-5 scenes a quadrant on the outer coast, where the hill viewpoints look, each facing
	          the sea on the first spot (from the sea inwards) where its footprint stands: a
	          fisherman's hut on stilts by the water (a painted door and a pennant, a ladder, a net
	          hung to dry), a beach camp (a faded jewel tent, a campfire with smoke, log seats, a
	          painted canoe), drying racks (a net, a rack of fish, a basket of floats), a keeper's
	          cottage on the grass over the beach (plinth, plaster, stepped roof, chimney, a flower
	          box in jewel blooms, a flag), boulder piles with dune grass; drawn 1.3 x (SHORE_SCALE)
	  coast   a pair of palms (drooping fronds: farTree "beachPalm") every ~65 studs of the outer
	          beaches; between the pairs, by turns,
	          a beach set (parasol with a towel, sandcastle, towel and ball, driftwood) and a rock
	          group at the waterline in a ring of foam; foamy rocks in the surf below the cliffs
	  pines   the mountains in their styles: up to 14 pines on the grassy flanks of each snow
	          peak (snow-dusted higher up) with snow-capped rocks, pines and round trees on the
	          green hill with mossy rocks; on each red-rock mesa three cacti, up to 8 palms /
	          round trees (a few russet ones) and terracotta boulders
	  belts   a continuous tree line behind every plot's back wall (two rows, round-robin over
	          the plots), one tree family per plot by the biome noise
	  crests  woods of 5-8 trees whose crowns merge on the most visible hill crests (local high
	          points, at least 70 studs apart): the skyline behind the plots and over the coast
	  sets    set-pieces on the biggest open lawns, spread over the sectors, before the groves
	          take the land
	  groves  woods of 5-9 trees whose crowns merge (centres ~80 studs apart, round-robin over
	          the 16 sectors of 22.5°, most visible first) with bushes on the wood's edge; one
	          family per grove by height and a ~260-stud biome noise: mixed green (oak, round,
	          pine, birch), birch woods, conifer woods, pines up high; the accent families only in
	          their spots (blossom on the waterfall mesa, the farm orchard)
	  decor   flowers along both sides of the landmark paths (by turns a drift of flowers on
	          stems, Props.flowerBed, and a pair of clumps, the sides staggered); spaced groups
	          where people walk: flower clumps and drifts (one jewel pair), bushes and rock groups
	          along the paths and on the low lawns round the plots, plazas and landmark sites,
	          bushes and rocks on the terrace lips facing the promenade (only rocks and bushes on
	          the mountains' flanks); wildflower patches where the woods leave room on the
	          waterfall mesa and the giant tree's lawn
	  fill    coverage: rounds over every land spot, most visible first, each placing something
	          wherever nothing (Nature or other dressing) is within 34 / 26 studs — a copse of up
	          to three trees on the big gaps, a bush or a rock group on the rest (no flowers;
	          nothing behind the mountains); more groves with what is left
	The far woods beyond FAR_R (behind the plots and the peaks) are thinned by a quarter with
	bigger trees for the same cover, so the budget stays with the near hills.
	Level of detail by distance to the play area: full Props trees (13-16 parts) only right beside
	the landmark paths (at most FULL_CAP), compact Props lite trees (6-10) within ~50 studs of the
	play area, the 5-part trees built here everywhere else (Coast.luau uses them on the islets
	too). The biggest canopy block of every tree casts a shadow; small foliage does not.
	Returns counts per kind (printed by tools/build.luau).
]]

local U = require("./Util")
local Kit = require("./MapKit")
local Props = require("./Props")

local CFrame = U.CFrame
local Vector3 = U.Vector3
local C = Kit.C

local sqrt, deg, atan2, floor, abs, min, max = math.sqrt, math.deg, math.atan2, math.floor, math.abs, math.min, math.max
local sin, cos, rad = math.sin, math.cos, math.rad

local Nature = {}

-- Share per pass of the budget left after the lagoon, showcase and gateway-wedge passes (the
-- rest of a pass's share carries over to the next one).
local SHARE = {
	shore = 0.14,
	coast = 0.13,
	pines = 0.15,
	belts = 0.12,
	crests = 0.1,
	sets = 0.03,
	decor = 0.13,
	groves = 0.12,
	fill = 0.08,
}
-- Most full Props trees (13-16 parts): only the ones right beside the paths and plazas.
local FULL_CAP = 16
-- The far back belt (beyond FAR_R from the centre: behind the plots and the peaks, seen across
-- the whole island) is thinned by a quarter (one spot in four stays open) with bigger cheap
-- trees for the same cover, so the budget stays with the near hills, where players look.
local FAR_R = 520
local FAR_SCALE = 1.15
local THINNED = { pines = false, crest = false, palm = false }

local FOLIAGE = Kit.DECOR
local CANOPY = { CanCollide = false, CanQuery = false, CastShadow = true } -- the one shadow block
local lerp = Kit.lerpColor
-- Every colour is a Palette token or derived from one (DESIGN.md §1).
local BEACH_ROCK = lerp(C.StoneLight, C.SandDark, 0.4) -- warm light rocks on the sand
-- warm stone (the Palette's Stone tokens: never a flat grey) with a moss cap
local ROCK = lerp(C.Stone, C.StoneLight, 0.35)
local ROCK_DARK = C.StoneDark
local HAY = { C.Straw, C.StrawLight }
local FOAM = C.Foam
-- Red-rock mesas: terracotta boulders and sage voxel cacti on the ochre tops.
local REDROCK = lerp(C.RoofTerracotta, C.Stone, 0.15)
local CACTUS = { C.Mint2, C.Mint1 }

-- Leaf palettes {dark, mid, light}: a step darker than the lawns so woods read as woods; a few
-- neighbouring greens (leaf, deep, mint, birch) give the woods a natural variety.
local GREEN = { C.Leaf1, C.Leaf2, C.Leaf3 }
local BUSH = { C.Leaf0, C.Leaf1, C.Leaf2 }
local PAL = {
	green = GREEN,
	deep = { C.Leaf0, C.Leaf1, C.Leaf2 },
	mint = { C.Mint1, C.Mint2, C.Mint3 },
	birch = { C.BirchLeaf1, C.BirchLeaf2, C.BirchLeaf3 },
	lime = { C.Leaf2, C.Leaf3, C.LeafLight },
	cherry = { C.Blossom0, C.Blossom1, C.Blossom2 },
	autumn = { C.Autumn0, Kit.shade(C.Autumn1, 0.88), lerp(C.Autumn2, C.StrawLight, 0.5) },
	-- (golden but mellow: the big canopies stay under the loud threshold of DESIGN.md §1)
	gold = {
		Kit.shade(lerp(C.Autumn1, C.Autumn2, 0.4), 0.86),
		lerp(C.Straw, C.Autumn2, 0.1),
		lerp(C.Autumn2, C.StrawLight, 0.5),
	},
	palm = { C.Palm1, C.Palm2, C.Palm3 },
}
-- Accent foliage: tree kinds that are not green (they count against ACCENT_CAP).
local ACCENT_KIND = { cherry = true, autumn = true, gold = true }
-- At most this many accent trees on the whole island (a few deliberate groves; ~6 % of trees).
local ACCENT_CAP = 24

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
	farPalm = 5.8,
}
-- Height of the lowest foliage above the foot (studs at scale 1): nothing round a tree may
-- stand higher than this within its canopy.
local CANOPY_BOTTOM = { far = 4.6, farPine = 2.4, farPalm = 9.6, broad = 4.1, birch = 7.2, pine = 1.9, palm = 8.5 }
-- Trunk half-width (studs at scale 1, incl. jitter and roots).
local TRUNK_R = { full = 2.6, lite = 1.6, far = 1.4 }

-- Flower colours come in harmonious pairs (one colour and a light partner, or two neighbouring
-- hues); a clump or bed uses one pair, never a rainbow.
local PAIRS = Props.bloomPairs
local function pairOf(roll: number): { any }
	return PAIRS[floor(roll * #PAIRS) % #PAIRS + 1]
end
-- A single accent colour (berries on a bush): the first colour of a pair.
local function bloomOf(roll: number): any
	return pairOf(roll)[1]
end

-- NumberSequence from a to b.
local function seq(a: number, b: number): any
	return U.roblox.NumberSequence.new({
		U.roblox.NumberSequenceKeypoint.new(0, a),
		U.roblox.NumberSequenceKeypoint.new(1, b),
	})
end

-- A ParticleEmitter (no parts: spray, bubbles) on `part`, emitting from its top face; low rates
-- (phones), never lit, no shadows.
local function emitter(part: any, name: string, props: { [string]: any }): any
	local p = table.clone(props)
	p.Name = name
	p.EmissionDirection = p.EmissionDirection or U.Enum.NormalId.Top
	p.LightEmission = p.LightEmission or 0.15
	return U.new("ParticleEmitter", p, part)
end

local function smooth(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

--------------------------------------------------------------------------------------------
-- Cheap far trees (5 parts)
--------------------------------------------------------------------------------------------

--[[
	Nature.farTree(parent, cf, kind, scale, seed): a 5-part voxel tree for far hills, tree belts
	and islets (the silhouettes of the Props trees with fewer blocks).
	  "green" | "deep" | "mint" | "lime"       trunk and a three-step pyramid: a wide dark base,
	  | "cherry" | "autumn" | "gold"           a mid "plus" of two blocks (the shadow caster), a
	                                           small light top (cherry / autumn / gold: accents)
	  "birch"               a slim white trunk under a narrower, taller canopy in fresh greens
	  "pine" | "snowPine"   trunk, a stepped cone of three tiers (dark to light) and a tip
	  "palm"                two trunk segments (the upper one leaning a little, overlapping the
	                        lower by 0.6 · scale: one bent trunk), crown, two crossed fronds
	  "beachPalm"           (7 parts) the palm with short light fronds over long darker ones a
	                        step lower: drooping frond tips (the outer beaches' palms)
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
	elseif kind == "palm" or kind == "beachPalm" then
		local lean = r(0.4, 0.8)
		trunk = box("Trunk1", -1.0, -1 / s, -1.0, 1.0, 5.6, 1.0, C.PalmBark)
		box("Trunk2", lean - 0.8, 5.0, -0.8, lean + 0.8, 10.4, 0.8, C.PalmBarkDark)
		box("Crown", lean - 1.4, 9.6, -1.4, lean + 1.4, 11.4, 1.4, C.Palm1, FOLIAGE)
		local L = r(4.6, 5.2)
		if kind == "beachPalm" then
			-- (7 parts) short, light upper fronds over long darker ones a step lower: the frond
			-- tips droop (a palm from the side, a two-tone star from above, not a flat cross)
			box("FrondX", lean - L * 0.6, 10.9, -1.2, lean + L * 0.6, 11.9, 1.2, C.Palm3, CANOPY)
			box("FrondZ", lean - 1.2, 10.7, -L * 0.6, lean + 1.2, 11.7, L * 0.6, C.Palm3, FOLIAGE)
			box("DroopX", lean - L * 1.12, 9.95, -0.85, lean + L * 1.12, 10.95, 0.85, C.Palm2, FOLIAGE)
			box("DroopZ", lean - 0.85, 9.75, -L * 1.12, lean + 0.85, 10.75, L * 1.12, C.Palm1, FOLIAGE)
		else
			box("FrondX", lean - L, 10.9, -1.1, lean + L, 11.9, 1.1, C.Palm2, CANOPY)
			box("FrondZ", lean - 1.1, 10.7, -L, lean + 1.1, 11.7, L, C.Palm3, FOLIAGE)
		end
	else
		local birch = kind == "birch"
		local pal = PAL[kind] or PAL.green
		-- (birches: a narrower crown on a taller, slimmer white trunk)
		local R = r(5.0, 5.8) * (if birch then 0.74 else 1)
		local th = r(4.6, 5.4) + (if birch then 2.2 else 0)
		local half = if birch then 0.85 else 1.2
		local bark = if birch then C.Birch elseif kind == "cherry" then C.BarkDark else C.Bark
		trunk = box("Trunk", -half, -1 / s, -half, half, th + 2, half, bark)
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

--------------------------------------------------------------------------------------------
-- Cheap decor (2-4 parts) and set-pieces (5-10 parts); all stand on cf (front -Z)
--------------------------------------------------------------------------------------------

local function turned(cf: any, r: (number?, number?) -> number): any
	return cf * CFrame.Angles(0, rad(90 * floor(r(0, 3.99))), 0)
end

-- Flower tuft (3 parts): a leafy mound with two blooms half sunk into it, one harmonious pair.
local function tuft(parent: any, cf: any, s: number, seed: number, pair: { any }?): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "Flowers", turned(cf, r))
	local w, d, h = r(1.8, 2.2) * s, r(1.4, 1.8) * s, r(1.0, 1.3) * s
	local mound = b:box("Leaves", -w, -0.3, -d, w, h, d, BUSH[2], FOLIAGE)
	local pr = pair or pairOf(r())
	local c1, c2 = pr[1], pr[2]
	local bw = r(0.7, 0.85) * s
	b:box("Bloom1", -0.4 * w - bw, h - 0.9 * bw, -0.2 * d - bw, -0.4 * w + bw, h + 1.1 * bw, -0.2 * d + bw, c1, FOLIAGE)
	b:box("Bloom2", 0.4 * w - bw, h - 0.5 * bw, 0.25 * d - bw, 0.4 * w + bw, h + 1.5 * bw, 0.25 * d + bw, c2, FOLIAGE)
	return b:finish(mound)
end

-- Bush (2 parts, 3 with berries): a leafy block with a lighter one on top.
local function shrub(parent: any, cf: any, s: number, seed: number, berry: any?): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "Bush", turned(cf, r))
	local w, d, h = r(1.9, 2.4) * s, r(1.6, 2.0) * s, r(2.0, 2.7) * s
	local main = b:box("Bush", -w, -0.3, -d, w, h, d, BUSH[2], CANOPY)
	local ox, oz = r(-0.2, 0.2) * w, r(-0.2, 0.2) * d
	b:box("Top", ox - 0.6 * w, h - 0.4, oz - 0.5 * d, ox + 0.6 * w, h + r(0.8, 1.2) * s, oz + 0.5 * d, BUSH[3], FOLIAGE)
	if berry then
		local bs = 0.9 * s
		local bx, by = 0.35 * w, h - bs - 0.5
		b:box("Berries", bx - bs / 2, by, -d - 0.3, bx + bs / 2, by + bs, -d + bs - 0.3, berry, FOLIAGE)
	end
	return b:finish(main)
end

--[[
	Rock (2-4 parts): a warm light grey block with a lighter one stacked off-centre on it, a
	moss (or snow) cap on top and a darker pebble beside it. opts: color, cap = "moss" |
	"snow" | nil, pebble = false.
]]
local function rock(parent: any, cf: any, s: number, seed: number, o: { [string]: any }): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "Rock", turned(cf, r))
	local body = o.color or ROCK
	local light = lerp(body, C.Limestone, 0.45)
	local w, d, h = r(3.2, 4.4) * s, r(2.8, 3.8) * s, r(1.8, 2.6) * s
	local main = b:box("Rock", -w / 2, -0.6, -d / 2, w / 2, h, d / 2, body)
	local ox, oz = r(-0.12, 0.12) * w, r(-0.12, 0.12) * d
	local uw, ud = w * 0.31, d * 0.31
	local top = h + r(1.1, 1.6) * s
	b:box("RockTop", ox - uw, h - 0.3, oz - ud, ox + uw, top, oz + ud, light)
	if o.cap then
		local capC = if o.cap == "snow" then C.Snow else C.Leaf2
		b:box(
			"Cap",
			ox - uw + 0.25,
			top - 0.05,
			oz - ud + 0.25,
			ox + uw - 0.25,
			top + 0.4,
			oz + ud - 0.25,
			capC,
			Kit.NOSHADOW
		)
	end
	if o.pebble ~= false then
		local ps = r(1.1, 1.5) * s
		local dark = if o.color then Kit.shade(body, 0.86) else ROCK_DARK
		b:box("Pebble", w / 2 + 0.3, -0.4, -0.3 * d, w / 2 + 0.3 + ps, 0.7 * ps, -0.3 * d + ps, dark)
	end
	return b:finish(main)
end

-- Rock in the water (3-4 parts): a rock on the sea bed (cf at the bed, y `bed`) standing out
-- of the water in a ring of white foam.
local function surfRock(parent: any, cf: any, bed: number, s: number, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "SurfRock", turned(cf, r))
	local w, d = r(3.6, 4.8) * s, r(3.2, 4.2) * s
	local h = -bed + r(1.6, 2.6) * s
	local main = b:box("Rock", -w / 2, -0.6, -d / 2, w / 2, h, d / 2, BEACH_ROCK)
	local ox = r(-0.1, 0.1) * w
	b:box("RockTop", ox - w * 0.3, h - 0.3, -d * 0.3, ox + w * 0.3, h + r(0.9, 1.4) * s, d * 0.3, C.Leaf2)
	-- (the foam ring floats 0.15-0.35 over the water plane: the terrain's waves never flood it)
	local fw, fd = w / 2 + r(1.0, 1.6), d / 2 + r(1.0, 1.6)
	local foam = b:box("Foam", -fw, -bed + 0.15, -fd, fw, -bed + 0.35, fd, FOAM, FOLIAGE)
	-- now and then a puff of spray where the waves hit the rock
	emitter(foam, "Spray", {
		Rate = 1.5,
		Lifetime = U.roblox.NumberRange.new(0.7, 1.1),
		Speed = U.roblox.NumberRange.new(3, 5),
		SpreadAngle = U.Vector2.new(25, 25),
		Size = seq(0.9, 2.2),
		Transparency = seq(0.35, 1),
		Color = U.roblox.ColorSequence.new(C.White),
		Acceleration = Vector3.new(0, -9, 0),
	})
	if r() < 0.6 then
		local ps = r(1.4, 2.0) * s
		b:box("Pebble", w / 2 + 1.4, -0.6, -ps / 2, w / 2 + 1.4 + ps, -bed + 0.6, ps / 2, Kit.shade(BEACH_ROCK, 0.88))
	end
	return b:finish(main)
end

-- Hay bales (3 parts): two side by side, one on top.
local function hayBales(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "HayBales", turned(cf, r))
	local first = b:box("Bale1", -3.0, -0.2, -1.3, -0.05, 2.4, 1.3, HAY[1])
	b:box("Bale2", 0.15, -0.2, -1.2, 3.1, 2.25, 1.4, HAY[1])
	b:box("Bale3", -1.6, 2.1, -1.05, 1.3, 4.4, 1.05, HAY[2])
	return b:finish(first)
end

-- Short fence run (4 parts): two posts and two rails, `len` studs long along local X.
local function fence(parent: any, cf: any, len: number, white: boolean): any
	local b = Kit.builder(parent, "Fence", cf)
	local post = if white then C.Cream else C.Wood
	local rail = if white then C.Plaster else C.WoodLight
	local first = b:box("PostA", -len / 2 - 0.45, -0.5, -0.45, -len / 2 + 0.45, 3.0, 0.45, post)
	b:box("PostB", len / 2 - 0.45, -0.5, -0.45, len / 2 + 0.45, 3.0, 0.45, post)
	b:box("RailLow", -len / 2, 0.9, -0.22, len / 2, 1.5, 0.22, rail, Kit.NOSHADOW)
	b:box("RailHigh", -len / 2, 2.0, -0.22, len / 2, 2.6, 0.22, rail, Kit.NOSHADOW)
	return b:finish(first)
end

-- Pumpkin patch (8 parts): a soil bed with a vine row and three pumpkins on stems.
local function pumpkinPatch(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "PumpkinPatch", turned(cf, r))
	local soil = b:box("Soil", -5, -0.3, -4, 5, 0.35, 4, C.DirtDark, Kit.NOSHADOW)
	b:box("Vines", -4.2, 0.3, -0.5, 4.2, 0.7, 0.5, C.Leaf1, FOLIAGE)
	local deep = Kit.shade(C.Orange, 0.88)
	for i, p in { { -2.6, -2.1, 2.4 }, { 0.6, 2.0, 2.0 }, { 3.0, -1.8, 1.6 } } do
		local x, z, w = p[1], p[2], p[3] * r(0.9, 1.1)
		local h = w * 0.75
		b:box(`Pumpkin{i}`, x - w / 2, 0.2, z - w / 2, x + w / 2, 0.2 + h, z + w / 2, if i == 2 then deep else C.Orange)
		b:box(`Stem{i}`, x - 0.22, 0.1 + h, z - 0.22, x + 0.22, 0.2 + h + 0.7, z + 0.22, C.Leaf1, FOLIAGE)
	end
	return b:finish(soil)
end

-- Picnic spot (5 parts): a jewel red or blue blanket with two cream stripes and a basket with
-- its lid.
-- (the stripes stand 0.06 proud of the cloth on every face: no shared plane)
local function picnic(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "Picnic", turned(cf, r))
	local col = if r() < 0.5 then C.Flowers[1] else C.Flowers[7]
	local blanket = b:box("Blanket", -3.2, -0.1, -2.6, 3.2, 0.14, 2.6, col, Kit.NOSHADOW)
	b:box("StripeA", -1.6, 0.05, -2.66, -0.8, 0.2, 2.66, C.Cream, FOLIAGE)
	b:box("StripeB", 0.8, 0.05, -2.66, 1.6, 0.2, 2.66, C.Cream, FOLIAGE)
	b:box("Basket", 1.9, 0.1, -1.9, 3.7, 1.3, -0.7, C.Wood)
	b:box("Lid", 1.75, 1.25, -2.05, 3.85, 1.6, -0.55, C.WoodLight)
	return b:finish(blanket)
end

-- Bee boxes (6 parts): three hives (a cream box under a wooden roof) in a row.
local function beeBoxes(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "BeeBoxes", turned(cf, r))
	local first
	for i = 1, 3 do
		local x = (i - 2) * 3.4
		local h = r(2.0, 2.6)
		local box = b:box(`Hive{i}`, x - 1.0, -0.3, -1.0, x + 1.0, h, 1.0, if i == 2 then C.Plaster else C.Cream)
		first = first or box
		b:box(`Roof{i}`, x - 1.3, h - 0.05, -1.3, x + 1.3, h + 0.5, 1.3, if i == 2 then C.RoofTerracotta else C.Wood)
	end
	return b:finish(first)
end

-- Voxel cactus (5-6 parts, for the red-rock mesas' ochre tops): a lime column with two arms in
-- a darker green (a stub out, then up, at two heights) and now and then a bloom on top.
local function cactus(parent: any, cf: any, s: number, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "Cactus", turned(cf, r))
	local h = r(8.5, 10.5)
	local trunk = b:box("Trunk", -1.1 * s, -0.5, -1.1 * s, 1.1 * s, h * s, 1.1 * s, CACTUS[1])
	local y1 = h * r(0.3, 0.4)
	b:box("ArmL", -3.0 * s, y1 * s, -0.7 * s, -1.0 * s, (y1 + 1.4) * s, 0.7 * s, CACTUS[2], FOLIAGE)
	b:box("ArmLUp", -3.0 * s, (y1 + 1.3) * s, -0.7 * s, -1.7 * s, (y1 + r(3.4, 4.4)) * s, 0.7 * s, CACTUS[2], FOLIAGE)
	local y2 = h * r(0.5, 0.6)
	b:box("ArmR", 1.0 * s, y2 * s, -0.6 * s, 2.8 * s, (y2 + 1.3) * s, 0.6 * s, CACTUS[2], FOLIAGE)
	b:box("ArmRUp", 1.5 * s, (y2 + 1.2) * s, -0.6 * s, 2.8 * s, (y2 + r(2.6, 3.4)) * s, 0.6 * s, CACTUS[2], FOLIAGE)
	if r() < 0.7 then
		local bloom = if r() < 0.5 then C.Pink else C.Yellow
		b:box("Bloom", -0.6 * s, h * s - 0.1, -0.6 * s, 0.6 * s, (h + 0.9) * s, 0.6 * s, bloom, FOLIAGE)
	end
	return b:finish(trunk)
end

-- Log pile (3 parts): two logs side by side and one on top.
local function logPile(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "LogPile", turned(cf, r))
	local first = b:box("Log1", -3.2, -0.2, -1.5, 3.0, 1.3, -0.05, C.Bark)
	b:box("Log2", -2.9, -0.2, 0.1, 3.3, 1.25, 1.5, C.BarkDark)
	b:box("Log3", -2.4, 1.1, -0.75, 2.6, 2.5, 0.7, C.Bark)
	return b:finish(first)
end

-- Mushroom ring (6 parts): three mushrooms (cream stem, red / terracotta / red cap).
local function mushrooms(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "Mushrooms", turned(cf, r))
	local first
	local caps = { C.RoofRed, C.RoofTerracotta, C.RoofRed }
	for i, p in { { -2.0, -1.0, 1.0 }, { 1.6, -1.6, 0.8 }, { 0.6, 1.9, 0.65 } } do
		local x, z, s = p[1], p[2], p[3]
		local h = r(1.6, 2.2) * s
		local stem = b:box(`Stem{i}`, x - 0.45 * s, -0.2, z - 0.45 * s, x + 0.45 * s, h, z + 0.45 * s, C.Cream)
		first = first or stem
		b:box(`Cap{i}`, x - 1.3 * s, h - 0.1, z - 1.3 * s, x + 1.3 * s, h + 0.9 * s, z + 1.3 * s, caps[i], FOLIAGE)
	end
	return b:finish(first)
end

--[[
	Raised flower bed (10 parts at 8 studs, 14 at 12): a clipped hedge rim, a soil mound on it and
	two or three leafy rows, each with three separate bloom clumps poking out of the leaves at
	staggered heights and spacings (flowers, not a bar of colour), the rows alternating the two
	colours of one harmonious pair, lined up with cf (rows along local X): a tidy, planted patch
	of colour that reads from the promenade.
]]
local BED_SOIL = C.Dirt
local BED_RIM = C.Leaf0
local function flowerBed(parent: any, cf: any, size: number, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "FlowerBed", cf)
	local h = size / 2
	local rim = b:box("Rim", -h, -0.4, -h, h, 1.1, h, BED_RIM)
	b:box("Soil", -h + 0.8, 0.9, -h + 0.8, h - 0.8, 1.45, h - 0.8, BED_SOIL, Kit.NOSHADOW)
	local rows = if size >= 11 then 3 else 2
	local pitch = (size - 1.6) / rows
	local len = size - 2.4
	local pair = pairOf(r())
	for i = 1, rows do
		local c = pair[(i - 1) % 2 + 1]
		local z = -h + 0.8 + pitch * (i - 0.5)
		b:box(`Leaves{i}`, -len / 2, 1.35, z - 0.6, len / 2, 2.4, z + 0.6, C.Leaf1, FOLIAGE)
		-- three clumps along the row, each 1.2-1.6 wide, sunk into the leaves
		local step = len / 3
		for j = 1, 3 do
			local x = -len / 2 + step * (j - 0.5) + r(-0.25, 0.25) * step
			local w = r(1.2, 1.6)
			local top = 2.9 + r(0, 0.7) + (if (i + j) % 2 == 0 then 0.3 else 0)
			local dz = r(-0.2, 0.2)
			b:box(`Blooms{i}_{j}`, x - w / 2, 2.0, z + dz - 0.75, x + w / 2, top, z + dz + 0.75, c, FOLIAGE)
		end
	end
	return b:finish(rim)
end

-- Wildflower patch (5 parts): a low leafy mat with a mound and three clumps of blooms in one
-- harmonious pair (the big clump in the main colour, the small ones in its partner).
local function meadow(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "FlowerMeadow", turned(cf, r))
	local w, d = r(10, 13), r(7, 9)
	local mat = b:box("Leaves", -w / 2, -0.4, -d / 2, w / 2, 0.9, d / 2, C.Leaf2, FOLIAGE)
	local mx, mz = r(-0.12, 0.12) * w, r(-0.12, 0.12) * d
	b:box("Mound", mx - w * 0.28, 0.5, mz - d * 0.3, mx + w * 0.28, 2.0, mz + d * 0.3, C.Leaf1, FOLIAGE)
	local pair = pairOf(r())
	for i, p in
		{ { mx + r(-0.8, 0.8), mz + r(-0.6, 0.6), 1.4 }, { -w * 0.34, -d * 0.24, 0.6 }, { w * 0.34, d * 0.24, 0.6 } }
	do
		local s = r(1.7, 2.2)
		local col = if i == 1 then pair[1] else pair[2]
		b:box(`Blooms{i}`, p[1] - s / 2, p[3], p[2] - s / 2, p[1] + s / 2, p[3] + s * 0.95, p[2] + s / 2, col, FOLIAGE)
	end
	return b:finish(mat)
end

-- Bush clump (5 parts, 6 with blossoms): a big leafy block with a darker one and a lighter low
-- one merged into its sides and a light top — one ~10-stud shrub mass instead of a dot.
local function bushClump(parent: any, cf: any, s: number, seed: number, bloom: any?): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "BushClump", turned(cf, r))
	local main = b:box("Bush", -3.2 * s, -0.3, -2.6 * s, 2.4 * s, 4.2 * s, 2.4 * s, BUSH[2], CANOPY)
	b:box("Side", 1.6 * s, -0.35, -1.8 * s, 4.6 * s, 3.0 * s, 1.6 * s, BUSH[1], FOLIAGE)
	b:box("Low", -4.6 * s, -0.4, -0.6 * s, -2.2 * s, 2.2 * s, 2.9 * s, BUSH[3], FOLIAGE)
	b:box("Front", -1.4 * s, -0.45, -3.6 * s, 1.0 * s, 2.6 * s, -1.6 * s, BUSH[1], FOLIAGE)
	b:box("Top", -2.0 * s, 4.0 * s, -1.6 * s, 1.2 * s, 5.4 * s, 1.4 * s, BUSH[3], FOLIAGE)
	if bloom then
		b:box("Blossoms", -0.9 * s, 3.4 * s, -2.9 * s, 0.5 * s, 4.6 * s, -2.3 * s, bloom, FOLIAGE)
	end
	return b:finish(main)
end

-- Beach props: a parasol with a towel (4 parts), a sandcastle with a flag (4), a towel with a
-- beach ball (3), driftwood (2), a starfish (2).
local function beachProp(parent: any, cf: any, kind: string, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "BeachProp", cf * CFrame.Angles(0, rad(r(0, 360)), 0))
	local first
	if kind == "parasol" then
		-- canopy and towel: a jewel-tone canopy (a small accent) and a light partner
		local F = C.Flowers
		local cols = {
			{ F[1], C.Cream },
			{ F[7], C.Canvas },
			{ F[2], C.Cream },
			{ F[6], C.Canvas },
		}
		local pair = cols[floor(r(1, #cols + 0.99))]
		first = b:pole("Pole", 0.5, 0, 0, -0.6, 7.0, C.Cream, Kit.NOSHADOW)
		b:box("Canopy", -3.4, 6.3, -3.4, 3.4, 7.2, 3.4, pair[1])
		b:box("CanopyTop", -1.7, 7.15, -1.7, 1.7, 7.9, 1.7, C.Cream, Kit.NOSHADOW)
		b:box("Towel", 1.0, 0, -1.4, 3.6, 0.16, 4.0, pair[2], FOLIAGE)
	elseif kind == "sandcastle" then
		local wet = Kit.lerpColor(C.SandDark, C.Wood, 0.15)
		first = b:box("Base", -2.2, -0.3, -2.2, 2.2, 1.4, 2.2, wet)
		b:box("Tower", -1.2, 1.4, -1.2, 1.2, 3.4, 1.2, lerp(C.Sand, C.White, 0.3))
		b:box("Turret", -0.6, 3.4, -0.6, 0.6, 4.4, 0.6, wet)
		b:box("Flag", 0.6, 3.7, -0.1, 1.7, 4.4, 0.1, C.Flowers[1], FOLIAGE)
	elseif kind == "towel" then
		local blue = r() >= 0.5
		local col = if blue then C.Flowers[7] else C.Flowers[3]
		first = b:box("Towel", -1.4, 0, -2.6, 1.4, 0.16, 2.6, col, FOLIAGE)
		b:box("Stripe", -1.55, -0.1, -0.4, 1.55, 0.24, 0.4, C.Cream, FOLIAGE)
		b:box("Ball", 2.0, -0.1, -0.8, 3.4, 1.3, 0.6, if blue then C.Flowers[1] else C.Flowers[2], FOLIAGE)
	elseif kind == "driftwood" then
		first = b:box("Log", -3.4, -0.3, -0.7, 3.4, 0.9, 0.7, Kit.lerpColor(C.WoodLight, C.White, 0.25))
		b:box("Branch", 0.6, -0.2, 0.6, 1.5, 0.7, 2.8, Kit.lerpColor(C.WoodLight, C.White, 0.2))
	else
		local col = if r() < 0.5 then C.Blossom0 else C.RoofTerracotta
		first = b:box("ArmA", -1.3, -0.1, -0.4, 1.3, 0.3, 0.4, col, FOLIAGE)
		b:box("ArmB", -0.4, -0.1, -1.3, 0.4, 0.42, 1.3, col, FOLIAGE)
	end
	return b:finish(first)
end

--[[
	Coral reef patch (14 parts) on the lagoon bed (cf at the bed, y `bed` <= -6), calm and sunk
	(nothing above y -4: shapes on the bed, seen through the water, not bricks in a pool): an
	irregular pad of pale sand (two slabs crossing at an angle), five coral fingers 1-2 studs wide
	and of mixed heights in terracotta, sand and sage, a low brain-coral head, two seaweed strips,
	a rock, a starfish (two crossed arms) and one small pink tip as the patch's only accent.
]]
local REEF_CORAL = {
	lerp(C.RoofTerracotta, C.Sand, 0.25), -- terracotta
	lerp(C.SandDark, C.Cream, 0.2), -- sand
	lerp(C.Mint2, C.Stone, 0.35), -- sage
	lerp(C.Brick, C.Sand, 0.4), -- dusty rose-brown
}
local REEF_SAND = lerp(C.Sand, C.Cream, 0.3)
local REEF_WEED = lerp(C.Seaweed, C.Stone, 0.2)
local REEF_STAR = lerp(C.Orange, C.RoofTerracotta, 0.5)
local function reefPatch(parent: any, cf: any, bed: number, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "Reef", cf * CFrame.Angles(0, rad(r(-20, 20)), 0))
	local lim = max(1.4, -4 - bed) -- (the tallest top, local: y -4 in the world)
	local pad = b:box("Sand", -5.5, -0.6, -3.5, 4.5, 0.25, 3.0, REEF_SAND, Kit.NOSHADOW)
	b:block(
		"SandB",
		Vector3.new(6.5, 0.75, 8),
		CFrame.new(1.2, -0.2, -0.8) * CFrame.Angles(0, rad(r(25, 40)), 0),
		REEF_SAND,
		Kit.NOSHADOW
	)
	-- a few bubbles rising from the reef (they fade before the surface)
	emitter(pad, "Bubbles", {
		Rate = 1.0,
		Lifetime = U.roblox.NumberRange.new(2.0, 2.8),
		Speed = U.roblox.NumberRange.new(1.2, 1.8),
		SpreadAngle = U.Vector2.new(6, 6),
		Size = seq(0.25, 0.5),
		Transparency = seq(0.3, 0.9),
		Color = U.roblox.ColorSequence.new(C.Foam),
		LightEmission = 0.3,
	})
	-- coral fingers round the middle, the tallest first (its tip gets the pink accent)
	local a0 = r(0, 2 * math.pi)
	local tallest = nil
	for i = 1, 5 do
		local a = a0 + i * 1.25 + r(-0.3, 0.3)
		local d = r(0.8, 3.2)
		local x, z = d * cos(a), d * sin(a)
		local w = r(1.0, 2.0)
		local h = if i == 1 then lim else lim * r(0.45, 0.9)
		local col = REEF_CORAL[(i + floor(r(0, 3.99))) % #REEF_CORAL + 1]
		b:box(`Coral{i}`, x - w / 2, 0.1, z - w / 2, x + w / 2, h, z + w / 2, col, FOLIAGE)
		if i == 1 then
			tallest = { x, z, w, h }
		end
	end
	if tallest then
		local x, z, w, h = tallest[1], tallest[2], tallest[3] * 0.32, tallest[4]
		b:box("Tip", x - w, h - 0.35, z - w, x + w, h + 0.05, z + w, lerp(C.Pink, C.Cream, 0.15), FOLIAGE)
	end
	-- a low brain-coral head, two seaweed strips, a rock, a starfish
	local hx, hz = r(-3.5, -2), r(1, 2.2)
	b:box("Head", hx - 1.3, 0.05, hz - 1.1, hx + 1.3, min(lim, r(0.6, 1.0)), hz + 1.1, REEF_CORAL[1], FOLIAGE)
	for i, p in { { 3.4, -2.2 }, { -4.4, -1.6 } } do
		local h = lim * r(0.7, 1.0)
		b:box(`Weed{i}`, p[1] - 0.2, 0.1, p[2] - 0.5, p[1] + 0.2, h, p[2] + 0.5, REEF_WEED, FOLIAGE)
	end
	b:box("Rock", 2.0, -0.2, 1.2, 4.0, 1.1, 2.9, C.Stone)
	local sx, sz = r(-1.5, 1.5), r(-3.0, -2.2)
	b:box("StarA", sx - 0.9, 0.2, sz - 0.25, sx + 0.9, 0.45, sz + 0.25, REEF_STAR, FOLIAGE)
	b:box("StarB", sx - 0.25, 0.18, sz - 0.9, sx + 0.25, 0.5, sz + 0.9, REEF_STAR, FOLIAGE)
	return b:finish(pad)
end

--------------------------------------------------------------------------------------------
-- Lagoon surface features (2-3 a quadrant): a moored houseboat, a floating fish-farm ring, a
-- rocky islet with a perch; cf on the water surface (y = 0), `bed` the depth below it
--------------------------------------------------------------------------------------------

--[[
	Houseboat (11 parts, bobbing gently): a painted hull with a plank deck, a cream cabin with
	windows on both sides and a door at the bow, a roof in two steps, a stovepipe, a flower box
	on the foredeck; its mooring post (2 parts, a rope to the deck) stands beside it on the bed.
	Along local Z (bow -Z).
]]
local function houseboat(parent: any, cf: any, bed: number, seed: number): any
	local r = Kit.rng(seed)
	local m = U.model(parent, "Houseboat")
	local paint = C.BoatPaint[floor(r(1, #C.BoatPaint + 0.99))]
	if paint == C.BoatPaint[5] then
		paint = C.BoatPaint[2] -- (a white hull would vanish against the cabin)
	end
	local roof = if r() < 0.5 then C.RoofRed else C.RoofTerracotta
	local b = Kit.builder(m, "Boat", cf)
	local hull = b:box("Hull", -3.5, -0.9, -8, 3.5, 0.8, 8, paint)
	b:box("Deck", -3.2, 0.75, -7.7, 3.2, 1.05, 7.7, C.Plank)
	b:box("Cabin", -2.6, 1.0, -4.0, 2.6, 4.8, 4.6, C.Plaster)
	b:box("Roof", -3.3, 4.75, -4.7, 3.3, 5.35, 5.3, roof)
	b:box("RoofTop", -2.3, 5.3, -3.6, 2.3, 5.9, 4.2, Kit.shade(roof, 0.88), Kit.NOSHADOW)
	b:box("WindowL", -2.78, 2.4, -2.4, -2.55, 3.8, 2.9, C.WindowBlue, FOLIAGE)
	b:box("WindowR", 2.55, 2.4, -2.4, 2.78, 3.8, 2.9, C.WindowBlue, FOLIAGE)
	b:box("Door", -0.8, 1.0, -4.18, 0.8, 3.9, -3.95, C.WoodDark, Kit.NOSHADOW)
	b:box("Pipe", 1.2, 5.85, 2.0, 1.8, 7.4, 2.6, C.Iron, Kit.NOSHADOW)
	b:box("FlowerBox", -2.4, 1.0, -7.3, -0.4, 1.7, -6.3, C.Wood, Kit.NOSHADOW)
	b:box("Blooms", -2.2, 1.65, -7.1, -0.6, 2.35, -6.5, pairOf(r())[1], FOLIAGE)
	b:finish(hull)
	b.model:SetAttribute("Bob", 0.15)
	b.model:SetAttribute("BobPeriod", 4.6)
	-- the mooring post on the shore side (+X) and a rope from it to the deck
	local post = U.part(
		m,
		"MooringPost",
		Vector3.new(0.9, bed + 3.2, 0.9),
		cf * CFrame.new(5.4, (3.2 - bed) / 2, -1.5),
		C.WoodDark,
		nil,
		Kit.NOSHADOW
	)
	local a, c = (cf * CFrame.new(5.4, 2.6, -1.5)).Position, (cf * CFrame.new(3.0, 1.3, -3.5)).Position
	U.part(m, "Rope", Vector3.new(0.2, 0.2, (c - a).Magnitude), CFrame.lookAt((a + c) / 2, c), C.Rope, nil, FOLIAGE)
	m.PrimaryPart = post
	return m
end

--[[
	Floating fish-farm ring (13 parts): a square collar of dark floating pipe with plank walkways
	along two sides, a dark net just under the surface inside it, a float on every corner (orange
	and cream) and a feeder post with a hopper box on one corner. Bobbing gently.
]]
local FARM_COLLAR = lerp(C.Iron, C.Navy, 0.3)
local FARM_NET = lerp(C.Seaweed, C.Navy, 0.55)
local function fishFarm(parent: any, cf: any, seed: number): any
	local b = Kit.builder(parent, "FishFarm", cf)
	local R, w = 7, 1.0
	local first = b:box("CollarN", -R, -0.3, R - w, R, 0.5, R, FARM_COLLAR)
	b:box("CollarS", -R, -0.3, -R, R, 0.5, -R + w, FARM_COLLAR)
	b:box("CollarW", -R, -0.25, -R + w, -R + w, 0.45, R - w, FARM_COLLAR)
	b:box("CollarE", R - w, -0.25, -R + w, R, 0.45, R - w, FARM_COLLAR)
	-- plank walkways along two sides
	b:box("WalkN", -R + 0.6, 0.5, R - 1.6, R - 0.6, 0.8, R + 0.4, C.Plank, Kit.NOSHADOW)
	b:box("WalkS", -R + 0.6, 0.5, -R - 0.4, R - 0.6, 0.8, -R + 1.6, C.Plank, Kit.NOSHADOW)
	b:box("Net", -R + w, -0.65, -R + w, R - w, -0.2, R - w, FARM_NET, FOLIAGE)
	for i, p in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		local x, z = p[1] * (R + 0.3), p[2] * (R + 0.3)
		b:box(`Float{i}`, x - 0.75, -0.3, z - 0.75, x + 0.75, 1.0, z + 0.75, if i % 2 == 1 then C.Orange else C.Cream)
	end
	b:box("FeederPost", R - 2.2, 0.45, -R + 0.15, R - 1.5, 4.0, -R + 0.85, C.WoodDark, Kit.NOSHADOW)
	b:box("FeederBox", R - 2.6, 3.9, -R - 0.25, R - 1.1, 5.0, -R + 1.25, C.WoodLight, Kit.NOSHADOW)
	b:finish(first)
	b.model:SetAttribute("Bob", 0.12)
	b.model:SetAttribute("BobPeriod", 3.8 + (seed % 5) * 0.2)
	return b.model
end

--[[
	A small rocky islet with a perch (9 parts): two warm rocks and a darker one rising from the bed,
	a moss cap and a tuft, a wooden perch post with a crossbar and a little pennant on top, a ring
	of foam.
]]
local function rockyIslet(parent: any, cf: any, bed: number, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "RockyIslet", cf * CFrame.Angles(0, rad(90 * floor(r(0, 3.99))), 0))
	local first = b:box("Rock1", -5.5, -bed, -4, 4.5, 2.2, 4.5, ROCK)
	b:box("Rock2", -2.5, 2.0, -2.5, 3.0, 4.4, 2.0, lerp(ROCK, C.Limestone, 0.45))
	b:box("Rock3", 3.8, -bed, -5.5, 7.2, 1.3, -2.0, ROCK_DARK)
	b:box("Moss", -2.2, 4.3, -2.2, 1.6, 4.8, 1.2, C.Leaf2, Kit.NOSHADOW)
	b:box("Tuft", -5.0, 2.1, 1.4, -2.9, 3.3, 3.8, C.Leaf1, FOLIAGE)
	b:box("Perch", 1.8, 4.3, 0.6, 2.4, 10.5, 1.2, C.WoodDark)
	b:box("Crossbar", 0.8, 9.9, 0.7, 3.4, 10.35, 1.1, C.Wood, Kit.NOSHADOW)
	b:box("Pennant", 2.4, 8.4, 0.8, 4.2, 9.5, 1.0, C.Flowers[1], FOLIAGE)
	b:box("Foam", -8, 0.1, -7.5, 8.5, 0.3, 6.5, FOAM, FOLIAGE)
	return b:finish(first)
end

--------------------------------------------------------------------------------------------
-- Coastal set pieces (7-16 parts): small scenes of island life on the outer beaches and cliff
-- tops, where the hill viewpoints look; cf on the ground, front -Z to the sea. Calm wood, plaster
-- and canvas with one small jewel accent each (a door, a canoe, a pennant, a flower box).
--------------------------------------------------------------------------------------------

local HUT_ROOFS = { C.RoofTerracotta, C.RoofBlue, C.RoofRed, C.RoofGreen }
local JEWEL = C.Flowers -- red, yellow, pink, violet, white, orange, blue
local ACCENTS = { JEWEL[1], JEWEL[7], JEWEL[2], JEWEL[6] }
-- fishing net hung to dry: a light rope-green mesh, a little see-through
local NET = lerp(C.RoofGreen, C.Rope, 0.5)
local NET_MESH = { CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.3 }
local DUNE_GRASS = { lerp(C.Leaf2, C.Straw, 0.3), lerp(C.Leaf3, C.StrawLight, 0.35) }
local SILVER = lerp(C.Iron, C.Glass, 0.55)

-- The coastal set pieces are drawn at SHORE_SCALE: a builder whose box / pole / lean
-- coordinates are scaled about the frame's origin (they read from the hill viewpoints).
local SHORE_SCALE = 1.3
local function shoreBuilder(parent: any, name: string, cf: any): any
	local b = Kit.builder(parent, name, cf)
	local k = SHORE_SCALE
	local sb = { model = b.model }
	function sb.box(_: any, n: string, x0, y0, z0, x1, y1, z1, color, extra): any
		return b:box(n, x0 * k, y0 * k, z0 * k, x1 * k, y1 * k, z1 * k, color, extra)
	end
	function sb.pole(_: any, n: string, d: number, x: number, z: number, y0: number, y1: number, color, extra): any
		return b:pole(n, d * k, x * k, z * k, y0 * k, y1 * k, color, extra)
	end
	-- a thin block from (y0, z0) to (y1, z1) at x (ladders, paddles)
	function sb.lean(_: any, n: string, x, y0, z0, y1, z1, w, d, color): any
		local dy, dz = (y1 - y0) * k, (z1 - z0) * k
		return b:block(
			n,
			Vector3.new(w * k, sqrt(dy * dy + dz * dz), d * k),
			CFrame.new(x * k, (y0 + y1) / 2 * k, (z0 + z1) / 2 * k) * CFrame.Angles(math.atan2(dz, dy), 0, 0),
			color,
			FOLIAGE
		)
	end
	function sb.finish(_: any, first: any): any
		return b:finish(first)
	end
	return sb
end

-- A stepped roof in three layers (a voxel hip roof) over x ±hx, z z0..z1 from y.
local function steppedRoof(b: any, hx: number, z0: number, z1: number, y: number, color: any)
	local zc, hz = (z0 + z1) / 2, (z1 - z0) / 2
	b:box("Roof1", -hx, y, zc - hz, hx, y + 1.1, zc + hz, color)
	b:box("Roof2", -hx + 1.0, y + 1.05, zc - hz + 1.3, hx - 1.0, y + 2.15, zc + hz - 1.3, lerp(color, C.Cream, 0.12))
	b:box("Roof3", -hx + 2.1, y + 2.1, zc - hz * 0.35, hx - 2.1, y + 3.0, zc + hz * 0.35, color, Kit.NOSHADOW)
end

-- Fisherman's hut on stilts (16 parts): four stilts, a plank deck with a porch on the sea side, a
-- weathered plank hut with a painted door and a window, a stepped roof with a pennant, a ladder
-- down to the sand, a net hung to dry on the porch.
local function stiltHut(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = shoreBuilder(parent, "StiltHut", cf)
	local first
	for i, p in { { -4, -2.4 }, { 4, -2.4 }, { -4, 3.2 }, { 4, 3.2 } } do
		local post = b:box(`Stilt{i}`, p[1] - 0.55, -1.6, p[2] - 0.55, p[1] + 0.55, 3.5, p[2] + 0.55, C.WoodDark)
		first = first or post
	end
	b:box("Deck", -5.4, 3.4, -7.4, 5.4, 4.0, 4.2, C.Plank)
	b:box("Walls", -4.2, 4.0, -2.8, 4.2, 9.4, 3.6, C.WoodLight)
	local accent = ACCENTS[floor(r(1, #ACCENTS + 0.99))]
	b:box("Door", -1.0, 4.0, -2.98, 1.0, 7.8, -2.72, accent, Kit.NOSHADOW)
	b:box("Window", 1.9, 5.8, -2.98, 3.3, 7.4, -2.72, C.WindowBlue, FOLIAGE)
	local roof = HUT_ROOFS[floor(r(1, #HUT_ROOFS + 0.99))]
	steppedRoof(b, 5.2, -4.0, 4.8, 9.4, roof)
	b:box("PennantPole", -0.2, 12.3, 0.2, 0.2, 15.2, 0.6, C.Cream, FOLIAGE)
	b:box("Pennant", 0.2, 13.8, 0.3, 2.6, 15.0, 0.5, accent, FOLIAGE)
	b:lean("Ladder", -3.4, -0.2, -10.2, 3.9, -7.3, 1.6, 0.35, C.Wood)
	b:box("NetPole", 4.3, 4.0, -7.0, 4.8, 8.8, -6.5, C.WoodDark, FOLIAGE)
	b:box("Net", 1.4, 5.2, -6.9, 4.3, 8.4, -6.65, NET, NET_MESH)
	return b:finish(first)
end

-- Beach camp (12 parts): a stepped ridge tent in a faded jewel canvas with a dark doorway facing
-- the sea, a campfire (stone ring, logs, a small flame with smoke), two log seats and a painted
-- canoe pulled up on the sand with its paddle.
local TENTS = { lerp(JEWEL[6], C.Canvas, 0.35), lerp(C.Cyan, C.Canvas, 0.3), lerp(JEWEL[1], C.Canvas, 0.4) }
local function beachCamp(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = shoreBuilder(parent, "BeachCamp", cf)
	local tent = TENTS[floor(r(1, #TENTS + 0.99))]
	-- the tent (ridge along Z, its door at the -Z end), a little to the side of the fire
	local tx = -2.5
	local first = b:box("Tent1", tx - 2.8, -0.2, -3.0, tx + 2.8, 1.6, 3.0, tent)
	b:box("Tent2", tx - 1.9, 1.55, -3.0, tx + 1.9, 3.0, 3.0, Kit.shade(tent, 0.94))
	b:box("Tent3", tx - 0.9, 2.95, -3.0, tx + 0.9, 4.0, 3.0, tent, Kit.NOSHADOW)
	b:box("Doorway", tx - 0.9, -0.1, -3.12, tx + 0.9, 2.4, -2.9, C.Dark, FOLIAGE)
	-- the campfire in front, the log seats round it
	local fx, fz = 1.2, -5.4
	b:box("FireStones", fx - 1.3, -0.2, fz - 1.3, fx + 1.3, 0.45, fz + 1.3, C.StoneDark, Kit.NOSHADOW)
	b:box("FireLogs", fx - 0.9, 0.4, fz - 0.35, fx + 0.9, 0.9, fz + 0.35, C.BarkDark, FOLIAGE)
	local flame = b:box("Flame", fx - 0.4, 0.7, fz - 0.4, fx + 0.4, 1.7, fz + 0.4, C.Flame, Kit.NEON_DECOR)
	Kit.smoke(flame, { rate = 1.4, size = 1.0, rise = 2.5 })
	b:box("SeatA", fx - 4.4, -0.2, fz - 1.4, fx - 3.0, 1.0, fz + 1.4, C.Bark)
	b:box("SeatB", fx + 2.8, -0.2, fz - 1.4, fx + 4.2, 1.0, fz + 1.4, C.Bark)
	-- the canoe on the sand beside the tent, its paddle leaning on the hull
	local paint = ACCENTS[floor(r(1, #ACCENTS + 0.99))]
	b:box("Canoe", 4.2, -0.2, -2.6, 5.9, 0.9, 4.4, paint)
	b:box("CanoeInner", 4.5, 0.85, -2.1, 5.6, 1.0, 3.9, C.WoodLight, FOLIAGE)
	b:lean("Paddle", 6.3, -0.2, 2.6, 2.6, 0.6, 0.35, 0.9, C.WoodLight)
	return b:finish(first)
end

-- Drying racks (11 parts): a net hung over a bar on two posts, a rack of fish on two posts, a
-- basket of floats in a jewel colour.
local function dryingRacks(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = shoreBuilder(parent, "DryingRacks", cf)
	local first = b:box("NetPostA", -6.4, -0.6, -0.3, -5.8, 5.2, 0.3, C.WoodDark)
	b:box("NetPostB", -1.4, -0.6, -0.3, -0.8, 5.2, 0.3, C.WoodDark)
	b:box("NetBar", -6.6, 4.7, -0.25, -0.6, 5.1, 0.25, C.Wood, Kit.NOSHADOW)
	b:box("Net", -5.8, 1.4, -0.3, -1.4, 4.75, 0.3, NET, NET_MESH)
	b:box("FishPostA", 1.6, -0.6, -0.3, 2.2, 4.8, 0.3, C.WoodDark)
	b:box("FishPostB", 6.6, -0.6, -0.3, 7.2, 4.8, 0.3, C.WoodDark)
	b:box("FishBar", 1.4, 4.3, -0.2, 7.4, 4.7, 0.2, C.Wood, Kit.NOSHADOW)
	b:box("FishA", 3.1, 2.1, -0.2, 3.7, 4.3, 0.2, SILVER, FOLIAGE)
	b:box("FishB", 5.0, 2.4, -0.2, 5.6, 4.3, 0.2, C.Gold, FOLIAGE)
	b:box("Basket", 2.6, -0.2, -3.4, 4.6, 1.3, -1.6, C.Wood)
	b:box("Floats", 2.9, 1.25, -3.1, 4.3, 1.9, -1.9, ACCENTS[floor(r(1, #ACCENTS + 0.99))], FOLIAGE)
	return b:finish(first)
end

-- Keeper's cottage (14 parts): a little plastered cottage on a stone plinth with a painted door,
-- two windows and a flower box in jewel blooms, a stepped roof and a brick chimney, a flag on a
-- pole beside it (the coast watch).
local function keeperCottage(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = shoreBuilder(parent, "KeeperCottage", cf)
	local first = b:box("Plinth", -5.6, -1.2, -4.6, 5.6, 0.8, 4.6, C.StoneLight)
	b:box("Walls", -5.0, 0.8, -4.0, 5.0, 7.0, 4.0, C.Plaster)
	local accent = ACCENTS[floor(r(1, #ACCENTS + 0.99))]
	b:box("Door", -3.6, 0.8, -4.15, -1.8, 4.6, -3.9, accent, Kit.NOSHADOW)
	b:box("WindowA", 0.4, 3.0, -4.15, 2.4, 5.2, -3.9, C.WindowBlue, FOLIAGE)
	b:box("WindowB", -5.15, 3.0, -1.0, -4.9, 5.2, 1.0, C.WindowBlue, FOLIAGE)
	b:box("FlowerBox", 0.2, 2.2, -4.7, 2.6, 2.9, -3.95, C.Wood, Kit.NOSHADOW)
	b:box("Blooms", 0.4, 2.85, -4.55, 2.4, 3.5, -4.1, JEWEL[floor(r(1, 3.99)) * 2 - 1], FOLIAGE)
	steppedRoof(b, 6.0, -5.1, 5.1, 7.0, if r() < 0.5 then C.RoofSlate else C.RoofRed)
	b:box("Chimney", 2.4, 8.0, 1.4, 3.6, 11.6, 2.6, C.Brick)
	b:pole("FlagPole", 0.5, 7.6, -3.4, -0.5, 13.5, C.Cream, Kit.NOSHADOW)
	b:box("Flag", 7.85, 10.9, -3.5, 11.2, 13.1, -3.3, accent, FOLIAGE)
	return b:finish(first)
end

-- Boulder pile with dune grass (7 parts): three warm beach rocks of falling sizes, a moss cap,
-- three tall tufts of dune grass round them.
local function boulderPile(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = shoreBuilder(parent, "BoulderPile", turned(cf, r))
	local light = lerp(BEACH_ROCK, C.Limestone, 0.35)
	local first = b:box("BoulderA", -3.4, -0.6, -2.6, 1.6, r(3.2, 3.8), 2.4, BEACH_ROCK)
	b:box("BoulderB", 1.3, -0.6, -1.4, 4.4, r(2.0, 2.5), 2.0, light)
	b:box("BoulderC", -2.2, -0.6, 2.3, 0.2, 1.4, 4.2, Kit.shade(BEACH_ROCK, 0.86))
	b:box("Moss", -2.8, 3.1, -1.9, 0.6, 3.9, 1.6, C.Leaf2, Kit.NOSHADOW)
	for i, p in { { 4.6, -2.6 }, { -4.6, 1.4 }, { 2.4, 3.2 } } do
		local h = r(2.2, 3.4)
		b:box(`Grass{i}`, p[1] - 0.6, -0.3, p[2] - 0.5, p[1] + 0.6, h, p[2] + 0.5, DUNE_GRASS[i % 2 + 1], FOLIAGE)
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

-- Map children whose parts Nature keeps clear of (their bounding boxes).
local OBSTACLE_MODELS =
	{ Bridges = true, Promenade = true, Gateways = true, Landmarks = true, Lagoon = true, Ocean = true }
local OB = 16

local function sortBy(list: { any }, key: string)
	table.sort(list, function(a, b)
		if a[key] ~= b[key] then
			return a[key] > b[key]
		end
		return a.s.x + a.s.z * 1e-3 < b.s.x + b.s.z * 1e-3
	end)
end

function Nature.build(map: any, cfg: any, world: any, budget: number): { [string]: number }
	local nature = U.model(map, "Nature")
	local groups = {
		trees = U.model(nature, "Trees"),
		plants = U.model(nature, "Plants"),
		rocks = U.model(nature, "Rocks"),
		sets = U.model(nature, "SetPieces"),
	}
	local counts: { [string]: number } = {}
	local G = cfg.GroundTop
	local inner = cfg.PromenadeRadius + cfg.PromenadeWidth + 6
	local maxR = cfg.RingOuterRadius + 140 -- (the outer mountains reach r ~730)
	local partsBefore = U.partCount
	local function spentAll(): number
		return U.partCount - partsBefore
	end
	local function affordable(n: number): boolean
		return spentAll() + n <= budget
	end
	local function count(k: string)
		counts[k] = (counts[k] or 0) + 1
	end

	-- Bounding boxes of the dressing built before Nature (hashed on a 16-stud grid).
	local obstacles: { [number]: { { number } } } = {}
	for _, child in map:GetChildren() do
		if OBSTACLE_MODELS[child.Name] then
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					local cf, size = d.CFrame, d.Size
					local p = cf.Position
					local rx, ry, rz = cf.RightVector, cf.UpVector, cf.LookVector
					local ex = (abs(rx.X) * size.X + abs(ry.X) * size.Y + abs(rz.X) * size.Z) / 2
					local ey = (abs(rx.Y) * size.X + abs(ry.Y) * size.Y + abs(rz.Y) * size.Z) / 2
					local ez = (abs(rx.Z) * size.X + abs(ry.Z) * size.Y + abs(rz.Z) * size.Z) / 2
					if ex < 300 and ez < 300 then
						local box = { p.X - ex, p.X + ex, p.Y - ey, p.Y + ey, p.Z - ez, p.Z + ez }
						for ix = floor(box[1] / OB), floor(box[2] / OB) do
							for iz = floor(box[5] / OB), floor(box[6] / OB) do
								local k = (ix + 200) * 1000 + iz + 200
								local list = obstacles[k]
								if not list then
									list = {}
									obstacles[k] = list
								end
								table.insert(list, box)
							end
						end
					end
				end
			end
		end
	end
	-- Does a part of the other dressing reach into the box (x ± half, y0..y1, z ± half)?
	local function blocked(x: number, z: number, half: number, y0: number, y1: number): boolean
		for ix = floor((x - half) / OB), floor((x + half) / OB) do
			for iz = floor((z - half) / OB), floor((z + half) / OB) do
				local list = obstacles[(ix + 200) * 1000 + iz + 200]
				if list then
					for _, o in list do
						if
							o[1] < x + half
							and o[2] > x - half
							and o[5] < z + half
							and o[6] > z - half
							and o[3] < y1
							and o[4] > y0
						then
							return true
						end
					end
				end
			end
		end
		return false
	end
	-- Horizontal distance from (x, z) to the nearest part of the other dressing (capped).
	local function obstacleDistance(x: number, z: number, cap: number): number
		local best = cap
		for ix = floor((x - cap) / OB), floor((x + cap) / OB) do
			for iz = floor((z - cap) / OB), floor((z + cap) / OB) do
				local list = obstacles[(ix + 200) * 1000 + iz + 200]
				if list then
					for _, o in list do
						local dx = max(o[1] - x, 0, x - o[2])
						local dz = max(o[5] - z, 0, z - o[6])
						best = min(best, sqrt(dx * dx + dz * dz))
					end
				end
			end
		end
		return best
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
							-- palms may cross fronds (pairs on the beaches); other trees
							-- only touch within a group, and their square canopies keep apart
							-- along x or z as well (no corners overlapping on the diagonal)
							local palms = fam == "palm" and o[5] == "palm"
							local k = if palms then 0.62 elseif fam ~= o[5] then 1.0 else 0.8
							need = k * (canopy + o[3])
							if not palms and max(abs(dx), abs(dz)) < (k + 0.02) * (canopy + o[3]) then
								return false
							end
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
	-- Distance from (x, z) to the edge of the nearest placed object (capped at `cap`).
	local function nearest(x: number, z: number, cap: number): number
		local best = cap
		local n = math.ceil((cap + 16) / HASH)
		local cx, cz = floor(x / HASH), floor(z / HASH)
		for ix = cx - n, cx + n do
			for iz = cz - n, cz + n do
				local list = placed[(ix + 200) * 1000 + iz + 200]
				if list then
					for _, o in list do
						local dx, dz = x - o[1], z - o[2]
						local extent = if o[3] > 0 then 0.75 * o[3] else o[4]
						best = min(best, max(0, sqrt(dx * dx + dz * dz) - extent))
					end
				end
			end
		end
		return best
	end
	-- How far (x, z) is from anything at all: Nature, the other dressing, the plots and plazas
	-- (their bases and props fill them), capped at `cap`.
	local function emptiness(x: number, z: number, cap: number): number
		if world:isReserved(x, z, -6) or Kit.isClaimed(x, z, 0) then
			return 0
		end
		return min(nearest(x, z, cap), obstacleDistance(x, z, cap))
	end

	-- The ground under a footprint of half-width `half` round (x, z) is one dry column top h.
	local DIRS8 = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }
	local function flatAt(x: number, z: number, half: number): number?
		local h, _, water = world:surfaceAt(x, z)
		if water then
			return nil
		end
		for _, d in DIRS8 do
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
		for _, d in DIRS8 do
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
	-- Nothing round a tree on ground h rises into its canopy (bottom `bottom` above h, half-width
	-- R): a terrace step or a stone column next to it would cut through the foliage.
	-- (the canopy blocks are squares: a 5 x 5 grid over the whole square, corners included)
	local function clearCanopy(x: number, z: number, h: number, R: number, bottom: number): boolean
		local limit = h + bottom - 0.3
		for i = -2, 2 do
			for j = -2, 2 do
				if world:heightAt(x + i * R / 2, z + j * R / 2) > limit then
					return false
				end
			end
		end
		return true
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
	local COST = {
		full = 16,
		lite = 10,
		far = 7,
		tuft = 3,
		shrub = 3,
		rock = 4,
		hay = 3,
		fence = 4,
		meadow = 5,
		cactus = 6,
		drift = 14,
	}
	local fullTrees = 0
	local seedRng = Kit.rng(9001)

	-- The mountains (by angle) and the one whose foot (plus `pad`) holds (x, z), if any: its
	-- style picks the trees — snowy pines on the snow peaks, plain pines and round trees on the
	-- green hill, palms, autumn trees and cacti on the red-rock mesas.
	local peaks = {}
	for _, site in world.landmarks do
		if site.peak then
			table.insert(peaks, site)
		end
	end
	table.sort(peaks, function(a, b)
		return a.angle < b.angle
	end)
	local function peakAt(x: number, z: number, pad: number): any
		local best, bestD = nil, math.huge
		for _, p in peaks do
			local d = sqrt((x - p.x) ^ 2 + (z - p.z) ^ 2)
			if d < p.mountainRadius + pad and d < bestD then
				best, bestD = p, d
			end
		end
		return best
	end
	-- An ochre mesa top (red-rock column above y 40): only a few palms and autumn trees there
	-- (MESA_TREES per mesa), a few cacti and boulders.
	local MESA_TREES = 5
	local mesaTrees = {}
	local function mesaTop(x: number, z: number, h: number): any
		if h > 40 and world:kindAt(x, z) == "redrock" then
			return peakAt(x, z, 0)
		end
		return nil
	end

	-- Places a tree of `kind` ("oak" | "round" | "deep" | "mint" | "birch" | "pine" |
	-- "snowPine" | "palm", or an accent: "cherry" | "autumn" | "gold") at (x, z) if it fits;
	-- `level` = "full" | "lite" | "far"; `fam` = its group (trees of one group may touch).
	-- Accent kinds turn into green round trees once ACCENT_CAP accent trees stand. Returns the
	-- parts spent (0 = none).
	local accentTrees = 0
	local function tree(x: number, z: number, kind: string, level: string, fam: string, scale: number?): number
		if level == "full" and fullTrees >= FULL_CAP then
			level = "lite"
		end
		if ACCENT_KIND[kind] and accentTrees >= ACCENT_CAP then
			kind = "round"
		end
		local s
		if level == "full" then
			s = seedRng(1.35, 1.7)
		elseif level == "lite" then
			s = seedRng(1.8, 2.3)
		else
			s = seedRng(1.6, 2.5)
		end
		s = scale or s
		if
			level == "far"
			and x * x + z * z > FAR_R * FAR_R
			and THINNED[fam] ~= false
			and string.sub(fam, 1, 4) ~= "belt"
			and string.sub(fam, 1, 5) ~= "wedge"
		then
			-- the far belt (the woods there; not the plots' tree lines, the gateway wedges, the
			-- skyline crests, the mountains' own trees or the beach palms): one spot in four stays
			-- open, the others get a bigger tree
			if (floor(x / 6) * 73 + floor(z / 6) * 151) % 4 == 0 then
				return 0
			end
			s *= FAR_SCALE
		end
		local seed = floor(seedRng(1, 1e6))
		if kind == "snowPine" then
			-- snow-dusted pines only on the snowy mountains
			local pk = peakAt(x, z, 30)
			if not pk or pk.style ~= "snow" then
				kind = "pine"
			end
		end
		local pine = kind == "pine" or kind == "snowPine"
		local canopy, bottom
		if level == "far" then
			canopy = (if pine then CANOPY_R.farPine elseif kind == "palm" then CANOPY_R.farPalm else CANOPY_R.far) * s
			bottom = (
				if pine
					then CANOPY_BOTTOM.farPine
					elseif kind == "palm" then CANOPY_BOTTOM.farPalm
					else CANOPY_BOTTOM.far
			) * s
		else
			local base = if kind == "snowPine"
				then "pine"
				elseif kind == "gold" then "autumn"
				elseif kind == "deep" or kind == "mint" then "round"
				else kind
			canopy = (CANOPY_R[base] or 6.2) * s * (if level == "full" and not pine then 1.15 else 1)
			local ps = if kind == "palm" then 0.85 else 1
			bottom = (
				if pine
					then CANOPY_BOTTOM.pine
					elseif kind == "palm" then CANOPY_BOTTOM.palm
					elseif kind == "birch" then CANOPY_BOTTOM.birch
					else CANOPY_BOTTOM.broad
			)
				* s
				* ps
		end
		if not affordable(COST[level]) or not freeLand(x, z, canopy) then
			return 0
		end
		local h = flatAt(x, z, TRUNK_R[level] * s + 0.4) -- (trunk sides clear of any riser)
		if not h or not fits(x, z, canopy, 0, fam) or not clearCanopy(x, z, h, canopy, bottom) then
			return 0
		end
		local mesa = mesaTop(x, z, h)
		if mesa and (mesaTrees[mesa] or 0) >= MESA_TREES then
			return 0
		end
		-- the trunk and the canopy keep off the other dressing
		if
			blocked(x, z, TRUNK_R[level] * s, h + 0.3, h + bottom)
			or blocked(x, z, canopy * 0.85, h + bottom, h + bottom + 10 * s)
		then
			return 0
		end
		local before = U.partCount
		local cf = CFrame.new(x, h, z) -- props add quarter turns: forests stay on the grid
		if level == "far" then
			-- (each species keeps its own green at a distance: oaks leaf green, round trees deep,
			-- birches fresh on white trunks)
			-- (the beach palms get drooping fronds)
			local far = if kind == "oak"
				then "green"
				elseif kind == "round" then "deep"
				elseif kind == "palm" and fam == "palm" then "beachPalm"
				else kind
			Nature.farTree(groups.trees, cf, far, s, seed)
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
				m = Kit.prop("oakTree", groups.trees, cf, { seed = seed, scale = s, lite = lite, compact = lite })
			elseif kind == "round" or kind == "mint" then
				m = Kit.prop("roundTree", groups.trees, cf, {
					seed = seed,
					scale = s,
					lite = lite,
					compact = lite,
					palette = if kind == "mint" then "mint" else "mixed",
				})
			elseif kind == "deep" then
				m = Kit.prop(
					"oakTree",
					groups.trees,
					cf,
					{ seed = seed, scale = s, lite = lite, compact = lite, leaves = PAL.deep, fruit = false }
				)
			elseif kind == "birch" then
				m = Kit.prop("birchTree", groups.trees, cf, { seed = seed, scale = s, lite = lite })
			elseif kind == "cherry" then
				m = Kit.prop("cherryTree", groups.trees, cf, { seed = seed, scale = s, lite = lite, compact = lite })
			elseif kind == "gold" then
				m = Kit.prop(
					"autumnTree",
					groups.trees,
					cf,
					{ seed = seed, scale = s, lite = lite, compact = lite, leaves = PAL.gold }
				)
			elseif kind == "palm" then
				m = Kit.prop("palmTree", groups.trees, cf, { seed = seed, scale = s * 0.85, lite = lite })
			else
				m = Kit.prop(
					"autumnTree",
					groups.trees,
					cf,
					{ seed = seed, scale = s, lite = lite, compact = lite, leaves = PAL.autumn }
				)
			end
			settleLitter(m)
			shadows(m)
			if level == "full" then
				fullTrees += 1
			end
		end
		addPlaced(x, z, canopy, 0, fam)
		if mesa then
			mesaTrees[mesa] = (mesaTrees[mesa] or 0) + 1
		end
		if ACCENT_KIND[kind] then
			accentTrees += 1
		end
		count(kind)
		count(level)
		return U.partCount - before
	end

	-- Small things: "tuft" | "shrub" | "rock" | "hay" | "fence" | "meadow" | "cactus" (footprint
	-- radius by kind and size). opts: scale, gap (extra clearance), margin (distance kept from
	-- reserved ground; small decor may hug the paths and plots), berry (shrubs), cap / color
	-- (rocks), yaw (fences), white (fences).
	local function small(x: number, z: number, kind: string, opts: { [string]: any }?): number
		local o = opts or {}
		local seed = floor(seedRng(1, 1e6))
		local s = o.scale or 1
		local radius = if kind == "tuft"
			then 2.2 * s
			elseif kind == "shrub" then 2.5 * s
			elseif kind == "rock" then 3.4 * s + 0.6
			elseif kind == "hay" then 3.4
			elseif kind == "fence" then 5.2
			elseif kind == "meadow" then 6.6
			elseif kind == "drift" then 4.2
			elseif kind == "cactus" then 3 * s + 0.4
			else 3
		if not affordable(COST[kind]) then
			return 0
		end
		local margin = o.margin or max(5, radius * 0.6)
		if world:isReserved(x, z, margin) or Kit.isClaimed(x, z, max(2, radius * 0.6)) or not offPath(x, z, radius) then
			return 0
		end
		local h = flatAt(x, z, radius) -- (the whole footprint: nothing overhangs a step)
		if not h or not fits(x, z, 0, radius + (o.gap or 1), kind) then
			return 0
		end
		local height = if kind == "cactus"
			then 11 * s
			elseif kind == "fence" or kind == "hay" or kind == "rock" then 5
			else 3.5
		if blocked(x, z, radius, h + 0.2, h + height) then
			return 0
		end
		local before = U.partCount
		local cf = CFrame.new(x, h, z)
		if kind == "tuft" then
			tuft(groups.plants, cf, s, seed, o.pair)
		elseif kind == "shrub" then
			shrub(groups.plants, cf, s, seed, o.berry)
		elseif kind == "meadow" then
			meadow(groups.plants, cf, seed)
		elseif kind == "drift" then
			-- a drift of wildflowers on stems in one jewel pair (Props.flowerBed without a kerb),
			-- lined up with the path (o.yaw)
			Kit.prop("flowerBed", groups.plants, cf * CFrame.Angles(0, rad(o.yaw or 0), 0), {
				seed = seed,
				width = 6.4,
				depth = 4.2,
				spacing = 1.9,
				kerb = false,
				leaves = C.Leaf2,
				colors = o.pair or pairOf(seedRng()),
				max = 6,
			})
		elseif kind == "hay" then
			hayBales(groups.sets, cf, seed)
		elseif kind == "fence" then
			fence(groups.sets, cf * CFrame.Angles(0, rad(o.yaw or 0), 0), 8, o.white == true)
		elseif kind == "cactus" then
			cactus(groups.plants, cf, s, seed)
		else
			rock(groups.rocks, cf, s, seed, { cap = o.cap, color = o.color, pebble = o.pebble })
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

	-- the sites within `radius` of a point (closest first, ragged edges): groves and crest woods
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

	local fall = world.landmarks.Waterfall
	local function onMesa(x: number, z: number, h: number): boolean
		if not fall or h < G + fall.cliffTop - 8 then
			return false
		end
		local lx, lz = world.radialLocal(x, z, fall.angle, fall.radius)
		return lz > 6 and lz < fall.depth - 10 and abs(lx) < fall.halfWidth - 4
	end
	local function nearPeak(x: number, z: number, pad: number): boolean
		return peakAt(x, z, pad) ~= nil
	end
	-- A spot on the far side of a mountain (beyond r 640, behind its summit from the island's
	-- centre): no view from the play area or the hill viewpoints reaches it, so no trees there
	local function behindMountain(x: number, z: number): boolean
		local r = sqrt(x * x + z * z)
		if r < 640 then
			return false
		end
		local p = peakAt(x, z, 30)
		return p ~= nil and r > sqrt(p.x * p.x + p.z * p.z) + 20
	end

	-- Family of a grove at a site and the kind of each of its trees; up on a mountain the
	-- mountain's style decides: pines on the snow peaks, pines and round trees on the green
	-- hill, palms and autumn trees on the red-rock mesas.
	-- The autumn orchard: the hills behind the farm gateway (θ 0), one of the three accent spots.
	local function inOrchard(x: number, z: number, r: number): boolean
		return r > 410 and r < 540 and Kit.angleDistance(deg(atan2(x, z)) % 360, 0) < 8
	end
	local function family(s: { [string]: any }): string
		local pk = if s.h >= G + 28 then peakAt(s.x, s.z, 20) else nil
		if onMesa(s.x, s.z, s.h) then
			return "blossom"
		elseif pk and pk.style == "sandstone" then
			return "desert"
		elseif pk and pk.style == "green" then
			return "greenhill"
		elseif pk or s.h >= G + 60 then
			return "pines"
		elseif inOrchard(s.x, s.z, s.r or sqrt(s.x * s.x + s.z * s.z)) then
			return "orchard"
		elseif s.biome > 0.25 then
			return "birchwood"
		elseif s.biome < -0.25 then
			return "conifer"
		end
		return "green"
	end
	-- The species of one tree of a family (roll in [0, 1)): woods are green — oak, round and deep
	-- broadleaves, birches, pines — and only the accent families (the waterfall mesa's blossom, the
	-- farm orchard, the red-rock mesas' ledges) carry cherry / autumn colours.
	local function speciesOf(fam: string, roll: number, h: number): string
		if fam == "pines" then
			return if h >= G + 88 then "snowPine" else "pine"
		elseif fam == "greenhill" then
			return if roll < 0.5 then "pine" elseif roll < 0.8 then "round" else "oak"
		elseif fam == "desert" then
			-- palms on the ochre tops, green round trees and a few russet ones on the grassy ledges
			if h > 40 then
				return if roll < 0.8 then "palm" else "round"
			end
			return if roll < 0.25 then "autumn" elseif roll < 0.6 then "round" else "palm"
		elseif fam == "blossom" then
			return if roll < 0.65 then "cherry" else "birch"
		elseif fam == "orchard" then
			return if roll < 0.25 then "gold" elseif roll < 0.35 then "autumn" elseif roll < 0.75 then "round" else "oak"
		elseif fam == "birchwood" then
			return if roll < 0.4 then "birch" elseif roll < 0.7 then "oak" elseif roll < 0.85 then "mint" else "pine"
		elseif fam == "conifer" then
			return if roll < 0.6 then "pine" elseif roll < 0.85 then "deep" else "birch"
		end
		return if roll < 0.35 then "oak" elseif roll < 0.6 then "round" elseif roll < 0.85 then "pine" else "birch"
	end
	-- Detail level by distance to the play area: full Props trees right beside the landmark
	-- paths, compact lite ones near the play area, the cheap ones everywhere else.
	local function detail(x: number, z: number): string
		if world:pathDistance(x, z) < 14 then
			return "full"
		elseif world:isReserved(x, z, 46) then
			return "lite"
		end
		return "far"
	end

	local carry = 0
	local shareBase = nil -- (the budget left when the shared passes start)
	local function quota(name: string): number
		shareBase = shareBase or max(0, budget - spentAll())
		return shareBase * SHARE[name] + carry
	end
	local function finishPass(q: number, spent: number)
		carry = max(0, q - spent)
	end
	-- how much a spot at radius r is seen from the play area (hub, bridges, promenade, bases)
	local function visibility(r: number): number
		return 0.55 + 0.45 * smooth(380, 470, r) - 0.3 * smooth(600, 680, r)
	end

	-- A rock with a tuft or a bush beside it (never a bare rock on a lawn).
	local function rockGroup(x: number, z: number, s: number, margin: number, r: (number?, number?) -> number): number
		local used = small(x, z, "rock", { scale = s, cap = if r() < 0.7 then "moss" else nil, margin = margin })
		if used > 0 then
			local a = r(0, 2 * math.pi)
			local d = 3.4 * s + 3.6
			local px, pz = x + d * sin(a), z + d * cos(a)
			if r() < 0.55 then
				used += small(px, pz, "tuft", { scale = r(0.9, 1.2), margin = margin, gap = 0.2 })
			else
				used += small(px, pz, "shrub", { scale = r(0.8, 1.1), margin = margin, gap = 0.2 })
			end
		end
		return used
	end
	-- One cheap decor group at (x, z) on ground h: a flower clump (or two of one colour pair), a
	-- leafy bush (sometimes with berries), a rock group, or on the low lawns hay bales or a short
	-- fence run; without `flowers` (terrace lips, open lawns) only bushes and rocks; on the
	-- mountains' flanks only rocks and bushes. Everything is sized to read from the promenade (no
	-- 2-stud dots: the same parts, bigger).
	local drng = Kit.rng(6060)
	local function decorGroup(x: number, z: number, h: number, margin: number, flowers: boolean?): number
		local roll = drng()
		local farm = h <= G + 16
		local pk = if h >= G + 28 then peakAt(x, z, 10) else nil
		if pk and pk.style == "sandstone" then
			-- the red-rock mesas: terracotta boulders, on the ochre tops now and then a cactus
			if roll < 0.3 and mesaTop(x, z, h) then
				return small(x, z, "cactus", { scale = drng(1.4, 1.7), margin = margin })
			end
			return small(x, z, "rock", { scale = drng(1.1, 1.5), color = REDROCK, margin = margin })
		elseif pk or not flowers then
			if roll < 0.4 then
				return rockGroup(x, z, drng(1.1, 1.5), margin, drng)
			end
			return small(x, z, "shrub", { scale = drng(1.3, 1.7), margin = margin })
		end
		if roll < 0.22 then
			return small(x, z, "tuft", { scale = drng(1.5, 1.9), margin = margin })
		elseif roll < 0.32 then
			-- a drift of wildflowers on stems along the path
			return small(x, z, "drift", { margin = margin, yaw = deg(atan2(x, z)) + 90 })
		elseif roll < 0.42 then
			-- two clumps of one colour pair
			local pair = pairOf(drng())
			local used = small(x, z, "tuft", { scale = drng(1.4, 1.7), margin = margin, pair = pair })
			if used > 0 then
				local a = drng(0, 2 * math.pi)
				used += small(
					x + 7.5 * sin(a),
					z + 7.5 * cos(a),
					"tuft",
					{ scale = drng(1.1, 1.4), margin = margin, pair = pair }
				)
			end
			return used
		elseif roll < 0.66 then
			local berry = if drng() < 0.4 then bloomOf(drng()) else nil
			return small(x, z, "shrub", { scale = drng(1.3, 1.7), margin = margin, berry = berry })
		elseif roll < 0.84 then
			return rockGroup(x, z, drng(1.0, 1.4), margin, drng)
		elseif roll < 0.92 and farm then
			return small(x, z, "hay", { margin = margin + 1 })
		elseif farm then
			-- along the slope (tangential): a field edge
			local yaw = deg(atan2(x, z)) + drng(-20, 20)
			return small(x, z, "fence", { margin = margin + 1, yaw = yaw, white = drng() < 0.4 })
		end
		return small(x, z, "shrub", { scale = drng(1.4, 1.8), margin = margin })
	end

	--------------------------------------------------------------------------------------------
	-- Pass 0: the lagoon — 12 calm coral patches on its sandy slope (bed -6: r ~197-215 along the
	-- hub beach, r ~266-284 along the promenade), where players look down on them: one beside
	-- each pier on the side away from its bridge (r ~275) and one beside each bridge (r ~206);
	-- then 2-3 features on the surface of every quadrant (a moored houseboat near the promenade
	-- beach, a fish-farm ring beside a bridge, a rocky islet with a perch off the hub beach).
	-- The water in front of the piers and along the bridges stays clear, the surface features
	-- keep out of every pier's whole casting cone (like the boats) and off the other water decor
	--------------------------------------------------------------------------------------------
	do
		local reef = U.model(nature, "Reef")
		local function clear(x: number, z: number): boolean
			for i = 1, cfg.BaseCount do
				local lx, lz = world:toBaseLocal(i, x, z)
				if abs(lx) < 32 and lz > -(cfg.PierLength or 72) - 20 and lz < 3 then
					return false
				end
			end
			for _, a in cfg.BridgeAngles do
				local ux, uz = sin(rad(a)), cos(rad(a))
				if x * ux + z * uz > cfg.HubPlazaRadius - 10 and abs(x * uz - z * ux) < cfg.BridgeWidth / 2 + 16 then
					return false
				end
			end
			return true
		end
		-- the whole pad on one bed column top at -6 to -8 (the slope band: everything stays under
		-- y -4)
		local function bedAt(x: number, z: number): number?
			local h = world:heightAt(x, z)
			if h > -6 or h < -8 then
				return nil
			end
			for _, d in DIRS8 do
				if world:heightAt(x + d[1] * 7, z + d[2] * 7) ~= h then
					return nil
				end
			end
			return h
		end
		local spots = {}
		local landmarkSide = { 33.75, 56.25 } -- beside the piers at 22.5 / 67.5, towards θ 45
		for q = 0, 3 do
			for _, a in landmarkSide do
				table.insert(spots, { a = a + q * 90, r = 275 })
			end
			table.insert(spots, { a = q * 90 + (if q % 2 == 0 then 11.25 else -11.25), r = 206 })
		end
		for n, spot in spots do
			-- the first clear, flat spot along the band (radius and angle nudged a little)
			for _, dr in { 0, 3, -3, 6, -6 } do
				local done = false
				for _, da in { 0, 2.5, -2.5, 5, -5 } do
					local p = U.polar(spot.a + da, spot.r + dr, 0)
					local bed = bedAt(p.X, p.Z)
					if bed and affordable(14) and clear(p.X, p.Z) and not blocked(p.X, p.Z, 8, bed, 1) then
						reefPatch(
							reef,
							CFrame.new(p.X, bed, p.Z) * CFrame.Angles(0, rad(spot.a + da), 0),
							bed,
							8086 + n * 31
						)
						count("reef")
						done = true
						break
					end
				end
				if done then
					break
				end
			end
		end

		-- surface features: out of every pier's casting cone (40 studs either side of its axis,
		-- 150 out) and clear of the bridges, in open water all round, off the other water decor
		local surface = U.model(nature, "Lagoon")
		local function free(x: number, z: number, pad: number): boolean
			for i = 1, cfg.BaseCount do
				local lx, lz = world:toBaseLocal(i, x, z)
				if abs(lx) < 40 + pad and lz > -150 - pad and lz < pad then
					return false
				end
			end
			for _, a in cfg.BridgeAngles do
				local ux, uz = sin(rad(a)), cos(rad(a))
				if
					x * ux + z * uz > cfg.HubPlazaRadius - 10
					and abs(x * uz - z * ux) < cfg.BridgeWidth / 2 + 10 + pad
				then
					return false
				end
			end
			for _, d in DIRS8 do
				if not world:isWater(x + d[1] * pad, z + d[2] * pad) then
					return false
				end
			end
			return world:isWater(x, z) and not blocked(x, z, pad, -16, 12) and fits(x, z, 0, pad, "lagoon")
		end
		-- per quadrant (from the bridge at 90q): the features and their candidate spots
		-- { angle offset, radius }; odd quadrants mirror the offsets
		local SETS = {
			[0] = { "houseboat", "farm", "islet" },
			[1] = { "farm", "islet" },
			[2] = { "houseboat", "farm", "islet" },
			[3] = { "houseboat", "islet" },
		}
		local SPOTS = {
			houseboat = { { 57, 270 }, { 33, 270 }, { 59, 262 }, { 31, 262 }, { 55, 278 } },
			farm = { { 8, 246 }, { 82, 246 }, { 8, 234 }, { 82, 234 }, { 45, 246 } },
			islet = { { 45, 196 }, { 39, 204 }, { 51, 204 }, { 40, 232 }, { 50, 232 }, { 45, 250 } },
		}
		local PAD = { houseboat = 11, farm = 10, islet = 9 }
		local COST_OF = { houseboat = 13, farm = 13, islet = 9 }
		local lrng = Kit.rng(5577)
		for q = 0, 3 do
			for k, kind in SETS[q] do
				for _, sp in SPOTS[kind] do
					-- (the fish farms all sit on the same side of their bridge)
					local off = if q % 2 == 1 and kind ~= "farm" then 90 - sp[1] else sp[1]
					local a = q * 90 + off
					local p = U.polar(a, sp[2], 0)
					if affordable(COST_OF[kind]) and free(p.X, p.Z, PAD[kind]) then
						local bed = max(2, -world:heightAt(p.X, p.Z))
						local seed = floor(lrng(1, 1e6))
						if kind == "houseboat" then
							-- along the shore (bow pointing round the ring), its mooring post on the
							-- promenade side
							houseboat(surface, CFrame.new(p.X, 0, p.Z) * CFrame.Angles(0, rad(a + 90), 0), bed, seed)
						elseif kind == "farm" then
							fishFarm(surface, CFrame.new(p.X, 0, p.Z) * CFrame.Angles(0, rad(a + 12), 0), seed)
						else
							rockyIslet(surface, CFrame.new(p.X, 0, p.Z) * CFrame.Angles(0, rad(a), 0), bed, seed)
						end
						addPlaced(p.X, p.Z, 0, PAD[kind], "lagoon")
						count(kind)
						break
					end
				end
			end
		end
	end

	--------------------------------------------------------------------------------------------
	-- Pass 0b: showcase lawns — the wedges between two plots at the landmark paths that are no
	-- landmark site themselves (the peak trail, the giant tree's meadow) are the first thing
	-- seen from the promenade: a pine avenue framing the peak trail, then set pieces of 8-16
	-- studs lined up with the path (raised flower beds, bush clumps, boulders with a bush and
	-- flowers) instead of scattered dots
	--------------------------------------------------------------------------------------------
	do
		local srng = Kit.rng(2468)
		local outerR = cfg.PromenadeRadius + cfg.PromenadeWidth
		-- one set piece standing on cf (radial frame) with footprint half-width `half`
		local function piece(x: number, z: number, half: number, yaw: number, kind: string): number
			if not affordable(14) or not offPath(x, z, half + 2) then
				return 0
			end
			if world:isReserved(x, z, 2) or Kit.isClaimed(x, z, half + 1) then
				return 0
			end
			local h = flatAt(x, z, half)
			if not h or not fits(x, z, 0, half + 4, "show") or blocked(x, z, half + 1, h + 0.2, h + 8) then
				return 0
			end
			local before = U.partCount
			local cf = CFrame.new(x, h, z) * CFrame.Angles(0, rad(yaw), 0)
			local seed = floor(srng(1, 1e6))
			if kind == "bed12" then
				flowerBed(groups.plants, cf, 12, seed)
			elseif kind == "bed8" then
				flowerBed(groups.plants, cf, 8, seed)
			elseif kind == "clump" then
				local bloom = if srng() < 0.6 then bloomOf(srng()) else nil
				bushClump(groups.plants, cf, srng(1.0, 1.2), seed, bloom)
			else
				-- a big mossy boulder with a bush clump behind it and a flower tuft in front
				rock(groups.rocks, cf, srng(1.5, 1.8), seed, { cap = "moss" })
				bushClump(groups.plants, cf * CFrame.new(-4.5, 0, 4.5), 0.75, seed + 1, nil)
				tuft(groups.plants, cf * CFrame.new(4.2, 0, -3.6), 1.2, seed + 2)
			end
			addPlaced(x, z, 0, half + 1, "show")
			count(kind)
			return U.partCount - before
		end
		local KINDS = { "bed12", "clump", "boulder", "bed8", "clump", "bed12", "boulder", "bed8" }
		for _, name in { "Peak", "GiantTree" } do
			local site = world.landmarks[name]
			if not site then
				continue
			end
			local a = site.angle
			-- the peak trail: a pine avenue up to the mountain's foot on both sides, each pine on
			-- the first spot out from the path where it fits (the terraces beside the cut)
			if name == "Peak" then
				-- (from 26 studs out: the path mouth by the promenade stays open)
				local foot = site.radius - site.mountainRadius - outerR
				for lz = 26, foot - 6, 18 do
					for _, side in { -1, 1 } do
						local s = srng(1.1, 1.25) -- (neat rows, not a dark tunnel at eye level)
						local ok = false
						for _, dz in { 0, 5, -5 } do
							for lx = 14, 30, 3 do
								local x, z = Kit.radial(a, outerR, side * lx, lz + dz)
								if tree(x, z, "pine", "lite", "avenue", s) > 0 then
									ok = true
									break
								end
							end
							if ok then
								break
							end
						end
					end
				end
			end
			-- set pieces: candidate spots on a 6-stud grid of the wedge (path-local lx, lz),
			-- nearest to the promenade first, at least 24 studs apart
			local cands = {}
			for lz = 12, 140, 6 do
				for lx = -96, 96, 6 do
					if abs(lx) >= 22 then
						local x, z = Kit.radial(a, outerR, lx + srng(-1.5, 1.5), lz + srng(-1.5, 1.5))
						if not world:isReserved(x, z, 2) then
							table.insert(cands, { x = x, z = z, score = lz + abs(lx) * 0.35 + srng(0, 10) })
						end
					end
				end
			end
			table.sort(cands, function(p, q)
				if p.score ~= q.score then
					return p.score < q.score
				end
				return p.x + p.z * 1e-3 < q.x + q.z * 1e-3
			end)
			local n = 0
			local done = {}
			for _, c in cands do
				if n >= 10 then
					break
				end
				local near = false
				for _, o in done do
					if (o[1] - c.x) ^ 2 + (o[2] - c.z) ^ 2 < 24 * 24 then
						near = true
						break
					end
				end
				if not near then
					-- (on the voxel grid like the terraces they stand on)
					local kind = KINDS[n % #KINDS + 1]
					local half = if kind == "bed12"
						then 6.5
						elseif kind == "bed8" then 4.5
						elseif kind == "clump" then 5.5
						else 8
					if piece(c.x, c.z, half, 0, kind) > 0 then
						n += 1
						table.insert(done, { c.x, c.z })
					end
				end
			end
		end
	end

	--------------------------------------------------------------------------------------------
	-- Pass 0c: gateway wedges — the hills behind the four gateway plazas are the first land seen
	-- from every bridge: clumps of two or three trees in the district's theme on the terrace lips
	-- either side of the climb (an autumn orchard behind the farm, birches behind the garden, palms
	-- behind the harbour, pines round the camp), each with a flowering bush, clear of the climb
	-- and the plaza (the district's own pieces and claims keep their ground)
	--------------------------------------------------------------------------------------------
	do
		local THEMES = {
			[0] = { "gold", "round", "oak" }, -- the farm's orchard: one golden tree a clump (accent)
			[90] = { "birch", "round", "birch" }, -- the garden: fresh birches
			[180] = { "palm", "round", "palm" },
			[270] = { "pine", "round", "pine" },
		}
		local wrng = Kit.rng(1357)
		for _, gw in world.gateways do
			local kinds = THEMES[floor(gw.angle + 0.5) % 360] or THEMES[0]
			local ux, uz = sin(rad(gw.angle)), cos(rad(gw.angle))
			local cands = {}
			for _, s in sites do
				local lx, lz = world.radialLocal(s.x, s.z, gw.angle, 0)
				local plaza = sqrt((s.x - gw.x) ^ 2 + (s.z - gw.z) ^ 2)
				if lz > 400 and lz < 545 and abs(lx) >= 18 and abs(lx) <= 0.24 * lz and plaza > gw.radius + 14 then
					-- terrace lips first (the ground drops towards the promenade in front)
					local lip = world:heightAt(s.x - ux * 8, s.z - uz * 8) <= s.h - 4
					table.insert(cands, { s = s, score = (if lip then 1 else 0) + 0.6 * s.jitter - lz / 400 })
				end
			end
			sortBy(cands, "score")
			local clumps, planted = {}, 0
			for _, c in cands do
				if #clumps >= 7 or planted >= 15 then
					break
				end
				local s = c.s
				local apart = true
				for _, o in clumps do
					if (o[1] - s.x) ^ 2 + (o[2] - s.z) ^ 2 < 34 * 34 then
						apart = false
						break
					end
				end
				if apart then
					-- the clump: its centre and up to two neighbours a canopy's width away (tried
					-- round it in five directions)
					local fam = `wedge{gw.index}_{#clumps + 1}`
					local a0 = wrng(0, 2 * math.pi)
					local n = 0
					for k = 0, 5 do
						if n >= 3 or planted >= 15 then
							break
						end
						local x, z = s.x, s.z
						if k > 0 then
							local a = a0 + k * 1.2566
							x, z = s.x + 20 * sin(a), s.z + 20 * cos(a)
						end
						-- (on a column's centre: the trunk never straddles a terrace step)
						x, z = floor(x / 8) * 8 + 4, floor(z / 8) * 8 + 4
						if tree(x, z, kinds[(n + k) % #kinds + 1], detail(x, z), fam) > 0 then
							n += 1
							planted += 1
							count("wedgeTree")
						end
					end
					if n > 0 then
						table.insert(clumps, { s.x, s.z })
						count("wedge")
						local a = a0 + 1.05
						local berry = bloomOf(wrng())
						small(s.x + 10 * sin(a), s.z + 10 * cos(a), "shrub", { scale = wrng(1.3, 1.6), berry = berry })
					end
				end
			end
		end
	end

	--------------------------------------------------------------------------------------------
	-- Pass 1a: shore — small scenes of island life on the outer beaches and cliff tops, where the
	-- hill viewpoints look (4-5 a quadrant): fishermen's huts on stilts by the water, beach camps,
	-- drying racks, keepers' cottages on the grass over the beach, boulder piles with dune grass;
	-- each facing the sea on the first flat spot (from the sea inwards) near its angle
	--------------------------------------------------------------------------------------------
	do
		local q = quota("shore")
		local spent = 0
		local shore = U.model(nature, "Shore")
		-- (round-robin over the quadrants: a short budget thins every coast evenly)
		local SPOTS = {
			{ 352, "hut" },
			{ 90, "hut" },
			{ 178, "hut" },
			{ 268, "hut" },
			{ 8, "camp" },
			{ 60, "camp" },
			{ 145, "camp" },
			{ 215, "camp" },
			{ 340, "racks" },
			{ 97, "racks" },
			{ 188, "racks" },
			{ 285, "racks" },
			{ 330, "cottage" },
			{ 128, "cottage" },
			{ 238, "cottage" },
			{ 16, "boulders" },
			{ 137, "boulders" },
			{ 222, "boulders" },
			{ 70, "boulders" },
			{ 298, "boulders" },
		}
		-- footprints in the piece's frame before SHORE_SCALE: { x0, x1, z0, z1 } (-Z to the sea)
		local FOOT = {
			hut = { -5.6, 5.6, -7.5, 4.3 },
			camp = { -5.4, 6.7, -7.0, 4.5 },
			racks = { -6.7, 7.4, -3.5, 0.5 },
			cottage = { -6.1, 8.0, -5.2, 5.2 },
			boulders = { -4.8, 4.8, -3.0, 4.4 },
		}
		local COSTS = { hut = 16, camp = 12, racks = 11, cottage = 14, boulders = 7 }
		local BUILD = {
			hut = stiltHut,
			camp = beachCamp,
			racks = dryingRacks,
			cottage = keeperCottage,
			boulders = boulderPile,
		}
		-- Does the footprint of `kind` at (x, z) on ground h, facing the sea along the ray `a`,
		-- stand on one dry column top (a 4 x 4 grid of points over it)? The hut's sea side may
		-- step down (it stands on stilts), the boulders' edges may step either way by 2.
		local function settles(kind: string, x: number, z: number, h: number, a: number): boolean
			local f = FOOT[kind]
			local cf = CFrame.new(x, h, z) * CFrame.Angles(0, rad(a + 180), 0)
			for i = 0, 3 do
				for j = 0, 3 do
					local lx = (f[1] + (f[2] - f[1]) * i / 3) * SHORE_SCALE
					local lz = (f[3] + (f[4] - f[3]) * j / 3) * SHORE_SCALE
					local p = cf * Vector3.new(lx, 0, lz)
					local hh, _, water = world:surfaceAt(p.X, p.Z)
					local ok = hh == h and not water
					if kind == "hut" and j == 0 then
						ok = hh <= h and hh >= h - 2
					elseif kind == "boulders" and (i == 0 or i == 3 or j == 0 or j == 3) then
						ok = not water and abs(hh - h) <= 2
					end
					if not ok then
						return false
					end
				end
			end
			return true
		end
		-- the first spot near `theta` (from the sea inwards) where the piece stands on the right
		-- ground (sand for the beach pieces, then a low lawn by the beach; grass for the
		-- cottages): x, z, ground y, the ray's angle
		local function spotFor(theta: number, kind: string): (number?, number?, number?, number?)
			local f = FOOT[kind]
			local reach = max(-f[1], f[2], -f[3], f[4]) * SHORE_SCALE
			local beach = kind == "hut" or kind == "camp" or kind == "racks"
			for round = 1, if beach and kind ~= "hut" then 2 else 1 do
				for _, da in { 0, 1.5, -1.5, 3, -3, 4.5, -4.5, 6, -6 } do
					local a = theta + da
					local ux, uz = sin(rad(a)), cos(rad(a))
					local coastR = world:coastRadius(a)
					for r = coastR + 30, coastR - 70, -2 do
						local x, z = r * ux, r * uz
						local h, k, water = world:surfaceAt(x, z)
						local ok = not water
						if ok and beach then
							ok = if round == 1 then k == "sand" and h <= 3 else k ~= "sand" and h <= G + 6
						elseif ok and kind == "cottage" then
							ok = k ~= "sand" and h >= G and h <= G + 40
						end
						if
							ok
							and settles(kind, x, z, h, a)
							and not world:isReserved(x, z, reach + 2)
							and not Kit.isClaimed(x, z, reach + 1)
							and offPath(x, z, reach)
							and fits(x, z, 0, reach + 2, "shore")
							and not blocked(x, z, reach, h + 0.2, h + 18)
						then
							return x, z, h, a
						end
					end
				end
			end
			return nil, nil, nil, nil
		end
		local srng = Kit.rng(8642)
		for _, sp in SPOTS do
			local kind = sp[2]
			local seed = floor(srng(1, 1e6))
			if spent < q and affordable(COSTS[kind]) then
				local x, z, h, a = spotFor(sp[1], kind)
				if x and z and h and a then
					local before = U.partCount
					-- (front, local -Z, out to sea)
					BUILD[kind](shore, CFrame.new(x, h, z) * CFrame.Angles(0, rad(a + 180), 0), seed)
					local f = FOOT[kind]
					addPlaced(x, z, 0, max(-f[1], f[2], -f[3], f[4]) * SHORE_SCALE + 1, "shore")
					count(kind)
					spent += U.partCount - before
				end
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 1: coast — palm pairs, beach sets and foamy rocks along the outer beaches, rocks in
	-- the surf below the cliffs
	--------------------------------------------------------------------------------------------
	do
		local q = quota("coast")
		local spent = 0
		local crng = Kit.rng(777)
		-- the outer coast every 2°: the beach band (dry sand at y 2-3) on each ray
		local samples = {}
		for k = 0, 179 do
			local theta = k * 2 + crng(-0.4, 0.4)
			local coastR = world:coastRadius(theta)
			local ux, uz = sin(rad(theta)), cos(rad(theta))
			local sandIn, sandOut = nil, nil
			for r = coastR - 50, coastR + 34, 2 do
				local h, kind, water = world:surfaceAt(r * ux, r * uz)
				if kind == "sand" and not water and h <= 3 then
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
		-- slots along the ring: a palm pair every 3 beach samples (~65 studs), a beach set or a
		-- foamy rock group half-way to the next pair (by turns), a rock in the surf at every
		-- fourth cliff sample
		local slots = {}
		local since = 99
		local pairsN = 0
		for _, smp in samples do
			if smp.beach then
				if since >= 3 then
					pairsN += 1
					table.insert(slots, { kind = "palms", s = smp, n = pairsN })
					since = 0
				else
					since += 1
					if since == 2 then
						table.insert(slots, { kind = if pairsN % 2 == 0 then "set" else "foam", s = smp, n = pairsN })
					end
				end
			else
				since += 1
				if smp.k % 4 == 0 then
					table.insert(slots, { kind = "surf", s = smp, n = smp.k })
				end
			end
		end
		-- every other pair first, then the rest, then the extras: a short budget thins the
		-- beach evenly instead of leaving its last stretch bare
		local RANK = { palms = 0, set = 2, foam = 3, surf = 4 }
		local function rank(slot: any): number
			return RANK[slot.kind] + (if slot.kind == "palms" and slot.n % 2 == 0 then 1 else 0)
		end
		table.sort(slots, function(a, b)
			if rank(a) ~= rank(b) then
				return rank(a) < rank(b)
			end
			return a.s.k < b.s.k
		end)
		local props = { "parasol", "sandcastle", "towel", "driftwood", "parasol", "starfish" }
		local nProps = 0
		-- a rock on the shallow bed past the sand (or the cliff foot) in a ring of foam, in open
		-- water all round (never half inside a cliff)
		local function openWater(x: number, z: number): boolean
			for _, d in DIRS8 do
				if not world:isWater(x + d[1] * 5, z + d[2] * 5) then
					return false
				end
			end
			return true
		end
		local function foamRock(smp: any, from: number, to: number): number
			for r = from, to, 2 do
				local x, z = r * smp.ux, r * smp.uz
				local h, _, water = world:surfaceAt(x, z)
				if
					water
					and h >= -4
					and h <= -2
					and affordable(4)
					and openWater(x, z)
					and fits(x, z, 0, 4.5, "rock")
				then
					if blocked(x, z, 4, h, 4) then
						return 0
					end
					local before = U.partCount
					surfRock(groups.rocks, CFrame.new(x, h, z), h, crng(1.0, 1.4), floor(crng(1, 1e6)))
					addPlaced(x, z, 0, 4, "rock")
					count("surfRock")
					return U.partCount - before
				end
			end
			return 0
		end
		for _, slot in slots do
			if spent >= q then
				break
			end
			local smp = slot.s
			local ux, uz = smp.ux, smp.uz
			local tx, tz = -uz, ux
			if slot.kind == "palms" then
				-- two palms on the inner half of the beach, 10-13 studs apart
				local width = smp.sandOut - smp.sandIn
				local r = smp.sandIn + min(5, width * 0.3)
				local x, z = r * ux, r * uz
				local used = tree(x, z, "palm", "far", "palm", crng(2.0, 2.4))
				local off = crng(10, 13) * (if slot.n % 2 == 0 then 1 else -1)
				local out = crng(1, min(7, width * 0.5))
				used += tree(x + tx * off + ux * out, z + tz * off + uz * out, "palm", "far", "palm", crng(1.6, 2.0))
				spent += used
			elseif slot.kind == "set" then
				-- the first flat spot across the beach, from the water's edge inwards
				local x, z, h
				for r = smp.sandOut - 3, smp.sandIn + 3, -2 do
					for _, side in { 0, 5, -5 } do
						local px, pz = r * ux + tx * side, r * uz + tz * side
						local ph = flatAt(px, pz, 3.6)
						if ph and fits(px, pz, 0, 4.5, "prop") and not blocked(px, pz, 4, ph + 0.2, ph + 8) then
							x, z, h = px, pz, ph
							break
						end
					end
					if h then
						break
					end
				end
				if h and affordable(4) then
					local before = U.partCount
					nProps += 1
					local kind = props[(nProps - 1) % #props + 1]
					beachProp(groups.plants, CFrame.new(x, h, z), kind, floor(crng(1, 1e6)))
					addPlaced(x, z, 0, 4, "prop")
					count(kind)
					spent += U.partCount - before
					-- a starfish or a towel beside the bigger pieces
					local x2, z2 = x + tx * 7, z + tz * 7
					local h2 = flatAt(x2, z2, 2.4)
					if kind ~= "starfish" and h2 and affordable(3) and fits(x2, z2, 0, 2.6, "prop") then
						before = U.partCount
						beachProp(
							groups.plants,
							CFrame.new(x2, h2, z2),
							if nProps % 2 == 0 then "towel" else "starfish",
							floor(crng(1, 1e6))
						)
						addPlaced(x2, z2, 0, 2.6, "prop")
						spent += U.partCount - before
					end
				end
			elseif slot.kind == "foam" then
				spent += foamRock(smp, smp.sandOut + 2, smp.sandOut + 16)
			else
				spent += foamRock(smp, smp.coastR - 24, smp.coastR + 40)
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 2: trees on the mountains, in each one's style — pines on the snow peaks' grassy flanks
	-- (snow-dusted higher up) and snow-capped rocks; plain pines and round trees on the green
	-- hill and mossy rocks; on the red-rock mesas (sparingly: the strata are the show) three
	-- cacti, a few palms and terracotta boulders on the ochre top, autumn trees on the ledges
	--------------------------------------------------------------------------------------------
	do
		local q = quota("pines")
		local spent = 0
		local prng = Kit.rng(3141)
		-- the mesas' cacti first, spread over the ochre top
		for _, p in peaks do
			if p.style == "sandstone" then
				local list = {}
				for _, s in sites do
					if mesaTop(s.x, s.z, s.h) == p then
						table.insert(list, { s = s, score = s.jitter })
					end
				end
				sortBy(list, "score")
				local done = {}
				for _, e in list do
					if #done >= 3 then
						break
					end
					local apart = true
					for _, o in done do
						if (o[1] - e.s.x) ^ 2 + (o[2] - e.s.z) ^ 2 < 30 * 30 then
							apart = false
							break
						end
					end
					if apart then
						local used = small(e.s.x, e.s.z, "cactus", { scale = prng(1.5, 1.8) })
						if used > 0 then
							spent += used
							table.insert(done, { e.s.x, e.s.z })
						end
					end
				end
			end
		end
		local perPeak = {}
		for i, p in peaks do
			local list = {}
			for _, s in sites do
				local dx, dz = s.x - p.x, s.z - p.z
				local d = sqrt(dx * dx + dz * dz)
				local land = if p.style == "sandstone"
					then s.kind == "redrock" or s.kind == "grass"
					else s.kind == "grass" or s.kind == "grassRock"
				if d < p.mountainRadius + 10 and s.h >= G + 8 and land and not behindMountain(s.x, s.z) then
					table.insert(
						list,
						{ s = s, score = s.grove * 0.6 + s.jitter + (if s.kind == "grassRock" then 0.4 else 0) }
					)
				end
			end
			sortBy(list, "score")
			perPeak[i] = list
		end
		local function kindOn(p: any, s: any): string
			if p.style == "sandstone" then
				return speciesOf("desert", prng(), s.h)
			elseif p.style == "green" then
				return speciesOf("greenhill", prng(), s.h)
			end
			return if s.h >= G + 60 then "snowPine" else "pine"
		end
		-- round-robin over the mountains so each gets its share
		local idx, placedOn = {}, {}
		for i in peaks do
			idx[i], placedOn[i] = 1, 0
		end
		local progress = true
		while progress and spent < q do
			progress = false
			for i, p in peaks do
				local list = perPeak[i]
				local cap = if p.style == "sandstone" then 8 else 14
				while idx[i] <= #list and placedOn[i] < cap do
					local s = list[idx[i]].s
					idx[i] += 1
					local level = if world:isReserved(s.x, s.z, 50) then "lite" else "far"
					local used = tree(s.x, s.z, kindOn(p, s), level, "pines")
					if used > 0 then
						spent += used
						placedOn[i] += 1
						progress = true
						break
					end
				end
			end
		end
		-- rocks: snow-capped on the snow peaks' stone flanks, mossy on the green hill, terracotta
		-- boulders on the mesa tops
		local rrng = Kit.rng(2024)
		local slate = lerp(C.StoneLight, C.RoofSlate, 0.2)
		for _, p in peaks do
			local n = 0
			local most = if p.style == "sandstone" then 3 else 2
			for _, s in sites do
				if n >= most or spent >= q then
					break
				end
				local d = sqrt((s.x - p.x) ^ 2 + (s.z - p.z) ^ 2)
				local used = 0
				if d < p.mountainRadius and s.jitter > 0.88 then
					if p.style == "sandstone" then
						if mesaTop(s.x, s.z, s.h) == p then
							used = small(s.x, s.z, "rock", { scale = rrng(1.4, 1.8), color = REDROCK })
						end
					elseif p.style == "green" then
						if s.kind == "grass" and s.h >= G + 28 then
							used = small(s.x, s.z, "rock", { scale = rrng(1.3, 1.7), cap = "moss" })
						end
					elseif s.kind == "stone" or s.kind == "grassRock" then
						used = small(s.x, s.z, "rock", { scale = rrng(1.3, 1.7), cap = "snow", color = slate })
					end
				end
				if used > 0 then
					n += 1
					spent += used
				end
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 3: tree belts behind the plots' back walls (two rows, round-robin over the plots)
	--------------------------------------------------------------------------------------------
	do
		local q = quota("belts")
		local spent = 0
		local back = cfg.PlotFront + cfg.PlotDepth + (cfg.PlotMargin or 8)
		-- slots in plot-local space, the middle first: row 1 every 19 studs, row 2 staggered
		local slots = {}
		for row = 1, 2 do
			local lz = back + (if row == 1 then 12 else 26)
			for k = 0, 4 do
				for _, sg in (if k == 0 and row == 1 then { 1 } else { -1, 1 }) do
					local lx = sg * (k * 19 + (if row == 2 then 9.5 else 0))
					if abs(lx) <= 86 then
						table.insert(slots, { lx = lx, lz = lz, row = row })
					end
				end
			end
		end
		local brng = Kit.rng(1234)
		for _, slot in slots do
			for i = 1, cfg.BaseCount do
				if spent >= q then
					break
				end
				local b = world.bases[i]
				-- try the slot, then a little further out / to the sides
				for _, d in { { 0, 0 }, { 0, 6 }, { 5, 3 }, { -5, 3 }, { 0, 12 } } do
					local lx = slot.lx + d[1] + brng(-2, 2)
					local lz = slot.lz + d[2] + brng(-2, 2)
					local x, z = Kit.radial(b.angle, cfg.BaseRadius, lx, lz)
					local h = world:heightAt(x, z)
					local s = { x = x, z = z, h = h, biome = world:noise(x / 260 + 13, z / 260 + 41) }
					local fam = family(s)
					local kind = speciesOf(fam, brng(), h)
					local used = tree(x, z, kind, "far", "belt" .. i, brng(1.8, 2.3))
					if used > 0 then
						spent += used
						count("belt")
						break
					end
				end
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 4: woods on the hill crests (the skyline behind the plots and over the outer coast):
	-- on each of the most visible crests (at least 70 studs apart) a grove of 5-8 trees whose
	-- crowns merge, instead of a lone tree every 50-100 studs
	--------------------------------------------------------------------------------------------
	do
		local q = quota("crests")
		local spent = 0
		local list = {}
		for _, s in sites do
			if s.kind == "grass" and s.h >= G + 12 and not nearPeak(s.x, s.z, 6) and not onMesa(s.x, s.z, s.h) then
				local top = true
				for _, d in DIRS8 do
					if world:heightAt(s.x + d[1] * 20, s.z + d[2] * 20) > s.h then
						top = false
						break
					end
				end
				if top then
					table.insert(list, { s = s, score = visibility(s.r) + 0.4 * s.jitter + s.h / 200 })
				end
			end
		end
		sortBy(list, "score")
		local crng = Kit.rng(4711)
		local woods = {}
		for _, e in list do
			if spent >= q then
				break
			end
			local c = e.s
			local apart = not behindMountain(c.x, c.z)
			for _, o in woods do
				if (o[1] - c.x) ^ 2 + (o[2] - c.z) ^ 2 < 70 * 70 then
					apart = false
					break
				end
			end
			if apart then
				local fam = family(c)
				local group = `crest{#woods + 1}`
				local target = 5 + floor(c.jitter * 3.99)
				local n = 0
				for _, near in sitesNear(c.x, c.z, 34) do
					if n >= target or spent >= q then
						break
					end
					local s = near.s
					if s.kind ~= "sand" and s.kind ~= "snow" and s.kind ~= "stone" then
						local used = tree(s.x, s.z, speciesOf(fam, crng(), s.h), "far", group, crng(1.9, 2.4))
						if used > 0 then
							n += 1
							spent += used
						end
					end
				end
				if n > 0 then
					table.insert(woods, { c.x, c.z })
					count("crestWood")
				end
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 5a: set-pieces on the biggest open lawns, before the groves take the land (pumpkin
	-- patch, picnic, bee boxes, log pile, mushroom ring, hay), each with a tree or a bush beside
	-- it and a flower clump or two
	--------------------------------------------------------------------------------------------
	do
		local q = quota("sets")
		local spent = 0
		local list = {}
		for _, s in sites do
			if (s.kind == "grass" or s.kind == "meadow") and s.h <= G + 40 and not world:isReserved(s.x, s.z, 8) then
				local e = emptiness(s.x, s.z, 40)
				if e >= 18 then
					table.insert(list, { s = s, score = e / 40 + visibility(s.r) + 0.3 * s.jitter })
				end
			end
		end
		sortBy(list, "score")
		local KINDS = { "pumpkins", "picnic", "bees", "logs", "mushrooms", "hay" }
		local srng = Kit.rng(31337)
		local nSets = 0
		local bySector = {}
		for _, e in list do
			if spent >= q then
				break
			end
			local s = e.s
			-- at most two set-pieces per 45° sector, 60 studs apart
			local sec = floor(s.theta / 45)
			bySector[sec] = bySector[sec] or {}
			local ok = #bySector[sec] < 2
			for _, o in bySector[sec] do
				if (o[1] - s.x) ^ 2 + (o[2] - s.z) ^ 2 < 60 * 60 then
					ok = false
				end
			end
			local h = if ok then flatAt(s.x, s.z, 6.5) else nil
			if
				h
				and affordable(14)
				and fits(s.x, s.z, 0, 8, "set")
				and not Kit.isClaimed(s.x, s.z, 8)
				and offPath(s.x, s.z, 8)
				and not blocked(s.x, s.z, 7, h + 0.2, h + 8)
			then
				local kind = KINDS[nSets % #KINDS + 1]
				nSets += 1
				local before = U.partCount
				-- (facing the lagoon)
				local cf = CFrame.new(s.x, h, s.z) * CFrame.Angles(0, rad(s.theta), 0)
				local seed = floor(srng(1, 1e6))
				if kind == "pumpkins" then
					pumpkinPatch(groups.sets, cf, seed)
				elseif kind == "picnic" then
					picnic(groups.sets, cf, seed)
				elseif kind == "bees" then
					beeBoxes(groups.sets, cf, seed)
				elseif kind == "logs" then
					logPile(groups.sets, cf, seed)
				elseif kind == "mushrooms" then
					mushrooms(groups.sets, cf, seed)
				else
					hayBales(groups.sets, cf, seed)
				end
				addPlaced(s.x, s.z, 0, 7, "set")
				table.insert(bySector[sec], { s.x, s.z })
				count(kind)
				spent += U.partCount - before
				-- company: a tree or a bush beside it, a tuft or two
				local a = srng(0, 2 * math.pi)
				local tx, tz = s.x + 15 * sin(a), s.z + 15 * cos(a)
				local fam = family(s)
				local used = tree(tx, tz, speciesOf(fam, srng(), s.h), "far", "set", srng(1.7, 2.1))
				if used == 0 then
					used = small(tx, tz, "shrub", { scale = 1.3 })
				end
				spent += used
				local pair = pairOf(srng())
				for _, da in { 2.2, 4.0 } do
					spent += small(
						s.x + 10 * sin(a + da),
						s.z + 10 * cos(a + da),
						"tuft",
						{ scale = srng(1.0, 1.3), pair = pair }
					)
				end
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 6: decor — flowers in jewel tones along both sides of the landmark paths (by turns a
	-- drift of flowers on stems, Props.flowerBed, and a pair of clumps of one colour pair, the
	-- sides staggered), then spaced groups round the landmark sites (flowers, bushes, rocks),
	-- bushes and rocks round the plots and plazas and on the terrace lips facing the promenade;
	-- wildflower patches on the mesa and the giant tree's lawn
	--------------------------------------------------------------------------------------------
	do
		local q = quota("decor")
		local spent = 0
		do
			-- the paths (as VoxelWorld:pathDistance draws them): radial strips from the promenade
			local paths = {}
			for name, site in world.landmarks do
				if not (site.peak and not site.path) then
					local reach = if name == "Waterfall"
						then site.pondR - site.pondRadius
						elseif name == "Windmill" then site.radius - site.hillRadius - 4
						elseif name == "GiantTree" then site.radius - site.plateauRadius - 6
						else site.radius - site.mountainRadius + 12
					table.insert(paths, { angle = site.angle, reach = reach })
				end
			end
			table.sort(paths, function(a, b)
				return a.angle < b.angle
			end)
			local outerR = cfg.PromenadeRadius + cfg.PromenadeWidth
			local half = (cfg.PathWidth or 12) / 2
			local frng = Kit.rng(7373)
			local k = 0
			for _, pth in paths do
				for lz = 18, pth.reach - outerR - 8, 26 do
					for _, side in { -1, 1 } do
						if spent >= q * 0.65 then
							break
						end
						k += 1
						local along = lz + (if side > 0 then 13 else 0) -- (the sides staggered)
						local pair = pairOf(frng())
						local used = 0
						-- (the path's 8-stud columns reach ~4 studs past its strip)
						for _, off in { 8.5, 11, 13.5 } do
							local x, z = Kit.radial(pth.angle, outerR, side * (half + off), along)
							if k % 3 == 0 then
								used = small(x, z, "drift", { margin = 1, yaw = pth.angle + 90, pair = pair })
							else
								used = small(x, z, "tuft", { scale = frng(1.4, 1.8), margin = 1, pair = pair })
								if used > 0 then
									local x2, z2 = Kit.radial(pth.angle, outerR, side * (half + off + 1.5), along + 6.5)
									used += small(
										x2,
										z2,
										"tuft",
										{ scale = frng(1.0, 1.3), margin = 1, pair = pair, gap = 0.2 }
									)
								end
							end
							if used > 0 then
								break
							end
						end
						if used > 0 then
							spent += used
							count("pathFlowers")
						end
					end
				end
			end
		end
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
		sortBy(beds, "score")
		local nBeds = 0
		for _, e in beds do
			if nBeds >= 10 or spent >= q * 0.25 then
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
		-- groups within ~14 studs of a path, plot, plaza or landmark site (the paths first), and
		-- on the terrace lips facing the promenade; flowers along the paths and on the low lawns
		-- by the plots, plazas and sites, spaced groups (16 studs apart along the paths, 22
		-- elsewhere) instead of a carpet of dots
		local list = {}
		for _, group in { edgeSites, sites } do
			for _, s in group do
				if s.kind == "grass" or s.kind == "meadow" or s.kind == "grassRock" then
					local score = s.jitter
					if world:isReserved(s.x, s.z, 14) then
						score += if world:pathDistance(s.x, s.z) < 16 then 1.0 else 0.6
					elseif s.h > G and s.r < 560 then
						local ux, uz = s.x / s.r, s.z / s.r
						if world:heightAt(s.x - ux * 8, s.z - uz * 8) <= s.h - 4 then
							score += 0.5 * (1 - smooth(340, 560, s.r))
						else
							score = -1
						end
					else
						score = -1
					end
					if score >= 0 then
						table.insert(list, { s = s, score = score })
					end
				end
			end
		end
		sortBy(list, "score")
		for _, e in list do
			if spent >= q then
				break
			end
			local path = world:pathDistance(e.s.x, e.s.z) < 16
			local gap = if path then 16 else 22
			-- flowers where people walk: along the paths and on the low lawns round the plots,
			-- plazas and landmark sites
			local flowers = path or (e.s.h <= G + 12 and world:isReserved(e.s.x, e.s.z, 14))
			if nearest(e.s.x, e.s.z, gap) >= gap then
				spent += decorGroup(e.s.x, e.s.z, e.s.h, 1.5, flowers)
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 5: groves
	--------------------------------------------------------------------------------------------
	local centres = {}
	do
		local order = {}
		for _, s in sites do
			if s.kind ~= "sand" and s.kind ~= "snow" and s.kind ~= "stone" then
				table.insert(order, { s = s, score = visibility(s.r) + 0.35 * s.grove + 0.25 * s.jitter })
			end
		end
		sortBy(order, "score")
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
	local nextCentre = 1
	local groveCount = 0
	-- A wood edge: up to `n` bushes just outside the trees planted round (cx, cz), on the side of
	-- the grove away from its centre (a bush with berries now and then).
	local function woodEdge(cx: number, cz: number, trees: { { number } }, n: number, roll: number): number
		local spent, done = 0, 0
		for k = 1, #trees do
			if done >= n then
				break
			end
			local t = trees[(k + floor(roll * 7)) % #trees + 1]
			local dx, dz = t[1] - cx, t[2] - cz
			local d = sqrt(dx * dx + dz * dz)
			if d > 4 then
				local out = t[3] + 4
				local px, pz = t[1] + dx / d * out, t[2] + dz / d * out
				local berry = if (roll * 13 + k) % 1 < 0.3 then bloomOf((roll * 31 + k * 0.37) % 1) else nil
				local used =
					small(px, pz, "shrub", { scale = 1.2 + 0.3 * ((roll * 17 + k) % 1), berry = berry, gap = 0.4 })
				if used > 0 then
					spent += used
					done += 1
				end
			end
		end
		return spent
	end
	local function groves(q: number): number
		local spent = 0
		while nextCentre <= #centres and spent < q do
			local c = centres[nextCentre]
			nextCentre += 1
			local fam = family(c)
			-- woods, not dots: 5-9 trees whose canopies touch
			local target = 5 + floor(c.jitter * 4.99)
			local planted = {}
			for _, e in sitesNear(c.x, c.z, 46) do
				if #planted >= target or spent >= q then
					break
				end
				local s = e.s
				if s.kind ~= "sand" and s.kind ~= "snow" and not behindMountain(s.x, s.z) then
					-- the waterfall mesa top always blossoms, whatever grove reaches it
					local f = if onMesa(s.x, s.z, s.h) then "blossom" else fam
					local level = detail(s.x, s.z)
					local kind = speciesOf(f, (s.jitter * 7.31) % 1, s.h)
					local used = tree(s.x, s.z, kind, level, fam)
					if used > 0 then
						spent += used
						table.insert(planted, { s.x, s.z, 12 })
					end
				end
			end
			if #planted > 0 then
				groveCount += 1
				-- bushes on the wood's edge
				spent += woodEdge(c.x, c.z, planted, if #planted >= 4 then 2 else 1, c.jitter)
			end
		end
		return spent
	end
	do
		local q = quota("groves")
		finishPass(q, groves(q))
	end

	--------------------------------------------------------------------------------------------
	-- Pass 7: fill — coverage rounds over every land spot, most visible first: a copse (a tree
	-- and up to two neighbours of its family, a bush on its edge) where nothing is within 34
	-- studs, then a bush or a rock group where nothing is within 26 (no flowers: the lawns stay
	-- calm); palms and beach rocks on the empty sand; more groves with the rest of the budget
	--------------------------------------------------------------------------------------------
	do
		local order = {}
		for _, s in sites do
			if s.kind ~= "snow" and s.kind ~= "stone" and not behindMountain(s.x, s.z) then
				table.insert(order, { s = s, score = visibility(s.r) + 0.5 * s.jitter })
			end
		end
		for _, s in edgeSites do
			if s.kind == "grass" or s.kind == "meadow" or s.kind == "sand" then
				table.insert(order, { s = s, score = visibility(s.r) + 0.5 * s.jitter - 0.3 })
			end
		end
		sortBy(order, "score")
		local frng = Kit.rng(5150)
		local copses = 0
		for _, T in { 34, 26 } do
			for _, e in order do
				if not affordable(3) then
					break
				end
				local s = e.s
				if emptiness(s.x, s.z, T) >= T then
					if s.kind == "sand" then
						if s.r > 500 then
							tree(s.x, s.z, "palm", "far", "palm", frng(1.7, 2.2))
						else
							small(
								s.x,
								s.z,
								"rock",
								{ scale = frng(0.9, 1.2), color = BEACH_ROCK, cap = "moss", margin = 2 }
							)
						end
					elseif T >= 34 then
						-- a copse: up to three trees of one family whose canopies touch
						local fam = family(s)
						copses += 1
						local group = `copse{copses}`
						local planted = {}
						local a0 = frng(0, 2 * math.pi)
						for k = 0, 4 do
							if #planted >= 3 then
								break
							end
							local x, z = s.x, s.z
							if k > 0 then
								local a = a0 + k * 1.2566
								x, z = s.x + 19 * sin(a), s.z + 19 * cos(a)
							end
							local h = world:heightAt(x, z)
							local used = tree(x, z, speciesOf(fam, frng(), h), detail(x, z), group, nil)
							if used > 0 then
								table.insert(planted, { x, z, 12 })
							elseif k == 0 then
								break
							end
						end
						if #planted > 0 then
							count("copse")
							woodEdge(s.x, s.z, planted, 1, frng())
						else
							decorGroup(s.x, s.z, s.h, 2, false)
						end
					else
						decorGroup(s.x, s.z, s.h, 2, false)
					end
				end
			end
		end
		-- whatever is left: more groves
		local left = budget - spentAll()
		if left > 20 then
			groves(left - 10)
		end
	end

	--------------------------------------------------------------------------------------------
	-- Last: two neighbouring pieces whose side faces happen to share a plane (two canopies of a
	-- grove, a bloom against a rock) would flicker; the later one moves 0.15 stud away. Nature
	-- turns its pieces by quarter turns only, so every part is a box on the world axes.
	--------------------------------------------------------------------------------------------
	do
		local boxes = {}
		local cells: { [number]: { number } } = {}
		for gi, group in { groups.trees, groups.plants, groups.rocks, groups.sets } do
			for mi, model in group:GetChildren() do
				local id = gi * 100000 + mi
				for _, p in model:GetDescendants() do
					if p:IsA("BasePart") then
						local cf, size = p.CFrame, p.Size
						local pos = cf.Position
						local rx, ry, rz = cf.RightVector, cf.UpVector, cf.LookVector
						local ex = (abs(rx.X) * size.X + abs(ry.X) * size.Y + abs(rz.X) * size.Z) / 2
						local ey = (abs(rx.Y) * size.X + abs(ry.Y) * size.Y + abs(rz.Y) * size.Z) / 2
						local ez = (abs(rx.Z) * size.X + abs(ry.Z) * size.Y + abs(rz.Z) * size.Z) / 2
						local box =
							{ pos.X - ex, pos.X + ex, pos.Y - ey, pos.Y + ey, pos.Z - ez, pos.Z + ez, id, model }
						table.insert(boxes, box)
						for ix = floor(box[1] / OB), floor(box[2] / OB) do
							for iz = floor(box[5] / OB), floor(box[6] / OB) do
								local k = (ix + 200) * 1000 + iz + 200
								cells[k] = cells[k] or {}
								table.insert(cells[k], #boxes)
							end
						end
					end
				end
			end
		end
		local function overlap(a0: number, a1: number, b0: number, b1: number): boolean
			return min(a1, b1) - max(a0, b0) > 0.05
		end
		local conflicts = {}
		local seen = {}
		for _, list in cells do
			for i = 1, #list do
				for j = i + 1, #list do
					local a, b = boxes[list[i]], boxes[list[j]]
					local key = min(list[i], list[j]) * 1e6 + max(list[i], list[j])
					if a[7] ~= b[7] and not seen[key] then
						seen[key] = true
						-- the later model of the pair moves
						local later = if a[7] > b[7] then a else b
						local other = if later == a then b else a
						local dx, dz = 0, 0
						if
							(abs(a[1] - b[1]) < 0.06 or abs(a[2] - b[2]) < 0.06)
							and overlap(a[3], a[4], b[3], b[4])
							and overlap(a[5], a[6], b[5], b[6])
						then
							dx = if (later[1] + later[2]) >= (other[1] + other[2]) then 0.15 else -0.15
						elseif
							(abs(a[5] - b[5]) < 0.06 or abs(a[6] - b[6]) < 0.06)
							and overlap(a[3], a[4], b[3], b[4])
							and overlap(a[1], a[2], b[1], b[2])
						then
							dz = if (later[5] + later[6]) >= (other[5] + other[6]) then 0.15 else -0.15
						end
						if dx ~= 0 or dz ~= 0 then
							table.insert(conflicts, { later[7], dx, dz, later[8] })
						end
					end
				end
			end
		end
		-- (sorted: the result never depends on the hash's iteration order)
		table.sort(conflicts, function(p, q)
			if p[1] ~= q[1] then
				return p[1] < q[1]
			elseif p[2] ~= q[2] then
				return p[2] < q[2]
			end
			return p[3] < q[3]
		end)
		local moved = {}
		for _, c in conflicts do
			if not moved[c[1]] then
				moved[c[1]] = true
				counts.nudged = (counts.nudged or 0) + 1
				local d = Vector3.new(c[2], 0, c[3])
				for _, p in c[4]:GetDescendants() do
					if p:IsA("BasePart") then
						p.CFrame = p.CFrame + d
					end
				end
			end
		end
	end

	counts.groves = groveCount
	return counts
end

return Nature
