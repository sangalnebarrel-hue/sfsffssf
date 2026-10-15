--[[
	Hud — the HUD chrome in the UI v3 «Кирпичики» style (toy bricks with studs; the reference for
	the other builders): the status stack (base badge, catch counter), the right button column
	(Home), the toast column, the base-assignment banner (built with the status stack: it flies
	into the badge) and the off-screen trophy chip. Controllers: HudController (badge, banner,
	catch counter, Home), NotifyController (toasts, trophy chip). Layout rules: tools/builder/
	Gui.luau; look and API: tools/builder/gui/STYLE.md.

	Names are a contract (controllers and tests find them): Status.BaseBadge.{Swatch, Label,
	FlagSocket.Flag}, Status.CatchCounter.{Icon, Label}, RightButtons.HomeButton.{Icon, Caption,
	Cooldown, CooldownText}, Toasts.ToastTemplate.{Label, IconSocket.Icon}, BaseBanner.{Caption,
	NameLabel, FlagSocket.Flag}, TrophyPointer.{Body.IconSocket.Icon, Tip, BaseRing.Stroke}
	(NotifyController: the chip pointing at someone else's off-screen light pillar). Everything
	else (Studs, Lip, Spec, Shine, Rim, …) is decoration.

	The bricks (Theme.brick; content at Theme.BZ.Content):
	  BaseBadge     a brick in the base colour with 4 studs, a white 1x1 flag tile (one stud)
	                over its left end, the name in CAPS («ЛАЗУРНАЯ БАЗА», Title tier);
	  CatchCounter  a yellow 1x3 brick «🐟 12»: the 🐟 sticker over its left end, the number as
	                a currency display (box-driven, about Title);
	  HomeButton    a square azure 2x2 brick with 2 studs, 🏠 and «ДОМОЙ» on its face;
	  ToastTemplate a smooth tile in the kind's colour with the icon in a white 1x1 round tile;
	                NotifyController gives Legendary / Mythic broadcasts studs (UiFx.setStuds);
	  BaseBanner    a big brick in the base colour with 6 studs and the flag tile;
	  TrophyPointer a round rarity brick with the icon in a white tile.
	Only the action button idles (shine / breathing); the chrome stays calm — the badge quieter
	than the counter.
]]

local Theme = require("./Theme")

local U = Theme.U
local Enum = U.Enum
local UDim = U.UDim
local UDim2 = U.UDim2
local Vector2 = U.Vector2

local UI = Theme.UI
local P = Theme.P
local BZ = Theme.BZ
local INK = Theme.INK
local WHITE = Theme.WHITE
local BRICK = Theme.BRICK
local FACE = 1 - BRICK.Lip -- a brick's face covers its top; content is centred on it
local TILE_FACE = 1 - BRICK.TileLip
local corner = Theme.corner
local label = Theme.label

-- The white 1x1 flag tile (one stud) that sits over the left end of the badge and the banner.
local function flagTile(parent: any, emoji: string, props: { [string]: any }): any
	local base: { [string]: any } = {
		Name = "FlagSocket",
		BackgroundTransparency = 1,
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = BZ.Content + 1,
	}
	for key, value in props do
		base[key] = value
	end
	local tile = U.new("Frame", base, parent)
	Theme.brick(tile, "Cream", {
		studs = 1,
		studScale = Theme.studScale(35), -- the stud module (UIM-05): the badge's tile is ≈ 35 px tall
		radius = 0.22,
		spec = { x = 0.12, y = 0.12, w = 0.2, h = 0.08 },
	})
	Theme.icon(tile, "Flag", emoji, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, FACE * 0.52),
		Size = UDim2.fromScale(0.94, FACE * 0.94),
		ZIndex = BZ.Content,
	})
	return tile
end

