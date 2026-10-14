--[[
	Every game script compiles in Roblox's Luau with room to grow: a function (and a whole module
	is one function) can hold at most 200 live locals and temporaries — over that the script fails
	to load at all ("Out of local registers"), in Studio and on a phone alike. RbxSim runs the same
	compiler, so the other tests would break too, but only with a cryptic load error; this test
	names the file and keeps a margin of SPARE_MIN registers so the next feature does not hit the wall.

	How the margin is measured: extra non-constant top-level locals are added after the file's first
	local until it stops compiling.

	Run: lune run tools/run_tests.luau compile_limits
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local SPARE_MIN = 24 -- registers a module must keep free at its top level
local LIMIT = 200 -- Luau's cap; above it nothing more can be measured

local function sources(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			sources(path, out)
		elseif string.match(name, "%.luau$") then
			table.insert(out, path)
		end
	end
end

local function compiles(source: string): (boolean, string?)
	local ok, err = pcall(luau.compile, source)
	return ok, if ok then nil else tostring(err)
end

-- How many more top-level locals the module takes (0 if it does not compile).
local function spareRegisters(source: string): number
	if not compiles(source) then
		return 0
	end
	local cut = string.find(source, "\nlocal ", 1, true) or 1
	local head, tail = string.sub(source, 1, cut), string.sub(source, cut + 1)
	local low, high = 0, LIMIT
	while low < high do
		local n = (low + high + 1) // 2
		if compiles(head .. string.rep("local _spare = os.clock()\n", n) .. tail) then
			low = n
		else
			high = n - 1
		end
	end
	return low
end

local tests = {}

tests["every game script compiles"] = function(t)
	local files = {}
	sources("src", files)
	t.ok(#files > 10, `found {#files} scripts`)
	for _, path in files do
		local ok, err = compiles(fs.readFile(path))
		t.ok(ok, `{path} compiles{if err then ": " .. err else ""}`)
	end
end

tests["every game script keeps spare local registers"] = function(t)
	local files = {}
	sources("src", files)
	for _, path in files do
		local spare = spareRegisters(fs.readFile(path))
		t.ok(spare >= SPARE_MIN, `{path}: {spare} spare registers (need ≥ {SPARE_MIN})`)
	end
end

return tests
