-- runtime.luau: runs Scripts / LocalScripts in their contexts and implements
-- instance-based require() with a per-context module cache.

local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Util = require("./util")

local Enum = roblox.Enum

local Runtime = {}
Runtime.__index = Runtime

function Runtime.new(sim)
	local self = setmetatable({}, Runtime)
	self.sim = sim
	self.records = setmetatable({}, { __mode = "k" }) -- raw script -> record
	self.bytecode = {} -- source -> bytecode
	self.loadingIn = setmetatable({}, { __mode = "k" }) -- thread -> module entry it is loading
	self.waitingOn = setmetatable({}, { __mode = "k" }) -- thread -> module entry it waits for
	self.batchDepth = 0
	self.pending = {}
	return self
end

function Runtime:record(s)
	local rec = self.records[s]
	if rec == nil then
		rec = {
			ran = setmetatable({}, { __mode = "k" }),
			threads = setmetatable({}, { __mode = "k" }),
			conns = {},
			dead = false,
		}
		self.records[s] = rec
	end
	return rec
end

function Runtime:_trackThread(script, co)
	self:record(script).threads[co] = true
end

function Runtime:_trackConn(script, conn, added: boolean)
	local rec = self:record(script)
	rec.conns[conn] = if added then true else nil
end

function Runtime:isScriptDead(script): boolean
	local rec = self.records[script]
	return rec ~= nil and rec.dead
end

-- Compiles a script's Source (bytecode cached by source text).
function Runtime:compile(s, env)
	local source = s.Source
	local name = Util.fullName(s)
	local bc = self.bytecode[source]
	if bc == nil then
		local ok, res = pcall(luau.compile, source)
		if not ok then
			local msg = Util.cleanError(res)
			msg = string.gsub(msg, "^syntax error: ", "")
			error(name .. ":" .. msg, 0)
		end
		bc = res
		self.bytecode[source] = bc
	end
	return luau.load(bc, { debugName = "=" .. name, environment = env, injectGlobals = false })
end

function Runtime:_scriptEnv(s, ctx)
	return setmetatable({ script = self.sim.proxy:wrap(s) }, { __index = ctx.env })
end

-- Runs a script in a context right now (in its own thread).
function Runtime:runIn(s, ctx)
	local sim = self.sim
	local rec = self:record(s)
	rec.ran[ctx] = true
	rec.dead = false
	local ok, fn = pcall(self.compile, self, s, self:_scriptEnv(s, ctx))
	if not ok then
		sim:_recordError(ctx, Util.cleanError(fn), "", s)
		return
	end
	local co = coroutine.create(fn)
	sim.sched:tag(co, ctx, s)
	sim.sched:resume(co)
end

function Runtime:runOnce(s, ctx)
	local rec = self.records[s]
	if rec and rec.ran[ctx] then
		return
	end
	if not ctx.alive then
		return
	end
	self:runIn(s, ctx)
end

function Runtime:isDisabled(s): boolean
	local ok, v = pcall(function()
		return s.Disabled
	end)
	return ok and v == true
end

local function hasAncestorClass(s, className: string)
	return s:FindFirstAncestorOfClass(className) ~= nil
end

function Runtime:_inReplicated(s): boolean
	local game = self.sim.real
	for _, cls in { "Workspace", "ReplicatedStorage", "ReplicatedFirst" } do
		local svc = game:FindFirstChildOfClass(cls)
		if svc and s:IsDescendantOf(svc) then
			return true
		end
	end
	return false
end

-- Decides whether/where a script should run given its location (Roblox rules).
function Runtime:maybeRun(s)
	local sim = self.sim
	if not sim.started or not s:IsA("BaseScript") or self:isDisabled(s) then
		return
	end
	if not s:IsDescendantOf(sim.real) then
		return
	end
	local players = sim.players
	if s.ClassName == "LocalScript" then
		local owner = players:ownerOf(s)
		local st = owner and players.state[owner]
		if st and st.clientStarted and not st.removed then
			self:runOnce(s, st.ctx)
		end
		return
	end
	local rc = s.RunContext
	if rc == Enum.RunContext.Client then
		local owner = players:ownerOf(s)
		if owner then
			local st = players.state[owner]
			if st and st.clientStarted and not st.removed then
				self:runOnce(s, st.ctx)
			end
		elseif self:_inReplicated(s) then
			for _, p in players.order do
				local st = players.state[p]
				if st.clientStarted and not st.removed then
					self:runOnce(s, st.ctx)
				end
			end
		end
		return
	end
	if rc == Enum.RunContext.Server then
		for _, cls in { "ServerStorage", "StarterGui", "StarterPack", "StarterPlayer" } do
			if hasAncestorClass(s, cls) then
				return
			end
		end
		self:runOnce(s, sim.serverCtx)
		return
	end
	-- Legacy server Script: Workspace, ServerScriptService or a player's Backpack
	local sss = sim.real:FindFirstChildOfClass("ServerScriptService")
	if s:IsDescendantOf(sim.workspaceReal) or (sss and s:IsDescendantOf(sss)) then
		self:runOnce(s, sim.serverCtx)
		return
	end
	local bp = s:FindFirstAncestorOfClass("Backpack")
	if bp and bp.Parent and bp.Parent.ClassName == "Player" then
		self:runOnce(s, sim.serverCtx)
	end
end

function Runtime:startServerScripts()
	for _, d in self.sim.real:GetDescendants() do
		if d:IsA("Script") and d.ClassName ~= "LocalScript" and d.RunContext ~= Enum.RunContext.Client then
			self:maybeRun(d)
		end
	end
end

