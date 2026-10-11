-- sim_selftest_services.luau: DataStores, BindToClose, tweens, pivots/geometry,
-- raycasts, WaitForChild, CollectionService, Debris, misc services, place loading.

local roblox = require("@lune/roblox")
local fs = require("@lune/fs")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local tests = {}

local function build(t, scripts, opts)
	local sim = t.sim(opts)
	for _, s in scripts do
		local parent = sim:Find(s[1])
		assert(parent, "missing parent " .. s[1])
		sim:AddScript(parent, s[2], s[3], s[4] or "", s[5])
	end
	return sim
end

-- A typical retrying save/load module used by several tests.
local DATA_SCRIPT = [[
	local DSS = game:GetService("DataStoreService")
	local store = DSS:GetDataStore("PlayerData")
	local function retry(label, fn)
		for attempt = 1, 5 do
			local ok, res = pcall(fn)
			if ok then return true, res end
			warn(label .. " failed (attempt " .. attempt .. "): " .. tostring(res))
			task.wait(1)
		end
		return false
	end
	_G.loaded = {}
	_G.saves = 0
	local function save(p)
		local ok = retry("save", function()
			return store:UpdateAsync("u_" .. p.UserId, function(old)
				return { money = p:GetAttribute("Money"), fish = { "Carp", "Pike" } }
			end)
		end)
		if ok then _G.saves += 1 end
	end
	game.Players.PlayerAdded:Connect(function(p)
		local t0 = time()
		local ok, data = retry("load", function() return store:GetAsync("u_" .. p.UserId) end)
		_G.loadTook = time() - t0
		p:SetAttribute("Money", data and data.money or 0)
		_G.loaded[p.Name] = data
	end)
	game.Players.PlayerRemoving:Connect(save)
	game:BindToClose(function()
		for _, p in game.Players:GetPlayers() do save(p) end
		task.wait(2)
		_G.closed = true
	end)
]]

