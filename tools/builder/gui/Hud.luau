--[[
	Hud — the HUD chrome in the "Candy Splash" style (the reference for the other builders): the
	status stack (base badge, catch counter), the right button column (Home), the toast column and
	the base-assignment banner (built with the status stack: it flies into the badge). Controllers: HudController (badge, banner, catch counter, Home),
	NotifyController (toasts). Layout rules: tools/builder/Gui.luau; look and API:
	tools/builder/gui/STYLE.md.

	Names are a contract (controllers and tests find them): Status.BaseBadge.{Swatch, Label},
	Status.CatchCounter.{Icon, Label}, RightButtons.HomeButton.{Icon, Caption, Cooldown,
	CooldownText}, Toasts.ToastTemplate.{Label, IconSocket.Icon}, BaseBanner.{Caption, NameLabel,
	FlagSocket.Flag}. Everything else (Lip, Gloss, Shine, sockets, ribbons, …) is decoration.

	Text uses the type scale (Theme.TYPE, UiFx.fitText): badge Title, counter and toasts Body,
	Home caption Button; every tiered label gets a box at least as tall as its tier.
]]

local Theme = require("./Theme")

local U = Theme.U
local Enum = U.Enum
local UDim = U.UDim
local UDim2 = U.UDim2
local Vector2 = U.Vector2

local UI = Theme.UI
local P = Theme.P
local Z = Theme.Z
local INK = Theme.INK
local WHITE = Theme.WHITE
local FACE = 1 - Theme.LIP -- the face covers the top of a candy; content is centred on it
local corner = Theme.corner
local label = Theme.label

local function buildBaseBanner(hud: any)
	-- The moment the base is assigned: a big candy in the base's swatch across the screen centre —
	-- small «ТВОЯ БАЗА» over big «ЛАЗУРНАЯ!», a waving 🚩, rays and confetti behind; after ~2 s
	-- HudController shrinks it into the badge. Never takes input.
	local banner = U.new("Frame", {
		Name = "BaseBanner",
		Visible = false,
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(1.05, 0.3),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 20,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(560, 170) }, banner)
	Theme.candy(banner, "Leaf", { radius = 0.32 })
	Theme.socket(banner, "FlagSocket", "🚩", {
		IconName = "Flag",
		AnchorPoint = Vector2.new(0.32, 0.5),
		Position = UDim2.fromScale(0, FACE * 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
		Rotation = -8,
	})
	label(banner, "Caption", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.57, FACE * 0.25),
		Size = UDim2.fromScale(0.76, FACE * 0.26),
		Text = "ТВОЯ БАЗА",
		Outline = 2,
		ZIndex = Z.Content,
		Tier = "Body",
	})
	label(banner, "NameLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.57, FACE * 0.64),
		Size = UDim2.fromScale(0.78, FACE * 0.44),
		Text = "ЛАЗУРНАЯ!",
		Outline = 3,
		TextGradient = { WHITE, P.Cream.Bottom },
		ZIndex = Z.Content,
		MaxTextSize = 64,
	})
end

