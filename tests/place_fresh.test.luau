--[[
	Place1.rbxl is generated (tools/build.luau copies every script from src/ into it), and it is
	the file that is handed over and opened in Studio. A source change without a rebuild ships
	the OLD game: in v3 the fix «ВЗЯТЬ» anywhere was in src/ while the delivered place still had
	the old FishingController — the player again saw nothing but «ДОМОЙ». The other tests run
	against the built place too, so they would test the old code as well; this one says plainly
	which script is stale.

	Run: lune run tools/run_tests.luau place_fresh
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local PLACE = "Place1.rbxl"
local SRC = "src"

-- The same naming as tools/builder/Scripts.luau.
local function classify(fileName: string): (string?, string?)
	local name = string.match(fileName, "^(.+)%.server%.luau$")
	if name then
		return "Script", name
	end
	name = string.match(fileName, "^(.+)%.client%.luau$")
	if name then
		return "LocalScript", name
	end
	name = string.match(fileName, "^(.+)%.luau$")
	if name then
		return "ModuleScript", name
	end
	return nil, nil
end

type Entry = { path: string, className: string, chain: { string } }

local function collect(dir: string, chain: { string }, out: { Entry })
	local entries = fs.readDir(dir)
	table.sort(entries)
	for _, entry in entries do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			local next = table.clone(chain)
			table.insert(next, entry)
			collect(path, next, out)
		else
			local className, name = classify(entry)
			if className and name then
				local full = table.clone(chain)
				table.insert(full, name)
				table.insert(out, { path = path, className = className, chain = full })
			end
		end
	end
end

local tests = {}

tests["Place1.rbxl carries the current src/ scripts (stale → run tools/build.luau)"] = function(t)
	local game = roblox.deserializePlace(fs.readFile(PLACE))
	local entries: { Entry } = {}
	collect(SRC, {}, entries)
	t.ok(#entries > 20, `found {#entries} scripts in src/`)
	local stale = {}
	for _, entry in entries do
		local node: any = game:GetService(entry.chain[1])
		for i = 2, #entry.chain do
			node = node and node:FindFirstChild(entry.chain[i])
		end
		if not node then
			table.insert(stale, `{entry.path}: missing in {PLACE}`)
		elseif node.ClassName ~= entry.className then
			table.insert(stale, `{entry.path}: {node.ClassName} in {PLACE}, expected {entry.className}`)
		elseif node.Source ~= fs.readFile(entry.path) then
			table.insert(stale, `{entry.path}: differs`)
		end
	end
	t.eq(
		#stale,
		0,
		`{PLACE} is stale, run tools/build.luau (and hand over the rebuilt place):\n  {table.concat(stale, "\n  ")}`
	)
end

return tests
