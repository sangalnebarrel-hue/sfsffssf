-- remotes.luau: RemoteEvent / RemoteFunction / Bindable delivery between
-- contexts, with Roblox-like argument copying and event queueing.

local Serialize = require("./serialize")

local Remotes = {}
Remotes.__index = Remotes

local function serverFilter(ctx)
	return ctx.kind == "server"
end

function Remotes.new(sim)
	local self = setmetatable({}, Remotes)
	self.sim = sim
	self.serverQueue = {} -- remote -> list of { player, args }
	self.clientQueue = {} -- remote -> { [ctx] = list of args }
	self.serverInvoke = {} -- remote -> { fn, ctx, script }
	self.clientInvoke = {} -- remote -> { [ctx] = { fn, ctx, script } }
	self.bindableInvoke = {} -- bindable -> { [ctx] = { fn, ctx, script } }
	self.callbackWaiters = {} -- remote/bindable -> list of { token, ctx }
	return self
end

local function requireKind(ctx, kind: string, message: string)
	if ctx.kind ~= kind then
		error(message, 0)
	end
end

local function playerArg(sim, player, method: string)
	local real = sim.proxy:toReal(player)
	if real == nil or real.ClassName ~= "Player" then
		error(method .. ": Argument 1 must be a Player", 0)
	end
	return real
end

function Remotes:_later(fn)
	local latency = self.sim.opts.remoteLatency or 0
	if latency > 0 then
		self.sim.sched:after(latency, fn)
	else
		fn()
	end
end

-- RemoteEvent -------------------------------------------------------------------------------

function Remotes:fireServer(real, ...)
	local sim = self.sim
	local ctx = sim.sched:context()
	requireKind(ctx, "client", "FireServer can only be called from the client")
	local args = Serialize.remoteArgs(sim, "toServer", nil, ...)
	local player = sim.proxy:wrap(ctx.player)
	table.insert(sim.ServerEvents, {
		time = sim.sched.clock,
		player = player,
		remote = sim.proxy:wrap(real),
		name = real.Name,
		args = args,
	})
	self:_later(function()
		local sig = sim.proxy:getSignal(real, "OnServerEvent")
		if sig:HasConnectionsFor(serverFilter) then
			sig:FireFiltered(serverFilter, player, table.unpack(args, 1, args.n))
		else
			local q = self.serverQueue[real]
			if q == nil then
				q = {}
				self.serverQueue[real] = q
			end
			table.insert(q, { player = player, args = args })
		end
	end)
end

function Remotes:flushServerQueue(real)
	local q = self.serverQueue[real]
	if q == nil then
		return
	end
	self.serverQueue[real] = nil
	local sig = self.sim.proxy:getSignal(real, "OnServerEvent")
	for _, item in q do
		sig:FireFiltered(serverFilter, item.player, table.unpack(item.args, 1, item.args.n))
	end
end

function Remotes:_deliverClient(real, ctx, args)
	local sim = self.sim
	self:_later(function()
		if not ctx.alive then
			return
		end
		local filter = function(c)
			return c == ctx
		end
		local sig = sim.proxy:getSignal(real, "OnClientEvent")
		if sig:HasConnectionsFor(filter) then
			sig:FireFiltered(filter, table.unpack(args, 1, args.n))
		else
			local perRemote = self.clientQueue[real]
			if perRemote == nil then
				perRemote = setmetatable({}, { __mode = "k" })
				self.clientQueue[real] = perRemote
			end
			local q = perRemote[ctx]
			if q == nil then
				q = {}
				perRemote[ctx] = q
			end
			table.insert(q, args)
		end
	end)
end

function Remotes:flushClientQueue(real, ctx)
	local perRemote = self.clientQueue[real]
	local q = perRemote and perRemote[ctx]
	if q == nil then
		return
	end
	perRemote[ctx] = nil
	local filter = function(c)
		return c == ctx
	end
	local sig = self.sim.proxy:getSignal(real, "OnClientEvent")
	for _, args in q do
		sig:FireFiltered(filter, table.unpack(args, 1, args.n))
	end
