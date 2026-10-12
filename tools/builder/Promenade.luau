--[[
	Promenade — the 4 bridges (hub plaza ↔ promenade) and the promenade ring along the lagoon
	(World v3, tools/builder/DESIGN.md §2/§6).

	  Map.Bridges     Bridge_1..4 at θ = BridgeAngles: chunky Props.bridge from the hub plaza
	                  (r ≈ 118) to the promenade (r ≈ 312), deck top GroundTop + 0.6, no end
	                  arches (the hub's avenue gates and the gateway arches frame the crossing);
	                  planks in two woods with every fourth one in the gateway's pastel, a chunky
	                  top rail, lanterns in the gateway's colour and a mid-span lookout: bump-outs
	                  on both sides with benches facing the water, a lamp and a flag each, a
	                  telescope
	  Map.Promenade   the ring walk r 312..330 on flat GroundTop: paving tiles in two warm
	                  shades with a coral middle band and white kerbs; a sea wall on the lagoon
	                  side (light stone face from the beach up, white coping) with a low white
	                  railing and a blue rail on it, open at the 8 pier entrances (base ± 6°), the
	                  4 bridge landings and 4 sand steps down to the beach (between two plots);
	                  chunky lamps (caps in the colour of the nearest gateway: each quarter of
	                  the ring has its own), bunting, benches and flower boxes in front of the
	                  plots, big billboards at the landmark paths.

	Nothing is placed on the walking surface except along its two edges, so players can run
	all the way round. Returns { lamps = number }.
]]

local U = require("./Util")
local Kit = require("./MapKit")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local rgb = U.rgb
local C = Kit.C

local rad, cos, tan, floor = math.rad, math.cos, math.tan, math.floor

local Promenade = {}

-- Gateway themes by bridge angle (shared with Gateways.luau): name, colour.
Promenade.Themes = {
	[0] = { gate = "ЮЖНЫЕ ВОРОТА", bridge = "ЮЖНЫЙ МОСТ", color = C.Orange },
	[90] = { gate = "ВОСТОЧНЫЕ ВОРОТА", bridge = "ВОСТОЧНЫЙ МОСТ", color = C.Pink },
	[180] = { gate = "СЕВЕРНЫЕ ВОРОТА", bridge = "СЕВЕРНЫЙ МОСТ", color = C.Blue },
	[270] = { gate = "ЗАПАДНЫЕ ВОРОТА", bridge = "ЗАПАДНЫЙ МОСТ", color = rgb(64, 196, 92) },
}

-- Landmark path mouths on the promenade's land side: a big billboard beside each path.
local PATH_SIGNS = {
	{ angle = 45, text = "ВОДОПАД →", color = rgb(40, 170, 230) },
	{ angle = 135, text = "МЕЛЬНИЦА →", color = rgb(240, 76, 64) },
	{ angle = 225, text = "БОЛЬШОЕ ДЕРЕВО →", color = rgb(64, 180, 80) },
	{ angle = 315, text = "ВЕРШИНА →", color = rgb(110, 110, 230) },
}

-- Flat pieces on the ground cast no shadows (cheaper on phones, nothing visible is lost).
local FLAT = { CastShadow = false }

local DECK_TOP = 0.64 -- above GroundTop: a hair above the bridge and pier decks (0.6)

--------------------------------------------------------------------------------------------
-- Bridges
--------------------------------------------------------------------------------------------

-- Half length (studs, along the bridge) of the mid-span lookout and how far it sticks out.
local LOOKOUT_HALF = 10
local LOOKOUT_OUT = 6.5

-- Mid-span lookout of a bridge (Props.bridge local frame `cf`: y = 0 is the deck top, local -Z
-- runs from the hub to the promenade, ±hw are the deck edges): a bump-out on both sides in the
-- gateway's colour with a thick railing, a bench facing the water, a lamp and a flag on the
-- outer corners, a stone pier under each, and a telescope. The bridge's own railing is cut
-- open there (see buildBridges). ~38 parts.
local function lookout(bridge: any, cf: any, hw: number, bedLocal: number, theme: any)
	local b = Kit.builder(bridge, "Lookout", cf)
	local zh = LOOKOUT_HALF
	local deckC = Kit.lerpColor(theme.color, C.White, 0.55)
	local railC = C.Wood
	local first
	for i, sx in { -1, 1 } do
		local x0, x1 = sx * (hw + 0.25), sx * (hw + LOOKOUT_OUT)
		local lo, hi = math.min(x0, x1), math.max(x0, x1)
		local deck = b:box(`Deck{i}`, lo, -1.2, -zh, hi, 0, zh, deckC)
		first = first or deck
		-- one stone pier under the bump-out
		local px0, px1 = sx * (hw + 1.4), sx * (hw + LOOKOUT_OUT - 1)
		b:box(`Pier{i}`, math.min(px0, px1), bedLocal, -3, math.max(px0, px1), -1.2, 3, C.StoneLight)
		-- railing: the outer rail and two end rails, on posts at the corners
		-- (rails 1.5 thick, inner posts 1.8: their faces stay clear of the lamp posts' 1.1)
		local ox = sx * (hw + LOOKOUT_OUT - 0.75)
		b:box(`Rail{i}`, ox - 0.75, 3.0, -zh + 0.75, ox + 0.75, 4.4, zh - 0.75, railC, Kit.NOSHADOW)
		for j, sz in { -1, 1 } do
			local z = sz * (zh - 0.75)
			local ix = sx * (hw - 0.45)
			b:box(
				`EndRail{i}_{j}`,
				math.min(ix, ox),
				3.0,
				z - 0.75,
				math.max(ix, ox),
				4.4,
				z + 0.75,
				railC,
				Kit.NOSHADOW
			)
			b:box(`InnerPost{i}_{j}`, ix - 0.9, -0.05, z - 0.9, ix + 0.9, 4.8, z + 0.9, C.WoodDark)
		end
		-- a lamp (theme-coloured caps) on one outer corner, a flag on the other
		local lampCf = cf * CFrame.new(ox, 0, -(zh - 0.75))
		Kit.lamp(b.model, lampCf, { height = 6.5, trim = theme.color, light = i == 2 })
		b:pole(`FlagPole{i}`, 0.7, ox, zh - 0.75, -0.05, 13, C.White)
		local fx0, fx1 = ox + sx * 0.3, ox + sx * 5.3
		b:box(`Flag{i}`, math.min(fx0, fx1), 9.4, zh - 0.9, math.max(fx0, fx1), 12.6, zh - 0.6, theme.color, Kit.DECOR)
		-- a chunky bench facing the water
		local bx = sx * (hw + 3.6)
		local backX0, backX1 = bx - sx * 1.5, bx - sx * 1.0
		b:box(`BenchBase{i}`, bx - 0.7, -0.05, -2.2, bx + 0.7, 1.5, 2.2, C.WoodDark)
		b:box(`BenchSeat{i}`, bx - 1.2, 1.5, -3, bx + 1.2, 2.1, 3, C.WoodLight)
		b:box(`BenchBack{i}`, math.min(backX0, backX1), 2.1, -3, math.max(backX0, backX1), 4.0, 3, theme.color)
	end
	-- a telescope on the right-hand bump-out, looking out over the lagoon
	local tx = hw + LOOKOUT_OUT - 2.4
	b:box("ScopeStand", tx - 0.4, -0.05, 6.1, tx + 0.4, 3.6, 6.9, C.Navy)
	b:box("ScopeTube", tx - 1.2, 3.6, 5.95, tx + 1.9, 4.7, 7.05, C.Gold)
	b:box("ScopeLens", tx + 1.9, 3.45, 5.8, tx + 2.2, 4.85, 7.2, C.Glass, Kit.NOSHADOW)
	b:finish(first)
	return b.model
end

function Promenade.buildBridges(map: any, cfg: any)
	local bridges = U.model(map, "Bridges")
	for i, angle in cfg.BridgeAngles do
		local theme = Promenade.Themes[angle % 360] or Promenade.Themes[0]
		local from = U.polar(angle, cfg.HubPlazaRadius - 6, 0)
		-- the deck runs 0.4 stud under the promenade tiles
		local to = U.polar(angle, cfg.PromenadeRadius + 0.4, 0)
		local deckY = cfg.GroundTop + 0.6
		local width = cfg.BridgeWidth
		-- no end arches: the hub's avenue gates and the gateway arches frame every crossing
		local bridge = Kit.prop("bridge", bridges, from, to, {
			deckY = deckY,
			width = width,
			bedY = -cfg.LagoonDepth,
			plankLength = 8,
			postSpacing = 16,
			bentSpacing = 48,
			roof = theme.color,
			gates = false,
			lights = false,
			seed = i * 31,
		})
		bridge.Name = `Bridge_{i}`
		-- the Props.bridge frame: y = 0 on the deck, local -Z from the hub to the promenade
		local a = Vector3.new(from.X, deckY, from.Z)
		local c = Vector3.new(to.X, deckY, to.Z)
		local cf = CFrame.lookAt((a + c) / 2, c)
		local hw = width / 2
		local L = (c - a).Magnitude
		local inv = cf:Inverse()
		local pastel = Kit.lerpColor(theme.color, C.White, 0.6)
		local open = LOOKOUT_HALF - 0.75 -- rails end inside the lookout's inner corner posts
		for _, d in bridge:GetChildren() do
			if not d:IsA("BasePart") then
				continue
			end
			local name = d.Name
			local lp = (inv * d.CFrame).Position
			if string.match(name, "^Deck%d+$") then
				-- planks: light / mid wood, every fourth one in the gateway's pastel
				local k = tonumber(string.sub(name, 5)) :: number
				d.Color = if k % 4 == 3 then pastel elseif k % 2 == 1 then C.WoodLight else C.Wood
			elseif string.match(name, "^TopRail") or string.match(name, "^MidRail") then
				-- split round the lookout; the top rail gets chunkier (1.2 x 1.4)
				local top = string.match(name, "^TopRail") ~= nil
				local size = if top then Vector3.new(1.2, 1.4, 0) else Vector3.new(d.Size.X, d.Size.Y, 0)
				local y = if top then 3.7 else lp.Y
				for j, seg in { { open, L / 2 }, { -L / 2, -open } } do
					local len = seg[2] - seg[1]
					U.part(
						bridge,
						`{name}_{j}`,
						Vector3.new(size.X, size.Y, len),
						cf * CFrame.new(lp.X, y, (seg[1] + seg[2]) / 2),
						d.Color,
						nil,
						if top then nil else Kit.NOSHADOW
					)
				end
				d:Destroy()
			elseif math.abs(lp.Z) < LOOKOUT_HALF + 0.5 and math.abs(lp.X) > hw - 2 and lp.Y > -0.2 and d.Size.Z < 4 then
				-- posts and lanterns in the opening
				d:Destroy()
			end
		end
		lookout(bridge, cf, hw, -cfg.LagoonDepth - deckY, theme)
	end
end

--------------------------------------------------------------------------------------------
-- Promenade ring
--------------------------------------------------------------------------------------------

-- Ring piece between angles a0..a1 (degrees) and radii r0..r1, top at y, as one block along
-- the chord (wide enough to cover the outer arc).
local function ringPiece(
	parent: any,
	name: string,
	a0: number,
	a1: number,
	r0: number,
	r1: number,
	y0: number,
	y1: number,
	color: any,
	extra: any?
): any
	local am = (a0 + a1) / 2
	local half = rad(a1 - a0) / 2
	local length = 2 * r1 * tan(half) + 0.1
	local rm = (r0 + r1) / 2 * cos(half) -- chord midpoint of the band
	local cf = U.polarCFrame(am, rm, (y0 + y1) / 2)
	return U.part(parent, name, Vector3.new(length, y1 - y0, r1 - r0), cf, color, nil, extra)
end

-- Railing gaps: piers (base angle ± PierGap), bridge landings (± BridgeGap) and the sand steps
-- down to the beach (± STEP_GAP at STEP_ANGLES, between two plots).
local PIER_GAP = 6
local BRIDGE_GAP = 3
local STEP_GAP = 1.3
local STEP_ANGLES = { 45, 135, 225, 315 }

-- The sea wall: its lagoon face (r = WALL_IN) hides the beach/grass step under the promenade's
-- lagoon edge; open only where a pier or bridge deck meets the promenade (± DECK_HALF studs).
local WALL_IN = 308.2
local DECK_HALF = 10

local function inGap(cfg: any, a: number): boolean
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		if Kit.angleDistance(a, base) < PIER_GAP then
			return true
		end
	end
	for _, b in cfg.BridgeAngles do
		if Kit.angleDistance(a, b) < BRIDGE_GAP then
			return true
		end
	end
	for _, s in STEP_ANGLES do
		if Kit.angleDistance(a, s) < STEP_GAP then
			return true
		end
	end
	return false
end

-- True where a pier or bridge deck crosses the sea wall line.
local function onDeck(cfg: any, a: number): boolean
	local half = math.deg(math.asin(DECK_HALF / WALL_IN))
	for i = 1, cfg.BaseCount do
		if Kit.angleDistance(a, cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount) < half then
			return true
		end
	end
	for _, b in cfg.BridgeAngles do
		if Kit.angleDistance(a, b) < half then
			return true
		end
	end
	return false
end

-- Continuous runs { a0, a1, class } of the ring (degrees, increasing) where class(a) is the
-- same; the scan starts on a pier (deck) so no run wraps around 360.
local function runs(cfg: any, class: (number) -> string): { { any } }
	local list = {}
	local step = 0.25
	local start, current = nil, nil
	local origin = cfg.BaseAngleOffset
	for k = 0, 360 / step do
		local a = origin + k * step
		local c = class(a)
		if c ~= current then
			if start then
				table.insert(list, { start, a - step, current })
			end
			start, current = a, c
		end
	end
	if start then
		table.insert(list, { start, origin + 360, current })
	end
	return list
end

-- Railing runs [a0, a1] outside the gaps.
local function railRuns(cfg: any): { { any } }
	local list = {}
	for _, run in
		runs(cfg, function(a)
			return if inGap(cfg, a) then "gap" else "rail"
		end)
	do
		if run[3] == "rail" then
			table.insert(list, run)
		end
	end
	return list
end

-- Splits [a0, a1] into pieces of at most `maxStep` degrees.
local function pieces(a0: number, a1: number, maxStep: number): { { number } }
	local n = math.max(1, math.ceil((a1 - a0) / maxStep - 1e-6))
	local list = {}
	for p = 0, n - 1 do
		table.insert(list, { a0 + (a1 - a0) * p / n, a0 + (a1 - a0) * (p + 1) / n })
	end
	return list
end

-- Colour of the promenade quarter around angle a: the theme of the nearest bridge/gateway, so
-- each quarter of the ring is recognisable (orange south, pink east, blue north, green west).
local function quarterColor(a: number): any
	local best, color = math.huge, C.Navy
	for angle, theme in Promenade.Themes do
		local d = Kit.angleDistance(a, angle)
		if d < best then
			best, color = d, theme.color
		end
	end
	return color
end

function Promenade.buildPromenade(map: any, cfg: any, world: any): number
	local promenade = U.model(map, "Promenade")
	local G = cfg.GroundTop
	local inner = cfg.PromenadeRadius
	local outer = inner + cfg.PromenadeWidth
	local top = G + DECK_TOP

	-- Paving: 48 tiles (7.5°) in two warm shades at two heights 0.12 apart (the chord
	-- rectangles overlap near the inner edge), a coral middle band and white kerbs.
	local paving = U.model(promenade, "Paving")
	local tiles = { rgb(255, 238, 206), rgb(255, 214, 168) }
	local step = 360 / 96 -- railing post grid (3.75°)
	for k = 0, 47 do
		local a0 = k * 2 * step
		local lift = (k % 2) * 0.12
		ringPiece(paving, "Tile", a0, a0 + 2 * step, inner + 0.2, outer, G - 1, top + lift, tiles[k % 2 + 1], FLAT)
	end
	local bandColor = rgb(255, 128, 104)
	local mid = (inner + outer) / 2
	for k = 0, 47 do
		local a0 = k * step * 2
		ringPiece(paving, "Band", a0, a0 + 2 * step, mid - 2.2, mid + 2.2, top, top + 0.28, bandColor, Kit.NOSHADOW)
	end
	local N = 96
	-- outer kerb (0.5 high: walkable) between the plots; in front of a plot its own front wall
	-- already edges the walk
	for k = 0, N / 2 - 1 do
		local a0 = k * step * 2
		local nearPlot = false
		for i = 1, cfg.BaseCount do
			local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
			if Kit.angleDistance(a0 + step, base) < 11 then
				nearPlot = true
			end
		end
		if not nearPlot then
			ringPiece(paving, "KerbOuter", a0, a0 + 2 * step, outer - 1.4, outer, top, top + 0.5, C.White, FLAT)
		end
	end

	-- Railing on the lagoon side, on the sea wall's coping: white posts every 3.75°, a blue top
	-- rail; lamps replace some posts; open at piers, bridges and the beach steps.
	local railing = U.model(promenade, "Railing")
	local railColor = rgb(70, 176, 255)
	local postR = inner + 0.9
	local lampModel = U.model(promenade, "Lamps")
	local lamps = 0
	local lampAngles = {}
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		for _, off in { 7.5, 15, 30, 37.5 } do
			lampAngles[floor(((base + off) % 360) * 100 + 0.5)] = true
		end
	end
	local function isLamp(a: number): boolean
		return lampAngles[floor((a % 360) * 100 + 0.5)] == true
	end
	-- Sea wall along the lagoon edge: a light stone face from the beach (y 1.5) up to the walk,
	-- under a white coping that is also the railing's kerb; where the railing is open (beside
	-- the piers and bridge landings, at the beach steps) the wall stops just under the tiles.
	local seaWall = U.model(promenade, "SeaWall")
	local stone = Kit.lerpColor(C.StoneLight, C.White, 0.25)
	for _, run in
		runs(cfg, function(a)
			return if onDeck(cfg, a) then "deck" elseif inGap(cfg, a) then "open" else "rail"
		end)
	do
		if run[3] == "deck" then
			continue
		end
		for _, pc in pieces(run[1], run[2], 7.5) do
			if run[3] == "rail" then
				ringPiece(seaWall, "Wall", pc[1], pc[2], WALL_IN + 0.2, inner + 0.3, 1.5, top - 0.2, stone, FLAT)
				ringPiece(seaWall, "Coping", pc[1], pc[2], WALL_IN, inner + 1.6, top - 0.2, top + 0.6, C.White, FLAT)
			else
				ringPiece(seaWall, "Wall", pc[1], pc[2], WALL_IN, inner + 0.3, 1.5, top - 0.12, stone, FLAT)
			end
		end
	end
	-- two sand steps down to the beach at each step gap
	for _, sa in STEP_ANGLES do
		local h = math.deg(math.asin(4 / WALL_IN))
		ringPiece(seaWall, "Step1", sa - h, sa + h, WALL_IN - 2.8, WALL_IN + 0.1, 1.5, 3.85, C.Cream, FLAT)
		ringPiece(seaWall, "Step2", sa - h, sa + h, WALL_IN - 5.6, WALL_IN - 2.8, 1.5, 2.95, C.SandDark, FLAT)
	end

	local posts = {}
	for _, run in railRuns(cfg) do
		local a0, a1 = run[1], run[2]
		-- posts at the run ends and on the 3.75° grid between them
		local list = { a0 }
		local g = math.ceil(a0 / step + 0.01) * step
		while g < a1 - 1 do
			table.insert(list, g)
			g += step
		end
		table.insert(list, a1)
		for j, a in list do
			local p = U.polar(a, postR, 0)
			if isLamp(a) then
				Kit.lamp(lampModel, CFrame.new(p.X, top + 0.6, p.Z) * CFrame.Angles(0, rad(a), 0), {
					height = 8,
					trim = quarterColor(a),
					light = lamps % 4 == 0,
				})
				lamps += 1
			else
				U.part(
					railing,
					"Post",
					Vector3.new(1.1, 3.2, 1.1),
					CFrame.new(p.X, top + 0.6 + 1.5, p.Z) * CFrame.Angles(0, rad(a), 0),
					C.White,
					nil,
					Kit.NOSHADOW
				)
			end
			if j > 1 then
				local q = U.polar(list[j - 1], postR, 0)
				local d = Vector3.new(p.X - q.X, 0, p.Z - q.Z)
				local m = (p + q) / 2
				U.part(
					railing,
					"Rail",
					Vector3.new(0.8, 0.7, d.Magnitude),
					CFrame.lookAt(Vector3.new(m.X, top + 3.0, m.Z), Vector3.new(p.X, top + 3.0, p.Z)),
					railColor,
					nil,
					Kit.NOSHADOW
				)
			end
			table.insert(posts, a)
		end
	end

	-- Bunting between the first two lamps after each pier (lantern tops ~ y + 11).
	local bunting = U.model(promenade, "Bunting")
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		local pa = U.polar(base + 7.5, postR, top + 10.9)
		local pb = U.polar(base + 15, postR, top + 10.9)
		Kit.prop("bunting", bunting, pa, pb, { seed = i * 7, count = 4, sag = 2.4, name = "Bunting" })
	end

	-- A bench facing the lagoon and flower boxes on both sides of each plot's gate.
	local furniture = U.model(promenade, "Furniture")
	local boxColors = { C.Red, C.Blue, C.Yellow, C.Pink, C.Purple, C.Orange }
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		local ab = base + 9
		local p = U.polar(ab, outer - 3.2, 0)
		Kit.prop("bench", furniture, CFrame.new(p.X, top, p.Z) * CFrame.Angles(0, rad(ab), 0), {
			length = 7,
			color = C.WoodLight,
			seed = i * 2,
		})
		for j, sgn in { -1, 1 } do
			local af = base + sgn * 5.6
			local q = U.polar(af, outer - 2.2, 0)
			Kit.prop("flowerBox", furniture, CFrame.new(q.X, top, q.Z) * CFrame.Angles(0, rad(af), 0), {
				length = 6,
				color = boxColors[(i + j) % #boxColors + 1],
				seed = i * 5 + j,
			})
		end
	end

	-- Big billboards at the landmark path mouths (land side, beside the path, facing the
	-- lagoon), on the first spot where both feet stand on the same flat ground (the waterfall
	-- pond's sand rim reaches the promenade).
	for _, sign in PATH_SIGNS do
		local spot = nil
		for _, d in { 2.7, 3.4, 4.1, -2.7, -3.4, 4.8, 5.5 } do
			for _, dr in { 5, 4, 7 } do
				local a = sign.angle + d
				local ok = true
				for _, f in { -6, -4, 0, 4, 6 } do
					local x, z = Kit.radial(a, outer + dr, f, 0)
					local h, kind, water = world:surfaceAt(x, z)
					if water or h ~= G or kind == "sand" then
						ok = false
					end
				end
				if ok then
					spot = { a, outer + dr }
					break
				end
			end
			if spot then
				break
			end
		end
		local a, r = (spot or { sign.angle + 2.7, outer + 5 })[1], (spot or { sign.angle + 2.7, outer + 5 })[2]
		local p = U.polar(a, r, 0)
		Kit.prop(
			"billboard",
			promenade,
			CFrame.new(p.X, world:heightAt(p.X, p.Z), p.Z) * CFrame.Angles(0, rad(sign.angle), 0),
			{
				text = sign.text,
				width = 13,
				height = 4,
				lift = 3.5,
				color = sign.color,
				back = false,
				name = "PathSign",
			}
		)
	end

	return lamps
end

return Promenade
