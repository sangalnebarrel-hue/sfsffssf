--[[
	Hud — the HUD chrome: the status stack (base badge, catch counter), the right button column
	(Home) and the toast column. Controllers: HudController, NotifyController, FishingController
	(the catch counter). Layout rules: tools/builder/Gui.luau; look: tools/builder/gui/STYLE.md.
]]

local Theme = require("./Theme")

local U = Theme.U
local Enum = U.Enum
local UDim = U.UDim
local UDim2 = U.UDim2
local Vector3 = U.Vector3
local Vector2 = U.Vector2
local rgb = U.rgb

local C = Theme.C
local HOTBAR = Theme.HOTBAR
local corner = Theme.corner
local stroke = Theme.stroke
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

	-- "Your base" badge: colour swatch + base name. LayoutOrder 20 leaves room above it
	-- for the money counter (Stage 3) and below it for the shield timer (Stage 4).
	local badge = U.new("Frame", {
		Name = "BaseBadge",
		LayoutOrder = 20,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.2,
		Size = UDim2.fromScale(0.76, 0.38),
	}, status)
	corner(badge, 0.5)
	stroke(badge, 2, 0.3)
	local swatch = U.new("Frame", {
		Name = "Swatch",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.04, 0.5),
		Size = UDim2.fromScale(0.66, 0.66),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = C.noBase,
	}, badge)
	corner(swatch, 0.5)
	U.new("UIStroke", { Color = C.text, Thickness = 2 }, swatch)
	label(badge, "Label", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.21, 0.5),
		Size = UDim2.fromScale(0.75, 0.68),
		Text = "Ищем базу…",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 30,
	})

	-- Catch counter (stage 2): fish caught this session; hidden until the first catch.
	local counter = U.new("Frame", {
		Name = "CatchCounter",
		LayoutOrder = 30,
		Visible = false,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.25,
		Size = UDim2.fromScale(0.46, 0.26),
	}, status)
	corner(counter, 0.5)
	stroke(counter, 2, 0.4)
	label(counter, "Icon", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.05, 0.5),
		Size = UDim2.fromScale(0.24, 0.8),
		Text = "🐟",
		TextStrokeTransparency = 1,
	})
	label(counter, "Label", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.3, 0.5),
		Size = UDim2.fromScale(0.64, 0.66),
		Text = "Улов: 0",
		TextXAlignment = Enum.TextXAlignment.Left,
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

	-- Big square "Home" button (icon + caption) with a cooldown overlay.
	local home = U.new("TextButton", {
		Name = "HomeButton",
		LayoutOrder = 100, -- bottom of the column; Shop/Shield go above it later
		Size = UDim2.fromScale(1, 0.3),
		BackgroundColor3 = C.home,
		AutoButtonColor = true,
		Text = "",
		Visible = false, -- shown once the player has a base
	}, right)
	U.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Width }, home)
	corner(home, 0.22)
	stroke(home, 3)
	label(home, "Icon", {
		Position = UDim2.fromScale(0, 0.06),
		Size = UDim2.fromScale(1, 0.56),
		Text = "🏠",
		TextStrokeTransparency = 1,
	})
	label(home, "Caption", {
		Position = UDim2.fromScale(0.04, 0.64),
		Size = UDim2.fromScale(0.92, 0.3),
		Text = "ДОМОЙ",
		MaxTextSize = 24,
		MinTextSize = 9, -- short caption in a small square: allow it to shrink rather than wrap
	})
	local cooldown = U.new("Frame", {
		Name = "Cooldown",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = rgb(0, 0, 0),
		BackgroundTransparency = 0.45,
		Visible = false,
		ZIndex = 3,
	}, home)
	corner(cooldown, 0.22)
end

local function buildToasts(hud: any)
	-- Width follows the screen WIDTH (RelativeXY), so the column never reaches the corners.
	local toasts = U.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromScale(0.44, 0.34),
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(560, 300) }, toasts)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0.04, 0),
	}, toasts)

	local template = U.new("Frame", {
		Name = "ToastTemplate",
		Visible = false,
		BackgroundColor3 = C.toast,
		BackgroundTransparency = 0.08,
		Size = UDim2.fromScale(1, 0.3),
	}, toasts)
	corner(template, 0.35)
	stroke(template, 2, 0.35)
	label(template, "Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.8),
		Text = "",
		TextWrapped = true,
		MaxTextSize = 26,
	})
end

return {
	buildStatus = buildStatus,
	buildRightButtons = buildRightButtons,
	buildToasts = buildToasts,
}
