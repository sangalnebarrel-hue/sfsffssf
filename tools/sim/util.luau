-- util.luau: small shared helpers used across RbxSim modules.

local Util = {}

-- Lune's native typeof (returns "Instance" for raw Lune instances).
Util.luneTypeof = typeof

-- Strips Lune/mlua decorations ("runtime error:", stack dumps) from an error value.
function Util.cleanError(err: any): string
	local s = tostring(err)
	s = string.gsub(s, "^runtime error: ", "")
	local cut = string.find(s, "\n%[Stack Begin%]")
	if cut then
		s = string.sub(s, 1, cut - 1)
	end
	cut = string.find(s, "\nstack traceback:")
	if cut then
		s = string.sub(s, 1, cut - 1)
	end
	return s
end

function Util.isInstance(v: any): boolean
	return Util.luneTypeof(v) == "Instance"
end

-- Full dotted name of a raw instance (DataModel itself is "game").
function Util.fullName(real: any): string
	if real == nil then
		return "nil"
	end
	local ok, name = pcall(function()
		if real.ClassName == "DataModel" then
			return "game"
		end
		return real:GetFullName()
	end)
	return ok and name or "<instance>"
end

-- Formats a value for diagnostics (tables shown shallowly, sorted keys).
function Util.format(v: any, depth: number?): string
	depth = depth or 2
	if type(v) == "string" then
		return string.format("%q", v)
	elseif type(v) == "table" then
		if depth <= 0 then
			return "{...}"
		end
		local keys = {}
		for k in pairs(v) do
			table.insert(keys, k)
		end
		table.sort(keys, function(a, b)
			local ta, tb = type(a), type(b)
			if ta ~= tb then
				return ta < tb
			end
			if ta == "number" or ta == "string" then
				return a < b
			end
			return tostring(a) < tostring(b)
		end)
		local parts = {}
		local isArray = #v == #keys
		for i, k in keys do
			if i > 12 then
				table.insert(parts, "...")
				break
			end
			if isArray then
				table.insert(parts, Util.format(v[k], depth - 1))
			else
				table.insert(parts, string.format("%s = %s", tostring(k), Util.format(v[k], depth - 1)))
			end
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

-- Structural equality for plain tables; falls back to == otherwise.
function Util.deepEqual(a: any, b: any, seen: { [any]: any }?): boolean
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	seen = seen or {}
	if seen[a] == b then
		return true
	end
	seen[a] = b
	for k, v in pairs(a) do
		if not Util.deepEqual(v, b[k], seen) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

-- Deep copy of plain tables (no metatables, no cycles expected).
function Util.deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[Util.deepCopy(k)] = Util.deepCopy(x)
	end
	return out
end

-- Joins varargs the way Roblox print does.
function Util.joinArgs(...: any): string
	local n = select("#", ...)
	local parts = table.create(n)
	for i = 1, n do
		parts[i] = tostring((select(i, ...)))
	end
	return table.concat(parts, " ")
end

-- Minimal binary heap ordered by (t, seq).
local Heap = {}
Heap.__index = Heap
Util.Heap = Heap

function Heap.new()
	return setmetatable({ items = {}, size = 0 }, Heap)
end

local function less(a, b)
	if a.t ~= b.t then
		return a.t < b.t
	end
	return a.seq < b.seq
end

function Heap:push(item)
	self.size += 1
	local items = self.items
	local i = self.size
	items[i] = item
	while i > 1 do
		local p = i // 2
		if less(items[i], items[p]) then
			items[i], items[p] = items[p], items[i]
			i = p
		else
			break
		end
	end
end

function Heap:peek()
	return self.items[1]
end

function Heap:pop()
	local items = self.items
	local top = items[1]
	if top == nil then
		return nil
	end
	items[1] = items[self.size]
	items[self.size] = nil
	self.size -= 1
	local i = 1
	while true do
		local l, r = i * 2, i * 2 + 1
		local smallest = i
		if l <= self.size and less(items[l], items[smallest]) then
			smallest = l
		end
		if r <= self.size and less(items[r], items[smallest]) then
			smallest = r
		end
		if smallest == i then
			break
		end
		items[i], items[smallest] = items[smallest], items[i]
		i = smallest
	end
	return top
end

return Util
