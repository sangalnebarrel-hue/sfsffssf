-- sim_selftest.luau: core RbxSim self-tests (contexts, require, scheduler,
-- signals, remotes + serialization, attributes, errors, connection counting).
-- Run: /opt/tools/l11/lune run tools/run_tests.luau sim_selftest

local roblox = require("@lune/roblox")

local tests = {}

-- Builds a sim from a list of { path, className, name, source, props? }.
local function build(t, scripts, opts)
	local sim = t.sim(opts)
	for _, s in scripts do
		local parent = sim:Find(s[1])
		assert(parent, "missing parent " .. s[1])
		sim:AddScript(parent, s[2], s[3], s[4], s[5])
	end
	return sim
end

tests["require caches per context and _G is per context"] = function(t)
	local sim = build(t, {
		{
			"ReplicatedStorage",
			"ModuleScript",
			"Shared",
			[[
			local M = { loadedIn = game:GetService("RunService"):IsServer() and "server" or "client", marks = {} }
			print("load " .. M.loadedIn)
			return M
		]],
		},
		{
			"ServerScriptService",
			"Script",
			"Server",
			[[
			local a = require(game.ReplicatedStorage.Shared)
			local b = require(game.ReplicatedStorage:WaitForChild("Shared"))
			a.marks.server = true
			_G.same = rawequal(a, b)
			_G.loadedIn = a.loadedIn
			_G.who = "server"
		]],
		},
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Client",
			[[
			local m = require(game.ReplicatedStorage.Shared)
			_G.loadedIn = m.loadedIn
			_G.sawServerMark = m.marks.server == true
			_G.who = "client"
		]],
		},
	})
	sim:StartServer()
	local p1 = sim:AddPlayer({ Name = "A" })
	local p2 = sim:AddPlayer({ Name = "B" })
	sim:Advance(0.5)
	sim:AssertNoErrors()
	local server = sim:Globals()
	t.eq(server.same, true, "same table within a context")
	t.eq(server.loadedIn, "server")
	for _, p in { p1, p2 } do
		local g = sim:Globals(p)
		t.eq(g.loadedIn, "client")
		t.eq(g.sawServerMark, false, "client module table is separate from the server one")
		t.eq(g.who, "client")
	end
	local loads = 0
	for _, line in sim:Output() do
		if string.find(line, "^load ") then
			loads += 1
		end
	end
	t.eq(loads, 3, "module body runs once per context (server + 2 clients)")
	t.eq(#sim:Output("server"), 1)
	t.eq(sim:Output(sim:ContextName(p1))[1], "load client")
end

tests["IsServer / IsClient / LocalPlayer follow the running context"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"S",
			[[
			local RS = game:GetService("RunService")
			_G.info = { RS:IsServer(), RS:IsClient(), game.Players.LocalPlayer == nil }
			task.spawn(function()
				task.wait(0.1)
				_G.spawned = RS:IsServer()
			end)
		]],
		},
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"L",
			[[
			local RS = game:GetService("RunService")
			local lp = game:GetService("Players").LocalPlayer
			_G.info = { RS:IsServer(), RS:IsClient(), lp.Name, lp == game.Players:FindFirstChild(lp.Name) }
			local ev = Instance.new("BindableEvent")
			ev.Event:Connect(function()
				_G.handlerSees = game.Players.LocalPlayer.Name
			end)
			task.delay(0.2, function()
				ev:Fire()
				_G.delayedSees = game.Players.LocalPlayer.Name
			end)
		]],
		},
	})
	sim:StartServer()
	local a = sim:AddPlayer({ Name = "Ann" })
	local b = sim:AddPlayer({ Name = "Bob" })
	sim:Advance(1)
	sim:AssertNoErrors()
	t.eq(sim:Globals().info, { true, false, true })
	t.eq(sim:Globals().spawned, true, "spawned threads inherit the server context")
	t.eq(sim:Globals(a).info, { false, true, "Ann", true })
	t.eq(sim:Globals(b).info, { false, true, "Bob", true })
	t.eq(sim:Globals(a).handlerSees, "Ann", "event handlers run in the connecting context")
	t.eq(sim:Globals(b).delayedSees, "Bob")
