--[[
	Landmarks — dressing of the four landmark sites of World v3 (world.landmarks, DESIGN.md §5/§6),
	built into Map.Landmarks:

	  Waterfall  a Props.waterfall pouring off the mesa's lagoon-facing cliff into the pond, a
	             stream across the mesa top from a little spring, lily pads / reeds / boulders
	             in the pond yard, a zigzag wooden staircase (4 flights, landings, rails,
	             lanterns) from the yard up the cliff to a lookout deck jutting out over the
	             edge (telescope, bench, flag, sign).
	  Windmill   a big Props.windmill (spinning "Blades") on the ziggurat top, rainbow tulip
	             rows on the lagoon-facing terraces, walkable stairs up the terraces, a rail
	             fence round the top meadow, hay crates and barrels.
	  GiantTree  Props.giantTree (treehouse, swing, lanterns) on the meadow plateau, steps up
	             from the path, glowing giant mushrooms, a ring of small mushrooms, torches,
	             a picnic table.
	  Peaks      a big flag on the main Peak's summit; a base camp at the end of its
	             path (watchtower, tents, campfire, logs, signpost); flags on the two smaller
	             peaks. The pines on the slopes come from Nature.

	Every site is registered with Kit.claim so Nature keeps its trees off the dressing.
]]

local U = require("./Util")
local Kit = require("./MapKit")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local rgb = U.rgb
local C = Kit.C

local rad, deg, sqrt, atan2, floor, max, min, abs =
	math.rad, math.deg, math.sqrt, math.atan2, math.floor, math.max, math.min, math.abs

local Landmarks = {}

local WATER_SHEET = { CanCollide = false, CastShadow = false, CanQuery = false, Transparency = 0.1 }

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
		b:box(`LandingEdge{f}`, lx0 - 0.2, y - 1.7, zB0 - 0.3, lx1 + 0.2, y - 1.1, zA1, C.WoodDark, Kit.NOSHADOW)
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
		b:box(`Post{i}`, px - 0.8, g - 1, zB0, px + 0.8, ytop + 3.4, zB0 + 1.6, C.WoodDark)
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
	b:box("DeckEdge", xa - 0.3, y - 1.8, zFront - 0.3, xb + 0.3, y - 1.1, zBack, C.WoodDark, Kit.NOSHADOW)
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
		b:box(`RailPost{i}`, p[1], y, p[2], p[1] + 1.1, y + 3.9, p[2] + 1.1, C.White)
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
	-- the stream across the mesa top from a spring pool
	local stream = Kit.builder(model, "Stream", frame)
	local sLen = 46
	stream:box(
		"Stream",
		-9,
		site.cliffTop - 0.4,
		lipLz - 1,
		9,
		site.cliffTop + 0.3,
		lipLz + sLen,
		rgb(80, 186, 255),
		WATER_SHEET
	)
	stream:box(
		"StreamLight",
		-5,
		site.cliffTop - 0.38,
		lipLz - 1,
		-1,
		site.cliffTop + 0.36,
		lipLz + sLen,
		rgb(150, 224, 255),
		WATER_SHEET
	)
	stream:box(
		"StreamLight2",
		3,
		site.cliffTop - 0.38,
		lipLz + 6,
		6,
		site.cliffTop + 0.36,
		lipLz + sLen,
		rgb(150, 224, 255),
		WATER_SHEET
	)
	stream:box(
		"Pool",
		-15,
		site.cliffTop - 0.4,
		lipLz + sLen,
		15,
		site.cliffTop + 0.3,
		lipLz + sLen + 18,
		rgb(80, 186, 255),
		WATER_SHEET
	)
	stream:box(
		"Spring",
		-2,
		site.cliffTop + 0.2,
		lipLz + sLen + 7,
		2,
		site.cliffTop + 1.6,
		lipLz + sLen + 11,
		C.Foam,
		Kit.DECOR
	)
	-- banks: stone kerbs along the stream
	for i, sx in { -1, 1 } do
		stream:box(
			`Bank{i}`,
			sx * 9,
			site.cliffTop - 0.2,
			lipLz + 2,
			sx * 11,
			site.cliffTop + 1.2,
			lipLz + sLen,
			C.StoneLight
		)
	end
	stream:finish()
	for i, p in { { -17, lipLz + sLen + 4 }, { 17, lipLz + sLen + 12 } } do
		local x, z = W(p[1], p[2])
		Kit.prop("boulder", model, Kit.ground(world, x, z, i * 37), { seed = i, moss = true })
	end

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
		Kit.prop("boulder", model, Kit.ground(world, x, z, i * 50), { seed = 40 + i, moss = i == 2, scale = 1.2 })
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

	-- claims: the stream, the lookout and the stairs (the pond yard is reserved already)
	for _, lz in { lipLz + 6, lipLz + 26, lipLz + sLen + 9 } do
		local cx, cz = W(0, lz)
		Kit.claim(cx, cz, 18)
	end
	local qx, qz = W((sx0 + sx1) / 2 - 4, face)
	Kit.claim(qx, qz, 34)
end

--------------------------------------------------------------------------------------------
-- Windmill
--------------------------------------------------------------------------------------------

