--[[
	HUD chrome in the UI v5 «Симулятор» style (tools/builder/gui/Hud.luau + HudController +
	NotifyController) in RbxSim against the built Place1.rbxl:
	  • every contract name is still there (controllers and tests find widgets by name);
	  • the chrome is the reference's simulator look: sim plates and buttons (a Top → Bottom
	    gradient face, a thick outline in the dark shade of the hue on the Lip, a light rim inside,
	    a hidden Shine), outlined emoji, Montserrat Heavy text with thick outlines, the CAPS badge
	    «ЛАЗУРНАЯ БАЗА», the Wallet a panel-less italic money stat «💵 $1 234», the «САДОК» button
	    a square like Home with its «0/6» chip, the base banner a huge outlined title with a drop
	    shadow and no panel, the red «!» badges (hidden); and no stud anywhere in the GUI (the LEGO
	    look belongs to the map);
	  • the layout still fits on a phone, a tablet and a desktop: nothing overlaps, everything is
	    on screen, the right column («САДОК» over «ДОМОЙ») stays above the Jump button on touch
	    screens;
	  • stage 4 wave 3: on a PC the toast stack stops above the own fisher (the rest wait, UX-06),
	    a toast an alert pushed out early is dropped once it is stale (UX-05), a phone's broadcast
	    that would reach his head goes one line (ART-08);
	  • the runtime juice: base swatch on the badge and the base banner flying into it, the «САДОК»
	    chip (frozen while the HUD has CounterHold, rolling on arrival), the draining Home cooldown («ЖДИ»),
	    toasts by kind (colour, icon, width, slots, queue while fishing widgets are up — and while
	    a hit word or a minigame ghost rises into the column, Legendary / Mythic broadcasts), the
	    chip pointing at someone else's off-screen light pillar, the type scale (UiFx.fitText), no
	    frame connection at idle; the chrome stirs now and then (one widget at a time, only when
	    calm, timers only). The stage 3 HUD in depth (the Wallet's tick and floats, the stamps, the
	    sold / replaced flights, the onboarding «!»): stage3_hud.test.luau.

	The sim ignores UIListLayout alignment, so this file computes rectangles itself (rectOf).

	Run: lune run tools/run_tests.luau hud_style
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Enum = roblox.Enum
local Color3 = roblox.Color3
local Vector3 = roblox.Vector3

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

local function liveToasts(p: any): { any }
	local list = {}
	for _, c in p.PlayerGui.HUD.Toasts:GetChildren() do
		if c.Name == "Toast" then
			table.insert(list, c)
		end
	end
	table.sort(list, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	return list
end

local function colorNear(a: any, b: any, eps: number?): boolean
	local e = eps or 0.01
	return math.abs(a.R - b.R) <= e and math.abs(a.G - b.G) <= e and math.abs(a.B - b.B) <= e
end

-- A sim face's Top colour: the first keypoint of its Top → Bottom "Fill".
local function capTop(fill: any): any
	return fill.Color.Keypoints[1].Value
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

-- Sim check ----------------------------------------------------------------------------------

-- A sim plate / button (Theme.sim): the Lip carries the thick outline (no fill) in the swatch's
-- dark shade, the face covers the root with a Top → Bottom "Fill", a light Rim inside, a hidden
-- Shine; a smooth surface: nothing raised, no glint, no side band.
local function checkSim(t: any, root: any, token: string?, what: string)
	local faceName = root:GetAttribute("CandyFace")
	t.ok(type(faceName) == "string", `{what}: CandyFace attribute`)
	t.eq(root:GetAttribute("CandyStyle"), "sim", `{what}: a sim plate`)
	local lip = root:FindFirstChild("Lip")
	local face = root:FindFirstChild(faceName)
	t.ok(lip and lip:IsA("Frame"), `{what}: Lip`)
	t.ok(face and face:IsA("Frame"), `{what}: face {faceName}`)
	t.ok(lip.ZIndex < face.ZIndex, `{what}: the outline is behind the face`)
	t.eq(lip.BackgroundTransparency, 1, `{what}: the Lip draws no band`)
	t.eq(face.Size.Y.Scale, 1, `{what}: the face covers the root (no side band)`)
	local outline = lip:FindFirstChildOfClass("UIStroke")
	t.ok(outline, `{what}: the outline is on the Lip`)
	t.ok(outline:GetAttribute("BaseThickness") >= 5, `{what}: a thick outline (5–6 at 720)`)
	t.ok(colorNear(outline.Color, lip.BackgroundColor3), `{what}: the outline in the swatch's dark shade`)
	t.ok(not colorNear(outline.Color, UIConfig.Ink) or token == nil, `{what}: not a neutral black outline`)
	local fill = face:FindFirstChild("Fill")
	t.ok(fill and fill:IsA("UIGradient"), `{what}: Fill gradient`)
	t.eq(fill.Rotation, 90, `{what}: vertical gradient`)
	local keys = fill.Color.Keypoints
	t.eq(#keys, 2, `{what}: light top → saturated bottom`)
	if token then
		local look = UIConfig.Palette[token]
		t.ok(colorNear(capTop(fill), look.Top), `{what}: {token} top`)
		t.ok(colorNear(keys[#keys].Value, look.Bottom), `{what}: {token} bottom`)
		t.ok(colorNear(lip.BackgroundColor3, look.Lip), `{what}: {token} outline colour`)
	end
	local rim = face:FindFirstChild("Rim")
	local ring = rim and rim:FindFirstChildOfClass("UIStroke")
	t.ok(ring and colorNear(ring.Color, Color3.new(1, 1, 1)), `{what}: a light rim inside the outline`)
	t.eq(face:FindFirstChild("Spec"), nil, `{what}: no brick glint`)
	t.eq(root:FindFirstChild("Studs"), nil, `{what}: no studs`)
	local shine = face:FindFirstChild("Shine")
	t.ok(shine and shine:FindFirstChild("Band"), `{what}: Shine overlay with its Band`)
	t.ok(shine:FindFirstChildOfClass("UICorner"), `{what}: the shine follows the rounded corners`)
	t.ok(math.abs(shine.Band.Offset.X) >= 1, `{what}: the band waits out of sight`)
end

-- A guard: nothing stud-like may be built under root (the GUI is smooth; the LEGO look belongs
-- to the map).
local function studsUnder(root: any): { string }
	local found = {}
	for _, d in root:GetDescendants() do
		local name = d.Name
		if
			string.match(name, "^Stud%d*$")
			or d:GetAttribute("CandyStud") ~= nil
			or name == "Spec"
			or ((string.match(name, "^Studs") ~= nil or name == "StudRow") and #d:GetChildren() > 0)
		then
			table.insert(found, d:GetFullName())
		end
	end
	return found
end

local tests = {}

tests["names: every widget the controllers and tests use is still there"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	local paths = {
		"Status.BaseBadge.Swatch",
		"Status.BaseBadge.Label",
		"Status.BaseBadge.FlagSocket.Flag",
		"Status.Wallet.Money.Icon",
		"Status.Wallet.Money.Label",
		"Status.Wallet.Money.Back",
		"Status.Wallet.Rate",
		"RightButtons.TankButton.Icon",
		"RightButtons.TankButton.Caption",
		"RightButtons.TankButton.Count.Label",
		"RightButtons.TankButton.Badge.Mark",
		"RightButtons.HomeButton.Icon",
		"RightButtons.HomeButton.Caption",
		"RightButtons.HomeButton.Cooldown",
		"Toasts.ToastTemplate.Label",
		"Toasts.ToastTemplate.IconSocket.Icon",
		"RightButtons.HomeButton.CooldownText",
		"BaseBanner.Caption",
		"BaseBanner.NameLabel",
		"BaseBanner.FlagSocket.Flag",
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
		"Fishing.CatchCard.TankStamp.Label",
		-- Stage 4 (docs/stage4_design.md §6.1; built hidden in wave 0, driven in wave 2)
		"Status.BaseBadge.ShieldChip.Icon",
		"Status.BaseBadge.ShieldChip.Label",
		"RightButtons.DefenceButton.Icon",
		"RightButtons.DefenceButton.Caption",
		"RightButtons.DefenceButton.Badge.Mark",
		"RightButtons.DefenceButton.Cooldown.Drain",
		"RightButtons.DefenceButton.CooldownText",
		"TheftBar.Plate",
		"TheftBar.Icon.Icon",
		"TheftBar.Title",
		"TheftBar.Bar.Track",
		"TheftBar.Bar.Fill",
		"TheftBar.Time",
		"TheftBar.Sub",
		"TheftBar.DogChip.Label",
		"TheftTitle.Title",
		"TheftTitle.Sub",
		"TheftAlert.Plate",
		"TheftAlert.Icon.Icon",
		"TheftAlert.Text.Title",
		"TheftAlert.Text.Sub",
		"TheftAlert.Buttons.Shield.Icon",
		"TheftAlert.Buttons.Shield.Caption",
		"TheftAlert.Buttons.Home.Icon",
		"TheftAlert.Buttons.Home.Caption",
		"TheftAlert.Compact.Label",
		"TheftAlert.Compact.Shield",
		"TheftAlert.Compact.Home",
		"DefencePanel.Panel.Strip",
		"DefencePanel.Panel.Header.Icon",
		"DefencePanel.Panel.Header.Title",
		"DefencePanel.Panel.Header.Money.Label",
		"DefencePanel.Panel.Close",
	}
	for _, card in { "ShieldCard", "DogCard", "AlarmCard", "LockCard" } do
		for _, part in { "Icon.Emoji", "Name", "Effect", "State", "Buy.Label", "Buy.Price" } do
			table.insert(paths, `DefencePanel.Panel.Cards.{card}.{part}`)
		end
	end
	for _, path in paths do
		t.ok(sim:Gui(p, `HUD.{path}`), `HUD.{path}`)
	end
	-- Stage 4 roots are built hidden: nothing changes on screen until their controllers run.
	for _, path in
		{
			"Status.BaseBadge.ShieldChip",
			"RightButtons.DefenceButton",
			"TheftBar",
			"TheftTitle",
			"TheftAlert",
			"TheftAlert.Compact",
			"DefencePanel",
		}
	do
		t.eq(sim:Gui(p, `HUD.{path}`).Visible, false, `HUD.{path} hidden`)
	end
	t.ok(sim:Gui(p, "HUD.RightButtons.DefenceButton"):IsA("GuiButton"), "«ЗАЩИТА» is a button")
	t.eq(sim:Gui(p, "HUD.RightButtons.DefenceButton").LayoutOrder, 80, "«ЗАЩИТА» above «САДОК» (90)")
	t.ok(sim:Gui(p, "HUD.TheftAlert.Buttons.Shield"):IsA("GuiButton"), "ЩИТ is a button")
	t.ok(sim:Gui(p, "HUD.DefencePanel.Panel.Cards.DogCard.Buy"):IsA("GuiButton"), "a card's Buy is a button")
	t.ok(sim:Gui(p, "HUD.RightButtons.HomeButton"):IsA("GuiButton"), "Home is a button")
	t.ok(sim:Gui(p, "HUD.RightButtons.TankButton"):IsA("GuiButton"), "«САДОК» is a button")
	t.eq(p.PlayerGui.HUD.Status:FindFirstChild("CatchCounter"), nil, "stage 3: no catch counter")
	t.ok(sim:Gui(p, "HUD.Status.BaseBadge.Label"):IsA("TextLabel"))
	sim:AssertNoErrors({ warnings = true })
end

tests["sim: badge, Wallet (stat), «САДОК», Home, banner (title), toasts — the reference's look, no studs"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	local hud = p.PlayerGui.HUD
	checkSim(t, hud.Status.BaseBadge, nil, "BaseBadge")
	t.eq(hud.Status.BaseBadge:GetAttribute("CandyFace"), "Swatch", "the badge face is the Swatch")
	t.eq(hud.Status.BaseBadge:GetAttribute("CandyRadius"), UIConfig.Sim.PlateRadius, "a label plate")
	t.eq(hud.Status.BaseBadge.FlagSocket.BackgroundTransparency, 1, "the flag holder draws nothing")
	checkSim(t, hud.RightButtons.HomeButton, "Grape", "HomeButton")
	t.eq(hud.RightButtons.HomeButton:GetAttribute("CandyRadius"), UIConfig.Sim.Radius, "a chunky square button")
	t.ok(hud.RightButtons.HomeButton:FindFirstChildOfClass("UIAspectRatioConstraint"), "… square")
	checkSim(t, hud.RightButtons.TankButton, "Water", "TankButton")
	t.eq(
		hud.RightButtons.TankButton:GetAttribute("CandyRadius"),
		UIConfig.Sim.Radius,
		"«САДОК»: the Home recipe"
	)
	t.ok(hud.RightButtons.TankButton:FindFirstChildOfClass("UIAspectRatioConstraint"), "… square")
	local chip = hud.RightButtons.TankButton.Count
	t.eq(chip:GetAttribute("CandyStyle"), "sim", "the «0/6» chip is a sim plate")
	t.ok(colorNear(capTop(chip[chip:GetAttribute("CandyFace")].Fill), UIConfig.Palette.Cream.Top), "… Cream")
	t.ok(colorNear(chip.Label.TextColor3, UIConfig.Ink), "… dark digits")
	t.eq(chip.Label.FontFace.Style, Enum.FontStyle.Italic, "… italic")
	t.ok(chip.Label.TextSize >= 12 or chip.Label.TextScaled, "… readable")
	checkSim(t, hud.Toasts.ToastTemplate, "Sky", "ToastTemplate")
	checkSim(t, hud.TrophyPointer.Body, "Gold", "TrophyPointer.Body")
	t.eq(hud.TrophyPointer.Body:GetAttribute("CandyRadius"), 0.5, "a round chip")
	-- The Wallet: a panel-less stat like the reference's «$0» (no plate behind the number), the
	-- money green with the thick Ink outline; the rate a smaller italic green label after it.
	local money = hud.Status.Wallet.Money
	t.eq(money:GetAttribute("CandyFace"), nil, "no panel behind the money")
	t.eq(money:FindFirstChild("Lip"), nil)
	t.eq(money.Label.FontFace.Style, Enum.FontStyle.Italic, "a big italic number")
	t.eq(money.Label.TextXAlignment, Enum.TextXAlignment.Left, "… right of its icon")
	t.ok(colorNear(money.Label.TextColor3, UIConfig.MoneyText), "… in the money green")
	t.eq(money.Label.FontFace.Weight, Enum.FontWeight.Heavy, "… Montserrat Heavy")
	t.ok(colorNear(money.Label.Outline.Color, UIConfig.Ink), "… with an Ink outline")
	t.ok(money.Label.Outline:GetAttribute("BaseThickness") >= 2.5, "… a thick one")
	t.eq(money.Back.Visible, false, "the «$…» glass is hidden while the data is there")
	t.eq(money.Back:GetAttribute("CandyStyle"), "glass", "… a glass pill")
	local rate = hud.Status.Wallet.Rate
	t.eq(rate.FontFace.Style, Enum.FontStyle.Italic, "the rate in italics")
	t.ok(colorNear(rate.TextColor3, UIConfig.MoneyText), "… green too")
	t.eq(rate:GetAttribute("TextTier"), "Button", "… at the Button tier")
	-- The banner: the reference's huge outlined title, no panel, a drop-shadow twin.
	local banner = hud.BaseBanner
	t.eq(banner:GetAttribute("CandyFace"), nil, "no panel behind the banner")
	t.eq(banner:FindFirstChild("Lip"), nil)
	t.ok(banner.NameLabel.Outline:GetAttribute("BaseThickness") >= 7, "a thick title outline")
	local shadow = banner:FindFirstChild("NameLabelShadow")
	t.ok(shadow and shadow:GetAttribute("ShadowOf") == "NameLabel", "a drop shadow under the name")
	t.ok(shadow.ZIndex < banner.NameLabel.ZIndex)
	-- The red «!» badge of the reference sits on Home's corner, hidden until the shop stage.
	local badge = hud.RightButtons.HomeButton:FindFirstChild("Badge")
	t.ok(badge and badge.Visible == false, "a hidden «!» badge on Home")
	t.eq(badge.Mark.Text, "!")

	-- Text: white Montserrat Heavy with a thick Ink outline (at least its tier's); CAPS on the chrome.
	for _, label in
		{
			hud.Status.BaseBadge.Label,
			hud.RightButtons.TankButton.Caption,
			hud.RightButtons.HomeButton.Caption,
			hud.Toasts.ToastTemplate.Label,
			hud.BaseBanner.NameLabel,
		}
	do
		t.ok(colorNear(label.TextColor3, Color3.new(1, 1, 1)), `{label:GetFullName()}: white text`)
		t.eq(label.FontFace.Weight, Enum.FontWeight.Heavy, `{label:GetFullName()}: Montserrat Heavy`)
		t.ok(string.find(label.FontFace.Family, "Montserrat", 1, true) ~= nil, `{label:GetFullName()}: Montserrat`)
		local outline = label:FindFirstChild("Outline")
		t.ok(outline and outline:IsA("UIStroke"), `{label:GetFullName()}: outlined`)
		t.eq(outline.ApplyStrokeMode, Enum.ApplyStrokeMode.Contextual)
		t.ok(colorNear(outline.Color, UIConfig.Ink), `{label:GetFullName()}: an Ink outline`)
		t.ok(outline:GetAttribute("BaseThickness") >= 2.5, `{label:GetFullName()}: a thick outline`)
		local lip = label.Parent:FindFirstChild("Lip")
		if lip then
			t.ok(label.ZIndex > lip.ZIndex + 1, `{label:GetFullName()}: above the face`)
		end
	end
	local TextUtil = sim:Require(sim:Find("ReplicatedStorage.Shared.TextUtil"), p)
	local badgeText = hud.Status.BaseBadge.Label.Text
	t.eq(badgeText, TextUtil.upper(badgeText), "the badge in CAPS")
	t.eq(money.Icon.Text, "💵")
	t.eq(hud.RightButtons.TankButton.Icon.Text, "🐠")
	t.eq(hud.RightButtons.TankButton.Caption.Text, "САДОК")
	t.eq(hud.RightButtons.HomeButton.Icon.Text, "🏠")
	-- Icons: emoji with a dark Ink contour, like the reference's black-outlined icons.
	for _, icon in
		{
			money.Icon,
			hud.RightButtons.TankButton.Icon,
			hud.RightButtons.HomeButton.Icon,
			hud.Status.BaseBadge.FlagSocket.Flag,
		}
	do
		local outline = icon:FindFirstChild("Outline")
		t.ok(outline and colorNear(outline.Color, UIConfig.Ink), `{icon:GetFullName()}: an Ink contour`)
		t.eq(icon:FindFirstChild("Sticker"), nil, `{icon:GetFullName()}: no white sticker rim`)
	end
	t.eq(hud.RightButtons.HomeButton.Icon.Rotation, 0, "the house is upright")
	t.ok(hud.Toasts.ToastTemplate.IconSocket.Icon, "icon holder on toasts")
	t.eq(hud.Toasts.ToastTemplate.IconSocket.BackgroundTransparency, 1, "… no white disc behind it")
	t.ok(hud.RightButtons.HomeButton.Cooldown:FindFirstChild("Drain"), "draining cooldown veil")
	t.ok(hud.RightButtons.HomeButton.Cooldown.ZIndex > hud.RightButtons.HomeButton.Caption.ZIndex)
	-- «ДОМОЙ» sits ON the button's bottom edge (no ribbon); text tiers are set.
	t.eq(hud.RightButtons.HomeButton:FindFirstChild("CaptionRibbon"), nil, "no caption ribbon")
	t.ok(hud.RightButtons.HomeButton.Caption.Position.Y.Scale >= 0.8, "the caption on the bottom edge")
	t.eq(hud.RightButtons.HomeButton.Caption:GetAttribute("TextTier"), "Small")
	t.eq(hud.Status.BaseBadge.Label:GetAttribute("TextTier"), "Title")
	t.eq(hud.Toasts.ToastTemplate.Label:GetAttribute("TextTier"), "Body")
	-- The Wallet is a currency display: its number is box-driven, at least the Title tier.
	local number = money.Label
	t.eq(number:GetAttribute("TextTier"), nil, "the Wallet's number is display text")
	t.ok(number:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize > UIConfig.Type.Title, "… big")
	-- No stud anywhere in the GUI (HUD chrome and the fishing widgets): the map keeps them.
	local studs = studsUnder(hud)
	t.eq(#studs, 0, `no studs in the GUI ({table.concat(studs, ", ")})`)
	-- One UIStroke per GuiObject (Roblox draws only one reliably; SIM-C1-01: a second, disabled
	-- "Outline" on the action icon shadowed the real one and the controller switched that off).
	local doubled = {}
	for _, d in hud:GetDescendants() do
		if d:IsA("GuiObject") then
			local strokes = 0
			for _, c in d:GetChildren() do
				if c:IsA("UIStroke") then
					strokes += 1
				end
			end
			if strokes > 1 then
				table.insert(doubled, d:GetFullName())
			end
		end
	end
	t.eq(#doubled, 0, `at most one UIStroke per GUI object ({table.concat(doubled, ", ")})`)
	for _, d in hud:GetDescendants() do
		local style = d:GetAttribute("CandyStyle")
		if style ~= nil then
			t.ok(style == "sim" or style == "glass", `{d:GetFullName()}: a sim or glass look ({style})`)
		end
	end
	local UiFx = sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p)
	t.eq(UiFx.setStuds, nil, "UiFx.setStuds is gone")
	t.eq(UiFx.paintStuds, nil, "UiFx.paintStuds is gone")
	t.eq(UiFx.studsPop, nil, "UiFx.studsPop is gone")
	-- Shine overlays are hidden until a sweep (no full-size quad drawn every frame).
	sim:Advance(6) -- the join celebration is over
	for _, d in hud:GetDescendants() do
		if d.Name == "Shine" and d:IsA("Frame") and not d:IsDescendantOf(hud.Fishing) then
			t.eq(d.Visible, false, `{d:GetFullName()} hidden at rest`)
		end
	end
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
		p:SetAttribute("Money", 123456) -- a long Wallet row
		p:SetAttribute("Income", 1234)
		p:SetAttribute("TankCount", 4)
	end
	sim:WaitFor(function() -- the base banners have flown into the badges, the Wallet and «САДОК» are in
		for _, device in devices do
			local hud = players[device].PlayerGui.HUD
			if not (hud.Status.Wallet.Visible and hud.RightButtons.TankButton.Visible) then
				return false
			end
		end
		return true
	end, 10)
	sim:Advance(1)
	for _, device in devices do
		local p = players[device]
		notify(sim, p, "Вася: мифическая рыба «Рыба-дракон» ×5!", "Mythic")
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
		local money = r(hud.Status.Wallet.Money)
		local rate = r(hud.Status.Wallet.Rate)
		local tank = r(hud.RightButtons.TankButton)
		local home = r(hud.RightButtons.HomeButton)
		t.ok(hud.Status.Wallet.Visible, `{device}: Wallet shown`)
		t.ok(hud.Status.Wallet.Rate.Visible, `{device}: the rate shown (income > 0)`)
		t.ok(hud.RightButtons.TankButton.Visible, `{device}: «САДОК» shown`)
		t.ok(hud.RightButtons.HomeButton.Visible, `{device}: Home shown`)
		local toasts = {}
		for _, c in hud.Toasts:GetChildren() do
			if c.Name == "Toast" then
				table.insert(toasts, c)
			end
		end
		local cap = if device == "desktop"
			then UIConfig.MaxToasts
			elseif device == "phone" then UIConfig.MaxToastsPhone
			else UIConfig.MaxToastsTouch
		t.eq(#toasts, cap, `{device}: {cap} toasts (the device cap)`)

		local rects: { [string]: Rect } = { badge = badge, money = money, rate = rate, tank = tank, home = home }
		for i, toast in toasts do
			rects[`toast{i}`] = r(toast)
		end
		-- Everything on screen, below the top bar.
		local decorations = {
			flag = r(hud.Status.BaseBadge.FlagSocket),
			bill = r(hud.Status.Wallet.Money.Icon),
			chip = r(hud.RightButtons.TankButton.Count),
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
		t.eq(overlap(decorations.bill, badge, 1), 0, `{device}: the Wallet's 💵 stays off the badge`)
		for name, rect in rects do
			if string.sub(name, 1, 5) == "toast" then
				t.eq(overlap(decorations.flag, rect), 0, `{device}: flag vs {name}`)
				t.eq(overlap(decorations.bill, rect), 0, `{device}: 💵 vs {name}`)
			end
		end
		-- The «0/6» chip stays inside its button's outline (nothing of it sticks out of the column;
		-- on a phone its 40 px minimum may reach a pixel or two into the outline).
		local chip = decorations.chip
		local edge = 3
		t.ok(
			chip.x >= tank.x - edge and chip.y >= tank.y - edge and chip.x + chip.w <= tank.x + tank.w + edge,
			`{device}: the chip {fmt(chip)} inside «САДОК» {fmt(tank)}`
		)
		t.ok(chip.h >= 20, `{device}: the chip {fmt(chip)} big enough for «12/12» at 12 px`)
		-- Big enough to tap, «САДОК» over «ДОМОЙ», above the Jump button on touch screens.
		t.ok(home.w >= 44 and home.h >= 44, `{device}: Home is at least 44 px ({fmt(home)})`)
		t.ok(tank.w >= 44 and tank.h >= 44, `{device}: «САДОК» is at least 44 px ({fmt(tank)})`)
		t.ok(tank.y + tank.h <= home.y, `{device}: «САДОК» {fmt(tank)} above Home {fmt(home)}`)
		if device ~= "desktop" then
			local jumpTop = if vp.Y > 500 then vp.Y - 170 else vp.Y - 95
			t.ok(home.y + home.h <= jumpTop, `{device}: Home {fmt(home)} above the Jump button (y {jumpTop})`)
		end
		-- Readable money on a phone: the number's row is at least 20 px tall.
		t.ok(money.h >= 20, `{device}: Wallet {fmt(money)} tall enough`)
	end
	sim:AssertNoErrors({ warnings = true })
end

-- Stage 4 wave 0: the hidden widgets, shown by hand here (their controllers come in wave 2),
-- fit where docs/stage4_design.md §6.9 puts them: «ЗАЩИТА» is the column's third square above
-- «САДОК», the shield chip fits beside the badge, ЩИТ is the alert's largest target.
tests["stage 4: «ЗАЩИТА» is the column's third square; the shield chip and ЩИТ keep their sizes"] = function(
	t
)
	local sim = boot(t)
	local devices = { "phone", "tablet", "desktop" }
	local players = {}
	for i, device in devices do
		players[device] = addPlayer(sim, i, device)
	end
	sim:WaitFor(function()
		for _, device in devices do
			local hud = players[device].PlayerGui.HUD
			if not (hud.Status.Wallet.Visible and hud.RightButtons.TankButton.Visible) then
				return false
			end
		end
		return true
	end, 10)
	sim:Advance(1)
	local THEFT = UIConfig.Theft
	for _, device in devices do
		local p = players[device]
		local hud = p.PlayerGui.HUD
		local vp = sim.players.state[sim:Unwrap(p)].viewport
		hud.RightButtons.DefenceButton.Visible = true
		hud.Status.BaseBadge.ShieldChip.Visible = true
		hud.TheftAlert.Visible = true
		sim:Advance(0.1)
		local function r(gui: any): Rect
			return rectOf(sim, p, gui)
		end
		local defence, tank, home =
			r(hud.RightButtons.DefenceButton), r(hud.RightButtons.TankButton), r(hud.RightButtons.HomeButton)
		local badge, money, chip =
			r(hud.Status.BaseBadge), r(hud.Status.Wallet.Money), r(hud.Status.BaseBadge.ShieldChip)
		t.ok(defence.w >= 44 and defence.h >= 44, `{device}: «ЗАЩИТА» at least 44 px ({fmt(defence)})`)
		t.ok(
			defence.y + defence.h <= tank.y,
			`{device}: «ЗАЩИТА» {fmt(defence)} above «САДОК» {fmt(tank)}`
		)
		t.ok(tank.y + tank.h <= home.y, `{device}: «САДОК» still above Home`)
		t.ok(
			defence.y >= INSET and defence.x + defence.w <= vp.X,
			`{device}: «ЗАЩИТА» {fmt(defence)} on screen`
		)
		t.ok(math.abs(defence.w - tank.w) < 1, `{device}: the same square as «САДОК»`)
		for name, rect in { badge = badge, money = money, chip = chip } do
			t.eq(overlap(defence, rect), 0, `{device}: «ЗАЩИТА» {fmt(defence)} clear of the {name} {fmt(rect)}`)
		end
		t.ok(chip.w <= THEFT.ChipMax + 0.5, `{device}: the shield chip {fmt(chip)} ≤ {THEFT.ChipMax} px wide`)
		t.ok(chip.x > badge.x + badge.w / 2, `{device}: the chip {fmt(chip)} at the badge's right end {fmt(badge)}`)
		t.ok(chip.x + chip.w <= vp.X and chip.y >= INSET, `{device}: the chip on screen`)
		local alert = r(hud.TheftAlert)
		local shield, alertHome = r(hud.TheftAlert.Buttons.Shield), r(hud.TheftAlert.Buttons.Home)
		t.ok(alert.w <= THEFT.WidthMax + 0.5, `{device}: the alert {fmt(alert)} ≤ {THEFT.WidthMax} px wide`)
		t.ok(shield.h >= THEFT.ShieldMin - 0.5, `{device}: ЩИТ {fmt(shield)} ≥ {THEFT.ShieldMin} px tall`)
		t.ok(
			shield.w >= THEFT.ShieldShare * alert.w - 0.5,
			`{device}: ЩИТ {fmt(shield)} ≥ {THEFT.ShieldShare} of the plate {fmt(alert)}`
		)
		t.ok(
			alertHome.w >= THEFT.HomeMin and alertHome.h >= THEFT.HomeMin,
			`{device}: ДОМОЙ {fmt(alertHome)} ≥ 44 px`
		)
		t.ok(shield.w * shield.h > alertHome.w * alertHome.h, `{device}: ЩИТ is the plate's largest target`)
		t.eq(overlap(shield, alertHome), 0, `{device}: ЩИТ and ДОМОЙ apart`)
		hud.RightButtons.DefenceButton.Visible = false
		hud.Status.BaseBadge.ShieldChip.Visible = false
		hud.TheftAlert.Visible = false
	end
	sim:AssertNoErrors({ warnings = true })
end

-- The base's clean swatch (UIConfig.BaseSwatches by the base's colour Id).
local function swatchOf(p: any): any
	local name = p:GetAttribute("BaseColorName")
	for _, entry in BaseConfig.Colors do
		if entry.Name == name then
			return UIConfig.BaseSwatches[entry.Id]
		end
	end
	return nil
end

tests["badge: base swatch on the glossy face; the base banner pops up, then flies into the badge"] = function(t)
	local sim = boot(t)
	local p = sim:AddPlayer({ UserId = 1, Name = "Badge", device = "desktop" })
	sim:Advance(0.2)
	local hud = p.PlayerGui.HUD
	local badge = hud.Status.BaseBadge
	t.ok(typeof(p:GetAttribute("BaseColor")) == "Color3", "base assigned")
	local swatch = swatchOf(p)
	t.ok(swatch, "a swatch for every base colour")
	local keys = badge.Swatch.Fill.Color.Keypoints
	t.ok(colorNear(capTop(badge.Swatch.Fill), swatch.Top), "the face takes the swatch top")
	t.ok(colorNear(keys[#keys].Value, swatch.Bottom), "… and bottom (no grey tint)")
	t.ok(colorNear(badge.Lip.BackgroundColor3, swatch.Lip), "the swatch's outline colour")
	t.ok(colorNear(badge.Lip:FindFirstChildOfClass("UIStroke").Color, swatch.Lip), "… on the outline itself")
	t.eq(badge.Swatch.BackgroundColor3, Color3.new(1, 1, 1), "white face under the gradient")
	t.eq(badge.FlagSocket.Flag.Text, "🚩")
	local name = p:GetAttribute("BaseColorName")
	local caps = sim:Require(sim:Find("ReplicatedStorage.Shared.TextUtil"), p).upper(name)
	t.eq(badge.Label.Text, `{caps} БАЗА`, "the base name in CAPS")
	-- The banner: centre of the screen, in the same swatch, the name in capitals.
	local banner = hud.BaseBanner
	t.eq(banner.Visible, true, "the base banner is up")
	t.eq(banner.Caption.Text, "ТВОЯ БАЗА")
	t.ok(string.find(banner.NameLabel.Text, "!", 1, true), "big name with «!»")
	t.eq(banner.NameLabelShadow.Text, banner.NameLabel.Text, "the drop shadow follows the name")
	local nameKeys = banner.NameLabel.TextFill.Color.Keypoints
	t.ok(colorNear(nameKeys[#nameKeys].Value, swatch.Bottom), "the name in the base colours")
	t.ok(banner:FindFirstChild("FxRays"), "rays behind the banner")
	t.eq(banner.FxRays:FindFirstChild("Halo1"), nil, "banner rays without halo quads")
	sim:Advance(2.1)
	t.ok(banner.Visible, "still there, flying towards the badge")
	t.ok(banner.FxScale.Scale < 1, "shrinking on the way")
	for _ = 1, 30 do -- lands ~2.4 s after the assignment
		if not banner.Visible then
			break
		end
		sim:Advance(1 / 30)
	end
	t.eq(banner.Visible, false, "landed in the badge")
	t.eq(banner:FindFirstChild("FxRays"), nil, "its rays are gone")
	t.ok(badge.FxScale.Scale > 1, "the badge bumps when the banner lands")
	sim:Advance(2)
	t.near(badge.FxScale.Scale, 1, 1e-3, "and settles")
	t.near(banner.FxScale.Scale, 1, 1e-3, "the banner is reset for next time")
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
		return p.PlayerGui.HUD.Status.BaseBadge.Lip:FindFirstChildOfClass("UIStroke")
	end
	t.ok(lipStroke(phone).Thickness < lipStroke(desktop).Thickness, "phone outline thinner")
	t.ok(lipStroke(phone).Thickness >= 3, "but still a thick outline (≈ 4 px)")
	t.eq(lipStroke(phone):GetAttribute("BaseThickness"), UIConfig.Sim.Stroke, "design value kept")
	t.ok(lipStroke(desktop).Thickness <= UIConfig.Sim.Stroke * UIConfig.Fx.StrokeMax, "capped on big screens")
	-- Toasts cloned later are fitted too.
	notify(sim, phone, "Привет!", "info")
	sim:Advance(0.1)
	local toast = phone.PlayerGui.HUD.Toasts:FindFirstChild("Toast")
	t.eq(toast.Lip:FindFirstChildOfClass("UIStroke").Thickness, lipStroke(phone).Thickness)
	-- Text outlines never go below 2 px (white on Gold/Leaf/Sun reads only thanks to them).
	t.ok(phone.PlayerGui.HUD.Status.Wallet.Money.Label.Outline.Thickness >= 2, "text outline floor 2 px")
	t.ok(toast.Label.Outline.Thickness >= 2, "… also on toasts cloned later")
	sim:AssertNoErrors({ warnings = true })
end

tests["type scale: tiered labels share one size per tier, scaled from phone to desktop"] = function(t)
	local sim = boot(t)
	local phone = addPlayer(sim, 1, "phone")
	local desktop = addPlayer(sim, 2, "desktop")
	local function limits(label: any): (number, number)
		local c = label:FindFirstChildOfClass("UITextSizeConstraint")
		return c.MinTextSize, c.MaxTextSize
	end
	local function check(p: any, height: number, device: string)
		local hud = p.PlayerGui.HUD
		local k = math.clamp(height / UIConfig.TypeHeight, 1, UIConfig.TypeMaxScale)
		for _, case in
			{
				{ hud.Status.BaseBadge.Label, "Title" },
				{ hud.RightButtons.HomeButton.Caption, "Small" },
				{ hud.Toasts.ToastTemplate.Label, "Body" },
				{ hud.BaseBanner.Caption, "Button" },
			}
		do
			local want = math.floor(UIConfig.Type[case[2]] * k + 0.5)
			local lo, hi = limits(case[1])
			t.eq(hi, want, `{device}: {case[1]:GetFullName()} {case[2]} max`)
			t.eq(lo, want - 2, `{device}: … min = max - 2`)
		end
	end
	check(phone, 390, "phone")
	check(desktop, 720, "desktop")
	-- A big broadcast toast cloned later: «кто» (Byline) at the Small size but never under 14 px
	-- (v3, UIM-06), «что» (Label) sized by its box between Body and Title (on a phone Title − 2:
	-- both lines end above the avatar's head).
	notify(sim, phone, "Рыбак: легендарная рыба «Акулёнок»!", "Legendary")
	sim:Advance(0.1)
	local toast = liveToasts(phone)[1]
	t.eq(toast.Byline:GetAttribute("TextTier"), nil, "the byline has its own floor")
	local bylineMin, bylineMax = limits(toast.Byline)
	t.eq(bylineMax, UIConfig.Type.Small, "phone Small size on the byline")
	t.ok(bylineMin >= 14, `… never under 14 px ({bylineMin})`)
	t.eq(toast.Label:GetAttribute("TextTier"), nil, "the headline is box-driven")
	local lo, hi = limits(toast.Label)
	t.eq(hi, UIConfig.Type.Title - 2, "phone: the headline up to Title − 2")
	t.eq(lo, UIConfig.Type.Body, "… never under Body")
	sim:AssertNoErrors({ warnings = true })
end

-- The «САДОК» button of a fresh player, once it has popped in after the base banner.
local function tankButtonOf(sim: any, p: any): any
	local button = p.PlayerGui.HUD.RightButtons.TankButton
	sim:WaitFor(function()
		return button.Visible
	end, 10)
	sim:Advance(1.5) -- (its pop-in, delayed after the Wallet's, is over)
	return button
end

tests["«САДОК» chip: a fish stored without a card rolls «N/6»; a full tank turns it gold"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	local button = tankButtonOf(sim, p)
	local chip = button.Count
	local restTilt = button.Icon.Rotation
	t.eq(chip.Label.Text, `0/{p:GetAttribute("TankSlots")}`, "the chip reads the attributes")
	-- Stage 4 "Stored" (no catch card): the same arrival, a beat after the attribute.
	p:SetAttribute("TankCount", 1)
	sim:Advance(0.1)
	t.eq(chip.Label.Text, "0/6", "a beat later (a «Caught» may still follow the attribute)")
	sim:Advance(UIConfig.TankButton.StoredWait + 0.05)
	t.eq(chip.Label.Text, "1/6", "the new count")
	local ghost = chip:FindFirstChild("FxSwap")
	t.ok(ghost and ghost.Text == "0/6", "the old count rolls away like an odometer")
	t.ok(math.abs(button.Icon.Rotation - restTilt) > 0.5, "🐠 wiggles")
	local ring = button:FindFirstChild("FxRing")
	t.ok(ring, "a ring around «САДОК»")
	t.ok(
		colorNear(ring:FindFirstChildOfClass("UIStroke").Color, UIConfig.Palette.Water.Top),
		"… in Water (no rarity)"
	)
	sim:Advance(1.5)
	t.eq(chip:FindFirstChild("FxSwap"), nil, "the odometer copy is gone")
	t.eq(button:FindFirstChild("FxRing"), nil, "the ring is gone")
	t.near(button.Icon.Rotation, restTilt, 1e-3, "🐠 back at rest")
	t.near(button.FxScale.Scale, 1, 1e-3)
	-- Full: the chip turns Gold; a sale brings it back to Cream (the count just swaps).
	p:SetAttribute("TankCount", 6)
	sim:Advance(UIConfig.TankButton.StoredWait + 0.1)
	local face = chip[chip:GetAttribute("CandyFace")]
	t.eq(chip.Label.Text, "6/6")
	t.ok(colorNear(capTop(face.Fill), UIConfig.Palette.Gold.Top), "a full tank: the chip is gold")
	p:SetAttribute("TankCount", 5)
	sim:Advance(0.1)
	t.eq(chip.Label.Text, "5/6", "a sale: the count follows at once")
	t.ok(colorNear(capTop(face.Fill), UIConfig.Palette.Cream.Top), "… Cream again")
	sim:Advance(1)
	t.eq(button:FindFirstChild("FxRing"), nil, "a sale plays no arrival")
	sim:AssertNoErrors({ warnings = true })
end

tests["«САДОК» chip: frozen while the HUD has CounterHold; the release plays the arrival in rarity colours"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	local button = tankButtonOf(sim, p)
	local hud = p.PlayerGui.HUD
	local chip = button.Count
	t.eq(chip.Label.Text, "0/6")
	-- The catch card is up: its fish has not flown into «САДОК» yet.
	sim:Run(function()
		hud:SetAttribute("CounterHold", 0)
	end, p)
	p:SetAttribute("TankCount", 1)
	sim:Advance(1)
	t.eq(chip.Label.Text, "0/6", "held at the old count while the fish flies")
	t.eq(chip:FindFirstChild("FxSwap"), nil, "no roll while held")
	t.eq(button:FindFirstChild("FxRing"), nil)
	-- The card closes on an Epic (CounterIncoming), the 🐟 lands: CounterHold goes.
	sim:Run(function()
		hud:SetAttribute("CounterIncoming", "Epic")
		hud:SetAttribute("CounterHold", nil)
	end, p)
	sim:Advance(0.05)
	t.eq(chip.Label.Text, "1/6", "the new count on arrival")
	t.ok(chip:FindFirstChild("FxSwap"), "… rolling in")
	t.ok(button.FxScale.Scale > 1.05, "«САДОК» jumps")
	local ring = button:FindFirstChild("FxRing")
	t.ok(ring and colorNear(ring:FindFirstChildOfClass("UIStroke").Color, UIConfig.Rarity.Epic.Top), "an Epic ring")
	sim:Advance(1.5)
	t.near(button.FxScale.Scale, 1, 1e-3, "settled")
	t.eq(chip:FindFirstChild("FxSwap"), nil)
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
	t.eq(home.Caption.Text, "ЖДИ", "«ЖДИ» instead of «ДОМОЙ» while cooling down")
	t.ok(home.Caption.ZIndex > home.Cooldown.ZIndex, "the caption sits above the veil")
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
	t.near(home.Icon.TextTransparency, 0.85, 0.02, "the house fades")
	sim:Advance(BaseConfig.HomeCooldown)
	t.eq(home.Cooldown.Visible, false)
	t.eq(home.CooldownText.Visible, false)
	t.eq(home.Caption.Text, "ДОМОЙ", "caption restored")
	t.ok(home.Caption.ZIndex < home.Cooldown.ZIndex, "back under the (hidden) veil")
	t.near(home.Icon.TextTransparency, 0, 0.02, "the house is bright again")
	sim:Advance(1)
	t.eq(home:FindFirstChild("FxRing"), nil, "ready ring gone")
	t.near(home.FxScale.Scale, 1, 1e-3)
	sim:AssertNoErrors({ warnings = true })
end

tests["toasts (stage 4 wave 3, C-31): the entrance and the leave never rise above the column's free top — a pop-in never crosses the status stack; a lower slot still drops in"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	sim:Advance(5)
	local column = p.PlayerGui.HUD.Toasts
	sim:WaitFor(function()
		return #liveToasts(p) == 0
	end, 15, 0.1)
	sim:Advance(1)
	-- The top of a toast in px from the column's top (its Position: scale of the column + offset).
	local function topOf(toast: any): number
		return toast.Position.Y.Scale * column.AbsoluteSize.Y + toast.Position.Y.Offset
	end
	local function watch(seconds: number, pick: () -> any?): (number, number)
		local lowest, highest = math.huge, -math.huge
		local t0 = sim:Time()
		while sim:Time() - t0 < seconds do
			local toast = pick()
			if toast then
				lowest = math.min(lowest, topOf(toast))
				highest = math.max(highest, topOf(toast))
			end
			sim:Advance(1 / 60)
		end
		return lowest, highest
	end
	notify(sim, p, "Первое", "info")
	local lowest1 = watch(0.6, function()
		return liveToasts(p)[1]
	end)
	t.ok(
		lowest1 >= -0.5,
		`slot 1's entrance starts inside the column (top {lowest1} px ≥ 0): never over the status stack`
	)
	notify(sim, p, "Второе", "success")
	sim:Advance(1 / 60)
	local second = liveToasts(p)[2]
	t.ok(second ~= nil, "a second toast")
	local start = topOf(second)
	local lowest2, highest2 = watch(0.6, function()
		return liveToasts(p)[2]
	end)
	t.ok(lowest2 >= -0.5, `slot 2's entrance stays inside the column ({lowest2} px)`)
	t.ok(highest2 > start + 4, `… and still drops in from above its slot ({start} → {highest2} px)`)
	-- The top toast leaves: it rises only as far as the column's free top (here: not at all).
	local seen, lowestLeaving = 0, math.huge
	local t0 = sim:Time()
	while sim:Time() - t0 < UIConfig.ToastDuration + 1 do
		for _, c in column:GetChildren() do
			if c.Name == "ToastLeaving" then
				seen += 1
				lowestLeaving = math.min(lowestLeaving, topOf(c))
			end
		end
		sim:Advance(1 / 60)
	end
	t.ok(seen > 0, "a toast left meanwhile")
	t.ok(lowestLeaving >= -0.5, `a leaving toast never rises above the column ({lowestLeaving} px)`)
	sim:AssertNoErrors({ warnings = true })
end

tests["toasts: colour and icon by kind, width by text, slots, leave and reflow"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	sim:Advance(5) -- the join banner is gone
	local column = p.PlayerGui.HUD.Toasts
	-- (stage 4: the join / newbie protection toast «Защита новичка …» shows once after the banner)
	sim:WaitFor(function()
		return #liveToasts(p) == 0
	end, 15, 0.1)
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
	local slotY = 0
	for i, kind in { "success", "danger", "warning" } do
		local style = UIConfig.ToastKinds[kind]
		t.ok(colorNear(capTop(toasts[i].Face.Fill), UIConfig.Palette[style.Token].Top), `{kind}: {style.Token} tile`)
		t.ok(colorNear(toasts[i].Lip.BackgroundColor3, UIConfig.Palette[style.Token].Lip), `{kind}: lip`)
		t.eq(toasts[i].IconSocket.Icon.Text, style.Icon, `{kind}: icon`)
		t.near(toasts[i].Position.Y.Scale, slotY, 1e-3, `{kind}: in slot {i}`)
		t.near(toasts[i].FxScale.Scale, 1, 1e-3, `{kind}: popped in`)
		slotY += toasts[i].Size.Y.Scale + 0.08
	end
	t.eq(toasts[2].IconSocket.Icon.Text, "🚨", "danger is an alarm, not «forbidden»")
	t.ok(
		toasts[1]:GetAttribute("NaturalWidth") < toasts[2]:GetAttribute("NaturalWidth"),
		"short text → narrower natural width"
	)
	t.near(toasts[2]:GetAttribute("NaturalWidth"), 1, 1e-6, "long text → full width")
	t.ok(toasts[2].Size.Y.Scale > toasts[1].Size.Y.Scale * 1.4, "… and two lines tall")
	for i = 1, 3 do
		t.near(toasts[i].Size.X.Scale, 1, 1e-3, `stacked toasts share the widest width ({i})`)
	end
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

tests["toasts: phones — one at a time, none over the minigame or the catch; they wait and come back"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	sim:Advance(5)
	local hud = p.PlayerGui.HUD
	local minigame = hud.Fishing.Minigame
	local function setMinigame(visible: boolean)
		sim:Run(function()
			minigame.Visible = visible
		end, p)
	end
	-- A phone shows one at most (a second one would lie on the avatar's head).
	notify(sim, p, "Один", "info")
	notify(sim, p, "Два", "info")
	sim:Advance(0.6)
	t.eq(#liveToasts(p), UIConfig.MaxToastsPhone, "one toast on a phone")
	sim:Advance(8)
	t.eq(#liveToasts(p), 0)
	-- A toast just shown when the minigame opens goes back into the queue.
	notify(sim, p, "Первое", "info")
	sim:Advance(0.6)
	setMinigame(true)
	sim:Advance(0.3)
	t.eq(#liveToasts(p), 0, "nothing under the minigame on a phone")
	notify(sim, p, "Рыбак: легендарная рыба «Акулёнок»!", "Legendary")
	sim:Advance(0.6)
	t.eq(#liveToasts(p), 0, "a broadcast waits too")
	-- A danger toast does not wait.
	notify(sim, p, "Твою базу грабят!", "danger")
	sim:Advance(0.6)
	local live = liveToasts(p)
	t.eq(#live, 1)
	t.eq(live[1].Label.Text, "Твою базу грабят!", "danger shows even over the minigame")
	sim:Advance(6)
	-- The minigame closes: the waiting ones come out, one at a time, in order.
	setMinigame(false)
	sim:Advance(0.6)
	live = liveToasts(p)
	t.eq(#live, 1)
	t.eq(live[1].Label.Text, "Первое", "the evicted toast comes back first")
	-- The catch (CounterHold from "Caught" to the 🐟 arriving): nothing, even on a PC.
	sim:Run(function()
		hud:SetAttribute("CounterHold", 0)
	end, p)
	sim:Advance(0.3)
	t.eq(#liveToasts(p), 0, "no toast during the catch")
	sim:Run(function()
		hud:SetAttribute("CounterHold", nil)
	end, p)
	sim:Advance(0.6)
	live = liveToasts(p)
	t.eq(#live, 1)
	t.eq(live[1].Label.Text, "Первое", "the catch sent it back into the queue too: it returns first")
	sim:Advance(UIConfig.ToastDuration + 0.8)
	live = liveToasts(p)
	t.eq(#live, 1)
	t.eq(live[1]:GetAttribute("Kind"), "Legendary", "then the broadcast")
	sim:Advance(8)
	t.eq(#liveToasts(p), 0, "everyone leaves")
	sim:AssertNoErrors({ warnings = true })
end

tests["toasts: a PC keeps one toast over the minigame, none over the catch card; the column clears the chat"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	sim:Advance(5)
	local hud = p.PlayerGui.HUD
	local column = hud.Toasts
	local vp = sim.players.state[sim:Unwrap(p)].viewport
	-- The Roblox chat window is in the top-left corner (≈ 370 px wide): the column stays clear.
	t.ok(column.AbsolutePosition.X >= 368 + 48, `the column starts at x {column.AbsolutePosition.X}`)
	t.ok(column.AbsoluteSize.X >= 320, "still wide enough")
	t.near(column.AbsolutePosition.X + column.AbsoluteSize.X / 2, vp.X / 2, 1, "centred")
	local minigame, card = hud.Fishing.Minigame, hud.Fishing.CatchCard
	sim:Run(function()
		minigame.Visible = true
	end, p)
	notify(sim, p, "Первое", "info")
	notify(sim, p, "Второе", "info")
	sim:Advance(0.6)
	t.eq(#liveToasts(p), 1, "one over the minigame")
	-- A hit word («ОТЛИЧНО!», a FxFloat over the panel) rises into the column: the toast steps aside
	-- and comes back when the word is gone (like «МИМО!» on the miss ghost).
	local word = sim:Create("TextLabel", { Name = "FxFloat" }, minigame)
	sim:Advance(0.4)
	t.eq(#liveToasts(p), 0, "no toast while a hit word rises over the minigame")
	word:Destroy()
	sim:Advance(0.6)
	t.eq(#liveToasts(p), 1, "back once the word is gone")
	sim:Run(function()
		minigame.Visible = false
		card.Visible = true
	end, p)
	sim:Advance(0.6)
	t.eq(#liveToasts(p), 0, "none over the catch card")
	sim:Run(function()
		card.Visible = false
	end, p)
	sim:Advance(0.6)
	t.eq(#liveToasts(p), 2, "back after the card")
	sim:AssertNoErrors({ warnings = true })
end

tests["toasts: Legendary is a gold plate, Mythic a dark plate in a spinning rainbow outline — bigger, longer"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	sim:Advance(5)
	notify(sim, p, "Рыбак: легендарный «Акулёнок»!", "Legendary")
	sim:Advance(0.2)
	notify(sim, p, "Рыбак: мифическая рыба «Рыба-дракон» ×2!", "Mythic")
	sim:Advance(0.2)
	notify(sim, p, "Ура!", "success")
	sim:Advance(0.6)
	local live = liveToasts(p)
	t.eq(#live, 3)
	local legendary, mythic, plain = live[1], live[2], live[3]
	local gold = UIConfig.Palette.Gold
	t.ok(colorNear(capTop(legendary.Face.Fill), gold.Top), "Legendary: a Gold plate")
	-- No studs on any toast (UI v5): the broadcasts are bigger and louder instead.
	for _, toast in { legendary, mythic, plain } do
		t.eq(#studsUnder(toast), 0, `{toast:GetAttribute("Kind")}: no studs`)
		t.eq(toast:FindFirstChild("Studs"), nil)
	end
	t.eq(legendary.IconSocket.Icon.Text, "🌟")
	t.eq(mythic.IconSocket.Icon.Text, "🌈")
	-- The rainbow only on the outline — a dark face, white letters.
	t.ok(colorNear(capTop(mythic.Face.Fill), UIConfig.Palette.Night.Top), "Mythic: a dark (Night) face")
	local rim = mythic.Lip:FindFirstChildOfClass("UIStroke")
	t.ok(rim and rim:FindFirstChild("FxRim") and #rim.FxRim.Color.Keypoints >= 6, "… in a rainbow outline")
	-- Two lines: who (small) over what (big; the rarity word in capitals; white, gold at the bottom).
	t.eq(legendary.Byline.Text, "Рыбак")
	t.eq(legendary.Label.Text, "ЛЕГЕНДАРНЫЙ «Акулёнок»!")
	t.eq(mythic.Byline.Text, "Рыбак")
	t.eq(mythic.Label.Text, "МИФИЧЕСКАЯ рыба «Рыба-дракон» ×2!")
	t.ok(legendary.Byline.AbsolutePosition.Y < legendary.Label.AbsolutePosition.Y, "who above what")
	t.ok(colorNear(legendary.Label.TextFill.Color.Keypoints[1].Value, Color3.new(1, 1, 1)), "light gold letters")
	t.eq(mythic.Label:FindFirstChild("TextFill"), nil, "white letters on the dark face (readable)")
	t.eq(plain:FindFirstChild("Byline"), nil, "a plain toast stays one label")
	t.eq(p.PlayerGui.HUD:FindFirstChild("FxVignette"), nil, "someone else's catch never washes the screen")
	local r0 = rim.FxRim.Rotation
	sim:Advance(0.5)
	t.ok(rim.FxRim.Rotation ~= r0, "… the rainbow rim slowly spins")
	t.ok(legendary.Size.Y.Scale > plain.Size.Y.Scale * 1.1, "broadcasts are bigger")
	-- They outlive a plain toast (4.5 s vs 3.5 s); an unknown kind shows as info.
	notify(sim, p, "???", "nonsense")
	sim:Advance(3.1)
	local kinds = {}
	for _, toast in liveToasts(p) do
		kinds[toast:GetAttribute("Kind")] = true
	end
	t.ok(kinds.Mythic, "the Mythic broadcast is still up")
	t.ok(not kinds.success, "the plain one has left")
	sim:Advance(6)
	t.eq(#liveToasts(p), 0)
	t.eq(sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p).activeJobs(), 0, "nothing left per frame")
	sim:AssertNoErrors({ warnings = true })
end

tests["toasts: on the smallest phone a long broadcast stays one line (≥ 12 px), not over the avatar's head"] = function(
	t
)
	-- SIM-C1-02: on 667 x 375 the two-line (or three-line) broadcast covered the player's own head
	-- for 4.5 s. A touch screen shrinks a long headline (down to 12 px) before it wraps.
	local sim = boot(t)
	local p = sim:AddPlayer({ UserId = 1, Name = "Hud1", device = "phone", viewport = roblox.Vector2.new(667, 375) })
	sim:Advance(6)
	for _, case in
		{
			{
				"Legendary",
				"КапитанКрюк (Лазурная база): легендарная рыба «Акулёнок»!",
			},
			{
				"Mythic",
				"КапитанКрюк (Лазурная база): мифическая радужная рыба «Рыба-дракон» ×5!",
			},
		}
	do
		local kind, text = case[1], case[2]
		notify(sim, p, text, kind)
		sim:Advance(1)
		local toast = liveToasts(p)[1]
		t.ok(toast and toast:GetAttribute("Kind") == kind, `{kind}: shown`)
		t.eq(toast.Label.TextWrapped, false, `{kind}: the headline is one line`)
		local fit = toast.Label:FindFirstChildOfClass("UITextSizeConstraint")
		t.ok(fit.MinTextSize >= 12 and fit.MaxTextSize >= fit.MinTextSize, `{kind}: text ≥ 12 px`)
		-- One headline line under the byline: the plate stays about as low as two plain lines.
		local height = toast.AbsoluteSize.Y
		t.ok(height <= 48, `{kind}: a one-line broadcast ({height} px)`)
		t.ok(toast.AbsoluteSize.X <= 667 - 2 * 16, `{kind}: on screen`)
		sim:Advance(6)
	end
	sim:AssertNoErrors({ warnings = true })
end

tests["trophy chip: someone else's Legendary pillar off-screen — a small chip on that side while it burns"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	local other = addPlayer(sim, 2, "phone")
	sim:Advance(5)
	local hud = p.PlayerGui.HUD
	local UiFx = sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p)
	local fx = sim:Require(sim:Find("Controllers.FishingFxController", p:FindFirstChildOfClass("PlayerScripts")), p)
	local FishingConfig = sim:Require(sim:Find("ReplicatedStorage.Shared.Config.FishingConfig"), p)
	local template = hud:FindFirstChild("TrophyPointer")
	t.ok(template and template.Visible == false, "HUD.TrophyPointer: a hidden template")
	local camera = roblox.CFrame.lookAt(Vector3.new(0, 30, 0), Vector3.new(0, 25, -100))
	sim:Run(function()
		sim.workspace.CurrentCamera.CFrame = camera
	end, p)
	local vp = sim.players.state[sim:Unwrap(p)].viewport
	local function chips(): { any }
		local list = {}
		for _, c in hud:GetChildren() do
			if c.Name == "TrophyChip" then
				table.insert(list, c)
			end
		end
		return list
	end
	-- Behind the camera and to its right: the chip sits at the right edge.
	local behind = camera.Position - camera.LookVector * 120 + camera.RightVector * 60 - Vector3.new(0, 40, 0)
	sim:Run(function()
		fx.OtherTrophy:Fire(other, behind, "Legendary")
	end, p)
	sim:Advance(0.5)
	local chip = chips()[1]
	t.ok(chip and chip.Visible, "a chip for the off-screen pillar")
	t.eq(chip.Body.IconSocket.Icon.Text, "🌟", "Legendary: 🌟")
	t.ok(chip.AbsolutePosition.X > vp.X / 2, `on the right edge (x {chip.AbsolutePosition.X})`)
	t.ok(vp.X - (chip.AbsolutePosition.X + chip.AbsoluteSize.X * 1.42) >= 16 - 1, "≥ 16 px from the screen edge")
	-- (stage 3: «САДОК» over «ДОМОЙ» — the top of the taller column; stage 4: with «ЗАЩИТА» over
	-- them a phone has no room above the column — the chip stands LEFT of it, at its foot)
	t.ok(hud.RightButtons.TankButton.Visible, "«САДОК» is on screen")
	local chipRect = rectOf(sim, p, chip)
	local top = if hud.RightButtons.DefenceButton.Visible
		then hud.RightButtons.DefenceButton
		else hud.RightButtons.TankButton
	local topRect = rectOf(sim, p, top)
	if hud.RightButtons.DefenceButton.Visible then
		local columnLeft = math.huge
		for _, button in hud.RightButtons:GetChildren() do
			if button:IsA("GuiObject") and button.Visible then
				columnLeft = math.min(columnLeft, button.AbsolutePosition.X)
			end
		end
		t.ok(
			columnLeft - (chip.AbsolutePosition.X + chip.AbsoluteSize.X * 1.42) >= 16 - 1,
			`three buttons on a phone: left of the column, ≥ 16 px (chip right {chip.AbsolutePosition.X + chip.AbsoluteSize.X * 1.42}, column {columnLeft})`
		)
		local home = rectOf(sim, p, hud.RightButtons.HomeButton)
		t.ok(
			math.abs((chipRect.y + chipRect.h / 2) - (home.y + home.h / 2)) <= home.h,
			`no fishing buttons: at the column's foot, by «ДОМОЙ» (its row {home.y}, chip {chipRect.y})`
		)
		-- The rod in hand («ЗАБРОСИТЬ») and waiting («СМОТАТЬ»): the chip climbs above them (≥ 16 px:
		-- the right thumb is there) or hides when the lane has no free spot.
		for _, name in { "ActionButton", "StopButton" } do
			local button = hud.Fishing.ActionArea[name]
			button.Visible = true
			sim:Advance(0.2)
			if chip.Visible then
				local r = rectOf(sim, p, chip)
				local ring = chip.AbsoluteSize.X * 0.62 -- (its base ring and tip reach past the body)
				local b = rectOf(sim, p, button)
				local dx = math.max(b.x - (r.x + r.w + ring / 2), (r.x - ring / 2) - (b.x + b.w), 0)
				local dy = math.max(b.y - (r.y + r.h + ring / 2), (r.y - ring / 2) - (b.y + b.h), 0)
				t.ok(
					math.sqrt(dx * dx + dy * dy) >= 16 - 1,
					`{name} up: the chip keeps ≥ 16 px from it (chip y {r.y}, {name} y {b.y})`
				)
			end
			button.Visible = false
			sim:Advance(0.2)
		end
	else
		t.ok(
			chipRect.y + chipRect.h * 1.1 + 16 <= topRect.y + 1,
			`above the right button column, ≥ 16 px (chip {chipRect.y}+{chipRect.h}, «САДОК» {topRect.y})`
		)
	end
	t.ok(chip.AbsoluteSize.Y >= 44, `big enough to see (≥ 44 px: {chip.AbsoluteSize.Y})`)
	local baseColor = other:GetAttribute("BaseColor")
	t.ok(
		typeof(baseColor) ~= "Color3" or colorNear(chip.BaseRing.Stroke.Color, baseColor),
		"ringed in the catcher's base colour"
	)
	t.ok(UiFx.activeJobs() > 0, "one frame job follows the pillar while the chip lives")
	-- On a phone the own minigame hides it (like the toasts).
	sim:Run(function()
		hud.Fishing.Minigame.Visible = true
	end, p)
	sim:Advance(0.2)
	t.eq(chip.Visible, false, "hidden during the own minigame on a phone")
	sim:Run(function()
		hud.Fishing.Minigame.Visible = false
	end, p)
	sim:Advance(0.2)
	t.eq(chip.Visible, true, "back after it")
	-- A pillar in front of the camera is on screen: no chip for it.
	local ahead = camera.Position + camera.LookVector * 200 - Vector3.new(0, 30, 0)
	sim:Run(function()
		fx.OtherTrophy:Fire(other, ahead, "Mythic")
	end, p)
	sim:Advance(0.3)
	t.eq(#chips(), 2)
	for _, c in chips() do
		if c:GetAttribute("Rarity") == "Mythic" then
			t.eq(c.Visible, false, "the Mythic pillar is on screen: its chip stays hidden")
			t.eq(c.Body.IconSocket.Icon.Text, "🌈")
		end
	end
	-- Gone with the pillar; nothing runs per frame afterwards.
	sim:Advance(FishingConfig.Fx.PillarTimeOther.Mythic + 0.3)
	t.eq(#chips(), 0, "the chips go with the pillars")
	t.eq(UiFx.activeJobs(), 0, "no frame job without chips")
	sim:AssertNoErrors({ warnings = true })
end

tests["chrome micro-life: rare, one widget at a time, only when calm; timers only"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	sim:Advance(6) -- the base banner has flown into the badge, the welcome toast is gone
	local hud = p.PlayerGui.HUD
	t.ok(hud.RightButtons.TankButton.Visible, "«САДОК» is on screen")
	local UiFx = sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p)
	local flag = hud.Status.BaseBadge.FlagSocket
	local fish = hud.RightButtons.TankButton.Icon
	local home = hud.RightButtons.HomeButton.Icon
	local rest = { flag = flag.Rotation, fish = fish.Rotation, home = home.AnchorPoint }
	local function moving(): { string }
		local list = {}
		if math.abs(flag.Rotation - rest.flag) > 0.5 then
			table.insert(list, "flag")
		end
		if math.abs(fish.Rotation - rest.fish) > 0.5 then
			table.insert(list, "fish")
		end
		if (home.AnchorPoint - rest.home).Magnitude > 0.01 then
			table.insert(list, "home")
		end
		return list
	end
	local idle = sim:CountConnections(p)
	-- While fishing nothing stirs.
	p:SetAttribute("FishingState", "Waiting")
	local stirred = false
	for _ = 1, 200 do
		sim:Advance(0.1)
		if #moving() > 0 then
			stirred = true
		end
	end
	t.eq(stirred, false, "the chrome keeps still while fishing")
	-- Calm: one widget at a time, rarely, a different one each time.
	p:SetAttribute("FishingState", "Idle")
	local starts: { { at: number, what: string } } = {}
	local lastSeen: { [string]: number } = {} -- (a wiggle passes its rest between swings: one move)
	local now = 0
	for _ = 1, 400 do
		sim:Advance(0.1)
		now += 0.1
		local list = moving()
		t.ok(#list <= 1, `one widget at a time ({table.concat(list, ", ")})`)
		for _, what in list do
			if now - (lastSeen[what] or -math.huge) > 1.5 then
				table.insert(starts, { at = now, what = what })
			end
			lastSeen[what] = now
		end
	end
	t.ok(#starts >= 2, `the chrome comes alive now and then ({#starts} times in 40 s)`)
	t.ok(#starts <= 6, "… but rarely")
	local kinds = {}
	for index, start in starts do
		kinds[start.what] = true
		if index > 1 then
			t.ok(start.at - starts[index - 1].at >= 7.5, `≥ 8 s apart ({start.at - starts[index - 1].at})`)
		end
	end
	local distinct = 0
	for _ in kinds do
		distinct += 1
	end
	t.ok(distinct >= 2, "different widgets take turns")
	t.eq(UiFx.activeJobs(), 0, "no frame work")
	t.eq(sim:CountConnections(p), idle, "no connections added")
	-- The 40 s window can end mid-swing (the schedule is random): let the last one settle.
	sim:WaitFor(function()
		return #moving() == 0
	end, 1.5)
	t.near(flag.Rotation, rest.flag, 0.5, "the flag back at rest")
	t.near(fish.Rotation, rest.fish, 0.5, "the fish back at rest")
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
	-- A toast and a fish in the tank add no lasting connections either.
	notify(sim, p, "Привет!", "success")
	p:SetAttribute("TankCount", 1)
	p:SetAttribute("Money", 40)
	sim:Advance(6)
	t.eq(sim:CountConnections(p), idle, "back to the idle count")
	t.eq(UiFx.activeJobs(), 0)
	sim:AssertNoErrors({ warnings = true })
end

-- Stage 4 wave 3 (UX-05 / UX-06 / ART-08): the own fisher under the column.

-- The client's modules (NotifyController, FishingLayout).
local function clientModule(sim: any, p: any, name: string): any
	local module = sim:Find(`Controllers.{name}`, p:FindFirstChildOfClass("PlayerScripts"))
	assert(module, `Controllers.{name}`)
	return sim:Require(module, p)
end

-- A follow camera behind the character (his head in the middle of the screen, under the toast
-- column), or one looking away at the sky (no fisher on screen).
local function cameraOn(sim: any, p: any, fisher: boolean)
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
	assert(root, "a character")
	sim:Run(function()
		local camera = sim.workspace.CurrentCamera
		camera.FieldOfView = 70
		local at = root.Position
		local back = root.CFrame.LookVector * -1
		camera.CFrame = if fisher
			then roblox.CFrame.lookAt(at + back * 11 + Vector3.new(0, 4.5, 0), at + Vector3.new(0, 1.5, 0))
			else roblox.CFrame.lookAt(at + Vector3.new(0, 200, 0), at + Vector3.new(0, 400, 50))
	end, p)
end

-- The own fisher's box on screen (FishingLayout.fisherBox, HUD px; with its FISHER_PAD) or nil.
local function fisherBox(sim: any, p: any): any?
	local layout = clientModule(sim, p, "FishingLayout")
	local hud = p.PlayerGui.HUD
	return sim:Run(function()
		return layout.fisherBox(p.Character, sim.workspace.CurrentCamera, hud.AbsolutePosition)
	end, p)
end

local function quiet(sim: any, p: any)
	sim:Advance(5) -- the join banner is gone
	sim:WaitFor(function()
		return #liveToasts(p) == 0
	end, 15, 0.1)
	sim:Advance(1)
end

tests["toasts (stage 4 wave 3, UX-06): on a PC the stack stops above the own fisher — the others wait their turn; the fisher off screen: the device cap as before"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	quiet(sim, p)
	local hud = p.PlayerGui.HUD
	cameraOn(sim, p, true)
	sim:Advance(0.1)
	local fisher = fisherBox(sim, p)
	t.ok(fisher ~= nil, "the fisher on screen, under the column")
	local seen: { [string]: boolean } = {}
	local most = 0
	notify(sim, p, "Украдено: ФУГУ (Ника)", "theft")
	notify(sim, p, "Садок отдыхает 1:30 — не украдут", "shield")
	notify(sim, p, "Щит бесплатный: увидишь 🚨 — жми 🛡️", "info")
	local t0 = sim:Time()
	local worst = math.huge
	while sim:Time() - t0 < 16 do
		local live = liveToasts(p)
		most = math.max(most, #live)
		for i, toast in live do
			seen[toast:GetAttribute("Kind")] = true
			if i >= 2 and fisher then
				local bottom = toast.AbsolutePosition.Y + toast.AbsoluteSize.Y - hud.AbsolutePosition.Y
				worst = math.min(worst, fisher.y0 - bottom)
			end
		end
		sim:Advance(0.1)
	end
	t.ok(most < UIConfig.MaxToasts, `fewer than the PC cap at once over the fisher ({most})`)
	t.ok(worst >= 16 - 0.5, `a second toast only when it ends ≥ 16 px over the fisher ({worst})`)
	t.ok(seen.theft and seen.shield and seen.info, "… and every one of them shown in turn")
	-- the fisher off screen: three at once, as before
	cameraOn(sim, p, false)
	sim:Advance(0.1)
	t.eq(fisherBox(sim, p), nil, "no fisher on screen")
	notify(sim, p, "Первое", "info")
	notify(sim, p, "Второе", "success")
	notify(sim, p, "Третье", "warning")
	sim:Advance(1)
	t.eq(#liveToasts(p), UIConfig.MaxToasts, "the PC cap again")
	sim:AssertNoErrors({ warnings = true })
end

tests["toasts (stage 4 wave 3, UX-05): a toast an alert band pushed out early comes back when the band goes, but not when it waited longer than its own life (no stale «Щит погас» flicker before «Украдено»)"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	quiet(sim, p)
	local notifyModule = clientModule(sim, p, "NotifyController")
	local column = p.PlayerGui.HUD.Toasts
	local function band(on: boolean)
		sim:Run(function()
			notifyModule.Reserve("alert", if on then column.AbsoluteSize.Y else nil)
		end, p)
	end
	local life = UIConfig.ToastKinds.shield.Life or UIConfig.ToastDuration
	notify(sim, p, "Щит погас", "shield")
	sim:Advance(0.4)
	t.eq(#liveToasts(p), 1, "«Щит погас»")
	band(true)
	sim:Advance(0.3)
	t.eq(#liveToasts(p), 0, "the alert's band pushed it out (in its first half: back to the queue)")
	band(false)
	sim:Advance(0.3)
	local back = liveToasts(p)[1]
	t.ok(back and back:GetAttribute("Kind") == "shield", "a short alert: it comes back")
	sim:Advance(0.2)
	band(true)
	sim:Advance(life + 1)
	notify(sim, p, "Украдено: ФУГУ (Ника)", "theft")
	sim:Advance(0.1)
	band(false)
	local kinds: { string } = {}
	local t0 = sim:Time()
	while sim:Time() - t0 < 3 do
		for _, toast in liveToasts(p) do
			local kind = toast:GetAttribute("Kind")
			if kinds[#kinds] ~= kind then
				table.insert(kinds, kind)
			end
		end
		sim:Advance(1 / 30)
	end
	t.eq(
		table.concat(kinds, ","),
		"theft",
		"after a long alert: only «Украдено» — the stale «Щит погас» is dropped"
	)
	sim:AssertNoErrors({ warnings = true })
end

tests["toasts (stage 4 wave 3, ART-08): on a phone a two-line broadcast that would reach the own fisher's head is one line «Кто: ЧТО» over it (≥ 12 px); with no fisher under the column — two lines as before"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	quiet(sim, p)
	local hud = p.PlayerGui.HUD
	cameraOn(sim, p, true)
	sim:Advance(0.1)
	local fisher = fisherBox(sim, p)
	t.ok(fisher ~= nil, "the fisher on screen")
	local layout = clientModule(sim, p, "FishingLayout")
	notify(sim, p, "Украдено: ФУГУ (Ника)", "theft")
	sim:Advance(1)
	local toast = liveToasts(p)[1]
	t.ok(toast and toast:GetAttribute("Kind") == "theft", "«Украдено»")
	if toast and fisher then
		t.eq(toast:FindFirstChild("Byline"), nil, "one line (no byline)")
		t.eq(toast.Label.Text, "Украдено: ФУГУ (Ника)", "«Украдено: ФУГУ (Ника)»")
		local fit = toast.Label:FindFirstChildOfClass("UITextSizeConstraint")
		t.ok(fit and fit.MinTextSize >= 12, "≥ 12 px")
		local bottom = toast.AbsolutePosition.Y + toast.AbsoluteSize.Y - hud.AbsolutePosition.Y
		local head = fisher.y0 + layout.FISHER_PAD
		t.ok(
			bottom <= head - 8 + 0.5,
			`its plate ends over the head with room for its outline ({bottom} vs head {head})`
		)
	end
	sim:Advance(6)
	cameraOn(sim, p, false)
	sim:Advance(0.1)
	notify(sim, p, "Украдено: ФУГУ (Ника)", "theft")
	sim:Advance(1)
	local two = liveToasts(p)[1]
	t.ok(
		two and two:FindFirstChild("Byline") ~= nil,
		"no fisher under the column: «кто» over «что» as before"
	)
	sim:AssertNoErrors({ warnings = true })
end

return tests
