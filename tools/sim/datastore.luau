-- datastore.luau: in-memory DataStoreService backend with virtual latency,
-- Roblox-like validation, write throttling and failure injection.
-- Exposed to tests as `sim.DataStore`.

local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Serialize = require("./serialize")
local Util = require("./util")

local DataStore = {}
DataStore.__index = DataStore

local MAX_SIZE = 4 * 1024 * 1024
local MAX_KEY = 50
local DEFAULT_FAILURE = "502: API Services rejected request with error. HTTP 500 (Internal Server Error)"

local function storeId(name: string, scope: string?)
	return name .. "\0" .. (scope or "global")
end

function DataStore.new(sim, snapshot)
	local self = setmetatable({}, DataStore)
	self.sim = sim
	self.data = {} -- storeId -> { key -> entry }
	if snapshot then
		for id, entries in snapshot do
			local copy = {}
			for k, e in entries do
				copy[k] = table.clone(e)
			end
			self.data[id] = copy
		end
	end
	self.latency = 0.05
	self.failQueue = {}
	self.failRate = 0
	self.failRateMessage = DEFAULT_FAILURE
	self.enabled = true
	self.writeCooldown = 6
	self.lastWrite = {}
	self.Calls = {}
	self.stores = {} -- storeId -> raw DataStore instance
	self.info = setmetatable({}, { __mode = "k" }) -- raw store -> { name, scope, id, ordered }
	return self
end

-- Test-facing controls -------------------------------------------------------------------

-- Makes the next `count` requests fail (optionally only for some operations).
function DataStore:FailNext(count: number?, message: string?, ops: { string }?)
	local set = nil
	if ops then
		set = {}
		for _, op in ops do
			set[op] = true
		end
	end
	for _ = 1, count or 1 do
		table.insert(self.failQueue, { message = message or DEFAULT_FAILURE, ops = set })
	end
end

function DataStore:SetFailRate(p: number, message: string?)
	self.failRate = p
	self.failRateMessage = message or DEFAULT_FAILURE
end

function DataStore:SetLatency(seconds: number)
	self.latency = seconds
end

function DataStore:SetEnabled(enabled: boolean)
	self.enabled = enabled
end

function DataStore:SetWriteCooldown(seconds: number)
	self.writeCooldown = seconds
end

function DataStore:Peek(name: string, key: string, scope: string?)
	local entries = self.data[storeId(name, scope)]
	local e = entries and entries[key]
	if e == nil then
		return nil
	end
	return serde.decode("json", e.json)
end

function DataStore:Poke(name: string, key: string, value, scope: string?)
	local id = storeId(name, scope)
	if value == nil then
		if self.data[id] then
			self.data[id][key] = nil
		end
		return
	end
	Serialize.validateStoreValue(value)
	self:_write(id, key, serde.encode("json", value), nil, nil)
end

function DataStore:Keys(name: string, scope: string?)
	local out = {}
	for k in self.data[storeId(name, scope)] or {} do
		table.insert(out, k)
	end
	table.sort(out)
	return out
end

-- Deep copy of all stored data; pass to Sim.new({ dataStore = ... }) to "restart" a server.
function DataStore:Snapshot()
	local out = {}
	for id, entries in self.data do
		local copy = {}
		for k, e in entries do
			copy[k] = table.clone(e)
		end
		out[id] = copy
	end
	return out
end

function DataStore:CountCalls(op: string?, name: string?): number
	local n = 0
	for _, c in self.Calls do
		if (op == nil or c.op == op) and (name == nil or c.store == name) then
			n += 1
		end
	end
	return n
end

function DataStore:ClearCalls()
	table.clear(self.Calls)
end

-- Internals ---------------------------------------------------------------------------------

function DataStore:getStore(name, scope, ordered: boolean?)
	if type(name) ~= "string" or #name == 0 then
		error("GetDataStore: name must be a non-empty string", 0)
	end
	if #name > MAX_KEY then
		error("DataStore name exceeds the 50 character limit", 0)
	end
	if scope ~= nil and type(scope) ~= "string" then
		scope = nil
	end
	local id = storeId(name, scope) .. (if ordered then "\0ordered" else "")
	local store = self.stores[id]
	if store == nil then
		store = roblox.Instance.new(if ordered then "OrderedDataStore" else "DataStore")
		store.Name = name
		self.stores[id] = store
		self.info[store] = { name = name, scope = scope or "global", id = storeId(name, scope), ordered = ordered }
	end
	return self.sim.proxy:wrap(store)
end

function DataStore:_write(id: string, key: string, json: string, userIds, metadata)
	local entries = self.data[id]
	if entries == nil then
		entries = {}
		self.data[id] = entries
	end
	local now = math.floor(self.sim:_serverTime() * 1000)
	local e = entries[key]
	if e then
		e.json = json
		e.version += 1
		e.updated = now
		e.userIds = userIds or e.userIds
		e.metadata = metadata or e.metadata
	else
		entries[key] =
			{ json = json, version = 1, created = now, updated = now, userIds = userIds, metadata = metadata }
	end
	return entries[key]
end

