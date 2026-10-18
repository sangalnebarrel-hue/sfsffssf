--[[
	Hud — the HUD chrome in the UI v5 «Симулятор» style (the reference for the other builders:
	chunky gradient buttons with a thick outline in a dark shade of their hue, outlined emoji,
	panel-less big italic numbers and outlined titles): the status stack (base badge, the Wallet),
	the right button column (САДОК, Home), the toast column, the base-assignment banner (built
	with the status stack: it flies into the badge) and the off-screen trophy chip. Controllers:
	HudController (badge, banner, Home, the chrome's micro-life), MoneyController (the Wallet),
	TankButtonController (САДОК), NotifyController (toasts, trophy chip).
	Layout rules: tools/builder/Gui.luau; look and API: tools/builder/gui/STYLE.md.

	Names are a contract (controllers and tests find them): Status.BaseBadge.{Swatch, Label,
	FlagSocket.Flag}, Status.Wallet.{Money.{Icon, Label, Back}, Rate} (MoneyController),
	RightButtons.TankButton.{Icon, Caption, Count.Label, Badge} (TankButtonController),
	RightButtons.HomeButton.{Icon, Caption, Cooldown, CooldownText, Badge},
	Toasts.ToastTemplate.{Label, IconSocket.Icon}, BaseBanner.{Caption, NameLabel,
	FlagSocket.Flag}, TrophyPointer.{Body.IconSocket.Icon, Tip, BaseRing.Stroke} (NotifyController:
	the chip pointing at someone else's off-screen light pillar). Everything else (Lip, Rim, Shine,
	NameLabelShadow, …) is decoration. Stage 3: the catch counter is gone — its row is the Wallet.

	The widgets (Theme.sim and friends; content at Theme.SZ.Content):
	  BaseBadge     a label plate in the base colour (Theme.plate shape), the 🚩 overhanging its
	                left end, the name in CAPS («ЛАЗУРНАЯ БАЗА», Title tier);
	  Wallet        the reference's panel-less «💵 $0»: an outlined 💵 at −8° and a big italic
	                MoneyText-green number with the display outline, the income «+$42/с» beside it
	                (smaller italic green); a glass «$…» pill while the data loads (Money.Back);
	                MoneyController sizes the row to its text so the group stays centred;
	  TankButton    a square aqua button above Home: 🐠 «САДОК», the chip «0/6» in its top-left
	                corner, a hidden red «!» on its top-right one (the first fish ever: open me);
	  HomeButton    a square purple button: 🏠 big in the middle, «ДОМОЙ» on its bottom edge, a
	                hidden red «!» badge (the shop stage);
	  ToastTemplate a label plate in the kind's colour with the kind's emoji overhanging its left end;
	  BaseBanner    the reference title: «ТВОЯ БАЗА» over a huge outlined «ЛАЗУРНАЯ!» in the base
	                colours with a drop shadow, a waving 🚩, no panel;
	  TrophyPointer a round gold button with 🌟, a gold arrow tip, a ring in the catcher's colour.
	Only the action button idles (shine / breathing); the chrome stays calm.
]]

local Theme = require("./Theme")

local U = Theme.U
local Enum = U.Enum
local UDim = U.UDim
local UDim2 = U.UDim2
local Vector2 = U.Vector2

local UI = Theme.UI
local P = Theme.P
local SZ = Theme.SZ
local INK = Theme.INK
local WHITE = Theme.WHITE
local SIM = UI.Sim
local corner = Theme.corner
local label = Theme.label

local function buildBaseBanner(hud: any)
	-- The moment the base is assigned: the reference's huge centred title — small «ТВОЯ БАЗА» over
	-- a big outlined «ЛАЗУРНАЯ!» in the base colours (HudController paints its TextFill), a waving
	-- 🚩, rays and confetti behind, no panel; after ~2 s HudController shrinks it into the badge.
	-- Never takes input.
	local banner = U.new("Frame", {
		Name = "BaseBanner",
		Visible = false,
		Active = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		-- (Clear of the chat window, and ≥ 16 px under the status stack on a notched phone. On the
		-- small 667 px phone «ВЗЯТЬ» stands under the name's end: HudController lifts the banner
		-- until the name keeps 16 px above the disc — V-02.)
		Position = UDim2.fromScale(0.5, 0.46),
		Size = UDim2.fromScale(1.05, 0.3),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 20,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(560, 170) }, banner)
	Theme.socket(banner, "FlagSocket", "🚩", {
		IconName = "Flag",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.09, 0.56),
		Size = UDim2.fromScale(0.8, 0.8),
		Rotation = -8,
		ZIndex = SZ.Content + 1,
	})
	label(banner, "Caption", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.56, 0.17),
		Size = UDim2.fromScale(0.74, 0.28),
		Text = "ТВОЯ БАЗА",
		ZIndex = SZ.Content,
		Tier = "Button",
	})
	-- (Anchored at its baseline: the slam grows it up and sideways, never down onto «ВЗЯТЬ».)
	Theme.title(banner, "NameLabel", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.56, 0.92),
		Size = UDim2.fromScale(0.84, 0.6),
		Text = "ЛАЗУРНАЯ!",
		TextGradient = { WHITE, WHITE, P.Leaf.Top, P.Leaf.Bottom },
		ZIndex = SZ.Content,
		MaxTextSize = 72,
	})
