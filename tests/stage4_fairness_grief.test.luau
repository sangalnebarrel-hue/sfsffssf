--[[
	Stage 4 wave 3 (the server fixer) — the fairness holes the Wave 3 critics found, on the real
	server (docs/stage4_design.md §11.7 S-rows), in RbxSim against the built Place1.rbxl with headless
	players (tests/stage4_server.luau):
	  • UX-01 a newbie's accidental tap: a 0.3 s tap on «Украсть» keeps his 5:00 «newbie» protection
	    to the second (no «Кража погасила твою защиту», no wait, nothing to the victim); a real
	    hold ends it once it outlasts the tap window (1.4 s on a normal link) — still in the hold,
	    never in the carry — and only then the victim's loud Alert;
	  • UX-02 the shield bait: the owner's shield against a hold costs the thief no wait, but closes
	    that base to him until the shield ends and Limits.ShieldWait more («shielded»: Cancel
	    BaseUntil / BaseReason, Denied with Until) — exactly when the owner's shield is ready again;
	    another base stays open; the base opens again on time;
	  • DATA-01 / V-UX-01 a let-go inside the tap window (1.2 s) is a free tap for both: no
	    StealCooldownUntil, and the victim hears nothing (no Alert, no Saved: the hold reaches him
	    only once it outlasts the tap window), Limits.FreeTaps times per FailWindow, then a failure
	    (still nothing to the victim); the base's alarm (AlarmState) waits for the window too; a
	    tap neither takes the pair's loud alert (a real hold right after is loud) nor, every 31 s
	    for 3 minutes, gives the victim a single Alert;
	  • UX-03 griefing one kid: Limits.BaseFails own-fault failures on one base within FailWindow
	    close it to that thief for Limits.BaseWait («wary»; other bases open, back on time); an
	    attempt whose alert was coalesced (Quiet) ends quietly too; a 150 s release-spam loop on one
	    kid gives ≤ 6 holds and ≤ 3 loud results, the loud alerts ≥ AlertCoalesce apart (the critic
	    measured 8 holds, 5 loud alerts and 8 loud «Кража сорвалась» before).

	Run: lune run tools/run_tests.luau stage4_fairness_grief
]]

local S = require("./stage4_server")

local tests = {}

local TANK = {
	{ Id = "Perch" },
	{ Id = "Perch" },
	{ Id = "Puffer" },
	{ Id = "Crucian" },
}
local LIMITS = S.LIMITS
local FAIL = LIMITS.FailCooldown
local SHIELD = S.SHIELD

local function serverNow(sim: any): number
	return sim.workspace:GetServerTimeNow()
end

local function cooldownLeft(sim: any, p: any): number
	local untilT = p:GetAttribute("StealCooldownUntil")
	return if type(untilT) == "number" then untilT - serverNow(sim) else 0
end

