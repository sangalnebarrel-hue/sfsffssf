--[[
	Map dressing (tools/builder/Map.luau and its modules) invariants — pure Lune, no sim:
	part / light budget (and Nature's guaranteed share), the expected models, a spinning windmill, a clear promenade walkway,
	clear water in front of the piers and along the bridges, deterministic output; the v3 micro-detail kits (Shore,
	Promenade details, Hub details: budgets, decor flags, the cast clear zones, no overlapping surf / wet-sand strips) and
	the ambient attributes (Sway / Bob / Spin / Pulse / Drift well-formed, never nested; every
	mover's parts neither collide nor take raycasts / touches — palm trunks excepted —, the floats
	you can stand on do not bob: tools/builder/Movers.luau), the float lines framing every cast lane.

	Run: lune run tools/run_tests.luau map_dressing
]]

local roblox = require("@lune/roblox")

local U = require("../tools/builder/Util")
local VoxelWorld = require("../tools/builder/VoxelWorld")
local buildMap = require("../tools/builder/Map")
local Movers = require("../tools/builder/Movers")

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

tests["dressing stays within its part / PointLight budget and Nature gets its minimum"] = function(t)
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
	local budget = result.budget
	t.ok(#parts <= budget.dressing, `dressing parts {#parts} <= {budget.dressing}`)
	t.ok(lights <= budget.lights, `dressing lights {lights} <= {budget.lights}`)
	local nature = 0
	for _, d in map.Nature:GetDescendants() do
		if d:IsA("BasePart") then
			nature += 1
		end
	end
	t.ok(nature >= budget.natureMin, `Nature parts {nature} >= {budget.natureMin}`)
end

-- Base-local box of a part for base i: centre (lx, y, lz) and half-extents (from its 8 corners).
local function baseBox(i: number, part: any): (number, number, number, number, number, number)
	local cf, sz = part.CFrame, part.Size / 2
	local x0, x1, y0, y1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, s in { -1, 1 } do
				local w = cf * roblox.Vector3.new(sx * sz.X, sy * sz.Y, s * sz.Z)
				local lx, lz = world:toBaseLocal(i, w.X, w.Z)
				x0, x1 = math.min(x0, lx), math.max(x1, lx)
				z0, z1 = math.min(z0, lz), math.max(z1, lz)
				y0, y1 = math.min(y0, w.Y), math.max(y1, w.Y)
			end
		end
	end
	return (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2, (x1 - x0) / 2, (y1 - y0) / 2, (z1 - z0) / 2
end

-- Every BasePart of the late kits (built after Nature) and the hub's details.
local function kitParts(): { any }
	local list = {}
	for _, root in { map.Shore, map.Promenade:FindFirstChild("Details"), map.Hub:FindFirstChild("Details") } do
		for _, d in (if root then root:GetDescendants() else {}) do
			if d:IsA("BasePart") then
				table.insert(list, d)
			end
		end
	end
	return list
end

tests["micro-detail kits: within their budgets, decor only"] = function(t)
	t.ok(map:FindFirstChild("Shore") ~= nil, "Map.Shore")
	t.ok(map.Promenade:FindFirstChild("Details") ~= nil, "Map.Promenade.Details")
	t.ok(map.Hub:FindFirstChild("Details") ~= nil, "Map.Hub.Details")
	local late = 0
	for _, root in { map.Shore, map.Promenade.Details } do
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				late += 1
			end
		end
	end
	t.ok(late <= result.budget.late, `late kits {late} <= {result.budget.late}`)
	local hub = 0
	for _, d in map.Hub:GetDescendants() do
		if d:IsA("BasePart") then
			hub += 1
		end
	end
	t.ok(hub <= result.budget.hub, `hub {hub} <= {result.budget.hub}`)
	local bad = {}
	for _, p in kitParts() do
		if p.CanCollide or p.CanQuery or p.CanTouch or p.CastShadow then
			table.insert(bad, p:GetFullName())
		end
	end
	t.eq(
		#bad,
		0,
		`kit parts with collisions / raycasts / touches / shadows: {table.concat(bad, ", ", 1, math.min(#bad, 5))}`
	)
	local counts = { Foam = 0, WetSand = 0, Float = 0, Kelp = 0, SunkenChest = 0, Signpost = 0, Bollard = 0 }
	for _, d in map:GetDescendants() do
		if counts[d.Name] and d:IsDescendantOf(map.Shore) or d:IsDescendantOf(map.Promenade.Details) then
			if counts[d.Name] then
				counts[d.Name] += 1
			end
		end
	end
	t.ok(counts.Foam >= 150 and counts.WetSand >= 150, `surf {counts.Foam} and wet sand {counts.WetSand} strips`)
	t.ok(counts.Float >= 32, `float lines ({counts.Float} floats)`)
	-- v3 fix W2: big LEGO floats (Cylinder + band, ≥ 1.4 studs: a foam ring) out in the cast lane's
	-- view (base-local z -80..-116, |x| 26..30), on every base
	local perBase = {}
	for _, m in map.Shore.Lagoon:GetChildren() do
		if m.Name == "Float" and m:IsA("Model") then
			local body = m.PrimaryPart
			t.ok(
				body and body.Shape == roblox.Enum.PartType.Cylinder and body.Size.Y >= 1.4,
				`{m:GetFullName()}: a big round float`
			)
			t.ok(typeof(m:GetAttribute("Bob")) == "number", `{m:GetFullName()}: bobs`)
			if body then
				for i = 1, cfg.BaseCount do
					local lx, lz = world:toBaseLocal(i, body.CFrame.Position.X, body.CFrame.Position.Z)
					if math.abs(lx) >= 26 and math.abs(lx) <= 30 and lz <= -80 and lz >= -116 then
						perBase[i] = (perBase[i] or 0) + 1
					end
				end
			end
		end
	end
	for i = 1, cfg.BaseCount do
		t.ok((perBase[i] or 0) >= 6, `base {i}: {perBase[i] or 0} floats in the cast lane's view`)
	end
	t.ok(counts.Signpost >= 6 and counts.Bollard >= 30, `signposts {counts.Signpost}, bollards {counts.Bollard}`)
end

tests["shore kit: the piers' cast zones and corridors and the bridges stay clear"] = function(t)
	local bad = {}
	for _, p in kitParts() do
		if not p:IsDescendantOf(map.Shore) then
			continue
		end
		local edge = p.Name == "Foam" or p.Name == "WetSand"
		for i = 1, cfg.BaseCount do
			local lx, y, lz, ex, ey, ez = baseBox(i, p)
			-- the cast clear zone (base-local x -6..16, z -72..-115): nothing above the water
			if lx + ex > -6 and lx - ex < 16 and lz - ez < -72 and lz + ez > -115 and y + ey > cfg.WaterTop - 0.6 then
				table.insert(bad, `{p:GetFullName()} in pier {i}'s cast zone`)
			end
			-- the pier corridor (its deck, its boat, the fishing water): only the surf / wet sand comes
			-- nearer than 26 studs, never nearer than 12
			local side = if edge then 12 else 26
			if math.abs(lx) < side and lz > -92 and lz < 6 then
				table.insert(bad, `{p:GetFullName()} in pier {i}'s corridor`)
			end
		end
		local pos = p.CFrame.Position
		for _, a in cfg.BridgeAngles do
			local ux, uz = math.sin(math.rad(a)), math.cos(math.rad(a))
			local along = pos.X * ux + pos.Z * uz
			local across = math.abs(pos.X * uz - pos.Z * ux)
			if along > cfg.HubPlazaRadius and along < cfg.LagoonRadius + 8 and across < cfg.BridgeWidth / 2 + 1 then
				table.insert(bad, `{p:GetFullName()} on bridge {a}`)
			end
		end
	end
	t.eq(#bad, 0, `shore kit in the way: {table.concat(bad, ", ", 1, math.min(#bad, 6))}`)
end

tests["surf and wet-sand strips never overlap (no shimmering transparent / studded layers)"] = function(t)
	for _, name in { "Foam", "WetSand" } do
		local boxes = {}
		for _, d in map.Shore:GetDescendants() do
			if d:IsA("BasePart") and d.Name == name then
				local p, h = d.CFrame.Position, d.Size / 2
				table.insert(boxes, { p.X - h.X, p.Z - h.Z, p.X + h.X, p.Z + h.Z, d })
			end
		end
		local overlaps = {}
		for a = 1, #boxes do
			for b = a + 1, #boxes do
				local A, B = boxes[a], boxes[b]
				local w = math.min(A[3], B[3]) - math.max(A[1], B[1])
				local d = math.min(A[4], B[4]) - math.max(A[2], B[2])
				if w > 0.01 and d > 0.01 then
					table.insert(overlaps, `{A[5].CFrame.Position} / {B[5].CFrame.Position}`)
				end
			end
		end
		t.eq(#overlaps, 0, `{name} strips overlapping: {table.concat(overlaps, "; ", 1, math.min(#overlaps, 4))}`)
	end
end

tests["moving details: Sway / Bob / Spin / Pulse / Drift marks are well-formed and never nested"] = function(t)
	local MOVING = { "Sway", "Bob", "Spin", "Pulse", "Drift" }
	local function movingKind(inst: any): string?
		for _, a in MOVING do
			if typeof(inst:GetAttribute(a)) == "number" then
				return a
			end
		end
		return nil
	end
	local counts = { Sway = 0, Bob = 0, Spin = 0, Pulse = 0, Drift = 0 }
	local bad = {}
	for _, d in map:GetDescendants() do
		local kind = movingKind(d)
		if not kind then
			continue
		end
		counts[kind] += 1
		local name = d:GetFullName()
		-- (the Ferris wheel's gondolas keep upright inside the spinning wheel: KeepUpright)
		local up = d.Parent
		while up and up ~= map do
			local outer = movingKind(up)
			if outer and not (outer == "Spin" and kind == "Spin") then
				table.insert(bad, `{name} ({kind}) inside {up:GetFullName()} ({outer})`)
				break
			end
			up = up.Parent
		end
		if kind == "Sway" then
			local axis, period, amp = d:GetAttribute("SwayAxis"), d:GetAttribute("SwayPeriod"), d:GetAttribute("Sway")
			if
				not (axis == "X" or axis == "Y" or axis == "Z")
				or typeof(period) ~= "number"
				or amp <= 0
				or amp > 30
			then
				table.insert(bad, `{name}: Sway {amp} / {axis} / {period}`)
			end
			local primary = if d:IsA("BasePart") then d else d.PrimaryPart
			if not primary then
				table.insert(bad, `{name}: no pivot part`)
			end
		elseif kind == "Pulse" then
			if typeof(d:GetAttribute("PulsePeriod")) ~= "number" then
				table.insert(bad, `{name}: Pulse without PulsePeriod`)
			end
		elseif kind == "Drift" then
			if not d:IsDescendantOf(map.Sky) then
				table.insert(bad, `{name}: Drift outside Map.Sky`)
			end
		end
	end
	-- v3 fix F2: every part the client moves (any mark) neither collides nor takes raycasts or
	-- touches — the palms' trunks excepted (1.2° about their foot): Movers.quiet
	for _, d in map:GetDescendants() do
		if movingKind(d) and (d:IsA("Model") or d:IsA("BasePart")) then
			for _, p in (if d:IsA("BasePart") then { d } else d:GetDescendants()) do
				if p:IsA("BasePart") and (p.CanCollide or p.CanQuery or p.CanTouch) then
					if not Movers.isSolidTrunk(d, p) then
						table.insert(bad, `{p:GetFullName()}: solid / queryable but moves ({movingKind(d)})`)
					end
				end
			end
		end
	end
	t.eq(#bad, 0, `malformed moving details: {table.concat(bad, "; ", 1, math.min(#bad, 5))}`)
	-- the floats you can stand on stay still (a bob seen only on one client would carry a child)
	for _, d in map:GetDescendants() do
		if d.Name == "SwimPlatform" or d.Name == "Raft" or d.Name == "FishFarm" or d.Name == "Houseboat" then
			t.eq(d:GetAttribute("Bob"), nil, `{d:GetFullName()}: still (no Bob)`)
			for _, c in d:GetDescendants() do
				t.eq(c:GetAttribute("Bob"), nil, `{c:GetFullName()}: still (no Bob)`)
			end
		end
	end
	t.ok(counts.Sway >= 100, `swinging details: {counts.Sway}`)
	t.ok(counts.Bob >= 80, `bobbing models: {counts.Bob}`)
	t.ok(counts.Pulse >= 1 and counts.Drift >= 10, `pulse {counts.Pulse}, drifting clouds {counts.Drift}`)
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
	t.ok(trees >= 200, `forests on the hills ({trees} trees)`)
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
	for _, group in { map.Lagoon, map.Nature } do -- (Map.Shore: its own, finer test above)
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

tests["the peak's summit deck sits flush and centred on the carved flat summit"] = function(t)
	local site = world.landmarks.Peak
	local deck = nil
	for _, d in map:GetDescendants() do
		if d.Name == "SummitDeck" then
			deck = d
			break
		end
	end
	t.ok(deck ~= nil, "Landmarks has a SummitDeck")
	if not deck then
		return
	end
	-- (Lune has no Model:GetBoundingBox: measure the plank deck itself)
	local plank = deck:FindFirstChild("Deck")
	t.ok(plank ~= nil and plank:IsA("BasePart"), "SummitDeck has its Deck part")
	if not plank then
		return
	end
	local pos, size = plank.CFrame.Position, plank.Size
	local dx, dz = pos.X - site.x, pos.Z - site.z
	t.ok(math.sqrt(dx * dx + dz * dz) < 6, `deck centre {pos} within 6 studs of the summit centre`)
	local bottom = pos.Y - size.Y / 2
	t.ok(math.abs(bottom - site.summitTop) < 2, `deck bottom {bottom} within 2 studs of summitTop {site.summitTop}`)
end

return tests
