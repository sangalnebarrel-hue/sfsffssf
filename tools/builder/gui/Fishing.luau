--[[
	Fishing — HUD.Fishing (stage 2) in the UI v5 «Симулятор» style (the user's reference: chunky
	gradient plates with a thick outline in a dark shade of their own hue, outlined emoji, white
	Montserrat Heavy text with a dark outline, dark glass pills; NO studs — they belong to the
	map): the action button, the bite alert, the minigame, the hint and the catch card (the big
	reveal). Controller and all the motion: FishingController (UiFx). Layout rules:
	tools/builder/Gui.luau; look and API: tools/builder/gui/STYLE.md.

	Names are a contract (FishingController, tests and the preview scenarios find widgets by
	name); everything not listed here is decoration and may change:
	  ActionArea.ActionButton.{Icon, Caption, Ring}   ActionArea.StopButton.Caption
	  BiteAlert.{Label, Timer}   Minigame.{Title, Pips.Pip1..Pip5, Track.{Zone, Needle},
	  TimeBar.Fill, Help}   Hint   CatchCard.{Banner.RarityLabel, Viewport, NameLabel,
	  MutationLabel, InfoLabel, TapHint}
	UI v2, the playing widgets (FishingController): ActionArea.ActionButton.{KeyChip.Key, TapCue,
	Bobber, Badge} (the desktop key chip, the first-timer 👆, the waiting look's icon, the red «!»
	newcomer badge), BiteAlert.{IconLeft, IconRight, TapPad} (the «!» glyphs, the touch tap pad
	over the plate), Minigame.{Clock, TapPad, Track.Rider, Track.Needle.Head} (⏱, the touch tap
	pad over the panel, the fish riding the zone — its glyph by rarity, the ▼ needle head),
	Hint.IconSocket.Icon (the hint's emoji).
	Value-holding labels on plates (Hint, CatchCard.MutationLabel, CatchCard.InfoLabel) keep
	their Text as the contract value but draw it through children (children render above their
	parent, so the plate's face would hide the label's own text): Hint.Label, MutationLabel.Caption,
	InfoLabel.Weight / InfoLabel.Price (chips; the price counts up). The catch also uses (by name)
	CatchCard.{FishGlow, NewStamp, Lip (its outline), InfoLabel.Price.Multiplier, Pedestal} and
	TitleSlam.{Label, Letters} (the giant rarity title).
	Minigame pips keep a visible BackgroundColor3 (filled = green 64,200,96, as the e2e bot reads
	it); the zone and the needle keep Position.X = centre and Size.X = width in track fractions.

	The widgets (still built through the v3 / v4 Theme names — brick, tile, roundPlate,
	candyButton, pill — which now build sim plates; the fishing waves move them to sim / glass /
	simButton / plate): the action button is a round sim disc with the chunky outline and a gloss,
	an outlined emoji in the middle, the caption on a dark glass pill across its bottom and a red
	«!» badge on its upper left shoulder for a newcomer; «СМОТАТЬ» a red sim button, the key chip a
	small white chip; the bite alert an orange plate; the hint a dark glass pill with italic text;
	the minigame a dark plate with a black groove, the zone a green bar the fish rides on, pips as
	round chips; the catch card a white plate (the fish in a display window on a podium in the
	rarity's colour, the rarity banner a long plate, the price a yellow chip, the weight a grey
	chip, «НОВИНКА!» a red stamp).
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
local BZ = Theme.BZ
local INK = Theme.INK
local WHITE = Theme.WHITE
local HOTBAR = Theme.HOTBAR
local corner = Theme.corner
local stroke = Theme.stroke
local label = Theme.label

-- The action disc: the centre of its icon, a share of the disc's height (a little above the
-- middle, clear of the caption pill across its bottom).
local ICON_Y = 0.414

-- Pip colours: the e2e bot recognises a filled pip by this exact green (FishingController too);
-- an empty pip is a light grey chip with a faint white ★.
local PIP_DONE = rgb(64, 200, 96)
local PIP_EMPTY = P.Slate.Bottom

-- The bottom line of the centre column (Hint, BiteAlert, Minigame): 16 px above the screen
-- bottom (v3: the Roblox hotbar is off — HudController disables the Backpack CoreGui, HOTBAR = 0 —
-- so the column stays UNDER the fisher's feet on a phone instead of on his body). The hint and
-- the bite/minigame never show together (FishingController hides the hint for the bite and
-- shows the miss hint as the miss ghost leaves), so they share the line and the stack stays low.
-- FishingController moves the column sideways on narrow screens (clear of the thumbstick and
-- the action button) through Position.X.Offset; X.Scale stays 0.5. On phones (HUD under 500 px
-- tall) the minigame docks LEFT of the own fisher instead (FishingLayout), the bite and the hint
-- shrink / slide off him if they would touch him.
local STACK_BOTTOM = UDim2.new(0.5, 0, 1, -HOTBAR - 16)

-- A white highlight band in the top part of a small flat shape (bars).
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

-- A dark groove (the minigame's track, the bite and time bars): Coal with a shadow at the top
-- (it is cut INTO the plate), an Ink outline.
local function groove(parent: any, name: string, props: { [string]: any }, radius: number, thickness: number): any
	local base: { [string]: any } = {
		Name = name,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
	}
	for key, value in props do
		base[key] = value
	end
	local frame = U.new("Frame", base, parent)
	corner(frame, radius)
	stroke(frame, thickness)
	U.new("UIGradient", {
		Name = "Shade", -- (not "Fill": the time bar's Fill is its draining child)
		Rotation = 90,
		Color = Theme.sequence({ P.Coal.Lip, P.Coal.Bottom, P.Coal.Top }),
	}, frame)
	return frame
end

--------------------------------------------------------------------------------
-- Action area: the round action disc and the «СМОТАТЬ» button
--------------------------------------------------------------------------------

local function buildActionArea(root: any)
	-- Action area: 0.66H wide, 0.46H tall (at most 320 x 240 px), in the bottom-right corner. The
	-- button sits at its LEFT edge, so the right part stays free for the Jump button: on a
	-- phone (844x390) the caption tile ends ≈22 px before Jump (glow rings too); on a 4:3
	-- tablet the plate is 16 px left of Jump, its caption tile passes ≈20 px below it, and the
	-- area (capped at 320 px, not wider) stays clear of the centred catch card.
	-- ZIndex 9: above the catch card's dim and rays (the button closes the card too), below the
	-- card itself.
	local area = U.new("Frame", {
		Name = "ActionArea",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.fromScale(1, 1),
		Size = UDim2.fromScale(0.66, 0.46),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 9,
	}, root)
	-- Capped on big screens; FishingController keeps the centre column (hint, bite alert,
	-- minigame) between the thumbstick and this area.
	U.new("UISizeConstraint", { MaxSize = Vector2.new(320, 240) }, area)

	-- The star of the screen: a round sim disc (Theme.roundPlate: the light → juicy gradient, the
	-- chunky outline in a dark shade of its hue, a light rim and a gloss) with an outlined emoji in
	-- the middle. FishingController recolours it per state with UiFx.setCandy (Sky «ЗАБРОСИТЬ»,
	-- Slate «ЖДЁМ…» / «КУДА ИДТИ?», Pond «ЖДИ КЛЁВА…» (line in the water), Sun «ПОДСЕЧЬ!», Leaf
	-- «ЛОВИ!» / «ЗАБРАТЬ!», Gold «ВЗЯТЬ»), makes it breathe and wiggle its icon at rest. The
	-- caption sits on a dark glass pill across the bottom of the disc (readable on any colour),
	-- at the Button text tier: the pill is wide enough for «ЗАБРОСИТЬ» at 16+ px on the smallest
	-- phone. A press squashes the whole button (UiFx.press) and kicks the icon.
	local action = U.new("TextButton", {
		Name = "ActionButton",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		-- (2 px left of the area's edge: with the chunky outline the disc keeps 16 px to Jump on a
		-- 4:3 tablet and still does not slip under the square catch card; the centre column keeps
		-- COLUMN_GAP to the area, so ≥ 20 px to the disc.)
		Position = UDim2.new(0, -2, 0.9, 0),
		Size = UDim2.fromScale(0.43, 0.56),
		Visible = false,
	}, area)
	U.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, action)
	corner(action, 0.5) -- the Ring and the glow rings follow the round shape
	Theme.roundPlate(action, "Sky")
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
	-- The icon in the middle of the disc: an outlined emoji per state (the reference's
	-- black-outlined icons); on the bite it becomes the «!» glyph (white → gold): FishingController
	-- turns TextFill on for it and makes the one "Outline" thicker (5 at 720), never off.
	local icon = Theme.icon(action, "Icon", "🎣", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, ICON_Y),
		Size = UDim2.fromScale(0.58, 0.58),
		ZIndex = BZ.Content,
		Outline = 3.5,
	})
	U.new("UIGradient", {
		Name = "TextFill",
		Enabled = false,
		Color = Theme.sequence({ WHITE, P.Gold.Top }),
		Rotation = 90,
	}, icon)
	-- Waiting for a bite («ЖДИ КЛЁВА…» on Pond): a drawn bobber instead of the emoji — a red/white
	-- ball with an Ink outline and a little antenna (FishingController bobs it and sends ripples
	-- from it). Its Position belongs to that bob (a looping tween).
	local bobber = U.new("Frame", {
		Name = "Bobber",
		Visible = false,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, ICON_Y + 0.03),
		Size = UDim2.fromScale(0.3, 0.3),
		ZIndex = BZ.Content,
	}, action)
	corner(bobber, 0.5)
	stroke(bobber, 3)
	U.new("UIGradient", {
		Name = "Fill",
		Rotation = 90,
		Color = U.roblox.ColorSequence.new({
			U.roblox.ColorSequenceKeypoint.new(0, P.Berry.Top),
			U.roblox.ColorSequenceKeypoint.new(0.47, P.Berry.Bottom),
			U.roblox.ColorSequenceKeypoint.new(0.53, WHITE),
			U.roblox.ColorSequenceKeypoint.new(1, P.Cream.Bottom),
		}),
	}, bobber)
	local antenna = U.new("Frame", {
		Name = "Antenna",
		BackgroundColor3 = P.Berry.Bottom,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.06),
		Size = UDim2.fromScale(0.16, 0.42),
		ZIndex = 0,
	}, bobber)
	corner(antenna, 0.5)
	stroke(antenna, 2.5)
	-- The caption pill: dark glass over the bottom of the disc (Theme.tile of a dark token = glass),
	-- the caption on it in CAPS at the Button tier.
	local ribbon = U.new("Frame", {
		Name = "CaptionRibbon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromScale(1.3, 0.3),
		ZIndex = BZ.Content + 1,
	}, action)
	Theme.tile(ribbon, "Coal", { radius = 0.3, shine = false })
	label(action, "Caption", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromScale(1.22, 0.23),
		Text = "ЗАБРОСИТЬ",
		ZIndex = BZ.Content + 2,
		Tier = "Button",
	})
	-- Desktop / console: the action key as a little white key chip on the disc's shoulder (an
	-- Ink «F» / «R2»), instead of a «[F]» suffix that would shrink the caption.
	local chip = U.new("Frame", {
		Name = "KeyChip",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.9, 0.12),
		Size = UDim2.fromScale(0.3, 0.3),
		ZIndex = BZ.Content + 3,
	}, action)
	Theme.tile(chip, "Cream", { radius = 0.28, shine = false })
	label(chip, "Key", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.84, 0.76),
		Text = "F",
		TextColor3 = INK,
		TextStrokeTransparency = 1,
		ZIndex = BZ.Content,
		Tier = "Small",
	})
	-- The reference's red «!» notification badge, on the disc's upper LEFT shoulder (the key chip
	-- has the right one on a PC): FishingController pops it in and wobbles it on «ВЗЯТЬ» /
	-- «ЗАБРОСИТЬ» until the session's first cast (UiFx.badgeBob / badgeHide). Hidden by default.
	Theme.badge(action, "Badge", {
		Position = UDim2.fromScale(0.13, 0.13),
		Size = UDim2.fromScale(0.3, 0.3),
		ZIndex = BZ.Content + 3,
	})
	-- First-timer cue: a 👆 tapping the button while the needle is in the zone (the player's
	-- first minigames of the session; FishingController shows it and bounces it). On the
	-- plate's lower right, above the caption tile and inside the button's right edge (the
	-- bounce never comes near the Jump button on its right).
	Theme.icon(action, "TapCue", "👆", {
		Visible = false,
		MaxTextSize = 64,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.66, 0.28),
		Size = UDim2.fromScale(0.48, 0.48),
		Rotation = -16,
		ZIndex = BZ.Content + 4,
	})

	-- «СМОТАТЬ»: a red sim button above the action disc with the outlined 🎣 («reel the rod in»)
	-- at its left end; 0.3 of the area tall and never under 44 px (a full-size tap target on every
	-- phone), its bottom 0.18 of the area down: ≥ 22 px above the action disc on phones, so a thumb
	-- mashing the big button does not slip onto it (FishingController also hides it while a
	-- fish is on the hook: the bite and the minigame). Narrow enough to stay clear of the Home
	-- button on the right.
	local stop = Theme.candyButton(area, "StopButton", "Berry", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 0.18),
		Size = UDim2.fromScale(0.56, 0.3),
		Visible = false,
		Radius = UI.Sim.Radius,
	})
	U.new("UISizeConstraint", { MinSize = Vector2.new(0, 44) }, stop)
	Theme.icon(stop, "Icon", "🎣", {
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.04, 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		ZIndex = BZ.Content,
	})
	label(stop, "Caption", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.95, 0.5),
		Size = UDim2.fromScale(0.68, 0.64),
		Text = "СМОТАТЬ",
		ZIndex = BZ.Content,
		Tier = "Button",
	})
