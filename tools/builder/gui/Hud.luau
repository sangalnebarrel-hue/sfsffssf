--[[
	Hud — the HUD chrome in the UI v5 «Симулятор» style (the reference for the other builders:
	chunky gradient buttons with a thick outline in a dark shade of their hue, outlined emoji,
	panel-less big italic numbers and outlined titles): the status stack (base badge, catch
	counter), the right button column (Home), the toast column, the base-assignment banner (built
	with the status stack: it flies into the badge) and the off-screen trophy chip. Controllers:
	HudController (badge, banner, catch counter, Home), NotifyController (toasts, trophy chip).
	Layout rules: tools/builder/Gui.luau; look and API: tools/builder/gui/STYLE.md.

	Names are a contract (controllers and tests find them): Status.BaseBadge.{Swatch, Label,
	FlagSocket.Flag}, Status.CatchCounter.{Icon, Label}, RightButtons.HomeButton.{Icon, Caption,
	Cooldown, CooldownText, Badge}, Toasts.ToastTemplate.{Label, IconSocket.Icon}, BaseBanner.{Caption,
	NameLabel, FlagSocket.Flag}, TrophyPointer.{Body.IconSocket.Icon, Tip, BaseRing.Stroke}
	(NotifyController: the chip pointing at someone else's off-screen light pillar). Everything
	else (Lip, Rim, Shine, NameLabelShadow, …) is decoration.

	The widgets (Theme.sim and friends; content at Theme.SZ.Content):
	  BaseBadge     a label plate in the base colour (Theme.plate shape), the 🚩 overhanging its
	                left end, the name in CAPS («ЛАЗУРНАЯ БАЗА», Title tier);
	  CatchCounter  a panel-less stat like the reference's «👟 10»: 🐟 + a big italic white number;
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
		Position = UDim2.fromScale(0.5, 0.45), -- clear of the chat window and the status stack
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
	Theme.title(banner, "NameLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.56, 0.62),
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
	-- contour, so the red 🚩 still reads on the red base's plate). LayoutOrder 20 leaves room above
	-- it for the money counter (Stage 3) and below it for the shield timer (Stage 4).
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

	-- Catch counter (stage 2): fish caught this session — the reference's panel-less stat «🐟 12»
	-- (an outlined 🐟 and a big italic white number), hidden until the first catch. HudController
	-- owns its text (the number) and visibility (Player attribute FishCaught; HUD attribute
	-- CounterHold). The 🐟 "Icon" is a direct child (contract).
	Theme.stat(status, "CatchCounter", "🐟", {
		LayoutOrder = 30,
		Visible = false,
		Size = UDim2.fromScale(0.5, 0.38),
		Text = "0",
		MaxTextSize = 48,
		MinTextSize = 16,
	})

	buildBaseBanner(hud)
end

local function buildRightButtons(hud: any)
	local right = U.new("Frame", {
		Name = "RightButtons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(0.99, 0.64), -- bottom edge; the column grows upwards
		Size = UDim2.fromScale(0.18, 0.6), -- 3 square buttons (0.54H) + gaps fit in 0.6H
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(104, 380) }, right)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0.05, 0), -- (≈ 0.15 of a button: the reference's column rhythm)
	}, right)

	-- "Home": a square purple button (Grape: never the green «ЛОВИ!» nor the blue «ЗАБРОСИТЬ»),
	-- 🏠 big in the middle and «ДОМОЙ» ON its bottom edge (the reference squares are icon-only;
	-- ours keep the word for kids), shown once the player has a base.
	local home = Theme.simButton(right, "HomeButton", "Grape", {
		LayoutOrder = 100, -- bottom of the column; Shop/Shield go above it later
		Size = UDim2.fromScale(1, 0.3),
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
end

local function buildToasts(hud: any)
	-- Width follows the screen WIDTH (RelativeXY), so the column never reaches the corners.
	-- No UIListLayout: NotifyController stacks the toasts itself (slots of 0.28 + 0.08 of the
	-- column height; big rarity toasts are taller), sizes each to its text and lets them slide.
	-- The column starts right under the status stack (0.23 of the HUD): on a phone one toast
	-- ends above the avatar's head. Without a touch screen NotifyController narrows it to
	-- 512 px, clear of the Roblox chat window in the top-left corner.
	local toasts = U.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.23),
		Size = UDim2.fromScale(0.56, 0.34),
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
