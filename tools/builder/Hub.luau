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
	θ = 22.5 + k·45; those lanes stay open (nothing taller than a bench near their axis), so every
	base sees the whole tower, and each lane is a garden walk from the plaza rim to the beach:
	  centre       «Золотая рыбка» fountain tower (~108 studs, the landmark every base, pier and
	               bridge sees): a brick basin with a blue tile band, gold corner bands and stone
	               seats with plank tops round a see-through pool, three tiers (the middle one turned
	               45°: an octagonal silhouette) with stone cornices under wide cream basin lips and
	               pools on them, gold spout heads pouring turquoise curtains that fall free in front
	               of the faces (a light streak down each, ragged foam where they land), a spire with
	               gold-framed fish medallions, a cream balcony ring on corbels with a balustrade and
	               gold finials, a plaster shaft, a lantern colonnade round a glowing gold core, an
	               onion dome of verdigris on a gold band, and on top a huge crowned golden fish (the
	               hub's one hero accent, the map's only big saturated piece: yolk gold, amber
	               scales, pale gold belly and shine, russet fins, a warm light under its belly)
	               riding a water spout and slowly circling (Spin attribute, turned by the client's
	               AmbientController); sparkles, spray and mist as particles. A round plaza (r 66)
	               of warm stone with an inlaid cream limestone star in a dark outline, cream rays to
	               the shop porches and the fun fair and a terracotta ring; benches and lamps 22.5°
	               off the avenues and the shop diagonals (clear walkways to every bridge and counter)
	  avenues      θ = 0/90/180/270, 25 wide: warm grey cobbles between cream kerbs from the plaza
	               to the bridge (r 62..153), a terracotta brick runner on a dark outline from the
	               plaza star to the bridge, cream cross bands every 16 studs, short clipped box
	               hedges broken by stone planters with topiary balls, a lamp pair carrying iron masts
	               with small pennants hung high (13+ studs) across the avenue, and the welcome gate
	               at r 140: stepped limestone piers on stone plinths (a tile band in the district
	               colour of the bridge and gateway, ball finials with gold knobs, lantern niches on
	               the bridge side, flower boxes on the plaza side) carrying a timber beam and the
	               board «ОСТРОВ РЫБАКОВ» (inner side «ХОРОШЕГО КЛЁВА!») under a little moss-slate
	               gable roof; tall palms on the sand beside the bridge landing; a frontage on the
	               open side (a bed of jewel-tone blooms, a bench with a gravel walk out to the next
	               lane) and rounded voxel street trees (green, mint or blossom); HubSpawn on the
	               θ 180 avenue at r 100, facing the tower (its lamps and bunting stand behind it)
	  shops        built 1.2× (modelled at 1/1.2), facing the tower from r 76 (porches on the
	               plaza rim, customers stand on the porch, the counter closes the open shop front):
	    θ 45       Shop «УДОЧКИ» — a two-storey half-timbered house (plaster, dark timber, moss
	               slate roof, green shutters, flower boxes); its plaza front: a striped awning over
	               the counter, timber studs, two shuttered upper windows with flower boxes, the sign
	               hanging from iron brackets under the eave, a dormer on the front slope; a rod
	               wall inside, and a giant rod on a bracket at the eave with a fish twirling on its
	               line in front of the roof
	    θ 315      FishMarket «РЫБНЫЙ РЫНОК» — an open timber market hall on stone pedestals under a
	               blue-grey slate roof (a light plank ceiling inside) with a louvred lantern and a
	               fish weather vane, the sign on the front fascia, a blue/cream awning, a
	               fishmonger's slab: trays of fish laid side by side on heaped ice (heads, eyes and
	               tails, a lemon and parsley) either side of the scales, side counters, crates
	    θ 135      Workshop «МАСТЕРСКАЯ» — a brick workshop with stone quoins and a slate roof, its
	               gable to the plaza carrying a big turning gear, the sign between two small
	               iron-framed windows, a hoist beam with a pulley and a hook, a rolled-up garage
	               door over the workbench, a forge inside, a chimney with smoke, a side door
	  θ 225        fun fair on a flagstone ground: an entrance arch «АТТРАКЦИОНЫ» (striped posts
	               lit by rows of bulbs, a scalloped valance) on the plaza rim, a path lined by an
	               ice-cream cart, a popcorn wagon, a lemonade stand with a big lemon and the striped
	               «ИГРЫ» game tent, a string of lights across it, the big carousel at its end (a
	               two-tier striped canopy with a scalloped valance) with a ring toss and a hook-a-fish
	               pool beside it, and a Ferris wheel in white and teal behind (their spinning parts
	               never collide)
	  lanes        the eight base lanes (r 70..149): a cobbled walk between cream kerbs, box-edged
	               flower beds (Props.flowerBed, one tone family per lane) near the plaza (on the
	               side of a shop or the fair further out, clear of it), and one feature each: on the
	               garden lanes (θ 22.5, 112.5, 202.5, 292.5) a cream round with a sundial or a
	               birdbath between clipped box hedges, on the cottage lanes a topiary fish with a
	               bench (θ 67.5), a rill with a plank footbridge (θ 157.5) or a lily pond with a
	               bench (θ 247.5), and a pair of benches facing the tower (θ 337.5)
	  cottages     three clusters of two different houses flanking a base lane (θ 67.5, 157.5,
	               247.5), fronts to the beach: a two-storey fisher's house (jettied timber upper
	               floor, balcony, outside stair), an L-shaped cottage (cross gable, porch on posts),
	               a red net loft (boat doors, hoist, lean-to, nets and floats) and a hip-roofed
	               house (stepped roof, dormer, portico); each pair shares a yard on the lane with its
	               own plan (mirrored cluster to cluster; a dry-stone wall, a clipped hedge or a white
	               rail fence; the kitchen garden, hives, barrel and woodpile in different corners)
	               and its own piece: a washing line, a cold frame with a bench, a roofed well with a
	               bucket on its rope; roofs in clay, slate and moss slate, off the bases' team hues
	  lawns        an orchard tree behind the Shop, a walled boat yard behind the Workshop (θ 128),
	               the «СЦЕНА» bandstand on its own pad behind the Fish Market facing the harbour
	               boardwalk (θ 318, benches on the boardwalk), a koi garden (θ 302: pond, plank
	               bridge, stepping stones, stone lantern, bench, maple), a picnic on the lawn by the
	               θ 180 landing, two oaks
	  terrace      a ring of 1-stud sand steps between the plaza and the beach (walk down anywhere)
	  beach ring   a waterfront of zones beside the lanes: a thatched beach bar (θ 26), bathing huts
	               on a deck (θ 63) with a swimming line of floats, a fishing corner (θ 112), a
	               boathouse on stilts (θ 124), a lifeguard tower (θ 161), a kayak rack (θ 205),
	               plank walks with lamps at the foot of the steps (θ 138..152, 218..236), three
	               bathing groups (a parasol over two loungers, towels in jewel tones, a cooler and a
	               bucket), rocks with tide pools and starfish at the waterline, canoes pulled up on
	               the sand, a sandcastle; big palms and tufts of dune grass along the steps
	  harbour      a plank boardwalk with lamps along the shore (θ 285..345), its boards in two tones
	               with dark joints, a step down to the sand all along it, a pier from it to deep
	               water with a T-head at θ 322, fish crates at its root, bobbing boats moored on
	               open water (Bob attribute), a lifebuoy, an anchor on a stone plinth, and a
	               lighthouse on a rock islet with a breakwater at θ 305, clear of every base's pier
	               corridor (checked: the build fails otherwise)

	Every building is modelled in a local frame (origin = front centre at ground level, local −Z
	towards the tower), so the customer side of every counter is local −Z; prompts sit about
	3.5 studs above the porch, just in front of the counter.
	Budget: ≤ 2900 parts and ≤ 12 PointLights (the build fails above either); the lane beds are
	planted last with whatever the budget leaves (placeLaneBeds).
]]

local U = require("./Util")
local Props = require("./Props")
local Promenade = require("./Promenade") -- district colours of the bridges and gateways
local Kit = require("./MapKit") -- Kit.sway: moving details for the ambient wave

local Enum = U.Enum
local CFrame = U.CFrame
local V = U.Vector3.new
local Mat = Enum.Material

local C = Props.Colors -- the Palette (tools/builder/Palette.luau) plus a few legacy aliases
local shade = Props.shade
local lerpColor = Props.lerpColor

local rad, sqrt, floor, abs = math.rad, math.sqrt, math.floor, math.abs

local MAX_PARTS = 2900
local MAX_LIGHTS = 12

-- Layout radii (studs from the island centre); the ones tied to the ground's shore radii are set
-- from cfg in buildHub (HubPlazaRadius 158, HubRadius 185).
local PLAZA_R = 66 -- round paved plaza
local SHOP_R = 76 -- shop fronts: the porches reach the plaza rim
local SHOP_SCALE = 1.2 -- the three shops are modelled at 1/1.2 and built 1.2× bigger
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
	walk = C.SandDark, -- the fun fair's path
	medallion = C.Limestone, -- the cream star round the fountain and its rays
	street = lerpColor(C.Stone, C.CobbleDark, 0.3), -- avenue cobbles: a warm grey stone
	runner = lerpColor(C.Brick, C.CobbleDark, 0.15), -- the avenues' terracotta brick runners
	kerb = C.Limestone, -- cream kerbs and the cross bands
	lane = lerpColor(C.Cobble, C.Stone, 0.2), -- the base lanes' cobbled walks
	ring = C.Brick, -- the terracotta ring round the fountain
	water = C.Water,
	waterLight = C.WaterLight,
	-- water streaming down the tower's tiers: clearly water (turquoise), lighter than the pools
	cascade = lerpColor(C.Water, C.WaterLight, 0.45),
	streak = lerpColor(C.WaterLight, C.Foam, 0.55),
	basinFloor = lerpColor(C.Water, C.Navy, 0.4),
	ice = lerpColor(C.Foam, C.WaterLight, 0.3),
	tile = C.RoofBlue, -- blue tile bands on the stone fountain
	basinBrick = lerpColor(C.Brick, C.Limestone, 0.18), -- the fountain basin's brick walls
	stoneWarm = lerpColor(C.Limestone, C.SandDark, 0.4), -- the fountain's warm sandstone
	verdigris = lerpColor(C.RoofGreen, C.Cyan, 0.4), -- the spire's copper cap
	-- the golden fish, the hub's one hero accent (the only big saturated piece of the map,
	-- exempt from the "no loud big part" rule in palette_lint): a rich yolk gold (≈ 248,190,52)
	-- that stays gold on the shaded side and from below, a brighter head (≈ 250,204,70), amber
	-- scales, a pale gold belly and shine, russet-orange fins
	gold = lerpColor(C.Flowers[2], C.Autumn1, 0.13),
	goldHead = lerpColor(C.Flowers[2], C.GoldLight, 0.15),
	goldScale = lerpColor(C.Flowers[2], C.Autumn1, 0.45),
	goldDeep = shade(C.Autumn2, 0.86), -- gold trims on stone (spouts, medallions, finials)
	goldLight = lerpColor(C.GoldLight, C.White, 0.35),
	goldBelly = lerpColor(C.GoldLight, C.Flowers[2], 0.55),
	goldFin = C.Autumn1,
	-- hub roofs stay off the saturated team hues (DESIGN.md §1): every sector's strongest roof
	-- colour is its own base's
	roofClay = lerpColor(C.RoofTerracotta, C.RoofBrown, 0.5), -- weathered clay tiles
	roofSage = lerpColor(C.RoofGreen, C.RoofSlate, 0.45), -- moss-green slate
	roofHarbour = lerpColor(C.RoofBlue, C.RoofSlate, 0.4), -- blue-grey slate
	gravel = lerpColor(C.SandDark, C.Stone, 0.35), -- garden and yard paths
	wall = lerpColor(C.Stone, C.Limestone, 0.3), -- low dry-stone walls
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
		local bw = math.min(0.65, hw * 0.45 - 0.05) -- the two blooms never touch
		for i = 1, 2 do
			local c = a + (if i == 1 then -1 else 1) * hw * 0.45
			local top = by + 0.75 + (i % 2) * 0.2
			F:onFace(`{name}Bloom{i}`, face, w, c - bw, by - 0.2, c + bw, top, 0.5, 1.4, o.flowers[i], DECOR)
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
	Fish laid on the ice across a fishmonger's tray (along local Z, its head towards the customers
	at −Z, lying on its side): a plump body, a lighter stepped head, a darker tail fan and a white
	eye on the upper side. 4 parts.
]]
local function trayFish(F: any, name: string, x: number, y: number, z0: number, len: number, color: any)
	local w = len * 0.2 -- half the body's height (now across the tray)
	local hz = z0 + len * 0.22
	local tz = z0 + len * 0.78
	F:box(name, x - w, y, hz, x + w, y + 0.55, tz, color, DECOR)
	F:box(name .. "Head", x - w * 0.8, y + 0.02, z0, x + w * 0.8, y + 0.5, hz, lerpColor(color, C.Cream, 0.3), DECOR)
	F:box(name .. "Tail", x - w * 1.15, y + 0.06, tz, x + w * 1.15, y + 0.36, z0 + len, shade(color, 0.78), DECOR)
	F:box(name .. "Eye", x - 0.18, y + 0.5, z0 + len * 0.07, x + 0.18, y + 0.6, z0 + len * 0.15, C.White, DECOR)
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

--[[
	Light bunting high over a street: a rope in two sagging halves between the world points a and
	b and n small pennants (one block each, w × h, hanging from the rope) in the festive colours.
	2 + n parts.
]]
local function pennants(parent: any, a: any, b: any, n: number, sag: number, w: number, h: number, seed: number)
	local m = U.model(parent, "Bunting")
	local low = (a + b) / 2 - V(0, sag, 0)
	local function rope(name: string, p: any, q: any): any
		local cf = CFrame.lookAt((p + q) / 2, q)
		return U.part(m, name, V(0.18, 0.18, (q - p).Magnitude), cf, C.Rope, nil, DECOR)
	end
	m.PrimaryPart = rope("RopeA", a, low)
	rope("RopeB", low, b)
	local along = V(b.X - a.X, 0, b.Z - a.Z).Unit
	local up = V(0, 1, 0)
	for i = 1, n do
		local t = i / (n + 1)
		local p = if t <= 0.5 then a + (low - a) * (t * 2) else low + (b - low) * ((t - 0.5) * 2)
		local col = C.Festive[(seed + i) % #C.Festive + 1]
		local cf = CFrame.fromMatrix(p - V(0, h / 2 + 0.02, 0), along, up, along:Cross(up))
		U.part(m, `Flag{i}`, V(w, h, 0.26), cf, col, nil, DECOR)
	end
	-- the pennants swing about the rope line (the pivot's local Z runs along it)
	Kit.sway(m, CFrame.lookAt((a + b) / 2, b), 5, "Z", 2.6)
end

--[[
	Park bench standing on cf (you sit facing local −Z), length len: two dark end blocks, a plank
	seat and a solid plank back resting on the seat's rear edge. 4 parts (Props.bench has 8).
]]
local function parkBench(parent: any, cf: any, len: number, color: any?): any
	local F = newFrame(U.model(parent, "Bench"), cf)
	local wood = color or C.Wood
	local seat = F:box("Seat", -len / 2, 1.6, -0.95, len / 2, 2.15, 0.95, wood)
	F:box("Back", -len / 2, 2.15, 0.45, len / 2, 4.1, 0.95, shade(wood, 0.9), NOSHADOW)
	for i, x in { -len / 2 + 0.8, len / 2 - 0.8 } do
		F:box(`Leg{i}`, x - 0.45, -0.2, -0.85, x + 0.45, 1.6, 0.85, C.WoodDark, NOSHADOW)
	end
	F.model.PrimaryPart = seat
	seat.PivotOffset = seat.CFrame:Inverse() * cf
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
	floor windows, a moss-slate roof with a ridge beam, eave boards and plastered gables with attic
	windows, dormers on both slopes, a brick chimney with smoke. The plaza front: a red/cream
	striped awning under the lintel beam, the upper storey framed by timber studs with two
	shuttered windows (flower boxes) and between them the sign hanging from two iron brackets
	under the eave; the counter (Counter.ShopPromptAttachment) between two glass display cases, a
	rod wall, a shelf of tackle and a trophy fish inside. A giant rod in
	a holder on a bracket at the left eave rises over the porch; a fish dangles from its line in
	front of the roof and slowly twirls. On the porch: a rod rack, a barrel of rods and a sandwich
	board «Купить удочку».
]]
local function buildShop(hub: any, cf: any): (any, any)
	local F = newFrame(U.model(hub, "Shop"), cf, SHOP_SCALE)
	local wall, timber, trim = C.Plaster, C.WoodDark, C.Cream
	local roof, accent, shutter = H.roofSage, C.Red, C.RoofGreen
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
	-- and a dormer on the front slope too (right of the giant rod; roof surface: eave 23 at
	-- z −2.45, slope 14 / 19.45)
	local fz = 3.5
	dormer(F, "FrontDormer", "-z", fz, 9, h + 1.0 + (fz + 2.45) * 14 / 19.45, 7.4, 6, 12, {
		wall = wall,
		trim = trim,
		roof = roof,
	})
	F:box("Chimney", 12.6, h, 22.6, 16.4, ridgeTop + 1.6, 26.4, C.Brick)
	local cap = F:box("ChimneyCap", 12.2, ridgeTop + 1.6, 22.2, 16.8, ridgeTop + 2.6, 26.8, C.StoneDark)
	chimneySmoke(cap)

	-- the plaza front of the upper storey: timber studs, two shuttered windows with flower boxes
	-- and, between them, the sign hanging from two iron brackets under the eave
	for i, sx in { -1, 1 } do
		F:box(`FrontStud{i}`, sx * 8 - 0.6, OPEN + 0.7, -0.05, sx * 8 + 0.6, h - 0.5, 0.5, timber)
		window(F, `FrontUpWin{i}`, "-z", 0.4, sx * 13.4, OPEN + 2.0, 4.4, 4.8, {
			trim = trim,
			shutter = shutter,
			flowers = { C.Flowers[if sx < 0 then 1 else 3], C.Flowers[5] },
		})
		F:box(`SignBracket{i}`, sx * 4.6 - 0.25, h - 1.5, -3.2, sx * 4.6 + 0.25, h - 0.9, 0.4, C.Iron, NOSHADOW)
		F:box(`SignHanger{i}`, sx * 4.6 - 0.12, OPEN + 6.4, -2.75, sx * 4.6 + 0.12, h - 1.5, -2.55, C.Iron, DECOR)
	end
	signBoard(F, "Sign", -6.2, 6.2, OPEN + 2.2, OPEN + 5.6, -2.65, timber, trim, "УДОЧКИ", nil, C.Cream, C.Dark)
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
		F:box(`CaseRod{i}`, sx * 9.2, 3.25, 3.9, sx * (OH - 0.8), 3.6, 4.25, if sx < 0 then C.Navy else accent, DECOR)
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
	front: a rolled-up garage door under the lintel beam, the sign between two small iron-framed
	windows, a hoist beam with a pulley and a hook, the workbench with tools and a
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

	-- the sign over the opening between two small iron-framed windows, a hoist beam with a pulley
	-- and a hook out of the gable above the right one; the rolled-up garage door, wall lanterns
	signBoard(F, "Sign", -9, 9, OPEN + 1.9, h - 1.5, -0.15, C.Cream, timber, "МАСТЕРСКАЯ", nil, timber)
	for i, sx in { -1, 1 } do
		window(F, `FrontUpWin{i}`, "-z", 0.4, sx * 14.2, OPEN + 1.7, 4.4, 4.6, { trim = stone, cross = true })
	end
	F:box("HoistBeam", 13.6, h + 1.6, -6.4, 14.8, h + 2.6, -1.6, timber)
	F:box("HoistPulley", 13.7, h + 0.5, -6.0, 14.7, h + 1.6, -5.0, C.Iron, NOSHADOW)
	F:box("HoistRope", 14.1, OPEN + 3.4, -5.6, 14.3, h + 0.5, -5.4, C.Rope, DECOR)
	F:box("HoistHook", 13.8, OPEN + 2.6, -5.8, 14.6, OPEN + 3.4, -5.2, C.Iron, DECOR)
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
	F.model.PrimaryPart = plinth
	return F.model, bench
