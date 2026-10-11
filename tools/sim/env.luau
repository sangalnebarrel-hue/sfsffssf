-- env.luau: builds the global environment seen by game scripts in each
-- context (server / client), plus mock datatypes Lune lacks: Random,
-- TweenInfo, RaycastParams, OverlapParams, RaycastResult, DateTime, PathWaypoint.

local roblox = require("@lune/roblox")
local Util = require("./util")
local RandomMod = require("./random")

local Env = {}

local luneTypeof = typeof
local nativeCoroutine = coroutine

-- Mock datatypes -------------------------------------------------------------------------

function Env.newTweenInfo(sim, time, style, direction, repeatCount, reverses, delayTime)
	local info = table.freeze({
		Time = tonumber(time) or 1,
		EasingStyle = style or roblox.Enum.EasingStyle.Quad,
		EasingDirection = direction or roblox.Enum.EasingDirection.Out,
		RepeatCount = tonumber(repeatCount) or 0,
		Reverses = reverses == true,
		DelayTime = tonumber(delayTime) or 0,
	})
	sim.types[info] = "TweenInfo"
	return info
end

local function addToFilter(self, value)
	local list = table.clone(self.FilterDescendantsInstances or {})
	if type(value) == "table" then
		for _, v in value do
			table.insert(list, v)
		end
	else
		table.insert(list, value)
	end
	self.FilterDescendantsInstances = list
end

function Env.newRaycastParams(sim)
	local p = {
		FilterType = roblox.Enum.RaycastFilterType.Exclude,
		FilterDescendantsInstances = {},
		IgnoreWater = false,
		CollisionGroup = "Default",
		RespectCanCollide = false,
		BruteForceAllSlow = false,
		AddToFilter = addToFilter,
	}
	sim.types[p] = "RaycastParams"
	return p
end

function Env.newOverlapParams(sim)
	local p = {
		FilterType = roblox.Enum.RaycastFilterType.Exclude,
		FilterDescendantsInstances = {},
		MaxParts = 0,
		CollisionGroup = "Default",
		RespectCanCollide = false,
		BruteForceAllSlow = false,
		AddToFilter = addToFilter,
	}
	sim.types[p] = "OverlapParams"
	return p
end

function Env.makeRaycastResult(sim, fields)
	local r = table.freeze(fields)
	sim.types[r] = "RaycastResult"
	return r
end

local DateTimeMT = {}
DateTimeMT.__index = DateTimeMT
DateTimeMT.__eq = function(a, b)
	return a.UnixTimestampMillis == b.UnixTimestampMillis
end
DateTimeMT.__lt = function(a, b)
	return a.UnixTimestampMillis < b.UnixTimestampMillis
end
DateTimeMT.__le = function(a, b)
	return a.UnixTimestampMillis <= b.UnixTimestampMillis
end
DateTimeMT.__tostring = function(self)
	return self:ToIsoDate()
end

function DateTimeMT:ToUniversalTime()
	local secs = math.floor(self.UnixTimestampMillis / 1000)
	local t = os.date("!*t", secs) :: any
	return {
		Year = t.year,
		Month = t.month,
		Day = t.day,
		Hour = t.hour,
		Minute = t.min,
		Second = t.sec,
		Millisecond = self.UnixTimestampMillis % 1000,
	}
end
DateTimeMT.ToLocalTime = DateTimeMT.ToUniversalTime

function DateTimeMT:ToIsoDate()
	return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(self.UnixTimestampMillis / 1000)) :: string
end

function DateTimeMT:FormatUniversalTime(format: string)
	local t = self:ToUniversalTime()
	local out = format
	out = string.gsub(out, "YYYY", string.format("%04d", t.Year))
	out = string.gsub(out, "MM", string.format("%02d", t.Month))
	out = string.gsub(out, "DD", string.format("%02d", t.Day))
	out = string.gsub(out, "HH", string.format("%02d", t.Hour))
	out = string.gsub(out, "mm", string.format("%02d", t.Minute))
	out = string.gsub(out, "ss", string.format("%02d", t.Second))
	return out
end
DateTimeMT.FormatLocalTime = DateTimeMT.FormatUniversalTime

local function newDateTime(sim, millis: number)
	local dt = setmetatable({
		UnixTimestampMillis = math.floor(millis),
		UnixTimestamp = math.floor(millis / 1000),
	}, DateTimeMT)
	sim.types[dt] = "DateTime"
	return dt
end

