--[[
	Builds Workspace.Map: voxel-style shore around a round lake, the central hub island with
	the shop, bridges, decor, ocean, invisible boundaries and the 8 base slots.

	Coordinates: angle θ (degrees, 0 = +Z) and radius r map to (r·sin θ, y, r·cos θ).
	All heights come from MapConfig (GroundTop, WaterTop, LakeBottom, HubTop).
]]

local U = require("./Util")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Enum = U.Enum
local rgb = U.rgb

local C = {
	grass = rgb(98, 178, 72),
	sand = rgb(234, 212, 152),
	hubSand = rgb(238, 220, 165),
	seabed = rgb(206, 190, 140),
	water = rgb(40, 160, 220),
	wood = rgb(160, 112, 68),
	woodDark = rgb(105, 72, 45),
	rail = rgb(120, 82, 50),
	stone = rgb(150, 150, 155),
	cobble = rgb(178, 176, 166),
	rock = rgb(128, 128, 134),
	cliff = rgb(140, 132, 120),
	trunk = rgb(150, 105, 60),
	leaves = rgb(72, 168, 60),
	leavesTop = rgb(92, 140, 52),
	lampGlow = rgb(255, 205, 120),
	white = rgb(245, 245, 245),
	shopBlue = rgb(40, 110, 200),
	gold = rgb(255, 190, 40),
	red = rgb(215, 45, 45),
}

local LOCKED = { Locked = true }
-- Flush ground/seabed slabs: locked in Studio and no shadow casting (they never cast a visible shadow).
local SLAB = { Locked = true, CastShadow = false }

--------------------------------------------------------------------------------
-- Small reusable props
--------------------------------------------------------------------------------

local function lamp(parent: any, ground: any, height: number?)
	local h = height or 5
	local model = U.model(parent, "Lamp")
	U.part(
		model,
		"Post",
		Vector3.new(0.6, h, 0.6),
		CFrame.new(ground + Vector3.new(0, h / 2, 0)),
		C.woodDark,
		Enum.Material.Wood,
		{ CastShadow = false }
	)
	U.part(
		model,
		"Light",
		Vector3.new(1.2, 1.2, 1.2),
		CFrame.new(ground + Vector3.new(0, h + 0.6, 0)),
		C.lampGlow,
		Enum.Material.Neon,
		{ CastShadow = false }
	)
	return model
end

-- Voxel palm: 2 trunk segments, a crown block and 3 crossed leaf slabs.
local function palm(parent: any, ground: any, rotY: number?, scale: number?)
	local s = scale or 1
	local model = U.model(parent, "Palm")
	local base = CFrame.new(ground) * CFrame.Angles(0, math.rad(rotY or 0), 0)
	U.part(model, "Trunk", Vector3.new(1.3, 6, 1.3) * s, base * CFrame.new(0, 3 * s, 0), C.trunk, Enum.Material.Wood)
	U.part(
		model,
		"TrunkTop",
		Vector3.new(1.1, 5, 1.1) * s,
		base * CFrame.new(0.35 * s, 8.4 * s, 0) * CFrame.Angles(0, 0, math.rad(-5)),
		C.trunk,
		Enum.Material.Wood
	)
	U.part(
		model,
		"Crown",
		Vector3.new(2, 1.2, 2) * s,
		base * CFrame.new(0.6 * s, 11 * s, 0),
		C.leavesTop,
		Enum.Material.SmoothPlastic
	)
	for i = 0, 2 do
		local y = (10.9 + i * 0.18) * s
		U.part(
			model,
			"Leaf",
			Vector3.new(10, 0.45, 2.2) * s,
			base * CFrame.new(0.6 * s, y, 0) * CFrame.Angles(0, math.rad(i * 60), 0),
			C.leaves,
			Enum.Material.SmoothPlastic
		)
	end
	return model
end

local function rock(parent: any, ground: any, size: any, rotY: number, color: any?)
	return U.part(
		parent,
		"Rock",
		size,
		CFrame.new(ground + Vector3.new(0, size.Y / 2 - 0.4, 0)) * CFrame.Angles(0, math.rad(rotY), 0),
		color or C.rock,
		Enum.Material.Slate
	)
end

