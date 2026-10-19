--[[
	Alert — the victim's alert (stage 4, docs/stage4_design.md §6.3) in the UI v5 «Симулятор»
	style: the plate HUD.TheftAlert at the top of the toast column, «🚨 ВОР В САДКЕ!» with one line
	under it on the left and the two big buttons on the right of the same row — [🛡️ ЩИТ] (the
	plate's largest target: ≥ UIConfig.Theft.ShieldMin px tall, ≥ Theft.ShieldShare of the plate's
	width) and [🏠 ДОМОЙ] (≥ Theft.HomeMin px) —, and its Compact pill for phones when the plate
	would cover the own fisher. Controller and all the motion: AlertController (wave 2 D); the
	layers around it (the edge vignette, «ДОМОЙ!», «ЩИТ!» on the column) belong to the other
	controllers. Every text comes from StealConfig.Texts.Alert, every number of the place from
	UIConfig.Theft (pure modules). Layout rules: tools/builder/Gui.luau; look and API:
	tools/builder/gui/STYLE.md.

	Names are a contract (AlertController, tests and the preview scenarios find them):
	  TheftAlert    (hidden, ZIndex 32: over the sheets) the root at the top of the toast column
	                (NotifyController.Reserve("alert", px) moves the toasts under it): Theft.Width
	                of the HUD width (≤ Theft.WidthMax px; AlertController keeps it inside the toast
	                column), ≈ Theft.PlateHeight px tall on a phone; for the Compact pill
	                AlertController makes the root the pill's own box (Theft.CompactHeight tall: the
	                root's height floor is the pill's)
	    Plate       a Berry sim plate (AlertController shakes and pops it)
	    Icon        a socket over the plate's left end: Icon.Icon 🚨
	    Text        the left part: Title (CAPS «ВОР В САДКЕ!» / «ВОР УБЕГАЕТ!», one line, the box
	                fits it: TITLE_MIN..TITLE_MAX px), Sub (italic, «Ника крадёт: Окунь», wraps,
	                12..SUB_MAX px; «Пока крадёшь сам, щит не включить» — then the buttons are hidden)
	    Buttons     the right part, a right-aligned row:
	      Shield    a Guard row button «🛡️ ЩИТ» (Icon, Caption): Slate «⏳ 1:12» while the shield
	                recharges, ⏳ until the server answers
	      Home      a Grape square «🏠 ДОМОЙ» (Icon, Caption) with Home's cooldown veil look
	    Compact     (hidden) the pill variant filling the root (Theft.CompactHeight px tall on a
	                phone), placed by AlertController beside the own fisher: a Berry plate with Icon 🚨
	                and Label «ВОР! Окунь», then Shield (Guard «🛡️ ЩИТ» at the pill's right end, its
	                full height — ≥ Theft.ShieldMin px — and ≥ Theft.ShieldShare of its width: the
	                largest target here too) or Home (a round Grape 🏠, hidden: when the shield is
	                not ready)
	Sizes are scales only, capped by UISizeConstraint on big screens; text never under 12 px.
]]

local Theme = require("./Theme")

local U = Theme.U
local Enum = U.Enum
local UDim = U.UDim
local UDim2 = U.UDim2
local Vector2 = U.Vector2

local UI = Theme.UI
local SZ = Theme.SZ
local label = Theme.label

-- Texts and numbers (pure modules, the same tables the client reads).
local StealConfig = U.loadPure("src/ReplicatedStorage/Shared/Config/StealConfig.luau")
local TextUtil = U.loadPure("src/ReplicatedStorage/Shared/TextUtil.luau")
local TEXTS = StealConfig.Texts.Alert
local THEFT = UI.Theft

local Z = 32 -- over the sheets (30) and the base banner (20), like the thief's banner
-- The plate's height as a share of the HUD (≈ Theft.PlateHeight on a phone's 332 px HUD).
local HEIGHT = 0.22
-- The buttons' row: a share of the plate's width; ЩИТ takes Theft.ShieldShare of the PLATE.
-- (ЩИТ ShieldShare + a gap + a 44 px ДОМОЙ on the phone_small column: «ВОР УБЕГАЕТ!» keeps its
-- Title tier left of them — tests/stage4_rules text widths)
local BUTTONS = 0.485
local SHIELD = THEFT.ShieldShare / BUTTONS + 0.003

local SAMPLE = { name = "Ника", short = "Окунь" }
-- The Compact pill's ЩИТ: this share of the pill's width (≥ Theft.ShieldShare: the largest target).
local COMPACT_SHIELD = 0.42
-- The plate's text, px (the box fits it: TextScaled between these).
local TITLE_MAX = 30
local TITLE_MIN = 14
local SUB_MAX = 20

