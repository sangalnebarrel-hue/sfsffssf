--[[
	VoxelWorld (World v3 ground) invariants the game relies on — pure Lune, no sim:
	flat dry plots, promenade, hub plaza and gateway plazas; water under the piers and bridges;
	landmarks; everything important reachable on foot/swimming from the hub; part budget;
	deterministic output; lossless Terrain water encoding.

	Run: lune run tools/run_tests.luau voxelworld
]]

local roblox = require("@lune/roblox")

local U = require("../tools/builder/Util")
local VoxelWorld = require("../tools/builder/VoxelWorld")
local buildGround = require("../tools/builder/Ground")
local SmoothGrid = require("../tools/terrain/SmoothGrid")

local cfg = U.loadPure("src/ReplicatedStorage/Shared/Config/MapConfig.luau")
local world = VoxelWorld.new(cfg)

local function polar(angle: number, r: number): (number, number)
	local a = math.rad(angle)
	return r * math.sin(a), r * math.cos(a)
end

-- World point at base-local (lx, lz) of base i: lz grows inland, lx sideways.
local function baseLocal(i: number, lx: number, lz: number): (number, number)
	local a = math.rad(cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount)
	local ux, uz = math.sin(a), math.cos(a)
	local px, pz = math.cos(a), -math.sin(a)
	return cfg.BaseRadius * ux + lz * ux + lx * px, cfg.BaseRadius * uz + lz * uz + lx * pz
end

local tests = {}

tests["plots are flat dry ground at GroundTop (with margin)"] = function(t)
	local half = cfg.PlotHalfWidth + cfg.PlotMargin - 4
	for i = 1, cfg.BaseCount do
		for lz = cfg.PlotFront - cfg.PlotMargin + 4, cfg.PlotFront + cfg.PlotDepth + cfg.PlotMargin - 4, 6 do
			for lx = -half, half, 6 do
				local x, z = baseLocal(i, lx, lz)
				local h, kind, water = world:surfaceAt(x, z)
				if h ~= cfg.GroundTop or water ~= nil then
					t.eq(h, cfg.GroundTop, `base {i} plot height at ({lx}, {lz}) [{kind}]`)
					return
				end
			end
		end
	end
	t.ok(true)
end

tests["promenade ring is flat and dry all the way round"] = function(t)
	for a = 0, 359.5, 0.5 do
		for _, r in
			{
				cfg.PromenadeRadius + 3,
				cfg.PromenadeRadius + cfg.PromenadeWidth / 2,
				cfg.PromenadeRadius + cfg.PromenadeWidth - 3,
			}
		do
			local x, z = polar(a, r)
			local h = world:heightAt(x, z)
			if h ~= cfg.GroundTop then
				t.eq(h, cfg.GroundTop, `promenade at {a}° r={r}`)
				return
			end
		end
	end
	t.ok(true)
end

tests["hub plaza is flat; beaches at y = 2 around hub and lagoon"] = function(t)
	for a = 0, 355, 5 do
		for r = 0, cfg.HubPlazaRadius - 6, 10 do
			local x, z = polar(a, r)
			t.eq(world:heightAt(x, z), cfg.GroundTop, `hub plaza at {a}° r={r}`)
		end
		local x, z = polar(a, (cfg.HubPlazaRadius + cfg.HubRadius) / 2)
		t.eq(world:heightAt(x, z), 2, `hub beach at {a}°`)
		-- between the lagoon and the promenade there is always a sand step (water → 2 → 4)
		local beach = false
		for r = cfg.LagoonRadius - 6, cfg.PromenadeRadius, 1 do
			x, z = polar(a, r)
			beach = beach or world:heightAt(x, z) == 2
		end
		t.ok(beach, `ring beach at {a}°`)
	end
end

tests["water under every pier and its end platform"] = function(t)
	for i = 1, cfg.BaseCount do
		for _, lz in { -24, -40, -70, -92 } do
			for _, lx in { -cfg.PierHalfWidth, 0, cfg.PierHalfWidth } do
				local x, z = baseLocal(i, lx, lz)
				local h, _, water = world:surfaceAt(x, z)
				t.eq(water, cfg.WaterTop, `base {i}: water at ({lx}, {lz})`)
				t.ok(h <= cfg.WaterTop - 2, `base {i}: depth at ({lx}, {lz}) is {h}`)
			end
		end
	end
end

tests["bridges span water between the hub plaza and the promenade"] = function(t)
	for _, angle in cfg.BridgeAngles do
		local x, z = polar(angle, cfg.HubPlazaRadius - 8)
		t.eq(world:heightAt(x, z), cfg.GroundTop, `bridge {angle}: hub end`)
		x, z = polar(angle, cfg.PromenadeRadius + 4)
		t.eq(world:heightAt(x, z), cfg.GroundTop, `bridge {angle}: promenade end`)
		for r = cfg.HubRadius + 4, cfg.LagoonRadius - 4, 12 do
			x, z = polar(angle, r)
			t.ok(world:isWater(x, z), `bridge {angle}: water at r={r}`)
		end
		local g = world.gateways[table.find(cfg.BridgeAngles, angle) :: number]
		for _, d in { { 0, 0 }, { 24, 0 }, { -24, 0 }, { 0, 24 }, { 0, -24 } } do
			t.eq(world:heightAt(g.x + d[1], g.z + d[2]), cfg.GroundTop, `gateway {angle} flat`)
		end
	end