end

tests["virtual time: spawn/defer/delay/wait ordering and clocks"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"Order",
			[[
			local order = {}
			_G.order = order
			task.delay(0.5, function(x) table.insert(order, "delay:" .. x) end, "arg")
			task.spawn(function() table.insert(order, "spawn") end)
			task.defer(function() table.insert(order, "defer") end)
			local cancelled = task.delay(0.2, function() table.insert(order, "cancelled!") end)
			task.cancel(cancelled)
			table.insert(order, "main")
			local t0, c0 = time(), os.clock()
			local e1 = task.wait()
			_G.oneFrame = e1
			local e = task.wait(1)
			table.insert(order, "wait1")
			_G.elapsed = e
			_G.timeDelta = time() - t0
			_G.clockDelta = os.clock() - c0
			_G.osTime = os.time()
			_G.tick = tick()
			local legacyElapsed = wait(0.25)
			_G.legacy = legacyElapsed
		]],
		},
	}, { epoch = 1000000 })
	sim:StartServer()
	local g = sim:Globals()
	t.eq(g.order, { "spawn", "main", "defer" }, "spawn runs immediately, defer after the script yields")
	sim:Advance(2)
	sim:AssertNoErrors()
	t.eq(g.order, { "spawn", "main", "defer", "delay:arg", "wait1" })
	t.near(g.oneFrame, 1 / 60, 1e-6, "task.wait() waits one frame")
	t.near(g.elapsed, 1, 1 / 60 + 1e-6)
	t.near(g.timeDelta, 1 + 1 / 60, 1 / 30)
	t.near(g.clockDelta, g.timeDelta, 1e-9)
	t.ok(g.osTime >= 1000001 and g.osTime <= 1000002, "os.time uses the virtual epoch")
	t.near(g.legacy, 0.25, 1 / 60 + 1e-6)
	t.near(sim:Time(), 2, 1e-9)
end