end

--------------------------------------------------------------------------------
-- Bite alert
--------------------------------------------------------------------------------

local function buildBiteAlert(root: any)
	-- Where the minigame appears next (they are never shown together). An orange sim plate:
	-- «КЛЮЁТ!» with a «!» glyph on both ends and a countdown in a black groove; FishingController
	-- slams it in and puts calm rays behind it (UiFx.rays at ZIndex 0 = behind the outline and the
	-- face). 0.8H x 0.21H: ≈265 x 70 px on a phone,
	-- «КЛЮЁТ!» ≈38 px; 380 x 100 at most (PC, tablet).
	local alert = U.new("Frame", {
		Name = "BiteAlert",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = STACK_BOTTOM,
		Size = UDim2.fromScale(0.8, 0.21),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 4,
	}, root)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(380, 100) }, alert)
	Theme.brick(alert, "Sun", {
		radius = 0.22,
	})
	label(alert, "Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.6, 0.62),
		Text = "КЛЮЁТ!",
		Outline = 5,
		TextGradient = { WHITE, P.Gold.Top },
		ZIndex = BZ.Content,
		MaxTextSize = 64,
	})
	-- «!» glyphs (not the ❗ emoji: red on orange disappears): the world marker's look —
	-- white → gold text with a thick Ink outline, tilted outwards.
	for _, side in { { "IconLeft", 0.095, -10 }, { "IconRight", 0.905, 10 } } do
		label(alert, side[1], {
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(side[2], 0.47),
			Size = UDim2.fromScale(0.5, 1.02),
			Text = "!",
			Rotation = side[3],
			Outline = 5,
			TextGradient = { WHITE, P.Gold.Top },
			ZIndex = BZ.Content,
			MaxTextSize = 96,
		})
	end
	-- Countdown: a black groove with the shrinking Timer over it (UiFx.timerBar: width 1 → 0,
	-- green → yellow → red). Timer is anchored left, so it drains towards the left end.
	groove(alert, "TimerTrack", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.82),
		Size = UDim2.fromScale(0.6, 0.17),
		ZIndex = BZ.Content,
	}, 0.5, 3)
	local timer = U.new("Frame", {
		Name = "Timer",
		BackgroundColor3 = P.Leaf.Top,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.2, 0.82),
		Size = UDim2.fromScale(0.6, 0.17),
		ZIndex = BZ.Content + 1,
	}, alert)
	corner(timer, 0.5)
	stroke(timer, 2)
	miniGloss(timer, 2)

	-- Touch screens: a tap on the plate hooks like «ПОДСЕЧЬ!» (kids tap the big «КЛЮЁТ!»
	-- first). Transparent, on top of the plate; FishingController shows it with a touch screen.
	U.new("TextButton", {
		Name = "TapPad",
		Visible = false,
		Active = true,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
	}, alert)
