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
	bounding boxes are hashed first). Objects keep their distance: two trees at least 0.9 × (sum
	of canopy radii) apart, along x or z too (square canopies never meet on the diagonal; 1.0
	between different groups, 0.62 between palms: fronds may cross), small things clear of
	trunks and of each other.

	Most of the budget goes into cheap pieces (2-5 parts) so the land reads full: 5-part voxel
	trees (Nature.farTree), 3-part flower tufts, 2-3 part bushes, 3-4 part rocks (warm light
	greys with a moss cap, always with a tuft or a bush beside them), hay bales, short fence
	runs, and set-pieces of 5-10 parts (pumpkin patch with a scarecrow, picnic blanket, bee
	boxes, log pile, mushroom ring).

	Passes, each with its share of the budget (unspent parts carry over to the next one):
	  reef    coral clusters (2-3 blocks in coral colours) on the lagoon bed, seen through the
	          water; the water in front of the piers and along the bridges stays clear
	  coast   a pair of palms every ~65 studs of the outer beaches; between the pairs, by turns,
	          a beach set (parasol with a towel, sandcastle, towel and ball, driftwood) and a rock
	          group at the waterline in a ring of foam; foamy rocks in the surf below the cliffs
	  pines   up to 14 pines on the grassy flanks of each mountain, snow-dusted higher up, and a
	          few snow-capped rocks
	  belts   a continuous tree line behind every plot's back wall (two rows, round-robin over
	          the plots), one tree family per plot by the biome noise
	  crests  trees on the hill crests (local high points): the skyline behind the plots
	  groves  groves of 4-7 trees (centres ~80 studs apart, round-robin over the 16 sectors of
	          22.5°, most visible first); one family per grove by height and a ~260-stud biome
	          noise: cherry (pink), autumn (orange / gold), mixed green, pines up high, blossom
	          on the waterfall mesa
	  decor   cheap colour where people walk: tufts, bushes, rock groups and fences along both
	          sides of the paths, round the plots, plazas and landmark sites, on the terrace lips
	          facing the promenade; flower meadows on the waterfall mesa and the giant tree's lawn
	  sets    set-pieces on the biggest open lawns, spread over the sectors
	  fill    coverage: rounds over every land spot, most visible first, each placing something
	          wherever nothing (Nature or other dressing) is within 30 / 22 / 16 studs — a tree
	          with a bush on the big gaps, cheap decor on the rest; more groves with what is left
	Level of detail by distance to the play area: full Props trees (13-16 parts) only right beside
	the landmark paths (at most FULL_CAP), compact Props lite trees (6-10) within ~50 studs of the
	play area, the 5-part trees built here everywhere else (Coast.luau uses them on the islets
	too). The biggest canopy block of every tree casts a shadow; small foliage does not.
	Returns counts per kind (printed by tools/build.luau).
]]

local U = require("./Util")
local Kit = require("./MapKit")

local CFrame = U.CFrame
local C = Kit.C

local sqrt, deg, atan2, floor, abs, min, max = math.sqrt, math.deg, math.atan2, math.floor, math.abs, math.min, math.max
local sin, cos, rad = math.sin, math.cos, math.rad

local Nature = {}

