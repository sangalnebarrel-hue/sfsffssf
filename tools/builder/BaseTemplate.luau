--[[
	Builds ServerStorage.BaseTemplate — one big player base in the bright voxel "simulator"
	style (tools/builder/DESIGN.md §1 and §2 "Base-local frame"). BaseService clones it into the
	8 slots and paints every part with attribute Accent = true in the base colour; the optional
	number attribute AccentShade (-1..1) gives lighter (> 0, towards white) or darker (< 0,
	towards black) variants, so a base is recognisable by its colour from far away.

	Base-local frame (Root at the origin, y = 0 is GroundTop; the world builder provides flat
	grass under the plot):
	  -Z     towards the lagoon. lz 0..18 is the public promenade (the template places nothing
	         there except the start of the pier), lz 0..-92 is the base's own pier over the
	         beach (sand, y = -2) and the water (y = -4).
	  +Z     inland: the plot x = -68..68, lz = 18..168.
	  +X/-X  sideways (+X is on the left of a player walking in through the gate).

	Layout (front to back):
	  lz 18        entrance gate: two pillars with lanterns, a beam, a big name board
	               (SurfaceGui with OwnerLabel / BaseLabel on both faces) and a gold fish on top
	  lz 20..50    front yard: spawn pad on an Accent ring, flag with the owner billboard, siren
	               tower (Alarm), vegetable beds (left), doghouse + guard dog (right)
	  lz 54..130   aquarium plaza, a raised Accent stage: the big central tank (Tank.Glass, a lit
	               voxel reef inside on a Neon plinth band) between two rows of six display
	               pedestals facing it (Tank.Slots.Slot_1..12;
	               odd numbers on the -X row, even on the +X row, slots 1-2 nearest the gate),
	               flower fields and big trees in the side lawns
	  lz 133..168  the owner's cottage with a porch, a duck pond (left), a campfire with a tent
	               (right)
	  lz 0..-70    plank pier with block rails and lanterns, a moored boat
	  lz -70..-92  end platform: fishing pavilion over the FishingSpot, rod rack, crates,
	               barrel, lifebuoy
	The plot is closed by low Accent walls with white caps and lantern pillars.

	Names the server code relies on (BaseService, DESIGN.md §2) — keep in sync:
	  Root, SpawnPad, FishingSpot, Tank.Glass.PromptAttachment, Alarm.Lamp, Dog (PrimaryPart),
	  Tank.Slots.Slot_N.{Pedestal.PromptAttachment, Pedestal.LabelGui.Label, Display.FishPoint}
	  (attribute SlotIndex), Flag.Pole.SignAttachment.OwnerSign.{OwnerLabel, BaseLabel},
	  Flag.Cloth (tests), Gate.Board.SignFront/SignBack.{OwnerLabel, BaseLabel}.

	Budget: <= 450 parts (8 bases at runtime). Deterministic: variation comes from a seeded
	generator, never math.random.
]]

local U = require("./Util")
local Props = require("./Props")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Color3 = U.Color3
local Enum = U.Enum
local UDim2 = U.UDim2
local rgb = U.rgb

local M = Enum.Material
local rad = math.rad

------------------------------------------------------------------------------------------
-- Palette (DESIGN.md §1) and plot numbers
------------------------------------------------------------------------------------------

local C = {
	Lawn = rgb(128, 226, 72), -- a touch brighter than the world's grass
	LawnStripe = rgb(110, 210, 60), -- mowed stripes
	Dirt = rgb(170, 116, 70),
	DirtDark = rgb(136, 90, 56),
	Sand = rgb(255, 228, 152),
	Stone = rgb(158, 166, 180),
	StoneLight = rgb(196, 202, 212),
	Wood = rgb(204, 138, 78),
	WoodDark = rgb(150, 94, 52),
	WoodLight = rgb(236, 184, 120),
	Leaf1 = Props.Colors.Leaf1, -- foliage: cooler and darker than the lawn
	Leaf2 = Props.Colors.Leaf2,
	Leaf3 = Props.Colors.Leaf3,
	Red = rgb(255, 72, 72),
	Orange = rgb(255, 148, 40),
	Yellow = rgb(255, 212, 50),
	Lime = rgb(156, 236, 60),
	Blue = rgb(64, 150, 255),
	Purple = rgb(168, 96, 255),
	Pink = rgb(255, 104, 184),
	White = rgb(252, 252, 250),
	Cream = rgb(255, 244, 220),
	Glass = rgb(150, 230, 255),
	Water = rgb(70, 196, 255),
	TankWater = rgb(225, 250, 255), -- aquarium glass: an almost clear tint, the reef keeps its colours
	TankEdge = rgb(236, 252, 255), -- the glass box's glowing top edges (Neon)
	Reef = rgb(36, 150, 232), -- aquarium backdrop: deep sea blue behind the corals
	ReefLight = rgb(140, 230, 255), -- the tank's PointLight
	-- corals: a deep base, saturated arms and a light Neon tip (they must stay vivid behind glass)
	CoralPinkBase = rgb(232, 52, 150),
	CoralPink = rgb(255, 92, 184),
	CoralPinkTip = rgb(255, 176, 226),
	CoralOrangeBase = rgb(240, 100, 20),
	CoralOrange = rgb(255, 150, 30),
	CoralOrangeTip = rgb(255, 226, 100),
	SeaFan = rgb(150, 70, 255),
	Kelp1 = rgb(30, 186, 84),
	Kelp2 = rgb(70, 218, 96),
	CastleStone = rgb(180, 148, 255),
	Bubble = rgb(205, 245, 255),
	GoldGlow = rgb(255, 222, 90),
	Gold = rgb(255, 200, 40),
	Lamp = rgb(255, 238, 170), -- neon lantern light
	Flame = rgb(255, 120, 30),
	LampOff = rgb(150, 30, 40), -- siren lens when not alarmed (stage 4 lights it up)
	Ink = rgb(34, 40, 64), -- text, eyes, door holes (small dark details only)
	Dog = rgb(240, 150, 70),
	DogCream = rgb(255, 242, 222),
	Tongue = rgb(255, 120, 150),
}

-- Accent parts get this (shaded) grey in the template; BaseService repaints them.
local ACCENT_DEFAULT = rgb(200, 200, 200)
local WHITE = Color3.new(1, 1, 1)

-- Floor layers: the world's grass is at y = 0; no two floor layers are coplanar, and thin
-- decorative slabs lying on another slab stand >= 0.15 above it (no shimmer from across the lagoon).
local LAWN = 0.2 -- plot lawn slab
local STRIPE = 0.35 -- mowed lawn stripes
local PATH = 0.5 -- paths
local STAGE = 1.0 -- aquarium stage (Accent block)
local RIM = 1.2 -- its white rim
local FIELD = 1.3 -- its light tile field
local BAND = 1.45 -- checker bands on the field
local STRIP = 1.55 -- pedestal rows
local DECK = 0.6 -- pier and platform deck top
local PLANK = 0.75 -- plank strips on the decks

------------------------------------------------------------------------------------------
-- Part helpers
------------------------------------------------------------------------------------------

local function merge(a: { [string]: any }?, b: { [string]: any }?): { [string]: any }
	local out: { [string]: any } = {}
	for _, t in { a, b } do
		if t then
			for k, v in t do
				out[k] = v
			end
		end
	end
	return out
end

-- Same rule as BaseService: shade > 0 lerps towards white, < 0 darkens in HSV.
local function shadeColor(color: any, shade: number): any
	if shade > 0 then
		return color:Lerp(WHITE, math.min(shade, 1))
	elseif shade < 0 then
		local amount = math.min(-shade, 1)
		local h, s, v = color:ToHSV()
		if h > 0.02 and h < 0.2 then
			h -= 0.04 * amount
		end
		return U.Color3.fromHSV(h, math.min(1, s * (1 + 0.15 * amount)), v * (1 - 0.6 * amount))
	end
	return color
end

local DECOR = { CanCollide = false, CastShadow = false }
local NEON = { Material = M.Neon, CastShadow = false }
local NEON_DECOR = { Material = M.Neon, CastShadow = false, CanCollide = false }

--[[
	Creates a part. `paint` is a Color3 for a plain part, or a number for an Accent part
	(the number is its AccentShade; 0 = the base colour itself). opts may hold any part
	property (Material, Transparency, CanCollide, Shape, ...) plus `wedge = true`.
	Small or thin parts never cast shadows (cheaper, and their shadows look noisy).
]]
local function make(parent: any, name: string, size: any, cf: any, paint: any, opts: { [string]: any }?): any
	local props = merge(opts, nil)
	local isWedge = props.wedge == true
	props.wedge = nil
	local color = paint
	if typeof(paint) == "number" then
		local attributes: { [string]: any } = { Accent = true }
		if paint ~= 0 then
			attributes.AccentShade = paint
		end
		props.Attributes = merge(props.Attributes, attributes)
		color = shadeColor(ACCENT_DEFAULT, paint)
	end
	if props.CastShadow == nil then
		local minSide = math.min(size.X, size.Y, size.Z)
		local maxSide = math.max(size.X, size.Y, size.Z)
		if minSide <= 0.5 or maxSide <= 2.2 then
			props.CastShadow = false
		end
	end
	local material = props.Material
	props.Material = nil
	if isWedge then
		return U.wedge(parent, name, size, cf, color, material, props)
	end
	return U.part(parent, name, size, cf, color, material, props)
