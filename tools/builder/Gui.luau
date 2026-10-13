--[[
	Builds StarterGui.HUD — the main mobile-friendly interface (landscape; the place locks
	StarterGui.ScreenOrientation to LandscapeSensor).

	Sizing rules (phones first):
	  • everything is in Scale, never fixed pixels — except HOTBAR: the fishing widgets stand
	    that many pixels above the screen bottom, because the Roblox hotbar (CoreGui, drawn over
	    PlayerGui) is a fixed-pixel band there (60 px slots, 5..65 px from the bottom, centred);
	  • SizeConstraint RelativeYY makes widgets scale with screen HEIGHT, so they look the same
	    on a phone and on a PC; UISizeConstraint caps them on big screens;
	  • ScreenInsets = CoreUISafeInsets keeps widgets out of the notch and the Roblox top bar.

	Screen grid (H = safe-area height), planned for all stages:
	  Status        top-centre stack: base badge (St.1), catch counter (St.2), money (St.3),
	                shield timer (St.4).
	                Top-left is the chat window, top-right the player list — both CoreGui.
	  Toasts        centred column from y = 0.30H, width from screen WIDTH (never reaches
	                the corners).
	  RightButtons  column anchored at its BOTTOM (y = 0.64H) and growing upwards, so the
	                bottom-right 0.36H stays free for the mobile Jump button (and the Stage 2
	                cast button left of it). HudController moves it lower on non-touch screens.
	  Fishing       (St.2) ActionArea bottom-right, LEFT of the mobile Jump button (phones: 70 px
	                at 25..95 px from the right; screens over 500 px tall: 120 px at 50..170 px);
	                Hint, then BiteAlert / Minigame stacked bottom-centre above the hotbar;
	                CatchCard as a modal between the status stack and the hotbar.
	  (Stage 5)     shop as a centred modal.

	Controllers that use these names: HudController, NotifyController, FishingController.
]]

local U = require("./Util")

local Enum = U.Enum
local UDim = U.UDim
local UDim2 = U.UDim2
local Vector3 = U.Vector3
local Vector2 = U.Vector2
local rgb = U.rgb

local FONT = U.FONT
local MIN_TEXT = 12 -- never let TextScaled shrink text below this on phones
-- Pixels from the screen bottom to the fishing widgets: clears the Roblox hotbar (see above).
local HOTBAR = 74

