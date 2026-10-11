--[[
	Bakes the procedural world (src/ServerStorage/WorldGen.luau) into smooth-terrain voxels.
	Returns { smoothGrid = string, physicsGrid = string, gen = WorldGen, grid = SmoothGrid, stats }.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local SmoothGrid = require("./SmoothGrid")

local Bake = {}

-- Loads a pure ModuleScript source (no Roblox globals needed).
local function loadModule(path: string): any
	return luau.load(fs.readFile(path), { debugName = path, injectGlobals = true })()
end

function Bake.run(cfg: any): any
	local WorldGen = loadModule("src/ServerStorage/WorldGen.luau")
	local t0 = os.clock()
	local gen = WorldGen.new(cfg)
	gen:build()
	local t1 = os.clock()

	local grid = SmoothGrid.new()
	local slots = SmoothGrid.Slots
	local n = gen.n
	for iz = -n, n - 1 do
		for ix = -n, n - 1 do
			gen:fillColumn(ix, iz, function(iy, material, occupancy)
				local slot = slots[material]
				assert(slot, `unknown terrain material {material}`)
				grid:set(ix, iy, iz, slot, occupancy)
			end)
		end
	end
	local t2 = os.clock()
	local smooth = grid:encode()
	local physics = grid:encodePhysics()
	local t3 = os.clock()
	return {
		smoothGrid = smooth,
		physicsGrid = physics,
		gen = gen,
		grid = grid,
		timing = { heightfield = t1 - t0, voxels = t2 - t1, encode = t3 - t2 },
	}
end

return Bake
