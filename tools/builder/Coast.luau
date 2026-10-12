--[[
	Coast — everything on the water and in the sky (World v3, DESIGN.md §6):

	  Map.Lagoon  sailboats, rowboats, a motorboat, a ring of buoys, lily pads near both shores, a
	              floating raft with a parasol and a tiny sandbar with a palm. The water in front
	              of every pier (base-local lz -92..0, |lx| <= 26) and along the bridges stays
	              clear (lagoonClear).
	  Map.Ocean   decorated islets (world.islets): a lighthouse, a pirate hideout with a hut,
	              a treasure chest and a flag, palms and rocks; a shipwreck in an islet's
	              shallows, a rock arch and a whale between the coast and the boundary wall, two
	              big sailboats far out at sea.
	  Map.Sky     voxel clouds (Props.cloud) at y 180-320 over the island and the ocean.
]]

local U = require("./Util")
local Kit = require("./MapKit")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local C = Kit.C

local rad, sin, cos, abs = math.rad, math.sin, math.cos, math.abs

local Coast = {}

-- CFrame on the water surface at angle/radius, turned by `heading` degrees about +Y (a boat's
-- bow, local -Z, then points along (-sin heading, 0, -cos heading)).
local function onWater(angle: number, r: number, heading: number): any
	local p = U.polar(angle, r, 0)
	return CFrame.new(p.X, 0, p.Z) * CFrame.Angles(0, rad(heading), 0)
end

-- Heading (yaw degrees) that makes a boat's bow (-Z) travel tangentially round the lagoon.
local function tangent(angle: number, clockwise: boolean): number
	return if clockwise then angle - 90 else angle + 90
end

--------------------------------------------------------------------------------------------
-- Lagoon
--------------------------------------------------------------------------------------------

local function lagoonClear(cfg: any, world: any, x: number, z: number, pad: number): boolean
	for i = 1, cfg.BaseCount do
		local lx, lz = world:toBaseLocal(i, x, z)
		if abs(lx) < 26 + pad and lz > -(cfg.PierLength or 92) - pad and lz < pad then
			return false
		end
	end
	for _, a in cfg.BridgeAngles do
		local ux, uz = sin(rad(a)), cos(rad(a))
		local along = x * ux + z * uz
		local side = abs(x * uz - z * ux)
		if along > cfg.HubPlazaRadius - 10 and side < cfg.BridgeWidth / 2 + 10 + pad then
			return false
		end
	end
	return world:isWater(x, z)
end

local function raft(parent: any, cf: any)
	local b = Kit.builder(parent, "Raft", cf)
	local deck = b:box("Logs", -4, -0.8, -4, 4, 0.5, 4, C.Wood)
	for i, x in { -2.6, 0, 2.6 } do
		b:box(
			`Log{i}`,
			x - 1.2,
			0.45,
			-4.2,
			x + 1.2,
			0.75,
			4.2,
			if i % 2 == 1 then C.WoodLight else C.Wood,
			Kit.NOSHADOW
		)
	end
	b:box("Towel", -2.6, 0.75, -2.5, 0.2, 0.85, 1.5, C.Pink, Kit.DECOR)
	b:box("TowelStripe", -2.6, 0.76, -1.0, 0.2, 0.87, -0.2, C.White, Kit.DECOR)
	b:finish(deck)
	Kit.prop("parasol", b.model, cf * CFrame.new(2, 0.75, 1.5), { color = C.Cyan })
	return b.model
end

local function sandbar(parent: any, cf: any)
	local b = Kit.builder(parent, "Sandbar", cf)
	local base = b:box("Sand", -11, -15, -7, 11, 0.7, 7, C.Sand)
	b:box("SandB", -7, -15, -10, 7, 0.72, 10, C.Sand)
	b:box("Top", -5, 0.7, -4, 5, 1.6, 4, Kit.lerpColor(C.Sand, C.White, 0.25))
	b:box("Wet", -12, -15, -8, 12, 0.25, 8, C.SandWet, Kit.NOSHADOW)
	b:finish(base)
	Kit.prop("palmTree", b.model, cf * CFrame.new(1, 1.6, 0), { seed = 5, scale = 1.4, variant = 1 })
	Kit.prop("rock", b.model, cf * CFrame.new(-7, 0.7, 4), { seed = 6, count = 3 })
	Kit.prop(
		"beachChair",
		b.model,
		cf * CFrame.new(-2.5, 1.6, -1) * CFrame.Angles(0, rad(200), 0),
		{ color = C.Orange }
	)
	return b.model
end

