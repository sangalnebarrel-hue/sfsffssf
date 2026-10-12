--!strict
--[[
	export_parts.luau  (Lune 0.11)

	Exports the visible geometry of a place file to JSON so render.py can draw it.

	Usage:
		lune run tools/preview/export_parts.luau <place.rbxl> <out.json> [--no-bases]

	What gets exported:
	  * every BasePart under Workspace (Terrain and anything under Camera are skipped,
	    parts with Transparency >= 0.98 are skipped)                      -> kind "part"
	  * parts under Workspace.Map.Lake.WaterVolumes or Workspace.Map.Water (edit-mode
	    stand-ins for Terrain water; exported even when invisible)        -> kind "water"
	  * a runtime simulation of base spawning (BaseService): for every child part of
	    Workspace.Map.BaseSlots with a numeric attribute "Index" (sorted by Index), a
	    virtual copy of ServerStorage.BaseTemplate is placed like Model:PivotTo(slot.CFrame):
	        worldCF = slot.CFrame * PrimaryPart.CFrame:Inverse() * part.CFrame
	    (PrimaryPart.PivotOffset is honoured when set), and parts with attribute
	    Accent == true get base color Index from BaseConfig.Colors, shaded like BaseService
	    does by the optional number attribute AccentShade (> 0 lighter, < 0 darker)
	                                                                     -> kind "base"
	    (disable with --no-bases)

	Output: { parts = {...}, bounds = {...}, slots = {...}, stats = {...} }
	CFrame arrays are {x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22}
	(position, then the rotation matrix row-major; world = R * local + p).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
-- Lune's roblox typedefs don't describe instance properties, so treat it as dynamic.
local roblox = require("@lune/roblox") :: any
local serde = require("@lune/serde")

local Color3 = roblox.Color3

-- Parts at least this transparent are treated as invisible.
local INVISIBLE_TRANSPARENCY = 0.98
-- Parts wider than this (X or Z) are ignored for "content" bounds (e.g. a 2048 Baseplate).
local HUGE_EXTENT = 1000

-- Folders whose parts are edit-mode stand-ins for Terrain water (filled at runtime).
local WATER_FOLDERS = {
	{ "Map", "Lake", "WaterVolumes" },
	{ "Map", "Water" },
}

-- Roblox datatypes exposed to config modules loaded from the place.
local MODULE_GLOBALS = {
	"Color3",
	"Vector3",
	"Vector2",
	"CFrame",
	"UDim",
	"UDim2",
	"Enum",
	"BrickColor",
	"NumberRange",
	"NumberSequence",
	"NumberSequenceKeypoint",
	"ColorSequence",
	"ColorSequenceKeypoint",
	"Rect",
	"Font",
	"Instance",
}

-- Fallback base palette when ReplicatedStorage.Shared.Config.BaseConfig can't be read.
local FALLBACK_COLORS = {
	Color3.fromRGB(231, 76, 60), -- red
	Color3.fromRGB(52, 152, 219), -- blue
	Color3.fromRGB(46, 204, 113), -- green
	Color3.fromRGB(241, 196, 15), -- yellow
	Color3.fromRGB(155, 89, 182), -- purple
	Color3.fromRGB(230, 126, 34), -- orange
	Color3.fromRGB(26, 188, 156), -- teal
	Color3.fromRGB(236, 112, 160), -- pink
}

------------------------------------------------------------------------------------------
-- Arguments
------------------------------------------------------------------------------------------

local positional = {}
local simulateBases = true
for _, arg in process.args do
	if arg == "--no-bases" then
		simulateBases = false
	else
		table.insert(positional, arg)
	end
end

if #positional < 2 then
	print("usage: lune run tools/preview/export_parts.luau <place.rbxl> <out.json> [--no-bases]")
	process.exit(1)
end

local placePath, outPath = positional[1], positional[2]
local game: any = roblox.deserializePlace(fs.readFile(placePath))
local Workspace: any = game:GetService("Workspace")

------------------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------------------

local function round(n: number, digits: number): number
	local m = 10 ^ digits
	return math.floor(n * m + 0.5) / m
end

-- Walks a chain of child names, returning nil when any link is missing.
local function findPath(root: any, names: { string }): any
	local current = root
	for _, name in names do
		if current == nil then
			return nil
		end
		current = current:FindFirstChild(name)
	end
	return current
end

-- Exported shape name for any BasePart class.
local function shapeOf(part: any): string
	if part:IsA("WedgePart") then
		return "Wedge"
	elseif part:IsA("CornerWedgePart") then
		return "CornerWedge"
	elseif part:IsA("Part") then
		local ok, shape = pcall(function()
			return part.Shape
		end)
		if ok and shape then
			return shape.Name
		end
	end
	-- MeshPart, UnionOperation, TrussPart, ...: approximated by their bounding box.
	return "Block"
end

local function cframeArray(cf: any): { number }
	local c = { cf:GetComponents() }
	for i, v in c do
		c[i] = round(v, 5)
	end
	return c
end

local function colorArray(color: any): { number }
	return {
		math.clamp(math.floor(color.R * 255 + 0.5), 0, 255),
		math.clamp(math.floor(color.G * 255 + 0.5), 0, 255),
		math.clamp(math.floor(color.B * 255 + 0.5), 0, 255),
	}
end

-- World-space AABB (min, max corners) of a box with CFrame cf and the given size.
local function aabb(cf: any, size: any): (any, any)
	local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = cf:GetComponents()
	local hx, hy, hz = size.X / 2, size.Y / 2, size.Z / 2
	local ex = math.abs(r00) * hx + math.abs(r01) * hy + math.abs(r02) * hz
	local ey = math.abs(r10) * hx + math.abs(r11) * hy + math.abs(r12) * hz
	local ez = math.abs(r20) * hx + math.abs(r21) * hy + math.abs(r22) * hz
	local p = cf.Position
	return p - roblox.Vector3.new(ex, ey, ez), p + roblox.Vector3.new(ex, ey, ez)
end

------------------------------------------------------------------------------------------
-- Base colors from ReplicatedStorage.Shared.Config.BaseConfig
------------------------------------------------------------------------------------------

-- Loads a ModuleScript's Source in a sandbox with Roblox datatypes and a minimal
-- require/script/game so config modules that require siblings still work.
local moduleCache: { [any]: any } = {}
local function loadModule(moduleScript: any): any
	if moduleCache[moduleScript] ~= nil then
		return moduleCache[moduleScript]
	end
	local env = {
		script = moduleScript,
		game = game,
		workspace = Workspace,
		warn = function(...) end,
		require = function(target: any)
			local targetType: string = typeof(target)
			if targetType == "Instance" and target:IsA("ModuleScript") then
				return loadModule(target)
			end
			error("export_parts: unsupported require target " .. tostring(target))
		end,
	}
	for _, name in MODULE_GLOBALS do
		local value = roblox[name]
		if value ~= nil then
			env[name] = value
		end
	end
	local fn = luau.load(moduleScript.Source, {
		debugName = moduleScript:GetFullName(),
		environment = env,
		injectGlobals = true,
	})
	local result = fn()
	moduleCache[moduleScript] = result
	return result
end

-- House wall tones per base (BaseConfig.WallTones; parts with WallTone = true, shade WallShade).
local wallTones: { any } = {}

local function readBaseColors(): ({ any }, string)
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local module = findPath(ReplicatedStorage, { "Shared", "Config", "BaseConfig" })
	if module == nil or not module:IsA("ModuleScript") then
		return FALLBACK_COLORS, "fallback (BaseConfig not found)"
	end
	local ok, result = pcall(loadModule, module)
	if not ok or type(result) ~= "table" or type(result.Colors) ~= "table" then
		return FALLBACK_COLORS, "fallback (BaseConfig failed: " .. tostring(result) .. ")"
	end
	local colors = {}
	for _, entry in result.Colors do
		local color = if type(entry) == "table" then entry.Color else entry
		local colorType: string = typeof(color)
		if colorType == "Color3" then
			table.insert(colors, color)
		end
	end
	if #colors == 0 then
		return FALLBACK_COLORS, "fallback (BaseConfig.Colors empty)"
	end
	if type(result.WallTones) == "table" then
		for _, tone in result.WallTones do
			table.insert(wallTones, tone)
		end
	end
	return colors, "BaseConfig"
end

-- Mirrors BaseService: AccentShade > 0 lerps the base colour towards white; < 0 darkens in HSV
-- (value down, saturation up, warm hues towards red).
local WHITE = Color3.new(1, 1, 1)
local function accentColor(baseColor: any, shade: any): any
	if type(shade) ~= "number" or shade == 0 then
		return baseColor
	end
	local amount = math.clamp(math.abs(shade), 0, 1)
	if shade > 0 then
		return baseColor:Lerp(WHITE, amount)
	end
	local h, s, v = baseColor:ToHSV()
	if h > 0.02 and h < 0.2 then
		h -= 0.04 * amount
	end
	return Color3.fromHSV(h, math.min(1, s * (1 + 0.15 * amount)), v * (1 - 0.6 * amount))
end

------------------------------------------------------------------------------------------
-- Export
------------------------------------------------------------------------------------------

local parts = {}
local stats = { part = 0, water = 0, base = 0, skippedInvisible = 0, bases = 0 }
local boundsMin, boundsMax = nil :: any, nil :: any
local contentMin, contentMax = nil :: any, nil :: any

local function grow(lo: any, hi: any, a: any, b: any): (any, any)
	if lo == nil then
		return a, b
	end
	return lo:Min(a), hi:Max(b)
end

local function addPart(part: any, cf: any, color: any, kind: string, path: string, extra: { [string]: any }?)
	local size = part.Size
	local entry = {
		name = part.Name,
		path = path,
		className = part.ClassName,
		shape = shapeOf(part),
		cf = cframeArray(cf),
		size = { round(size.X, 4), round(size.Y, 4), round(size.Z, 4) },
		color = colorArray(color),
		transparency = round(part.Transparency, 3),
		material = part.Material.Name,
		kind = kind,
	}
	if extra then
		for k, v in extra do
			(entry :: any)[k] = v
		end
	end
	table.insert(parts, entry)
	stats[kind] += 1

	local lo, hi = aabb(cf, size)
	boundsMin, boundsMax = grow(boundsMin, boundsMax, lo, hi)
	if hi.X - lo.X < HUGE_EXTENT and hi.Z - lo.Z < HUGE_EXTENT then
		contentMin, contentMax = grow(contentMin, contentMax, lo, hi)
	end
end

-- 1) Workspace parts (+ water stand-ins).
local terrain = Workspace:FindFirstChildOfClass("Terrain")
local camera = Workspace:FindFirstChildOfClass("Camera")
local waterFolders = {}
for _, path in WATER_FOLDERS do
	local folder = findPath(Workspace, path)
	if folder then
		table.insert(waterFolders, folder)
	end
end

local function isWater(inst: any): boolean
	for _, folder in waterFolders do
		if inst:IsDescendantOf(folder) then
			return true
		end
	end
	return false
end

for _, inst in Workspace:GetDescendants() do
	if not inst:IsA("BasePart") or inst:IsA("Terrain") then
		continue
	end
	if (terrain and inst:IsDescendantOf(terrain)) or (camera and inst:IsDescendantOf(camera)) then
		continue
	end
	local water = isWater(inst)
	-- Water stand-ins are usually invisible in edit mode; render them anyway.
	if not water and inst.Transparency >= INVISIBLE_TRANSPARENCY then
		stats.skippedInvisible += 1
		continue
	end
	addPart(inst, inst.CFrame, inst.Color, if water then "water" else "part", inst:GetFullName())
end

-- 2) Simulated base spawning (what the server does at runtime).
local slotsOut = {}
local colorSource = "none"
local template = findPath(game:GetService("ServerStorage"), { "BaseTemplate" })
local slotFolder = findPath(Workspace, { "Map", "BaseSlots" })

