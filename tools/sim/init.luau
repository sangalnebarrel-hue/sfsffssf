-- RbxSim: a headless Roblox runtime emulator for Lune.
--
--   local Sim = require("../tools/sim")
--   local sim = Sim.new({ place = "Place1.rbxl" })
--   sim:StartServer()
--   local p = sim:AddPlayer({ Name = "Alice" })
--   sim:Advance(2)
--   sim:AssertNoErrors()
--
-- Scripts from the place run unmodified: a server context plus one client
-- context per player share a single DataModel; each context has its own
-- require cache and _G. Time is virtual (sim:Advance / sim:Step).
-- See tools/sim/README.md for the full API and fidelity notes.

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Util = require("@self/util")
local Scheduler = require("@self/scheduler")
local Proxy = require("@self/proxy")
local Members = require("@self/members")
local Runtime = require("@self/runtime")
local Env = require("@self/env")
local Players = require("@self/players")
local Remotes = require("@self/remotes")
local World = require("@self/world")
local Tween = require("@self/tween")
local Input = require("@self/input")
local Collection = require("@self/collection")
local Misc = require("@self/misc")
local DataStore = require("@self/datastore")
local RandomMod = require("@self/random")
local Rigs = require("@self/rigs")

local Vector2 = roblox.Vector2
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local Sim = {}
Sim.__index = Sim

Sim.Random = RandomMod
Sim.Util = Util

local DEFAULT_EPOCH = 1700000000
local DEFAULT_VIEWPORT = Vector2.new(1280, 720)

local CORE_SERVICES = {
	"Workspace",
	"Players",
	"ReplicatedStorage",
	"ReplicatedFirst",
	"ServerScriptService",
	"ServerStorage",
	"StarterGui",
	"StarterPack",
	"StarterPlayer",
	"Lighting",
	"SoundService",
	"RunService",
	"UserInputService",
	"ProximityPromptService",
	"CollectionService",
	"Teams",
}

-- Properties a client may change on its own character (network ownership).
local CLIENT_PHYSICS = {
	CFrame = true,
	Position = true,
	Orientation = true,
	Rotation = true,
	Velocity = true,
	AssemblyLinearVelocity = true,
	AssemblyAngularVelocity = true,
}

-- Client-side changes to these services are purely local visuals; not reported.
local CLIENT_LOCAL_SERVICES = { Lighting = true, SoundService = true, StarterGui = true }

local function verboseFromEnv(): boolean
	local v = process.env.SIM_VERBOSE
	return v ~= nil and v ~= "" and v ~= "0"
end

--[=[
	Sim.new(opts)
	opts.place        path to a .rbxl/.rbxlx place file
	opts.game         a Lune DataModel (or a sim proxy of one) to use directly
	opts.seed         RNG seed (default 1) for math.random / Random.new / spawns
	opts.frameTime    default frame length in seconds (default 1/60)
	opts.epoch        unix time at virtual t=0 (default 1700000000)
	opts.dataStore    a snapshot from sim.DataStore:Snapshot() to start from
	opts.remoteLatency seconds of one-way latency for remotes (default 0)
	opts.strictReplication  error on client writes that would not replicate
	opts.destroyPlayerOnLeave  Destroy() Player objects on leave (default false)
	opts.instantMoveTo  Humanoid:MoveTo teleports instead of walking at WalkSpeed
	opts.verbose      echo logs to stdout (also SIM_VERBOSE=1)
]=]
function Sim.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Sim)
	self.opts = opts
	opts.remoteLatency = opts.remoteLatency or 0
	self.verbose = opts.verbose == true or verboseFromEnv()
	self.frameTime = opts.frameTime or 1 / 60
	self.util = Util
	self.env = Env

	local game
	if opts.game then
		game = opts.game
	elseif opts.place then
		game = roblox.deserializePlace(fs.readFile(opts.place))
	else
		game = roblox.Instance.new("DataModel")
	end

	-- result logs (public)
	self.Errors = {}
	self.Logs = {}
	self.Warnings = {}
	self.Notes = {}
	self.ClientEvents = {}
	self.ServerEvents = {}
	self.TerrainOps = {}
	self.ClientWrites = {}
	self.Kicks = {}
	self.CoreCalls = {}
	self.Purchases = {}
	self.Teleports = {}
	self.Badges = {}

	-- internal state
	self.types = setmetatable({}, { __mode = "k" })
	self.connections = {}
	self.connectionCount = 0
	self.contexts = {}
	self.bindToClose = {}
	self.coreGui = {}
	self.filteredText = setmetatable({}, { __mode = "k" })
	self.paths = setmetatable({}, { __mode = "k" })
	self.clientWriteSeen = {}
	self.seq = 0
	self.started = false
	self.rng = RandomMod.new(opts.seed or 1)
	self.mathRng = RandomMod.new((opts.seed or 1) + 1)

	self.sched = Scheduler.new(self)
	self.proxy = Proxy.new(self)
	if self.proxy.realOf[game] then
		game = self.proxy.realOf[game]
	end
	self.real = game
	self.members = Members.new(self)
	self.runtime = Runtime.new(self)
	self.players = Players.new(self)
	self.remotes = Remotes.new(self)
	self.world = World.new(self)
	self.tweens = Tween.new(self)
	self.input = Input.new(self)
	self.collection = Collection.new(self)
	self.misc = Misc.new(self)
	self.rigs = Rigs.new(self)
	self.DataStore = DataStore.new(self, opts.dataStore)

	for _, name in CORE_SERVICES do
		game:GetService(name)
	end
	local starterPlayer = game:GetService("StarterPlayer")
	for _, cls in { "StarterPlayerScripts", "StarterCharacterScripts" } do
		if starterPlayer:FindFirstChildOfClass(cls) == nil then
			local c = roblox.Instance.new(cls)
			c.Name = cls
			c.Parent = starterPlayer
		end
	end
	local ws = game:GetService("Workspace")
	if ws:FindFirstChildOfClass("Terrain") == nil then
		local t = roblox.Instance.new("Terrain")
		t.Name = "Terrain"
		t.Parent = ws
	end
	if ws.CurrentCamera == nil then
		local cam = roblox.Instance.new("Camera")
		cam.Name = "Camera"
		cam.Parent = ws
		ws.CurrentCamera = cam
	end

	self.workspaceReal = ws
	self.playersReal = game:GetService("Players")
	self.uisReal = game:GetService("UserInputService")
	self.ppsReal = game:GetService("ProximityPromptService")
	self.collectionReal = game:GetService("CollectionService")
	self.runServiceReal = game:GetService("RunService")
	self.proxy.serverOnlyRoots[game:GetService("ServerStorage")] = true
	self.proxy.serverOnlyRoots[game:GetService("ServerScriptService")] = true

	self.serverCtx = self:_newContext("server", nil)
	self.game = self.proxy:wrap(game)
	self.workspace = self.proxy:wrap(ws)
	return self
