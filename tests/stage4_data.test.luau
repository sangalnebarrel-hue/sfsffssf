--[[
	Stage 4 wave 1 A — the anti-dupe transfer (docs/stage4_design.md §3.2–§3.4, §7.3), in RbxSim
	against the built Place1.rbxl with headless players and the sim DataStore (per-key failures and
	latency, S4 / S4b; both PlayerRemoving handler orders, S7; both shutdown orders, S6). Every row
	of the §3.3 failure table:
	  • F1 a crash during the carry (a restart from a snapshot) → the victim keeps it;
	  • F4 StealFish with a side that cannot write → nil, nothing moves; F12 holder tokens;
	  • F5 the normal escrow: the thief's save during it lacks the fish, his income without it, the
	    slot Escrow; after the victim's commit it clears and the thief's next save has it;
	  • the inline save (BE-3): a MoneyChanged handler saving the thief synchronously inside a
	    "replaced" StealFish (DataStore latency 0) never writes the loot before the victim's commit;
	  • Memory mode → cleared at once;
	  • F6 the victim leaves mid-escrow → the thief commits with the fish;
	  • F7 the victim's save never lands (FailKey until the leave window passes) → void on the thief
	    (Returned «Рыба вернулась к хозяину»), restart → the victim has it, the thief does not; a lost
	    lock (a foreign Session) → void; the lost reply (S4b after = true) → at most one copy;
	  • F8a the thief leaves mid-escrow → back in the victim's tank (original uid), the thief's final
	    save lacks it, restart → exactly one copy; F8b the victim leaving, then the thief →
	    AmendLeaving, the victim's key has it once; F8c the victim's final snapshot already taken →
	    zero copies, never two (documented);
	  • F9 Shutdown with two escrows → each fish once in its victim's key; F9' players first → the same;
	  • F10 a crash between the two commits (a snapshot) → zero copies, never two (documented);
	  • F13 an old dupe in a save → Sanitize keeps one per Origin.
	F2/F3 live in tests/stage4_theft (the leaves during hold and carry). F6–F9 run in both
	PlayerRemoving handler orders.

	Run: lune run tools/run_tests.luau stage4_data
]]

local S = require("./stage4_server")

local tests = {}

local TANK = {
	{ Id = "Perch" },
	{ Id = "Perch" },
	{ Id = "Puffer", Age = 120 },
	{ Id = "Crucian" },
}
local GAP = S.GAP
local ORDERS = { "fifo", "reverse" }

local function bootOrder(t: any, order: string, extra: { [string]: any }?): any
	local opts = table.clone(extra or {})
	if order == "reverse" then
		opts.removingOrder = "reverse"
	end
	return S.boot(t, opts)
end

-- Copies of the victim's fish uid across the keys: in the victim's key by Uid, elsewhere by Origin.
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

local function originIn(sim: any, id: number, origin: string): boolean
	local d = S.peek(sim, id)
	for _, row in (d and d.Tank) or {} do
		if row.Origin == origin then
			return true
		end
	end
	return false
end

-- A full theft of the victim's slot 3 (the victim's key slow: the escrow stays in force).
local function theft(t: any, sim: any, thief: any, victim: any, slot: number?)
	S.toCarry(t, sim, thief, victim, slot or 3)
	S.out(sim, thief, victim, "gate")
	t.ok(S.last(sim, thief, "Done"), `{thief.Name} credited`)
end

local function ledger(t: any, sim: any, ids: { number }, what: string)
	for _, id in ids do
		local saved = S.peek(sim, id)
		if saved then
			S.ledgerHolds(t, sim, saved, `{what}: key {id}`)
		end
	end
end

--------------------------------------------------------------------------------
-- F1, F4, F12
--------------------------------------------------------------------------------

