-- tween.luau: TweenService emulation. Tweens interpolate every frame in
-- virtual time, write through the proxy layer (so Changed events fire) and
-- fire Completed(PlaybackState) when done or cancelled.

local roblox = require("@lune/roblox")

local Enum = roblox.Enum

local Tween = {}
Tween.__index = Tween

local TWEENABLE = {
	number = true,
	boolean = true,
	CFrame = true,
	Color3 = true,
	Vector3 = true,
	Vector2 = true,
	UDim2 = true,
	UDim = true,
	Rect = true,
	NumberRange = true,
	Vector2int16 = true,
	Vector3int16 = true,
}

-- Easing ------------------------------------------------------------------------------

local PI = math.pi
local C1 = 1.70158
local C3 = C1 + 1

local function bounceOut(t)
	local n1, d1 = 7.5625, 2.75
	if t < 1 / d1 then
		return n1 * t * t
	elseif t < 2 / d1 then
		t -= 1.5 / d1
		return n1 * t * t + 0.75
	elseif t < 2.5 / d1 then
		t -= 2.25 / d1
		return n1 * t * t + 0.9375
	end
	t -= 2.625 / d1
	return n1 * t * t + 0.984375
end

-- "In" curves; Out/InOut are derived.
local EASE_IN = {
	Linear = function(t)
		return t
	end,
	Sine = function(t)
		return 1 - math.cos(t * PI / 2)
	end,
	Quad = function(t)
		return t * t
	end,
	Cubic = function(t)
		return t ^ 3
	end,
	Quart = function(t)
		return t ^ 4
	end,
	Quint = function(t)
		return t ^ 5
	end,
	Exponential = function(t)
		return if t <= 0 then 0 else 2 ^ (10 * t - 10)
	end,
	Circular = function(t)
		return 1 - math.sqrt(math.max(1 - t * t, 0))
	end,
	Back = function(t)
		return C3 * t ^ 3 - C1 * t * t
	end,
	Bounce = function(t)
		return 1 - bounceOut(1 - t)
	end,
	Elastic = function(t)
		if t <= 0 or t >= 1 then
			return t
		end
		return -(2 ^ (10 * t - 10)) * math.sin((t * 10 - 10.75) * (2 * PI) / 3)
	end,
}

function Tween.ease(alpha: number, style, direction): number
	local t = math.clamp(alpha, 0, 1)
	local styleName = style and style.Name or "Quad"
	local f = EASE_IN[styleName] or EASE_IN.Quad
	local dir = direction and direction.Name or "Out"
	if dir == "In" then
		return f(t)
	elseif dir == "Out" then
		return 1 - f(1 - t)
	elseif dir == "InOut" then
		if t < 0.5 then
			return f(2 * t) / 2
		end
		return 1 - f(2 - 2 * t) / 2
	elseif dir == "OutIn" then
		if t < 0.5 then
			return (1 - f(1 - 2 * t)) / 2
		end
		return 0.5 + f(2 * t - 1) / 2
	end
	return 1 - f(1 - t)
end

local function lerp(a, b, t)
	local ta = typeof(a)
	if ta == "number" then
		return a + (b - a) * t
	elseif ta == "Vector3" or ta == "Vector2" or ta == "CFrame" or ta == "Color3" or ta == "UDim2" then
		return a:Lerp(b, t)
	elseif ta == "UDim" then
		return roblox.UDim.new(a.Scale + (b.Scale - a.Scale) * t, math.round(a.Offset + (b.Offset - a.Offset) * t))
	elseif ta == "Rect" then
		return roblox.Rect.new(a.Min:Lerp(b.Min, t), a.Max:Lerp(b.Max, t))
	elseif ta == "NumberRange" then
		return roblox.NumberRange.new(a.Min + (b.Min - a.Min) * t, a.Max + (b.Max - a.Max) * t)
	end
	return if t >= 1 then b else a
end

-- Engine ---------------------------------------------------------------------------------

