--[[
	Shore — the waterline, the beaches and the lagoon's edges (v3 micro-detail, DESIGN.md §6),
	built last by Map.luau (with Promenade.buildDetails, within LATE_BUDGET), after every other
	dressing module, so it keeps off all of them: each footprint is tested against the parts
	already in the map (MapKit.obstacles).

	  Map.Shore.Foam       a strip of surf along every edge where the beach sand meets the water,
	                       on the ring's beach and round the hub island (one part per straight run
	                       of the voxel edge; none under the piers and bridges); attribute Pulse on
	                       the model (the ambient wave breathes its transparency)
	  Map.Shore.Beach      little beach stories on the ring beach either side of every pier — a
	                       sandcastle with a pail and spade, a towel under a parasol with a beach
	                       ball, driftwood with shells, a toy pinwheel (Spin) by an upturned pail, a
	                       bottle washed up among shells — different on every stretch, with a
	                       small find near the pier steps (shells, a pail, a ball) and rocks or
	                       reeds (Sway) at the waterline
	  Map.Shore.Lagoon     a line of red and white floats either side of every base's fishing water
	                       (|base-local x| 34, out to z -84; each float bobs: Bob), a drifting crate
	                       or barrel (Bob) and a lily cluster per stretch
	  Map.Shore.Underwater kelp on the sandy slope (Sway; the tops 2+ studs under the surface, dark
	                       shapes through the water), a sunken chest per stretch for kids to spot

	Rules (tests/map_dressing.test.luau): every part is decor (no collisions, raycasts, touches;
	only the chest casts no shadow either), nothing above y -0.6 (the water at -4 base-local + 3.4)
	in any pier's cast clear zone (base-local x -6..16, z -72..-115), nothing within 26 studs of a
	pier's axis from the promenade to z -92 (the pier, its boat, the cast), nothing on the bridges.
	Colours from Palette (calm sand and wood; jewel tones only on small toys). No animals or
	figures (DESIGN.md §1).
]]

local U = require("./Util")
local Kit = require("./MapKit")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Enum = U.Enum
local C = Kit.C
local lerp = Kit.lerpColor

local rad, sin, cos, abs, floor, sqrt = math.rad, math.sin, math.cos, math.abs, math.floor, math.sqrt
local max, min = math.max, math.min

local Shore = {}

local DECOR = Kit.DECOR
local BALL = { Shape = Enum.PartType.Ball, CanCollide = false, CastShadow = false, CanQuery = false }
local CYL = { Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false, CanQuery = false }

local SAND_TOP = 2 -- the beaches (ring and hub) stand at y 2
local FOAM_W = 1.8 -- surf strip width (out from the sand face)
local FOAM_Y0, FOAM_Y1 = -0.15, 0.2 -- (the water plane is y 0)
local FOAM = lerp(C.Foam, C.WaterLight, 0.12)
local WET_W = 2 -- wet sand band along the sand's edge (whole studs: its studs line up with the sand's)
local WET_RISE = 0.1 -- (its top over the sand top)
local WET = lerp(C.SandDark, C.Dirt, 0.3) -- (a clear step darker than the dry sand: it reads at a distance)

local SHELL = { C.Cream, lerp(C.Pink, C.Cream, 0.55), lerp(C.Orange, C.Cream, 0.6) }
local DRIFT = lerp(C.WoodLight, C.StoneLight, 0.45)
local KELP = { lerp(C.Seaweed, C.Leaf0, 0.3), lerp(C.Seaweed, C.Navy, 0.25) }
local ROCK = { lerp(C.RockMid, C.SandDark, 0.25), lerp(C.RockLight, C.SandDark, 0.2) }

--------------------------------------------------------------------------------------------
-- Where things may go
--------------------------------------------------------------------------------------------

-- Base-local (x, z) of (x, z) for the nearest base, and its index.
local function nearestBase(cfg: any, world: any, x: number, z: number): (number, number, number)
	local best, bx, bz = 1, math.huge, math.huge
	for i = 1, cfg.BaseCount do
		local lx, lz = world:toBaseLocal(i, x, z)
		if lx * lx + lz * lz < bx * bx + bz * bz then
			best, bx, bz = i, lx, lz
		end
	end
	return best, bx, bz
end

