--[[
	Fishing — HUD.Fishing (stage 2) in the "Candy Splash" style: the action button, the bite
	alert, the minigame, the hint and the catch card (the big reveal). Controller and all the
	motion: FishingController (UiFx). Layout rules: tools/builder/Gui.luau; look and API:
	tools/builder/gui/STYLE.md (§3 "Fishing UI", §6).

	Names are a contract (FishingController, tests and the preview scenarios find widgets by
	name); everything not listed here is decoration and may change:
	  ActionArea.ActionButton.{Icon, Caption, Ring}   ActionArea.StopButton.Caption
	  BiteAlert.{Label, Timer}   Minigame.{Title, Pips.Pip1..Pip5, Track.{Zone, Needle},
	  TimeBar.Fill, Help}   Hint   CatchCard.{Banner.RarityLabel, Viewport, NameLabel,
	  MutationLabel, InfoLabel, TapHint}
	Value-holding labels on candies (Hint, CatchCard.MutationLabel, CatchCard.InfoLabel) keep
	their Text as the contract value but draw it through children (children render above their
	parent, so the candy face would hide the label's own text): Hint.Label, MutationLabel.Caption,
	InfoLabel.Weight / InfoLabel.Price (pills; the price counts up).
	Minigame pips keep a visible BackgroundColor3 (filled = green 64,200,96, as the e2e bot reads
	it); the zone and the needle keep Position.X = centre and Size.X = width in track fractions.
]]

local Theme = require("./Theme")

local U = Theme.U
local Enum = U.Enum
local UDim = U.UDim
local UDim2 = U.UDim2
local Vector3 = U.Vector3
local Vector2 = U.Vector2
local rgb = U.rgb

local UI = Theme.UI
local P = Theme.P
local Z = Theme.Z
local INK = Theme.INK
local WHITE = Theme.WHITE
local HOTBAR = Theme.HOTBAR
local FACE = 1 - Theme.LIP
local corner = Theme.corner
local stroke = Theme.stroke
local label = Theme.label

-- Pip colours: the e2e bot recognises a filled pip by this exact green (FishingController too).
local PIP_DONE = rgb(64, 200, 96)
local PIP_EMPTY = P.Slate.Lip

-- Fishing widgets stand this far above the hotbar band (BiteAlert / Minigame bottoms).
local STACK_BOTTOM = UDim2.new(0.5, 0, 0.92, -HOTBAR - 6)

-- A white highlight band in the top part of a small flat shape (pips, bars, the needle).
local function miniGloss(parent: any, z: number)
	local band = U.new("Frame", {
		Name = "Gloss",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.08),
		Size = UDim2.fromScale(0.86, 0.42),
		ZIndex = z,
	}, parent)
	corner(band, 0.5)
	U.new("UIGradient", {
		Name = "Fade",
		Rotation = 90,
		Transparency = Theme.numbers({ { 0, 0.35 }, { 1, 1 } }),
	}, band)
	return band
end

--------------------------------------------------------------------------------
-- Action area: the big round action button and the «СМОТАТЬ» pill
--------------------------------------------------------------------------------

