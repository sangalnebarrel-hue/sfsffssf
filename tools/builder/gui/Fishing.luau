--[[
	Fishing — HUD.Fishing (stage 2) in the UI v3 «Кирпичики» style (toy bricks with studs): the
	action button, the bite alert, the minigame, the hint and the catch card (the big reveal).
	Controller and all the motion: FishingController (UiFx). Layout rules: tools/builder/Gui.luau;
	look and API: tools/builder/gui/STYLE.md (§3 "Fishing UI", §6).

	Names are a contract (FishingController, tests and the preview scenarios find widgets by
	name); everything not listed here is decoration and may change:
	  ActionArea.ActionButton.{Icon, Caption, Ring}   ActionArea.StopButton.Caption
	  BiteAlert.{Label, Timer}   Minigame.{Title, Pips.Pip1..Pip5, Track.{Zone, Needle},
	  TimeBar.Fill, Help}   Hint   CatchCard.{Banner.RarityLabel, Viewport, NameLabel,
	  MutationLabel, InfoLabel, TapHint}
	UI v2, the playing widgets (FishingController): ActionArea.ActionButton.{KeyChip.Key, TapCue,
	Bobber} (the desktop key chip, the first-timer 👆, the waiting look's icon),
	BiteAlert.{IconLeft, IconRight, TapPad} (the «!» glyphs, the touch tap pad over the plate),
	Minigame.{Clock, TapPad, Track.Rider, Track.Needle.Head} (⏱, the touch tap pad over the
	panel, the fish riding the zone — its glyph by rarity, the ▼ needle head),
	Hint.IconSocket.Icon (the hint's emoji).
	Value-holding labels on bricks (Hint, CatchCard.MutationLabel, CatchCard.InfoLabel) keep
	their Text as the contract value but draw it through children (children render above their
	parent, so the brick's face would hide the label's own text): Hint.Label, MutationLabel.Caption,
	InfoLabel.Weight / InfoLabel.Price (bricks; the price counts up). The catch also uses (by name)
	CatchCard.{FishGlow, NewStamp, Lip (its outline), InfoLabel.Price.Multiplier, Pedestal} and
	TitleSlam.{Label, Letters} (the giant rarity title).
	Minigame pips keep a visible BackgroundColor3 (filled = green 64,200,96, as the e2e bot reads
	it); the zone and the needle keep Position.X = centre and Size.X = width in track fractions.

	UI v4 (the widgets as toy bricks, STYLE.md §3): the action button is a round plate with a
	raised centre stud (Theme.roundPlate) and a black caption tile, «СМОТАТЬ» a red 1x3 brick,
	the key chip a small white tile; the bite alert an orange 1x6 brick; the hint a smooth dark
	stone tile; the minigame a dark stone baseplate with a row of studs along its top edge, a
	black groove, the zone a green 1x3 brick the fish rides on, pips as round studs seen from
	above; the catch card a white display plate (studs in the gaps between its tiles, the fish
	in a display window on a studded pedestal in the rarity's colour, the rarity banner a long
	studded brick, the price a yellow studded brick, the weight a grey tile, «НОВИНКА!» a red
	tile). Children with the attribute NoSink stay put when UiFx.press sinks the brick's face.
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
local BRICK = Theme.BRICK
local BRICK_FACE = 1 - BRICK.Lip -- a brick's face covers its top; content is centred on it
local TILE_FACE = 1 - BRICK.TileLip
local corner = Theme.corner
local stroke = Theme.stroke
local label = Theme.label

-- The action button's round plate: side band depth, the raised stud (diameter share of the face,
-- its centre as a share of the face's height) and where that centre is on the button.
local PLATE_LIP = 0.1
local PLATE_STUD = 0.66
local PLATE_STUD_Y = 0.46
local STUD_CENTER = (1 - PLATE_LIP) * PLATE_STUD_Y

-- Pip colours: the e2e bot recognises a filled pip by this exact green (FishingController too);
-- an empty pip is a light grey stud with a faint white ★.
local PIP_DONE = rgb(64, 200, 96)
local PIP_EMPTY = P.Slate.Bottom

-- The bottom line of the centre column (Hint, BiteAlert, Minigame): ≥ 16 px above the Roblox
-- hotbar, outlines included (its slots end 65 px above the screen bottom; HOTBAR = 74). The hint and the
-- bite/minigame never show together (FishingController hides the hint for the bite and shows
-- the miss hint as the miss ghost leaves), so they share the line and the stack stays low.
-- FishingController moves the column sideways on narrow screens (clear of the thumbstick and
-- the action button) through Position.X.Offset; X.Scale stays 0.5.
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
-- Action area: the round plate and the «СМОТАТЬ» brick
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

	-- The star of the screen: a round toy plate seen from above (Theme.roundPlate: an Ink-ringed
	-- disc on its dark side band, a raised centre stud carrying the icon). FishingController
	-- recolours it per state with UiFx.setCandy — the stud follows (Sky «ЗАБРОСИТЬ», Slate «ЖДЁМ…»
	-- / «КУДА ИДТИ?», Water «ЖДЁМ…» (line in the water), Sun «ПОДСЕЧЬ!», Leaf «ЛОВИ!» /
	-- «ЗАБРАТЬ!», Gold «ВЗЯТЬ»). The caption sits on a black tile across the bottom of the plate
	-- (readable on any colour), at the Button text tier: the tile is wide enough for «ЗАБРОСИТЬ»
	-- at 16+ px on the smallest phone. When pressed, the plate's face sinks into its side band
	-- (UiFx.press) and the icon rides it; the caption tile, the key chip and the 👆 stay put.
	local action = U.new("TextButton", {
		Name = "ActionButton",
		Text = "",
		AutoButtonColor = false,
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 0.9),
		Size = UDim2.fromScale(0.43, 0.56),
		Visible = false,
	}, area)
	U.new("UIAspectRatioConstraint", { AspectRatio = 1, DominantAxis = Enum.DominantAxis.Height }, action)
	corner(action, 0.5) -- the Ring and the glow rings follow the round shape
	Theme.roundPlate(action, "Sky", { lip = PLATE_LIP, stud = PLATE_STUD, studY = PLATE_STUD_Y })
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
	-- The icon on the raised stud: an emoji per state; on the bite it becomes the «!» glyph
	-- (white → gold, Ink outline — FishingController enables Outline and TextFill for it, off for
	-- the emoji).
	local icon = Theme.icon(action, "Icon", "🎣", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, STUD_CENTER),
		Size = UDim2.fromScale(0.58, 0.58),
		ZIndex = BZ.Content,
	})
	U.new("UIStroke", {
		Name = "Outline",
		Enabled = false,
		Color = INK,
		Thickness = 4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Attributes = { BaseThickness = 4 },
	}, icon)
	U.new("UIGradient", {
		Name = "TextFill",
		Enabled = false,
		Color = Theme.sequence({ WHITE, P.Gold.Top }),
		Rotation = 90,
	}, icon)
	-- Waiting for a bite («ЖДЁМ…» on Water): a drawn bobber on the stud instead of the emoji — a
	-- red/white ball with an Ink outline and a little antenna (FishingController bobs it and sends
	-- ripples from it). Its Position belongs to that bob (a looping tween): NoSink.
	local bobber = U.new("Frame", {
		Name = "Bobber",
		Visible = false,
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, STUD_CENTER + 0.03),
		Size = UDim2.fromScale(0.3, 0.3),
		ZIndex = BZ.Content,
		Attributes = { NoSink = true },
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
	-- The caption tile: a black smooth tile over the bottom of the plate (the toy's name plate),
	-- the caption on it in CAPS at the Button tier.
	local ribbon = U.new("Frame", {
		Name = "CaptionRibbon",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.86),
		Size = UDim2.fromScale(1.3, 0.3),
		ZIndex = BZ.Content + 1,
		Attributes = { NoSink = true },
	}, action)
	Theme.tile(ribbon, "Coal", { radius = 0.3, spec = false, shine = false })
	label(action, "Caption", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.86 - 0.15 * BRICK.TileLip),
		Size = UDim2.fromScale(1.22, 0.23),
		Text = "ЗАБРОСИТЬ",
		ZIndex = BZ.Content + 2,
		Tier = "Button",
		Attributes = { NoSink = true },
	})
	-- Desktop / console: the action key as a little white key tile on the plate's shoulder (an
	-- Ink «F» / «R2»), instead of a «[F]» suffix that would shrink the caption.
	local chip = U.new("Frame", {
		Name = "KeyChip",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.9, 0.12),
		Size = UDim2.fromScale(0.3, 0.3),
		ZIndex = BZ.Content + 3,
		Attributes = { NoSink = true },
	}, action)
	Theme.tile(chip, "Cream", { radius = 0.28, spec = false, shine = false })
	label(chip, "Key", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, TILE_FACE * 0.5),
		Size = UDim2.fromScale(0.84, TILE_FACE * 0.76),
		Text = "F",
		TextColor3 = INK,
		TextStrokeTransparency = 1,
		ZIndex = BZ.Content,
		Tier = "Small",
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
		Attributes = { NoSink = true },
	})

	-- «СМОТАТЬ»: a red 1x3 brick (3 studs) above the action button with the 🧵 inside its left
	-- end; 0.3 of the area tall and never under 44 px (a full-size tap target on every phone),
	-- its bottom 0.18 of the area down: ≥ 22 px above the action plate on phones, so a thumb
	-- mashing the big button does not slip onto it (FishingController also hides it while a
	-- fish is on the hook: the bite and the minigame). Narrow enough to stay clear of the Home
	-- button on the right.
	local stop = Theme.candyButton(area, "StopButton", "Berry", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 0.18),
		Size = UDim2.fromScale(0.56, 0.3),
		Visible = false,
		Brick = { studs = 3, studScale = 0.6, studArea = { 0.3, 0.98 } },
	})
	U.new("UISizeConstraint", { MinSize = Vector2.new(0, 44) }, stop)
	Theme.icon(stop, "Icon", "🧵", {
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.04, BRICK_FACE * 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		ZIndex = BZ.Content,
	})
	label(stop, "Caption", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.95, BRICK_FACE * 0.5),
		Size = UDim2.fromScale(0.68, BRICK_FACE * 0.64),
		Text = "СМОТАТЬ",
		ZIndex = BZ.Content,
		Tier = "Button",
	})