-- The refusal's text is its Denied template with the time filled in.
local function startsWith(text: string?, reason: string): boolean
	local template = S.STEAL_TEXTS.Denied[reason]
	local head = string.match(template, "^(.-){t}") or template
	return type(text) == "string" and string.sub(text, 1, #head) == head and #text > #head
end

local function notified(sim: any, p: any, text: string): boolean
	for _, e in sim:ClientEventsFor(p, "Notify") do
		if e.args[1] == text then
			return true
		end
	end
	return false
end

-- A hold of `seconds` on the owner's display, then let go: the thief's Cancel and the owner's Saved.
local function holdFor(t: any, sim: any, thief: any, owner: any, slot: number, seconds: number): (any, any)
	local hold, prompt = S.hold(t, sim, thief, owner, slot)
	t.ok(hold.active, `the hold on Slot_{slot} began`)
	t.eq(thief:GetAttribute("Stealing"), "hold", "the server began it")
	sim:Advance(seconds)
	sim:ReleasePrompt(thief, prompt)
	sim:Advance(0.1)
	return S.last(sim, thief, "Cancel"), S.last(sim, owner, "Saved")
end

--------------------------------------------------------------------------------
-- UX-01: the newbie's tap
--------------------------------------------------------------------------------

tests["UX-01: a newbie's 0.3 s tap keeps his 5:00 protection (no «Кража погасила…», no wait); a hold past the tap window ends it in the hold, before the carry"] = function(
	t
)
	local sim = S.boot(t)
	local defence = S.service(sim, "DefenceService")
	local victim = S.player(t, sim, 101, { tank = TANK })
	local kid = S.player(t, sim, 102, { fresh = true, protected = true })
	local kidBase = S.baseOf(sim, kid)
	t.eq(defence:IsProtected(kid), "newbie", "a fresh save: the newbie protection")
	local untilBefore = kidBase:GetAttribute("ProtectUntil")
	t.ok(
		type(untilBefore) == "number" and untilBefore - serverNow(sim) > SHIELD.JoinProtectFirst - 30,
		"≈ 5:00 of it"
	)

	-- the curious tap
	local cancel, saved = holdFor(t, sim, kid, victim, 3, 0.3)
	t.eq(cancel and cancel.Reason, "released", "the tap: Cancel «released»")
	t.eq(defence:IsProtected(kid), "newbie", "the tap kept his protection")
	t.eq(kidBase:GetAttribute("ProtectKind"), "newbie", "… on the base")
	t.eq(kidBase:GetAttribute("ProtectUntil"), untilBefore, "… to the same second")
	t.eq(
		notified(sim, kid, S.STEAL_TEXTS.Hint.Ended),
		false,
		"no «Кража погасила твою защиту»"
	)
	t.eq(cooldownLeft(sim, kid), 0, "no wait: a free tap")
	t.eq(saved, nil, "the victim: no Saved for the tap …")
	t.eq(#S.events(sim, victim, "Alert"), 0, "… and no Alert: he never heard of it (V-UX-01)")

	-- a real attempt: the protection goes once the hold outlasts the tap window — in the hold
	sim:Advance(1 / LIMITS.StartRate)
	local hold, prompt = S.hold(t, sim, kid, victim, 3)
	t.ok(hold.active, "the real hold began")
	sim:Advance(1)
	t.eq(defence:IsProtected(kid), "newbie", "1 s in: still protected (a let-go now would be a tap)")
	sim:Advance(0.5)
	t.eq(kid:GetAttribute("Stealing"), "hold", "still holding at 1.5 s")
	t.eq(defence:IsProtected(kid), nil, "past the 1.4 s tap window: his protection is gone")
	t.eq(kidBase:GetAttribute("ProtectKind"), nil, "… on the base too")
	t.ok(notified(sim, kid, S.STEAL_TEXTS.Hint.Ended), "«Кража погасила твою защиту»")
	local alerts = S.events(sim, victim, "Alert")
	t.eq(#alerts, 1, "… and now the victim's Alert")
	t.eq(alerts[1] and alerts[1].data.Quiet, nil, "… loud: the tap took nothing from it")
	local carried = sim:WaitFor(function()
		return kid:GetAttribute("Stealing") == "carry"
	end, S.BASE_HOLD, S.FRAME)
	t.ok(carried, "the carry")
	t.eq(defence:IsProtected(kid), nil, "nothing is carried under protection")
	if hold.active then
		sim:ReleasePrompt(kid, prompt)
	end
	S.out(sim, kid, victim, "gate")
	t.ok(S.last(sim, kid, "Done"), "credited")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- UX-02: the shield bait
--------------------------------------------------------------------------------

tests["UX-02: the shield bait — the owner's shield closes his base to that thief until the shield is ready again («shielded»), with no fail wait; another base stays open; back on time"] = function(
	t
)
	local sim = S.boot(t)
	local defence = S.service(sim, "DefenceService")
	local steal = S.service(sim, "StealService")
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local other = S.player(t, sim, 103, { tank = TANK })

	-- the bait: a hold, the kid taps ЩИТ as the game teaches him
	local hold, prompt = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active, "the bait hold")
	sim:Advance(1)
	sim:FireServer(victim, "ShieldActivate")
	sim:Advance(0.1)
	local cancel = S.last(sim, thief, "Cancel")
	t.eq(cancel and cancel.Reason, "shield", "Cancel «shield»")
	t.eq(cooldownLeft(sim, thief), 0, "no fail wait: the shield is not his fault")
	t.eq(cancel.BaseReason, "shielded", "… but the base is closed to him: «shielded»")
	local readyAt = victim:GetAttribute("ShieldReadyAt")
	t.near(
		cancel.BaseUntil,
		serverNow(sim) + SHIELD.Duration + LIMITS.ShieldWait,
		0.5,
		"until the shield's end + ShieldWait"
	)
	t.near(cancel.BaseUntil, readyAt, 0.5, "= when the owner's shield is ready again")
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	sim:Advance(0.2)

	-- under the shield: his own wait answers first (row «wait» before row «protect») — the whole of it
	local d = S.denied(t, sim, thief, victim, 2)
	t.eq(
		d and d.Reason,
		"shielded",
		"under the shield: «Хозяин включил щит — здесь красть снова через 4:00»"
	)
	t.near(d and d.Until, cancel.BaseUntil, 1, "Denied carries Until = the Cancel's BaseUntil")
	t.eq(
		S.denied(t, sim, other, victim, 2).Reason,
		"shield",
		"another thief there: the shield's own «Здесь щит»"
	)
	-- another base stays open
	sim:Advance(1 / LIMITS.StartRate)
	local cancel2 = holdFor(t, sim, thief, other, 3, 0.3)
	t.eq(cancel2 and cancel2.Reason, "released", "another base: a hold began there")
	t.eq(cancel2 and cancel2.BaseReason, nil, "… and it is not closed")

	-- the shield ends: the bait still costs him this base — «Хозяин включил щит — здесь …»
	sim:Advance(SHIELD.Duration + 0.5, S.COARSE)
	t.eq(defence:IsProtected(victim), nil, "the shield is over")
	t.ok((readyAt :: number) - serverNow(sim) > SHIELD.Cooldown - 5, "… and recharging")
	d = S.denied(t, sim, thief, victim, 3)
	t.eq(d and d.Reason, "shielded", "the base refuses him: «shielded»")
	t.near(d and d.Until, cancel.BaseUntil, 1, "Until = the Cancel's BaseUntil")
	t.ok(
		startsWith(d and d.Text, "shielded"),
		`«Хозяин включил щит — здесь красть снова через 3:00» ({d and d.Text})`
	)
	t.eq(thief:GetAttribute("Stealing"), nil, "no theft")

	-- back when the owner's shield is ready again
	sim:Advance(cancel.BaseUntil - serverNow(sim) - 2, S.COARSE)
	d = S.denied(t, sim, thief, victim, 3)
	t.eq(d and d.Reason, "shielded", "2 s before: still closed")
	sim:Advance(2.5)
	t.ok((victim:GetAttribute("ShieldReadyAt") or 0) <= serverNow(sim) + 0.1, "the owner's shield is ready")
	hold, prompt = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active, "the hold")
	t.eq(thief:GetAttribute("Stealing"), "hold", "the base is open to him again")
	sim:FireServer(victim, "ShieldActivate")
	sim:Advance(0.1)
	t.eq(S.last(sim, thief, "Cancel").Reason, "shield", "… and the owner can answer with his shield again")
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	sim:Advance(0.2)
	t.eq(steal._debugSizes().Tags, 1, "one closed pair (the new shield)")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- DATA-01: the tap window is free for both
--------------------------------------------------------------------------------

tests["DATA-01 / V-UX-01: a let-go at 1.2 s (inside the tap window) is a free tap for both — no StealCooldownUntil, nothing to the victim (no Alert, no Saved, no alarm); FreeTaps of them, then a failure (still nothing to him)"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local base = S.baseOf(sim, victim)
	local alarms = 0
	base:GetAttributeChangedSignal("AlarmState"):Connect(function()
		if base:GetAttribute("AlarmState") == "theft" then
			alarms += 1
		end
	end)
	for i = 1, LIMITS.FreeTaps do
		local cancel, saved = holdFor(t, sim, thief, victim, 3, 1.2)
		t.eq(cancel and cancel.Reason, "released", `tap {i}: «released»`)
		t.eq(cooldownLeft(sim, thief), 0, `tap {i}: no wait`)
		t.eq(saved, nil, `tap {i}: no Saved to the victim — no «Кража сорвалась» for a tap`)
		sim:Advance(1 / LIMITS.StartRate)
	end
	t.eq(#S.events(sim, victim, "Alert"), 0, "no Alert for a tap: it never outlasted the tap window")
	-- one more 1.2 s let-go in the window: spam — a failure (his wait), still nothing to the victim
	local cancel, saved = holdFor(t, sim, thief, victim, 3, 1.2)
	t.eq(cancel and cancel.Reason, "released")
	t.near(cooldownLeft(sim, thief), FAIL[1], 0.3, `tap {LIMITS.FreeTaps + 1}: a failure, {FAIL[1]} s`)
	t.eq(saved, nil, "… the victim still hears nothing")
	t.eq(#S.events(sim, victim, "Alert"), 0, "… no Alert")
	t.eq(alarms, 0, "the base's alarm (AlarmState «theft») never went off for these holds")

	-- the taps took nothing from a real attempt: a hold 4 s later is loud (V-UX-01: the tap did not
	-- take the pair's AlertCoalesce slot)
	sim:Advance(FAIL[1] + 1)
	local hold, prompt = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active, "the real hold")
	sim:Advance(1.6)
	local alerts = S.events(sim, victim, "Alert")
	t.eq(#alerts, 1, "the real hold: the victim's Alert")
	t.eq(alerts[1] and alerts[1].data.Quiet, nil, "… loud")
	t.eq(alarms, 1, "… and the alarm")
	sim:ReleasePrompt(thief, prompt)
	sim:Advance(0.2)
	local result = S.last(sim, victim, "Saved")
	t.eq(result and result.Reason, "released", "its end: Saved …")
	t.eq(result and result.Quiet, nil, "… loud «Кража сорвалась — рыба дома»")
	sim:AssertNoErrors({ warnings = true })
end

tests["V-UX-01: a 0.3 s tap every 31 s for 3 minutes on one kid — not a single Alert or Saved to him, no alarm, no wait for the thief"] = function(
	t
)
	local sim = S.boot(t)
	local steal = S.service(sim, "StealService")
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local base = S.baseOf(sim, victim)
	local alarms = 0
	base:GetAttributeChangedSignal("AlarmState"):Connect(function()
		if base:GetAttribute("AlarmState") ~= nil then
			alarms += 1
		end
	end)
	local taps = 0
	local start = sim:Time()
	while sim:Time() - start < 180 do
		local cancel = holdFor(t, sim, thief, victim, 3, 0.3)
		taps += 1
		t.eq(cancel and cancel.Reason, "released", `tap {taps}: «released»`)
		t.eq(cancel and cancel.BaseReason, nil, `tap {taps}: the base stays open`)
		t.eq(cooldownLeft(sim, thief), 0, `tap {taps}: no wait (a tap per 31 s is under FreeTaps per minute)`)
		sim:Advance(31 - 0.4, 0.25)
	end
	t.ok(taps >= 6, `{taps} taps`)
	t.eq(#S.events(sim, victim, "Alert"), 0, "not one Alert to the victim")
	t.eq(#S.events(sim, victim, "Saved"), 0, "not one Saved")
	t.eq(alarms, 0, "the base's alarm never went off")
	t.eq(steal._debugSizes().Alerts, 0, "no pair's loud-alert slot taken")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- UX-03: one thief, one kid
--------------------------------------------------------------------------------

tests["UX-03: two failures on one base close it to him for BaseWait («wary»: Cancel BaseUntil, Denied Until); other bases open; a coalesced (Quiet) alert ends quietly; open again on time"] = function(
	t
)
	local sim = S.boot(t)
	local steal = S.service(sim, "StealService")
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local other = S.player(t, sim, 103, { tank = TANK })

	-- the 1st failure: a loud alert, a loud result, the 1st step, the base open
	local cancel, saved = holdFor(t, sim, thief, victim, 3, 1.5)
	t.eq(cancel and cancel.Reason, "released", "1st: «released»")
	t.eq(cancel and cancel.BaseReason, nil, "1st: the base stays open")
	t.near(cooldownLeft(sim, thief), FAIL[1], 0.3, "1st: 3 s")
	t.eq(S.last(sim, victim, "Alert").Quiet, nil, "1st: a loud alert")
	t.eq(saved and saved.Quiet, nil, "1st: a loud result «Кража сорвалась — рыба дома»")
	sim:Advance(FAIL[1] + 0.2)

	-- the 2nd failure on the same base: the 2nd step and the base closed
	cancel, saved = holdFor(t, sim, thief, victim, 2, 1.5)
	t.eq(cancel and cancel.Reason, "released", "2nd: «released»")
	t.near(cooldownLeft(sim, thief), FAIL[2], 0.3, "2nd: 10 s")
	t.eq(cancel and cancel.BaseReason, "wary", `2nd: BaseFails {LIMITS.BaseFails} → the base closed «wary»`)
	t.near(cancel and cancel.BaseUntil, serverNow(sim) + LIMITS.BaseWait, 0.5, "for BaseWait")
	t.eq(S.last(sim, victim, "Alert").Quiet, true, "2nd: the alert coalesced (Quiet)")
	t.eq(saved and saved.Quiet, true, "2nd: so its result is quiet too (no second toast)")

	-- after his 10 s: other bases open, this one refuses with the time
	sim:Advance(FAIL[2] + 0.2)
	local d = S.denied(t, sim, thief, victim, 3)
	t.eq(d and d.Reason, "wary", "this base: «Хозяин настороже»")
	t.near(d and d.Until, cancel.BaseUntil, 1, "Until = the Cancel's BaseUntil")
	t.ok(
		startsWith(d and d.Text, "wary"),
		`«Хозяин настороже — здесь красть снова через 0:50» ({d and d.Text})`
	)
	sim:Advance(1 / LIMITS.StartRate)
	local tap = holdFor(t, sim, thief, other, 3, 0.3)
	t.eq(tap and tap.BaseReason, nil, "another base: open (a free tap there)")

	-- open again at BaseUntil
	sim:Advance(cancel.BaseUntil - serverNow(sim) + 0.3, S.COARSE)
	local hold, prompt = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active)
	t.eq(thief:GetAttribute("Stealing"), "hold", "the base is open to him again")
	sim:ReleasePrompt(thief, prompt)
	sim:Advance(0.2)
	sim:Advance(LIMITS.FailWindow + 1, S.COARSE)
	t.eq(steal._debugSizes().BaseFails, 0, "the per-base failures age out with FailWindow")
	sim:AssertNoErrors({ warnings = true })
end

tests["UX-03: a 150 s release-spam loop on one kid — ≤ 6 holds (8 before), ≤ 3 loud alerts and ≤ 3 loud results; every Quiet alert ends quietly"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local start = sim:Time()
	local holds = 0
	local closedUntil = 0
	while sim:Time() - start < 150 do
		local wait = math.max(cooldownLeft(sim, thief), closedUntil - serverNow(sim))
		if wait > 0 then
			sim:Advance(wait + 0.1, 0.25)
			continue
		end
		local cancel = holdFor(t, sim, thief, victim, 3, 1.5) -- (outside the tap window: a failure each time)
		holds += 1
		t.eq(cancel and cancel.Reason, "released", `hold {holds}`)
		closedUntil = if cancel and type(cancel.BaseUntil) == "number" then cancel.BaseUntil else 0
		sim:Advance(1 / LIMITS.StartRate)
	end
	-- pair each alert with its result (one theft at a time: Alert(hold), then Saved)
	local loudAlerts, loudResults = 0, 0
	local events = S.events(sim, victim)
	local lastAlert: any = nil
	for _, e in events do
		if e.kind == "Alert" then
			lastAlert = e.data
			if e.data.Quiet == nil then
				loudAlerts += 1
			end
		elseif e.kind == "Saved" then
			if e.data.Quiet == nil then
				loudResults += 1
			end
			if lastAlert and lastAlert.Quiet == true then
				t.eq(e.data.Quiet, true, "a Quiet alert's result is quiet")
			end
		end
	end
	-- loud ones at least AlertCoalesce apart
	local lastLoud = -math.huge
	for _, e in S.events(sim, victim, "Alert") do
		if e.data.Quiet == nil then
			t.ok(e.time - lastLoud >= LIMITS.AlertCoalesce - 0.1, `loud alerts {e.time - lastLoud} s apart`)
			lastLoud = e.time
		end
	end
	t.log(`150 s of release spam: {holds} holds, {loudAlerts} loud alerts, {loudResults} loud results`)
	t.ok(holds <= 6, `holds {holds} ≤ 6 (the critic measured 8 before the per-base close)`)
	t.ok(loudAlerts <= 3, `loud alerts {loudAlerts} ≤ 3 (5 before)`)
	t.ok(loudResults <= 3, `loud «Кража сорвалась» results {loudResults} ≤ 3 (8 before)`)
	t.ok(holds >= 4, `the loop ran ({holds} holds)`)
	sim:AssertNoErrors({ warnings = true })
end

return tests
