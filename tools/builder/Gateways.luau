--[[
	Gateways — the 4 themed plazas behind the bridge landings (world.gateways, r ≈ 372,
	radius 40, flat GroundTop), each with a way up the hill behind it to a viewpoint, so the
	strongest sightline of the map (bridge → welcome arch → plaza) leads somewhere.
	Art direction v4 (DESIGN.md §1): natural materials (stone, timber, plaster, canvas) carry the
	look; each gateway's own colour (THEMES.accent, a calm roof tone in its bridge's hue) only on
	roofs, awnings, the name board and small trims. No figures.
	Each Map.Gateways.Gateway_N has:
	  • a roofed welcome arch over the brick entry road with a framed name board («СЕВЕРНЫЕ
	    ВОРОТА» …) in the gateway colour, each with its own silhouette (see ARCHES): a harbour gate
	    of timber masts with an anchor and a lifebuoy, a garden gate of clipped hedges under a
	    rose pergola, a toy-block gate with a spinning pinwheel, a log gate with hanging lanterns;
	  • stone-flag paving in its own footprint and its own layout — the axis from the arch to the
	    hill path stays open, the centrepiece stands off it; every stall and board faces the plaza.
	    The stalls are little timber pavilions (see stall): a plank floor on a stone kerb, posts
	    and tie beams, a pitched roof with a fascia, a sign board on the roof, a striped awning, a
	    counter with the goods, a back shelf, lanterns, crates.
	      north (180) fish market   a square market (checker flags): the fish and the tackle
	                                stall, a fountain with a bronze fish off the axis, a notice
	                                board, lamps, barrels; wooden steps up the fishermen's slope
	                                (drying racks, upturned and beached boats, fishers' cottages,
	                                a net rack, crates, palms) to a deck by the lighthouse
	      east  (90)  flower garden round plaza with hedge beds round a cross of paths, a wishing
	                                well among flowers off the axis, a rose pergola over the axis,
	                                a photo frame, the flower stall; a ramped garden path between
	                                tulip terraces, hedge mazes and topiaries to a gazebo
	      south (0)   playground    round plaza with a wood-chip play yard: a timber play fort
	                                with a slide off the axis, a sandpit, swings, the ice cream
	                                stall; a stone ramp path up a little farm (crop beds, a barn,
	                                haystacks, a pumpkin patch, an orchard) to a lookout deck with
	                                a long slide down
	      west  (270) picnic camp   a meadow with a paved path and a camp off the axis: a trodden
	                                clearing round a fire pit with a cooking tripod and log seats,
	                                two canvas tents; the souvenir stall, an upturned canoe, a
	                                picnic table, firewood and a lantern on a plank patio; plank
	                                stairs zigzag up past a camp to a lookout with a pergola
	  • the climb from the back of the plaza up the terraces to the viewpoint (Kit.stairs 1-stud
	    steps, or Kit.rampPath slabs and wedge ramps), a lantern post beside it; the viewpoint
	    stands on a solid plinth on the hilltop. District pieces stand only where the ground
	    under their whole footprint is flat (nudged up to 8 studs to find such a spot); the
	    theme's chunky trees (Kit.voxelTree) stand in groves on the terraces round them.

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

local rad, max, min = math.rad, math.max, math.min

local Gateways = {}

local FLOOR = 0.35 -- plaza paving top above GroundTop
local PAVE = mix(C.SandDark, C.Cobble, 0.35) -- warm stone flags ...
local PAVE2 = mix(C.Cobble, C.SandDark, 0.25) -- ... and their second tone (paths, checker)
local KERB = C.CobbleDark -- borders round the paving
local ROAD = mix(C.Brick, C.SandDark, 0.45) -- terracotta brick entry roads
local EARTH = mix(C.Dirt, C.SandDark, 0.6) -- trodden earth (the camp clearing)
local CHIPS = mix(C.WoodLight, C.Dirt, 0.35) -- wood chips under the play fort
local BRONZE = mix(C.Gold, C.WoodDark, 0.35) -- statues
local BRASS = mix(C.Gold, C.WoodDark, 0.3) -- telescopes
local INK = Kit.shade(C.WoodDark, 0.7) -- dark brown sign text on cream boards
local ROAD_TOP = 0.97 -- the entry road: a clear step (>= 0.15) over the promenade tiles

-- Per-gateway details (keyed by bridge angle): the layout and the gateway's own colour (a calm
-- roof tone in the hue of its bridge, Promenade.Themes).
local THEMES = {
	[180] = { kind = "market", accent = C.RoofBlue },
	[90] = { kind = "garden", accent = C.Blossom0 },
	[0] = { kind = "playground", accent = C.RoofTerracotta },
	[270] = { kind = "picnic", accent = C.RoofGreen },
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
	The welcome arches: every gateway has its own silhouette, all of stone, timber and its own
	roof colour (local frame of the arch: y = 0 on the paving, front = -Z towards the bridge, the
	road between x = ±9; the pillars stand at |x| 12..16). Each hangs a framed name board in the
	gateway colour under a roofed beam; 18-26 parts.
	  playground  a toy-block gate: pillars of three chunky stacked timber blocks on stone, a
	              tiled roof, a pinwheel on the ridge that spins (attribute Spin)
	  garden      a hedge gate: clipped hedge pillars in stone planters under a timber pergola
	              with climbing roses
	  market      a harbour gate: two timber masts on stone footings under a roofed beam, an
	              anchor on one mast, a lifebuoy on the other, a bronze fish vane on the ridge
	  picnic      a log gate: log posts on stones, a log lintel under a shingle roof, lanterns
	              hanging from the lintel
]]
local function pillarSpan(sx: number): (number, number, number)
	local x0, x1 = sx * 12, sx * 16
	return min(x0, x1), max(x0, x1), (x0 + x1) / 2
end

-- The name board (double-sided, white text with a dark outline) in a dark timber frame.
local function nameBoard(b: any, text: string, x: number, y0: number, y1: number, d: number, color: any)
	b:box("BoardFrame", -x - 0.5, y0 - 0.5, -d + 0.25, x + 0.5, y1 + 0.5, d - 0.25, C.WoodDark)
	local board = b:box("Board", -x, y0, -d, x, y1, d, color)
	Kit.sign(board, Enum.NormalId.Front, text, C.White, C.Navy, { pps = 24 })
	Kit.sign(board, Enum.NormalId.Back, text, C.White, C.Navy, { pps = 24 })
	return board
end

-- Two ropes from the beam (bottom at yBeam) down to the board's frame top (y).
local function ropes(b: any, x: number, y: number, yBeam: number)
	for i, sx in { -1, 1 } do
		b:box(`Rope{i}`, sx * x - 0.2, y, -0.2, sx * x + 0.2, yBeam + 0.2, 0.2, C.Rope, Kit.DECOR)
	end