local function crate(parent: any, ground: any, rotY: number)
	return U.part(
		parent,
		"Crate",
		Vector3.new(2, 2, 2),
		CFrame.new(ground + Vector3.new(0, 1, 0)) * CFrame.Angles(0, math.rad(rotY), 0),
		C.wood,
		Enum.Material.WoodPlanks
	)
end

local function barrel(parent: any, ground: any)
	return U.cylinderY(parent, "Barrel", 1.8, 2.2, ground + Vector3.new(0, 1.1, 0), C.woodDark, Enum.Material.Wood)
end

--------------------------------------------------------------------------------
-- Shore, lake, hub island: voxel grid classification + rectangle merging
--------------------------------------------------------------------------------

type Rect = { cls: string, ix0: number, ix1: number, iz0: number, iz1: number }

local function classifyGrid(cfg: any): ({ { string } }, number)
	local cell, half = cfg.Cell, cfg.InnerHalf
	local n = math.floor(2 * half / cell)
	local lakeR = cfg.LakeRadius
	local beachR = cfg.LakeRadius + cfg.BeachWidth
	local hubR = cfg.HubRadius
	local hubGrassR = cfg.HubRadius - cfg.HubSandWidth

	local grid = {}
	for iz = 1, n do
		local row = {}
		for ix = 1, n do
			local x0, z0 = -half + (ix - 1) * cell, -half + (iz - 1) * cell
			local x1, z1 = x0 + cell, z0 + cell
			local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
			local dCenter = math.sqrt(cx * cx + cz * cz)
			local fx, fz = math.max(math.abs(x0), math.abs(x1)), math.max(math.abs(z0), math.abs(z1))
			local dFar = math.sqrt(fx * fx + fz * fz)
			local nx = if x0 <= 0 and x1 >= 0 then 0 else math.min(math.abs(x0), math.abs(x1))
			local nz = if z0 <= 0 and z1 >= 0 then 0 else math.min(math.abs(z0), math.abs(z1))
			local dNear = math.sqrt(nx * nx + nz * nz)

			local cls
			if dCenter <= hubR then
				cls = if dCenter <= hubGrassR then "hubGrass" else "hubSand"
			elseif dFar <= lakeR then
				cls = "water" -- whole cell inside the lake circle
			elseif dNear < beachR then
				cls = "sand"
			else
				cls = "grass"
			end
			row[ix] = cls
		end
		grid[iz] = row
	end
	return grid, n
end

-- Greedy merge: horizontal runs per row, then stack identical runs of consecutive rows.
local function mergeRects(grid: { { string } }, n: number): { Rect }
	local rects: { Rect } = {}
	local open: { [string]: Rect } = {}
	for iz = 1, n do
		local nextOpen: { [string]: Rect } = {}
		local ix = 1
		while ix <= n do
			local cls = grid[iz][ix]
			local start = ix
			while ix + 1 <= n and grid[iz][ix + 1] == cls do
				ix += 1
			end
			local key = `{cls}:{start}:{ix}`
			local rect = open[key]
			if rect then
				rect.iz1 = iz
			else
				rect = { cls = cls, ix0 = start, ix1 = ix, iz0 = iz, iz1 = iz }
				table.insert(rects, rect)
			end
			nextOpen[key] = rect
			ix += 1
		end
		open = nextOpen
	end
	return rects
end

local function rectBox(cfg: any, rect: Rect, yBottom: number, yTop: number): (any, any)
	local cell, half = cfg.Cell, cfg.InnerHalf
	local x0 = -half + (rect.ix0 - 1) * cell
	local x1 = -half + rect.ix1 * cell
	local z0 = -half + (rect.iz0 - 1) * cell
	local z1 = -half + rect.iz1 * cell
	local size = Vector3.new(x1 - x0, yTop - yBottom, z1 - z0)
	local cf = CFrame.new((x0 + x1) / 2, (yBottom + yTop) / 2, (z0 + z1) / 2)
	return size, cf
end

local function waterVolume(parent: any, size: any, cf: any)
	return U.part(parent, "WaterVolume", size, cf, C.water, Enum.Material.SmoothPlastic, {
		Transparency = 0.45,
		CanCollide = false,
		CanQuery = false,
		CastShadow = false,
	})
end

