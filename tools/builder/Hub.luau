--[[
	Hub — the central island village «Рыбацкая гавань» (Workspace.Map.Hub): the social hub
	where every player buys upgrades and sells fish.

	Usage (from Map.luau):  local hub = buildHub(map, cfg, gen?)
	  parent  Workspace.Map
	  cfg     MapConfig
	  gen     optional WorldGen (gen:surfaceAt(x, z)): beach props stand on the real terrain.
	          Without it the island profile of WorldGen.naturalHeight is reproduced here.
	Returns { model = Model "Hub", partCount = number, expectedAttachments = {...} }.

	Layout (angle θ in degrees, 0 = +Z; θ → (sin θ, 0, cos θ)); the plaza is flat at GroundTop:
	  * centre      octagonal fountain with a golden fish; HubSpawn on its −Z side, facing +Z
	  * walkways    along the 4 axes (the bridges land there): nothing within |lateral| < 6
	                from r = 20 outwards; light paving strips mark them, lamp pairs at r = 41
	  * 45°         Shop «МАГАЗИН»: 2-storey timber house, striped awning, fish on the roof
	  * 135°        Workshop «МАСТЕРСКАЯ»: stone forge with a gear sign on the ridge
	  * 315°        Fish market «СКУПКА РЫБЫ»: open stall with ice, fish, scales, canopy
	  * 225°        café terrace + notice board on the plaza, lighthouse on the shore
	  * beach ring  palms, 2 docks with 3 moored boats, rocks, gulls
	Every building is modelled in a local frame (U.polarCFrame) whose −Z faces the plaza centre,
	so the customer side of counters is local −Z.
]]

local U = require("./Util")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Enum = U.Enum
local rgb = U.rgb
local V = Vector3.new
local M = Enum.Material

local rad, pi = math.rad, math.pi

--------------------------------------------------------------------------------
-- Palette: warm wood and cream walls, coral / teal roofs, sea blues, gold accents.
--------------------------------------------------------------------------------

local C = {
	woodLight = rgb(228, 176, 110),
	wood = rgb(190, 130, 76),
	woodDark = rgb(126, 82, 50),
	beam = rgb(88, 58, 40),
	plaster = rgb(253, 240, 214),
	sandstone = rgb(222, 200, 160),
	stone = rgb(176, 170, 158),
	stoneLight = rgb(232, 226, 210),
	stoneDark = rgb(124, 118, 110),
	paving = rgb(238, 222, 186),
	pavingDark = rgb(176, 150, 118),
	terracotta = rgb(214, 110, 74),
	roofRed = rgb(230, 86, 66),
	roofRedDark = rgb(186, 60, 50),
	roofTeal = rgb(40, 164, 166),
	roofTealDark = rgb(26, 124, 134),
	red = rgb(234, 66, 60),
	white = rgb(252, 250, 244),
	cream = rgb(255, 236, 196),
	yellow = rgb(255, 208, 64),
	gold = rgb(255, 190, 40),
	goldLight = rgb(255, 224, 120),
	orange = rgb(255, 142, 48),
	teal = rgb(32, 180, 172),
	blue = rgb(52, 140, 232),
	navy = rgb(34, 56, 104),
	pink = rgb(255, 120, 164),
	purple = rgb(150, 98, 222),
	green = rgb(96, 196, 84),
	leaf = rgb(76, 182, 70),
	leafDark = rgb(46, 138, 62),
	trunk = rgb(166, 118, 70),
	glass = rgb(156, 214, 240),
	ice = rgb(212, 244, 255),
	iron = rgb(54, 60, 72),
	silver = rgb(200, 208, 218),
	water = rgb(80, 196, 240),
	skin = rgb(255, 204, 150),
	lamp = rgb(255, 216, 130),
	ink = rgb(28, 28, 34),
	rope = rgb(120, 96, 70),
}

local PENNANTS = { C.red, C.yellow, C.teal, C.white, C.blue, C.orange }

-- Small or thin parts: no shadow. GHOST: also not solid (pennants, smoke, water jets).
local SMALL = { CastShadow = false }
local GHOST = { CastShadow = false, CanCollide = false }

--------------------------------------------------------------------------------
-- Part helpers
--------------------------------------------------------------------------------

local function with(base: { [string]: any }, extra: { [string]: any }?): { [string]: any }
	local t = table.clone(base)
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end

local function blk(parent: any, name: string, size: any, cf: any, color: any, material: any?, extra: any?): any
	return U.part(parent, name, size, cf, color, material, extra)
end

local function wdg(parent: any, name: string, size: any, cf: any, color: any, material: any?, extra: any?): any
	return U.wedge(parent, name, size, cf, color, material, extra)
end

-- CornerWedgePart: rectangular base, apex above the (+X, −Z) corner.
local function cornerWedge(parent: any, name: string, size: any, cf: any, color: any, extra: any?): any
	local props = with({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = M.SmoothPlastic,
		Anchored = true,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		CanTouch = false,
	}, extra)
	U.partCount += 1
	return U.new("CornerWedgePart", props, parent)
end

-- Cylinder along the local X axis of cf.
local function cyl(parent: any, name: string, d: number, len: number, cf: any, color: any, material: any?, extra: any?): any
	return U.part(parent, name, V(len, d, d), cf, color, material, with({ Shape = Enum.PartType.Cylinder }, extra))
end

local UPRIGHT = CFrame.Angles(0, 0, rad(90))
local FORWARD = CFrame.Angles(0, rad(90), 0)

-- Cylinder along the local Y axis of cf (a post, a disc lying flat).
local function cylUp(parent: any, name: string, d: number, h: number, cf: any, color: any, material: any?, extra: any?): any
	return cyl(parent, name, d, h, cf * UPRIGHT, color, material, extra)
end

-- Cylinder along the local Z axis of cf (a disc facing the front).
local function cylFwd(parent: any, name: string, d: number, t: number, cf: any, color: any, material: any?, extra: any?): any
	return cyl(parent, name, d, t, cf * FORWARD, color, material, extra)
end

local function ball(parent: any, name: string, d: number, cf: any, color: any, material: any?, extra: any?): any
	return U.part(parent, name, V(d, d, d), cf, color, material, with({ Shape = Enum.PartType.Ball }, extra))
end

-- Block of square section t from world point a to world point b (not vertical).
local function beam(parent: any, name: string, a: any, b: any, t: number, color: any, material: any?, extra: any?): any
	return U.part(parent, name, V(t, t, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), color, material, extra)
end

--[[
	Roof slab lying on the line from `eave` to `ridge` (points in F's local space, the slab's
	underside touches that line), `width` along edgeDir. Returns the part and frameAt(t, h):
	the slab's orientation at fraction t from eave (0) to ridge (1), h above the underside.
]]
local function roofPlane(
	parent: any,
	name: string,
	F: any,
	eave: any,
	ridge: any,
	edgeDir: any,
	width: number,
	thick: number,
	extEave: number,
	extRidge: number,
	color: any
)
	local up = (ridge - eave).Unit
	local x = edgeDir.Unit
	local n = up:Cross(x)
	if n.Y < 0 then
		x = -x
		n = -n
	end
	local function frameAt(t: number, h: number): any
		return F * CFrame.fromMatrix(eave:Lerp(ridge, t) + n * h, x, n, up)
	end
	local len = (ridge - eave).Magnitude
	local mid = (len + extRidge - extEave) / 2 / len
	local part = U.part(parent, name, V(width, thick, len + extEave + extRidge), frameAt(mid, thick / 2), color)
	return part, frameAt
end

-- Painted text on one face of a part (U.FONT supports Cyrillic).
local function signText(part: any, face: any, text: string, color: any, stroke: any, box: { number }?)
	local gui = U.new("SurfaceGui", {
		Name = "SignGui",
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0,
	}, part)
	local b = box or { 0.5, 0.5, 0.92, 0.82 }
	U.new("TextLabel", {
		Name = "Text",
		AnchorPoint = U.Vector2.new(0.5, 0.5),
		Position = U.UDim2.fromScale(b[1], b[2]),
		Size = U.UDim2.fromScale(b[3], b[4]),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = color,
		TextStrokeColor3 = stroke,
		TextStrokeTransparency = 0,
	}, gui)
	return gui
end

local function pointLight(part: any, color: any, range: number, brightness: number)
	return U.new("PointLight", { Color = color, Range = range, Brightness = brightness, Shadows = false }, part)
end

--------------------------------------------------------------------------------
-- Small props
--------------------------------------------------------------------------------

-- Blocky villager standing on cf (feet), facing cf's −Z.
local function villager(parent: any, name: string, cf: any, look: { [string]: any }): any
	local m = U.model(parent, name)
	local function p(n: string, size: any, x: number, y: number, z: number, color: any, extra: any?)
		return blk(m, n, size, cf * CFrame.new(x, y, z), color, nil, extra)
	end
	p("Legs", V(2, 2, 1), 0, 1, 0, look.pants)
	local torso = p("Torso", V(2, 2, 1), 0, 3, 0, look.shirt)
	p("ArmLeft", V(1, 2, 1), -1.5, 3, 0, look.shirt)
	p("ArmRight", V(1, 2, 1), 1.5, 3, 0, look.shirt)
	p("Head", V(1.6, 1.6, 1.6), 0, 4.8, 0, C.skin)
	p("EyeLeft", V(0.25, 0.4, 0.1), -0.35, 4.95, -0.85, C.ink, SMALL)
	p("EyeRight", V(0.25, 0.4, 0.1), 0.35, 4.95, -0.85, C.ink, SMALL)
	p("Apron", V(1.7, 2.6, 0.2), 0, 2.6, -0.6, look.apron, SMALL)
	p("HatBrim", V(2.1, 0.3, 2.1), 0, 5.75, 0, look.hat, SMALL)
	p("HatTop", V(1.6, 0.8, 1.6), 0, 6.3, 0, look.hat, SMALL)
	m.PrimaryPart = torso
	return m
