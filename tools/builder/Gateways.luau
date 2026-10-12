--[[
	Gateways — the 4 themed plazas behind the bridge landings (world.gateways, r ≈ 372,
	radius 40, flat GroundTop). Each one (Map.Gateways.Gateway_N) has:
	  • a paved plaza (rounded-square paving, a coloured inner ring, an entry road from the
	    promenade);
	  • a big welcome arch over the entry road with a name board («СЕВЕРНЫЕ ВОРОТА» …) in the
	    gateway colour, lanterns on the pillars, a stepped roof with a gold top;
	  • a themed centrepiece: fish fountain (north), giant flower bed (east), anchor monument
	    with a treasure chest (south), camp with a totem (west);
	  • a market stall (fish / flowers / ice cream / souvenirs), a notice board, a photo frame,
	    topiary planters, benches and flower beds round the edge — the middle stays open.

	Local frame of a plaza: origin at its centre on the ground, +Z away from the lagoon (like a
	base slot's frame), so the entry road comes in from -Z.
]]

local U = require("./Util")
local Kit = require("./MapKit")
local Promenade = require("./Promenade")

local CFrame = U.CFrame
local Enum = U.Enum
local rgb = U.rgb
local C = Kit.C

local rad = math.rad

local Gateways = {}

local FLOOR = 0.35 -- plaza paving top above GroundTop

-- Per-gateway details (keyed by bridge angle).
local THEMES = {
	[180] = { centre = "fountain", stall = "РЫБА", goods = "fish" },
	[90] = { centre = "flowers", stall = "ЦВЕТЫ", goods = "flowers" },
	[0] = { centre = "anchor", stall = "МОРОЖЕНОЕ", goods = "icecream" },
	[270] = { centre = "camp", stall = "СУВЕНИРЫ", goods = "souvenirs" },
}

--------------------------------------------------------------------------------------------
-- Pieces (each builds in its own local frame: y = 0 on the paving, front = -Z)
--------------------------------------------------------------------------------------------

local function welcomeArch(parent: any, cf: any, text: string, color: any)
	-- white candy-striped pillars (bands in the gateway colour), lanterns on top, a big board
	-- in the gateway colour between Neon rims, a stepped roof with a gold star: it reads as a
	-- different thing than the wooden bridge gate in front of it.
	local b = Kit.builder(parent, "WelcomeArch", cf)
	local dark = Kit.shade(color, 0.78)
	local light = Kit.lerpColor(color, C.White, 0.4)
	for _, sx in { -1, 1 } do
		local x0, x1 = sx * 12, sx * 16
		local lo, hi = math.min(x0, x1), math.max(x0, x1)
		local xm = (lo + hi) / 2
		b:box("Plinth", lo - 0.8, -0.5, -2.8, hi + 0.8, 2.4, 2.8, C.Cream)
		b:box("Pillar", lo, 2.4, -2, hi, 20, 2, C.White)
		for k, y in { 5.2, 10.2, 15.2 } do
			b:box(`Band{k}`, lo - 0.25, y, -2.25, hi + 0.25, y + 1.8, 2.25, color, Kit.NOSHADOW)
		end
		b:box("Capital", lo - 0.7, 20, -2.7, hi + 0.7, 21.4, 2.7, color)
		local glow = b:box("Lantern", xm - 1.5, 21.4, -1.5, xm + 1.5, 24.4, 1.5, C.Glow, Kit.NEON)
		b:box("LanternCap", xm - 2.1, 24.4, -2.1, xm + 2.1, 25.3, 2.1, dark, Kit.NOSHADOW)
		if sx > 0 then
			Kit.light(glow, 16, 1.2)
		end
	end
	-- the big board hanging between the pillars, Neon rims, a stepped roof and a gold star
	b:box("BoardFrame", -16.4, 13.4, -1.0, 16.4, 22.2, 1.0, C.White)
	local board = b:box("Board", -15.4, 14.2, -1.25, 15.4, 21.4, 1.25, color)
	Kit.sign(board, Enum.NormalId.Front, text, C.White, C.Navy, { pps = 24 })
	Kit.sign(board, Enum.NormalId.Back, text, C.White, C.Navy, { pps = 24 })
	b:box("RimBottom", -16.4, 12.8, -1.1, 16.4, 13.4, 1.1, C.Yellow, Kit.NEON)
	b:box("RimTop", -16.4, 22.2, -1.1, 16.4, 22.8, 1.1, C.Yellow, Kit.NEON)
	b:box("Roof1", -10, 22.8, -1.8, 10, 24.2, 1.8, light)
	b:box("Roof2", -5.5, 24.2, -1.4, 5.5, 25.4, 1.4, color)
	b:box("Star", -1.2, 25.4, -0.5, 1.2, 28.6, 0.5, C.Gold, Kit.NEON_DECOR)
	b:box("StarX", -2.4, 26.4, -0.45, 2.4, 27.6, 0.45, C.Gold, Kit.NEON_DECOR)
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
		b:box(`PostBack{i}`, x - 0.35, 0, 2.2, x + 0.35, 9.4, 2.9, C.WoodDark)
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
	-- goods
	if goods == "fish" then
		for i, c in { C.Orange, C.Blue, C.Pink } do
			local x = -3 + (i - 1) * 3
			b:box(`Fish{i}`, x - 1.1, 3.7, -2.6, x + 1.1, 4.5, -1.6, c, Kit.DECOR)
			b:box(`Tail{i}`, x + 1.1, 3.75, -2.4, x + 1.7, 4.45, -1.8, Kit.shade(c, 0.85), Kit.DECOR)
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
	b:box("Crate", 5.6, 0, -2.2, 8, 2.4, 0.2, C.WoodLight)
	return b:finish(counter)
end

-- Wooden notice board with coloured notes under a little roof (front = -Z). 11 parts.
local function noticeBoard(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "NoticeBoard", cf)
	local post = b:box("PostL", -4.1, -0.5, -0.4, -3.3, 8.2, 0.4, C.WoodDark)
	b:box("PostR", 3.3, -0.5, -0.4, 4.1, 8.2, 0.4, C.WoodDark)
	b:box("Frame", -3.4, 2.2, -0.3, 3.4, 7.8, 0.3, C.WoodDark)
	b:box("Board", -3, 2.6, -0.45, 3, 6.4, 0.2, C.WoodLight)
	local header = b:box("Header", -3, 6.5, -0.5, 3, 7.6, 0.2, C.Cream)
	Kit.sign(header, Enum.NormalId.Front, "ОБЪЯВЛЕНИЯ", rgb(96, 56, 30), nil, { pps = 40 })
	b:box("Roof", -4.8, 8.2, -1.4, 4.8, 9.0, 1.4, color)
	b:box("Roof2", -3.4, 9.0, -0.9, 3.4, 9.6, 0.9, Kit.lerpColor(color, C.White, 0.3))
	for i, n in { { -1.8, 5.2, C.White }, { 0.4, 4.6, C.Yellow }, { 2.0, 5.4, C.Pink }, { -0.6, 3.4, C.Cyan } } do
		b:box(`Note{i}`, n[1] - 0.8, n[2] - 0.9, -0.55, n[1] + 0.8, n[2] + 0.9, -0.42, n[3], Kit.DECOR)
	end
	return b:finish(post)
end

-- Walk-in photo frame on a little stage, «ФОТО» on top (front = -Z). 9 parts.
local function photoFrame(parent: any, cf: any)
	local b = Kit.builder(parent, "PhotoSpot", cf)
	local stage = b:box("Stage", -7, -0.4, -3, 7, 0.7, 3, C.White)
	b:box("FrameL", -7, 0.7, -0.8, -5.6, 12, 0.8, C.Red)
	b:box("FrameR", 5.6, 0.7, -0.8, 7, 12, 0.8, C.Blue)
	b:box("FrameTop", -7, 12, -0.9, 7, 13.4, 0.9, C.Yellow)
	local sign = b:box("Sign", -4.5, 13.4, -0.7, 4.5, 16.4, 0.7, C.Pink)
	Kit.sign(sign, Enum.NormalId.Front, "ФОТО", C.White, C.Navy, { pps = 30 })
	Kit.sign(sign, Enum.NormalId.Back, "ФОТО", C.White, C.Navy, { pps = 30 })
	b:box("Heart", 4.6, 14.2, -0.5, 6.4, 15.8, 0.5, C.Red, Kit.DECOR)
	b:box("Heart2", 5.0, 13.5, -0.45, 6.0, 14.3, 0.45, C.Red, Kit.DECOR)
	b:box("SpotL", -2.6, 0.7, -1.4, -0.8, 0.8, 0.4, C.Yellow, Kit.DECOR)
	b:box("SpotR", 0.8, 0.7, -1.4, 2.6, 0.8, 0.4, C.Yellow, Kit.DECOR)
	return b:finish(stage)
end

--------------------------------------------------------------------------------------------
-- Centrepieces
--------------------------------------------------------------------------------------------

local function fountain(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Fountain", cf)
	local water = { CanCollide = false, CastShadow = false, Transparency = 0.15 }
	local rim = b:box("Rim", -10, 0, -6.5, 10, 2.2, 6.5, C.White)
	b:box("RimB", -6.5, 0.02, -10, 6.5, 2.22, 10, C.White)
	b:box("Water", -9, 2.0, -5.5, 9, 2.5, 5.5, rgb(60, 200, 240), water)
	b:box("WaterB", -5.5, 2.02, -9, 5.5, 2.52, 9, rgb(60, 200, 240), water)
	-- water jets around the statue
	for i, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local x, z = d[1] * 6, d[2] * 6
		b:box(`Jet{i}`, x - 0.5, 2.4, z - 0.5, x + 0.5, 6.4, z + 0.5, C.WaterLight, Kit.DECOR)
		b:box(`Splash{i}`, x - 1, 2.45, z - 1, x + 1, 3.1, z + 1, C.Foam, Kit.DECOR)
	end
	b:finish(rim)
	-- the golden fish on its pedestal rising out of the water
	Kit.prop("fishStatue", b.model, cf * CFrame.new(0, 2, 0), {
		color = C.Gold,
		belly = C.GoldLight,
		pedestal = color,
		trim = C.White,
		scale = 1.2,
		name = "GoldenFish",
	})
end

local function flowerBed(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "FlowerBed", cf)
	local rim = b:box("Rim", -10, 0, -7, 10, 1.6, 7, C.White)
	b:box("RimB", -7, 0.02, -10, 7, 1.62, 10, C.White)
	b:box("Soil", -9.2, 1.0, -6.2, 9.2, 1.9, 6.2, C.GrassTop, Kit.NOSHADOW)
	b:box("SoilB", -6.2, 1.02, -9.2, 6.2, 1.92, 9.2, C.GrassTop, Kit.NOSHADOW)
	-- a ring of 8 flower blocks in rainbow colours
	for k = 0, 7 do
		local a = k * math.pi / 4
		local x, z = math.sin(a) * 6.6, math.cos(a) * 6.6
		b:box(
			`Flower{k + 1}`,
			x - 1.1,
			1.9,
			z - 1.1,
			x + 1.1,
			3.4 + (k % 2) * 0.3,
			z + 1.1,
			C.Festive[k + 1],
			Kit.DECOR
		)
	end
	-- the giant flower: stem, two leaves, a plus of petals, a yellow centre
	b:box("Stem", -0.6, 1.9, -0.6, 0.6, 11, 0.6, C.Leaf1)
	b:box("LeafL", -3.4, 5, -0.4, -0.6, 6, 0.4, C.Leaf2, Kit.NOSHADOW)
	b:box("LeafR", 0.6, 7, -0.4, 3.2, 8, 0.4, C.Leaf2, Kit.NOSHADOW)
	b:box("Petals", -4.4, 10.6, -1.6, 4.4, 15.4, 1.0, color)
	b:box("PetalsB", -1.6, 8.6, -1.5, 1.6, 17.4, 0.9, color)
	b:box("Centre", -1.6, 11.4, -2.0, 1.6, 14.6, -1.3, C.Yellow, Kit.NOSHADOW)
	return b:finish(rim)
end

local function anchorMonument(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "AnchorMonument", cf)
	local base = b:box("Base", -6, 0, -6, 6, 1.4, 6, C.White)
	b:box("Step", -4.5, 1.4, -4.5, 4.5, 3.2, 4.5, color)
	b:box("StepTop", -5, 3.2, -5, 5, 3.8, 5, C.White)
	b:finish(base)
	Kit.prop("anchor", b.model, cf * CFrame.new(0, 3.8, 0), { color = C.Navy, ring = C.Gold, scale = 1.5 })
	Kit.prop("lifebuoy", b.model, cf * CFrame.new(0, 9.4, -1.3), { scale = 1.2 })
	Kit.prop("treasureChest", b.model, cf * CFrame.new(8, 0, -3) * CFrame.Angles(0, rad(-25), 0), { scale = 1.3 })
	Kit.prop("parasol", b.model, cf * CFrame.new(-9, 0, 2), { color = color, scale = 1.3 })
	Kit.prop("beachChair", b.model, cf * CFrame.new(-8.5, 0, -2.5) * CFrame.Angles(0, rad(20), 0), { color = C.Cyan })
end

local function camp(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Camp", cf)
	-- a carved totem: stacked coloured blocks with eyes, wings and a beak
	local t = b:box("TotemBase", -2.2, -0.5, -2.2, 2.2, 4, 2.2, C.Wood)
	b:box("Totem2", -2, 4, -2, 2, 8, 2, color)
	b:box("Totem3", -2.2, 8, -2.2, 2.2, 12, 2.2, C.Autumn1)
	b:box("Wings", -5, 9.6, -1, 5, 10.8, 1, C.Red, Kit.NOSHADOW)
	b:box("Beak", -0.8, 9.2, -3.2, 0.8, 10.4, -2.1, C.Yellow, Kit.DECOR)
	for i, x in { -1, 1 } do
		b:box(`Eye{i}`, x - 0.5, 10.6, -2.35, x + 0.5, 11.6, -2.15, C.White, Kit.DECOR)
		b:box(`Face{i}`, x - 0.6, 5.4, -2.15, x + 0.6, 6.6, -1.95, C.Dark, Kit.DECOR)
	end
	b:box("TotemTop", -1.4, 12, -1.4, 1.4, 13.4, 1.4, C.Gold)
	b:finish(t)
	Kit.prop("campfire", b.model, cf * CFrame.new(0, 0, -10), { light = true })
	for i, p in { { -5, -10, 90 }, { 5, -10, 90 }, { 0, -15, 0 } } do
		Kit.prop("log", b.model, cf * CFrame.new(p[1], 0, p[2]) * CFrame.Angles(0, rad(p[3]), 0), { seed = i })
	end
end

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

	-- paving: a rounded square, a coloured inner ring, the entry road from the promenade
	local floor = Kit.builder(model, "Paving", origin)
	local pave = rgb(255, 238, 206)
	floor:box("Plaza", -34, -0.6, -21, 34, FLOOR, 21, pave, Kit.NOSHADOW)
	floor:box("PlazaB", -21, -0.6, -34, 21, FLOOR, 34, pave, Kit.NOSHADOW)
	local ring = Kit.lerpColor(color, C.White, 0.55)
	floor:box("Ring", -16, FLOOR, -10, 16, FLOOR + 0.08, 10, ring, Kit.NOSHADOW)
	floor:box("RingB", -10, FLOOR + 0.02, -16, 10, FLOOR + 0.1, 16, ring, Kit.NOSHADOW)
	floor:box("Road", -9, -0.6, -42.6, 9, FLOOR + 0.12, -29, rgb(255, 128, 104), Kit.NOSHADOW)
	floor:finish()

	welcomeArch(model, at(0, -34), theme.gate, color)

	local centre = at(0, 0)
	if details.centre == "fountain" then
		fountain(model, centre, color)
	elseif details.centre == "flowers" then
		flowerBed(model, centre, color)
	elseif details.centre == "anchor" then
		anchorMonument(model, centre, color)
	else
		camp(model, at(0, 4), color)
	end

	-- around the edge (fronts face the plaza centre)
	stall(model, at(-24, 8, "centre"), details.stall, color, details.goods)
	noticeBoard(model, at(24, 6, "centre"), color)
	photoFrame(model, at(0, 27, "centre"))
	for i, p in { { -12, -24 }, { 12, -24 } } do
		Kit.prop(
			"planter",
			model,
			at(p[1], p[2]),
			{ seed = gw.index * 10 + i, variant = if i <= 2 then "topiary" else "flowers" }
		)
	end
	-- flower beds filling the corner pockets of the rounded paving
	for i, p in { { -27, -26 }, { 27, -26 }, { -27, 26 }, { 27, 26 } } do
		Kit.flowerMeadow(model, origin * CFrame.new(p[1], 0, p[2]), gw.index * 100 + i)
	end
	for i, p in { { -14, 18 }, { 14, 18 } } do
		Kit.prop("bench", model, at(p[1], p[2], "centre"), { seed = gw.index * 3 + i, length = 7 })
	end
	Kit.claim(gw.x, gw.z, (gw.radius or 40) + 6)
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
