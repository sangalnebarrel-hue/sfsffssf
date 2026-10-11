--[[
	Builds Place1.rbxl from the original place + src/ + generated geometry.

	Usage (from the repo root):
	  lune run tools/build.luau [input.rbxl] [output.rbxl]
	Defaults: input = tools/base/Place1.base.rbxl (the original blank place),
	          output = Place1.rbxl.

	Steps:
	  1. load the input place and remove everything this script manages (so it is repeatable);
	  2. world settings (streaming off, manual character spawning, lighting, water look);
	  3. Workspace.Map (shore, lake, hub, bridges, decor, base slots);
	  4. ServerStorage.BaseTemplate;
	  5. ReplicatedStorage.Remotes from RemoteNames;
	  6. StarterGui.HUD;
	  7. all scripts from src/;
	  8. write the place + sourcemap.json (for luau-lsp) and print stats.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local U = require("./builder/Util")
local buildMap = require("./builder/Map")
local buildBaseTemplate = require("./builder/BaseTemplate")
local buildGui = require("./builder/Gui")
local Scripts = require("./builder/Scripts")
local Sourcemap = require("./builder/Sourcemap")

local Enum = U.Enum
local rgb = U.rgb

local SRC = "src"
local input = process.args[1] or "tools/base/Place1.base.rbxl"
local output = process.args[2] or "Place1.rbxl"

local game = roblox.deserializePlace(fs.readFile(input))

local MapConfig = U.loadPure(`{SRC}/ReplicatedStorage/Shared/Config/MapConfig.luau`)
local BaseConfig = U.loadPure(`{SRC}/ReplicatedStorage/Shared/Config/BaseConfig.luau`)
local RemoteNames = U.loadPure(`{SRC}/ReplicatedStorage/Shared/RemoteNames.luau`)

--------------------------------------------------------------------------------
-- 1. Remove managed content
--------------------------------------------------------------------------------

local MANAGED = {
	{ "Workspace", "Map" },
	{ "Workspace", "Bases" },
	{ "Workspace", "Baseplate" }, -- default template content replaced by our map
	{ "Workspace", "SpawnLocation" },
	{ "ServerStorage", "BaseTemplate" },
	{ "ReplicatedStorage", "Remotes" },
	{ "StarterGui", "HUD" },
}
for _, entry in MANAGED do
	local service = game:GetService(entry[1])
	local existing = service:FindFirstChild(entry[2])
	while existing do
		existing:Destroy()
		existing = service:FindFirstChild(entry[2])
	end
end

--------------------------------------------------------------------------------
-- 2. World settings
--------------------------------------------------------------------------------

local workspace = game:GetService("Workspace")
-- Small map (~1k parts): stream everything, so client code never waits for missing parts.
workspace.StreamingEnabled = false

-- The HUD is laid out for landscape (sizes follow screen height) — like most action games.
game:GetService("StarterGui").ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

local players = game:GetService("Players")
players.CharacterAutoLoads = false -- BaseService spawns characters on their base
players.RespawnTime = BaseConfig.RespawnDelay

local terrain = workspace:FindFirstChildOfClass("Terrain")
if terrain then
	terrain.WaterColor = rgb(25, 150, 205)
	terrain.WaterTransparency = 0.6
	terrain.WaterReflectance = 0.35
	terrain.WaterWaveSize = 0.1
	terrain.WaterWaveSpeed = 8
	terrain.Decoration = false
end

local lighting = game:GetService("Lighting")
lighting.TimeOfDay = "14:30:00"
lighting.OutdoorAmbient = rgb(140, 140, 150)
-- Depth of field is a full-screen blur pass — too heavy for phones.
local dof = lighting:FindFirstChildOfClass("DepthOfFieldEffect")
if dof then
	dof:Destroy()
end
local atmosphere = lighting:FindFirstChildOfClass("Atmosphere")
if atmosphere then
	atmosphere.Density = 0.25
	atmosphere.Haze = 0.6
	atmosphere.Glare = 0
end

--------------------------------------------------------------------------------
-- 3-6. Generated content
--------------------------------------------------------------------------------

local mapResult = buildMap(game, MapConfig)
local templateResult = buildBaseTemplate(game, MapConfig)

local replicatedStorage = game:GetService("ReplicatedStorage")
local remotes = U.folder(replicatedStorage, "Remotes")
for _, name in RemoteNames.Events do
	U.new("RemoteEvent", { Name = name }, remotes)
end
for _, name in RemoteNames.Functions do
	U.new("RemoteFunction", { Name = name }, remotes)
end

buildGui(game)

-- Models without a PrimaryPart get their pivot at the centre of their parts, so Studio's
-- move/rotate gizmo appears on the object itself. Note: the saved property is WorldPivotData
-- (Model.WorldPivot is a non-serialized alias and would be silently dropped).
local function centrePivots(root: any)
	for _, model in root:GetDescendants() do
		if model:IsA("Model") and not model.PrimaryPart then
			local sum, count = U.Vector3.new(0, 0, 0), 0
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					sum += part.CFrame.Position
					count += 1
				end
			end
			if count > 0 then
				model.WorldPivotData = U.CFrame.new(sum / count)
			end
		end
	end
end
centrePivots(mapResult.map)
centrePivots(templateResult.template)

--------------------------------------------------------------------------------
-- 7. Scripts
--------------------------------------------------------------------------------

local mapping = Scripts.sync(game, SRC)
local scriptCount = 0
for _ in mapping do
	scriptCount += 1
end

--------------------------------------------------------------------------------
-- 8. Write + stats
--------------------------------------------------------------------------------

local placeBytes = roblox.serializePlace(game)

--------------------------------------------------------------------------------
-- Self-check: re-read the serialized bytes (before writing) and verify things Lune could silently drop
-- (non-serialized aliases such as Attachment.Position or Model.WorldPivot) or that the
-- server code depends on.
--------------------------------------------------------------------------------

local check = roblox.deserializePlace(placeBytes)
local problems = {}
local function expect(cond: boolean, message: string)
	if not cond then
		table.insert(problems, message)
	end
end
local function find(root: any, path: { string }): any
	local current = root
	for _, name in path do
		current = current and current:FindFirstChild(name)
	end
	return current
end
local function expectAttachment(root: any, path: { string }, offset: any)
	local attachment = find(root, path)
	expect(attachment ~= nil, `missing {table.concat(path, ".")}`)
	if attachment then
		local delta = (attachment.CFrame.Position - offset).Magnitude
		expect(delta < 1e-3, `{table.concat(path, ".")} offset {attachment.CFrame.Position} ≠ {offset}`)
	end
end

local checkTemplate = check:GetService("ServerStorage"):FindFirstChild("BaseTemplate")
expect(checkTemplate ~= nil and checkTemplate.PrimaryPart ~= nil, "BaseTemplate.PrimaryPart not saved")
expectAttachment(checkTemplate, { "Flag", "Pole", "SignAttachment" }, U.Vector3.new(0, 9.6, 0))
expectAttachment(checkTemplate, { "Tank", "Glass", "PromptAttachment" }, U.Vector3.new(0, -1, 3.9))
expectAttachment(
	check:GetService("Workspace"),
	{ "Map", "Hub", "Shop", "Counter", "ShopPromptAttachment" },
	U.Vector3.new(0, 0.6, 1.4)
)
local accents = 0
for _, d in (if checkTemplate then checkTemplate:GetDescendants() else {}) do
	if d:GetAttribute("Accent") == true then
		accents += 1
	end
end
expect(accents >= 8, `only {accents} Accent parts in BaseTemplate`)
local slotsFolder = find(check:GetService("Workspace"), { "Map", "BaseSlots" })
expect(slotsFolder ~= nil and #slotsFolder:GetChildren() == MapConfig.BaseCount, "BaseSlots count mismatch")
expect(check:GetService("Players").CharacterAutoLoads == false, "CharacterAutoLoads not saved")
expect(check:GetService("Workspace").StreamingEnabled == false, "StreamingEnabled not saved")
local pivotsSaved = 0
for _, d in find(check:GetService("Workspace"), { "Map" }):GetDescendants() do
	if d:IsA("Model") and not d.PrimaryPart then
		local ok, pivot = pcall(function()
			return d.WorldPivotData
		end)
		if ok and pivot and pivot.Position.Magnitude > 0 then
			pivotsSaved += 1
		end
	end
end
expect(pivotsSaved > 0, "Model pivots (WorldPivotData) not saved")

if #problems > 0 then
	error("Self-check of the built place failed:\n  - " .. table.concat(problems, "\n  - "))
end

-- Only a place that passed the self-check replaces Place1.rbxl.
fs.writeFile(output, placeBytes)
fs.writeFile("sourcemap.json", serde.encode("json", Sourcemap.build(game, mapping), true))

local function countParts(root: any): number
	local count = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	return count
end

local mapParts = countParts(mapResult.map)
local waterParts = countParts(mapResult.map:FindFirstChild("Water"))
local runtimeParts = mapParts - waterParts + templateResult.partCount * MapConfig.BaseCount
print(`Built {output} from {input} (self-check passed)`)
print(`  map parts: {mapParts} (incl. {waterParts} water volumes removed at runtime)`)
print(`  base template parts: {templateResult.partCount} × {MapConfig.BaseCount} bases`)
print(`  ≈ parts at runtime: {runtimeParts}`)
print(`  scripts: {scriptCount}, remotes: {#remotes:GetChildren()}`)
local cells = {}
for cls, n in mapResult.cellCounts do
	table.insert(cells, `{cls}={n}`)
end
table.sort(cells)
print(`  merged ground rects: {table.concat(cells, ", ")}`)