tests["signals: Connect/Once/Wait/Disconnect, deferred delivery, typeof"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"Sig",
			[[
			local ev = Instance.new("BindableEvent")
			ev.Name = "Ev"
			ev.Parent = workspace
			local log = {}
			_G.log = log
			local c1 = ev.Event:Connect(function(x) table.insert(log, "c1:" .. x) end)
			ev.Event:Once(function(x) table.insert(log, "once:" .. x) end)
			ev.Event:Connect(function() error("handler boom") end)
			_G.types = { typeof(ev.Event), typeof(c1), c1.Connected }
			task.spawn(function()
				local v = ev.Event:Wait()
				table.insert(log, "wait:" .. v)
			end)
			ev:Fire("a")
			table.insert(log, "after fire")
			task.wait()
			c1:Disconnect()
			_G.connectedAfter = c1.Connected
			ev:Fire("b")
			task.wait()
			table.insert(log, "end")
		]],
		},
	})
	sim:StartServer()
	sim:Advance(0.2)
	local g = sim:Globals()
	t.eq(g.types, { "RBXScriptSignal", "RBXScriptConnection", true })
	t.eq(g.connectedAfter, false)
	t.eq(g.log, { "after fire", "c1:a", "once:a", "wait:a", "end" })
	t.eq(#sim.Errors, 2, "handler errors are captured (fired twice)")
	t.match(sim.Errors[1].message, "handler boom")
	t.eq(sim.Errors[1].context, "server")
end

tests["remote events round trip both ways, with queueing and logs"] = function(t)
	local sim = build(t, {
		{ "ReplicatedStorage", "RemoteEvent", "Ping", "" },
		{
			"ServerScriptService",
			"Script",
			"Server",
			[[
			local ping = game.ReplicatedStorage.Ping
			task.wait(1) -- connect late: events fired before must be queued
			ping.OnServerEvent:Connect(function(player, n, payload)
				payload.server = true
				ping:FireClient(player, n + 1, payload)
			end)
		]],
		},
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Client",
			[[
			local ping = game.ReplicatedStorage:WaitForChild("Ping")
			local sent = { tag = "x" }
			_G.got = {}
			ping.OnClientEvent:Connect(function(n, payload)
				table.insert(_G.got, n)
				_G.payload = payload
				_G.originalUntouched = sent.server == nil
			end)
			ping:FireServer(1, sent)
		]],
		},
	})
	sim:StartServer()
	local p = sim:AddPlayer({ Name = "P" })
	sim:Advance(0.5)
	t.eq(#sim:Globals(p).got, 0, "server not connected yet")
	sim:Advance(1)
	sim:AssertNoErrors()
	local g = sim:Globals(p)
	t.eq(g.got, { 2 })
	t.eq(g.payload, { tag = "x", server = true })
	t.eq(g.originalUntouched, true, "tables are copied, not shared")
	local args, entry = sim:LastClientEvent(p, "Ping")
	t.eq(args[1], 2)
	t.eq(entry.player, p)
	t.eq(#sim:ServerEventsFor(p, "Ping"), 1)
	-- harness-driven FireServer
	sim:FireServer(p, "Ping", 10, {})
	sim:Advance(0.1)
	t.eq(sim:Globals(p).got, { 2, 11 })
end

tests["remote serialization rules"] = function(t)
	local sim = build(t, {
		{ "ReplicatedStorage", "RemoteEvent", "R", "" },
		{ "ServerStorage", "Folder", "Secret", "" },
		{
			"ServerScriptService",
			"Script",
			"Server",
			[[
			local r = game.ReplicatedStorage.R
			_G.received = {}
			r.OnServerEvent:Connect(function(player, ...)
				table.insert(_G.received, table.pack(...))
				if select(1, ...) == "secret" then
					r:FireClient(player, game.ServerStorage.Secret, workspace)
				end
			end)
		]],
		},
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Client",
			[[
			game.ReplicatedStorage.R.OnClientEvent:Connect(function(a, b)
				_G.secret = a
				_G.ws = b
			end)
		]],
		},
	}, {})
	sim:StartServer()
	local p = sim:AddPlayer()
	sim:Advance(0.2)
	local part = sim:Create("Part", { Name = "Ref" }, sim.workspace)
	local withMeta = setmetatable({ k = 1 }, {
		__index = function()
			return "meta"
		end,
	})
	sim:FireServer(p, "R", { 1, 2, 3 }, { 1, 2, x = 3 }, { [10] = "a" }, part, withMeta, nil, "tail")
	sim:Advance(0.1)
	local got = sim:Globals().received[1]
	t.eq(got.n, 7, "nil arguments keep their position")
	t.eq(got[1], { 1, 2, 3 })
	t.eq(got[2], { 1, 2 }, "mixed table keeps only the array part")
	t.eq(got[3], { ["10"] = "a" }, "numeric dictionary keys become strings")
	t.ok(got[4] == part, "instances pass by reference")
	t.eq(got[5].k, 1)
	t.eq(got[5].missing, nil, "metatables are dropped")
	t.eq(got[6], nil)
	t.eq(got[7], "tail")
	local warnings = 0
	for _, w in sim.Warnings do
		if string.find(w.message, "%[RbxSim%] remote") then
			warnings += 1
		end
	end
	t.eq(warnings, 2, "mixed table + numeric key warnings")
	t.throws(function()
		sim:FireServer(p, "R", function() end)
	end, "cannot pass a function")
	local cyclic = {}
	cyclic.self = cyclic
	t.throws(function()
		sim:FireServer(p, "R", cyclic)
	end, "cyclic")
	-- server-only instances arrive as nil on the client
	sim:FireServer(p, "R", "secret")
	sim:Advance(0.1)
	t.eq(sim:Globals(p).secret, nil)
	t.ok(sim:Globals(p).ws == sim.workspace)
	t.ok(#sim.Notes >= 1)
	sim:AssertNoErrors()
end

tests["RemoteFunction invoke both directions, errors propagate"] = function(t)
	local sim = build(t, {
		{ "ReplicatedStorage", "RemoteFunction", "Add", "" },
		{ "ReplicatedStorage", "RemoteFunction", "Ask", "" },
		{
			"ServerScriptService",
			"Script",
			"Server",
			[[
			local add = game.ReplicatedStorage.Add
			add.OnServerInvoke = function(player, a, b)
				if a == "boom" then error("bad input") end
				task.wait(0.5)
				return a + b, player.Name
			end
			game.Players.PlayerAdded:Connect(function(player)
				task.wait(1)
				_G.answer = game.ReplicatedStorage.Ask:InvokeClient(player, "color?")
			end)
		]],
		},
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Client",
			[[
			local add = game.ReplicatedStorage.Add
			game.ReplicatedStorage.Ask.OnClientInvoke = function(q)
				return q .. " blue"
			end
			local t0 = time()
			_G.sum, _G.name = add:InvokeServer(2, 3)
			_G.took = time() - t0
			local ok, err = pcall(function() return add:InvokeServer("boom") end)
			_G.errOk, _G.err = ok, err
		]],
		},
	})
	sim:StartServer()
	local p = sim:AddPlayer({ Name = "Zed" })
	sim:Advance(2)
	local g = sim:Globals(p)
	t.eq(g.sum, 5)
	t.eq(g.name, "Zed")
	t.near(g.took, 0.5, 1 / 30, "invoke yields until the server returns")
	t.eq(g.errOk, false)
	t.match(g.err, "bad input")
	t.eq(sim:Globals().answer, "color? blue")
	local r1, r2 = sim:InvokeServer(p, "Add", 40, 2)
	t.eq(r1, 42)
	t.eq(r2, "Zed")
	t.eq(#sim.Errors, 0, "errors returned to the invoker are not script errors")
end

tests["attribute and property change signals"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"Watch",
			[[
			local part = Instance.new("Part")
			part.Name = "Watched"
			part.Parent = workspace
			local value = Instance.new("IntValue")
			value.Name = "Score"
			value.Parent = workspace
			_G.events = {}
			local function log(s) table.insert(_G.events, s) end
			part:GetAttributeChangedSignal("Coins"):Connect(function() log("coins=" .. tostring(part:GetAttribute("Coins"))) end)
			part.AttributeChanged:Connect(function(name) log("attr:" .. name) end)
			part:GetPropertyChangedSignal("Transparency"):Connect(function() log("transparency=" .. part.Transparency) end)
			part:GetPropertyChangedSignal("Position"):Connect(function() log("moved") end)
			part.Changed:Connect(function(prop) if prop == "Name" then log("changed:Name") end end)
			value.Changed:Connect(function(v) log("value=" .. v) end)
		]],
		},
	})
	sim:StartServer()
	local part = sim:Find("Workspace.Watched")
	part:SetAttribute("Coins", 5)
	part:SetAttribute("Coins", 5) -- unchanged: no event
	part.Transparency = 0.5
	part.Name = "Renamed"
	part.CFrame = roblox.CFrame.new(1, 2, 3)
	sim:Find("Workspace.Score").Value = 7
	sim:Flush()
	t.eq(sim:Globals().events, {
		"coins=5",
		"attr:Coins",
		"transparency=0.5",
		"changed:Name",
		"moved",
		"value=7",
	})
	t.eq(part.Position, roblox.Vector3.new(1, 2, 3), "Position derives from CFrame")
	part.Position = roblox.Vector3.new(4, 5, 6)
	t.eq(part.CFrame.Position, roblox.Vector3.new(4, 5, 6))
	t.throws(function()
		part:GetPropertyChangedSignal("NotAProperty")
	end, "not a valid property")
	sim:AssertNoErrors()
