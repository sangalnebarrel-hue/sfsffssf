--[[
	Sheet — the shell of a modal "sheet" over the game in the UI v5 «Симулятор» style: the tank
	panel (stage 3, tools/builder/gui/Tank.luau fills it) and later the stage 5 shop reuse it. The
	client helper Controllers/Sheet.luau opens, places and closes it (snapIn / popOut, the place in
	px written back as a scale of the HUD, recomputed on a ViewportSize change, closes itself when
	fishing needs the screen). Layout rules: tools/builder/Gui.luau; look and API:
	tools/builder/gui/STYLE.md.

	Names are a contract (controllers and tests find them):
	  <Name>          the root (a transparent Frame, hidden, ZIndex 30 by default: above HUD.Fishing
	                  and the base banner); its Position / Size are the sheet's place (scale of the
	                  HUD), the default below is the phone's (16..733 × 153..374 px on 844 × 390)
	    Panel         the plate: a Night sim plate (tablet / desktop) — on phones the client turns it
	                  into glass (UiFx.setCandy: one quad, secondary info on glass); no dim around it
	      Header      the row of the title (a horizontal UIListLayout, LayoutOrder): Icon (an
	                  outlined emoji), Title (Title tier, CAPS); the owner adds its own chips after them
	      Close       a round Berry «✕» button (≥ 44 px) on the plate's top-right corner
	      Cards       a ScrollingFrame with a UIGridLayout (explicit CanvasSize: no AutomaticCanvasSize
	                  in RbxSim or the preview); one row on phones (FillDirection Vertical,
	                  FillDirectionMaxCells = rows), the owner puts its templates there (hidden)
	Sizes are scales only (the spec: «UDim2 через scale»), capped by UISizeConstraint where a
	scale alone would grow too big on a desktop.

	build(hud, name, opts) -> { root, panel, header, close, cards }
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
local SZ = Theme.SZ
local label = Theme.label

-- The phone's place (HUD 844 × 332 below the top bar): x 16..733, y 95..316 → scales of the HUD.
local DEFAULT_POSITION = UDim2.fromScale(0.02, 0.29)
local DEFAULT_SIZE = UDim2.fromScale(0.85, 0.66)
local HEADER_HEIGHT = 0.2 -- of the plate (≈ 44 px on a phone) …
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
		Size = UDim2.fromScale(1, 1),
	}, root)
	Theme.sim(panel, opts.Token or "Night", { radius = UI.Sim.Radius, shine = false })

	local header = U.new("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Position = UDim2.fromScale(0.02, 0.02),
		Size = UDim2.fromScale(0.86, HEADER_HEIGHT),
		ZIndex = SZ.Content,
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
		Size = UDim2.fromScale(1, 1),
	})
	label(header, "Title", {
		LayoutOrder = 2,
		Size = UDim2.fromScale(0.13, 0.8),
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
	U.new("UISizeConstraint", { MinSize = Vector2.new(44, 44), MaxSize = Vector2.new(64, 64) }, close)

	-- The cards: a horizontal strip that scrolls (one row on phones, the owner sets the rows).
	local cards = U.new("ScrollingFrame", {
		Name = "Cards",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0.02, 0.25),
		Size = UDim2.fromScale(0.96, 0.72),
		CanvasSize = UDim2.fromScale(1, 1),
		ScrollingDirection = Enum.ScrollingDirection.X,
		ScrollBarThickness = 0,
		ZIndex = SZ.Content,
	}, panel)
	U.new("UIGridLayout", {
		CellSize = UDim2.fromScale(0.15, 0.96),
		CellPadding = UDim2.fromScale(0.012, 0.02),
		FillDirection = Enum.FillDirection.Vertical,
		FillDirectionMaxCells = 1,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Top,
	}, cards)

	return { root = root, panel = panel, header = header, close = close, cards = cards }
end

return { build = build }
