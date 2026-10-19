--[[
	Steal — the thief's widgets (stage 4, docs/stage4_design.md §6.4 rev. 3) in the UI v5
	«Симулятор» style: the banner HUD.TheftBar in the BOTTOM band (under the thief and the stock
	«Украсть» prompt: from his follow camera the robbed display fills the top-centre band, where
	the status stack and the toasts are — B1-01) — «🥷 КРАДЁШЬ: ОКУНЬ» with a bar filling to the
	server's end time, «🏃 БЕГИ ЗА ОГРАДУ!» with a draining bar, «СОРВАЛОСЬ!» with the reason, the
	court hint and the "why not" reasons on glass — and the slam HUD.TheftTitle («ДОБЫЧА!» with one
	line under it) in the same band. Controller and all the motion: TheftController (wave 2 C; it
	places both in px of the HUD, written as scales: between the thumbstick and the Jump button,
	≥ UIConfig.Theft.Bar.Gap px from them). Every text comes from StealConfig.Texts, every number
	of the place from UIConfig.Theft (pure modules). Layout rules: tools/builder/Gui.luau; look and
	API: tools/builder/gui/STYLE.md.

	Names are a contract (TheftController, tests and the preview scenarios find them):
	  TheftBar       (hidden, ZIndex 32: over the sheets) the root in the bottom band, centred:
	                 Theft.Width of the HUD width (≤ Theft.WidthMax px), Theft.BarHeight of its
	                 height (≈ 50 px on a phone), its top at Theft.Bar.Top of the HUD height
	    Plate        the plate: a Night sim plate (hold), Berry (carry, fail), glass (hints) —
	                 TheftController recolours it with UiFx.setCandy
	    Icon         a socket over the plate's left end: Icon.Icon 🥷 / 🏃 / 💨 / ⏳ / 🛡️ / 🐠
	    Title        Title tier, CAPS («КРАДЁШЬ: ОКУНЬ», «БЕГИ ЗА ОГРАДУ!», «СОРВАЛОСЬ!»), the
	                 whole width of the plate's content, the upper half
	    Bar          the progress bar (§6.1 Bar.{Track, Fill}), the lower half: a chunky pill
	                 (0.36 of the plate: ≥ 16 px on a phone — the thumb hides the stock prompt's
	                 ring, so this is the progress he sees). Track — a glass groove over the
	                 whole bar; Fill — its sibling over it (a sim pill with its outline, Berry
	                 while holding, Gold while carrying: its X scale is the progress)
	    Sub          Small italic «Не отходи!» / «Не попадись хозяину», INSIDE the bar at its
	                 left end (white with the dark outline: reads on the fill and on the groove)
	    Time         italic Small «1,8 с» inside the bar at its right end
	    Reason       (hidden) «СОРВАЛОСЬ!»'s reason under the title: Body tier, italic, the whole
	                 content width (TheftController sizes the plate to the longer of the two)
	    Line         the hint on glass (hidden; Body tier, italic, two even lines at most: the
	                 court hint, the "why not" reasons, «Подожди секунду») — laid out like the
	                 fishing Hint's label, so FishingLayout.hintWidth sizes the pill to its text
	    DogChip      a Sun plate «СОБАКА!» with 🐕 in its own socket over its left end
	                 (IconSocket.Icon, the chip's height), over the plate's right end (hidden:
	                 while Slowed; above it, not under: the band's foot is the screen's bottom)
	  TheftTitle     (hidden) the slam in the bottom band — Title (Theme.title: «ДОБЫЧА!» in Gold →
	                 Leaf), Sub (Body: «Окунь — в твоём садке · +$4/с»)
	Sizes are scales only, capped by UISizeConstraint on big screens; text never under 12 px.
]]

local Theme = require("./Theme")

local U = Theme.U
local Enum = U.Enum
local UDim2 = U.UDim2
local Vector2 = U.Vector2

local UI = Theme.UI
local P = Theme.P
local SZ = Theme.SZ
local WHITE = Theme.WHITE
local label = Theme.label

-- Texts and numbers (pure modules, the same tables the client reads).
local StealConfig = U.loadPure("src/ReplicatedStorage/Shared/Config/StealConfig.luau")
local TextUtil = U.loadPure("src/ReplicatedStorage/Shared/TextUtil.luau")
local TEXTS = StealConfig.Texts
local THEFT = UI.Theft
local BAR = THEFT.Bar

local Z = 32 -- over the sheets (30) and the base banner (20): the thief's banner is never covered
local CONTENT_X = 0.1 -- the content starts right of the overhanging socket
local CONTENT_W = 0.87
local TITLE_Y, TITLE_H = 0.05, 0.44 -- the title: the upper half
local BAR_Y, BAR_H = 0.53, 0.36 -- the bar (with Sub and Time inside): the lower half
local REASON_Y, REASON_H = 0.5, 0.42 -- «СОРВАЛОСЬ!»'s reason, where the bar would be
local TEXT_PAD = 0.025 -- Sub / Time inside the bar's round ends

local function buildBar(hud: any)
	local root = U.new("Frame", {
		Name = "TheftBar",
		Visible = false,
		Active = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, BAR.Top), -- the bottom band (TheftController moves it)
		Size = UDim2.fromScale(THEFT.Width, THEFT.BarHeight),
		ZIndex = Z,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(THEFT.WidthMax, 84) }, root)

	-- The plate (Night while holding; TheftController recolours it).
	local plate = U.new("Frame", {
		Name = "Plate",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, root)
	Theme.sim(plate, "Night", { radius = UI.Sim.PlateRadius, shine = false })

	-- 🥷 over the plate's left end (a socket: TheftController swaps the emoji).
	Theme.socket(root, "Icon", TEXTS.Icons.Hold, {
		AnchorPoint = Vector2.new(0.45, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1.05, 1.05),
		ZIndex = 4,
	})

	-- The title over the whole content width (the upper half); under it the chunky bar with
	-- the Sub line and the time written inside it (the lower half).
	label(root, "Title", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(CONTENT_X, TITLE_Y),
		Size = UDim2.fromScale(CONTENT_W, TITLE_H),
		Text = TextUtil.fill(TEXTS.Banner.Hold, { short = "ОКУНЬ" }),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		Tier = "Title",
	})
	local bar = U.new("Frame", {
		Name = "Bar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(CONTENT_X, BAR_Y),
		Size = UDim2.fromScale(CONTENT_W, BAR_H),
		ZIndex = 4,
	}, root)
	local track = U.new("Frame", {
		Name = "Track",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	}, bar)
	Theme.glass(track, { radius = 0.5, shine = false })
	-- The fill is the Track's sibling (§6.1 Bar.{Track, Fill}), over the same box: a sim pill
	-- with its dark outline and a gloss (the progress reads as a solid candy, not a hairline).
	local fill = U.new("Frame", {
		Name = "Fill",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(0, 1), -- X = the progress (0 → 1 holding; 1 → 0 carrying)
		ZIndex = 6,
	}, bar)
	Theme.sim(fill, "Berry", { round = true, stroke = Theme.MINOR, rim = false, shine = false, gloss = true })
	-- «Не отходи!» and «1,8 с» written inside the bar (over the fill).
	label(root, "Sub", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(CONTENT_X + TEXT_PAD, BAR_Y),
		Size = UDim2.fromScale(0.6, BAR_H),
		Text = TEXTS.Banner.HoldSub,
		TextXAlignment = Enum.TextXAlignment.Left,
		Italic = true,
		ZIndex = 9,
		Tier = "Small",
	})
	label(root, "Time", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(CONTENT_X + CONTENT_W - TEXT_PAD, BAR_Y),
		Size = UDim2.fromScale(0.22, BAR_H),
		Text = TextUtil.fill(TEXTS.Banner.Time, { s = "3,0" }),
		TextXAlignment = Enum.TextXAlignment.Right,
		Italic = true,
		ZIndex = 9,
		Tier = "Small",
	})
	-- «СОРВАЛОСЬ!»'s reason under the title (no bar then).
	label(root, "Reason", {
		Visible = false,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(CONTENT_X, REASON_Y),
		Size = UDim2.fromScale(CONTENT_W, REASON_H),
		Text = TEXTS.Cancel.shield,
		TextXAlignment = Enum.TextXAlignment.Left,
		Italic = true,
		ZIndex = 4,
		Tier = "Body",
	})

	-- The hint on glass: one or two even lines (the fishing Hint's label box: 0.78 of the pill,
	-- right-anchored at 0.94 — FishingLayout.hintWidth fits the pill to it).
	label(root, "Line", {
		Visible = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.94, 0.5),
		Size = UDim2.fromScale(0.78, 0.9),
		Text = TEXTS.Hint.Touch,
		TextWrapped = true,
		Italic = true,
		ZIndex = 4,
		Tier = "Body",
	})

	-- «🐕 СОБАКА!» over the plate's right end (while the dog slows the thief): the 🐕 in its own
	-- socket at the chip's height over its left end, «СОБАКА!» beside it.
	local dog = Theme.plate(root, "DogChip", "Sun", {
		Visible = false,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.97, 0.16),
		Size = UDim2.fromScale(0.3, 0.55),
		ZIndex = 6,
		Icon = TEXTS.Icons.Dog,
		Socket = true,
		IconScale = 1.25,
		Text = TEXTS.Banner.Dog,
		Tier = "Small",
		Radius = 0.5,
		SimOpts = { stroke = Theme.MINOR, shine = false },
		LabelProps = {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.94, 0.5),
			Size = UDim2.fromScale(0.68, 0.8),
		},
	})
	dog.Rotation = -3
end

local function buildTitle(hud: any)
	-- The slam in the bottom band (where the bar was): a huge outlined word with no panel, like
	-- the base banner's name; one line under it. TheftController places it like the bar.
	local root = U.new("Frame", {
		Name = "TheftTitle",
		Visible = false,
		Active = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, BAR.TitleTop),
		Size = UDim2.fromScale(THEFT.Width, BAR.TitleHeight),
		ZIndex = 25,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(THEFT.WidthMax, 170) }, root)
	Theme.title(root, "Title", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 0.66),
		Text = TEXTS.Banner.Done,
		TextGradient = { WHITE, P.Gold.Top, P.Leaf.Top, P.Leaf.Bottom },
		ZIndex = SZ.Content,
		MaxTextSize = 72,
	})
	label(root, "Sub", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.fromScale(1, 0.28),
		Text = "",
		ZIndex = SZ.Content,
		Tier = "Body",
	})
end

local function build(hud: any)
	buildBar(hud)
	buildTitle(hud)
end

return build
