-- sim_selftest_stage4.test.luau: the RbxSim additions for Stage 4 (docs/stage4_design.md §7.0):
--   S1  holds read Enabled / MaxActivationDistance (and HoldDuration, PPS.Enabled) through the
--       holding client's view, so a prompt hidden on that client cannot be held there;
--   S2  a replicated write that changes a value overwrites every client-local value of it
--       (properties, attributes, part moves) and fires the change on those clients;
--   S3  sim:FirePromptEvent(p, prompt, kind): the four kinds, to the server only, unchecked, in
--       call order (also after the player left);
--   S4  DataStore:FailKey(key, count, message?, ops?) and DataStore:SetKeyLatency(key, s);
--   S4b FailKey(..., { after = true }): the write lands, then the call errors;
--   S6  sim:Shutdown({ order = "playersFirst" }) (the default still runs BindToClose first);
--   S7  Sim.new({ removingOrder = "reverse" }) (the default still runs handlers FIFO);
--   S8  prompt events reach the server after remoteLatency, the holding client at once.

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Color3 = roblox.Color3

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

-- A part with a StealPrompt at the origin (1 s hold, 10 studs reach).
local function promptWorld(sim, props)
	local slot = sim:Create("Part", { Name = "Slot", Anchored = true, CFrame = CFrame.new(0, 2, 0) }, sim.workspace)
	local p = { Name = "StealPrompt", HoldDuration = 1, MaxActivationDistance = 10 }
	for k, v in props or {} do
		p[k] = v
	end
	local prompt = sim:Create("ProximityPrompt", p, slot)
	return slot, prompt
end

-- Server + client logs of every prompt event of `Workspace.Slot.StealPrompt`, with times.
local PROMPT_LOG_SERVER = [[
	local PPS = game:GetService("ProximityPromptService")
	local prompt = workspace:WaitForChild("Slot"):WaitForChild("StealPrompt")
	_G.log = {}
	local function log(s) table.insert(_G.log, { s, os.clock() }) end
	prompt.PromptButtonHoldBegan:Connect(function(p) log("began:" .. p.Name) end)
	prompt.PromptButtonHoldEnded:Connect(function(p) log("ended:" .. p.Name) end)
	prompt.Triggered:Connect(function(p) log("triggered:" .. p.Name) end)
	prompt.TriggerEnded:Connect(function(p) log("triggerEnded:" .. p.Name) end)
	PPS.PromptButtonHoldBegan:Connect(function(pr, p) log("pps.began:" .. pr.Name .. ":" .. p.Name) end)
	PPS.PromptButtonHoldEnded:Connect(function(pr, p) log("pps.ended:" .. pr.Name .. ":" .. p.Name) end)
	PPS.PromptTriggered:Connect(function(pr, p) log("pps.triggered:" .. pr.Name .. ":" .. p.Name) end)
	PPS.PromptTriggerEnded:Connect(function(pr, p) log("pps.triggerEnded:" .. pr.Name .. ":" .. p.Name) end)
]]
local PROMPT_LOG_CLIENT = [[
	local prompt = workspace:WaitForChild("Slot"):WaitForChild("StealPrompt")
	_G.log = {}
	local function log(s) table.insert(_G.log, { s, os.clock() }) end
	prompt.PromptButtonHoldBegan:Connect(function(p) log("began:" .. p.Name) end)
	prompt.PromptButtonHoldEnded:Connect(function(p) log("ended:" .. p.Name) end)
	prompt.Triggered:Connect(function(p) log("triggered:" .. p.Name) end)
	prompt.TriggerEnded:Connect(function(p) log("triggerEnded:" .. p.Name) end)
]]

local function names(log)
	local out = {}
	for i, e in log do
		out[i] = e[1]
	end
	return out
end

local function timeOf(log, name)
	for _, e in log do
		if e[1] == name then
			return e[2]
		end
	end
	return nil
end

-- S1 ------------------------------------------------------------------------------------------------