local function buildTerrain(map: any, hub: any, cfg: any)
	local ground = U.folder(map, "Ground")
	local water = U.folder(map, "Water")
	local lakeWater = U.folder(water, "Lake")
	local oceanWater = U.folder(water, "Ocean")
	local seabed = U.folder(map, "Seabed")
	local island = U.folder(hub, "Island")

	local grid, n = classifyGrid(cfg)
	local rects = mergeRects(grid, n)
	local counts = {}
	for _, rect in rects do
		counts[rect.cls] = (counts[rect.cls] or 0) + 1
		if rect.cls == "water" then
			local size, cf = rectBox(cfg, rect, cfg.LakeBottom, cfg.WaterTop)
			waterVolume(lakeWater, size, cf)
		elseif rect.cls == "grass" then
			local size, cf = rectBox(cfg, rect, cfg.LakeBottom, cfg.GroundTop)
			U.part(ground, "Grass", size, cf, C.grass, Enum.Material.Grass, SLAB)
		elseif rect.cls == "sand" then
			local size, cf = rectBox(cfg, rect, cfg.LakeBottom, cfg.GroundTop)
			U.part(ground, "Sand", size, cf, C.sand, Enum.Material.Sand, SLAB)
		elseif rect.cls == "hubSand" then
			local size, cf = rectBox(cfg, rect, cfg.LakeBottom, cfg.GroundTop)
			U.part(island, "Sand", size, cf, C.hubSand, Enum.Material.Sand, SLAB)
		elseif rect.cls == "hubGrass" then
			local size, cf = rectBox(cfg, rect, cfg.LakeBottom, cfg.HubTop)
			U.part(island, "Grass", size, cf, C.grass, Enum.Material.Grass, SLAB)
		end
	end

	-- Outer grass frame around the voxel square, up to LandHalf.
	local h, L = cfg.InnerHalf, cfg.LandHalf
	local height = cfg.GroundTop - cfg.LakeBottom
	local yc = (cfg.GroundTop + cfg.LakeBottom) / 2
	local frame = {
		{ Vector3.new(2 * L, height, L - h), Vector3.new(0, yc, (L + h) / 2) },
		{ Vector3.new(2 * L, height, L - h), Vector3.new(0, yc, -(L + h) / 2) },
		{ Vector3.new(L - h, height, 2 * h), Vector3.new((L + h) / 2, yc, 0) },
		{ Vector3.new(L - h, height, 2 * h), Vector3.new(-(L + h) / 2, yc, 0) },
	}
	for _, f in frame do
		U.part(ground, "Grass", f[1], CFrame.new(f[2]), C.grass, Enum.Material.Grass, SLAB)
	end

	-- Lake bed under every lake cell.
	local bedHalf = cfg.LakeRadius + cfg.Cell
	U.part(
		seabed,
		"LakeBed",
		Vector3.new(2 * bedHalf, 2, 2 * bedHalf),
		CFrame.new(0, cfg.LakeBottom - 1, 0),
		C.seabed,
		Enum.Material.Sand,
		SLAB
	)

	-- Ocean around the land (water volumes + floor).
	local O = cfg.OceanHalf
	local wh = cfg.WaterTop - cfg.LakeBottom
	local wy = (cfg.WaterTop + cfg.LakeBottom) / 2
	local ocean = {
		{ Vector3.new(2 * O, 0, O - L), Vector3.new(0, 0, (O + L) / 2) },
		{ Vector3.new(2 * O, 0, O - L), Vector3.new(0, 0, -(O + L) / 2) },
		{ Vector3.new(O - L, 0, 2 * L), Vector3.new((O + L) / 2, 0, 0) },
		{ Vector3.new(O - L, 0, 2 * L), Vector3.new(-(O + L) / 2, 0, 0) },
	}
	for _, o in ocean do
		local s, p = o[1], o[2]
		waterVolume(oceanWater, Vector3.new(s.X, wh, s.Z), CFrame.new(p.X, wy, p.Z))
		U.part(
			seabed,
			"OceanFloor",
			Vector3.new(s.X, 2, s.Z),
			CFrame.new(p.X, cfg.LakeBottom - 1, p.Z),
			C.seabed,
			Enum.Material.Sand,
			SLAB
		)
	end

	return counts