if simulateBases and template and slotFolder then
	local primary = if template:IsA("Model") then template.PrimaryPart else nil
	if primary == nil then
		print("[export_parts] warning: BaseTemplate has no PrimaryPart; bases not simulated")
	else
		local colors
		colors, colorSource = readBaseColors()

		local slots = {}
		for _, slot in slotFolder:GetChildren() do
			if slot:IsA("BasePart") and type(slot:GetAttribute("Index")) == "number" then
				table.insert(slots, slot)
			end
		end
		table.sort(slots, function(a, b)
			return a:GetAttribute("Index") < b:GetAttribute("Index")
		end)

		local templateParts = {}
		for _, inst in template:GetDescendants() do
			if inst:IsA("BasePart") then
				table.insert(templateParts, inst)
			end
		end

		-- Model:PivotTo(slot.CFrame) moves the pivot (PrimaryPart.CFrame * PivotOffset) onto the slot.
		local okOffset, pivotOffset = pcall(function()
			return primary.PivotOffset
		end)
		local pivot = if okOffset and pivotOffset then primary.CFrame * pivotOffset else primary.CFrame
		local toLocal = pivot:Inverse()
		for _, slot in slots do
			local index = slot:GetAttribute("Index") :: number
			local baseColor = colors[((math.floor(index) - 1) % #colors) + 1]
			local slotToWorld = slot.CFrame * toLocal
			for _, inst in templateParts do
				if inst.Transparency >= INVISIBLE_TRANSPARENCY then
					stats.skippedInvisible += 1
					continue
				end
				local color = inst.Color
				if inst:GetAttribute("Accent") == true then
					color = accentColor(baseColor, inst:GetAttribute("AccentShade"))
				elseif inst:GetAttribute("WallTone") == true and #wallTones > 0 then
					color = accentColor(
						wallTones[((math.floor(index) - 1) % #wallTones) + 1],
						inst:GetAttribute("WallShade")
					)
				end
				addPart(
					inst,
					slotToWorld * inst.CFrame,
					color,
					"base",
					string.format("VirtualBase%d:%s", index, inst:GetFullName()),
					{ baseIndex = index }
				)
			end
			stats.bases += 1
			table.insert(slotsOut, {
				index = index,
				name = slot.Name,
				cf = cframeArray(slot.CFrame),
				color = colorArray(baseColor),
			})
		end
	end
elseif simulateBases then
	print(
		string.format(
			"[export_parts] bases not simulated (BaseTemplate: %s, Map.BaseSlots: %s)",
			if template then "found" else "missing",
			if slotFolder then "found" else "missing"
		)
	)
end

------------------------------------------------------------------------------------------
-- Write JSON
------------------------------------------------------------------------------------------

local function vec(v: any): { number }?
	if v == nil then
		return nil
	end
	return { round(v.X, 3), round(v.Y, 3), round(v.Z, 3) }
end

-- The place's colour grading (ColorCorrectionEffect), so previews can match what Studio shows.
local grade = nil
do
	local lightingService = game:GetService("Lighting")
	local cc = lightingService:FindFirstChildOfClass("ColorCorrectionEffect")
	if cc and cc.Enabled then
		grade = {
			saturation = round(cc.Saturation, 3),
			contrast = round(cc.Contrast, 3),
			brightness = round(cc.Brightness, 3),
			tint = colorArray(cc.TintColor),
		}
	end
end

-- Terrain water and the sky's Atmosphere, so previews tint water and distance haze like Studio.
local water, atmosphere = nil, nil
do
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain then
		water = { color = colorArray(terrain.WaterColor), transparency = round(terrain.WaterTransparency, 3) }
	end
	local atm = game:GetService("Lighting"):FindFirstChildOfClass("Atmosphere")
	if atm then
		atmosphere = {
			density = round(atm.Density, 3),
			offset = round(atm.Offset, 3),
			haze = round(atm.Haze, 3),
			color = colorArray(atm.Color),
			decay = colorArray(atm.Decay),
		}
	end
end

local output = {
	source = placePath,
	grade = grade,
	water = water,
	atmosphere = atmosphere,
	parts = parts,
	slots = slotsOut,
	baseColorSource = colorSource,
	bounds = {
		min = vec(boundsMin),
		max = vec(boundsMax),
		-- Same, but ignoring parts wider than HUGE_EXTENT (Baseplate-like slabs).
		contentMin = vec(contentMin or boundsMin),
		contentMax = vec(contentMax or boundsMax),
	},
	stats = stats,
}

fs.writeFile(outPath, serde.encode("json", output, false))
print(
	string.format(
		"[export_parts] %d parts (part=%d water=%d base=%d, %d bases, skipped invisible=%d, colors=%s) -> %s",
		#parts,
		stats.part,
		stats.water,
		stats.base,
		stats.bases,
		stats.skippedInvisible,
		colorSource,
		outPath
	)
)