end

local function buildStatus(hud: any)
	local status = U.new("Frame", {
		Name = "Status",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.02), -- room for the flag overhanging the badge's top
		Size = UDim2.fromScale(0.9, 0.25),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}, hud)
	-- (Capped like a 720p screen: a 1080p desktop keeps the proportions, not a 100 px badge.)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(480, 170) }, status)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0.05, 0),
	}, status)

	-- "Your base" badge: a label plate in the base colour (HudController paints it with the base's
	-- swatch, UIConfig.BaseSwatches; the face is named Swatch), the 🚩 overhanging its left end
	-- (a transparent holder, tilted like a sticker; 60 % of it hangs off the plate with a thick
	-- contour, so the red 🚩 still reads on the red base's plate). LayoutOrder 20; the Wallet
	-- (30) is the row under it; the Stage 4 shield timer docks at the badge's right end.
	local badge = U.new("Frame", {
		Name = "BaseBadge",
		LayoutOrder = 20,
		Size = UDim2.fromScale(0.8, 0.36),
	}, status)
	Theme.sim(badge, "Slate", { faceName = "Swatch", radius = SIM.PlateRadius })
	Theme.socket(badge, "FlagSocket", "🔎", {
		IconName = "Flag",
		IconOutline = 4,
		AnchorPoint = Vector2.new(0.6, 0.55),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1.25, 1.25),
		Rotation = 8,
		ZIndex = SZ.Content + 1,
	})
	label(badge, "Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.56, 0.5),
		Size = UDim2.fromScale(0.78, 0.8),
		Text = "ИЩЕМ БАЗУ…",
		ZIndex = SZ.Content,
		Tier = "Title",
	})

	-- Wallet (stage 3, the catch counter's old row): the reference's panel-less «💵 $0» — Money
	-- is a Theme.stat (the outlined 💵 at −8° and a big italic number in MoneyText green with the
	-- display outline), Rate the income «+$42/с» in a smaller italic green beside it (Button tier;
	-- hidden while the income is 0). One centred row (UIListLayout) 0.94 of the stack wide; the
	-- stack does not grow (phones have no room under it). Money 0.64 / Rate 0.34 are the builder's
	-- shares: MoneyController fits the row to its text (the 💵, the number, a gap, the rate — the
	-- group stays centred under the badge; the number shrinks only when the row is full) and
	-- re-fits it when the screen or the digit count changes. Money.Back is a hidden glass pill:
	-- while the player's data loads longer than 3 s the money shows on glass with «$…». Hidden
	-- until the data is loaded (MoneyController).
	local wallet = U.new("Frame", {
		Name = "Wallet",
		LayoutOrder = 30,
		Visible = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(0.94, 0.38),
	}, status)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
	}, wallet)
	local money = Theme.stat(wallet, "Money", "💵", {
		LayoutOrder = 1,
		Size = UDim2.fromScale(0.64, 1),
		Text = "$0",
		-- (the bill about as tall as the digits, like the reference; its emoji box — a line tall —
		-- keeps 16 px to the toasts below and to a minigame docked beside the row on small phones)
		IconScale = 0.85,
		Color = UI.MoneyText,
		MaxTextSize = 48,
		MinTextSize = 16,
	})
	local back = U.new("Frame", {
		Name = "Back",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.2, 1),
		ZIndex = SZ.Behind,
	}, money)
	Theme.glass(back, { radius = 0.5 })
	label(wallet, "Rate", {
		LayoutOrder = 2,
		Visible = false,
		Size = UDim2.fromScale(0.34, 0.6),
		Text = "+$0/с",
		TextColor3 = UI.MoneyText,
		TextXAlignment = Enum.TextXAlignment.Left,
		Italic = true,
		Tier = "Button",
	})

	buildBaseBanner(hud)
end