end

tests["script errors are captured with context, sources and tracebacks"] = function(t)
	local sim = build(t, {
		{ "ServerScriptService", "Script", "Bad", "local x = nil\nprint(x.y)" },
		{ "ServerScriptService", "Script", "Syntax", "local = 1" },
		{ "ServerScriptService", "Script", "Good", "_G.ran = true" },
		{ "ReplicatedStorage", "ModuleScript", "Broken", "error('module exploded')" },
		{ "ReplicatedStorage", "ModuleScript", "CycA", "require(script.Parent.CycB) return {}" },
		{ "ReplicatedStorage", "ModuleScript", "CycB", "require(script.Parent.CycA) return {}" },
		{ "ReplicatedStorage", "ModuleScript", "NoReturn", "local x = 1" },
		{
			"ServerScriptService",
			"Script",
			"Requirer",
			[[
			_G.r1 = select(2, pcall(require, game.ReplicatedStorage.Broken))
			_G.r1again = select(2, pcall(require, game.ReplicatedStorage.Broken))
			_G.r2 = select(2, pcall(require, game.ReplicatedStorage.CycA))
			_G.r3 = select(2, pcall(require, game.ReplicatedStorage.NoReturn))
		]],
		},
	})
	sim:StartServer()
	local g = sim:Globals()
	t.eq(g.ran, true, "other scripts keep running")
	t.match(g.r1, "Requested module experienced an error while loading")
	t.match(g.r1, "module exploded")
	t.match(g.r1again, "Requested module experienced an error while loading")
	t.match(g.r2, "required recursively: ReplicatedStorage.CycA %-> ReplicatedStorage.CycB %-> ReplicatedStorage.CycA")
	t.match(g.r3, "did not return exactly one value")
	local found = {}
	for _, e in sim.Errors do
		if string.find(e.message, "^ServerScriptService%.Bad:2: attempt to index nil") then
			found.bad = true
			t.match(e.traceback, "ServerScriptService%.Bad:2")
		end
		if string.find(e.message, "^ServerScriptService%.Syntax:1:") then
			found.syntax = true
		end
		if string.find(e.message, "module exploded") then
			found.module = true
		end
	end
	t.ok(found.bad and found.syntax and found.module, "all three failures captured")
	t.throws(function()
		sim:AssertNoErrors()
	end, "script error")
