--[[
	Stage 4 END-TO-END, part 1 — the theft (docs/stage4_design.md §7.7 cases 1 and 9): the real
	server (every service, real persistence in the sim DataStore) and the REAL clients of three
	players — a phone thief, a tablet victim, a desktop bystander (tests/stage4_e2e_kit.luau). The
	players only walk (Humanoid:MoveTo at the server's WalkSpeed), hold «Украсть» as a stock prompt
	(as their own client sees it), tap and read their screens; the saves are poked before the join.

	  (1) the happy path: the victim has 4 fish with a Legendary (SharkPup) aged 200 s, the thief 3
	      weaker ones; the protections run out (the ShieldChip goes); the thief walks into the court —
	      «Украсть» is shown to him and hidden from the owner — and holds 3 s: the victim's plate
	      «ВОР В САДКЕ!» with the big ЩИТ, «ЗАЩИТА» → «ЩИТ!», the bystander's lamp blinking, the
	      thief's banner «КРАДЁШЬ: АКУЛЁНОК»; the carry: StolenFish over his head, WalkSpeed 13.6,
	      the red guide on the ground, «ДОМОЙ» locked; he walks out of the gate → «ДОБЫЧА!», both
	      «САДОК» chips roll (3/6 → 4/6 and 4/6 → 3/6), the victim's «Украдено: Акулёнок (…)» and his
	      chip «🛡️ 1:30»; the saves: the victim's write without the fish lands BEFORE any write of
	      the thief's key that holds it (the DataStore's landed writes, in order); a shutdown and a
	      NEW server: exactly one copy, the thief's, its age kept;
	  (9) the same with remoteLatency 0.15: the prompt events reach the server late (S8), the
	      server still times the hold (Tolerance / Grace) and credits once; the victim's alert and
	      the thief's banner come through the lag.
	Parts 2–4: stage4_e2e_defence (the shield in the hold and the carry, the tag, dog + alarm from
	the sheet, the lock), stage4_e2e_tank (the full thief tank, the rejoin with a slow victim key),
	stage4_e2e_timeline (the minigame timeline, the catch card).

	Run: lune run tools/run_tests.luau stage4_e2e.test
]]

local roblox = require("@lune/roblox")

local E = require("./stage4_e2e_kit")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

local tests = {}

local function upper(sim: any, text: string): string
	return E.shared(sim, "TextUtil").upper(text)
end

