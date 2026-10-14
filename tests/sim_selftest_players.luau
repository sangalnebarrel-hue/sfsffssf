-- sim_selftest_players.luau: characters, death/respawn, StarterGui reset rules,
-- GUI clicks and layout, input, ProximityPrompt holds, tools, kicks.

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local Vector2 = roblox.Vector2
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

tests["LoadCharacter, CharacterAdded, Died and auto respawn"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"Chars",
			[[
			game.Players.RespawnTime = 2
			_G.added, _G.died, _G.removing = 0, 0, 0
			game.Players.PlayerAdded:Connect(function(p)
				p.CharacterAdded:Connect(function(char)
					_G.added += 1
					local hum = char:WaitForChild("Humanoid")
					_G.lastHealth = hum.Health
					_G.lastChar = char
					hum.Died:Connect(function() _G.died += 1 end)
				end)
				p.CharacterRemoving:Connect(function() _G.removing += 1 end)
			end)
		]],
		},
	})
	sim:Create(
		"SpawnLocation",
		{ Name = "Spawn", CFrame = CFrame.new(50, 0, 0), Size = Vector3.new(6, 1, 6) },
		sim.workspace
	)
	sim:StartServer()
	local p = sim:AddPlayer({ Name = "Hero" })
	sim:Advance(0.2)
	local g = sim:Globals()
	t.eq(g.added, 1)
	t.eq(g.lastHealth, 100)
	local char = sim:GetCharacter(p)
	t.ok(char ~= nil and char.Parent == sim.workspace)
	t.ok(p.Character == char)
	t.ok(char.PrimaryPart == char.HumanoidRootPart)
	t.near(char.HumanoidRootPart.Position, Vector3.new(50, 3.5, 0), 1e-4, "spawned on top of the SpawnLocation")
	t.ok(sim.game.Players:GetPlayerFromCharacter(char) == p)
	local hum = sim:GetHumanoid(p)
	t.eq(hum.WalkSpeed, 16)
	hum:TakeDamage(30)
	t.eq(hum.Health, 70)
	sim:KillCharacter(p)
	sim:Advance(0.1)
	t.eq(g.died, 1)
	t.eq(hum:GetState(), Enum.HumanoidStateType.Dead)
	sim:Advance(1.5)
	t.eq(g.added, 1, "respawn waits for RespawnTime")
	sim:Advance(0.6)
	t.eq(g.added, 2, "auto respawn after RespawnTime")
	t.eq(g.removing, 1)
	t.ok(sim:GetCharacter(p) ~= char, "new character model")
	t.eq(char.Parent, nil, "old character removed")
	sim:AssertNoErrors()
end

tests["respawn driven by a script when CharacterAutoLoads is false"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"Respawner",
			[[
			game.Players.CharacterAutoLoads = false
			_G.spawns = 0
			local function onPlayer(p)
				p.CharacterAdded:Connect(function(char)
					_G.spawns += 1
					char:WaitForChild("Humanoid").Died:Connect(function()
						task.wait(1)
						p:LoadCharacter()
					end)
				end)
				p:LoadCharacter()
			end
			game.Players.PlayerAdded:Connect(onPlayer)
			for _, p in game.Players:GetPlayers() do onPlayer(p) end
		]],
		},
	})
	sim:StartServer()
	local p = sim:AddPlayer()
	sim:Advance(0.2)
	t.eq(sim:Globals().spawns, 1)
	sim:KillCharacter(p)
	sim:Advance(0.5)
	t.eq(sim:Globals().spawns, 1)
	sim:Advance(1)
	t.eq(sim:Globals().spawns, 2)
	sim:AssertNoErrors()
end

