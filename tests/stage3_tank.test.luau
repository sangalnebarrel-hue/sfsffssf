--[[
	Stage 3 wave 1 A — the tank on the server (design §7.3), run inside RbxSim against the built
	Place1.rbxl with real persistence (the sim DataStore) and headless players (clientDelay = 1e9:
	no client scripts run, the server is driven like a client would drive it):
	  • catching: a forced fish lands in the lowest free display with a Uid, the "Caught" payload
	    carries Fish.Uid / Fish.New and Tank; slot / Tank / Player attributes, the label and the
	    light bar; Event written last, fish fields nil on empty displays, locked displays 7..12;
	    New true then false, persisted;
	  • the full tank: a stronger catch replaces the weakest fish (sold at its value now), a weaker
	    one is sold at once — money, Stats.Sold, the toast data;
	  • casting before the load finishes → Denied "loading";
	  • income: exact whole coins from integer tenths, a hitch credits ≤ MaxCatchUp ticks, no base
	    (the queue) → no income, no growth, then a quiet mount;
	  • growth ×1 → ×3 (patched to 30 s), the price at the sale moment; GrowFrom exact on a
	    whole-second mount (AttrTime);
	  • selling: money, the empty display, Event sold, TankEvent Sold, stats, the ledger;
	  • the stall rate from the server's own 1 Hz samples (dwell, a teleport resets it), the
	    prompts (market, kiosk, the own tank; another player's tank prompt does nothing; spam is
	    bounded by the request bucket), the exploits (junk uids, someone else's fish, a double
	    sell, 100 sells in one frame);
	  • rare catches save soon; dormant fish; the rod from data; two players; leave → clean.

	Run: lune run tools/run_tests.luau stage3_tank
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local PLACE = "Place1.rbxl"

-- Pure config modules are read straight from src/ (the same values the game uses).
local function loadConfig(name: string): any
	local path = `src/ReplicatedStorage/Shared/Config/{name}.luau`
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum },
		injectGlobals = true,
	})
	return chunk()
end

local DataConfig = loadConfig("DataConfig")
local EconomyConfig = loadConfig("EconomyConfig")
local FishingConfig = loadConfig("FishingConfig")
local RodConfig = loadConfig("RodConfig")
local TankConfig = loadConfig("TankConfig")
local UIConfig = loadConfig("UIConfig")

local Vector3 = roblox.Vector3

local COARSE = 0.05
local STORE = "PlayerData_Studio" -- the sim reports Studio (DataService.StoreName)
-- Fast bites: the catch tests do not wait 2.5–6 s for every fish.
local FAST_BITES = {
	path = "ReplicatedStorage.Shared.Config.FishingConfig",
	from = "BiteDelay = { Min = 2.5, Max = 6 },",
	to = "BiteDelay = { Min = 0.1, Max = 0.1 },",
}

--------------------------------------------------------------------------------
-- Sim helpers
--------------------------------------------------------------------------------

type Patch = { path: string, from: string, to: string }