end

--[[
	FishMarket «РЫБНЫЙ РЫНОК» (sells fish): an open timber market hall — six wooden posts on stone
	pedestals, beams with knee braces, a plastered back wall with timber posts and shuttered
	windows (a fish relief between them, the side the bases see), a blue-grey slate roof with a
	ridge beam, plastered gables and a louvred lantern on the ridge carrying a fish weather vane,
	the sign on the front fascia (the roof and the lantern read above it), a blue/cream striped
	awning over the counters, a light plank ceiling under the roof. Wooden counters with ice and
	fish (a fishmonger's slab: heaped ice either side of the scales, each with a tray of four fish
	laid side by side, a lemon and parsley), the scales (Scales.SellPromptAttachment) on the front
	counter above a «Продать рыбу» panel, crates of fish, a «СВЕЖАЯ РЫБА» board inside, a hanging
	lamp, a barrel.
]]
local function buildFishMarket(hub: any, cf: any): (any, any)
	local F = newFrame(U.model(hub, "FishMarket"), cf, SHOP_SCALE)
	local roof, timber, post, trim = H.roofHarbour, C.WoodDark, C.Wood, C.Cream
	local blue = C.RoofBlue -- shutters, awning stripes, the fishes' fins: the market's accent
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
			shutter = blue,
			ledge = true,
		})
	end
	local relief = F:sub(CFrame.new(0, 9.6, D - 0.6) * CFrame.Angles(0, math.pi, 0))
	bigFish(relief, 0.48, {
		body = lerpColor(C.Cyan, C.RoofBlue, 0.3),
		head = lerpColor(C.Cyan, C.Cream, 0.3),
		fin = blue,
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

	-- the sign on the front fascia (the roof and its lantern read above it), the striped awning
	-- over the counters
	signBoard(F, "Sign", -13, 13, top - 0.9, top + 2.3, -3.6, trim, timber, "РЫБНЫЙ РЫНОК", nil, C.Navy)
	awning(F, "Awning", -HW - 0.8, HW + 0.8, top - 1.5, -1.5, 6, 2.0, 7, blue, trim)

	-- a fish jumping on the lantern, turning on its pole like a weather vane
	F:box("FishPole", -0.4, lanternTop, cz - 0.4, 0.4, lanternTop + 4.6, cz + 0.4, C.Iron, NOSHADOW)
	local vane = CFrame.new(0, lanternTop + 7.2, cz)
	local jumper = F:child("JumpingFish", vane * CFrame.Angles(0, 0, rad(-18)))
	local jumperBody = bigFish(jumper, 0.5, {
		body = lerpColor(C.Cyan, C.RoofBlue, 0.2),
		head = lerpColor(C.Cyan, C.Cream, 0.35),
		fin = blue,
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
	-- a fishmonger's slab: the ice heaped up either side of the scales, a tray of four fish laid
	-- side by side on each (heads to the customers), a lemon and a sprig of parsley at its end
	for j, sx in { -1, 1 } do
		F:box(`IceHeap{j}`, sx * 2.6, 4.2, 2.5, sx * 10.0, 4.75, 5.5, lerpColor(H.ice, C.White, 0.35))
		for k = 1, 4 do
			local n = (j * 3 + k) % #fishColors + 1
			trayFish(F, `Fish{j}_{k}`, sx * (3.5 + (k - 1) * 1.55), 4.75, 2.65, 2.75, fishColors[n])
		end
		F:box(`Lemon{j}`, sx * 9.0 - 0.45, 4.75, 2.9, sx * 9.0 + 0.45, 5.15, 3.8, C.Yellow, DECOR)
		F:box(`Parsley{j}`, sx * 9.2 - 0.5, 4.75, 4.2, sx * 9.2 + 0.5, 5.4, 5.2, C.Leaf2, DECOR)
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
		F:prop("crate", sx * 12.15, FL, 4.1, 0, { size = 3.4, color = C.Wood, seed = 30 + i })
		smallFish(F, sx * 12.15, FL + 3.45, 4.1, 2.6, fishColors[i + 2])
	end
	local lamp = F:box("CeilingLamp", -1.6, top - 3.2, 13, 1.6, top - 2.0, 16, C.Glow, NEON_DECOR)
	F:box("LampCord", -0.15, top - 2.0, 14.35, 0.15, top + 0.4, 14.65, C.Dark, DECOR)
	pointLight(lamp, 16, 1.3)
	-- a light plank ceiling under the roof keeps the stall bright and open
	F:box("Soffit", -px, top + 0.05, -1.2, px, top + 0.3, D - 3.4, C.Plank, NOSHADOW)

	-- outside: a barrel
	F:prop("barrel", -19.4, FL, -5.6, 0, { color = C.Wood, seed = 14 })
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
	cream limestone star in its dark outline, cream rays with dark edges from its diagonal points to
	the shop porches and the fun fair arch, and a terracotta ring (r 47..52) crossing under the
	rays and the runners. The avenues' terracotta runners (buildAvenues) start on the star's axis
	points and carry the walk on to every bridge. Each layer stands at least 0.06 above the one
	under it (paving 0.2, ring 0.32, outline 0.44, star 0.56, runner 0.62), so no two colours share
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
	for _, layer in { { "StarEdge", STAR + STAR_EDGE, 0.44, H.paveDark }, { "Star", STAR, 0.56, H.medallion } } do
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
		R:box(`Ray{k + 1}`, -RAY_W / 2, 0.06, rayIn, RAY_W / 2, 0.56, rayOut, H.medallion, FLAT)
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
	«Золотая рыбка» tower, the island's landmark and the tallest thing on it (~108 studs, seen
	from every base, pier and bridge): an octagonal brick basin with a blue tile band, gold
	corner bands, a cream rim and stone seats with plank tops round a see-through pool; three
	tiers (the middle one turned 45°) with tile bands, stone cornices under wide cream basin lips
	and pools on them, darker buttresses on the bottom tier's corners, the water pouring over
	every lip out of a gold spout head and falling free in front of the face into the pool below
	(a light streak down the curtains, ragged foam where they meet the basin); a stone spire with
	a gold-framed fish medallion on every face, a cream balcony ring on corbels with a balustrade
	and gold finials, a plaster shaft, a lantern colonnade (eight slim columns round the glowing
	gold core), an onion dome of verdigris on a gold band and a stepped water spout carrying a
	huge crowned golden fish (tilted nose-up) that spits an arc of water and slowly circles about
	the spout (Spin), so every avenue sees it from all sides. Particles (no parts): gold sparkles
	round the fish, spray from the spout, drops from the fish's jet, mist at the basin foam.
	~185 parts.
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
		along(d, -half, half, r0, r1, -0.3, 3.4, `BasinWall{i}`, H.basinBrick)
		along(d, -half - 0.4, half + 0.4, r0 - 0.4, r1 + 0.4, 3.4, 4.1, `BasinRim{i}`, rimC)
		-- the band stops 0.12 short of the wall ends (no shared plane with the end faces)
		along(d, -half + 0.12, half - 0.12, r1 - 0.3, r1 + 0.15, 2.3, 3.1, `BasinBand{i}`, tile, NOSHADOW)
		-- a stone seat with a plank top along the wall: the basin is a place to sit
		along(d, -12, 12, r1 - 0.2, r1 + 1.9, -0.3, 1.5, `BasinSeat{i}`, C.Limestone)
		along(d, -11.6, 11.6, r1 - 0.1, r1 + 1.75, 1.5, 1.95, `BasinSeatTop{i}`, C.Wood, NOSHADOW)
	end
	for i, d in DIAG do
		local c0, c1 = half, r0 + 1.2
		F:box(`BasinCorner{i}`, d[1] * c0, -0.3, d[2] * c0, d[1] * c1, 3.4, d[2] * c1, H.basinBrick)
		F:box(
			`BasinCornerBand{i}`,
			d[1] * (c0 + 0.6),
			2.3,
			d[2] * (c0 + 0.6),
			d[1] * (c1 + 0.15),
			3.1,
			d[2] * (c1 + 0.15),
			H.goldDeep,
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
		Three stepped tiers, the middle one turned 45° (an octagonal silhouette from every side):
		half width w, from y0 (the pool top of the tier below) to y1; a band on the faces, a stone
		cornice under a wide cream basin lip overhanging the faces by ov, and a pool on the lip. On
		every face the water pours over the lip out of a gold spout head and falls free, ~2 studs
		proud of the face, into the pool below (a light streak down each curtain; on the basin,
		ragged foam where it lands); darker buttresses frame the bottom tier's corners.
	]]
	local y0 = 0.4
	local poolBelow = 2.6 -- basin water top
	local T45 = newFrame(F.model, F.cf * CFrame.Angles(0, rad(45), 0))
	for k, t in
		{
			{ 13, 14, stone, tile, 2.8, 3.4, false },
			{ 8.4, 12, C.PlasterShade, H.ring, 2.2, 2.4, true },
			{ 6.0, 10, stone, tile, 1.9, 1.6, false },
		}
	do
		local w, h, wall, band, ov, cw = t[1], t[2], t[3], t[4], t[5], t[6]
		local T = if t[7] then T45 else F
		local function side(
			d: { number },
			a0: number,
			a1: number,
			b0: number,
			b1: number,
			ya: number,
			yb: number,
			name: string,
			c: any,
			ex: { [string]: any }?
		): any
			if d[1] ~= 0 then
				return T:box(name, d[1] * b0, ya, a0, d[1] * b1, yb, a1, c, ex)
			end
			return T:box(name, a0, ya, d[2] * b0, a1, yb, d[2] * b1, c, ex)
		end
		local y1 = y0 + h
		local lip = w + ov
		T:box(`Tier{k}`, -w, y0, -w, w, y1, w, wall)
		T:box(`Tier{k}Band`, -w - 0.3, y0 + h * 0.42, -w - 0.3, w + 0.3, y0 + h * 0.42 + 1.6, w + 0.3, band, NOSHADOW)
		local cor = w + ov * 0.55
		T:box(`Tier{k}Cornice`, -cor, y1 - 1.6, -cor, cor, y1 - 0.6, cor, lerpColor(stone, C.Stone, 0.55))
		T:box(`Tier{k}Rim`, -lip, y1 - 0.6, -lip, lip, y1 + 0.8, lip, rimC)
		T:box(`Tier{k}Pool`, -lip + 0.6, y1 + 0.8, -lip + 0.6, lip - 0.6, y1 + 1.2, lip - 0.6, H.water, FLOW)
		if k == 1 then
			for i, d in DIAG do
				local b0, b1 = w - 1.7, w + 0.75
				F:box(
					`Tier{k}Buttress{i}`,
					d[1] * b0,
					y0,
					d[2] * b0,
					d[1] * b1,
					y1 - 1.6,
					d[2] * b1,
					lerpColor(stone, C.Stone, 0.55)
				)
			end
		end
		for i, d in AXES do
			side(d, -cw, cw, lip - 0.75, lip - 0.15, poolBelow - 0.2, y1 - 0.6, `Tier{k}Curtain{i}`, H.cascade, FLOW)
			side(d, -cw - 0.45, cw + 0.45, lip - 0.5, lip + 0.55, y1 - 0.35, y1 + 1.05, `Tier{k}Spout{i}`, H.goldDeep)
			side(d, -cw * 0.35, cw * 0.35, lip - 0.2, lip, poolBelow, y1 - 0.9, `Tier{k}Streak{i}`, H.streak, FLOW)
			if k == 1 then
				-- ragged foam where the curtain lands (bottoms 0.12+ above the curtain's)
				local foam = side(d, -cw - 0.7, cw + 0.7, lip - 1.6, lip + 0.5, 2.52, 3.3, `Foam{i}`, C.Foam, DECOR)
				side(d, -cw + 0.4, cw + 1.6, lip + 0.3, lip + 1.5, 2.48, 2.95, `FoamOut{i}`, C.Foam, DECOR)
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
		poolBelow = y1 + 1.2
		y0 = poolBelow
	end

	--[[
		Spire on the top pool (39.4): a stone foot, a sandstone shaft with a tile band and a slit
		window on every side, a cream collar, a plastered shaft with a tile band and the glowing
		gold ring, then the verdigris cap.
	]]
	local base = y0 -- 39.4
	F:box("SpireFoot", -5.6, base - 0.4, -5.6, 5.6, base + 1.6, 5.6, C.Stone)
	F:box("Shaft1", -4.8, base + 1.6, -4.8, 4.8, base + 15.6, 4.8, stone)
	F:box("ShaftStripe", -5.05, base + 3.2, -5.05, 5.05, base + 4.4, 5.05, tile, NOSHADOW)
	-- a medallion on every face: a gold frame, a blue tile face and a little gold fish
	local my = base + 9.6
	for i, d in AXES do
		along(d, -2.6, 2.6, 4.6, 5.1, my - 2.6, my + 2.6, `Medallion{i}`, H.goldDeep, NOSHADOW)
		along(d, -2.0, 2.0, 4.7, 5.3, my - 2.0, my + 2.0, `MedallionFace{i}`, tile, NOSHADOW)
		along(d, -1.3, 1.3, 4.8, 5.5, my - 0.6, my + 0.6, `MedallionFish{i}`, H.gold, DECOR)
	end
	-- the balcony ring round the collar: a cream stone slab on corbels, a balustrade with corner
	-- posts carrying gold finials (seen from every base: the tower gets a waist)
	local by = base + 15.6
	F:box("Balcony", -8.2, by - 1.0, -8.2, 8.2, by, 8.2, C.Limestone)
	for i, d in AXES do
		along(d, -1.2, 1.2, 4.6, 7.6, by - 3.0, by - 1.0, `Corbel{i}`, stone)
		along(d, -8.2, 8.2, 7.5, 8.1, by + 2.7, by + 3.3, `Balustrade{i}`, C.Limestone, NOSHADOW)
		along(d, -0.5, 0.5, 7.4, 8.0, by, by + 2.7, `Baluster{i}`, C.Limestone, NOSHADOW)
	end
	for i, d in DIAG do
		F:box(`BalconyPost{i}`, d[1] * 7.2, by, d[2] * 7.2, d[1] * 8.4, by + 3.9, d[2] * 8.4, C.Limestone)
		F:box(`Finial{i}`, d[1] * 7.35, by + 3.9, d[2] * 7.35, d[1] * 8.25, by + 4.8, d[2] * 8.25, H.goldDeep, DECOR)
	end
	F:box("Collar", -5.6, by, -5.6, 5.6, by + 1.6, 5.6, rimC)
	-- the plaster shaft, then an open lantern stage: a colonnade of eight slim stone columns (two on
	-- every face, the corners left open) round the glowing gold core under a cream cornice
	F:box("Shaft2", -4, base + 17.2, -4, 4, base + 23.4, 4, C.Plaster)
	F:box("ShaftBand", -4.25, base + 19.2, -4.25, 4.25, base + 20.6, 4.25, tile, NOSHADOW)
	F:box("LanternSill", -4.7, base + 23.4, -4.7, 4.7, base + 24.2, 4.7, rimC)
	for i, d in AXES do
		for j, a in { -2.2, 2.2 } do
			along(d, a - 0.5, a + 0.5, 3.4, 4.4, base + 24.2, base + 27.9, `LanternColumn{i}_{j}`, C.Limestone)
		end
	end
	local ring = F:box("GoldRing", -2.3, base + 24.2, -2.3, 2.3, base + 27.9, 2.3, C.GoldLight, NEON)
	pointLight(ring, 16, 1.4, C.Glow)
	F:box("LanternHead", -4.9, base + 27.9, -4.9, 4.9, base + 28.6, 4.9, rimC)

	-- an onion dome of verdigris copper (square layers turned 45° to each other, so it reads round
	-- from every side) on a gold band, then the stepped spout that carries the fish
	local top = base + 28.6
	F:box("DomeBand", -4.5, top, -4.5, 4.5, top + 0.6, 4.5, H.goldDeep, NOSHADOW)
	local vd, vl = shade(H.verdigris, 0.9), H.verdigris
	local dome = {
		{ 4.2, 0.6, 2.0, vd, false },
		{ 4.6, 1.0, 2.6, vl, true },
		{ 3.4, 2.6, 3.8, vl, false },
		{ 3.0, 3.0, 4.6, vd, true },
		{ 1.8, 3.8, 5.6, vl, false },
	}
	for k, l in dome do
		local Dm = if l[5] then T45 else F
		Dm:box(`Dome{k}`, -l[1], top + l[2], -l[1], l[1], top + l[3], l[1], l[4])
	end
	top += 5.6 -- the dome's tip
	local spout = F:box("Spout1", -1.6, top - 0.4, -1.6, 1.6, top + 3.2, 1.6, H.waterLight, FLOW)
	F:box("Spout2", -1.1, top + 3.2, -1.1, 1.1, top + 6.6, 1.1, H.waterLight, FLOW)
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

	-- «Золотая рыбка»: tilted nose-up 26°; as it turns, its lowest point stays a few studs above
	-- the dome's tip (the spout reaches into its belly) and its tail sweeps clear of the spire
	local s, fishY = 1.7, top + 15.5
	local fishCf = CFrame.new(0, fishY, 0) * CFrame.Angles(0, rad(45), 0)
	local fish = F:child("GoldenFish", fishCf * CFrame.Angles(0, 0, rad(-26)))
	-- (no Reflectance: in Studio it mirrors the blue sky into the gold and turns it khaki)
	local body = bigFish(fish, s, {
		body = H.gold,
		head = H.goldHead,
		belly = H.goldBelly,
		fin = H.goldFin,
		lips = lerpColor(C.Orange, C.Red, 0.3),
		spots = H.goldScale,
	}, { crown = true })
	-- a pale gold shine along its back
	fish:box("BackShine", -7 * s, 4.75 * s, -2.3 * s, 3.4 * s, 5.4 * s, 2.3 * s, H.goldLight, DECOR)
	-- a warm light just under the belly (it turns with the fish) lifts the underside the players
	-- see from the plaza: the shaded gold stays gold instead of going olive
	local under = U.new("Attachment", { Name = "UnderGlow", CFrame = CFrame.new(-2 * s, -7.6 * s, 0) }, body)
	pointLight(under, 16, 1.6, lerpColor(C.LightColor, C.Glow, 0.4))
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
	bridge and every counter stay clear (the garden walks carry all eight base lanes on outwards).
]]
local function buildPlazaFurniture(hub: any, G: number)
	local m = U.model(hub, "PlazaFurniture")
	for k = 0, 3 do
		local a = 22.5 + k * 90
		parkBench(m, U.polarCFrame(a, 35, G + 0.2), 8, C.Wood)
		streetLamp(m, U.polarCFrame(a + 45, 36, G + 0.2), 10, C.Iron, true)
	end
end

--------------------------------------------------------------------------------
-- Avenues (θ = 0/90/180/270): paving, lamps with bunting, gates, palms
--------------------------------------------------------------------------------

local AVENUE_START = PLAZA_R - 4

-- per avenue (BridgeAngles order): the street trees (a Props broadleaf: "round" with a leaf
-- palette, or "cherry") and the flower beds' two jewel tones (Palette.Flowers: 1 red, 2 yellow,
-- 3 pink, 4 violet, 5 white, 6 orange, 7 blue); the welcome gate's flower boxes repeat them
local FRONTAGE = {
	{ tree = "round", palette = "green", beds = { 3, 2 } },
	{ tree = "cherry", beds = { 4, 5 } },
	{ tree = "round", palette = "mint", beds = { 1, 2 } },
	{ tree = "cherry", beds = { 7, 6 } },
}

