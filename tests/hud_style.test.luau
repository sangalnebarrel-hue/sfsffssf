--[[
	HUD chrome in the UI v3 «Кирпичики» style (tools/builder/gui/Hud.luau + HudController +
	NotifyController) in RbxSim against the built Place1.rbxl:
	  • every contract name is still there (controllers and tests find widgets by name);
	  • the chrome is made of bricks: front-view Studs behind the Lip (the side band, Ink outline
	    4 px at 720), a face with a capped "Fill" gradient, a Spec glint (no Gloss), Shine; Nunito
	    Heavy text with thick outlines, CAPS badge «ЛАЗУРНАЯ БАЗА», the counter a number «🐟 12»;
	  • the layout still fits on a phone, a tablet and a desktop: nothing overlaps, everything is
	    on screen, the Home button stays above the Jump button on touch screens;
	  • the runtime juice: base swatch on the badge and the base banner flying into it, «+N» over
	    the catch counter (held while the HUD has CounterHold), the draining Home cooldown («ЖДИ»),
	    toasts by kind (colour, icon, width, slots, queue while fishing widgets are up — and while
	    a hit word or a minigame ghost rises into the column, Legendary / Mythic broadcasts), the
	    chip pointing at someone else's off-screen light pillar, the type scale (UiFx.fitText), no
	    frame connection at idle.

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

-- A brick face's Top colour: the keypoint at UIConfig.Brick.CapStop (above it is the light cap).
local function capTop(fill: any): any
	for _, key in fill.Color.Keypoints do
		if math.abs(key.Time - UIConfig.Brick.CapStop) < 1e-3 then
			return key.Value
		end
	end
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

-- Brick check ---------------------------------------------------------------------------------

-- A brick (Theme.brick / Theme.tile): side band, capped face, glint, shine, studs (`studs` = count).
local function checkBrick(t: any, root: any, token: string?, what: string, studs: number?)
	local faceName = root:GetAttribute("CandyFace")
	t.ok(type(faceName) == "string", `{what}: CandyFace attribute`)
	local style = root:GetAttribute("CandyStyle")
	t.ok(style == "brick" or style == "tile", `{what}: a brick or a tile ({style})`)
	local lip = root:FindFirstChild("Lip")
	local face = root:FindFirstChild(faceName)
	t.ok(lip and lip:IsA("Frame"), `{what}: Lip`)
	t.ok(face and face:IsA("Frame"), `{what}: face {faceName}`)
	t.ok(lip.ZIndex < face.ZIndex, `{what}: the side band is behind the face`)
	local band = 1 - face.Size.Y.Scale
	t.ok(band >= 0.1 and band <= 0.2, `{what}: a deep side band ({band})`)
	local outline = lip:FindFirstChildOfClass("UIStroke")
	t.ok(outline, `{what}: the outline is on the lip`)
	t.eq(outline:GetAttribute("BaseThickness"), 4, `{what}: outline designed at 4 px`)
	t.ok(colorNear(outline.Color, UIConfig.Ink), `{what}: Ink outline`)
	local fill = face:FindFirstChild("Fill")
	t.ok(fill and fill:IsA("UIGradient"), `{what}: Fill gradient`)
	t.eq(fill.Rotation, 90, `{what}: vertical gradient`)
	local keys = fill.Color.Keypoints
	t.ok(#keys >= 3, `{what}: a light cap on top of the face`)
	if token then
		local look = UIConfig.Palette[token]
		t.ok(colorNear(capTop(fill), look.Top), `{what}: {token} top`)
		t.ok(colorNear(keys[#keys].Value, look.Bottom), `{what}: {token} bottom`)
		t.ok(colorNear(lip.BackgroundColor3, look.Lip), `{what}: {token} side band`)
		local cap = keys[1].Value
		t.ok(cap.R >= look.Top.R and cap.G >= look.Top.G and cap.B >= look.Top.B, `{what}: the cap is lighter`)
	end
	t.eq(face:FindFirstChild("Gloss"), nil, `{what}: no glossy band (it washed out the text)`)
	t.ok(face:FindFirstChild("Spec"), `{what}: a Spec glint`)
	local shine = face:FindFirstChild("Shine")
	t.ok(shine and shine:FindFirstChild("Band"), `{what}: Shine overlay with its Band`)
	t.ok(shine:FindFirstChildOfClass("UICorner"), `{what}: the shine follows the rounded corners`)
	t.ok(math.abs(shine.Band.Offset.X) >= 1, `{what}: the band waits out of sight`)
	local holder = root:FindFirstChild("Studs")
	if (studs or 0) == 0 then
		t.ok(holder == nil or #holder:GetChildren() == 0, `{what}: a smooth tile, no studs`)
		return
	end
	t.ok(holder, `{what}: Studs`)
	t.ok(holder.ZIndex < lip.ZIndex, `{what}: the studs stand behind the side band`)
	t.eq(#holder:GetChildren(), studs, `{what}: {studs} studs`)
	for i = 1, studs do
		local stud = holder:FindFirstChild(`Stud{i}`)
		t.ok(stud, `{what}: Stud{i}`)
		t.eq(stud:GetAttribute("CandyStud"), "front", `{what}: Stud{i} is a front stud`)
		t.ok(stud:FindFirstChild("Fill") and stud:FindFirstChildOfClass("UIStroke"), `{what}: Stud{i} lit, outlined`)
		t.ok(stud.AnchorPoint.Y > 0.5 and stud.Position.Y.Scale == 0, `{what}: Stud{i} on the top edge`)
	end
end

local tests = {}

tests["names: every widget the controllers and tests use is still there"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	local paths = {
		"Status.BaseBadge.Swatch",
		"Status.BaseBadge.Label",
		"Status.BaseBadge.FlagSocket.Flag",
		"Status.CatchCounter.Icon",
		"Status.CatchCounter.Label",
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
	}
	for _, path in paths do
		t.ok(sim:Gui(p, `HUD.{path}`), `HUD.{path}`)
	end
	t.ok(sim:Gui(p, "HUD.RightButtons.HomeButton"):IsA("GuiButton"), "Home is a button")
	t.ok(sim:Gui(p, "HUD.Status.BaseBadge.Label"):IsA("TextLabel"))
	sim:AssertNoErrors({ warnings = true })
end

tests["bricks: badge, counter, Home, banner and toasts are studded bricks / smooth tiles"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	local hud = p.PlayerGui.HUD
	checkBrick(t, hud.Status.BaseBadge, nil, "BaseBadge", 4)
	t.eq(hud.Status.BaseBadge:GetAttribute("CandyFace"), "Swatch", "the badge face is the Swatch")
	checkBrick(t, hud.Status.BaseBadge.FlagSocket, "Cream", "the badge's flag tile", 1)
	checkBrick(t, hud.Status.CatchCounter, "Gold", "CatchCounter", 3)
	checkBrick(t, hud.RightButtons.HomeButton, "Mint", "HomeButton", 2)
	checkBrick(t, hud.BaseBanner, nil, "BaseBanner", 6)
	checkBrick(t, hud.Toasts.ToastTemplate, "Sky", "ToastTemplate", 0)
	t.eq(hud.Toasts.ToastTemplate:GetAttribute("CandyStyle"), "tile", "a toast is a smooth tile")
	checkBrick(t, hud.TrophyPointer.Body, "Gold", "TrophyPointer.Body", 0)

	-- Text: white Nunito Heavy with a thick Ink outline (at least its tier's); CAPS on the chrome.
	for _, label in
		{
			hud.Status.BaseBadge.Label,
			hud.Status.CatchCounter.Label,
			hud.RightButtons.HomeButton.Caption,
			hud.Toasts.ToastTemplate.Label,
			hud.BaseBanner.NameLabel,
		}
	do
		t.ok(colorNear(label.TextColor3, Color3.new(1, 1, 1)), `{label:GetFullName()}: white text`)
		t.eq(label.FontFace.Weight, Enum.FontWeight.Heavy, `{label:GetFullName()}: Nunito Heavy`)
		local outline = label:FindFirstChild("Outline")
		t.ok(outline and outline:IsA("UIStroke"), `{label:GetFullName()}: outlined`)
		t.eq(outline.ApplyStrokeMode, Enum.ApplyStrokeMode.Contextual)
		t.ok(outline:GetAttribute("BaseThickness") >= 3.5, `{label:GetFullName()}: a thick outline`)
		t.ok(label.ZIndex > label.Parent.Lip.ZIndex + 1, `{label:GetFullName()}: above the face`)
	end
	local TextUtil = sim:Require(sim:Find("ReplicatedStorage.Shared.TextUtil"), p)
	local badgeText = hud.Status.BaseBadge.Label.Text
	t.eq(badgeText, TextUtil.upper(badgeText), "the badge in CAPS")
	t.eq(hud.Status.CatchCounter.Icon.Text, "🐟")
	t.eq(hud.RightButtons.HomeButton.Icon.Text, "🏠")
	-- Icons stand upright (only stamps and the banner flag tilt); free-standing ones are stickers.
	t.eq(hud.Status.CatchCounter.Icon.Rotation, 0, "the counter fish is upright")
	t.ok(hud.Status.CatchCounter.Icon:FindFirstChild("Sticker"), "… a sticker with a white rim")
	t.ok(hud.RightButtons.HomeButton.Icon:FindFirstChild("Sticker"), "the house too")
	t.ok(hud.Status.BaseBadge.FlagSocket.Flag, "flag tile on the badge")
	t.ok(hud.Toasts.ToastTemplate.IconSocket.Icon, "icon socket on toasts")
	t.ok(hud.Toasts.ToastTemplate.IconSocket:FindFirstChild("Rim"), "… a white 1x1 round tile with a rim")
	t.ok(hud.RightButtons.HomeButton.Cooldown:FindFirstChild("Drain"), "draining cooldown veil")
	t.ok(hud.RightButtons.HomeButton.Cooldown.ZIndex > hud.RightButtons.HomeButton.Caption.ZIndex)
	-- «ДОМОЙ» is on the brick's face (no navy ribbon); text tiers are set.
	t.eq(hud.RightButtons.HomeButton:FindFirstChild("CaptionRibbon"), nil, "no caption ribbon")
	t.eq(hud.RightButtons.HomeButton.Caption:GetAttribute("TextTier"), "Button")
	t.eq(hud.Status.BaseBadge.Label:GetAttribute("TextTier"), "Title")
	t.eq(hud.Toasts.ToastTemplate.Label:GetAttribute("TextTier"), "Body")
	-- The counter is a currency display: its number is box-driven, at least the Title tier.
	local number = hud.Status.CatchCounter.Label
	t.eq(number:GetAttribute("TextTier"), nil, "the counter's number is display text")
	t.ok(number:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize > UIConfig.Type.Title, "… big")
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
		p:SetAttribute("FishCaught", 7) -- shows the catch counter
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
		local cap = if device == "desktop"
			then UIConfig.MaxToasts
			elseif device == "phone" then UIConfig.MaxToastsPhone
			else UIConfig.MaxToastsTouch
		t.eq(#toasts, cap, `{device}: {cap} toasts (the device cap)`)

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
	t.ok(colorNear(badge.Lip.BackgroundColor3, swatch.Lip), "swatch side band")
	t.eq(badge.Swatch.BackgroundColor3, Color3.new(1, 1, 1), "white face under the gradient")
	local studBody = swatch.Top:Lerp(swatch.Bottom, 0.3)
	for _, stud in badge.Studs:GetChildren() do
		local mid = stud.Fill.Color.Keypoints[2].Value
		t.ok(colorNear(mid, studBody), `{stud.Name} in the base colour too`)
	end
	t.eq(badge.FlagSocket.Flag.Text, "🚩")
	local name = p:GetAttribute("BaseColorName")
	local caps = sim:Require(sim:Find("ReplicatedStorage.Shared.TextUtil"), p).upper(name)
	t.eq(badge.Label.Text, `{caps} БАЗА`, "the base name in CAPS")
	-- The banner: centre of the screen, in the same swatch, the name in capitals.
	local banner = hud.BaseBanner
	t.eq(banner.Visible, true, "the base banner is up")
	t.eq(banner.Caption.Text, "ТВОЯ БАЗА")
	t.ok(string.find(banner.NameLabel.Text, "!", 1, true), "big name with «!»")
	t.ok(colorNear(banner.Lip.BackgroundColor3, swatch.Lip), "banner in the base swatch")
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
		return p.PlayerGui.HUD.RightButtons.HomeButton.Lip:FindFirstChildOfClass("UIStroke")
	end
	t.ok(lipStroke(phone).Thickness < lipStroke(desktop).Thickness, "phone outline thinner")
	t.ok(lipStroke(phone).Thickness >= 1.5, "but still a real outline")
	t.eq(lipStroke(phone):GetAttribute("BaseThickness"), 4, "design value kept")
	-- Toasts cloned later are fitted too.
	notify(sim, phone, "Привет!", "info")
	sim:Advance(0.1)
	local toast = phone.PlayerGui.HUD.Toasts:FindFirstChild("Toast")
	t.eq(toast.Lip:FindFirstChildOfClass("UIStroke").Thickness, lipStroke(phone).Thickness)
	-- Text outlines never go below 2.5 px (white on Gold/Leaf/Sun reads only thanks to them).
	t.ok(phone.PlayerGui.HUD.Status.CatchCounter.Label.Outline.Thickness >= 2.5, "text outline floor 2.5 px")
	t.ok(toast.Label.Outline.Thickness >= 2.5, "… also on toasts cloned later")
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
				{ hud.RightButtons.HomeButton.Caption, "Button" },
				{ hud.Toasts.ToastTemplate.Label, "Body" },
				{ hud.BaseBanner.Caption, "Body" },
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
	-- A big broadcast toast cloned later: «кто» (Byline) at the Small tier, «что» (Label) sized by
	-- its box between Body and Title (on a phone Title − 2: both lines end above the avatar's head).
	notify(sim, phone, "Рыбак: легендарная рыба «Акулёнок»!", "Legendary")
	sim:Advance(0.1)
	local toast = liveToasts(phone)[1]
	t.eq(toast.Byline:GetAttribute("TextTier"), "Small")
	t.eq(select(2, limits(toast.Byline)), UIConfig.Type.Small, "phone Small size on the byline")
	t.eq(toast.Label:GetAttribute("TextTier"), nil, "the headline is box-driven")
	local lo, hi = limits(toast.Label)
	t.eq(hi, UIConfig.Type.Title - 2, "phone: the headline up to Title − 2")
	t.eq(lo, UIConfig.Type.Body, "… never under Body")
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
	t.eq(counter.Label.Text, "1", "and writes the number")
	local float = counter:FindFirstChild("FxFloat")
	t.ok(float, "+1 floats over the counter")
	t.eq(float.Text, "+1")
	t.ok(counter.Icon.Rotation ~= 0, "the fish wiggles")
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
	t.near(counter.Icon.Rotation, 0, 1e-3, "the fish is back at rest")
	p:SetAttribute("FishCaught", 3)
	sim:Advance(0.1)
	t.eq(counter:FindFirstChild("FxFloat"), nil, "no float without a new catch")
	sim:AssertNoErrors({ warnings = true })
end

tests["catch counter: CounterHold keeps the old number; clearing it plays the arrival"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	sim:Advance(5)
	local hud = p.PlayerGui.HUD
	local counter = hud.Status.CatchCounter
	p:SetAttribute("FishCaught", 2)
	sim:Advance(1.5)
	t.eq(counter.Label.Text, "2")
	-- The catch card opens: it holds the previous total until its 🐟 flies into the counter.
	sim:Run(function()
		hud:SetAttribute("CounterHold", 2)
	end, p)
	p:SetAttribute("FishCaught", 3)
	sim:Advance(0.2)
	t.eq(counter.Label.Text, "2", "held at the old total")
	t.eq(counter:FindFirstChild("FxFloat"), nil, "no +1 while held")
	-- (FishingController still bumps the counter on FishCaught in this wave; the next wave drops that.)
	sim:Run(function()
		hud:SetAttribute("CounterHold", nil)
	end, p)
	sim:Advance(0.05)
	t.eq(counter.Label.Text, "3", "the new total on arrival")
	t.ok(counter.FxScale.Scale > 1.05, "bump on arrival")
	local float = counter:FindFirstChild("FxFloat")
	t.ok(float and float.Text == "+1", "+1 floats on arrival")
	sim:Advance(1.5)
	t.eq(counter:FindFirstChild("FxFloat"), nil)
	t.near(counter.FxScale.Scale, 1, 1e-3)
	-- The first catch of the session while held at 0: the counter stays hidden until arrival.
	local q = addPlayer(sim, 2, "desktop")
	sim:Advance(5)
	local qhud = q.PlayerGui.HUD
	sim:Run(function()
		qhud:SetAttribute("CounterHold", 0)
	end, q)
	q:SetAttribute("FishCaught", 1)
	sim:Advance(0.2)
	t.eq(qhud.Status.CatchCounter.Visible, false, "hidden while the first fish is held")
	sim:Run(function()
		qhud:SetAttribute("CounterHold", nil)
	end, q)
	sim:Advance(0.05)
	t.eq(qhud.Status.CatchCounter.Visible, true, "appears when the fish arrives")
	t.eq(qhud.Status.CatchCounter.Label.Text, "1")
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

tests["toasts: colour and icon by kind, width by text, slots, leave and reflow"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "desktop")
	sim:Advance(5) -- the join banner is gone
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

tests["toasts: Legendary is a studded yellow brick, Mythic a spinning rainbow — bigger, longer"] = function(t)
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
	t.ok(colorNear(capTop(legendary.Face.Fill), gold.Top), "Legendary: a Gold brick")
	-- Rarer = a bigger brick: the broadcasts get studs (Mythic's in rainbow colours), a plain toast none.
	local studs = legendary:FindFirstChild("Studs")
	t.ok(studs and #studs:GetChildren() >= 3, "Legendary: studs on top")
	t.ok(studs.ZIndex < legendary.Lip.ZIndex, "… behind its side band")
	local hues = {}
	for _, stud in mythic.Studs:GetChildren() do
		local c = stud.Fill.Color.Keypoints[2].Value
		hues[string.format("%.2f %.2f %.2f", c.R, c.G, c.B)] = true
	end
	local distinct = 0
	for _ in hues do
		distinct += 1
	end
	t.ok(distinct >= 3, `Mythic: rainbow studs ({distinct} colours)`)
	t.eq(legendary.IconSocket.Icon.Text, "🌟")
	t.eq(mythic.IconSocket.Icon.Text, "🌈")
	t.ok(#mythic.Face.Fill.Color.Keypoints >= 6, "Mythic: rainbow face")
	-- Two lines: who (small) over what (big; the rarity word in capitals, gold / running rainbow).
	t.eq(legendary.Byline.Text, "Рыбак")
	t.eq(legendary.Label.Text, "ЛЕГЕНДАРНЫЙ «Акулёнок»!")
	t.eq(mythic.Byline.Text, "Рыбак")
	t.eq(mythic.Label.Text, "МИФИЧЕСКАЯ рыба «Рыба-дракон» ×2!")
	t.ok(legendary.Byline.AbsolutePosition.Y < legendary.Label.AbsolutePosition.Y, "who above what")
	t.ok(colorNear(legendary.Label.TextFill.Color.Keypoints[1].Value, Color3.new(1, 1, 1)), "light gold letters")
	t.ok(#mythic.Label.TextFill.Color.Keypoints >= 6, "rainbow letters")
	t.eq(plain:FindFirstChild("Byline"), nil, "a plain toast stays one label")
	t.ok(plain:FindFirstChild("Studs") == nil, "… and a smooth tile")
	t.ok(p.PlayerGui.HUD:FindFirstChild("FxVignette"), "Mythic: one thin rainbow pulse on the screen edges")
	local hue0 = mythic.Label.TextFill.Color.Keypoints[1].Value
	local r0 = mythic.Face.Fill.Rotation
	sim:Advance(0.5)
	t.ok(mythic.Face.Fill.Rotation ~= r0, "… slowly spinning")
	t.ok(mythic.Label.TextFill.Color.Keypoints[1].Value ~= hue0, "… and the rainbow letters run")
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
	local chipRect, homeRect = rectOf(sim, p, chip), rectOf(sim, p, hud.RightButtons.HomeButton)
	t.ok(
		chipRect.y + chipRect.h * 1.1 + 16 <= homeRect.y + 1,
		`above the right button column, ≥ 16 px (chip {chipRect.y}+{chipRect.h}, Home {homeRect.y})`
	)
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
