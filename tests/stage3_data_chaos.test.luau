--[[
	Stage 3 wave 1 A — persistence under chaos (design §7.2b): the one test that exercises the
	retries, the coalescing and the per-key queue together. Headless players, the built
	Place1.rbxl, the sim DataStore failing 30 % of all requests:
	  1. three players, 10 virtual minutes of catches (TankService:AddFish, like the catch sink),
	     sales (TankSell), SaveSoon and income; the latency jumps between 0.05 s and 1–3 s; two
	     leaves, each while a save's UpdateAsync is in flight (latency 2.5 s), and a fast rejoin
	     on the same server 1–4 s later (a player kicked by a failed load rejoins too); then
	     Shutdown();
	  2. a restart on that DataStore with no failures; every player rejoins;
	  3. no duplicate Uids; the ledger holds; every lock is released after the final shutdown
	     (a lock the chaos left behind is taken over by the rejoin); each player's money — at
	     every same-server rejoin and after the restart — is ≥ the last value seen in the store at
	     a confirmed Committed and ≤ the money in memory at the last leave; no two writes to a key
	     closer than the write gap and no "added to queue" warning. Warnings: on the chaos server
	     only the failure ones (a lock wait / steal or a «lost» lock there would be a bug: one
	     server never waits for itself); after the restart only one steal per lock the chaos
	     left behind (fresh, not stale).

	Run: lune run tools/run_tests.luau stage3_data_chaos
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local PLACE = "Place1.rbxl"

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
local FishConfig = loadConfig("FishConfig")

local COARSE = 0.05
local STORE = "PlayerData_Studio"
local EPOCH = 1700000000
local GAP = DataConfig.MinWriteGap + DataConfig.GapEpsilon
local IDS = { 1, 2, 3 }
local MINUTES = 10

-- Failure warnings the chaos server is allowed to produce (anything else fails the test).
local CHAOS_WARNINGS = {
	"не удалась (попытка",
	"не удалось (попытка",
	"проверка DataStore не удалась",
}
local STEAL_WARNING = "занята другим сервером — забираю"
local LEAVE_LATENCY = 2.5

local function lcg(seed: number): (lo: number, hi: number) -> number
	local state = seed
	return function(lo: number, hi: number): number
		state = (state * 1103515245 + 12345) % 2147483648
		return lo + math.floor(state / 2147483648 * (hi - lo + 1))
	end
end

local function boot(t: any, opts: { [string]: any }?): any
	local o = opts or {}
	local sim = t.sim({ place = PLACE, dataStore = o.dataStore, epoch = o.epoch, seed = o.seed })
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

local function service(sim: any, name: string): any
	return sim:Require(sim:Find(`ServerScriptService.Services.{name}`))
end

local function join(sim: any, id: number): any
	return sim:AddPlayer({ UserId = id, Name = `Player{id}`, DisplayName = `Игрок{id}`, clientDelay = 1e9 })
end

local function inGame(sim: any, player: any): boolean
	for _, p in sim:GetPlayers() do
		if p == player then
			return true
		end
	end
	return false
end

local function peek(sim: any, id: number): any
	return sim.DataStore:Peek(STORE, `Player_{id}`)
end

local function filterWarnings(t: any, sim: any, expected: { string })
	local unexpected = {}
	for _, w in sim.Warnings do
		local ok = false
		for _, text in expected do
			if string.find(w.message, text, 1, true) then
				ok = true
				break
			end
		end
		if not ok then
			table.insert(unexpected, w.message)
		end
	end
	t.eq(#unexpected, 0, `only the expected failure warnings:\n{table.concat(unexpected, "\n")}`)
	sim:ClearErrors()
end

local function assertGaps(t: any, sim: any)
	local byKey = {}
	for _, call in sim.DataStore.Calls do
		if call.op == "UpdateAsync" then
			byKey[call.key] = byKey[call.key] or {}
			table.insert(byKey[call.key], call.time)
		end
	end
	for key, times in byKey do
		for i = 2, #times do
			t.ok(times[i] - times[i - 1] >= DataConfig.MinWriteGap - 1e-6, `{key}: writes ≥ the gap apart`)
		end
	end
end

local tests = {}

tests["chaos: 30 % failures, 10 minutes, leaves and rejoins, shutdown, restart → no dupes, ledger, bounded money"] = function(
	t
)
	local sim = boot(t)
	local random = lcg(20261017)
	local data = service(sim, "DataService")
	local tank = service(sim, "TankService")
	local rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"))
	local PlayerData = sim:Require(sim:Find("ServerScriptService.Lib.PlayerData"))
	sim.DataStore:SetFailRate(0.3)

	local players: { [number]: any } = {}
	local lastCommitted: { [number]: number } = {}
	local atLeave: { [number]: number } = {}
	local sessions: { [number]: number } = {}
	local leftBy: { [number]: boolean } = {} -- the last session ended with leave() (not a kick)
	-- Same-server rejoins after leave(): the money loaded and its bounds at that moment.
	local rejoins: { { id: number, money: number, low: number, high: number } } = {}
	data.Committed:Connect(function(player, _seq)
		local saved = peek(sim, player.UserId)
		if type(saved) == "table" then
			lastCommitted[player.UserId] = saved.Money
		end
	end)
	data.Loaded:Connect(function(player, loaded)
		local id = player.UserId
		if leftBy[id] then
			leftBy[id] = false
			table.insert(
				rejoins,
				{ id = id, money = loaded.Money, low = lastCommitted[id] or 0, high = atLeave[id] or 0 }
			)
		end
	end)
	local function money(player: any): number?
		local live = data:Get(player)
		return live and live.Money
	end
	local function enter(id: number)
		players[id] = join(sim, id)
		sessions[id] = (sessions[id] or 0) + 1
	end
	local function leave(id: number)
		local p = players[id]
		if p and inGame(sim, p) then
			atLeave[id] = money(p) or atLeave[id]
			leftBy[id] = true
			sim:RemovePlayer(p)
		end
	end
	-- Is a save's UpdateAsync of this player on the wire right now (latency LEAVE_LATENCY)?
	local function onTheWire(id: number): boolean
		local p = players[id]
		local rec = p and data._recordFor(p)
		if not (rec and rec.InFlight) then
			return false
		end
		local last = nil
		for _, call in sim.DataStore.Calls do
			if call.op == "UpdateAsync" and call.key == `Player_{id}` then
				last = call.time
			end
		end
		return last ~= nil and sim:Time() - last < LEAVE_LATENCY - 0.2
	end
	for _, id in IDS do
		enter(id)
	end

	local species = {}
	for _, def in FishConfig.Fish do
		table.insert(species, def)
	end
	local leaves = { [math.floor(MINUTES * 60 * 0.3)] = 1, [math.floor(MINUTES * 60 * 0.6)] = 2 }
	local away: { [number]: number } = {}
	local leaving: { [number]: number } = {} -- who → the deadline of the leave
	local wireLeaves = 0
	for second = 1, MINUTES * 60 do
		sim:Advance(1, COARSE)
		-- The latency jumps now and then (not while a leave waits for its save on the wire).
		if second % 20 == 0 and next(leaving) == nil then
			sim.DataStore:SetLatency(if random(1, 3) == 1 then random(10, 30) / 10 else 0.05)
		end
		-- A leave: a SaveSoon on a slow wire, the leave while its UpdateAsync is in flight, a
		-- rejoin a few seconds later (a same-server fast rejoin behind the in-flight save).
		local who = leaves[second]
		if who and players[who] and inGame(sim, players[who]) then
			sim.DataStore:SetLatency(LEAVE_LATENCY)
			leaving[who] = second + 20
			sim:Run(function()
				data:SaveSoon(players[who])
			end)
		end
		for id, deadline in leaving do
			local wire = onTheWire(id)
			if wire or second >= deadline or not (players[id] and inGame(sim, players[id])) then
				leaving[id] = nil
				if wire then
					wireLeaves += 1
				end
				leave(id)
				away[id] = second + random(1, 4)
			end
		end
		for _, id in IDS do
			local p = players[id]
			if away[id] and second >= away[id] then
				away[id] = nil
				enter(id)
			elseif not away[id] and p and not inGame(sim, p) then
				-- Kicked (a failed load or a lost lock): back in a little while.
				away[id] = second + random(5, 15)
			elseif not away[id] and p and data:CanWrite(p) and random(1, 3) == 1 then
				local roll = random(1, 10)
				if roll <= 5 then
					local def = species[random(1, #species)]
					local kg = def.MinKg + (def.MaxKg - def.MinKg) * random(0, 100) / 100
					local value, income = rules.Price(def.Id, kg, nil)
					sim:Run(function()
						tank:AddFish(
							p,
							{ Id = def.Id, Rarity = def.Rarity, Kg = kg, Value = value, Income = income },
							"catch"
						)
					end)
				elseif roll <= 8 then
					local live = data:Get(p)
					local fish = live and live.Tank[random(1, math.max(1, #live.Tank))]
					if fish then
						sim:FireServer(p, "TankSell", fish.Uid)
					end
				else
					sim:Run(function()
						data:SaveSoon(p)
					end)
				end
			end
		end
	end
	-- One more catch each (the random sales may have emptied a tank: the uid checks need fish).
	local perch = FishConfig.Fish[1]
	local perchValue, perchIncome = rules.Price(perch.Id, perch.MinKg, nil)
	for _, id in IDS do
		local p = players[id]
		if p and inGame(sim, p) and data:CanWrite(p) then
			sim:Run(function()
				tank:AddFish(
					p,
					{ Id = perch.Id, Rarity = perch.Rarity, Kg = perch.MinKg, Value = perchValue, Income = perchIncome },
					"catch"
				)
			end)
		end
	end
	for _, id in IDS do
		local p = players[id]
		if p and inGame(sim, p) then
			atLeave[id] = money(p) or atLeave[id]
		end
	end
	-- The chaos really happened: many failed requests, many commits, fish caught and sold.
	local failed, writes = 0, 0
	for _, call in sim.DataStore.Calls do
		if call.op == "UpdateAsync" then
			writes += 1
			if call.failed then
				failed += 1
			end
		end
	end
	t.ok(writes >= 30 and failed >= 8, `{writes} writes, {failed} of them failed`)
	t.eq(wireLeaves, 2, "both leaves happened while a save was on the wire")
	t.ok(#rejoins >= 2, `{#rejoins} same-server rejoins after a leave`)
	for _, r in rejoins do
		t.ok(
			r.money >= r.low and r.money <= r.high,
			`player {r.id} rejoined with {r.money} (last committed {r.low}, at leave {r.high})`
		)
	end
	for _, id in IDS do
		local live = players[id] and data:Get(players[id])
		if live then
			t.ok(live.Stats.Sold >= 3 and #live.Tank >= 1, `player {id} caught and sold ({live.Stats.Sold} sold)`)
		end
	end
	local result = sim:Shutdown()
	t.ok(result.completed, "the chaos shutdown completed")
	assertGaps(t, sim)
	filterWarnings(t, sim, CHAOS_WARNINGS)
	sim:AssertNoErrors()
	t.ok(sessions[1] >= 2 and sessions[2] >= 2, "two leaves and rejoins happened")

	-- A restart with no failures: everyone rejoins.
	local later = boot(t, {
		dataStore = sim.DataStore:Snapshot(),
		epoch = EPOCH + math.floor(sim:Time()) + 5,
		seed = 7,
	})
	local laterData = service(later, "DataService")
	-- Locks the chaos left behind (its final saves failed): each one is waited for and stolen.
	local now = math.floor(later.workspace:GetServerTimeNow())
	local leftLocks = 0
	for _, id in IDS do
		local session = peek(later, id).Session
		if session and now - session.T < DataConfig.LockStale then
			leftLocks += 1
		end
	end
	-- The money each player loads with (income goes on while the others wait for their locks).
	local loadedMoney: { [number]: number } = {}
	laterData.Loaded:Connect(function(player, loaded)
		loadedMoney[player.UserId] = loaded.Money
	end)
	local back = {}
	for _, id in IDS do
		back[id] = join(later, id)
	end
	later:WaitFor(function()
		for _, id in IDS do
			if back[id]:GetAttribute("DataMode") ~= "Ready" then
				return false
			end
		end
		return true
	end, DataConfig.LockWait.Tries * DataConfig.LockWait.Every + 20, COARSE)
	for _, id in IDS do
		local p = back[id]
		t.eq(p:GetAttribute("DataMode"), "Ready", `player {id} loads after the restart`)
		local live = laterData:Get(p)
		local seen = {}
		for _, fish in live.Tank do
			t.ok(not seen[fish.Uid], `player {id}: unique uid {fish.Uid}`)
			seen[fish.Uid] = true
			local n = tonumber(string.match(fish.Uid, "^f(%d+)$"))
			t.ok(n and n < live.NextUid, `player {id}: {fish.Uid} below NextUid {live.NextUid}`)
		end
		local ok, expected = PlayerData.Ledger(live)
		t.ok(ok, `player {id}: the ledger holds ({live.Money} vs {expected})`)
		local low, high, got = lastCommitted[id] or 0, atLeave[id] or 0, loadedMoney[id] or -1
		t.ok(got >= low, `player {id}: loaded money {got} ≥ last committed {low}`)
		t.ok(got <= high, `player {id}: loaded money {got} ≤ in memory at leave {high}`)
	end
	local closed = later:Shutdown()
	t.ok(closed.completed, "the final shutdown completed")
	for _, id in IDS do
		local saved = peek(later, id)
		t.eq(saved.Session, nil, `player {id}: every lock released`)
		local ok = PlayerData.Ledger(saved)
		t.ok(ok, `player {id}: the stored ledger holds`)
	end
	assertGaps(t, later)
	local steals = 0
	for _, w in later.Warnings do
		if string.find(w.message, STEAL_WARNING, 1, true) then
			steals += 1
		end
	end
	t.eq(steals, leftLocks, "one steal per fresh lock the chaos left behind")
	filterWarnings(t, later, { STEAL_WARNING })
	later:AssertNoErrors({ warnings = true })
end

return tests
