--[[
	HUD chrome in the "Candy Splash" style (tools/builder/gui/Hud.luau + HudController +
	NotifyController) in RbxSim against the built Place1.rbxl:
	  • every contract name is still there (controllers and tests find widgets by name);
	  • the chrome is made of candies: Lip (outline), face with a "Fill" gradient, Gloss, Shine;
	  • the layout still fits on a phone, a tablet and a desktop: nothing overlaps, everything is
	    on screen, the Home button stays above the Jump button on touch screens;
	  • the runtime juice: base colour on the badge, «+N» over the catch counter, the draining
	    Home cooldown, toasts by kind (colour, icon, width, slots), no frame connection at idle.

	The sim ignores UIListLayout alignment, so this file computes rectangles itself (rectOf).

	Run: lune run tools/run_tests.luau hud_style
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Enum = roblox.Enum
local Color3 = roblox.Color3

local INSET = 58 -- RbxSim's top bar inset for ScreenGuis without IgnoreGuiInset

local function loadConfig(name: string): any
	local path = `src/ReplicatedStorage/Shared/Config/{name}.luau`
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum },
		injectGlobals = true,
	})
	return chunk()
end

local UIConfig = loadConfig("UIConfig")
local BaseConfig = loadConfig("BaseConfig")

local function boot(t: any): any
	local sim = t.sim({ place = t.place })
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

local function addPlayer(sim: any, id: number, device: string): any
	local p = sim:AddPlayer({ UserId = id, Name = `Hud{id}`, device = device })
	sim:Advance(1)
	return p
end

local function notify(sim: any, p: any, text: string, kind: string)
	sim:Find("ReplicatedStorage.Remotes.Notify"):FireClient(p, text, kind)
end

local function colorNear(a: any, b: any, eps: number?): boolean
	local e = eps or 0.01
	return math.abs(a.R - b.R) <= e and math.abs(a.G - b.G) <= e and math.abs(a.B - b.B) <= e
end

-- Layout ------------------------------------------------------------------------------------

type Rect = { x: number, y: number, w: number, h: number }

local function visibleItems(parent: any): { any }
	local items = {}
	for _, c in parent:GetChildren() do
		if c:IsA("GuiObject") and c.Visible then
			table.insert(items, c)
		end
	end
	table.sort(items, function(a, b)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return a.Name < b.Name
	end)
	return items
end

-- Absolute rectangle like Roblox lays it out (incl. list alignment), for a player's GUI.
local function rectOf(sim: any, p: any, gui: any): Rect
	local parent = gui.Parent
	local size = gui.AbsoluteSize
	if parent:IsA("LayerCollector") then
		local vp = sim.players.state[sim:Unwrap(p)].viewport
		local prect = { x = 0, y = INSET, w = vp.X, h = vp.Y - INSET }
		local pos, anchor = gui.Position, gui.AnchorPoint
		return {
			x = prect.x + pos.X.Scale * prect.w + pos.X.Offset - anchor.X * size.X,
			y = prect.y + pos.Y.Scale * prect.h + pos.Y.Offset - anchor.Y * size.Y,
			w = size.X,
			h = size.Y,
		}
	end
	local prect = rectOf(sim, p, parent)
	local list = parent:FindFirstChildOfClass("UIListLayout")
	if list then
		local vertical = list.FillDirection == Enum.FillDirection.Vertical
		local pad = list.Padding
		local padPx = pad.Scale * (if vertical then prect.h else prect.w) + pad.Offset
		local items = visibleItems(parent)
		local total, along, found = 0, 0, false
		for i, c in items do
			local s = c.AbsoluteSize
			local extent = if vertical then s.Y else s.X
			if c == gui then
				found = true
			end
			if not found then
				along += extent + padPx
			end
			total += extent + (if i > 1 then padPx else 0)
		end
		local main = if vertical then prect.h else prect.w
		local cross = if vertical then prect.w else prect.h
		local mainAlign = if vertical then list.VerticalAlignment.Name else list.HorizontalAlignment.Name
		local crossAlign = if vertical then list.HorizontalAlignment.Name else list.VerticalAlignment.Name
		local start = if mainAlign == "Center"
			then (main - total) / 2
			elseif mainAlign == "Bottom" or mainAlign == "Right" then main - total
			else 0
		local crossSize = if vertical then size.X else size.Y
		local crossPos = if crossAlign == "Center"
			then (cross - crossSize) / 2
			elseif crossAlign == "Bottom" or crossAlign == "Right" then cross - crossSize
			else 0
		if vertical then
			return { x = prect.x + crossPos, y = prect.y + start + along, w = size.X, h = size.Y }
		end
		return { x = prect.x + start + along, y = prect.y + crossPos, w = size.X, h = size.Y }
	end
	local pos, anchor = gui.Position, gui.AnchorPoint
	return {
		x = prect.x + pos.X.Scale * prect.w + pos.X.Offset - anchor.X * size.X,
		y = prect.y + pos.Y.Scale * prect.h + pos.Y.Offset - anchor.Y * size.Y,
		w = size.X,
		h = size.Y,
	}