end

-- Contexts ---------------------------------------------------------------------------------

function Sim:_newContext(kind: string, playerReal)
	local name = "server"
	if kind == "client" then
		name = "client:" .. playerReal.Name
		for _, c in self.contexts do
			if c.name == name then
				name = name .. "#" .. tostring(playerReal.UserId)
				break
			end
		end
	end
	local ctx = {
		name = name,
		kind = kind,
		player = playerReal,
		alive = true,
		modules = {},
		G = {},
		shared = {},
		threads = setmetatable({}, { __mode = "k" }),
		connections = {},
		renderBinds = {},
		invokeTokens = {},
	}
	ctx.env = Env.build(self, ctx)
	table.insert(self.contexts, ctx)
	return ctx
end

function Sim:_killContext(ctx)
	if not ctx.alive then
		return
	end
	ctx.alive = false
	for conn in table.clone(ctx.connections) do
		conn.signal:_disconnect(conn)
	end
	for co in ctx.threads do
		self.sched:kill(co)
	end
	table.clear(ctx.threads)
	ctx.renderBinds = {}
	self.proxy:dropOverlays(ctx)
	self.remotes:onContextKilled(ctx)
	self.input.cas[ctx] = nil
	self.input.focused[ctx] = nil
	local i = table.find(self.contexts, ctx)
	if i then
		table.remove(self.contexts, i)
	end
end

function Sim:_ctxFor(who)
	if who == nil or who == "server" then
		return self.serverCtx
	end
	if type(who) == "table" and who.kind ~= nil and who.modules ~= nil then
		return who
	end
	local real = self.proxy:toReal(who)
	if real and real.ClassName == "Player" then
		local st = self.players.state[real]
		if st == nil then
			error("RbxSim: unknown player", 3)
		end
		return st.ctx
	end
	error("RbxSim: expected a Player, 'server' or nil for the context", 3)
end

function Sim:_playerReal(player)
	local real = self.proxy:toReal(player)
	if real == nil or real.ClassName ~= "Player" then
		error("RbxSim: Player expected", 3)
	end
	return real
end

-- Internal hooks used by subsystems -------------------------------------------------------------

function Sim:_nextSeq(): number
	self.seq += 1
	return self.seq
end

function Sim:_serverTime(): number
	return (self.opts.epoch or DEFAULT_EPOCH) + self.sched.clock
end

function Sim:_viewportFor(ctx)
	local st = ctx and ctx.player and self.players.state[ctx.player]
	if st then
		return st.viewport
	end
	return DEFAULT_VIEWPORT
end

function Sim:_log(kind: string, ctx, message: string)
	local entry = { time = self.sched.clock, context = ctx and ctx.name or "sim", kind = kind, message = message }
	table.insert(self.Logs, entry)
	if self.verbose then
		print(string.format("[%8.3f][%s][%s] %s", entry.time, entry.context, kind, message))
	end
	return entry
end

function Sim:_warn(ctx, message: string)
	local entry = self:_log("warn", ctx, message)
	table.insert(self.Warnings, entry)
end

function Sim:_note(message: string)
	table.insert(self.Notes, { time = self.sched.clock, message = message })
	if self.verbose then
		print("[RbxSim note] " .. message)
	end
end

function Sim:_recordError(ctx, message: string, traceback: string?, source)
	local entry = {
		time = self.sched.clock,
		context = ctx and ctx.name or "sim",
		message = message,
		traceback = traceback or "",
		source = source and Util.fullName(source) or nil,
	}
	table.insert(self.Errors, entry)
	self:_log("error", ctx, message)
	if self.verbose and traceback and traceback ~= "" then
		print(traceback)
	end
