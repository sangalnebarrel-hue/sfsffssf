-- input.luau: per-client input state: device profile, keys, ContextActionService
-- bindings, ProximityPrompt holds and TextBox focus. Tests drive it through
-- sim:PressKey / sim:Tap / sim:FireInput / sim:TriggerAction / sim:HoldPrompt.
-- A hold reads the prompt as the holding client sees it (its client-local Enabled,
-- MaxActivationDistance, HoldDuration and ProximityPromptService.Enabled); its events reach
-- that client at once and the server after the client->server remoteLatency (in the
-- order they happened). sim:FirePromptEvent sends one prompt event to the server only,
-- unchecked (an exploit's fireproximityprompt or a forged HoldBegan).

local roblox = require("@lune/roblox")

local Enum = roblox.Enum

local Input = {}
Input.__index = Input

local DEFAULT_PRIORITY = 2000

function Input.new(sim)
	local self = setmetatable({}, Input)
	self.sim = sim
	self.cas = setmetatable({}, { __mode = "k" }) -- ctx -> { name -> binding }
	self.holds = {} -- active ProximityPrompt holds
	self.focused = setmetatable({}, { __mode = "k" }) -- ctx -> raw TextBox
	self.seq = 0
	return self
end

local function playerState(sim, ctx)
	return ctx.player and sim.players.state[ctx.player]
end

function Input:device(name: string): boolean
	local st = playerState(self.sim, self.sim.sched:context())
	return st ~= nil and st.device[name] == true
end

function Input:lastInputType()
	local st = playerState(self.sim, self.sim.sched:context())
	if st == nil then
		return Enum.UserInputType.None
	end
	if st.device.TouchEnabled then
		return Enum.UserInputType.Touch
	elseif st.device.GamepadEnabled then
		return Enum.UserInputType.Gamepad1
	end
	return Enum.UserInputType.MouseButton1
end

function Input:isKeyDown(keyCode): boolean
	local st = playerState(self.sim, self.sim.sched:context())
	return st ~= nil and st.keysDown[keyCode] == true
end

function Input:keysPressed()
	local st = playerState(self.sim, self.sim.sched:context())
	local out = {}
	if st then
		for kc in st.keysDown do
			table.insert(
				out,
				self:makeInputObject({
					KeyCode = kc,
					UserInputType = Enum.UserInputType.Keyboard,
					UserInputState = Enum.UserInputState.Begin,
				})
			)
		end
	end
	return out
end

-- Builds a (proxied) InputObject from a spec table.
function Input:makeInputObject(spec)
	local io = roblox.Instance.new("InputObject")
	-- KeyCode.None is Lune's name for Roblox's KeyCode.Unknown (value 0)
	io.KeyCode = spec.KeyCode or Enum.KeyCode.None
	io.UserInputType = spec.UserInputType or Enum.UserInputType.None
	io.UserInputState = spec.UserInputState or Enum.UserInputState.Begin
	local pos = spec.Position
	if typeof(pos) == "Vector2" then
		pos = roblox.Vector3.new(pos.X, pos.Y, 0)
	end
	io.Position = pos or roblox.Vector3.zero
	io.Delta = spec.Delta or roblox.Vector3.zero
	return self.sim.proxy:wrap(io)
end

local function onlyCtx(ctx)
	return function(c)
		return c == ctx
	end
end

function Input:_ctxOf(playerReal)
	local st = self.sim.players.state[playerReal]
	if st == nil or st.removed then
		error("RbxSim: player is not in the game", 3)
	end
	return st.ctx, st
end

function Input:fireUIS(playerReal, event: string, ...)
	local ctx = self:_ctxOf(playerReal)
	self.sim.proxy:fireFiltered(self.sim.uisReal, event, onlyCtx(ctx), ...)
end

-- ContextActionService ---------------------------------------------------------------------

function Input:bindAction(name, fn, touchButton, priority, ...)
	if type(name) ~= "string" or type(fn) ~= "function" then
		error("BindAction(name, function, createTouchButton, ...inputs) expected", 0)
	end
	local sched = self.sim.sched
	local ctx = sched:context()
	local per = self.cas[ctx]
	if per == nil then
		per = {}
		self.cas[ctx] = per
	end
	self.seq += 1
	per[name] = {
		name = name,
		fn = fn,
		touchButton = touchButton == true,
		priority = tonumber(priority) or DEFAULT_PRIORITY,
		inputs = table.pack(...),
		script = sched:script(),
		seq = self.seq,
	}
end

function Input:unbindAction(name)
	local per = self.cas[self.sim.sched:context()]
	if per then
		per[name] = nil
	end
end

function Input:unbindAll()
	self.cas[self.sim.sched:context()] = nil
end

local function bindingInfo(b)
	local inputs = {}
	for i = 1, b.inputs.n do
		inputs[i] = b.inputs[i]
	end
	return {
		createTouchButton = b.touchButton,
		inputTypes = inputs,
		priorityLevel = b.priority,
		stackOrder = b.seq,
		title = "",
		description = "",
		image = "",
	}
end

function Input:actionInfo(name)
	local per = self.cas[self.sim.sched:context()]
	local b = per and per[name]
	return b and bindingInfo(b) or {}
end

function Input:allActionInfo()
	local out = {}
	for name, b in self.cas[self.sim.sched:context()] or {} do
		out[name] = bindingInfo(b)
	end
	return out
end

-- Runs a CAS handler in the client context; returns its result (Sink unless it yields).
function Input:_callBinding(ctx, b, state, io)
	local result = Enum.ContextActionResult.Sink
	local done = false
	local sched = self.sim.sched
	local co = sched:newThread(function(...)
		local r = b.fn(...)
		done = true
		if r ~= nil then
			result = r
		end
	end, ctx, b.script)
	sched:resume(co, b.name, state, io)
	if not done then
		result = Enum.ContextActionResult.Sink
	end
	return result
end

function Input:triggerAction(playerReal, name: string, state, io)
	local ctx = self:_ctxOf(playerReal)
	local per = self.cas[ctx]
	local b = per and per[name]
	if b == nil then
		error("RbxSim: no ContextActionService action named '" .. name .. "' is bound for this player", 3)
	end
	io = io
		or self:makeInputObject({
			UserInputType = Enum.UserInputType.Touch,
			UserInputState = state or Enum.UserInputState.Begin,
		})
	local r = self:_callBinding(ctx, b, state or Enum.UserInputState.Begin, io)
	self.sim.sched:flush()
	return r
end

local function matches(b, io)
	for i = 1, b.inputs.n do
		local inp = b.inputs[i]
		if inp == io.KeyCode or inp == io.UserInputType then
			return true
		end
	end
	return false
end

-- Offers an input to bound actions (highest priority, most recent first).
function Input:_routeCAS(ctx, io, state)
	local list = {}
	for _, b in self.cas[ctx] or {} do
		if matches(b, io) then
			table.insert(list, b)
		end
	end
	table.sort(list, function(a, b)
		if a.priority ~= b.priority then
			return a.priority > b.priority
		end
		return a.seq > b.seq
	end)
	for _, b in list do
		if self:_callBinding(ctx, b, state, io) ~= Enum.ContextActionResult.Pass then
			return true
		end
	end
	return false
end

-- Keyboard / touch / mouse helpers -----------------------------------------------------------

function Input:keyEvent(playerReal, keyCode, down: boolean, gameProcessed: boolean?)
	local ctx, st = self:_ctxOf(playerReal)
	local state = if down then Enum.UserInputState.Begin else Enum.UserInputState.End
	local io =
		self:makeInputObject({ KeyCode = keyCode, UserInputType = Enum.UserInputType.Keyboard, UserInputState = state })
	local real = self.sim.proxy:toReal(io)
	local sunk = self:_routeCAS(ctx, real, state)
	if down then
		st.keysDown[keyCode] = true
	else
		st.keysDown[keyCode] = nil
	end
	self:fireUIS(playerReal, if down then "InputBegan" else "InputEnded", io, sunk or gameProcessed == true)
end

function Input:pressKey(playerReal, keyCode, opts)
	opts = opts or {}
	self:keyEvent(playerReal, keyCode, true, opts.gameProcessed)
	self.sim.sched:flush()
	if not opts.hold then
		self:keyEvent(playerReal, keyCode, false, opts.gameProcessed)
		self.sim.sched:flush()
	end
end

function Input:tap(playerReal, position, gameProcessed: boolean?)
	local pos = position or roblox.Vector2.new(100, 100)
	local spec =
		{ UserInputType = Enum.UserInputType.Touch, Position = pos, UserInputState = Enum.UserInputState.Begin }
	local ctx = self:_ctxOf(playerReal)
	local began = self:makeInputObject(spec)
	local sunk = self:_routeCAS(ctx, self.sim.proxy:toReal(began), Enum.UserInputState.Begin)
	local gp = sunk or gameProcessed == true
	self:fireUIS(playerReal, "TouchStarted", began, gp)
	self:fireUIS(playerReal, "InputBegan", began, gp)
	spec.UserInputState = Enum.UserInputState.End
	local ended = self:makeInputObject(spec)
	self:fireUIS(playerReal, "TouchEnded", ended, gp)
	self:fireUIS(playerReal, "InputEnded", ended, gp)
	self:fireUIS(playerReal, "TouchTap", { pos }, gp)
	self.sim.sched:flush()
end

function Input:mouseClick(playerReal, gameProcessed: boolean?)
	local ctx = self:_ctxOf(playerReal)
	local spec = { UserInputType = Enum.UserInputType.MouseButton1, UserInputState = Enum.UserInputState.Begin }
	local began = self:makeInputObject(spec)
	local sunk = self:_routeCAS(ctx, self.sim.proxy:toReal(began), Enum.UserInputState.Begin)
	local gp = sunk or gameProcessed == true
	self:fireUIS(playerReal, "InputBegan", began, gp)
	spec.UserInputState = Enum.UserInputState.End
	self:fireUIS(playerReal, "InputEnded", self:makeInputObject(spec), gp)
	self.sim.sched:flush()
end

-- TextBox focus --------------------------------------------------------------------------------

function Input:focusTextBox(real, focus: boolean, submitted: boolean?)
	local sim = self.sim
	local ctx = sim.sched:context()
	local proxy = sim.proxy
	if focus then
		self.focused[ctx] = real
		proxy:fireFiltered(real, "Focused", onlyCtx(ctx))
	elseif self.focused[ctx] == real then
		self.focused[ctx] = nil
		local io = self:makeInputObject({ UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Return })
		proxy:fireFiltered(real, "FocusLost", onlyCtx(ctx), submitted == true, io)
	end
end

-- ProximityPrompt holds -------------------------------------------------------------------------

local function promptPosition(sim, prompt)
	local parent = prompt.Parent
	if parent == nil then
		return nil
	end
	if parent:IsA("BasePart") then
		return parent.CFrame.Position
	elseif parent:IsA("Attachment") then
		return sim.proxy:read(parent, "WorldPosition")
	elseif parent:IsA("Model") then
		return sim.world:getPivot(parent).Position
	end
	return nil
end
Input.promptPosition = promptPosition

-- A prompt property (or a service's) as the holding client sees it: its client-local value
-- (an Enabled = false or MaxActivationDistance = 0 a LocalScript wrote) over the replicated one.
local function seenBy(sim, ctx, real, key: string)
	return sim.proxy:viewOf(ctx, real, key)
end

-- HoldDuration of the prompt as this player's client sees it.
function Input:holdDurationFor(playerReal, prompt): number
	local st = self.sim.players.state[playerReal]
	return seenBy(self.sim, st and st.ctx, prompt, "HoldDuration")
end

-- Returns (ok, reason) for whether the player can currently use the prompt. Enabled,
-- MaxActivationDistance and ProximityPromptService.Enabled are read through the player's
-- client (a prompt that client hid locally cannot be held there); a MaxActivationDistance
-- of 0 or less is never in range.
function Input:canUsePrompt(playerReal, prompt, opts)
	local sim = self.sim
	opts = opts or {}
	local st = sim.players.state[playerReal]
	if st == nil or st.removed then
		return false, "player left"
	end
	local ctx = st.ctx
	if sim.proxy:isDestroyed(prompt) or not prompt:IsDescendantOf(sim.workspaceReal) then
		return false, "prompt not in workspace"
	end
	if not opts.ignoreEnabled and not seenBy(sim, ctx, prompt, "Enabled") then
		return false, "prompt disabled"
	end
	local ppsEnabled = true
	pcall(function()
		ppsEnabled = seenBy(sim, ctx, sim.ppsReal, "Enabled")
	end)
	if not ppsEnabled then
		return false, "ProximityPromptService disabled"
	end
	local char = playerReal.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hum == nil or hrp == nil then
		return false, "no character"
	end
	if sim.players:isDead(hum) then
		return false, "character dead"
	end
	if not opts.ignoreDistance then
		local pos = promptPosition(sim, prompt)
		if pos == nil then
			return false, "prompt has no world position"
		end
		local dist = (hrp.CFrame.Position - pos).Magnitude
		local reach = seenBy(sim, ctx, prompt, "MaxActivationDistance")
		if reach <= 0 or dist > reach + 1e-6 then
			return false, string.format("out of range (%.1f > %.1f)", dist, reach)
		end
	end
	return true, nil
end

local function serverOnly(c)
	return c.kind == "server"
end

-- Prompt event names per FirePromptEvent kind: { prompt event, ProximityPromptService event }.
local PROMPT_EVENTS = {
	HoldBegan = { "PromptButtonHoldBegan", "PromptButtonHoldBegan" },
	HoldEnded = { "PromptButtonHoldEnded", "PromptButtonHoldEnded" },
	Triggered = { "Triggered", "PromptTriggered" },
	TriggerEnded = { "TriggerEnded", "PromptTriggerEnded" },
}
Input.PROMPT_EVENTS = PROMPT_EVENTS

-- Delivers a prompt event (and its ProximityPromptService twin) to the server's handlers after
-- the client->server latency, like a RemoteEvent (equal delays keep the call order).
function Input:_toServer(promptReal, event: string, serviceEvent: string, playerProxy)
	local sim = self.sim
	sim.remotes:_later(function()
		local proxy = sim.proxy
		proxy:fireFiltered(promptReal, event, serverOnly, playerProxy)
		proxy:fireFiltered(sim.ppsReal, serviceEvent, serverOnly, proxy:wrap(promptReal), playerProxy)
	end)
end

-- A hold's event: the holding client's handlers at once, the server's after remoteLatency
-- (with no latency both in this frame, in connection order, as before).
function Input:_firePrompt(hold, event: string, serviceEvent: string)
	local sim = self.sim
	local proxy = sim.proxy
	local ctx = sim.players.state[hold.player].ctx
	local pp = proxy:wrap(hold.player)
	if (sim.opts.remoteLatency or 0) <= 0 then
		local filter = function(c)
			return c.kind == "server" or c == ctx
		end
		proxy:fireFiltered(hold.prompt, event, filter, pp)
		proxy:fireFiltered(sim.ppsReal, serviceEvent, filter, proxy:wrap(hold.prompt), pp)
		return
	end
	local own = function(c)
		return c == ctx
	end
	proxy:fireFiltered(hold.prompt, event, own, pp)
	proxy:fireFiltered(sim.ppsReal, serviceEvent, own, proxy:wrap(hold.prompt), pp)
	self:_toServer(hold.prompt, event, serviceEvent, pp)
end

-- sim:FirePromptEvent: one prompt event as the player's client would send it, to the server
-- only, with no checks at all (enabled, range, alive, hold time, a hold in progress) and
-- through remoteLatency like the real ones. Also for a player who already left: an event
-- still in flight when he disconnected.
function Input:firePromptEvent(playerReal, prompt, kind: string)
	local names = PROMPT_EVENTS[kind]
	if names == nil then
		error(
			'RbxSim: FirePromptEvent kind must be "HoldBegan", "HoldEnded", "Triggered" or "TriggerEnded", got '
				.. tostring(kind),
			3
		)
	end
	if prompt == nil or not prompt:IsA("ProximityPrompt") then
		error("RbxSim: ProximityPrompt expected", 3)
	end
	if self.sim.players.state[playerReal] == nil then
		error("RbxSim: unknown player", 3)
	end
	self:_toServer(prompt, names[1], names[2], self.sim.proxy:wrap(playerReal))
	self.sim.sched:flush()
end

function Input:findHold(playerReal, prompt)
	for _, h in self.holds do
		if h.player == playerReal and h.prompt == prompt then
			return h
		end
	end
	return nil
end

function Input:_trigger(hold)
	hold.triggered = true
	hold.triggeredAt = self.sim.sched.clock
	self:_firePrompt(hold, "Triggered", "PromptTriggered")
end

function Input:beginHold(playerReal, prompt, opts)
	if prompt == nil or not prompt:IsA("ProximityPrompt") then
		error("RbxSim: ProximityPrompt expected", 3)
	end
	local existing = self:findHold(playerReal, prompt)
	if existing then
		return existing
	end
	local ok, reason = self:canUsePrompt(playerReal, prompt, opts)
	local hold = {
		player = playerReal,
		prompt = prompt,
		started = self.sim.sched.clock,
		triggered = false,
		opts = opts or {},
		active = ok,
		began = self:holdDurationFor(playerReal, prompt) > 0,
		cancelReason = reason,
	}
	if not ok then
		return hold
	end
	table.insert(self.holds, hold)
	if not hold.began then
		self:_trigger(hold)
	else
		self:_firePrompt(hold, "PromptButtonHoldBegan", "PromptButtonHoldBegan")
	end
	self.sim.sched:flush()
	return hold
end

function Input:_endHold(hold, reason: string?)
	local i = table.find(self.holds, hold)
	if i then
		table.remove(self.holds, i)
	end
	hold.active = false
	hold.cancelReason = reason
	if self.sim.players.state[hold.player] and not self.sim.players.state[hold.player].removed then
		if hold.began then
			self:_firePrompt(hold, "PromptButtonHoldEnded", "PromptButtonHoldEnded")
		end
		if hold.triggered then
			self:_firePrompt(hold, "TriggerEnded", "PromptTriggerEnded")
		end
	end
end

function Input:releaseHold(playerReal, prompt)
	local hold = self:findHold(playerReal, prompt)
	if hold then
		self:_endHold(hold, nil)
		self.sim.sched:flush()
	end
	return hold
end

-- Per-frame: cancel invalid holds, trigger completed ones.
function Input:update()
	if #self.holds == 0 then
		return
	end
	local clock = self.sim.sched.clock
	for _, hold in table.clone(self.holds) do
		local ok, reason = self:canUsePrompt(hold.player, hold.prompt, hold.opts)
		if not ok then
			self:_endHold(hold, reason)
		elseif not hold.triggered and clock - hold.started >= self:holdDurationFor(hold.player, hold.prompt) - 1e-9 then
			self:_trigger(hold)
		end
	end
end

function Input:clearPlayer(playerReal)
	for _, hold in table.clone(self.holds) do
		if hold.player == playerReal then
			local i = table.find(self.holds, hold)
			if i then
				table.remove(self.holds, i)
			end
		end
	end
end

return Input
