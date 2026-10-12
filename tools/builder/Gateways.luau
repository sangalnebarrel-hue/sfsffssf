--[[
	Gateways — the 4 themed plazas behind the bridge landings (world.gateways, r ≈ 372,
	radius 40, flat GroundTop), each with a way up the hill behind it to a viewpoint, so the
	strongest sightline of the map (bridge → welcome arch → plaza) leads somewhere.
	Each Map.Gateways.Gateway_N has:
	  • a big welcome arch over the coral entry road with a name board («СЕВЕРНЫЕ ВОРОТА» …) in
	    the gateway colour, each with its own silhouette (see ARCHES): a rainbow arch with a
	    spinning pinwheel, a hedge arch with giant tulips, a harbour arch of masts with a hanging
	    anchor, a log arch with totem heads;
	  • warm two-tone paving in its own footprint, and its own layout — the axis from the arch
	    to the hill path stays open, the centrepiece stands off it (decorated on every side);
	    every stall and board faces the plaza:
	      north (180) fish market   a square market (checker paving): two stalls (fish, tackle),
	                                the golden fish fountain off the axis, a barrel, a notice
	                                board; wooden steps up the fishermen's slope (drying racks
	                                with fish, upturned boats, fishers' huts) to a deck beside
	                                the lighthouse (rails, bench, telescope)
	      east  (90)  flower garden round plaza with hedge beds round a cross of paths, the giant
	                                flower on its bed off the axis (petals both sides), a flower
	                                arch over the axis, a photo frame, the flower stall; a ramped
	                                garden path between long tulip terraces to a pink gazebo
	      south (0)   playground    round plaza with a blue play mat: play tower with a slide
	                                off the axis, a sandpit with a castle, swings, a seesaw, the
	                                ice cream stall; stone steps up a little farm (long crop
	                                beds, a red barn, a scarecrow) to a lookout deck with a long
	                                slide down
	      west  (270) picnic camp   a meadow with a paved path and a camp off the axis: a sand
	                                clearing round the fire circle (totem carved on the back too,
	                                a smoking campfire, log seats), two tents facing the fire, an
	                                upturned canoe on its trestle; a picnic table and the souvenir
	                                stall on a plank patio; plank stairs zigzag up past a camp
	                                (tents, a smoking fire ring, a blanket) to a picnic lookout
	                                with a flag and a telescope off the axis
	  • the climb from the back of the plaza up the terraces to the viewpoint (Kit.stairs 1-stud
	    steps, or Kit.rampPath slabs and wedge ramps), lantern posts beside it; the viewpoint
	    stands on a solid plinth on the hilltop. District pieces stand only where the ground
	    under their whole footprint is flat.

	Local frame of a plaza: origin at its centre on the ground, +Z away from the lagoon (like a
	base slot's frame), so the entry road comes in from -Z.
]]

local U = require("./Util")
local Kit = require("./MapKit")
local Promenade = require("./Promenade")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Enum = U.Enum
local rgb = U.rgb
local C = Kit.C

local rad, max, min = math.rad, math.max, math.min

local Gateways = {}

local FLOOR = 0.35 -- plaza paving top above GroundTop
local PAVE = rgb(246, 214, 160) -- warm mid-tone paving ...
local PAVE2 = rgb(236, 196, 140) -- ... and its second tone
local CORAL = rgb(255, 128, 104) -- entry roads and stripes
local ROAD_TOP = 0.97 -- the entry road: a clear step (>= 0.15) over the promenade tiles

-- Per-gateway details (keyed by bridge angle).
local THEMES = {
	[180] = { kind = "market", stall = "РЫБА", goods = "fish" },
	[90] = { kind = "garden", stall = "ЦВЕТЫ", goods = "flowers" },
	[0] = { kind = "playground", stall = "МОРОЖЕНОЕ", goods = "icecream" },
	[270] = { kind = "picnic", stall = "СУВЕНИРЫ", goods = "souvenirs" },
}

--------------------------------------------------------------------------------------------
-- Shared pieces (each builds in its own local frame: y = 0 on the paving, front = -Z)
--------------------------------------------------------------------------------------------

-- A voxel "circle" of radius r from overlapping rectangles (4 for big ones, 3 for small).
local function disc(b: any, name: string, x: number, z: number, r: number, y0: number, y1: number, color: any)
	local rects = if r > 30
		then { { 1, 0.35 }, { 0.35, 1 }, { 0.85, 0.6 }, { 0.6, 0.85 } }
		else { { 1, 0.4 }, { 0.4, 1 }, { 0.77, 0.77 } }
	for i, q in rects do
		b:box(`{name}{i}`, x - r * q[1], y0, z - r * q[2], x + r * q[1], y1, z + r * q[2], color, Kit.NOSHADOW)
	end
end

--[[
	The welcome arches: every gateway has its own silhouette, not just its own colour (local frame
	of the arch: y = 0 on the paving, front = -Z towards the bridge, the road between x = ±9; the
	pillars stand at |x| 12..16). Each builds its name board; 17-19 parts.
	  playground  a rainbow arch: pillars of stacked rainbow cubes, a stepped rainbow over the
	              board, a pinwheel on top that spins (attribute Spin)
	  garden      a flower arch: green hedge pillars in white planters with blooms stuck on them,
	              a giant tulip on each, a leafy beam with flowers over the board
	  market      a harbour arch: two wooden masts on crates, a yard across them, the board hanging
	              from it on ropes, an anchor hanging under it, a lifebuoy on a mast, a golden fish
	              on the yard
	  picnic      a camp arch: log pillars on stones with a carved totem head on each (beak and
	              eyes), a log lintel over the board, a little pine on top
]]
local function pillarSpan(sx: number): (number, number, number)
	local x0, x1 = sx * 12, sx * 16
	return min(x0, x1), max(x0, x1), (x0 + x1) / 2
end

local function nameBoard(b: any, text: string, x: number, y0: number, y1: number, d: number, color: any)
	local board = b:box("Board", -x, y0, -d, x, y1, d, color)
	Kit.sign(board, Enum.NormalId.Front, text, C.White, C.Navy, { pps = 24 })
	Kit.sign(board, Enum.NormalId.Back, text, C.White, C.Navy, { pps = 24 })
	return board
end

local ARCHES = {}

ARCHES.playground = function(b: any, text: string, color: any)
	local bands = { C.Red, C.Orange, C.Yellow, C.Lime, C.Cyan, C.Blue }
	for i, sx in { -1, 1 } do
		local lo, hi = pillarSpan(sx)
		b:box(`Plinth{i}`, lo - 0.8, -0.5, -2.8, hi + 0.8, 1.6, 2.8, C.White)
		-- three 6-stud cubes, every other one 0.3 proud (chunky stacked blocks), rainbow order
		for k = 1, 3 do
			local o = (k % 2) * 0.3
			local c = bands[(k - 1) * 2 + i]
			b:box(`Block{i}_{k}`, lo - o, 1.6 + (k - 1) * 6, -2 - o, hi + o, 1.6 + k * 6, 2 + o, c)
		end
	end
	nameBoard(b, text, 14.5, 13.6, 19.6, 1.2, color)
	-- the rainbow over the board: three bands, each a step narrower and thinner
	for k, c in { C.Red, C.Yellow, C.Cyan } do
		local w, d = 16.6 - (k - 1) * 2.4, 2.2 - (k - 1) * 0.2
		b:box(`Rainbow{k}`, -w, 19.6 + (k - 1) * 1.6, -d, w, 19.6 + k * 1.6, d, c)
	end
	b:box("Stick", -0.3, 24.4, -0.3, 0.3, 29.4, 0.3, C.White, Kit.NOSHADOW)
	-- the pinwheel: four blades round a hub, each offset along its arm (the swirl); it spins about
	-- its hub (the pivot's LookVector points down the road), no collisions
	local hubCF = b.cf * CFrame.new(0, 29.4, -0.95)
	local pw = Kit.builder(b.model, "Pinwheel", hubCF)
	pw.model:SetAttribute("Spin", 80)
	local hub = pw:box("Hub", -0.8, -0.8, -0.65, 0.8, 0.8, 0.65, C.White, Kit.DECOR)
	for k, c in { C.Red, C.Yellow, C.Lime, C.Blue } do
		local lcf = CFrame.Angles(0, 0, rad(k * 90)) * CFrame.new(2.6, 1.05, -0.1)
		pw:block(`Blade{k}`, Vector3.new(4.4, 2.1, 0.4), lcf, c, Kit.DECOR)
	end
	pw.model.PrimaryPart = hub
	hub.PivotOffset = hub.CFrame:Inverse() * hubCF
end

ARCHES.garden = function(b: any, text: string, color: any)
	local tips = Kit.lerpColor(color, C.White, 0.35)
	for i, sx in { -1, 1 } do
		local lo, hi, xm = pillarSpan(sx)
		b:box(`Planter{i}`, lo - 1, -0.5, -3, hi + 1, 2.4, 3, C.White)
		b:box(`Hedge{i}`, lo, 2.4, -2, hi, 18, 2, C.Leaf2)
		-- a bloom stuck through the hedge (shows on both faces)
		local y = if i == 1 then 7 else 10
		b:box(
			`Bloom{i}`,
			lo - 0.4,
			y,
			-2.4,
			lo + 2.2,
			y + 2.4,
			2.4,
			if i == 1 then C.Yellow else C.Blossom1,
			Kit.NOSHADOW
		)
		-- the giant tulip: a leafy collar, the cup, two petal tips with a notch between
		b:box(`Collar{i}`, xm - 1.6, 18, -1.6, xm + 1.6, 19.4, 1.6, C.Leaf1, Kit.NOSHADOW)
		b:box(`Cup{i}`, xm - 2.4, 19.4, -2.4, xm + 2.4, 23.8, 2.4, color)
		b:box(`TipL{i}`, xm - 2.4, 23.8, -1.8, xm - 0.8, 25.6, 1.8, tips, Kit.NOSHADOW)
		b:box(`TipR{i}`, xm + 0.8, 23.8, -1.8, xm + 2.4, 25.6, 1.8, tips, Kit.NOSHADOW)
	end
	b:box("Beam", -14, 16, -1.6, 14, 18.4, 1.6, C.Leaf1)
	nameBoard(b, text, 13.5, 10.4, 16, 1.1, color)
	for k, p in { { -7, C.Yellow }, { 0.5, C.Red }, { 7.5, C.Purple } } do
		b:box(`BeamBloom{k}`, p[1] - 1.3, 18.2, -1.3, p[1] + 1.3, 20.4, 1.3, p[2], Kit.NOSHADOW)
	end
end

ARCHES.market = function(b: any, text: string, color: any)
	for i, sx in { -1, 1 } do
		local _, _, xm = pillarSpan(sx)
		b:box(`Crate{i}`, xm - 2.8, -0.5, -2.8, xm + 2.8, 3.4, 2.8, C.WoodLight)
		b:pole(`Mast{i}`, 2.2, xm, 0, 3.4, 27, C.Wood)
	end
	b:box("Yard", -18, 22.6, -0.9, 18, 24, 0.9, C.WoodDark)
	for k, x in { -9, 9 } do
		b:box(`Rope{k}`, x - 0.2, 20.2, -0.2, x + 0.2, 22.6, 0.2, C.Rope, Kit.DECOR)
	end
	nameBoard(b, text, 11, 14.2, 20.2, 1, color)
	-- the anchor hanging under the board: shank, stock, crown, two flukes
	local navy = C.Navy
	b:box("Shank", -0.45, 7.6, -0.45, 0.45, 14.2, 0.45, navy)
	b:box("Stock", -2.2, 12.2, -0.4, 2.2, 13, 0.4, navy, Kit.NOSHADOW)
	b:box("Crown", -3.2, 7.6, -0.4, 3.2, 8.4, 0.4, navy, Kit.NOSHADOW)
	b:box("FlukeL", -3.2, 8.4, -0.4, -2.4, 10.2, 0.4, navy, Kit.NOSHADOW)
	b:box("FlukeR", 2.4, 8.4, -0.4, 3.2, 10.2, 0.4, navy, Kit.NOSHADOW)
	-- a lifebuoy on the left mast (red and white quarters round the mast's front)
	local _, _, lx = pillarSpan(-1)
	for k, q in
		{
			{ -1.9, 10.4, 1.9, 11.4, C.Red },
			{ -1.9, 6.6, 1.9, 7.6, C.Red },
			{ -1.9, 7.6, -0.9, 10.4, C.White },
			{ 0.9, 7.6, 1.9, 10.4, C.White },
		}
	do
		b:box(`Buoy{k}`, lx + q[1], q[2], -1.7, lx + q[3], q[4], -1.1, q[5], Kit.NOSHADOW)
	end
	-- a golden fish on the yard
	b:box("Fish", -2.4, 24, -0.5, 1.6, 26.8, 0.5, C.Gold, Kit.NEON_DECOR)
	b:box("Tail", 1.5, 24.2, -0.4, 3.1, 27.2, 0.4, C.Gold, Kit.NEON_DECOR)
	b:box("Eye", -1.9, 25.6, -0.6, -1.3, 26.2, 0.6, C.Navy, Kit.DECOR)
end

ARCHES.picnic = function(b: any, text: string, color: any)
	for i, sx in { -1, 1 } do
		local lo, hi, xm = pillarSpan(sx)
		b:box(`Stone{i}`, lo - 0.8, -0.5, -2.8, hi + 0.8, 1.4, 2.8, C.StoneLight)
		b:box(`Log{i}`, lo, 1.4, -2, hi, 17, 2, C.Bark)
		b:box(`Ring{i}`, lo - 0.25, 6.6, -2.25, hi + 0.25, 7.8, 2.25, C.WoodDark, Kit.NOSHADOW)
		-- the totem head: a carved block, a yellow beak, two white eyes
		b:box(`Head{i}`, lo - 0.3, 17, -2.3, hi + 0.3, 21.8, 2.3, if i == 1 then color else C.Autumn1)
		b:box(`Beak{i}`, xm - 0.8, 17.8, -3.5, xm + 0.8, 19.4, -2.3, C.Yellow, Kit.DECOR)
		for k, ex in { -1.1, 1.1 } do
			b:box(`Eye{i}_{k}`, xm + ex - 0.55, 19.8, -2.45, xm + ex + 0.55, 20.9, -2.3, C.White, Kit.DECOR)
		end
	end
	b:box("Lintel", -16.6, 14.2, -1.7, 16.6, 16.6, 1.7, C.Wood)
	nameBoard(b, text, 13.6, 9.2, 14.2, 1.1, color)
	b:box("Pine", -2.4, 16.6, -1, 2.4, 18.2, 1, C.Pine2, Kit.NOSHADOW)
	b:box("Pine2", -1.5, 18.2, -0.8, 1.5, 19.8, 0.8, C.Pine3, Kit.NOSHADOW)
	b:box("Pine3", -0.6, 19.8, -0.6, 0.6, 21.2, 0.6, C.Gold, Kit.NEON_DECOR)
end

local function welcomeArch(parent: any, cf: any, text: string, color: any, kind: string)
	local b = Kit.builder(parent, "WelcomeArch", cf)
	ARCHES[kind](b, text, color)
	return b:finish()
end

-- Striped market stall with a name sign and goods on the counter (front = -Z). 15-18 parts.
local function stall(parent: any, cf: any, text: string, color: any, goods: string)
	local b = Kit.builder(parent, "Stall", cf)
	local counter = b:box("Counter", -5, 0, -3, 5, 3.2, -0.8, C.Wood)
	b:box("CounterTop", -5.4, 3.2, -3.4, 5.4, 3.7, -0.4, C.WoodLight)
	for i, x in { -4.6, 4.6 } do
		b:box(`PostFront{i}`, x - 0.35, 3.7, -2.4, x + 0.35, 8.6, -1.7, C.WoodDark)
		b:box(`PostBack{i}`, x - 0.35, 0, 2.2, x + 0.35, 9.3, 2.9, C.WoodDark)
	end
	-- awning: 4 stripes stepping up towards the back, a valance at the front
	for k = 0, 3 do
		local x0 = -5.6 + k * 2.8
		local col = if k % 2 == 0 then color else C.White
		b:box(`Awning{k + 1}`, x0, 8.6 + k * 0.02, -4.4, x0 + 2.8, 9.4 + k * 0.02, 3.2, col)
	end
	b:box("Valance", -5.65, 7.8, -4.6, 5.65, 8.62, -4.2, color, Kit.NOSHADOW)
	local sign = b:box("Sign", -4.4, 9.4, -3.9, 4.4, 11.8, -3.2, C.Cream)
	Kit.sign(sign, Enum.NormalId.Front, text, rgb(96, 56, 30), nil, { pps = 30 })
	if goods == "fish" then
		for i, c in { C.Orange, C.Blue, C.Pink } do
			local x = -3.2 + (i - 1) * 2.9
			b:box(`Fish{i}`, x - 1.1, 3.7, -2.6, x + 1.1, 4.5, -1.6, c, Kit.DECOR)
			b:box(`Tail{i}`, x + 1.1, 3.75, -2.4, x + 1.6, 4.45, -1.8, Kit.shade(c, 0.85), Kit.DECOR)
		end
	elseif goods == "tackle" then
		for i, c in { C.Red, C.Yellow, C.Lime } do
			local x = -3 + (i - 1) * 3
			b:box(`Rod{i}`, x - 0.2, 3.7, -2.2, x + 0.2, 8.2, -1.8, c, Kit.DECOR)
			b:box(`Reel{i}`, x - 0.6, 4.6, -2.7, x + 0.6, 5.4, -2.2, C.White, Kit.DECOR)
		end
	elseif goods == "bait" then
		for i, c in { C.Pink, C.Lime, C.Orange } do
			local x = -3 + (i - 1) * 3
			b:box(`Jar{i}`, x - 0.8, 3.7, -2.6, x + 0.8, 5.3, -1.2, C.Glass, { Transparency = 0.3, CanCollide = false })
			b:box(`Lid{i}`, x - 0.9, 5.3, -2.7, x + 0.9, 5.8, -1.1, c, Kit.DECOR)
		end
	elseif goods == "icecream" then
		for i, c in { C.Pink, C.Cream, rgb(140, 90, 60) } do
			local x = -3 + (i - 1) * 3
			b:box(`Cone{i}`, x - 0.5, 3.7, -2.4, x + 0.5, 5.0, -1.4, C.Autumn2, Kit.DECOR)
			b:box(`Scoop{i}`, x - 0.8, 5.0, -2.7, x + 0.8, 6.4, -1.1, c, Kit.DECOR)
		end
	elseif goods == "flowers" then
		for i, c in { C.Red, C.Yellow, C.Purple } do
			local x = -3 + (i - 1) * 3
			b:box(`Pot{i}`, x - 0.7, 3.7, -2.5, x + 0.7, 4.9, -1.3, C.Autumn0, Kit.DECOR)
			b:box(`Bloom{i}`, x - 0.9, 4.9, -2.7, x + 0.9, 6.1, -1.1, c, Kit.DECOR)
		end
	else
		for i, c in { C.Cyan, C.Red, C.Yellow } do
			local x = -3 + (i - 1) * 3
			b:box(`Box{i}`, x - 0.8, 3.7, -2.6, x + 0.8, 5.1, -1.4, c, Kit.DECOR)
		end
	end
	return b:finish(counter)
end

-- Wooden notice board with coloured notes under a little roof (front = -Z). 9 parts.
local function noticeBoard(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "NoticeBoard", cf)
	local post = b:box("PostL", -4.2, -0.5, -0.5, -3.2, 8.2, 0.5, C.WoodDark)
	b:box("PostR", 3.2, -0.5, -0.5, 4.2, 8.2, 0.5, C.WoodDark)
	b:box("Frame", -3.4, 2.2, -0.3, 3.4, 7.8, 0.3, C.WoodDark)
	b:box("Board", -3, 2.6, -0.45, 3, 6.4, 0.2, C.WoodLight)
	local header = b:box("Header", -3, 6.5, -0.5, 3, 7.6, 0.2, C.Cream)
	Kit.sign(header, Enum.NormalId.Front, "ОБЪЯВЛЕНИЯ", rgb(96, 56, 30), nil, { pps = 40 })
	b:box("Roof", -4.8, 8.2, -1.4, 4.8, 9.0, 1.4, color)
	b:box("Roof2", -3.4, 9.0, -0.9, 3.4, 9.6, 0.9, Kit.lerpColor(color, C.White, 0.3))
	for i, n in { { -1.4, 4.9, C.Yellow }, { 1.4, 3.9, C.Pink } } do
		local front = -0.6 - (i % 3) * 0.1 -- overlapping notes never share a plane
		b:box(`Note{i}`, n[1] - 0.8, n[2] - 0.9, front, n[1] + 0.8, n[2] + 0.9, -0.42, n[3], Kit.DECOR)
	end
	return b:finish(post)
end

-- The viewpoint's solid plinth on the hilltop: a block from below the lowest ground under it up
-- to a hair above the highest. Returns its top y (local, relative to the frame).
local function plinth(b: any, world: any, origin: any, x0: number, z0: number, x1: number, z1: number, color: any)
	local hi, lo = -math.huge, math.huge
	for x = x0, x1, 2 do
		for z = z0, z1, 2 do
			local p = (origin * CFrame.new(x, 0, z)).Position
			local h = world:heightAt(p.X, p.Z)
			hi, lo = max(hi, h), min(lo, h)
		end
	end
	local base = origin.Position.Y
	local top = hi - base + 0.6
	-- (0.15 proud of the given edges: its sides never share a plane with a voxel cell's side)
	b:box("Plinth", x0 - 0.15, lo - base - 1.3, z0 - 0.15, x1 + 0.15, top, z1 + 0.15, color)
	return top
end

--------------------------------------------------------------------------------------------
-- Centrepieces
--------------------------------------------------------------------------------------------

local function fountain(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Fountain", cf)
	local water = { CanCollide = false, CastShadow = false } -- opaque: the two sheets cross
	local rim = b:box("Rim", -10.4, 0, -6.6, 10.4, 2.2, 6.6, C.White)
	b:box("RimB", -6.6, 0.02, -10.4, 6.6, 2.22, 10.4, C.White)
	b:box("Water", -9.2, 2.0, -5.4, 9.2, 2.5, 5.4, rgb(60, 200, 240), water)
	b:box("WaterB", -5.4, 2.02, -9.2, 5.4, 2.52, 9.2, rgb(60, 200, 240), water)
	for i, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local x, z = d[1] * 6.4, d[2] * 6.4
		b:box(`Jet{i}`, x - 0.5, 2.4, z - 0.5, x + 0.5, 7.2, z + 0.5, C.WaterLight, Kit.DECOR)
	end
	b:finish(rim)
	-- the golden fish on its pedestal rising out of the water (about 22 studs to the tail)
	Kit.prop("fishStatue", b.model, cf * CFrame.new(0, 2, 0), {
		color = C.Gold,
		belly = C.GoldLight,
		pedestal = color,
		trim = C.White,
		scale = 1.5,
		name = "GoldenFish",
	})
end

-- Giant flower on a round raised bed with a ring of blooms on stems (about 24 studs tall); the
-- petal disc has petals on both faces, so it reads from the hill path too.
local function giantFlower(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "GiantFlower", cf)
	local rim = b:box("Rim", -9.6, 0, -6, 9.6, 1.6, 6, C.White)
	b:box("RimB", -6, 0.02, -9.6, 6, 1.62, 9.6, C.White)
	b:box("Grass", -8.8, 1.2, -5.2, 8.8, 1.95, 5.2, C.GrassTop, Kit.NOSHADOW)
	b:box("GrassB", -5.2, 1.22, -8.8, 5.2, 1.97, 8.8, C.GrassTop, Kit.NOSHADOW)
	for k = 0, 5 do
		local a = k * math.pi / 3 + 0.5
		local x, z = math.sin(a) * 6.4, math.cos(a) * 6.4
		local top = 4.6 + (k % 2) * 1.2
		b:box(`Stem{k + 1}`, x - 0.3, 1.9, z - 0.3, x + 0.3, top - 1.6, z + 0.3, C.Leaf1, Kit.DECOR)
		b:box(`Bloom{k + 1}`, x - 1.1, top - 2, z - 1.1, x + 1.1, top, z + 1.1, C.Festive[(k * 3) % 8 + 1], Kit.DECOR)
	end
	b:box("Stem", -0.8, 1.9, -0.8, 0.8, 15, 0.8, C.Leaf1)
	b:box("LeafL", -4.6, 6, -0.5, -0.8, 7.2, 0.5, C.Leaf2, Kit.NOSHADOW)
	b:box("LeafR", 0.8, 9, -0.5, 4.4, 10.2, 0.5, C.Leaf2, Kit.NOSHADOW)
	b:box("Petals", -6, 14.4, -1.6, 6, 21, 1.6, color)
	b:box("PetalsB", -2.4, 11.8, -1.5, 2.4, 23.6, 1.5, color)
	local tips = Kit.lerpColor(color, C.White, 0.35)
	b:box("PetalTips", -4.2, 12.6, -1.75, 4.2, 22.8, 1.75, tips, Kit.NOSHADOW)
	b:box("Centre", -2.2, 15.6, -2.2, 2.2, 19.8, 2.2, C.Yellow, Kit.NOSHADOW)
	return b:finish(rim)
end

-- Playground tower: posts, a deck with a parapet, a stepped roof with a pennant, climbing
-- blocks at the back and a slide down the front (about 24 studs tall).
local function playTower(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "PlayTower", cf)
	local deckY = 8
	local first = nil
	for i, p in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local post = b:box(`Post{i}`, p[1] * 5 - 0.8, -0.3, p[2] * 5 - 0.8, p[1] * 5 + 0.8, 16, p[2] * 5 + 0.8, color)
		first = first or post
	end
	b:box("Deck", -5.6, deckY - 1, -5.6, 5.6, deckY, 5.6, C.Yellow)
	b:box("WallB", -4.2, deckY, 4.2, 4.2, deckY + 2.4, 5.0, C.Cyan)
	b:box("WallL", -5.0, deckY, -4.2, -4.2, deckY + 2.4, 4.2, C.Lime)
	b:box("WallR", 4.2, deckY, -4.2, 5.0, deckY + 2.4, 4.2, C.Lime)
	b:box("Roof1", -6.8, 16, -6.8, 6.8, 17.4, 6.8, C.Red)
	b:box("Roof2", -4.6, 17.4, -4.6, 4.6, 18.8, 4.6, C.White)
	b:box("Roof3", -2.4, 18.8, -2.4, 2.4, 20.2, 2.4, C.Red)
	b:box("Mast", -0.3, 20.2, -0.3, 0.3, 25, 0.3, C.White, Kit.NOSHADOW)
	b:box("Pennant", 0.3, 22.4, -0.15, 3.8, 24.8, 0.15, C.Yellow, Kit.DECOR)
	-- climbing blocks at the back (jump up: 2.7 studs each)
	for i = 1, 3 do
		local h = i * 2.7
		local z0 = 5.6 + (3 - i) * 2.6
		b:box(`Climb{i}`, -2.4, -0.3, z0, 2.4, h, z0 + 2.6, if i % 2 == 1 then C.Blue else C.Purple)
	end
	b:finish(first)
	-- the slide: a pink chute from the deck's front edge down to the paving, with side walls
	local top = (cf * CFrame.new(0, deckY, -5.6)).Position
	local foot = (cf * CFrame.new(0, 0.4, -19)).Position
	Kit.ramp(b.model, top, foot, { width = 4, thick = 0.8, color = C.Pink, name = "Slide" })
	for i, sx in { -1, 1 } do
		local off = (cf * CFrame.new(sx * 2.2, 1, 0)).Position - (cf * CFrame.new(0, 0, 0)).Position
		Kit.ramp(b.model, top + off, foot + off, {
			width = 0.6,
			thick = 1.6,
			color = C.Orange,
			name = `SlideWall{i}`,
			extra = Kit.NOSHADOW,
		})
	end
	return b.model
end

-- Swing set: two posts, a top bar, two seats on single ropes. 7 parts.
local function swings(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Swings", cf)
	local post = b:box("PostL", -6, -0.3, -0.6, -4.8, 9.6, 0.6, color)
	b:box("PostR", 4.8, -0.3, -0.6, 6, 9.6, 0.6, color)
	b:box("Bar", -6.4, 9.6, -0.7, 6.4, 10.6, 0.7, C.White)
	for i, x in { -2.2, 2.2 } do
		b:box(`Rope{i}`, x - 0.15, 3.4, -0.15, x + 0.15, 9.6, 0.15, C.Rope, Kit.DECOR)
		b:box(`Seat{i}`, x - 1.2, 2.8, -0.8, x + 1.2, 3.4, 0.8, if i == 1 then C.Red else C.Blue)
	end
	return b:finish(post)
end

-- Seesaw: a base, a tilted plank, two handles. 4 parts.
local function seesaw(parent: any, cf: any)
	local b = Kit.builder(parent, "Seesaw", cf)
	local base = b:box("Base", -1, -0.3, -1, 1, 1.8, 1, C.Yellow)
	local tilt = CFrame.new(0, 2.1, 0) * CFrame.Angles(0, 0, rad(12))
	b:block("Plank", Vector3.new(11, 0.6, 1.6), tilt, C.Red)
	b:block("HandleL", Vector3.new(0.4, 1.4, 1.4), tilt * CFrame.new(-4.2, 0.9, 0), C.Blue, Kit.NOSHADOW)
	b:block("HandleR", Vector3.new(0.4, 1.4, 1.4), tilt * CFrame.new(4.2, 0.9, 0), C.Blue, Kit.NOSHADOW)
	return b:finish(base)
end

-- Sandpit: a wooden frame round sand, a sand castle, a bucket and a spade. 7 parts.
local function sandpit(parent: any, cf: any)
	local b = Kit.builder(parent, "Sandpit", cf)
	local frame = b:box("Frame", -6.5, -0.3, -5, 6.5, 1.2, 5, C.WoodLight)
	b:box("Sand", -5.6, -0.2, -4.1, 5.6, 1.45, 4.1, C.Sand, Kit.NOSHADOW)
	b:box("Castle", -3.6, 1.45, -1.4, 0.4, 3.6, 1.6, C.SandDark)
	b:box("Tower", -2.6, 3.6, -0.6, -0.6, 5.2, 1, C.SandDark, Kit.NOSHADOW)
	b:box("Flag", -1.75, 5.2, 0.15, -1.45, 6.8, 0.25, C.Red, Kit.DECOR)
	b:box("Bucket", 2.2, 1.45, -2.6, 3.8, 3.2, -1, C.Red, Kit.NOSHADOW)
	b:box("Spade", 3, 1.45, 1.2, 4.6, 1.8, 2, C.Yellow, Kit.DECOR)
	return b:finish(frame)
end

-- Campfire circle: a carved totem (faces on the front and the back), the campfire in front of
-- it, a ring of four logs round the fire.
local function campCircle(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Camp", cf)
	local t = b:box("TotemBase", -2.2, -0.5, -2.2, 2.2, 4, 2.2, C.Wood)
	b:box("Totem2", -2, 4, -2, 2, 8, 2, color)
	b:box("Totem3", -2.2, 8, -2.2, 2.2, 12, 2.2, C.Autumn1)
	b:box("Wings", -5, 9.6, -1, 5, 10.8, 1, C.Red, Kit.NOSHADOW)
	for _, sz in { -1, 1 } do
		local f = sz * 2.1 -- the face plane, just outside the block
		b:box(`Beak{sz}`, -0.8, 9.2, min(f, f + sz * 1.1), 0.8, 10.4, max(f, f + sz * 1.1), C.Yellow, Kit.DECOR)
		for i, x in { -1, 1 } do
			b:box(
				`Eye{sz}_{i}`,
				x - 0.5,
				10.6,
				min(f + sz * 0.25, f),
				x + 0.5,
				11.6,
				max(f + sz * 0.25, f),
				C.White,
				Kit.DECOR
			)
			local g = sz * 2.0
			b:box(
				`Face{sz}_{i}`,
				x - 0.6,
				5.4,
				min(g, g + sz * 0.15),
				x + 0.6,
				6.6,
				max(g, g + sz * 0.15),
				C.Dark,
				Kit.DECOR
			)
		end
	end
	b:box("TotemTop", -1.4, 12, -1.4, 1.4, 13.4, 1.4, C.Gold)
	b:finish(t)
	local fire = Kit.prop("campfire", b.model, cf * CFrame.new(0, 0, -10), { light = true })
	local flame = fire:FindFirstChild("Flame")
	if flame then
		Kit.smoke(flame)
		Kit.sparkles(flame, C.Autumn2, { rate = 4, size = 0.4, lifetime = 1.4, speed = 5, drift = 2 })
	end
	for i, p in { { -6, -10, 90 }, { 6, -10, 90 }, { 0, -16, 0 }, { 0, -4.6, 0 } } do
		Kit.prop("log", b.model, cf * CFrame.new(p[1], 0, p[2]) * CFrame.Angles(0, rad(p[3]), 0), { seed = i })
	end
end

-- Flower arch: two leafy posts, a blossom beam and blooms on top. 6 parts. Spans 10 studs.
local function flowerArch(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "FlowerArch", cf)
	local post = b:box("PostL", -6.2, -0.3, -0.8, -4.6, 9, 0.8, C.Leaf1)
	b:box("PostR", 4.6, -0.3, -0.8, 6.2, 9, 0.8, C.Leaf1)
	b:box("Beam", -6.8, 9, -1.2, 6.8, 11, 1.2, C.Leaf2)
	b:box("Bloom1", -5.8, 10.6, -1.5, -2.8, 12.4, 1.5, color, Kit.NOSHADOW)
	b:box("Bloom2", -1.4, 10.8, -1.4, 1.4, 12.8, 1.4, C.Yellow, Kit.NOSHADOW)
	b:box("Bloom3", 2.8, 10.6, -1.5, 5.8, 12.4, 1.5, C.Blossom1, Kit.NOSHADOW)
	return b:finish(post)
end

-- Walk-in photo frame on a stage with chunky 2x2 posts, «ФОТО» on top (front = -Z). 8 parts.
local function photoFrame(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "PhotoSpot", cf)
	local stage = b:box("Stage", -7, -0.4, -3, 7, 0.7, 3, C.White)
	b:box("FrameL", -7, 0.7, -1, -5, 12, 1, color)
	b:box("FrameR", 5, 0.7, -1, 7, 12, 1, C.Purple)
	b:box("FrameTop", -7.4, 12, -1.2, 7.4, 13.6, 1.2, C.Yellow)
	local sign = b:box("Sign", -4.5, 13.6, -0.8, 4.5, 16.6, 0.8, C.Pink)
	Kit.sign(sign, Enum.NormalId.Front, "ФОТО", C.White, C.Navy, { pps = 30 })
	Kit.sign(sign, Enum.NormalId.Back, "ФОТО", C.White, C.Navy, { pps = 30 })
	b:box("Heart", 4.8, 14.4, -0.6, 6.8, 16.2, 0.6, C.Red, Kit.DECOR)
	b:box("Heart2", 5.3, 13.6, -0.55, 6.3, 14.5, 0.55, C.Red, Kit.DECOR)
	return b:finish(stage)
end

--------------------------------------------------------------------------------------------
-- Viewpoints on the hilltop (local frame of the plaza; `top` = the plinth top)
--------------------------------------------------------------------------------------------

-- Lookout rail along the back and both sides of the deck x0..x1 / z0..z1 (open at the front).
local function rails(b: any, x0: number, x1: number, z0: number, z1: number, y: number, color: any)
	b:box("RailBack", x0, y + 2.6, z1 - 0.8, x1, y + 3.4, z1, color, Kit.NOSHADOW)
	b:box("RailL", x0, y + 2.6, z0, x0 + 0.8, y + 3.4, z1, color, Kit.NOSHADOW)
	b:box("RailR", x1 - 0.8, y + 2.6, z0, x1, y + 3.4, z1, color, Kit.NOSHADOW)
	for i, x in { x0, x1 - 1 } do
		b:box(`RailPost{i}`, x - 0.1, y, z1 - 1.1, x + 1.1, y + 3.9, z1 + 0.1, C.White)
	end
end

local function telescope(b: any, x: number, y: number, z: number)
	b:box("ScopePost", x - 0.4, y, z - 0.4, x + 0.4, y + 3.4, z + 0.4, C.Navy)
	b:box("Scope", x - 1, y + 3.4, z - 1.8, x + 1, y + 4.7, z + 0.9, C.Yellow)
	b:box("ScopeLens", x - 0.65, y + 3.6, z - 2.1, x + 0.65, y + 4.5, z - 1.75, C.Cyan, Kit.DECOR)
end

--------------------------------------------------------------------------------------------
-- The hill districts: set-pieces on the terraces either side of each climb (local frame of the
-- plaza, standing on the voxel ground; each is placed only where its footprint is flat)
--------------------------------------------------------------------------------------------

-- Chunky lantern post (3 parts): a white post, a Neon cube, a cap in the theme colour.
local function lantern(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Lantern", cf)
	local post = b:box("Post", -0.6, -0.6, -0.6, 0.6, 6, 0.6, C.White)
	b:box("Lamp", -1.1, 6, -1.1, 1.1, 8.2, 1.1, C.Glow, Kit.NEON)
	b:box("Cap", -1.4, 8.2, -1.4, 1.4, 8.9, 1.4, color, Kit.NOSHADOW)
	return b:finish(post)
end

-- Crop bed w x d (4 parts): a soil bed with three chunky rows of one bright crop along X
-- (walk-through), the Grow-a-Garden look on a terrace.
local function cropBed(parent: any, cf: any, w: number, d: number, crop: any)
	local b = Kit.builder(parent, "CropBed", cf)
	local soil = b:box("Soil", -w / 2, -0.6, -d / 2, w / 2, 0.6, d / 2, rgb(170, 112, 66))
	for i = 1, 3 do
		local z = -d / 2 + (i - 0.5) * d / 3
		b:box(`Row{i}`, -w / 2 + 1, 0.6, z - 1.1, w / 2 - 1, 1.9, z + 1.1, crop, Kit.DECOR)
	end
	return b:finish(soil)
end

-- Red barn with white trim (6 parts), front = -Z.
local function barn(parent: any, cf: any)
	local b = Kit.builder(parent, "Barn", cf)
	local body = b:box("Body", -6, -0.6, -5, 6, 7, 5, C.Red)
	b:box("Eaves", -6.8, 7, -5.8, 6.8, 8.2, 5.8, C.White)
	b:box("Roof", -5.6, 8.2, -5.6, 5.6, 10.4, 5.6, rgb(214, 56, 56))
	b:box("Ridge", -3, 10.4, -5.4, 3, 12, 5.4, C.White)
	b:box("DoorFrame", -3, 0, -5.4, 3, 5.8, -4.9, C.White, Kit.NOSHADOW)
	b:box("Door", -2.3, 0.05, -5.6, 2.3, 5.1, -5.2, C.WoodDark, Kit.NOSHADOW)
	return b:finish(body)
end

-- Scarecrow (5 parts): post, shirt with arms, straw head, a wide hat.
local function scarecrow(parent: any, cf: any)
	local b = Kit.builder(parent, "Scarecrow", cf)
	local post = b:box("Post", -0.3, -0.5, -0.3, 0.3, 5, 0.3, C.WoodDark)
	b:box("Arms", -2.6, 3.6, -0.35, 2.6, 4.4, 0.35, C.Blue, Kit.NOSHADOW)
	b:box("Shirt", -0.9, 2.2, -0.6, 0.9, 4.6, 0.6, C.Red)
	b:box("Head", -0.8, 4.6, -0.8, 0.8, 6.2, 0.8, C.Autumn2, Kit.NOSHADOW)
	b:box("Hat", -1.4, 6.2, -1.4, 1.4, 6.9, 1.4, C.WoodLight, Kit.NOSHADOW)
	return b:finish(post)
end

-- Flower bed w x d (4 parts): two strips of blooms on green stems along X (rows of tulips).
local function tulipBed(parent: any, cf: any, w: number, d: number, c1: any, c2: any)
	local b = Kit.builder(parent, "TulipBed", cf)
	local first = nil
	for i, z in { -d / 4, d / 4 } do
		local stems = b:box(`Stems{i}`, -w / 2 + 0.4, -0.3, z - 1.6, w / 2 - 0.4, 1.2, z + 1.6, C.Leaf1, Kit.DECOR)
		first = first or stems
		b:box(`Blooms{i}`, -w / 2, 1.1, z - 1.9, w / 2, 2.7, z + 1.9, if i == 1 then c1 else c2, Kit.DECOR)
	end
	return b:finish(first)
end

-- Fish-drying rack (6 parts): two posts, a bar, three fish hanging from it.
local function dryingRack(parent: any, cf: any)
	local b = Kit.builder(parent, "DryingRack", cf)
	local post = b:box("PostL", -5, -0.5, -0.4, -4.2, 6.6, 0.4, C.WoodDark)
	b:box("PostR", 4.2, -0.5, -0.4, 5, 6.6, 0.4, C.WoodDark)
	b:box("Bar", -5.4, 6.6, -0.5, 5.4, 7.3, 0.5, C.Wood)
	for i, c in { C.Orange, C.Cyan, C.Pink } do
		local x = -2.6 + (i - 1) * 2.6
		b:box(`Fish{i}`, x - 0.6, 3.6 + (i % 2) * 0.5, -0.3, x + 0.6, 6.6, 0.3, c, Kit.DECOR)
	end
	return b:finish(post)
end

-- Fisher's hut (4 parts): a chunky white shed with a stepped roof in the theme colour and a door.
local function hut(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Hut", cf)
	local body = b:box("Body", -5.9, -0.6, -4.6, 5.9, 7.8, 4.6, C.White)
	b:box("Roof", -6.8, 7.8, -5.5, 6.8, 9.6, 5.5, color)
	b:box("Roof2", -4.4, 9.6, -3.9, 4.4, 11.2, 3.9, Kit.lerpColor(color, C.White, 0.35))
	b:box("Door", -1.7, 0.05, -4.95, 1.7, 6, -4.4, C.Navy, Kit.NOSHADOW)
	return b:finish(body)
end

-- Picnic blanket (2 parts) with a white stripe.
local function blanket(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Blanket", cf)
	local cloth = b:box("Cloth", -3.5, -0.2, -3, 3.5, 0.25, 3, color, Kit.NOSHADOW)
	b:box("Stripe", -3.6, -0.18, -0.7, 3.6, 0.4, 0.7, C.White, Kit.DECOR) -- 0.1 past the cloth's ends
	return b:finish(cloth)
end

-- Upturned rowboat on a trestle (3 parts), a crate stack beside it (2 parts).
local function boatYard(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "BoatYard", cf)
	local trestle = b:box("Trestle", -1.6, -0.5, -4, 1.6, 1.6, 4, C.WoodDark)
	b:box("Hull", -2.6, 1.6, -5.5, 2.6, 3.6, 5.5, color)
	b:box("Keel", -1, 3.6, -5.2, 1, 4.3, 5.2, C.White, Kit.NOSHADOW)
	b:box("Crate", 4, -0.5, -2.5, 7, 2.6, 0.5, C.WoodLight)
	b:box("Crate2", 4.4, 2.6, -2, 6.6, 4.4, 0.2, C.Red, Kit.NOSHADOW)
	return b:finish(trestle)
end

-- Big camping tent (5 parts), front = -Z (the door).
local function tent(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Tent", cf)
	local base = b:box("Floor", -4.8, -0.4, -5, 4.8, 0.3, 5, C.WoodDark)
	b:box("Low", -4.5, 0.3, -4.8, 4.5, 3.4, 4.8, color)
	b:box("Mid", -3.1, 3.4, -4.8, 3.1, 5.6, 4.8, Kit.lerpColor(color, C.White, 0.25))
	b:box("Top", -1.5, 5.6, -4.8, 1.5, 7.3, 4.8, color)
	b:box("Door", -1.7, 0.3, -4.95, 1.7, 4.2, -4.7, C.Dark, Kit.DECOR)
	return b:finish(base)
end

-- Fire ring (4 parts): a stone ring, two crossed logs, a Neon flame.
local function fireRing(parent: any, cf: any)
	local b = Kit.builder(parent, "FireRing", cf)
	local ring = b:box("Stones", -2.4, -0.4, -2.4, 2.4, 0.7, 2.4, C.StoneLight)
	b:box("LogA", -1.9, 0.7, -0.45, 1.9, 1.5, 0.45, C.Bark)
	b:box("LogB", -0.45, 1.5, -1.9, 0.45, 2.2, 1.9, C.Bark)
	local flame = b:box("Flame", -0.8, 1.4, -0.8, 0.8, 3.4, 0.8, C.Flame, Kit.NEON_DECOR)
	Kit.smoke(flame, { rate = 2 })
	return b:finish(ring)
end

--[[
	Per theme: the climb ("steps" stone stairs, "wood" plank stairs, "ramps" a paved path with
	wedge ramps, "switchback" plank stairs in three legs to a deck off the axis), the lantern
	spots beside it, and the district pieces { kind, x, z, w, d, yaw, ... } on the terraces either
	side (dropped where the ground under them is not flat).
]]
local DISTRICTS = {
	-- south: a little farm — long crop beds on the terraces, a red barn, a scarecrow
	playground = {
		climb = "steps",
		lanterns = { { -5.6, 66 }, { 5.6, 106 } },
		pieces = {
			{ "crop", -32, 52, 28, 12, 0, C.Lime },
			{ "crop", 32, 52, 28, 12, 0, C.Orange },
			{ "crop", -40, 68, 40, 12, 0, C.Red },
			{ "crop", 40, 68, 40, 12, 0, C.Yellow },
			{ "crop", 40, 84, 40, 12, 0, rgb(186, 110, 255) },
			{ "barn", -40, 100, 14, 12, -90 },
			{ "scarecrow", -30, 84, 5, 3, 60 },
		},
	},
	-- east: long flower terraces either side of a ramped garden path
	garden = {
		climb = "ramps",
		lanterns = { { 5.6, 58 }, { -5.6, 90 } },
		pieces = {
			{ "tulips", -32, 52, 28, 12, 0, C.Red, C.Yellow },
			{ "tulips", 32, 52, 28, 12, 0, C.Purple, C.Pink },
			{ "tulips", -40, 68, 40, 12, 0, C.Orange, C.Blossom1 },
			{ "tulips", 40, 68, 40, 12, 0, C.Yellow, C.Red },
			{ "tulips", -40, 84, 40, 12, 0, C.Blue, C.Pink },
		},
	},
	-- north: the fishermen's slope — fish-drying racks, upturned boats, fishers' huts
	market = {
		climb = "wood",
		lanterns = { { 5.6, 58 }, { -5.6, 88 } },
		pieces = {
			{ "clearing", -32, 52, 28, 13, 0, rgb(236, 214, 170) },
			{ "clearing", 32, 52, 28, 13, 0, rgb(236, 214, 170) },
			{ "rack", -30, 52, 12, 3, 0 },
			{ "rack", 30, 66, 12, 3, 0 },
			{ "boat", 32, 52, 15, 12, 90 },
			{ "boat", -36, 68, 15, 12, -70 },
			{ "hut", -40, 84, 14, 11, -90 },
			{ "hut", 40, 84, 14, 11, 90 },
		},
	},
	-- west: a camp — tents round a fire ring, blankets; the path zigzags up to a lookout off
	-- the axis
	picnic = {
		climb = "switchback",
		deckX = -24,
		turnZ = 80,
		lanterns = { { 5.6, 62 }, { -29.6, 104 } },
		pieces = {
			{ "clearing", 32, 52, 30, 13, 0, rgb(232, 200, 140) },
			{ "tent", 23, 52, 10, 10, -60, C.Orange },
			{ "tent", 42, 52, 10, 10, -110, C.Blue },
			{ "fire", 32.5, 52, 6, 6, 0 },
			{ "blanket", 44, 70, 8, 8, 20, C.Red },
			{ "tent", -24, 52, 10, 10, 70, C.Yellow },
			{ "tent", -42, 68, 10, 10, 100, rgb(186, 110, 255) },
		},
	},
}

local PIECES = {
	crop = function(parent: any, cf: any, q: any)
		cropBed(parent, cf, q[4], q[5], q[7])
	end,
	barn = function(parent: any, cf: any)
		barn(parent, cf)
	end,
	scarecrow = function(parent: any, cf: any)
		scarecrow(parent, cf)
	end,
	tulips = function(parent: any, cf: any, q: any)
		tulipBed(parent, cf, q[4], q[5], q[7], q[8])
	end,
	rack = function(parent: any, cf: any)
		dryingRack(parent, cf)
	end,
	boat = function(parent: any, cf: any, _q: any, color: any)
		boatYard(parent, cf, color)
	end,
	hut = function(parent: any, cf: any, _q: any, color: any)
		hut(parent, cf, color)
	end,
	tent = function(parent: any, cf: any, q: any)
		tent(parent, cf, q[7])
	end,
	fire = function(parent: any, cf: any)
		fireRing(parent, cf)
	end,
	blanket = function(parent: any, cf: any, q: any)
		blanket(parent, cf, q[7])
	end,
	-- a trodden sand clearing under a group of pieces (1 part)
	clearing = function(parent: any, cf: any, q: any)
		U.part(
			parent,
			"Clearing",
			Vector3.new(q[4], 0.75, q[5]),
			cf * CFrame.new(0, -0.225, 0),
			q[7],
			nil,
			Kit.NOSHADOW
		)
	end,
}

-- Builds the district of a theme on the hill behind its plaza (origin: the plaza frame on the
-- ground at GroundTop G). Each piece stands where the ground under its whole footprint is flat.
local function buildDistrict(parent: any, world: any, origin: any, G: number, d: any, color: any)
	local model = U.model(parent, "District")
	local function ground(x: number, z: number): number
		local p = (origin * CFrame.new(x, 0, z)).Position
		return world:heightAt(p.X, p.Z)
	end
	local function flat(x: number, z: number, w: number, dd: number): number?
		local h = nil
		for _, fx in { -0.5, -0.25, 0, 0.25, 0.5 } do
			for _, fz in { -0.5, -0.25, 0, 0.25, 0.5 } do
				local g = ground(x + fx * w, z + fz * dd)
				if h and g ~= h then
					return nil
				end
				h = g
			end
		end
		return h
	end
	for _, q in d.pieces do
		local x, z, yaw = q[2], q[3], q[6]
		-- the footprint: w x d, turned a quarter (or any other angle: its bounding square)
		local w, dd = q[4], q[5]
		if yaw % 180 == 90 then
			w, dd = dd, w
		elseif yaw % 180 ~= 0 then
			w = max(w, dd)
			dd = w
		end
		local h = flat(x, z, w, dd)
		if h then
			PIECES[q[1]](model, origin * CFrame.new(x, h - G, z) * CFrame.Angles(0, rad(yaw), 0), q, color)
			-- claims along the long side (Nature keeps its trees off the beds)
			local long, short = max(w, dd), min(w, dd)
			for t = -long / 2 + short / 2, long / 2 - short / 2 + 0.01, short do
				local lx, lz = if w >= dd then x + t else x, if w >= dd then z else z + t
				local p = (origin * CFrame.new(lx, 0, lz)).Position
				Kit.claim(p.X, p.Z, short * 0.72 + 2)
			end
		end
	end
	for _, l in d.lanterns do
		local h = flat(l[1], l[2], 2.6, 2.6)
		if h then
			lantern(model, origin * CFrame.new(l[1], h - G, l[2]), color)
		end
	end
	return model
end

--------------------------------------------------------------------------------------------
-- The plazas
--------------------------------------------------------------------------------------------

-- Each theme gets the plaza model, `at(x, z, yaw)` (local CFrame on the paving; yaw in degrees
-- or "centre"), the paving builder, the viewpoint builder and its hill info { world, origin,
-- deckZ0, color }; returns the viewpoint's plinth top (local y).

local function marketPlaza(model: any, at: any, paving: any, view: any, h: any): number
	local color = h.color
	-- a square market: light paving with a checker of darker tiles, a coral border
	paving:box("Square", -36, -0.6, -36, 36, FLOOR, 36, PAVE, Kit.NOSHADOW)
	paving:box("Border", -38, -0.7, -38, 38, FLOOR - 0.15, 38, CORAL, Kit.NOSHADOW)
	for i = 0, 3 do
		for j = 0, 3 do
			if (i + j) % 2 == 0 then
				local x0, z0 = -36 + i * 18, -36 + j * 18
				-- (the tiles on the square's rim stop 0.1 short of its sides)
				local ax, az = max(x0, -35.9), max(z0, -35.9)
				local bx, bz = min(x0 + 18, 35.9), min(z0 + 18, 35.9)
				paving:box(`Tile{i}_{j}`, ax, -0.5, az, bx, FLOOR + 0.12, bz, PAVE2, Kit.NOSHADOW)
			end
		end
	end
	-- the fountain off the axis (front right), two stalls facing the square
	fountain(model, at(13, -8), color)
	-- (every stall and board faces the square: front = -Z turned towards the centre)
	stall(model, at(-24, -10, -90), "РЫБА", color, "fish")
	stall(model, at(26, 18, 60), "СНАСТИ", C.Orange, "tackle")
	noticeBoard(model, at(-28, 8, -90), color)
	Kit.prop("barrel", model, at(-22, 24), { color = C.Blue })
	Kit.bench(model, at(14, 28, 180), { length = 7, color = C.Cream, legs = color })
	-- up the hill: a fenced deck beside the lighthouse (rails, bench, telescope)
	local z0 = h.deckZ0
	local top = plinth(view, h.world, h.origin, -17, z0, 17, z0 + 20, PAVE)
	Kit.prop("lighthouse", view.model, h.origin * CFrame.new(-9, top, z0 + 11), { stripe = C.Blue })
	local railC = C.Red
	view:box("RailFront", 4, top + 2.6, z0, 17, top + 3.4, z0 + 0.8, railC, Kit.NOSHADOW)
	view:box("RailR", 16.2, top + 2.6, z0, 17, top + 3.4, z0 + 20, railC, Kit.NOSHADOW)
	view:box("RailBack", -2, top + 2.6, z0 + 19.2, 17, top + 3.4, z0 + 20, railC, Kit.NOSHADOW)
	for i, p in { { 4, z0 }, { 16, z0 }, { 16, z0 + 19 } } do
		view:box(`RailPost{i}`, p[1] - 0.1, top, p[2] - 0.1, p[1] + 1.1, top + 3.9, p[2] + 1.1, C.White)
	end
	telescope(view, 13, top, z0 + 3.5)
	Kit.bench(view.model, h.origin * CFrame.new(7, top, z0 + 12), { length = 7 })
	return top
end

local function gardenPlaza(model: any, at: any, paving: any, view: any, h: any): number
	local color = h.color
	-- a round plaza with four hedge beds round a cross of paths (the paths in the second tone)
	disc(paving, "Pad", 0, 0, 40, -0.6, FLOOR, PAVE)
	paving:box("PathX", -38, -0.5, -4.5, 38, FLOOR + 0.12, 4.5, PAVE2, Kit.NOSHADOW)
	paving:box("PathZ", -4.5, -0.5, -38, 4.5, FLOOR + 0.12, 38, PAVE2, Kit.NOSHADOW)
	for i, p in { { -17, -17, 1 }, { 17, -17, 2 }, { -17, 17, 3 } } do
		Kit.flowerBed(model, at(p[1], p[2], if p[1] < 0 then 90 else -90), {
			width = 16,
			depth = 9,
			count = 2,
			height = 1.6,
			seed = i + 30,
			box = C.Leaf1,
			name = "HedgeBed",
		})
	end
	-- the giant flower stands in the fourth bed (back right, off the axis); a flower arch spans
	-- the axis, the stall and the photo frame on the cross paths
	giantFlower(model, at(17, 17), color)
	flowerArch(model, at(0, 30), color)
	stall(model, at(-27, 1, -90), "ЦВЕТЫ", color, "flowers")
	photoFrame(model, at(27, 1, -90), color)
	Kit.flowerMeadow(model, h.origin * CFrame.new(-31, 0, -27), 41)
	Kit.flowerMeadow(model, h.origin * CFrame.new(31, 0, -27), 42)
	Kit.bench(model, at(-9, -26, 0), { length = 7, color = C.White, legs = color })
	-- a gazebo on the hill
	local z0 = h.deckZ0
	local top = plinth(view, h.world, h.origin, -8, z0, 8, z0 + 16, C.White)
	local za, zb = z0 + 1.5, z0 + 14.5
	for i, p in { { -6, za }, { 6, za }, { 6, zb }, { -6, zb } } do
		view:box(`Post{i}`, p[1] - 0.7, top, p[2] - 0.7, p[1] + 0.7, top + 9, p[2] + 0.7, C.White)
	end
	local zc = (za + zb) / 2
	view:box("Roof1", -8.6, top + 9, zc - 8.6, 8.6, top + 10.4, zc + 8.6, color)
	view:box("Roof2", -6, top + 10.4, zc - 6, 6, top + 11.8, zc + 6, Kit.lerpColor(color, C.White, 0.45))
	view:box("Roof3", -3.4, top + 11.8, zc - 3.4, 3.4, top + 13.2, zc + 3.4, color)
	view:box("Finial", -1, top + 13.2, zc - 1, 1, top + 15, zc + 1, C.Gold, Kit.NEON_DECOR)
	Kit.bench(view.model, h.origin * CFrame.new(0, top, zb - 2), { length = 7, color = C.White, legs = color })
	return top
end

local function playgroundPlaza(model: any, at: any, paving: any, view: any, h: any): number
	local color = h.color
	-- a round plaza: a blue play mat on the left under the tower and the swings, a path in the
	-- second tone along the axis
	disc(paving, "Pad", 0, 0, 40, -0.6, FLOOR, PAVE)
	paving:box("Axis", -5, -0.5, -38, 5, FLOOR + 0.12, 38, PAVE2, Kit.NOSHADOW)
	paving:box("PlayMat", -33.8, -0.5, -18, -8, FLOOR + 0.26, 23.8, rgb(96, 190, 255), Kit.NOSHADOW)
	paving:box("PlayMatRim", -35, -0.55, -19, -7, FLOOR + 0.13, 25, C.White, Kit.NOSHADOW)
	playTower(model, at(-19, 10), color)
	swings(model, at(-21, -12, 0), C.Blue)
	sandpit(model, at(19, 10, -15))
	seesaw(model, at(24, -12, 60))
	stall(model, at(27, 26, 45), "МОРОЖЕНОЕ", color, "icecream")
	Kit.bench(model, at(14, -27, 180), { length = 7, color = C.Yellow, legs = color })
	Kit.flowerMeadow(model, h.origin * CFrame.new(-29, 0, 30), 51)
	-- a lookout deck on the hill and a long slide back down beside the stairs
	local z0 = h.deckZ0
	local top = plinth(view, h.world, h.origin, -8, z0, 15, z0 + 12, Kit.lerpColor(color, C.White, 0.3))
	rails(view, -8, 15, z0, z0 + 12, top, color)
	Kit.prop("flagPole", view.model, h.origin * CFrame.new(-5.5, top, z0 + 9), { height = 14, color = C.Yellow })
	local origin, world = h.origin, h.world
	local sx = 11
	local foot = (origin * CFrame.new(sx, 0.6, 46)).Position
	local baseY = origin.Position.Y
	local startY = baseY + top + 1.4 -- world y of the chute's top
	local sideV = (origin * CFrame.new(1, 0, 0)).Position - origin.Position
	-- lift the chute so it clears every terrace edge under it
	local p0 = (origin * CFrame.new(sx, 0, z0 + 1)).Position
	for k = 1, 40 do
		local t = k / 40
		local q = foot:Lerp(p0, t)
		for _, dx in { -2.4, 0, 2.4 } do
			local g = world:heightAt(q.X + sideV.X * dx, q.Z + sideV.Z * dx) + 0.6
			local yAt = foot.Y + (startY - foot.Y) * t
			if g > yAt then
				startY = max(startY, foot.Y + (g - foot.Y) / t)
			end
		end
	end
	local topPt = Vector3.new(p0.X, startY, p0.Z)
	Kit.ramp(view.model, topPt, foot, { width = 4.4, thick = 0.8, color = C.Yellow, name = "Slide" })
	for i, s in { -1, 1 } do
		local off = sideV * (s * 2.5) + Vector3.new(0, 1, 0)
		Kit.ramp(view.model, topPt + off, foot + off, {
			width = 0.6,
			thick = 1.8,
			color = C.Orange,
			name = `SlideWall{i}`,
			extra = Kit.NOSHADOW,
		})
	end
	-- (Nature keeps its flowers and trees out of the chute's corridor)
	for t = 0, 1, 0.2 do
		local q = foot:Lerp(topPt, t)
		Kit.claim(q.X, q.Z, 5)
	end
	-- the chute rests on a few posts where it runs high
	for i, t in { 0.3, 0.6, 0.85 } do
		local q = foot:Lerp(topPt, t)
		local g = world:heightAt(q.X, q.Z)
		if q.Y - 1 - g > 1.5 then
			U.part(
				view.model,
				`SlidePost{i}`,
				Vector3.new(1.2, q.Y - 1 - g + 1, 1.2),
				CFrame.new(q.X, (q.Y - 1 + g - 1) / 2, q.Z) * CFrame.Angles(0, rad(h.angle), 0),
				C.White
			)
		end
	end
	-- the top of the chute sits on the deck: a little start platform where it is higher
	if startY - baseY - top > 0.6 then
		view:box("SlideStart", sx - 2.4, top, z0, sx + 2.4, startY - baseY, z0 + 3, color)
	end
	return top
end

local function picnicPlaza(model: any, at: any, paving: any, view: any, h: any): number
	local color = h.color
	-- a meadow: a paved path along the axis and a round fire circle off it (left), the picnic
	-- tables on the grass
	paving:box("Path", -6, -0.6, -35.8, 6, FLOOR, 38, PAVE, Kit.NOSHADOW)
	paving:box("PathEdge", -7, -0.65, -36.3, 7, FLOOR - 0.15, 38.3, PAVE2, Kit.NOSHADOW)
	-- the camp: a big trodden sand clearing round the fire circle, two tents facing the fire, an
	-- upturned canoe on its trestle
	disc(paving, "Clearing", -17, 5, 22, -0.55, FLOOR + 0.12, rgb(240, 210, 150))
	disc(paving, "Hearth", -15, 4, 9.3, -0.5, FLOOR + 0.24, PAVE2)
	-- a plank patio under the picnic table and the stall (nothing stands on the bare grass)
	paving:box("Patio", 12, -0.6, -31, 33, FLOOR, 23, rgb(232, 186, 128), Kit.NOSHADOW)
	campCircle(model, at(-15, 14), color)
	tent(model, at(-31, 0, -90), C.Orange)
	tent(model, at(-24, 21, -30), C.Blue)
	boatYard(model, at(-27, -15, 0), C.Red)
	Kit.prop("picnicTable", model, at(21, 4, 70), { cloth = C.Red })
	stall(model, at(27, -24, 90), "СУВЕНИРЫ", color, "souvenirs")
	-- a picnic lookout on the hill (off the axis, where the zigzag path arrives): a striped pergola
	-- over a picnic table, a telescope, a flag
	local z0 = h.deckZ0
	local top = plinth(view, h.world, h.viewOrigin, -9, z0, 9, z0 + 14, rgb(214, 168, 118))
	rails(view, -9, 9, z0, z0 + 14, top, C.Red)
	telescope(view, -6, top, z0 + 3)
	local zc = z0 + 8
	for i, p in { { -5, -4 }, { 5, -4 }, { 5, 4 }, { -5, 4 } } do
		view:box(`PergolaPost{i}`, p[1] - 0.6, top, zc + p[2] - 0.6, p[1] + 0.6, top + 8.5, zc + p[2] + 0.6, C.White)
	end
	for k = 0, 3 do
		local x0 = -6.6 + k * 3.3
		view:box(
			`Canopy{k + 1}`,
			x0,
			top + 8.5,
			zc - 5.6,
			x0 + 3.3,
			top + 9.5,
			zc + 5.6,
			if k % 2 == 0 then color else C.White
		)
	end
	view:box("CanopyTop", -3.6, top + 9.5, zc - 3, 3.6, top + 10.6, zc + 3, color)
	Kit.prop("flagPole", view.model, h.viewOrigin * CFrame.new(6.5, top, z0 + 2.5), { height = 18, color = C.Yellow })
	Kit.prop("picnicTable", view.model, h.viewOrigin * CFrame.new(0, top, zc) * CFrame.Angles(0, rad(90), 0), {
		cloth = C.Red,
	})
	return top
end

local PLAZAS = {
	market = marketPlaza,
	garden = gardenPlaza,
	playground = playgroundPlaza,
	picnic = picnicPlaza,
}

--------------------------------------------------------------------------------------------

local function buildGateway(parent: any, cfg: any, world: any, gw: any)
	local angle = gw.angle % 360
	local theme = Promenade.Themes[angle] or Promenade.Themes[0]
	local details = THEMES[angle] or THEMES[0]
	local color = theme.color
	local G = cfg.GroundTop
	local model = U.model(parent, `Gateway_{gw.index}`)
	local origin = CFrame.new(gw.x, G, gw.z) * CFrame.Angles(0, rad(gw.angle), 0)
	-- local CFrame on the paving; yaw in degrees, or "centre" = front looks at the plaza centre
	local at = function(x: number, z: number, yaw: (number | string)?): any
		local y = if yaw == "centre" then math.atan2(x, z) else rad((yaw :: number?) or 0)
		return origin * CFrame.new(x, FLOOR, z) * CFrame.Angles(0, y, 0)
	end
	local light = Kit.lerpColor(color, C.White, 0.55)

	-- the coral entry road from the promenade (a clear step over its tiles) and the path stub
	-- towards the hill; the theme lays the rest of the paving
	local paving = Kit.builder(model, "Paving", origin)
	paving:box("Road", -9, -0.45, -42.6, 9, ROAD_TOP, -36.5, CORAL, Kit.NOSHADOW)
	paving:box("Back", -5.2, -0.45, 35.5, 5.2, FLOOR + 0.3, 43, CORAL, Kit.NOSHADOW)

	welcomeArch(model, at(0, -34), theme.gate, color, details.kind)

	-- the hill behind: find the hilltop along the deck's line (the axis, or off it where the
	-- path zigzags), a solid plinth for the viewpoint there
	local district = DISTRICTS[details.kind]
	local deckX = district.deckX or 0
	local function groundAt(x: number, z: number): number
		local p = (origin * CFrame.new(x, 0, z)).Position
		return world:heightAt(p.X, p.Z)
	end
	local topZ, topH = 120, -math.huge
	for z = 60, 200, 4 do
		local h = groundAt(deckX, z)
		if h > topH then
			topZ, topH = z, h
		end
	end
	local deckZ0 = topZ - 2 -- the plinth's front edge
	local viewOrigin = origin * CFrame.new(deckX, 0, 0)
	local view = Kit.builder(model, "Viewpoint", viewOrigin)
	local viewTop = PLAZAS[details.kind](model, at, paving, view, {
		world = world,
		origin = origin,
		viewOrigin = viewOrigin,
		deckZ0 = deckZ0,
		color = color,
		angle = gw.angle,
	})
	paving:finish()
	view:finish()

	-- the climb from the back of the plaza up to the viewpoint, different on every hill
	local function P(x: number, z: number): any
		local p = (origin * CFrame.new(x, 0, z)).Position
		return Vector3.new(p.X, 0, p.Z)
	end
	local top = G + viewTop - 0.15 -- the last step hidden in the plinth, a 0.15 step onto it
	local z1 = deckZ0 + 1.5
	local route = { { 0, 40.5 }, { 0, z1 } } -- for the claims
	if district.climb == "ramps" then
		-- a garden path: paved runs on the terraces, wedge ramps up every riser
		Kit.rampPath(model, world, P(0, 40.5), P(0, z1), {
			width = 7,
			color = PAVE,
			color2 = light,
			top = top,
			name = "HillPath",
		})
	elseif district.climb == "switchback" then
		-- plank stairs in three legs: up the valley, across onto the terrace, up to the deck
		local path = U.model(model, "HillPath")
		local tz = district.turnZ
		local opts = { width = 7, color = C.WoodLight, color2 = rgb(222, 166, 104), pave = true }
		opts.name = "Leg1"
		Kit.stairs(path, world, P(0, 40.5), P(0, tz + 3.5), opts)
		opts.name = "Leg2"
		Kit.stairs(path, world, P(-3.5, tz), P(deckX - 3.5, tz), opts)
		opts.name, opts.top = "Leg3", top
		Kit.stairs(path, world, P(deckX, tz + 3.5), P(deckX, z1), opts)
		route = { { 0, 40.5 }, { 0, tz }, { deckX, tz }, { deckX, z1 } }
	else
		local wood = district.climb == "wood"
		Kit.stairs(model, world, P(0, 40.5), P(0, z1), {
			width = 7,
			color = if wood then C.WoodLight else C.StoneLight,
			color2 = if wood then rgb(222, 166, 104) else C.White,
			pave = true,
			top = top,
			name = "HillPath",
		})
	end
	buildDistrict(model, world, origin, G, district, color)

	-- (the market's square paving reaches into the corners)
	Kit.claim(gw.x, gw.z, (gw.radius or 40) + (if details.kind == "market" then 15 else 4))
	for k = 1, #route - 1 do
		local a, b = route[k], route[k + 1]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		for t = 0, len, 12 do
			local f = t / len
			local x, z = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
			local p = (origin * CFrame.new(x, 0, z)).Position
			Kit.claim(p.X, p.Z, 7)
		end
	end
	local deck = (viewOrigin * CFrame.new(0, 0, deckZ0 + 8)).Position
	Kit.claim(deck.X, deck.Z, 18)
	return model
end

function Gateways.build(map: any, cfg: any, world: any)
	local root = U.model(map, "Gateways")
	for _, gw in world.gateways do
		buildGateway(root, cfg, world, gw)
	end
	return root
end

return Gateways
