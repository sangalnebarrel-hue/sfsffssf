-- members/gui.luau: GUI members. Absolute sizes/positions are computed from
-- UDim2 Size/Position, AnchorPoint, SizeConstraint, UIPadding, UISizeConstraint,
-- UIAspectRatioConstraint and basic UIListLayout/UIGridLayout stacking (a grid fills rows or,
-- with FillDirection Vertical, columns; FillDirectionMaxCells caps a line), against the owning
-- player's viewport (device profile).

local roblox = require("@lune/roblox")

local Vector2 = roblox.Vector2
local Enum = roblox.Enum

local INSET = 58

return function(M)
	local function readOr(inst, key, default)
		local ok, v = pcall(function()
			return inst[key]
		end)
		if ok and v ~= nil then
			return v
		end
		return default
	end

	local function viewportOf(sim, real)
		local player = sim.players:ownerOf(real)
		local st = player and sim.players.state[player]
		if st then
			return st.viewport
		end
		return sim:_viewportFor(sim.sched:context())
	end

	local function layerRect(sim, layer)
		if layer:IsA("ScreenGui") then
			local vp = viewportOf(sim, layer)
			if readOr(layer, "IgnoreGuiInset", false) then
				return Vector2.zero, vp
			end
			return Vector2.new(0, INSET), Vector2.new(vp.X, vp.Y - INSET)
		elseif layer:IsA("SurfaceGui") then
			return Vector2.zero, readOr(layer, "CanvasSize", Vector2.new(800, 600))
		elseif layer:IsA("BillboardGui") then
			local s = layer.Size
			return Vector2.zero, Vector2.new(s.X.Offset + s.X.Scale * 50, s.Y.Offset + s.Y.Scale * 50)
		end
		return Vector2.zero, viewportOf(sim, layer)
	end

	local absRect

	local function sizeOf(gui, psize)
		local size = gui.Size
		local sx = size.X.Scale * psize.X + size.X.Offset
		local sy = size.Y.Scale * psize.Y + size.Y.Offset
		local sc = readOr(gui, "SizeConstraint", Enum.SizeConstraint.RelativeXY)
		if sc == Enum.SizeConstraint.RelativeXX then
			sy = size.Y.Scale * psize.X + size.Y.Offset
		elseif sc == Enum.SizeConstraint.RelativeYY then
			sx = size.X.Scale * psize.Y + size.X.Offset
		end
		local szc = gui:FindFirstChildOfClass("UISizeConstraint")
		if szc then
			local mn, mx = szc.MinSize, szc.MaxSize
			sx = math.clamp(sx, mn.X, math.max(mn.X, mx.X))
			sy = math.clamp(sy, mn.Y, math.max(mn.Y, mx.Y))
		end
		local arc = gui:FindFirstChildOfClass("UIAspectRatioConstraint")
		if arc and arc.AspectRatio > 0 then
			local ratio = arc.AspectRatio
			local aspectType = readOr(arc, "AspectType", Enum.AspectType.FitWithinMaxSize)
			local dominant = readOr(arc, "DominantAxis", Enum.DominantAxis.Width)
			if aspectType == Enum.AspectType.ScaleWithParentSize then
				if dominant == Enum.DominantAxis.Width then
					sy = sx / ratio
				else
					sx = sy * ratio
				end
			elseif sx / math.max(sy, 1e-9) > ratio then
				sx = sy * ratio
			else
				sy = sx / ratio
			end
		end
		return Vector2.new(sx, sy)
	end

	local function sortedSiblings(parent, layout)
		local items = {}
		for _, c in parent:GetChildren() do
			if c:IsA("GuiObject") and c.Visible then
				table.insert(items, c)
			end
		end
		local byName = readOr(layout, "SortOrder", Enum.SortOrder.LayoutOrder) == Enum.SortOrder.Name
		table.sort(items, function(a, b)
			if byName then
				return a.Name < b.Name
			end
			if a.LayoutOrder ~= b.LayoutOrder then
				return a.LayoutOrder < b.LayoutOrder
			end
			return a.Name < b.Name
		end)
		return items
	end

	-- A UIGridLayout in a parent of psize px: cell and padding px, cells per line (FillDirection
	-- Horizontal — per row, by the width; Vertical — per column, by the height; FillDirectionMaxCells
	-- caps it) and cell(idx) -> (column, row) of the idx-th (0-based) item.
	local function gridOf(grid, psize)
		local cell, cpad = grid.CellSize, grid.CellPadding
		local cw = cell.X.Scale * psize.X + cell.X.Offset
		local ch = cell.Y.Scale * psize.Y + cell.Y.Offset
		local px = cpad.X.Scale * psize.X + cpad.X.Offset
		local py = cpad.Y.Scale * psize.Y + cpad.Y.Offset
		local vertical = readOr(grid, "FillDirection", Enum.FillDirection.Horizontal) == Enum.FillDirection.Vertical
		local fit = if vertical
			then math.max(1, math.floor((psize.Y + py) / math.max(ch + py, 1)))
			else math.max(1, math.floor((psize.X + px) / math.max(cw + px, 1)))
		local maxCells = readOr(grid, "FillDirectionMaxCells", 0)
		if maxCells > 0 then
			fit = math.min(fit, maxCells)
		end
		return {
			cw = cw,
			ch = ch,
			px = px,
			py = py,
			vertical = vertical,
			fit = fit,
			cell = function(idx: number): (number, number)
				if vertical then
					return idx // fit, idx % fit
				end
				return idx % fit, idx // fit
			end,
		}
	end

	-- Position of `gui` inside a parent that has a UIListLayout / UIGridLayout.
	local function layoutPosition(gui, parent, ppos, psize)
		local list = parent:FindFirstChildOfClass("UIListLayout")
		if list then
			local vertical = list.FillDirection == Enum.FillDirection.Vertical
			local pad = list.Padding
			local padPx = pad.Scale * (if vertical then psize.Y else psize.X) + pad.Offset
			local offset = 0
			for _, c in sortedSiblings(parent, list) do
				local s = sizeOf(c, psize)
				if c == gui then
					return if vertical then ppos + Vector2.new(0, offset) else ppos + Vector2.new(offset, 0)
				end
				offset += (if vertical then s.Y else s.X) + padPx
			end
		end
		local grid = parent:FindFirstChildOfClass("UIGridLayout")
		if grid then
			local g = gridOf(grid, psize)
			for i, c in sortedSiblings(parent, grid) do
				if c == gui then
					local col, row = g.cell(i - 1)
					return ppos + Vector2.new(col * (g.cw + g.px), row * (g.ch + g.py)), Vector2.new(g.cw, g.ch)
				end
			end
		end
		return nil
	end

	absRect = function(sim, gui)
		local parent = gui.Parent
		local ppos, psize
		if parent ~= nil and parent:IsA("GuiObject") then
			ppos, psize = absRect(sim, parent)
			if parent:IsA("ScrollingFrame") then
				local cs = parent.CanvasSize
				psize = Vector2.new(cs.X.Scale * psize.X + cs.X.Offset, cs.Y.Scale * psize.Y + cs.Y.Offset)
				local cp = readOr(parent, "CanvasPosition", Vector2.zero)
				ppos = ppos - cp
			end
			local pad = parent:FindFirstChildOfClass("UIPadding")
			if pad then
				local l = pad.PaddingLeft.Scale * psize.X + pad.PaddingLeft.Offset
				local r = pad.PaddingRight.Scale * psize.X + pad.PaddingRight.Offset
				local t = pad.PaddingTop.Scale * psize.Y + pad.PaddingTop.Offset
				local b = pad.PaddingBottom.Scale * psize.Y + pad.PaddingBottom.Offset
				ppos = ppos + Vector2.new(l, t)
				psize = psize - Vector2.new(l + r, t + b)
			end
		elseif parent ~= nil and parent:IsA("LayerCollector") then
			ppos, psize = layerRect(sim, parent)
		else
			ppos, psize = Vector2.zero, viewportOf(sim, gui)
		end
		local size = sizeOf(gui, psize)
		if parent ~= nil and parent:IsA("GuiObject") then
			local lp, cellSize = layoutPosition(gui, parent, ppos, psize)
			if lp then
				return lp, cellSize or size
			end
		end
		local pos = gui.Position
		local anchor = gui.AnchorPoint
		local px = ppos.X + pos.X.Scale * psize.X + pos.X.Offset - anchor.X * size.X
		local py = ppos.Y + pos.Y.Scale * psize.Y + pos.Y.Offset - anchor.Y * size.Y
		return Vector2.new(px, py), size
	end

	local function textBounds(_, real)
		local text = tostring(readOr(real, "Text", ""))
		local size = readOr(real, "TextSize", 14)
		return Vector2.new(#text * size * 0.5, if #text > 0 then size else 0)
	end

	local function stripRich(text)
		return (string.gsub(text, "<[^>]->", ""))
	end

	local function legacyTween(sim, real, goals, dir, style, time, override, callback)
		return sim.tweens:legacy(real, goals, dir, style, time, override, callback)
	end

	M.define("GuiObject", {
		AbsoluteSize = M.prop(function(sim, real)
			local _, size = absRect(sim, real)
			return size
		end),
		AbsolutePosition = M.prop(function(sim, real)
			local pos = absRect(sim, real)
			return pos
		end),
		AbsoluteRotation = M.prop(function(_, real)
			return real.Rotation
		end),
		InputBegan = M.signal(),
		InputEnded = M.signal(),
		InputChanged = M.signal(),
		MouseEnter = M.signal(),
		MouseLeave = M.signal(),
		MouseMoved = M.signal(),
		MouseWheelForward = M.signal(),
		MouseWheelBackward = M.signal(),
		TouchTap = M.signal(),
		TouchLongPress = M.signal(),
		TouchPan = M.signal(),
		TouchPinch = M.signal(),
		TouchRotate = M.signal(),
		TouchSwipe = M.signal(),
		SelectionGained = M.signal(),
		SelectionLost = M.signal(),
		TweenSize = M.method(function(sim, real, size, dir, style, time, override, callback)
			return legacyTween(sim, real, { Size = size }, dir, style, time, override, callback)
		end),
		TweenPosition = M.method(function(sim, real, pos, dir, style, time, override, callback)
			return legacyTween(sim, real, { Position = pos }, dir, style, time, override, callback)
		end),
		TweenSizeAndPosition = M.method(function(sim, real, size, pos, dir, style, time, override, callback)
			return legacyTween(sim, real, { Size = size, Position = pos }, dir, style, time, override, callback)
		end),
	})

	M.define("LayerCollector", {
		AbsoluteSize = M.prop(function(sim, real)
			local _, size = layerRect(sim, real)
			return size
		end),
		AbsolutePosition = M.prop(function(sim, real)
			local pos = layerRect(sim, real)
			return pos
		end),
		AbsoluteRotation = M.prop(function()
			return 0
		end),
	})

	M.define("GuiButton", {
		Activated = M.signal(),
		MouseButton1Click = M.signal(),
		MouseButton1Down = M.signal(),
		MouseButton1Up = M.signal(),
		MouseButton2Click = M.signal(),
		MouseButton2Down = M.signal(),
		MouseButton2Up = M.signal(),
	})

	local textDefs = {
		TextBounds = M.prop(textBounds),
		TextFits = M.prop(function()
			return true
		end),
		ContentText = M.prop(function(_, real)
			local text = tostring(readOr(real, "Text", ""))
			if readOr(real, "RichText", false) then
				return stripRich(text)
			end
			return text
		end),
	}
	M.define("TextLabel", textDefs)
	M.define("TextButton", textDefs)
	M.define("TextBox", textDefs)
	M.define("TextBox", {
		FocusLost = M.signal(),
		Focused = M.signal(),
		ReturnPressedFromOnScreenKeyboard = M.signal(),
		CaptureFocus = M.method(function(sim, real)
			sim.input:focusTextBox(real, true)
		end),
		ReleaseFocus = M.method(function(sim, real, submitted)
			sim.input:focusTextBox(real, false, submitted)
		end),
		IsFocused = M.method(function(sim, real)
			return sim.input.focused[sim.sched:context()] == real
		end),
	})

	local function contentSize(sim, layout)
		local parent = layout.Parent
		if parent == nil or not parent:IsA("GuiObject") then
			return Vector2.zero
		end
		local _, psize = absRect(sim, parent)
		local items = sortedSiblings(parent, layout)
		if layout:IsA("UIGridLayout") then
			local g = gridOf(layout, psize)
			local lines, along = math.ceil(#items / g.fit), math.min(#items, g.fit)
			local cols = if g.vertical then lines else along
			local rows = if g.vertical then along else lines
			return Vector2.new(math.max(cols * (g.cw + g.px) - g.px, 0), math.max(rows * (g.ch + g.py) - g.py, 0))
		end
		local vertical = readOr(layout, "FillDirection", Enum.FillDirection.Vertical) == Enum.FillDirection.Vertical
		local pad = readOr(layout, "Padding", roblox.UDim.new(0, 0))
		local padPx = pad.Scale * (if vertical then psize.Y else psize.X) + pad.Offset
		local along, across = 0, 0
		for i, c in items do
			local s = sizeOf(c, psize)
			along += if vertical then s.Y else s.X
			if i > 1 then
				along += padPx
			end
			across = math.max(across, if vertical then s.X else s.Y)
		end
		return if vertical then Vector2.new(across, along) else Vector2.new(along, across)
	end

	M.define("UIGridStyleLayout", {
		AbsoluteContentSize = M.prop(contentSize),
		ApplyLayout = M.method(function() end),
	})

	M.define("ScrollingFrame", {
		AbsoluteCanvasSize = M.prop(function(sim, real)
			local _, size = absRect(sim, real)
			local cs = real.CanvasSize
			return Vector2.new(cs.X.Scale * size.X + cs.X.Offset, cs.Y.Scale * size.Y + cs.Y.Offset)
		end),
		AbsoluteWindowSize = M.prop(function(sim, real)
			local _, size = absRect(sim, real)
			return size
		end),
	})

	M.absRect = absRect
end
