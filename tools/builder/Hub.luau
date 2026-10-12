--[[
	Hub — «Остров Рыбаков», the harbour village on the central island (Workspace.Map.Hub).
	Style contract: tools/builder/DESIGN.md §1 (art direction v4: a rich, sunny voxel village in a
	calm, natural palette — every colour comes from tools/builder/Palette.luau via Props.Colors);
	place in the world: §2 and §6.

	Usage (Map.luau):  local hub = buildHub(map, cfg, world)
	  map    Workspace.Map
	  cfg    MapConfig (GroundTop, HubPlazaRadius, HubRadius, BridgeAngles, WaterTop)
	  world  VoxelWorld (heightAt: beach props stand on the real sand)
	Returns { model = Model "Hub", partCount = number, expectedAttachments = {...} }.

	Ground (VoxelWorld): flat grass at GroundTop (4) for r < HubPlazaRadius (158), sand (y = 2) to
	HubRadius (185), lagoon water (y = 0) beyond. Angle θ → (r·sin θ, y, r·cos θ). The bridges of
	Promenade.luau start at θ = 0/90/180/270, r ≈ 152: their avenues stay open from the bridge to
	the tower.

	The look: a well-kept harbour town square. Large surfaces are calm materials (warm stone
	paving, cobbled streets, plaster, timber, brick, stone, tiled roofs); strong colour only on
	small accents (awnings, shutters, flowers, flags, signs, boats). Every building is real voxel
	architecture: a stone base course, timber posts and rails, framed windows with sills (most with
	shutters, some with flower boxes), doors with steps and little pent roofs, wedge roofs with
	overhangs, eave boards, a ridge beam and plastered gables on tie beams, chimneys, signs and
	lanterns. One building = one wall + one roof + one trim colour (+ wood / stone). No people and
	no animals on display.

	Layout (r = distance from the island centre). The bases look at the island along
	θ = 22.5 + k·45; those lanes stay open (nothing tall stands on them), so every base sees the
	whole tower:
	  centre       «Золотая рыбка» fountain tower (~106 studs, the landmark every base, pier and
	               bridge sees): a sandstone basin with a blue tile band round a see-through pool,
	               three stepped sandstone tiers with water streaming down their faces, a spire
	               with slit windows, a glowing gold ring and a verdigris cap, and on top a huge
	               crowned golden fish riding a water spout and slowly circling (Spin attribute,
	               turned by the client's AmbientController); sparkles, spray and splashes as
	               particles. A round plaza (r 66) of warm stone with an inlaid sandstone star in
	               a dark outline, sandstone rays to the shop porches and the fun fair and a
	               terracotta ring; benches and lamps 22.5° off the avenues and the shop diagonals
	               (clear walkways to every bridge and counter), planters on the plaza rim
	  avenues      θ = 0/90/180/270, 25 wide: cobbles between stone kerbs from the plaza to the
	               bridge (r 62..153), a sandstone runner from the plaza star to the bridge, two
	               lamp pairs with bunting, hedges with flower clumps, a stone welcome gate
	               «ОСТРОВ РЫБАКОВ» (inner side «ХОРОШЕГО КЛЁВА!») at r 140 with a band and a topper
	               in the district colour of its bridge and gateway, tall palms on the sand beside
	               the bridge landing; HubSpawn on the θ 180 avenue at r 100, facing the tower
	  shops        built 1.2× (modelled at 1/1.2), facing the tower from r 76 (porches on the
	               plaza rim, customers stand on the porch, the counter closes the open shop front):
	    θ 45       Shop «УДОЧКИ» — a two-storey half-timbered house (plaster, dark timber, red
	               roof, green shutters, flower boxes), a striped awning over the counter, a rod
	               wall inside, and a giant rod on a bracket at the eave with a fish twirling on
	               its line in front of the roof
	    θ 315      FishMarket «РЫБНЫЙ РЫНОК» — an open timber market hall on stone pedestals under a
	               blue roof with a louvred lantern and a fish weather vane, a blue/cream awning,
	               ice counters with fish, the scales on the front counter, crates and barrels
	    θ 135      Workshop «МАСТЕРСКАЯ» — a brick workshop with stone quoins and a slate roof, its
	               gable to the plaza carrying a big turning gear, a rolled-up garage door over the
	               workbench, a forge inside, a chimney with smoke, a side door, an anvil outside
	  θ 225        fun fair: an entrance arch «АТТРАКЦИОНЫ» on the plaza rim, a path lined by three
	               wooden food stalls with treats on their roofs and a picnic table, and a Ferris
	               wheel in white and teal (its spinning parts never collide)
	  gardens      a flower garden on every base lane (r 97..125): rows of one- or two-colour
	               bloom clumps pointing at the tower
	  second ring  r ≈ 125..150: «ИГРЫ» game booth behind the Shop and the «СЦЕНА» bandstand
	               behind the Workshop, both facing the lagoon and the bases; 8 gable-front
	               cottages in pairs flanking the lanes (doors towards the beach), a garden (θ 32),
	               a boat yard (θ 124), a fish-drying rack behind the market, a koi pond (θ 302),
	               oaks
	  terrace      a ring of 1-stud sand steps between the plaza and the beach (walk down anywhere)
	  beach ring   big palms, bathing huts on little decks, parasols with deck chairs
	  harbour      a plank boardwalk with lamps along the shore (θ 285..345) with a step down to the
	               sand all along it, a pier from it to deep water with a T-head at θ 322, bobbing
	               boats moored on open water (Bob attribute), lifebuoys, an anchor, and a
	               lighthouse on a rock islet with a breakwater at θ 305, clear of every base's pier
	               corridor (checked: the build fails otherwise)

	Every building is modelled in a local frame (origin = front centre at ground level, local −Z
	towards the tower), so the customer side of every counter is local −Z; prompts sit about
	3.5 studs above the porch, just in front of the counter.
	Budget: ≤ 2200 parts and ≤ 12 PointLights (DESIGN.md §3; the build fails above either).
]]

local U = require("./Util")
local Props = require("./Props")
local Promenade = require("./Promenade") -- district colours of the bridges and gateways

local Enum = U.Enum
local CFrame = U.CFrame
local V = U.Vector3.new
local Mat = Enum.Material

local C = Props.Colors -- the Palette (tools/builder/Palette.luau) plus a few legacy aliases
local shade = Props.shade
local lerpColor = Props.lerpColor

local rad, sqrt, floor, abs = math.rad, math.sqrt, math.floor, math.abs

local MAX_PARTS = 2200
local MAX_LIGHTS = 12

-- Layout radii (studs from the island centre); the ones tied to the ground's shore radii are set
-- from cfg in buildHub (HubPlazaRadius 158, HubRadius 185).
local PLAZA_R = 66 -- round paved plaza
local SHOP_R = 76 -- shop fronts: the porches reach the plaza rim
local SHOP_SCALE = 1.2 -- the three shops are modelled at 1/1.2 and built 1.2× bigger
local RING_R = 134 -- second ring: the game booth and the bandstand behind the shops
local COTTAGE_R = 140
local L = {
	avenueEnd = 153, -- the bridge decks start at HubPlazaRadius − 6
	gate = 140,
	terraceIn = 150, -- sand steps round the grass edge (grass columns reach r ≈ 152..164)
	terraceOut = 166,
	beach = 175, -- middle of the open sand between the steps and the waterline
	shore = 185,
}

--------------------------------------------------------------------------------
-- Hub tones, all derived from Palette tokens (DESIGN.md §1)
--------------------------------------------------------------------------------

local H = {
	pave = lerpColor(C.Cobble, C.Sand, 0.4), -- plaza: warm light stone
	paveDark = C.CobbleDark, -- outlines and edges
	walk = C.SandDark, -- the walk: the plaza star, its rays, the avenue runners, paths
	street = lerpColor(C.Cobble, C.Sand, 0.15), -- avenue cobbles
	kerb = C.StoneLight,
	ring = C.Brick, -- the terracotta ring round the fountain
	water = C.Water,
	waterLight = C.WaterLight,
	cascade = lerpColor(C.WaterLight, C.Foam, 0.35), -- water streaming down the tower's tiers
	basinFloor = lerpColor(C.Water, C.Navy, 0.4),
	ice = lerpColor(C.Foam, C.WaterLight, 0.3),
	tile = C.RoofBlue, -- blue tile bands on the stone fountain
	stoneWarm = lerpColor(C.StoneLight, C.SandDark, 0.35), -- the fountain's warm sandstone
	verdigris = lerpColor(C.RoofGreen, C.Cyan, 0.4), -- the spire's copper cap
	-- the golden fish: an old, warm gold (not candy), a lighter head and belly
	gold = lerpColor(C.Gold, C.Cream, 0.25),
	goldLight = C.GoldLight,
	goldBelly = lerpColor(C.GoldLight, C.Cream, 0.5),
	goldFin = lerpColor(C.Orange, C.Cream, 0.25),
	fair = C.Cyan, -- the fun fair's one accent (teal), with white and wood
	curtain = lerpColor(C.Red, C.WoodDark, 0.35),
	speaker = lerpColor(C.Navy, C.Dark, 0.5),
	-- fish on the market's ice (silver, salmon, orange, teal, gold, blue)
	fish = {
		C.StoneLight,
		lerpColor(C.Pink, C.Orange, 0.35),
		C.Orange,
		C.Cyan,
		lerpColor(C.Gold, C.Cream, 0.3),
		lerpColor(C.RoofBlue, C.WaterLight, 0.3),
	},
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
-- the basin pool is the only see-through water (nothing transparent overlaps it); falling water,
-- spouts and bowls are opaque: the colour reads as water and nothing sort-flickers
local WATER = { Transparency = 0.35, CanCollide = false, CastShadow = false, CanQuery = false }
local FLOW = DECOR

--------------------------------------------------------------------------------
-- Frame kit: every structure is built in a local frame with axis-aligned blocks
--------------------------------------------------------------------------------

local Frame = {}
Frame.__index = Frame

-- s scales the local units (positions and sizes): the shops are modelled at 1/SHOP_SCALE.
local function newFrame(model: any, cf: any, s: number?): any
	return setmetatable({ model = model, cf = cf, s = s or 1 }, Frame)
end

-- Local (unscaled) CFrame → CFrame relative to this frame, with the scale applied.
function Frame:scaled(lcf: any): any
	if self.s == 1 then
		return lcf
	end
	return CFrame.new(lcf.Position * self.s) * lcf.Rotation
end

-- Local (unscaled) CFrame → world CFrame.
function Frame:world(lcf: any): any
	return self.cf * self:scaled(lcf)
end

-- World point → local (unscaled) coordinates.
function Frame:toLocal(p: any): any
	return self.cf:PointToObjectSpace(p) / self.s
end

-- A child Model `name` whose parts are placed relative to this frame * lcf.
function Frame:child(name: string, lcf: any?): any
	return newFrame(U.model(self.model, name), self:world(lcf or CFrame.new()), self.s)
end

-- Same Model, shifted/rotated sub-frame.
function Frame:sub(lcf: any): any
	return newFrame(self.model, self:world(lcf), self.s)
end

-- World CFrame of a local point, facing yaw degrees (0 = local −Z): for Props placement.
function Frame:at(x: number, y: number, z: number, yaw: number?): any
	local s = self.s
	return self.cf * CFrame.new(x * s, y * s, z * s) * CFrame.Angles(0, rad(yaw or 0), 0)
end

function Frame:point(x: number, y: number, z: number): any
	local s = self.s
	return self.cf * V(x * s, y * s, z * s)
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
	local s = self.s
	local size = V(abs(x1 - x0) * s, abs(y1 - y0) * s, abs(z1 - z0) * s)
	local cf = self.cf * CFrame.new((x0 + x1) / 2 * s, (y0 + y1) / 2 * s, (z0 + z1) / 2 * s)
	return U.part(self.model, name, size, cf, color, nil, extra)
end

--[[
	Wedge filling the box between two local corners, its slope rising towards `up` ("+z" by
	default, "-z", "+x", "-x"): a full bottom face, a full upright face on the `up` side and the
	slope down to the opposite bottom edge. Roofs, gables, awnings and pent roofs only.
]]
function Frame:wedge(
	name: string,
	x0: number,
	y0: number,
	z0: number,
	x1: number,
	y1: number,
	z1: number,
	color: any,
	up: string?,
	extra: { [string]: any }?
): any
	local s = self.s
	local sx, sy, sz = abs(x1 - x0) * s, abs(y1 - y0) * s, abs(z1 - z0) * s
	local centre = CFrame.new((x0 + x1) / 2 * s, (y0 + y1) / 2 * s, (z0 + z1) / 2 * s)
	local size, turn = V(sx, sy, sz), CFrame.new()
	if up == "-z" then
		turn = CFrame.Angles(0, math.pi, 0)
	elseif up == "+x" then
		size, turn = V(sz, sy, sx), CFrame.Angles(0, rad(90), 0)
	elseif up == "-x" then
		size, turn = V(sz, sy, sx), CFrame.Angles(0, rad(-90), 0)
	end
	return U.wedge(self.model, name, size, self.cf * centre * turn, color, nil, extra)
end

--[[
	Block on a wall face: `face` is the wall's outward normal ("-z", "+z", "-x", "+x") and w the
	plane of its outer surface; a0..a1 run along the wall (x on z faces, z on x faces), d0..d1 is
	the depth out of the wall (negative = into it).
]]
function Frame:onFace(
	name: string,
	face: string,
	w: number,
	a0: number,
	y0: number,
	a1: number,
	y1: number,
	d0: number,
	d1: number,
	color: any,
	extra: { [string]: any }?
): any
	if face == "-z" then
		return self:box(name, a0, y0, w - d1, a1, y1, w - d0, color, extra)
	elseif face == "+z" then
		return self:box(name, a0, y0, w + d0, a1, y1, w + d1, color, extra)
	elseif face == "-x" then
		return self:box(name, w - d1, y0, a0, w - d0, y1, a1, color, extra)
	end
	return self:box(name, w + d0, y0, a0, w + d1, y1, a1, color, extra)
end

-- Like onFace, a wedge rising towards the wall: a pent roof over a door or a window.
local TOWARDS_WALL = { ["-z"] = "+z", ["+z"] = "-z", ["-x"] = "+x", ["+x"] = "-x" }
function Frame:faceWedge(
	name: string,
	face: string,
	w: number,
	a0: number,
	y0: number,
	a1: number,
	y1: number,
	d0: number,
	d1: number,
	color: any,
	extra: { [string]: any }?
): any
	local up = TOWARDS_WALL[face]
	if face == "-z" then
		return self:wedge(name, a0, y0, w - d1, a1, y1, w - d0, color, up, extra)
	elseif face == "+z" then
		return self:wedge(name, a0, y0, w + d0, a1, y1, w + d1, color, up, extra)
	elseif face == "-x" then
		return self:wedge(name, w - d1, y0, a0, w - d0, y1, a1, color, up, extra)
	end
	return self:wedge(name, w + d0, y0, a0, w + d1, y1, a1, color, up, extra)
end

-- Upright cylinder (thin round things only: poles, barrels, drums).
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
	local s = self.s
	local cf = self.cf * CFrame.new(x * s, (y0 + y1) / 2 * s, z * s) * CFrame.Angles(0, 0, rad(90))
	return U.part(
		self.model,
		name,
		V((y1 - y0) * s, d * s, d * s),
		cf,
		color,
		nil,
		merge({ Shape = Enum.PartType.Cylinder }, extra)
	)
end

-- A Props prop at a local point, scaled with the frame.
function Frame:prop(kind: string, x: number, y: number, z: number, yaw: number?, opts: { [string]: any }?): any
	local o = merge(opts, { scale = (opts and opts.scale or 1) * self.s })
	return Props[kind](self.model, self:at(x, y, z, yaw), o)
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
		U.new("UIStroke", { Name = "Stroke", Color = stroke, Thickness = 4 }, label)
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

-- Particles cost no parts (spray, foam, sparkles, smoke); rates stay low for phones.
local Rbx = U.roblox -- NumberSequence, NumberRange, ColorSequence
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds" -- glints: sparkles, droplets
local PUFF = "rbxasset://textures/particles/smoke_main.dds" -- soft puffs: foam, mist, smoke

-- Two-key NumberSequence a → b.
local function seq(a: number, b: number): any
	return Rbx.NumberSequence.new({ Rbx.NumberSequenceKeypoint.new(0, a), Rbx.NumberSequenceKeypoint.new(1, b) })
end

--[[
	ParticleEmitter in `part`. p: rate, life = {min, max}, speed = {min, max}, spread (degrees),
	size = {from, to}, fade = {from, to} (transparency), color = Color3 or {from, to}, accel
	(Vector3), dir (NormalId name, default "Top"), glow (LightEmission), drag, texture (default
	SPARKLE).
]]
local function emitter(part: any, name: string, p: { [string]: any }): any
	local col = p.color or C.White
	return U.new("ParticleEmitter", {
		Name = name,
		Texture = p.texture or SPARKLE,
		Rate = p.rate,
		Lifetime = Rbx.NumberRange.new(p.life[1], p.life[2]),
		Speed = Rbx.NumberRange.new(p.speed[1], p.speed[2]),
		SpreadAngle = U.Vector2.new(p.spread or 20, p.spread or 20),
		Size = seq(p.size[1], p.size[2]),
		Transparency = seq(p.fade and p.fade[1] or 0, p.fade and p.fade[2] or 1),
		Color = if type(col) == "table" then Rbx.ColorSequence.new(col[1], col[2]) else Rbx.ColorSequence.new(col),
		Acceleration = p.accel or V(0, 0, 0),
		EmissionDirection = Enum.NormalId[p.dir or "Top"],
		LightEmission = p.glow or 0,
		LightInfluence = if (p.glow or 0) > 0.5 then 0 else 1,
		Drag = p.drag or 0,
	}, part)
end

-- Chimney smoke: slow, soft, pale puffs drifting with the wind.
local function chimneySmoke(part: any)
	emitter(part, "Smoke", {
		rate = 1.6,
		life = { 3, 4.5 },
		speed = { 2, 3 },
		spread = 12,
		size = { 2, 5 },
		fade = { 0.45, 1 },
		color = C.CloudShade,
		accel = V(0.6, 0.4, 0),
		texture = PUFF,
	})
end

--------------------------------------------------------------------------------
-- Building kit (DESIGN.md §1 "Richness"): windows, doors, roofs, signs, awnings
--------------------------------------------------------------------------------

--[[
	Window on a wall face (Frame:onFace) centred at `a` along the wall, its sill at y0, wd × ht:
	a frame (o.trim) with the glass 0.1 proud of it, a mullion (unless o.mullion == false), a
	transom (o.cross), a sill (unless o.sill == false; colour o.sill or the trim), shutters either
	side (o.shutter, with a darker ledge across them when o.ledge) and a flower box under the sill
	(o.flowers = { c1, c2 }, box colour o.box or Wood). 2..10 parts.
]]
local function window(
	F: any,
	name: string,
	face: string,
	w: number,
	a: number,
	y0: number,
	wd: number,
	ht: number,
	o: { [string]: any }
)
	local hw = wd / 2
	if o.shutter then
		local sw = wd * 0.5
		F:onFace(
			name .. "Shutters",
			face,
			w,
			a - hw - sw,
			y0 + 0.15,
			a + hw + sw,
			y0 + ht - 0.15,
			-0.1,
			0.18,
			o.shutter
		)
		if o.ledge then
			local ly = y0 + ht * 0.5
			F:onFace(
				name .. "Ledge",
				face,
				w,
				a - hw - sw + 0.3,
				ly - 0.25,
				a + hw + sw - 0.3,
				ly + 0.25,
				0.1,
				0.26,
				shade(o.shutter, 0.78),
				DECOR
			)
		end
	end
	F:onFace(name .. "Frame", face, w, a - hw, y0, a + hw, y0 + ht, -0.1, 0.3, o.trim, NOSHADOW)
	local glassInset = math.min(0.5, wd * 0.14)
	F:onFace(
		name .. "Glass",
		face,
		w,
		a - hw + glassInset,
		y0 + glassInset,
		a + hw - glassInset,
		y0 + ht - glassInset,
		0,
		0.4,
		o.glass or C.WindowBlue,
		NOSHADOW
	)
	if o.mullion ~= false then
		F:onFace(name .. "Mullion", face, w, a - 0.22, y0 + 0.3, a + 0.22, y0 + ht - 0.3, 0, 0.5, o.trim, DECOR)
	end
	if o.cross then
		local ty = y0 + ht * 0.56
		F:onFace(name .. "Transom", face, w, a - hw + 0.3, ty - 0.2, a + hw - 0.3, ty + 0.2, 0, 0.5, o.trim, DECOR)
	end
	if o.sill ~= false then
		F:onFace(
			name .. "Sill",
			face,
			w,
			a - hw - 0.5,
			y0 - 0.5,
			a + hw + 0.5,
			y0 + 0.05,
			-0.1,
			0.8,
			o.sill or o.trim,
			NOSHADOW
		)
	end
	if o.flowers then
		local by = y0 - 0.5
		F:onFace(name .. "FlowerBox", face, w, a - hw + 0.1, by - 1.3, a + hw - 0.1, by, 0.05, 1.5, o.box or C.Wood)
		for i = 1, 2 do
			local c = a + (if i == 1 then -1 else 1) * hw * 0.45
			local top = by + 0.75 + (i % 2) * 0.2
			F:onFace(`{name}Bloom{i}`, face, w, c - 0.65, by - 0.2, c + 0.65, top, 0.5, 1.4, o.flowers[i], DECOR)
		end
	end
end

--[[
	Door on a wall face centred at `a`, threshold y0, wd × ht: a trim frame, the leaf (o.color)
	with a darker lower panel (o.panel), a stone step (o.step = { y0, y1, depth }), a little pent
	roof (o.canopy colour, wedge) and a lantern beside it (o.lantern = -1 | 1: the side).
	2..8 parts.
]]
local function door(
	F: any,
	name: string,
	face: string,
	w: number,
	a: number,
	y0: number,
	wd: number,
	ht: number,
	o: { [string]: any }
)
	local hw = wd / 2
	F:onFace(name .. "Frame", face, w, a - hw - 0.55, y0, a + hw + 0.55, y0 + ht + 0.55, -0.1, 0.3, o.trim, NOSHADOW)
	F:onFace(name, face, w, a - hw, y0, a + hw, y0 + ht, 0, 0.4, o.color, NOSHADOW)
	if o.panel then
		F:onFace(
			name .. "Panel",
			face,
			w,
			a - hw + 0.45,
			y0 + 0.7,
			a + hw - 0.45,
			y0 + ht * 0.42,
			0,
			0.5,
			shade(o.color, 0.8),
			DECOR
		)
	end
	if o.step then
		local s = o.step
		F:onFace(name .. "Step", face, w, a - hw - 0.9, s[1], a + hw + 0.9, s[2], -0.1, s[3], C.StoneLight, FLAT)
	end
	if o.canopy then
		local cy = y0 + ht + 0.4
		F:faceWedge(name .. "Canopy", face, w, a - hw - 1.1, cy, a + hw + 1.1, cy + 1.2, 0, 2.2, o.canopy)
	end
	if o.lantern then
		local lx = a + o.lantern * (hw + 1.6)
		local ly = y0 + ht - 1.8
		F:onFace(name .. "Lamp", face, w, lx - 0.6, ly, lx + 0.6, ly + 1.4, 0.3, 1.5, C.Glow, NEON_DECOR)
		F:onFace(name .. "LampCap", face, w, lx - 0.8, ly + 1.4, lx + 0.8, ly + 1.9, 0, 1.7, C.Iron, DECOR)
	end
end

--[[
	Gable roof (two wedges) over cx ± hl along the ridge by cz ± hs across it, the ridge along
	`along` ("x" | "z"), the eaves at y and the ridge line at y + rise. The roof overhangs the
	eaves by o.ov and the gable ends by o.og; a ridge beam (o.ridge) and two eave boards (o.eave,
	unless o.noEaves) give it a chunky trim. Each gable end listed in o.gables (−1 / 1 along the
	ridge axis; default both) gets a triangle of o.gable 0.3 in front of the roof's end, o.t
	below its slopes (the roof shows round it as a thick border), standing on a tie beam (o.beam,
	unless o.noBeam); o.window = { trim, glass } adds an attic window to the gables listed in
	o.windowAt (default all filled ones), o.king a king post (colour) above it.
	3..5 parts + per filled gable 2..6. Returns the top of the ridge beam.
]]
local function gableRoof(
	F: any,
	name: string,
	cx: number,
	cz: number,
	along: string,
	hl: number,
	hs: number,
	y: number,
	rise: number,
	o: { [string]: any }
): number
	local ov, og, t = o.ov or 1.5, o.og or 1, o.t or 0.9
	local ul, run = hl + og, hs + ov
	local k = rise / run
	local alongX = along == "x"
	-- (u, v) = (along the ridge, across it) → local (x, z)
	local function box(
		nm: string,
		u0: number,
		y0: number,
		v0: number,
		u1: number,
		y1: number,
		v1: number,
		col: any,
		ex: any?
	)
		local ua, ub = math.min(u0, u1), math.max(u0, u1)
		if alongX then
			return F:box(nm, cx + ua, y0, cz + v0, cx + ub, y1, cz + v1, col, ex)
		end
		return F:box(nm, cx + v0, y0, cz + ua, cx + v1, y1, cz + ub, col, ex)
	end
	local function wedge(
		nm: string,
		u0: number,
		y0: number,
		v0: number,
		u1: number,
		y1: number,
		v1: number,
		col: any,
		rising: number,
		ex: any?
	)
		local ua, ub = math.min(u0, u1), math.max(u0, u1)
		if alongX then
			return F:wedge(nm, cx + ua, y0, cz + v0, cx + ub, y1, cz + v1, col, if rising > 0 then "+z" else "-z", ex)
		end
		return F:wedge(nm, cx + v0, y0, cz + ua, cx + v1, y1, cz + ub, col, if rising > 0 then "+x" else "-x", ex)
	end
	wedge(name .. "A", -ul, y, -run, ul, y + rise, 0, o.roof, 1, o.extra)
	wedge(name .. "B", -ul, y, 0, ul, y + rise, run, o.roof, -1, o.extra)
	local ridgeTop = y + rise + 0.65
	if not o.noRidge then
		box(
			name .. "Ridge",
			-ul - 0.35,
			y + rise - 0.75,
			-0.95,
			ul + 0.35,
			ridgeTop,
			0.95,
			o.ridge or shade(o.roof, 0.78)
		)
	end
	if not o.noEaves then
		for i, sv in { -1, 1 } do
			local va, vb = sv * (run + 0.3), sv * (run - 0.8)
			box(
				`{name}Eave{i}`,
				-ul - 0.2,
				y - 0.7,
				math.min(va, vb),
				ul + 0.2,
				y + 0.35,
				math.max(va, vb),
				o.eave or C.WoodDark,
				NOSHADOW
			)
		end
	end
	local vIn = run - t / k -- half width of a gable triangle at the eave line
	local windowAt = o.windowAt
	for _, su in o.gables or { -1, 1 } do
		local gname = name .. (if su < 0 then "Gable1" else "Gable2")
		local function out(d: number): number -- u of a plane d in front of the gable fill
			return su * (ul + 0.3 + d)
		end
		wedge(gname .. "A", su * ul, y, -vIn, out(0), y + rise - t, 0, o.gable, 1)
		wedge(gname .. "B", su * ul, y, 0, out(0), y + rise - t, vIn, o.gable, -1)
		if not o.noBeam and (not o.beamAt or o.beamAt[su]) then
			box(
				gname .. "Beam",
				su * (hl - 0.8),
				y - 1.1,
				-vIn - 0.4,
				out(0.25),
				y + 0.1,
				vIn + 0.4,
				o.beam or C.WoodDark
			)
		end
		local top = y + 0.1
		if o.window and (not windowAt or windowAt[su]) then
			local wh = math.min(3.4, (rise - t) * 0.42)
			local ww = math.min(3.2, wh)
			local wy = y + 0.9
			box(gname .. "WinFrame", out(-0.05), wy, -ww / 2, out(0.25), wy + wh, ww / 2, o.window[1], NOSHADOW)
			box(
				gname .. "WinGlass",
				out(-0.05),
				wy + 0.45,
				-ww / 2 + 0.45,
				out(0.35),
				wy + wh - 0.45,
				ww / 2 - 0.45,
				o.window[2] or C.WindowBlue,
				NOSHADOW
			)
			top = wy + wh + 0.05
		end
		if o.king then
			local kTop = y + rise - t - 1.2
			if kTop > top + 1 then
				box(gname .. "King", out(-0.05), top, -0.45, out(0.2), kTop, 0.45, o.king, NOSHADOW)
			end
		end
	end
	return ridgeTop
end

--[[
	Gabled dormer on a roof slope: a little wall box (o.wall) standing in the roof, its front on the
	plane w of `face` (the direction down the slope) centred at `a`, from y0 (the roof surface
	at its front) up by ht, `depth` deep into the roof (deep enough that the main roof covers its
	back), with a framed window (o.trim) and its own little gable roof (o.roof, two wedges; the roof
	colour shows on their ends). 5 parts.
]]
local function dormer(
	F: any,
	name: string,
	face: string,
	w: number,
	a: number,
	y0: number,
	wd: number,
	ht: number,
	depth: number,
	o: { [string]: any }
)
	F:onFace(name, face, w, a - wd / 2, y0 - 1.5, a + wd / 2, y0 + ht, -depth, 0, o.wall)
	F:onFace(
		name .. "Frame",
		face,
		w,
		a - wd / 2 + 0.8,
		y0 + 0.6,
		a + wd / 2 - 0.8,
		y0 + ht - 0.6,
		-0.1,
		0.3,
		o.trim,
		NOSHADOW
	)
	F:onFace(
		name .. "Glass",
		face,
		w,
		a - wd / 2 + 1.25,
		y0 + 1.05,
		a + wd / 2 - 1.25,
		y0 + ht - 1.05,
		0,
		0.4,
		C.WindowBlue,
		NOSHADOW
	)
	local sgn = if face == "+z" or face == "+x" then -1 else 1 -- from the front into the roof
	local mid = w + sgn * depth / 2
	local rOpts = { roof = o.roof, gables = {}, noEaves = true, noRidge = true, ov = 0.6, og = 0.6 }
	if face == "+z" or face == "-z" then
		gableRoof(F, name .. "Roof", a, mid, "z", depth / 2, wd / 2, y0 + ht, wd * 0.42, rOpts)
	else
		gableRoof(F, name .. "Roof", mid, a, "x", depth / 2, wd / 2, y0 + ht, wd * 0.42, rOpts)
	end
end

-- Sign board in the local XY plane on depth zc (front = −Z): a frame behind the board and text
-- (ink, optional stroke) on its front face and, with backText, on its back. 2 parts.
local function signBoard(
	F: any,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	zc: number,
	board: any,
	frame: any,
	text: string,
	backText: string?,
	ink: any?,
	stroke: any?
): any
	F:box(name .. "Frame", x0 - 0.8, y0 - 0.8, zc - 0.35, x1 + 0.8, y1 + 0.8, zc + 0.35, frame)
	local b = F:box(name, x0, y0, zc - 0.55, x1, y1, zc + 0.55, board)
	signText(b, Enum.NormalId.Front, text, ink or C.Cream, stroke)
	if backText then
		signText(b, Enum.NormalId.Back, backText, ink or C.Cream, stroke)
	end
	return b
end

--[[
	Striped awning on a wall face at zFace (front = −Z) from x0 to x1: n wedge stripes sloping from
	yTop at the wall down by `drop` over `depth`, alternating c1 / c2, each with a valance under its
	front edge (the c1 ones hang lower: scallops). 2n parts.
]]
local function awning(
	F: any,
	name: string,
	x0: number,
	x1: number,
	yTop: number,
	zFace: number,
	depth: number,
	drop: number,
	n: number,
	c1: any,
	c2: any
)
	local w = (x1 - x0) / n
	local zEnd = zFace - depth
	for i = 0, n - 1 do
		local a, b = x0 + i * w, x0 + (i + 1) * w
		local col = if i % 2 == 0 then c1 else c2
		F:wedge(`{name}{i + 1}`, a, yTop - drop, zEnd, b, yTop, zFace, col, "+z", NOSHADOW)
		local hang = if i % 2 == 0 then 1.5 else 1.0
		F:box(
			`{name}Valance{i + 1}`,
			a,
			yTop - drop - hang,
			zEnd - 0.05,
			b,
			yTop - drop + 0.05,
			zEnd + 0.45,
			col,
			DECOR
		)
	end
end

--------------------------------------------------------------------------------
-- Recurring pieces: fish, gear, flower bed, street lamp
--------------------------------------------------------------------------------

--[[
	Big cartoon voxel fish lying along local X (head at −X), its side towards ±Z, centred on the
	frame origin; s scales it (s = 1: ~27 long, ~16 tall). pal: body, head, belly, fin, lips,
	spots. opts.crown (golden crown with gems), opts.simple (10 parts: no belly, fins, scales,
	shine), opts.side = −1 | 1 (a relief: eye, shine and spot only on that Z side, the other one
	is in the wall). 16-24 parts. opts.extra (property set for the big parts).
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
	b("Lips", -13.8, -2.6, -1.9, -11.9, 0.2, 1.9, pal.lips, merge(big, NOSHADOW))
	b("TailStem", 5.6, -2.6, -2.1, 9.6, 2.6, 2.1, pal.body, big)
	b("TailUp", 9.2, 1.2, -1.2, 13.4, 7.8, 1.2, pal.fin, big)
	b("TailDown", 9.2, -7.8, -1.2, 13.4, -1.2, 1.2, pal.fin, big)
	local sides = if o.side then { o.side } else { -1, 1 }
	for i, sz in sides do
		b(`Eye{i}`, -11.4, -0.2, sz * 2.95, -8.0, 3.6, sz * 3.35, C.White, DECOR)
		b(`Pupil{i}`, -10.9, 0.4, sz * 3.25, -8.9, 2.8, sz * 3.6, C.Dark, DECOR)
	end
	if not o.simple then
		b("Belly", -7.6, -5.6, -3.6, 4.4, -2.2, 3.6, pal.belly, big)
		b("Dorsal", -4.4, 4.6, -1.1, 3.2, 8.8, 1.1, pal.fin, big)
		b("FinL", -4, -3.6, -4.8, 0.4, -1.4, -3.4, pal.fin, merge(big, NOSHADOW))
		b("FinR", -4, -3.6, 3.4, 0.4, -1.4, 4.8, pal.fin, merge(big, NOSHADOW))
		for i, sz in sides do
			b(`Shine{i}`, -10.5, 2.0, sz * 3.45, -9.8, 2.6, sz * 3.72, C.White, DECOR)
			b(`Spot{i}`, -3.6, -0.6, sz * 3.5, 0.6, 3.0, sz * 3.68, pal.spots or pal.belly, DECOR)
		end
	end
	if o.crown then
		local gold = C.GoldLight
		b("CrownBand", -11.7, 4.2, -2.2, -7.9, 5.6, 2.2, gold, merge(big, NEON))
		for i, x in { -11.25, -9.8, -8.35 } do
			b(`CrownSpike{i}`, x - 0.45, 5.5, -0.5, x + 0.45, 7.3, 0.5, gold, merge(big, NEON))
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
	Voxel gear facing −Z in the local XY plane, centre (cx, cz), outer radius r: a rounded body
	(plus of two blocks), 4 square teeth on the axes and 4 on the diagonals (pixel-art steps), and
	a hub. The teeth overlap the body (one solid piece) and are a little thinner, so no faces are
	coplanar. 11 parts. Returns the body, centred on the gear with LookVector = the axle.
]]
local function gear(F: any, cx: number, cy: number, cz: number, r: number, t: number, color: any, hub: any): any
	local b = r * 0.62
	local k = r * 0.38
	local body = F:box("Gear", cx - b, cy - k, cz - t / 2, cx + b, cy + k, cz + t / 2, color)
	F:box("GearB", cx - k, cy - b, cz - t / 2 - 0.1, cx + k, cy + b, cz + t / 2 + 0.1, color)
	local tw = r * 0.34
	local tz = t / 2 - 0.1 -- teeth are 0.2 thinner than the body
	for i, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
		-- from inside the body (0.5 r) out to the rim (r)
		local x0, x1 = cx + d[1] * r * 0.5, cx + d[1] * r
		local y0, y1 = cy + d[2] * r * 0.5, cy + d[2] * r
		if d[1] == 0 then
			x0, x1 = cx - tw / 2, cx + tw / 2
		else
			y0, y1 = cy - tw / 2, cy + tw / 2
		end
		F:box(`Tooth{i}`, x0, y0, cz - tz, x1, y1, cz + tz, color)
	end
	local dd = r * 0.53 -- overlaps both body blocks
	for i, d in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		local tx, ty = cx + d[1] * dd, cy + d[2] * dd
		F:box(`ToothD{i}`, tx - tw / 2, ty - tw / 2, cz - tz, tx + tw / 2, ty + tw / 2, cz + tz, color)
	end
	F:box(
		"GearHub",
		cx - r * 0.24,
		cy - r * 0.24,
		cz - t / 2 - 0.25,
		cx + r * 0.24,
		cy + r * 0.24,
		cz + t / 2 + 0.25,
		hub
	)
	return body
end

--[[
	Raised flower bed centred at (cx, cz), w along X, d along Z: a stone border block, soil, a green
	cushion and one row of cube flowers along the long side. 3 + n parts.
]]
local function flowerBed(F: any, cx: number, cz: number, w: number, d: number, colors: { any }, border: any?)
	F:box("Bed", cx - w / 2, -0.3, cz - d / 2, cx + w / 2, 1.0, cz + d / 2, border or C.StoneLight)
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
	local len = if alongX then w else d
	local n = math.max(2, floor((len - 1.4) / 2.2))
	for i = 1, n do
		local t = -len / 2 + 0.7 + (len - 1.4) * (i - 0.5) / n
		local x = if alongX then cx + t else cx + (if i % 2 == 0 then 0.35 else -0.35)
		local z = if alongX then cz + (if i % 2 == 0 then 0.35 else -0.35) else cz + t
		local top = 2.6 + (i % 3) * 0.18 -- bottoms sink into the green cushion (top 1.8)
		F:box(`Flower{i}`, x - 0.6, 1.6, z - 0.6, x + 0.6, top, z + 0.6, colors[(i - 1) % #colors + 1], DECOR)
	end
end

--[[
	Chunky street lamp standing on cf: stone foot, dark post, an iron plate, a big Neon cube and an
	iron cap (the silhouette of Props.lampPost without its collar and knob, for the hub's many
	lamps). light = true adds a PointLight. 5 parts.
]]
local function streetLamp(parent: any, cf: any, h: number, trim: any?, light: boolean?): any
	local F = newFrame(U.model(parent, "LampPost"), cf)
	local iron = trim or C.Iron
	F:box("Foot", -1.2, -0.4, -1.2, 1.2, 1.0, 1.2, C.StoneLight)
	local post = F:box("Post", -0.5, 0.9, -0.5, 0.5, h, 0.5, C.WoodDark)
	F:box("Plate", -1.5, h - 0.05, -1.5, 1.5, h + 0.45, 1.5, iron, NOSHADOW)
	local glow = F:box("Glow", -1.12, h + 0.45, -1.12, 1.12, h + 2.95, 1.12, C.Glow, NEON)
	F:box("Cap", -1.7, h + 2.95, -1.7, 1.7, h + 3.7, 1.7, iron, NOSHADOW)
	if light then
		pointLight(glow, 16, 1.6)
	end
	F.model.PrimaryPart = post
	post.PivotOffset = post.CFrame:Inverse() * cf
	return F.model
end

--------------------------------------------------------------------------------
-- Shop buildings (local frame: origin = front centre at ground level, −Z = customers)
--------------------------------------------------------------------------------

local FL = 1.0 -- floor level of the shops above the plaza ground (porch and interior)

-- Shop dimensions: half width, depth (front z = 0 .. back z = D), half width of the open front
-- between the jambs, top of the opening. The porch runs from z = −8.5 to 2.
local HW, D, OH, OPEN = 23, 34, 19, 13.6
local WO, WI = HW - 0.4, HW - 3.6 -- outer and inner face of the side walls (x)

--[[
	Shared shell of the Shop and the Workshop: a stone plinth with a plank porch and a step down
	to the plaza, the interior floor, side and back walls, the two front wall pieces beside the
	open front (x ±OH, up to OPEN) and the wall above it, a stone base course round the outside
	(top `course`), jambs at the opening and a heavy lintel beam across the whole front.
	s: wall, porch, floor, jamb, beam, course. 18 parts. Returns the plinth.
]]
local function shopShell(F: any, h: number, s: { [string]: any }): any
	local plinth = F:box("Plinth", -HW - 1, -0.5, -9, HW + 1, FL - 0.4, D + 1, C.Stone, FLAT)
	F:box("Porch", -HW - 0.4, FL - 0.4, -8.5, HW + 0.4, FL, 2, s.porch, FLAT)
	F:box("PorchStep", -10, -0.5, -10.4, 10, FL - 0.75, -8.9, C.StoneLight, FLAT)
	F:box("Floor", -WI, FL - 0.4, 2, WI, FL, D - 3.6, s.floor, FLAT)
	F:box("WallL", -WO, FL - 0.4, 3.6, -WI, h, D - 0.4, s.wall)
	F:box("WallR", WI, FL - 0.4, 3.6, WO, h, D - 0.4, s.wall)
	F:box("WallBack", -WI, FL - 0.4, D - 3.6, WI, h, D - 0.4, s.wall)
	F:box("WallFrontL", -WO, FL - 0.4, 0.4, -OH, h, 3.6, s.wall)
	F:box("WallFrontR", OH, FL - 0.4, 0.4, WO, h, 3.6, s.wall)
	F:box("Lintel", -OH, OPEN, 0.4, OH, h, 3.6, s.wall)
	-- stone base course (0.25 proud) on the sides, the back and the front pieces
	local cy = s.course
	F:box("CourseL", -WO - 0.25, FL - 0.4, 0.15, -WO + 0.6, cy, D - 0.15, C.Stone, NOSHADOW)
	F:box("CourseR", WO - 0.6, FL - 0.4, 0.15, WO + 0.25, cy, D - 0.15, C.Stone, NOSHADOW)
	F:box("CourseBack", -WO - 0.25, FL - 0.4, D - 0.65, WO + 0.25, cy, D - 0.15, C.Stone, NOSHADOW)
	for i, sx in { -1, 1 } do
		F:box(`CourseFront{i}`, sx * (OH + 1.0), FL - 0.4, 0.15, sx * (WO + 0.25), cy, 0.9, C.Stone, NOSHADOW)
		-- jambs framing the open front (0.3 into the opening and 0.3 proud of the facade)
		F:box(`Jamb{i}`, sx * (OH - 0.3), FL, 0.1, sx * (OH + 1.3), h, 1.6, s.jamb)
	end
	F:box("FrontBeam", -WO - 0.2, OPEN - 0.6, -0.2, WO + 0.2, OPEN + 0.7, 1.2, s.beam)
	return plinth
end

--[[
	Shop «УДОЧКИ» (sells rods): a two-storey half-timbered house — white plaster between dark
	timber posts and rails on a stone base course, green shutters, flower boxes under the ground
	floor windows, a red roof with a ridge beam, eave boards and plastered gables with attic
	windows, a brick chimney with smoke. The open shop front: a red/cream striped awning under the
	lintel beam, the dark sign board above it, the counter (Counter.ShopPromptAttachment) between
	two glass display cases, a rod wall, a shelf of tackle and a trophy fish inside. A giant rod in
	a holder on a bracket at the left eave rises over the porch; a fish dangles from its line in
	front of the roof and slowly twirls. On the porch: a rod rack, a barrel of rods and a sandwich
	board «Купить удочку».
]]
local function buildShop(hub: any, cf: any): (any, any)
	local F = newFrame(U.model(hub, "Shop"), cf, SHOP_SCALE)
	local wall, timber, trim = C.Plaster, C.WoodDark, C.Cream
	local roof, accent, shutter = C.RoofRed, C.Red, C.RoofGreen
	local h = 22
	local course = FL + 2.2
	local plinth = shopShell(F, h, {
		wall = wall,
		porch = C.Plank,
		floor = C.WoodLight,
		jamb = timber,
		beam = timber,
		course = course,
	})

	-- half-timbering: corner posts, a post in the middle of each side and of the back, the floor
	-- rail of the upper storey, the top plate under the eaves
	for i, p in { { -1, 0 }, { 1, 0 }, { -1, 1 }, { 1, 1 } } do
		local z0, z1 = 0.1, 1.6
		if p[2] == 1 then
			z0, z1 = D - 1.6, D - 0.1
		end
		F:box(`Post{i}`, p[1] * (WO - 1.3), course, z0, p[1] * (WO + 0.3), h, z1, timber)
	end
	for i, sx in { -1, 1 } do
		F:box(`MidPost{i}`, sx * (WO - 0.5), course, D / 2 - 0.7, sx * (WO + 0.25), h, D / 2 + 0.7, timber)
		F:box(`Rail{i}`, sx * (WO - 0.5), OPEN - 0.5, 0.15, sx * (WO + 0.2), OPEN + 0.5, D - 0.15, timber)
	end
	F:box("BackPost", -0.7, course, D - 0.9, 0.7, h, D - 0.15, timber)
	F:box("BackRail", -WO - 0.2, OPEN - 0.5, D - 0.7, WO + 0.2, OPEN + 0.5, D - 0.2, timber)
	F:box("Plate", -WO - 0.45, h - 0.5, -0.05, WO + 0.45, h + 1.0, D + 0.05, timber)

	-- windows: two shuttered ones with flower boxes on each side, small ones upstairs, two at the
	-- back (the side the bases see)
	for i, sx in { -1, 1 } do
		local face = if sx < 0 then "-x" else "+x"
		for j, zc in { 9.5, 24.5 } do
			local k = i * 2 + j
			window(F, `Win{i}_{j}`, face, sx * WO, zc, FL + 3.6, 6, 6.6, {
				trim = trim,
				shutter = shutter,
				ledge = true,
				flowers = { C.Flowers[k % #C.Flowers + 1], C.Flowers[(k + 2) % #C.Flowers + 1] },
			})
			window(F, `UpWin{i}_{j}`, face, sx * WO, zc, OPEN + 1.7, 4.4, 4.6, { trim = trim, mullion = false })
		end
	end
	for j, xc in { -10, 10 } do
		window(F, `BackWin{j}`, "+z", D - 0.4, xc, FL + 3.6, 6.4, 6.6, { trim = trim, shutter = shutter })
		window(F, `BackUpWin{j}`, "+z", D - 0.4, xc, OPEN + 1.7, 4.4, 4.6, { trim = trim, mullion = false })
	end

	-- roof: ridge along X, plastered gables with attic windows and king posts; brick chimney
	local ridgeTop = gableRoof(F, "Roof", 0, D / 2, "x", WO + 0.45, D / 2 + 0.05, h + 1.0, 14, {
		roof = roof,
		eave = timber,
		gable = wall,
		beam = timber,
		ov = 2.4,
		og = 1.4,
		t = 1.1,
		window = { trim, C.WindowBlue },
		king = timber,
	})
	-- a dormer on the back slope (the roof surface at z: eave 23 at z 36.45, slope 14 / 19.45)
	local dz = 31
	dormer(F, "Dormer", "+z", dz, -9, h + 1.0 + (D / 2 + 19.45 - dz) * 14 / 19.45, 7.4, 6, 12, {
		wall = wall,
		trim = trim,
		roof = roof,
	})
	F:box("Chimney", 12.6, h, 22.6, 16.4, ridgeTop + 1.6, 26.4, C.Brick)
	local cap = F:box("ChimneyCap", 12.2, ridgeTop + 1.6, 22.2, 16.8, ridgeTop + 2.6, 26.8, C.StoneDark)
	chimneySmoke(cap)

	-- the sign over the shop front, the awning under the lintel beam
	signBoard(F, "Sign", -14.5, 14.5, OPEN + 1.7, h - 1.3, -0.15, timber, trim, "УДОЧКИ", nil, C.Cream, C.Dark)
	awning(F, "Awning", -OH + 0.3, OH - 0.3, OPEN - 0.6, 0.1, 6.6, 2.2, 6, accent, C.Cream)

	-- the giant rod: its butt sits in a holder on a bracket at the left eave, the rod rises over the
	-- porch in front of the roof; a fish hangs on the line (its lips on the hook, the body
	-- wriggling down) and slowly twirls on it (Spin about the vertical through the hook)
	F:box("RodArm", -21.6, h + 0.2, -5.6, -19.6, h + 1.2, 0.6, timber)
	F:box("RodHolder", -21.9, h + 1.2, -6.0, -19.3, h + 3.2, -4.0, timber)
	local rod = F:sub(CFrame.new(-20.6, h + 2.4, -5.0) * CFrame.Angles(0, 0, rad(36)))
	rod:box("RodHandle", -0.4, -0.9, -0.9, 4.8, 0.9, 0.9, C.WoodLight)
	rod:box("RodReel", 2.6, -2.5, -1.1, 4.4, -0.9, 1.1, C.Iron, NOSHADOW)
	rod:box("Rod1", 4.8, -0.55, -0.55, 18, 0.55, 0.55, C.Navy)
	rod:box("Rod2", 18, -0.38, -0.38, 30, 0.38, 0.38, C.Navy, NOSHADOW)
	local tip = rod:box("RodTip", 30, -0.45, -0.45, 31.4, 0.45, 0.45, accent, NOSHADOW)
	local tipPos = F:toLocal(tip.CFrame.Position)
	local hookY, fs = tipPos.Y - 6, 0.4
	F:box("Line", tipPos.X - 0.12, hookY, -5.12, tipPos.X + 0.12, tipPos.Y, -4.88, C.White, DECOR)
	local hook = CFrame.new(tipPos.X, hookY, -5)
	local hooked = F:child("HookedFish", hook * CFrame.Angles(0, 0, rad(-52)) * CFrame.new(13.8 * fs, 1.2 * fs, 0))
	local hookedBody = bigFish(hooked, fs, {
		body = C.Orange,
		head = lerpColor(C.Orange, C.Cream, 0.3),
		fin = accent,
		lips = C.Pink,
	}, { simple = true })
	hooked.model.PrimaryPart = hookedBody
	hookedBody.PivotOffset = hookedBody.CFrame:Inverse() * F:world(hook * CFrame.Angles(rad(90), 0, 0))
	hooked.model:SetAttribute("Spin", 30)

	-- the counter and glass display cases close the opening
	local counter = F:box("Counter", -8, FL, 2.6, 8, 4.4, 5.6, C.Wood)
	F:box("CounterTop", -8.4, 4.4, 2.2, 8.4, 5.0, 6.0, C.WoodLight)
	F:box("CounterPanel", -7.2, FL + 0.7, 2.45, 7.2, 3.8, 2.6, timber, NOSHADOW)
	U.new("Attachment", { Name = "ShopPromptAttachment", CFrame = CFrame.new(0, 1.3, -2.3) }, counter)
	for i, sx in { -1, 1 } do
		F:box(`Case{i}`, sx * 8.4, FL, 2.6, sx * OH, 3.2, 5.6, C.Wood)
		F:box(`CaseGlass{i}`, sx * 8.5, 3.2, 2.7, sx * (OH - 0.1), 4.6, 5.5, C.Glass, GLASS)
		F:box(`CaseRodA{i}`, sx * 9.2, 3.25, 3.4, sx * (OH - 0.8), 3.6, 3.75, C.Navy, DECOR)
		F:box(`CaseRodB{i}`, sx * 9.2, 3.25, 4.5, sx * (OH - 0.8), 3.6, 4.85, accent, DECOR)
	end

	-- interior: rod wall, a shelf with tackle boxes, a trophy fish, a hanging lamp
	local bi = D - 3.6
	F:box("RodWall", -15, 2.6, bi - 0.6, 15, 17, bi, C.WoodLight, NOSHADOW)
	for k = 0, 4 do
		local x = -10 + k * 5
		F:box(`Rod{k + 1}`, x - 0.3, 3.2, bi - 1.2, x + 0.3, 16.4, bi - 0.6, C.BoatPaint[k + 1], DECOR)
		F:box(`Reel{k + 1}`, x - 0.75, 5.4, bi - 1.7, x + 0.75, 6.7, bi - 1.1, C.Iron, DECOR)
	end
	F:box("Shelf", -WI, 7, 10, -WI + 2, 7.5, 24, C.Wood, NOSHADOW)
	for i, c in { accent, H.tile, C.Yellow } do
		local z = 8 + i * 4.5
		F:box(`Tackle{i}`, -WI + 0.2, 7.5, z - 0.9, -WI + 1.8, 9.0, z + 0.9, c, DECOR)
	end
	F:box("Trophy", WI - 0.6, 8, 13.5, WI, 13, 20.5, C.Wood, NOSHADOW)
	F:box("TrophyFish", WI - 1.2, 9.4, 14.4, WI - 0.6, 11.6, 18.4, H.fish[4], DECOR)
	F:box("TrophyTail", WI - 1.1, 9.0, 18.4, WI - 0.7, 12.0, 19.6, H.tile, DECOR)
	local lamp = F:box("CeilingLamp", -1.6, h - 3, 15, 1.6, h - 1.8, 18, C.Glow, NEON_DECOR)
	F:box("LampCord", -0.15, h - 1.8, 16.35, 0.15, h, 16.65, C.Dark, DECOR)
	pointLight(lamp, 16, 1.3)

	-- porch: a rod rack, a barrel of rods, a sandwich board
	F:prop("fishingRodRack", -15.5, FL, -4.6, 0, { seed = 3 })
	local barrel = F:prop("barrel", 19.6, FL, -5.2, 0, { color = C.Wood, seed = 4 })
	local bp = F:toLocal(barrel.PrimaryPart.CFrame.Position)
	for i, c in { accent, C.Navy, C.WoodLight } do
		local dx = (i - 2) * 0.6
		local dz = (i % 2) * 0.4
		F:box(`BarrelRod{i}`, bp.X + dx - 0.15, 3, bp.Z - 0.2 + dz, bp.X + dx + 0.15, 11.5, bp.Z + 0.1 + dz, c, DECOR)
	end
	local ab = F:box("BoardSign", 10.6, FL + 1.0, -7.2, 15.4, FL + 4.6, -6.8, C.Cream, NOSHADOW)
	F:box("BoardLegs", 10.9, FL, -6.8, 15.1, FL + 4.2, -6.2, timber, NOSHADOW)
	signText(ab, Enum.NormalId.Front, "Купить удочку", C.WoodDark)
	F.model.PrimaryPart = plinth
	return F.model, counter
end

--[[
	Workshop «МАСТЕРСКАЯ» (upgrades): a brick workshop on a stone base course with pale stone
	quoins and jambs, iron-framed windows, a slate roof whose gable faces the plaza and carries a
	big slowly turning gear, a tall chimney with smoke, a side door with a pent roof. The open
	front: a rolled-up garage door under the lintel beam, the sign, the workbench with tools and a
	glowing upgrade gem (Workbench.UpgradePromptAttachment), a tool chest and an anvil; inside a
	pegboard and a glowing forge; outside a giant wrench, barrels and wall lanterns.
]]
local function buildWorkshop(hub: any, cf: any): (any, any)
	local F = newFrame(U.model(hub, "Workshop"), cf, SHOP_SCALE)
	local wall, stone, timber = C.Brick, C.StoneLight, C.WoodDark
	local roof, accent = C.RoofSlate, C.Orange
	local h = 21
	local course = FL + 2.0
	local plinth = shopShell(F, h, {
		wall = wall,
		porch = C.Wood,
		floor = lerpColor(C.WoodLight, C.Stone, 0.35),
		jamb = stone,
		beam = timber,
		course = course,
	})
	local bi, wi = D - 3.6, WI

	-- stone quoins on the corners (alternating long and short blocks), the top plate
	for i, p in { { -1, 0 }, { 1, 0 }, { -1, 1 }, { 1, 1 } } do
		local zf = if p[2] == 0 then 0.4 else D - 0.4 -- the corner's face plane on z
		local zs = if p[2] == 0 then 1 else -1 -- into the building
		for q, y0 in { course + 0.6, course + 5.4, course + 10.2, course + 15.0 } do
			if p[2] == 0 or q % 2 == 1 then
				local long = q % 2 == 1
				local ax = if long then 3.0 else 1.6
				local az = if long then 1.6 else 3.0
				local x0, x1 = p[1] * (WO - ax), p[1] * (WO + 0.25)
				local z0, z1 = zf - zs * 0.25, zf + zs * az
				F:box(
					`Quoin{i}_{q}`,
					math.min(x0, x1),
					y0,
					math.min(z0, z1),
					math.max(x0, x1),
					y0 + 2.6,
					math.max(z0, z1),
					stone,
					NOSHADOW
				)
			end
		end
	end
	F:box("Plate", -WO - 0.45, h - 0.5, -0.05, WO + 0.45, h + 1.0, D + 0.05, timber)

	-- iron-framed workshop windows with stone sills, two on each side and two at the back
	local win = { trim = stone, glass = C.WindowBlue, cross = true }
	for i, sx in { -1, 1 } do
		for j, zc in { 10, 24 } do
			window(F, `Win{i}_{j}`, if sx < 0 then "-x" else "+x", sx * WO, zc, FL + 4.4, 7, 7.6, win)
		end
	end
	for j, xc in { -10, 10 } do
		window(F, `BackWin{j}`, "+z", D - 0.4, xc, FL + 4.4, 7, 7.6, win)
	end
	-- a side door between the right-hand windows, under a little slate pent roof
	door(F, "SideDoor", "+x", WO, 17, FL, 4.2, 8.4, {
		trim = stone,
		color = C.Wood,
		panel = true,
		canopy = roof,
		step = { -0.5, FL - 0.3, 1.6 },
	})

	-- slate roof with the gable to the plaza (ridge along Z); brick gable fill; a window in the
	-- back gable, the big gear in the front one
	local ridgeTop = gableRoof(F, "Roof", 0, D / 2, "z", D / 2 + 0.05, WO + 0.45, h + 1.0, 11, {
		roof = roof,
		eave = timber,
		gable = wall,
		beam = timber,
		ov = 1.8,
		og = 1.6,
		t = 1.0,
		window = { stone, C.WindowBlue },
		windowAt = { [1] = true },
	})
	local cog = F:child("SignGear")
	cog.model.PrimaryPart = gear(cog, 0, h + 5.6, -2.9, 4.6, 1.4, lerpColor(C.Iron, C.StoneLight, 0.55), C.Gold)
	cog.model:SetAttribute("Spin", -24)
	-- tall brick chimney on the right, a stone band, a dark cap, smoke
	F:box("Chimney", 13.6, h, D - 10, 17.6, ridgeTop + 3.4, D - 6, wall)
	F:box("ChimneyBand", 13.3, ridgeTop + 0.6, D - 10.3, 17.9, ridgeTop + 1.6, D - 5.7, stone, NOSHADOW)
	local cap = F:box("ChimneyCap", 13.2, ridgeTop + 3.4, D - 10.4, 18.0, ridgeTop + 4.4, D - 5.6, C.StoneDark)
	chimneySmoke(cap)

	-- the sign over the opening, the rolled-up garage door, wall lanterns either side
	signBoard(F, "Sign", -14.5, 14.5, OPEN + 1.7, h - 1.3, -0.15, C.Cream, timber, "МАСТЕРСКАЯ", nil, timber)
	F:box("DoorRoll", -OH, OPEN - 2.2, 1.4, OH, OPEN - 0.6, 3.4, C.Wood, NOSHADOW)
	for i, x in { -12, 0, 12 } do
		F:box(`DoorBand{i}`, x - 0.5, OPEN - 2.35, 1.25, x + 0.5, OPEN - 0.5, 3.55, C.Iron, DECOR)
	end
	for i, sx in { -1, 1 } do
		local x = sx * (OH + 2.2)
		F:box(`WallLamp{i}`, x - 0.7, 8.4, -0.6, x + 0.7, 10.2, 0.4, C.Glow, NEON_DECOR)
		F:box(`WallLampCap{i}`, x - 0.9, 10.2, -0.8, x + 0.9, 10.7, 0.4, C.Iron, DECOR)
	end

	-- the workbench (counter) with tools and a glowing upgrade gem
	local bench = F:box("Workbench", -8, FL, 2.6, 8, 4.0, 5.6, C.Wood)
	F:box("BenchTop", -8.6, 4.0, 2.2, 8.6, 4.7, 6.0, C.WoodLight)
	F:box("DrawerL", -6.8, 1.7, 2.45, -1.2, 3.4, 2.65, timber, NOSHADOW)
	F:box("DrawerR", 1.2, 1.7, 2.45, 6.8, 3.4, 2.65, timber, NOSHADOW)
	U.new("Attachment", { Name = "UpgradePromptAttachment", CFrame = CFrame.new(0, 1.5, -2.3) }, bench)
	F:box("HammerHandle", 3, 4.7, 3.6, 5.7, 5.1, 4.0, C.WoodDark, DECOR)
	F:box("HammerHead", 5.6, 4.75, 3.2, 6.8, 5.6, 4.4, C.Iron, DECOR)
	F:box("Wrench", -6.4, 4.7, 4.4, -2.6, 5.0, 4.9, C.StoneLight, DECOR)
	F:box("WrenchJaw", -7.2, 4.75, 4.0, -6.2, 5.05, 5.3, C.StoneLight, DECOR)
	F:box("GemStand", -0.7, 4.7, 3.4, 0.7, 5.4, 4.8, C.Gold, NOSHADOW)
	F:box("UpgradeGem", -0.55, 5.4, 3.55, 0.55, 6.6, 4.65, C.Cyan, NEON_DECOR)
	-- tool chest (left), anvil and a crate (right) close the opening
	F:box("ToolChest", -OH, FL, 2.6, -8.9, 5.0, 6.2, C.Red)
	F:box("ChestDrawer1", -OH + 0.6, 3.4, 2.45, -9.5, 3.8, 2.65, C.Cream, DECOR)
	F:box("ChestDrawer2", -OH + 0.6, 2.0, 2.45, -9.5, 2.4, 2.65, C.Cream, DECOR)
	F:box("AnvilStump", 9.8, FL, 3, 13.8, 2.8, 6, C.Bark)
	F:box("AnvilBase", 10.4, 2.8, 3.6, 13.2, 3.6, 5.4, C.Iron)
	F:box("AnvilTop", 9.6, 3.6, 3.3, 14.2, 4.8, 5.7, C.Iron)
	F:box("AnvilHorn", 14.2, 3.9, 3.9, 15.6, 4.6, 5.1, C.Iron, NOSHADOW)
	F:prop("crate", 17.3, FL, 4.1, 0, { size = 3.2, color = C.Wood, seed = 6 })

	-- interior: pegboard with tools, a glowing forge
	F:box("Pegboard", -9.6, 4, bi - 0.6, 14, 15, bi, C.WoodLight, NOSHADOW)
	local pz0, pz1 = bi - 1.0, bi - 0.6
	F:box("PegWrench", -7.2, 5.5, pz0, -6.0, 12.5, pz1, C.Iron, DECOR)
	F:box("PegWrenchJaw", -8.0, 11.8, pz0, -5.2, 13.2, pz1, C.Iron, DECOR)
	F:box("PegHammer", -1.0, 5.5, pz0, -0.2, 12, pz1, C.Wood, DECOR)
	F:box("PegHammerHead", -2.4, 11, pz0 - 0.1, 1.2, 12.8, pz1, C.Iron, DECOR)
	F:box("PegSaw", 4.4, 7.5, pz0, 10.9, 10.5, pz1, C.StoneLight, DECOR)
	F:box("PegSawHandle", 10.9, 7.2, pz0 - 0.1, 12.4, 10.8, pz1, accent, DECOR)
	F:box("Forge", -wi, FL, 23, -13, 6.4, bi, C.Stone)
	local glow = F:box("ForgeFire", -17.6, 2, 22.85, -14.8, 4.6, 23.2, C.Flame, NEON_DECOR)
	F:box("ForgeHood", -wi, 6.4, 24, -13.4, 10, bi, wall)
	F:box("ForgeFlue", -17.4, 10, 26, -15.4, h, 28, wall, NOSHADOW)
	F:box("StovePipe", -17.1, h, 26.3, -15.7, ridgeTop - 3.0, 27.7, C.Iron, NOSHADOW)
	local pipeCap = F:box("StovePipeCap", -17.6, ridgeTop - 3.0, 25.8, -15.2, ridgeTop - 2.3, 28.2, C.Dark, NOSHADOW)
	chimneySmoke(pipeCap)
	pointLight(glow, 14, 1.6, C.Flame)
	emitter(glow, "Sparks", {
		rate = 3,
		life = { 0.6, 1.1 },
		speed = { 2, 4 },
		spread = 30,
		size = { 0.35, 0 },
		color = { C.FlameCore, C.Flame },
		accel = V(0, -6, 0),
		dir = "Front",
		glow = 1,
	})

	-- outside: a giant wrench leaning on the wall, barrels on the porch
	local wrench = F:sub(CFrame.new(-HW - 2.6, 0, 17) * CFrame.Angles(0, 0, rad(-12)))
	wrench:box("BigWrench", -0.5, 0, -0.8, 0.5, 11, 0.8, C.Iron, NOSHADOW)
	wrench:box("BigWrenchJawA", -0.5, 10.4, -2.4, 0.5, 13.4, -0.8, C.Iron, NOSHADOW)
	wrench:box("BigWrenchJawB", -0.5, 10.4, 0.8, 0.5, 13.4, 2.4, C.Iron, NOSHADOW)
	F:prop("barrel", 19.8, FL, -5.6, 0, { color = C.Wood, seed = 7 })
	F:prop("barrel", 16.4, FL, -6.4, 0, { color = H.tile, seed = 8 })
	F.model.PrimaryPart = plinth
	return F.model, bench
end

--[[
	FishMarket «РЫБНЫЙ РЫНОК» (sells fish): an open timber market hall — six wooden posts on stone
	pedestals, beams with knee braces, a plastered back wall with timber posts and shuttered
	windows (a fish relief between them, the side the bases see), a blue roof with a ridge beam,
	plastered gables and a louvred lantern on the ridge carrying a fish weather vane, the big sign
	standing on the front of the roof, a blue/cream striped awning over the counters. Wooden
	counters with ice and fish, the scales (Scales.SellPromptAttachment) on the front counter
	above a «Продать рыбу» panel, crates of fish, a «СВЕЖАЯ РЫБА» board inside, a hanging lamp,
	a cooler, a barrel and a lifebuoy on the front post.
]]
local function buildFishMarket(hub: any, cf: any): (any, any)
	local F = newFrame(U.model(hub, "FishMarket"), cf, SHOP_SCALE)
	local roof, timber, post, trim = C.RoofBlue, C.WoodDark, C.Wood, C.Cream
	local fishColors = H.fish
	local px = HW - 2.4 -- inner face of the posts
	local plinth = F:box("Plinth", -HW - 1, -0.5, -9, HW + 1, FL - 0.4, D + 1, C.Stone, FLAT)
	F:box("Floor", -HW - 0.4, FL - 0.4, -8.5, HW + 0.4, FL, D + 0.4, C.StoneLight, FLAT)
	F:box("PorchStep", -10, -0.5, -10.4, 10, FL - 0.75, -8.9, C.StoneLight, FLAT)
	local top = 17
	-- posts on stone pedestals, beams, knee braces at the front
	for i, z in { 0, 16, D - 2.4 } do
		for j, sx in { -1, 1 } do
			F:box(`Post{i}_{j}`, sx * px, FL, z - 1.2, sx * HW, top, z + 1.2, post)
			F:box(
				`PostBase{i}_{j}`,
				sx * (px - 0.3),
				FL,
				z - 1.5,
				sx * (HW + 0.3),
				FL + 1.8,
				z + 1.5,
				C.Stone,
				NOSHADOW
			)
		end
	end
	for j, sx in { -1, 1 } do
		F:box(`SideBeam{j}`, sx * (px - 0.2), top - 1.4, -1.5, sx * (HW + 0.2), top + 0.4, D - 0.6, timber)
		F:box(`Knee{j}`, sx * (px - 2.4), top - 3.4, -0.8, sx * px, top - 1.4, 0.8, timber, NOSHADOW)
	end
	F:box("FrontBeam", -HW - 0.2, top - 1.4, -1.5, HW + 0.2, top + 0.4, 1.3, timber)
	F:box("BackBeam", -HW - 0.2, top - 1.4, D - 3.4, HW + 0.2, top + 0.4, D - 0.3, timber)

	-- back wall: plaster on a stone course, timber posts, two shuttered windows, the fish relief
	F:box("BackWall", -px, FL, D - 3.2, px, top - 1.4, D - 0.6, C.Plaster)
	F:box("BackCourse", -px - 0.25, FL - 0.4, D - 0.75, px + 0.25, FL + 2.0, D - 0.35, C.Stone, NOSHADOW)
	for i, x in { -7.8, 7.8 } do
		F:box(`BackStud{i}`, x - 0.7, FL + 2.0, D - 0.85, x + 0.7, top - 1.4, D - 0.3, timber)
	end
	for j, xc in { -14.2, 14.2 } do
		window(F, `BackWin{j}`, "+z", D - 0.6, xc, FL + 4.4, 4.4, 6.4, {
			trim = trim,
			shutter = roof,
			ledge = true,
		})
	end
	local relief = F:sub(CFrame.new(0, 9.6, D - 0.6) * CFrame.Angles(0, math.pi, 0))
	bigFish(relief, 0.48, {
		body = lerpColor(C.Cyan, C.RoofBlue, 0.3),
		head = lerpColor(C.Cyan, C.Cream, 0.3),
		fin = roof,
		lips = C.Pink,
	}, { simple = true, side = -1 })
	local fresh = F:box("FreshBoard", -10, 8.6, D - 3.7, 10, 13.4, D - 3.2, C.Cream, NOSHADOW)
	signText(fresh, Enum.NormalId.Front, "СВЕЖАЯ РЫБА", C.Navy)

	-- blue roof (ridge along X) with plastered gables, a louvred lantern on the ridge
	local cz, hs = (D - 1.5) / 2, (D + 1.5) / 2 -- the beams run from z −1.5 to D
	local ridgeTop = gableRoof(F, "Roof", 0, cz, "x", HW + 0.2, hs, top + 0.4, 11, {
		roof = roof,
		ridge = shade(roof, 0.75),
		eave = timber,
		gable = C.Plaster,
		beam = timber,
		ov = 1.2,
		og = 1.2,
		t = 1.0,
		window = { trim, C.WindowBlue },
	})
	local ly = ridgeTop - 0.4 -- lantern bottom on the ridge beam
	F:box("Lantern", -6, ly - 2, cz - 2.6, 6, ly + 3.0, cz + 2.6, C.Plaster)
	F:box("Louvres", -6.25, ly + 0.6, cz - 2.85, 6.25, ly + 2.0, cz + 2.85, timber, NOSHADOW)
	local lanternTop = gableRoof(F, "LanternRoof", 0, cz, "x", 6, 2.6, ly + 3.0, 2.4, {
		roof = roof,
		ridge = shade(roof, 0.75),
		gables = {},
		ov = 0.9,
		og = 0.6,
		noEaves = true,
	})

	-- the big sign standing on the front of the roof, the striped awning over the counters
	signBoard(F, "Sign", -16, 16, top + 2.4, top + 9.0, -0.6, trim, timber, "РЫБНЫЙ РЫНОК", nil, C.Navy)
	awning(F, "Awning", -HW - 0.8, HW + 0.8, top - 1.5, -1.5, 6, 2.0, 7, roof, trim)

	-- a fish jumping on the lantern, turning on its pole like a weather vane
	F:box("FishPole", -0.4, lanternTop, cz - 0.4, 0.4, lanternTop + 4.6, cz + 0.4, C.Iron, NOSHADOW)
	local vane = CFrame.new(0, lanternTop + 7.2, cz)
	local jumper = F:child("JumpingFish", vane * CFrame.Angles(0, 0, rad(-18)))
	local jumperBody = bigFish(jumper, 0.5, {
		body = lerpColor(C.Cyan, C.RoofBlue, 0.2),
		head = lerpColor(C.Cyan, C.Cream, 0.35),
		fin = roof,
		lips = C.Pink,
	}, { simple = true })
	jumper.model.PrimaryPart = jumperBody
	jumperBody.PivotOffset = jumperBody.CFrame:Inverse() * F:world(vane * CFrame.Angles(rad(90), 0, 0))
	jumper.model:SetAttribute("Spin", 14)

	-- front counter with ice and fish, the «Продать рыбу» panel and the scales (low, so the
	-- counter reads at a glance); side wings and crates of fish close the front
	F:box("Counter", -10, FL, 2.4, 10, 3.6, 5.6, C.Wood)
	local sub = F:box("SubSign", -7.6, 1.35, 2.2, 7.6, 3.4, 2.45, C.Cream, NOSHADOW)
	signText(sub, Enum.NormalId.Front, "Продать рыбу", C.Navy)
	F:box("Ice", -10.3, 3.6, 2.1, 10.3, 4.2, 5.9, H.ice)
	for i, x in { -8, -5, 5, 8 } do
		smallFish(F, x, 4.2, 4.0 + (i % 2) * 0.5, 2.6, fishColors[i])
	end
	local scales = F:box("Scales", -1.8, 4.2, 2.6, 1.8, 5.2, 5.0, C.Iron)
	F:box("ScalesDial", -1.1, 5.2, 3.3, 1.1, 6.6, 4.3, C.Cream)
	F:box("ScalesNeedle", -0.12, 5.5, 3.18, 0.12, 6.4, 3.32, C.Red, DECOR)
	F:box("ScalesPan", -2.2, 6.6, 2.7, 2.2, 6.9, 4.9, C.Gold, NOSHADOW)
	U.new("Attachment", { Name = "SellPromptAttachment", CFrame = CFrame.new(0, -0.7, -2.3) }, scales)
	for i, sx in { -1, 1 } do
		F:box(`WingCounter{i}`, sx * 14, FL, 2.4, sx * px, 3.6, 5.6, C.Wood)
		F:box(`WingIce{i}`, sx * 13.8, 3.6, 2.1, sx * px, 4.2, 5.9, H.ice)
		F:box(`SideCounter{i}`, sx * (px - 2.8), FL, 7, sx * px, 3.6, 28, C.Wood)
		F:box(`SideIce{i}`, sx * (px - 3.0), 3.6, 6.8, sx * px, 4.2, 28.2, H.ice)
		smallFish(F, sx * 17.2, 4.2, 4.0, 2.6, fishColors[i + 3])
		for k = 1, 3 do
			smallFish(F, sx * (px - 1.4), 4.2, 6 + k * 5.5, 2.4, fishColors[(i * 3 + k) % #fishColors + 1])
		end
		F:prop("crate", sx * 12.15, FL, 4.1, 0, { size = 3.4, color = C.Wood, seed = 30 + i })
		smallFish(F, sx * 12.15, FL + 3.45, 4.1, 2.6, fishColors[i + 2])
	end
	local lamp = F:box("CeilingLamp", -1.6, top - 3.2, 13, 1.6, top - 2.0, 16, C.Glow, NEON_DECOR)
	F:box("LampCord", -0.15, top - 2.0, 14.35, 0.15, top + 0.4, 14.65, C.Dark, DECOR)
	pointLight(lamp, 16, 1.3)
	-- just inside the front beam: a rail of fish hung up to dry (left) and two hanging lanterns
	F:box("FishRail", -17, top - 2.2, 2.0, -7, top - 1.8, 2.4, C.Rope, DECOR)
	for k = 1, 3 do
		local x = -15.4 + (k - 1) * 3.6
		F:box(
			`HungFish{k}`,
			x - 0.5,
			top - 5.0 + (k % 2) * 0.4,
			1.95,
			x + 0.5,
			top - 2.0,
			2.45,
			fishColors[k + 2],
			DECOR
		)
	end
	for i, x in { 9, 15 } do
		F:box(`LanternCord{i}`, x - 0.1, top - 3.0, 2.1, x + 0.1, top - 1.4, 2.3, C.Dark, DECOR)
		F:box(`Lantern{i}`, x - 0.6, top - 4.6, 1.6, x + 0.6, top - 3.0, 2.8, C.Glow, NEON_DECOR)
	end

	-- outside: a cooler, a barrel, a lifebuoy hung on the front post
	F:prop("cooler", 18.6, FL, -6, 0, { color = roof, seed = 13 })
	F:prop("barrel", -19.4, FL, -5.6, 0, { color = C.Wood, seed = 14 })
	F:prop("lifebuoy", (px + HW) / 2, 6.6, -1.53, 0, { seed = 15 })
	F.model.PrimaryPart = plinth
	return F.model, scales
end

--------------------------------------------------------------------------------
-- Centre: plaza, the golden fish tower, spawn
--------------------------------------------------------------------------------

local BASIN_R = 23 -- outer face of the tower's basin walls (its corners reach r ≈ 30)

-- Inlay at the tower's feet: a sandstone eight-point star of two squares (half size STAR, one
-- turned 45°) in a dark stone outline STAR_EDGE wide. Its axis points reach r ≈ 42 under the
-- avenue runners, its diagonal points run on as rays to the shop porches and the fun fair.
local STAR, STAR_EDGE = 28, 1.8
local STAR_TIP = (STAR + STAR_EDGE) * sqrt(2) -- outline point on every axis and diagonal
local RAY_W = 6 -- ray width (the dark edges add STAR_EDGE on each side)

--[[
	Round plaza: rows of 8 studs of warm stone out to PLAZA_R and an inlay round the basin: the
	sandstone star in its dark outline, sandstone rays with dark edges from its diagonal points to
	the shop porches and the fun fair arch, and a terracotta ring (r 47..52) crossing under the
	rays and the runners. The avenues' sandstone runners (buildAvenues) start on the star's axis
	points and carry the walk on to every bridge. Each layer stands at least 0.12 above the one
	under it (paving 0.2, ring 0.32, outline 0.44, star 0.56, runner 0.7), so no two colours share
	a plane. 31 parts.
]]
local function buildPlaza(hub: any, G: number)
	local F = newFrame(U.model(hub, "Plaza"), CFrame.new(0, G, 0))
	local rows = {} -- row z0 → half width
	local n = floor(PLAZA_R / 8) + 1
	for z0 = -n * 8, (n - 1) * 8, 8 do
		local zm = abs(z0 + 4)
		local w = floor(sqrt(math.max(0, PLAZA_R * PLAZA_R - zm * zm)) / 4 + 0.5) * 4
		if w > 0 then
			rows[z0] = w
		end
	end
	-- one slab per run of rows of the same width
	local z0 = -n * 8
	while z0 <= (n - 1) * 8 do
		local w = rows[z0]
		local z1 = z0 + 8
		while w and rows[z1] == w do
			z1 += 8
		end
		if w then
			F:box("Paving", -w, -0.3, z0, w, 0.2, z1, H.pave, FLAT)
		end
		z0 = z1
	end
	-- the star: outline squares under sandstone squares (the parts under the basin are hidden)
	for _, layer in { { "StarEdge", STAR + STAR_EDGE, 0.44, H.paveDark }, { "Star", STAR, 0.56, H.walk } } do
		local h, top = layer[2], layer[3]
		for k, yaw in { 0, 45 } do
			local S = newFrame(F.model, F.cf * CFrame.Angles(0, rad(yaw), 0))
			S:box(`{layer[1]}{k}`, -h, top - 0.5, -h, h, top, h, layer[4], FLAT)
		end
	end
	-- rays from the star's diagonal points (each starts inside the point) to the shop porches
	-- (r ≈ 65) and the fun fair arch; the dark edge ends where the fair path starts
	local rayIn, rayOut = STAR * sqrt(2) - 4, PLAZA_R - 1 - STAR_EDGE
	for k = 0, 3 do
		local R = radialFrame(F.model, 45 + k * 90, G)
		local e = RAY_W / 2 + STAR_EDGE
		R:box(`RayEdge{k + 1}`, -e, -0.06, rayIn, e, 0.44, rayOut + STAR_EDGE, H.paveDark, FLAT)
		R:box(`Ray{k + 1}`, -RAY_W / 2, 0.06, rayIn, RAY_W / 2, 0.56, rayOut, H.walk, FLAT)
	end
	-- terracotta ring: one chord per axis and diagonal (the chords overlap in thin wedges at the
	-- inner corners, all one colour)
	local b0, b1 = 47, 52
	local len = 2 * b1 * math.tan(rad(22.5)) + 0.1
	for k = 0, 7 do
		local R = radialFrame(F.model, k * 45, G)
		R:box(`Band{k + 1}`, -len / 2, -0.18, b0, len / 2, 0.32, b1, H.ring, FLAT)
	end
end

--[[
	«Золотая рыбка» tower, the island's landmark and the tallest thing on it (~106 studs, seen
	from every base, pier and bridge): an octagonal sandstone basin with a blue tile band and a
	cream rim round a see-through pool; three stepped sandstone tiers with tile bands and cream
	rims and a pool on top, the water spilling from under every rim down the tier's faces into the
	pool below (foam where it meets the basin); four jets arcing from the basin's corners into the
	pool; a stone spire with slit windows, a cream collar, a glowing gold ring, a verdigris cap and
	a stepped water spout carrying a huge crowned golden fish (tilted nose-up) that spits an arc
	of water and slowly circles about the spout (Spin), so every avenue sees it from all sides.
	Particles (no parts): gold sparkles round the fish, spray from the spout, drops from the
	fish's jet, splashes where the jets land, mist at the basin foam. ~115 parts.
]]
local function buildTower(hub: any, G: number)
	local F = newFrame(U.model(hub, "FishTower"), CFrame.new(0, G + 0.25, 0))
	local stone, rimC, tile = H.stoneWarm, C.Cream, H.tile
	local r1 = BASIN_R
	local r0, half = r1 - 3, 16 -- basin wall inner face, half length of a straight wall
	F:box("BasinFloor", -r0 - 0.6, -0.3, -r0 - 0.6, r0 + 0.6, 0.5, r0 + 0.6, H.basinFloor, FLAT)
	F:box("Water", -r0 - 0.5, 0.5, -r0 - 0.5, r0 + 0.5, 2.6, r0 + 0.5, H.water, WATER)
	-- a piece on each side of the tower (d = axis): a0..a1 along the side, b0..b1 out from the centre
	local function along(
		d: { number },
		a0: number,
		a1: number,
		b0: number,
		b1: number,
		y0: number,
		y1: number,
		name: string,
		c: any,
		ex: { [string]: any }?
	): any
		if d[1] ~= 0 then
			return F:box(name, d[1] * b0, y0, a0, d[1] * b1, y1, a1, c, ex)
		end
		return F:box(name, a0, y0, d[2] * b0, a1, y1, d[2] * b1, c, ex)
	end
	local AXES = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }
	local DIAG = { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } }
	for i, d in AXES do
		along(d, -half, half, r0, r1, -0.3, 3.4, `BasinWall{i}`, stone)
		along(d, -half - 0.4, half + 0.4, r0 - 0.4, r1 + 0.4, 3.4, 4.1, `BasinRim{i}`, rimC)
		-- the band stops 0.12 short of the wall ends (no shared plane with the end faces)
		along(d, -half + 0.12, half - 0.12, r1 - 0.3, r1 + 0.15, 1.1, 2.1, `BasinBand{i}`, tile, NOSHADOW)
	end
	for i, d in DIAG do
		local c0, c1 = half, r0 + 1.2
		F:box(`BasinCorner{i}`, d[1] * c0, -0.3, d[2] * c0, d[1] * c1, 3.4, d[2] * c1, stone)
		F:box(
			`BasinCornerBand{i}`,
			d[1] * (c0 + 0.6),
			1.1,
			d[2] * (c0 + 0.6),
			d[1] * (c1 + 0.15),
			2.1,
			d[2] * (c1 + 0.15),
			tile,
			NOSHADOW
		)
		F:box(
			`BasinCornerRim{i}`,
			d[1] * (c0 - 0.4),
			3.42,
			d[2] * (c0 - 0.4),
			d[1] * (c1 + 0.4),
			4.08,
			d[2] * (c1 + 0.4),
			rimC
		)
	end

	--[[
		Three stepped tiers: half width w, from y0 (the pool top of the tier below) to y1; a band on
		the faces, a rim round the top and a pool on the rim. A narrow stream of water (cw = half
		width) hangs just under the middle of each rim's overhang, from the rim down into the pool
		below; the tier's stone wall and band fill the rest of the face. 4 + 4 parts per tier.
	]]
	local y0 = 0.4
	local poolBelow = 2.6 -- basin water top
	for k, t in
		{
			{ 13, 14, stone, tile, rimC, 3.6 },
			{ 9.6, 12, C.PlasterShade, H.ring, rimC, 2.6 },
			{ 6.4, 10, stone, tile, rimC, 1.8 },
		}
	do
		local w, h, wall, band, rim, cw = t[1], t[2], t[3], t[4], t[5], t[6]
		local y1 = y0 + h
		F:box(`Tier{k}`, -w, y0, -w, w, y1, w, wall)
		F:box(`Tier{k}Band`, -w - 0.3, y0 + h * 0.42, -w - 0.3, w + 0.3, y0 + h * 0.42 + 1.6, w + 0.3, band, NOSHADOW)
		F:box(`Tier{k}Rim`, -w - 0.6, y1 - 0.6, -w - 0.6, w + 0.6, y1 + 0.6, w + 0.6, rim)
		F:box(`Tier{k}Pool`, -w + 0.6, y1 + 0.6, -w + 0.6, w - 0.6, y1 + 1.0, w - 0.6, H.water, FLOW)
		for i, d in AXES do
			along(d, -cw, cw, w + 0.05, w + 0.55, poolBelow - 0.2, y1 - 0.6, `Tier{k}Curtain{i}`, H.cascade, FLOW)
			if k == 1 then
				-- the foam's bottom stays 0.12 above the curtain's (no shared plane in the pool)
				local foam = along(d, -cw - 0.6, cw + 0.6, w - 0.4, w + 2.2, 2.52, 3.3, `Foam{i}`, C.Foam, DECOR)
				emitter(foam, "Mist", {
					rate = 3,
					life = { 1.2, 1.8 },
					speed = { 1, 2 },
					spread = 40,
					size = { 1.4, 2.8 },
					fade = { 0.45, 1 },
					accel = V(0, 1.5, 0),
					texture = PUFF,
				})
			end
		end
		poolBelow = y1 + 1.0
		y0 = poolBelow
	end

	--[[
		Four jets arc from the basin's corners into the pool beside the first tier: a chain of
		overlapping water cubes (u = distance along the diagonal from the centre) rising out of
		the corner rim and landing in a white splash in the basin water (top 2.6).
	]]
	for i, d in DIAG do
		for k, p in
			{ -- u, y bottom, y top, size, foam
				{ 18.6, 3.9, 5.7, 1.8 },
				{ 17.2, 5.4, 7.2, 1.8 },
				{ 15.7, 5.7, 7.5, 1.8 },
				{ 14.5, 4.0, 5.8, 1.8 },
				{ 14.4, 2.3, 4.1, 2.4, true },
			}
		do
			local x, z, w = d[1] * p[1], d[2] * p[1], p[4] / 2
			local jet = F:box(
				if p[5] then `CornerSplash{i}` else `CornerJet{i}_{k}`,
				x - w,
				p[2],
				z - w,
				x + w,
				p[3],
				z + w,
				if p[5] then C.Foam else H.waterLight,
				FLOW
			)
			if p[5] then
				emitter(jet, "Splash", {
					rate = 4,
					life = { 0.5, 0.8 },
					speed = { 3, 5 },
					spread = 35,
					size = { 0.7, 0.2 },
					fade = { 0.1, 0.8 },
					color = { C.Foam, H.waterLight },
					accel = V(0, -24, 0),
				})
			end
		end
	end

	--[[
		Spire on the top pool (39.4): a stone foot, a sandstone shaft with a tile band and a slit
		window on every side, a cream collar, a plastered shaft with a tile band and the glowing
		gold ring, then the verdigris cap.
	]]
	local base = y0 -- 39.4
	F:box("SpireFoot", -5.6, base - 0.4, -5.6, 5.6, base + 1.6, 5.6, C.Stone)
	F:box("Shaft1", -4.8, base + 1.6, -4.8, 4.8, base + 15.6, 4.8, stone)
	F:box("ShaftStripe", -5.05, base + 4.2, -5.05, 5.05, base + 5.6, 5.05, tile, NOSHADOW)
	for i, d in AXES do
		along(d, -0.8, 0.8, 4.7, 4.95, base + 8.0, base + 12.6, `SpireWindow{i}`, C.Navy, NOSHADOW)
	end
	F:box("Collar", -5.6, base + 15.6, -5.6, 5.6, base + 17.2, 5.6, rimC)
	F:box("Shaft2", -4, base + 17.2, -4, 4, base + 28.6, 4, C.Plaster)
	F:box("ShaftBand", -4.25, base + 19.6, -4.25, 4.25, base + 21.2, 4.25, tile, NOSHADOW)
	local ring = F:box("GoldRing", -4.3, base + 24, -4.3, 4.3, base + 25.4, 4.3, C.GoldLight, NEON)
	pointLight(ring, 16, 1.4, C.Glow)

	-- the cap and the stepped spout that carries the fish; spray bubbles out round it
	local top = base + 28.6 -- 68
	F:box("Cap", -5.2, top, -5.2, 5.2, top + 1.4, 5.2, H.verdigris)
	local spout = F:box("Spout1", -2.4, top + 1.4, -2.4, 2.4, top + 5, 2.4, H.waterLight, FLOW)
	F:box("Spout2", -1.6, top + 5, -1.6, 1.6, top + 9, 1.6, H.waterLight, FLOW)
	emitter(spout, "Spray", {
		rate = 16,
		life = { 1.1, 1.5 },
		speed = { 9, 13 },
		spread = 55,
		size = { 0.9, 0.3 },
		fade = { 0.05, 0.7 },
		color = { C.Foam, H.waterLight },
		accel = V(0, -26, 0),
		glow = 0.3,
	})

	-- «Золотая рыбка»: tilted nose-up 26°; as it turns, its lowest point stays ~6 studs above
	-- the cap (the spout reaches into its belly) and its tail sweeps clear of the spire
	local s, fishY = 1.7, top + 19.5
	local fishCf = CFrame.new(0, fishY, 0) * CFrame.Angles(0, rad(45), 0)
	local fish = F:child("GoldenFish", fishCf * CFrame.Angles(0, 0, rad(-26)))
	local body = bigFish(fish, s, {
		body = H.gold,
		head = H.goldLight,
		belly = H.goldBelly,
		fin = H.goldFin,
		lips = lerpColor(C.Orange, C.Red, 0.3),
		spots = H.goldLight,
	}, { crown = true, extra = { Reflectance = 0.1 } })
	emitter(body, "Sparkles", {
		rate = 6,
		life = { 1.2, 2.0 },
		speed = { 1.5, 3 },
		spread = 180,
		size = { 1.1, 0 },
		fade = { 0, 0.4 },
		color = { C.GoldLight, C.Cream },
		accel = V(0, 1.5, 0),
		glow = 1,
		drag = 1,
	})
	-- a water jet out of its mouth: a chain of overlapping cubes arcing up from the lips (part of
	-- the fish model, so it turns with it); drops fall from its end
	local jetFrame = newFrame(fish.model, F.cf * fishCf)
	local mouth = jetFrame.cf:PointToObjectSpace(fish.cf * V(-13.9 * s, -1.2 * s, 0))
	local last
	for k, p in
		{
			{ -0.5, 0.5, 1.8 },
			{ -1.9, 1.8, 1.7 },
			{ -3.4, 2.7, 1.6 },
			{ -5.0, 3.0, 1.5 },
			{ -6.5, 2.6, 1.4 },
			{ -7.7, 1.6, 1.3 },
		}
	do
		local x, yy, w = mouth.X + p[1], mouth.Y + p[2], p[3]
		last =
			jetFrame:box(`MouthJet{k}`, x - w / 2, yy - w / 2, -w / 2, x + w / 2, yy + w / 2, w / 2, H.waterLight, FLOW)
	end
	emitter(last, "Drops", {
		rate = 8,
		life = { 0.9, 1.3 },
		speed = { 2, 4 },
		spread = 25,
		size = { 0.6, 0.2 },
		fade = { 0.1, 0.8 },
		color = { C.Foam, H.waterLight },
		accel = V(0, -30, 0),
		dir = "Bottom",
	})
	-- the golden fish slowly circles above the spout (AmbientController turns Models with a Spin
	-- attribute about their pivot's LookVector: here the vertical spout axis)
	fish.model.PrimaryPart = body
	body.PivotOffset = body.CFrame:Inverse() * (F.cf * CFrame.new(0, fishY, 0) * CFrame.Angles(rad(90), 0, 0))
	fish.model:SetAttribute("Spin", 10)
end

-- HubSpawn: players without a free base appear on the θ 180 avenue, 100 studs out, facing the
-- tower (+Z): the whole tower with the golden fish fills the middle of the first view, the
-- Workshop and the fun fair stand left and right. The frame stands 0.15 above the avenue runner;
-- gold glints rise from the pad.
local SPAWN_Z = -100

local function buildSpawn(hub: any, G: number)
	local z = SPAWN_Z
	local F = newFrame(U.model(hub, "SpawnPad"), CFrame.new(0, G, z))
	local frame = F:box("SpawnFrame", -5.2, -0.2, -5.2, 5.2, 0.85, 5.2, C.StoneLight, FLAT)
	emitter(frame, "Glints", {
		rate = 3,
		life = { 1.5, 2.2 },
		speed = { 2, 3 },
		spread = 15,
		size = { 0.8, 0 },
		color = { C.GoldLight, C.Cream },
		glow = 1,
	})
	for i, d in { { 1, 1 }, { -1, 1 }, { 1, -1 }, { -1, -1 } } do
		F:box(
			`SpawnLight{i}`,
			d[1] * 5.2 - 0.6,
			0.65,
			d[2] * 5.2 - 0.6,
			d[1] * 5.2 + 0.6,
			1.25,
			d[2] * 5.2 + 0.6,
			C.Glow,
			NEON
		)
	end
	U.new("SpawnLocation", {
		Name = "HubSpawn",
		Size = V(8, 0.8, 8),
		CFrame = CFrame.new(0, G + 0.6, z) * CFrame.Angles(0, math.pi, 0), -- the part's −Z faces +Z
		Anchored = true,
		Neutral = true,
		Duration = 0, -- no ForceField
		Enabled = true,
		AllowTeamChangeOnTouch = false,
		Color = lerpColor(H.walk, C.Cream, 0.4),
		Material = Mat.SmoothPlastic,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		CastShadow = false,
		CanTouch = true,
	}, hub)
	U.partCount += 1
end

--[[
	A ring of benches (facing the tower) and lamps round the basin, alternating every 45° and set
	22.5° off the avenues and the shop diagonals: the walkways from the tower and HubSpawn to every
	bridge and every counter stay clear. Wooden flower planters stand on the plaza rim on every
	other base lane (the flower gardens carry all eight lanes on outwards).
]]
local function buildPlazaFurniture(hub: any, G: number)
	local m = U.model(hub, "PlazaFurniture")
	for k = 0, 3 do
		local a = 22.5 + k * 90
		Props.bench(m, U.polarCFrame(a, 35, G + 0.2), { length = 8, color = C.Wood, seed = 40 + k })
		streetLamp(m, U.polarCFrame(a + 45, 36, G + 0.2), 10, C.Iron, true)
	end
	-- wooden planters: a box with a dark rim, a green cushion and two clumps of flowers (5 parts)
	for k = 1, 7, 2 do
		local P = newFrame(U.model(m, "Planter"), U.polarCFrame(22.5 + k * 45, PLAZA_R - 6, G + 0.2))
		local box = P:box("Box", -2.8, -0.2, -2.8, 2.8, 2.4, 2.8, C.Wood)
		P:box("Rim", -3.1, 2.3, -3.1, 3.1, 2.8, 3.1, C.WoodDark, NOSHADOW)
		P:box("Greens", -2.3, 2.6, -2.3, 2.3, 3.6, 2.3, C.Leaf1, DECOR)
		for j, d in { -1, 1 } do
			local col = C.Flowers[(k + j * 3) % #C.Flowers + 1]
			P:box(`Bloom{j}`, d * 1.9 - 1.1, 3.2, d * 0.6 - 1.1, d * 1.9 + 1.1, 4.5, d * 0.6 + 1.1, col, DECOR)
		end
		P.model.PrimaryPart = box
	end
end

--------------------------------------------------------------------------------
-- Avenues (θ = 0/90/180/270): paving, lamps with bunting, gates, palms
--------------------------------------------------------------------------------

local AVENUE_START = PLAZA_R - 4

-- per avenue (θ 0/90/180/270): the district colour of its bridge and gateway (Promenade.Themes)
-- for the gate's band and topper, and the topper after the gateway's theme
local AVENUE_TOPPER = { [0] = "pinwheel", [90] = "tulip", [180] = "fish", [270] = "lantern" }

-- Theme topper standing on a gate pillar's cap at (x, y, z), facing the bridge and the plaza: a
-- pinwheel, a giant tulip, a golden fish (head towards the avenue: dir = −1 | 1 along X) or a
-- lantern. 3 parts.
local function gateTopper(m: any, kind: string, x: number, y: number, z: number, dir: number, accent: any)
	if kind == "pinwheel" then
		m:box("PinStick", x - 0.3, y, z - 0.3, x + 0.3, y + 3.4, z + 0.3, C.Cream, DECOR)
		m:box("PinBladeX", x - 2.7, y + 3.75, z - 0.35, x + 2.7, y + 5.05, z + 0.35, accent, DECOR)
		m:box("PinBladeY", x - 0.65, y + 1.7, z - 0.45, x + 0.65, y + 7.1, z + 0.45, C.Cream, DECOR)
	elseif kind == "tulip" then
		m:box("TulipStem", x - 0.35, y, z - 0.35, x + 0.35, y + 3.8, z + 0.35, C.Leaf2, DECOR)
		m:box("TulipLeaf", x - 1.4, y + 1.2, z - 0.5, x + 1.4, y + 1.8, z + 0.5, C.Leaf3, DECOR)
		m:box("TulipBloom", x - 1.3, y + 3.6, z - 1.3, x + 1.3, y + 6.4, z + 1.3, accent, DECOR)
	elseif kind == "fish" then
		m:box("FishBody", x - 1.9, y, z - 0.6, x + 1.9, y + 2.4, z + 0.6, H.gold, DECOR)
		local t0, t1 = x - dir * 1.8, x - dir * 3.1
		m:box("FishTail", math.min(t0, t1), y - 0.2, z - 0.45, math.max(t0, t1), y + 2.6, z + 0.45, H.goldFin, DECOR)
		local e = x + dir * 1.2
		m:box("FishEye", e - 0.3, y + 1.2, z - 0.7, e + 0.3, y + 1.8, z + 0.7, C.Navy, DECOR)
	else -- lantern
		m:box("LanternBase", x - 0.9, y, z - 0.9, x + 0.9, y + 0.6, z + 0.9, C.Iron, DECOR)
		m:box("LanternGlow", x - 0.7, y + 0.6, z - 0.7, x + 0.7, y + 2.8, z + 0.7, C.Glow, NEON_DECOR)
		m:box("LanternCap", x - 1.1, y + 2.8, z - 1.1, x + 1.1, y + 3.5, z + 1.1, accent, DECOR)
	end
end

-- Welcome gate over an avenue at radial distance z: pale stone pillars on dark stone feet with a
-- band in the district colour, stone caps with theme toppers, a timber beam and a dark board
-- resting on it: «ОСТРОВ РЫБАКОВ» for visitors coming off the bridge, «ХОРОШЕГО КЛЁВА!» for
-- players heading back to their bases. Low (board top ≈ 22 above the avenue, 12 clear under the
-- beam): from r ≥ 180 on the bridge the whole golden fish shows above it. 17 parts.
local function welcomeGate(F: any, z: number, accent: any, topper: string)
	local m = F:child("WelcomeGate")
	for i, sx in { -1, 1 } do
		m:box(`GateBase{i}`, sx * 14.4, -0.3, z - 2.6, sx * 20.4, 2.2, z + 2.6, C.Stone)
		m:box(`GatePillar{i}`, sx * 15.4, 2.2, z - 2, sx * 19.4, 22, z + 2, C.StoneLight)
		m:box(`GateBand{i}`, sx * 15.2, 17.6, z - 2.2, sx * 19.6, 19.0, z + 2.2, accent, NOSHADOW)
		m:box(`GateCap{i}`, sx * 14.8, 22, z - 2.6, sx * 20, 23.4, z + 2.6, C.Stone)
		gateTopper(m, topper, sx * 17.4, 23.4, z, -sx, accent)
	end
	m:box("GateBeam", -15.4, 12, z - 1.2, 15.4, 13.6, z + 1.2, C.WoodDark)
	-- the board's front (−Z) faces the tower, its back the bridge
	signBoard(
		m,
		"GateSign",
		-13,
		13,
		14.4,
		21,
		z,
		C.WoodDark,
		C.Wood,
		"ХОРОШЕГО КЛЁВА!",
		"ОСТРОВ РЫБАКОВ",
		C.Cream,
		C.Dark
	)
end

local function buildAvenues(hub: any, cfg: any, G: number)
	local root = U.model(hub, "Avenues")
	local endZ, gateZ = L.avenueEnd, L.gate
	local flowers = C.Flowers
	for i, angle in cfg.BridgeAngles do
		local F = radialFrame(U.model(root, `Avenue{i}`), angle, G)
		local theme = Promenade.Themes[angle % 360]
		local accent = if theme then theme.color else C.Orange
		-- paving: cobbles, a sandstone runner from the plaza star to the bridge, stone kerbs; each
		-- layer stands 0.15+ above the one under it (no shimmer from the bridges)
		F:box("Bricks", -11, -0.3, AVENUE_START, 11, 0.35, endZ, H.street, FLAT)
		-- the runner starts on the plaza star's axis point (over its sandstone, see buildPlaza)
		-- and stops just short of the bridge deck (its top would sit 0.1 above the planks)
		F:box("Runner", -4, 0.1, STAR_TIP - 4, 4, 0.7, endZ - 1.2, H.walk, FLAT)
		for j, sx in { -1, 1 } do
			F:box(`Kerb{j}`, sx * 11, -0.3, AVENUE_START + 4, sx * 12.4, 0.8, endZ, H.kerb, FLAT)
		end
		-- two pairs of lamps, bunting across the avenue between the inner pair
		for k, z in { 86, 118 } do
			local tops = {}
			for j, sx in { -1, 1 } do
				streetLamp(F.model, F:at(sx * 14.2, 0, z), 11, C.Iron)
				tops[j] = F:point(sx * 14.2, 10.2, z)
			end
			if k == 1 then
				Props.bunting(F.model, tops[1], tops[2], { seed = i * 7 + k, sag = 1.8, count = 3 })
			end
		end
		-- hedge rows outside the kerbs, between the lamps, each with a clump of flowers per
		-- ~10 studs (two tones, two heights)
		for j, sx in { -1, 1 } do
			for k, zz in { { 70, 82 }, { 90, 114 }, { 122, 134 } } do
				F:box(`Hedge{j}_{k}`, sx * 15, -0.3, zz[1], sx * 17.6, 2.4, zz[2], C.Leaf1)
				local n = math.max(1, floor((zz[2] - zz[1]) / 10 + 0.5))
				local step = (zz[2] - zz[1]) / n
				for c = 1, n do
					local z = zz[1] + (c - 0.5) * step
					local bloom = flowers[(i * 2 + j + k + c) % #flowers + 1]
					local top = 3.4 + (c % 2) * 0.4
					F:box(`HedgeBloom{j}_{k}_{c}`, sx * 15.3, 2.1, z - 1.5, sx * 17.3, top, z + 1.5, bloom, DECOR)
				end
			end
		end
		welcomeGate(F, gateZ, accent, AVENUE_TOPPER[angle % 360] or "pinwheel")
		-- (the tall palms framing the bridge landing come with the beach: buildLandingPalms)
	end
end

--------------------------------------------------------------------------------
-- Fun fair (θ 225): entrance arch, food stalls, Ferris wheel
--------------------------------------------------------------------------------

--[[
	Wooden food stall facing local −Z: a stone base, a plank back wall, light wooden sides, dark
	corner posts, a counter with a stripe in the stall's colour, a canvas roof (wedges) with a ridge
	and a valance in that colour, a cream sign board at the eave and a treat on the ridge
	("icecream" | "popcorn" | "lemonade"). ~20 parts.
]]
local function kiosk(parent: any, cf: any, name: string, text: string, main: any, product: string)
	local F = newFrame(U.model(parent, name), cf)
	local base = F:box("Base", -6.2, -0.3, -4.4, 6.2, 0.5, 4.2, C.Stone, FLAT)
	F:box("Counter", -5.6, 0.5, -3.8, 5.6, 3.8, -1.8, C.Wood)
	F:box("CounterTop", -6, 3.8, -4.3, 6, 4.3, -1.4, C.WoodLight)
	F:box("CounterStripe", -4.6, 2.0, -3.92, 4.6, 2.7, -3.7, main, NOSHADOW)
	F:box("Back", -5.6, 0.5, 2.4, 5.6, 9.2, 3.6, C.Plank)
	F:box("SideL", -5.6, 0.5, -1.8, -4.6, 3.8, 2.4, C.WoodLight)
	F:box("SideR", 4.6, 0.5, -1.8, 5.6, 3.8, 2.4, C.WoodLight)
	F:box("PostL", -5.75, 0.5, -3.95, -4.6, 9.2, -2.8, C.WoodDark)
	F:box("PostR", 4.6, 0.5, -3.95, 5.75, 9.2, -2.8, C.WoodDark)
	local ridgeTop = gableRoof(F, "Roof", 0, -0.1, "x", 5.6, 3.7, 9.2, 3.0, {
		roof = C.Canvas,
		ridge = main,
		gables = {},
		ov = 1.0,
		og = 0.6,
		noEaves = true,
	})
	F:box("Valance", -6.4, 8.2, -4.95, 6.4, 9.3, -4.55, main, NOSHADOW)
	local sign = F:box("Sign", -4.6, 9.3, -5.3, 4.6, 11.9, -4.7, C.Cream)
	F:box("SignFrame", -5.0, 9.2, -5.0, 5.0, 12.3, -4.6, C.WoodDark)
	signText(sign, Enum.NormalId.Front, text, shade(main, 0.7))
	local y = ridgeTop - 0.1
	if product == "icecream" then
		F:box("Cone1", -0.8, y, -0.8, 0.8, y + 1.2, 0.8, C.Straw)
		F:box("Cone2", -1.4, y + 1.2, -1.4, 1.4, y + 2.6, 1.4, C.Straw)
		F:box("Scoop1", -2.0, y + 2.6, -2.0, 2.0, y + 4.4, 2.0, C.Pink)
		F:box("Scoop2", -1.6, y + 4.4, -1.6, 1.6, y + 5.8, 1.6, C.Cream)
		F:box("Cherry", -0.5, y + 5.8, -0.5, 0.5, y + 6.8, 0.5, C.Red, DECOR)
	elseif product == "popcorn" then
		F:box("Bucket", -1.8, y, -1.8, 1.8, y + 4.0, 1.8, C.Red)
		F:box("BucketStripe", -0.45, y + 0.1, -1.9, 0.45, y + 4.1, 1.9, C.Cream, NOSHADOW)
		for k, p in { { -0.9, 4.6, -0.6 }, { 0.8, 4.8, 0.5 }, { 0.0, 5.5, 0.0 } } do
			local w = if k == 3 then 1.4 else 1.7
			F:box(
				`Popcorn{k}`,
				p[1] - w / 2,
				y + p[2] - w / 2,
				p[3] - w / 2,
				p[1] + w / 2,
				y + p[2] + w / 2,
				p[3] + w / 2,
				if k == 2 then C.StrawLight else C.Cream,
				DECOR
			)
		end
	else -- lemonade
		F:box("Cup", -1.7, y, -1.7, 1.7, y + 4.4, 1.7, C.Yellow)
		F:box("CupBand", -1.8, y + 1.4, -1.8, 1.8, y + 2.3, 1.8, C.Cream, NOSHADOW)
		F:box("Lid", -2.0, y + 4.4, -2.0, 2.0, y + 5.0, 2.0, C.Cream)
		F:box("Straw", 0.4, y + 5.0, -0.2, 0.8, y + 8.0, 0.2, C.Red, DECOR)
		F:box("Lemon", 1.5, y + 3.4, -0.8, 2.2, y + 5.3, 0.8, C.Lime, DECOR)
	end
	F.model.PrimaryPart = base
end

-- Entrance arch of the fun fair over its path at radial distance z: white posts on stone feet
-- with a teal band, teal caps with little pennants, a timber beam and a board «АТТРАКЦИОНЫ» on
-- both faces resting on it. 13 parts.
local function fairArch(F: any, z: number)
	local m = F:child("FairArch")
	for i, sx in { -1, 1 } do
		m:box(`ArchFoot{i}`, sx * 7.6, -0.3, z - 1.9, sx * 11.6, 1.6, z + 1.9, C.Stone)
		m:box(`ArchPost{i}`, sx * 8.2, 1.6, z - 1.3, sx * 11.0, 19, z + 1.3, C.White)
		m:box(`ArchBand{i}`, sx * 8.0, 12.6, z - 1.5, sx * 11.2, 13.8, z + 1.5, H.fair, NOSHADOW)
		m:box(`ArchCap{i}`, sx * 7.8, 19, z - 1.7, sx * 11.4, 20.2, z + 1.7, H.fair)
		local px = sx * 9.6
		m:box(`Pennant{i}`, px - 0.2, 20.2, z - 0.2, px + 0.2, 24.6, z + 0.2, C.WoodDark, DECOR)
		local f0, f1 = px - sx * 0.2, px - sx * 3.0
		m:box(`PennantFlag{i}`, math.min(f0, f1), 22.4, z - 0.1, math.max(f0, f1), 24.4, z + 0.1, C.Red, DECOR)
	end
	m:box("ArchBeam", -8.2, 14.4, z - 1.0, 8.2, 15.6, z + 1.0, C.WoodDark)
	signBoard(
		m,
		"ArchSign",
		-6.4,
		6.4,
		16.4,
		19.6,
		z,
		C.Cream,
		C.WoodDark,
		"АТТРАКЦИОНЫ",
		"АТТРАКЦИОНЫ",
		shade(H.fair, 0.6)
	)
end

-- The Ferris wheel (Props.ferrisWheel) in the fair's colours: a white frame, its rim in pairs
-- of white and teal segments, cream and teal gondolas, teal hub, braces and ticket booth roof.
local function calmWheel(wheel: any)
	for _, p in wheel:GetDescendants() do
		if p:IsA("BasePart") then
			local n = p.Name
			local k = tonumber(string.match(n, "^Rim(%d+)_"))
			if k then
				p.Color = if floor(k / 2) % 2 == 0 then C.White else H.fair
			elseif n == "Cabin" then
				local g = tonumber(string.match(p.Parent.Name, "_(%d+)$")) or 1
				p.Color = if g % 2 == 0 then H.fair else C.Cream
			elseif string.match(n, "^Cross") or string.match(n, "^Brace") or n == "Hub" or n == "BoothRoof" then
				p.Color = shade(H.fair, 0.9)
			end
		end
	end
end

--[[
	Fun fair on the θ 225 diagonal (off every base's line of sight to the tower): an entrance arch
	on the plaza rim, a path lined by three food stalls with treats on their roofs and a picnic
	table under a parasol, and a big Ferris wheel at its end (its spinning parts never collide,
	see buildHub).
]]
local function buildFair(hub: any, G: number)
	local m = U.model(hub, "FunFair")
	local F = radialFrame(m, 225, G)
	local wheelR, scale = 108, 1.45
	local deckFront = wheelR - 8 * scale
	F:box("Path", -6, -0.3, PLAZA_R - 1, 6, 0.35, deckFront + 1, H.walk, FLAT)
	for j, sx in { -1, 1 } do
		F:box(`PathEdge{j}`, sx * 6, -0.3, PLAZA_R - 1, sx * 7.4, 0.5, deckFront + 1, H.paveDark, FLAT)
	end
	fairArch(F, PLAZA_R - 3)
	-- the stalls face the path from both sides; their roofs end short of the wheel's base
	kiosk(m, F:at(-15.5, 0, 74, -90), "IceCreamKiosk", "МОРОЖЕНОЕ", C.Pink, "icecream")
	kiosk(m, F:at(15.5, 0, 74, 90), "PopcornKiosk", "ПОПКОРН", C.Red, "popcorn")
	kiosk(m, F:at(15.5, 0, 89, 90), "LemonadeKiosk", "ЛИМОНАД", C.Yellow, "lemonade")
	Props.picnicTable(m, F:at(-15.5, 0, 89, 90), { seed = 61, cloth = C.Red })
	Props.parasol(m, F:at(-15.7, 0, 89.1), { seed = 63, color = H.fair })
	local wheel = Props.ferrisWheel(m, U.polarCFrame(225, wheelR, G), { scale = scale, deck = C.Plank, seed = 1 })
	calmWheel(wheel)
end

--------------------------------------------------------------------------------
-- Second ring (r ≈ 134): game booth and bandstand behind the shops, facing the lagoon
--------------------------------------------------------------------------------

--[[
	«ИГРЫ» game booth (frame origin = booth centre on the ground, −Z = players): plank back wall,
	light wooden sides, dark corner posts, a counter with a red stripe, a canvas roof with a red
	ridge and eave boards, a string of lights under the front eave, the sign standing on the
	ridge, two shelves of plush fish prizes and a pyramid of cans to knock down. ~38 parts.
]]
local function buildArcade(hub: any, cf: any)
	local F = newFrame(U.model(hub, "GameBooth"), cf)
	local accent = C.Red
	local base = F:box("Base", -11.5, -0.3, -9, 11.5, 0.5, 7, C.Stone, FLAT)
	F:box("BackWall", -10, 0.5, 4.6, 10, 11, 6, C.Plank)
	for i, sx in { -1, 1 } do
		F:box(`Side{i}`, sx * 8.6, 0.5, -6, sx * 10, 11, 4.6, C.WoodLight)
		F:box(`Post{i}`, sx * 8.4, 0.5, -6.4, sx * 10.2, 11.2, -4.8, C.WoodDark)
	end
	F:box("Counter", -8.4, 0.5, -6, 8.4, 4, -4, C.Wood)
	F:box("CounterTop", -8.8, 4, -6.3, 8.8, 4.5, -3.7, C.WoodLight)
	F:box("CounterStripe", -8.2, 1.8, -6.15, 8.2, 2.6, -5.9, accent, NOSHADOW)
	local ridgeTop = gableRoof(F, "Roof", 0, -0.2, "x", 10.2, 6.2, 11.2, 4.2, {
		roof = C.Canvas,
		ridge = accent,
		eave = accent,
		gables = {},
		ov = 1.2,
		og = 1.0,
	})
	local bulbs = F:box("Bulbs", -10.6, 9.9, -7.2, 10.6, 10.4, -6.8, C.Glow, NEON_DECOR)
	pointLight(bulbs, 16, 1.2)
	signBoard(F, "Sign", -6, 6, ridgeTop + 0.6, ridgeTop + 5, -0.2, C.Cream, C.WoodDark, "ИГРЫ", "ИГРЫ", accent)
	-- prizes: plush fish on two shelves
	local prizes = { H.fish[4], C.Orange, C.Lime, C.Purple, C.Pink }
	for k, y in { 5.2, 8.4 } do
		F:box(`Shelf{k}`, -7.6, y - 0.5, 3.4, 7.6, y, 4.6, C.WoodLight, NOSHADOW)
		local xs = if k == 1 then { -5, 0, 5 } else { -2.6, 2.6 }
		for j, x in xs do
			smallFish(F, x, y, 4.0, 3.4, prizes[(k * 3 + j) % #prizes + 1])
		end
	end
	-- the game: a stand with a pyramid of cans
	F:box("CanStand", -2.4, 0.5, -0.8, 2.4, 3.6, 0.8, C.Cream)
	local cans = { { -1.3, 0 }, { 0, 0 }, { 1.3, 0 }, { -0.65, 1 }, { 0.65, 1 }, { 0, 2 } }
	for k, c in cans do
		local y0 = 3.6 + c[2] * 1.4
		F:column(`Can{k}`, 1.1, c[1], 0, y0, y0 + 1.4, ({ accent, C.Iron, H.fair })[k % 3 + 1], NOSHADOW)
	end
	F.model.PrimaryPart = base
end

--[[
	«СЦЕНА» village bandstand (frame origin = front centre of the platform, −Z = audience): a plank
	platform with a dark trim and stone steps, a light wooden back wall, dark posts and header, deep
	red curtains under a cream valance, a red roof (wedges) with the sign standing on its front, a
	drum, a cymbal, a microphone and an amp, two speakers, two spotlight poles and two benches.
	~36 parts.
]]
local function buildStage(hub: any, cf: any)
	local F = newFrame(U.model(hub, "Stage"), cf)
	local timber = C.WoodDark
	local deck = F:box("Platform", -10, -0.3, 0, 10, 2.4, 11, C.Plank)
	F:box("PlatformTrim", -10.15, 0.6, -0.15, 10.15, 1.6, 0.1, timber, NOSHADOW)
	F:box("Steps", -3.5, -0.3, -2.4, 3.5, 1.2, 0, C.StoneLight)
	F:box("BackWall", -10, 2.4, 9.8, 10, 15, 11, C.WoodLight)
	for i, sx in { -1, 1 } do
		F:box(`Leg{i}`, sx * 8.4, 2.4, -0.4, sx * 10.2, 15, 1.6, timber)
		F:box(`Curtain{i}`, sx * 6, 2.4, 0.4, sx * 8.4, 13, 1.4, H.curtain, NOSHADOW)
	end
	F:box("Header", -10.2, 13, -0.4, 10.2, 15, 1.6, timber)
	F:box("Valance", -8.4, 11.4, -0.2, 8.4, 13, 1.3, C.Cream, NOSHADOW)
	gableRoof(F, "Roof", 0, 5.5, "x", 10.2, 5.9, 15, 4.6, {
		roof = C.RoofRed,
		eave = C.Cream,
		gables = {},
		ov = 1.2,
		og = 0.8,
	})
	signBoard(F, "Sign", -6, 6, 16.4, 20.2, -0.2, C.Cream, timber, "СЦЕНА", nil, H.curtain)
	-- the band's kit
	F:column("Drum", 3.2, -4.4, 6.6, 2.4, 4.6, H.tile)
	F:box("DrumRim", -6.1, 4.6, 4.9, -2.7, 4.9, 8.3, C.Cream, NOSHADOW)
	F:column("CymbalStand", 0.3, -1.2, 7.6, 2.4, 7, C.Iron, DECOR)
	F:box("Cymbal", -2.4, 7, 6.4, 0, 7.25, 8.8, C.Gold, DECOR)
	F:column("MicStand", 0.3, 0.6, 3, 2.4, 7.4, C.Iron, DECOR)
	F:box("Mic", 0.2, 7.4, 2.6, 1, 8.4, 3.4, C.Dark, DECOR)
	F:box("Amp", 3.6, 2.4, 5.8, 7.2, 6.2, 8.6, C.Wood)
	F:box("AmpGrille", 3.9, 3, 5.65, 6.9, 5.6, 5.85, C.Dark, NOSHADOW)
	-- speakers beside the stage, spotlights on poles in front
	for i, sx in { -1, 1 } do
		F:box(`Speaker{i}`, sx * 10.6, -0.3, 2, sx * 13.8, 8.6, 5.6, H.speaker)
		F:box(`Woofer{i}`, sx * 11.2, 3, 1.85, sx * 13.2, 6.4, 2.05, C.Stone, NOSHADOW)
		F:column(`SpotPole{i}`, 0.8, sx * 12.2, -5, -0.3, 13, C.Iron, NOSHADOW)
		local spot = F:box(`Spot{i}`, sx * 12.2 - 1.1, 13, -6.1, sx * 12.2 + 1.1, 14.8, -3.9, C.Glow, NEON_DECOR)
		if i == 1 then
			pointLight(spot, 16, 1.4)
		end
	end
	-- benches for the audience
	for k, z in { -8, -12 } do
		for j, sx in { -1, 1 } do
			F:box(
				`Seat{k}_{j}`,
				sx * 1.4,
				-0.3,
				z - 0.9,
				sx * 8.6,
				1.6,
				z + 0.9,
				if k == 1 then C.Wood else C.WoodLight
			)
		end
	end
	F.model.PrimaryPart = deck
end

--------------------------------------------------------------------------------
-- Lawns: cottages, a garden, a boat yard and a fish yard behind the shops, trees
--------------------------------------------------------------------------------

--[[
	Gable-front cottage facing local −Z: a stone plinth, plastered walls, a wedge roof (ridge
	front to back) with a ridge beam and eave boards in the trim colour, plastered gables (the
	front one jettied on a tie beam with an attic window), a brick chimney, a door with a stone step
	and a little pent roof, a shuttered window with a flower box beside it, a window on each side
	and one at the back. s: wall, roof, trim, shutter, door, flowers {c1, c2}, flip (mirror the door
	and chimney side). ~33 parts.
]]
local function cottage(parent: any, cf: any, s: { [string]: any })
	local F = newFrame(U.model(parent, "Cottage"), cf)
	local hw, hd, wh = 7, 6, 10 -- half width, half depth, wall height
	local m = if s.flip then -1 else 1
	local base = F:box("Base", -hw - 0.5, -0.3, -hd - 0.5, hw + 0.5, 1.4, hd + 0.5, C.Stone, FLAT)
	F:box("Walls", -hw, 1.4, -hd, hw, wh, hd, s.wall)
	local ridgeTop = gableRoof(F, "Roof", 0, 0, "z", hd + 0.2, hw + 0.2, wh, 6.4, {
		roof = s.roof,
		eave = s.trim,
		gable = s.wall,
		beam = C.WoodDark,
		ov = 1.3,
		og = 0.9,
		t = 0.8,
		window = { s.trim, C.WindowBlue },
		windowAt = { [-1] = true },
		beamAt = { [-1] = true },
	})
	F:box("Chimney", m * 2.4, wh - 1, 1.4, m * 4.6, ridgeTop + 1.4, 3.6, C.Brick)
	F:box("ChimneyCap", m * 2.1, ridgeTop + 1.4, 1.1, m * 4.9, ridgeTop + 2.1, 3.9, C.StoneDark, NOSHADOW)
	-- front: the door on one side, a shuttered window with a flower box on the other
	door(F, "Door", "-z", -hd, -m * 3.2, 1.4, 3, 5.6, {
		trim = s.trim,
		color = s.door,
		canopy = s.roof,
		step = { -0.3, 0.6, 2.0 },
	})
	window(F, "Window", "-z", -hd, m * 3.1, 3.8, 3, 3.6, {
		trim = s.trim,
		shutter = s.shutter,
		mullion = false,
		flowers = s.flowers,
	})
	-- a window on each side and one at the back (frame and glass)
	for i, sx in { -1, 1 } do
		window(F, `SideWin{i}`, if sx < 0 then "-x" else "+x", sx * hw, -0.6, 4.0, 3.2, 3.4, {
			trim = s.trim,
			mullion = false,
			sill = false,
		})
	end
	window(F, "BackWin", "+z", hd, -m * 2.4, 4.0, 3.2, 3.4, { trim = s.trim, mullion = false, sill = false })
	F.model.PrimaryPart = base
end

-- angle, then the house's colours: pale plaster tints, a tiled roof, trim, shutters, door
local COTTAGES = {
	{ 60, C.Plaster, C.RoofRed, C.Cream, C.RoofGreen, C.WoodDark },
	{ 74, lerpColor(C.Plaster, C.Blue, 0.12), C.RoofSlate, C.White, C.RoofBlue, C.RoofBlue },
	{ 151, C.PlasterShade, C.RoofGreen, C.Cream, C.Red, C.WoodDark },
	{ 165, lerpColor(C.Plaster, C.Yellow, 0.25), C.RoofBlue, C.White, C.RoofBlue, C.Wood },
	{ 243, lerpColor(C.Plaster, C.Pink, 0.14), C.RoofTerracotta, C.Cream, C.RoofGreen, C.WoodDark },
	{ 256, lerpColor(C.Plaster, C.RoofGreen, 0.14), C.RoofBrown, C.Cream, C.Red, C.Wood },
	{ 332, lerpColor(C.WoodLight, C.Plaster, 0.45), C.RoofSlate, C.Cream, C.RoofBlue, C.WoodDark },
	{ 346, C.Plaster, C.RoofTerracotta, C.White, C.RoofBlue, C.RoofGreen },
}

--[[
	Flower garden (a plot on the lawn): a soil bed and n rows along local Z, every ROW_PITCH. Each
	row is a low green stem hedge carrying `clumps` separate bloom blocks in its two tones
	(alternating, at two heights); neighbouring rows are staggered by half a clump step, so the
	field reads as rows of flowers rather than a stack of bars. Centre (cx, cz), d = row length,
	tones = one {a, b} pair per row. 1 + n·(1 + clumps) parts.
]]
local ROW_PITCH = 6
local function flowerField(F: any, cx: number, cz: number, n: number, d: number, clumps: number, tones: { any })
	local w = (n - 1) * ROW_PITCH + 3.2
	F:box("Bed", cx - w / 2 - 1.2, -0.3, cz - d / 2 - 1.2, cx + w / 2 + 1.2, 0.5, cz + d / 2 + 1.2, C.Dirt, FLAT)
	local step = d / clumps
	for k = 1, n do
		local x = cx - w / 2 + 1.6 + (k - 1) * ROW_PITCH
		F:box(`Stems{k}`, x - 1.3, 0.4, cz - d / 2, x + 1.3, 1.6, cz + d / 2, C.Leaf1, DECOR)
		local pair = tones[k]
		local shift = (if k % 2 == 0 then 1 else -1) * step / 4
		for j = 1, clumps do
			local z = cz - d / 2 + (j - 0.5) * step + shift
			local top = 3.2 + ((j + k) % 2) * 0.6 -- bottoms sink into the stem hedge (top 1.6)
			local half = math.min(step / 2 - 1.8, 5)
			F:box(`Bloom{k}_{j}`, x - 1.5, 1.2, z - half, x + 1.5, top, z + half, pair[(j - 1) % 2 + 1], DECOR)
		end
	end
end

-- per garden: the tones of its three rows (one or two calm flower colours per garden)
local FL_RED, FL_YELLOW, FL_PINK, FL_VIOLET, FL_WHITE, FL_ORANGE, FL_BLUE =
	C.Flowers[1], C.Flowers[2], C.Flowers[3], C.Flowers[4], C.Flowers[5], C.Flowers[6], C.Flowers[7]
local GARDEN_TONES = {
	{ { FL_RED, FL_RED }, { FL_YELLOW, FL_YELLOW }, { FL_RED, FL_RED } },
	{ { FL_VIOLET, FL_VIOLET }, { FL_WHITE, FL_WHITE }, { FL_VIOLET, FL_VIOLET } },
	{ { FL_PINK, FL_WHITE }, { FL_PINK, FL_PINK }, { FL_WHITE, FL_PINK } },
	{ { FL_ORANGE, FL_ORANGE }, { FL_YELLOW, FL_YELLOW }, { FL_ORANGE, FL_ORANGE } },
	{ { FL_BLUE, FL_BLUE }, { FL_WHITE, FL_WHITE }, { FL_BLUE, FL_BLUE } },
	{ { FL_RED, FL_PINK }, { FL_WHITE, FL_WHITE }, { FL_PINK, FL_RED } },
	{ { FL_YELLOW, FL_WHITE }, { FL_VIOLET, FL_VIOLET }, { FL_WHITE, FL_YELLOW } },
	{ { FL_PINK, FL_PINK }, { FL_VIOLET, FL_VIOLET }, { FL_PINK, FL_PINK } },
}

--[[
	A flower garden on every base's line of sight (θ = 22.5 + k·45, r 97..125, between the plaza
	ring and the cottages): low rows of bloom clumps pointing at the tower, so the lawns between
	the avenues and the shops turn into gardens and the lanes stay open. Each garden stands
	off-centre, away from the shop / fun fair beside its lane. 13 parts each.
]]
local function buildGardens(hub: any, G: number)
	local m = U.model(hub, "Gardens")
	for k = 0, 7 do
		local F = radialFrame(U.model(m, "FlowerGarden"), 22.5 + k * 45, G)
		-- the shops / fun fair stand at +X of the even lanes and at −X of the odd ones
		local side = if k % 2 == 0 then 1 else -1
		flowerField(F, -side * 5, 111, 3, 27, 2, GARDEN_TONES[k + 1])
	end
end

--[[
	Koi pond on the lawn between the fish market and the harbour boardwalk (θ 302, r 137): a pale
	stone rim of four kerbs round opaque pond water sunk 0.3 below them (no rim face lies under
	the water), three lily pads (one in bloom) and two koi breaking the surface. 12 parts.
]]
local function koiPond(parent: any, G: number)
	local F = newFrame(U.model(parent, "KoiPond"), U.polarCFrame(302, 137, G))
	local rim
	for i, sz in { -1, 1 } do
		rim = F:box(`PondRim{i}`, -10, -0.3, sz * 5.1, 10, 0.9, sz * 6.5, C.StoneLight, FLAT)
		F:box(`PondRimEnd{i}`, sz * 8.6, -0.3, -5.1, sz * 10, 0.9, 5.1, C.StoneLight, FLAT)
	end
	F:box("PondWater", -8.6, -0.3, -5.1, 8.6, 0.6, 5.1, H.water, FLOW)
	for i, p in { { -5.4, -2.2, 3.2 }, { 5.2, 2.6, 2.6 }, { 1.2, -3.2, 2.0 } } do
		local w = p[3] / 2
		F:box(`LilyPad{i}`, p[1] - w, 0.5, p[2] - w, p[1] + w, 0.72, p[2] + w, C.Leaf2, DECOR)
	end
	F:box("LilyBloom", -5.9, 0.67, -2.7, -4.9, 1.47, -1.7, C.Pink, DECOR)
	for i, k in { { -1.6, 2.0, C.Orange, 1 }, { 3.0, -0.8, C.Red, -1 } } do
		F:box(`Koi{i}`, k[1] - 1.6, 0.3, k[2] - 0.65, k[1] + 1.6, 0.85, k[2] + 0.65, k[3], DECOR)
		local t0 = k[1] + k[4] * 1.6
		local t1 = t0 + k[4] * 1.3
		F:box(`KoiTail{i}`, math.min(t0, t1), 0.35, k[2] - 0.8, math.max(t0, t1), 0.8, k[2] + 0.8, C.Cream, DECOR)
	end
	F.model.PrimaryPart = rim
end

local function buildLawns(hub: any, G: number)
	local m = U.model(hub, "Lawns")
	local flowers = C.Flowers
	-- cottages, their doors towards the beach terrace
	for i, c in COTTAGES do
		cottage(m, U.polarCFrame(c[1], COTTAGE_R, G) * CFrame.Angles(0, math.pi, 0), {
			wall = c[2],
			roof = c[3],
			trim = c[4],
			shutter = c[5],
			door = c[6],
			flowers = { flowers[i % #flowers + 1], flowers[(i + 2) % #flowers + 1] },
			flip = i % 2 == 0,
		})
	end
	-- garden beside the Shop's back corner (θ 32, off base 1's line of sight at 22.5°)
	local g = polarFrame(m, 32, 0, G)
	Props.cherryTree(m, g:at(-3, 0, 137), { seed = 71, scale = 1.4 })
	Props.roundTree(m, g:at(9, 0, 143), { seed = 72, scale = 1.2 })
	flowerBed(g, 0, 127, 14, 4, { flowers[1], flowers[2] })
	flowerBed(g, 9, 133, 4, 8, { flowers[3], flowers[5] })
	-- boat yard beside the Workshop's back corner (θ 124, off base 3's line of sight at 112.5°):
	-- a boat on trestles, planks, a barrel, a tree
	local y = polarFrame(m, 124, 0, G)
	for i, z in { 128, 134 } do
		y:box(`Trestle{i}`, -3.4, -0.3, z - 0.6, 3.4, 2.4, z + 0.6, C.Wood)
	end
	Props.rowboat(m, y:at(0, 2.95, 131), { color = C.BoatPaint[1], seed = 74, oars = false })
	y:box("Planks1", -14, -0.3, 132, -8, 0.9, 140, C.WoodLight)
	y:box("Planks2", -13.4, 0.9, 133, -8.6, 1.8, 139, C.Wood)
	Props.barrel(m, y:at(-4, 0, 141), { seed = 75 })
	Props.roundTree(m, y:at(5, 0, 146), { seed = 77, scale = 1.2 })
	-- fish-drying rack behind the market (θ 315) and a crate
	local f = polarFrame(m, 315, 0, G)
	for i, x in { -6, 6 } do
		f:box(`RackPost{i}`, x - 0.4, -0.3, 127.6, x + 0.4, 6.4, 128.4, C.WoodDark)
	end
	f:box("RackBar", -6.7, 6.0, 127.7, 6.7, 6.6, 128.3, C.Wood, NOSHADOW)
	for k = 1, 4 do
		local x = -6 + k * 2.4
		f:box(`HangFish{k}`, x - 0.5, 3.4, 127.6, x + 0.5, 6.0, 128.4, H.fish[(k % 3) + 1], DECOR)
	end
	Props.crate(m, f:at(12, 0, 125), { seed = 79, size = 3.4, color = C.Wood })
	-- big oaks on the lawns beside the bases' lines of sight
	for _, t in { { 282, 130 }, { 212, 132 } } do
		Props.oakTree(m, polarFrame(m, t[1], 0, G):at(0, 0, t[2]), { seed = floor(t[1]) + 4, scale = 1.4 })
	end
	koiPond(m, G)
end

--------------------------------------------------------------------------------
-- Sand terrace round the grass edge
--------------------------------------------------------------------------------

--[[
	Sand terrace: the plaza (GroundTop) stands 2 studs above the beach (y = 2). A ring of 1-stud
	sand steps (top GroundTop − 1) runs round the shore just outside the plaza's stair-stepped
	grass edge (grass cells reach r ≈ 152..164), so players walk down to the beach and back up
	anywhere without jumping. Straight chords of a 36-gon whose outer edge is a smooth polygon at
	L.terraceOut; the inner parts of the chords sit inside the grass columns (hidden). Left out
	under the bridge decks and along the harbour boardwalk (which carries the walk there).
]]
local TERRACE_STEP = 10 -- degrees per chord
local PIER_ANGLE = 322 -- harbour pier centreline
local BOARDWALK = { 285, 345 } -- harbour boardwalk, θ from .. to (on the terrace chords)

local function buildTerrace(hub: any, cfg: any, G: number)
	local m = U.model(hub, "BeachTerrace")
	local rIn, rOut = L.terraceIn, L.terraceOut
	local len = 2 * rOut * math.tan(rad(TERRACE_STEP / 2)) + 0.2
	local bridges = {}
	for _, a in cfg.BridgeAngles do
		bridges[a % 360] = true
	end
	for a = 0, 360 - TERRACE_STEP, TERRACE_STEP do
		local onBoardwalk = a > BOARDWALK[1] and a < BOARDWALK[2]
		if not bridges[a] and not onBoardwalk then
			local cf = U.polarCFrame(a, (rIn + rOut) / 2, G - 1.6)
			U.part(m, "Step", V(len, 1.2, rOut - rIn), cf, C.Sand, nil, FLAT)
		end
	end
end

--[[
	Tall palms framing every bridge landing (in Avenues.AvenueN), leaning away from the welcome
	gate (their fronds point along the diagonals), so no frond reaches the gate or the view of the
	tower down the avenue. Each trunk stands on one level surface: from 14 studs past the gate it
	moves out towards the water until its whole foot (a 2.4-stud circle) is clear of the terrace
	steps (Hub parts, built first: their own extents, not the voxel ground) and on level sand above
	the water, so no step cuts through it. The build fails if a landing has no such spot.
]]
local function buildLandingPalms(hub: any, cfg: any, world: any, G: number)
	local steps = {}
	for _, s in hub:FindFirstChild("BeachTerrace"):GetChildren() do
		if s:IsA("BasePart") then
			table.insert(steps, s)
		end
	end
	local water = cfg.WaterTop or 0
	-- ground top under the whole foot at (x, z), or nil when it is uneven, wet or on a step
	local function footTop(x: number, z: number): number?
		local top
		for k = 0, 8 do
			local a = rad(k * 45)
			local q = if k == 0 then V(x, 0, z) else V(x + 2.4 * math.sin(a), 0, z + 2.4 * math.cos(a))
			for _, s in steps do
				local l = s.CFrame:PointToObjectSpace(V(q.X, s.CFrame.Position.Y, q.Z))
				if abs(l.X) <= s.Size.X / 2 and abs(l.Z) <= s.Size.Z / 2 then
					return nil
				end
			end
			local h = world:heightAt(q.X, q.Z)
			if h <= water or (top and h ~= top) then
				return nil
			end
			top = h
		end
		return top
	end
	for i, angle in cfg.BridgeAngles do
		local avenue = hub:FindFirstChild("Avenues"):FindFirstChild(`Avenue{i}`)
		local F = radialFrame(avenue, angle, G)
		for j, sx in { -1, 1 } do
			local placed = false
			for dz = 0, 24 do
				local p = F:point(sx * 24, 0, L.gate + 14 + dz)
				local top = footTop(p.X, p.Z)
				if top then
					local cf = CFrame.new(p.X, top, p.Z) * CFrame.Angles(0, rad(angle - 90 + sx * 45), 0)
					Props.palmTree(avenue, cf, { seed = i * 31 + j, scale = 1.5, lite = true })
					placed = true
					break
				end
			end
			assert(placed, `no level sand for the landing palm {j} of the θ {angle} bridge`)
		end
	end
end

--------------------------------------------------------------------------------
-- Beach ring: palms, bathing huts, parasols with deck chairs
--------------------------------------------------------------------------------

local PALM_ANGLES = { 44, 60, 118, 136, 150, 212, 240 } -- (the avenue ends have their own)

local function beachSet(parent: any, cf: any, seed: number, color: any)
	local F = newFrame(U.model(parent, "BeachSet"), cf)
	Props.parasol(F.model, F:at(0, 0, 1), { seed = seed, color = color })
	Props.beachChair(F.model, F:at(-2.2, 0, -1, 0), { seed = seed + 1, color = color })
	F:box("Towel", 2.4, -0.05, -3.6, 5.6, 0.12, 1.8, lerpColor(color, C.Cream, 0.4), DECOR)
	F:box("TowelStripe", 2.25, -0.1, -1.4, 5.75, 0.24, -0.4, C.Cream, DECOR)
end

-- CFrame on the real ground at (θ, r), turned to face θ + yaw (0 = towards the centre).
local function groundCf(world: any, a: number, r: number, yaw: number?): any
	local p = U.polar(a, r, 0)
	return CFrame.new(p.X, world:heightAt(p.X, p.Z), p.Z) * CFrame.Angles(0, rad(a + (yaw or 0)), 0)
end

local function buildBeach(hub: any, world: any)
	local m = U.model(hub, "Beach")
	local R = L.beach
	-- big palms in two staggered rows
	for k, a in PALM_ANGLES do
		local r = if k % 2 == 0 then R - 4 else R + 2
		Props.palmTree(m, groundCf(world, a, r, k * 47), { seed = 100 + k, scale = 1.45 + (k % 3) * 0.2, lite = true })
	end
	-- parasols and deck chairs facing the lagoon
	for i, a in { 33, 226 } do
		beachSet(m, groundCf(world, a, R, 180), 120 + i * 3, C.Festive[(i * 3) % #C.Festive + 1])
	end
	-- bathing huts of tinted planks on little plank decks, facing the lagoon (the bases see them):
	-- a tiled gable roof with a cream ridge (its ends show the roof colour), a framed door in the
	-- roof colour and a small window in the gable. 8 parts each.
	for _, h in
		{
			{ 249, C.RoofRed },
			{ 256, C.RoofBlue },
			{ 263, C.RoofGreen },
			{ 100, C.RoofTerracotta },
			{ 107, C.RoofSlate },
		}
	do
		local hut = newFrame(U.model(m, "BeachHut"), groundCf(world, h[1], R - 1, 180))
		local main = h[2]
		local deck = hut:box("Deck", -3.8, -0.3, -4.8, 3.8, 0.5, 3.4, C.Plank, FLAT)
		hut:box("Hut", -3, 0.5, -2.8, 3, 6.4, 3, lerpColor(C.Plaster, main, 0.16))
		gableRoof(hut, "HutRoof", 0, 0.1, "z", 2.9, 3, 6.4, 3.2, {
			roof = main,
			ridge = C.Cream,
			gables = {},
			noEaves = true,
			ov = 0.8,
			og = 0.7,
		})
		door(hut, "HutDoor", "-z", -2.8, 0, 0.5, 2.4, 4.6, { trim = C.Cream, color = main })
		hut:box("HutWindow", -0.7, 7.0, -3.9, 0.7, 8.3, -3.45, C.WindowBlue, NOSHADOW)
		hut.model.PrimaryPart = deck
	end
end

--------------------------------------------------------------------------------
-- Harbour (θ ≈ 287..343): boardwalk, pier with boats, an anchor, lighthouse on a rock islet
--------------------------------------------------------------------------------

--[[
	Plank boardwalk along the shore: straight chords of planks (top GroundTop − 0.4) from inside
	the grass edge (hidden there) out to r = L.terraceOut + 6 over the sand, a wooden fascia down
	to the sand along the outer edge, bollards at the joints, three lamps, a bench looking out at
	the boats and a wooden step (top 2.8) all along the outer edge: deck 3.6 → step → sand 2, so
	the beach is reached anywhere along the harbour without a jump. The pier starts at its outer
	edge (above the step).
]]
local function buildBoardwalk(m: any, G: number): number
	local bw = U.model(m, "Boardwalk")
	local rIn, rOut = L.terraceIn, L.terraceOut + 6
	local top = G - 0.4
	local n = 6
	local step = (BOARDWALK[2] - BOARDWALK[1]) / n
	local len = 2 * rOut * math.tan(rad(step / 2))
	for k = 0, n - 1 do
		local a = BOARDWALK[1] + (k + 0.5) * step
		local F = polarFrame(bw, a, 0, 0)
		-- all chords one colour: they overlap in thin wedges at the inner joints
		F:box(`Deck{k + 1}`, -len / 2 - 0.1, top - 0.8, rIn, len / 2 + 0.1, top, rOut, C.Plank, FLAT)
		F:box(`Fascia{k + 1}`, -len / 2, 1.4, rOut - 0.8, len / 2, top - 0.1, rOut + 0.2, C.Wood, NOSHADOW)
		-- the step chord is a little longer (it lies further out), so neighbours still meet; it
		-- leaves a gap round the harbour pier's piles
		local stepLen = 2 * (rOut + 3.2) * math.tan(rad(step / 2)) + 0.3
		local px = (rOut + 1.7) * math.sin(rad(PIER_ANGLE - a)) -- the pier across this chord
		local pieces = { { -stepLen / 2, stepLen / 2 } }
		if abs(px) < stepLen / 2 + 5.8 then
			pieces = { { -stepLen / 2, px - 5.8 }, { px + 5.8, stepLen / 2 } }
		end
		for j, piece in pieces do
			if piece[2] - piece[1] > 1 then
				F:box(`Step{k + 1}_{j}`, piece[1], 1.4, rOut + 0.2, piece[2], top - 0.8, rOut + 3.2, C.Wood, FLAT)
			end
		end
	end
	for k = 0, n do
		local a = BOARDWALK[1] + k * step
		local F = polarFrame(bw, a, rOut - 0.9, 0)
		if k % 2 == 1 then
			streetLamp(bw, F:at(0, top, 0), 9, C.Iron)
		else
			F:box(`Bollard{k}`, -0.7, 1.4, -0.7, 0.7, top + 1.4, 0.7, C.WoodDark)
		end
	end
	Props.bench(bw, polarFrame(bw, 306, rOut - 3, top):at(0, 0, 0, 180), { length = 7, color = C.Wood, seed = 240 })
	return rOut
end

local function buildHarbour(hub: any, cfg: any, world: any)
	local m = U.model(hub, "Harbour")
	local G = cfg.GroundTop or 4
	local water = cfg.WaterTop or 0
	local deck = water + 3.8 -- just under the plaza grass, a step above the boardwalk
	local pierA = PIER_ANGLE
	local r0 = buildBoardwalk(m, G)
	-- Props.dockSegment hangs a brace between the piles of every segment: over the beach it would
	-- be buried in the sand (invisible), so it is taken out there
	local function dock(cf: any, opts: { [string]: any })
		local brace = Props.dockSegment(m, cf, opts):FindFirstChild("Brace")
		if brace then
			local braceTop = brace.CFrame.Position.Y + brace.Size.Y / 2
			local buried = true
			for _, x in { -brace.Size.X / 2, 0, brace.Size.X / 2 } do
				local p = brace.CFrame * V(x, 0, 0)
				buried = buried and world:heightAt(p.X, p.Z) >= braceTop
			end
			if buried then
				brace:Destroy()
				U.partCount -= 1
			end
		end
	end
	-- pier from the boardwalk over the beach out to deep water: 5 chained segments, a T-head
	for k = 0, 4 do
		dock(U.polarCFrame(pierA, r0 + 6 + k * 12, deck), {
			length = 12,
			width = 8,
			depth = if k < 2 then 10 else 20,
			piles = if k == 4 then "both" else "front",
			seed = 200 + k,
		})
	end
	local head = r0 + 64
	dock(U.polarCFrame(pierA, head, deck) * CFrame.Angles(0, rad(90), 0), {
		length = 24,
		width = 8,
		depth = 22,
		seed = 205,
	})
	local P = radialFrame(m, pierA, 0)
	-- boats moored along the pier, all on open water (lagoon bed −2 … −14), floating 0.4 high (the
	-- hull floors stay above the waves) and gently bobbing (Bob attribute, AmbientController)
	for _, b in
		{
			{
				Props.motorboat(
					m,
					P:at(9.5, water + 0.4, head - 20, 180),
					{ color = C.White, stripe = C.Red, seed = 210 }
				),
				3.4,
			},
			{ Props.rowboat(m, P:at(-9.5, water + 0.4, head - 22), { color = C.BoatPaint[2], seed = 211 }), 2.9 },
			{ Props.sailboat(m, P:at(19, water + 0.4, head + 1, 190), { color = C.BoatPaint[3], seed = 213 }), 4.2 },
		}
	do
		b[1]:SetAttribute("Bob", 0.3)
		b[1]:SetAttribute("BobPeriod", b[2])
	end
	-- mooring posts with lifebuoys (between the piles)
	for i, z in { r0 + 21, r0 + 45 } do
		P:box(`BuoyPost{i}`, 4.6, water - 8, z - 0.6, 5.8, deck + 4.4, z + 0.6, C.WoodDark)
		Props.lifebuoy(m, P:at(5.2, deck + 3, z - 0.93, 0), { seed = 214 + i })
	end
	-- an anchor on the beach by the boardwalk
	Props.anchor(m, groundCf(world, 338, r0 + 8, 70), { seed = 220, scale = 1.3 })

	-- lighthouse on a stepped rock islet, joined to the boardwalk's step by a stone breakwater: at
	-- θ 305, between base 7's pier (θ 292.5) and the harbour pier, its rocks 30+ studs clear of
	-- every base's pier corridor (checkPierCorridors) and of the lagoon's rowboat (θ 313); the
	-- big rocks sit on the inner (shore) side towards base 7. Corner rocks stay clear of the
	-- lighthouse plinth (±10.5 at scale 1.5), which is the islet's top step. 63 studs: well
	-- below the tower.
	local I = polarFrame(U.model(m, "LighthouseIslet"), 305, L.shore + 9, 0)
	I:box("Rock1", -13, -15, -12.5, 14, 0.8, 14, C.Stone)
	I:box("Rock3", 13, -15, -5.5, 15.5, 0.2, 4.5, C.StoneDark)
	I:box("Rock4", -14, -15, 11.5, -9.5, 0.4, 16, C.StoneDark)
	I:box("Rock5", -17, -15, -14, -12, 2.4, -6.5, C.StoneDark)
	I:box("Rock5Top", -16.2, 2.4, -13, -12.8, 3.8, -8.4, C.Stone)
	I:box("Rock6", 12.5, -15, 8.5, 17.5, 1.8, 15.5, C.Stone)
	local stepR = L.terraceOut + 6 + 4.2 -- just past the boardwalk's step (its chord ends reach r + 0.7)
	I:box("Breakwater", -4.5, -6, stepR - (L.shore + 9), 4.5, 2.6, -12.5, C.StoneLight)
	Props.lighthouse(I.model, I:at(0, 3.2, 1), { scale = 1.35, seed = 232 })
end

--------------------------------------------------------------------------------
-- Pier corridors: nothing of the hub may stand on a base's pier or in front of its fishing spot
--------------------------------------------------------------------------------

--[[
	Every base's pier, end platform and the open water its fisher looks at (base-local
	|lx| < PierHalfWidth + 8, −(PierLength + 38) < lz < 0) stay free of hub parts: the build fails
	and names the parts otherwise. Separating-axis test in the top view between each part's box
	(its 8 corners) and each corridor rectangle.
]]
local function checkPierCorridors(hub: any, cfg: any, world: any)
	local halfW = (cfg.PierHalfWidth or 22) + 8
	local depth = (cfg.PierLength or 72) + 38
	local slotR = cfg.BaseRadius or 312
	local rects = {}
	for i, b in world.bases do
		local a = rad(b.angle)
		local u = { math.sin(a), math.cos(a) } -- outwards (lz)
		local v = { math.cos(a), -math.sin(a) } -- sideways (lx)
		local pts = {}
		for _, c in { { -halfW, -depth }, { halfW, -depth }, { halfW, 0 }, { -halfW, 0 } } do
			local lx, rr = c[1], slotR + c[2]
			table.insert(pts, { rr * u[1] + lx * v[1], rr * u[2] + lx * v[2] })
		end
		rects[i] = { pts = pts, axes = { u, v } }
	end
	local function span(pts: { any }, ax: { number }): (number, number)
		local lo, hi = math.huge, -math.huge
		for _, q in pts do
			local d = q[1] * ax[1] + q[2] * ax[2]
			lo, hi = math.min(lo, d), math.max(hi, d)
		end
		return lo, hi
	end
	local hits = {}
	for _, p in hub:GetDescendants() do
		if p:IsA("BasePart") then
			local h, cf = p.Size / 2, p.CFrame
			local pts = {}
			for _, sx in { -1, 1 } do
				for _, sy in { -1, 1 } do
					for _, sz in { -1, 1 } do
						local q = cf * V(sx * h.X, sy * h.Y, sz * h.Z)
						table.insert(pts, { q.X, q.Z })
					end
				end
			end
			-- the box's own axes, seen from above, and their normals
			local axes = {}
			for _, d in { cf.RightVector, cf.UpVector, cf.LookVector } do
				local n = sqrt(d.X * d.X + d.Z * d.Z)
				if n > 1e-3 then
					table.insert(axes, { d.X / n, d.Z / n })
					table.insert(axes, { -d.Z / n, d.X / n })
				end
			end
			for i, r in rects do
				local apart = false
				for _, list in { r.axes, axes } do
					for _, ax in list do
						local a0, a1 = span(pts, ax)
						local b0, b1 = span(r.pts, ax)
						if a1 <= b0 or b1 <= a0 then
							apart = true
							break
						end
					end
					if apart then
						break
					end
				end
				if not apart then
					table.insert(hits, `B{i}: {p:GetFullName()}`)
				end
			end
		end
	end
	if #hits > 0 then
		error(`Hub parts in a base's pier corridor: {table.concat(hits, ", ", 1, math.min(#hits, 12))}`)
	end
end

--------------------------------------------------------------------------------

return function(parent: any, cfg: any, world: any)
	local startCount = U.partCount
	local G = cfg.GroundTop or 4
	local plazaR = cfg.HubPlazaRadius or 158
	L.avenueEnd = plazaR - 5
	L.gate = L.avenueEnd - 13
	L.terraceIn = plazaR - 8
	L.terraceOut = plazaR + 8
	L.shore = cfg.HubRadius or 185
	L.beach = (L.terraceOut + L.shore) / 2 + 0.5
	local hub = U.model(parent, "Hub")

	buildPlaza(hub, G)
	buildTower(hub, G)
	buildSpawn(hub, G)
	buildPlazaFurniture(hub, G)

	buildShop(hub, U.polarCFrame(45, SHOP_R, G))
	buildFishMarket(hub, U.polarCFrame(315, SHOP_R, G))
	buildWorkshop(hub, U.polarCFrame(135, SHOP_R, G))

	buildAvenues(hub, cfg, G)
	buildFair(hub, G)
	-- the game booth and the bandstand stand behind the Shop and the Workshop, facing the lagoon
	-- and the bases (their audience on the lawn by the beach terrace)
	buildArcade(hub, U.polarCFrame(45, RING_R, G) * CFrame.Angles(0, math.pi, 0))
	buildStage(hub, U.polarCFrame(135, RING_R - 1, G) * CFrame.Angles(0, math.pi, 0))
	buildLawns(hub, G)
	buildGardens(hub, G)
	buildTerrace(hub, cfg, G)
	buildLandingPalms(hub, cfg, world, G)
	buildBeach(hub, world)
	buildHarbour(hub, cfg, world)

	-- everything that turns (Spin models: the Ferris wheel, the golden fish, the hooked and the
	-- jumping fish, the sign gear) is moved by the client only: it must never shove or carry a
	-- player, so none of it collides or takes raycasts
	for _, d in hub:GetDescendants() do
		if d:IsA("Model") and typeof(d:GetAttribute("Spin")) == "number" then
			for _, p in d:GetDescendants() do
				if p:IsA("BasePart") then
					p.CanCollide = false
					p.CanQuery = false
				end
			end
		end
	end

	checkPierCorridors(hub, cfg, world)

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
				offset = V(0, -0.7, -2.3),
			},
			{
				root = "workspace",
				path = { "Map", "Hub", "Workshop", "Workbench", "UpgradePromptAttachment" },
				offset = V(0, 1.5, -2.3),
			},
		},
	}
end