end

--------------------------------------------------------------------------------
-- Minigame
--------------------------------------------------------------------------------

-- The panel's corners.
local PLATE_RADIUS = 0.1

local function buildMinigame(root: any)
	-- A dark Night sim panel (opaque); width from the screen WIDTH (like the toasts), capped on
	-- big screens. Rows (fractions of the panel height): the rarity title (0.095..0.255) — a band where
	-- the 🐟 rider and the ▼ needle head stand on the track — the track (0.42..0.63) — the status
	-- row (⏱ + time bar left, hit pips right) — the help line. Content ZIndex 4..7; effects
	-- (sparks, words) go at 8 over the panel, the touch TapPad at 9 on top of everything.
	local mini = U.new("Frame", {
		Name = "Minigame",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = STACK_BOTTOM,
		Size = UDim2.fromScale(0.4, 0.37),
		ZIndex = 4,
	}, root)
	-- (MinSize 208 wide: docked left of the fisher on the smallest phone — with the fishing camera
	-- offset he stands left of the middle — it is ≈ 220 px.)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(520, 210), MinSize = Vector2.new(208, 92) }, mini)
	Theme.brick(mini, "Night", { radius = PLATE_RADIUS, shine = false })
	-- Epic+ aura: a rarity-coloured rim outside the Ink outline (FishingController enables it
	-- and recolours / animates "AuraFill": Legendary — a gold shine band, Mythic — a rainbow).
	corner(mini, PLATE_RADIUS)
	local aura = U.new("UIStroke", {
		Name = "AuraStroke",
		Enabled = false,
		Color = WHITE,
		Thickness = 6,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		LineJoinMode = Enum.LineJoinMode.Round,
		Attributes = { BaseThickness = 6 },
	}, mini)
	U.new("UIGradient", { Name = "AuraFill", Color = Theme.sequence({ WHITE, WHITE }) }, aura)

	-- Title in the rarity gradient (FishingController recolours "TextFill": white → rarity;
	-- Mythic: a running rainbow), centred over the whole width.
	label(mini, "Title", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.105),
		Size = UDim2.fromScale(0.91, 0.15),
		Text = "РЫБА НА КРЮЧКЕ!",
		TextGradient = { WHITE, UI.Rarity.Common.Top },
		ZIndex = 5,
		Tier = "Title",
	})

	-- Track: a black groove cut into the plate. Zone and Needle: Position.X.Scale is the centre
	-- (AnchorPoint 0.5), Size.X.Scale the width, both as fractions of the track (FishingRules:
	-- ZoneCenter, ZoneWidth, Needle). What is drawn along X is exactly what the server checks:
	-- nothing scales the zone sideways (FishingController pops it only in height).
	local track = groove(mini, "Track", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.91, 0.21),
		ZIndex = 4,
	}, 0.3, 3)
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
	-- The zone: a green sim bar with a thin outline (transparent root = the logical box; the rider
	-- stands on it) on a soft light-green glow that breathes in HEIGHT
	-- only (its width is the zone's), plus a white Flash layer for hits. ZIndex 3: under the
	-- rider (5) and the needle (6), above the needle's ghost trail (2).
	local zone = U.new("Frame", {
		Name = "Zone",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.3, 0.84),
		ZIndex = 3,
	}, track)
	local glow = U.new("Frame", {
		Name = "Glow",
		BackgroundColor3 = UI.Fishing.ZoneGlow,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1.42),
		ZIndex = BZ.Behind,
	}, zone)
	corner(glow, 0.4)
	Theme.brick(zone, "Leaf", {
		radius = 0.28,
		stroke = 3,
		shine = false,
	})
	local flash = U.new("Frame", {
		Name = "Flash",
		BackgroundColor3 = WHITE,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = BZ.Overlay,
	}, zone)
	corner(flash, 0.28)
	-- The fish on the hook: a 🐟 standing on the zone (FishingController keeps it over
	-- the zone, wiggles it and makes it hop to the next zone). Above the zone, under the needle.
	local rider = Theme.icon(track, "Rider", "🐟", {
		Visible = false,
		MaxTextSize = 48,
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.04),
		Size = UDim2.fromScale(0.9, 0.9),
		Rotation = 0,
		ZIndex = 5,
	})
	corner(rider, 0.5) -- round glow rings around the rider (Legendary / Mythic)
	-- The needle: a thin white bar poking out of the groove (UiFx.trail adds ghosts) with a ▼
	-- head above the groove, so «стрелка» is literally an arrow.
	local needle = U.new("Frame", {
		Name = "Needle",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(0.026, 1.5),
		ZIndex = 6,
	}, track)
	corner(needle, 0.35)
	stroke(needle, 3)
	Theme.gradient(needle, WHITE, UI.Fishing.NeedleShade, 0) -- left → right: a lit, rounded bar
	label(needle, "Head", {
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.2),
		Size = UDim2.fromScale(0.5, 0.42),
		Text = "▼",
		Outline = 3,
		ZIndex = 2,
		MaxTextSize = 40,
	})

	-- Status row: ⏱ and the time left (a cool bar: full = icy blue → Sun → Berry, so the zone
	-- stays the only green in the panel) on the left, the hit pips on the right.
	Theme.icon(mini, "Clock", "⏱", {
		MaxTextSize = 40,
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.04, 0.73),
		Size = UDim2.fromScale(0.16, 0.16),
		ZIndex = 5,
	})
	local timeBar = groove(mini, "TimeBar", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.105, 0.73),
		Size = UDim2.fromScale(0.56, 0.065),
		ZIndex = 4,
	}, 0.5, 2)
	local fill = U.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = UI.Fishing.TimeBar[1],
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, timeBar)
	corner(fill, 0.5)
	miniGloss(fill, 2)
	-- Pips: hits needed — round chips (a light grey chip with a faint white ★: its "Fill" lights
	-- the colour from the top left, a translucent white "Cap" is its gloss) / done (the same chip
	-- in green with a stamped ⭐). The pip's own BackgroundColor3 is
	-- the colour (the e2e bot reads it), the gradient and the cap only light it.
	local pips = U.new("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.955, 0.73),
		Size = UDim2.fromScale(0.3, 0.16),
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
		stroke(pip, 2.5)
		Theme.gradient(pip, WHITE, UI.Fishing.PipShade, 45) -- "Fill": lit top-left → shade
		local cap = U.new("Frame", {
			Name = "Cap",
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 0.7,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.43, 0.41),
			Size = UDim2.fromScale(0.68, 0.68),
			ZIndex = 1,
		}, pip)
		corner(cap, 0.5)
		Theme.icon(pip, "Star", "★", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.78, 0.78),
			Rotation = 0,
			TextTransparency = 0.55,
			ZIndex = 2,
		})
	end

	label(mini, "Help", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.808),
		Size = UDim2.fromScale(0.91, 0.125),
		Text = "Жми «ЛОВИ!» в зелёной зоне",
		TextColor3 = P.Cream.Bottom,
		ZIndex = 5,
		Tier = "Body",
	})

	-- Touch screens: a tap anywhere on the panel counts like a tap on «ЛОВИ!» (FishingController
	-- shows the pad only with a touch screen). Transparent, on top of the panel's content.
	U.new("TextButton", {
		Name = "TapPad",
		Visible = false,
		Active = true,
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		Text = "",
		Size = UDim2.fromScale(1, 1),
		ZIndex = 9,
	}, mini)
