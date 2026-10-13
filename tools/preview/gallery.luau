--[[
	gallery.luau (Lune 0.11) — builds a showcase place with every prop of
	tools/builder/Props.luau, for visual review with the preview renderer.

	Usage (from the repo root):
		lune run tools/preview/gallery.luau <out.rbxl> [base.rbxl]
	then
		lune run tools/preview/export_parts.luau <out.rbxl> parts.json --no-bases
		python3 tools/preview/render.py parts.json --out-dir DIR --views top,iso,zoom --zoom X,Z,R[,AZ]...

	Layout (top view, +X right, +Z down): rows of trees, plants, rocks and furniture on a
	checkered bright-green ground (top at y = 0); a water channel (Workspace.Map.Water stand-in,
	surface y = 0) with boats, docks, buoys, a shipwreck, a rock arch, two bridges and a
	waterfall off a cliff; a row of landmarks; a balloon and clouds in the sky. Props face +Z
	(towards the default iso camera). The script prints a zoom target for every section and
	fails if a public Props constructor is not shown.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local U = require("../builder/Util")
local Props = require("../builder/Props")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local C = Props.Colors

local out = process.args[1] or "gallery.rbxl"
local basePath = process.args[2] or "tools/base/Place1.base.rbxl"

local game = roblox.deserializePlace(fs.readFile(basePath))
local workspace = game:GetService("Workspace")
for _, child in workspace:GetChildren() do
	if not (child:IsA("Terrain") or child:IsA("Camera")) then
		child:Destroy()
	end
end

local map = U.model(workspace, "Map")
local groundModel = U.model(map, "Ground")
local waterFolder = U.folder(map, "Water")
local propsModel = U.model(map, "Props")

local used: { [string]: boolean } = {}
local sections: { { any } } = {}

-- Props face +Z (towards the default iso camera at azimuth 45).
local FACE = CFrame.Angles(0, math.pi, 0)

local function place(name: string, x: number, z: number, opts: any?, y: number?): any
	used[name] = true
	local fn = (Props :: any)[name]
	assert(type(fn) == "function", `Props.{name} missing`)
	return fn(propsModel, CFrame.new(x, y or 0, z) * FACE, opts)
end

-- Places a row of { name, opts?, width? } entries left to right starting at x0.
local function row(label: string, x0: number, z: number, spacing: number, items: { any })
	local x = x0
	for _, item in items do
		local w = item[3] or spacing
		place(item[1], x + w / 2, z, item[2], item[4])
		x += w
	end
	table.insert(sections, { label, (x0 + x) / 2, z, (x - x0) / 2 + 6 })
end

--------------------------------------------------------------------------------------------
-- Ground: 32-stud checker tiles, top at y = 0, leaving the water channel open
--------------------------------------------------------------------------------------------

local X0, X1 = -32, 448
local Z0, Z1 = -32, 448
local WATER_Z0, WATER_Z1 = 192, 320
local TILE = 32
for tz = Z0, Z1 - TILE, TILE do
	for tx = X0, X1 - TILE, TILE do
		if tz + TILE <= WATER_Z0 or tz >= WATER_Z1 then
			local even = ((tx - X0) / TILE + (tz - Z0) / TILE) % 2 == 0
			U.part(
				groundModel,
				"Tile",
				Vector3.new(TILE, 4, TILE),
				CFrame.new(tx + TILE / 2, -2, tz + TILE / 2),
				if even then C.GrassTop else C.GrassTop2
			)
		end
	end
end
-- channel: sand bed and the water stand-in (exported as water by export_parts)
U.part(
	groundModel,
	"Seabed",
	Vector3.new(X1 - X0, 2, WATER_Z1 - WATER_Z0),
	CFrame.new((X0 + X1) / 2, -7, (WATER_Z0 + WATER_Z1) / 2),
	C.SandWet
)
U.part(
	waterFolder,
	"Water",
	Vector3.new(X1 - X0, 6, WATER_Z1 - WATER_Z0),
	CFrame.new((X0 + X1) / 2, -3, (WATER_Z0 + WATER_Z1) / 2),
	C.Water,
	nil,
	{ Transparency = 0.5, CanCollide = false }
)

--------------------------------------------------------------------------------------------
-- Rows of props
--------------------------------------------------------------------------------------------

row("trees", 0, 8, 19, {
	{ "oakTree", { seed = 1 } },
	{ "oakTree", { seed = 2 } },
	{ "oakTree", { seed = 3, fruit = true } },
	{ "oakTree", { seed = 4 } },
	{ "cherryTree", { seed = 1 } },
	{ "cherryTree", { seed = 2 } },
	{ "autumnTree", { seed = 1 } },
	{ "autumnTree", { seed = 2 } },
	{ "birchTree", { seed = 1 } },
	{ "birchTree", { seed = 2 } },
	{ "roundTree", { seed = 5, palette = "green" } },
	{ "roundTree", { seed = 6, palette = "lime" } },
	{ "roundTree", { seed = 7, palette = "blossom" } },
	{ "roundTree", { seed = 8, palette = "autumn" } },
	{ "roundTree", { seed = 9, palette = "mixed" } },
})

row("conifers+palms", 0, 40, 19, {
	{ "pineTree", { seed = 1, variant = 1 } },
	{ "pineTree", { seed = 2, variant = 2 } },
	{ "pineTree", { seed = 3, variant = 3 } },
	{ "pineTree", { seed = 4, variant = 1, snow = true } },
	{ "pineTree", { seed = 5, variant = 2, snow = true } },
	{ "pineTree", { seed = 6 } },
	{ "palmTree", { seed = 1, variant = 1 } },
	{ "palmTree", { seed = 2, variant = 2 } },
	{ "palmTree", { seed = 3, variant = 1 } },
	{ "palmTree", { seed = 4, variant = 2, lean = 1 } },
	-- lite versions for background forests
	{ "oakTree", { seed = 11, lite = true } },
	{ "pineTree", { seed = 12, variant = 2, lite = true } },
	{ "palmTree", { seed = 13, lite = true } },
	{ "birchTree", { seed = 14, lite = true } },
})

row("plants", 0, 70, 8, {
	{ "bush", { seed = 1 } },
	{ "bush", { seed = 2, berries = C.Red } },
	{ "bush", { seed = 3, berries = false } },
	{ "bush", { seed = 4, berries = C.Yellow } },
	{ "berryBush", { seed = 1 } },
	{ "flowerClump", { seed = 1 } },
	{ "flowerClump", { seed = 2 } },
	-- planted beds of small flowers (a petal plate with an eye, 1.1-1.3 apart, three heights)
	{ "flowerBed", { seed = 1 } },
	{ "flowerBed", { seed = 2, width = 8, depth = 2, kerb = false } },
	-- a wildflower drift (Nature's decor along the paths: no kerb, leaf blades)
	{ "flowerBed", { seed = 3, width = 6.4, depth = 4.2, kerb = false, leaves = C.Leaf2, blades = 4 } },
	-- capped beds: the flowers gather in clumps (a base gate bed, a long parapet box)
	{ "flowerBed", { seed = 4, width = 6, depth = 3.6, spacing = 1.6, max = 8 } },
	{ "flowerBed", { seed = 5, width = 14, depth = 1.6, kerb = C.Wood, stems = false, spacing = 2.6, max = 10 }, 16 },
	{ "hayBale", {} },
	{ "flowerPatch", { seed = 1 } },
	{ "flowerPatch", { seed = 2 } },
	{ "flowerPatch", { seed = 3, colors = { C.Pink, C.White } } },
	{ "flowerPatch", { seed = 4, colors = { C.Blue, C.Yellow } } },
	{ "mushroom", { seed = 1 } },
	{ "mushroom", { seed = 2, color = C.Red } },
	{ "mushroom", { seed = 3 } },
	{ "reeds", { seed = 1 } },
	{ "reeds", { seed = 2 } },
	{ "stump", { seed = 1, axe = true } },
	{ "stump", { seed = 2, axe = false } },
	{ "log", { seed = 1 }, 10 },
	{ "log", { seed = 2 }, 10 },
})

row("rocks", 0, 96, 9, {
	{ "rock", { seed = 1, count = 1 } },
	{ "rock", { seed = 2, count = 2 } },
	{ "rock", { seed = 3, count = 3 } },
	{ "rock", { seed = 4, count = 4 } },
	{ "rock", { seed = 5, snow = true } },
	{ "rock", { seed = 6, moss = true } },
	{ "rockPair", { seed = 1 } },
	{ "boulder", { seed = 1 }, 15 },
	{ "boulder", { seed = 2, moss = true }, 15 },
	{ "crystalCluster", { seed = 1, color = "cyan", light = true }, 10 },
	{ "crystalCluster", { seed = 2, color = "purple" }, 10 },
	{ "crystalCluster", { seed = 3, color = "pink" }, 10 },
	{ "giantMushroom", { seed = 1 }, 20 },
	{ "giantMushroom", { seed = 2, glow = true }, 20 },
})

row("furniture", 0, 128, 9, {
	{ "lampPost", { light = true } },
	{ "lampPost", { color = C.Red } },
	{ "doubleLamp", { light = true }, 11 },
	{ "torch", { light = true }, 6 },
	{ "bench", {} },
	{ "picnicTable", {}, 11 },
	{ "crate", {}, 6 },
	{ "crateStack", { seed = 1 } },
	{ "barrel", {}, 6 },
	{ "signpost", { text = "ОСТРОВ", arrow = "right" } },
	{ "billboard", { text = "РЫБНЫЙ РЫНОК", color = C.Blue }, 22 },
	{ "flowerBox", { seed = 1 }, 7 },
	{ "planter", { seed = 1, variant = "bush" }, 7 },
	{ "planter", { seed = 2, variant = "flowers" }, 7 },
	{ "planter", { seed = 3, variant = "topiary" }, 7 },
	{ "flagPole", { color = C.Red }, 10 },
	{ "campfire", { light = true }, 7 },
})

row("beach+harbour", 0, 160, 9, {
	{ "fenceSegment", { length = 8 }, 10 },
	{ "fenceSegment", { length = 8, style = "rail" }, 10 },
	{ "fenceSegment", { length = 12, color = C.Cyan, trim = C.Yellow }, 14 },
	{ "parasol", { seed = 1 } },
	{ "parasol", { seed = 2, color = C.Blue } },
	{ "beachChair", { seed = 1 }, 6 },
	{ "beachChair", { seed = 2 }, 6 },
	{ "cooler", { seed = 1 }, 5 },
	{ "treasureChest", {}, 7 },
	{ "treasureChest", { open = false }, 7 },
	{ "anchor", {}, 10 },
	{ "fishStatue", {}, 14 },
	{ "fishStatue", { color = C.Gold, pedestal = C.White, trim = C.Blue }, 14 },
	{ "fishingRodRack", {}, 9 },
	{ "dockSegment", { length = 12, piles = "both", depth = 2 }, 12, 1.2 },
})

-- fence along a polyline and bunting between two flag poles
do
	local fx, fz = 162, 150
	Props.fenceLine(propsModel, {
		Vector3.new(fx, 0, fz),
		Vector3.new(fx + 16, 0, fz),
		Vector3.new(fx + 16, 0, fz + 16),
		Vector3.new(fx + 30, 0, fz + 16),
	}, { color = C.White, trim = C.Red })
	used.fenceLine = true
	place("flagPole", fx + 40, fz, { color = C.Blue, height = 10 })
	place("flagPole", fx + 64, fz, { color = C.Yellow, height = 10 })
	Props.bunting(propsModel, Vector3.new(fx + 40, 9.6, fz), Vector3.new(fx + 64, 9.6, fz), {})
	used.bunting = true
	-- lifebuoy on a post
	U.part(propsModel, "LifebuoyPost", Vector3.new(1, 5, 1), CFrame.new(fx + 74, 2.5, fz), C.WoodDark)
	place("lifebuoy", fx + 74, fz + 0.9, {}, 3.4)
	table.insert(sections, { "fence/bunting/lifebuoy", fx + 38, fz + 8, 44 })
end

--------------------------------------------------------------------------------------------
-- Water channel
--------------------------------------------------------------------------------------------

-- pier from the north bank (deck top y = 1.2, runs along Z)
do
	local px = 30
	for k = 0, 3 do
		Props.dockSegment(propsModel, CFrame.new(px, 1.2, WATER_Z0 - 4 + k * 12 + 6), {
			length = 12,
			piles = "front",
			seed = k + 1,
			depth = 9,
		})
	end
	used.dockSegment = true
	place("rowboat", px + 9, WATER_Z0 + 30, { seed = 1, color = C.Red })
	place("rowboat", px - 9, WATER_Z0 + 22, { seed = 2, color = C.Cyan })
	place("motorboat", px + 34, WATER_Z0 + 24, { seed = 1 })
	place("motorboat", px + 34, WATER_Z0 + 62, { seed = 2, color = C.Red })
	place("sailboat", px + 64, WATER_Z0 + 30, { seed = 1, color = C.Blue })
	place("sailboat", px + 64, WATER_Z0 + 80, { seed = 2, color = C.BoatPaint[5] })
	place("buoy", px - 10, WATER_Z0 + 70, { seed = 1, light = true })
	place("buoy", px + 6, WATER_Z0 + 80, { seed = 2, color = C.Yellow })
	place("buoy", px + 20, WATER_Z0 + 92, { seed = 3, color = C.Cyan })
	for i = 0, 3 do
		place("lilyPad", px - 14 + i * 4.5, WATER_Z0 + 100 + (i % 2) * 4, { seed = i + 1, flower = i % 2 == 0 })
	end
	place("reeds", px - 22, WATER_Z0 + 104, { seed = 7 })
	table.insert(sections, { "harbour", px + 28, WATER_Z0 + 50, 60 })
end

-- big water props
place("shipwreck", 140, WATER_Z0 + 64, { seed = 1 })
table.insert(sections, { "shipwreck", 140, WATER_Z0 + 64, 40 })
place("rockArch", 260, WATER_Z0 + 64, { seed = 1 })
table.insert(sections, { "rockArch", 260, WATER_Z0 + 64, 32 })

-- bridges across the channel: a long wooden one with arches and bunting, a stone one
do
	local bx = 312
	Props.bridge(propsModel, Vector3.new(bx, 0, WATER_Z0 - 14), Vector3.new(bx, 0, WATER_Z1 + 14), {
		deckY = 3,
		width = 14,
		bedY = -8,
		bunting = true,
		buntingEvery = 2,
		signText = "ОСТРОВ",
	})
	Props.bridge(propsModel, Vector3.new(bx + 50, 0, WATER_Z0 - 10), Vector3.new(bx + 50, 0, WATER_Z1 + 10), {
		deckY = 2.6,
		width = 12,
		bedY = -8,
		style = "stone",
	})
	used.bridge = true
	table.insert(sections, { "bridges", bx + 25, (WATER_Z0 + WATER_Z1) / 2, 70 })
end

-- waterfall off a voxel cliff on the south bank
do
	local wx = 398
	local cliff = U.model(map, "Cliff")
	U.part(cliff, "CliffBase", Vector3.new(60, 24, 24), CFrame.new(wx, 12, WATER_Z1 + 12), C.Stone)
	U.part(cliff, "CliffTop", Vector3.new(60, 3, 24), CFrame.new(wx, 25.5, WATER_Z1 + 12), C.GrassTop)
	U.part(cliff, "CliffStep", Vector3.new(20, 10, 6), CFrame.new(wx - 24, 5, WATER_Z1 - 2), C.StoneDark)
	U.part(cliff, "River", Vector3.new(12, 0.6, 24), CFrame.new(wx, 27.1, WATER_Z1 + 12), C.Water)
	Props.waterfall(propsModel, Vector3.new(wx, 27, WATER_Z1 + 1), Vector3.new(wx, 0, WATER_Z1 - 6), 12)
	used.waterfall = true
	table.insert(sections, { "waterfall", wx, WATER_Z1, 30 })
end

--------------------------------------------------------------------------------------------
-- Landmarks
--------------------------------------------------------------------------------------------

row("landmarks", 0, 392, 50, {
	{ "lighthouse", {}, 40 },
	{ "windmill", {}, 44 },
	{ "watchtower", {}, 36 },
	{ "ferrisWheel", {}, 64 },
	{ "giantTree", {}, 64 },
	{ "giantTree", { seed = 2, leaves = { C.Blossom0, C.Blossom1, C.Blossom2 }, roof = C.Blue }, 64 },
})

-- sky: balloons and clouds above the north edge (they show up in the sky of the views)
place("hotAirBalloon", 110, -12, { seed = 1 }, 34)
place("hotAirBalloon", 235, -4, { seed = 4 }, 26)
place("cloud", 40, -24, { seed = 1 }, 58)
place("cloud", 170, -28, { seed = 2, size = 44 }, 66)
place("cloud", 300, -22, { seed = 3, size = 34 }, 54)
table.insert(sections, { "sky", 170, -20, 150 })

--------------------------------------------------------------------------------------------
-- Coverage check, output
--------------------------------------------------------------------------------------------

local HELPERS =
	{ makeRng = true, shade = true, lerpColor = true, tones = true, fx = true, fxAt = true, bloomCentre = true }
local missing = {}
for name, value in Props :: any do
	if type(value) == "function" and not HELPERS[name] and not used[name] then
		table.insert(missing, name)
	end
end
table.sort(missing)
if #missing > 0 then
	error("gallery does not show: " .. table.concat(missing, ", "))
end

local parts = 0
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") then
		parts += 1
	end
end

-- parts per prop model (min..max over the instances shown)
local perProp: { [string]: { number } } = {}
for _, model in propsModel:GetChildren() do
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	local range = perProp[model.Name]
	if range then
		range[1] = math.min(range[1], n)
		range[2] = math.max(range[2], n)
	else
		perProp[model.Name] = { n, n }
	end
end
local names = {}
for name in perProp do
	table.insert(names, name)
end
table.sort(names)
local lines = {}
for _, name in names do
	local r = perProp[name]
	table.insert(lines, if r[1] == r[2] then `{name} {r[1]}` else `{name} {r[1]}-{r[2]}`)
end
fs.writeFile(out, roblox.serializePlace(game))
print(`Gallery written to {out}: {parts} parts`)
print("Parts per prop: " .. table.concat(lines, ", "))
print("Zoom targets (label: --zoom X,Z,R):")
for _, s in sections do
	print(
		string.format("  %-24s --zoom %g,%g,%g", s[1], math.floor(s[2] + 0.5), math.floor(s[3] + 0.5), math.ceil(s[4]))
	)
end
