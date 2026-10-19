--[[
	Stage 4 END-TO-END, part 3 — the thief's tank and the saves (docs/stage4_design.md §7.7 cases 5
	and 6): the real server and the REAL clients of a phone thief and a tablet victim
	(tests/stage4_e2e_kit.luau).

	  (5) the thief's tank is full (6/6: five Swordfish and a Puffer): the victim's Perch and
	      Crucian are weaker than everything he has — no «Украсть» on them on his screen, and a hold
	      forced past his client (ignoreEnabled / ignoreDistance: an exploit's) gets the server's
	      Denied «full» on his glass; the SharkPup is stronger than his Puffer — shown; stolen, it
	      takes the Puffer's display: Done "replaced", the coins for the Puffer (autosell from his
	      own fish), «Замена! «Акулёнок» вместо «Фугу» +$N» on his screen; the Puffer is gone, the
	      tank stays 6/6;
	  (6) the victim's key is slow (DataStore:SetKeyLatency 4 s) so the thief's copy waits in
	      escrow; the thief leaves 1 s after the credit → the fish goes back to the victim (its
	      uid, its display), «Вор ушёл — рыба вернулась!» on his screen; the thief's final save lacks
	      it; a shutdown and a new server → exactly one copy, the victim's.

	Run: lune run tools/run_tests.luau stage4_e2e_tank
]]

local E = require("./stage4_e2e_kit")

local tests = {}

local function upper(sim: any, text: string): string
	return E.shared(sim, "TextUtil").upper(text)
end