local function buildRightButtons(hud: any)
	local right = U.new("Frame", {
		Name = "RightButtons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.99, 0.64), -- bottom edge; the column grows upwards
		Size = UDim2.fromScale(0.18, 0.6), -- 3 square buttons (0.84 of it) + gaps fit in 0.6H
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(104, 380) }, right)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		-- (≈ 0.12 of a button: the reference's column rhythm; stage 3: two buttons — the
		-- off-screen trophy chip above them keeps 16 px on a notched phone)
		Padding = UDim.new(0.035, 0),
	}, right)

	-- "Home": a square purple button (Grape: never the green «ЛОВИ!» nor the blue «ЗАБРОСИТЬ»),
	-- 🏠 big in the middle and «ДОМОЙ» ON its bottom edge (the reference squares are icon-only;
	-- ours keep the word for kids), shown once the player has a base.
	local home = Theme.simButton(right, "HomeButton", "Grape", {
		LayoutOrder = 100, -- bottom of the column; Shop/Shield go above it later
		Size = UDim2.fromScale(1, 0.28), -- (stage 3: two buttons in the column — the trophy chip above keeps 16 px)
		Visible = false,
		Layout = "square",
		Icon = "🏠",
		Caption = "ДОМОЙ",
		Tier = "Small",
		-- (5 at 720, a little under the plates' 6: the column keeps 16 px to «СМОТАТЬ» on a tablet.)
		SimOpts = { stroke = 5 },
	})
	-- Cooldown: a dark veil over the whole button that drains downwards (HudController moves the
	-- hard edge of the "Drain" gradient: Offset.Y -0.5 = fully covered → 0.5 = clear), plus the
	-- seconds left in big italic digits; «ДОМОЙ» reads «ЖДИ» over the veil.
	local cooldown = U.new("Frame", {
		Name = "Cooldown",
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = SZ.Overlay,
	}, home)
	corner(cooldown, SIM.Radius)
	U.new("UIGradient", {
		Name = "Drain",
		Rotation = 90,
		Offset = Vector2.new(0, -0.5),
		Transparency = Theme.numbers({ { 0, 1 }, { 0.495, 1 }, { 0.5, 0 }, { 1, 0 } }),
	}, cooldown)
	label(home, "CooldownText", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.8, 0.62),
		Text = "",
		Italic = true,
		Outline = Theme.DISPLAY_OUTLINE,
		ZIndex = SZ.Top,
		MaxTextSize = 56,
		TextGradient = { WHITE, P.Gold.Top },
	})
	-- The red «!» of the reference on the top-right corner: hidden (the shop stage lights it).
	Theme.badge(home, "Badge")

	-- «САДОК» (stage 3): the same square recipe as Home, one slot above it (LayoutOrder 90), in
	-- aqua Water (never Grape «ДОМОЙ», Leaf «ЛОВИ!» or Sky «ЗАБРОСИТЬ»), 🐠 in the middle (a little
	-- lower right, clear of the chip) and «САДОК» on its bottom edge; Count — a small Cream chip
	-- «0/6» (italic dark digits) in its top-left corner (Gold when the tank is full), Badge — the
	-- hidden red «!» on its top-right corner (the first fish ever: open me). Hidden until the base
	-- and the data are there (TankButtonController).
	local tank = Theme.simButton(right, "TankButton", "Water", {
		LayoutOrder = 90,
		Size = UDim2.fromScale(1, 0.28),
		Visible = false,
		Layout = "square",
		Icon = "🐠",
		Caption = "САДОК",
		Tier = "Small",
		SimOpts = { stroke = 5 },
	})
	-- (the chip sits in the top-left corner, inside the button's outline: nothing of it sticks
	-- out of the column — the trophy chip above it, a wide toast and «СМОТАТЬ» beside it keep
	-- their 16 px; it grows rightwards from its left edge when its 40 px minimum kicks in)
	local count = Theme.plate(tank, "Count", "Cream", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.05, 0.17),
		Size = UDim2.fromScale(0.5, 0.24),
		ZIndex = SZ.Top + 1,
		Text = "0/6",
		Italic = true,
		Tier = "Small",
		Radius = 0.5,
		SimOpts = { stroke = Theme.MINOR, shine = false },
		LabelProps = {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.8),
			Outline = false,
			TextColor3 = INK,
			TextStrokeTransparency = 1,
		},
	})
	-- (never so small that «12/12» drops under 12 px: 40 × 20 px on the smallest phone)
	U.new("UISizeConstraint", { MinSize = Vector2.new(40, 20) }, count)
	-- 🐠 smaller and lower right than Home's 🏠 (its bottom just under the caption's outline):
	-- its head and eye (the fish faces left) clear the chip — on a phone too, where the chip is
	-- at its 40 × 20 px minimum — so «САДОК» reads as a fish next to the Sky «ЗАБРОСИТЬ» (K-23).
	local fish = tank:FindFirstChild("Icon")
	if fish then
		fish.Position = UDim2.fromScale(0.58, 0.55)
		fish.Size = UDim2.fromScale(0.5, 0.5)
	end
	-- «!» on the top-right corner like the reference's, but tucked in: the column hugs the
	-- screen's right edge (≈ 1 % of the width away), so the disc overhangs upwards, not out of
	-- the screen — even at the top of its pop (1.25) on a tablet / desktop.
	Theme.badge(tank, "Badge", {
		Position = UDim2.fromScale(0.84, 0.1),
		Size = UDim2.fromScale(0.4, 0.4),
	})
