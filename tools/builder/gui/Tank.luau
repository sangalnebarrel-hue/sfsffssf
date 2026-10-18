--[[
	Tank — HUD.TankPanel (stage 3), the tank panel on the sheet shell (tools/builder/gui/Sheet.luau)
	in the UI v5 «Симулятор» style: the header (🐠 «САДОК», the count chip, the income, the tank's
	total value, the market chip) and the card templates the client clones per slot. Controller
	and all the motion: TankPanelController (cards: the helper Controllers/TankCards; the sheet:
	Controllers/Sheet). Every text comes from TankConfig.Texts (a pure module). Layout rules:
	tools/builder/Gui.luau; look and API: tools/builder/gui/STYLE.md.

	Names are a contract (TankPanelController, tests and the preview scenarios find them):
	  TankPanel                (hidden, ZIndex 30)
	    Panel.Header.{Icon, Title, Count, Rate, Total, Market} — the client sizes each item to its
	              text (px written as scales of the header) and, when even the bare text widths do
	              not fit before the ✕, drops first Rate, then the Market chip's long text, then the
	              Title (🐠 stays)
	      Count   a Cream chip «0/6» (Label; italic dark digits; Gold when the tank is full)
	      Rate    «+$0/с» green italic (UIConfig.MoneyText; the Wallet right above shows the same
	              income, so it is the first to go)
	      Total   «💵 $0 📈» — the tank's total value now (it grows: «дорожает, чем дольше лежит»)
	      Market  a Gold chip «💰 РЫНОК +50%» (Icon TankConfig.Texts.MarketIcon, Label; short
	              «💰 +50%» — Texts.MarketShort — when the header is crowded), hidden: only while
	              SellRatePct > 100
	    Panel.Strip            the Night band under the header (phones: the plate is glass there)
	    Panel.Close            the round Berry «✕»
	    Panel.Cards            ScrollingFrame + UIGridLayout with three hidden templates:
	      CardTemplate  a fish: a sim plate in the rarity's colours (Common here; no shine, gloss
	                    or shadow); the client lays its rows out FROM THE BOTTOM in px written as
	                    scales (TankConfig.Panel.Card: the sell button ≥ 44 px, the income and
	                    growth row with «МАКС» always clear above it, the fish gets what is
	                    left) —
	                    NameLabel (Small tier, CAPS ShortName; design §6.4 calls it
	                    "Name", but a child named Name is shadowed by Instance.Name: card.Name is
	                    "CardTemplate" — so NameLabel, like CatchCard.NameLabel), Viewport (the
	                    fish model), Mutation (a chip «👑 ×2» over the top-left corner, tilted,
	                    hidden: Icon = the mutation's emoji, Label); one row above the sell
	                    button: Rate on its left («+$4/с», Body tier, green italic, as wide as
	                    its text; «−$4/с» red while a sale waits for «ПРОДАТЬ?») and Growth on
	                    its right ({Track.Fill — a glass pill, Label «×1.4» drawn on it, Max
	                    «МАКС» — a Gold stamp over it, inside the row's height, hidden}),
	                    Sell (a Leaf button: Caption «💵 $45»; «ПРОДАТЬ $45» on cards ≥
	                    TankConfig.Panel.WideCard px when the panel's longest price fits — one
	                    style for the whole panel; Gold at a stall, Berry «ПРОДАТЬ?» while
	                    confirming («ТОЧНО?» on a card too narrow for it), Slate «⏳» while the
	                    server answers)
	      EmptyTemplate an empty slot: a glass plate (darker on a phone, where the sheet is glass
	                    too: TankConfig.Panel.EmptyAlpha) — Icon (a faint 🎣), Title «ПУСТО», Hint
	                    «Поймай рыбу!»
	      LockedTemplate a locked slot (the stage 5 teaser): a Slate plate — Icon 🔒, Title «ЕЩЁ
	                    МЕСТО», Hint «Скоро в магазине»
	Sizes are scales of the card (phone ≈ 110 × 141 px: every text fits its box at its tier —
	tests/stage3_rules), the sell button ≥ 44 px tall on a phone; the fish card's rows below are
	the phone's defaults until the client lays them out for the real card.
]]

local Theme = require("./Theme")
local Sheet = require("./Sheet")

local U = Theme.U
local Enum = U.Enum
local UDim2 = U.UDim2
local Vector2 = U.Vector2
local Vector3 = U.Vector3
local rgb = U.rgb

local UI = Theme.UI
local SZ = Theme.SZ
local INK = Theme.INK
local label = Theme.label

-- Texts (pure modules, the same tables the client reads).
local TankConfig = U.loadPure("src/ReplicatedStorage/Shared/Config/TankConfig.luau")
local EconomyConfig = U.loadPure("src/ReplicatedStorage/Shared/Config/EconomyConfig.luau")
local TextUtil = U.loadPure("src/ReplicatedStorage/Shared/TextUtil.luau")
local TEXTS = TankConfig.Texts

local MONEY = UI.MoneyText
local BONUS = EconomyConfig.MarketRatePct - 100

-- A Small-tier caption chip (Cream / Gold): a round plate with its text in the middle.
local function chip(parent: any, name: string, token: string, text: string, props: { [string]: any }): any
	local base: { [string]: any } = {
		Text = text,
		Tier = "Small",
		Radius = 0.5,
		SimOpts = { stroke = Theme.MINOR, shine = false },
		LabelProps = {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.8),
		},
	}
	for key, value in props do
		base[key] = value
	end
	return Theme.plate(parent, name, token, base)
end

local function buildHeader(header: any)
	local count = chip(header, "Count", "Cream", TextUtil.fill(TEXTS.Count, { count = 0, slots = 6 }), {
		LayoutOrder = 3,
		Size = UDim2.fromScale(0.09, 0.66),
		Italic = true,
		LabelProps = {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.8),
			Outline = false,
			TextColor3 = INK,
			TextStrokeTransparency = 1,
		},
	})
	count.ZIndex = SZ.Content
	label(header, "Rate", {
		LayoutOrder = 4,
		Size = UDim2.fromScale(0.16, 0.7),
		Text = "+$0/с",
		TextColor3 = MONEY,
		TextXAlignment = Enum.TextXAlignment.Left,
		Italic = true,
		ZIndex = SZ.Content,
		Tier = "Body",
	})
	label(header, "Total", {
		LayoutOrder = 5,
		Size = UDim2.fromScale(0.2, 0.7),
		Text = TextUtil.fill(TEXTS.TotalDone, { money = "$0" }),
		TextXAlignment = Enum.TextXAlignment.Left,
		Italic = true,
		ZIndex = SZ.Content,
		Tier = "Body",
	})
	local market = chip(header, "Market", "Gold", TextUtil.fill(TEXTS.MarketChip, { bonus = BONUS }), {
		LayoutOrder = 6,
		Visible = false,
		Size = UDim2.fromScale(0.24, 0.66),
		Icon = TEXTS.MarketIcon,
		IconScale = 1.2,
		LabelProps = {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.95, 0.5),
			Size = UDim2.fromScale(0.74, 0.8),
		},
	})
	market.ZIndex = SZ.Content