local function buildActionArea(root: any)
	-- Action area: 0.58H wide, 0.46H tall (at most 320 x 240 px), in the bottom-right corner. The
	-- button sits in its left part, so the rightmost ~0.33H (190 px on big screens) stays free
	-- for the Jump button. ZIndex 9: above the catch card's dim and rays (the button closes the
	-- card too), below the card itself.
	local area = U.new("Frame", {
		Name = "ActionArea",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromScale(0.58, 0.46),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 9,
	}, root)
	-- Capped on big screens, so on a 4:3 tablet the bottom-centre minigame still fits between
	-- the thumbstick and the button.
	U.new("UISizeConstraint", { MaxSize = Vector2.new(320, 240) }, area)

	-- The star of the screen: a big round candy (FishingController recolours it per state with
	-- UiFx.setCandy: Sky «ЗАБРОСИТЬ», Slate «ЖДЁМ…», Sun «ПОДСЕЧЬ!», Leaf «ТЯНИ!», Gold «ВЗЯТЬ»).
	-- The caption sits on a dark ribbon across the bottom of the circle (readable on any colour).
	local action = Theme.candyButton(area, "ActionButton", "Sky", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 0.89),
		Size = UDim2.fromScale(0.43, 0.54),
		Visible = false,
		Radius = 0.5,
	})
	U.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, action)
	corner(action, 0.5) -- the Ring and the glow rings follow the round shape
	-- Ring: a white halo outside the Ink outline, lit while the button matters (bite, take).
	U.new("UIStroke", {
		Name = "Ring",
		Color = WHITE,
		Thickness = 5,
		Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Attributes = { BaseThickness = 5 },
	}, action)
	Theme.icon(action, "Icon", "🎣", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, FACE * 0.39),
		Size = UDim2.fromScale(0.74, FACE * 0.6),
		ZIndex = Z.Content,
	})
	local ribbon = U.new("Frame", {
		Name = "CaptionRibbon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.82),
		Size = UDim2.fromScale(1.16, 0.3),
		ZIndex = Z.Content + 1,
	}, action)
	Theme.candy(ribbon, "Night", { radius = 0.5, lip = 0.1, shine = false })
	label(action, "Caption", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.807),
		Size = UDim2.fromScale(1.04, 0.22),
		Text = "ЗАБРОСИТЬ",
		Outline = 2,
		ZIndex = Z.Content + 2,
		MaxTextSize = 28,
		MinTextSize = 9,
	})

	-- «СМОТАТЬ»: a small Berry candy pill above the action button, the 🧵 overhanging its left end.
	local stop = Theme.candyButton(area, "StopButton", "Berry", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 0.22),
		Size = UDim2.fromScale(0.43, 0.2),
		Visible = false,
		Radius = 0.5,
	})
	Theme.icon(stop, "Icon", "🧵", {
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.4, 0.5),
		Position = UDim2.fromScale(0, FACE * 0.48),
		Size = UDim2.fromScale(1.15, 1.15),
		Rotation = -14,
		ZIndex = Z.Content,
	})
	label(stop, "Caption", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.95, FACE * 0.5),
		Size = UDim2.fromScale(0.74, FACE * 0.64),
		Text = "СМОТАТЬ",
		Outline = 2,
		ZIndex = Z.Content,
		MaxTextSize = 24,
		MinTextSize = 9,
	})
end

--------------------------------------------------------------------------------
-- Bite alert
--------------------------------------------------------------------------------

local function buildBiteAlert(root: any)
	-- Where the minigame appears next (they are never shown together). A Sun candy pill:
	-- «КЛЮЁТ!» with ❗ on both ends and a candy countdown bar; FishingController slams it in
	-- and puts rays behind it (UiFx.rays at ZIndex 0 = behind the lip and the face).
	local alert = U.new("Frame", {
		Name = "BiteAlert",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = STACK_BOTTOM,
		Size = UDim2.fromScale(0.64, 0.165),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 4,
	}, root)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(380, 100) }, alert)
	Theme.candy(alert, "Sun", { radius = 0.5 })
	label(alert, "Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, FACE * 0.4),
		Size = UDim2.fromScale(0.64, FACE * 0.62),
		Text = "КЛЮЁТ!",
		Outline = 3,
		TextGradient = { WHITE, P.Gold.Top },
		ZIndex = Z.Content,
		MaxTextSize = 60,
	})
	for _, side in { { "IconLeft", 0.1, -14 }, { "IconRight", 0.9, 14 } } do
		Theme.icon(alert, side[1], "❗", {
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(side[2], FACE * 0.46),
			Size = UDim2.fromScale(1.05, 1.05),
			Rotation = side[3],
			ZIndex = Z.Content,
		})
	end
	-- Countdown: a dark candy track with the shrinking Timer over it (UiFx.timerBar: width
	-- 1 → 0, green → yellow → red). Timer is anchored left, so it drains towards the left end.
	local track = U.new("Frame", {
		Name = "TimerTrack",
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, FACE * 0.82),
		Size = UDim2.fromScale(0.6, FACE * 0.17),
		ZIndex = Z.Content,
	}, alert)
	corner(track, 0.5)
	local timer = U.new("Frame", {
		Name = "Timer",
		BackgroundColor3 = P.Leaf.Top,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.2, FACE * 0.82),
		Size = UDim2.fromScale(0.6, FACE * 0.17),
		ZIndex = Z.Content + 1,
	}, alert)
	corner(timer, 0.5)
	stroke(timer, 1.5)
	miniGloss(timer, 2)
