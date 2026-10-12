--[[
	Map dressing (tools/builder/Map.luau and its modules) invariants — pure Lune, no sim:
	part / light budget, the expected models, a spinning windmill, a clear promenade walkway,
	clear water in front of the piers and along the bridges, deterministic output.

	Run: lune run tools/run_tests.luau map_dressing
]]

local roblox = require("@lune/roblox")

local U = require("../tools/builder/Util")
local VoxelWorld = require("../tools/builder/VoxelWorld")
local buildMap = require("../tools/builder/Map")

local cfg = U.loadPure("src/ReplicatedStorage/Shared/Config/MapConfig.luau")
local world = VoxelWorld.new(cfg)

local game = roblox.Instance.new("DataModel")
local result = buildMap(game, cfg, world)
local map = result.map

local DRESSING_EXCLUDED = { Ground = true, Hub = true }

-- Every BasePart of the dressing (all of Map except Ground and Hub).
local function dressingParts(): { any }
	local list = {}
	for _, child in map:GetChildren() do
		if not DRESSING_EXCLUDED[child.Name] then
			for _, d in child:GetDescendants() do
				if d:IsA("BasePart") then
					table.insert(list, d)
				end
			end
			if child:IsA("BasePart") then
				table.insert(list, child)
			end
		end
	end
	return list
end

local function radius(p: any): number
	return math.sqrt(p.X * p.X + p.Z * p.Z)
end

local tests = {}

tests["dressing stays within 4000 parts and 40 PointLights"] = function(t)
	local parts = dressingParts()
	local lights = 0
	for _, child in map:GetChildren() do
		if not DRESSING_EXCLUDED[child.Name] then
			for _, d in child:GetDescendants() do
				if d:IsA("PointLight") then
					lights += 1
					t.ok(d.Range <= 16 and d.Shadows == false, `{d:GetFullName()}: Range <= 16, no shadows`)
				end
			end
		end
	end
	t.ok(#parts <= 4000, `dressing parts {#parts} <= 4000`)
	t.ok(lights <= 40, `dressing lights {lights} <= 40`)
end

tests["all dressing groups are there"] = function(t)
	for _, name in
		{
			"BaseSlots",
			"Ground",
			"Hub",
			"Bridges",
			"Promenade",
			"Gateways",
			"Landmarks",
			"Lagoon",
			"Ocean",
			"Sky",
			"Nature",
			"Boundaries",
		}
	do
		t.ok(map:FindFirstChild(name) ~= nil, `Map.{name}`)
	end
	for i = 1, #cfg.BridgeAngles do
		t.ok(map.Bridges:FindFirstChild(`Bridge_{i}`) ~= nil, `Bridge_{i}`)
		t.ok(map.Gateways:FindFirstChild(`Gateway_{i}`) ~= nil, `Gateway_{i}`)
	end
	for _, name in { "Waterfall", "Windmill", "GiantTree", "Peaks" } do
		t.ok(map.Landmarks:FindFirstChild(name) ~= nil, `Landmarks.{name}`)
	end
	local clouds = #map.Sky:GetChildren()
	t.ok(clouds >= 10 and clouds <= 16, `10..16 clouds ({clouds})`)
	t.ok(#map.BaseSlots:GetChildren() == cfg.BaseCount, "base slots")
	local trees = 0
	for _ in map.Nature.Trees:GetChildren() do
		trees += 1
	end
	t.ok(trees >= 60, `forests on the hills ({trees} trees)`)
end

tests["the windmill blades spin (Spin attribute on a Model with a pivot)"] = function(t)
	local spinners = 0
	for _, d in map:GetDescendants() do
		if d:IsA("Model") and typeof(d:GetAttribute("Spin")) == "number" then
			spinners += 1
			t.ok(d.PrimaryPart ~= nil, `{d:GetFullName()} has a PrimaryPart (its pivot is the hub)`)
		end
	end
	t.ok(spinners >= 1, `spinning models: {spinners}`)
	local mill = map.Landmarks.Windmill:FindFirstChild("Windmill")
	t.ok(mill and mill:FindFirstChild("Blades") and mill.Blades:GetAttribute("Spin") ~= nil, "Windmill.Blades spins")
end

tests["promenade walkway is clear (nothing solid on the running lane)"] = function(t)
	local inner = cfg.PromenadeRadius + 1.8 -- inside the railing kerb
	local outer = cfg.PromenadeRadius + cfg.PromenadeWidth - 5 -- benches/boxes stand on the outer edge
	local floorY = cfg.GroundTop + 0.9
	local bad = {}
	for _, p in dressingParts() do
		if p.CanCollide and p.Transparency < 1 and not p:IsDescendantOf(map.Promenade.Paving) then
			local pos = p.CFrame.Position
			local r = radius(pos)
			local halfY = p.Size.Y / 2
			if r > inner and r < outer and pos.Y - halfY < floorY + 5 and pos.Y + halfY > floorY then
				table.insert(bad, p:GetFullName())
			end
		end
	end
	t.eq(#bad, 0, `solid parts on the promenade lane: {table.concat(bad, ", ", 1, math.min(#bad, 5))}`)
end

tests["water in front of the piers and along the bridges stays clear"] = function(t)
	local bad = {}
	for _, group in { map.Lagoon, map.Nature } do
		for _, p in group:GetDescendants() do
			if p:IsA("BasePart") then
				local pos = p.CFrame.Position
				for i = 1, cfg.BaseCount do
					local lx, lz = world:toBaseLocal(i, pos.X, pos.Z)
					if math.abs(lx) <= 26 and lz >= -cfg.PierLength and lz <= 0 then
						table.insert(bad, `{p:GetFullName()} in front of pier {i}`)
					end
				end
				for _, a in cfg.BridgeAngles do
					local ux, uz = math.sin(math.rad(a)), math.cos(math.rad(a))
					local along = pos.X * ux + pos.Z * uz
					local side = math.abs(pos.X * uz - pos.Z * ux)
					if along > cfg.HubRadius and along < cfg.LagoonRadius and side < cfg.BridgeWidth / 2 + 4 then
						table.insert(bad, `{p:GetFullName()} at bridge {a}`)
					end
				end
			end
		end
	end
	t.eq(#bad, 0, `obstacles: {table.concat(bad, ", ", 1, math.min(#bad, 5))}`)
end

tests["nature keeps off reserved ground and water"] = function(t)
	local bad = {}
	for _, model in map.Nature.Trees:GetChildren() do
		local pos = (model.PrimaryPart.CFrame * model.PrimaryPart.PivotOffset).Position -- (Lune has no GetPivot)
		if world:isReserved(pos.X, pos.Z, 2) or world:isWater(pos.X, pos.Z) then
			table.insert(bad, `{model.Name} at ({math.floor(pos.X)}, {math.floor(pos.Z)})`)
		end
	end
	t.eq(#bad, 0, `trees on reserved ground or in water: {table.concat(bad, ", ", 1, math.min(#bad, 5))}`)
end

tests["deterministic: a second build places the same parts"] = function(t)
	local function signature(root: any): string
		local acc = {}
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and not d:IsDescendantOf(root.Ground) then
				local p = d.CFrame.Position
				table.insert(acc, string.format("%s%.2f,%.2f,%.2f", d.Name, p.X, p.Y, p.Z))
			end
		end
		return table.concat(acc, ";")
	end
	local other = roblox.Instance.new("DataModel")
	local again = buildMap(other, cfg, world)
	t.ok(signature(again.map) == signature(map), "identical dressing")
end

return tests
