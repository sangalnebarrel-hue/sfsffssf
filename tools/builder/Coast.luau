--[[
	Coast — everything on the water and in the sky (World v3, DESIGN.md §6):

	  Map.Lagoon  sailboats, rowboats, a motorboat, a ring of buoys, lily pads near both shores, a
	              floating raft with a parasol and a tiny sandbar with a palm. The water in front
	              of every pier (base-local lz -92..0, |lx| <= 26) and along the bridges stays
	              clear (lagoonClear).
	  Map.Ocean   decorated islets (world.islets): a lighthouse on a stone foundation, a pirate
	              hideout with a hut, a treasure chest and a flag, a palm grove, the big island
	              with palms on its beach, pines, a boulder and a fisherman's hut, a
	              cherry-blossom island (far islets use Nature.farTree: 5 parts a tree); a
	              shipwreck in an islet's shallows, a rock arch and a whale between the coast and
	              the boundary wall, a ring of red / yellow marker buoys just inside the wall
	              (the swim limit), two big sailboats far out at sea.
	  Map.Sky     12 voxel clouds (Props.cloud) at y 180-320 over the island and the ocean.
]]

local U = require("./Util")
local Kit = require("./MapKit")
local Nature = require("./Nature")

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
	b:box("TowelStripe", -2.65, 0.8, -1.0, 0.25, 0.97, -0.2, C.White, Kit.DECOR)
	b:finish(deck)
	Kit.prop("parasol", b.model, cf * CFrame.new(2, 0.75, 1.5), { color = C.Cyan })
	return b.model
end

local function sandbar(parent: any, cf: any)
	local b = Kit.builder(parent, "Sandbar", cf)
	local base = b:box("Sand", -11, -15, -7, 11, 0.7, 7, C.Sand)
	b:box("SandB", -7, -15, -10, 7, 0.72, 10, C.Sand)
	b:box("Top", -5, 0.7, -4, 5, 1.6, 4, Kit.lerpColor(C.Sand, C.White, 0.25))
	b:box("Wet", -12, -14.8, -8, 12, 0.25, 8, C.SandWet, Kit.NOSHADOW)
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

-- A foundation under the square footprint (half-width `half`) of a prop standing on `cf`
-- (turned like the prop) where the ground is lower than `top` somewhere (islet terraces): from
-- the lowest column up to `top`, so nothing overhangs a step. Nil when the ground is flat.
local function foundation(parent: any, world: any, cf: any, half: number, top: number, color: any): any
	local low = top
	for _, fx in { -1, -0.5, 0, 0.5, 1 } do
		for _, fz in { -1, -0.5, 0, 0.5, 1 } do
			local p = cf * Vector3.new(fx * half, 0, fz * half)
			low = math.min(low, world:heightAt(p.X, p.Z))
		end
	end
	if low >= top - 0.25 then
		return nil
	end
	local c = cf.Position
	return U.part(
		parent,
		"Foundation",
		Vector3.new(2 * half, top - low + 1, 2 * half),
		CFrame.new(c.X, (top + low - 1) / 2, c.Z) * cf.Rotation,
		color
	)
end

-- Land columns of an islet: { x, z, h, kind, d (distance from the centre) }, in a fixed order.
local function isletSites(world: any, isle: any): { any }
	local list = {}
	local n = math.floor(isle.size / 8)
	-- on the centres of the ground's 8-stud columns
	local ox, oz = math.floor(isle.x / 8) * 8 + 4, math.floor(isle.z / 8) * 8 + 4
	for iz = -n, n do
		for ix = -n, n do
			local x, z = ox + ix * 8, oz + iz * 8
			local h, kind, water = world:surfaceAt(x, z)
			if not water and h >= 2 then
				table.insert(
					list,
					{ x = x, z = z, h = h, kind = kind, d = math.sqrt((x - isle.x) ^ 2 + (z - isle.z) ^ 2) }
				)
			end
		end
	end
	return list
end

