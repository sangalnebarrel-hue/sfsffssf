-- signal.luau: RBXScriptSignal / RBXScriptConnection emulation.
-- Scripts only ever see opaque userdata facades; the internal Signal objects
-- live inside the sim. Handlers run in the context in which :Connect was called.

local Util = require("./util")

local Signal = {}
Signal.__index = Signal

local signalOfFacade = setmetatable({}, { __mode = "k" })
local connOfFacade = setmetatable({}, { __mode = "k" })

local facadeMethods = {}

function facadeMethods.Connect(f, fn)
	local s = signalOfFacade[f]
	if s == nil then
		error("Expected ':' not '.' calling member function Connect", 2)
	end
	return s:Connect(fn, false)
end
facadeMethods.ConnectParallel = facadeMethods.Connect

function facadeMethods.Once(f, fn)
	local s = signalOfFacade[f]
	if s == nil then
		error("Expected ':' not '.' calling member function Once", 2)
	end
	return s:Connect(fn, true)
end

function facadeMethods.Wait(f)
	local s = signalOfFacade[f]
	if s == nil then
		error("Expected ':' not '.' calling member function Wait", 2)
	end
	return s:Wait()
end

local connMethods = {}
function connMethods.Disconnect(f)
	local c = connOfFacade[f]
	if c then
		c.signal:_disconnect(c)
	end
end

-- opts: owner (raw instance), check(ctx) -> errMessage?, onConnect(signal, conn),
--       onDisconnect(signal, conn), desc (string)
function Signal.new(sim, name: string, opts)
	local self = setmetatable({}, Signal)
	self.sim = sim
	self.name = name
	self.opts = opts or {}
	self.owner = self.opts.owner
	self.conns = {}
	self.waiters = {}
	return self
end

function Signal:describe(): string
	if self.opts.desc then
		return self.opts.desc
	end
	if self.owner then
		return Util.fullName(self.owner) .. "." .. self.name
	end
	return self.name
end

function Signal:facade()
	local f = self._facade
	if f then
		return f
	end
	f = newproxy(true)
	local mt = getmetatable(f)
	local signal = self
	mt.__index = function(_, key)
		local m = facadeMethods[key]
		if m then
			return m
		end
		error(tostring(key) .. " is not a valid member of RBXScriptSignal", 2)
	end
	mt.__newindex = function()
		error("RBXScriptSignal members cannot be assigned", 2)
	end
	mt.__tostring = function()
		return "Signal " .. signal.name
	end
	mt.__metatable = "The metatable is locked"
	signalOfFacade[f] = self
	self.sim.types[f] = "RBXScriptSignal"
	self._facade = f
	return f
end

local function connFacade(sim, conn)
	local f = newproxy(true)
	local mt = getmetatable(f)
	mt.__index = function(_, key)
		if key == "Connected" then
			return conn.connected
		end
		local m = connMethods[key]
		if m then
			return m
		end
		error(tostring(key) .. " is not a valid member of RBXScriptConnection", 2)
	end
	mt.__newindex = function()
		error("RBXScriptConnection members cannot be assigned", 2)
	end
	mt.__tostring = function()
		return "Connection"
	end
	mt.__metatable = "The metatable is locked"
	connOfFacade[f] = conn
	sim.types[f] = "RBXScriptConnection"
	return f
end

function Signal:Connect(fn, once: boolean?)
	if type(fn) ~= "function" then
		error("Attempt to connect failed: Passed value is not a function", 3)
	end
	local sched = self.sim.sched
	local ctx = sched:context()
	if self.opts.check then
		local err = self.opts.check(ctx)
		if err then
			error(err, 3)
		end
	end
	local conn = {
		fn = fn,
		ctx = ctx,
		script = sched:script(),
		connected = true,
		signal = self,
		once = once or false,
	}
	table.insert(self.conns, conn)
	self.sim:_trackConnection(conn, true)
	if self.opts.onConnect then
		self.opts.onConnect(self, conn)
	end
	return connFacade(self.sim, conn)
end

function Signal:_disconnect(conn)
	if not conn.connected then
		return
	end
	conn.connected = false
	local i = table.find(self.conns, conn)
	if i then
		table.remove(self.conns, i)
	end
	self.sim:_trackConnection(conn, false)
	if self.opts.onDisconnect then
		self.opts.onDisconnect(self, conn)
	end
end

function Signal:DisconnectAll()
	for _, conn in table.clone(self.conns) do
		self:_disconnect(conn)
	end
	self.waiters = {}
end

function Signal:Wait()
	local sched = self.sim.sched
	local token = {}
	table.insert(self.waiters, { token = token, ctx = sched:context() })
	return sched:suspend(token)
end

function Signal:HasConnections(): boolean
	return #self.conns > 0 or #self.waiters > 0
end

function Signal:ConnectionCount(): number
	return #self.conns
end

-- filter(ctx) -> boolean restricts delivery to some contexts.
-- forceAll: queued handlers run even if disconnected before the flush (Destroying).
function Signal:_dispatch(immediate: boolean, filter, forceAll: boolean, ...)
	local sched = self.sim.sched
	if #self.conns > 0 then
		local args = table.pack(...)
		for _, conn in table.clone(self.conns) do
			if conn.connected and (filter == nil or filter(conn.ctx)) then
				local force = forceAll
				if conn.once then
					self:_disconnect(conn)
					force = true
				end
				sched:invoke(conn, args, force, immediate)
			end
		end
	end
	if #self.waiters > 0 then
		local waiters = self.waiters
		self.waiters = {}
		for _, w in waiters do
			if filter == nil or filter(w.ctx) then
				sched:wake(w.token, immediate, ...)
			elseif sched:isWaiting(w.token) then
				table.insert(self.waiters, w)
			end
		end
	end
end

-- Deferred delivery (Workspace.SignalBehavior = Deferred).
function Signal:Fire(...)
	self:_dispatch(false, nil, false, ...)
end

function Signal:FireFiltered(filter, ...)
	self:_dispatch(false, filter, false, ...)
end

function Signal:FireForced(...)
	self:_dispatch(false, nil, true, ...)
end

-- Immediate delivery (used for RunService frame events).
function Signal:FireImmediate(...)
	self:_dispatch(true, nil, false, ...)
end

function Signal:FireImmediateFiltered(filter, ...)
	self:_dispatch(true, filter, false, ...)
end

-- Returns true when any live connection belongs to a context accepted by filter.
function Signal:HasConnectionsFor(filter): boolean
	for _, conn in self.conns do
		if conn.connected and filter(conn.ctx) then
			return true
		end
	end
	return false
end

Signal.signalOfFacade = signalOfFacade

return Signal