end

--------------------------------------------------------------------------------
-- Minigame
--------------------------------------------------------------------------------

local function buildMinigame(root: any)
	-- A Night candy panel; width from the screen WIDTH (like the toasts), capped on big screens.
	-- Content ZIndex 4+ (the panel's lip/face are 1/2; UiFx.burst sparks go at 3 — they fly out
	-- from behind the track and never cover the needle or the zone).
	local mini = Theme.panel(root, "Minigame", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = STACK_BOTTOM,
		Size = UDim2.fromScale(0.36, 0.28),
		ZIndex = 4,
		Radius = 0.2,
	})
	U.new("UISizeConstraint", { MaxSize = Vector2.new(560, 170), MinSize = Vector2.new(280, 96) }, mini)
	-- Title in the rarity gradient (FishingController recolours "TextFill"; Mythic: rainbow).
	label(mini, "Title", {
		Position = UDim2.fromScale(0.045, 0.06),
		Size = UDim2.fromScale(0.6, 0.235),
		Text = "РЫБА НА КРЮЧКЕ!",
		TextXAlignment = Enum.TextXAlignment.Left,
		Outline = 2.5,
		TextGradient = { UI.Rarity.Common.Top, UI.Rarity.Common.Bottom },
		ZIndex = 4,
		MaxTextSize = 30,
	})
	-- Pips: hits needed (slots with a ghost ⭐) / done (green with a stamped ⭐).
	local pips = U.new("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(0.955, 0.065),
		Size = UDim2.fromScale(0.34, 0.22),
		ZIndex = 4,
	}, mini)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.04, 0),
	}, pips)
	for i = 1, 5 do
		local pip = U.new("Frame", {
			Name = `Pip{i}`,
			LayoutOrder = i,
			Visible = false,
			BackgroundColor3 = PIP_EMPTY,
			BorderSizePixel = 0,
			Size = UDim2.fromScale(1, 1),
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
		}, pips)
		corner(pip, 0.5)
		stroke(pip, 2)
		Theme.gradient(pip, WHITE, rgb(190, 196, 210)) -- "Fill": a light-to-shade tint of the colour
		Theme.icon(pip, "Star", "⭐", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.86, 0.86),
			Rotation = 0,
			TextTransparency = 0.72,
			ZIndex = 2,
		})
	end

	-- Track: a dark inset candy groove. Zone and Needle: Position.X.Scale is the centre
	-- (AnchorPoint 0.5), Size.X.Scale the width, both as fractions of the track (FishingRules:
	-- ZoneCenter, ZoneWidth, Needle).
	local track = U.new("Frame", {
		Name = "Track",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.33),
		Size = UDim2.fromScale(0.91, 0.3),
		ZIndex = 4,
	}, mini)
	corner(track, 0.4)
	stroke(track, 2.5)
	Theme.gradient(track, P.Night.Lip, rgb(40, 50, 92)) -- inset: dark at the top, lighter below
	-- Quarter ticks, so the eye can judge the needle's run.
	for i = 1, 3 do
		U.new("Frame", {
			Name = `Tick{i}`,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.86,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(i / 4, 0.5),
			Size = UDim2.fromScale(0.006, 0.5),
			ZIndex = 1,
		}, track)
	end
	-- The zone: a glossy Leaf candy (transparent root = the logical box) on a soft glow that
	-- breathes, plus a white Flash layer for hits. ZIndex 3: under the needle (6), above the
	-- needle's ghost trail (FishingController puts the ghosts at 2).
	local zone = U.new("Frame", {
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.3, 0.84),
		ZIndex = 3,
	}, track)
	local glow = U.new("Frame", {
		Name = "Glow",
		BackgroundColor3 = P.Leaf.Top,
		BackgroundTransparency = 0.55,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.08, 1.32),
		ZIndex = Z.Behind,
	}, zone)
	corner(glow, 0.4)
	Theme.candy(zone, "Leaf", { radius = 0.3, stroke = 2, shine = false })
	local flash = U.new("Frame", {
		Name = "Flash",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = Z.Overlay,
	}, zone)
	corner(flash, 0.3)
	-- The needle: a white candy capsule poking out of the groove (UiFx.trail adds ghosts).
	local needle = U.new("Frame", {
		Name = "Needle",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(0.026, 1.5),
		ZIndex = 6,
	}, track)
	corner(needle, 0.5)
	stroke(needle, 2)
	Theme.gradient(needle, WHITE, rgb(214, 224, 240), 0) -- left → right: a rounded, lit capsule

	-- Time left: a candy bar (FishingController: width = time left, green → yellow → red).
	local timeBar = U.new("Frame", {
		Name = "TimeBar",
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.695),
		Size = UDim2.fromScale(0.91, 0.075),
		ZIndex = 4,
	}, mini)
	corner(timeBar, 0.5)
	local fill = U.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = P.Leaf.Top,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, timeBar)
	corner(fill, 0.5)
	miniGloss(fill, 2)
	label(mini, "Help", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.94),
		Size = UDim2.fromScale(0.91, 0.16),
		Text = "Жми, когда стрелка в зелёной зоне!",
		TextColor3 = P.Cream.Bottom,
		ZIndex = 4,
		MaxTextSize = 20,
	})
