--[[
	Promenade — the 4 bridges (hub plaza ↔ promenade) and the promenade ring along the lagoon
	(World v3, tools/builder/DESIGN.md §2/§6).

	  Map.Bridges     Bridge_1..4 at θ = BridgeAngles: chunky Props.bridge from the hub plaza
	                  (r ≈ 118) to the promenade (r ≈ 312), deck top GroundTop + 0.6, gates with
	                  a name board at both ends, the roofs in the colour of its gateway
	  Map.Promenade   the ring walk r 312..330 on flat GroundTop: paving tiles in two warm
	                  shades with a coral middle band and white kerbs; a low white railing with a
	                  blue rail on the lagoon side, open at the 8 pier entrances (base ± 6°) and
	                  the 4 bridge landings; chunky lamps (caps in the colour of the nearest
	                  gateway: each quarter of the ring has its own), bunting, benches and
	                  flower boxes in front of the plots, big billboards at the landmark paths.

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

function Promenade.buildBridges(map: any, cfg: any)
	local bridges = U.model(map, "Bridges")
	for i, angle in cfg.BridgeAngles do
		local theme = Promenade.Themes[angle % 360] or Promenade.Themes[0]
		local from = U.polar(angle, cfg.HubPlazaRadius - 6, 0)
		-- the deck runs 0.4 stud under the promenade tiles; the gate stands on the beach edge
		local to = U.polar(angle, cfg.PromenadeRadius + 0.4, 0)
		local bridge = Kit.prop("bridge", bridges, from, to, {
			deckY = cfg.GroundTop + 0.6,
			width = cfg.BridgeWidth,
			bedY = -cfg.LagoonDepth,
			plankLength = 8,
			postSpacing = 16,
			bentSpacing = 32,
			roof = theme.color,
			signText = theme.bridge,
			lights = false,
			seed = i * 31,
		})
		bridge.Name = `Bridge_{i}`
		-- one warm light under the promenade-side gate (the prop's own lights are off)
		for _, d in bridge:GetChildren() do
			if d.Name == "ArchLamp2_1" then
				Kit.light(d, 16, 1.4)
			end
		end
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

-- Railing gaps: piers (base angle ± PierGap) and bridge landings (± BridgeGap).
local PIER_GAP = 6
local BRIDGE_GAP = 3

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
	return false
end

-- Continuous runs [a0, a1] of the ring (degrees, increasing) outside the gaps.
local function railRuns(cfg: any): { { number } }
	local runs = {}
	local step = 0.25
	local start: number? = nil
	-- start the scan inside a gap so no run wraps around 360
	local origin = cfg.BaseAngleOffset
	for k = 0, 360 / step do
		local a = origin + k * step
		local open = not inGap(cfg, a)
		if open and not start then
			start = a
		elseif not open and start then
			table.insert(runs, { start, a - step })
			start = nil
		end
	end
	return runs
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

	-- Paving: 96 tiles (3.75°) in two warm shades, slightly different heights (the chord
	-- rectangles overlap near the inner edge), a coral middle band and white kerbs.
	local paving = U.model(promenade, "Paving")
	local tiles = { rgb(255, 238, 206), rgb(255, 214, 168) }
	local N = 96
	local step = 360 / N
	for k = 0, N - 1 do
		local a0 = k * step
		local lift = (k % 2) * 0.06
		ringPiece(paving, "Tile", a0, a0 + step, inner + 0.2, outer, G - 1, top + lift, tiles[k % 2 + 1], FLAT)
	end
	local bandColor = rgb(255, 128, 104)
	local mid = (inner + outer) / 2
	for k = 0, N / 2 - 1 do
		local a0 = k * step * 2
		ringPiece(paving, "Band", a0, a0 + 2 * step, mid - 2.2, mid + 2.2, top, top + 0.16, bandColor, Kit.NOSHADOW)
	end
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

	-- Railing on the lagoon side: kerb, white posts every 3.75°, a blue top rail; lamps replace
	-- some posts; open at piers and bridges.
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
	local posts = {}
	for _, run in railRuns(cfg) do
		local a0, a1 = run[1], run[2]
		-- kerb pieces of at most 7.5°
		local pieces = math.max(1, math.ceil((a1 - a0) / 7.5))
		for p = 0, pieces - 1 do
			local s0 = a0 + (a1 - a0) * p / pieces
			local s1 = a0 + (a1 - a0) * (p + 1) / pieces
			ringPiece(railing, "Kerb", s0, s1, inner + 0.2, inner + 1.6, top, top + 0.6, C.White, FLAT)
		end
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

	-- Big billboards at the landmark path mouths (land side, beside the path, facing the lagoon).
	for _, sign in PATH_SIGNS do
		local a = sign.angle + 2.7
		local p = U.polar(a, outer + 5, 0)
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
