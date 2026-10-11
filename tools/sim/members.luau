-- members.luau: registry of emulated class members (properties, methods,
-- events, callbacks) resolved along the reflection-database class hierarchy.
--
-- Definition shapes (all functions receive the sim and the RAW instance):
--   M.prop(get(sim, real, key), set(sim, real, value, key)?)
--   M.method(fn(sim, real, ...args))        -- args/returns are script-facing values
--   M.signal({ check = fn(ctx) -> err?, onConnect = fn(sim, real, sig, conn) })
--   M.callback(set(sim, real, fn, key))     -- write-only callback members

local roblox = require("@lune/roblox")

local db = roblox.getReflectionDatabase()

local Members = {}
Members.__index = Members

local registry: { [string]: { [string]: any } } = {}

function Members.prop(get, set)
	return { kind = "prop", get = get, set = set }
end

function Members.method(fn)
	return { kind = "method", method = fn }
end

function Members.signal(opts)
	local def = opts or {}
	def.kind = "signal"
	return def
end

function Members.callback(set)
	return { kind = "callback", set = set }
end

function Members.define(className: string, defs)
	local t = registry[className] or {}
	for k, v in defs do
		t[k] = v
	end
	registry[className] = t
end

-- Load definition modules (each returns function(M)).
require("./members/instance")(Members)
require("./members/world")(Members)
require("./members/players")(Members)
require("./members/remotes")(Members)
require("./members/services")(Members)
require("./members/gui")(Members)
require("./members/input")(Members)

function Members.new(sim)
	local self = setmetatable({}, Members)
	self.sim = sim
	self.cache = {}
	self.chainCache = {}
	self.defaultCache = {}
	return self
end

-- Class chain from Instance down to className.
function Members:chain(className: string)
	local c = self.chainCache[className]
	if c then
		return c
	end
	c = {}
	local cur = className
	while cur do
		table.insert(c, 1, cur)
		local def = db:GetClass(cur)
		cur = def and def.Superclass or nil
	end
	if c[1] ~= "Instance" then
		table.insert(c, 1, "Instance")
	end
	self.chainCache[className] = c
	return c
end

function Members:resolve(className: string)
	local merged = self.cache[className]
	if merged then
		return merged
	end
	merged = {}
	for _, cls in self:chain(className) do
		local defs = registry[cls]
		if defs then
			for k, v in defs do
				merged[k] = v
			end
		end
	end
	self.cache[className] = merged
	return merged
end

function Members:isA(className: string, base: string): boolean
	return table.find(self:chain(className), base) ~= nil
end

function Members:propertyInfo(className: string, prop: string)
	local chain = self:chain(className)
	for i = #chain, 1, -1 do
		local def = db:GetClass(chain[i])
		local p = def and def.Properties[prop]
		if p then
			return p
		end
	end
	return nil
end

local SIMPLE_DEFAULTS = {
	Bool = false,
	String = "",
	Content = "",
	ContentId = "",
	Float32 = 0,
	Float64 = 0,
	Int32 = 0,
	Int64 = 0,
}

-- Fallback for properties Lune cannot read because the reflection database has
-- no default value for them (e.g. IgnoreGuiInset, PlaceId, TextBounds).
function Members:defaultValue(className: string, prop: string)
	local key = className .. "." .. prop
	local cached = self.defaultCache[key]
	if cached ~= nil then
		return if cached == "__nil" then nil else cached
	end
	local info = self:propertyInfo(className, prop)
	local value = nil
	if info then
		local dt = tostring(info.Datatype)
		if SIMPLE_DEFAULTS[dt] ~= nil then
			value = SIMPLE_DEFAULTS[dt]
		elseif dt == "Vector3" then
			value = roblox.Vector3.zero
		elseif dt == "Vector2" then
			value = roblox.Vector2.zero
		elseif dt == "CFrame" or dt == "OptionalCFrame" then
			value = roblox.CFrame.identity
		elseif dt == "Color3" or dt == "Color3uint8" then
			value = roblox.Color3.new(0, 0, 0)
		elseif dt == "UDim2" then
			value = roblox.UDim2.new()
		elseif dt == "UDim" then
			value = roblox.UDim.new()
		elseif dt == "BrickColor" then
			value = roblox.BrickColor.new("Medium stone grey")
		elseif dt == "Rect" then
			value = roblox.Rect.new(0, 0, 0, 0)
		elseif dt == "NumberRange" then
			value = roblox.NumberRange.new(0)
		elseif string.sub(dt, 1, 5) == "Enum." then
			local ok, items = pcall(function()
				return (roblox.Enum :: any)[string.sub(dt, 6)]:GetEnumItems()
			end)
			if ok and items[1] then
				value = items[1]
			end
		end
	end
	self.defaultCache[key] = if value == nil then "__nil" else value
	return value
end

return Members
