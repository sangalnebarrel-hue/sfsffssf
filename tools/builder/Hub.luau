--[[
	Hub — «Остров Рыбаков», the village on the central island (Workspace.Map.Hub), World v3.
	Style contract: tools/builder/DESIGN.md §1 (bright, chunky, saturated voxel "simulator" look);
	place in the world: §2 and §6.

	Usage (Map.luau):  local hub = buildHub(map, cfg, world)
	  map    Workspace.Map
	  cfg    MapConfig (GroundTop, HubPlazaRadius, HubRadius, BridgeAngles, WaterTop)
	  world  VoxelWorld (heightAt: beach props stand on the real sand)
	Returns { model = Model "Hub", partCount = number, expectedAttachments = {...} }.

	Ground (VoxelWorld): flat grass at GroundTop (4) for r < 124, sand (y = 2) to r 150, lagoon
	water (y = 0) beyond. Angle θ → (r·sin θ, y, r·cos θ). The bridges of Map.luau land at
	θ = 0/90/180/270, r ≈ 118: their avenues stay open from the bridge to the fountain.

	Layout (r = distance from the island centre):
	  centre       «Золотая рыбка» fountain: turquoise basin, tiered pedestal with water curtains
	               and a huge crowned golden fish (top ~49 studs) riding a water spout; a round
	               paved plaza (r 50, peach checker ring), benches with lamps on the diagonals;
	               HubSpawn at θ 180, r 38, facing the fountain, between two planters
	  avenues      θ = 0/90/180/270, 25 wide: coral bricks between white kerbs from the plaza to
	               the bridge (r 46..119), two lamp pairs with bunting, flowering hedges, a tall
	               welcome gate «ОСТРОВ РЫБАКОВ» (inner side «ХОРОШЕГО КЛЁВА!») at r 104 whose sign
	               shows above the bridge arch, and tall palms at the avenue end
	  θ 45         Shop «УДОЧКИ» — yellow/red shop, giant rod with a hooked fish on the sign,
	               rod wall, display cases, counter, an old captain
	  θ 315        FishMarket «РЫБНЫЙ РЫНОК» — blue/white market hall: ice counters with fish,
	               scales, a fishmonger, a jumping fish on the roof, a fish relief on the back
	  θ 135        Workshop «МАСТЕРСКАЯ» — orange/purple garage: workbench, anvil, forge, gear
	               sign, chimney with smoke, a mechanic in a hard hat
	               (the shops face the fountain from r 58; customers stand on the porch, r 49..60)
	  θ 225        fun fair: Ferris wheel, three food kiosks with giant treats, a picnic table
	  lawns        8 pastel cottages on the outer ring (doors to the beach, a step down at each),
	               garden behind the Shop, boat yard behind the Workshop, fish yard behind the
	               market, big oaks
	  beach ring   big palms, parasols with deck chairs, a sand castle, a volleyball net
	  harbour      pier with a T-head at θ 322, moored boats, crates, lifebuoys, an anchor, and a
	               red-white lighthouse (~80 studs) on a rock islet with a breakwater at θ 300

	Every building is modelled in a local frame (origin = front centre at ground level, local −Z
	towards the fountain), so the customer side of every counter is local −Z; prompts sit 3 studs
	above the porch, just in front of the counter.
	Budget: ≤ 1800 parts and ≤ 12 PointLights (the build fails above either).
]]

local U = require("./Util")
local Props = require("./Props")

local Enum = U.Enum
local Vector3 = U.Vector3
local CFrame = U.CFrame
local rgb = U.rgb
local V = Vector3.new
local Mat = Enum.Material

local C = Props.Colors
local shade = Props.shade
local lerpColor = Props.lerpColor

local rad, sqrt, floor, abs = math.rad, math.sqrt, math.floor, math.abs

local MAX_PARTS = 1800
local MAX_LIGHTS = 12

--------------------------------------------------------------------------------
-- Palette: Props.Colors (DESIGN.md §1) + a few hub tones
--------------------------------------------------------------------------------

local H = {
	tileA = rgb(255, 244, 222), -- plaza paving (light)
	tileB = rgb(255, 210, 166), -- plaza checker (peach)
	brick = rgb(242, 126, 96), -- avenue bricks (coral)
	brickLight = rgb(255, 160, 124),
	skin = rgb(255, 206, 158),
	skinShade = rgb(242, 170, 124),
	blush = rgb(255, 140, 156),
	water = rgb(70, 212, 246),
	waterLight = rgb(184, 242, 255),
	ice = rgb(214, 246, 255),
	basin = rgb(40, 196, 222),
	basinFloor = rgb(28, 150, 214),
	yellowWall = rgb(255, 214, 72),
	orangeWall = rgb(255, 150, 48),
	lilac = rgb(200, 156, 255),
	marketWall = rgb(52, 200, 226),
	waffle = rgb(236, 168, 88),
}

--------------------------------------------------------------------------------
-- Part property sets
--------------------------------------------------------------------------------

local function merge(a: { [string]: any }?, b: { [string]: any }?): { [string]: any }
	local out = {}
	for _, t in { a or {}, b or {} } do
		for k, v in t do
			out[k] = v
		end
	end
	return out
end

local DECOR = { CanCollide = false, CastShadow = false, CanQuery = false } -- small non-walkable details
local NOSHADOW = { CastShadow = false }
local FLAT = { CastShadow = false } -- paving slabs (walkable)
local NEON = { Material = Mat.Neon, CastShadow = false }
local NEON_DECOR = merge(DECOR, { Material = Mat.Neon })
local GLASS = { Material = Mat.Glass, Transparency = 0.45, CastShadow = false }
local WATER = { Transparency = 0.3, CanCollide = false, CastShadow = false, CanQuery = false }
local SPRAY = { Transparency = 0.2, CanCollide = false, CastShadow = false, CanQuery = false }
local STREAM = merge(SPRAY, { Transparency = 0.1 }) -- falling water: nearly opaque reads as water, not glass

--------------------------------------------------------------------------------
-- Frame kit: every structure is built in a local frame with axis-aligned blocks
--------------------------------------------------------------------------------

local Frame = {}
Frame.__index = Frame

local function newFrame(model: any, cf: any): any
	return setmetatable({ model = model, cf = cf }, Frame)
end

-- A child Model `name` whose parts are placed relative to this frame * lcf.
function Frame:child(name: string, lcf: any?): any
	return newFrame(U.model(self.model, name), self.cf * (lcf or CFrame.new()))
end

-- Same Model, shifted/rotated sub-frame.
function Frame:sub(lcf: any): any
	return newFrame(self.model, self.cf * lcf)
end

-- World CFrame of a local point, facing yaw degrees (0 = local −Z): for Props placement.
function Frame:at(x: number, y: number, z: number, yaw: number?): any
	return self.cf * CFrame.new(x, y, z) * CFrame.Angles(0, rad(yaw or 0), 0)
end

function Frame:point(x: number, y: number, z: number): any
	return self.cf * V(x, y, z)
end

-- Axis-aligned block between two local corners (any order).
function Frame:box(
	name: string,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	color: any,
	extra: { [string]: any }?
): any
	local size = V(abs(x1 - x0), abs(y1 - y0), abs(z1 - z0))
	local cf = self.cf * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
	return U.part(self.model, name, size, cf, color, nil, extra)
end

-- Upright cylinder (thin round things only: poles, barrels).
function Frame:column(
	name: string,
	d: number,
	x: number,
	z: number,
	y0: number,
	y1: number,
	color: any,
	extra: { [string]: any }?
): any
	local cf = self.cf * CFrame.new(x, (y0 + y1) / 2, z) * CFrame.Angles(0, 0, rad(90))
	return U.part(self.model, name, V(y1 - y0, d, d), cf, color, nil, merge({ Shape = Enum.PartType.Cylinder }, extra))
end

local function polarFrame(model: any, angle: number, r: number, y: number): any
	return newFrame(model, U.polarCFrame(angle, r, y))
end

-- Frame at the island centre whose local +Z points along θ = angle (radial), X lateral.
local function radialFrame(model: any, angle: number, y: number): any
	return newFrame(model, CFrame.new(0, y, 0) * CFrame.Angles(0, rad(angle), 0))
end

-- Big readable sign text (DESIGN.md §1): Nunito ExtraBold, TextScaled, optional outline.
local function signText(part: any, face: any, text: string, color: any, stroke: any?): any
	local gui = U.new("SurfaceGui", {
		Name = "SignGui" .. face.Name,
		Face = face,
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 24,
		LightInfluence = 0.15,
	}, part)
	local label = U.new("TextLabel", {
		Name = "Text",
		AnchorPoint = U.Vector2.new(0.5, 0.5),
		Position = U.UDim2.fromScale(0.5, 0.5),
		Size = U.UDim2.fromScale(0.92, 0.82),
		BackgroundTransparency = 1,
		Text = text,
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = color,
	}, gui)
	if stroke then
		U.new("UIStroke", { Name = "Stroke", Color = stroke, Thickness = 5 }, label)
	end
	return label
end

local function pointLight(part: any, range: number, brightness: number, color: any?): any
	return U.new("PointLight", {
		Name = "Light",
		Range = math.min(range, 16),
		Brightness = brightness,
		Color = color or C.LightColor,
		Shadows = false,
	}, part)
end

--------------------------------------------------------------------------------
-- Characters and recurring pieces
--------------------------------------------------------------------------------

