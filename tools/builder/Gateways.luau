--[[
	Gateways — the 4 themed plazas behind the bridge landings (world.gateways, r ≈ 372,
	radius 40, flat GroundTop), each with a way up the hill behind it to a viewpoint, so the
	strongest sightline of the map (bridge → welcome arch → plaza) leads somewhere.
	Art direction v4 (DESIGN.md §1): natural materials (stone, timber, plaster, canvas) and natural
	roofing (THEMES.roof: slate, straw thatch, wood shingles, clay tile — never a saturated team hue
	on a big roof) carry the look; each gateway's own colour (THEMES.accent, a jewel tone in its
	bridge's hue) pops only on small parts: awnings, the name board's frame, shutters, flags,
	lantern caps, the medallion. Flowers are planted beds and clumps, never flat colour slabs. No
	figures.
	Each Map.Gateways.Gateway_N has:
	  • a slender welcome arch over the brick entry road (see ARCHES: posts on plinths with
	    capitals, a stepped lintel on knee braces, a small cream name board «СЕВЕРНЫЕ ВОРОТА» … in a
	    thin frame of the gateway colour, two hanging lanterns), each dressed its own way: masts
	    with pennants, floats, a lifebuoy and a golden fish vane; hedge posts with roses; painted
	    posts with a spinning pinwheel; log posts under a little shingle roof;
	  • flagstone paving in visible patterns (rings and a medallion, a checker with kerb joints,
	    cross paths, cross joints along the walks) in its own layout — the axis from the arch to
	    the hill path stays open, the centrepiece stands off it; every stall and board faces the
	    plaza. The stalls are little timber pavilions (see stall): a plank floor on a stone kerb,
	    posts and tie beams, a pitched roof with a fascia, a sign board on the roof, a striped
	    awning, a counter with the goods, a back shelf, lanterns.
	      north (180) fish market   a square market (a checker of deep flags with kerb joints, a
	                                compass rose inlaid in the middle): the fish and the tackle
	                                stall, a fountain off the axis (light water in a foam ring,
	                                jets of stacked foam, the golden fish) among planters and
	                                benches, a notice board, lamps; wooden steps up the
	                                fishermen's row (the harbour-master's house with its lookout
	                                tower, the net loft, the smokehouse and its fish-drying rack,
	                                a rowboat on the grass) to a deck by the lighthouse
	      east  (90)  flower garden round plaza with planted hedge beds round a cross of deep paths
	                                and a medallion, a thatched wishing well among flowers off the
	                                axis, a photo frame, the flower stall; a ramped garden path
	                                past the orangery and the potting shed, the florist's thatched
	                                cottage, planted flower beds and a hedge maze to a gazebo
	      south (0)   playground    round plaza in rings with a medallion and planters: a
	                                wood-chip play yard with a timber play fort and a slide off
	                                the axis, a sandpit, swings, the ice cream stall; a stone ramp
	                                path up a little farm (a gambrel barn with a ramp down into
	                                its paddock, a silo, the farmhouse with its porch and kitchen
	                                garden, a wheat field, pumpkins, hay) to a lookout deck with a
	                                long slide down
	      west  (270) picnic camp   a meadow with a jointed paved path, picnic blankets and a camp
	                                off the axis: a trodden clearing round a fire pit with a
	                                cooking tripod and log seats, a canvas tent; the souvenir
	                                stall, an upturned canoe, a picnic table, firewood and a
	                                lantern on a plank patio; plank stairs zigzag up past a
	                                woodshed, the log lodge with its porch and a ranger hut on
	                                stilts to a lookout with a pergola
	  • the climb from the back of the plaza up the terraces to the viewpoint (Kit.stairs 1-stud
	    steps, or Kit.rampPath slabs and wedge ramps), a lantern post beside it; the viewpoint
	    stands on a solid plinth on the hilltop. The district on the terraces either side: a hero
	    building and one or two more on the second terrace framing the climb, so the plaza looks
	    up into a street (see house and the district buildings: base courses, corner boards,
	    roofs with overhangs and filled gables, framed doors under hoods, windows with glazing
	    bars, shutters and planted boxes, chimneys, dormers, porches, lean-tos, a tower), their
	    yards and gardens, each standing only where the ground under its whole footprint is flat
	    (nudged up to 8 studs to find such a spot); lanes of 1-stud steps from the climb along the
	    foot of the terrace to the buildings' doors, a lantern, bush clumps and rocks at the foot
	    of the terrace walls; the trees round them come from Nature (a view corridor from the
	    plaza to every building is kept clear).

	Local frame of a plaza: origin at its centre on the ground, +Z away from the lagoon (like a
	base slot's frame), so the entry road comes in from -Z.
]]

local U = require("./Util")
local Kit = require("./MapKit")
local Promenade = require("./Promenade")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Enum = U.Enum
local C = Kit.C -- the Palette (tools/builder/Palette.luau)
local mix = Kit.lerpColor

local rad, max, min, abs, floor = math.rad, math.max, math.min, math.abs, math.floor

local Gateways = {}

local FLOOR = 0.35 -- plaza paving top above GroundTop
local PAVE = C.Flagstone -- warm stone flags ...
local PAVE2 = C.FlagstoneDark -- ... their second tone (paths) ...
local PAVE3 = mix(C.FlagstoneDark, C.CobbleDark, 0.4) -- ... and a deeper one: rings, checker, joints
local KERB = C.CobbleDark -- borders round the paving
local ROAD = mix(C.Brick, C.SandDark, 0.45) -- terracotta brick entry roads
local EARTH = mix(C.Dirt, C.SandDark, 0.6) -- trodden earth (the camp clearing)
local CHIPS = mix(C.WoodLight, C.Dirt, 0.35) -- wood chips under the play fort
-- the golden fish of the hub (Hub.luau) for every fish statue, vane and finial: gold, not khaki
local GOLD = U.rgb(238, 194, 98)
local GOLD_LIGHT = U.rgb(239, 202, 108)
local GOLD_FIN = U.rgb(222, 124, 52)
local BRASS = mix(C.Gold, C.WoodDark, 0.3) -- telescopes
local INK = Kit.shade(C.WoodDark, 0.7) -- dark brown sign text on cream boards
local POOL = U.rgb(120, 196, 226) -- light fountain water (DESIGN.md: falling and shallow water) ...
local FOAM = U.rgb(240, 248, 252) -- ... and its foam
local ROAD_TOP = 0.97 -- the entry road: a clear step (>= 0.15) over the promenade tiles
-- natural roofing (DESIGN.md §1: no saturated team hues on big roofs): blue-grey slate, straw
-- thatch, weathered wood shingles, a calm clay tile
local SLATE = C.RoofSlate
local THATCH = mix(C.Straw, C.WoodLight, 0.3)
local THATCH_RIDGE = mix(C.Straw, C.Twine, 0.5)
local SHINGLE = mix(C.Wood, C.StoneDark, 0.45)
local TILE = mix(C.RoofTerracotta, C.StoneLight, 0.22)

-- Per-gateway details (keyed by bridge angle): the layout, the gateway's own colour (a clear
-- jewel tone in the hue of its bridge, Promenade.Themes: awnings, boards' frames, shutters,
-- flags, lantern caps, the medallion — small parts only, the colour pops of a calm district) and
-- its roofing material (stalls, kiosks, the well, the gazebo).
local THEMES = {
	[180] = { kind = "market", accent = C.Flowers[7], roof = SLATE },
	[90] = { kind = "garden", accent = U.rgb(236, 86, 150), roof = THATCH },
	[0] = { kind = "playground", accent = C.Flowers[6], roof = TILE },
	[270] = { kind = "picnic", accent = U.rgb(72, 170, 86), roof = SHINGLE },
}

--------------------------------------------------------------------------------------------
-- Shared pieces (each builds in its own local frame: y = 0 on the paving, front = -Z)
--------------------------------------------------------------------------------------------

-- A voxel "circle" of radius r from overlapping rectangles (4 for big ones, 3 for small).
local function disc(b: any, name: string, x: number, z: number, r: number, y0: number, y1: number, color: any)
	local rects = if r > 30
		then { { 1, 0.35 }, { 0.35, 1 }, { 0.85, 0.6 }, { 0.6, 0.85 } }
		else { { 1, 0.4 }, { 0.4, 1 }, { 0.77, 0.77 } }
	for i, q in rects do
		b:box(`{name}{i}`, x - r * q[1], y0, z - r * q[2], x + r * q[1], y1, z + r * q[2], color, Kit.NOSHADOW)
	end
end

-- A wedge in a builder's frame (its tall face at local +Z, the slope falling towards -Z).
local function wedge(b: any, name: string, size: any, lcf: any, color: any, extra: any?): any
	local p = U.wedge(b.model, name, size, b.cf * lcf, color, nil, extra)
	p.Locked = true
	b.first = b.first or p
	return p
end

--[[
	A pitched roof of two wedges over x0..x1 / z0..z1, eaves at y0, the ridge h higher. The ridge
	runs along X (eaves to the front and the back), or along Z with alongZ (the gable end to the
	front, like a cottage).
]]
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

--[[
	The welcome arches (local frame: y = 0 on the paving, front = -Z towards the bridge, the road
	between x = ±9): light, slender gates, not door frames — two posts (a stone plinth, a slim
	shaft, a capital) centred at x = ±12 with 14 studs clear under a stepped lintel on knee braces,
	a small name board (a cream field in a thin frame of the gateway colour) standing on the
	lintel, two lanterns hanging under it. Each theme dresses the frame its own way (see ARCHES),
	20-28 parts:
	  playground  painted timber posts with coloured bands and capitals, a pinwheel spinning
	              over the board (attribute Spin)
	  garden      clipped hedge posts in stone planters under a stepped hedge lintel with roses
	              (small jewel-tone blooms) on it
	  market      two round masts on stone footings under a yard, pennants on the mast tops,
	              floats hanging from the yard, a lifebuoy on a mast, a golden fish vane
	  picnic      log posts, a log lintel with cut ends past the posts, a little shingle roof on
	              two struts over the board
]]
local ARCH_X, ARCH_H = 12, 14 -- post centres, clear height

-- The common frame. o: plinth, shaft, cap, beam, beam2 (colours), sw (shaft width), round (round
-- masts), shaftTop (masts rising past the lintel), braces = false, lintelTop = false. Returns the
-- board's top y.
local function archFrame(b: any, text: string, color: any, o: any): number
	local H = ARCH_H
	for i, sx in { -1, 1 } do
		local x = sx * ARCH_X
		b:box(`Plinth{i}`, x - 2.05, -0.5, -2.05, x + 2.05, 1.6, 2.05, o.plinth)
		if o.round then
			b:pole(`Shaft{i}`, o.sw, x, 0, 1.6, o.shaftTop or (H - 0.7), o.shaft)
		else
			local h = o.sw / 2
			b:box(`Shaft{i}`, x - h, 1.6, -h, x + h, H - 0.7, h, o.shaft)
		end
		b:box(`Capital{i}`, x - 1.75, H - 0.7, -1.75, x + 1.75, H, 1.75, o.cap, Kit.NOSHADOW)
	end
	local top = H + 1.4
	b:box("Lintel", -ARCH_X - 2.6, H, -1.25, ARCH_X + 2.6, top, 1.25, o.beam)
	if o.lintelTop ~= false then
		b:box("LintelTop", -ARCH_X + 1.2, top, -0.95, ARCH_X - 1.2, top + 0.8, 0.95, o.beam2 or o.beam, Kit.NOSHADOW)
		top += 0.8
	end
	if o.braces ~= false then
		for i, sx in { -1, 1 } do
			b:block(
				`Brace{i}`,
				Vector3.new(0.8, 4.4, 0.9),
				CFrame.new(sx * (ARCH_X - 2.6), H - 1.45, 0) * CFrame.Angles(0, 0, rad(sx * 42)),
				o.beam,
				Kit.NOSHADOW
			)
		end
	end
	-- the board: a cream field in a thin frame of the gateway colour, standing on the lintel
	b:box("BoardFrame", -7.4, top - 0.2, -0.4, 7.4, top + 3.9, 0.4, color)
	local board = b:box("Board", -6.9, top + 0.25, -0.55, 6.9, top + 3.45, 0.55, C.Cream)
	Kit.sign(board, Enum.NormalId.Front, text, INK, nil, { pps = 24 })
	Kit.sign(board, Enum.NormalId.Back, text, INK, nil, { pps = 24 })
	-- two lanterns hanging under the lintel over the road's edges
	for i, sx in { -1, 1 } do
		local x = sx * 6.4
		b:box(`LanternRod{i}`, x - 0.15, H - 1.3, -0.15, x + 0.15, H + 0.05, 0.15, C.Iron, Kit.DECOR)
		b:box(`LanternCap{i}`, x - 0.75, H - 1.6, -0.75, x + 0.75, H - 1.2, 0.75, C.Iron, Kit.DECOR)
		b:box(`Lantern{i}`, x - 0.55, H - 2.9, -0.55, x + 0.55, H - 1.6, 0.55, C.Glow, Kit.NEON_DECOR)
	end
	return top + 3.9
end

local ARCHES = {}