tests["DataStore latency, retries on injected failures and persistence across servers"] = function(t)
	local sim = build(t, { { "ServerScriptService", "Script", "Data", DATA_SCRIPT } })
	sim.DataStore:Poke("PlayerData", "u_1001", { money = 50 })
	sim.DataStore:FailNext(2, "502: injected", { "GetAsync" })
	sim:StartServer()
	local p = sim:AddPlayer()
	sim:Advance(3)
	t.eq(sim:Globals().loaded.Player1, { money = 50 })
	t.eq(p:GetAttribute("Money"), 50)
	t.near(sim:Globals().loadTook, 2 + 3 * 0.05, 0.05, "two failed attempts + latency")
	t.eq(#sim.Warnings, 2)
	t.match(sim.Warnings[1].message, "injected")
	t.eq(sim.DataStore:CountCalls("GetAsync"), 3)
	p:SetAttribute("Money", 75)
	sim:RemovePlayer(p)
	sim:Advance(0.5)
	t.eq(sim:Globals().saves, 1)
	t.eq(sim.DataStore:Peek("PlayerData", "u_1001"), { money = 75, fish = { "Carp", "Pike" } })
	sim:AssertNoErrors()

	-- "restart" the server from a snapshot
	local sim2 = build(
		t,
		{ { "ServerScriptService", "Script", "Data", DATA_SCRIPT } },
		{ dataStore = sim.DataStore:Snapshot() }
	)
	sim2:StartServer()
	local p2 = sim2:AddPlayer()
	sim2:Advance(1)
	t.eq(p2:GetAttribute("Money"), 75)
	sim2:AssertNoErrors()
end

tests["DataStore validation, UpdateAsync cancel, IncrementAsync, failure rate, disabled"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"V",
			[[
			local store = game:GetService("DataStoreService"):GetDataStore("V")
			local function try(f) local ok, e = pcall(f) return ok and "ok" or tostring(e) end
			_G.vec = try(function() store:SetAsync("k", { pos = Vector3.new(1, 2, 3) }) end)
			_G.mixed = try(function() store:SetAsync("k", { 1, 2, x = 3 }) end)
			_G.sparse = try(function() store:SetAsync("k", { [1] = 1, [5] = 5 }) end)
			_G.inst = try(function() store:SetAsync("k", workspace) end)
			_G.longKey = try(function() store:SetAsync(string.rep("k", 51), 1) end)
			_G.good = try(function() store:SetAsync("k", { list = { 1, 2 }, name = "x" }) end)
			_G.cancel = store:UpdateAsync("k", function(old) return nil end)
			_G.after = store:GetAsync("k")
			_G.inc1 = store:IncrementAsync("count")
			_G.inc2 = store:IncrementAsync("count", 5)
			_G.yieldErr = try(function() store:UpdateAsync("k", function(old) task.wait(1) return old end) end)
			_G.removed = store:RemoveAsync("k")
			_G.gone = store:GetAsync("k")
		]],
		},
	})
	sim:StartServer()
	sim:Advance(30)
	local g = sim:Globals()
	t.match(g.vec, "Cannot store Vector3")
	t.match(g.mixed, "mixed")
	t.match(g.sparse, "non%-sequential")
	t.match(g.inst, "Cannot store")
	t.match(g.longKey, "50 character")
	t.eq(g.good, "ok")
	t.eq(g.cancel, nil)
	t.eq(g.after, { list = { 1, 2 }, name = "x" })
	t.eq(g.inc1, 1)
	t.eq(g.inc2, 6)
	t.match(g.yieldErr, "must not yield")
	t.eq(g.removed, { list = { 1, 2 }, name = "x" })
	t.eq(g.gone, nil)
	local throttled = 0
	for _, w in sim.Warnings do
		if string.find(w.message, "added to queue") then
			throttled += 1
		end
	end
	t.ok(throttled >= 1, "writes to the same key within 6s are throttled")
	sim:AssertNoErrors()

	local flaky = build(t, {
		{
			"ServerScriptService",
			"Script",
			"F",
			[[
			local store = game:GetService("DataStoreService"):GetDataStore("F")
			_G.fails = 0
			for i = 1, 40 do
				if not pcall(function() return store:GetAsync("x") end) then _G.fails += 1 end
			end
		]],
		},
	}, { seed = 3 })
	flaky.DataStore:SetFailRate(0.5)
	flaky:StartServer()
	flaky:Advance(5)
	local fails = flaky:Globals().fails
	t.ok(fails > 5 and fails < 35, "about half the calls fail, got " .. fails)

	local off = build(t, {
		{
			"ServerScriptService",
			"Script",
			"O",
			[[_G.err = select(2, pcall(function() return game:GetService("DataStoreService"):GetDataStore("x"):GetAsync("k") end))]],
		},
	})
	off.DataStore:SetEnabled(false)
	off:StartServer()
	off:Advance(0.1)
	t.match(off:Globals().err, "Studio access to APIs is not allowed")
end