end

local function buildToasts(hud: any)
	-- Width follows the screen WIDTH (RelativeXY), so the column never reaches the corners.
	-- No UIListLayout: NotifyController stacks the toasts itself (slots of 0.28 + 0.08 of the
	-- column height; big rarity toasts are taller), sizes each to its text and lets them slide.
	-- The column starts right under the status stack (0.26 of the HUD: stage 3, under the
	-- Wallet row, which is always shown): on a phone one toast ends above the avatar's head.
	-- Without a touch screen NotifyController narrows it to 512 px, clear of the Roblox chat
	-- window in the top-left corner.
	-- ZIndex 0: under the status stack — a toast drops into its slot from above (NotifyController)
	-- and passes behind the Wallet row on the way, never over the money.
	local toasts = U.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.26),
		Size = UDim2.fromScale(0.56, 0.34),
		ZIndex = 0,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(640, 190) }, toasts)

	-- A label plate per toast: NotifyController clones it and recolours it by kind
	-- (UIConfig.ToastKinds: Sky / Leaf / Sun / Berry / base colour / Gold / Night in a rainbow
	-- outline) and puts the kind's emoji into the holder overhanging its left end.
	Theme.plate(toasts, "ToastTemplate", "Sky", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 0.28),
		Icon = UI.ToastKinds.info.Icon,
		Socket = true,
		IconScale = 1.05,
		Text = "",
		Tier = "Body",
		LabelProps = {
			Position = UDim2.fromScale(0.96, 0.5),
			Size = UDim2.fromScale(0.8, 0.74),
			TextWrapped = true, -- long texts: NotifyController makes the toast taller (two lines)
		},
	})

	-- Someone else's Legendary / Mythic catch whose light pillar is off-screen: NotifyController
	-- clones this per catch to the screen edge on the pillar's side (FishingFxController.OtherTrophy)
	-- — a round button in the rarity colours (Gold / rainbow) with the outlined 🌟 / 🌈, in a ring
	-- of the catcher's base colour, its Tip (an arrowhead in the rarity colour, out from under the
	-- disc) pointing at the edge (built on the right; mirrored for the left). Small (≈ 46 px on a
	-- phone) and never takes input.
	local pointer = U.new("Frame", {
		Name = "TrophyPointer",
		Visible = false,
		Active = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.38),
		Size = UDim2.fromScale(0.118, 0.118),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 15,
	}, hud)
	U.new("UISizeConstraint", { MinSize = Vector2.new(46, 46), MaxSize = Vector2.new(72, 72) }, pointer)
	local tip = U.new("Frame", {
		Name = "Tip",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(1.1, 0.5),
		Size = UDim2.fromScale(0.44, 0.44),
		Rotation = 45,
		BackgroundColor3 = P.Gold.Bottom,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, pointer)
	corner(tip, 0.18)
	Theme.stroke(tip, Theme.MINOR, 0, P.Gold.Lip)
	local ring = U.new("Frame", {
		Name = "BaseRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.24, 1.24),
		BackgroundTransparency = 1,
		ZIndex = 1,
	}, pointer)
	corner(ring, 0.5)
	U.new("UIStroke", {
		Name = "Stroke",
		Color = WHITE,
		Thickness = 4,
		Attributes = { BaseThickness = 6 },
	}, ring)
	local body = U.new("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 3,
	}, pointer)
	Theme.sim(body, "Gold", { round = true })
	Theme.socket(body, "IconSocket", "🌟", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		ZIndex = SZ.Content,
	})
end

return {
	buildStatus = buildStatus,
	buildRightButtons = buildRightButtons,
	buildToasts = buildToasts,
}
