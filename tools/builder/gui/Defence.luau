--[[
	Defence — HUD.DefencePanel (stage 4, docs/stage4_design.md §6.6), the «ЗАЩИТА» sheet on the
	sheet shell (tools/builder/gui/Sheet.luau, unchanged) in the UI v5 «Симулятор» style: the
	header (🛡️ «ЗАЩИТА» and the Wallet's money on a glass chip) and one card per defence — the
	free shield, the dog, the alarm and the lock (level 1; no level pips in stage 4: the levelled
	lock is stage 5's). Controller and all the motion: DefenceController (wave 2 D; the sheet:
	Controllers/Sheet, its layout DefenceConfig.Panel). Every text comes from DefenceConfig.Texts
	(a pure module). Layout rules: tools/builder/Gui.luau; look and API: tools/builder/gui/STYLE.md.

	Names are a contract (DefenceController, tests and the preview scenarios find them):
	  DefencePanel             (hidden, ZIndex 30)
	    Panel.Header.{Icon, Title, Money} — Money: a glass chip «💵 $12 345» (Icon, Label)
	    Panel.Strip            the Night band under the header (phones: the plate is glass there)
	    Panel.Close            the round Berry «✕»
	    Panel.Cards            ScrollingFrame + UIGridLayout with the four cards (LayoutOrder 1..4):
	      ShieldCard, DogCard, AlarmCard, LockCard — each a Pond sim plate (no shine):
	        Icon     a sim disc in the defence's colour (Guard / Sun / Berry / Grape) with the
	                 outlined emoji Icon.Emoji (🛡️ / 🐕 / 🚨 / 🔐)
	        Name     Small tier CAPS («ЩИТ», «СОБАКА», «СИГНАЛИЗАЦИЯ» — «СИГНАЛКА» on cards
	                 under 120 px —, «ЗАМОК»), a box 0.96 of the card's width; the design's name
	                 (§6.1) is kept, so reach it with card:FindFirstChild("Name") — card.Name is
	                 the Instance's own name ("DogCard")
	        Effect   Small italic, two lines («Никто не украдёт 1 минуту»)
	        State    Small italic, hidden: «Замок ур. 1» / «Сильнее замки — скоро в магазине»
	        Buy      the button across the card's foot (≥ 44 px on a phone): Label (the state word —
	                 «ВКЛЮЧИТЬ», «КУПИТЬ?», «КУПЛЕНО», «ТЫ ПОД ЗАЩИТОЙ», ⏳) and Price («💵 $6 000»);
	                 the controller shows one of them and recolours the button (Guard / Gold /
	                 Berry / Leaf stamp / Slate) with UiFx.setCandy. Shield: Guard «ВКЛЮЧИТЬ»;
	                 the others: Gold with the price
	Sizes are scales of the card (phone ≈ 117 × 150 px; DefenceController sets the cells in px
	written as scales: DefenceConfig.Panel.CardAspect, CardMin), text never under 12 px.
]]

local Theme = require("./Theme")
local Sheet = require("./Sheet")

local U = Theme.U
local Enum = U.Enum
local UDim2 = U.UDim2
local Vector2 = U.Vector2

local UI = Theme.UI
local SZ = Theme.SZ
local label = Theme.label

-- Texts (pure modules, the same tables the client reads).
local DefenceConfig = U.loadPure("src/ReplicatedStorage/Shared/Config/DefenceConfig.luau")
local TextUtil = U.loadPure("src/ReplicatedStorage/Shared/TextUtil.luau")
local TEXTS = DefenceConfig.Texts
local CARDS = TEXTS.Cards
local LOCK = DefenceConfig.Lock

-- The four cards in their order: the free shield first (the one tap that matters), then the
-- defences from the cheapest kind of help to the strongest.
local ORDER = {
	{ Name = "ShieldCard", Key = "Shield", Disc = "Guard", Button = "Guard" },
	{ Name = "DogCard", Key = "Dog", Disc = "Sun", Button = "Gold" },
	{ Name = "AlarmCard", Key = "Alarm", Disc = "Berry", Button = "Gold" },
	{ Name = "LockCard", Key = "Lock", Disc = "Grape", Button = "Gold" },
}