--[[
	Welcome gate over an avenue at radial distance z, the hub's showpiece at every bridge: two
	stepped piers of cream limestone on a stone plinth (a stone string course where they step in,
	a tile band in the district colour of the bridge and gateway — the gate's only strong colour —
	a stone cap and a ball finial with a gold knob), on the bridge side of each pier an arched niche
	with a glowing lantern, on the plaza side a flower box in the street's colours; between them a
	timber beam carrying the board «ОСТРОВ РЫБАКОВ» (bridge side) / «ХОРОШЕГО КЛЁВА!» (plaza side)
	under a little gabled roof of moss slate. Low (ridge ≈ 22 above the avenue, 11 clear under the
	beam): from the bridge the whole golden fish shows above it. 34 parts.
]]
local function welcomeGate(F: any, z: number, accent: any, blooms: { any })
	local m = F:child("WelcomeGate")
	local stone, cream = C.Stone, C.Limestone
	for i, sx in { -1, 1 } do
		local cx = sx * 17.4 -- the pier's centre line
		m:box(`GatePlinth{i}`, cx - 2.9, -0.3, z - 2.9, cx + 2.9, 1.8, z + 2.9, stone)
		m:box(`GatePier{i}`, cx - 2.4, 1.8, z - 2.35, cx + 2.4, 11.4, z + 2.35, cream)
		m:box(`GateCourse{i}`, cx - 2.7, 11.4, z - 2.65, cx + 2.7, 12.3, z + 2.65, C.StoneLight)
		m:box(`GatePierTop{i}`, cx - 1.9, 12.3, z - 1.95, cx + 1.9, 20.4, z + 1.95, cream)
		m:box(`GateBand{i}`, cx - 2.05, 16.6, z - 2.1, cx + 2.05, 17.8, z + 2.1, accent, NOSHADOW)
		m:box(`GateCap{i}`, cx - 2.4, 20.4, z - 2.45, cx + 2.4, 21.4, z + 2.45, stone)
		m:box(`GateFinial{i}`, cx - 0.95, 21.4, z - 0.95, cx + 0.95, 23.2, z + 0.95, C.StoneLight)
		m:box(`GateKnob{i}`, cx - 0.35, 23.2, z - 0.35, cx + 0.35, 23.9, z + 0.35, H.goldDeep, DECOR)
		-- the niche on the bridge side: a dark recess with an arched head and a lantern in it
		local nz = z + 2.35
		local dark = shade(C.StoneDark, 0.72)
		m:box(`Niche{i}`, cx - 1.15, 4.2, nz - 0.05, cx + 1.15, 8.4, nz + 0.12, dark, NOSHADOW)
		m:box(`NicheHead{i}`, cx - 0.7, 8.4, nz - 0.05, cx + 0.7, 9.2, nz + 0.12, dark, NOSHADOW)
		m:box(`NicheLamp{i}`, cx - 0.6, 5.0, nz + 0.05, cx + 0.6, 6.9, nz + 0.75, C.Glow, NEON_DECOR)
		-- the flower box on the plaza side
		local fz = z - 2.35
		m:box(`FlowerBox{i}`, cx - 1.9, 4.6, fz - 1.3, cx + 1.9, 5.8, fz, C.Wood)
		m:box(`FlowerBoxGreens{i}`, cx - 1.7, 5.8, fz - 1.1, cx + 1.7, 6.4, fz - 0.15, C.Leaf1, DECOR)
		for k, dx in { -0.9, 0.9 } do
			local top = 7.0 + (k - 1) * 0.25
			m:box(
				`FlowerBoxBloom{i}_{k}`,
				cx + dx - 0.55,
				6.1,
				fz - 1.15,
				cx + dx + 0.55,
				top,
				fz - 0.1,
				blooms[k],
				DECOR
			)
		end
	end
	m:box("GateBeam", -15.1, 11.5, z - 1.2, 15.1, 12.9, z + 1.2, C.WoodDark)
	-- the board's front (−Z) faces the tower, its back the bridge
	signBoard(
		m,
		"GateSign",
		-11,
		11,
		13.6,
		18.4,
		z,
		C.Cream,
		C.WoodDark,
		"ХОРОШЕГО КЛЁВА!",
		"ОСТРОВ РЫБАКОВ",
		C.Navy
	)
	gableRoof(m, "GateRoof", 0, z, "x", 12.0, 0.9, 19.2, 2.5, {
		roof = H.roofSage,
		ridge = C.WoodDark,
		gables = {},
		noEaves = true,
		ov = 1.4,
		og = 0.7,
	})
end

--[[
	The four avenues from the plaza to the bridges: warm grey-beige cobbles between cream kerbs, a
	terracotta brick runner on a dark cobble outline from the plaza star to the bridge, cream cross
	bands every 16 studs (the last one under the welcome gate), lamps with bunting hung high, short
	clipped box hedges along both sides with stone planters carrying topiary balls in the gaps, and
	the welcome gate. Paving layers: cobbles 0.35, outline 0.5, runner 0.62, bands 0.74 (no two
	colours share a plane; the runner stands over the plaza star, 0.56).
]]
local function buildAvenues(hub: any, cfg: any, G: number)
	local root = U.model(hub, "Avenues")
	local endZ, gateZ = L.avenueEnd, L.gate
	for i, angle in cfg.BridgeAngles do
		local F = radialFrame(U.model(root, `Avenue{i}`), angle, G)
		local theme = Promenade.Themes[angle % 360]
		local accent = if theme then theme.color else C.Orange
		local look = FRONTAGE[(i - 1) % #FRONTAGE + 1]
		F:box("Bricks", -11, -0.3, AVENUE_START, 11, 0.35, endZ, H.street, FLAT)
		-- the runner starts on the plaza star's axis point and stops just short of the bridge deck
		F:box("RunnerEdge", -5, -0.3, STAR_TIP - 4.6, 5, 0.5, endZ - 0.6, H.paveDark, FLAT)
		F:box("Runner", -4, -0.3, STAR_TIP - 4, 4, 0.62, endZ - 1.2, H.runner, FLAT)
		for j, sx in { -1, 1 } do
			F:box(`Kerb{j}`, sx * 11, -0.3, AVENUE_START + 4, sx * 12.4, 0.8, endZ, H.kerb, FLAT)
		end
		for k, z in { 76, 92, 108, 124, gateZ } do
			F:box(`Band{k}`, -10.95, -0.3, z - 0.7, 10.95, 0.74, z + 0.7, H.kerb, FLAT)
		end
		-- one pair of lamps carries iron masts with bunting high over the avenue (13+ studs above
		-- the paving: it frames the view of the tower instead of covering it); on the spawn avenue
		-- (θ 180) it stands behind the spawn
		local spawnAvenue = angle % 360 == 180
		local lampZ = if spawnAvenue then 118 else 86
		local tops = {}
		for j, sx in { -1, 1 } do
			local lamp = streetLamp(F.model, F:at(sx * 14.2, 0, lampZ), 11, C.Iron)
			local Lm = newFrame(lamp, F:world(CFrame.new(sx * 14.2, 0, lampZ)))
			Lm:box("Mast", -0.3, 14.7, -0.3, 0.3, 19.2, 0.3, C.Iron, NOSHADOW)
			Lm:box("MastKnob", -0.55, 19.2, -0.55, 0.55, 20.0, 0.55, H.goldDeep, DECOR)
			tops[j] = F:point(sx * 14.2, 18.9, lampZ)
		end
		pennants(F.model, tops[1], tops[2], 6, 1.4, 1.3, 1.7, i * 3)
		-- short clipped box hedges outside the kerbs, broken by the lamp pair and by stone planters
		-- with topiary balls (the beds, benches and street trees behind them: buildFrontages)
		local hedges = if spawnAvenue
			then { { 70, 88 }, { 94, 112.5 }, { 123.5, 134 } }
			else { { 70, 81 }, { 91, 108.5 }, { 114.5, 134 } }
		local planters = if spawnAvenue then { 91 } else { 111.5 }
		for j, sx in { -1, 1 } do
			-- (the middle block a little taller and darker: a clipped rhythm, not one long wall)
			for k, zz in hedges do
				local top = if k == 2 then 2.3 else 1.9
				F:box(`Hedge{j}_{k}`, sx * 15, -0.3, zz[1], sx * 17.6, top, zz[2], if k == 2 then C.Leaf0 else C.Leaf1)
			end
			for k, z in planters do
				F:box(`Planter{j}_{k}`, sx * 15.1, -0.3, z - 1.25, sx * 17.5, 1.5, z + 1.25, C.Limestone)
				F:box(`Topiary{j}_{k}`, sx * 14.95, 1.5, z - 1.35, sx * 17.65, 4.2, z + 1.35, C.Leaf2, DECOR)
			end
		end
		welcomeGate(F, gateZ, accent, { C.Flowers[look.beds[1]], C.Flowers[look.beds[2]] })
		-- (the tall palms framing the bridge landing come with the beach: buildLandingPalms)
	end
end

--------------------------------------------------------------------------------
-- Fun fair (θ 225): entrance arch, food stalls, Ferris wheel
--------------------------------------------------------------------------------

--[[
	The fun fair's food stalls, each its own shape (frame origin = its foot on the fair ground,
	−Z = the customers on the path), its name on its front:
	"icecream" — a cream ice-cream cart on a pair of wheels with a pink band, a push handle, a
	striped parasol and a giant cone on its lid (12 parts);
	"popcorn" — a red popcorn wagon on two axles with a cream name band, a glass case heaped with
	popcorn and a striped little roof (11 parts);
	"lemonade" — a wooden lemonade stand with a yellow front, a striped awning on two posts, a jug
	and cups on the counter and a big lemon sign on top (12 parts).
]]
local function foodStall(parent: any, cf: any, name: string, text: string, main: any, kind: string)
	local F = newFrame(U.model(parent, name), cf)
	-- a wheel pair: one cylinder across the body, its ends showing on both long faces
	local function axle(nm: string, x: number, y: number, d: number, z: number)
		U.part(
			F.model,
			nm,
			V(z * 2, d, d),
			F.cf * CFrame.new(x, y, 0) * CFrame.Angles(0, rad(90), 0),
			C.Iron,
			nil,
			{ Shape = Enum.PartType.Cylinder }
		)
	end
	local main0
	if kind == "icecream" then
		main0 = F:box("Cart", -3.4, 1.4, -1.8, 3.4, 4.2, 1.8, C.Cream)
		local band = F:box("CartBand", -3.55, 2.2, -1.95, 3.55, 3.7, 1.95, main, NOSHADOW)
		signText(band, Enum.NormalId.Front, text, C.Cream)
		F:box("CartLid", -3.7, 4.2, -2.1, 3.7, 4.7, 2.1, C.WoodLight)
		axle("Wheels", -1.4, 1.35, 2.6, 2.2)
		F:box("CartLeg", 2.5, -0.3, -0.4, 3.1, 1.4, 0.4, C.WoodDark, NOSHADOW)
		F:box("Handle", 3.4, 3.4, -1.2, 5.4, 3.8, 1.2, C.WoodDark, NOSHADOW)
		F:box("ParasolPole", -2.65, 4.7, 0.95, -2.35, 10.6, 1.25, C.White, NOSHADOW)
		F:box("Parasol", -6.1, 9.6, -2.4, 1.1, 10.2, 4.6, main, { CanCollide = false })
		F:box("ParasolTop", -4.3, 10.2, -0.6, -0.7, 10.8, 2.8, C.Cream, DECOR)
		F:box("Cone", 1.5, 4.7, -0.5, 2.5, 6.1, 0.5, C.Straw)
		F:box("Scoop1", 1.1, 6.1, -0.9, 2.9, 7.5, 0.9, C.Pink)
		F:box("Scoop2", 1.4, 7.5, -0.6, 2.6, 8.4, 0.6, C.Cream, DECOR)
	elseif kind == "popcorn" then
		main0 = F:box("Wagon", -3.6, 1.6, -2.2, 3.6, 4.4, 2.2, main)
		local band = F:box("NameBand", -3.0, 2.5, -2.4, 3.0, 3.7, -2.15, C.Cream, NOSHADOW)
		signText(band, Enum.NormalId.Front, text, shade(main, 0.75))
		for i, x in { -2.2, 2.2 } do
			axle(`Wheels{i}`, x, 1.25, 2.4, 2.5)
		end
		F:box("Case", -2.6, 4.4, -1.6, 2.6, 7.2, 1.6, C.Glass, GLASS)
		F:box("Popcorn", -2.3, 4.4, -1.3, 2.3, 5.9, 1.3, C.StrawLight, DECOR)
		gableRoof(F, "Roof", 0, 0, "x", 3.0, 2.0, 7.2, 1.4, {
			roof = main,
			ridge = C.Cream,
			gables = {},
			noEaves = true,
			ov = 0.5,
			og = 0.3,
		})
		F:box("TowBar", 3.6, 1.9, -0.25, 5.8, 2.3, 0.25, C.WoodDark, NOSHADOW)
	else
		main0 = F:box("Counter", -4.4, -0.3, -1.4, 4.4, 3.6, 1.4, C.Wood)
		local front = F:box("Front", -3.8, 1.0, -1.6, 3.8, 3.0, -1.35, main, NOSHADOW)
		signText(front, Enum.NormalId.Front, text, shade(C.WoodDark, 0.9))
		F:box("CounterTop", -4.8, 3.6, -1.8, 4.8, 4.1, 1.8, C.WoodLight)
		for i, sx in { -1, 1 } do
			F:box(`Post{i}`, sx * 4.2 - 0.35, 4.1, 0.9, sx * 4.2 + 0.35, 9.4, 1.6, C.WoodDark)
		end
		F:wedge("Awning", -4.9, 7.6, -3.0, 4.9, 9.2, 1.6, main, "+z", NOSHADOW)
		F:box("AwningValance", -4.9, 6.9, -3.25, 4.9, 7.65, -2.95, C.Cream, DECOR)
		F:box("Jug", -2.6, 4.1, -0.6, -1.6, 5.6, 0.4, lerpColor(C.Yellow, C.Glass, 0.35))
		F:box("Cups", 1.2, 4.1, -0.7, 3.0, 4.9, 0.1, C.Cream, DECOR)
		F:box("Lemon", -2.0, 9.4, 0.9, 2.0, 12.0, 1.7, C.Yellow)
		F:box("LemonSlice", -1.3, 9.9, 0.7, 1.3, 11.5, 0.95, lerpColor(C.Yellow, C.Cream, 0.55), DECOR)
		F:box("LemonLeaf", 1.4, 11.6, 1.0, 3.0, 12.4, 1.6, C.Leaf2, DECOR)
	end
	F.model.PrimaryPart = main0
end

--[[
	Entrance arch of the fun fair over its path at radial distance z: white posts on stone feet,
	each striped with two teal bands and lit by a row of bulbs up its inner face, teal caps with gold
	knobs, a timber beam with a scalloped teal valance under it, and the board «АТТРАКЦИОНЫ» on
	both faces resting on it. 20 parts.
]]
local function fairArch(F: any, z: number)
	local m = F:child("FairArch")
	for i, sx in { -1, 1 } do
		m:box(`ArchFoot{i}`, sx * 7.6, -0.3, z - 1.9, sx * 11.6, 1.6, z + 1.9, C.Stone)
		m:box(`ArchPost{i}`, sx * 8.2, 1.6, z - 1.3, sx * 11.0, 19, z + 1.3, C.White)
		for k, y in { 5.0, 10.6 } do
			m:box(`ArchStripe{i}_{k}`, sx * 8.05, y, z - 1.45, sx * 11.15, y + 1.4, z + 1.45, H.fair, NOSHADOW)
		end
		m:box(`ArchBulbs{i}`, sx * 7.95, 2.6, z - 0.3, sx * 8.25, 14.2, z + 0.3, C.Glow, NEON_DECOR)
		m:box(`ArchCap{i}`, sx * 7.8, 19, z - 1.7, sx * 11.4, 20.2, z + 1.7, H.fair)
		m:box(`ArchKnob{i}`, sx * 8.9, 20.2, z - 0.7, sx * 10.3, 21.6, z + 0.7, H.goldDeep, DECOR)
	end
	m:box("ArchBeam", -8.2, 14.4, z - 1.0, 8.2, 15.6, z + 1.0, C.WoodDark)
	for k, x in { -5.4, 0, 5.4 } do
		m:box(
			`ArchScallop{k}`,
			x - 2.2,
			13.3,
			z - 0.8,
			x + 2.2,
			14.45,
			z + 0.8,
			if k == 2 then C.Cream else H.fair,
			DECOR
		)
	end
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
	«ИГРЫ» game tent at the fun fair (frame origin = tent centre on the ground, −Z = players): a
	plank floor, a counter with a red stripe, four dark posts, a striped canvas roof (red and cream
	wedge stripes on both slopes) with a red valance, the sign on the ridge, a canvas back wall
	with three targets under a prize shelf of plush fish, and a string of bulbs under the front
	eave. ~38 parts.
]]
local function gameTent(parent: any, cf: any)
	local F = newFrame(U.model(parent, "GameBooth"), cf)
	local accent = C.Red
	local base = F:box("Floor", -7, -0.3, -5, 7, 0.5, 5, C.Plank, FLAT)
	F:box("BackWall", -6.6, 0.5, 3.8, 6.6, 7.6, 4.6, C.Canvas)
	F:box("Counter", -6.4, 0.5, -4.8, 6.4, 3.6, -3.2, C.Wood)
	F:box("CounterTop", -6.8, 3.6, -5.1, 6.8, 4.1, -2.9, C.WoodLight)
	F:box("CounterStripe", -6.0, 1.5, -4.95, 6.0, 2.3, -4.7, accent, NOSHADOW)
	for i, d in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		-- (0.45 deep either side of 4.2: the back posts stand proud of the back wall, no shared face)
		F:box(`Post{i}`, d[1] * 6.6 - 0.4, 0.5, d[2] * 4.2 - 0.45, d[1] * 6.6 + 0.4, 7.6, d[2] * 4.2 + 0.45, C.WoodDark)
	end
	local n, x0, x1 = 5, -7.6, 7.6
	for k = 0, n - 1 do
		local a, b = x0 + k * (x1 - x0) / n, x0 + (k + 1) * (x1 - x0) / n
		local col = if k % 2 == 0 then accent else C.Cream
		F:wedge(`RoofA{k + 1}`, a, 7.6, -5.8, b, 11.0, 0, col, "+z", NOSHADOW)
		F:wedge(`RoofB{k + 1}`, a, 7.6, 0, b, 11.0, 5.8, col, "-z", NOSHADOW)
	end
	F:box("Valance", -7.6, 6.8, -6.05, 7.6, 7.6, -5.75, accent, NOSHADOW)
	signBoard(F, "Sign", -3.4, 3.4, 11.5, 14.1, 0, C.Cream, C.WoodDark, "ИГРЫ", "ИГРЫ", accent)
	local bulbs = F:box("Bulbs", -7.0, 6.35, -5.95, 7.0, 6.82, -5.55, C.Glow, NEON_DECOR)
	pointLight(bulbs, 16, 1.2)
	-- targets on the back wall under the prize shelf
	for i, x in { -4.2, 0, 4.2 } do
		F:box(`Target{i}`, x - 1.3, 1.9, 3.55, x + 1.3, 4.5, 3.8, accent, NOSHADOW)
		F:box(`Bullseye{i}`, x - 0.5, 2.7, 3.4, x + 0.5, 3.7, 3.65, C.White, DECOR)
	end
	F:box("PrizeShelf", -6.2, 5.2, 2.6, 6.2, 5.6, 3.8, C.WoodLight, NOSHADOW)
	-- a red banner on the back of the tent
	local banner = F:box("BackBanner", -4.4, 2.4, 4.55, 4.4, 6.6, 4.8, accent, NOSHADOW)
	signText(banner, Enum.NormalId.Back, "ИГРЫ", C.Cream)
	local prizes = { H.fish[4], C.Orange, C.Purple }
	for j, x in { -4, 0, 4 } do
		smallFish(F, x, 5.6, 3.2, 3.0, prizes[j])
	end
	F.model.PrimaryPart = base