local function buildLagoon(map: any, cfg: any, world: any)
	local lagoon = U.model(map, "Lagoon")
	local function place(name: string, angle: number, r: number, heading: number, opts: any, pad: number)
		local p = U.polar(angle, r, 0)
		if not lagoonClear(cfg, world, p.X, p.Z, pad) then
			return nil
		end
		return Kit.prop(name, lagoon, onWater(angle, r, heading), opts)
	end
	-- boats sailing round the lagoon (between the piers, away from the bridges)
	place("sailboat", 45, 226, tangent(45, true), { seed = 1, color = C.Red, stripe = C.Yellow }, 10)
	place("sailboat", 226, 238, tangent(226, false), { seed = 2, color = C.Blue, stripe = C.White }, 10)
	place("motorboat", 152, 205, tangent(152, true), { seed = 3, color = C.White, stripe = C.Red }, 8)
	place("rowboat", 314, 196, tangent(314, false) + 25, { seed = 4, color = C.Yellow }, 6)
	place("rowboat", 128, 270, tangent(128, true) - 20, { seed = 5, color = C.BoatPaint[2] }, 6)
	-- buoys on a ring between the shores
	local colors = { C.Red, C.Yellow, C.Orange, C.Pink }
	for k = 0, 7 do
		local a = k * 45 + 11.25 + (k % 2) * 22.5
		place("buoy", a, 214 + (k % 2) * 10, 0, { seed = k, color = colors[k % #colors + 1] }, 2)
	end
	-- lily pads near both shores at the landmark angles
	local n = 0
	for _, a in { 45, 135, 225, 315 } do
		for _, spec in { { -5, 287 }, { 4, 288 }, { 1, 159 } } do
			n += 1
			place("lilyPad", a + spec[1], spec[2], n * 37, { seed = n, scale = 1.5 }, 0)
		end
	end
	-- a floating raft and a tiny sandbar island with a palm
	local rp = U.polar(100, 238, 0)
	if lagoonClear(cfg, world, rp.X, rp.Z, 8) then
		raft(lagoon, CFrame.new(rp.X, 0, rp.Z) * CFrame.Angles(0, rad(30), 0))
	end
	local sp = U.polar(138, 236, 0)
	if lagoonClear(cfg, world, sp.X, sp.Z, 14) then
		sandbar(lagoon, CFrame.new(sp.X, 0, sp.Z) * CFrame.Angles(0, rad(138), 0))
	end
	return lagoon
end

--------------------------------------------------------------------------------------------
-- Ocean
--------------------------------------------------------------------------------------------

local function hut(parent: any, cf: any, roof: any)
	local b = Kit.builder(parent, "Hut", cf)
	local base = b:box("Floor", -5, -1, -4.5, 5, 0.6, 4.5, C.WoodDark)
	b:box("Walls", -4.2, 0.6, -3.8, 4.2, 6, 3.8, C.Cream)
	b:box("Roof1", -5.4, 6, -5, 5.4, 7.4, 5, roof)
	b:box("Roof2", -3.8, 7.4, -3.6, 3.8, 8.6, 3.6, Kit.lerpColor(roof, C.White, 0.2))
	b:box("Roof3", -2, 8.6, -2, 2, 9.6, 2, roof)
	b:box("Door", -1.2, 0.6, -3.95, 1.2, 4.4, -3.7, C.Blue, Kit.NOSHADOW)
	b:box("Window", 2.0, 2.6, -3.95, 3.4, 4.0, -3.7, C.WindowBlue, Kit.DECOR)
	return b:finish(base)
end

-- Ground CFrame on an islet, `r` studs from its centre towards `towards` degrees.
local function isletSpot(world: any, isle: any, r: number, a: number, yaw: number?): any
	local x = isle.x + r * sin(rad(a))
	local z = isle.z + r * cos(rad(a))
	return Kit.ground(world, x, z, yaw)
end

-- Radius on the ray `angle` of the first spot past the coast where the sea floor is at least
-- 8 deep everywhere within `clear` studs (capped inside the boundary wall).
local function openSea(cfg: any, world: any, angle: number, clear: number): number
	local limit = cfg.BoundaryRadius - clear - 6
	for r = world:coastRadius(angle) + 20, limit, 4 do
		local ok = true
		for _, d in { { 0, 0 }, { clear, 0 }, { -clear, 0 }, { 0, clear }, { 0, -clear } } do
			local p = U.polar(angle, r + d[1], 0)
			local side = Vector3.new(cos(rad(angle)), 0, -sin(rad(angle))) * d[2]
			if world:heightAt(p.X + side.X, p.Z + side.Z) > -8 then
				ok = false
				break
			end
		end
		if ok then
			return r
		end
	end
	return limit
end

local function buildOcean(map: any, cfg: any, world: any)
	local ocean = U.model(map, "Ocean")
	for i, isle in world.islets do
		local m = U.model(ocean, `Islet_{i}`)
		-- the side facing the main island
		local home = math.deg(math.atan2(-isle.x, -isle.z))
		local s = isle.size
		if i == 1 then
			Kit.prop("lighthouse", m, isletSpot(world, isle, 0, 0, home), { scale = 1.3 })
			Kit.lights += 1
			Kit.prop(
				"palmTree",
				m,
				isletSpot(world, isle, s * 0.42, home + 70),
				{ seed = 11, scale = 1.4, lite = true }
			)
			Kit.prop("rock", m, isletSpot(world, isle, s * 0.55, home - 60), { seed = 12, scale = 1.6 })
		elseif i == 3 then
			-- pirate hideout
			hut(m, isletSpot(world, isle, s * 0.15, home + 20, home), C.Red)
			Kit.prop("treasureChest", m, isletSpot(world, isle, s * 0.45, home - 15, home), { scale = 1.3 })
			Kit.prop(
				"flagPole",
				m,
				isletSpot(world, isle, s * 0.3, home - 70),
				{ color = C.Dark, stripe = C.White, height = 14 }
			)
			Kit.prop(
				"palmTree",
				m,
				isletSpot(world, isle, s * 0.5, home + 110),
				{ seed = 31, scale = 1.4, lite = true }
			)
		elseif i == 5 then
			Kit.prop("palmTree", m, isletSpot(world, isle, s * 0.2, home + 40), { seed = 51, scale = 1.5, lite = true })
			Kit.prop(
				"palmTree",
				m,
				isletSpot(world, isle, s * 0.35, home - 50),
				{ seed = 52, scale = 1.3, lite = true }
			)
			Kit.prop("boulder", m, isletSpot(world, isle, s * 0.5, home + 150), { seed = 53 })
			-- shipwreck in the shallows on the side facing the main island
			local d = s + 12
			local wx = isle.x + d * sin(rad(home + 25))
			local wz = isle.z + d * cos(rad(home + 25))
			Kit.prop("shipwreck", m, CFrame.new(wx, 0, wz) * CFrame.Angles(0, rad(home + 115), 0), { seed = 54 })
		elseif i == 2 then
			-- two big palms on the side facing the main island (lite: seen through the haze);
			-- the farthest islets stay bare, the fog hides them anyway
			Kit.prop(
				"palmTree",
				m,
				isletSpot(world, isle, s * 0.25, home + 30),
				{ seed = 21, scale = 1.8, lite = true }
			)
			Kit.prop("palmTree", m, isletSpot(world, isle, s * 0.4, home - 40), { seed = 22, scale = 1.5, lite = true })
		end
	end
	-- a rock arch (its opening facing the island) and a whale in open water between the coast
	-- and the boundary wall, where they are seen from the outer beaches
	local ra = openSea(cfg, world, 66, 24)
	Kit.prop("rockArch", ocean, onWater(66, ra, 66), { seed = 3 })
	local wa = openSea(cfg, world, 160, 22)
	Kit.prop("whale", ocean, onWater(160, wa, tangent(160, true)), { seed = 4 })
	-- two big sailboats far out at sea (beyond the wall, seen from the coast and the peaks)
	Kit.prop("sailboat", ocean, onWater(124, 930, tangent(124, true)), { seed = 21, scale = 1.6, color = C.Yellow })
	Kit.prop("sailboat", ocean, onWater(302, 960, tangent(302, false)), { seed = 22, scale = 1.6, color = C.Red })
	return ocean
end

--------------------------------------------------------------------------------------------
-- Sky
--------------------------------------------------------------------------------------------

local function buildSky(map: any, cfg: any)
	local sky = U.model(map, "Sky")
	local rng = Kit.rng(2718)
	-- (angle, radius): a ring over the hills and the coast, a few far out over the ocean; the
	-- lagoon stays clear so the sky above the play area is open
	local spots = {
		{ 20, 470 },
		{ 75, 560 },
		{ 120, 430 },
		{ 165, 600 },
		{ 210, 480 },
		{ 255, 610 },
		{ 300, 460 },
		{ 340, 640 },
		{ 230, 900 },
		{ 10, 940 },
		{ 290, 980 },
	}
	for i, s in spots do
		local p = U.polar(s[1] + rng(-8, 8), s[2], 0)
		local y = rng(185, 315)
		Kit.prop("cloud", sky, CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, rad(rng(-20, 20)), 0), {
			seed = i,
			scale = rng(2.0, 3.2),
		})
	end
	return sky
end

--------------------------------------------------------------------------------------------

function Coast.build(map: any, cfg: any, world: any)
	buildLagoon(map, cfg, world)
	buildOcean(map, cfg, world)
	buildSky(map, cfg)
end

return Coast
