-- Bakes the world's Terrain water, prints stats, checks encode→decode→encode is identical,
-- dumps the blobs (for tools/terrain_check and the preview renderer).
-- Usage: lune run tools/terrain/selftest.luau [outDir]
local OUT = require("@lune/process").args[1] or "."
local fs = require("@lune/fs")
local U = require("../builder/Util")
local VoxelWorld = require("../builder/VoxelWorld")
local SmoothGrid = require("./SmoothGrid")

local cfg = U.loadPure("src/ReplicatedStorage/Shared/Config/MapConfig.luau")
local t0 = os.clock()
local world = VoxelWorld.new(cfg)
local t1 = os.clock()
local grid = world:bakeWater(SmoothGrid)
local smooth, physics = grid:encode(), grid:encodePhysics()
local t2 = os.clock()
print(string.format("heightfield %.2fs water %.2fs", t1 - t0, t2 - t1))
print("SmoothGrid bytes", #smooth, "PhysicsGrid bytes", #physics)
local stats = grid:stats()
for k, v in stats do
	print(k, v)
end
local back = SmoothGrid.decode(smooth)
local stats2 = back:stats()
for k, v in stats do
	assert(stats2[k] == v, "mismatch " .. k)
end
print("decode roundtrip ok")
assert(back:encode() == smooth, "re-encode not identical")
print("re-encode identical")
fs.writeFile(OUT .. "/smoothgrid.bin", smooth)
fs.writeFile(OUT .. "/physicsgrid.bin", physics)
