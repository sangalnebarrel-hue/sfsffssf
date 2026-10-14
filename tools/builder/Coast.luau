--[[
	Coast — everything on the water and in the sky (World v3, DESIGN.md §6):

	  Map.Lagoon  sailboats, rowboats, a motorboat (Palette boat paint, jewel-tone sail and racing
	              stripes), four red and yellow buoys, lily pads near the promenade shore, a
	              log raft with a parasol, a wooden diving platform on drums, a sandbar island with
	              a palm and a towel and a small one (the coral reefs on the bed and the
	              houseboats, fish farms and rocky islets are Nature's). The water in front of
	              every pier (base-local lz -(PierLength + 16)..0, |lx| <= 26)
	              and along the bridges stays clear (lagoonClear); boats keep out of every pier's
	              whole casting cone (|lx| <= 40, lz -150..0): they sail half-way between piers.
	  Map.Ocean   decorated islets (world.islets, all beyond the boundary wall, seen through the
	              haze, so lean: Nature.farTree palms / pines / cherries at 5 parts a tree): a
	              lighthouse on a stone foundation, a fisherman's hut with a jetty and a dinghy,
	              a palm grove with a beach hut and a red-white parasol, the big island with a
	              ruined stone tower on its summit, a cherry-blossom island, an island with a cheap
	              shipwreck off its shore; a sand atoll round a
	              shallow pool; a rock arch and a rock stack with a red-and-white beacon and a buoy
	              between the coast and the boundary wall, a ring of red / cream marker buoys just
	              inside the wall (the swim limit). The islets'
	              outlines are irregular: every set piece finds its ground (and the shore it faces)
	              by sampling world:surfaceAt along rays from the islet's centre. No animals or
	              figures. Calm, natural colours from Palette.luau (DESIGN.md §1): strong colour only
	              on small accents. Parts beyond the wall neither collide nor cast shadows.
	  Map.Sky     voxel clouds (Props.cloud): a ring of 10 big lite ones (4-5 parts) high over the open ocean
	              (r 1100-1300, y 250-320: one on the horizon of every outward view, softened
	              by the haze); none over the island (seen from below a block cloud is a slab).

	Boats, buoys, the raft and the swim platform carry the attribute Bob (amplitude
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
		local across = abs(x * uz - z * ux)
		if along > cfg.HubPlazaRadius - 10 and across < cfg.BridgeWidth / 2 + 10 + pad then
			return false
		end
	end
	return world:isWater(x, z)
end

local function raft(parent: any, cf: any)
	local b = Kit.builder(parent, "Raft", cf)
	local deck = b:box("Logs", -4, -0.8, -4, 4, 0.5, 4, C.Wood)
	for i, x in { -2.0, 2.0 } do
		b:box(`Log{i}`, x - 1.6, 0.45, -4.2, x + 1.6, 0.75, 4.2, C.WoodLight, Kit.NOSHADOW)
	end
	-- a jewel-blue towel on the logs
	b:box("Towel", -2.6, 0.75, -2.5, 0.2, 0.85, 1.5, C.Flowers[7], Kit.DECOR)
	b:finish(deck)
	Kit.prop("parasol", b.model, cf * CFrame.new(2, 0.75, 1.5), { color = C.Flowers[1] })
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
	-- a striped towel in the sun (jewel blue with a white stripe)
	b:box("Towel", -4.6, 1.6, -2.4, -2.0, 1.78, 2.2, C.Flowers[7], Kit.DECOR)
	b:box("TowelStripe", -4.75, 1.5, -0.4, -1.85, 1.88, 0.3, C.Flowers[5], Kit.DECOR)
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
	b:box("StarA", 3.9, 0.6, 3.8, 6.1, 0.85, 4.4, C.Flowers[6], Kit.DECOR)
	b:box("StarB", 4.7, 0.5, 3.0, 5.3, 0.97, 5.2, C.Flowers[6], Kit.DECOR)
	b:finish(base)
	Nature.farTree(b.model, cf * CFrame.new(0.5, 1.3, 0.5), "palm", 1.5, 71)
	return b.model
end

-- Wooden diving platform (7 parts): a plank deck with a dark rim on two iron drums, a plank
-- tower on one corner with a deck on top and a springboard out over the water.
local function swimPlatform(parent: any, cf: any)
	local b = Kit.builder(parent, "SwimPlatform", cf)
	local deck = b:box("Deck", -6, 0.3, -6, 6, 1.1, 6, C.Plank)
	b:box("Rim", -6.4, -0.3, -6.4, 6.4, 0.5, 6.4, C.WoodDark, Kit.NOSHADOW)
	b:box("FloatA", -5.6, -1.4, -5.6, -3.4, -0.25, 5.6, C.Iron, Kit.NOSHADOW)
	b:box("FloatB", 3.4, -1.4, -5.6, 5.6, -0.25, 5.6, C.Iron, Kit.NOSHADOW)
	b:box("Tower", 2.2, 1.1, 2.2, 5.8, 5.6, 5.8, C.Wood)
	b:box("TowerTop", 1.8, 5.6, 1.8, 6.2, 6.2, 6.2, C.Plank)
	b:box("Springboard", 3.3, 5.75, 6.2, 4.7, 6.1, 12.5, C.WoodLight, Kit.NOSHADOW)
	return b:finish(deck)
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
	-- (hulls in the Palette's boat paint: red, white with a blue sail stripe, teal, green)
	local paint = C.BoatPaint
	local jewel = C.Flowers -- (small accents: sail stripes, buoys, towels, parasols)
	bob(place("sailboat", 45, 226, tangent(45, true), { seed = 1, color = paint[1], stripe = jewel[2] }, 10), 0.35, 4.2)
	bob(
		place("sailboat", 226, 238, tangent(226, false), { seed = 2, color = paint[5], stripe = jewel[7] }, 10),
		0.35,
		4.8
	)
	bob(
		place("motorboat", 133, 202, tangent(133, true), { seed = 3, color = paint[5], stripe = jewel[1] }, 8, 0.3),
		0.3,
		3.4
	)
	bob(place("rowboat", 314, 196, tangent(314, false) + 25, { seed = 4, color = paint[6] }, 6, 0.35), 0.25, 3.0)
	bob(place("rowboat", 128, 270, tangent(128, true) - 20, { seed = 5, color = paint[2] }, 6, 0.35), 0.25, 3.2)
	-- four buoys on a ring between the shores (bobbing faster than the boats): red and yellow
	-- markers by turns
	local colors = { jewel[1], jewel[2] }
	for j = 0, 3 do
		bob(
			place("buoy", j * 90 + 11.25, 214 + (j % 2) * 10, 0, { seed = j * 2, color = colors[j % #colors + 1] }, 2),
			0.3,
			2.4 + (j % 3) * 0.3
		)
	end
	-- lily pads near the promenade shore at the landmark angles
	local n = 0
	for _, a in { 45, 135, 225, 315 } do
		for _, spec in { { -5, 287 }, { 4, 288 } } do
			n += 1
			place("lilyPad", a + spec[1], spec[2], n * 37, { seed = n, scale = 1.5 }, 0)
		end
	end
	-- a floating raft, a swim platform with a slide off the hub beach, a sandbar island with a
	-- palm and a towel and two small sandbars with a palm and a towel
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
	for _, s in { { 318, 252, C.Flowers[1] } } do
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

-- A hut (7 parts, scaled by `s`): a plank floor, plaster walls, a stepped roof, door and window.
local function hut(parent: any, cf: any, roof: any, s: number?)
	local k = s or 1
	local b = Kit.builder(parent, "Hut", cf)
	local function box(name: string, x0, y0, z0, x1, y1, z1, color, extra)
		return b:box(name, x0 * k, y0 * k, z0 * k, x1 * k, y1 * k, z1 * k, color, extra)
	end
	local base = box("Floor", -5, -1, -4.5, 5, 0.6, 4.5, C.WoodDark)
	box("Walls", -4.2, 0.6, -3.8, 4.2, 6, 3.8, C.Plaster)
	box("Roof1", -5.4, 6, -5, 5.4, 7.4, 5, roof)
	box("Roof2", -3.8, 7.4, -3.6, 3.8, 8.6, 3.6, Kit.lerpColor(roof, C.Plaster, 0.2))
	box("Roof3", -2, 8.6, -2, 2, 9.6, 2, roof)
	box("Door", -1.2, 0.6, -3.95, 1.2, 4.4, -3.7, C.WoodDark, Kit.NOSHADOW)
	box("Window", 2.0, 2.6, -3.95, 3.4, 4.0, -3.7, C.WindowBlue, Kit.DECOR)
	return b:finish(base)
end

-- Weathered sandstone strata for the beacon rock (Palette rock tones warmed with sand) and its
-- grassy cap.
local STRATA = {
	Kit.lerpColor(C.RockDark, C.SandDark, 0.3),
	Kit.lerpColor(C.RockMid, C.SandDark, 0.35),
	Kit.lerpColor(C.RockLight, C.Sand, 0.35),
}
local GRASS_TOP = C.GrassTop2

-- A sand atoll (6 parts + a palm): a square ring of sand (two sides a little lower) round
-- a shallow pool (light sea green, calm), in a ring of foam. cf on the water surface.
local SHALLOW = Kit.lerpColor(C.WaterLight, C.Cyan, 0.35)

local function atoll(parent: any, cf: any)
	local b = Kit.builder(parent, "Atoll", cf)
	local sand = Kit.lerpColor(C.Sand, C.Cream, 0.3)
	local R, w = 36, 11
	local first = b:box("RingN", -R, -6, R - w, R, 1.6, R, sand)
	b:box("RingS", -R, -6, -R, R, 1.6, -R + w, sand)
	b:box("RingW", -R, -6, -R + w, -R + w, 1.2, R - w, sand)
	b:box("RingE", R - w, -6, -R + w, R, 1.2, R - w, sand)
	b:box("Pool", -R + w, -3, -R + w, R - w, 0.35, R - w, SHALLOW, Kit.NOSHADOW)
	b:box("Foam", -R - 4, 0.05, -R - 4, R + 4, 0.25, R + 4, C.Foam, Kit.DECOR)
	b:finish(first)
	Nature.farTree(b.model, cf * CFrame.new(-R + w / 2, 1.6, R - w / 2 - 2), "palm", 2.4, 81)
	return b.model
end

-- Radius (from the islet's centre along `angle`) of its outermost dry column: the shore on that
-- side (the outlines are irregular, so it is sampled from the sea inwards).
local function shoreRadius(world: any, isle: any, angle: number): number
	local ux, uz = sin(rad(angle)), cos(rad(angle))
	for r = isle.size * 1.6, 0, -2 do
		local _, _, water = world:surfaceAt(isle.x + r * ux, isle.z + r * uz)
		if not water then
			return r
		end
	end
	return 0
end

-- Ground CFrame on an islet along `angle`, `frac` of the way from its centre to its shore but at
-- least `margin` studs inside the shore (turned by yaw).
local function landSpot(world: any, isle: any, frac: number, angle: number, yaw: number?, margin: number?): any
	local shore = shoreRadius(world, isle, angle)
	local r = math.max(0, math.min(shore * frac, shore - (margin or 6)))
	return Kit.ground(world, isle.x + r * sin(rad(angle)), isle.z + r * cos(rad(angle)), yaw)
end

-- Ground CFrame of the first spot along `angle`, from `inset` studs inside the shore inwards,
-- where a square footprint of half-width `half` (turned by yaw) is one flat column top; nil when
-- there is none on that ray.
local function flatSpot(world: any, isle: any, angle: number, inset: number, half: number, yaw: number?): any
	local ux, uz = sin(rad(angle)), cos(rad(angle))
	for r = shoreRadius(world, isle, angle) - inset, 0, -2 do
		local x, z = isle.x + r * ux, isle.z + r * uz
		local cf = Kit.ground(world, x, z, yaw)
		local h = cf.Position.Y
		local flat = h >= 2
		for _, fx in { -1, 0, 1 } do
			for _, fz in { -1, 0, 1 } do
				local q = cf * Vector3.new(fx * half, 0, fz * half)
				if world:heightAt(q.X, q.Z) ~= h then
					flat = false
				end
			end
		end
		if flat then
			return cf
		end
	end
	return nil
end

-- Is the sea at least `depth` deep (bed at -depth or lower) at every point of the list?
local function openWater(world: any, points: { any }, depth: number): boolean
	for _, q in points do
		if world:heightAt(q.X, q.Z) > -depth then
			return false
		end
	end
	return true
end

-- A cheap shipwreck (16 parts; it is seen from 200+ studs through the haze): a dark hull with
-- a faded red band, half sunk and listing in a ring of foam, a stepped bow with a bowsprit, a stern
-- castle, a broken main mast with a torn sail on its yard and a fore mast with a black flag.
-- cf on the water surface, bow = -Z.
local function wreck(parent: any, cf: any)
	local b = Kit.builder(parent, "Shipwreck", cf)
	local hull, hullDark = C.Bark, C.BarkDark
	b:box("FoamA", -9, -0.3, -24, 9, 0.35, -16, C.Foam, Kit.DECOR)
	b:box("FoamB", -10, -0.3, 10, 10, 0.3, 20, C.Foam, Kit.DECOR)
	-- the ship: sunk 2.6 and listed (rolled to starboard, bow up)
	local s = Kit.builder(b.model, "Ship", cf * CFrame.new(0, -2.6, 0) * CFrame.Angles(rad(-5), 0, rad(-9)))
	local keel = s:box("Hull", -6.5, -5, -13, 6.5, 5.5, 22, hull)
	s:box("Band", -6.6, 3.9, -13.1, 6.6, 4.8, 22.1, C.RoofRed, Kit.NOSHADOW)
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

--[[
	A rock stack with a navigation beacon (10 parts; it replaces the old decorative whale: no
	animals on the map): three weathered strata narrowing upwards on the sea floor, a grassy cap,
	a red-and-white iron beacon with a small glowing lamp, a ring of foam. cf on the water
	surface; the bed `bed` studs down.
]]
local function beaconRock(parent: any, cf: any, bed: number)
	local b = Kit.builder(parent, "BeaconRock", cf)
	local base = b:box("Rock1", -8, -bed, -6.5, 7.5, 3.5, 6, STRATA[1])
	b:box("Rock2", -5.5, 3.3, -4.5, 5, 9, 4.2, STRATA[2])
	b:box("Rock3", -3.6, 8.8, -3.2, 2.6, 12.6, 2.6, STRATA[3])
	b:box("Cap", -3.8, 12.5, -3.4, 2.8, 13.3, 2.8, GRASS_TOP, Kit.NOSHADOW)
	b:box("BeaconFoot", -1.4, 13.2, -1.3, 0.6, 14.4, 0.7, C.Iron)
	b:box("BeaconPole", -0.8, 14.3, -0.7, 0.0, 22.2, 0.1, C.White)
	b:box("BeaconBand", -0.95, 17.0, -0.85, 0.15, 19.2, 0.25, C.RoofRed, Kit.NOSHADOW)
	b:box("BeaconLamp", -1.1, 22.1, -1.0, 0.3, 23.5, 0.4, C.Glow, Kit.NEON)
	b:box("BeaconCap", -1.3, 23.45, -1.2, 0.5, 24.1, 0.6, C.RoofRed, Kit.NOSHADOW)
	b:box("Foam", -11, 0.1, -9.5, 10.5, 0.3, 9, C.Foam, Kit.DECOR)
	return b:finish(base)
end

--[[
	A fisherman's jetty (8 parts) from the beach out over the water: a plank deck on two pairs of
	piles, a bollard at its end and a little dinghy (hull, inner, seat) tied up beside it. cf on
	the shore at the water's edge (y = 0 the sand top), local -Z out to sea.
]]
local function jetty(parent: any, cf: any, sand: number, paint: any)
	local b = Kit.builder(parent, "Jetty", cf)
	local top = 0.7 -- (over the sand; the deck reaches 18 studs out over the water)
	local deck = b:box("Deck", -2.2, top - 0.6, -18, 2.2, top, 5, C.Plank)
	for i, z in { -8, -16.5 } do
		b:box(`Piles{i}`, -2.0, -sand - 4, z - 0.6, 2.0, top - 0.55, z + 0.6, C.WoodDark)
	end
	b:box("Bollard", 1.0, top - 0.05, -17.6, 2.0, top + 1.3, -16.6, C.WoodDark, Kit.NOSHADOW)
	-- the dinghy floats on the water (y = -sand) beside the deck's end
	local w = -sand
	b:box("Dinghy", 3.0, w - 0.6, -17.5, 6.2, w + 0.9, -11.0, paint)
	b:box("DinghyInner", 3.5, w + 0.2, -17.0, 5.7, w + 0.95, -11.5, C.WoodLight, Kit.NOSHADOW)
	b:box("DinghySeat", 3.4, w + 0.5, -14.6, 5.8, w + 1.05, -13.8, C.Wood, Kit.NOSHADOW)
	return b:finish(deck)
end

--[[
	A ruined stone tower (8 parts) on a summit: a plinth, four broken walls of a square keep at
	different heights (the highest with a window gap made by two piers), rubble at its foot, moss
	on the stump. cf on the ground.
]]
local function ruinedTower(parent: any, cf: any)
	local b = Kit.builder(parent, "RuinedTower", cf)
	local wall, dark = C.Stone, C.StoneDark
	local base = b:box("Plinth", -7, -3, -7, 7, 1.5, 7, dark)
	b:box("WallN", -5.5, 1.5, 3.5, 5.5, 22, 5.5, wall)
	b:box("WallE", 3.5, 1.5, -5.5, 5.5, 15, 3.4, Kit.shade(wall, 0.94))
	b:box("WallS", -5.5, 1.5, -5.5, 3.4, 8, -3.5, wall)
	b:box("WallW", -5.5, 1.5, -3.4, -3.5, 12, 3.4, Kit.shade(wall, 0.94))
	b:box("Moss", -5.7, 7.9, -5.7, 0.5, 8.6, -3.3, C.GrassTop2, Kit.NOSHADOW)
	b:box("RubbleA", -10, -1, -9, -6, 2.2, -5.5, dark)
	b:box("RubbleB", 6, -1, -10, 9, 1.6, -7, wall)
	return b:finish(base)
end

local function buildOcean(map: any, cfg: any, world: any)
	local ocean = U.model(map, "Ocean")
	for i, isle in world.islets do
		local m = U.model(ocean, `Islet_{i}`)
		-- the side facing the main island
		local home = math.deg(math.atan2(-isle.x, -isle.z))
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
			-- (the highest column whose footprint nothing rises above: the foundation fills the
			-- steps below it)
			local best = nil
			for _, site in sites do
				if not best or site.h > best.h or (site.h == best.h and site.d < best.d) then
					local ok = true
					for _, d in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 }, { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } } do
						if world:heightAt(site.x + d[1] * 8.7, site.z + d[2] * 8.7) > site.h then
							ok = false
						end
					end
					if ok then
						best = site
					end
				end
			end
			local cf = if best
				then CFrame.new(best.x, best.h, best.z) * CFrame.Angles(0, rad(home), 0)
				else landSpot(world, isle, 0, 0, home)
			local top = cf.Position.Y
			Kit.prop("lighthouse", m, cf, { scale = 1.3, light = false, stripe = C.RoofRed })
			foundation(m, world, cf, 8.7, top - 2.4, C.Stone)
			Nature.farTree(m, landSpot(world, isle, 0.55, home + 70, nil, 8), "palm", 2.3, 11)
		elseif i == 3 then
			-- a fisherman's hut with its door to a jetty on the shore facing the main island, a
			-- dinghy tied up at the jetty's end, palms behind the hut
			local hutCf = landSpot(world, isle, 0.15, home + 20, home + 180, 10)
			hut(m, hutCf, C.RoofRed)
			foundation(m, world, hutCf, 4.9, hutCf.Position.Y - 1, C.WoodDark)
			local shore = shoreRadius(world, isle, home)
			local ux, uz = sin(rad(home)), cos(rad(home))
			local jx, jz = isle.x + (shore + 2) * ux, isle.z + (shore + 2) * uz
			local sand = world:heightAt(isle.x + shore * ux, isle.z + shore * uz)
			jetty(m, CFrame.new(jx, sand, jz) * CFrame.Angles(0, rad(home + 180), 0), sand, C.BoatPaint[2])
			Nature.farTree(m, landSpot(world, isle, 0.6, home + 150, nil, 7), "palm", 2.2, 31)
		elseif i == 5 then
			Nature.farTree(m, landSpot(world, isle, 0.25, home + 40, nil, 8), "palm", 2.3, 51)
			Nature.farTree(m, landSpot(world, isle, 0.4, home - 50, nil, 8), "palm", 2.0, 52)
			-- a shipwreck lying off the shore facing the main island (in open water all along its
			-- hull: pushed out until it is)
			local ux, uz = sin(rad(home)), cos(rad(home))
			local tx, tz = cos(rad(home)), -sin(rad(home)) -- (along the shore)
			local shore = shoreRadius(world, isle, home)
			local wcf = nil
			for out = 18, 60, 4 do
				local cx, cz = isle.x + (shore + out) * ux + 10 * tx, isle.z + (shore + out) * uz + 10 * tz
				local hull = {}
				for _, d in { -26, -13, 0, 13, 24 } do
					for _, side in { -10, 0, 10 } do
						table.insert(hull, Vector3.new(cx + d * tx + side * ux, 0, cz + d * tz + side * uz))
					end
				end
				if openWater(world, hull, 4) then
					wcf = CFrame.new(cx, 0, cz) * CFrame.Angles(0, rad(home + 90 + 12), 0)
					break
				end
			end
			if wcf then
				wreck(m, wcf)
			end
		elseif i == 2 then
			-- a palm grove (cheap far palms: it is seen through the haze) and, on the beach facing
			-- the main island, a beach hut with a red-white parasol beside it
			local hutCf = flatSpot(world, isle, home - 8, 10, 7.5, home + 180)
			if not hutCf then
				-- the flat column nearest the shore facing the main island
				local ux, uz = sin(rad(home)), cos(rad(home))
				local order = table.clone(sites)
				table.sort(order, function(a, b)
					return (a.x - isle.x) * ux + (a.z - isle.z) * uz > (b.x - isle.x) * ux + (b.z - isle.z) * uz
				end)
				for _, site in order do
					local cf = CFrame.new(site.x, site.h, site.z) * CFrame.Angles(0, rad(home + 180), 0)
					local flat = true
					for _, d in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
						local q = cf * Vector3.new(d[1] * 7.5, 0, d[2] * 7.5)
						if world:heightAt(q.X, q.Z) ~= site.h then
							flat = false
						end
					end
					if flat then
						hutCf = cf
						break
					end
				end
			end
			if hutCf then
				hut(m, hutCf, C.RoofTerracotta, 1.4)
				table.insert(taken, { hutCf.Position.X, hutCf.Position.Z })
			end
			Kit.prop("parasol", m, landSpot(world, isle, 1, home + 9, nil, 9), { color = C.Flowers[1], scale = 1.6 })
			plant(world, sites, taken, 2, 15, 3, 21, land, farTree("palm", 2.0, 2.5, 21))
		elseif i == 4 then
			-- the big one (far out, mostly seen through the haze, so lean): a ruined stone tower on
			-- its summit (a silhouette on the horizon), a pine below it and a palm on the beach
			local summit = nil
			for _, site in sites do
				if not summit or site.h > summit.h or (site.h == summit.h and site.d < summit.d) then
					summit = site
				end
			end
			if summit then
				local tcf = CFrame.new(summit.x, summit.h, summit.z) * CFrame.Angles(0, rad(home + 15), 0)
				ruinedTower(m, tcf)
				foundation(m, world, tcf, 7, summit.h - 2.9, C.StoneDark)
				table.insert(taken, { summit.x, summit.z })
			end
			plant(world, sites, taken, 1, 30, 3, 41, function(site)
				return site.h >= isle.height * 0.5
			end, farTree("pine", 2.2, 2.7, 41))
		elseif i == 6 then
			-- a cherry grove on the hill and a palm
			plant(world, sites, taken, 2, 24, 3, 61, land, farTree("cherry", 2.3, 2.7, 61))
			plant(world, sites, taken, 1, 20, 3, 62, function(site)
				return site.kind ~= "sand" and site.h <= 12
			end, farTree("palm", 1.8, 2.2, 62))
		end
	end
	-- a white-sand atoll with a turquoise pool out between the lighthouse and the palm grove
	local ap = U.polar(62, 900, 0)
	atoll(ocean, CFrame.new(ap.X, 0, ap.Z) * CFrame.Angles(0, rad(80), 0))
	-- a rock arch (its opening facing the island) and a rock stack with a navigation beacon and
	-- a bobbing buoy in open water between the coast and the boundary wall, where they are seen
	-- from the outer beaches
	local ra = openSea(cfg, world, 66, 24)
	Kit.prop("rockArch", ocean, onWater(66, ra, 66), { seed = 3 })
	local wa = openSea(cfg, world, 160, 22)
	local wp = U.polar(160, wa, 0)
	beaconRock(ocean, onWater(160, wa, 160 + 25), math.max(4, -world:heightAt(wp.X, wp.Z)))
	bob(Kit.prop("buoy", ocean, onWater(162.2, wa + 6, 0), { seed = 4, color = C.BoatPaint[1] }), 0.3, 2.6)
	-- the swim limit: a ring of red and cream marker buoys (every 22.5°, ~300 studs apart) just
	-- inside the invisible boundary wall, so swimmers heading for the islets see where the sea
	-- ends (1 part each, bobbing; they keep clear of the arch and the beacon rock)
	local line = U.model(ocean, "BuoyLine")
	local R = cfg.BoundaryRadius - 10
	local keepOff = { U.polar(66, ra, 0), U.polar(160, wa, 0) }
	local count = 12
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
				if k % 2 == 0 then C.BoatPaint[1] else C.Cream,
				nil,
				{ Shape = U.Enum.PartType.Ball, CanCollide = false, CanQuery = false, CastShadow = false }
			)
			buoy.PrimaryPart = ball
			bob(buoy, 0.3, 2.6 + (k % 3) * 0.3)
		end
	end
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
	-- big chunky clouds high over the open ocean (~120-210 studs long), one every 36° with their
	-- long side to the island, far out (r 1100-1300) and high (y 250-320), where the haze softens
	-- them into the horizon of every view out to sea; nothing hangs over the play area (seen from
	-- below, a block cloud reads as a slab)
	for k = 0, 9 do
		local a = k * 36 + 14 + rng(-7, 7)
		local p = U.polar(a, if k % 2 == 0 then rng(1100, 1180) else rng(1220, 1300), 0)
		local y = rng(250, 320)
		local cloud = Kit.prop("cloud", sky, CFrame.new(p.X, y, p.Z) * CFrame.Angles(0, rad(a + rng(-12, 12)), 0), {
			seed = 40 + k,
			scale = rng(3.9, 4.9),
			lite = true,
		})
		-- (the ambient wave drifts the clouds slowly round the island: DESIGN.md §3)
		cloud:SetAttribute("Drift", 2)
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