end

--------------------------------------------------------------------------------
-- Hint
--------------------------------------------------------------------------------

local function buildHint(root: any)
	-- One or two lines at the bottom centre above the hotbar, between the thumbstick and the
	-- action button; the Minigame / BiteAlert stand on top of it (0.92H - HOTBAR - 6). A Night
	-- candy pill with the kind's emoji overhanging its left end (💡 info / ⚠️ warning).
	-- Hint.Text is the value; the visible text is Hint.Label (above the candy face).
	local hint = U.new("TextLabel", {
		Name = "Hint",
		Visible = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -HOTBAR),
		Size = UDim2.fromScale(0.5, 0.096),
		Text = "",
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		FontFace = Theme.FONT,
		ZIndex = 4,
	}, root)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(368, 56) }, hint)
	Theme.candy(hint, "Night", { radius = 0.5, transparency = 0.06 })
	Theme.icon(hint, "Icon", "💡", {
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.3, 0.48),
		Position = UDim2.fromScale(0, FACE * 0.5),
		Size = UDim2.fromScale(1.12, 1.12),
		Rotation = -10,
		ZIndex = Z.Content,
	})
	label(hint, "Label", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.965, FACE * 0.5),
		Size = UDim2.fromScale(0.86, FACE * 0.86),
		Text = "",
		TextWrapped = true,
		Outline = 2,
		ZIndex = Z.Content,
		MaxTextSize = 24,
	})
end

--------------------------------------------------------------------------------
-- Catch card: the big reveal
--------------------------------------------------------------------------------