end

--------------------------------------------------------------------------------
-- Hub: paths, shop, fountain, lamps, palms, spawn
--------------------------------------------------------------------------------

local function buildShop(hub: any, cfg: any)
	local shop = U.model(hub, "Shop")
	local floorTop = cfg.HubTop + 0.6

	U.part(
		shop,
		"Floor",
		Vector3.new(20, 0.6, 12),
		CFrame.new(0, floorTop - 0.3, -15),
		C.wood,
		Enum.Material.WoodPlanks
	)
	local backWall = U.part(
		shop,
		"BackWall",
		Vector3.new(20, 9, 1),
		CFrame.new(0, floorTop + 4.5, -20.5),
		C.wood,
		Enum.Material.WoodPlanks
	)
	-- Painted sign on the back, seen by players arriving from the north bridge.
	local backGui = U.new("SurfaceGui", {
		Name = "BackSignGui",
		Face = Enum.NormalId.Front, -- -Z, towards the north bridge
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 30,
		LightInfluence = 0,
	}, backWall)
	U.new("TextLabel", {
		Name = "Title",
		AnchorPoint = U.Vector2.new(0.5, 0.5),
		Position = U.UDim2.fromScale(0.5, 0.45),
		Size = U.UDim2.fromScale(0.8, 0.3),
		BackgroundTransparency = 1,
		Text = "⬅ МАГАЗИН ➡",
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = rgb(250, 236, 200),
		TextStrokeTransparency = 0.5,
	}, backGui)
	U.part(
		shop,
		"WallLeft",
		Vector3.new(1, 9, 11),
		CFrame.new(-9.5, floorTop + 4.5, -15.5),
		C.wood,
		Enum.Material.WoodPlanks
	)
	U.part(
		shop,
		"WallRight",
		Vector3.new(1, 9, 11),
		CFrame.new(9.5, floorTop + 4.5, -15.5),
		C.wood,
		Enum.Material.WoodPlanks
	)
	U.part(shop, "Roof", Vector3.new(21, 1, 12), CFrame.new(0, floorTop + 9.5, -15.5), C.woodDark, Enum.Material.Wood)

	local counter = U.part(
		shop,
		"Counter",
		Vector3.new(16, 3.2, 1.6),
		CFrame.new(0, floorTop + 1.6, -10.2),
		C.woodDark,
		Enum.Material.WoodPlanks
	)
	U.part(
		shop,
		"CounterTop",
		Vector3.new(16.4, 0.3, 2),
		CFrame.new(0, floorTop + 3.35, -10.2),
		C.shopBlue,
		Enum.Material.SmoothPlastic
	)
	-- Stage 5: the shop / sell ProximityPrompts are created on this attachment.
	-- Attachments must be placed via CFrame: Lune does not save Attachment.Position.
	U.new("Attachment", { Name = "ShopPromptAttachment", CFrame = CFrame.new(0, 0.6, 1.4) }, counter)

	-- Striped awning, front edge lower.
	for i = 0, 5 do
		local x = -10 + 20 / 12 + i * 20 / 6
		local color = if i % 2 == 0 then C.shopBlue else C.white
		U.part(
			shop,
			"Awning",
			Vector3.new(20 / 6, 0.3, 5),
			CFrame.new(x, floorTop + 7.75, -7.62) * CFrame.Angles(math.rad(18), 0, 0),
			color,
			Enum.Material.SmoothPlastic,
			{ CastShadow = true }
		)
	end

	-- Shopkeeper behind the counter.
	local keeper = U.model(shop, "Shopkeeper")
	U.part(keeper, "Legs", Vector3.new(2, 2, 1), CFrame.new(0, floorTop + 1, -14), rgb(45, 60, 110))
	U.part(keeper, "Torso", Vector3.new(2, 2, 1), CFrame.new(0, floorTop + 3, -14), rgb(235, 130, 40))
	U.part(keeper, "Head", Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, floorTop + 4.7, -14), rgb(255, 205, 150))
	U.part(keeper, "Hat", Vector3.new(1.8, 0.5, 1.8), CFrame.new(0, floorTop + 5.65, -14), rgb(120, 80, 45))
	U.part(
		keeper,
		"EyeLeft",
		Vector3.new(0.22, 0.28, 0.1),
		CFrame.new(-0.3, floorTop + 4.85, -13.28),
		rgb(20, 20, 20),
		nil,
		{ CastShadow = false }
	)
	U.part(
		keeper,
		"EyeRight",
		Vector3.new(0.22, 0.28, 0.1),
		CFrame.new(0.3, floorTop + 4.85, -13.28),
		rgb(20, 20, 20),
		nil,
		{ CastShadow = false }
	)

	-- Sign on the roof with a big fish on top.
	local roofTop = floorTop + 10
	local sign = U.part(
		shop,
		"Sign",
		Vector3.new(14, 3.6, 0.6),
		CFrame.new(0, roofTop + 1.8, -11),
		rgb(250, 236, 200),
		Enum.Material.SmoothPlastic
	)
	local gui = U.new("SurfaceGui", {
		Name = "SignGui",
		Face = Enum.NormalId.Back, -- +Z, towards the plaza
		SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud,
		PixelsPerStud = 40,
		LightInfluence = 0,
	}, sign)
	U.new("TextLabel", {
		Name = "Title",
		Size = U.UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "МАГАЗИН",
		TextScaled = true,
		FontFace = U.FONT,
		TextColor3 = C.shopBlue,
	}, gui)

	local fy = roofTop + 3.6 + 1.5
	U.part(shop, "FishBody", Vector3.new(7, 3, 0.8), CFrame.new(0, fy, -11), rgb(60, 140, 230))
	U.part(
		shop,
		"FishTail",
		Vector3.new(2.6, 2.6, 0.6), -- thinner than the body: no coplanar faces (z-fighting)
		CFrame.new(-4.4, fy, -11) * CFrame.Angles(0, 0, math.rad(45)),
		rgb(45, 115, 205)
	)
	U.part(shop, "FishFin", Vector3.new(2.2, 0.8, 0.6), CFrame.new(0.2, fy + 1.8, -11), rgb(45, 115, 205))
	U.part(
		shop,
		"FishEye",
		Vector3.new(0.9, 0.9, 0.9),
		CFrame.new(2.3, fy + 0.5, -10.75),
		C.white,
		nil,
		{ CastShadow = false }
	)
	U.part(
		shop,
		"FishPupil",
		Vector3.new(0.45, 0.45, 0.3),
		CFrame.new(2.45, fy + 0.5, -10.25),
		rgb(20, 20, 20),
		nil,
		{ CastShadow = false }
	)

	crate(shop, Vector3.new(11, floorTop - 0.6, -12.5), 0)
	barrel(shop, Vector3.new(11, floorTop - 0.6, -16))