-- Boots a sim; patches edit ModuleScript sources before the server starts; opts.dataStore /
-- opts.epoch / opts.seed restart a server on a previous DataStore.
local function boot(t: any, patches: { Patch }?, opts: { [string]: any }?): any
	local o = opts or {}
	local sim = t.sim({ place = PLACE, dataStore = o.dataStore, epoch = o.epoch, seed = o.seed })
	for _, patch in patches or {} do
		local module = sim:Find(patch.path)
		t.ok(module, `module {patch.path} exists`)
		local source = module.Source
		local start = string.find(source, patch.from, 1, true)
		t.ok(start, `patch anchor «{patch.from}» found in {patch.path}`)
		module.Source = string.sub(source, 1, start - 1) .. patch.to .. string.sub(source, start + #patch.from)
	end
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

local function service(sim: any, name: string): any
	return sim:Require(sim:Find(`ServerScriptService.Services.{name}`))
end

local function shared(sim: any, name: string): any
	return sim:Require(sim:Find(`ReplicatedStorage.Shared.{name}`))
end

-- A headless player (no client scripts), waited until the data is loaded.
local function addPlayer(sim: any, id: number, wait: boolean?): any
	local p = sim:AddPlayer({ UserId = id, Name = `Player{id}`, DisplayName = `Игрок{id}`, clientDelay = 1e9 })
	if wait ~= false then
		sim:WaitFor(function()
			return p:GetAttribute("DataMode") ~= "Loading" and p.Character ~= nil
		end, 10)
		sim:Advance(0.1)
	end
	return p
end

local function baseOf(sim: any, player: any): any
	local index = player:GetAttribute("BaseIndex")
	if typeof(index) ~= "number" or index <= 0 then
		return nil
	end
	return sim.workspace.Bases:FindFirstChild(`Base_{index}`)
end

local function slotOf(sim: any, player: any, index: number): any
	return baseOf(sim, player).Tank.Slots:FindFirstChild(`Slot_{index}`)
end

local function leaderMoney(player: any): number
	return player.leaderstats[EconomyConfig.Leaderstats.Money].Value
end

local function fishData(sim: any, id: string, kg: number?, mutation: string?): any
	local rules = shared(sim, "FishingRules")
	local def = rules.GetFish(id)
	local weight = kg or def.MinKg
	local value, income = rules.Price(id, weight, mutation)
	return { Id = id, Rarity = def.Rarity, Mutation = mutation, Kg = weight, Value = value, Income = income }
end

-- Adds a fish through TankService:AddFish (as the catch sink would), in a server thread.
local function addFish(sim: any, player: any, id: string, kg: number?, mutation: string?, reason: string?): any
	local tank = service(sim, "TankService")
	local fish = fishData(sim, id, kg, mutation)
	return sim:Run(function()
		return tank:AddFish(player, fish, reason or "catch")
	end)
end

local function tankEvents(sim: any, player: any, kind: string?): { any }
	local out = {}
	for _, e in sim:ClientEventsFor(player, "TankEvent") do
		if kind == nil or e.args[1] == kind then
			table.insert(out, e.args[2])
		end
	end
	return out
end

local function sell(sim: any, player: any, uid: any)
	sim:FireServer(player, "TankSell", uid)
end

--------------------------------------------------------------------------------
-- Fishing helpers (the real minigame, like stage2_fishing)
--------------------------------------------------------------------------------

local function stateEvents(sim: any, player: any): { any }
	return sim:ClientEventsFor(player, "FishingState")
end

local function nextState(sim: any, player: any, timeout: number?, from: number?, step: number?): (string?, any)
	local start = from or #stateEvents(sim, player)
	local entry = sim:WaitFor(function()
		return stateEvents(sim, player)[start + 1]
	end, timeout or 10, step)
	if not entry then
		return nil, nil
	end
	return entry.args[1], entry.args[2]
end

local function rodOf(player: any): any
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, child in container:GetChildren() do
				if child:IsA("Tool") and child:GetAttribute("RodId") ~= nil then
					return child
				end
			end
		end
	end
	return nil
end

-- On its own fishing spot with the rod in hand.
local function ready(sim: any, player: any)
	local spot = baseOf(sim, player).FishingSpot
	sim:Teleport(player, spot.Position + Vector3.new(0, 3, 0))
	local rod = rodOf(player)
	if rod and rod.Parent ~= player.Character then
		sim:EquipTool(player, rod)
	end
end

local function forceFish(sim: any, id: string, mutation: string?, kg: number?): any
	local fish = fishData(sim, id, kg, mutation)
	service(sim, "FishingService").RollFishForTest = function()
		return table.clone(fish)
	end
	return fish
end

-- Cast → bite → hook → perfect taps; returns the final FishingState name and payload.
local function catchOne(t: any, sim: any, player: any): (string?, any)
	local rules = shared(sim, "FishingRules")
	local count = #stateEvents(sim, player)
	sim:FireServer(player, "FishingCast")
	local name = nextState(sim, player, 1, count)
	t.eq(name, "Waiting", "cast accepted")
	local bite = nextState(sim, player, 10, count + 1, COARSE)
	t.eq(bite, "Bite", "the fish bites")
	local before = #stateEvents(sim, player)
	sim:FireServer(player, "FishingHook")
	local mgName, mg = nextState(sim, player, 1, before)
	t.eq(mgName, "Minigame", "hooked")
	local startTime = sim:Time()
	local center = mg.ZoneCenter
	local from = FishingConfig.TapInterval + 0.02
	for _ = 1, mg.HitsNeeded do
		local moment = from
		while true do
			local d = math.abs(rules.Needle(mg.U0, mg.Speed, moment) - center)
			if d <= mg.ZoneWidth / 2 * 0.6 then
				break
			end
			moment += 0.005
		end
		local wait = startTime + moment - sim:Time()
		if wait > 0 then
			sim:Advance(wait)
		end
		local n = #stateEvents(sim, player)
		sim:FireServer(player, "FishingTap", moment)
		local result, data = nextState(sim, player, 0.1, n)
		if result ~= "Zone" then
			sim:Advance(FishingConfig.CastCooldown + 0.05)
			return result, data
		end
		center = data.ZoneCenter
		from = moment + FishingConfig.TapInterval + 0.02
	end
	error("no catch after all hits")
end

-- What the save looks like after everyone leaves and the final saves land.
local function peekAfterLeave(sim: any, player: any): any
	sim:RemovePlayer(player)
	sim:Advance(DataConfig.MinWriteGap + 1, COARSE)
	return sim.DataStore:Peek(STORE, `Player_{player.UserId}`)
end

local function savedFish(id: string, uid: string, slot: number, extra: { [string]: any }?): { [string]: any }
	local f: { [string]: any } = { Uid = uid, Id = id, Kg = 1.2, Age = 0, Slot = slot, CaughtAt = 1700000000 }
	for key, value in extra or {} do
		f[key] = value
	end
	return f
end

-- A saved player (the template + changes) poked into the store before they join.
local function pokeSave(sim: any, userId: number, changes: { [string]: any })
	local data = {
		V = 1,
		Money = 0,
		RodId = RodConfig.StartRod,
		TankSlots = TankConfig.StartSlots,
		LockLevel = 0,
		Upgrades = {},
		Tank = {},
		NextUid = 1,
		Stats = { Caught = 0, Sold = 0, Earned = 0, Spent = 0, Species = {} },
		Created = 1700000000,
		LastOnline = 1700000000,
		SaveCount = 1,
	}
	for key, value in changes do
		data[key] = value
	end
	sim.DataStore:Poke(STORE, `Player_{userId}`, data)
end

local function ledgerHolds(t: any, sim: any, value: any, what: string)
	local PlayerData = sim:Require(sim:Find("ServerScriptService.Lib.PlayerData"))
	local ok, expected = PlayerData.Ledger(value)
	t.ok(ok, `{what}: the ledger holds (Money {value.Money}, expected {expected})`)
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

local tests = {}

tests["catch: the lowest free display, a Uid, the payload's Tank; attributes, label, light bar; Event last; New persisted"] = function(
	t
)
	local sim = boot(t, { FAST_BITES })
	local p = addPlayer(sim, 1)
	local TankRules = shared(sim, "TankRules")
	local rules = shared(sim, "FishingRules")
	local base = baseOf(sim, p)
	local slot1 = slotOf(sim, p, 1)
	-- Mounted: displays 1..6 empty, 7..12 locked; every display got a quiet mount event.
	for i = 1, TankConfig.MaxSlots do
		local slot = slotOf(sim, p, i)
		local state = if i <= TankConfig.StartSlots then "empty" else "locked"
		t.eq(slot:GetAttribute("State"), state, `Slot_{i}: {state}`)
		t.match(slot:GetAttribute("Event"), "^%d+|mount|$")
		t.eq(slot:GetAttribute("FishId"), nil, `Slot_{i}: no fish fields`)
		if state == "locked" then
			t.eq(slot.Pedestal.LabelGui.Label.Text, TankConfig.Texts.SlotLocked)
			t.eq(slot.LightBar.Material, roblox.Enum.Material.SmoothPlastic, `Slot_{i}: dim bar`)
			t.eq(slot.LightBar:FindFirstChildOfClass("SurfaceLight").Enabled, false, `Slot_{i}: light off`)
		else
			t.eq(slot.Pedestal.LabelGui.Label.Text, TankConfig.Texts.SlotEmpty)
		end
	end
	t.eq(base.Tank:GetAttribute("Count"), 0)
	t.eq(base.Tank:GetAttribute("Slots"), TankConfig.StartSlots)
	t.eq(p:GetAttribute("TankCount"), 0)
	t.eq(p:GetAttribute("TankSlots"), TankConfig.StartSlots)
	t.ok(base.Tank.Glass.PromptAttachment.TankPrompt.Enabled, "the tank prompt is on")

	-- The order of attribute writes on Slot_1: fish fields, then State, then Event LAST.
	local order = {}
	slot1.AttributeChanged:Connect(function(name: string)
		table.insert(order, name)
	end)
	ready(sim, p)
	local fish = forceFish(sim, "Perch", "Gold", 1.1)
	local name, data = catchOne(t, sim, p)
	t.eq(name, "Caught")
	t.eq(data.Fish.Id, "Perch")
	t.eq(data.Fish.Uid, "f1", "the payload names the fish in the tank")
	t.eq(data.Fish.New, true, "first Perch ever")
	t.eq(data.Total, 1)
	local tank = data.Tank
	t.eq(tank.Result, "stored")
	t.eq(tank.Slot, 1, "the lowest free display")
	t.eq(tank.Uid, "f1")
	t.eq(tank.Count, 1)
	t.eq(tank.Slots, TankConfig.StartSlots)
	t.eq(tank.Price, nil, "nothing sold")
	t.eq(tank.First, true, "the first fish ever")

	sim:Flush()
	t.eq(order[#order], "Event", `Event written last ({table.concat(order, ", ")})`)
	t.ok(table.find(order, "State") and table.find(order, "State") < #order, "State before Event")
	t.eq(slot1:GetAttribute("State"), "fish")
	t.eq(slot1:GetAttribute("FishUid"), "f1")
	t.eq(slot1:GetAttribute("FishId"), "Perch")
	t.eq(slot1:GetAttribute("Rarity"), "Common")
	t.eq(slot1:GetAttribute("Mutation"), "Gold")
	t.near(slot1:GetAttribute("Kg"), 1.1, 1e-4)
	t.eq(slot1:GetAttribute("Value"), fish.Value)
	local income10 = TankRules.Income10(fish.Income)
	t.near(slot1:GetAttribute("Income"), income10 / 10, 1e-4)
	local age = sim.workspace:GetServerTimeNow() - slot1:GetAttribute("GrowFrom")
	t.ok(age >= -0.01 and age < 1.5, `GrowFrom ≈ the catch moment (age {age})`)
	t.match(slot1:GetAttribute("Event"), "^%d+|in|Perch$")
	t.eq(slot1.Pedestal.LabelGui.Label.Text, rules.GetFish("Perch").Name)
	t.eq(slot1.Pedestal.LabelGui.Label.TextColor3, rules.GetRarity("Common").Color, "label in the rarity colour")
	t.eq(slot1.LightBar.Color, UIConfig.Rarity.Common.Bottom, "light bar in the rarity colour")
	t.near(slot1.Display.Transparency, TankConfig.Display.GlassOccupied, 1e-4)
	t.eq(base.Tank:GetAttribute("Count"), 1)
	t.near(base.Tank:GetAttribute("Income"), income10 / 10, 1e-4)
	t.eq(p:GetAttribute("TankCount"), 1)
	t.near(p:GetAttribute("Income"), income10 / 10, 1e-4)
	t.eq(p.leaderstats[EconomyConfig.Leaderstats.Income].Value, math.round(income10 / 10))

	-- The second Perch: not new any more, the next display.
	local name2, data2 = catchOne(t, sim, p)
	t.eq(name2, "Caught")
	t.eq(data2.Fish.New, false, "the second Perch is not new")
	t.eq(data2.Fish.Uid, "f2")
	t.eq(data2.Tank.Slot, 2)
	t.eq(data2.Tank.First, nil, "First only once")
	t.eq(slotOf(sim, p, 2):GetAttribute("State"), "fish")

	local saved = peekAfterLeave(sim, p)
	t.eq(saved.Stats.Caught, 2, "Stats.Caught saved")
	t.eq(saved.Stats.Species.Perch, 2, "Stats.Species saved")
	t.eq(#saved.Tank, 2, "both fish saved")
	t.eq(saved.Session, nil, "the lock released on leave")
	ledgerHolds(t, sim, saved, "after leave")
	sim:AssertNoErrors({ warnings = true })
end

tests["full tank: a stronger catch replaces the weakest (sold at its value now), a weaker one is sold at once"] = function(
	t
)
	local sim = boot(t, { FAST_BITES })
	local p = addPlayer(sim, 1)
	local TankRules = shared(sim, "TankRules")
	local data = service(sim, "DataService"):Get(p)
	-- Six fish: the weakest is the 0.3 kg Crucian (income 0.8/s) in display 4.
	for i = 1, TankConfig.StartSlots do
		local kg = if i == 4 then 0.3 else 1.2
		local result = addFish(sim, p, "Crucian", kg)
		t.eq(result.Result, "stored", `fish {i} stored`)
		t.eq(result.Slot, i)
	end
	t.eq(p:GetAttribute("TankCount"), TankConfig.StartSlots, "full")
	sim:Advance(3, COARSE)
	local before = leaderMoney(p)

	-- A Swordfish replaces the weakest Crucian: its price at its age now, into the wallet.
	ready(sim, p)
	forceFish(sim, "Swordfish", nil, 30)
	local weakest = slotOf(sim, p, 4)
	local weakValue = weakest:GetAttribute("Value")
	local name, payload = catchOne(t, sim, p)
	t.eq(name, "Caught")
	local tank = payload.Tank
	t.eq(tank.Result, "replaced")
	t.eq(tank.Slot, 4, "the new fish takes the weakest one's display")
	t.eq(tank.Replaced.Id, "Crucian")
	t.eq(tank.Replaced.Uid, "f4")
	t.eq(tank.Replaced.Rarity, "Common")
	t.eq(tank.Price, tank.Replaced.Price, "Price == Replaced.Price")
	t.ok(tank.Price >= weakValue and tank.Price <= weakValue * TankConfig.Growth.Cap, "the price grew with age")
	t.eq(tank.Count, TankConfig.StartSlots)
	t.eq(payload.Fish.Uid, tank.Uid)
	t.eq(leaderMoney(p) - before >= tank.Price, true, "the sale reached the wallet")
	t.eq(weakest:GetAttribute("FishId"), "Swordfish")
	t.eq(weakest:GetAttribute("State"), "fish", "a swap keeps State")
	t.match(weakest:GetAttribute("Event"), `^%d+|swap|{tank.Price}$`)
	t.eq(data.Stats.Sold, 1)

	-- A weaker Crucian is sold at once at ×1, nothing in the displays changes.
	local events = {}
	for i = 1, TankConfig.MaxSlots do
		events[i] = slotOf(sim, p, i):GetAttribute("Event")
	end
	local money = leaderMoney(p)
	local sold = addFish(sim, p, "Crucian", 0.3)
	t.eq(sold.Result, "sold")
	t.eq(sold.Uid, nil, "a sold fish gets no Uid")
	t.eq(sold.Slot, nil)
	local value = fishData(sim, "Crucian", 0.3).Value
	t.eq(sold.Price, TankRules.SellPrice(value, 0, EconomyConfig.HomeRatePct))
	t.eq(leaderMoney(p) - money, sold.Price, "exactly the sale price")
	for i = 1, TankConfig.MaxSlots do
		t.eq(slotOf(sim, p, i):GetAttribute("Event"), events[i], `Slot_{i}: no event for a sold catch`)
	end
	t.eq(data.Stats.Sold, 2)
	t.eq(data.NextUid, 8, "the sold catch spent no number")
	sim:AssertNoErrors({ warnings = true })
end

tests["casting before the load finishes → Denied loading; accepted once loaded"] = function(t)
	local sim = boot(t, { FAST_BITES })
	sim.DataStore:SetLatency(2)
	local p = addPlayer(sim, 1, false)
	sim:WaitFor(function()
		return p.Character ~= nil and rodOf(p) ~= nil and baseOf(sim, p) ~= nil
	end, 5)
	t.eq(p:GetAttribute("DataMode"), "Loading")
	ready(sim, p)
	local count = #stateEvents(sim, p)
	sim:FireServer(p, "FishingCast")
	local name, data = nextState(sim, p, 1, count)
	t.eq(name, "Denied")
	t.eq(data.Reason, "loading")
	t.eq(data.Text, FishingConfig.Texts.Denied.loading)
	sim:WaitFor(function()
		return p:GetAttribute("DataMode") == "Ready"
	end, 5)
	sim.DataStore:SetLatency(0.05)
	sim:Advance(FishingConfig.CastCooldown + 0.1)
	ready(sim, p) -- (the spawn may have put the fresh character back on its pad)
	local again = #stateEvents(sim, p)
	sim:FireServer(p, "FishingCast")
	local againName, againData = nextState(sim, p, 1, again)
	t.eq(againName, "Waiting", `accepted once the data is loaded ({againData and againData.Reason})`)
	sim:AssertNoErrors({ warnings = true })
end

tests["income: whole coins from integer tenths, exactly; a hitch credits ≤ MaxCatchUp ticks"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local TankRules = shared(sim, "TankRules")
	local tank = service(sim, "TankService")
	local rt = tank._runtimeFor(p)
	local ticks0 = rt.Ticks
	-- 0.8 + 1.7 + 4 = 6.5 coins a second: the tenths carry over between ticks.
	local fish = {
		fishData(sim, "Crucian", 0.3),
		fishData(sim, "Perch", 1.1),
		fishData(sim, "Puffer", 1.4),
	}
	local sum = 0
	sim:Run(function()
		for _, f in fish do
			tank:AddFish(p, f, "catch")
			sum += TankRules.Income10(f.Income)
		end
	end)
	t.eq(rt.Income10Sum, sum)
	t.ok(sum % 10 ~= 0, `a fractional rate ({sum} tenths)`)
	sim:Advance(23.4, COARSE)
	local ticks = rt.Ticks - ticks0
	t.ok(ticks >= 22 and ticks <= 24, `about one tick a second ({ticks})`)
	t.eq(leaderMoney(p), (ticks * sum) // 10, "money = floor(ticks · Σ Income10 / 10)")
	t.eq(p:GetAttribute("Money"), leaderMoney(p))
	t.eq(rt.Carry10, (ticks * sum) % 10, "the tenths are carried")

	-- A 10 s hitch in one frame: at most MaxCatchUp ticks, no lump sum.
	local beforeTicks = rt.Ticks
	sim:Advance(10, 10)
	sim:Advance(0.1)
	local hitch = rt.Ticks - beforeTicks
	t.ok(hitch >= 1 and hitch <= EconomyConfig.MaxCatchUp, `a hitch credits {hitch} ≤ MaxCatchUp ticks`)
	t.eq(leaderMoney(p), ((rt.Ticks - ticks0) * sum) // 10, "still exact after the hitch")
	local data = service(sim, "DataService"):Get(p)
	ledgerHolds(t, sim, data, "live data")
	sim:AssertNoErrors({ warnings = true })
end

tests["no base (the queue): no income, no growth, Denied nobase; assigned → a quiet mount, ages kept"] = function(t)
	local sim = boot(t)
	local players = {}
	for id = 1, 8 do
		players[id] = addPlayer(sim, id)
	end
	pokeSave(sim, 9, {
		Tank = { savedFish("Perch", "f1", 1, { Age = 40 }), savedFish("Puffer", "f2", 2, { Age = 12.5 }) },
		NextUid = 3,
	})
	local waiting = addPlayer(sim, 9)
	t.eq(waiting:GetAttribute("BaseIndex"), 0, "in the queue")
	t.eq(waiting:GetAttribute("DataMode"), "Ready", "data loaded without a base")
	t.eq(waiting:GetAttribute("TankCount"), 2)
	t.eq(waiting:GetAttribute("TankSlots"), TankConfig.StartSlots)
	t.eq(waiting:GetAttribute("Income"), 0, "no income without a base")
	sim:Advance(5, COARSE)
	t.eq(leaderMoney(waiting), 0, "nothing credited in the queue")
	local data = service(sim, "DataService"):Get(waiting)
	t.near(data.Tank[1].Age, 40, 1e-9, "no growth in the queue")
	sell(sim, waiting, "f1")
	local denied = tankEvents(sim, waiting, "Denied")
	t.eq(#denied, 1)
	t.eq(denied[1].Reason, "nobase")
	t.eq(denied[1].Text, TankConfig.Texts.Denied.nobase)

	-- A base frees up: the tank mounts quietly (mount events only), ages carry on from 40 / 12.5.
	local freed = baseOf(sim, players[3])
	local seen = {}
	for i = 1, TankConfig.MaxSlots do
		local slot = freed.Tank.Slots:FindFirstChild(`Slot_{i}`)
		slot:GetAttributeChangedSignal("Event"):Connect(function()
			table.insert(seen, slot:GetAttribute("Event"))
		end)
	end
	sim:RemovePlayer(players[3])
	sim:WaitFor(function()
		return waiting:GetAttribute("BaseIndex") == freed:GetAttribute("BaseIndex")
	end, 5)
	sim:Flush()
	for _, event in seen do
		t.ok(string.find(event, "|in|", 1, true) == nil, `no splash on a mount ({event})`)
	end
	local slot1 = freed.Tank.Slots.Slot_1
	t.eq(slot1:GetAttribute("FishUid"), "f1")
	t.match(slot1:GetAttribute("Event"), "^%d+|mount|$")
	local age = sim.workspace:GetServerTimeNow() - slot1:GetAttribute("GrowFrom")
	t.near(age, 40, 0.5, "the age carries on from the save")
	local TankRules = shared(sim, "TankRules")
	local income10 = TankRules.Income10(fishData(sim, "Perch", 1.2).Income)
		+ TankRules.Income10(fishData(sim, "Puffer", 1.2).Income)
	t.near(waiting:GetAttribute("Income"), income10 / 10, 1e-4, "income once mounted")
	sim:AssertNoErrors({ warnings = true })
end

tests["growth: ×1 → ×3 (Growth.Time patched to 30 s), the price at the sale moment"] = function(t)
	local sim = boot(t, {
		{ path = "ReplicatedStorage.Shared.Config.TankConfig", from = "Time = 300,", to = "Time = 30," },
	})
	local p = addPlayer(sim, 1)
	local TankRules = shared(sim, "TankRules")
	t.eq(TankRules.Growth(30), TankConfig.Growth.Cap, "the patched curve")
	local first = addFish(sim, p, "Puffer", 2)
	local second = addFish(sim, p, "Swordfish", 50)
	local value1 = slotOf(sim, p, first.Slot):GetAttribute("Value")
	local value2 = slotOf(sim, p, second.Slot):GetAttribute("Value")
	sim:Advance(12.3, COARSE)
	-- The price the client would show at this moment (same formula, same clock) is what is paid.
	local growFrom = slotOf(sim, p, first.Slot):GetAttribute("GrowFrom")
	local expected = TankRules.SellPrice(value1, sim.workspace:GetServerTimeNow() - growFrom, 100)
	local money = leaderMoney(p)
	sell(sim, p, first.Uid)
	local sold = tankEvents(sim, p, "Sold")
	t.eq(#sold, 1)
	t.eq(sold[1].Amount, expected, "the price at the sale moment")
	t.ok(expected > value1 and expected < value1 * 3, `grew between ×1 and ×3 ({expected} for {value1})`)
	t.eq(leaderMoney(p) - money, expected)
	sim:Advance(40, COARSE)
	sell(sim, p, second.Uid)
	local maxed = tankEvents(sim, p, "Sold")[2]
	t.eq(maxed.Amount, value2 * TankConfig.Growth.Cap, "«МАКС»: ×Cap and no more")
	sim:AssertNoErrors({ warnings = true })
end

tests["AttrTime: a mount on a whole-second frame keeps GrowFrom exact through the float32 attribute"] = function(t)
	local sim = boot(t)
	local TankRules = shared(sim, "TankRules")
	pokeSave(sim, 1, { Tank = { savedFish("Perch", "f1", 1, { Age = 0 }) }, NextUid = 2 })
	sim.DataStore:SetLatency(1)
	local p = addPlayer(sim, 1, false)
	-- The load's latency ends inside one long frame that lands exactly on a whole second
	-- (Sterbenz: k − c is exact for c ≥ k / 2, so c + (k − c) == k).
	local c = sim:Time()
	local k = math.ceil(c + 1.5)
	sim:Step(k - c)
	t.eq(sim:Time(), k, "a whole-second frame")
	sim:WaitFor(function()
		return p:GetAttribute("DataMode") == "Ready" and baseOf(sim, p) ~= nil
	end, 5)
	local slot = slotOf(sim, p, 1)
	local growFrom = slot:GetAttribute("GrowFrom")
	t.ok(growFrom % 1 ~= 0, "never a whole number in the attribute")
	local mountedAt = growFrom - 1 / 1024
	t.eq(mountedAt % 1, 0, "mounted on the whole second (+1/1024 s)")
	t.eq(growFrom, TankRules.AttrTime(mountedAt), "AttrTime(now − Age), read back exactly")
	t.ok(math.abs(sim.workspace:GetServerTimeNow() - growFrom) < 5, "not off by the float32 step (±64 s)")
	sim.DataStore:SetLatency(0.05)
	sim:AssertNoErrors({ warnings = true })
end

tests["selling: money += price, the display empties, Event sold, TankEvent Sold, Stats.Sold, the ledger"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local TankRules = shared(sim, "TankRules")
	local result = addFish(sim, p, "Puffer", 2, "Neon")
	local slot = slotOf(sim, p, result.Slot)
	local value = slot:GetAttribute("Value")
	local order = {}
	slot.AttributeChanged:Connect(function(name: string)
		table.insert(order, name)
	end)
	local money = leaderMoney(p)
	local growFrom = slot:GetAttribute("GrowFrom")
	sell(sim, p, result.Uid)
	local now = sim.workspace:GetServerTimeNow()
	local price = TankRules.SellPrice(value, now - growFrom, EconomyConfig.HomeRatePct)
	local sold = tankEvents(sim, p, "Sold")
	t.eq(#sold, 1)
	t.eq(sold[1].Amount, price)
	t.eq(sold[1].RatePct, EconomyConfig.HomeRatePct, "home rate")
	t.eq(sold[1].Place, nil, "sold from the panel")
	t.eq(#sold[1].Items, 1)
	t.eq(sold[1].Items[1].Uid, result.Uid)
	t.eq(sold[1].Items[1].Id, "Puffer")
	t.eq(sold[1].Items[1].Rarity, "Rare")
	t.eq(sold[1].Items[1].Mutation, "Neon")
	t.eq(sold[1].Items[1].Price, price)
	t.eq(leaderMoney(p) - money, price, "money += price")
	sim:Flush()
	t.eq(slot:GetAttribute("State"), "empty")
	for _, field in { "FishUid", "FishId", "Rarity", "Mutation", "Kg", "Value", "Income", "GrowFrom" } do
		t.eq(slot:GetAttribute(field), nil, `{field} cleared`)
	end
	t.match(slot:GetAttribute("Event"), `^%d+|sold|{price}$`)
	t.eq(order[#order], "Event", "Event last")
	t.eq(slot.Pedestal.LabelGui.Label.Text, TankConfig.Texts.SlotEmpty)
	t.eq(p:GetAttribute("TankCount"), 0)
	t.eq(p:GetAttribute("Income"), 0)
	local data = service(sim, "DataService"):Get(p)
	t.eq(data.Stats.Sold, 1)
	t.eq(#data.Tank, 0)
	-- Selling the same fish again: Denied missing, money once.
	sell(sim, p, result.Uid)
	local denied = tankEvents(sim, p, "Denied")
	t.eq(#denied, 1)
	t.eq(denied[1].Reason, "missing")
	t.eq(leaderMoney(p) - money, price, "money only once")
	local saved = peekAfterLeave(sim, p)
	t.eq(saved.Money, money + price)
	ledgerHolds(t, sim, saved, "saved")
	sim:AssertNoErrors({ warnings = true })
end

tests["rare catches save soon: a Mythic is in the DataStore within the write gap, not at the next autosave"] = function(
	t
)
	local sim = boot(t, { FAST_BITES })
	local p = addPlayer(sim, 1)
	local data = service(sim, "DataService")
	ready(sim, p)
	sim:Advance(DataConfig.MinWriteGap + 0.5, COARSE) -- (the load's gap has passed)
	local committed = data:CommittedSeq(p)
	local calls = sim.DataStore:CountCalls("UpdateAsync", STORE)
	forceFish(sim, "Perch")
	t.eq((catchOne(t, sim, p)), "Caught")
	sim:Advance(1, COARSE)
	t.eq(sim.DataStore:CountCalls("UpdateAsync", STORE), calls, "a common catch waits for the autosave")
	forceFish(sim, "DragonFish", nil, 6)
	local name, payload = catchOne(t, sim, p)
	t.eq(name, "Caught")
	t.eq(payload.Tank.Result, "stored")
	sim:WaitFor(function()
		return data:CommittedSeq(p) > committed
	end, DataConfig.MinWriteGap + 1, COARSE)
	t.ok(data:CommittedSeq(p) > committed, "SaveSoon committed")
	local saved = sim.DataStore:Peek(STORE, "Player_1")
	t.eq(#saved.Tank, 2, "both fish already in the store")
	t.eq(saved.Tank[2].Id, "DragonFish")
	t.ok(saved.Session ~= nil, "the lock is kept (still playing)")
	sim:AssertNoErrors({ warnings = true })
end

tests["dormant fish: an unknown Id is never shown, sold or replaced, and is saved back verbatim"] = function(t)
	local sim = boot(t)
	pokeSave(sim, 1, {
		Tank = {
			savedFish("Perch", "f1", 1),
			savedFish("FutureFish", "f2", 2, { Glow = "blue" }),
			savedFish("Crucian", "f3", 3, { Kg = 0.3 }),
		},
		NextUid = 4,
	})
	local p = addPlayer(sim, 1)
	t.eq(p:GetAttribute("TankCount"), 2, "the dormant fish is not counted")
	t.eq(slotOf(sim, p, 2):GetAttribute("State"), "empty", "not shown (its display is free)")
	sell(sim, p, "f2")
	t.eq(tankEvents(sim, p, "Denied")[1].Reason, "missing", "a dormant fish cannot be sold")
	-- Fill the tank with strong fish: the weakest active fish is replaced, never the dormant one.
	for _ = 1, 4 do
		addFish(sim, p, "Perch", 1.8)
	end
	t.eq(p:GetAttribute("TankCount"), TankConfig.StartSlots)
	local replaced = addFish(sim, p, "Swordfish", 40)
	t.eq(replaced.Result, "replaced")
	t.eq(replaced.Replaced.Uid, "f3", "the weakest active fish (the small Crucian)")
	local saved = peekAfterLeave(sim, p)
	local future = nil
	for _, f in saved.Tank do
		if f.Id == "FutureFish" then
			future = f
		end
	end
	t.ok(future, "the dormant fish is saved")
	t.eq(future.Uid, "f2")
	t.eq(future.Glow, "blue", "with the fields this server does not know")
	ledgerHolds(t, sim, saved, "saved")
	sim:AssertNoErrors({ warnings = true })
end

tests["rod from data: RodSea is the rod in hand; RodFuture plays the start rod and stays saved"] = function(t)
	local sim = boot(t)
	pokeSave(sim, 1, { RodId = "RodSea" })
	pokeSave(sim, 2, { RodId = "RodFuture" })
	local sea = addPlayer(sim, 1)
	local future = addPlayer(sim, 2)
	sim:Advance(0.5)
	local fishing = service(sim, "FishingService")
	t.eq(fishing:GetRodId(sea), "RodSea")
	t.eq(sea:GetAttribute("RodId"), "RodSea")
	t.eq(rodOf(sea):GetAttribute("RodId"), "RodSea", "the RodSea tool")
	t.eq(fishing:GetRodId(future), RodConfig.StartRod, "an unknown rod plays the start rod")
	t.eq(service(sim, "DataService"):Get(future).RodId, "RodFuture", "the saved RodId is not rewritten")
	-- SetRod writes the data.
	t.eq(fishing:SetRod(sea, "RodGolden"), true)
	t.eq(service(sim, "DataService"):Get(sea).RodId, "RodGolden")
	local savedFuture = peekAfterLeave(sim, future)
	t.eq(savedFuture.RodId, "RodFuture", "saved back unchanged")
	sim:AssertNoErrors({ warnings = true })
end

tests["two players are independent: own displays, money, uids and sales"] = function(t)
	local sim = boot(t)
	local a = addPlayer(sim, 1)
	local b = addPlayer(sim, 2)
	local fa = addFish(sim, a, "Perch", 1)
	local fb = addFish(sim, b, "Puffer", 1)
	t.eq(fa.Uid, "f1")
	t.eq(fb.Uid, "f1", "per-player numbers")
	t.eq(slotOf(sim, a, 1):GetAttribute("FishId"), "Perch")
	t.eq(slotOf(sim, b, 1):GetAttribute("FishId"), "Puffer")
	sell(sim, a, "f1")
	t.eq(slotOf(sim, a, 1):GetAttribute("State"), "empty")
	t.eq(slotOf(sim, b, 1):GetAttribute("State"), "fish", "B's fish untouched")
	t.ok(leaderMoney(a) > 0)
	t.eq(#tankEvents(sim, b, "Sold"), 0)
	sim:AssertNoErrors({ warnings = true })
end

tests["leave: displays «Пусто», fish and Tank attributes cleared, the prompt off; nothing left behind"] = function(
	t
)
	local sim = boot(t)
	local baseline = sim:CountConnections("server")
	local p = addPlayer(sim, 1)
	addFish(sim, p, "Perch", 1)
	addFish(sim, p, "SharkPup", 20, "Gold")
	local base = baseOf(sim, p)
	sim:RemovePlayer(p)
	sim:Advance(0.5)
	for i = 1, TankConfig.MaxSlots do
		local slot = base.Tank.Slots:FindFirstChild(`Slot_{i}`)
		t.eq(slot:GetAttribute("State"), "empty", `Slot_{i} empty`)
		t.eq(slot:GetAttribute("FishId"), nil)
		t.eq(slot.Pedestal.LabelGui.Label.Text, TankConfig.Texts.SlotEmpty)
		t.eq(slot.LightBar.Material, roblox.Enum.Material.Neon, `Slot_{i}: the template light bar`)
		t.near(slot.Display.Transparency, 0.66, 1e-4, `Slot_{i}: template glass`)
	end
	for _, name in { "Count", "Slots", "Income" } do
		t.eq(base.Tank:GetAttribute(name), nil, `Tank.{name} cleared`)
	end
	t.eq(base.Tank.Glass.PromptAttachment.TankPrompt.Enabled, false, "the prompt is off")
	t.eq(sim:CountConnections("server"), baseline, `no per-player connections:\n{sim:FormatConnections("server")}`)
	sim:Advance(DataConfig.MinWriteGap * 2 + 1, COARSE)
	for _, name in { "DataService", "EconomyService", "MarketService", "TankService" } do
		for key, size in service(sim, name)._debugSizes() do
			t.eq(size, 0, `{name}._debugSizes().{key}`)
		end
	end
	sim:AssertNoErrors({ warnings = true })
end

local function attachmentAt(sim: any, path: string): any
	local node = sim.workspace
	for name in string.gmatch(path, "[^%.]+") do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local MARKET_PATH = EconomyConfig.SellPoints[1].Path
local KIOSK_PATH = EconomyConfig.SellPoints[2].Path

-- Out of the stall's range, then walks in (no teleport into range: the dwell counts).
local function walkInto(sim: any, player: any, attachment: any)
	local spot = attachment.WorldPosition
	sim:Teleport(player, spot + Vector3.new(0, 3, 24))
	sim:Advance(1.2, COARSE)
	sim:WalkTo(player, spot + Vector3.new(0, 3, 3))
end

tests["stall rate: ×1.5 after MarketDwell samples at the market or a kiosk; away ×1; a teleport in sells at ×1"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local TankRules = shared(sim, "TankRules")
	local market = attachmentAt(sim, MARKET_PATH)
	local kiosk = attachmentAt(sim, KIOSK_PATH)
	t.ok(market and kiosk, "the sell points exist")
	local fish = {}
	for i = 1, 4 do
		fish[i] = addFish(sim, p, "Puffer", 2)
	end
	t.eq(p:GetAttribute("SellRatePct"), EconomyConfig.HomeRatePct)
	t.eq(p:GetAttribute("SellPlace"), "")

	walkInto(sim, p, market)
	sim:Advance(EconomyConfig.MarketDwell * EconomyConfig.IncomeTick + 0.3, COARSE)
	t.eq(p:GetAttribute("SellRatePct"), EconomyConfig.MarketRatePct, "the market rate after the dwell")
	t.eq(p:GetAttribute("SellPlace"), "Market")
	local slot = slotOf(sim, p, fish[1].Slot)
	local value, growFrom = slot:GetAttribute("Value"), slot:GetAttribute("GrowFrom")
	sell(sim, p, fish[1].Uid)
	local sold = tankEvents(sim, p, "Sold")[1]
	local age = sim.workspace:GetServerTimeNow() - growFrom
	t.eq(sold.RatePct, EconomyConfig.MarketRatePct)
	t.eq(sold.Place, "Market")
	t.eq(sold.Amount, TankRules.SellPrice(value, age, EconomyConfig.MarketRatePct), "×1.5 price")

	-- Home again: ×1.
	sim:Teleport(p, baseOf(sim, p).SpawnPad.Position + Vector3.new(0, 3, 0))
	sim:Advance(1.2, COARSE)
	t.eq(p:GetAttribute("SellRatePct"), EconomyConfig.HomeRatePct, "away from the stalls")
	t.eq(p:GetAttribute("SellPlace"), "")

	-- A kiosk on a bridge pays the same.
	walkInto(sim, p, kiosk)
	sim:Advance(EconomyConfig.MarketDwell * EconomyConfig.IncomeTick + 0.3, COARSE)
	t.eq(p:GetAttribute("SellRatePct"), EconomyConfig.MarketRatePct, "the kiosk rate")
	t.eq(p:GetAttribute("SellPlace"), "Kiosk1")
	sell(sim, p, fish[2].Uid)
	t.eq(tankEvents(sim, p, "Sold")[2].RatePct, EconomyConfig.MarketRatePct)
	t.eq(tankEvents(sim, p, "Sold")[2].Place, "Kiosk1")

	-- Teleported straight to the market and selling at once: ×1 (the dwell starts over).
	sim:Teleport(p, baseOf(sim, p).SpawnPad.Position + Vector3.new(0, 3, 0))
	sim:Advance(1.2, COARSE)
	sim:Teleport(p, market.WorldPosition + Vector3.new(0, 3, 3))
	sell(sim, p, fish[3].Uid)
	t.eq(tankEvents(sim, p, "Sold")[3].RatePct, EconomyConfig.HomeRatePct, "a teleport in sells at ×1")
	sim:Advance(1.1, COARSE)
	sell(sim, p, fish[4].Uid)
	t.eq(tankEvents(sim, p, "Sold")[4].RatePct, EconomyConfig.HomeRatePct, "one sample after a jump is not a dwell")
	sim:Advance(EconomyConfig.MarketDwell * EconomyConfig.IncomeTick, COARSE)
	t.eq(p:GetAttribute("SellRatePct"), EconomyConfig.MarketRatePct, "staying there earns the rate")
	sim:AssertNoErrors({ warnings = true })
end

tests["prompts: a stall hold or the own tank prompt opens the panel; another player's tank prompt does nothing; spam is bounded"] = function(
	t
)
	local sim = boot(t)
	local a = addPlayer(sim, 1)
	local b = addPlayer(sim, 2)
	local market = attachmentAt(sim, MARKET_PATH)
	local kiosk = attachmentAt(sim, KIOSK_PATH)
	local marketPrompt = market:FindFirstChild("SellPrompt")
	local kioskPrompt = kiosk:FindFirstChild("SellPrompt")
	t.ok(marketPrompt and kioskPrompt, "SellPrompt on every stall")
	local bonus = EconomyConfig.MarketRatePct - EconomyConfig.HomeRatePct
	t.eq(marketPrompt.ActionText, EconomyConfig.Prompt.Action)
	t.eq(marketPrompt.ObjectText, `Рыбный рынок · +{bonus}%`)
	t.eq(kioskPrompt.ObjectText, `Ларёк · +{bonus}%`)
	t.eq(marketPrompt.HoldDuration, EconomyConfig.Prompt.HoldDuration)
	t.eq(marketPrompt.MaxActivationDistance, EconomyConfig.Prompt.MaxDistance)
	t.eq(marketPrompt.RequiresLineOfSight, false)
	for _, point in EconomyConfig.SellPoints do
		t.ok(attachmentAt(sim, point.Path):FindFirstChild("SellPrompt"), `{point.Id}: a SellPrompt`)
	end

	sim:Teleport(a, market.WorldPosition + Vector3.new(0, 0, 4))
	local triggered = sim:HoldPrompt(a, marketPrompt)
	t.ok(triggered, "the market prompt triggers")
	local open = tankEvents(sim, a, "Open")
	t.eq(#open, 1)
	t.eq(open[1].Place, "Market")
	t.eq(open[1].Name, "Рыбный рынок")
	t.eq(open[1].RatePct, EconomyConfig.HomeRatePct, "just arrived: the panel opens, the rate comes with the dwell")

	local tankPrompt = baseOf(sim, a).Tank.Glass.PromptAttachment.TankPrompt
	t.eq(tankPrompt.ActionText, TankConfig.Prompt.Action)
	t.eq(tankPrompt.ObjectText, TankConfig.Prompt.Object)
	t.eq(tankPrompt.HoldDuration, TankConfig.Prompt.HoldDuration)
	t.eq(tankPrompt.MaxActivationDistance, TankConfig.Prompt.MaxDistance)
	t.eq(tankPrompt.RequiresLineOfSight, false)
	local near = tankPrompt.Parent.WorldPosition + Vector3.new(0, 0, -4)
	sim:Teleport(a, near)
	t.ok(sim:HoldPrompt(a, tankPrompt), "the own tank prompt triggers")
	open = tankEvents(sim, a, "Open")
	t.eq(#open, 2)
	t.eq(open[2].Place, "Tank")
	t.eq(open[2].Name, TankConfig.Prompt.Object)

	sim:Teleport(b, near)
	sim:HoldPrompt(b, tankPrompt)
	t.eq(#tankEvents(sim, b, "Open"), 0, "another player's tank prompt answers nothing")

	-- Spam in one frame: no more answers than the bucket holds.
	sim:Advance(3, COARSE)
	sim:Teleport(a, near)
	for _ = 1, 40 do
		sim:BeginHold(a, tankPrompt)
		sim:ReleasePrompt(a, tankPrompt)
	end
	local answered = #tankEvents(sim, a, "Open") - 2
	t.ok(answered >= 1 and answered <= TankConfig.Requests.Burst, `spam answered {answered} ≤ Burst times`)
	sim:AssertNoErrors({ warnings = true })
end

tests["exploits: junk uids dropped silently, someone else's fish / a double sell → Denied missing, 100 sells in a frame ≤ Burst"] = function(
	t
)
	local sim = boot(t)
	local a = addPlayer(sim, 1)
	local b = addPlayer(sim, 2)
	local mine = addFish(sim, a, "Perch", 1)
	addFish(sim, b, "Perch", 1)
	local theirs = addFish(sim, b, "SharkPup", 20)
	t.eq(theirs.Uid, "f2")
	local before = #sim:ClientEventsFor(a, "TankEvent")
	local money0 = leaderMoney(a)
	local junk = { 5, {}, { Uid = "f1" }, 0 / 0, math.huge, string.rep("f", 200), "f1x", "F1", "f", "f-1", "f 1", true }
	for _, value in junk do
		sim:FireServer(a, "TankSell", value)
	end
	sim:FireServer(a, "TankSell")
	sim:Flush()
	t.eq(#sim:ClientEventsFor(a, "TankEvent"), before, "junk is dropped without an answer")
	t.eq(leaderMoney(a), money0, "no money from junk")
	t.eq(slotOf(sim, a, 1):GetAttribute("FishUid"), "f1", "nothing sold")

	-- B's SharkPup is "f2" in B's tank; A has no "f2".
	sell(sim, a, "f2")
	t.eq(tankEvents(sim, a, "Denied")[1].Reason, "missing", "someone else's fish")
	t.eq(slotOf(sim, b, 2):GetAttribute("FishId"), "SharkPup", "B's fish untouched")

	-- A double sell in one frame: money once, the second answer is Denied missing.
	sim:Advance(3, COARSE)
	local money1 = leaderMoney(a)
	sell(sim, a, mine.Uid)
	sell(sim, a, mine.Uid)
	sim:Flush()
	local sold = tankEvents(sim, a, "Sold")
	t.eq(#sold, 1, "sold once")
	t.eq(leaderMoney(a) - money1, sold[1].Amount, "paid once")
	t.eq(tankEvents(sim, a, "Denied")[2].Reason, "missing")

	-- 100 sells of B's real fish in one frame: one sale, the answers bounded by the bucket.
	sim:Advance(3, COARSE)
	local answers = #sim:ClientEventsFor(b, "TankEvent")
	for _ = 1, 100 do
		sell(sim, b, "f1")
	end
	sim:Flush()
	local got = #sim:ClientEventsFor(b, "TankEvent") - answers
	t.ok(got >= 1 and got <= TankConfig.Requests.Burst, `{got} answers ≤ Burst`)
	t.eq(#tankEvents(sim, b, "Sold"), 1, "one sale")
	ledgerHolds(t, sim, service(sim, "DataService"):Get(b), "B")
	sim:AssertNoErrors({ warnings = true })
end

return tests
