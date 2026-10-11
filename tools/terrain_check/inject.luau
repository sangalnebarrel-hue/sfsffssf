--!strict
--[[
	inject.luau (Lune 0.11): copies a place and puts raw terrain blobs into
	Workspace.Terrain.SmoothGrid / PhysicsGrid. For testing the terrain
	tooling with blobs made elsewhere (terrain_demo, terrain_check --emit).

	lune run tools/terrain_check/inject.luau <in.rbxl> <smoothgrid.bin> <physicsgrid.bin|-> <out.rbxl>

	"-" for the PhysicsGrid keeps the place's existing one.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local args = process.args
if #args ~= 4 then
	print("usage: lune run tools/terrain_check/inject.luau <in.rbxl> <smoothgrid.bin> <physicsgrid.bin|-> <out.rbxl>")
	process.exit(2)
end
local input, smoothPath, physicsPath, output = args[1], args[2], args[3], args[4]

local game = roblox.deserializePlace(fs.readFile(input))
local terrain = game:GetService("Workspace"):FindFirstChildOfClass("Terrain")
if terrain == nil then
	error("Workspace has no Terrain")
end

local smooth = fs.readFile(smoothPath)
local t = terrain :: any
t.SmoothGrid = smooth
if physicsPath ~= "-" then
	t.PhysicsGrid = fs.readFile(physicsPath)
end

local bytes = roblox.serializePlace(game)
fs.writeFile(output, bytes)

-- Read back: the blobs must survive the round trip unchanged.
local check = roblox.deserializePlace(bytes):GetService("Workspace"):FindFirstChildOfClass("Terrain") :: any
assert(check.SmoothGrid == smooth, "SmoothGrid changed on write")
if physicsPath ~= "-" then
	assert(check.PhysicsGrid == t.PhysicsGrid, "PhysicsGrid changed on write")
end
print(string.format("[inject] SmoothGrid %d bytes, PhysicsGrid %d bytes -> %s", #smooth, #t.PhysicsGrid, output))