end

local function buildHub(hub: any, cfg: any)
	local top = cfg.HubTop
	local pathTop = top + 0.15
	local paths = U.folder(hub, "Paths")
	local function path(name: string, x0: number, x1: number, z0: number, z1: number)
		-- 0.8 thick so it also covers the lower sand ring at the island edge.
		U.part(
			paths,
			name,
			Vector3.new(x1 - x0, 0.8, z1 - z0),
			CFrame.new((x0 + x1) / 2, pathTop - 0.4, (z0 + z1) / 2),
			C.cobble,
			Enum.Material.Cobblestone,
			{ CastShadow = false, Locked = true }
		)
	end
	-- Non-overlapping pieces (no z-fighting): plaza in front of the shop + 4 arms to the bridges.
	path("Plaza", -10, 10, -9, 14)
	path("PathEast", 10, 32, -3, 3)
	path("PathWest", -32, -10, -3, 3)
	path("PathSouth", -3, 3, 14, 32)
	-- From the north bridge the path goes AROUND the shop (its back wall is blank) to the side arms.
	path("PathNorth", -3, 3, -32, -26)
	path("PathBehindShop", -16, 16, -26, -22)
	path("PathShopWest", -16, -12, -22, -3)
	path("PathShopEast", 12, 16, -22, -3)

	buildShop(hub, cfg)

	-- Fountain with a golden fish.
	local fountain = U.model(hub, "Fountain")
	local fz = 2
	U.cylinderY(fountain, "Basin", 10, 1.2, Vector3.new(0, pathTop + 0.6, fz), C.stone, Enum.Material.Slate)
	U.cylinderY(
		fountain,
		"Water",
		8.6,
		0.2,
		Vector3.new(0, pathTop + 1.25, fz),
		rgb(70, 180, 235),
		Enum.Material.SmoothPlastic,
		{ Transparency = 0.2, CanCollide = false, CastShadow = false }
	)
	U.cylinderY(fountain, "Pedestal", 1.6, 3, Vector3.new(0, pathTop + 2.7, fz), C.stone, Enum.Material.Slate)
	U.part(
		fountain,
		"GoldenFish",
		Vector3.new(1.3, 2.6, 0.9),
		CFrame.new(0, pathTop + 5.5, fz) * CFrame.Angles(0, 0, math.rad(-12)),
		C.gold,
		Enum.Material.Neon
	)
	U.part(
		fountain,
		"GoldenTail",
		Vector3.new(1.5, 1.5, 0.5),
		CFrame.new(0.35, pathTop + 7.1, fz) * CFrame.Angles(0, 0, math.rad(33)),
		C.gold,
		Enum.Material.Neon
	)

	local lamps = U.model(hub, "Lamps")
	for _, p in { { -9, -7.5 }, { 9, -7.5 }, { -9, 13 }, { 9, 13 } } do
		lamp(lamps, Vector3.new(p[1], pathTop, p[2]), 5)
	end

	local palms = U.model(hub, "Palms")
	palm(palms, Vector3.new(-20, top, -12), 10)
	palm(palms, Vector3.new(20, top, -12), 70)
	palm(palms, Vector3.new(-15, top, 17), 130) -- (±15, 17) is still a grass cell (top = HubTop)
	palm(palms, Vector3.new(15, top, 17), 200)

	-- Fallback spawn: players without a base appear here. Bases use their own SpawnPad.
	U.new("SpawnLocation", {
		Name = "HubSpawn",
		Size = Vector3.new(6, 0.4, 6),
		CFrame = CFrame.new(0, pathTop + 0.2, 11),
		Anchored = true,
		Neutral = true,
		Duration = 0, -- no ForceField
		Enabled = true,
		AllowTeamChangeOnTouch = false,
		Color = rgb(250, 245, 230),
		Material = Enum.Material.SmoothPlastic,
		TopSurface = Enum.SurfaceType.Smooth,
		BottomSurface = Enum.SurfaceType.Smooth,
		CastShadow = false,
	}, hub)
	U.partCount += 1
