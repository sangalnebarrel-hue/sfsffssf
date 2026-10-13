--[[
	UiFx (ReplicatedStorage.Shared.UiFx) in RbxSim against the built Place1.rbxl: every effect
	runs in a real client context, cleans up its temporary instances, looping effects stop when
	asked, the shared frame scheduler holds exactly one connection while anything animates and
	none when idle, and confetti respects the per-device cap (40 on touch, 60 otherwise).

	Run: lune run tools/run_tests.luau uifx
]]

local roblox = require("@lune/roblox")

local UDim2 = roblox.UDim2
local Vector2 = roblox.Vector2
local Color3 = roblox.Color3

local function boot(t: any, device: string?): (any, any)
	local sim = t.sim({ place = t.place })
	sim:StartServer()
	sim:Advance(0.5)
	local p = sim:AddPlayer({ UserId = 1, Name = "Fx", device = device or "desktop" })
	sim:Advance(6) -- join juice (badge pop, toast) is over
	return sim, p
end

-- The client's own UiFx module (same instance the controllers use).
local function fxOf(sim: any, p: any): any
	return sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p)
end

-- Runs fn in the player's client context (so RunService/UserInputService answer for that client).
local function client(sim: any, p: any, fn: () -> any): any
	return sim:Run(fn, p)
end

-- An empty frame in the middle of the player's HUD to play effects on.
local function stage(sim: any, p: any, name: string?): any
	return sim:Create("Frame", {
		Name = name or "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.3, 0.12),
		BackgroundColor3 = Color3.fromRGB(80, 160, 240),
	}, p.PlayerGui.HUD)
end

-- A candy pill (a clone of the toast template: Lip, Face/Fill/Gloss/Shine, IconSocket, Label).
local function candy(sim: any, p: any): any
	local pill = p.PlayerGui.HUD.Toasts.ToastTemplate:Clone()
	pill.Name = "CandyStage"
	pill.Visible = true
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromScale(0.5, 0.15)
	pill.Parent = p.PlayerGui.HUD
	sim:Advance(0.05)
	return pill
end

local function count(root: any, name: string): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d.Name == name then
			n += 1
		end
	end
	return n
end

local tests = {}

tests["scheduler: one RenderStepped connection for all frame effects, none when idle"] = function(t)
	local sim, p = boot(t)
	local UiFx = fxOf(sim, p)
	local hud = p.PlayerGui.HUD
	local base = sim:CountConnections(p)
	t.eq(UiFx.activeJobs(), 0, "idle HUD runs no frame effects")

	local s = stage(sim, p)
	local label = sim:Create("TextLabel", { Name = "Num", Size = UDim2.fromScale(1, 1) }, s)
	local gradient = sim:Create("UIGradient", { Name = "Rainbow" }, s)
	local stopRainbow
	client(sim, p, function()
		UiFx.confetti(hud, { count = 20, duration = 1 })
		UiFx.countUp(label, 0, 250, 0.5)
		stopRainbow = UiFx.rainbow(gradient)
	end)
	t.eq(UiFx.activeJobs(), 3, "three frame effects")
	t.eq(sim:CountConnections(p), base + 1, "…on a single connection")
	sim:Advance(0.2)
	local partial = tonumber(label.Text)
	t.ok(partial and partial > 0 and partial < 250, `count-up is running ({label.Text})`)
	sim:Advance(1.2)
	t.eq(label.Text, "250", "count-up ends on the value")
	t.eq(UiFx.activeJobs(), 1, "confetti and count-up finished")
	t.eq(sim:CountConnections(p), base + 1)
	client(sim, p, function()
		stopRainbow()
	end)
	t.eq(UiFx.activeJobs(), 0)
	t.eq(sim:CountConnections(p), base, "the scheduler disconnects when nothing runs")
	sim:Advance(0.5)
	t.eq(sim:CountConnections(p), base)
	sim:AssertNoErrors({ warnings = true })
end