end

tests["connection counting detects leaks after player removal"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"Clean",
			[[
			local conns = {}
			game.Players.PlayerAdded:Connect(function(p)
				conns[p] = p.CharacterAdded:Connect(function() end)
			end)
			game.Players.PlayerRemoving:Connect(function(p)
				conns[p]:Disconnect()
				conns[p] = nil
			end)
		]],
		},
		{
			"ServerScriptService",
			"Script",
			"Leaky",
			[[
			game.Players.PlayerAdded:Connect(function(p)
				p:GetAttributeChangedSignal("Money"):Connect(function() end)
				game:GetService("RunService").Heartbeat:Connect(function() end)
			end)
		]],
		},
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Ui",
			[[
			game:GetService("RunService").RenderStepped:Connect(function() end)
			game.Players.LocalPlayer:GetAttributeChangedSignal("Money"):Connect(function() end)
		]],
		},
	})
	sim:StartServer()
	local baseline = sim:CountConnections()
	local baselineServer = sim:CountConnections("server")
	local p = sim:AddPlayer()
	sim:Advance(0.5)
	t.eq(sim:CountConnections(p), 2, "client connections are attributed to its context")
	t.eq(sim:CountConnections("server") - baselineServer, 3)
	sim:RemovePlayer(p)
	sim:Advance(0.1)
	t.eq(sim:CountConnections(p), 0, "client connections die with the client")
	local leaked = sim:CountConnections("server") - baselineServer
	t.eq(leaked, 2, "Leaky script leaves 2 server connections behind")
	local report = sim:ConnectionReport("server")
	local leakySignals = {}
	for _, g in report do
		if g.script == "ServerScriptService.Leaky" then
			leakySignals[g.signal] = (leakySignals[g.signal] or 0) + g.count
		end
	end
	t.eq(leakySignals["RunService.Heartbeat"], 1)
	t.eq(leakySignals["Player1.GetAttributeChangedSignal(Money)"], 1)
	t.match(sim:FormatConnections("server"), "RunService%.Heartbeat")
	t.ok(sim:CountConnections() >= baseline)
	sim:AssertNoErrors()
end

