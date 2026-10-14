--[[
	HubDetails — the hub plaza's small things (v3 micro-detail, Workspace.Map.Hub.Details), built
	by Map.luau after Nature with the late kits, keeping off every part already there
	(Kit.obstacles): café tables under parasols on the plaza beside the Shop and the Fish Market,
	flower barrels at the avenue mouths and a wooden arrow signpost at every avenue's plaza end
	pointing to the shops and the fair (kids find their way). The avenues and the rays to the shop
	porches stay clear (nothing within 7 studs of an avenue's or a ray's axis), nothing collides or
	takes raycasts, nothing casts a shadow. Calm colours from Palette; jewel tones only on the
	parasols and blooms. Returns its part count.
]]

local U = require("./Util")
local Kit = require("./MapKit")
local Promenade = require("./Promenade")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Enum = U.Enum
local C = Kit.C

local rad = math.rad

local HubDetails = {}

local DECOR = Kit.DECOR
local CYL = { Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false, CanQuery = false }

-- What stands at the end of each plaza diagonal (the signposts point there).
local PLACES =
	{ [45] = "УДОЧКИ", [135] = "МАСТЕРСКАЯ", [225] = "АТТРАКЦИОНЫ", [315] = "РЫНОК" }

-- A café table under a parasol with two cube stools (7 parts), on cf (local -Z to the tower).
local function cafeTable(parent: any, cf: any, k: number)
	local b = Kit.builder(parent, "CafeTable", cf)
	b:box("TablePost", -0.25, 0, -0.25, 0.25, 2.3, 0.25, C.Iron, DECOR)
	b:block(
		"TableTop",
		Vector3.new(0.3, 3.0, 3.0),
		CFrame.new(0, 2.45, 0) * CFrame.Angles(0, 0, rad(90)),
		C.WoodLight,
		CYL
	)
	for i, x in { -2.3, 2.3 } do
		b:box("Stool", x - 0.65, 0, -0.65 + (i - 1.5) * 0.4, x + 0.65, 1.3, 0.65 + (i - 1.5) * 0.4, C.Wood, DECOR)
	end
	b:pole("ParasolPole", 0.25, 0, 0, 2.6, 6.8, C.White, DECOR)
	local canopy = ({ C.Flowers[1], C.Flowers[7], C.BoatPaint[2], C.Flowers[6] })[k % 4 + 1]
	b:box("Parasol", -2.2, 6.2, -2.2, 2.2, 6.7, 2.2, canopy, DECOR)
	b:box("ParasolTop", -1.0, 6.65, -1.0, 1.0, 7.15, 1.0, C.White, DECOR)
	return b:finish()
end

-- A wooden flower barrel (3 parts).
local function flowerBarrel(parent: any, cf: any, k: number)
	local b = Kit.builder(parent, "FlowerBarrel", cf)
	b:pole("Barrel", 2.2, 0, 0, 0, 1.8, C.Wood, DECOR)
	b:box("BarrelGreens", -1.0, 1.7, -1.0, 1.0, 2.5, 1.0, C.Leaf1, DECOR)
	b:box("BarrelBlooms", -0.6, 2.45, -0.6, 0.6, 2.95, 0.6, C.Flowers[({ 1, 3, 2, 5 })[k % 4 + 1]], DECOR)
	return b:finish()
end

function HubDetails.build(map: any, cfg: any, obstacles: any): number
	local hub = map:FindFirstChild("Hub")
	if not hub then
		return 0
	end
	local details = U.model(hub, "Details")
	local before = U.partCount
	local blocked, topAt = obstacles.blocked, obstacles.topAt
	local G = cfg.GroundTop

	-- (the walking surface under (a, r): the plaza paving; nil when something stands there)
	local function spot(a: number, r: number, w: number, d: number, h: number): any
		local p = U.polar(a, r, 0)
		local top = topAt(p.X, p.Z, G + 0.8)
		if not top or top < G - 0.5 then
			return nil
		end
		local cf = CFrame.new(p.X, top, p.Z) * CFrame.Angles(0, rad(a), 0)
		if blocked(cf, w, d, top + 0.05, top + h) then
			return nil
		end
		return cf
	end

	-- café tables beside the Shop (45°) and the Fish Market (315°), off their rays
	local k = 0
	for _, shop in { 45, 315 } do
		for _, off in { 14, -14 } do
			for _, try in { { 0, 58 }, { 2, 58 }, { -2, 58 }, { 0, 56 }, { 0, 60 } } do
				local cf = spot(shop + off + try[1], try[2], 6.2, 4.8, 7.5)
				if cf then
					k += 1
					cafeTable(details, cf, k)
					break
				end
			end
		end
	end
	-- flower barrels either side of every avenue's mouth
	local n = 0
	for _, a in cfg.BridgeAngles do
		for _, off in { 11, -11 } do
			for _, dr in { 0, 2, -2, 4 } do
				local cf = spot(a + off, 60 + dr, 2.4, 2.4, 3.2)
				if cf then
					n += 1
					flowerBarrel(details, cf, n)
					break
				end
			end
		end
	end
	-- a signpost at every avenue's plaza end: the shops (or the fair) on the diagonals either side
	for _, a in cfg.BridgeAngles do
		local right, left = PLACES[(a + 45) % 360], PLACES[(a + 315) % 360]
		for _, try in { { 6.5, 57 }, { 7.5, 58 }, { -6.5, 57 }, { -7.5, 58 } } do
			local cf = spot(a + try[1], try[2], 1.2, 1.2, 7.5)
			if cf and right and left then
				-- (local +X points towards increasing angles)
				Promenade.signpost(details, cf, { { dir = 1, text = right }, { dir = -1, text = left } })
				break
			end
		end
	end

	for _, d in details:GetDescendants() do
		if d:IsA("BasePart") then
			d.Locked = true
			d.CanTouch = false
		end
	end
	return U.partCount - before
end

return HubDetails
