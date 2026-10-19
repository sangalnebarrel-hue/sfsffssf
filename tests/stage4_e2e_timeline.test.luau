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
	      his base while its card is up → the card closes within 1 s by its normal path (the 🐟 still
	      flies into «САДОК», 4/6 → 5/6), the plate pops in, his tap on its ЩИТ saves the fish.

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
		end, 1, E.FRAME),
		"the victim's alert is on"
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

tests["(8) the catch card: a Mythic card is up when the hold starts — it closes within 1 s (the 🐟 still flies into «САДОК»), the plate pops in, its ЩИТ saves the fish"] = function(
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
			return not hud.card.Visible
		end, 1, E.FRAME),
		`the card closed within 1 s (HurryCard; {sim:Time() - cardUp} s)`
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

return tests