end

function Remotes:_fireClient(real, playerReal, ...)
	local sim = self.sim
	local st = sim.players.state[playerReal]
	if st == nil or st.removed then
		return
	end
	local args = Serialize.remoteArgs(sim, "toClient", st.ctx, ...)
	table.insert(sim.ClientEvents, {
		time = sim.sched.clock,
		player = sim.proxy:wrap(playerReal),
		remote = sim.proxy:wrap(real),
		name = real.Name,
		args = args,
	})
	self:_deliverClient(real, st.ctx, args)
end

function Remotes:fireClient(real, player, ...)
	local sim = self.sim
	requireKind(sim.sched:context(), "server", "FireClient can only be called from the server")
	self:_fireClient(real, playerArg(sim, player, "FireClient"), ...)
end

function Remotes:fireAllClients(real, ...)
	local sim = self.sim
	requireKind(sim.sched:context(), "server", "FireAllClients can only be called from the server")
	for _, p in table.clone(sim.players.order) do
		self:_fireClient(real, p, ...)
	end
end

-- Callbacks -----------------------------------------------------------------------------------

function Remotes:_wakeCallbackWaiters(real)
	local list = self.callbackWaiters[real]
	if list == nil then
		return
	end
	self.callbackWaiters[real] = nil
	for _, w in list do
		self.sim.sched:wake(w.token, false)
	end
end

function Remotes:_waitForCallback(real, getter)
	local sched = self.sim.sched
	local cb = getter()
	local warned = false
	while cb == nil do
		local list = self.callbackWaiters[real]
		if list == nil then
			list = {}
			self.callbackWaiters[real] = list
		end
		local token = {}
		table.insert(list, { token = token })
		if not warned then
			warned = true
			local ctx = sched:context()
			local name = self.sim.util.fullName(real)
			sched:after(5, function()
				if sched:isWaiting(token) then
					self.sim:_warn(ctx, string.format("Infinite yield possible waiting for a callback on %s", name))
				end
			end, ctx)
		end
		sched:suspend(token)
		cb = getter()
	end
	return cb
end

local function callbackRecord(sim, fn, what: string)
	if fn ~= nil and type(fn) ~= "function" then
		error(what .. " must be a function or nil", 0)
	end
	if fn == nil then
		return nil
	end
	local sched = sim.sched
	return { fn = fn, ctx = sched:context(), script = sched:script() }
end

function Remotes:setServerInvoke(real, fn)
	requireKind(self.sim.sched:context(), "server", "OnServerInvoke can only be set on the server")
	self.serverInvoke[real] = callbackRecord(self.sim, fn, "OnServerInvoke")
	self:_wakeCallbackWaiters(real)
end

function Remotes:setClientInvoke(real, fn)
	local ctx = self.sim.sched:context()
	requireKind(ctx, "client", "OnClientInvoke can only be set on the client")
	local per = self.clientInvoke[real]
	if per == nil then
		per = setmetatable({}, { __mode = "k" })
		self.clientInvoke[real] = per
	end
	per[ctx] = callbackRecord(self.sim, fn, "OnClientInvoke")
	self:_wakeCallbackWaiters(real)
end

-- Runs a callback in its own context and suspends the caller until it returns.
function Remotes:_call(cb, invokingCtx, ...)
	local sim = self.sim
	local sched = sim.sched
	local args = table.pack(...)
	local token = {}
	local co = coroutine.create(function()
		local r = table.pack(pcall(cb.fn, table.unpack(args, 1, args.n)))
		self:_later(function()
			sched:wake(token, false, r)
		end)
	end)
	sched:tag(co, cb.ctx, cb.script)
	if invokingCtx then
		invokingCtx.invokeTokens[token] = true
	end
	self:_later(function()
		table.insert(sched.deferred, { kind = "resume", co = co, args = { n = 0 } })
	end)
	local r = sched:suspend(token)
	if invokingCtx then
		invokingCtx.invokeTokens[token] = nil
	end
	if not r[1] then
		error(r[2], 0)
	end
	return r