end

function Sim:_trackConnection(conn, added: boolean)
	if added then
		self.connections[conn] = true
		self.connectionCount += 1
		conn.ctx.connections[conn] = true
	else
		self.connections[conn] = nil
		self.connectionCount -= 1
		conn.ctx.connections[conn] = nil
	end
	if conn.script then
		self.runtime:_trackConn(conn.script, conn, added)
	end
end

function Sim:_onInstanceCreated(real)
	local ctx = self.sched:context()
	if ctx.kind == "client" then
		self.proxy.createdBy[real] = ctx
	end
end

function Sim:_createdByClient(real): boolean
	local cur = real
	while cur ~= nil do
		if self.proxy.createdBy[cur] ~= nil then
			return true
		end
		cur = cur.Parent
	end
	return false
end

function Sim:_clientOwns(ctx, real, what: string): boolean
	local player = ctx.player
	local camera = self.workspaceReal.CurrentCamera
	local cur = real
	while cur ~= nil do
		if self.proxy.createdBy[cur] == ctx then
			return true
		end
		local cls = cur.ClassName
		if (cls == "PlayerGui" or cls == "PlayerScripts" or cls == "Backpack") and cur.Parent == player then
			return true
		end
		if cur == camera or CLIENT_LOCAL_SERVICES[cls] then
			return true
		end
		cur = cur.Parent
	end
	-- physics of the own character's parts (not e.g. attachment frames: those never replicate)
	local char = player and player.Character
	if char and real:IsA("BasePart") and real:IsDescendantOf(char) and CLIENT_PHYSICS[what] then
		return true
	end
	return false
end

function Sim:_recordClientWrite(ctx, real, what: string, applied: string)
	local key = ctx.name .. "|" .. Util.fullName(real) .. "|" .. what
	local message = string.format(
		"client %s changed %s.%s on an instance it does not own; %s",
		ctx.name,
		Util.fullName(real),
		what,
		applied
	)
	if not self.clientWriteSeen[key] then
		self.clientWriteSeen[key] = true
		table.insert(self.ClientWrites, {
			time = self.sched.clock,
			context = ctx.name,
			player = self.proxy:wrap(ctx.player),
			instance = self.proxy:wrap(real),
			property = what,
			message = message,
		})
	end
	if self.opts.strictReplication then
		error("RbxSim: " .. message, 0)
	end
end

-- Returns the client context when the running code is a client writing to an
-- instance it does not own: such writes stay local to that client (like Roblox,
-- where they never replicate). Logged in sim.ClientWrites.
function Sim:_clientLocal(real, what: string)
	local ctx = self.sched:context()
	if ctx.kind ~= "client" or self:_clientOwns(ctx, real, what) then
		return nil
	end
	self:_recordClientWrite(ctx, real, what, "the value is kept client-local and does not replicate to the server")
	return ctx
end

-- Hierarchy changes / Destroy / Health by a client on server-owned instances are
-- applied globally (not emulated as local) but still reported.
function Sim:_checkClientWrite(real, what: string)
	local ctx = self.sched:context()
	if ctx.kind ~= "client" or self:_clientOwns(ctx, real, what) then
		return
	end
	self:_recordClientWrite(
		ctx,
		real,
		what,
		"RbxSim applies it globally, but in Roblox it would not replicate to the server"
	)
end

function Sim:_onReparented(real, oldParent, newParent, wasInGame: boolean, isInGame: boolean, getSubtree)
	if wasInGame ~= isInGame then
		self.collection:onMembershipChanged(getSubtree(), isInGame)
	end
	if real:IsA("Tool") then
		self.players:onToolMoved(real, oldParent, newParent)
	end
	self.rigs:onReparented(real, oldParent, newParent)
	if self.started and newParent ~= nil and isInGame then
		if real:IsA("BaseScript") or real:FindFirstChildWhichIsA("BaseScript", true) then
			self.runtime:onInstanceMoved(real)
		end
	end
end

function Sim:_beforeDestroy(real)
	if real:IsA("LuaSourceContainer") then
		self.runtime:stopScript(real)
	end
end

-- Lifecycle / time --------------------------------------------------------------------------------

-- Runs every enabled server Script, then starts clients of players already added.
function Sim:StartServer()
	if self.started then
		return
	end
	self.started = true
	self.runtime:startServerScripts()
	self.sched:flush()
	for _, p in table.clone(self.players.order) do
		self.players:_scheduleClientStart(p)
	end
	self.sched:flush()
end

function Sim:Time(): number
	return self.sched.clock
end

function Sim:Flush()
	self.sched:flush()
end

local function clientFilter(ctx)
	return ctx.kind == "client"
end

