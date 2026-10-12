--[[
	Promenade — the 4 bridges (hub plaza ↔ promenade) and the promenade ring along the lagoon
	(World v3, art direction v4: tools/builder/DESIGN.md §1/§2/§6; colours from Palette.luau).

	  Map.Bridges     Bridge_1..4 at θ = BridgeAngles: chunky wooden Props.bridge from the hub
	                  plaza (r ≈ 118) to the promenade (r ≈ 312), deck top GroundTop + 0.6, no end
	                  arches (the hub's avenue gates and the gateway arches frame the crossing):
	                  a deck of plank / light / mid wood boards, dark-wood posts, kerbs and mid
	                  rail, a chunky wooden top rail, stone pillars under the lanterns (the
	                  lantern caps are the gateway's colour: the district accent), a stone landing
	                  plate where the deck meets the promenade and a mid-span lookout: plank
	                  bump-outs on both sides on stone piers with stone corner posts, an iron lamp
	                  and a flag in the gateway's colour each, two-tone bunting across the deck
	                  between the flags; on the left (deeper) one a fish stall «ПРОДАТЬ РЫБУ»
	                  (SellKiosk.Scales.SellPromptAttachment, bound by the server like the hub
	                  market's) under a gabled roof, on the right a bench facing the water, a
	                  telescope and the district's touch (a crate of glass floats, a flower box,
	                  an anchor, a picnic basket). Pile bents buried in the sand are left out.
	                  buildBridges returns the kiosks' attachments for the build's self-check.
	  Map.Promenade   the ring walk r 312..330 on flat GroundTop: light sandstone flags with
	                  darker joints, a clay-brick runner down the middle and light stone kerbs
	                  (open where the gateway roads and landmark paths leave the ring); a
	                  sandstone sea wall on the lagoon side (two shades by turns, a pale coping)
	                  with a low parapet between pale stone pillars, open at the 8 pier entrances
	                  (base ± 6°, with two broad steps down to the beach on both sides of the
	                  pier) and 4 steps down to the beach (between two plots); dark iron lamps on
	                  every other pillar, two-tone bunting in the colour of each quarter, wooden
	                  benches and planters in front of the plots and along the stretches between
	                  them, wooden direction signs at the landmark paths, and a small stall on
	                  every stretch from a base's gate to its bridge (Stops: an ice-cream cart, a
	                  fish smokehouse, a lemonade stall, a fishing spot on the sea wall, a boat
	                  hire, a bait shed, an island map board, a flower cart) — real little
	                  buildings with plinths, framed walls, doors, windows, gabled roofs and
	                  signs; the base's own colour only on small accents (awning stripes,
	                  shutters, a valance). No people.

	Nothing is placed on the walking surface except along its two edges (the stops stand on
	its outer half: ~10 studs of lane stay free), so players can run all the way round.
	Returns { lamps = number }.
]]

local U = require("./Util")
local Kit = require("./MapKit")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local C = Kit.C
local lerp = Kit.lerpColor

local rad, cos, tan, floor, abs = math.rad, math.cos, math.tan, math.floor, math.abs

local Promenade = {}

-- Gateway themes by bridge angle (shared with Gateways.luau and the hub's avenues): names and the
-- district colour (a Palette accent: flags, lantern caps, awnings, signs — small parts only) and
-- the roof colour of its bridge's fish stall. `accent`: the lookout's district touch (wingAccent).
Promenade.Themes = {
	[0] = {
		gate = "ЮЖНЫЕ ВОРОТА",
		bridge = "ЮЖНЫЙ МОСТ",
		color = C.Orange,
		roof = C.RoofTerracotta,
		accent = "floats",
	},
	[90] = {
		gate = "ВОСТОЧНЫЕ ВОРОТА",
		bridge = "ВОСТОЧНЫЙ МОСТ",
		color = C.Pink,
		roof = C.RoofRed,
		accent = "flowers",
	},
	[180] = {
		gate = "СЕВЕРНЫЕ ВОРОТА",
		bridge = "СЕВЕРНЫЙ МОСТ",
		color = C.Blue,
		roof = C.RoofBlue,
		accent = "anchor",
	},
	[270] = {
		gate = "ЗАПАДНЫЕ ВОРОТА",
		bridge = "ЗАПАДНЫЙ МОСТ",
		color = C.BoatPaint[6], -- the Palette's calm green
		roof = C.RoofGreen,
		accent = "picnic",
	},
}

-- Materials of the walk (calm, large surfaces: DESIGN.md §1).
local WALK = lerp(C.StoneLight, C.Sand, 0.45) -- light sandstone flags
local JOINT = lerp(C.Cobble, C.SandDark, 0.3) -- the joints between them
local RUNNER = lerp(C.Brick, C.CobbleDark, 0.5) -- the clay-brick runner down the middle
local KERB = C.StoneLight
local WALL = { lerp(C.StoneLight, C.SandDark, 0.3), lerp(C.Stone, C.SandDark, 0.3) } -- sea wall blocks
local COPING = lerp(C.StoneLight, C.White, 0.35)
local PARAPET_TOP = 2.4 -- the parapet's top over the walk (its foot on the coping, 0.6)
local PILLAR_TOP = 3.6
local ICE = lerp(C.WaterLight, C.White, 0.65)
local SILVER = lerp(C.Iron, C.Glass, 0.55) -- fish on ice, fish on the line
local SALMON = lerp(C.Orange, C.Cream, 0.3)

-- Landmark path mouths on the promenade's land side: a wooden direction sign beside each path,
-- on the `side` (+1: towards larger angles) that stays clear (the waterfall's stepping stones
-- round the pond start on its + side); boards in calm painted colours.
local PATH_SIGNS = {
	{ angle = 45, text = "ВОДОПАД →", color = C.RoofBlue, side = -1 },
	{ angle = 135, text = "МЕЛЬНИЦА →", color = C.RoofRed },
	{ angle = 225, text = "БОЛЬШОЕ ДЕРЕВО →", color = C.RoofGreen },
	{ angle = 315, text = "ВЕРШИНА →", color = C.RoofSlate },
}

-- Flat pieces on the ground cast no shadows (cheaper on phones, nothing visible is lost).
local FLAT = { CastShadow = false }

local DECK_TOP = 0.64 -- above GroundTop: a hair above the bridge and pier decks (0.6)

-- Props.bunting hangs its flags in the rope's plane (0.2 thick flags on a 0.18 rope: faces 0.01
-- apart); each flag moves 0.06 off it, so no flag face shimmers against the rope's.
local function offsetFlags(model: any): any
	if model then
		for _, p in model:GetChildren() do
			if p:IsA("BasePart") and string.match(p.Name, "^Flag") then
				p.CFrame = p.CFrame * CFrame.new(0, 0, 0.06)
			end
		end
	end
	return model
end

-- Two-tone bunting: the district colour and the Palette's festive white.
local function twoTone(color: any): { any }
	return { color, C.Festive[3] }
end

--[[
	Wedge in a builder's local frame filling the box between two corners, its slope falling
	towards `down` ("-z" | "+z" | "-x" | "+x"): roof halves, canopies (DESIGN.md §1: chunky
	wedges for roofs).
]]
local function wedge(
	b: any,
	name: string,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	down: string,
	color: any,
	extra: { [string]: any }?
): any
	local dx, dy, dz = abs(x1 - x0), abs(y1 - y0), abs(z1 - z0)
	local centre = CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	local size, turn
	if down == "-z" then
		size, turn = Vector3.new(dx, dy, dz), CFrame.new()
	elseif down == "+z" then
		size, turn = Vector3.new(dx, dy, dz), CFrame.Angles(0, math.pi, 0)
	elseif down == "-x" then
		size, turn = Vector3.new(dz, dy, dx), CFrame.Angles(0, math.pi / 2, 0)
	else
		size, turn = Vector3.new(dz, dy, dx), CFrame.Angles(0, -math.pi / 2, 0)
	end
	local p = U.wedge(b.model, name, size, b.cf * centre * turn, color, nil, extra)
	p.Locked = true
	b.first = b.first or p
	return p
end

--[[
	Gabled roof (3 parts) over x0..x1 (ridge along X), eaves at y0 along z0 and z1, ridge at y1
	half-way: two wedge halves and a dark ridge beam on top.
]]
local function gable(b: any, x0: number, x1: number, z0: number, z1: number, y0: number, y1: number, color: any)
	local zm = (z0 + z1) / 2
	wedge(b, "RoofFront", x0, y0, z0, x1, y1, zm, "-z", color)
	wedge(b, "RoofBack", x0, y0, zm, x1, y1, z1, "+z", color)
	b:box("Ridge", x0 - 0.2, y1 - 0.25, zm - 0.45, x1 + 0.2, y1 + 0.35, zm + 0.45, C.WoodDark, Kit.NOSHADOW)
