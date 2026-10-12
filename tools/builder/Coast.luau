--[[
	Coast — everything on the water and in the sky (World v3, DESIGN.md §6):

	  Map.Lagoon  sailboats, rowboats, a motorboat, a ring of buoys, lily pads near both shores, a
	              floating raft with a parasol, a swim platform with a slide, a sandbar island
	              with a palm and two small ones (the coral reefs on the bed are Nature's). The
	              water in front of every pier (base-local lz -(PierLength + 16)..0, |lx| <= 26)
	              and along the bridges stays clear (lagoonClear); boats keep out of every pier's
	              whole casting cone (|lx| <= 40, lz -150..0): they sail half-way between piers.
	  Map.Ocean   decorated islets (world.islets, all beyond the boundary wall, seen through the
	              haze, so lean: Nature.farTree palms / pines / cherries at 5 parts a tree): a
	              lighthouse on a stone foundation, a pirate hideout with a hut and a flag, a palm
	              grove with a beach hut and a red-white parasol, the big island, a
	              cherry-blossom island, an island with a cheap shipwreck along its shore and a
	              red-rock sea stack off its corner; a white-sand atoll with a turquoise pool; a
	              rock arch and a whale (spouting spray) between the coast and the boundary
	              wall, a ring of red / yellow marker buoys just inside the wall (the swim
	              limit), a big sailboat far out at sea. Parts beyond the wall neither collide
	              nor cast shadows.
	  Map.Sky     voxel clouds (Props.cloud): a ring of 8 big ones low over the open ocean
	              (r 1020-1260, y 130-190: one on the horizon of every outward view) and three
	              high ones over the hills.

	Boats, buoys, the raft, the swim platform and the whale carry the attribute Bob (amplitude
	in studs, BobPeriod in seconds): AmbientController rocks them on the waves on the client.
	Their floors sit 0.5+ above the water plane (waves never flood them).
]]

local U = require("./Util")
local Kit = require("./MapKit")
local Nature = require("./Nature")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local C = Kit.C

local rad, sin, cos, abs = math.rad, math.sin, math.cos, math.abs

local Coast = {}

local BEACH_ROCK = Kit.lerpColor(C.StoneLight, C.SandDark, 0.4) -- warm light rocks on the sand

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

-- Marks a floating model for AmbientController: it bobs `amplitude` studs up and down (and
-- rolls a little) every `period` seconds on the client.
local function bob(model: any, amplitude: number, period: number): any
	if model then
		model:SetAttribute("Bob", amplitude)
		model:SetAttribute("BobPeriod", period)
	end
	return model
end

--------------------------------------------------------------------------------------------
-- Lagoon
--------------------------------------------------------------------------------------------

-- (the water 16 studs past the pier end stays open too: the fishing spot looks out over it;
-- a boat keeps out of the whole casting cone: 40 studs either side of a pier's axis, from the
-- promenade 150 studs out, nearly to the hub beach)
local function lagoonClear(cfg: any, world: any, x: number, z: number, pad: number, boat: boolean?): boolean
	local side = if boat then 40 else 26
	local reach = if boat then 150 else (cfg.PierLength or 72) + 16
	for i = 1, cfg.BaseCount do
		local lx, lz = world:toBaseLocal(i, x, z)
		if abs(lx) < side + pad and lz > -reach - pad and lz < pad then
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
	b:box("TowelStripe", -2.75, 0.7, -1.0, 0.35, 0.97, -0.2, C.White, Kit.DECOR)
	b:finish(deck)
	Kit.prop("parasol", b.model, cf * CFrame.new(2, 0.75, 1.5), { color = C.Cyan })
	return b.model
end

local function sandbar(parent: any, cf: any)
	local b = Kit.builder(parent, "Sandbar", cf)
	-- (down into the bed: nothing floats over the deep tier)
	local base = b:box("Sand", -11, -16.5, -7, 11, 0.7, 7, C.Sand)
	b:box("SandB", -7, -16.5, -10, 7, 0.72, 10, C.Sand)
	b:box("Top", -5, 0.7, -4, 5, 1.6, 4, Kit.lerpColor(C.Sand, C.White, 0.25))
	b:box("Wet", -12, -16.3, -8, 12, 0.25, 8, C.SandWet, Kit.NOSHADOW)
	b:finish(base)
	Nature.farTree(b.model, cf * CFrame.new(1, 1.6, 0), "palm", 1.7, 5)
	Kit.prop("rock", b.model, cf * CFrame.new(-7, 0.7, 4), { seed = 6, count = 3, color = BEACH_ROCK, moss = true })
	Kit.prop(
		"beachChair",
		b.model,
		cf * CFrame.new(-2.5, 1.6, -1) * CFrame.Angles(0, rad(200), 0),
		{ color = C.Orange }
	)
	return b.model
end

-- A small sandbar (8 parts + a palm): a sand mound in two steps on a wider shoal just under
-- the water, a striped towel and a starfish, a cheap palm leaning over it.
local function islandlet(parent: any, cf: any, towel: any)
	local b = Kit.builder(parent, "Sandbar", cf)
	local base = b:box("Sand", -8, -16.5, -5.5, 8, 0.6, 5.5, C.Sand)
	b:box("SandB", -5, -16.5, -8, 5, 0.62, 8, C.Sand)
	b:box("Wet", -10.5, -16.3, -9, 10.5, -0.6, 9, C.SandWet, Kit.NOSHADOW)
	b:box("Top", -3.5, 0.6, -3, 3.5, 1.3, 3, Kit.lerpColor(C.Sand, C.White, 0.25))
	b:box("Towel", -6.6, 0.6, -2.0, -4.2, 0.78, 2.6, towel, Kit.DECOR)
	b:box("TowelStripe", -6.75, 0.5, 0.0, -4.05, 0.88, 0.7, C.White, Kit.DECOR)
	b:box("StarA", 3.9, 0.6, 3.8, 6.1, 0.85, 4.4, C.Orange, Kit.DECOR)
	b:box("StarB", 4.7, 0.5, 3.0, 5.3, 0.97, 5.2, C.Orange, Kit.DECOR)
	b:finish(base)
	Nature.farTree(b.model, cf * CFrame.new(0.5, 1.3, 0.5), "palm", 1.5, 71)
	return b.model
end

-- Floating swim platform (7 parts): a white deck on yellow floats with a cyan rim, a slide
-- tower on one corner and a yellow chute down into the water.
local function swimPlatform(parent: any, cf: any)
	local b = Kit.builder(parent, "SwimPlatform", cf)
	local deck = b:box("Deck", -6, 0.3, -6, 6, 1.1, 6, C.White)
	b:box("Rim", -6.4, -0.3, -6.4, 6.4, 0.5, 6.4, C.Cyan, Kit.NOSHADOW)
	b:box("FloatA", -5.6, -1.4, -5.6, -3.4, -0.25, 5.6, C.Yellow, Kit.NOSHADOW)
	b:box("FloatB", 3.4, -1.4, -5.6, 5.6, -0.25, 5.6, C.Yellow, Kit.NOSHADOW)
	b:box("Tower", 2.0, 1.1, 2.0, 6.0, 6.6, 6.0, C.Cyan)
	b:box("TowerTop", 1.6, 6.6, 1.6, 6.4, 7.4, 6.4, C.Pink)
	b:finish(deck)
	local a = cf * Vector3.new(4.0, 6.6, 5.6)
	local c = cf * Vector3.new(4.0, -0.2, 16.5)
	Kit.ramp(b.model, a, c, { width = 3.6, thick = 0.8, color = C.Yellow, name = "Slide" })
	return b.model
end

local function buildLagoon(map: any, cfg: any, world: any)
	local lagoon = U.model(map, "Lagoon")
	-- (lift: how far the model floats above the water plane, so a low hull's floor stays dry;
	-- boats keep out of every pier's casting cone)
	local function place(name: string, angle: number, r: number, heading: number, opts: any, pad: number, lift: number?)
		local p = U.polar(angle, r, 0)
		local boat = string.find(name, "boat") ~= nil
		if not lagoonClear(cfg, world, p.X, p.Z, pad, boat) then
			return nil
		end
		return Kit.prop(name, lagoon, onWater(angle, r, heading) * CFrame.new(0, lift or 0, 0), opts)
	end
	-- boats sailing round the lagoon (half-way between two piers, away from the bridges),
	-- rocking on the waves (the rowboats' and the motorboat's floors lifted to 0.55-0.6 above the
	-- water)
	bob(place("sailboat", 45, 226, tangent(45, true), { seed = 1, color = C.Red, stripe = C.Yellow }, 10), 0.35, 4.2)
	bob(place("sailboat", 226, 238, tangent(226, false), { seed = 2, color = C.Blue, stripe = C.White }, 10), 0.35, 4.8)
	bob(
		place("motorboat", 133, 202, tangent(133, true), { seed = 3, color = C.White, stripe = C.Red }, 8, 0.3),
		0.3,
		3.4
	)
	bob(place("rowboat", 314, 196, tangent(314, false) + 25, { seed = 4, color = C.Yellow }, 6, 0.35), 0.25, 3.0)
	bob(place("rowboat", 128, 270, tangent(128, true) - 20, { seed = 5, color = C.BoatPaint[2] }, 6, 0.35), 0.25, 3.2)
	-- buoys on a ring between the shores (bobbing faster than the boats)
	local colors = { C.Red, C.Yellow, C.Orange, C.Pink }
	for k = 0, 7 do
		local a = k * 45 + 11.25 + (k % 2) * 22.5
		bob(
			place("buoy", a, 214 + (k % 2) * 10, 0, { seed = k, color = colors[k % #colors + 1] }, 2),
			0.3,
			2.4 + (k % 3) * 0.3
		)
	end
	-- lily pads near both shores at the landmark angles
	local n = 0
	for _, a in { 45, 135, 225, 315 } do
		for _, spec in { { -5, 287 }, { 4, 288 }, { 1, 159 } } do
			n += 1
			place("lilyPad", a + spec[1], spec[2], n * 37, { seed = n, scale = 1.5 }, 0)
		end
	end
	-- a floating raft, a swim platform with a slide off the hub beach, a sandbar island with a
	-- palm and a beach chair and two small sandbars with a palm and a towel
	local rp = U.polar(100, 238, 0)
	if lagoonClear(cfg, world, rp.X, rp.Z, 8, true) then
		bob(raft(lagoon, CFrame.new(rp.X, 0, rp.Z) * CFrame.Angles(0, rad(30), 0)), 0.25, 3.6)
	end
	local wp = U.polar(55, cfg.HubRadius + 24, 0)
	if lagoonClear(cfg, world, wp.X, wp.Z, 18) then
		bob(swimPlatform(lagoon, CFrame.new(wp.X, 0, wp.Z) * CFrame.Angles(0, rad(55), 0)), 0.2, 4.0)
	end
	local sp = U.polar(138, 236, 0)
	if lagoonClear(cfg, world, sp.X, sp.Z, 14) then
		sandbar(lagoon, CFrame.new(sp.X, 0, sp.Z) * CFrame.Angles(0, rad(138), 0))
	end
	for _, s in { { 318, 252, C.Pink }, { 222, 214, C.Blue } } do
		local p = U.polar(s[1], s[2], 0)
		if lagoonClear(cfg, world, p.X, p.Z, 12) then
			islandlet(lagoon, CFrame.new(p.X, 0, p.Z) * CFrame.Angles(0, rad(s[1] + 30), 0), s[3])
		end
	end
	return lagoon
end

--------------------------------------------------------------------------------------------
-- Ocean
--------------------------------------------------------------------------------------------

-- A hut (7 parts, scaled by `s`): a plank floor, cream walls, a stepped roof, door and window.
local function hut(parent: any, cf: any, roof: any, s: number?)
	local k = s or 1
	local b = Kit.builder(parent, "Hut", cf)
	local function box(name: string, x0, y0, z0, x1, y1, z1, color, extra)
		return b:box(name, x0 * k, y0 * k, z0 * k, x1 * k, y1 * k, z1 * k, color, extra)
	end
	local base = box("Floor", -5, -1, -4.5, 5, 0.6, 4.5, C.WoodDark)
	box("Walls", -4.2, 0.6, -3.8, 4.2, 6, 3.8, C.Cream)
	box("Roof1", -5.4, 6, -5, 5.4, 7.4, 5, roof)
	box("Roof2", -3.8, 7.4, -3.6, 3.8, 8.6, 3.6, Kit.lerpColor(roof, C.White, 0.2))
	box("Roof3", -2, 8.6, -2, 2, 9.6, 2, roof)
	box("Door", -1.2, 0.6, -3.95, 1.2, 4.4, -3.7, C.Blue, Kit.NOSHADOW)
	box("Window", 2.0, 2.6, -3.95, 3.4, 4.0, -3.7, C.WindowBlue, Kit.DECOR)
	return b:finish(base)
end

-- Red-rock strata (the mesas' colours) for the sea stack.
local STRATA = { U.rgb(226, 110, 72), U.rgb(242, 142, 90), U.rgb(252, 190, 130) }
local CREAM_BAND = U.rgb(255, 226, 170)
local OCHRE = U.rgb(250, 206, 130)

--[[
	A red-rock sea stack (9 parts + a palm): three terracotta strata narrowing upwards, each off
	the centre of the one under it, with a cream band between them (a lip, like the mesas'
	strata), an ochre top with a palm, two boulders at its foot in a ring of foam. cf on the
	water surface; it stands on the sea floor `bed` studs down.
]]
local function seaStack(parent: any, cf: any, bed: number)
	local b = Kit.builder(parent, "SeaStack", cf)
	local base = b:box("Rock1", -11, -bed, -9, 11, 14, 9, STRATA[1])
	b:box("Band1", -11.3, 14, -9.3, 10.4, 17, 8.4, CREAM_BAND)
	b:box("Rock2", -9, 17, -7.5, 8, 30, 7, STRATA[2])
	b:box("Band2", -9.3, 30, -7.8, 7.4, 32.5, 6.4, CREAM_BAND)
	b:box("Rock3", -7.5, 32.5, -6, 5.6, 44, 5.4, STRATA[1])
	b:box("Top", -7.8, 44, -6.3, 5.9, 46, 5.7, OCHRE)
	b:box("BoulderA", 10, -bed, 2, 16, 3.5, 8, STRATA[2])
	b:box("BoulderB", -15, -bed, -8, -9.5, 2.2, -2.6, STRATA[3])
	b:box("Foam", -17, 0.1, -12, 18, 0.3, 12, C.Foam, Kit.DECOR)
	b:finish(base)
	Nature.farTree(b.model, cf * CFrame.new(-1, 46, 0), "palm", 2.2, 57)
	return b.model
end

-- A white-sand atoll (6 parts + three palms): a square ring of sand (two sides a little lower)
-- round a bright turquoise inner pool, in a ring of foam. cf on the water surface.
local function atoll(parent: any, cf: any)
	local b = Kit.builder(parent, "Atoll", cf)
	local sand = U.rgb(255, 246, 220)
	local R, w = 36, 11
	local first = b:box("RingN", -R, -6, R - w, R, 1.6, R, sand)
	b:box("RingS", -R, -6, -R, R, 1.6, -R + w, sand)
	b:box("RingW", -R, -6, -R + w, -R + w, 1.2, R - w, sand)
	b:box("RingE", R - w, -6, -R + w, R, 1.2, R - w, sand)
	b:box("Pool", -R + w, -3, -R + w, R - w, 0.35, R - w, U.rgb(70, 226, 214), Kit.NOSHADOW)
	b:box("Foam", -R - 4, 0.05, -R - 4, R + 4, 0.25, R + 4, C.Foam, Kit.DECOR)
	b:finish(first)
	for i, p in { { -R + w / 2, R - w / 2 - 2, 2.3 }, { R - w / 2, -R + w / 2 + 8, 2.0 }, { R - 20, R - w / 2, 1.8 } } do
		Nature.farTree(b.model, cf * CFrame.new(p[1], if i == 1 then 1.6 else 1.2, p[2]), "palm", p[3], 80 + i)
	end
	return b.model
end

-- Ground CFrame on the islet's square sand rim, on the side facing `towards` degrees: `inset`
-- studs in from the water's edge, `off` studs along that side.
local function rimSpot(world: any, isle: any, towards: number, inset: number, off: number, yaw: number?): any
	local ux, uz = sin(rad(towards)), cos(rad(towards))
	local x, z
	if abs(ux) >= abs(uz) then
		x, z = isle.x + (if ux > 0 then 1 else -1) * (isle.size - inset), isle.z + off
	else
		x, z = isle.x + off, isle.z + (if uz > 0 then 1 else -1) * (isle.size - inset)
	end
	return Kit.ground(world, x, z, yaw)
end

-- A cheap shipwreck (16 parts; it is seen from 200+ studs through the haze): a dark hull with
-- a red band, half sunk and listing in a ring of foam, a stepped bow with a bowsprit, a stern
-- castle, a broken main mast with a torn sail on its yard and a fore mast with a black flag.
-- cf on the water surface, bow = -Z.
local function wreck(parent: any, cf: any)
	local b = Kit.builder(parent, "Shipwreck", cf)
	local hull, hullDark = U.rgb(150, 96, 62), U.rgb(116, 72, 46)
	b:box("FoamA", -9, -0.3, -24, 9, 0.35, -16, C.Foam, Kit.DECOR)
	b:box("FoamB", -10, -0.3, 10, 10, 0.3, 20, C.Foam, Kit.DECOR)
	-- the ship: sunk 2.6 and listed (rolled to starboard, bow up)
	local s = Kit.builder(b.model, "Ship", cf * CFrame.new(0, -2.6, 0) * CFrame.Angles(rad(-5), 0, rad(-9)))
	local keel = s:box("Hull", -6.5, -5, -13, 6.5, 5.5, 22, hull)
	s:box("Band", -6.6, 3.9, -13.1, 6.6, 4.8, 22.1, C.Red, Kit.NOSHADOW)
	s:box("Deck", -5.7, 5.5, -12, 5.7, 6.1, 11, C.WoodLight)
	s:box("Bow1", -4.9, -4, -17, 4.9, 6.1, -12.9, hull)
	s:box("Bow2", -3.1, -2, -20, 3.1, 6.7, -16.9, hullDark)
	s:box("Bowsprit", -0.4, 7.1, -28, 0.4, 7.9, -19.6, C.WoodDark, Kit.NOSHADOW)
	s:box("Castle", -5.7, 5.5, 11, 5.7, 11, 21.6, hull)
	s:box("CastleDeck", -6.0, 11, 10.7, 6.0, 11.6, 22, C.WoodLight)
	s:box("MainMast", -0.8, 5.0, -1.8, 0.8, 19, -0.2, C.WoodDark)
	s:box("Yard", -8, 15.4, -2.4, 8, 16.2, -1.8, C.WoodDark, Kit.NOSHADOW)
	s:box("SailA", -7, 8.5, -2.3, -1.2, 15.4, -2.0, C.Sail, Kit.DECOR)
	s:box("SailB", 1.2, 10.5, -2.3, 6.6, 15.4, -2.0, C.Canvas, Kit.DECOR)
	s:box("ForeMast", -0.6, 5.0, -10.6, 0.6, 23, -9.4, C.WoodDark)
	s:box("Flag", 0.6, 19.6, -10.1, 5.4, 22.6, -9.9, C.Dark, Kit.DECOR)
	return b:finish(keel)
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
			-- the lighthouse on the top terrace, on a stone foundation down to the lower one (no
			-- PointLight: the sun never sets), a little grove of cheap palms beside it
			local cf = isletSpot(world, isle, 0, 0, home)
			local top = cf.Position.Y
			Kit.prop("lighthouse", m, cf, { scale = 1.3, light = false })
			foundation(m, world, cf, 8.7, top - 2.4, C.Stone)
			Nature.farTree(m, isletSpot(world, isle, s * 0.42, home + 70), "palm", 2.2, 11)
			Nature.farTree(m, isletSpot(world, isle, s * 0.62, home + 98), "palm", 2.0, 13)
		elseif i == 3 then
			-- pirate hideout: a red-roofed hut, a black flag and palms
			local hutCf = isletSpot(world, isle, s * 0.15, home + 20, home)
			hut(m, hutCf, C.Red)
			foundation(m, world, hutCf, 4.9, hutCf.Position.Y - 1, C.WoodDark)
			Kit.prop(
				"flagPole",
				m,
				isletSpot(world, isle, s * 0.3, home - 70),
				{ color = C.Dark, stripe = C.White, height = 14 }
			)
			Nature.farTree(m, isletSpot(world, isle, s * 0.5, home + 110), "palm", 2.1, 31)
			Nature.farTree(m, isletSpot(world, isle, s * 0.58, home + 150), "palm", 1.9, 32)
		elseif i == 5 then
			Nature.farTree(m, isletSpot(world, isle, s * 0.2, home + 40), "palm", 2.3, 51)
			Nature.farTree(m, isletSpot(world, isle, s * 0.35, home - 50), "palm", 2.0, 52)
			-- shipwreck lying along the side facing the main island (clear of the square island's
			-- edge), a red-rock sea stack off the corner beside it (the square reaches s / cos 45°
			-- along its diagonals)
			local ux, uz = sin(rad(home)), cos(rad(home))
			local wx, wz, yaw
			if abs(ux) >= abs(uz) then
				wx, wz, yaw = isle.x + (if ux > 0 then 1 else -1) * (s + 16), isle.z + 18, 12
			else
				wx, wz, yaw = isle.x + 18, isle.z + (if uz > 0 then 1 else -1) * (s + 16), 102
			end
			wreck(m, CFrame.new(wx, 0, wz) * CFrame.Angles(0, rad(yaw), 0))
			local sd = s * 1.42 + 22
			local sx, sz = isle.x + sd * sin(rad(home - 45)), isle.z + sd * cos(rad(home - 45))
			seaStack(
				m,
				CFrame.new(sx, 0, sz) * CFrame.Angles(0, rad(home + 10), 0),
				math.max(4, -world:heightAt(sx, sz))
			)
		elseif i == 2 then
			-- a palm grove (cheap far palms: it is seen through the haze) and, on the beach facing
			-- the main island, a beach hut with a red-white parasol beside it
			hut(m, rimSpot(world, isle, home, 14, 12, home), C.Orange, 1.4)
			Kit.prop("parasol", m, rimSpot(world, isle, home, 10, -10), { color = C.Red, scale = 1.6 })
			plant(world, sites, taken, 3, 16, 3, 21, land, farTree("palm", 1.7, 2.2, 21))
		elseif i == 4 then
			-- the big one (far out, mostly seen through the haze, so lean): a palm on the beach and
			-- a pine on the upper terraces
			plant(world, sites, taken, 1, 30, 3, 41, function(site)
				return site.h >= isle.height * 0.5
			end, farTree("pine", 2.2, 2.7, 41))
			plant(world, sites, taken, 1, 26, 3, 42, function(site)
				return site.kind == "sand" or site.h <= 12
			end, farTree("palm", 2.0, 2.3, 42))
		elseif i == 6 then
			-- a cherry grove on the hill and a palm
			plant(world, sites, taken, 3, 24, 3, 61, land, farTree("cherry", 2.1, 2.6, 61))
			plant(world, sites, taken, 1, 20, 3, 62, function(site)
				return site.kind ~= "sand" and site.h <= 12
			end, farTree("palm", 1.8, 2.2, 62))
		end
	end
	-- a white-sand atoll with a turquoise pool out between the lighthouse and the palm grove
	local ap = U.polar(62, 900, 0)
	atoll(ocean, CFrame.new(ap.X, 0, ap.Z) * CFrame.Angles(0, rad(80), 0))
	-- a rock arch (its opening facing the island) and a whale in open water between the coast
	-- and the boundary wall, where they are seen from the outer beaches
	local ra = openSea(cfg, world, 66, 24)
	Kit.prop("rockArch", ocean, onWater(66, ra, 66), { seed = 3 })
	local wa = openSea(cfg, world, 160, 22)
	local whale = bob(Kit.prop("whale", ocean, onWater(160, wa, tangent(160, true)), { seed = 4 }), 0.4, 5.5)
	-- a puff of spray from the blowhole every second or so (particles: no parts)
	local blow = whale:FindFirstChild("SpoutHead") or whale:FindFirstChild("Blowhole")
	if blow then
		U.new("ParticleEmitter", {
			Name = "Spray",
			Rate = 5,
			Lifetime = U.roblox.NumberRange.new(0.9, 1.4),
			Speed = U.roblox.NumberRange.new(9, 13),
			SpreadAngle = U.Vector2.new(14, 14),
			Size = U.roblox.NumberSequence.new({
				U.roblox.NumberSequenceKeypoint.new(0, 1.2),
				U.roblox.NumberSequenceKeypoint.new(1, 2.6),
			}),
			Transparency = U.roblox.NumberSequence.new({
				U.roblox.NumberSequenceKeypoint.new(0, 0.2),
				U.roblox.NumberSequenceKeypoint.new(1, 1),
			}),
			Color = U.roblox.ColorSequence.new(C.White, U.rgb(170, 235, 255)),
			Acceleration = Vector3.new(0, -18, 0),
			LightEmission = 0.2,
			EmissionDirection = U.Enum.NormalId.Top,
		}, blow)
	end
	-- the swim limit: a ring of red and yellow marker buoys (every 15°, ~200 studs apart) just
	-- inside the invisible boundary wall, so swimmers heading for the islets see where the sea
	-- ends (1 part each, bobbing; they keep clear of the arch and the whale)
	local line = U.model(ocean, "BuoyLine")
	local R = cfg.BoundaryRadius - 10
	local keepOff = { U.polar(66, ra, 0), U.polar(160, wa, 0) }
	local count = 24
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
			local buoy = U.model(line, "Buoy")
			local ball = U.part(
				buoy,
				"Float",
				Vector3.new(3.6, 3.6, 3.6),
				CFrame.new(p.X, 0.5, p.Z),
				if k % 2 == 0 then C.Red else C.Yellow,
				nil,
				{ Shape = U.Enum.PartType.Ball, CanCollide = false, CanQuery = false, CastShadow = false }
			)
			buoy.PrimaryPart = ball
			bob(buoy, 0.3, 2.6 + (k % 3) * 0.3)
		end
	end
	-- a big sailboat far out at sea (beyond the wall, seen from the coast and the peaks)
	bob(
		Kit.prop("sailboat", ocean, onWater(302, 960, tangent(302, false)), { seed = 22, scale = 1.6, color = C.Red }),
		0.4,
		5.0
	)
	-- beyond the wall nobody can reach: no collisions, no queries, no shadows
	for _, d in ocean:GetDescendants() do
		if d:IsA("BasePart") then
			local p = d.CFrame.Position
			if math.sqrt(p.X * p.X + p.Z * p.Z) > cfg.BoundaryRadius then
				d.CanCollide = false
				d.CanQuery = false
				d.CastShadow = false
			end
		end
	end
	return ocean
end

--------------------------------------------------------------------------------------------
-- Sky
--------------------------------------------------------------------------------------------

local function buildSky(map: any, cfg: any)
	local sky = U.model(map, "Sky")
	local rng = Kit.rng(2718)
	-- big chunky clouds low over the open ocean (~130-230 studs long, 35-60 tall), one every
	-- 45° with their long side to the island, far enough out to sit on the horizon of every
	-- view out to sea (from the plots, the coast and the peaks alike)
	for k = 0, 7 do
		local a = k * 45 + 14 + rng(-8, 8)
		local p = U.polar(a, if k % 2 == 0 then rng(1020, 1120) else rng(1160, 1260), 0)
		local y = rng(130, 190)
		Kit.prop("cloud", sky, CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, rad(a + rng(-12, 12)), 0), {
			seed = 40 + k,
			scale = rng(4.2, 5.2),
		})
	end
	-- a few high ones over the hills (the lagoon stays clear: the sky above the play area is open)
	local spots = { { 20, 470 }, { 140, 450 }, { 260, 480 } }
	for i, s in spots do
		local p = U.polar(s[1] + rng(-8, 8), s[2], 0)
		local y = rng(230, 300)
		Kit.prop("cloud", sky, CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, rad(rng(-20, 20)), 0), {
			seed = i,
			scale = rng(2.2, 3.0),
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
