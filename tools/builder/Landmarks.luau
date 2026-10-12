--[[
	Landmarks — dressing of the four landmark sites of World v3 (world.landmarks, DESIGN.md §5/§6),
	built into Map.Landmarks. Art direction v4 (DESIGN.md §1): natural materials (sandstone,
	stone, timber, plaster, canvas) in Palette colours, strong colour only on small accents
	(flowers, flags, lanterns), no figures.

	  Waterfall  a three-tier cascade off the mesa's lagoon-facing cliff, each tier 5-6 studs
	             narrower than the one above (staggered curtains of light-blue columns 2-6 wide at
	             different depths with pale streaks, ragged lips of warm stone with lumps of white
	             foam breaking over them, two solid mossy sandstone shelves) into the pond: foam
	             patches, bubbling foam cubes and splash rocks in rings of foam where it lands,
	             rocks and reeds round the pool's rim; foam particles off every lip, spray and mist
	             over the pool, the roar of the water (a looped 3D sound); solid sandstone stairs
	             right of the fall (two flights along the foot of the face where it steps back,
	             the upper one against clean cut walls in the cliff's strata, light stone treads,
	             timber posts and rails, lanterns, vine curtains) up to a bastion whose top is the
	             lookout deck (telescope, bench, flag); a plank boardwalk level with the promenade
	             from its path gap round the pond's rim to the stairs; mossy ledges, vines and
	             grassy boulders on the cliffs; a lily pad and reeds. On the mesa top a stream
	             meanders from a spring pool to the lip, and the pool is the way to a destination:
	             a stepped sandstone grotto («РОДНИК») the spring flows out of, a small glowing
	             crystal cluster with sparkles on top, a paved path to it from the lookout, a
	             picnic grove (fruit and blossom trees, a hammock, a blanket, flowers), a rope swing
	             near the lip, stepping stones across the stream.
	  Windmill   the hero tower mill on the ziggurat top (see heroMill: a stone ground floor, a
	             timber band, plaster tiers with framed windows, green shutters and a flower box, a
	             pitched red cap, canvas sails spinning as "Blades" on an axle high over the
	             balcony): a walk-through room on the ground floor (front and back doors, a
	             millstone, sacks, a lantern), a ladder up the back to the balcony (a 5-stud
	             walkway, parapet, bench, telescope, petals drifting off it); planted beds on every
	             other terrace ring all round (tulip clumps in segments with grass between at the
	             front, lavender and sunflowers on the sides, wheat at the back), bush clumps and
	             rocks on the lawn rings' risers, a little farm on the back (hay bales, a beehive);
	             chunky 2-stud stairs up the front (invisible ramps over them), a timber rail
	             fence round the top meadow.
	  GiantTree  Props.giantTree (treehouse, swing, lanterns) on the meadow plateau, scaled to a
	             real giant, with a long slide from the treehouse deck down to the meadow (the fun
	             way down); steps up from the path with grassy cheek blocks filling the plateau's
	             jagged edge beside them; a glowing giant mushroom with fireflies, lantern posts.
	  Peaks      the main Peak is climbed by the spiral trail VoxelWorld carves into it, walkable
	             all the way: a path-tan wedge ramp on every riser. A base camp on a flat pad beside
	             the end of its path (tents, a smoking fire ring with sparks), a roofed «ВЕРШИНА»
	             gate where the trail leaves the path, lantern posts, pennants, leafy curtains with
	             blooms on the inner rock wall and a rest bench along it, and a lookout deck flush
	             on the flat snowy summit, open towards the trail's end (big flag with gold
	             sparkles, telescope, a board under a little roof). The other mountains are
	             scenery nobody can climb, so they carry no flags. The pines on the slopes come
	             from Nature.

	Every site is registered with Kit.claim so Nature keeps its trees off the dressing.
]]

local U = require("./Util")
local Kit = require("./MapKit")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Enum = U.Enum
local C = Kit.C -- the Palette (tools/builder/Palette.luau)
local mix = Kit.lerpColor

local rad, deg, sqrt, atan2, floor, max, min, abs =
	math.rad, math.deg, math.sqrt, math.atan2, math.floor, math.max, math.min, math.abs

local Landmarks = {}

local WATER_SHEET = { CanCollide = false, CastShadow = false, CanQuery = false } -- opaque stream/pool sheets
local BRASS = mix(C.Gold, C.WoodDark, 0.3) -- telescopes, finials
local INK = Kit.shade(C.WoodDark, 0.7) -- dark brown sign text on cream boards
-- falling and shallow water: light, so the falls read as white water, not panels of glass
local FALL_A = U.rgb(120, 196, 226)
local FALL_B = U.rgb(150, 210, 234)
local STREAK = U.rgb(200, 234, 246)
local FOAM = U.rgb(240, 248, 252)
local DEEP = mix(FALL_A, C.Water, 0.45) -- deeper water in pools

-- A wedge in a builder's frame (its tall face at local +Z, the slope falling towards -Z).
local function wedge(b: any, name: string, size: any, lcf: any, color: any, extra: any?): any
	local p = U.wedge(b.model, name, size, b.cf * lcf, color, nil, extra)
	p.Locked = true
	b.first = b.first or p
	return p
end

-- A pitched roof of two wedges over x0..x1 / z0..z1, eaves at y0, the ridge h higher; the ridge
-- runs along X, or along Z with alongZ (the gable ends to the front and the back).
local function gable(
	b: any,
	name: string,
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	y0: number,
	h: number,
	color: any,
	alongZ: boolean?
)
	local xm, zm, y = (x0 + x1) / 2, (z0 + z1) / 2, y0 + h / 2
	if alongZ then
		local w, d = (x1 - x0) / 2, z1 - z0
		wedge(b, `{name}L`, Vector3.new(d, h, w), CFrame.new(x0 + w / 2, y, zm) * CFrame.Angles(0, rad(90), 0), color)
		wedge(b, `{name}R`, Vector3.new(d, h, w), CFrame.new(x1 - w / 2, y, zm) * CFrame.Angles(0, rad(-90), 0), color)
	else
		local w, d = x1 - x0, (z1 - z0) / 2
		wedge(b, `{name}F`, Vector3.new(w, h, d), CFrame.new(xm, y, z0 + d / 2), color)
		wedge(b, `{name}B`, Vector3.new(w, h, d), CFrame.new(xm, y, z1 - d / 2) * CFrame.Angles(0, math.pi, 0), color)
	end
end

-- A brass telescope on an iron post at (x, y, z) looking along -Z.
local function telescope(b: any, x: number, y: number, z: number)
	b:box("ScopePost", x - 0.4, y, z - 0.4, x + 0.4, y + 3.4, z + 0.4, C.Iron)
	b:box("Scope", x - 0.9, y + 3.4, z - 1.8, x + 0.9, y + 4.6, z + 0.9, BRASS)
	b:box("ScopeLens", x - 0.6, y + 3.6, z - 2.1, x + 0.6, y + 4.4, z - 1.75, C.Glass, Kit.DECOR)
end

-- Chunky lantern post standing on cf (3 parts): a timber post, a Neon cube, a dark cap.
local function lanternPost(parent: any, cf: any, h: number?): any
	local hh = h or 5
	local b = Kit.builder(parent, "Lantern", cf)
	local post = b:box("Post", -0.8, -0.6, -0.8, 0.8, hh, 0.8, C.Wood)
	b:box("Lamp", -1, hh, -1, 1, hh + 2, 1, C.Glow, Kit.NEON)
	b:box("Cap", -1.4, hh + 2, -1.4, 1.4, hh + 2.7, 1.4, C.WoodDark, Kit.NOSHADOW)
	return b:finish(post)
end

-- Pennant on a pole standing on cf (3 parts), flying along local +X.
local function pennant(parent: any, cf: any, color: any, h: number)
	local b = Kit.builder(parent, "Pennant", cf)
	b:pole("Pole", 0.7, 0, 0, -0.5, h, C.WoodLight)
	b:box("Cloth", 0.3, h - 3.4, -0.25, 4.6, h - 0.6, 0.25, color, Kit.DECOR)
	b:box("Knob", -0.5, h, -0.5, 0.5, h + 1, 0.5, BRASS, Kit.DECOR)
	return b:finish()
end

--------------------------------------------------------------------------------------------
-- Waterfall
--------------------------------------------------------------------------------------------

-- The mesa's cliff strata (Ground.luau): 12-stud bands on absolute y in three sandstone shades.
local STRATA = { U.rgb(206, 162, 112), U.rgb(190, 144, 98), U.rgb(222, 186, 138) } -- = Ground.luau Sandstone
local STRATUM = 12
local TREAD = mix(C.Cream, C.SandDark, 0.5) -- light stone stair treads on the sandstone
-- falling water and foam: opaque (colour does the work; transparent layers would sort-flicker)
local WATER = { CanCollide = false, CastShadow = false, CanQuery = false }