function DataStore:_keyInfo(e)
	if e == nil then
		return nil
	end
	local info = {
		Version = tostring(e.version),
		CreatedTime = e.created,
		UpdatedTime = e.updated,
	}
	function info:GetUserIds()
		return table.clone(e.userIds or {})
	end
	function info:GetMetadata()
		return table.clone(e.metadata or {})
	end
	self.sim.types[info] = "Instance"
	return info
end

local function checkKey(key)
	if type(key) == "number" then
		key = tostring(key)
	end
	if type(key) ~= "string" or #key == 0 then
		error("Argument 1 missing or nil", 0)
	end
	if #key > MAX_KEY then
		error("Key name exceeds the 50 character limit.", 0)
	end
	return key
end

-- Common request path: logging, latency, throttling and failure injection.
function DataStore:_request(op: string, real, key: string, isWrite: boolean)
	local sim = self.sim
	local sched = sim.sched
	local info = self.info[real]
	local ctx = sched:context()
	if ctx.kind ~= "server" then
		error("DataStoreService: requests can only be made from the server", 0)
	end
	local call = { op = op, store = info.name, scope = info.scope, key = key, time = sched.clock }
	table.insert(self.Calls, call)
	if not self.enabled then
		error(
			"502: API Services rejected request with error. HTTP 403 (Forbidden) - Studio access to APIs is not allowed.",
			0
		)
	end
	local canYield = sched:inSimThread()
	if canYield and self.latency > 0 then
		sched:taskWait(self.latency)
	end
	if isWrite and self.writeCooldown > 0 then
		local wkey = info.id .. "\0" .. key
		local last = self.lastWrite[wkey]
		if last and sched.clock - last < self.writeCooldown then
			sim:_warn(
				ctx,
				string.format(
					"DataStore request was added to queue. If request queue fills, further requests will be dropped. Try sending fewer requests. Key = %s",
					key
				)
			)
			if canYield then
				sched:taskWait(self.writeCooldown - (sched.clock - last))
			end
		end
		self.lastWrite[wkey] = sched.clock
	end
	for i, f in self.failQueue do
		if f.ops == nil or f.ops[op] then
			table.remove(self.failQueue, i)
			call.failed = true
			error(f.message, 0)
		end
	end
	if self.failRate > 0 and sim.rng:NextNumber() < self.failRate then
		call.failed = true
		error(self.failRateMessage, 0)
	end
	return info
end

local function encode(value)
	Serialize.validateStoreValue(value)
	local json = serde.encode("json", value)
	if #json > MAX_SIZE then
		error("105: Serialized value exceeds 4MB limit.", 0)
	end
	return json
end

function DataStore:getAsync(real, key)
	key = checkKey(key)
	local info = self:_request("GetAsync", real, key, false)
	local entries = self.data[info.id]
	local e = entries and entries[key]
	if e == nil then
		return nil, nil
	end
	return serde.decode("json", e.json), self:_keyInfo(e)
end

function DataStore:setAsync(real, key, value, userIds, options)
	key = checkKey(key)
	local json = encode(value)
	local info = self:_request("SetAsync", real, key, true)
	local metadata = nil
	if type(options) == "table" and options.GetMetadata then
		metadata = options:GetMetadata()
	end
	local e = self:_write(info.id, key, json, userIds, metadata)
	return tostring(e.version)
end

function DataStore:updateAsync(real, key, transform)
	key = checkKey(key)
	if type(transform) ~= "function" then
		error("Argument 2 missing or nil", 0)
	end
	local info = self:_request("UpdateAsync", real, key, true)
	local entries = self.data[info.id]
	local e = entries and entries[key]
	local old = e and serde.decode("json", e.json) or nil
	local co = coroutine.create(transform)
	local r = table.pack(coroutine.resume(co, old, self:_keyInfo(e)))
	if coroutine.status(co) == "suspended" then
		self.sim.sched:kill(co)
		error("UpdateAsync: transform function must not yield", 0)
	end
	if not r[1] then
		error(Util.cleanError(r[2]), 0)
	end
	local new = r[2]
	if new == nil then
		return nil, nil -- update cancelled
	end
	local json = encode(new)
	local written = self:_write(info.id, key, json, r[3], r[4])
	return serde.decode("json", json), self:_keyInfo(written)
end

function DataStore:removeAsync(real, key)
	key = checkKey(key)
	local info = self:_request("RemoveAsync", real, key, true)
	local entries = self.data[info.id]
	local e = entries and entries[key]
	if e == nil then
		return nil, nil
	end
	entries[key] = nil
	return serde.decode("json", e.json), self:_keyInfo(e)
end

function DataStore:incrementAsync(real, key, delta)
	key = checkKey(key)
	delta = delta or 1
	if type(delta) ~= "number" or delta % 1 ~= 0 then
		error("IncrementAsync: delta must be an integer", 0)
	end
	local info = self:_request("IncrementAsync", real, key, true)
	local entries = self.data[info.id]
	local e = entries and entries[key]
	local current = 0
	if e then
		current = serde.decode("json", e.json)
		if type(current) ~= "number" or current % 1 ~= 0 then
			error("IncrementAsync: stored value is not an integer", 0)
		end
	end
	local new = current + delta
	self:_write(info.id, key, serde.encode("json", new), nil, nil)
	return new
end

return DataStore
