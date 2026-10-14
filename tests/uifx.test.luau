--[[
	UiFx (ReplicatedStorage.Shared.UiFx) in RbxSim against the built Place1.rbxl: every effect
	runs in a real client context, cleans up its temporary instances, looping effects stop when
	asked, the shared frame scheduler holds exactly one connection while anything animates and
	none when idle, and confetti respects the per-device cap (40 on touch, 60 otherwise).
	UI v2 foundation: rays (halo/breathe by device, signed speed, maxPx, the callable handle with
	settle), pooled sounds with pitch and the rarity arpeggio, flash from/hold and flashBig,
	fovPunch (one owner of Camera.FieldOfView, −8° cap; the eased-in wind-up), edgeVignette, fitText
	and the 2 px text outline floor, fadeOut of a ViewportFrame, glowRing stop, the hidden Shine
	overlay. UI v2.1: rays with an empty middle (hole, growFrom) and the shockwave rings of a landing.

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

tests["confettiPop: tween-only confetti — no frame job, shares the cap, removes itself"] = function(t)
	local sim, p = boot(t, "phone")
	local UiFx = fxOf(sim, p)
	local hud = p.PlayerGui.HUD
	local base = sim:CountConnections(p)
	client(sim, p, function()
		UiFx.confettiPop(hud, { count = 30, origin = Vector2.new(0.5, 0.6), duration = 1.2 })
		UiFx.confetti(hud, { count = 30 })
	end)
	t.eq(count(hud, "Piece"), 40, "both kinds share the touch cap")
	t.eq(UiFx.activeJobs(), 1, "only the physics confetti runs per frame")
	local popped = hud:FindFirstChild("FxConfetti")
	local piece
	for _, layer in hud:GetChildren() do
		if layer.Name == "FxConfetti" and #layer:GetChildren() == 30 then
			piece = layer.Piece
		end
	end
	t.ok(popped and piece, "the tweened layer")
	local start = piece.Position
	sim:Advance(0.3)
	t.ok(piece.Position.Y.Scale < start.Y.Scale, "flies up first")
	sim:Advance(2.5)
	t.eq(count(hud, "Piece"), 0, "all pieces removed")
	t.eq(UiFx.liveConfetti(), 0, "the cap is free again")
	t.eq(sim:CountConnections(p), base, "no connections left")
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
	-- A runtime colour becomes a clean swatch (UIConfig.swatchFor), not a grey-tinted face.
	local swatch = UIConfig.swatchFor(base)
	keys = fill.Color.Keypoints
	t.eq(pill.Face.BackgroundColor3, Color3.new(1, 1, 1), "white face under the gradient")
	t.ok(keys[1].Value == swatch.Top and keys[#keys].Value == swatch.Bottom, "swatch gradient from the colour")
	local top = keys[1].Value
	t.ok(top.R > base.R and top.G > base.G and top.B > base.B, "lighter top")
	local lip = pill.Lip.BackgroundColor3
	t.ok(lip.R < base.R and lip.G < base.G and lip.B < base.B, "darker lip")
	sim:AssertNoErrors({ warnings = true })
end

tests["rays: no halo quads on touch, signed speed, size cap, callable handle with settle"] = function(t)
	local sim, p = boot(t, "phone")
	local UiFx = fxOf(sim, p)
	local s = stage(sim, p)
	local s2 = stage(sim, p, "Stage2")
	local rays, counter
	client(sim, p, function()
		rays = UiFx.rays(s, { count = 10, speed = 30, maxPx = 120, transparency = 0.3 })
		counter = UiFx.rays(s2, { count = 8, speed = -15 })
	end)
	local holder = s.FxRays
	t.eq(holder:FindFirstChild("Halo1"), nil, "touch: no halo quads by default")
	t.ok(holder:FindFirstChild("Ray10"), "the core rays")
	t.eq(holder:FindFirstChildOfClass("UISizeConstraint").MaxSize.X, 120, "maxPx caps the sunburst")
	t.ok(holder.FxScale.Scale < 0.5, "grows from the centre")
	sim:Advance(0.5)
	t.near(holder.FxScale.Scale, 1, 1e-3, "grown, without an overshoot or breathing on touch")
	t.ok(holder.Rotation > 5, "spins forwards")
	t.ok(s2.FxRays.Rotation < -2, "a negative speed counter-rotates")
	local ray = holder.Ray1
	t.eq(ray.BackgroundTransparency, 0)
	client(sim, p, function()
		rays:settle({ alphaAdd = 0.3, spinMul = 0.5, time = 0.4 })
	end)
	local r0 = holder.Rotation
	sim:Advance(0.5)
	t.ok(ray.BackgroundTransparency > 0.2, "settle: the rays fade back")
	local turned = (holder.Rotation - r0) % 360
	t.ok(turned > 3 and turned < 12, `settle: slower spin ({turned}° in 0.5 s)`)
	client(sim, p, function()
		rays() -- the handle is callable as stop()
		counter:Destroy() -- … and works in a Trove
	end)
	t.eq(s:FindFirstChild("FxRays"), nil, "removed")
	t.eq(s2:FindFirstChild("FxRays"), nil, "removed")
	sim:AssertNoErrors({ warnings = true })
end

tests["rays: halo quads and breathing stay on by default on a desktop"] = function(t)
	local sim, p = boot(t, "desktop")
	local UiFx = fxOf(sim, p)
	local s = stage(sim, p)
	local rays
	client(sim, p, function()
		rays = UiFx.rays(s, { count = 6 })
	end)
	t.ok(s.FxRays:FindFirstChild("Halo1"), "halo quads on a desktop")
	sim:Advance(1.4)
	t.ok(math.abs(s.FxRays.FxScale.Scale - 1) > 1e-3, "breathing")
	client(sim, p, function()
		rays.stop()
	end)
	t.eq(s:FindFirstChild("FxRays"), nil)
	sim:AssertNoErrors({ warnings = true })
end

tests["rays with a hole: the middle stays empty from the first frame (growFrom), no glow discs"] = function(t)
	local sim, p = boot(t, "desktop")
	local UiFx = fxOf(sim, p)
	local s = stage(sim, p)
	local rays
	client(sim, p, function()
		rays = UiFx.rays(s, { count = 8, hole = 0.3, growFrom = 0.75, halo = false })
	end)
	local holder = s.FxRays
	t.eq(holder:FindFirstChild("GlowInner"), nil, "no glow disc over the middle")
	t.near(holder.FxScale.Scale, 0.75, 0.05, "grows from growFrom, not from nothing")
	local ray = holder.Ray1
	t.near(ray.Size.Y.Scale, 0.35, 1e-6, "a ray spans the outer 70 % of the radius")
	t.near(ray.Position.Y.Scale, 0.5 - 0.325, 1e-6, "…starting at the hole's edge")
	client(sim, p, function()
		rays()
	end)
	t.eq(s:FindFirstChild("FxRays"), nil)
	sim:AssertNoErrors({ warnings = true })
end

tests["shockwave: rings burst out of a point and are gone; the middle stays clear"] = function(t)
	local sim, p = boot(t, "phone")
	local UiFx = fxOf(sim, p)
	local hud = p.PlayerGui.HUD
	client(sim, p, function()
		UiFx.shockwave(hud, Vector2.new(0.4, 0.35), { color = Color3.new(1, 0.9, 0.4), size = 1.3, glow = 0.8 })
	end)
	local ring = hud:FindFirstChild("FxShock")
	t.ok(ring, "a ring at the point")
	t.near(ring.Position.X.Scale, 0.4, 1e-6)
	t.ok(ring.Size.Y.Scale >= 0.2, "it starts wider than what landed (no stroke over it)")
	t.eq(ring.BackgroundTransparency, 1, "a ring, not a disc")
	t.ok(hud.FxShockGlow.BackgroundTransparency >= 0.8 - 1e-6, "a faint glow only")
	t.eq(hud:FindFirstChild("FxFlash"), nil, "not a full-screen flash")
	sim:Advance(0.1)
	t.ok(hud:FindFirstChild("FxShockInner"), "a white ring follows")
	t.ok(ring.Size.Y.Scale > 0.4, "the ring spreads")
	sim:Advance(0.6)
	t.eq(hud:FindFirstChild("FxShock"), nil, "gone")
	t.eq(hud:FindFirstChild("FxShockInner"), nil)
	t.eq(hud:FindFirstChild("FxShockGlow"), nil)
	t.eq(UiFx.activeJobs(), 0, "tweens only")
	sim:AssertNoErrors({ warnings = true })
end

tests["sound: a small pool per sound, pitch per call; arpeggio rises with rarity"] = function(t)
	local sim, p = boot(t)
	local UiFx = fxOf(sim, p)
	local soundService = sim.game:GetService("SoundService")
	local PING = "rbxasset://sounds/electronicpingshort.wav"
	local function pings(): { any }
		local list = {}
		for _, c in soundService:GetChildren() do
			if c:IsA("Sound") and c.SoundId == PING then
				table.insert(list, c)
			end
		end
		return list
	end
	client(sim, p, function()
		UiFx.arpeggio("Legendary", 0.3)
	end)
	sim:Advance(0.4)
	local speeds = {}
	for _, sound in pings() do
		table.insert(speeds, math.floor(sound.PlaybackSpeed * 100 + 0.5))
	end
	table.sort(speeds)
	t.eq(#speeds, 4, "four pooled copies for four notes")
	t.eq(table.concat(speeds, ","), "100,126,150,200", "do-mi-sol-do")
	-- More calls reuse the pool (round robin), never more copies.
	client(sim, p, function()
		for i = 1, 6 do
			UiFx.sound("pop", 0.3, 1 + i / 10)
		end
		UiFx.arpeggio("Mythic")
	end)
	sim:Advance(0.6)
	t.eq(#pings(), 4, "still four copies")
	local stopNotes
	client(sim, p, function()
		stopNotes = UiFx.arpeggio("Mythic")
		stopNotes() -- cancels the notes not yet played
	end)
	sim:Advance(0.6)
	t.eq(UiFx.activeJobs(), 0)
	sim:AssertNoErrors({ warnings = true })
end

tests["flash: from and hold; flashBig is a near-solid flash; still rate-limited"] = function(t)
	local sim, p = boot(t)
	local UiFx = fxOf(sim, p)
	local hud = p.PlayerGui.HUD
	client(sim, p, function()
		UiFx.flash(hud, nil, 0.2, 0.3, 0.1)
	end)
	t.near(hud.FxFlash.BackgroundTransparency, 0.3, 1e-3, "starts at `from`")
	sim:Advance(0.08)
	t.near(hud.FxFlash.BackgroundTransparency, 0.3, 1e-3, "holds")
	sim:Advance(0.4)
	t.eq(hud:FindFirstChild("FxFlash"), nil)
	client(sim, p, function()
		UiFx.flashBig(hud, Color3.new(1, 0.9, 0.3))
	end)
	t.near(hud.FxFlash.BackgroundTransparency, 0.12, 1e-3, "big flash")
	client(sim, p, function()
		UiFx.flashBig(hud)
	end)
	t.eq(count(hud, "FxFlash"), 1, "rate-limited too")
	sim:Advance(0.6)
	t.eq(count(hud, "FxFlash"), 0)
	sim:AssertNoErrors({ warnings = true })
end

tests["fovPunch: one owner of the FOV — sums punches, caps at −8°, restores the base"] = function(t)
	local sim, p = boot(t)
	local UiFx = fxOf(sim, p)
	local camera = sim.workspace.CurrentCamera
	local function fov(): number
		return sim:Run(function()
			return camera.FieldOfView
		end, p)
	end
	client(sim, p, function()
		camera.FieldOfView = 70
		UiFx.fovPunch(-6, 0.1, 0.3)
		UiFx.fovPunch(-6, 0.1, 0.3)
	end)
	sim:Advance(0.1)
	t.near(fov(), 62, 0.01, "two −6° punches are capped at −8°")
	t.eq(UiFx.activeJobs(), 1, "one frame job for all punches")
	sim:Advance(0.5)
	t.near(fov(), 70, 1e-6, "back to the base")
	t.eq(UiFx.activeJobs(), 0, "the job ends with the last punch")
	-- Someone else changes the FOV mid-punch: that value becomes the base.
	client(sim, p, function()
		UiFx.fovPunch(-4, 0.05, 0.4)
	end)
	sim:Advance(0.1)
	client(sim, p, function()
		camera.FieldOfView = 60
	end)
	sim:Advance(0.6)
	t.near(fov(), 60, 1e-6, "the outside change is kept as the new base")
	-- stop() lets a punch go early.
	local stop
	client(sim, p, function()
		stop = UiFx.fovPunch(5, 0.05, 2)
	end)
	sim:Advance(0.1)
	t.ok(fov() > 64, "a positive punch widens the view")
	client(sim, p, function()
		stop()
	end)
	sim:Advance(0.05)
	t.near(fov(), 60, 1e-6, "stopped")
	-- A wind-up (easeIn): slow at first, then the peak; a snap on top of it still caps at −8°.
	client(sim, p, function()
		UiFx.fovPunch(2, 0.25, 0.12, true)
	end)
	sim:Advance(0.08)
	local early = fov() - 60
	t.ok(early > 0 and early < 0.6, `the wind-up starts slowly (+{early}° after 0.08 s)`)
	sim:Advance(0.17)
	t.near(fov(), 62, 0.1, "…and reaches its peak")
	sim:Advance(0.3)
	t.near(fov(), 60, 1e-6, "back to the base")
	client(sim, p, function()
		camera.FieldOfView = 70
	end)
	sim:AssertNoErrors({ warnings = true })
end

tests["edgeVignette: four edge bands fade in, pulse on tweens, stop fades and removes them"] = function(t)
	local sim, p = boot(t)
	local UiFx = fxOf(sim, p)
	local hud = p.PlayerGui.HUD
	local base = sim:CountConnections(p)
	local stop
	client(sim, p, function()
		stop = UiFx.edgeVignette(hud, { Color3.fromRGB(255, 210, 63), Color3.fromRGB(255, 106, 31) }, 0.55, 0.1)
	end)
	local layer = hud.FxVignette
	t.eq(#layer:GetChildren(), 4, "top, bottom, left, right")
	t.eq(layer.Top.BackgroundTransparency, 1, "starts invisible")
	sim:Advance(0.36)
	t.near(layer.Top.BackgroundTransparency, 0.55, 0.02, "faded in to alpha")
	sim:Advance(0.3)
	local seen = layer.Left.BackgroundTransparency
	t.ok(seen >= 0.55 - 1e-3 and seen <= 0.75 + 1e-3, `pulses between alpha and alpha + 0.2 ({seen})`)
	t.eq(UiFx.activeJobs(), 0, "tweens only, no frame job")
	t.eq(sim:CountConnections(p), base, "no connections")
	client(sim, p, function()
		stop(0.1)
	end)
	sim:Advance(0.2)
	t.eq(hud:FindFirstChild("FxVignette"), nil, "removed after its fade")
	-- A one-shot: fades in at once and leaves by itself.
	client(sim, p, function()
		UiFx.edgeVignette(hud, Color3.fromRGB(255, 240, 122), 0.8, nil, { fadeIn = 0, hold = 0, fadeOut = 0.25 })
	end)
	t.near(hud.FxVignette.Bottom.BackgroundTransparency, 0.8, 1e-3)
	sim:Advance(0.4)
	t.eq(hud:FindFirstChild("FxVignette"), nil, "one-shot gone")
	sim:AssertNoErrors({ warnings = true })
end

tests["edgeVignette: a frame that builds (from → alpha, Quad In), cycling colours, stop(0) cuts it"] = function(t)
	local sim, p = boot(t)
	local UiFx = fxOf(sim, p)
	local hud = p.PlayerGui.HUD
	local stop
	local colors = { Color3.fromRGB(255, 0, 0), Color3.fromRGB(0, 255, 0), Color3.fromRGB(0, 0, 255) }
	client(sim, p, function()
		stop = UiFx.edgeVignette(hud, colors[1], 0.5, nil, {
			from = 0.85,
			fadeIn = 0.6,
			build = true,
			size = 0.13,
			cycle = colors,
		})
	end)
	local layer = hud.FxVignette
	t.near(layer.Top.BackgroundTransparency, 0.85, 0.02, "starts at `from`")
	sim:Advance(0.3)
	local half = layer.Top.BackgroundTransparency
	t.ok(half > 0.85 - (0.85 - 0.5) * 0.5, `builds slowly first (Quad In: {half} at half time)`)
	sim:Advance(0.35)
	t.near(layer.Top.BackgroundTransparency, 0.5, 0.02, "…and ends at alpha")
	t.ok(UiFx.activeJobs() > 0, "the cycling colours are a frame job while it lives")
	local function same(a: Color3, b: Color3): boolean
		return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.05
	end
	t.ok(not same(layer.Top.BackgroundColor3, layer.Bottom.BackgroundColor3), "each side its own colour")
	local before = layer.Top.BackgroundColor3
	sim:Advance(0.3)
	t.ok(not same(before, layer.Top.BackgroundColor3), "…and the colours run round the frame")
	client(sim, p, function()
		stop(0)
	end)
	t.eq(hud:FindFirstChild("FxVignette"), nil, "stop(0) cuts it at once (no fade into the landing)")
	sim:Advance(0.1)
	t.eq(UiFx.activeJobs(), 0, "the colour job is gone too")
	sim:AssertNoErrors({ warnings = true })
end

tests["fitText, text outline floor, fadeOut of a ViewportFrame, glowRing stop, hidden Shine"] = function(t)
	local sim, p = boot(t, "phone")
	local UiFx = fxOf(sim, p)
	local hud = p.PlayerGui.HUD
	local s = stage(sim, p)
	-- A tiered label added later gets the size of its tier on this screen (phone: 14/12).
	local small = sim:Create("TextLabel", { Name = "Chip", Size = UDim2.fromScale(1, 0.5), TextScaled = true }, nil)
	small:SetAttribute("TextTier", "Small")
	local outline = sim:Create("UIStroke", { Name = "Outline", Thickness = 2 }, small)
	outline:SetAttribute("BaseThickness", 2)
	small.Parent = s
	sim:Advance(0.05)
	local c = small:FindFirstChildOfClass("UITextSizeConstraint")
	t.ok(c, "a size constraint is added")
	t.eq(c.MaxTextSize, 14)
	t.eq(c.MinTextSize, 12)
	t.eq(
		client(sim, p, function()
			return UiFx.textSize("Small")
		end),
		14,
		"textSize tells the same size"
	)
	t.ok(outline.Thickness >= 2, "text outlines never thinner than 2 px (phone would give 1.5)")
	-- fadeOut also fades a 3D ViewportFrame (the fish on the card).
	local vp = sim:Create("ViewportFrame", { Name = "Vp", Size = UDim2.fromScale(0.5, 0.5) }, s)
	client(sim, p, function()
		UiFx.fadeOut(s, 0.2)
	end)
	sim:Advance(0.3)
	t.near(vp.ImageTransparency, 1, 1e-3, "the viewport fades")
	-- glowRing stop fades its rings that are still flying.
	local s2 = stage(sim, p, "Stage2")
	local stopRing
	client(sim, p, function()
		stopRing = UiFx.glowRing(s2, { time = 2, loop = true })
	end)
	sim:Advance(0.1)
	t.eq(count(s2, "FxRing"), 1)
	client(sim, p, function()
		stopRing()
	end)
	sim:Advance(0.15)
	t.eq(count(s2, "FxRing"), 0, "rings gone 0.1 s after stop")
	-- A candy's Shine overlay is hidden at rest and shown only while a sweep runs.
	local pill = candy(sim, p)
	local shine = pill.Face.Shine
	t.eq(shine.Visible, false, "hidden at rest")
	client(sim, p, function()
		UiFx.shine(pill, 0.5)
	end)
	sim:Advance(0.3)
	client(sim, p, function()
		UiFx.shine(pill, 0.5) -- overlaps the first one
	end)
	t.eq(shine.Visible, true, "visible while sweeping")
	sim:Advance(0.3)
	t.eq(shine.Visible, true, "the second sweep keeps it visible")
	sim:Advance(0.3)
	t.eq(shine.Visible, false, "hidden again")
	t.eq(hud:FindFirstChild("FxFlash"), nil)
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
