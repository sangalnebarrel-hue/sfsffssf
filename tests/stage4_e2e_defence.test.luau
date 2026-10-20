--[[
	Stage 4 END-TO-END, part 2 — the defences (docs/stage4_design.md §7.7 cases 2–4): the real server
	and the REAL clients of a phone thief, a tablet victim and (where the case says so) a desktop
	bystander (tests/stage4_e2e_kit.luau). The victim defends only with what he sees: the column
	«ЩИТ!», the plate's ЩИТ and ДОМОЙ, the «ЗАЩИТА» sheet's cards (two taps); the thief walks and
	holds «Украсть» as his own client shows it.

	  (2a) the victim taps the column «ЩИТ!» during the thief's hold → the hold is cancelled: the
	       thief's «СОРВАЛОСЬ!» «Хозяин включил щит — рыба дома», no fail wait; the
	       victim's one toast «Щит спас рыбу! 🛡️ 1:00», his chip in Guard; the bystander sees the
	       shield dome over the court;
	  (2b) the victim taps the plate's ЩИТ during the CARRY → the fish flies home (DC-01): back in its
	       display (the same uid, rebuilt on the victim's screen), the thief at 16 with nothing over
	       his head and no wait;
	  (2c) the victim taps the plate's ДОМОЙ in the hold → lands on his spawn facing the court
	       (+Z), runs at the carrier → the tag: «Вор пойман — рыба спасена!» and the fish home, the
	       thief «Хозяин тебя поймал!» and 20 s barred from this base;
	  (3)  dog + alarm bought from the sheet (two taps each: the money, the stamps «✔️ КУПЛЕНО», the
	       dog in the court): the thief walks into the plot → the early «👀 … у тебя во дворе!»; the
	       hold → the dog runs from the court and reaches him during the hold (Slowed before the
	       carry), the carry at 6.8 and the way out ≈ 2× the honest one; the red Highlight on the
	       bystander's screen (Occluded) and on the owner's (AlwaysOnTop); the siren;
	  (4)  the lock bought from the sheet → the thief's ring takes 4 s (his client sees
	       HoldDuration 4); letting go at 3 s fails («Кнопку надо держать до конца!»), a 4 s hold
	       after the fail wait carries.

	Run: lune run tools/run_tests.luau stage4_e2e_defence
]]

local roblox = require("@lune/roblox")

local E = require("./stage4_e2e_kit")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

local tests = {}

local function cardOf(p: any, name: string): any
	return p.PlayerGui.HUD.DefencePanel.Panel.Cards:FindFirstChild(name)
end

local function buyLabel(p: any, name: string): string
	local buy = cardOf(p, name).Buy
	local label, price = buy:FindFirstChild("Label"), buy:FindFirstChild("Price")
	if label and label.Visible and label.Text ~= "" then
		return label.Text
	end
	return if price then price.Text else ""
end

-- Two taps on a card's buy button, ≥ the arm apart: DefenceBuy once → "Bought".
local function buy(t: any, sim: any, p: any, card: string, item: string)
	local before = #E.defenceEvents(sim, p, "Bought")
	sim:Click(p, cardOf(p, card).Buy)
	sim:Advance(0.6)
	sim:Click(p, cardOf(p, card).Buy)
	t.ok(
		sim:WaitFor(function()
			return #E.defenceEvents(sim, p, "Bought") > before
		end, 2, E.FRAME),
		`{item}: bought («{buyLabel(p, card)}»)`
	)
	local list = E.defenceEvents(sim, p, "Bought")
	t.eq(list[#list] and list[#list].data.Item, item, `Bought {item}`)
	sim:Advance(1)
end

-- Opens «ЗАЩИТА» with its button (the sheet rises).
local function openSheet(t: any, sim: any, p: any)
	sim:Click(p, p.PlayerGui.HUD.RightButtons.DefenceButton)
	t.ok(
		sim:WaitFor(function()
			return p.PlayerGui.HUD.DefencePanel.Visible and cardOf(p, "DogCard") ~= nil
		end, 2, E.FRAME),
		"«ЗАЩИТА» opens the sheet"
	)
	sim:Advance(0.8)
end

local function closeSheet(sim: any, p: any)
	sim:Click(p, p.PlayerGui.HUD.DefencePanel.Panel.Close)
	sim:Advance(0.8)
end

-- The thief walks up to Slot_3 and begins the hold; returns prompt, hold.
local function startHold(t: any, sim: any, thief: any, victim: any): (any, any)
	local prompt = E.toCourt(t, sim, thief, victim, 3)
	sim:Advance(0.6)
	t.ok(E.seen(sim, thief, prompt) > 0, "«Украсть» is shown to the thief")
	local hold = sim:BeginHold(thief, prompt)
	t.ok(hold.active, `the hold began ({hold.cancelReason})`)
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == "hold"
		end, 1, E.FRAME),
		"the server took the hold"
	)
	return prompt, hold