tests["S1: a prompt hidden on the holding client (MaxActivationDistance 0, Enabled false) cannot be held there"] = function(
	t
)
	local sim = build(t, {
		{ "ServerScriptService", "Script", "Log", PROMPT_LOG_SERVER },
	})
	local _, prompt = promptWorld(sim)
	sim:StartServer()
	local owner = sim:AddPlayer({ Name = "Owner" })
	local thief = sim:AddPlayer({ Name = "Thief" })
	sim:Advance(0.2)
	local g = sim:Globals()
	sim:Teleport(owner, Vector3.new(3, 3, 0))
	sim:Teleport(thief, Vector3.new(-3, 3, 0))

	-- the owner's client hides the prompt with the property the server never writes
	sim:Run(function()
		prompt.MaxActivationDistance = 0
	end, owner)
	t.eq(prompt.MaxActivationDistance, 10, "the server keeps its value")
	t.eq(
		sim:Run(function()
			return prompt.MaxActivationDistance
		end, owner),
		0,
		"the owner's client sees 0"
	)
	local ok, why = sim:CanUsePrompt(owner, prompt)
	t.eq(ok, false)
	t.match(why, "out of range %(%d+%.%d > 0%.0%)")
	local triggered
	triggered, why = sim:HoldPrompt(owner, prompt)
	t.eq(triggered, false, "the owner cannot hold his own hidden prompt")
	t.match(why, "out of range")
	t.eq(#g.log, 0, "nothing reached the server")
	-- MaxActivationDistance 0 is never in range, even standing on the attachment
	sim:Teleport(owner, Vector3.new(0, 2, 0))
	t.eq((sim:CanUsePrompt(owner, prompt)), false, "0 reach: never in range")
	t.ok(sim:CanUsePrompt(owner, prompt, { ignoreDistance = true }), "ignoreDistance skips the reach")

	-- the thief's client did not hide it: he can
	t.ok(sim:HoldPrompt(thief, prompt), "another client still holds it")
	t.eq(names(g.log)[1], "began:Thief")

	-- a hold in progress ends when the holding client hides the prompt (a stock prompt that
	-- leaves its range ends the hold on the client)
	table.clear(g.log)
	local hold = sim:BeginHold(thief, prompt)
	sim:Advance(0.5)
	sim:Run(function()
		prompt.MaxActivationDistance = 0
	end, thief)
	sim:Advance(0.1)
	t.eq(hold.active, false)
	t.eq(hold.triggered, false)
	t.match(hold.cancelReason, "out of range")
	t.eq(names(g.log), { "began:Thief", "pps.began:StealPrompt:Thief", "ended:Thief", "pps.ended:StealPrompt:Thief" })
	-- showing it again restores the reach
	sim:Run(function()
		prompt.MaxActivationDistance = 10
	end, thief)
	t.ok(sim:HoldPrompt(thief, prompt), "shown again: holdable")

	-- a client-local Enabled = false: "prompt disabled" on that client only
	sim:Run(function()
		prompt.Enabled = false
	end, thief)
	t.eq(prompt.Enabled, true, "the server's stays enabled")
	triggered, why = sim:HoldPrompt(thief, prompt)
	t.eq(triggered, false)
	t.eq(why, "prompt disabled")
	t.ok(sim:CanUsePrompt(thief, prompt, { ignoreEnabled = true }), "ignoreEnabled skips the local value too")
	sim:Run(function()
		prompt.Enabled = true
	end, thief)

	-- the client's HoldDuration times the hold (a client-local 3 s on a 1 s prompt)
	sim:Run(function()
		prompt.HoldDuration = 3
	end, thief)
	hold = sim:BeginHold(thief, prompt)
	sim:Advance(1.5)
	t.eq(hold.triggered, false, "not at the server's 1 s")
	sim:Advance(1.6)
	t.eq(hold.triggered, true, "at the client's 3 s")
	sim:ReleasePrompt(thief, prompt)
	t.eq(prompt.HoldDuration, 1, "the server's HoldDuration is untouched")
	sim:Run(function()
		prompt.HoldDuration = 1
	end, thief)

	-- ProximityPromptService.Enabled = false on one client turns its prompts off there
	sim:Run(function()
		sim.game:GetService("ProximityPromptService").Enabled = false
	end, thief)
	triggered, why = sim:HoldPrompt(thief, prompt)
	t.eq(triggered, false)
	t.eq(why, "ProximityPromptService disabled")
	sim:AssertNoErrors()
end

tests["S1+S2: the server toggles Enabled 20 times; the client's MaxActivationDistance 0 survives every frame"] = function(
	t
)
	local sim = build(t, {})
	local _, prompt = promptWorld(sim)
	sim:StartServer()
	local owner = sim:AddPlayer({ Name = "Owner" })
	sim:Advance(0.2)
	sim:Teleport(owner, Vector3.new(2, 3, 0))
	sim:Run(function()
		prompt.MaxActivationDistance = 0
	end, owner)
	-- 20 server writes, 1..3 frames apart (a fixed "random" pattern)
	local frames = { 1, 3, 2, 1, 2, 3, 1, 1, 2, 3, 2, 1, 3, 1, 2, 2, 3, 1, 1, 2 }
	for i, gap in frames do
		prompt.Enabled = i % 2 == 0
		for _ = 1, gap do
			sim:Step()
			local seen = sim:Run(function()
				return prompt.MaxActivationDistance
			end, owner)
			t.eq(seen, 0, "frame after toggle " .. i .. ": still hidden on the owner's client")
			local ok, why = sim:CanUsePrompt(owner, prompt)
			t.eq(ok, false)
			if prompt.Enabled then
				t.match(why, "out of range")
			else
				t.eq(why, "prompt disabled")
			end
		end
	end
	t.eq(prompt.MaxActivationDistance, 10, "the server never wrote it")
	sim:AssertNoErrors()
end

-- S2 ------------------------------------------------------------------------------------------------

tests["S2: a server write overwrites a client-local property and fires the change on that client"] = function(t)
	local sim = build(t, {
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Watch",
			[[
			local prompt = workspace:WaitForChild("Slot"):WaitForChild("StealPrompt")
			_G.enabledEvents = {}
			prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
				table.insert(_G.enabledEvents, prompt.Enabled)
			end)
			_G.changed = {}
			prompt.Changed:Connect(function(prop)
				table.insert(_G.changed, prop)
			end)
		]],
		},
	})
	local _, prompt = promptWorld(sim)
	sim:StartServer()
	local hider = sim:AddPlayer({ Name = "Hider" })
	local other = sim:AddPlayer({ Name = "Other" })
	sim:Advance(0.2)
	local gh, go = sim:Globals(hider), sim:Globals(other)
	local function enabledOn(p)
		return sim:Run(function()
			return prompt.Enabled
		end, p)
	end

	sim:Run(function()
		prompt.Enabled = false
		prompt.MaxActivationDistance = 0
	end, hider)
	sim:Advance(0.05)
	t.eq(gh.enabledEvents, { false }, "the local write fires on the hider's client")
	t.eq(go.enabledEvents, {}, "… and nowhere else")
	t.eq(enabledOn(hider), false)
	t.eq(enabledOn(other), true)

	-- the server writes the value it already has: nothing replicates, the local value stays
	prompt.Enabled = true
	sim:Advance(0.05)
	t.eq(enabledOn(hider), false, "an unchanged server value does not overwrite the local one")
	t.eq(gh.enabledEvents, { false })

	-- the server changes it (true → false): the hider's local key is dropped; its view was
	-- already false, so only the other client hears a change
	prompt.Enabled = false
	sim:Advance(0.05)
	t.eq(enabledOn(hider), false)
	t.eq(enabledOn(other), false)
	t.eq(gh.enabledEvents, { false }, "the hider's view did not change: no event there")
	t.eq(go.enabledEvents, { false }, "the other client hears the change")

	-- the server re-enables it: both clients see true and both hear it (the hider's local hide
	-- is gone, as in Roblox)
	prompt.Enabled = true
	sim:Advance(0.05)
	t.eq(enabledOn(hider), true, "the server's write replicated over the local value")
	t.eq(gh.enabledEvents, { false, true })
	t.eq(go.enabledEvents, { false, true })

	-- a hide re-applied after that is local again …
	sim:Run(function()
		prompt.Enabled = false
	end, hider)
	t.eq(enabledOn(hider), false)
	-- … and the other key the hider wrote was never touched by the Enabled writes
	t.eq(
		sim:Run(function()
			return prompt.MaxActivationDistance
		end, hider),
		0,
		"MaxActivationDistance 0 kept through every Enabled write"
	)
	-- a server write of THAT key overwrites it as well
	prompt.MaxActivationDistance = 12
	sim:Advance(0.05)
	t.eq(
		sim:Run(function()
			return prompt.MaxActivationDistance
		end, hider),
		12
	)
	t.ok(table.find(gh.changed, "MaxActivationDistance") ~= nil, "Changed fired on the hider for it")
	sim:AssertNoErrors()
