--[[
	Builder helpers: instance creation shortcuts and loading of "pure" config modules
	(ModuleScripts from src/ that only use Roblox datatypes, no require/game access).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Enum = roblox.Enum
local Color3 = roblox.Color3
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local Util = {}

Util.roblox = roblox
Util.Instance = Instance
Util.Enum = Enum
Util.Color3 = Color3
Util.Vector3 = Vector3
Util.CFrame = CFrame
Util.UDim = roblox.UDim
Util.UDim2 = roblox.UDim2
Util.Vector2 = roblox.Vector2
Util.Font = roblox.Font

-- Generic constructor: Util.new("Part", { Name = "X", Attributes = {...}, Tags = {...} }, parent)
function Util.new(className: string, props: { [string]: any }?, parent: any?): any
	local inst = Instance.new(className)
	if props then
		-- Name first so errors below mention a useful name.
		if props.Name then
			inst.Name = props.Name
		end
		for key, value in props do
			if key == "Attributes" then
				for attrName, attrValue in value do
					inst:SetAttribute(attrName, attrValue)
				end
			elseif key == "Tags" then
				for _, tag in value do
					inst:AddTag(tag)
				end
			elseif key ~= "Name" and key ~= "Parent" then
				local ok, err = pcall(function()
					inst[key] = value
				end)
				if not ok then
					error(`Util.new: cannot set {className}.{key}: {err}`, 2)
				end
			end
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Util.rgb(r: number, g: number, b: number)
	return Color3.fromRGB(r, g, b)
end

function Util.folder(parent: any, name: string): any
	return Util.new("Folder", { Name = name }, parent)
end

function Util.model(parent: any, name: string): any
	return Util.new("Model", { Name = name }, parent)
end

-- Counts every BasePart created through Util.part (for stats).
Util.partCount = 0

--[[
	Anchored part with sensible defaults for a static, mobile-friendly map:
	smooth surfaces, CanTouch off (no touch events), shadows on.
	extra may override anything (e.g. CanCollide = false, Shape = Enum.PartType.Cylinder,
	Attributes = { Accent = true }).
]]
function Util.part(
	parent: any,
	name: string,
	size: any,
	cframe: any,
	color: any,
	material: any?,
	extra: { [string]: any }?
): any
	local props: { [string]: any } = {
		Name = name,
		Size = size,
		CFrame = cframe,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Anchored = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		CanTouch = false,
	}
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	Util.partCount += 1
	return Util.new("Part", props, parent)
end

-- Invisible, non-colliding, non-queryable marker part.
function Util.marker(parent: any, name: string, size: any, cframe: any, extra: { [string]: any }?): any
	local props: { [string]: any } = {
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
		Locked = false,
	}
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	return Util.part(parent, name, size, cframe, Color3.fromRGB(255, 0, 255), nil, props)
end

-- Upright cylinder (Roblox cylinders have their axis along local X; rotate it to Y).
function Util.cylinderY(
	parent: any,
	name: string,
	diameter: number,
	height: number,
	position: any,
	color: any,
	material: any?,
	extra: { [string]: any }?
): any
	local props: { [string]: any } = { Shape = Enum.PartType.Cylinder }
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	local cf = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
	return Util.part(parent, name, Vector3.new(height, diameter, diameter), cf, color, material, props)
end

-- Point on the map ring: angle in degrees (0 = +Z), radius, height.
function Util.polar(angleDeg: number, radius: number, y: number)
	local a = math.rad(angleDeg)
	return Vector3.new(radius * math.sin(a), y, radius * math.cos(a))
end

-- CFrame at polar position whose local +Z points away from the centre (local -Z faces the lake centre).
function Util.polarCFrame(angleDeg: number, radius: number, y: number)
	return CFrame.new(Util.polar(angleDeg, radius, y)) * CFrame.Angles(0, math.rad(angleDeg), 0)
end

-- Environment for pure modules: Roblox datatypes + standard library.
local PURE_ENV = {
	Color3 = Color3,
	Vector3 = Vector3,
	Vector2 = roblox.Vector2,
	CFrame = CFrame,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Enum = Enum,
	NumberRange = roblox.NumberRange,
}

-- Loads a pure ModuleScript source file from src/ and returns its value.
function Util.loadPure(path: string): any
	local source = fs.readFile(path)
	local env = table.clone(PURE_ENV)
	local chunk = luau.load(source, { debugName = path, environment = env, injectGlobals = true })
	return chunk()
end

return Util