end

--------------------------------------------------------------------------------
-- Hint
--------------------------------------------------------------------------------

local function buildHint(root: any)
	-- One or two lines (the Body tier) at the bottom of the centre column, 16 px above the
	-- screen bottom (under the fisher's feet on a phone), between the thumbstick and the action
	-- button (FishingController moves it sideways on narrow screens and sizes the tile to its
	-- text: FishingLayout.hintWidth). A smooth tile by kind — dark stone Night (info), Sun (warning), Berry
	-- (danger) — with the kind's emoji in a white round tile on its left end, like the toasts.
	-- The bite alert and the minigame use the same bottom line: they never show together.
	-- Hint.Text is the value; the visible text is Hint.Label (above the tile's face).
	local hint = U.new("TextLabel", {
		Name = "Hint",
		Visible = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = STACK_BOTTOM,
		Size = UDim2.fromScale(0.5, 0.12),
		Text = "",
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		FontFace = Theme.FONT,
		ZIndex = 4,
	}, root)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(440, 64) }, hint)
	Theme.tile(hint, "Night", { radius = 0.25 })
	Theme.socket(hint, "IconSocket", "💡", {
		AnchorPoint = Vector2.new(0.3, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(1.12, 1.12),
		ZIndex = BZ.Content,
	})
	label(hint, "Label", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.955, 0.5),
		Size = UDim2.fromScale(0.8, 0.9),
		Text = "",
		TextWrapped = true,
		Italic = true, -- the reference's timer pill: italic white text on dark glass
		ZIndex = BZ.Content,
		Tier = "Body",
	})