--[[
	Blocky shopkeeper: a static voxel figure ~10 studs tall with a big cute head (eyes with a
	shine, blush, nose), short legs, standing at (x, y0, z) and facing local −Z (the customer).
	o: shirt, pants, sleeve?, apron? (colour), beard = bool, hat = "captain" | "bucket" |
	"hardhat", goggles = bool. 19-23 parts, non-colliding (they stand behind counters).
]]
local function shopkeeper(F: any, x: number, y0: number, z: number, o: { [string]: any }): any
	local n = F:child("Shopkeeper", CFrame.new(x, y0, z))
	local P = DECOR
	local skin = H.skin
	local sleeve = o.sleeve or o.shirt
	n:box("LegL", -1.35, 0, -0.65, -0.12, 2.2, 0.65, o.pants, P)
	n:box("LegR", 0.12, 0, -0.65, 1.35, 2.2, 0.65, o.pants, P)
	local torso = n:box("Torso", -1.7, 2.2, -1.0, 1.7, 5.4, 1.0, o.shirt, P)
	n:box("ArmL", -2.75, 2.9, -0.6, -1.7, 5.3, 0.6, sleeve, P)
	n:box("ArmR", 1.7, 2.9, -0.6, 2.75, 5.3, 0.6, sleeve, P)
	n:box("HandL", -2.65, 2.2, -0.5, -1.8, 2.9, 0.5, skin, P)
	n:box("HandR", 1.8, 2.2, -0.5, 2.65, 2.9, 0.5, skin, P)
	if o.apron then
		n:box("Apron", -1.4, 1.2, -1.14, 1.4, 4.9, -0.96, o.apron, P)
	end
	-- the head: big and round-ish (a plus of two blocks), face on the −Z side (z = −1.75)
	n:box("Head", -1.95, 5.4, -1.75, 1.95, 8.9, 1.75, skin, P)
	n:box("Cheeks", -2.15, 6.0, -1.3, 2.15, 8.2, 1.3, skin, P)
	n:box("EyeL", -1.25, 7.0, -1.84, -0.5, 8.0, -1.7, C.Dark, P)
	n:box("EyeR", 0.5, 7.0, -1.84, 1.25, 8.0, -1.7, C.Dark, P)
	n:box("ShineL", -1.1, 7.55, -1.89, -0.82, 7.85, -1.8, C.White, P)
	n:box("ShineR", 0.65, 7.55, -1.89, 0.93, 7.85, -1.8, C.White, P)
	n:box("BlushL", -1.8, 6.4, -1.81, -1.2, 6.75, -1.7, H.blush, P)
	n:box("BlushR", 1.2, 6.4, -1.81, 1.8, 6.75, -1.7, H.blush, P)
	n:box("Nose", -0.3, 6.45, -2.05, 0.3, 7.0, -1.7, H.skinShade, P)
	if o.beard then
		n:box("Beard", -1.75, 5.1, -2.0, 1.75, 6.35, -0.9, C.White, P)
		n:box("BeardTip", -0.9, 4.4, -1.95, 0.9, 5.15, -1.0, C.White, P)
	else
		n:box("Smile", -0.6, 5.95, -1.8, 0.6, 6.2, -1.7, C.Dark, P)
	end
	if o.hat == "captain" then
		n:box("Cap", -2.0, 8.7, -1.8, 2.0, 10.1, 1.8, C.White, P)
		n:box("CapBand", -2.06, 8.66, -1.86, 2.06, 9.2, 1.86, C.Navy, P)
		n:box("Visor", -1.6, 8.6, -2.8, 1.6, 8.95, -1.8, C.Navy, P)
		n:box("Badge", -0.4, 9.3, -1.9, 0.4, 9.85, -1.78, C.Gold, P)
	elseif o.hat == "bucket" then
		n:box("Brim", -2.6, 8.65, -2.5, 2.6, 9.05, 2.5, o.hatColor or C.Yellow, P)
		n:box("Crown", -1.9, 9.0, -1.8, 1.9, 10.5, 1.8, lerpColor(o.hatColor or C.Yellow, C.White, 0.25), P)
	else -- hard hat
		n:box("Shell", -2.0, 8.7, -1.8, 2.0, 10.3, 1.8, C.Yellow, P)
		n:box("Brim", -2.3, 8.62, -2.4, 2.3, 8.95, 2.1, shade(C.Yellow, 0.9), P)
		n:box("Ridge", -0.45, 10.25, -1.85, 0.45, 10.75, 1.85, C.Orange, P)
	end
	if o.goggles then
		n:box("GogglesBand", -2.05, 9.25, -1.86, 2.05, 9.7, 1.86, C.Dark, P)
		n:box("GogglesL", -1.3, 9.1, -1.98, -0.25, 9.95, -1.84, C.Cyan, P)
		n:box("GogglesR", 0.25, 9.1, -1.98, 1.3, 9.95, -1.84, C.Cyan, P)
	end
	n.model.PrimaryPart = torso
	return n.model
end

--[[
	Big cartoon voxel fish lying along local X (head at −X), its side towards ±Z, centred on the
	frame origin; s scales it (s = 1: ~27 long, ~16 tall). pal: body, head, belly, fin, lips,
	spots. opts.crown (golden crown with gems), opts.simple (10 parts: no belly, fins, scales,
	shine). 16-24 parts. opts.extra (property set for the big parts).
]]
local function bigFish(F: any, s: number, pal: { [string]: any }, opts: { [string]: any }?): any
	local o = opts or {}
	local big = o.extra or {}
	local function b(
		name: string,
		x0: number,
		y0: number,
		z0: number,
		x1: number,
		y1: number,
		z1: number,
		c: any,
		ex: any?
	)
		return F:box(name, x0 * s, y0 * s, z0 * s, x1 * s, y1 * s, z1 * s, c, ex)
	end
	local body = b("Body", -8, -5, -3.5, 6, 5, 3.5, pal.body, big)
	b("Head", -12.2, -4, -3.1, -7.6, 4.4, 3.1, pal.head or pal.body, big)
	b("Lips", -13.8, -2.6, -1.9, -11.9, 0.2, 1.9, pal.lips, NOSHADOW)
	b("TailStem", 5.6, -2.6, -2.1, 9.6, 2.6, 2.1, pal.body, big)
	b("TailUp", 9.2, 1.2, -1.2, 13.4, 7.8, 1.2, pal.fin, big)
	b("TailDown", 9.2, -7.8, -1.2, 13.4, -1.2, 1.2, pal.fin, big)
	for i, sz in { -1, 1 } do
		b(`Eye{i}`, -11.4, -0.2, sz * 2.95, -8.0, 3.6, sz * 3.35, C.White, DECOR)
		b(`Pupil{i}`, -10.9, 0.4, sz * 3.25, -8.9, 2.8, sz * 3.5, C.Dark, DECOR)
	end
	if not o.simple then
		b("Belly", -7.6, -5.6, -3.6, 4.4, -2.2, 3.6, pal.belly, big)
		b("Dorsal", -4.4, 4.6, -1.1, 3.2, 8.8, 1.1, pal.fin, big)
		b("FinL", -4, -3.6, -4.8, 0.4, -1.4, -3.4, pal.fin, NOSHADOW)
		b("FinR", -4, -3.6, 3.4, 0.4, -1.4, 4.8, pal.fin, NOSHADOW)
		for i, sz in { -1, 1 } do
			b(`Shine{i}`, -10.5, 2.0, sz * 3.45, -9.8, 2.6, sz * 3.6, C.White, DECOR)
			b(`Spot{i}`, -3.6, -0.6, sz * 3.5, 0.6, 3.0, sz * 3.68, pal.spots or pal.belly, DECOR)
		end
	end
	if o.crown then
		local gold = C.GoldLight
		b("CrownBand", -11.7, 4.2, -2.2, -7.9, 5.6, 2.2, gold, NEON)
		for i, x in { -11.25, -9.8, -8.35 } do
			b(`CrownSpike{i}`, x - 0.45, 5.5, -0.5, x + 0.45, 7.3, 0.5, gold, NEON)
		end
		b("Gem1", -10.3, 4.5, -2.42, -9.3, 5.3, -2.15, C.Red, DECOR)
		b("Gem2", -10.3, 4.5, 2.15, -9.3, 5.3, 2.42, C.Cyan, DECOR)
	end
	return body
end

-- Small fish lying on a counter or in a crate along local X: body + tail. 2 parts.
local function smallFish(F: any, x: number, y: number, z: number, len: number, color: any)
	F:box("Fish", x - len / 2, y, z - len * 0.2, x + len * 0.25, y + len * 0.3, z + len * 0.2, color, DECOR)
	F:box(
		"FishTail",
		x + len * 0.25,
		y + 0.03,
		z - len * 0.16,
		x + len / 2,
		y + len * 0.27,
		z + len * 0.16,
		shade(color, 0.82),
		DECOR
	)
end

--[[
	Voxel gear facing −Z in the local XY plane, centre (cx, cy, cz), outer radius r: a rounded
	body (plus of two blocks), 4 square teeth on the axes and 4 on the diagonals (pixel-art
	steps), and a hub. 11 parts.
]]
local function gear(F: any, cx: number, cy: number, cz: number, r: number, t: number, color: any, hub: any)
	local b = r * 0.62
	local k = r * 0.38
	F:box("Gear", cx - b, cy - k, cz - t / 2, cx + b, cy + k, cz + t / 2, color)
	F:box("GearB", cx - k, cy - b, cz - t / 2 - 0.02, cx + k, cy + b, cz + t / 2 + 0.02, color)
	local tw = r * 0.34
	for i, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		local tx, ty = cx + d[1] * (r - tw / 2), cy + d[2] * (r - tw / 2)
		F:box(`Tooth{i}`, tx - tw / 2, ty - tw / 2, cz - t / 2, tx + tw / 2, ty + tw / 2, cz + t / 2, color)
	end
	local dd = r * 0.56
	for i, d in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		local tx, ty = cx + d[1] * dd, cy + d[2] * dd
		F:box(`ToothD{i}`, tx - tw / 2, ty - tw / 2, cz - t / 2, tx + tw / 2, ty + tw / 2, cz + t / 2, color)
	end
	F:box(
		"GearHub",
		cx - r * 0.24,
		cy - r * 0.24,
		cz - t / 2 - 0.15,
		cx + r * 0.24,
		cy + r * 0.24,
		cz + t / 2 + 0.15,
		hub
	)
end