local function effectText(key: string): string
	local card = CARDS[key]
	if key == "Lock" then
		local first = LOCK.Levels[1]
		return TextUtil.fill(card.Effect, { new = first.Hold, old = LOCK.BaseHold })
	end
	return card.Effect
end

local function buildHeader(header: any)
	-- The Wallet's money on a glass chip (DefenceController keeps it in step with the Wallet).
	local money = Theme.plate(header, "Money", "Glass", {
		LayoutOrder = 3,
		Glass = true,
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Size = UDim2.fromScale(3, 0.66),
		Icon = "💵",
		IconScale = 1.1,
		Text = "$0",
		Italic = true,
		Tier = "Body",
		Radius = 0.5,
		LabelProps = { Size = UDim2.fromScale(0.72, 0.8) },
	})
	money.ZIndex = SZ.Content
end

local function buildCard(cards: any, order: number, spec: { [string]: string })
	local texts = CARDS[spec.Key]
	local card = U.new("Frame", {
		Name = spec.Name,
		LayoutOrder = order,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, cards)
	Theme.sim(card, "Pond", { radius = UI.Sim.Radius, shine = false })

	-- The defence's colour as a sim disc with its emoji (outlined).
	local disc = U.new("Frame", {
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.03),
		Size = UDim2.fromScale(0.23, 0.23),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = SZ.Content,
	}, card)
	Theme.sim(disc, spec.Disc, { round = true, stroke = Theme.MINOR, shine = false })
	Theme.icon(disc, "Emoji", texts.Icon, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		ZIndex = SZ.Content + 1,
	})

	label(card, "Name", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.265),
		Size = UDim2.fromScale(0.96, 0.12),
		Text = texts.Name,
		ZIndex = SZ.Content,
		Tier = "Small",
	})
	label(card, "Effect", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.39),
		Size = UDim2.fromScale(0.92, 0.255),
		Text = effectText(spec.Key),
		TextWrapped = true,
		Italic = true,
		ZIndex = SZ.Content,
		Tier = "Small",
	})
	label(card, "State", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.65),
		Size = UDim2.fromScale(0.92, 0.07),
		Text = TextUtil.fill(TEXTS.LockLevel, { n = 1 }),
		Italic = true,
		ZIndex = SZ.Content,
		Tier = "Small",
	})

	-- Buy: the button across the card's foot (≥ 44 px tall on a phone).
	local buy = Theme.simButton(card, "Buy", spec.Button, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.965),
		Size = UDim2.fromScale(0.92, 0.245),
		ZIndex = SZ.Content,
		SimOpts = { stroke = Theme.MINOR },
	})
	U.new("UISizeConstraint", { MinSize = Vector2.new(0, 44) }, buy)
	local isShield = spec.Key == "Shield"
	label(buy, "Label", {
		Visible = isShield,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.62),
		Text = if isShield then TEXTS.Buy.On else TEXTS.Buy.Confirm,
		TextWrapped = true, -- («ТЫ ПОД ЗАЩИТОЙ» takes two lines on a phone card)
		ZIndex = SZ.Content,
		Tier = "Small",
	})
	label(buy, "Price", {
		Visible = not isShield,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.62),
		Text = TextUtil.fill(TEXTS.Buy.Price, { price = "$0" }),
		Italic = true,
		ZIndex = SZ.Content,
		Tier = "Small",
	})
end

local function build(hud: any): any
	local sheet = Sheet.build(hud, "DefencePanel", { Icon = "🛡️", Title = TEXTS.Title, ZIndex = 30 })
	buildHeader(sheet.header)
	for order, spec in ORDER do
		buildCard(sheet.cards, order, spec)
	end
	return sheet.root
end

return build