local C = {
	panel = rgb(22, 28, 48),
	stroke = rgb(10, 12, 20),
	text = rgb(255, 255, 255),
	home = rgb(52, 180, 90),
	toast = rgb(45, 120, 220),
	noBase = rgb(140, 140, 150),
	cast = rgb(40, 132, 226), -- the fishing action button (FishingController recolours it per state)
	stop = rgb(200, 72, 64),
	track = rgb(34, 42, 66),
	zone = rgb(64, 200, 96),
	needle = rgb(255, 255, 255),
	pip = rgb(70, 78, 100),
	card = rgb(250, 248, 242),
	ink = rgb(34, 38, 56),
	common = rgb(150, 160, 172),
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

--[[
	Fishing UI (stage 2), all under HUD.Fishing (FishingController drives it; everything starts
	hidden):
	  ActionArea              bottom-right container, sized by screen height
	    ActionButton          big round button: Icon + Caption («ЗАБРОСИТЬ» / «ПОДСЕЧЬ!» / «ТЯНИ!»),
	                          Ring (UIStroke) — shown while the rod is in hand («ВЗЯТЬ»
	                          at the own fishing spot while the rod is in the backpack)
	    StopButton            «СМОТАТЬ» pill above it (Caption) — while the line is out
	  BiteAlert               «КЛЮЁТ!» (Label) with a shrinking Timer bar
	  Minigame                Title (rarity, coloured), Track (Zone, Needle), Pips (Pip1..Pip5:
	                          hits needed / done), TimeBar (Fill), Help
	  Hint                    one line at the bottom centre («Встань в круг на своём пирсе» …)
	  CatchCard               TextButton (tap to close): Banner (RarityLabel), Viewport
	                          (ViewportFrame for the fish model), NameLabel, MutationLabel, InfoLabel,
	                          TapHint
]]
local function buildFishing(hud: any)
	local root = U.new("Frame", {
		Name = "Fishing",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2, -- above HUD.Toasts (Sibling): the minigame, bite alert and card cover toasts
	}, hud)

	-- Action area: 0.58H wide, 0.46H tall (at most 320 x 240 px), in the bottom-right corner. The
	-- button sits in its left part, so the rightmost ~0.33H (190 px on big screens) stays free
	-- for the Jump button.
	local area = U.new("Frame", {
		Name = "ActionArea",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromScale(0.58, 0.46),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}, root)
	-- Capped on big screens, so on a 4:3 tablet the bottom-centre minigame still fits between
	-- the thumbstick and the button.
	U.new("UISizeConstraint", { MaxSize = Vector2.new(320, 240) }, area)
	local action = U.new("TextButton", {
		Name = "ActionButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 0.89),
		Size = UDim2.fromScale(0.43, 0.54),
		BackgroundColor3 = C.cast,
		AutoButtonColor = true,
		Text = "",
		Visible = false,
	}, area)
	U.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, action)
	corner(action, 0.5)
	U.new("UIStroke", {
		Name = "Ring",
		Color = C.text,
		Thickness = 4,
		Transparency = 0.1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, action)
	label(action, "Icon", {
		Position = UDim2.fromScale(0.15, 0.1),
		Size = UDim2.fromScale(0.7, 0.46),
		Text = "🎣",
		TextStrokeTransparency = 1,
	})
	label(action, "Caption", {
		Position = UDim2.fromScale(0.08, 0.56),
		Size = UDim2.fromScale(0.84, 0.26),
		Text = "ЗАБРОСИТЬ",
		MaxTextSize = 26,
		MinTextSize = 9,
	})
	local stop = U.new("TextButton", {
		Name = "StopButton",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 0.22),
		Size = UDim2.fromScale(0.43, 0.2),
		BackgroundColor3 = C.stop,
		AutoButtonColor = true,
		Text = "",
		Visible = false,
	}, area)
	corner(stop, 0.5)
	stroke(stop, 2, 0.2)
	label(stop, "Caption", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.86, 0.7),
		Text = "СМОТАТЬ",
		MaxTextSize = 22,
		MinTextSize = 9,
	})

	-- Bite alert: where the minigame appears next (they are never shown together).
	local alert = U.new("Frame", {
		Name = "BiteAlert",
		Visible = false,
		BackgroundColor3 = rgb(240, 140, 30),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.92, -HOTBAR - 6),
		Size = UDim2.fromScale(0.6, 0.15),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}, root)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(380, 100) }, alert)
	corner(alert, 0.35)
	stroke(alert, 3, 0.1)
	label(alert, "Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.44),
		Size = UDim2.fromScale(0.9, 0.7),
		Text = "КЛЮЁТ! ЖМИ!",
		MaxTextSize = 40,
	})
	local alertTimer = U.new("Frame", {
		Name = "Timer",
		BackgroundColor3 = C.text,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.92),
		Size = UDim2.fromScale(0.8, 0.08),
	}, alert)
	corner(alertTimer, 0.5)

	-- Minigame: width from the screen WIDTH (like the toasts), capped on big screens.
	local mini = U.new("Frame", {
		Name = "Minigame",
		Visible = false,
		BackgroundColor3 = C.panel,
		BackgroundTransparency = 0.15,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.92, -HOTBAR - 6),
		Size = UDim2.fromScale(0.36, 0.22),
	}, root)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(560, 160), MinSize = Vector2.new(280, 90) }, mini)
	corner(mini, 0.18)
	stroke(mini, 2, 0.3)
	label(mini, "Title", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0.04, 0.04),
		Size = UDim2.fromScale(0.6, 0.24),
		Text = "РЫБА НА КРЮЧКЕ!",
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = C.text,
		MaxTextSize = 26,
	})
	local pips = U.new("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.96, 0.07),
		Size = UDim2.fromScale(0.32, 0.18),
	}, mini)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.03, 0),
	}, pips)
	for i = 1, 5 do
		local pip = U.new("Frame", {
			Name = `Pip{i}`,
			LayoutOrder = i,
			Visible = false,
			BackgroundColor3 = C.pip,
			Size = UDim2.fromScale(1, 1),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
		}, pips)
		corner(pip, 0.5)
		U.new("UIStroke", { Color = C.text, Thickness = 2, Transparency = 0.2 }, pip)
	end
	local track = U.new("Frame", {
		Name = "Track",
		BackgroundColor3 = C.track,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.34),
		Size = UDim2.fromScale(0.92, 0.3),
		ClipsDescendants = false,
	}, mini)
	corner(track, 0.3)
	stroke(track, 2, 0.2)
	-- Zone and Needle: Position.X.Scale is the centre (AnchorPoint 0.5), Size.X.Scale the width,
	-- both as fractions of the track (FishingRules: ZoneCenter, ZoneWidth, Needle).
	local zone = U.new("Frame", {
		Name = "Zone",
		BackgroundColor3 = C.zone,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.3, 0.84),
	}, track)
	corner(zone, 0.3)
	local needle = U.new("Frame", {
		Name = "Needle",
		BackgroundColor3 = C.needle,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(0.022, 1.5),
		ZIndex = 3,
	}, track)
	corner(needle, 0.5)
	stroke(needle, 2)
	local timeBar = U.new("Frame", {
		Name = "TimeBar",
		BackgroundColor3 = C.track,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.71),
		Size = UDim2.fromScale(0.92, 0.05),
	}, mini)
	corner(timeBar, 0.5)
	local fill = U.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = rgb(240, 200, 70),
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
	}, timeBar)
	corner(fill, 0.5)
	label(mini, "Help", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.97),
		Size = UDim2.fromScale(0.92, 0.18),
		Text = "Жми, когда стрелка в зелёной зоне!",
		MaxTextSize = 20,
	})

	-- Hint: one line at the bottom centre above the hotbar, between the thumbstick and the
	-- action button; the Minigame / BiteAlert stand on top of it (0.92H - HOTBAR - 6).
	local hint = label(root, "Hint", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -HOTBAR),
		Size = UDim2.fromScale(0.36, 0.08),
		Text = "",
		BackgroundTransparency = 0.35,
		BackgroundColor3 = C.panel,
		MaxTextSize = 24,
	})
	corner(hint, 0.5)

	-- Catch card: a modal between the status stack (base badge, catch counter) and the hotbar
	-- (tap anywhere on it to close).
	local card = U.new("TextButton", {
		Name = "CatchCard",
		Visible = false,
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = C.card,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -HOTBAR),
		Size = UDim2.fromScale(0.55, 0.56),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 10,
	}, root)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(380, 400) }, card)
	corner(card, 0.08)
	stroke(card, 3, 0.1)
	local banner = U.new("Frame", {
		Name = "Banner",
		BackgroundColor3 = C.common,
		Size = UDim2.fromScale(1, 0.15),
		ZIndex = 10,
	}, card)
	corner(banner, 0.35)
	label(banner, "RarityLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.9, 0.72),
		Text = "ОБЫЧНАЯ",
		MaxTextSize = 30,
		ZIndex = 11,
	})
	U.new("ViewportFrame", {
		Name = "Viewport",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.16),
		Size = UDim2.fromScale(0.92, 0.46),
		Ambient = rgb(200, 200, 210),
		LightColor = rgb(255, 250, 240),
		LightDirection = Vector3.new(-1, -1.4, -0.8),
		ZIndex = 10,
	}, card)
	label(card, "NameLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromScale(0.92, 0.12),
		Text = "Карасик",
		TextColor3 = C.ink,
		TextStrokeTransparency = 1,
		MaxTextSize = 34,
		ZIndex = 10,
	})
	local mutation = label(card, "MutationLabel", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.74),
		Size = UDim2.fromScale(0.7, 0.08),
		Text = "",
		BackgroundTransparency = 0,
		BackgroundColor3 = rgb(255, 200, 40),
		MaxTextSize = 22,
		ZIndex = 11,
	})
	corner(mutation, 0.5)
	label(card, "InfoLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.83),
		Size = UDim2.fromScale(0.92, 0.08),
		Text = "",
		TextColor3 = C.ink,
		TextStrokeTransparency = 1,
		MaxTextSize = 24,
		ZIndex = 10,
	})
	label(card, "TapHint", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.98),
		Size = UDim2.fromScale(0.8, 0.06),
		Text = "Нажми, чтобы закрыть",
		TextColor3 = rgb(120, 126, 140),
		TextStrokeTransparency = 1,
		MaxTextSize = 16,
		MinTextSize = 9,
		ZIndex = 10,
	})
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
	buildFishing(hud)
	buildToasts(hud)

	return hud
end