end

--------------------------------------------------------------------------------
-- Bite alert
--------------------------------------------------------------------------------

local function buildBiteAlert(root: any)
	-- Where the minigame appears next (they are never shown together). An orange 1x6 brick (6
	-- studs on its top edge): «КЛЮЁТ!» with a «!» glyph on both ends and a countdown in a black
	-- groove; FishingController slams it in and puts calm rays behind it (UiFx.rays at ZIndex 0 =
	-- behind the studs, the side band and the face). 0.8H x 0.21H: ≈265 x 70 px on a phone,
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
		studs = 6,
		studScale = 0.6,
		studArea = { 0.1, 0.9 },
		radius = 0.22,
		spec = { x = 0.04, y = 0.14, w = 0.07, h = 0.08 },
	})
	label(alert, "Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, BRICK_FACE * 0.4),
		Size = UDim2.fromScale(0.6, BRICK_FACE * 0.62),
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
			Position = UDim2.fromScale(side[2], BRICK_FACE * 0.47),
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
		Position = UDim2.fromScale(0.5, BRICK_FACE * 0.82),
		Size = UDim2.fromScale(0.6, BRICK_FACE * 0.17),
		ZIndex = BZ.Content,
	}, 0.5, 3)
	local timer = U.new("Frame", {
		Name = "Timer",
		BackgroundColor3 = P.Leaf.Top,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0.2, BRICK_FACE * 0.82),
		Size = UDim2.fromScale(0.6, BRICK_FACE * 0.17),
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

-- The baseplate's corners and side band (a big plate: a thin band).
local PLATE_RADIUS = 0.1
local PLATE_BAND = 0.06

local function buildMinigame(root: any)
	-- A dark stone baseplate (opaque) with a row of studs seen from above along its top edge;
	-- width from the screen WIDTH (like the toasts), capped on big screens. Rows (fractions of
	-- the panel height): the studs (0.03..0.085), the rarity title (0.095..0.255) — a band where
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
	U.new("UISizeConstraint", { MaxSize = Vector2.new(520, 210), MinSize = Vector2.new(280, 120) }, mini)
	local face = Theme.brick(mini, "Night", { radius = PLATE_RADIUS, lip = PLATE_BAND, spec = false, shine = false })
	-- The studs of the baseplate (Theme.studRow: 2 Frames + 2 UICorners + 1 gradient each, no
	-- outline) along the top edge, like the ceiling of a Brainrot base.
	Theme.studRow(face, {
		Name = "StudRow",
		Area = { 0.03, 0.028, 0.97, 0.088 },
		Count = 18,
		Size = 1,
		Token = "Night",
		ZIndex = 1,
	})
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
		Position = UDim2.fromScale(0.5, 0.095),
		Size = UDim2.fromScale(0.91, 0.16),
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
	-- The zone: a green 1x3 brick (transparent root = the logical box; its 3 studs poke out of the
	-- groove and the rider stands on them) on a soft light-green glow that breathes in HEIGHT
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
		studs = 3,
		studScale = 0.6,
		radius = 0.28,
		stroke = 3,
		spec = { x = 0.08, y = 0.2, w = 0.16, h = 0.12 },
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
	-- The fish on the hook: a 🐟 standing on the zone's studs (FishingController keeps it over
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
	-- The needle: a thin white brick poking out of the groove (UiFx.trail adds ghosts) with a ▼
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
	-- Pips: hits needed — round 1x1 studs seen from above (a light grey stud with a faint white
	-- ★: its "Fill" lights the colour from the top left, a translucent white "Cap" is the stud's
	-- top) / done (the same stud in green with a stamped ⭐). The pip's own BackgroundColor3 is
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
	-- hotbar, between the thumbstick and the action button (FishingController moves it sideways
	-- on narrow screens). A smooth tile by kind — dark stone Night (info), Sun (warning), Berry
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
	Theme.tile(hint, "Night", { radius = 0.25, spec = { x = 0.1, y = 0.16, w = 0.05, h = 0.1 } })
	Theme.socket(hint, "IconSocket", "💡", {
		AnchorPoint = Vector2.new(0.3, 0.5),
		Position = UDim2.fromScale(0, TILE_FACE * 0.5),
		Size = UDim2.fromScale(1.12, 1.12),
		ZIndex = BZ.Content,
	})
	label(hint, "Label", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.955, TILE_FACE * 0.5),
		Size = UDim2.fromScale(0.8, TILE_FACE * 0.9),
		Text = "",
		TextWrapped = true,
		ZIndex = BZ.Content,
		Tier = "Body",
	})