end

local function overlap(a: Rect, b: Rect, tolerance: number?): number
	local tol = tolerance or 0
	local dx = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local dy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	if dx <= tol or dy <= tol then
		return 0
	end
	return dx * dy
end

local function fmt(r: Rect): string
	return string.format("(%d,%d %dx%d)", r.x, r.y, r.w, r.h)
end

-- Candy check ---------------------------------------------------------------------------------

local function checkCandy(t: any, root: any, token: string?, what: string)
	local faceName = root:GetAttribute("CandyFace")
	t.ok(type(faceName) == "string", `{what}: CandyFace attribute`)
	local lip = root:FindFirstChild("Lip")
	local face = root:FindFirstChild(faceName)
	t.ok(lip and lip:IsA("Frame"), `{what}: Lip`)
	t.ok(face and face:IsA("Frame"), `{what}: face {faceName}`)
	t.ok(lip.ZIndex < face.ZIndex, `{what}: the lip is behind the face`)
	t.ok(face.Size.Y.Scale < 1 and face.Size.Y.Scale >= 0.9, `{what}: the lip shows under the face`)
	local outline = lip:FindFirstChildOfClass("UIStroke")
	t.ok(outline, `{what}: the outline is on the lip`)
	t.eq(outline:GetAttribute("BaseThickness"), 3, `{what}: outline designed at 3 px`)
	t.ok(colorNear(outline.Color, UIConfig.Ink), `{what}: Ink outline`)
	local fill = face:FindFirstChild("Fill")
	t.ok(fill and fill:IsA("UIGradient"), `{what}: Fill gradient`)
	t.eq(fill.Rotation, 90, `{what}: vertical gradient`)
	if token then
		local keys = fill.Color.Keypoints
		t.ok(colorNear(keys[1].Value, UIConfig.Palette[token].Top), `{what}: {token} top`)
		t.ok(colorNear(keys[#keys].Value, UIConfig.Palette[token].Bottom), `{what}: {token} bottom`)
		t.ok(colorNear(lip.BackgroundColor3, UIConfig.Palette[token].Lip), `{what}: {token} lip`)
	end
	local gloss = face:FindFirstChild("Gloss")
	t.ok(gloss and gloss:FindFirstChildOfClass("UIGradient"), `{what}: Gloss with a fading gradient`)
	local shine = face:FindFirstChild("Shine")
	t.ok(shine and shine:FindFirstChild("Band"), `{what}: Shine overlay with its Band`)
	t.ok(shine:FindFirstChildOfClass("UICorner"), `{what}: the shine follows the rounded corners`)
	t.ok(math.abs(shine.Band.Offset.X) >= 1, `{what}: the band waits out of sight`)
end

local tests = {}

tests["names: every widget the controllers and tests use is still there"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	local paths = {
		"Status.BaseBadge.Swatch",
		"Status.BaseBadge.Label",
		"Status.CatchCounter.Icon",
		"Status.CatchCounter.Label",
		"RightButtons.HomeButton.Icon",
		"RightButtons.HomeButton.Caption",
		"RightButtons.HomeButton.Cooldown",
		"Toasts.ToastTemplate.Label",
		"Fishing.ActionArea.ActionButton.Icon",
		"Fishing.ActionArea.ActionButton.Caption",
		"Fishing.ActionArea.ActionButton.Ring",
		"Fishing.ActionArea.StopButton.Caption",
		"Fishing.BiteAlert.Label",
		"Fishing.BiteAlert.Timer",
		"Fishing.Minigame.Title",
		"Fishing.Minigame.Pips.Pip1",
		"Fishing.Minigame.Pips.Pip5",
		"Fishing.Minigame.Track.Zone",
		"Fishing.Minigame.Track.Needle",
		"Fishing.Minigame.TimeBar.Fill",
		"Fishing.Minigame.Help",
		"Fishing.Hint",
		"Fishing.CatchCard.Banner.RarityLabel",
		"Fishing.CatchCard.Viewport",
		"Fishing.CatchCard.NameLabel",
		"Fishing.CatchCard.MutationLabel",
		"Fishing.CatchCard.InfoLabel",
		"Fishing.CatchCard.TapHint",
	}
	for _, path in paths do
		t.ok(sim:Gui(p, `HUD.{path}`), `HUD.{path}`)
	end
	t.ok(sim:Gui(p, "HUD.RightButtons.HomeButton"):IsA("GuiButton"), "Home is a button")
	t.ok(sim:Gui(p, "HUD.Status.BaseBadge.Label"):IsA("TextLabel"))
	sim:AssertNoErrors({ warnings = true })
end

tests["candies: badge, counter, Home and toasts have lip, gradient face, gloss and shine"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	local hud = p.PlayerGui.HUD
	checkCandy(t, hud.Status.BaseBadge, nil, "BaseBadge")
	t.eq(hud.Status.BaseBadge:GetAttribute("CandyFace"), "Swatch", "the badge face is the Swatch")
	checkCandy(t, hud.Status.CatchCounter, "Gold", "CatchCounter")
	checkCandy(t, hud.RightButtons.HomeButton, "Leaf", "HomeButton")
	checkCandy(t, hud.Toasts.ToastTemplate, "Sky", "ToastTemplate")

	-- Text: white with an Ink outline; icons are emoji without outline.
	for _, label in
		{
			hud.Status.BaseBadge.Label,
			hud.Status.CatchCounter.Label,
			hud.RightButtons.HomeButton.Caption,
			hud.Toasts.ToastTemplate.Label,
		}
	do
		t.ok(colorNear(label.TextColor3, Color3.new(1, 1, 1)), `{label:GetFullName()}: white text`)
		local outline = label:FindFirstChild("Outline")
		t.ok(outline and outline:IsA("UIStroke"), `{label:GetFullName()}: outlined`)
		t.eq(outline.ApplyStrokeMode, Enum.ApplyStrokeMode.Contextual)
		t.ok(label.ZIndex > label.Parent.Lip.ZIndex + 1, `{label:GetFullName()}: above the face`)
	end
	t.eq(hud.Status.CatchCounter.Icon.Text, "🐟")
	t.eq(hud.RightButtons.HomeButton.Icon.Text, "🏠")
	t.ok(hud.Status.BaseBadge.FlagSocket.Flag, "flag socket on the badge")
	t.ok(hud.Toasts.ToastTemplate.IconSocket.Icon, "icon socket on toasts")
	t.ok(hud.RightButtons.HomeButton.Cooldown:FindFirstChild("Drain"), "draining cooldown veil")
	t.ok(hud.RightButtons.HomeButton.Cooldown.ZIndex > hud.RightButtons.HomeButton.Caption.ZIndex)
	sim:AssertNoErrors({ warnings = true })
end

tests["layout: the chrome fits on phone, tablet and desktop without overlaps"] = function(t)
	local sim = boot(t)
	local devices = { "phone", "tablet", "desktop" }
	local players = {}
	for i, device in devices do
		players[device] = addPlayer(sim, i, device)
	end
	for _, device in devices do
		local p = players[device]
		p:SetAttribute("FishCaught", 7) -- shows the catch counter
		notify(
			sim,
			p,
			"Улов дня! Вася — «Дракон-рыба» (Мифическая, Радужная)",
			"info"
		)
		notify(sim, p, "Сейчас нельзя вернуться домой", "warning")
		notify(sim, p, "Ура!", "success")
	end
	sim:Advance(1) -- toasts have settled in their slots

	for _, device in devices do
		local p = players[device]
		local hud = p.PlayerGui.HUD
		local vp = sim.players.state[sim:Unwrap(p)].viewport
		local function r(gui: any): Rect
			return rectOf(sim, p, gui)
		end
		local badge = r(hud.Status.BaseBadge)
		local counter = r(hud.Status.CatchCounter)
		local home = r(hud.RightButtons.HomeButton)
		t.ok(hud.Status.CatchCounter.Visible, `{device}: counter shown`)
		t.ok(hud.RightButtons.HomeButton.Visible, `{device}: Home shown`)
		local toasts = {}
		for _, c in hud.Toasts:GetChildren() do
			if c.Name == "Toast" then
				table.insert(toasts, c)
			end
		end
		t.eq(#toasts, 3, `{device}: three toasts`)

		local rects: { [string]: Rect } = { badge = badge, counter = counter, home = home }
		for i, toast in toasts do
			rects[`toast{i}`] = r(toast)
		end
		-- Everything on screen, below the top bar.
		local decorations = {
			flag = r(hud.Status.BaseBadge.FlagSocket),
			fish = r(hud.Status.CatchCounter.Icon),
		}
		for name, rect in rects do
			t.ok(rect.x >= 0 and rect.x + rect.w <= vp.X, `{device}: {name} {fmt(rect)} inside the width`)
			t.ok(rect.y >= INSET and rect.y + rect.h <= vp.Y, `{device}: {name} {fmt(rect)} inside the height`)
		end
		for name, rect in decorations do
			t.ok(rect.x >= 0 and rect.x + rect.w <= vp.X, `{device}: {name} {fmt(rect)} on screen`)
			t.ok(rect.y >= INSET, `{device}: {name} below the top bar`)
		end
		-- No two chrome elements overlap.
		local names = {}
		for name in rects do
			table.insert(names, name)
		end
		table.sort(names)
		for i = 1, #names do
			for j = i + 1, #names do
				local a, b = rects[names[i]], rects[names[j]]
				t.eq(overlap(a, b), 0, `{device}: {names[i]} {fmt(a)} overlaps {names[j]} {fmt(b)}`)
			end
		end
		-- Decorations overhang their own pill, never the neighbours.
		t.eq(overlap(decorations.fish, badge, 1), 0, `{device}: the counter fish stays off the badge`)
		for name, rect in rects do
			if string.sub(name, 1, 5) == "toast" then
				t.eq(overlap(decorations.flag, rect), 0, `{device}: flag vs {name}`)
				t.eq(overlap(decorations.fish, rect), 0, `{device}: fish vs {name}`)
			end
		end
		-- Big enough to tap, above the Jump button on touch screens.
		t.ok(home.w >= 44 and home.h >= 44, `{device}: Home is at least 44 px ({fmt(home)})`)
		if device ~= "desktop" then
			local jumpTop = if vp.Y > 500 then vp.Y - 170 else vp.Y - 95
			t.ok(home.y + home.h <= jumpTop, `{device}: Home {fmt(home)} above the Jump button (y {jumpTop})`)
		end
		-- Readable text on a phone: the counter pill is at least 20 px tall.
		t.ok(counter.h >= 20, `{device}: counter {fmt(counter)} tall enough`)
	end
	sim:AssertNoErrors({ warnings = true })
end

tests["badge: base colour on the glossy face, darker lip, flag, bounce on assignment"] = function(t)
	local sim = boot(t)
	local p = sim:AddPlayer({ UserId = 1, Name = "Badge", device = "desktop" })
	sim:Advance(0.2)
	local badge = p.PlayerGui.HUD.Status.BaseBadge
	local color = p:GetAttribute("BaseColor")
	t.ok(typeof(color) == "Color3", "base assigned")
	t.eq(badge.Swatch.BackgroundColor3, color, "the face (Swatch) takes the base colour")
	local lip = badge.Lip.BackgroundColor3
	t.ok(lip.R <= color.R and lip.G <= color.G and lip.B <= color.B and lip ~= color, "darker lip")
	t.eq(badge.FlagSocket.Flag.Text, "🚩")
	t.ok(badge.FxScale.Scale < 1.2 and badge.FxScale.Scale ~= 1, "the badge bounces in")
	sim:Advance(2.5)
	t.near(badge.FxScale.Scale, 1, 1e-3, "and settles")
	local sparkles = 0
	for _, d in badge:GetDescendants() do
		if d.Name == "FxSparkle" then
			sparkles += 1
		end
	end
	t.eq(sparkles, 0, "celebration sparkles are gone")
	sim:AssertNoErrors({ warnings = true })
end

tests["strokes: thinner on a phone, thicker on a desktop (fitted to the screen height)"] = function(t)
	local sim = boot(t)
	local phone = addPlayer(sim, 1, "phone")
	local desktop = addPlayer(sim, 2, "desktop")
	local function lipStroke(p: any): any
		return p.PlayerGui.HUD.RightButtons.HomeButton.Lip:FindFirstChildOfClass("UIStroke")
	end
	t.ok(lipStroke(phone).Thickness < lipStroke(desktop).Thickness, "phone outline thinner")
	t.ok(lipStroke(phone).Thickness >= 1.5, "but still a real outline")
	t.eq(lipStroke(phone):GetAttribute("BaseThickness"), 3, "design value kept")
	-- Toasts cloned later are fitted too.
	notify(sim, phone, "Привет!", "info")
	sim:Advance(0.1)
	local toast = phone.PlayerGui.HUD.Toasts:FindFirstChild("Toast")
	t.eq(toast.Lip:FindFirstChildOfClass("UIStroke").Thickness, lipStroke(phone).Thickness)
	sim:AssertNoErrors({ warnings = true })
end

tests["catch counter: «+N» floats up when FishCaught grows, the fish wiggles"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	sim:Advance(5)
	local counter = p.PlayerGui.HUD.Status.CatchCounter
	p:SetAttribute("FishCaught", 1)
	sim:Advance(0.1)
	t.eq(counter.Visible, true, "FishingController shows the counter")
	t.eq(counter.Label.Text, "Улов: 1", "and writes the text")
	local float = counter:FindFirstChild("FxFloat")
	t.ok(float, "+1 floats over the counter")
	t.eq(float.Text, "+1")
	t.ok(counter.Icon.Rotation ~= -12, "the fish wiggles")
	p:SetAttribute("FishCaught", 3)
	sim:Advance(0.1)
	local texts = {}
	for _, c in counter:GetChildren() do
		if c.Name == "FxFloat" then
			table.insert(texts, c.Text)
		end
	end
	t.ok(table.find(texts, "+2"), "+2 for two fish at once")
	sim:Advance(1.5)
	t.eq(counter:FindFirstChild("FxFloat"), nil, "floats removed")
	t.near(counter.Icon.Rotation, -12, 1e-3, "the fish is back at rest")
	p:SetAttribute("FishCaught", 3)
	sim:Advance(0.1)
	t.eq(counter:FindFirstChild("FxFloat"), nil, "no float without a new catch")
	sim:AssertNoErrors({ warnings = true })
end

tests["Home: the cooldown veil drains with a countdown, then a ready ring"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	sim:Advance(1)
	local home = p.PlayerGui.HUD.RightButtons.HomeButton
	sim:Click(p, home)
	sim:Advance(0.1)
	t.eq(home.Cooldown.Visible, true)
	t.eq(home.CooldownText.Visible, true)
	t.eq(home.CooldownText.Text, tostring(math.ceil(BaseConfig.HomeCooldown)))
	local first = home.Cooldown.Drain.Offset.Y
	sim:Advance(1.2)
	local second = home.Cooldown.Drain.Offset.Y
	t.ok(second > first, `the veil drains ({first} → {second})`)
	t.eq(home.CooldownText.Text, tostring(math.ceil(BaseConfig.HomeCooldown) - 1), "counts down")
	-- A tap during the cooldown does not fire again (the button wiggles «no» instead).
	local before = #sim:ServerEventsFor(p, "RequestHome")
	sim:Click(p, home)
	sim:Advance(0.1)
	t.eq(#sim:ServerEventsFor(p, "RequestHome"), before, "no request during the cooldown")
	sim:Advance(BaseConfig.HomeCooldown)
	t.eq(home.Cooldown.Visible, false)
	t.eq(home.CooldownText.Visible, false)
	sim:Advance(1)
	t.eq(home:FindFirstChild("FxRing"), nil, "ready ring gone")
	t.near(home.FxScale.Scale, 1, 1e-3)
	sim:AssertNoErrors({ warnings = true })
end

tests["toasts: colour and icon by kind, width by text, slots, leave and reflow"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	sim:Advance(5) -- the join toast is gone
	local column = p.PlayerGui.HUD.Toasts
	local function live(): { any }
		local list = {}
		for _, c in column:GetChildren() do
			if c.Name == "Toast" then
				table.insert(list, c)
			end
		end
		table.sort(list, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		return list
	end
	notify(sim, p, "Ок", "success")
	sim:Advance(0.2)
	notify(
		sim,
		p,
		"Очень длинное уведомление, которое занимает всю ширину колонки",
		"danger"
	)
	sim:Advance(0.2)
	notify(sim, p, "Осторожно", "warning")
	sim:Advance(0.8)
	local toasts = live()
	t.eq(#toasts, 3)
	for i, kind in { "success", "danger", "warning" } do
		local style = UIConfig.ToastKinds[kind]
		local keys = toasts[i].Face.Fill.Color.Keypoints
		t.ok(colorNear(keys[1].Value, UIConfig.Palette[style.Token].Top), `{kind}: {style.Token} candy`)
		t.ok(colorNear(toasts[i].Lip.BackgroundColor3, UIConfig.Palette[style.Token].Lip), `{kind}: lip`)
		t.eq(toasts[i].IconSocket.Icon.Text, style.Icon, `{kind}: icon`)
		t.near(toasts[i].Position.Y.Scale, (i - 1) * 0.34, 1e-3, `{kind}: in slot {i}`)
		t.near(toasts[i].FxScale.Scale, 1, 1e-3, `{kind}: popped in`)
	end
	t.ok(toasts[1].Size.X.Scale < toasts[2].Size.X.Scale, "short text → narrower toast")
	t.near(toasts[2].Size.X.Scale, 1, 1e-6, "long text → full width")
	-- A fourth one pushes the oldest out; the rest move up.
	notify(sim, p, "Четвёртое", "info")
	sim:Advance(0.05)
	t.ok(column:FindFirstChild("ToastLeaving"), "the oldest is leaving")
	sim:Advance(0.6)
	t.eq(column:FindFirstChild("ToastLeaving"), nil, "and is gone")
	toasts = live()
	t.eq(#toasts, 3)
	t.near(toasts[1].Position.Y.Scale, 0, 1e-3, "the others moved up")
	t.eq(toasts[3].Label.Text, "Четвёртое")
	sim:Advance(UIConfig.ToastDuration + 1)
	t.eq(#live(), 0, "all toasts leave")
	local guis = 0
	for _, c in column:GetChildren() do
		if c:IsA("GuiObject") then
			guis += 1
		end
	end
	t.eq(guis, 1, "only the template is left")
	sim:AssertNoErrors({ warnings = true })
end

tests["idle HUD: no frame effects and no connection churn"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	sim:Advance(6)
	local UiFx = sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p)
	t.eq(UiFx.activeJobs(), 0, "nothing runs per frame while idle")
	local idle = sim:CountConnections(p)
	sim:Advance(10) -- several shine loops on the badge and Home
	t.eq(sim:CountConnections(p), idle, "the idle shine loops add no connections")
	-- A toast and a catch add no lasting connections either.
	notify(sim, p, "Привет!", "success")
	p:SetAttribute("FishCaught", 1)
	sim:Advance(6)
	t.eq(sim:CountConnections(p), idle, "back to the idle count")
	t.eq(UiFx.activeJobs(), 0)
	sim:AssertNoErrors({ warnings = true })
end

return tests