function Tween.new(sim)
	local self = setmetatable({}, Tween)
	self.sim = sim
	self.state = setmetatable({}, { __mode = "k" }) -- raw Tween -> state
	self.active = {} -- list of raw tweens currently playing
	self.owner = setmetatable({}, { __mode = "k" }) -- raw target -> { prop -> raw tween }
	return self
end

function Tween:create(target, info, goals)
	local sim = self.sim
	local real = sim.proxy:toReal(target)
	if real == nil then
		error("TweenService:Create: Unable to cast value to Object", 0)
	end
	if sim.types[info] ~= "TweenInfo" then
		error("TweenService:Create: Unable to cast to TweenInfo", 0)
	end
	if type(goals) ~= "table" then
		error("TweenService:Create: Unable to cast to Dictionary", 0)
	end
	local props = {}
	for k, goal in goals do
		if type(k) ~= "string" then
			error("TweenService:Create: property names must be strings", 0)
		end
		local ok, cur = pcall(sim.proxy.read, sim.proxy, real, k)
		if not ok then
			error(string.format("TweenService:Create no property named '%s' for object '%s'", k, real.Name), 0)
		end
		local tc, tg = typeof(cur), typeof(goal)
		if not TWEENABLE[tc] then
			error(string.format("TweenService:Create property named '%s' on object '%s' is not a data type that can be tweened", k, real.Name), 0)
		end
		if tc ~= tg then
			error(
				string.format(
					"TweenService:Create property named '%s' cannot be tweened due to type mismatch (property is a '%s', but given type is '%s')",
					k,
					tc,
					tg
				),
				0
			)
		end
		props[k] = goal
	end
	local tw = roblox.Instance.new("Tween")
	tw.Name = "Tween"
	self.state[tw] = {
		target = real,
		info = info,
		goals = props,
		playback = Enum.PlaybackState.Begin,
		elapsed = 0,
		delayLeft = info.DelayTime,
		cycle = 0,
		reversing = false,
		starts = nil,
	}
	return sim.proxy:wrap(tw)
end

function Tween:get(tw)
	local st = self.state[tw]
	if st == nil then
		error("RbxSim: unknown Tween", 0)
	end
	return st
end

function Tween:_setPlayback(tw, st, state)
	if st.playback ~= state then
		st.playback = state
		self.sim.proxy:emitChanged(tw, "PlaybackState", state)
	end
end

function Tween:_release(tw, st)
	local owned = self.owner[st.target]
	if owned then
		for k in st.goals do
			if owned[k] == tw then
				owned[k] = nil
			end
		end
	end
	local i = table.find(self.active, tw)
	if i then
		table.remove(self.active, i)
	end
end

function Tween:play(tw)
	local st = self:get(tw)
	if st.playback == Enum.PlaybackState.Playing or st.playback == Enum.PlaybackState.Delayed then
		return
	end
	local sim = self.sim
	if st.playback ~= Enum.PlaybackState.Paused then
		st.elapsed = 0
		st.delayLeft = st.info.DelayTime
		st.cycle = 0
		st.reversing = false
		st.starts = {}
		for k in st.goals do
			st.starts[k] = sim.proxy:read(st.target, k)
		end
	end
	local owned = self.owner[st.target]
	if owned == nil then
		owned = {}
		self.owner[st.target] = owned
	end
	for k in st.goals do
		local other = owned[k]
		if other and other ~= tw then
			local ost = self.state[other]
			if ost and (ost.playback == Enum.PlaybackState.Playing or ost.playback == Enum.PlaybackState.Delayed) then
				self:cancel(other)
			end
		end
		owned[k] = tw
	end
	self:_setPlayback(tw, st, Enum.PlaybackState.Playing)
	if not table.find(self.active, tw) then
		table.insert(self.active, tw)
	end
end

function Tween:pause(tw)
	local st = self:get(tw)
	if st.playback == Enum.PlaybackState.Playing or st.playback == Enum.PlaybackState.Delayed then
		self:_setPlayback(tw, st, Enum.PlaybackState.Paused)
		local i = table.find(self.active, tw)
		if i then
			table.remove(self.active, i)
		end
	end
