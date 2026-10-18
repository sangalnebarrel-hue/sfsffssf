--[[
	Stage 4 wave 1 A — the transfer under stress (docs/stage4_design.md §3.3, §3.4, §7.3), in RbxSim
	against the built Place1.rbxl with headless players and the sim DataStore:
	  • F2 / F3 in the reversed PlayerRemoving order (S7): the victim leaves mid-carry → his final save
	    keeps the fish; the thief leaves mid-carry → the victim keeps it;
	  • the seq collision (BE-2): the victim rejoins this server during an escrow (a new record of the
	    same UserId) → exactly one copy after restart;
	  • F14 (BE-4): the thief leaves and the shutdown starts in the same frame → one row in the
	    victim's tank, the stats taken back, no Sanitize repair on reload, Released once per record;
	  • chaos (once per handler order): SetFailRate(0.3), four players stealing from each other for
	    10 virtual minutes with leaves and rejoins, then Shutdown + restart → no Origin twice across
	    the keys, no fish both in its victim's key and as an Origin elsewhere, the fish total ≤ the
	    start (no catches), the ledger in every key, the write gap per key.

	Run: lune run tools/run_tests.luau stage4_data_chaos
]]

local S = require("./stage4_server")

local tests = {}

-- A small deterministic generator (the harness has no Roblox Random).
local function lcg(seed: number): any
	local state = seed
	local function nextNumber(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	return {
		NextNumber = function(_: any): number
			return nextNumber()
		end,
		NextInteger = function(_: any, a: number, b: number): number
			return a + math.floor(nextNumber() * (b - a + 1))
		end,
	}
end

local TANK = {
	{ Id = "Perch" },
	{ Id = "Perch" },
	{ Id = "Puffer", Age = 120 },
	{ Id = "Crucian" },
}
local GAP = S.GAP

local function copies(sim: any, victimId: number, uid: string, others: { number }): number
	local n = 0
	local v = S.peek(sim, victimId)
	for _, row in (v and v.Tank) or {} do
		if row.Uid == uid then
			n += 1
		end
	end
	local origin = `{victimId}:{uid}`
	for _, id in others do
		local d = S.peek(sim, id)
		for _, row in (d and d.Tank) or {} do
			if row.Origin == origin then
				n += 1
			end
		end
	end
	return n
end

local function theft(t: any, sim: any, thief: any, victim: any, slot: number?)
	S.toCarry(t, sim, thief, victim, slot or 3)
	S.out(sim, thief, victim, "gate")
	t.ok(S.last(sim, thief, "Done"), `{thief.Name} credited`)
end

--------------------------------------------------------------------------------
-- F2 / F3 reversed, the seq collision, F14
--------------------------------------------------------------------------------

tests["F2 / F3 with PlayerRemoving handlers reversed: a leave mid-carry never moves the fish"] = function(t)
	local sim = S.boot(t, { removingOrder = "reverse" })
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	-- F3: the thief leaves mid-carry
	S.toCarry(t, sim, thief, victim, 3)
	sim:Advance(0.5)
	sim:RemovePlayer(thief)
	sim:Advance(0.2)
	t.eq(S.slot(sim, victim, 3):GetAttribute("FishUid"), "f3", "F3: the fish home")
	t.eq(S.slot(sim, victim, 3):GetAttribute("StealPhase"), nil)
	-- F2: the victim leaves mid-carry
	local thief2 = S.player(t, sim, 103, { tank = { { Id = "Crucian" } } })
	S.toCarry(t, sim, thief2, victim, 3)
	sim:Advance(0.5)
	sim:RemovePlayer(victim)
	sim:Advance(0.2)
	t.eq(S.last(sim, thief2, "Cancel").Reason, "victim")
	sim:RemovePlayer(thief2)
	sim:Advance(GAP + 4, S.COARSE)
	t.eq(copies(sim, 101, "f3", { 102, 103 }), 1, "one copy")
	t.ok(S.rowOf(S.peek(sim, 101).Tank, "f3"), "the victim's")
	sim:AssertNoErrors({ warnings = true })
end

tests["seq collision (BE-2): the victim rejoins this server during an escrow → exactly one copy after restart"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local tank = S.service(sim, "TankService")
	sim:Advance(GAP, S.COARSE)
	sim.DataStore:SetKeyLatency(S.key(101), 4)
	theft(t, sim, thief, victim)
	t.eq(tank:EscrowCount(thief), 1)
	sim:RemovePlayer(victim)
	sim:Advance(0.2)
	-- the same UserId again, a new record (its seq counter starts at 0 too)
	local again = sim:AddPlayer({ UserId = 101, Name = "Player101", DisplayName = "Игрок101", clientDelay = 1e9 })
	t.ok(
		sim:WaitFor(function()
			return again:GetAttribute("DataMode") == "Ready"
		end, 40, S.COARSE),
		"the rejoin loads behind the old record's final save"
	)
	t.eq(tank:EscrowCount(thief), 0, "the old record's commit cleared the escrow")
	t.eq(S.rowOf(S.tankOf(sim, again), "f3"), nil, "the rejoined victim has no copy")
	sim:Run(function()
		S.service(sim, "DataService"):SaveSoon(again)
	end)
	sim:Advance(GAP + 6, S.COARSE)
	sim:RemovePlayer(thief)
	sim:RemovePlayer(again)
	sim:Advance(GAP + 6, S.COARSE)
	local after = S.restart(t, sim, 5)
	t.eq(copies(after, 101, "f3", { 102 }), 1, "exactly one copy")
	sim:AssertNoErrors({ warnings = true })
end

tests["F14 (BE-4): the thief leaves and the shutdown starts in the same frame → one row, stats back, a clean reload"] = function(
	t
)
	local sim = S.boot(t)
	local data = S.service(sim, "DataService")
	local released: { [any]: number } = {}
	data.Released:Connect(function(who: any)
		released[who] = (released[who] or 0) + 1
	end)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	sim:Advance(GAP, S.COARSE)
	sim.DataStore:SetKeyLatency(S.key(101), 4)
	theft(t, sim, thief, victim)
	t.eq(S.service(sim, "TankService"):EscrowCount(thief), 1)
	sim:RemovePlayer(thief)
	sim:Shutdown({ timeout = 30 })
	local saved = S.peek(sim, 101)
	local n = 0
	for _, row in saved.Tank do
		if row.Uid == "f3" then
			n += 1
		end
	end
	t.eq(n, 1, "one row in the victim's tank")
	t.eq(saved.Stats.Lost, 0, "the victim's Stats.Lost taken back")
	t.eq(S.peek(sim, 102).Stats.Stolen, 0, "the thief's Stats.Stolen taken back")
	t.eq(copies(sim, 101, "f3", { 102 }), 1)
	t.eq(released[victim], 1, "Released once for the victim's record")
	t.eq(released[thief], 1, "Released once for the thief's record")
	-- a reload repairs nothing (no duplicate uid, no duplicate Origin)
	local after = S.restart(t, sim, 5)
	local back = S.player(t, after, 101, { keep = true })
	t.eq(S.takeWarnings(after, "починены"), 0, "no Sanitize repair on reload")
	t.ok(S.rowOf(S.tankOf(after, back), "f3"), "the fish is the victim's")
	sim:AssertNoErrors({ warnings = true })
	after:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Chaos
--------------------------------------------------------------------------------

local START = {
	{ Id = "Perch" },
	{ Id = "Perch" },
	{ Id = "Puffer" },
	{ Id = "Crucian" },
	{ Id = "Perch" },
	{ Id = "Puffer" },
}

-- One try of a theft as a player: hold, carry out of the gate; nothing if the server refuses.
local function attempt(sim: any, thief: any, victim: any, slot: number): string
	if not thief.Parent or not victim.Parent or not thief.Character or not victim.Character then
		return "gone"
	end
	local prompt = S.prompt(sim, victim, slot)
	if not prompt or not prompt.Enabled then
		return "empty"
	end
	S.standAt(sim, thief, prompt)
	local hold = sim:BeginHold(thief, prompt)
	sim:Advance(S.FRAME * 2)
	if thief:GetAttribute("Stealing") ~= "hold" then
		if hold.active then
			sim:ReleasePrompt(thief, prompt)
		end
		return "refused"
	end
	sim:WaitFor(function()
		return thief:GetAttribute("Stealing") ~= "hold"
	end, prompt.HoldDuration + 2, S.FRAME)
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	if thief:GetAttribute("Stealing") ~= "carry" then
		return "cancelled"
	end
	S.out(sim, thief, victim, "gate")
	return "done"
end

local function invariants(t: any, sim: any, ids: { number }, startCount: number, what: string)
	local origins: { [string]: number } = {}
	local rows: { [number]: { any } } = {}
	local total = 0
	for _, id in ids do
		local saved = S.peek(sim, id)
		rows[id] = (saved and saved.Tank) or {}
		total += #rows[id]
		if saved then
			S.ledgerHolds(t, sim, saved, `{what}: key {id}`)
		end
		for _, row in rows[id] do
			if row.Origin then
				origins[row.Origin] = (origins[row.Origin] or 0) + 1
			end
		end
	end
	for origin, n in origins do
		t.eq(n, 1, `{what}: Origin {origin} once across the keys`)
		local victimId, uid = string.match(origin, "^(%d+):(.+)$")
		local v = rows[tonumber(victimId) :: number] or {}
		for _, row in v do
			t.ok(row.Uid ~= uid, `{what}: {origin} is not still in its victim's key`)
		end
	end
	t.ok(total <= startCount, `{what}: fish total {total} ≤ the start {startCount}`)
end

for _, order in { "fifo", "reverse" } do
	tests[`chaos ({order}): fail rate 0.3, four players stealing for 10 minutes with rejoins → no dupe anywhere`] = function(
		t
	)
		local sim = S.boot(t, if order == "reverse" then { removingOrder = "reverse", seed = 7 } else { seed = 7 })
		local ids = { 101, 102, 103, 104 }
		local players: { [number]: any } = {}
		for _, id in ids do
			players[id] = S.player(t, sim, id, { tank = START, lastOnline = 1 })
		end
		sim.DataStore:SetFailRate(0.3)
		local rng = lcg(if order == "reverse" then 11 else 5)
		local start = sim:Time()
		local done, tries, rejoins = 0, 0, 0
		local away: { [number]: number } = {} -- id → when he comes back
		local nextLeave = start + 45
		while sim:Time() - start < 600 do
			-- leaves and rejoins
			for id, back in table.clone(away) do
				if sim:Time() >= back then
					away[id] = nil
					local p = sim:AddPlayer({
						UserId = id,
						Name = `Player{id}`,
						DisplayName = `Игрок{id}`,
						clientDelay = 1e9,
					})
					players[id] = p
					rejoins += 1
				end
			end
			if sim:Time() >= nextLeave then
				nextLeave = sim:Time() + 45 + rng:NextNumber() * 30
				local id = ids[rng:NextInteger(1, #ids)]
				local p = players[id]
				if p and p.Parent and not away[id] then
					sim:RemovePlayer(p)
					away[id] = sim:Time() + 8 + rng:NextNumber() * 10
				end
			end
			-- a theft try between two random players who are here
			local a, b = ids[rng:NextInteger(1, #ids)], ids[rng:NextInteger(1, #ids)]
			local thief, victim = players[a], players[b]
			if a ~= b and thief and victim and not away[a] and not away[b] then
				local mode = victim:GetAttribute("DataMode")
				if mode == "Ready" and thief:GetAttribute("DataMode") == "Ready" then
					tries += 1
					local before = #S.events(sim, thief, "Done")
					attempt(sim, thief, victim, rng:NextInteger(1, 6))
					done += #S.events(sim, thief, "Done") - before
				end
			end
			sim:Advance(2 + rng:NextNumber() * 3, 0.25)
		end
		t.log(`chaos {order}: {tries} tries, {done} thefts done, {rejoins} rejoins`)
		t.ok(tries > 20, `enough tries ({tries})`)
		t.ok(done >= 2, `some thefts went through ({done})`)
		sim.DataStore:SetFailRate(0)
		sim:Shutdown({ timeout = 30 })
		S.assertGaps(t, sim)
		local after = S.restart(t, sim, 5)
		invariants(t, after, ids, #START * #ids, `chaos {order}`)
		S.takeWarnings(sim, "[DataService]")
		S.takeWarnings(sim, "[EconomyService]")
		sim:AssertNoErrors({ warnings = true })
		after:AssertNoErrors({ warnings = true })
	end
end

return tests
