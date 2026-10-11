--[[
	Builds StarterGui.HUD — the main mobile-friendly interface (landscape; the place locks
	StarterGui.ScreenOrientation to LandscapeSensor).

	Sizing rules (phones first):
	  • everything is in Scale, never fixed pixels;
	  • SizeConstraint RelativeYY makes widgets scale with screen HEIGHT, so they look the same
	    on a phone and on a PC; UISizeConstraint caps them on big screens;
	  • ScreenInsets = CoreUISafeInsets keeps widgets out of the notch and the Roblox top bar.

	Screen grid (H = safe-area height), planned for all stages:
	  Status        top-centre stack: base badge (St.1), money (St.3), shield timer (St.4).
	                Top-left is the chat window, top-right the player list — both CoreGui.
	  Toasts        centred column from y = 0.30H, width from screen WIDTH (never reaches
	                the corners).
	  RightButtons  column anchored at its BOTTOM (y = 0.64H) and growing upwards, so the
	                bottom-right 0.36H stays free for the mobile Jump button (and the Stage 2
	                cast button left of it). HudController moves it lower on non-touch screens.
	  (Stage 2)     minigame bar bottom-centre; (Stage 5) shop as a centred modal.

	Controllers that use these names: HudController, NotifyController.
]]

local U = require("./Util")

local Enum = U.Enum
local UDim = U.UDim
local UDim2 = U.UDim2
local Vector2 = U.Vector2
local rgb = U.rgb

local FONT = U.FONT
local MIN_TEXT = 12 -- never let TextScaled shrink text below this on phones

local C = {
	panel = rgb(22, 28, 48),
	stroke = rgb(10, 12, 20),
	text = rgb(255, 255, 255),
	home = rgb(52, 180, 90),
	toast = rgb(45, 120, 220),
	noBase = rgb(140, 140, 150),
}

local function corner(parent: any, scale: number)
	return U.new("UICorner", { CornerRadius = UDim.new(scale, 0) }, parent)
end

local function stroke(parent: any, thickness: number, transparency: number?)
	return U.new("UIStroke", {
		Color = C.stroke,
		Thickness = thickness,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function label(parent: any, name: string, props: { [string]: any }): any
	local base: { [string]: any } = {
		Name = name,
		BackgroundTransparency = 1,
		TextScaled = true,
		FontFace = FONT,
		TextColor3 = C.text,
		TextStrokeColor3 = C.stroke,
		TextStrokeTransparency = 0.4,
	}
	for key, value in props do
		base[key] = value
	end
	local maxText = base.MaxTextSize
	local minText = base.MinTextSize or MIN_TEXT
	base.MaxTextSize = nil
	base.MinTextSize = nil
	local inst = U.new("TextLabel", base, parent)
	if maxText then
		U.new("UITextSizeConstraint", { MaxTextSize = maxText, MinTextSize = minText }, inst)
	end
	return inst
end

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

return function(game: any)
	local starterGui = game:GetService("StarterGui")
	local hud = U.new("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 1,
	}, starterGui)

	buildStatus(hud)
	buildRightButtons(hud)
	buildToasts(hud)

	return hud
end
