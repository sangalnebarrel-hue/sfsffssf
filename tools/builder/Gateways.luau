--[[
	Gateways — the 4 themed plazas behind the bridge landings (world.gateways, r ≈ 372,
	radius 40, flat GroundTop), each with a way up the hill behind it to a viewpoint, so the
	strongest sightline of the map (bridge → welcome arch → plaza) leads somewhere.
	Each Map.Gateways.Gateway_N has:
	  • a big welcome arch over the coral entry road with a name board («СЕВЕРНЫЕ ВОРОТА» …) in
	    the gateway colour, lanterns on the cream pillars, a stepped roof with a theme topper
	    (star, flower, golden fish, pine);
	  • warm two-tone paving in its own footprint, and its own layout — the axis from the arch
	    to the hill path stays open, the centrepiece stands off it (decorated on every side):
	      north (180) fish market   a square market (checker paving): three stalls in a U
	                                (fish, tackle, bait), the golden fish fountain off the axis,
	                                crates and barrels, a notice board; up the hill a deck beside
	                                the lighthouse (rails, bench, telescope)
	      east  (90)  flower garden round plaza with four hedge beds round a cross of paths, the
	                                giant flower on its bed off the axis (petals both sides), a
	                                flower arch over the axis, a photo frame, the flower stall; a
	                                pink gazebo on the hill
	      south (0)   playground    round plaza with a blue play mat: play tower with a slide
	                                off the axis, a sandpit with a castle, swings, a seesaw, the
	                                ice cream stall; a lookout deck on the hill with a long slide
	                                down
	      west  (270) picnic camp   a meadow with a paved path and a round fire circle off the
	                                axis: totem (carved on the back too), campfire, log seats;
	                                picnic tables on the grass, the souvenir stall; a picnic
	                                lookout with a flag and a telescope on the hill
	  • a paved stair path (Kit.stairs, 1-stud steps) from the back of the plaza up the terraces
	    to the viewpoint, which stands on a solid plinth on the hilltop.

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
local ROAD_TOP = 0.79 -- the entry road: a clear step over the promenade tiles (GroundTop + 0.64)

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

-- The theme topper on the arch roof (local frame of the arch, standing on y).
local function topper(b: any, kind: string, y: number)
	if kind == "garden" then -- a flower: petal cross and a yellow heart
		b:box("Petals", -2.6, y + 1.2, -0.5, 2.6, y + 3.6, 0.5, C.Pink, Kit.NEON_DECOR)
		b:box("Petals2", -1.2, y, -0.45, 1.2, y + 4.8, 0.45, C.Pink, Kit.NEON_DECOR)
		b:box("Heart", -0.9, y + 1.5, -0.7, 0.9, y + 3.3, 0.7, C.Yellow, Kit.NEON_DECOR)
	elseif kind == "market" then -- a golden fish
		b:box("Fish", -2.4, y + 0.6, -0.5, 1.6, y + 3.4, 0.5, C.Gold, Kit.NEON_DECOR)
		b:box("Tail", 1.5, y + 0.2, -0.4, 3.1, y + 3.8, 0.4, C.Gold, Kit.NEON_DECOR)
		b:box("Eye", -1.9, y + 2.2, -0.6, -1.3, y + 2.8, 0.6, C.Navy, Kit.DECOR)
	elseif kind == "picnic" then -- a little pine
		b:box("Pine", -2.2, y, -0.6, 2.2, y + 1.6, 0.6, C.Lime, Kit.NEON_DECOR)
		b:box("Pine2", -1.4, y + 1.6, -0.55, 1.4, y + 3, 0.55, C.Lime, Kit.NEON_DECOR)
		b:box("Pine3", -0.6, y + 3, -0.5, 0.6, y + 4.4, 0.5, C.Gold, Kit.NEON_DECOR)
	else -- a star
		b:box("Star", -1.2, y, -0.5, 1.2, y + 3.2, 0.5, C.Gold, Kit.NEON_DECOR)
		b:box("StarX", -2.4, y + 1, -0.45, 2.4, y + 2.2, 0.45, C.Gold, Kit.NEON_DECOR)
	end
end

local function welcomeArch(parent: any, cf: any, text: string, color: any, kind: string)
	-- cream candy-striped pillars (bands in the gateway colour), lanterns on top, a big board
	-- in the gateway colour between Neon rims, a stepped roof with the theme topper
	local b = Kit.builder(parent, "WelcomeArch", cf)
	local dark = Kit.shade(color, 0.78)
	local light = Kit.lerpColor(color, C.White, 0.4)
	for _, sx in { -1, 1 } do
		local x0, x1 = sx * 12, sx * 16
		local lo, hi = math.min(x0, x1), math.max(x0, x1)
		local xm = (lo + hi) / 2
		b:box("Plinth", lo - 0.8, -0.5, -2.8, hi + 0.8, 2.4, 2.8, C.White)
		b:box("Pillar", lo, 2.4, -2, hi, 20, 2, C.Cream)
		for k, y in { 6.2, 13.2 } do
			b:box(`Band{k}`, lo - 0.25, y, -2.25, hi + 0.25, y + 2.2, 2.25, color, Kit.NOSHADOW)
		end
		b:box("Capital", lo - 0.7, 20, -2.7, hi + 0.7, 21.4, 2.7, color)
		local glow = b:box("Lantern", xm - 1.5, 21.4, -1.5, xm + 1.5, 24.4, 1.5, C.Glow, Kit.NEON)
		b:box("LanternCap", xm - 2.1, 24.4, -2.1, xm + 2.1, 25.3, 2.1, dark, Kit.NOSHADOW)
		if sx > 0 then
			Kit.light(glow, 16, 1.2)
		end
	end
	b:box("BoardFrame", -16.4, 13.4, -1.0, 16.4, 22.2, 1.0, C.White)
	local board = b:box("Board", -15.4, 14.2, -1.25, 15.4, 21.4, 1.25, color)
	Kit.sign(board, Enum.NormalId.Front, text, C.White, C.Navy, { pps = 24 })
	Kit.sign(board, Enum.NormalId.Back, text, C.White, C.Navy, { pps = 24 })
	b:box("RimBottom", -16.4, 12.8, -1.1, 16.4, 13.4, 1.1, C.Yellow, Kit.NEON)
	b:box("RimTop", -16.4, 22.2, -1.1, 16.4, 22.8, 1.1, C.Yellow, Kit.NEON)
	b:box("Roof1", -10, 22.8, -1.8, 10, 24.2, 1.8, light)
	b:box("Roof2", -5.5, 24.2, -1.4, 5.5, 25.4, 1.4, color)
	topper(b, kind, 25.4)
	return b:finish()
end

-- Striped market stall with a name sign and goods on the counter (front = -Z). 15-18 parts.
local function stall(parent: any, cf: any, text: string, color: any, goods: string)
	local b = Kit.builder(parent, "Stall", cf)
	local counter = b:box("Counter", -5, 0, -3, 5, 3.2, -0.8, C.Wood)
	b:box("CounterTop", -5.4, 3.2, -3.4, 5.4, 3.7, -0.4, C.WoodLight)
	b:box("CounterFront", -4.2, 0.8, -3.15, 4.2, 2.6, -3.0, color, Kit.NOSHADOW)
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

-- Wooden notice board with coloured notes under a little roof (front = -Z). 11 parts.
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
	for i, n in { { -1.8, 5.2, C.White }, { 0.4, 4.6, C.Yellow }, { 2.0, 5.4, C.Pink }, { -0.6, 3.4, C.Cyan } } do
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
	b:box("Plinth", x0, lo - base - 1.3, z0, x1, top, z1, color)
	return top
end

--------------------------------------------------------------------------------------------
-- Centrepieces
--------------------------------------------------------------------------------------------

local function fountain(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Fountain", cf)
	local water = { CanCollide = false, CastShadow = false, Transparency = 0.15 }
	local rim = b:box("Rim", -10.4, 0, -6.6, 10.4, 2.2, 6.6, C.White)
	b:box("RimB", -6.6, 0.02, -10.4, 6.6, 2.22, 10.4, C.White)
	b:box("Water", -9.2, 2.0, -5.4, 9.2, 2.5, 5.4, rgb(60, 200, 240), water)
	b:box("WaterB", -5.4, 2.02, -9.2, 5.4, 2.52, 9.2, rgb(60, 200, 240), water)
	for i, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local x, z = d[1] * 6.4, d[2] * 6.4
		b:box(`Jet{i}`, x - 0.5, 2.4, z - 0.5, x + 0.5, 7.2, z + 0.5, C.WaterLight, Kit.DECOR)
		b:box(`Splash{i}`, x - 1, 2.45, z - 1, x + 1, 3.1, z + 1, C.Foam, Kit.DECOR)
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
	Kit.prop("campfire", b.model, cf * CFrame.new(0, 0, -10), { light = true })
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
				paving:box(`Tile{i}_{j}`, x0, -0.5, z0, x0 + 18, FLOOR + 0.12, z0 + 18, PAVE2, Kit.NOSHADOW)
			end
		end
	end
	-- the fountain off the axis (front right), three stalls in a U round the square
	fountain(model, at(13, -8), color)
	stall(model, at(-24, -10, 90), "РЫБА", color, "fish")
	stall(model, at(-20, 22, 150), "НАЖИВКА", C.Lime, "bait")
	stall(model, at(26, 18, -120), "СНАСТИ", C.Orange, "tackle")
	noticeBoard(model, at(-28, 8, 90), color)
	Kit.prop("barrel", model, at(-30, -20), { color = C.Blue })
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
			count = 3,
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
	stall(model, at(-27, 1, 90), "ЦВЕТЫ", color, "flowers")
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
	paving:box("PlayMat", -34, -0.5, -18, -8, FLOOR + 0.14, 24, rgb(96, 190, 255), Kit.NOSHADOW)
	paving:box("PlayMatRim", -35, -0.55, -19, -7, FLOOR + 0.07, 25, C.White, Kit.NOSHADOW)
	playTower(model, at(-19, 10), color)
	swings(model, at(-21, -12, 0), C.Blue)
	sandpit(model, at(19, 10, -15))
	seesaw(model, at(24, -12, 60))
	stall(model, at(27, 26, -135), "МОРОЖЕНОЕ", color, "icecream")
	Kit.bench(model, at(14, -27, 0), { length = 7, color = C.Yellow, legs = color })
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
	paving:box("Path", -6, -0.6, -36, 6, FLOOR, 38, PAVE, Kit.NOSHADOW)
	paving:box("PathEdge", -7, -0.65, -36, 7, FLOOR - 0.15, 38, PAVE2, Kit.NOSHADOW)
	disc(paving, "Circle", -15, 4, 19, -0.55, FLOOR + 0.12, PAVE2)
	disc(paving, "Hearth", -15, 4, 9, -0.5, FLOOR + 0.24, PAVE)
	campCircle(model, at(-15, 14), color)
	Kit.prop("picnicTable", model, at(20, -8, 70), { cloth = C.Red })
	Kit.prop("picnicTable", model, at(22, 16, -70), { cloth = C.Yellow })
	stall(model, at(27, -24, -90), "СУВЕНИРЫ", color, "souvenirs")
	Kit.flowerMeadow(model, h.origin * CFrame.new(-31, 0, -22), 61)
	Kit.flowerMeadow(model, h.origin * CFrame.new(-27, 0, 30), 62)
	-- a picnic lookout on the hill: a striped pergola over a picnic table, a telescope, a flag
	local z0 = h.deckZ0
	local top = plinth(view, h.world, h.origin, -9, z0, 9, z0 + 14, rgb(214, 168, 118))
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
	Kit.prop("flagPole", view.model, h.origin * CFrame.new(6.5, top, z0 + 2.5), { height = 18, color = C.Yellow })
	Kit.prop("picnicTable", view.model, h.origin * CFrame.new(0, top, zc) * CFrame.Angles(0, rad(90), 0), {
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
	paving:box("Road", -9, -0.45, -43, 9, ROAD_TOP, -36.5, CORAL, Kit.NOSHADOW)
	paving:box("Back", -5, -0.45, 35.5, 5, FLOOR + 0.3, 43, CORAL, Kit.NOSHADOW)

	welcomeArch(model, at(0, -34), theme.gate, color, details.kind)

	-- the hill behind: find the hilltop along the axis, a solid plinth for the viewpoint there
	local function groundAt(z: number): number
		local p = (origin * CFrame.new(0, 0, z)).Position
		return world:heightAt(p.X, p.Z)
	end
	local topZ, topH = 120, -math.huge
	for z = 60, 200, 4 do
		local h = groundAt(z)
		if h > topH then
			topZ, topH = z, h
		end
	end
	local deckZ0 = topZ - 2 -- the plinth's front edge
	local view = Kit.builder(model, "Viewpoint", origin)
	local viewTop = PLAZAS[details.kind](model, at, paving, view, {
		world = world,
		origin = origin,
		deckZ0 = deckZ0,
		color = color,
		angle = gw.angle,
	})
	paving:finish()
	view:finish()

	-- the stair path from the back of the plaza up to the viewpoint
	local a = (origin * CFrame.new(0, 0, 40.5)).Position -- stations off the 8-stud cell grid
	local bTop = (origin * CFrame.new(0, 0, deckZ0 + 1.5)).Position
	Kit.stairs(model, world, Vector3.new(a.X, 0, a.Z), Vector3.new(bTop.X, 0, bTop.Z), {
		width = 7,
		color = light,
		color2 = PAVE,
		pave = true,
		top = G + viewTop - 0.15, -- hidden in the plinth, a 0.15 step onto it
		name = "HillPath",
	})

	-- (the market's square paving reaches into the corners)
	Kit.claim(gw.x, gw.z, (gw.radius or 40) + (if details.kind == "market" then 15 else 4))
	for z = 50, deckZ0 + 10, 16 do
		local p = (origin * CFrame.new(0, 0, z)).Position
		Kit.claim(p.X, p.Z, if z >= deckZ0 - 8 then 18 else 8)
	end
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