end

function Tween:cancel(tw)
	local st = self:get(tw)
	if st.playback == Enum.PlaybackState.Completed or st.playback == Enum.PlaybackState.Cancelled then
		return
	end
	local wasRunning = st.playback ~= Enum.PlaybackState.Begin
	self:_release(tw, st)
	self:_setPlayback(tw, st, Enum.PlaybackState.Cancelled)
	if wasRunning then
		self.sim.proxy:fire(tw, "Completed", Enum.PlaybackState.Cancelled)
	end
	self:_finished(st, Enum.TweenStatus.Canceled)
end

function Tween:_apply(st, alpha)
	local eased = Tween.ease(if st.reversing then 1 - alpha else alpha, st.info.EasingStyle, st.info.EasingDirection)
	local proxy = self.sim.proxy
	for k, goal in st.goals do
		local ok, err = pcall(proxy.assign, proxy, st.target, k, lerp(st.starts[k], goal, eased))
		if not ok then
			self.sim:_warn(nil, "[RbxSim] tween failed to set " .. k .. ": " .. tostring(err))
		end
	end
end

function Tween:_finished(st, status)
	if st.onDone then
		local cb = st.onDone
		st.onDone = nil
		self.sim.sched:queueFn(function()
			cb.fn(status)
		end, cb.ctx)
	end
end

function Tween:_complete(tw, st)
	self:_release(tw, st)
	self:_setPlayback(tw, st, Enum.PlaybackState.Completed)
	self.sim.proxy:fire(tw, "Completed", Enum.PlaybackState.Completed)
	self:_finished(st, Enum.TweenStatus.Completed)
end

-- Legacy GuiObject:TweenSize/TweenPosition/TweenSizeAndPosition.
function Tween:legacy(real, goals, dir, style, time, override, callback)
	local sim = self.sim
	self.legacyActive = self.legacyActive or setmetatable({}, { __mode = "k" })
	local current = self.legacyActive[real]
	if current then
		local cst = self.state[current]
		if cst and cst.playback == Enum.PlaybackState.Playing then
			if not override then
				return false
			end
			self:cancel(current)
		end
	end
	local info = sim.env.newTweenInfo(sim, tonumber(time) or 1, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local twProxy = self:create(real, info, goals)
	local tw = sim.proxy:toReal(twProxy)
	if type(callback) == "function" then
		self.state[tw].onDone = { fn = callback, ctx = sim.sched:context() }
	end
	self.legacyActive[real] = tw
	self:play(tw)
	return true
end

-- Advances all playing tweens by dt (called once per frame).
function Tween:update(dt: number)
	if #self.active == 0 then
		return
	end
	local proxy = self.sim.proxy
	for _, tw in table.clone(self.active) do
		local st = self.state[tw]
		if st == nil or st.playback ~= Enum.PlaybackState.Playing then
			local i = table.find(self.active, tw)
			if i then
				table.remove(self.active, i)
			end
		elseif proxy:isDestroyed(st.target) then
			self:_release(tw, st)
			self:_setPlayback(tw, st, Enum.PlaybackState.Cancelled)
		else
			local remaining = dt
			if st.delayLeft > 0 then
				local use = math.min(st.delayLeft, remaining)
				st.delayLeft -= use
				remaining -= use
			end
			if st.delayLeft <= 0 then
				st.elapsed += remaining
				local T = st.info.Time
				local alpha = if T <= 0 then 1 else math.min(st.elapsed / T, 1)
				self:_apply(st, alpha)
				if alpha >= 1 then
					if st.info.Reverses and not st.reversing then
						st.reversing = true
						st.elapsed = 0
					else
						st.cycle += 1
						local repeats = st.info.RepeatCount
						if repeats < 0 or st.cycle <= repeats then
							st.reversing = false
							st.elapsed = 0
							st.delayLeft = st.info.DelayTime
						else
							self:_complete(tw, st)
						end
					end
				end
			end
		end
	end
end

return Tween
