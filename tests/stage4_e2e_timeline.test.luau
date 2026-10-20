--[[
	Stage 4 END-TO-END, part 4 — the busy victim (docs/stage4_design.md §7.7 cases 7 and 8, DC-21 and
	DC-02): the real server and the REAL clients of the thief and a victim who is fishing for real
	(the careful player bot of tests/stage3_e2e_kit: it taps the action button it sees).

	  (7) the timeline: a phone victim casts, the bite comes, he hooks — the minigame; the thief's
	      hold starts on his tank; at the hold's end + 1 s (the carry) he taps the column «ЩИТ!» →
	      the fish flies home, the thief's «СОРВАЛОСЬ!» «Хозяин включил щит…», and the minigame never
	      noticed (no FishingState change, «ЛОВИ!» still sends FishingTap); «Щит спас рыбу!» comes
	      once the fishing lets the toast through;
	  (8) the catch card: a tablet victim lands a Mythic (the forced next fish) and a hold starts on
	      his base while its card is up → once the hold outlasts the tap window the alert comes and
	      the card closes within 1 s by its normal path (the 🐟 still flies into «САДОК», 4/6 → 5/6),
	      the plate pops in, his tap on its ЩИТ saves the fish.
	  (10) the bait log (§11.7 F-05): the victim's shield ends — «Щит погас» on his phone; another
	      thief's hold a second later pushes the read toast out with the alert, and when the alert
	      is over it does not come back (the critic saw it twice for the server's one Notify).
	  (11) the free tap (§11.7 F-10, V-UX-01): a 0.3 s tap on «Украсть» never reaches the victim's
	      phone — no Alert or Saved, no alarm in his AlertController, no ping, no shake, no HurryCard,
	      his pier word stays white and his open «САДОК» stays open; the thief waits nothing; a real
	      hold 4 s later is loud (the alert, Theft.Pings pings, the shake, the card hurried, «САДОК»
	      closed, «🚨 КРАДУТ!» at his bucket).

	Run: lune run tools/run_tests.luau stage4_e2e_timeline
]]

local E = require("./stage4_e2e_kit")

local tests = {}

-- The bot casts and plays until the minigame is on (then it stops playing: the test taps).
local function intoMinigame(t: any, sim: any, p: any, hud: any): any
	E.goFish(t, sim, p)
	E.forceFish(sim, "Puffer", 1)
	local fisher = E.Fisher.new(sim, p, hud)
	fisher:cast()
	t.ok(
		sim:WaitFor(function()
			fisher:look()
			return fisher.stage == "reeling" or fisher:done()
		end, 25, E.FRAME),
		`{p.Name}: the minigame\n{fisher:describe()}`
	)
	t.eq(fisher.stage, "reeling", "reeling")
	t.eq(E.lastFishingState(sim, p), "Minigame", "FishingState Minigame")
	return fisher
end

tests["(7) the timeline: the victim in the minigame taps the column «ЩИТ!» at the hold's end + 1 s — the fish home, the thief «СОРВАЛОСЬ!», the minigame never noticed"] = function(
	t
)
	local cast = E.trio(t, { quick = true, bystander = false, victim = { device = "phone" } })
	local sim, victim, thief = cast.sim, cast.victim, cast.thief
	local hud = E.hud(sim, victim)
	local tu = E.ui(sim, thief)
	local victimToasts = E.toastWatch(victim)
	local uid = E.slot(sim, victim, 3):GetAttribute("FishUid")
	local prompt = E.toCourt(t, sim, thief, victim, 3)
	sim:Advance(0.3)

	intoMinigame(t, sim, victim, hud)
	local states = #sim:ClientEventsFor(victim, "FishingState")
	local phases = E.phaseLog(sim, thief)
	local hold = sim:BeginHold(thief, prompt)
	t.ok(hold.active, "the thief's hold began during the minigame")
	t.ok(
		sim:WaitFor(function()
			return E.alert(sim, victim).phase == "hold"
		end, 2.5, E.FRAME),
		"the victim's alert is on (once the hold outlasts the tap window)"
	)
	t.ok(E.defenceStats(sim, victim).alert, "«ЩИТ!» on the column")
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == "carry"
		end, prompt.HoldDuration + 1, E.FRAME),
		"the hold ended: the carry"
	)
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	local carryAt = E.phaseAt(phases, "carry") :: number
	E.moveTo(sim, thief, E.exitPoint(E.baseOf(sim, victim), "gate"))
	sim:Advance(math.max(0, carryAt + 1 - sim:Time()))
	t.eq(thief:GetAttribute("Stealing"), "carry", "1 s into the carry, still in the plot")
	E.shieldTap(sim, victim, "column")
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == nil
		end, 1, E.FRAME),
		"the carry stopped"
	)
	t.eq(#sim:ServerEventsFor(victim, "ShieldActivate"), 1, "one ShieldActivate")
	local saved = E.theftEvents(sim, victim, "Saved")
	t.eq(saved[#saved] and saved[#saved].data.Reason, "shield", "Saved «shield»")
	t.ok(
		sim:WaitFor(function()
			return E.mode(sim, thief) == "fail"
		end, 0.5, E.FRAME),
		"the thief's «СОРВАЛОСЬ!»"
	)
	t.eq(tu.barReason.Text, E.CANCEL.shield, "«Хозяин включил щит — рыба дома»")
	sim:Advance(0.3)
	t.eq(E.slot(sim, victim, 3):GetAttribute("FishUid"), uid, "the fish is home")
	-- The minigame never noticed.
	local list = sim:ClientEventsFor(victim, "FishingState")
	for i = states + 1, #list do
		t.ok(list[i].args[1] == "Zone" or list[i].args[1] == "Minigame", `no FishingState change ({list[i].args[1]})`)
	end
	E.minigameAnswers(t, sim, victim, "after the shield in the carry")
	t.ok(
		sim:WaitFor(function()
			return E.has(victimToasts, "Щит спас рыбу!")
		end, E.FishingConfig.MinigameTimeout + 8, E.COARSE),
		`«Щит спас рыбу!» once the fishing lets it through ({E.list(victimToasts)})`
	)
	sim:AssertNoErrors({ warnings = true })
end

tests["(8) the catch card: a Mythic card is up when the hold starts — it closes within 1 s of the alert (the 🐟 still flies into «САДОК»), the plate pops in, its ЩИТ saves the fish"] = function(
	t
)
	local cast = E.trio(t, { quick = true, bystander = false })
	local sim, victim, thief = cast.sim, cast.victim, cast.thief
	local hud = E.hud(sim, victim)
	local vu = E.ui(sim, victim)
	local uid = E.slot(sim, victim, 3):GetAttribute("FishUid")
	local prompt = E.toCourt(t, sim, thief, victim, 3)
	sim:Advance(0.3)

	E.goFish(t, sim, victim)
	E.forceFish(sim, "DragonFish", 8)
	local caught = E.catch(t, sim, victim, hud, "the Mythic")
	t.eq(caught.Fish.Rarity, "Mythic", "a Mythic")
	t.ok(hud.card.Visible, "its card is up")
	local cardUp = sim:Time()

	local hold = sim:BeginHold(thief, prompt)
	t.ok(hold.active, "the thief's hold began while the card is up")
	t.ok(
		sim:WaitFor(function()
			return E.alert(sim, victim).phase == "hold"
		end, 2.5, E.FRAME),
		"the victim's alert (once the hold outlasts the tap window)"
	)
	local alertAt = sim:Time()
	t.ok(
		sim:WaitFor(function()
			return not hud.card.Visible
		end, 1, E.FRAME),
		`the card closed within 1 s of the alert (HurryCard; {sim:Time() - alertAt} s, {sim:Time() - cardUp} s up)`
	)
	t.ok(
		sim:WaitFor(function()
			return hud.screen:GetAttribute("CounterHold") == nil
		end, 2, E.FRAME),
		"the 🐟 flew into «САДОК» (CounterHold cleared)"
	)
	t.ok(
		sim:WaitFor(function()
			return hud.tankChip.Text == "5/6"
		end, 2, E.FRAME),
		`«САДОК» 5/6 ({hud.tankChip.Text})`
	)
	t.ok(
		sim:WaitFor(function()
			local stats = E.alert(sim, victim)
			return stats.shown == "plate"
		end, 1.5, E.FRAME),
		"the plate popped in"
	)
	t.ok(thief:GetAttribute("Stealing") ~= nil, `the theft is still on ({thief:GetAttribute("Stealing")})`)
	E.shieldTap(sim, victim, "plate")
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == nil
		end, 1, E.FRAME),
		"the shield stopped the theft"
	)
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	local saved = E.theftEvents(sim, victim, "Saved")
	t.eq(saved[#saved] and saved[#saved].data.Reason, "shield", "Saved «shield»")
	sim:Advance(0.3)
	t.eq(E.slot(sim, victim, 3):GetAttribute("FishUid"), uid, "the fish is home")
	t.eq(victim:GetAttribute("TankCount"), 5, "the victim keeps 5 fish (the Mythic and the saved one)")
	t.eq(vu.alert.Visible and E.alert(sim, victim).phase ~= nil, false, "the alert is over")
	sim:AssertNoErrors({ warnings = true })
end

tests["(10) the bait log (F-05): the shield ends — «Щит погас» once; another thief's short hold a second later pushes it out, and after his alert it does not come back"] = function(
	t
)
	local cast = E.trio(t, { quick = true, victim = { device = "phone" } })
	local sim, victim, thief, other = cast.sim, cast.victim, cast.thief, cast.bystander
	local victimToasts = E.toastWatch(victim)
	local base = E.baseOf(sim, victim)
	-- the bait: the thief's hold, the kid taps the plate's ЩИТ (the base is closed to that thief now)
	local prompt = E.toCourt(t, sim, thief, victim, 3)
	local hold = sim:BeginHold(thief, prompt)
	t.ok(hold.active, "the bait hold")
	t.ok(
		sim:WaitFor(function()
			local stats = E.alert(sim, victim)
			return stats.phase == "hold" and stats.shown ~= nil
		end, 2.5, E.FRAME),
		"the victim's alert (once the hold outlasts the tap window)"
	)
	sim:Advance(0.2)
	E.shieldTap(sim, victim, "plate")
	sim:Advance(0.6)
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	t.eq(E.theftEvents(sim, thief, "Cancel")[1].data.BaseReason, "shielded", "the bait closed the base to him")
	-- another thief waits by the display for the shield to end
	local second = E.toCourt(t, sim, other, victim, 2)
	local left = base:GetAttribute("ProtectUntil") - E.serverNow(sim)
	sim:Advance(left - 0.5, E.COARSE)
	t.ok(
		sim:WaitFor(function()
			return E.has(victimToasts, E.DEFENCE_TEXTS.Shield.Off)
		end, 3, E.FRAME),
		"«Щит погас» on the victim's screen"
	)
	local offAt = sim:Time()
	sim:Advance(math.max(0, offAt + 1.0 - sim:Time()))
	E.standAt(sim, other, second)
	local hold2 = sim:BeginHold(other, second)
	t.ok(hold2.active, "the second thief's hold, a second after «Щит погас»")
	t.ok(
		sim:WaitFor(function()
			return E.alert(sim, victim).phase == "hold"
		end, 2.5, E.FRAME),
		"the victim's alert (once the hold outlasts the tap window)"
	)
	sim:Advance(0.8)
	if hold2.active then
		sim:ReleasePrompt(other, second)
	end
	sim:Advance(E.UIConfig.ToastDuration + 3, E.COARSE)
	local count = 0
	for _, text in victimToasts do
		if text == E.DEFENCE_TEXTS.Shield.Off then
			count += 1
		end
	end
	local notified = 0
	for _, e in sim:ClientEventsFor(victim, "Notify") do
		if e.args[1] == E.DEFENCE_TEXTS.Shield.Off then
			notified += 1
		end
	end
	t.eq(notified, 1, "the server sent one Notify «Щит погас»")
	t.eq(count, 1, `… and the victim saw one toast ({E.list(victimToasts)})`)
	sim:AssertNoErrors({ warnings = true })
end

-- What the victim's own client does for an alarm: pings (UiFx.sound "ping"), shakes of the alert
-- (UiFx.shake on HUD.TheftAlert or inside it), FishingController.HurryCard calls.
local function alarmSpy(sim: any, p: any): { pings: number, shakes: number, hurry: number }
	local UiFx = sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p)
	local spy = { pings = 0, shakes = 0, hurry = 0 }
	local sound, shake = UiFx.sound, UiFx.shake
	UiFx.sound = function(name: any, ...: any): any
		if name == "ping" then
			spy.pings += 1
		end
		return sound(name, ...)
	end
	local alertRoot = p.PlayerGui.HUD.TheftAlert
	UiFx.shake = function(gui: any, ...: any): any
		if gui == alertRoot or gui:IsDescendantOf(alertRoot) then
			spy.shakes += 1
		end
		return shake(gui, ...)
	end
	local fishing = E.module(sim, p, "FishingController")
	local hurry = fishing.HurryCard
	fishing.HurryCard = function(...: any): any
		spy.hurry += 1
		return hurry(...)
	end
	return spy
end

local function pierRed(sim: any, p: any): boolean
	local pier = E.call(sim, p, function()
		return E.module(sim, p, "TankWorldController").GetPierWord()
	end)
	local alarm = pier and pier:FindFirstChild("Alarm", true)
	return alarm ~= nil and alarm.Visible == true
end

tests["(11) the free tap (F-10, V-UX-01): a 0.3 s tap never reaches the victim's phone — no alert, ping, shake or HurryCard, «САДОК» stays open; a real hold 4 s later is loud"] = function(
	t
)
	local cast = E.trio(t, { quick = true, bystander = false, victim = { device = "phone" } })
	local sim, victim, thief = cast.sim, cast.victim, cast.thief
	local hud = E.hud(sim, victim)
	local spy = alarmSpy(sim, victim)
	local prompt = E.toCourt(t, sim, thief, victim, 3)
	sim:Advance(0.3)
	E.openPanel(t, sim, victim, hud)

	-- the tap: 0.3 s, then 2 s of looking at the victim's phone
	local seen = { alarm = false, pier = false }
	local function look(): boolean
		seen.alarm = seen.alarm or E.alert(sim, victim).phase ~= nil
		seen.pier = seen.pier or pierRed(sim, victim)
		return false
	end
	local hold = sim:BeginHold(thief, prompt)
	t.ok(hold.active, "the tap began")
	sim:WaitFor(look, 0.3, E.FRAME)
	t.eq(thief:GetAttribute("Stealing"), "hold", "the server took the hold")
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	sim:WaitFor(look, 2, E.FRAME)
	local cancel = E.theftEvents(sim, thief, "Cancel")
	t.eq(cancel[#cancel] and cancel[#cancel].data.Reason, "released", "the thief let go")
	local untilT = thief:GetAttribute("StealCooldownUntil")
	t.ok(untilT == nil or untilT <= E.serverNow(sim), "a free tap: the thief waits nothing")
	t.eq(#E.theftEvents(sim, victim, "Alert"), 0, "no Alert reached the victim")
	t.eq(#E.theftEvents(sim, victim, "Saved"), 0, "… and no Saved")
	t.eq(seen.alarm, false, "his AlertController never raised an alarm")
	t.eq(seen.pier, false, "his pier word never turned red")
	t.eq(spy.pings, 0, "no ping")
	t.eq(spy.shakes, 0, "no shake")
	t.eq(spy.hurry, 0, "no HurryCard")
	t.ok(hud.panel.Visible, "his «САДОК» stays open")

	-- a real hold 4 s after the tap: the whole loud alarm
	sim:Advance(4 - 2.3)
	hold = sim:BeginHold(thief, prompt)
	t.ok(hold.active, "the real hold began")
	t.ok(
		sim:WaitFor(function()
			return E.alert(sim, victim).phase == "hold"
		end, 2.5, E.FRAME),
		"the victim's alert (once the hold outlasts the tap window)"
	)
	local alerts = E.theftEvents(sim, victim, "Alert")
	t.eq(#alerts, 1, "one Alert")
	t.eq(alerts[1] and alerts[1].data.Quiet, nil, "… loud: the tap took nothing from it")
	t.ok(
		sim:WaitFor(function()
			return not hud.panel.Visible
		end, 1, E.FRAME),
		"the loud alert closes «САДОК»"
	)
	sim:Advance(E.THEFT_UI.PingGap * E.THEFT_UI.Pings + 0.3)
	t.eq(spy.pings, E.THEFT_UI.Pings, `{E.THEFT_UI.Pings} pings`)
	t.ok(spy.shakes >= 1, `the alert shook ({spy.shakes})`)
	t.ok(spy.hurry >= 1, `HurryCard ({spy.hurry})`)
	t.ok(pierRed(sim, victim), "«🚨 КРАДУТ!» at his bucket")
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	sim:Advance(0.5)
	sim:AssertNoErrors({ warnings = true })
end

return tests
