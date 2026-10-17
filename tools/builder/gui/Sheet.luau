--[[
	Sheet — the shell of a modal "sheet" over the game in the UI v5 «Симулятор» style: the tank
	panel (stage 3, tools/builder/gui/Tank.luau fills it) and later the stage 5 shop reuse it. The
	client helper Controllers/Sheet.luau opens, places and closes it (snapIn / popOut; its place
	and the place of the header, the ✕ and the card strip are computed in px and written back as
	scales — of the HUD, of the plate —, again on a ViewportSize change; it closes itself when
	fishing needs the screen). Layout rules: tools/builder/Gui.luau; look and API:
	tools/builder/gui/STYLE.md.

	Names are a contract (controllers and tests find them):
	  <Name>          the root (a transparent Frame, hidden, ZIndex 30 by default: above HUD.Fishing
	                  and the base banner); its Position / Size are the sheet's place (scale of the
	                  HUD), the default below is the phone's (16..733 × 146..374 px on 844 × 390)
	    Panel         the plate: a Night sim plate (tablet / desktop, no shine) — on phones the
	                  client turns it into glass (UiFx.setCandy: one quad, secondary info on glass);
	                  no dim around it; Active (taps on it never reach the world)
	      Strip       a thin Night band under the header (one quad: a gradient, round corners) —
	                  shown on phones only, where the plate is glass (Controllers/Sheet)
	      Header      the row of the title (a horizontal UIListLayout, LayoutOrder): Icon (an
	                  outlined emoji, LayoutOrder 1), Title (Title tier, CAPS, LayoutOrder 2); the
	                  owner adds its own chips after them (LayoutOrder 3+)
	      Close       a round Berry «✕» button (≥ 44 px) overhanging the plate's top-right corner
	      Cards       a ScrollingFrame (it clips; no scroll bar: the cut-off last card says "more")
	                  with a UIGridLayout (horizontal fill) and a UIPadding — the client sets the
	                  cell size, the padding and an explicit CanvasSize, all as scales (no
	                  AutomaticCanvasSize: RbxSim and the preview do not know it); the owner puts
	                  its templates there (hidden)
	Sizes are scales only (the spec: «UDim2 через scale»), capped by UISizeConstraint where a
	scale alone would grow too big on a desktop.

	build(hud, name, opts) -> { root, panel, strip, header, close, cards }
	  opts: Icon (emoji), Title (text, already in CAPS), ZIndex (default 30), Token (the plate's
	  colour, default Night).
]]

local Theme = require("./Theme")

local U = Theme.U
local Enum = U.Enum
local UDim = U.UDim
local UDim2 = U.UDim2
local Vector2 = U.Vector2

local UI = Theme.UI
local P = Theme.P
local SZ = Theme.SZ
local label = Theme.label

-- The phone's place (HUD 844 × 332 below the top bar): x 16..733, y 88..316 → scales of the HUD.
local DEFAULT_POSITION = UDim2.fromScale(0.019, 0.265)
local DEFAULT_SIZE = UDim2.fromScale(0.85, 0.687)
local HEADER_HEIGHT = 0.2 -- of the plate (≈ 45 px on a phone; the client caps it in px) …
local HEADER_MAX = 64 -- … never taller than this on a big screen, px

local function build(hud: any, name: string, opts: { [string]: any }): { [string]: any }
	local root = U.new("Frame", {
		Name = name,
		Visible = false,
		BackgroundTransparency = 1,
		Position = DEFAULT_POSITION,
		Size = DEFAULT_SIZE,
		ZIndex = opts.ZIndex or 30,
	}, hud)

	-- The plate: a Night sim plate with the chunky outline in its dark shade, no shine sweep
	-- (it is a panel, not a button; the client makes it glass on phones).
	local panel = U.new("Frame", {
		Name = "Panel",
		Active = true, -- taps on the plate do not fall through to the world
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5), -- (its UIScale grows / shrinks it about its middle)
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
	}, root)
	Theme.sim(panel, opts.Token or "Night", { radius = UI.Sim.Radius, shine = false })

	-- The header band of the glass plate (phones): one Night quad, round corners.
	local strip = U.new("Frame", {
		Name = "Strip",
		Visible = false,
		BackgroundColor3 = Theme.WHITE,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 0),
		Size = UDim2.fromScale(1, HEADER_HEIGHT + 0.02),
		ZIndex = SZ.Content, -- over the face (Lip 1, Face 2), under the header and the cards
	}, panel)
	Theme.corner(strip, UI.Sim.Radius * 2.5)
	Theme.gradient(strip, P.Night.Top, P.Night.Bottom)

	local header = U.new("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.015, 0.01),
		Size = UDim2.fromScale(0.86, HEADER_HEIGHT),
		ZIndex = SZ.Content + 1,
	}, panel)
	U.new("UISizeConstraint", { MaxSize = Vector2.new(10000, HEADER_MAX) }, header)
	U.new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0.012, 0),
	}, header)
	Theme.icon(header, "Icon", opts.Icon or "", {
		LayoutOrder = 1,
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Size = UDim2.fromScale(0.8, 0.8), -- (the emoji's ink is taller than its box: it stays on the plate)
	})
	-- (as wide as 2.8 header heights: «САДОК» at the Title tier fits on one line on every screen —
	-- the tier grows with the screen height, the header only up to HEADER_MAX)
	label(header, "Title", {
		LayoutOrder = 2,
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		Size = UDim2.fromScale(2.8, 0.8),
		Text = opts.Title or "",
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = SZ.Content,
		Tier = "Title",
	})

	-- ✕: a round red button on the plate's top-right corner (a little over its edge), ≥ 44 px.
	local close = Theme.simButton(panel, "Close", "Berry", {
		Layout = "round",
		Icon = "✕",
		AnchorPoint = Vector2.new(0.7, 0.3),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromScale(0.2, 0.2),
		SizeConstraint = Enum.SizeConstraint.RelativeYY,
		ZIndex = SZ.Top + 1,
		SimOpts = { stroke = Theme.MINOR, shine = false },
	})
	U.new("UISizeConstraint", { MinSize = Vector2.new(44, 44), MaxSize = Vector2.new(60, 60) }, close)

	-- The cards: a strip that scrolls sideways (one row on phones, the owner sets the rows).
	local cards = U.new("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromScale(0.014, 0.24),
		Size = UDim2.fromScale(0.972, 0.73),
		CanvasSize = UDim2.fromScale(1, 1),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		ZIndex = SZ.Content + 1,
	}, panel)
	U.new("UIGridLayout", {
		CellSize = UDim2.fromScale(0.15, 0.9),
		CellPadding = UDim2.fromScale(0.012, 0.02),
		FillDirection = Enum.FillDirection.Horizontal,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	}, cards)
	U.new("UIPadding", {
		PaddingLeft = UDim.new(0.01, 0),
		PaddingRight = UDim.new(0.01, 0),
		PaddingTop = UDim.new(0.06, 0),
		PaddingBottom = UDim.new(0.03, 0),
	}, cards)

	return { root = root, panel = panel, strip = strip, header = header, close = close, cards = cards }
end

return { build = build }
