-- serialize.luau: argument rules for remotes/bindables and value rules for
-- DataStores, mirroring Roblox's replication/serialization behaviour.

local Util = require("./util")

local Serialize = {}

local luneTypeof = Util.luneTypeof

local function isArrayLike(t)
	-- Roblox treats a table as an array when t[1] ~= nil
	return rawget(t, 1) ~= nil
end

-- Copies one remote argument.
-- dir: "toServer" | "toClient" | "bindable"; target: client ctx for "toClient".
local function copyRemote(sim, v, dir, path, seen, target)
	local tv = type(v)
	if tv == "nil" or tv == "boolean" or tv == "number" or tv == "string" or tv == "vector" or tv == "buffer" then
		return v
	end
	if tv == "function" or tv == "thread" then
		if dir == "bindable" then
			return v
		end
		error(string.format("RbxSim: cannot pass a %s through a remote (%s)", tv, path), 0)
	end
	local proxy = sim.proxy
	local real = proxy.realOf[v]
	if real ~= nil then
		if dir == "toClient" then
			if proxy:isServerOnly(real) or not proxy:isInGame(real) then
				local owner = sim.players:ownerOf(real)
				local visible = target and owner == target.player and not proxy:isServerOnly(real)
				if not visible then
					sim:_note(
						string.format(
							"remote %s: instance %s is not replicated to the client and arrives as nil",
							path,
							Util.fullName(real)
						)
					)
					return nil
				end
			end
		elseif dir == "toServer" then
			if sim:_createdByClient(real) then
				sim:_note(
					string.format(
						"remote %s: client-created instance %s does not exist on the server and arrives as nil",
						path,
						Util.fullName(real)
					)
				)
				return nil
			end
		end
		return v
	end
	local simType = sim.types[v]
	if simType == "RBXScriptSignal" or simType == "RBXScriptConnection" then
		if dir == "bindable" then
			return v
		end
		error(string.format("RbxSim: cannot pass an %s through a remote (%s)", simType, path), 0)
	end
	if tv == "userdata" then
		return v -- Roblox datatypes are immutable values
	end
	if tv == "table" then
		if simType ~= nil then
			return v -- mock datatype (TweenInfo, RaycastParams, ...)
		end
		if seen[v] then
			error(string.format("RbxSim: cyclic table passed through a remote (%s)", path), 0)
		end
		seen[v] = true
		local out = {}
		if isArrayLike(v) then
			local n = 0
			while rawget(v, n + 1) ~= nil do
				n += 1
				out[n] = copyRemote(sim, rawget(v, n), dir, path .. "[" .. n .. "]", seen, target)
			end
			if dir ~= "bindable" then
				for k in pairs(v) do
					if not (type(k) == "number" and k % 1 == 0 and k >= 1 and k <= n) then
						sim:_warn(
							nil,
							string.format(
								"[RbxSim] remote %s: mixed/sparse table, only the array part [1..%d] is sent (key %s dropped)",
								path,
								n,
								tostring(k)
							)
						)
						break
					end
				end
			else
				for k, x in pairs(v) do
					if out[k] == nil then
						out[k] = copyRemote(sim, x, dir, path .. "." .. tostring(k), seen, target)
					end
				end
			end
		else
			for k, x in pairs(v) do
				local key = k
				if type(k) ~= "string" and dir ~= "bindable" then
					key = tostring(k)
					sim:_warn(
						nil,
						string.format(
							'[RbxSim] remote %s: non-string key %s converted to string "%s"',
							path,
							tostring(k),
							key
						)
					)
				end
				out[key] = copyRemote(sim, x, dir, path .. "." .. tostring(k), seen, target)
			end
		end
		seen[v] = nil
		return out
	end
	return v
end

-- Returns a packed table of copied arguments.
function Serialize.remoteArgs(sim, dir: string, target, ...)
	local n = select("#", ...)
	local out = { n = n }
	local seen = {}
	for i = 1, n do
		out[i] = copyRemote(sim, (select(i, ...)), dir, "argument #" .. i, seen, target)
	end
	return out
end

-- Validates a DataStore value; errors like Roblox (with a path hint).
local function validateStore(v, path, seen)
	local tv = type(v)
	if tv == "boolean" or tv == "string" then
		if tv == "string" and utf8.len(v) == nil then
			error("104: Cannot store invalid UTF-8 string in data store (" .. path .. ")", 0)
		end
		return
	end
	if tv == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			error("104: Cannot store NaN or infinite numbers in data store (" .. path .. ")", 0)
		end
		return
	end
	if tv == "table" then
		if seen[v] then
			error("104: Cannot store cyclic tables in data store (" .. path .. ")", 0)
		end
		seen[v] = true
		local n = 0
		while rawget(v, n + 1) ~= nil do
			n += 1
		end
		for k, x in pairs(v) do
			if type(k) == "number" then
				if not (k % 1 == 0 and k >= 1 and k <= n) then
					error(
						string.format(
							"104: Cannot store table with non-sequential numeric key %s in data store (%s); use string keys or a proper array",
							tostring(k),
							path
						),
						0
					)
				end
			elseif type(k) == "string" then
				if n > 0 then
					error(string.format("104: Cannot store mixed array/dictionary table in data store (%s)", path), 0)
				end
			else
				error(string.format("104: Cannot store table with %s key in data store (%s)", typeof(k), path), 0)
			end
			validateStore(x, path .. "." .. tostring(k), seen)
		end
		seen[v] = nil
		return
	end
	local t = luneTypeof(v)
	if tv == "userdata" and t == "userdata" then
		t = "Instance"
	end
	error(
		string.format(
			"104: Cannot store %s in data store. Data stores can only accept valid UTF-8 characters. (%s)",
			t,
			path
		),
		0
	)
end

function Serialize.validateStoreValue(v)
	if v == nil then
		error("Argument 2 missing or nil", 0)
	end
	validateStore(v, "value", {})
end

return Serialize