end

--------------------------------------------------------------------------------
-- Bridges, decor, boundaries, base slots
--------------------------------------------------------------------------------

local function buildBridges(map: any, cfg: any)
	local bridges = U.model(map, "Bridges")
	local w = cfg.BridgeWidth
	-- Starts exactly at the island edge (no overlap with the hub paths), ends on the beach.
	local z0, z1 = cfg.HubRadius, cfg.LakeRadius + 2
	local len = z1 - z0
	local zc = (z0 + z1) / 2
	local deckTop = cfg.GroundTop + 0.6
	local railTop = deckTop + 1.4
	for i, angle in cfg.BridgeAngles do
		local bridge = U.model(bridges, `Bridge_{i}`)
		local rot = CFrame.Angles(0, math.rad(angle), 0)
		U.part(
			bridge,
			"Deck",
			Vector3.new(w, 1, len),
			rot * CFrame.new(0, deckTop - 0.5, zc),
			C.wood,
			Enum.Material.WoodPlanks
		)
		for _, side in { -1, 1 } do
			local x = side * (w / 2 - 0.25)
			U.part(
				bridge,
				"Rail",
				Vector3.new(0.5, 0.4, len),
				rot * CFrame.new(x, railTop - 0.2, zc),
				C.rail,
				Enum.Material.Wood,
				{ CastShadow = false }
			)
			for _, z in { z0 + 10, zc, z1 - 10 } do
				local postH = railTop - 0.4 - cfg.LakeBottom -- ends under the rail: no coplanar tops
				U.part(
					bridge,
					"Post",
					Vector3.new(0.8, postH, 0.8),
					rot * CFrame.new(x, cfg.LakeBottom + postH / 2, z),
					C.woodDark,
					Enum.Material.Wood,
					{ CastShadow = false }
				)
			end
		end
		-- Shore-end lamps and a couple of props.
		for _, side in { -1, 1 } do
			local p = rot * CFrame.new(side * (w / 2 + 1.6), cfg.GroundTop, z1 + 1)
			lamp(bridge, p.Position, 5)
		end
		local cratePos = (rot * CFrame.new(w / 2 + 4, cfg.GroundTop, z1 + 4)).Position
		crate(bridge, cratePos, angle + 20)
		local barrelPos = (rot * CFrame.new(-(w / 2 + 4), cfg.GroundTop, z1 + 5)).Position
		barrel(bridge, barrelPos)
	end
