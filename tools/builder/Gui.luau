--[[
	Builds StarterGui.HUD — the main mobile-friendly interface.

	Sizing rules (phones first):
	  • everything is in Scale, never fixed pixels;
	  • SizeConstraint RelativeYY makes widgets scale with screen HEIGHT, so they look the same
	    on a phone in landscape and on a PC; UISizeConstraint caps them on big screens;
	  • ScreenInsets = CoreUISafeInsets keeps widgets out of the notch and Roblox top bar.

	Controllers that use these names: HudController, NotifyController.
]]

local U = require("./Util")

local Enum = U.Enum
local UDim = U.UDim
local UDim2 = U.UDim2
local Vector2 = U.Vector2
local rgb = U.rgb

local FONT = U.Font.fromEnum(Enum.Font.FredokaOne)

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
	base.MaxTextSize = nil
	local inst = U.new("TextLabel", base, parent)
	if maxText then
		U.new("UITextSizeConstraint", { MaxTextSize = maxText, MinTextSize = 8 }, inst)
	end
	return inst
end

local function buildTopLeft(hud: any)
	local topLeft = U.new("Frame", {
		Name = "TopLeft",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.012, 0.02),
		Size = UDim2.fromScale(0.52, 0.3),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(400, 230) }, topLeft)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.04, 0),
	}, topLeft)

	-- "Your base" badge: colour swatch + base name.
	local badge = U.new("Frame", {
		Name = "BaseBadge",
		LayoutOrder = 1,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.2,
		Size = UDim2.fromScale(1, 0.27),
	}, topLeft)
	corner(badge, 0.5)
	stroke(badge, 2, 0.3)
	local swatch = U.new("Frame", {
		Name = "Swatch",
		AnchorPoint = U.Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.035, 0.5),
		Size = UDim2.fromScale(0.68, 0.68),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		BackgroundColor3 = C.noBase,
	}, badge)
	corner(swatch, 0.5)
	U.new("UIStroke", { Color = C.text, Thickness = 2 }, swatch)
	label(badge, "Label", {
		AnchorPoint = U.Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.2, 0.5),
		Size = UDim2.fromScale(0.76, 0.66),
		Text = "Ищем базу…",
		TextXAlignment = Enum.TextXAlignment.Left,
		MaxTextSize = 30,
	})
end

local function buildRightButtons(hud: any)
	local right = U.new("Frame", {
		Name = "RightButtons",
		BackgroundTransparency = 1,
		AnchorPoint = U.Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.99, 0.55),
		Size = UDim2.fromScale(0.16, 0.66),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(112, 470) }, right)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0.03, 0),
	}, right)

	-- Big square "Home" button (icon + caption) with a cooldown overlay.
	local home = U.new("TextButton", {
		Name = "HomeButton",
		LayoutOrder = 10,
		Size = UDim2.fromScale(1, 0.24),
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
		Position = UDim2.fromScale(0.05, 0.64),
		Size = UDim2.fromScale(0.9, 0.28),
		Text = "ДОМОЙ",
		MaxTextSize = 24,
	})
	local cooldown = U.new("Frame", {
		Name = "Cooldown",
		AnchorPoint = U.Vector2.new(0, 1),
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
	local toasts = U.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = U.Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.02),
		Size = UDim2.fromScale(1.15, 0.36),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(640, 360) }, toasts)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0.03, 0),
	}, toasts)

	local template = U.new("Frame", {
		Name = "ToastTemplate",
		Visible = false,
		BackgroundColor3 = C.toast,
		BackgroundTransparency = 0.08,
		Size = UDim2.fromScale(1, 0.28),
	}, toasts)
	corner(template, 0.35)
	stroke(template, 2, 0.35)
	label(template, "Label", {
		AnchorPoint = U.Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.94, 0.78),
		Text = "",
		TextWrapped = true,
		MaxTextSize = 28,
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

	buildTopLeft(hud)
	buildRightButtons(hud)
	buildToasts(hud)

	return hud
end