-- Advances one frame: RenderStepped (clients), PreAnimation + the emulated Animator
-- (rigged characters), Stepped/PreSimulation, simulation systems (walking, joints of rigged
-- characters, tweens), Heartbeat, then due timers (task.wait/delay); deferred work flushes in
-- between.
function Sim:Step(dt: number?)
	local step = dt or self.frameTime
	local sched = self.sched
	if sched.depth > 0 then
		error("RbxSim: Step/Advance cannot be called from inside a sim thread", 2)
	end
	local proxy = self.proxy
	local rs = self.runServiceReal
	sched.frame += 1
	sched.clock += step

	local render = proxy:peekSignal(rs, "RenderStepped")
	if render then
		render:FireImmediateFiltered(clientFilter, step)
	end
	local preRender = proxy:peekSignal(rs, "PreRender")
	if preRender then
		preRender:FireImmediateFiltered(clientFilter, step)
	end
	for _, ctx in table.clone(self.contexts) do
		if ctx.kind == "client" and ctx.alive and next(ctx.renderBinds) then
			local binds = {}
			for _, b in ctx.renderBinds do
				table.insert(binds, b)
			end
			table.sort(binds, function(a, b)
				if a.priority ~= b.priority then
					return a.priority < b.priority
				end
				return a.seq < b.seq
			end)
			for _, b in binds do
				local co = coroutine.create(b.fn)
				sched:tag(co, ctx, b.script)
				sched:resume(co, step)
			end
		end
	end
	sched:flush()

	local preAnimation = proxy:peekSignal(rs, "PreAnimation")
	if preAnimation then
		preAnimation:FireImmediate(step)
	end
	self.rigs:animate(sched.frame)
	sched:flush()

	local stepped = proxy:peekSignal(rs, "Stepped")
	if stepped then
		stepped:FireImmediate(sched.clock, step)
	end
	local pre = proxy:peekSignal(rs, "PreSimulation")
	if pre then
		pre:FireImmediate(step)
	end
	sched:flush()

	self.players:update(step)
	self.rigs:solve()
	self.tweens:update(step)
	self.input:update()
	sched:flush()

	local hb = proxy:peekSignal(rs, "Heartbeat")
	if hb then
		hb:FireImmediate(step)
	end
	local post = proxy:peekSignal(rs, "PostSimulation")
	if post then
		post:FireImmediate(step)
	end
	sched:flush()

	sched:runTimers()
	sched:flush()
end

-- Advances virtual time by `seconds` in frames of `step` (default frameTime).
function Sim:Advance(seconds: number, step: number?)
	local frame = step or self.frameTime
	local target = self.sched.clock + seconds
	while self.sched.clock < target - 1e-9 do
		self:Step(math.min(frame, target - self.sched.clock))
	end
end

-- Steps until predicate() is truthy or timeout elapses. Returns the result.
function Sim:WaitFor(predicate, timeout: number?, step: number?)
	local limit = self.sched.clock + (timeout or 10)
	local r = predicate()
	while not r and self.sched.clock < limit - 1e-9 do
		self:Step(step)
		r = predicate()
	end
	return r
end

-- Runs fn inside a sim thread of the given context (nil/"server" or a Player),
-- advancing time until it finishes. Errors are re-raised in the caller.
function Sim:Run(fn, who, timeout: number?)
	local ctx = self:_ctxFor(who)
	if not ctx.alive then
		error("RbxSim: the " .. ctx.name .. " context is no longer running (player left?)", 2)
	end
	local sched = self.sched
	local done, results = false, nil
	local co = coroutine.create(function()
		results = table.pack(xpcall(fn, function(e)
			return e
		end))
		done = true
	end)
	sched:tag(co, ctx, nil)
	sched:resume(co)
	sched:flush()
	local limit = sched.clock + (timeout or 30)
	while not done and sched.clock < limit - 1e-9 and coroutine.status(co) ~= "dead" do
		self:Step()
	end
	if not done then
		if coroutine.status(co) == "dead" then
			error("RbxSim: sim:Run thread was stopped (its context ended)", 2)
		end
		sched:kill(co)
		error(string.format("RbxSim: sim:Run timed out after %gs", timeout or 30), 2)
	end
	if not results[1] then
		error(results[2], 2)
	end
	return table.unpack(results, 2, results.n)
end

-- The global environment of a context (TweenInfo, RaycastParams, Random, typeof ...).
function Sim:Env(who)
	return self:_ctxFor(who).env
end

-- Roblox-style typeof (proxies -> "Instance", signals -> "RBXScriptSignal", ...).
function Sim:Typeof(v): string
	return self.serverCtx.env.typeof(v)
end

