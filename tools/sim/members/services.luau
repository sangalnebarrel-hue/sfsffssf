-- members/services.luau: engine services (RunService, TweenService, Debris,
-- CollectionService, HttpService, DataStoreService, DataModel, ...).

local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Enum = roblox.Enum

return function(M)
	local function noop()
		return nil
	end

	local function clientOnlySignal(name: string)
		return M.signal({
			check = function(ctx)
				if ctx.kind ~= "client" then
					return name .. " event can only be used from local scripts"
				end
				return nil
			end,
		})
	end

	M.define("RunService", {
		IsServer = M.method(function(sim)
			return sim.sched:context().kind == "server"
		end),
		IsClient = M.method(function(sim)
			return sim.sched:context().kind == "client"
		end),
		IsStudio = M.method(function()
			return true
		end),
		IsRunning = M.method(function()
			return true
		end),
		IsRunMode = M.method(function()
			return false
		end),
		IsEdit = M.method(function()
			return false
		end),
		Heartbeat = M.signal(),
		Stepped = M.signal(),
		PostSimulation = M.signal(),
		PreSimulation = M.signal(),
		PreAnimation = M.signal(),
		RenderStepped = clientOnlySignal("RenderStepped"),
		PreRender = clientOnlySignal("PreRender"),
		BindToRenderStep = M.method(function(sim, _, name, priority, fn)
			local ctx = sim.sched:context()
			if ctx.kind ~= "client" then
				error("BindToRenderStep can only be called from the client", 0)
			end
			if type(name) ~= "string" or type(fn) ~= "function" then
				error("BindToRenderStep(name, priority, function) expected", 0)
			end
			ctx.renderBinds[name] =
				{ priority = tonumber(priority) or 0, fn = fn, script = sim.sched:script(), seq = sim:_nextSeq() }
		end),
		UnbindFromRenderStep = M.method(function(sim, _, name)
			local ctx = sim.sched:context()
			if ctx.renderBinds then
				ctx.renderBinds[name] = nil
			end
		end),
	})

	-- TweenService ------------------------------------------------------------------------
	M.define("TweenService", {
		Create = M.method(function(sim, _, inst, info, goals)
			return sim.tweens:create(inst, info, goals)
		end),
		GetValue = M.method(function(sim, _, alpha, style, direction)
			return sim.tweens.ease(alpha, style, direction)
		end),
	})

	M.define("Tween", {
		Play = M.method(function(sim, real)
			sim.tweens:play(real)
		end),
		Pause = M.method(function(sim, real)
			sim.tweens:pause(real)
		end),
		Cancel = M.method(function(sim, real)
			sim.tweens:cancel(real)
		end),
		PlaybackState = M.prop(function(sim, real)
			return sim.tweens:get(real).playback
		end),
		Instance = M.prop(function(sim, real)
			return sim.proxy:wrap(sim.tweens:get(real).target)
		end),
		TweenInfo = M.prop(function(sim, real)
			return sim.tweens:get(real).info
		end),
		Completed = M.signal(),
	})

	-- Debris ---------------------------------------------------------------------------------
	local function addItem(sim, _, inst, lifetime)
		local real = sim.proxy:toReal(inst)
		if real == nil then
			error("Debris:AddItem expects an Instance", 0)
		end
		sim.sched:after(tonumber(lifetime) or 10, function()
			if not sim.proxy:isDestroyed(real) then
				sim.proxy:destroy(real)
			end
		end)
	end
	M.define("Debris", {
		AddItem = M.method(addItem),
		addItem = M.method(addItem),
	})

	-- CollectionService ---------------------------------------------------------------------
	M.define("CollectionService", {
		AddTag = M.method(function(sim, _, inst, tag)
			sim.collection:addTag(sim.proxy:toReal(inst), tag)
		end),
		RemoveTag = M.method(function(sim, _, inst, tag)
			sim.collection:removeTag(sim.proxy:toReal(inst), tag)
		end),
		HasTag = M.method(function(sim, _, inst, tag)
			return sim.proxy:toReal(inst):HasTag(tag)
		end),
		GetTags = M.method(function(sim, _, inst)
			return sim.proxy:toReal(inst):GetTags()
		end),
		GetTagged = M.method(function(sim, _, tag)
			return sim.collection:getTagged(tag)
		end),
		GetAllTags = M.method(function(sim)
			return sim.collection:allTags()
		end),
		GetInstanceAddedSignal = M.method(function(sim, _, tag)
			return sim.collection:addedSignal(tag):facade()
		end),
		GetInstanceRemovedSignal = M.method(function(sim, _, tag)
			return sim.collection:removedSignal(tag):facade()
		end),
		TagAdded = M.signal(),
		TagRemoved = M.signal(),
	})

	-- HttpService ------------------------------------------------------------------------------
	local function jsonEncode(sim, v, seen)
		local t = type(v)
		if t == "nil" then
			return "null"
		elseif t == "boolean" then
			return tostring(v)
		elseif t == "number" then
			if v ~= v or v == math.huge or v == -math.huge then
				return "null"
			end
			if v % 1 == 0 and math.abs(v) < 2 ^ 53 then
				return string.format("%d", v)
			end
			return string.format("%.14g", v)
		elseif t == "string" then
			return serde.encode("json", v)
		elseif t == "table" then
			if seen[v] then
				error("HttpService:JSONEncode: tables cannot be cyclic", 0)
			end
			seen[v] = true
			local parts = {}
			local n = #v
			local isArray = true
			for k in pairs(v) do
				if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > n then
					isArray = false
					break
				end
			end
			local out
			if isArray then
				for i = 1, n do
					parts[i] = jsonEncode(sim, v[i], seen)
				end
				out = "[" .. table.concat(parts, ",") .. "]"
			else
				local keys = {}
				for k in pairs(v) do
					if type(k) ~= "string" then
						error(
							"HttpService:JSONEncode: Cannot convert mixed or non-array tables: keys must be strings",
							0
						)
					end
					table.insert(keys, k)
				end
				table.sort(keys)
				for _, k in keys do
					table.insert(parts, serde.encode("json", k) .. ":" .. jsonEncode(sim, v[k], seen))
				end
				out = "{" .. table.concat(parts, ",") .. "}"
			end
			seen[v] = nil
			return out
		end
		error("HttpService:JSONEncode: Cannot encode " .. typeof(v), 0)
	end

	M.define("HttpService", {
		GenerateGUID = M.method(function(sim, _, wrap)
			local rng = sim.rng
			local function hex(n)
				local s = {}
				for i = 1, n do
					s[i] = string.format("%X", rng:NextInteger(0, 15))
				end
				return table.concat(s)
			end
			local guid = string.format("%s-%s-4%s-%s-%s", hex(8), hex(4), hex(3), hex(4), hex(12))
			if wrap == false then
				return guid
			end
			return "{" .. guid .. "}"
		end),
		JSONEncode = M.method(function(sim, _, v)
			return jsonEncode(sim, v, {})
		end),
		JSONDecode = M.method(function(_, _, s)
			if type(s) ~= "string" then
				error("HttpService:JSONDecode: string expected", 0)
			end
			local ok, v = pcall(serde.decode, "json", s)
			if not ok then
				error("Can't parse JSON", 0)
			end
			return v
		end),
		UrlEncode = M.method(function(_, _, s)
			return (
				string.gsub(tostring(s), "[^%w%-_%.~]", function(c)
					return string.format("%%%02X", string.byte(c))
				end)
			)
		end),
		GetAsync = M.method(function()
			error("Http requests are not enabled. Enable via game settings", 0)
		end),
		PostAsync = M.method(function()
			error("Http requests are not enabled. Enable via game settings", 0)
		end),
		RequestAsync = M.method(function()
			error("Http requests are not enabled. Enable via game settings", 0)
		end),
		HttpEnabled = M.prop(function()
			return false
		end),
	})

	-- DataStoreService ------------------------------------------------------------------------
	M.define("DataStoreService", {
		GetDataStore = M.method(function(sim, _, name, scope)
			return sim.DataStore:getStore(name, scope, false)
		end),
		GetGlobalDataStore = M.method(function(sim)
			return sim.DataStore:getStore("__global", nil, false)
		end),
		GetOrderedDataStore = M.method(function(sim, _, name, scope)
			return sim.DataStore:getStore(name, scope, true)
		end),
		GetRequestBudgetForRequestType = M.method(function()
			return 100
		end),
		ListDataStoresAsync = M.method(function()
			error("RbxSim: ListDataStoresAsync is not supported", 0)
		end),
	})

	local storeDefs = {
		GetAsync = M.method(function(sim, real, key)
			return sim.DataStore:getAsync(real, key)
		end),
		SetAsync = M.method(function(sim, real, key, value, userIds, options)
			return sim.DataStore:setAsync(real, key, value, userIds, options)
		end),
		UpdateAsync = M.method(function(sim, real, key, fn)
			return sim.DataStore:updateAsync(real, key, fn)
		end),
		RemoveAsync = M.method(function(sim, real, key)
			return sim.DataStore:removeAsync(real, key)
		end),
		IncrementAsync = M.method(function(sim, real, key, delta)
			return sim.DataStore:incrementAsync(real, key, delta)
		end),
		GetVersionAsync = M.method(function()
			error("RbxSim: GetVersionAsync is not supported", 0)
		end),
		ListKeysAsync = M.method(function()
			error("RbxSim: ListKeysAsync is not supported", 0)
		end),
		ListVersionsAsync = M.method(function()
			error("RbxSim: ListVersionsAsync is not supported", 0)
		end),
		OnUpdate = M.method(function()
			error("RbxSim: OnUpdate is not supported", 0)
		end),
	}
	M.define("GlobalDataStore", storeDefs)
	M.define("OrderedDataStore", {
		GetSortedAsync = M.method(function()
			error("RbxSim: OrderedDataStore:GetSortedAsync is not supported", 0)
		end),
	})

	-- DataModel -----------------------------------------------------------------------------------
	M.define("DataModel", {
		BindToClose = M.method(function(sim, _, fn)
			local ctx = sim.sched:context()
			if ctx.kind ~= "server" then
				error("BindToClose can only be called on the server", 0)
			end
			if type(fn) ~= "function" then
				error("BindToClose expects a function", 0)
			end
			table.insert(sim.bindToClose, { fn = fn, ctx = ctx, script = sim.sched:script() })
		end),
		IsLoaded = M.method(function()
			return true
		end),
		Loaded = M.signal(),
		Close = M.signal(),
		PlaceId = M.prop(function(sim)
			return sim.opts.placeId or 0
		end),
		GameId = M.prop(function(sim)
			return sim.opts.gameId or 0
		end),
		JobId = M.prop(function()
			return "rbxsim-job"
		end),
		PrivateServerId = M.prop(function()
			return ""
		end),
		PrivateServerOwnerId = M.prop(function()
			return 0
		end),
		CreatorId = M.prop(function()
			return 0
		end),
		PlaceVersion = M.prop(function()
			return 0
		end),
		GetJobsInfo = M.method(function()
			return {}
		end),
	})

	-- GUI-related services -------------------------------------------------------------------
	M.define("StarterGui", {
		SetCoreGuiEnabled = M.method(function(sim, _, kind, enabled)
			sim.coreGui[tostring(kind)] = enabled
		end),
		GetCoreGuiEnabled = M.method(function(sim, _, kind)
			local v = sim.coreGui[tostring(kind)]
			return v ~= false
		end),
		SetCore = M.method(function(sim, _, name, value)
			table.insert(
				sim.CoreCalls,
				{ name = name, value = value, ctx = sim.sched:context().name, time = sim.sched.clock }
			)
		end),
		GetCore = M.method(noop),
		RegisterSetCore = M.method(noop),
		RegisterGetCore = M.method(noop),
	})

	M.define("GuiService", {
		GetGuiInset = M.method(function()
			return roblox.Vector2.new(0, 58), roblox.Vector2.new(0, 0)
		end),
		TopbarInset = M.prop(function(sim)
			local vp = sim:_viewportFor(sim.sched:context())
			return roblox.Rect.new(0, 0, vp.X, 58)
		end),
		IsTenFootInterface = M.method(function()
			return false
		end),
		MenuOpened = M.signal(),
		MenuClosed = M.signal(),
	})

	M.define("TextService", {
		GetTextSize = M.method(function(_, _, text, size)
			text = tostring(text or "")
			size = tonumber(size) or 14
			return roblox.Vector2.new(#text * size * 0.5, size)
		end),
		GetTextBoundsAsync = M.method(function(_, _, params)
			local text = params and params.Text or ""
			local size = params and params.Size or 14
			return roblox.Vector2.new(#tostring(text) * size * 0.5, size)
		end),
		FilterStringAsync = M.method(function(sim, _, text)
			local result = roblox.Instance.new("TextFilterResult")
			sim.filteredText[result] = tostring(text)
			return sim.proxy:wrap(result)
		end),
	})

	local function filtered(sim, real)
		return sim.filteredText[real] or ""
	end
	M.define("TextFilterResult", {
		GetNonChatStringForBroadcastAsync = M.method(filtered),
		GetNonChatStringForUserAsync = M.method(filtered),
		GetChatForUserAsync = M.method(filtered),
	})

	-- Marketplace / physics / pathfinding stubs ---------------------------------------------------
	M.define("MarketplaceService", {
		UserOwnsGamePassAsync = M.method(function(sim, _, userId, passId)
			local owned = sim.opts.gamePasses
			return owned ~= nil and owned[userId] ~= nil and owned[userId][passId] == true
		end),
		PlayerOwnsAsset = M.method(function()
			return false
		end),
		PromptProductPurchase = M.method(function(sim, _, player, id)
			table.insert(sim.Purchases, { kind = "product", player = player, id = id })
		end),
		PromptGamePassPurchase = M.method(function(sim, _, player, id)
			table.insert(sim.Purchases, { kind = "gamepass", player = player, id = id })
		end),
		PromptPurchase = M.method(function(sim, _, player, id)
			table.insert(sim.Purchases, { kind = "asset", player = player, id = id })
		end),
		GetProductInfo = M.method(function(_, _, id)
			return { Name = "Product " .. tostring(id), PriceInRobux = 0, AssetId = id, ProductId = id }
		end),
		ProcessReceipt = M.callback(function(sim, _, fn)
			sim.processReceipt = fn
		end),
		PromptProductPurchaseFinished = M.signal(),
		PromptGamePassPurchaseFinished = M.signal(),
		PromptPurchaseFinished = M.signal(),
	})

	M.define("PhysicsService", {
		RegisterCollisionGroup = M.method(noop),
		UnregisterCollisionGroup = M.method(noop),
		RenameCollisionGroup = M.method(noop),
		CollisionGroupSetCollidable = M.method(noop),
		CollisionGroupsAreCollidable = M.method(function()
			return true
		end),
		IsCollisionGroupRegistered = M.method(function()
			return true
		end),
		GetRegisteredCollisionGroups = M.method(function()
			return {}
		end),
		GetMaxCollisionGroups = M.method(function()
			return 32
		end),
		SetPartCollisionGroup = M.method(function(sim, _, part, group)
			sim.proxy:setProperty(sim.proxy:toReal(part), "CollisionGroup", group)
		end),
	})

	M.define("PathfindingService", {
		CreatePath = M.method(function(sim)
			return sim.proxy:wrap(roblox.Instance.new("Path"))
		end),
		FindPathAsync = M.method(function(sim, _, from, to)
			local path = roblox.Instance.new("Path")
			sim.paths[path] = { from = from, to = to }
			return sim.proxy:wrap(path)
		end),
	})

	M.define("Path", {
		ComputeAsync = M.method(function(sim, real, from, to)
			sim.paths[real] = { from = from, to = to }
		end),
		GetWaypoints = M.method(function(sim, real)
			local p = sim.paths[real]
			if p == nil then
				return {}
			end
			local function wp(pos)
				local w = { Position = pos, Action = Enum.PathWaypointAction.Walk, Label = "" }
				sim.types[w] = "PathWaypoint"
				return w
			end
			return { wp(p.from), wp(p.to) }
		end),
		CheckOcclusionAsync = M.method(function()
			return -1
		end),
		Status = M.prop(function()
			return Enum.PathStatus.Success
		end),
		Blocked = M.signal(),
		Unblocked = M.signal(),
	})

	M.define("ProximityPromptService", {
		PromptTriggered = M.signal(),
		PromptTriggerEnded = M.signal(),
		PromptButtonHoldBegan = M.signal(),
		PromptButtonHoldEnded = M.signal(),
		PromptShown = M.signal(),
		PromptHidden = M.signal(),
	})

	M.define("Team", {
		GetPlayers = M.method(function(sim, real)
			local out = {}
			for _, p in sim.players.order do
				if p.Team == real then
					table.insert(out, sim.proxy:wrap(p))
				end
			end
			return out
		end),
		PlayerAdded = M.signal(),
		PlayerRemoved = M.signal(),
	})

	M.define("TeleportService", {
		Teleport = M.method(function(sim, _, placeId, player)
			table.insert(sim.Teleports, { placeId = placeId, player = player })
		end),
		TeleportAsync = M.method(function(sim, _, placeId, players)
			table.insert(sim.Teleports, { placeId = placeId, players = players })
		end),
		TeleportToPlaceInstance = M.method(function(sim, _, placeId, _jobId, player)
			table.insert(sim.Teleports, { placeId = placeId, player = player })
		end),
		GetLocalPlayerTeleportData = M.method(noop),
		TeleportInitFailed = M.signal(),
	})

	M.define("BadgeService", {
		AwardBadge = M.method(function(sim, _, userId, badgeId)
			table.insert(sim.Badges, { userId = userId, badgeId = badgeId })
			return true
		end),
		UserHasBadgeAsync = M.method(function(sim, _, userId, badgeId)
			for _, b in sim.Badges do
				if b.userId == userId and b.badgeId == badgeId then
					return true
				end
			end
			return false
		end),
		GetBadgeInfoAsync = M.method(function(_, _, id)
			return { Name = "Badge " .. tostring(id), IsEnabled = true }
		end),
	})

	M.define("PolicyService", {
		GetPolicyInfoForPlayerAsync = M.method(function()
			return {
				AreAdsAllowed = true,
				ArePaidRandomItemsRestricted = false,
				AllowedExternalLinkReferences = {},
				IsPaidItemTradingAllowed = true,
				IsSubjectToChinaPolicies = false,
				IsContentSharingAllowed = true,
			}
		end),
	})
end
