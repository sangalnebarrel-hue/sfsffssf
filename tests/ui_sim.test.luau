--[[
	The UI v5 «Симулятор» kit of the GUI builder (tools/builder/gui/Theme.luau) on its own, without
	the sim: what Theme.sim / glass / simButton / plate / badge / stat / title / label / icon build
	(the structure UiFx.setCandy, the motion helpers and the controllers rely on), that the numbers
	come from UIConfig (Sim, Font, Palette — the same table the client uses), that the font is
	Montserrat Heavy with an italic face for numbers, and that the kit is the only API: the old
	v3 / v4 names are gone (every widget is built with the sim primitives). The HUD in the built
	place is checked by tests/hud_style.test.luau; the runtime recolouring and motion by uifx.

	Run: lune run tools/run_tests.luau ui_sim
]]

local roblox = require("@lune/roblox")

local Theme = require("../tools/builder/gui/Theme")

local Instance = roblox.Instance
local Enum = roblox.Enum
local UDim2 = roblox.UDim2

local UI = Theme.UI
local SIM = UI.Sim
local P = UI.Palette

local function frame(): any
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(0.4, 0.1)
	return f
end

local function keyAt(gradient: any, time: number): any
	for _, key in gradient.Color.Keypoints do
		if math.abs(key.Time - time) < 1e-3 then
			return key.Value
		end
	end
	return nil
end