end

--[[
	Carousel at the end of the fair's path, the fair's focal point (frame origin = its centre on the
	ground, built 1.35× big): a cream stone plinth (two crossed squares) and the turning top, a Model
	"Top" with a Spin attribute (the client turns it about the vertical): a plank turntable (two
	crossed squares), a cream column with a gold band, eight riders on gold poles (little boats on
	the axes, cups on the diagonals) and a two-tier striped canopy in teal and cream (squares turned
	45° to each other) over a cream rim hung with a scalloped valance, and a gold finial. ~37 parts.
]]
local CAROUSEL_SCALE = 1.35
local function carousel(parent: any, cf: any)
	local S = CAROUSEL_SCALE
	local F = newFrame(U.model(parent, "Carousel"), cf, S)
	local turned = newFrame(F.model, cf * CFrame.Angles(0, rad(45), 0), S)
	local plinth = F:box("Plinth", -7.2, -0.3, -7.2, 7.2, 1.0, 7.2, C.Limestone)
	turned:box("Plinth2", -7.2, -0.32, -7.2, 7.2, 0.98, 7.2, C.Limestone)
	F.model.PrimaryPart = plinth
	local top = U.model(F.model, "Top")
	local T = newFrame(top, cf, S)
	local T45 = newFrame(top, cf * CFrame.Angles(0, rad(45), 0), S)
	T:box("Turntable", -6.6, 1.0, -6.6, 6.6, 1.5, 6.6, C.Plank)
	T45:box("Turntable2", -6.6, 1.02, -6.6, 6.6, 1.48, 6.6, C.Plank)
	local column = T:box("Column", -1.0, 1.5, -1.0, 1.0, 9.6, 1.0, C.Cream)
	T:box("ColumnBand", -1.15, 4.6, -1.15, 1.15, 5.4, 1.15, H.goldDeep, NOSHADOW)
	-- the canopy: a cream rim with a scalloped valance (two scallops on every side, teal and cream)
	T:box("CanopyRim", -7.9, 9.2, -7.9, 7.9, 9.7, 7.9, C.Cream, NOSHADOW)
	for i, d in { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } } do
		for j, a in { -3.6, 3.6 } do
			local col = if j == 1 then H.fair else C.Cream
			local lo, hi = 8.3, 9.25
			if d[1] ~= 0 then
				T:box(`Scallop{i}_{j}`, d[1] * 7.75, lo, a - 2.9, d[1] * 8.1, hi, a + 2.9, col, DECOR)
			else
				T:box(`Scallop{i}_{j}`, a - 2.9, lo, d[2] * 7.75, a + 2.9, hi, d[2] * 8.1, col, DECOR)
			end
		end
	end
	local y = 9.6
	for k, r in { 8.4, 6.6, 4.6, 2.8 } do
		local L = if k % 2 == 1 then T else T45
		local h = if k <= 2 then 1.3 else 1.0
		L:box(`Canopy{k}`, -r, y, -r, r, y + h, r, if k % 2 == 1 then H.fair else C.Cream)
		y += h
	end
	T:box("FinialPole", -0.25, y, -0.25, 0.25, y + 1.6, 0.25, H.goldDeep, NOSHADOW)
	T:box("FinialKnob", -0.6, y + 1.6, -0.6, 0.6, y + 2.6, 0.6, H.goldDeep, DECOR)
	-- riders on poles at radius 5: boats on the axes, cups on the diagonals
	for k = 0, 7 do
		local a = rad(k * 45)
		local x, z = 5 * math.sin(a), 5 * math.cos(a)
		T:box(`Pole{k + 1}`, x - 0.15, 1.5, z - 0.15, x + 0.15, 9.2, z + 0.15, H.goldDeep, DECOR)
		local ry = 3.0 + (k % 2) * 0.8
		if k % 2 == 0 then
			local alongX = k % 4 == 0 -- tangent to the circle
			local hx, hz = if alongX then 1.4 else 0.6, if alongX then 0.6 else 1.4
			T:box(`Boat{k / 2 + 1}`, x - hx, ry, z - hz, x + hx, ry + 1.2, z + hz, C.BoatPaint[k / 2 + 1], DECOR)
		else
			local c = if k % 4 == 1 then C.Pink else C.Cream
			T:box(`Cup{(k + 1) / 2}`, x - 0.8, ry, z - 0.8, x + 0.8, ry + 1.2, z + 0.8, c, DECOR)
		end
	end
	top.PrimaryPart = column
	column.PivotOffset = column.CFrame:Inverse() * (cf * CFrame.Angles(rad(90), 0, 0))
	top:SetAttribute("Spin", 18)
end

--[[
	A string of lights between the world points a and b: a rope in two sagging halves and n small
	glowing bulbs hanging from it. 2 + n parts.
]]
local function festoon(parent: any, a: any, b: any, n: number, sag: number)
	local m = U.model(parent, "Festoon")
	local low = (a + b) / 2 - V(0, sag, 0)
	local function rope(name: string, p: any, q: any): any
		return U.part(m, name, V(0.16, 0.16, (q - p).Magnitude), CFrame.lookAt((p + q) / 2, q), C.Dark, nil, DECOR)
	end
	m.PrimaryPart = rope("RopeA", a, low)
	rope("RopeB", low, b)
	for i = 1, n do
		local t = i / (n + 1)
		local p = if t <= 0.5 then a + (low - a) * (t * 2) else low + (b - low) * ((t - 0.5) * 2)
		U.part(m, `Bulb{i}`, V(0.6, 0.7, 0.6), CFrame.new(p - V(0, 0.45, 0)), C.Glow, nil, NEON_DECOR)
	end
	Kit.sway(m, CFrame.lookAt((a + b) / 2, b), 3, "Z", 3.2)
end