end

--------------------------------------------------------------------------------
-- Catch card: the big reveal (UI v2: FUI-02 / 03 / 07 / 12; UI v5 «Симулятор»: a white sim
-- display plate with the chunky outline, a rarity ribbon, a podium, gold and grey chips)
--------------------------------------------------------------------------------

--[[
	The card as built here is the SQUARE layout (desktop / tablet, 380 x 384 at most). On short
	screens (HUD under 500 px tall: phones) FishingController re-lays the same instances out as
	a landscape trophy card (CARD_WIDE in the controller): the fish on the left, name / chips /
	tap hint in a right column, the same child names (also the display window under its Face:
	Face.Window). The controller also places the card itself every time it opens: beside the own
	fisher and his trophy where a side gap fits it (FishingLayout.cardDock / dockSide), else
	centred in its slot; CatchRays is the layer of its sunburst (CatchFx.raysFrame: the whole
	screen, or up to the fisher's edge when the card is docked — the rays never reach him).
]]
local CARD_RADIUS = 0.07
-- The share of the card the v4 plate's face covered (it had a side band): the window and the
-- children were laid out in it; kept so the tuned layout stays put.
local CARD_FACE = 0.965

-- Name text: white → the rarity's colours with an Ink outline, like every other word of the
-- reference (FishingController paints the fill per rarity).
local NAME_COMMON = { WHITE, UI.Rarity.Common.Bottom }

-- The display window behind the fish: a pale sky panel with a dark slate-blue frame.
local WINDOW_TOP = rgb(250, 253, 255)
local WINDOW_BOTTOM = rgb(207, 230, 250)
local WINDOW_EDGE = rgb(44, 58, 79)

--[[
	The podium the fish stands on (SIM-C1-05: a trophy stand, not an empty bar): three stacked
	sim shapes in the rarity's colours, outlined in its dark shade — a light oval Cap (its top,
	with the fish's soft Shadow on it), the Pedestal itself as the column (its face — the rarity
	gradient — with an outlined ⭐ on the front) and a darker Base slab. FishingController paints
	it per rarity (CatchFx.paintPodium) and pops it in under the fish.
]]
local function buildPodium(card: any, look: any)
	local pedestal = U.new("Frame", {
		Name = "Pedestal",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.59),
		Size = UDim2.fromScale(0.2, 0.07),
		ZIndex = 4,
	}, card)
	Theme.sim(pedestal, look, { radius = 0.22, stroke = Theme.MINOR, rim = 1.5, shine = false })
	local function slab(name: string, y: number, w: number, h: number, round: boolean): any
		local frame = U.new("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, y),
			Size = UDim2.fromScale(w, h),
			ZIndex = 3,
		}, pedestal)
		return Theme.sim(frame, look, {
			round = round,
			radius = 0.35,
			stroke = Theme.MINOR,
			rim = 1.5,
			shine = false,
		})
	end
	slab("Base", 1, 1.34, 0.46, false)
	local cap = slab("Cap", 0, 1.56, 0.62, true)
	local shadow = U.new("Frame", {
		Name = "Shadow",
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.7,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.42),
		Size = UDim2.fromScale(0.5, 0.42),
		ZIndex = 3,
	}, cap)
	corner(shadow, 0.5)
	Theme.icon(pedestal, "Star", "⭐", {
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.58),
		Size = UDim2.fromScale(0.96, 0.96),
		ZIndex = 4,
		Outline = 2,
		MaxTextSize = 64, -- (and MinTextSize 12: on the smallest card the ⭐ overhangs its column)
	})
	return pedestal