local function buildBaseBanner(hud: any)
	-- The moment the base is assigned: a big brick in the base's colour across the screen centre —
	-- small «ТВОЯ БАЗА» over big «ЛАЗУРНАЯ!», a waving 🚩 tile, rays and confetti behind; after
	-- ~2 s HudController shrinks it into the badge. Never takes input.
	local banner = U.new("Frame", {
		Name = "BaseBanner",
		Visible = false,
		Active = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45), -- its studs and flag tile stay clear of the chat window
		Size = UDim2.fromScale(1.05, 0.3),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = 20,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(560, 170) }, banner)
	-- (The one hero brick off the stud module: a 100 px slab for two seconds, its studs in scale.)
	Theme.brick(banner, "Leaf", {
		studs = 6,
		studArea = { 0.2, 0.98 },
		studScale = 0.55,
		spec = { x = 0.22, y = 0.14, w = 0.1, h = 0.07 },
	})
	flagTile(banner, "🚩", {
		AnchorPoint = Vector2.new(0.14, 0.5),
		Position = UDim2.fromScale(0, FACE * 0.52),
		Size = UDim2.fromScale(0.8, 0.8),
		Rotation = -8,
	})
	label(banner, "Caption", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.57, FACE * 0.25),
		Size = UDim2.fromScale(0.76, FACE * 0.26),
		Text = "ТВОЯ БАЗА",
		ZIndex = BZ.Content,
		Tier = "Body",
	})
	label(banner, "NameLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.57, FACE * 0.64),
		Size = UDim2.fromScale(0.78, FACE * 0.46),
		Text = "ЛАЗУРНАЯ!",
		Outline = 6,
		TextGradient = { WHITE, P.Cream.Bottom },
		ZIndex = BZ.Content,
		MaxTextSize = 64,
	})
end

