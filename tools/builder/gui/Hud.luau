--[[
	Hud — the HUD chrome in the "Candy Splash" style (the reference for the other builders): the
	status stack (base badge, catch counter), the right button column (Home) and the toast column.
	Controllers: HudController (badge, counter juice, Home), NotifyController (toasts),
	FishingController (writes the catch counter's Label and Visible). Layout rules:
	tools/builder/Gui.luau; look and API: tools/builder/gui/STYLE.md.

	Names are a contract (controllers and tests find them): Status.BaseBadge.{Swatch, Label},
	Status.CatchCounter.{Icon, Label}, RightButtons.HomeButton.{Icon, Caption, Cooldown},
	Toasts.ToastTemplate.Label. Everything else (Lip, Gloss, Shine, FlagSocket, …) is decoration.
]]

local Theme = require("./Theme")

local U = Theme.U
local Enum = U.Enum
local UDim = U.UDim
local UDim2 = U.UDim2
local Vector2 = U.Vector2

local UI = Theme.UI
local Z = Theme.Z
local INK = Theme.INK
local FACE = 1 - Theme.LIP -- the face covers the top of a candy; content is centred on it
local corner = Theme.corner
local label = Theme.label

local function buildStatus(hud: any)
	local status = U.new("Frame", {
		Name = "Status",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.015),
		Size = UDim2.fromScale(0.9, 0.25),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(520, 210) }, status)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0.04, 0),
	}, status)

	-- "Your base" badge: a glossy pill in the base colour (HudController paints it from the
	-- BaseColor attribute; the face is named Swatch) with a flag in a white socket overhanging
	-- its left end. LayoutOrder 20 leaves room above it for the money counter (Stage 3) and
	-- below it for the shield timer (Stage 4).
	local badge = U.new("Frame", {
		Name = "BaseBadge",
		LayoutOrder = 20,
		Size = UDim2.fromScale(0.76, 0.38),
	}, status)
	Theme.candy(badge, nil, { color = UI.NoBaseColor, faceName = "Swatch" })
	Theme.socket(badge, "FlagSocket", "🔎", {
		IconName = "Flag",
		AnchorPoint = Vector2.new(0.3, 0.5),
		Position = UDim2.fromScale(0, FACE * 0.5),
		Size = UDim2.fromScale(1.2, 1.2),
	})
	label(badge, "Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.575, FACE * 0.5),
		Size = UDim2.fromScale(0.74, FACE * 0.7),
		Text = "Ищем базу…",
		Outline = 2,
		ZIndex = Z.Content,
		MaxTextSize = 30,
	})

	-- Catch counter (stage 2): fish caught this session, a gold pill with a big 🐟 overhanging
	-- its left end; hidden until the first catch (FishingController shows it and writes the text).
	Theme.pill(status, "CatchCounter", "Gold", {
		LayoutOrder = 30,
		Visible = false,
		Size = UDim2.fromScale(0.46, 0.26),
		Icon = "🐟",
		IconScale = 1.4,
		Text = "Улов: 0",
		MaxTextSize = 24,
	})
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

	-- Big square Leaf candy "Home" button (🏠 over «ДОМОЙ»), shown once the player has a base.
	local home = Theme.candyButton(right, "HomeButton", "Leaf", {
		LayoutOrder = 100, -- bottom of the column; Shop/Shield go above it later
		Size = UDim2.fromScale(1, 0.3),
		Visible = false,
		Square = true,
		Radius = 0.3,
		Icon = "🏠",
		Caption = "ДОМОЙ",
		MaxTextSize = 24,
		MinTextSize = 9, -- short caption in a small square: allow it to shrink rather than wrap
	})
	-- Cooldown: a dark veil over the whole candy that drains downwards (HudController moves the
	-- hard edge of the "Drain" gradient: Offset.Y -0.5 = fully covered → 0.5 = clear), plus the
	-- seconds left in big digits.
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
		Position = UDim2.fromScale(0.5, FACE * 0.45),
		Size = UDim2.fromScale(0.8, FACE * 0.62),
		Text = "",
		Outline = 3,
		ZIndex = Z.Top,
		MaxTextSize = 56,
		TextGradient = { Theme.WHITE, UI.Palette.Gold.Top },
	})
end

local function buildToasts(hud: any)
	-- Width follows the screen WIDTH (RelativeXY), so the column never reaches the corners.
	-- No UIListLayout: NotifyController stacks the toasts itself (slots of 0.3 + 0.04 of the
	-- column height), so they can slide into place and reflow smoothly.
	local toasts = U.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromScale(0.44, 0.34),
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(560, 300) }, toasts)

	-- A candy pill per toast: NotifyController clones it, recolours it by kind
	-- (UIConfig.ToastKinds: Sky / Leaf / Sun / Berry) and puts the kind's emoji into the socket.
	Theme.pill(toasts, "ToastTemplate", "Sky", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 0.3),
		Icon = UI.ToastKinds.info.Icon,
		Socket = true,
		IconScale = 1.12,
		Text = "",
		MaxTextSize = 26,
		LabelProps = {
			Position = UDim2.fromScale(0.96, FACE * 0.5),
			Size = UDim2.fromScale(0.78, FACE * 0.72),
			TextWrapped = true,
		},
	})
end

return {
	buildStatus = buildStatus,
	buildRightButtons = buildRightButtons,
	buildToasts = buildToasts,
}