tests["destroying a script stops its threads and connections"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"Loop",
			[[
			_G.ticks = 0
			game:GetService("RunService").Heartbeat:Connect(function() _G.hb = (_G.hb or 0) + 1 end)
			while true do
				_G.ticks += 1
				task.wait(0.1)
			end
		]],
		},
	})
	sim:StartServer()
	sim:Advance(0.55)
	local g = sim:Globals()
	t.ok(g.ticks >= 5, "loop runs")
	local before = sim:CountConnections()
	sim:Find("ServerScriptService.Loop"):Destroy()
	local ticks, hb = g.ticks, g.hb
	sim:Advance(1)
	t.eq(g.ticks, ticks, "loop thread stopped")
	t.eq(g.hb, hb, "Heartbeat connection disconnected")
	t.eq(sim:CountConnections(), before - 1)
	sim:AssertNoErrors()
end

tests["instance semantics: Destroy, hierarchy events, circular parent, client visibility"] = function(t)
	local sim = build(t, {
		{ "ServerStorage", "Folder", "Hidden", "" },
		{
			"ServerScriptService",
			"Script",
			"H",
			[[
			local folder = Instance.new("Folder")
			folder.Name = "F"
			folder.Parent = workspace
			_G.ev = {}
			folder.ChildAdded:Connect(function(c) table.insert(_G.ev, "added:" .. c.Name) end)
			folder.ChildRemoved:Connect(function(c) table.insert(_G.ev, "removed:" .. c.Name) end)
			workspace.DescendantAdded:Connect(function(d) if d.Name == "Deep" then table.insert(_G.ev, "desc:Deep") end end)
			local p = Instance.new("Part")
			p.Name = "P"
			p.Destroying:Connect(function() table.insert(_G.ev, "destroying:" .. p.Name) end)
			p.AncestryChanged:Connect(function(_, parent) table.insert(_G.ev, "ancestry:" .. tostring(parent)) end)
			p.Parent = folder
			local deep = Instance.new("Part", p)
			deep.Name = "Deep"
			task.wait()
			p:Destroy()
			_G.afterDestroy = { p.Parent == nil, p.Name, deep.Parent == nil }
			_G.lockErr = select(2, pcall(function() p.Parent = workspace end))
			_G.circErr = select(2, pcall(function() folder.Parent = folder end))
			_G.typeofInst = typeof(folder)
			_G.isA = folder:IsA("Instance")
		]],
		},
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"C",
			[[
			_G.ssChildren = #game:GetService("ServerStorage"):GetChildren()
			_G.ssFind = game:GetService("ServerStorage"):FindFirstChild("Hidden")
			_G.ssIndex = select(2, pcall(function() return game.ServerStorage.Hidden end))
		]],
		},
	})
	sim:StartServer()
	local p = sim:AddPlayer()
	sim:Advance(0.2)
	local g = sim:Globals()
	t.eq(g.ev, { "added:P", "ancestry:F", "desc:Deep", "destroying:P", "removed:P", "ancestry:nil" })
	t.eq(g.afterDestroy, { true, "P", true })
	t.match(g.lockErr, "Parent property of P is locked")
	t.match(g.circErr, "own parent")
	t.eq(g.typeofInst, "Instance")
	t.eq(g.isA, true)
	local c = sim:Globals(p)
	t.eq(c.ssChildren, 0, "ServerStorage looks empty to clients")
	t.eq(c.ssFind, nil)
	t.match(c.ssIndex, "not a valid member")
	t.ok(sim:Find("ServerStorage.Hidden") ~= nil, "server/harness still sees it")
	sim:AssertNoErrors()
end