tests["BindToClose runs on Shutdown and finishes saving"] = function(t)
	local sim = build(t, { { "ServerScriptService", "Script", "Data", DATA_SCRIPT } })
	sim.DataStore:SetWriteCooldown(0)
	sim:StartServer()
	local a = sim:AddPlayer({ Name = "A" })
	local b = sim:AddPlayer({ Name = "B" })
	sim:Advance(0.5)
	a:SetAttribute("Money", 10)
	b:SetAttribute("Money", 20)
	local result = sim:Shutdown()
	t.eq(result.completed, true)
	t.ok(result.elapsed >= 2 and result.elapsed < 3, "callbacks ran to completion: " .. result.elapsed)
	t.eq(sim:Globals().closed, true)
	t.eq(sim.DataStore:Peek("PlayerData", "u_1001").money, 10)
	t.eq(sim.DataStore:Peek("PlayerData", "u_1002").money, 20)
	t.eq(#sim:GetPlayers(), 0)
	sim:AssertNoErrors()

	local slow = build(t, {
		{ "ServerScriptService", "Script", "Slow", "game:BindToClose(function() task.wait(60) _G.done = true end)" },
	})
	slow:StartServer()
	local r = slow:Shutdown({ timeout = 30 })
	t.eq(r.completed, false)
	t.near(r.elapsed, 30, 0.05)
end

tests["tweens interpolate in virtual time and fire Completed"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"Tw",
			[[
			local TweenService = game:GetService("TweenService")
			local part = Instance.new("Part")
			part.Name = "Fade"
			part.Transparency = 0
			part.Parent = workspace
			local changes = 0
			part:GetPropertyChangedSignal("Transparency"):Connect(function() changes += 1 end)
			local tween = TweenService:Create(part, TweenInfo.new(1, Enum.EasingStyle.Linear), { Transparency = 1, Position = Vector3.new(0, 10, 0) })
			_G.state0 = tween.PlaybackState
			tween.Completed:Connect(function(state) _G.completed = state; _G.changes = changes end)
			tween:Play()
			_G.state1 = tween.PlaybackState
			local other = TweenService:Create(part, TweenInfo.new(5), { Size = Vector3.new(9, 9, 9) })
			other.Completed:Connect(function(state) _G.otherState = state end)
			other:Play()
			task.wait(0.5)
			other:Cancel()
			_G.mismatch = select(2, pcall(function() TweenService:Create(part, TweenInfo.new(1), { Transparency = "x" }) end))
			_G.noprop = select(2, pcall(function() TweenService:Create(part, TweenInfo.new(1), { Bogus = 1 }) end))
			_G.ease = TweenService:GetValue(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		]],
		},
	})
	sim:StartServer()
	sim:Advance(0.5)
	local part = sim:Find("Workspace.Fade")
	t.near(part.Transparency, 0.5, 0.02, "halfway at 0.5s (linear)")
	t.near(part.Position.Y, 5, 0.2)
	sim:Advance(0.6)
	local g = sim:Globals()
	t.eq(g.state0, Enum.PlaybackState.Begin)
	t.eq(g.state1, Enum.PlaybackState.Playing)
	t.eq(g.completed, Enum.PlaybackState.Completed)
	t.eq(part.Transparency, 1)
	t.ok(g.changes >= 30, "Changed fired every frame")
	t.eq(g.otherState, Enum.PlaybackState.Cancelled)
	t.match(g.mismatch, "type mismatch")
	t.match(g.noprop, "no property named 'Bogus'")
	t.near(g.ease, 0.25, 1e-9)
	sim:AssertNoErrors()

	-- a client tweening a server-owned part only changes its own view
	local client = build(t, {
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Glow",
			[[
			local lamp = workspace:WaitForChild("Lamp")
			game:GetService("TweenService"):Create(lamp, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			task.wait(1)
			_G.seen = lamp.Transparency
		]],
		},
	})
	local lamp = client:Create("Part", { Name = "Lamp", Transparency = 0 }, client.workspace)
	client:StartServer()
	local p = client:AddPlayer()
	client:Advance(1.5)
	t.eq(client:Globals(p).seen, 1)
	t.eq(lamp.Transparency, 0, "server copy untouched")
	client:AssertNoErrors()
end

