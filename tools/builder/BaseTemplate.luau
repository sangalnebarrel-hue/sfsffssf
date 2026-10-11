--[[
	Builds ServerStorage.BaseTemplate — one player base. BaseService clones it into the
	8 slots at runtime and paints every part with attribute Accent = true in the base colour.

	Local frame (Root at the origin = shore line, terrace top):
	  y = 0      flat terrace (MapConfig.GroundTop in world space); water is at y = -4
	  -Z         towards the lake centre (pier direction)
	  +Z         inland (yard, spawn pad, gate to the ring road)
	  +X / -X    right / left when facing the lake
	The terrace is flat for x = ±44, z = 0..84; a sand beach slopes into the water by z ≈ -10.

	Layout (back to front), ~220 parts:
	  z ≈ 80        gate arch with banners and lanterns (open towards the ring road), mailbox
	  z ≈ 58        round spawn plaza (SpawnPad on a glowing ring), flagpole with the owner
	                sign, vegetable garden (left), trees (right)
	  z ≈ 20..44    patio with a picnic table and a parasol; cabin on the left (door to the
	                patio), fish stall on the right; hedges along both side edges
	  z ≈ 8..20     campfire by the lake (left), doghouse with the guard dog at the pier entrance
	  z = 8..-46    long pier: rope rails, lanterns, lifebuoy, a moored rowing boat
	  z = -46..-68  pier platform: fishing pavilion (FishingSpot), aquarium tank, lighthouse
	                whose lantern room is the alarm lamp, barrels with rods, bench to the lake

	Names below are referenced by server code (BaseService.createBase) — keep them in sync:
	  Root, SpawnPad, FishingSpot, Tank.Glass.PromptAttachment, Alarm.Lamp, Dog,
	  Flag.Pole.SignAttachment.OwnerSign.{OwnerLabel, BaseLabel}, Flag.Cloth (tests)
]]

local U = require("./Util")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Enum = U.Enum
local UDim2 = U.UDim2
local rgb = U.rgb

local M = Enum.Material
local rad = math.rad

local ACCENT_DEFAULT = rgb(200, 200, 200) -- replaced by the base colour at runtime

local C = {
	deck = rgb(204, 152, 96),
	deckLight = rgb(226, 182, 124),
	wood = rgb(178, 124, 76),
	woodDark = rgb(124, 84, 52),
	woodDeep = rgb(88, 60, 40),
	stone = rgb(186, 180, 168),
	stoneDark = rgb(132, 128, 122),
	path = rgb(232, 218, 186),
	cream = rgb(250, 240, 216),
	white = rgb(250, 250, 246),
	glass = rgb(150, 220, 248),
	window = rgb(132, 196, 232),
	sand = rgb(240, 218, 162),
	soil = rgb(120, 82, 56),
	leaf1 = rgb(90, 172, 74),
	leaf2 = rgb(66, 146, 64),
	leaf3 = rgb(132, 198, 90),
	pine1 = rgb(44, 122, 78),
	pine2 = rgb(58, 142, 88),
	hedge = rgb(70, 148, 66),
	hedgeTop = rgb(98, 178, 80),
	crops = rgb(112, 196, 84),
	pumpkin = rgb(246, 140, 40),
	pink = rgb(255, 126, 172),
	yellow = rgb(255, 214, 74),
	lilac = rgb(178, 128, 238),
	lamp = rgb(255, 216, 140),
	fire = rgb(255, 128, 36),
	metal = rgb(72, 76, 86),
	steel = rgb(196, 200, 208),
	gold = rgb(248, 198, 60),
	lampOff = rgb(128, 30, 30),
	rope = rgb(222, 196, 142),
	buoy = rgb(242, 92, 62),
	dog = rgb(232, 156, 84),
	dogCream = rgb(255, 242, 220),
	black = rgb(30, 30, 36),
	tongue = rgb(255, 118, 140),
	food = rgb(150, 92, 52),
}

local DECK = 0.6 -- top of the pier deck and platform

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

-- Small or thin parts never cast shadows (cheaper, and their shadows look noisy).
local function shadowRule(size: any, extra: { [string]: any }): { [string]: any }
	if extra.CastShadow == nil then
		local minSide = math.min(size.X, size.Y, size.Z)
		local maxSide = math.max(size.X, size.Y, size.Z)
		if minSide <= 0.5 or maxSide <= 2.2 then
			extra.CastShadow = false
		end
	end
	return extra
end

local function P(parent: any, name: string, size: any, cf: any, color: any, mat: any?, extra: { [string]: any }?): any
	return U.part(parent, name, size, cf, color, mat, shadowRule(size, merge(nil, extra)))
end

local function A(parent: any, name: string, size: any, cf: any, mat: any?, extra: { [string]: any }?): any
	local props = shadowRule(size, merge(extra, { Attributes = { Accent = true } }))
	return U.part(parent, name, size, cf, ACCENT_DEFAULT, mat, props)
end

local function W(parent: any, name: string, size: any, cf: any, color: any?, mat: any?, extra: { [string]: any }?): any
	if color == nil then
		local props = shadowRule(size, merge(extra, { Attributes = { Accent = true } }))
		return U.wedge(parent, name, size, cf, ACCENT_DEFAULT, mat, props)
	end
	return U.wedge(parent, name, size, cf, color, mat, shadowRule(size, merge(nil, extra)))
end

-- Shaped part (cylinder / ball); colour nil = Accent.
local function shaped(
	parent: any,
	name: string,
	shape: any,
	size: any,
	cf: any,
	color: any?,
	mat: any?,
	extra: any?
): any
	local props = merge(extra, { Shape = shape })
	if color == nil then
		return A(parent, name, size, cf, mat, props)
	end
	return P(parent, name, size, cf, color, mat, props)
end

-- Cylinder whose axis is cf's local Y (upright when cf is not rotated).
local function cylY(parent: any, name: string, d: number, h: number, cf: any, color: any?, mat: any?, extra: any?): any
	local frame = cf * CFrame.Angles(0, 0, rad(90))
	return shaped(parent, name, Enum.PartType.Cylinder, Vector3.new(h, d, d), frame, color, mat, extra)