local function buildCatch(root: any)
	-- The dim behind the card (darker at the top and bottom). Not Active: never blocks input.
	local dim = U.new("Frame", {
		Name = "CatchDim",
		Visible = false,
		Active = false,
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1.6, 2), -- with a margin: covers notches and the inset band too
		ZIndex = 6,
	}, root)
	U.new("UIGradient", {
		Name = "Vignette",
		Rotation = 90,
		Transparency = Theme.numbers({ { 0, 0 }, { 0.25, 0.12 }, { 0.5, 0.5 }, { 0.75, 0.12 }, { 1, 0 } }),
	}, dim)

	-- Same box as the card: UiFx.rays sizes its sunburst by this holder's height.
	local cardSize = UDim2.fromScale(0.58, 0.58)
	local cardPosition = UDim2.new(0.5, 0, 1, -HOTBAR)
	local rays = U.new("Frame", {
		Name = "CatchRays",
		Visible = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = cardPosition,
		Size = cardSize,
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 7,
	}, root)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(380, 400) }, rays)

	-- The card: a modal between the status stack (base badge, catch counter) and the hotbar
	-- (tap anywhere on it to close). A Cream candy.
	local card = U.new("TextButton", {
		Name = "CatchCard",
		Visible = false,
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = cardPosition,
		Size = cardSize,
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 10,
	}, root)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(380, 400) }, card)
	corner(card, 0.09)
	Theme.candy(card, "Cream", { radius = 0.09, lip = 0.035 })

	-- Rarity banner overhanging both sides (FishingController: UiFx.setCandy with
	-- UIConfig.Rarity[r]; Mythic: an animated rainbow + sparkles).
	local banner = U.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.03),
		Size = UDim2.fromScale(1.08, 0.165),
		ZIndex = 4,
	}, card)
	local common = UI.Rarity.Common
	Theme.candy(banner, { Top = common.Top, Bottom = common.Bottom, Lip = common.Lip }, { radius = 0.5 })
	label(banner, "RarityLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, FACE * 0.5),
		Size = UDim2.fromScale(0.74, FACE * 0.7),
		Text = "ОБЫЧНАЯ",
		Outline = 2.5,
		ZIndex = Z.Content,
		MaxTextSize = 34,
	})
	for _, side in { { "StarLeft", 0.075, -14 }, { "StarRight", 0.925, 14 } } do
		Theme.icon(banner, side[1], "⭐", {
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(side[2], FACE * 0.48),
			Size = UDim2.fromScale(0.85, 0.85),
			Rotation = side[3],
			ZIndex = Z.Content,
		})
	end

	-- The fish on a soft rarity glow: three discs (halo, disc, white core) in a transparent root
	-- that FishingController breathes; it tints Halo and Disc with the rarity colour.
	local glow = U.new("Frame", {
		Name = "FishGlow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.39),
		Size = UDim2.fromScale(0.4, 0.4),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 3,
	}, card)
	for i, disc in { { "Halo", 1.32, 0.78, common.Top }, { "Disc", 1, 0.5, common.Top }, { "Core", 0.6, 0.3, WHITE } } do
		local frame = U.new("Frame", {
			Name = disc[1],
			BackgroundColor3 = disc[4],
			BackgroundTransparency = disc[3],
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(disc[2], disc[2]),
			ZIndex = i,
		}, glow)
		corner(frame, 0.5)
	end
	U.new("ViewportFrame", {
		Name = "Viewport",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.39),
		Size = UDim2.fromScale(0.92, 0.39),
		Ambient = rgb(200, 200, 210),
		LightColor = rgb(255, 250, 240),
		LightDirection = Vector3.new(-1, -1.4, -0.8),
		ZIndex = 5,
	}, card)
	-- «НОВАЯ!»: stamped on the first catch of a species this session.
	Theme.pill(card, "NewStamp", "Berry", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.23, 0.245),
		Size = UDim2.fromScale(0.36, 0.088),
		Rotation = -12,
		ZIndex = 8,
		Icon = "✨",
		IconScale = 1.25,
		Text = "НОВАЯ!",
		MaxTextSize = 24,
	})

	label(card, "NameLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.585),
		Size = UDim2.fromScale(0.92, 0.105),
		Text = "Карасик",
		Outline = 3,
		TextGradient = { WHITE, common.Top },
		ZIndex = 6,
		MaxTextSize = 44,
	})

	-- Mutation badge (UIConfig.Mutations: Gold / Neon / Rainbow candies with their icon);
	-- MutationLabel.Text is the value, MutationLabel.Caption shows it.
	local mutation = U.new("TextLabel", {
		Name = "MutationLabel",
		Visible = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.697),
		Size = UDim2.fromScale(0.88, 0.078),
		Text = "",
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		FontFace = Theme.FONT,
		ZIndex = 7,
	}, card)
	local gold = UI.Mutations.Gold
	Theme.candy(mutation, { Top = gold.Top, Bottom = gold.Bottom, Lip = gold.Lip }, { radius = 0.5, stroke = 2.5 })
	Theme.icon(mutation, "Icon", gold.Icon, {
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.35, 0.5),
		Position = UDim2.fromScale(0, FACE * 0.46),
		Size = UDim2.fromScale(1.45, 1.45),
		Rotation = -14,
		ZIndex = Z.Content,
	})
	label(mutation, "Caption", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.95, FACE * 0.5),
		Size = UDim2.fromScale(0.83, FACE * 0.8),
		Text = "",
		Outline = 2,
		ZIndex = Z.Content,
		MaxTextSize = 24,
	})

	-- Weight and price chips; InfoLabel.Text is the summary «1,2 кг · цена 35 💰» (the value),
	-- Price.Label counts up from 0.
	local info = U.new("TextLabel", {
		Name = "InfoLabel",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.79),
		Size = UDim2.fromScale(0.84, 0.08),
		Text = "",
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		FontFace = Theme.FONT,
		ZIndex = 6,
	}, card)
	Theme.pill(info, "Weight", "Sky", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0.04, 0),
		Size = UDim2.fromScale(0.42, 1),
		Icon = "⚖️",
		IconScale = 1.3,
		Text = "1 кг",
		MaxTextSize = 24,
	})
	Theme.pill(info, "Price", "Gold", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.44, 1),
		Icon = "💰",
		IconScale = 1.45,
		Text = "0",
		MaxTextSize = 26,
	})

	label(card, "TapHint", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.952),
		Size = UDim2.fromScale(0.8, 0.062),
		Text = "Нажми, чтобы закрыть",
		TextColor3 = rgb(130, 120, 100),
		TextStrokeTransparency = 1,
		ZIndex = 6,
		MaxTextSize = 16,
		MinTextSize = 9,
	})
