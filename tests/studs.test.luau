--[[
	LEGO studs (tools/builder/Studs.luau, art direction v5) — pure Lune, no sim: builds the map and
	the base template like tools/build.luau, runs Studs.apply + Studs.resolveCoplanar and checks
	  • the rules on hand-made parts: blocks only, opaque SmoothPlastic/Plastic only, whole studs on
	    small faces, the face that points world-up gets Studs whatever local axis it is, Inlet below
	    only where StudsBottom = true (never on foliage), Studs = false / true attributes, variant B
	    (PATHS_AS_TILES), foliage switch, water-like names;
	  • the coplanar fix on hand-made parts: out-of-phase grids and studs-on-flat move, one aligned
	    grid of one colour stays, protected parts never move, layers never swap, a squeezed paving
	    disc becomes one flat tile;
	  • the real map and template: Plastic only where studded, one Studs face up / an Inlet down
	    only where asked (the arcade ceilings), nothing on water / glass / sky / seabed, every land
	    cap and the base lawns and decks studded, the fishing spot smooth, the hero faces on whole
	    studs, no coplanar stud overlap left, counts in their band, deterministic;
	  • runtime parts stay smooth: rods / bobbers / fish (Assets) and every Part created in src/.

	Run: lune run tools/run_tests.luau studs
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local U = require("../tools/builder/Util")
local VoxelWorld = require("../tools/builder/VoxelWorld")
local buildMap = require("../tools/builder/Map")
local buildBaseTemplate = require("../tools/builder/BaseTemplate")
local buildAssets = require("../tools/builder/Assets")
local Studs = require("../tools/builder/Studs")

local Enum = U.Enum
local Vector3 = U.Vector3
local CFrame = U.CFrame
local rgb = U.rgb

local cfg = U.loadPure("src/ReplicatedStorage/Shared/Config/MapConfig.luau")
local world = VoxelWorld.new(cfg)

-- The real thing, built once (like tools/build.luau).
local function buildAll(): (any, any, any)
	local game = roblox.Instance.new("DataModel")
	local map = buildMap(game, cfg, world).map
	local template = buildBaseTemplate(game, cfg).template
	local stats = {
		map = Studs.apply(map),
		template = Studs.apply(template),
		fixMap = Studs.resolveCoplanar({ map }),
		fixTemplate = Studs.resolveCoplanar({ template }),
	}
	return map, template, stats
end
local map, template, stats = buildAll()

local function studded(root: any): { any }
	local list = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and Studs.isStudded(d) then
			table.insert(list, d)
		end
	end
	return list
end

local function surfaces(part: any): string
	local acc = {}
	for _, face in Studs.ALL_FACES do
		table.insert(acc, part[face].Name)
	end
	return table.concat(acc, ",")
end

-- A sandbox model for hand-made parts.
local function sandbox(): any
	local game = roblox.Instance.new("DataModel")
	return U.model(game:GetService("Workspace"), "Sandbox")
end

local function block(parent: any, name: string, size: any, cframe: any, color: any?, extra: any?): any
	return U.part(parent, name, size, cframe, color or rgb(120, 180, 90), nil, extra)
end

local tests = {}

--------------------------------------------------------------------------------
-- Rules on hand-made parts
--------------------------------------------------------------------------------

tests["a flat block gets Plastic, Studs on top, the rest Smooth; Inlet below only where asked"] = function(t)
	local box = sandbox()
	local deck = block(box, "Deck", Vector3.new(8, 1, 4), CFrame.new(0, 0, 0))
	-- a ceiling asks for the LEGO underside (StudsBottom = true, here on an ancestor) …
	local hall = U.model(box, "Hall")
	hall:SetAttribute("StudsBottom", true)
	local ceiling = block(hall, "Ceiling", Vector3.new(8, 0.4, 6), CFrame.new(0, 10, 0))
	-- … a canopy never does (no holes punched in the leaves)
	local canopy = block(hall, "Canopy", Vector3.new(6, 2, 6), CFrame.new(20, 10, 0))
	local s = Studs.apply(box)
	t.eq(s.ok, 3, "three parts studded")
	t.eq(deck.Material, Enum.Material.Plastic, "Plastic (surfaces render only on Plastic)")
	t.eq(surfaces(deck), "Studs,Smooth,Smooth,Smooth,Smooth,Smooth", "Top Studs, the bottom smooth")
	t.ok(Studs.studsFaceUp(deck), "the Studs face points up")
	t.eq(surfaces(ceiling), "Studs,Inlet,Smooth,Smooth,Smooth,Smooth", "StudsBottom: Bottom Inlet")
	t.eq(surfaces(canopy), "Studs,Smooth,Smooth,Smooth,Smooth,Smooth", "foliage: no Inlet")
end

tests["the face pointing world-up gets the studs whatever local axis points up"] = function(t)
	local box = sandbox()
	-- local X up (rolled 90° about Z): RightSurface (+X) is on top
	local rolled = block(box, "Rolled", Vector3.new(1, 6, 4), CFrame.Angles(0, 0, math.rad(90)))
	-- local -Z up (pitched -90° about X): FrontSurface (-Z) is on top
	local pitched = block(box, "Pitched", Vector3.new(4, 6, 1), CFrame.Angles(math.rad(90), 0, 0))
	-- upside down: BottomSurface is on top
	local flipped = block(box, "Flipped", Vector3.new(4, 1, 4), CFrame.Angles(math.rad(180), 0, 0))
	-- yawed 30°: still the top
	local yawed = block(box, "Yawed", Vector3.new(4, 1, 6), CFrame.new(20, 0, 0) * CFrame.Angles(0, math.rad(30), 0))
	box:SetAttribute("StudsBottom", true) -- (the Inlet shows which face points down)
	Studs.apply(box)
	t.eq(rolled.CFrame.RightVector.Y > 0.99, true, "setup: rolled +X up")
	t.eq(rolled.RightSurface, Enum.SurfaceType.Studs, "rolled: +X face studded")
	t.eq(rolled.LeftSurface, Enum.SurfaceType.Inlet, "rolled: -X face inlet")
	t.eq(rolled.TopSurface, Enum.SurfaceType.Smooth, "rolled: +Y (a side now) smooth")
	t.eq(-pitched.CFrame.LookVector.Y > 0.99 or pitched.CFrame.LookVector.Y > 0.99, true, "setup: pitched Z vertical")
	t.ok(Studs.studsFaceUp(pitched), "pitched: the studs on the face pointing up")
	t.eq(flipped.BottomSurface, Enum.SurfaceType.Studs, "upside down: Bottom (now on top) studded")
	t.eq(flipped.TopSurface, Enum.SurfaceType.Inlet, "upside down: Top (now below) inlet")
	t.eq(yawed.TopSurface, Enum.SurfaceType.Studs, "yawed: top studded")
	for _, p in { rolled, pitched, flipped, yawed } do
		t.eq(#Studs.studFaces(p), 1, `{p.Name}: exactly one Studs face`)
		t.ok(Studs.studsFaceUp(p), `{p.Name}: studs up`)
	end
end

tests["exclusions: shapes, materials, transparency, tilt, small and fractional faces, names, ancestors"] = function(t)
	local box = sandbox()
	local cases = {
		{ block(box, "Ok", Vector3.new(4, 1, 4), CFrame.new(0, 0, 0)), "ok" },
		{ block(box, "OkBig", Vector3.new(7.3, 1, 2.6), CFrame.new(10, 0, 0)), "ok" }, -- >= 6 on one side: cut studs allowed
		{
			U.wedge(box, "Roof", Vector3.new(4, 2, 4), CFrame.new(20, 0, 0), rgb(150, 60, 50)),
			"class",
		},
		{
			block(box, "Barrel", Vector3.new(4, 4, 4), CFrame.new(30, 0, 0), nil, { Shape = Enum.PartType.Cylinder }),
			"shape",
		},
		{
			U.part(box, "Lamp", Vector3.new(4, 1, 4), CFrame.new(40, 0, 0), rgb(255, 230, 150), Enum.Material.Neon),
			"material",
		},
		{
			block(box, "Pane", Vector3.new(4, 1, 4), CFrame.new(50, 0, 0), nil, { Transparency = 0.5 }),
			"transparent",
		},
		{
			block(box, "Tilted", Vector3.new(4, 1, 4), CFrame.Angles(math.rad(10), 0, 0) + Vector3.new(60, 0, 0)),
			"tilted",
		},
		{ block(box, "Narrow", Vector3.new(1.6, 1, 8), CFrame.new(70, 0, 0)), "small" },
		{ block(box, "Crate", Vector3.new(3.5, 1, 3.5), CFrame.new(80, 0, 0)), "fractional" },
		{ block(box, "PondWater", Vector3.new(8, 1, 8), CFrame.new(90, 0, 0)), "name" },
		{ block(box, "SeaFoam", Vector3.new(8, 1, 8), CFrame.new(100, 0, 0)), "name" },
		{ block(box, "PoolRim", Vector3.new(8, 1, 8), CFrame.new(110, 0, 0)), "ok" }, -- solid: SKIP_NAME_EXCEPT
		{ block(box, "Jetty", Vector3.new(8, 1, 8), CFrame.new(120, 0, 0)), "ok" },
	}
	local sky = U.folder(box, "Sky")
	table.insert(cases, { block(sky, "Cloud", Vector3.new(8, 2, 8), CFrame.new(0, 80, 0)), "ancestor" })
	local underwater = U.folder(box, "Underwater")
	table.insert(cases, { block(underwater, "Seabed", Vector3.new(16, 2, 16), CFrame.new(0, -30, 0)), "ancestor" })
	for _, case in cases do
		local ok, why = Studs.qualifies(case[1], box)
		t.eq(why, case[2], case[1].Name)
		t.eq(ok, case[2] == "ok", `{case[1].Name} qualifies`)
	end
	Studs.apply(box)
	for _, case in cases do
		local part = case[1]
		if case[2] ~= "ok" then
			t.ok(not Studs.isStudded(part), `{part.Name} stays without studs`)
			t.eq(surfaces(part):find("Studs") == nil, true, `{part.Name}: no Studs surface`)
		end
	end
end

tests["attribute Studs = false opts out (on an ancestor too), Studs = true skips name filters only"] = function(t)
	local box = sandbox()
	local plain = U.model(box, "Plain")
	plain:SetAttribute("Studs", false)
	local inner = block(plain, "Floor", Vector3.new(8, 1, 8), CFrame.new(0, 0, 0))
	local own =
		block(box, "Floor2", Vector3.new(8, 1, 8), CFrame.new(20, 0, 0), nil, { Attributes = { Studs = false } })
	local forced =
		block(box, "IceWater", Vector3.new(8, 1, 8), CFrame.new(40, 0, 0), nil, { Attributes = { Studs = true } })
	local forcedSmall =
		block(box, "Tiny", Vector3.new(1, 1, 1), CFrame.new(60, 0, 0), nil, { Attributes = { Studs = true } })
	Studs.apply(box)
	t.ok(not Studs.isStudded(inner), "ancestor Studs = false")
	t.ok(not Studs.isStudded(own), "own Studs = false")
	t.ok(Studs.isStudded(forced), "Studs = true beats the water-like name")
	t.ok(not Studs.isStudded(forcedSmall), "Studs = true does not beat the geometry rules")
end

tests["variant B (PATHS_AS_TILES) keeps paved walks smooth; FOLIAGE = false keeps tree tops smooth"] = function(t)
	local box = sandbox()
	local paving = U.folder(box, "Paving")
	local tile = block(paving, "Tile", Vector3.new(8, 1, 8), CFrame.new(0, 0, 0))
	local walk = block(box, "CrossWalk", Vector3.new(8, 1, 4), CFrame.new(20, 0, 0))
	local lawn = block(box, "Lawn", Vector3.new(8, 1, 8), CFrame.new(40, 0, 0))
	local canopy = block(box, "CanopyTop", Vector3.new(6, 2, 6), CFrame.new(60, 0, 0))
	local saved = { Studs.PATHS_AS_TILES, Studs.FOLIAGE }
	Studs.PATHS_AS_TILES, Studs.FOLIAGE = true, false
	local ok1, why1 = Studs.qualifies(tile, box)
	local ok2, why2 = Studs.qualifies(walk, box)
	local ok3 = Studs.qualifies(lawn, box)
	local ok4, why4 = Studs.qualifies(canopy, box)
	Studs.PATHS_AS_TILES, Studs.FOLIAGE = saved[1], saved[2]
	t.ok(not ok1 and why1 == "tile", "tile under Paving smooth in variant B")
	t.ok(not ok2 and why2 == "tile", "…Walk smooth in variant B")
	t.ok(ok3, "lawns keep studs in variant B")
	t.ok(not ok4 and why4 == "foliage", "canopy smooth with FOLIAGE = false")
	t.eq(Studs.PATHS_AS_TILES, false, "default: variant A (studs on paths)")
	t.ok(select(1, Studs.qualifies(tile, box)), "variant A: tiles studded")
end

--------------------------------------------------------------------------------
-- Coplanar fix on hand-made parts
--------------------------------------------------------------------------------

local function top(part: any): number
	return part.CFrame.Position.Y + part.Size.Y / 2
end

tests["coplanar: out-of-phase grids and studs on flat are separated, aligned one-colour grids stay"] = function(t)
	local box = sandbox()
	local floor = block(box, "Floor", Vector3.new(16, 1, 16), CFrame.new(0, 0, 0))
	-- same height, grid shifted by 0.5 stud: shimmers
	local rug = block(box, "Rug", Vector3.new(4, 1, 4), CFrame.new(0.5, 0, 0), rgb(200, 60, 60))
	-- same height, same colour, aligned: one surface, nothing to do
	local twin = block(box, "Twin", Vector3.new(16, 1, 16), CFrame.new(32, 0, 0))
	local patch = block(box, "Patch", Vector3.new(4, 1, 4), CFrame.new(32 + 2, 0, 2))
	-- a flat (Neon) inlay level with studs
	local deck = block(box, "Deck", Vector3.new(16, 1, 16), CFrame.new(64, 0, 0))
	local inlay =
		U.part(box, "Inlay", Vector3.new(2, 1, 2), CFrame.new(64, 0, 0), rgb(255, 220, 120), Enum.Material.Neon)
	Studs.apply(box)
	local before = { floor = top(floor), twin = top(twin), patch = top(patch), deck = top(deck) }
	t.eq(Studs.coplanarPairs({ box }), 2, "two conflicting pairs before the fix")
	local fix, flipped = Studs.resolveCoplanar({ box })
	t.eq(Studs.coplanarPairs({ box }), 0, "none after")
	t.eq(fix.left, 0, "left")
	t.eq(#flipped, 0, "no flipped layers")
	t.near(top(rug), before.floor + Studs.RAISE, 1e-4, "the smaller (rug) rises RAISE")
	t.near(top(floor), before.floor, 1e-4, "the floor stays")
	t.near(rug.CFrame.Position.Y - rug.Size.Y / 2, -0.5, 1e-4, "the rug's bottom stays")
	t.near(top(inlay), before.deck + Studs.RAISE, 1e-4, "the flat inlay rises above the studs")
	t.near(top(patch), before.patch, 1e-4, "aligned same-colour patch untouched")
	t.near(top(twin), before.twin, 1e-4, "twin untouched")
end

tests["coplanar: protected parts never move, layers never swap, a squeezed disc becomes a flat tile"] = function(t)
	local box = sandbox()
	-- a tagged / attributed gameplay part level with a studded floor: the floor part moves instead
	local floor = block(box, "Floor", Vector3.new(6, 1, 6), CFrame.new(0, 0, 0))
	local spot = block(box, "FishingSpot", Vector3.new(4, 1, 4), CFrame.new(0.5, 0, 0), rgb(220, 90, 90))
	local pad = block(box, "Pad", Vector3.new(4, 1, 4), CFrame.new(20.5, 0, 0), rgb(90, 90, 220), {
		Attributes = { Index = 1 },
	})
	local under = block(box, "Under", Vector3.new(6, 1, 6), CFrame.new(20, 0, 0))
	-- a paving disc: three overlapping pieces of one colour, one rotated, between a layer below and
	-- a runner above, both `gap` away: out of z-fight range (COPLANAR_EPS) but nearer than a
	-- move (RAISE) — no room for a second height
	local gap = (Studs.COPLANAR_EPS + Studs.RAISE) / 2
	local base = block(box, "Ground", Vector3.new(64, 2, 64), CFrame.new(60, -1 + 0.4 - gap, 0))
	local stone = rgb(196, 172, 132)
	local d1 = block(box, "Disc1", Vector3.new(21, 0.8, 9), CFrame.new(60, 0, 0), stone)
	local d2 = block(box, "Disc2", Vector3.new(9, 0.8, 21), CFrame.new(60, 0, 0), stone)
	local d3 =
		block(box, "Disc3", Vector3.new(15, 0.8, 15), CFrame.new(60, 0, 0) * CFrame.Angles(0, math.rad(45), 0), stone)
	local runner = block(box, "Runner", Vector3.new(4, 0.8, 40), CFrame.new(60, gap, 0), rgb(170, 90, 70))
	Studs.apply(box)
	local before = { spot = top(spot), pad = top(pad), runner = top(runner), base = top(base) }
	local fix, flipped = Studs.resolveCoplanar({ box })
	t.eq(Studs.coplanarPairs({ box }), 0, "nothing left")
	t.eq(fix.left, 0, "left")
	t.eq(#flipped, 0, "no layer swapped")
	t.near(top(spot), before.spot, 1e-6, "FishingSpot (a name the server uses) never moves")
	t.near(top(pad), before.pad, 1e-6, "a part with a gameplay attribute never moves")
	t.ok(math.abs(top(floor) - top(spot)) >= Studs.COPLANAR_EPS, "the floor moved off the spot instead")
	t.ok(math.abs(top(under) - top(pad)) >= Studs.COPLANAR_EPS, "the other part moved off the pad")
	t.near(top(runner), before.runner, 1e-6, "the runner above keeps its place")
	for _, d in { d1, d2, d3 } do
		t.ok(top(d) < top(runner) - Studs.COPLANAR_EPS, `{d.Name} stays under the runner`)
		t.ok(top(d) > before.base + Studs.COPLANAR_EPS, `{d.Name} stays above the layer below`)
		t.ok(not Studs.isStudded(d), `{d.Name}: the squeezed disc is one flat tile`)
		t.eq(d.Material, Enum.Material.SmoothPlastic, `{d.Name}: flattened to SmoothPlastic`)
	end
	t.ok(fix.flattened >= 3, "flattened the disc")
end

--------------------------------------------------------------------------------
-- The real map and base template
--------------------------------------------------------------------------------

local function invariants(t: any, root: any)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and not d:IsA("TrussPart") then
			local nonSmooth = false
			for _, face in Studs.ALL_FACES do
				if d[face] ~= Enum.SurfaceType.Smooth then
					nonSmooth = true
				end
			end
			if nonSmooth then
				t.eq(d.Material, Enum.Material.Plastic, `{d:GetFullName()}: surfaces only on Plastic`)
			end
			if d.Material == Enum.Material.Plastic then
				t.ok(Studs.isStudded(d), `{d:GetFullName()}: Plastic only where studded`)
			end
			if Studs.isStudded(d) then
				t.ok(Studs.studsFaceUp(d), `{d:GetFullName()}: one Studs face, pointing up`)
				t.ok(d.Transparency <= Studs.MAX_TRANSPARENCY, `{d:GetFullName()}: opaque`)
				t.ok(d.ClassName == "Part" or d.ClassName == "SpawnLocation", `{d:GetFullName()}: a block part`)
				local inlets = 0
				for _, face in Studs.ALL_FACES do
					if d[face] == Enum.SurfaceType.Inlet then
						inlets += 1
					end
				end
				-- (the LEGO underside only where a ceiling asks for it, never on foliage)
				local want = if Studs.wantsInlet(d, root) then 1 else 0
				t.eq(inlets, want, `{d:GetFullName()}: {want} Inlet face (the bottom)`)
				local x = d.Parent
				while x and x ~= root.Parent do
					t.ok(not Studs.SKIP_ANCESTOR[x.Name], `{d:GetFullName()}: studs under {x.Name}`)
					x = x.Parent
				end
			end
		end
	end
end

tests["map: surfaces only on Plastic, studs up, inlets down, nothing on water / sky / seabed"] = function(t)
	invariants(t, map)
	local studdedWater = 0
	for _, d in map:GetDescendants() do
		if d:IsA("BasePart") and Studs.isStudded(d) then
			local lower = string.lower(d.Name)
			local solid = false -- pool rims, breakwaters, … (Studs.SKIP_NAME_EXCEPT)
			for _, keep in Studs.SKIP_NAME_EXCEPT do
				solid = solid or string.find(lower, keep, 1, true) ~= nil
			end
			if (lower:find("water") or lower:find("foam") or lower:find("cloud")) and not solid then
				studdedWater += 1
			end
		end
	end
	t.eq(studdedWater, 0, "water / foam / clouds smooth")
end

tests["template: the same invariants; lawns and decks studded, the fishing spot and spawn pad kept"] = function(t)
	invariants(t, template)
	local pier, platform = template:FindFirstChild("Pier"), template:FindFirstChild("Platform")
	local named = {
		Lawn = template:FindFirstChild("Lawn", true),
		TerraceLawn = template:FindFirstChild("TerraceLawn", true),
		["Pier.Deck"] = pier and pier:FindFirstChild("Deck", true),
		["Platform.Deck"] = platform and platform:FindFirstChild("Deck", true),
	}
	for label, part in named do
		t.ok(part ~= nil, `template has {label}`)
		if part then
			t.ok(Studs.isStudded(part), `{label} studded`)
		end
	end
	local spot = template:FindFirstChild("FishingSpot", true)
	t.ok(spot ~= nil and not Studs.isStudded(spot), "FishingSpot smooth (a LEGO tile: Studs = false)")
	-- v3 fix W4: the hero surfaces on whole studs — the ring round the spot is exactly one ring of
	-- whole studs round the 5 x 5 mat; lawn, stripes, decks, planks and display rims whole too
	local ring = platform and platform:FindFirstChild("SpotRing")
	t.ok(ring ~= nil and Studs.isStudded(ring), "SpotRing studded")
	if ring and spot then
		t.near(ring.Size.X, 7, 1e-3, "SpotRing 7 wide")
		t.near(ring.Size.Z, 7, 1e-3, "SpotRing 7 deep")
		t.near(spot.Size.X, 5, 1e-3, "FishingSpot 5 wide")
		t.near(spot.Size.Z, 5, 1e-3, "FishingSpot 5 deep")
	end
	local HERO = { Lawn = true, Stripe = true, Deck = true, Planks = true, SpotRing = true, Rim = true }
	local off = Studs.fractionalFaces(template, function(p: any): boolean
		return HERO[p.Name] == true
	end)
	local names = {}
	for i = 1, math.min(#off, 5) do
		table.insert(names, `{off[i]:GetFullName()} {off[i].Size}`)
	end
	t.eq(#off, 0, `hero faces off whole studs: {table.concat(names, ", ")}`)
	-- v3 fix W7: no Inlet under the shelter's roof; the market arcade's ceiling keeps it
	local pav = template:FindFirstChild("Pavilion")
	for _, roof in (if pav then pav:GetChildren() else {}) do
		if roof:IsA("BasePart") and roof.Name == "Roof" then
			t.ok(roof.BottomSurface ~= Enum.SurfaceType.Inlet, "no Inlet under the shelter's roof")
		end
	end
	local ceiling = template:FindFirstChild("Ceiling", true)
	t.ok(ceiling ~= nil and Studs.wantsInlet(ceiling, template), "the arcade ceiling asks for the LEGO underside")
end

tests["map: every land cap is studded, nothing under Ground.Underwater"] = function(t)
	local CAPS = {
		Grass = true,
		Sand = true,
		Meadow = true,
		Snow = true,
		Stone = true,
		RedRock = true,
		Mountainside = true,
		Sandstone = true,
		Path = true,
	}
	local caps, missing = 0, {}
	for _, d in map.Ground.Land:GetChildren() do
		if d:IsA("BasePart") and CAPS[d.Name] then
			caps += 1
			if not Studs.isStudded(d) then
				table.insert(missing, d.Name)
			end
		end
	end
	t.ok(caps > 1000, `land caps found ({caps})`)
	t.eq(#missing, 0, `land caps without studs: {table.concat(missing, ", ")}`)
	t.eq(#studded(map.Ground.Underwater), 0, "no studs under water")
end

tests["map + template: no coplanar stud overlap left, no layer swapped, few parts moved"] = function(t)
	t.eq(Studs.coplanarPairs({ map }), 0, "map pairs left")
	t.eq(Studs.coplanarPairs({ template }), 0, "template pairs left")
	for _, key in { "fixMap", "fixTemplate" } do
		local fix = stats[key]
		t.eq(fix.left, 0, `{key}: left`)
		t.eq(fix.inverted, 0, `{key}: flipped layers`)
		t.ok(fix.passes <= Studs.MAX_PASSES, `{key}: passes`)
	end
	local moved = stats.fixMap.raised + stats.fixMap.lowered
	t.ok(moved > 50 and moved < 400, `map parts moved: {moved}`)
	-- (v3 W3: the builders keep their layers 0.06 apart, so no studded paving goes flat — the
	-- gateway plazas' walks and medallions, the hub's side walks, the pond rims keep their studs)
	t.ok(stats.fixMap.flattened <= 4, `map parts flattened: {stats.fixMap.flattened}`)
	t.eq(stats.fixTemplate.flattened, 0, "template parts flattened")
end

tests["counts: studded parts in the expected band"] = function(t)
	local m, tp = #studded(map), #studded(template)
	local bm, bt = Studs.EXPECTED.map, Studs.EXPECTED.template
	t.ok(m >= bm[1] and m <= bm[2], `map studded {m} in {bm[1]}..{bm[2]}`)
	t.ok(tp >= bt[1] and tp <= bt[2], `template studded {tp} in {bt[1]}..{bt[2]}`)
	t.eq(stats.map.ok - stats.fixMap.flattened, m, "apply count minus flattened = studded")
	t.log(`studs: map {m}, template {tp} × {cfg.BaseCount}; moved {stats.fixMap.raised + stats.fixMap.lowered}`)
end

tests["deterministic: a second build gets the same studs and the same fixes"] = function(t)
	local function signature(root: any): string
		local acc = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				local p = d.CFrame.Position
				table.insert(
					acc,
					string.format(
						"%s %s %s %.3f,%.3f,%.3f %.3f",
						d.Name,
						d.Material.Name,
						surfaces(d),
						p.X,
						p.Y,
						p.Z,
						d.Size.Y
					)
				)
			end
		end
		return table.concat(acc, ";")
	end
	local map2, template2 = buildAll()
	t.ok(signature(map2) == signature(map), "identical map")
	t.ok(signature(template2) == signature(template), "identical template")
end

--------------------------------------------------------------------------------
-- Runtime parts stay smooth
--------------------------------------------------------------------------------

tests["Assets (rods, bobbers, fish) carry no surfaces"] = function(t)
	local game = roblox.Instance.new("DataModel")
	buildAssets(game, {
		FishConfig = U.loadPure("src/ReplicatedStorage/Shared/Config/FishConfig.luau"),
		RodConfig = U.loadPure("src/ReplicatedStorage/Shared/Config/RodConfig.luau"),
	})
	local parts = 0
	for _, d in game:GetService("ReplicatedStorage").Assets:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			for _, face in Studs.ALL_FACES do
				t.eq(d[face], Enum.SurfaceType.Smooth, `{d:GetFullName()}.{face}`)
			end
		end
	end
	t.ok(parts > 100, `asset parts checked ({parts})`)
end

-- Instance.new("Part") is Plastic with Studs on top and Inlet below by default: every part made at
-- runtime in src/ must say what it is (SmoothPlastic, or its own material) within its first lines.
tests["every Part created in src/ sets its Material explicitly (no accidental studs)"] = function(t)
	local function walk(dir: string, out: { string })
		for _, name in fs.readDir(dir) do
			local path = dir .. "/" .. name
			if fs.isDir(path) then
				walk(path, out)
			elseif string.sub(name, -5) == ".luau" then
				table.insert(out, path)
			end
		end
	end
	local files = {}
	walk("src", files)
	table.sort(files)
	local sites = 0
	for _, path in files do
		local lines = string.split(fs.readFile(path), "\n")
		for i, line in lines do
			local class = string.match(line, 'Instance%.new%(%s*"([%a]*Part)"')
				or string.match(line, 'Instance%.new%(%s*"(SpawnLocation)"')
				or string.match(line, 'Instance%.new%(%s*"(Seat)"')
			if class then
				sites += 1
				-- `x.Material = Enum.Material.…` or a property table's `Material = Enum.Material.…`
				local found = false
				for j = i, math.min(#lines, i + 25) do
					if string.find(lines[j], "Material = Enum.Material.", 1, true) then
						found = true
						break
					end
				end
				t.ok(found, `{path}:{i}: {class} without an explicit Material (Instance.new gives Plastic + studs)`)
			end
		end
	end
	t.ok(sites >= 2, `creation sites found ({sites})`)
end

return tests
