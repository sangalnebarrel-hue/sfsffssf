--[[
	Theme — shared look of the HUD builders (tools/builder/gui/*): colours, fonts, the hotbar
	offset and small constructors (rounded corners, outlines, text labels). Style guide:
	tools/builder/gui/STYLE.md.
]]

local U = require("../Util")

local Enum = U.Enum
local UDim = U.UDim
local rgb = U.rgb

local FONT = U.FONT
local MIN_TEXT = 12 -- never let TextScaled shrink text below this on phones
-- Pixels from the screen bottom to the fishing widgets: clears the Roblox hotbar (see Gui.luau).
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

return {
	U = U,
	C = C,
	FONT = FONT,
	MIN_TEXT = MIN_TEXT,
	HOTBAR = HOTBAR,
	corner = corner,
	stroke = stroke,
	label = label,
}
