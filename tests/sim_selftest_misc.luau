-- sim_selftest_misc.luau: remaining RbxSim features: render binds, RunContext,
-- ReplicatedFirst, script enable/disable, TextBox, legacy GUI tweens, layouts,
-- bindables, coroutine.wrap, Enum aliases, mocks and typeof.

local roblox = require("@lune/roblox")

local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local UDim2 = roblox.UDim2
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

tests["RenderStepped / BindToRenderStep run per client frame; server cannot use them"] = function(t)
	local sim = build(t, {
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"Render",
			[[
			local RS = game:GetService("RunService")
			_G.order = {}
			RS:BindToRenderStep("Late", 300, function() if #_G.order < 2 then table.insert(_G.order, "late") end end)
			RS:BindToRenderStep("Early", 100, function(dt) _G.dt = dt if #_G.order < 2 then table.insert(_G.order, "early") end end)
			_G.frames = 0
			local c = RS.RenderStepped:Connect(function() _G.frames += 1 end)
			task.wait(0.5)
			c:Disconnect()
			RS:UnbindFromRenderStep("Early")
		]],
		},
		{
			"ServerScriptService",
			"Script",
			"S",
			[[
			_G.renderErr = select(2, pcall(function() game:GetService("RunService").RenderStepped:Connect(function() end) end))
			_G.bindErr = select(2, pcall(function() game:GetService("RunService"):BindToRenderStep("x", 1, function() end) end))
		]],
		},
	})
	sim:StartServer()
	local p = sim:AddPlayer()
	sim:Advance(1)
	local g = sim:Globals(p)
	t.eq(g.order, { "early", "late" }, "lower priority value runs first")
	t.near(g.dt, 1 / 60, 1e-9)
	t.ok(g.frames >= 29 and g.frames <= 31, "about 30 frames in 0.5s, got " .. g.frames)
	t.match(sim:Globals().renderErr, "can only be used from local scripts")
	t.match(sim:Globals().bindErr, "only be called from the client")
	sim:AssertNoErrors()
end

tests["RunContext Client scripts, ReplicatedFirst and Script.Enabled toggling"] = function(t)
	local sim = build(t, {
		{ "ReplicatedFirst", "LocalScript", "Loading", "_G.loadingRan = game.Players.LocalPlayer.Name" },
		{
			"ReplicatedStorage",
			"Script",
			"ClientRC",
			"_G.clientRC = game:GetService('RunService'):IsClient()",
			{ RunContext = Enum.RunContext.Client },
		},
		{
			"ReplicatedStorage",
			"Script",
			"ServerRC",
			"_G.serverRC = game:GetService('RunService'):IsServer()",
			{ RunContext = Enum.RunContext.Server },
		},
		{ "ServerStorage", "Script", "NotRun", "_G.serverStorageRan = true" },
		{ "ReplicatedStorage", "Script", "LegacyInRS", "_G.legacyInRS = true" },
		{
			"ServerScriptService",
			"Script",
			"Toggle",
			[[
			_G.starts = (_G.starts or 0) + 1
			while true do
				_G.toggleTicks = (_G.toggleTicks or 0) + 1
				task.wait(0.1)
			end
		]],
		},
	})
	sim:StartServer()
	local p = sim:AddPlayer({ Name = "Q" })
	sim:Advance(0.3)
	local server, client = sim:Globals(), sim:Globals(p)
	t.eq(client.loadingRan, "Q")
	t.eq(client.clientRC, true)
	t.eq(server.serverRC, true)
	t.eq(server.serverStorageRan, nil, "scripts in ServerStorage do not run")
	t.eq(server.legacyInRS, nil, "legacy Scripts in ReplicatedStorage do not run")
	local script = sim:Find("ServerScriptService.Toggle")
	script.Enabled = false
	local ticks = server.toggleTicks
	sim:Advance(0.5)
	t.eq(server.toggleTicks, ticks, "disabled script stopped")
	t.eq(script.Disabled, true)
	script.Enabled = true
	sim:Advance(0.25)
	t.eq(server.starts, 2, "re-enabled script runs again from the top")
	t.ok(server.toggleTicks > ticks)
	-- a server Script cloned into Workspace at runtime starts running
	local template = sim:Create("Folder", { Name = "Template" }, sim:Find("ServerStorage"))
	sim:AddScript(template, "Script", "PerBase", "_G.perBase = (_G.perBase or 0) + 1")
	template:Clone().Parent = sim.workspace
	template:Clone().Parent = sim.workspace
	sim:Flush()
	t.eq(server.perBase, 2)
	sim:AssertNoErrors()
end

tests["TextBox typing, legacy TweenSize callback, list/grid layouts, viewport"] = function(t)
	local sim = t.sim()
	local gui = sim:Create("ScreenGui", { Name = "Main", IgnoreGuiInset = true }, sim:Find("StarterGui"))
	local list = sim:Create("Frame", { Name = "List", Size = UDim2.fromOffset(200, 400) }, gui)
	sim:Create("UIListLayout", { Padding = roblox.UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	sim:Create("TextButton", { Name = "B", LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 50) }, list)
	sim:Create("TextButton", { Name = "A", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 50) }, list)
	local grid = sim:Create(
		"Frame",
		{ Name = "Grid", Position = UDim2.fromOffset(300, 0), Size = UDim2.fromOffset(220, 300) },
		gui
	)
	sim:Create("UIGridLayout", { CellSize = UDim2.fromOffset(100, 100), CellPadding = UDim2.fromOffset(10, 10) }, grid)
	for i = 1, 3 do
		sim:Create("ImageButton", { Name = "Cell" .. i, LayoutOrder = i }, grid)
	end
	sim:Create(
		"TextBox",
		{ Name = "Input", Size = UDim2.fromOffset(100, 30), Position = UDim2.fromOffset(600, 0) },
		gui
	)
	sim:Create("Frame", { Name = "Bar", Size = UDim2.fromScale(0, 1) }, gui)
	sim:AddScript(
		gui,
		"LocalScript",
		"Ui",
		[[
		local gui = script.Parent
		gui.Input.FocusLost:Connect(function(enter) _G.typed = gui.Input.Text; _G.enter = enter end)
		gui.Bar:TweenSize(UDim2.fromScale(1, 1), Enum.EasingDirection.Out, Enum.EasingStyle.Linear, 1, false, function(status)
			_G.tweenStatus = status
		end)
		_G.viewport = workspace.CurrentCamera.ViewportSize
		_G.mouse = typeof(game.Players.LocalPlayer:GetMouse())
	]]
	)
	sim:StartServer()
	local p = sim:AddPlayer({ device = "tablet" })
	sim:Advance(0.2)
	local a, b = sim:Gui(p, "Main.List.A"), sim:Gui(p, "Main.List.B")
	t.near(a.AbsolutePosition, Vector2.new(0, 0), 1e-6)
	t.near(b.AbsolutePosition, Vector2.new(0, 60), 1e-6, "list layout stacks by LayoutOrder with padding")
	t.near(sim:Gui(p, "Main.Grid.Cell2").AbsolutePosition, Vector2.new(410, 0), 1e-6)
	t.near(sim:Gui(p, "Main.Grid.Cell3").AbsolutePosition, Vector2.new(300, 110), 1e-6, "grid wraps")
	t.near(sim:Gui(p, "Main.List.UIListLayout").AbsoluteContentSize, Vector2.new(200, 110), 1e-6)
	sim:TypeText(p, sim:Gui(p, "Main.Input"), "hello", true)
	t.eq(sim:Globals(p).typed, "hello")
	t.eq(sim:Globals(p).enter, true)
	sim:Advance(1)
	t.eq(sim:Globals(p).tweenStatus, Enum.TweenStatus.Completed)
	t.eq(sim:Gui(p, "Main.Bar").Size, UDim2.fromScale(1, 1))
	t.eq(sim:Globals(p).viewport, Vector2.new(1024, 768))
	t.eq(sim:Globals(p).mouse, "Instance")
	sim:AssertNoErrors()
end

tests["bindables stay in their context; coroutine.wrap and task.wait interplay"] = function(t)
	local sim = build(t, {
		{ "ReplicatedStorage", "BindableEvent", "Bus" },
		{ "ReplicatedStorage", "BindableFunction", "Ask" },
		{
			"ServerScriptService",
			"Script",
			"S",
			[[
			local bus = game.ReplicatedStorage.Bus
			_G.serverGot = {}
			bus.Event:Connect(function(v) table.insert(_G.serverGot, v) end)
			game.ReplicatedStorage.Ask.OnInvoke = function(x) task.wait(0.1) return x * 2, typeof(x) end
			local payload = { n = 1 }
			bus:Fire(payload)
			_G.answer, _G.kind = game.ReplicatedStorage.Ask:Invoke(21)
			local co = coroutine.wrap(function(a)
				local e = task.wait(0.5)
				_G.wrapped = { a, e > 0 }
			end)
			co("x")
			_G.afterWrap = true
		]],
		},
		{
			"StarterPlayer.StarterPlayerScripts",
			"LocalScript",
			"C",
			[[
			game.ReplicatedStorage.Bus.Event:Connect(function(v) _G.clientGot = v end)
			game.ReplicatedStorage.Bus:Fire("from client")
		]],
		},
	})
	sim:StartServer()
	local p = sim:AddPlayer()
	sim:Advance(1)
	local g = sim:Globals()
	t.eq(#g.serverGot, 1, "client Fire does not reach server listeners")
	t.eq(g.serverGot[1], { n = 1 })
	t.eq(g.answer, 42)
	t.eq(g.kind, "number")
	t.eq(g.afterWrap, true)
	t.eq(g.wrapped, { "x", true })
	t.eq(sim:Globals(p).clientGot, "from client")
	sim:AssertNoErrors()
end

tests["sim:Require, sim:Run, Enum aliases, mock datatypes and typeof"] = function(t)
	local sim = build(t, {
		{
			"ReplicatedStorage",
			"ModuleScript",
			"Config",
			"return { Price = 100, Side = game:GetService('RunService'):IsServer() and 's' or 'c' }",
		},
	})
	sim:StartServer()
	local p = sim:AddPlayer()
	sim:Advance(0.1)
	local server = sim:Require(sim:Find("ReplicatedStorage.Config"))
	local client = sim:Require(sim:Find("ReplicatedStorage.Config"), p)
	t.eq(server.Price, 100)
	t.eq(server.Side, "s")
	t.eq(client.Side, "c")
	t.ok(server ~= client)
	local env = sim:Env()
	t.ok(env.Enum.KeyCode.Unknown == Enum.KeyCode.None, "KeyCode.Unknown aliases Lune's value-0 item")
	t.eq(env.Enum.KeyCode:FromName("E"), Enum.KeyCode.E)
	t.eq(sim:Typeof(env.TweenInfo.new(1)), "TweenInfo")
	t.eq(sim:Typeof(env.RaycastParams.new()), "RaycastParams")
	t.eq(sim:Typeof(env.DateTime.now()), "DateTime")
	t.eq(sim:Typeof(sim.workspace), "Instance")
	t.eq(sim:Typeof(sim.workspace.ChildAdded), "RBXScriptSignal")
	t.eq(sim:Typeof(env.Enum), "Enums")
	t.eq(sim:Typeof(Vector3.one), "Vector3")
	t.throws(function()
		env.Instance.new("NotAClass")
	end, "Unable to create an Instance")
	-- harness functions keep Lune's globals; use the context env for task/etc.
	local start = sim:Time()
	local r1, r2 = sim:Run(function()
		env.task.wait(1)
		return nil, 7
	end)
	t.eq(r1, nil)
	t.eq(r2, 7)
	t.near(sim:Time() - start, 1, 1 / 30, "sim:Run advances time while the function yields")
	t.throws(function()
		sim:Run(function()
			error("inside run")
		end)
	end, "inside run")
	t.throws(function()
		sim.workspace:WaitForChild("Nope")
	end, "harness thread")
	t.throws(function()
		local _ = sim.workspace.NotAChild
	end, 'NotAChild is not a valid member of Workspace "Workspace"')
	sim:AssertNoErrors()
end

tests["instantMoveTo option and AnimationTrack timing"] = function(t)
	local sim = t.sim({ instantMoveTo = true })
	sim:StartServer()
	local p = sim:AddPlayer()
	sim:Advance(0.1)
	local hum = sim:GetHumanoid(p)
	hum:MoveTo(Vector3.new(30, 0, 30))
	local pos = sim:GetRoot(p).Position
	t.near(Vector2.new(pos.X, pos.Z), Vector2.new(30, 30), 1e-4)
	local anim = sim:Create("Animation", { AnimationId = "rbxassetid://1" })
	anim:SetAttribute("SimLength", 2)
	local track = hum:LoadAnimation(anim)
	track:Play()
	t.eq(track.IsPlaying, true)
	sim:Advance(1)
	t.eq(track.IsPlaying, true)
	sim:Advance(1.1)
	t.eq(track.IsPlaying, false)
	sim:AssertNoErrors()
end

tests["API smoke: rarely used members run without errors"] = function(t)
	local sim = build(t, {
		{
			"ServerScriptService",
			"Script",
			"Smoke",
			[[
			local results = {}
			local function check(name, fn)
				local ok, err = pcall(fn)
				if not ok then table.insert(results, name .. ": " .. tostring(err)) end
			end
			local model = Instance.new("Model")
			local a = Instance.new("Part", model)
			a.Size = Vector3.new(2, 2, 2)
			local b = Instance.new("Part", model)
			b.CFrame = CFrame.new(4, 0, 0)
			model.Parent = workspace
			check("ScaleTo", function() model:ScaleTo(2); assert(model:GetScale() == 2); assert(a.Size == Vector3.new(4, 4, 4)) end)
			check("WorldPivot", function() model.WorldPivot = CFrame.new(1, 2, 3); assert(model:GetPivot().Position == Vector3.new(1, 2, 3)) end)
			check("TranslateBy", function() model:TranslateBy(Vector3.new(0, 10, 0)) end)
			check("MoveTo", function() model:MoveTo(Vector3.new(0, 0, 0)) end)
			check("Orientation", function() a.Orientation = Vector3.new(0, 90, 0); assert(math.abs(a.Orientation.Y - 90) < 1e-3) end)
			check("Rotation", function() a.Rotation = Vector3.new(0, 45, 0) end)
			check("BrickColor", function() a.BrickColor = BrickColor.new("Bright red"); assert(a.BrickColor.Name == "Bright red") end)
			check("Mass", function() assert(a:GetMass() > 0 and a.AssemblyMass > 0) end)
			check("Velocity", function() a.AssemblyLinearVelocity = Vector3.new(1, 0, 0); assert(a.AssemblyLinearVelocity.X == 1) end)
			check("misc part", function() a:ApplyImpulse(Vector3.one); a:SetNetworkOwner(nil); assert(#a:GetTouchingParts() == 0) end)
			check("FindPartOnRay", function() local hit = workspace:FindPartOnRay(Ray.new(Vector3.new(0, 50, 0), Vector3.new(0, -100, 0))) end)
			check("Region3", function() workspace:FindPartsInRegion3(Region3.new(Vector3.new(-5, -5, -5), Vector3.new(5, 5, 5)), nil, 10) end)
			check("Spherecast", function() workspace:Spherecast(Vector3.new(0, 50, 0), 2, Vector3.new(0, -100, 0)) end)
			check("OverlapParams", function() local p = OverlapParams.new(); p:AddToFilter(a); workspace:GetPartsInPart(b, p) end)
			check("Camera", function()
				local cam = workspace.CurrentCamera
				local _ = cam.ViewportSize
				local v, on = cam:WorldToViewportPoint(Vector3.new(0, 0, -10))
				local r = cam:ScreenPointToRay(10, 10)
				assert(typeof(r) == "Ray")
			end)
			check("Terrain", function() workspace.Terrain:FillBall(Vector3.zero, 4, Enum.Material.Grass); workspace.Terrain:Clear() end)
			check("Http", function()
				local H = game:GetService("HttpService")
				assert(H:UrlEncode("a b") == "a%20b")
				assert(not pcall(function() H:GetAsync("http://x") end))
			end)
			check("Marketplace", function()
				local M = game:GetService("MarketplaceService")
				assert(M:UserOwnsGamePassAsync(1, 1) == false)
				M.ProcessReceipt = function() return Enum.ProductPurchaseDecision.PurchaseGranted end
			end)
			check("Physics", function() game:GetService("PhysicsService"):RegisterCollisionGroup("Fish") end)
			check("Path", function()
				local path = game:GetService("PathfindingService"):CreatePath()
				path:ComputeAsync(Vector3.zero, Vector3.new(10, 0, 0))
				assert(#path:GetWaypoints() == 2 and path.Status == Enum.PathStatus.Success)
			end)
			check("TextService", function()
				assert(game:GetService("TextService"):GetTextSize("abc", 20, Enum.Font.Gotham, Vector2.new(100, 100)).X > 0)
				local f = game:GetService("TextService"):FilterStringAsync("hi", 1)
				assert(f:GetNonChatStringForBroadcastAsync() == "hi")
			end)
			check("Teams", function()
				local team = Instance.new("Team", game:GetService("Teams"))
				assert(#team:GetPlayers() == 0)
			end)
			check("StarterGui", function() game:GetService("StarterGui"):SetCore("SendNotification", { Title = "x" }) end)
			check("Gui inset", function() local a1, b1 = game:GetService("GuiService"):GetGuiInset() assert(a1.Y == 58) end)
			check("Attachment", function()
				local att = Instance.new("Attachment", a)
				att.WorldPosition = Vector3.new(1, 1, 1)
				assert((att.WorldPosition - Vector3.new(1, 1, 1)).Magnitude < 1e-3)
				att.Orientation = Vector3.new(0, 30, 0)
			end)
			check("ObjectValue", function()
				local ov = Instance.new("ObjectValue", workspace)
				local got
				ov.Changed:Connect(function(v) got = v end)
				ov.Value = a
				task.wait()
				assert(got == a)
			end)
			check("Values", function()
				local s = Instance.new("StringValue")
				s.Value = 5 -- coerced
				assert(s.Value == "5")
			end)
			check("Sound", function() local s = Instance.new("Sound", workspace); s:Play(); s:Pause(); s:Resume(); s:Stop() end)
			check("UserSettings", function() assert(UserSettings():GetService("UserGameSettings")) end)
			check("DateTime", function()
				local d = DateTime.fromUniversalTime(2024, 1, 2, 3, 4, 5)
				assert(d:ToIsoDate() == "2024-01-02T03:04:05Z", d:ToIsoDate())
				assert(DateTime.fromIsoDate("2024-01-02T03:04:05Z") == d)
				assert(d:FormatUniversalTime("YYYY-MM-DD") == "2024-01-02")
			end)
			check("Random", function()
				local r = Random.new(1)
				local v = r:NextUnitVector()
				assert(math.abs(v.Magnitude - 1) < 1e-6)
				local c = r:Clone()
				assert(c:NextInteger(1, 1000) == r:NextInteger(1, 1000))
			end)
			check("GetFullName", function() assert(a:GetFullName() == "Workspace.Model.Part") end)
			check("ClearAllChildren", function() local f = Instance.new("Folder"); Instance.new("Part", f); f:ClearAllChildren(); assert(#f:GetChildren() == 0) end)
			check("fromExisting", function() local c = Instance.fromExisting(model); assert(#c:GetChildren() == 0 and c.ClassName == "Model") end)
			_G.results = results
		]],
		},
	})
	sim:StartServer()
	sim:Advance(0.5)
	t.eq(sim:Globals().results, {})
	sim:AssertNoErrors()
end

return tests