end

local function buildDecor(map: any, cfg: any)
	local decor = U.model(map, "Decor")
	local g = cfg.GroundTop
	local diagonals = { 45, 135, 225, 315 }

	-- Palms between neighbouring bases (on the diagonals; bridges sit on the axes).
	local palms = U.model(decor, "Palms")
	for i, d in diagonals do
		palm(palms, U.polar(d - 6, 112, g), i * 37)
		palm(palms, U.polar(d + 6, 119, g), i * 53 + 20, 1.1)
		palm(palms, U.polar(d, 152, g), i * 71 + 40, 1.25)
	end

	-- Rock clusters on the outer ring.
	local rocks = U.model(decor, "Rocks")
	for k = 0, 7 do
		local a = k * 45 + 8
		if math.abs(a - 135 - 8) > 1 then
			rock(rocks, U.polar(a, 158, g), Vector3.new(7, 5, 6), k * 23)
			rock(rocks, U.polar(a + 3, 165, g), Vector3.new(4, 3, 4), k * 41 + 10, C.stone)
		end
	end

	-- Stepped cliffs in the 4 corners of the land.
	local cliffs = U.model(decor, "Cliffs")
	local cliffTops = {}
	for i, d in diagonals do
		local p = U.polar(d, 212, g)
		local cliff = U.model(cliffs, `Cliff_{i}`)
		local t1, t2 = g + 8, g + 15
		U.part(
			cliff,
			"Rock1",
			Vector3.new(44, t1 - g + 1, 44),
			CFrame.new(p.X, (g - 1 + t1) / 2, p.Z),
			C.cliff,
			Enum.Material.Slate,
			LOCKED
		)
		U.part(
			cliff,
			"Grass1",
			Vector3.new(44.2, 0.6, 44.2),
			CFrame.new(p.X, t1 + 0.3, p.Z),
			C.grass,
			Enum.Material.Grass,
			LOCKED
		)
		local q = U.polar(d, 222, g)
		U.part(
			cliff,
			"Rock2",
			Vector3.new(24, t2 - t1, 24),
			CFrame.new(q.X, (t1 + t2) / 2 + 0.3, q.Z),
			C.cliff,
			Enum.Material.Slate,
			LOCKED
		)
		U.part(
			cliff,
			"Grass2",
			Vector3.new(24.2, 0.6, 24.2),
			CFrame.new(q.X, t2 + 0.6, q.Z),
			C.grass,
			Enum.Material.Grass,
			LOCKED
		)
		cliffTops[d] = Vector3.new(q.X, t2 + 0.9, q.Z)
	end

	-- Lighthouse on the 135° cliff.
	local lh = U.model(decor, "Lighthouse")
	local b = cliffTops[135]
	local y = b.Y
	local function seg(name: string, d: number, h: number, color: any, material: any?)
		U.cylinderY(lh, name, d, h, Vector3.new(b.X, y + h / 2, b.Z), color, material or Enum.Material.SmoothPlastic)
		y += h
	end
	seg("Base", 9, 2, C.stone, Enum.Material.Slate)
	seg("Tower1", 7, 6, C.red)
	seg("Tower2", 6.4, 6, C.white)
	seg("Tower3", 5.8, 6, C.red)
	seg("Gallery", 8, 0.6, C.woodDark, Enum.Material.Wood)
	seg("Light", 4.4, 3, rgb(255, 230, 120), Enum.Material.Neon)
	seg("Roof", 5.6, 1.6, C.red)

	-- Beach corner: umbrella + loungers (45° and 315°).
	local beach = U.model(decor, "Beach")
	for _, d in { 45, 315 } do
		local center = U.polarCFrame(d, 110, g)
		U.cylinderY(beach, "UmbrellaPole", 0.3, 6.5, (center * CFrame.new(0, 3.25, 0)).Position, C.white)
		U.cylinderY(beach, "Umbrella", 7, 0.5, (center * CFrame.new(0, 6.6, 0)).Position, C.red)
		U.cylinderY(beach, "UmbrellaTop", 3, 0.5, (center * CFrame.new(0, 7.0, 0)).Position, C.white)
		U.part(beach, "Lounger", Vector3.new(2, 0.6, 5), center * CFrame.new(-2, 0.3, 1), C.white)
		U.part(beach, "Lounger", Vector3.new(2, 0.6, 5), center * CFrame.new(2, 0.3, 1), C.shopBlue)
	end

	-- Campfire with log seats (225°).
	local camp = U.model(decor, "Campfire")
	local cc = U.polarCFrame(225, 134, g)
	U.cylinderY(camp, "Stones", 4.2, 0.6, (cc * CFrame.new(0, 0.3, 0)).Position, C.rock, Enum.Material.Slate)
	U.part(
		camp,
		"Log",
		Vector3.new(3, 0.6, 0.6),
		cc * CFrame.new(0, 0.9, 0) * CFrame.Angles(0, math.rad(45), 0),
		C.woodDark,
		Enum.Material.Wood
	)
	U.part(
		camp,
		"Log",
		Vector3.new(3, 0.6, 0.6),
		cc * CFrame.new(0, 0.9, 0) * CFrame.Angles(0, math.rad(-45), 0),
		C.woodDark,
		Enum.Material.Wood
	)
	U.part(
		camp,
		"Fire",
		Vector3.new(1.2, 1.8, 1.2),
		cc * CFrame.new(0, 1.8, 0) * CFrame.Angles(0, math.rad(45), 0),
		rgb(255, 130, 30),
		Enum.Material.Neon,
		{ CanCollide = false, CastShadow = false }
	)
	U.part(camp, "Seat", Vector3.new(4, 1, 1.2), cc * CFrame.new(0, 0.5, 4), C.trunk, Enum.Material.Wood)
	U.part(camp, "Seat", Vector3.new(1.2, 1, 4), cc * CFrame.new(4, 0.5, 0), C.trunk, Enum.Material.Wood)