-- The happy path, shared by (1) and (9).
local function happyPath(t: any, opts: { [string]: any }?)
	local o = opts or {}
	local cast = E.trio(t, { latency = o.latency })
	local sim, victim, thief, bystander = cast.sim, cast.victim, cast.thief, cast.bystander
	local vu, tu = E.ui(sim, victim), E.ui(sim, thief)
	local base = E.baseOf(sim, victim)
	local writes = E.writeLog(sim)
	local phases = E.phaseLog(sim, thief)
	local victimToasts = E.toastWatch(victim)
	local def = E.fishDef("SharkPup")
	local origin = `{victim.UserId}:f3`

	-- After the join protections: no chip; «САДОК» 4/6 and 3/6.
	t.eq(vu.chip.Visible, false, "the victim's ShieldChip is gone with his join protection")
	t.eq(vu.tankChip.Text, "4/6", "the victim's «САДОК» 4/6")
	t.eq(tu.tankChip.Text, "3/6", "the thief's «САДОК» 3/6")
	local growFrom = E.slot(sim, victim, 3):GetAttribute("GrowFrom")

	-- The bystander stands at the victim's gate; the thief walks into the court.
	sim:Teleport(bystander, E.exitPoint(base, "gate") + Vector3.new(14, 0, -6))
	local prompt = E.toCourt(t, sim, thief, victim, 3)
	sim:Advance(0.6)
	t.ok(E.seen(sim, thief, prompt) > 0, "«Украсть» is shown to the thief")
	t.eq(E.seen(sim, victim, prompt), 0, "… and hidden from the owner (a local MaxActivationDistance 0)")
	t.eq(prompt.HoldDuration, E.BASE_HOLD, "the ring takes 3 s (no lock)")

	-- The hold.
	local hold = sim:BeginHold(thief, prompt)
	local holdAt = sim:Time()
	t.ok(hold.active, `the hold began ({hold.cancelReason})`)
	if o.latency then
		-- (S8: the prompt events travel the link like a RemoteEvent)
		sim:Advance(E.FRAME)
		t.eq(thief:GetAttribute("Stealing"), nil, "the HoldBegan is still on its way to the server")
	end
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == "hold" and E.mode(sim, thief) == "hold"
		end, 1, E.FRAME),
		"the server took the hold; the thief's banner holds"
	)
	t.eq(
		tu.barTitle.Text,
		E.fill(E.BANNER.Hold, { short = upper(sim, def.ShortName) }),
		"«КРАДЁШЬ: АКУЛЁНОК»"
	)
	t.ok(
		sim:WaitFor(function()
			local stats = E.alert(sim, victim)
			return stats.phase == "hold" and stats.shown == "plate"
		end, 1.5, E.FRAME),
		"the victim's plate shows (tablet: the full plate)"
	)
	local plate = vu.alert
	t.eq(plate.Text.Title.Text, E.ALERT.Hold, "«ВОР В САДКЕ!»")
	t.eq(
		plate.Text.Sub.Text,
		E.fill(E.ALERT.HoldSub, { name = thief.DisplayName, short = def.ShortName }),
		"«… крадёт: Акулёнок»"
	)
	local shield = plate.Buttons.Shield
	t.ok(
		shield.Visible and shield.AbsoluteSize.Y >= E.THEFT_UI.ShieldMin - 0.5,
		`the big ЩИТ ({shield.AbsoluteSize.Y} px)`
	)
	t.ok(E.defenceStats(sim, victim).alert, "«ЗАЩИТА» became «ЩИТ!»")
	t.ok(
		sim:WaitFor(function()
			local view = E.world(sim, bystander, base)
			return view ~= nil and view.lamp
		end, 1.5, E.FRAME),
		"the bystander sees the lamp blink"
	)
	local lampNeon = E.call(sim, bystander, function()
		return base.Alarm.Lamp.Material
	end)
	t.eq(lampNeon, Enum.Material.Neon, "… Neon on his client")
	t.eq(#E.theftEvents(sim, bystander), 0, "the bystander gets no StealEvent")

	-- The carry.
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == "carry"
		end, prompt.HoldDuration + 1, E.FRAME),
		"the hold completed: the carry"
	)
	local carryAfter = sim:Time() - holdAt
	t.ok(
		carryAfter >= E.BASE_HOLD - E.StealConfig.Hold.Tolerance
			and carryAfter <= E.BASE_HOLD + 2 * (o.latency or 0) + 0.2,
		`the server timed the hold: the carry {carryAfter} s after the press`
	)
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	sim:Advance(0.3)
	t.ok(thief.Character:FindFirstChild("StolenFish"), "the SharkPup over the thief's head (StolenFish)")
	t.near(thief.Character.Humanoid.WalkSpeed, E.CARRY, 1e-6, "WalkSpeed 13.6")
	t.eq(E.mode(sim, thief), "carry", "«БЕГИ ЗА ОГРАДУ!»")
	t.eq(tu.barTitle.Text, E.BANNER.Carry)
	t.ok(sim.workspace:FindFirstChild("TheftGuide") ~= nil, "the red guide on the ground")
	t.eq(tu.hud:GetAttribute("Stealing"), "carry", "his HUD knows (D locks «ДОМОЙ»)")
	t.ok(
		sim:WaitFor(function()
			return E.alert(sim, victim).phase == "carry"
		end, 1, E.FRAME),
		"the victim's alert says the carry"
	)
	t.eq(vu.alert.Text.Title.Text, E.ALERT.Carry, "«ВОР УБЕГАЕТ!»")

	-- Out of the gate → «ДОБЫЧА!».
	local victimChip = vu.tankChip.Text
	t.ok(E.walkOut(sim, thief, victim, "gate"), "walking out of the gate ends the theft")
	local carryAt, doneAt = E.phaseAt(phases, "carry"), E.phaseAt(phases, nil)
	t.ok(carryAt and doneAt, "carry → over")
	local done = E.theftEvents(sim, thief, "Done")
	t.eq(#done, 1, "one Done")
	t.eq(done[1] and done[1].data.Fish.Id, "SharkPup")
	t.ok(
		sim:WaitFor(function()
			return E.mode(sim, thief) == "done"
		end, 0.5, E.FRAME),
		"«ДОБЫЧА!»"
	)
	t.eq(tu.slamTitle.Text, E.BANNER.Done)
	local lost = E.theftEvents(sim, victim, "Lost")
	t.eq(#lost, 1, "one Lost to the victim")
	t.eq(lost[1] and lost[1].data.Kind, "after", "his after-theft immunity")
	sim:Advance(1)
	-- (NotifyController splits «Украдено: Акулёнок (Ника)» at its ": " into a title and a line)
	t.ok(E.has(victimToasts, "Украдено"), `the victim's «Украдено: …» ({E.list(victimToasts)})`)
	t.ok(E.has(victimToasts, `({thief.DisplayName})`), `… naming the fish and the thief ({E.list(victimToasts)})`)
	t.ok(vu.chip.Visible, "the victim's ShieldChip is back")
	local chipText = vu.chipLabel.Text
	t.ok(
		chipText == "1:30" or chipText == "1:29" or chipText == "1:28" or chipText == "1:27",
		`«🛡️ {chipText}» (1:30)`
	)
	t.ok(
		sim:WaitFor(function()
			return tu.tankChip.Text == "4/6"
		end, 3, E.FRAME),
		`the thief's «САДОК» 4/6 (got {tu.tankChip.Text})`
	)
	t.eq(vu.tankChip.Text, "3/6", `the victim's «САДОК» rolled down ({victimChip} → {vu.tankChip.Text})`)
	t.eq(thief.Character.Humanoid.WalkSpeed, E.WALK, "the thief walks at 16 again")
	t.eq(thief.Character:FindFirstChild("StolenFish"), nil, "nothing over his head")
	local slot, row = E.slotByOrigin(sim, thief, origin)
	t.ok(slot, "the fish in a display of the thief's")
	if slot then
		local thiefGrow = E.slot(sim, thief, slot):GetAttribute("GrowFrom")
		t.near(thiefGrow, growFrom, 1.01, "the age kept (the same GrowFrom ± 1 s)")
	end

	-- The saves: the victim's commit lands before the thief's key holds the fish.
	local victimKey, thiefKey = E.key(victim.UserId), E.key(thief.UserId)
	t.ok(
		sim:WaitFor(function()
			local saved = E.peek(sim, thief.UserId)
			for _, r in if saved then saved.Tank else {} do
				if r.Origin == origin then
					return true
				end
			end
			return false
		end, 2 * E.GAP + 4, E.COARSE),
		"the thief's key holds the fish"
	)
	local victimCommit, thiefFirst
	for _, w in writes do
		if w.key == victimKey and victimCommit == nil and not w.uids.f3 and w.time >= doneAt - 1e-6 then
			victimCommit = w.time
		end
		if w.key == thiefKey and thiefFirst == nil and w.origins[origin] then
			thiefFirst = w.time
		end
	end
	t.ok(victimCommit ~= nil, "the victim's write without the fish landed")
	t.ok(thiefFirst ~= nil, "the thief's write with the fish landed")
	t.ok(
		victimCommit and thiefFirst and victimCommit <= thiefFirst,
		`the victim's commit ({victimCommit}) before the thief's key has it ({thiefFirst})`
	)
	E.assertGaps(t, sim)
	t.ok(
		sim:WaitFor(function()
			return E.has(victimToasts, "Садок отдыхает")
		end, 12, E.COARSE),
		`then «Садок отдыхает 1:2x — не украдут» ({E.list(victimToasts)})`
	)
	local savedRow = row and table.clone(row) or nil
	sim:AssertNoErrors({ warnings = true })

	-- A shutdown, a NEW server: exactly one copy, the thief's, the age kept.
	local closed = sim:Shutdown()
	t.ok(closed.completed, "the shutdown completed")
	local where, rows = E.copies(sim, victim.UserId, "f3")
	t.eq(#where, 1, `one copy in the store ({table.concat(where, ", ")})`)
	t.eq(where[1], thiefKey, "… the thief's")
	local later = E.restart(t, sim, 60)
	local where2 = E.copies(later, victim.UserId, "f3")
	t.eq(#where2, 1, "one copy after the restart")
	local back = E.join(t, later, thief.UserId, "phone")
	local backSlot = E.slotByOrigin(later, back, origin)
	t.ok(backSlot, "the thief has the SharkPup on the new server")
	if backSlot and rows[1] then
		t.near(E.ageOf(later, back, backSlot), rows[1].Age, 1.5, `the age kept across the restart ({rows[1].Age} s)`)
		t.ok(rows[1].Age >= 200, `older than the 200 s it had ({rows[1].Age})`)
	end
	local victim2 = E.join(t, later, victim.UserId, "tablet")
	t.eq(victim2:GetAttribute("TankCount"), 3, "the victim has 3 fish")
	t.eq(savedRow and savedRow.Id, "SharkPup")
	later:AssertNoErrors({ warnings = true })
end

tests["(1) phone thief, tablet victim, desktop bystander: hold → the plate, the lamp, the banner → carry 13.6 with the guide → out of the gate «ДОБЫЧА!», both «САДОК», «🛡️ 1:30»; the victim's commit first; a new server: one copy, the age kept"] = function(
	t
)
	happyPath(t)
end

tests["(9) the happy path with remoteLatency 0.15: the prompt events arrive late (S8), the server times the hold and credits once; alert, banner and «ДОБЫЧА!» through the lag"] = function(
	t
)
	happyPath(t, { latency = 0.15 })
end

return tests
