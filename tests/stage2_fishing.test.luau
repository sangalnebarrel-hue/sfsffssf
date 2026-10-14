--[[
	Stage 2 integration tests for the fishing server (FishingService), run inside RbxSim against
	the built Place1.rbxl: rod giving, cast checks, bite timing, hook, the minigame (hits, zone
	moves, misses, bogus taps, spam, timeout), the catch (FishData, counter, signal, the fish
	held above the head), every way a session ends, stale threads, two players, leaks.

	The tests drive the real server like a client would: sim:FireServer(...) with the
	FishingCast / FishingHook / FishingTap / FishingStop remotes, then read the FishingState
	events the server fired (sim:ClientEventsFor).

	Run: lune run tools/run_tests.luau stage2
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local PLACE = "Place1.rbxl"

-- Pure config modules are read straight from src/ (same values the game uses).
local function loadConfig(name: string): any
	local path = `src/ReplicatedStorage/Shared/Config/{name}.luau`
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum },
		injectGlobals = true,
	})
	return chunk()
end

local BaseConfig = loadConfig("BaseConfig")
local FishConfig = loadConfig("FishConfig")
local FishingConfig = loadConfig("FishingConfig")
local MapConfig = loadConfig("MapConfig")
local RodConfig = loadConfig("RodConfig")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local FRAME = 1 / 60
-- Larger sim steps for long waits where frame-exact timing is not checked (faster tests).
local COARSE = 0.05
local SERVICE_PATH = "ServerScriptService.Services.FishingService"

local function rodDef(id: string): any
	for _, rod in RodConfig.Rods do
		if rod.Id == id then
			return rod
		end
	end
	error(`no rod {id}`)
end

local START_ROD = rodDef(RodConfig.StartRod)

--------------------------------------------------------------------------------
-- Sim helpers
--------------------------------------------------------------------------------