end

function Remotes:invokeServer(real, ...)
	local sim = self.sim
	local ctx = sim.sched:context()
	requireKind(ctx, "client", "InvokeServer can only be called from the client")
	local args = Serialize.remoteArgs(sim, "toServer", nil, ...)
	local player = sim.proxy:wrap(ctx.player)
	table.insert(sim.ServerEvents, {
		time = sim.sched.clock,
		player = player,
		remote = sim.proxy:wrap(real),
		name = real.Name,
		args = args,
		invoke = true,
	})
	local cb = self:_waitForCallback(real, function()
		return self.serverInvoke[real]
	end)
	local r = self:_call(cb, nil, player, table.unpack(args, 1, args.n))
	local out = Serialize.remoteArgs(sim, "toClient", ctx, table.unpack(r, 2, r.n))
	return table.unpack(out, 1, out.n)
end

function Remotes:invokeClient(real, player, ...)
	local sim = self.sim
	requireKind(sim.sched:context(), "server", "InvokeClient can only be called from the server")
	local playerReal = playerArg(sim, player, "InvokeClient")
	local st = sim.players.state[playerReal]
	if st == nil or st.removed or not st.ctx.alive then
		error("InvokeClient: player has left the game", 0)
	end
	local target = st.ctx
	local args = Serialize.remoteArgs(sim, "toClient", target, ...)
	table.insert(sim.ClientEvents, {
		time = sim.sched.clock,
		player = sim.proxy:wrap(playerReal),
		remote = sim.proxy:wrap(real),
		name = real.Name,
		args = args,
		invoke = true,
	})
	local cb = self:_waitForCallback(real, function()
		if not target.alive then
			error("InvokeClient: player has left the game", 0)
		end
		local per = self.clientInvoke[real]
		return per and per[target]
	end)
	local r = self:_call(cb, target, table.unpack(args, 1, args.n))
	local out = Serialize.remoteArgs(sim, "toServer", nil, table.unpack(r, 2, r.n))
	return table.unpack(out, 1, out.n)
end

-- Bindables (same-context only, like Roblox) -------------------------------------------------

function Remotes:fireBindable(real, ...)
	local sim = self.sim
	local ctx = sim.sched:context()
	local args = Serialize.remoteArgs(sim, "bindable", nil, ...)
	sim.proxy:fireFiltered(real, "Event", function(c)
		return c == ctx
	end, table.unpack(args, 1, args.n))
end

function Remotes:setBindableInvoke(real, fn)
	local ctx = self.sim.sched:context()
	local per = self.bindableInvoke[real]
	if per == nil then
		per = setmetatable({}, { __mode = "k" })
		self.bindableInvoke[real] = per
	end
	per[ctx] = callbackRecord(self.sim, fn, "OnInvoke")
	self:_wakeCallbackWaiters(real)
end

function Remotes:invokeBindable(real, ...)
	local sim = self.sim
	local ctx = sim.sched:context()
	local args = Serialize.remoteArgs(sim, "bindable", nil, ...)
	local cb = self:_waitForCallback(real, function()
		local per = self.bindableInvoke[real]
		return per and per[ctx]
	end)
	local r = table.pack(pcall(cb.fn, table.unpack(args, 1, args.n)))
	if not r[1] then
		error(r[2], 0)
	end
	local out = Serialize.remoteArgs(sim, "bindable", nil, table.unpack(r, 2, r.n))
	return table.unpack(out, 1, out.n)
end

-- Called when a client context dies: fail any server InvokeClient waiting on it.
function Remotes:onContextKilled(ctx)
	for token in ctx.invokeTokens do
		self.sim.sched:wake(token, false, table.pack(false, "InvokeClient: player has left the game"))
	end
	ctx.invokeTokens = {}
end

return Remotes