end

-- The fish card (Common colours; the client recolours it with UiFx.setCandy by rarity).
local function buildCard(cards: any)
	local card = U.new("Frame", {
		Name = "CardTemplate",
		Visible = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, cards)
	local common = UI.Rarity.Common
	Theme.sim(card, { Top = common.Top, Bottom = common.Bottom, Lip = common.Lip }, {
		radius = UI.Sim.Radius,
		shine = false,
	})
	label(card, "NameLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.03),
		Size = UDim2.fromScale(0.94, 0.12),
		Text = "КАРАСИК",
		ZIndex = SZ.Content + 1, -- (over the fish: the viewport reaches under the name)
		Tier = "Small",
	})
	U.new("ViewportFrame", {
		Name = "Viewport",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.09),
		Size = UDim2.fromScale(0.92, 0.47),
		Ambient = rgb(200, 200, 210),
		LightColor = rgb(255, 250, 240),
		LightDirection = Vector3.new(-1, -1.4, -0.8),
		ZIndex = SZ.Content,
	}, card)
	chip(card, "Mutation", "Gold", "×2", {
		Visible = false,
		AnchorPoint = Vector2.new(0.06, 0.6), -- (over the corner, above the name; the strip clips sideways)
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(0.56, 0.13),
		Rotation = -8,
		ZIndex = SZ.Top,
		Icon = "👑",
		IconScale = 1.3,
		Italic = true,
		LabelProps = {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.93, 0.5),
			Size = UDim2.fromScale(0.62, 0.8),
		},
	})
	-- One row above the sell button: the income on the left (Rate, sized to its text by the
	-- client), the growth on the right (Growth: a glass pill with the fill ×1 → ×3 and «×1.4» drawn
	-- on it; a Gold «МАКС» stamp over it when the value is maxed). The fish gets the freed row.
	-- (the defaults hold the longest «−$1 125/с» at full size on a 112 px card — tests/stage3_rules;
	-- the client gives the rate only its own text's width and the pill the rest)
	label(card, "Rate", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0.04, 0.575),
		Size = UDim2.fromScale(0.7, 0.11),
		Text = "+$1/с",
		TextColor3 = MONEY,
		TextXAlignment = Enum.TextXAlignment.Left,
		Italic = true,
		ZIndex = SZ.Content + 1,
		Tier = "Body",
	})
	local growth = U.new("Frame", {
		Name = "Growth",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.96, 0.575),
		Size = UDim2.fromScale(0.42, 0.11),
		ZIndex = SZ.Content,
	}, card)
	local track = U.new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1, 0.66),
		ZIndex = SZ.Content,
	}, growth)
	Theme.glass(track, { radius = 0.5, shine = false })
	local fillBar = U.new("Frame", {
		Name = "Fill",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(0, 1), -- X = (growth − 1) / (Cap − 1)
		ZIndex = SZ.Content,
	}, track)
	Theme.sim(fillBar, "Leaf", { round = true, stroke = 0, rim = false, shine = false })
	-- «×1.4» on the pill (outlined white, over the fill)
	label(growth, "Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 1),
		Text = TextUtil.fill(TEXTS.Growth, { mult = 1 }),
		Italic = true,
		ZIndex = SZ.Content + 1,
		Tier = "Small",
	})
	-- (the stamp stays inside the row's height: the client keeps the row clear of the sell button
	-- by both outlines and the stamp's tilt — TankCards; its text fills the chip: ≥ 12 px on a phone)
	chip(growth, "Max", "Gold", TEXTS.Max, {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Rotation = -2,
		ZIndex = SZ.Top,
		LabelProps = {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.9, 0.92),
		},
	})

	-- Sell: a Leaf button across the card's foot (≥ 44 px tall on a phone).
	local sell = Theme.simButton(card, "Sell", "Leaf", {
		Layout = "stack",
		Caption = TextUtil.fill(TEXTS.SellPhone, { price = "$0" }),
		Tier = "Small",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.965),
		Size = UDim2.fromScale(0.92, 0.28),
		ZIndex = SZ.Content,
		SimOpts = { stroke = Theme.MINOR },
	})
	U.new("UISizeConstraint", { MinSize = Vector2.new(0, 44) }, sell)