end

local function barrel(parent: any, cf: any, color: any?): any
	return cylUp(parent, "Barrel", 2, 2.4, cf * CFrame.new(0, 1, 0), color or C.woodDark, M.Wood)
end

local function crate(parent: any, cf: any, s: number?): any
	local size = s or 2.2
	return blk(parent, "Crate", V(size, size, size), cf * CFrame.new(0, size / 2 - 0.1, 0), C.wood, M.WoodPlanks)
end

-- Street lamp at a ground point (dark iron post, warm neon lantern).
local function lampPost(parent: any, ground: any, withLight: boolean)
	local m = U.model(parent, "Lamp")
	local base = CFrame.new(ground)
	cylUp(m, "Base", 1.5, 1, base * CFrame.new(0, 0.3, 0), C.iron, M.Metal)
	cylUp(m, "Post", 0.5, 8.1, base * CFrame.new(0, 4.75, 0), C.iron, M.Metal, SMALL)
	local lantern = blk(
		m,
		"Lantern",
		V(1.3, 1.6, 1.3),
		base * CFrame.new(0, 9.55, 0) * CFrame.Angles(0, rad(45), 0),
		C.lamp,
		M.Neon,
		SMALL
	)
	blk(m, "Cap", V(1.9, 0.45, 1.9), base * CFrame.new(0, 10.55, 0) * CFrame.Angles(0, rad(45), 0), C.iron, M.Metal, SMALL)
	if withLight then
		pointLight(lantern, C.lamp, 14, 1.2)
	end
	m.PrimaryPart = lantern
end

-- Bench on cf (ground), the sitter faces cf's −Z.
local function bench(parent: any, cf: any)
	local m = U.model(parent, "Bench")
	blk(m, "Seat", V(5, 0.4, 1.8), cf * CFrame.new(0, 1.7, 0), C.woodLight, M.WoodPlanks)
	blk(m, "Back", V(5, 1.6, 0.35), cf * CFrame.new(0, 2.65, 0.75) * CFrame.Angles(rad(-8), 0, 0), C.woodLight, M.WoodPlanks)
	for _, sx in { -1, 1 } do
		blk(m, "Leg", V(0.4, 1.8, 1.7), cf * CFrame.new(sx * 2.0, 0.7, 0), C.iron, M.Metal, SMALL)
	end
end