tests["PivotTo / GetPivot / bounding boxes on rotated models"] = function(t)
	local sim = t.sim()
	local model = sim:Create("Model", { Name = "Base" }, sim.workspace)
	local root = sim:Create(
		"Part",
		{ Name = "Root", Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0) },
		model
	)
	local arm = sim:Create("Part", { Name = "Arm", Size = Vector3.new(4, 1, 1), CFrame = CFrame.new(5, 0, 0) }, model)
	model.PrimaryPart = root
	t.near(model:GetPivot(), root.CFrame, 1e-6)
	local target = CFrame.new(100, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	model:PivotTo(target)
	t.near(root.CFrame, target, 1e-4)
	-- the arm's offset relative to the root is preserved
	local before = (CFrame.new(0, 0, 0) * CFrame.Angles(0, math.rad(90), 0)):ToObjectSpace(CFrame.new(5, 0, 0))
	t.near(root.CFrame:ToObjectSpace(arm.CFrame), before, 1e-4)
	-- rotation by +90 about Y relative to the original: (5,0,0) rotated by 0 extra -> stays (+5 x) since same rotation
	t.near(arm.Position, Vector3.new(105, 0, 0), 1e-4)
	-- rotating the pivot by +90 deg about Y swings the arm from +X to -Z
	model:PivotTo(CFrame.new(100, 0, 0) * CFrame.Angles(0, math.rad(180), 0))
	t.near(arm.Position, Vector3.new(100, 0, -5), 1e-4, "arm swings around the pivot")
	t.near(arm.CFrame.LookVector, Vector3.new(-1, 0, 0), 1e-4, "arm rotates with the model")
	local cf, size = model:GetBoundingBox()
	t.near(size, Vector3.new(2, 2, 8), 1e-3)
	t.near(cf.Position, Vector3.new(100, 0, -3), 1e-3)
	t.near(model:GetExtentsSize(), Vector3.new(2, 2, 8), 1e-3)

	-- model without PrimaryPart pivots around its bounding-box centre
	local loose = sim:Create("Model", { Name = "Loose" }, sim.workspace)
	sim:Create("Part", { Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(0, 0, 0) }, loose)
	sim:Create("Part", { Size = Vector3.new(1, 1, 1), CFrame = CFrame.new(10, 0, 0) }, loose)
	t.near(loose:GetPivot().Position, Vector3.new(5, 0, 0), 1e-6)
	loose:PivotTo(CFrame.new(0, 50, 0))
	t.near(loose:GetPivot().Position, Vector3.new(0, 50, 0), 1e-6)
	local parts = loose:GetChildren()
	t.near(parts[1].Position, Vector3.new(-5, 50, 0), 1e-4)
	t.near(parts[2].Position, Vector3.new(5, 50, 0), 1e-4)
	-- legacy SetPrimaryPartCFrame + clones keep PrimaryPart
	local clone = model:Clone()
	clone.Parent = sim.workspace
	t.ok(clone.PrimaryPart ~= nil and clone.PrimaryPart.Parent == clone)
	clone:SetPrimaryPartCFrame(CFrame.new(0, 0, -20))
	t.near(clone.PrimaryPart.Position, Vector3.new(0, 0, -20), 1e-4)
	t.near(root.Position, Vector3.new(100, 0, 0), 1e-4, "original untouched")
	-- attachments
	local att = sim:Create("Attachment", { CFrame = CFrame.new(0, 1, 0) }, root)
	t.near(att.WorldPosition, Vector3.new(100, 1, 0), 1e-4)
end

tests["raycasts and spatial queries"] = function(t)
	local sim = t.sim()
	local floor = sim:Create(
		"Part",
		{ Name = "Floor", Anchored = true, Size = Vector3.new(20, 1, 20), CFrame = CFrame.new(0, 0, 0) },
		sim.workspace
	)
	local wall = sim:Create(
		"Part",
		{ Name = "Wall", Anchored = true, Size = Vector3.new(1, 10, 10), CFrame = CFrame.new(5, 5, 0) },
		sim.workspace
	)
	sim:Create(
		"Part",
		{ Name = "Ghost", CanQuery = false, Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(0, 8, 0) },
		sim.workspace
	)
	sim.workspace.Terrain:FillBlock(CFrame.new(50, -5, 0), Vector3.new(20, 10, 20), Enum.Material.Water)
	local ws = sim.workspace
	local hit = ws:Raycast(Vector3.new(0, 10, 0), Vector3.new(0, -20, 0))
	t.ok(hit ~= nil and hit.Instance == floor, "ghost part (CanQuery=false) ignored")
	t.near(hit.Position, Vector3.new(0, 0.5, 0), 1e-4)
	t.near(hit.Normal, Vector3.new(0, 1, 0), 1e-6)
	t.near(hit.Distance, 9.5, 1e-4)
	local side = ws:Raycast(Vector3.new(0, 5, 0), Vector3.new(10, 0, 0))
	t.ok(side and side.Instance == wall)
	t.near(side.Position, Vector3.new(4.5, 5, 0), 1e-4)
	local rp = sim:Env().RaycastParams.new()
	rp.FilterDescendantsInstances = { floor }
	t.eq(ws:Raycast(Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), rp), nil, "excluded floor")
	rp.FilterType = Enum.RaycastFilterType.Include
	t.ok(ws:Raycast(Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), rp).Instance == floor)
	local water = ws:Raycast(Vector3.new(50, 10, 0), Vector3.new(0, -50, 0))
	t.ok(water and water.Instance == ws.Terrain and water.Material == Enum.Material.Water)
	t.near(water.Position.Y, 0, 1e-4)
	t.eq(#sim.TerrainOps, 1)
	t.eq(sim.TerrainOps[1].op, "FillBlock")
	local near = ws:GetPartBoundsInRadius(Vector3.new(5, 5, 0), 1)
	t.eq(#near, 1)
	t.ok(near[1] == wall)
	t.eq(#ws:GetPartBoundsInBox(CFrame.new(0, 0, 0), Vector3.new(2, 2, 2)), 1)
	sim:SetRaycastHandler(function(origin, dir, p, default)
		if dir.Y < 0 then
			return default(origin, dir, p) -- defer to the built-in raycaster
		end
		return {
			Instance = wall,
			Position = origin,
			Normal = Vector3.yAxis,
			Material = Enum.Material.Plastic,
			Distance = 0,
		}
	end)
	t.ok(ws:Raycast(Vector3.zero, Vector3.xAxis).Instance == wall, "custom handler")
	t.ok(ws:Raycast(Vector3.new(0, 10, 0), Vector3.new(0, -20, 0)).Instance == floor, "handler can fall back")
end

tests["WaitForChild resolves late children, times out, and warns on infinite yield"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"W",
			[[
			task.spawn(function()
				local t0 = time()
				_G.missing = workspace:WaitForChild("Missing", 2)
				_G.timeoutTook = time() - t0
			end)
			task.spawn(function()
				_G.late = workspace:WaitForChild("Late")
				_G.lateAt = time()
			end)
			task.spawn(function()
				_G.renamed = workspace:WaitForChild("Renamed", 10)
			end)
			workspace:WaitForChild("Never")
			_G.never = true
		]],
		},
	})
	sim:StartServer()
	sim:Advance(1)
	sim:Create("Folder", { Name = "Late" }, sim.workspace)
	local f = sim:Create("Folder", { Name = "Other" }, sim.workspace)
	f.Name = "Renamed"
	sim:Advance(6)
	local g = sim:Globals()
	t.eq(g.missing, nil)
	t.near(g.timeoutTook, 2, 1 / 30)
	t.ok(g.late == sim:Find("Workspace.Late"))
	t.near(g.lateAt, 1, 1 / 30)
	t.ok(g.renamed == f, "renaming a child wakes WaitForChild")
	t.eq(g.never, nil)
	local warned = false
	for _, w in sim.Warnings do
		if string.find(w.message, "Infinite yield possible on 'Workspace:WaitForChild%(\"Never\"%)'") then
			warned = true
		end
	end
	t.ok(warned, "infinite yield warning")
	sim:AssertNoErrors()
end

tests["CollectionService signals, Debris, DateTime, StarterCharacterScripts, sounds"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"C",
			[[
			local CS = game:GetService("CollectionService")
			_G.added, _G.removed = {}, {}
			CS:GetInstanceAddedSignal("Fish"):Connect(function(i) table.insert(_G.added, i.Name) end)
			CS:GetInstanceRemovedSignal("Fish"):Connect(function(i) table.insert(_G.removed, i.Name) end)
			local a = Instance.new("Part")
			a.Name = "A"
			CS:AddTag(a, "Fish") -- not in the DataModel yet
			a.Parent = workspace
			local b = Instance.new("Part", workspace)
			b.Name = "B"
			b:AddTag("Fish")
			task.wait()
			_G.tagged = #CS:GetTagged("Fish")
			CS:RemoveTag(b, "Fish")
			a:Destroy()
			local d = Instance.new("Part", workspace)
			d.Name = "Temp"
			game:GetService("Debris"):AddItem(d, 1)
			_G.now = DateTime.now().UnixTimestamp
			_G.iso = DateTime.fromUnixTimestamp(0):ToIsoDate()
			local s = Instance.new("Sound", workspace)
			s.Ended:Connect(function() _G.soundEnded = time() end)
			s:Play()
			_G.playing = s.IsPlaying
		]],
		},
	}, { epoch = 1700000000 })
	sim:AddScript(
		sim:Find("StarterPlayer.StarterCharacterScripts"),
		"LocalScript",
		"Anim",
		"_G.charScript = script.Parent.Name"
	)
	sim:AddScript(
		sim:Find("StarterPlayer.StarterCharacterScripts"),
		"Script",
		"Health",
		"_G.serverCharScript = script.Parent.Name"
	)
	sim:StartServer()
	sim:Advance(0.1)
	local g = sim:Globals()
	t.eq(g.tagged, 2)
	t.eq(g.added, { "A", "B" })
	t.eq(g.removed, { "B", "A" })
	t.ok(sim:Find("Workspace.Temp") ~= nil)
	sim:Advance(1)
	t.eq(sim:Find("Workspace.Temp"), nil, "Debris destroyed it")
	t.eq(g.now, 1700000000)
	t.eq(g.iso, "1970-01-01T00:00:00Z")
	t.eq(g.playing, true)
	t.near(g.soundEnded, 1, 1 / 30)
	local p = sim:AddPlayer({ Name = "Runner" })
	sim:Advance(0.2)
	t.eq(sim:Globals(p).charScript, "Runner")
	t.eq(g.serverCharScript, "Runner")
	sim:AssertNoErrors()