tests["StarterGui copies respect ResetOnSpawn and run their LocalScripts"] = function(t)
	local sim = t.sim()
	local sg = sim:Find("StarterGui")
	local reset = sim:Create("ScreenGui", { Name = "Reset", ResetOnSpawn = true }, sg)
	local keep = sim:Create("ScreenGui", { Name = "Keep", ResetOnSpawn = false }, sg)
	sim:AddScript(reset, "LocalScript", "Count", "_G.resetRuns = (_G.resetRuns or 0) + 1")
	sim:AddScript(keep, "LocalScript", "Count", "_G.keepRuns = (_G.keepRuns or 0) + 1")
	sim:StartServer()
	local p = sim:AddPlayer()
	sim:Advance(0.2)
	local pg = p:WaitForChild("PlayerGui")
	local firstReset, firstKeep = pg.Reset, pg.Keep
	t.eq(sim:Globals(p).resetRuns, 1)
	t.eq(sim:Globals(p).keepRuns, 1)
	sim:LoadCharacter(p)
	sim:Advance(0.1)
	t.ok(pg.Reset ~= firstReset, "ResetOnSpawn gui is re-cloned")
	t.eq(firstReset.Parent, nil)
	t.ok(pg.Keep == firstKeep, "ResetOnSpawn=false gui persists")
	t.eq(sim:Globals(p).resetRuns, 2)
	t.eq(sim:Globals(p).keepRuns, 1)
	t.ok(sim.game.StarterGui.Reset.Count:IsA("LocalScript"), "templates stay in StarterGui")
	sim:AssertNoErrors()
end

tests["StarterPlayerScripts and StarterGui are fully copied before LocalScripts start"] = function(t)
	local sim = t.sim()
	local sps = sim:Find("StarterPlayer.StarterPlayerScripts")
	-- the LocalScript is added before the folder it requires without WaitForChild
	sim:AddScript(sps, "LocalScript", "Main", "_G.fish = require(script.Parent.Controllers.Fish).name")
	local folder = sim:Create("Folder", { Name = "Controllers" }, sps)
	sim:AddScript(folder, "ModuleScript", "Fish", "return { name = 'carp' }")
	local sg = sim:Find("StarterGui")
	local a = sim:Create("ScreenGui", { Name = "A" }, sg)
	sim:AddScript(a, "LocalScript", "UsesB", "_G.sawB = script.Parent.Parent:FindFirstChild('B') ~= nil")
	sim:Create("ScreenGui", { Name = "B" }, sg)
	sim:StartServer()
	local p = sim:AddPlayer()
	sim:Advance(0.2)
	t.eq(sim:Globals(p).fish, "carp")
	t.eq(sim:Globals(p).sawB, true)
	sim:AssertNoErrors()
end

tests["GUI clicks reach the client, visibility is enforced, phone layout sizes"] = function(t)
	local sim = t.sim()
	local rs = sim:Find("ReplicatedStorage")
	sim:Create("RemoteEvent", { Name = "Buy" }, rs)
	local gui = sim:Create("ScreenGui", { Name = "Shop" }, sim:Find("StarterGui"))
	local frame = sim:Create("Frame", {
		Name = "Panel",
		Size = roblox.UDim2.fromScale(0.5, 0.5),
		Position = roblox.UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
	}, gui)
	sim:Create("TextButton", { Name = "BuyRod", Size = roblox.UDim2.new(1, 0, 0.4, 0), Text = "Buy" }, frame)
	sim:Create("TextButton", { Name = "Hidden", Visible = false, Size = roblox.UDim2.fromOffset(100, 50) }, frame)
	sim:AddScript(
		frame,
		"LocalScript",
		"Ui",
		[[
		local frame = script.Parent
		frame.BuyRod.Activated:Connect(function(input, clicks)
			_G.inputType = input.UserInputType
			_G.clicks = clicks
			game.ReplicatedStorage.Buy:FireServer("Rod")
		end)
		frame.BuyRod.MouseButton1Click:Connect(function() _G.m1 = true end)
	]]
	)
	sim:AddScript(
		sim:Find("ServerScriptService"),
		"Script",
		"Shop",
		[[
		game.ReplicatedStorage.Buy.OnServerEvent:Connect(function(player, item)
			_G.bought = player.Name .. ":" .. item
		end)
	]]
	)
	sim:StartServer()
	local p = sim:AddPlayer({ Name = "Mobile", device = "phone" })
	sim:Advance(0.2)
	local button = sim:Gui(p, "Shop.Panel.BuyRod")
	t.ok(button ~= nil)
	sim:Click(p, button)
	sim:Advance(0.05)
	t.eq(sim:Globals().bought, "Mobile:Rod")
	t.eq(sim:Globals(p).inputType, Enum.UserInputType.Touch, "phones activate with touch input")
	t.eq(sim:Globals(p).clicks, 1)
	t.eq(sim:Globals(p).m1, true)
	-- phone viewport 844x390 minus the 58px top bar inset
	local panel = sim:Gui(p, "Shop.Panel")
	t.near(panel.AbsoluteSize, Vector2.new(422, 166), 1e-3)
	t.near(panel.AbsolutePosition, Vector2.new(211, 58 + 83), 1e-3)
	t.near(button.AbsoluteSize, Vector2.new(422, 66.4), 1e-3)
	t.throws(function()
		sim:Click(p, sim:Gui(p, "Shop.Panel.Hidden"))
	end, "not Visible")
	panel.Visible = false
	local ok, why = sim:CanClick(p, button)
	t.eq(ok, false)
	t.match(why, "Panel is not Visible")
	-- server-side connections to a player's GUI never fire (wrong context)
	sim:AddScript(
		sim:Find("ServerScriptService"),
		"Script",
		"Wrong",
		[[
		local p = game.Players:GetPlayers()[1]
		p.PlayerGui.Shop.Panel.BuyRod.Activated:Connect(function() _G.serverSawClick = true end)
	]]
	)
	panel.Visible = true
	sim:Click(p, button)
	sim:Advance(0.05)
	t.eq(sim:Globals().serverSawClick, nil)
	sim:AssertNoErrors()