tests["(5) a full thief tank: weaker fish show no «Украсть» and a forced hold gets Denied «full»; the stronger SharkPup replaces his Puffer — «Замена!» and the coins"] = function(
	t
)
	local thiefTank = {
		{ Id = "Swordfish" },
		{ Id = "Swordfish" },
		{ Id = "Puffer" },
		{ Id = "Swordfish" },
		{ Id = "Swordfish" },
		{ Id = "Swordfish" },
	}
	local cast = E.trio(t, { quick = true, bystander = false, thief = { tank = thiefTank } })
	local sim, victim, thief = cast.sim, cast.victim, cast.thief
	local tu = E.ui(sim, thief)
	local thiefToasts = E.toastWatch(thief)
	local log = E.moneyLog(sim)
	t.eq(tu.tankChip.Text, "6/6", "the thief's tank is full")
	t.ok(
		thief:GetAttribute("Income") <= 3 * victim:GetAttribute("Income"),
		"not «much stronger» (the weak rule stays out)"
	)

	-- The weaker fish: no prompt on his screen; forced past his client → Denied «full».
	local prompt = E.toCourt(t, sim, thief, victim, 1)
	sim:Advance(0.6)
	for _, slot in { 1, 2, 4 } do
		t.eq(E.seen(sim, thief, E.stealPrompt(sim, victim, slot)), 0, `Slot_{slot} (weaker than all his fish): hidden`)
	end
	t.ok(E.seen(sim, thief, E.stealPrompt(sim, victim, 3)) > 0, "Slot_3 (the SharkPup): shown")
	local denied = #E.theftEvents(sim, thief, "Denied")
	local forced = sim:BeginHold(thief, prompt, { ignoreEnabled = true, ignoreDistance = true })
	t.ok(
		sim:WaitFor(function()
			return #E.theftEvents(sim, thief, "Denied") > denied
		end, 1, E.FRAME),
		"the server answers the forced hold"
	)
	local answer = E.theftEvents(sim, thief, "Denied")
	t.eq(answer[#answer] and answer[#answer].data.Reason, "full", "Denied «full»")
	t.eq(thief:GetAttribute("Stealing"), nil, "no theft")
	if forced.active then
		sim:ReleasePrompt(thief, prompt)
	end
	sim:Advance(0.3)
	t.eq(tu.barLine.Text, E.DENIED.full, `his glass says why («{tu.barLine.Text}»)`)

	-- The SharkPup: stolen, it replaces his Puffer.
	sim:Advance(E.StealConfig.Limits.DeniedEvery + 0.2)
	local money0 = thief:GetAttribute("Money")
	local shark = E.toCourt(t, sim, thief, victim, 3)
	local hold = sim:BeginHold(thief, shark)
	t.ok(hold.active, "the hold on the SharkPup began")
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == "carry"
		end, shark.HoldDuration + 1.5, E.FRAME),
		"the carry"
	)
	if hold.active then
		sim:ReleasePrompt(thief, shark)
	end
	t.ok(E.walkOut(sim, thief, victim, "gate"), "out of the gate")
	local done = E.theftEvents(sim, thief, "Done")
	t.eq(#done, 1, "Done")
	local result = done[1] and done[1].data.Result
	t.eq(result and result.Result, "replaced", "the loot replaced his weakest")
	t.eq(result and result.Replaced and result.Replaced.Id, "Puffer", "… the Puffer")
	local price = result and result.Price or 0
	t.ok(price > 0, `the Puffer's coins ({price})`)
	t.eq(E.earned(log, thief, "autosell"), price, "credited as autosell — from his own fish")
	t.ok(thief:GetAttribute("Money") >= money0 + price, "his money grew by the coins")
	sim:Advance(E.UI.TankButton.ReplacedToastAfter + E.THEFT_UI.DoneTime + 3)
	t.eq(tu.tankChip.Text, "6/6", "still 6/6")
	local text = E.fill(E.TEXTS.Replaced, {
		new = E.fishDef("SharkPup").ShortName,
		old = E.fishDef("Puffer").ShortName,
		price = E.shared(sim, "TankRules").FormatMoney(price),
	})
	t.ok(
		E.has(thiefToasts, "Замена!") or E.has(thiefToasts, upper(sim, "Замена")),
		`«{text}» ({E.list(thiefToasts)})`
	)
	local data = E.service(sim, "DataService"):Get(thief)
	local puffers = 0
	for _, row in data.Tank do
		if row.Id == "Puffer" then
			puffers += 1
		end
	end
	t.eq(puffers, 0, "the Puffer is gone from his tank")
	sim:AssertNoErrors({ warnings = true })
end

tests["(6) a slow victim key holds the loot in escrow; the thief leaves 1 s after the credit → the fish back with the victim («Вор ушёл — рыба вернулась!»); a new server: one copy, the victim's"] = function(
	t
)
	local cast = E.trio(t, { quick = true, bystander = false })
	local sim, victim, thief = cast.sim, cast.victim, cast.thief
	local victimToasts = E.toastWatch(victim)
	local uid = E.slot(sim, victim, 3):GetAttribute("FishUid")
	local origin = `{victim.UserId}:{uid}`
	local tank = E.service(sim, "TankService")
	sim:Advance(E.GAP) -- (the join writes are behind: the next victim save goes at once)
	sim.DataStore:SetKeyLatency(E.key(victim.UserId), 4)

	local prompt = E.toCourt(t, sim, thief, victim, 3)
	local hold = sim:BeginHold(thief, prompt)
	t.ok(hold.active, "the hold began")
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == "carry"
		end, prompt.HoldDuration + 1, E.FRAME),
		"the carry"
	)
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	t.ok(E.walkOut(sim, thief, victim, "gate"), "credited at the fence")
	t.eq(#E.theftEvents(sim, thief, "Done"), 1, "Done")
	t.eq(tank:EscrowCount(thief), 1, "the loot waits in escrow (the victim's write is slow)")
	t.eq(E.slot(sim, victim, 3):GetAttribute("State"), "empty", "the victim's display is empty")

	-- The thief leaves 1 s after the credit.
	sim:Advance(1)
	t.eq(tank:EscrowCount(thief), 1, "still in escrow a second later")
	local thiefId = thief.UserId
	sim:RemovePlayer(thief)
	sim:Advance(0.5)
	local slot = E.slot(sim, victim, 3)
	t.eq(slot:GetAttribute("State"), "fish", "the fish is back in the victim's display")
	t.eq(slot:GetAttribute("FishUid"), uid, "… the same fish (its uid)")
	local returned = E.theftEvents(sim, victim, "Returned")
	t.eq(#returned, 1, "Returned to the victim")
	t.eq(returned[1] and returned[1].data.Result, "stored", "… into its display")
	-- (a tablet's column shows one toast at a time: «Украдено», «Садок отдыхает …» and the tip came
	-- first and stay their life each)
	t.ok(
		sim:WaitFor(function()
			return E.has(victimToasts, E.RESULT.Saved.left)
		end, 18, E.COARSE),
		`«Вор ушёл — рыба вернулась!» ({E.list(victimToasts)})`
	)
	t.ok(
		sim:WaitFor(function()
			local saved = E.peek(sim, thiefId)
			return saved ~= nil and saved.Session == nil
		end, E.DataConfig.LeaveSaveWindow + 2, E.COARSE),
		"the thief's final save released his key"
	)
	local thiefSaved = E.peek(sim, thiefId)
	for _, row in thiefSaved.Tank do
		t.ok(row.Origin ~= origin, "the thief's final save lacks the fish")
	end

	-- A shutdown and a new server: one copy, the victim's.
	local closed = sim:Shutdown()
	t.ok(closed.completed, "the shutdown completed")
	local where = E.copies(sim, victim.UserId, uid)
	t.eq(#where, 1, `one copy in the store ({table.concat(where, ", ")})`)
	t.eq(where[1], E.key(victim.UserId), "… the victim's")
	local later = E.restart(t, sim, 60)
	local back = E.join(t, later, victim.UserId, "tablet")
	t.eq(back:GetAttribute("TankCount"), 4, "the victim has his 4 fish")
	t.eq(E.slot(later, back, 3):GetAttribute("FishUid"), uid, "the SharkPup in its display")
	later:AssertNoErrors({ warnings = true })
end

return tests
