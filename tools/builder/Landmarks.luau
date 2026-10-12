--[[
	Landmarks — dressing of the four landmark sites of World v3 (world.landmarks, DESIGN.md §5/§6),
	built into Map.Landmarks:

	  Waterfall  a Props.waterfall pouring off the mesa's lagoon-facing cliff into the pond; on
	             the mesa top a spring pool (sand rim, rocks, lily pads, a bench and a cherry
	             tree) feeding a stream that meanders in 8-stud blocks between sand banks to the
	             lip; moss ledges and hanging vines on the sandstone cliffs; lily pads / reeds /
	             boulders in the pond yard; a zigzag wooden staircase (4 flights, landings,
	             rails, lanterns) from the yard up the cliff to a lookout deck jutting out over
	             the edge (telescope, bench, flag, sign).
	  Windmill   a big Props.windmill (spinning "Blades") on the ziggurat top, set low so its
	             plinth is a small step; rainbow tulip rows (green stems + blooms) on the
	             lagoon-facing terraces, walkable stairs up the terraces, a chunky rail fence
	             round the edge of the top meadow (a walkway all round the mill), hay crates and
	             barrels.
	  GiantTree  Props.giantTree (treehouse, swing, lanterns) on the meadow plateau, steps up
	             from the path, glowing giant mushrooms, a ring of small mushrooms, torches,
	             a picnic table.
	  Peaks      the main Peak is climbable: a base camp on a flat pad at the end of its path
	             (watchtower, tents, campfire, logs, signpost), a switchback boardwalk (sloped
	             flights, landings, red rails, lantern posts) up the camp-facing flank, and a
	             summit lookout deck (big flag, snowman, cairn, telescope, sign). Chunky flags
	             and cairns on the two smaller peaks. The pines on the slopes come from Nature.

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
local SANDSTONE = rgb(232, 178, 112) -- the mesa cliff (Ground paints its walls in this family)
local SANDSTONE_DARK = rgb(206, 148, 90)

--------------------------------------------------------------------------------------------
-- Waterfall
--------------------------------------------------------------------------------------------

-- Wooden zigzag stairs against the cliff (radial frame of the site, lz outwards): two lanes in
-- front of the face, 4 flights running along lx between x0 and x1, landings at both ends; the
-- top landing is the lookout deck (built by `lookout`). Returns the lane z-ranges and heights.
local function zigzagStairs(parent: any, world: any, site: any, frame: any, faceLz: number, x0: number, x1: number)
	local b = Kit.builder(parent, "CliffStairs", frame)
	local laneW = 5.6
	local zA1, zA0 = faceLz - 0.8, faceLz - 0.8 - laneW -- lane A: next to the cliff
	local zB1, zB0 = zA0 - 0.6, zA0 - 0.6 - laneW -- lane B: lagoon side
	local landW = 7 -- landing length along lx
	local function groundAt(lx: number, lz: number): number
		local wx, wz = Kit.radial(site.angle, site.radius, lx, lz)
		return world:heightAt(wx, wz)
	end
	local y0 = groundAt(x0 + 2, (zA0 + zA1) / 2)
	local flights, steps = 4, 7
	local yTopAll = site.cliffTop + 0.4 -- the lookout deck sits a hair above the mesa top
	local riseTotal = yTopAll - y0
	local run = x1 - x0
	local tread = run / steps
	local rise = riseTotal / flights / steps
	local ramp = { Transparency = 1, CastShadow = false, CanQuery = false }
	local railC = C.Red
	local landingYs = {}
	for f = 1, flights do
		landingYs[f] = y0 + f * riseTotal / flights
	end
	-- landings 1..3 (odd ones at the x1 end); the 4th is the lookout deck
	for f = 1, flights - 1 do
		local y = landingYs[f]
		local atEnd = f % 2 == 1
		local lx0 = if atEnd then x1 else x0 - landW
		local lx1 = if atEnd then x1 + landW else x0
		b:box(`Landing{f}`, lx0, y - 1.2, zB0, lx1, y, zA1, C.WoodLight)
		b:box(`LandingEdge{f}`, lx0 - 0.2, y - 1.7, zB0 - 0.3, lx1 + 0.2, y - 1.1, zA1 - 0.2, C.WoodDark, Kit.NOSHADOW)
		b:box(`LandingRail{f}`, lx0, y + 2.6, zB0 - 0.1, lx1, y + 3.3, zB0 + 0.6, railC, Kit.NOSHADOW)
		local endX = if atEnd then lx1 - 0.6 else lx0
		b:box(`LandingRailEnd{f}`, endX, y + 2.6, zB0, endX + 0.6, y + 3.3, zA1, railC, Kit.NOSHADOW)
	end
	-- support posts with lanterns at the outer corners of the landing columns
	for i, spec in
		{ { x1 + landW - 0.8, landingYs[3] }, { x1 + 0.8, landingYs[3] }, { x0 - landW + 0.8, landingYs[2] } }
	do
		local px, ytop = spec[1], spec[2]
		local g = groundAt(px, zB0 + 0.8)
		b:box(`Post{i}`, px - 0.9, g - 1, zB0 - 0.15, px + 0.9, ytop + 3.4, zB0 + 1.6, C.WoodDark)
		b:box(`PostLamp{i}`, px - 0.9, ytop + 3.4, zB0 - 0.1, px + 0.9, ytop + 5.2, zB0 + 1.7, C.Glow, Kit.NEON)
		b:box(`PostCap{i}`, px - 1.2, ytop + 5.2, zB0 - 0.4, px + 1.2, ytop + 5.8, zB0 + 2.0, railC, Kit.NOSHADOW)
	end
	-- flights: sawtooth steps, an invisible ramp over the nosings (smooth walking up ~1.9-stud
	-- steps), a sloped rail on the lagoon side
	for f = 1, flights do
		local laneA = f % 2 == 1
		local z0, z1 = if laneA then zA0 else zB0, if laneA then zA1 else zB1
		local yStart = if f == 1 then y0 else landingYs[f - 1]
		local yEnd = landingYs[f]
		local up = f % 2 == 1 -- odd flights climb towards x1
		for s = 1, steps do
			local yTop = yStart + s * rise
			local xa = if up then x0 + (s - 1) * tread else x1 - s * tread
			local bottom = if f == 1 and s <= 2 then y0 - 1 else yTop - 2.6
			b:box(`Step{f}_{s}`, xa, bottom, z0, xa + tread, yTop, z1, if s % 2 == 1 then C.WoodLight else C.Wood)
		end
		-- the ramp runs from the floor one tread before the flight to the last nosing
		local dir = if up then 1 else -1
		local startX = if up then x0 - tread else x1 + tread
		local endX = if up then x1 - tread else x0 + tread
		local slope = math.atan((yEnd - yStart) / run)
		local length = run / math.cos(slope)
		local mid = Vector3.new((startX + endX) / 2, (yStart + yEnd) / 2 - 0.2, (z0 + z1) / 2)
		b:block(
			`Ramp{f}`,
			Vector3.new(length, 0.4, z1 - z0),
			CFrame.new(mid) * CFrame.Angles(0, 0, dir * slope),
			C.WoodLight,
			ramp
		)
		-- a stringer on the lagoon side hides the sawtooth underside
		local smid = Vector3.new((x0 + x1) / 2, (yStart + yEnd) / 2 - 0.6, z0 - 0.1)
		b:block(
			`Stringer{f}`,
			Vector3.new(length, 3.2, 0.6),
			CFrame.new(smid) * CFrame.Angles(0, 0, dir * slope),
			C.WoodDark,
			Kit.NOSHADOW
		)
		-- rail on the lagoon side of the flight (over the steps' outer edge)
		local rmid = Vector3.new((x0 + x1) / 2, (yStart + yEnd) / 2 + 3.2, z0 + 0.3)
		b:block(
			`Rail{f}`,
			Vector3.new(length, 0.7, 0.6),
			CFrame.new(rmid) * CFrame.Angles(0, 0, dir * slope),
			railC,
			Kit.NOSHADOW
		)
	end
	b:finish()
	return { zA0 = zA0, zA1 = zA1, zB0 = zB0, zB1 = zB1, y0 = y0, top = yTopAll }
end

-- The lookout deck = the top landing of the stairs: lx from x0 - 14 to x0, jutting out from
-- the mesa top over the cliff on two tall stilts; railings, telescope, bench, flag.
local function lookout(parent: any, world: any, site: any, frame: any, faceLz: number, x0: number, lanes: any)
	local y = lanes.top
	local b = Kit.builder(parent, "Lookout", frame)
	local xa, xb = x0 - 14, x0
	local zFront, zBack = lanes.zB0, faceLz + 6
	local deck = b:box("Deck", xa, y - 1.2, zFront, xb, y, zBack, C.WoodLight)
	b:box("DeckEdge", xa - 0.3, y - 1.8, zFront - 0.3, xb + 0.3, y - 1.1, zBack - 0.2, C.WoodDark, Kit.NOSHADOW)
	for i, x in { xa + 1, xb - 1 } do
		local wx, wz = Kit.radial(site.angle, site.radius, x, zFront + 1)
		local g = world:heightAt(wx, wz)
		b:box(`Stilt{i}`, x - 0.9, g - 1, zFront + 0.1, x + 0.9, y - 1.1, zFront + 1.9, C.WoodDark)
		b:box(`Brace{i}`, x - 0.6, y - 9, zFront + 1.9, x + 0.6, y - 7.6, faceLz + 0.5, C.WoodDark, Kit.NOSHADOW)
	end
	-- railing: front, the free left side, and over lane A on the right (lane B is the way in)
	local railC = C.Red
	b:box("RailFront", xa, y + 2.6, zFront - 0.1, xb, y + 3.4, zFront + 0.6, railC, Kit.NOSHADOW)
	b:box("RailL", xa, y + 2.6, zFront, xa + 0.7, y + 3.4, faceLz, railC, Kit.NOSHADOW)
	b:box("RailR", xb - 0.7, y + 2.6, lanes.zA0, xb, y + 3.4, faceLz, railC, Kit.NOSHADOW)
	for i, p in { { xa, zFront }, { xb - 1.1, zFront }, { xa, faceLz - 1.1 }, { xb - 1.1, lanes.zA0 } } do
		b:box(`RailPost{i}`, p[1] - 0.15, y, p[2] - 0.15, p[1] + 1.25, y + 3.9, p[2] + 1.25, C.White)
	end
	-- coin telescope looking at the lagoon
	local tx, tz = xa + 4, zFront + 2.5
	b:box("ScopePost", tx - 0.35, y, tz - 0.35, tx + 0.35, y + 3.2, tz + 0.35, C.Navy)
	b:box("Scope", tx - 0.9, y + 3.2, tz - 1.6, tx + 0.9, y + 4.4, tz + 0.8, C.Yellow)
	b:box("ScopeLens", tx - 0.6, y + 3.4, tz - 1.9, tx + 0.6, y + 4.2, tz - 1.55, C.Cyan, Kit.DECOR)
	b:finish(deck)
	-- bench facing the lagoon, flag on the back corner
	Kit.prop("bench", b.model, frame * CFrame.new(xa + 9.5, y, zFront + 4.5), { length = 6 })
	Kit.prop("flagPole", b.model, frame * CFrame.new(xa + 1.6, y, zBack - 1.6) * CFrame.Angles(0, rad(90), 0), {
		height = 16,
		color = C.Cyan,
	})
	return b.model
end

--[[
	The mesa top: a spring pool at the head of a stream that meanders to the lip in 8-stud blocks
	between sand banks (no kerbs; foam only at the lip). Pool and stream are water sheets a hair
	above sand slabs, which sit a hair above the grass (>= 0.2 apart, nothing coplanar).
	Returns the claim circles (lx, lz, r) in the site frame.
]]
local function mesaStream(parent: any, world: any, site: any, frame: any, lipLz: number): { { number } }
	local top = site.cliffTop
	local b = Kit.builder(parent, "Stream", frame)
	local water = rgb(70, 190, 250)
	local deep = rgb(52, 166, 236)
	local sand, sandDark = C.Sand, C.SandDark
	local SAND_TOP, WATER_TOP = top + 0.25, top + 0.5
	-- meander: {lz0, lz1, lx centre, width}; the mouth is as wide as the fall
	local segs = {
		{ lipLz - 1.5, lipLz + 9, 0, 16 },
		{ lipLz + 9, lipLz + 17, -4, 10 },
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
	-- foam where the stream tips over the lip
	b:box("Foam", -7.5, WATER_TOP - 0.05, lipLz - 1.6, 7.5, WATER_TOP + 0.6, lipLz + 0.8, C.Foam, Kit.DECOR)
	-- the spring pool: two overlapping sheets for a rounded voxel outline on a sand rim, a
	-- deeper middle, a bubbling spring at the back
	local pz0, pz1, px = lipLz + 55, lipLz + 81, 6
	b:box("PoolRim", px - 17, top - 0.6, pz0 - 1, px + 17, SAND_TOP, pz1 + 3, sand, Kit.NOSHADOW)
	b:box("PoolRimB", px - 13, top - 0.8, pz0 - 4, px + 13, SAND_TOP - 0.15, pz1 + 6, sandDark, Kit.NOSHADOW)
	b:box("Pool", px - 14, top - 0.3, pz0 + 2, px + 14, WATER_TOP, pz1, water, WATER_SHEET)
	b:box("PoolB", px - 10.3, top - 0.4, pz0, px + 10.3, WATER_TOP + 0.02, pz1 + 2.4, water, WATER_SHEET)
	b:box("PoolDeep", px - 7, top - 0.2, pz0 + 7, px + 7, WATER_TOP + 0.15, pz1 - 4, deep, WATER_SHEET)
	b:box("Spring", px - 2, WATER_TOP, pz1 - 2, px + 2, WATER_TOP + 1.2, pz1 + 2, C.Foam, Kit.DECOR)
	b:box("Spring2", px - 1, WATER_TOP + 1.1, pz1 - 1, px + 1, WATER_TOP + 2.1, pz1 + 1, C.WaterLight, Kit.DECOR)
	b:finish()

	local function place(lx: number, lz: number, yaw: number?): any
		return frame * CFrame.new(lx, top, lz) * CFrame.Angles(0, rad(yaw or 0), 0)
	end
	-- rocks round the spring, cream pebbles on the banks, lily pads, flowers, a bench by the pool
	Kit.prop("boulder", parent, place(px + 18, pz1 + 2, 30) * CFrame.new(0, -0.3, 0), {
		seed = 3,
		moss = true,
		color = SANDSTONE,
	})
	Kit.prop("boulder", parent, place(px - 4, pz1 + 10, 75) * CFrame.new(0, -0.3, 0), {
		seed = 8,
		moss = true,
		scale = 1.25,
		color = SANDSTONE,
	})
	Kit.prop("rock", parent, place(px - 19, pz0 + 4), { seed = 5, count = 3, color = SANDSTONE })
	Kit.prop("rock", parent, place(-20, lipLz + 28), { seed = 11, count = 3, color = C.Cream })
	Kit.prop("rock", parent, place(6, lipLz + 14), { seed = 12, count = 2, color = C.Cream })
	for i, p in { { px - 6, pz0 + 8 }, { px + 7, pz0 + 14 }, { px - 3, pz1 - 6 } } do
		Kit.prop("lilyPad", parent, place(p[1], p[2], i * 40) * CFrame.new(0, WATER_TOP - top, 0), {
			seed = i * 5,
			scale = 1.2,
			flower = i ~= 2,
		})
	end
	Kit.flowerMeadow(parent, place(-16, lipLz + 44), 21)
	Kit.flowerMeadow(parent, place(px + 22, pz0 + 12), 23)
	Kit.prop("bench", parent, place(px - 20, pz0 + 16, -90), { length = 6, seed = 4 })
	Kit.prop("cherryTree", parent, place(px - 26, pz1 + 4), { seed = 17, scale = 1.2 })
	return {
		{ -6, lipLz + 12, 14 },
		{ -8, lipLz + 34, 15 },
		{ 2, lipLz + 52, 14 },
		{ px - 4, (pz0 + pz1) / 2, 30 },
	}
end

--[[
	Moss and vines on the mesa's cliffs: finds the vertical faces of the voxel columns (a column
	of the top or the side ledge whose neighbour on the lagoon side is much lower) and hangs
	leafy vine blocks (two greens) from their top edge, flush with the face, plus a few mossy
	sandstone ledges half way down the tallest walls. Skips the fall and the staircase.
]]
local function mesaVines(parent: any, world: any, site: any, skip: (number, number) -> boolean)
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
	local vines, ledges = 0, 0
	for _, f in faces do
		if vines >= 12 then
			break
		end
		-- the face plane and its tangent direction
		local fx, fz = f.cx + f.nx * cell / 2, f.cz + f.nz * cell / 2
		local tx, tz = f.nz, f.nx -- along the face (axis-aligned)
		local w = floor(r(2, 4.99)) + 0.5
		local off = r(-(cell / 2 - w / 2 - 0.3), cell / 2 - w / 2 - 0.3)
		local len = min(f.drop - 3, r(6, 15))
		local cxv, czv = fx + tx * off + f.nx * 0.35, fz + tz * off + f.nz * 0.35
		local sizeX = if tx ~= 0 then w else 0.9
		local sizeZ = if tz ~= 0 then w else 0.9
		vines += 1
		U.part(
			model,
			"Vine",
			Vector3.new(sizeX, len, sizeZ),
			CFrame.new(cxv, f.top - len / 2 + 0.25, czv),
			if vines % 2 == 0 then C.Leaf1 else C.Leaf0,
			nil,
			Kit.DECOR
		)
		-- a shorter, lighter tuft beside some vines (the voxel "shading" of hanging leaves)
		if vines % 3 == 0 then
			local o2 = off + (if off > 0 then -w / 2 - 1 else w / 2 + 1)
			local cx2, cz2 = fx + tx * o2 + f.nx * 0.3, fz + tz * o2 + f.nz * 0.3
			U.part(
				model,
				"Tuft",
				Vector3.new(if tx ~= 0 then 2 else 0.8, len * 0.45, if tz ~= 0 then 2 else 0.8),
				CFrame.new(cx2, f.top - len * 0.225 + 0.2, cz2),
				C.Leaf2,
				nil,
				Kit.DECOR
			)
		end
		-- mossy sandstone ledges jutting out half way down the tallest walls
		if f.drop >= 30 and ledges < 5 and vines % 2 == 1 then
			ledges += 1
			local y = f.top - f.drop * r(0.45, 0.65)
			local lo = -off * 0.6
			local lw = 5
			local lcx, lcz = fx + tx * lo + f.nx * 1.0, fz + tz * lo + f.nz * 1.0
			local lsx = if tx ~= 0 then lw else 2.2
			local lsz = if tz ~= 0 then lw else 2.2
			U.part(model, "Ledge", Vector3.new(lsx, 2, lsz), CFrame.new(lcx, y, lcz), SANDSTONE_DARK)
			U.part(
				model,
				"Moss",
				Vector3.new(lsx + 0.3, 0.7, lsz + 0.3),
				CFrame.new(lcx, y + 1.2, lcz),
				C.GrassTop,
				nil,
				Kit.NOSHADOW
			)
		end
	end
	return model
end

local function buildWaterfall(root: any, cfg: any, world: any, site: any)
	local model = U.model(root, "Waterfall")
	local frame = Kit.radialCFrame(site.angle, site.radius, 0, 0, 0)
	local function W(lx: number, lz: number): (number, number)
		return Kit.radial(site.angle, site.radius, lx, lz)
	end
	-- the cliff face (the jagged voxel edge): first lz where the mesa top begins, per lx
	local function faceAt(lx: number): number
		for lz = -20, 30, 1 do
			local x, z = W(lx, lz)
			if world:heightAt(x, z) >= site.cliffTop - 16 then -- the top or the side ledge
				return lz
			end
		end
		return 0
	end
	local function faceMin(a: number, b: number): number
		local m = math.huge
		for lx = a, b, 2 do
			m = min(m, faceAt(lx))
		end
		return m
	end
	local function faceMax(a: number, b: number): number
		local m = -math.huge
		for lx = a, b, 2 do
			m = max(m, faceAt(lx))
		end
		return m
	end

	-- the fall: from the lip (a little behind the edge) into the pond
	local lipLz = faceMax(-10, 10) + 1.5
	local tx, tz = W(0, lipLz)
	local bx, bz = W(0, -(site.radius - site.pondR) + site.pondRadius - 4)
	Kit.prop(
		"waterfall",
		model,
		Vector3.new(tx, site.cliffTop, tz),
		Vector3.new(bx, 0, bz),
		20,
		{ seed = 7, puffs = 6 }
	)
	-- the mesa top: spring pool and meandering stream
	local streamClaims = mesaStream(model, world, site, frame, lipLz)

	-- the pond yard: lily pads, reeds, boulders at the cliff foot
	local pondCF = CFrame.new(site.pondX, 0, site.pondZ) * CFrame.Angles(0, rad(site.angle), 0)
	local pads = { { -16, -8 }, { -20, 4 }, { -8, -18 }, { 14, -14 }, { 19, -2 }, { -14, 12 } }
	for i, p in pads do
		Kit.prop("lilyPad", model, pondCF * CFrame.new(p[1], 0, p[2]), { seed = i * 3, scale = 1.4 })
	end
	for i, a in { 205, 150, 300 } do
		local r = site.pondRadius - 2
		local x = site.pondX + r * math.sin(rad(a + site.angle))
		local z = site.pondZ + r * math.cos(rad(a + site.angle))
		Kit.prop("reeds", model, CFrame.new(x, 0, z), { seed = i, scale = 1.3 })
	end
	for i, p in { { -15, -3 }, { 15, -4 }, { -26, -6 } } do
		local x, z = W(p[1], faceAt(p[1]) + p[2])
		-- sunk a little, so the boulder's skirt never sits flush with a terrace top
		Kit.prop(
			"boulder",
			model,
			Kit.ground(world, x, z, i * 50) * CFrame.new(0, -0.3, 0),
			{ seed = 40 + i, moss = i == 2, scale = 1.2 }
		)
	end

	-- stairs up the cliff (right side, +lx); their top landing is the lookout deck
	local sx0, sx1 = 27, 49
	local face = faceMin(sx0 - 16, sx1 + 8)
	local lanes = zigzagStairs(model, world, site, frame, face, sx0, sx1)
	lookout(model, world, site, frame, face, sx0, lanes)
	local sx, sz = W(sx0 - 3, lanes.zB0 - 5)
	Kit.prop("signpost", model, Kit.ground(world, sx, sz, site.angle), {
		text = "СМОТРОВАЯ ↑",
		width = 8,
		color = C.Cream,
		trim = C.Red,
	})

	-- moss and vines on the cliffs (not behind the fall, not behind the staircase)
	mesaVines(model, world, site, function(lx: number, lz: number): boolean
		return (abs(lx) < 16 and lz < 24) or (lx > sx0 - 20 and lx < sx1 + 14 and lz < 24)
	end)

	-- claims: the stream and pool, the lookout and the stairs (the pond yard is reserved already)
	for _, c in streamClaims do
		local cx, cz = W(c[1], c[2])
		Kit.claim(cx, cz, c[3])
	end
	local qx, qz = W((sx0 + sx1) / 2 - 4, face)
	Kit.claim(qx, qz, 34)
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

local function buildGiantTree(root: any, cfg: any, world: any, site: any)
	local model = U.model(root, "GiantTree")
	local topY = world:heightAt(site.x, site.z)
	local lagoonA = deg(atan2(-site.x, -site.z))
	local function at(r: number, a: number, yaw: number?): any
		local aa = rad(lagoonA + a)
		local px, pz = site.x + r * math.sin(aa), site.z + r * math.cos(aa)
		return CFrame.new(px, world:heightAt(px, pz), pz) * CFrame.Angles(0, aa + rad(yaw or 0), 0)
	end
	-- the tree faces the lagoon (ladder and swing towards the path)
	Kit.prop("giantTree", model, Kit.facing(site.x, topY, site.z, 0, 0), { scale = 1.25, roof = C.Blue, name = "Tree" })
	-- steps up from the path onto the plateau
	local ux, uz = site.x / site.radius, site.z / site.radius
	local a = Vector3.new(site.x - ux * (site.plateauRadius + 12), 0, site.z - uz * (site.plateauRadius + 12))
	local b = Vector3.new(site.x - ux * (site.plateauRadius - 8), 0, site.z - uz * (site.plateauRadius - 8))
	Kit.stairs(model, world, a, b, { width = 12, color = C.WoodLight, color2 = C.Wood, name = "Steps" })
	-- glowing giant mushrooms round the tree, a fairy ring of small ones
	for i, spec in { { 30, 55, true }, { 32, -70, true } } do
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
	for k = 0, 1 do
		Kit.prop("mushroom", model, at(22, -140 + k * 24), { seed = k + 5, scale = 1.3 })
	end
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
	Switchback boardwalk up the camp-facing flank of a mountain, in the CliffStairs style (site
	frame: lz outwards, so the camp is at -lz and the summit at +lz). Flights run along lx,
	alternating direction, each a sloped plank deck with a dark skirt and a red rail on its open
	(camp) side; a landing at every turn joins a flight to the next lane further up, with a
	chunky lantern post down to the ground on its outer corner. The voxel cone is steep (about
	1.6 : 1) and jagged, so the plan is a small depth-first search: every lane as close to the
	summit as the ground allows, the turn points free to slide sideways, each flight as gentle
	as possible — and never below the ground under it (backtracking when a lane leads nowhere).
	The last flight ends on a walkway onto the summit deck.
	o: cx (summit lx), y0 (camp pad top), padEdge (lz of the pad's mountain-side edge), deckY
	   (summit deck top), deckFront (lz of the deck's front edge), deckHalf (its half size).
	Returns the model, the flights and the claim circles (lx, lz, r).
]]
local function mountainTrail(parent: any, world: any, site: any, frame: any, o: { [string]: number })
	local W, Lw, GAP = 7, 7, 1 -- lane width, landing length, gap between lanes
	local R0, MAX_SLOPE, CLR = 10, 0.66, 0.4
	local cx, D = o.cx, o.deckHalf
	local function ground(lx: number, lz: number): number
		local x, z = Kit.radial(site.angle, site.radius, lx, lz)
		return world:heightAt(x, z)
	end
	-- highest ground over an lx/lz rectangle (sampled every 1.5 studs)
	local function maxGround(x0: number, x1: number, z0: number, z1: number): number
		local m = -math.huge
		local nx = max(1, math.ceil(abs(x1 - x0) / 1.5))
		local nz = max(1, math.ceil(abs(z1 - z0) / 1.5))
		for i = 0, nx do
			for j = 0, nz do
				m = max(m, ground(x0 + (x1 - x0) * i / nx, z0 + (z1 - z0) * j / nz))
			end
		end
		return m
	end
	-- smallest rise for a flight on lane lz from xs (at height y) to xe that keeps the deck above
	-- the ground; nil when the start itself is buried
	local function minRise(lz: number, xs: number, xe: number, y: number): number?
		local n = math.ceil(abs(xe - xs))
		local need = 0
		for k = 0, n do
			local t = k / n
			local x = xs + (xe - xs) * t
			for _, dz in { -W / 2 + 0.3, 0, W / 2 - 0.3 } do
				local g = ground(x, lz + dz) + CLR
				if k == 0 then
					if g > y then
						return nil
					end
				else
					need = max(need, (g - y) / t)
				end
			end
		end
		return need
	end

	-- plan (depth-first, bounded)
	local nodes = 0
	local plan = {}
	local function search(prevLz: number, y: number, dir: number, xs: number): boolean
		nodes += 1
		if nodes > 12000 then
			return false
		end
		local remaining = o.deckY - y
		local finalXe = cx + dir * (D - W)
		local final = (finalXe - xs) * dir > 10 and remaining <= abs(finalXe - xs) * MAX_SLOPE + 1e-6
		local zMin = prevLz + W + GAP
		local zMax = o.deckFront - W / 2 - 0.5
		if not final then
			zMax = min(zMax, zMin + 16)
		end
		if zMin > zMax then
			return false
		end
		local lx0, lx1 = min(xs, xs - dir * Lw), max(xs, xs - dir * Lw)
		local ends = if final then { finalXe } else { xs + dir * 28, xs + dir * 24, xs + dir * 32, xs + dir * 20 }
		for z = zMax, zMin, -1 do
			if maxGround(lx0, lx1, prevLz - W / 2, z + W / 2) <= y - CLR then
				for _, xe in ends do
					if abs(xe - cx) <= 26 then
						local need = minRise(z, xs, xe, y)
						if need and final then
							if need <= remaining then
								table.insert(plan, { lz = z, xs = xs, xe = xe, y0 = y, y1 = o.deckY, dir = dir })
								return true
							end
						elseif need then
							local R = max(R0, need)
							local Rhi = min(abs(xe - xs) * MAX_SLOPE, remaining - 3)
							while R <= Rhi + 1e-6 do
								table.insert(plan, { lz = z, xs = xs, xe = xe, y0 = y, y1 = y + R, dir = dir })
								if search(z, y + R, -dir, xe) then
									return true
								end
								table.remove(plan)
								R += 4
							end
						end
					end
				end
			end
		end
		return false
	end
	local found = false
	for _, startX in { -14, -10, -18, -6 } do
		nodes, plan = 0, {}
		-- the first lane may lie on the pad's back strip
		if search(o.padEdge - 1.5 * W - GAP, o.y0, 1, cx + startX) then
			found = true
			break
		end
	end
	if not found then
		print("  [Landmarks] peak trail: no clean switchback found")
		return nil, {}, {}
	end

	-- build
	local model = U.model(parent, "Trail")
	local b = Kit.builder(model, "Landings", frame)
	local function P(lx: number, yy: number, lz: number): any
		return (frame * CFrame.new(lx, yy, lz)).Position
	end
	local railC = C.Red
	local claims = {}
	for f, fl in plan do
		local z = fl.lz
		local zo = z - W / 2 -- the open (camp) side of the lane
		Kit.ramp(model, P(fl.xs, fl.y0, z), P(fl.xe, fl.y1, z), {
			width = W,
			thick = 1.2,
			color = if f % 2 == 1 then C.WoodLight else rgb(244, 196, 134),
			name = `Flight{f}`,
		})
		Kit.ramp(model, P(fl.xs, fl.y0 - 0.4, zo + 0.3), P(fl.xe, fl.y1 - 0.4, zo + 0.3), {
			width = 0.8,
			thick = 2.6,
			color = C.WoodDark,
			name = `Skirt{f}`,
			extra = Kit.NOSHADOW,
		})
		Kit.ramp(model, P(fl.xs, fl.y0 + 3.3, zo + 0.35), P(fl.xe, fl.y1 + 3.3, zo + 0.35), {
			width = 0.7,
			thick = 0.7,
			color = railC,
			name = `Rail{f}`,
			extra = Kit.NOSHADOW,
		})
		-- a stilt under the middle of the flight where it runs high over the slope
		local mx, my = (fl.xs + fl.xe) / 2, (fl.y0 + fl.y1) / 2
		local gm = ground(mx, zo + 1)
		if my - gm > 10 then
			b:box(`Stilt{f}`, mx - 0.9, gm - 1, zo + 0.2, mx + 0.9, my - 2.6, zo + 2, C.WoodDark)
		end
		-- the landing this flight starts from (from the previous lane, or from the camp pad)
		local prev = plan[f - 1]
		local z0 = if prev then prev.lz - W / 2 else o.padEdge - 1
		local lx0, lx1 = min(fl.xs, fl.xs - fl.dir * Lw), max(fl.xs, fl.xs - fl.dir * Lw)
		local ly = fl.y0
		if prev or z + W / 2 > o.padEdge + 0.05 then -- (the first lane may lie on the pad itself)
			b:box(`Landing{f}`, lx0, ly - 1.2, z0, lx1, ly, z + W / 2, C.WoodLight)
		end
		local outerX = if fl.dir > 0 then lx0 else lx1 - 0.7 -- the free end of the landing
		b:box(`LandingRail{f}`, outerX, ly + 2.6, z0, outerX + 0.7, ly + 3.3, z + W / 2, railC, Kit.NOSHADOW)
		if prev then
			b:box(`LandingRailB{f}`, lx0, ly + 2.6, z0, lx1, ly + 3.3, z0 + 0.7, railC, Kit.NOSHADOW)
		end
		-- chunky post on the outer corner, down to the ground; a lantern on every other one
		local px = if fl.dir > 0 then lx0 + 0.85 else lx1 - 0.85
		local pz = z0 + 0.85
		local gp = ground(px, pz)
		b:box(`Post{f}`, px - 1.05, gp - 1, pz - 1.05, px + 1.05, ly + 4, pz + 1.05, C.WoodDark)
		if f % 2 == 1 or f == #plan then
			b:box(`Lantern{f}`, px - 1.1, ly + 4, pz - 1.1, px + 1.1, ly + 5.8, pz + 1.1, C.Glow, Kit.NEON_DECOR)
		end
		table.insert(claims, { (fl.xs + fl.xe) / 2, z, abs(fl.xe - fl.xs) / 2 + Lw })
	end
	-- the walkway from the last flight onto the summit deck
	local last = plan[#plan]
	local ex0, ex1 = min(last.xe, last.xe + last.dir * W), max(last.xe, last.xe + last.dir * W)
	b:box("Walkway", ex0, last.y1 - 1.2, last.lz - W / 2, ex1, last.y1, o.deckFront + 1, C.WoodLight)
	local wx = if last.dir > 0 then ex1 - 0.7 else ex0
	b:box("WalkwayRail", wx, last.y1 + 2.6, last.lz - W / 2, wx + 0.7, last.y1 + 3.3, o.deckFront, railC, Kit.NOSHADOW)
	b:box(
		"WalkwayRailB",
		ex0,
		last.y1 + 2.6,
		last.lz - W / 2,
		ex1,
		last.y1 + 3.3,
		last.lz - W / 2 + 0.7,
		railC,
		Kit.NOSHADOW
	)
	if o.deckFront - (last.lz + W / 2) > 1 then
		-- the inner side, where the walkway leaves the lane and crosses to the deck
		local ix = if last.dir > 0 then ex0 else ex1 - 0.7
		b:box(
			"WalkwayRailC",
			ix,
			last.y1 + 2.6,
			last.lz + W / 2,
			ix + 0.7,
			last.y1 + 3.3,
			o.deckFront,
			railC,
			Kit.NOSHADOW
		)
	end
	b:finish()
	return model, plan, claims
end

-- Summit lookout deck (site frame, centred on the summit block): plank deck on stilts, red
-- rails with an opening where the boardwalk arrives (lx gap0..gap1 on the front), a big flag,
-- a snowman, a cairn, a telescope looking at the lagoon and a «ВЕРШИНА» board.
local function summitDeck(parent: any, world: any, site: any, frame: any, o: { [string]: number })
	local cx, cz, y, D = o.cx, o.cz, o.deckY, o.half
	local b = Kit.builder(parent, "SummitDeck", frame)
	local deck = b:box("Deck", cx - D, y - 1.2, cz - D, cx + D, y, cz + D, C.WoodLight)
	b:box(
		"DeckEdge",
		cx - D - 0.3,
		y - 1.9,
		cz - D - 0.3,
		cx + D + 0.3,
		y - 1.1,
		cz + D + 0.3,
		C.WoodDark,
		Kit.NOSHADOW
	)
	for i, p in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local px, pz = cx + p[1] * (D - 1), cz + p[2] * (D - 1)
		local wx, wz = Kit.radial(site.angle, site.radius, px, pz)
		local g = world:heightAt(wx, wz)
		if y - 1.9 - g > 0.5 then
			b:box(`Stilt{i}`, px - 1, g - 1, pz - 1, px + 1, y - 1.8, pz + 1, C.WoodDark)
		end
		b:box(`Corner{i}`, px - 0.9, y, pz - 0.9, px + 0.9, y + 4, pz + 0.9, C.White)
	end
	local railC = C.Red
	local ry0, ry1 = y + 2.7, y + 3.5
	b:box("RailBack", cx - D, ry0, cz + D - 0.8, cx + D, ry1, cz + D, railC, Kit.NOSHADOW)
	b:box("RailL", cx - D, ry0, cz - D, cx - D + 0.8, ry1, cz + D, railC, Kit.NOSHADOW)
	b:box("RailR", cx + D - 0.8, ry0, cz - D, cx + D, ry1, cz + D, railC, Kit.NOSHADOW)
	if o.gap0 - (cx - D) > 1 then
		b:box("RailFront", cx - D, ry0, cz - D, o.gap0, ry1, cz - D + 0.8, railC, Kit.NOSHADOW)
	end
	if (cx + D) - o.gap1 > 1 then
		b:box("RailFrontB", o.gap1, ry0, cz - D, cx + D, ry1, cz - D + 0.8, railC, Kit.NOSHADOW)
	end
	-- telescope on the front corner away from the opening, looking down at the lagoon
	local side = if (o.gap0 + o.gap1) / 2 > cx then -1 else 1
	local tx, tz = cx + side * (D - 3.5), cz - D + 3
	b:box("ScopePost", tx - 0.4, y, tz - 0.4, tx + 0.4, y + 3.4, tz + 0.4, C.Navy)
	b:box("Scope", tx - 1, y + 3.4, tz - 1.8, tx + 1, y + 4.7, tz + 0.9, C.Yellow)
	b:box("ScopeLens", tx - 0.65, y + 3.6, tz - 2.1, tx + 0.65, y + 4.5, tz - 1.75, C.Cyan, Kit.DECOR)
	-- «ВЕРШИНА» board on posts at the back, facing the arrival
	local board = b:box("Board", cx - 5, y + 3.8, cz + D - 1.6, cx + 3, y + 7.4, cz + D - 0.9, C.Blue)
	b:box("BoardPostL", cx - 5.7, y, cz + D - 1.8, cx - 4.7, y + 7.8, cz + D - 0.8, C.White)
	b:box("BoardPostR", cx + 2.7, y, cz + D - 1.8, cx + 3.7, y + 7.8, cz + D - 0.8, C.White)
	Kit.sign(board, Enum.NormalId.Front, "ВЕРШИНА", C.White, C.Navy, { pps = 24 })
	b:finish(deck)
	local function on(lx: number, lz: number, yaw: number?): any
		return frame * CFrame.new(lx, y, lz) * CFrame.Angles(0, rad(yaw or 0), 0)
	end
	bigFlag(b.model, on(cx + 6, cz + D - 4.5, 0), 24, 10, 6, C.Red)
	snowman(b.model, on(cx - side * 1 + side * 0, cz - 1, side * 15))
	cairn(b.model, on(cx - D + 3.5, cz + D - 3.5, 30), 1)
	return b.model
end

local function buildPeaks(root: any, cfg: any, world: any)
	local model = U.model(root, "Peaks")
	-- the smaller peaks: a chunky flag and a cairn on the summit block
	for _, name in { "PeakEast", "PeakSouth" } do
		local site = world.landmarks[name]
		if not site then
			continue
		end
		local x, z, y = summit(world, site.x, site.z, 48)
		local m = U.model(model, `{name}Flag`)
		bigFlag(m, CFrame.new(x, y, z) * CFrame.Angles(0, rad(site.angle + 90), 0), 16, 8, 5, C.Yellow)
		cairn(m, CFrame.new(x + 4, y, z - 3) * CFrame.Angles(0, rad(site.angle), 0), 0.9)
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
	local function maxGround(x0: number, x1: number, z0: number, z1: number): number
		local m = -math.huge
		for lx = x0, x1, 2 do
			for lz = z0, z1, 2 do
				m = max(m, ground(lx, lz))
			end
		end
		return m
	end

	-- base camp: a flat pad at the end of the path, where the ground under it is lowest
	local reach = site.radius - site.mountainRadius + 12 -- the path's end (VoxelWorld.pathDistance)
	local padHX, padHZ = 22.35, 12 -- wider than the trail's first landing (no flush sides)
	local bestLz, bestTop = reach - site.radius, math.huge
	for lz = reach - site.radius - 30, reach - site.radius + 4, 2 do
		local top = maxGround(-padHX, padHX, lz - padHZ, lz + padHZ)
		if top < bestTop or (top == bestTop and lz > bestLz) then
			bestLz, bestTop = lz, top
		end
	end
	local padLz = bestLz
	local padTop = bestTop + 0.5
	local camp = U.model(model, "Camp")
	local pb = Kit.builder(camp, "Pad", frame)
	local pad = pb:box("Pad", -padHX, bestTop - 1.5, padLz - padHZ, padHX, padTop, padLz + padHZ, rgb(236, 206, 150))
	pb:box(
		"PadEdge",
		-padHX - 0.6,
		bestTop - 1.6,
		padLz - padHZ - 0.6,
		padHX + 0.6,
		padTop - 0.15,
		padLz + padHZ + 0.6,
		C.WoodDark,
		Kit.NOSHADOW
	)
	pb:finish(pad)
	-- 1-stud steps up from the path where the pad stands above it (in front of its edge)
	local pathY = ground(0, padLz - padHZ - 3)
	local nSteps = math.ceil(padTop - pathY - 0.6)
	if nSteps >= 1 then
		local sb = Kit.builder(camp, "PadSteps", frame)
		for k = 1, nSteps do
			local zf = padLz - padHZ - 0.6 - (nSteps - k + 1) * 2
			sb:box(
				`Step{k}`,
				-4,
				pathY - 1,
				zf,
				4,
				pathY + k * (padTop - pathY) / (nSteps + 1),
				zf + 2,
				if k % 2 == 1 then C.WoodLight else C.Wood
			)
		end
		sb:finish()
	end
	local function at(lx: number, lz: number, yaw: number?): any
		return frame * CFrame.new(lx, padTop, padLz + lz) * CFrame.Angles(0, rad(yaw or 0), 0)
	end
	-- yaw (degrees) that turns a prop's front (-Z) from (lx, lz) towards (tx, tz)
	local function toward(lx: number, lz: number, tx: number, tz: number): number
		return deg(atan2(-(tx - lx), -(tz - lz)))
	end
	-- the trail leaves from the pad's back-left corner, the tower stands back-right; the tents'
	-- doors and the tower's ladder face the campfire
	local fireX, fireZ = 2, -2
	Kit.prop("watchtower", camp, at(13, 3, toward(13, 3, fireX, fireZ)), { roof = C.Red, height = 16 })
	tent(camp, at(-12, -5, toward(-12, -5, fireX, fireZ)), C.Orange)
	tent(camp, at(-1, -8, toward(-1, -8, fireX, fireZ)), C.Blue)
	Kit.prop("campfire", camp, at(fireX, fireZ), { light = true })
	Kit.prop("log", camp, at(fireX, fireZ - 5, 90), { seed = 1 })
	Kit.prop("log", camp, at(fireX - 5, fireZ), { seed = 2 })
	Kit.prop(
		"signpost",
		camp,
		at(-6, -padHZ + 1.5, 180),
		{ text = "ВЕРШИНА ↑", width = 9, color = C.Cream, trim = C.Blue }
	)

	-- the switchback boardwalk and the summit deck
	local sxw, szw, topY = summit(world, site.x, site.z, 48)
	local slx, slz = world.radialLocal(sxw, szw, site.angle, site.radius)
	local deckHalf = 10
	local deckY = topY + 1.4
	local _, flights, claims = mountainTrail(model, world, site, frame, {
		cx = slx,
		y0 = padTop + 0.15,
		padEdge = padLz + padHZ,
		deckY = deckY,
		deckFront = slz - deckHalf,
		deckHalf = deckHalf,
	})
	local last = flights[#flights]
	local g0 = if last then min(last.xe, last.xe + last.dir * 7) else slx - 3.5
	summitDeck(model, world, site, frame, {
		cx = slx,
		cz = slz,
		deckY = deckY,
		half = deckHalf,
		gap0 = g0,
		gap1 = g0 + 7,
	})

	-- claims: the camp, the trail, the summit
	local cxw, czw = Kit.radial(site.angle, site.radius, 0, padLz)
	Kit.claim(cxw, czw, 26)
	for _, c in claims do
		local x, z = Kit.radial(site.angle, site.radius, c[1], c[2])
		Kit.claim(x, z, c[3])
	end
	Kit.claim(sxw, szw, deckHalf + 6)
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
