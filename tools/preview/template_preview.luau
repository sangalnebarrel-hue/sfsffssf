--[[
	template_preview.luau  (Lune 0.11)

	Builds a minimal place that shows ONE player base on a flat stand-in world, so the
	BaseTemplate can be previewed without generating the whole map:

		lune run tools/preview/template_preview.luau <out.rbxl> [baseIndex]
		lune run tools/preview/export_parts.luau <out.rbxl> parts.json
		python3 tools/preview/render.py parts.json --out-dir DIR --views iso,zoom --zoom 0,90,120,200

	World (base-local frame of the slot = world frame, y = 0 is GroundTop):
	  * grass ground slab, top y = 0, x -110..110, z 10..200 (the plot and its margins; the
	    template brings its own house terrace);
	  * the public promenade strip z 0..18 (light paving, top y = 0.05);
	  * sand beach, top y = -2, z -12..0, plus a lagoon bed slab;
	  * water stand-in under Workspace.Map.Water for z < 0, surface y = -4
	    (export_parts renders it as water);
	  * Workspace.Map.BaseSlots.Slot_1 at the origin (attribute Index = baseIndex, default 1:
	    picks the base colour from BaseConfig.Colors);
	  * ServerStorage.BaseTemplate from tools/builder/BaseTemplate.luau;
	  * ReplicatedStorage.Shared.Config.BaseConfig copied from src/ (base colours).
	The stand-ins use the map's Palette colours and the same colour grading, water colour and haze
	as tools/build.luau, so a preview looks like the base in the real map (export_parts paints the
	Accent parts in the base colour and the WallTone parts in the base's wall tone).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local U = require("../builder/Util")
local Palette = require("../builder/Palette")
local buildBaseTemplate = require("../builder/BaseTemplate")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local rgb = U.rgb
local P = Palette

local output = process.args[1]
local baseIndex = tonumber(process.args[2]) or 1
if not output then
	print("usage: lune run tools/preview/template_preview.luau <out.rbxl> [baseIndex]")
	process.exit(1)
end

local SRC = "src"
local game = roblox.deserializePlace(fs.readFile("tools/base/Place1.base.rbxl"))
local workspace = game:GetService("Workspace")
for _, name in { "Baseplate", "SpawnLocation", "Map" } do
	local existing = workspace:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
end

local MapConfig = U.loadPure(`{SRC}/ReplicatedStorage/Shared/Config/MapConfig.luau`)

-- Axis-aligned slab from its min/max corners.
local function slab(
	parent: any,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	color: any
)
	return U.part(
		parent,
		name,
		Vector3.new(x1 - x0, y1 - y0, z1 - z0),
		CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2),
		color
	)
end

local map = U.folder(workspace, "Map")
local ground = U.folder(map, "Ground")
slab(ground, "Grass", -110, 110, -8, 0, 10, 200, P.GrassTop)
slab(ground, "Promenade", -110, 110, -6, 0.05, 0, 18, P.Cobble)
slab(ground, "Beach", -110, 110, -8, -2, -12, 0, P.Sand)
slab(ground, "LagoonBed", -150, 150, -18, -14, -150, -12, P.SandDark)

local water = U.folder(map, "Water")
slab(water, "Lagoon", -150, 150, -14, -4, -150, 0, rgb(36, 156, 186))

-- The map's colour grading, water colour and haze (tools/build.luau), read by the renderer.
local lighting = game:GetService("Lighting")
local grade = lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	or U.new("ColorCorrectionEffect", { Name = "ColorCorrection" }, lighting)
grade.Saturation = 0.1
grade.Contrast = 0.06
grade.Brightness = 0
grade.TintColor = rgb(255, 252, 246)
local atmosphere = lighting:FindFirstChildOfClass("Atmosphere")
	or U.new("Atmosphere", { Name = "Atmosphere" }, lighting)
atmosphere.Density = 0.22
atmosphere.Offset = 0.25
atmosphere.Color = rgb(198, 222, 248)
atmosphere.Decay = rgb(104, 150, 210)
atmosphere.Haze = 0.2
local terrain = workspace:FindFirstChildOfClass("Terrain")
if terrain then
	terrain.WaterColor = rgb(36, 156, 186)
	terrain.WaterTransparency = 0.55
end

local slots = U.folder(map, "BaseSlots")
U.marker(slots, "Slot_1", Vector3.new(4, 0.2, 4), CFrame.new(0, 0, 0), { Attributes = { Index = baseIndex } })

local result = buildBaseTemplate(game, MapConfig)

-- Base colours for export_parts (it executes the ModuleScript source in a sandbox).
local shared = U.folder(game:GetService("ReplicatedStorage"), "Shared")
local config = U.folder(shared, "Config")
U.new("ModuleScript", {
	Name = "BaseConfig",
	Source = fs.readFile(`{SRC}/ReplicatedStorage/Shared/Config/BaseConfig.luau`),
}, config)

fs.writeFile(output, roblox.serializePlace(game))
print(`[template_preview] BaseTemplate: {result.partCount} parts -> {output}`)