--[[
	Two low midway games on the fair ground beside the carousel (frame origin = the game's centre):
	"rings" — a ring-toss platform with three pegs and two rings lying by them; "fishing" — a hook-a-
	fish pool: a teal tub of water with three little fish floating in it. 5-6 parts.
]]
local function midwayGame(parent: any, cf: any, kind: string)
	local F = newFrame(U.model(parent, if kind == "rings" then "RingToss" else "FishPond"), cf)
	if kind == "rings" then
		F.model.PrimaryPart = F:box("Platform", -2.4, -0.3, -2.4, 2.4, 0.9, 2.4, C.Cream)
		F:box("PlatformTrim", -2.55, 0.2, -2.55, 2.55, 0.6, 2.55, C.Red, NOSHADOW)
		for i, p in { { -1.2, -1.0 }, { 1.2, -0.6 }, { 0, 1.2 } } do
			F:column(`Peg{i}`, 0.45, p[1], p[2], 0.9, 2.6, C.WoodDark, NOSHADOW)
		end
		F:box("Ring", 0.6, 0.9, 0.6, 1.8, 1.05, 1.8, C.Yellow, DECOR)
	else
		F.model.PrimaryPart = F:box("Tub", -2.6, -0.3, -2.6, 2.6, 1.3, 2.6, H.fair)
		F:box("TubWater", -2.1, 1.0, -2.1, 2.1, 1.4, 2.1, H.water, DECOR)
		for i, p in { { -1.0, -0.8, C.Orange }, { 0.9, -0.2, C.Yellow }, { -0.2, 1.1, C.Pink } } do
			F:box(`Fish{i}`, p[1] - 0.55, 1.35, p[2] - 0.25, p[1] + 0.55, 1.65, p[2] + 0.25, p[3], DECOR)
		end
	end
end

--[[
	Fun fair on the θ 225 diagonal (off every base's line of sight to the tower): an entrance arch
	on the plaza rim, a warm flagstone fair ground, a path lined by an ice-cream cart, a popcorn
	wagon, a lemonade stand and the striped «ИГРЫ» game tent, a string of lights across it, the big
	carousel at its end with a ring toss and a hook-a-fish pool beside it, and the Ferris wheel
	behind (the spinning parts never collide, see buildHub).
]]
local function buildFair(hub: any, G: number)
	local m = U.model(hub, "FunFair")
	local F = radialFrame(m, 225, G)
	local wheelR, scale = 126, 1.45
	local pathEnd = 93
	-- (its edges stay clear of the θ 202.5 / 247.5 lane paths)
	F:box("FairGround", -23.4, -0.3, PLAZA_R + 1, 23.4, 0.12, 121, C.FlagstoneDark, FLAT)
	F:box("Path", -6, -0.3, PLAZA_R - 1, 6, 0.35, pathEnd, H.walk, FLAT)
	for j, sx in { -1, 1 } do
		F:box(`PathEdge{j}`, sx * 6, -0.3, PLAZA_R - 1, sx * 7.4, 0.5, pathEnd, H.paveDark, FLAT)
	end
	fairArch(F, PLAZA_R - 3)
	-- the stalls and the game tent face the path from both sides
	foodStall(m, F:at(-13.4, 0, 74, -90), "IceCreamCart", "МОРОЖЕНОЕ", C.Pink, "icecream")
	foodStall(m, F:at(13.6, 0, 74, 90), "PopcornWagon", "ПОПКОРН", C.Red, "popcorn")
	foodStall(m, F:at(12.6, 0, 87, 90), "LemonadeStand", "ЛИМОНАД", C.Yellow, "lemonade")
	gameTent(m, F:at(-17.2, 0, 89, -90))
	-- a string of lights across the path between iron poles
	local tops = {}
	for j, sx in { -1, 1 } do
		F:box(`LightPole{j}`, sx * 9.2 - 0.3, -0.3, 80.7, sx * 9.2 + 0.3, 12, 81.3, C.Iron, NOSHADOW)
		tops[j] = F:point(sx * 9.2, 11.8, 81)
	end
	festoon(m, tops[1], tops[2], 5, 1.2)
	local cz = pathEnd + 6.5
	carousel(m, F:world(CFrame.new(0, 0, cz)))
	midwayGame(m, F:at(-18.5, 0, cz + 3.5, 0), "rings")
	midwayGame(m, F:at(18.5, 0, cz + 3.5, 0), "fishing")
	local wheel = Props.ferrisWheel(m, U.polarCFrame(225, wheelR, G), { scale = scale, deck = C.Plank, seed = 1 })
	calmWheel(wheel)
end

--------------------------------------------------------------------------------
-- Village kit: dry-stone walls, gravel paths, yard props
--------------------------------------------------------------------------------

-- Low dry-stone wall over the local rectangle x0..x1 × z0..z1 (any order), height h: a stone body
-- and a cream cap stone 0.2 proud all round. 2 parts.
local function stoneWall(F: any, name: string, x0: number, z0: number, x1: number, z1: number, h: number)
	F:box(name, x0, -0.3, z0, x1, h, z1, H.wall)
	local xa, xb = math.min(x0, x1), math.max(x0, x1)
	local za, zb = math.min(z0, z1), math.max(z0, z1)
	F:box(name .. "Cap", xa - 0.2, h, za - 0.2, xb + 0.2, h + 0.5, zb + 0.2, C.Limestone, NOSHADOW)
end

-- The lanes' gravel paths start just outside the plaza paving (whose stepped rows reach r ≈ 70
-- on some lanes).
local LANE_PATH_IN = PLAZA_R + 4

-- Gravel path over x0..x1 × z0..z1, its top 0.1 above the lawn (0.1 under the plaza paving). 1 part.
local function gravelPath(F: any, name: string, x0: number, z0: number, x1: number, z1: number): any
	return F:box(name, x0, -0.3, z0, x1, 0.1, z1, H.gravel, FLAT)
end

-- Woodpile of length len along local X centred at (x, z), its cut ends facing local −Z: a stack
-- of bark, the light cut ends and a plank roof. 3 parts.
local function woodpile(F: any, x: number, z: number, len: number)
	F:box("Woodpile", x - len / 2, -0.2, z - 0.9, x + len / 2, 2.4, z + 0.9, C.Bark)
	F:box("WoodpileEnds", x - len / 2 + 0.2, 0.1, z - 1.0, x + len / 2 - 0.2, 2.2, z - 0.8, C.CutWood, DECOR)
	F:box("WoodpileRoof", x - len / 2 - 0.3, 2.4, z - 1.3, x + len / 2 + 0.3, 2.8, z + 1.0, C.WoodDark, NOSHADOW)
end

--[[
	Kitchen garden: a soil bed (w along X, d along Z) with n rows across it, each row a line of k
	leafy clumps (cabbages and lettuces in two greens, staggered row to row, a few with an orange
	or red crop showing), on a timber edging. 2 + n·k parts.
]]
local function vegPatch(F: any, name: string, cx: number, cz: number, w: number, d: number, n: number, k: number)
	F:box(
		name .. "Edge",
		cx - w / 2 - 0.3,
		-0.3,
		cz - d / 2 - 0.3,
		cx + w / 2 + 0.3,
		0.6,
		cz + d / 2 + 0.3,
		C.Wood,
		FLAT
	)
	F:box(name, cx - w / 2, -0.3, cz - d / 2, cx + w / 2, 0.75, cz + d / 2, C.DirtDark, FLAT)
	local step = (w - 1.2) / k
	for row = 1, n do
		local z = cz - d / 2 + (row - 0.5) * d / n
		for j = 1, k do
			local x = cx - w / 2 + 0.6 + (j - 0.5) * step + (if row % 2 == 0 then 0.35 else -0.35)
			local big = (row + j) % 2 == 0
			local hw = if big then 0.75 else 0.6
			local col = if big then C.Leaf3 else C.Mint2
			if (row * 3 + j) % 5 == 0 then
				col = if row % 2 == 0 then C.Orange else lerpColor(C.Red, C.Leaf1, 0.25) -- pumpkin / beet
			end
			F:box(`{name}Clump{row}_{j}`, x - hw, 0.7, z - hw, x + hw, if big then 2.0 else 1.7, z + hw, col, DECOR)
		end
	end
end

-- Beehive on a little stand at local (x, z): a cream box under a red lid. 3 parts.
local function beehive(F: any, x: number, z: number)
	F:box("HiveStand", x - 0.9, -0.3, z - 0.9, x + 0.9, 0.8, z + 0.9, C.WoodDark, NOSHADOW)
	F:box("Hive", x - 1.2, 0.8, z - 1.1, x + 1.2, 3.2, z + 1.1, C.Cream)
	F:box("HiveLid", x - 1.45, 3.2, z - 1.35, x + 1.45, 3.75, z + 1.35, C.RoofRed, NOSHADOW)
end

-- Washing line along local X from x0 to x1 at z: two posts, the line and three pieces of laundry.
-- 6 parts.
local function washingLine(F: any, x0: number, x1: number, z: number)
	for i, x in { x0, x1 } do
		F:box(`LinePost{i}`, x - 0.25, -0.3, z - 0.25, x + 0.25, 5.4, z + 0.25, C.WoodDark, NOSHADOW)
	end
	F:box("Line", x0, 5.0, z - 0.06, x1, 5.12, z + 0.06, C.Rope, DECOR)
	for k, col in { C.White, lerpColor(C.Blue, C.Cream, 0.3), C.Cream } do
		local x = x0 + (x1 - x0) * k / 4
		local w = if k == 2 then 0.8 else 1.0
		local item = F:box(`Laundry{k}`, x - w, 2.9 + (k % 2) * 0.5, z - 0.08, x + w, 5.0, z + 0.08, col, DECOR)
		Kit.sway(item, F:at(x, 5.0, z), 6, "X", 2.6 + 0.3 * k) -- (swings on the line in the breeze)
	end
end

--------------------------------------------------------------------------------
-- Houses: four types (frame origin = footprint centre on the ground, −Z = the front, towards the
-- beach; s.flip mirrors them). s: wall, wall2 (upper storey), roof, trim, shutter, door,
-- flowers = { c1, c2 }.
--------------------------------------------------------------------------------

--[[
	Fisher's house: a plastered ground floor on a stone plinth under a jettied upper storey in
	painted timber on a heavy beam (dark corner posts), a gable roof (ridge along X) with an attic
	window and a chimney. Front: a panelled door with a step and a shuttered window under the
	jetty; upstairs a glazed door onto a balcony (balustrade, flower box) between two windows. An
	outside stone stair climbs the side (+X, or −X when flipped) to an upper side door; windows on
	the other side and at the back. ~62 parts.
]]
local function fisherHouse(F: any, s: { [string]: any }): any
	local m = if s.flip then -1 else 1
	local hw, hd, up, top = 7, 5, 8.2, 14 -- half width, half depth, upper floor, wall top
	local trim, timber = s.trim, C.WoodDark
	local sideFace, otherFace = if m > 0 then "+x" else "-x", if m > 0 then "-x" else "+x"
	local base = F:box("Base", -hw - 0.5, -0.3, -hd - 0.5, hw + 0.5, 1.2, hd + 0.5, C.Stone, FLAT)
	F:box("Walls", -hw, 1.2, -hd, hw, up - 0.4, hd, s.wall)
	F:box("Jetty", -hw - 0.7, up - 0.6, -hd - 1.1, hw + 0.7, up + 0.4, hd + 0.4, timber)
	F:box("Upper", -hw - 0.45, up + 0.4, -hd - 0.85, hw + 0.45, top, hd + 0.2, s.wall2)
	for i, sx in { -1, 1 } do
		F:box(`CornerPost{i}`, sx * (hw - 0.2), up + 0.4, -hd - 1.15, sx * (hw + 0.75), top, -hd - 0.35, timber)
	end
	local ridgeTop = gableRoof(F, "Roof", 0, -0.33, "x", hw + 0.45, hd + 0.53, top, 6, {
		roof = s.roof,
		eave = trim,
		gable = s.wall2,
		noBeam = true,
		ov = 1.3,
		og = 0.9,
		t = 0.8,
		window = { trim, C.WindowBlue },
		windowAt = { [-m] = true },
	})
	F:box("Chimney", -m * 3.4, top - 1, 0.6, -m * 5.2, ridgeTop + 1.6, 2.4, C.Brick)
	F:box("ChimneyCap", -m * 3.1, ridgeTop + 1.6, 0.3, -m * 5.5, ridgeTop + 2.3, 2.7, C.StoneDark, NOSHADOW)
	-- ground floor front, sheltered by the jetty
	door(F, "Door", "-z", -hd, -m * 3.4, 1.2, 2.8, 5.2, {
		trim = trim,
		color = s.door,
		panel = true,
		step = { -0.3, 0.6, 1.6 },
	})
	window(F, "Window", "-z", -hd, m * 3.3, 3.2, 3.2, 3.0, { trim = trim, shutter = s.shutter, mullion = false })
	-- upstairs: the balcony in front of a glazed door, a window either side
	local bz = -hd - 0.85
	F:box("Balcony", -3.4, up - 0.15, bz - 2.4, 3.4, up + 0.45, bz + 0.2, timber)
	F:box("BalconyRail", -3.4, up + 0.45, bz - 2.4, 3.4, up + 2.5, bz - 2.0, trim, NOSHADOW)
	F:box("BalconyBox", -2.4, up + 2.5, bz - 2.5, 2.4, up + 3.1, bz - 1.9, C.Wood, NOSHADOW)
	for i, sx in { -1, 1 } do
		local bt = up + 3.7 + (i - 1) * 0.25
		F:box(`BalconyBloom{i}`, sx * 1.2 - 0.8, up + 2.9, bz - 2.4, sx * 1.2 + 0.8, bt, bz - 2.0, s.flowers[i], DECOR)
	end
	F:onFace("UpDoorFrame", "-z", bz, -1.5, up + 0.45, 1.5, up + 5.0, -0.1, 0.25, trim, NOSHADOW)
	F:onFace("UpDoor", "-z", bz, -1.0, up + 0.45, 1.0, up + 4.5, 0, 0.35, C.WindowBlue, NOSHADOW)
	for i, sx in { -1, 1 } do
		window(F, `UpWin{i}`, "-z", bz, sx * 5.2, up + 1.6, 2.0, 3.0, { trim = trim, mullion = false })
	end
	-- the outside stair: four stone steps and a landing along the side wall, the upper side door
	local x0, x1 = m * (hw + 0.75), m * (hw + 2.85)
	for k = 1, 4 do
		local z0 = -hd + 0.2 + (k - 1) * 1.7
		F:box(`Stair{k}`, x0, -0.3, z0, x1, k * up / 5, z0 + 1.7, H.wall)
	end
	F:box("Landing", x0, -0.3, -hd + 7.0, x1, up + 0.4, hd + 0.4, H.wall)
	door(F, "SideDoor", sideFace, m * (hw + 0.45), 3.3, up + 0.4, 2.4, 4.4, { trim = trim, color = s.door })
	-- the other side and the back (the plaza sees the back)
	window(F, "SideWin", otherFace, -m * hw, 0, 3.2, 2.6, 3.0, { trim = trim, mullion = false, sill = false })
	window(
		F,
		"SideUpWin",
		otherFace,
		-m * (hw + 0.45),
		0,
		up + 1.6,
		2.4,
		3.0,
		{ trim = trim, mullion = false, sill = false }
	)
	for i, sx in { -1, 1 } do
		window(F, `BackWin{i}`, "+z", hd, sx * 3.4, 3.2, 2.6, 3.0, { trim = trim, mullion = false, sill = false })
	end
	window(F, "BackUpWin", "+z", hd + 0.2, 0, up + 1.6, 2.6, 3.0, { trim = trim, mullion = false, sill = false })
	return base
end

--[[
	L-shaped cottage: a one-storey main wing (ridge along X) and a front wing with its own gable
	to the front (a cross gable meeting the main ridge), a covered porch on posts in the inner
	corner with the door, a big shuttered window with a flower box in the front gable wall, side
	and back windows, a chimney. ~54 parts.
]]
local function lCottage(F: any, s: { [string]: any }): any
	local m = if s.flip then -1 else 1
	local wh, trim = 7.6, s.trim
	local sideFace, otherFace = if m > 0 then "+x" else "-x", if m > 0 then "-x" else "+x"
	local base = F:box("Base", -8.5, -0.3, -0.5, 8.5, 1.2, 7.5, C.Stone, FLAT)
	F:box("WingBase", m * -8, -0.3, -6.5, m * -1, 1.2, -0.4, C.Stone, FLAT)
	F:box("Walls", -8, 1.2, 0, 8, wh, 7, s.wall)
	F:box("WingWalls", m * -7.5, 1.2, -6, m * -1.5, wh, 0.2, s.wall)
	local ridgeTop = gableRoof(F, "Roof", 0, 3.5, "x", 8.05, 3.55, wh, 5, {
		roof = s.roof,
		eave = trim,
		gable = s.wall,
		noBeam = true,
		ov = 1.2,
		og = 0.8,
		t = 0.8,
	})
	-- the front wing's roof runs back to the main ridge (its far end hides in the main roof)
	local wx = m * -4.5
	gableRoof(F, "WingRoof", wx, -1.65, "z", 4.35, 3.05, wh, 5, {
		roof = s.roof,
		eave = trim,
		gable = s.wall,
		gables = { -1 },
		noBeam = true,
		ov = 1.15,
		og = 0.8,
		t = 0.8,
		window = { trim, C.WindowBlue },
	})
	F:box("Chimney", m * 4.4, wh - 1, 2.6, m * 6.2, ridgeTop + 1.4, 4.4, C.Brick)
	F:box("ChimneyCap", m * 4.1, ridgeTop + 1.4, 2.3, m * 6.5, ridgeTop + 2.1, 4.7, C.StoneDark, NOSHADOW)
	-- the porch in the inner corner: plank deck, two posts, a pent roof tucked under the main eave
	local px0, px1 = m * -1.1, m * 8.3
	F:box("PorchDeck", px0, -0.3, -4.4, px1, 1.3, 0, C.Plank, FLAT)
	for i, x in { 3.0, 7.6 } do
		F:box(`PorchPost{i}`, m * x - 0.35, 1.3, -4.3, m * x + 0.35, 6.6, -3.6, C.WoodDark)
	end
	F:faceWedge("PorchRoof", "-z", 0, px0, 6.4, px1, wh + 0.2, 1.0, 4.9, s.roof)
	door(F, "Door", "-z", 0, m * 5.3, 1.3, 2.8, 4.9, { trim = trim, color = s.door, panel = true })
	-- the front wing: a big shuttered window with a flower box
	window(F, "Window", "-z", -6, wx, 3.0, 2.8, 3.2, { trim = trim, shutter = s.shutter, flowers = s.flowers })
	window(F, "SideWin", otherFace, m * -8, 3.5, 3.0, 2.6, 3.0, { trim = trim, mullion = false, sill = false })
	window(F, "SideWin2", sideFace, m * 8, 3.5, 3.0, 2.6, 3.0, { trim = trim, mullion = false, sill = false })
	for i, sx in { -1, 1 } do
		window(F, `BackWin{i}`, "+z", 7, sx * 4, 3.0, 2.6, 3.0, { trim = trim, mullion = false, sill = false })
	end
	return base
end

--[[
	Net loft: a tall timber boathouse painted in a calm red, white corner boards, its gable to the
	front over big double doors with a cross rail, a loft door in the gable with a hoist beam,
	pulley and hook; a lean-to shed on one side (+X, or −X when flipped); on the other side a net
	hung to dry with floats and two oars; back windows and a window in the back gable. ~41 parts.
]]
local function netLoft(F: any, s: { [string]: any }): any
	local m = if s.flip then -1 else 1
	local hw, hd, wh = 6.5, 7, 9.6
	local trim = s.trim
	local sideFace, otherFace = if m > 0 then "+x" else "-x", if m > 0 then "-x" else "+x"
	local base = F:box("Base", -hw - 0.5, -0.3, -hd - 0.5, hw + 0.5, 0.9, hd + 0.5, C.Stone, FLAT)
	F:box("Walls", -hw, 0.9, -hd, hw, wh, hd, s.wall)
	for i, d in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		F:box(
			`Corner{i}`,
			d[1] * (hw - 0.45),
			0.9,
			d[2] * (hd - 0.45),
			d[1] * (hw + 0.3),
			wh,
			d[2] * (hd + 0.3),
			trim,
			NOSHADOW
		)
	end
	gableRoof(F, "Roof", 0, 0, "z", hd + 0.05, hw + 0.05, wh, 7.5, {
		roof = s.roof,
		eave = trim,
		gable = s.wall,
		noBeam = true,
		ov = 1.0,
		og = 1.0,
		t = 0.8,
		window = { trim, C.WindowBlue },
		windowAt = { [1] = true },
	})
	-- the boat doors, a loft door in the front gable (its face at z −8.35) and the hoist
	F:onFace("BoatDoorFrame", "-z", -hd, -3.6, 0.9, 3.6, 7.6, -0.1, 0.3, trim, NOSHADOW)
	for i, sx in { -1, 1 } do
		F:onFace(`BoatDoor{i}`, "-z", -hd, sx * 0.1, 0.9, sx * 3.0, 7.0, 0, 0.45, C.WoodDark, NOSHADOW)
	end
	F:onFace("DoorRail", "-z", -hd, -3.1, 3.7, 3.1, 4.3, 0, 0.6, trim, DECOR)
	F:box("LoftFrame", -1.9, wh + 0.4, -8.55, 1.9, wh + 4.4, -8.25, trim, NOSHADOW)
	F:box("LoftDoor", -1.4, wh + 0.5, -8.7, 1.4, wh + 3.9, -8.4, C.WoodDark, NOSHADOW)
	F:box("Hoist", -0.45, wh + 5.0, -11.8, 0.45, wh + 5.8, -8.2, C.WoodDark)
	F:box("HoistRope", -0.1, wh + 1.4, -11.3, 0.1, wh + 5.0, -11.1, C.Rope, DECOR)
	F:box("HoistBlock", -0.45, wh + 0.6, -11.7, 0.45, wh + 1.4, -10.7, C.Iron, DECOR)
	-- the lean-to shed with its own little door
	F:box("LeanTo", m * hw, 0.9, -3.5, m * (hw + 4.4), 5.8, 5.0, lerpColor(s.wall, C.WoodDark, 0.3))
	F:faceWedge("LeanToRoof", sideFace, m * hw, -4.1, 5.6, 5.6, 7.6, 0, 5.1, s.roof)
	F:onFace("LeanToDoor", sideFace, m * (hw + 4.4), -1.2, 0.9, 1.2, 4.9, 0, 0.3, C.WoodDark, NOSHADOW)
	-- the net drying on the other wall, floats along its foot, two oars
	local nw = -m * hw
	F:onFace("Net", otherFace, nw, -4.6, 2.2, 3.0, 8.2, 0, 0.25, lerpColor(C.Twine, C.WoodDark, 0.35), NOSHADOW)
	for k, c in { C.Red, C.Cream, C.Yellow } do
		local a = -3.6 + (k - 1) * 2.8
		F:onFace(`Float{k}`, otherFace, nw, a - 0.45, 2.4, a + 0.45, 3.3, 0.2, 0.9, c, DECOR)
	end
	for k = 1, 2 do
		local a = 3.9 + k * 0.9
		F:onFace(`Oar{k}`, otherFace, nw, a, 0, a + 0.4, 7.6, 0.2, 0.55, C.WoodLight, DECOR)
	end
	for i, sx in { -1, 1 } do
		window(F, `BackWin{i}`, "+z", hd, sx * 3.2, 3.0, 2.4, 3.0, { trim = trim, mullion = false, sill = false })
	end
	return base
end

--[[
	Hip-roofed house: a two-storey plastered house with pale stone quoins, a string course and a
	cornice, a stepped hip roof (four layers and a ridge cap) with a gabled dormer at the front and
	a chimney; a portico (two posts, a pent roof, a stone step) over the panelled door, shuttered
	windows below, windows with flower boxes above, side and back windows. ~61 parts.
]]
local function hipHouse(F: any, s: { [string]: any }): any
	local m = if s.flip then -1 else 1
	local hw, hd, wh = 7.5, 6.5, 12.4
	local trim = s.trim
	local base = F:box("Base", -hw - 0.5, -0.3, -hd - 0.5, hw + 0.5, 1.2, hd + 0.5, C.Stone, FLAT)
	F:box("Walls", -hw, 1.2, -hd, hw, wh, hd, s.wall)
	F:box("StringCourse", -hw - 0.25, 6.6, -hd - 0.25, hw + 0.25, 7.2, hd + 0.25, trim, NOSHADOW)
	for i, d in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		F:box(
			`Quoin{i}`,
			d[1] * (hw - 0.8),
			1.2,
			d[2] * (hd - 0.8),
			d[1] * (hw + 0.35),
			wh,
			d[2] * (hd + 0.35),
			C.Limestone,
			NOSHADOW
		)
	end
	F:box("Cornice", -hw - 0.7, wh, -hd - 0.7, hw + 0.7, wh + 0.6, hd + 0.7, trim)
	local y = wh + 0.6
	for k, inset in { 0, 1.5, 3.0, 4.5 } do
		local c = if k % 2 == 0 then shade(s.roof, 0.9) else s.roof
		F:box(`RoofStep{k}`, -hw - 1 + inset, y, -hd - 1 + inset, hw + 1 - inset, y + 1.2, hd + 1 - inset, c)
		y += 1.2
	end
	F:box("RoofRidge", -hw + 4.6, y, -0.7, hw - 4.6, y + 0.7, 0.7, shade(s.roof, 0.78))
	dormer(F, "Dormer", "-z", -hd - 0.1, 0, wh + 1.8, 4.4, 3.2, 4.2, { wall = s.wall, trim = trim, roof = s.roof })
	F:box("Chimney", m * 2.8, wh, 1.6, m * 4.4, y + 2.2, 3.2, C.Brick)
	F:box("ChimneyCap", m * 2.5, y + 2.2, 1.3, m * 4.7, y + 2.9, 3.5, C.StoneDark, NOSHADOW)
	-- the portico
	door(F, "Door", "-z", -hd, 0, 1.2, 3, 4.9, {
		trim = trim,
		color = s.door,
		panel = true,
		step = { -0.3, 0.7, 2.6 },
	})
	for i, sx in { -1, 1 } do
		F:box(`PorchPost{i}`, sx * 2.3 - 0.35, 0.7, -hd - 2.4, sx * 2.3 + 0.35, 7.0, -hd - 1.7, trim)
	end
	F:faceWedge("PorchRoof", "-z", -hd, -3.0, 6.9, 3.0, 7.9, 0, 2.8, s.roof)
	for i, sx in { -1, 1 } do
		window(F, `Win{i}`, "-z", -hd, sx * 4.7, 2.8, 2.2, 3.2, { trim = trim, shutter = s.shutter, mullion = false })
		window(F, `UpWin{i}`, "-z", -hd, sx * 4.7, 8.3, 2.2, 3.0, {
			trim = trim,
			mullion = false,
			flowers = s.flowers,
		})
		local face = if sx < 0 then "-x" else "+x"
		window(F, `SideWin{i}`, face, sx * hw, -1.5, 2.8, 2.4, 3.0, { trim = trim, mullion = false, sill = false })
		window(F, `BackWin{i}`, "+z", hd, sx * 4.2, 2.8, 2.4, 3.2, { trim = trim, mullion = false, sill = false })
	end
	window(F, "BackUpWin", "+z", hd, 0, 8.3, 2.4, 3.0, { trim = trim, mullion = false, sill = false })
	return base
end

local HOUSE_TYPES = { fisher = fisherHouse, lcottage = lCottage, netloft = netLoft, hip = hipHouse }

-- House palettes: calm walls (pale plaster tints, painted timber), one tiled roof, one trim.
local HOUSE_STYLES = {
	harbourBlue = {
		wall = C.Plaster,
		wall2 = lerpColor(C.RoofBlue, C.Plaster, 0.38),
		roof = H.roofClay,
		trim = C.Cream,
		shutter = C.RoofBlue,
		door = C.RoofBlue,
		flowers = { C.Flowers[1], C.Flowers[5] },
	},
	butter = {
		wall = lerpColor(C.Plaster, C.Yellow, 0.22),
		roof = H.roofHarbour,
		trim = C.White,
		shutter = C.RoofGreen,
		door = C.RoofGreen,
		flowers = { C.Flowers[3], C.Flowers[5] },
	},
	netRed = {
		wall = lerpColor(C.Brick, C.WoodDark, 0.2),
		roof = H.roofSage,
		trim = C.Cream,
		door = C.WoodDark,
	},
	rose = {
		wall = lerpColor(C.Plaster, C.Pink, 0.14),
		roof = H.roofClay,
		trim = C.Cream,
		shutter = C.RoofBlue,
		door = C.Wood,
		flowers = { C.Flowers[2], C.Flowers[5] },
	},
	sage = {
		wall = lerpColor(C.Plaster, C.RoofGreen, 0.14),
		roof = C.RoofBrown,
		trim = C.White,
		shutter = C.RoofRed,
		door = C.RoofGreen,
		flowers = { C.Flowers[4], C.Flowers[3] },
	},
	harbourGreen = {
		wall = C.Limestone,
		wall2 = lerpColor(C.RoofGreen, C.Plaster, 0.42),
		roof = C.RoofSlate,
		trim = C.Cream,
		shutter = C.RoofGreen,
		door = C.Wood,
		flowers = { C.Flowers[4], C.Flowers[3] },
	},
}

-- Is the world point (x, z) within `margin` of a base's line of sight to the tower (the base
-- lanes θ = 22.5 + k·45, which stay open)?
local function nearLane(x: number, z: number, margin: number): boolean
	for k = 0, 7 do
		local a = rad(22.5 + k * 45)
		local along = x * math.sin(a) + z * math.cos(a)
		if along > 0 and abs(x * math.cos(a) - z * math.sin(a)) < margin then
			return true
		end
	end
	return false
end

