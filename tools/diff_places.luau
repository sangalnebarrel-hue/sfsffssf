--[[
	Compares two places and lists what changed: added/removed instances, changed properties
	(position, size, colour, material, transparency, text, ...), attributes and script sources.

	Usage: lune run tools/diff_places.luau <old.rbxl> <new.rbxl>

	Used before every stage: diff the Place1.rbxl we shipped against the one the user edited
	in Studio, then port those edits into src/ and tools/builder/ so the next build keeps them.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local oldPath, newPath = process.args[1], process.args[2]
assert(oldPath and newPath, "usage: lune run tools/diff_places.luau <old.rbxl> <new.rbxl>")

local SERVICES = {
	"Workspace",
	"Lighting",
	"Players",
	"ReplicatedFirst",
	"ReplicatedStorage",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"SoundService",
}

-- Properties worth comparing (missing ones are skipped per class).
local PROPS = {
	"CFrame",
	"Size",
	"Color",
	"Material",
	"Transparency",
	"Reflectance",
	"CanCollide",
	"CanQuery",
	"CanTouch",
	"Anchored",
	"CastShadow",
	"Shape",
	"Text",
	"TextColor3",
	"BackgroundColor3",
	"BackgroundTransparency",
	"Position",
	"Visible",
	"Enabled",
	"Neutral",
	"Duration",
	"HoldDuration",
	"MaxActivationDistance",
	"Source",
	"Value",
	"Brightness",
	"TimeOfDay",
	"ClockTime",
	"CharacterAutoLoads",
	"StreamingEnabled",
	"ScreenOrientation",
}

local function read(inst: any, prop: string): (boolean, any)
	return pcall(function()
		return inst[prop]
	end)
end

local function fmt(v: any): string
	local text = tostring(v)
	if #text > 120 then
		return string.sub(text, 1, 117) .. "..."
	end
	return text
end

local function equal(a: any, b: any): boolean
	if typeof(a) == "CFrame" and typeof(b) == "CFrame" then
		-- Component-wise with tolerance (rotations are stored as float32, not exactly orthonormal).
		local ca, cb = { a:GetComponents() }, { b:GetComponents() }
		for i = 1, 12 do
			if math.abs(ca[i] - cb[i]) > 1e-3 then
				return false
			end
		end
		return true
	end
	return a == b
end

-- Children keyed by name; duplicate names get #2, #3 ... suffixes in order.
local function childMap(inst: any): ({ [string]: any }, { string })
	local map, order, seen = {}, {}, {}
	for _, child in inst:GetChildren() do
		local key = child.Name
		seen[key] = (seen[key] or 0) + 1
		if seen[key] > 1 then
			key = `{key}#{seen[key]}`
		end
		map[key] = child
		table.insert(order, key)
	end
	return map, order
end

local changes = 0
local function out(line: string)
	changes += 1
	print(line)
end

local function compare(a: any, b: any, path: string)
	if a.ClassName ~= b.ClassName then
		out(`~ {path}: class {a.ClassName} → {b.ClassName}`)
		return
	end
	for _, prop in PROPS do
		local okA, va = read(a, prop)
		local okB, vb = read(b, prop)
		if okA and okB and not equal(va, vb) then
			if prop == "Source" then
				out(`~ {path}.Source changed (extract both places with tools/extract.luau and diff)`)
			else
				out(`~ {path}.{prop}: {fmt(va)} → {fmt(vb)}`)
			end
		end
	end
	local attrsA, attrsB = a:GetAttributes(), b:GetAttributes()
	for name, value in attrsA do
		if not equal(value, attrsB[name]) then
			out(`~ {path}@{name}: {fmt(value)} → {fmt(attrsB[name])}`)
		end
	end
	for name, value in attrsB do
		if attrsA[name] == nil then
			out(`+ {path}@{name} = {fmt(value)}`)
		end
	end

	local mapA, orderA = childMap(a)
	local mapB, orderB = childMap(b)
	for _, key in orderA do
		local childPath = `{path}.{key}`
		if mapB[key] then
			compare(mapA[key], mapB[key], childPath)
		else
			out(`- {childPath} ({mapA[key].ClassName}) removed`)
		end
	end
	for _, key in orderB do
		if not mapA[key] then
			out(`+ {path}.{key} ({mapB[key].ClassName}) added, {#mapB[key]:GetDescendants()} descendants`)
		end
	end
end

local oldGame = roblox.deserializePlace(fs.readFile(oldPath))
local newGame = roblox.deserializePlace(fs.readFile(newPath))
for _, name in SERVICES do
	local a, b = oldGame:FindFirstChildOfClass(name), newGame:FindFirstChildOfClass(name)
	if a and b then
		compare(a, b, name)
	elseif a or b then
		out(`? service {name} present in only one place`)
	end
end
print(`{changes} difference(s)`)