end

--------------------------------------------------------------------------------
-- Catch card: the big reveal (UI v2: FUI-02 / 03 / 07 / 12; UI v4: a toy display plate)
--------------------------------------------------------------------------------

--[[
	The card as built here is the SQUARE layout (desktop / tablet, 380 x 384 at most). On short
	screens (HUD under 500 px tall: phones) FishingController re-lays the same instances out as
	a landscape trophy card (CARD_WIDE in the controller): the fish on the left, name / chips /
	tap hint in a right column, the same child names (also the plate's decoration under its
	Face: Window, StudsTop, StudsLeft, StudsRight). The controller also places the card (and
	its CatchRays) itself every time it opens: centred in its slot, born at the held fish.
]]
local CARD_RADIUS = 0.09
local CARD_BAND = 0.035 -- the plate's side band (drawn as a LipBand along the bottom: fill)
local CARD_FACE = 1 - CARD_BAND

-- Name text on the white plate: a dark rarity gradient with a white outline (FUI-12).
local NAME_COMMON = { P.Night.Top, INK }

-- The display window behind the fish: a recessed pale sky panel (one quad + its outline).
local WINDOW_TOP = rgb(250, 253, 255)
local WINDOW_BOTTOM = rgb(214, 230, 246)

-- Studs seen from above on the plate's face (in the gaps between its tiles): a row, or a
-- column (sized by the holder's WIDTH, so the same column works in both layouts).
local function studColumn(face: any, name: string, area: { number }, count: number)
	local holder = U.new("Frame", {
		Name = name,
		BackgroundTransparency = 1,
		Active = false,
		Position = UDim2.fromScale(area[1], area[2]),
		Size = UDim2.fromScale(area[3] - area[1], area[4] - area[2]),
		ZIndex = 1,
	}, face)
	for i = 1, count do
		Theme.topStud(holder, `Stud{i}`, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, (i - 0.5) / count),
			Size = UDim2.fromScale(0.8, 0.8),
			SizeConstraint = Enum.SizeConstraint.RelativeXX,
			Token = "Cream",
		})
	end
	return holder
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
		U.new("Frame", {
			Name = band,
			Active = false,
			BackgroundColor3 = INK,
			BackgroundTransparency = 0.4,
			BorderSizePixel = 0,
			ZIndex = 6,
		}, dim)
	end

	-- Same box as the card: UiFx.rays sizes its sunburst by this holder's height.
	local cardSize = UDim2.fromScale(0.58, 0.58)
	local cardPosition = UDim2.new(0.5, 0, 1, -HOTBAR - 16) -- 16 px more: clear of the hotbar
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

	-- The card: a modal above the hotbar (tap anywhere on it: skip the reveal / close). A white
	-- toy display plate (Theme.brick, no studs on its edge, no glint). Its Lip keeps the outline
	-- but draws no background: the side band is a LipBand along the bottom (the face hides all
	-- but its lowest 3.5 % anyway) — a quarter of the phone screen less to blend. A mutation
	-- recolours that outline (FishingController, FUI-07). ZIndex inside the card: Lip/LipBand 1,
	-- Face 2 (with its Window, stud rows and columns), FishGlow 3, Banner and Pedestal 4,
	-- Viewport 5, NameLabel / InfoLabel / TapHint 6, NewStamp / MutationLabel 8.
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
	local face = Theme.brick(card, "Cream", { radius = CARD_RADIUS, lip = CARD_BAND, spec = false, z = 1 })
	local lip = card:FindFirstChild("Lip")
	lip.BackgroundTransparency = 1
	local lipBand = U.new("Frame", {
		Name = "LipBand",
		BackgroundColor3 = P.Cream.Lip,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.2),
		ZIndex = lip.ZIndex,
	}, card)
	corner(lipBand, 0.45) -- ≈ the card's corner radius (its shorter side is its height)

	-- The plate's decoration on its face (face coordinates: the card's y / CARD_FACE): the
	-- display window behind the fish, a row of studs under the banner, a column of studs on
	-- each side of the window (on phones: one column between the fish and the right column).
	local window = U.new("Frame", {
		Name = "Window",
		BackgroundColor3 = WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.065, 0.232 / CARD_FACE),
		Size = UDim2.fromScale(0.87, 0.366 / CARD_FACE),
		ZIndex = 2,
	}, face)
	corner(window, 0.12)
	stroke(window, 3)
	Theme.gradient(window, WINDOW_TOP, WINDOW_BOTTOM)
	Theme.studRow(face, {
		Name = "StudsTop",
		Area = { 0.05, 0.2 / CARD_FACE, 0.95, 0.227 / CARD_FACE },
		Count = 16,
		Size = 1,
		Token = "Cream",
		ZIndex = 1,
	})
	studColumn(face, "StudsLeft", { 0.014, 0.25 / CARD_FACE, 0.05, 0.585 / CARD_FACE }, 5)
	studColumn(face, "StudsRight", { 0.95, 0.25 / CARD_FACE, 0.986, 0.585 / CARD_FACE }, 5)

	-- Rarity banner overhanging both sides: a long brick with 8 studs (FishingController:
	-- UiFx.setCandy with UIConfig.Rarity[r] — the studs follow; Mythic: an animated rainbow,
	-- rainbow studs + sparkles; Epic+: the giant TitleSlam flies into it).
	local banner = U.new("Frame", {
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.03),
		Size = UDim2.fromScale(1.08, 0.165),
		ZIndex = 4,
	}, card)
	local common = UI.Rarity.Common
	local commonLook = { Top = common.Top, Bottom = common.Bottom, Lip = common.Lip }
	Theme.brick(banner, commonLook, {
		studs = 8,
		studScale = 0.5,
		studArea = { 0.13, 0.87 },
		radius = 0.22,
		spec = { x = 0.12, y = 0.16, w = 0.07, h = 0.09 },
	})
	label(banner, "RarityLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, BRICK_FACE * 0.5),
		Size = UDim2.fromScale(0.72, BRICK_FACE * 0.72),
		Text = "ОБЫЧНАЯ",
		Outline = 4.5,
		ZIndex = BZ.Content,
		MaxTextSize = 40,
		MinTextSize = 14,
	})
	for _, side in { { "StarLeft", 0.07 }, { "StarRight", 0.93 } } do
		Theme.icon(banner, side[1], "⭐", {
			SizeConstraint = Enum.SizeConstraint.RelativeYY,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(side[2], BRICK_FACE * 0.5),
			Size = UDim2.fromScale(0.82, 0.82),
			ZIndex = BZ.Content,
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
	for i, disc in { { "Disc", 0.82, 0.5, common.Top } } do
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
	-- The pedestal the fish stands on (a Steal-a-Brainrot display stand): a studded brick in the
	-- rarity's colour (FishingController: UiFx.setCandy; Mythic: rainbow studs), in front of the
	-- glow, behind the fish (whose belly overlaps its studs).
	local pedestal = U.new("Frame", {
		Name = "Pedestal",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.592),
		Size = UDim2.fromScale(0.34, 0.064),
		ZIndex = 4,
	}, card)
	Theme.brick(pedestal, commonLook, {
		studs = 4,
		studScale = 0.75,
		studArea = { 0.14, 0.86 },
		radius = 0.24,
		lip = 0.3,
		stroke = 3,
		spec = { x = 0.05, y = 0.2, w = 0.06, h = 0.16 },
		shine = false,
	})
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

	-- «НОВИНКА!»: a red tile stamped on the top-left corner of the window (first catch of a
	-- species this session). Neutral for any fish name («НОВАЯ! Акулёнок» did not agree). Never
	-- smaller than 96 x 28 px: its text stays ≥ 14 px even on the smallest phone's Common card.
	local newStamp = Theme.pill(card, "NewStamp", "Berry", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.2, 0.26),
		Size = UDim2.fromScale(0.34, 0.088),
		Rotation = -8,
		ZIndex = 8,
		Text = "НОВИНКА!",
		MaxTextSize = 24,
		Brick = { tile = true, radius = 0.25, spec = { x = 0.05, y = 0.18, w = 0.06, h = 0.14 } },
		LabelProps = {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, TILE_FACE * 0.5),
			Size = UDim2.fromScale(0.88, TILE_FACE * 0.7),
			Outline = 3,
		},
	})
	U.new("UISizeConstraint", { MinSize = Vector2.new(96, 28) }, newStamp)

	-- Mutation stamp on the top-right corner of the window (FUI-07; on phones a plaque on the
	-- pedestal): a tile in the mutation's colours with its icon; MutationLabel.Text is the value
	-- («Золотая мутация ×2»), MutationLabel.Caption shows the stamp («ЗОЛОТАЯ ×2!»).
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
	Theme.tile(mutation, { Top = gold.Top, Bottom = gold.Bottom, Lip = gold.Lip }, {
		radius = 0.25,
		stroke = 3.5,
		spec = { x = 0.2, y = 0.18, w = 0.06, h = 0.14 },
	})
	Theme.icon(mutation, "Icon", gold.Icon, {
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.35, 0.5),
		Position = UDim2.fromScale(0, TILE_FACE * 0.46),
		Size = UDim2.fromScale(1.45, 1.45),
		Rotation = -10,
		ZIndex = BZ.Content,
	})
	label(mutation, "Caption", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.95, TILE_FACE * 0.5),
		Size = UDim2.fromScale(0.8, TILE_FACE * 0.74),
		Text = "",
		Outline = 3,
		ZIndex = BZ.Content,
		MaxTextSize = 30,
		MinTextSize = 14,
	})

	-- The name: the hero of the card (display text, box-driven like the banner), a dark rarity
	-- gradient with a white outline (readable on the white plate); two lines on the landscape card.
	label(card, "NameLabel", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.608),
		Size = UDim2.fromScale(0.92, 0.108),
		Text = "Карасик",
		TextWrapped = true,
		Outline = 3,
		OutlineColor = WHITE,
		TextGradient = NAME_COMMON,
		ZIndex = 6,
		MaxTextSize = 44,
		MinTextSize = 18,
	})

	-- Weight and price chips; InfoLabel.Text is the summary «1,2 кг · цена 35 💰» (the value),
	-- Price.Label counts up from 0: the hero number, a tall label (0.8 of the brick's face) that
	-- FishingController turns into display text (box-driven, up to 1.4 × Title, never under
	-- Button − 2). Weight is a light grey tile with Ink text in CAPS (never the rarity's colour
	-- again), the price a yellow studded brick (it is what a thief steals) with the «×N» of a
	-- mutation slammed on its corner.
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
	Theme.pill(info, "Weight", "Slate", {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0.05, 0),
		Size = UDim2.fromScale(0.41, 1),
		Icon = "⚖️",
		IconScale = 1.3,
		Text = "1 КГ",
		Tier = "Body",
		Brick = { tile = true, spec = false },
		LabelProps = { Outline = false, TextColor3 = INK, TextStrokeTransparency = 1 },
	})
	local price = Theme.pill(info, "Price", "Gold", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.45, 1),
		Icon = "💰",
		IconScale = 1.45,
		Text = "0",
		Tier = "Title",
		Brick = {
			studs = 3,
			studScale = 0.5,
			studArea = { 0.35, 0.95 },
			spec = { x = 0.3, y = 0.16, w = 0.06, h = 0.1 },
		},
		LabelProps = { Size = UDim2.fromScale(0.78, BRICK_FACE * 0.8) },
	})
	label(price, "Multiplier", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.97, 0.02),
		Size = UDim2.fromScale(0.42, 0.95),
		Rotation = 12,
		Text = "×2",
		Outline = 4,
		TextGradient = { WHITE, P.Gold.Top },
		ZIndex = BZ.Top,
		MaxTextSize = 34,
		MinTextSize = 14,
	})

	-- The close hint, named like the button's «ЗАБРАТЬ!»: muted on the plate, Body tier (≥ 14 px
	-- on the smallest phone); hidden until the last beat of the reveal, then it breathes gently.
	label(card, "TapHint", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, 0.955),
		Size = UDim2.fromScale(0.8, 0.075),
		Text = "Тапни — забрать!",
		TextColor3 = UI.Fishing.Muted,
		TextStrokeTransparency = 1,
		ZIndex = 6,
		Tier = "Body",
	})

	-- The giant rarity title (Epic and rarer, FUI-03): slams in at the centre of the screen when
	-- the fish lands, then flies into the card's banner. Label: the whole word (Epic); Letters:
	-- FishingController puts one label per letter there (Legendary / Mythic wave).
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
	label(title, "Label", {
		Size = UDim2.fromScale(1, 1),
		Text = "ЭПИЧЕСКАЯ!",
		Outline = 8,
		TextGradient = { WHITE, UI.Rarity.Epic.Top },
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
	    ActionButton          round plate (Theme.roundPlate: Lip, Face with the raised Stud): Icon
	                          (emoji or the «!» glyph: Outline, TextFill) on the stud,
	                          CaptionRibbon (black tile) + Caption («ЗАБРОСИТЬ» / «ЖДЁМ…» /
	                          «КУДА ИДТИ?» / «ПОДСЕЧЬ!» / «ЛОВИ!» / «ВЗЯТЬ» / «ЗАБРАТЬ!»), Ring
	                          (white halo), KeyChip.Key («F» / «R2», a white tile), TapCue (👆),
	                          Bobber (the waiting look's icon)
	    StopButton            «СМОТАТЬ» red 1x3 brick above it (Icon 🧵 inside, Caption)
	  BiteAlert               orange 1x6 brick: «КЛЮЁТ!» (Label), «!» IconLeft/IconRight,
	                          TimerTrack (black groove) + Timer, TapPad (touch: a tap on the plate hooks)
	  Minigame                dark stone baseplate (Face.StudRow; AuraStroke.AuraFill for Epic+):
	                          Title (rarity gradient), Track (black groove: Zone — a green brick
	                          with 3 studs: Glow, Flash; Rider 🐟 on its studs; Needle: Head ▼),
	                          Clock ⏱ + TimeBar (Fill), Pips (Pip1..Pip5: studs from above with a
	                          Cap and a Star), Help, TapPad
	  Hint                    smooth tile: IconSocket.Icon + Label (Hint.Text = the value)
	  CatchDim, CatchRays     the reveal's dim and the holder of its sunburst, behind the card
	  CatchCard               TextButton (tap: skip the reveal / close) — a white display plate:
	                          Face.{Window, StudsTop, StudsLeft, StudsRight}, Banner (a studded
	                          brick: RarityLabel, stars), FishGlow, Pedestal (studded brick),
	                          Viewport (the fish model), NewStamp «НОВИНКА!» (red tile), NameLabel,
	                          MutationLabel (corner stamp tile: Icon, Caption), InfoLabel (Weight
	                          tile, Price brick; Price.Multiplier «×N»), TapHint, LipBand.
	                          Square here; phones: the landscape layout of FishingController
	                          (same children)
	  TitleSlam               the giant rarity title of Epic+ (Label, Letters), flies into the
	                          banner
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