end

-- An empty or a locked slot: a plate with a big icon, a CAPS title and a hint (two lines).
local function buildSlotCard(cards: any, name: string, glass: boolean, emoji: string, title: string, hint: string)
	local card = U.new("Frame", {
		Name = name,
		Visible = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
	}, cards)
	if glass then
		-- (on a phone, where the sheet is glass too, the client makes it darker: TankConfig.Panel.EmptyAlpha)
		Theme.glass(card, { radius = UI.Sim.Radius, shine = false })
	else
		Theme.sim(card, "Slate", { radius = UI.Sim.Radius, shine = false, rim = false })
	end
	Theme.icon(card, "Icon", emoji, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromScale(0.6, 0.3),
		TextTransparency = if glass then 0.45 else 0,
	})
	label(card, "Title", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.56),
		Size = UDim2.fromScale(0.92, 0.12),
		Text = title,
		ZIndex = SZ.Content,
		Tier = "Small",
	})
	label(card, "Hint", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.7),
		Size = UDim2.fromScale(0.92, 0.24),
		Text = hint,
		TextWrapped = true,
		Italic = true,
		ZIndex = SZ.Content,
		Tier = "Small",
	})
end

local function build(hud: any): any
	local sheet = Sheet.build(hud, "TankPanel", { Icon = "🐠", Title = TEXTS.Title, ZIndex = 30 })
	buildHeader(sheet.header)
	buildCard(sheet.cards)
	buildSlotCard(sheet.cards, "EmptyTemplate", true, "🎣", TEXTS.Empty, TEXTS.EmptyHint)
	buildSlotCard(sheet.cards, "LockedTemplate", false, "🔒", TEXTS.Locked, TEXTS.LockedHint)
	return sheet.root
end

return build