end

-- The plate is up on the victim's screen in this phase.
local function plateUp(t: any, sim: any, victim: any, phase: string)
	t.ok(
		sim:WaitFor(function()
			local stats = E.alert(sim, victim)
			return stats.phase == phase and stats.shown ~= nil
		end, 2.5, E.FRAME), -- (the hold's alert comes once it outlasts the tap window, ≈ 1.4 s: V-UX-01)
		`the victim's alert ({phase}) is up`
	)
end

-- The fish is back in its display (server) with the same uid, nobody holding it.
local function fishHome(t: any, sim: any, victim: any, uid: string, what: string)
	local slot = E.slot(sim, victim, 3)
	t.eq(slot:GetAttribute("State"), "fish", `{what}: Slot_3 holds a fish`)
	t.eq(slot:GetAttribute("FishUid"), uid, `{what}: the same fish`)
	t.eq(slot:GetAttribute("StealPhase"), nil, `{what}: nobody holds it`)
end

local function thiefFree(t: any, sim: any, thief: any, what: string)
	t.eq(thief:GetAttribute("Stealing"), nil, `{what}: the theft is over`)
	t.eq(thief.Character.Humanoid.WalkSpeed, E.WALK, `{what}: the thief walks at 16`)
	t.eq(thief.Character:FindFirstChild("StolenFish"), nil, `{what}: nothing over his head`)
end

--------------------------------------------------------------------------------
-- (2) The shield and the tag
--------------------------------------------------------------------------------

tests["(2a) the column «ЩИТ!» in the hold: cancelled, the thief «Хозяин включил щит…» without a wait, one «Щит спас рыбу!» toast, the dome on the bystander's screen"] = function(
	t
)
	local cast = E.trio(t, { quick = true })
	local sim, victim, thief, bystander = cast.sim, cast.victim, cast.thief, cast.bystander
	local vu, tu = E.ui(sim, victim), E.ui(sim, thief)
	local base = E.baseOf(sim, victim)
	local victimToasts = E.toastWatch(victim)
	sim:Teleport(bystander, E.exitPoint(base, "gate") + Vector3.new(14, 0, -6))
	local uid = E.slot(sim, victim, 3):GetAttribute("FishUid")

	startHold(t, sim, thief, victim)
	plateUp(t, sim, victim, "hold")
	t.ok(E.defenceStats(sim, victim).alert, "the column button is «ЩИТ!»")
	t.eq(vu.defenceCaption.Text, E.DEFENCE_TEXTS.ButtonAlert, `its caption «{vu.defenceCaption.Text}»`)
	E.shieldTap(sim, victim, "column")
	sim:Advance(0.3)
	t.eq(#sim:ServerEventsFor(victim, "ShieldActivate"), 1, "one ShieldActivate from the column")
	t.eq(vu.sheet.Visible, false, "no sheet opened")
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == nil
		end, 1, E.FRAME),
		"the hold is cancelled"
	)
	local cancel = E.theftEvents(sim, thief, "Cancel")
	t.eq(cancel[#cancel] and cancel[#cancel].data.Reason, "shield", "Cancel «shield»")
	t.ok(
		sim:WaitFor(function()
			return E.mode(sim, thief) == "fail"
		end, 0.5, E.FRAME),
		"the thief's «СОРВАЛОСЬ!»"
	)
	t.eq(tu.barTitle.Text, E.BANNER.Fail)
	t.eq(tu.barReason.Text, E.CANCEL.shield, "«Хозяин включил щит — рыба дома»")
	t.eq(thief:GetAttribute("StealCooldownUntil"), nil, "no fail wait for the thief (not his fault)")
	fishHome(t, sim, victim, uid, "after the shield")
	thiefFree(t, sim, thief, "after the shield")
	t.ok(
		sim:WaitFor(function()
			local view = E.world(sim, bystander, base)
			return view ~= nil and view.dome ~= nil
		end, 1.5, E.FRAME),
		"the bystander sees the shield dome over the court"
	)
	t.eq(base:GetAttribute("ProtectKind"), "shield", "the base is under the shield")
	t.ok(vu.chip.Visible, "the victim's ShieldChip «🛡️ 1:00»")
	sim:Advance(4)
	local shieldToasts = 0
	for _, text in victimToasts do
		if string.find(text, "Щит", 1, true) then
			shieldToasts += 1
		end
	end
	t.ok(
		E.has(victimToasts, "Щит спас рыбу!"),
		`«Щит спас рыбу! 🛡️ 1:00» ({E.list(victimToasts)})`
	)
	t.eq(shieldToasts, 1, `one shield toast, not two ({E.list(victimToasts)})`)
	t.eq(E.seen(sim, thief, E.stealPrompt(sim, victim, 3)), 0, "the thief's prompts are hidden under the shield")
	sim:AssertNoErrors({ warnings = true })
end

tests["(2b) the plate's ЩИТ in the CARRY: the fish flies home (DC-01) — its display again, the thief at 16 with no wait"] = function(
	t
)
	local cast = E.trio(t, { quick = true, bystander = false })
	local sim, victim, thief = cast.sim, cast.victim, cast.thief
	local vu, tu = E.ui(sim, victim), E.ui(sim, thief)
	local base = E.baseOf(sim, victim)
	local world = E.module(sim, victim, "TankWorldController")
	local uid = E.slot(sim, victim, 3):GetAttribute("FishUid")

	local prompt, hold = startHold(t, sim, thief, victim)
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == "carry"
		end, prompt.HoldDuration + 1, E.FRAME),
		"the carry began"
	)
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	E.moveTo(sim, thief, E.exitPoint(base, "gate")) -- (he runs for the gate)
	plateUp(t, sim, victim, "carry")
	t.eq(vu.alert.Text.Title.Text, E.ALERT.Carry, "«ВОР УБЕГАЕТ!»")
	t.ok(
		string.find(vu.alert.Text.Sub.Text, "жми ЩИТ", 1, true) ~= nil,
		`«… — жми ЩИТ!» ({vu.alert.Text.Sub.Text})`
	)
	t.eq(E.slot(sim, victim, 3):GetAttribute("StealPhase"), "carry", "the fish is on the thief's head")
	E.shieldTap(sim, victim, "plate")
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == nil
		end, 1, E.FRAME),
		"the carry is stopped"
	)
	local cancel = E.theftEvents(sim, thief, "Cancel")
	t.eq(cancel[#cancel] and cancel[#cancel].data.Reason, "shield", "Cancel «shield»")
	t.eq(cancel[#cancel] and cancel[#cancel].data.Phase, "carry", "… in the carry")
	local saved = E.theftEvents(sim, victim, "Saved")
	t.eq(saved[#saved] and saved[#saved].data.Reason, "shield", "Saved «shield» to the victim")
	sim:Advance(0.2)
	fishHome(t, sim, victim, uid, "the fish flew home")
	thiefFree(t, sim, thief, "after the shield in the carry")
	t.eq(thief:GetAttribute("StealCooldownUntil"), nil, "no wait for the thief")
	t.eq(tu.barReason.Text, E.CANCEL.shield, "the thief reads why")
	t.ok(
		sim:WaitFor(function()
			return E.call(sim, victim, function()
				return world.GetFish(base, 3)
			end) ~= nil
		end, 3, E.FRAME),
		"the fish is back in its display on the victim's screen"
	)
	t.eq(E.alert(sim, victim).phase, nil, "the alert is over")
	sim:AssertNoErrors({ warnings = true })
end

tests["(2c) the plate's ДОМОЙ in the hold: he lands facing the court, runs at the carrier — the tag: «Вор пойман — рыба спасена!», the fish home, the thief barred from this base"] = function(
	t
)
	local cast = E.trio(t, { quick = true, bystander = false })
	local sim, victim, thief = cast.sim, cast.victim, cast.thief
	local vu, tu = E.ui(sim, victim), E.ui(sim, thief)
	local base = E.baseOf(sim, victim)
	local victimToasts = E.toastWatch(victim)
	local uid = E.slot(sim, victim, 3):GetAttribute("FishUid")
	-- The victim is away from home (at the market side of his pier: 60 studs out).
	local away = E.basePoint(base, 0, -60, E.HRP_HEIGHT)
	sim:Teleport(victim, away)
	sim:Advance(0.3)

	local prompt, hold = startHold(t, sim, thief, victim)
	plateUp(t, sim, victim, "hold")
	local homeButton = vu.alert.Buttons.Home
	t.ok(homeButton.Visible and homeButton.AbsoluteSize.Y >= E.THEFT_UI.HomeMin - 0.5, "the plate's ДОМОЙ")
	sim:Click(victim, homeButton)
	t.ok(
		sim:WaitFor(function()
			local root = victim.Character.HumanoidRootPart
			return (root.Position - away).Magnitude > 20
		end, 1.5, E.FRAME),
		"ДОМОЙ: the victim landed on his spawn"
	)
	local look = victim.Character.HumanoidRootPart.CFrame.LookVector
	local plusZ = base:GetPivot().LookVector * -1 -- (the base's +Z: into the court)
	local zAxis = base:GetPivot():VectorToWorldSpace(Vector3.new(0, 0, 1))
	t.ok(
		Vector3.new(look.X, 0, look.Z).Unit:Dot(Vector3.new(zAxis.X, 0, zAxis.Z).Unit) > 0.9,
		`he faces the court (+Z; look {look}, +Z {zAxis}, -Look {plusZ})`
	)

	-- The hold completes; the thief runs for the gate, the owner runs at him.
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == "carry"
		end, prompt.HoldDuration + 1, E.FRAME),
		"the carry began"
	)
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	local gate = E.exitPoint(base, "gate")
	local ended = sim:WaitFor(function()
		E.moveTo(sim, thief, gate)
		E.moveTo(sim, victim, thief.Character.HumanoidRootPart.Position)
		return thief:GetAttribute("Stealing") == nil
	end, 12, 0.1)
	t.ok(ended, "the run ended")
	local cancel = E.theftEvents(sim, thief, "Cancel")
	t.eq(cancel[#cancel] and cancel[#cancel].data.Reason, "tag", "the owner tagged him")
	t.eq(#E.theftEvents(sim, thief, "Done"), 0, "no credit")
	sim:Advance(0.3)
	fishHome(t, sim, victim, uid, "after the tag")
	thiefFree(t, sim, thief, "after the tag")
	t.eq(tu.barReason.Text, E.CANCEL.tag, "the thief reads «Хозяин тебя поймал!»")
	sim:Advance(3)
	t.ok(
		E.has(victimToasts, E.RESULT.Saved.tag),
		`«Вор пойман — рыба спасена!» ({E.list(victimToasts)})`
	)
	-- After the fail wait the base stays barred (TagCooldown), the prompt hidden for him.
	sim:Advance(E.LIMITS.FailCooldown[1] + 0.5)
	E.moveTo(sim, victim, E.basePoint(base, 0, -40, E.HRP_HEIGHT)) -- (the owner walks away)
	sim:Advance(2)
	local again = E.toCourt(t, sim, thief, victim, 2)
	sim:Advance(0.6)
	t.eq(E.seen(sim, thief, again), 0, "barred from this base: no «Украсть» for him")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- (3) Dog + alarm
--------------------------------------------------------------------------------

tests["(3) dog + alarm bought from the sheet; the early «у тебя во дворе!»; the dog reaches him during the hold — the carry at 6.8, ≈ 2× as long; the red Highlight for the bystander and the owner"] = function(
	t
)
	local DOG, ALARM = E.DOG.Price, E.DefenceConfig.Alarm.Price
	local cast = E.trio(t, { quick = true, victim = { money = DOG + ALARM + 500 } })
	local sim, victim, thief, bystander = cast.sim, cast.victim, cast.thief, cast.bystander
	local vu = E.ui(sim, victim)
	local base = E.baseOf(sim, victim)
	local victimToasts = E.toastWatch(victim)
	sim:Teleport(bystander, E.exitPoint(base, "gate") + Vector3.new(14, 0, -6))

	-- The sheet: two taps each.
	openSheet(t, sim, victim)
	local log = E.moneyLog(sim)
	buy(t, sim, victim, "DogCard", "Dog")
	buy(t, sim, victim, "AlarmCard", "Alarm")
	local spentDog = E.earned(log, victim, "defence:Dog")
	local spentAlarm = E.earned(log, victim, "defence:Alarm")
	t.eq(spentDog, -DOG, "the dog cost $6 000 (the ledger)")
	t.eq(spentAlarm, -ALARM, "the alarm cost $2 500")
	t.eq(E.service(sim, "DataService"):Get(victim).Stats.Spent, DOG + ALARM, "Stats.Spent")
	t.eq(buyLabel(victim, "DogCard"), E.DEFENCE_TEXTS.Buy.Bought, "the dog card: «✔️ КУПЛЕНО»")
	t.eq(buyLabel(victim, "AlarmCard"), E.DEFENCE_TEXTS.Buy.Bought, "the alarm card: «✔️ КУПЛЕНО»")
	closeSheet(sim, victim)
	t.eq(base:GetAttribute("HasDog"), true, "the base has the dog")
	t.eq(base:GetAttribute("HasAlarm"), true, "… and the alarm")
	local dog = base:FindFirstChild("Dog")
	t.eq(dog and dog:GetAttribute("Unlocked"), true, "the dog shows")
	local rest = E.basePoint(base, E.DOG.Rest.X, E.DOG.Rest.Z)
	local pup = dog.Pup:GetPivot().Position
	t.ok(Vector3.new(pup.X - rest.X, 0, pup.Z - rest.Z).Magnitude < 1, "asleep at its court spot")

	-- The thief walks in: the early warning.
	local prompt = E.toCourt(t, sim, thief, victim, 3)
	t.ok(
		sim:WaitFor(function()
			return #E.theftEvents(sim, victim, "Intruder") > 0
		end, E.DefenceConfig.Alarm.IntruderEvery + 1, E.FRAME),
		"the alarm's early warning (Intruder)"
	)
	sim:Advance(0.5)
	t.ok(
		E.has(victimToasts, E.fill(E.STEAL_TEXTS.Intruder, { name = thief.DisplayName })),
		`«{E.fill(E.STEAL_TEXTS.Intruder, { name = thief.DisplayName })}» ({E.list(victimToasts)})`
	)

	-- The hold: the dog wakes and reaches him before the hold ends.
	sim:Advance(0.3)
	local phases = E.phaseLog(sim, thief)
	local slowedAt
	thief:GetAttributeChangedSignal("Slowed"):Connect(function()
		if thief:GetAttribute("Slowed") and not slowedAt then
			slowedAt = sim:Time()
		end
	end)
	local hold = sim:BeginHold(thief, prompt)
	t.ok(hold.active, `the hold began ({hold.cancelReason})`)
	sim:Advance(0.3)
	t.ok(dog:GetAttribute("DogState") ~= "Sleep", `the dog woke ({dog:GetAttribute("DogState")})`)
	t.ok(
		sim:WaitFor(function()
			local view = E.world(sim, bystander, base)
			return view ~= nil and view.mark ~= nil
		end, 2.5, E.FRAME),
		"the bystander sees the thief marked (once the hold outlasts the tap window: F-10)"
	)
	local mark = E.world(sim, bystander, base).mark
	t.eq(mark.ClassName, "Highlight", "a Highlight")
	t.eq(mark.DepthMode, Enum.HighlightDepthMode.Occluded, "Occluded for a bystander")
	local ownerMark = E.world(sim, victim, base)
	t.eq(
		ownerMark and ownerMark.mark and ownerMark.mark.DepthMode,
		Enum.HighlightDepthMode.AlwaysOnTop,
		"AlwaysOnTop for the owner"
	)
	t.ok(
		sim:WaitFor(function()
			local view = E.world(sim, bystander, base)
			return view ~= nil and view.siren ~= nil
		end, 2.5, E.FRAME),
		"the siren spins (the base's alarm starts once the hold outlasts the tap window: F-10)"
	)
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == "carry"
		end, prompt.HoldDuration + 1, E.FRAME),
		"the carry began"
	)
	local carryAt = E.phaseAt(phases, "carry")
	t.ok(
		slowedAt ~= nil and carryAt ~= nil and slowedAt < carryAt,
		`the dog reached him during the hold (Slowed at {slowedAt}, carry at {carryAt})`
	)
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	sim:Advance(0.2)
	t.near(thief.Character.Humanoid.WalkSpeed, E.CARRY * E.DOG.Slow, 1e-6, "the carry at 6.8")
	t.ok(thief.PlayerGui.HUD.TheftBar.DogChip.Visible, "«🐕 СОБАКА!» on his bar")

	-- Out of the gate at the dog's pace: ≈ 2× the honest carry.
	local from = thief.Character.HumanoidRootPart.Position
	t.ok(E.walkOut(sim, thief, victim, "gate"), "he still gets out (the dog only slows)")
	local doneAt = E.phaseAt(phases, nil)
	local to = thief.Character.HumanoidRootPart.Position
	local path = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
	local took = doneAt - carryAt
	local honest = path / E.CARRY
	t.ok(took >= 1.7 * honest, `the way out took {took} s ≈ 2× the honest {honest} s ({path} studs)`)
	t.eq(#E.theftEvents(sim, thief, "Done"), 1, "credited once")
	sim:Advance(0.5)
	t.eq(thief.Character.Humanoid.WalkSpeed, E.WALK, "16 again after the credit")
	t.eq(thief:GetAttribute("Slowed"), nil, "Slowed cleared")
	t.eq(E.world(sim, bystander, base).mark, nil, "the Highlight is gone")
	sim:Advance(E.DOG.SlowLinger + 3)
	t.eq(dog:GetAttribute("DogTarget"), nil, "the dog let go")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- (4) The lock
--------------------------------------------------------------------------------

tests["(4) the lock bought from the sheet: the thief's ring takes 4 s — letting go at 3 s fails, 4 s after the fail wait carries"] = function(
	t
)
	local LOCK1 = E.LOCK.Levels[1]
	local cast = E.trio(t, { quick = true, bystander = false, victim = { money = LOCK1.Price + 200 } })
	local sim, victim, thief = cast.sim, cast.victim, cast.thief
	local tu = E.ui(sim, thief)
	local base = E.baseOf(sim, victim)

	openSheet(t, sim, victim)
	buy(t, sim, victim, "LockCard", "Lock")
	closeSheet(sim, victim)
	t.eq(victim:GetAttribute("LockLevel"), 1, "lock level 1")
	t.eq(base:GetAttribute("HoldTime"), LOCK1.Hold, "the base's hold time 4 s")

	local prompt = E.toCourt(t, sim, thief, victim, 3)
	sim:Advance(0.6)
	t.eq(prompt.HoldDuration, LOCK1.Hold, "the server's HoldDuration 4")
	t.eq(
		E.call(sim, thief, function()
			return prompt.HoldDuration
		end),
		LOCK1.Hold,
		"… and the thief's client sees 4 s"
	)
	-- 3 s (the old hold) is not enough.
	local hold = sim:BeginHold(thief, prompt)
	t.ok(hold.active, "the hold began")
	sim:Advance(E.BASE_HOLD + 0.05)
	t.eq(hold.triggered, false, "not triggered at 3 s")
	t.eq(thief:GetAttribute("Stealing"), "hold", "still holding at 3 s")
	sim:ReleasePrompt(thief, prompt)
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == nil
		end, 1, E.FRAME),
		"letting go at 3 s ends it"
	)
	local cancel = E.theftEvents(sim, thief, "Cancel")
	t.eq(cancel[#cancel] and cancel[#cancel].data.Reason, "released", "Cancel «released»")
	t.ok(
		sim:WaitFor(function()
			return E.mode(sim, thief) == "fail"
		end, 0.5, E.FRAME),
		"«СОРВАЛОСЬ!»"
	)
	t.eq(tu.barReason.Text, E.CANCEL.released, "«Кнопку надо держать до конца!»")
	t.eq(E.slot(sim, victim, 3):GetAttribute("State"), "fish", "the fish stays")

	-- The fail wait, then the full 4 s.
	sim:Advance(E.LIMITS.FailCooldown[1] + 0.5)
	t.ok(E.seen(sim, thief, prompt) > 0, "«Украсть» again after the wait")
	local holdAt = sim:Time()
	local again = sim:BeginHold(thief, prompt)
	t.ok(again.active, "the second hold began")
	t.ok(
		sim:WaitFor(function()
			return thief:GetAttribute("Stealing") == "carry"
		end, LOCK1.Hold + 1, E.FRAME),
		"4 s: the carry"
	)
	local took = sim:Time() - holdAt
	t.ok(took >= LOCK1.Hold - 0.05, `the ring took {took} s (≥ 4)`)
	if again.active then
		sim:ReleasePrompt(thief, prompt)
	end
	t.ok(E.walkOut(sim, thief, victim, "gate"), "out of the gate")
	t.eq(#E.theftEvents(sim, thief, "Done"), 1, "credited")
	sim:AssertNoErrors({ warnings = true })
end

return tests
