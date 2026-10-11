-- random.luau: deterministic Random (xorshift128) matching Roblox's Random API.

local roblox = require("@lune/roblox")

local Random = {}
Random.__index = Random

local TWO32 = 4294967296
local band, bxor, lshift, rshift = bit32.band, bit32.bxor, bit32.lshift, bit32.rshift

local function mul32(a: number, b: number): number
	local alo, ahi = band(a, 0xFFFF), rshift(a, 16)
	local blo, bhi = band(b, 0xFFFF), rshift(b, 16)
	local mid = (alo * bhi + ahi * blo) % 65536
	return (alo * blo + mid * 65536) % TWO32
end

local function splitmix(z: number): (number, number)
	z = (z + 0x9E3779B9) % TWO32
	local r = z
	r = mul32(bxor(r, rshift(r, 16)), 0x85EBCA6B)
	r = mul32(bxor(r, rshift(r, 13)), 0xC2B2AE35)
	r = bxor(r, rshift(r, 16))
	return z, r
end

function Random.new(seed: number?)
	local self = setmetatable({}, Random)
	local s = tonumber(seed) or 0
	local whole = math.floor(s)
	local frac = math.floor((s - whole) * TWO32)
	local z = (whole % TWO32 + frac) % TWO32
	local state = {}
	for i = 1, 4 do
		local r
		z, r = splitmix(z)
		state[i] = r
	end
	if state[1] == 0 and state[2] == 0 and state[3] == 0 and state[4] == 0 then
		state[1] = 1
	end
	self._s = state
	return self
end

-- Next 32-bit unsigned integer.
function Random:_next32(): number
	local s = self._s
	local t = bxor(s[1], lshift(s[1], 11))
	s[1], s[2], s[3] = s[2], s[3], s[4]
	s[4] = bxor(bxor(s[4], rshift(s[4], 19)), bxor(t, rshift(t, 8)))
	return s[4]
end

-- Uniform in [0, 1) with 53 bits of precision.
function Random:_unit(): number
	local a = rshift(self:_next32(), 5) -- 27 bits
	local b = rshift(self:_next32(), 6) -- 26 bits
	return (a * 67108864 + b) / 9007199254740992
end

function Random:NextNumber(min: number?, max: number?): number
	local lo, hi = min or 0, max or 1
	return lo + (hi - lo) * self:_unit()
end

function Random:NextInteger(min: number, max: number): number
	if type(min) ~= "number" or type(max) ~= "number" then
		error("invalid argument to 'NextInteger' (number expected)", 2)
	end
	min, max = math.floor(min), math.floor(max)
	if min > max then
		error("invalid argument #2 to 'NextInteger' (interval is empty)", 2)
	end
	return min + math.floor(self:_unit() * (max - min + 1))
end

function Random:NextUnitVector()
	local z = self:NextNumber(-1, 1)
	local theta = self:NextNumber(0, 2 * math.pi)
	local r = math.sqrt(1 - z * z)
	return roblox.Vector3.new(r * math.cos(theta), r * math.sin(theta), z)
end

function Random:Shuffle(t: { any })
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end

function Random:Clone()
	local c = setmetatable({}, Random)
	c._s = table.clone(self._s)
	return c
end

return Random
