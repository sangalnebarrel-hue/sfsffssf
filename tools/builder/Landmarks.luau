--[[
	Landmarks — dressing of the four landmark sites of World v3 (world.landmarks, DESIGN.md §5/§6),
	built into Map.Landmarks:

	  Waterfall  a three-tier cascade off the mesa's lagoon-facing cliff (columns of blues, light
	             crests, two mossy sandstone rock shelves) into the pond, a foam slab with a white
	             ring where it lands; solid sandstone stairs right of the fall (two flights along
	             the cliff, cream treads, white posts and red rails, lanterns, vine curtains) up to
	             a bastion in the cliff's strata whose top is the lookout deck (telescope, bench,
	             flag); stepping stones from the end of the path round the pond to the stairs;
	             mossy ledges, vines and grassy boulders on the cliffs; lily pads and reeds. On the
	             mesa top a stream meanders from a spring pool to the lip, and the pool is the way
	             to a destination: a sandstone grotto («РОДНИК») the spring flows out of, a
	             glowing crystal cluster on it, a picnic glade (blossom trees, blankets), a rope
	             swing near the lip, lantern posts along stepping stones.
	  Windmill   a big Props.windmill (spinning "Blades") on the ziggurat top, set low so its
	             plinth is a small step; rainbow tulip rows (green stems + blooms) on the
	             lagoon-facing terraces, walkable stairs up the terraces, a chunky rail fence
	             round the edge of the top meadow (a walkway all round the mill), hay crates and
	             barrels.
	  GiantTree  Props.giantTree (treehouse, swing, lanterns) on the meadow plateau, scaled to a
	             real giant; steps up from the path with grassy cheek blocks filling the plateau's
	             jagged edge beside them; glowing giant mushrooms, a mushroom, torches, a picnic
	             table.
	  Peaks      the main Peak is climbed by the spiral trail VoxelWorld carves into it: a base
	             camp on a flat pad beside the end of its path (tents, campfire, log, flag), a
	             signpost, a «ВЕРШИНА» arch where the trail leaves the path, lantern posts, short
	             red rails over the drops, pennants and a rest bench along it, and a lookout deck
	             flush on the flat snowy summit, open towards the trail's end (big flag, telescope,
	             board, a snowman and a cairn on the snow). Chunky flags on the two smaller peaks.
	             The pines on the slopes come from Nature.

	Every site is registered with Kit.claim so Nature keeps its trees off the dressing.
]]

local U = require("./Util")
local Kit = require("./MapKit")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Enum = U.Enum
local rgb = U.rgb
local C = Kit.C

local rad, deg, sqrt, atan2, floor, max, min, abs =
	math.rad, math.deg, math.sqrt, math.atan2, math.floor, math.max, math.min, math.abs

local Landmarks = {}

local WATER_SHEET = { CanCollide = false, CastShadow = false, CanQuery = false, Transparency = 0.1 }

-- Chunky lantern post standing on cf (3 parts): a light-wood post, a Neon cube, a red cap.
local function lanternPost(parent: any, cf: any, h: number?): any
	local hh = h or 5
	local b = Kit.builder(parent, "Lantern", cf)
	local post = b:box("Post", -0.9, -0.6, -0.9, 0.9, hh, 0.9, C.WoodLight)
	b:box("Lamp", -1.15, hh, -1.15, 1.15, hh + 2.3, 1.15, C.Glow, Kit.NEON)
	b:box("Cap", -1.5, hh + 2.3, -1.5, 1.5, hh + 3, 1.5, C.Red, Kit.NOSHADOW)
	return b:finish(post)
end

-- Pennant on a pole standing on cf (3 parts), flying along local +X.
local function pennant(parent: any, cf: any, color: any, h: number)
	local b = Kit.builder(parent, "Pennant", cf)
	b:pole("Pole", 0.7, 0, 0, -0.5, h, C.White)
	b:box("Cloth", 0.3, h - 3.4, -0.25, 4.6, h - 0.6, 0.25, color, Kit.DECOR)
	b:box("Knob", -0.6, h, -0.6, 0.6, h + 1.2, 0.6, C.Gold, Kit.NEON_DECOR)
	return b:finish()
end

--------------------------------------------------------------------------------------------
-- Waterfall
--------------------------------------------------------------------------------------------

-- The mesa's cliff strata (Ground.luau): 8-stud bands on absolute y in three sandstone shades.
local STRATA = { rgb(232, 178, 112), rgb(214, 150, 92), rgb(246, 206, 150) }
local TREAD = rgb(255, 236, 200) -- cream stair treads on the sandstone
local WATER_FALL = { CanCollide = false, CastShadow = false, CanQuery = false, Transparency = 0.08 }

