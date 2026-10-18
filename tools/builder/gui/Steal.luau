--[[
	Steal — the thief's widgets (stage 4, docs/stage4_design.md §6.4) in the UI v5 «Симулятор» style:
	the top banner HUD.TheftBar («🥷 КРАДЁШЬ: ОКУНЬ» with a bar filling to the server's end time,
	then «🏃 БЕГИ ЗА ОГРАДУ!» with a draining bar, the court hint on glass) and the slam
	HUD.TheftTitle («ДОБЫЧА!» / «СОРВАЛОСЬ!» with one line under it). Controller and all the
	motion: TheftController (wave 2 C). Every text comes from StealConfig.Texts, every number of
	the place from UIConfig.Theft (pure modules). Layout rules: tools/builder/Gui.luau; look and
	API: tools/builder/gui/STYLE.md.

	Names are a contract (TheftController, tests and the preview scenarios find them):
	  TheftBar       (hidden, ZIndex 32: over the sheets) the root at the top of the toast column
	                 (NotifyController.Reserve("theft", px) moves the toasts under it; Offset("theft")
	                 says where it stands when the victim's alert is up too): Theft.Width of the HUD
	                 width (≤ Theft.WidthMax px), Theft.BarHeight of its height (≈ 50 px on a phone)
	    Plate        the plate: a Night sim plate (hold), Berry (carry, fail), glass (the hint) —
	                 TheftController recolours it with UiFx.setCandy
	    Icon         a socket over the plate's left end: Icon.Icon 🥷 / 🏃 / ⏳ / 🛡️ / 🐠
	    Title        Title tier, CAPS («КРАДЁШЬ: ОКУНЬ», «БЕГИ ЗА ОГРАДУ!»; the hint — sentence case)
	    Time         italic Small «1,8 с» at the right end of the title row
	    Sub          Small «Не отходи!» / «Не попадись хозяину» (the hint's second line)
	    Bar          the progress bar: Track (a glass groove) and Track.Fill (a Berry sim pill whose
	                 X scale is the progress)
	    DogChip      a Sun plate «🐕 СОБАКА!» under the plate's right end (hidden: while Slowed)
	  TheftTitle     (hidden) the slam over the top band — Title (Theme.title: «ДОБЫЧА!» in Gold →
	                 Leaf, «СОРВАЛОСЬ!»), Sub (Small: «Окунь — в твоём садке · +$4/с» / the reason)
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

local Z = 32 -- over the sheets (30) and the base banner (20): the thief's banner is never covered

local function buildBar(hud: any)
	local root = U.new("Frame", {
		Name = "TheftBar",
		Visible = false,
		Active = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.26), -- the toast column's top (gui/Hud.luau buildToasts)
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
	Theme.socket(root, "Icon", "🥷", {
		AnchorPoint = Vector2.new(0.45, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1.05, 1.05),
		ZIndex = 4,
	})

	-- Title row: the title (Title tier) and the time at its right end; under it the Sub line
	-- and the thin bar along the plate's foot.
	label(root, "Title", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0.09, 0.05),
		Size = UDim2.fromScale(0.74, 0.46),
		Text = TextUtil.fill(TEXTS.Banner.Hold, { short = "ОКУНЬ" }),
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		Tier = "Title",
	})
	label(root, "Time", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.08),
		Size = UDim2.fromScale(0.14, 0.4),
		Text = TextUtil.fill(TEXTS.Banner.Time, { s = "3,0" }),
		TextXAlignment = Enum.TextXAlignment.Right,
		Italic = true,
		ZIndex = 4,
		Tier = "Small",
	})
	label(root, "Sub", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0.09, 0.5),
		Size = UDim2.fromScale(0.88, 0.31),
		Text = TEXTS.Banner.HoldSub,
		TextXAlignment = Enum.TextXAlignment.Left,
		Italic = true,
		ZIndex = 4,
		Tier = "Small",
	})
	local bar = U.new("Frame", {
		Name = "Bar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0.09, 0.82),
		Size = UDim2.fromScale(0.88, 0.12),
		ZIndex = 4,
	}, root)
	local track = U.new("Frame", {
		Name = "Track",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 4,
	}, bar)
	Theme.glass(track, { radius = 0.5, shine = false })
	local fill = U.new("Frame", {
		Name = "Fill",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(0, 1), -- X = the progress (0 → 1 holding; 1 → 0 carrying)
		ZIndex = 5,
	}, track)
	Theme.sim(fill, "Berry", { round = true, stroke = 0, rim = false, shine = false })

	-- «🐕 СОБАКА!» under the plate's right end (while the dog slows the thief).
	local dog = Theme.plate(root, "DogChip", "Sun", {
		Visible = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.97, 0.92),
		Size = UDim2.fromScale(0.32, 0.55),
		ZIndex = 6,
		Text = TEXTS.Banner.Dog,
		Tier = "Small",
		Radius = 0.5,
		SimOpts = { stroke = Theme.MINOR, shine = false },
		LabelProps = {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.9, 0.8),
		},
	})
	dog.Rotation = -3
end

local function buildTitle(hud: any)
	-- The slam in the top band (the thief is never fishing in a foreign court): a huge outlined
	-- word with no panel, like the base banner's name; one line under it.
	local root = U.new("Frame", {
		Name = "TheftTitle",
		Visible = false,
		Active = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromScale(1.05, 0.26),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 25,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(560, 150) }, root)
	Theme.title(root, "Title", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.fromScale(0.96, 0.66),
		Text = TEXTS.Banner.Done,
		TextGradient = { WHITE, P.Gold.Top, P.Leaf.Top, P.Leaf.Bottom },
		ZIndex = SZ.Content,
		MaxTextSize = 72,
	})
	label(root, "Sub", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.72),
		Size = UDim2.fromScale(0.96, 0.26),
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