-- Share of the budget per pass (the rest of a pass's share carries over).
local SHARE = {
	coast = 0.17,
	pines = 0.12,
	belts = 0.16,
	crests = 0.06,
	groves = 0.12,
	decor = 0.1,
	sets = 0.06,
	fill = 0.21,
}
-- Most full Props trees (13-16 parts): only the ones right beside the paths and plazas.
local FULL_CAP = 16

local FOLIAGE = Kit.DECOR
local CANOPY = { CanCollide = false, CanQuery = false, CastShadow = true } -- the one shadow block
local BEACH_ROCK = Kit.lerpColor(C.StoneLight, C.SandDark, 0.4) -- warm light rocks on the sand
-- Rocks: warm light greys (not the cool Stone of the cliffs: grey boxes read as concrete on
-- the lime lawns).
local ROCK = U.rgb(190, 190, 204)
local ROCK_DARK = U.rgb(166, 168, 184)
local HAY = { U.rgb(236, 196, 88), U.rgb(250, 220, 118) }
local FOAM = U.rgb(250, 254, 255)

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
-- Height of the lowest foliage above the foot (studs at scale 1): nothing round a tree may
-- stand higher than this within its canopy.
local CANOPY_BOTTOM = { far = 4.6, farPine = 2.4, farPalm = 9.6, broad = 4.1, birch = 7.2, pine = 1.9, palm = 8.5 }
-- Trunk half-width (studs at scale 1, incl. jitter and roots).
local TRUNK_R = { full = 2.6, lite = 1.6, far = 1.4 }

-- Bright bloom colours for flowers (no white: it reads as sugar lumps).
local BLOOMS = { C.Red, C.Yellow, C.Pink, C.Purple, C.Orange, C.Blue }

local function smooth(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- A colour from `list` other than `c`.
local function other(list: { any }, c: any, roll: number): any
	local i = table.find(list, c) or 1
	return list[(i + floor(roll * (#list - 1)) % (#list - 1)) % #list + 1]
end

--------------------------------------------------------------------------------------------
-- Cheap far trees (5 parts)
--------------------------------------------------------------------------------------------

--[[
	Nature.farTree(parent, cf, kind, scale, seed): a 5-part voxel tree for far hills, tree belts
	and islets (the silhouettes of the Props trees with fewer blocks).
	  "green" | "lime" | "cherry" | "autumn" | "gold"  trunk and a three-step pyramid: a wide
	                                                   dark base, a mid "plus" of two blocks
	                                                   (the shadow caster), a small light top
	  "pine" | "snowPine"   trunk, a stepped cone of three tiers (dark to light) and a tip
	  "palm"                two trunk segments (the upper one leaning a little, overlapping the
	                        lower by 0.6 · scale: one bent trunk), crown, two crossed fronds
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
		local lean = r(0.4, 0.8)
		trunk = box("Trunk1", -1.0, -1 / s, -1.0, 1.0, 5.6, 1.0, C.PalmBark)
		box("Trunk2", lean - 0.8, 5.0, -0.8, lean + 0.8, 10.4, 0.8, C.PalmBarkDark)
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

--------------------------------------------------------------------------------------------
-- Cheap decor (2-4 parts) and set-pieces (5-10 parts); all stand on cf (front -Z)
--------------------------------------------------------------------------------------------

local function turned(cf: any, r: (number?, number?) -> number): any
	return cf * CFrame.Angles(0, rad(90 * floor(r(0, 3.99))), 0)
end

-- Flower tuft (3 parts): a leafy mound with two blooms half sunk into it, two colours.
local function tuft(parent: any, cf: any, s: number, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "Flowers", turned(cf, r))
	local w, d, h = r(1.8, 2.2) * s, r(1.4, 1.8) * s, r(1.0, 1.3) * s
	local mound = b:box("Leaves", -w, -0.3, -d, w, h, d, BUSH[2], FOLIAGE)
	local c1 = BLOOMS[floor(r(1, #BLOOMS + 0.99))]
	local c2 = other(BLOOMS, c1, r())
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
	local light = Kit.lerpColor(body, C.White, 0.22)
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
	local fw, fd = w / 2 + r(1.0, 1.6), d / 2 + r(1.0, 1.6)
	b:box("Foam", -fw, -bed - 0.05, -fd, fw, -bed + 0.2, fd, FOAM, FOLIAGE)
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
	local post = if white then C.White else C.Wood
	local rail = if white then C.Cream else C.WoodLight
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

-- Scarecrow (5 parts): a post, a cross bar, a bright shirt, a straw head and a hat.
local function scarecrow(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "Scarecrow", cf)
	local post = b:box("Post", -0.3, -0.5, -0.3, 0.3, 5.0, 0.3, C.Wood)
	b:box("Arms", -2.6, 3.7, -0.25, 2.6, 4.2, 0.25, C.Wood, Kit.NOSHADOW)
	b:box("Shirt", -1.0, 2.6, -0.6, 1.0, 4.6, 0.6, if r() < 0.5 then C.Blue else C.Red)
	b:box("Head", -0.7, 4.55, -0.7, 0.7, 5.95, 0.7, HAY[2])
	b:box("Hat", -1.15, 5.9, -1.15, 1.15, 6.6, 1.15, C.WoodDark)
	return b:finish(post)
end

-- Picnic spot (5 parts): a red blanket with two white stripes and a basket with its lid.
local function picnic(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "Picnic", turned(cf, r))
	local col = if r() < 0.5 then C.Red else C.Blue
	local blanket = b:box("Blanket", -3.2, -0.1, -2.6, 3.2, 0.14, 2.6, col, Kit.NOSHADOW)
	b:box("StripeA", -1.6, 0.05, -2.62, -0.8, 0.2, 2.62, C.White, FOLIAGE)
	b:box("StripeB", 0.8, 0.05, -2.62, 1.6, 0.2, 2.62, C.White, FOLIAGE)
	b:box("Basket", 1.9, 0.1, -1.9, 3.7, 1.3, -0.7, C.Wood)
	b:box("Lid", 1.75, 1.25, -2.05, 3.85, 1.6, -0.55, C.WoodLight)
	return b:finish(blanket)
end

-- Bee boxes (6 parts): three hives (a cream box under a coloured roof) in a row.
local function beeBoxes(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "BeeBoxes", turned(cf, r))
	local first
	for i = 1, 3 do
		local x = (i - 2) * 3.4
		local h = r(2.0, 2.6)
		local box = b:box(`Hive{i}`, x - 1.0, -0.3, -1.0, x + 1.0, h, 1.0, if i == 2 then C.White else C.Cream)
		first = first or box
		b:box(`Roof{i}`, x - 1.3, h - 0.05, -1.3, x + 1.3, h + 0.5, 1.3, if i == 2 then C.Orange else C.Yellow)
	end
	return b:finish(first)
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

-- Mushroom ring (6 parts): three mushrooms (white stem, red / orange / purple cap).
local function mushrooms(parent: any, cf: any, seed: number): any
	local r = Kit.rng(seed)
	local b = Kit.builder(parent, "Mushrooms", turned(cf, r))
	local first
	local caps = { C.Red, C.Orange, C.Purple }
	for i, p in { { -2.0, -1.0, 1.0 }, { 1.6, -1.6, 0.8 }, { 0.6, 1.9, 0.65 } } do
		local x, z, s = p[1], p[2], p[3]
		local h = r(1.6, 2.2) * s
		local stem = b:box(`Stem{i}`, x - 0.45 * s, -0.2, z - 0.45 * s, x + 0.45 * s, h, z + 0.45 * s, C.Cream)
		first = first or stem
		b:box(`Cap{i}`, x - 1.3 * s, h - 0.1, z - 1.3 * s, x + 1.3 * s, h + 0.9 * s, z + 1.3 * s, caps[i], FOLIAGE)
	end
	return b:finish(first)
end

-- Beach props: a parasol with a towel (4 parts), a sandcastle with a flag (4), a towel with a
-- beach ball (3), driftwood (2), a starfish (2).
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
	elseif kind == "towel" then
		local col = if r() < 0.5 then C.Pink else C.Cyan
		first = b:box("Towel", -1.4, 0, -2.6, 1.4, 0.16, 2.6, col, FOLIAGE)
		b:box("Stripe", -1.55, 0.04, -0.4, 1.55, 0.24, 0.4, C.White, FOLIAGE)
		b:box("Ball", 2.0, -0.1, -0.8, 3.4, 1.3, 0.6, if col == C.Pink then C.Yellow else C.Red, FOLIAGE)
	elseif kind == "driftwood" then
		first = b:box("Log", -3.4, -0.3, -0.7, 3.4, 0.9, 0.7, Kit.lerpColor(C.WoodLight, C.White, 0.25))
		b:box("Branch", 0.6, -0.2, 0.6, 1.5, 0.7, 2.8, Kit.lerpColor(C.WoodLight, C.White, 0.2))
	else
		local col = if r() < 0.5 then C.Pink else C.Orange
		first = b:box("ArmA", -1.3, 0, -0.4, 1.3, 0.3, 0.4, col, FOLIAGE)
		b:box("ArmB", -0.4, 0.02, -1.3, 0.4, 0.32, 1.3, col, FOLIAGE)
	end
	return b:finish(first)
end

-- Coral cluster (2-3 parts) on the lagoon bed (cf at the bed, y `bed`): a head, a branch
-- beside it in another colour and sometimes a fan on top; everything stays under the water.
local CORAL = {
	U.rgb(255, 120, 120),
	U.rgb(255, 180, 60),
	U.rgb(170, 96, 255),
	U.rgb(255, 224, 80),
	U.rgb(255, 104, 184),
}
local function coral(parent: any, cf: any, bed: number, r: (number?, number?) -> number): any
	local b = Kit.builder(parent, "Coral", cf)
	local c1 = CORAL[floor(r(1, #CORAL + 0.99))]
	local c2 = other(CORAL, c1, r())
	local w, d = r(4.5, 7), r(3.5, 5.5)
	local top = -bed - 0.6 -- (highest top above the bed: 0.6 under the surface)
	local h1 = if bed <= -14 then r(5, 8) elseif bed <= -6 then r(2, 3.2) else r(0.6, 1.0)
	local main = b:box("Head", -w / 2, -0.4, -d / 2, w / 2, h1, d / 2, c1, FOLIAGE)
	local s = r(2.2, 3.2) -- (always narrower than the head: no side faces in one plane)
	local ox = w / 2 + s / 2 - 0.6
	local h2 = min(h1 * (if r() < 0.5 then r(0.5, 0.8) else r(1.15, 1.35)), top)
	b:box("Branch", ox - s / 2, -0.6, -s / 2, ox + s / 2, h2, s / 2, c2, FOLIAGE)
	if r() < 0.45 and h1 + 1.2 < top then
		local t = r(1.0, 1.5)
		local h3 = min(h1 + r(1, 2.5), top - 0.4)
		b:box("Fan", -w / 4 - t / 2, h1 - 0.3, -t / 2, -w / 4 + t / 2, h3, t / 2, other(CORAL, c1, r()), FOLIAGE)
	end
	return b:finish(main)
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
	local maxR = cfg.RingOuterRadius + 80
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
							local k = if palms then 0.62 elseif fam ~= o[5] then 1.0 else 0.9
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
		far = 5,
		tuft = 3,
		shrub = 3,
		rock = 4,
		hay = 3,
		fence = 4,
		meadow = 5,
	}
	local fullTrees = 0
	local seedRng = Kit.rng(9001)

	-- Places a tree of `kind` ("oak" | "round" | "birch" | "cherry" | "autumn" | "gold" |
	-- "pine" | "snowPine" | "palm") at (x, z) if it fits; `level` = "full" | "lite" | "far";
	-- `fam` = its group (trees of one group may touch). Returns the parts spent (0 = none).
	local function tree(x: number, z: number, kind: string, level: string, fam: string, scale: number?): number
		if level == "full" and fullTrees >= FULL_CAP then
			level = "lite"
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
		local seed = floor(seedRng(1, 1e6))
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
			local base = if kind == "snowPine" then "pine" elseif kind == "gold" then "autumn" else kind
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
		local h = flatAt(x, z, TRUNK_R[level] * s)
		if not h or not fits(x, z, canopy, 0, fam) or not clearCanopy(x, z, h, canopy, bottom) then
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
				m = Kit.prop("oakTree", groups.trees, cf, { seed = seed, scale = s, lite = lite, compact = lite })
			elseif kind == "round" then
				m = Kit.prop(
					"roundTree",
					groups.trees,
					cf,
					{ seed = seed, scale = s, lite = lite, compact = lite, palette = "mixed" }
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
				m = Kit.prop("autumnTree", groups.trees, cf, { seed = seed, scale = s, lite = lite, compact = lite })
			end
			settleLitter(m)
			shadows(m)
			if level == "full" then
				fullTrees += 1
			end
		end
		addPlaced(x, z, canopy, 0, fam)
		count(kind)
		count(level)
		return U.partCount - before
	end

	-- Small things: "tuft" | "shrub" | "rock" | "hay" | "fence" | "meadow" (footprint radius by
	-- kind and size). opts: scale, gap (extra clearance), margin (distance kept from reserved
	-- ground; small decor may hug the paths and plots), berry (shrubs), cap / color (rocks),
	-- yaw (fences), white (fences).
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
		local height = if kind == "fence" or kind == "hay" or kind == "rock" then 5 else 3.5
		if blocked(x, z, radius, h + 0.2, h + height) then
			return 0
		end
		local before = U.partCount
		local cf = CFrame.new(x, h, z)
		if kind == "tuft" then
			tuft(groups.plants, cf, s, seed)
		elseif kind == "shrub" then
			shrub(groups.plants, cf, s, seed, o.berry)
		elseif kind == "meadow" then
			Kit.flowerMeadow(groups.plants, cf, seed)
		elseif kind == "hay" then
			hayBales(groups.sets, cf, seed)
		elseif kind == "fence" then
			fence(groups.sets, cf * CFrame.Angles(0, rad(o.yaw or 0), 0), 8, o.white == true)
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
		elseif s.h >= G + 60 or (s.h >= G + 28 and nearPeak(s.x, s.z, 20)) then
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
			return if roll < 0.72 then "cherry" elseif roll < 0.88 then "round" else "pine"
		elseif fam == "autumn" then
			return if roll < 0.45 then "autumn" elseif roll < 0.7 then "gold" elseif roll < 0.88 then "oak" else "pine"
		end
		return if roll < 0.42 then "oak" elseif roll < 0.68 then "round" else "pine"
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
	local function quota(name: string): number
		return budget * SHARE[name] + carry
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
	-- One cheap decor group at (x, z) on ground h: a tuft, a bush (sometimes with berries), a
	-- rock group, two tufts, or on the low lawns hay bales or a short fence run.
	local drng = Kit.rng(6060)
	local function decorGroup(x: number, z: number, h: number, margin: number): number
		local roll = drng()
		local farm = h <= G + 16
		if roll < 0.32 then
			return small(x, z, "tuft", { scale = drng(1.0, 1.4), margin = margin })
		elseif roll < 0.55 then
			local berry = if drng() < 0.5 then BLOOMS[floor(drng(1, #BLOOMS + 0.99))] else nil
			return small(x, z, "shrub", { scale = drng(1.0, 1.4), margin = margin, berry = berry })
		elseif roll < 0.7 then
			return rockGroup(x, z, drng(0.9, 1.3), margin, drng)
		elseif roll < 0.8 then
			local used = small(x, z, "tuft", { scale = drng(1.0, 1.3), margin = margin })
			if used > 0 then
				local a = drng(0, 2 * math.pi)
				used += small(x + 5.5 * sin(a), z + 5.5 * cos(a), "tuft", { scale = drng(0.8, 1.1), margin = margin })
			end
			return used
		elseif roll < 0.9 and farm then
			return small(x, z, "hay", { margin = margin + 1 })
		elseif farm then
			-- along the slope (tangential): a field edge
			local yaw = deg(atan2(x, z)) + drng(-20, 20)
			return small(x, z, "fence", { margin = margin + 1, yaw = yaw, white = drng() < 0.4 })
		end
		return small(x, z, "shrub", { scale = drng(1.1, 1.5), margin = margin })
	end

	--------------------------------------------------------------------------------------------
	-- Pass 0: coral reefs on the lagoon bed (2-3 blocks each in coral colours, seen through the
	-- water from the piers, bridges and the promenade); the water in front of the piers and
	-- along the bridges stays clear
	--------------------------------------------------------------------------------------------
	do
		local reef = U.model(nature, "Reef")
		local function clear(x: number, z: number): boolean
			for i = 1, cfg.BaseCount do
				local lx, lz = world:toBaseLocal(i, x, z)
				if abs(lx) < 29 and lz > -(cfg.PierLength or 92) - 3 and lz < 3 then
					return false
				end
			end
			for _, a in cfg.BridgeAngles do
				local ux, uz = sin(rad(a)), cos(rad(a))
				if x * ux + z * uz > cfg.HubPlazaRadius - 10 and abs(x * uz - z * ux) < cfg.BridgeWidth / 2 + 13 then
					return false
				end
			end
			return world:isWater(x, z)
		end
		local step = 30
		local r0, r1 = cfg.HubRadius + 12, cfg.LagoonRadius - 10
		for gz = -r1, r1, step do
			for gx = -r1, r1, step do
				-- (one generator per grid cell: a cluster never shifts its neighbours)
				local r = Kit.rng(8086 + (gx + 1000) * 7919 + (gz + 1000) * 31)
				r()
				local x, z = gx + r(-9, 9), gz + r(-9, 9)
				local roll = r()
				local d = sqrt(x * x + z * z)
				local bed = world:heightAt(x, z)
				if
					d < r0
					or d > r1
					or bed > -2
					or roll > 0.5
					or not affordable(3)
					or not clear(x, z)
					or blocked(x, z, 5, bed, 0)
				then
					continue
				end
				coral(reef, CFrame.new(x, bed, z) * CFrame.Angles(0, rad(r(0, 90)), 0), bed, r)
				count("coral")
			end
		end
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
		-- a rock on the shallow bed past the sand (or the cliff foot) in a ring of foam
		local function foamRock(smp: any, from: number, to: number): number
			for r = from, to, 2 do
				local x, z = r * smp.ux, r * smp.uz
				local h, _, water = world:surfaceAt(x, z)
				if water and h >= -4 and h <= -2 and affordable(4) and fits(x, z, 0, 4.5, "rock") then
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
	-- Pass 2: pines on the mountains' grassy flanks (snow-dusted higher up) and a few rocks
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
				if d < p.mountainRadius + 10 and s.h >= G + 8 and (s.kind == "grass" or s.kind == "grassRock") then
					table.insert(
						list,
						{ s = s, score = s.grove * 0.6 + s.jitter + (if s.kind == "grassRock" then 0.4 else 0) }
					)
				end
			end
			sortBy(list, "score")
			perPeak[i] = list
		end
		-- round-robin over the mountains so each gets its share
		local idx, placedOn = {}, {}
		for i in peaks do
			idx[i], placedOn[i] = 1, 0
		end
		local progress = true
		while progress and spent < q do
			progress = false
			for i in peaks do
				local list = perPeak[i]
				while idx[i] <= #list and placedOn[i] < 14 do
					local s = list[idx[i]].s
					idx[i] += 1
					local kind = if s.h >= G + 60 then "snowPine" else "pine"
					local level = if world:isReserved(s.x, s.z, 50) then "lite" else "far"
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
		-- snow-capped rocks on the stone flanks
		local rrng = Kit.rng(2024)
		for _, p in peaks do
			local n = 0
			for _, s in sites do
				if n >= 2 or spent >= q then
					break
				end
				local d = sqrt((s.x - p.x) ^ 2 + (s.z - p.z) ^ 2)
				if d < p.mountainRadius and (s.kind == "stone" or s.kind == "grassRock") and s.jitter > 0.9 then
					local used = small(s.x, s.z, "rock", { scale = rrng(1.3, 1.7), cap = "snow", color = C.StoneLight })
					if used > 0 then
						n += 1
						spent += used
					end
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
	-- Pass 4: trees on the hill crests (the skyline behind the plots)
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
		for _, e in list do
			if spent >= q then
				break
			end
			local s = e.s
			local fam = family(s)
			spent += tree(s.x, s.z, speciesOf(fam, crng(), s.h), "far", "crest", crng(2.0, 2.5))
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
	-- sites within 40 studs of each centre (closest first, ragged edges)
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
			local target = 4 + floor(c.jitter * 3.99)
			local planted = 0
			for _, e in sitesNear(c.x, c.z, 40) do
				if planted >= target or spent >= q then
					break
				end
				local s = e.s
				if s.kind ~= "sand" and s.kind ~= "snow" then
					-- the waterfall mesa top always blossoms, whatever grove reaches it
					local f = if onMesa(s.x, s.z, s.h) then "blossom" else fam
					local level = detail(s.x, s.z)
					local kind = speciesOf(f, (s.jitter * 7.31) % 1, s.h)
					local used = tree(s.x, s.z, kind, level, fam)
					if used > 0 then
						spent += used
						planted += 1
					end
				end
			end
			if planted > 0 then
				groveCount += 1
				-- a bush or a tuft at the grove's edge
				local a = (c.jitter * 997) % (2 * math.pi)
				local bx, bz = c.x + 22 * sin(a), c.z + 22 * cos(a)
				spent += if c.jitter < 0.5
					then small(bx, bz, "shrub", { scale = 1.3 })
					else small(bx, bz, "tuft", { scale = 1.2 })
			end
		end
		return spent
	end
	do
		local q = quota("groves")
		finishPass(q, groves(q))
	end

	--------------------------------------------------------------------------------------------
	-- Pass 6: decor — cheap colour along the paths, round the plots, plazas and landmark
	-- sites, on the terrace lips facing the promenade; meadows on the mesa and the giant
	-- tree's lawn
	--------------------------------------------------------------------------------------------
	do
		local q = quota("decor")
		local spent = 0
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
		-- on the terrace lips facing the promenade
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
			if nearest(e.s.x, e.s.z, 12) >= 12 then
				spent += decorGroup(e.s.x, e.s.z, e.s.h, 1.5)
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 7: set-pieces on the biggest open lawns (pumpkin patch with a scarecrow, picnic,
	-- bee boxes, log pile, mushroom ring, hay and a fence)
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
				-- (facing the lagoon: the scarecrow stands behind the patch)
				local cf = CFrame.new(s.x, h, s.z) * CFrame.Angles(0, rad(s.theta), 0)
				local seed = floor(srng(1, 1e6))
				if kind == "pumpkins" then
					pumpkinPatch(groups.sets, cf, seed)
					scarecrow(groups.sets, cf * CFrame.new(0, 0, 6.2), seed)
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
				for _, da in { 2.2, 4.0 } do
					spent += small(s.x + 10 * sin(a + da), s.z + 10 * cos(a + da), "tuft", { scale = srng(1.0, 1.3) })
				end
			end
		end
		finishPass(q, spent)
	end

	--------------------------------------------------------------------------------------------
	-- Pass 8: fill — coverage rounds over every land spot, most visible first: a tree with a
	-- bush where nothing is within 30 studs, then cheap decor where nothing is within 22 and 16
	-- studs; more groves with the rest of the budget
	--------------------------------------------------------------------------------------------
	do
		local order = {}
		for _, s in sites do
			if s.kind ~= "snow" and s.kind ~= "stone" then
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
		for _, T in { 30, 22, 16 } do
			for _, e in order do
				if not affordable(3) then
					break
				end
				local s = e.s
				if emptiness(s.x, s.z, T) >= T then
					if s.kind == "sand" then
						if s.r > 500 and T >= 22 then
							tree(s.x, s.z, "palm", "far", "palm", frng(1.7, 2.2))
						else
							small(
								s.x,
								s.z,
								"rock",
								{ scale = frng(0.9, 1.2), color = BEACH_ROCK, cap = "moss", margin = 2 }
							)
						end
					elseif T >= 30 then
						local fam = family(s)
						local level = detail(s.x, s.z)
						local used = tree(s.x, s.z, speciesOf(fam, frng(), s.h), level, "fill", nil)
						if used > 0 then
							local a = frng(0, 2 * math.pi)
							small(s.x + 13 * sin(a), s.z + 13 * cos(a), "shrub", { scale = frng(1.1, 1.4) })
						else
							decorGroup(s.x, s.z, s.h, 2)
						end
					else
						decorGroup(s.x, s.z, s.h, 2)
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

	counts.groves = groveCount
	return counts
end

return Nature