end

tests["S2: server attribute writes and part moves overwrite client-local ones too"] = function(t)
	local sim = build(t, {
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Watch",
			[[
			local lamp = workspace:WaitForChild("Lamp")
			_G.attrEvents = {}
			lamp:GetAttributeChangedSignal("State"):Connect(function()
				table.insert(_G.attrEvents, lamp:GetAttribute("State") or "nil")
			end)
			_G.anyAttr = 0
			lamp.AttributeChanged:Connect(function() _G.anyAttr += 1 end)
			_G.moves = 0
			lamp:GetPropertyChangedSignal("CFrame"):Connect(function() _G.moves += 1 end)
		]],
		},
	})
	local lamp = sim:Create("Part", {
		Name = "Lamp",
		Anchored = true,
		CFrame = CFrame.new(0, 5, 0),
		Color = Color3.new(1, 1, 1),
	}, sim.workspace)
	lamp:SetAttribute("State", "off")
	lamp:SetAttribute("Owner", 1)
	sim:StartServer()
	local p = sim:AddPlayer({ Name = "Viewer" })
	sim:Advance(0.2)
	local g = sim:Globals(p)
	local function seen(fn)
		return sim:Run(fn, p)
	end

	-- attributes
	sim:Run(function()
		lamp:SetAttribute("State", "flash")
		lamp:SetAttribute("Owner", 99)
	end, p)
	sim:Advance(0.05)
	t.eq(g.attrEvents, { "flash" })
	t.eq(lamp:GetAttribute("State"), "off", "the server never sees the local attribute")
	lamp:SetAttribute("State", "off") -- unchanged on the server: nothing replicates
	sim:Advance(0.05)
	t.eq(
		seen(function()
			return lamp:GetAttribute("State")
		end),
		"flash"
	)
	lamp:SetAttribute("State", "theft")
	sim:Advance(0.05)
	t.eq(
		seen(function()
			return lamp:GetAttribute("State")
		end),
		"theft",
		"a server change overwrites the local attribute"
	)
	t.eq(g.attrEvents, { "flash", "theft" })
	t.eq(
		seen(function()
			return lamp:GetAttribute("Owner")
		end),
		99,
		"another attribute's local value stays"
	)
	t.eq(
		seen(function()
			return lamp:GetAttributes().Owner
		end),
		99
	)
	lamp:SetAttribute("State", nil)
	sim:Advance(0.05)
	t.eq(g.attrEvents, { "flash", "theft", "nil" }, "a server clear replicates too")

	-- part moves
	local moves0 = g.moves
	sim:Run(function()
		lamp.CFrame = CFrame.new(0, 50, 0)
	end, p)
	sim:Advance(0.05)
	t.eq(g.moves, moves0 + 1, "the local move fires on the client")
	t.near(lamp.Position, Vector3.new(0, 5, 0), 1e-6, "the server's part stays")
	lamp.CFrame = CFrame.new(10, 5, 0)
	sim:Advance(0.05)
	t.near(
		seen(function()
			return lamp.Position
		end),
		Vector3.new(10, 5, 0),
		1e-6,
		"a server move overwrites the local CFrame"
	)
	t.eq(g.moves, moves0 + 2, "… and fires the change on that client")
	t.eq(#sim.ClientWrites, 3, "the local writes are still reported")
	sim:AssertNoErrors()
end

-- S3 ------------------------------------------------------------------------------------------------

tests["S3: FirePromptEvent sends the four kinds to the server only, unchecked, in call order"] = function(t)
	local sim = build(t, {
		{ "ServerScriptService", "Script", "Log", PROMPT_LOG_SERVER },
		{ "StarterPlayer.StarterPlayerScripts", "LocalScript", "Log", PROMPT_LOG_CLIENT },
	})
	-- disabled, 1 stud of reach and a 3 s hold: none of it matters to a forged event
	local _, prompt = promptWorld(sim, { Enabled = false, MaxActivationDistance = 1, HoldDuration = 3 })
	sim:StartServer()
	local cheat = sim:AddPlayer({ Name = "Cheat" })
	sim:Advance(0.2)
	sim:Teleport(cheat, Vector3.new(200, 3, 0))
	local g, gc = sim:Globals(), sim:Globals(cheat)

	sim:FirePromptEvent(cheat, prompt, "Triggered")
	t.eq(names(g.log), { "triggered:Cheat", "pps.triggered:StealPrompt:Cheat" }, "delivered before the call returns")
	t.eq(#gc.log, 0, "the sender's own client handlers get nothing")
	t.eq(#sim.input.holds, 0, "no sim hold was started")

	table.clear(g.log)
	sim:FirePromptEvent(cheat, prompt, "HoldBegan")
	sim:FirePromptEvent(cheat, prompt, "HoldEnded")
	sim:FirePromptEvent(cheat, prompt, "Triggered")
	sim:FirePromptEvent(cheat, prompt, "TriggerEnded")
	t.eq(names(g.log), {
		"began:Cheat",
		"pps.began:StealPrompt:Cheat",
		"ended:Cheat",
		"pps.ended:StealPrompt:Cheat",
		"triggered:Cheat",
		"pps.triggered:StealPrompt:Cheat",
		"triggerEnded:Cheat",
		"pps.triggerEnded:StealPrompt:Cheat",
	}, "every kind, in call order (HoldEnded before Triggered kept)")
	t.eq(#gc.log, 0)

	-- a dead sender, too
	table.clear(g.log)
	sim:KillCharacter(cheat)
	sim:FirePromptEvent(cheat, prompt, "HoldBegan")
	t.eq(names(g.log)[1], "began:Cheat", "no alive check")

	-- bad arguments are the test's mistake
	t.throws(function()
		sim:FirePromptEvent(cheat, prompt, "Shown")
	end, "kind must be")
	t.throws(function()
		sim:FirePromptEvent(cheat, sim.workspace.Slot, "Triggered")
	end, "ProximityPrompt expected")

	-- an event still in flight after the sender left reaches the server with a parentless Player
	table.clear(g.log)
	sim:AddScript(
		sim:Find("ServerScriptService"),
		"Script",
		"Parent",
		[[
		workspace.Slot.StealPrompt.PromptButtonHoldBegan:Connect(function(p)
			_G.parentAtBegan = tostring(p.Parent)
		end)
	]]
	)
	sim:Flush()
	sim:RemovePlayer(cheat)
	sim:Advance(0.1)
	sim:FirePromptEvent(cheat, prompt, "HoldBegan")
	t.eq(names(g.log)[1], "began:Cheat")
	t.eq(g.parentAtBegan, "nil", "the Player is already out of Players")
	sim:AssertNoErrors()
end

-- S8 ------------------------------------------------------------------------------------------------

tests["S8: with remoteLatency the prompt events reach the server late and the holding client at once, in order"] = function(
	t
)
	local LAT = 0.15
	local sim = build(t, {
		{ "ServerScriptService", "Script", "Log", PROMPT_LOG_SERVER },
		{ "StarterPlayer.StarterPlayerScripts", "LocalScript", "Log", PROMPT_LOG_CLIENT },
	}, { remoteLatency = LAT })
	local _, prompt = promptWorld(sim)
	sim:StartServer()
	local p = sim:AddPlayer({ Name = "Thief" })
	sim:Advance(0.5)
	sim:Teleport(p, Vector3.new(3, 3, 0))
	local g, gc = sim:Globals(), sim:Globals(p)

	local t0 = sim:Time()
	local hold = sim:BeginHold(p, prompt)
	t.eq(names(gc.log), { "began:Thief" }, "the holding client hears HoldBegan at once")
	t.eq(#g.log, 0, "the server not yet")
	sim:Advance(1.05)
	t.eq(hold.triggered, true)
	sim:ReleasePrompt(p, prompt)
	sim:Advance(0.5)
	t.eq(names(gc.log), { "began:Thief", "triggered:Thief", "ended:Thief", "triggerEnded:Thief" })
	t.eq(names(g.log), {
		"began:Thief",
		"pps.began:StealPrompt:Thief",
		"triggered:Thief",
		"pps.triggered:StealPrompt:Thief",
		"ended:Thief",
		"pps.ended:StealPrompt:Thief",
		"triggerEnded:Thief",
		"pps.triggerEnded:StealPrompt:Thief",
	}, "the server gets all of them, in the order they happened")
	for _, name in { "began:Thief", "triggered:Thief", "ended:Thief", "triggerEnded:Thief" } do
		t.near(timeOf(g.log, name) - timeOf(gc.log, name), LAT, 0.02, name .. " arrives one latency later")
	end
	t.near(timeOf(g.log, "began:Thief") - t0, LAT, 0.02)

	-- forged events take the same road
	table.clear(g.log)
	local f0 = sim:Time()
	sim:FirePromptEvent(p, prompt, "HoldEnded")
	sim:FirePromptEvent(p, prompt, "Triggered")
	t.eq(#g.log, 0, "in flight")
	sim:Advance(LAT + 0.05)
	t.eq(
		names(g.log),
		{ "ended:Thief", "pps.ended:StealPrompt:Thief", "triggered:Thief", "pps.triggered:StealPrompt:Thief" }
	)
	t.near(g.log[1][2] - f0, LAT, 0.02)
	sim:AssertNoErrors()

	-- no latency (the default): the server's handlers run inside BeginHold, as before
	local now = build(t, { { "ServerScriptService", "Script", "Log", PROMPT_LOG_SERVER } })
	local _, prompt2 = promptWorld(now)
	now:StartServer()
	local q = now:AddPlayer({ Name = "Quick" })
	now:Advance(0.2)
	now:Teleport(q, Vector3.new(3, 3, 0))
	now:BeginHold(q, prompt2)
	t.eq(names(now:Globals().log), { "began:Quick", "pps.began:StealPrompt:Quick" }, "same frame")
	now:AssertNoErrors()
end

-- S4 / S4b ------------------------------------------------------------------------------------------

local DS_SCRIPT = [[
	local store = game:GetService("DataStoreService"):GetDataStore("PlayerData")
	_G.results = {}
	local function record(label, ok, res)
		-- (the sim reports an API error at the calling line: strip "Script:9: ")
		local err = (not ok) and (string.gsub(tostring(res), "^[%w%.]+:%d+: ", "")) or nil
		table.insert(_G.results, { label = label, ok = ok, err = err, at = os.clock() })
	end
	function _G.update(key, value)
		local t0 = os.clock()
		local ok, res = pcall(function()
			return store:UpdateAsync(key, function() return value end)
		end)
		record("update:" .. key, ok, res)
		_G.took = os.clock() - t0
	end
	function _G.cancel(key)
		local ok, res = pcall(function()
			return store:UpdateAsync(key, function() return nil end)
		end)
		record("cancel:" .. key, ok, res)
	end
	function _G.get(key)
		local ok, res = pcall(function() return store:GetAsync(key) end)
		record("get:" .. key, ok, res)
		_G.got = ok and res or nil
	end
	function _G.set(key, value)
		local ok, res = pcall(function() return store:SetAsync(key, value) end)
		record("set:" .. key, ok, res)
	end
	function _G.remove(key)
		local ok, res = pcall(function() return store:RemoveAsync(key) end)
		record("remove:" .. key, ok, res)
	end
	function _G.increment(key)
		local ok, res = pcall(function() return store:IncrementAsync(key, 1) end)
		record("increment:" .. key, ok, res)
	end
]]

-- Runs _G[fn](...) in the server context and waits for it.
local function call(sim, fn, ...)
	local args = table.pack(...)
	sim:Run(function()
		sim:Globals()[fn](table.unpack(args, 1, args.n))
	end)
end

local function last(sim)
	local r = sim:Globals().results
	return r[#r]
end

tests["S4: FailKey fails one key's requests (count, message, ops) while other keys succeed"] = function(t)
	local sim = build(t, { { "ServerScriptService", "Script", "Data", DS_SCRIPT } })
	sim.DataStore:SetWriteCooldown(0)
	sim:StartServer()
	sim.DataStore:FailKey("victim", 2, "500: victim down", { "UpdateAsync" })

	call(sim, "update", "victim", { fish = 1 })
	t.eq(last(sim).ok, false)
	t.eq(last(sim).err, "500: victim down")
	call(sim, "update", "thief", { fish = 1 })
	t.eq(last(sim).ok, true, "another key is not affected")
	call(sim, "get", "victim")
	t.eq(last(sim).ok, true, "other operations on the key are not affected")
	call(sim, "update", "victim", { fish = 2 })
	t.eq(last(sim).ok, false, "the 2nd failure")
	call(sim, "update", "victim", { fish = 3 })
	t.eq(last(sim).ok, true, "count used up")
	t.eq(sim.DataStore:Peek("PlayerData", "victim"), { fish = 3 })
	local failed = 0
	for _, c in sim.DataStore.Calls do
		if c.key == "victim" and c.failed then
			failed += 1
		end
	end
	t.eq(failed, 2, "Calls marks the failures")

	-- default message, any operation, math.huge until cleared, FailNext still separate
	sim.DataStore:FailKey("victim", math.huge)
	for _ = 1, 5 do
		call(sim, "get", "victim")
		t.eq(last(sim).ok, false)
	end
	t.match(last(sim).err, "502: API Services rejected request")
	sim.DataStore:FailKey("victim", 0)
	call(sim, "get", "victim")
	t.eq(last(sim).ok, true, "count 0 clears the key")
	sim.DataStore:FailKey("victim", 1, "key")
	sim.DataStore:FailNext(1, "global")
	call(sim, "get", "victim")
	t.eq(last(sim).err, "key", "the key's failure first")
	call(sim, "get", "victim")
	t.eq(last(sim).err, "global", "then FailNext")
	call(sim, "get", "victim")
	t.eq(last(sim).ok, true)
	t.throws(function()
		sim.DataStore:FailKey("victim", 1, nil, { "UpdateAsnyc" })
	end, "unknown DataStore operation")
	t.throws(function()
		sim.DataStore:FailKey(nil :: any, 1)
	end, "expects a key")
	sim:AssertNoErrors()
end

tests["S4: SetKeyLatency slows one key's requests; nil restores the global latency"] = function(t)
	local sim = build(t, { { "ServerScriptService", "Script", "Data", DS_SCRIPT } })
	sim.DataStore:SetWriteCooldown(0)
	sim:StartServer()
	sim.DataStore:SetKeyLatency("victim", 4)
	call(sim, "update", "victim", { fish = 1 })
	t.near(sim:Globals().took, 4, 0.02, "the slow key")
	call(sim, "update", "thief", { fish = 1 })
	t.near(sim:Globals().took, 0.05, 0.02, "the other key: the global SetLatency (0.05)")
	sim.DataStore:SetKeyLatency("thief", 0)
	call(sim, "update", "thief", { fish = 2 })
	t.near(sim:Globals().took, 0, 1e-6, "0 = no wait for that key")
	sim.DataStore:SetKeyLatency("victim", nil)
	call(sim, "update", "victim", { fish = 2 })
	t.near(sim:Globals().took, 0.05, 0.02, "cleared")
	-- both together: the key's write lands after its latency, then fails
	sim.DataStore:SetKeyLatency("victim", 2)
	sim.DataStore:FailKey("victim", 1, "late", { after = true })
	call(sim, "update", "victim", { fish = 3 })
	t.near(sim:Globals().took, 2, 0.02)
	t.eq(last(sim).err, "late")
	t.eq(sim.DataStore:Peek("PlayerData", "victim"), { fish = 3 })
	t.throws(function()
		sim.DataStore:SetKeyLatency("victim", -1)
	end, "must be a number")
	sim:AssertNoErrors()
end

tests["S4b: FailKey(..., { after = true }) lands the write, then the call errors (an ambiguous commit)"] = function(t)
	local sim = build(t, { { "ServerScriptService", "Script", "Data", DS_SCRIPT } })
	sim.DataStore:SetWriteCooldown(0)
	sim:StartServer()
	sim.DataStore:Poke("PlayerData", "victim", { fish = { "Perch", "Carp" } })

	sim.DataStore:FailKey("victim", 1, "500: reply lost", { "UpdateAsync", after = true })
	call(sim, "update", "victim", { fish = { "Perch" } })
	t.eq(last(sim).ok, false, "the caller sees an error")
	t.eq(last(sim).err, "500: reply lost")
	t.eq(sim.DataStore:Peek("PlayerData", "victim"), { fish = { "Perch" } }, "… but the write landed")
	local c = sim.DataStore.Calls[#sim.DataStore.Calls]
	t.eq(c.failed, true)
	t.eq(c.landed, true, "Calls marks it as landed")
	-- a retry sees its own write
	call(sim, "get", "victim")
	t.eq(sim:Globals().got, { fish = { "Perch" } })

	-- every write operation; ops given as opts.ops
	sim.DataStore:FailKey("k", 4, "lost", { after = true, ops = { "SetAsync", "IncrementAsync", "RemoveAsync" } })
	call(sim, "set", "k", 5)
	t.eq(last(sim).err, "lost")
	t.eq(sim.DataStore:Peek("PlayerData", "k"), 5)
	call(sim, "increment", "k")
	t.eq(last(sim).err, "lost")
	t.eq(sim.DataStore:Peek("PlayerData", "k"), 6)
	call(sim, "update", "k", 9)
	t.eq(last(sim).ok, true, "UpdateAsync is not in ops")
	call(sim, "remove", "k")
	t.eq(last(sim).err, "lost")
	t.eq(sim.DataStore:Peek("PlayerData", "k"), nil, "removed anyway")
	-- a cancelled UpdateAsync writes nothing and still errors
	sim.DataStore:FailKey("victim", 1, "lost", { after = true })
	call(sim, "cancel", "victim")
	t.eq(last(sim).err, "lost")
	t.eq(sim.DataStore:Peek("PlayerData", "victim"), { fish = { "Perch" } })
	-- the 4th entry of "k" is left: it applies to the next matching request only
	call(sim, "set", "k", 1)
	t.eq(last(sim).err, "lost")
	call(sim, "set", "k", 2)
	t.eq(last(sim).ok, true)
	sim:AssertNoErrors()
end

-- S6 / S7 -------------------------------------------------------------------------------------------

local ORDER_SCRIPT = [[
	_G.order = {}
	local Players = game:GetService("Players")
	Players.PlayerRemoving:Connect(function(p)
		table.insert(_G.order, "removing:" .. p.Name)
	end)
	game:BindToClose(function()
		table.insert(_G.order, "close:" .. #Players:GetPlayers())
		task.wait(1)
		table.insert(_G.order, "closed")
	end)
]]

tests["S6: Shutdown({ order = 'playersFirst' }) removes everyone before BindToClose; the default runs BindToClose first"] = function(
	t
)
	-- default (today's behaviour): BindToClose starts first, with both players still in
	local sim = build(t, { { "ServerScriptService", "Script", "Order", ORDER_SCRIPT } })
	sim:StartServer()
	sim:AddPlayer({ Name = "A" })
	sim:AddPlayer({ Name = "B" })
	sim:Advance(0.2)
	local r = sim:Shutdown()
	t.eq(r.completed, true)
	t.eq(sim:Globals().order, { "close:2", "removing:A", "removing:B", "closed" })
	t.eq(#sim:GetPlayers(), 0)
	sim:AssertNoErrors()

	-- players first: every PlayerRemoving before the callbacks, which find nobody
	local pf = build(t, { { "ServerScriptService", "Script", "Order", ORDER_SCRIPT } })
	pf:StartServer()
	pf:AddPlayer({ Name = "A" })
	pf:AddPlayer({ Name = "B" })
	pf:Advance(0.2)
	r = pf:Shutdown({ order = "playersFirst" })
	t.eq(r.completed, true)
	t.near(r.elapsed, 1, 0.05)
	t.eq(pf:Globals().order, { "removing:A", "removing:B", "close:0", "closed" })
	t.eq(#pf:GetPlayers(), 0)
	pf:AssertNoErrors()

	t.throws(function()
		pf:Shutdown({ order = "random" })
	end, "order must be")
	t.throws(function()
		pf:Shutdown({ order = "playersFirst", kickPlayers = false })
	end, "contradicts")
	-- the explicit default name works
	local cf = build(t, { { "ServerScriptService", "Script", "Order", ORDER_SCRIPT } })
	cf:StartServer()
	cf:AddPlayer({ Name = "A" })
	cf:Advance(0.2)
	cf:Shutdown({ order = "closeFirst" })
	t.eq(cf:Globals().order, { "close:1", "removing:A", "closed" })
end

local REMOVING_SCRIPT = [[
	_G.removing = {}
	_G.added = {}
	local Players = game:GetService("Players")
	for i = 1, 3 do
		Players.PlayerRemoving:Connect(function(p)
			table.insert(_G.removing, i .. ":" .. p.Name)
		end)
		Players.PlayerAdded:Connect(function(p)
			table.insert(_G.added, i .. ":" .. p.Name)
		end)
	end
]]

tests["S7: removingOrder 'reverse' runs PlayerRemoving handlers last-connected first; the default keeps FIFO"] = function(
	t
)
	local fifo = build(t, { { "ServerScriptService", "Script", "Removing", REMOVING_SCRIPT } })
	fifo:StartServer()
	local a = fifo:AddPlayer({ Name = "A" })
	fifo:Advance(0.1)
	fifo:RemovePlayer(a)
	fifo:Advance(0.1)
	t.eq(fifo:Globals().removing, { "1:A", "2:A", "3:A" }, "default: connection order")
	fifo:AssertNoErrors()

	local rev = build(
		t,
		{ { "ServerScriptService", "Script", "Removing", REMOVING_SCRIPT } },
		{ removingOrder = "reverse" }
	)
	rev:StartServer()
	local b = rev:AddPlayer({ Name = "B" })
	rev:Advance(0.1)
	t.eq(rev:Globals().added, { "1:B", "2:B", "3:B" }, "other signals keep their order")
	rev:RemovePlayer(b)
	rev:Advance(0.1)
	t.eq(rev:Globals().removing, { "3:B", "2:B", "1:B" }, "reverse")
	-- a Kick and a players-first Shutdown take the same road
	local c = rev:AddPlayer({ Name = "C" })
	local d = rev:AddPlayer({ Name = "D" })
	rev:Advance(0.1)
	table.clear(rev:Globals().removing)
	c:Kick("bye")
	rev:Advance(0.1)
	t.eq(rev:Globals().removing, { "3:C", "2:C", "1:C" })
	table.clear(rev:Globals().removing)
	rev:Shutdown({ order = "playersFirst" })
	t.eq(rev:Globals().removing, { "3:D", "2:D", "1:D" })
	t.eq(d.Parent, nil)
	rev:AssertNoErrors()

	t.eq(t.sim({ removingOrder = "fifo" }).opts.removingOrder, "fifo", "the explicit default name is accepted")
	t.throws(function()
		t.sim({ removingOrder = "lifo" })
	end, "removingOrder must be")
end

return tests