-- Is the footprint circle (world x, z, radius) clear of every hub part reaching higher than
-- G + minTop (default 0.7: paving, paths, kerbs and other flat slabs don't count)? Parts are taken
-- as their oriented top-view boxes.
local function groundClear(hub: any, G: number, x: number, z: number, radius: number, minTop: number?): boolean
	for _, p in hub:GetDescendants() do
		if p:IsA("BasePart") then
			local cf, size = p.CFrame, p.Size
			local top = 0
			for _, d in { cf.RightVector * size.X, cf.UpVector * size.Y, cf.LookVector * size.Z } do
				top += abs(d.Y) / 2
			end
			if cf.Position.Y + top > G + (minTop or 0.7) then
				local l = cf:PointToObjectSpace(V(x, cf.Position.Y, z))
				local dx = math.max(abs(l.X) - size.X / 2, 0)
				local dz = math.max(abs(l.Z) - size.Z / 2, 0)
				if dx * dx + dz * dz < radius * radius then
					return false
				end
			end
		end
	end
	return true
end

--[[
	Three clusters of two different houses flanking a base lane (their fronts towards the beach,
	the lane between them open), sharing a yard on the lane, each yard with its own plan: the lane's
	walk runs through it to a gate at the beach terrace; the boundary towards the plaza is a
	dry-stone wall, a clipped hedge or a white post-and-rail fence (and the other end hedges or a
	wall), the kitchen garden, the rain barrel, the woodpile and the hives sit in different corners
	(the plans are mirrored cluster to cluster), and one special piece each: a washing line, a cold
	frame with a bench, a well with a roof and a bucket on its rope.
]]
local CLUSTERS = {
	{
		lane = 67.5,
		houses = { { 58.3, "fisher", "harbourBlue" }, { 77, "lcottage", "butter" } },
		-- (x mirrored by `flip`): plaza side, beach side, veg patch, hives, barrel, woodpile, extra
		yard = { flip = 1, front = "wall", back = "hedge", veg = { -7.6, 134.6 }, hives = {}, barrel = { -11.4, 145 } },
		woodpile = { 9.6, 131.4 },
		extra = "washing",
		feature = "fish",
		tones = { C.Flowers[3], C.Flowers[4] }, -- pink / violet
	},
	{
		lane = 157.5,
		houses = { { 147.6, "netloft", "netRed" }, { 167.3, "hip", "rose" } },
		yard = {
			flip = -1,
			front = "hedge",
			back = "wall",
			veg = { -7.4, 142.6 },
			hives = { { -11.6, 131.4 }, { -8.6, 131.4 } },
			barrel = { 11.6, 144.6 },
		},
		woodpile = { 9.2, 131.6 },
		extra = "frame",
		feature = "rill",
		tones = { C.Flowers[7], C.Flowers[5] }, -- blue / white
	},
	{
		lane = 247.5,
		houses = { { 238.2, "hip", "sage" }, { 256.8, "fisher", "harbourGreen" } },
		yard = {
			flip = -1,
			front = "fence",
			back = "fence",
			veg = { 7.6, 142.4 },
			hives = { { 11.6, 132 } },
			barrel = { -11.6, 131.4 },
		},
		woodpile = { -9.6, 145 },
		extra = "well",
		feature = "pond",
		tones = { C.Flowers[6], C.Flowers[1] }, -- orange / red
	},
}
local HOUSE_R = 139

-- A yard boundary across the lane at radial z (from the walk's kerb out to ±x1): a dry-stone wall,
-- a clipped hedge or a white post-and-rail fence, each in two halves either side of the walk.
local function yardBoundary(Y: any, name: string, kind: string, z: number, x1: number)
	for i, sx in { -1, 1 } do
		local a, b = sx * 2.5, sx * x1
		if kind == "wall" then
			stoneWall(Y, `{name}{i}`, a, z - 0.6, b, z + 0.6, 1.6)
		elseif kind == "hedge" then
			Y:box(`{name}{i}`, a, -0.3, z - 0.7, b, 1.8, z + 0.7, C.Leaf0)
		else -- white post-and-rail fence: two posts, two rails
			for k, x in { a + sx * 0.3, b - sx * 0.3 } do
				Y:box(`{name}{i}Post{k}`, x - 0.3, -0.3, z - 0.3, x + 0.3, 2.4, z + 0.3, C.White, NOSHADOW)
			end
			for k, y in { 0.9, 1.9 } do
				Y:box(`{name}{i}Rail{k}`, a, y - 0.2, z - 0.12, b, y + 0.2, z + 0.12, C.White, NOSHADOW)
			end
		end
	end
end

--[[
	The base lanes (θ 22.5 + k·45) are the bases' lines of sight to the tower: nothing on them stands
	higher than a bench near the axis. Each is a garden walk from the plaza rim (r 70) to the beach
	terrace: a cobbled walk between cream kerbs, box-edged flower beds either side near the plaza in
	the lane's tone family (Props.flowerBed), and one small feature further out (built by the
	gardens and the cottage yards). 2 + 2 beds.
]]
local LANE_BED_R = { 75, 85 } -- the beds run from r 75 to 85 (or further out, see laneBeds)
local LANE_BEDS = {} -- queued by laneBeds, planted by placeLaneBeds
local function laneWalk(F: any, cx: number, r0: number, r1: number)
	F:box("WalkKerb", cx - 2.3, -0.3, r0 - 0.6, cx + 2.3, 0.12, r1 + 0.6, C.Limestone, FLAT)
	F:box("Walk", cx - 1.7, -0.3, r0, cx + 1.7, 0.24, r1, H.lane, FLAT)
end

local function laneBeds(hub: any, G: number, F: any, cx: number, tones: { any }, seed: number, n: number)
	local depth = LANE_BED_R[2] - LANE_BED_R[1]
	for i, sx in { -1, 1 } do
		local x = cx + sx * 5.1
		-- near the plaza a shop or the fun fair stands close beside some lanes: the bed on that
		-- side slides outwards until its footprint is clear of them
		local r0 = LANE_BED_R[1]
		while r0 < 104 do
			local clear = true
			for _, q in { { -2.9, 0 }, { 2.9, 0 }, { -2.9, 0.5 }, { 2.9, 0.5 }, { -2.9, 1 }, { 2.9, 1 } } do
				local p = F:point(x + q[1], 0, r0 - 0.4 + q[2] * (depth + 0.8))
				if not groundClear(hub, G, p.X, p.Z, 0.8, 0.5) then
					clear = false
					break
				end
			end
			if clear then
				break
			end
			r0 += 2
		end
		-- (scale 0.8: smaller blooms, set closer; the sizes below are divided by it). Planted at
		-- the end of the build, within the part budget left (placeLaneBeds).
		table.insert(LANE_BEDS, {
			parent = F.model,
			cf = F:at(x, 0, r0 + depth / 2),
			opts = {
				scale = 0.8,
				width = 4.4 / 0.8,
				depth = depth / 0.8,
				colors = if sx < 0 then tones else { tones[2], tones[1] },
				spacing = 2.3,
				stems = false,
				max = n,
				kerb = C.Leaf0, -- a clipped box edging
				seed = seed + i,
			},
		})
	end
end

--[[
	Plant the queued lane beds (Props.flowerBed) at the end of the build with as many blooms as the
	hub's part budget still allows: each bed asks for its `max`; when the beds would not fit (a
	richer Props.flowerBed costs more parts per bloom), they are taken down and planted again with
	fewer blooms, so the hub never fails its budget because of them.
]]
local function placeLaneBeds(room: number)
	local tries = 0
	while true do
		local built, used = {}, 0
		for _, b in LANE_BEDS do
			local before = U.partCount
			table.insert(built, Props.flowerBed(b.parent, b.cf, b.opts))
			used += U.partCount - before
		end
		if used <= room or tries >= 6 then
			return
		end
		tries += 1
		for _, m in built do
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					U.partCount -= 1
				end
			end
			m:Destroy()
		end
		for _, b in LANE_BEDS do
			b.opts.max = math.max(2, b.opts.max - 2)
		end
	end
end

--[[
	The small feature towards the outer end of a cottage lane (r 110..122, low, the walk kept clear):
	"fish" — a clipped topiary fish on a stone plinth beside the walk, a bench facing it;
	"rill" — a stone-edged rill of water across the lane from a little spring to a round pool, a
	plank footbridge with low rails carrying the walk over it; "pond" — a small pond with a stone
	rim, lily pads and a bench across the walk looking over it. 8-9 parts.
]]
local function laneFeature(m: any, lane: number, G: number, kind: string)
	local F = radialFrame(m, lane, G)
	if kind == "fish" then
		local x, z = 6.4, 117
		F:box("FishPlinth", x - 1.6, -0.3, z - 3.0, x + 1.6, 0.8, z + 3.0, C.Limestone)
		F:box("FishBody", x - 0.9, 0.8, z - 2.2, x + 0.9, 3.0, z + 1.4, C.Leaf1)
		F:box("FishHead", x - 0.75, 1.05, z - 3.0, x + 0.75, 2.75, z - 2.2, C.Leaf2)
		F:box("FishTail", x - 0.6, 1.2, z + 1.4, x + 0.6, 3.6, z + 2.8, C.Leaf2)
		F:box("FishEye", x - 0.95, 2.1, z - 2.6, x + 0.95, 2.5, z - 2.2, C.Dark, DECOR)
		parkBench(m, F:at(-5.4, 0, z, -90), 6, C.Wood)
	elseif kind == "rill" then
		local z = 115
		F:box("RillEdge", -8.4, -0.3, z - 1.9, 9.4, 0.3, z + 1.9, C.Limestone, FLAT)
		F:box("Rill", -7.8, -0.3, z - 1.2, 9, 0.4, z + 1.2, H.water, FLAT)
		F:box("Spring", -9.8, -0.3, z - 1.8, -7.8, 1.6, z + 1.8, C.Limestone)
		F:box("PoolRim", 8.2, -0.3, z - 2.8, 13.8, 0.6, z + 2.8, C.Limestone, FLAT)
		F:box("Pool", 8.8, -0.3, z - 2.2, 13.2, 0.7, z + 2.2, H.water, FLAT)
		F:box("Footbridge", -2.5, -0.3, z - 2.4, 2.5, 0.95, z + 2.4, C.Plank, FLAT)
		for i, sx in { -1, 1 } do
			F:box(`BridgeRail{i}`, sx * 2.3 - 0.2, 0.95, z - 2.2, sx * 2.3 + 0.2, 2.0, z + 2.2, C.WoodDark, NOSHADOW)
		end
	else
		local x, z = 7.4, 114
		F:box("PondRim", x - 3.4, -0.3, z - 5.0, x + 3.4, 0.6, z + 5.0, C.Limestone, FLAT)
		F:box("Pond", x - 2.7, -0.3, z - 4.3, x + 2.7, 0.7, z + 4.3, H.water, FLAT)
		F:box("LilyPad1", x - 1.6, 0.7, z - 2.6, x - 0.2, 0.84, z - 1.2, C.Leaf2, DECOR)
		F:box("LilyPad2", x + 0.4, 0.7, z + 1.0, x + 1.6, 0.84, z + 2.2, C.Leaf2, DECOR)
		F:box("LilyBloom", x - 1.2, 0.84, z - 2.2, x - 0.6, 1.3, z - 1.6, C.Pink, DECOR)
		parkBench(m, F:at(-x, 0, z, -90), 6, C.Wood)
	end
end

local function buildCottages(hub: any, G: number)
	local root = U.model(hub, "Cottages")
	for ci, cl in CLUSTERS do
		local cm = U.model(root, `Cluster{ci}`)
		for hi, h in cl.houses do
			local style = HOUSE_STYLES[h[3]]
			-- the house's local +X points to lower θ (its frame is turned to face the beach): the
			-- side towards the lane carries the stair / the porch / the net
			local towardsLane = if h[1] < cl.lane then -1 else 1
			local s = table.clone(style)
			s.flip = (h[2] == "fisher" and towardsLane < 0)
				or (h[2] == "netloft" and towardsLane > 0)
				or (h[2] == "lcottage" and towardsLane < 0)
				or (h[2] == "hip" and hi == 2)
			local F = newFrame(U.model(cm, `House{hi}`), U.polarCFrame(h[1], HOUSE_R, G) * CFrame.Angles(0, math.pi, 0))
			F.model.PrimaryPart = HOUSE_TYPES[h[2]](F, s)
		end
		-- the shared yard in the lane's frame (+Z radial, X lateral)
		local Y = radialFrame(U.model(cm, "Yard"), cl.lane, G)
		local p = cl.yard
		local fx = p.flip
		laneWalk(Y, 0, LANE_PATH_IN, 149.4)
		yardBoundary(Y, "YardFront", p.front, 127.8, 13.5)
		yardBoundary(Y, "YardBack", p.back, 148.3, 12.5)
		for i, sx in { -1, 1 } do
			Y:box(`GatePier{i}`, sx * 2.0 - 0.6, -0.3, 147.6, sx * 2.0 + 0.6, 2.6, 149.0, H.wall)
		end
		vegPatch(Y, "VegPatch", p.veg[1] * fx, p.veg[2], 6.4, 5.6, 2, 3)
		for _, hv in p.hives do
			beehive(Y, hv[1] * fx, hv[2])
		end
		Props.barrel(cm, Y:at(p.barrel[1] * fx, 0, p.barrel[2]), { seed = 310 + ci, color = C.Wood })
		woodpile(Y, cl.woodpile[1] * fx, cl.woodpile[2], 5.2)
		local ex = fx -- the extra stands on the side opposite the kitchen garden
		if cl.extra == "washing" then
			washingLine(Y, ex * 3.8, ex * 11.8, 140.4)
		elseif cl.extra == "frame" then
			-- a cold frame of glass on a timber box and a little bench beside it
			local x = -ex * 8.2
			Y:box("ColdFrame", x - 2.6, -0.3, 136.2, x + 2.6, 1.0, 140.2, C.Wood)
			Y:wedge("ColdFrameGlass", x - 2.4, 1.0, 136.4, x + 2.4, 2.0, 140.0, C.Glass, "+z", GLASS)
			parkBench(cm, Y:at(-ex * 9.6, 0, 144.2, 0), 5, C.WoodLight)
		else
			-- a stone well with a little roof, the bucket hanging on its rope from the beam
			local x = ex * 7.6
			Y:box("Well", x - 2, -0.3, 136.4, x + 2, 2.4, 140.4, H.wall)
			Y:box("WellWater", x - 1.3, 2.0, 137.1, x + 1.3, 2.45, 139.7, H.basinFloor, DECOR)
			for i, dx in { -1.7, 1.7 } do
				Y:box(`WellPost{i}`, x + dx - 0.25, 2.4, 138.15, x + dx + 0.25, 6.4, 138.65, C.WoodDark, NOSHADOW)
			end
			Y:box("WellBeam", x - 1.6, 5.1, 138.2, x + 1.6, 5.5, 138.6, C.Wood, NOSHADOW)
			gableRoof(
				Y,
				"WellRoof",
				x,
				138.4,
				"x",
				2.3,
				1.6,
				6.3,
				1.6,
				{ roof = C.RoofRed, gables = {}, ov = 0.4, og = 0.4, noEaves = true }
			)
			Y:box("WellRope", x - 0.06, 4.0, 138.34, x + 0.06, 5.1, 138.46, C.Rope, DECOR)
			Y:box("Bucket", x - 0.45, 3.2, 137.95, x + 0.45, 4.0, 138.85, C.Wood, DECOR)
		end
		laneBeds(hub, G, Y, 0, cl.tones, 330 + ci * 5, 8)
		laneFeature(U.model(cm, "LaneFeature"), cl.lane, G, cl.feature)
	end
end

--------------------------------------------------------------------------------
-- Gardens on the other base lanes, the orchard behind the Shop, boat yard, koi garden, bandstand
--------------------------------------------------------------------------------

--[[
	Parterre garden on a base lane (its walk at lateral cx): the lane's walk, the box-edged beds
	near the plaza and, further out, a round of cream paving on the walk with a focal piece in the
	middle (a sundial or a birdbath) and two clipped box hedges either side of it. ~33 parts.
]]
local function parterre(hub: any, G: number, F: any, cx: number, tones: { any }, focal: string, seed: number)
	laneWalk(F, cx, LANE_PATH_IN, 149.4)
	laneBeds(hub, G, F, cx, tones, seed, 8)
	local fz = 111
	F:box("Round", cx - 4.2, -0.3, fz - 4.2, cx + 4.2, 0.36, fz + 4.2, H.medallion, FLAT)
	for i, sx in { -1, 1 } do
		F:box(`BoxHedge{i}`, cx + sx * 5.4, -0.3, fz - 6, cx + sx * 6.8, 1.5, fz + 6, C.Leaf0)
	end
	if focal == "sundial" then
		F:box("SundialBase", cx - 1.1, 0.36, fz - 1.1, cx + 1.1, 2.4, fz + 1.1, C.Limestone)
		F:box("SundialTop", cx - 1.5, 2.4, fz - 1.5, cx + 1.5, 2.8, fz + 1.5, C.StoneLight)
		F:box("Gnomon", cx - 0.12, 2.8, fz - 0.8, cx + 0.12, 3.9, fz + 0.6, H.goldDeep, DECOR)
	else
		F:box("BirdbathFoot", cx - 0.6, 0.36, fz - 0.6, cx + 0.6, 2.2, fz + 0.6, C.Limestone)
		F:box("Birdbath", cx - 1.7, 2.2, fz - 1.7, cx + 1.7, 2.9, fz + 1.7, C.StoneLight)
		F:box("BirdbathWater", cx - 1.2, 2.75, fz - 1.2, cx + 1.2, 2.95, fz + 1.2, H.water, DECOR)
	end
end

-- per garden lane: the lateral offset (away from the shop or fair beside the lane), the tones
local GARDENS = {
	{ 22.5, -5, { C.Flowers[1], C.Flowers[5] }, "sundial" }, -- red / white
	{ 112.5, -5, { C.Flowers[4], C.Flowers[3] }, "birdbath" }, -- violet / pink
	{ 202.5, -5, { C.Flowers[2], C.Flowers[6] }, "sundial" }, -- yellow / orange
	{ 292.5, -5, { C.Flowers[7], C.Flowers[5] }, "birdbath" }, -- blue / white
}

local function buildGardens(hub: any, G: number)
	local m = U.model(hub, "Gardens")
	for i, g in GARDENS do
		local F = radialFrame(U.model(m, "FlowerGarden"), g[1], G)
		parterre(hub, G, F, g[2], g[3], g[4], 400 + i * 7)
	end
	-- base 8's lane (θ 337.5) between the bandstand and the θ 0 avenue: the walk, the beds and a
	-- pair of benches facing the tower
	local P = radialFrame(U.model(m, "LaneGarden"), 337.5, G)
	laneWalk(P, 0, LANE_PATH_IN, 149.4)
	laneBeds(hub, G, P, 0, { C.Flowers[1], C.Flowers[2] }, 460, 8)
	for _, sx in { -1, 1 } do
		parkBench(P.model, P:at(sx * 5.4, 0, 112, 0), 6, C.Wood)
	end
end

--[[
	Boat yard behind the Workshop (θ 128): a gravel yard behind a dry-stone wall (plaza side and
	both flanks), a rowboat on trestles, a workbench with tools, a hoist frame with a pulley and a
	hook, a little plank shed against the back wall and a stack of planks. ~40 parts.
]]
local function boatYard(parent: any, G: number)
	local Y = polarFrame(U.model(parent, "BoatYard"), 128, 0, G)
	gravelPath(Y, "YardFloor", -11, 125, 11, 147)
	stoneWall(Y, "WallBack", -11.6, 123.6, 11.6, 124.8, 1.6)
	for i, sx in { -1, 1 } do
		stoneWall(Y, `WallSide{i}`, sx * 11, 124.8, sx * 12.2, 140, 1.6)
	end
	for i, z in { 131.5, 137.5 } do
		Y:box(`Trestle{i}`, -8.6, -0.3, z - 0.5, -2.8, 2.0, z + 0.5, C.Wood)
	end
	Props.rowboat(parent, Y:at(-5.7, 2.55, 134.5, 180), { color = C.BoatPaint[1], seed = 74, oars = false })
	-- workbench with a plane and a saw, a hoist frame
	Y:box("Bench", -10.2, 1.9, 141.4, -4.6, 2.4, 143.4, C.WoodLight)
	for i, x in { -9.7, -5.1 } do
		Y:box(`BenchLeg{i}`, x - 0.3, -0.3, 141.6, x + 0.3, 1.9, 143.2, C.WoodDark, NOSHADOW)
	end
	for i, x in { -9.6, -1.6 } do
		Y:box(`HoistPost{i}`, x - 0.4, -0.3, 128.6, x + 0.4, 9.6, 129.4, C.WoodDark)
	end
	Y:box("HoistBeam", -10.2, 9.6, 128.5, -1.0, 10.4, 129.5, C.Wood)
	Y:box("HoistRope", -5.7, 5.2, 128.9, -5.5, 9.6, 129.1, C.Rope, DECOR)
	Y:box("HoistHook", -6.0, 4.4, 128.6, -5.2, 5.2, 129.4, C.Iron, DECOR)
	-- the shed against the back wall, a stack of planks
	Y:box("Shed", 3.6, -0.3, 125.2, 10.6, 5.2, 129.6, lerpColor(C.Wood, C.WoodDark, 0.3))
	Y:wedge("ShedRoof", 3.2, 5.2, 124.8, 11.0, 6.6, 130.4, C.RoofSlate, "-z")
	Y:box("ShedDoor", 5.6, -0.3, 129.6, 8.0, 4.4, 129.9, C.WoodDark, NOSHADOW)
	Y:box("Planks1", -10.6, -0.3, 145.2, -2.6, 0.9, 146.6, C.WoodLight)
end