end

tests["remote latency option delays delivery"] = function(t)
	local sim = build(t, {
		{ "ReplicatedStorage", "RemoteEvent", "E" },
		{
			"ServerScriptService",
			"Script",
			"S",
			"game.ReplicatedStorage.E.OnServerEvent:Connect(function(p) _G.at = time() end)",
		},
	}, { remoteLatency = 0.1 })
	sim:StartServer()
	local p = sim:AddPlayer()
	sim:Advance(0.5)
	local sent = sim:Time()
	sim:FireServer(p, "E")
	sim:Advance(0.3)
	t.near(sim:Globals().at - sent, 0.1, 1 / 30)
end

tests["loads the base place file and runs a player through it"] = function(t)
	if not fs.isFile(t.basePlace) then
		t.skip("base place missing")
	end
	local sim = t.sim({ place = t.basePlace })
	sim:StartServer()
	local p = sim:AddPlayer()
	sim:Advance(2)
	local char = sim:GetCharacter(p)
	t.ok(char ~= nil, "character spawned")
	local spawn
	for _, d in sim.workspace:GetDescendants() do
		if d:IsA("SpawnLocation") then
			spawn = d
		end
	end
	if spawn then
		local expected = spawn.Position + Vector3.new(0, spawn.Size.Y / 2 + 3, 0)
		t.near(char.HumanoidRootPart.Position, expected, 1e-3, "spawned on the template SpawnLocation")
	end
	t.ok(sim.workspace:FindFirstChild("Baseplate") ~= nil)
	sim:AssertNoErrors()
end

return tests