end

local function buildCatch(root: any)
	-- The dim around the card: four Ink bands (Top, Bottom, Left, Right) that FishingController
	-- places AROUND the card's rest box each time it opens (they reach a little under its rounded
	-- edges and far past the screen edges: notches and the inset band). The card covers the middle
	-- anyway, so no pixel is dimmed twice — a quarter less GPU fill on a phone than one
	-- full-screen frame. The CatchDim root draws nothing; never Active: never blocks input.
	local dim = U.new("Frame", {
		Name = "CatchDim",
		Visible = false,
		Active = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 6,
	}, root)
	for _, band in { "Top", "Bottom", "Left", "Right" } do
		local frame = U.new("Frame", {
			Name = band,
			Active = false,
			BackgroundColor3 = INK,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 6,
		}, dim)
		if band == "Left" or band == "Right" then
			-- v3 (UIM-04): a card docked beside the fisher dims one side band that melts away
			-- towards him (FishingController placeDim sets its Transparency and enables it).
			U.new("UIGradient", { Name = "Fade", Enabled = false }, frame)
		end
	end

	-- The layer of the card's sunburst: the whole screen here; FishingController
	-- (CatchFx.raysFrame) makes it end at the fisher's edge when the card docks beside him (it
	-- then clips its rays: big, but never over him and his trophy) and puts the rays' centre and
	-- size in pixels (behind the card, or at the fish over his head for the rarity title).
	local cardSize = UDim2.fromScale(0.58, 0.58)
	local cardPosition = UDim2.new(0.5, 0, 1, -HOTBAR - 16) -- 16 px above the screen bottom
	U.new("Frame", {
		Name = "CatchRays",
		Visible = false,
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 7,
	}, root)

	-- The card: a modal (tap anywhere on it: skip the reveal / close). A white sim display plate
	-- (Cream: the white → cool white gradient, the chunky outline in its dark ink-blue shade, the
	-- light rim). A mutation recolours that outline (FishingController, FUI-07). ZIndex inside the
	-- card: Lip 1, Face 2 (with its Window), FishGlow 3, Banner and Pedestal 4, Viewport 5,
	-- NameLabel / InfoLabel / TapHint 6, NewStamp / MutationLabel 8.
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
	corner(card, CARD_RADIUS)
	local face = Theme.sim(card, "Cream", { radius = CARD_RADIUS, z = 1 })

	-- The display window behind the fish (in the v4 face's coordinates: the card's y / CARD_FACE).
	local window = U.new("Frame", {
		Name = "Window",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.065, 0.232 / CARD_FACE),
		Size = UDim2.fromScale(0.87, 0.366 / CARD_FACE),
		ZIndex = 2,
	}, face)
	corner(window, 0.1)
	stroke(window, 3, 0, WINDOW_EDGE)
	Theme.gradient(window, WINDOW_TOP, WINDOW_BOTTOM)

	-- The rarity ribbon overhanging both sides: a sim plate (label radius) with the chunky
	-- outline (FishingController: UiFx.setCandy with UIConfig.Rarity[r]; Mythic: an animated
	-- rainbow + sparkles; Epic+: the giant TitleSlam flies into it), the rarity word in outlined
	-- white CAPS between two outlined ⭐ tilted outwards.
	local banner = U.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.03),
		Size = UDim2.fromScale(1.08, 0.165),
		ZIndex = 4,
	}, card)
	local common = UI.Rarity.Common
	local commonLook = { Top = common.Top, Bottom = common.Bottom, Lip = common.Lip }
	Theme.sim(banner, commonLook, { radius = UI.Sim.PlateRadius })
	label(banner, "RarityLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.72, 0.72),
		Text = "ОБЫЧНАЯ",
		Outline = Theme.DISPLAY_OUTLINE,
		ZIndex = Theme.SZ.Content,
		MaxTextSize = 40,
		MinTextSize = 14,
	})
	for _, side in { { "StarLeft", 0.07, -10 }, { "StarRight", 0.93, 10 } } do
		Theme.icon(banner, side[1], "⭐", {
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(side[2], 0.5),
			Size = UDim2.fromScale(0.86, 0.86),
			Rotation = side[3],
			ZIndex = Theme.SZ.Content,
		})
	end

	-- The fish on a soft rarity glow: a disc in a transparent root that FishingController
	-- breathes and tints with the rarity colour (and spins small rarity rays in, behind the fish).
	local glow = U.new("Frame", {
		Name = "FishGlow",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.39),
		Size = UDim2.fromScale(0.38, 0.38),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 3,
	}, card)
	local disc = U.new("Frame", {
		Name = "Disc",
		BackgroundColor3 = common.Top,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.82, 0.82),
		ZIndex = 1,
	}, glow)
	corner(disc, 0.5)
	buildPodium(card, commonLook)
	U.new("ViewportFrame", {
		Name = "Viewport",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.385),
		Size = UDim2.fromScale(0.86, 0.34),
		Ambient = rgb(200, 200, 210),
		LightColor = rgb(255, 250, 240),
		LightDirection = Vector3.new(-1, -1.4, -0.8),
		ZIndex = 5,
	}, card)

	-- «НОВИНКА!»: a red sticker slapped on the top-left corner of the window (first catch of a
	-- species this session; CatchFx.slap). Neutral for any fish name («НОВАЯ! Акулёнок» did not
	-- agree). Never smaller than 96 x 28 px: its text stays ≥ 14 px even on the smallest phone's
	-- Common card.
	local newStamp = Theme.plate(card, "NewStamp", "Berry", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.2, 0.26),
		Size = UDim2.fromScale(0.34, 0.088),
		Rotation = -8,
		ZIndex = 8,
		Text = "НОВИНКА!",
		MaxTextSize = 24,
		Radius = UI.Sim.PlateRadius,
		SimOpts = { stroke = Theme.DISPLAY_OUTLINE },
		LabelProps = {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.88, 0.7),
			Outline = 3,
		},
	})
	U.new("UISizeConstraint", { MinSize = Vector2.new(96, 28) }, newStamp)

	-- Mutation stamp on the top-right corner of the window (FUI-07; on phones a plaque on the
	-- podium): a sim plate in the mutation's colours with its outlined icon overhanging the left
	-- end; MutationLabel.Text is the value («Золотая мутация ×2»), MutationLabel.Caption shows
	-- the stamp («ЗОЛОТАЯ ×2!»).
	local mutation = U.new("TextLabel", {
		Name = "MutationLabel",
		Visible = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.77, 0.26),
		Size = UDim2.fromScale(0.42, 0.09),
		Rotation = 8,
		Text = "",
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		FontFace = Theme.FONT,
		ZIndex = 8,
	}, card)
	local gold = UI.Mutations.Gold
	Theme.sim(mutation, { Top = gold.Top, Bottom = gold.Bottom, Lip = gold.Lip }, {
		radius = UI.Sim.PlateRadius,
		stroke = Theme.DISPLAY_OUTLINE,
		rim = 1.5,
	})
	Theme.icon(mutation, "Icon", gold.Icon, {
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.35, 0.5),
		Position = UDim2.fromScale(0, 0.46),
		Size = UDim2.fromScale(1.45, 1.45),
		Rotation = -10,
		ZIndex = Theme.SZ.Content,
	})
	label(mutation, "Caption", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.95, 0.5),
		Size = UDim2.fromScale(0.8, 0.74),
		Text = "",
		Outline = 3,
		ZIndex = Theme.SZ.Content,
		MaxTextSize = 30,
		MinTextSize = 12, -- (one line: on the landscape card the stamp is small)
	})

	-- The name: the hero of the card (display text, box-driven like the banner), white → the
	-- rarity's colours with an Ink outline. MinTextSize 12, not more: TextScaled wraps a word
	-- that does not fit at the minimum size mid-word («Рыба-драк / он» on the smallest card).
	label(card, "NameLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.608),
		Size = UDim2.fromScale(0.92, 0.108),
		Text = "Карасик",
		TextWrapped = true,
		Outline = 3.5,
		TextGradient = NAME_COMMON,
		ZIndex = 6,
		MaxTextSize = 44,
		MinTextSize = 12,
	})

	-- Weight and price chips; InfoLabel.Text is the summary «1,2 кг · цена 35 💰» (the value),
	-- Price.Label counts up from 0: the hero number in italic white digits with a display outline,
	-- a tall label (0.8 of the chip) that FishingController turns into display text (box-driven,
	-- up to 1.4 × Title, never under Button − 2). Weight is a light grey round chip with Ink text
	-- in CAPS (never the rarity's colour again), the price a yellow Gold round chip (it is what a
	-- thief steals) with its outlined 💰 overhanging the left end and the «×N» of a mutation
	-- slammed on its corner.
	local info = U.new("TextLabel", {
		Name = "InfoLabel",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.735),
		Size = UDim2.fromScale(0.86, 0.115),
		Text = "",
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		FontFace = Theme.FONT,
		ZIndex = 6,
	}, card)
	Theme.plate(info, "Weight", "Slate", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0.05, 0),
		Size = UDim2.fromScale(0.41, 1),
		Icon = "⚖️",
		IconScale = 1.3,
		Text = "1 КГ",
		Tier = "Body",
		Radius = 0.5,
		SimOpts = { stroke = Theme.MINOR },
		LabelProps = { Outline = false, TextColor3 = INK, TextStrokeTransparency = 1 },
	})
	local price = Theme.plate(info, "Price", "Gold", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.45, 1),
		Icon = "💰",
		IconScale = 1.45,
		Text = "0",
		Tier = "Title",
		Italic = true,
		Radius = 0.5,
		SimOpts = { stroke = Theme.DISPLAY_OUTLINE },
		LabelProps = { Size = UDim2.fromScale(0.78, 0.8), Outline = Theme.DISPLAY_OUTLINE },
	})
	label(price, "Multiplier", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.97, 0.02),
		Size = UDim2.fromScale(0.42, 0.95),
		Rotation = 12,
		Text = "×2",
		Italic = true,
		Outline = 4,
		TextGradient = { WHITE, P.Gold.Top },
		ZIndex = Theme.SZ.Top,
		MaxTextSize = 34,
		MinTextSize = 14,
	})

	-- The close hint, named like the button's «ЗАБРАТЬ!»: muted italic on the plate (the
	-- reference's hint text), Body tier (≥ 14 px on the smallest phone); hidden until the last
	-- beat of the reveal, then it breathes gently.
	label(card, "TapHint", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.955),
		Size = UDim2.fromScale(0.8, 0.075),
		Text = "Тапни — забрать!",
		TextColor3 = UI.Fishing.Muted,
		TextStrokeTransparency = 1,
		Italic = true,
		ZIndex = 6,
		Tier = "Body",
	})

	-- The giant rarity title (Epic and rarer, FUI-03): the reference's panel-less title —
	-- outlined letters (Theme.title: a thick Ink outline and the drop-shadow twin LabelShadow),
	-- white → the rarity's colours. It slams in over the fisher and his trophy when the fish
	-- lands, then flies into the card's banner. Label: the whole word (Epic); Letters:
	-- FishingController puts one label per letter there (Legendary / Mythic wave, no shadow).
	local title = U.new("Frame", {
		Name = "TitleSlam",
		Visible = false,
		Active = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.4),
		Size = UDim2.fromScale(0.9, 0.17),
		ZIndex = 12,
	}, root)
	Theme.title(title, "Label", {
		Size = UDim2.fromScale(1, 1),
		Text = "ЭПИЧЕСКАЯ!",
		Outline = Theme.TITLE_OUTLINE,
		TextGradient = { WHITE, WHITE, UI.Rarity.Epic.Top, UI.Rarity.Epic.Bottom },
		ZIndex = 2,
		MaxTextSize = 120,
		MinTextSize = 14,
	})
	U.new("Frame", {
		Name = "Letters",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 2,
	}, title)
