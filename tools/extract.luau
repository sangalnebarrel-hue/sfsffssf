--[[
	Extracts every Script / LocalScript / ModuleScript from a place into files, mirroring the
	DataModel path with the same naming as src/ (.server.luau / .client.luau / .luau).

	Usage: lune run tools/extract.luau <place.rbxl> <outDir>

	Used to pull edits made directly in Roblox Studio back into src/:
	extract the edited place into a temp dir, then diff it against src/.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local placePath = process.args[1]
local outDir = process.args[2]
assert(placePath and outDir, "usage: lune run tools/extract.luau <place.rbxl> <outDir>")

local game = roblox.deserializePlace(fs.readFile(placePath))

local SERVICES = {
	"Workspace",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
}

local SUFFIX = {
	Script = ".server.luau",
	LocalScript = ".client.luau",
	ModuleScript = ".luau",
}

local count = 0

local function walk(inst: any, dir: string)
	for _, child in inst:GetChildren() do
		local suffix = SUFFIX[child.ClassName]
		if suffix then
			fs.writeDir(dir)
			fs.writeFile(`{dir}/{child.Name}{suffix}`, child.Source)
			count += 1
			if #child:GetChildren() > 0 then
				warn(`{child:GetFullName()} has children; they are extracted into a sibling folder`)
				walk(child, `{dir}/{child.Name}`)
			end
		else
			walk(child, `{dir}/{child.Name}`)
		end
	end
end

for _, name in SERVICES do
	local service = game:FindFirstChildOfClass(name)
	if service then
		walk(service, `{outDir}/{name}`)
	end
end

print(`extracted {count} scripts into {outDir}`)