-- Block from y0 to y1 (absolute y; the builder's frame sits at y = 0) split into the mesa's
-- strata bands, so built rock lines up with the cliff behind it.
local function strataBox(b: any, name: string, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
	local y = y1
	local k = 0
	while y > y0 + 0.01 do
		local band = floor((y - 0.01) / 8)
		local yb = max(y0, band * 8)
		if yb - y0 < 2 then -- no sliver at the bottom
			yb = y0
		end
		k += 1
		b:box(`{name}{k}`, x0, yb, z0, x1, y, z1, STRATA[band % #STRATA + 1])
		y = yb
	end
end

-- Railing on a straight run between two top-of-floor points (site-frame lx, y, lz): white
-- 1.2-stud posts with red caps, a chunky red bar 3 studs up. posts: "both" (default), "last"
-- (the run continues from an existing post) or "none". 1-5 parts.
local function railRun(b: any, name: string, a: any, c: any, posts: string?)
	local which = posts or "both"
	for i, p in { a, c } do
		if which == "none" or (i == 1 and which == "last") then
			continue
		end
		b:box(`{name}Post{i}`, p.X - 0.6, p.Y - 0.5, p.Z - 0.6, p.X + 0.6, p.Y + 3.4, p.Z + 0.6, C.White)
		b:box(`{name}Cap{i}`, p.X - 0.8, p.Y + 3.4, p.Z - 0.8, p.X + 0.8, p.Y + 3.9, p.Z + 0.8, C.Red, Kit.NOSHADOW)
	end
	local u, v = a + Vector3.new(0, 2.9, 0), c + Vector3.new(0, 2.9, 0)
	local d = v - u
	b:block(
		`{name}Bar`,
		Vector3.new(0.9, 0.9, d.Magnitude),
		CFrame.lookAt((u + v) / 2, (u + v) / 2 + d),
		C.Red,
		Kit.NOSHADOW
	)
end

--[[
	The falls (site frame, y absolute): three tiers of falling water — columns of three blues
	with a light crest where each tier tips over an edge — stepping out over two sandstone rock
	shelves (mossy ends) from the lip into the pond; foam on the shelves, a foam slab with a white
	ring and foam pillows where the water lands, mist. fmin / fmax: the jagged cliff face (lz)
	behind the fall, lipLz: where the stream reaches the lip, W: the width of the fall.
]]
local function cascade(parent: any, site: any, frame: any, fmin: number, fmax: number, lipLz: number, W: number)
	local b = Kit.builder(parent, "Waterfall", frame)
	local hw = W / 2
	local top = site.cliffTop + 0.9 -- over the stream sheet
	local blues = { rgb(96, 196, 255), rgb(150, 224, 255), rgb(118, 210, 255) }
	-- the rock shelves: the upper one juts out of the cliff, the lower one stands in the pond
	local s1 = { z0 = -12, z1 = fmax + 1, y0 = 33, y1 = 38.4 }
	local s2 = { z0 = -23, z1 = fmin + 2, y0 = -7, y1 = 19.4 }
	for i, s in { s1, s2 } do
		b:box(`Shelf{i}`, -hw - 3, s.y0, s.z0, hw + 3, s.y1, s.z1, if i == 1 then STRATA[2] else STRATA[1])
		for k, sx in { -1, 1 } do
			local x0, x1 = sx * (hw - 0.5), sx * (hw + 3.4)
			b:box(
				`Moss{i}_{k}`,
				min(x0, x1),
				s.y1 - 0.3,
				s.z0 - 0.4,
				max(x0, x1),
				s.y1 + 0.9,
				s.z1,
				C.Leaf2,
				Kit.NOSHADOW
			)
		end
		-- the water runs over the shelf top to its front edge
		b:box(`ShelfFoam{i}`, -hw + 0.5, s.y1 - 0.2, s.z0 - 0.2, hw - 0.5, s.y1 + 0.5, s.z0 + 9, C.Foam, WATER_FALL)
	end
	-- tiers: top y, bottom y, front lz, back lz (each from the edge above down to the next shelf)
	local tiers = {
		{ top, s1.y1 - 0.3, fmin - 3, lipLz },
		{ s1.y1 + 0.5, s2.y1 - 0.3, s1.z0 - 3, s1.z0 + 0.6 },
		{ s2.y1 + 0.5, -0.6, s2.z0 - 3, s2.z0 + 0.6 },
	}
	for t, tier in tiers do
		local y1, y0, f, k = tier[1], tier[2], tier[3], tier[4]
		for c = 0, 2 do
			local x0 = -hw + c * W / 3
			local fwd = if c == 1 then -0.4 else 0
			b:box(
				`Sheet{t}_{c + 1}`,
				x0,
				y0,
				f + fwd,
				x0 + W / 3,
				y1 + 0.02 * c,
				k,
				Kit.lerpColor(blues[(c + t) % 3 + 1], C.White, (t - 1) * 0.06),
				WATER_FALL
			)
		end
		-- the bright lip where the tier tips over (foam on top, light water on the front)
		b:box(`Crest{t}`, -hw - 0.2, y1 - 2.2, f - 0.7, hw + 0.2, y1 + 0.3, f + 2.6, C.WaterLight, WATER_FALL)
	end
	-- where it lands: a foam slab ringed with white, foam cubes, mist
	local zf = s2.z0 - 3
	local foam = b:box("Splash", -hw - 3, -0.3, zf - 9, hw + 3, 0.4, zf + 2, rgb(200, 240, 255), WATER_FALL)
	b:box("RingFront", -hw - 5, -0.2, zf - 11, hw + 5, 0.7, zf - 9, C.Foam, Kit.DECOR)
	for k, sx in { -1, 1 } do
		local x0, x1 = sx * (hw + 3), sx * (hw + 5)
		b:box(`RingSide{k}`, min(x0, x1), -0.2, zf - 9, max(x0, x1), 0.7, s2.z0 + 4, C.Foam, Kit.DECOR)
	end
	for i, p in { { -0.72, 4.6 }, { -0.22, 3.6 }, { 0.3, 4.2 }, { 0.76, 3.4 } } do
		local x, s = p[1] * hw, p[2]
		local col = if i % 2 == 0 then C.WaterLight else C.Foam
		b:box(`Puff{i}`, x - s / 2, -0.3, zf - 6 - s * 0.4, x + s / 2, s * 0.42, zf - 6 + s * 0.4, col, WATER_FALL)
	end
	U.new("ParticleEmitter", {
		Name = "Mist",
		Rate = 6,
		Lifetime = U.roblox.NumberRange.new(1.6, 2.6),
		Speed = U.roblox.NumberRange.new(2, 5),
		SpreadAngle = U.Vector2.new(50, 50),
		Size = U.roblox.NumberSequence.new({
			U.roblox.NumberSequenceKeypoint.new(0, W * 0.2),
			U.roblox.NumberSequenceKeypoint.new(1, W * 0.4),
		}),
		Transparency = U.roblox.NumberSequence.new({
			U.roblox.NumberSequenceKeypoint.new(0, 0.55),
			U.roblox.NumberSequenceKeypoint.new(1, 1),
		}),
		Color = U.roblox.ColorSequence.new(C.Foam),
		Acceleration = Vector3.new(0, 2, 0),
		LightEmission = 0.1,
		EmissionDirection = Enum.NormalId.Top,
	}, foam)
	return b:finish()
end

--[[
	Stairs up the cliff right of the fall, all solid sandstone (no stilts), in the site frame
	(lz outwards, y absolute): two lanes along the face — the outer flight climbs away from the
	fall to a landing, the inner flight (against the cliff) climbs back to a bastion beside the
	fall whose top is the lookout deck, level with the mesa top. 4-stud cream treads on sandstone
	blocks down to the ground (the bastion in the cliff's strata); an invisible ramp over each
	flight makes the 2.6-stud steps walkable. White posts with red caps and red bars on the open
	sides, lantern posts at the foot and the landing.
	Returns the stair info: bastion lx bx0..bx1, lanes zB0 (front) .. zA1 (into the cliff),
	deck top y, the foot (lx, lz) of the first flight, the far x of the landing.
]]
local function cliffStairs(parent: any, world: any, site: any, frame: any, fmin: number, fmax: number, bx0: number)
	local b = Kit.builder(parent, "CliffStairs", frame)
	local function ground(lx: number, lz: number): number
		local x, z = Kit.radial(site.angle, site.radius, lx, lz)
		return world:heightAt(x, z)
	end
	local function lowest(x0: number, x1: number, z0: number, z1: number): number
		local m = math.huge
		for x = x0, x1, 2 do
			for z = z0, z1, 2 do
				m = min(m, ground(x, z))
			end
		end
		return m
	end
	local bx1 = bx0 + 10
	local zB0, zA0, zA1 = -15, -7.5, fmax + 1
	local n, tread = 9, 4
	local y0 = ground(bx1 + 4, (zB0 + zA0) / 2) + 0.4
	local yTop = site.cliffTop + 0.4
	local rise = (yTop - y0) / (2 * (n + 1))
	local yMid = y0 + (n + 1) * rise
	local xs = bx1 -- the outer flight starts at the bastion ...
	local xe = xs + n * tread -- ... its last step ends here, the landing runs on to xl
	local xl = xe + 8
	local ramp = { Transparency = 1, CastShadow = false, CanQuery = false }
	local function P(x: number, y: number, z: number): any
		return Vector3.new(x, y, z)
	end
	-- a flight of n steps on lane z0..z1 from x = from (going dir) starting at yStart
	local function flight(f: number, z0: number, z1: number, from: number, dir: number, yStart: number)
		for k = 1, n do
			local xa, xb = from + dir * (k - 1) * tread, from + dir * k * tread
			local x0, x1 = min(xa, xb), max(xa, xb)
			local yk = yStart + k * rise
			local shade = if k % 2 == 0 then 1.04 else 1
			b:box(`Block{f}_{k}`, x0, lowest(x0, x1, z0, z1) - 1.5, z0, x1, yk - 0.8, z1, Kit.shade(STRATA[f], shade))
			-- the cream tread overhangs the step's front (and the lane's open side) a little
			local nx0, nx1 = if dir > 0 then x0 - 0.3 else x0, if dir > 0 then x1 else x1 + 0.3
			b:box(`Step{f}_{k}`, nx0, yk - 0.8, z0 - (if f == 1 then 0.3 else 0), nx1, yk, z1, TREAD)
		end
		-- the ramp over the nosings: from the floor one tread before the first step to the top
		local ax = from - dir * tread
		local bxx = from + dir * n * tread
		local yEnd = yStart + (n + 1) * rise
		local run = abs(bxx - ax)
		local slope = math.atan((yEnd - yStart) / run)
		b:block(
			`Ramp{f}`,
			Vector3.new(run / math.cos(slope), 0.4, z1 - z0),
			CFrame.new((ax + bxx) / 2, (yStart + yEnd) / 2 - 0.2, (z0 + z1) / 2) * CFrame.Angles(0, 0, dir * slope),
			C.WoodLight,
			ramp
		)
		return function(x: number): number -- the nosing line
			return yStart + rise + (x - from) * dir / tread * rise
		end
	end
	-- the lower flight (outer lane), and four low steps up to its foot from the yard in front
	-- (it starts at the bastion; an invisible ramp over them), the landing at its far end
	local line1 = flight(1, zB0, zA0, xs, 1, y0)
	local g0 = ground(xs + 2, zB0 - 6)
	local yIn = line1(xs + 1.5) - 0.4
	for k = 1, 4 do
		local z0, z1 = zB0 - 0.3 - (5 - k) * 2.5, zB0 - 0.3 - (4 - k) * 2.5
		b:box(`Entry{k}`, xs, g0 - 1, z0, xs + tread + 1.6, g0 + k * (yIn - g0) / 4, z1, TREAD)
	end
	-- (over the nosings: from the yard one step before the first to the last)
	local zIn, zTop = zB0 - 12.8, zB0 - 2.8
	local mid = Vector3.new(xs + 1.8, (g0 + yIn) / 2 - 0.2, (zIn + zTop) / 2)
	b:block(
		"RampIn",
		Vector3.new(3.4, 0.4, sqrt((zTop - zIn) ^ 2 + (yIn - g0) ^ 2)),
		CFrame.lookAt(mid, mid + Vector3.new(0, yIn - g0, zTop - zIn)),
		C.WoodLight,
		ramp
	)
	local gl = lowest(xe, xl, zB0, zA1)
	b:box("LandingBlock", xe, gl - 1.5, zB0, xl, yMid - 0.8, zA1, STRATA[3])
	b:box("Landing", xe, yMid - 0.8, zB0 - 0.3, xl + 0.3, yMid, zA1, TREAD)
	-- the upper flight (inner lane, back towards the fall)
	local line2 = flight(2, zA0, zA1, xe, -1, yMid)
	-- the bastion: a solid tower in the cliff's strata, the lookout deck on top
	local gb = lowest(bx0, bx1, zB0, zA1)
	strataBox(b, "Bastion", bx0, gb - 1.5, zB0, bx1, yTop - 0.8, zA1)
	b:box("Deck", bx0 - 0.3, yTop - 0.8, zB0 - 0.3, bx1, yTop, zA1, C.WoodLight)
	-- rails: the lower flight's open side (the entry left free at the foot), the landing, the
	-- upper flight's open side (over the lower flight), the deck
	local rx = xs + 2 * tread
	local cA, cB = P(xe - 0.6, yMid, zB0 + 0.4), P(xl - 0.6, yMid, zB0 + 0.4)
	railRun(b, "Rail1", P(rx, line1(rx), zB0 + 0.4), cA)
	railRun(b, "RailL1", cA, cB, "last")
	railRun(b, "RailL2", cB, P(xl - 0.6, yMid, zA1 - 3.6), "last")
	local r2 = xe - 2 * tread
	local cC, cD, cE = P(bx1 - 0.6, yTop, zA0 + 0.6), P(bx0 + 0.6, yTop, zB0 + 0.4), P(bx1 - 0.6, yTop, zB0 + 0.4)
	railRun(b, "Rail2", P(r2, line2(r2), zA0 + 0.6), cC)
	railRun(b, "DeckFront", cD, cE)
	railRun(b, "DeckSide", cD, P(bx0 + 0.6, yTop, fmin - 1), "last")
	railRun(b, "DeckBack", cE, cC, "none")
	-- vine curtains hanging over the open faces of the lower flight and the bastion
	for i, v in { { xs + 2.5 * tread, 7 }, { xs + 5.5 * tread, 10 }, { xs + 7.6 * tread, 6 }, { bx0 + 3, 12 } } do
		local x = v[1]
		local yv = if x < xs then yTop - 0.8 else line1(x) - 0.8
		b:box(
			`Vine{i}`,
			x - 1.3,
			yv - v[2],
			zB0 - 0.7,
			x + 1.3,
			yv,
			zB0 - 0.1,
			if i % 2 == 0 then C.Leaf1 else C.Leaf2,
			Kit.DECOR
		)
	end
	b:finish()
	-- lantern posts at the foot (either side of the way in) and on the landing's far corner
	lanternPost(parent, frame * CFrame.new(xs - 1.5, ground(xs - 1.5, zB0 - 2.2), zB0 - 2.2))
	lanternPost(parent, frame * CFrame.new(rx + 1.2, ground(rx + 1.2, zB0 - 2.2), zB0 - 2.2))
	lanternPost(parent, frame * CFrame.new(xl - 1.5, yMid, zA1 - 1.5))
	return { bx0 = bx0, bx1 = bx1, zB0 = zB0, zA0 = zA0, zA1 = zA1, top = yTop, footX = xs + tread, xl = xl }
end

-- The lookout on the bastion deck: telescope at the front corner by the fall, a bench and a
-- flag, all looking out over the pond and the lagoon.
local function lookout(parent: any, frame: any, st: any)
	local y = st.top
	local b = Kit.builder(parent, "Lookout", frame)
	local tx, tz = st.bx0 + 2.6, st.zB0 + 2.6
	b:box("ScopePost", tx - 0.4, y, tz - 0.4, tx + 0.4, y + 3.4, tz + 0.4, C.Navy)
	b:box("Scope", tx - 1, y + 3.4, tz - 1.8, tx + 1, y + 4.7, tz + 0.9, C.Yellow)
	b:box("ScopeLens", tx - 0.65, y + 3.6, tz - 2.1, tx + 0.65, y + 4.5, tz - 1.75, C.Cyan, Kit.DECOR)
	b:finish()
	Kit.bench(b.model, frame * CFrame.new(st.bx0 + 5.5, y, st.zB0 + 5), { length = 6, color = C.White, legs = C.Red })
	Kit.prop("flagPole", b.model, frame * CFrame.new(st.bx0 + 1.8, y, st.zA0 + 2) * CFrame.Angles(0, rad(90), 0), {
		height = 16,
		color = C.Cyan,
	})
	return b.model
end

--[[
	The mesa top: a spring pool at the head of a stream that meanders to the lip in 8-stud blocks
	between sand banks (no kerbs; foam only at the lip). Pool and stream are water sheets a hair
	above sand slabs, which sit a hair above the grass (>= 0.2 apart, nothing coplanar). The mouth
	is as wide as the fall. Returns the claim circles (lx, lz, r) in the site frame and the pool.
]]
local function mesaStream(parent: any, world: any, site: any, frame: any, lipLz: number, W: number)
	local top = site.cliffTop
	local b = Kit.builder(parent, "Stream", frame)
	local water = rgb(70, 190, 250)
	local deep = rgb(52, 166, 236)
	local sand, sandDark = C.Sand, C.SandDark
	local SAND_TOP, WATER_TOP = top + 0.25, top + 0.5
	-- meander: {lz0, lz1, lx centre, width}
	local segs = {
		{ lipLz - 1.5, lipLz + 9, 0, W - 4 },
		{ lipLz + 9, lipLz + 17, -3, 14 },
		{ lipLz + 17, lipLz + 25, -10, 10 },
		{ lipLz + 25, lipLz + 33, -12, 10 },
		{ lipLz + 33, lipLz + 41, -8, 10 },
		{ lipLz + 41, lipLz + 49, -2, 10 },
		{ lipLz + 49, lipLz + 57, 4, 10 },
	}
	for i, s in segs do
		local x0, x1 = s[3] - s[4] / 2, s[3] + s[4] / 2
		-- the sand bank: wider than the water, and reaching over the joints of the meander
		local bank = if i == 1 then 2 else 3
		local z0 = if i == 1 then s[1] else s[1] - 2
		b:box(`Bank{i}`, x0 - bank, top - 0.6, z0, x1 + bank, SAND_TOP, s[2] + 2, sand, Kit.NOSHADOW)
		b:box(`Water{i}`, x0, top - 0.35, s[1] - (if i == 1 then 0.3 else 0), x1, WATER_TOP, s[2], water, WATER_SHEET)
	end
	-- the spring pool: two overlapping sheets for a rounded voxel outline on a sand rim, a
	-- deeper middle (each sheet >= 0.12 above the one under it)
	local pz0, pz1, px = lipLz + 55, lipLz + 81, 6
	b:box("PoolRim", px - 17, top - 0.6, pz0 - 1, px + 17, SAND_TOP, pz1 + 3, sand, Kit.NOSHADOW)
	b:box("PoolRimB", px - 13, top - 0.8, pz0 - 4, px + 13, SAND_TOP - 0.15, pz1 + 6, sandDark, Kit.NOSHADOW)
	b:box("Pool", px - 14, top - 0.3, pz0 + 2, px + 14, WATER_TOP, pz1, water, WATER_SHEET)
	b:box("PoolB", px - 10.3, top - 0.4, pz0, px + 10.3, WATER_TOP + 0.12, pz1 + 2.4, water, WATER_SHEET)
	b:box("PoolDeep", px - 7, top - 0.2, pz0 + 7, px + 7, WATER_TOP + 0.24, pz1 - 4, deep, WATER_SHEET)
	b:finish()

	local function place(lx: number, lz: number, yaw: number?): any
		return frame * CFrame.new(lx, top, lz) * CFrame.Angles(0, rad(yaw or 0), 0)
	end
	-- cream pebbles on the banks, lily pads (on the deep sheet's level), flowers, a bench
	Kit.prop("rock", parent, place(-20, lipLz + 28), { seed = 11, count = 3, color = C.Cream })
	for i, p in { { px - 6, pz0 + 8 }, { px + 6, pz1 - 7 } } do
		Kit.prop("lilyPad", parent, place(p[1], p[2], i * 40) * CFrame.new(0, WATER_TOP + 0.36 - top, 0), {
			seed = i * 5,
			scale = 1.2,
			flower = true,
		})
	end
	Kit.flowerMeadow(parent, place(-16, lipLz + 44), 21)
	Kit.flowerMeadow(parent, place(px + 22, pz0 + 12), 23)
	Kit.bench(parent, place(px - 20, pz0 + 16, -90), { length = 6 })
	return {
		{ 0, lipLz + 3, 17 },
		{ -6, lipLz + 12, 14 },
		{ -8, lipLz + 34, 15 },
		{ 2, lipLz + 52, 14 },
		{ px - 4, (pz0 + pz1) / 2, 30 },
	}, { x = px, z0 = pz0, z1 = pz1 }
end

--[[
	The mesa top's destination, behind the spring pool and round it: a sandstone grotto the
	spring flows out of (a dark cave mouth, a little spout, a glowing crystal cluster on top), a
	picnic glade on the far bank (blossom trees, two blankets with a basket), a rope swing near the
	lip, stepping stones from the lookout deck to the grotto lit by lantern posts, and stepping
	stones across the stream.
]]
local function mesaGarden(parent: any, world: any, site: any, frame: any, lipLz: number, pool: any, st: any)
	local top = site.cliffTop
	local function place(lx: number, lz: number, yaw: number?): any
		return frame * CFrame.new(lx, top, lz) * CFrame.Angles(0, rad(yaw or 0), 0)
	end
	-- the grotto at the back of the pool
	local g = Kit.builder(parent, "Grotto", frame)
	local px, gz = pool.x, pool.z1 + 4
	local rock = g:box("Rock", px - 15, top - 1, gz, px + 15, top + 8, gz + 12, STRATA[2])
	g:box("Rock2", px - 10, top + 8, gz + 2, px + 12, top + 14, gz + 12, STRATA[1])
	g:box("Moss", px - 15.4, top + 7.6, gz + 7, px - 6, top + 8.8, gz + 12.4, C.Leaf2, Kit.NOSHADOW)
	g:box("Moss2", px + 7, top + 13.6, gz + 6, px + 12.4, top + 14.8, gz + 12.4, C.Leaf2, Kit.NOSHADOW)
	g:box("CaveFrame", px - 5.2, top - 0.5, gz - 0.7, px + 5.2, top + 7.6, gz + 0.2, STRATA[3])
	g:box("Cave", px - 4, top + 0.4, gz - 0.9, px + 4, top + 6.5, gz - 0.5, C.Dark, Kit.DECOR)
	local board = g:box("Board", px - 4.5, top + 8, gz + 1.3, px + 4.5, top + 10.8, gz + 2, C.Cream)
	Kit.sign(board, Enum.NormalId.Front, "РОДНИК", rgb(96, 56, 30), nil, { pps = 30 })
	g:box("VineL", px - 13, top + 1.5, gz - 0.5, px - 10.5, top + 8.2, gz - 0.1, C.Leaf2, Kit.DECOR)
	g:box("VineR", px + 9, top + 3, gz - 0.5, px + 11, top + 8.2, gz - 0.1, C.Leaf1, Kit.DECOR)
	g:box("Spout", px - 2.5, top + 0.3, gz - 4, px + 2.5, top + 1.1, gz + 0.2, C.WaterLight, Kit.DECOR)
	g:box("SpoutFoam", px - 3.5, top + 0.55, gz - 5, px + 3.5, top + 1.5, gz - 3, C.Foam, Kit.DECOR)
	g:finish(rock)
	Kit.prop("crystalCluster", g.model, place(px + 1, gz + 7) * CFrame.new(0, 14, 0), {
		color = "cyan",
		scale = 1.6,
		seed = 4,
		light = true,
	})
	Kit.lights += 1
	-- the picnic glade on the far bank: blossom trees, blankets with a basket
	Kit.prop("cherryTree", parent, place(px - 27, pool.z1 + 2), { seed = 17, scale = 1.25 })
	Kit.prop("cherryTree", parent, place(-31, lipLz + 26), { seed = 23, scale = 1.1 })
	for i, p in { { -27, lipLz + 44, 20, C.Red }, { -30, pool.z0 + 4, -15, C.Blue } } do
		local bl = Kit.builder(parent, "Blanket", place(p[1], p[2], p[3]))
		local cloth = bl:box("Cloth", -3.5, -0.1, -3, 3.5, 0.25, 3, p[4], Kit.NOSHADOW)
		bl:box("Stripe", -3.5, -0.08, -0.7, 3.5, 0.3, 0.7, C.White, Kit.DECOR)
		bl:box("Basket", 1.2, 0.25, 0.8, 3, 1.6, 2.2, C.WoodLight)
		bl:box("Handle", 1.95, 1.6, 0.9, 2.25, 2.4, 2.1, C.Wood, Kit.DECOR)
		bl:finish(cloth)
	end
	-- a rope swing on an A-frame near the lip, left of the fall
	local sw = Kit.builder(parent, "Swing", place(-30, lipLz + 4))
	local post = sw:box("PostL", -5.2, -0.5, -0.6, -4, 11, 0.6, C.WoodLight)
	sw:box("PostR", 4, -0.5, -0.6, 5.2, 11, 0.6, C.WoodLight)
	sw:box("Bar", -5.8, 11, -0.8, 5.8, 12.2, 0.8, C.Red)
	sw:box("RopeL", -1.6, 3, -0.12, -1.35, 11, 0.12, C.Rope, Kit.DECOR)
	sw:box("RopeR", 1.35, 3, -0.12, 1.6, 11, 0.12, C.Rope, Kit.DECOR)
	sw:box("Seat", -2, 2.6, -0.8, 2, 3.1, 0.8, C.Yellow)
	sw:finish(post)
	-- stepping stones from the lookout deck to the grotto (lantern posts along them) and across
	-- the stream to the glade
	local stones = {
		{ st.bx0 + 4, st.zA1 + 4 },
		{ 22, lipLz + 12 },
		{ 20, lipLz + 21 },
		{ 18, lipLz + 30 },
		{ 19, lipLz + 39 },
		{ 7, lipLz + 32 },
		{ 23, pool.z0 - 2 },
		{ 25, pool.z0 + 8 },
		{ 26, pool.z0 + 18 },
		{ 22, pool.z1 + 1 },
		{ -3, lipLz + 33 },
		{ -10, lipLz + 36 },
		{ -16, lipLz + 33 },
	}
	local sb = Kit.builder(parent, "SteppingStones", frame)
	for i, p in stones do
		local s = if i >= 11 then 3.4 else 4.4
		local y = if i >= 11 then top + 0.95 else top + 0.35
		sb:box(
			`Stone{i}`,
			p[1] - s / 2,
			top - 0.4,
			p[2] - s / 2,
			p[1] + s / 2,
			y,
			p[2] + s / 2,
			if i % 2 == 0 then C.StoneLight else C.Cream,
			Kit.NOSHADOW
		)
	end
	sb:finish()
	for _, p in { { 25.5, lipLz + 17 }, { 29.5, pool.z0 + 13 } } do
		lanternPost(parent, place(p[1], p[2]))
	end
end

--[[
	Moss and vines on the mesa's cliffs: finds the vertical faces of the voxel columns (a column
	of the top or the side ledge whose neighbour on the lagoon side is much lower) and hangs
	leafy vine curtains (two greens, a lighter tuft) from their top edge, flush with the face.
	Skips the fall and the staircase (skip).
]]
local function mesaVines(parent: any, world: any, site: any, skip: (number, number) -> boolean, count: number)
	local model = U.model(parent, "Vines")
	local cell = world.cell
	local r = Kit.rng(4501)
	local towards = Vector3.new(-site.x, 0, -site.z).Unit -- the lagoon direction
	local faces = {}
	local half = site.halfWidth + 8
	local R = site.radius
	-- scan the cells of the mesa footprint
	local x0, x1 = floor((site.x - half - 160) / cell), floor((site.x + half + 160) / cell)
	local z0, z1 = floor((site.z - half - 160) / cell), floor((site.z + half + 160) / cell)
	for iz = z0, z1 do
		for ix = x0, x1 do
			local cx, cz = (ix + 0.5) * cell, (iz + 0.5) * cell
			local lx, lz = world.radialLocal(cx, cz, site.angle, R)
			if lz >= -4 and lz <= site.depth + 4 and abs(lx) <= half then
				local top = world:heightAt(cx, cz)
				if top >= site.cliffTop - 16 then
					for _, n in { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } } do
						local nx, nz = cx + n[1] * cell, cz + n[2] * cell
						local drop = top - world:heightAt(nx, nz)
						local facing = n[1] * towards.X + n[2] * towards.Z
						if drop >= 12 and facing > 0.5 and not skip(lx, lz) then
							table.insert(faces, { cx = cx, cz = cz, nx = n[1], nz = n[2], top = top, drop = drop })
						end
					end
				end
			end
		end
	end
	-- deterministic pick: every face gets a score, the best ones get vines
	for _, f in faces do
		f.score = r()
	end
	table.sort(faces, function(a, b)
		return a.score > b.score
	end)
	local vines = 0
	for _, f in faces do
		if vines >= count then
			break
		end
		-- the face plane and its tangent direction
		local fx, fz = f.cx + f.nx * cell / 2, f.cz + f.nz * cell / 2
		local tx, tz = f.nz, f.nx -- along the face (axis-aligned)
		local w = floor(r(3, 5.99)) + 0.5
		local off = r(-(cell / 2 - w / 2 - 0.3), cell / 2 - w / 2 - 0.3)
		local len = min(f.drop - 3, r(9, 20))
		local cxv, czv = fx + tx * off + f.nx * 0.35, fz + tz * off + f.nz * 0.35
		local sizeX = if tx ~= 0 then w else 0.9
		local sizeZ = if tz ~= 0 then w else 0.9
		vines += 1
		U.part(
			model,
			"Vine",
			Vector3.new(sizeX, len, sizeZ),
			CFrame.new(cxv, f.top - len / 2 + 0.25, czv),
			if vines % 2 == 0 then C.Leaf1 else C.Leaf2,
			nil,
			Kit.DECOR
		)
		-- a shorter, lighter tuft beside some vines (the voxel "shading" of hanging leaves)
		if vines % 2 == 0 then
			local o2 = off + (if off > 0 then -w / 2 - 1 else w / 2 + 1)
			local cx2, cz2 = fx + tx * o2 + f.nx * 0.3, fz + tz * o2 + f.nz * 0.3
			U.part(
				model,
				"Tuft",
				Vector3.new(if tx ~= 0 then 2 else 0.8, len * 0.45, if tz ~= 0 then 2 else 0.8),
				CFrame.new(cx2, f.top - len * 0.225 + 0.2, cz2),
				C.Leaf3,
				nil,
				Kit.DECOR
			)
		end
	end
	return model
end

-- Mossy ledges jutting out of the cliff face (site frame, y absolute): a sandstone lip in the
-- cliff's stratum with a grass top. 2 parts each.
local function cliffLedges(parent: any, frame: any, faceRange: (number, number) -> (number, number), specs: { any })
	local b = Kit.builder(parent, "Ledges", frame)
	for i, s in specs do
		local lx, y, w = s[1], s[2], s[3]
		local fmin, fmax = faceRange(lx - w / 2, lx + w / 2)
		local z0 = fmin - 4
		b:box(`Ledge{i}`, lx - w / 2, y - 2.4, z0, lx + w / 2, y, fmax + 1, STRATA[floor(y / 8) % 3 + 1])
		b:box(`Grass{i}`, lx - w / 2 + 0.4, y - 0.4, z0 + 0.5, lx + w / 2 - 0.4, y + 1, fmax + 1, C.Leaf2, Kit.NOSHADOW)
	end
	return b:finish()
end

-- Chunky boulder (2 parts): a light stone block with a grass cap, standing on cf.
local function boulder2(parent: any, cf: any, w: number, d: number, h: number)
	local b = Kit.builder(parent, "Boulder", cf)
	local stone = b:box("Stone", -w / 2, -1, -d / 2, w / 2, h, d / 2, C.StoneLight)
	b:box("Cap", -w / 2 + 0.6, h, -d / 2 + 0.6, w / 2 - 0.6, h + 1.2, d / 2 - 0.6, C.GrassTop)
	return b:finish(stone)
end

local function buildWaterfall(root: any, cfg: any, world: any, site: any)
	local model = U.model(root, "Waterfall")
	local frame = Kit.radialCFrame(site.angle, site.radius, 0, 0, 0)
	local function W(lx: number, lz: number): (number, number)
		return Kit.radial(site.angle, site.radius, lx, lz)
	end
	-- the cliff face (the jagged voxel edge): first lz where the mesa top begins, per lx
	local function faceAt(lx: number): number
		for lz = -20, 30, 0.5 do
			local x, z = W(lx, lz)
			if world:heightAt(x, z) >= site.cliffTop - 16 then -- the top or the side ledge
				return lz
			end
		end
		return 0
	end
	local function faceRange(a: number, b: number): (number, number)
		local lo, hi = math.huge, -math.huge
		for lx = a, b, 1 do
			local f = faceAt(lx)
			lo, hi = min(lo, f), max(hi, f)
		end
		return lo, hi
	end
	local FALL_W = 30

	-- the falls: from the lip (a little behind the edge) down two rock shelves into the pond
	local fmin, fmax = faceRange(-FALL_W / 2 - 3, FALL_W / 2 + 3)
	local lipLz = fmax + 1.5
	cascade(model, site, frame, fmin, fmax, lipLz, FALL_W)
	-- the mesa top: spring pool and meandering stream
	local streamClaims, pool = mesaStream(model, world, site, frame, lipLz, FALL_W)

	-- the pond yard: lily pads and reeds in the pond, boulders at the cliff foot
	local pondCF = CFrame.new(site.pondX, 0, site.pondZ) * CFrame.Angles(0, rad(site.angle), 0)
	for i, p in { { -18, -6 }, { -9, -19 }, { 16, -12 } } do
		Kit.prop("lilyPad", model, pondCF * CFrame.new(p[1], 0, p[2]), { seed = i * 3, scale = 1.4 })
	end
	for i, a in { 205, 150 } do
		local r = site.pondRadius - 2
		local x = site.pondX + r * math.sin(rad(a + site.angle))
		local z = site.pondZ + r * math.cos(rad(a + site.angle))
		Kit.prop("reeds", model, CFrame.new(x, 0, z), { seed = i, scale = 1.3 })
	end
	for i, p in
		{ { -24, 8, 7, 6, 1 }, { -36, 10, 8, 9, 1 }, { -48, 7, 6, 5, 1 }, { -31, 6, 5, 4, 8 }, { 54, 7, 6, 4, 22 } }
	do
		local lx = p[1]
		local f = if i == 5 then 0 else faceRange(lx - p[2] / 2, lx + p[2] / 2)
		local x, z = W(lx, f - p[3] / 2 - p[5])
		boulder2(model, Kit.ground(world, x, z, site.angle + i * 7), p[2], p[3], p[4])
	end

	-- solid stairs up the cliff right of the fall; the bastion at their top is the lookout
	local _, stairFace = faceRange(FALL_W / 2 + 4, 80)
	local st = cliffStairs(model, world, site, frame, fmin, stairFace, FALL_W / 2 + 5)
	lookout(model, frame, st)
	-- stepping stones from the end of the path round the pond to the foot of the stairs
	local stones = Kit.builder(model, "Stones", CFrame.new())
	local pr = site.pondRadius + 10
	local k = 0
	for a = 16, 116, 12.5 do
		local lx = pr * math.sin(rad(a))
		local lz = site.pondR - site.radius - pr * math.cos(rad(a))
		local x, z = W(lx, lz)
		local g = world:heightAt(x, z)
		k += 1
		stones:block(
			`Stone{k}`,
			Vector3.new(4.6, 1, 3.8),
			CFrame.new(x, g - 0.15, z) * CFrame.Angles(0, rad(site.angle - a), 0),
			if k % 2 == 0 then C.StoneLight else C.Cream,
			Kit.NOSHADOW
		)
	end
	stones:finish()
	local sx, sz = W(10, site.pondR - site.radius - site.pondRadius - 4)
	Kit.prop("signpost", model, Kit.ground(world, sx, sz, site.angle), {
		text = "СМОТРОВАЯ",
		width = 10,
		color = C.Cream,
		trim = C.Red,
		arrow = "left",
	})

	-- the mesa top's destination
	mesaGarden(model, world, site, frame, lipLz, pool, st)

	-- mossy ledges and vine curtains on the cliffs (not behind the fall or the staircase)
	cliffLedges(model, frame, faceRange, {
		{ -30, 46, 10 },
		{ -44, 30, 8 },
		{ -26, 22, 9 },
		{ -50, 14, 6 },
		{ -38, 38, 6 },
	})
	mesaVines(model, world, site, function(lx: number, lz: number): boolean
		return (abs(lx) < FALL_W / 2 + 6 and lz < 24) or (lx > st.bx0 - 6 and lx < st.xl + 10 and lz < 24)
	end, 10)

	-- claims: the stream and pool, the garden, the stairs (the pond yard is reserved already)
	for _, c in streamClaims do
		local cx, cz = W(c[1], c[2])
		Kit.claim(cx, cz, c[3])
	end
	for _, c in { { -28, lipLz + 30, 16 }, { pool.x, pool.z1 + 10, 18 }, { -30, lipLz + 4, 8 } } do
		local cx, cz = W(c[1], c[2])
		Kit.claim(cx, cz, c[3])
	end
	for x = st.bx0, st.xl, 12 do
		local qx, qz = W(x + 4, -6)
		Kit.claim(qx, qz, 14)
	end
end

--------------------------------------------------------------------------------------------
-- Windmill
--------------------------------------------------------------------------------------------

-- Rainbow tulip rows on the lagoon-facing terraces: per row of 8-stud cells, runs of equal
-- height merge into one strip of green stems with a strip of blooms on top (a green line under
-- every colour band, so the rows read as flowers, not tiles); the terrace colour cycles through
-- a warm rainbow and the grass shows between the rows.
local function tulipTerraces(parent: any, world: any, site: any, corridor: (number, number) -> boolean)
	local model = U.model(parent, "TulipFields")
	local cell = world.cell
	local palette = { C.Red, C.Orange, C.Yellow, C.Pink, C.Purple, rgb(255, 72, 140), C.Blue, rgb(255, 120, 60) }
	local towards = Vector3.new(-site.x, 0, -site.z).Unit -- the lagoon direction
	local R = site.hillRadius
	local ix0, ix1 = floor((site.x - R) / cell), floor((site.x + R) / cell)
	local iz0, iz1 = floor((site.z - R) / cell), floor((site.z + R) / cell)
	local count = 0
	local function eligible(ix: number, iz: number): number?
		local x, z = (ix + 0.5) * cell, (iz + 0.5) * cell
		local dx, dz = x - site.x, z - site.z
		local d = sqrt(dx * dx + dz * dz)
		if d < site.topRadius + 5 or d > R - 6 then
			return nil
		end
		local facing = (dx * towards.X + dz * towards.Z) / d
		if facing < 0.45 or corridor(x, z) then
			return nil
		end
		return world:heightAt(x, z)
	end
	for iz = iz0, iz1 do
		local ix = ix0
		while ix <= ix1 do
			local h = eligible(ix, iz)
			if h then
				local j = ix
				while j + 1 <= ix1 and eligible(j + 1, iz) == h do
					j += 1
				end
				local level = floor((h - 4) / 4)
				local colour = palette[level % #palette + 1]
				local x0, x1 = ix * cell + 0.9, (j + 1) * cell - 0.9
				local z0, z1 = iz * cell + 1.4, (iz + 1) * cell - 1.4
				U.part(
					model,
					"Stems",
					Vector3.new(x1 - x0 - 0.6, 1.4, z1 - z0 - 0.6),
					CFrame.new((x0 + x1) / 2, h + 0.5, (z0 + z1) / 2),
					C.Leaf1,
					nil,
					Kit.DECOR
				)
				U.part(
					model,
					"Tulips",
					Vector3.new(x1 - x0, 1.6, z1 - z0),
					CFrame.new((x0 + x1) / 2, h + 1.95, (z0 + z1) / 2),
					colour,
					nil,
					Kit.DECOR
				)
				count += 1
				ix = j + 1
			else
				ix += 1
			end
		end
	end
	return count
end

-- Chunky rail fence (posts + one thick rail per segment) along a polyline of ground points.
local function railFence(parent: any, points: { any }, name: string)
	local model = U.model(parent, name)
	for i, p in points do
		U.part(model, `Post{i}`, Vector3.new(1.3, 3.6, 1.3), CFrame.new(p + Vector3.new(0, 1.6, 0)), C.WoodDark)
		U.part(
			model,
			`Cap{i}`,
			Vector3.new(1.6, 0.5, 1.6),
			CFrame.new(p + Vector3.new(0, 3.6, 0)),
			C.Red,
			nil,
			Kit.NOSHADOW
		)
		local q = points[i + 1]
		if q then
			local mid = (p + q) / 2 + Vector3.new(0, 2.4, 0)
			local d = q - p
			U.part(
				model,
				`Rail{i}`,
				Vector3.new(0.7, 0.8, Vector3.new(d.X, 0, d.Z).Magnitude),
				CFrame.lookAt(mid, mid + Vector3.new(d.X, 0, d.Z)),
				C.Wood,
				nil,
				Kit.NOSHADOW
			)
		end
	end
	return model
end

local function buildWindmill(root: any, cfg: any, world: any, site: any)
	local model = U.model(root, "Windmill")
	local topY = world:heightAt(site.x, site.z)
	-- the stair corridor: along the radial line towards the lagoon
	local ux, uz = site.x / sqrt(site.x ^ 2 + site.z ^ 2), site.z / sqrt(site.x ^ 2 + site.z ^ 2)
	local function corridor(x: number, z: number): boolean
		local dx, dz = x - site.x, z - site.z
		local along = -(dx * ux + dz * uz) -- towards the lagoon
		local side = abs(dx * uz - dz * ux)
		return along > 0 and side < 10
	end
	-- the mill stands 1.8 studs low: its stone plinth (2.4 high at scale 1.6) is a 0.6 step,
	-- and the door sits just above the meadow
	local mill = Kit.prop("windmill", model, Kit.facing(site.x, topY - 1.8, site.z, 0, 0), {
		scale = 1.6,
		spin = 20,
		roof = C.Red,
		name = "Windmill",
	})
	mill.Name = "Windmill"
	tulipTerraces(model, world, site, corridor)
	-- stairs from the hill foot up to the top meadow (Kit.stairs adds a first step if needed)
	local foot = Vector3.new(site.x - ux * (site.hillRadius + 4), 0, site.z - uz * (site.hillRadius + 4))
	local summit = Vector3.new(site.x - ux * (site.topRadius - 2), 0, site.z - uz * (site.topRadius - 2))
	Kit.stairs(
		model,
		world,
		foot,
		summit,
		{ width = 8, color = rgb(255, 236, 204), color2 = rgb(250, 222, 184), name = "Stairs" }
	)
	local lagoonA = deg(atan2(-site.x, -site.z))
	local function onTop(r: number, a: number): any
		local aa = rad(lagoonA + a)
		local px, pz = site.x + r * math.sin(aa), site.z + r * math.cos(aa)
		return CFrame.new(px, topY, pz) * CFrame.Angles(0, aa, 0)
	end
	-- a rail fence round the edge of the top meadow (radius 19.5: a walkway all round the
	-- mill's plinth), open where the stairs arrive, broken wherever the jagged voxel edge of the
	-- top would leave a post hanging in the air
	local run = {}
	local fences = 0
	local function flush()
		if #run >= 2 then
			fences += 1
			railFence(model, run, `Fence{fences}`)
		end
		run = {}
	end
	local gapHalf, posts = 15, 14
	for k = 0, posts do
		local a = gapHalf + k * (360 - 2 * gapHalf) / posts
		local p = onTop(19.5, a).Position
		local inner = onTop(18, a).Position
		if world:heightAt(p.X, p.Z) == topY and world:heightAt(inner.X, inner.Z) == topY then
			table.insert(run, p)
		else
			flush()
		end
	end
	flush()
	-- hay crates and barrels behind the mill (clear of the walkway)
	Kit.prop("crate", model, onTop(16, 150), { color = C.Yellow, size = 3.4 })
	Kit.prop("crate", model, onTop(16.4, 163), { size = 2.6 })
	Kit.prop("barrel", model, onTop(16, -150), {})
	Kit.prop("barrel", model, onTop(16, -162), { color = C.Red })
	Kit.claim(site.x, site.z, site.hillRadius - 2)
	return mill
end

--------------------------------------------------------------------------------------------
-- Giant tree
--------------------------------------------------------------------------------------------

-- Height of a model's highest part top above y0 (its parts are upright blocks).
local function heightAbove(m: any, y0: number): number
	local top = y0
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			top = max(top, d.CFrame.Position.Y + d.Size.Y / 2)
		end
	end
	return top - y0
end

-- The giant tree's crown should top out about this high over the meadow: a real giant next to
-- the ~30-stud oaks round it (the hub's balloon flies at ~100), its treehouse up in the canopy.
local GIANT_TREE_HEIGHT = 104

local function buildGiantTree(root: any, cfg: any, world: any, site: any)
	local model = U.model(root, "GiantTree")
	local topY = world:heightAt(site.x, site.z)
	local lagoonA = deg(atan2(-site.x, -site.z))
	local function at(r: number, a: number, yaw: number?): any
		local aa = rad(lagoonA + a)
		local px, pz = site.x + r * math.sin(aa), site.z + r * math.cos(aa)
		return CFrame.new(px, world:heightAt(px, pz), pz) * CFrame.Angles(0, aa + rad(yaw or 0), 0)
	end
	-- the tree faces the lagoon (ladder and swing towards the path); scaled up to the giant
	-- height whatever the prop's own proportions are
	local treeCF = Kit.facing(site.x, topY, site.z, 0, 0)
	local opts = { scale = 1.25, roof = C.Blue, name = "Tree" }
	local tree = Kit.prop("giantTree", model, treeCF, opts)
	local h = heightAbove(tree, topY)
	if h < GIANT_TREE_HEIGHT * 0.92 then
		tree:Destroy()
		opts.scale = 1.25 * GIANT_TREE_HEIGHT / h
		Kit.prop("giantTree", model, treeCF, opts)
	end
	-- steps up from the path onto the plateau
	local ux, uz = site.x / site.radius, site.z / site.radius
	local a = Vector3.new(site.x - ux * (site.plateauRadius + 12), 0, site.z - uz * (site.plateauRadius + 12))
	local b = Vector3.new(site.x - ux * (site.plateauRadius - 8), 0, site.z - uz * (site.plateauRadius - 8))
	Kit.stairs(model, world, a, b, { width = 12, color = C.WoodLight, color2 = C.Wood, name = "Steps" })
	-- cheek blocks either side of the top of the steps: the plateau's jagged voxel edge leaves
	-- notches (cells one step down) beside the 45-degree steps; two grassy blocks in the steps'
	-- frame fill them almost level with the meadow without touching the steps
	local cheeks = Kit.builder(model, "Landing", Kit.facing(b.X, 0, b.Z, a.X, a.Z))
	local along = (a - b).Magnitude -- the steps run from local z = 0 (top) to z = -along
	for i, sx in { -1, 1 } do
		local x0, x1 = sx * 6.05, sx * 13
		local lo = math.huge
		for _, p in { { x0, -2 }, { x1, -2 }, { x0, -along + 8 }, { x1, -along + 8 } } do
			local w = (cheeks.cf * CFrame.new(p[1], 0, p[2])).Position
			lo = min(lo, world:heightAt(w.X, w.Z))
		end
		cheeks:box(`Cheek{i}`, min(x0, x1), lo - 1, -along + 8, max(x0, x1), topY - 1.4, 0, rgb(206, 148, 88))
		cheeks:box(`CheekTop{i}`, min(x0, x1), topY - 1.4, -along + 8, max(x0, x1), topY - 0.4, 0, rgb(170, 240, 96))
	end
	cheeks:finish()
	-- glowing giant mushrooms round the tree, a fairy ring of small ones
	for i, spec in { { 35, 62, true }, { 32, -70, true } } do
		Kit.prop("giantMushroom", model, at(spec[1], spec[2]), {
			glow = true,
			light = spec[3],
			seed = i,
			scale = 1.1,
		})
		if spec[3] then
			Kit.lights += 1
		end
	end
	Kit.prop("mushroom", model, at(24, -140), { seed = 5, scale = 1.5 })
	-- torches lining the way in, a picnic table, flowers, a stump
	for i, spec in { { 40, -13 }, { 40, 13 } } do
		Kit.prop("torch", model, at(spec[1], spec[2]), { seed = i, height = 5 })
	end
	Kit.prop("picnicTable", model, at(26, 105, 90), { cloth = C.Pink })
	Kit.flowerMeadow(model, at(36, -40), 3)
	Kit.prop("stump", model, at(34, -110), { seed = 9, axe = true })
	Kit.claim(site.x, site.z, site.plateauRadius + 2)
end

--------------------------------------------------------------------------------------------
-- Peaks
--------------------------------------------------------------------------------------------

-- Centre and height of the highest flat top within `radius` of (x, z) (the summit block).
local function summit(world: any, x: number, z: number, radius: number): (number, number, number)
	local by = -math.huge
	for dz = -radius, radius, 2 do
		for dx = -radius, radius, 2 do
			by = max(by, world:heightAt(x + dx, z + dz))
		end
	end
	local sx, sz, n = 0, 0, 0
	for dz = -radius, radius, 2 do
		for dx = -radius, radius, 2 do
			if world:heightAt(x + dx, z + dz) == by then
				sx, sz, n = sx + x + dx, sz + z + dz, n + 1
			end
		end
	end
	return sx / n, sz / n, by
end

local function tent(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Tent", cf)
	local base = b:box("Floor", -3.4, -0.2, -3.6, 3.4, 0.25, 3.6, C.WoodDark)
	b:box("Low", -3.2, 0.25, -3.4, 3.2, 2.4, 3.4, color)
	b:box("Mid", -2.2, 2.4, -3.4, 2.2, 4.0, 3.4, Kit.lerpColor(color, C.White, 0.2))
	b:box("Top", -1.1, 4.0, -3.4, 1.1, 5.2, 3.4, color)
	b:box("Door", -1.2, 0.25, -3.55, 1.2, 3.0, -3.3, C.Dark, Kit.DECOR)
	return b:finish(base)
end

-- Big chunky flag on a 2-stud pole (front = -Z, the flag flies along local +X). 6 parts.
local function bigFlag(parent: any, cf: any, h: number, w: number, fh: number, color: any)
	local b = Kit.builder(parent, "Flag", cf)
	local foot = b:box("Foot", -1.8, -0.6, -1.8, 1.8, 0.8, 1.8, C.StoneLight)
	b:pole("Pole", 1.8, 0, 0, 0.8, h, C.White)
	b:box("Top", -1.3, h, -1.3, 1.3, h + 2.2, 1.3, C.Gold, Kit.NEON_DECOR)
	b:box("Cloth", 0.9, h - fh - 0.4, -0.3, 0.9 + w, h - 0.4, 0.3, color, Kit.DECOR)
	b:box("Stripe", 1.0, h - fh * 0.62 - 0.4, -0.42, 0.8 + w, h - fh * 0.38 - 0.4, 0.42, C.White, Kit.DECOR)
	b:box("Tail", 0.9 + w, h - fh * 0.8 - 0.4, -0.3, 2.6 + w, h - fh * 0.2 - 0.4, 0.3, color, Kit.DECOR)
	return b:finish(foot)
end

-- Little stone cairn: three stacked stones. 3 parts.
local function cairn(parent: any, cf: any, s: number)
	local b = Kit.builder(parent, "Cairn", cf)
	local base = b:box("Stone1", -1.8 * s, -0.3, -1.5 * s, 1.8 * s, 1.6 * s, 1.5 * s, C.Stone)
	b:box("Stone2", -1.2 * s, 1.6 * s, -1.1 * s, 1.3 * s, 3.0 * s, 1.0 * s, C.StoneLight)
	b:box("Stone3", -0.7 * s, 3.0 * s, -0.6 * s, 0.6 * s, 4.0 * s, 0.7 * s, C.White)
	return b:finish(base)
end

-- Snowman: three snow blocks, coal eyes, a carrot nose, a red scarf and a navy hat. 8 parts.
local function snowman(parent: any, cf: any)
	local b = Kit.builder(parent, "Snowman", cf)
	local base = b:box("Body", -2.2, 0, -2.2, 2.2, 3.8, 2.2, C.Snow)
	b:box("Belly", -1.7, 3.8, -1.7, 1.7, 6.6, 1.7, C.Snow)
	b:box("Scarf", -1.8, 6.4, -1.8, 1.8, 7.1, 1.8, C.Red, Kit.NOSHADOW)
	b:box("Head", -1.3, 7.1, -1.3, 1.3, 9.5, 1.3, C.Snow)
	b:box("Nose", -0.25, 8.0, -2.4, 0.25, 8.5, -1.3, C.Orange, Kit.DECOR)
	b:box("Eyes", -0.85, 8.7, -1.38, 0.85, 9.1, -1.3, C.Dark, Kit.DECOR)
	b:box("Brim", -1.6, 9.5, -1.6, 1.6, 9.8, 1.6, C.Navy, Kit.NOSHADOW)
	b:box("Hat", -1.0, 9.8, -1.0, 1.0, 11.4, 1.0, C.Navy, Kit.NOSHADOW)
	return b:finish(base)
end

--[[
	Dressing of the spiral trail VoxelWorld carves into the main peak (site.trail: centreline
	points {x, z, h} every ~2 studs from the foot to the flat snowy summit; 4-stud steps): a
	wooden arch with a «ВЕРШИНА» board where the trail leaves the path, chunky lantern posts on
	the outer edge every ~30 studs (every other one with a short red rail along the drop),
	pennants between them and a rest bench half way up on the inner side. Everything stands on
	the trail's own cells (a spot is only used when the ground under its whole footprint is the
	ledge at that point), on the edges, so the ledge stays free to walk.
]]
local function trailDressing(parent: any, world: any, site: any)
	local model = U.model(parent, "Trail")
	local pts = site.trail
	local n = #pts
	-- per point: length along the trail, ledge top, outward unit normal, unit tangent
	local info = {}
	local len = 0
	for i, p in pts do
		if i > 1 then
			len += sqrt((p[1] - pts[i - 1][1]) ^ 2 + (p[2] - pts[i - 1][2]) ^ 2)
		end
		local dx, dz = p[1] - site.x, p[2] - site.z
		local d = sqrt(dx * dx + dz * dz)
		local a, b = pts[max(i - 1, 1)], pts[min(i + 1, n)]
		local tx, tz = b[1] - a[1], b[2] - a[2]
		local tl = sqrt(tx * tx + tz * tz)
		info[i] = { s = len, top = world:heightAt(p[1], p[2]), nx = dx / d, nz = dz / d, tx = tx / tl, tz = tz / tl }
	end
	-- is the ground under a square of half size r round (x, z) all the ledge at height `top`?
	local function onLedge(x: number, z: number, r: number, top: number): boolean
		for _, c in { { -r, -r }, { r, -r }, { r, r }, { -r, r }, { 0, 0 } } do
			local xx, zz = x + c[1], z + c[2]
			if world:heightAt(xx, zz) ~= top or world:kindAt(xx, zz) ~= "path" then
				return false
			end
		end
		return true
	end
	-- a spot `off` studs out from the centreline of point i (inwards when off < 0), moved towards
	-- the centre until the footprint r fits on the ledge: x, z or nil
	local function spot(i: number, off: number, r: number): (number?, number?)
		local p, q = pts[i], info[i]
		local sg = if off < 0 then -1 else 1
		local a = abs(off)
		while a >= 0 do
			local x, z = p[1] + q.nx * a * sg, p[2] + q.nz * a * sg
			if onLedge(x, z, r, q.top) then
				return x, z
			end
			a -= 0.5
		end
		return nil, nil
	end
	local function at(s: number): number
		for i = 1, n do
			if info[i].s >= s then
				return i
			end
		end
		return n
	end
	local function facing(x: number, y: number, z: number, dx: number, dz: number): any
		return CFrame.lookAt(Vector3.new(x, y, z), Vector3.new(x + dx, y, z + dz))
	end

	-- the arch where the trail leaves the path (the first point 15 studs off the path's axis)
	local ux, uz = math.sin(rad(site.angle)), math.cos(rad(site.angle))
	for i = 1, n do
		local p, q = pts[i], info[i]
		if abs((p[1] - site.x) * uz - (p[2] - site.z) * ux) >= 15 then
			local cf = facing(p[1], q.top, p[2], -q.tx, -q.tz) -- the board faces the way up
			local b = Kit.builder(model, "Arch", cf)
			local half, top = 8.6, 11
			for k, sx in { -1, 1 } do
				local w = (cf * CFrame.new(sx * half, 0, 0)).Position
				local g = world:heightAt(w.X, w.Z) - q.top
				b:box(`Post{k}`, sx * half - 1, g - 0.6, -1, sx * half + 1, top, 1, C.WoodLight)
				b:box(`Lamp{k}`, sx * half - 1.3, top + 1.6, -1.3, sx * half + 1.3, top + 4, 1.3, C.Glow, Kit.NEON)
			end
			b:box("Beam", -half - 1.6, top, -1.3, half + 1.6, top + 1.6, 1.3, C.Red)
			local board = b:box("Board", -6, top + 1.6, -0.7, 6, top + 5, 0.7, C.Cream)
			Kit.sign(board, Enum.NormalId.Front, "ВЕРШИНА", C.Navy, nil, { pps = 24 })
			Kit.sign(board, Enum.NormalId.Back, "ВЕРШИНА", C.Navy, nil, { pps = 24 })
			b:finish()
			break
		end
	end

	-- lanterns on the outer edge; every other one starts a short rail along the drop
	local lanterns = 0
	local k = 0
	local s = 26
	while s < len - 20 do
		k += 1
		local i = at(s)
		local placed = false
		for j = i, min(i + 3, n) do
			local x, z = spot(j, 7.2, 1)
			if x then
				local q = info[j]
				lanternPost(model, facing(x, q.top, z, q.tx, q.tz))
				lanterns += 1
				placed = true
				-- a rail from this post 10 studs on along the edge, over a long drop
				local e = at(q.s + 10)
				local x2, z2 = spot(e, 7.2, 0.8)
				local drop = q.top - world:heightAt(pts[j][1] + q.nx * 16, pts[j][2] + q.nz * 16)
				if k % 2 == 0 and x2 and info[e].top == q.top and drop >= 8 then
					local rb = Kit.builder(model, "Rail", CFrame.new(x2, q.top, z2))
					local post = rb:box("Post", -0.7, -0.6, -0.7, 0.7, 3.6, 0.7, C.WoodLight)
					rb:box("Cap", -0.95, 3.6, -0.95, 0.95, 4.2, 0.95, C.Red, Kit.NOSHADOW)
					local a, bb = Vector3.new(x, q.top + 3, z), Vector3.new(x2, q.top + 3, z2)
					local mid = (a + bb) / 2
					rb:block(
						"Rail",
						Vector3.new(0.9, 0.9, (bb - a).Magnitude + 0.6),
						rb.cf:Inverse() * CFrame.lookAt(mid, bb),
						C.Red,
						Kit.NOSHADOW
					)
					rb:finish(post)
				end
				break
			end
		end
		-- a pennant half way to the next lantern (in between, alternating colours)
		local fi = at(s + 15)
		if placed and s + 15 < len - 20 and k % 4 == 1 then
			local x, z = spot(fi, 7.5, 0.6)
			if x then
				local q = info[fi]
				local cols = { C.Yellow, C.Cyan, C.Pink, C.Lime }
				pennant(model, facing(x, q.top, z, q.nx, q.nz), cols[(k // 2) % 4 + 1], 9)
			end
		end
		s += 30
	end

	-- a rest bench half way up, on the inner side, looking out
	for j = at(len * 0.5), n do
		local x, z = spot(j, -6, 3.2)
		if x then
			local q = info[j]
			Kit.bench(model, facing(x, q.top, z, q.nx, q.nz), { length = 6 })
			break
		end
	end
	return lanterns
end

-- Summit lookout deck on the flat snowy summit (cf: its centre on the snow, front = -Z towards
-- where the trail arrives): a stone plinth and a plank deck flush on the snow, red rails with
-- an opening (lantern posts) at the front, a big flag, a snowman, a cairn, a telescope at the
-- front corner and a «ВЕРШИНА» board at the back facing the arrival.
local function summitDeck(parent: any, cf: any, D: number)
	local b = Kit.builder(parent, "SummitDeck", cf)
	local y = 0.9 -- deck top above the snow (two 0.45 steps)
	b:box("Plinth", -D - 1.2, -1.4, -D - 1.2, D + 1.2, 0.45, D + 1.2, C.StoneLight)
	local deck = b:box("Deck", -D, -0.8, -D, D, y, D, C.WoodLight)
	for i, p in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local px, pz = p[1] * (D - 0.9), p[2] * (D - 0.9)
		b:box(`Corner{i}`, px - 0.9, y, pz - 0.9, px + 0.9, y + 4, pz + 0.9, C.White)
	end
	local railC = C.Red
	local ry0, ry1 = y + 2.7, y + 3.5
	local gap = 4
	b:box("RailBack", -D, ry0, D - 0.8, D, ry1, D, railC, Kit.NOSHADOW)
	b:box("RailL", -D, ry0, -D, -D + 0.8, ry1, D, railC, Kit.NOSHADOW)
	b:box("RailR", D - 0.8, ry0, -D, D, ry1, D, railC, Kit.NOSHADOW)
	b:box("RailFront", -D, ry0, -D, -gap, ry1, -D + 0.8, railC, Kit.NOSHADOW)
	b:box("RailFrontB", gap, ry0, -D, D, ry1, -D + 0.8, railC, Kit.NOSHADOW)
	-- lantern posts framing the way in
	for i, sx in { -1, 1 } do
		local x = sx * (gap + 0.8)
		b:box(`GatePost{i}`, x - 0.8, y, -D - 0.2, x + 0.8, y + 5, -D + 1.4, C.White)
		b:box(`GateLamp{i}`, x - 1.1, y + 5, -D - 0.5, x + 1.1, y + 7.2, -D + 1.7, C.Glow, Kit.NEON)
	end
	-- telescope on the front-left corner, looking out
	local tx, tz = -D + 3.5, -D + 3.5
	b:box("ScopePost", tx - 0.4, y, tz - 0.4, tx + 0.4, y + 3.4, tz + 0.4, C.Navy)
	b:box("Scope", tx - 1, y + 3.4, tz - 1.8, tx + 1, y + 4.7, tz + 0.9, C.Yellow)
	b:box("ScopeLens", tx - 0.65, y + 3.6, tz - 2.1, tx + 0.65, y + 4.5, tz - 1.75, C.Cyan, Kit.DECOR)
	-- «ВЕРШИНА» board on posts at the back, facing the arrival
	local board = b:box("Board", -6, y + 4.2, D - 1.7, 6, y + 8.6, D - 1, C.Blue)
	b:box("BoardPostL", -6.8, y, D - 1.9, -5.6, y + 9, D - 0.8, C.White)
	b:box("BoardPostR", 5.6, y, D - 1.9, 6.8, y + 9, D - 0.8, C.White)
	Kit.sign(board, Enum.NormalId.Front, "ВЕРШИНА", C.White, C.Navy, { pps = 24 })
	b:finish(deck)
	local function on(lx: number, lz: number, yaw: number?): any
		return cf * CFrame.new(lx, y, lz) * CFrame.Angles(0, rad(yaw or 0), 0)
	end
	bigFlag(b.model, on(D - 4, D - 4.5, 0), 24, 10, 6, C.Red)
	-- the snowman and the cairn stand on the snow beside the deck
	snowman(b.model, on(D + 4.5, -D + 3, -30) * CFrame.new(0, -y, 0))
	cairn(b.model, on(-D - 4, D - 3, 30) * CFrame.new(0, -y, 0), 1.2)
	return b.model
end

local function buildPeaks(root: any, cfg: any, world: any)
	local model = U.model(root, "Peaks")
	-- the smaller peaks: a chunky flag on the summit block
	for _, name in { "PeakEast", "PeakSouth" } do
		local site = world.landmarks[name]
		if not site then
			continue
		end
		local x, z, y = summit(world, site.x, site.z, 48)
		local m = U.model(model, `{name}Flag`)
		bigFlag(m, CFrame.new(x, y, z) * CFrame.Angles(0, rad(site.angle + 90), 0), 16, 8, 5, C.Yellow)
	end

	local site = world.landmarks.Peak
	if not site then
		return
	end
	local frame = Kit.radialCFrame(site.angle, site.radius, 0, 0, 0)
	local function ground(lx: number, lz: number): number
		local x, z = Kit.radial(site.angle, site.radius, lx, lz)
		return world:heightAt(x, z)
	end

	-- base camp: a flat plank pad beside the end of the path, on the side away from where the
	-- trail turns off, as low as the ground allows and clear of the path and the trail
	local reach = site.radius - site.mountainRadius + 12 -- the path's end (VoxelWorld.pathDistance)
	local endLz = reach - site.radius
	local side = 1
	if site.trail then
		local p = site.trail[min(12, #site.trail)]
		local tlx = world.radialLocal(p[1], p[2], site.angle, site.radius)
		side = if tlx > 0 then -1 else 1
	end
	local padHX, padHZ = 12, 11
	local best, padLx, padLz, padLo, padHi = math.huge, nil, nil, 0, 0
	for clx = 10 + padHX, 26 + padHX, 2 do
		for clz = endLz - 34, endLz + 8, 2 do
			local lo, hi, clear = math.huge, -math.huge, true
			for gx = -padHX - 2, padHX + 2, 2 do
				for gz = -padHZ - 2, padHZ + 2, 2 do
					local x, z = Kit.radial(site.angle, site.radius, side * clx + gx, clz + gz)
					if world:isReserved(x, z) then
						clear = false
						break
					end
					local h = world:heightAt(x, z)
					lo, hi = min(lo, h), max(hi, h)
				end
				if not clear then
					break
				end
			end
			-- the lowest pad with the least fill, then the closest to the path's end
			local score = hi * 3 + (hi - lo) + abs(clz - endLz) * 0.1 + clx * 0.05
			if clear and score < best then
				best, padLx, padLz, padLo, padHi = score, side * clx, clz, lo, hi
			end
		end
	end
	local camp = U.model(model, "Camp")
	if padLx then
		local padTop = padHi + 0.5
		local pb = Kit.builder(camp, "Pad", frame * CFrame.new(padLx, 0, padLz))
		local pad = pb:box("Pad", -padHX, padLo - 1.5, -padHZ, padHX, padTop, padHZ, rgb(236, 206, 150))
		pb:box(
			"PadEdge",
			-padHX - 0.6,
			padLo - 1.6,
			-padHZ - 0.6,
			padHX + 0.6,
			padTop - 0.15,
			padHZ + 0.6,
			C.WoodDark,
			Kit.NOSHADOW
		)
		pb:finish(pad)
		-- 1-stud steps down from the pad's path-side edge to the path
		local edge = padLx - side * padHX
		local pathY = ground(edge - side * 3, padLz)
		local nSteps = math.ceil(padTop - pathY - 0.6)
		if nSteps >= 1 then
			local sb = Kit.builder(camp, "PadSteps", frame)
			for k = 1, nSteps do
				local x0 = edge - side * (0.6 + (nSteps - k + 1) * 2)
				local x1 = x0 + side * 2
				sb:box(
					`Step{k}`,
					min(x0, x1),
					pathY - 1,
					padLz - 4,
					max(x0, x1),
					pathY + k * (padTop - pathY) / (nSteps + 1),
					padLz + 4,
					if k % 2 == 1 then C.WoodLight else C.Wood
				)
			end
			sb:finish()
		end
		local function at(lx: number, lz: number, yaw: number?): any
			return frame * CFrame.new(padLx + side * lx, padTop, padLz + lz) * CFrame.Angles(0, rad(yaw or 0), 0)
		end
		-- yaw (degrees) that turns a prop's front (-Z) from (lx, lz) towards (tx, tz) (pad frame)
		local function toward(lx: number, lz: number, tx: number, tz: number): number
			return deg(atan2(-side * (tx - lx), -(tz - lz)))
		end
		-- two tents and a flag at the back, the campfire with two logs in front of them
		local fireX, fireZ = 0, -2
		tent(camp, at(-5, 5, toward(-5, 5, fireX, fireZ)), C.Orange)
		tent(camp, at(6, 4, toward(6, 4, fireX, fireZ)), C.Blue)
		Kit.prop("campfire", camp, at(fireX, fireZ), { light = true })
		Kit.prop("log", camp, at(fireX, fireZ - 5, 90), { seed = 1 })
		bigFlag(camp, at(8.5, -7.5, 90), 14, 7, 4.5, C.Orange)
		local wx, wz = Kit.radial(site.angle, site.radius, padLx, padLz)
		Kit.claim(wx, wz, 20)
	end
	-- the signpost at the path's end, pointing up the trail
	local sx, sz = Kit.radial(site.angle, site.radius, -side * 9.5, endLz - 20)
	Kit.prop("signpost", camp, Kit.ground(world, sx, sz, site.angle), {
		text = "ВЕРШИНА",
		width = 9,
		color = C.Cream,
		trim = C.Blue,
		arrow = if side > 0 then "right" else "left",
	})

	-- the carved trail and the summit deck flush on the flat snowy summit, open towards where
	-- the trail arrives (without a trail: on the highest block, open towards the lagoon)
	local cx, cz, topY, half
	local tx, tz
	if site.trail and site.summitTop then
		cx, cz, topY = site.x, site.z, site.summitTop
		half = min(12, site.summitRadius - 6)
		local last = site.trail[#site.trail]
		tx, tz = last[1], last[2]
		trailDressing(model, world, site)
	else
		cx, cz, topY = summit(world, site.x, site.z, 48)
		half = 10
		tx, tz = 0, 0
	end
	summitDeck(model, Kit.facing(cx, topY, cz, tx, tz), half)
	Kit.claim(cx, cz, half + 6)
end

--------------------------------------------------------------------------------------------

function Landmarks.build(map: any, cfg: any, world: any)
	local root = U.model(map, "Landmarks")
	local sites = world.landmarks
	if sites.Waterfall then
		buildWaterfall(root, cfg, world, sites.Waterfall)
	end
	if sites.Windmill then
		buildWindmill(root, cfg, world, sites.Windmill)
	end
	if sites.GiantTree then
		buildGiantTree(root, cfg, world, sites.GiantTree)
	end
	buildPeaks(root, cfg, world)
	return root
end

return Landmarks