-- The _G table of a context (server by default, or a player's client).
function Sim:Globals(who)
	return self:_ctxFor(who).G
end

-- Name of a context ("server" or "client:<Name>"), e.g. for sim:Output(name).
function Sim:ContextName(who): string
	return self:_ctxFor(who).name
end

-- Requires a ModuleScript in a context (server by default), e.g. to read config.
function Sim:Require(module, who)
	local ctx = self:_ctxFor(who)
	return self:Run(function()
		return self.runtime:require(module, ctx)
	end, who)
end

-- Runs BindToClose callbacks (and kicks players) like a server shutdown.
function Sim:Shutdown(opts)
	opts = opts or {}
	local timeout = opts.timeout or 30
	local sched = self.sched
	local pending = 0
	for _, cb in table.clone(self.bindToClose) do
		pending += 1
		local co = coroutine.create(function()
			local ok, err = xpcall(cb.fn, function(e)
				return { msg = Util.cleanError(e), tb = debug.traceback(Util.cleanError(e), 2) }
			end)
			if not ok then
				self:_recordError(cb.ctx, err.msg, err.tb)
			end
			pending -= 1
		end)
		sched:tag(co, cb.ctx, cb.script)
		sched:resume(co)
	end
	if opts.kickPlayers ~= false then
		for _, p in table.clone(self.players.order) do
			self.players:remove(p)
		end
	end
	sched:flush()
	local start = sched.clock
	while pending > 0 and sched.clock - start < timeout - 1e-9 do
		self:Step()
	end
	return { completed = pending == 0, elapsed = sched.clock - start, pending = pending }
end

-- Players --------------------------------------------------------------------------------------------

-- opts: UserId, Name, DisplayName, device ("desktop"|"phone"|"tablet"|"console"),
--       viewport (Vector2), clientDelay, characterDelay, AccountAge, MembershipType
function Sim:AddPlayer(opts)
	Rigs.validate(opts or {})
	return self.proxy:wrap(self.players:add(opts))
end

-- Rigged characters (AddPlayer{ rig = "R15" | "R6" }): the pose the emulated Animator writes
-- every frame, joint name -> Transform (joint space); joints not listed get identity. nil
-- clears it (everything identity, "idle").
function Sim:SetAnimatorPose(player, poses)
	self.rigs:setPose(self:_playerReal(player), poses)
end

-- Every `everyN`-th frame the emulated Animator of this player's rig skips its write
-- (Animator.EvaluationThrottled = true for that frame); nil turns throttling off.
function Sim:ThrottleAnimator(player, everyN: number?)
	self.rigs:setThrottle(self:_playerReal(player), everyN)
end

function Sim:RemovePlayer(player)
	self.players:remove(self:_playerReal(player))
end

function Sim:GetPlayers()
	return self.players:list()
end

function Sim:LoadCharacter(player)
	local real = self:_playerReal(player)
	local char = self.players:loadCharacter(real)
	self.sched:flush()
	return self.proxy:wrap(char)
end

function Sim:GetCharacter(player)
	return self.proxy:toScript(self:_playerReal(player).Character)
end

function Sim:GetHumanoid(player)
	local char = self:_playerReal(player).Character
	return char and self.proxy:toScript(char:FindFirstChildOfClass("Humanoid")) or nil
end

function Sim:GetRoot(player)
	local char = self:_playerReal(player).Character
	return char and self.proxy:toScript(char:FindFirstChild("HumanoidRootPart")) or nil
end

function Sim:KillCharacter(player)
	local real = self:_playerReal(player)
	local char = real.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum == nil then
		error("RbxSim: player has no character/humanoid", 2)
	end
	self.players:setHealth(hum, 0)
	self.sched:flush()
end

-- Moves a player's character so its root is at the given CFrame / Vector3.
function Sim:Teleport(player, target)
	local real = self:_playerReal(player)
	local char = real.Character
	if char == nil then
		error("RbxSim: player has no character", 2)
	end
	local cf = target
	if typeof(target) == "Vector3" then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		cf = CFrame.new(target) * (hrp and hrp.CFrame.Rotation or CFrame.identity)
	end
	self.world:pivotTo(char, cf)
	self.sched:flush()
end

-- Walks the character to a position with Humanoid:MoveTo at WalkSpeed.
function Sim:WalkTo(player, pos, timeout: number?)
	local real = self:_playerReal(player)
	local char = real.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum == nil then
		error("RbxSim: player has no humanoid", 2)
	end
	self.players:humanoidMoveTo(hum, pos)
	self:WaitFor(function()
		return not self.players:isWalking(hum)
	end, timeout or 10)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local p = hrp.CFrame.Position
	return (Vector2.new(p.X, p.Z) - Vector2.new(pos.X, pos.Z)).Magnitude < 0.1
end

function Sim:SetDevice(player, device)
	local st = self.players.state[self:_playerReal(player)]
	local profile = Players.DEVICES[device]
	if profile == nil then
		error("RbxSim: unknown device " .. tostring(device), 2)
	end
	st.device = table.clone(profile)
	st.device.name = device
	st.device.viewport = nil
	st.viewport = Vector2.new(profile.viewport[1], profile.viewport[2])
end

function Sim:SetViewport(player, size)
	self.players.state[self:_playerReal(player)].viewport = size
end

-- Remotes ---------------------------------------------------------------------------------------------

function Sim:_resolveRemote(remote)
	if type(remote) == "string" then
		local rs = self.real:FindFirstChildOfClass("ReplicatedStorage")
		local found = rs and rs:FindFirstChild(remote, true) or self.real:FindFirstChild(remote, true)
		if found == nil then
			error("RbxSim: no remote named '" .. remote .. "'", 3)
		end
		return self.proxy:wrap(found)
	end
	local real = self.proxy:toReal(remote)
	if real == nil then
		error("RbxSim: remote instance or name expected", 3)
	end
	return self.proxy:wrap(real)
end

-- Fires a RemoteEvent as if the player's client did it.
function Sim:FireServer(player, remote, ...)
	local r = self:_resolveRemote(remote)
	local args = table.pack(...)
	self:Run(function()
		r:FireServer(table.unpack(args, 1, args.n))
	end, player)
end

-- Invokes a RemoteFunction as the player's client; returns the server's results.
function Sim:InvokeServer(player, remote, ...)
	local r = self:_resolveRemote(remote)
	local args = table.pack(...)
	return self:Run(function()
		return r:InvokeServer(table.unpack(args, 1, args.n))
	end, player)
end

local function matchesEvent(self, e, player, name)
	if player ~= nil and e.player ~= self.proxy:wrap(self.proxy:toReal(player)) then
		return false
	end
	if name ~= nil and e.name ~= name then
		return false
	end
	return true
end

function Sim:ClientEventsFor(player, remoteName: string?)
	local out = {}
	for _, e in self.ClientEvents do
		if matchesEvent(self, e, player, remoteName) then
			table.insert(out, e)
		end
	end
	return out
end

function Sim:ServerEventsFor(player, remoteName: string?)
	local out = {}
	for _, e in self.ServerEvents do
		if matchesEvent(self, e, player, remoteName) then
			table.insert(out, e)
		end
	end
	return out
end

-- Returns the args (packed table) of the last FireClient for player+remote, and the entry.
function Sim:LastClientEvent(player, remoteName: string?)
	for i = #self.ClientEvents, 1, -1 do
		local e = self.ClientEvents[i]
		if matchesEvent(self, e, player, remoteName) then
			return e.args, e
		end
	end
	return nil, nil
end

-- Input / GUI ------------------------------------------------------------------------------------------

function Sim:_guiClickable(playerReal, real)
	local st = self.players.state[playerReal]
	local pg = playerReal:FindFirstChildOfClass("PlayerGui")
	if not (pg and real:IsDescendantOf(pg)) and not real:IsDescendantOf(self.workspaceReal) then
		return false, "not inside the player's PlayerGui"
	end
	local cur = real
	while cur ~= nil and cur ~= pg do
		if cur:IsA("GuiObject") then
			if cur.Visible == false then
				return false, Util.fullName(cur) .. " is not Visible"
			end
			local ok, interactable = pcall(function()
				return cur.Interactable
			end)
			if ok and interactable == false then
				return false, Util.fullName(cur) .. " is not Interactable"
			end
		elseif cur:IsA("LayerCollector") then
			if cur.Enabled == false then
				return false, Util.fullName(cur) .. " is not Enabled"
			end
			break
		end
		cur = cur.Parent
	end
	local pos, size = Members.absRect(self, real)
	if size.X <= 0 or size.Y <= 0 then
		return false, "button has zero AbsoluteSize"
	end
	local vp = st and st.viewport or DEFAULT_VIEWPORT
	if pos.X + size.X <= 0 or pos.Y + size.Y <= 0 or pos.X >= vp.X or pos.Y >= vp.Y then
		return false, string.format("button is off-screen at %s (viewport %s)", tostring(pos), tostring(vp))
	end
	return true, nil
end

-- Clicks/taps a GuiButton as the player (fires Down/Up/Click/Activated in its client).
function Sim:Click(player, button, opts)
	opts = opts or {}
	local playerReal = self:_playerReal(player)
	local real = self.proxy:toReal(button)
	if real == nil or not real:IsA("GuiButton") then
		error("RbxSim: GuiButton expected", 2)
	end
	local st = self.players.state[playerReal]
	if st == nil or st.removed then
		error("RbxSim: player is not in the game", 2)
	end
	if not opts.force then
		local ok, why = self:_guiClickable(playerReal, real)
		if not ok then
			error("RbxSim: cannot click " .. Util.fullName(real) .. ": " .. tostring(why), 2)
		end
	end
	local ctx = st.ctx
	local filter = function(c)
		return c == ctx
	end
	local pos, size = Members.absRect(self, real)
	local cx, cy = pos.X + size.X / 2, pos.Y + size.Y / 2
	local touch = st.device.TouchEnabled
	local io = self.input:makeInputObject({
		UserInputType = if touch then Enum.UserInputType.Touch else Enum.UserInputType.MouseButton1,
		UserInputState = Enum.UserInputState.End,
		Position = Vector2.new(cx, cy),
	})
	local proxy = self.proxy
	proxy:fireFiltered(real, "MouseButton1Down", filter, cx, cy)
	proxy:fireFiltered(real, "MouseButton1Up", filter, cx, cy)
	proxy:fireFiltered(real, "MouseButton1Click", filter)
	proxy:fireFiltered(real, "Activated", filter, io, 1)
	self.sched:flush()
end

-- Returns (ok, reason) whether the button could be clicked right now.
function Sim:CanClick(player, button)
	return self:_guiClickable(self:_playerReal(player), self.proxy:toReal(button))
end

-- Types into a TextBox as the player (Focused, Text, FocusLost(enterPressed)).
function Sim:TypeText(player, textbox, text: string, enterPressed: boolean?)
	local real = self.proxy:toReal(textbox)
	self:Run(function()
		self.input:focusTextBox(real, true)
		self.proxy:setProperty(real, "Text", text)
		self.input:focusTextBox(real, false, enterPressed ~= false)
	end, player)
end

function Sim:PressKey(player, keyCode, opts)
	self.input:pressKey(self:_playerReal(player), keyCode, opts)
end

function Sim:ReleaseKey(player, keyCode)
	self.input:keyEvent(self:_playerReal(player), keyCode, false)
	self.sched:flush()
end

function Sim:Tap(player, position)
	self.input:tap(self:_playerReal(player), position)
end

function Sim:MouseClick(player)
	self.input:mouseClick(self:_playerReal(player))
end

-- Fires a UserInputService event for one client: spec = { KeyCode, UserInputType, UserInputState, Position }.
function Sim:FireInput(player, event: string, spec, gameProcessed: boolean?)
	local playerReal = self:_playerReal(player)
	if event == "TouchTap" then
		self.input:fireUIS(playerReal, event, spec or { Vector2.new(100, 100) }, gameProcessed == true)
	else
		self.input:fireUIS(playerReal, event, self.input:makeInputObject(spec or {}), gameProcessed == true)
	end
	self.sched:flush()
end

function Sim:TriggerAction(player, name: string, state, inputObject)
	return self.input:triggerAction(self:_playerReal(player), name, state, inputObject)
end

-- Proximity prompts --------------------------------------------------------------------------------------

function Sim:CanUsePrompt(player, prompt, opts)
	return self.input:canUsePrompt(self:_playerReal(player), self.proxy:toReal(prompt), opts)
end

-- Starts holding a prompt (non-blocking). opts: ignoreDistance, ignoreEnabled.
function Sim:BeginHold(player, prompt, opts)
	return self.input:beginHold(self:_playerReal(player), self.proxy:toReal(prompt), opts)
end

function Sim:ReleasePrompt(player, prompt)
	return self.input:releaseHold(self:_playerReal(player), self.proxy:toReal(prompt))
end

-- Holds a prompt for `seconds` (default HoldDuration + one frame) while time advances.
-- Returns (triggered, cancelReason). opts.release=false keeps holding afterwards.
function Sim:HoldPrompt(player, prompt, seconds: number?, opts)
	opts = opts or {}
	local promptReal = self.proxy:toReal(prompt)
	local hold = self:BeginHold(player, prompt, opts)
	if not hold.active then
		return false, hold.cancelReason
	end
	local duration = seconds or (promptReal.HoldDuration + self.frameTime)
	self:Advance(duration, opts.step)
	local triggered = hold.triggered
	if hold.active and opts.release ~= false then
		self.input:releaseHold(hold.player, hold.prompt)
	end
	return triggered, hold.cancelReason
end

-- Tools / physics ------------------------------------------------------------------------------------------

function Sim:EquipTool(player, tool)
	local real = self:_playerReal(player)
	local char = real.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum == nil then
		error("RbxSim: player has no humanoid", 2)
	end
	local toolReal
	if type(tool) == "string" then
		local bp = real:FindFirstChildOfClass("Backpack")
		toolReal = (bp and bp:FindFirstChild(tool)) or char:FindFirstChild(tool)
	else
		toolReal = self.proxy:toReal(tool)
	end
	if toolReal == nil then
		error("RbxSim: tool not found: " .. tostring(tool), 2)
	end
	if toolReal.Parent ~= char then
		self.players:equipTool(hum, toolReal)
	end
	self.sched:flush()
	return self.proxy:wrap(toolReal)
end

function Sim:UnequipTools(player)
	local char = self:_playerReal(player).Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		self.players:unequipTools(hum)
	end
	self.sched:flush()
end

-- Simulates a click with the equipped tool (Activated then Deactivated).
function Sim:ActivateTool(player, tool)
	local char = self:_playerReal(player).Character
	local toolReal = tool and self.proxy:toReal(tool) or (char and char:FindFirstChildOfClass("Tool"))
	if toolReal == nil or toolReal.Parent ~= char then
		error("RbxSim: no equipped tool to activate", 2)
	end
	if toolReal.ManualActivationOnly then
		return false
	end
	local ok = self.players:activateTool(toolReal)
	self.sched:flush()
	self.players:deactivateTool(toolReal)
	self.sched:flush()
	return ok
end

-- Fires Touched on both parts (no physics contact detection exists).
function Sim:Touch(part, other)
	local a, b = self.proxy:toReal(part), self.proxy:toReal(other)
	self.proxy:fire(a, "Touched", self.proxy:wrap(b))
	self.proxy:fire(b, "Touched", self.proxy:wrap(a))
	self.sched:flush()
end

-- handler(origin, direction, params, defaultRaycast) -> RaycastResult-like table or nil.
function Sim:SetRaycastHandler(handler)
	self.world.raycastHandler = handler
end

-- Instances --------------------------------------------------------------------------------------------

function Sim:Wrap(real)
	return self.proxy:wrap(real)
end

function Sim:Unwrap(v)
	return self.proxy:unwrap(v)
end

-- Finds an instance by dotted/slashed path from game, e.g. "ReplicatedStorage.Remotes.Fish".
function Sim:Find(path: string, root)
	local cur = root and self.proxy:toReal(root) or self.real
	for part in string.gmatch(path, "[^%./]+") do
		cur = cur:FindFirstChild(part)
		if cur == nil then
			return nil
		end
	end
	return self.proxy:wrap(cur)
end

-- Finds an instance under a player's PlayerGui, e.g. sim:Gui(p, "HUD.Money").
function Sim:Gui(player, path: string)
	local pg = self:_playerReal(player):FindFirstChildOfClass("PlayerGui")
	return self:Find(path, pg)
end

-- Creates a Script/LocalScript/ModuleScript with Source under parent.
function Sim:AddScript(parent, className: string, name: string, source: string, props)
	local real = roblox.Instance.new(className)
	real.Name = name
	if real:IsA("LuaSourceContainer") then
		real.Source = source or ""
	end
	for k, v in props or {} do
		real[k] = v
	end
	local p = self.proxy:toReal(parent)
	if p then
		self.proxy:setParent(real, p)
		self.sched:flush()
	end
	return self.proxy:wrap(real)
end

-- Creates an instance with properties (raw construction, no events) and parents it.
function Sim:Create(className: string, props, parent)
	local real = roblox.Instance.new(className)
	for k, v in props or {} do
		if k ~= "Parent" then
			real[k] = self.proxy:unwrap(v)
		end
	end
	local p = parent or (props and props.Parent)
	if p then
		self.proxy:setParent(real, self.proxy:toReal(p))
	end
	return self.proxy:wrap(real)
end

-- Diagnostics --------------------------------------------------------------------------------------------

function Sim:FormatErrors(): string
	local lines = {}
	for i, e in self.Errors do
		table.insert(lines, string.format("#%d [t=%.3f][%s] %s", i, e.time, e.context, e.message))
		if e.traceback and e.traceback ~= "" and e.traceback ~= e.message then
			for line in string.gmatch(e.traceback, "[^\n]+") do
				if line ~= e.message then
					table.insert(lines, "    " .. line)
				end
			end
		end
	end
	return table.concat(lines, "\n")
end

-- Throws if any script error was captured (opts.warnings=true also fails on warnings).
function Sim:AssertNoErrors(opts)
	opts = opts or {}
	local problems = {}
	if #self.Errors > 0 then
		table.insert(problems, string.format("%d script error(s):\n%s", #self.Errors, self:FormatErrors()))
	end
	if opts.warnings and #self.Warnings > 0 then
		local w = {}
		for _, e in self.Warnings do
			table.insert(w, string.format("  [t=%.3f][%s] %s", e.time, e.context, e.message))
		end
		table.insert(problems, string.format("%d warning(s):\n%s", #self.Warnings, table.concat(w, "\n")))
	end
	if #problems > 0 then
		error(table.concat(problems, "\n"), 2)
	end
end

function Sim:ClearErrors()
	table.clear(self.Errors)
	table.clear(self.Warnings)
end

local function connFilter(self, filter)
	if filter == nil then
		return function()
			return true
		end
	end
	if type(filter) == "function" then
		return filter
	end
	if type(filter) == "string" then
		return function(conn)
			return conn.ctx.kind == filter or conn.ctx.name == filter
		end
	end
	local ctx = self:_ctxFor(filter)
	return function(conn)
		return conn.ctx == ctx
	end
end

-- Number of live connections. filter: nil | "server" | "client" | ctx name |
-- Player | function(conn) -> bool (conn has .ctx, .signal, .script).
function Sim:CountConnections(filter): number
	if filter == nil then
		return self.connectionCount
	end
	local f = connFilter(self, filter)
	local n = 0
	for conn in self.connections do
		if f(conn) then
			n += 1
		end
	end
	return n
end

-- Live connections grouped by signal/context/script, largest first.
function Sim:ConnectionReport(filter)
	local f = connFilter(self, filter)
	local groups = {}
	for conn in self.connections do
		if f(conn) then
			local key = conn.signal:describe()
				.. "|"
				.. conn.ctx.name
				.. "|"
				.. (conn.script and Util.fullName(conn.script) or "-")
			local g = groups[key]
			if g == nil then
				g = {
					signal = conn.signal:describe(),
					context = conn.ctx.name,
					script = conn.script and Util.fullName(conn.script) or nil,
					count = 0,
				}
				groups[key] = g
			end
			g.count += 1
		end
	end
	local list = {}
	for _, g in groups do
		table.insert(list, g)
	end
	table.sort(list, function(a, b)
		if a.count ~= b.count then
			return a.count > b.count
		end
		return a.signal < b.signal
	end)
	return list
end

function Sim:FormatConnections(filter): string
	local lines = {}
	for _, g in self:ConnectionReport(filter) do
		table.insert(lines, string.format("%4d  %s  [%s]  %s", g.count, g.signal, g.context, g.script or ""))
	end
	return table.concat(lines, "\n")
end

-- Prints captured logs (for debugging a failing test).
function Sim:PrintLogs(filterKind: string?)
	for _, e in self.Logs do
		if filterKind == nil or e.kind == filterKind then
			print(string.format("[%8.3f][%s][%s] %s", e.time, e.context, e.kind, e.message))
		end
	end
end

-- Messages printed by scripts (optionally only from one context name).
function Sim:Output(contextName: string?): { string }
	local out = {}
	for _, e in self.Logs do
		if e.kind == "print" and (contextName == nil or e.context == contextName) then
			table.insert(out, e.message)
		end
	end
	return out
end

return Sim