function Runtime:startClientRunContextScripts(ctx)
	for _, d in self.sim.real:GetDescendants() do
		if d:IsA("Script") and d.ClassName ~= "LocalScript" and d.RunContext == Enum.RunContext.Client then
			if self:_inReplicated(d) and not self:isDisabled(d) then
				self:runOnce(d, ctx)
			end
		end
	end
end

-- Called after an instance subtree was parented somewhere new.
function Runtime:onInstanceMoved(real)
	if self.batchDepth > 0 then
		-- defer until the whole batch of copies is in place
		if real:IsA("BaseScript") then
			table.insert(self.pending, real)
		end
		for _, d in real:GetDescendants() do
			if d:IsA("BaseScript") then
				table.insert(self.pending, d)
			end
		end
		return
	end
	if real:IsA("BaseScript") then
		self:maybeRun(real)
	end
	for _, d in real:GetDescendants() do
		if d:IsA("BaseScript") then
			self:maybeRun(d)
		end
	end
end

-- Runs fn while deferring script starts; scripts parented meanwhile start
-- afterwards in order (Roblox copies StarterPlayerScripts/StarterGui contents
-- completely before their LocalScripts run).
function Runtime:batch(fn)
	self.batchDepth += 1
	local ok, err = pcall(fn)
	self.batchDepth -= 1
	if self.batchDepth == 0 and #self.pending > 0 then
		local pending = self.pending
		self.pending = {}
		for _, s in pending do
			self:maybeRun(s)
		end
	end
	if not ok then
		error(err, 0)
	end
end

-- Stops a script: kills its threads and disconnects its connections.
function Runtime:stopScript(s)
	local rec = self.records[s]
	if rec == nil then
		return
	end
	rec.dead = true
	for conn in table.clone(rec.conns) do
		conn.signal:_disconnect(conn)
	end
	for co in rec.threads do
		self.sim.sched:kill(co)
	end
	table.clear(rec.threads)
end

function Runtime:setEnabled(s, enabled: boolean)
	local wasEnabled = not self:isDisabled(s)
	self.sim.proxy:setProperty(s, "Disabled", not enabled)
	if wasEnabled and not enabled then
		self:stopScript(s)
		local rec = self.records[s]
		if rec then
			rec.ran = setmetatable({}, { __mode = "k" })
		end
	elseif enabled and not wasEnabled then
		local rec = self:record(s)
		rec.dead = false
		self:maybeRun(s)
	end
end

-- require ------------------------------------------------------------------------------------

function Runtime:_wouldDeadlock(entry, co): boolean
	local t = entry.thread
	local seen = {}
	while t ~= nil and not seen[t] do
		if t == co then
			return true
		end
		seen[t] = true
		local w = self.waitingOn[t]
		t = w and w.thread
	end
	return false
end

function Runtime:_chain(co, target)
	local names = { Util.fullName(target) }
	local e = self.loadingIn[co]
	while e do
		table.insert(names, 1, Util.fullName(e.module))
		if e.module == target then
			break
		end
		e = e.parent
	end
	return table.concat(names, " -> ")
end

function Runtime:require(target, ctxOverride)
	local sim = self.sim
	local proxy = sim.proxy
	local real = proxy.realOf[target]
	if real == nil then
		if type(target) == "number" then
			error("RbxSim: require(assetId) is not supported", 2)
		end
		error("Attempted to call require with invalid argument(s).", 2)
	end
	if real.ClassName ~= "ModuleScript" then
		error("Attempted to call require with invalid argument(s).", 2)
	end
	local sched = sim.sched
	local ctx = ctxOverride or sched:context()
	if ctx.kind == "client" and proxy:isServerOnly(real) then
		error(
			string.format(
				"RbxSim: a client cannot require %s (server-only containers do not replicate)",
				Util.fullName(real)
			),
			2
		)
	end
	local cache = ctx.modules
	local co = coroutine.running()
	local entry = cache[real]
	if entry then
		if entry.state == "loading" then
			if self:_wouldDeadlock(entry, co) then
				error("Requested module was required recursively: " .. self:_chain(co, real), 2)
			end
			local token = {}
			table.insert(entry.waiters, token)
			self.waitingOn[co] = entry
			sched:suspend(token)
			self.waitingOn[co] = nil
		end
		if entry.state == "done" then
			return entry.value
		end
		error("Requested module experienced an error while loading: " .. Util.fullName(real), 2)
	end

	entry = { state = "loading", waiters = {}, thread = co, module = real, parent = self.loadingIn[co] }
	cache[real] = entry
	self.loadingIn[co] = entry
	local results
	local okCompile, fn = pcall(self.compile, self, real, self:_scriptEnv(real, ctx))
	if okCompile then
		results = table.pack(xpcall(fn, function(e)
			local msg = Util.cleanError(e)
			return { msg = msg, tb = debug.traceback(msg, 2) }
		end))
	else
		results = table.pack(false, { msg = Util.cleanError(fn), tb = "" })
	end
	self.loadingIn[co] = entry.parent
	if results[1] and results.n ~= 2 then
		results = table.pack(
			false,
			{ msg = Util.fullName(real) .. ": Module code did not return exactly one value", tb = "" }
		)
	end
	if results[1] then
		entry.state = "done"
		entry.value = results[2]
	else
		entry.state = "error"
		local err = results[2]
		if type(err) ~= "table" then
			err = { msg = tostring(err), tb = "" }
		end
		entry.err = err
		sim:_recordError(ctx, err.msg, err.tb, real)
	end
	for _, token in entry.waiters do
		sched:wake(token, false)
	end
	entry.waiters = {}
	if entry.state == "error" then
		error(
			"Requested module experienced an error while loading: "
				.. Util.fullName(real)
				.. ": "
				.. tostring(entry.err.msg),
			2
		)
	end
	return entry.value
end

return Runtime