end

--------------------------------------------------------------------------------------------
-- Bridges
--------------------------------------------------------------------------------------------

-- Half length (studs, along the bridge) of the mid-span lookout and how far it sticks out (the
-- left wing, with the fish stall, sticks out further).
local LOOKOUT_HALF = 10
local LOOKOUT_OUT = 6.5
local KIOSK_OUT = 9

-- Path of the sell kiosk's scales under a bridge model, and its prompt attachment's offset in
-- the Scales part (like the hub's FishMarket.Scales: in front of the counter, over the deck).
local KIOSK_PROMPT_OFFSET = Vector3.new(0, -0.7, -2.3)

--[[
	Fish stall «ПРОДАТЬ РЫБУ» on a lookout wing (26 parts), standing on `cf` (y = 0 the wing's
	deck top, front -Z towards the bridge deck, local X along the bridge): a wooden counter with
	a sign panel in the district colour and an ice top with two fish, brass-and-iron scales (the
	Scales part with the SellPromptAttachment the server binds, like the hub market's), a plank
	back wall with a shelf of jars and a window, two dark front posts under a gabled roof (the bridge's roof
	colour) with a valance in the district colour along the eave, a «РЫБА» board on the ridge,
	a barrel and a crate of fish beside it. Everything stays within 4.2 studs in front of /
	3.6 behind cf (the roof's eaves 4.4) and ±8.4 along X.
	Returns the Scales part.
]]
local function sellKiosk(parent: any, cf: any, theme: any): any
	local b = Kit.builder(parent, "SellKiosk", cf)
	local color = theme.color
	-- counter: wooden body, a sign panel in the district colour, an ice top with two fish
	local counter = b:box("Counter", -5.5, -0.05, -2.8, 5.5, 3.2, -1.4, C.Wood)
	local panel = b:box("Panel", -5.0, 0.5, -2.95, 5.0, 2.7, -2.75, color, Kit.NOSHADOW)
	Kit.sign(panel, U.Enum.NormalId.Front, "ПРОДАТЬ РЫБУ", C.White, C.Navy, { pps = 24 })
	b:box("Ice", -5.8, 3.2, -3.1, 5.8, 3.7, -1.2, ICE)
	b:box("FishA", -4.7, 3.7, -2.55, -2.3, 4.3, -1.75, SILVER, Kit.DECOR)
	b:box("FishATail", -2.35, 3.75, -2.45, -1.75, 4.25, -1.85, C.Iron, Kit.DECOR)
	b:box("FishB", 2.3, 3.7, -2.65, 4.7, 4.3, -1.85, SALMON, Kit.DECOR)
	b:box("FishBTail", 1.75, 3.75, -2.55, 2.35, 4.25, -1.95, C.Orange, Kit.DECOR)
	-- the scales in the middle of the counter
	local scales = b:box("Scales", -1.1, 3.7, -2.6, 1.1, 4.5, -1.6, C.Iron)
	b:box("ScalesDial", -0.7, 4.5, -2.35, 0.7, 5.6, -1.85, C.Cream)
	b:box("ScalesPan", -1.4, 5.6, -2.75, 1.4, 5.85, -1.45, C.Gold, Kit.NOSHADOW)
	U.new("Attachment", { Name = "SellPromptAttachment", CFrame = CFrame.new(KIOSK_PROMPT_OFFSET) }, scales)
	-- the stall: a plank back wall with a shelf of jars, two dark posts in front
	b:box("BackWall", -6.4, -0.05, 2.4, 6.4, 7.7, 3.0, C.Plank)
	-- a window in the back wall (seen from the water): a cream frame round the glass
	b:box("WindowFrame", -1.7, 3.3, 3.0, 1.7, 6.1, 3.15, C.Cream, Kit.NOSHADOW)
	b:box("WindowGlass", -1.25, 3.75, 3.1, 1.25, 5.65, 3.25, C.WindowBlue, Kit.DECOR)
	b:box("Shelf", -5.2, 3.6, 1.7, 5.2, 4.0, 2.4, C.WoodDark, Kit.NOSHADOW)
	b:box("JarsA", -4.6, 4.0, 1.85, -1.8, 5.1, 2.35, lerp(C.Glass, C.Gold, 0.35), Kit.DECOR)
	b:box("JarsB", 1.4, 4.0, 1.85, 4.4, 4.9, 2.35, lerp(C.Glass, C.Leaf2, 0.35), Kit.DECOR)
	for i, x in { -6.4, 5.8 } do
		b:box(`Post{i}`, x, -0.05, -2.6, x + 0.6, 7.7, -2.0, C.WoodDark)
	end
	-- gabled roof over the stall (eaves at 7.7, ridge 10.3), a valance along the front eave
	gable(b, -7.2, 7.2, -4.4, 3.6, 7.7, 10.3, theme.roof or C.RoofRed)
	b:box("Valance", -7.0, 7.05, -4.25, 7.0, 7.7, -3.95, color, Kit.NOSHADOW)
	local board = b:box("Board", -3.4, 10.25, -0.65, 3.4, 12.6, -0.05, C.Cream)
	Kit.sign(board, U.Enum.NormalId.Front, "РЫБА", C.Navy, nil, { pps = 24 })
	Kit.sign(board, U.Enum.NormalId.Back, "РЫБА", C.Navy, nil, { pps = 24 })
	-- a barrel and a crate of fish beside the stall
	b:pole("Barrel", 1.8, -7.9, 0.6, -0.05, 2.6, C.Wood)
	b:box("Crate", 6.9, -0.05, -0.4, 8.4, 1.4, 1.4, C.WoodLight)
	b:box("CrateFish", 7.1, 1.35, -0.2, 8.2, 1.75, 1.2, SILVER, Kit.DECOR)
	b:finish(counter)
	return scales
end

--[[
	The right wing's touch in the theme of the gateway district behind the bridge, so the four
	crossings tell themselves apart (4-7 parts; lookout builder frame, the bench at x = bx, seat
	z -3..3, its back on the deck side, the outer rail at ox): a crate of glass fishing floats
	and a coil of rope (playground), a flower box on the outer rail and a planter by the bench
	(garden), an anchor leaning on the rail and a lifebuoy hung on it (fish market), a picnic
	basket on a checked cloth on the bench (picnic).
]]
local function wingAccent(b: any, theme: any, bx: number, ox: number)
	local kind = theme.accent
	local sx = if ox < 0 then -1 else 1
	if kind == "floats" then
		local x = ox - sx * 2.2
		b:box("FloatCrate", x - 1.1, -0.05, -6.8, x + 1.1, 1.6, -4.4, C.Wood)
		for i, p in { { -6.2, C.Glass }, { -4.9, lerp(C.Glass, C.Leaf2, 0.4) } } do
			b:box(`Float{i}`, x - 0.55, 1.55, p[1] - 0.55 + 0.1, x + 0.55, 2.6, p[1] + 0.55 + 0.1, p[2], Kit.DECOR)
		end
		b:box("RopeCoil", x - 0.9, -0.05, -8.3, x + 0.9, 0.7, -6.9, C.Rope, Kit.DECOR)
	elseif kind == "flowers" then
		-- a flower box along the top of the outer rail, a planter at the bench's end
		b:box("RailBox", ox - 0.65, 4.35, -6.5, ox + 0.65, 5.2, 4.5, C.Wood)
		b:box("RailGreens", ox - 0.45, 5.1, -6.2, ox + 0.45, 5.9, 4.2, C.Leaf2, Kit.DECOR)
		b:box("RailBloomsA", ox - 0.55, 5.6, -5.8, ox + 0.55, 6.6, -1.2, C.Flowers[2], Kit.DECOR)
		b:box("RailBloomsB", ox - 0.58, 5.7, -0.4, ox + 0.58, 6.5, 3.8, C.Flowers[4], Kit.DECOR)
		b:box("Planter", bx - 1.3, -0.05, -6.6, bx + 1.3, 1.5, -4.0, C.Wood)
		b:box("PlanterGreens", bx - 1.0, 1.4, -6.3, bx + 1.0, 2.6, -4.3, C.Leaf2, Kit.DECOR)
		b:box("PlanterBloom", bx - 0.7, 2.4, -5.9, bx + 0.6, 3.5, -4.7, C.Flowers[3], Kit.DECOR)
	elseif kind == "anchor" then
		-- an iron anchor leaning on the outer rail (shank, stock, arms, flukes, ring) and a lifebuoy
		local x, z = ox - 1.3, -5.2
		b:box("AnchorShank", x - 0.35, -0.05, z - 0.35, x + 0.35, 5.6, z + 0.35, C.Iron)
		b:box("AnchorStock", x - 0.25, 4.5, z - 1.7, x + 0.25, 5.0, z + 1.7, C.Iron, Kit.NOSHADOW)
		b:box("AnchorArms", x - 0.45, 0.4, z - 2.0, x + 0.45, 1.1, z + 2.0, C.Iron, Kit.NOSHADOW)
		b:box("AnchorFlukeA", x - 0.55, 1.0, z - 2.1, x + 0.55, 2.1, z - 1.3, C.Iron, Kit.NOSHADOW)
		b:box("AnchorFlukeB", x - 0.55, 1.0, z + 1.3, x + 0.55, 2.1, z + 2.1, C.Iron, Kit.NOSHADOW)
		b:box("AnchorRing", x - 0.2, 5.55, z - 0.6, x + 0.2, 6.6, z + 0.6, C.Gold, Kit.NOSHADOW)
		-- (the lifebuoy hangs on the hub-side end rail, facing along the wing)
		local endZ = -(LOOKOUT_HALF - 0.75) + 0.75 + 0.4
		Kit.prop("lifebuoy", b.model, b.cf * CFrame.new(ox - 3.4, 2.6, endZ), {})
	elseif kind == "picnic" then
		-- a red cloth with a cream check on the bench and a basket on it
		b:box("Cloth", bx - 0.95, 2.05, -2.9, bx + 1.05, 2.2, -0.2, C.Red, Kit.DECOR)
		b:box("ClothCheck", bx - 0.5, 2.1, -1.2, bx + 0.5, 2.3, -0.45, C.Cream, Kit.DECOR)
		b:box("Basket", bx - 0.7, 2.15, -2.6, bx + 0.6, 3.3, -1.5, C.Wood)
		b:box("BasketLid", bx - 0.8, 3.25, -2.7, bx + 0.7, 3.6, -1.4, C.WoodLight, Kit.NOSHADOW)
		b:box("BasketHandle", bx - 0.15, 3.55, -2.25, bx + 0.05, 4.4, -1.85, C.WoodDark, Kit.DECOR)
	end
end

-- Mid-span lookout of a bridge (Props.bridge local frame `cf`: y = 0 is the deck top, local -Z
-- runs from the hub to the promenade, ±hw are the deck edges): a plank bump-out on both sides
-- on a stone pier, a wooden railing on stone corner posts, an iron lamp and a flag in the
-- district colour on the outer corners; the left wing (deeper) carries the fish stall, the
-- right one a bench facing the water and a telescope. The bridge's own railing is cut open
-- there (see buildBridges). ~65 parts.
local function lookout(bridge: any, cf: any, hw: number, bedLocal: number, theme: any)
	local b = Kit.builder(bridge, "Lookout", cf)
	local zh = LOOKOUT_HALF
	local first
	local flagX = {}
	for i, sx in { -1, 1 } do
		local out = if i == 1 then KIOSK_OUT else LOOKOUT_OUT
		local x0, x1 = sx * (hw + 0.25), sx * (hw + out)
		local lo, hi = math.min(x0, x1), math.max(x0, x1)
		local deck = b:box(`Deck{i}`, lo, -1.2, -zh, hi, 0, zh, C.Plank)
		first = first or deck
		-- one stone pier under the bump-out
		local px0, px1 = sx * (hw + 1.4), sx * (hw + out - 1)
		b:box(`Pier{i}`, math.min(px0, px1), bedLocal, -3, math.max(px0, px1), -1.2, 3, C.Stone)
		-- railing: the outer rail and two end rails, on posts at the corners
		-- (rails 1.5 thick, inner posts 1.8: their faces stay clear of the lamp posts' 1.1)
		local ox = sx * (hw + out - 0.75)
		b:box(`Rail{i}`, ox - 0.75, 3.0, -zh + 0.75, ox + 0.75, 4.4, zh - 0.75, C.Wood, Kit.NOSHADOW)
		for j, sz in { -1, 1 } do
			local z = sz * (zh - 0.75)
			local ix = sx * (hw - 0.45)
			-- (the end rails' tops 0.1 under the side rails': no shared top face)
			b:box(
				`EndRail{i}_{j}`,
				math.min(ix, ox),
				3.0,
				z - 0.75,
				math.max(ix, ox),
				4.3,
				z + 0.75,
				C.Wood,
				Kit.NOSHADOW
			)
			b:box(`InnerPost{i}_{j}`, ix - 0.9, -0.05, z - 0.9, ix + 0.9, 4.8, z + 0.9, C.StoneLight)
		end
		-- an iron lamp on one outer corner, a flag in the district colour on the other
		local lampCf = cf * CFrame.new(ox, 0, -(zh - 0.75))
		Kit.lamp(b.model, lampCf, { height = 6.5, post = C.Iron, trim = C.Navy, light = i == 2 })
		b:pole(`FlagPole{i}`, 0.7, ox, zh - 0.75, -0.05, 13, C.Cream)
		local fx0, fx1 = ox + sx * 0.3, ox + sx * 5.3
		b:box(`Flag{i}`, math.min(fx0, fx1), 9.4, zh - 0.9, math.max(fx0, fx1), 12.6, zh - 0.6, theme.color, Kit.DECOR)
		flagX[i] = ox
		if i == 1 then
			-- the fish stall, its counter at the wing's inner edge facing the bridge deck
			local kx = sx * (hw + 3.2)
			sellKiosk(b.model, cf * CFrame.new(kx, 0, 0) * CFrame.Angles(0, math.rad(90 * sx), 0), theme)
		else
			-- a chunky wooden bench facing the water
			local bx = sx * (hw + 3.6)
			local backX0, backX1 = bx - sx * 1.5, bx - sx * 1.0
			b:box(`BenchBase{i}`, bx - 0.7, -0.05, -2.2, bx + 0.7, 1.5, 2.2, C.WoodDark)
			b:box(`BenchSeat{i}`, bx - 1.2, 1.5, -3, bx + 1.2, 2.1, 3, C.WoodLight)
			b:box(`BenchBack{i}`, math.min(backX0, backX1), 2.1, -3, math.max(backX0, backX1), 4.0, 3, C.Wood)
			wingAccent(b, theme, bx, ox)
		end
	end
	-- a brass telescope on the right-hand bump-out, looking out over the lagoon
	local tx = hw + LOOKOUT_OUT - 2.4
	b:box("ScopeStand", tx - 0.4, -0.05, 6.1, tx + 0.4, 3.6, 6.9, C.Iron)
	b:box("ScopeTube", tx - 1.2, 3.6, 5.95, tx + 1.9, 4.7, 7.05, C.Gold)
	b:box("ScopeLens", tx + 1.9, 3.45, 5.8, tx + 2.2, 4.85, 7.2, C.Glass, Kit.NOSHADOW)
	-- two-tone bunting across the deck between the two flag poles (well above the players' heads)
	local fz = zh - 0.75
	offsetFlags(
		Kit.prop(
			"bunting",
			b.model,
			(cf * CFrame.new(flagX[1], 12.2, fz)).Position,
			(cf * CFrame.new(flagX[2], 12.2, fz)).Position,
			{ seed = 3, count = 3, sag = 1.6, name = "Bunting", colors = twoTone(theme.color) }
		)
	)
	b:finish(first)
	return b.model
end

-- Returns the attachments it placed (the sell kiosks' prompts) for the build's self-check:
-- { { root = "workspace", path = {...}, offset = Vector3 }, ... }.
function Promenade.buildBridges(map: any, cfg: any, world: any): { any }
	local bridges = U.model(map, "Bridges")
	local top = cfg.GroundTop + DECK_TOP
	local attachments = {}
	for i, angle in cfg.BridgeAngles do
		local theme = Promenade.Themes[angle % 360] or Promenade.Themes[0]
		local from = U.polar(angle, cfg.HubPlazaRadius - 6, 0)
		-- the deck runs 0.4 stud under the promenade tiles (the landing plate covers the seam)
		local to = U.polar(angle, cfg.PromenadeRadius + 0.4, 0)
		local deckY = cfg.GroundTop + 0.6
		local width = cfg.BridgeWidth
		-- no end arches: the hub's avenue gates and the gateway arches frame every crossing
		-- (`roof` colours the lanterns' plates and caps: the district accent along the bridge)
		local bridge = Kit.prop("bridge", bridges, from, to, {
			deckY = deckY,
			width = width,
			bedY = -cfg.LagoonDepth,
			plankLength = 10,
			postSpacing = 16,
			bentSpacing = 48,
			roof = theme.color,
			gates = false,
			lights = false,
			seed = i * 31,
		})
		bridge.Name = `Bridge_{i}`
		-- the Props.bridge frame: y = 0 on the deck, local -Z from the hub to the promenade
		local a = Vector3.new(from.X, deckY, from.Z)
		local c = Vector3.new(to.X, deckY, to.Z)
		local cf = CFrame.lookAt((a + c) / 2, c)
		local hw = width / 2
		local L = (c - a).Magnitude
		local inv = cf:Inverse()
		local open = LOOKOUT_HALF - 0.75 -- rails end inside the lookout's inner corner posts
		for _, d in bridge:GetChildren() do
			if not d:IsA("BasePart") then
				continue
			end
			local name = d.Name
			local lp = (inv * d.CFrame).Position
			if string.match(name, "^Deck%d+$") then
				-- boards: plank and light wood by turns, every fourth one a mid wood
				local k = tonumber(string.sub(name, 5)) :: number
				d.Color = if k % 4 == 3 then C.Wood elseif k % 2 == 1 then C.WoodLight else C.Plank
				if k == 1 then
					-- the hub-end plank reaches 0.1 into the plaza, so its end face is not in the
					-- plane of the ground columns' edge there
					local dir = (c - a).Unit
					local sz = d.Size
					d.Size = if math.abs(d.CFrame.RightVector:Dot(dir)) > 0.9
						then Vector3.new(sz.X + 0.1, sz.Y, sz.Z)
						else Vector3.new(sz.X, sz.Y, sz.Z + 0.1)
					d.CFrame = d.CFrame - dir * 0.05
				end
			elseif string.match(name, "^TopRail") or string.match(name, "^MidRail") then
				-- split round the lookout; the top rail gets chunkier (1.2 x 1.4) in mid wood, the
				-- thin mid rail dark wood
				local isTop = string.match(name, "^TopRail") ~= nil
				local size = if isTop then Vector3.new(1.2, 1.4, 0) else Vector3.new(d.Size.X, d.Size.Y, 0)
				local y = if isTop then 3.7 else lp.Y
				for j, seg in { { open, L / 2 }, { -L / 2, -open } } do
					local len = seg[2] - seg[1]
					U.part(
						bridge,
						`{name}_{j}`,
						Vector3.new(size.X, size.Y, len),
						cf * CFrame.new(lp.X, y, (seg[1] + seg[2]) / 2),
						if isTop then C.Wood else C.WoodDark,
						nil,
						if isTop then nil else Kit.NOSHADOW
					)
				end
				d:Destroy()
			elseif math.abs(lp.Z) < LOOKOUT_HALF + 0.5 and math.abs(lp.X) > hw - 2 and lp.Y > -0.2 and d.Size.Z < 4 then
				-- posts and lanterns in the opening
				d:Destroy()
			elseif string.match(name, "^Pile") or string.match(name, "^Cap%d") then
				-- dark wood stays on the piles under the deck; the end bents stand in the sand
				-- (hub plaza / beach) and are never seen
				local p = d.CFrame.Position
				if world and world:heightAt(p.X, p.Z) >= p.Y + d.Size.Y / 2 - 0.25 then
					d:Destroy()
				elseif string.match(name, "^Cap") then
					d.Color = C.Wood
				end
			elseif string.match(name, "^LampPost") then
				-- stone pillars under the lanterns
				d.Color = C.StoneLight
			elseif string.match(name, "^Post") or string.match(name, "^Kerb") then
				d.Color = C.WoodDark
			elseif string.match(name, "^Stringer") then
				d.Color = C.Wood
			end
		end
		lookout(bridge, cf, hw, -cfg.LagoonDepth - deckY, theme)
		table.insert(attachments, {
			root = "workspace",
			path = { "Map", "Bridges", bridge.Name, "Lookout", "SellKiosk", "Scales", "SellPromptAttachment" },
			offset = KIOSK_PROMPT_OFFSET,
		})
		-- stone landing plate where the deck meets the promenade: it covers the deck end and the
		-- tile edge (their tops are only 0.04-0.16 apart) with one clear top 0.1 above the tiles
		local land = U.polar(angle, cfg.PromenadeRadius + 0.6, 0)
		U.part(
			bridge,
			"Landing",
			Vector3.new(width + 1.2, 0.7, 3.4),
			CFrame.new(land.X, top + 0.22 - 0.35, land.Z) * CFrame.Angles(0, math.rad(angle), 0),
			KERB,
			nil,
			FLAT
		)
	end
	return attachments
end

--------------------------------------------------------------------------------------------
-- Promenade ring
--------------------------------------------------------------------------------------------

-- Ring piece between angles a0..a1 (degrees) and radii r0..r1, top at y, as one block along
-- the chord (wide enough to cover the outer arc).
local function ringPiece(
	parent: any,
	name: string,
	a0: number,
	a1: number,
	r0: number,
	r1: number,
	y0: number,
	y1: number,
	color: any,
	extra: any?
): any
	local am = (a0 + a1) / 2
	local half = rad(a1 - a0) / 2
	local length = 2 * r1 * tan(half) + 0.1
	local rm = (r0 + r1) / 2 * cos(half) -- chord midpoint of the band
	local cf = U.polarCFrame(am, rm, (y0 + y1) / 2)
	return U.part(parent, name, Vector3.new(length, y1 - y0, r1 - r0), cf, color, nil, extra)
end

-- The sea wall: its lagoon face (r = WALL_IN) hides the beach/grass step under the promenade's
-- lagoon edge; open only where a pier or bridge deck meets the promenade (± DECK_HALF studs).
local WALL_IN = 308.2
local DECK_HALF = 10

-- Railing gaps: piers (base angle ± PIER_GAP: the pier deck plus a broad flight of sand steps
-- on each side), bridge landings (the deck only: the railing runs right up to the bridge) and
-- the sand steps down to the beach (± STEP_GAP at STEP_ANGLES, between two plots).
local PIER_GAP = 6
local BRIDGE_GAP = math.deg(math.asin(DECK_HALF / WALL_IN))
local STEP_GAP = 1.3
local STEP_ANGLES = { 45, 135, 225, 315 }

local function inGap(cfg: any, a: number): boolean
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		if Kit.angleDistance(a, base) < PIER_GAP then
			return true
		end
	end
	for _, b in cfg.BridgeAngles do
		if Kit.angleDistance(a, b) < BRIDGE_GAP then
			return true
		end
	end
	for _, s in STEP_ANGLES do
		if Kit.angleDistance(a, s) < STEP_GAP then
			return true
		end
	end
	return false
end

-- True where a pier or bridge deck crosses the sea wall line.
local function onDeck(cfg: any, a: number): boolean
	local half = math.deg(math.asin(DECK_HALF / WALL_IN))
	for i = 1, cfg.BaseCount do
		if Kit.angleDistance(a, cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount) < half then
			return true
		end
	end
	for _, b in cfg.BridgeAngles do
		if Kit.angleDistance(a, b) < half then
			return true
		end
	end
	return false
end

-- Continuous runs { a0, a1, class } of the ring (degrees, increasing) where class(a) is the
-- same; the scan starts on a pier (deck) so no run wraps around 360.
local function runs(cfg: any, class: (number) -> string): { { any } }
	local list = {}
	local step = 0.25
	local start, current = nil, nil
	local origin = cfg.BaseAngleOffset
	for k = 0, 360 / step do
		local a = origin + k * step
		local c = class(a)
		if c ~= current then
			if start then
				table.insert(list, { start, a - step, current })
			end
			start, current = a, c
		end
	end
	if start then
		table.insert(list, { start, origin + 360, current })
	end
	return list
end

-- Railing runs [a0, a1] outside the gaps.
local function railRuns(cfg: any): { { any } }
	local list = {}
	for _, run in
		runs(cfg, function(a)
			return if inGap(cfg, a) then "gap" else "rail"
		end)
	do
		if run[3] == "rail" then
			table.insert(list, run)
		end
	end
	return list
end

-- Splits [a0, a1] into pieces of at most `maxStep` degrees.
local function pieces(a0: number, a1: number, maxStep: number): { { number } }
	local n = math.max(1, math.ceil((a1 - a0) / maxStep - 1e-6))
	local list = {}
	for p = 0, n - 1 do
		table.insert(list, { a0 + (a1 - a0) * p / n, a0 + (a1 - a0) * (p + 1) / n })
	end
	return list
end

-- District colour of the promenade quarter around angle a: the theme of the nearest bridge /
-- gateway (only on the bunting: each quarter of the ring is recognisable by its flags).
local function quarterColor(a: number): any
	local best, color = math.huge, C.Navy
	for angle, theme in Promenade.Themes do
		local d = Kit.angleDistance(a, angle)
		if d < best then
			best, color = d, theme.color
		end
	end
	return color
end

-- Wooden planter (4 parts): a plank box (4.8 along the ring), a leafy mound and two blooms in
-- two colours poking out of it at different heights. Stands on cf (local X along the ring).
local function planter(parent: any, cf: any, c1: any, c2: any)
	local b = Kit.builder(parent, "Planter", cf)
	local box = b:box("Box", -2.4, -0.2, -1.4, 2.4, 1.2, 1.4, C.Wood)
	b:box("Greens", -2.05, 0.9, -1.05, 2.05, 2.2, 1.05, C.Leaf2, Kit.DECOR)
	b:box("Bloom1", -1.6, 2.0, -0.65, -0.5, 3.1, 0.45, c1, Kit.DECOR)
	b:box("Bloom2", 0.45, 2.05, -0.4, 1.55, 3.35, 0.7, c2, Kit.DECOR)
	return b:finish(box)
end

--------------------------------------------------------------------------------------------
-- Stops: one small stall on every stretch between a base's gate and its bridge
--------------------------------------------------------------------------------------------

-- Base colours (BaseConfig.Colors: base i gets colour i); a fallback when the module is missing.
local BASE_COLORS = (function(): { any }
	local ok, cfg = pcall(U.loadPure, "src/ReplicatedStorage/Shared/Config/BaseConfig.luau")
	local list = {}
	if ok and type(cfg) == "table" and type(cfg.Colors) == "table" then
		for _, entry in cfg.Colors do
			table.insert(list, entry.Color)
		end
	end
	if #list == 0 then
		list = { C.Red, C.Orange, C.Yellow, C.BoatPaint[6], C.Cyan, C.Blue, C.Purple, C.Pink }
	end
	return list
end)()

--[[
	The stops' frame: cf on the walk at r ≈ 326 (outer half of the walk), local -Z towards the
	lagoon (the front, where people walk past), local X along the ring. Solid parts stay centred
	at z >= -0.9 (the running lane keeps ~10 studs clear) and within z <= 4 (the walk's outer
	edge), x within ±6.5; awnings and eaves over the lane stay above head height (y >= 5.3).
	`color` is the base's colour: only on small accents (awning stripes, shutters, valances).
]]

-- Striped canvas awning (4 parts) on top of posts at y: canvas, two stripes in the accent and a
-- valance along its front edge (z0).
local function awning(b: any, x0: number, x1: number, z0: number, z1: number, y: number, color: any)
	b:box("Awning", x0, y, z0, x1, y + 0.5, z1, C.Canvas)
	local w = (x1 - x0) / 7
	for i, k in { 1.5, 4.5 } do
		local sx = x0 + k * w
		b:box(`AwningStripe{i}`, sx, y + 0.45, z0 + 0.1, sx + w, y + 0.7, z1 - 0.1, color, Kit.NOSHADOW)
	end
	b:box("Valance", x0 - 0.1, y - 0.55, z0 - 0.15, x1 + 0.1, y + 0.05, z0 + 0.15, color, Kit.DECOR)
end

-- Two cart wheels (2 parts) on the front face (z) at x = ±dx, axle height h.
local function wheels(b: any, dx: number, z: number, d: number)
	for i, x in { -dx, dx } do
		b:block(
			`Wheel{i}`,
			Vector3.new(0.5, d, d),
			CFrame.new(x, d / 2 - 0.05, z) * CFrame.Angles(0, math.rad(90), 0),
			C.WoodDark,
			{ Shape = U.Enum.PartType.Cylinder, CanCollide = false, CanQuery = false }
		)
	end
end

-- Ice-cream cart (18 parts): a cream cart tinted with the base colour, «МОРОЖЕНОЕ» on its
-- front, a lid with three tubs, two wheels and a handle, four slim poles under a striped
-- canvas canopy with a wafer cone on top.
local function iceCreamStop(b: any, color: any)
	local body = b:box("Cart", -2.8, 1.2, -0.8, 2.8, 3.6, 1.4, lerp(color, C.Cream, 0.8))
	Kit.sign(body, U.Enum.NormalId.Front, "МОРОЖЕНОЕ", C.Navy, nil, { pps = 24, height = 0.55 })
	b:box("Lid", -3.0, 3.6, -0.95, 3.0, 3.95, 1.55, C.White)
	for i, s in { { -2.1, C.Blossom1 }, { -0.5, C.Cream }, { 1.1, C.Mint3 } } do
		b:box(`Tub{i}`, s[1], 3.9, -0.6, s[1] + 1.0, 4.45, 0.3, s[2], Kit.DECOR)
	end
	wheels(b, 1.6, -1.05, 2.0)
	b:box("Handle", 2.8, 2.9, -0.2, 3.9, 3.2, 1.0, C.Iron, Kit.DECOR)
	for i, p in { { -2.75, -0.65 }, { 2.45, -0.65 }, { -2.75, 1.0 }, { 2.45, 1.0 } } do
		b:box(`Pole{i}`, p[1], 3.95, p[2], p[1] + 0.3, 8.2, p[2] + 0.3, C.Cream, Kit.NOSHADOW)
	end
	awning(b, -3.6, 3.6, -1.5, 2.2, 8.2, color)
	b:box("Cone", -0.45, 8.85, 0.0, 0.45, 9.9, 0.9, C.WoodLight, Kit.DECOR)
	b:box("Scoop", -0.8, 9.8, -0.35, 0.8, 11.0, 1.25, C.Blossom1, Kit.DECOR)
	return body
end

-- Fish smokehouse (15 parts): a dark-plank hut on a stone plinth with a light door, a gabled
-- brown roof and a brick chimney with a puff of smoke, a «КОПТИЛЬНЯ» board over the door and a
-- drying rack with three fish beside it.
local function smokehouseStop(b: any, color: any)
	-- (the plinth's top 0.1 over the walk's kerb under its back: no shared top face)
	local plinth = b:box("Plinth", -3.0, -0.05, -0.2, 3.0, 0.6, 3.8, C.Stone)
	b:box("Walls", -2.6, 0.6, 0.2, 2.6, 5.0, 3.4, C.WoodDark)
	b:box("Door", -1.0, 0.6, 0.05, 1.0, 3.9, 0.25, C.Wood, Kit.NOSHADOW)
	local board = b:box("Board", -2.4, 4.1, -0.05, 2.4, 5.0, 0.2, C.Cream, Kit.NOSHADOW)
	Kit.sign(board, U.Enum.NormalId.Front, "КОПТИЛЬНЯ", C.Navy, nil, { pps = 24 })
	gable(b, -3.4, 3.4, -0.6, 4.0, 5.0, 7.4, C.RoofBrown)
	b:box("Chimney", 1.1, 5.6, 2.2, 2.3, 9.2, 3.4, C.Brick)
	local cap = b:box("ChimneyCap", 0.9, 9.2, 2.0, 2.5, 9.7, 3.6, C.StoneDark, Kit.NOSHADOW)
	Kit.smoke(cap, { rate = 1.2, size = 1.2, rise = 2.5 })
	-- the drying rack: two posts, a bar, three fish hanging from it
	for i, x in { 3.7, 5.9 } do
		b:box(`RackPost{i}`, x - 0.25, -0.05, 1.2, x + 0.25, 4.6, 1.7, C.WoodDark)
	end
	b:box("RackBar", 3.3, 4.2, 1.25, 6.3, 4.6, 1.65, C.Wood, Kit.NOSHADOW)
	for i, x in { 4.3, 4.85, 5.4 } do
		b:box(
			`Fish{i}`,
			x - 0.2,
			2.6 + (i % 2) * 0.3,
			1.3,
			x + 0.2,
			4.2,
			1.6,
			if i == 2 then C.Gold else SILVER,
			Kit.DECOR
		)
	end
	-- the accent: a small window shutter by the door
	b:box("Shutter", 1.4, 2.2, 0.05, 2.2, 3.6, 0.25, color, Kit.NOSHADOW)
	return plinth
end

-- Lemonade stall (14 parts): a wooden counter with a cream «ЛИМОНАД» panel, a light top with a
-- jug and cups, two dark posts at the back under a striped canvas awning, a crate of lemons.
local function lemonadeStop(b: any, color: any)
	local counter = b:box("Counter", -3.0, -0.05, -0.6, 3.0, 3.2, 1.2, C.Wood)
	local panel = b:box("Panel", -2.6, 0.5, -0.75, 2.6, 2.7, -0.55, C.Cream, Kit.DECOR)
	Kit.sign(panel, U.Enum.NormalId.Front, "ЛИМОНАД", C.Navy, nil, { pps = 24 })
	b:box("Top", -3.3, 3.2, -0.9, 3.3, 3.6, 1.5, C.WoodLight)
	b:box("Jug", -2.3, 3.6, -0.5, -1.3, 5.0, 0.5, lerp(C.Yellow, C.Cream, 0.35), Kit.NOSHADOW)
	b:box("Cups", 0.4, 3.6, -0.4, 1.6, 4.4, 0.2, C.White, Kit.DECOR)
	for i, x in { -3.2, 2.6 } do
		b:box(`Post{i}`, x, -0.05, 1.5, x + 0.6, 7.6, 2.1, C.WoodDark)
	end
	awning(b, -3.8, 3.8, -1.7, 2.4, 7.6, color)
	b:box("Crate", 3.6, -0.05, -0.2, 5.4, 1.5, 1.6, C.WoodLight)
	b:box("Lemons", 3.8, 1.45, 0.0, 5.2, 1.9, 1.4, C.Yellow, Kit.DECOR)
	return counter
end

-- Fishing spot on the sea wall (9 parts), on the coping's lagoon edge (cf on the coping top,
-- -Z to the lagoon, the edge at z = -1.4): a folding stool, a rod in an iron holder out over the
-- beach with its line and a float on the water, a bucket with a fish and a tackle box.
local function fishingSpotStop(b: any, color: any, waterY: number)
	local seat = b:box("StoolSeat", -0.8, 1.2, -0.2, 0.8, 1.45, 1.1, C.Canvas)
	b:box("StoolLegs", -0.7, 0, 0.0, 0.7, 1.2, 0.9, C.WoodDark, Kit.NOSHADOW)
	b:box("Holder", -1.6, 0, -1.3, -1.0, 1.6, -0.7, C.Iron, Kit.NOSHADOW)
	-- the rod from the holder up and out over the beach, the line straight down to the water
	local a, tip = Vector3.new(-1.3, 1.2, -1.0), Vector3.new(-1.3, 8.0, -16.0)
	local mid = (a + tip) / 2
	b:block("Rod", Vector3.new(0.25, 0.25, (tip - a).Magnitude), CFrame.lookAt(mid, tip), C.WoodDark, Kit.DECOR)
	b:box("Line", -1.35, waterY + 0.3, -16.05, -1.25, 8.0, -15.95, C.White, Kit.DECOR)
	b:box("Float", -1.6, waterY - 0.1, -16.3, -1.0, waterY + 0.5, -15.7, C.Red, Kit.DECOR)
	b:box("Bucket", 1.3, 0, -0.6, 2.5, 1.3, 0.6, C.BoatPaint[3])
	b:box("Fish", 1.6, 1.25, -0.3, 2.2, 2.0, 0.3, SILVER, Kit.DECOR)
	b:box("TackleBox", -3.0, 0, -0.5, -1.8, 0.9, 0.5, color)
	return seat
end

-- Boat hire (18 parts): a rowboat (Palette boat paint) lying keel-up on two trestles, being
-- repainted (a paint tin in the base colour on the walk), two oars leaning on a trestle and a
-- «ЛОДКИ» board on a post.
local function boatHireStop(b: any, color: any)
	local first
	for i, x in { -2.9, 2.9 } do
		local beam = b:box(`TrestleBeam{i}`, x - 0.35, 1.7, -0.1, x + 0.35, 2.1, 3.5, C.WoodDark)
		first = first or beam
		b:box(`TrestleLegs{i}`, x - 0.25, -0.05, 0.2, x + 0.25, 1.7, 3.2, C.Wood, Kit.NOSHADOW)
	end
	-- the boat: along X, keel up, its rim (y 1.3 in the boat's frame) resting on the beams
	local boat = Kit.prop(
		"rowboat",
		b.model,
		b.cf * CFrame.new(0, 2.1 + 1.3, 1.7) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.pi),
		{ color = C.BoatPaint[3], oars = false, bob = 0, seed = 7 }
	)
	for _, name in { "SeatFront", "SeatBack" } do
		local seat = boat and boat:FindFirstChild(name)
		if seat then
			seat:Destroy() -- hidden under the upturned hull
		end
	end
	-- the bottom boards (now on top) in a darker shade of the paint, a dark keel along them
	local bottom = boat and boat:FindFirstChild("Hull")
	if bottom then
		bottom.Color = lerp(C.BoatPaint[3], C.WoodDark, 0.45)
	end
	b:box("Keel", -4.4, 3.75, 1.45, 4.2, 4.3, 1.95, C.WoodDark, Kit.NOSHADOW)
	b:box("Oars", 4.2, -0.05, 0.2, 4.5, 4.6, 0.5, C.WoodLight, Kit.DECOR)
	b:box("OarBlades", 4.05, -0.05, 0.05, 4.65, 1.6, 0.65, C.WoodDark, Kit.DECOR)
	b:box("PaintTin", -4.6, -0.05, -0.4, -3.8, 0.9, 0.4, color)
	b:box("SignPost", -5.6, -0.05, 2.4, -5.1, 6.2, 2.9, C.WoodDark)
	local board = b:box("Sign", -7.1, 4.6, 2.05, -3.6, 6.0, 2.4, C.Cream)
	Kit.sign(board, U.Enum.NormalId.Front, "ЛОДКИ", C.Navy, nil, { pps = 24 })
	return first
end

-- Bait shed (18 parts): a little plank shed on a stone plinth with dark corner posts and a
-- skirting board, a door, a framed window with a sill and shutters in the base colour, a
-- «НАЖИВКА» board under the eave, a gabled slate roof, a barrel and two crates beside it.
local function baitShedStop(b: any, color: any)
	local plinth = b:box("Plinth", -3.9, -0.05, -0.5, 3.9, 0.6, 3.8, C.Stone)
	b:box("Walls", -3.4, 0.6, 0.0, 3.4, 5.4, 3.5, C.Plank)
	b:box("Skirting", -3.45, 0.6, -0.05, 3.45, 1.1, 3.55, C.WoodDark, Kit.NOSHADOW)
	for i, x in { -3.7, 3.1 } do
		b:box(`Corner{i}`, x, 0.6, -0.25, x + 0.6, 5.4, 0.35, C.WoodDark)
	end
	b:box("Door", -2.8, 1.1, -0.15, -1.0, 4.4, 0.0, C.WoodDark, Kit.NOSHADOW)
	b:box("WindowFrame", 0.3, 2.0, -0.15, 2.7, 4.2, 0.0, C.Cream, Kit.NOSHADOW)
	b:box("Glass", 0.65, 2.35, -0.25, 2.35, 3.85, -0.1, C.WindowBlue, Kit.DECOR)
	b:box("Sill", 0.1, 1.75, -0.5, 2.9, 2.05, 0.0, C.WoodLight, Kit.NOSHADOW)
	for i, x in { -0.25, 2.7 } do
		b:box(`Shutter{i}`, x, 2.0, -0.2, x + 0.55, 4.2, -0.05, color, Kit.DECOR)
	end
	local board = b:box("Board", -3.0, 4.6, -0.45, 3.0, 5.35, -0.15, C.Cream, Kit.NOSHADOW)
	Kit.sign(board, U.Enum.NormalId.Front, "НАЖИВКА", C.Navy, nil, { pps = 24 })
	gable(b, -4.3, 4.3, -1.2, 4.1, 5.4, 8.0, C.RoofSlate)
	b:pole("Barrel", 1.9, 5.0, 1.0, -0.05, 2.5, C.Wood)
	b:box("CrateA", -5.9, -0.05, 0.0, -4.2, 1.6, 1.8, C.WoodLight)
	b:box("CrateB", -5.7, 1.6, 0.25, -4.4, 2.8, 1.55, C.Wood)
	return plinth
end

-- Island map board (13 parts): a cream board on two dark posts with a painted map (sea, the
-- island and the hub), a «КАРТА ОСТРОВА» header and a small gabled roof, a flower pot on each
-- side.
local function mapBoardStop(b: any, color: any)
	local first = b:box("PostA", -3.2, -0.05, 0.9, -2.6, 7.2, 1.5, C.WoodDark)
	b:box("PostB", 2.6, -0.05, 0.9, 3.2, 7.2, 1.5, C.WoodDark)
	b:box("Board", -2.7, 1.8, 0.75, 2.7, 5.6, 1.15, C.Cream)
	b:box("MapSea", -2.3, 2.2, 0.62, 2.3, 5.2, 0.76, C.WaterLight, Kit.DECOR)
	b:box("MapIsland", -1.5, 2.6, 0.55, 1.5, 4.8, 0.7, C.GrassTop, Kit.DECOR)
	b:box("MapHub", -0.5, 3.3, 0.5, 0.5, 4.1, 0.6, C.Sand, Kit.DECOR)
	local header = b:box("Header", -2.9, 5.7, 0.75, 2.9, 6.9, 1.15, C.Wood)
	Kit.sign(
		header,
		U.Enum.NormalId.Front,
		"КАРТА ОСТРОВА",
		C.Cream,
		C.WoodDark,
		{ pps = 24, strokeThickness = 2 }
	)
	gable(b, -3.7, 3.7, 0.1, 2.3, 7.2, 8.4, C.RoofGreen)
	for i, x in { -4.6, 4.6 } do
		b:box(`Pot{i}`, x - 0.8, -0.05, 0.2, x + 0.8, 1.4, 1.8, C.Brick)
		b:box(`Bloom{i}`, x - 0.65, 1.3, 0.35, x + 0.65, 2.5, 1.65, if i == 1 then color else C.Flowers[2], Kit.DECOR)
	end
	return first
end

-- Flower cart (17 parts): a wooden cart with a dark rim, two wheels and handles, three iron
-- buckets of flowers (leaves and blooms: Palette flowers, one in the base colour), a «ЦВЕТЫ»
-- board on a post.
local function flowerCartStop(b: any, color: any)
	local bed = b:box("Bed", -2.6, 1.1, -0.6, 2.6, 2.4, 1.6, C.Wood)
	b:box("Rim", -2.75, 2.3, -0.75, 2.75, 2.65, 1.75, C.WoodDark, Kit.NOSHADOW)
	wheels(b, 1.5, -0.85, 2.2)
	b:box("Handles", 2.75, 2.0, -0.4, 4.2, 2.3, 1.4, C.WoodDark, Kit.DECOR)
	for i, spec in { { -1.7, color }, { 0, C.Flowers[2] }, { 1.7, C.Flowers[5] } } do
		local x = spec[1]
		local h = (i % 2) * 0.35
		b:box(`Bucket{i}`, x - 0.65, 2.6, -0.1, x + 0.65, 3.6, 1.1, C.Iron, Kit.NOSHADOW)
		b:box(`Leaves{i}`, x - 0.8, 3.5, -0.25, x + 0.8, 4.3 + h, 1.25, C.Leaf2, Kit.DECOR)
		b:box(`Blooms{i}`, x - 0.55, 4.2 + h, 0.0, x + 0.55, 5.0 + h, 1.0, spec[2], Kit.DECOR)
	end
	b:box("SignPost", -0.25, -0.05, 2.2, 0.25, 6.6, 2.7, C.WoodDark)
	local board = b:box("Sign", -2.2, 5.2, 1.9, 2.2, 6.6, 2.2, C.Cream)
	Kit.sign(board, U.Enum.NormalId.Front, "ЦВЕТЫ", C.Navy, nil, { pps = 24 })
	return bed
end

local STOPS = {
	{ name = "IceCreamCart", build = iceCreamStop },
	{ name = "Smokehouse", build = smokehouseStop },
	{ name = "LemonadeStall", build = lemonadeStop },
	{ name = "FishingSpot", build = fishingSpotStop, seaWall = true },
	{ name = "BoatHire", build = boatHireStop },
	{ name = "BaitShed", build = baitShedStop },
	{ name = "MapBoard", build = mapBoardStop },
	{ name = "FlowerCart", build = flowerCartStop },
}

-- Wooden direction sign (8 parts) at a landmark path mouth: two dark posts on stone feet, a
-- painted board (white text with a dark outline) in a wooden frame, a small gabled roof.
-- Stands on cf, front -Z.
local function pathSign(parent: any, cf: any, text: string, color: any): any
	local b = Kit.builder(parent, "PathSign", cf)
	local W, H, lift = 13, 4, 3.5
	local first
	for i, x in { -W / 2 + 1.6, W / 2 - 1.6 } do
		local post = b:box(`Post{i}`, x - 0.6, -1, 0.2, x + 0.6, lift + H + 1.2, 1.4, C.WoodDark)
		first = first or post
		b:box(`Foot{i}`, x - 1.0, -0.4, -0.2, x + 1.0, 0.8, 1.8, C.StoneLight, Kit.NOSHADOW)
	end
	b:box("Frame", -W / 2 - 0.5, lift - 0.5, -0.3, W / 2 + 0.5, lift + H + 0.5, 0.2, C.Wood)
	local board = b:box("Board", -W / 2, lift, -0.5, W / 2, lift + H, -0.3, color)
	Kit.sign(board, U.Enum.NormalId.Front, text, C.White, C.Navy)
	local y0 = lift + H + 0.5
	wedge(b, "RoofFront", -W / 2 - 1.2, y0, -1.0, W / 2 + 1.2, y0 + 1.4, 0.4, "-z", C.RoofBrown)
	wedge(b, "RoofBack", -W / 2 - 1.2, y0, 0.4, W / 2 + 1.2, y0 + 1.4, 1.8, "+z", C.RoofBrown)
	return b:finish(first)
end

function Promenade.buildPromenade(map: any, cfg: any, world: any): number
	local promenade = U.model(map, "Promenade")
	local G = cfg.GroundTop
	local inner = cfg.PromenadeRadius
	local outer = inner + cfg.PromenadeWidth
	local top = G + DECK_TOP

	-- Paving: 48 light sandstone flags (7.5°), all one colour at one height (the chord
	-- rectangles overlap near the inner edge: same colour, so no seam, no lip and no shimmer), a
	-- darker joint strip across the walk on every flag boundary, a darker cobble runner down the
	-- middle (over the joints) and light stone kerbs.
	local paving = U.model(promenade, "Paving")
	local step = 360 / 96 -- railing post grid (3.75°)
	local mid = (inner + 1.6 + outer - 1.4) / 2 -- middle of the open walk (coping to kerb)
	for k = 0, 47 do
		local a0 = k * 2 * step
		ringPiece(paving, "Tile", a0, a0 + 2 * step, inner + 0.2, outer, G - 1, top, WALK, FLAT)
		ringPiece(paving, "Runner", a0, a0 + 2 * step, mid - 2.0, mid + 2.0, top, top + 0.2, RUNNER, FLAT)
	end
	-- joint strips (2 wide, 0.12 proud) from the coping to the kerb
	for k = 0, 47 do
		local a = k * 2 * step
		local p = U.polar(a, mid, 0)
		U.part(
			paving,
			"Joint",
			Vector3.new(2, 0.24, outer - inner - 3.0),
			CFrame.new(p.X, top, p.Z) * CFrame.Angles(0, rad(a), 0),
			JOINT,
			nil,
			FLAT
		)
	end
	-- outer kerb (0.5 high: walkable) between the plots; in front of a plot its own front wall
	-- already edges the walk, and it opens where the gateway roads (± 9 studs) and the landmark
	-- paths (± 6) leave the ring. It overhangs the tiles' outer face by ~0.2 (no shimmer).
	local roadGap = math.deg(math.asin(11 / outer))
	local pathGap = math.deg(math.asin(8 / outer))
	for _, run in
		runs(cfg, function(a)
			for i = 1, cfg.BaseCount do
				if Kit.angleDistance(a, cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount) < 11 then
					return "open"
				end
			end
			for _, b in cfg.BridgeAngles do
				if Kit.angleDistance(a, b) < roadGap then
					return "open"
				end
			end
			for _, s in STEP_ANGLES do
				if Kit.angleDistance(a, s) < pathGap then
					return "open"
				end
			end
			return "kerb"
		end)
	do
		if run[3] == "kerb" then
			for _, pc in pieces(run[1], run[2], 7.5) do
				ringPiece(paving, "KerbOuter", pc[1], pc[2], outer - 1.4, outer + 0.2, top, top + 0.5, KERB, FLAT)
			end
		end
	end

	-- Parapet on the lagoon side, on the sea wall's coping: a low sandstone wall between pale
	-- stone pillars every 7.5°, iron lamps on every other pillar; open at piers, bridges and the
	-- beach steps.
	local railing = U.model(promenade, "Railing")
	local postR = inner + 0.9
	local lampModel = U.model(promenade, "Lamps")
	local lamps = 0
	local lampAngles = {}
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		for _, off in { 7.5, 15, 30, 37.5 } do
			lampAngles[floor(((base + off) % 360) * 100 + 0.5)] = true
		end
	end
	local function isLamp(a: number): boolean
		return lampAngles[floor((a % 360) * 100 + 0.5)] == true
	end
	-- Sea wall along the lagoon edge: a sandstone face from the beach (y 1.5) up to the walk in
	-- blocks of two shades by turns, under a pale coping that is also the railing's kerb; where
	-- the railing is open (beside the piers and bridge landings, at the beach steps) the wall
	-- stops just under the tiles, with a stone and a sand step down to the beach.
	local seaWall = U.model(promenade, "SeaWall")
	local copings = {} -- { a0, a1 } of the coping pieces (the fishing spot sits on one)
	local nWall = 0
	for _, run in
		runs(cfg, function(a)
			return if onDeck(cfg, a) then "deck" elseif inGap(cfg, a) then "open" else "rail"
		end)
	do
		if run[3] == "deck" then
			continue
		end
		for _, pc in pieces(run[1], run[2], 7.5) do
			nWall += 1
			local stone = WALL[nWall % 2 + 1]
			if run[3] == "rail" then
				ringPiece(seaWall, "Wall", pc[1], pc[2], WALL_IN + 0.2, inner + 0.3, 1.5, top - 0.2, stone, FLAT)
				ringPiece(seaWall, "Coping", pc[1], pc[2], WALL_IN, inner + 1.6, top - 0.2, top + 0.6, COPING, FLAT)
				table.insert(copings, pc)
			else
				ringPiece(seaWall, "Wall", pc[1], pc[2], WALL_IN, inner + 0.3, 1.5, top - 0.12, stone, FLAT)
				-- two steps down to the beach along the whole opening (beside the piers and at the
				-- step gaps between two plots): no ledge to jump back up
				ringPiece(seaWall, "Step1", pc[1], pc[2], WALL_IN - 2.8, WALL_IN + 0.1, 1.5, 3.85, COPING, FLAT)
				ringPiece(seaWall, "Step2", pc[1], pc[2], WALL_IN - 5.6, WALL_IN - 2.8, 1.5, 2.95, C.SandDark, FLAT)
			end
		end
	end

	-- (the end pillars stand 0.95 inside the run, so their sides stay clear of the coping's end)
	local inset = math.deg(0.95 / postR)
	local node = 2 * step -- pillar grid (7.5°): every lamp angle is on it
	for _, run in railRuns(cfg) do
		local a0, a1 = run[1] + inset, run[2] - inset
		-- pillars at the run ends and on the 7.5° grid between them
		local list = { a0 }
		local g = math.ceil(a0 / node + 0.01) * node
		while g < a1 - 1 do
			table.insert(list, g)
			g += node
		end
		table.insert(list, a1)
		for j, a in list do
			local p = U.polar(a, postR, 0)
			local turn = CFrame.Angles(0, rad(a), 0)
			U.part(
				railing,
				"Pillar",
				Vector3.new(1.8, PILLAR_TOP - 0.6, 1.8),
				CFrame.new(p.X, top + (PILLAR_TOP + 0.6) / 2, p.Z) * turn,
				COPING
			)
			if isLamp(a) then
				-- an iron lamp on the pillar
				Kit.lamp(lampModel, CFrame.new(p.X, top + PILLAR_TOP, p.Z) * turn, {
					height = 5,
					post = C.Iron,
					trim = C.Navy,
					light = lamps % 4 == 0,
				})
				lamps += 1
			end
			if j > 1 then
				-- the parapet between this pillar and the last one: a chord into both pillars
				local q = U.polar(list[j - 1], postR, 0)
				local d = Vector3.new(p.X - q.X, 0, p.Z - q.Z)
				local m = (p + q) / 2
				local y = top + (0.6 + PARAPET_TOP) / 2
				U.part(
					railing,
					"Parapet",
					Vector3.new(0.9, PARAPET_TOP - 0.6, d.Magnitude),
					CFrame.lookAt(Vector3.new(m.X, y, m.Z), Vector3.new(p.X, y, p.Z)),
					WALL[1]
				)
			end
		end
	end
	-- life rings on the parapet's lagoon face next to the sand steps (one beside each flight)
	for k, sa in STEP_ANGLES do
		local a = sa + (if k % 2 == 0 then step else -step)
		local p = U.polar(a, postR - 1.25, 0)
		-- (front, local -Z, towards the lagoon)
		Kit.prop("lifebuoy", railing, CFrame.new(p.X, top + 2.3, p.Z) * CFrame.Angles(0, rad(a), 0), { seed = k })
	end

	-- The bridge landing at angle a (within 1°), if any.
	local function bridgeAt(a: number): number?
		for _, b in cfg.BridgeAngles do
			if Kit.angleDistance(a, b) < 1 then
				return b
			end
		end
		return nil
	end
	-- Radius of the coping's lagoon edge on the ray `a` (the pieces are chords), nil off it.
	local function copingEdge(a: number): number?
		for _, pc in copings do
			if a >= pc[1] and a <= pc[2] then
				local am = (pc[1] + pc[2]) / 2
				local half = rad(pc[2] - pc[1]) / 2
				local rm = (WALL_IN + inner + 1.6) / 2 * cos(half)
				return (rm - (inner + 1.6 - WALL_IN) / 2) / cos(rad(a - am))
			end
		end
		return nil
	end

	-- Two-tone bunting (the quarter's district colour and white) between the first two lamps
	-- after each pier (lantern tops ~ y + 11).
	local bunting = U.model(promenade, "Bunting")
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		local pa = U.polar(base + 7.5, postR, top + 10.9)
		local pb = U.polar(base + 15, postR, top + 10.9)
		offsetFlags(Kit.prop("bunting", bunting, pa, pb, {
			seed = i * 7,
			count = 4,
			sag = 2.4,
			name = "Bunting",
			colors = twoTone(quarterColor(base + 11)),
		}))
	end

	-- A bench facing the lagoon and planters on both sides of each plot's gate; more planters
	-- along the land edge of the stretches between two plots (both sides of the gateway road
	-- or landmark path), so something in bloom passes by every ~35 studs. The lagoon edge keeps
	-- its lamps only: the running lane stays clear.
	local furniture = U.model(promenade, "Furniture")
	local n = 0
	local flowers = C.Flowers
	local function planterAt(a: number, r: number)
		n += 1
		local q = U.polar(a, r, 0)
		planter(
			furniture,
			CFrame.new(q.X, top, q.Z) * CFrame.Angles(0, rad(a), 0),
			flowers[(n * 2) % #flowers + 1],
			flowers[(n * 2 + 3) % #flowers + 1]
		)
	end
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		local ab = base + 9
		local p = U.polar(ab, outer - 3.2, 0)
		Kit.bench(furniture, CFrame.new(p.X, top, p.Z) * CFrame.Angles(0, rad(ab), 0), {
			length = 7,
			color = C.WoodLight,
			legs = C.Iron,
		})
		for _, sgn in { -1, 1 } do
			planterAt(base + sgn * 5.6, outer - 2.6)
		end
		-- the stretch from this plot to the next one (centre = base + 22.5); beside a bridge
		-- landing the stops stand there instead
		local gap = base + 180 / cfg.BaseCount
		if not bridgeAt(gap) then
			for _, off in { -6.2, 6.2 } do
				planterAt(gap + off, outer - 2.6)
			end
		end
	end

	-- Stops: one on every stretch from a base's gate to its bridge landing, with the base's
	-- colour on small accents, on the outer half of the walk (from r ~324 out, every solid part
	-- centred beyond r 325: 10 studs of lane stay free between it and the lamps) 5.5° from the
	-- bridge, between the lamps; the fishing spot is on the sea wall's coping instead, half-way
	-- between two lamps.
	local stops = U.model(promenade, "Stops")
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		local half = 180 / cfg.BaseCount
		local bridge = bridgeAt(base + half) or bridgeAt(base - half)
		if not bridge then
			continue
		end
		local dir = if Kit.angleDistance(base - half, bridge) < 1 then 1 else -1 -- bridge to base
		local spec = STOPS[(i - 1) % #STOPS + 1]
		local color = BASE_COLORS[(i - 1) % #BASE_COLORS + 1]
		local b
		if spec.seaWall then
			local a = bridge + dir * 11.25
			local edge = copingEdge(a) or WALL_IN
			local cf = U.polarCFrame(a, edge + 1.4, top + 0.6)
			b = Kit.builder(stops, spec.name, cf)
			b:finish(spec.build(b, color, -(top + 0.6)))
		else
			local a = bridge + dir * 5.5
			b = Kit.builder(stops, spec.name, U.polarCFrame(a, outer - 4.1, top))
			b:finish(spec.build(b, color))
		end
	end

	-- Direction signs at the landmark path mouths (land side, beside the path, facing the
	-- lagoon), on the first spot where both feet stand on the same flat ground (the waterfall
	-- pond's sand rim reaches the promenade). Each sign is claimed (Nature keeps off it).
	for _, sign in PATH_SIGNS do
		local spot = nil
		local side = sign.side or 1
		for _, d in { 2.7, 3.4, 4.1, -2.7, -3.4, 4.8, 5.5 } do
			for _, dr in { 5, 4, 7 } do
				local a = sign.angle + d * side
				local ok = true
				-- (the feet reach 6 studs to the sides and 2 behind the board)
				for _, f in { -6.5, -4, 0, 4, 6.5 } do
					for _, back in { -0.5, 2.5 } do
						local x, z = Kit.radial(a, outer + dr + back, f, 0)
						local h, kind, water = world:surfaceAt(x, z)
						if water or h ~= G or kind == "sand" then
							ok = false
						end
					end
				end
				if ok then
					spot = { a, outer + dr }
					break
				end
			end
			if spot then
				break
			end
		end
		local fallback = { sign.angle + 2.7 * side, outer + 5 }
		local a, r = (spot or fallback)[1], (spot or fallback)[2]
		local p = U.polar(a, r, 0)
		Kit.claim(p.X, p.Z, 8)
		pathSign(
			promenade,
			CFrame.new(p.X, world:heightAt(p.X, p.Z), p.Z) * CFrame.Angles(0, rad(sign.angle), 0),
			sign.text,
			sign.color
		)
	end

	return lamps
end

return Promenade
