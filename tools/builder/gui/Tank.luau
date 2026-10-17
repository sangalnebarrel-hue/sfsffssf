--[[
	Tank — HUD.TankPanel (stage 3), the tank panel on the sheet shell (tools/builder/gui/Sheet.luau)
	in the UI v5 «Симулятор» style: the header (🐠 «САДОК», the count chip, the income, the tank's
	total value, the market chip) and the card templates the client clones per slot. Controller
	and all the motion: TankPanelController (with the client helper Controllers/Sheet.luau). Every
	text comes from TankConfig.Texts (a pure module). Layout rules: tools/builder/Gui.luau; look
	and API: tools/builder/gui/STYLE.md.

	Names are a contract (TankPanelController, tests and the preview scenarios find them):
	  TankPanel                (hidden, ZIndex 30)
	    Panel.Header.{Icon, Title, Count, Rate, Total, Market}
	      Count   a Cream chip «0/6» (Label; italic dark digits)
	      Rate    «+$0/с» green italic (UIConfig.MoneyText)
	      Total   «💵 $0 ▲» — the tank's total value now (it grows: «дорожает, чем дольше лежит»)
	      Market  a Gold chip «🏪 РЫНОК +50%» (Label), hidden: only while SellRatePct > 100
	    Panel.Close            the round Berry «✕»
	    Panel.Cards            ScrollingFrame + UIGridLayout with three hidden templates:
	      CardTemplate  a fish: a sim plate in the rarity's colours (Common here; no shine, gloss
	                    or shadow) — NameLabel (Small tier, CAPS ShortName; design §6.4 calls it
	                    "Name", but a child named Name is shadowed by Instance.Name: card.Name is
	                    "CardTemplate" — so NameLabel, like CatchCard.NameLabel), Viewport (the fish model),
	                    Mutation (a chip «✨ ×2» over the top-left corner, hidden), Rate («+$4/с»,
	                    Body tier, green italic), Growth.{Track.Fill, Label «×1.4», Max «МАКС» —
	                    a Gold stamp, hidden}, Sell (a Leaf button: Caption «💵 $45» on phones,
	                    «ПРОДАТЬ $45» on cards ≥ TankConfig.Panel.WideCard px; Gold at a stall,
	                    Berry «ТОЧНО?» while confirming)
	      EmptyTemplate an empty slot: a glass plate — Icon (a faint 🎣), Title «ПУСТО», Hint
	                    «Поймай рыбу!»
	      LockedTemplate a locked slot (the stage 5 teaser): a Slate plate — Icon 🔒, Title «ЕЩЁ
	                    МЕСТО», Hint «Скоро в магазине»
	Sizes are scales of the card (phone ≈ 112 × 160 px: every text fits its box at its tier —
	tests/stage3_rules), buttons ≥ 44 px tall on a phone.
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
local P = Theme.P
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
	local count = chip(header, "Count", "Cream", "0/6", {
		LayoutOrder = 3,
		Size = UDim2.fromScale(0.09, 0.7),
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
		Text = "💵 $0 ▲",
		TextXAlignment = Enum.TextXAlignment.Left,
		Italic = true,
		ZIndex = SZ.Content,
		Tier = "Body",
	})
	local market = chip(header, "Market", "Gold", TextUtil.fill(TEXTS.MarketChip, { bonus = BONUS }), {
		LayoutOrder = 6,
		Visible = false,
		Size = UDim2.fromScale(0.2, 0.7),
		Icon = "🏪",
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
		Position = UDim2.fromScale(0.5, 0.04),
		Size = UDim2.fromScale(0.94, 0.12),
		Text = "КАРАСИК",
		ZIndex = SZ.Content,
		Tier = "Small",
	})
	U.new("ViewportFrame", {
		Name = "Viewport",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.17),
		Size = UDim2.fromScale(0.9, 0.28),
		Ambient = rgb(200, 200, 210),
		LightColor = rgb(255, 250, 240),
		LightDirection = Vector3.new(-1, -1.4, -0.8),
		ZIndex = SZ.Content,
	}, card)
	chip(card, "Mutation", "Gold", "×2", {
		Visible = false,
		AnchorPoint = Vector2.new(0.2, 0.3),
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(0.56, 0.12),
		Rotation = -8,
		ZIndex = SZ.Top,
		Icon = "✨",
		IconScale = 1.3,
		Italic = true,
		LabelProps = {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.95, 0.5),
			Size = UDim2.fromScale(0.66, 0.8),
		},
	})
	label(card, "Rate", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(0.92, 0.1),
		Text = "+$1/с",
		TextColor3 = MONEY,
		Italic = true,
		ZIndex = SZ.Content,
		Tier = "Body",
	})

	-- Growth: a thin glass groove with the fill (×1 → ×3), the multiplier on its right; a Gold
	-- «МАКС» stamp over the whole row when the value is maxed.
	local growth = U.new("Frame", {
		Name = "Growth",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.57),
		Size = UDim2.fromScale(0.88, 0.1),
		ZIndex = SZ.Content,
	}, card)
	local track = U.new("Frame", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(0.58, 0.46),
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
	label(growth, "Label", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromScale(0.38, 1),
		Text = "×1",
		Italic = true,
		ZIndex = SZ.Content,
		Tier = "Small",
	})
	chip(growth, "Max", "Gold", TEXTS.Max, {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 1.3),
		Rotation = -4,
		ZIndex = SZ.Top,
	})

	-- Sell: a Leaf button across the card's foot (≥ 44 px tall on a phone).
	local sell = Theme.simButton(card, "Sell", "Leaf", {
		Layout = "stack",
		Caption = "💵 $0",
		Tier = "Small",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromScale(0.94, 0.28),
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
		Theme.glass(card, { radius = UI.Sim.Radius, shine = false })
	else
		Theme.sim(card, "Slate", { radius = UI.Sim.Radius, shine = false })
	end
	Theme.icon(card, "Icon", emoji, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.33),
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
