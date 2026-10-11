--[[
	WorldGen invariants the game relies on (pure Lune, no sim):
	flat base terraces, water under the piers, flat cobbled plaza, water under the bridges,
	rivers connected to the lake, the upper rivers at their own level, and a lossless
	SmoothGrid encode → decode → encode round trip.

	Run: lune run tools/run_tests.luau worldgen
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local SmoothGrid = require("../tools/terrain/SmoothGrid")

local function load(path: string): any
	return luau.load(fs.readFile(path), { debugName = path, injectGlobals = true })()
end

local cfg = load("src/ReplicatedStorage/Shared/Config/MapConfig.luau")
local WorldGen = load("src/ServerStorage/WorldGen.luau")

local gen = WorldGen.new(cfg)
gen:build()

local function polar(angle: number, r: number): (number, number)
	local a = math.rad(angle)
	return r * math.sin(a), r * math.cos(a)
end

-- World point at base-local (lx, lz): lz grows inland, lx sideways.
local function baseLocal(angle: number, lx: number, lz: number): (number, number)
	local a = math.rad(angle)
	local ux, uz = math.sin(a), math.cos(a)
	local px, pz = math.cos(a), -math.sin(a)
	return cfg.BaseRadius * ux + lz * ux + lx * px, cfg.BaseRadius * uz + lz * uz + lx * pz
end

local tests = {}

tests["base terraces are flat at GroundTop"] = function(t)
	for i = 1, cfg.BaseCount do
		local angle = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		for _, lz in { 2, 20, 45, 70, 80 } do
			for _, lx in { -38, -20, 0, 20, 38 } do
				local x, z = baseLocal(angle, lx, lz)
				local h, _, water = gen:surfaceAt(x, z)
				t.near(h, cfg.GroundTop, 0.35, `base {i} terrace at ({lx}, {lz})`)
				t.ok(water == nil, `base {i} terrace is dry at ({lx}, {lz})`)
			end
		end
	end
end

tests["the lake in front of every base is water deep enough for a pier"] = function(t)
	for i = 1, cfg.BaseCount do
		local angle = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		for _, lz in { -16, -30, -45, -60 } do
			local x, z = baseLocal(angle, 0, lz)
			local h, _, water = gen:surfaceAt(x, z)
			t.eq(water, cfg.WaterTop, `base {i}: water at lz={lz}`)
			t.ok(h < cfg.WaterTop - 2, `base {i}: lake bed below water at lz={lz} (h={h})`)
		end
	end
end

tests["hub plaza is flat cobblestone at GroundTop"] = function(t)
	for _, p in { { 0, 0 }, { 20, 10 }, { -30, -15 }, { 10, -38 } } do
		local h, material = gen:surfaceAt(p[1], p[2])
		t.near(h, cfg.GroundTop, 0.35, `plaza height at {p[1]},{p[2]}`)
		t.eq(material, "Cobblestone", `plaza material at {p[1]},{p[2]}`)
	end
end

tests["bridges span water between the island and the shore"] = function(t)
	for _, angle in cfg.BridgeAngles do
		for _, r in { 80, 120, 160, 200 } do
			local x, z = polar(angle, r)
			local _, _, water = gen:surfaceAt(x, z)
			t.eq(water, cfg.WaterTop, `water under bridge {angle} at r={r}`)
		end
		-- Landing on the shore is at terrace height.
		local x, z = polar(angle, cfg.LakeRadius + 6)
		t.near((gen:surfaceAt(x, z)), cfg.GroundTop, 0.6, `bridge {angle} landing`)
	end
end

tests["rivers connect the lake with the waterfall pools; upper rivers run at their own level"] = function(t)
	for _, angle in cfg.Rivers do
		for _, r in { cfg.LakeRadius + 30, cfg.RingRoadRadius - 20, cfg.ValleyRadius } do
			local a = angle + 3.5 * math.sin((r - cfg.LakeRadius) / 38)
			local x, z = polar(a, r)
			local _, _, water = gen:surfaceAt(x, z)
			t.eq(water, cfg.WaterTop, `river {angle} water at r={r}`)
		end
		local r = cfg.ValleyRadius + 60
		local a = angle + 3.5 * math.sin((r - cfg.LakeRadius) / 38)
		local x, z = polar(a, r)
		local _, _, water = gen:surfaceAt(x, z)
		t.eq(water, WorldGen.UpperRiverWater, `upper river {angle} water level`)
	end
end

tests["ring road is walkable: gentle and dry"] = function(t)
	local previous = nil
	for k = 0, 359, 3 do
		local x, z = polar(k, cfg.RingRoadRadius)
		local h, _, water = gen:surfaceAt(x, z)
		local nearRiver = false
		for _, river in cfg.Rivers do
			if math.abs(((k - river + 180) % 360) - 180) < 10 then
				nearRiver = true
			end
		end
		if not nearRiver then
			t.ok(water == nil, `road dry at {k}°`)
			if previous then
				t.ok(math.abs(h - previous) < 3, `road smooth at {k}° ({previous} → {h})`)
			end
			previous = h
		else
			previous = nil
		end
	end
end

tests["mountains enclose the valley above the boundary wall"] = function(t)
	for k = 0, 359, 15 do
		local canyon = false -- the upper rivers cut canyons through the mountains
		for _, river in cfg.Rivers do
			if math.abs(((k - river + 180) % 360) - 180) < 6 then
				canyon = true
			end
		end
		if not canyon then
			local x, z = polar(k, cfg.BoundaryRadius + 20)
			local h = gen:surfaceAt(x, z)
			t.ok(h > 60, `mountain at {k}° is high (h={h})`)
		end
	end
end

tests["SmoothGrid encode → decode → encode is lossless"] = function(t)
	local grid = SmoothGrid.new()
	for iz = -24, 23 do
		for ix = -24, 23 do
			gen:fillColumn(ix, iz, function(iy, material, occupancy)
				grid:set(ix, iy, iz, SmoothGrid.Slots[material], occupancy)
			end)
		end
	end
	local bytes = grid:encode()
	local back = SmoothGrid.decode(bytes)
	t.eq(back:encode(), bytes, "re-encode identical")
	local a, b = grid:stats(), back:stats()
	for name, count in a do
		t.eq(b[name], count, `voxel count {name}`)
	end
	local physics = grid:encodePhysics()
	t.eq(string.byte(physics, 1), 2, "PhysicsGrid version")
	t.eq(string.byte(physics, 2), 3, "PhysicsGrid region size")
end

return tests