local function buildStatus(hud: any)
	local status = U.new("Frame", {
		Name = "Status",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.02), -- room for the badge's studs under the top bar
		Size = UDim2.fromScale(0.9, 0.25),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
	}, hud)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(520, 210) }, status)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0.09, 0), -- the counter's studs stand in the gap
	}, status)

	-- "Your base" badge: a brick in the base colour (HudController paints it with the base's
	-- swatch, UIConfig.BaseSwatches; the face is named Swatch) with 4 studs and the white flag
	-- tile over its left end. LayoutOrder 20 leaves room above it for the money counter
	-- (Stage 3) and below it for the shield timer (Stage 4).
	local badge = U.new("Frame", {
		Name = "BaseBadge",
		LayoutOrder = 20,
		Size = UDim2.fromScale(0.76, 0.36),
	}, status)
	Theme.brick(badge, "Slate", {
		faceName = "Swatch",
		studs = 4,
		studArea = { 0.17, 0.97 },
		studScale = Theme.studScale(29), -- one stud module on every brick (≈ 29 px tall on a phone)
		spec = { x = 0.17, y = 0.17, w = 0.08, h = 0.09 },
	})
	flagTile(badge, "🔎", {
		AnchorPoint = Vector2.new(0.3, 0.5),
		Position = UDim2.fromScale(0, FACE * 0.52),
		Size = UDim2.fromScale(1.22, 1.22),
	})
	label(badge, "Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.585, FACE * 0.52),
		Size = UDim2.fromScale(0.76, FACE * 0.86),
		Text = "ИЩЕМ БАЗУ…",
		ZIndex = BZ.Content,
		Tier = "Title",
	})

	-- Catch counter (stage 2): fish caught this session — a yellow 1x3 brick «🐟 12» (a currency
	-- display: the 🐟 sticker over its left end, the number big), hidden until the first catch.
	-- HudController owns its text (the number) and visibility (Player attribute FishCaught; HUD
	-- attribute CounterHold). The 🐟 "Icon" is a direct child (contract).
	local counter = U.new("Frame", {
		Name = "CatchCounter",
		LayoutOrder = 30,
		Visible = false,
		Size = UDim2.fromScale(0.34, 0.29),
	}, status)
	Theme.brick(counter, "Gold", {
		studs = 3,
		studArea = { 0.3, 0.97 },
		studScale = Theme.studScale(24),
		spec = { x = 0.33, y = 0.17, w = 0.1, h = 0.09 },
	})
	Theme.icon(counter, "Icon", "🐟", {
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		AnchorPoint = Vector2.new(0.36, 0.5),
		Position = UDim2.fromScale(0, FACE * 0.5),
		Size = UDim2.fromScale(1.45, 1.45),
		ZIndex = BZ.Content + 1,
		Sticker = true,
	})
	label(counter, "Label", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.635, FACE * 0.52),
		Size = UDim2.fromScale(0.63, FACE * 1.02),
		Text = "0",
		Outline = Theme.TIER_OUTLINE.Title,
		ZIndex = BZ.Content,
		MaxTextSize = 40,
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
		Padding = UDim.new(0.05, 0), -- room for the studs of the button below
	}, right)

	-- "Home": a square azure 2x2 brick (2 studs) with 🏠 and «ДОМОЙ» on its face, shown once the
	-- player has a base. Azure (Mint), not Leaf: it never looks like «ЛОВИ!».
	local home = Theme.candyButton(right, "HomeButton", "Mint", {
		LayoutOrder = 100, -- bottom of the column; Shop/Shield go above it later
		Size = UDim2.fromScale(1, 0.3),
		Visible = false,
		Square = true,
		Brick = { studs = 2, studScale = Theme.studScale(60), spec = { x = 0.1, y = 0.1, w = 0.16, h = 0.06 } },
		Icon = "🏠",
	})
	local icon = home:FindFirstChild("Icon")
	icon.Position = UDim2.fromScale(0.5, FACE * 0.35)
	icon.Size = UDim2.fromScale(0.8, FACE * 0.66)
	U.new("UIStroke", {
		Name = "Sticker",
		Color = WHITE,
		Thickness = 3,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		LineJoinMode = Enum.LineJoinMode.Round,
		Attributes = { BaseThickness = 3 },
	}, icon)
	-- On the face; during the cooldown HudController lifts it above the veil as «ЖДИ».
	label(home, "Caption", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, FACE * 0.8),
		Size = UDim2.fromScale(0.96, FACE * 0.36),
		Text = "ДОМОЙ",
		ZIndex = BZ.Content + 1,
		Tier = "Button",
	})
	-- Cooldown: a dark veil over the whole brick that drains downwards (HudController moves the
	-- hard edge of the "Drain" gradient: Offset.Y -0.5 = fully covered → 0.5 = clear), plus the
	-- seconds left in big digits centred on the face.
	local cooldown = U.new("Frame", {
		Name = "Cooldown",
		BackgroundColor3 = INK,
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = BZ.Overlay,
	}, home)
	corner(cooldown, BRICK.Radius)
	U.new("UIGradient", {
		Name = "Drain",
		Rotation = 90,
		Offset = Vector2.new(0, -0.5),
		Transparency = Theme.numbers({ { 0, 1 }, { 0.495, 1 }, { 0.5, 0 }, { 1, 0 } }),
	}, cooldown)
	label(home, "CooldownText", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, FACE * 0.4),
		Size = UDim2.fromScale(0.8, FACE * 0.66),
		Text = "",
		Outline = 5,
		ZIndex = BZ.Top,
		MaxTextSize = 56,
		TextGradient = { WHITE, P.Gold.Top },
	})
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

	-- A smooth tile per toast: NotifyController clones it, recolours it by kind
	-- (UIConfig.ToastKinds: Sky / Leaf / Sun / Berry / base colour / Gold / rainbow), puts the
	-- kind's emoji into the white round tile and gives Legendary / Mythic broadcasts studs.
	Theme.pill(toasts, "ToastTemplate", "Sky", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 0.28),
		Brick = { tile = true, spec = { x = 0.1, y = 0.16, w = 0.07, h = 0.09 } },
		Icon = UI.ToastKinds.info.Icon,
		Socket = true,
		IconScale = 1.0,
		Text = "",
		Tier = "Body",
		LabelProps = {
			Position = UDim2.fromScale(0.96, TILE_FACE * 0.5),
			Size = UDim2.fromScale(0.8, TILE_FACE * 0.74),
			TextWrapped = true, -- long texts: NotifyController makes the toast taller (two lines)
		},
	})

	-- Someone else's Legendary / Mythic catch whose light pillar is off-screen: NotifyController
	-- clones this per catch to the screen edge on the pillar's side (FishingFxController.OtherTrophy)
	-- — a round brick in the rarity colours (Gold / rainbow) with the 🌟 / 🌈 in a white tile, in
	-- a ring of the catcher's base colour, its Tip (an arrowhead in the rarity colour, out from
	-- under the brick) pointing at the edge (built on the right; mirrored for the left). Small (≈ 46
	-- px on a phone) and never takes input.
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
		Position = UDim2.fromScale(1.1, 0.46),
		Size = UDim2.fromScale(0.44, 0.44),
		Rotation = 45,
		BackgroundColor3 = P.Gold.Top,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, pointer)
	corner(tip, 0.18)
	Theme.stroke(tip, Theme.STROKE)
	local ring = U.new("Frame", {
		Name = "BaseRing",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.48),
		Size = UDim2.fromScale(1.2, 1.2),
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
	Theme.brick(body, "Gold", { radius = 0.5, lip = 0.12, spec = { x = 0.2, y = 0.12, w = 0.18, h = 0.08 } })
	Theme.socket(body, "IconSocket", "🌟", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.88 * 0.5),
		Size = UDim2.fromScale(0.7, 0.7),
		ZIndex = BZ.Content,
	})
end

return {
	buildStatus = buildStatus,
	buildRightButtons = buildRightButtons,
	buildToasts = buildToasts,
}
