-- Bakes the world, prints stats, checks encode→decode→encode is identical, dumps blobs.
-- Usage: lune run tools/terrain/selftest.luau [outDir]
local OUT = require("@lune/process").args[1] or "."
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Bake = require("./Bake")
local SmoothGrid = require("./SmoothGrid")
local cfg = luau.load(
	fs.readFile("src/ReplicatedStorage/Shared/Config/MapConfig.luau"),
	{ environment = {}, injectGlobals = true }
)()
local res = Bake.run(cfg)
print(
	string.format(
		"heightfield %.2fs voxels %.2fs encode %.2fs",
		res.timing.heightfield,
		res.timing.voxels,
		res.timing.encode
	)
)
print("SmoothGrid bytes", #res.smoothGrid, "PhysicsGrid bytes", #res.physicsGrid)
local stats = res.grid:stats()
local total = 0
for k, v in stats do
	total += v
	print(k, v)
end
print("total voxels", total)
local t = os.clock()
local back = SmoothGrid.decode(res.smoothGrid)
local stats2 = back:stats()
for k, v in stats do
	assert(stats2[k] == v, "mismatch " .. k)
end
print("decode roundtrip ok", os.clock() - t)
assert(back:encode() == res.smoothGrid, "re-encode not identical")
print("re-encode identical")
fs.writeFile(OUT .. "/smoothgrid.bin", res.smoothGrid)
fs.writeFile(OUT .. "/physicsgrid.bin", res.physicsGrid)
-- heightmap image data for a quick look: write a PGM-like grid of surface heights + materials
local gen = res.gen
local lines = {}
for iz = -gen.n, gen.n - 1, 2 do
	local row = {}
	for ix = -gen.n, gen.n - 1, 2 do
		local h, mat, water = gen:surfaceAt(ix * 4 + 2, iz * 4 + 2)
		table.insert(row, string.format("%.1f:%s:%s", h, mat, water and "1" or "0"))
	end
	table.insert(lines, table.concat(row, " "))
end
fs.writeFile(OUT .. "/heightmap.txt", table.concat(lines, "\n"))