-- A guard: nothing stud-like may be built in the GUI (the LEGO look belongs to the map).
local function studsIn(root: any): { string }
	local found = {}
	for _, d in root:GetDescendants() do
		local name = d.Name
		if
			string.match(name, "^Stud%d*$")
			or name == "StudRow"
			or name == "Spec"
			or name == "LipBand"
			or d:GetAttribute("CandyStud") ~= nil
			or ((string.match(name, "^Studs") ~= nil) and #d:GetChildren() > 0)
		then
			table.insert(found, d:GetFullName())
		end
	end
	return found
end

local tests = {}

tests["sim: a gradient face, a thick outline in the hue's dark shade, a light rim, a hidden shine"] = function(t)
	local root = frame()
	local face = Theme.sim(root, "Leaf")
	t.eq(face.Name, "Face")
	t.eq(root:GetAttribute("CandyStyle"), "sim")
	t.eq(root:GetAttribute("CandyFace"), "Face")
	t.eq(root:GetAttribute("CandyRadius"), SIM.Radius, "nearly square corners (the outline rounds them)")
	t.eq(root.BackgroundTransparency, 1, "the root draws nothing")
	local lip = root.Lip
	t.eq(lip.BackgroundTransparency, 1, "the Lip only carries the outline (no fill under the face)")
	t.eq(lip.BackgroundColor3, P.Leaf.Lip, "… its colour is the Edge (kept for readers)")
	t.eq(face.Size, UDim2.fromScale(1, 1), "the face covers the whole root: no side band")
	t.ok(lip.ZIndex < face.ZIndex, "outline under the face")
	t.ok(Theme.SZ.Content > face.ZIndex, "content goes above the face")
	local edge = lip:FindFirstChildOfClass("UIStroke")
	t.eq(edge:GetAttribute("BaseThickness"), SIM.Stroke, "a thick outline (6 at 720: 4 px on a phone)")
	t.eq(edge.Color, P.Leaf.Lip, "in a dark shade of the button's own hue, not black")
	t.eq(edge.ApplyStrokeMode, Enum.ApplyStrokeMode.Border)
	t.eq(edge.LineJoinMode, Enum.LineJoinMode.Round)
	local fill = face.Fill
	t.eq(fill.Rotation, 90, "vertical: light top → saturated bottom")
	t.eq(#fill.Color.Keypoints, 2)
	t.eq(keyAt(fill, 0), P.Leaf.Top, "a plain Top → Bottom")
	t.eq(keyAt(fill, 1), P.Leaf.Bottom)
	local rim = face.Rim:FindFirstChildOfClass("UIStroke")
	t.eq(rim.Color, UI.White, "a white rim …")
	t.near(rim.Transparency, SIM.RimAlpha, 1e-6, "… half transparent")
	t.eq(rim.BorderStrokePosition, Enum.BorderStrokePosition.Inner, "… just inside the outline")
	t.eq(face.Shine.Visible, false, "the shine overlay waits hidden")
	t.eq(face:FindFirstChild("Gloss"), nil, "no gloss band unless asked")
	t.eq(root:FindFirstChild("Shadow"), nil, "no drop shadow unless asked")
	-- Options: round, gloss, shadow, a runtime colour.
	local round = frame()
	Theme.sim(round, "Sky", { round = true, gloss = true, shadow = true })
	t.eq(round:GetAttribute("CandyRadius"), 0.5)
	t.ok(round.Face:FindFirstChild("Gloss"), "a gloss highlight on request")
	t.ok(round.Shadow.ZIndex < round.Lip.ZIndex, "the drop shadow behind everything")
	local runtime = frame()
	Theme.sim(runtime, nil, { color = roblox.Color3.fromRGB(62, 114, 200) })
	local look = UI.swatchFor(roblox.Color3.fromRGB(62, 114, 200))
	t.eq(runtime.Lip:FindFirstChildOfClass("UIStroke").Color, look.Lip, "a runtime colour becomes a clean swatch")
	local _, s, v = look.Lip:ToHSV()
	t.ok(s > 0.9 and v < 0.35, "… its edge is the hue at value ≈ 0.29")
end

tests["glass: the reference's timer pill — a black face at half transparency, no outline, no rim"] = function(t)
	local root = frame()
	local face = Theme.glass(root)
	t.eq(root:GetAttribute("CandyStyle"), "glass")
	t.eq(root:GetAttribute("CandyHome"), "glass", "built as glass: dark tokens keep it glass")
	t.near(face.BackgroundTransparency, P.Glass.Alpha, 1e-6)
	t.eq(root.Lip:FindFirstChildOfClass("UIStroke").Transparency, 1, "no outline")
	t.eq(face.Rim:FindFirstChildOfClass("UIStroke").Transparency, 1, "no rim")
	t.eq(root:GetAttribute("CandyRadius"), 0.5, "a pill")
	-- A groove (cut into a panel): a faint Ink edge.
	local groove = frame()
	Theme.glass(groove, { edge = 2, alpha = 0.55 })
	local edge = groove.Lip:FindFirstChildOfClass("UIStroke")
	t.eq(edge.Color, UI.Ink)
	t.ok(edge.Transparency < 1, "a groove keeps a faint edge")
	-- A glass plate (the hint) and a bright label plate (a chip).
	local parent = frame()
	local hint = Theme.plate(parent, "Hint", "Glass", { Glass = true, Text = "Жди" })
	t.eq(hint:GetAttribute("CandyStyle"), "glass", "a glass pill")
	local chip = Theme.plate(parent, "Chip", "Cream", { Text = "1 КГ" })
	t.eq(chip:GetAttribute("CandyStyle"), "sim")
	t.eq(chip:GetAttribute("CandyRadius"), SIM.PlateRadius, "a label plate")
end

tests["buttons and plates: row, square and round layouts; outlined icons; transparent icon holders"] = function(t)
	local parent = frame()
	local row = Theme.simButton(parent, "Shop", "Leaf", { Layout = "row", Icon = "🛒", Caption = "Магазин" })
	t.ok(row:IsA("TextButton"), "a TextButton")
	t.eq(row.AutoButtonColor, false)
	t.eq(row.Icon.AnchorPoint.X, 0, "row: the icon at the left end")
	t.eq(row.Caption.AnchorPoint.X, 1, "… the caption fills the rest")
	t.ok(row.Caption.ZIndex > row.Face.ZIndex)
	local square =
		Theme.simButton(parent, "Home", "Grape", { Layout = "square", Icon = "🏠", Caption = "ДОМОЙ" })
	t.ok(square:FindFirstChildOfClass("UIAspectRatioConstraint"), "square")
	t.ok(square.Caption.Position.Y.Scale >= 0.85, "the caption sits on the bottom edge")
	t.eq(square.Icon.Outline.ApplyStrokeMode, Enum.ApplyStrokeMode.Contextual, "an Ink contour around the emoji")
	t.eq(square.Icon.Outline.Color, UI.Ink)
	local round = Theme.simButton(parent, "Act", "Sky", { Layout = "round", Icon = "🎣" })
	t.eq(round:GetAttribute("CandyRadius"), 0.5)
	local plate = Theme.plate(
		parent,
		"Toast",
		"Sun",
		{ Icon = "⚠️", Socket = true, Text = "Осторожно", Tier = "Body" }
	)
	t.eq(plate:GetAttribute("CandyRadius"), SIM.PlateRadius, "a label plate is rounder than a button")
	t.eq(plate.IconSocket.BackgroundTransparency, 1, "the icon holder draws nothing (no white disc)")
	t.eq(plate.IconSocket:FindFirstChildOfClass("UIStroke"), nil, "… and no ring")
	t.ok(plate.IconSocket.Icon.Outline, "the emoji itself is outlined")
	t.ok(plate.IconSocket.AnchorPoint.X > 0, "overhanging the left end")
	t.eq(plate.Label:GetAttribute("TextTier"), "Body")
	t.eq(#studsIn(parent), 0, "no studs")
end

tests["badge, stat and title: the red «!», the panel-less italic number, the outlined title with a shadow"] = function(
	t
)
	local host = frame()
	local badge = Theme.badge(host)
	t.eq(badge.Name, "Badge")
	t.eq(badge.Visible, false, "hidden until UiFx.badgeBob shows it")
	t.eq(badge:GetAttribute("CandyRadius"), 0.5, "a disc")
	t.eq(badge.Face.Fill.Color.Keypoints[1].Value, UI.BadgeRed.Top)
	t.eq(badge.Lip:FindFirstChildOfClass("UIStroke").Color, UI.BadgeRed.Lip, "a dark red ring")
	t.eq(badge.Mark.Text, "!")
	t.ok(badge.Position.X.Scale > 0.8 and badge.Position.Y.Scale < 0.3, "on the top-right corner")
	t.ok(badge:FindFirstChildOfClass("UISizeConstraint").MinSize.X >= 22, "never smaller than 22 px")

	local stat = Theme.stat(host, "CatchCounter", "🐟", { Text = "12" })
	t.eq(stat.BackgroundTransparency, 1)
	t.eq(stat:GetAttribute("CandyFace"), nil, "no panel behind the number")
	t.eq(stat:FindFirstChild("Lip"), nil)
	t.eq(stat.Label.FontFace.Style, Enum.FontStyle.Italic, "an italic number")
	t.eq(stat.Label.FontFace.Weight, Enum.FontWeight.Heavy)
	t.eq(stat.Label.TextXAlignment, Enum.TextXAlignment.Left)
	t.ok(stat.Label.Outline:GetAttribute("BaseThickness") >= 4, "a display outline")
	t.ok(stat.Label:FindFirstChild("TextFill"), "a TextFill to tint")
	t.ok(stat.Icon.Outline, "an outlined icon")

	local title = Theme.title(host, "NameLabel", { Text = "КРАСНАЯ!", Size = UDim2.fromScale(1, 0.5) })
	t.ok(title.Outline:GetAttribute("BaseThickness") >= 7, "a thick title outline")
	local shadow = host:FindFirstChild("NameLabelShadow")
	t.ok(shadow, "a drop-shadow twin next to it (a sibling)")
	t.eq(shadow:GetAttribute("ShadowOf"), "NameLabel")
	t.eq(shadow.Text, title.Text)
	t.eq(shadow.TextColor3, UI.Ink)
	t.ok(shadow.ZIndex < title.ZIndex, "under the title")
	t.ok(shadow.Position.Y.Scale > title.Position.Y.Scale, "a little lower")
	t.eq(shadow:FindFirstChild("TextFill"), nil, "a plain dark copy")
	t.eq(shadow:GetAttribute("TextTier"), nil, "the type scale sizes only the title")
end

tests["text: Montserrat Heavy, an italic face for numbers, outlines by tier"] = function(t)
	local root = frame()
	t.eq(Theme.FONT.Weight, Enum.FontWeight.Heavy, "the UI font is Montserrat Heavy")
	t.eq(Theme.FONT.Family, UI.Font.Family)
	t.ok(string.find(UI.Font.Family, "Montserrat", 1, true) ~= nil, "Montserrat (the reference's font)")
	t.eq(Theme.FONT_ITALIC.Style, Enum.FontStyle.Italic)
	t.eq(Theme.FONT_ITALIC.Family, UI.Font.Family)
	local number = Theme.label(root, "Number", { Text = "12", Italic = true })
	t.eq(number.FontFace.Style, Enum.FontStyle.Italic)
	local title = Theme.label(root, "Title", { Text = "РЕДКАЯ", Tier = "Title", Outline = 2 })
	t.eq(title.Outline:GetAttribute("BaseThickness"), Theme.TIER_OUTLINE.Title, "a tier lifts a thin outline")
	local body = Theme.label(root, "Body", { Text = "Подсказка", Tier = "Body" })
	t.eq(body.Outline:GetAttribute("BaseThickness"), Theme.TIER_OUTLINE.Body, "a tiered label gets one")
	t.eq(body.TextStrokeTransparency, 1, "the UIStroke draws it, not the thin legacy stroke")
	local dark = Theme.label(root, "Dark", { Text = "F", Tier = "Small", TextStrokeTransparency = 1 })
	t.eq(dark:FindFirstChild("Outline"), nil, "dark text on a white chip stays clean")
	local none = Theme.label(root, "None", { Text = "1 кг", Tier = "Body", Outline = false })
	t.eq(none:FindFirstChild("Outline"), nil, "Outline = false is respected")
	-- Icons: upright, outlined in Ink; a faint glyph without a contour.
	local icon = Theme.icon(root, "Icon", "🐟")
	t.eq(icon.Rotation, 0, "icons stand upright")
	t.eq(icon.Outline:GetAttribute("BaseThickness"), Theme.ICON_OUTLINE)
	local faint = Theme.icon(root, "Star", "★", { TextTransparency = 0.55 })
	t.eq(faint:FindFirstChild("Outline"), nil)
	local bare = Theme.icon(root, "Bare", "🎣", { Outline = false })
	t.eq(bare:FindFirstChild("Outline"), nil)
	-- Type scale (Montserrat is wider than Nunito: one step smaller, the same cap height).
	t.eq(UI.Type.Title, 20)
	t.eq(UI.Type.Button, 17)
	t.eq(UI.Type.Body, 15)
	t.eq(UI.Type.Small, 14)
end

tests["one kit: the sim primitives are the whole API — the v3 / v4 names are gone"] = function(t)
	for _, name in
		{
			"brick",
			"tile",
			"roundPlate",
			"candyButton",
			"pill",
			"topStud",
			"studRow",
			"studScale",
			"BZ",
			"BRICK",
		}
	do
		t.eq((Theme :: any)[name], nil, `Theme.{name} is gone`)
	end
	t.eq((UI :: any).Brick, nil, "UIConfig.Brick is gone (a face's Fill is a plain Top → Bottom)")
	local parent = frame()
	local socket = Theme.socket(parent, "IconSocket", "💡")
	t.eq(socket.BackgroundTransparency, 1, "a socket is a transparent holder")
	t.ok(socket.Icon.Outline, "… with the outlined emoji")
	local stop = Theme.simButton(parent, "Stop", "Berry", { Layout = "row", Icon = "🎣", Caption = "СМОТАТЬ" })
	t.eq(stop:GetAttribute("CandyStyle"), "sim")
	t.eq(stop.Face.Size, UDim2.fromScale(1, 1), "the face covers the button: no side band")
	local price = Theme.plate(parent, "Price", "Gold", { Icon = "💰", Text = "0" })
	t.eq(price:GetAttribute("CandyStyle"), "sim")
	t.eq(#studsIn(parent), 0, "nothing stud-like anywhere")
end

tests["palette: the reference's colours; outlines in the hue's dark shade; Ink; the PIP colour kept"] = function(t)
	local function hex(code: string): any
		return roblox.Color3.fromRGB(
			tonumber(string.sub(code, 2, 3), 16),
			tonumber(string.sub(code, 4, 5), 16),
			tonumber(string.sub(code, 6, 7), 16)
		)
	end
	-- Measured on the reference: «Магазин» green, «Индекс» blue, the egg (red) and paw (orange) squares.
	t.eq(P.Leaf.Top, hex("#8BFA0C"))
	t.eq(P.Leaf.Bottom, hex("#3FFF03"))
	t.eq(P.Leaf.Lip, hex("#0A4800"))
	t.eq(P.Sky.Top, hex("#25FCFF"))
	t.eq(P.Sky.Lip, hex("#180149"))
	t.eq(P.Berry.Bottom, hex("#F8060B"))
	t.eq(P.Sun.Bottom, hex("#F77718"))
	for _, token in
		{ "Sky", "Sun", "Leaf", "Berry", "Grape", "Gold", "Night", "Cream", "Slate", "Mint", "Water", "Pond", "Pink" }
	do
		local look = P[token]
		t.ok(look and look.Top and look.Bottom and look.Lip, `{token} kept`)
		local _, _, vEdge = look.Lip:ToHSV()
		t.ok(vEdge <= 0.36, `{token}: a dark outline ({vEdge})`)
		local _, _, vTop = look.Top:ToHSV()
		t.ok(vTop > vEdge + 0.2, `{token}: a face far lighter than its outline`)
	end
	t.eq(P.Glass.Alpha, 0.5, "the glass look")
	t.eq(UI.Ink, roblox.Color3.fromRGB(0x15, 0x17, 0x1C), "a neutral near-black Ink")
	t.eq(UI.Fishing.PipDone, roblox.Color3.fromRGB(64, 200, 96), "the e2e bot's pip colour")
	t.eq(UI.Fx.TextStrokeMin, 2, "text outlines never under 2 px")
	t.eq(UI.Fx.StrokeMax, 1.2)
	t.eq(UI.Fx.TextStrokeMax, 1.0)
	for id, look in UI.BaseSwatches do
		t.ok(look.Top and look.Bottom and look.Lip, `base {id}`)
	end
	t.ok(UI.Motion and UI.Motion.Press.Scale < 1 and UI.Motion.Press.Peak > 1, "press squash and overshoot")
end

return tests