tests["confetti: capped at 60 on desktop (all bursts together), pieces fly, fade and are removed"] = function(t)
	local sim, p = boot(t, "desktop")
	local UiFx = fxOf(sim, p)
	local hud = p.PlayerGui.HUD
	client(sim, p, function()
		UiFx.confetti(hud, { count = 100, origin = Vector2.new(0.5, 0.8) })
		UiFx.confetti(hud, { count = 10 })
	end)
	t.eq(count(hud, "Piece"), 60, "60 pieces at most")
	t.eq(UiFx.liveConfetti(), 60)
	local piece = hud:FindFirstChild("FxConfetti"):FindFirstChild("Piece")
	local start = piece.Position
	sim:Advance(0.3)
	t.ok(piece.Position ~= start, "pieces move")
	t.ok(piece.Position.Y.Scale < 0.8, "launched upwards")
	sim:Advance(1.3)
	local fading = 0
	for _, d in hud:GetDescendants() do
		if d.Name == "Piece" and d.BackgroundTransparency > 0 then
			fading += 1
		end
	end
	t.ok(fading > 0, "pieces fade near the end of their life")
	sim:Advance(1)
	t.eq(count(hud, "Piece"), 0, "all pieces removed")
	t.eq(hud:FindFirstChild("FxConfetti"), nil, "layer removed")
	t.eq(UiFx.liveConfetti(), 0)
	client(sim, p, function()
		UiFx.confetti(hud, { count = 5 })
	end)
	t.eq(count(hud, "Piece"), 5, "budget is free again")
	sim:AssertNoErrors({ warnings = true })
end

tests["confetti: capped at 40 on a phone; stop removes everything at once"] = function(t)
	local sim, p = boot(t, "phone")
	local UiFx = fxOf(sim, p)
	local hud = p.PlayerGui.HUD
	local stop
	client(sim, p, function()
		stop = UiFx.confetti(hud, { count = 100 })
	end)
	t.eq(
		client(sim, p, function()
			return UiFx.confettiCap()
		end),
		40,
		"cap on a touch device"
	)
	t.eq(count(hud, "Piece"), 40, "40 pieces at most on touch devices")
	sim:Advance(0.2)
	client(sim, p, function()
		stop()
	end)
	t.eq(count(hud, "Piece"), 0, "stop removes the pieces")
	t.eq(UiFx.liveConfetti(), 0)
	t.eq(UiFx.activeJobs(), 0)
	sim:AssertNoErrors({ warnings = true })
end