-- Rainbow tulip rows on the lagoon-facing terraces: per row of 8-stud cells, runs of equal
-- height merge into one bloom strip; the terrace colour cycles through a rainbow palette and the
-- grass shows between the rows.
local function tulipTerraces(parent: any, world: any, site: any, corridor: (number, number) -> boolean)
	local model = U.model(parent, "TulipFields")
	local cell = world.cell
	local palette = { C.Red, C.Orange, C.Yellow, C.Pink, C.Purple, C.White, C.Blue, rgb(255, 72, 140) }
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
		if facing < 0.3 or corridor(x, z) then
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
					"Tulips",
					Vector3.new(x1 - x0, 2.2, z1 - z0),
					CFrame.new((x0 + x1) / 2, h + 1.0, (z0 + z1) / 2),
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
	local mill = Kit.prop("windmill", model, Kit.facing(site.x, topY, site.z, 0, 0), {
		scale = 1.6,
		spin = 20,
		roof = C.Red,
		name = "Windmill",
	})
	mill.Name = "Windmill"
	tulipTerraces(model, world, site, corridor)
	-- stairs from the hill foot up to the top meadow
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
	-- a rustic rail fence round the top meadow: a 16-gon, open where the stairs arrive, broken
	-- wherever the jagged voxel edge of the top would leave a post hanging in the air
	local run = {}
	local fences = 0
	local function flush()
		if #run >= 2 then
			fences += 1
			Kit.prop("fenceLine", model, run, { style = "rail", height = 3, name = `Fence{fences}` })
		end
		run = {}
	end
	for k = 0, 15 do
		local p = onTop(16, 11.25 + k * 22.5).Position
		if world:heightAt(p.X, p.Z) == topY then
			table.insert(run, p)
		else
			flush()
		end
	end
	flush()
	-- hay crates and barrels behind the mill
	Kit.prop("crate", model, onTop(14.5, 150), { color = C.Yellow, size = 3.4 })
	Kit.prop("crate", model, onTop(14.6, 162), { size = 2.6 })
	Kit.prop("barrel", model, onTop(14.5, -150), {})
	Kit.prop("barrel", model, onTop(14.5, -163), { color = C.Red })
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
	for k = 0, 3 do
		Kit.prop("mushroom", model, at(22, -150 + k * 20), { seed = k + 5, scale = 1.3 })
	end
	-- torches lining the way in, a picnic table, flowers, a stump
	for i, spec in { { 40, -13 }, { 40, 13 }, { 28, -15 }, { 28, 15 } } do
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

-- Highest column within `radius` of (x, z).
local function summit(world: any, x: number, z: number, radius: number): (number, number, number)
	local bx, bz, by = x, z, world:heightAt(x, z)
	for dz = -radius, radius, 4 do
		for dx = -radius, radius, 4 do
			local h = world:heightAt(x + dx, z + dz)
			if h > by then
				bx, bz, by = x + dx, z + dz, h
			end
		end
	end
	return bx, bz, by
end

local function tent(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Tent", cf)
	local base = b:box("Floor", -3.4, -0.2, -3.6, 3.4, 0.2, 3.6, C.WoodDark)
	b:box("Low", -3.2, 0.2, -3.4, 3.2, 2.4, 3.4, color)
	b:box("Mid", -2.2, 2.4, -3.4, 2.2, 4.0, 3.4, Kit.lerpColor(color, C.White, 0.2))
	b:box("Top", -1.1, 4.0, -3.4, 1.1, 5.2, 3.4, color)
	b:box("Door", -1.2, 0.2, -3.5, 1.2, 3.0, -3.3, C.Dark, Kit.DECOR)
	return b:finish(base)
end

local function buildPeaks(root: any, cfg: any, world: any)
	local model = U.model(root, "Peaks")
	for _, name in { "Peak", "PeakEast", "PeakSouth" } do
		local site = world.landmarks[name]
		if not site then
			continue
		end
		local x, z, y = summit(world, site.x, site.z, 48)
		local main = name == "Peak"
		Kit.prop("flagPole", model, CFrame.new(x, y, z) * CFrame.Angles(0, rad(site.angle + 90), 0), {
			height = if main then 16 else 12,
			color = if main then C.Red else C.Yellow,
			scale = if main then 4 else 2.8,
			name = `{name}Flag`,
		})
	end

	-- base camp at the end of the main peak's path
	local site = world.landmarks.Peak
	if not site then
		return
	end
	local camp = U.model(model, "Camp")
	local reach = site.radius - site.mountainRadius + 12
	local function at(lx: number, lz: number, yaw: number?): any
		local px, pz = Kit.radial(site.angle, reach, lx, lz)
		return CFrame.new(px, world:heightAt(px, pz), pz) * CFrame.Angles(0, rad(site.angle + (yaw or 0)), 0)
	end
	Kit.prop("watchtower", camp, at(-16, -2, 180), { roof = C.Red, height = 16 })
	tent(camp, at(14, -6, 200), C.Orange)
	tent(camp, at(15, 6, 160), C.Blue)
	Kit.prop("campfire", camp, at(4, 2), { light = true })
	Kit.prop("log", camp, at(4, 7, 90), { seed = 1 })
	Kit.prop("log", camp, at(-1, 2), { seed = 2 })
	Kit.prop(
		"signpost",
		camp,
		at(-8, 10, 180),
		{ text = "БАЗОВЫЙ ЛАГЕРЬ", width = 9, color = C.Cream, trim = C.Blue }
	)
	local cx, cz = Kit.radial(site.angle, reach, 0, 0)
	Kit.claim(cx, cz, 24)
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