tests["client writes to server-owned state stay client-local and are reported"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"Watch",
			[[
			_G.serverSawChange = false
			workspace:WaitForChild("Baseplate"):GetPropertyChangedSignal("Color"):Connect(function()
				_G.serverSawChange = true
			end)
		]],
		},
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Cheat",
			[[
			local lp = game.Players.LocalPlayer
			if lp.Name ~= "Mallory" then return end
			local plate = workspace.Baseplate
			plate:GetPropertyChangedSignal("Color"):Connect(function() _G.localChange = true end)
			lp:SetAttribute("Money", 999999)
			plate.Color = Color3.new(1, 0, 0)
			plate.Position = Vector3.new(0, 100, 0)
			local mine = Instance.new("Part")
			mine.Parent = workspace
			mine.Color = Color3.new(0, 1, 0)
			workspace.CurrentCamera.FieldOfView = 50
			_G.seen = { lp:GetAttribute("Money"), plate.Color, plate.Position.Y, lp:GetAttributes().Money }
		]],
		},
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Observer",
			[[
			if game.Players.LocalPlayer.Name ~= "Bob" then return end
			task.wait(0.1)
			_G.otherSees = { workspace.Baseplate.Color, game.Players.Mallory:GetAttribute("Money") }
		]],
		},
	})
	local plate = sim:Create("Part", { Name = "Baseplate", Color = roblox.Color3.new(0.5, 0.5, 0.5) }, sim.workspace)
	sim:StartServer()
	local mallory = sim:AddPlayer({ Name = "Mallory" })
	sim:AddPlayer({ Name = "Bob" })
	mallory:SetAttribute("Money", 10)
	sim:Advance(0.3)
	local seen = sim:Globals(mallory).seen
	t.eq(seen[1], 999999, "the client sees its own write")
	t.eq(seen[2], roblox.Color3.new(1, 0, 0))
	t.eq(seen[3], 100)
	t.eq(seen[4], 999999)
	t.eq(sim:Globals(mallory).localChange, true, "local change events fire on that client")
	t.eq(mallory:GetAttribute("Money"), 10, "the server never sees it")
	t.eq(plate.Color, roblox.Color3.new(0.5, 0.5, 0.5))
	t.eq(plate.Position.Y, 0)
	t.eq(sim:Globals().serverSawChange, false)
	local other = sim:Find("Players.Bob")
	t.eq(sim:Globals(other).otherSees, { roblox.Color3.new(0.5, 0.5, 0.5), 10 }, "other clients do not see it")
	local props = {}
	for _, w in sim.ClientWrites do
		props[w.property] = w.context
	end
	t.eq(props["@Money"], "client:Mallory")
	t.eq(props.Color, "client:Mallory")
	t.eq(props.CFrame, "client:Mallory")
	t.eq(props.FieldOfView, nil, "camera is client-owned")
	t.eq(#sim.ClientWrites, 3)
	sim:AssertNoErrors()
	local strict = build(t, {
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Cheat",
			"game.Players.LocalPlayer:SetAttribute('Money', 1)",
		},
	}, { strictReplication = true })
	strict:StartServer()
	strict:AddPlayer()
	strict:Advance(0.1)
	t.eq(#strict.Errors, 1)
	t.match(strict.Errors[1].message, "does not replicate")
end

tests["deterministic Random, math.random and HttpService"] = function(t)
	local function run(seed)
		local sim = build(t, {
			{
				"ServerScriptService",
				"Script",
				"R",
				[[
				local r = Random.new(42)
				local list = { 1, 2, 3, 4, 5 }
				r:Shuffle(list)
				_G.values = { r:NextInteger(1, 100), r:NextNumber(), math.random(1, 6), math.random() }
				_G.list = list
				_G.typeofR = typeof(r)
				local Http = game:GetService("HttpService")
				_G.guid = Http:GenerateGUID(false)
				_G.json = Http:JSONEncode({ a = 1, b = { 1, 2 }, c = "x" })
				_G.decoded = Http:JSONDecode('{"n":[1,2,3],"s":"y"}')
				_G.empty = Http:JSONEncode({})
			]],
			},
		}, { seed = seed })
		sim:StartServer()
		sim:AssertNoErrors()
		return sim:Globals()
	end
	local a, b, c = run(7), run(7), run(8)
	t.eq(a.values, b.values, "same seed, same sequence")
	t.eq(a.list, b.list)
	t.eq(a.values[1], c.values[1], "Random.new(seed) is independent of the sim seed")
	t.neq(a.values[3], nil)
	t.eq(a.typeofR, "Random")
	t.match(a.guid, "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$")
	t.eq(a.json, '{"a":1,"b":[1,2],"c":"x"}')
	t.eq(a.decoded, { n = { 1, 2, 3 }, s = "y" })
	t.eq(a.empty, "[]")
	local r = run(1)
	t.ok(r.values[2] >= 0 and r.values[2] < 1)
	t.ok(r.values[3] >= 1 and r.values[3] <= 6)
end

return tests