end

-- Cylinder along cf's local X / local Z.
local function cylX(
	parent: any,
	name: string,
	d: number,
	len: number,
	cf: any,
	color: any?,
	mat: any?,
	extra: any?
): any
	return shaped(parent, name, Enum.PartType.Cylinder, Vector3.new(len, d, d), cf, color, mat, extra)
end

local function cylZ(
	parent: any,
	name: string,
	d: number,
	len: number,
	cf: any,
	color: any?,
	mat: any?,
	extra: any?
): any
	return cylX(parent, name, d, len, cf * CFrame.Angles(0, rad(90), 0), color, mat, extra)
end

local function ball(parent: any, name: string, d: number, cf: any, color: any?, mat: any?, extra: any?): any
	return shaped(parent, name, Enum.PartType.Ball, Vector3.new(d, d, d), cf, color, mat, extra)
end

local function at(x: number, y: number, z: number): any
	return CFrame.new(x, y, z)
end

-- Attachment on `part` placed at template-space CFrame `cf`; returns its offset for the self-check.
local function attachAt(part: any, name: string, cf: any): (any, any)
	local rel = part.CFrame:Inverse() * cf
	local attachment = U.new("Attachment", { Name = name, CFrame = rel }, part)
	return attachment, rel.Position
end

local NO_COLLIDE = { CanCollide = false }
local DECOR = { CanCollide = false, CastShadow = false }

--[[
	Gable roof in frame cf: ridge along local X, y = 0 is the eaves line, centred on the ridge.
	A solid prism (two wedges, colour `gable`) fills the gables; two Accent slabs with overhangs
	lie on top (0.05 above the slopes), an optional ridge cap closes the seam.
]]
local function gableRoof(
	parent: any,
	cf: any,
	lenX: number,
	depthZ: number,
	h: number,
	gable: any,
	opts: { t: number?, eave: number?, ends: number?, ridge: any? }?
)
	local o = opts or {}
	local t = o.t or 0.6
	local eave = o.eave or 1.2
	local ends = o.ends or 0.8
	local d = depthZ / 2
	W(
		parent,
		"Gable",
		Vector3.new(lenX, h, d),
		cf * at(0, h / 2, d / 2) * CFrame.Angles(0, math.pi, 0),
		gable,
		M.WoodPlanks
	)
	W(parent, "Gable", Vector3.new(lenX, h, d), cf * at(0, h / 2, -d / 2), gable, M.WoodPlanks)
	local L = math.sqrt(d * d + h * h)
	local a = math.atan2(h, d)
	local lift = t / 2 + 0.05
	local size = Vector3.new(lenX + 2 * ends, t, L + eave)
	for _, side in { 1, -1 } do
		local n = Vector3.new(0, d / L, side * h / L)
		local s = Vector3.new(0, -h / L, side * d / L)
		local mid = Vector3.new(0, h / 2, side * d / 2)
		local pos = mid + n * lift + s * (eave / 2)
		A(
			parent,
			"Roof",
			size,
			cf * CFrame.new(pos) * CFrame.Angles(side * a, 0, 0),
			M.SmoothPlastic,
			{ CastShadow = true }
		)
	end
	if o.ridge then
		cylX(parent, "Ridge", t * 1.9, lenX + 2 * ends + 0.3, cf * at(0, h + t * 0.75, 0), o.ridge, M.Wood, DECOR)
	end
end

-- Text on one face of a sign board.
local function label(parent: any, face: any, text: string, color: any)
	local gui = U.new("SurfaceGui", {
		Name = "Sign" .. face.Name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0.3,
	}, parent)
	U.new("TextLabel", {
		Name = "Text",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = color,
		TextStrokeColor3 = C.woodDeep,
		TextStrokeTransparency = 0.2,
	}, gui)
end

------------------------------------------------------------------------------------------
-- Pier and platform
------------------------------------------------------------------------------------------

local PIER_HALF = 5 -- deck x = ±5
local PIER_START, PIER_END = 8, -46 -- deck z range
local PLAT_HALF = 16 -- platform x = ±16
local PLAT_BACK, PLAT_FRONT = -46, -68 -- platform z range