end

tests["landmarks: pond with water, mesa, windmill hill, snowy peak"] = function(t)
	local fall = world.landmarks.Waterfall
	t.ok(world:isWater(fall.pondX, fall.pondZ), "waterfall pond has water")
	local mx, mz = polar(fall.angle, fall.radius + 40)
	t.eq(world:heightAt(mx, mz), fall.cliffTop, "mesa top")
	local mill = world.landmarks.Windmill
	t.eq(world:heightAt(mill.x, mill.z), mill.top, "windmill hill top")
	local peak = world.landmarks.Peak
	local _, hi = world:heightRange()
	t.ok(hi >= 100, `peak height {hi}`)
	t.eq(world:kindAt(peak.x, peak.z), "snow", "peak is snowy")
	local tree = world.landmarks.GiantTree
	t.eq(world:heightAt(tree.x, tree.z), tree.top, "giant tree plateau")
end

tests["everything important is reachable from the hub (walk, jump 4, swim)"] = function(t)
	local n, size = world.n, world.size
	local seen = buffer.create(size * size)
	local function idx(ix: number, iz: number): number
		return (iz + n) * size + (ix + n)
	end
	local function surface(ix: number, iz: number): (number, boolean)
		local top = world:topAtCell(ix, iz)
		if top < cfg.WaterTop then
			return cfg.WaterTop, true
		end
		return top, false
	end
	local qx, qz = { 0 }, { 0 }
	buffer.writeu8(seen, idx(0, 0), 1)
	local head = 1
	local limit = cfg.BoundaryRadius - 8
	while head <= #qx do
		local cx, cz = qx[head], qz[head]
		head += 1
		local h = surface(cx, cz)
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local nx, nz = cx + d[1], cz + d[2]
			if nx >= -n and nx < n and nz >= -n and nz < n and buffer.readu8(seen, idx(nx, nz)) == 0 then
				local px, pz = (nx + 0.5) * world.cell, (nz + 0.5) * world.cell
				if math.sqrt(px * px + pz * pz) < limit then
					local h2 = surface(nx, nz)
					if h2 - h <= 4 then
						buffer.writeu8(seen, idx(nx, nz), 1)
						table.insert(qx, nx)
						table.insert(qz, nz)
					end
				end
			end
		end
	end
	local function reachable(x: number, z: number): boolean
		local ix, iz = world:cellOf(x, z)
		return buffer.readu8(seen, idx(ix, iz)) == 1
	end
	for i = 1, cfg.BaseCount do
		for _, p in
			{ { 0, cfg.PlotFront + 10 }, { 0, cfg.PlotFront + cfg.PlotDepth - 10 }, { 60, 90 }, { -60, 90 }, { 0, -60 } }
		do
			local x, z = baseLocal(i, p[1], p[2])
			t.ok(reachable(x, z), `base {i} point ({p[1]}, {p[2]}) reachable`)
		end
	end
	for _, g in world.gateways do
		t.ok(reachable(g.x, g.z), `gateway {g.angle} reachable`)
	end
	local mill = world.landmarks.Windmill
	t.ok(reachable(mill.x, mill.z), "windmill hill top reachable by its terraces")
	t.ok(reachable(world.landmarks.GiantTree.x, world.landmarks.GiantTree.z), "giant tree plateau reachable")
	local fall = world.landmarks.Waterfall
	t.ok(reachable(fall.pondX, fall.pondZ), "waterfall pond reachable")
end

tests["ground part budget"] = function(t)
	local game = roblox.Instance.new("DataModel")
	local map = U.new("Model", { Name = "Map" }, game:GetService("Workspace"))
	local res = buildGround(map, world)
	t.ok(res.parts <= 5200, `ground parts {res.parts} <= 5200`)
	for _, part in res.model:GetDescendants() do
		if part:IsA("BasePart") then
			local s = part.Size
			if s.X > 2048 or s.Y > 2048 or s.Z > 2048 or not part.Anchored or not part.Locked then
				t.ok(false, `bad ground part {part.Name} size {s}`)
				return
			end
		end
	end
end

tests["deterministic: two builds give identical columns"] = function(t)
	local other = VoxelWorld.new(cfg)
	t.ok(buffer.tostring(other.top) == buffer.tostring(world.top), "same heights")
	t.ok(buffer.tostring(other.kind) == buffer.tostring(world.kind), "same kinds")
end

tests["Terrain water: lossless round trip, water only"] = function(t)
	local grid = world:bakeWater(SmoothGrid)
	local bytes = grid:encode()
	local back = SmoothGrid.decode(bytes)
	t.ok(back:encode() == bytes, "encode → decode → encode is identical")
	local stats = back:stats()
	for name, count in stats do
		t.ok(name == "Water" or count == 0, `only water voxels ({name} = {count})`)
	end
	-- the water surface is at WaterTop in the middle of the lagoon
	local x, z = polar(10, (cfg.HubRadius + cfg.LagoonRadius) / 2)
	local slot = back:get(math.floor(x / 4), cfg.WaterTop // 4 - 1, math.floor(z / 4))
	t.eq(slot, SmoothGrid.Slots.Water, "lagoon voxel below the surface is water")
	local above = back:get(math.floor(x / 4), cfg.WaterTop // 4, math.floor(z / 4))
	t.eq(above, SmoothGrid.Slots.Air, "voxel above the surface is air")
end

return tests