--[[
	Plants up to `count` things on islet sites that pass `filter`, at least `spacing` apart (and
	clear of `taken`), in an order shuffled by `seed`; every site must be flat over `half`
	studs. place(site, k) builds one.
]]
local function plant(
	world: any,
	sites: { any },
	taken: { any },
	count: number,
	spacing: number,
	half: number,
	seed: number,
	filter: (any) -> boolean,
	place: (any, number) -> ()
)
	local r = Kit.rng(seed)
	local order = {}
	for _, s in sites do
		if filter(s) then
			table.insert(order, { s = s, key = r() })
		end
	end
	table.sort(order, function(a, b)
		return a.key < b.key
	end)
	local k = 0
	for _, e in order do
		if k >= count then
			break
		end
		local s = e.s
		local ok = true
		for _, d in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
			if world:heightAt(s.x + d[1] * half, s.z + d[2] * half) ~= s.h then
				ok = false
			end
		end
		for _, t in taken do
			if (s.x - t[1]) ^ 2 + (s.z - t[2]) ^ 2 < spacing * spacing then
				ok = false
				break
			end
		end
		if ok then
			k += 1
			table.insert(taken, { s.x, s.z })
			place(s, k)
		end
	end
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
		local sites = isletSites(world, isle)
		local taken = {}
		local function sand(site: any): boolean
			return site.kind == "sand"
		end
		local function land(site: any): boolean
			return site.kind ~= "sand"
		end
		local function farTree(kind: string, scale0: number, scale1: number, seed: number)
			local r = Kit.rng(seed)
			return function(site: any)
				Nature.farTree(m, CFrame.new(site.x, site.h, site.z), kind, r(scale0, scale1), seed + site.x)
			end
		end
		if i == 1 then
			-- the lighthouse on the top terrace, on a stone foundation down to the lower one
			local cf = isletSpot(world, isle, 0, 0, home)
			local top = cf.Position.Y
			Kit.prop("lighthouse", m, cf, { scale = 1.3 })
			Kit.lights += 1
			foundation(m, world, cf, 8.7, top - 2.4, C.Stone)
			Kit.prop(
				"palmTree",
				m,
				isletSpot(world, isle, s * 0.42, home + 70),
				{ seed = 11, scale = 1.4, lite = true }
			)
			-- two cheap palms beside it: a little grove on the side facing the swimmers
			Nature.farTree(m, isletSpot(world, isle, s * 0.62, home + 98), "palm", 2.0, 13)
			Nature.farTree(m, isletSpot(world, isle, s * 0.6, home + 42), "palm", 1.8, 14)
			Kit.prop("rock", m, isletSpot(world, isle, s * 0.55, home - 60), { seed = 12, scale = 1.6 })
		elseif i == 3 then
			-- pirate hideout
			local hutCf = isletSpot(world, isle, s * 0.15, home + 20, home)
			hut(m, hutCf, C.Red)
			foundation(m, world, hutCf, 4.9, hutCf.Position.Y - 1, C.WoodDark)
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
			Nature.farTree(m, isletSpot(world, isle, s * 0.58, home + 150), "palm", 1.9, 32)
			Nature.farTree(m, isletSpot(world, isle, s * 0.6, home + 75), "palm", 1.7, 33)
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
			-- a palm grove (cheap far palms: it is seen through the haze) and a rock
			plant(world, sites, taken, 6, 16, 3, 21, land, farTree("palm", 1.6, 2.1, 21))
			plant(world, sites, taken, 2, 14, 2, 22, sand, function(site)
				Kit.prop("rock", m, CFrame.new(site.x, site.h, site.z), { seed = 22, scale = 1.5, moss = true })
			end)
		elseif i == 4 then
			-- the big one (far out, mostly seen through the haze, so lean): palms on the beach,
			-- pines on the upper terraces, a mossy boulder and a fisherman's hut with a blue roof
			-- facing the main island
			local cx, cz = isle.x - s * 0.25 * sin(rad(home + 180)), isle.z - s * 0.25 * cos(rad(home + 180))
			local hutCf = Kit.ground(world, cx, cz, home)
			hut(m, hutCf, C.Blue)
			foundation(m, world, hutCf, 4.9, hutCf.Position.Y - 1, C.WoodDark)
			table.insert(taken, { cx, cz })
			plant(world, sites, taken, 4, 30, 3, 41, function(site)
				return site.h >= isle.height * 0.5
			end, farTree("pine", 2.1, 2.6, 41))
			plant(world, sites, taken, 4, 26, 3, 42, function(site)
				return site.kind == "sand" or site.h <= 12
			end, farTree("palm", 1.9, 2.3, 42))
			plant(world, sites, taken, 2, 28, 3, 43, function(site)
				return site.kind ~= "sand" and site.h < isle.height * 0.5
			end, farTree("green", 2.1, 2.5, 43))
			plant(world, sites, taken, 1, 20, 5, 44, land, function(site, k)
				Kit.prop("boulder", m, CFrame.new(site.x, site.h, site.z), { seed = 44 + k, moss = true })
			end)
		elseif i == 6 then
			-- a cherry grove on the hill and two rocks on the beach
			plant(world, sites, taken, 6, 24, 3, 61, land, farTree("cherry", 1.9, 2.4, 61))
			plant(world, sites, taken, 2, 20, 3, 62, function(site)
				return site.kind ~= "sand" and site.h <= 12
			end, farTree("palm", 1.7, 2.1, 62))
			plant(world, sites, taken, 2, 16, 2, 63, sand, function(site, k)
				Kit.prop("rock", m, CFrame.new(site.x, site.h, site.z), { seed = 63 + k, scale = 1.6 })
			end)
		end
	end
	-- a rock arch (its opening facing the island) and a whale in open water between the coast
	-- and the boundary wall, where they are seen from the outer beaches
	local ra = openSea(cfg, world, 66, 24)
	Kit.prop("rockArch", ocean, onWater(66, ra, 66), { seed = 3 })
	local wa = openSea(cfg, world, 160, 22)
	Kit.prop("whale", ocean, onWater(160, wa, tangent(160, true)), { seed = 4 })
	-- the swim limit: a ring of red and yellow marker buoys just inside the invisible boundary
	-- wall, so swimmers heading for the islets see where the sea ends (1 part each; they bob
	-- round the arch and the whale)
	local line = U.model(ocean, "BuoyLine")
	local R = cfg.BoundaryRadius - 10
	local keepOff = { U.polar(66, ra, 0), U.polar(160, wa, 0) }
	local count = 72
	for k = 0, count - 1 do
		local a = (k + 0.5) * 360 / count
		local p = U.polar(a, R, 0)
		local clear = world:isWater(p.X, p.Z)
		for _, q in keepOff do
			if (p - q).Magnitude < 36 then
				clear = false
			end
		end
		if clear then
			U.part(
				line,
				"Buoy",
				Vector3.new(3.6, 3.6, 3.6),
				CFrame.new(p.X, 0.5, p.Z),
				if k % 2 == 0 then C.Red else C.Yellow,
				nil,
				{ Shape = U.Enum.PartType.Ball, CanCollide = false, CanQuery = false, CastShadow = false }
			)
		end
	end
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
		{ 95, 860 },
		{ 145, 760 },
		{ 330, 820 },
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