local function buildPier(template: any, pileBottom: number)
	local pier = U.model(template, "Pier")
	local len = PIER_START - PIER_END
	local zMid = (PIER_START + PIER_END) / 2

	P(pier, "Deck", Vector3.new(PIER_HALF * 2, 1, len), at(0, DECK - 0.5, zMid), C.deck, M.WoodPlanks)
	for _, sx in { -1, 1 } do
		A(pier, "Curb", Vector3.new(0.7, 0.45, len), at(sx * (PIER_HALF - 0.35), DECK + 0.225, zMid), M.WoodPlanks)
	end

	-- Posts double as piles: from the lake bed through the deck edge up to the rope rail.
	-- The pairs at the entrance and at the platform carry lanterns.
	local postX = PIER_HALF + 0.35
	local zs = { 6, -10, -26, -42 }
	for _, z in zs do
		local lantern = z == zs[1] or z == zs[#zs]
		local top = if lantern then DECK + 5.2 else DECK + 2.8
		for _, sx in { -1, 1 } do
			local bottom = if z > 0 then -3 else pileBottom
			cylY(pier, "Post", 1.1, top - bottom, at(sx * postX, (top + bottom) / 2, z), C.woodDark, M.Wood)
			if lantern then
				P(pier, "LanternCap", Vector3.new(1.5, 0.4, 1.5), at(sx * postX, top + 1.55, z), C.metal, M.Metal)
				local glow = P(pier, "Lantern", Vector3.new(1, 1.35, 1), at(sx * postX, top + 0.68, z), C.lamp, M.Neon)
				if z == zs[1] then
					U.new("PointLight", { Range = 14, Brightness = 1.4, Color = C.lamp, Shadows = false }, glow)
				end
			end
		end
	end
	local ropeLen = zs[1] - zs[#zs] + 0.4
	for _, sx in { -1, 1 } do
		cylZ(pier, "Rope", 0.28, ropeLen, at(sx * postX, DECK + 2.3, (zs[1] + zs[#zs]) / 2), C.rope, M.Fabric, DECOR)
	end

	-- Lifebuoy hanging on the outer side of a middle post.
	local bx = postX + 0.75
	cylX(pier, "Lifebuoy", 2.3, 0.4, at(bx, DECK + 1.3, -26), C.buoy, M.SmoothPlastic, DECOR)
	cylX(pier, "LifebuoyHole", 1.05, 0.5, at(bx, DECK + 1.3, -26), C.woodDeep, M.SmoothPlastic, DECOR)
end

local function buildPlatform(template: any, pileBottom: number)
	local plat = U.model(template, "Platform")
	local zMid = (PLAT_BACK + PLAT_FRONT) / 2
	local depth = PLAT_BACK - PLAT_FRONT
	P(plat, "Deck", Vector3.new(PLAT_HALF * 2, 1, depth), at(0, DECK - 0.5, zMid), C.deck, M.WoodPlanks)

	-- Accent curbs around the edge (open where the pier joins).
	local e = PLAT_HALF - 0.35
	A(plat, "Curb", Vector3.new(0.7, 0.45, depth), at(-e, DECK + 0.225, zMid), M.WoodPlanks)
	A(plat, "Curb", Vector3.new(0.7, 0.45, depth), at(e, DECK + 0.225, zMid), M.WoodPlanks)
	A(plat, "Curb", Vector3.new(e * 2 - 0.7, 0.45, 0.7), at(0, DECK + 0.225, PLAT_FRONT + 0.35), M.WoodPlanks)
	local backLen = PLAT_HALF - 0.7 - PIER_HALF
	for _, sx in { -1, 1 } do
		A(
			plat,
			"Curb",
			Vector3.new(backLen, 0.45, 0.7),
			at(sx * (PIER_HALF + backLen / 2), DECK + 0.225, PLAT_BACK - 0.35),
			M.WoodPlanks
		)
	end

	-- Corner piles down to the lake bed.
	for _, sx in { -1, 1 } do
		for _, z in { PLAT_BACK - 1, PLAT_FRONT + 1 } do
			local top = DECK - 1
			cylY(
				plat,
				"Pile",
				1.6,
				top - pileBottom,
				at(sx * (PLAT_HALF - 0.9), (top + pileBottom) / 2, z),
				C.woodDeep,
				M.Wood
			)
		end
	end
end

-- Roofed fishing pavilion on the left half of the platform; FishingSpot at its lake edge.
local function buildPavilion(template: any)
	local pav = U.model(template, "Pavilion")
	local x0, x1 = -15, -5
	local z0, z1 = PLAT_BACK - 7, PLAT_FRONT + 1
	local postTop = DECK + 7
	for _, x in { x0, x1 } do
		for _, z in { z0, z1 } do
			P(
				pav,
				"Post",
				Vector3.new(0.8, postTop - DECK + 0.1, 0.8),
				at(x, (postTop + DECK - 0.1) / 2, z),
				C.cream,
				M.Wood
			)
		end
		P(pav, "Beam", Vector3.new(0.9, 0.8, z0 - z1 + 1.4), at(x, postTop + 0.4, (z0 + z1) / 2), C.woodDark, M.Wood)
	end
	for _, z in { z0, z1 } do
		P(pav, "TieBeam", Vector3.new(x1 - x0 + 0.7, 0.8, 0.9), at((x0 + x1) / 2, postTop + 0.3, z), C.woodDark, M.Wood)
	end
	local roofCf = at((x0 + x1) / 2, postTop + 0.8, (z0 + z1) / 2) * CFrame.Angles(0, rad(90), 0)
	gableRoof(pav, roofCf, z0 - z1 + 1.4, x1 - x0 + 0.9, 4.4, C.cream, { eave = 1.6, ends = 1.2, ridge = C.cream })

	-- Hanging lantern under the ridge, over the fishing spot.
	local lz = z1 + 2.5
	P(pav, "LanternCord", Vector3.new(0.12, 1.7, 0.12), at((x0 + x1) / 2, postTop + 0.95, lz), C.metal, nil, DECOR)
	local glow = P(pav, "Lantern", Vector3.new(1, 1.3, 1), at((x0 + x1) / 2, postTop - 0.5, lz), C.lamp, M.Neon, DECOR)
	U.new("PointLight", { Range = 16, Brightness = 1.5, Color = C.lamp, Shadows = false }, glow)

	-- Where the owner stands to fish (stage 2 checks the distance to this part).
	A(template, "FishingSpot", Vector3.new(3.4, 0.12, 3.4), at((x0 + x1) / 2, DECK + 0.06, PLAT_FRONT + 2.6), M.Fabric)

	-- Barrels, crates and fishing rods leaning on them in the back-left corner.
	local props = U.model(template, "PierProps")
	local pz = PLAT_BACK
	cylY(props, "Barrel", 2.1, 2.6, at(-13.8, DECK + 1.3, pz - 2.2), C.wood, M.Wood)
	cylY(props, "Barrel", 2.1, 2.6, at(-11.4, DECK + 1.3, pz - 2.0), C.woodDark, M.Wood)
	P(
		props,
		"Crate",
		Vector3.new(2.4, 2.4, 2.4),
		at(-13.6, DECK + 1.2, pz - 4.7) * CFrame.Angles(0, rad(14), 0),
		C.deckLight,
		M.WoodPlanks
	)
	P(
		props,
		"Crate",
		Vector3.new(1.7, 1.7, 1.7),
		at(-13.5, DECK + 3.25, pz - 4.6) * CFrame.Angles(0, rad(-8), 0),
		C.wood,
		M.WoodPlanks
	)
	-- Fishing rods standing in the first barrel, fanned out.
	for i, tilt in { { -9, 7 }, { 8, -5 }, { 3, 12 } } do
		local rod = CFrame.new(-13.8, DECK + 2.6, pz - 2.2)
			* CFrame.Angles(rad(tilt[1]), 0, rad(tilt[2]))
			* at(0, 2.5, 0)
		P(props, "Rod", Vector3.new(0.2, 7, 0.2), rod, if i == 2 then C.metal else C.woodDeep, nil, DECOR)
	end

	-- Bench at the lake end of the central aisle, facing the water.
	local bz = PLAT_FRONT + 3.4
	P(props, "BenchSeat", Vector3.new(5.4, 0.4, 1.5), at(0, DECK + 1.6, bz), C.deckLight, M.WoodPlanks)
	P(props, "BenchBack", Vector3.new(5.4, 1.3, 0.35), at(0, DECK + 2.5, bz + 0.75), C.deckLight, M.WoodPlanks)
	P(props, "BenchLeg", Vector3.new(3.6, 1.4, 0.8), at(0, DECK + 0.7, bz), C.woodDark, M.Wood)
end

------------------------------------------------------------------------------------------
-- Aquarium tank + lighthouse alarm
------------------------------------------------------------------------------------------

local GLASS = Vector3.new(11, 7, 11)
local TANK_X, TANK_Z = 9, PLAT_BACK - 11.5
local PLINTH_TOP = DECK + 0.8
local SAND_TOP = PLINTH_TOP + 0.6
local GLASS_Y = SAND_TOP + GLASS.Y / 2
local PROMPT_OFFSET = Vector3.new(0, (DECK + 3) - GLASS_Y, GLASS.Z / 2 + 1)

local function buildTank(template: any)
	local tank = U.model(template, "Tank")
	local hx, hz = GLASS.X / 2, GLASS.Z / 2
	P(
		tank,
		"Plinth",
		Vector3.new(GLASS.X + 1.6, PLINTH_TOP - DECK + 0.2, GLASS.Z + 1.6),
		at(TANK_X, (PLINTH_TOP + DECK - 0.2) / 2, TANK_Z),
		C.woodDark,
		M.WoodPlanks
	)
	P(
		tank,
		"Sand",
		Vector3.new(GLASS.X, SAND_TOP - PLINTH_TOP, GLASS.Z),
		at(TANK_X, (SAND_TOP + PLINTH_TOP) / 2, TANK_Z),
		C.sand,
		M.Sand
	)
	local glass = P(tank, "Glass", GLASS, at(TANK_X, GLASS_Y, TANK_Z), C.glass, M.Glass, {
		Transparency = 0.45,
		CastShadow = false,
	})
	-- Stage 3/4: tank / steal ProximityPrompts live here, on the side facing the pier deck.
	U.new("Attachment", { Name = "PromptAttachment", CFrame = CFrame.new(PROMPT_OFFSET) }, glass)
	tank.PrimaryPart = glass

	-- Glowing accent frame: corner posts + white top rim + name board.
	local frameTop = SAND_TOP + GLASS.Y + 0.35
	local postBottom, postTop = PLINTH_TOP - 0.1, frameTop + 0.15
	local postH = postTop - postBottom
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			A(
				tank,
				"Trim",
				Vector3.new(0.6, postH, 0.6),
				at(TANK_X + sx * hx, postBottom + postH / 2, TANK_Z + sz * hz),
				M.Neon,
				{ CastShadow = false }
			)
		end
	end
	for _, sz in { -1, 1 } do
		P(
			tank,
			"Rim",
			Vector3.new(GLASS.X + 0.7, 0.7, 0.7),
			at(TANK_X, frameTop - 0.35, TANK_Z + sz * hz),
			C.white,
			nil,
			{ CastShadow = false }
		)
	end
	for _, sx in { -1, 1 } do
		P(
			tank,
			"Rim",
			Vector3.new(0.7, 0.7, GLASS.Z - 0.7),
			at(TANK_X + sx * hx, frameTop - 0.35, TANK_Z),
			C.white,
			nil,
			{ CastShadow = false }
		)
	end
	local board = A(
		tank,
		"Board",
		Vector3.new(6, 1.6, 0.3),
		at(TANK_X, frameTop + 0.75, TANK_Z + hz),
		nil,
		{ CastShadow = false }
	)
	label(board, Enum.NormalId.Back, "УЛОВ", C.white)

	-- Little lighthouse on the platform corner behind the tank; its lantern room is the alarm
	-- lamp (stage 4 makes Lamp flash red), visible from across the lake.
	local alarm = U.model(template, "Alarm")
	local lx, lz = PLAT_HALF - 2.9, PLAT_FRONT + 2.1
	local towerTop = DECK + 14
	cylY(alarm, "Tower", 3.6, towerTop - DECK + 0.2, at(lx, (towerTop + DECK - 0.2) / 2, lz), C.white, M.SmoothPlastic)
	for _, y in { DECK + 3.6, DECK + 9.4 } do
		cylY(alarm, "Stripe", 3.8, 2.2, at(lx, y, lz), nil, M.SmoothPlastic)
	end
	cylY(alarm, "Gallery", 5, 0.5, at(lx, towerTop + 0.25, lz), C.metal, M.Metal)
	cylY(alarm, "Lamp", 2.8, 2.4, at(lx, towerTop + 1.7, lz), C.lampOff, M.SmoothPlastic, { CastShadow = false })
	cylY(alarm, "Cap", 3.8, 0.5, at(lx, towerTop + 3.15, lz), nil, M.SmoothPlastic)
	ball(alarm, "Dome", 2.6, at(lx, towerTop + 3.4, lz), nil, M.SmoothPlastic)
end

------------------------------------------------------------------------------------------
-- Rowing boat moored at the pier
------------------------------------------------------------------------------------------

local function buildBoat(template: any, waterY: number)
	local boat = U.model(template, "Boat")
	local cf = at(-10.6, waterY, -27) * CFrame.Angles(0, rad(-7), 0)
	local w, len, bowLen = 4.2, 6.6, 3.2
	local bottom, top = -0.6, 1.2
	local h = top - bottom
	local yc = (top + bottom) / 2
	for _, sx in { -1, 1 } do
		A(boat, "Side", Vector3.new(0.4, h, len), cf * at(sx * (w / 2 - 0.2), yc, 0), nil, { CastShadow = true })
	end
	A(boat, "Stern", Vector3.new(w - 0.8, h, 0.4), cf * at(0, yc, len / 2 - 0.2), nil, { CastShadow = true })
	P(boat, "Floor", Vector3.new(w - 0.8, 0.3, len - 0.4), cf * at(0, 0.4, -0.2), C.deckLight, M.WoodPlanks)
	-- Pointed bow: two wedges lying on their side (triangles in the horizontal plane).
	local zb = -len / 2 - bowLen / 2
	W(boat, "Bow", Vector3.new(h, w / 2, bowLen), cf * at(-w / 4, yc, zb) * CFrame.Angles(0, 0, rad(90)), nil)
	W(boat, "Bow", Vector3.new(h, w / 2, bowLen), cf * at(w / 4, yc, zb) * CFrame.Angles(0, 0, rad(-90)), nil)
	P(boat, "Seat", Vector3.new(w - 0.8, 0.35, 1.2), cf * at(0, 0.95, 0.9), C.white, M.Wood)
end

------------------------------------------------------------------------------------------
-- Doghouse + guard dog at the pier entrance
------------------------------------------------------------------------------------------

local function buildDogHouse(template: any)
	local house = U.model(template, "DogHouse")
	-- Doghouse frame: door faces local -Z, turned towards the pier path (-X).
	local cf = at(14, 0, 12.5) * CFrame.Angles(0, rad(90), 0)
	local w, d, wallH = 5, 5.4, 3.6
	P(house, "Floor", Vector3.new(w + 0.8, 0.6, d + 0.8), cf * at(0, 0.1, 0), C.woodDark, M.WoodPlanks)
	P(house, "Walls", Vector3.new(w, wallH, d), cf * at(0, 0.4 + wallH / 2, 0), C.wood, M.WoodPlanks)
	P(
		house,
		"Door",
		Vector3.new(1.9, 2.05, 0.2),
		cf * at(0, 0.45 + 1.025, -d / 2 - 0.05),
		C.woodDeep,
		nil,
		{ CastShadow = false }
	)
	cylZ(house, "DoorArch", 1.9, 0.3, cf * at(0, 0.4 + 2.1, -d / 2 - 0.05), C.woodDeep, nil, DECOR)
	gableRoof(
		house,
		cf * at(0, 0.4 + wallH, 0) * CFrame.Angles(0, rad(90), 0),
		d,
		w,
		2.2,
		C.cream,
		{ t = 0.45, eave = 0.8, ends = 0.6 }
	)

	-- Bowl (accent) with food.
	local bowlCf = cf * at(-2.4, 0, -3.8)
	cylY(house, "Bowl", 1.7, 0.6, bowlCf * at(0, 0.3, 0), nil, nil, DECOR)
	cylY(house, "Food", 1.2, 0.2, bowlCf * at(0, 0.62, 0), C.food, nil, DECOR)
end

-- Cute blocky shiba guarding the pier entrance, looking at whoever comes down the path.
local function buildDog(template: any)
	local dog = U.model(template, "Dog")
	local S = 1.3
	local cf = at(8.6, 0, 11) * CFrame.Angles(0, rad(130), 0) -- local -Z = where the dog looks
	local function piece(name: string, size: any, x: number, y: number, z: number, color: any, extra: any?): any
		return P(dog, name, size * S, cf * at(x * S, y * S, z * S), color, nil, merge(NO_COLLIDE, extra))
	end
	local body = piece("Body", Vector3.new(1.5, 1.25, 2.3), 0, 1.3, 0.2, C.dog, { CastShadow = true })
	piece("Chest", Vector3.new(1.1, 0.9, 0.3), 0, 1.25, -1.0, C.dogCream)
	piece("Head", Vector3.new(1.8, 1.55, 1.55), 0, 2.45, -1.15, C.dog, { CastShadow = true })
	piece("Muzzle", Vector3.new(1.0, 0.6, 0.6), 0, 2.1, -2.15, C.dogCream)
	piece("Nose", Vector3.new(0.38, 0.26, 0.16), 0, 2.32, -2.5, C.black)
	piece("Tongue", Vector3.new(0.3, 0.32, 0.1), 0.12, 1.72, -2.36, C.tongue)
	for _, sx in { -1, 1 } do
		piece("Eye", Vector3.new(0.24, 0.34, 0.1), sx * 0.42, 2.7, -1.96, C.black)
		-- Triangular ear facing forward: wedge turned so its triangle lies in the face plane.
		local ear = cf * at(sx * 0.55 * S, 3.6 * S, -1.2 * S) * CFrame.Angles(0, rad(-90 * sx), 0)
		W(dog, "Ear", Vector3.new(0.35, 0.8, 0.65) * S, ear, C.dog, nil, DECOR)
		piece("Paw", Vector3.new(0.5, 0.75, 0.5), sx * 0.42, 0.375, -0.6, C.dogCream)
		piece("Leg", Vector3.new(0.5, 0.75, 0.5), sx * 0.42, 0.375, 0.95, C.dog)
	end
	ball(dog, "Tail", 0.9 * S, cf * at(0, 2.1 * S, 1.45 * S), C.dogCream, nil, DECOR)
	A(dog, "Collar", Vector3.new(1.6, 0.32, 1.25) * S, cf * at(0, 1.8 * S, -0.8 * S), nil, DECOR)
	dog.PrimaryPart = body
end

------------------------------------------------------------------------------------------
-- Yard: paths, spawn plaza, patio, gate, hedges
------------------------------------------------------------------------------------------

local SPAWN_Z = 58

local function buildYard(template: any)
	local yard = U.model(template, "Yard")

	-- Paths: gate -> spawn plaza -> patio -> pier, and a side path to the cabin door.
	P(yard, "Path", Vector3.new(7, 0.6, 18), at(0, -0.15, 75), C.path, M.Cobblestone)
	P(yard, "Path", Vector3.new(7, 0.6, 6), at(0, -0.15, 47), C.path, M.Cobblestone)
	P(yard, "Path", Vector3.new(7, 0.6, 12.4), at(0, -0.15, 14), C.path, M.Cobblestone)
	P(yard, "Path", Vector3.new(6.6, 0.6, 3.6), at(-18, -0.15, 33), C.path, M.Cobblestone)

	-- Spawn plaza: round stone plinth, white ring, accent pad with a white centre.
	cylY(yard, "Plaza", 19, 0.9, at(0, -0.1, SPAWN_Z), C.stone, M.Slate)
	cylY(yard, "PlazaRing", 14.4, 0.3, at(0, 0.5, SPAWN_Z), C.white, M.SmoothPlastic, { CastShadow = false })
	cylY(yard, "PlazaGlow", 15.4, 0.28, at(0, 0.44, SPAWN_Z), nil, M.Neon, { CastShadow = false })
	A(template, "SpawnPad", Vector3.new(9.6, 0.35, 9.6), at(0, 0.825, SPAWN_Z), M.SmoothPlastic, { CastShadow = false })

	-- Patio: framed wooden deck in front of the spawn plaza.
	local pz0, pz1, px = 20, 44, 15
	A(yard, "PatioFrame", Vector3.new(px * 2, 0.8, pz1 - pz0), at(0, -0.1, (pz0 + pz1) / 2), M.WoodPlanks)
	P(
		yard,
		"Patio",
		Vector3.new(px * 2 - 1.4, 0.8, pz1 - pz0 - 1.4),
		at(0, -0.02, (pz0 + pz1) / 2),
		C.deckLight,
		M.WoodPlanks
	)
	-- Planters with flowers along the patio front, flanking the path.
	for _, sx in { -1, 1 } do
		A(yard, "Planter", Vector3.new(8, 1.2, 1.8), at(sx * 9, 0.98, pz0 + 1.6), M.WoodPlanks, { CastShadow = true })
		P(
			yard,
			"Flowers",
			Vector3.new(7.4, 0.7, 1.3),
			at(sx * 9, 1.86, pz0 + 1.6),
			if sx < 0 then C.pink else C.yellow,
			M.Grass,
			DECOR
		)
	end

	-- Picnic table under a big parasol.
	local tx, tz = 7.5, 33
	P(yard, "TableTop", Vector3.new(3.4, 0.35, 6), at(tx, 2.4, tz), C.deck, M.WoodPlanks)
	P(yard, "TableLeg", Vector3.new(0.6, 2.1, 4.6), at(tx, 1.2, tz), C.woodDark, M.Wood)
	for _, sx in { -1, 1 } do
		P(yard, "TableBench", Vector3.new(1.3, 1.3, 6), at(tx + sx * 2.7, 0.95, tz), C.deck, M.WoodPlanks)
	end
	cylY(yard, "ParasolPole", 0.3, 7.6, at(tx, 4.2, tz), C.white, M.Metal, DECOR)
	cylY(yard, "Parasol", 9, 0.5, at(tx, 7.6, tz), nil, M.Fabric, { CanCollide = false, CastShadow = true })
	cylY(yard, "ParasolTop", 4.6, 0.6, at(tx, 8.1, tz), C.white, M.Fabric, DECOR)

	-- Gate arch at the back (towards the ring road): stone feet, posts, beam, roof, banners.
	local gz = 80
	local gate = U.model(template, "Gate")
	for _, sx in { -1, 1 } do
		local x = sx * 7.5
		P(gate, "Foot", Vector3.new(3, 2, 3), at(x, 0.8, gz), C.stone, M.Slate)
		P(gate, "Post", Vector3.new(1.6, 10.6, 1.6), at(x, 1.8 + 5.3, gz), C.woodDark, M.Wood)
		A(gate, "Banner", Vector3.new(0.25, 6.7, 2.2), at(sx * 9.1, 8.8, gz), M.Fabric, { CanCollide = false })
		P(gate, "Lantern", Vector3.new(0.9, 1.3, 0.9), at(sx * 10, 11.5, gz), C.lamp, M.Neon, DECOR)
	end
	P(gate, "Beam", Vector3.new(21, 1.3, 2), at(0, 12.75, gz), C.woodDark, M.Wood)
	P(gate, "CrossBar", Vector3.new(13.4, 0.8, 1.2), at(0, 10.4, gz), C.woodDark, M.Wood)
	for _, sz in { -1, 1 } do
		local rot = if sz > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.new()
		W(
			gate,
			"Roof",
			Vector3.new(22.4, 1.6, 1.9),
			at(0, 13.4 + 0.8, gz + sz * 0.95) * rot,
			nil,
			M.SmoothPlastic,
			{ CastShadow = true }
		)
	end
	local board = P(gate, "Board", Vector3.new(9, 2.2, 0.4), at(0, 8.9, gz), C.cream, M.WoodPlanks)
	label(board, Enum.NormalId.Back, "ДОБРО ПОЖАЛОВАТЬ!", C.woodDeep)
	label(board, Enum.NormalId.Front, "УДАЧНОЙ РЫБАЛКИ!", C.woodDeep)

	-- Mailbox beside the gate.
	P(gate, "MailPost", Vector3.new(0.4, 3.2, 0.4), at(11.5, 1.4, gz - 1), C.woodDark, M.Wood)
	A(gate, "Mailbox", Vector3.new(1.3, 1.3, 2.1), at(11.5, 3.6, gz - 1), nil, { CastShadow = true })

	-- Hedges along the side edges (the back and the pier side stay open).
	local hz0, hz1 = 4, 78
	for _, sx in { -1, 1 } do
		local x = sx * 42.4
		P(yard, "Hedge", Vector3.new(2.6, 2.6, hz1 - hz0), at(x, 1.0, (hz0 + hz1) / 2), C.hedge, M.Grass)
		cylZ(
			yard,
			"HedgeTop",
			2.6,
			hz1 - hz0 - 0.4,
			at(x, 2.3, (hz0 + hz1) / 2),
			C.hedgeTop,
			M.Grass,
			{ CastShadow = false }
		)
	end
end

------------------------------------------------------------------------------------------
-- Cabin, garden, campfire, flag, trees
------------------------------------------------------------------------------------------

local function buildCabin(template: any)
	local cabin = U.model(template, "Cabin")
	local cx, cz = -29, 33
	local w, d, wallH = 16, 13, 8.5
	local base = 0.6
	P(cabin, "Foundation", Vector3.new(w + 1, 1.4, d + 1), at(cx, -0.1, cz), C.stoneDark, M.Slate)
	P(cabin, "Walls", Vector3.new(w, wallH, d), at(cx, base + wallH / 2, cz), C.cream, M.WoodPlanks)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(
				cabin,
				"Corner",
				Vector3.new(0.9, wallH + 0.1, 0.9),
				at(cx + sx * w / 2, base + wallH / 2, cz + sz * d / 2),
				C.woodDark,
				M.Wood
			)
		end
	end
	-- Roof ridge along Z (gables face the lake and the road).
	local roofH = 6.2
	gableRoof(cabin, at(cx, base + wallH, cz) * CFrame.Angles(0, rad(90), 0), d + 0.9, w + 0.9, roofH, C.cream, {
		t = 0.8,
		eave = 1.8,
		ends = 1.2,
		ridge = C.woodDark,
	})
	-- Chimney through the far slope.
	local chx, chz = cx - 4.6, cz + 3.4
	local chTop = base + wallH + roofH * (1 - 4.6 / ((w + 0.9) / 2)) + 3.4
	local chBottom = base + wallH + 0.3
	P(cabin, "Chimney", Vector3.new(2.2, chTop - chBottom, 2.2), at(chx, (chTop + chBottom) / 2, chz), C.stone, M.Brick)
	P(cabin, "ChimneyCap", Vector3.new(2.8, 0.5, 2.8), at(chx, chTop + 0.25, chz), C.stoneDark, M.Slate)

	-- Door and windows with flower boxes on the patio side (+X), round window on the lake gable.
	local fx = cx + w / 2
	P(cabin, "DoorFrame", Vector3.new(0.3, 5.4, 3.6), at(fx + 0.15, base + 2.7, cz), C.white, M.Wood)
	A(cabin, "Door", Vector3.new(0.3, 4.8, 2.8), at(fx + 0.25, base + 2.45, cz), M.WoodPlanks)
	W(
		cabin,
		"Awning",
		Vector3.new(4.6, 1.1, 2.4),
		at(fx + 1.2, base + 5.4 + 0.55, cz) * CFrame.Angles(0, rad(-90), 0),
		nil,
		M.SmoothPlastic,
		{ CastShadow = true }
	)
	for _, z in { cz - 4.8, cz + 4.8 } do
		P(cabin, "WindowFrame", Vector3.new(0.3, 3.2, 3.2), at(fx + 0.15, base + 4.4, z), C.white, M.Wood)
		P(cabin, "Window", Vector3.new(0.3, 2.5, 2.5), at(fx + 0.25, base + 4.4, z), C.window, M.Glass)
		A(cabin, "FlowerBox", Vector3.new(0.9, 0.7, 3.4), at(fx + 0.55, base + 2.45, z), M.WoodPlanks)
		P(cabin, "FlowerBoxBloom", Vector3.new(0.7, 0.45, 3.1), at(fx + 0.55, base + 3.0, z), C.pink, M.Grass, DECOR)
	end
	local gz = cz - d / 2
	cylZ(cabin, "RoundWindowFrame", 3.4, 0.3, at(cx, base + wallH + 2.1, gz - 0.6), C.white, M.Wood)
	cylZ(cabin, "RoundWindow", 2.5, 0.3, at(cx, base + wallH + 2.1, gz - 0.7), C.window, M.Glass)
end

local function buildGarden(template: any)
	local garden = U.model(template, "Garden")
	local gx, gz = -24, 63
	for i, dz in { -3.2, 3.2 } do
		P(garden, "Bed", Vector3.new(15, 0.9, 3.6), at(gx, 0.15, gz + dz), C.soil, M.Ground)
		P(
			garden,
			"Crops",
			Vector3.new(14, 1, 2.2),
			at(gx, 1.0, gz + dz),
			if i == 1 then C.crops else C.leaf2,
			M.LeafyGrass,
			NO_COLLIDE
		)
	end
	ball(garden, "Pumpkin", 2.4, at(gx + 9.4, 1.0, gz), C.pumpkin, M.SmoothPlastic)
end

-- Campfire by the lake, with log seats and a few sparks. Returns the sparks attachment offset.
local function buildCampfire(template: any): any
	local camp = U.model(template, "Campfire")
	local fx, fz = -21, 12
	local ring = cylY(camp, "FireRing", 4.6, 0.8, at(fx, 0.1, fz), C.stoneDark, M.Slate)
	local sparks, sparksOffset = attachAt(ring, "SparksAttachment", at(fx, 1.6, fz))
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
		Color = R.ColorSequence.new(rgb(255, 214, 96), C.fire),
		LightEmission = 1,
	}, sparks)
	for _, r in { 30, -30 } do
		cylX(camp, "Log", 0.7, 3.4, at(fx, 0.85, fz) * CFrame.Angles(0, rad(r), 0), C.woodDark, M.Wood, DECOR)
	end
	local flame = P(
		camp,
		"Flame",
		Vector3.new(1.4, 1.4, 1.4),
		at(fx, 1.8, fz) * CFrame.Angles(rad(45), rad(45), 0),
		C.fire,
		M.Neon,
		DECOR
	)
	U.new("PointLight", { Range = 14, Brightness = 1.6, Color = C.fire, Shadows = false }, flame)
	for _, a in { 0, 110, 250 } do
		cylX(camp, "LogSeat", 1.5, 4.4, at(fx, 0.55, fz) * CFrame.Angles(0, rad(a), 0) * at(0, 0, 5.2), C.wood, M.Wood)
	end
	return sparksOffset
end

-- Little fish stall facing the patio: counter, posts, accent awning, fish on ice.
local function buildStall(template: any)
	local stall = U.model(template, "Stall")
	local sx, sz = 27, 34
	local counter = P(stall, "Counter", Vector3.new(2.6, 2.6, 7), at(sx, 1.1, sz), C.deck, M.WoodPlanks)
	label(counter, Enum.NormalId.Left, "РЫБА", C.cream)
	P(stall, "Fish", Vector3.new(1.4, 0.45, 5), at(sx - 0.1, 2.62, sz), C.steel, M.SmoothPlastic, DECOR)
	for _, dz in { -3.2, 3.2 } do
		P(stall, "Post", Vector3.new(0.5, 6.4, 0.5), at(sx + 1.1, 3.05, sz + dz), C.woodDark, M.Wood)
	end
	W(
		stall,
		"Awning",
		Vector3.new(8, 1.4, 4.2),
		at(sx - 0.2, 6.9, sz) * CFrame.Angles(0, rad(90), 0),
		nil,
		M.Fabric,
		{ CastShadow = true }
	)
end

local function buildFlag(template: any)
	local flag = U.model(template, "Flag")
	local fx, fz = 13.5, SPAWN_Z + 3
	local poleBottom, poleTop = 1.2, 26
	P(flag, "Base", Vector3.new(3, 1.6, 3), at(fx, 0.4, fz), C.stone, M.Slate)
	local poleH = poleTop - poleBottom
	local pole = cylY(flag, "Pole", 0.6, poleH, at(fx, (poleTop + poleBottom) / 2, fz), C.steel, M.Metal)
	ball(flag, "Top", 1.1, at(fx, poleTop + 0.4, fz), C.gold, M.SmoothPlastic, DECOR)
	-- Big waving banner (two panels at a slight angle).
	local clothTop = poleTop - 0.5
	local h = 5.8
	A(
		flag,
		"Cloth",
		Vector3.new(5.6, h, 0.25),
		at(fx + 0.3 + 2.8, clothTop - h / 2, fz),
		M.Fabric,
		{ CanCollide = false }
	)
	A(
		flag,
		"ClothTip",
		Vector3.new(3.8, h * 0.92, 0.25),
		at(fx + 5.9, clothTop - h / 2 - 0.15, fz) * CFrame.Angles(0, rad(22), 0) * at(1.85, 0, 0),
		M.Fabric,
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
	U.new("TextLabel", {
		Name = "OwnerLabel",
		Size = UDim2.fromScale(1, 0.6),
		BackgroundTransparency = 1,
		Text = "Свободно",
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = C.white,
		TextStrokeColor3 = C.black,
		TextStrokeTransparency = 0.2,
	}, sign)
	U.new("TextLabel", {
		Name = "BaseLabel",
		Position = UDim2.fromScale(0, 0.6),
		Size = UDim2.fromScale(1, 0.4),
		BackgroundTransparency = 1,
		Text = "База",
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = C.white,
		TextStrokeColor3 = C.black,
		TextStrokeTransparency = 0.2,
	}, sign)
	return signOffset
end

local function roundTree(parent: any, x: number, z: number, s: number)
	cylY(parent, "Trunk", 1.5 * s, 7 * s, at(x, 3.3 * s, z), C.woodDark, M.Wood)
	ball(parent, "Leaves", 8.5 * s, at(x, 8.6 * s, z), C.leaf1, M.Grass, NO_COLLIDE)
	ball(parent, "Leaves", 6 * s, at(x + 2.6 * s, 7.4 * s, z + 1.4 * s), C.leaf3, M.Grass, NO_COLLIDE)
	ball(parent, "Leaves", 5.4 * s, at(x - 2.2 * s, 10.6 * s, z - 1.2 * s), C.leaf2, M.Grass, NO_COLLIDE)
end

local function pineTree(parent: any, x: number, z: number, s: number)
	cylY(parent, "Trunk", 1.3 * s, 4 * s, at(x, 1.6 * s, z), C.woodDark, M.Wood)
	cylY(parent, "Needles", 8 * s, 3 * s, at(x, 4.6 * s, z), C.pine1, M.Grass, NO_COLLIDE)
	cylY(parent, "Needles", 5.8 * s, 3 * s, at(x, 7.4 * s, z), C.pine2, M.Grass, NO_COLLIDE)
	cylY(parent, "Needles", 3.4 * s, 3 * s, at(x, 10.2 * s, z), C.pine1, M.Grass, NO_COLLIDE)
end

local function buildTrees(template: any)
	local trees = U.model(template, "Trees")
	roundTree(trees, -36, 75, 1.45)
	roundTree(trees, 34, 47, 1.35)
	roundTree(trees, 32, 72, 1.45)
	pineTree(trees, -36, 9, 1.3)
	pineTree(trees, 33, 14, 1.4)
end

------------------------------------------------------------------------------------------

return function(game: any, mapCfg: any)
	local serverStorage = game:GetService("ServerStorage")
	local template = U.new("Model", { Name = "BaseTemplate" }, serverStorage)

	local root = U.marker(template, "Root", Vector3.new(2, 0.2, 2), CFrame.new(0, 0, 0))
	template.PrimaryPart = root

	local waterY = mapCfg.WaterTop - mapCfg.GroundTop -- local water surface (-4)
	local pileBottom = waterY - 18 -- below the lake bed under the pier

	buildPier(template, pileBottom)
	buildPlatform(template, pileBottom)
	buildPavilion(template)
	buildTank(template)
	buildBoat(template, waterY)
	buildDogHouse(template)
	buildDog(template)
	buildYard(template)
	buildCabin(template)
	buildGarden(template)
	local sparksOffset = buildCampfire(template)
	buildStall(template)
	local signOffset = buildFlag(template)
	buildTrees(template)

	local count = 0
	for _, d in template:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	return {
		template = template,
		partCount = count,
		-- Verified by the post-build self-check in tools/build.luau (path from the template root).
		expectedAttachments = {
			{ root = "template", path = { "Flag", "Pole", "SignAttachment" }, offset = signOffset },
			{ root = "template", path = { "Tank", "Glass", "PromptAttachment" }, offset = PROMPT_OFFSET },
			{ root = "template", path = { "Campfire", "FireRing", "SparksAttachment" }, offset = sparksOffset },
		},
	}
end