end

-- Axis-aligned block from its min/max corners (template space; corners may come in any order).
local function span(
	parent: any,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	z0: number,
	z1: number,
	paint: any,
	opts: { [string]: any }?
): any
	local size = Vector3.new(math.abs(x1 - x0), math.abs(y1 - y0), math.abs(z1 - z0))
	return make(parent, name, size, CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2), paint, opts)
end

-- Block centred at (x, y, z) of a local frame; size (sx, sy, sz).
local function box(
	parent: any,
	name: string,
	frame: any,
	x: number,
	y: number,
	z: number,
	sx: number,
	sy: number,
	sz: number,
	paint: any,
	opts: { [string]: any }?
): any
	return make(parent, name, Vector3.new(sx, sy, sz), frame * CFrame.new(x, y, z), paint, opts)
end

-- Upright cylinder (axis along the frame's Y) centred at cf.
local function cylY(parent: any, name: string, d: number, h: number, cf: any, paint: any, opts: { [string]: any }?): any
	local props = merge(opts, { Shape = Enum.PartType.Cylinder })
	return make(parent, name, Vector3.new(h, d, d), cf * CFrame.Angles(0, 0, rad(90)), paint, props)
end

local function ball(parent: any, name: string, d: number, cf: any, paint: any, opts: { [string]: any }?): any
	return make(parent, name, Vector3.new(d, d, d), cf, paint, merge(opts, { Shape = Enum.PartType.Ball }))
end

local function at(x: number, y: number, z: number): any
	return CFrame.new(x, y, z)
end

-- Frame at (x, y, z) whose local -Z (front) looks along yaw degrees (0 = -Z, 90 = -X).
local function facing(x: number, y: number, z: number, yaw: number): any
	return CFrame.new(x, y, z) * CFrame.Angles(0, rad(yaw), 0)
end

-- Attachment on `part` placed at template-space CFrame `cf`; returns it and its offset
-- (reported to the post-build self-check in tools/build.luau).
local function attachAt(part: any, name: string, cf: any): (any, any)
	local rel = part.CFrame:Inverse() * cf
	local attachment = U.new("Attachment", { Name = name, CFrame = rel }, part)
	return attachment, rel.Position
end

------------------------------------------------------------------------------------------
-- Signs
------------------------------------------------------------------------------------------

local function surfaceGui(part: any, name: string, face: any, pixelsPerStud: number): any
	return U.new("SurfaceGui", {
		Name = name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = pixelsPerStud,
		LightInfluence = 0,
	}, part)
end

-- TextLabel filling a horizontal band [top, top + height] (scale) of its parent.
local function textBand(
	parent: any,
	name: string,
	text: string,
	color: any,
	top: number,
	height: number,
	stroke: boolean
): any
	return U.new("TextLabel", {
		Name = name,
		Position = UDim2.fromScale(0.04, top),
		Size = UDim2.fromScale(0.92, height),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = color,
		TextStrokeColor3 = C.Ink,
		TextStrokeTransparency = if stroke then 0 else 1,
	}, parent)
end

-- One-line text sign on a face of `part`.
local function plainText(part: any, face: any, text: string, color: any, stroke: boolean)
	local gui = surfaceGui(part, "Sign" .. face.Name, face, 40)
	textBand(gui, "Text", text, color, 0.08, 0.84, stroke)
end

------------------------------------------------------------------------------------------
-- Plot floor: lawn, paths, the aquarium stage
------------------------------------------------------------------------------------------

local function buildGrounds(template: any, plot: any)
	local floor = U.model(template, "Grounds")
	local inner = plot.halfWidth - 2.8 -- inside face of the side walls
	local front, back = plot.front + 2.8, plot.back - 2.8

	-- Lawn inside the walls, brighter than the world grass, with mowed stripes (inset from the
	-- lawn's edges, so no side faces are shared).
	span(floor, "Lawn", -inner, inner, -0.4, LAWN, front, back, C.Lawn)
	local z = front + 5
	while z + 8 <= back do
		span(floor, "LawnStripe", -inner + 0.1, inner - 0.1, LAWN - 0.1, STRIPE, z, z + 8, C.LawnStripe)
		z += 20
	end

	-- Main path: gate -> spawn -> stage steps, edged with light Accent kerbs (raised above the
	-- spawn square they cross, ending at the stage step); a pale base-colour square round the pad.
	span(floor, "Path", -10, 10, 0, PATH, plot.front, 51, C.Cream)
	for _, sx in { -1, 1 } do
		span(floor, "PathEdge", sx * 10, sx * 11.2, 0, PATH + 0.3, front + 3, 50.6, 0.45)
	end
	span(floor, "SpawnSquare", -14, 14, 0, PATH + 0.15, 24, 48, 0.8)

	-- Aquarium stage: Accent block with a white rim, light tile field, darker pedestal strips,
	-- checker bands across the aisle (every other 11-stud band, matching the slot pitch).
	span(floor, "Stage", -46, 46, 0, STAGE, 54, 130, -0.3, { CastShadow = true })
	span(floor, "StageRim", -45.2, 45.2, STAGE, RIM, 54.8, 129.2, C.White)
	span(floor, "StageField", -43.6, 43.6, RIM, FIELD, 56.4, 127.6, 0.62)
	for i = 0, 2 do
		-- 0.1 short of the 11-stud pitch at both ends (the tank plinth starts at 69.5 / ends at 113.5)
		local z0 = 58.5 + i * 22
		span(floor, "StageBand", -26, 26, FIELD - 0.06, BAND, z0 + 0.1, z0 + 10.9, 0.34)
	end
	for _, sx in { -1, 1 } do
		span(floor, "SlotStrip", sx * 26, sx * 39, FIELD - 0.1, STRIP, 57.5, 126.5, 0.3)
	end
	-- Steps up to the stage from the path (front) and from the porch (back).
	span(floor, "StageStep", -14, 14, 0, 0.75, 50.6, 54, 0.5)
	span(floor, "StageStep", -10, 10, 0, 0.75, 130, 133.4, 0.5)
end

------------------------------------------------------------------------------------------
-- Walls with lantern pillars
------------------------------------------------------------------------------------------

local function pillar(parent: any, x: number, z: number, height: number)
	span(parent, "Pillar", x - 1.9, x + 1.9, 0, height, z - 1.9, z + 1.9, -0.28)
	span(parent, "PillarTop", x - 2.4, x + 2.4, height, height + 1, z - 2.4, z + 2.4, C.White)
	span(parent, "PillarLamp", x - 1.1, x + 1.1, height + 1, height + 3, z - 1.1, z + 1.1, C.Lamp, NEON)
end

local function buildWalls(template: any, plot: any)
	local walls = U.model(template, "Walls")
	local hw, front, back = plot.halfWidth, plot.front, plot.back
	local gateHalf = 17.5 -- the gate pillars fill x = ±12..±17.5

	-- Wall segment (axis-aligned box): Accent body inset on the thin axis under a white cap
	-- over the full width (reads as an overhang).
	local function wall(x0: number, x1: number, z0: number, z1: number)
		local thinX = (x1 - x0) < (z1 - z0)
		local ix, iz = if thinX then 0.4 else 0, if thinX then 0 else 0.4
		span(walls, "Wall", x0 + ix, x1 - ix, 0, 4.2, z0 + iz, z1 - iz, 0)
		span(walls, "WallCap", x0, x1, 4.2, 5, z0, z1, C.White)
	end
	wall(-hw, -hw + 2.8, front, back) -- -X side
	wall(hw - 2.8, hw, front, back) -- +X side
	wall(-hw + 2.8, hw - 2.8, back - 2.8, back) -- back
	wall(-hw + 2.8, -gateHalf, front, front + 2.8) -- front, left of the gate
	wall(gateHalf, hw - 2.8, front, front + 2.8) -- front, right of the gate

	-- Lantern pillars: corners and side middles (the gate pillars carry the front's lanterns).
	-- Centres sit 2.4 inside the plot edge so the pillar tops never cross it.
	local e = hw - 2.4
	local zf, zb = front + 2.4, back - 2.4
	for _, p in
		{
			{ -e, zf },
			{ e, zf },
			{ -e, zb },
			{ e, zb },
			{ -e, 92 },
			{ e, 92 },
		}
	do
		pillar(walls, p[1], p[2], 7.4)
	end
end

------------------------------------------------------------------------------------------
-- Entrance gate with the owner's name board and a gold fish on top
------------------------------------------------------------------------------------------

local function signFace(board: any, face: any)
	local gui = surfaceGui(board, "Sign" .. face.Name, face, 32)
	textBand(gui, "OwnerLabel", "Свободно", C.Ink, 0.06, 0.58, false)
	textBand(gui, "BaseLabel", "База", C.White, 0.64, 0.32, true)
end

-- Big voxel fish: body along local X (head at -X), belly at y = 0 of the frame, forked tail.
local function fishStatue(parent: any, f: any, s: number, color: any, fin: any)
	local function piece(name: string, x: number, y: number, sx: number, sy: number, sz: number, paint: any, opts: any?)
		box(parent, name, f, x * s, y * s, 0, sx * s, sy * s, sz * s, paint, opts)
	end
	piece("FishBody", 0, 2.4, 9, 4.8, 2.6, color, { CastShadow = true })
	piece("FishNose", -5.3, 2.1, 1.6, 3.2, 2.2, color)
	piece("FishTailStem", 5.1, 2.4, 1.4, 2.6, 1.6, fin)
	piece("FishTail", 6.6, 4.3, 2.2, 2.8, 1.3, fin)
	piece("FishTail", 6.6, 0.5, 2.2, 2.8, 1.3, fin)
	piece("FishFin", 0.4, 5.4, 3.6, 1.6, 1.2, fin, DECOR)
	piece("FishEye", -3.4, 3.3, 1.5, 1.5, 2.8, C.White, DECOR)
	piece("FishPupil", -3.7, 3.2, 0.7, 0.8, 3, C.Ink, DECOR)
end

local function buildGate(template: any, plot: any)
	local gate = U.model(template, "Gate")
	local z0 = plot.front
	local zc = z0 + 3
	for _, sx in { -1, 1 } do
		local lo, hi = math.min(sx * 12, sx * 17.5), math.max(sx * 12, sx * 17.5)
		local xm = (lo + hi) / 2
		span(gate, "Plinth", lo - 0.5, hi + 0.5, 0, 2.4, z0, z0 + 6, C.White)
		span(gate, "Pillar", lo, hi, 2.4, 17, z0 + 0.5, z0 + 5.5, -0.22)
		span(gate, "PillarBand", lo - 0.3, hi + 0.3, 8.5, 9.7, z0 + 0.2, z0 + 5.8, C.White)
		span(gate, "Capital", lo - 0.6, hi + 0.6, 17, 18.4, z0, z0 + 6, C.White)
		local lamp = span(gate, "Lantern", xm - 1.7, xm + 1.7, 18.4, 21.8, zc - 1.7, zc + 1.7, C.Lamp, NEON)
		span(gate, "LanternCap", xm - 2.3, xm + 2.3, 21.8, 22.8, zc - 2.3, zc + 2.3, 0)
		if sx > 0 then
			U.new("PointLight", { Range = 16, Brightness = 1.2, Color = C.Lamp, Shadows = false }, lamp)
		end
	end
	-- Beam across the opening (clearance 12.4 studs) and the big name board above it.
	span(gate, "Beam", -12, 12, 13, 15.6, z0 + 1, z0 + 5, -0.12)
	span(gate, "BeamTrim", -12, 12, 12.4, 13, z0 + 0.8, z0 + 5.2, C.White)
	span(gate, "BoardFrame", -16, 16, 15.6, 26.6, zc - 0.9, zc + 0.9, 0, { CastShadow = true })
	local board = span(gate, "Board", -14.8, 14.8, 16.6, 25.6, zc - 1.1, zc + 1.1, C.White)
	signFace(board, Enum.NormalId.Front) -- faces the promenade
	signFace(board, Enum.NormalId.Back) -- faces the yard
	-- The base's mascot: a jumping gold fish on top of the board.
	fishStatue(gate, at(0, 26.3, zc) * CFrame.Angles(0, 0, rad(-10)), 1.2, C.Gold, C.Orange)
end

------------------------------------------------------------------------------------------
-- Front yard: spawn pad, flag, siren tower, mailbox, lamp posts
------------------------------------------------------------------------------------------

local SPAWN_Z = 36

local function buildSpawn(template: any)
	local yard = U.model(template, "SpawnArea")
	-- A glowing ring in a light shade of the base colour frames the pad.
	span(yard, "SpawnRing", -6.6, 6.6, PATH, 1.0, SPAWN_Z - 6.6, SPAWN_Z + 6.6, 0.35, NEON)
	-- The pad: -Z (the lagoon) is the facing on spawn. Pure base colour (tests check it).
	span(template, "SpawnPad", -5, 5, 1.0, 1.4, SPAWN_Z - 5, SPAWN_Z + 5, 0, { CastShadow = false })
end

-- Flag pole with the base-colour flag and the owner billboard above it.
local function buildFlag(template: any): any
	local flag = U.model(template, "Flag")
	local fx, fz = -24, 32
	span(flag, "Plinth", fx - 3, fx + 3, 0, 1.6, fz - 3, fz + 3, C.StoneLight)
	span(flag, "PlinthTop", fx - 2, fx + 2, 1.6, 2.6, fz - 2, fz + 2, -0.25)
	local poleBottom, poleTop = 2.6, 27
	local poleH = poleTop - poleBottom
	local pole = cylY(flag, "Pole", 0.9, poleH, at(fx, (poleTop + poleBottom) / 2, fz), C.White)
	ball(flag, "Top", 1.8, at(fx, poleTop + 0.6, fz), C.Gold, DECOR)
	-- The flag flies towards +X (over the path): main cloth + a slightly darker tail.
	local clothTop = poleTop - 0.6
	make(flag, "Cloth", Vector3.new(7, 5, 0.4), at(fx + 0.45 + 3.5, clothTop - 2.5, fz), 0, { CanCollide = false })
	make(
		flag,
		"ClothTip",
		Vector3.new(3, 4.2, 0.4),
		at(fx + 7.45 + 1.4, clothTop - 2.6, fz) * CFrame.Angles(0, rad(-12), 0),
		-0.18,
		{ CanCollide = false }
	)

	-- Owner sign above the flag (BaseService writes the owner name / base name).
	-- The pole is a cylinder (local X = up), so the offset is along local X.
	local signOffset = Vector3.new(poleH / 2 + 4.5, 0, 0)
	local attachment = U.new("Attachment", { Name = "SignAttachment", CFrame = CFrame.new(signOffset) }, pole)
	local sign = U.new("BillboardGui", {
		Name = "OwnerSign",
		Size = UDim2.new(16, 0, 5, 0), -- studs
		LightInfluence = 0,
		MaxDistance = 250,
		AlwaysOnTop = false,
	}, attachment)
	for _, spec in { { "OwnerLabel", "Свободно", 0, 0.6 }, { "BaseLabel", "База", 0.6, 0.4 } } do
		U.new("TextLabel", {
			Name = spec[1],
			Position = UDim2.fromScale(0, spec[3]),
			Size = UDim2.fromScale(1, spec[4]),
			BackgroundTransparency = 1,
			Text = spec[2],
			TextScaled = true,
			FontFace = U.FONT,
			TextColor3 = C.White,
			TextStrokeColor3 = C.Ink,
			TextStrokeTransparency = 0.2,
		}, sign)
	end
	return signOffset
end

-- Siren tower: striped column, platform, the alarm lamp (Alarm.Lamp) under an Accent cap.
local function buildAlarm(template: any)
	local alarm = U.model(template, "Alarm")
	local ax, az = 24, 32
	span(alarm, "Base", ax - 3, ax + 3, 0, 1.6, az - 3, az + 3, C.StoneLight)
	span(alarm, "Column", ax - 1.6, ax + 1.6, 1.6, 14.4, az - 1.6, az + 1.6, -0.2)
	span(alarm, "Stripe", ax - 1.9, ax + 1.9, 7.2, 8.8, az - 1.9, az + 1.9, C.White)
	span(alarm, "Platform", ax - 3, ax + 3, 14.4, 15.4, az - 3, az + 3, C.White)
	span(alarm, "Lamp", ax - 2, ax + 2, 15.4, 18.4, az - 2, az + 2, C.LampOff, { CastShadow = false })
	span(alarm, "Cap", ax - 2.8, ax + 2.8, 18.4, 19.4, az - 2.8, az + 2.8, 0)
	-- Two loudspeaker horns on the platform.
	for _, sx in { -1, 1 } do
		span(alarm, "Horn", ax + sx * 1.95, ax + sx * 3.5, 15.4, 17.0, az - 0.8, az + 0.8, C.White, DECOR)
	end
end

local function lampPost(parent: any, x: number, z: number, base: number)
	span(parent, "LampPost", x - 0.5, x + 0.5, base, base + 8, z - 0.5, z + 0.5, C.White)
	span(parent, "LampGlow", x - 1, x + 1, base + 8, base + 10, z - 1, z + 1, C.Lamp, NEON_DECOR)
	span(parent, "LampCap", x - 1.3, x + 1.3, base + 10, base + 10.7, z - 1.3, z + 1.3, 0, DECOR)
end

local function buildYardDecor(template: any)
	local yard = U.model(template, "YardDecor")
	-- Mailbox next to the gate.
	span(yard, "MailPost", 14.6, 15.4, LAWN - 0.1, 3.6, 25.6, 26.4, C.Wood)
	span(yard, "Mailbox", 13.9, 16.1, 3.6, 5.4, 24.6, 27.4, 0)
	-- Lamp posts flanking the steps up to the aquarium stage.
	for _, sx in { -1, 1 } do
		lampPost(yard, sx * 16.5, 51.5, LAWN)
	end
end

------------------------------------------------------------------------------------------
-- Aquarium: the big tank and the 12 display pedestals
------------------------------------------------------------------------------------------

local TANK_HALF_X = 12
local TANK_Z0, TANK_Z1 = 71.5, 111.5
local TANK_BASE = FIELD + 1.7 -- plinth top = glass bottom
local TANK_TOP = TANK_BASE + 11
local SLOT_ROW_X = 32
local SLOT_Z0, SLOT_PITCH = 64, 11

local function buildTank(template: any): (any, { any })
	local tank = U.model(template, "Tank")
	local hx = TANK_HALF_X
	local expected = {}

	-- Plinth: dark Accent step, a glowing Neon band in the base colour (like the slot plates).
	span(tank, "Plinth", -hx - 2, hx + 2, FIELD - 0.1, TANK_BASE - 0.6, TANK_Z0 - 2, TANK_Z1 + 2, -0.35)
	span(tank, "PlinthTrim", -hx - 1.2, hx + 1.2, TANK_BASE - 0.6, TANK_BASE, TANK_Z0 - 1.2, TANK_Z1 + 1.2, 0.35, NEON)

	-- The glass (one part = the whole water volume; fish swim inside it later): almost clear, so
	-- the reef keeps its colours from across the plaza.
	local glass = span(tank, "Glass", -hx, hx, TANK_BASE, TANK_TOP, TANK_Z0, TANK_Z1, C.TankWater, {
		Material = M.Glass,
		Transparency = 0.75,
		CastShadow = false,
	})
	tank.PrimaryPart = glass
	-- Stage 3/4 prompts: in front of the tank's entrance end (towards the gate).
	local _, promptOffset = attachAt(glass, "PromptAttachment", at(0, FIELD + 3, TANK_Z0 - 3))
	table.insert(expected, { root = "template", path = { "Tank", "Glass", "PromptAttachment" }, offset = promptOffset })

	-- Inside: a sand bed and a deep-blue backdrop wall along the middle, so each long side reads as
	-- a lit reef aquarium (also when no fish are on display). The entrance end, seen from the
	-- spawn, is the show window: a lilac castle in the middle (it hides the backdrop's end), an
	-- open treasure chest with glowing gold and an orange coral either side of it and a yellow fish
	-- swimming across above them. Along the sides: chunky branching corals with glowing Neon tips,
	-- wavy kelp, rising Neon bubbles, voxel fish, a purple sea fan and a yellow brain coral. A cyan
	-- PointLight on the backdrop lights it all.
	local s = TANK_BASE + 1.2 -- sand top
	span(tank, "Sand", -hx + 0.2, hx - 0.2, TANK_BASE, s, TANK_Z0 + 0.2, TANK_Z1 - 0.2, C.Sand, DECOR)
	local backdrop = span(tank, "Backdrop", -0.3, 0.3, s - 0.2, TANK_TOP - 0.6, 78.4, TANK_Z1 - 4, C.Reef, DECOR)
	U.new("PointLight", { Range = 16, Brightness = 1.2, Color = C.ReefLight, Shadows = false }, backdrop)
	local function piece(
		name: string,
		x0: number,
		x1: number,
		y0: number,
		y1: number,
		z0: number,
		z1: number,
		paint: any
	)
		span(tank, name, x0, x1, s + y0, s + y1, z0, z1, paint, DECOR)
	end
	local function glow(
		name: string,
		x0: number,
		x1: number,
		y0: number,
		y1: number,
		z0: number,
		z1: number,
		paint: any
	)
		span(tank, name, x0, x1, s + y0, s + y1, z0, z1, paint, NEON_DECOR)
	end
	-- Branching coral: a fat deep-coloured base (w x 0.9w), a tall and a short arm in a saturated
	-- shade, a Neon tip on the tall arm. (x, z) = the base's -X/-Z corner; flip puts the tall arm
	-- on the +X side.
	local function coral(x: number, z: number, w: number, high: number, base: any, arm: any, tip: any, flip: boolean)
		local d = w * 0.9
		local a = if flip then w - 2.3 else 0.3 -- tall arm (2 wide)
		local b = if flip then 0.4 else w - 2.0 -- short arm (1.6 wide)
		piece("Coral", x, x + w, -0.2, 2.6, z, z + d, base)
		piece("CoralArm", x + a, x + a + 2, 2.6, high, z + 0.8, z + 2.8, arm)
		piece("CoralArm", x + b, x + b + 1.6, 2.6, high - 2.6, z + d - 2, z + d - 0.4, arm)
		glow("CoralTip", x + a - 0.5, x + a + 2.5, high, high + 1.2, z + 0.3, z + 3.3, tip)
	end
	-- Wavy kelp: three stacked blocks shifted back and forth, nearly up to the water line.
	local function kelp(x: number, z: number, dx: number)
		piece("Kelp", x, x + 1.6, -0.2, 3.4, z, z + 1.6, C.Kelp1)
		piece("Kelp", x + dx, x + dx + 1.6, 3.2, 6.4, z + 0.4, z + 2, C.Kelp2)
		piece("Kelp", x - dx * 0.5, x - dx * 0.5 + 1.6, 6.2, 9.2, z - 0.2, z + 1.4, C.Lime)
	end
	-- Voxel fish: body, a tall tail fin behind it and an eye block straight through the head (an
	-- eye on both sides). Swims along Z (dir = +1 towards +Z, -1 towards -Z), or along X with
	-- acrossX (dir = +1 towards +X), showing its side to the spawn.
	local function fish(x: number, y: number, z: number, dir: number, body: any, tail: any, acrossX: boolean?)
		if acrossX then
			piece("Fish", x - 1.6, x + 1.6, y - 1, y + 1, z - 1.1, z + 1.1, body)
			local tx, ex = x - dir * 2.3, x + dir * 0.9
			piece("FishTail", tx - 0.7, tx + 0.7, y - 1.2, y + 1.2, z - 0.25, z + 0.25, tail)
			piece("FishEye", ex - 0.3, ex + 0.3, y + 0.15, y + 0.75, z - 1.25, z + 1.25, C.Ink)
		else
			piece("Fish", x - 1.1, x + 1.1, y - 1, y + 1, z - 1.6, z + 1.6, body)
			local tz, ez = z - dir * 2.3, z + dir * 0.9
			piece("FishTail", x - 0.25, x + 0.25, y - 1.2, y + 1.2, tz - 0.7, tz + 0.7, tail)
			piece("FishEye", x - 1.25, x + 1.25, y + 0.15, y + 0.75, ez - 0.3, ez + 0.3, C.Ink)
		end
	end
	local function bubbles(x: number, z: number, list: { { number } })
		for _, bub in list do
			ball(tank, "Bubble", bub[2], at(x, s + bub[1], z), C.Bubble, NEON_DECOR)
		end
	end

	-- The entrance end: the castle (stepped roof, a dark door towards the spawn), the open
	-- treasure chest (-X), an orange coral (+X) and a yellow tang swimming across above the chest.
	piece("Castle", -3, 3, -0.2, 6.6, 73.4, 78.8, C.CastleStone)
	piece("CastleRoof", -3.6, 3.6, 6.6, 7.8, 72.9, 79.3, C.Red)
	piece("CastleRoof", -2.2, 2.2, 7.8, 9, 74, 78.2, C.Pink)
	piece("CastleDoor", -1, 1, 0, 3.2, 73.2, 73.4, C.Ink)
	piece("Chest", -10.4, -5.8, -0.2, 2.6, 73.2, 76.8, C.Wood)
	piece("ChestLid", -10.6, -5.6, 2.6, 6, 76.6, 77.4, C.Gold) -- open, standing at the back
	glow("ChestGold", -10, -6.2, 2.4, 3.4, 73.6, 76.4, C.GoldGlow)
	coral(5.8, 73.2, 5, 7.6, C.CoralOrangeBase, C.CoralOrange, C.CoralOrangeTip, true)
	fish(-6.4, 8.2, 80.5, 1, C.Yellow, C.Blue, true)
	-- -X side (seen from the odd slot row): pink coral, bubbles, kelp, clownfish, purple sea fan.
	coral(-10.6, 83, 5, 8.4, C.CoralPinkBase, C.CoralPink, C.CoralPinkTip, false)
	bubbles(-3.2, 88.5, { { 2.6, 1 }, { 5.4, 1.3 }, { 8.2, 1.6 } })
	kelp(-4.6, 93, 0.4)
	fish(-7, 7.2, 97, -1, C.Orange, C.White)
	piece("SeaFan", -9, -8.2, -0.2, 7.4, 101, 108.5, C.SeaFan)
	-- +X side (seen from the even slot row): kelp, blue tang, bubbles, yellow brain coral.
	kelp(2.6, 81.5, -0.4)
	fish(6.6, 8, 90, 1, C.Blue, C.Yellow)
	bubbles(3, 99, { { 3, 1.1 }, { 5.8, 1.4 }, { 8.4, 1.6 } })
	piece("BrainCoral", 5.6, 10.4, -0.2, 2.8, 103.5, 108.5, C.Yellow)

	-- Chunky Accent corner posts (the long sides stay open for the view) and glowing white top
	-- edges, so the clear glass still reads as a glass box.
	local postTop = TANK_TOP + 1
	for _, sx in { -1, 1 } do
		for _, z in { TANK_Z0, TANK_Z1 } do
			span(tank, "Post", sx * hx - 0.9, sx * hx + 0.9, TANK_BASE, postTop, z - 0.9, z + 0.9, 0)
		end
		span(tank, "Rim", sx * hx - 0.5, sx * hx + 0.5, TANK_TOP, TANK_TOP + 0.6, TANK_Z0, TANK_Z1, C.TankEdge, NEON)
	end
	for _, z in { TANK_Z0, TANK_Z1 } do
		span(tank, "Rim", -hx + 0.5, hx - 0.5, TANK_TOP, TANK_TOP + 0.6, z - 0.5, z + 0.5, C.TankEdge, NEON)
	end

	-- Name board standing on the rim of the entrance end.
	local signY = TANK_TOP + 0.6
	span(tank, "SignFrame", -8, 8, signY, signY + 4.8, TANK_Z0 - 0.6, TANK_Z0 + 0.6, -0.2)
	local board = span(tank, "SignBoard", -7.2, 7.2, signY + 0.6, signY + 4.2, TANK_Z0 - 0.8, TANK_Z0 + 0.8, C.White)
	plainText(board, Enum.NormalId.Front, "АКВАРИУМ", C.Ink, false)

	return tank, expected
end

-- One display pedestal (Steal-a-Brainrot podium style). Local frame: -Z faces the aisle.
local function buildSlot(slots: any, index: number, frame: any, expected: { any })
	local slot = U.model(slots, `Slot_{index}`)
	slot:SetAttribute("SlotIndex", index)
	local y0 = STRIP
	box(slot, "Step", frame, 0, y0 + 0.5, 0, 9, 1, 9, -0.35)
	local pedestal = box(slot, "Pedestal", frame, 0, y0 + 2.6, 0, 7, 3.2, 7, C.White, { CastShadow = true })
	-- Glowing plate in the base colour under the glass case.
	box(slot, "Plate", frame, 0, y0 + 4.6, 0, 8.2, 0.8, 8.2, 0.1, NEON)
	local display = box(slot, "Display", frame, 0, y0 + 8.1, 0, 6.2, 6.2, 6.2, C.Glass, {
		Material = M.Glass,
		Transparency = 0.6,
		CastShadow = false,
	})
	box(slot, "Cap", frame, 0, y0 + 11.6, 0, 7.2, 0.8, 7.2, -0.05)
	slot.PrimaryPart = pedestal

	-- The fish model floats in the centre of the display; prompts stand in front of the pedestal.
	local fishPoint = U.new("Attachment", { Name = "FishPoint", CFrame = CFrame.new() }, display)
	local _, promptOffset = attachAt(pedestal, "PromptAttachment", frame * at(0, y0 + 2.6, -5))
	local name = slot.Name
	table.insert(expected, {
		root = "template",
		path = { "Tank", "Slots", name, "Display", "FishPoint" },
		offset = fishPoint.CFrame.Position,
	})
	table.insert(expected, {
		root = "template",
		path = { "Tank", "Slots", name, "Pedestal", "PromptAttachment" },
		offset = promptOffset,
	})

	-- Label on the front face: "Пусто" until a fish is put on display.
	local gui = surfaceGui(pedestal, "LabelGui", Enum.NormalId.Front, 50)
	U.new("TextLabel", {
		Name = "Label",
		Position = UDim2.fromScale(0.06, 0.12),
		Size = UDim2.fromScale(0.88, 0.76),
		BackgroundTransparency = 1,
		Text = "Пусто",
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = C.Ink,
	}, gui)
	-- Slot number on the pedestal's back face (seen from behind the row).
	plainText(pedestal, Enum.NormalId.Back, tostring(index), C.Ink, false)
end

local function buildSlots(tank: any, expected: { any })
	local slots = U.folder(tank, "Slots")
	for k = 1, 6 do
		local z = SLOT_Z0 + (k - 1) * SLOT_PITCH
		-- Odd slots on the -X row (front faces +X), even on the +X row (front faces -X).
		buildSlot(slots, 2 * k - 1, facing(-SLOT_ROW_X, 0, z, -90), expected)
		buildSlot(slots, 2 * k, facing(SLOT_ROW_X, 0, z, 90), expected)
	end
end

------------------------------------------------------------------------------------------
-- Doghouse + guard dog
------------------------------------------------------------------------------------------

local function buildDogHouse(template: any)
	local house = U.model(template, "DogHouse")
	local f = facing(48, LAWN, 42, 90) -- the door looks towards -X (the main path)
	box(house, "Floor", f, 0, 0.3, 0, 7.6, 0.6, 7.6, C.WoodDark)
	box(house, "Walls", f, 0, 0.6 + 2.3, 0, 6.4, 4.6, 6.4, C.Wood)
	box(house, "DoorHole", f, 0, 0.6 + 1.6, -3.25, 2.6, 3.2, 0.2, C.Ink, DECOR)
	-- Stepped gable roof, ridge along the door axis.
	box(house, "Roof", f, 0, 5.7, 0, 8, 1, 8, -0.3)
	box(house, "Roof", f, 0, 6.8, 0, 5.6, 1.2, 8, 0)
	box(house, "Roof", f, 0, 8, 0, 3.2, 1.2, 8, 0.2)
	local plate = box(house, "NamePlate", f, 0, 4.6, -3.35, 3.4, 1.1, 0.3, C.White, DECOR)
	plainText(plate, Enum.NormalId.Front, "ГАВ!", C.Ink, false)
	-- A food bowl.
	cylY(house, "Bowl", 1.9, 0.7, f * at(2.8, 0.35, -5), 0, DECOR)
end

-- Cute blocky shiba guarding the entrance; local -Z = where it looks.
local function buildDog(template: any)
	local dog = U.model(template, "Dog")
	local S = 1.6
	local f = facing(38, LAWN, 37, 45) -- looks towards the gate (-X/-Z)
	local function piece(
		name: string,
		x: number,
		y: number,
		z: number,
		sx: number,
		sy: number,
		sz: number,
		color: any,
		opts: any?
	): any
		return box(
			dog,
			name,
			f,
			x * S,
			y * S,
			z * S,
			sx * S,
			sy * S,
			sz * S,
			color,
			merge({ CanCollide = false }, opts)
		)
	end
	local body = piece("Body", 0, 1.35, 0.2, 1.6, 1.3, 2.4, C.Dog, { CastShadow = true })
	piece("Chest", 0, 1.25, -1.05, 1.2, 0.9, 0.3, C.DogCream)
	piece("Head", 0, 2.5, -1.1, 1.9, 1.6, 1.6, C.Dog, { CastShadow = true })
	piece("Muzzle", 0, 2.15, -2.1, 1.1, 0.65, 0.6, C.DogCream)
	piece("Nose", 0, 2.42, -2.45, 0.4, 0.28, 0.2, C.Ink)
	piece("Tongue", 0.15, 1.78, -2.38, 0.3, 0.32, 0.12, C.Tongue)
	for _, sx in { -1, 1 } do
		piece("Eye", sx * 0.46, 2.78, -1.93, 0.26, 0.36, 0.1, C.Ink)
		piece("Ear", sx * 0.6, 3.55, -1.05, 0.5, 0.62, 0.42, C.Dog)
		piece("FrontLeg", sx * 0.45, 0.4, -0.65, 0.5, 0.8, 0.5, C.DogCream)
		piece("BackLeg", sx * 0.45, 0.4, 1.0, 0.5, 0.8, 0.5, C.Dog)
	end
	piece("Tail", 0, 2.1, 1.5, 0.5, 0.7, 0.5, C.Dog)
	piece("TailTip", 0, 2.55, 1.25, 0.62, 0.5, 0.62, C.DogCream)
	piece("Collar", 0, 1.95, -0.8, 1.75, 0.36, 1.2, 0)
	dog.PrimaryPart = body
end

------------------------------------------------------------------------------------------
-- Owner's cottage
------------------------------------------------------------------------------------------

local function buildHouse(template: any)
	local house = U.model(template, "House")
	local x0, x1, z0, z1 = -20, 20, 140, 162
	local base = 1.2 -- floor level (on the foundation)
	local wallTop = base + 12

	span(house, "Foundation", x0 - 1, x1 + 1, 0, base, z0 - 1, z1 + 1, C.StoneLight)
	span(house, "Walls", x0, x1, base, wallTop, z0, z1, C.Cream)
	span(house, "Band", x0 - 0.3, x1 + 0.3, base + 6.2, base + 7.2, z0 - 0.3, z1 + 0.3, C.Wood)
	for _, x in { x0, x1 } do
		for _, z in { z0, z1 } do
			span(house, "Corner", x - 0.9, x + 0.9, base, wallTop, z - 0.9, z + 0.9, C.Wood)
		end
	end

	-- Stepped gable roof (ridge along X); shades alternate for the voxel look.
	local roofY = wallTop
	local depth = (z1 - z0) + 6
	local zc = (z0 + z1) / 2
	for i, shade in { -0.38, 0, -0.12, 0.08, -0.05, 0.2 } do
		local d = depth - (i - 1) * 4.4
		local h = if i == 1 then 1.4 else 2.2
		span(house, "Roof", x0 - 2.6, x1 + 2.6, roofY, roofY + h, zc - d / 2, zc + d / 2, shade, { CastShadow = true })
		roofY += h
	end
	span(house, "Ridge", x0 - 3, x1 + 3, roofY, roofY + 0.9, zc - 1.2, zc + 1.2, C.White)

	-- Dormer with a window on the front slope (above the porch awning); its top sinks 0.1 into its
	-- roof so it never shares the plane of the roof step below.
	local dy0 = wallTop + 1.4
	span(house, "Dormer", -5, 5, dy0, dy0 + 6.7, z0 - 0.2, z0 + 7, C.Cream)
	span(house, "DormerWindow", -3, 3, dy0 + 1.2, dy0 + 5.4, z0 - 0.6, z0, C.Glass, {
		Material = M.Glass,
		Transparency = 0.25,
	})
	span(house, "DormerRoof", -6.4, 6.4, dy0 + 6.6, dy0 + 7.8, z0 - 1.2, z0 + 7.6, -0.3, { CastShadow = true })
	span(house, "DormerRoof", -4.2, 4.2, dy0 + 7.8, dy0 + 9, z0 - 0.6, z0 + 7.6, 0.12)

	-- Chimney through the back slope.
	span(house, "Chimney", 9, 13, wallTop + 2, wallTop + 15.5, zc + 3, zc + 7, C.StoneLight)
	span(house, "ChimneyCap", 8.4, 13.6, wallTop + 15.5, wallTop + 16.7, zc + 2.4, zc + 7.6, C.Stone)

	-- Front (-Z): door with a frame, two windows with flower boxes.
	span(house, "DoorFrame", -3.8, 3.8, base, base + 9.2, z0 - 0.4, z0, C.Wood)
	span(house, "Door", -2.8, 2.8, base, base + 8.2, z0 - 0.6, z0 - 0.2, -0.25)
	for _, sx in { -1, 1 } do
		local x = sx * 11
		span(house, "WindowFrame", x - 3.6, x + 3.6, base + 3.2, base + 10, z0 - 0.4, z0, C.Wood)
		span(house, "Window", x - 2.8, x + 2.8, base + 4, base + 9.2, z0 - 0.6, z0 - 0.2, C.Glass, {
			Material = M.Glass,
			Transparency = 0.25,
		})
		span(house, "FlowerBox", x - 3.8, x + 3.8, base + 2, base + 3.2, z0 - 1.6, z0, 0)
		local bloom = if sx < 0 then C.Pink else C.Yellow
		span(house, "Flowers", x - 3.4, x + 3.4, base + 3.2, base + 4, z0 - 1.4, z0 - 0.3, bloom, DECOR)
	end
	-- One window on each side wall.
	for _, sx in { -1, 1 } do
		local x = sx * (x1 + 0.2)
		span(house, "WindowFrame", x - 0.4, x + 0.4, base + 3.2, base + 10, zc - 3.6, zc + 3.6, C.Wood)
		span(house, "Window", x - 0.6, x + 0.6, base + 4, base + 9.2, zc - 2.8, zc + 2.8, C.Glass, {
			Material = M.Glass,
			Transparency = 0.25,
		})
	end

	-- Porch: deck (ends at the foundation's edge: no shared top face), two posts with lanterns,
	-- Accent awning.
	local pz0 = 133.4
	span(house, "Porch", -9, 9, 0, base, pz0, z0 - 1, C.WoodLight)
	for _, sx in { -1, 1 } do
		local x = sx * 8
		span(house, "PorchPost", x - 0.6, x + 0.6, base, base + 9.4, pz0 + 0.4, pz0 + 1.6, C.Wood)
		local lamp =
			span(house, "PorchLamp", x - 0.8, x + 0.8, base + 6.4, base + 8, pz0 - 0.4, pz0 + 0.4, C.Lamp, NEON_DECOR)
		if sx > 0 then
			U.new("PointLight", { Range = 14, Brightness = 1.1, Color = C.Lamp, Shadows = false }, lamp)
		end
	end
	span(house, "Awning", -10, 10, base + 9.4, base + 10.4, pz0 - 0.6, z0, -0.3, { CastShadow = true })
	span(house, "AwningTop", -9.4, 9.4, base + 10.4, base + 11.2, pz0 + 0.4, z0, 0.15)
end

------------------------------------------------------------------------------------------
-- Vegetable beds, pond, campfire, flower fields, trees, bushes
------------------------------------------------------------------------------------------

-- Raised vegetable beds (Grow-a-Garden style) in the front-left yard.
local function buildGarden(template: any)
	local garden = U.model(template, "Garden")
	local beds = {
		{ x = -56, crop = "Pumpkin", color = C.Orange, size = 3.6 },
		{ x = -45, crop = "Cabbage", color = C.Lime, size = 3.4 },
		{ x = -34, crop = "Strawberry", color = C.Red, size = 2.6 },
	}
	local z0, z1 = 25, 49
	for _, bed in beds do
		local x, s = bed.x, bed.size
		span(garden, "BedFrame", x - 4, x + 4, 0, 1.4, z0, z1, C.Wood)
		span(garden, "Soil", x - 3.2, x + 3.2, 1.4, 1.6, z0 + 0.8, z1 - 0.8, C.DirtDark, { CanCollide = false })
		for i = 0, 2 do
			local z = z0 + 4.6 + i * 7.4
			local crop = { CanCollide = false, CastShadow = true }
			span(garden, bed.crop, x - s / 2, x + s / 2, 1.4, 1.4 + s * 0.8, z - s / 2, z + s / 2, bed.color, crop)
		end
	end
	span(garden, "SignPost", -45.4, -44.6, 0, 5, z1 + 1.6, z1 + 2.4, C.Wood)
	local board = span(garden, "SignBoard", -49, -41, 4.4, 7.4, z1 + 1.4, z1 + 2.6, C.WoodLight)
	plainText(board, Enum.NormalId.Front, "ОГОРОД", C.Ink, false)
end

local function buildPond(template: any)
	local pond = U.model(template, "Pond")
	local px, pz = -46, 146
	span(pond, "PondRim", px - 11, px + 11, 0, 1.0, pz - 8, pz + 8, C.StoneLight)
	span(pond, "PondWater", px - 9.6, px + 9.6, 0.2, 1.2, pz - 6.6, pz + 6.6, C.Water, { CanCollide = false })
	span(pond, "LilyPad", px - 6, px - 3.6, 1.2, 1.4, pz - 3, pz - 0.6, C.Leaf2, DECOR)
	span(pond, "LilyPad", px + 3, px + 5.4, 1.2, 1.4, pz + 2, pz + 4.4, C.Leaf2, DECOR)
	span(pond, "LilyFlower", px + 3.8, px + 4.6, 1.4, 2.0, pz + 2.8, pz + 3.6, C.Pink, DECOR)
	-- A rubber-duck-like duck.
	local d = facing(px + 1, 1.2, pz - 2, 140)
	box(pond, "DuckBody", d, 0, 0.6, 0, 1.6, 1.2, 2.2, C.Yellow, DECOR)
	box(pond, "DuckHead", d, 0, 1.7, -0.7, 1.1, 1.1, 1.1, C.Yellow, DECOR)
	box(pond, "DuckBeak", d, 0, 1.55, -1.45, 0.7, 0.35, 0.5, C.Orange, DECOR)
	-- Chunky bench facing the pond.
	span(pond, "BenchSeat", px - 4, px + 4, LAWN, 2.2, pz + 9.6, pz + 11.6, C.WoodLight)
	span(pond, "BenchBack", px - 4, px + 4, 2.2, 4.4, pz + 11.2, pz + 11.8, -0.3)
end

-- Campfire with log seats and a tent; returns the sparks attachment offset.
local function buildCampfire(template: any): any
	local camp = U.model(template, "Campfire")
	local fx, fz = 44, 146
	-- (the sand patch stands 0.15 above the mowed stripes it covers: no shimmer from the hills)
	span(camp, "Patch", fx - 9, fx + 9, 0, STRIPE + 0.15, fz - 9, fz + 9, C.Sand)
	span(camp, "FirePit", fx - 2.6, fx + 2.6, 0.3, 1.1, fz - 2.6, fz + 2.6, C.StoneLight)
	local spin = CFrame.Angles(0, rad(45), 0)
	local logs = make(camp, "Logs", Vector3.new(3.6, 0.8, 1), at(fx, 1.4, fz) * spin, C.WoodDark, DECOR)
	local flame = make(camp, "Flame", Vector3.new(1.8, 1.8, 1.8), at(fx, 2.6, fz) * spin, C.Flame, NEON_DECOR)
	make(camp, "FlameTip", Vector3.new(1, 1.2, 1), at(fx, 3.9, fz) * CFrame.Angles(0, rad(20), 0), C.Yellow, NEON_DECOR)
	U.new("PointLight", { Range = 14, Brightness = 1.4, Color = C.Flame, Shadows = false }, flame)
	local sparks, sparksOffset = attachAt(logs, "SparksAttachment", at(fx, 3.4, fz))
	local R = U.roblox
	U.new("ParticleEmitter", {
		Name = "Sparks",
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Rate = 5,
		Lifetime = R.NumberRange.new(0.8, 1.6),
		Speed = R.NumberRange.new(3, 6),
		SpreadAngle = U.Vector2.new(14, 14),
		Acceleration = Vector3.new(0, 1.5, 0),
		Drag = 1,
		Size = R.NumberSequence.new({ R.NumberSequenceKeypoint.new(0, 0.35), R.NumberSequenceKeypoint.new(1, 0) }),
		Color = R.ColorSequence.new(rgb(255, 214, 96), C.Flame),
		LightEmission = 1,
	}, sparks)
	-- Log seats on three sides.
	span(camp, "LogSeat", fx - 3.5, fx + 3.5, 0.3, 1.9, fz - 6.6, fz - 5, C.Wood)
	span(camp, "LogSeat", fx - 6.6, fx - 5, 0.3, 1.9, fz - 3.5, fz + 3.5, C.Wood)
	span(camp, "LogSeat", fx + 5, fx + 6.6, 0.3, 1.9, fz - 3.5, fz + 3.5, C.Wood)
	-- A-frame tent behind the fire: two Accent wedges back to back (their upright backs meet at
	-- the ridge, so no faces overlap), a dark doorway towards the fire.
	local t = facing(fx, 0.15, fz + 10, 0)
	local tent = Vector3.new(6, 5.4, 3.6)
	make(
		camp,
		"Tent",
		tent,
		t * at(-1.8, 2.7, 0) * CFrame.Angles(0, rad(90), 0),
		0,
		{ wedge = true, CastShadow = true }
	)
	make(camp, "Tent", tent, t * at(1.8, 2.7, 0) * CFrame.Angles(0, rad(-90), 0), 0.25, { wedge = true })
	box(camp, "TentDoor", t, 0, 1.75, -3.05, 1.6, 2.8, 0.3, C.Ink, DECOR)
	return sparksOffset
end

-- Tulip field in a dirt bed: three wide rows of colour running along Z.
local function flowerField(parent: any, x0: number, z0: number, z1: number, seed: number)
	local colors = { C.Red, C.Yellow, C.Pink, C.Purple, C.Orange }
	span(parent, "FieldBed", x0, x0 + 13, 0, 1.0, z0, z1, C.Dirt)
	for i = 0, 2 do
		local x = x0 + 0.9 + i * 4
		local color = colors[(seed + i) % #colors + 1]
		span(parent, "Tulips", x, x + 3.2, 1.0, 2.4, z0 + 1, z1 - 1, color, DECOR)
	end
end

-- Voxel tree from the prop library (the same layered dark / mid / light canopy as the map's
-- trees, "lite + compact": 6 parts, + 3 with fruit), standing on the lawn.
local function tree(parent: any, x: number, z: number, s: number, seed: number, palette: string, fruit: any?)
	Props.roundTree(parent, at(x, LAWN, z), {
		seed = seed,
		scale = s,
		lite = true,
		compact = true,
		palette = palette,
		fruit = fruit,
		name = "Tree",
	})
end

-- Flowering shrub: a leaf block with a crown of blooms (`bloom`) on top.
local function bush(parent: any, x: number, z: number, s: number, bloom: any)
	span(parent, "Bush", x - 2.6 * s, x + 2.6 * s, LAWN - 0.1, LAWN + 3 * s, z - 2.2 * s, z + 2.2 * s, C.Leaf2, DECOR)
	local top = LAWN + 3 * s
	span(parent, "BushTop", x - 1.9 * s, x + 1.7 * s, top - 0.3, top + 1.2 * s, z - 1.6 * s, z + 1.6 * s, bloom, DECOR)
end

local function buildGreenery(template: any)
	local green = U.model(template, "Greenery")
	-- Flower fields in the side lawns.
	flowerField(green, -62, 74, 104, 0)
	flowerField(green, 49, 74, 104, 2)
	-- Big trees in the side lawns (an apple and an orange tree among them) and beside the house.
	tree(green, -56, 62, 1.6, 11, "green", C.Red)
	tree(green, 56, 62, 1.55, 12, "mint")
	tree(green, -56, 117, 1.65, 13, "mint")
	tree(green, 56, 117, 1.6, 14, "green", C.Orange)
	tree(green, -30, 160, 1.3, 15, "green")
	tree(green, 30, 160, 1.3, 16, "mint")
	-- Flowering shrubs flanking the steps up to the stage.
	for _, p in { { -20, 49 }, { 20, 49 } } do
		bush(green, p[1], p[2], 1.1, C.Pink)
	end
end

------------------------------------------------------------------------------------------
-- Pier, end platform, pavilion, props, boat
------------------------------------------------------------------------------------------

local PIER_HALF = 8 -- walkway deck x = ±8
local PIER_END = -70 -- walkway ends, platform begins
local PLAT_HALF = 20 -- platform x = ±20

-- Deck slab (top at `top`) with raised plank strips (4 studs wide, every 8; 0.1 short of the
-- deck's ends): along Z for the walkway, across (along X) for the platform. z0 < z1.
local function deck(parent: any, halfWidth: number, z0: number, z1: number, across: boolean, top: number)
	span(parent, "Deck", -halfWidth, halfWidth, DECK - 1.2, top, z0, z1, C.WoodLight)
	local flat = { CastShadow = false }
	if across then
		local z = z0 + 2
		while z + 4 <= z1 - 1 do
			span(parent, "Planks", -halfWidth + 0.1, halfWidth - 0.1, DECK - 0.2, PLANK, z, z + 4, C.Wood, flat)
			z += 8
		end
	else
		local x = -halfWidth + 2
		while x + 4 <= halfWidth - 2 + 0.01 do
			span(parent, "Planks", x, x + 4, DECK - 0.2, PLANK, z0 + 0.1, z1 - 0.1, C.Wood, flat)
			x += 8
		end
	end
end

local function buildPier(template: any, pierEnd: number, pileBottom: number)
	local pier = U.model(template, "Pier")
	local hw = PIER_HALF
	-- (the walkway slab sits 0.14 under the promenade tiles it runs into: no shared plane)
	deck(pier, hw, PIER_END, 0, false, DECK - 0.1)
	-- Accent kerbs along both edges.
	for _, sx in { -1, 1 } do
		span(pier, "Kerb", sx * hw, sx * (hw + 1.2), DECK - 1.4, DECK + 0.6, PIER_END, 0, -0.3)
	end
	-- Posts double as piles; the two end pairs carry lanterns.
	local px = hw + 0.6
	local zs = { -3, -17, -31, -45, -59 }
	for i, z in zs do
		local lantern = i == 1 or i == #zs
		local top = if lantern then DECK + 6 else DECK + 4.2
		for _, sx in { -1, 1 } do
			local x = sx * px
			span(pier, "Post", x - 1, x + 1, pileBottom, top, z - 1, z + 1, C.Wood)
			if lantern then
				span(pier, "Lantern", x - 0.9, x + 0.9, top, top + 1.8, z - 0.9, z + 0.9, C.Lamp, NEON_DECOR)
				span(pier, "LanternCap", x - 1.3, x + 1.3, top + 1.8, top + 2.4, z - 1.3, z + 1.3, 0, DECOR)
			end
		end
	end
	-- Block rails: Accent top rail, white middle rail.
	for _, sx in { -1, 1 } do
		local x = sx * px
		span(pier, "Rail", x - 0.5, x + 0.5, DECK + 3.2, DECK + 4.0, PIER_END + 1, -3, 0)
		span(pier, "RailLow", x - 0.35, x + 0.35, DECK + 1.6, DECK + 2.2, PIER_END + 1, -3, C.White)
	end

	-- End platform (its front kerb ends exactly at the end of the pier corridor).
	local plat = U.model(template, "Platform")
	local z0, z1 = pierEnd + 1.2, PIER_END
	deck(plat, PLAT_HALF, z0, z1, true, DECK)
	local e = PLAT_HALF
	span(plat, "Kerb", -e - 1.2, e + 1.2, DECK - 1.4, DECK + 0.6, pierEnd, z0, -0.3)
	for _, sx in { -1, 1 } do
		span(plat, "Kerb", sx * e, sx * (e + 1.2), DECK - 1.4, DECK + 0.6, z0, z1, -0.3)
		span(plat, "Kerb", sx * (hw + 1.2), sx * (e + 1.2), DECK - 1.4, DECK + 0.6, z1, z1 + 1.2, -0.3)
	end
	-- Piles and rails (the front middle stays open for casting).
	local pe = e + 0.6
	local zf = z0 + 0.4
	for _, p in
		{
			{ -pe, zf },
			{ pe, zf },
			{ -pe, z1 - 1 },
			{ pe, z1 - 1 },
			{ -pe, (zf + z1) / 2 },
			{ pe, (zf + z1) / 2 },
			{ -9, zf },
			{ 9, zf },
		}
	do
		span(plat, "Post", p[1] - 1, p[1] + 1, pileBottom, DECK + 4.2, p[2] - 1, p[2] + 1, C.Wood)
	end
	for _, sx in { -1, 1 } do
		span(plat, "Rail", sx * pe - 0.5, sx * pe + 0.5, DECK + 3.2, DECK + 4, zf, z1 - 1, 0)
		span(plat, "Rail", sx * 9, sx * pe, DECK + 3.2, DECK + 4, zf - 0.5, zf + 0.5, 0)
	end
end

-- Fishing pavilion over the FishingSpot at the front edge of the platform.
local function buildPavilion(template: any, pierEnd: number)
	local pav = U.model(template, "Pavilion")
	local z0 = pierEnd + 3.5 -- front posts
	local z1 = pierEnd + 15.5 -- back posts
	local postTop = DECK + 9
	for _, x in { -6.5, 6.5 } do
		for _, z in { z0, z1 } do
			span(pav, "Post", x - 0.7, x + 0.7, DECK, postTop, z - 0.7, z + 0.7, C.White)
		end
	end
	local zc = (z0 + z1) / 2
	local y = postTop
	for i, layer in { { 17, 1.2, -0.3 }, { 13, 1.4, 0 }, { 9, 1.4, 0.2 }, { 4.4, 1.4, -0.1 } } do
		local w = layer[1]
		span(pav, "Roof", -w / 2, w / 2, y, y + layer[2], zc - w / 2, zc + w / 2, layer[3], { CastShadow = i <= 2 })
		y += layer[2]
	end
	local lamp = span(pav, "Lantern", -0.9, 0.9, postTop - 2.6, postTop - 0.6, zc - 0.9, zc + 0.9, C.Lamp, NEON_DECOR)
	span(pav, "LanternCord", -0.15, 0.15, postTop - 0.65, postTop + 0.1, zc - 0.15, zc + 0.15, C.Ink, DECOR)
	U.new("PointLight", { Range = 16, Brightness = 1.3, Color = C.Lamp, Shadows = false }, lamp)

	-- Where the owner stands to fish (stage 2 checks the distance to this part).
	local sz = pierEnd + 4.5
	span(pav, "SpotRing", -3.4, 3.4, DECK, PLANK + 0.15, sz - 3.4, sz + 3.4, C.White, { CanCollide = false })
	span(template, "FishingSpot", -2.6, 2.6, DECK, PLANK + 0.3, sz - 2.6, sz + 2.6, 0.3, { CastShadow = false })
end

local function buildPierProps(template: any, pierEnd: number)
	local props = U.model(template, "PierProps")
	-- Rod rack on the left of the platform.
	local rx, rz = -15, pierEnd + 14
	for _, dx in { -3, 3 } do
		span(props, "RackPost", rx + dx - 0.4, rx + dx + 0.4, DECK, DECK + 5.4, rz - 0.4, rz + 0.4, C.Wood)
	end
	span(props, "RackBar", rx - 3.6, rx + 3.6, DECK + 4.2, DECK + 5, rz - 0.5, rz + 0.5, -0.2)
	local rod = at(rx - 1, DECK + 3.6, rz - 0.6) * CFrame.Angles(rad(-12), 0, rad(8))
	make(props, "Rod", Vector3.new(0.3, 7.4, 0.3), rod, C.Red, DECOR)
	-- Crates and a barrel on the right.
	span(props, "Crate", 11, 15, DECK, DECK + 4, pierEnd + 11, pierEnd + 15, C.Wood)
	span(props, "Crate", 15.6, 18.6, DECK, DECK + 3, pierEnd + 12, pierEnd + 15, C.WoodLight)
	span(props, "Crate", 12, 14.6, DECK + 4, DECK + 6.6, pierEnd + 12, pierEnd + 14.6, 0.1)
	cylY(props, "Barrel", 2.8, 3.4, at(16.6, DECK + 1.7, pierEnd + 7.6), C.Blue)
	-- Lifebuoy hanging on the outside of the left rail (square ring, red and white).
	local bx, bz = -(PLAT_HALF + 1.35), pierEnd + 8
	for i, s in { { 0, 1.1 }, { 0, -1.1 }, { 1.1, 0 }, { -1.1, 0 } } do
		local col = if i <= 2 then C.Red else C.White
		local dy, dz = s[1], s[2]
		local sy = if dz == 0 then 0.8 else 3
		local sz = if dz == 0 then 1.4 else 0.8
		local y = DECK + 2.4 + dy
		span(
			props,
			"Lifebuoy",
			bx - 0.3,
			bx + 0.3,
			y - sy / 2,
			y + sy / 2,
			bz + dz - sz / 2,
			bz + dz + sz / 2,
			col,
			DECOR
		)
	end
end

-- Little rowing boat moored at the right side of the pier.
local function buildBoat(template: any, waterY: number)
	local boat = U.model(template, "Boat")
	local f = facing(15, waterY, -44, 4)
	box(boat, "Hull", f, 0, 0, 0, 4.6, 1.6, 10, C.WoodLight)
	for _, sx in { -1, 1 } do
		box(boat, "Side", f, sx * 2.7, 0.9, 0.3, 0.8, 2.4, 10.6, 0)
	end
	box(boat, "Stern", f, 0, 0.9, 5.2, 4.6, 2.4, 0.8, 0)
	box(boat, "Bow", f, 0, 0.9, -5.6, 3.6, 2.4, 1.6, -0.25)
	box(boat, "BowTip", f, 0, 1.1, -6.8, 2, 2.2, 1, -0.25)
	box(boat, "Seat", f, 0, 1.3, 1.6, 4.6, 0.5, 1.6, C.White)
	box(boat, "Oar", f, 0.6, 1.0, -1.8, 0.4, 0.3, 7, C.Wood, DECOR)
end

------------------------------------------------------------------------------------------

return function(game: any, mapCfg: any)
	local serverStorage = game:GetService("ServerStorage")
	local template = U.new("Model", { Name = "BaseTemplate" }, serverStorage)
	local partsBefore = U.partCount

	local root = U.marker(template, "Root", Vector3.new(2, 0.2, 2), CFrame.new(0, 0, 0))
	template.PrimaryPart = root

	local front = mapCfg.PlotFront or 18
	local plot = {
		halfWidth = mapCfg.PlotHalfWidth or 68,
		front = front,
		back = front + (mapCfg.PlotDepth or 150),
	}
	local pierEnd = -(mapCfg.PierLength or 92)
	local waterY = (mapCfg.WaterTop or 0) - (mapCfg.GroundTop or 4) -- local water surface (-4)
	local pileBottom = waterY - 16 -- y = -20: below the lagoon bed under the pier

	buildGrounds(template, plot)
	buildWalls(template, plot)
	buildGate(template, plot)
	buildSpawn(template)
	local signOffset = buildFlag(template)
	buildAlarm(template)
	buildYardDecor(template)
	local tank, expected = buildTank(template)
	buildSlots(tank, expected)
	buildDogHouse(template)
	buildDog(template)
	buildHouse(template)
	buildGarden(template)
	buildPond(template)
	local sparksOffset = buildCampfire(template)
	buildGreenery(template)
	buildPier(template, pierEnd, pileBottom)
	buildPavilion(template, pierEnd)
	buildPierProps(template, pierEnd)
	buildBoat(template, waterY)

	local count = 0
	for _, d in template:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	assert(count == U.partCount - partsBefore, "BaseTemplate: parts created outside Util.part")

	table.insert(expected, { root = "template", path = { "Flag", "Pole", "SignAttachment" }, offset = signOffset })
	table.insert(
		expected,
		{ root = "template", path = { "Campfire", "Logs", "SparksAttachment" }, offset = sparksOffset }
	)
	return {
		template = template,
		partCount = count,
		-- Verified by the post-build self-check in tools/build.luau (path from the template root).
		expectedAttachments = expected,
	}
end