--[[
	Koi garden on the lawn between the Fish Market and the harbour (θ 302, r 137), a little
	Japanese corner: a pond (a stone kerb round opaque water, a second lobe), a plank bridge with
	rails across its neck, stepping stones, lily pads (one in bloom), koi, a stone lantern, a stone
	bench and a red maple. ~36 parts.
]]
local function koiGarden(parent: any, G: number)
	local F = newFrame(U.model(parent, "KoiPond"), U.polarCFrame(302, 137, G))
	local rim
	for i, sz in { -1, 1 } do
		rim = F:box(`PondRim{i}`, -11, -0.3, sz * 5.1, 11, 0.9, sz * 6.5, C.StoneLight, FLAT)
		F:box(`PondRimEnd{i}`, sz * 9.6, -0.3, -5.1, sz * 11, 0.9, 5.1, C.StoneLight, FLAT)
	end
	F:box("PondWater", -9.6, -0.3, -5.1, 9.6, 0.6, 5.1, H.water, FLOW)
	-- the plank bridge across the pond (rails either side)
	F:box("Bridge", -1.6, 0.9, -7.2, 1.6, 1.5, 7.2, C.Wood)
	for i, sx in { -1, 1 } do
		F:box(`BridgeRail{i}`, sx * 1.5 - 0.15, 1.5, -5.8, sx * 1.5 + 0.15, 3.2, 5.8, C.Red, NOSHADOW)
	end
	for i, p in { { -6.5, -2.6, 3.0 }, { 5.6, 2.6, 2.6 }, { 6.8, -2.2, 2.0 } } do
		local w = p[3] / 2
		F:box(`LilyPad{i}`, p[1] - w, 0.5, p[2] - w, p[1] + w, 0.72, p[2] + w, C.Leaf2, DECOR)
	end
	F:box("LilyBloom", -7.0, 0.67, -3.1, -6.0, 1.47, -2.1, C.Pink, DECOR)
	for i, k in { { -4.0, 2.0, C.Orange, 1 }, { 4.0, -0.6, C.Red, -1 } } do
		F:box(`Koi{i}`, k[1] - 1.6, 0.3, k[2] - 0.65, k[1] + 1.6, 0.85, k[2] + 0.65, k[3], DECOR)
		local t0 = k[1] + k[4] * 1.6
		local t1 = t0 + k[4] * 1.3
		F:box(`KoiTail{i}`, math.min(t0, t1), 0.35, k[2] - 0.8, math.max(t0, t1), 0.8, k[2] + 0.8, C.Cream, DECOR)
	end
	-- stepping stones from the plaza side, a stone lantern, a stone bench
	for i, p in { { -4.2, -9.0 }, { -2.4, -11.6 }, { -4.6, -14.2 } } do
		F:box(`SteppingStone{i}`, p[1] - 1.0, -0.3, p[2] - 0.9, p[1] + 1.0, 0.3, p[2] + 0.9, C.StoneLight, FLAT)
	end
	F:box("LanternFoot", 12.4, -0.3, -9.4, 14.0, 1.0, -7.8, C.StoneLight)
	F:box("LanternPost", 12.8, 1.0, -9.0, 13.6, 3.2, -8.2, C.StoneLight)
	F:box("LanternBox", 12.2, 3.2, -9.6, 14.2, 4.8, -7.6, C.Glow, NEON)
	F:box("LanternRoof", 11.7, 4.8, -10.1, 14.7, 5.6, -7.1, C.StoneLight)
	F:box("StoneBench", -14.2, -0.3, -1.6, -12.6, 1.6, 4.6, C.StoneLight)
	F:box("StoneBenchTop", -14.5, 1.6, -2.0, -12.3, 2.0, 5.0, C.Stone, NOSHADOW)
	Props.autumnTree(parent, F:at(15.0, 0, 3.0), { seed = 81, scale = 1.05, lite = true })
	F.model.PrimaryPart = rim
end

--[[
	«СЦЕНА» bandstand behind the Fish Market (θ 318), facing the harbour boardwalk where its
	audience sits (frame origin = centre of the pavilion on the ground, −Z = the audience): a
	flagstone pad, a stone deck with a plank floor and two steps at the front, four cream posts
	with a balustrade round the sides and the back, a header with a red valance and the sign, a
	stepped tent roof in red and cream with a gold finial, the band's kit (drum, cymbal, microphone,
	amp), a hanging lantern; two benches angled towards it on the boardwalk. ~58 parts.
]]
local function buildBandstand(hub: any, cf: any, benchY: number)
	local F = newFrame(U.model(hub, "Bandstand"), cf)
	local accent, post = C.RoofRed, C.Cream
	F:box("Pad", -11.4, -0.3, -9.6, 11.4, 0.24, 11.4, C.Flagstone, FLAT)
	local deck = F:box("Deck", -7, -0.3, -7, 7, 2.2, 7, C.Limestone)
	F:box("Floor", -7.3, 2.2, -7.3, 7.3, 2.6, 7.3, C.Plank, FLAT)
	F:box("Step1", -3.6, -0.3, -9.4, 3.6, 0.95, -7, C.Limestone)
	F:box("Step2", -3.6, -0.3, -8.2, 3.6, 1.8, -7, C.Limestone)
	for i, d in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		F:box(`Post{i}`, d[1] * 5.9, 2.6, d[2] * 5.9, d[1] * 6.9, 10.6, d[2] * 6.9, post)
	end
	F:box("RailBack", -6.4, 4.3, 6.2, 6.4, 4.8, 6.6, post, NOSHADOW)
	for i, sx in { -1, 1 } do
		F:box(`RailSide{i}`, sx * 6.2, 4.3, -6.4, sx * 6.6, 4.8, 6.4, post, NOSHADOW)
	end
	-- the header ring and the red valance under the roof's eave
	F:box("HeaderFront", -7.2, 10.2, -7.2, 7.2, 11.2, -6.0, C.WoodDark)
	F:box("HeaderBack", -7.2, 10.2, 6.0, 7.2, 11.2, 7.2, C.WoodDark)
	for i, sx in { -1, 1 } do
		F:box(`HeaderSide{i}`, sx * 6.0, 10.2, -6.0, sx * 7.2, 11.2, 6.0, C.WoodDark)
	end
	F:box("ValanceFront", -8.6, 10.3, -8.7, 8.6, 11.2, -8.4, accent, NOSHADOW)
	F:box("ValanceBack", -8.6, 10.3, 8.4, 8.6, 11.2, 8.7, accent, NOSHADOW)
	-- the tent roof: stepped layers in red and cream, a gold finial
	local y = 11.2
	for k, r in { 8.7, 7.0, 5.2, 3.2 } do
		F:box(`Roof{k}`, -r, y, -r, r, y + 1.2, r, if k % 2 == 1 then accent else C.Cream)
		y += 1.2
	end
	F:box("FinialPole", -0.3, y, -0.3, 0.3, y + 2.2, 0.3, H.goldDeep, NOSHADOW)
	F:box("FinialKnob", -0.65, y + 2.2, -0.65, 0.65, y + 3.3, 0.65, H.goldDeep, DECOR)
	signBoard(F, "Sign", -3.6, 3.6, 8.4, 9.8, -7.3, C.Cream, C.WoodDark, "СЦЕНА", "СЦЕНА", H.curtain)
	-- the band's kit
	F:column("Drum", 2.8, -3.6, 3.4, 2.6, 4.6, H.tile)
	F:box("DrumRim", -5.1, 4.6, 1.9, -2.1, 4.9, 4.9, C.Cream, NOSHADOW)
	F:box("Cymbal", -2.2, 6.2, 3.4, 0.2, 6.45, 5.8, C.Gold, DECOR)
	F:column("MicStand", 0.3, 1.2, -2.0, 2.6, 7.4, C.Iron, DECOR)
	F:box("Mic", 0.8, 7.4, -2.4, 1.6, 8.4, -1.6, C.Dark, DECOR)
	F:box("Amp", 3.0, 2.6, 2.4, 6.0, 6.0, 5.2, C.Wood)
	F:box("LanternCord", -0.1, 9.0, -0.1, 0.1, 11.2, 0.1, C.Dark, DECOR)
	local lamp = F:box("Lantern", -0.7, 7.6, -0.7, 0.7, 9.0, 0.7, C.Glow, NEON_DECOR)
	pointLight(lamp, 16, 1.3)
	-- the audience's benches in an arc on the boardwalk, facing the stage
	for _, p in { { -5, -19.5, 195 }, { 5, -19.5, 165 } } do
		parkBench(F.model, F:at(p[1], benchY, p[2], p[3]), 7, C.Wood)
	end
	F.model.PrimaryPart = deck
end

--[[
	The lawns: a cherry tree behind the Shop, the boat yard behind the Workshop, the koi garden
	behind the Fish Market, a picnic by the θ 180 landing and two big oaks beside the bases' lines
	of sight.
]]
local function buildLawns(hub: any, G: number)
	local m = U.model(hub, "Lawns")
	local g = polarFrame(m, 32, 0, G)
	Props.cherryTree(m, g:at(-3, 0, 137), { seed = 71, scale = 1.4, lite = true })
	boatYard(m, G)
	koiGarden(m, G)
	-- a picnic on the lawn by the θ 180 landing: a checked blanket with a basket on it
	local P = newFrame(U.model(m, "Picnic"), U.polarCFrame(193, 146, G) * CFrame.Angles(0, rad(20), 0))
	P.model.PrimaryPart = P:box("Blanket", -2.8, -0.3, -2.2, 2.8, 0.14, 2.2, C.Red, FLAT)
	P:box("BlanketCheck", -0.5, -0.3, -2.3, 0.5, 0.2, 2.3, C.Cream, FLAT)
	P:box("Basket", 0.9, 0.14, -1.2, 2.5, 1.3, 0.2, C.Straw)
	P:box("BasketHandle", 1.55, 1.3, -1.0, 1.85, 2.1, 0.0, C.WoodDark, DECOR)
	for _, t in { { 282, 130 }, { 209.5, 132 } } do
		Props.oakTree(m, polarFrame(m, t[1], 0, G):at(0, 0, t[2]), { seed = floor(t[1]) + 4, scale = 1.4, lite = true })
	end
end

--------------------------------------------------------------------------------
-- Avenue frontages: a pocket garden and street trees on the lawns beside every avenue
--------------------------------------------------------------------------------

--[[
	Street frontage beside every avenue between the plaza and the welcome gate (built after the
	cottages, gardens and lawns, so it fits round them), so the avenue reads as a street of trees,
	flowers and benches rather than a road through a field: on the open side, behind the clipped
	hedge, a kerbed bed of jewel-tone blooms and a bench behind it looking over the flowers at the
	avenue with a gravel walk out to the next lane; rounded voxel street trees out on the lawn
	(Props broadleaf, lite and compact: two on the open side, one on the other), each standing
	where nothing else of the hub does and off the bases' lines of sight. ~30 parts per avenue.
]]
local function buildFrontages(hub: any, cfg: any, G: number)
	for i, angle in cfg.BridgeAngles do
		local look = FRONTAGE[(i - 1) % #FRONTAGE + 1]
		local F = radialFrame(hub:FindFirstChild("Avenues"):FindFirstChild(`Avenue{i}`), angle, G)
		local zc = if angle % 360 == 180 then 104 else 112 -- the bed's middle (r): clear of the lamps
		local c1, c2 = C.Flowers[look.beds[1]], C.Flowers[look.beds[2]]
		-- the parterre side (+X, towards the garden on the next base lane) and the open side (−X)
		for j, sx in { -1, 1 } do
			if sx < 0 then
				Props.flowerBed(F.model, F:at(sx * 21.6, 0, zc), {
					width = 3.6,
					depth = 12,
					colors = { c1, c2 },
					spacing = 2.0,
					stems = false,
					max = 5,
					kerb = C.Limestone,
					seed = 500 + i * 10 + j,
				})
				parkBench(F.model, F:at(sx * 26.2, 0, zc, sx * 90), 7, C.Wood)
				-- a gravel walk from the bench out to the next base lane's path (about r·tan 22.5°
				-- out), or as far as the lawn is free
				local x1 = zc * 0.414 + 0.5
				while x1 > 32 do
					local q = F:point(sx * x1, 0, zc)
					if groundClear(hub, G, q.X, q.Z, 2.4) then
						break
					end
					x1 -= 2
				end
				gravelPath(F, "SideWalk", sx * 27.4, zc - 1.5, sx * x1, zc + 1.5)
			end
			local want = if sx < 0 then 2 else 1
			local candidates = if sx < 0
				then {
					{ 31, zc - 9 },
					{ 34, zc + 9 },
					{ 28, zc + 18 },
					{ 37, zc - 3 },
					{ 33, zc - 20 },
					{ 25, zc - 19 },
					{ 40, zc + 14 },
					{ 27, zc - 28 },
				}
				else {
					{ 24, zc + 19 },
					{ 23, zc - 16 },
					{ 28, zc + 24 },
					{ 27, zc + 6 },
					{ 31, zc - 8 },
					{ 24, zc - 27 },
				}
			local placed = 0
			for _, c in candidates do
				if placed >= want then
					break
				end
				-- the trunk clear of everything on the ground, the crown of everything tall, and
				-- the whole tree off the bases' lines of sight to the tower
				local p = F:point(sx * c[1], 0, c[2])
				-- (the lane beds are only planted at the end: their queued footprints count too)
				local offBeds = true
				for _, b in LANE_BEDS do
					local q = b.cf.Position
					if (V(q.X, 0, q.Z) - V(p.X, 0, p.Z)).Magnitude < 8.5 then
						offBeds = false
					end
				end
				if
					offBeds
					and not nearLane(p.X, p.Z, 10)
					and groundClear(hub, G, p.X, p.Z, 1.8, 0.3)
					and groundClear(hub, G, p.X, p.Z, 5.6, 5)
				then
					placed += 1
					-- a rounded voxel broadleaf (three canopy layers in two or three shades)
					local opts = {
						seed = 600 + i * 10 + j * 3 + placed,
						scale = 0.82,
						lite = true,
						compact = true,
						palette = look.palette,
						name = `StreetTree{j}_{placed}`,
					}
					if look.tree == "cherry" then
						Props.cherryTree(F.model, F:at(sx * c[1], 0, c[2], 0), opts)
					else
						Props.roundTree(F.model, F:at(sx * c[1], 0, c[2], 0), opts)
					end
				end
			end
		end
	end
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

local PALM_ANGLES = { 36, 104, 136, 216, 258 } -- (the avenue ends have their own)

-- CFrame on the real ground at (θ, r), turned to face θ + yaw (0 = towards the centre).
local function groundCf(world: any, a: number, r: number, yaw: number?): any
	local p = U.polar(a, r, 0)
	return CFrame.new(p.X, world:heightAt(p.X, p.Z), p.Z) * CFrame.Angles(0, rad(a + (yaw or 0)), 0)
end

-- Frame of a beach zone at (θ, r) on the sand, its local −Z towards the water (X = lower θ).
local function zoneFrame(parent: any, name: string, world: any, a: number, r: number): any
	return newFrame(U.model(parent, name), groundCf(world, a, r, 180))
end

-- Small beach parasol on local (x, z) of frame F, its foot at y0: a white pole and a canopy in
-- `canopy` under a cream top. 3 parts.
local function miniParasol(F: any, x: number, z: number, y0: number, canopy: any)
	F:column("ParasolPole", 0.35, x, z, y0 - 0.3, y0 + 6.4, C.White, NOSHADOW)
	F:box("Parasol", x - 3.2, y0 + 5.2, z - 3.2, x + 3.2, y0 + 5.8, z + 3.2, canopy, { CanCollide = false })
	F:box("ParasolTop", x - 2.0, y0 + 5.8, z - 2.0, x + 2.0, y0 + 6.5, z + 2.0, C.Cream, DECOR)
end