end

--[[
	Fishing UI (stage 2), all under HUD.Fishing (FishingController drives it; everything starts
	hidden). ZIndex inside Fishing: Hint / BiteAlert / Minigame 4, CatchDim 6, CatchRays 7,
	ActionArea 9, CatchCard 10.
	  ActionArea              bottom-right container, sized by screen height
	    ActionButton          big round candy: Icon, CaptionRibbon + Caption («ЗАБРОСИТЬ» /
	                          «ЖДЁМ…» / «ПОДСЕЧЬ!» / «ТЯНИ!» / «ВЗЯТЬ»), Ring (white halo)
	    StopButton            «СМОТАТЬ» Berry pill above it (Icon 🧵, Caption)
	  BiteAlert               Sun pill: «КЛЮЁТ!» (Label), ❗ IconLeft/IconRight, TimerTrack + Timer
	  Minigame                Night panel: Title (rarity gradient), Pips (Pip1..Pip5 with a Star),
	                          Track (Zone: Glow, candy, Flash; Needle), TimeBar (Fill), Help
	  Hint                    Night pill: Icon + Label (Hint.Text = the value)
	  CatchDim, CatchRays     the reveal's dim and the holder of its sunburst, behind the card
	  CatchCard               TextButton (tap to close): Banner (RarityLabel, stars), FishGlow,
	                          Viewport (the fish model), NewStamp, NameLabel, MutationLabel
	                          (Icon, Caption), InfoLabel (Weight, Price pills), TapHint
]]
local function buildFishing(hud: any)
	local root = U.new("Frame", {
		Name = "Fishing",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2, -- above HUD.Toasts (Sibling): the minigame, bite alert and card cover toasts
	}, hud)
	buildActionArea(root)
	buildBiteAlert(root)
	buildMinigame(root)
	buildHint(root)
	buildCatch(root)
end

return buildFishing