-- Block from y0 to y1 (absolute y; the builder's frame sits at y = 0) split into the mesa's
-- strata bands, so built rock lines up with the cliff behind it.
local function strataBox(b: any, name: string, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
	local y = y1
	local k = 0
	while y > y0 + 0.01 do
		local band = floor((y - 0.01) / STRATUM)
		local yb = max(y0, band * STRATUM)
		if yb - y0 < 2 then -- no sliver at the bottom
			yb = y0
		end
		k += 1
		b:box(`{name}{k}`, x0, yb, z0, x1, y, z1, STRATA[band % #STRATA + 1])
		y = yb
	end
end

-- Railing on a straight run between two top-of-floor points (site-frame lx, y, lz): chunky
-- dark timber 1.4-stud posts, a timber bar 3 studs up. posts: "both" (default), "last" (the run
-- continues from an existing post) or "none". 1-3 parts.
local function railRun(b: any, name: string, a: any, c: any, posts: string?)
	local which = posts or "both"
	for i, p in { a, c } do
		if which == "none" or (i == 1 and which == "last") then
			continue
		end
		b:box(`{name}Post{i}`, p.X - 0.7, p.Y - 0.5, p.Z - 0.7, p.X + 0.7, p.Y + 3.9, p.Z + 0.7, C.WoodDark)
	end
	local u, v = a + Vector3.new(0, 2.9, 0), c + Vector3.new(0, 2.9, 0)
	local d = v - u
	b:block(
		`{name}Bar`,
		Vector3.new(0.9, 0.9, d.Magnitude),
		CFrame.lookAt((u + v) / 2, (u + v) / 2 + d),
		C.Wood,
		Kit.NOSHADOW
	)
end

--[[
	The falls (site frame, y absolute): three tiers of falling water, each narrower than the one
	above, stepping out over two solid sandstone rock shelves from the lip into the pond. Each
	tier is a staggered curtain of columns 2-6 studs wide, at different depths (up to 1.8 out)
	and in two light blues, some starting a little under the lip, with a few pale streaks of
	faster water 0.35 proud of them; the water runs over each shelf top to its edge. Every lip is
	ragged: rocks of warm stone (two shades) flank the water, one stands in the top lip's flow,
	and irregular white foam caps (different widths, heights and overhangs, 1-2 studs out over
	the edge) mark where it breaks over. Where it lands: overlapping foam patches of different
	sizes, a few bubbling foam cubes, two splash rocks each in a ring of foam. Particles: foam
	tumbling off every lip, spray and mist over the pool. Nothing is transparent (no sorting
	flicker) and no two faces share a plane. fmin / fmax: the jagged cliff face (lz) behind the
	fall, lipLz: where the stream reaches the lip, W: the width of the fall at the top.
]]
local function cascade(parent: any, site: any, frame: any, fmin: number, fmax: number, lipLz: number, W: number)
	local b = Kit.builder(parent, "Waterfall", frame)
	local r = Kit.rng(4507)
	local top = site.cliffTop + 0.9 -- over the stream sheet
	local blues = { FALL_A, FALL_B }
	local hw1 = W / 2
	-- the rock shelves: the upper one is a solid block from the lower shelf up out of the cliff
	-- (the narrower middle tier falls down its face), the lower one stands in the pond
	local s1 = { z0 = -12, z1 = fmax + 1, y0 = 18.9, y1 = 38.4, hw = hw1 + 3 }
	local s2 = { z0 = -23, z1 = fmin + 2, y0 = -7.5, y1 = 19.4, hw = hw1 + 4 }
	-- tiers: top y, bottom y, front lz, back lz, half width
	local tiers = {
		{ top, s1.y1 - 0.3, fmin - 3, lipLz, hw1 },
		{ s1.y1 + 0.5, s2.y1 - 0.3, s1.z0 - 3, s1.z0 + 0.6, hw1 - 3 },
		{ s2.y1 + 0.5, -0.6, s2.z0 - 3, s2.z0 + 0.6, hw1 - 5.5 },
	}
	for i, s in { s1, s2 } do
		b:box(`Shelf{i}`, -s.hw, s.y0, s.z0, s.hw, s.y1, s.z1, if i == 1 then STRATA[2] else STRATA[1])
		-- moss on the shoulders either side of the water running over it
		local w = tiers[i + 1][5]
		for k, sx in { -1, 1 } do
			local x0, x1 = sx * (w + 1.5), sx * (s.hw + 0.4)
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
		-- the water running over the shelf top to its front edge
		b:box(`ShelfWater{i}`, -w + 0.3, s.y1 - 0.2, s.z0 - 0.3, w - 0.3, s.y1 + 0.45, s.z0 + 9, FALL_B, WATER)
	end
	for t, tier in tiers do
		local y1, y0, f, k, hw = tier[1], tier[2], tier[3], tier[4], tier[5]
		local h = y1 - y0
		-- the curtain: columns 2-6 wide across the tier, each at its own depth and blue, some
		-- starting a little under the lip
		local cols = {}
		local x = -hw
		while x < hw - 0.5 do
			local w = r(2, 6)
			if hw - (x + w) < 2 then
				w = hw - x
			end
			table.insert(cols, { x, x + w })
			x += w
		end
		local fronts = {}
		for c, q in cols do
			local out = floor(r(0, 3.99)) * 0.6 + (c % 2) * 0.05
			local drop = if r() < 0.35 then r(0.6, 1.6) else 0
			fronts[c] = f - out
			b:box(`Curtain{t}_{c}`, q[1], y0, f - out, q[2], y1 - drop, k, blues[(c + t) % 2 + 1], WATER)
		end
		-- streaks of faster water down the columns: thin white threads and pale ribbons of
		-- different lengths, each in its own slot across the tier
		local ns = 5 - t
		for i = 1, ns do
			local slot = 2 * hw / ns
			local sx0 = -hw + (i - 1) * slot
			local sw = r(0.8, 1.6)
			local sx = sx0 + r(0.3, max(slot - sw - 0.3, 0.4))
			local c = 1
			for ci, q in cols do
				if sx + sw / 2 >= q[1] and sx + sw / 2 < q[2] then
					c = ci
				end
			end
			local zf = min(fronts[c], fronts[min(c + 1, #cols)], fronts[max(c - 1, 1)]) - 0.35
			local len = h * r(0.3, 0.9)
			local yt = y1 - r(0.8, 3)
			b:box(
				`Streak{t}_{i}`,
				sx,
				max(yt - len, y0 + 0.3),
				zf,
				sx + sw,
				yt,
				f + 0.5,
				if i % 2 == 0 then FOAM else STREAK,
				WATER
			)
		end
		-- foam where it breaks over the lip: lumps of white of different sizes along the edge,
		-- at different heights and overhangs (0.3-1.6 out over it), with gaps where the blue
		-- water pours through (not a bar); foam particles tumble off the biggest
		local crest, biggest = nil, 0
		local cx = -hw + r(0, 1)
		local nf = 0
		while cx < hw - 1 do
			nf += 1
			local w = min(r(2.4, 4.2), hw + 0.4 - cx)
			local hgt = r(1.2, 2.4)
			-- (overhangs and tops never on a column's front or top plane)
			local over = floor(r(0, 2.99)) * 0.6 + 0.3 + (nf % 3) * 0.07
			local yb = y1 - r(0.6, 1.4)
			if abs(yb + hgt - y1) < 0.15 then
				hgt += 0.3
			end
			local p = b:box(
				`Foam{t}_{nf}`,
				cx,
				yb,
				f - over,
				cx + w,
				yb + hgt,
				f + 2.4,
				if nf % 2 == 0 then FOAM else mix(FOAM, STREAK, 0.4),
				WATER
			)
			if w * hgt > biggest then
				crest, biggest = p, w * hgt
			end
			cx += w + (if r() < 0.45 then r(0.8, 2.2) else -0.2)
		end
		Kit.foam(crest, Enum.NormalId.Bottom, { box = true, rate = 2 + hw * 0.4, size = 1.6, grow = 2.6 })
		-- the ragged rock lip: a rock of warm stone either side of the water, the top lip with a
		-- third standing in the flow
		for i, sx in { -1, 1 } do
			local rw, rh = r(3.2, 4.6), r(2.4, 3.6)
			local x0 = sx * (hw - 0.6)
			local x1 = x0 + sx * rw
			b:box(
				`LipRock{t}_{i}`,
				min(x0, x1),
				y1 - 1.6,
				f - r(0.4, 1.4),
				max(x0, x1),
				y1 + rh - 1.6,
				f + 4,
				if (i + t) % 2 == 0 then C.Stone else C.StoneDark
			)
		end
		if t == 1 then
			local mx = r(-0.4, -0.15) * hw
			b:box("FlowRock", mx - 1.6, y1 - 1.4, f - 1.2, mx + 1.6, y1 + 1.6, f + 3, C.StoneDark)
		end
	end
	-- where it lands: overlapping foam patches round the impact, bubbling foam cubes, two splash
	-- rocks each in a ring of foam
	local hw3 = tiers[3][5]
	local zf = s2.z0 - 3
	local foam = b:box("Splash", -hw3 - 1, -0.3, zf - 8, hw3 + 1, 0.5, zf + 2.5, FOAM, WATER)
	for i, q in
		{
			{ -hw3 - 4.5, -hw3 + 3, -5, 1.5, 0.35 },
			{ hw3 - 4, hw3 + 4, -11, -2, 0.25 },
			{ -4, 6, -14, -6, 0.15 },
		}
	do
		local c = if i == 2 then mix(FOAM, FALL_B, 0.3) else FOAM
		b:box(`FoamPatch{i}`, q[1], -0.4, zf + q[3], q[2], q[5], zf + q[4], c, WATER)
	end
	for i = 1, 3 do
		local sz = r(2.2, 3.6)
		local x = -hw3 + (i - 0.5) * (2 * hw3) / 3 + r(-1, 1)
		local z = zf - 1.5 - r(0, 4)
		b:box(
			`FoamCube{i}`,
			x - sz / 2,
			0.2,
			z - sz / 2,
			x + sz / 2,
			0.6 + sz * 0.45 + i * 0.07,
			z + sz / 2,
			FOAM,
			WATER
		)
	end
	for i, q in { { -hw3 - 7, zf - 12, 4.2, 3 }, { hw3 + 4.5, zf - 15, 3.4, 2.4 } } do
		local x, z, w, h = q[1], q[2], q[3], q[4]
		b:box(
			`SplashRock{i}`,
			x - w / 2,
			-2,
			z - w / 2,
			x + w / 2,
			h,
			z + w / 2,
			if i == 1 then C.StoneDark else C.Stone
		)
		b:box(
			`SplashRockTop{i}`,
			x - w / 2 + 0.6,
			h,
			z - w / 2 + 0.5,
			x + w / 2 - 0.4,
			h + 0.9,
			z + w / 2 - 0.7,
			C.Stone,
			Kit.NOSHADOW
		)
		b:box(
			`FoamRing{i}`,
			x - w / 2 - 1.2,
			-0.3,
			z - w / 2 - 1.2,
			x + w / 2 + 1.2,
			0.25 + i * 0.05,
			z + w / 2 + 1.2,
			FOAM,
			WATER
		)
	end
	-- the falls are heard before they are seen: a looped water sound in the splash, slowed to a
	-- rumble, 3D (fades out by the promenade). A built-in engine sound (always present in the
	-- client), so no asset id can go missing.
	U.new("Sound", {
		Name = "Roar",
		SoundId = "rbxasset://sounds/action_swim.mp3",
		Looped = true,
		Playing = true,
		Volume = 0.45,
		PlaybackSpeed = 0.55,
		RollOffMode = Enum.RollOffMode.InverseTapered,
		RollOffMinDistance = 14,
		RollOffMaxDistance = 130,
	}, foam)
	-- spray thrown up where it lands, mist drifting over the pool
	Kit.foam(foam, Enum.NormalId.Top, {
		name = "Spray",
		box = true,
		rate = 14,
		size = 1.4,
		grow = 3,
		speed = { 6, 11 },
		lifetime = { 0.8, 1.4 },
		gravity = 18,
		spread = 30,
	})
	Kit.foam(foam, Enum.NormalId.Top, {
		name = "Mist",
		rate = 5,
		size = W * 0.25,
		grow = 2,
		speed = { 2, 5 },
		lifetime = { 1.6, 2.6 },
		gravity = -2,
		spread = 50,
		transparency = 0.55,
	})
	return b:finish()
end

--[[
	Stairs up the cliff right of the fall, all solid sandstone (no stilts), in the site frame
	(lz outwards, y absolute): two lanes along the face — the outer flight climbs away from the
	fall to a landing, the inner flight (against the cliff) climbs back to a bastion beside the
	fall whose top is the lookout deck, level with the mesa top. 4-stud cream treads on sandstone
	blocks down to the ground (the bastion in the cliff's strata); an invisible ramp over each
	flight makes the 2.6-stud steps walkable. White posts and red bars on the open sides,
	lantern posts at the foot and the landing. Both lanes stay in front of the jagged
	voxel face (faceLo: its nearest lz), so no mesa column pokes through a tread; the upper
	flight's blocks and treads run on into the rock (to fmax + 1) like steps cut into it, and the
	bastion and its deck reach back into the mesa top.
	Returns the stair info: bastion lx bx0..bx1, lanes zB0 (front) .. zA1 (the cliff side), the
	back zBack, deck top y, the foot (lx, lz) of the first flight, the far x of the landing.
]]
local function cliffStairs(
	parent: any,
	world: any,
	site: any,
	frame: any,
	fmin: number,
	faceLo: number,
	fmax: number,
	bx0: number
)
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
	local zA1 = faceLo - 0.5
	local zA0, zBack = zA1 - 7.5, fmax + 1
	local zB0 = zA0 - 7.5
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
	-- a flight of n steps on lane z0..z1 (blocks and treads on to zx) from x = from (going dir)
	-- starting at yStart
	local function flight(f: number, z0: number, z1: number, zx: number, from: number, dir: number, yStart: number)
		for k = 1, n do
			local xa, xb = from + dir * (k - 1) * tread, from + dir * k * tread
			local x0, x1 = min(xa, xb), max(xa, xb)
			local yk = yStart + k * rise
			local shade = if k % 2 == 0 then 1.04 else 1
			b:box(`Block{f}_{k}`, x0, lowest(x0, x1, z0, zx) - 1.5, z0, x1, yk - 0.8, zx, Kit.shade(STRATA[f], shade))
			-- the cream tread overhangs the step's front (and the lane's open side) a little
			local nx0, nx1 = if dir > 0 then x0 - 0.3 else x0, if dir > 0 then x1 else x1 + 0.3
			b:box(`Step{f}_{k}`, nx0, yk - 0.8, z0 - (if f == 1 then 0.3 else 0), nx1, yk, zx, TREAD)
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
	local line1 = flight(1, zB0, zA0, zA0, xs, 1, y0)
	local g0 = ground(xs + 2, zB0 - 6)
	local yIn = line1(xs + 1.5) - 0.4
	for k = 1, 4 do
		local z0, z1 = zB0 - 0.3 - (5 - k) * 2.5, zB0 - 0.3 - (4 - k) * 2.5
		b:box(`Entry{k}`, xs, min(g0, 0) - 1, z0, xs + tread + 1.6, g0 + k * (yIn - g0) / 4, z1, TREAD)
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
	local gl = lowest(xe, xl, zB0, zBack)
	b:box("LandingBlock", xe, gl - 1.5, zB0, xl, yMid - 0.8, zBack, STRATA[3])
	b:box("Landing", xe, yMid - 0.8, zB0 - 0.3, xl + 0.3, yMid, zBack, TREAD)
	-- the upper flight (inner lane, back towards the fall)
	local line2 = flight(2, zA0, zA1, zBack, xe, -1, yMid)
	-- the rock it is cut into: the lane runs along the foot of the face, but behind it the voxel
	-- cliff is a staircase of 8-stud cells across the 45-degree flight, which would poke up
	-- through the treads' back halves in a zig-zag, so a solid cut wall (the cliff's strata, a
	-- grass cap) stands on the lane's inner edge up to the rock's own top wherever the rock
	-- reaches a tread (a low grassy kerb where it barely does), hiding the jagged cells behind a
	-- clean face; the lane in front stays clear. Steps with the same rock height behind them
	-- share one wall.
	local walls = {}
	local cur = nil
	for k = 1, n do
		local x0, x1 = xe - k * tread, xe - (k - 1) * tread
		local hk = -math.huge
		for x = x0, x1, 1 do
			for z = zA1, zBack + 2, 1 do
				hk = max(hk, ground(x, z))
			end
		end
		local yk = yMid + k * rise -- the tread top
		if hk <= yk - 0.05 then
			cur = nil
		elseif cur and cur.h == hk then
			cur.x0, cur.y = x0, min(cur.y, yk)
		else
			cur = { x0 = x0, x1 = x1, h = hk, y = yk }
			table.insert(walls, cur)
		end
	end
	for i, w in walls do
		-- (0.1 up the flight and 0.1 deeper than the treads: no plane shared with a riser or a
		-- tread's back; 0.06 off the bastion's side and the top step's back)
		local x0, x1 = max(w.x0 - 0.1, bx1 + 0.06), w.x1 - 0.1
		strataBox(b, `Cut{i}_`, x0, w.y - 1.2, zA1, x1, w.h - 0.7, zBack + 0.1)
		b:box(`CutGrass{i}`, x0, w.h - 0.7, zA1, x1, w.h + 0.35, zBack + 0.1, C.GrassTop, Kit.NOSHADOW)
	end
	-- the bastion: a solid tower in the cliff's strata, the lookout deck on top
	local gb = lowest(bx0, bx1, zB0, zBack)
	strataBox(b, "Bastion", bx0, gb - 1.5, zB0, bx1, yTop - 0.8, zBack)
	b:box("Deck", bx0 - 0.3, yTop - 0.8, zB0 - 0.3, bx1, yTop, zBack, C.WoodLight)
	-- rails: the lower flight's open side (the entry left free at the foot), the landing, the
	-- upper flight's open side (over the lower flight), the deck
	local rx = xs + 2 * tread
	local cA, cB = P(xe - 0.6, yMid, zB0 + 0.5), P(xl - 0.6, yMid, zB0 + 0.5)
	railRun(b, "Rail1", P(rx, line1(rx), zB0 + 0.5), cA)
	railRun(b, "RailL1", cA, cB, "last")
	railRun(b, "RailL2", cB, P(xl - 0.6, yMid, zBack - 2), "last")
	local r2 = xe - 2 * tread
	local cC, cD, cE = P(bx1 - 0.6, yTop, zA0 + 0.6), P(bx0 + 0.6, yTop, zB0 + 0.5), P(bx1 - 0.6, yTop, zB0 + 0.5)
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
	lanternPost(parent, frame * CFrame.new(xl - 1.5, yMid, zA1 - 1.5))
	return {
		bx0 = bx0,
		bx1 = bx1,
		zB0 = zB0,
		zA0 = zA0,
		zA1 = zA1,
		zBack = zBack,
		top = yTop,
		footX = xs + tread,
		xl = xl,
	}
end

-- The lookout on the bastion deck: telescope at the front corner by the fall, a bench and a
-- flag, all looking out over the pond and the lagoon.
local function lookout(parent: any, frame: any, st: any)
	local y = st.top
	local b = Kit.builder(parent, "Lookout", frame)
	local tx, tz = st.bx0 + 2.6, st.zB0 + 2.6
	telescope(b, tx, y, tz)
	b:finish()
	Kit.bench(b.model, frame * CFrame.new(st.bx0 + 5.5, y, st.zB0 + 5), { length = 6 })
	Kit.prop("flagPole", b.model, frame * CFrame.new(st.bx0 + 1.8, y, st.zA0 + 2) * CFrame.Angles(0, rad(90), 0), {
		height = 16,
		color = C.Blue,
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
	local water = FALL_A
	local deep = DEEP
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
		local bank = if i == 1 then 2.2 else 3 -- (the first a hair wider than the fall's top sheet)
		local z0 = if i == 1 then s[1] else s[1] - 2
		b:box(`Bank{i}`, x0 - bank, top - 0.6, z0, x1 + bank, SAND_TOP, s[2] + 2, sand, Kit.NOSHADOW)
		b:box(`Water{i}`, x0, top - 0.35, s[1] - (if i == 1 then 0.3 else 0), x1, WATER_TOP, s[2], water, WATER_SHEET)
	end
	-- white water where the stream breaks over the lip into the fall
	for i, q in { { -8, -2.2, 0.9 }, { 2.5, 8.5, 1.3 } } do
		b:box(`LipFoam{i}`, q[1], top - 0.2, lipLz - 1.4, q[2], WATER_TOP + q[3], lipLz + 2.6, FOAM, WATER_SHEET)
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
	-- a lily pad (on the deep sheet's level), flowers on the banks
	for i, p in { { px - 6, pz0 + 8 } } do
		Kit.prop("lilyPad", parent, place(p[1], p[2], i * 40) * CFrame.new(0, WATER_TOP + 0.36 - top, 0), {
			seed = i * 5,
			scale = 1.2,
			flower = true,
		})
	end
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
	spring flows out of (a dark cave mouth, a little spout, a glowing crystal cluster on top, magic
	sparkles), a picnic grove in the back corner on the far bank (chunky blossom and fruit trees,
	a hammock between two of them, a blanket with a basket, flowers), a rope swing near the lip, a
	paved path from the lookout deck past the pool to the grotto and stepping stones across the
	stream.
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
	g:box("Rock3", px - 5, top + 14, gz + 4, px + 6, top + 18, gz + 11, STRATA[3])
	g:box("CaveFrame", px - 5.2, top - 0.5, gz - 0.7, px + 5.2, top + 7.6, gz + 0.2, STRATA[3])
	g:box("Cave", px - 4, top + 0.4, gz - 0.9, px + 4, top + 6.5, gz - 0.5, C.Dark, Kit.DECOR)
	local board = g:box("Board", px - 4.5, top + 8, gz + 1.3, px + 4.5, top + 10.8, gz + 2, C.Cream)
	Kit.sign(board, Enum.NormalId.Front, "РОДНИК", INK, nil, { pps = 30 })
	g:box("VineL", px - 13, top + 1.5, gz - 0.5, px - 10.5, top + 8.2, gz - 0.1, C.Leaf2, Kit.DECOR)
	g:box("VineR", px + 9, top + 3, gz - 0.5, px + 11, top + 8.2, gz - 0.1, C.Leaf1, Kit.DECOR)
	g:box("Spout", px - 2.5, top + 0.3, gz - 4, px + 2.5, top + 1.1, gz + 0.2, FALL_B, Kit.DECOR)
	g:box("SpoutFoam", px - 3.5, top + 0.55, gz - 5, px + 3.5, top + 1.5, gz - 3, FOAM, Kit.DECOR)
	g:finish(rock)
	local crystal = Kit.prop("crystalCluster", g.model, place(px + 1, gz + 7.5) * CFrame.new(0, 18, 0), {
		color = "cyan",
		scale = 0.8,
		seed = 4,
		light = true,
	})
	Kit.lights += 1
	if crystal.PrimaryPart then
		Kit.sparkles(crystal.PrimaryPart, C.WaterLight, { rate = 3, size = 0.6, lifetime = 2.5, speed = 2 })
	end
	-- the picnic grove on the far bank, in the mesa's back corner: chunky blossom and fruit
	-- trees, a striped hammock slung between two of them, a blanket with a basket, flowers
	local grove = {
		{ px - 27, pool.z1 + 2, "fruit", 1.5 },
		{ -31, lipLz + 26, "blossom", 1.4 },
		{ -36, pool.z1 + 4, "fruit", 1.45 },
		{ -36, pool.z1 + 18, "fruit", 1.45 },
		{ -20, pool.z1 + 26, "blossom", 1.5 },
	}
	for _, t in grove do
		Kit.voxelTree(parent, place(t[1], t[2], 15), t[3], { scale = t[4] })
	end
	local hz0, hz1 = pool.z1 + 4 + 1, pool.z1 + 18 - 1 -- (into the two trunks at lx -36)
	local hm = Kit.builder(parent, "Hammock", place(-36, (hz0 + hz1) / 2))
	local bed = hm:box("Bed", -1.4, 2.4, -(hz1 - hz0) / 2 + 1.6, 1.4, 2.9, (hz1 - hz0) / 2 - 1.6, C.Canvas)
	hm:box("Stripe", -1.5, 2.3, -1.2, 1.5, 3.0, 1.2, C.RoofRed, Kit.DECOR) -- 0.1 proud all round
	for i, sz in { -1, 1 } do
		local e = sz * ((hz1 - hz0) / 2 - 1.6)
		local a = (hm.cf * CFrame.new(0, 2.7, e)).Position
		local c = (hm.cf * CFrame.new(0, 4.6, sz * (hz1 - hz0) / 2)).Position
		Kit.ramp(hm.model, a, c, { width = 0.35, thick = 0.35, color = C.Rope, name = `Rope{i}`, extra = Kit.DECOR })
	end
	hm:finish(bed)
	local bl = Kit.builder(parent, "Blanket", place(-23, pool.z1 + 12, 20))
	local cloth = bl:box("Cloth", -3.5, -0.1, -3, 3.5, 0.25, 3, C.Red, Kit.NOSHADOW)
	bl:box("Stripe", -3.6, -0.08, -0.7, 3.6, 0.4, 0.7, C.Cream, Kit.DECOR) -- 0.15 over, 0.1 past the cloth
	bl:box("Basket", 1.2, 0.25, 0.8, 3, 1.6, 2.2, C.WoodLight)
	bl:box("Handle", 1.95, 1.6, 0.9, 2.25, 2.4, 2.1, C.Wood, Kit.DECOR)
	bl:finish(cloth)
	Kit.flowerMeadow(parent, place(-30, pool.z1 + 34), 27)
	-- a rope swing on an A-frame near the lip, left of the fall
	local sw = Kit.builder(parent, "Swing", place(-30, lipLz + 4))
	local post = sw:box("PostL", -5.2, -0.5, -0.6, -4, 11, 0.6, C.WoodLight)
	sw:box("PostR", 4, -0.5, -0.6, 5.2, 11, 0.6, C.WoodLight)
	sw:box("Bar", -5.8, 11, -0.8, 5.8, 12.2, 0.8, C.WoodDark)
	sw:box("RopeL", -1.6, 3, -0.12, -1.35, 11, 0.12, C.Rope, Kit.DECOR)
	sw:box("RopeR", 1.35, 3, -0.12, 1.6, 11, 0.12, C.Rope, Kit.DECOR)
	sw:box("Seat", -2, 2.6, -0.8, 2, 3.1, 0.8, C.WoodLight)
	sw:finish(post)
	-- a paved path from the lookout deck past the pool to the grotto (three long slabs, by turns
	-- light stone and cream, 0.08 apart in height where they overlap at the bends, 0.1+ under
	-- the deck), and stepping stones across the stream to the grove
	local walk = U.model(parent, "GrottoPath")
	local bends = { { st.bx0 + 4.5, st.zBack - 1 }, { 21, lipLz + 38 }, { 27, pool.z0 - 1 }, { 26, pool.z1 + 4 } }
	for i = 1, #bends - 1 do
		local a, c = bends[i], bends[i + 1]
		local dz = Vector3.new(c[1] - a[1], 0, c[2] - a[2]).Unit
		-- (each slab runs 2 studs on past its bends, under the next)
		local pa = (frame * CFrame.new(a[1] - dz.X * 2, top + 0.22 + (i % 2) * 0.08, a[2] - dz.Z * 2)).Position
		local pc = (frame * CFrame.new(c[1] + dz.X * 2, top + 0.22 + (i % 2) * 0.08, c[2] + dz.Z * 2)).Position
		Kit.ramp(walk, pa, pc, {
			width = 4.4,
			thick = 0.75,
			color = if i % 2 == 0 then mix(C.StoneLight, C.SandDark, 0.35) else C.StoneLight,
			name = `Slab{i}`,
			extra = Kit.NOSHADOW,
		})
	end
	local sb = Kit.builder(parent, "SteppingStones", frame)
	for i, p in { { -3, lipLz + 33 }, { -10, lipLz + 36 }, { -16, lipLz + 33 } } do
		sb:box(
			`Stone{i}`,
			p[1] - 1.7,
			top - 0.4,
			p[2] - 1.7,
			p[1] + 1.7,
			top + 0.95,
			p[2] + 1.7,
			if i % 2 == 0 then C.StoneLight else C.Stone,
			Kit.NOSHADOW
		)
	end
	sb:finish()
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
		b:box(`Ledge{i}`, lx - w / 2, y - 2.4, z0, lx + w / 2, y, fmax + 1, STRATA[floor(y / STRATUM) % 3 + 1])
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
	for i, p in { { -18, -6 } } do
		Kit.prop("lilyPad", model, pondCF * CFrame.new(p[1], 0, p[2]), { seed = i * 3, scale = 1.4 })
	end
	for i, a in { 215 } do -- (left of the path: the stepping stones run round the right)
		local r = site.pondRadius - 2
		local x = site.pondX + r * math.sin(rad(a + site.angle))
		local z = site.pondZ + r * math.cos(rad(a + site.angle))
		Kit.prop("reeds", model, CFrame.new(x, 0, z), { seed = i, scale = 1.3 })
	end
	for i, p in { { -24, 8, 7, 6, 1 }, { -36, 10, 8, 9, 1 }, { 54, 7, 6, 4, 22 } } do
		local lx = p[1]
		local f = if i == 5 then 0 else faceRange(lx - p[2] / 2, lx + p[2] / 2)
		local x, z = W(lx, f - p[3] / 2 - p[5])
		boulder2(model, Kit.ground(world, x, z, site.angle + i * 7), p[2], p[3], p[4])
	end
	-- the plunge pool's rim broken by rocks half in the water (the left and the front: the
	-- boardwalk runs round the right), reeds between them
	local pz0 = site.pondR - site.radius -- the pond centre (lz)
	for i, p in { { -27, pz0 + 12, 6, 3.4, 20 }, { -30, pz0 - 8, 5, 2.6, -15 }, { -19, pz0 - 25, 6.5, 3, 35 } } do
		local x, z = W(p[1], p[2])
		local g = max(world:heightAt(x, z), -1.5)
		local cf = CFrame.new(x, g, z) * CFrame.Angles(0, rad(site.angle + p[5]), 0)
		local rb = Kit.builder(model, "PoolRock", cf)
		local w = p[3]
		local rock = rb:box(
			"Rock",
			-w / 2,
			-1,
			-w * 0.4,
			w / 2,
			2.4 - g + p[4] * 0.3,
			w * 0.4,
			if i == 2 then C.StoneDark else C.Stone
		)
		rb:box(
			"RockTop",
			-w / 2 + 0.7,
			2.3 - g + p[4] * 0.3,
			-w * 0.4 + 0.5,
			w / 2 - 1.1,
			3.2 - g + p[4] * 0.3,
			w * 0.4 - 0.4,
			C.StoneLight,
			Kit.NOSHADOW
		)
		rb:finish(rock)
	end
	do
		local x, z = W(-25, pz0 - 17)
		local rb = Kit.builder(model, "Reeds", CFrame.new(x, 0, z) * CFrame.Angles(0, rad(site.angle), 0))
		local first = nil
		for i, q in { { -1.2, -0.4, 5.2 }, { 0.3, 0.6, 6.4 }, { 1.4, -0.6, 4.4 } } do
			local blade = rb:box(
				`Blade{i}`,
				q[1] - 0.25,
				-1.5,
				q[2] - 0.25,
				q[1] + 0.25,
				q[3],
				q[2] + 0.25,
				if i == 2 then C.Leaf1 else C.Leaf2,
				Kit.DECOR
			)
			first = first or blade
		end
		rb:box("Cattail", -0.05, 4.4, 0.25, 0.65, 6, 0.95, C.WoodDark, Kit.DECOR)
		rb:finish(first)
	end

	-- solid stairs up the cliff right of the fall, the upper flight hugging the face where it
	-- steps back (lx 23 to the mesa's side); the bastion at their top is the lookout
	local stairLo, stairFace = faceRange(FALL_W / 2 + 8, site.halfWidth)
	local st = cliffStairs(model, world, site, frame, fmin, stairLo, stairFace, FALL_W / 2 + 5)
	lookout(model, frame, st)
	-- a plank boardwalk from the promenade's path gap round the pond's sand rim to the foot of
	-- the stairs, level with the promenade (0.2 under its tiles), so the way in is a walk, not a
	-- drop onto the sand: straight runs that overlap at the bends (alternate runs 0.1 apart in
	-- height, no shared top faces), each a solid slab down into the sand (or 1.5 under the water)
	local walk = Kit.builder(model, "Boardwalk", frame)
	local pz = site.pondR - site.radius -- the pond centre (lz)
	local ez = st.zB0 - 8 -- over the first entry step, where the stairs' ramp meets the deck
	local route = { { 3.5, pz - 35.5 }, { 17, pz - 30 }, { 28, pz - 19 }, { 33, pz - 6 }, { st.footX - 1.2, ez } }
	local WALK_TOP = 4.4
	for i = 1, #route - 1 do
		local a, c = Vector3.new(route[i][1], 0, route[i][2]), Vector3.new(route[i + 1][1], 0, route[i + 1][2])
		local d = c - a
		-- (the first run starts 2.5 back under the promenade's tiles: no crack at its edge)
		local back = if i == 1 then 2.5 else 0
		local len = d.Magnitude + back + (if i < #route - 1 then 3.5 else 0)
		local lo = math.huge
		for t = 0, 1, 0.1 do
			for _, s in { -3.5, 0, 3.5 } do
				local p = a + d * t + Vector3.new(d.Z, 0, -d.X).Unit * s
				local wx, wz = W(p.X, p.Z)
				lo = min(lo, world:heightAt(wx, wz))
			end
		end
		local yTop = WALK_TOP + (i % 2) * 0.1
		lo = max(lo, 0) - 0.5 - (i % 2) * 0.1
		local mid = a + d.Unit * (len / 2 - back)
		walk:block(
			`Deck{i}`,
			Vector3.new(7, yTop - lo + 1, len),
			CFrame.lookAt(Vector3.new(mid.X, (yTop + lo - 1) / 2, mid.Z), Vector3.new(c.X, (yTop + lo - 1) / 2, c.Z)),
			if i % 2 == 0 then C.Plank else C.WoodLight
		)
	end
	walk:finish()
	local sx, sz = W(24, pz - 34)
	Kit.prop("signpost", model, Kit.ground(world, sx, sz, site.angle), {
		text = "СМОТРОВАЯ",
		width = 10,
		color = C.Cream,
		trim = C.WoodDark,
		arrow = "left",
	})

	-- the mesa top's destination
	mesaGarden(model, world, site, frame, lipLz, pool, st)

	-- mossy ledges and vine curtains on the cliffs (not behind the fall or the staircase)
	cliffLedges(model, frame, faceRange, {
		{ -30, 46, 10 },
		{ -44, 30, 8 },
		{ -26, 22, 9 },
	})
	mesaVines(model, world, site, function(lx: number, lz: number): boolean
		return (abs(lx) < FALL_W / 2 + 6 and lz < 24) or (lx > st.bx0 - 6 and lx < st.xl + 10 and lz < 24)
	end, 4)

	-- claims: the stream and pool, the garden, the stairs (the pond yard is reserved already)
	for _, c in streamClaims do
		local cx, cz = W(c[1], c[2])
		Kit.claim(cx, cz, c[3])
	end
	for _, c in
		{
			{ -28, lipLz + 30, 16 },
			{ pool.x, pool.z1 + 10, 18 },
			{ -30, lipLz + 4, 8 },
			{ -28, pool.z1 + 14, 18 },
			{ 26, pool.z0 - 10, 12 },
		}
	do
		local cx, cz = W(c[1], c[2])
		Kit.claim(cx, cz, c[3])
	end
	for x = st.bx0, st.xl, 12 do
		local qx, qz = W(x + 4, (st.zB0 + st.zBack) / 2)
		Kit.claim(qx, qz, 16)
	end
end

--------------------------------------------------------------------------------------------
-- Windmill
--------------------------------------------------------------------------------------------

--[[
	Flower and crop rows on the windmill hill's terraces, all round. The hill is a ziggurat of
	one-cell (8-stud) rings, 4 studs per ring, so the rows follow the rings: every cell whose
	outward direction is mostly along X takes a row along Z and vice versa, and runs of equal
	height merge into one long row (the straight faces of the hill give long rows, the diagonal
	corners short ones). Every other ring stays lawn, so the hill reads as terraced garden beds
	with grass between, and every row is green leaves with its colour on top, narrower (a planted
	bed, not a painted plank). By the cell's direction from the mill:
	  front (towards the lagoon and the stairs)  tulips on the two lower rings: segments of two
	                                             or three square bloom bunches (2.4, 1 apart, zig-
	                                             zag, two tints, two heights) on a strip of green
	                                             stems, 5-7 studs of grass between the segments;
	                                             pink, yellow by ring; the top ring stays lawn
	  sides                                      lavender (grey-green mounds with separate purple
	                                             spike tufts) on one side, tall sunflowers (a stem
	                                             hedge with separate straw-gold heads) on the other
	  back                                       golden wheat on every other planted ring; the
	                                             rings between hold the farm (see hillFarm)
	Lone cells on the sides and the back stay grass (a row needs two cells). Returns the cells
	left free on the back's farm rings: { x, z, h, d, a } (a: degrees from straight back).
]]
local function hillFields(parent: any, world: any, site: any, corridor: (number, number) -> boolean): { any }
	local model = U.model(parent, "Fields")
	local cell = world.cell
	local tulips = { C.Flowers[1], C.Flowers[3], C.Flowers[2], C.Flowers[4] }
	local lavenderLeaf = mix(C.Leaf1, C.StoneLight, 0.3)
	local lavender = mix(C.Purple, C.Cream, 0.12)
	local rr = Kit.rng(1351)
	local towards = Vector3.new(-site.x, 0, -site.z).Unit -- the lagoon direction
	local R = site.hillRadius
	local G = world.cfg.GroundTop
	local ix0, ix1 = floor((site.x - R) / cell), floor((site.x + R) / cell)
	local iz0, iz1 = floor((site.z - R) / cell), floor((site.z + R) / cell)
	local farm = {}
	-- a cell's row: height, row axis, zone, side (+1 / -1), ring level; nil = no row
	local function info(ix: number, iz: number): (number?, string?, string?, number?, number?)
		local x, z = (ix + 0.5) * cell, (iz + 0.5) * cell
		local dx, dz = x - site.x, z - site.z
		local d = sqrt(dx * dx + dz * dz)
		if d < site.topRadius + 5 or d > R - 4 or corridor(x, z) then
			return nil
		end
		local h = world:heightAt(x, z)
		if h <= G or world:kindAt(x, z) == "path" then
			return nil
		end
		local facing = (dx * towards.X + dz * towards.Z) / d
		local zone = if facing >= 0.45 then "front" elseif facing <= -0.45 then "back" else "side"
		local side = if dx * towards.Z - dz * towards.X > 0 then 1 else -1
		local level = floor((h - G) / 4)
		if level % 2 == 1 then -- (lawn between the beds; on the back, the farm)
			return nil
		end
		return h, if abs(dx) > abs(dz) then "z" else "x", zone, side, level
	end
	local used: { [number]: boolean } = {}
	local function row(
		name: string,
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		y0: number,
		y1: number,
		colour: any
	)
		local p = U.part(
			model,
			name,
			Vector3.new(x1 - x0, y1 - y0, z1 - z0),
			CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
			colour,
			nil,
			Kit.DECOR
		)
		p.Locked = true
	end
	for iz = iz0, iz1 do
		for ix = ix0, ix1 do
			local h, axis, zone, side, level = info(ix, iz)
			if not h or used[ix * 4096 + iz] then
				continue
			end
			local sx, sz = if axis == "x" then 1 else 0, if axis == "z" then 1 else 0
			local n = 1
			while true do
				local h2, a2, z2, s2 = info(ix + sx * n, iz + sz * n)
				if h2 == h and a2 == axis and z2 == zone and s2 == side then
					n += 1
				else
					break
				end
			end
			for k = 0, n - 1 do
				used[(ix + sx * k) * 4096 + iz + sz * k] = true
			end
			if n == 1 and zone ~= "front" then
				continue
			end
			-- the row's footprint: inset from the cell edges, long along the run
			local ax0, az0 = ix * cell, iz * cell
			local ax1, az1 = (ix + 1 + sx * (n - 1)) * cell, (iz + 1 + sz * (n - 1)) * cell
			local ex, ez = if axis == "x" then 0.9 else 1.4, if axis == "z" then 0.9 else 1.4
			local x0, x1, z0, z1 = ax0 + ex, ax1 - ex, az0 + ez, az1 - ez
			local lv = (level :: number) // 2
			-- along the row (a) and across it (b)
			local A0, A1 = if axis == "x" then x0 else z0, if axis == "x" then x1 else z1
			local B0, B1 = if axis == "x" then z0 else x0, if axis == "x" then z1 else x1
			local function strip(
				name: string,
				a0: number,
				a1: number,
				b0: number,
				b1: number,
				y0: number,
				y1: number,
				colour: any
			)
				if axis == "x" then
					row(name, a0, b0, a1, b1, y0, y1, colour)
				else
					row(name, b0, a0, b1, a1, y0, y1, colour)
				end
			end
			if zone == "front" then
				-- tulips in segments of two or three square bunches (2.4, 1 apart, zig-zag, two
				-- tints and two heights by turns) on a strip of green stems, 5-7 studs of grass
				-- between the segments: planted clumps, not stripes. The top ring stays lawn.
				if lv >= 3 then
					continue
				end
				local c1 = tulips[lv % #tulips + 1]
				local c2 = mix(c1, C.White, 0.22)
				local segs, pos = {}, A0 + 0.3
				while true do
					local room = A1 - 0.3 - pos
					local k = if room >= 9.8 then 3 elseif room >= 6.4 then 2 elseif room >= 3 then 1 else 0
					if k == 0 then
						break
					end
					local len = k * 3.4 - 0.4
					table.insert(segs, { pos, pos + len, k })
					pos += len + rr(5, 7)
				end
				local shift = if #segs > 0 then (A1 - 0.3 - segs[#segs][2]) / 2 else 0
				for si, sg in segs do
					local s0, s1 = sg[1] + shift, sg[2] + shift
					local bm = (B0 + B1) / 2
					strip("Stems", s0, s1, bm - 1.9, bm + 1.9, h - 0.2, h + 1.4, C.Leaf1)
					for k = 1, sg[3] do
						local c0 = s0 + 0.3 + (k - 1) * 3.4
						local odd = (k + si) % 2 == 1
						local top = h + 2.3 + (if odd then 0 else 0.6) + (k % 3) * 0.12
						local zig = if k % 2 == 0 then 0.45 else -0.45
						strip(
							"Tulips",
							c0,
							c0 + 2.4,
							bm + zig - 1.2,
							bm + zig + 1.2,
							h + 1.2,
							top,
							if odd then c1 else c2
						)
					end
				end
			elseif zone == "side" then
				-- lavender (a grey-green mound with separate purple spike tufts) on one side,
				-- sunflowers (a stem hedge with separate gold heads) on the other
				local lav = side == 1
				local inset = if lav then 0.4 else 0.6
				strip(
					if lav then "Lavender" else "SunStems",
					A0 + inset,
					A1 - inset,
					B0 + inset,
					B1 - inset,
					h - 0.2,
					h + (if lav then 1.8 else 2.9),
					if lav then lavenderLeaf else C.Leaf1
				)
				local k = math.clamp(floor((A1 - A0) / 6), 1, 2)
				for t = 1, k do
					local c = A0 + (A1 - A0) * (t - 0.5) / k + (if t % 2 == 0 then 0.4 else -0.3)
					if lav then
						local hi = h + 2.9 + (t % 2) * 0.4
						strip("LavenderSpikes", c - 1.1, c + 1.1, B0 + 1.6, B1 - 1.6, h + 1.6, hi, lavender)
					else
						local hi = h + 4.1 + (t % 2) * 0.4
						strip("Sunflower", c - 1.2, c + 1.2, B0 + 1.1, B1 - 1.1, h + 2.7, hi, C.Straw)
					end
				end
			elseif lv % 2 == 0 then
				-- golden wheat on the back (the rings between stay lawn or hold the farm)
				row("Wheat", x0 + 0.2, z0 + 0.2, x1 - 0.2, z1 - 0.2, h - 0.2, h + 2.6, C.Straw)
			end
		end
	end
	-- the farm rings: the back's cells between the crop rows, flat across the whole cell
	local back = Vector3.new(-towards.X, 0, -towards.Z)
	for iz = iz0, iz1 do
		for ix = ix0, ix1 do
			local x, z = (ix + 0.5) * cell, (iz + 0.5) * cell
			local dx, dz = x - site.x, z - site.z
			local d = sqrt(dx * dx + dz * dz)
			local h = world:heightAt(x, z)
			if d < site.topRadius + 6 or d > R - 8 or h <= G or corridor(x, z) then
				continue
			end
			local facing = (dx * back.X + dz * back.Z) / d
			if facing < 0.45 or floor((h - G) / 4) % 2 == 0 then
				continue
			end
			local flat = true
			for _, c in { { -3.5, -3.5 }, { 3.5, -3.5 }, { 3.5, 3.5 }, { -3.5, 3.5 } } do
				if world:heightAt(x + c[1], z + c[2]) ~= h then
					flat = false
				end
			end
			if flat then
				local a = deg(atan2(dx * back.Z - dz * back.X, dx * back.X + dz * back.Z))
				table.insert(farm, { x = x, z = z, h = h, d = d, a = a })
			end
		end
	end
	return farm
end

--[[
	Bush clumps and rocks at the foot of the windmill hill's risers on the lawn rings (the rings
	between the planted ones) at the front and the sides: their backs 0.3 into the riser towards
	the mill, a spread-out pick (22+ apart) of up to n, clear of the stairs. 2-3 parts each.
]]
local function hillDressing(parent: any, world: any, site: any, corridor: (number, number) -> boolean, n: number)
	local model = U.model(parent, "Dressing")
	local cell = world.cell
	local G = world.cfg.GroundTop
	local towards = Vector3.new(-site.x, 0, -site.z).Unit
	local r = Kit.rng(1871)
	local R = site.hillRadius
	local spots = {}
	for iz = floor((site.z - R) / cell), floor((site.z + R) / cell) do
		for ix = floor((site.x - R) / cell), floor((site.x + R) / cell) do
			local x, z = (ix + 0.5) * cell, (iz + 0.5) * cell
			local dx, dz = x - site.x, z - site.z
			local d = sqrt(dx * dx + dz * dz)
			local h = world:heightAt(x, z)
			if d > site.topRadius + 6 and d < R - 4 and h > G and not corridor(x, z) then
				local facing = (dx * towards.X + dz * towards.Z) / d
				if floor((h - G) / 4) % 2 == 1 and facing > -0.3 then
					local ux, uz = 0, 0
					if abs(dx) > abs(dz) then
						ux = if dx > 0 then -1 else 1
					else
						uz = if dz > 0 then -1 else 1
					end
					if world:heightAt(x + ux * cell, z + uz * cell) == h + 4 then
						table.insert(spots, { x = x, z = z, h = h, ux = ux, uz = uz, score = r() })
					end
				end
			end
		end
	end
	table.sort(spots, function(a, b)
		return a.score > b.score
	end)
	local placed = {}
	for _, s in spots do
		if #placed >= n then
			break
		end
		local ok = true
		for _, o in placed do
			if (o[1] - s.x) ^ 2 + (o[2] - s.z) ^ 2 < 22 * 22 then
				ok = false
				break
			end
		end
		if ok then
			table.insert(placed, { s.x, s.z })
			local wx, wz = s.x + s.ux * (cell / 2 + 0.3), s.z + s.uz * (cell / 2 + 0.3)
			local cf = CFrame.new(wx, s.h, wz) * CFrame.Angles(0, math.atan2(s.ux, s.uz), 0)
			local o = r(-1.5, 1.5)
			local kind = #placed % 3
			if kind == 0 then
				local b = Kit.builder(model, "Rocks", cf)
				local w = r(3, 4.2)
				local stone = b:box("Rock", o - w / 2, -0.6, -2.6, o + w / 2, r(1.8, 2.6), 0, C.Stone)
				b:box(
					"RockTop",
					o - w / 2 + 0.5,
					1.2,
					-2,
					o + w / 2 - 0.9,
					r(2.8, 3.3),
					0.1,
					C.StoneLight,
					Kit.NOSHADOW
				)
				b:finish(stone)
			else
				local b = Kit.builder(model, "Bush", cf)
				local w = r(4, 5.4)
				local bush = b:box("Leaves", o - w / 2, -0.4, -3, o + w / 2, r(2.8, 3.4), 0, C.Leaf1, Kit.DECOR)
				b:box("Top", o - w / 2 + 0.8, 2.2, -2.3, o + w / 2 - 1.2, r(3.9, 4.4), 0.1, C.Leaf3, Kit.DECOR)
				if kind == 1 then
					b:box("Bloom", o + w / 2 - 2.1, 2.3, -3.3, o + w / 2 - 0.8, 3.6, -2, C.Pink, Kit.DECOR)
				end
				b:finish(bush)
			end
		end
	end
	return model
end

-- Beehive on a little stand (4 parts): legs, a straw hive with an amber band, a plank roof.
local function beehive(parent: any, cf: any)
	local b = Kit.builder(parent, "Beehive", cf)
	local stand = b:box("Stand", -1.4, -0.4, -1.4, 1.4, 1.2, 1.4, C.WoodDark)
	b:box("Hive", -1.3, 1.2, -1.3, 1.3, 4, 1.3, C.Straw)
	b:box("Band", -1.45, 2.2, -1.45, 1.45, 2.8, 1.45, C.Twine, Kit.NOSHADOW)
	b:box("Roof", -1.8, 4, -1.8, 1.8, 4.6, 1.8, C.WoodDark, Kit.NOSHADOW)
	return b:finish(stand)
end

--[[
	The little farm on the back of the windmill hill, on the free rings between the crop rows:
	hay bales and a beehive. Each piece
	takes the free cell nearest its spot (degrees from straight back, distance from the mill).
]]
local function hillFarm(parent: any, site: any, cells: { any })
	local model = U.model(parent, "Farm")
	local pieces = {
		{ "hay", -22, 50 },
		{ "hive", 24, 50 },
	}
	local taken: { [any]: boolean } = {}
	for i, p in pieces do
		local best, bd = nil, math.huge
		for _, c in cells do
			if not taken[c] then
				local da = Kit.angleDistance(c.a, p[2]) * c.d * math.pi / 180
				local score = da * da + (c.d - p[3]) ^ 2
				if score < bd then
					best, bd = c, score
				end
			end
		end
		if not best then
			continue
		end
		taken[best] = true
		-- facing out along the ring (tangent), so rows and pieces line up with the terrace
		local yaw = deg(atan2(best.x - site.x, best.z - site.z)) + 90
		local cf = CFrame.new(best.x, best.h, best.z) * CFrame.Angles(0, rad(yaw), 0)
		if p[1] == "hive" then
			beehive(model, cf)
		else
			Kit.prop("hayBale", model, cf * CFrame.new(-1.6, 0, -0.4), { seed = i })
			Kit.prop("hayBale", model, cf * CFrame.new(2.2, 0, 0.6) * CFrame.Angles(0, rad(90), 0), { seed = i + 7 })
		end
	end
	return model
end

-- Chunky rail fence (posts + one thick rail per segment) along a polyline of ground points.
local function railFence(parent: any, points: { any }, name: string)
	local model = U.model(parent, name)
	for i, p in points do
		U.part(model, `Post{i}`, Vector3.new(1.4, 4, 1.4), CFrame.new(p + Vector3.new(0, 1.8, 0)), C.WoodDark)
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

--[[
	The hero windmill (frame cf on the top meadow, front = -Z towards the lagoon and the stairs),
	a tower mill in natural materials: a stone plinth one step up, a ground floor of warm stone,
	a dark timber band, two plaster tiers up to a pitched red cap whose gables face the sails, a
	bronze finial. Trim: dark timber frames, green shutters, a flower box. The ground floor is a
	real room (16 x 16, a stone floor, a plank ceiling, a millstone on its shaft, flour sacks, a
	lantern on a chain) with a door at the front (a little roof over it, a wall lantern beside it)
	and one at the back; behind it a wooden ladder (a climbable TrussPart) runs up to the plank
	balcony round the second tier (a 5-stud walkway): a timber parapet open at the ladder, a bench
	and a telescope at the front parapet looking out over the sails to the lagoon, petals drifting
	off it. The sails (canvas on a timber lattice, 56 across) are a child Model "Blades" spinning
	about the hub on its axle high over the balcony and out past its rim (attribute Spin,
	PrimaryPart = Hub, pivot LookVector = the axis; nothing in it collides). About 75 parts,
	53 studs to the finial.
]]
local function heroMill(parent: any, cf: any, spin: number): any
	local b = Kit.builder(parent, "Windmill", cf)
	local stone = mix(C.StoneLight, C.SandDark, 0.35)
	local plaster, roof, timber, shutter = C.Plaster, C.RoofRed, C.WoodDark, C.RoofGreen
	local plinth = b:box("Plinth", -11, -2, -11, 11, 1, 11, C.Stone)
	-- the room: stone walls 1.5 thick, a door (x ±2.6, up to y 9) in the front and the back wall;
	-- the timber door frames stand 0.1 into the openings and 0.1 under the lintels (no shared faces)
	b:box("WallL", -9.5, 1, -8, -8, 16, 8, stone)
	b:box("WallR", 8, 1, -8, 9.5, 16, 8, stone)
	for _, side in { { "Front", -1 }, { "Back", 1 } } do
		local s = side[2]
		local z0, z1 = min(s * 8, s * 9.5), max(s * 8, s * 9.5)
		local f0, f1 = min(s * 9.3, s * 9.9), max(s * 9.3, s * 9.9)
		b:box(`{side[1]}L`, -9.5, 1, z0, -2.6, 16, z1, stone)
		b:box(`{side[1]}R`, 2.6, 1, z0, 9.5, 16, z1, stone)
		b:box(`{side[1]}Lintel`, -2.6, 9, z0, 2.6, 16, z1, stone)
		b:box(`{side[1]}DoorL`, -3.6, 1, f0, -2.5, 10, f1, timber, Kit.NOSHADOW)
		b:box(`{side[1]}DoorR`, 2.5, 1, f0, 3.6, 10, f1, timber, Kit.NOSHADOW)
		b:box(`{side[1]}DoorTop`, -3.6, 8.9, f0, 3.6, 10, f1, timber, Kit.NOSHADOW)
	end
	-- a little roof over the front door, a wall lantern beside it
	wedge(b, "DoorRoof", Vector3.new(8.4, 1.6, 2.6), CFrame.new(0, 11, -10.75), roof)
	b:box("WallLampCap", 4.6, 8.4, -10.6, 6, 8.9, -9.4, timber, Kit.NOSHADOW)
	b:box("WallLamp", 4.8, 6.8, -10.4, 5.8, 8.4, -9.45, C.Glow, Kit.NEON_DECOR)
	b:box("Ceiling", -8, 13.4, -8, 8, 15, 8, C.WoodLight)
	-- inside (on the plinth's stone floor): a millstone on its shaft left of the way through,
	-- flour sacks on the right, a lantern on a chain from the ceiling
	b:block(
		"Millstone",
		Vector3.new(1.6, 5.2, 5.2),
		CFrame.new(-5, 1.8, 2.5) * CFrame.Angles(0, 0, rad(90)),
		C.StoneLight,
		{ Shape = Enum.PartType.Cylinder }
	)
	b:box("Shaft", -5.6, 2.6, 1.9, -4.4, 13.4, 3.1, timber, Kit.NOSHADOW)
	b:box("Sack1", 4.6, 1, -6.6, 6.8, 3.6, -4.4, C.Canvas)
	b:box("Sack2", 5, 1, -3.6, 7, 3, -1.6, C.Cream, Kit.NOSHADOW)
	b:box("Chain", -0.15, 11.4, -0.15, 0.15, 13.4, 0.15, C.Iron, Kit.DECOR)
	local lantern = b:box("Lantern", -0.9, 9.6, -0.9, 0.9, 11.4, 0.9, C.Glow, Kit.NEON_DECOR)
	Kit.light(lantern, 14, 1.2)
	b:box("Band", -10.2, 14.6, -10.2, 10.2, 16.8, 10.2, timber)
	b:box("Tower2", -8, 16.8, -8, 8, 30, 8, plaster)
	-- the balcony: a 5-stud walkway all round the top tier (bench and telescope at the parapet
	-- leave 3 free)
	b:box("Balcony", -12.5, 29.4, -12.5, 12.5, 30.6, 12.5, C.WoodLight)
	b:box("BalconyRim", -12.9, 28.8, -12.9, 12.9, 29.4, 12.9, timber, Kit.NOSHADOW)
	-- the balcony's parapet, open at the back where the ladder arrives (x 3.8..7.2)
	b:box("ParapetF", -12.5, 30.6, -12.5, 12.5, 32.2, -11.7, C.Wood)
	b:box("ParapetL", -12.5, 30.6, -11.7, -11.7, 32.2, 11.7, C.Wood)
	b:box("ParapetR", 11.7, 30.6, -11.7, 12.5, 32.2, 11.7, C.Wood)
	b:box("ParapetB", -12.5, 30.6, 11.7, 3.8, 32.2, 12.5, C.Wood)
	b:box("ParapetB2", 7.2, 30.6, 11.7, 12.5, 32.2, 12.5, C.Wood)
	b:box("Tower3", -6.5, 30.6, -6.5, 6.5, 42, 6.5, plaster)
	-- windows: dark frames round blue glass; the big front one has green shutters and a flower box
	local function window(name: string, x0: number, y0: number, x1: number, y1: number, face: number, axis: string)
		-- face: the wall's outer plane; the frame 0.45 proud of it, the glass 0.6
		local s = if face < 0 then -1 else 1
		local fa, fb = face, face + s * 0.45
		local ga, gb = face + s * 0.2, face + s * 0.6
		if axis == "z" then
			b:box(`{name}Frame`, x0 - 0.5, y0 - 0.5, min(fa, fb), x1 + 0.5, y1 + 0.5, max(fa, fb), timber, Kit.NOSHADOW)
			b:box(`{name}`, x0, y0, min(ga, gb), x1, y1, max(ga, gb), C.WindowBlue, Kit.NOSHADOW)
		else
			b:box(`{name}Frame`, min(fa, fb), y0 - 0.5, x0 - 0.5, max(fa, fb), y1 + 0.5, x1 + 0.5, timber, Kit.NOSHADOW)
			b:box(`{name}`, min(ga, gb), y0, x0, max(ga, gb), y1, x1, C.WindowBlue, Kit.NOSHADOW)
		end
	end
	window("Window1", -1.7, 20.4, 1.7, 25, -8, "z")
	window("Window2", -1.4, 33.4, 1.4, 36.8, -6.5, "z")
	window("Window5", -1.7, 20.4, 1.7, 25, 8, "z")
	window("Window3", -1.6, 5, 1.6, 9.6, 9.5, "x")
	window("Window4", -1.6, 5, 1.6, 9.6, -9.5, "x")
	for i, sx in { -1, 1 } do
		b:box(`Shutter{i}`, sx * 2.3 - 0.9, 19.9, -8.55, sx * 2.3 + 0.9, 25.5, -8.15, shutter, Kit.NOSHADOW)
	end
	b:box("FlowerBox", -2.8, 18.9, -9.4, 2.8, 19.9, -8, C.Wood, Kit.NOSHADOW)
	b:box("Flowers", -2.5, 19.9, -9.1, 2.5, 20.8, -8.3, C.Flowers[1], Kit.DECOR)
	-- the cap: a pitched red roof whose gables face the sails, on a dark eaves course, a hatch in
	-- the front gable, a bronze finial on the ridge
	b:box("Eaves", -7.2, 41.4, -7.2, 7.2, 42.4, 7.2, timber)
	gable(b, "Roof", -8.4, 8.4, -8.4, 8.4, 42.4, 8.4, roof, true)
	b:box("Ridge", -0.7, 50.4, -8.8, 0.7, 51.4, 8.8, timber, Kit.NOSHADOW)
	b:box("Hatch", -1.4, 43.6, -8.6, 1.4, 46.6, -8.2, timber, Kit.NOSHADOW)
	b:box("Finial", -0.6, 51.4, -0.6, 0.6, 53.2, 0.6, BRASS, Kit.NOSHADOW)
	-- a telescope at the front of the balcony against the parapet, looking out over it
	local y = 30.6
	telescope(b, 5, y, -11.1)
	b:finish(plinth)
	Kit.bench(b.model, cf * CFrame.new(-4.5, y, -10.6), { length = 5, color = C.WoodLight, legs = timber })
	-- the ladder up the back to the balcony gap: a climbable wooden truss (Roblox sizes trusses
	-- in 2-stud steps), standing on the meadow just outside the balcony's rim
	U.partCount += 1
	U.new("TrussPart", {
		Name = "Ladder",
		Size = Vector3.new(2, 32, 2),
		CFrame = cf * CFrame.new(5.5, 16, 14),
		Color = C.Wood,
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanTouch = false,
		Locked = true,
	}, b.model)
	-- petals drifting off the balcony over the flower hill
	Kit.petals(b.model.Balcony, { rate = 3, box = true, wind = Vector3.new(1.6, 0, 0.8) })
	-- the sails: a timber hub on a round axle out of the top tier, two crossed arms, four canvas
	-- sails on the trailing side of their arms with a lattice bar each (an X at rest). The axle
	-- runs 7.7+ over the balcony floor (above Window2, under the cap's overhang) and the hub
	-- starts past the parapet, so nothing turns through the walkway or a player's head; the arms
	-- and sails turn 2.6+ outside the balcony's rim. The client spins the group, so none of it
	-- collides (DESIGN.md: spinners never shove a player).
	local hubCF = cf * CFrame.new(0, 40, -10)
	local blades = Kit.builder(b.model, "Blades", hubCF * CFrame.Angles(0, 0, rad(45)))
	blades.model:SetAttribute("Spin", spin)
	local spinning = { CanCollide = false, CanQuery = false }
	local hub = blades:box("Hub", -1.7, -1.7, -6.9, 1.7, 1.7, -2.5, timber, spinning)
	blades:block("Axle", Vector3.new(6.7, 2.2, 2.2), CFrame.new(0, 0, 0.75) * CFrame.Angles(0, rad(90), 0), C.Wood, {
		Shape = Enum.PartType.Cylinder,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
	blades:box("HubCap", -1, -1, -7.9, 1, 1, -6.9, BRASS, Kit.DECOR)
	blades:box("ArmX", -27, -0.7, -6.6, 27, 0.7, -5.5, timber, Kit.DECOR)
	blades:box("ArmY", -0.7, -27, -6.65, 0.7, 27, -5.45, timber, Kit.DECOR)
	local sails = {
		{ 4, 26, 0.5, 6, "x" },
		{ -26, -4, -6, -0.5, "x" },
		{ -6, -0.5, 4, 26, "y" },
		{ 0.5, 6, -26, -4, "y" },
	}
	for i, q in sails do
		blades:box(`Sail{i}`, q[1], q[3], -6.3, q[2], q[4], -5.7, C.Canvas, Kit.DECOR)
		if q[5] == "x" then
			local xm = (q[1] + q[2]) / 2
			blades:box(`Lattice{i}`, xm - 0.45, q[3] - 0.1, -6.75, xm + 0.45, q[4] + 0.1, -6.2, C.Wood, Kit.DECOR)
		else
			local ym = (q[3] + q[4]) / 2
			blades:box(`Lattice{i}`, q[1] - 0.1, ym - 0.45, -6.75, q[2] + 0.1, ym + 0.45, -6.2, C.Wood, Kit.DECOR)
		end
	end
	blades.model.PrimaryPart = hub
	hub.PivotOffset = hub.CFrame:Inverse() * hubCF -- pivot: the hub, LookVector = the axis
	return b.model
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
	-- the hero mill on the meadow, its open doorway facing the stairs (the plinth is a 1-stud step)
	local mill = heroMill(model, Kit.facing(site.x, topY, site.z, 0, 0), 20)
	hillFarm(model, site, hillFields(model, world, site, corridor))
	hillDressing(model, world, site, corridor, 5)
	-- stairs from the hill foot up to the top meadow (Kit.stairs adds a first step if needed):
	-- chunky 2-stud steps, an invisible ramp over their nosings so the climb is a walk
	local foot = Vector3.new(site.x - ux * (site.hillRadius + 4), 0, site.z - uz * (site.hillRadius + 4))
	local summit = Vector3.new(site.x - ux * (site.topRadius - 2), 0, site.z - uz * (site.topRadius - 2))
	local stairs = Kit.stairs(model, world, foot, summit, {
		width = 8,
		tread = 4,
		rise = 2,
		color = mix(C.StoneLight, C.SandDark, 0.3),
		color2 = C.Cobble,
		name = "Stairs",
	})
	if stairs then
		-- one ramp over the nosings of every run of evenly spaced steps (a longer tread, where
		-- the stairs follow a flat bit of the hill, is walked on itself): from one tread before
		-- the run's first step (one rise down) to the run's last step's front edge
		local dir = Vector3.new(ux, 0, uz) -- (up the stairs: from the foot towards the mill)
		local steps = {}
		for _, s in stairs:GetChildren() do
			local p = s.CFrame.Position
			local along = (p - foot):Dot(dir) - s.Size.Z / 2
			table.insert(steps, { s = along, top = p.Y + s.Size.Y / 2 })
		end
		table.sort(steps, function(a, b)
			return a.s < b.s
		end)
		local i, k = 1, 0
		while i <= #steps do
			local j = i
			while j < #steps and abs(steps[j + 1].s - steps[j].s - 4) < 0.01 do
				j += 1
			end
			local first, last = steps[i], steps[j]
			local a = foot + dir * (first.s - 4) + Vector3.new(0, first.top - 2, 0)
			local c = foot + dir * last.s + Vector3.new(0, last.top, 0)
			k += 1
			Kit.ramp(stairs, a, c, { width = 8, thick = 0.4, invisible = true, name = `Ramp{k}` })
			i = j + 1
		end
	end
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
	local gapHalf, posts = 15, 6
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

--[[
	The fun way down from the treehouse: a terracotta chute with dark timber side walls from the
	open front corner of the deck (right of the hut, where its door opens) out over the meadow to
	the ground, about 38 degrees, resting on timber posts where it runs high. 3-6 parts.
]]
local function treeSlide(parent: any, world: any, tree: any)
	local deck = tree:FindFirstChild("Deck", true)
	if not deck then
		return
	end
	local cf, size = deck.CFrame, deck.Size
	-- the open stretch of the deck's front edge right of the hut (prop x 9.4..13.2 of 14)
	local top = (cf * CFrame.new(size.X / 2 * 11.3 / 14, size.Y / 2, -size.Z / 2)).Position
	local dir = (cf.LookVector + cf.RightVector * 0.35).Unit
	local dirXZ = Vector3.new(dir.X, 0, dir.Z).Unit
	-- the foot: the first point out where the drop is at most 0.8 per stud
	local foot = nil
	for run = 20, 90, 2 do
		local q = top + dirXZ * run
		local g = world:heightAt(q.X, q.Z) + 0.6
		if (top.Y - g) / run <= 0.8 then
			foot = Vector3.new(q.X, g, q.Z)
			break
		end
	end
	if not foot then
		return
	end
	local m = U.model(parent, "Slide")
	local side = Vector3.new(-dirXZ.Z, 0, dirXZ.X)
	Kit.ramp(m, top, foot, { width = 3.6, thick = 0.8, color = C.RoofTerracotta, name = "Chute" })
	for i, sx in { -1, 1 } do
		local off = side * (sx * 2.1) + Vector3.new(0, 1, 0)
		Kit.ramp(m, top + off, foot + off, {
			width = 0.6,
			thick = 1.8,
			color = C.WoodDark,
			name = `Wall{i}`,
			extra = Kit.NOSHADOW,
		})
	end
	for i, t in { 0.25, 0.55, 0.8 } do
		local q = top:Lerp(foot, t)
		local g = world:heightAt(q.X, q.Z)
		if q.Y - 1 - g > 3 then
			U.part(
				m,
				`Post{i}`,
				Vector3.new(1.4, q.Y - 0.8 - g + 1, 1.4),
				CFrame.new(q.X, (q.Y - 0.8 + g - 1) / 2, q.Z),
				C.Wood
			)
		end
	end
	for _, t in { 0.4, 0.7, 1, 1.15 } do
		local q = top:Lerp(foot, t)
		Kit.claim(q.X, q.Z, 6)
	end
end

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
	local opts = { scale = 1.25, roof = C.RoofTerracotta, name = "Tree" }
	local tree = Kit.prop("giantTree", model, treeCF, opts)
	local h = heightAbove(tree, topY)
	if h < GIANT_TREE_HEIGHT * 0.92 then
		tree:Destroy()
		opts.scale = 1.25 * GIANT_TREE_HEIGHT / h
		tree = Kit.prop("giantTree", model, treeCF, opts)
	end
	treeSlide(model, world, tree)
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
		cheeks:box(`Cheek{i}`, min(x0, x1), lo - 1, -along + 8, max(x0, x1), topY - 1.4, 0, C.Dirt)
		cheeks:box(`CheekTop{i}`, min(x0, x1), topY - 1.4, -along + 8, max(x0, x1), topY - 0.4, 0, C.GrassTop3)
	end
	cheeks:finish()
	-- a glowing giant mushroom beside the tree
	for i, spec in { { 33, -66, true } } do
		local m = Kit.prop("giantMushroom", model, at(spec[1], spec[2]), {
			glow = true,
			light = spec[3],
			seed = i,
			scale = 1.1,
		})
		if spec[3] then
			Kit.lights += 1
		end
		-- fireflies drifting round the glowing cap
		local cap = m:FindFirstChild("Cap", true)
		if cap then
			Kit.sparkles(cap, mix(C.Glow, C.Lime, 0.4), { rate = 2, size = 0.6, lifetime = 6, speed = 0.6, box = true })
		end
	end
	-- lantern posts lining the way in, flowers
	for _, spec in { { 40, -13 }, { 40, 13 } } do
		lanternPost(model, at(spec[1], spec[2]), 4)
	end
	Kit.flowerMeadow(model, at(36, -40), 3)
	Kit.claim(site.x, site.z, site.plateauRadius + 2)
	-- the steps and their cheek blocks (no flowers growing through them)
	for _, r in { site.plateauRadius - 4, site.plateauRadius + 4, site.plateauRadius + 12 } do
		Kit.claim(site.x - ux * r, site.z - uz * r, 11)
	end
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

-- Canvas tent (5 parts), front = -Z (the door): stepped canvas, a ridge stripe in `color`.
local function tent(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Tent", cf)
	local base = b:box("Floor", -3.4, -0.2, -3.6, 3.4, 0.25, 3.6, C.WoodDark)
	b:box("Low", -3.2, 0.25, -3.4, 3.2, 2.4, 3.4, C.Canvas)
	b:box("Mid", -2.2, 2.4, -3.4, 2.2, 4.0, 3.4, Kit.shade(C.Canvas, 0.94))
	b:box("Top", -1.1, 4.0, -3.4, 1.1, 5.2, 3.4, color)
	b:box("Door", -1.2, 0.25, -3.55, 1.2, 3.0, -3.3, C.Dark, Kit.DECOR)
	return b:finish(base)
end

-- Big chunky flag on a 2-stud pole (front = -Z, the flag flies along local +X). 6 parts.
local function bigFlag(parent: any, cf: any, h: number, w: number, fh: number, color: any)
	local b = Kit.builder(parent, "Flag", cf)
	local foot = b:box("Foot", -1.8, -0.6, -1.8, 1.8, 0.8, 1.8, C.StoneLight)
	b:pole("Pole", 1.8, 0, 0, 0.8, h, C.WoodLight)
	b:box("Top", -1.1, h, -1.1, 1.1, h + 1.8, 1.1, BRASS, Kit.DECOR)
	b:box("Cloth", 0.9, h - fh - 0.4, -0.3, 0.9 + w, h - 0.4, 0.3, color, Kit.DECOR)
	b:box("Stripe", 1.0, h - fh * 0.62 - 0.4, -0.42, 0.8 + w, h - fh * 0.38 - 0.4, 0.42, C.Cream, Kit.DECOR)
	b:box("Tail", 0.9 + w, h - fh * 0.8 - 0.4, -0.3, 2.6 + w, h - fh * 0.2 - 0.4, 0.3, color, Kit.DECOR)
	return b:finish(foot)
end

-- the ramps on the trail's risers: a shade under Ground.luau's path cap
local TRAIL_TAN = Kit.shade(mix(C.SandDark, C.Cobble, 0.15), 0.95)

--[[
	Walkable ramps on the trail's risers: the carved ledge climbs in 4-stud steps between 8-stud
	cells, so every riser between two trail cells gets a path-tan Wedge in the lower cell, its tall
	back face against the higher cell (collinear risers of the same step merge into one wedge).
	The climb is a walk, not 33 jumps. Returns the wedges' footprints {x0, z0, x1, z1} (the other
	trail dressing keeps off them).
]]
local function trailRamps(parent: any, world: any, site: any): { { number } }
	local model = U.model(parent, "Ramps")
	local cell = world.cell
	local R = site.mountainRadius + cell
	local ix0, ix1 = floor((site.x - R) / cell), floor((site.x + R) / cell)
	local iz0, iz1 = floor((site.z - R) / cell), floor((site.z + R) / cell)
	local function trail(ix: number, iz: number): boolean
		return world:kindAtCell(ix, iz) == "path"
	end
	-- the raw rise from cell (ix, iz) to its neighbour in direction (dx, dz): 4 or 8 between
	-- trail cells, else 0
	local function step(ix: number, iz: number, dx: number, dz: number): number
		local jx, jz = ix + dx, iz + dz
		local summitCell = world:kindAtCell(jx, jz) == "snow" and world:topAtCell(jx, jz) == site.summitTop
		if not trail(ix, iz) or not (trail(jx, jz) or summitCell) then
			return 0
		end
		local dh = world:topAtCell(ix + dx, iz + dz) - world:topAtCell(ix, iz)
		return if dh == 4 or dh == 8 then dh else 0
	end
	-- the uphill direction of the trail at a cell (its nearest centreline point)
	local pts = site.trail
	local function uphill(ix: number, iz: number): (number, number)
		local x, z = (ix + 0.5) * cell, (iz + 0.5) * cell
		local best, bi = math.huge, 1
		for i, p in pts do
			local d2 = (p[1] - x) ^ 2 + (p[2] - z) ^ 2
			if d2 < best then
				best, bi = d2, i
			end
		end
		local a, b = pts[max(bi - 1, 1)], pts[min(bi + 1, #pts)]
		return b[1] - a[1], b[2] - a[2]
	end
	local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
	-- a cell with risers on two sides (a diagonal bend) keeps only the one facing up the trail,
	-- so ramps never cross into ridges and pits
	local kept: { [number]: number } = {}
	local function rise(ix: number, iz: number, dx: number, dz: number): number
		local dh = step(ix, iz, dx, dz)
		if dh == 0 then
			return 0
		end
		local key = ix * 4096 + iz
		if kept[key] == nil then
			local ux, uz = uphill(ix, iz)
			local bestDot, bestK = -math.huge, 0
			for k, d in DIRS do
				local dot = d[1] * ux + d[2] * uz
				if step(ix, iz, d[1], d[2]) > 0 and dot > bestDot then
					bestDot, bestK = dot, k
				end
			end
			kept[key] = bestK
		end
		local d = DIRS[kept[key]]
		return if d and d[1] == dx and d[2] == dz then dh else 0
	end
	local rects = {}
	for _, d in DIRS do
		local dx, dz = d[1], d[2]
		local tx, tz = abs(dz), abs(dx) -- along the riser
		for iz = iz0, iz1 do
			for ix = ix0, ix1 do
				local dh = rise(ix, iz, dx, dz)
				local h = world:topAtCell(ix, iz)
				-- start of a run of collinear risers of the same step
				local function same(jx: number, jz: number): boolean
					return rise(jx, jz, dx, dz) == dh and world:topAtCell(jx, jz) == h
				end
				if dh > 0 and not same(ix - tx, iz - tz) then
					local m = 1
					while same(ix + m * tx, iz + m * tz) do
						m += 1
					end
					local depth = min(cell - 1, 1.5 * dh) -- 4 high, 6 deep: a 34-degree ramp
					-- the riser plane, the ramp's centre (0.1 sunk into the higher cell)
					local ex = if dx > 0 then (ix + 1) * cell elseif dx < 0 then ix * cell else nil
					local ez = if dz > 0 then (iz + 1) * cell elseif dz < 0 then iz * cell else nil
					local along = (0.1 - depth) / 2
					local cx = if ex then ex + dx * along else (ix + m / 2) * cell
					local cz = if ez then ez + dz * along else (iz + m / 2) * cell
					local c = Vector3.new(cx, h + (dh - 0.2) / 2, cz)
					U.wedge(
						model,
						"Ramp",
						Vector3.new(m * cell, dh + 0.2, depth + 0.1),
						CFrame.lookAt(c, c - Vector3.new(dx, 0, dz)), -- back (+Z) towards the riser
						TRAIL_TAN
					)
					local hx, hz =
						if ex then (depth + 0.1) / 2 else m * cell / 2, if ez then (depth + 0.1) / 2 else m * cell / 2
					table.insert(rects, { cx - hx, cz - hz, cx + hx, cz + hz })
				end
			end
		end
	end
	return rects
end

--[[
	Dressing of the spiral trail VoxelWorld carves into the main peak (site.trail: centreline
	points {x, z, h} every ~2 studs from the foot to the flat snowy summit; 4-stud steps): the
	riser ramps (trailRamps), a roofed timber gate with a «ВЕРШИНА» board where the trail leaves
	the path, chunky lantern posts on the outer edge every ~30 studs (every other one with a short
	timber rail along the drop where a level is long enough), pennants between them, leafy curtains
	on the inner rock wall and a rest bench half way up on the inner side. Everything stands on
	the trail's own cells clear of the ramps (a spot is only used when the ground under its
	whole footprint is the ledge at that point), on the edges, so the ledge stays free to walk.
]]
local function trailDressing(parent: any, world: any, site: any)
	local model = U.model(parent, "Trail")
	local ramps = trailRamps(model, world, site)
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
	-- is the ground under a square of half size r round (x, z) all the ledge at height `top`, clear
	-- of the riser ramps?
	local function onLedge(x: number, z: number, r: number, top: number): boolean
		for _, c in { { -r, -r }, { r, -r }, { r, r }, { -r, r }, { 0, 0 } } do
			local xx, zz = x + c[1], z + c[2]
			if world:heightAt(xx, zz) ~= top or world:kindAt(xx, zz) ~= "path" then
				return false
			end
		end
		for _, q in ramps do
			if x + r > q[1] - 0.3 and x - r < q[3] + 0.3 and z + r > q[2] - 0.3 and z - r < q[4] + 0.3 then
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
			-- a timber gate on stone footings under a little slate roof, the board hanging from
			-- its beam, a lantern under each end of the beam
			local b = Kit.builder(model, "Arch", cf)
			local half, top = 8.6, 12
			for k, sx in { -1, 1 } do
				local w = (cf * CFrame.new(sx * half, 0, 0)).Position
				local g = world:heightAt(w.X, w.Z) - q.top
				b:box(`Footing{k}`, sx * half - 1.6, g - 0.6, -1.6, sx * half + 1.6, g + 1.6, 1.6, C.Stone)
				b:box(`Post{k}`, sx * half - 1, g + 1.6, -1, sx * half + 1, top, 1, C.Wood)
				b:box(
					`Lamp{k}`,
					sx * (half - 1.8) - 0.6,
					top - 1.6,
					-0.6,
					sx * (half - 1.8) + 0.6,
					top,
					0.6,
					C.Glow,
					Kit.NEON_DECOR
				)
			end
			b:box("Beam", -half - 1.8, top, -1.3, half + 1.8, top + 1.6, 1.3, C.WoodDark)
			gable(b, "Roof", -half - 2.6, half + 2.6, -2.6, 2.6, top + 1.6, 2.6, C.RoofSlate)
			local board = b:box("Board", -5.6, top - 4.6, -0.5, 5.6, top - 1.2, 0.5, C.Cream)
			b:box("BoardBack", -6, top - 5, -0.3, 6, top, 0.3, C.WoodDark)
			Kit.sign(board, Enum.NormalId.Front, "ВЕРШИНА", INK, nil, { pps = 24 })
			Kit.sign(board, Enum.NormalId.Back, "ВЕРШИНА", INK, nil, { pps = 24 })
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
					local post = rb:box("Post", -0.7, -0.6, -0.7, 0.7, 3.6, 0.7, C.Wood)
					rb:box("Cap", -0.95, 3.6, -0.95, 0.95, 4.2, 0.95, C.WoodDark, Kit.NOSHADOW)
					local a, bb = Vector3.new(x, q.top + 3, z), Vector3.new(x2, q.top + 3, z2)
					local mid = (a + bb) / 2
					rb:block(
						"Rail",
						Vector3.new(0.9, 0.9, (bb - a).Magnitude + 0.6),
						rb.cf:Inverse() * CFrame.lookAt(mid, bb),
						C.Wood,
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
				local cols = { C.Festive[1], C.Festive[2], C.Festive[4], C.Festive[6] }
				pennant(model, facing(x, q.top, z, q.nx, q.nz), cols[(k // 2) % 4 + 1], 9)
			end
		end
		s += 40
	end

	-- leafy curtains on the inner rock wall (green and flowering streaks on the grey stone): the
	-- faces where a trail cell meets a mountain column at least 8 higher, a spread-out pick
	local cell = world.cell
	local faces = {}
	local R = site.mountainRadius
	for iz = floor((site.z - R) / cell), floor((site.z + R) / cell) do
		for ix = floor((site.x - R) / cell), floor((site.x + R) / cell) do
			if world:kindAtCell(ix, iz) == "path" then
				local h = world:topAtCell(ix, iz)
				for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
					local nh = world:topAtCell(ix + d[1], iz + d[2])
					if world:kindAtCell(ix + d[1], iz + d[2]) ~= "path" and nh - h >= 8 then
						table.insert(faces, { ix = ix, iz = iz, dx = d[1], dz = d[2], h = h, top = nh })
					end
				end
			end
		end
	end
	local blooms = { C.Flowers[3], C.Flowers[2], C.Flowers[4], C.Blossom1 }
	local VINES = 5
	for v = 1, min(VINES, #faces) do
		-- (spread evenly over the faces in scan order)
		local f = faces[floor((v - 0.5) * #faces / VINES) + 1]
		-- the face plane, a vine hanging from its top edge 0.35 proud of it
		local fx = (f.ix + 0.5 + f.dx * 0.5) * cell - f.dx * 0.35
		local fz = (f.iz + 0.5 + f.dz * 0.5) * cell - f.dz * 0.35
		local drop = min(f.top - f.h - 2, 7 + (v % 3) * 2.5)
		local w = 3 + (v % 2) * 1.5
		U.part(
			model,
			"Vine",
			Vector3.new(if f.dx ~= 0 then 0.8 else w, drop, if f.dz ~= 0 then 0.8 else w),
			CFrame.new(fx, f.top - drop / 2 + 0.2, fz),
			if v % 2 == 0 then C.Leaf1 else C.Leaf2,
			nil,
			Kit.DECOR
		)
		if v % 3 == 1 then
			U.part(
				model,
				"Bloom",
				Vector3.new(if f.dx ~= 0 then 1 else 2, 1.6, if f.dz ~= 0 then 1 else 2),
				CFrame.new(fx - f.dx * 0.2, f.top - drop * 0.4, fz - f.dz * 0.2),
				blooms[(v // 3) % #blooms + 1],
				nil,
				Kit.DECOR
			)
		end
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
-- where the trail arrives): a stone plinth and a plank deck flush on the snow, timber rails with
-- an opening (lantern posts) at the front, a big flag, a telescope at
-- the front corner and a «ВЕРШИНА» board under a little roof at the back facing the arrival.
local function summitDeck(parent: any, _world: any, cf: any, D: number)
	local b = Kit.builder(parent, "SummitDeck", cf)
	local y = 0.9 -- deck top above the snow (two 0.45 steps)
	b:box("Plinth", -D - 1.2, -1.4, -D - 1.2, D + 1.2, 0.45, D + 1.2, C.StoneLight)
	local deck = b:box("Deck", -D, -0.8, -D, D, y, D, C.WoodLight)
	for i, p in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		-- (0.2 proud of the rails on every side: no shared faces)
		local px, pz = p[1] * (D - 0.9), p[2] * (D - 0.9)
		b:box(`Corner{i}`, px - 1.1, y, pz - 1.1, px + 1.1, y + 4, pz + 1.1, C.WoodDark)
	end
	local railC = C.Wood
	local ry0, ry1 = y + 2.7, y + 3.5
	local gap = 4
	b:box("RailBack", -D, ry0, D - 0.8, D, ry1, D, railC, Kit.NOSHADOW)
	b:box("RailL", -D, ry0, -D, -D + 0.8, ry1, D, railC, Kit.NOSHADOW)
	b:box("RailR", D - 0.8, ry0, -D, D, ry1, D, railC, Kit.NOSHADOW)
	-- (the front rails end 0.1 inside the gate posts: no shared end faces)
	b:box("RailFront", -D, ry0, -D, -gap - 0.1, ry1, -D + 0.8, railC, Kit.NOSHADOW)
	b:box("RailFrontB", gap + 0.1, ry0, -D, D, ry1, -D + 0.8, railC, Kit.NOSHADOW)
	-- lantern posts framing the way in
	for i, sx in { -1, 1 } do
		local x = sx * (gap + 0.8)
		b:box(`GatePost{i}`, x - 0.8, y, -D - 0.2, x + 0.8, y + 5, -D + 1.4, C.Wood)
		b:box(`GateLamp{i}`, x - 0.9, y + 5, -D - 0.3, x + 0.9, y + 6.8, -D + 1.5, C.Glow, Kit.NEON)
		b:box(`GateCap{i}`, x - 1.2, y + 6.8, -D - 0.6, x + 1.2, y + 7.4, -D + 1.8, C.WoodDark, Kit.NOSHADOW)
	end
	-- telescope on the front-left corner, looking out
	telescope(b, -D + 3.5, y, -D + 3.5)
	-- «ВЕРШИНА» board on posts under a little slate roof at the back, facing the arrival
	local board = b:box("Board", -6, y + 4.2, D - 1.7, 6, y + 8.6, D - 1, C.RoofBlue)
	b:box("BoardPostL", -6.8, y, D - 1.9, -5.6, y + 9, D - 0.8, C.WoodDark)
	b:box("BoardPostR", 5.6, y, D - 1.9, 6.8, y + 9, D - 0.8, C.WoodDark)
	gable(b, "BoardRoof", -7.6, 7.6, D - 3, D + 0.3, y + 9, 1.6, C.RoofSlate)
	Kit.sign(board, Enum.NormalId.Front, "ВЕРШИНА", C.White, C.Navy, { pps = 24 })
	b:finish(deck)
	local function on(lx: number, lz: number, yaw: number?): any
		return cf * CFrame.new(lx, y, lz) * CFrame.Angles(0, rad(yaw or 0), 0)
	end
	local flag = bigFlag(b.model, on(D - 4, D - 4.5, 0), 24, 10, 6, C.Red)
	Kit.sparkles(flag.Top, C.GoldLight, { rate = 3, size = 0.8, lifetime = 3, speed = 2 }) -- the goal glints
	return b.model
end

local function buildPeaks(root: any, cfg: any, world: any)
	local model = U.model(root, "Peaks")
	-- (the other mountains are scenery: no flag on a summit nobody can reach)
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
		local pad = pb:box("Pad", -padHX, padLo - 1.5, -padHZ, padHX, padTop, padHZ, C.Plank)
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
		-- two tents at the back, the campfire in front of them
		local fireX, fireZ = 0, -2
		tent(camp, at(-5, 5, toward(-5, 5, fireX, fireZ)), C.RoofTerracotta)
		tent(camp, at(6, 4, toward(6, 4, fireX, fireZ)), C.RoofGreen)
		local fire = Kit.builder(camp, "Campfire", at(fireX, fireZ))
		local ring = fire:box("Stones", -2.4, -0.4, -2.4, 2.4, 0.7, 2.4, C.StoneLight)
		fire:box("LogA", -1.9, 0.7, -0.45, 1.9, 1.5, 0.45, C.Bark)
		fire:box("LogB", -0.45, 1.5, -1.9, 0.45, 2.2, 1.9, C.Bark)
		local flame = fire:box("Flame", -0.8, 1.4, -0.8, 0.8, 3.4, 0.8, C.Flame, Kit.NEON_DECOR)
		Kit.light(flame, 14, 1.2)
		Kit.smoke(flame)
		Kit.sparkles(flame, C.Autumn2, { rate = 4, size = 0.4, lifetime = 1.4, speed = 5, drift = 2 })
		fire:finish(ring)
		local wx, wz = Kit.radial(site.angle, site.radius, padLx, padLz)
		Kit.claim(wx, wz, 20)
	end
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
	summitDeck(model, world, Kit.facing(cx, topY, cz, tx, tz), half)
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