local function buildPlate(root: any)
	local plate = U.new("Frame", {
		Name = "Plate",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 1,
	}, root)
	Theme.sim(plate, "Berry", { radius = UI.Sim.PlateRadius, shine = false })

	-- 🚨 over the plate's left end.
	Theme.socket(root, "Icon", "🚨", {
		AnchorPoint = Vector2.new(0.55, 0.5), -- (mostly outside the plate: the text needs the room)
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromScale(0.9, 0.9),
		ZIndex = 4,
	})

	-- The text on the left: the CAPS title and one line under it (it wraps: a long name).
	local text = U.new("Frame", {
		Name = "Text",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.08, 0.08),
		Size = UDim2.fromScale(0.985 - BUTTONS - 0.09, 0.84),
		ZIndex = 4,
	}, root)
	-- (box-driven, not tiered: on a desktop the chat narrows the toast column to ≈ 390 px and the
	-- Title tier there — 32 px — would break «ВОР УБЕГАЕТ!» into two lines over the Sub; the box
	-- keeps one line, never under TITLE_MIN / 12 px)
	label(text, "Title", {
		Position = UDim2.fromScale(0, 0.02),
		Size = UDim2.fromScale(1, 0.54),
		Text = TEXTS.Hold,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = false,
		ZIndex = 4,
		MaxTextSize = TITLE_MAX,
		MinTextSize = TITLE_MIN,
	})
	label(text, "Sub", {
		Position = UDim2.fromScale(0, 0.58),
		Size = UDim2.fromScale(1, 0.38),
		Text = TextUtil.fill(TEXTS.HoldSub, SAMPLE),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Italic = true,
		ZIndex = 4,
		MaxTextSize = SUB_MAX,
		MinTextSize = 12,
	})

	-- The buttons on the right of the same row: [🛡️ ЩИТ] (the largest target) and [🏠 ДОМОЙ].
	local buttons = U.new("Frame", {
		Name = "Buttons",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(0.985, 0.5),
		Size = UDim2.fromScale(BUTTONS, 0.86),
		ZIndex = 4,
	}, root)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0.02, 0),
	}, buttons)
	local shield = Theme.simButton(buttons, "Shield", "Guard", {
		LayoutOrder = 1,
		Size = UDim2.fromScale(SHIELD, 1),
		Layout = "row",
		Icon = "🛡️",
		Caption = TEXTS.Shield,
		Tier = "Button",
		ZIndex = 5,
		SimOpts = { stroke = Theme.MINOR },
	})
	U.new("UISizeConstraint", { MinSize = Vector2.new(0, THEFT.ShieldMin) }, shield)
	local home = Theme.simButton(buttons, "Home", "Grape", {
		LayoutOrder = 2,
		Size = UDim2.fromScale(0.72, 0.72), -- (≥ Theft.HomeMin: the plate is ≥ PlateHeight tall)
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Layout = "square",
		Icon = "🏠",
		Caption = TEXTS.Home,
		-- (no tier: the square is only ≈ 44–64 px, so «ДОМОЙ» scales 12..16 px to its width
		-- instead of the Small tier, which grows with the screen and would break the word)
		MaxTextSize = 16,
		MinTextSize = 12,
		ZIndex = 5,
		SimOpts = { stroke = Theme.MINOR },
	})
	U.new("UISizeConstraint", { MinSize = Vector2.new(THEFT.HomeMin, THEFT.HomeMin) }, home)
	home.Caption.TextWrapped = false -- (shrinks, never breaks)
end

-- The phone pill when the plate would cover the own fisher: «🚨 ВОР! Окунь» + ЩИТ (or 🏠).
local function buildCompact(root: any)
	local compact = Theme.plate(root, "Compact", "Berry", {
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0),
		Size = UDim2.fromScale(1, 1), -- (AlertController makes the root the pill's box)
		ZIndex = 2,
		Icon = "🚨",
		IconScale = 0.9, -- (inside the pill: its ink stays within the pill height)
		Text = TextUtil.fill(TEXTS.Compact, { short = TextUtil.upper(SAMPLE.short) }),
		Tier = "Body",
		Radius = 0.5,
		SimOpts = { shine = false },
		LabelProps = {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.13, 0.5),
			Size = UDim2.fromScale(0.42, 0.7),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		},
	})
	U.new("UISizeConstraint", { MinSize = Vector2.new(0, THEFT.CompactHeight) }, compact)
	-- ЩИТ at the pill's right end, its full height (≥ ShieldMin) and COMPACT_SHIELD of its width.
	local shield = Theme.simButton(compact, "Shield", "Guard", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromScale(COMPACT_SHIELD, 1),
		Layout = "row",
		Icon = "🛡️",
		Caption = TEXTS.Shield,
		Tier = "Button",
		ZIndex = 5,
		SimOpts = { stroke = Theme.MINOR },
	})
	U.new("UISizeConstraint", { MinSize = Vector2.new(0, THEFT.ShieldMin) }, shield)
	local home = Theme.simButton(compact, "Home", "Grape", {
		Visible = false,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromScale(1, 1),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Layout = "round",
		Icon = "🏠",
		ZIndex = 5,
		SimOpts = { stroke = Theme.MINOR },
	})
	U.new("UISizeConstraint", { MinSize = Vector2.new(THEFT.HomeMin, THEFT.HomeMin) }, home)
end

local function build(hud: any)
	local root = U.new("Frame", {
		Name = "TheftAlert",
		Visible = false,
		Active = true, -- taps on the plate never reach the world
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, 0.26), -- the toast column's top (gui/Hud.luau buildToasts)
		Size = UDim2.fromScale(THEFT.Width, HEIGHT),
		ZIndex = Z,
	}, hud)
	-- (the height floor is the Compact pill's: AlertController sizes the root in px — the plate
	-- Theft.PlateHeight.., the pill Theft.CompactHeight)
	U.new("UISizeConstraint", {
		MinSize = Vector2.new(0, THEFT.CompactHeight),
		MaxSize = Vector2.new(THEFT.WidthMax, THEFT.PlateHeight * 1.35),
	}, root)
	buildPlate(root)
	buildCompact(root)
end

return build