tests["F1 a crash during the carry → the victim keeps it; F4 StealFish with a side that cannot write → nil; F12 holder tokens"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local tank = S.service(sim, "TankService")
	sim:Advance(GAP, S.COARSE)
	sim:Run(function()
		S.service(sim, "DataService"):SaveSoon(victim)
	end)
	sim:Advance(1)
	S.toCarry(t, sim, thief, victim, 3)
	-- F1: the server dies here (a snapshot of the store mid-carry)
	local crashed = S.restart(t, sim, 5)
	t.eq(copies(crashed, 101, "f3", { 102 }), 1, "F1: one copy, the victim's")
	t.ok(not originIn(crashed, 102, "101:f3"), "F1: never the thief's")
	sim:FireServer(victim, "ShieldActivate")
	sim:Advance(0.2)

	-- F12: one holder at a time
	t.eq(
		sim:Run(function()
			return tank:SetSteal(victim, "f1", 9001, "hold", { By = 1 })
		end),
		true,
		"token A holds f1"
	)
	t.eq(
		sim:Run(function()
			return tank:SetSteal(victim, "f1", 9002, "hold", { By = 2 })
		end),
		false,
		"token B cannot"
	)
	t.eq(
		sim:Run(function()
			return tank:SetSteal(victim, "f1", 9002, nil)
		end),
		false,
		"… nor release A's hold"
	)
	t.eq(
		sim:Run(function()
			return tank:SetSteal(victim, "f1", 9001, "carry")
		end),
		true,
		"A moves to the carry"
	)
	-- F4: the thief cannot write (his data still loading) → nil, nothing moves
	S.seed(sim, 150, { tank = { { Id = "Crucian" } } })
	sim.DataStore:SetKeyLatency(S.key(150), 60)
	local loading =
		sim:AddPlayer({ UserId = 150, Name = "Player150", DisplayName = "Игрок150", clientDelay = 1e9 })
	sim:Advance(0.5)
	local result, why = sim:Run(function()
		return tank:StealFish(victim, loading, "f1", 9001)
	end)
	t.eq(result, nil, "F4: StealFish refuses")
	t.eq(why, "busy")
	t.ok(S.rowOf(S.tankOf(sim, victim), "f1"), "F4: the fish never left")
	-- a wrong token / a fish not in the carry → nil as well
	t.eq(
		sim:Run(function()
			return tank:StealFish(victim, thief, "f1", 1234)
		end),
		nil,
		"a foreign token → nil"
	)
	t.eq(
		sim:Run(function()
			return tank:SetSteal(victim, "f1", 9001, nil)
		end),
		true,
		"A releases"
	)
	t.eq(S.slot(sim, victim, 1):GetAttribute("StealPhase"), nil)
	sim:RemovePlayer(loading)
	sim:Advance(0.5)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- F5, the inline save, Memory mode
--------------------------------------------------------------------------------

tests["F5 the escrow: the thief's save lacks the fish and his income excludes it until the victim's commit"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local tank = S.service(sim, "TankService")
	local data = S.service(sim, "DataService")
	sim:Advance(GAP, S.COARSE)
	sim.DataStore:SetKeyLatency(S.key(101), 10)
	local income = thief:GetAttribute("Income")
	theft(t, sim, thief, victim)
	t.eq(tank:EscrowCount(thief), 1, "escrowed: the victim's save is in flight")
	local row = S.rowByOrigin(S.tankOf(sim, thief), "101:f3")
	t.ok(row, "the thief's live data has the row")
	local slot = S.slot(sim, thief, row.Slot)
	t.eq(slot:GetAttribute("Escrow"), true, "the slot shows Escrow")
	t.eq(slot:GetAttribute("State"), "fish", "… and the fish")
	t.near(thief:GetAttribute("Income"), income, 1e-6, "the escrowed fish earns nothing")
	-- a save of the thief during the escrow lacks the fish
	local before = data:CommittedSeq(thief)
	sim:Run(function()
		data:SaveSoon(thief)
	end)
	t.ok(
		sim:WaitFor(function()
			return data:CommittedSeq(thief) > before
		end, GAP + 2, S.COARSE),
		"the thief's save committed"
	)
	t.eq(tank:EscrowCount(thief), 1, "still escrowed")
	t.ok(not originIn(sim, 102, "101:f3"), "the thief's save lacks the fish")
	t.ok(S.rowOf(S.peek(sim, 101).Tank, "f3"), "the victim's key still has it (not committed yet)")
	-- the victim's commit clears it; the thief's next save has it
	t.ok(
		sim:WaitFor(function()
			return tank:EscrowCount(thief) == 0
		end, 12, S.COARSE),
		"cleared at the victim's commit"
	)
	t.eq(S.rowOf(S.peek(sim, 101).Tank, "f3"), nil, "the victim's key lost it")
	t.eq(slot:GetAttribute("Escrow"), nil, "Escrow cleared")
	t.ok(thief:GetAttribute("Income") > income, "now it earns")
	t.ok(
		sim:WaitFor(function()
			return originIn(sim, 102, "101:f3")
		end, GAP + 2, S.COARSE),
		"the thief's next save has it"
	)
	t.eq(copies(sim, 101, "f3", { 102 }), 1, "one copy")
	-- the sale is refused while escrowed (checked on a second escrow)
	sim:Advance(S.LIMITS.ThiefCooldown, 0.5)
	local victim2 = S.player(t, sim, 103, { tank = TANK })
	sim:Advance(GAP, S.COARSE)
	sim.DataStore:SetKeyLatency(S.key(103), 10)
	theft(t, sim, thief, victim2)
	local row2 = S.rowByOrigin(S.tankOf(sim, thief), "103:f3")
	sim:FireServer(thief, "TankSell", row2.Uid)
	sim:Advance(0.1)
	local denied = S.tankEvents(sim, thief, "Denied")
	t.eq(denied[#denied].Reason, "escrow", "TankSell → Denied escrow")
	t.eq(denied[#denied].Text, S.TEXTS.Denied.escrow)
	ledger(t, sim, { 101, 102 }, "F5")
	sim:AssertNoErrors({ warnings = true })
end

tests["inline save (BE-3): a MoneyChanged handler saving the thief inside a «replaced» StealFish never writes the loot early"] = function(
	t
)
	local sim = S.boot(t)
	-- the thief's tank is full of weaker fish: the loot replaces one (autosell coins → MoneyChanged)
	local thief = S.player(t, sim, 102, {
		tank = {
			{ Id = "Crucian" },
			{ Id = "Crucian" },
			{ Id = "Crucian" },
			{ Id = "Crucian" },
			{ Id = "Crucian" },
			{ Id = "Crucian" },
		},
	})
	local victim = S.player(t, sim, 101, { tank = TANK })
	local data = S.service(sim, "DataService")
	local economy = S.service(sim, "EconomyService")
	sim:Advance(GAP + 1, S.COARSE)
	sim.DataStore:SetLatency(0) -- every request completes in the same frame …
	sim.DataStore:SetKeyLatency(S.key(101), 8) -- … except the victim's: its commit comes later
	local inline = 0
	local leaked = false
	economy.MoneyChanged:Connect(function(who: any, _money: number, _delta: number, reason: string)
		if who == thief and reason == "autosell" then
			inline += 1
			data:SaveSoon(thief) -- synchronously, inside StealFish step 5
			if originIn(sim, 102, "101:f3") then
				leaked = true
			end
		end
	end)
	theft(t, sim, thief, victim)
	t.eq(S.last(sim, thief, "Done").Result.Result, "replaced", "the loot replaced the thief's weakest fish")
	t.eq(inline, 1, "the handler ran inside the theft")
	t.ok(data:CommittedSeq(thief) > 0, "the thief's inline save committed")
	t.eq(leaked, false, "the inline save never held the loot")
	t.ok(not originIn(sim, 102, "101:f3"), "not before the victim's commit")
	t.ok(
		sim:WaitFor(function()
			return S.service(sim, "TankService"):EscrowCount(thief) == 0
		end, 12, S.COARSE),
		"cleared at the victim's commit"
	)
	t.ok(
		sim:WaitFor(function()
			return originIn(sim, 102, "101:f3")
		end, GAP + 2, S.COARSE),
		"then saved"
	)
	t.eq(copies(sim, 101, "f3", { 102 }), 1)
	ledger(t, sim, { 101, 102 }, "inline")
	sim:AssertNoErrors({ warnings = true })
end

tests["Memory mode (no DataStore): the escrow clears at once"] = function(t)
	local sim = S.boot(t, {
		before = function(s: any)
			s.DataStore:SetEnabled(false)
		end,
	})
	S.takeWarnings(sim, "DataStore")
	local victim = S.player(t, sim, 101, { fresh = true })
	local thief = S.player(t, sim, 102, { fresh = true })
	t.eq(victim:GetAttribute("DataMode"), "Memory")
	for _, id in { "Perch", "Perch", "Puffer", "Crucian" } do
		S.addFish(sim, victim, id, nil, "stolen")
	end
	S.addFish(sim, thief, "Crucian", nil, "stolen")
	S.unprotect(sim, victim)
	theft(t, sim, thief, victim)
	t.eq(S.service(sim, "TankService"):EscrowCount(thief), 0, "no escrow in Memory mode")
	local row = S.rowByOrigin(S.tankOf(sim, thief), "101:f3")
	t.ok(row, "the thief has it")
	t.eq(S.slot(sim, thief, row.Slot):GetAttribute("Escrow"), nil)
	S.takeWarnings(sim, "DataStore")
	S.takeWarnings(sim, "Memory")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- F6–F9 in both PlayerRemoving handler orders
--------------------------------------------------------------------------------

local cases: { [string]: { [string]: (t: any) -> () } } = { fifo = {}, reverse = {} }
for _, order in ORDERS do
	cases[order]["F6 the victim leaves mid-escrow → the thief commits with the fish"] = function(t)
		local sim = bootOrder(t, order)
		local victim = S.player(t, sim, 101, { tank = TANK })
		local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
		local tank = S.service(sim, "TankService")
		sim:Advance(GAP, S.COARSE)
		sim.DataStore:SetKeyLatency(S.key(101), 4)
		theft(t, sim, thief, victim)
		t.eq(tank:EscrowCount(thief), 1)
		sim:RemovePlayer(victim)
		t.ok(
			sim:WaitFor(function()
				return tank:EscrowCount(thief) == 0
			end, 25, S.COARSE),
			"cleared by the victim's final save"
		)
		t.ok(S.rowByOrigin(S.tankOf(sim, thief), "101:f3"), "the thief keeps it")
		sim:RemovePlayer(thief)
		sim:Advance(GAP + 3, S.COARSE)
		local after = S.restart(t, sim, 5)
		t.eq(copies(after, 101, "f3", { 102 }), 1, "one copy")
		t.ok(originIn(after, 102, "101:f3"), "the thief's")
		ledger(t, after, { 101, 102 }, "F6")
		sim:AssertNoErrors({ warnings = true })
	end

	cases[order]["F7 the victim's save never lands → void on the thief; restart → the victim has it"] = function(t)
		local sim = bootOrder(t, order)
		local victim = S.player(t, sim, 101, { tank = TANK })
		local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
		local tank = S.service(sim, "TankService")
		sim:Advance(GAP, S.COARSE)
		sim.DataStore:SetKeyLatency(S.key(101), 2)
		sim.DataStore:FailKey(S.key(101), math.huge, nil, { "UpdateAsync" })
		theft(t, sim, thief, victim)
		t.eq(tank:EscrowCount(thief), 1)
		sim:RemovePlayer(victim)
		t.ok(
			sim:WaitFor(function()
				return tank:EscrowCount(thief) == 0
			end, S.DataConfig.LeaveSaveWindow + 20, S.COARSE),
			"the victim's record released without the commit"
		)
		t.eq(S.rowByOrigin(S.tankOf(sim, thief), "101:f3"), nil, "voided: gone from the thief")
		local returned = S.last(sim, thief, "Returned")
		t.ok(returned, "the thief is told")
		t.eq(returned.Text, S.STEAL_TEXTS.Result.Void)
		t.eq(S.service(sim, "DataService"):Get(thief).Stats.Stolen, 0, "Stats.Stolen taken back")
		sim.DataStore:FailKey(S.key(101), 0)
		sim:RemovePlayer(thief)
		sim:Advance(GAP + 3, S.COARSE)
		local after = S.restart(t, sim, 5)
		t.eq(copies(after, 101, "f3", { 102 }), 1, "one copy")
		t.ok(S.rowOf(S.peek(after, 101).Tank, "f3"), "the victim's key still has it")
		ledger(t, after, { 101, 102 }, "F7")
		S.takeWarnings(sim, "[DataService]")
		sim:AssertNoErrors({ warnings = true })
	end

	cases[order]["F8a the thief leaves mid-escrow → back in the victim's tank, one copy after restart"] = function(t)
		local sim = bootOrder(t, order)
		local victim = S.player(t, sim, 101, { tank = TANK })
		local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
		local data = S.service(sim, "DataService")
		sim:Advance(GAP, S.COARSE)
		sim.DataStore:SetKeyLatency(S.key(101), 4)
		theft(t, sim, thief, victim)
		t.eq(S.service(sim, "TankService"):EscrowCount(thief), 1)
		sim:RemovePlayer(thief)
		sim:Advance(S.FRAME)
		local back = S.rowOf(S.tankOf(sim, victim), "f3")
		t.ok(back, "the victim has it back with its original uid")
		t.eq(back.Slot, 3, "in its own display")
		t.eq(S.slot(sim, victim, 3):GetAttribute("FishUid"), "f3")
		t.eq(S.last(sim, victim, "Returned").Text, S.STEAL_TEXTS.Result.Saved.left)
		t.eq(data:Get(victim).Stats.Lost, 0, "Stats.Lost taken back")
		sim:Advance(GAP + 8, S.COARSE)
		t.ok(not originIn(sim, 102, "101:f3"), "the thief's final save lacks it")
		sim:RemovePlayer(victim)
		sim:Advance(GAP + 8, S.COARSE)
		local after = S.restart(t, sim, 5)
		t.eq(copies(after, 101, "f3", { 102 }), 1, "exactly one copy …")
		t.ok(S.rowOf(S.peek(after, 101).Tank, "f3"), "… the victim's")
		ledger(t, after, { 101, 102 }, "F8a")
		sim:AssertNoErrors({ warnings = true })
	end

	cases[order]["F8b the victim leaves, the thief 1 s later → AmendLeaving: the fish once in the victim's key"] = function(
		t
	)
		local sim = bootOrder(t, order)
		local victim = S.player(t, sim, 101, { tank = TANK })
		local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
		sim:Advance(GAP, S.COARSE)
		sim.DataStore:SetKeyLatency(S.key(101), 4)
		theft(t, sim, thief, victim)
		sim:RemovePlayer(victim)
		sim:Advance(1)
		local rec = S.service(sim, "DataService")._recordFor(victim)
		t.ok(rec and rec.State == "Leaving" and not rec.FinalTaken, "the victim is leaving, no final snapshot yet")
		sim:RemovePlayer(thief)
		sim:Advance(GAP + 12, S.COARSE)
		local after = S.restart(t, sim, 5)
		t.eq(copies(after, 101, "f3", { 102 }), 1, "exactly one copy")
		t.ok(S.rowOf(S.peek(after, 101).Tank, "f3"), "in the victim's key")
		ledger(t, after, { 101, 102 }, "F8b")
		sim:AssertNoErrors({ warnings = true })
	end

	cases[order]["F8c the victim's final snapshot already taken → zero copies, never two (documented)"] = function(t)
		local sim = bootOrder(t, order)
		local victim = S.player(t, sim, 101, { tank = TANK })
		local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
		sim:Advance(GAP, S.COARSE)
		sim.DataStore:SetKeyLatency(S.key(101), 4)
		theft(t, sim, thief, victim)
		sim:RemovePlayer(victim)
		sim:Advance(0.5)
		-- the window between the victim's final transform and its reply (one request): forced
		local rec = S.service(sim, "DataService")._recordFor(victim)
		rec.FinalTaken = true
		sim:RemovePlayer(thief)
		sim:Advance(GAP + 12, S.COARSE)
		local after = S.restart(t, sim, 5)
		local n = copies(after, 101, "f3", { 102 })
		t.ok(n <= 1, `never two copies ({n})`)
		t.log(`F8c ({order}): {n} copies (the documented loss is 0)`)
		ledger(t, after, { 101, 102 }, "F8c")
		sim:AssertNoErrors({ warnings = true })
	end

	cases[order]["F9 Shutdown with two escrows → each fish once in its victim's key; F9' players first → the same"] = function(
		t
	)
		for _, shutdownOrder in { "closeFirst", "playersFirst" } do
			local sim = bootOrder(t, order)
			local victimA = S.player(t, sim, 101, { tank = TANK })
			local victimB = S.player(t, sim, 103, { tank = TANK })
			local thiefA = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
			local thiefB = S.player(t, sim, 104, { tank = { { Id = "Crucian" } } })
			sim:Advance(GAP, S.COARSE)
			-- (A's save stays in flight through B's theft: both escrows are open at the shutdown)
			sim.DataStore:SetKeyLatency(S.key(101), 12)
			sim.DataStore:SetKeyLatency(S.key(103), 4)
			theft(t, sim, thiefA, victimA)
			theft(t, sim, thiefB, victimB)
			local tank = S.service(sim, "TankService")
			t.eq(tank:EscrowCount(thiefA) + tank:EscrowCount(thiefB), 2, `{shutdownOrder}: two escrows`)
			sim:Shutdown({ timeout = 30, order = shutdownOrder })
			t.eq(copies(sim, 101, "f3", { 102, 104 }), 1, `{shutdownOrder}: victim A's fish once`)
			t.eq(copies(sim, 103, "f3", { 102, 104 }), 1, `{shutdownOrder}: victim B's fish once`)
			t.ok(S.rowOf(S.peek(sim, 101).Tank, "f3"), `{shutdownOrder}: in victim A's key`)
			t.ok(S.rowOf(S.peek(sim, 103).Tank, "f3"), `{shutdownOrder}: in victim B's key`)
			ledger(t, sim, { 101, 102, 103, 104 }, `F9 {shutdownOrder}`)
			sim:AssertNoErrors({ warnings = true })
		end
	end
end

-- (one top-level line per test, so `grep -c '^tests\['` counts them all)
tests["F6 the victim leaves mid-escrow → the thief commits with the fish (fifo)"] =
	cases.fifo["F6 the victim leaves mid-escrow → the thief commits with the fish"]
tests["F7 the victim's save never lands → void on the thief; restart → the victim has it (fifo)"] =
	cases.fifo["F7 the victim's save never lands → void on the thief; restart → the victim has it"]
tests["F8a the thief leaves mid-escrow → back in the victim's tank, one copy after restart (fifo)"] =
	cases.fifo["F8a the thief leaves mid-escrow → back in the victim's tank, one copy after restart"]
tests["F8b the victim leaves, the thief 1 s later → AmendLeaving: the fish once in the victim's key (fifo)"] =
	cases.fifo["F8b the victim leaves, the thief 1 s later → AmendLeaving: the fish once in the victim's key"]
tests["F8c the victim's final snapshot already taken → zero copies, never two (documented) (fifo)"] =
	cases.fifo["F8c the victim's final snapshot already taken → zero copies, never two (documented)"]
tests["F9 Shutdown with two escrows → each fish once in its victim's key; F9' players first → the same (fifo)"] =
	cases.fifo["F9 Shutdown with two escrows → each fish once in its victim's key; F9' players first → the same"]
tests["F6 the victim leaves mid-escrow → the thief commits with the fish (reverse)"] =
	cases.reverse["F6 the victim leaves mid-escrow → the thief commits with the fish"]
tests["F7 the victim's save never lands → void on the thief; restart → the victim has it (reverse)"] =
	cases.reverse["F7 the victim's save never lands → void on the thief; restart → the victim has it"]
tests["F8a the thief leaves mid-escrow → back in the victim's tank, one copy after restart (reverse)"] =
	cases.reverse["F8a the thief leaves mid-escrow → back in the victim's tank, one copy after restart"]
tests["F8b the victim leaves, the thief 1 s later → AmendLeaving: the fish once in the victim's key (reverse)"] =
	cases.reverse["F8b the victim leaves, the thief 1 s later → AmendLeaving: the fish once in the victim's key"]
tests["F8c the victim's final snapshot already taken → zero copies, never two (documented) (reverse)"] =
	cases.reverse["F8c the victim's final snapshot already taken → zero copies, never two (documented)"]
tests["F9 Shutdown with two escrows → each fish once in its victim's key; F9' players first → the same (reverse)"] =
	cases.reverse["F9 Shutdown with two escrows → each fish once in its victim's key; F9' players first → the same"]

--------------------------------------------------------------------------------
-- F7 variants, F10, F13
--------------------------------------------------------------------------------

tests["F7 a lost lock (a foreign Session) → void; the lost reply (S4b after = true) → at most one copy"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local tank = S.service(sim, "TankService")
	sim:Advance(GAP, S.COARSE)
	-- another server takes the victim's lock: his next save is «lost» → kicked → void
	local saved = S.peek(sim, 101)
	saved.Session = { Id = "other", Server = "other", Job = "other", T = saved.Session.T + 1 }
	sim.DataStore:Poke(S.STORE, S.key(101), saved)
	sim.DataStore:SetKeyLatency(S.key(101), 2)
	theft(t, sim, thief, victim)
	t.ok(
		sim:WaitFor(function()
			return tank:EscrowCount(thief) == 0
		end, 20, S.COARSE),
		"the escrow ended"
	)
	t.eq(S.rowByOrigin(S.tankOf(sim, thief), "101:f3"), nil, "voided")
	t.ok(#sim.Kicks > 0, "the victim was kicked (lock lost)")
	S.takeWarnings(sim, "[DataService]")

	-- the lost reply: the victim's final writes land, then their calls error
	local sim2 = S.boot(t)
	local victim2 = S.player(t, sim2, 101, { tank = TANK })
	local thief2 = S.player(t, sim2, 102, { tank = { { Id = "Crucian" } } })
	sim2:Advance(GAP, S.COARSE)
	sim2.DataStore:SetKeyLatency(S.key(101), 3)
	theft(t, sim2, thief2, victim2)
	sim2.DataStore:FailKey(S.key(101), 2, nil, { after = true })
	sim2:RemovePlayer(victim2)
	sim2:Advance(S.DataConfig.LeaveSaveWindow + 10, S.COARSE)
	sim2:RemovePlayer(thief2)
	sim2:Advance(GAP + 8, S.COARSE)
	local n = copies(sim2, 101, "f3", { 102 })
	t.ok(n <= 1, `the lost reply: at most one copy ({n})`)
	t.log(`F7 lost reply: {n} copies`)
	S.takeWarnings(sim2, "[DataService]")
	sim:AssertNoErrors({ warnings = true })
	sim2:AssertNoErrors({ warnings = true })
end

tests["F10 a crash between the victim's and the thief's commits → zero copies, never two (documented)"] = function(t)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local tank = S.service(sim, "TankService")
	sim:Advance(GAP, S.COARSE)
	sim.DataStore:SetKeyLatency(S.key(101), 2)
	sim.DataStore:SetKeyLatency(S.key(102), 5) -- the thief's commit comes later
	theft(t, sim, thief, victim)
	t.ok(
		sim:WaitFor(function()
			return tank:EscrowCount(thief) == 0
		end, 10, S.COARSE),
		"the victim committed"
	)
	t.ok(not originIn(sim, 102, "101:f3"), "the thief's key not yet")
	local crashed = S.restart(t, sim, 5) -- the store as it is right now: a hard crash
	local n = copies(crashed, 101, "f3", { 102 })
	t.ok(n <= 1, `never two ({n})`)
	t.eq(n, 0, "the documented loss: zero copies")
	-- without the crash the thief's save lands
	t.ok(
		sim:WaitFor(function()
			return originIn(sim, 102, "101:f3")
		end, GAP + 8, S.COARSE),
		"the thief's key gets it"
	)
	t.eq(copies(sim, 101, "f3", { 102 }), 1)
	sim:AssertNoErrors({ warnings = true })
end

tests["F13 an old dupe in a save → Sanitize keeps one per Origin"] = function(t)
	local sim = S.boot(t)
	local p = S.player(t, sim, 101, {
		tank = {
			{ Id = "Perch", Origin = "777:f1" },
			{ Id = "Perch", Origin = "777:f1" },
			{ Id = "Crucian", Origin = "777:f2" },
		},
	})
	local rows = S.tankOf(sim, p)
	local n = 0
	for _, row in rows do
		if row.Origin == "777:f1" then
			n += 1
		end
	end
	t.eq(n, 1, "one row per Origin")
	t.eq(#rows, 2, "the dupe dropped")
	t.ok(S.takeWarnings(sim, "Origin") >= 1, "the repair is reported")
	sim:AssertNoErrors({ warnings = true })
end

return tests
