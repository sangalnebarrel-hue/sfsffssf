--[[
	Builds Place1.rbxl from the original place + src/ + generated geometry.

	Usage (from the repo root):
	  lune run tools/build.luau [input.rbxl] [output.rbxl]
	Defaults: input = tools/base/Place1.base.rbxl (the original blank place),
	          output = Place1.rbxl.

	Steps:
	  1. load the input place and remove everything this script manages (so it is repeatable);
	  2. world settings (streaming off, manual character spawning, lighting, water look);
	  3. Workspace.Map (voxel ground, hub, bridges, promenade, decor, base slots) + Terrain water;
	  4. ServerStorage.BaseTemplate; LEGO studs on both (tools/builder/Studs.luau);
	  5. ReplicatedStorage.Remotes from RemoteNames, ReplicatedStorage.Assets (rods, bobbers, fish);
	  6. StarterGui.HUD;
	  7. all scripts from src/;
	  8. self-check (incl. the part budgets of MapConfig.PartBudget), write the place + sourcemap.json
	     (for luau-lsp) and print stats.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local U = require("./builder/Util")
local VoxelWorld = require("./builder/VoxelWorld")
local SmoothGrid = require("./terrain/SmoothGrid")
local buildMap = require("./builder/Map")
local buildBaseTemplate = require("./builder/BaseTemplate")
local buildAssets = require("./builder/Assets")
local buildGui = require("./builder/Gui")
local Studs = require("./builder/Studs")
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
local FishConfig = U.loadPure(`{SRC}/ReplicatedStorage/Shared/Config/FishConfig.luau`)
local RodConfig = U.loadPure(`{SRC}/ReplicatedStorage/Shared/Config/RodConfig.luau`)

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
	{ "ReplicatedStorage", "Assets" },
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
-- The whole map is ~15k static parts: replicate everything up front, so client code never
-- waits for streamed-out bases/tanks.
workspace.StreamingEnabled = false

-- The HUD is laid out for landscape (sizes follow screen height) — like most action games.
game:GetService("StarterGui").ScreenOrientation = Enum.ScreenOrientation.LandscapeSensor

local players = game:GetService("Players")
players.CharacterAutoLoads = false -- BaseService spawns characters on their base
players.RespawnTime = BaseConfig.RespawnDelay

-- World: the voxel ground (parts, built in Map.luau) and Terrain water (lagoon, pond, ocean).
local terrain = workspace:FindFirstChildOfClass("Terrain")
assert(terrain, "place has no Terrain")
local world = VoxelWorld.new(MapConfig)
local waterGrid = world:bakeWater(SmoothGrid)
local baked = { smoothGrid = waterGrid:encode(), physicsGrid = waterGrid:encodePhysics() }
terrain.SmoothGrid = baked.smoothGrid
terrain.PhysicsGrid = baked.physicsGrid
-- Bright tropical lagoon water.
terrain.WaterColor = rgb(36, 156, 186)
terrain.WaterTransparency = 0.55
terrain.WaterReflectance = 0.2
-- Slightly livelier waves (v3 ambient): still calm, the bobbers' rings (RingLift 0.3) and the
-- client's foam rings (0.12 over WaterTop) stay above the crests.
terrain.WaterWaveSize = 0.15
terrain.WaterWaveSpeed = 10
terrain.Decoration = false -- no terrain grass blades (there is no solid terrain anyway)
-- No realistic volumetric clouds: the sky has chunky voxel clouds (Map.Sky) instead.
local clouds = terrain:FindFirstChildOfClass("Clouds")
if clouds then
	clouds:Destroy()
end

-- Lighting: sunny but not overexposed (art direction v4): moderate sun, low exposure, light bloom.
local lighting = game:GetService("Lighting")
-- Sun ~50° high from the south-west: tops bright, one side lit, one side shaded — the classic
-- three-tone voxel shading (a midday sun would light only the tops).
lighting.GeographicLatitude = 35
lighting.TimeOfDay = "14:30:00"
lighting.Brightness = 1.7
-- Warm sun with a soft, slightly cool sky fill on shaded faces.
lighting.Ambient = rgb(96, 94, 100)
lighting.OutdoorAmbient = rgb(112, 116, 130)
lighting.ColorShift_Top = rgb(236, 220, 196)
lighting.ColorShift_Bottom = rgb(0, 0, 0)
lighting.EnvironmentDiffuseScale = 0.3
lighting.EnvironmentSpecularScale = 0.08 -- less plastic sky reflection on the blocks
lighting.ExposureCompensation = -0.3 -- no overexposure: pale sand/plaster/snow keep their colour
lighting.GlobalShadows = true
lighting.ShadowSoftness = 0.25
-- Depth of field is a full-screen blur pass — too heavy for phones.
local dof = lighting:FindFirstChildOfClass("DepthOfFieldEffect")
if dof then
	dof:Destroy()
end
local atmosphere = lighting:FindFirstChildOfClass("Atmosphere")
	or U.new("Atmosphere", { Name = "Atmosphere" }, lighting)
atmosphere.Density = 0.16
atmosphere.Offset = 0.25
atmosphere.Color = rgb(196, 214, 236)
atmosphere.Decay = rgb(96, 150, 214)
atmosphere.Glare = 0
atmosphere.Haze = 0.05
local bloom = lighting:FindFirstChildOfClass("BloomEffect") or U.new("BloomEffect", { Name = "Bloom" }, lighting)
-- Only Neon blooms (sunlit cream/white surfaces stay crisp).
bloom.Intensity = 0.15
bloom.Size = 18
bloom.Threshold = 2.6
local sunRays = lighting:FindFirstChildOfClass("SunRaysEffect")
	or U.new("SunRaysEffect", { Name = "SunRays" }, lighting)
sunRays.Intensity = 0.02
sunRays.Spread = 0.5
local grade = lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	or U.new("ColorCorrectionEffect", { Name = "ColorCorrection" }, lighting)
grade.Saturation = 0.12
grade.Contrast = 0.12
grade.Brightness = -0.04
grade.TintColor = rgb(255, 252, 246)

--------------------------------------------------------------------------------
-- 3-6. Generated content
--------------------------------------------------------------------------------

local mapResult = buildMap(game, MapConfig, world)
local templateResult = buildBaseTemplate(game, MapConfig)

-- LEGO studs (art direction v5): Plastic + Studs on the up faces of the map and the base template
-- (not Assets: rods and fish stay smooth), then no two overlapping tops left at one height.
local studsMap = Studs.apply(mapResult.map)
local studsTemplate = Studs.apply(templateResult.template)
local coplanarMap = Studs.resolveCoplanar({ mapResult.map })
local coplanarTemplate = Studs.resolveCoplanar({ templateResult.template })

local replicatedStorage = game:GetService("ReplicatedStorage")
local remotes = U.folder(replicatedStorage, "Remotes")
for _, name in RemoteNames.Events do
	U.new("RemoteEvent", { Name = name }, remotes)
end
for _, name in RemoteNames.Functions do
	U.new("RemoteFunction", { Name = name }, remotes)
end
local assetsResult = buildAssets(game, { FishConfig = FishConfig, RodConfig = RodConfig })

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
-- The generated map is locked in Studio (no accidental drags of thousands of blocks); unlock a
-- part in Properties if you really want to move it. The base template stays editable.
for _, d in mapResult.map:GetDescendants() do
	if d:IsA("BasePart") then
		d.Locked = true
	end
end
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
-- Builders report the attachments they placed: { root = "template"|"workspace", path = {...}, offset = Vector3 }.
local expectations = {}
for _, list in
	{
		templateResult.expectedAttachments or {},
		mapResult.expectedAttachments or {},
		assetsResult.expectedAttachments,
	}
do
	for _, item in list do
		table.insert(expectations, item)
	end
end
expect(#expectations > 0, "builders reported no attachments to verify")
for _, item in expectations do
	local root = if item.root == "template"
		then checkTemplate
		elseif item.root == "replicated" then check:GetService("ReplicatedStorage")
		else check:GetService("Workspace")
	expectAttachment(root, item.path, item.offset)
end
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
local checkTerrain = check:GetService("Workspace"):FindFirstChildOfClass("Terrain")
expect(checkTerrain ~= nil and checkTerrain.SmoothGrid == baked.smoothGrid, "Terrain.SmoothGrid not saved")
expect(checkTerrain ~= nil and checkTerrain.PhysicsGrid == baked.physicsGrid, "Terrain.PhysicsGrid not saved")
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
-- Assets: every rod is a Tool with a Handle whose other parts are welded with explicit C0
-- (Weld.C0 must survive serialization, or the rod collapses onto the hand in game);
-- every fish has its four variants; Rainbow models keep their tag.
local checkAssets = find(check:GetService("ReplicatedStorage"), { "Assets" })
expect(checkAssets ~= nil, "ReplicatedStorage.Assets not saved")
for _, rod in RodConfig.Rods do
	local tool = find(checkAssets, { "Rods", rod.Id })
	expect(tool ~= nil and tool:IsA("Tool"), `Assets.Rods.{rod.Id} is not a Tool`)
	if tool then
		local handle = tool:FindFirstChild("Handle")
		expect(handle ~= nil and handle:IsA("BasePart"), `{rod.Id}: no Handle`)
		local moved = 0
		for _, d in tool:GetDescendants() do
			if d:IsA("Weld") and d.C0.Position.Magnitude > 0.01 then
				moved += 1
			end
		end
		expect(moved > 0, `{rod.Id}: Weld.C0 offsets not saved`)
		-- The rod rises 35° forward from the hand (tools/builder/Assets.luau GRIP_TILT); an unset
		-- (identity) Grip would point it sideways.
		local tilt = math.rad(35)
		local expectedLook = U.Vector3.new(math.cos(tilt), -math.sin(tilt), 0)
		expect(
			tool.Grip.Position.Magnitude < 1e-3 and (tool.Grip.LookVector - expectedLook).Magnitude < 1e-3,
			`{rod.Id}: Grip not saved ({tool.Grip.LookVector})`
		)
		for _, d in tool:GetDescendants() do
			if d:IsA("Weld") then
				expect(d.Part0 == handle and d.Part1 == d.Parent, `{rod.Id}: Weld {d:GetFullName()} lost its parts`)
			end
		end
	end
	expect(find(checkAssets, { "Bobbers", rod.Id }) ~= nil, `Assets.Bobbers.{rod.Id} missing`)
end
for _, fish in FishConfig.Fish do
	for _, variant in { "Normal", "Gold", "Neon", "Rainbow" } do
		local model = find(checkAssets, { "Fish", fish.Id, variant })
		expect(
			model ~= nil and model.PrimaryPart ~= nil,
			`Assets.Fish.{fish.Id}.{variant} missing or without PrimaryPart`
		)
		if model and variant == "Rainbow" then
			expect(model:HasTag("RainbowFish"), `Assets.Fish.{fish.Id}.Rainbow lost its RainbowFish tag`)
		end
	end
end

-- LEGO studs: surfaces only on Plastic (elsewhere the engine draws none: a forgotten Material is
-- a silent bug), one Studs face pointing up per studded part, never on glass / water / sky /
-- seabed, none in Assets, the studded count in its band, no shimmering coplanar tops left.
local function studsCheck(root: any, label: string, band: { number }): number
	local studded = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and not d:IsA("TrussPart") then
			local nonSmooth = false
			for _, face in Studs.ALL_FACES do
				if d[face] ~= Enum.SurfaceType.Smooth then
					nonSmooth = true
				end
			end
			expect(not nonSmooth or d.Material == Enum.Material.Plastic, `{d:GetFullName()}: surfaces on {d.Material}`)
			if Studs.isStudded(d) then
				studded += 1
				expect(Studs.studsFaceUp(d), `{d:GetFullName()}: studs not (only) on the face pointing up`)
				expect(d.Transparency <= Studs.MAX_TRANSPARENCY, `{d:GetFullName()}: studs on a transparent part`)
				local x = d.Parent
				while x and x ~= root.Parent do
					expect(not Studs.SKIP_ANCESTOR[x.Name], `{d:GetFullName()}: studs under {x.Name}`)
					x = x.Parent
				end
			end
		end
	end
	expect(studded >= band[1] and studded <= band[2], `{label}: {studded} studded parts, expected {band[1]}..{band[2]}`)
	return studded
end
local checkMap = find(check:GetService("Workspace"), { "Map" })
local studdedMap = studsCheck(checkMap, "Map", Studs.EXPECTED.map)
local studdedTemplate = if checkTemplate then studsCheck(checkTemplate, "BaseTemplate", Studs.EXPECTED.template) else 0
for _, d in (if checkAssets then checkAssets:GetDescendants() else {}) do
	if d:IsA("BasePart") and not d:IsA("TrussPart") then
		for _, face in Studs.ALL_FACES do
			expect(d[face] == Enum.SurfaceType.Smooth, `{d:GetFullName()}: {face} is not Smooth`)
		end
	end
end
local leftMap = Studs.coplanarPairs({ checkMap })
local leftTemplate = if checkTemplate then Studs.coplanarPairs({ checkTemplate }) else 0
expect(leftMap + leftTemplate == 0, `{leftMap + leftTemplate} coplanar stud overlaps left (map {leftMap})`)
expect(
	coplanarMap.inverted + coplanarTemplate.inverted == 0,
	`coplanar fix flipped {coplanarMap.inverted + coplanarTemplate.inverted} layer pairs`
)

-- Part budgets (DESIGN.md §3, MapConfig.PartBudget): StreamingEnabled is off, so every phone holds
-- every part from the join on. Static = the map + one copy of the base per slot (its own variant
-- scenes only); the runtime peak adds what comes later (stage-3 tank fish, the client's ambient
-- life, characters with rods, fishing FX). The build fails rather than ship a heavier place.
local function countParts(root: any): number
	local count = 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	return count
end
local budget = MapConfig.PartBudget
local mapParts = countParts(mapResult.map)
local runtimeParts = mapParts + (templateResult.perBaseParts or templateResult.partCount) * MapConfig.BaseCount
local reserve = 0
for _, n in budget.RuntimeReserve do
	reserve += n
end
expect(runtimeParts <= budget.Static, `static parts {runtimeParts} > budget {budget.Static} (MapConfig.PartBudget)`)
expect(
	runtimeParts + reserve <= budget.RuntimePeak,
	`runtime peak {runtimeParts} + reserve {reserve} > budget {budget.RuntimePeak} (MapConfig.PartBudget)`
)

if #problems > 0 then
	error("Self-check of the built place failed:\n  - " .. table.concat(problems, "\n  - "))
end

-- Only a place that passed the self-check replaces Place1.rbxl.
fs.writeFile(output, placeBytes)
fs.writeFile("sourcemap.json", serde.encode("json", Sourcemap.build(game, mapping), true))

print(`Built {output} from {input} (self-check passed)`)
print(`  water: SmoothGrid {#baked.smoothGrid} B, PhysicsGrid {#baked.physicsGrid} B`)
print(`  ground parts: {mapResult.groundParts}`)
print(`  map parts: {mapParts}`)
print(
	`  base template parts: {templateResult.perBaseParts or templateResult.partCount} per base × {MapConfig.BaseCount} bases`
		.. ` ({templateResult.partCount} with every variant)`
)
print(
	`  assets: {assetsResult.rods} rods, {assetsResult.fish} fish × 4 variants ({assetsResult.partCount} parts, not in Workspace)`
)
print(
	`  parts: static {runtimeParts}/{budget.Static} (map + {MapConfig.BaseCount} bases), runtime peak`
		.. ` ≈ {runtimeParts + reserve}/{budget.RuntimePeak} (+ reserve {reserve}: tank fish, ambient life, characters, FX)`
)
print(
	`  studs: map {studdedMap}, template {studdedTemplate} × {MapConfig.BaseCount}`
		.. ` (≈ {studdedMap + studdedTemplate * MapConfig.BaseCount} at runtime; {studsMap.ok + studsTemplate.ok} qualified); coplanar tops fixed:`
		.. ` raised {coplanarMap.raised + coplanarTemplate.raised}, lowered {coplanarMap.lowered + coplanarTemplate.lowered},`
		.. ` flattened {coplanarMap.flattened + coplanarTemplate.flattened}, left {coplanarMap.left + coplanarTemplate.left}`
)
local nature = {}
for kind, count in mapResult.natureCounts or {} do
	table.insert(nature, `{kind}={count}`)
end
table.sort(nature)
print(`  nature: {table.concat(nature, ", ")}; road lamps: {mapResult.lamps}`)
print(`  scripts: {scriptCount}, remotes: {#remotes:GetChildren()}`)
