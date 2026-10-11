--!strict
--[[
	export_terrain.luau (Lune 0.11): writes the raw Terrain blobs of a place to files,
	for tools/preview/terrain_export.py (heightfield for render.py --terrain) and
	tools/terrain_check (terrain_check --raw ...).

	lune run tools/preview/export_terrain.luau <place.rbxl> <smoothgrid.bin> [<physicsgrid.bin>]

	A place whose Terrain was never edited stores SmoothGrid = 01 05 (empty grid).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local args = process.args
if #args < 2 or #args > 3 then
	print("usage: lune run tools/preview/export_terrain.luau <place.rbxl> <smoothgrid.bin> [<physicsgrid.bin>]")
	process.exit(2)
end

local game = roblox.deserializePlace(fs.readFile(args[1]))
local terrain = game:GetService("Workspace"):FindFirstChildOfClass("Terrain")
if terrain == nil then
	error("Workspace has no Terrain")
end

local function blob(name: string): string
	local ok, value = pcall(function()
		return (terrain :: any)[name]
	end)
	if not ok or type(value) ~= "string" then
		return if name == "SmoothGrid" then "\1\5" else ""
	end
	return value
end

local smooth = blob("SmoothGrid")
fs.writeFile(args[2], smooth)
local line = string.format("[export_terrain] SmoothGrid %d bytes -> %s", #smooth, args[2])
if args[3] then
	local physics = blob("PhysicsGrid")
	fs.writeFile(args[3], physics)
	line ..= string.format("; PhysicsGrid %d bytes -> %s", #physics, args[3])
end
print(line)