-- Boots a sim; patches (optional) edit ModuleScript sources before the server starts.
local function boot(t: any, patches: { { path: string, from: string, to: string } }?): any
	local sim = t.sim({ place = PLACE })
	for _, patch in patches or {} do
		local module = sim:Find(patch.path)
		t.ok(module, `module {patch.path} exists`)
		local source = module.Source
		local start = string.find(source, patch.from, 1, true)
		t.ok(start, `patch anchor found in {patch.path}`)
		module.Source = string.sub(source, 1, start - 1) .. patch.to .. string.sub(source, start + #patch.from)
	end
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

local function addPlayer(sim: any, id: number): any
	local player = sim:AddPlayer({ UserId = id, Name = `Player{id}`, DisplayName = `Игрок{id}` })
	sim:Advance(0.5)
	return player
end

local function service(sim: any): any
	return sim:Require(sim:Find(SERVICE_PATH))
end

local function rules(sim: any): any
	return sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"))
end

local function baseOf(sim: any, player: any): any
	local index = player:GetAttribute("BaseIndex")
	if typeof(index) ~= "number" or index <= 0 then
		return nil
	end
	return sim.game:GetService("Workspace").Bases:FindFirstChild(`Base_{index}`)
end

local function spotOf(sim: any, player: any): any
	return baseOf(sim, player).FishingSpot
end

-- Every rod Tool the player has (Backpack + character).
local function rodsOf(player: any): { any }
	local found = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("RodId") ~= nil then
					table.insert(found, child)
				end
			end
		end
	end
	return found
end

local function equipRod(sim: any, player: any): any
	local rods = rodsOf(player)
	assert(#rods == 1, `expected one rod, got {#rods}`)
	return sim:EquipTool(player, rods[1])
end

-- Puts the character on the given spot part (root 3 studs above it), plus an offset.
local function standOn(sim: any, player: any, spot: any, offset: any?)
	sim:Teleport(player, spot.Position + Vector3.new(0, 3, 0) + (offset or Vector3.zero))
end

-- On its own fishing spot with the rod in hand, ready to cast.
local function ready(sim: any, player: any)
	standOn(sim, player, spotOf(sim, player))
	equipRod(sim, player)
end

local function stateEvents(sim: any, player: any): { any }
	return sim:ClientEventsFor(player, "FishingState")
end

local function lastState(sim: any, player: any): (string?, any, number?)
	local args, entry = sim:LastClientEvent(player, "FishingState")
	if not args then
		return nil, nil, nil
	end
	return args[1], args[2], entry.time
end

-- Waits for the next FishingState event after event number `from` (default: now).
-- step: frame length while waiting (coarser = faster, when exact timing does not matter).
local function nextState(sim: any, player: any, timeout: number?, from: number?, step: number?): (string?, any, number?)
	local start = from or #stateEvents(sim, player)
	local entry = sim:WaitFor(function()
		return stateEvents(sim, player)[start + 1]
	end, timeout or 10, step)
	if not entry then
		return nil, nil, nil
	end
	return entry.args[1], entry.args[2], entry.time
end

-- Names of the FishingState events after event number `from`.
local function statesSince(sim: any, player: any, from: number): { string }
	local names = {}
	local list = stateEvents(sim, player)
	for i = from + 1, #list do
		table.insert(names, list[i].args[1])
	end
	return names
end

local function cast(sim: any, player: any): (string?, any, number?)
	local count = #stateEvents(sim, player)
	sim:FireServer(player, "FishingCast")
	local events = stateEvents(sim, player)
	local entry = events[count + 1]
	if not entry then
		return nil, nil, nil
	end
	return entry.args[1], entry.args[2], entry.time
end

-- Casts and waits for the bite; returns the bite time.
local function castAndWaitBite(t: any, sim: any, player: any): number
	local name = cast(sim, player)
	t.eq(name, "Waiting", "cast accepted")
	local bite, _, biteTime = nextState(sim, player, 10, nil, COARSE)
	t.eq(bite, "Bite", "the fish bites")
	return biteTime :: number
end

-- Casts, waits for the bite, hooks: returns the "Minigame" payload and its server time.
local function startMinigame(t: any, sim: any, player: any): (any, number)
	castAndWaitBite(t, sim, player)
	local count = #stateEvents(sim, player)
	sim:FireServer(player, "FishingHook")
	local name, data, time = nextState(sim, player, 1, count)
	t.eq(name, "Minigame", "hook during the bite starts the minigame")
	return data, time :: number
end

-- First moment ≥ from when the needle is well inside (hit) / well outside (miss) the zone.
local function findMoment(sim: any, mg: any, center: number, from: number, wantHit: boolean): number
	local fr = rules(sim)
	local half = mg.ZoneWidth / 2
	local t = from
	while t < from + 8 do
		local d = math.abs(fr.Needle(mg.U0, mg.Speed, t) - center)
		if (wantHit and d <= half * 0.6) or (not wantHit and d >= half + 0.05) then
			return t
		end
		t += 0.005
	end
	error("no such moment")
end

-- Advances the sim until `elapsed` seconds of the minigame passed on the server, then taps
-- with that elapsed value (what an honest zero-latency client would send).
local function tapAt(sim: any, player: any, startTime: number, elapsed: number)
	local wait = startTime + elapsed - sim:Time()
	if wait > 0 then
		sim:Advance(wait)
	end
	sim:FireServer(player, "FishingTap", elapsed)
end

-- Plays the minigame to the end with perfect taps; returns the final event and the list of
-- "Zone" payloads seen on the way.
local function winMinigame(sim: any, player: any, mg: any, startTime: number): (string?, any, { any })
	local center = mg.ZoneCenter
	local from = FishingConfig.TapInterval + 0.02
	local zones = {}
	for _ = 1, mg.HitsNeeded do
		local moment = findMoment(sim, mg, center, from, true)
		local count = #stateEvents(sim, player)
		tapAt(sim, player, startTime, moment)
		local name, data = nextState(sim, player, 0.1, count)
		if name ~= "Zone" then
			return name, data, zones
		end
		table.insert(zones, { data = data, at = moment })
		center = data.ZoneCenter
		from = moment + FishingConfig.TapInterval + 0.02
	end
	error(`no catch after {mg.HitsNeeded} hits`)
end

-- Test-only hook of FishingService: the next rolls give this fish.
local function forceFish(sim: any, id: string, mutation: string?, kg: number?): any
	local fr = rules(sim)
	local def = fr.GetFish(id)
	local weight = kg or def.MinKg
	local value, income = fr.Price(id, weight, mutation)
	local fish = { Id = id, Rarity = def.Rarity, Mutation = mutation, Kg = weight, Value = value, Income = income }
	service(sim).RollFishForTest = function()
		return table.clone(fish)
	end
	return fish
end

local function notifyTexts(sim: any, player: any): { string }
	local texts = {}
	for _, event in sim:ClientEventsFor(player, "Notify") do
		table.insert(texts, event.args[1])
	end
	return texts
end

local function horizontal(v: any): any
	return Vector3.new(v.X, 0, v.Z)
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

local tests = {}

tests["rod: exactly one start rod in the Backpack on spawn, player attributes set"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	sim:Advance(1)
	local rods = rodsOf(p)
	t.eq(#rods, 1, "exactly one rod")
	local rod = rods[1]
	local template = sim:Find(`ReplicatedStorage.Assets.Rods.{RodConfig.StartRod}`)
	t.eq(rod.Parent, p:FindFirstChildOfClass("Backpack"), "in the Backpack")
	t.eq(rod:GetAttribute("RodId"), RodConfig.StartRod)
	t.eq(rod.Name, template:GetAttribute("DisplayName"), "named by its DisplayName")
	t.eq(rod.Name, START_ROD.Name)
	t.ok(rod.Handle:FindFirstChild("TipAttachment"), "a real copy of the asset")
	t.eq(p:GetAttribute("RodId"), RodConfig.StartRod)
	t.eq(p:GetAttribute("FishingState"), "Idle")
	t.eq(p:GetAttribute("FishCaught"), 0)
	t.eq(service(sim):GetRodId(p), RodConfig.StartRod)
	sim:AssertNoErrors()
end

tests["rod: given again after respawn, never duplicated"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local first = rodsOf(p)[1]
	equipRod(sim, p)
	local oldCharacter = p.Character
	sim:KillCharacter(p)
	sim:Advance(BaseConfig.RespawnDelay + 1)
	t.ok(p.Character ~= oldCharacter, "respawned")
	local rods = rodsOf(p)
	t.eq(#rods, 1, "one rod after respawn")
	t.ok(rods[1] ~= first, "a fresh copy")
	t.eq(rods[1].Parent, p:FindFirstChildOfClass("Backpack"))

	-- Several respawns in a row (BaseService API) still leave exactly one rod.
	local BaseService = sim:Require(sim:Find("ServerScriptService.Services.BaseService"))
	for _ = 1, 3 do
		sim:Run(function()
			BaseService:RespawnPlayer(p)
		end)
		sim:Advance(0.3)
	end
	t.eq(#rodsOf(p), 1, "one rod after repeated respawns")
	sim:AssertNoErrors()
end

tests["rod: SetRod swaps the tool (kept in hand), unknown rods are refused"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local fishing = service(sim)
	local ok = sim:Run(function()
		return fishing:SetRod(p, "RodSea")
	end)
	t.eq(ok, true, "SetRod accepted")
	local rods = rodsOf(p)
	t.eq(#rods, 1, "still exactly one rod")
	t.eq(rods[1]:GetAttribute("RodId"), "RodSea")
	t.eq(rods[1].Name, rodDef("RodSea").Name)
	t.eq(rods[1].Parent, p.Character, "the new rod is in hand (the old one was)")
	t.eq(p:GetAttribute("RodId"), "RodSea")
	t.eq(fishing:GetRodId(p), "RodSea")

	local bad = sim:Run(function()
		return fishing:SetRod(p, "RodNope")
	end)
	t.eq(bad, false, "unknown rod refused")
	t.eq(p:GetAttribute("RodId"), "RodSea")

	-- The new rod casts farther.
	local name, data = cast(sim, p)
	t.eq(name, "Waiting")
	local distance = horizontal(data.Target - spotOf(sim, p).Position).Magnitude
	t.ok(math.abs(distance - rodDef("RodSea").CastDistance) <= 3.5, `RodSea cast distance {distance}`)

	-- Changing the rod mid-cast ends the session.
	sim:Run(function()
		fishing:SetRod(p, RodConfig.StartRod)
	end)
	local idle, idleData = lastState(sim, p)
	t.eq(idle, "Idle")
	t.eq(idleData.Reason, "unequipped")
	t.eq(#rodsOf(p), 1)
	sim:AssertNoErrors()
end

tests["cast denied: far from the spot, rod not equipped, standing on someone else's spot"] = function(t)
	local sim = boot(t)
	local a = addPlayer(sim, 1)
	local b = addPlayer(sim, 2)

	-- Rod in hand, but at the spawn pad.
	equipRod(sim, a)
	local name, data = cast(sim, a)
	t.eq(name, "Denied")
	t.eq(data.Reason, "far")
	t.ok(#data.Text > 0, "far: a hint text")
	t.eq(a:GetAttribute("FishingState"), "Idle")

	-- On the spot, but just outside SpotRadius.
	standOn(sim, a, spotOf(sim, a), Vector3.new(FishingConfig.SpotRadius + 1, 0, 0))
	name, data = cast(sim, a)
	t.eq(data.Reason, "far", "outside SpotRadius")
	-- Too high above the spot.
	standOn(sim, a, spotOf(sim, a), Vector3.new(0, FishingConfig.SpotMaxHeight + 2, 0))
	name, data = cast(sim, a)
	t.eq(data.Reason, "far", "above SpotMaxHeight")

	-- On the spot without the rod in hand.
	sim:UnequipTools(a)
	standOn(sim, a, spotOf(sim, a))
	name, data = cast(sim, a)
	t.eq(name, "Denied")
	t.eq(data.Reason, "norod")
	t.ok(#data.Text > 0, "norod: a hint text")

	-- Someone else's fishing spot with the rod in hand.
	equipRod(sim, a)
	standOn(sim, a, spotOf(sim, b))
	name, data = cast(sim, a)
	t.eq(name, "Denied")
	t.eq(data.Reason, "far", "another player's spot does not count")
	t.eq(a:GetAttribute("FishingState"), "Idle")

	-- A rod Tool that is not the one the server gave does not count either.
	sim:UnequipTools(a)
	local fake = sim:Find(`ReplicatedStorage.Assets.Rods.{RodConfig.StartRod}`):Clone()
	fake.Parent = a.Character
	sim:Flush()
	standOn(sim, a, spotOf(sim, a))
	name, data = cast(sim, a)
	t.eq(data.Reason, "norod", "a cloned rod is not the given one")
	sim:AssertNoErrors()
end

tests["cast denied: no base (waiting in the queue)"] = function(t)
	local sim = boot(t, {
		{
			path = "ReplicatedStorage.Shared.Config.BaseConfig",
			from = "MaxBases = nil :: number?",
			to = "MaxBases = 1 :: number?",
		},
	})
	addPlayer(sim, 1)
	local waiting = addPlayer(sim, 2)
	t.eq(waiting:GetAttribute("BaseIndex"), 0, "second player waits for a base")
	t.eq(#rodsOf(waiting), 1, "still gets a rod")
	equipRod(sim, waiting)
	local name, data = cast(sim, waiting)
	t.eq(name, "Denied")
	t.eq(data.Reason, "nobase")
	t.ok(#data.Text > 0, "nobase: a hint text")
	sim:AssertNoErrors()
end

tests["cast denied: busy while fishing, cooldown right after a session ends"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	t.eq((cast(sim, p)), "Waiting")
	local name, data = cast(sim, p)
	t.eq(name, "Denied")
	t.eq(data.Reason, "busy")
	t.eq(p:GetAttribute("FishingState"), "Waiting", "the session goes on")

	sim:FireServer(p, "FishingStop")
	name, data = lastState(sim, p)
	t.eq(name, "Idle")
	t.eq(data.Reason, "stop")
	name, data = cast(sim, p)
	t.eq(name, "Denied")
	t.eq(data.Reason, "cooldown")
	t.eq(typeof(data.Text), "string")
	sim:Advance(FishingConfig.CastCooldown * 0.5)
	t.eq((select(2, cast(sim, p))).Reason, "cooldown", "still cooling down")
	sim:Advance(FishingConfig.CastCooldown * 0.5 + 0.05)
	t.eq((cast(sim, p)), "Waiting", "accepted after CastCooldown")
	sim:AssertNoErrors()
end

tests["cast accepted: attributes, target in the water out from the pier, a little to the right"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local base = baseOf(sim, p)
	local pivot = base:GetPivot()
	local spot = base.FishingSpot.Position
	local spotLocal = pivot:PointToObjectSpace(spot)
	local sides = {}
	-- Sim quirk (Lune): a whole-number attribute value is stored with float32 precision
	-- (1700000001 → 1700000000), fractional ones are exact. Keep the server clock off whole
	-- seconds so CastTime can be compared exactly (Roblox keeps attributes as doubles).
	sim:Advance(0.25)
	for i = 1, 12 do
		local name, data, time = cast(sim, p)
		t.eq(name, "Waiting", `cast {i} accepted`)
		t.eq(data.FlightTime, FishingConfig.CastFlightTime)
		local target = data.Target
		t.eq(typeof(target), "Vector3")
		t.near(target.Y, MapConfig.WaterTop, 1e-6, "on the water surface")
		local distance = horizontal(target - spot).Magnitude
		t.ok(
			distance >= START_ROD.CastDistance - 1e-3 and distance <= START_ROD.CastDistance + 3.5,
			`horizontal distance {distance} ≈ CastDistance`
		)
		local localTarget = pivot:PointToObjectSpace(target)
		local side = localTarget.X - spotLocal.X
		-- To the fisher's right (+X of the base when looking out to -Z): the camera behind the
		-- fisher sees the bobber right of the head, not behind it (FishingConfig.CastSide).
		t.ok(
			side >= FishingConfig.CastSide.Min - 1e-3 and side <= FishingConfig.CastSide.Max + 1e-3,
			`to the right by CastSide ({side})`
		)
		t.near(localTarget.Z, spotLocal.Z - START_ROD.CastDistance, 1e-3, "out from the pier (-Z of the base)")
		table.insert(sides, side)

		t.eq(p:GetAttribute("FishingState"), "Waiting")
		-- attributes keep Vector3 as float32
		t.near(p:GetAttribute("BobberTarget"), target, 1e-3, "BobberTarget attribute")
		-- CastTime = the moment the float leaves the rod tip: the cast + CastWindUp (the wind-up
		-- every client shows, FisherAnimController).
		local castTime = p:GetAttribute("CastTime")
		local now = sim.workspace:GetServerTimeNow()
		t.ok(
			typeof(castTime) == "number" and math.abs(now + FishingConfig.CastWindUp - castTime) < 1e-6,
			string.format("CastTime %.4f = server time of the cast %.4f + CastWindUp", castTime, now)
		)
		t.eq(data.WindUp, FishingConfig.CastWindUp, "the Waiting payload carries WindUp")
		t.eq(time, sim:Time())

		sim:FireServer(p, "FishingStop")
		sim:Advance(FishingConfig.CastCooldown + 0.05)
	end
	table.sort(sides)
	t.ok(sides[#sides] - sides[1] > 1, "random sideways offset")
	sim:AssertNoErrors()
end

tests["bite: arrives within WindUp + FlightTime + BiteDelay / BiteSpeed"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local lo = FishingConfig.CastWindUp
		+ FishingConfig.CastFlightTime
		+ FishingConfig.BiteDelay.Min / START_ROD.BiteSpeed
	local hi = FishingConfig.CastWindUp
		+ FishingConfig.CastFlightTime
		+ FishingConfig.BiteDelay.Max / START_ROD.BiteSpeed
	local delays = {}
	for i = 1, 6 do
		local _, _, castTime = cast(sim, p)
		local name, data, biteTime = nextState(sim, p, hi + 1, nil, COARSE)
		t.eq(name, "Bite", `bite {i}`)
		t.eq(data.Window, FishingConfig.BiteWindow)
		t.eq(p:GetAttribute("FishingState"), "Bite")
		local delay = biteTime - castTime
		t.ok(delay >= lo - 1e-6 and delay <= hi + COARSE + 1e-6, `bite after {delay} s (expected {lo}..{hi})`)
		table.insert(delays, delay)
		sim:FireServer(p, "FishingStop")
		sim:Advance(FishingConfig.CastCooldown + 0.05)
	end
	table.sort(delays)
	t.ok(delays[#delays] - delays[1] > 0.2, "random bite delays")
	sim:AssertNoErrors()
end

tests["hook: late (after BiteWindow + LatencyGrace) loses the fish"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local biteTime = castAndWaitBite(t, sim, p)
	local name, data, lostTime = nextState(sim, p, 5)
	t.eq(name, "Lost")
	t.eq(data.Reason, "late")
	t.ok(#data.Text > 0, "a text for the player")
	local window = FishingConfig.BiteWindow + FishingConfig.LatencyGrace
	t.ok(math.abs(lostTime - biteTime - window) <= 2 * FRAME, `lost {lostTime - biteTime} s after the bite`)
	t.eq(p:GetAttribute("FishingState"), "Idle")
	-- A hook arriving now does nothing.
	local count = #stateEvents(sim, p)
	sim:FireServer(p, "FishingHook")
	sim:Advance(0.2)
	t.eq(#stateEvents(sim, p), count, "late hook ignored")
	sim:AssertNoErrors()
end

tests["hook: within LatencyGrace after the window still counts"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	castAndWaitBite(t, sim, p)
	sim:Advance(FishingConfig.BiteWindow + FishingConfig.LatencyGrace * 0.5)
	sim:FireServer(p, "FishingHook")
	t.eq((lastState(sim, p)), "Minigame", "hook during the grace period accepted")
	sim:AssertNoErrors()
end

tests["hook: early (before the bite) scares the fish"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	t.eq((cast(sim, p)), "Waiting")
	sim:Advance(1)
	sim:FireServer(p, "FishingHook")
	local name, data = lastState(sim, p)
	t.eq(name, "Lost")
	t.eq(data.Reason, "early")
	t.ok(#data.Text > 0)
	t.eq(p:GetAttribute("FishingState"), "Idle")
	sim:Advance(8, COARSE)
	t.eq((lastState(sim, p)), "Lost", "no bite after the session ended")
	sim:AssertNoErrors()
end

tests["minigame: payload follows the rules, perfect taps catch the fish"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local other = addPlayer(sim, 2)
	local fr = rules(sim)
	local fishing = service(sim)
	local signalled = {}
	fishing.FishCaught:Connect(function(player, fish)
		table.insert(signalled, { player = player, fish = fish })
	end)
	ready(sim, p)

	local mg, startTime = startMinigame(t, sim, p)
	t.eq(p:GetAttribute("FishingState"), "Reeling")
	local rule = FishingConfig.Minigame[mg.Rarity]
	t.ok(rule ~= nil, `known rarity {mg.Rarity}`)
	t.eq(mg.Speed, rule.Speed)
	t.eq(mg.HitsNeeded, rule.Hits)
	t.eq(mg.Hits, 0)
	t.eq(mg.Timeout, FishingConfig.MinigameTimeout)
	t.near(mg.ZoneWidth, fr.ZoneWidth(mg.Rarity, RodConfig.StartRod), 1e-9)
	t.ok(mg.U0 >= 0 and mg.U0 <= 2, "U0 in 0..2")
	local lo = mg.ZoneWidth / 2 + FishingConfig.ZoneMargin
	t.ok(mg.ZoneCenter >= lo - 1e-9 and mg.ZoneCenter <= 1 - lo + 1e-9, "zone fully on the bar")
	t.ok(
		not fr.IsHit(fr.Needle(mg.U0, mg.Speed, 0), mg.ZoneCenter, mg.ZoneWidth),
		"the needle does not start inside the zone"
	)

	local name, data = winMinigame(sim, p, mg, startTime)
	t.eq(name, "Caught")
	local fish = data.Fish
	local def = fr.GetFish(fish.Id)
	t.ok(def ~= nil, `fish {fish.Id} is in FishConfig`)
	t.eq(fish.Rarity, def.Rarity)
	t.eq(fish.Rarity, mg.Rarity, "the rolled rarity matches the minigame")
	t.ok(fish.Kg >= def.MinKg and fish.Kg <= def.MaxKg, "weight in range")
	t.ok(fish.Mutation == nil or fr.GetMutation(fish.Mutation) ~= nil, "valid mutation")
	local value, income = fr.Price(fish.Id, fish.Kg, fish.Mutation)
	t.eq(fish.Value, value, "Value == FishingRules.Price")
	t.eq(fish.Income, income, "Income == FishingRules.Price")
	t.eq(data.Total, 1)
	t.eq(p:GetAttribute("FishCaught"), 1)
	t.eq(p:GetAttribute("FishingState"), "Idle")

	local catch = fishing:GetCatch(p)
	t.eq(#catch, 1, "in this session's catch")
	t.eq(catch[1].Id, fish.Id)
	sim:Flush()
	t.eq(#signalled, 1, "FishCaught signal fired once")
	t.eq(signalled[1].player, p)
	t.eq(signalled[1].fish.Id, fish.Id)
	t.eq(#stateEvents(sim, other), 0, "nothing sent to the other player")

	-- The next cast works after the cooldown, the counter keeps counting.
	sim:Advance(FishingConfig.CastCooldown + 0.05)
	local mg2, start2 = startMinigame(t, sim, p)
	local name2, data2 = winMinigame(sim, p, mg2, start2)
	t.eq(name2, "Caught")
	t.eq(data2.Total, 2)
	t.eq(p:GetAttribute("FishCaught"), 2)
	t.eq(#fishing:GetCatch(p), 2)
	sim:AssertNoErrors()
end

tests["minigame: a Mythic fish needs 3 hits, the zone jumps away from the needle, the others hear"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local other = addPlayer(sim, 2)
	local fr = rules(sim)
	local forced = forceFish(sim, "DragonFish", nil, 9.5)
	ready(sim, p)

	local mg, startTime = startMinigame(t, sim, p)
	t.eq(mg.Rarity, "Mythic")
	t.eq(mg.HitsNeeded, FishingConfig.Minigame.Mythic.Hits)
	t.eq(mg.HitsNeeded, 3)
	local name, data, zones = winMinigame(sim, p, mg, startTime)
	t.eq(#zones, 2, "two zone moves before the catch")
	for i, zone in zones do
		t.eq(zone.data.Hits, i, `hit {i} counted`)
		local needle = fr.Needle(mg.U0, mg.Speed, zone.at)
		local lo = mg.ZoneWidth / 2 + FishingConfig.ZoneMargin
		local jump = math.abs(zone.data.ZoneCenter - needle)
		t.ok(
			jump >= FishingConfig.MinZoneJump - 1e-9 or zone.data.ZoneCenter == lo or zone.data.ZoneCenter == 1 - lo,
			`zone {i} moved away from the needle ({jump})`
		)
	end
	t.eq(name, "Caught")
	t.eq(data.Fish.Id, "DragonFish")
	t.eq(data.Fish.Value, forced.Value)

	local function heard(player: any): boolean
		for _, text in notifyTexts(sim, player) do
			if string.find(text, "Рыба-дракон", 1, true) and string.find(text, "Игрок1", 1, true) then
				return true
			end
		end
		return false
	end
	-- UI v2 (WFX-7): the broadcast lands with the pillar — when the fish has leapt (LeapTime).
	t.ok(not heard(other), "not yet: the fish is still in the air")
	sim:Advance(FishingConfig.LeapTime + 0.1)
	t.ok(heard(other), "the other player was told about the Mythic catch")
	t.ok(not heard(p), "not the fisher: their catch card shows it (a toast would cover the card)")
	-- «Игрок1 (Лазурная база): мифическая рыба «Рыба-дракон»!» in the Mythic toast style (kind =
	-- the rarity id); the client splits it at the first ": " (who / what).
	local base = p:GetAttribute("BaseColorName")
	t.ok(typeof(base) == "string" and base ~= "", "the fisher has a base")
	local args = sim:LastClientEvent(other, "Notify")
	t.eq(
		args[1],
		`Игрок1 ({base} база): мифическая рыба «Рыба-дракон»!`,
		"who (and where: the base), lower-case rarity (NameLower), the fish in «ёлочки»"
	)
	t.eq(args[2], "Mythic", "kind = the rarity id (NotifyController draws it in the rarity's colours)")
	sim:AssertNoErrors()
end

tests["announce: a mutated Legendary catch names the mutation and its multiplier"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local other = addPlayer(sim, 2)
	forceFish(sim, "SharkPup", "Gold")
	ready(sim, p)
	local mg, startTime = startMinigame(t, sim, p)
	t.eq((winMinigame(sim, p, mg, startTime)), "Caught")
	sim:Advance(FishingConfig.LeapTime + 0.1)
	local args = sim:LastClientEvent(other, "Notify")
	-- Both adjectives agree with «рыба» (not with the fish's own name).
	t.eq(
		args[1],
		`Игрок1 ({p:GetAttribute("BaseColorName")} база): легендарная золотая рыба «Акулёнок» ×2!`
	)
	t.eq(args[2], "Legendary")
	for _, rarity in FishConfig.Rarities do
		t.ok(typeof(rarity.NameLower) == "string" and #rarity.NameLower > 0, `{rarity.Id}: NameLower`)
	end
	for _, mutation in FishConfig.Mutations do
		t.ok(typeof(mutation.NameLower) == "string" and #mutation.NameLower > 0, `{mutation.Id}: NameLower`)
	end
	sim:AssertNoErrors()
end

tests["announce: a fisher who leaves before the fish lands is not announced"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local other = addPlayer(sim, 2)
	forceFish(sim, "SharkPup")
	ready(sim, p)
	local before = #notifyTexts(sim, other)
	local mg, startTime = startMinigame(t, sim, p)
	t.eq((winMinigame(sim, p, mg, startTime)), "Caught")
	sim:RemovePlayer(p)
	sim:Advance(FishingConfig.LeapTime + 0.3)
	t.eq(#notifyTexts(sim, other), before, "no broadcast about someone who has gone")
	sim:AssertNoErrors()
end

tests["minigame: a common catch is not announced"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local other = addPlayer(sim, 2)
	forceFish(sim, "Crucian")
	ready(sim, p)
	local before = #notifyTexts(sim, other)
	local mg, startTime = startMinigame(t, sim, p)
	t.eq((winMinigame(sim, p, mg, startTime)), "Caught")
	sim:Advance(FishingConfig.LeapTime + 0.1)
	t.eq(#notifyTexts(sim, other), before, "no broadcast")
	sim:AssertNoErrors()
end

tests["minigame: a tap at a miss moment loses the fish"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	forceFish(sim, "Swordfish") -- Epic: 2 hits
	ready(sim, p)
	local mg, startTime = startMinigame(t, sim, p)
	local miss = findMoment(sim, mg, mg.ZoneCenter, FishingConfig.TapInterval + 0.05, false)
	tapAt(sim, p, startTime, miss)
	local name, data = lastState(sim, p)
	t.eq(name, "Lost")
	t.eq(data.Reason, "miss")
	t.ok(#data.Text > 0)
	t.eq(p:GetAttribute("FishingState"), "Idle")
	t.eq(p:GetAttribute("FishCaught"), 0)
	t.eq(#service(sim):GetCatch(p), 0)
	sim:AssertNoErrors()
end

tests["minigame: a miss after a hit (zone moved) loses the fish"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	forceFish(sim, "Swordfish")
	ready(sim, p)
	local mg, startTime = startMinigame(t, sim, p)
	local hit = findMoment(sim, mg, mg.ZoneCenter, FishingConfig.TapInterval + 0.02, true)
	tapAt(sim, p, startTime, hit)
	local name, zone = lastState(sim, p)
	t.eq(name, "Zone")
	-- Tapping again at a moment that would have hit the OLD zone but misses the new one.
	local miss = findMoment(sim, mg, zone.ZoneCenter, hit + FishingConfig.TapInterval + 0.02, false)
	tapAt(sim, p, startTime, miss)
	local lost, data = lastState(sim, p)
	t.eq(lost, "Lost")
	t.eq(data.Reason, "miss")
	sim:AssertNoErrors()
end

tests["minigame: bogus taps never count as a hit and never error"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	forceFish(sim, "Swordfish")
	ready(sim, p)
	local mg, startTime = startMinigame(t, sim, p)
	local fr = rules(sim)
	-- Wait until the needle sits in the zone right NOW (so a clamped "huge" tap would hit).
	local hit = findMoment(sim, mg, mg.ZoneCenter, FishingConfig.TapInterval + 0.02, true)
	sim:Advance(startTime + hit - sim:Time())
	t.ok(fr.IsHit(fr.Needle(mg.U0, mg.Speed, hit), mg.ZoneCenter, mg.ZoneWidth), "needle in the zone now")
	local count = #stateEvents(sim, p)
	local bogus = {
		"abc",
		tostring(hit),
		true,
		{ hit },
		0 / 0,
		math.huge,
		-math.huge,
		1e12,
		-1,
		-hit,
		hit + 1, -- from the future
		hit + 0.5,
	}
	for _, value in bogus do
		sim:FireServer(p, "FishingTap", value)
	end
	sim:FireServer(p, "FishingTap") -- no argument at all
	sim:Advance(FRAME)
	t.eq(#stateEvents(sim, p), count, "no Zone / Caught / Lost from bogus taps")
	t.eq(p:GetAttribute("FishingState"), "Reeling")

	-- A real tap right after still counts (bogus taps did not use up the tap interval).
	sim:FireServer(p, "FishingTap", sim:Time() - startTime)
	local name, data = lastState(sim, p)
	t.eq(name, "Zone")
	t.eq(data.Hits, 1)
	sim:AssertNoErrors()
end

tests["minigame: tap spam is limited (one tap per TapInterval)"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	forceFish(sim, "Swordfish")
	ready(sim, p)
	local mg, startTime = startMinigame(t, sim, p)
	local hit = findMoment(sim, mg, mg.ZoneCenter, FishingConfig.TapInterval + 0.02, true)
	sim:Advance(startTime + hit - sim:Time())
	local count = #stateEvents(sim, p)
	for _ = 1, 8 do
		sim:FireServer(p, "FishingTap", hit)
	end
	local names = statesSince(sim, p, count)
	t.eq(#names, 1, "one answer to 8 taps in a frame")
	t.eq(names[1], "Zone")
	t.eq((select(2, lastState(sim, p))).Hits, 1, "counted once")
	t.eq(p:GetAttribute("FishingState"), "Reeling")

	-- Spam a few frames later (still inside TapInterval) is ignored too, even at a miss moment.
	sim:Advance(FishingConfig.TapInterval * 0.5)
	sim:FireServer(p, "FishingTap", sim:Time() - startTime)
	t.eq(#statesSince(sim, p, count), 1, "tap inside TapInterval ignored")
	sim:AssertNoErrors()
end

tests["minigame: taps right after the hook are ignored, not misses"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	forceFish(sim, "Crucian")
	ready(sim, p)
	local _, startTime = startMinigame(t, sim, p)
	local count = #stateEvents(sim, p)
	sim:FireServer(p, "FishingTap", 0) -- accidental double press
	sim:Advance(FishingConfig.TapInterval * 0.5)
	sim:FireServer(p, "FishingTap", sim:Time() - startTime)
	t.eq(#stateEvents(sim, p), count, "ignored")
	t.eq(p:GetAttribute("FishingState"), "Reeling")
	sim:AssertNoErrors()
end

tests["minigame: no taps until MinigameTimeout loses the fish"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local _, startTime = startMinigame(t, sim, p)
	local name, data, time = nextState(sim, p, FishingConfig.MinigameTimeout + 2, nil, COARSE)
	t.eq(name, "Lost")
	t.eq(data.Reason, "timeout")
	local expected = FishingConfig.MinigameTimeout + FishingConfig.LatencyGrace
	t.ok(math.abs(time - startTime - expected) <= COARSE + 1e-6, `timeout after {time - startTime} s`)
	t.eq(p:GetAttribute("FishingState"), "Idle")
	sim:AssertNoErrors()
end

tests["minigame: hook / cast during the minigame change nothing; Stop ends it"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	startMinigame(t, sim, p)
	local count = #stateEvents(sim, p)
	sim:FireServer(p, "FishingHook")
	t.eq(#stateEvents(sim, p), count, "hook ignored")
	local name, data = cast(sim, p)
	t.eq(name, "Denied")
	t.eq(data.Reason, "busy")
	sim:FireServer(p, "FishingStop")
	name, data = lastState(sim, p)
	t.eq(name, "Idle")
	t.eq(data.Reason, "stop")
	t.eq(p:GetAttribute("FishingState"), "Idle")
	sim:AssertNoErrors()
end

tests["caught: after LeapTime the fish is held above the head, welded, removed after HoldFishTime"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local fish = forceFish(sim, "Perch", "Gold", 1)
	ready(sim, p)
	local mg, startTime = startMinigame(t, sim, p)
	local name = winMinigame(sim, p, mg, startTime)
	local landedAt = sim:Time() + FishingConfig.LeapTime
	t.eq(name, "Caught")
	local character = p.Character
	-- The fish leaps from the water to the fisher first (clients draw it, FishingConfig.LeapTime);
	-- the server hangs it above the head when it lands.
	t.eq(character:FindFirstChild("HeldFish"), nil, "not above the head while the fish is in the air")
	sim:Advance(FishingConfig.LeapTime - 0.05)
	t.eq(character:FindFirstChild("HeldFish"), nil, "still in the air just before LeapTime")
	sim:Advance(0.1)
	local held = character:FindFirstChild("HeldFish")
	t.ok(held and held:IsA("Model"), "HeldFish model in the character")
	t.ok(held:IsDescendantOf(sim.workspace), "server-side in the Workspace: every client sees it")
	t.eq(held:GetAttribute("Mutation"), "Gold", "the Gold variant of the model")
	t.eq(held:GetAttribute("Kind"), sim:Find("ReplicatedStorage.Assets.Fish.Perch.Gold"):GetAttribute("Kind"))
	-- The FishData for nameplates above it (FishingFxController).
	t.eq(held:GetAttribute("FishId"), "Perch")
	t.eq(held:GetAttribute("Rarity"), "Common")
	t.eq(held:GetAttribute("Kg"), fish.Kg)
	t.eq(held:GetAttribute("Value"), fish.Value)
	local head = character.Head
	local body = held.PrimaryPart
	t.ok(body, "has a PrimaryPart")
	local headWeld
	for _, d in held:GetDescendants() do
		if d:IsA("BasePart") then
			t.eq(d.Anchored, false, `{d.Name} unanchored`)
			t.eq(d.Massless, true, `{d.Name} massless`)
			t.ok(not d.CanCollide and not d.CanQuery and not d.CanTouch, `{d.Name} no collisions`)
			if d ~= body then
				local joined = false
				for _, w in d:GetChildren() do
					if w:IsA("Weld") and w.Part0 == body and w.Part1 == d then
						joined = true
						t.near(body.CFrame * w.C0, d.CFrame, 1e-3, `{d.Name} weld C0 matches`)
					end
				end
				t.ok(joined, `{d.Name} welded to the body`)
			end
		elseif d:IsA("Weld") and d.Part0 == head then
			headWeld = d
		end
	end
	t.ok(headWeld, "the body is welded to the head")
	t.eq(headWeld.Part1, body)
	t.near(head.CFrame * headWeld.C0, body.CFrame, 1e-3, "head weld C0 matches the placement")
	local boxCFrame, boxSize = held:GetBoundingBox()
	local bottom = boxCFrame.Position.Y - boxSize.Y / 2
	t.ok(bottom >= head.Position.Y + head.Size.Y / 2 - 0.05, "above the head")
	t.ok(bottom <= head.Position.Y + head.Size.Y / 2 + 2, "close above the head")
	t.near(horizontal(boxCFrame.Position - head.Position).Magnitude, 0, 0.05, "centred over the head")

	local hold = rules(sim).HoldFishTime("Common")
	t.eq(hold, FishingConfig.HoldFishTime.Common, "FishingRules.HoldFishTime reads FishingConfig")
	sim:Advance(hold - (sim:Time() - landedAt) - 0.1)
	t.ok(character:FindFirstChild("HeldFish"), "still held just before HoldFishTime.Common")
	sim:Advance(0.2)
	t.eq(character:FindFirstChild("HeldFish"), nil, "removed after HoldFishTime.Common")
	sim:AssertNoErrors()
end

tests["caught: rarer fish are held longer (HoldFishTime per rarity)"] = function(t)
	local sim = boot(t)
	local fr = rules(sim)
	local last = 0
	for _, rarity in FishConfig.Rarities do
		local hold = fr.HoldFishTime(rarity.Id)
		t.eq(hold, FishingConfig.HoldFishTime[rarity.Id], `{rarity.Id}: {hold} s`)
		t.ok(hold >= last, "never shorter for a rarer fish")
		last = hold
	end
	t.eq(fr.HoldFishTime("Nope"), FishingConfig.HoldFishTime.Common, "unknown rarity: as Common")
	t.eq(fr.FormatCoins(7), "7")
	t.eq(fr.FormatCoins(2083), "2\u{00A0}083", "thousands split by a no-break space")
	t.eq(fr.FormatCoins(1234567.4), "1\u{00A0}234\u{00A0}567")

	local p = addPlayer(sim, 1)
	forceFish(sim, "DragonFish")
	ready(sim, p)
	local mg, startTime = startMinigame(t, sim, p)
	t.eq((winMinigame(sim, p, mg, startTime)), "Caught")
	local landedAt = sim:Time() + FishingConfig.LeapTime
	local character = p.Character
	sim:Advance(landedAt + FishingConfig.HoldFishTime.Mythic - 0.1 - sim:Time(), COARSE)
	t.ok(character:FindFirstChild("HeldFish"), "a Mythic fish is still held just before HoldFishTime.Mythic")
	sim:Advance(0.2)
	t.eq(character:FindFirstChild("HeldFish"), nil, "…and removed after it")
	sim:AssertNoErrors()
end

tests["session ends: walking beyond KeepRadius (but not inside it)"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	t.eq((cast(sim, p)), "Waiting")
	local spot = spotOf(sim, p)
	-- Beyond SpotRadius but inside KeepRadius: the line stays.
	standOn(sim, p, spot, Vector3.new(FishingConfig.SpotRadius + 2, 0, 0))
	sim:Advance(0.5)
	t.eq(p:GetAttribute("FishingState"), "Waiting", "still fishing inside KeepRadius")
	standOn(sim, p, spot, Vector3.new(0, 0, FishingConfig.KeepRadius + 1))
	local name, data = nextState(sim, p, 0.5)
	t.eq(name, "Idle")
	t.eq(data.Reason, "moved")
	t.eq(p:GetAttribute("FishingState"), "Idle")
	sim:AssertNoErrors()
end

tests["session ends: unequipping the rod (at once by Tool.Unequipped, also on a hook)"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	castAndWaitBite(t, sim, p)
	sim:UnequipTools(p)
	sim:Advance(FRAME) -- the same frame: no waiting for the 0.2 s watcher
	local name, data = lastState(sim, p)
	t.eq(name, "Idle")
	t.eq(data.Reason, "unequipped")
	t.eq(p:GetAttribute("FishingState"), "Idle")

	-- Unequip and re-equip before the watcher could notice: the session still ends (the
	-- client resets its UI on unequip, so the server must not keep the line out).
	sim:Advance(FishingConfig.CastCooldown + 0.05)
	equipRod(sim, p)
	castAndWaitBite(t, sim, p)
	sim:UnequipTools(p)
	equipRod(sim, p)
	sim:Advance(FRAME)
	name, data = lastState(sim, p)
	t.eq(name, "Idle", "a quick unequip + re-equip still ends the session")
	t.eq(data.Reason, "unequipped")

	-- Unequip + hook in the same frame (before the watcher runs): no minigame.
	sim:Advance(FishingConfig.CastCooldown + 0.05)
	equipRod(sim, p)
	castAndWaitBite(t, sim, p)
	sim:UnequipTools(p)
	sim:FireServer(p, "FishingHook")
	name, data = lastState(sim, p)
	t.eq(name, "Idle", "the hook found the rod gone")
	t.eq(data.Reason, "unequipped")
	sim:AssertNoErrors()
end

tests["session ends: death (and the minigame with it)"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	startMinigame(t, sim, p)
	sim:KillCharacter(p)
	sim:Advance(FRAME)
	local name, data = lastState(sim, p)
	t.eq(name, "Idle")
	t.eq(data.Reason, "died")
	t.eq(p:GetAttribute("FishingState"), "Idle")
	sim:Advance(FishingConfig.CastCooldown + 0.05)
	local denied, deniedData = cast(sim, p)
	t.eq(denied, "Denied", "a dead fisher cannot cast")
	t.eq(deniedData.Reason, "norod")
	local count = #stateEvents(sim, p)
	sim:Advance(FishingConfig.MinigameTimeout + 1, COARSE)
	t.eq(#stateEvents(sim, p), count, "no timeout after the session ended")
	t.eq(#rodsOf(p), 1, "a rod after respawning")
	sim:AssertNoErrors()
end

tests["session ends: FishingStop; Stop without a session does nothing"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	sim:FireServer(p, "FishingStop")
	t.eq(#stateEvents(sim, p), 0, "no session → no answer")
	t.eq((cast(sim, p)), "Waiting")
	sim:FireServer(p, "FishingStop")
	local name, data = lastState(sim, p)
	t.eq(name, "Idle")
	t.eq(data.Reason, "stop")
	local count = #stateEvents(sim, p)
	sim:Advance(10, COARSE)
	t.eq(#stateEvents(sim, p), count, "no bite after Stop")
	sim:AssertNoErrors()
end

tests["session ends: StopFishing API and a released base"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local fishing = service(sim)
	ready(sim, p)
	t.eq((cast(sim, p)), "Waiting")
	sim:Run(function()
		fishing:StopFishing(p, "base")
	end)
	local name, data = lastState(sim, p)
	t.eq(name, "Idle")
	t.eq(data.Reason, "base")

	-- BaseService.BaseReleased for the fisher's base (a later stage may take bases away).
	sim:Advance(FishingConfig.CastCooldown + 0.05)
	t.eq((cast(sim, p)), "Waiting")
	local BaseService = sim:Require(sim:Find("ServerScriptService.Services.BaseService"))
	local base = BaseService:GetBase(p)
	sim:Run(function()
		BaseService.BaseReleased:Fire(p, base)
	end)
	name, data = lastState(sim, p)
	t.eq(name, "Idle")
	t.eq(data.Reason, "base")
	t.eq(p:GetAttribute("FishingState"), "Idle")
	sim:AssertNoErrors()
end

-- Bite delay fixed to 3 s: session 1 would bite at cast1 + 4.0, session 2 (cast 1 s later)
-- bites at cast2 + 4.0 (CastWindUp + CastFlightTime + 3). A stale bite thread of session 1 would show up 1 s early.
local function staleBiteTest(t: any, extraPatches: { any })
	local patches = {
		{
			path = "ReplicatedStorage.Shared.Config.FishingConfig",
			from = "BiteDelay = { Min = 2.5, Max = 6 }",
			to = "BiteDelay = { Min = 3, Max = 3 }",
		},
	}
	for _, patch in extraPatches do
		table.insert(patches, patch)
	end
	local sim = boot(t, patches)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local expected = FishingConfig.CastWindUp + FishingConfig.CastFlightTime + 3 / START_ROD.BiteSpeed
	local _, _, cast1 = cast(sim, p)
	sim:Advance(0.2)
	sim:FireServer(p, "FishingStop")
	sim:Advance(FishingConfig.CastCooldown + 0.05)
	local name, _, cast2 = cast(sim, p)
	t.eq(name, "Waiting", "recast accepted")
	local count = #stateEvents(sim, p)
	sim:Advance(cast1 + expected + 0.1 - sim:Time())
	t.eq(#stateEvents(sim, p), count, "no stale bite from the stopped session")
	t.eq(p:GetAttribute("FishingState"), "Waiting")
	local bite, _, biteTime = nextState(sim, p, 5)
	t.eq(bite, "Bite")
	t.near(biteTime - cast2, expected, 2 * FRAME, "the new session bites on its own schedule")
	sim:AssertNoErrors()
end

tests["stale threads: a stopped session's bite never reaches the new session"] = function(t)
	staleBiteTest(t, {})
end

tests["stale threads: the session token alone guards (thread cancelling disabled)"] = function(t)
	staleBiteTest(t, {
		{
			path = SERVICE_PATH,
			from = "local function cancelThread(thread: thread?)",
			to = "local function cancelThread(thread: thread?)\n\tdo return end -- test: never cancel",
		},
	})
end

tests["two players fish at the same time independently"] = function(t)
	local sim = boot(t)
	local a = addPlayer(sim, 1)
	local b = addPlayer(sim, 2)
	ready(sim, a)
	ready(sim, b)
	local nameA, dataA = cast(sim, a)
	local nameB, dataB = cast(sim, b)
	t.eq(nameA, "Waiting")
	t.eq(nameB, "Waiting")
	t.ok(horizontal(dataA.Target - spotOf(sim, a).Position).Magnitude < START_ROD.CastDistance + 3.5, "A's own water")
	t.ok(horizontal(dataB.Target - spotOf(sim, b).Position).Magnitude < START_ROD.CastDistance + 3.5, "B's own water")
	t.near(b:GetAttribute("BobberTarget"), dataB.Target, 1e-3)

	-- A scares the fish; B keeps fishing.
	sim:FireServer(a, "FishingHook")
	t.eq((lastState(sim, a)), "Lost")
	t.eq(b:GetAttribute("FishingState"), "Waiting", "B unaffected")
	local bite = nextState(sim, b, 10)
	t.eq(bite, "Bite")
	sim:FireServer(b, "FishingHook")
	t.eq((lastState(sim, b)), "Minigame")
	t.eq(a:GetAttribute("FishingState"), "Idle")

	-- A casts again while B plays the minigame; B leaving the spot does not touch A.
	sim:Advance(FishingConfig.CastCooldown)
	t.eq((cast(sim, a)), "Waiting")
	standOn(sim, b, spotOf(sim, b), Vector3.new(0, 0, FishingConfig.KeepRadius + 5))
	sim:Advance(0.5)
	t.eq(b:GetAttribute("FishingState"), "Idle")
	t.eq((select(2, lastState(sim, b))).Reason, "moved")
	t.eq(a:GetAttribute("FishingState"), "Waiting", "A unaffected")
	for _, event in stateEvents(sim, a) do
		t.eq(event.player, a)
	end
	sim:AssertNoErrors()
end

tests["requests: junk arguments and request floods are handled safely"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	sim:FireServer(p, "FishingCast", { evil = true }, 1e309, "x")
	t.eq((lastState(sim, p)), "Waiting", "extra arguments ignored")
	sim:FireServer(p, "FishingHook", 0 / 0)
	sim:FireServer(p, "FishingStop", "now", {})
	sim:Advance(FishingConfig.CastCooldown + 0.05)

	-- A flood of casts in one frame: one session, a bounded number of answers.
	local count = #stateEvents(sim, p)
	for _ = 1, 100 do
		sim:FireServer(p, "FishingCast")
	end
	local names = statesSince(sim, p, count)
	t.eq(names[1], "Waiting")
	t.ok(#names <= 25, `flood answered {#names} times (rate limited)`)
	t.eq(p:GetAttribute("FishingState"), "Waiting")
	sim:AssertNoErrors()
end

tests["no leaks: players leaving mid-fishing clean up connections, threads and the held fish"] = function(t)
	local sim = boot(t)
	local baseline = sim:CountConnections()
	local fishing = service(sim)

	local waiting = addPlayer(sim, 1)
	local reeling = addPlayer(sim, 2)
	local holder = addPlayer(sim, 3)
	local dead = addPlayer(sim, 4)
	for _, p in { waiting, reeling, holder, dead } do
		ready(sim, p)
	end
	t.eq((cast(sim, waiting)), "Waiting")
	startMinigame(t, sim, reeling)
	local mg, startTime = startMinigame(t, sim, holder)
	t.eq((winMinigame(sim, holder, mg, startTime)), "Caught")
	sim:Advance(FishingConfig.LeapTime + 0.05) -- the fish lands above the head after its leap
	local heldCharacter = holder.Character
	t.ok(heldCharacter:FindFirstChild("HeldFish"), "holding a fish")
	t.eq((cast(sim, dead)), "Waiting")
	sim:KillCharacter(dead)
	sim:Advance(BaseConfig.RespawnDelay + 1, COARSE)

	for _, p in { waiting, reeling, holder, dead } do
		sim:RemovePlayer(p)
	end
	sim:Advance(1)
	t.eq(sim:CountConnections(), baseline, `connections back to baseline:\n{sim:FormatConnections()}`)
	t.eq(#fishing:GetCatch(holder), 0, "state of the departed player dropped")
	t.eq(heldCharacter:FindFirstChild("HeldFish"), nil, "held fish gone")

	-- Nothing scheduled for the departed players fires later.
	local events = #sim.ClientEvents
	sim:Advance(FishingConfig.MinigameTimeout + 2, COARSE)
	t.eq(#sim.ClientEvents, events, "no late events")
	sim:AssertNoErrors()
end

tests["no leaks: per-player server connections do not pile up on respawn and are released on leave"] = function(t)
	local sim = boot(t)
	local before = sim:CountConnections("server")
	local p = addPlayer(sim, 1)
	ready(sim, p)
	t.eq((cast(sim, p)), "Waiting")
	local playing = sim:CountConnections("server")
	t.ok(playing > before, "per-player connections exist while playing")
	for _ = 1, 3 do
		sim:KillCharacter(p)
		sim:Advance(BaseConfig.RespawnDelay + 0.5, COARSE)
	end
	t.eq(sim:CountConnections("server"), playing, `respawns replace, not add:\n{sim:FormatConnections("server")}`)
	t.eq(#rodsOf(p), 1, "one rod after three respawns")
	sim:RemovePlayer(p)
	sim:Advance(0.5)
	t.eq(sim:CountConnections("server"), before, `back to baseline:\n{sim:FormatConnections("server")}`)
	t.eq(sim:CountConnections(p), 0, "no connections owned by the departed client")
	t.eq(service(sim):GetRodId(p), RodConfig.StartRod, "state of the departed player dropped")
	sim:AssertNoErrors()
end

return tests