end

local function buildBoundaries(map: any, cfg: any)
	local walls = U.folder(map, "Boundaries")
	local B = cfg.BoundaryHalf
	local h = 220
	local y = cfg.LakeBottom + h / 2
	local function wall(size: any, pos: any)
		U.part(walls, "Wall", size, CFrame.new(pos), C.white, nil, {
			Transparency = 1,
			CanQuery = false,
			CastShadow = false,
			Locked = true,
		})
	end
	wall(Vector3.new(2 * B + 8, h, 4), Vector3.new(0, y, B + 2))
	wall(Vector3.new(2 * B + 8, h, 4), Vector3.new(0, y, -B - 2))
	wall(Vector3.new(4, h, 2 * B + 8), Vector3.new(B + 2, y, 0))
	wall(Vector3.new(4, h, 2 * B + 8), Vector3.new(-B - 2, y, 0))
end

local function buildSlots(map: any, cfg: any): { any }
	local slots = U.folder(map, "BaseSlots")
	local list = {}
	for i = 1, cfg.BaseCount do
		local angle = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		local slot =
			U.marker(slots, `Slot_{i}`, Vector3.new(4, 0.2, 4), U.polarCFrame(angle, cfg.BaseRadius, cfg.GroundTop), {
				Attributes = { Index = i, Angle = angle },
			})
		table.insert(list, slot)
	end
	return list
end

--------------------------------------------------------------------------------

return function(game: any, cfg: any)
	local workspace = game:GetService("Workspace")
	local map = U.new("Model", { Name = "Map" }, workspace)
	local hub = U.model(map, "Hub")

	local counts = buildTerrain(map, hub, cfg)
	buildHub(hub, cfg)
	buildBridges(map, cfg)
	buildDecor(map, cfg)
	buildBoundaries(map, cfg)
	local slots = buildSlots(map, cfg)

	return { map = map, cellCounts = counts, slots = slots }
end