end

local ARCHES = {}

ARCHES.playground = function(b: any, text: string, color: any)
	for i, sx in { -1, 1 } do
		local _, _, xm = pillarSpan(sx)
		b:box(`Plinth{i}`, xm - 3.2, -0.5, -3.2, xm + 3.2, 1.8, 3.2, C.StoneLight)
		-- three chunky 5.6-stud timber blocks, the middle one turned out a little (toy blocks)
		for k = 1, 3 do
			local o = if k == 2 then 0.35 else 0
			local c = if k == 2 then C.WoodLight else C.Wood
			local y0 = 1.8 + (k - 1) * 5.6
			b:box(`Block{i}_{k}`, xm - 2.4 - o, y0, -2.4 - o, xm + 2.4 + o, y0 + 5.6, 2.4 + o, c)
		end
	end
	b:box("Beam", -17.2, 18.6, -1.6, 17.2, 20.6, 1.6, C.WoodDark)
	gable(b, "Roof", -18.4, 18.4, -3.8, 3.8, 20.6, 4, color)
	b:box("Ridge", -18.7, 24.2, -0.7, 18.7, 25.2, 0.7, C.WoodDark)
	nameBoard(b, text, 11.5, 12, 17.4, 0.9, color)
	ropes(b, 8, 17.9, 18.6)
	-- the pinwheel on the ridge: four blades round a hub, each offset along its arm (the swirl);
	-- it spins about its hub (the pivot's LookVector points down the road), no collisions
	b:box("Stick", -0.3, 25.2, -0.3, 0.3, 30, 0.3, C.WoodDark, Kit.NOSHADOW)
	local hubCF = b.cf * CFrame.new(0, 30, -0.95)
	local pw = Kit.builder(b.model, "Pinwheel", hubCF)
	pw.model:SetAttribute("Spin", 80)
	local hub = pw:box("Hub", -0.8, -0.8, -0.65, 0.8, 0.8, 0.65, C.Cream, Kit.DECOR)
	for k, c in { C.Red, C.Yellow, C.Cream, C.Blue } do
		local lcf = CFrame.Angles(0, 0, rad(k * 90)) * CFrame.new(2.6, 1.05, -0.1)
		pw:block(`Blade{k}`, Vector3.new(4.4, 2.1, 0.4), lcf, c, Kit.DECOR)
	end
	pw.model.PrimaryPart = hub
	hub.PivotOffset = hub.CFrame:Inverse() * hubCF
end

ARCHES.garden = function(b: any, text: string, color: any)
	for i, sx in { -1, 1 } do
		local _, _, xm = pillarSpan(sx)
		b:box(`Planter{i}`, xm - 3.2, -0.5, -3.2, xm + 3.2, 2.6, 3.2, C.StoneLight)
		b:box(`Hedge{i}`, xm - 2.4, 2.6, -2.4, xm + 2.4, 17.4, 2.4, C.Leaf1)
		b:box(`HedgeTop{i}`, xm - 1.8, 17.4, -1.8, xm + 1.8, 19.6, 1.8, C.Leaf2, Kit.NOSHADOW)
	end
	-- the pergola: two beams along the road's width on the hedges, rafters across them
	for i, z in { -2.2, 2.2 } do
		b:box(`Beam{i}`, -18, 18.8, z - 0.6, 18, 20.2, z + 0.6, C.WoodLight)
	end
	for k, x in { -15.5, 0, 15.5 } do
		b:box(`Rafter{k}`, x - 0.5, 20.2, -4, x + 0.5, 21.1, 4, C.Wood, Kit.NOSHADOW)
	end
	-- climbing roses on the pergola and the hedges
	local roses = { C.Blossom1, color, C.Cream, C.Blossom2, color }
	for k, p in { { -12, 19.8 }, { -4, 20.6 }, { 4.5, 20 }, { 11.5, 20.6 } } do
		b:box(`Roses{k}`, p[1] - 1.6, p[2], -3.2, p[1] + 1.6, p[2] + 1.8, 3.2, roses[k], Kit.NOSHADOW)
	end
	for i, sx in { -1, 1 } do
		local _, _, xm = pillarSpan(sx)
		for k, q in { { -1.9, 8.6 + i * 1.5 }, { 0.3, 12.4 - i * 1.2 } } do
			local x = xm + sx * q[1]
			b:box(`Bloom{i}_{k}`, x - 1, q[2], -2.9, x + 1, q[2] + 1.6, -2, roses[(i + k) % 4 + 1], Kit.NOSHADOW)
		end
	end
	nameBoard(b, text, 11, 12.4, 17.6, 0.9, color)
	ropes(b, 7.5, 18.1, 18.8)
end

ARCHES.market = function(b: any, text: string, color: any)
	for i, sx in { -1, 1 } do
		local _, _, xm = pillarSpan(sx)
		b:box(`Footing{i}`, xm - 3, -0.5, -3, xm + 3, 2.4, 3, C.StoneLight)
		b:box(`Mast{i}`, xm - 1.5, 2.4, -1.5, xm + 1.5, 20.4, 1.5, C.Wood)
	end
	b:box("Beam", -18.4, 19.2, -1.5, 18.4, 21.4, 1.5, C.WoodDark)
	gable(b, "Roof", -19.6, 19.6, -3.8, 3.8, 21.4, 4.2, color)
	b:box("Ridge", -19.9, 25.2, -0.7, 19.9, 26.2, 0.7, C.WoodDark)
	nameBoard(b, text, 10.6, 12.6, 18.2, 0.9, color)
	ropes(b, 7, 18.7, 19.2)
	-- an iron anchor hanging on the left mast's front: shank, stock, crown with two flukes
	local _, _, lx = pillarSpan(-1)
	local z0, z1 = -2.3, -1.5
	b:box("Shank", lx - 0.4, 6.6, z0, lx + 0.4, 13.2, z1, C.Iron, Kit.NOSHADOW)
	b:box("Stock", lx - 1.9, 11.6, z0 - 0.05, lx + 1.9, 12.3, z1 - 0.05, C.Iron, Kit.NOSHADOW)
	b:box("Crown", lx - 2.6, 6.6, z0 + 0.05, lx + 2.6, 7.3, z1 + 0.05, C.Iron, Kit.NOSHADOW)
	b:box("FlukeL", lx - 2.6, 7.3, z0 + 0.05, lx - 1.9, 8.8, z1 + 0.05, C.Iron, Kit.NOSHADOW)
	b:box("FlukeR", lx + 1.9, 7.3, z0 + 0.05, lx + 2.6, 8.8, z1 + 0.05, C.Iron, Kit.NOSHADOW)
	-- a lifebuoy on the right mast's front (red and white quarters)
	local _, _, rx = pillarSpan(1)
	for k, q in
		{
			{ -1.9, 11.4, 1.9, 12.4, C.Red },
			{ -1.9, 7.6, 1.9, 8.6, C.Red },
			{ -1.9, 8.6, -0.9, 11.4, C.White },
			{ 0.9, 8.6, 1.9, 11.4, C.White },
		}
	do
		b:box(`Buoy{k}`, rx + q[1], q[2], -2.2, rx + q[3], q[4], -1.45, q[5], Kit.NOSHADOW)
	end
	-- a bronze fish weathervane on the ridge
	b:box("VaneRod", -0.25, 26.2, -0.25, 0.25, 28.6, 0.25, C.Iron, Kit.DECOR)
	b:box("VaneFish", -2.2, 28.4, -0.35, 1.4, 30.2, 0.35, BRONZE, Kit.DECOR)
	b:box("VaneTail", 1.3, 28, -0.3, 2.6, 30.6, 0.3, BRONZE, Kit.DECOR)
end

ARCHES.picnic = function(b: any, text: string, color: any)
	for i, sx in { -1, 1 } do
		local _, _, xm = pillarSpan(sx)
		b:box(`Stone{i}`, xm - 3, -0.5, -3, xm + 3, 1.8, 3, C.StoneLight)
		b:box(`Log{i}`, xm - 2, 1.8, -2, xm + 2, 18.8, 2, C.Bark)
		b:box(`Ring{i}`, xm - 2.25, 6, -2.25, xm + 2.25, 7, 2.25, C.BarkDark, Kit.NOSHADOW)
	end
	b:box("Lintel", -18.2, 17, -1.8, 18.2, 19.6, 1.8, C.Bark)
	gable(b, "Roof", -19.2, 19.2, -3.8, 3.8, 19.6, 4, color)
	b:box("Ridge", -19.5, 23.2, -0.7, 19.5, 24.2, 0.7, C.WoodDark)
	nameBoard(b, text, 10.6, 10.6, 15.8, 0.9, color)
	ropes(b, 7, 16.3, 17)
	-- two lanterns hanging from the lintel either side of the board
	for i, sx in { -1, 1 } do
		local x = sx * 13.6
		b:box(`LanternCap{i}`, x - 0.8, 15.4, -0.8, x + 0.8, 17, 0.8, C.WoodDark, Kit.NOSHADOW)
		b:box(`Lantern{i}`, x - 0.6, 13.8, -0.6, x + 0.6, 15.4, 0.6, C.Glow, Kit.NEON_DECOR)
	end
end

local function welcomeArch(parent: any, cf: any, text: string, color: any, kind: string)
	local b = Kit.builder(parent, "WelcomeArch", cf)
	ARCHES[kind](b, text, color)
	return b:finish()
end

--[[
	Market stall (front = -Z, the customers' side): a little timber pavilion, about 28-30 parts —
	a stone platform, four posts with tie beams, a pitched roof in the gateway colour with a cream
	fascia and a dark ridge, a framed sign board standing on the roof's front slope, a striped
	canvas awning with a valance over the counter, the counter (plank body, a dark plinth, a light
	top) with the goods on it, a back wall with a shelf, two lanterns hanging inside the front
	beam. goods: fish, tackle, flowers, icecream, souvenirs.
]]
local function stall(parent: any, cf: any, text: string, color: any, goods: string)
	local b = Kit.builder(parent, "Stall", cf)
	local kerb = b:box("Kerb", -6.4, -0.4, -4.4, 6.4, 0.85, 4.4, KERB)
	for i, p in { { -5.5, -3.4 }, { 5.5, -3.4 }, { 5.5, 3.4 }, { -5.5, 3.4 } } do
		b:box(`Post{i}`, p[1] - 0.5, 0.85, p[2] - 0.5, p[1] + 0.5, 8.4, p[2] + 0.5, C.WoodDark)
	end
	b:box("BeamF", -6.2, 8, -4, 6.2, 8.9, -2.9, C.Wood)
	b:box("BeamB", -6.2, 8, 2.9, 6.2, 8.9, 4, C.Wood)
	-- the roof: eaves at 8.9, ridge at 12.5
	gable(b, "Roof", -7.2, 7.2, -5.4, 5.4, 8.9, 3.6, color)
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
	b:box("Plinth", -5.1, 0.85, -3.65, 5.1, 1.35, -1.6, C.WoodDark, Kit.NOSHADOW)
	b:box("CounterTop", -5.4, 3.6, -3.9, 5.4, 4.1, -1.4, C.WoodLight)
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
		b:box("BigCone", -0.9, 12.9, -0.9, 0.9, 15.5, 0.9, C.Straw, Kit.NOSHADOW)
		b:box("BigScoop", -1.5, 15.5, -1.5, 1.5, 17.7, 1.5, C.Blossom1, Kit.NOSHADOW)
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
local function noticeBoard(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "NoticeBoard", cf)
	local post = b:box("PostL", -4.2, -0.5, -0.5, -3.2, 8.4, 0.5, C.WoodDark)
	b:box("PostR", 3.2, -0.5, -0.5, 4.2, 8.4, 0.5, C.WoodDark)
	b:box("Frame", -3.4, 2.2, -0.3, 3.4, 7.8, 0.3, C.WoodDark)
	b:box("Board", -3, 2.6, -0.45, 3, 6.4, 0.2, C.WoodLight)
	local header = b:box("Header", -3, 6.5, -0.5, 3, 7.6, 0.2, C.Cream)
	Kit.sign(header, Enum.NormalId.Front, "ОБЪЯВЛЕНИЯ", INK, nil, { pps = 40 })
	gable(b, "Roof", -5, 5, -1.6, 1.6, 8.4, 1.6, color)
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

-- Fountain: a stone basin (two crossed rims), water, four jets, a bronze fish on a pedestal.
local function fountain(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Fountain", cf)
	local water = { CanCollide = false, CastShadow = false } -- opaque: the two sheets cross
	local rim = b:box("Rim", -10.4, 0, -6.6, 10.4, 2.2, 6.6, C.StoneLight)
	b:box("RimB", -6.6, 0.02, -10.4, 6.6, 2.22, 10.4, C.StoneLight)
	b:box("Water", -9.2, 2.0, -5.4, 9.2, 2.5, 5.4, C.Water, water)
	b:box("WaterB", -5.4, 2.02, -9.2, 5.4, 2.52, 9.2, C.Water, water)
	for i, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local x, z = d[1] * 6.4, d[2] * 6.4
		b:box(`Jet{i}`, x - 0.35, 2.4, z - 0.35, x + 0.35, 4.8, z + 0.35, mix(C.WaterLight, C.Foam, 0.4), Kit.DECOR)
	end
	b:finish(rim)
	-- the bronze fish on its pedestal rising out of the water (about 22 studs to the tail)
	Kit.prop("fishStatue", b.model, cf * CFrame.new(0, 2, 0), {
		color = BRONZE,
		belly = mix(BRONZE, C.Cream, 0.4),
		pedestal = C.StoneLight,
		trim = color,
		scale = 1.5,
		name = "GoldenFish",
	})
end

--[[
	Wishing well among flowers (the garden's centrepiece): a stone well with a dark water top and
	a cap course, two timber posts with a crank beam, a little pitched roof in the gateway colour,
	a bucket on its rope, flower clumps round its foot. 16 parts.
]]
local function wishingWell(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "WishingWell", cf)
	local base = b:box("Well", -3.6, -0.3, -3.6, 3.6, 3.4, 3.6, C.StoneLight)
	b:box("WellCap", -4, 3.4, -4, 4, 4, 4, C.Stone)
	b:box("Water", -2.8, 3.2, -2.8, 2.8, 4.15, 2.8, mix(C.Water, C.Navy, 0.35), Kit.NOSHADOW)
	for i, sx in { -1, 1 } do
		b:box(`Post{i}`, sx * 3.4 - 0.5, 4, -0.5, sx * 3.4 + 0.5, 10.4, 0.5, C.WoodDark)
	end
	b:box("Crank", -4.4, 8.4, -0.35, 4.4, 9.1, 0.35, C.Wood, Kit.NOSHADOW)
	gable(b, "Roof", -5, 5, -3.4, 3.4, 10.4, 2.8, color)
	b:box("Ridge", -5.2, 12.9, -0.45, 5.2, 13.6, 0.45, C.WoodDark, Kit.NOSHADOW)
	b:box("Rope", -0.15, 6.4, -0.15, 0.15, 8.4, 0.15, C.Rope, Kit.DECOR)
	b:box("Bucket", -0.8, 5, -0.8, 0.8, 6.4, 0.8, C.Wood, Kit.DECOR)
	-- flower clumps round the foot: a leafy ring with blooms poking out
	for k, p in { { -4.6, -4.6 }, { 4.6, 4.6 } } do
		b:box(`Leaves{k}`, p[1] - 1.6, -0.3, p[2] - 1.6, p[1] + 1.6, 1.2, p[2] + 1.6, C.Leaf2, Kit.DECOR)
	end
	for k, p in { { -4.6, -4.6 }, { 4.6, 4.6 } } do
		b:box(`Blooms{k}`, p[1] - 1.1, 1, p[2] - 1.1, p[1] + 1.1, 2.4, p[2] + 1.1, C.Flowers[k * 2], Kit.DECOR)
	end
	return b:finish(base)
end

--[[
	Timber play fort: four posts, a plank deck with walls, a pitched roof in the gateway colour,
	a pennant, climbing blocks at the back and a slide down the front (about 22 studs tall).
]]
local function playFort(parent: any, cf: any, color: any)
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
	gable(b, "Roof", -7, 7, -7, 7, 15, 4, color)
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
	Garden bed w x d (front = -Z, 6 parts): a clipped hedge border round dark soil, a leafy mound
	on it, three clumps of blooms poking out of the mound (two colours by turns, staggered).
]]
local function gardenBed(parent: any, cf: any, w: number, d: number, c1: any, c2: any)
	local b = Kit.builder(parent, "HedgeBed", cf)
	local hedge = b:box("Hedge", -w / 2, -0.3, -d / 2, w / 2, 1.4, d / 2, C.Leaf1)
	b:box("Soil", -w / 2 + 0.8, 1.2, -d / 2 + 0.8, w / 2 - 0.8, 1.55, d / 2 - 0.8, C.DirtDark, Kit.NOSHADOW)
	b:box("Mound", -w / 2 + 1.6, 1.4, -d / 2 + 1.6, w / 2 - 1.6, 2.6, d / 2 - 1.6, C.Leaf2, Kit.DECOR)
	for k, x in { -w / 2 + 3.6, 0, w / 2 - 3.6 } do
		local z = if k == 2 then 0.7 else -0.6
		local top = 3.1 + (k % 2) * 0.5
		b:box(`Blooms{k}`, x - 1.8, 2.2, z - 1.4, x + 1.8, top, z + 1.4, if k % 2 == 1 then c1 else c2, Kit.DECOR)
	end
	return b:finish(hedge)
end

-- Rose pergola over the axis: two timber posts, a beam, rafters and climbing roses. 8 parts.
local function pergola(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "FlowerArch", cf)
	local post = b:box("PostL", -6.2, -0.3, -0.7, -4.8, 9.6, 0.7, C.WoodDark)
	b:box("PostR", 4.8, -0.3, -0.7, 6.2, 9.6, 0.7, C.WoodDark)
	b:box("Beam", -7.2, 9.6, -1.1, 7.2, 10.8, 1.1, C.WoodLight)
	for k, x in { -4.5, 0, 4.5 } do
		b:box(`Rafter{k}`, x - 0.4, 10.8, -2.4, x + 0.4, 11.5, 2.4, C.Wood, Kit.NOSHADOW)
	end
	b:box("Roses", -6, 10.4, -1.5, -2.6, 12.2, 1.5, C.Blossom1, Kit.NOSHADOW)
	b:box("Roses2", 1.4, 10.6, -1.4, 4.6, 12.4, 1.4, color, Kit.NOSHADOW)
	return b:finish(post)
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

-- Crop bed w x d (4 parts): a soil bed with three chunky rows of one crop along X (walk-through);
-- tall (rows `tall` high, default 1.3) reads as corn or wheat.
local function cropBed(parent: any, cf: any, w: number, d: number, crop: any, tall: number?)
	local b = Kit.builder(parent, "CropBed", cf)
	local soil = b:box("Soil", -w / 2, -0.6, -d / 2, w / 2, 0.6, d / 2, C.Dirt)
	for i = 1, 3 do
		local z = -d / 2 + (i - 0.5) * d / 3
		local top = 0.6 + (tall or 1.3) + (if tall then (i % 2) * 0.5 else 0)
		b:box(`Row{i}`, -w / 2 + 1, 0.6, z - 1.1, w / 2 - 1, top, z + 1.1, crop, Kit.DECOR)
	end
	return b:finish(soil)
end

--[[
	Barn (front = -Z, 11 parts): a stone base course, barn-red plank walls, a slate roof with the
	gable to the front, a cream-framed double door with a cross brace, a hayloft hatch.
]]
local function barn(parent: any, cf: any)
	local b = Kit.builder(parent, "Barn", cf)
	local base = b:box("Base", -6.4, -0.6, -5.4, 6.4, 0.8, 5.4, C.StoneLight)
	b:box("Body", -6, 0.8, -5, 6, 8, 5, C.RoofRed)
	gable(b, "Roof", -7, 7, -5.8, 5.8, 8, 5.4, C.RoofSlate, true)
	b:box("Eaves", -6.2, 7.6, -5.2, 6.2, 8.2, 5.2, C.Cream, Kit.NOSHADOW)
	b:box("DoorFrame", -3.2, 0.8, -5.3, 3.2, 6.6, -4.9, C.Cream, Kit.NOSHADOW)
	b:box("Door", -2.6, 0.8, -5.45, 2.6, 6, -5.2, C.WoodDark, Kit.NOSHADOW)
	for i, a in { 45, -45 } do
		b:block(
			`Brace{i}`,
			Vector3.new(0.5, 6.6, 0.2),
			CFrame.new(0, 3.4, -5.55) * CFrame.Angles(0, 0, rad(a * 0.82)),
			C.Cream,
			Kit.DECOR
		)
	end
	b:box("Hayloft", -1.6, 9, -5.95, 1.6, 11.4, -5.6, C.WoodDark, Kit.NOSHADOW)
	return b:finish(base)
end

-- Flower bed w x d (2 + about w / 5 parts): two rows of tulips along X, each a green stem strip
-- with the blooms on it in separate clumps (two tints, two heights by turns), not a plank.
local function tulipBed(parent: any, cf: any, w: number, d: number, c1: any, c2: any)
	local b = Kit.builder(parent, "TulipBed", cf)
	local first = nil
	for i, z in { -d / 4, d / 4 } do
		local stems = b:box(`Stems{i}`, -w / 2 + 0.4, -0.3, z - 1.6, w / 2 - 0.4, 1.2, z + 1.6, C.Leaf1, Kit.DECOR)
		first = first or stems
		local c = if i == 1 then c1 else c2
		for k, q in Kit.clumps(-w / 2 + 0.8, w / 2 - 0.8, 6.5, 1.8) do
			local top = 2.3 + ((k + i) % 2) * 0.5
			local tint = if k % 2 == 0 then mix(c, C.White, 0.2) else c
			b:box(`Blooms{i}_{k}`, q[1], 1.1, z - 1.1, q[2], top, z + 1.1, tint, Kit.DECOR)
		end
	end
	return b:finish(first)
end

-- Fish-drying rack (6 parts): two posts, a bar, three silver fish hanging from it.
local function dryingRack(parent: any, cf: any)
	local b = Kit.builder(parent, "DryingRack", cf)
	local post = b:box("PostL", -5, -0.5, -0.4, -4.2, 6.6, 0.4, C.WoodDark)
	b:box("PostR", 4.2, -0.5, -0.4, 5, 6.6, 0.4, C.WoodDark)
	b:box("Bar", -5.4, 6.6, -0.5, 5.4, 7.3, 0.5, C.Wood)
	for i, c in { C.StoneLight, mix(C.Gold, C.StoneLight, 0.5), C.Stone } do
		local x = -2.6 + (i - 1) * 2.6
		b:box(`Fish{i}`, x - 0.6, 3.6 + (i % 2) * 0.5, -0.3, x + 0.6, 6.6, 0.3, c, Kit.DECOR)
	end
	return b:finish(post)
end

--[[
	Fisher's cottage (front = -Z, 9 parts): a stone base course, plaster walls, a roof in the
	gateway colour with the gable to the front, a plank door, a framed window, a brick chimney.
]]
local function hut(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Hut", cf)
	local base = b:box("Base", -6.2, -0.6, -4.9, 6.2, 1, 4.9, C.StoneLight)
	b:box("Body", -5.8, 1, -4.5, 5.8, 7.4, 4.5, C.Plaster)
	gable(b, "Roof", -6.8, 6.8, -5.4, 5.4, 7.4, 4.4, color, true)
	b:box("Door", -3.6, 1, -4.75, -1.2, 5.8, -4.45, C.WoodDark, Kit.NOSHADOW)
	b:box("WindowFrame", 0.8, 2.8, -4.7, 4.4, 6, -4.45, C.WoodLight, Kit.NOSHADOW)
	b:box("Window", 1.3, 3.3, -4.85, 3.9, 5.5, -4.6, C.WindowBlue, Kit.NOSHADOW)
	b:box("Chimney", 2.6, 8, 1.4, 4.4, 12.6, 3.2, C.Brick)
	return b:finish(base)
end

-- Picnic blanket (2 parts) with a cream stripe.
local function blanket(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Blanket", cf)
	local cloth = b:box("Cloth", -3.5, -0.2, -3, 3.5, 0.25, 3, color, Kit.NOSHADOW)
	b:box("Stripe", -3.6, -0.18, -0.7, 3.6, 0.4, 0.7, C.Cream, Kit.DECOR) -- 0.1 past the cloth's ends
	return b:finish(cloth)
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

-- Haystack (2 parts): a big straw block with a smaller lighter one on top.
local function hayStack(parent: any, cf: any)
	local b = Kit.builder(parent, "HayStack", cf)
	local bale = b:box("Bale", -3.2, -0.5, -2.2, 3.2, 3.2, 2.2, C.Straw)
	b:box("Top", -2.2, 3.2, -1.5, 2, 5.4, 1.7, C.StrawLight, Kit.NOSHADOW)
	return b:finish(bale)
end

-- Pumpkin patch w x d (1 + 4 parts): a leafy vine bed with four chunky pumpkins of three sizes.
local function pumpkinPatch(parent: any, cf: any, w: number, d: number)
	local b = Kit.builder(parent, "PumpkinPatch", cf)
	local bed = b:box("Vines", -w / 2, -0.4, -d / 2, w / 2, 0.7, d / 2, C.Leaf2, Kit.NOSHADOW)
	for i, p in { { -0.32, -0.2, 3 }, { -0.05, 0.22, 2.4 }, { 0.2, -0.18, 3.4 }, { 0.38, 0.24, 2.2 } } do
		local x, z, s = p[1] * w, p[2] * d, p[3]
		b:box(
			`Pumpkin{i}`,
			x - s / 2,
			0.2,
			z - s / 2,
			x + s / 2,
			0.2 + s * 0.8,
			z + s / 2,
			if i % 2 == 0 then C.Autumn1 else C.Orange
		)
	end
	return b:finish(bed)
end

-- Hedge maze 14 x 14 (7 parts, fits on one terrace): clipped walls in two greens (the lighter a
-- little lower), a way in at the front, a baffle inside, a stone urn in the middle.
local function hedgeMaze(parent: any, cf: any)
	local b = Kit.builder(parent, "HedgeMaze", cf)
	local dark, mid = C.Leaf1, C.Leaf2
	local first = b:box("WallW", -7, -0.4, -7, -5.5, 3.6, 7, dark)
	b:box("WallE", 5.5, -0.4, -7, 7, 3.6, 7, dark)
	b:box("WallN", -5.5, -0.4, 5.5, 5.5, 3.2, 7, mid)
	b:box("WallS1", -5.5, -0.4, -7, -1.8, 3.2, -5.5, mid)
	b:box("WallS2", 1.8, -0.4, -7, 5.5, 3.2, -5.5, mid)
	b:box("Baffle", -3.2, -0.4, -2.6, 5.5, 3.4, -1.2, dark)
	b:box("Urn", -1.3, -0.4, 1.4, 1.3, 2.4, 4, C.StoneLight)
	return b:finish(first)
end

-- Fishing-net rack (3 parts): two posts and a teal net hung between them.
local function netRack(parent: any, cf: any)
	local b = Kit.builder(parent, "NetRack", cf)
	local post = b:box("PostL", -5.4, -0.5, -0.45, -4.5, 6.2, 0.45, C.WoodDark)
	b:box("PostR", 4.5, -0.5, -0.45, 5.4, 6.2, 0.45, C.WoodDark)
	b:box("Net", -4.6, 1.6, -0.2, 4.6, 5.8, 0.2, mix(C.Cyan, C.Navy, 0.25), Kit.DECOR)
	return b:finish(post)
end

-- Two stacked crates (2 parts), the top one turned and smaller.
local function crates(parent: any, cf: any, color: any)
	local b = Kit.builder(parent, "Crates", cf)
	local base = b:box("Crate", -1.8, -0.5, -1.8, 1.8, 3.1, 1.8, C.WoodLight)
	b:block("Crate2", Vector3.new(2.6, 2.6, 2.6), CFrame.new(0.2, 4.4, -0.1) * CFrame.Angles(0, rad(20), 0), color)
	return b:finish(base)
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

-- Fire ring (4 parts): a stone ring, two crossed logs, a Neon flame.
local function fireRing(parent: any, cf: any)
	local b = Kit.builder(parent, "FireRing", cf)
	local ring = b:box("Stones", -2.4, -0.4, -2.4, 2.4, 0.7, 2.4, C.StoneLight)
	b:box("LogA", -1.9, 0.7, -0.45, 1.9, 1.5, 0.45, C.Bark)
	b:box("LogB", -0.45, 1.5, -1.9, 0.45, 2.2, 1.9, C.Bark)
	local flame = b:box("Flame", -0.8, 1.4, -0.8, 0.8, 3.4, 0.8, C.Flame, Kit.NEON_DECOR)
	Kit.smoke(flame, { rate = 2 })
	return b:finish(ring)
end

--[[
	Per theme: the climb ("steps" stone stairs, "wood" plank stairs, "ramps" a paved path with
	wedge ramps, "switchback" plank stairs in three legs to a deck off the axis), the lantern
	spots beside it, the district pieces { kind, x, z, w, d, yaw, ... } on the terraces either
	side (nudged to a flat spot nearby, dropped where there is none) and the trees { kind,
	scale, seed, groves = { { x, z, count }, ... } } (see buildDistrict).
]]
local DISTRICTS = {
	-- south: a little farm — crop beds on the terraces (tall wheat and corn among them), a barn,
	-- haystacks, a pumpkin patch, an orchard of fruit trees either side
	playground = {
		climb = "ramps",
		lanterns = { { 5.6, 66 } },
		pieces = {
			{ "crop", -32, 52, 28, 12, 0, C.Straw, 3.2 },
			{ "crop", 32, 52, 28, 12, 0, C.Leaf3 },
			{ "crop", 40, 68, 40, 12, 0, mix(C.Straw, C.Leaf3, 0.45), 3.4 },
			{ "barn", -40, 100, 14, 12, -90 },
			{ "hay", -58, 100, 7, 5, 20 },
			{ "pumpkins", 52, 100, 14, 8, 0 },
		},
		trees = { kind = "fruit", scale = 1.6, seed = 11, groves = { { -72, 64, 1 }, { 74, 72, 1 } } },
	},
	-- east: a flower garden — tulip terraces either side of a ramped garden path, hedge mazes,
	-- clipped topiary trees
	garden = {
		climb = "ramps",
		lanterns = { { 5.6, 58 } },
		pieces = {
			{ "tulips", -32, 52, 28, 12, 0, C.Flowers[1], C.Flowers[2] },
			{ "tulips", 32, 52, 28, 12, 0, C.Flowers[4], C.Flowers[3] },
			{ "tulips", -40, 68, 40, 12, 0, C.Flowers[3], C.Flowers[7] },
			{ "maze", 40, 68, 14, 14, 0 },
			{ "maze", -40, 100, 14, 14, 90 },
		},
		trees = { kind = "topiary", scale = 1.5, seed = 23, groves = { { -70, 70, 1 }, { 70, 96, 1 } } },
	},
	-- north: the fishermen's slope — fish-drying racks, upturned and beached boats, fishers'
	-- cottages, a net rack, crates, palms
	market = {
		climb = "wood",
		lanterns = { { 5.6, 58 } },
		pieces = {
			{ "rack", -30, 52, 12, 3, 0 },
			{ "boat", 32, 52, 15, 12, 90 },
			{ "boat", -36, 68, 15, 12, -70 },
			{ "hut", -40, 84, 14, 11, -90 },
			{ "hut", 40, 84, 14, 11, 90 },
			{ "net", -56, 60, 12, 3, 20 },
			{ "crates", 22, 84, 5, 5, 0, C.Wood },
			{ "rowboat", 60, 72, 6, 11, -30, C.BoatPaint[1] },
		},
		trees = { kind = "palm", scale = 1.5, seed = 31, groves = { { -70, 78, 1 }, { 68, 98, 1 } } },
	},
	-- west: a camp — tents round a fire ring, a blanket, firewood, pines; the path zigzags up to a
	-- lookout off the axis
	picnic = {
		climb = "switchback",
		deckX = -24,
		turnZ = 80,
		lanterns = { { 5.6, 62 } },
		pieces = {
			{ "clearing", 32, 52, 30, 13, 0, EARTH },
			{ "tent", 23, 52, 10, 10, -60, C.RoofTerracotta },
			{ "tent", 42, 52, 10, 10, -110, C.RoofGreen },
			{ "fire", 32.5, 52, 6, 6, 0 },
			{ "blanket", 44, 70, 8, 8, 20, C.Red },
			{ "logs", 22, 66, 6, 4, 10 },
		},
		trees = { kind = "pine", scale = 1.6, seed = 47, groves = { { 66, 70, 1 }, { -66, 96, 1 } } },
	},
}

local PIECES = {
	crop = function(parent: any, cf: any, q: any)
		cropBed(parent, cf, q[4], q[5], q[7], q[8])
	end,
	hay = function(parent: any, cf: any)
		hayStack(parent, cf)
	end,
	pumpkins = function(parent: any, cf: any, q: any)
		pumpkinPatch(parent, cf, q[4], q[5])
	end,
	maze = function(parent: any, cf: any)
		hedgeMaze(parent, cf)
	end,
	net = function(parent: any, cf: any)
		netRack(parent, cf)
	end,
	crates = function(parent: any, cf: any, q: any)
		crates(parent, cf, q[7])
	end,
	rowboat = function(parent: any, cf: any, q: any)
		beachedBoat(parent, cf, q[7])
	end,
	logs = function(parent: any, cf: any)
		logPile(parent, cf)
	end,
	barn = function(parent: any, cf: any)
		barn(parent, cf)
	end,
	tulips = function(parent: any, cf: any, q: any)
		tulipBed(parent, cf, q[4], q[5], q[7], q[8])
	end,
	rack = function(parent: any, cf: any)
		dryingRack(parent, cf)
	end,
	boat = function(parent: any, cf: any, _q: any, color: any)
		boatYard(parent, cf, color)
	end,
	hut = function(parent: any, cf: any, _q: any, color: any)
		hut(parent, cf, color)
	end,
	tent = function(parent: any, cf: any, q: any)
		tent(parent, cf, q[7])
	end,
	fire = function(parent: any, cf: any)
		fireRing(parent, cf)
	end,
	blanket = function(parent: any, cf: any, q: any)
		blanket(parent, cf, q[7])
	end,
	-- a trodden earth clearing under a group of pieces (1 part)
	clearing = function(parent: any, cf: any, q: any)
		U.part(
			parent,
			"Clearing",
			Vector3.new(q[4], 0.75, q[5]),
			cf * CFrame.new(0, -0.225, 0),
			q[7],
			nil,
			Kit.NOSHADOW
		)
	end,
}

-- Builds the district of a theme on the hill behind its plaza (origin: the plaza frame on the
-- ground at GroundTop G). Each piece stands where the ground under its whole footprint is flat:
-- at its spot, or the nearest spot up to 8 studs off it that is flat, clear of the climb (open,
-- |x| > 9) and of the pieces placed before it. Then the theme's trees (Kit.voxelTree, an orchard,
-- topiaries, palms or pines) in groves round their centres { x, z, count }: each tree on the
-- free spot nearest its grove's centre whose ground under the trunk is flat and not claimed
-- (the plaza, the climb, the viewpoint, the pieces), at least 14 studs from the other trees.
local function buildDistrict(parent: any, world: any, origin: any, G: number, d: any, color: any)
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
			-- claims along the long side (Nature keeps its trees off the beds)
			local long, short = max(w, dd), min(w, dd)
			for t = -long / 2 + short / 2, long / 2 - short / 2 + 0.01, short do
				local lx, lz = if w >= dd then x + t else x, if w >= dd then z else z + t
				local p = (origin * CFrame.new(lx, 0, lz)).Position
				Kit.claim(p.X, p.Z, short * 0.72 + 2)
			end
		end
	end
	-- the groves
	local t = d.trees
	if t then
		local r = Kit.rng(t.seed)
		local spots = {}
		for gz = 42, 140, 6 do
			for gx = -104, 104, 6 do
				local x, z = gx + r(-2, 2), gz + r(-2, 2)
				local p = (origin * CFrame.new(x, 0, z)).Position
				local h = ground(x, z)
				local ok = math.abs(x) > 14
					and h > G
					and world:kindAt(p.X, p.Z) ~= "sand"
					and not world:isReserved(p.X, p.Z, 4)
					and not Kit.isClaimed(p.X, p.Z, 6)
					and flat(x, z, 3, 3) == h
				if ok then
					table.insert(spots, { x = x, z = z, h = h })
				end
			end
		end
		local trees: { { number } } = {}
		local left = {}
		for gi, g in t.groves do
			left[gi] = g[3]
		end
		-- round robin over the groves, each taking its nearest free spot
		local more = true
		while more do
			more = false
			for gi, g in t.groves do
				if left[gi] > 0 then
					local best, bd = nil, math.huge
					for _, s in spots do
						local dist = (s.x - g[1]) ^ 2 + (s.z - g[2]) ^ 2
						if dist < bd then
							local clear = true
							for _, o in trees do
								if (s.x - o[1]) ^ 2 + (s.z - o[2]) ^ 2 < 14 * 14 then
									clear = false
									break
								end
							end
							if clear then
								best, bd = s, dist
							end
						end
					end
					if best then
						table.insert(trees, { best.x, best.z })
						left[gi] -= 1
						more = more or left[gi] > 0
						local yaw = math.floor(r(0, 3.99)) * 90 + r(-15, 15)
						local cf = origin * CFrame.new(best.x, best.h - G, best.z) * CFrame.Angles(0, rad(yaw), 0)
						Kit.voxelTree(model, cf, t.kind, { scale = t.scale * r(0.9, 1.1) })
						local p = cf.Position
						Kit.claim(p.X, p.Z, 6)
					end
				end
			end
		end
	end
	for _, l in d.lanterns do
		local h = flat(l[1], l[2], 2.6, 2.6)
		if h then
			lantern(model, origin * CFrame.new(l[1], h - G, l[2]), color)
		end
	end
	return model
end

--------------------------------------------------------------------------------------------
-- The plazas
--------------------------------------------------------------------------------------------

-- Each theme gets the plaza model, `at(x, z, yaw)` (local CFrame on the paving; yaw in degrees
-- or "centre"), the paving builder, the viewpoint builder and its hill info { world, origin,
-- deckZ0, color }; returns the viewpoint's plinth top (local y).

local function marketPlaza(model: any, at: any, paving: any, view: any, h: any): number
	local color = h.color
	-- a square market of stone flags with a checker of darker flags, a kerb all round
	paving:box("Square", -36, -0.6, -36, 36, FLOOR, 36, PAVE, Kit.NOSHADOW)
	paving:box("Border", -38, -0.7, -38, 38, FLOOR - 0.15, 38, KERB, Kit.NOSHADOW)
	for i = 0, 3 do
		for j = 0, 3 do
			if (i + j) % 2 == 0 then
				local x0, z0 = -36 + i * 18, -36 + j * 18
				-- (the tiles on the square's rim stop 0.1 short of its sides)
				local ax, az = max(x0, -35.9), max(z0, -35.9)
				local bx, bz = min(x0 + 18, 35.9), min(z0 + 18, 35.9)
				paving:box(`Tile{i}_{j}`, ax, -0.5, az, bx, FLOOR + 0.12, bz, PAVE2, Kit.NOSHADOW)
			end
		end
	end
	-- the fountain off the axis (front right), two stalls facing the square
	fountain(model, at(13, -8), color)
	-- (every stall and board faces the square: front = -Z turned towards the centre)
	stall(model, at(-24, -10, -90), "РЫБА", color, "fish")
	stall(model, at(26, 18, 60), "СНАСТИ", color, "tackle")
	noticeBoard(model, at(-28, 10, -90), color)
	Kit.prop("barrel", model, at(-19.6, 25), { color = C.Wood })
	-- fish crates stacked by the fish stall, lamps in the square's back corners
	local cr = Kit.builder(model, "FishCrates", at(-17.5, -19, 10))
	cr:box("Crate", -1.6, -0.3, -1.4, 1.6, 2.2, 1.4, C.WoodLight)
	cr:box("Crate2", -1.3, 2.2, -1.1, 1.5, 4, 1.2, C.Wood, Kit.NOSHADOW)
	cr:finish()
	for i, p in { { -31, 31 }, { 31, 31 } } do
		Kit.lamp(model, at(p[1], p[2]), { trim = C.Iron, post = C.WoodDark, name = `Lamp{i}` })
	end
	Kit.bench(model, at(14, 28, 180), { length = 7, color = C.WoodLight, legs = C.WoodDark })
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
	-- a round plaza with four hedge beds round a cross of paths (the paths in the second tone)
	disc(paving, "Pad", 0, 0, 40, -0.6, FLOOR, PAVE)
	paving:box("PathX", -38, -0.5, -4.5, 38, FLOOR + 0.12, 4.5, PAVE2, Kit.NOSHADOW)
	paving:box("PathZ", -4.5, -0.5, -38, 4.5, FLOOR + 0.12, 38, PAVE2, Kit.NOSHADOW)
	local beds = { { C.Flowers[1], C.Flowers[3] }, { C.Flowers[4], C.Flowers[7] }, { C.Flowers[2], C.Flowers[6] } }
	for i, p in { { -17, -17 }, { 17, -17 }, { -17, 17 } } do
		gardenBed(model, at(p[1], p[2], if p[1] < 0 then 90 else -90), 16, 9, beds[i][1], beds[i][2])
	end
	-- the wishing well stands in the fourth bed (back right, off the axis); a rose pergola spans
	-- the axis, the stall and the photo frame on the cross paths
	wishingWell(model, at(17, 17, -45), color)
	pergola(model, at(0, 30), color)
	stall(model, at(-27, 1, -90), "ЦВЕТЫ", color, "flowers")
	photoFrame(model, at(27, 1, 90), color)
	Kit.bench(model, at(-9, -26, 0), { length = 7, color = C.WoodLight, legs = C.WoodDark })
	-- a gazebo on the hill: cream posts, a stepped roof in the gateway colour
	local z0 = h.deckZ0
	local top = plinth(view, h.world, h.origin, -8, z0, 8, z0 + 16, C.StoneLight)
	local za, zb = z0 + 1.5, z0 + 14.5
	for i, p in { { -6, za }, { 6, za }, { 6, zb }, { -6, zb } } do
		view:box(`Post{i}`, p[1] - 0.7, top, p[2] - 0.7, p[1] + 0.7, top + 9, p[2] + 0.7, C.Cream)
	end
	local zc = (za + zb) / 2
	view:box("Eaves", -8.9, top + 8.6, zc - 8.9, 8.9, top + 9.2, zc + 8.9, C.Cream, Kit.NOSHADOW)
	view:box("Roof1", -8.6, top + 9.2, zc - 8.6, 8.6, top + 10.6, zc + 8.6, color)
	view:box("Roof2", -6, top + 10.6, zc - 6, 6, top + 12, zc + 6, Kit.shade(color, 0.9))
	view:box("Roof3", -3.4, top + 12, zc - 3.4, 3.4, top + 13.4, zc + 3.4, color)
	view:box("Finial", -0.8, top + 13.4, zc - 0.8, 0.8, top + 15, zc + 0.8, BRONZE)
	Kit.bench(view.model, h.origin * CFrame.new(0, top, zb - 2), { length = 7, color = C.WoodLight, legs = C.WoodDark })
	return top
end

local function playgroundPlaza(model: any, at: any, paving: any, view: any, h: any): number
	local color = h.color
	-- a round plaza: a wood-chip play yard in a timber kerb on the left under the fort and the
	-- swings, a path in the second tone along the axis
	disc(paving, "Pad", 0, 0, 40, -0.6, FLOOR, PAVE)
	paving:box("Axis", -5, -0.5, -38, 5, FLOOR + 0.12, 38, PAVE2, Kit.NOSHADOW)
	paving:box("PlayMat", -33.8, -0.5, -18, -8, FLOOR + 0.26, 23.8, CHIPS, Kit.NOSHADOW)
	paving:box("PlayMatRim", -35, -0.55, -19, -7, FLOOR + 0.4, 25, C.Wood, Kit.NOSHADOW)
	playFort(model, at(-19, 10), color)
	swings(model, at(-21, -12, 0), color)
	sandpit(model, at(19, 10, -15), color)
	stall(model, at(27, 26, 45), "МОРОЖЕНОЕ", color, "icecream")
	Kit.bench(model, at(14, -27, 180), { length = 7, color = C.WoodLight, legs = C.WoodDark })
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
	Kit.ramp(view.model, topPt, foot, { width = 4.4, thick = 0.8, color = color, name = "Slide" })
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
	-- the camp: a big trodden clearing round the fire pit, two canvas tents facing the fire
	disc(paving, "Clearing", -17, 5, 22, -0.55, FLOOR + 0.12, EARTH)
	disc(paving, "Hearth", -15, 4, 9.3, -0.5, FLOOR + 0.24, PAVE2)
	-- a plank patio by the path (nothing stands on the bare grass): the souvenir stall, the canoe
	-- upturned on its trestle with crates, a picnic table, firewood, a lantern post
	paving:box("Patio", 12, -0.6, -31, 33, FLOOR, 9, C.Plank, Kit.NOSHADOW)
	firePit(model, at(-15, 4))
	tent(model, at(-31, 0, -90), color)
	tent(model, at(-24, 21, -30), C.RoofTerracotta)
	boatYard(model, at(24, -11, -90), C.BoatPaint[2])
	Kit.prop("picnicTable", model, at(21, 3, 70), { cloth = C.Red })
	logPile(model, at(29.5, 4.5, 80))
	lantern(model, at(14.2, -15), color)
	stall(model, at(27, -24, 90), "СУВЕНИРЫ", color, "souvenirs")
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

	welcomeArch(model, at(0, -34), theme.gate, color, details.kind)
	-- a lantern either side of the walk just inside the arch
	for _, sx in { -1, 1 } do
		lantern(model, at(sx * 8.5, -29), color)
	end

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
	buildDistrict(model, world, origin, G, district, color)
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
