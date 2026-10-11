-- proxy.luau: the script-facing instance layer.
--
-- Lune instances cannot have their built-in members overridden (implementMethod /
-- implementProperty are ignored for SetAttribute, Parent, Position, ...), so
-- scripts receive opaque userdata proxies instead. Every read/write goes through
-- this module, which lets the sim:
--   * emulate engine members (events, Position, Humanoid, remotes, services ...)
--   * fire Changed / AttributeChanged / ChildAdded ... at write time (no polling)
--   * emulate Roblox Destroy semantics (Lune's Destroy makes instances unreadable)
-- One proxy exists per raw instance, so proxies are stable table keys.

local Util = require("./util")
local Signal = require("./signal")

local luneTypeof = Util.luneTypeof

local Proxy = {}
Proxy.__index = Proxy

-- Events that require subtree walks when the hierarchy changes.
local HIER_EVENTS = { DescendantAdded = true, DescendantRemoving = true, AncestryChanged = true }

-- ValueBase classes fire Changed(newValue) for Value only.
local VALUE_BASE = {
	IntValue = true,
	NumberValue = true,
	StringValue = true,
	BoolValue = true,
	ObjectValue = true,
	Vector3Value = true,
	CFrameValue = true,
	Color3Value = true,
	BrickColorValue = true,
	RayValue = true,
	IntConstrainedValue = true,
	DoubleConstrainedValue = true,
}
Proxy.VALUE_BASE = VALUE_BASE

-- Built-in child queries that return nothing on clients for server-only containers.
local CHILD_QUERIES = {
	GetChildren = true,
	GetDescendants = true,
	FindFirstChild = true,
	FindFirstChildOfClass = true,
	FindFirstChildWhichIsA = true,
}

local function rawGet(r, k)
	return r[k]
end

local function rawSet(r, k, v)
	r[k] = v
end

local function notMember(key, cls, real)
	return string.format('%s is not a valid member of %s "%s"', tostring(key), cls, Util.fullName(real))
end

function Proxy.new(sim)
	local self = setmetatable({}, Proxy)
	self.sim = sim
	self.realOf = setmetatable({}, { __mode = "k" })
	self.proxyOf = setmetatable({}, { __mode = "v" })
	self.signals = {} -- raw instance -> { [eventKey] = Signal }
	self.destroyed = setmetatable({}, { __mode = "k" })
	self.classOf = setmetatable({}, { __mode = "k" })
	self.builtinCache = {}
	self.memberCache = {}
	self.watch = { DescendantAdded = 0, DescendantRemoving = 0, AncestryChanged = 0 }
	self.childWaiters = {} -- raw parent -> list of { name, token, ctx }
	self.serverOnlyRoots = {} -- raw ServerStorage / ServerScriptService
	self.createdBy = setmetatable({}, { __mode = "k" }) -- raw -> client ctx that created it
	-- >0 while destroying: queued handlers still run although Destroy disconnects them
	self.forceDepth = 0

	local realOf = self.realOf

	-- __index for every proxy. Errors use level 2 so they point at the script line.
	self._index = function(p, key)
		local real = realOf[p]
		if type(key) ~= "string" then
			error(string.format("invalid member key '%s' (string expected)", tostring(key)), 2)
		end
		local cls = self:className(real)
		local def = sim.members:resolve(cls)[key]
		if def then
			local kind = def.kind
			if kind == "prop" then
				if def.get == nil then
					error(string.format("%s of %s is write-only", key, cls), 2)
				end
				local ok, v = pcall(def.get, sim, real, key)
				if not ok then
					error(v, 2)
				end
				return v
			elseif kind == "method" then
				return self:memberMethod(def, key)
			elseif kind == "signal" then
				return self:getSignal(real, key, def):facade()
			elseif kind == "callback" then
				error(string.format("%s is a callback member of %s; you can only set the callback value, get is not available", key, cls), 2)
			end
		end
		local ok, v = pcall(rawGet, real, key)
		if not ok then
			local msg = Util.cleanError(v)
			if string.find(msg, "missing default value", 1, true) then
				return sim.members:defaultValue(cls, key)
			end
			error(notMember(key, cls, real), 2)
		end
		if v == nil then
			return nil
		end
		if type(v) == "function" then
			return self:builtinMethod(key)
		end
		if luneTypeof(v) == "Instance" then
			if self.serverOnlyRoots[real] and self:clientContext() then
				error(notMember(key, cls, real), 2)
			end
			return self:wrap(v)
		end
		return v
	end

	self._newindex = function(p, key, value)
		local real = realOf[p]
		local cls = self:className(real)
		local def = sim.members:resolve(cls)[key]
		if def then
			if (def.kind == "prop" or def.kind == "callback") and def.set then
				local ok, err = pcall(def.set, sim, real, value, key)
				if not ok then
					error(err, 2)
				end
				return
			end
			error(string.format("%s cannot be assigned to", tostring(key)), 2)
		end
		local ok, err = pcall(self.setProperty, self, real, key, value)
		if not ok then
			error(err, 2)
		end
	end

	self._tostring = function(p)
		local real = realOf[p]
		local ok, name = pcall(rawGet, real, "Name")
		return ok and name or "Instance"
	end

	return self
end

-- Wrapping -------------------------------------------------------------------------

function Proxy:wrap(real)
	if real == nil then
		return nil
	end
	local p = self.proxyOf[real]
	if p then
		return p
	end
	if self.realOf[real] ~= nil then
		return real -- already a proxy
	end
	if luneTypeof(real) ~= "Instance" then
		return real
	end
	p = newproxy(true)
	local mt = getmetatable(p)
	mt.__index = self._index
	mt.__newindex = self._newindex
	mt.__tostring = self._tostring
	mt.__metatable = "The metatable is locked"
	self.realOf[p] = real
	self.proxyOf[real] = p
	return p
end

-- Converts a raw value to its script-facing form (instances -> proxies).
function Proxy:toScript(v)
	if v ~= nil and luneTypeof(v) == "Instance" then
		return self:wrap(v)
	end
	return v
end

function Proxy:unwrap(v)
	if v == nil then
		return nil
	end
	local r = self.realOf[v]
	if r ~= nil then
		return r
	end
	return v
end

function Proxy:isProxy(v): boolean
	return v ~= nil and self.realOf[v] ~= nil
end

-- Accepts a proxy or a raw instance and returns the raw instance (or nil).
function Proxy:toReal(v)
	if v == nil then
		return nil
	end
	local r = self.realOf[v]
	if r ~= nil then
		return r
	end
	if luneTypeof(v) == "Instance" then
		return v
	end
	return nil
end

function Proxy:className(real): string
	local c = self.classOf[real]
	if c == nil then
		c = real.ClassName
		self.classOf[real] = c
	end
	return c
end

function Proxy:clientContext()
	local ctx = self.sim.sched:context()
	if ctx.kind == "client" then
		return ctx
	end
	return nil
end

-- True when the instance lives in ServerStorage / ServerScriptService.
function Proxy:isServerOnly(real): boolean
	local cur = real
	while cur ~= nil do
		if self.serverOnlyRoots[cur] then
			return cur ~= real
		end
		cur = cur.Parent
	end
	return false
end

-- Method wrappers --------------------------------------------------------------------

function Proxy:memberMethod(def, key: string)
	local m = self.memberCache[def]
	if m then
		return m
	end
	local sim = self.sim
	local realOf = self.realOf
	m = function(p, ...)
		local real = realOf[p]
		if real == nil then
			error(string.format("Expected ':' not '.' calling member function %s", key), 2)
		end
		local r = table.pack(pcall(def.method, sim, real, ...))
		if not r[1] then
			error(r[2], 2)
		end
		return table.unpack(r, 2, r.n)
	end
	self.memberCache[def] = m
	return m
end

-- Wraps a Lune built-in method: unwraps proxy arguments and wraps results.
function Proxy:builtinMethod(key: string)
	local m = self.builtinCache[key]
	if m then
		return m
	end
	local realOf = self.realOf
	m = function(p, ...)
		local real = realOf[p]
		if real == nil then
			error(string.format("Expected ':' not '.' calling member function %s", key), 2)
		end
		local n = select("#", ...)
		local args = table.pack(...)
		for i = 1, n do
			local a = args[i]
			if a ~= nil then
				local ra = realOf[a]
				if ra ~= nil then
					args[i] = ra
				end
			end
		end
		local client = self:clientContext()
		if client and CHILD_QUERIES[key] and self.serverOnlyRoots[real] then
			if key == "GetChildren" or key == "GetDescendants" then
				return {}
			end
			return nil
		end
		local r = table.pack(pcall(real[key], real, table.unpack(args, 1, n)))
		if not r[1] then
			error(Util.cleanError(r[2]), 2)
		end
		for i = 2, r.n do
			local v = r[i]
			if v ~= nil then
				if type(v) == "table" then
					local filterServerOnly = client ~= nil and key == "GetDescendants"
					local out = {}
					for k, x in v do
						if luneTypeof(x) == "Instance" then
							if not (filterServerOnly and self:isServerOnly(x)) then
								if filterServerOnly then
									table.insert(out, self:wrap(x))
								else
									out[k] = self:wrap(x)
								end
							end
						else
							out[k] = x
						end
					end
					r[i] = out
				elseif luneTypeof(v) == "Instance" then
					r[i] = self:wrap(v)
				end
			end
		end
		return table.unpack(r, 2, r.n)
	end
	self.builtinCache[key] = m
	return m
end

-- Signals ------------------------------------------------------------------------------

function Proxy:getSignal(real, key: string, def)
	local sigs = self.signals[real]
	if sigs == nil then
		sigs = {}
		self.signals[real] = sigs
	end
	local s = sigs[key]
	if s == nil then
		if def == nil then
			def = self.sim.members:resolve(self:className(real))[key]
		end
		local opts = { owner = real, check = def and def.check }
		local watchKey = HIER_EVENTS[key] and key or nil
		if watchKey or (def and (def.onConnect or def.onDisconnect)) then
			opts.onConnect = function(sig, conn)
				if watchKey then
					self.watch[watchKey] += 1
				end
				if def and def.onConnect then
					def.onConnect(self.sim, real, sig, conn)
				end
			end
			opts.onDisconnect = function(sig, conn)
				if watchKey then
					self.watch[watchKey] -= 1
				end
				if def and def.onDisconnect then
					def.onDisconnect(self.sim, real, sig, conn)
				end
			end
		end
		local label = key
		if string.sub(key, 1, 5) == "prop:" then
			label = "GetPropertyChangedSignal(" .. string.sub(key, 6) .. ")"
		elseif string.sub(key, 1, 5) == "attr:" then
			label = "GetAttributeChangedSignal(" .. string.sub(key, 6) .. ")"
		end
		s = Signal.new(self.sim, label, opts)
		sigs[key] = s
	end
	return s
end

function Proxy:peekSignal(real, key: string)
	local sigs = self.signals[real]
	return sigs and sigs[key]
end

-- Fires a signal (deferred); forced while a Destroy is in progress.
function Proxy:_fireSig(s, ...)
	s:_dispatch(false, nil, self.forceDepth > 0, ...)
end

-- Fires an instance event (deferred) if anybody ever asked for it.
function Proxy:fire(real, key: string, ...)
	local sigs = self.signals[real]
	local s = sigs and sigs[key]
	if s then
		s:_dispatch(false, nil, self.forceDepth > 0, ...)
	end
end

function Proxy:fireFiltered(real, key: string, filter, ...)
	local sigs = self.signals[real]
	local s = sigs and sigs[key]
	if s then
		s:_dispatch(false, filter, self.forceDepth > 0, ...)
	end
end

-- Property writes -------------------------------------------------------------------------

function Proxy:emitChanged(real, key: string, newValue)
	local sigs = self.signals[real]
	if sigs == nil then
		return
	end
	local s = sigs["prop:" .. key]
	if s then
		self:_fireSig(s)
	end
	local c = sigs.Changed
	if c then
		if VALUE_BASE[self:className(real)] then
			if key == "Value" then
				self:_fireSig(c, self:toScript(newValue))
			end
		else
			self:_fireSig(c, key)
		end
	end
end

function Proxy:isWatched(real, key: string): boolean
	local sigs = self.signals[real]
	return sigs ~= nil and (sigs.Changed ~= nil or sigs["prop:" .. key] ~= nil)
end

-- Generic write of a real (reflected) property with Roblox-like coercions.
function Proxy:setProperty(real, key: string, value)
	local raw = self:unwrap(value)
	if key == "Parent" then
		return self:setParent(real, raw)
	end
	self.sim:_checkClientWrite(real, key)
	local watched = self:isWatched(real, key)
	local old
	if watched then
		local ok, v = pcall(rawGet, real, key)
		if ok then
			old = v
		end
	end
	local ok, err = pcall(rawSet, real, key, raw)
	if not ok then
		local msg = Util.cleanError(err)
		if string.find(msg, "is not a valid member", 1, true) then
			error(notMember(key, self:className(real), real), 0)
		end
		if type(raw) == "number" and string.find(msg, "'String'", 1, true) then
			ok, err = pcall(rawSet, real, key, tostring(raw))
		elseif type(raw) == "string" and tonumber(raw) ~= nil then
			ok, err = pcall(rawSet, real, key, tonumber(raw))
		end
		if not ok then
			error(string.format("Unable to assign property %s. %s", key, Util.cleanError(err)), 0)
		end
	end
	if key == "Name" then
		local parent = real.Parent
		if parent ~= nil then
			self:_checkWaiters(parent, real)
		end
	end
	if watched then
		local okNew, nv = pcall(rawGet, real, key)
		if okNew and nv ~= old then
			self:emitChanged(real, key, nv)
		end
	end
end

-- Writes a property through the member table when one exists (used by tweens,
-- sim helpers), otherwise like a script assignment.
function Proxy:assign(real, key: string, value)
	local def = self.sim.members:resolve(self:className(real))[key]
	if def and def.kind == "prop" and def.set then
		def.set(self.sim, real, value, key)
	else
		self:setProperty(real, key, value)
	end
end

-- Reads a property through the member table when one exists.
function Proxy:read(real, key: string)
	return self._index(self:wrap(real), key)
end

-- Hierarchy ---------------------------------------------------------------------------------

function Proxy:isInGame(real): boolean
	local game = self.sim.real
	return real == game or real:IsDescendantOf(game)
end

function Proxy:setParent(real, newParent)
	if newParent ~= nil and luneTypeof(newParent) ~= "Instance" then
		error("Unable to assign property Parent. Instance expected, got " .. typeof(newParent), 0)
	end
	if self.destroyed[real] then
		error(
			string.format(
				"The Parent property of %s is locked, current parent: NULL, new parent %s",
				real.Name,
				newParent and newParent.Name or "NULL"
			),
			0
		)
	end
	local oldParent = real.Parent
	if oldParent == newParent then
		return
	end
	if newParent ~= nil then
		if newParent == real then
			error(string.format("Attempt to set %s as its own parent", Util.fullName(real)), 0)
		end
		if newParent:IsDescendantOf(real) then
			error(
				string.format(
					"Attempt to set parent of %s to %s would result in circular reference",
					Util.fullName(real),
					Util.fullName(newParent)
				),
				0
			)
		end
	end
	self.sim:_checkClientWrite(real, "Parent")

	local subtree
	local function getSubtree()
		if subtree == nil then
			subtree = real:GetDescendants()
			table.insert(subtree, 1, real)
		end
		return subtree
	end

	-- DescendantRemoving is announced before the removal (handlers run deferred).
	if oldParent ~= nil and self.watch.DescendantRemoving > 0 then
		local anc = oldParent
		while anc ~= nil do
			local s = self:peekSignal(anc, "DescendantRemoving")
			if s and s:HasConnections() then
				for _, d in getSubtree() do
					self:_fireSig(s, self:wrap(d))
				end
			end
			anc = anc.Parent
		end
	end

	local wasInGame = oldParent ~= nil and self:isInGame(oldParent)
	rawSet(real, "Parent", newParent)

	if oldParent ~= nil then
		self:fire(oldParent, "ChildRemoved", self:wrap(real))
	end
	if newParent ~= nil then
		self:fire(newParent, "ChildAdded", self:wrap(real))
		if self.watch.DescendantAdded > 0 then
			local anc = newParent
			while anc ~= nil do
				local s = self:peekSignal(anc, "DescendantAdded")
				if s and s:HasConnections() then
					for _, d in getSubtree() do
						self:_fireSig(s, self:wrap(d))
					end
				end
				anc = anc.Parent
			end
		end
	end
	if self.watch.AncestryChanged > 0 then
		local pr, pp = self:wrap(real), self:toScript(newParent)
		for _, d in getSubtree() do
			local s = self:peekSignal(d, "AncestryChanged")
			if s then
				self:_fireSig(s, pr, pp)
			end
		end
	end
	self:emitChanged(real, "Parent", newParent)
	if newParent ~= nil then
		self:_checkWaiters(newParent, real)
	end
	local isInGame = newParent ~= nil and self:isInGame(newParent)
	self.sim:_onReparented(real, oldParent, newParent, wasInGame, isInGame, getSubtree)
end

-- Roblox Destroy: fire Destroying, detach, lock Parent, disconnect, recurse.
function Proxy:destroy(real)
	if self.destroyed[real] then
		return
	end
	self.sim:_beforeDestroy(real)
	self.forceDepth += 1
	local s = self:peekSignal(real, "Destroying")
	if s then
		self:_fireSig(s)
	end
	if real.Parent ~= nil then
		local ok, err = pcall(self.setParent, self, real, nil)
		if not ok then
			self.forceDepth -= 1
			error(err, 0)
		end
	end
	self.forceDepth -= 1
	self.destroyed[real] = true
	local sigs = self.signals[real]
	if sigs then
		for _, sig in sigs do
			sig:DisconnectAll()
		end
		self.signals[real] = nil
	end
	self.childWaiters[real] = nil
	for _, child in real:GetChildren() do
		self:destroy(child)
	end
end

function Proxy:isDestroyed(real): boolean
	return self.destroyed[real] == true
end

-- WaitForChild ------------------------------------------------------------------------------

function Proxy:waitForChild(real, name: string, timeout: number?)
	local sched = self.sim.sched
	local ctx = sched:context()
	local hidden = ctx.kind == "client" and self.serverOnlyRoots[real]
	if not hidden then
		local child = real:FindFirstChild(name)
		if child then
			return self:wrap(child)
		end
	end
	local token = {}
	local list = self.childWaiters[real]
	if list == nil then
		list = {}
		self.childWaiters[real] = list
	end
	local entry = { name = name, token = token, ctx = ctx }
	table.insert(list, entry)
	if timeout ~= nil then
		sched:addTimer(timeout, { token = token, args = table.pack(nil) })
	else
		local where = Util.fullName(real)
		sched:after(5, function()
			if sched:isWaiting(token) then
				self.sim:_warn(ctx, string.format("Infinite yield possible on '%s:WaitForChild(\"%s\")'", where, name))
			end
		end, ctx)
	end
	local result = sched:suspend(token)
	local i = table.find(list, entry)
	if i then
		table.remove(list, i)
	end
	return self:toScript(result)
end

function Proxy:_checkWaiters(parent, child)
	local list = self.childWaiters[parent]
	if list == nil or #list == 0 then
		return
	end
	local name = child.Name
	local hiddenRoot = self.serverOnlyRoots[parent]
	for _, entry in table.clone(list) do
		if entry.name == name and not (hiddenRoot and entry.ctx.kind == "client") then
			self.sim.sched:wake(entry.token, false, child)
		end
	end
end

return Proxy
