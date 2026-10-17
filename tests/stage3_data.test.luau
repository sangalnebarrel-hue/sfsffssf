--[[
	Stage 3 wave 1 A — persistence (design §2, §7.2), run inside RbxSim against the built
	Place1.rbxl with headless players (clientDelay = 1e9) and the sim DataStore:
	  • load: a new player gets the template and the lock (LoadId, Server = the boot token); load
	    retries; 5 failures → kicked (≈ 30 s), nothing written, the record released before the
	    kick; V = 99 → kicked «Игра обновилась», untouched; a non-table value → kicked, untouched;
	  • locks: a fresh foreign lock → waits ≈ 24 s, steals, one warn; a stale lock is taken at
	    once; the lock lost mid-session → the next save is cancelled and the player kicked;
	  • the holes of critique_backend: B-1 (a released or deleted key is «lost», never
	    recreated), B-2 (an old record of a same-server rejoin cannot overwrite the new session),
	    B-3 (a same-server fast rejoin behind a retrying final save), B-5 (runtime junk is dropped
	    with one warn; a forced 104 → one strict retry), B-6 (future content survives load →
	    play → leave);
	  • cadence: no two writes to a key closer than the write gap (from the call log), no
	    "added to queue" warning; coalescing (SaveSoon while queued is dropped, after the
	    snapshot → exactly one follow-up), Committed in order;
	  • leave: the final save releases the lock; a leave during the load → a release-only save;
	    the leave save retried within LeaveSaveWindow; a release retry that finds no lock stops
	    quietly;
	  • shutdown: one final write per key, every lock released, well inside CloseBudget; a player
	    mid-load at shutdown → the lock is released (B-13);
	  • modes: Memory (Studio without API access) — one warn, DataMode "Memory", zero writes, an
	    instant shutdown; Broken (an error in Start) — plays, never writes;
	  • hygiene: a garbage save is sanitized (warns expected); nothing left behind after leave.
	Every test that leaves data checks the ledger (Money == StartMoney + Earned − Spent).

	Run: lune run tools/run_tests.luau stage3_data
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
local EconomyConfig = loadConfig("EconomyConfig")
local RodConfig = loadConfig("RodConfig")
local TankConfig = loadConfig("TankConfig")

local COARSE = 0.05
local STORE = "PlayerData_Studio" -- the sim reports Studio (DataService.StoreName)
local EPOCH = 1700000000
local GAP = DataConfig.MinWriteGap + DataConfig.GapEpsilon

--------------------------------------------------------------------------------
-- Sim helpers
--------------------------------------------------------------------------------

type Patch = { path: string, from: string, to: string }

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
	if o.before then
		o.before(sim)
	end
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

-- A server restart on the old server's DataStore: a later clock and a new seed (a new token).
local function restart(t: any, old: any, gap: number, seed: number?): any
	return boot(t, nil, {
		dataStore = old.DataStore:Snapshot(),
		epoch = EPOCH + math.floor(old:Time()) + gap,
		seed = seed or 2,
	})
end

local function service(sim: any, name: string): any
	return sim:Require(sim:Find(`ServerScriptService.Services.{name}`))
end

local function join(sim: any, id: number): any
	return sim:AddPlayer({ UserId = id, Name = `Player{id}`, DisplayName = `Игрок{id}`, clientDelay = 1e9 })
end

local function waitMode(sim: any, player: any, timeout: number?): string?
	sim:WaitFor(function()
		return player:GetAttribute("DataMode") ~= "Loading"
	end, timeout or 5, COARSE)
	return player:GetAttribute("DataMode")
end

-- A headless player, waited until the data is loaded.
local function addPlayer(sim: any, id: number): any
	local p = join(sim, id)
	waitMode(sim, p)
	sim:Advance(0.1)
	return p
end

local function key(id: number): string
	return `Player_{id}`
end

local function peek(sim: any, id: number): any
	return sim.DataStore:Peek(STORE, key(id))
end

local function template(changes: { [string]: any }?): { [string]: any }
	local data: { [string]: any } = {
		V = 1,
		Money = 0,
		RodId = RodConfig.StartRod,
		TankSlots = TankConfig.StartSlots,
		LockLevel = 0,
		Upgrades = {},
		Tank = {},
		NextUid = 1,
		Stats = { Caught = 0, Sold = 0, Earned = 0, Spent = 0, Species = {} },
		Created = EPOCH,
		LastOnline = EPOCH,
		SaveCount = 1,
	}
	for k, v in changes or {} do
		data[k] = v
	end
	return data
end

local function savedFish(id: string, uid: string, slot: number, extra: { [string]: any }?): { [string]: any }
	local f: { [string]: any } = { Uid = uid, Id = id, Kg = 1.2, Age = 0, Slot = slot, CaughtAt = EPOCH }
	for k, v in extra or {} do
		f[k] = v
	end
	return f
end

local function foreignLock(sim: any, ageSeconds: number): { [string]: any }
	return {
		Id = "11111111-2222-4333-8444-555555555555",
		Server = "other-server-token",
		Job = "other-job",
		T = math.floor(sim.workspace:GetServerTimeNow()) - ageSeconds,
	}
end

-- Writes (UpdateAsync / SetAsync, failed and cancelled ones too) per key, in order.
local function writesByKey(sim: any): { [string]: { number } }
	local out = {}
	for _, call in sim.DataStore.Calls do
		if call.op == "UpdateAsync" or call.op == "SetAsync" or call.op == "RemoveAsync" then
			local list = out[call.key]
			if not list then
				list = {}
				out[call.key] = list
			end
			table.insert(list, call.time)
		end
	end
	return out
end

local function writes(sim: any, id: number): number
	return #(writesByKey(sim)[key(id)] or {})
end

-- No two writes to one key closer than the write gap (B-9).
local function assertGaps(t: any, sim: any)
	for k, times in writesByKey(sim) do
		for i = 2, #times do
			t.ok(
				times[i] - times[i - 1] >= DataConfig.MinWriteGap - 1e-6,
				`{k}: writes {i - 1} and {i} are {times[i] - times[i - 1]} s apart (≥ {DataConfig.MinWriteGap})`
			)
		end
	end
end

-- Takes the warnings containing `text` out of sim.Warnings; returns how many there were.
local function takeWarnings(sim: any, text: string): number
	local n = 0
	for i = #sim.Warnings, 1, -1 do
		if string.find(sim.Warnings[i].message, text, 1, true) then
			table.remove(sim.Warnings, i)
			n += 1
		end
	end
	return n
end

local function kicksOf(sim: any, player: any): { string }
	local out = {}
	for _, kick in sim.Kicks do
		if kick.player == player then
			table.insert(out, kick.message)
		end
	end
	return out
end

local function ledgerHolds(t: any, sim: any, value: any, what: string)
	local PlayerData = sim:Require(sim:Find("ServerScriptService.Lib.PlayerData"))
	local ok, expected = PlayerData.Ledger(value)
	t.ok(ok, `{what}: the ledger holds (Money {value.Money}, expected {expected})`)
end

-- Shutdown, then: every save in the store keeps its ledger and no lock of this server.
local function finish(t: any, sim: any)
	local result = sim:Shutdown()
	t.ok(result.completed, "Shutdown completed")
	local token = service(sim, "DataService").Token
	for _, k in sim.DataStore:Keys(STORE) do
		local value = sim.DataStore:Peek(STORE, k)
		if type(value) == "table" and value.Stats then
			ledgerHolds(t, sim, value, k)
			t.ok(value.Session == nil or value.Session.Server ~= token, `{k}: no lock of this server left`)
		end
	end
	assertGaps(t, sim)
end

-- The player leaves; the save after the final write lands.
local function peekAfter(sim: any, player: any): any
	sim:RemovePlayer(player)
	sim:Advance(GAP + 1, COARSE)
	return peek(sim, player.UserId)
end

local function setMoney(sim: any, player: any, money: number)
	service(sim, "EconomyService"):SetMoneyForTest(player, money)
end

--------------------------------------------------------------------------------
-- Tests: load
--------------------------------------------------------------------------------

local tests = {}

tests["load: a new player gets the template and the lock (LoadId, Server = the boot token)"] = function(t)
	local sim = boot(t)
	local data = service(sim, "DataService")
	t.eq(data.StoreName, STORE)
	t.eq(data:Mode(), "DataStore")
	local p = join(sim, 1)
	t.eq(p:GetAttribute("DataMode"), "Loading", "loading at first")
	t.eq(data:CanWrite(p), false, "no writes while loading")
	t.eq(waitMode(sim, p), "Ready")
	t.eq(data:CanWrite(p), true)
	t.eq(data:IsLoaded(p), true)
	local saved = peek(sim, 1)
	local rec = data._recordFor(p)
	t.eq(saved.V, 1)
	t.eq(saved.Money, EconomyConfig.StartMoney)
	t.eq(saved.RodId, RodConfig.StartRod)
	t.eq(saved.TankSlots, TankConfig.StartSlots)
	t.eq(#saved.Tank, 0)
	t.eq(saved.Session.Id, rec.LoadId, "the lock carries this load's id")
	t.eq(saved.Session.Server, data.Token, "… and this server's boot token")
	t.eq(type(saved.Session.Job), "string")
	t.ok(saved.Created > 0, "Created stamped")
	t.eq(data:Get(p), rec.Data, "Get = the live table")
	t.eq(data:Get(p).Session.Id, rec.LoadId, "the live table is UpdateAsync's committed value")
	t.eq(p:GetAttribute("Money"), 0)
	t.eq(p.leaderstats:GetChildren()[1].Name, EconomyConfig.Leaderstats.Money, "«Деньги» first")
	t.eq(writes(sim, 1), 1, "one write for the load")
	-- WaitLoaded answers at once when loaded, nil for strangers.
	t.eq(
		sim:Run(function()
			return data:WaitLoaded(p, 1)
		end),
		rec.Data
	)
	finish(t, sim)
	sim:AssertNoErrors({ warnings = true })
end

tests["load: retried after failures with backoff and the write gap; WaitLoaded waits"] = function(t)
	local sim = boot(t)
	local data = service(sim, "DataService")
	sim.DataStore:FailNext(2, nil, { "UpdateAsync" })
	local p = join(sim, 1)
	local waited: any = "pending"
	local env = sim:Env()
	sim:Run(function()
		env.task.spawn(function()
			waited = data:WaitLoaded(p, 30)
		end)
	end)
	t.eq(waited, "pending", "WaitLoaded waits while loading")
	t.eq(waitMode(sim, p, 30), "Ready", "loaded after two failures")
	sim:Flush()
	t.eq(waited, data:Get(p), "WaitLoaded resumed with the data")
	t.eq(writes(sim, 1), 3, "three attempts")
	t.eq(takeWarnings(sim, "загрузка игрока 1 не удалась"), 2, "one warn per failed attempt")
	finish(t, sim)
	sim:AssertNoErrors({ warnings = true })
end

tests["load: five failures → kicked (≈ 30 s), nothing written, the record released before the kick"] = function(t)
	local sim = boot(t)
	local data = service(sim, "DataService")
	sim.DataStore:FailNext(DataConfig.Retry.Load, nil, { "UpdateAsync" })
	local recordAtLeave = "unset"
	local players = sim.game:GetService("Players")
	players.PlayerRemoving:Connect(function(player)
		recordAtLeave = data._recordFor(player)
	end)
	local p = join(sim, 1)
	local started = sim:Time()
	sim:WaitFor(function()
		return #sim.Kicks > 0
	end, 60, COARSE)
	local kicks = kicksOf(sim, p)
	t.eq(#kicks, 1, "kicked once")
	t.eq(kicks[1], DataConfig.Texts.LoadFailed)
	local took = sim:Time() - started
	t.ok(took >= 4 * GAP and took <= 45, `after ≈ 30 s of retries ({took})`)
	sim:Flush()
	t.eq(recordAtLeave, nil, "the record was released before the kick")
	t.eq(peek(sim, 1), nil, "nothing written")
	t.eq(writes(sim, 1), DataConfig.Retry.Load)
	t.eq(takeWarnings(sim, "загрузка игрока 1 не удалась"), DataConfig.Retry.Load)
	sim:Advance(GAP + 1, COARSE)
	for k, size in data._debugSizes() do
		t.eq(size, 0, `_debugSizes().{k}`)
	end
	sim:AssertNoErrors({ warnings = true })
end

tests["load: V = 99 → kicked «Игра обновилась», untouched; a non-table value → kicked, untouched"] = function(
	t
)
	local sim = boot(t)
	local newer = template({ V = 99, Money = 5, Future = { "x" } })
	sim.DataStore:Poke(STORE, key(1), newer)
	sim.DataStore:Poke(STORE, key(2), "corrupted")
	local a = join(sim, 1)
	local b = join(sim, 2)
	sim:Advance(1, COARSE)
	t.eq(kicksOf(sim, a)[1], DataConfig.Texts.TooNew)
	t.eq(kicksOf(sim, b)[1], DataConfig.Texts.LoadFailed)
	t.eq(peek(sim, 1), newer, "the newer data untouched")
	t.eq(peek(sim, 2), "corrupted", "the corrupt value untouched")
	t.eq(takeWarnings(sim, "не таблица"), 1, "one warn for the corrupt value")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Tests: locks
--------------------------------------------------------------------------------

tests["locks: a fresh foreign lock → waits ≈ 24 s, then steals with one warn"] = function(t)
	local sim = boot(t)
	local data = service(sim, "DataService")
	sim.DataStore:Poke(
		STORE,
		key(1),
		template({
			Money = 7,
			Stats = {
				Caught = 0,
				Sold = 0,
				Earned = 7,
				Spent = 0,
				Species = {},
			},
			Session = foreignLock(sim, 1),
		})
	)
	local p = join(sim, 1)
	local started = sim:Time()
	sim:Advance(DataConfig.LockWait.Every * 2, COARSE)
	t.eq(p:GetAttribute("DataMode"), "Loading", "still waiting for the other server")
	t.eq(waitMode(sim, p, 40), "Ready")
	local took = sim:Time() - started
	local wait = DataConfig.LockWait.Tries * DataConfig.LockWait.Every
	t.ok(took >= wait and took <= wait + 6, `stole after ≈ {wait} s ({took})`)
	t.eq(takeWarnings(sim, "занята другим сервером — забираю"), 1, "one warn")
	t.eq(peek(sim, 1).Session.Id, data._recordFor(p).LoadId, "the lock is ours")
	t.eq(p:GetAttribute("Money"), 7, "the data came along")
	t.eq(writes(sim, 1), DataConfig.LockWait.Tries + 1)
	finish(t, sim)
	sim:AssertNoErrors({ warnings = true })
end

tests["locks: a stale lock (T − 200 s) is taken at once"] = function(t)
	local sim = boot(t)
	sim.DataStore:Poke(STORE, key(1), template({ Session = foreignLock(sim, 200) }))
	local p = join(sim, 1)
	t.eq(waitMode(sim, p, 1), "Ready", "no waiting for a stale lock")
	t.eq(writes(sim, 1), 1)
	finish(t, sim)
	sim:AssertNoErrors({ warnings = true })
end

tests["locks: the lock lost mid-session → the next save is cancelled and the player kicked"] = function(t)
	local sim = boot(t)
	local data = service(sim, "DataService")
	local p = addPlayer(sim, 1)
	local stolen = peek(sim, 1)
	stolen.Session = foreignLock(sim, 0)
	stolen.Money = 999
	stolen.Stats.Earned = 999
	sim.DataStore:Poke(STORE, key(1), stolen)
	setMoney(sim, p, 5)
	sim:Run(function()
		data:SaveSoon(p)
	end)
	sim:Advance(GAP + 1, COARSE)
	t.eq(
		kicksOf(sim, p)[1],
		DataConfig.Texts.Stolen,
		"kicked: «Ты зашёл в игру на другом сервере…»"
	)
	t.eq(peek(sim, 1), stolen, "the other server's data untouched")
	t.eq(takeWarnings(sim, "забрал другой сервер"), 1)
	sim:Advance(GAP + 1, COARSE)
	for k, size in data._debugSizes() do
		t.eq(size, 0, `_debugSizes().{k}`)
	end
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Tests: the holes of critique_backend
--------------------------------------------------------------------------------

tests["B-1: a key released by another server (Session = nil) or deleted → our save is cancelled, never recreated"] = function(
	t
)
	local sim = boot(t)
	local data = service(sim, "DataService")
	local a = addPlayer(sim, 1)
	local b = addPlayer(sim, 2)
	local newer = peek(sim, 1)
	newer.Session = nil
	newer.Money = 777
	newer.Stats.Earned = 777
	sim.DataStore:Poke(STORE, key(1), newer)
	sim.DataStore:Poke(STORE, key(2), nil)
	sim:Run(function()
		data:SaveSoon(a)
		data:SaveSoon(b)
	end)
	sim:Advance(GAP + 1, COARSE)
	t.eq(peek(sim, 1), newer, "the newer data of the other server untouched")
	t.eq(peek(sim, 2), nil, "a deleted key is not recreated")
	t.eq(kicksOf(sim, a)[1], DataConfig.Texts.Stolen)
	t.eq(kicksOf(sim, b)[1], DataConfig.Texts.Stolen)
	t.eq(takeWarnings(sim, "забрал другой сервер"), 2)
	sim:AssertNoErrors({ warnings = true })
end

tests["B-2: a same-server rejoin — the old record's save is cancelled, the new session's money untouched"] = function(
	t
)
	local sim = boot(t)
	local data = service(sim, "DataService")
	local first = addPlayer(sim, 1)
	setMoney(sim, first, 100)
	local oldRecord = data._recordFor(first)
	sim:RemovePlayer(first)
	sim:Advance(GAP + 1, COARSE)
	t.eq(peek(sim, 1).Session, nil, "released on leave")
	local second = addPlayer(sim, 1)
	t.eq(second:GetAttribute("Money"), 100, "the money came back")
	setMoney(sim, second, 500)
	sim:Run(function()
		data:SaveSoon(second)
	end)
	sim:Advance(GAP + 1, COARSE)
	t.eq(peek(sim, 1).Money, 500)
	-- A leaked save of the previous session (same server token, old LoadId).
	oldRecord.Data.Money = 100
	local result = sim:Run(function()
		return data._saveRecordForTest(oldRecord)
	end, nil, 30)
	t.eq(result, "lost", "the old record's save is cancelled")
	t.eq(peek(sim, 1).Money, 500, "the new session's money untouched")
	t.eq(peek(sim, 1).Session.Id, data._recordFor(second).LoadId, "the new session keeps its lock")
	t.eq(takeWarnings(sim, "потерян"), 1)
	t.eq(#kicksOf(sim, second), 0, "the new session plays on")
	finish(t, sim)
	sim:AssertNoErrors({ warnings = true })
end

tests["B-3: a same-server fast rejoin while the old final save retries → the new session still loads and saves"] = function(
	t
)
	local sim = boot(t)
	local data = service(sim, "DataService")
	local first = addPlayer(sim, 1)
	setMoney(sim, first, 40)
	sim:Advance(GAP + 0.5, COARSE)
	sim.DataStore:FailNext(2, nil, { "UpdateAsync" })
	sim:RemovePlayer(first)
	sim:Advance(0.2)
	local second = join(sim, 1)
	t.eq(waitMode(sim, second, 40), "Ready", "the rejoin loads after the old final save")
	t.eq(second:GetAttribute("Money"), 40, "with the money the final save wrote")
	t.eq(
		takeWarnings(sim, "сохранение игрока 1 не удалось"),
		2,
		"the two failed final-save attempts"
	)
	setMoney(sim, second, 90)
	sim:Run(function()
		data:SaveSoon(second)
	end)
	sim:Advance(GAP + 1, COARSE)
	t.eq(peek(sim, 1).Money, 90, "the new session saves")
	t.eq(peek(sim, 1).Session.Id, data._recordFor(second).LoadId)
	finish(t, sim)
	sim:AssertNoErrors({ warnings = true })
end

tests["B-5: runtime junk in the live table → the save still commits a valid value with one warn; a forced 104 → one strict retry"] = function(
	t
)
	local sim = boot(t)
	sim.DataStore:Poke(STORE, key(1), template({ Future = { Level = 3 } }))
	local data = service(sim, "DataService")
	local tank = service(sim, "TankService")
	local p = addPlayer(sim, 1)
	local rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"))
	local value, income = rules.Price("Perch", 1, nil)
	sim:Run(function()
		tank:AddFish(p, { Id = "Perch", Rarity = "Common", Kg = 1, Value = value, Income = income }, "catch")
	end)
	local live = data:Get(p)
	live.Tank[1].Junk = sim.workspace -- an Instance: not JSON
	live.Stats.Bad = function() end
	live._runtime = { cache = true } -- "_" keys are never written (silently)
	sim:Advance(GAP, COARSE)
	sim:Run(function()
		data:SaveSoon(p)
	end)
	sim:Advance(1, COARSE)
	local saved = peek(sim, 1)
	t.eq(saved.Tank[1].Junk, nil, "the junk is not written")
	t.eq(saved.Stats.Bad, nil)
	t.eq(saved._runtime, nil)
	t.eq(saved.Tank[1].Id, "Perch", "the fish is")
	t.eq(saved.Future, { Level = 3 }, "an unknown JSON field of a newer server is kept")
	t.eq(takeWarnings(sim, "сохранение: выброшено"), 1, "one warn for the dropped fields")
	-- The same junk again: no new warn (one per field path per session).
	sim:Advance(GAP, COARSE)
	sim:Run(function()
		data:SaveSoon(p)
	end)
	sim:Advance(1, COARSE)
	t.eq(takeWarnings(sim, "сохранение: выброшено"), 0, "no repeated warn")

	-- A forced 104: one warn, one strict retry (unknown fields dropped), committed.
	live.Tank[1].Junk = nil
	live.Stats.Bad = nil
	sim:Advance(GAP, COARSE)
	local before = writes(sim, 1)
	sim.DataStore:FailNext(1, "104: Cannot store Dictionary in data store (value.Future)", { "UpdateAsync" })
	local committed = data:CommittedSeq(p)
	sim:Run(function()
		data:SaveSoon(p)
	end)
	sim:Advance(GAP + 1, COARSE)
	t.eq(writes(sim, 1) - before, 2, "the failed write and one strict retry")
	t.ok(data:CommittedSeq(p) > committed, "committed")
	t.eq(peek(sim, 1).Future, nil, "strict: unknown fields dropped")
	t.eq(data._recordFor(p).Strict, true)
	t.eq(takeWarnings(sim, "повтор без незнакомых полей"), 1)
	t.eq(takeWarnings(sim, "Future: незнакомое поле → выброшено (strict)"), 1, "what strict dropped is logged")
	finish(t, sim)
	sim:AssertNoErrors({ warnings = true })
end

tests["B-6: future content survives load → play → leave (rolling updates)"] = function(t)
	local sim = boot(t)
	local fish = {}
	for i = 1, 12 do
		table.insert(fish, savedFish("Perch", `f{i}`, i, { Age = i }))
	end
	table.insert(fish, savedFish("FutureFish", "f13", 13, { Aura = "storm" }))
	table.insert(fish, savedFish("Perch", "f14", 14, { Mutation = "Cosmic" }))
	local future = template({
		RodId = "RodFuture",
		TankSlots = 16,
		Tank = fish,
		NextUid = 15,
		Upgrades = { Shield = 3, Dog = true },
		Pets = { "cat", "dog" },
		Stats = { Caught = 14, Sold = 0, Earned = 0, Spent = 0, Species = { Perch = 13, FutureFish = 1 }, Streak = 4 },
	})
	sim.DataStore:Poke(STORE, key(1), future)
	local p = addPlayer(sim, 1)
	t.eq(p:GetAttribute("TankSlots"), TankConfig.MaxSlots, "runtime: at most MaxSlots displays")
	t.eq(p:GetAttribute("TankCount"), 12, "12 known fish in 12 displays; the 13th and 14th wait")
	sim:Advance(5, COARSE)
	local saved = peekAfter(sim, p)
	t.eq(saved.RodId, "RodFuture", "an unknown rod is kept")
	t.eq(saved.TankSlots, 16, "the newer server's slot count is kept")
	t.eq(#saved.Tank, 14, "nothing dropped, nothing sold")
	t.eq(saved.Pets, { "cat", "dog" }, "an unknown top-level field is kept")
	t.eq(saved.Upgrades, { Shield = 3, Dog = true })
	t.eq(saved.Stats.Streak, 4, "an unknown Stats field is kept")
	local byUid = {}
	for _, f in saved.Tank do
		byUid[f.Uid] = f
	end
	t.eq(byUid.f13.Id, "FutureFish")
	t.eq(byUid.f13.Aura, "storm")
	t.eq(byUid.f14.Mutation, "Cosmic", "an unknown mutation is kept")
	t.eq(byUid.f14.Slot, 14, "a dormant fish keeps its slot")
	t.ok(byUid.f1.Age > 1, "the active fish grew while mounted")
	t.eq(saved.Session, nil)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Tests: cadence and coalescing
--------------------------------------------------------------------------------

tests["cadence: autosaves never closer than the write gap, no queue warning, no per-player connections"] = function(t)
	local sim = boot(t, {
		{ path = "ReplicatedStorage.Shared.Config.DataConfig", from = "AutoSave = 60,", to = "AutoSave = 10," },
	})
	local data = service(sim, "DataService")
	local connections = sim:CountConnections("server")
	local a = addPlayer(sim, 1)
	local b = addPlayer(sim, 2)
	local perPlayer = sim:CountConnections("server") - connections
	-- SaveSoon at awkward moments (right after a load, during the gap): never a gap violation.
	for _ = 1, 8 do
		sim:Run(function()
			data:SaveSoon(a)
		end)
		sim:Advance(3.7, COARSE)
	end
	sim:Advance(40, COARSE)
	t.ok(writes(sim, 1) >= 6, `player 1 saved regularly ({writes(sim, 1)} writes)`)
	t.ok(writes(sim, 2) >= 4, `player 2 autosaved every AutoSave ({writes(sim, 2)} writes)`)
	assertGaps(t, sim)
	t.eq(sim:CountConnections("server") - connections, perPlayer, "no connections pile up")
	local c = sim:CountConnections("server")
	sim:RemovePlayer(a)
	sim:RemovePlayer(b)
	sim:Advance(0.5)
	t.ok(sim:CountConnections("server") <= c, "leaving drops connections at once (none from DataService)")
	finish(t, sim)
	sim:AssertNoErrors({ warnings = true })
end

tests["coalescing: SaveSoon while queued is one write; after the snapshot → exactly one follow-up; Committed in order"] = function(
	t
)
	local sim = boot(t)
	local data = service(sim, "DataService")
	local p = addPlayer(sim, 1)
	local committed = {}
	data.Committed:Connect(function(player, seq)
		if player == p then
			table.insert(committed, seq)
		end
	end)
	local before = writes(sim, 1)
	local seqs = sim:Run(function()
		return { data:SaveSoon(p), data:SaveSoon(p), data:SaveSoon(p) }
	end)
	t.eq(seqs, { 1, 2, 3 }, "SaveSoon returns increasing seqs")
	sim:Advance(GAP + 1, COARSE)
	t.eq(writes(sim, 1) - before, 1, "three SaveSoon while waiting for the gap → one write")
	sim:Flush()
	t.eq(committed, { 3 }, "the commit covers every SaveSoon up to 3")
	t.eq(data:CommittedSeq(p), 3)

	-- A SaveSoon that lands after the snapshot (inside the save's transform): one follow-up.
	local armed = true
	data:OnSerialize(function(player)
		if armed and player == p then
			armed = false
			data:SaveSoon(player)
		end
		return nil
	end)
	sim:Run(function()
		data:SaveSoon(p)
	end)
	sim:Advance(GAP * 2 + 1, COARSE)
	sim:Flush()
	t.eq(writes(sim, 1) - before, 3, "the save and exactly one follow-up")
	t.eq(committed, { 3, 4, 5 }, "Committed in order")
	t.eq(data:CommittedSeq(p), 5)
	sim:Advance(GAP * 2, COARSE)
	t.eq(writes(sim, 1) - before, 3, "no more")
	finish(t, sim)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Tests: leave
--------------------------------------------------------------------------------

tests["leave: the final save releases the lock; WaitLoaded waiters get nil when a loading player leaves"] = function(t)
	local sim = boot(t)
	local data = service(sim, "DataService")
	local p = addPlayer(sim, 1)
	setMoney(sim, p, 33)
	sim:RemovePlayer(p)
	t.eq(data:CanWrite(p), false, "no writes once leaving")
	sim:Advance(GAP + 1, COARSE)
	local saved = peek(sim, 1)
	t.eq(saved.Session, nil, "the lock is released")
	t.eq(saved.Money, 33)
	t.eq(saved.SaveCount, 1, "one save (the final one; a load is not a save)")

	-- A loading player who leaves: the waiter is resumed with nil at once.
	sim.DataStore:SetLatency(3)
	local q = join(sim, 2)
	local result: any = "pending"
	local env = sim:Env()
	sim:Run(function()
		env.task.spawn(function()
			result = data:WaitLoaded(q, 30)
		end)
	end)
	t.eq(result, "pending", "waiting")
	sim:Advance(0.5)
	sim:RemovePlayer(q)
	sim:Flush()
	t.eq(result, nil, "WaitLoaded → nil on leave")
	sim.DataStore:SetLatency(0.05)
	sim:Advance(GAP * 2, COARSE)
	finish(t, sim)
	sim:AssertNoErrors({ warnings = true })
end

tests["leave during the load (latency 3 s) → a release-only save, no gap warning"] = function(t)
	local sim = boot(t)
	local data = service(sim, "DataService")
	sim.DataStore:SetLatency(3)
	local p = join(sim, 1)
	sim:Advance(1, COARSE)
	sim:RemovePlayer(p)
	sim:Advance(2.5, COARSE)
	sim.DataStore:SetLatency(0.05)
	sim:Advance(GAP + 1, COARSE)
	local saved = peek(sim, 1)
	t.ok(saved ~= nil, "the load took the lock (created the key)")
	t.eq(saved.Session, nil, "… and the release-only save let it go")
	t.eq(writes(sim, 1), 2, "the load + the release")
	sim:Advance(GAP, COARSE)
	for k, size in data._debugSizes() do
		t.eq(size, 0, `_debugSizes().{k}`)
	end
	assertGaps(t, sim)
	sim:AssertNoErrors({ warnings = true })
end

tests["leave: the final save fails twice → retried within LeaveSaveWindow and succeeds"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	setMoney(sim, p, 42)
	sim:Advance(GAP + 0.5, COARSE)
	sim.DataStore:FailNext(2, nil, { "UpdateAsync" })
	local left = sim:Time()
	sim:RemovePlayer(p)
	sim:WaitFor(function()
		local saved = peek(sim, 1)
		return saved and saved.Session == nil
	end, DataConfig.LeaveSaveWindow + 3, COARSE)
	local saved = peek(sim, 1)
	t.eq(saved.Session, nil, "released on the third attempt")
	t.eq(saved.Money, 42)
	t.ok(sim:Time() - left <= DataConfig.LeaveSaveWindow, "within LeaveSaveWindow")
	t.eq(writes(sim, 1), 4, "the load + 3 attempts")
	t.eq(takeWarnings(sim, "сохранение игрока 1 не удалось"), 2)
	finish(t, sim)
	sim:AssertNoErrors({ warnings = true })
end

tests["leave: a release retry that finds no lock (our earlier attempt landed) stops quietly"] = function(t)
	local sim = boot(t)
	local data = service(sim, "DataService")
	local p = addPlayer(sim, 1)
	setMoney(sim, p, 8)
	sim:Advance(GAP + 0.5, COARSE)
	sim.DataStore:FailNext(1, nil, { "UpdateAsync" })
	sim:RemovePlayer(p)
	sim:Advance(1, COARSE)
	-- As if the failed attempt had landed after all (an unknown result): the lock is gone.
	local landed = peek(sim, 1)
	landed.Session = nil
	landed.Money = 8
	landed.Stats.Earned = 8
	sim.DataStore:Poke(STORE, key(1), landed)
	sim:Advance(GAP + 1, COARSE)
	t.eq(peek(sim, 1), landed, "nothing written over it")
	t.eq(takeWarnings(sim, "сохранение игрока 1 не удалось"), 1, "only the failed attempt")
	t.eq(takeWarnings(sim, "потерян"), 0, "no «lost» warning")
	t.eq(#sim.Kicks, 0)
	sim:Advance(GAP, COARSE)
	for k, size in data._debugSizes() do
		t.eq(size, 0, `_debugSizes().{k}`)
	end
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Tests: shutdown
--------------------------------------------------------------------------------

tests["shutdown: 3 players → completed, one final write each, every lock released, < CloseBudget"] = function(t)
	local sim = boot(t)
	local data = service(sim, "DataService")
	local players = {}
	for id = 1, 3 do
		players[id] = addPlayer(sim, id)
		setMoney(sim, players[id], id * 10)
	end
	sim:Advance(GAP, COARSE)
	sim:WaitFor(function()
		for _, p in players do
			local rec = data._recordFor(p)
			if rec.InFlight or rec.Queued then
				return false
			end
		end
		return true
	end, 10, COARSE)
	sim.DataStore:ClearCalls()
	local result = sim:Shutdown()
	t.ok(result.completed, "completed")
	t.ok(result.elapsed < DataConfig.CloseBudget, `inside CloseBudget ({result.elapsed} s)`)
	for id = 1, 3 do
		t.eq(writes(sim, id), 1, `player {id}: one final write`)
		local saved = peek(sim, id)
		t.eq(saved.Session, nil, `player {id}: lock released`)
		t.eq(saved.Money, id * 10)
		ledgerHolds(t, sim, saved, `player {id}`)
	end
	sim:AssertNoErrors({ warnings = true })
end

tests["shutdown (B-13): a player mid-load → the lock is released"] = function(t)
	local sim = boot(t)
	sim.DataStore:SetLatency(3)
	local p = join(sim, 1)
	sim:Advance(1, COARSE)
	t.eq(p:GetAttribute("DataMode"), "Loading")
	local result = sim:Shutdown()
	t.ok(result.completed, "completed")
	t.ok(result.elapsed < DataConfig.CloseBudget, `inside CloseBudget ({result.elapsed} s)`)
	local saved = peek(sim, 1)
	t.ok(saved ~= nil, "the load took the lock")
	t.eq(saved.Session, nil, "and released it during the shutdown")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Tests: modes
--------------------------------------------------------------------------------

tests["Memory mode (Studio without API access): one warn, DataMode Memory, zero writes, an instant shutdown"] = function(
	t
)
	local sim = boot(t, nil, {
		before = function(s: any)
			s.DataStore:SetEnabled(false)
		end,
	})
	local data = service(sim, "DataService")
	t.eq(data:Mode(), "Memory")
	local p = join(sim, 1)
	t.eq(waitMode(sim, p, 1), "Memory")
	t.eq(data:CanWrite(p), true, "playable")
	local tank = service(sim, "TankService")
	local rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"))
	local value, income = rules.Price("Perch", 1, nil)
	local result = sim:Run(function()
		return tank:AddFish(p, { Id = "Perch", Rarity = "Common", Kg = 1, Value = value, Income = income }, "catch")
	end)
	t.eq(result.Result, "stored", "the tank works")
	sim:Advance(3, COARSE)
	t.ok(p:GetAttribute("Money") > 0, "income works")
	t.eq(takeWarnings(sim, DataConfig.Texts.MemoryWarn), 1, "one Output warn with the instructions")
	t.eq(sim.DataStore:CountCalls("UpdateAsync"), 0, "zero writes")
	t.eq(sim.DataStore:CountCalls(), 1, "only the probe")
	local closed = sim:Shutdown()
	t.ok(closed.completed and closed.elapsed < 0.5, `an instant shutdown ({closed.elapsed} s)`)
	t.eq(sim.DataStore:CountCalls("UpdateAsync"), 0)
	sim:AssertNoErrors({ warnings = true })
end

tests["Broken mode (an error in Start): the game plays as Memory and never writes"] = function(t)
	local sim = boot(t, {
		{ path = "ReplicatedStorage.Shared.Config.DataConfig", from = "AutoSave = 60,", to = "AutoSave = 200," },
	})
	local data = service(sim, "DataService")
	t.eq(data:Mode(), "Broken")
	local p = join(sim, 1)
	t.eq(waitMode(sim, p, 1), "Memory", "clients see Memory")
	t.eq(data:CanWrite(p), true)
	sim:Advance(3, COARSE)
	t.eq(takeWarnings(sim, "режим Broken"), 1, "one loud warn")
	t.eq(sim.DataStore:CountCalls(), 0, "no DataStore call at all")
	local closed = sim:Shutdown()
	t.ok(closed.completed and closed.elapsed < 0.5, "an instant shutdown")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Tests: hygiene
--------------------------------------------------------------------------------

tests["hygiene: a garbage save is sanitized on load (warns), playable, and saved back clean"] = function(t)
	local sim = boot(t)
	sim.DataStore:Poke(STORE, key(1), {
		V = 1,
		Money = -50,
		RodId = 12,
		TankSlots = 2,
		Upgrades = "none",
		Tank = { a = savedFish("Perch", "f1", 1), b = { Id = "Perch", Kg = "heavy" }, c = savedFish("Perch", "f1", 1) },
		NextUid = "x",
		Stats = { Caught = -3, Earned = 100, Species = { Perch = 2.5 } },
	})
	local p = addPlayer(sim, 1)
	t.eq(p:GetAttribute("DataMode"), "Ready")
	t.eq(p:GetAttribute("Money"), 0, "negative money → 0")
	t.eq(p:GetAttribute("TankCount"), 2, "two valid fish, the duplicate uid renumbered")
	t.eq(takeWarnings(sim, "починены при загрузке"), 1, "one warn listing the repairs")
	t.eq(takeWarnings(sim, "книга денег"), 1, "the ledger warn (Earned 100, Money 0)")
	local saved = peekAfter(sim, p)
	t.eq(saved.RodId, RodConfig.StartRod)
	t.eq(saved.TankSlots, TankConfig.StartSlots)
	t.eq(#saved.Tank, 2)
	t.ok(saved.Tank[1].Uid ~= saved.Tank[2].Uid, "unique uids")
	t.eq(saved.Stats.Species.Perch, 2)
	sim:AssertNoErrors({ warnings = true })
end

tests["restart: money, fish, slots and ages come back on a new server (no offline growth)"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local tank = service(sim, "TankService")
	local rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"))
	local value, income = rules.Price("Swordfish", 40, "Gold")
	sim:Run(function()
		tank:AddFish(
			p,
			{ Id = "Swordfish", Rarity = "Epic", Kg = 40, Mutation = "Gold", Value = value, Income = income },
			"catch"
		)
	end)
	sim:Advance(20, COARSE)
	local money = p:GetAttribute("Money")
	local base = sim.workspace.Bases:FindFirstChild(`Base_{p:GetAttribute("BaseIndex")}`)
	local age = sim.workspace:GetServerTimeNow() - base.Tank.Slots.Slot_1:GetAttribute("GrowFrom")
	sim:RemovePlayer(p)
	sim:Advance(GAP + 1, COARSE)
	local later = restart(t, sim, 3600)
	local back = addPlayer(later, 1)
	t.eq(back:GetAttribute("Money"), money, "the same money")
	t.eq(back:GetAttribute("TankCount"), 1)
	local slot = later.workspace.Bases:FindFirstChild(`Base_{back:GetAttribute("BaseIndex")}`).Tank.Slots.Slot_1
	t.eq(slot:GetAttribute("FishId"), "Swordfish")
	t.eq(slot:GetAttribute("Mutation"), "Gold")
	t.eq(slot:GetAttribute("FishUid"), "f1")
	local ageNow = later.workspace:GetServerTimeNow() - slot:GetAttribute("GrowFrom")
	t.near(ageNow, age, 0.2, "the same age (no growth while offline)")
	finish(t, later)
	later:AssertNoErrors({ warnings = true })
	sim:AssertNoErrors({ warnings = true })
end

return tests