local function buildStatus(hud: any)
	local status = U.new("Frame", {
		Name = "Status",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.01),
		Size = UDim2.fromScale(0.9, 0.25),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(520, 210) }, status)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0.05, 0),
	}, status)

	-- "Your base" badge: a glossy pill in the base colour (HudController paints it with the base's
	-- swatch, UIConfig.BaseSwatches; the face is named Swatch) with a flag in a white socket
	-- overhanging its left end. LayoutOrder 20 leaves room above it for the money counter
	-- (Stage 3) and below it for the shield timer (Stage 4).
	local badge = U.new("Frame", {
		Name = "BaseBadge",
		LayoutOrder = 20,
		Size = UDim2.fromScale(0.76, 0.37),
	}, status)
	Theme.candy(badge, "Slate", { faceName = "Swatch" })
	Theme.socket(badge, "FlagSocket", "🔎", {
		IconName = "Flag",
		AnchorPoint = Vector2.new(0.3, 0.5),
		Position = UDim2.fromScale(0, FACE * 0.54), -- a little low: clear of the top bar on phones
		Size = UDim2.fromScale(1.12, 1.12),
	})
	label(badge, "Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.575, FACE * 0.5),
		Size = UDim2.fromScale(0.74, FACE * 0.8),
		Text = "Ищем базу…",
		Outline = 2,
		ZIndex = Z.Content,
		Tier = "Title",
	})

	-- Catch counter (stage 2): fish caught this session, a gold pill with the 🐟 in a white socket
	-- overhanging its left end (like the badge flag); hidden until the first catch. HudController
	-- owns its text and visibility (Player attribute FishCaught; HUD attribute CounterHold).
	-- The 🐟 "Icon" is a direct child (contract), drawn over the empty socket.
	local counter = Theme.pill(status, "CatchCounter", "Gold", {
		LayoutOrder = 30,
		Visible = false,
		Size = UDim2.fromScale(0.5, 0.3),
		Text = "Улов: 0",
		Tier = "Body",
		LabelProps = {
			Position = UDim2.fromScale(0.94, FACE * 0.5),
			Size = UDim2.fromScale(0.72, FACE * 0.7),
		},
	})
	local socketScale = 1.15 -- socket diameter in pill heights
	local iconShare = 0.74 -- the 🐟 fills this much of the socket
	local socket = Theme.socket(counter, "IconSocket", "", {
		AnchorPoint = Vector2.new(0.3, 0.5),
		Position = UDim2.fromScale(0, FACE * 0.5),
		Size = UDim2.fromScale(socketScale, socketScale),
	})
	-- Same Position as the socket; the AnchorPoint puts the icon's centre on the socket's centre
	-- (0.2 socket diameters right of the pill's left end): d * (0.5 - a) = 0.2 * D.
	Theme.icon(counter, "Icon", "🐟", {
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.5 - 0.2 / iconShare, 0.5),
		Position = UDim2.fromScale(0, FACE * 0.5),
		Size = UDim2.fromScale(socketScale * iconShare, socketScale * iconShare),
		Rotation = -12,
		ZIndex = socket.ZIndex + 1,
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
		Padding = UDim.new(0.03, 0),
	}, right)

	-- Big square Mint candy "Home" button (🏠 over a dark caption ribbon «ДОМОЙ», like the action
	-- button), shown once the player has a base. Mint, not Leaf: it never looks like «ЛОВИ!».
	local home = Theme.candyButton(right, "HomeButton", "Mint", {
		LayoutOrder = 100, -- bottom of the column; Shop/Shield go above it later
		Size = UDim2.fromScale(1, 0.3),
		Visible = false,
		Square = true,
		Radius = 0.3,
		Icon = "🏠",
	})
	local icon = home:FindFirstChild("Icon")
	icon.Position = UDim2.fromScale(0.5, FACE * 0.38)
	icon.Size = UDim2.fromScale(0.62, FACE * 0.54)
	local ribbon = U.new("Frame", {
		Name = "CaptionRibbon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.84),
		Size = UDim2.fromScale(1.1, 0.3),
		ZIndex = Z.Content,
	}, home)
	Theme.candy(ribbon, "Night", { radius = 0.5, lip = 0.1, shine = false })
	-- On the ribbon; during the cooldown HudController lifts it above the veil (Z.Top) as «ЖДИ».
	label(home, "Caption", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.825),
		Size = UDim2.fromScale(1.04, 0.28),
		Text = "ДОМОЙ",
		Outline = 2,
		ZIndex = Z.Content + 1,
		Tier = "Button",
	})
	-- Cooldown: a dark veil over the whole candy that drains downwards (HudController moves the
	-- hard edge of the "Drain" gradient: Offset.Y -0.5 = fully covered → 0.5 = clear), plus the
	-- seconds left in big digits centred on the face.
	local cooldown = U.new("Frame", {
		Name = "Cooldown",
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = Z.Overlay,
	}, home)
	corner(cooldown, 0.3)
	U.new("UIGradient", {
		Name = "Drain",
		Rotation = 90,
		Offset = Vector2.new(0, -0.5),
		Transparency = Theme.numbers({ { 0, 1 }, { 0.495, 1 }, { 0.5, 0 }, { 1, 0 } }),
	}, cooldown)
	label(home, "CooldownText", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, FACE * 0.42),
		Size = UDim2.fromScale(0.8, FACE * 0.7),
		Text = "",
		Outline = 3,
		ZIndex = Z.Top,
		MaxTextSize = 56,
		TextGradient = { WHITE, P.Gold.Top },
	})
end

local function buildToasts(hud: any)
	-- Width follows the screen WIDTH (RelativeXY), so the column never reaches the corners.
	-- No UIListLayout: NotifyController stacks the toasts itself (slots of 0.28 + 0.08 of the
	-- column height; big rarity toasts are taller), sizes each to its text and lets them slide.
	local toasts = U.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.27),
		Size = UDim2.fromScale(0.56, 0.34),
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(640, 190) }, toasts)

	-- A candy pill per toast: NotifyController clones it, recolours it by kind
	-- (UIConfig.ToastKinds: Sky / Leaf / Sun / Berry / base colour / Gold / rainbow) and puts the
	-- kind's emoji into the socket.
	Theme.pill(toasts, "ToastTemplate", "Sky", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 0.28),
		Icon = UI.ToastKinds.info.Icon,
		Socket = true,
		IconScale = 1.0,
		Text = "",
		Tier = "Body",
		LabelProps = {
			Position = UDim2.fromScale(0.96, FACE * 0.5),
			Size = UDim2.fromScale(0.8, FACE * 0.72),
			TextWrapped = true, -- long texts: NotifyController makes the toast taller (two lines)
		},
	})
end

return {
	buildStatus = buildStatus,
	buildRightButtons = buildRightButtons,
	buildToasts = buildToasts,
}