-- Round stone planter with a bush and flowers.
local function planter(parent: any, ground: any, flowers: { any })
	local m = U.model(parent, "Planter")
	local base = CFrame.new(ground)
	cylUp(m, "Pot", 3.6, 1.3, base * CFrame.new(0, 0.45, 0), C.terracotta, M.SmoothPlastic)
	ball(m, "Bush", 2.8, base * CFrame.new(0, 1.6, 0), C.leaf)
	for i, color in flowers do
		local a = rad(i * 360 / #flowers + 20)
		ball(m, "Flower", 1.0, base * CFrame.new(1.05 * math.sin(a), 2.15, 1.05 * math.cos(a)), color, nil, SMALL)
	end
end

-- Palm: 2 bending trunk segments leaning towards cf's +Z, 5 drooping leaves, coconuts.
local function palm(parent: any, ground: any, yaw: number, scale: number)
	local m = U.model(parent, "Palm")
	local s = scale
	local cf = CFrame.new(ground) * CFrame.Angles(0, rad(yaw), 0) * CFrame.new(0, -1.5 * s, 0)
	local lengths, widths, tilts = { 7.5, 7 }, { 1.6, 1.3 }, { 6, 12 }
	for i = 1, 2 do
		cf = cf * CFrame.Angles(rad(tilts[i]), 0, 0)
		local L = lengths[i] * s
		blk(m, "Trunk", V(widths[i] * s, L + 0.3 * s, widths[i] * s), cf * CFrame.new(0, L / 2, 0), C.trunk, M.Wood)
		cf = cf * CFrame.new(0, L, 0)
	end
	local top = CFrame.new(cf.Position) * CFrame.Angles(0, rad(yaw), 0)
	ball(m, "Coconuts", 1.8 * s, top * CFrame.new(0, -0.5 * s, 0), C.woodDark)
	for k = 0, 4 do
		local leafCF = top
			* CFrame.Angles(0, rad(k * 72 + 15), 0)
			* CFrame.Angles(rad(24 + (k % 2) * 8), 0, 0)
			* CFrame.new(0, 0, 3.6 * s)
			* CFrame.Angles(0, pi, 0)
		wdg(m, "Leaf", V(2.4 * s, 0.6 * s, 7.6 * s), leafCF, if k % 2 == 0 then C.leaf else C.leafDark, nil, GHOST)
	end
end

-- Café table under a 4-colour umbrella.
local function umbrellaTable(parent: any, ground: any, colors: { any })
	local m = U.model(parent, "CafeTable")
	local base = CFrame.new(ground)
	cylUp(m, "Pole", 0.35, 8.2, base * CFrame.new(0, 3.9, 0), C.white, nil, SMALL)
	cylUp(m, "Table", 3.6, 0.3, base * CFrame.new(0, 2.6, 0), C.white)
	local apex = base * CFrame.new(0, 8.0, 0)
	for k = 0, 3 do
		cornerWedge(
			m,
			"Canopy",
			V(3.8, 1.7, 3.8),
			apex * CFrame.Angles(0, rad(k * 90), 0) * CFrame.new(-1.9, -0.85, 1.9),
			colors[k % 2 + 1],
			{ CastShadow = true }
		)
	end
	for _, sx in { -1, 1 } do
		cylUp(m, "Stool", 1.4, 1.6, base * CFrame.new(sx * 2.7, 0.6, 0.4), C.teal, nil, SMALL)
	end
end

-- String of triangular pennants from a to b (world points), sagging in the middle.
local function bunting(parent: any, a: any, b: any, sag: number, count: number, offset: number)
	local m = U.model(parent, "Bunting")
	local mid = (a + b) / 2 - V(0, sag, 0)
	beam(m, "Rope", a, mid, 0.18, C.rope, nil, GHOST)
	beam(m, "Rope", mid, b, 0.18, C.rope, nil, GHOST)
	for i = 1, count do
		local t = i / (count + 1)
		local p, dir
		if t < 0.5 then
			p, dir = a:Lerp(mid, t * 2), (mid - a).Unit
		else
			p, dir = mid:Lerp(b, (t - 0.5) * 2), (b - mid).Unit
		end
		-- Wedge flipped upside down: full top edge along the rope, point hanging below.
		local cf = CFrame.lookAt(p, p + dir) * CFrame.new(0, -0.85, 0) * CFrame.Angles(0, 0, pi)
		wdg(m, "Pennant", V(0.12, 1.6, 1.4), cf, PENNANTS[(i + offset) % #PENNANTS + 1], nil, GHOST)
	end
end

-- Gull sitting on cf (feet), looking along cf's −Z.
local function gull(parent: any, cf: any)
	local m = U.model(parent, "Gull")
	blk(m, "Body", V(0.7, 0.6, 1.4), cf * CFrame.new(0, 0.4, 0.1), C.white, nil, SMALL)
	blk(m, "Wings", V(0.8, 0.25, 1.1), cf * CFrame.new(0, 0.75, 0.25), rgb(150, 160, 175), nil, SMALL)
	blk(m, "Head", V(0.5, 0.5, 0.55), cf * CFrame.new(0, 0.85, -0.55), C.white, nil, SMALL)
	blk(m, "Beak", V(0.18, 0.15, 0.45), cf * CFrame.new(0, 0.8, -1.0), C.orange, nil, SMALL)
end

--[[
	Big decorative fish (signs, statue): frame = body centre, head towards +X, broadside
	facing ±Z, s = scale (s = 1 → about 14 studs long). 10 parts.
]]
local function signFish(m: any, fish: any, s: number, look: { [string]: any }): any
	local extra = look.extra
	local finMaterial = look.finMaterial
	local function fp(n: string, size: any, cf: any, color: any, material: any?, ex: any?): any
		return blk(m, n, size * s, fish * cf, color, material, ex or extra)
	end
	local body = fp("FishBody", V(6.4, 4.6, 1.4), CFrame.new(), look.body)
	fp("FishHead", V(2.6, 3.8, 1.3), CFrame.new(4.4 * s, 0.1 * s, 0), look.body)
	fp("FishSnout", V(1.2, 2.4, 1.2), CFrame.new(6.2 * s, -0.1 * s, 0), look.body)
	fp("FishBelly", V(6.6, 1.3, 1.5), CFrame.new(0.4 * s, -1.6 * s, 0), look.belly)
	fp("FishTailBase", V(1.8, 2.8, 1.2), CFrame.new(-4 * s, 0, 0), look.body)
	fp("FishTail", V(3.2, 1.6, 1), CFrame.new(-5.6 * s, 1.3 * s, 0) * CFrame.Angles(0, 0, rad(-35)), look.fins, finMaterial)
	fp("FishTail", V(3.2, 1.6, 1), CFrame.new(-5.6 * s, -1.3 * s, 0) * CFrame.Angles(0, 0, rad(35)), look.fins, finMaterial)
	wdg(m, "FishFin", V(0.9, 2, 3.6) * s, fish * CFrame.new(0, 3.2 * s, 0) * CFrame.Angles(0, rad(90), 0), look.fins, finMaterial, extra)
	ball(m, "FishEye", 1.7 * s, fish * CFrame.new(4.7 * s, 0.7 * s, 0), C.white, nil, SMALL)
	fp("FishPupil", V(0.7, 0.8, 1.9), CFrame.new(5 * s, 0.7 * s, 0), C.ink, nil, SMALL)
	return body
end

--[[
	Welcome gate over a walkway at `angle`, radius r: two timber pillars, a cross beam with
	a roofed sign on top (text on both faces) and two hanging lanterns. 8 parts.
]]
local function gateArch(parent: any, angle: number, r: number, G: number)
	local m = U.model(parent, "Gate")
	local A = U.polarCFrame(angle, r, G)
	local function at(x: number, y: number, z: number): any
		return A * CFrame.new(x, y, z)
	end
	for _, sx in { -1, 1 } do
		blk(m, "Pillar", V(1.8, 13, 1.8), at(sx * 7.2, 6.3, 0), C.beam, M.Wood)
		blk(m, "Lantern", V(1.2, 1.9, 1.2), at(sx * 8.6, 10.35, 0), C.lamp, M.Neon, SMALL)
	end
	local beamPart = blk(m, "Beam", V(18.6, 1.4, 2.2), at(0, 12, 0), C.woodDark, M.Wood)
	local sign = blk(m, "Sign", V(12, 3.2, 0.6), at(0, 14.3, 0), C.blue)
	signText(sign, Enum.NormalId.Back, "РЫБАЦКАЯ ГАВАНЬ", C.yellow, C.navy) -- outward: arriving players
	signText(sign, Enum.NormalId.Front, "ДОБРО ПОЖАЛОВАТЬ!", C.white, C.navy) -- towards the plaza
	wdg(m, "SignRoof", V(13.6, 1.3, 1.5), at(0, 16.55, -0.75), C.roofRed)
	wdg(m, "SignRoof", V(13.6, 1.3, 1.5), at(0, 16.55, 0.75) * CFrame.Angles(0, pi, 0), C.roofRed)
	m.PrimaryPart = beamPart
end

--------------------------------------------------------------------------------
-- Shop «МАГАЗИН»: honey-plank ground floor with a serving window and striped awning,
-- jettied cream upper floor, coral roof with a roof sign and a giant fish on the ridge.
--------------------------------------------------------------------------------

local function buildShop(hub: any, F: any)
	local m = U.model(hub, "Shop")
	local function at(x: number, y: number, z: number): any
		return F * CFrame.new(x, y, z)
	end

	-- Ground floor (outer 22 × 14), walls sunk 0.5 into the plaza.
	blk(m, "WallBack", V(22, 10.5, 1), at(0, 4.75, 6.5), C.woodLight, M.WoodPlanks)
	local sideL = blk(m, "WallLeft", V(1, 10.5, 12), at(-10.5, 4.75, 0), C.woodLight, M.WoodPlanks)
	local sideR = blk(m, "WallRight", V(1, 10.5, 12), at(10.5, 4.75, 0), C.woodLight, M.WoodPlanks)
	signText(sideL, Enum.NormalId.Left, "МАГАЗИН", C.white, C.beam, { 0.5, 0.42, 0.9, 0.3 })
	signText(sideR, Enum.NormalId.Right, "МАГАЗИН", C.white, C.beam, { 0.5, 0.42, 0.9, 0.3 })
	blk(m, "PierLeft", V(3, 10.5, 1), at(-9.5, 4.75, -6.5), C.woodLight, M.WoodPlanks)
	blk(m, "PierRight", V(3, 10.5, 1), at(9.5, 4.75, -6.5), C.woodLight, M.WoodPlanks)
	blk(m, "Lintel", V(16, 2.4, 1), at(0, 8.8, -6.5), C.woodLight, M.WoodPlanks)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			blk(m, "CornerPost", V(1.2, 10.5, 1.2), at(sx * 10.9, 4.75, sz * 6.9), C.beam, M.Wood)
		end
	end
	local floor = blk(m, "Floor", V(20, 0.4, 12), at(0, 0, 0), C.wood, M.WoodPlanks, SMALL)
	blk(m, "Porch", V(20, 0.5, 6), at(0, 0, -10.5), C.wood, M.WoodPlanks, SMALL)

	-- Serving counter in the front window (stage 5 puts the shop prompt on its attachment).
	local counter = blk(m, "Counter", V(16, 3.8, 2), at(0, 1.4, -6.5), C.woodDark, M.WoodPlanks)
	blk(m, "CounterTop", V(17, 0.4, 2.8), at(0, 3.5, -6.7), C.teal)
	blk(m, "CounterPanel", V(13, 2, 0.3), at(0, 1.6, -7.6), C.cream, nil, SMALL)
	-- Attachments must be placed via CFrame (Lune drops Attachment.Position).
	U.new("Attachment", { Name = "ShopPromptAttachment", CFrame = CFrame.new(0, 2.2, -2.8) }, counter)

	-- Upper floor: overhanging cream plaster on a dark timber frame.
	blk(m, "FloorBeam", V(23.4, 0.8, 15.4), at(0, 10.2, 0), C.beam, M.Wood)
	blk(m, "UpperFloor", V(22.6, 7.4, 14.6), at(0, 14.3, 0), C.plaster)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			blk(m, "UpperPost", V(1, 7.6, 1), at(sx * 11.3, 14.3, sz * 7.3), C.beam, M.Wood)
		end
	end
	blk(m, "EavePlate", V(23.6, 0.6, 15.6), at(0, 18.3, 0), C.beam, M.Wood)
	for _, x in { -6.5, 6.5 } do
		blk(m, "WindowFrame", V(3.4, 4.2, 0.4), at(x, 14.4, -7.4), C.beam, M.Wood, SMALL)
		blk(m, "WindowGlass", V(2.6, 3.4, 0.4), at(x, 14.4, -7.5), C.glass, nil, SMALL)
		blk(m, "Mullion", V(0.3, 3.4, 0.2), at(x, 14.4, -7.75), C.beam, nil, SMALL)
		blk(m, "Transom", V(2.6, 0.3, 0.22), at(x, 14.6, -7.76), C.beam, nil, SMALL)
		blk(m, "Shutter", V(1.3, 4.2, 0.3), at(x - 2.45, 14.4, -7.45), C.teal, nil, SMALL)
		blk(m, "Shutter", V(1.3, 4.2, 0.3), at(x + 2.45, 14.4, -7.45), C.teal, nil, SMALL)
		blk(m, "FlowerBox", V(3.6, 0.8, 1.1), at(x, 11.9, -7.85), C.woodDark, M.WoodPlanks, SMALL)
		ball(m, "Flower", 1, at(x - 0.8, 12.4, -7.85), C.pink, nil, SMALL)
		ball(m, "Flower", 1, at(x + 0.8, 12.4, -7.85), C.yellow, nil, SMALL)
	end
	-- Lifebuoy between the windows.
	local ring = at(0, 14.6, -7.55)
	cylFwd(m, "Lifebuoy", 3.4, 0.5, ring, C.red, nil, SMALL)
	cylFwd(m, "LifebuoyHole", 1.5, 0.1, ring * CFrame.new(0, 0, -0.3), C.plaster, nil, SMALL)
	for k = 0, 3 do
		blk(
			m,
			"LifebuoyBand",
			V(0.95, 0.75, 0.6),
			ring * CFrame.Angles(0, 0, rad(45 + 90 * k)) * CFrame.new(1.22, 0, 0),
			C.white,
			nil,
			SMALL
		)
	end

	-- Gable roof, ridge along local X.
	wdg(m, "Gable", V(22.6, 7, 7.3), at(0, 22.1, -3.65), C.plaster)
	wdg(m, "Gable", V(22.6, 7, 7.3), at(0, 22.1, 3.65) * CFrame.Angles(0, pi, 0), C.plaster)
	for _, sx in { -1, 1 } do
		cyl(m, "GableWindow", 2.6, 0.3, at(sx * 11.35, 21.3, 0), C.beam, nil, SMALL)
	end
	for _, sz in { -1, 1 } do
		local _, frameAt =
			roofPlane(m, "Roof", F, V(0, 18.6, sz * 7.3), V(0, 25.6, 0), V(1, 0, 0), 25.2, 0.8, 1.6, 0.45, C.roofRed)
		for _, t in { 0.28, 0.64 } do
			blk(m, "RoofTiles", V(25.4, 0.3, 0.8), frameAt(t, 0.95), C.roofRedDark, nil, SMALL)
		end
	end
	blk(m, "Ridge", V(25.8, 0.8, 1.8), at(0, 26.2, 0), C.roofRedDark)
	blk(m, "Chimney", V(2.4, 7, 2.4), at(6.5, 24.6, 3.6), C.terracotta, M.Brick)
	blk(m, "ChimneyCap", V(3, 0.6, 3), at(6.5, 28.4, 3.6), C.stoneDark, nil, SMALL)

	-- Roof sign and the giant fish on the ridge (seen from the plaza and from the lake).
	blk(m, "SignBacker", V(16.8, 5.2, 0.4), at(0, 23, -5.15), C.gold, M.Neon) -- glowing frame
	local sign = blk(m, "Sign", V(16, 4.4, 0.6), at(0, 23, -5.6), C.blue)
	signText(sign, Enum.NormalId.Front, "МАГАЗИН", C.yellow, C.navy)
	blk(m, "FishPost", V(0.8, 3, 0.8), at(0, 27.6, 0), C.beam, nil, SMALL)
	signFish(m, F * CFrame.new(0, 31.2, 0), 1, { body = C.blue, belly = C.ice, fins = C.yellow })

	-- Striped awning over the serving window (back edge tucked into the lintel), valance flaps.
	local slope = math.atan2(2.35, 5.6)
	for i = 0, 6 do
		local x = -9 + 18 / 7 * (i + 0.5)
		local color = if i % 2 == 0 then C.red else C.white
		blk(
			m,
			"Awning",
			V(18 / 7, 0.3, 6.1),
			at(x, 8.58, -9.6) * CFrame.Angles(-slope, 0, 0),
			color,
			nil,
			{ CastShadow = true }
		)
		blk(m, "Valance", V(18 / 7, 1, 0.2), at(x, 7.0, -12.45), color, nil, SMALL)
	end
	for _, sx in { -1, 1 } do
		beam(m, "AwningBracket", (at(sx * 8.8, 6, -6.8)).Position, (at(sx * 8.8, 7.5, -12.2)).Position, 0.3, C.iron, M.Metal, SMALL)
	end

	-- Shopkeeper and the goods behind him.
	villager(m, "Shopkeeper", at(0, 0.2, -4), { shirt = C.orange, pants = C.navy, apron = C.white, hat = C.blue })
	blk(m, "Shelf", V(14, 0.4, 1.6), at(0, 5.6, 5.2), C.woodDark, M.Wood, SMALL)
	local goods = {
		{ -4.5, 5.8, V(1.4, 1.6, 1), C.red },
		{ -1.5, 5.8, V(1.8, 1.1, 1), C.yellow },
		{ 2.5, 5.8, V(1.2, 1.8, 1), C.purple },
	}
	for _, g in goods do
		blk(m, "Goods", g[3], at(g[1], g[2] + g[3].Y / 2, 5.2), g[4], nil, SMALL)
	end

	-- A barrel of fishing rods for sale and crates by the front corners.
	local rods = at(-11.6, 0, -10)
	barrel(m, rods)
	for i, spec in { { C.red, 8, 5, 0.3, 0.3 }, { C.yellow, -7, 6, -0.4, 0.1 }, { C.teal, 3, -9, 0, -0.4 } } do
		cylUp(
			m,
			"Rod",
			0.25,
			7,
			rods * CFrame.new(spec[4], 0.6, spec[5]) * CFrame.Angles(rad(spec[3]), 0, rad(spec[2])) * CFrame.new(0, 3.5, 0),
			spec[1],
			nil,
			SMALL
		)
		local _ = i
	end
	crate(m, at(11.7, 0, -9.8) * CFrame.Angles(0, rad(12), 0))
	crate(m, at(11.7, 2.1, -9.8) * CFrame.Angles(0, rad(-10), 0), 1.7)
	barrel(m, at(12.3, 0, -6.4))

	m.PrimaryPart = floor
	return m
end

--------------------------------------------------------------------------------
-- Workshop «МАСТЕРСКАЯ»: stone ground floor with an open work bay, plank upper floor,
-- teal front-gable roof with a big gear and crossed rod + wrench, smoking forge chimney.
--------------------------------------------------------------------------------

local function buildWorkshop(hub: any, F: any)
	local m = U.model(hub, "Workshop")
	local function at(x: number, y: number, z: number): any
		return F * CFrame.new(x, y, z)
	end

	-- Ground floor (outer 20 × 16): sandstone walls, open bay x −6..6 at the front.
	blk(m, "WallBack", V(20, 9.5, 1), at(0, 4.25, 7.5), C.sandstone, M.Cobblestone)
	local sideL = blk(m, "WallLeft", V(1, 9.5, 14), at(-9.5, 4.25, 0), C.sandstone, M.Cobblestone)
	local sideR = blk(m, "WallRight", V(1, 9.5, 14), at(9.5, 4.25, 0), C.sandstone, M.Cobblestone)
	signText(sideL, Enum.NormalId.Left, "МАСТЕРСКАЯ", C.white, C.beam, { 0.5, 0.4, 0.9, 0.3 })
	signText(sideR, Enum.NormalId.Right, "МАСТЕРСКАЯ", C.white, C.beam, { 0.5, 0.4, 0.9, 0.3 })
	blk(m, "PierLeft", V(4, 9.5, 1), at(-8, 4.25, -7.5), C.sandstone, M.Cobblestone)
	blk(m, "PierRight", V(4, 9.5, 1), at(8, 4.25, -7.5), C.sandstone, M.Cobblestone)
	blk(m, "Lintel", V(12.4, 2, 1.2), at(0, 8, -7.5), C.beam, M.Wood)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			blk(m, "Quoin", V(1.4, 9.5, 1.4), at(sx * 9.8, 4.25, sz * 7.8), C.stoneDark, M.Cobblestone)
		end
	end
	local floor = blk(m, "Floor", V(18, 0.4, 14), at(0, 0, 0), C.wood, M.WoodPlanks, SMALL)
	blk(m, "Apron", V(14, 0.3, 4.5), at(0, 0, -10.4), C.stoneLight, M.Pavement, SMALL)

	-- Upper floor and front-gable roof (ridge along local Z).
	blk(m, "FloorBeam", V(21, 0.8, 17), at(0, 9.4, 0), C.beam, M.Wood)
	blk(m, "UpperFloor", V(20.4, 7, 16.4), at(0, 13.3, 0), C.wood, M.WoodPlanks)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			blk(m, "UpperPost", V(0.9, 7.2, 0.9), at(sx * 10.2, 13.3, sz * 8.2), C.beam, M.Wood)
		end
	end
	wdg(m, "Gable", V(16.4, 7.5, 10.2), at(-5.1, 20.55, 0) * CFrame.Angles(0, rad(90), 0), C.plaster)
	wdg(m, "Gable", V(16.4, 7.5, 10.2), at(5.1, 20.55, 0) * CFrame.Angles(0, rad(-90), 0), C.plaster)
	cylFwd(m, "GableWindow", 2.4, 0.3, at(0, 19.2, -8.35), C.beam, nil, SMALL)
	cylFwd(m, "GableGlass", 1.6, 0.3, at(0, 19.2, -8.45), C.glass, nil, SMALL)
	for _, sx in { -1, 1 } do
		local _, frameAt =
			roofPlane(m, "Roof", F, V(sx * 10.2, 16.8, 0), V(0, 24.3, 0), V(0, 0, 1), 19.6, 0.8, 1.5, 0.45, C.roofTeal)
		for _, t in { 0.3, 0.65 } do
			blk(m, "RoofTiles", V(19.8, 0.3, 0.8), frameAt(t, 0.95), C.roofTealDark, nil, SMALL)
		end
	end
	blk(m, "Ridge", V(1.8, 0.8, 20), at(0, 25, 0), C.roofTealDark)

	-- Sign board and windows on the upper floor.
	blk(m, "SignBacker", V(13.8, 3.8, 0.3), at(0, 13.6, -8.3), C.orange, M.Neon) -- glowing frame
	local sign = blk(m, "Sign", V(13, 3, 0.5), at(0, 13.6, -8.45), C.navy)
	signText(sign, Enum.NormalId.Front, "МАСТЕРСКАЯ", C.yellow, C.beam)
	for _, sx in { -1, 1 } do
		blk(m, "WindowFrame", V(2.2, 3, 0.4), at(sx * 8.4, 13.6, -8.3), C.beam, M.Wood, SMALL)
		blk(m, "WindowGlass", V(1.6, 2.4, 0.4), at(sx * 8.4, 13.6, -8.4), C.glass, nil, SMALL)
	end

	-- Big gear on the ridge with a crossed fishing rod and wrench.
	local gear = at(0, 29.4, -6)
	blk(m, "GearPost", V(1, 2.6, 0.6), at(0, 26.3, -6), C.beam, nil, SMALL)
	cylFwd(m, "Gear", 6.6, 0.8, gear, C.yellow)
	for k = 0, 7 do
		blk(
			m,
			"GearTooth",
			V(1.5, 1.4, 0.7),
			gear * CFrame.Angles(0, 0, rad(k * 45 + 22.5)) * CFrame.new(3.6, 0, 0),
			C.yellow,
			nil,
			SMALL
		)
	end
	cylFwd(m, "GearHub", 2.6, 1.2, gear, C.orange, nil, SMALL)
	local rodCF = gear * CFrame.new(0, 0, -0.85) * CFrame.Angles(0, 0, rad(45))
	cyl(m, "SignRod", 0.35, 10, rodCF, C.red, nil, SMALL)
	cyl(m, "SignRodHandle", 0.7, 2.4, rodCF * CFrame.new(-4, 0, 0), rgb(214, 172, 112), nil, SMALL)
	cylFwd(m, "SignRodReel", 1.3, 0.5, rodCF * CFrame.new(-2.4, 0, -0.3), C.silver, M.Metal, SMALL)
	local wrenchCF = gear * CFrame.new(0, 0, -1.05) * CFrame.Angles(0, 0, rad(45))
	blk(m, "SignWrench", V(0.8, 7.6, 0.4), wrenchCF, C.silver, M.Metal, SMALL)
	blk(m, "SignWrenchHead", V(2.4, 1.6, 0.5), wrenchCF * CFrame.new(0, 4.2, 0), C.silver, M.Metal, SMALL)
	blk(m, "SignWrenchJaw", V(0.8, 0.9, 0.56), wrenchCF * CFrame.new(0, 4.7, 0), C.navy, nil, SMALL)

	-- Workbench in the bay (stage: the upgrade prompt is created on its attachment).
	local bench = blk(m, "Workbench", V(11, 0.6, 3.2), at(0, 3, -7.4), C.woodLight, M.WoodPlanks)
	U.new("Attachment", { Name = "UpgradePromptAttachment", CFrame = CFrame.new(0, 0.5, -2.8) }, bench)
	for _, sx in { -1, 1 } do
		for _, z in { -8.6, -6.2 } do
			blk(m, "BenchLeg", V(0.7, 2.9, 0.7), at(sx * 4.9, 1.25, z), C.beam, M.Wood, SMALL)
		end
	end
	blk(m, "BenchShelf", V(10, 0.4, 2.6), at(0, 0.9, -7.4), C.woodDark, M.Wood, SMALL)
	blk(m, "Vice", V(1.2, 0.9, 1.4), at(-4.2, 3.75, -7.6), C.iron, M.Metal, SMALL)
	blk(m, "ViceJaw", V(1.8, 0.5, 0.3), at(-4.2, 3.95, -8.45), C.iron, M.Metal, SMALL)
	blk(m, "HammerHandle", V(2.4, 0.3, 0.3), at(-1.4, 3.45, -7.9) * CFrame.Angles(0, rad(20), 0), C.woodDark, nil, SMALL)
	blk(m, "HammerHead", V(0.6, 0.6, 1.2), at(-0.3, 3.6, -8.3) * CFrame.Angles(0, rad(20), 0), C.iron, M.Metal, SMALL)
	cylUp(m, "Reel", 1.4, 0.6, at(1.8, 3.6, -7.2), C.silver, M.Metal, SMALL)
	cyl(m, "RodBlank", 0.25, 5, at(2.6, 3.45, -6.5) * CFrame.Angles(0, rad(15), 0), C.red, nil, SMALL)

	-- Inside: tool wall, anvil, forge with glowing coals.
	blk(m, "ToolWall", V(12, 5, 0.3), at(0, 5.2, 6.85), C.woodLight, M.WoodPlanks, SMALL)
	blk(m, "Saw", V(3.4, 1.3, 0.3), at(-3.6, 5.8, 6.6), C.silver, M.Metal, SMALL)
	blk(m, "ToolHammer", V(0.3, 2.6, 0.3), at(-0.8, 5, 6.6), C.woodDark, nil, SMALL)
	blk(m, "ToolHammerHead", V(1.4, 0.7, 0.5), at(-0.8, 6.3, 6.5), C.iron, M.Metal, SMALL)
	blk(m, "ToolWrench", V(0.45, 3, 0.3), at(1.4, 5.2, 6.6) * CFrame.Angles(0, 0, rad(10)), C.silver, M.Metal, SMALL)
	cylUp(m, "Stump", 2.4, 2.4, at(-3, 1, 2), C.wood, M.Wood)
	blk(m, "AnvilBase", V(1.2, 0.7, 1), at(-3, 2.55, 2), C.iron, M.Metal)
	blk(m, "Anvil", V(2.8, 0.9, 1.3), at(-3, 3.35, 2), C.iron, M.Metal)
	wdg(m, "AnvilHorn", V(1.3, 0.9, 1.4), at(-0.9, 3.35, 2) * CFrame.Angles(0, rad(-90), 0) * CFrame.Angles(0, 0, pi), C.iron, M.Metal, SMALL)
	blk(m, "Forge", V(4, 3, 3.5), at(5.6, 1.3, 4.6), C.stoneDark, M.Cobblestone)
	local coals = blk(m, "Coals", V(3, 0.3, 2.5), at(5.6, 2.9, 4.6), rgb(255, 112, 36), M.Neon, SMALL)
	pointLight(coals, rgb(255, 140, 60), 12, 1.2)
	blk(m, "ForgeHood", V(4.4, 1.2, 3.9), at(5.6, 6.8, 4.6), C.iron, M.Metal)
	blk(m, "ForgeFlue", V(1.6, 2.6, 1.6), at(5.6, 8.6, 4.6), C.iron, M.Metal, SMALL)

	-- The smith behind the bench.
	villager(m, "Smith", at(0, 0.2, -4.6), { shirt = C.red, pants = C.navy, apron = rgb(126, 84, 52), hat = C.iron })

	-- Chimney on the right side with glowing top and smoke puffs.
	blk(m, "Chimney", V(3, 26, 3), at(11.6, 12.5, 3.5), C.terracotta, M.Brick)
	blk(m, "ChimneyBand", V(3.4, 0.7, 3.4), at(11.6, 19.5, 3.5), C.stoneDark, nil, SMALL)
	blk(m, "ChimneyCap", V(3.6, 0.6, 3.6), at(11.6, 25.8, 3.5), C.stoneDark, nil, SMALL)
	blk(m, "ChimneyGlow", V(2.2, 0.3, 2.2), at(11.6, 26.15, 3.5), C.orange, M.Neon, SMALL)
	for i, puff in { { 12, 28.4, 3.3, 2.2 }, { 12.9, 30.8, 2.8, 2.8 }, { 14.1, 33.6, 2.2, 3.4 } } do
		ball(m, "Smoke", puff[4], at(puff[1], puff[2], puff[3]), rgb(236, 236, 240), nil, with(GHOST, { Transparency = 0.1 + 0.18 * i }))
	end

	-- Lumber, barrel and crates on the left side (the +X walkway side).
	for _, p in { { -12.2, 0.2 }, { -12.85, 0.8 } } do
		blk(m, "Lumber", V(1.2, 0.6, 7), at(p[1], p[2], 1), C.woodLight, M.Wood)
	end
	barrel(m, at(-12.4, 0, -4))
	crate(m, at(-12.6, 0, 5.6) * CFrame.Angles(0, rad(8), 0))
	crate(m, at(-12.6, 2.1, 5.6) * CFrame.Angles(0, rad(-14), 0), 1.6)

	m.PrimaryPart = floor
	return m
end

--------------------------------------------------------------------------------
-- Fish market «СКУПКА РЫБЫ»: open stall with a striped canopy, ice tray full of fish,
-- red scales, fishmonger, net drying behind.
--------------------------------------------------------------------------------

local FISH_COLORS = { C.orange, C.pink, C.yellow, C.teal, C.purple, C.red }

local function buildFishMarket(hub: any, F: any)
	local m = U.model(hub, "FishMarket")
	local function at(x: number, y: number, z: number): any
		return F * CFrame.new(x, y, z)
	end

	local floor = blk(m, "Floor", V(18, 0.4, 9.2), at(0, 0, 1), C.wood, M.WoodPlanks, SMALL)
	local backWall = blk(m, "BackWall", V(18.4, 11.8, 0.8), at(0, 5.4, 5.8), C.woodLight, M.WoodPlanks)
	signText(backWall, Enum.NormalId.Back, "СКУПКА РЫБЫ", C.white, C.navy, { 0.5, 0.45, 0.9, 0.35 })
	for _, sx in { -1, 1 } do
		blk(m, "PostFront", V(0.8, 13.6, 0.8), at(sx * 8.8, 6.3, -5), C.beam, M.Wood)
		blk(m, "PostBack", V(0.8, 11.9, 0.8), at(sx * 8.8, 5.45, 5), C.beam, M.Wood)
		ball(m, "PostCap", 1.1, at(sx * 8.8, 13.5, -5), C.gold, nil, SMALL)
	end
	blk(m, "Boardwalk", V(18, 0.3, 3.4), at(0, 0, -7.6), C.wood, M.WoodPlanks, SMALL)

	-- Counter with an ice tray of colourful fish.
	blk(m, "Counter", V(16.8, 3.4, 2.2), at(0, 1.2, -4.4), C.woodLight, M.WoodPlanks)
	blk(m, "CounterTop", V(17.4, 0.3, 2.6), at(0, 3.05, -4.4), C.woodDark, M.Wood)
	blk(m, "CounterPanel", V(15.6, 2, 0.25), at(0, 1.5, -5.6), C.blue, nil, SMALL)
	blk(m, "CounterWave", V(15.6, 0.35, 0.2), at(0, 1.9, -5.78), C.white, nil, SMALL)
	blk(m, "IceTray", V(10, 0.5, 2), at(-2.6, 3.45, -4.4), C.ice, M.Ice)
	for i = 1, 6 do
		local x = -7 + (i - 1) * 1.75
		local z = if i % 2 == 0 then -4.0 else -4.8
		local cf = at(x, 3.95, z) * CFrame.Angles(0, rad(if i % 2 == 0 then 25 else -20), 0)
		local color = FISH_COLORS[i]
		blk(m, "Fish", V(1.9, 0.5, 0.9), cf, color, nil, SMALL)
		blk(m, "FishTail", V(0.75, 0.45, 0.75), cf * CFrame.new(-1.15, 0, 0) * CFrame.Angles(0, rad(45), 0), color, nil, SMALL)
	end

	-- Scales: the sell prompt (stage 3) is created on its attachment.
	local scales = blk(m, "Scales", V(2.4, 1.6, 2), at(5.6, 4, -4.4), C.red)
	U.new("Attachment", { Name = "SellPromptAttachment", CFrame = CFrame.new(0, -0.5, -2.8) }, scales)
	cylFwd(m, "ScalesDial", 1.4, 0.2, at(5.6, 4, -5.5), C.white, nil, SMALL)
	blk(m, "ScalesNeedle", V(0.14, 0.6, 0.1), at(5.65, 4.12, -5.64) * CFrame.Angles(0, 0, rad(-30)), C.ink, nil, SMALL)
	cylUp(m, "ScalesPan", 2.8, 0.25, at(5.6, 4.9, -4.4), C.silver, M.Metal, SMALL)
	blk(m, "GoldFish", V(1.8, 0.5, 0.9), at(5.5, 5.25, -4.4) * CFrame.Angles(0, rad(15), 0), C.gold, nil, SMALL)
	blk(m, "GoldFishTail", V(0.7, 0.45, 0.7), at(4.45, 5.25, -4.12) * CFrame.Angles(0, rad(60), 0), C.gold, nil, SMALL)

	-- Striped canopy sloping to the front, valance flaps.
	local slope = math.atan2(2.2, 12.4)
	for i = 0, 6 do
		local x = -9.6 + 19.2 / 7 * (i + 0.5)
		local color = if i % 2 == 0 then C.blue else C.white
		blk(m, "Canopy", V(19.2 / 7, 0.3, 12.6), at(x, 10.3, -0.6) * CFrame.Angles(-slope, 0, 0), color, nil, { CastShadow = true })
		blk(m, "Valance", V(19.2 / 7, 1, 0.2), at(x, 8.75, -6.85), color, nil, SMALL)
	end

	-- Sign between the front posts with a big orange fish on top.
	local sign = blk(m, "Sign", V(17.6, 3.2, 0.5), at(0, 11.5, -5), C.teal)
	signText(sign, Enum.NormalId.Front, "СКУПКА РЫБЫ", C.white, C.navy)
	signText(sign, Enum.NormalId.Back, "СКУПКА РЫБЫ", C.white, C.navy)
	signFish(m, at(0.3, 14.55, -5), 0.55, { body = C.orange, belly = C.cream, fins = C.yellow })

	villager(m, "Fishmonger", at(-1.5, 0.2, -2), { shirt = C.blue, pants = C.navy, apron = C.white, hat = C.yellow })

	-- Back shelf with fish crates, ice chest.
	blk(m, "Shelf", V(16, 0.4, 1.2), at(0, 5.6, 4.8), C.woodDark, M.Wood, SMALL)
	blk(m, "FishCrate", V(2.4, 1.4, 1.1), at(-4, 6.5, 4.8), C.teal, nil, SMALL)
	blk(m, "FishCrate", V(2.4, 1.4, 1.1), at(3.5, 6.5, 4.8), C.orange, nil, SMALL)
	blk(m, "IceChest", V(3, 2, 2), at(-6.4, 1.2, 2), C.teal)
	blk(m, "IceChestLid", V(3.2, 0.4, 2.2), at(-6.4, 2.4, 2), C.white, nil, SMALL)

	-- Outside: barrel of fish, crates (the +Z walkway side), drying net behind.
	local b = at(10.6, 0, -1.5)
	barrel(m, b)
	blk(m, "FishInBarrel", V(0.6, 1.6, 1), b * CFrame.new(-0.3, 2.6, 0) * CFrame.Angles(0, 0, rad(15)), C.pink, nil, SMALL)
	blk(m, "FishInBarrel", V(0.6, 1.4, 0.9), b * CFrame.new(0.4, 2.5, 0.2) * CFrame.Angles(rad(-12), 0, rad(-18)), C.yellow, nil, SMALL)
	crate(m, at(10.6, 0, 2.6) * CFrame.Angles(0, rad(-8), 0))
	crate(m, at(10.6, 2.1, 2.6) * CFrame.Angles(0, rad(12), 0), 1.7)
	for _, sx in { -1, 1 } do
		cylUp(m, "NetPole", 0.4, 6.6, at(sx * 4.2, 2.8, 9.6), C.woodDark, M.Wood, SMALL)
	end
	blk(m, "Net", V(8, 4, 0.15), at(0, 3.8, 9.6), rgb(96, 76, 56), M.Fabric, with(GHOST, { Transparency = 0.35 }))

	m.PrimaryPart = floor
	return m
end

--------------------------------------------------------------------------------
-- Fountain: octagonal basin, two-tier pedestal, leaping golden fish spitting a water jet.
--------------------------------------------------------------------------------

local function buildFountain(hub: any, G: number)
	local m = U.model(hub, "Fountain")
	local O = CFrame.new(0, G, 0)
	local apo = 8.6
	local side = 2 * apo * math.tan(rad(22.5))
	for k = 0, 7 do
		blk(m, "Rim", V(side, 1.4, 1.2), O * CFrame.Angles(0, rad(k * 45), 0) * CFrame.new(0, 0.4, apo), C.stoneLight, M.Slate)
		cylUp(
			m,
			"RimPost",
			1.8,
			1.8,
			O * CFrame.Angles(0, rad(k * 45 + 22.5), 0) * CFrame.new(0, 0.6, apo / math.cos(rad(22.5))),
			C.stone,
			M.Slate
		)
	end
	cylUp(m, "BasinFloor", 17.6, 0.4, O * CFrame.new(0, 0.1, 0), rgb(36, 128, 150), nil, SMALL)
	cylUp(m, "Pool", 17.6, 0.35, O * CFrame.new(0, 0.775, 0), C.water, nil, with(GHOST, { Transparency = 0.3, Reflectance = 0.1 }))
	cylUp(m, "Pedestal", 5, 2.6, O * CFrame.new(0, 1.3, 0), C.stoneLight, M.Slate)
	cylUp(m, "Bowl", 9, 0.9, O * CFrame.new(0, 3.05, 0), C.stoneLight, M.Slate)
	cylUp(m, "BowlWater", 8.2, 0.15, O * CFrame.new(0, 3.575, 0), C.water, nil, with(GHOST, { Transparency = 0.25 }))
	cylUp(m, "WaterCurtain", 9.3, 2.9, O * CFrame.new(0, 1.95, 0), C.water, nil, with(GHOST, { Transparency = 0.55 }))
	cylUp(m, "Column", 2.2, 2, O * CFrame.new(0, 4.5, 0), C.stoneLight, M.Slate)
	cylUp(m, "ColumnCap", 3, 0.5, O * CFrame.new(0, 5.6, 0), C.gold, M.Metal)

	-- Golden fish leaping out of the bowl (head towards +X, tilted 60° up), broadside towards ±Z.
	local fish = O * CFrame.new(2, 10.2, 0) * CFrame.Angles(0, 0, rad(60))
	local body = signFish(m, fish, 1, {
		body = C.gold,
		belly = C.goldLight,
		fins = C.gold,
		finMaterial = M.Neon,
		extra = { Reflectance = 0.15 },
	})
	pointLight(body, C.goldLight, 14, 1.4)

	-- Water jet from the mouth arcing into the pool, with a splash.
	local mouth = (fish * CFrame.new(6.7, -0.3, 0)).Position
	local pts = {
		mouth,
		mouth + V(0.6, 1.3, 0),
		mouth + V(1.4, 1.5, 0),
		mouth + V(2.0, 0.2, 0),
		V(7.2, G + 1.0, 0),
	}
	for i = 1, #pts - 1 do
		beam(m, "WaterJet", pts[i], pts[i + 1], 0.7, rgb(206, 242, 255), nil, with(GHOST, { Transparency = 0.3 }))
	end
	blk(m, "Splash", V(2.4, 0.6, 2.4), CFrame.new(7.2, G + 1.0, 0), C.white, nil, with(GHOST, { Shape = Enum.PartType.Ball, Transparency = 0.3 }))

	m.PrimaryPart = body
	return m
end

--------------------------------------------------------------------------------
-- Lighthouse on a stone podium at the shore: red/white tapering tower, gallery, lantern.
--------------------------------------------------------------------------------

local function buildLighthouse(hub: any, F: any)
	local m = U.model(hub, "Lighthouse")
	local function at(x: number, y: number, z: number): any
		return F * CFrame.new(x, y, z)
	end
	cylUp(m, "Podium", 15, 11.5, at(0, -5.85, 0), C.stone, M.Cobblestone)
	local cap = cylUp(m, "PodiumCap", 15.8, 0.6, at(0, 0.2, 0), C.stoneLight, M.Slate)
	for _, r in { { -9.5, 7.2, V(5, 4.4, 4.5), 20, 35, -14 }, { 8.6, 7.8, V(4.5, 3.6, 5.5), -16, -28, 12 } } do
		blk(m, "Rock", r[3], at(r[1], -2.4, r[2]) * CFrame.Angles(rad(r[4]), rad(r[5]), rad(r[6])), C.stoneDark, M.Slate)
	end
	-- Tower: 6 tapering bands.
	local y = 0.5
	for i = 0, 5 do
		local d = 10 - i * 0.6
		cylUp(m, "Tower", d, 5.6, at(0, y + 2.8, 0), if i % 2 == 0 then C.red else C.white)
		y += 5.6
	end
	blk(m, "DoorFrame", V(3.4, 5, 0.5), at(0, 3, -4.8), C.white, nil, SMALL)
	blk(m, "Door", V(2.6, 4.4, 0.8), at(0, 2.7, -4.75), C.woodDark, M.WoodPlanks, SMALL)
	for _, w in { { 2, 30 }, { 3, -50 }, { 4, 160 } } do
		local radius = (10 - w[1] * 0.6) / 2
		blk(
			m,
			"Window",
			V(1.2, 1.8, 0.6),
			at(0, 0, 0) * CFrame.Angles(0, rad(w[2]), 0) * CFrame.new(0, 0.5 + 5.6 * (w[1] + 0.5), -(radius + 0.1)),
			C.navy,
			nil,
			SMALL
		)
	end
	-- Gallery with a railing.
	local top = y -- 34.1
	cylUp(m, "Corbel", 8.6, 1, at(0, top - 0.2, 0), C.white)
	cylUp(m, "Gallery", 11, 0.7, at(0, top + 0.65, 0), C.iron, M.Metal)
	for k = 0, 7 do
		blk(
			m,
			"Railing",
			V(4.2, 1.4, 0.25),
			at(0, 0, 0) * CFrame.Angles(0, rad(k * 45 + 22.5), 0) * CFrame.new(0, top + 1.7, -5.2),
			C.white,
			nil,
			SMALL
		)
	end
	-- Lantern room.
	local ly = top + 1.0 + 2.3
	cylUp(m, "LanternGlass", 5.6, 4.6, at(0, ly, 0), rgb(255, 236, 170), nil, { Transparency = 0.45, CastShadow = false })
	local core = ball(m, "Lamp", 3.2, at(0, ly, 0), rgb(255, 214, 90), M.Neon, GHOST)
	pointLight(core, rgb(255, 220, 140), 16, 2)
	for k = 0, 3 do
		blk(m, "Mullion", V(0.35, 4.6, 0.35), at(0, 0, 0) * CFrame.Angles(0, rad(45 + k * 90), 0) * CFrame.new(0, ly, -2.75), C.iron, M.Metal, SMALL)
	end
	local ry = ly + 2.3
	cylUp(m, "Roof", 7, 0.8, at(0, ry + 0.4, 0), C.red)
	cylUp(m, "Dome", 5.4, 1, at(0, ry + 1.3, 0), C.red)
	cylUp(m, "Dome", 3.6, 1, at(0, ry + 2.3, 0), C.red)
	cylUp(m, "Dome", 1.8, 1, at(0, ry + 3.3, 0), C.red)
	cylUp(m, "Spire", 0.35, 3, at(0, ry + 5.3, 0), C.iron, M.Metal, SMALL)
	ball(m, "SpireBall", 0.9, at(0, ry + 6.9, 0), C.gold, nil, SMALL)
	wdg(m, "Flag", V(0.12, 1.2, 1.8), at(0, ry + 5.9, 1.0) * CFrame.Angles(0, 0, pi), C.red, nil, GHOST)
	gull(m, at(0, top + 2.4, -5.2))
	m.PrimaryPart = cap
	return m
end

--------------------------------------------------------------------------------
-- Docks and boats
--------------------------------------------------------------------------------

-- Boat on the water (B: waterline centre, bow towards B's +Z).
local function boat(parent: any, B: any, hull: any, trim: any, fishing: boolean): any
	local m = U.model(parent, "Boat")
	local function at(x: number, y: number, z: number): any
		return B * CFrame.new(x, y, z)
	end
	local floor = blk(m, "Floor", V(3.6, 0.4, 8), at(0, 0.1, 0), C.wood, M.WoodPlanks, SMALL)
	for _, sx in { -1, 1 } do
		blk(m, "Side", V(0.5, 2.2, 8), at(sx * 2.05, 0.3, 0), hull)
		blk(m, "Gunwale", V(0.7, 0.3, 8), at(sx * 2.05, 1.55, 0), trim, nil, SMALL)
	end
	blk(m, "Stern", V(4.6, 2.2, 0.5), at(0, 0.3, -4.25), hull)
	-- Pointed bow: two wedges laid on their sides (right angle at the hull's front centre).
	wdg(m, "Bow", V(2.2, 2.3, 3.2), B * CFrame.fromMatrix(V(1.15, 0.3, 5.6), V(0, 1, 0), V(1, 0, 0), V(0, 0, -1)), hull)
	wdg(m, "Bow", V(2.2, 2.3, 3.2), B * CFrame.fromMatrix(V(-1.15, 0.3, 5.6), V(0, -1, 0), V(-1, 0, 0), V(0, 0, -1)), hull)
	blk(m, "Seat", V(3.6, 0.3, 1), at(0, 0.9, 1.6), C.woodLight, M.Wood, SMALL)
	if fishing then
		blk(m, "Cabin", V(3, 2.6, 2.6), at(0, 1.6, -2.2), C.white)
		blk(m, "CabinRoof", V(3.6, 0.35, 3.2), at(0, 3.05, -2.2), hull)
		blk(m, "CabinWindow", V(2.2, 0.9, 0.2), at(0, 2.1, -0.85), C.navy, nil, SMALL)
		cylUp(m, "Mast", 0.35, 6, at(0, 6.2, -2.2), C.woodDark, M.Wood, SMALL)
		wdg(m, "MastFlag", V(0.12, 1, 1.6), at(0, 8.6, -3.0) * CFrame.Angles(0, 0, pi), trim, nil, GHOST)
		blk(m, "FishCrate", V(1.8, 0.8, 1.2), at(0, 0.7, 3.2), C.teal, nil, SMALL)
	else
		blk(m, "Seat", V(3.6, 0.3, 1), at(0, 0.9, -2.4), C.woodLight, M.Wood, SMALL)
		blk(m, "Oar", V(0.3, 0.2, 6.5), at(-0.8, 1.15, -0.4) * CFrame.Angles(0, rad(8), 0), C.woodLight, nil, SMALL)
		blk(m, "Oar", V(0.3, 0.2, 6.5), at(0.8, 1.15, -0.4) * CFrame.Angles(0, rad(-8), 0), C.woodLight, nil, SMALL)
	end
	m.PrimaryPart = floor
	return m
end

-- Angler sitting on the edge of a dock (A: on the deck surface, facing A's −Z over the water).
local function angler(parent: any, A: any, waterBelow: number)
	local m = U.model(parent, "Angler")
	local function p(n: string, size: any, x: number, y: number, z: number, color: any, extra: any?)
		return blk(m, n, size, A * CFrame.new(x, y, z), color, nil, extra)
	end
	p("Thighs", V(2, 1, 2), 0, 0.5, -0.5, C.navy)
	p("Shins", V(2, 2.2, 1), 0, -0.6, -1, C.navy, SMALL)
	local torso = p("Torso", V(2, 2, 1), 0, 2, 0.2, C.green)
	p("ArmLeft", V(1, 1, 2), -1.5, 2.6, -0.6, C.green, SMALL)
	p("ArmRight", V(1, 1, 2), 1.5, 2.6, -0.6, C.green, SMALL)
	p("Head", V(1.6, 1.6, 1.6), 0, 3.8, 0.2, C.skin)
	p("HatBrim", V(2.8, 0.25, 2.8), 0, 4.72, 0.2, C.yellow, SMALL)
	p("HatTop", V(1.6, 0.7, 1.6), 0, 5.15, 0.2, C.yellow, SMALL)
	p("Bucket", V(1.1, 1.2, 1.1), -1.9, 0.6, 0.8, C.teal, SMALL)
	local hands = (A * CFrame.new(0, 2.6, -1.7)).Position
	local tip = (A * CFrame.new(0, 7.8, -7.6)).Position
	local bob = (A * CFrame.new(0, waterBelow + 0.15, -8.4)).Position
	beam(m, "Rod", hands, tip, 0.22, C.red, nil, SMALL)
	beam(m, "Line", tip, bob, 0.06, C.white, nil, GHOST)
	ball(m, "Bobber", 0.6, CFrame.new(bob), C.red, nil, GHOST)
	m.PrimaryPart = torso
end

-- Dock from radius r0 (on the beach) to r1 (over the water) along `angle`. Returns its frame.
local function dock(parent: any, angle: number, r0: number, r1: number, deckTop: number, fancy: boolean): any
	local m = U.model(parent, "Dock")
	local len = r1 - r0
	local D = U.polarCFrame(angle, (r0 + r1) / 2, 0)
	local function at(x: number, y: number, z: number): any
		return D * CFrame.new(x, y, z)
	end
	local deck = blk(m, "Deck", V(4.4, 0.5, len), at(0, deckTop - 0.25, 0), C.wood, M.WoodPlanks)
	for _, sx in { -1, 1 } do
		blk(m, "Stringer", V(0.4, 0.7, len + 0.2), at(sx * 2.3, deckTop - 0.45, 0), C.woodDark, M.Wood, SMALL)
		for _, z in { -1, len / 2 - 0.6 } do
			cylUp(m, "Pile", 0.9, 9, at(sx * 2.5, deckTop - 3.75, z), C.woodDark, M.Wood)
		end
	end
	blk(m, "Bollard", V(0.8, 0.9, 0.8), at(-1.5, deckTop + 0.4, len / 2 - 3), C.iron, M.Metal, SMALL)
	crate(m, at(-1.1, deckTop, -len / 2 + 4) * CFrame.Angles(0, rad(14), 0), 1.8)
	if fancy then
		blk(m, "Bollard", V(0.8, 0.9, 0.8), at(1.5, deckTop + 0.4, len / 2 - 3), C.iron, M.Metal, SMALL)
		cylUp(m, "LampPost", 0.35, 3.6, at(2.5, deckTop + 2.55, len / 2 - 0.6), C.iron, M.Metal, SMALL)
		blk(m, "LampGlow", V(0.9, 1.1, 0.9), at(2.5, deckTop + 4.85, len / 2 - 0.6), C.lamp, M.Neon, SMALL)
		cyl(m, "LifeRing", 1.8, 0.3, at(2.83, deckTop + 2.6, len / 2 - 0.6), C.red, nil, SMALL)
		cyl(m, "LifeRingHole", 0.9, 0.1, at(3.03, deckTop + 2.6, len / 2 - 0.6), C.woodDark, nil, SMALL)
		barrel(m, at(1.2, deckTop, -len / 2 + 3))
		cylUp(m, "RopeCoil", 1.4, 0.4, at(1.3, deckTop + 0.2, len / 2 - 5), rgb(214, 186, 130), nil, SMALL)
		gull(m, at(-2.5, deckTop + 0.75, len / 2 - 0.6))
	end
	m.PrimaryPart = deck
	return D, m
end

--------------------------------------------------------------------------------

return function(parent: any, cfg: any, gen: any?)
	local startCount = U.partCount
	local G = cfg.GroundTop
	local PR, HR = cfg.HubPlazaRadius, cfg.HubRadius

	-- Terrain height: real terrain when the generator is given, else the island profile
	-- of WorldGen.naturalHeight (flat plaza, smooth slope down to −7 at HubRadius + 10).
	local function groundAt(x: number, z: number): number
		if gen then
			return (gen:surfaceAt(x, z))
		end
		local r = math.sqrt(x * x + z * z)
		local t = math.clamp((r - PR) / (HR + 10 - PR), 0, 1)
		return G + (-7 - G) * t * t * (3 - 2 * t)
	end
	local function groundPoint(angle: number, r: number, sink: number): any
		local p = U.polar(angle, r, 0)
		return V(p.X, groundAt(p.X, p.Z) - sink, p.Z)
	end

	local hub = U.model(parent, "Hub")

	------------------------------------------------------------------ plaza paving
	local plaza = U.model(hub, "Plaza")
	cylUp(plaza, "PavingBorder", 40, 0.5, CFrame.new(0, G - 0.17, 0), C.pavingDark, M.Slate, SMALL)
	cylUp(plaza, "Paving", 38, 0.5, CFrame.new(0, G - 0.13, 0), C.paving, M.Pavement, SMALL)
	for k = 0, 3 do
		blk(plaza, "Ray", V(1.6, 0.4, 7.4), U.polarCFrame(45 + k * 90, 14.2, G - 0.04), C.terracotta, M.Pavement, SMALL)
	end
	for _, a in cfg.BridgeAngles do
		blk(plaza, "WalkwayBorder", V(10.6, 0.5, 24.4), U.polarCFrame(a, 31.5, G - 0.19), C.pavingDark, M.Slate, SMALL)
		blk(plaza, "Walkway", V(9, 0.5, 24), U.polarCFrame(a, 31.5, G - 0.15), C.paving, M.Pavement, SMALL)
	end

	------------------------------------------------------------------ spawn
	blk(plaza, "SpawnFrame", V(7, 0.3, 7), CFrame.new(0, G + 0.1, -13.5), C.gold, nil, SMALL)
	U.new("SpawnLocation", {
		Name = "HubSpawn",
		Size = V(6, 0.4, 6),
		CFrame = CFrame.new(0, G + 0.2, -13.5) * CFrame.Angles(0, pi, 0), -- faces +Z: fountain, shop, market
		Anchored = true,
		Neutral = true,
		Duration = 0, -- no ForceField
		Enabled = true,
		AllowTeamChangeOnTouch = false,
		Color = C.teal,
		Material = M.SmoothPlastic,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		CastShadow = false,
	}, hub)
	U.partCount += 1

	------------------------------------------------------------------ buildings
	local shopF = U.polarCFrame(45, 33, G)
	local workshopF = U.polarCFrame(135, 33, G)
	local marketF = U.polarCFrame(315, 30, G)
	buildShop(hub, shopF)
	buildWorkshop(hub, workshopF)
	buildFishMarket(hub, marketF)
	buildFountain(hub, G)
	buildLighthouse(hub, U.polarCFrame(225, 54, G))

	------------------------------------------------------------------ street furniture
	local street = U.model(hub, "Street")
	for _, a in cfg.BridgeAngles do
		gateArch(street, a, 40, G)
	end
	-- Around the fountain on the diagonals: bench facing the water, lamp and planter at its ends.
	for k = 0, 3 do
		local a = 45 + k * 90
		local cf = U.polarCFrame(a, 15.4, G + 0.1)
		bench(street, cf)
		lampPost(street, (cf * CFrame.new(-4.1, -0.3, 0.2)).Position, true)
		planter(street, (cf * CFrame.new(4.4, -0.1, 0.3)).Position, if k % 2 == 0 then { C.pink, C.yellow } else { C.purple, C.white })
	end

	-- Café terrace and notice board between the −Z and −X walkways.
	local cafe = U.model(hub, "Cafe")
	umbrellaTable(cafe, U.polar(211, 29, G), { C.red, C.white })
	umbrellaTable(cafe, U.polar(239, 29, G), { C.teal, C.white })
	umbrellaTable(cafe, U.polar(225, 36.5, G), { C.yellow, C.white })
	local board = U.model(cafe, "NoticeBoard")
	local nb = U.polarCFrame(225, 21.5, G)
	for _, sx in { -1, 1 } do
		blk(board, "Post", V(0.6, 7, 0.6), nb * CFrame.new(sx * 3, 3.3, 0), C.woodDark, M.Wood)
	end
	local boardPart = blk(board, "Board", V(6.4, 4, 0.4), nb * CFrame.new(0, 4.2, 0), C.woodLight, M.WoodPlanks)
	signText(boardPart, Enum.NormalId.Front, "НОВОСТИ ГАВАНИ", C.beam, C.cream, { 0.5, 0.12, 0.9, 0.18 })
	wdg(board, "BoardRoof", V(7.6, 1, 0.9), nb * CFrame.new(0, 7.2, -0.45), C.roofRed)
	wdg(board, "BoardRoof", V(7.6, 1, 0.9), nb * CFrame.new(0, 7.2, 0.45) * CFrame.Angles(0, pi, 0), C.roofRed)
	for i, note in { { -1.8, 4.2, 6, C.white }, { 0, 3.6, -4, C.yellow }, { 1.9, 4.3, 8, C.pink }, { 0.2, 5.2, 3, C.ice } } do
		blk(board, "Note", V(1.4, 1.5, 0.1), nb * CFrame.new(note[1], note[2], -0.25) * CFrame.Angles(0, 0, rad(note[3])), note[4], nil, SMALL)
		local _ = i
	end
	local poleTops = {}
	for _, a in { 206, 244 } do
		local base = U.polar(a, 27, G)
		cylUp(cafe, "FestivalPole", 0.6, 16, CFrame.new(base + V(0, 7.8, 0)), C.white, nil, SMALL)
		ball(cafe, "PoleBall", 1.2, CFrame.new(base + V(0, 16, 0)), C.gold, nil, SMALL)
		wdg(cafe, "PoleFlag", V(0.12, 1.6, 2.4), CFrame.new(base + V(0, 14.6, 0)) * CFrame.Angles(0, rad(a), 0) * CFrame.new(0, 0, 1.4) * CFrame.Angles(0, 0, pi), C.red, nil, GHOST)
		poleTops[a] = base + V(0, 13.2, 0)
	end

	------------------------------------------------------------------ bunting over the walkways
	local flags = U.model(hub, "Bunting")
	local function p(F: any, x: number, y: number, z: number): any
		return (F * CFrame.new(x, y, z)).Position
	end
	bunting(flags, p(shopF, -11.3, 17.6, -7.3), p(marketF, 8.8, 12.6, -5), 2.5, 9, 0)
	bunting(flags, p(shopF, 11.3, 17.6, -7.3), p(workshopF, -10.2, 16.4, -8.2), 2.5, 9, 2)
	bunting(flags, p(workshopF, 10.2, 16.4, -8.2), poleTops[206], 2.5, 9, 4)
	bunting(flags, poleTops[244], p(marketF, -8.8, 12.6, -5), 2.5, 9, 1)

	------------------------------------------------------------------ beach: palms, rocks
	local beach = U.model(hub, "Beach")
	for _, spec in { { 15, 51, 1.0 }, { 33, 52, 0.9 }, { 75, 50, 0.95 }, { 106, 51, 1.05 }, { 152, 51, 1.0 }, { 166, 50, 0.9 }, { 249, 50, 1.05 }, { 290, 51, 1.0 } } do
		palm(beach, groundPoint(spec[1], spec[2], 0), spec[1], spec[3])
	end
	for i, spec in { { 122, 56, V(4, 2.6, 3.4) }, { 300, 57, V(3.6, 2.4, 3) } } do
		local g = groundPoint(spec[1], spec[2], 0.5)
		blk(beach, "Rock", spec[3], CFrame.new(g + V(0, spec[3].Y / 2 - 0.4, 0)) * CFrame.Angles(rad(6 * i), rad(53 * i), rad(-4 * i)), C.stone, M.Slate)
	end

	------------------------------------------------------------------ docks and boats
	local harbour = U.model(hub, "Harbour")
	local deckTop = cfg.WaterTop + 1.2
	local d1 = dock(harbour, 200, 54, 76, deckTop, true)
	local d2 = dock(harbour, 338, 54, 70, deckTop, false)
	angler(harbour, d1 * CFrame.new(-0.6, deckTop, 10.4) * CFrame.Angles(0, pi, 0), cfg.WaterTop - deckTop)
	local boatA = d1 * CFrame.new(-5, 0, 3)
	boat(harbour, boatA, C.red, C.white, true)
	local boatB = d1 * CFrame.new(5, 0, 1) * CFrame.Angles(0, pi, 0)
	boat(harbour, boatB, C.teal, C.yellow, false)
	local boatC = d2 * CFrame.new(-5, 0, 4.5) * CFrame.Angles(0, rad(180 - 6), 0)
	boat(harbour, boatC, C.yellow, C.blue, false)
	local function mooring(B: any, bowZ: number, post: any)
		beam(harbour, "MooringRope", (B * CFrame.new(0, 1.6, bowZ)).Position, post, 0.15, C.rope, nil, GHOST)
	end
	mooring(boatA, 4.5, (d1 * CFrame.new(-1.5, deckTop + 0.8, 8)).Position)
	mooring(boatB, -3.5, (d1 * CFrame.new(1.5, deckTop + 0.8, 8)).Position)
	mooring(boatC, -3.5, (d2 * CFrame.new(-1.5, deckTop + 0.8, 5)).Position)

	return {
		model = hub,
		partCount = U.partCount - startCount,
		expectedAttachments = {
			{
				root = "workspace",
				path = { "Map", "Hub", "Shop", "Counter", "ShopPromptAttachment" },
				offset = V(0, 2.2, -2.8),
			},
			{
				root = "workspace",
				path = { "Map", "Hub", "FishMarket", "Scales", "SellPromptAttachment" },
				offset = V(0, -0.5, -2.8),
			},
			{
				root = "workspace",
				path = { "Map", "Hub", "Workshop", "Workbench", "UpgradePromptAttachment" },
				offset = V(0, 0.5, -2.8),
			},
		},
	}
end