end

tests["UserInputService, ContextActionService and device profiles"] = function(t)
	local sim = build(t, {
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Input",
			[[
			local UIS = game:GetService("UserInputService")
			local CAS = game:GetService("ContextActionService")
			_G.touch = UIS.TouchEnabled
			_G.keyboard = UIS.KeyboardEnabled
			_G.began = {}
			UIS.InputBegan:Connect(function(input, gp)
				table.insert(_G.began, input.KeyCode.Name .. ":" .. tostring(gp))
			end)
			UIS.TouchTap:Connect(function(positions) _G.tapped = #positions end)
			CAS:BindAction("Cast", function(name, state, input)
				if state == Enum.UserInputState.Begin then
					_G.cast = (_G.cast or 0) + 1
				end
				return Enum.ContextActionResult.Sink
			end, true, Enum.KeyCode.F)
		]],
		},
	})
	sim:StartServer()
	local pc = sim:AddPlayer({ Name = "PC" })
	local phone = sim:AddPlayer({ Name = "Phone", device = "phone" })
	sim:Advance(0.2)
	t.eq(sim:Globals(pc).keyboard, true)
	t.eq(sim:Globals(pc).touch, false)
	t.eq(sim:Globals(phone).touch, true)
	sim:PressKey(pc, Enum.KeyCode.E)
	sim:PressKey(pc, Enum.KeyCode.F)
	t.eq(sim:Globals(pc).began, { "E:false", "F:true" }, "CAS-bound key is game-processed")
	t.eq(sim:Globals(pc).cast, 1)
	t.eq(sim:Globals(phone).began, {}, "input only reaches its own client")
	sim:TriggerAction(phone, "Cast", Enum.UserInputState.Begin)
	t.eq(sim:Globals(phone).cast, 1)
	sim:Tap(phone, Vector2.new(10, 10))
	t.eq(sim:Globals(phone).tapped, 1)
	sim:AssertNoErrors()
end