ARCHES.playground = function(b: any, text: string, color: any)
	local top = archFrame(b, text, color, {
		plinth = C.Limestone,
		shaft = C.WoodLight,
		cap = color,
		beam = C.Wood,
		beam2 = C.WoodLight,
		sw = 2.6,
	})
	-- painted bands round the posts (a toy-like touch)
	for i, sx in { -1, 1 } do
		local x = sx * ARCH_X
		b:box(`Band{i}`, x - 1.5, 5.4, -1.5, x + 1.5, 6.4, 1.5, color, Kit.NOSHADOW)
	end
	-- the pinwheel over the board: four blades round a hub, each offset along its arm (the
	-- swirl); it spins about its hub (the pivot's LookVector points down the road), no collisions
	b:box("Stick", -0.25, top, -0.25, 0.25, top + 3.4, 0.25, C.WoodDark, Kit.NOSHADOW)
	local hubCF = b.cf * CFrame.new(0, top + 3.4, -0.8)
	local pw = Kit.builder(b.model, "Pinwheel", hubCF)
	pw.model:SetAttribute("Spin", 80)
	local hub = pw:box("Hub", -0.6, -0.6, -0.5, 0.6, 0.6, 0.5, C.Cream, Kit.DECOR)
	for k, c in { C.Red, C.Yellow, C.Cream, C.Blue } do
		local lcf = CFrame.Angles(0, 0, rad(k * 90)) * CFrame.new(2, 0.8, -0.1)
		pw:block(`Blade{k}`, Vector3.new(3.4, 1.6, 0.35), lcf, c, Kit.DECOR)
	end
	pw.model.PrimaryPart = hub
	hub.PivotOffset = hub.CFrame:Inverse() * hubCF
end

ARCHES.garden = function(b: any, text: string, color: any)
	archFrame(b, text, color, {
		plinth = C.Limestone,
		shaft = C.Leaf1,
		cap = C.Leaf2,
		beam = C.Leaf1,
		beam2 = C.Leaf2,
		sw = 3,
		braces = false,
	})
	-- roses on the hedges: small blooms in two jewel tones and white on the fronts of the posts
	-- and along the lintel
	-- (clusters of three where the posts meet the lintel, a pair in the middle, one on each post)
	local roses = { C.Flowers[3], C.Flowers[5], C.Flowers[1] }
	local spots = {
		{ -13.5, 15.2 },
		{ -12.3, 15.9 },
		{ -11.2, 14.8 },
		{ 11.3, 14.9 },
		{ 12.4, 15.8 },
		{ 13.5, 15.1 },
		{ -0.7, 15.0 },
		{ 0.6, 14.7 },
		{ -12.2, 10.6 },
		{ 11.9, 9.4 },
	}
	for k, p in spots do
		local post = p[2] < 12
		local z = if post then -1.5 else -1.25
		local s = if k % 3 == 0 then 0.95 else 1.2
		b:box(
			`Rose{k}`,
			p[1] - s / 2,
			p[2] - s / 2,
			z - 0.45,
			p[1] + s / 2,
			p[2] + s / 2,
			z + 0.4,
			roses[k % 3 + 1],
			Kit.DECOR
		)
	end
end

ARCHES.market = function(b: any, text: string, color: any)
	local top = archFrame(b, text, color, {
		plinth = C.Limestone,
		shaft = C.Wood,
		cap = C.WoodDark,
		beam = C.WoodDark,
		sw = 2.2,
		round = true,
		shaftTop = ARCH_H + 6.5,
		lintelTop = false,
		braces = false,
	})
	-- pennants on the mast tops, flying inwards
	for i, sx in { -1, 1 } do
		local x = sx * ARCH_X
		b:box(`Pennant{i}`, x - sx * 4.3, ARCH_H + 4.6, -0.1, x - sx * 1.1, ARCH_H + 6.2, 0.1, color, Kit.DECOR)
	end
	-- cork floats hanging from the yard (red and white) between the lanterns
	for k, x in { -3.1, 3.1 } do
		local c = if k % 2 == 1 then C.Red else C.White
		b:box(`FloatLine{k}`, x - 0.1, ARCH_H - 1.4, -1.35, x + 0.1, ARCH_H + 0.1, -1.15, C.Rope, Kit.DECOR)
		b:box(`Float{k}`, x - 0.55, ARCH_H - 2.4, -1.75, x + 0.55, ARCH_H - 1.3, -0.75, c, Kit.DECOR)
	end
	-- a lifebuoy on the left mast
	Kit.prop("lifebuoy", b.model, b.cf * CFrame.new(-ARCH_X, 7.6, -1.45), { name = "Lifebuoy" })
	-- the golden fish vane over the board
	b:box("VaneRod", -0.2, top, -0.2, 0.2, top + 2.4, 0.2, C.Iron, Kit.DECOR)
	b:box("VaneFish", -2, top + 2.2, -0.35, 1.2, top + 3.8, 0.35, GOLD, Kit.DECOR)
	b:box("VaneHead", -2.8, top + 2.45, -0.3, -1.9, top + 3.55, 0.3, GOLD_LIGHT, Kit.DECOR)
	b:box("VaneTail", 1.1, top + 1.8, -0.25, 2.3, top + 4.2, 0.25, GOLD_FIN, Kit.DECOR)
end

ARCHES.picnic = function(b: any, text: string, color: any, roof: any)
	local top = archFrame(b, text, color, {
		plinth = C.StoneLight,
		shaft = C.Bark,
		cap = C.BarkDark,
		beam = C.Bark,
		sw = 2.8,
		lintelTop = false,
	})
	-- the lintel log's cut ends past the posts
	for i, sx in { -1, 1 } do
		local x = sx * (ARCH_X + 2.6)
		b:box(`LogEnd{i}`, x - 0.25, ARCH_H + 0.15, -1.05, x + 0.25, ARCH_H + 1.25, 1.05, C.CutWood, Kit.NOSHADOW)
	end
	-- a little shingle roof on two struts over the board
	local ry = top + 0.4
	for i, sx in { -1, 1 } do
		b:box(`Strut{i}`, sx * 8.4 - 0.4, ARCH_H + 1.4, -0.4, sx * 8.4 + 0.4, ry, 0.4, C.Bark)
	end
	gable(b, "Roof", -9.6, 9.6, -2.3, 2.3, ry, 2.2, roof)
	b:box("Ridge", -9.9, ry + 1.8, -0.5, 9.9, ry + 2.5, 0.5, C.BarkDark, Kit.NOSHADOW)
end

local function welcomeArch(parent: any, cf: any, text: string, color: any, kind: string, roof: any)
	local b = Kit.builder(parent, "WelcomeArch", cf)
	ARCHES[kind](b, text, color, roof)
	return b:finish()
end

--[[
	Market stall (front = -Z, the customers' side): a little timber pavilion, about 26-28 parts —
	a stone platform, four posts with a front tie beam, a pitched roof in the roofing with a
	cream fascia and a dark ridge, a framed sign board standing on the roof's front slope, a
	striped canvas awning with a valance over the counter, the counter (plank body, a light top)
	with the goods on it, a back wall with a shelf, two lanterns hanging inside the front beam.
	goods: fish, tackle, flowers, icecream, souvenirs.
]]
local function stall(parent: any, cf: any, text: string, color: any, goods: string, roof: any)
	local b = Kit.builder(parent, "Stall", cf)
	local kerb = b:box("Kerb", -6.4, -0.4, -4.4, 6.4, 0.85, 4.4, KERB)
	for i, p in { { -5.5, -3.4 }, { 5.5, -3.4 }, { 5.5, 3.4 }, { -5.5, 3.4 } } do
		b:box(`Post{i}`, p[1] - 0.5, 0.85, p[2] - 0.5, p[1] + 0.5, 8.4, p[2] + 0.5, C.WoodDark)
	end
	b:box("BeamF", -6.2, 8, -4.05, 6.2, 8.9, -2.8, C.Wood)
	-- the roof: eaves at 8.9, ridge at 12.5
	gable(b, "Roof", -7.2, 7.2, -5.4, 5.4, 8.9, 3.6, roof)
	b:box("Fascia", -7.4, 8.5, -5.65, 7.4, 9.3, -5.25, C.Cream, Kit.NOSHADOW)
	b:box("Ridge", -7.5, 12.2, -0.6, 7.5, 12.9, 0.6, C.WoodDark, Kit.NOSHADOW)
	-- the sign stands on the roof's front slope (its foot buried in the roof)
	b:box("SignFrame", -4.7, 10, -2.4, 4.7, 13.7, -1.8, C.WoodDark)
	local sign = b:box("Sign", -4.3, 10.4, -2.7, 4.3, 13.3, -2.3, C.Cream)
	Kit.sign(sign, Enum.NormalId.Front, text, INK, nil, { pps = 30 })
	-- the awning: three chunky stripes sloping out from the front beam over the counter, a
	-- valance along its edge
	for k = 1, 3 do
		local x0 = -6.4 + (k - 1) * 4.2667
		local lcf = CFrame.new(x0 + 2.1333, 7.32, -4.95) * CFrame.Angles(rad(-25), 0, 0)
		local thick = if k == 2 then 0.45 else 0.4
		b:block(`Awning{k}`, Vector3.new(4.2667, thick, 3.6), lcf, if k == 2 then C.Canvas else color)
	end
	b:box("Valance", -6.45, 5.9, -6.75, 6.45, 6.75, -6.45, color, Kit.NOSHADOW)
	-- the counter
	b:box("Counter", -5, 0.85, -3.5, 5, 3.6, -1.7, C.Wood)
	b:box("CounterTop", -5.4, 3.6, -3.95, 5.4, 4.1, -1.4, C.WoodLight)
	-- the back wall and its shelf
	b:box("BackWall", -5, 0.85, 3, 5, 7.8, 3.4, Kit.shade(C.Plank, 0.88))
	b:box("Shelf", -5, 4.6, 1.9, 5, 5, 3, C.WoodLight, Kit.NOSHADOW)
	-- lanterns hanging inside the front beam
	for i, x in { -4, 4 } do
		b:box(`Lantern{i}`, x - 0.45, 6.7, -3.3, x + 0.45, 8.1, -2.4, C.Glow, Kit.NEON_DECOR)
	end
	-- the goods: on the counter (top y 4.1) and the shelf (top y 5)
	local top = 4.1
	if goods == "fish" then
		-- fish laid on ice, a basket of fish on the shelf
		b:box("Ice", -4.6, top, -3.5, 4.6, top + 0.3, -1.8, C.Foam, Kit.NOSHADOW)
		for i, c in { C.StoneLight, mix(C.Gold, C.StoneLight, 0.4) } do
			local x = -2.2 + (i - 1) * 4
			b:box(`Fish{i}`, x - 1.3, top + 0.3, -3.1, x + 1.3, top + 1.2, -2.2, c, Kit.DECOR)
			b:box(`Tail{i}`, x + 1.3, top + 0.35, -3, x + 2, top + 1.15, -2.3, Kit.shade(c, 0.82), Kit.DECOR)
		end
		b:box("Basket", -3.5, 5, 2, -0.5, 6.6, 2.9, C.Wood, Kit.NOSHADOW)
	elseif goods == "tackle" then
		-- rods leaning on the back wall, a reel and a bobber jar on the counter
		for i, c in { C.Red, C.WoodLight, C.Navy } do
			local x = -3.4 + (i - 1) * 1.6
			b:block(
				`Rod{i}`,
				Vector3.new(0.3, 7.4, 0.3),
				CFrame.new(x, 4.6, 2.4) * CFrame.Angles(rad(-8), 0, 0),
				c,
				Kit.DECOR
			)
		end
		b:box("Reel", -1.8, top, -3.1, -0.4, top + 1.1, -2.2, C.Iron, Kit.DECOR)
		b:box("Jar", 1.6, top, -3.2, 3.2, top + 1.6, -2, mix(C.Glass, C.Red, 0.25), Kit.DECOR)
	elseif goods == "flowers" then
		-- buckets of flowers on the counter, greenery on the shelf
		for i, c in { C.Flowers[1], C.Flowers[2], color } do
			local x = -3 + (i - 1) * 3
			b:box(`Pot{i}`, x - 0.8, top, -3.2, x + 0.8, top + 1.2, -2, C.Iron, Kit.NOSHADOW)
			b:box(`Bloom{i}`, x - 1, top + 1.2, -3.4, x + 1, top + 2.4, -1.8, c, Kit.DECOR)
		end
		b:box("Leaves", -4.6, 5, 2, 4.6, 6, 2.9, C.Leaf2, Kit.NOSHADOW)
	elseif goods == "icecream" then
		-- three tubs set in the counter top; a big cone on the ridge
		for i, c in { C.Cream, C.Blossom1, C.WoodDark } do
			local x = -3 + (i - 1) * 3
			b:box(`Scoop{i}`, x - 1, top - 0.2, -3.3, x + 1, top + 0.8, -2, c, Kit.DECOR)
		end
		-- the big cone on the ridge: a stepped waffle cone, two scoops (strawberry under
		-- vanilla), a drip, a cherry
		for k, s in { 0.6, 1.2, 1.8 } do
			local y = 12.6 + (k - 1) * 0.9
			b:box(`BigCone{k}`, -s, y, -s, s, y + 0.95, s, if k == 2 then C.WoodLight else C.Straw, Kit.NOSHADOW)
		end
		b:box("BigScoop", -1.7, 15.3, -1.7, 1.7, 17.1, 1.7, C.Blossom1, Kit.NOSHADOW)
		b:box("BigScoopTop", -1.15, 17.1, -1.15, 1.15, 18.4, 1.15, C.Cream, Kit.NOSHADOW)
		b:box("Drip", -0.9, 14.6, -1.95, -0.2, 15.6, -1.6, C.Blossom1, Kit.DECOR)
		b:box("Cherry", -0.4, 18.4, -0.4, 0.4, 19.2, 0.4, C.Red, Kit.DECOR)
	else
		-- shells, a ship in a bottle, little flags on the shelf
		for i, c in { C.Cream, C.Blossom1 } do
			local x = -3 + (i - 1) * 2.6
			b:box(`Shell{i}`, x - 0.8, top, -3.1, x + 0.8, top + 0.8, -2.1, c, Kit.DECOR)
		end
		b:box("Bottle", 1.8, top, -3.2, 3.6, top + 1.2, -2.2, mix(C.Glass, C.Cyan, 0.3), Kit.DECOR)
		b:box("Flags", -4.4, 5, 2.2, 4.4, 6.6, 2.6, C.Festive[1], Kit.DECOR)
	end
	return b:finish(kerb)
end

-- Notice board under a little pitched roof (front = -Z). 11 parts.
local function noticeBoard(parent: any, cf: any, roof: any)
	local b = Kit.builder(parent, "NoticeBoard", cf)
	local post = b:box("PostL", -4.2, -0.5, -0.5, -3.2, 8.4, 0.5, C.WoodDark)
	b:box("PostR", 3.2, -0.5, -0.5, 4.2, 8.4, 0.5, C.WoodDark)
	b:box("Frame", -3.4, 2.2, -0.3, 3.4, 7.8, 0.3, C.WoodDark)
	b:box("Board", -3, 2.6, -0.45, 3, 6.4, 0.2, C.WoodLight)
	local header = b:box("Header", -3, 6.5, -0.5, 3, 7.6, 0.2, C.Cream)
	Kit.sign(header, Enum.NormalId.Front, "ОБЪЯВЛЕНИЯ", INK, nil, { pps = 40 })
	gable(b, "Roof", -5, 5, -1.6, 1.6, 8.4, 1.6, roof)
	for i, n in { { -1.6, 4.9, C.Cream }, { 0.6, 3.8, C.White }, { 1.9, 5.2, C.Straw } } do
		local front = -0.55 - (i % 3) * 0.05 -- overlapping notes never share a plane
		b:box(`Note{i}`, n[1] - 0.8, n[2] - 0.9, front, n[1] + 0.8, n[2] + 0.9, -0.42, n[3], Kit.DECOR)
	end
	return b:finish(post)
end

-- The viewpoint's solid plinth on the hilltop: a block from below the lowest ground under it up
-- to a hair above the highest. Returns its top y (local, relative to the frame).
local function plinth(b: any, world: any, origin: any, x0: number, z0: number, x1: number, z1: number, color: any)
	local hi, lo = -math.huge, math.huge
	for x = x0, x1, 2 do
		for z = z0, z1, 2 do
			local p = (origin * CFrame.new(x, 0, z)).Position
			local h = world:heightAt(p.X, p.Z)
			hi, lo = max(hi, h), min(lo, h)
		end
	end
	local base = origin.Position.Y
	local top = hi - base + 0.6
	-- (0.15 proud of the given edges: its sides never share a plane with a voxel cell's side)
	b:box("Plinth", x0 - 0.15, lo - base - 1.3, z0 - 0.15, x1 + 0.15, top, z1 + 0.15, color)
	-- a cap course round its top edge (the deck reads as built, not as a raw block)
	b:box("PlinthCap", x0 - 0.45, top - 0.7, z0 - 0.45, x1 + 0.45, top - 0.1, z1 + 0.45, C.Stone, Kit.NOSHADOW)
	return top
end

--------------------------------------------------------------------------------------------
-- Centrepieces
--------------------------------------------------------------------------------------------

-- The hub fish's colours on a Props.fishStatue: a lighter head, orange fins and tail.
local FISH_FINS = { TailUp = true, TailDown = true, Dorsal = true, FinL = true, FinR = true }
local function recolourFish(m: any)
	for _, p in m:GetDescendants() do
		if FISH_FINS[p.Name] then
			p.Color = GOLD_FIN
		elseif p.Name == "Head" then
			p.Color = GOLD_LIGHT
		end
	end
end

--[[
	Fountain: an octagonal limestone basin (two crossed rims), light water in a white foam ring
	along the rim (each a cross of two sheets, opaque), four jets of stacked foam cubes getting
	smaller towards the top, a foam ring round the golden fish rising out of the middle.
]]
local function fountain(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Fountain", cf)
	local water = { CanCollide = false, CastShadow = false } -- opaque: the sheets cross
	local rim = b:box("Rim", -10.4, 0, -6.6, 10.4, 2.2, 6.6, C.Limestone)
	b:box("RimB", -6.6, 0.02, -10.4, 6.6, 2.22, 10.4, C.Limestone)
	b:box("Foam", -9.4, 1.6, -5.6, 9.4, 2.4, 5.6, FOAM, water)
	b:box("FoamB", -5.6, 1.62, -9.4, 5.6, 2.42, 9.4, FOAM, water)
	b:box("Water", -8.4, 1.7, -4.6, 8.4, 2.5, 4.6, POOL, water)
	b:box("WaterB", -4.6, 1.72, -8.4, 4.6, 2.52, 8.4, POOL, water)
	b:box("Splash", -2.9, 2.3, -2.9, 2.9, 2.75, 2.9, FOAM, Kit.DECOR)
	for i, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local x, z = d[1] * 6.2, d[2] * 6.2
		b:box(`Jet{i}`, x - 0.6, 2.4, z - 0.6, x + 0.6, 3.9, z + 0.6, mix(FOAM, POOL, 0.25), Kit.DECOR)
		b:box(`JetTop{i}`, x - 0.35, 3.9, z - 0.35, x + 0.35, 5.1 + (i % 2) * 0.3, z + 0.35, FOAM, Kit.DECOR)
	end
	b:finish(rim)
	-- the golden fish (the hub's colours: gold body, a lighter head, orange fins) on its pedestal
	-- rising out of the water (about 22 studs to the tail)
	local fish = Kit.prop("fishStatue", b.model, cf * CFrame.new(0, 2, 0), {
		color = GOLD,
		belly = mix(GOLD, C.Cream, 0.5),
		pedestal = C.StoneLight,
		trim = color,
		scale = 1.5,
		name = "GoldenFish",
	})
	recolourFish(fish)
end

--[[
	Wishing well among flowers (the garden's centrepiece): a stone well with a dark water top and
	a cap course, two timber posts with a crank beam, a little pitched roof in the roofing,
	a bucket on its rope, flower clumps round its foot. 16 parts.
]]
local function wishingWell(parent: any, cf: any, roof: any)
	local b = Kit.builder(parent, "WishingWell", cf)
	local base = b:box("Well", -3.6, -0.3, -3.6, 3.6, 3.4, 3.6, C.StoneLight)
	b:box("WellCap", -4, 3.4, -4, 4, 4, 4, C.Stone)
	b:box("Water", -2.8, 3.2, -2.8, 2.8, 4.15, 2.8, mix(C.Water, C.Navy, 0.35), Kit.NOSHADOW)
	for i, sx in { -1, 1 } do
		b:box(`Post{i}`, sx * 3.4 - 0.5, 4, -0.5, sx * 3.4 + 0.5, 10.4, 0.5, C.WoodDark)
	end
	b:box("Crank", -4.4, 8.4, -0.35, 4.4, 9.1, 0.35, C.Wood, Kit.NOSHADOW)
	gable(b, "Roof", -5, 5, -3.4, 3.4, 10.4, 2.8, roof)
	b:box("Ridge", -5.2, 12.9, -0.45, 5.2, 13.6, 0.45, C.WoodDark, Kit.NOSHADOW)
	b:box("Rope", -0.15, 6.4, -0.15, 0.15, 8.4, 0.15, C.Rope, Kit.DECOR)
	b:box("Bucket", -0.8, 5, -0.8, 0.8, 6.4, 0.8, C.Wood, Kit.DECOR)
	b:finish(base)
	-- flower clumps round the foot (leafy tufts with blooms poking out)
	for k, p in { { -4.8, 4.9 }, { 4.9, 4.6 } } do
		Kit.prop("flowerClump", b.model, b.cf * CFrame.new(p[1], 0, p[2]), {
			colors = { C.Flowers[k * 2], C.Flowers[5] },
			seed = k * 13,
		})
	end
	return b.model
end

--[[
	Timber play fort: four posts, a plank deck with walls, a pitched roof in the roofing,
	a pennant, climbing blocks at the back and a slide down the front (about 22 studs tall).
]]
local function playFort(parent: any, cf: any, color: any, roof: any)
	local b = Kit.builder(parent, "PlayTower", cf)
	local deckY = 8
	local first = nil
	for i, p in { { -1, -1 }, { 1, -1 }, { 1, 1 }, { -1, 1 } } do
		local post = b:box(`Post{i}`, p[1] * 5 - 0.8, -0.3, p[2] * 5 - 0.8, p[1] * 5 + 0.8, 15, p[2] * 5 + 0.8, C.Wood)
		first = first or post
	end
	b:box("Deck", -5.6, deckY - 1, -5.6, 5.6, deckY, 5.6, C.WoodLight)
	b:box("WallB", -4.2, deckY, 4.2, 4.2, deckY + 2.6, 5.0, C.Plank)
	b:box("WallL", -5.0, deckY, -4.2, -4.2, deckY + 2.6, 4.2, C.Plank)
	b:box("WallR", 4.2, deckY, -4.2, 5.0, deckY + 2.6, 4.2, C.Plank)
	gable(b, "Roof", -7, 7, -7, 7, 15, 4, roof)
	b:box("Ridge", -7.3, 18.6, -0.6, 7.3, 19.4, 0.6, C.WoodDark, Kit.NOSHADOW)
	b:box("Mast", -0.25, 19.4, -0.25, 0.25, 23.6, 0.25, C.WoodDark, Kit.NOSHADOW)
	b:box("Pennant", 0.25, 21.6, -0.12, 3.2, 23.4, 0.12, C.Yellow, Kit.DECOR)
	-- climbing blocks at the back (jump up: 2.7 studs each)
	for i = 1, 3 do
		local h = i * 2.7
		local z0 = 5.6 + (3 - i) * 2.6
		b:box(`Climb{i}`, -2.4, -0.3, z0, 2.4, h, z0 + 2.6, if i % 2 == 1 then C.Wood else C.WoodLight)
	end
	b:finish(first)
	-- the slide: a chute in the gateway colour from the deck's front edge down to the ground
	local top = (cf * CFrame.new(-2.2, deckY, -5.6)).Position
	local foot = (cf * CFrame.new(-2.2, 0.4, -19)).Position
	Kit.ramp(b.model, top, foot, { width = 3.6, thick = 0.8, color = color, name = "Slide" })
	for i, sx in { -1, 1 } do
		local off = (cf * CFrame.new(sx * 2, 1, 0)).Position - cf.Position
		Kit.ramp(b.model, top + off, foot + off, {
			width = 0.5,
			thick = 1.6,
			color = C.WoodDark,
			name = `SlideWall{i}`,
			extra = Kit.NOSHADOW,
		})
	end
	return b.model
end

-- Swing set: two timber posts, a top beam, two seats on rope pairs. 7 parts.
local function swings(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Swings", cf)
	local post = b:box("PostL", -6, -0.3, -0.6, -4.8, 9.6, 0.6, C.Wood)
	b:box("PostR", 4.8, -0.3, -0.6, 6, 9.6, 0.6, C.Wood)
	b:box("Bar", -6.4, 9.6, -0.7, 6.4, 10.6, 0.7, C.WoodDark)
	for i, x in { -2.2, 2.2 } do
		b:box(`Rope{i}`, x - 0.15, 3.4, -0.15, x + 0.15, 9.6, 0.15, C.Rope, Kit.DECOR)
		b:box(`Seat{i}`, x - 1.2, 2.8, -0.8, x + 1.2, 3.4, 0.8, if i == 1 then color else C.WoodLight)
	end
	return b:finish(post)
end

-- Sandpit: a timber frame round sand, a sand castle with a flag, a bucket and a spade. 7 parts.
local function sandpit(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Sandpit", cf)
	local frame = b:box("Frame", -6.5, -0.3, -5, 6.5, 1.2, 5, C.Wood)
	b:box("Sand", -5.6, -0.2, -4.1, 5.6, 1.45, 4.1, C.Sand, Kit.NOSHADOW)
	b:box("Castle", -3.6, 1.45, -1.4, 0.4, 3.6, 1.6, C.SandDark)
	b:box("Tower", -2.6, 3.6, -0.6, -0.6, 5.2, 1, C.SandDark, Kit.NOSHADOW)
	b:box("Flag", -1.75, 5.2, 0.15, -1.45, 6.8, 0.25, C.Red, Kit.DECOR)
	b:box("Bucket", 2.2, 1.45, -2.6, 3.8, 3.2, -1, color, Kit.NOSHADOW)
	b:box("Spade", 3, 1.45, 1.2, 4.6, 1.8, 2, C.Iron, Kit.DECOR)
	return b:finish(frame)
end

--[[
	Camp fire pit: a stone ring, crossed logs and a flame (light, smoke, sparks), a cooking tripod
	with an iron pot over it, four log seats round it. 11 parts.
]]
local function firePit(parent: any, cf: any)
	local b = Kit.builder(parent, "Camp", cf)
	local ring = b:box("FireStones", -3, -0.4, -3, 3, 0.8, 3, C.StoneLight)
	b:box("Ash", -2.2, 0.8, -2.2, 2.2, 0.95, 2.2, C.StoneDark, Kit.NOSHADOW)
	b:box("FireLogA", -2, 0.95, -0.45, 2, 1.75, 0.45, C.Bark)
	b:box("FireLogB", -0.45, 1.75, -2, 0.45, 2.45, 2, C.Bark)
	local flame = b:box("Flame", -0.9, 1.6, -0.9, 0.9, 3.8, 0.9, C.Flame, Kit.NEON_DECOR)
	Kit.light(flame, 14, 1.4)
	Kit.smoke(flame)
	Kit.sparkles(flame, C.Autumn2, { rate = 4, size = 0.4, lifetime = 1.4, speed = 5, drift = 2 })
	-- the tripod: two leaning poles each side and a crossbar, the pot hanging over the flame
	for i, sx in { -1, 1 } do
		b:block(
			`Tripod{i}`,
			Vector3.new(0.4, 8, 0.4),
			CFrame.new(sx * 2.6, 3.6, 0) * CFrame.Angles(0, 0, rad(sx * 14)),
			C.WoodDark,
			Kit.NOSHADOW
		)
	end
	b:box("Crossbar", -2.2, 7.1, -0.25, 2.2, 7.5, 0.25, C.WoodDark, Kit.DECOR)
	b:box("Pot", -1, 4.4, -1, 1, 5.8, 1, C.Iron, Kit.DECOR)
	for i, p in { { -6, 0, 90 }, { 6, 0, 90 }, { 0, -6, 0 }, { 0, 6, 0 } } do
		b:block(
			`Seat{i}`,
			Vector3.new(6.4, 1.7, 1.7),
			CFrame.new(p[1], 0.6, p[2]) * CFrame.Angles(0, rad(p[3]), 0),
			C.Bark
		)
	end
	return b:finish(ring)
end

--[[
	Garden bed w x d (front = -Z, ~11 parts): a clipped hedge border with a planted bed in it
	(Props.flowerBed: soil, leaves, separate blooms in two jewel tones on a grid, staggered).
]]
local function gardenBed(parent: any, cf: any, w: number, d: number, c1: any, c2: any, seed: number)
	local b = Kit.builder(parent, "HedgeBed", cf)
	local hedge = b:box("Hedge", -w / 2, -0.3, -d / 2, w / 2, 1.3, d / 2, C.Leaf1)
	b:finish(hedge)
	Kit.prop("flowerBed", b.model, cf * CFrame.new(0, 1.3, 0), {
		width = w - 1.8,
		depth = d - 1.8,
		colors = { c1, c2 },
		kerb = false,
		stems = false,
		spacing = 3,
		max = 8,
		seed = seed,
	})
	return b.model
end

-- Walk-in photo frame on a low stage under a vine-covered top, «ФОТО» on top (front = -Z). 8 parts.
local function photoFrame(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "PhotoSpot", cf)
	local stage = b:box("Stage", -7, -0.4, -3, 7, 0.7, 3, C.StoneLight)
	b:box("FrameL", -7, 0.7, -1, -5, 12, 1, C.WoodDark)
	b:box("FrameR", 5, 0.7, -1, 7, 12, 1, C.WoodDark)
	b:box("FrameTop", -7.4, 12, -1.2, 7.4, 13.6, 1.2, C.Wood)
	b:box("Vines", -7.6, 11.2, -1.4, -1, 14.2, 1.4, C.Leaf2, Kit.NOSHADOW)
	b:box("Roses", -6.4, 13.8, -1.5, -3.6, 15.4, 1.5, C.Blossom1, Kit.NOSHADOW)
	local sign = b:box("Sign", -1.8, 13.6, -0.8, 6.6, 16.6, 0.8, color)
	Kit.sign(sign, Enum.NormalId.Front, "ФОТО", C.White, C.Navy, { pps = 30 })
	Kit.sign(sign, Enum.NormalId.Back, "ФОТО", C.White, C.Navy, { pps = 30 })
	return b:finish(stage)
end

--------------------------------------------------------------------------------------------
-- Viewpoints on the hilltop (local frame of the plaza; `top` = the plinth top)
--------------------------------------------------------------------------------------------

-- Timber lookout rail along the back and both sides of the deck x0..x1 / z0..z1 (open at the front).
local function rails(b: any, x0: number, x1: number, z0: number, z1: number, y: number)
	b:box("RailBack", x0, y + 2.6, z1 - 0.8, x1, y + 3.4, z1, C.Wood, Kit.NOSHADOW)
	b:box("RailL", x0, y + 2.6, z0, x0 + 0.8, y + 3.4, z1, C.Wood, Kit.NOSHADOW)
	b:box("RailR", x1 - 0.8, y + 2.6, z0, x1, y + 3.4, z1, C.Wood, Kit.NOSHADOW)
	for i, x in { x0, x1 - 1 } do
		b:box(`RailPost{i}`, x - 0.1, y, z1 - 1.1, x + 1.1, y + 3.9, z1 + 0.1, C.WoodDark)
	end
end

-- A brass telescope on an iron post.
local function telescope(b: any, x: number, y: number, z: number)
	b:box("ScopePost", x - 0.4, y, z - 0.4, x + 0.4, y + 3.4, z + 0.4, C.Iron)
	b:box("Scope", x - 0.9, y + 3.4, z - 1.8, x + 0.9, y + 4.6, z + 0.9, BRASS)
	b:box("ScopeLens", x - 0.6, y + 3.6, z - 2.1, x + 0.6, y + 4.4, z - 1.75, C.Glass, Kit.DECOR)
end

--------------------------------------------------------------------------------------------
-- The hill districts: set-pieces on the terraces either side of each climb (local frame of the
-- plaza, standing on the voxel ground; each is placed only where its footprint is flat)
--------------------------------------------------------------------------------------------

-- Chunky lantern post (3 parts): a dark timber post, a Neon cube, a cap in the gateway colour.
local function lantern(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Lantern", cf)
	local post = b:box("Post", -0.6, -0.6, -0.6, 0.6, 6, 0.6, C.WoodDark)
	b:box("Lamp", -1.1, 6, -1.1, 1.1, 8.2, 1.1, C.Glow, Kit.NEON)
	b:box("Cap", -1.4, 8.2, -1.4, 1.4, 8.9, 1.4, color, Kit.NOSHADOW)
	return b:finish(post)
end

--[[
	Crop bed w x d (front = -Z): dark soil with `rows` rows of separate plants along X at a `pitch`
	(the rows staggered by half a pitch) — plants, never one long bar. kind:
	  wheat    stalk clusters (1.2 wide, 2.6-3.6 tall) in two straw shades
	  cabbage  leaf heads in two greens
	  carrot   feathery green tufts with an orange root top showing at the soil
	1 + plants (carrots 2 each) parts.
]]
local function cropBed(parent: any, cf: any, w: number, d: number, kind: string, rows: number, pitch: number)
	local b = Kit.builder(parent, "CropBed", cf)
	local soil = b:box("Soil", -w / 2, -0.6, -d / 2, w / 2, 0.5, d / 2, C.DirtDark, Kit.NOSHADOW)
	local n = max(1, floor((w - 1) / pitch))
	local step = (w - 1) / n
	local k = 0
	for r = 1, rows do
		local z = -d / 2 + (r - 0.5) * d / rows
		local odd = r % 2 == 0
		for i = 1, n - (if odd then 1 else 0) do
			k += 1
			local x = -w / 2 + 0.5 + (i - 0.5 + (if odd then 0.5 else 0)) * step
			local v = (i * 7 + r * 3) % 4
			if kind == "wheat" then
				local h = 2.6 + v * 0.33
				local c = if (i + r) % 2 == 0 then C.Straw else C.StrawLight
				b:box(`Stalks{k}`, x - 0.45, 0.3, z - 0.5, x + 0.45, h, z + 0.5, c, Kit.DECOR)
			elseif kind == "cabbage" then
				local s = 1.3 + v * 0.1
				local c = if (i + r) % 2 == 0 then C.Leaf2 else C.Mint2
				b:box(`Head{k}`, x - s / 2, 0.3, z - s / 2, x + s / 2, 0.4 + s * 0.8, z + s / 2, c, Kit.DECOR)
			else
				b:box(`Root{k}`, x - 0.35, 0.3, z - 0.35, x + 0.35, 0.75, z + 0.35, C.Orange, Kit.DECOR)
				b:box(`Tuft{k}`, x - 0.5, 0.7, z - 0.4, x + 0.5, 1.8 + v * 0.15, z + 0.4, C.Leaf3, Kit.DECOR)
			end
		end
	end
	return b:finish(soil)
end

-- Fish-drying rack (6 parts): two posts, a bar, three silver fish hanging from it.
local function dryingRack(parent: any, cf: any)
	local b = Kit.builder(parent, "DryingRack", cf)
	local post = b:box("PostL", -5, -0.5, -0.4, -4.2, 6.6, 0.4, C.WoodDark)
	b:box("PostR", 4.2, -0.5, -0.4, 5, 6.6, 0.4, C.WoodDark)
	b:box("Bar", -5.4, 6.6, -0.5, 5.4, 7.3, 0.5, C.Wood)
	for i, c in { C.StoneLight, GOLD_LIGHT, C.Stone } do
		local x = -2.6 + (i - 1) * 2.6
		b:box(`Fish{i}`, x - 0.6, 3.6 + (i % 2) * 0.5, -0.3, x + 0.6, 6.6, 0.3, c, Kit.DECOR)
	end
	return b:finish(post)
end

-- Upturned rowboat on a trestle (3 parts), a crate stack beside it (2 parts).
local function boatYard(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "BoatYard", cf)
	local trestle = b:box("Trestle", -1.6, -0.5, -4, 1.6, 1.6, 4, C.WoodDark)
	b:box("Hull", -2.6, 1.6, -5.5, 2.6, 3.6, 5.5, color)
	b:box("Keel", -1, 3.6, -5.2, 1, 4.3, 5.2, C.Cream, Kit.NOSHADOW)
	b:box("Crate", 4, -0.5, -2.5, 7, 2.6, 0.5, C.WoodLight)
	b:box("Crate2", 4.4, 2.6, -2, 6.6, 4.4, 0.2, C.Wood, Kit.NOSHADOW)
	return b:finish(trestle)
end

-- Canvas tent (5 parts), front = -Z (the door): stepped canvas, a ridge stripe in `color`.
local function tent(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Tent", cf)
	local base = b:box("Floor", -4.8, -0.4, -5, 4.8, 0.3, 5, C.WoodDark)
	b:box("Low", -4.5, 0.3, -4.8, 4.5, 3.4, 4.8, C.Canvas)
	b:box("Mid", -3.1, 3.4, -4.8, 3.1, 5.6, 4.8, Kit.shade(C.Canvas, 0.94))
	b:box("Top", -1.5, 5.6, -4.8, 1.5, 7.3, 4.8, color)
	b:box("Door", -1.7, 0.3, -4.95, 1.7, 4.2, -4.7, C.WoodDark, Kit.DECOR)
	return b:finish(base)
end

-- Picnic blanket on the grass (3 parts): a cloth in a jewel tone with a cream band across it, a
-- wicker basket on one corner.
local function blanket(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Blanket", cf)
	local cloth = b:box("Cloth", -3.5, -0.2, -3, 3.5, 0.25, 3, color, Kit.NOSHADOW)
	b:box("Band", -3.6, -0.18, -0.8, 3.6, 0.32, 0.8, C.Cream, Kit.DECOR)
	b:box("Basket", 1.6, 0.25, 1.2, 3.2, 1.5, 2.4, C.Twine, Kit.NOSHADOW)
	return b:finish(cloth)
end

-- Haystack (2 parts): a big straw block with a smaller lighter one on top.
local function hayStack(parent: any, cf: any)
	local b = Kit.builder(parent, "HayStack", cf)
	local bale = b:box("Bale", -3.2, -0.5, -2.2, 3.2, 3.2, 2.2, C.Straw)
	b:box("Top", -2.2, 3.2, -1.5, 2, 5.4, 1.7, C.StrawLight, Kit.NOSHADOW)
	return b:finish(bale)
end

-- Pumpkin patch w x d (2 + 4 parts): soil under a leafy vine mat, four chunky pumpkins of
-- different sizes in two oranges.
local function pumpkinPatch(parent: any, cf: any, w: number, d: number)
	local b = Kit.builder(parent, "PumpkinPatch", cf)
	local bed = b:box("Soil", -w / 2, -0.5, -d / 2, w / 2, 0.4, d / 2, C.DirtDark, Kit.NOSHADOW)
	b:box("Vines", -w / 2 + 0.6, 0.3, -d / 2 + 0.6, w / 2 - 0.6, 0.8, d / 2 - 0.6, C.Leaf2, Kit.DECOR)
	for i, p in { { -0.34, -0.18, 2.6 }, { -0.12, 0.2, 2 }, { 0.1, -0.16, 3 }, { 0.3, 0.22, 2.2 } } do
		local x, z, s = p[1] * w, p[2] * d, p[3]
		local c = if i % 2 == 0 then C.Autumn1 else C.Orange
		b:box(`Pumpkin{i}`, x - s / 2, 0.4, z - s / 2, x + s / 2, 0.4 + s * 0.75, z + s / 2, c, Kit.DECOR)
	end
	return b:finish(bed)
end

-- Hedge maze 14 sx x 14 (7 parts, fits on one terrace): clipped walls in two greens (the lighter a
-- little lower), a way in at the front, a baffle inside, a stone urn in the middle.
local function hedgeMaze(parent: any, cf: any, sx: number?)
	local b = Kit.builder(parent, "HedgeMaze", cf)
	local dark, mid = C.Leaf1, C.Leaf2
	local k = sx or 1 -- (stretched along X: the walls stay 1.5 thick)
	local e, i = 7 * k, 7 * k - 1.5
	local first = b:box("WallW", -e, -0.4, -7, -i, 3.6, 7, dark)
	b:box("WallE", i, -0.4, -7, e, 3.6, 7, dark)
	b:box("WallN", -i, -0.4, 5.5, i, 3.2, 7, mid)
	b:box("WallS1", -i, -0.4, -7, -1.8, 3.2, -5.5, mid)
	b:box("WallS2", 1.8, -0.4, -7, i, 3.2, -5.5, mid)
	b:box("Baffle", -3.2 * k, -0.4, -2.6, i, 3.4, -1.2, dark)
	b:box("Urn", -1.3, -0.4, 1.4, 1.3, 2.4, 4, C.StoneLight)
	return b:finish(first)
end

-- Firewood pile (2 parts): a wide stack of logs with a narrower layer on top.
local function logPile(parent: any, cf: any)
	local b = Kit.builder(parent, "LogPile", cf)
	local pile = b:box("Logs", -2.6, -0.4, -1.8, 2.6, 1.8, 1.8, C.Bark)
	b:box("LogsTop", -2.3, 1.8, -0.9, 2.3, 3, 0.9, C.CutWood, Kit.NOSHADOW)
	return b:finish(pile)
end

-- Rowboat pulled up on the grass (3 parts): a painted hull, the plank floor inside, a seat.
-- Front = -Z.
local function beachedBoat(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Rowboat", cf)
	local hull = b:box("Hull", -2.4, -0.4, -5, 2.4, 1.8, 5, color)
	b:box("Floor", -1.7, 1.8, -4.2, 1.7, 1.9, 4.2, C.WoodLight, Kit.DECOR)
	b:box("Seat", -2.5, 1.8, -0.6, 2.5, 2.5, 0.6, C.WoodLight, Kit.NOSHADOW)
	return b:finish(hull)
end

--------------------------------------------------------------------------------------------
-- District buildings: real voxel architecture (DESIGN.md §1) — a stone base course, walls with
-- corner boards, a roof with overhangs, a ridge and filled gables, framed doors under hoods with
-- steps, windows with frames, glazing bars, shutters and planted flower boxes, chimneys,
-- dormers, porches on posts, lean-tos, towers. One wall + one roof + one trim colour a building
-- (+ wood and stone); natural roofing (slate, thatch, shingles, clay tile); the gateway colour
-- only on small parts (shutters, a door, a flag). Each district: a hero building and one or two
-- more, 30-70 parts each.
--------------------------------------------------------------------------------------------

-- A block on a wall face: face "-z" | "+z" | "-x" | "+x" (the wall's outward normal), p the
-- plane of the wall, a0..a1 along it (x on the z faces, z on the x faces), d0..d1 out of it.
local function onFace(
	b: any,
	name: string,
	face: string,
	p: number,
	a0: number,
	y0: number,
	a1: number,
	y1: number,
	d0: number,
	d1: number,
	color: any,
	extra: any?
): any
	if face == "-z" then
		return b:box(name, a0, y0, p - d1, a1, y1, p - d0, color, extra)
	elseif face == "+z" then
		return b:box(name, a0, y0, p + d0, a1, y1, p + d1, color, extra)
	elseif face == "-x" then
		return b:box(name, p - d1, y0, a0, p - d0, y1, a1, color, extra)
	end
	return b:box(name, p + d0, y0, a0, p + d1, y1, a1, color, extra)
end

-- A gable triangle (2 wedges, the tall faces meeting in the middle): half width hw at its base
-- y0, ht tall, th thick, in the plane z = c (axis "z") or x = c (axis "x").
local function triangle(
	b: any,
	name: string,
	axis: string,
	c: number,
	y0: number,
	hw: number,
	ht: number,
	th: number,
	color: any
)
	local y = y0 + ht / 2
	if axis == "z" then
		wedge(b, `{name}L`, Vector3.new(th, ht, hw), CFrame.new(-hw / 2, y, c) * CFrame.Angles(0, rad(90), 0), color)
		wedge(b, `{name}R`, Vector3.new(th, ht, hw), CFrame.new(hw / 2, y, c) * CFrame.Angles(0, rad(-90), 0), color)
	else
		wedge(b, `{name}L`, Vector3.new(th, ht, hw), CFrame.new(c, y, -hw / 2), color)
		wedge(b, `{name}R`, Vector3.new(th, ht, hw), CFrame.new(c, y, hw / 2) * CFrame.Angles(0, math.pi, 0), color)
	end
end

--[[
	A window on a wall face centred at a, sill at y0, ww x wh: a trim frame with the glass 0.1
	proud of it; o.shutter: a pair of shutters either side (one block behind the frame); o.cross:
	glazing bars (a mullion and a transom); o.box = { c1, c2 }: a flower box under it, planted
	(a leafy top, two blooms). 2-8 parts.
]]
local function window(
	b: any,
	name: string,
	face: string,
	p: number,
	a: number,
	y0: number,
	ww: number,
	wh: number,
	trim: any,
	o: any?
)
	local hw = ww / 2
	if o and o.shutter then
		local sw = ww * 0.5
		onFace(
			b,
			`{name}Shutters`,
			face,
			p,
			a - hw - sw,
			y0 + 0.15,
			a + hw + sw,
			y0 + wh - 0.15,
			-0.1,
			0.15,
			o.shutter,
			Kit.NOSHADOW
		)
	end
	onFace(b, `{name}Frame`, face, p, a - hw, y0, a + hw, y0 + wh, -0.1, 0.25, trim, Kit.NOSHADOW)
	onFace(
		b,
		`{name}Glass`,
		face,
		p,
		a - hw + 0.45,
		y0 + 0.45,
		a + hw - 0.45,
		y0 + wh - 0.45,
		0,
		0.35,
		C.WindowBlue,
		Kit.NOSHADOW
	)
	if o and o.cross then
		local ym = y0 + wh * 0.58
		onFace(b, `{name}Bar`, face, p, a - 0.17, y0 + 0.4, a + 0.17, y0 + wh - 0.4, 0, 0.45, trim, Kit.DECOR)
		onFace(b, `{name}Bar2`, face, p, a - hw + 0.4, ym - 0.17, a + hw - 0.4, ym + 0.17, 0, 0.45, trim, Kit.DECOR)
	end
	if o and o.box then
		onFace(
			b,
			`{name}Box`,
			face,
			p,
			a - hw + 0.1,
			y0 - 1.1,
			a + hw - 0.1,
			y0 + 0.1,
			0.05,
			1.2,
			C.WoodDark,
			Kit.NOSHADOW
		)
		onFace(
			b,
			`{name}Leaves`,
			face,
			p,
			a - hw + 0.3,
			y0 + 0.05,
			a + hw - 0.3,
			y0 + 0.55,
			0.2,
			1.1,
			C.Leaf1,
			Kit.DECOR
		)
		for i, sx in { -1, 1 } do
			local c = a + sx * hw * 0.42
			local top = y0 + 0.95 + (i % 2) * 0.3
			onFace(b, `{name}Bloom{i}`, face, p, c - 0.6, y0 + 0.2, c + 0.6, top, 0.3, 1.25, o.box[i], Kit.DECOR)
		end
	end
end

-- A door on a wall face centred at a: a trim frame round the leaf (the leaf 0.1 proud). 2 parts.
local function door(
	b: any,
	name: string,
	face: string,
	p: number,
	a: number,
	y0: number,
	dw: number,
	dh: number,
	trim: any,
	leaf: any
)
	onFace(
		b,
		`{name}Frame`,
		face,
		p,
		a - dw / 2 - 0.5,
		y0,
		a + dw / 2 + 0.5,
		y0 + dh + 0.5,
		-0.1,
		0.25,
		trim,
		Kit.NOSHADOW
	)
	onFace(b, name, face, p, a - dw / 2, y0, a + dw / 2, y0 + dh, 0, 0.35, leaf, Kit.NOSHADOW)
end

local WALL_PLANE = { ["-z"] = "d", ["+z"] = "d", ["-x"] = "w", ["+x"] = "w" }

--[[
	A house, front = -Z, standing on the ground at y = 0 (the floor is the top of a stone base
	course at 0.9, which is also the doorstep). Walls up to s.h, a pitched roof of two wedges
	(s.rise high, overhangs s.ov / s.og) with a ridge beam (s.ridge); the gable ends in s.fills
	(default: the front one, or both with s.eaves) filled with a triangle in s.gable on a dark tie
	beam, with an attic window (s.attic). s.eaves turns the ridge along X (the eaves face the
	front). s.lower = { colour, top }: a stone ground storey 0.2 proud of the walls. s.corners:
	corner boards on the front corners in that colour. Door s.door (x on the front; s.doorW,
	s.doorH, s.leaf) with s.hood (a little pent roof over it in that colour) and a stone step,
	s.lantern = -1 | 1 (a lamp beside the door); windows s.win = { { face, a, y0, w, h, shutter =,
	box =, cross = } }; chimney s.chimney = { x, z }; s.dormer = { x, w } (eaves roofs: a dormer
	with a window on the front slope); s.porch = { x0, x1, d, h, roof } (a plank porch on posts
	under a pent roof, rails either side of its steps). Returns the builder (b.base: the base
	course; b.front: the front wall plane; b.gable, b.eave); the caller adds its own details and
	finishes it.
]]
local function house(parent: any, cf: any, s: any): any
	local b = Kit.builder(parent, s.name or "House", cf)
	local hw, hd, h = s.w / 2, s.d / 2, s.h
	local B = 0.9
	b.base = b:box("Base", -hw - 0.5, -0.8, -hd - 0.5, hw + 0.5, B, hd + 0.5, s.base or C.Stone)
	b:box("Walls", -hw, B, -hd, hw, h, hd, s.wall)
	local lower = 0
	if s.lower then
		lower = 0.2
		b:box("Lower", -hw - 0.2, B, -hd - 0.2, hw + 0.2, s.lower[2], hd + 0.2, s.lower[1])
	end
	local y0, rise = h - 0.4, s.rise
	local ov, og = s.ov or 1.1, s.og or 0.8
	local ul, vl = if s.eaves then hw else hd, if s.eaves then hd else hw -- the walls along / across the ridge
	local UL, VL = ul + og, vl + ov -- the roof
	b.eave = { y = y0, VL = VL, UL = UL, rise = rise }
	local ridgeC = s.ridge or C.WoodDark
	if s.eaves then
		gable(b, "Roof", -UL, UL, -VL, VL, y0, rise, s.roof)
		b:box("Ridge", -UL - 0.25, y0 + rise - 0.6, -0.65, UL + 0.25, y0 + rise + 0.55, 0.65, ridgeC, Kit.NOSHADOW)
	else
		gable(b, "Roof", -VL, VL, -UL, UL, y0, rise, s.roof, true)
		b:box("Ridge", -0.65, y0 + rise - 0.6, -UL - 0.25, 0.65, y0 + rise + 0.55, UL + 0.25, ridgeC, Kit.NOSHADOW)
	end
	local k = rise / VL
	local gy = y0 + 0.2
	local ght = rise - 1
	local ghw = ght / k
	b.gable = { y = gy, ht = ght, hw = ghw, u = UL + 0.45 } -- (u: the plane of the triangles' fronts)
	for _, su in s.fills or (if s.eaves then { -1, 1 } else { -1 }) do
		local axis = if s.eaves then "x" else "z"
		triangle(b, `Gable{su}`, axis, su * (UL + 0.3), gy, ghw, ght, 0.3, s.gable or s.wall)
		local a0, a1 = su * (ul - 0.6), su * (UL + 0.55)
		local u0, u1 = min(a0, a1), max(a0, a1)
		if s.eaves then
			b:box(`Tie{su}`, u0, y0 - 0.9, -ghw - 0.6, u1, gy, ghw + 0.6, C.WoodDark)
		else
			b:box(`Tie{su}`, -ghw - 0.6, y0 - 0.9, u0, ghw + 0.6, gy, u1, C.WoodDark)
		end
		if s.attic and su == -1 then
			local wh = min(3, ght * 0.42)
			local ww = min(2.8, wh)
			local f0, f1, g0, g1 = su * (UL + 0.35), su * (UL + 0.6), su * (UL + 0.4), su * (UL + 0.7)
			local ya = gy + 0.7
			if s.eaves then
				b:box(`Attic{su}Frame`, min(f0, f1), ya, -ww / 2, max(f0, f1), ya + wh, ww / 2, s.trim, Kit.NOSHADOW)
				b:box(
					`Attic{su}`,
					min(g0, g1),
					ya + 0.4,
					-ww / 2 + 0.4,
					max(g0, g1),
					ya + wh - 0.4,
					ww / 2 - 0.4,
					C.WindowBlue,
					Kit.DECOR
				)
			else
				b:box(`Attic{su}Frame`, -ww / 2, ya, min(f0, f1), ww / 2, ya + wh, max(f0, f1), s.trim, Kit.NOSHADOW)
				b:box(
					`Attic{su}`,
					-ww / 2 + 0.4,
					ya + 0.4,
					min(g0, g1),
					ww / 2 - 0.4,
					ya + wh - 0.4,
					max(g0, g1),
					C.WindowBlue,
					Kit.DECOR
				)
			end
		end
	end
	local front = -hd - lower
	b.front = front
	if s.corners then
		for i, sx in { -1, 1 } do
			local x = sx * (hw + lower)
			onFace(b, `Corner{i}`, "-z", front, x - 0.55, B, x + 0.55, y0 - 0.1, -0.1, 0.2, s.corners, Kit.NOSHADOW)
		end
	end
	if s.door then
		local dw, dh = s.doorW or 2.8, s.doorH or 5.6
		door(b, "Door", "-z", front, s.door, B, dw, dh, s.trim, s.leaf or C.WoodDark)
		if not s.porch then
			b:box("Step", s.door - dw / 2 - 0.7, -0.5, -hd - 1.6, s.door + dw / 2 + 0.7, 0.5, -hd - 0.4, C.StoneLight)
		end
		if s.hood then
			wedge(
				b,
				"Hood",
				Vector3.new(dw + 1.8, 0.9, 1.5),
				CFrame.new(s.door, B + dh + 1.05, front - 0.75),
				s.hood,
				Kit.NOSHADOW
			)
		end
		if s.lantern then
			local lx = s.door + s.lantern * (dw / 2 + 1.5)
			b:box("Lamp", lx - 0.5, B + 3.9, front - 0.95, lx + 0.5, B + 5.2, front + 0.1, C.Glow, Kit.NEON_DECOR)
		end
	end
	for i, w in s.win or {} do
		local p = if WALL_PLANE[w[1]] == "d" then hd else hw
		if w[1] == "-z" or w[1] == "-x" then
			p = -p
		end
		if s.lower and w[3] < s.lower[2] then
			p += if p < 0 then -0.2 else 0.2
		end
		window(b, `Win{i}`, w[1], p, w[2], w[3], w[4], w[5], s.trim, w)
	end
	if s.chimney then
		local cx, cz = s.chimney[1], s.chimney[2]
		local across = if s.eaves then abs(cz) else abs(cx)
		local top = y0 + rise * (1 - (across + 1.1) / VL) + 3.6
		b:box("Chimney", cx - 1.1, h - 1, cz - 1.1, cx + 1.1, top, cz + 1.1, s.chimneyC or C.Brick)
		b:box("ChimneyCap", cx - 1.45, top, cz - 1.45, cx + 1.45, top + 0.6, cz + 1.45, C.StoneDark, Kit.NOSHADOW)
	end
	if s.dormer and s.eaves then
		-- a dormer on the front slope: its face 0.4 behind the wall, its own little gable roof
		local dx, dw = s.dormer[1], s.dormer[2]
		local zf = -hd + 0.4
		local ys = y0 + rise * (1 - abs(zf) / VL) -- the roof at the dormer's face
		local top = ys + 2.8
		b:box("Dormer", dx - dw / 2, ys - 0.8, zf, dx + dw / 2, top, -1, s.wall)
		gable(b, "DormerRoof", dx - dw / 2 - 0.6, dx + dw / 2 + 0.6, zf - 0.6, -0.1, top - 0.2, 1.9, s.roof, true)
		onFace(
			b,
			"DormerFrame",
			"-z",
			zf,
			dx - dw / 2 + 0.5,
			ys + 0.1,
			dx + dw / 2 - 0.5,
			top - 0.5,
			-0.1,
			0.2,
			s.trim,
			Kit.NOSHADOW
		)
		onFace(
			b,
			"DormerGlass",
			"-z",
			zf,
			dx - dw / 2 + 0.9,
			ys + 0.5,
			dx + dw / 2 - 0.9,
			top - 0.9,
			0,
			0.3,
			C.WindowBlue,
			Kit.DECOR
		)
	end
	if s.porch then
		-- a plank porch across the front on posts under a pent roof, rails either side of its steps
		local P = s.porch
		local x0, x1, pd, ph = P.x0, P.x1, P.d, P.h
		local zf = -hd - 0.5 - pd
		b:box("Porch", x0, -0.6, zf, x1, B + 0.25, -hd + 0.2, C.Plank)
		local posts = if x1 - x0 > 11 then { x0 + 0.6, (x0 + x1) / 2, x1 - 0.6 } else { x0 + 0.6, x1 - 0.6 }
		for i, x in posts do
			if s.door and abs(x - s.door) < 2.4 then
				x = s.door + (if x < s.door then -2.4 else 2.4)
			end
			b:box(`PorchPost{i}`, x - 0.4, B + 0.25, zf + 0.25, x + 0.4, ph, zf + 1.05, P.post or C.Wood)
		end
		b:box("PorchBeam", x0 - 0.2, ph - 0.1, zf + 0.15, x1 + 0.2, ph + 0.6, zf + 1.15, P.post or C.Wood, Kit.NOSHADOW)
		wedge(
			b,
			"PorchRoof",
			Vector3.new(x1 - x0 + 1, 1.6, pd + 1.6),
			CFrame.new((x0 + x1) / 2, ph + 1.4, (zf - 0.8 + front) / 2),
			P.roof or s.roof
		)
		local dx = s.door or 0
		local dw = (s.doorW or 2.8) / 2 + 0.9
		for i, seg in { { x0 + 0.2, dx - dw }, { dx + dw, x1 - 0.2 } } do
			if seg[2] - seg[1] > 1.5 then
				b:box(`PorchRail{i}`, seg[1], B + 1.6, zf + 0.35, seg[2], B + 2.2, zf + 0.85, s.trim, Kit.NOSHADOW)
			end
		end
	end
	return b
end

-- One wall colour per building (plus wood and stone)
local RORBU = mix(C.Brick, C.WoodDark, 0.22) -- calm barn / net loft red
local ROSE = mix(C.Plaster, C.Blossom1, 0.22) -- the florist's rose plaster
local LOGS = mix(C.Wood, C.Bark, 0.3) -- the lodge's logs
local SAGE = mix(C.RoofGreen, C.Plank, 0.5)
local GREEN_PAINT = mix(C.RoofGreen, C.Plaster, 0.12) -- doors and shutters on the farm
local NET = mix(C.Cyan, C.Navy, 0.45)
local GLASS = { Transparency = 0.45, CastShadow = false }

--[[
	The harbour-master's house (the north district's hero, ~70 parts): two storeys — a stone ground
	floor and a plastered upper floor — under a slate roof with the eaves to the front, a dormer
	over the door, a brick chimney; a door in the gateway colour under a slate hood with a lamp, a
	name board, shuttered windows with flower boxes below and glazing bars above; on one side
	(`m` = 1: +X) a lookout tower rising to an open belvedere with a stepped slate roof, a golden
	finial and a flag.
]]
local function harbourHouse(parent: any, cf: any, color: any, m: number)
	local trim = C.Cream
	local b = house(parent, cf, {
		name = "HarbourHouse",
		w = 16,
		d = 11,
		h = 13.4,
		rise = 6,
		eaves = true,
		wall = C.Plaster,
		lower = { C.StoneLight, 6.4 },
		roof = SLATE,
		trim = trim,
		gable = C.Plaster,
		door = 0,
		doorW = 3,
		doorH = 4.6,
		leaf = color,
		hood = SLATE,
		lantern = -m,
		win = {
			{ "-z", -4.9, 2.2, 2.8, 3.2, shutter = color, box = { C.Flowers[1], C.Flowers[5] } },
			{ "-z", 4.9, 2.2, 2.8, 3.2, shutter = color, box = { C.Flowers[2], C.Flowers[1] } },
			{ "-z", -4.9, 7.6, 2.6, 3.6, shutter = color, cross = true },
			{ "-z", 4.9, 7.6, 2.6, 3.6, shutter = color, cross = true },
			{ if m > 0 then "-x" else "+x", 0, 7.8, 2.6, 3.4 },
		},
		dormer = { 0, 4.2 },
		chimney = { -m * 5, 2 },
		fills = { -m },
	})
	local f = b.front
	-- the name board over the door
	local board = onFace(b, "NameBoard", "-z", f, -2.6, 6.6, 2.6, 7.8, 0, 0.3, C.Cream, Kit.NOSHADOW)
	Kit.sign(board, Enum.NormalId.Front, "ГАВАНЬ", INK, nil, { pps = 30 })
	-- the lookout tower on the side
	local t0, t1 = m * 8, m * 14
	local x0, x1 = min(t0, t1), max(t0, t1)
	local xm = (x0 + x1) / 2
	b:box("TowerBase", x0 - 0.2, -0.8, -3.2, x1 + 0.2, 6.4, 3.2, C.StoneLight)
	b:box("Tower", x0, 6.4, -3, x1, 19, 3, C.Plaster)
	b:box("TowerBand", x0 - 0.3, 18.6, -3.3, x1 + 0.3, 19.4, 3.3, trim, Kit.NOSHADOW)
	for i, y in { 12.6 } do
		onFace(b, `TowerWin{i}Frame`, "-z", -3, xm - 1.1, y, xm + 1.1, y + 3, -0.1, 0.2, trim, Kit.NOSHADOW)
		onFace(b, `TowerWin{i}`, "-z", -3, xm - 0.7, y + 0.4, xm + 0.7, y + 2.6, 0, 0.3, C.WindowBlue, Kit.DECOR)
	end
	b:box("Belvedere", x0 - 0.6, 19.4, -3.6, x1 + 0.6, 20, 3.6, C.WoodDark)
	for i, p in { { x0 - 0.3, -3.3 }, { x1 + 0.3, -3.3 }, { x1 + 0.3, 3.3 }, { x0 - 0.3, 3.3 } } do
		b:box(`TowerPost{i}`, p[1] - 0.35, 20, p[2] - 0.35, p[1] + 0.35, 23.4, p[2] + 0.35, C.WoodDark, Kit.NOSHADOW)
	end
	b:box("TowerRail", x0 - 0.3, 20.9, -3.5, x1 + 0.3, 21.5, -3.1, trim, Kit.NOSHADOW)
	b:box("TowerRoof", x0 - 1, 23.4, -4, x1 + 1, 24.6, 4, SLATE)
	b:box("TowerRoof2", xm - 2.3, 24.6, -2.3, xm + 2.3, 25.8, 2.3, SLATE, Kit.NOSHADOW)
	b:box("Finial", xm - 0.45, 25.8, -0.45, xm + 0.45, 27, 0.45, GOLD, Kit.NOSHADOW)
	b:pole("FlagPole", 0.35, xm, 0, 27, 31.5, C.WoodDark, Kit.DECOR)
	b:box("Flag", xm + 0.2, 29.2, -0.1, xm + 3.6, 31.3, 0.1, color, Kit.DECOR)
	return b:finish(b.base)
end

--[[
	Net loft (~30 parts): a tall red timber storehouse with cream corner boards on a stone base,
	its gable to the front under a slate roof: a wide door below, a loft door above it under a
	hoist beam with a bundle on its rope, a shuttered side window, nets with cork floats drying on
	the other side wall, two oars leaning by the door, a barrel.
]]
local function netLoft(parent: any, cf: any, color: any, side: string)
	local sx = if side == "+x" then 1 else -1
	local b = house(parent, cf, {
		name = "NetLoft",
		w = 11,
		d = 11,
		h = 12.6,
		rise = 6.5,
		wall = RORBU,
		roof = SLATE,
		trim = C.Cream,
		gable = RORBU,
		corners = C.Cream,
		door = 0,
		doorW = 4.4,
		doorH = 5.4,
		win = { { if sx > 0 then "-x" else "+x", -1, 8.2, 2.4, 3, shutter = color } },
	})
	door(b, "LoftDoor", "-z", -5.5, 0, 8, 3, 3.8, C.Cream, C.WoodDark)
	local g = b.gable
	local u = -g.u
	b:box("Hoist", -0.5, g.y + g.ht - 2.4, u - 3.4, 0.5, g.y + g.ht - 1.4, -4, C.WoodDark)
	b:box("Rope", -0.12, 9.6, u - 2.9, 0.12, g.y + g.ht - 2.4, u - 2.65, C.Rope, Kit.DECOR)
	b:box("Bundle", -1, 7.8, u - 3.8, 1, 9.6, u - 1.8, C.WoodLight, Kit.DECOR)
	onFace(b, "Net", side, sx * 5.5, -3.4, 4.6, 1, 11.4, 0.05, 0.4, NET, Kit.DECOR)
	onFace(b, "Net2", side, sx * 5.5, 1.4, 7.2, 3.8, 11.3, 0.1, 0.45, Kit.shade(NET, 0.85), Kit.DECOR)
	onFace(b, "Floats", side, sx * 5.5, -3.6, 11.2, 3.6, 12, 0.15, 0.75, C.Orange, Kit.DECOR)
	for i, x in { -4, -3.2 } do
		b:block(
			`Oar{i}`,
			Vector3.new(0.4, 7, 0.4),
			CFrame.new(x, 4.2, -6.2) * CFrame.Angles(rad(-10), 0, rad(-6 + i * 5)),
			C.WoodLight,
			Kit.DECOR
		)
	end
	b:box("Barrel", 3.6, 0.9, -7.6, 5.4, 3.4, -5.8, C.Wood, Kit.NOSHADOW)
	return b:finish(b.base)
end

-- Smokehouse (~16 parts): a squat stone house under a slate roof, a plank door, a louvred vent on
-- the ridge with smoke curling out of it, firewood stacked against the side.
local function smokehouse(parent: any, cf: any)
	local b = house(parent, cf, {
		name = "Smokehouse",
		w = 8,
		d = 8,
		h = 6.5,
		rise = 4.2,
		wall = C.Stone,
		roof = SLATE,
		trim = C.WoodDark,
		gable = C.StoneDark,
		base = C.StoneDark,
		door = 0,
		doorW = 2.4,
		doorH = 4.4,
		leaf = C.Wood,
	})
	local vy = 6.1 + 4.2
	b:box("Vent", -1.1, vy - 0.8, -1.4, 1.1, vy + 1.4, 1.4, C.WoodDark)
	local cap = b:box("VentCap", -1.7, vy + 1.4, -2, 1.7, vy + 2.1, 2, SLATE, Kit.NOSHADOW)
	Kit.smoke(cap, { rate = 2, size = 1.4, rise = 2.4 })
	b:box("Firewood", 4.6, -0.3, -3.4, 6.2, 3.2, 3.4, C.Bark)
	b:box("FirewoodEnds", 4.55, 0.4, -3.2, 6.25, 2.8, -1.2, C.CutWood, Kit.NOSHADOW)
	return b:finish(b.base)
end

--[[
	The big barn (the south district's hero, ~45 parts): calm red plank walls with cream corner
	boards on a stone base under a slate gambrel roof (steep lower slopes, shallow upper ones, the
	gable filled in red), a cupola with a golden vane on the ridge; a wide double door with cream X
	braces, the hayloft door in the gable with hay poking out under a hoist beam and its rope,
	small windows along the side towards `m`, an open lean-to on the other side with hay in it.
]]
local function bigBarn(parent: any, cf: any, m: number)
	local b = Kit.builder(parent, "Barn", cf)
	local hw, hd, h = 9, 7, 9
	local trim = C.Cream
	b.base = b:box("Base", -hw - 0.5, -0.8, -hd - 0.5, hw + 0.5, 0.9, hd + 0.5, C.StoneLight)
	b:box("Walls", -hw, 0.9, -hd, hw, h, hd, RORBU)
	-- the gambrel roof: ridge along Z
	local y0, VL, UL = h - 0.4, hw + 1, hd + 0.8
	local a, h0, h1 = 3.4, 4.6, 3.2
	local ia = VL - a
	for i, sx in { -1, 1 } do
		wedge(
			b,
			`RoofLow{i}`,
			Vector3.new(2 * UL, h0, a),
			CFrame.new(sx * (VL - a / 2), y0 + h0 / 2, 0) * CFrame.Angles(0, rad(-sx * 90), 0),
			SLATE
		)
		wedge(
			b,
			`RoofUp{i}`,
			Vector3.new(2 * UL, h1, ia),
			CFrame.new(sx * ia / 2, y0 + h0 + h1 / 2, 0) * CFrame.Angles(0, rad(-sx * 90), 0),
			SLATE
		)
	end
	b:box("Attic", -ia, y0 - 0.2, -hd - 0.3, ia, y0 + h0 + 0.05, hd + 0.3, RORBU)
	for _, su in { -1, 1 } do
		triangle(b, `Gable{su}`, "z", su * (hd + 0.3), y0 + h0, ia - 0.9, h1 - 0.6, 0.3, RORBU)
	end
	local top = y0 + h0 + h1
	b:box("Ridge", -0.6, top - 0.55, -UL - 0.2, 0.6, top + 0.45, UL + 0.2, C.WoodDark, Kit.NOSHADOW)
	-- the cupola with a golden vane
	b:box("Cupola", -1.4, top - 0.6, -1.4, 1.4, top + 2.4, 1.4, trim)
	b:box("CupolaRoof", -2, top + 2.4, -2, 2, top + 3.2, 2, SLATE, Kit.NOSHADOW)
	b:box("CupolaRoof2", -1.1, top + 3.2, -1.1, 1.1, top + 3.9, 1.1, SLATE, Kit.NOSHADOW)
	b:box("Vane", -1.4, top + 4.4, -0.15, 1.4, top + 5.2, 0.15, GOLD, Kit.DECOR)
	b:box("VaneRod", -0.12, top + 3.9, -0.12, 0.12, top + 5.6, 0.12, C.Iron, Kit.DECOR)
	-- the front: corner boards, the big double door with X braces
	local f = -hd
	for i, sx in { -1, 1 } do
		onFace(b, `Corner{i}`, "-z", f, sx * hw - 0.5, 0.9, sx * hw + 0.5, y0 - 0.1, -0.1, 0.2, trim, Kit.NOSHADOW)
	end
	door(b, "Door", "-z", f, 0, 0.9, 7, 6.8, trim, C.WoodDark)
	for i, sa in { 1, -1 } do
		b:block(
			`Brace{i}`,
			Vector3.new(0.5, 9.4, 0.25),
			CFrame.new(0, 4.3, f - 0.45) * CFrame.Angles(0, 0, sa * 0.8),
			trim,
			Kit.DECOR
		)
	end
	b:box("DoorSplit", -0.2, 0.9, f - 0.5, 0.2, 7.7, f - 0.3, trim, Kit.DECOR)
	-- the hayloft door in the gable, hay poking out, the hoist beam with its rope
	local u = -hd - 0.3
	b:box("LoftFrame", -2.2, y0 + 0.3, u - 0.15, 2.2, y0 + 4.2, u + 0.2, trim, Kit.NOSHADOW)
	b:box("Loft", -1.7, y0 + 0.4, u - 0.25, 1.7, y0 + 3.7, u + 0.1, C.WoodDark, Kit.NOSHADOW)
	b:box("Hay", -1.4, y0 + 0.5, u - 0.7, 1.4, y0 + 1.7, u, C.Straw, Kit.DECOR)
	b:box("Hoist", -0.45, top - 2.4, -UL - 2.6, 0.45, top - 1.6, -hd + 1, C.WoodDark)
	b:box("HoistRope", -0.1, y0 + 3.4, -UL - 2.2, 0.1, top - 2.4, -UL - 1.95, C.Rope, Kit.DECOR)
	-- small windows along the side towards m
	for i, z in { -3, 3 } do
		onFace(
			b,
			`SideWin{i}Frame`,
			if m > 0 then "+x" else "-x",
			m * hw,
			z - 1.2,
			4,
			z + 1.2,
			6.4,
			-0.1,
			0.2,
			trim,
			Kit.NOSHADOW
		)
		onFace(
			b,
			`SideWin{i}`,
			if m > 0 then "+x" else "-x",
			m * hw,
			z - 0.8,
			4.4,
			z + 0.8,
			6,
			0,
			0.3,
			C.WindowBlue,
			Kit.DECOR
		)
	end
	-- the open lean-to on the other side: a side wall, two posts, a pent roof, hay inside
	local o0, o1 = -m * hw, -m * (hw + 5.6)
	local lx0, lx1 = min(o0, o1), max(o0, o1)
	b:box("ShedFloor", lx0, -0.6, -5, lx1, 0.5, 5.6, C.StoneLight, Kit.NOSHADOW)
	b:box("ShedBack", lx0, 0.5, 4.8, lx1, 6.2, 5.6, mix(RORBU, C.WoodDark, 0.2))
	b:box("ShedPost", o1 - 0.4, 0.5, -5, o1 + 0.4, 5.6, -4.2, C.Wood)
	wedge(
		b,
		"ShedRoof",
		Vector3.new(11.4, 2.2, 6.6),
		CFrame.new((o0 + o1) / 2 - m * 0.4, 6.7, 0.3) * CFrame.Angles(0, rad(m * 90), 0),
		SLATE
	)
	b:box("ShedHay", lx0 + 0.6, 0.5, -1, lx1 - 0.6, 3.2, 4.6, C.Straw, Kit.NOSHADOW)
	return b:finish(b.base)
end

-- Silo (10 parts): a round voxel tower of limestone (two crossed blocks) on a stone base, iron
-- hoops, a stepped slate cap with a golden finial, a ladder up the front.
local function silo(parent: any, cf: any)
	local b = Kit.builder(parent, "Silo", cf)
	local base = b:box("Base", -3.6, -0.8, -3.6, 3.6, 1.2, 3.6, C.Stone)
	b:box("BodyA", -3.2, 1.2, -2.1, 3.2, 20, 2.1, C.Limestone)
	b:box("BodyB", -2.1, 1.2, -3.2, 2.1, 20.05, 3.2, C.Limestone)
	for i, y in { 7, 14 } do
		b:box(`Hoop{i}`, -3.35, y, -3.35, 3.35, y + 0.5, 3.35, C.Iron, Kit.NOSHADOW)
	end
	b:box("Cap", -3.4, 20, -3.4, 3.4, 21.6, 3.4, SLATE)
	b:box("Cap2", -2.2, 21.6, -2.2, 2.2, 23, 2.2, SLATE, Kit.NOSHADOW)
	b:box("Finial", -0.35, 23, -0.35, 0.35, 24.8, 0.35, GOLD, Kit.DECOR)
	b:box("Ladder", -0.6, 1.2, -3.75, 0.6, 19.6, -3.35, C.WoodDark, Kit.NOSHADOW)
	return b:finish(base)
end

--[[
	Farmhouse (~38 parts): a white plastered house, its gable to the front under a clay tile roof
	with a timber gable and an attic window, a porch across the front (plank floor, three posts, a
	pent tile roof, cream rails), a green door with a lamp, a shuttered window with a flower box,
	side windows, a brick chimney.
]]
local function farmhouse(parent: any, cf: any, m: number)
	local b = house(parent, cf, {
		name = "Farmhouse",
		w = 13,
		d = 10,
		h = 8.6,
		rise = 6.4,
		wall = C.Plaster,
		roof = TILE,
		trim = C.Cream,
		gable = C.WoodLight,
		attic = true,
		door = m * 3,
		doorW = 2.6,
		doorH = 4.6,
		leaf = GREEN_PAINT,
		lantern = -m,
		win = {
			{
				"-z",
				-m * 2.8,
				2.6,
				2.8,
				3,
				shutter = GREEN_PAINT,
				box = { C.Flowers[1], C.Flowers[2] },
				cross = true,
			},
			{ "+x", 0, 3, 2.6, 2.8, shutter = GREEN_PAINT },
			{ "-x", 0, 3, 2.6, 2.8, shutter = GREEN_PAINT },
		},
		chimney = { -m * 3.4, 2.2 },
		porch = { x0 = -7.2, x1 = 7.2, d = 3.6, h = 5.6, roof = TILE },
	})
	return b:finish(b.base)
end

--[[
	The orangery (the east district's hero, ~34 parts): a glass house on a brick plinth in a white
	frame — glass walls, a glass gable roof with the eaves to the front, white eaves, ridge, corner
	posts and mullions, golden finials — with a projecting glass entrance bay under its own little
	gable, white double doors; inside, two citrus trees in clay tubs with orange fruit and staging
	along the back with flowers in the gateway colour.
]]
local function orangery(parent: any, cf: any, w: number, d: number, color: any)
	local b = Kit.builder(parent, "Orangery", cf)
	local x, z = w / 2, d / 2
	local white = C.White
	local base = b:box("Plinth", -x - 0.4, -0.8, -z - 0.4, x + 0.4, 2.2, z + 0.4, C.Brick)
	b:box("PlinthCap", -x - 0.6, 2, -z - 0.6, x + 0.6, 2.5, z + 0.6, C.Limestone, Kit.NOSHADOW)
	b:box("Glass", -x, 2.5, -z, x, 8.4, z, C.Glass, GLASS)
	gable(b, "Roof", -x - 0.2, x + 0.2, -z - 0.6, z + 0.6, 8.2, 4.4, C.Glass)
	for _, p in b.model:GetChildren() do
		if p.Name == "RoofF" or p.Name == "RoofB" then
			p.Transparency, p.CastShadow = 0.45, false
		end
	end
	for i, sz in { -1, 1 } do
		b:box(`Eaves{i}`, -x - 0.3, 8, sz * z - 0.35, x + 0.3, 8.6, sz * z + 0.35, white, Kit.NOSHADOW)
	end
	b:box("Ridge", -x - 0.5, 12, -0.5, x + 0.5, 12.7, 0.5, white, Kit.NOSHADOW)
	for i, sx in { -1, 1 } do
		b:box(`Corner{i}`, sx * x - 0.4, 2.5, -z - 0.4, sx * x + 0.4, 8, -z + 0.4, white, Kit.NOSHADOW)
		b:box(`CornerB{i}`, sx * x - 0.4, 2.5, z - 0.4, sx * x + 0.4, 8, z + 0.4, white, Kit.NOSHADOW)
		b:box(`Mullion{i}`, sx * x * 0.62 - 0.3, 2.5, -z - 0.25, sx * x * 0.62 + 0.3, 8, -z + 0.05, white, Kit.NOSHADOW)
		b:box(`Finial{i}`, sx * (x + 0.2) - 0.4, 12.7, -0.4, sx * (x + 0.2) + 0.4, 14, 0.4, GOLD, Kit.DECOR)
	end
	-- the entrance bay
	local bz = -z - 2.6
	b:box("BayPlinth", -3.8, -0.8, bz - 0.4, 3.8, 2.2, -z, C.Brick)
	b:box("Bay", -3.4, 2.2, bz, 3.4, 8.5, -z, C.Glass, GLASS)
	gable(b, "BayRoof", -3.9, 3.9, bz - 0.5, -z + 1.4, 8.4, 2.8, C.Glass, true)
	for _, p in b.model:GetChildren() do
		if p.Name == "BayRoofL" or p.Name == "BayRoofR" then
			p.Transparency, p.CastShadow = 0.45, false
		end
	end
	b:box("BayEaves", -4, 8.1, bz - 0.4, 4, 8.7, bz + 0.3, white, Kit.NOSHADOW)
	for i, sx in { -1, 1 } do
		b:box(`BayPost{i}`, sx * 3.4 - 0.4, 2.2, bz - 0.35, sx * 3.4 + 0.4, 8.1, bz + 0.45, white, Kit.NOSHADOW)
	end
	door(b, "Door", "-z", bz, 0, 2.2, 3.2, 5, white, mix(C.Glass, C.White, 0.3))
	b:box("Step", -2.4, -0.6, bz - 1.8, 2.4, 1.2, bz - 0.4, C.Limestone)
	-- inside: two citrus trees in tubs, staging with flowers along the back
	for i, sx in { -1, 1 } do
		local tx = sx * x * 0.55
		b:box(`Tub{i}`, tx - 1, 2.5, -1, tx + 1, 4, 1, C.RoofTerracotta, Kit.NOSHADOW)
		b:box(`Crown{i}`, tx - 1.7, 5.2, -1.6, tx + 1.7, 8, 1.6, C.Leaf2, Kit.DECOR)
		b:box(`Fruit{i}`, tx - 1.9, 6, -1.1, tx + 1.9, 6.9, -0.3, C.Orange, Kit.DECOR)
		b:box(`Trunk{i}`, tx - 0.25, 4, -0.25, tx + 0.25, 5.2, 0.25, C.Bark, Kit.DECOR)
	end
	b:box("Staging", -x + 1, 2.5, z - 2.6, x - 1, 4.2, z - 0.6, C.WoodLight, Kit.NOSHADOW)
	b:box("StagingBlooms", -x + 1.6, 4.2, z - 2.3, x - 1.6, 5.2, z - 0.9, color, Kit.DECOR)
	return b:finish(base)
end

--[[
	The florist's cottage (~50 parts): rose plaster under a thick straw thatch with the eaves to
	the front, a dormer in the thatch, a chimney; a door under a thatched hood with a lamp, a big
	shuttered window with a flower box overflowing, side windows; beside it a stepped flower stand
	with pots of blooms, a planted bed along the front.
]]
local function floristCottage(parent: any, cf: any, m: number)
	local b = house(parent, cf, {
		name = "FloristCottage",
		w = 13,
		d = 10,
		h = 8.4,
		rise = 6.6,
		ov = 1.6,
		og = 1.1,
		eaves = true,
		wall = ROSE,
		roof = THATCH,
		ridge = THATCH_RIDGE,
		trim = C.Cream,
		gable = ROSE,
		door = -m * 3.4,
		doorW = 2.6,
		doorH = 5,
		leaf = SAGE,
		hood = THATCH,
		lantern = m,
		win = {
			{ "-z", m * 2.6, 2.6, 3.4, 3, shutter = SAGE, box = { C.Flowers[3], C.Flowers[5] }, cross = true },
			{ "+x", 0, 3, 2.6, 2.8, cross = true },
			{ "-x", 0, 3, 2.6, 2.8, cross = true },
		},
		dormer = { m * 2.6, 3.8 },
		chimney = { -m * 4.2, 0.8 },
	})
	-- the flower stand beside the house: two tiers, pots of blooms on them
	local sx = m * 9.6
	b:box("Stand", sx - 1.6, -0.5, -4.4, sx + 1.6, 1.4, -0.4, C.WoodLight)
	b:box("Stand2", sx - 1.6, 1.4, -2.4, sx + 1.6, 2.8, -0.4, C.WoodLight)
	for i, p in { { -0.8, -3.4, 1.4, 1 }, { 0.8, -3.4, 1.4, 3 }, { -0.8, -1.4, 2.8, 2 }, { 0.8, -1.4, 2.8, 6 } } do
		local x = sx + p[1]
		b:box(`Pot{i}`, x - 0.65, p[3], p[2] - 0.65, x + 0.65, p[3] + 1.6, p[2] + 0.65, C.Flowers[p[4]], Kit.DECOR)
	end
	b:box("Leaves", sx - 1.5, 1.4, -4.3, sx + 1.5, 2, -2.5, C.Leaf2, Kit.DECOR)
	return b:finish(b.base)
end

-- Potting shed (~16 parts, front = -Z): sage plank walls under a shingle pent roof, a door and a
-- window, a potting bench by the door with clay pots and plants, a rake on the wall.
local function pottingShed(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "PottingShed", cf)
	local base = b:box("Base", -4.5, -0.8, -3.5, 4.5, 0.8, 3.5, C.Stone)
	b:box("Walls", -4, 0.8, -3, 4, 7.4, 3, SAGE)
	wedge(b, "Roof", Vector3.new(10, 2.6, 8.2), CFrame.new(0, 8.4, -0.1), SHINGLE)
	b:box("Eaves", -4.3, 6.85, -3.4, 4.3, 7.3, 3.4, C.Cream, Kit.NOSHADOW)
	door(b, "Door", "-z", -3, -1.8, 0.8, 2.4, 5, C.Cream, C.WoodDark)
	window(b, "Win", "-z", -3, 2.2, 3.4, 2.6, 2.4, C.Cream, { cross = true })
	b:box("Bench", 4.4, 2.6, -2.6, 6.6, 3.1, 2.6, C.WoodLight)
	b:box("BenchLegs", 4.6, -0.3, -2.4, 6.4, 2.6, 2.4, C.Wood, Kit.NOSHADOW)
	for i, z in { -1.3, 1.2 } do
		b:box(`Pot{i}`, 4.9, 3.1, z - 0.7, 6.1, 4.1, z + 0.7, C.RoofTerracotta, Kit.DECOR)
		b:box(`Plant{i}`, 4.8, 4.1, z - 0.8, 6.2, 5.3, z + 0.8, if i == 1 then C.Leaf2 else color, Kit.DECOR)
	end
	b:box("Rake", -4.45, 1.2, 1, -4.05, 6.6, 1.4, C.Wood, Kit.DECOR)
	return b:finish(base)
end

--[[
	Log lodge (the west district's hero, ~55 parts): light log walls with darker log courses and
	cut-wood corner ends, its gable to the front under a slate roof with a cut-wood gable and an
	attic window; a porch across the front on log posts under a pent roof with rails and a bench,
	a door with a lamp, shuttered windows with flower boxes, a stepped stone chimney up the outside
	of the side wall away from `m`, firewood stacked beside it.
]]
local function logLodge(parent: any, cf: any, color: any, m: number)
	local b = house(parent, cf, {
		name = "LogLodge",
		w = 16,
		d = 11,
		h = 9,
		rise = 7.4,
		wall = LOGS,
		roof = SLATE,
		trim = C.CutWood,
		gable = C.CutWood,
		base = C.StoneLight,
		attic = true,
		door = 0,
		doorW = 3,
		doorH = 5.4,
		leaf = C.WoodDark,
		lantern = m,
		win = {
			{ "-z", -5, 2.8, 2.8, 3, shutter = color, box = { C.Flowers[6], C.Flowers[2] }, cross = true },
			{ "-z", 5, 2.8, 2.8, 3, shutter = color, box = { C.Flowers[1], C.Flowers[6] }, cross = true },
			{ if m > 0 then "+x" else "-x", 1, 3, 2.6, 2.8, shutter = color },
		},
		porch = { x0 = -8.6, x1 = 8.6, d = 3.2, h = 6.4, roof = SLATE, post = C.Bark },
	})
	for i, y in { 2.6, 4.7, 6.8 } do
		b:box(`Logs{i}`, -8.1, y, -5.6, 8.1, y + 0.7, 5.6, C.Bark, Kit.NOSHADOW)
	end
	for i, sx in { -1, 1 } do
		b:box(`LogEnds{i}`, sx * 8 - 0.6, 0.9, -6.1, sx * 8 + 0.6, 8.6, -4.9, C.CutWood, Kit.NOSHADOW)
	end
	-- the stone chimney up the outside of the far side wall
	local cx = -m * 9.3
	b:box("ChimneyBase", cx - 1.6, -0.6, -1.4, cx + 1.6, 6, 2.6, C.StoneLight)
	b:box("Chimney", cx - 1.1, 6, -0.9, cx + 1.1, 18.6, 2.1, C.Stone)
	b:box("ChimneyCap", cx - 1.45, 18.6, -1.25, cx + 1.45, 19.2, 2.45, C.StoneDark, Kit.NOSHADOW)
	b:box("Firewood", cx - 1.4, -0.4, -4.6, cx + 1.4, 3, -1.8, C.Bark)
	b:box("FirewoodEnds", cx - 1.45, 0.3, -4.65, cx + 1.45, 2.6, -4.2, C.CutWood, Kit.NOSHADOW)
	return b:finish(b.base)
end

--[[
	Ranger hut (~24 parts): a little timber cabin on four stilts with a plank deck and rails, a
	shingle roof, a ladder up to the deck, a flag, a board «ЛЕСНИК» on the rail, a lantern.
]]
local function rangerHut(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "RangerHut", cf)
	local first
	for i, p in { { -4, -4 }, { 4, -4 }, { 4, 4 }, { -4, 4 } } do
		local post = b:box(`Stilt{i}`, p[1] - 0.6, -0.6, p[2] - 0.6, p[1] + 0.6, 6, p[2] + 0.6, C.Bark)
		first = first or post
	end
	b:box("Deck", -5.2, 5.4, -6.2, 5.2, 6.2, 5.2, C.Plank)
	b:box("Cabin", -3.6, 6.2, -2.4, 3.6, 12, 4.4, C.WoodLight)
	gable(b, "Roof", -4.8, 4.8, -3.4, 5.4, 11.6, 3.6, SHINGLE)
	b:box("Ridge", -5, 14.8, 0.5, 5, 15.6, 1.5, C.WoodDark, Kit.NOSHADOW)
	door(b, "Door", "-z", -2.4, -1.4, 6.2, 2.2, 4.4, C.WoodDark, C.Wood)
	window(b, "Win", "-z", -2.4, 1.8, 8, 2.4, 2.4, C.WoodDark, { cross = true })
	b:box("RailF", -5.2, 8.6, -6.2, 5.2, 9.2, -5.6, C.Wood, Kit.NOSHADOW)
	b:box("RailL", -5.2, 8.6, -6.2, -4.6, 9.2, 5.2, C.Wood, Kit.NOSHADOW)
	b:box("RailPostL", -5.35, 6.2, -6.35, -4.4, 9.45, -5.4, C.WoodDark)
	b:box("RailPostR", 4.4, 6.2, -6.35, 5.35, 9.45, -5.4, C.WoodDark)
	local sign = b:box("Sign", -2.6, 7.4, -6.5, 2.6, 9.6, -6.15, C.Cream)
	Kit.sign(sign, Enum.NormalId.Front, "ЛЕСНИК", INK, nil, { pps = 30 })
	b:pole("FlagPole", 0.4, 4.6, -5.4, 9.2, 19, C.WoodDark)
	b:box("Flag", 4.8, 16, -5.55, 8, 18.4, -5.25, color, Kit.DECOR)
	b:box("Lamp", -3.2, 9.6, -2.9, -2.4, 10.8, -2.4, C.Glow, Kit.NEON_DECOR)
	b:box("WaterBarrel", -7.4, -0.4, 2, -5.6, 2.4, 3.8, C.Wood, Kit.NOSHADOW)
	-- a ladder (a climbable truss, Roblox sizes them in 2-stud steps) up the right side
	U.partCount += 1
	U.new("TrussPart", {
		Name = "Ladder",
		Size = Vector3.new(2, 6, 2),
		CFrame = cf * CFrame.new(6.2, 3.2, -3),
		Color = C.Wood,
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanTouch = false,
		Locked = true,
	}, b.model)
	return b:finish(first)
end

-- Woodshed (~9 parts, front = -Z): an open shed — a back wall, two posts, a shingle pent roof —
-- full of split logs, a chopping block with an axe in front.
local function woodshed(parent: any, cf: any)
	local b = Kit.builder(parent, "Woodshed", cf)
	local floor0 = b:box("Floor", -4.4, -0.6, -2.4, 4.4, 0.4, 2.4, C.StoneLight, Kit.NOSHADOW)
	b:box("Back", -4.4, 0.4, 1.8, 4.4, 6.6, 2.4, C.Wood)
	for i, sx in { -1, 1 } do
		b:box(`Post{i}`, sx * 4 - 0.4, 0.4, -2.2, sx * 4 + 0.4, 5.6, -1.4, C.Bark)
	end
	wedge(b, "Roof", Vector3.new(10, 1.8, 6.2), CFrame.new(0, 6.9, -0.2), SHINGLE)
	b:box("Logs", -3.5, 0.4, -0.8, 3.5, 4.4, 1.8, C.Bark)
	b:box("LogEnds", -3.4, 0.8, -0.9, 3.4, 4, -0.6, C.CutWood, Kit.NOSHADOW)
	b:box("Block", -1, -0.4, -5, 1, 1.4, -3, C.CutWood)
	b:box("Axe", -0.15, 1.4, -4.3, 0.15, 3.4, -3.9, C.WoodDark, Kit.DECOR)
	return b:finish(floor0)
end

--[[
	A rail fence (posts + one chunky rail a segment) along a polyline of local points {x, z}
	in a builder frame on ground y (one height). 2n - 1 parts.
]]
local function fence(b: any, name: string, pts: { { number } }, y: number, color: any?)
	for i, p in pts do
		b:box(`{name}Post{i}`, p[1] - 0.55, y - 0.5, p[2] - 0.55, p[1] + 0.55, y + 3.6, p[2] + 0.55, C.WoodDark)
		local q = pts[i + 1]
		if q then
			local a, c = Vector3.new(p[1], y + 2.5, p[2]), Vector3.new(q[1], y + 2.5, q[2])
			b:block(
				`{name}Rail{i}`,
				Vector3.new(0.5, 0.75, (c - a).Magnitude),
				CFrame.lookAt((a + c) / 2, c),
				color or C.Wood,
				Kit.NOSHADOW
			)
		end
	end
end

-- Paddock w x d (~14 parts, front = -Z): a trodden earth floor, a rail fence round it with a
-- gate gap on the +X side and one at the back at x = gx (the barn ramp), a water trough inside.
-- No animals.
local function paddock(parent: any, cf: any, w: number, d: number, gx: number)
	local b = Kit.builder(parent, "Paddock", cf)
	local x, z = w / 2, d / 2
	local earth = b:box("Floor", -x + 0.3, -0.5, -z + 0.3, x - 0.3, 0.22, z - 0.3, EARTH, Kit.NOSHADOW)
	fence(b, "FenceA", { { x, -2.5 }, { x, -z }, { -x, -z }, { -x, z }, { gx - 3.6, z } }, 0)
	fence(b, "FenceB", { { gx + 3.6, z }, { x, z }, { x, 2.5 } }, 0)
	b:box("Trough", -x + 2, -0.2, -z + 2, -x + 8, 1.6, -z + 4, C.Wood)
	b:box("TroughWater", -x + 2.4, 1.2, -z + 2.4, -x + 7.6, 1.75, -z + 3.6, C.WaterLight, Kit.DECOR)
	return b:finish(earth)
end

--[[
	Per theme: the climb ("steps" stone stairs, "wood" plank stairs, "ramps" a paved path with
	wedge ramps, "switchback" plank stairs in three legs to a deck off the axis), the lantern
	spots beside it, the district pieces { kind, x, z, w, d, yaw, ... } on the terraces either
	side (w x d: the footprint, which must be flat; nudged to a flat spot nearby, dropped where
	there is none), the lanes { x0, z0, x1, z1 } from the climb to the buildings (1-stud steps
	up the terrace walls, paved on the flats) and the number of riser dressings (bush clumps,
	rocks and grass tufts at the foot of the terrace walls). The terraces behind every plaza
	are 16-stud bands (z 44-60, 60-76, 76-92, ...) a step (4) higher each, split at x = ±16 (the
	valley of the climb) and ±48 / ±64. The hero building of each district stands on the second
	band beside the climb, so the view up from the plaza looks into a street.
]]
local DISTRICTS = {
	-- south: a farm — a big gambrel barn with a ramp down into its paddock and a silo on the
	-- left, the farmhouse with its kitchen garden, a wheat field, pumpkins and hay on the right
	playground = {
		climb = "ramps",
		lanterns = { { -7.5, 64 } },
		pieces = {
			{ "barn", -41, 84, 27, 15, 0 },
			{ "silo", -20.5, 84, 8, 8, 0 },
			{ "paddock", -40, 68, 30, 12, 0 },
			{ "farmhouse", 31, 68, 16, 15, 0 },
			{ "crop", 52.5, 68, 12, 7, 0, "cabbage", 2, 2.3 },
			{ "crop", 32, 51, 24, 7, 0, "wheat", 2, 2.2 },
			{ "pumpkins", 36, 84, 14, 8, 0 },
			{ "hay", 54, 84, 7, 5, 20 },
		},
		lanes = { { -4.5, 68, -25.5, 68 }, { 4.5, 57.6, 28, 57.6 }, { 28, 57.6, 28, 61.2 } },
		lane = { C.Flagstone, C.FlagstoneDark },
		risers = 2,
	},
	-- east: a flower garden — the orangery and the potting shed on the right, the florist's
	-- cottage on the left, planted flower beds below them, a hedge maze up the hill
	garden = {
		climb = "ramps",
		lanterns = { { 7.5, 63.5 } },
		pieces = {
			{ "orangery", 33, 68, 25, 15, 0 },
			{ "shed", 57.5, 68, 11, 9, 0 },
			{ "florist", -33, 68, 22, 14, 0 },
			{ "bed", -32, 51, 22, 6, 0, { C.Flowers[1], C.Flowers[2] } },
			{ "bed", 32, 51, 22, 6, 0, { C.Flowers[7], C.Flowers[6] } },
			{ "maze", -40, 84, 23, 14, 0, 1.6 },
		},
		lanes = {
			{ 4.5, 57.6, 33, 57.6 },
			{ 33, 57.6, 33, 61.2 },
			{ -4.5, 57.6, -38.8, 57.6 },
			{ -38.8, 57.6, -38.8, 61.2 },
		},
		lane = { PAVE, PAVE2 },
		risers = 1,
	},
	-- north: the fishermen's row — the harbour-master's house with its lookout tower on the left,
	-- the net loft and the smokehouse with its fish-drying rack on the right, a rowboat pulled up
	-- on the grass
	market = {
		climb = "wood",
		lanterns = { { -6.5, 64.5 } },
		pieces = {
			{ "harbour", -37, 68.5, 25, 15, 0 },
			{ "netloft", 29, 68, 13, 14, 0 },
			{ "smokehouse", 47, 68, 12, 10, 0 },
			{ "rack", 32, 51, 12, 3, 0 },
			{ "rowboat", -40, 86, 6, 11, -80, C.BoatPaint[1] },
		},
		lanes = {
			{ -4.5, 57.6, -40, 57.6 },
			{ -40, 57.6, -40, 61.2 },
			{ 4.5, 57.6, 47, 57.6 },
			{ 29, 57.6, 29, 61.2 },
		},
		lane = { C.WoodLight, C.Plank },
		risers = 1,
	},
	-- west: the woods — a log lodge with a porch above the camp, a ranger hut on stilts on the
	-- left where the zigzag path turns, a woodshed below
	picnic = {
		climb = "switchback",
		deckX = -24,
		turnZ = 80,
		lanterns = { { 6.2, 73.4 } },
		pieces = {
			{ "lodge", 38, 84, 21, 15, 0 },
			{ "ranger", -48, 84, 15, 12, 0 },
			{ "woodshed", 30, 51, 10, 9, 0 },
			{ "logs", 42, 51, 6, 4, 10 },
		},
		lanes = { { 3.5, 73, 38, 73 }, { 38, 73, 38, 76.8 }, { -27.5, 81, -41.5, 81 } },
		lane = { C.WoodLight, C.Plank },
		risers = 1,
	},
}

local BUILDINGS = {
	barn = true,
	silo = true,
	farmhouse = true,
	harbour = true,
	netloft = true,
	smokehouse = true,
	orangery = true,
	florist = true,
	shed = true,
	lodge = true,
	ranger = true,
	woodshed = true,
}

-- (m: the side towards the climb, +1 when the piece stands left of it at x < 0)
local function towards(q: any): number
	return if q[2] < 0 then 1 else -1
end

local PIECES = {
	crop = function(parent: any, cf: any, q: any)
		cropBed(parent, cf, q[4], q[5], q[7], q[8], q[9])
	end,
	hay = function(parent: any, cf: any)
		hayStack(parent, cf)
	end,
	pumpkins = function(parent: any, cf: any, q: any)
		pumpkinPatch(parent, cf, q[4], q[5])
	end,
	maze = function(parent: any, cf: any, q: any)
		hedgeMaze(parent, cf, q[7])
	end,
	rowboat = function(parent: any, cf: any, q: any)
		beachedBoat(parent, cf, q[7])
	end,
	logs = function(parent: any, cf: any)
		logPile(parent, cf)
	end,
	rack = function(parent: any, cf: any)
		dryingRack(parent, cf)
	end,
	-- a planted flower bed: stems with blooms in two tones, a limestone kerb
	bed = function(parent: any, cf: any, q: any)
		Kit.prop("flowerBed", parent, cf, {
			width = q[4] - 1,
			depth = q[5] - 1,
			colors = q[7],
			spacing = 2.6,
			max = 6,
			seed = floor(q[2] * 7 + q[3]),
		})
	end,
	-- the harbour house: its tower on the side towards the climb
	harbour = function(parent: any, cf: any, q: any, color: any)
		local m = towards(q)
		harbourHouse(parent, cf * CFrame.new(-m * 3, 0, 0.6), color, m)
	end,
	netloft = function(parent: any, cf: any, q: any, color: any)
		netLoft(parent, cf * CFrame.new(0, 0, 0.8), color, if q[2] < 0 then "-x" else "+x")
	end,
	smokehouse = function(parent: any, cf: any)
		smokehouse(parent, cf * CFrame.new(-0.8, 0, 0))
	end,
	-- the barn (its lean-to on the far side) with a plank ramp from its door down into the paddock
	-- on the terrace below
	barn = function(parent: any, cf: any, q: any)
		local m = towards(q)
		local bcf = cf * CFrame.new(m * 2.8, 0, 0)
		local model = bigBarn(parent, bcf, m)
		Kit.ramp(model, (bcf * CFrame.new(0, 0.9, -7.4)).Position, (bcf * CFrame.new(0, -3.75, -16)).Position, {
			width = 6,
			thick = 0.8,
			color = C.Plank,
			name = "Ramp",
		})
	end,
	silo = function(parent: any, cf: any)
		silo(parent, cf)
	end,
	farmhouse = function(parent: any, cf: any, q: any)
		farmhouse(parent, cf * CFrame.new(0, 0, 1.6), towards(q))
	end,
	paddock = function(parent: any, cf: any, q: any)
		paddock(parent, cf, q[4], q[5], 0.85)
	end,
	orangery = function(parent: any, cf: any, q: any, color: any)
		orangery(parent, cf * CFrame.new(0, 0, 2), q[4] - 3, q[5] - 5, color)
	end,
	florist = function(parent: any, cf: any, q: any)
		local m = towards(q)
		floristCottage(parent, cf * CFrame.new(-m * 2.4, 0, 1.2), m)
	end,
	shed = function(parent: any, cf: any, _q: any, color: any)
		pottingShed(parent, cf * CFrame.new(-1, 0, 0), color)
	end,
	-- the lodge's porch reaches out in front, so the model sits behind the footprint's centre
	lodge = function(parent: any, cf: any, q: any, color: any)
		logLodge(parent, cf * CFrame.new(0, 0, 1.6), color, towards(q))
	end,
	ranger = function(parent: any, cf: any, _q: any, color: any)
		rangerHut(parent, cf * CFrame.new(-1, 0, 0), color)
	end,
	woodshed = function(parent: any, cf: any)
		woodshed(parent, cf * CFrame.new(0, 0, 1.5))
	end,
}

--[[
	Riser dressing: bush clumps (two leaf blocks, some with a bloom), rocks (a stone with a
	lighter top) and grass tufts at the foot of the district's terrace walls (the 4-stud grass
	risers), their backs 0.3 into the wall: spots where the ground 2.5 studs on (uphill, or
	sideways) is one step higher and the spot itself is flat, unclaimed and clear of the climb;
	a spread-out pick (16+ apart) of up to n. 1-3 parts each.
]]
local RISER_BLOOMS = { C.Pink, C.Cream, C.Yellow, C.Flowers[1], C.Purple, C.Orange }

local function dressRisers(model: any, world: any, origin: any, G: number, n: number, seed: number)
	local r = Kit.rng(seed)
	local function ground(x: number, z: number): number
		local p = (origin * CFrame.new(x, 0, z)).Position
		return world:heightAt(p.X, p.Z)
	end
	local spots = {}
	for z = 44, 132, 2 do
		for x = -76, 76, 2 do
			local h = ground(x, z)
			local p = (origin * CFrame.new(x, 0, z)).Position
			if abs(x) > 11 and h > G - 0.1 and not Kit.isClaimed(p.X, p.Z, 3) and not world:isReserved(p.X, p.Z, 2) then
				for _, d in { { 0, 1 }, { if x < 0 then -1 else 1, 0 } } do
					local up = ground(x + d[1] * 2.5, z + d[2] * 2.5)
					local sx, sz = d[2], d[1] -- along the wall
					if
						up == h + 4
						and ground(x - d[1] * 2, z - d[2] * 2) == h
						and ground(x + sx * 2.5, z + sz * 2.5) == h
						and ground(x - sx * 2.5, z - sz * 2.5) == h
					then
						table.insert(spots, { x = x, z = z, h = h, dx = d[1], dz = d[2], score = r() - z / 90 })
					end
				end
			end
		end
	end
	table.sort(spots, function(a, b)
		return a.score > b.score
	end)
	local placed = {}
	local count = 0
	for _, s in spots do
		if count >= n then
			break
		end
		local ok = true
		for _, o in placed do
			if (o[1] - s.x) ^ 2 + (o[2] - s.z) ^ 2 < 16 * 16 then
				ok = false
				break
			end
		end
		if ok then
			count += 1
			table.insert(placed, { s.x, s.z })
			-- the wall: step on from the spot until the ground rises
			local t = 0
			while t < 3 and ground(s.x + s.dx * t, s.z + s.dz * t) == s.h do
				t += 0.25
			end
			local wx, wz = s.x + s.dx * (t - 0.25), s.z + s.dz * (t - 0.25)
			local yaw = math.atan2(s.dx, s.dz) -- local +Z into the wall
			local cf = origin * CFrame.new(wx, s.h - G, wz) * CFrame.Angles(0, yaw, 0)
			local kind = count % 5
			local b = Kit.builder(model, if kind == 1 or kind == 4 then "Rocks" else "Bush", cf)
			local o = r(-1.2, 1.2) -- sideways
			if kind == 1 or kind == 4 then
				local w = r(3, 4.4)
				local stone = b:box("Rock", o - w / 2, -0.6, -2.4, o + w / 2, r(1.8, 2.8), 0.4, C.Stone)
				b:box(
					"RockTop",
					o - w / 2 + 0.5,
					1.2,
					-1.8,
					o + w / 2 - 0.9,
					r(2.9, 3.4),
					0.5,
					C.StoneLight,
					Kit.NOSHADOW
				)
				if kind == 4 then
					b:box("Tuft", o + w / 2 - 0.4, -0.3, -2.8, o + w / 2 + 1.6, 1.4, -1, C.Leaf2, Kit.DECOR)
				end
				b:finish(stone)
			else
				local w = r(4.2, 5.6)
				local bush = b:box("Leaves", o - w / 2, -0.4, -3, o + w / 2, r(2.8, 3.6), 0.4, C.Leaf1, Kit.DECOR)
				b:box("Top", o - w / 2 + 0.8, 2.2, -2.3, o + w / 2 - 1.2, r(3.9, 4.6), 0.5, C.Leaf3, Kit.DECOR)
				if kind == 2 then
					local c = RISER_BLOOMS[floor(r(1, #RISER_BLOOMS + 0.99))]
					b:box("Bloom", o + w / 2 - 2.2, 2.4, -3.3, o + w / 2 - 0.8, 3.7, -2, c, Kit.DECOR)
				end
				b:finish(bush)
			end
			Kit.claim((cf.Position).X, (cf.Position).Z, 3)
		end
	end
end

-- Builds the district of a theme on the hill behind its plaza (origin: the plaza frame on the
-- ground at GroundTop G). Each piece stands where the ground under its whole footprint is flat:
-- at its spot, or the nearest spot up to 8 studs off it that is flat, clear of the climb (open,
-- |x| > 9) and of the pieces placed before it. Then the lanes from the climb to the buildings,
-- the lanterns and the riser dressing (which keeps off everything claimed). The trees round the
-- district come from Nature (its gateway wedge pass), which keeps off the claims.
local function buildDistrict(parent: any, world: any, origin: any, G: number, d: any, color: any, seed: number)
	local model = U.model(parent, "District")
	local function ground(x: number, z: number): number
		local p = (origin * CFrame.new(x, 0, z)).Position
		return world:heightAt(p.X, p.Z)
	end
	local function flat(x: number, z: number, w: number, dd: number): number?
		local h = nil
		for _, fx in { -0.5, -0.25, 0, 0.25, 0.5 } do
			for _, fz in { -0.5, -0.25, 0, 0.25, 0.5 } do
				local g = ground(x + fx * w, z + fz * dd)
				if h and g ~= h then
					return nil
				end
				h = g
			end
		end
		return h
	end
	local placed: { { number } } = {} -- footprints {x0, z0, x1, z1}
	local function free(x: number, z: number, w: number, dd: number): boolean
		if math.abs(x) - w / 2 < 9 then
			return false
		end
		for _, r in placed do
			if x + w / 2 > r[1] - 1 and x - w / 2 < r[3] + 1 and z + dd / 2 > r[2] - 1 and z - dd / 2 < r[4] + 1 then
				return false
			end
		end
		return true
	end
	local NUDGE = {}
	for _, dx in { 0, 4, -4, 8, -8 } do
		for _, dz in { 0, 4, -4, 8, -8 } do
			table.insert(NUDGE, { dx, dz })
		end
	end
	table.sort(NUDGE, function(a, b)
		local da, db = a[1] * a[1] + a[2] * a[2], b[1] * b[1] + b[2] * b[2]
		if da ~= db then
			return da < db
		end
		return a[1] * 100 + a[2] > b[1] * 100 + b[2]
	end)
	for _, q in d.pieces do
		local yaw = q[6]
		-- the footprint: w x d, turned a quarter (or any other angle: its bounding square)
		local w, dd = q[4], q[5]
		if yaw % 180 == 90 then
			w, dd = dd, w
		elseif yaw % 180 ~= 0 then
			w = max(w, dd)
			dd = w
		end
		local x, z, h = q[2], q[3], nil
		for _, n in NUDGE do
			local tx, tz = q[2] + n[1], q[3] + n[2]
			local th = if free(tx, tz, w, dd) then flat(tx, tz, w, dd) else nil
			if th then
				x, z, h = tx, tz, th
				break
			end
		end
		if h then
			PIECES[q[1]](model, origin * CFrame.new(x, h - G, z) * CFrame.Angles(0, rad(yaw), 0), q, color)
			if q[1] ~= "clearing" then -- (a clearing is the floor under the pieces on it)
				table.insert(placed, { x - w / 2, z - dd / 2, x + w / 2, z + dd / 2 })
			end
			-- a view corridor from the plaza to every building (no tree of Nature in front of it)
			if BUILDINGS[q[1]] then
				for t = 0.25, 0.8, 0.15 do
					local p = (origin * CFrame.new(x * t, 0, 20 + (z - 20) * t)).Position
					Kit.claim(p.X, p.Z, 7)
				end
			end
			-- claims along the long side (Nature keeps its trees off the pieces)
			local long, short = max(w, dd), min(w, dd)
			for t = -long / 2 + short / 2, long / 2 - short / 2 + 0.01, short do
				local lx, lz = if w >= dd then x + t else x, if w >= dd then z else z + t
				local p = (origin * CFrame.new(lx, 0, lz)).Position
				Kit.claim(p.X, p.Z, short * 0.72 + 2)
			end
		end
	end
	-- the lanes from the climb to the buildings: 1-stud steps up the terrace walls, paved on the
	-- flats
	for i, l in d.lanes or {} do
		local a = (origin * CFrame.new(l[1], 0, l[2])).Position
		local b = (origin * CFrame.new(l[3], 0, l[4])).Position
		Kit.stairs(model, world, Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z), {
			width = 3.2,
			color = d.lane[1],
			color2 = d.lane[2],
			pave = true,
			name = `Lane{i}`,
		})
		for t = 0, 1, 0.25 do
			local p = a:Lerp(b, t)
			Kit.claim(p.X, p.Z, 3.5)
		end
	end
	for _, l in d.lanterns do
		local h = flat(l[1], l[2], 2.6, 2.6)
		if h then
			lantern(model, origin * CFrame.new(l[1], h - G, l[2]), color)
			local p = (origin * CFrame.new(l[1], 0, l[2])).Position
			Kit.claim(p.X, p.Z, 2.5)
		end
	end
	dressRisers(model, world, origin, G, d.risers or 0, seed)
	return model
end

--------------------------------------------------------------------------------------------
-- The plazas
--------------------------------------------------------------------------------------------

-- Round plaza paving in visible rings (a sheet of one tone reads as unfinished at eye level): a
-- band of the deep tone at r1..r2 with the light flags again inside it. 6 parts.
local function ringPaving(paving: any, r1: number, r2: number)
	disc(paving, "Ring", 0, 0, r2, -0.5, FLOOR + 0.04, PAVE3)
	disc(paving, "Inner", 0, 0, r1, -0.45, FLOOR + 0.08, PAVE)
end

-- A round mosaic medallion at (x, z) (top at y): a limestone disc with a cross in the gateway
-- colour and a golden hub. 6 parts.
local function medallion(paving: any, x: number, z: number, r: number, y: number, color: any)
	disc(paving, "Medallion", x, z, r, -0.4, y, C.Limestone)
	paving:box("MedallionNS", x - 0.55, -0.35, z - r + 0.9, x + 0.55, y + 0.06, z + r - 0.9, color, Kit.NOSHADOW)
	paving:box("MedallionEW", x - r + 0.9, -0.35, z - 0.55, x + r - 0.9, y + 0.05, z + 0.55, color, Kit.NOSHADOW)
	paving:box("MedallionHub", x - 1.1, -0.3, z - 1.1, x + 1.1, y + 0.1, z + 1.1, GOLD, Kit.NOSHADOW)
end

-- A planter of jewel-tone flowers in a limestone box (Props.planter, 7 parts).
local function planter(model: any, cf: any, c1: any, c2: any, seed: number)
	Kit.prop("planter", model, cf, {
		variant = "flowers",
		color = C.Limestone,
		colors = { c1, c2 },
		scale = 1.1,
		seed = seed,
	})
end

-- Each theme gets the plaza model, `at(x, z, yaw)` (local CFrame on the paving; yaw in degrees
-- or "centre"), the paving builder, the viewpoint builder and its hill info { world, origin,
-- deckZ0, color }; returns the viewpoint's plinth top (local y).

local function marketPlaza(model: any, at: any, paving: any, view: any, h: any): number
	local color = h.color
	-- a square market of stone flags with a checker of darker flags, a kerb all round and kerb
	-- joints along the seams of the checker
	paving:box("Square", -36, -0.6, -36, 36, FLOOR, 36, PAVE, Kit.NOSHADOW)
	paving:box("Border", -38, -0.7, -38, 38, FLOOR - 0.15, 38, KERB, Kit.NOSHADOW)
	for i = 0, 3 do
		for j = 0, 3 do
			if (i + j) % 2 == 0 then
				local x0, z0 = -36 + i * 18, -36 + j * 18
				-- (the tiles on the square's rim stop 0.1 short of its sides)
				local ax, az = max(x0, -35.9), max(z0, -35.9)
				local bx, bz = min(x0 + 18, 35.9), min(z0 + 18, 35.9)
				paving:box(`Tile{i}_{j}`, ax, -0.5, az, bx, FLOOR + 0.12, bz, PAVE3, Kit.NOSHADOW)
			end
		end
	end
	for k, c in { -18, 0, 18 } do
		paving:box(`JointX{k}`, -35.8, -0.4, c - 0.35, 35.8, FLOOR + 0.17, c + 0.35, KERB, Kit.NOSHADOW)
		paving:box(`JointZ{k}`, c - 0.35, -0.4, -35.8, c + 0.35, FLOOR + 0.16, 35.8, KERB, Kit.NOSHADOW)
	end
	-- a compass rose inlaid where the four middle flags meet
	paving:box("CompassNS", -1.1, -0.4, -7.5, 1.1, FLOOR + 0.22, 7.5, C.Limestone, Kit.NOSHADOW)
	paving:box("CompassEW", -7.5, -0.4, -1.1, 7.5, FLOOR + 0.2, 1.1, C.Limestone, Kit.NOSHADOW)
	paving:box("CompassHub", -2.2, -0.4, -2.2, 2.2, FLOOR + 0.28, 2.2, GOLD, Kit.NOSHADOW)
	-- the fountain off the axis (front right) in a ring of planters and benches, two stalls
	-- facing the square
	fountain(model, at(13, -8), color)
	for i, p in { { 13, -21, 0 }, { 26, -8, -90 } } do
		Kit.bench(model, at(p[1], p[2], p[3]), { length = 7, color = C.WoodLight, legs = C.WoodDark })
	end
	for i, p in { { 22.5, -18 }, { 3.5, -18 } } do
		Kit.prop("planter", model, at(p[1], p[2], 45), {
			variant = if i == 1 then "flowers" else "topiary",
			color = C.Limestone,
			colors = { C.Flowers[1], C.Flowers[5] },
			scale = 1.15,
			seed = i * 3,
		})
	end
	-- (every stall and board faces the square: front = -Z turned towards the centre)
	stall(model, at(-24, -10, -90), "РЫБА", color, "fish", h.roof)
	stall(model, at(26, 18, 60), "СНАСТИ", color, "tackle", h.roof)
	noticeBoard(model, at(-28, 10, -90), h.roof)
	-- lamps in the square's back corners
	for i, p in { { -31, 31 }, { 31, 31 } } do
		Kit.lamp(model, at(p[1], p[2]), { trim = C.Iron, post = C.WoodDark, name = `Lamp{i}` })
	end
	-- up the hill: a fenced deck beside the lighthouse (rails, bench, telescope)
	local z0 = h.deckZ0
	local top = plinth(view, h.world, h.origin, -17, z0, 17, z0 + 20, C.StoneLight)
	Kit.prop("lighthouse", view.model, h.origin * CFrame.new(-9, top, z0 + 11), { stripe = C.RoofRed })
	view:box("RailFront", 4, top + 2.6, z0, 17, top + 3.4, z0 + 0.8, C.Wood, Kit.NOSHADOW)
	view:box("RailR", 16.2, top + 2.6, z0, 17, top + 3.4, z0 + 20, C.Wood, Kit.NOSHADOW)
	view:box("RailBack", -2, top + 2.6, z0 + 19.2, 17, top + 3.4, z0 + 20, C.Wood, Kit.NOSHADOW)
	for i, p in { { 4, z0 }, { 16, z0 }, { 16, z0 + 19 } } do
		view:box(`RailPost{i}`, p[1] - 0.1, top, p[2] - 0.1, p[1] + 1.1, top + 3.9, p[2] + 1.1, C.WoodDark)
	end
	telescope(view, 13, top, z0 + 3.5)
	Kit.bench(view.model, h.origin * CFrame.new(7, top, z0 + 12), { length = 7 })
	return top
end

local function gardenPlaza(model: any, at: any, paving: any, view: any, h: any): number
	local color = h.color
	-- a round plaza with four hedge beds round a cross of paths (the paths in the deep tone), a
	-- kerb ring, a medallion where the paths cross
	disc(paving, "Pad", 0, 0, 40, -0.6, FLOOR, PAVE)
	paving:box("PathX", -38, -0.5, -4.5, 38, FLOOR + 0.12, 4.5, PAVE3, Kit.NOSHADOW)
	paving:box("PathZ", -4.5, -0.5, -38, 4.5, FLOOR + 0.12, 38, PAVE3, Kit.NOSHADOW)
	medallion(paving, 0, 0, 6, FLOOR + 0.18, color)
	local beds = { { C.Flowers[1], C.Flowers[2] }, { C.Flowers[7], C.Flowers[5] }, { C.Flowers[6], C.Flowers[2] } }
	for i, p in { { -17, -17 }, { 17, -17 }, { -17, 17 } } do
		gardenBed(model, at(p[1], p[2], if p[1] < 0 then 90 else -90), 16, 9, beds[i][1], beds[i][2], i * 17)
	end
	-- the wishing well stands in the fourth bed (back right, off the axis); a rose pergola spans
	-- the axis, the stall and the photo frame on the cross paths
	wishingWell(model, at(17, 17, -45), h.roof)
	stall(model, at(-27, 1, -90), "ЦВЕТЫ", color, "flowers", h.roof)
	photoFrame(model, at(27, 1, 90), color)
	Kit.bench(model, at(-9, -26, 0), { length = 7, color = C.WoodLight, legs = C.WoodDark })
	-- a gazebo on the hill: cream posts, a stepped thatch roof
	local z0 = h.deckZ0
	local top = plinth(view, h.world, h.origin, -8, z0, 8, z0 + 16, C.StoneLight)
	local za, zb = z0 + 1.5, z0 + 14.5
	for i, p in { { -6, za }, { 6, za }, { 6, zb }, { -6, zb } } do
		view:box(`Post{i}`, p[1] - 0.7, top, p[2] - 0.7, p[1] + 0.7, top + 9, p[2] + 0.7, C.Cream)
	end
	local zc = (za + zb) / 2
	view:box("Eaves", -8.9, top + 8.6, zc - 8.9, 8.9, top + 9.2, zc + 8.9, C.Cream, Kit.NOSHADOW)
	view:box("Roof1", -8.6, top + 9.2, zc - 8.6, 8.6, top + 10.6, zc + 8.6, h.roof)
	view:box("Roof2", -6, top + 10.6, zc - 6, 6, top + 12, zc + 6, THATCH_RIDGE)
	view:box("Roof3", -3.4, top + 12, zc - 3.4, 3.4, top + 13.4, zc + 3.4, h.roof)
	view:box("Finial", -0.8, top + 13.4, zc - 0.8, 0.8, top + 15, zc + 0.8, GOLD)
	Kit.bench(view.model, h.origin * CFrame.new(0, top, zb - 2), { length = 7, color = C.WoodLight, legs = C.WoodDark })
	return top
end

local function playgroundPlaza(model: any, at: any, paving: any, view: any, h: any): number
	local color = h.color
	-- a round plaza: a wood-chip play yard in a timber kerb on the left under the fort and the
	-- swings, a path in the second tone along the axis
	disc(paving, "Pad", 0, 0, 40, -0.6, FLOOR, PAVE)
	ringPaving(paving, 21.5, 26)
	paving:box("Axis", -5, -0.5, -38, 5, FLOOR + 0.12, 38, PAVE2, Kit.NOSHADOW)
	-- cross joints in the deep tone along the walk (flags, not a running track)
	for k, z in { -31, -15, 13, 29 } do
		paving:box(`AxisJoint{k}`, -4.9, -0.4, z - 0.8, 4.9, FLOOR + 0.16, z + 0.8, PAVE3, Kit.NOSHADOW)
	end
	medallion(paving, 0, -2, 4.8, FLOOR + 0.18, color)
	paving:box("PlayMat", -33.8, -0.5, -18, -8, FLOOR + 0.26, 23.8, CHIPS, Kit.NOSHADOW)
	paving:box("PlayMatRim", -35, -0.55, -19, -7, FLOOR + 0.4, 25, C.Wood, Kit.NOSHADOW)
	playFort(model, at(-19, 10), color, h.roof)
	swings(model, at(-21, -12, 0), color)
	sandpit(model, at(19, 10, -15), color)
	stall(model, at(27, 26, 45), "МОРОЖЕНОЕ", color, "icecream", h.roof)
	-- planters either side of the walk in from the arch, benches by them
	planter(model, at(9.5, -24, 0), C.Flowers[1], C.Flowers[2], 3)
	planter(model, at(-9.5, -24, 0), C.Flowers[7], C.Flowers[2], 5)
	Kit.bench(model, at(15.5, -27, 180), { length = 7, color = C.WoodLight, legs = C.WoodDark })
	Kit.bench(model, at(25, -6, 90), { length = 7, color = C.WoodLight, legs = C.WoodDark })
	-- a lookout deck on the hill and a long slide back down beside the stairs
	local z0 = h.deckZ0
	local top = plinth(view, h.world, h.origin, -8, z0, 15, z0 + 12, C.StoneLight)
	rails(view, -8, 15, z0, z0 + 12, top)
	Kit.prop("flagPole", view.model, h.origin * CFrame.new(-5.5, top, z0 + 9), { height = 14, color = color })
	local origin, world = h.origin, h.world
	local sx = 11
	local foot = (origin * CFrame.new(sx, 0.6, 46)).Position
	local baseY = origin.Position.Y
	local startY = baseY + top + 1.4 -- world y of the chute's top
	local sideV = (origin * CFrame.new(1, 0, 0)).Position - origin.Position
	-- lift the chute so it clears every terrace edge under it
	local p0 = (origin * CFrame.new(sx, 0, z0 + 1)).Position
	for k = 1, 40 do
		local t = k / 40
		local q = foot:Lerp(p0, t)
		for _, dx in { -2.4, 0, 2.4 } do
			local g = world:heightAt(q.X + sideV.X * dx, q.Z + sideV.Z * dx) + 0.6
			local yAt = foot.Y + (startY - foot.Y) * t
			if g > yAt then
				startY = max(startY, foot.Y + (g - foot.Y) / t)
			end
		end
	end
	local topPt = Vector3.new(p0.X, startY, p0.Z)
	Kit.ramp(view.model, topPt, foot, { width = 4.4, thick = 0.8, color = C.RoofTerracotta, name = "Slide" })
	for i, s in { -1, 1 } do
		local off = sideV * (s * 2.5) + Vector3.new(0, 1, 0)
		Kit.ramp(view.model, topPt + off, foot + off, {
			width = 0.6,
			thick = 1.8,
			color = C.WoodDark,
			name = `SlideWall{i}`,
			extra = Kit.NOSHADOW,
		})
	end
	-- (Nature keeps its flowers and trees out of the chute's corridor)
	for t = 0, 1, 0.2 do
		local q = foot:Lerp(topPt, t)
		Kit.claim(q.X, q.Z, 5)
	end
	-- the chute rests on a few timber posts where it runs high
	for i, t in { 0.3, 0.6, 0.85 } do
		local q = foot:Lerp(topPt, t)
		local g = world:heightAt(q.X, q.Z)
		if q.Y - 1 - g > 1.5 then
			U.part(
				view.model,
				`SlidePost{i}`,
				Vector3.new(1.2, q.Y - 1 - g + 1, 1.2),
				CFrame.new(q.X, (q.Y - 1 + g - 1) / 2, q.Z) * CFrame.Angles(0, rad(h.angle), 0),
				C.Wood
			)
		end
	end
	-- the top of the chute sits on the deck: a little start platform where it is higher
	if startY - baseY - top > 0.6 then
		view:box("SlideStart", sx - 2.4, top, z0, sx + 2.4, startY - baseY, z0 + 3, C.WoodLight)
	end
	return top
end

local function picnicPlaza(model: any, at: any, paving: any, view: any, h: any): number
	local color = h.color
	-- a meadow: a paved path along the axis and a round camp clearing off it (left), the picnic
	-- things on a plank patio by the path
	paving:box("Path", -6, -0.6, -35.8, 6, FLOOR, 38, PAVE, Kit.NOSHADOW)
	paving:box("PathEdge", -7, -0.65, -36.3, 7, FLOOR - 0.15, 38.3, KERB, Kit.NOSHADOW)
	-- cross joints in the deep tone every 12 studs (flags, not a running track)
	for k = 1, 5 do
		local z = -36 + k * 12
		paving:box(`Joint{k}`, -5.9, -0.4, z - 0.9, 5.9, FLOOR + 0.06, z + 0.9, PAVE3, Kit.NOSHADOW)
	end
	-- the camp: a big trodden clearing round the fire pit, two canvas tents facing the fire
	disc(paving, "Clearing", -17, 5, 22, -0.55, FLOOR + 0.12, EARTH)
	disc(paving, "Hearth", -15, 4, 9.3, -0.5, FLOOR + 0.24, PAVE2)
	-- a plank patio by the path (nothing stands on the bare grass): the souvenir stall, the canoe
	-- upturned on its trestle with crates, a picnic table, firewood, a lantern post
	paving:box("Patio", 12, -0.6, -31, 33, FLOOR, 9, C.Plank, Kit.NOSHADOW)
	firePit(model, at(-15, 4))
	tent(model, at(-31, 0, -90), color)
	boatYard(model, at(24, -11, -90), C.BoatPaint[2])
	Kit.prop("picnicTable", model, at(21, 3, 70), { cloth = C.Red })
	logPile(model, at(29.5, 4.5, 80))
	lantern(model, at(14.2, -15), color)
	stall(model, at(27, -24, 90), "СУВЕНИРЫ", color, "souvenirs", h.roof)
	-- picnic blankets out on the meadow
	blanket(model, at(21, 24, 15), C.Flowers[1])
	blanket(model, at(-24, -27, -12), C.Flowers[7])
	-- a picnic lookout on the hill (off the axis, where the zigzag path arrives): a striped pergola
	-- over a bench, a telescope, a flag
	local z0 = h.deckZ0
	local top = plinth(view, h.world, h.viewOrigin, -9, z0, 9, z0 + 14, C.StoneLight)
	rails(view, -9, 9, z0, z0 + 14, top)
	telescope(view, -6, top, z0 + 3)
	local zc = z0 + 8
	for i, p in { { -5, -4 }, { 5, -4 }, { 5, 4 }, { -5, 4 } } do
		view:box(`PergolaPost{i}`, p[1] - 0.6, top, zc + p[2] - 0.6, p[1] + 0.6, top + 8.5, zc + p[2] + 0.6, C.WoodDark)
	end
	for k = 0, 3 do
		local x0 = -6.6 + k * 3.3
		view:box(
			`Canopy{k + 1}`,
			x0,
			top + 8.5,
			zc - 5.6,
			x0 + 3.3,
			top + 9.5 + (k % 2) * 0.1,
			zc + 5.6,
			if k % 2 == 0 then color else C.Canvas
		)
	end
	Kit.prop("flagPole", view.model, h.viewOrigin * CFrame.new(6.5, top, z0 + 2.5), { height = 18, color = color })
	Kit.bench(view.model, h.viewOrigin * CFrame.new(0, top, zc + 2), { length = 7 })
	return top
end

local PLAZAS = {
	market = marketPlaza,
	garden = gardenPlaza,
	playground = playgroundPlaza,
	picnic = picnicPlaza,
}

--------------------------------------------------------------------------------------------

local function buildGateway(parent: any, cfg: any, world: any, gw: any)
	local angle = gw.angle % 360
	local theme = Promenade.Themes[angle] or Promenade.Themes[0]
	local details = THEMES[angle] or THEMES[0]
	local color = details.accent
	local G = cfg.GroundTop
	local model = U.model(parent, `Gateway_{gw.index}`)
	local origin = CFrame.new(gw.x, G, gw.z) * CFrame.Angles(0, rad(gw.angle), 0)
	-- local CFrame on the paving; yaw in degrees, or "centre" = front looks at the plaza centre
	local at = function(x: number, z: number, yaw: (number | string)?): any
		local y = if yaw == "centre" then math.atan2(x, z) else rad((yaw :: number?) or 0)
		return origin * CFrame.new(x, FLOOR, z) * CFrame.Angles(0, y, 0)
	end

	-- the brick entry road from the promenade (a clear step over its tiles) and the path stub
	-- towards the hill; the theme lays the rest of the paving
	local paving = Kit.builder(model, "Paving", origin)
	paving:box("Road", -9, -0.45, -42.6, 9, ROAD_TOP, -36.5, ROAD, Kit.NOSHADOW)
	paving:box("Back", -5.2, -0.45, 35.5, 5.2, FLOOR + 0.3, 43, ROAD, Kit.NOSHADOW)

	welcomeArch(model, at(0, -34), theme.gate, color, details.kind, details.roof)

	-- the hill behind: find the hilltop along the deck's line (the axis, or off it where the
	-- path zigzags), a solid plinth for the viewpoint there
	local district = DISTRICTS[details.kind]
	local deckX = district.deckX or 0
	local function groundAt(x: number, z: number): number
		local p = (origin * CFrame.new(x, 0, z)).Position
		return world:heightAt(p.X, p.Z)
	end
	local topZ, topH = 120, -math.huge
	for z = 60, 200, 4 do
		local h = groundAt(deckX, z)
		if h > topH then
			topZ, topH = z, h
		end
	end
	local deckZ0 = topZ - 2 -- the plinth's front edge
	local viewOrigin = origin * CFrame.new(deckX, 0, 0)
	local view = Kit.builder(model, "Viewpoint", viewOrigin)
	local viewTop = PLAZAS[details.kind](model, at, paving, view, {
		world = world,
		origin = origin,
		viewOrigin = viewOrigin,
		deckZ0 = deckZ0,
		color = color,
		roof = details.roof,
		angle = gw.angle,
	})
	paving:finish()
	view:finish()

	-- the climb from the back of the plaza up to the viewpoint, different on every hill
	local function P(x: number, z: number): any
		local p = (origin * CFrame.new(x, 0, z)).Position
		return Vector3.new(p.X, 0, p.Z)
	end
	local top = G + viewTop - 0.15 -- the last step hidden in the plinth, a 0.15 step onto it
	local z1 = deckZ0 + 1.5
	local route = { { 0, 40.5 }, { 0, z1 } } -- for the claims
	if district.climb == "ramps" then
		-- a paved path: runs on the terraces, wedge ramps up every riser (the farm's in stone)
		local stone = details.kind == "playground"
		Kit.rampPath(model, world, P(0, 40.5), P(0, z1), {
			width = 7,
			color = if stone then C.StoneLight else PAVE,
			color2 = if stone then C.Cobble else PAVE2,
			top = top,
			name = "HillPath",
		})
	elseif district.climb == "switchback" then
		-- plank stairs in three legs: up the valley, across onto the terrace, up to the deck
		local path = U.model(model, "HillPath")
		local tz = district.turnZ
		local opts = { width = 7, color = C.WoodLight, color2 = C.Plank, pave = true }
		opts.name = "Leg1"
		Kit.stairs(path, world, P(0, 40.5), P(0, tz + 3.5), opts)
		opts.name = "Leg2"
		Kit.stairs(path, world, P(-3.5, tz), P(deckX - 3.5, tz), opts)
		opts.name, opts.top = "Leg3", top
		Kit.stairs(path, world, P(deckX, tz + 3.5), P(deckX, z1), opts)
		route = { { 0, 40.5 }, { 0, tz }, { deckX, tz }, { deckX, z1 } }
	else
		local wood = district.climb == "wood"
		Kit.stairs(model, world, P(0, 40.5), P(0, z1), {
			width = 7,
			color = if wood then C.WoodLight else C.StoneLight,
			color2 = if wood then C.Plank else C.Cobble,
			pave = true,
			top = top,
			name = "HillPath",
		})
	end
	-- (the market's square paving reaches into the corners)
	Kit.claim(gw.x, gw.z, (gw.radius or 40) + (if details.kind == "market" then 15 else 4))
	for k = 1, #route - 1 do
		local a, b = route[k], route[k + 1]
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		for t = 0, len, 12 do
			local f = t / len
			local x, z = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
			local p = (origin * CFrame.new(x, 0, z)).Position
			Kit.claim(p.X, p.Z, 7)
		end
	end
	local deck = (viewOrigin * CFrame.new(0, 0, deckZ0 + 8)).Position
	Kit.claim(deck.X, deck.Z, 18)
	-- the district last: its trees keep off everything claimed above
	buildDistrict(model, world, origin, G, district, color, 7000 + gw.index * 31)
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