local function makeDateTimeLib(sim)
	local lib = {}
	function lib.now()
		return newDateTime(sim, sim:_serverTime() * 1000)
	end
	function lib.fromUnixTimestamp(s)
		return newDateTime(sim, (tonumber(s) or 0) * 1000)
	end
	function lib.fromUnixTimestampMillis(ms)
		return newDateTime(sim, tonumber(ms) or 0)
	end
	function lib.fromUniversalTime(y, mo, d, h, mi, s, ms)
		local secs = os.time({ year = y or 1970, month = mo or 1, day = d or 1, hour = h or 0, min = mi or 0, sec = s or 0 })
		-- os.time interprets the table as local time; correct by the UTC offset
		local utcSelf = os.time(os.date("!*t", secs) :: any)
		secs = secs + (secs - utcSelf)
		return newDateTime(sim, secs * 1000 + (ms or 0))
	end
	lib.fromLocalTime = lib.fromUniversalTime
	function lib.fromIsoDate(iso: string)
		local y, mo, d, h, mi, s = string.match(iso, "^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
		if y == nil then
			return nil
		end
		return lib.fromUniversalTime(tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s), 0)
	end
	return table.freeze(lib)
end

-- Environment ------------------------------------------------------------------------------

-- Base globals for one context. Each script gets its own table indexing this one.
function Env.build(sim, ctx)
	local sched = sim.sched
	local proxy = sim.proxy

	local env = {}

	-- standard library
	for name, value in
		{
			assert = assert,
			error = error,
			getmetatable = getmetatable,
			setmetatable = setmetatable,
			ipairs = ipairs,
			pairs = pairs,
			next = next,
			pcall = pcall,
			xpcall = xpcall,
			rawequal = rawequal,
			rawget = rawget,
			rawset = rawset,
			rawlen = rawlen,
			select = select,
			tonumber = tonumber,
			tostring = tostring,
			type = type,
			unpack = table.unpack,
			gcinfo = gcinfo,
			collectgarbage = collectgarbage,
			newproxy = newproxy,
			getfenv = getfenv,
			setfenv = setfenv,
			string = string,
			table = table,
			utf8 = utf8,
			bit32 = bit32,
			buffer = buffer,
			vector = (vector :: any),
		}
	do
		env[name] = value
	end

	-- deterministic math.random
	local mathLib = table.clone(math)
	function mathLib.random(m, n)
		local rng = sim.mathRng
		if m == nil then
			return rng:NextNumber()
		end
		if n == nil then
			m, n = 1, m
		end
		m, n = math.floor(m), math.floor(n)
		if m > n then
			error("invalid argument #2 to 'random' (interval is empty)", 2)
		end
		return rng:NextInteger(m, n)
	end
	function mathLib.randomseed(seed)
		sim.mathRng = RandomMod.new(tonumber(seed) or 0)
	end
	env.math = table.freeze(mathLib)

	-- coroutines created by scripts inherit the creator's context
	local co = table.clone(nativeCoroutine)
	function co.create(f)
		local t = nativeCoroutine.create(f)
		sched:tag(t, sched:context(), sched:script())
		return t
	end
	function co.wrap(f)
		local t = co.create(f)
		return function(...)
			local r = table.pack(nativeCoroutine.resume(t, ...))
			if not r[1] then
				error(r[2], 2)
			end
			return table.unpack(r, 2, r.n)
		end
	end
	env.coroutine = table.freeze(co)

	local dbg = table.clone(debug)
	dbg.profilebegin = function() end
	dbg.profileend = function() end
	dbg.setmemorycategory = function() end
	dbg.resetmemorycategory = function() end
	dbg.dumpcodesize = function() end
	env.debug = table.freeze(dbg)

	-- virtual clock
	env.os = table.freeze({
		time = function(t)
			if t ~= nil then
				return os.time(t)
			end
			return math.floor(sim:_serverTime())
		end,
		clock = function()
			return sched.clock
		end,
		date = function(fmt, t)
			return os.date(fmt or "%c", t or math.floor(sim:_serverTime()))
		end,
		difftime = os.difftime,
	})
	env.tick = function()
		return sim:_serverTime()
	end
	env.time = function()
		return sched.clock
	end
	env.elapsedTime = env.time
	env.ElapsedTime = env.time
	env.version = function()
		return "0.700.0.7000000"
	end
	env.Version = env.version

	-- output
	env.print = function(...)
		sim:_log("print", sched:context(), Util.joinArgs(...))
	end
	env.warn = function(...)
		sim:_warn(sched:context(), Util.joinArgs(...))
	end
	env.printidentity = function(prefix)
		sim:_log("print", sched:context(), (prefix or "Current identity is") .. " 2")
	end

	env.typeof = function(v)
		if v ~= nil and proxy.realOf[v] ~= nil then
			return "Instance"
		end
		local t = sim.types[v]
		if t then
			return t
		end
		return luneTypeof(v)
	end

	-- task scheduler
	env.task = table.freeze({
		spawn = function(f, ...)
			return sched:taskSpawn(f, ...)
		end,
		defer = function(f, ...)
			return sched:taskDefer(f, ...)
		end,
		delay = function(t, f, ...)
			return sched:taskDelay(t, f, ...)
		end,
		wait = function(t)
			return sched:taskWait(t)
		end,
		cancel = function(t)
			sched:taskCancel(t)
		end,
		synchronize = function() end,
		desynchronize = function() end,
	})
	local function legacyWait(t)
		local elapsed = sched:taskWait(math.max(tonumber(t) or 0, 0.03))
		return elapsed, sched.clock
	end
	env.wait = legacyWait
	env.Wait = legacyWait
	local function legacyDelay(t, f)
		sched:taskDelay(math.max(tonumber(t) or 0, 0.03), f)
	end
	env.delay = legacyDelay
	env.Delay = legacyDelay
	local function legacySpawn(f)
		sched:taskDelay(0.03, f)
	end
	env.spawn = legacySpawn
	env.Spawn = legacySpawn

	-- shared state per context
	env._G = ctx.G
	env.shared = ctx.shared

	-- engine globals
	env.game = proxy:wrap(sim.real)
	env.Game = env.game
	env.workspace = proxy:wrap(sim.workspaceReal)
	env.Workspace = env.workspace
	env.plugin = nil
	env.settings = function()
		return { Physics = {}, Rendering = { QualityLevel = 1 }, Network = {} }
	end
	env.UserSettings = function()
		local gameSettings = {
			SavedQualityLevel = roblox.Enum.SavedQualitySetting.Automatic,
			MasterVolume = 1,
			RotationType = roblox.Enum.RotationType.MovementRelative,
		}
		return {
			GetService = function(_, _name)
				return gameSettings
			end,
		}
	end
	env.stats = function()
		return proxy:wrap(sim.real:GetService("Stats"))
	end
	env.require = function(target)
		return sim.runtime:require(target)
	end

	-- datatypes
	for _, name in
		{
			"Vector3",
			"Vector2",
			"Vector3int16",
			"Vector2int16",
			"CFrame",
			"Color3",
			"BrickColor",
			"UDim",
			"UDim2",
			"Rect",
			"Ray",
			"Region3",
			"Region3int16",
			"NumberRange",
			"NumberSequence",
			"NumberSequenceKeypoint",
			"ColorSequence",
			"ColorSequenceKeypoint",
			"PhysicalProperties",
			"Axes",
			"Faces",
			"Enum",
			"Font",
			"Content",
		}
	do
		env[name] = (roblox :: any)[name]
	end

	env.Instance = table.freeze({
		new = function(className, parent)
			if type(className) ~= "string" then
				error("invalid argument #1 to 'new' (string expected)", 2)
			end
			local ok, real = pcall(roblox.Instance.new, className)
			if not ok then
				error(string.format('Unable to create an Instance of type "%s"', className), 2)
			end
			sim:_onInstanceCreated(real)
			if parent ~= nil then
				local p = proxy:toReal(parent)
				if p == nil then
					error("invalid argument #2 to 'new' (Instance expected)", 2)
				end
				proxy:setParent(real, p)
			end
			return proxy:wrap(real)
		end,
		fromExisting = function(inst)
			local r = proxy:toReal(inst)
			if r == nil then
				error("invalid argument #1 to 'fromExisting' (Instance expected)", 2)
			end
			local copy = r:Clone()
			for _, c in copy:GetChildren() do
				c.Parent = nil
			end
			sim:_onInstanceCreated(copy)
			return proxy:wrap(copy)
		end,
	})

	env.Random = table.freeze({
		new = function(seed)
			local r = RandomMod.new(seed or sim.rng:NextInteger(0, 2 ^ 31))
			sim.types[r] = "Random"
			return r
		end,
	})

	env.TweenInfo = table.freeze({
		new = function(...)
			return Env.newTweenInfo(sim, ...)
		end,
	})
	env.RaycastParams = table.freeze({
		new = function()
			return Env.newRaycastParams(sim)
		end,
	})
	env.OverlapParams = table.freeze({
		new = function()
			return Env.newOverlapParams(sim)
		end,
	})
	env.DateTime = makeDateTimeLib(sim)
	env.PathWaypoint = table.freeze({
		new = function(pos, action, label)
			local w = table.freeze({
				Position = pos,
				Action = action or roblox.Enum.PathWaypointAction.Walk,
				Label = label or "",
			})
			sim.types[w] = "PathWaypoint"
			return w
		end,
	})

	return env
end

return Env