-- True near a pier (its deck, its moored boat, the fishing water in front of it) or a bridge.
local function nearPierOrBridge(cfg: any, world: any, x: number, z: number, pad: number): boolean
	local _, lx, lz = nearestBase(cfg, world, x, z)
	if abs(lx) < 26 + pad and lz > -92 - pad and lz < 6 then
		return true
	end
	for _, a in cfg.BridgeAngles do
		local ux, uz = sin(rad(a)), cos(rad(a))
		if x * ux + z * uz > cfg.HubPlazaRadius - 20 and abs(x * uz - z * ux) < cfg.BridgeWidth / 2 + 3 + pad then
			return true
		end
	end
	return false
end

-- The cast clear zone of any pier (base-local x -6..16, z -72..-115).
local function inCastZone(cfg: any, world: any, x: number, z: number, pad: number): boolean
	for i = 1, cfg.BaseCount do
		local lx, lz = world:toBaseLocal(i, x, z)
		if lx > -6 - pad and lx < 16 + pad and lz < -72 + pad and lz > -115 - pad then
			return true
		end
	end
	return false
end

--------------------------------------------------------------------------------------------
-- Foam and wet sand along the sand edges
--------------------------------------------------------------------------------------------

--[[
	Strips along every straight run of the voxel edge where beach sand (y 2) meets the water: the
	surf (out in the water, at the water plane, `outside`) or the wet sand (on the sand's top,
	along its edge). The x-facing strips own the corners: where two runs meet they are trimmed or
	lengthened by the strip width, so no two strips overlap (coplanar transparent / studded
	overlaps would shimmer) and no corner is left open.
]]
local function buildEdge(parent: any, cfg: any, world: any, blocked: any, outside: boolean): number
	local W = if outside then FOAM_W else WET_W
	local y0, y1 = if outside then FOAM_Y0 else SAND_TOP - 0.3, if outside then FOAM_Y1 else SAND_TOP + WET_RISE
	local n, cell = world.n, world.cell
	local function sand(ix: number, iz: number): boolean
		return world:topAtCell(ix, iz) == SAND_TOP and world:kindAtCell(ix, iz) == "sand"
	end
	local function wet(ix: number, iz: number): boolean
		return world:topAtCell(ix, iz) < cfg.WaterTop
	end
	local function inBand(ix: number, iz: number): boolean
		local x, z = (ix + 0.5) * cell, (iz + 0.5) * cell
		local r = sqrt(x * x + z * z)
		return (r > cfg.HubPlazaRadius and r < cfg.HubRadius + 12)
			or (r > cfg.LagoonRadius - 12 and r < cfg.PromenadeRadius)
	end
	-- the strip of one edge cell (sand at (ix, iz), water on side d), as world x0, z0, x1, z1
	local function rect(ix: number, iz: number, dx: number, dz: number): (number, number, number, number)
		local sgn = if dx + dz > 0 then 1 else -1
		local lo = if dx ~= 0 then ix else iz
		local face = if sgn > 0 then (lo + 1) * cell else lo * cell
		-- (the water lies on the sgn side of the face: the surf out there, the wet sand in here)
		local a, b
		if outside then
			a, b = face, face + W * sgn
		else
			a, b = face - W * sgn, face
		end
		a, b = min(a, b), max(a, b)
		if dx ~= 0 then
			return a, iz * cell, b, (iz + 1) * cell
		end
		return ix * cell, a, (ix + 1) * cell, b
	end
	local function edge(ix: number, iz: number, dx: number, dz: number): boolean
		if not (sand(ix, iz) and wet(ix + dx, iz + dz) and inBand(ix, iz)) then
			return false
		end
		local x0, z0, x1, z1 = rect(ix, iz, dx, dz)
		local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
		-- none under a pier's deck (|x| < 12 base-local) or a bridge's
		local _, lx, lz = nearestBase(cfg, world, cx, cz)
		if abs(lx) < 12 + (x1 - x0 + z1 - z0) / 2 and lz > -92 and lz < 6 then
			return false
		end
		for _, a in cfg.BridgeAngles do
			local ux, uz = sin(rad(a)), cos(rad(a))
			if cx * ux + cz * uz > cfg.HubPlazaRadius - 20 and abs(cx * uz - cz * ux) < cfg.BridgeWidth / 2 + 6 then
				return false
			end
		end
		return not blocked(CFrame.new(cx, 0, cz), x1 - x0, z1 - z0, y0, y1)
	end
	local count = 0
	for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local dx, dz = d[1], d[2]
		-- runs go along z for the x-facing edges, along x for the z-facing ones
		for s = -n, n - 1 do
			local t = -n
			while t < n do
				local ix, iz = if dx ~= 0 then s else t, if dx ~= 0 then t else s
				if not edge(ix, iz, dx, dz) then
					t += 1
					continue
				end
				local t1 = t
				while t1 + 1 < n do
					local jx, jz = if dx ~= 0 then s else t1 + 1, if dx ~= 0 then t1 + 1 else s
					if not edge(jx, jz, dx, dz) then
						break
					end
					t1 += 1
				end
				local x0, z0 = rect(ix, iz, dx, dz)
				local ex, ez = if dx ~= 0 then s else t1, if dx ~= 0 then t1 else s
				local _, _, x1, z1 = rect(ex, ez, dx, dz)
				if dx ~= 0 then
					local wx = s + dx
					for _, e in { { t1 + 1, 1 }, { t - 1, -1 } } do
						local nt, dir = e[1], e[2]
						local trim = 0
						if outside then
							-- surf: trimmed in a concave corner (the z-facing strip runs there),
							-- lengthened round a convex sand corner (open water on both sides)
							if sand(wx, nt) then
								trim = W
							elseif wet(s, nt) and wet(wx, nt) then
								trim = -W
							end
						elseif wet(s, nt) then
							-- wet sand: trimmed at a convex corner (the z-facing strip covers it)
							trim = W
						end
						if dir > 0 then
							z1 -= trim
						else
							z0 += trim
						end
					end
				end
				if outside then
					U.part(
						parent,
						"Foam",
						Vector3.new(x1 - x0, y1 - y0, z1 - z0),
						CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
						FOAM,
						nil,
						{ Transparency = 0.3, CanCollide = false, CanQuery = false, CastShadow = false }
					)
				else
					-- (a thin plate on the sand: its top WET_RISE over the sand's studs)
					U.part(
						parent,
						"WetSand",
						Vector3.new(x1 - x0, WET_RISE + 0.2, z1 - z0),
						CFrame.new((x0 + x1) / 2, SAND_TOP + (WET_RISE - 0.2) / 2, (z0 + z1) / 2),
						WET,
						nil,
						{ CanCollide = false, CanQuery = false, CastShadow = false }
					)
				end
				count += 1
				t = t1 + 1
			end
		end
	end
	return count
end

local function buildFoam(shore: any, cfg: any, world: any, blocked: any): number
	local foam = U.model(shore, "Foam")
	foam:SetAttribute("Pulse", 0.25)
	foam:SetAttribute("PulsePeriod", 3.5)
	local wetSand = U.model(shore, "WetSand")
	return buildEdge(foam, cfg, world, blocked, true) + buildEdge(wetSand, cfg, world, blocked, false)
end

--------------------------------------------------------------------------------------------
-- Beach stories (local frame: x along the shore, -z towards the water, y 0 = the sand top)
--------------------------------------------------------------------------------------------

local function shell(b: any, x: number, z: number, k: number)
	b:block(
		"Shell",
		Vector3.new(0.7, 0.32, 0.6),
		CFrame.new(x, 0.12, z) * CFrame.Angles(0, rad(k * 47), 0),
		SHELL[k % #SHELL + 1],
		DECOR
	)
end

local function pail(b: any, x: number, z: number, color: any, upturned: boolean?)
	b:block("Pail", Vector3.new(1.2, 1.1, 1.1), CFrame.new(x, 0.6, z) * CFrame.Angles(0, 0, rad(90)), color, CYL)
	if not upturned then
		b:box("PailRim", x - 0.62, 1.12, z - 0.12, x + 0.62, 1.26, z + 0.12, C.White, DECOR)
	end
end

local function spade(b: any, x: number, z: number, color: any)
	b:block(
		"Spade",
		Vector3.new(0.22, 1.6, 0.55),
		CFrame.new(x, 0.7, z) * CFrame.Angles(rad(-22), 0, rad(14)),
		color,
		DECOR
	)
end

-- Every story: { name, width (x), depth (z, from the water side), build(b, k) }.
local STORIES = {
	{
		name = "Sandcastle",
		w = 6,
		d = 4.5,
		build = function(b: any, k: number)
			local sand = lerp(C.SandDark, C.Sand, 0.2)
			b:box("Castle", -1.6, 0, -1.4, 1.6, 1.2, 1.4, sand, DECOR)
			b:box("CastleTower", -1.7, 1.2, -1.5, -0.5, 2.6, -0.3, lerp(sand, C.SandWet, 0.5), DECOR)
			b:box("CastleTower", 0.5, 1.2, 0.3, 1.7, 2.2, 1.5, lerp(sand, C.SandWet, 0.5), DECOR)
			local flag = b:box("CastleFlag", -1.15, 2.95, -0.95, -1.05, 3.55, -0.35, C.Flowers[k % 2 * 6 + 1], DECOR)
			b:box("FlagStick", -1.2, 2.6, -0.95, -1.0, 3.6, -0.85, C.WoodLight, DECOR)
			flag:SetAttribute("Sway", 14)
			flag:SetAttribute("SwayAxis", "Y")
			flag:SetAttribute("SwayPeriod", 1.6)
			flag.PivotOffset = flag.CFrame:Inverse() * (b.cf * CFrame.new(-1.1, 3.25, -0.9))
			pail(b, 2.7, -0.6, C.Flowers[7 - (k % 2) * 5])
			spade(b, 2.5, 1.0, C.Flowers[2])
		end,
	},
	{
		name = "Parasol",
		w = 7,
		d = 6,
		build = function(b: any, k: number)
			local towel = C.BoatPaint[(k % 3) + 2]
			b:block(
				"Towel",
				Vector3.new(2.8, 0.08, 4.6),
				CFrame.new(-1.2, 0.04, 0) * CFrame.Angles(0, rad(-8), 0),
				towel,
				DECOR
			)
			b:block(
				"TowelStripe",
				Vector3.new(2.84, 0.1, 0.7),
				CFrame.new(-1.2, 0.05, 0.4) * CFrame.Angles(0, rad(-8), 0),
				C.White,
				DECOR
			)
			b:pole("ParasolPole", 0.3, 1.0, 1.4, 0, 6.2, C.White, DECOR)
			b:box("ParasolTop", -1.5, 5.6, -1.1, 3.5, 6.2, 3.9, C.Flowers[if k % 2 == 0 then 1 else 6], DECOR)
			b:box("ParasolTop2", -0.5, 6.15, -0.1, 2.5, 6.75, 2.9, C.White, DECOR)
			b:block("BeachBall", Vector3.new(1.3, 1.3, 1.3), CFrame.new(1.9, 0.65, -1.6), C.Flowers[7], BALL)
		end,
	},
	{
		name = "Driftwood",
		w = 8,
		d = 3.5,
		build = function(b: any, k: number)
			b:block(
				"Drift",
				Vector3.new(6.4, 0.9, 0.9),
				CFrame.new(0, 0.35, 0) * CFrame.Angles(0, rad(12 + k * 7), 0),
				DRIFT,
				CYL
			)
			b:block(
				"DriftBranch",
				Vector3.new(0.5, 0.5, 2.0),
				CFrame.new(1.4, 0.35, -0.9) * CFrame.Angles(0, rad(52), 0),
				DRIFT,
				DECOR
			)
			for j, p in { { -2.6, -1.2 }, { 2.9, 1.1 }, { -0.4, 1.3 } } do
				shell(b, p[1], p[2], k + j)
			end
		end,
	},
	{
		name = "Pinwheel",
		w = 5,
		d = 4,
		build = function(b: any, k: number)
			b:pole("PinwheelStick", 0.2, 0, 0, -0.2, 3.4, C.WoodLight, DECOR)
			-- the toy windmill turns about its axle (local +Z faces the sea breeze): Spin
			local hub = b.cf * CFrame.new(0, 3.4, -0.2)
			local wheel = U.model(b.model, "Pinwheel")
			wheel:SetAttribute("Spin", 120)
			local p1 = U.part(wheel, "Vane", Vector3.new(2.2, 0.5, 0.08), hub, C.Flowers[(k % 3) * 2 + 1], nil, DECOR)
			U.part(wheel, "Vane", Vector3.new(0.5, 2.2, 0.08), hub * CFrame.new(0, 0, 0.02), C.Flowers[2], nil, DECOR)
			wheel.PrimaryPart = p1
			p1.PivotOffset = CFrame.new()
			pail(b, -1.6, 0.6, C.Flowers[if k % 2 == 0 then 3 else 7], true)
			b:box("SandTower", -2.15, 0, 0.05, -1.05, 1.0, 1.15, lerp(C.SandDark, C.Sand, 0.3), DECOR)
			spade(b, 1.5, 0.8, C.Flowers[6])
		end,
	},
	{
		name = "Bottle",
		w = 5,
		d = 3,
		build = function(b: any, k: number)
			b:block(
				"Bottle",
				Vector3.new(1.5, 0.6, 0.6),
				CFrame.new(0, 0.22, 0) * CFrame.Angles(0, rad(30 + k * 11), rad(8)),
				lerp(C.Glass, C.Leaf2, 0.35),
				CYL
			)
			b:block(
				"Cork",
				Vector3.new(0.35, 0.36, 0.36),
				CFrame.new(0, 0.22, 0) * CFrame.Angles(0, rad(30 + k * 11), rad(8)) * CFrame.new(0.9, 0, 0),
				C.WoodLight,
				CYL
			)
			for j, p in { { -1.8, 0.6 }, { 1.7, -0.7 }, { 1.2, 1.0 }, { -1.0, -0.9 } } do
				shell(b, p[1], p[2], k + j)
			end
		end,
	},
}

-- Small finds near the pier steps (1-2 parts).
local FINDS = {
	function(b: any, k: number)
		shell(b, -0.6, 0.2, k)
		shell(b, 0.7, -0.3, k + 1)
	end,
	function(b: any, k: number)
		pail(b, 0, 0, C.Flowers[if k % 2 == 0 then 2 else 3])
	end,
	function(b: any, _k: number)
		b:block("BeachBall", Vector3.new(1.3, 1.3, 1.3), CFrame.new(0, 0.65, 0), C.Flowers[1], BALL)
	end,
	function(b: any, k: number)
		b:block(
			"Crate",
			Vector3.new(1.8, 1.4, 1.8),
			CFrame.new(0, 0.55, 0) * CFrame.Angles(rad(6), rad(20 + k * 9), 0),
			lerp(C.WoodLight, C.StoneLight, 0.3),
			DECOR
		)
		shell(b, 1.5, 0.4, k)
	end,
}

--[[
	A footprint w x d (local x, z) at angle a, radius r on the ring beach: every corner and the
	middle on beach sand (y 2) and clear of every part already there (from 0.3 under to 7 over the
	sand). Returns the frame (local -Z towards the lagoon) or nil.
]]
local function beachSpot(cfg: any, world: any, blocked: any, a: number, r: number, w: number, d: number): any
	local cf = U.polarCFrame(a, r, SAND_TOP)
	for _, p in { { -w / 2, -d / 2 }, { w / 2, -d / 2 }, { -w / 2, d / 2 }, { w / 2, d / 2 }, { 0, 0 } } do
		local q = cf * Vector3.new(p[1], 0, p[2])
		if world:heightAt(q.X, q.Z) ~= SAND_TOP or world:kindAt(q.X, q.Z) ~= "sand" then
			return nil
		end
		if nearPierOrBridge(cfg, world, q.X, q.Z, 0) then
			return nil
		end
	end
	if blocked(cf, w, d, SAND_TOP - 0.3, SAND_TOP + 7) then
		return nil
	end
	return cf
end

-- First spot found round (a, r): nudged along the ring and across the beach.
local function findSpot(
	cfg: any,
	world: any,
	blocked: any,
	a: number,
	r: number,
	w: number,
	d: number,
	side: number
): any
	for _, dr in { 0, -1.5, 1.5, -3, 3 } do
		for _, da in { 0, 1.2, -1.2, 2.4, -2.4, 3.6 } do
			local cf = beachSpot(cfg, world, blocked, a + da * side, r + dr, w, d)
			if cf then
				return cf
			end
		end
	end
	return nil
end

-- The radius of the first water column out from r along the ray a (the beach's lagoon edge).
local function waterEdge(world: any, a: number, r: number): number
	local rr = r
	while rr > r - 20 do
		local p = U.polar(a, rr, 0)
		if world:isWater(p.X, p.Z) then
			return rr
		end
		rr -= 0.5
	end
	return r - 20
end

local function buildBeach(shore: any, cfg: any, world: any, blocked: any): number
	local beach = U.model(shore, "Beach")
	local before = U.partCount
	local rng = Kit.rng(4242)
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		for j, side in { -1, 1 } do
			local k = (i - 1) * 2 + j -- 1..16: every stretch its own scene
			-- the story, half-way between the vignette (±11.5°) and the bridge / beach steps
			local story = STORIES[(k * 3) % #STORIES + 1]
			local cf = findSpot(cfg, world, blocked, base + side * 16.5, 300.5, story.w, story.d, side)
			if cf then
				local b = Kit.builder(beach, story.name, cf)
				story.build(b, k)
				b:finish()
			end
			-- a small find beside the pier steps
			local find = FINDS[(k + i) % #FINDS + 1]
			local fcf = findSpot(cfg, world, blocked, base + side * 7.6, 299, 3, 2.5, side)
			if fcf then
				local b = Kit.builder(beach, "Find", fcf)
				find(b, k)
				b:finish()
			end
			-- rocks or reeds at the waterline, further along
			local a = base + side * rng(19.5, 21)
			local edgeR = waterEdge(world, a, 304)
			local p = U.polar(a, edgeR - 1.2, 0)
			if not nearPierOrBridge(cfg, world, p.X, p.Z, 4) and not blocked(CFrame.new(p.X, 0, p.Z), 6, 6, -2, 6) then
				local cfw = U.polarCFrame(a, edgeR - 1.2, 0)
				local b = Kit.builder(beach, if k % 2 == 0 then "Reeds" else "Rocks", cfw)
				if k % 2 == 0 then
					-- two reed tufts in the shallows, swaying from the bed
					for t, q in { { -0.6, 0.3 }, { 0.9, -0.5 } } do
						local tuft = U.model(b.model, "ReedTuft")
						local h = 3.6 + t * 0.4
						U.part(
							tuft,
							"Reed",
							Vector3.new(0.4, h, 0.4),
							cfw * CFrame.new(q[1], -2 + h / 2, q[2]),
							C.Leaf0,
							nil,
							DECOR
						)
						U.part(
							tuft,
							"Reed",
							Vector3.new(0.4, h - 0.9, 0.4),
							cfw * CFrame.new(q[1] + 0.5, -2 + (h - 0.9) / 2, q[2] + 0.4),
							C.Leaf2,
							nil,
							DECOR
						)
						tuft.PrimaryPart = tuft:FindFirstChild("Reed")
						tuft.PrimaryPart.PivotOffset = tuft.PrimaryPart.CFrame:Inverse()
							* (cfw * CFrame.new(q[1], -2, q[2]))
						tuft:SetAttribute("Sway", 5)
						tuft:SetAttribute("SwayAxis", "X")
						tuft:SetAttribute("SwayPeriod", 3.4 + t * 0.5)
					end
				else
					-- a pair of rounded rocks half in the water
					b:block(
						"Rock",
						Vector3.new(2.8, 3.1, 2.4),
						CFrame.new(0, -0.45, 0.6) * CFrame.Angles(0, rad(20), 0),
						ROCK[1],
						DECOR
					)
					b:block(
						"Rock",
						Vector3.new(1.6, 2.4, 1.5),
						CFrame.new(1.9, -0.8, -0.6) * CFrame.Angles(0, rad(-15), 0),
						ROCK[2],
						DECOR
					)
				end
				b:finish()
			end
		end
	end

	-- The hub island's beach (r 166..185) between the hub's own beach zones: a few stories and
	-- finds, the tall ones (the parasol, the pinwheel) never on a base's view lane to the tower.
	local placed = 0
	local last = -math.huge
	for step = 0, 47 do
		local a = 3.75 + step * 7.5
		if a - last < 22 then
			continue
		end
		local lane = (a - cfg.BaseAngleOffset) % 45
		local onLane = lane < 7 or lane > 38
		local k = step + 3
		local story = STORIES[k % #STORIES + 1]
		local tall = story.name == "Parasol" or story.name == "Pinwheel"
		if onLane and tall then
			story = STORIES[3] -- driftwood: low
		end
		local cf = findSpot(cfg, world, blocked, a, 174, story.w, story.d, 1)
		if cf then
			local b = Kit.builder(beach, story.name, cf)
			story.build(b, k)
			b:finish()
			placed += 1
			last = a
		end
	end
	local _ = placed
	return U.partCount - before
end

--------------------------------------------------------------------------------------------
-- The lagoon's edges: float lines, drifting cargo, lilies, kelp, sunken chests
--------------------------------------------------------------------------------------------

-- A model that bobs on the water (AmbientController: Bob = amplitude, BobPeriod).
local function bobbing(model: any, amplitude: number, period: number): any
	model:SetAttribute("Bob", amplitude)
	model:SetAttribute("BobPeriod", period)
	return model
end

local function buildLagoon(shore: any, cfg: any, world: any, blocked: any): number
	local lagoon = U.model(shore, "Lagoon")
	local under = U.model(shore, "Underwater")
	local before = U.partCount
	-- world point of base i's local (lx, lz)
	local function at(i: number, lx: number, lz: number): (number, number)
		local a = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		local slot = U.polarCFrame(a, cfg.BaseRadius, 0)
		local p = slot * Vector3.new(lx, 0, lz)
		return p.X, p.Z
	end
	local function openWater(x: number, z: number, pad: number): boolean
		for _, d in { { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			if not world:isWater(x + d[1] * pad, z + d[2] * pad) then
				return false
			end
		end
		return not blocked(CFrame.new(x, 0, z), 2 * pad, 2 * pad, -16, 6)
	end
	for i = 1, cfg.BaseCount do
		-- the base's fishing water marked by a line of floats on both sides (red and white)
		for _, side in { -1, 1 } do
			for f, lz in { -46, -58, -70, -82 } do
				local x, z = at(i, side * 34, lz)
				if openWater(x, z, 1.5) and not inCastZone(cfg, world, x, z, 2) then
					local m = bobbing(U.model(lagoon, "Float"), 0.15, 2.2 + 0.25 * ((f + i) % 3))
					local p = U.part(
						m,
						"Float",
						Vector3.new(1.1, 1.1, 1.1),
						CFrame.new(x, 0.2, z),
						if f % 2 == 1 then C.Red else C.White,
						nil,
						BALL
					)
					m.PrimaryPart = p
				end
			end
		end
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		-- a drifting crate or barrel between this pier and the next stretch's boats
		for _, try in { { 13, 262 }, { 15, 255 }, { 11, 268 }, { 17, 250 } } do
			local a = base + (if i % 2 == 0 then -1 else 1) * try[1]
			local p = U.polar(a, try[2], 0)
			if openWater(p.X, p.Z, 4) and not nearPierOrBridge(cfg, world, p.X, p.Z, 4) then
				local m = bobbing(U.model(lagoon, "Drifting"), 0.2, 3.1 + 0.2 * (i % 3))
				local cf = CFrame.new(p.X, 0.15, p.Z) * CFrame.Angles(0, rad(a + 25), rad(5))
				local first
				if i % 2 == 0 then
					first =
						U.part(m, "Crate", Vector3.new(2.2, 1.4, 2.2), cf, lerp(C.WoodLight, C.Wood, 0.3), nil, DECOR)
					U.part(
						m,
						"CrateBand",
						Vector3.new(2.3, 0.3, 0.3),
						cf * CFrame.new(0, 0.3, 0),
						C.WoodDark,
						nil,
						DECOR
					)
				else
					first = U.part(
						m,
						"Barrel",
						Vector3.new(2.6, 1.6, 1.6),
						cf * CFrame.Angles(0, rad(90), 0),
						C.Wood,
						nil,
						CYL
					)
					U.part(
						m,
						"BarrelHoop",
						Vector3.new(0.3, 1.7, 1.7),
						cf * CFrame.Angles(0, rad(90), 0),
						C.Iron,
						nil,
						CYL
					)
				end
				m.PrimaryPart = first
				break
			end
		end
		-- a lily cluster in the shallows beside the pier steps (on the side away from the boat)
		for _, try in { { -9.5, 289 }, { -11, 287 }, { -8, 290 } } do
			local a = base + try[1]
			local p = U.polar(a, try[2], 0)
			if openWater(p.X, p.Z, 2.5) and not nearPierOrBridge(cfg, world, p.X, p.Z, -8) then
				local m = bobbing(U.model(lagoon, "Lilies"), 0.06, 4.2)
				local cf = CFrame.new(p.X, 0, p.Z) * CFrame.Angles(0, rad(a), 0)
				local first = U.part(
					m,
					"Lily",
					Vector3.new(0.15, 2.4, 2.4),
					cf * CFrame.new(0, 0.08, 0) * CFrame.Angles(0, 0, rad(90)),
					C.Leaf1,
					nil,
					CYL
				)
				U.part(
					m,
					"Lily",
					Vector3.new(0.15, 1.8, 1.8),
					cf * CFrame.new(2.0, 0.1, 1.3) * CFrame.Angles(0, 0, rad(90)),
					C.Leaf2,
					nil,
					CYL
				)
				U.part(
					m,
					"Lily",
					Vector3.new(0.15, 1.4, 1.4),
					cf * CFrame.new(-1.2, 0.12, 2.0) * CFrame.Angles(0, 0, rad(90)),
					C.Leaf3,
					nil,
					CYL
				)
				U.part(
					m,
					"LilyBloom",
					Vector3.new(0.7, 0.5, 0.7),
					cf * CFrame.new(0.1, 0.4, 0.1),
					C.Flowers[if i % 2 == 0 then 3 else 5],
					nil,
					DECOR
				)
				m.PrimaryPart = first
				break
			end
		end
		-- kelp on the sandy slope (bed -6), either side of the fishing water: dark shapes under the
		-- surface, swaying slowly from the bed
		for j, spec in { { -40, -36 }, { 46, -44 }, { -58, -52 } } do
			local x, z = at(i, spec[1] + (i % 3) * 2, spec[2] - (i % 2) * 4)
			local bed = world:heightAt(x, z)
			if bed <= -6 and bed >= -8 and openWater(x, z, 2) then
				local m = U.model(under, "Kelp")
				local cf = CFrame.new(x, bed, z) * CFrame.Angles(0, rad(base + j * 40), 0)
				local h1, h2 = 3.6 + (j % 2) * 0.4, 2.6
				local first =
					U.part(m, "Kelp", Vector3.new(0.5, h1, 0.5), cf * CFrame.new(0, h1 / 2, 0), KELP[1], nil, DECOR)
				U.part(m, "Kelp", Vector3.new(0.5, h2, 0.5), cf * CFrame.new(0.8, h2 / 2, 0.5), KELP[2], nil, DECOR)
				U.part(
					m,
					"KelpLeaf",
					Vector3.new(1.4, 0.6, 0.3),
					cf * CFrame.new(0.4, h1 - 0.9, 0),
					KELP[1],
					nil,
					DECOR
				)
				m.PrimaryPart = first
				first.PivotOffset = first.CFrame:Inverse() * cf
				m:SetAttribute("Sway", 6)
				m:SetAttribute("SwayAxis", "X")
				m:SetAttribute("SwayPeriod", 4.5 + j * 0.4)
			end
		end
		-- a sunken chest on the slope between this pier and the next (kids find it)
		for _, try in { { 18, 280 }, { 20, 276 }, { 16, 284 }, { 22, 272 } } do
			local a = base + (if i % 2 == 0 then 1 else -1) * try[1]
			local p = U.polar(a, try[2], 0)
			local bed = world:heightAt(p.X, p.Z)
			if bed <= -6 and openWater(p.X, p.Z, 3) and not nearPierOrBridge(cfg, world, p.X, p.Z, 2) then
				local b = Kit.builder(
					under,
					"SunkenChest",
					CFrame.new(p.X, bed, p.Z) * CFrame.Angles(rad(4), rad(a + 30), rad(-6))
				)
				local body = b:box("Chest", -1.5, -0.3, -1.0, 1.5, 1.4, 1.0, C.WoodDark, DECOR)
				b:box("ChestLid", -1.55, 1.4, -1.05, 1.55, 2.0, 1.05, lerp(C.WoodDark, C.Seaweed, 0.3), DECOR)
				b:box("ChestBand", -0.25, -0.3, -1.1, 0.25, 2.05, 1.1, C.Gold, DECOR)
				b:box("Coins", 1.6, -0.3, -0.6, 2.6, 0.2, 0.6, C.GoldLight, DECOR)
				b:finish(body)
				break
			end
		end
	end
	return U.partCount - before
end

--------------------------------------------------------------------------------------------

function Shore.build(map: any, cfg: any, world: any): { [string]: number }
	local shore = U.model(map, "Shore")
	local blocked = Kit.obstacles(map).blocked
	local foam = buildFoam(shore, cfg, world, blocked)
	local beach = buildBeach(shore, cfg, world, blocked)
	local lagoon = buildLagoon(shore, cfg, world, blocked)
	for _, d in shore:GetDescendants() do
		if d:IsA("BasePart") then
			d.Locked = true
			d.CanTouch = false
		end
	end
	return { foam = foam, beach = beach, lagoon = lagoon }
end

-- (exposed for the tests)
Shore.inCastZone = inCastZone

return Shore