end

--[[
	Fishing UI (stage 2), all under HUD.Fishing (FishingController drives it; everything starts
	hidden). ZIndex inside Fishing: Hint / BiteAlert / Minigame 4, CatchDim 6, CatchRays 7,
	ActionArea 9, CatchCard 10, TitleSlam 12.
	  ActionArea              bottom-right container, sized by screen height
	    ActionButton          round sim disc (Theme.roundPlate: Lip, Face with Gloss / Rim): Icon
	                          (an outlined emoji or the «!» glyph: one Outline, TextFill),
	                          CaptionRibbon (dark glass pill) + Caption («ЗАБРОСИТЬ» / «ЖДЁМ…» /
	                          «КУДА ИДТИ?» / «ПОДСЕЧЬ!» / «ЛОВИ!» / «ВЗЯТЬ» / «ЗАБРАТЬ!»), Ring
	                          (white halo), KeyChip.Key («F» / «R2», a white chip), TapCue (👆),
	                          Bobber (the waiting look's icon), Badge (the newcomer's red «!»)
	    StopButton            «СМОТАТЬ» red sim button above it (Icon 🎣, Caption)
	  BiteAlert               orange sim plate: «КЛЮЁТ!» (Label), «!» IconLeft/IconRight,
	                          TimerTrack (black groove) + Timer, TapPad (touch: a tap on the plate hooks)
	  Minigame                dark Night sim panel (AuraStroke.AuraFill for Epic+):
	                          Title (rarity gradient), Track (black groove: Zone — a green bar:
	                          Glow, Flash; Rider 🐟 on it; Needle: Head ▼), Clock ⏱ + TimeBar
	                          (Fill), Pips (Pip1..Pip5: round chips with a Cap and a Star), Help, TapPad
	  Hint                    dark glass pill: IconSocket.Icon + Label (italic; Hint.Text = the value)
	  CatchDim, CatchRays     the reveal's dim and the layer of its sunburst (FxRays), behind the
	                          card; docked beside the fisher the layer clips the rays at his edge
	  CatchCard               TextButton (tap: skip the reveal / close) — a white sim display plate
	                          with the chunky outline: Face.Window (sky panel), Banner (the rarity
	                          ribbon: RarityLabel, StarLeft / StarRight), FishGlow, Pedestal (the
	                          trophy stand: Cap — the light oval top with the fish's Shadow, the
	                          rarity column with an outlined Star, Base slab), Viewport (the fish
	                          model), NewStamp «НОВИНКА!» (red sticker),
	                          NameLabel, MutationLabel (corner stamp: Icon, Caption), InfoLabel
	                          (Weight — grey round chip, Price — gold round chip with italic digits;
	                          Price.Multiplier «×N»), TapHint (italic).
	                          Square here; phones: the landscape layout of FishingController
	                          (same children); docked beside the fisher wherever it fits
	  TitleSlam               the giant panel-less rarity title of Epic+ (Label + its LabelShadow
	                          twin, Letters), flies into the banner
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