tests["one-shot effects leave nothing behind and restore the element"] = function(t)
	local sim, p = boot(t)
	local UiFx = fxOf(sim, p)
	local hud = p.PlayerGui.HUD
	local s = stage(sim, p)
	local pill = candy(sim, p)
	local target = p.PlayerGui.HUD.RightButtons.HomeButton
	sim:Advance(0.1)
	local hudBefore = #hud:GetChildren()
	local stageBefore = #s:GetDescendants()
	local pillBefore = #pill:GetDescendants()
	local position, rotation = s.Position, s.Rotation

	client(sim, p, function()
		UiFx.popIn(s, { rotate = -6 })
		UiFx.wiggle(s)
		UiFx.shake(s)
		UiFx.shine(s) -- not a candy: a temporary Shine overlay
		UiFx.shine(pill) -- candy: its own Face.Shine
		UiFx.glowRing(s)
		UiFx.glowRing(pill, { filled = true })
		UiFx.ripple(s)
		UiFx.floatText(s, "ОТЛИЧНО!")
		UiFx.burst(s)
		UiFx.sparkles(s, { duration = 0.5 })
		UiFx.flash(hud)
		UiFx.flyTo(hud, s, target, { text = "🐟" })
		UiFx.slam(pill)
		UiFx.bump(pill)
	end)
	sim:Advance(0.1)
	t.ok(count(s, "Shine") == 1, "temporary shine overlay while sweeping")
	t.ok(count(s, "FxRing") == 2, "rings")
	t.ok(s:FindFirstChild("FxFloat"), "float text")
	t.ok(s:FindFirstChild("FxBurst"), "burst")
	t.ok(hud:FindFirstChild("FxFlash"), "flash")
	t.ok(hud:FindFirstChild("FxFly"), "flying icon")
	local band = pill.Face.Shine.Band
	sim:Advance(0.2)
	t.ok(band.Offset.X > -1 and band.Offset.X < 1, "the candy's band sweeps")

	sim:Advance(2.5)
	t.eq(#hud:GetChildren(), hudBefore, "no temporary children left in the HUD")
	-- FxScale is the one permanent helper an animated element gets.
	t.eq(#s:GetDescendants(), stageBefore + 1, "only FxScale stays on the stage")
	t.eq(#pill:GetDescendants(), pillBefore + 1, "only FxScale stays on the candy")
	t.eq(s.Position, position, "shake returned to the rest position")
	t.near(s.Rotation, rotation, 1e-6, "wiggle returned to the rest rotation")
	t.near(s.FxScale.Scale, 1, 1e-6, "scale back to 1")
	t.near(pill.FxScale.Scale, 1, 1e-6)
	t.near(band.Offset.X, 1, 1e-6, "band parked out of sight")
	t.eq(UiFx.activeJobs(), 0)
	sim:AssertNoErrors({ warnings = true })
end

tests["looping effects run until their stop function is called"] = function(t)
	local sim, p = boot(t)
	local UiFx = fxOf(sim, p)
	local s = stage(sim, p)
	local pill = candy(sim, p)
	local fill = pill.Face.Fill
	local originalColor = fill.Color
	local stops = {}
	client(sim, p, function()
		stops.pulse = UiFx.pulse(s)
		stops.rays = UiFx.rays(s, { count = 14 })
		stops.sparkles = UiFx.sparkles(s, { rate = 10 })
		stops.rings = UiFx.glowRing(s, { loop = true, interval = 0.5 })
		stops.shine = UiFx.shineLoop(pill, { interval = 0.5, delay = 0.1 })
		stops.rainbow = UiFx.rainbow(fill)
	end)
	sim:Advance(1.3)
	t.ok(s.FxScale.Scale > 1.001, "pulse is breathing")
	t.ok(s:FindFirstChild("FxRays"), "rays")
	t.eq(count(s:FindFirstChild("FxRays"), "Ray1"), 1)
	t.ok(count(s, "FxSparkle") > 0, "sparkles keep coming")
	t.ok(count(s, "FxRing") > 0, "rings keep coming")
	t.ok(fill.Color ~= originalColor, "rainbow recolours the gradient")
	local before = fill.Color
	sim:Advance(0.3)
	t.ok(fill.Color ~= before, "…and keeps moving")
	local sweeping = false
	for _ = 1, 40 do
		sim:Advance(0.05)
		local x = pill.Face.Shine.Band.Offset.X
		if x > -0.99 and x < 0.99 then
			sweeping = true
		end
	end
	t.ok(sweeping, "the shine loop sweeps again and again")

	client(sim, p, function()
		for _, stop in stops do
			stop()
		end
	end)
	t.near(s.FxScale.Scale, 1, 1e-6, "pulse stopped at scale 1")
	t.eq(s:FindFirstChild("FxRays"), nil, "rays removed")
	t.eq(count(s, "FxSparkle"), 0, "sparkles removed at once")
	t.eq(fill.Color, originalColor, "rainbow restores the colours")
	sim:Advance(1)
	t.eq(count(s, "FxRing"), 0, "no more rings")
	t.near(s.FxScale.Scale, 1, 1e-6)
	local parked = pill.Face.Shine.Band.Offset.X
	sim:Advance(1.5)
	t.eq(pill.Face.Shine.Band.Offset.X, parked, "no more shines")
	t.eq(UiFx.activeJobs(), 0)
	sim:AssertNoErrors({ warnings = true })
end

tests["count-up, timer bar, trail and fly-to finish cleanly; stop jumps to the end"] = function(t)
	local sim, p = boot(t)
	local UiFx = fxOf(sim, p)
	local hud = p.PlayerGui.HUD
	local s = stage(sim, p)
	local label = sim:Create("TextLabel", { Name = "Price", Size = UDim2.fromScale(1, 1) }, s)
	local fill = sim:Create("Frame", { Name = "Fill", Size = UDim2.fromScale(1, 0.2) }, s)
	local needle = sim:Create("Frame", { Name = "Needle", Size = UDim2.fromScale(0.02, 1) }, s)
	local arrived = false
	local stopCount, stopTrail
	client(sim, p, function()
		stopCount = UiFx.countUp(label, 0, 1000, 1, function(n)
			return `{n} 💰`
		end)
		UiFx.timerBar(fill, 0.5)
		stopTrail = UiFx.trail(needle, { count = 3 })
		UiFx.flyTo(hud, s, hud.RightButtons.HomeButton, {
			onArrive = function()
				arrived = true
			end,
		})
	end)
	t.eq(count(s, "FxGhost"), 3, "three ghosts follow the needle")
	for i = 1, 10 do
		needle.Position = UDim2.fromScale(i / 10, 0)
		sim:Advance(1 / 60)
	end
	t.ok(s.FxGhost.Position.X.Scale < needle.Position.X.Scale, "ghosts lag behind")
	sim:Advance(0.2)
	client(sim, p, function()
		stopCount()
	end)
	t.eq(label.Text, "1000 💰", "stopping a count-up shows the final value")
	sim:Advance(0.5)
	t.near(fill.Size.X.Scale, 0, 1e-6, "timer bar drained")
	t.ok(arrived, "fly-to called onArrive")
	t.eq(hud:FindFirstChild("FxFly"), nil, "flying icon removed")
	client(sim, p, function()
		stopTrail()
	end)
	t.eq(count(s, "FxGhost"), 0, "ghosts removed")
	-- Camera shake: a translation-only jitter bound to the render step, unbound by itself.
	local camera = sim.workspace.CurrentCamera
	local still = camera.CFrame
	client(sim, p, function()
		UiFx.cameraShake(0.5, 0.3)
	end)
	sim:Advance(0.1)
	local shaken = sim:Run(function()
		return camera.CFrame
	end, p)
	t.ok((shaken.Position - still.Position).Magnitude > 1e-4, "the camera jitters")
	t.ok(shaken.LookVector:Dot(still.LookVector) > 0.9999, "without turning")
	t.eq(UiFx.activeJobs(), 0)
	sim:AssertNoErrors({ warnings = true })
end

tests["press: squashes on press, springs back on release; the binding can be removed"] = function(t)
	local sim, p = boot(t, "phone")
	local UiFx = fxOf(sim, p)
	local button = sim:Create("TextButton", {
		Name = "Btn",
		Size = UDim2.fromScale(0.2, 0.2),
		Position = UDim2.fromScale(0.4, 0.4),
		Text = "",
	}, p.PlayerGui.HUD)
	local base = sim:CountConnections(p)
	local unbind
	client(sim, p, function()
		unbind = UiFx.press(button)
	end)
	t.eq(sim:CountConnections(p), base + 3, "down, up and leave")
	-- Only the press (MouseButton1Down) — sim:Click would also release in the same frame.
	local real = sim:Unwrap(button)
	local ctx = sim.players.state[sim:Unwrap(p)].ctx
	sim.proxy:fireFiltered(real, "MouseButton1Down", function(c)
		return c == ctx
	end, 0, 0)
	sim:Advance(0.15)
	t.near(button.FxScale.Scale, 0.88, 0.01, "squashed while held")
	t.eq(sim:CountConnections(p), base + 4, "listens for the release anywhere")
	sim:FireInput(p, "InputEnded", {
		UserInputType = roblox.Enum.UserInputType.Touch,
		UserInputState = roblox.Enum.UserInputState.End,
	})
	sim:Advance(0.05)
	t.eq(sim:CountConnections(p), base + 3, "released: the global listener is gone")
	sim:Advance(0.4)
	t.near(button.FxScale.Scale, 1, 0.01, "springs back")
	sim:Click(p, button)
	sim:Advance(0.4)
	t.near(button.FxScale.Scale, 1, 0.01, "a full click ends at scale 1")
	client(sim, p, function()
		unbind()
	end)
	t.eq(sim:CountConnections(p), base, "unbound")
	sim:AssertNoErrors({ warnings = true })
end

tests["setCandy recolours a candy by token, by swatch and by a runtime colour"] = function(t)
	local sim, p = boot(t)
	local UiFx = fxOf(sim, p)
	local pill = candy(sim, p)
	local fill = pill.Face.Fill
	local UIConfig = sim:Require(sim:Find("ReplicatedStorage.Shared.Config.UIConfig"), p)
	client(sim, p, function()
		UiFx.setCandy(pill, "Berry")
	end)
	local keys = fill.Color.Keypoints
	t.eq(keys[1].Value, UIConfig.Palette.Berry.Top)
	t.eq(keys[#keys].Value, UIConfig.Palette.Berry.Bottom)
	t.eq(pill.Lip.BackgroundColor3, UIConfig.Palette.Berry.Lip)
	t.eq(pill.Face.BackgroundColor3, Color3.new(1, 1, 1))
	local base = Color3.fromRGB(62, 114, 200)
	client(sim, p, function()
		UiFx.setCandy(pill, base)
	end)
	t.eq(pill.Face.BackgroundColor3, base, "runtime colour on the face")
	local lip = pill.Lip.BackgroundColor3
	t.ok(lip.R < base.R and lip.G < base.G and lip.B < base.B, "darker lip")
	sim:AssertNoErrors({ warnings = true })
end

tests["flash is rate-limited (never more than 3 per second)"] = function(t)
	local sim, p = boot(t)
	local UiFx = fxOf(sim, p)
	local hud = p.PlayerGui.HUD
	client(sim, p, function()
		UiFx.flash(hud)
		UiFx.flash(hud)
		UiFx.flash(hud)
	end)
	t.eq(count(hud, "FxFlash"), 1, "one flash for three calls in the same frame")
	sim:Advance(0.4)
	t.eq(count(hud, "FxFlash"), 0, "gone after its time")
	client(sim, p, function()
		UiFx.flash(hud)
	end)
	t.eq(count(hud, "FxFlash"), 1, "allowed again later")
	sim:AssertNoErrors({ warnings = true })
end

return tests