--[[
	Beach bar (θ 26.6, base 1's lane): a plank deck on the sand, a plank hut with its counter to
	the lagoon under a thatched roof on two front posts (a blue stripe on the counter, a shelf of
	bottles behind it, three stools), the «КАФЕ» board on the ridge, two tables with parasols and
	stools on the deck. ~32 parts.
]]
local function beachCafe(parent: any, world: any)
	local F = zoneFrame(parent, "BeachCafe", world, 26.6, 175)
	local deck = F:box("Deck", -11, -0.6, -6.6, 11, 0.9, 7.2, C.Plank, FLAT)
	-- the hut: the back room, the counter in front of it, the front posts
	F:box("Hut", -6.4, 0.9, 2.2, 6.4, 7.6, 6.8, lerpColor(C.Plank, C.Plaster, 0.35))
	F:box("Counter", -6.4, 0.9, -0.4, 6.4, 3.9, 2.2, C.Wood)
	F:box("CounterTop", -6.8, 3.9, -0.8, 6.8, 4.4, 2.4, C.WoodLight)
	F:box("CounterStripe", -6.45, 2.0, -0.55, 6.45, 2.8, 1.0, C.RoofBlue, NOSHADOW)
	F:box("Shelf", -5.2, 5.4, 1.9, 5.2, 5.8, 2.3, C.WoodDark, NOSHADOW)
	for k = 1, 4 do
		local x = -4.2 + (k - 1) * 2.8
		local col = C.Flowers[(k * 2) % #C.Flowers + 1]
		F:box(`Bottle{k}`, x - 0.35, 5.8, 1.95, x + 0.35, 7.0, 2.25, col, DECOR)
	end
	for i, sx in { -1, 1 } do
		F:box(`Post{i}`, sx * 6.2 - 0.4, 0.9, -1.4, sx * 6.2 + 0.4, 8.4, -0.6, C.WoodDark)
	end
	-- thatched roof (ridge along X) over the counter and the hut
	local ridgeTop = gableRoof(F, "Roof", 0, 2.6, "x", 6.8, 4.2, 8.2, 3.6, {
		roof = C.Straw,
		ridge = lerpColor(C.Straw, C.Wood, 0.45),
		gables = {},
		ov = 1.4,
		og = 0.8,
		noEaves = true,
	})
	signBoard(
		F,
		"Sign",
		-3.2,
		3.2,
		ridgeTop + 0.6,
		ridgeTop + 2.6,
		2.6,
		C.Cream,
		C.WoodDark,
		"КАФЕ",
		"КАФЕ",
		C.Navy
	)
	for k = 1, 3 do
		local x = (k - 2) * 3.6
		F:box(`BarStool{k}`, x - 0.7, 0.9, -2.6, x + 0.7, 3.0, -1.2, C.Wood)
	end
	-- two tables with parasols and stools out on the deck
	for i, sx in { -1, 1 } do
		local x, z = sx * 7.4, -5.2
		F:box(`TablePost{i}`, x - 0.25, 0.9, z - 0.25, x + 0.25, 3.4, z + 0.25, C.WoodDark, NOSHADOW)
		F:box(`Table{i}`, x - 1.3, 3.4, z - 1.3, x + 1.3, 3.8, z + 1.3, C.WoodLight)
		for j, dx in { -1, 1 } do
			F:box(`Stool{i}_{j}`, x + dx * 2.3 - 0.6, 0.9, z - 0.6, x + dx * 2.3 + 0.6, 2.5, z + 0.6, C.Wood)
		end
		miniParasol(F, x, z, 3.8, if sx < 0 then C.RoofBlue else C.Flowers[1])
	end
	F.model.PrimaryPart = deck
end

--[[
	Bathing huts (θ 67.5, base 2's lane): three huts in a row on a shared plank deck, facing the
	lagoon — plank walls tinted in the hut's colour, a plank skirt, a tiled gable roof with a
	cream ridge, a door in the hut's colour with a cream stripe; a towel rail with two towels.
	~27 parts.
]]
local function bathingHuts(parent: any, world: any)
	local F = zoneFrame(parent, "BathingHuts", world, 63, 174)
	local deck = F:box("Deck", -12.5, -0.6, -4.2, 12.5, 0.9, 4.6, C.Plank, FLAT)
	for i, main in { C.RoofRed, C.RoofBlue, C.RoofGreen } do
		local x = (i - 2) * 8
		F:box(`Hut{i}`, x - 2.5, 0.9, -1.4, x + 2.5, 6.6, 3.6, lerpColor(C.Plaster, main, 0.18))
		F:box(`Skirt{i}`, x - 2.65, 0.9, -1.55, x + 2.65, 1.7, 3.75, C.WoodDark, NOSHADOW)
		gableRoof(F, `HutRoof{i}`, x, 1.1, "z", 2.75, 2.7, 6.6, 2.6, {
			roof = main,
			ridge = C.Cream,
			gables = {},
			noEaves = true,
			ov = 0.6,
			og = 0.5,
		})
		F:box(`HutDoor{i}`, x - 1.2, 1.7, -1.7, x + 1.2, 5.6, -1.3, main, NOSHADOW)
		F:box(`DoorStripe{i}`, x - 1.3, 3.2, -1.82, x + 1.3, 3.9, -1.6, C.Cream, DECOR)
	end
	for i, z in { -3.2, 1.2 } do
		F:box(`RailPost{i}`, 11.6, 0.9, z - 0.2, 12.0, 4.2, z + 0.2, C.WoodDark, NOSHADOW)
	end
	F:box("Rail", 11.65, 3.8, -3.4, 11.95, 4.1, 1.4, C.WoodDark, DECOR)
	F:box("Towel1", 11.6, 2.2, -2.6, 12.0, 3.9, -1.3, lerpColor(C.Red, C.Cream, 0.2), DECOR)
	F:box("Towel2", 11.6, 2.6, -0.7, 12.0, 3.9, 0.6, lerpColor(C.Cyan, C.Cream, 0.2), DECOR)
	F.model.PrimaryPart = deck
end

--[[
	Fishing corner (θ 112.5, base 3's lane): a rowboat pulled up on the sand, an upturned hull, a
	net rack with a net hung to dry, a crate and a lobster pot, a piece of driftwood. ~30 parts.
]]
local function fishingCorner(parent: any, world: any)
	local F = zoneFrame(parent, "FishingCorner", world, 112.5, 175)
	Props.rowboat(F.model, F:at(-5.5, 0, -1, 160), { color = C.BoatPaint[4], seed = 140 })
	local hull = F:box("Hull", 3.2, -0.3, -3.6, 7.4, 1.3, 4.8, C.BoatPaint[6])
	F:box("HullKeel", 5.0, 1.3, -4.0, 5.6, 1.9, 5.2, C.WoodDark, NOSHADOW)
	F:box("HullBow", 3.9, -0.2, -5.2, 6.7, 1.1, -3.6, shade(C.BoatPaint[6], 0.85))
	for i, x in { 10.0, 15.6 } do
		F:box(`RackPost{i}`, x - 0.3, -0.3, 2.2, x + 0.3, 6.4, 2.8, C.WoodDark)
	end
	F:box("RackBar", 9.6, 6.0, 2.25, 16.0, 6.6, 2.75, C.Wood, NOSHADOW)
	F:box("Net", 10.4, 1.6, 2.4, 15.2, 6.0, 2.6, lerpColor(C.Twine, C.WoodDark, 0.35), DECOR)
	Props.crate(F.model, F:at(-12.2, 0, 2.4), { seed = 141, size = 2.6, color = C.Wood })
	F:box("LobsterPot", -12.8, -0.3, -1.4, -10.4, 1.6, 0.4, lerpColor(C.Twine, C.Wood, 0.5))
	F:box("LobsterPotTop", -12.5, 1.6, -1.1, -10.7, 1.9, 0.1, C.WoodDark, DECOR)
	Props.log(F.model, F:at(12.8, 0, -3.4, 25), { seed = 142, length = 6 })
	F.model.PrimaryPart = hull
end

--[[
	Lifeguard tower (θ 157.5, base 4's lane): white legs, a platform, a cream cabin with a window
	band under a red roof, a ladder, a red flag on a pole and a lifebuoy. ~15 parts.
]]
local function lifeguard(parent: any, world: any)
	local F = zoneFrame(parent, "Lifeguard", world, 161, 176)
	for i, d in { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } } do
		F:box(`Leg{i}`, d[1] * 2.0 - 0.3, -0.3, d[2] * 2.0 - 0.3, d[1] * 2.0 + 0.3, 6.2, d[2] * 2.0 + 0.3, C.White)
	end
	local floor = F:box("Platform", -2.9, 6.2, -2.9, 2.9, 6.8, 2.9, C.WoodLight)
	F:box("Cabin", -2.3, 6.8, -1.6, 2.3, 9.6, 2.3, C.Cream)
	F:box("CabinWindow", -2.0, 8.0, -1.75, 2.0, 9.2, -1.5, C.WindowBlue, NOSHADOW)
	F:box("CabinRoof", -3.0, 9.6, -2.6, 3.0, 10.4, 3.0, C.Red)
	F:box("Ladder", -0.8, -0.3, 2.9, 0.8, 6.2, 3.3, C.WoodLight, NOSHADOW)
	F:box("FlagPole", 2.55, 10.4, 2.55, 2.85, 14.2, 2.85, C.White, NOSHADOW)
	Kit.sway(F:box("Flag", 2.85, 12.4, 2.62, 5.2, 14.0, 2.78, C.Red, DECOR), F:at(2.85, 13.2, 2.7), 10, "Y", 2.2)
	Props.lifebuoy(F.model, F:at(0, 3.4, -2.35, 0), { seed = 150 })
	F.model.PrimaryPart = floor
end

--[[
	Kayak rack by the fun fair (θ 205): two timber A-frames with two cross bars carrying three
	kayaks in jewel tones, a paddle leaning on it. 8 parts.
]]
local function kayakRack(parent: any, world: any)
	local F = zoneFrame(parent, "KayakRack", world, 205, 174.5)
	for i, x in { -3.2, 3.2 } do
		F:box(`RackPost{i}`, x - 0.35, -0.3, -0.35, x + 0.35, 4.6, 0.35, C.WoodDark)
	end
	for i, y in { 1.6, 3.6 } do
		F:box(`RackBar{i}`, -3.8, y, -1.3, 3.8, y + 0.4, 1.3, C.Wood, NOSHADOW)
	end
	F.model.PrimaryPart = F.model:FindFirstChild("RackPost1")
	-- two kayaks side by side on the lower bar, one on the upper
	for i, k in { { 2.0, -0.6, 1 }, { 2.0, 0.6, 6 }, { 4.0, 0, 3 } } do
		F:box(`Kayak{i}`, -5.2, k[1], k[2] - 0.5, 5.2, k[1] + 0.7, k[2] + 0.5, C.BoatPaint[k[3]], NOSHADOW)
	end
	F:box("Paddle", 4.0, -0.2, 1.6, 4.4, 5.2, 2.0, C.WoodLight, DECOR)
end

--[[
	Rocks at the waterline with a tide pool between them and a starfish on its rim (θ, r on the
	sand's edge). 4 parts.
]]
local function tidePool(parent: any, world: any, a: number, r: number, seed: number)
	local F = zoneFrame(parent, "TidePool", world, a, r)
	local flip = if seed % 2 == 0 then 1 else -1
	F.model.PrimaryPart = F:box("Rock", flip * 1.2, -0.8, -1.6, flip * 4.6, 2.2, 1.8, C.RockMid)
	F:box("RockSmall", -flip * 3.4, -0.8, -2.2, -flip * 1.4, 1.1, -0.2, C.RockLight)
	F:box("Pool", -flip * 1.6, -0.3, -0.2, flip * 1.4, 0.12, 2.6, H.water, FLAT)
	F:box("Starfish", flip * 1.6, 2.2, -0.6, flip * 2.6, 2.45, 0.4, C.Orange, DECOR)
end

--[[
	A bathing group on the sand (zone frame, −Z to the water): a parasol in `canopy` over two
	loungers side by side (light wooden frames with reclined cushions, heads landwards), two
	beach towels in jewel tones in front of them, a cooler with a white lid and a sand bucket.
	12 parts.
]]
local function bathingGroup(F: any, canopy: any, cushion: any, towels: { any }, cooler: any)
	miniParasol(F, 0, 1.8, 0, canopy)
	for i, sx in { -1, 1 } do
		local x = sx * 1.9
		F:box(`Lounger{i}`, x - 1.05, -0.2, -1.6, x + 1.05, 0.8, 3.6, C.WoodLight)
		F:wedge(`LoungerBack{i}`, x - 0.95, 0.8, 1.6, x + 0.95, 2.5, 3.5, cushion, "+z", NOSHADOW)
		F:box(`Towel{i}`, sx * 2.8 - 1.2, -0.1, -6.6, sx * 2.8 + 1.2, 0.15, -2.6, towels[i], FLAT)
	end
	F:box("Cooler", 4.4, -0.2, 0.2, 6.0, 1.2, 1.4, cooler)
	F:box("CoolerLid", 4.3, 1.2, 0.1, 6.1, 1.55, 1.5, C.White, NOSHADOW)
	F:box("Bucket", -5.0, -0.2, -3.6, -4.0, 0.9, -2.6, C.Red, DECOR)
end

-- A canoe pulled up on the sand at local (x, z) along local Z: a painted hull, its dark inside and
-- a paddle lying across it. 3 parts.
local function canoe(F: any, x: number, z: number, col: any)
	F:box("Canoe", x - 0.95, -0.2, z - 3.8, x + 0.95, 0.9, z + 3.8, col)
	F:box("CanoeInside", x - 0.6, 0.6, z - 3.0, x + 0.6, 0.98, z + 3.0, shade(C.Wood, 0.75), DECOR)
	F:box("Paddle", x - 2.4, 0.98, z - 0.25, x + 1.7, 1.2, z + 0.25, C.WoodLight, DECOR)
end

-- Beach lamp on local (x, z), its foot at y0: a dark post, a glowing cube and an iron cap. 3 parts.
local function beachLamp(F: any, x: number, z: number, y0: number)
	F:box("LampPost", x - 0.35, y0 - 0.3, z - 0.35, x + 0.35, y0 + 6.2, z + 0.35, C.WoodDark, NOSHADOW)
	F:box("LampGlow", x - 0.75, y0 + 6.2, z - 0.75, x + 0.75, y0 + 7.8, z + 0.75, C.Glow, NEON_DECOR)
	F:box("LampCap", x - 1.05, y0 + 7.8, z - 1.05, x + 1.05, y0 + 8.3, z + 1.05, C.Iron, DECOR)
end

--[[
	Plank walk along the beach at the foot of the terrace steps (a chord from θ a0 to a1, its
	middle at r): the deck a step above the sand, dark board joints across it and a beach lamp at
	each end on the land side. 10 parts.
]]
local function beachWalk(parent: any, a0: number, a1: number, r: number)
	local m = U.model(parent, "BeachWalk")
	local mid = (a0 + a1) / 2
	local F = radialFrame(m, mid, 0)
	local len = 2 * r * math.tan(rad((a1 - a0) / 2))
	m.PrimaryPart = F:box("Deck", -len / 2, 1.8, r - 2.2, len / 2, 2.7, r + 2.2, C.Plank, FLAT)
	for k = 2, 2 do
		local x = -len / 2 + len * k / 4
		F:box(`Joint{k}`, x - 0.3, 2.7, r - 2.2, x + 0.3, 2.78, r + 2.2, shade(C.Plank, 0.72), DECOR)
	end
	for _, sx in { -1, 1 } do
		beachLamp(F, sx * (len / 2 - 1.6), r - 1.4, 2.7)
	end
end

--[[
	Boathouse on stilts at the water's edge (θ 124, r 186): a plank deck from the beach out over
	the shallows on two stilts, a seafoam plank shed with a big dark boat door to the lagoon and a
	red bow peeking out of it, a clay roof (ridge towards the water). 9 parts.
]]
local function boathouse(parent: any)
	local a, r = 124, 186
	local p = U.polar(a, r, 0)
	-- frame on the water surface, −Z out to the lagoon, +Z up the beach
	local F = newFrame(U.model(parent, "Boathouse"), CFrame.new(p.X, 0, p.Z) * CFrame.Angles(0, rad(a + 180), 0))
	local deck = F:box("Deck", -7, 2.2, -8.4, 7, 3.2, 6.4, C.Plank, FLAT)
	for i, sx in { -1, 1 } do
		F:box(`Stilt{i}`, sx * 6.2 - 0.6, -5, -8.0, sx * 6.2 + 0.6, 2.2, -6.8, C.WoodDark)
	end
	F:box("Shed", -5, 3.2, -5.2, 5, 9.6, 4.2, lerpColor(C.Cyan, C.Plaster, 0.55))
	F:box("BoatDoor", -3.2, 3.2, -5.45, 3.2, 8.2, -5.0, shade(C.WoodDark, 0.6), NOSHADOW)
	F:box("BoatBow", -1.1, 2.9, -7.8, 1.1, 4.4, -5.2, C.BoatPaint[1])
	gableRoof(F, "Roof", 0, -0.5, "z", 4.7, 5.0, 9.6, 3.4, {
		roof = H.roofClay,
		gables = {},
		ov = 0.9,
		og = 0.9,
		noEaves = true,
	})
	F.model.PrimaryPart = deck
end

-- Two tufts of beach grass in two greens round (θ a, r) on the sand. 2 parts.
local function grassTufts(parent: any, world: any, a: number, r: number)
	local F = zoneFrame(parent, "BeachGrass", world, a, r)
	local dry = lerpColor(C.Palm3, C.Straw, 0.35) -- dune grass, a little sun-bleached
	for k, t in { { -0.8, 0.3, 1.7, C.Palm2, 0.5 }, { 0.7, -0.3, 2.3, dry, 0.4 } } do
		F:box(`Tuft{k}`, t[1] - t[5], -0.2, t[2] - t[5], t[1] + t[5], t[3], t[2] + t[5], t[4], DECOR)
	end
	F.model.PrimaryPart = F.model:FindFirstChild("Tuft1")
end

--[[
	The beach ring, a continuous waterfront in front of the bases' lanes (each zone set a little
	to the side of its lane, so the lane's middle stays open towards the tower): the beach bar
	(θ 26.6), bathing huts (θ 63) with a bathing group and a swimming line of floats beside them,
	the fishing corner (θ 112.5), the boathouse on stilts (θ 124), a lifeguard tower (θ 161), a
	kayak rack by the fun fair (θ 205), canoes pulled up on the sand, plank walks with lamps at the
	foot of the steps (θ 138..152, 218..236) each with a bathing group beside it, rocks with tide
	pools at the waterline in the gaps, a sandcastle, big palms and tufts of dune grass along the
	foot of the steps; the harbour (θ 285 .. 345) has its own boardwalk.
]]
local function buildBeach(hub: any, world: any)
	local m = U.model(hub, "Beach")
	local R = L.beach
	for k, a in PALM_ANGLES do
		local r = if k % 2 == 0 then R - 3 else R + 2
		Props.palmTree(m, groundCf(world, a, r, k * 47), { seed = 100 + k, scale = 1.45 + (k % 3) * 0.2, lite = true })
	end
	beachCafe(m, world)
	bathingHuts(m, world)
	fishingCorner(m, world)
	lifeguard(m, world)
	kayakRack(m, world)
	boathouse(m)
	beachWalk(m, 138, 152, 169)
	beachWalk(m, 218.5, 236, 169)
	-- three bathing groups: θ, parasol, cushions, towels, cooler (jewel tones: the beach's colour
	-- pops), each beside a zone so the beach reads busy in clusters
	local J = C.Flowers
	for _, b in
		{
			{ 76.5, J[1], C.Cream, { J[7], J[3] }, C.RoofBlue },
			{ 145, J[2], J[7], { J[1], J[5] }, C.Cyan },
			{ 228, J[7], J[2], { J[6], J[4] }, C.Red },
		}
	do
		local Z = zoneFrame(m, "BathingGroup", world, b[1], 177.5)
		bathingGroup(Z, b[2], b[3], b[4], b[5])
		Z.model.PrimaryPart = Z.model:FindFirstChild("Lounger1")
	end
	-- rocks with tide pools at the waterline in the gaps between the zones
	for k, a in { 96.5, 188.5, 241 } do
		tidePool(m, world, a, 183.2, k)
	end
	-- canoes pulled up by the water
	for _, c in { { 101, 2 }, { 253.5, 3 } } do
		local Z = zoneFrame(m, "Canoe", world, c[1], 180.5)
		canoe(Z, 0, 0, C.BoatPaint[c[2]])
		Z.model.PrimaryPart = Z.model:FindFirstChild("Canoe")
	end
	-- a sandcastle with a little flag
	local S = zoneFrame(m, "Sandcastle", world, 171.5, 180)
	S.model.PrimaryPart = S:box("Castle", -1.6, -0.2, -1.6, 1.6, 1.3, 1.6, C.SandDark, FLAT)
	S:box("CastleTower", -0.8, 1.3, -0.8, 0.8, 2.8, 0.8, C.Sand)
	S:box("CastleFlag", 0.1, 2.8, -0.05, 1.0, 3.5, 0.05, C.Red, DECOR)
	-- a swimming line of floats off the bathing beach
	for k = 0, 3 do
		local q = U.polar(71.5 + k * 3.4, 193, 0.25)
		U.part(
			m,
			"Float",
			V(1.3, 1.3, 1.3),
			CFrame.new(q),
			if k % 2 == 0 then C.Red else C.White,
			nil,
			merge(DECOR, { Shape = Enum.PartType.Ball })
		)
	end
	-- tufts of beach grass along the foot of the terrace steps
	for _, a in { 14, 46, 110, 122, 167, 196, 214, 244, 255 } do
		grassTufts(m, world, a, 167.6)
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
		-- boards in two tones chord by chord (the light ones 0.06 lower, so the thin wedges where
		-- the chords overlap at the inner joints never share a plane), dark joints across each
		local light = k % 2 == 1
		local dTop = if light then top - 0.06 else top
		local tone = if light then lerpColor(C.Plank, C.WoodLight, 0.5) else C.Plank
		F:box(`Deck{k + 1}`, -len / 2 - 0.1, top - 0.8, rIn, len / 2 + 0.1, dTop, rOut, tone, FLAT)
		for q, t in { 0 } do
			local x = t * len
			F:box(
				`DeckJoint{k + 1}_{q}`,
				x - 0.25,
				dTop,
				rIn + 6,
				x + 0.25,
				dTop + 0.07,
				rOut,
				shade(C.Plank, 0.7),
				DECOR
			)
		end
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
	parkBench(bw, polarFrame(bw, 306, rOut - 3, top):at(0, 0, 0, 180), 7, C.Wood)
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
	for i, z in { r0 + 33 } do
		P:box(`BuoyPost{i}`, 4.6, water - 8, z - 0.6, 5.8, deck + 4.4, z + 0.6, C.WoodDark)
		Props.lifebuoy(m, P:at(5.2, deck + 3, z - 0.93, 0), { seed = 214 + i })
	end
	-- an anchor on a stone plinth on the beach by the boardwalk
	local A = newFrame(U.model(m, "AnchorPlinth"), groundCf(world, 338, r0 + 8.5, 90))
	A.model.PrimaryPart = A:box("PlinthBase", -5.6, -0.3, -2.2, 5.6, 0.6, 2.2, C.StoneDark)
	A:box("Plinth", -5.0, 0.6, -1.6, 5.0, 1.6, 1.6, C.Limestone)
	Props.anchor(m, A:at(0, 1.6, 0), { seed = 220, scale = 1.3 })
	-- fish crates at the pier's root
	local Q = newFrame(U.model(m, "PierRoot"), U.polarCFrame(pierA - 3.2, r0 - 2.5, G - 0.4))
	Q.model.PrimaryPart = Q:box("FishCrate", -1.4, 0, -1.2, 1.4, 1.8, 1.2, C.Wood)
	Q:box("FishCrate2", -1.1, 1.8, -0.9, 1.4, 3.1, 1.0, C.WoodLight)
	Q:box("FishCrateFish", -0.8, 3.1, -0.6, 1.1, 3.45, 0.6, H.fish[1], DECOR)

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
	table.clear(LANE_BEDS)

	buildPlaza(hub, G)
	buildTower(hub, G)
	buildSpawn(hub, G)
	buildPlazaFurniture(hub, G)

	buildShop(hub, U.polarCFrame(45, SHOP_R, G))
	buildFishMarket(hub, U.polarCFrame(315, SHOP_R, G))
	buildWorkshop(hub, U.polarCFrame(135, SHOP_R, G))

	buildAvenues(hub, cfg, G)
	buildFair(hub, G)
	-- the bandstand behind the Fish Market faces the harbour boardwalk (its benches stand on the
	-- boardwalk deck, 0.4 below the lawn)
	buildBandstand(hub, U.polarCFrame(318, 140, G) * CFrame.Angles(0, math.pi, 0), -0.4)
	buildCottages(hub, G)
	buildGardens(hub, G)
	buildLawns(hub, G)
	buildFrontages(hub, cfg, G)
	buildTerrace(hub, cfg, G)
	buildLandingPalms(hub, cfg, world, G)
	buildBeach(hub, world)
	buildHarbour(hub, cfg, world)
	-- the lane beds last, with what is left of the part budget (a few parts spare)
	placeLaneBeds(MAX_PARTS - (U.partCount - startCount) - 4)
	table.clear(LANE_BEDS)

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