tests["ProximityPrompt holds: trigger, range, death, disable, HoldDuration"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"Steal",
			[[
			local prompt = workspace:WaitForChild("Tank"):WaitForChild("StealPrompt")
			_G.log = {}
			local function log(s) table.insert(_G.log, s) end
			prompt.PromptButtonHoldBegan:Connect(function(p) log("began:" .. p.Name) end)
			prompt.PromptButtonHoldEnded:Connect(function(p) log("ended:" .. p.Name) end)
			prompt.Triggered:Connect(function(p) log("triggered:" .. p.Name) end)
			game:GetService("ProximityPromptService").PromptTriggered:Connect(function(pr, p)
				_G.serviceSaw = pr.Name .. ":" .. p.Name
			end)
		]],
		},
	})
	local tank = sim:Create("Part", { Name = "Tank", Anchored = true, CFrame = CFrame.new(0, 2, 0) }, sim.workspace)
	local prompt =
		sim:Create("ProximityPrompt", { Name = "StealPrompt", HoldDuration = 3, MaxActivationDistance = 10 }, tank)
	sim:StartServer()
	local thief = sim:AddPlayer({ Name = "Thief" })
	sim:Advance(0.2)
	local g = sim:Globals()

	sim:Teleport(thief, Vector3.new(30, 3, 0))
	local ok, why = sim:HoldPrompt(thief, prompt, 3.1)
	t.eq(ok, false)
	t.match(why, "out of range")
	t.eq(#g.log, 0)

	sim:Teleport(thief, Vector3.new(5, 3, 0))
	ok = sim:HoldPrompt(thief, prompt, 3.1)
	sim:Advance(0.05)
	t.eq(ok, true)
	t.eq(g.log, { "began:Thief", "triggered:Thief", "ended:Thief" })
	t.eq(g.serviceSaw, "StealPrompt:Thief")

	-- too short
	table.clear(g.log)
	ok = sim:HoldPrompt(thief, prompt, 2)
	sim:Advance(0.05)
	t.eq(ok, false)
	t.eq(g.log, { "began:Thief", "ended:Thief" })

	-- walking out of range mid-hold cancels
	table.clear(g.log)
	local hold = sim:BeginHold(thief, prompt)
	sim:Advance(1)
	sim:Teleport(thief, Vector3.new(40, 3, 0))
	sim:Advance(3)
	t.eq(hold.triggered, false)
	t.match(hold.cancelReason, "out of range")
	t.eq(g.log, { "began:Thief", "ended:Thief" })

	-- dying mid-hold cancels
	sim:Teleport(thief, Vector3.new(2, 3, 0))
	hold = sim:BeginHold(thief, prompt)
	sim:Advance(1)
	sim:KillCharacter(thief)
	sim:Advance(3)
	t.eq(hold.triggered, false)
	t.eq(hold.cancelReason, "character dead")

	-- server raising HoldDuration mid-hold (lock upgrade) delays the trigger
	sim:Advance(6) -- respawn
	sim:Teleport(thief, Vector3.new(2, 3, 0))
	hold = sim:BeginHold(thief, prompt)
	sim:Advance(1)
	prompt.HoldDuration = 5
	sim:Advance(3)
	t.eq(hold.triggered, false)
	sim:Advance(1.1)
	t.eq(hold.triggered, true)
	sim:ReleasePrompt(thief, prompt)

	-- disabled prompt
	prompt.Enabled = false
	ok, why = sim:HoldPrompt(thief, prompt)
	t.eq(ok, false)
	t.eq(why, "prompt disabled")
	sim:AssertNoErrors()
end

tests["tools from StarterPack: equip, activate on server and client"] = function(t)
	local sim = t.sim()
	local tool = sim:Create("Tool", { Name = "Rod", RequiresHandle = false }, sim:Find("StarterPack"))
	sim:AddScript(
		tool,
		"Script",
		"Server",
		[[
		local tool = script.Parent
		tool.Equipped:Connect(function() _G.equipped = (_G.equipped or 0) + 1 end)
		tool.Activated:Connect(function()
			local player = game.Players:GetPlayerFromCharacter(tool.Parent)
			_G.casts = (_G.casts or 0) + 1
			_G.caster = player and player.Name
		end)
		tool.Unequipped:Connect(function() _G.unequipped = true end)
	]]
	)
	sim:AddScript(
		tool,
		"LocalScript",
		"Client",
		[[
		script.Parent.Activated:Connect(function() _G.clientCasts = (_G.clientCasts or 0) + 1 end)
	]]
	)
	sim:StartServer()
	local p = sim:AddPlayer({ Name = "Fisher" })
	sim:Advance(0.2)
	t.ok(p.Backpack:FindFirstChild("Rod") ~= nil, "StarterPack copied to Backpack")
	sim:EquipTool(p, "Rod")
	sim:Advance(0.05)
	t.ok(sim:GetCharacter(p):FindFirstChild("Rod") ~= nil)
	t.eq(sim:Globals().equipped, 1)
	sim:ActivateTool(p)
	sim:Advance(0.05)
	t.eq(sim:Globals().casts, 1)
	t.eq(sim:Globals().caster, "Fisher")
	t.eq(sim:Globals(p).clientCasts, 1)
	sim:UnequipTools(p)
	sim:Advance(0.05)
	t.eq(sim:Globals().unequipped, true)
	t.ok(p.Backpack:FindFirstChild("Rod") ~= nil)
	sim:AssertNoErrors()
end

tests["Humanoid MoveTo walks at WalkSpeed; Teleport moves the whole character"] = function(t)
	local sim = t.sim()
	sim:StartServer()
	local p = sim:AddPlayer()
	sim:Advance(0.1)
	sim:Teleport(p, Vector3.new(0, 3, 0))
	local char = sim:GetCharacter(p)
	t.near(char.Head.Position, Vector3.new(0, 4.5, 0), 1e-4, "head follows the root")
	local hum = sim:GetHumanoid(p)
	hum.WalkSpeed = 10
	local start = sim:Time()
	t.eq(sim:WalkTo(p, Vector3.new(20, 0, 0)), true)
	t.near(sim:Time() - start, 2, 0.05, "20 studs at WalkSpeed 10 takes 2s")
	t.near(char.HumanoidRootPart.Position, Vector3.new(20, 3, 0), 1e-3)
	hum.WalkSpeed = 2
	t.eq(sim:WalkTo(p, Vector3.new(100, 0, 0), 20), false, "MoveTo gives up after 8 seconds")
	sim:AssertNoErrors()
end

tests["rigs: R15/R6 limbs, Animator stand-in, per-client joint poses, RightGrip"] = function(t)
	local sim = t.sim()
	sim:AddScript(
		sim:Find("StarterPlayer.StarterPlayerScripts"),
		"LocalScript",
		"Poser",
		[[
		-- the client poses the joint named _G.joint of Fisher's character in PreSimulation
		local RunService = game:GetService("RunService")
		_G.preAnimation = 0
		RunService.PreAnimation:Connect(function() _G.preAnimation += 1 end)
		RunService.PreSimulation:Connect(function()
			local fisher = game.Players:FindFirstChild("Fisher")
			local char = fisher and fisher.Character
			local joint = _G.pose and char and char:FindFirstChild(_G.joint, true)
			if joint then
				_G.seen = joint.Transform
				joint.Transform = _G.pose
			end
		end)
	]]
	)
	sim:StartServer()
	local fisher = sim:AddPlayer({ Name = "Fisher", rig = "R15" })
	local watcher = sim:AddPlayer({ Name = "Watcher" })
	local r6 = sim:AddPlayer({ Name = "Old", rig = "R6" })
	local ac = sim:AddPlayer({ Name = "Aju", rig = "R15", joints = "AnimationConstraint" })
	t.throws(function()
		sim:AddPlayer({ rig = "R7" })
	end, "rig must be")
	sim:Advance(0.2)
	t.ok(sim:Globals(watcher).preAnimation > 0, "PreAnimation fires every frame")
	local char = sim:GetCharacter(fisher)
	t.eq(sim:GetHumanoid(fisher).RigType, Enum.HumanoidRigType.R15)
	sim:Teleport(fisher, CFrame.new(0, 3, 0))
	sim:Step()
	local hrp = char.HumanoidRootPart.Position
	t.near(char.Head.Position, hrp + Vector3.new(0, 1.6, 0), 1e-3, "R15 head on the neck")
	t.near(char.RightHand.Position.Y, hrp.Y - 1.1, 1e-3, "arm hangs at rest (identity Transforms)")
	t.ok(char.RightUpperArm:FindFirstChild("RightShoulder"):IsA("Motor6D"))
	t.near(
		sim:GetCharacter(watcher).Head.Position - sim:GetRoot(watcher).Position,
		Vector3.new(0, 1.5, 0),
		1e-4,
		"players without the option keep the minimal body"
	)

	-- equipped Tool: RightGrip weld from the hand's grip attachment to the Handle
	local tool = sim:Create("Tool", { Name = "Rod", Grip = CFrame.new(0, 0, -1) }, fisher.Backpack)
	sim:Create("Part", { Name = "Handle", Size = Vector3.new(1, 1, 4) }, tool)
	sim:EquipTool(fisher, tool)
	sim:Step()
	local grip = char.RightHand:FindFirstChild("RightGrip")
	t.ok(grip and grip:IsA("Weld") and grip.Part1 == tool.Handle, "RightGrip welds the Handle to the hand")
	t.near(
		tool.Handle.CFrame.Position,
		(char.RightHand.CFrame * char.RightHand.RightGripAttachment.CFrame * tool.Grip:Inverse()).Position,
		1e-3,
		"the Handle follows the hand"
	)

	-- the Animator stand-in: the pose set for the player, every frame, unless throttled
	local raised = CFrame.Angles(math.rad(90), 0, 0)
	sim:SetAnimatorPose(fisher, { RightShoulder = raised })
	sim:Step()
	t.near(char.RightUpperArm:FindFirstChild("RightShoulder").Transform, raised, 1e-6, "animator pose")
	t.ok(char.RightHand.Position.Y > hrp.Y, "arm raised by the animator pose")

	-- a client's own Transform write is applied for that client only
	local g = sim:Globals(watcher)
	g.joint, g.pose = "RightShoulder", CFrame.Angles(math.rad(-90), 0, 0)
	sim:Step()
	t.near(g.seen, raised, 1e-6, "PreSimulation sees the fresh animator pose")
	local serverHand = char.RightHand.Position
	local watcherHand = sim:Run(function()
		return char.RightHand.Position
	end, watcher)
	t.ok(serverHand.Y > hrp.Y, "the server still sees the animator pose")
	t.ok(watcherHand.Y < hrp.Y + 1 and (watcherHand - serverHand).Magnitude > 1, "the posing client sees its own pose")
	local watcherGrip = sim:Run(function()
		return char.RightHand.RightGripAttachment.WorldPosition
	end, watcher)
	t.ok((watcherGrip - watcherHand).Magnitude < 0.5, "attachments follow the client's parts")
	t.near(char.RightUpperArm:FindFirstChild("RightShoulder").Transform, raised, 1e-6, "Transform stays client-local")

	-- throttled frames: the Animator does not write, EvaluationThrottled is true
	g.pose = nil
	sim:ThrottleAnimator(fisher, 1)
	sim:Step()
	t.eq(char.Humanoid.Animator.EvaluationThrottled, true)
	sim:ThrottleAnimator(fisher, nil)
	sim:Step()
	t.eq(char.Humanoid.Animator.EvaluationThrottled, false)
	t.near(
		sim:Run(function()
			return char.RightHand.Position
		end, watcher),
		serverHand,
		1e-3,
		"client view back to the replicated pose"
	)

	-- R6 and AnimationConstraint rigs
	local old = sim:GetCharacter(r6)
	t.eq(sim:GetHumanoid(r6).RigType, Enum.HumanoidRigType.R6)
	t.near(old.Head.Position - sim:GetRoot(r6).Position, Vector3.new(0, 1.5, 0), 1e-3, "R6 head")
	t.near(old["Right Arm"].Position - sim:GetRoot(r6).Position, Vector3.new(1.5, 0, 0), 1e-3, "R6 arm")
	local aju = sim:GetCharacter(ac)
	local shoulder = aju.RightUpperArm:FindFirstChild("RightShoulder")
	t.ok(shoulder:IsA("AnimationConstraint"), "AnimationConstraint joints")
	t.ok(shoulder.Attachment0.Name == "RightShoulderRigAttachment", "rig attachments")
	t.near(aju.Head.Position - sim:GetRoot(ac).Position, Vector3.new(0, 1.6, 0), 1e-3, "solved through attachments")
	sim:AssertNoErrors()
end

tests["Kick and RemovePlayer stop the client and fire PlayerRemoving"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"Kicker",
			[[
			_G.left = {}
			game.Players.PlayerRemoving:Connect(function(p)
				table.insert(_G.left, p.Name .. ":" .. tostring(p.Parent ~= nil))
			end)
			game.Players.PlayerAdded:Connect(function(p)
				if p.Name == "Cheater" then
					task.wait(0.5)
					p:Kick("bye")
				end
			end)
		]],
		},
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Tick",
			[[
			while true do
				_G.ticks = (_G.ticks or 0) + 1
				task.wait(0.1)
			end
		]],
		},
	})
	sim:StartServer()
	local cheater = sim:AddPlayer({ Name = "Cheater" })
	local good = sim:AddPlayer({ Name = "Good" })
	sim:Advance(1)
	t.eq(sim.Kicks[1].message, "bye")
	t.eq(#sim:GetPlayers(), 1)
	t.ok(sim:GetPlayers()[1] == good)
	local ticks = sim:Globals(cheater).ticks
	sim:Advance(1)
	t.eq(sim:Globals(cheater).ticks, ticks, "kicked client's threads stopped")
	t.ok(sim:Globals(good).ticks > ticks)
	sim:RemovePlayer(good)
	sim:Advance(0.1)
	t.eq(sim:Globals().left, { "Cheater:true", "Good:true" }, "player still parented during PlayerRemoving")
	t.eq(good.Parent, nil)
	t.eq(sim:CountConnections("client"), 0)
	sim:AssertNoErrors()
end

return tests