--[[
	Raised flower bed centred at (cx, cz), w along X, d along Z: white border block, soil, a green
	cushion and one row of cube flowers along the long side. 3 + n parts.
]]
local function flowerBed(F: any, cx: number, cz: number, w: number, d: number, colors: { any }, border: any?)
	F:box("Bed", cx - w / 2, -0.3, cz - d / 2, cx + w / 2, 1.0, cz + d / 2, border or C.White)
	F:box(
		"Soil",
		cx - w / 2 + 0.45,
		1.0,
		cz - d / 2 + 0.45,
		cx + w / 2 - 0.45,
		1.15,
		cz + d / 2 - 0.45,
		C.DirtDark,
		DECOR
	)
	F:box("Greens", cx - w / 2 + 0.7, 1.1, cz - d / 2 + 0.7, cx + w / 2 - 0.7, 1.8, cz + d / 2 - 0.7, C.Leaf1, DECOR)
	local alongX = w >= d
	local L = if alongX then w else d
	local n = math.max(2, floor((L - 1.4) / 2.2))
	for i = 1, n do
		local t = -L / 2 + 0.7 + (L - 1.4) * (i - 0.5) / n
		local x = if alongX then cx + t else cx + (if i % 2 == 0 then 0.35 else -0.35)
		local z = if alongX then cz + (if i % 2 == 0 then 0.35 else -0.35) else cz + t
		local h = 1.7 + (i % 3) * 0.18
		F:box(`Flower{i}`, x - 0.6, h, z - 0.6, x + 0.6, h + 0.9, z + 0.6, colors[(i - 1) % #colors + 1], DECOR)
	end
end

--------------------------------------------------------------------------------
-- Shop buildings (local frame: origin = front centre at ground level, −Z = customers)
--------------------------------------------------------------------------------

local FL = 1.0 -- floor level of the shops above the plaza ground (porch and interior)

-- Shop dimensions: half width, depth (front z = 0 .. back z = D), half width of the open front
-- between the corner pillars, top of the opening. The porch runs from z = −8.5 to 2.
local HW, D, OH, OPEN = 23, 34, 19, 13.6

--[[
	Shared shell of the Shop and the Workshop: stone plinth with a front porch, interior floor,
	4 corner pillars, side and back walls with a darker bottom band and windows, an open front
	(x ±OH, up to y = OPEN) under a lintel with a trim band, and a cornice on the wall tops.
	s: wall, pillar, trim, porch, floor, wallH. 25 parts. Returns the plinth.
]]
local function shopShell(F: any, s: { [string]: any }): any
	local h = s.wallH
	local wi = HW - 3.6 -- inner face of the side walls
	local bi = D - 3.6 -- inner face of the back wall
	local wo = HW - 0.4 -- outer face of the side walls
	local plinth = F:box("Plinth", -HW - 1, -0.5, -9, HW + 1, FL - 0.4, D + 1, C.StoneLight, FLAT)
	F:box("Porch", -HW - 0.4, FL - 0.4, -8.5, HW + 0.4, FL, 2, s.porch, FLAT)
	F:box("Floor", -wi, FL - 0.4, 2, wi, FL, bi, s.floor, FLAT)
	for i, p in { { -1, 0 }, { 1, 0 }, { -1, D - 4 }, { 1, D - 4 } } do
		F:box(`Pillar{i}`, p[1] * OH, FL - 0.4, p[2], p[1] * HW, h, p[2] + 4, s.pillar)
	end
	F:box("WallL", -wo, FL - 0.4, 4, -wi, h, D - 4, s.wall)
	F:box("WallR", wi, FL - 0.4, 4, wo, h, D - 4, s.wall)
	F:box("WallBack", -OH, FL - 0.4, bi, OH, h, D - 0.4, s.wall)
	F:box("Lintel", -OH, OPEN, 0.4, OH, h, 3.6, s.wall)
	F:box("LintelTrim", -OH, OPEN - 0.5, 0.1, OH, OPEN + 0.3, 3.8, s.trim)
	F:box("Cornice", -HW - 0.8, h, -0.8, HW + 0.8, h + 1.4, D + 0.8, s.pillar)
	local band = shade(s.wall, 0.86)
	F:box("BandL", -wo - 0.15, FL - 0.4, 3.9, -wi - 0.2, FL + 1.8, D - 3.9, band, NOSHADOW)
	F:box("BandR", wi + 0.2, FL - 0.4, 3.9, wo + 0.15, FL + 1.8, D - 3.9, band, NOSHADOW)
	F:box("BandBack", -OH - 0.1, FL - 0.4, bi + 0.2, OH + 0.1, FL + 1.8, D - 0.25, band, NOSHADOW)
	-- windows: a wide one on each side, two on the back (the side the bases see)
	for i, sx in { -1, 1 } do
		F:box(`WinFrame{i}`, sx * (wo - 0.15), 5.2, 10, sx * (wo + 0.35), 12.4, 24, C.White, NOSHADOW)
		F:box(`WinGlass{i}`, sx * wo, 5.9, 10.7, sx * (wo + 0.5), 11.7, 23.3, C.WindowBlue, NOSHADOW)
		F:box(`WinBar{i}`, sx * (wo + 0.1), 5.8, 16.6, sx * (wo + 0.6), 11.8, 17.4, C.White, NOSHADOW)
	end
	for i, x in { -10, 10 } do
		F:box(`BackFrame{i}`, x - 5, 5.2, D - 0.55, x + 5, 12.4, D - 0.05, C.White, NOSHADOW)
		F:box(`BackGlass{i}`, x - 4.3, 5.9, D - 0.4, x + 4.3, 11.7, D + 0.1, C.WindowBlue, NOSHADOW)
	end
	return plinth
end

-- Framed sign board in the local XY plane centred on depth zc (front = −Z): white frame, the
-- board, Neon rims on top and at the sides, text on both faces. 5 parts. Returns the board.
local function signBoard(
	F: any,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	zc: number,
	board: any,
	rim: any,
	text: string,
	backText: string?
): any
	F:box(name .. "Frame", x0 - 1, y0 - 0.8, zc - 0.5, x1 + 1, y1 + 0.8, zc + 0.5, C.White)
	local b = F:box(name, x0, y0, zc - 0.8, x1, y1, zc + 0.8, board)
	F:box(name .. "Rim", x0 - 1, y1 + 0.8, zc - 0.5, x1 + 1, y1 + 1.6, zc + 0.5, rim, NEON)
	F:box(name .. "RimL", x0 - 1.8, y0 - 0.8, zc - 0.4, x0 - 1, y1 + 1.6, zc + 0.4, rim, NEON)
	F:box(name .. "RimR", x1 + 1, y0 - 0.8, zc - 0.4, x1 + 1.8, y1 + 1.6, zc + 0.4, rim, NEON)
	signText(b, Enum.NormalId.Front, text, C.White, C.Navy)
	signText(b, Enum.NormalId.Back, backText or text, C.White, C.Navy)
	return b
end

-- Stepped striped awning: two steps down from the facade at zFace, n stripes alternating
-- c1/c2 between x0 and x1, scallops hanging under the c1 stripes. 2n + n/2 parts.
local function awning(
	F: any,
	x0: number,
	x1: number,
	yTop: number,
	zFace: number,
	depth: number,
	n: number,
	c1: any,
	c2: any
)
	local w = (x1 - x0) / n
	local zMid = zFace - depth * 0.45
	local zEnd = zFace - depth
	for i = 0, n - 1 do
		local a, b = x0 + i * w, x0 + (i + 1) * w
		local col = if i % 2 == 0 then c1 else c2
		F:box(`AwningA{i}`, a, yTop - 0.9, zMid, b, yTop, zFace + 0.2, col, NOSHADOW)
		F:box(`AwningB{i}`, a, yTop - 1.8, zEnd, b, yTop - 0.9, zMid, col)
		if i % 2 == 0 then
			F:box(`Scallop{i}`, a + 0.5, yTop - 2.8, zEnd - 0.05, b - 0.5, yTop - 1.8, zEnd + 0.5, col, DECOR)
		end
	end
end

--[[
	Shop «УДОЧКИ» (sells rods): yellow walls, red pillars and a stepped red roof, a false-front sign
	crowned by a giant fishing rod with a hooked fish, a red/white awning, a rod wall inside,
	glass display cases, the counter (Counter.ShopPromptAttachment) and an old captain behind it.
]]
local function buildShop(hub: any, cf: any): (any, any)
	local F = newFrame(U.model(hub, "Shop"), cf)
	local red, redLight = C.Red, rgb(255, 124, 108)
	local h = 22
	local plinth = shopShell(
		F,
		{ wall = H.yellowWall, pillar = red, trim = C.White, porch = C.WoodLight, floor = H.tileA, wallH = h }
	)

	-- stepped pitched roof, ridge along X, and a chimney
	local y = h + 1.4
	for i = 0, 3 do
		local d = 1.5 + i * 3
		F:box(`Roof{i + 1}`, -HW - 0.4, y, d, HW + 0.4, y + 1.8, D - d, if i % 2 == 0 then redLight else red)
		y += 1.8
	end
	F:box("Ridge", -HW - 1, y, D / 2 - 1.5, HW + 1, y + 1, D / 2 + 1.5, C.White)
	F:box("Chimney", 12, 26, 21, 15.6, 36, 24.6, C.White)
	F:box("ChimneyTop", 11.6, 36, 20.6, 16, 37.2, 25, red)

	-- false-front sign with a giant rod on top; a fish dangles from the line
	signBoard(F, "Sign", -18, 18, h + 1.8, h + 13.8, 0, red, C.Yellow, "УДОЧКИ")
	local rod = F:sub(CFrame.new(-19.6, h + 15.8, 0) * CFrame.Angles(0, 0, rad(38)))
	rod:box("RodHandle", -0.4, -0.9, -0.9, 4.8, 0.9, 0.9, C.Red)
	rod:box("RodReel", 2.6, -2.5, -1.1, 4.4, -0.9, 1.1, C.Yellow, NOSHADOW)
	rod:box("Rod1", 4.8, -0.55, -0.55, 18, 0.55, 0.55, C.Blue)
	rod:box("Rod2", 18, -0.38, -0.38, 30, 0.38, 0.38, C.Blue, NOSHADOW)
	local tip = rod:box("RodTip", 30, -0.45, -0.45, 31.4, 0.45, 0.45, C.White, NOSHADOW)
	local tipPos = F.cf:PointToObjectSpace(tip.CFrame.Position)
	local hookY, fs = h + 29, 0.4
	F:box("Line", tipPos.X - 0.12, hookY, -0.12, tipPos.X + 0.12, tipPos.Y, 0.12, C.White, DECOR)
	-- the fish's lips (fish-local (−13.8, −1.2)) hang on the hook, the body wriggles down-right
	local hooked =
		F:sub(CFrame.new(tipPos.X, hookY, 0) * CFrame.Angles(0, 0, rad(-52)) * CFrame.new(13.8 * fs, 1.2 * fs, 0))
	bigFish(hooked, fs, { body = C.Orange, head = rgb(255, 176, 70), fin = C.Red, lips = C.Pink }, { simple = true })

	-- subtitle on the lintel, awning, lifebuoy on the pillar
	local sub = F:box("SubSign", -12.5, OPEN + 1.4, -0.1, 12.5, OPEN + 7, 0.45, C.White, NOSHADOW)
	signText(sub, Enum.NormalId.Front, "Купить удочку", C.Red)
	awning(F, -OH, OH, OPEN, 0.2, 7, 6, red, C.White)
	Props.lifebuoy(F.model, F:at(-21, 9.5, -0.1), { seed = 11 })

	-- the counter and glass display cases close the opening
	local counter = F:box("Counter", -8, FL, 2.6, 8, 4.4, 5.6, red)
	F:box("CounterTop", -8.4, 4.4, 2.2, 8.4, 5.0, 6.0, C.White)
	F:box("CounterStripe", -8.06, 2.3, 2.54, 8.06, 3.0, 5.66, C.Yellow, NOSHADOW)
	U.new("Attachment", { Name = "ShopPromptAttachment", CFrame = CFrame.new(0, 1.3, -2.3) }, counter)
	for i, sx in { -1, 1 } do
		F:box(`Case{i}`, sx * 8.4, FL, 2.6, sx * OH, 3.2, 5.6, C.White)
		F:box(`CaseGlass{i}`, sx * 8.5, 3.2, 2.7, sx * (OH - 0.1), 4.6, 5.5, C.Glass, GLASS)
		F:box(`CaseRodA{i}`, sx * 9.2, 3.25, 3.4, sx * (OH - 0.8), 3.6, 3.75, C.Blue, DECOR)
		F:box(`CaseRodB{i}`, sx * 9.2, 3.25, 4.5, sx * (OH - 0.8), 3.6, 4.85, C.Lime, DECOR)
	end
	shopkeeper(F, 0, FL, 9, { shirt = C.Blue, pants = C.Navy, sleeve = C.White, beard = true, hat = "captain" })

	-- interior: rod wall, a shelf with tackle boxes, a trophy fish, a ceiling lamp
	local bi, wi = D - 3.6, HW - 3.6
	F:box("RodWall", -15, 2.6, bi - 0.6, 15, 17, bi, C.WoodLight, NOSHADOW)
	for k = 0, 5 do
		local x = -10 + k * 4
		F:box(`Rod{k + 1}`, x - 0.3, 3.2, bi - 1.2, x + 0.3, 16.4, bi - 0.6, C.Festive[k + 1], DECOR)
		F:box(`Reel{k + 1}`, x - 0.75, 5.4, bi - 1.7, x + 0.75, 6.7, bi - 1.1, C.White, DECOR)
	end
	F:box("Shelf", -wi, 7, 10, -wi + 2, 7.5, 24, C.Wood, NOSHADOW)
	for i, c in { C.Red, C.Cyan, C.Yellow } do
		local z = 8 + i * 4.5
		F:box(`Tackle{i}`, -wi + 0.2, 7.5, z - 0.9, -wi + 1.8, 9.0, z + 0.9, c, DECOR)
	end
	F:box("Trophy", wi - 0.6, 8, 13.5, wi, 13, 20.5, C.Wood, NOSHADOW)
	F:box("TrophyFish", wi - 1.2, 9.4, 14.4, wi - 0.6, 11.6, 18.4, C.Cyan, DECOR)
	F:box("TrophyTail", wi - 1.1, 9.0, 18.4, wi - 0.7, 12.0, 19.6, C.Blue, DECOR)
	local lamp = F:box("CeilingLamp", -1.6, h - 3, 15, 1.6, h - 1.8, 18, C.Glow, NEON_DECOR)
	F:box("LampCord", -0.15, h - 1.8, 16.35, 0.15, h, 16.65, C.Dark, DECOR)
	pointLight(lamp, 16, 1.3)

	-- outside: rod rack, a barrel of rods, flower boxes under the side windows
	Props.fishingRodRack(F.model, F:at(-16.5, FL, -4.6), { seed = 3 })
	local barrel = Props.barrel(F.model, F:at(19.6, FL, -5.2), { color = C.Wood, seed = 4 })
	local bp = F.cf:PointToObjectSpace(barrel.PrimaryPart.CFrame.Position)
	for i, c in { C.Red, C.Yellow, C.Cyan } do
		local dx = (i - 2) * 0.6
		local dz = (i % 2) * 0.4
		F:box(`BarrelRod{i}`, bp.X + dx - 0.15, 3, bp.Z - 0.2 + dz, bp.X + dx + 0.15, 11.5, bp.Z + 0.1 + dz, c, DECOR)
	end
	for i, sx in { -1, 1 } do
		Props.flowerBox(F.model, F:at(sx * (HW + 0.45), 3.55, 17, sx * 90), { length = 12, color = red, seed = 20 + i })
	end
	F.model.PrimaryPart = plinth
	return F.model, counter
end

--[[
	Workshop «МАСТЕРСКАЯ» (upgrades): orange walls, purple pillars and a stepped barn roof, a big
	gear on the sign, a chimney with smoke, a rolled-up garage door, a workbench with tools and a
	glowing upgrade gem (Workbench.UpgradePromptAttachment), a tool chest, an anvil, a pegboard, a
	glowing forge and a mechanic in a hard hat.
]]
local function buildWorkshop(hub: any, cf: any): (any, any)
	local F = newFrame(U.model(hub, "Workshop"), cf)
	local purple, lilac = C.Purple, H.lilac
	local wall = H.orangeWall
	local h = 21
	local plinth = shopShell(
		F,
		{ wall = wall, pillar = purple, trim = C.Yellow, porch = C.WoodLight, floor = C.WoodLight, wallH = h }
	)
	local bi, wi = D - 3.6, HW - 3.6

	-- stepped barn roof (ridge along Z, gable towards the plaza), chimney with smoke
	local y = h + 1.4
	for i = 0, 3 do
		local w = HW - 4 - i * 4.4
		F:box(`Roof{i + 1}`, -w, y, -0.4 + i * 0.01, w, y + 1.8, D + 0.4, if i % 2 == 0 then lilac else purple)
		y += 1.8
	end
	F:box("Chimney", 13, h + 0.6, D - 13, 17, h + 16, D - 9, C.White)
	F:box("ChimneyBand", 12.8, h + 12, D - 13.2, 17.2, h + 13.4, D - 8.8, C.Red, NOSHADOW)
	F:box("ChimneyTop", 12.6, h + 16, D - 13.4, 17.4, h + 17.2, D - 8.6, C.Red)
	for i, p in { { 15, h + 19.4, D - 11, 2.8 }, { 16.8, h + 22.6, D - 11.8, 2.2 }, { 18.8, h + 25.4, D - 12.6, 1.7 } } do
		local r = p[4] / 2
		F:box(
			`Smoke{i}`,
			p[1] - r,
			p[2] - r,
			p[3] - r,
			p[1] + r,
			p[2] + r,
			p[3] + r,
			rgb(244, 246, 252),
			merge(DECOR, { Transparency = 0.1 })
		)
	end

	-- sign with a big gear on top
	signBoard(F, "Sign", -16, 16, h + 2, h + 11, -1.2, rgb(124, 70, 224), C.Lime, "МАСТЕРСКАЯ")
	gear(F, 0, h + 19, -1.2, 6.4, 1.4, C.Yellow, C.Orange)

	-- rolled-up garage door under the lintel, subtitle
	F:box("DoorRoll", -OH, OPEN - 2, 0.6, OH, OPEN - 0.5, 3.4, C.Yellow, NOSHADOW)
	for i, x in { -14, -5, 5, 14 } do
		F:box(`DoorStripe{i}`, x - 1.2, OPEN - 2.05, 0.5, x + 1.2, OPEN - 0.45, 3.5, C.Navy, DECOR)
	end
	local sub = F:box("SubSign", -11, OPEN + 1.2, -0.1, 11, OPEN + 6.6, 0.45, C.White, NOSHADOW)
	signText(sub, Enum.NormalId.Front, "Улучшения", rgb(124, 70, 224))

	-- the workbench (counter) with tools and a glowing upgrade gem
	local bench = F:box("Workbench", -8, FL, 2.6, 8, 4.0, 5.6, C.Wood)
	F:box("BenchTop", -8.6, 4.0, 2.2, 8.6, 4.7, 6.0, C.WoodLight)
	F:box("DrawerL", -6.8, 1.7, 2.45, -1.2, 3.4, 2.65, wall, NOSHADOW)
	F:box("DrawerR", 1.2, 1.7, 2.45, 6.8, 3.4, 2.65, wall, NOSHADOW)
	U.new("Attachment", { Name = "UpgradePromptAttachment", CFrame = CFrame.new(0, 1.5, -2.3) }, bench)
	F:box("HammerHandle", 3, 4.7, 3.6, 5.7, 5.1, 4.0, C.WoodDark, DECOR)
	F:box("HammerHead", 5.6, 4.75, 3.2, 6.8, 5.6, 4.4, C.Iron, DECOR)
	F:box("Wrench", -6.4, 4.7, 4.4, -2.6, 5.0, 4.9, C.StoneLight, DECOR)
	F:box("WrenchJaw", -7.2, 4.75, 4.0, -6.2, 5.05, 5.3, C.StoneLight, DECOR)
	F:box("GemStand", -0.7, 4.7, 3.4, 0.7, 5.4, 4.8, C.Gold, NOSHADOW)
	F:box("UpgradeGem", -0.55, 5.4, 3.55, 0.55, 6.6, 4.65, C.Cyan, NEON_DECOR)
	-- tool chest (left), anvil and a crate (right) close the opening
	F:box("ToolChest", -OH, FL, 2.6, -8.9, 5.0, 6.2, C.Red)
	F:box("ChestDrawer1", -OH + 0.6, 3.4, 2.45, -9.5, 3.8, 2.65, C.White, DECOR)
	F:box("ChestDrawer2", -OH + 0.6, 2.0, 2.45, -9.5, 2.4, 2.65, C.White, DECOR)
	F:box("AnvilStump", 9.8, FL, 3, 13.8, 2.8, 6, C.Bark)
	F:box("AnvilBase", 10.4, 2.8, 3.6, 13.2, 3.6, 5.4, C.Navy)
	F:box("AnvilTop", 9.6, 3.6, 3.3, 14.2, 4.8, 5.7, C.Navy)
	F:box("AnvilHorn", 14.2, 3.9, 3.9, 15.6, 4.6, 5.1, C.Navy, NOSHADOW)
	Props.crate(F.model, F:at(17.3, FL, 4.1), { size = 3.2, color = C.Yellow, seed = 6 })
	shopkeeper(F, 0, FL, 9, { shirt = C.Blue, pants = C.Blue, sleeve = C.Orange, hat = "hardhat", goggles = true })

	-- interior: pegboard with tools, a glowing forge, a boat motor on a stand
	F:box("Pegboard", -9.6, 4, bi - 0.6, 14, 15, bi, C.Cream, NOSHADOW)
	local pz0, pz1 = bi - 1.0, bi - 0.6
	F:box("PegWrench", -7.2, 5.5, pz0, -6.0, 12.5, pz1, C.Red, DECOR)
	F:box("PegWrenchJaw", -8.0, 11.8, pz0, -5.2, 13.2, pz1, C.Red, DECOR)
	F:box("PegHammer", -1.0, 5.5, pz0, -0.2, 12, pz1, C.Wood, DECOR)
	F:box("PegHammerHead", -2.4, 11, pz0 - 0.1, 1.2, 12.8, pz1, C.Blue, DECOR)
	F:box("PegSaw", 4.4, 7.5, pz0, 10.9, 10.5, pz1, C.StoneLight, DECOR)
	F:box("PegSawHandle", 10.9, 7.2, pz0 - 0.1, 12.4, 10.8, pz1, C.Yellow, DECOR)
	F:box("Forge", -wi, FL, 23, -13, 6.4, bi, C.StoneLight)
	local glow = F:box("ForgeFire", -17.6, 2, 22.85, -14.8, 4.6, 23.2, C.Flame, NEON_DECOR)
	F:box("ForgeHood", -wi, 6.4, 24, -13.4, 10, bi, C.Red)
	F:box("ForgeFlue", -17.4, 10, 26, -15.4, h, 28, C.Red, NOSHADOW)
	pointLight(glow, 14, 1.6, rgb(255, 160, 80))
	F:box("MotorStand", 14, FL, 20, 17.4, 3.2, 25, C.Wood)
	F:box("Motor", 14.7, 3.2, 21.4, 16.7, 7.0, 23.6, C.Red)
	F:box("MotorCap", 14.5, 7.0, 21.2, 16.9, 7.8, 23.8, C.White, NOSHADOW)

	-- outside: a giant wrench leaning on the wall, barrels on the porch
	local wrench = F:sub(CFrame.new(-HW - 2.6, 0, 14) * CFrame.Angles(0, 0, rad(-12)))
	wrench:box("BigWrench", -0.5, 0, -0.8, 0.5, 11, 0.8, C.StoneLight, NOSHADOW)
	wrench:box("BigWrenchJawA", -0.5, 10.4, -2.4, 0.5, 13.4, -0.8, C.StoneLight, NOSHADOW)
	wrench:box("BigWrenchJawB", -0.5, 10.4, 0.8, 0.5, 13.4, 2.4, C.StoneLight, NOSHADOW)
	Props.barrel(F.model, F:at(19.8, FL, -5.6), { color = C.Blue, seed = 7 })
	Props.barrel(F.model, F:at(16.4, FL, -6.4), { color = C.Red, seed = 8 })
	F.model.PrimaryPart = plinth
	return F.model, bench
end

--[[
	FishMarket «РЫБНЫЙ РЫНОК» (sells fish): an open market hall on six white posts under a stepped
	blue/white roof with a scalloped valance, a cyan back wall with a «СВЕЖАЯ РЫБА» board, ice
	counters with colourful fish, crates of fish, the scales (Scales.SellPromptAttachment) on the
	front counter, a fishmonger and a big jumping fish on the roof.
]]
local function buildFishMarket(hub: any, cf: any): (any, any)
	local F = newFrame(U.model(hub, "FishMarket"), cf)
	local blue, white = C.Blue, C.White
	local fishColors = { C.Orange, C.Pink, C.Yellow, C.Purple, C.Red, C.Lime }
	local px = HW - 2.4 -- inner face of the posts
	local plinth = F:box("Plinth", -HW - 1, -0.5, -9, HW + 1, FL - 0.4, D + 1, C.StoneLight, FLAT)
	F:box("Floor", -HW - 0.4, FL - 0.4, -8.5, HW + 0.4, FL, D + 0.4, rgb(236, 248, 255), FLAT)
	local top = 17
	for i, z in { 0, 16, D - 2.4 } do
		for j, sx in { -1, 1 } do
			F:box(`Post{i}_{j}`, sx * px, FL, z - 1.2, sx * HW, top, z + 1.2, white)
			F:box(
				`PostBase{i}_{j}`,
				sx * (px - 0.25),
				FL,
				z - 1.45,
				sx * (HW + 0.25),
				FL + 2.2,
				z + 1.45,
				blue,
				NOSHADOW
			)
		end
	end
	F:box("BackWall", -px, FL, D - 3.2, px, top, D - 0.6, H.marketWall)
	F:box("BackWave", -px, 3.4, D - 0.75, px, 4.6, D - 0.45, white, NOSHADOW)
	local relief = F:sub(CFrame.new(0, 10.4, D - 0.6) * CFrame.Angles(0, math.pi, 0))
	bigFish(
		relief,
		0.5,
		{ body = C.Orange, head = rgb(255, 176, 70), fin = C.Yellow, lips = C.Pink },
		{ simple = true }
	)
	local fresh = F:box("FreshBoard", -11, 9, D - 3.7, 11, 14, D - 3.2, white, NOSHADOW)
	signText(fresh, Enum.NormalId.Front, "СВЕЖАЯ РЫБА", blue)

	-- stepped hip roof: blue / white layers, scalloped valance
	local y = top
	for i = 0, 4 do
		local wx, z0, z1 = HW + 2.5 - i * 3, -3.5 + i * 3, D + 2 - i * 3
		F:box(`Roof{i + 1}`, -wx, y, z0, wx, y + 1.6, z1, if i % 2 == 0 then blue else white)
		y += 1.6
	end
	local roofTop = y
	local vw = (2 * HW + 5) / 7
	for i = 0, 6 do
		local x0 = -HW - 2.5 + i * vw
		F:box(
			`Valance{i}`,
			x0 + 0.2,
			top - 1.4,
			-3.6,
			x0 + vw - 0.2,
			top,
			-3.0,
			if i % 2 == 0 then white else blue,
			DECOR
		)
	end
	-- sign in front of the roof, subtitle board hanging under the valance
	signBoard(F, "Sign", -19, 19, top + 1.8, top + 10.8, -4.3, blue, C.Cyan, "РЫБНЫЙ РЫНОК")
	local sub = F:box("SubSign", -8, 11.4, -3.2, 8, 14.6, -2.6, white, NOSHADOW)
	signText(sub, Enum.NormalId.Front, "Продать рыбу", blue)
	F:box("SubRopeL", -6.6, 14.6, -3.0, -6.3, top - 1.4, -2.8, C.Navy, DECOR)
	F:box("SubRopeR", 6.3, 14.6, -3.0, 6.6, top - 1.4, -2.8, C.Navy, DECOR)

	-- big fish jumping on the roof top
	F:box("FishPole", -0.6, roofTop, D / 2 - 0.6, 0.6, roofTop + 3.4, D / 2 + 0.6, white, NOSHADOW)
	local jumper = F:sub(CFrame.new(0, roofTop + 8.4, D / 2) * CFrame.Angles(0, 0, rad(-18)))
	bigFish(jumper, 0.62, { body = C.Cyan, head = rgb(120, 236, 240), fin = blue, lips = C.Pink }, { simple = true })

	-- front ice counter with fish and the scales; side wings and crates of fish close the front
	F:box("Counter", -10, FL, 2.4, 10, 3.6, 5.6, blue)
	F:box("CounterStripe", -10.06, 2.0, 2.34, 10.06, 2.6, 5.66, white, NOSHADOW)
	F:box("Ice", -10.3, 3.6, 2.1, 10.3, 4.2, 5.9, H.ice)
	for i, x in { -8, -5, 5, 8 } do
		smallFish(F, x, 4.2, 4.0 + (i % 2) * 0.5, 2.6, fishColors[i])
	end
	local scales = F:box("Scales", -1.8, 4.2, 2.6, 1.8, 5.4, 5.0, C.Red)
	F:box("ScalesDial", -1.2, 5.4, 3.3, 1.2, 7.8, 4.3, white)
	F:box("ScalesNeedle", -0.12, 6.2, 3.18, 0.12, 7.4, 3.32, C.Red, DECOR)
	F:box("ScalesPlate", -2.2, 7.8, 2.6, 2.2, 8.2, 5.0, C.StoneLight, NOSHADOW)
	U.new("Attachment", { Name = "SellPromptAttachment", CFrame = CFrame.new(0, -0.8, -2.3) }, scales)
	for i, sx in { -1, 1 } do
		F:box(`WingCounter{i}`, sx * 14, FL, 2.4, sx * px, 3.6, 5.6, white)
		F:box(`WingIce{i}`, sx * 13.8, 3.6, 2.1, sx * px, 4.2, 5.9, H.ice)
		F:box(`SideCounter{i}`, sx * (px - 2.8), FL, 7, sx * px, 3.6, 28, white)
		F:box(`SideIce{i}`, sx * (px - 3.0), 3.6, 6.8, sx * px, 4.2, 28.2, H.ice)
		smallFish(F, sx * 17.2, 4.2, 4.0, 2.6, fishColors[i + 3])
		for k = 1, 3 do
			smallFish(F, sx * (px - 1.4), 4.2, 6 + k * 5.5, 2.4, fishColors[(i * 3 + k) % #fishColors + 1])
		end
		Props.crate(F.model, F:at(sx * 12.15, FL, 4.1), { size = 3.4, color = C.WoodLight, seed = 30 + i })
		smallFish(F, sx * 12.15, FL + 3.45, 4.1, 2.6, fishColors[i + 2])
	end
	shopkeeper(F, 0, FL, 9, { shirt = C.Cyan, pants = C.Navy, apron = white, hat = "bucket", hatColor = C.Yellow })
	local lamp = F:box("CeilingLamp", -1.6, top - 2.6, 13, 1.6, top - 1.4, 16, C.Glow, NEON_DECOR)
	pointLight(lamp, 16, 1.3)

	-- outside: a cooler, a barrel, a lifebuoy post
	Props.cooler(F.model, F:at(18.6, FL, -6), { color = C.Red, seed = 13 })
	Props.barrel(F.model, F:at(-19.4, FL, -5.6), { color = C.Cyan, seed = 14 })
	F:box("BuoyPost", HW + 1.4, -0.3, 21.4, HW + 2.6, 7.4, 22.6, C.WoodDark)
	Props.lifebuoy(F.model, F:at(HW + 2, 5.2, 20.9), { seed = 15 })
	F.model.PrimaryPart = plinth
	return F.model, scales
end

--------------------------------------------------------------------------------
-- Centre: plaza, fountain with the golden fish, spawn
--------------------------------------------------------------------------------

local PLAZA_R = 50 -- radius of the round central plaza

-- Round plaza (rows of 8 studs, light) with a peach checker of 8-stud tiles in a ring.
local function buildPlaza(hub: any, G: number)
	local F = newFrame(U.model(hub, "Plaza"), CFrame.new(0, G, 0))
	for z0 = -56, 48, 8 do
		local zm = abs(z0 + 4)
		local w = floor(sqrt(math.max(0, PLAZA_R * PLAZA_R - zm * zm)) / 4 + 0.5) * 4
		if w > 0 then
			F:box("Paving", -w, -0.3, z0, w, 0.2, z0 + 8, H.tileA, FLAT)
		end
	end
	for gz = -6, 5 do
		for gx = -6, 5 do
			local cx, cz = gx * 8 + 4, gz * 8 + 4
			local r = sqrt(cx * cx + cz * cz)
			if (gx + gz) % 2 == 0 and r > 21 and r < PLAZA_R - 10 then
				F:box("Tile", cx - 4, 0.1, cz - 4, cx + 4, 0.26, cz + 4, H.tileB, FLAT)
			end
		end
	end
end

--[[
	«Золотая рыбка» fountain: an octagonal turquoise basin with a white rim and water, a tiered
	pedestal with a gold band, a plus-shaped upper bowl with water curtains falling into the
	basin (foam where they land), and a stepped water spout carrying a huge crowned golden fish
	(tilted nose-up, turned 45° so every avenue sees it in three-quarter view) that spits an
	arc of water.
]]
local function buildFountain(hub: any, G: number)
	local F = newFrame(U.model(hub, "Fountain"), CFrame.new(0, G + 0.25, 0))
	local white = C.White
	local r0, r1, half = 16, 18.6, 13 -- basin wall inner/outer face, half length of a straight wall
	F:box("BasinFloor", -r0 - 0.6, -0.3, -r0 - 0.6, r0 + 0.6, 0.5, r0 + 0.6, H.basinFloor, FLAT)
	F:box("Water", -r0 - 0.5, 0.5, -r0 - 0.5, r0 + 0.5, 2.4, r0 + 0.5, H.water, WATER)
	for i, d in { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } } do
		local function along(
			a0: number,
			a1: number,
			b0: number,
			b1: number,
			y0: number,
			y1: number,
			name: string,
			c: any
		)
			if d[1] ~= 0 then
				F:box(name, d[1] * b0, y0, a0, d[1] * b1, y1, a1, c)
			else
				F:box(name, a0, y0, d[2] * b0, a1, y1, d[2] * b1, c)
			end
		end
		along(-half, half, r0, r1, -0.3, 3.2, `BasinWall{i}`, H.basin)
		along(-half - 0.4, half + 0.4, r0 - 0.4, r1 + 0.4, 3.2, 3.9, `BasinRim{i}`, white)
	end
	for i, d in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		F:box(`BasinCorner{i}`, d[1] * half, -0.3, d[2] * half, d[1] * (r0 + 1.2), 3.2, d[2] * (r0 + 1.2), H.basin)
		F:box(
			`BasinCornerRim{i}`,
			d[1] * (half - 0.4),
			3.22,
			d[2] * (half - 0.4),
			d[1] * (r0 + 1.6),
			3.88,
			d[2] * (r0 + 1.6),
			white
		)
	end
	-- pedestal and the upper bowl with water curtains
	F:box("Pedestal1", -7, 0.4, -7, 7, 3.6, 7, white)
	F:box("Pedestal2", -4.6, 3.6, -4.6, 4.6, 13, 4.6, H.basin)
	F:box("PedestalBand", -4.9, 7.8, -4.9, 4.9, 9.0, 4.9, C.Gold, NOSHADOW)
	F:box("BowlA", -10.4, 13, -6.4, 10.4, 15, 6.4, white)
	F:box("BowlB", -6.4, 12.96, -10.4, 6.4, 15.04, 10.4, white)
	F:box("BowlWaterA", -9.8, 15, -5.8, 9.8, 15.6, 5.8, H.water, WATER)
	F:box("BowlWaterB", -5.8, 15.02, -9.8, 5.8, 15.62, 9.8, H.water, WATER)
	for i, d in { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } } do
		if d[1] ~= 0 then
			F:box(`Curtain{i}`, d[1] * 10.4, 2.4, -3, d[1] * 11.1, 14.8, 3, H.waterLight, STREAM)
			F:box(`CurtainFoam{i}`, d[1] * 9.6, 2.2, -3.6, d[1] * 12.2, 3.0, 3.6, C.White, DECOR)
		else
			F:box(`Curtain{i}`, -3, 2.4, d[2] * 10.4, 3, 14.8, d[2] * 11.1, H.waterLight, STREAM)
			F:box(`CurtainFoam{i}`, -3.6, 2.2, d[2] * 9.6, 3.6, 3.0, d[2] * 12.2, C.White, DECOR)
		end
	end
	-- the stepped spout that carries the golden fish
	for i, d in { { 1, 0.4 }, { -0.6, 1 }, { -1, -0.5 }, { 0.5, -1 } } do
		local x, z = d[1] * 2.4, d[2] * 2.4
		F:box(`Foam{i}`, x - 1.1, 15.4, z - 1.1, x + 1.1, 16.9 + (i % 2) * 0.5, z + 1.1, white, DECOR)
	end
	F:box("Spout1", -1.9, 15.6, -1.9, 1.9, 21.5, 1.9, H.waterLight, SPRAY)
	F:box("Spout2", -1.35, 21.5, -1.35, 1.35, 27.6, 1.35, H.waterLight, SPRAY)

	-- «Золотая рыбка»
	local s = 1.35
	local fishCf = CFrame.new(0, 34, 0) * CFrame.Angles(0, rad(45), 0)
	local fish = F:child("GoldenFish", fishCf * CFrame.Angles(0, 0, rad(-26)))
	bigFish(fish, s, {
		body = C.Gold,
		head = rgb(255, 214, 72),
		belly = C.GoldLight,
		fin = rgb(255, 150, 30),
		lips = rgb(255, 110, 70),
		spots = C.GoldLight,
	}, { crown = true, extra = { Reflectance = 0.12 } })
	-- a water jet out of its mouth: an arc of cubes in front of the head
	local jetFrame = F:sub(fishCf)
	local mouth = jetFrame.cf:PointToObjectSpace(fish.cf * V(-13.9 * s, -1.2 * s, 0))
	for k, p in { { -1.6, 1.8, 1.5 }, { -3.8, 3.3, 1.4 }, { -6.2, 3.6, 1.3 }, { -8.4, 2.5, 1.2 }, { -10.2, 0.6, 1.1 } } do
		local x, yy, w = mouth.X + p[1], mouth.Y + p[2], p[3]
		jetFrame:box(`MouthJet{k}`, x - w / 2, yy - w / 2, -w / 2, x + w / 2, yy + w / 2, w / 2, H.waterLight, SPRAY)
	end
end

-- HubSpawn: players without a free base appear here, facing the fountain (+Z).
local function buildSpawn(hub: any, G: number)
	local z = -38
	local F = newFrame(U.model(hub, "SpawnPad"), CFrame.new(0, G, z))
	F:box("SpawnFrame", -5.2, -0.2, -5.2, 5.2, 0.45, 5.2, C.Gold, FLAT)
	for i, d in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		F:box(
			`SpawnLight{i}`,
			d[1] * 5.2 - 0.6,
			0.4,
			d[2] * 5.2 - 0.6,
			d[1] * 5.2 + 0.6,
			1.0,
			d[2] * 5.2 + 0.6,
			C.Glow,
			NEON
		)
	end
	U.new("SpawnLocation", {
		Name = "HubSpawn",
		Size = V(8, 0.8, 8),
		CFrame = CFrame.new(0, G + 0.3, z) * CFrame.Angles(0, math.pi, 0), -- the part's −Z faces +Z
		Anchored = true,
		Neutral = true,
		Duration = 0, -- no ForceField
		Enabled = true,
		AllowTeamChangeOnTouch = false,
		Color = C.Cyan,
		Material = Mat.SmoothPlastic,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		CastShadow = false,
		CanTouch = true,
	}, hub)
	U.partCount += 1
	for i, sx in { -1, 1 } do
		local variant = if i == 1 then "flowers" else "topiary"
		Props.planter(F.model, F:at(sx * 8.5, 0.2, 0), { variant = variant, color = C.White, seed = 36 + i })
	end
end

-- Benches facing the fountain on the diagonals, each with a lamp behind it.
local function buildPlazaFurniture(hub: any, G: number)
	local m = U.model(hub, "PlazaFurniture")
	for k = 0, 3 do
		local a = 45 + k * 90
		Props.bench(m, U.polarCFrame(a, 28.5, G + 0.2), { length = 8, color = C.WoodLight, seed = 40 + k })
		Props.lampPost(
			m,
			U.polarCFrame(a, 33, G + 0.2),
			{ height = 10, color = C.Festive[k * 2 + 1], light = true, seed = 50 + k }
		)
	end
end

--------------------------------------------------------------------------------
-- Avenues (θ = 0/90/180/270): paving, lamps with bunting, gates, palms
--------------------------------------------------------------------------------

local AVENUE_START = PLAZA_R - 4
local AVENUE_END = 119
local GATE_Z = 104

-- per avenue: accent colour (lamp trims, gate bands)
local AVENUE_ACCENT = { C.Red, C.Blue, C.Purple, C.Orange }
-- warm flower colours for the hedge tops (blue/white blooms read as plain slabs on a hedge)
local BLOOMS = { C.Pink, C.Yellow, C.Red, C.Orange, rgb(255, 150, 200) }

-- Welcome gate over an avenue at radial distance z: striped pillars with gold balls, a beam
-- and a big sign: «ОСТРОВ РЫБАКОВ» for visitors coming off the bridge, «ХОРОШЕГО КЛЁВА!» for
-- players heading back to their bases; tall enough to show above the bridge arch. 21 parts.
local function welcomeGate(F: any, z: number, accent: any)
	local m = F:child("WelcomeGate")
	for i, sx in { -1, 1 } do
		m:box(`GateBase{i}`, sx * 14.4, -0.3, z - 2.6, sx * 20.4, 1.8, z + 2.6, C.StoneLight)
		m:box(`GatePillar{i}`, sx * 15.4, 1.8, z - 2, sx * 19.4, 30, z + 2, C.White)
		for k, y0 in { 6, 13, 20 } do
			m:box(`GateBand{i}_{k}`, sx * 15.2, y0, z - 2.2, sx * 19.6, y0 + 2, z + 2.2, accent, NOSHADOW)
		end
		m:box(`GateCap{i}`, sx * 14.8, 30, z - 2.6, sx * 20, 31.6, z + 2.6, accent)
		m:box(`GateBall{i}`, sx * 16.4, 31.6, z - 1, sx * 18.4, 33.6, z + 1, C.Gold, NOSHADOW)
	end
	m:box("GateBeam", -15.4, 22, z - 1.2, 15.4, 23.6, z + 1.2, accent)
	-- the board's front (−Z) faces the fountain, its back the bridge
	signBoard(
		m,
		"GateSign",
		-13.4,
		13.4,
		24.4,
		31.8,
		z,
		C.Blue,
		C.Yellow,
		"ХОРОШЕГО КЛЁВА!",
		"ОСТРОВ РЫБАКОВ"
	)
end

local function buildAvenues(hub: any, cfg: any, G: number)
	local root = U.model(hub, "Avenues")
	for i, angle in cfg.BridgeAngles do
		local F = radialFrame(U.model(root, `Avenue{i}`), angle, G)
		local accent = AVENUE_ACCENT[(i - 1) % #AVENUE_ACCENT + 1]
		-- paving: coral bricks, light cross bands, white kerbs
		F:box("Bricks", -11, -0.3, AVENUE_START, 11, 0.27, AVENUE_END, H.brick, FLAT)
		for z = AVENUE_START + 14, AVENUE_END - 6, 24 do
			F:box("Band", -10.9, 0.1, z, 10.9, 0.34, z + 2, H.brickLight, FLAT)
		end
		for j, sx in { -1, 1 } do
			F:box(`Kerb{j}`, sx * 11, -0.3, AVENUE_START + 4, sx * 12.4, 0.6, AVENUE_END, C.White, FLAT)
		end
		-- two pairs of lamps with bunting across the avenue
		for k, z in { 64, 88 } do
			local tops = {}
			for j, sx in { -1, 1 } do
				Props.lampPost(
					F.model,
					F:at(sx * 14.2, 0, z),
					{ height = 11, color = accent, seed = i * 10 + k * 2 + j }
				)
				tops[j] = F:point(sx * 14.2, 10.2, z)
			end
			Props.bunting(F.model, tops[1], tops[2], { seed = i * 7 + k, sag = 1.8, count = 4 })
		end
		-- flowering hedge rows outside the kerbs, between the lamps
		for j, sx in { -1, 1 } do
			for k, zz in { { 54, 61 }, { 67, 85 } } do
				local bloom = BLOOMS[(i * 2 + j + k) % #BLOOMS + 1]
				F:box(`Hedge{j}_{k}`, sx * 15, -0.3, zz[1], sx * 17.6, 2.4, zz[2], C.Leaf1)
				F:box(`HedgeTop{j}_{k}`, sx * 15.4, 2.4, zz[1] + 0.4, sx * 17.2, 3.0, zz[2] - 0.4, bloom, DECOR)
			end
		end
		welcomeGate(F, GATE_Z, accent)
		-- tall palms framing the avenue end
		for j, sx in { -1, 1 } do
			Props.palmTree(F.model, F:at(sx * 21, 0, 114, 30 * j), { seed = i * 31 + j, scale = 1.6, lite = true })
		end
	end
end

--------------------------------------------------------------------------------
-- Fun fair (θ 225): Ferris wheel, food kiosks, a picnic table
--------------------------------------------------------------------------------

--[[
	Food kiosk facing local −Z: a counter, side walls, two posts, a stepped striped roof, a sign
	board and a giant treat on the roof ("icecream" | "popcorn" | "lemonade"). ~19 parts.
]]
local function kiosk(parent: any, cf: any, name: string, text: string, main: any, product: string)
	local F = newFrame(U.model(parent, name), cf)
	local light = lerpColor(main, C.White, 0.55)
	local base = F:box("Base", -6.2, -0.3, -4.4, 6.2, 0.5, 4.2, C.StoneLight, FLAT)
	F:box("Counter", -5.6, 0.5, -3.8, 5.6, 3.8, -1.8, main)
	F:box("CounterTop", -6, 3.8, -4.3, 6, 4.3, -1.4, C.White)
	F:box("Back", -5.6, 0.5, 2.4, 5.6, 9.2, 3.6, light)
	F:box("SideL", -5.6, 0.5, -1.8, -4.6, 3.8, 2.4, main)
	F:box("SideR", 4.6, 0.5, -1.8, 5.6, 3.8, 2.4, main)
	F:box("PostL", -5.6, 4.3, -3.8, -4.6, 9.2, -2.8, C.White)
	F:box("PostR", 4.6, 4.3, -3.8, 5.6, 9.2, -2.8, C.White)
	F:box("Roof1", -7.2, 9.2, -5.4, 7.2, 10.4, 4.8, main)
	F:box("Roof2", -5.8, 10.4, -4.0, 5.8, 11.6, 3.4, C.White)
	F:box("Roof3", -4.2, 11.6, -2.6, 4.2, 12.6, 1.8, main)
	local sign = F:box("Sign", -5.6, 10.6, -6.0, 5.6, 13.6, -5.2, C.White)
	F:box("SignRim", -5.9, 13.6, -5.9, 5.9, 14.1, -5.3, main, NEON)
	signText(sign, Enum.NormalId.Front, text, main, C.White)
	local y = 12.6
	if product == "icecream" then
		F:box("Cone1", -0.8, y, -0.8, 0.8, y + 1.2, 0.8, H.waffle)
		F:box("Cone2", -1.4, y + 1.2, -1.4, 1.4, y + 2.4, 1.4, H.waffle)
		F:box("Cone3", -2.0, y + 2.4, -2.0, 2.0, y + 3.6, 2.0, shade(H.waffle, 1.08))
		F:box("Scoop1", -2.5, y + 3.6, -2.5, 2.5, y + 5.6, 2.5, C.Pink)
		F:box("Drip", -1.2, y + 3.0, -2.7, -0.2, y + 3.8, -2.4, C.Pink, DECOR)
		F:box("Scoop2", -2.1, y + 5.6, -2.1, 2.1, y + 7.4, 2.1, C.Cream)
		F:box("Scoop3", -1.6, y + 7.4, -1.6, 1.6, y + 8.8, 1.6, rgb(140, 236, 170))
		F:box("Cherry", -0.6, y + 8.8, -0.6, 0.6, y + 10.0, 0.6, C.Red, DECOR)
	elseif product == "popcorn" then
		F:box("Bucket", -2.2, y, -2.2, 2.2, y + 4.8, 2.2, C.Red)
		for k = -1, 1, 2 do
			F:box(`BucketStripe{k}`, k * 1.1 - 0.4, y + 0.1, -2.3, k * 1.1 + 0.4, y + 4.9, 2.3, C.White, NOSHADOW)
		end
		for k, p in
			{ { -1.2, 5.4, -0.8 }, { 0.9, 5.6, 0.6 }, { -0.2, 6.5, 0.1 }, { 1.2, 5.3, -1.2 }, { -1.0, 5.5, 1.2 } }
		do
			local w = if k % 2 == 0 then 1.4 else 1.7
			local col = if k % 3 == 0 then C.Yellow else C.Cream
			F:box(
				`Popcorn{k}`,
				p[1] - w / 2,
				y + p[2] - w / 2,
				p[3] - w / 2,
				p[1] + w / 2,
				y + p[2] + w / 2,
				p[3] + w / 2,
				col,
				DECOR
			)
		end
	else -- lemonade
		F:box("Cup", -2.0, y, -2.0, 2.0, y + 5.2, 2.0, C.Yellow)
		F:box("CupBand", -2.1, y + 1.6, -2.1, 2.1, y + 2.6, 2.1, C.White, NOSHADOW)
		F:box("Lid", -2.3, y + 5.2, -2.3, 2.3, y + 5.9, 2.3, C.White)
		F:box("Straw", 0.5, y + 5.9, -0.2, 0.9, y + 9.2, 0.2, C.Pink, DECOR)
		F:box("StrawTip", -0.6, y + 8.8, -0.25, 0.5, y + 9.25, 0.25, C.Pink, DECOR)
		F:box("Lemon", 1.7, y + 4.2, -0.9, 2.5, y + 6.4, 0.9, C.Lime, DECOR)
	end
	F.model.PrimaryPart = base
end

local function buildFair(hub: any, G: number)
	local m = U.model(hub, "FunFair")
	local F = radialFrame(m, 225, G)
	F:box("Path", -6, -0.3, PLAZA_R - 3, 6, 0.22, 87, H.tileA, FLAT)
	for j, sx in { -1, 1 } do
		F:box(`PathEdge{j}`, sx * 6, -0.3, PLAZA_R - 1, sx * 7.4, 0.32, 87, H.brick, FLAT)
	end
	Props.ferrisWheel(m, U.polarCFrame(225, 98, G), { scale = 1.3, deck = C.Pink, seed = 1 })
	kiosk(m, F:at(-15.5, 0, 59, -90), "IceCreamKiosk", "МОРОЖЕНОЕ", C.Pink, "icecream")
	kiosk(m, F:at(15.5, 0, 59, 90), "PopcornKiosk", "ПОПКОРН", C.Red, "popcorn")
	kiosk(m, F:at(15.5, 0, 77, 90), "LemonadeKiosk", "ЛИМОНАД", rgb(255, 176, 30), "lemonade")
	Props.picnicTable(m, F:at(-15.5, 0, 76, 90), { seed = 61, cloth = C.Red })
	Props.parasol(m, F:at(-15.7, 0, 76.1), { seed = 63, color = C.Cyan })
end

--------------------------------------------------------------------------------
-- Lawns: cottages on the outer ring, a garden, a boat yard and a fish yard behind the shops
--------------------------------------------------------------------------------

--[[
	Cottage facing local −Z: a pastel block house on a stone base, a three-step roof with a white
	ridge cap, a door with a little canopy, two front windows and one at the back, a chimney.
	12 parts.
]]
local function cottage(parent: any, cf: any, wall: any, roof: any)
	local F = newFrame(U.model(parent, "Cottage"), cf)
	local base = F:box("Base", -8, -0.3, -7, 8, 0.6, 7, C.StoneLight, FLAT)
	F:box("Walls", -7, 0.6, -6, 7, 9.6, 6, wall)
	F:box("Roof1", -8, 9.6, -7, 8, 11.2, 7, roof)
	F:box("Roof2", -8, 11.2, -4.8, 8, 12.8, 4.8, lerpColor(roof, C.White, 0.25))
	F:box("Roof3", -8, 12.8, -2.6, 8, 14.4, 2.6, roof)
	F:box("RoofCap", -8.4, 14.4, -1, 8.4, 15.2, 1, C.White)
	F:box("Chimney", 3.6, 11, 1.4, 5.8, 17.6, 3.6, C.White)
	F:box("Door", -1.5, 0.6, -6.3, 1.5, 5.8, -5.9, roof)
	F:box("DoorCanopy", -2.4, 5.9, -7.6, 2.4, 6.5, -5.9, C.White, NOSHADOW)
	F:box("WindowL", -5.6, 3.6, -6.25, -2.8, 6.8, -5.9, C.WindowBlue, NOSHADOW)
	F:box("WindowR", 2.8, 3.6, -6.25, 5.6, 6.8, -5.9, C.WindowBlue, NOSHADOW)
	F:box("WindowBack", -2, 3.6, 5.9, 2, 6.8, 6.25, C.WindowBlue, NOSHADOW)
	F.model.PrimaryPart = base
end

local COTTAGES = { -- angle, wall, roof
	{ 18, rgb(255, 196, 214), C.Red },
	{ 72, rgb(196, 236, 255), C.Blue },
	{ 108, rgb(214, 246, 196), C.Orange },
	{ 162, rgb(255, 236, 170), C.Purple },
	{ 198, rgb(220, 204, 255), C.Red },
	{ 252, rgb(196, 244, 236), C.Pink },
	{ 288, rgb(255, 214, 180), C.Blue },
	{ 342, rgb(255, 250, 236), C.Cyan },
}

-- The plaza is 2 studs above the beach: a 1-stud sand-coloured step where the radial line at
-- `angle` crosses the plaza edge (found on the real heightfield), so players walk back up.
local function beachStep(parent: any, world: any, angle: number, G: number)
	for r = 112, 136, 0.5 do
		local p = U.polar(angle, r, 0)
		if world:heightAt(p.X, p.Z) < G then
			U.part(parent, "BeachStep", V(7, 1.6, 7), CFrame.new(p.X, G - 1.8, p.Z), C.SandDark, nil, FLAT)
			return
		end
	end
end

local function buildLawns(hub: any, G: number, world: any)
	local m = U.model(hub, "Lawns")
	local flowers = C.Flowers
	-- cottages on the outer ring, their doors towards the beach, each with a step down to it
	for _, c in COTTAGES do
		cottage(m, U.polarCFrame(c[1], 106, G) * CFrame.Angles(0, math.pi, 0), c[2], c[3])
		beachStep(m, world, c[1], G)
	end
	-- garden behind the Shop (θ 45)
	local g = polarFrame(m, 45, 0, G)
	Props.cherryTree(m, g:at(-17, 0, 104), { seed = 71, scale = 1.4 })
	Props.roundTree(m, g:at(16, 0, 107), { seed = 72, scale = 1.4 })
	flowerBed(g, 0, 100, 14, 4, { flowers[1], flowers[2] })
	flowerBed(g, -1, 112, 4, 9, { flowers[3], flowers[5] })
	-- boat yard behind the Workshop (θ 135): a boat on trestles, planks, a barrel, a tree
	local y = polarFrame(m, 135, 0, G)
	for i, z in { 102, 108 } do
		y:box(`Trestle{i}`, -3.4, -0.3, z - 0.6, 3.4, 2.4, z + 0.6, C.Wood)
	end
	Props.rowboat(m, y:at(0, 3.2, 105), { color = C.Red, seed = 74, oars = false })
	y:box("Planks1", 8, -0.3, 108, 14, 0.9, 116, C.WoodLight)
	y:box("Planks2", 8.6, 0.9, 109, 13.4, 1.8, 115, C.Wood)
	Props.barrel(m, y:at(-11, 0, 112), { seed = 75 })
	Props.roundTree(m, y:at(-17, 0, 101), { seed = 77, scale = 1.4 })
	-- fish yard behind the market (θ 315): a drying rack with fish and a crate
	local f = polarFrame(m, 315, 0, G)
	for i, x in { -6, 6 } do
		f:box(`RackPost{i}`, x - 0.4, -0.3, 101.6, x + 0.4, 6.4, 102.4, C.WoodDark)
	end
	f:box("RackBar", -6.4, 6.0, 101.7, 6.4, 6.6, 102.3, C.Wood, NOSHADOW)
	for k = 1, 4 do
		local x = -6 + k * 2.4
		f:box(`HangFish{k}`, x - 0.5, 3.4, 101.6, x + 0.5, 6.0, 102.4, flowers[k], DECOR)
	end
	Props.crate(m, f:at(12, 0, 99), { seed = 79, size = 3.4, color = C.Cyan })
	-- two big oaks between the shops and the cottages
	for _, a in { 166, 346 } do
		Props.oakTree(m, polarFrame(m, a, 0, G):at(0, 0, 86), { seed = floor(a), scale = 1.5 })
	end
end

--------------------------------------------------------------------------------
-- Beach ring: palms, parasols with deck chairs, a sand castle, a volleyball net
--------------------------------------------------------------------------------

local PALM_ANGLES = { 22.5, 37.5, 52.5, 67.5, 112.5, 127.5, 150, 202.5, 217.5, 240 }

local function beachSet(parent: any, cf: any, seed: number, color: any)
	local F = newFrame(U.model(parent, "BeachSet"), cf)
	Props.parasol(F.model, F:at(0, 0, 1), { seed = seed, color = color })
	Props.beachChair(F.model, F:at(-2.6, 0, -1, 0), { seed = seed + 1, color = color })
	Props.beachChair(F.model, F:at(2.6, 0, -1, 0), { seed = seed + 2 })
	F:box("Towel", 4.6, -0.05, -3.6, 7.8, 0.12, 1.8, lerpColor(color, C.White, 0.3), DECOR)
	F:box("TowelStripe", 4.55, -0.05, -1.4, 7.85, 0.18, -0.4, C.White, DECOR)
end

local function buildBeach(hub: any, world: any)
	local m = U.model(hub, "Beach")
	local function ground(a: number, r: number, yaw: number?): any
		local p = U.polar(a, r, 0)
		return CFrame.new(p.X, world:heightAt(p.X, p.Z), p.Z) * CFrame.Angles(0, rad(a + (yaw or 0)), 0)
	end
	-- big palms in two staggered rows
	for k, a in PALM_ANGLES do
		local r = if k % 2 == 0 then 133 else 141
		Props.palmTree(m, ground(a, r, k * 47), { seed = 100 + k, scale = 1.45 + (k % 3) * 0.2, lite = true })
	end
	-- parasols and deck chairs facing the lagoon
	for i, a in { 30, 225 } do
		beachSet(m, ground(a, 137, 180), 120 + i * 3, C.Festive[(i * 3) % #C.Festive + 1])
	end
	-- sand castle with a flag, a bucket and a spade
	local sc = newFrame(U.model(m, "SandCastle"), ground(12, 136))
	sc:box("Keep1", -3, -0.2, -3, 3, 1.8, 3, C.SandDark)
	sc:box("Keep2", -2, 1.8, -2, 2, 3.6, 2, C.Sand)
	sc:box("Keep3", -1, 3.6, -1, 1, 5.0, 1, C.SandDark)
	for i, d in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		sc:box(`Tower{i}`, d[1] * 3 - 0.8, -0.2, d[2] * 3 - 0.8, d[1] * 3 + 0.8, 2.8, d[2] * 3 + 0.8, C.Sand)
	end
	sc:box("FlagPole", -0.1, 5.0, -0.1, 0.1, 7.2, 0.1, C.WoodDark, DECOR)
	sc:box("Flag", 0.1, 6.2, -0.05, 1.5, 7.1, 0.05, C.Red, DECOR)
	sc:box("Bucket", 4.4, -0.1, 0.6, 5.8, 1.4, 2.0, C.Blue, NOSHADOW)
	sc:box("Spade", 4.2, -0.05, -2.4, 4.6, 0.25, -0.2, C.Yellow, DECOR)
	-- volleyball net
	local v = newFrame(U.model(m, "Volleyball"), ground(165, 137))
	for i, sx in { -1, 1 } do
		v:column(`NetPost{i}`, 0.6, sx * 9, 0, -0.6, 8, C.White)
	end
	v:box("Net", -9, 5, -0.08, 9, 7.6, 0.08, C.White, merge(DECOR, { Transparency = 0.35 }))
	v:box("NetTape", -9, 7.6, -0.12, 9, 8, 0.12, C.Red, DECOR)
	v:box("Ball", 3, 0, -4, 4.4, 1.4, -2.6, C.Yellow, DECOR)
end

--------------------------------------------------------------------------------
-- Harbour (θ ≈ 300..330): pier with boats, beach clutter, lighthouse on a rock islet
--------------------------------------------------------------------------------

local function buildHarbour(hub: any, cfg: any, world: any)
	local m = U.model(hub, "Harbour")
	local water = cfg.WaterTop or 0
	local deck = water + 2.9
	local pierA = 322
	-- pier: 4 chained segments and a T-head
	for k = 0, 3 do
		Props.dockSegment(m, U.polarCFrame(pierA, 132 + k * 12, deck), {
			length = 12,
			width = 8,
			depth = 12,
			piles = if k == 3 then "both" else "front",
			seed = 200 + k,
		})
	end
	Props.dockSegment(m, U.polarCFrame(pierA, 178, deck) * CFrame.Angles(0, rad(90), 0), {
		length = 24,
		width = 8,
		depth = 14,
		seed = 205,
	})
	local P = radialFrame(m, pierA, 0)
	-- boats along the pier
	Props.motorboat(m, P:at(9, water, 152, 180), { color = C.White, stripe = C.Red, seed = 210 })
	Props.rowboat(m, P:at(-8.5, water, 168), { color = C.Yellow, seed = 211 })
	Props.rowboat(m, P:at(-8, water, 156, 8), { color = C.Cyan, seed = 212 })
	Props.sailboat(m, P:at(19, water, 175, 190), { color = C.Blue, seed = 213 })
	-- mooring posts with lifebuoys, crates and a barrel on the pier
	for i, z in { 136, 169 } do
		P:box(`BuoyPost{i}`, 4.6, water - 6, z - 0.6, 5.8, deck + 4.4, z + 0.6, C.WoodDark)
		Props.lifebuoy(m, P:at(5.2, deck + 3, z - 0.75, 0), { seed = 214 + i })
	end
	Props.crate(m, P:at(-2.4, deck, 170), { size = 2.6, color = C.Red, seed = 216 })
	Props.barrel(m, P:at(2.6, deck, 180), { seed = 218 })
	-- an anchor and a barrel on the beach by the pier
	local function ground(a: number, r: number, yaw: number?): any
		local p = U.polar(a, r, 0)
		return CFrame.new(p.X, world:heightAt(p.X, p.Z), p.Z) * CFrame.Angles(0, rad(a + (yaw or 0)), 0)
	end
	Props.anchor(m, ground(331, 134, 70), { seed = 220, scale = 1.3 })
	Props.barrel(m, ground(312, 136), { seed = 223, color = C.Red })

	-- lighthouse on a stepped rock islet, joined to the beach by a stone breakwater
	local I = polarFrame(U.model(m, "LighthouseIslet"), 300, 168, 0)
	I:box("Rock1", -16, -7, -14, 15, 0.8, 16, C.Stone)
	I:box("Rock2", -12.5, 0.8, -12, 12, 2.8, 12.5, C.StoneLight)
	I:box("Rock3", -17.5, -6, -6, -15, 0.2, 5, C.StoneDark)
	I:box("Rock4", 11, -6, 13, 16, 0.4, 18, C.StoneDark)
	for k = 0, 1 do
		I:box(
			`Breakwater{k + 1}`,
			-4.5 + k * 0.4,
			-5,
			-26 + k * 8,
			4.5 - k * 0.4,
			2.6 - k * 0.1,
			-18 + k * 8,
			if k == 0 then C.StoneLight else C.Stone
		)
	end
	Props.boulder(I.model, I:at(-15, 0.8, 13), { seed = 230 })
	Props.boulder(I.model, I:at(14, 0.8, -12), { seed = 231 })
	Props.lighthouse(I.model, I:at(0, 3.2, 1), { scale = 1.9, seed = 232 })
end

--------------------------------------------------------------------------------

return function(parent: any, cfg: any, world: any)
	local startCount = U.partCount
	local G = cfg.GroundTop or 4
	local hub = U.model(parent, "Hub")

	buildPlaza(hub, G)
	buildFountain(hub, G)
	buildSpawn(hub, G)
	buildPlazaFurniture(hub, G)

	local shopR = PLAZA_R + 8 -- porch front on the plaza rim
	buildShop(hub, U.polarCFrame(45, shopR, G))
	buildFishMarket(hub, U.polarCFrame(315, shopR, G))
	buildWorkshop(hub, U.polarCFrame(135, shopR, G))

	buildAvenues(hub, cfg, G)
	buildFair(hub, G)
	buildLawns(hub, G, world)
	buildBeach(hub, world)
	buildHarbour(hub, cfg, world)

	-- budgets (DESIGN.md §3): fail the build rather than ship a heavier hub
	local partCount = U.partCount - startCount
	local lights = 0
	for _, d in hub:GetDescendants() do
		if d.ClassName == "PointLight" then
			lights += 1
		end
	end
	if partCount > MAX_PARTS then
		local lines = {}
		for _, child in hub:GetChildren() do
			local n = if child:IsA("BasePart") then 1 else 0
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					n += 1
				end
			end
			table.insert(lines, `{child.Name}={n}`)
		end
		error(`Hub has {partCount} parts (budget {MAX_PARTS}): {table.concat(lines, ", ")}`)
	end
	assert(lights <= MAX_LIGHTS, `Hub has {lights} PointLights (budget {MAX_LIGHTS})`)

	return {
		model = hub,
		partCount = partCount,
		lights = lights,
		expectedAttachments = {
			{
				root = "workspace",
				path = { "Map", "Hub", "Shop", "Counter", "ShopPromptAttachment" },
				offset = V(0, 1.3, -2.3),
			},
			{
				root = "workspace",
				path = { "Map", "Hub", "FishMarket", "Scales", "SellPromptAttachment" },
				offset = V(0, -0.8, -2.3),
			},
			{
				root = "workspace",
				path = { "Map", "Hub", "Workshop", "Workbench", "UpgradePromptAttachment" },
				offset = V(0, 1.5, -2.3),
			},
		},
	}
end
