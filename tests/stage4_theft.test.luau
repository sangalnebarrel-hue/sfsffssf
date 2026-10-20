--[[
	Stage 4 wave 1 A — the theft state machine on the server (docs/stage4_design.md §4.2–§4.4,
	§4.7, §7.2), run inside RbxSim against the built Place1.rbxl with headless players and the sim
	DataStore (tests/stage4_server.luau):
	  • hold → carry → exit → credit: both tanks, the slot attributes in order (StealBy / StealEnd
	    before StealPhase, Event last), Event "stolen|<thief>", Origin, the Age kept, the stats, the
	    cooldown, the victim's after, the escrow set and cleared at the victim's commit (the thief's
	    income without the fish until then), TheftStarted / TheftEnded;
	  • Carry.Enabled = false → credit at the hold end (the only test of that mode; DC-19);
	  • every cancel reason: released, far (a 9-stud teleport → HoldEnded classified far; BE-13),
	    died (KillCharacter), the thief leaves (hold and carry), the victim leaves (hold and carry),
	    the shield in the hold and in the carry (returned, the fish back in its display, the thief
	    at 16, no fail wait; DC-01), tag (the fail step + tagged 20 s on that base, another base
	    allowed after the fail step), deadline (the server HoldDuration raised mid-hold), early
	    (FirePromptEvent Triggered at 1 s → the next ordinary fail step, not the last: UX-04), the
	    carry timeout (these chains run with Limits.BaseFails off: the per-base close after two
	    failures has its own tests in stage4_fairness_grief);
	  • a late HoldBegan (UX-04, an honest phone on a slow link): a Triggered from Need × LateShare
	    on is taken — the server ends the hold itself at T0 + Need (no earlier), with the watcher's
	    checks (a walk-away in that window is «far»); under LateShare it is «early»;
	  • the speed budget with Kit.drive (BE-9, BE-35): 16 st/s under the dog → returned within 3 s;
	    an honest walk under the dog with a 1.2 s freeze and the catch-up → not returned; a 30-stud
	    hop → returned; a teleport straight out of the plot → returned, never credited; a 2× / 2.5×
	    hack from each of 6 displays straight to the nearest fence → returned «speed» within 1.5 s,
	    never credited, honest on that line → credited (A2-01: the budget starts at Start); a 2 s
	    server frame mid-carry at 13.6 → not returned (A2-05);
	  • StealFish nil at the exit (the thief's tank filled with stronger fish mid-carry) → returned
	    "full"; HoldEnded just before Triggered → still credited (Hold.Grace).

	Run: lune run tools/run_tests.luau stage4_theft
]]

local roblox = require("@lune/roblox")

local S = require("./stage4_server")

local Vector3 = roblox.Vector3

local tests = {}

local TANK = {
	{ Id = "Perch" },
	{ Id = "Perch" },
	{ Id = "Puffer", Age = 200 },
	{ Id = "Crucian" },
}
local TEXTS = S.STEAL_TEXTS
local FAIL = S.LIMITS.FailCooldown
-- Limits.BaseFails off: the fail-reason chains below fail twice on one base (stage 4 wave 3 UX-03
-- closes it; that rule's own tests are in stage4_fairness_grief).
local NO_BASE_CLOSE = {
	path = "ReplicatedStorage.Shared.Config.StealConfig",
	from = "\t\tBaseFails = 2,",
	to = "\t\tBaseFails = 0,",
}

local function pair(t: any, opts: { [string]: any }?): (any, any, any)
	local o = opts or {}
	local sim = S.boot(t, o.boot)
	local victim = S.player(t, sim, 101, { tank = o.victimTank or TANK, upgrades = o.victimUpgrades })
	local thief = S.player(t, sim, 102, { tank = o.thiefTank or { { Id = "Crucian" } } })
	return sim, victim, thief
end

local function cooldownLeft(sim: any, p: any): number
	local untilT = p:GetAttribute("StealCooldownUntil")
	if type(untilT) ~= "number" then
		return 0
	end
	return untilT - sim.workspace:GetServerTimeNow()
end

local function lastCancel(sim: any, p: any): any
	return S.last(sim, p, "Cancel")
end

-- The fish is back in its display, nobody holds it.
local function fishHome(t: any, sim: any, victim: any, slot: number, uid: string, what: string)
	local attrs = S.slotAttrs(sim, victim, slot)
	t.eq(attrs.State, "fish", `{what}: the display has a fish`)
	t.eq(attrs.FishUid, uid, `{what}: the same fish`)
	t.eq(attrs.StealPhase, nil, `{what}: StealPhase cleared`)
	t.eq(attrs.StealBy, nil, `{what}: StealBy cleared`)
	t.ok(S.rowOf(S.tankOf(sim, victim), uid), `{what}: still in the victim's data`)
end

--------------------------------------------------------------------------------
-- The happy path
--------------------------------------------------------------------------------

tests["hold → carry → exit → credit: tanks, slot attributes in order, Event stolen|<thief>, Origin, Age, stats, cooldown, after, escrow"] = function(
	t
)
	local sim, victim, thief = pair(t)
	local tank = S.service(sim, "TankService")
	local defence = S.service(sim, "DefenceService")
	local steal = S.service(sim, "StealService")
	local data = S.service(sim, "DataService")
	local signals = {}
	steal.TheftStarted:Connect(function(a, b, result)
		table.insert(signals, `start:{a.UserId}:{b.UserId}:{result}`)
	end)
	steal.TheftEnded:Connect(function(a, b, result)
		table.insert(signals, `end:{a.UserId}:{b.UserId}:{result}`)
	end)
	local slot = S.slot(sim, victim, 3)
	local order = {}
	for _, name in { "StealBy", "StealEnd", "StealPhase", "Event", "State" } do
		slot:GetAttributeChangedSignal(name):Connect(function()
			table.insert(order, name)
		end)
	end
	local prompt = S.prompt(sim, victim, 3)
	t.ok(prompt.Enabled, "the prompt of a display with a fish is enabled")
	t.eq(prompt.HoldDuration, S.BASE_HOLD)
	t.eq(prompt.MaxActivationDistance, S.StealConfig.Prompt.MaxDistance)
	t.eq(prompt.RequiresLineOfSight, false)
	t.ok(string.find(prompt.ObjectText, "+$", 1, true) ~= nil, `ObjectText «{prompt.ObjectText}»`)
	t.eq(S.prompt(sim, victim, 5).Enabled, false, "an empty display: no prompt")

	local hold = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active, `the hold began ({hold.cancelReason})`)
	t.eq(thief:GetAttribute("Stealing"), "hold")
	t.eq(slot:GetAttribute("StealPhase"), "hold")
	t.eq(slot:GetAttribute("StealBy"), thief.UserId)
	t.ok(type(slot:GetAttribute("StealEnd")) == "number", "StealEnd")
	t.eq(order, { "StealBy", "StealEnd", "StealPhase" }, "StealBy, StealEnd, then StealPhase last")
	t.eq(steal:IsStealing(thief), "hold")
	t.eq(steal:TheftOn(S.baseOf(sim, victim)).Thief, thief)
	local base = S.baseOf(sim, victim)
	t.eq(base:GetAttribute("Thief"), thief.UserId)
	-- a tap is not an attempt: the base's alarm and the victim's Alert wait for the tap window (V-UX-01)
	t.eq(base:GetAttribute("AlarmState"), nil, "no alarm in the tap window")
	t.eq(S.last(sim, victim, "Alert"), nil, "… and no Alert to the victim yet")
	local holdEvent = S.last(sim, thief, "Hold")
	t.ok(holdEvent, "Hold to the thief")
	t.eq(holdEvent.Slot, 3)
	t.eq(holdEvent.BaseIndex, base:GetAttribute("BaseIndex"))
	t.eq(holdEvent.Need, S.BASE_HOLD)
	t.eq(holdEvent.FishId, "Puffer")
	local window = math.max(S.LIMITS.QuietSavedUnder, S.HOLD_CFG.NoReply) + S.HOLD_CFG.NoReplySlack
	sim:Advance(window - 0.1)
	t.eq(S.last(sim, victim, "Alert"), nil, `{window - 0.1} s: still nothing to the victim`)
	sim:Advance(0.15)
	t.eq(base:GetAttribute("AlarmState"), "theft", `the tap window ({window} s) passed: the alarm`)
	local alert = S.last(sim, victim, "Alert")
	t.ok(alert and alert.Phase == "hold" and alert.Quiet == nil, "a loud Alert to the victim")
	t.eq(alert.Thief, thief.UserId)
	t.eq(alert.End, holdEvent.End, "its End is the hold's end")
	t.eq(#S.events(sim, victim, "Alert"), 1, "one")
	t.eq(signals, { `start:102:101:hold` })
	local income = victim:GetAttribute("Income")

	sim:Advance(prompt.HoldDuration - window - 0.05 + 0.1)
	t.eq(thief:GetAttribute("Stealing"), "carry", "the carry began")
	t.eq(slot:GetAttribute("StealPhase"), "carry")
	t.ok(thief.Character:FindFirstChild("StolenFish"), "StolenFish on the thief")
	t.eq(thief.Character.StolenFish:GetAttribute("Owner"), victim.UserId)
	t.eq(thief.Character.StolenFish:GetAttribute("FishId"), "Puffer")
	t.near(S.walk(thief), S.CARRY, 1e-6, "carry speed 13.6")
	t.ok(victim:GetAttribute("Income") < income, "the carried fish leaves the victim's income")
	local carryAlert = S.last(sim, victim, "Alert")
	t.eq(carryAlert.Phase, "carry", "the carry Alert")
	t.eq(carryAlert.Quiet, true, "… quiet (coalesced)")
	t.ok(S.last(sim, thief, "Carry"), "Carry to the thief")
	sim:ReleasePrompt(thief, prompt)
	sim:Advance(S.FRAME)
	t.eq(thief:GetAttribute("Stealing"), "carry", "the release after the hold changes nothing")

	-- The victim's key just wrote (a pause): the escrow is visible for a moment.
	local thiefIncome = thief:GetAttribute("Income")
	S.out(sim, thief, victim, "gate")
	t.eq(thief:GetAttribute("Stealing"), nil, "the theft ended")
	local done = S.last(sim, thief, "Done")
	t.ok(done, "Done to the thief")
	t.eq(done.Fish.Id, "Puffer")
	t.eq(done.Name, victim.DisplayName)
	t.eq(done.Result.Result, "stored")
	local lost = S.last(sim, victim, "Lost")
	t.ok(lost, "Lost to the victim")
	t.eq(lost.Kind, "after")
	t.eq(lost.Name, thief.DisplayName)
	t.eq(S.rowOf(S.tankOf(sim, victim), "f3"), nil, "gone from the victim")
	local row = S.rowByOrigin(S.tankOf(sim, thief), `{victim.UserId}:f3`)
	t.ok(row, "the thief has it with its Origin")
	t.ok(row.Age >= 200 - 1, `the Age kept ({row.Age})`)
	t.eq(row.Id, "Puffer")
	t.eq(slot:GetAttribute("State"), "empty")
	t.ok(string.find(slot:GetAttribute("Event"), `|stolen|{thief.UserId}`, 1, true) ~= nil, slot:GetAttribute("Event"))
	t.eq(order[#order], "Event", "Event written last")
	t.eq(slot:GetAttribute("StealPhase"), nil)
	t.eq(S.walk(thief), S.WALK, "speed restored")
	t.eq(thief.Character:FindFirstChild("StolenFish"), nil, "StolenFish gone")
	t.eq(defence:IsProtected(victim), "after", "the victim's after")
	t.near(cooldownLeft(sim, thief), S.LIMITS.ThiefCooldown, 1, "the thief waits 30 s")
	t.eq(data:Get(victim).Stats.Lost, 1)
	t.eq(data:Get(thief).Stats.Stolen, 1)
	t.eq(signals[#signals], `end:102:101:credited`)
	t.eq(base:GetAttribute("Thief"), nil, "Thief cleared")
	t.eq(base:GetAttribute("AlarmState"), "theft", "the lamp lingers …")
	sim:Advance(S.StealConfig.Alarm.Linger + 0.2)
	t.eq(base:GetAttribute("AlarmState"), nil, "… then goes out")
	-- The escrow: in force until the victim's record commits the removal.
	local thiefSlot = S.slot(sim, thief, row.Slot)
	local escrowed = tank:EscrowCount(thief) > 0
	if escrowed then
		t.eq(thiefSlot:GetAttribute("Escrow"), true, "the thief's slot shows Escrow")
		t.near(thief:GetAttribute("Income"), thiefIncome, 1e-6, "the escrowed fish earns nothing")
	end
	t.ok(
		sim:WaitFor(function()
			return tank:EscrowCount(thief) == 0
		end, S.GAP + 2, S.COARSE),
		"the escrow clears at the victim's commit"
	)
	t.eq(thiefSlot:GetAttribute("Escrow"), nil, "Escrow cleared")
	t.ok(thief:GetAttribute("Income") > thiefIncome, "now it earns")
	sim:AssertNoErrors({ warnings = true })
end

tests["Carry.Enabled = false: the fish moves at the end of the hold (no carry, no StolenFish)"] = function(t)
	local sim, victim, thief = pair(t, {
		boot = {
			patches = {
				{
					path = "ReplicatedStorage.Shared.Config.StealConfig",
					from = "Enabled = true, -- false:",
					to = "Enabled = false, -- false:",
				},
			},
		},
	})
	local hold, prompt = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active)
	sim:Advance(prompt.HoldDuration + 0.1)
	t.eq(thief:GetAttribute("Stealing"), nil, "no carry phase")
	t.ok(S.last(sim, thief, "Done"), "Done at the hold end")
	t.eq(#S.events(sim, thief, "Carry"), 0, "no Carry event")
	t.eq(thief.Character:FindFirstChild("StolenFish"), nil, "no StolenFish")
	t.ok(S.rowByOrigin(S.tankOf(sim, thief), `{victim.UserId}:f3`), "the thief has it")
	t.eq(S.rowOf(S.tankOf(sim, victim), "f3"), nil, "the victim has not")
	t.eq(S.walk(thief), S.WALK)
	sim:ReleasePrompt(thief, prompt)
	sim:Advance(0.5)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Cancel reasons in the hold
--------------------------------------------------------------------------------

tests["hold cancels: released (fail step 3 s), far (a 9-stud teleport, BE-13), died — the fish stays, Saved to the victim"] = function(
	t
)
	local sim, victim, thief = pair(t, { boot = { patches = { NO_BASE_CLOSE } } })
	-- released
	local hold, prompt = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active)
	sim:Advance(1.5)
	sim:ReleasePrompt(thief, prompt)
	sim:Advance(0.1)
	t.eq(lastCancel(sim, thief).Reason, "released")
	t.eq(lastCancel(sim, thief).Text, TEXTS.Cancel.released)
	t.eq(lastCancel(sim, thief).Phase, "hold")
	t.eq(thief:GetAttribute("Stealing"), nil)
	fishHome(t, sim, victim, 3, "f3", "released")
	local saved = S.last(sim, victim, "Saved")
	t.eq(saved.Reason, "released")
	t.eq(saved.Text, TEXTS.Result.Saved.failed)
	t.eq(saved.Quiet, nil, "a 1.5 s hold is not quiet")
	t.near(cooldownLeft(sim, thief), FAIL[1], 0.3, "the first failure: 3 s")
	sim:Advance(FAIL[1] + 0.2)

	-- far: a teleport 9 studs back ends the stock hold; the server classifies it «far»
	hold = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active, `second hold ({hold.cancelReason})`)
	sim:Advance(0.5)
	local root = thief.Character.HumanoidRootPart
	sim:Teleport(thief, root.Position - root.CFrame.LookVector * 9)
	sim:Advance(0.2)
	t.eq(lastCancel(sim, thief).Reason, "far", "classified far, not released")
	fishHome(t, sim, victim, 3, "f3", "far")
	t.near(cooldownLeft(sim, thief), FAIL[2], 0.4, "the second failure within 60 s: 10 s")
	sim:Advance(FAIL[2] + 0.2)

	-- died
	hold = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active, `third hold ({hold.cancelReason})`)
	sim:Advance(0.5)
	sim:KillCharacter(thief)
	sim:Advance(0.2)
	t.eq(lastCancel(sim, thief).Reason, "died")
	fishHome(t, sim, victim, 3, "f3", "died")
	t.near(cooldownLeft(sim, thief), FAIL[3], 0.4, "the third failure: 30 s")
	t.eq(S.service(sim, "StealService"):IsStealing(thief), nil)
	sim:AssertNoErrors({ warnings = true })
end

tests["hold and carry: the thief leaves → the fish stays / goes home; the victim leaves → «victim», his save keeps the fish"] = function(
	t
)
	local sim, victim, thief = pair(t)
	local steal = S.service(sim, "StealService")
	-- a thief leaves inside the tap window: the victim never heard of that hold — nothing (V-UX-01)
	local early = S.player(t, sim, 105, { tank = { { Id = "Crucian" } } })
	local hold = S.hold(t, sim, early, victim, 3)
	t.ok(hold.active)
	sim:Advance(0.8)
	sim:RemovePlayer(early)
	sim:Advance(0.2)
	fishHome(t, sim, victim, 3, "f3", "thief left in the tap window")
	t.eq(#S.events(sim, victim, "Alert"), 0, "no Alert to the victim: the hold never outlasted the tap window")
	t.eq(#S.events(sim, victim, "Saved"), 0, "… and no Saved")
	-- the thief leaves mid-hold (after the alert)
	hold = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active)
	sim:Advance(2)
	t.eq(#S.events(sim, victim, "Alert"), 1, "past the tap window: the victim's Alert")
	sim:RemovePlayer(thief)
	sim:Advance(0.2)
	fishHome(t, sim, victim, 3, "f3", "thief left in the hold")
	t.eq(S.last(sim, victim, "Saved").Reason, "left")
	t.eq(S.last(sim, victim, "Saved").Text, TEXTS.Result.Saved.left)
	t.eq(steal._debugSizes().Thefts, 0)
	-- a second thief leaves mid-carry
	local thief2 = S.player(t, sim, 103, { tank = { { Id = "Crucian" } } })
	S.toCarry(t, sim, thief2, victim, 3)
	sim:Advance(0.5)
	sim:RemovePlayer(thief2)
	sim:Advance(0.2)
	fishHome(t, sim, victim, 3, "f3", "thief left in the carry")
	t.eq(S.last(sim, victim, "Saved").Reason, "left")
	-- the victim leaves mid-carry: «victim» to the thief, nothing to the victim, his final save
	-- keeps the fish
	local thief3 = S.player(t, sim, 104, { tank = { { Id = "Crucian" } } })
	S.toCarry(t, sim, thief3, victim, 3)
	sim:Advance(0.5)
	local savedBefore = #S.events(sim, victim, "Saved")
	sim:RemovePlayer(victim)
	sim:Advance(0.2)
	t.eq(lastCancel(sim, thief3).Reason, "victim")
	t.eq(lastCancel(sim, thief3).Phase, "carry")
	t.eq(#S.events(sim, victim, "Saved"), savedBefore, "no Saved to a victim who left")
	t.eq(S.walk(thief3), S.WALK, "the thief at 16 again")
	t.eq(thief3.Character:FindFirstChild("StolenFish"), nil)
	t.eq(cooldownLeft(sim, thief3), 0, "not his fault: no wait")
	sim:Advance(S.GAP + 3, S.COARSE)
	local saved = S.peek(sim, 101)
	t.ok(S.rowOf(saved and saved.Tank, "f3"), "the victim's final save has the fish")
	sim:AssertNoErrors({ warnings = true })
end

tests["shield: in the hold → cancelled; in the carry → returned home, the thief at 16, no fail wait (DC-01)"] = function(
	t
)
	local sim, victim, thief = pair(t)
	local hold = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active)
	sim:Advance(1)
	sim:FireServer(victim, "ShieldActivate")
	sim:Advance(0.1)
	t.eq(lastCancel(sim, thief).Reason, "shield")
	t.eq(lastCancel(sim, thief).Text, TEXTS.Cancel.shield)
	fishHome(t, sim, victim, 3, "f3", "shield in the hold")
	t.eq(cooldownLeft(sim, thief), 0, "no fail wait")
	t.eq(S.last(sim, victim, "Saved").Text, TEXTS.Result.Saved.shield)
	sim:ReleasePrompt(thief, S.prompt(sim, victim, 3))
	-- the shield ends; a second victim's carry is returned by his shield
	local victim2 = S.player(t, sim, 105, { tank = TANK })
	S.toCarry(t, sim, thief, victim2, 3)
	sim:Advance(0.6)
	t.near(S.walk(thief), S.CARRY, 1e-6)
	sim:FireServer(victim2, "ShieldActivate")
	sim:Advance(0.1)
	t.eq(lastCancel(sim, thief).Reason, "shield")
	t.eq(lastCancel(sim, thief).Phase, "carry")
	fishHome(t, sim, victim2, 3, "f3", "shield in the carry")
	t.eq(S.walk(thief), S.WALK, "the thief at 16")
	t.eq(thief.Character:FindFirstChild("StolenFish"), nil, "the fish flew home")
	t.eq(cooldownLeft(sim, thief), 0, "no fail wait")
	t.ok(S.rowOf(S.tankOf(sim, victim2), "f3"), "still the victim's")
	t.eq(S.rowByOrigin(S.tankOf(sim, thief), `{victim2.UserId}:f3`), nil, "never the thief's")
	sim:AssertNoErrors({ warnings = true })
end

tests["tag: the owner within 6 studs → the fish home, the fail step + tagged 20 s on that base; another base after the fail step"] = function(
	t
)
	local sim, victim, thief = pair(t)
	local other = S.player(t, sim, 106, { tank = TANK })
	S.toCarry(t, sim, thief, victim, 3)
	sim:Advance(0.5)
	sim:Teleport(victim, S.beside(thief, 5))
	sim:Advance(0.2)
	t.eq(lastCancel(sim, thief).Reason, "tag")
	t.eq(lastCancel(sim, thief).BaseReason, "tagged", "the Cancel names the closed base: «tagged» …")
	t.near(
		lastCancel(sim, thief).BaseUntil,
		sim.workspace:GetServerTimeNow() + S.LIMITS.TagCooldown,
		0.5,
		"… until TagCooldown (BaseUntil: the client hides that base)"
	)
	t.eq(S.last(sim, victim, "Saved").Text, TEXTS.Result.Saved.tag)
	fishHome(t, sim, victim, 3, "f3", "tag")
	t.near(cooldownLeft(sim, thief), FAIL[1], 0.3, "the fail step")
	sim:Teleport(victim, S.baseOf(sim, victim).SpawnPad.Position + Vector3.new(0, 3, 0))
	sim:Advance(FAIL[1] + 0.2)
	-- that base: tagged for 20 s
	local hold = S.hold(t, sim, thief, victim, 3)
	sim:Advance(0.1)
	local denied = S.last(sim, thief, "Denied")
	t.eq(denied and denied.Reason, "tagged", "the tagged base refuses")
	t.eq(denied.Slot, 3)
	t.ok(type(denied.Until) == "number" and denied.Until > sim.workspace:GetServerTimeNow(), "Denied carries Until")
	if hold.active then
		sim:ReleasePrompt(thief, S.prompt(sim, victim, 3))
	end
	-- another base: allowed after the fail step
	hold = S.hold(t, sim, thief, other, 3)
	t.ok(hold.active)
	sim:Advance(0.1)
	t.eq(thief:GetAttribute("Stealing"), "hold", "another base is allowed")
	sim:ReleasePrompt(thief, S.prompt(sim, other, 3))
	sim:Advance(0.2)
	sim:AssertNoErrors({ warnings = true })
end

tests["deadline (the server HoldDuration raised to 10 mid-hold), early (Triggered at 1 s → the next fail step), carry timeout"] = function(
	t
)
	local sim, victim, thief = pair(t, { boot = { patches = { NO_BASE_CLOSE } } })
	-- deadline: the sim's hold reads the prompt's HoldDuration (now 10), the server captured 3
	local hold, prompt = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active)
	prompt.HoldDuration = 10
	sim:Advance(S.BASE_HOLD + S.HOLD_CFG.Deadline - 0.2)
	t.eq(thief:GetAttribute("Stealing"), "hold", "still holding just before need + Deadline")
	sim:Advance(0.4)
	t.eq(lastCancel(sim, thief).Reason, "deadline")
	t.eq(prompt.HoldDuration, S.BASE_HOLD, "the held prompt got the base's HoldDuration back at the end")
	sim:ReleasePrompt(thief, prompt)
	sim:Advance(FAIL[1] + 0.3)

	-- early: a Triggered 1 s after HoldBegan (under Need × LateShare: fireproximityprompt, or a link
	-- far too slow) → the next ordinary fail step (the 2nd here: 10 s), not the last one (UX-04)
	hold = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active)
	sim:Advance(1)
	t.ok(1 < S.BASE_HOLD * S.HOLD_CFG.LateShare, "1 s is under Need × LateShare")
	sim:FirePromptEvent(thief, prompt, "Triggered")
	sim:Advance(0.1)
	t.eq(lastCancel(sim, thief).Reason, "early")
	t.near(cooldownLeft(sim, thief), FAIL[2], 0.3, "early → the 2nd failure's step, 10 s (not the last)")
	fishHome(t, sim, victim, 3, "f3", "early")
	sim:Advance(S.BASE_HOLD) -- the stock hold completes on the client: no record, nothing happens
	t.eq(thief:GetAttribute("Stealing"), nil)
	sim:ReleasePrompt(thief, prompt)
	sim:Advance(FAIL[2] + 0.3)

	-- the carry timeout: he stands in the court
	S.toCarry(t, sim, thief, victim, 3)
	sim:Advance(S.CARRY_CFG.Timeout - 0.5, S.COARSE)
	t.eq(thief:GetAttribute("Stealing"), "carry", "still carrying before the timeout")
	sim:Advance(1, S.COARSE)
	t.eq(lastCancel(sim, thief).Reason, "timeout")
	fishHome(t, sim, victim, 3, "f3", "timeout")
	t.eq(S.walk(thief), S.WALK)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The speed budget (Kit.drive)
--------------------------------------------------------------------------------

tests["speed: 16 st/s under the dog → returned within 3 s; honest under the dog with a 1.2 s freeze → not returned"] = function(
	t
)
	local sim, victim, thief = pair(t, { victimUpgrades = { Dog = true } })
	local base = S.baseOf(sim, victim)
	S.toCarry(t, sim, thief, victim, 3)
	t.ok(thief:GetAttribute("Slowed"), "the dog reached him during the hold")
	t.near(S.walk(thief), S.CARRY * S.DOG.Slow, 1e-6, "6.8 under the dog")
	-- a client that keeps WalkSpeed 16: drive inside the court (no exit to credit)
	local started = sim:Time()
	S.drive(sim, thief, S.basePoint(base, 50, 150, S.HRP_HEIGHT), S.WALK, {
		stop = function()
			return thief:GetAttribute("Stealing") == nil
		end,
		timeout = 6,
	})
	t.eq(lastCancel(sim, thief) and lastCancel(sim, thief).Reason, "speed", "returned «speed»")
	t.ok(sim:Time() - started <= 3, `within 3 s ({sim:Time() - started})`)
	fishHome(t, sim, victim, 3, "f3", "speed")
	t.eq(S.walk(thief), S.WALK, "16 after the end")
	t.eq(thief:GetAttribute("Slowed"), nil, "Slowed cleared")
	sim:Advance(FAIL[1] + 0.5)

	-- honest at 6.8 with a 1.2 s freeze and the catch-up: not returned
	S.toCarry(t, sim, thief, victim, 3)
	S.out(sim, thief, victim, "gate", S.CARRY * S.DOG.Slow, { stall = { at = 1, seconds = 1.2 } })
	local done = S.last(sim, thief, "Done")
	t.ok(done, `credited (last cancel: {lastCancel(sim, thief) and lastCancel(sim, thief).Reason})`)
	t.eq(S.walk(thief), S.WALK, "16 after the credit")
	sim:Advance(0.1)
	t.eq(S.walk(thief), S.WALK, "… at +0.1 s")
	t.eq(thief:GetAttribute("Slowed"), nil, "Slowed nil")
	sim:Advance(5, S.COARSE)
	t.eq(S.walk(thief), S.WALK, "… and at +5 s (the dog bit at the exit: BE-10)")
	sim:AssertNoErrors({ warnings = true })
end

tests["speed: a 30-stud hop → returned; a teleport straight out of the plot → returned, never credited"] = function(
	t
)
	local sim, victim, thief = pair(t)
	local base = S.baseOf(sim, victim)
	S.toCarry(t, sim, thief, victim, 3)
	sim:Advance(0.3)
	S.drive(sim, thief, S.basePoint(base, 0, 150, S.HRP_HEIGHT), S.CARRY, {
		hop = 30,
		stop = function()
			return thief:GetAttribute("Stealing") == nil
		end,
		timeout = 2,
	})
	t.eq(lastCancel(sim, thief).Reason, "speed", "a hop over Teleport")
	fishHome(t, sim, victim, 3, "f3", "hop")
	sim:Advance(FAIL[1] + 0.5)

	S.toCarry(t, sim, thief, victim, 3)
	sim:Advance(0.3)
	sim:Teleport(thief, S.exitPoint(base, "gate"))
	sim:Advance(0.5)
	t.eq(lastCancel(sim, thief).Reason, "speed", "a teleport out is returned")
	t.eq(#S.events(sim, thief, "Done"), 0, "never credited")
	fishHome(t, sim, victim, 3, "f3", "teleport out")
	sim:AssertNoErrors({ warnings = true })
end

-- The nearest fence from where the thief stands, a few studs past the ExitMargin line (base studs →
-- world, at the HRP height).
local function nearestOut(sim: any, thief: any, victim: any): (any, number)
	local base = S.baseOf(sim, victim)
	local Rules = S.shared(sim, "StealRules")
	local here = Rules.LocalOf(base:GetPivot(), thief.Character.HumanoidRootPart.Position)
	local flatHere = Vector3.new(here.X, 0, here.Z)
	local exit = Rules.NearestExit(here)
	local away = exit - flatHere
	local beyond = exit + away.Unit * 3
	return S.basePoint(base, beyond.X, beyond.Z, S.HRP_HEIGHT), away.Magnitude
end

tests["speed (A2-01): a 2× / 2.5× hack from every display straight to the nearest fence → returned «speed», never credited; honest on that line → credited"] = function(
	t
)
	local six = table.clone(TANK)
	table.insert(six, { Id = "Perch" })
	table.insert(six, { Id = "Crucian" })
	local sim, victim, thief = pair(t, {
		victimTank = six,
		boot = {
			patches = {
				{
					path = "ReplicatedStorage.Shared.Config.StealConfig",
					from = "FailCooldown = { 3, 10, 30 },",
					to = "FailCooldown = { 0.2, 0.2, 0.2 },",
				},
				NO_BASE_CLOSE,
			},
		},
	})
	local shortest = math.huge
	for slot = 1, 6 do
		for _, factor in { 2, 2.5 } do
			S.toCarry(t, sim, thief, victim, slot)
			local target, distance = nearestOut(sim, thief, victim)
			shortest = math.min(shortest, distance)
			local started = sim:Time()
			S.drive(sim, thief, target, factor * S.CARRY, {
				stop = function()
					return thief:GetAttribute("Stealing") == nil
				end,
				timeout = 6,
			})
			local took = sim:Time() - started
			local cancel = lastCancel(sim, thief)
			t.eq(cancel and cancel.Reason, "speed", `slot {slot}, {factor}×, {distance} studs: returned «speed»`)
			t.ok(took <= 1.5, `… within 1.5 s ({took})`)
			t.eq(#S.events(sim, thief, "Done"), 0, "… never credited")
			fishHome(t, sim, victim, slot, `f{slot}`, `{factor}× from slot {slot}`)
			sim:Advance(0.5)
		end
	end
	t.ok(shortest < 50, `the nearest fence is close ({shortest} studs): the old full budget let ×2 through`)
	-- honest on the nearest line: credited
	S.toCarry(t, sim, thief, victim, 3)
	local target = nearestOut(sim, thief, victim)
	S.drive(sim, thief, target, S.CARRY, {
		stop = function()
			return thief:GetAttribute("Stealing") == nil
		end,
		timeout = S.CARRY_CFG.Timeout,
	})
	sim:Advance(0.3)
	t.ok(
		S.last(sim, thief, "Done"),
		`honest 13.6 → credited (last cancel: {lastCancel(sim, thief) and lastCancel(sim, thief).Reason})`
	)
	sim:AssertNoErrors({ warnings = true })
end

-- A2-05: a server hitch while an honest thief walks — one long server frame is not a teleport.
tests["speed (A2-05): a 2 s server frame mid-carry at 13.6 → not returned, then credited"] = function(t)
	local sim, victim, thief = pair(t)
	local base = S.baseOf(sim, victim)
	S.toCarry(t, sim, thief, victim, 3)
	S.drive(sim, thief, S.exitPoint(base, "gate"), S.CARRY, { timeout = 0.5 })
	local root = thief.Character.HumanoidRootPart
	local ahead = S.exitPoint(base, "gate") - root.Position
	local step = Vector3.new(ahead.X, 0, ahead.Z).Unit * (S.CARRY * 2)
	t.ok(step.Magnitude > S.CARRY_CFG.Speed.Teleport, "the hitch's displacement is over Teleport")
	sim:Teleport(thief, root.Position + step)
	sim:Advance(2, 2) -- one 2 s server frame
	t.eq(
		thief:GetAttribute("Stealing"),
		"carry",
		`still carrying (cancel: {lastCancel(sim, thief) and lastCancel(sim, thief).Reason})`
	)
	S.out(sim, thief, victim, "gate")
	t.ok(S.last(sim, thief, "Done"), "credited")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The exit
--------------------------------------------------------------------------------

tests["StealFish nil at the exit (the thief's tank full of stronger fish) → returned «full»; HoldEnded before Triggered → credited"] = function(
	t
)
	local sim, victim, thief = pair(t)
	local tank = S.service(sim, "TankService")
	-- mid-carry the thief's tank fills with fish stronger than the loot
	S.toCarry(t, sim, thief, victim, 3)
	local FishingRules = S.shared(sim, "FishingRules")
	for _ = 1, 6 do
		local v, inc = FishingRules.Price("SharkPup", 12, nil)
		sim:Run(function()
			return tank:AddFish(
				thief,
				{ Id = "SharkPup", Rarity = "Legendary", Kg = 12, Value = v, Income = inc },
				"catch"
			)
		end)
	end
	S.out(sim, thief, victim, "gate")
	t.eq(lastCancel(sim, thief).Reason, "full")
	t.eq(lastCancel(sim, thief).Text, TEXTS.Cancel.full)
	fishHome(t, sim, victim, 3, "f3", "full")
	t.eq(cooldownLeft(sim, thief), 0, "not his fault: no wait")

	-- HoldEnded just before Triggered: the Grace window waits for the Triggered
	local sim2, victim2, thief2 = pair(t)
	local prompt = S.prompt(sim2, victim2, 3)
	S.standAt(sim2, thief2, prompt)
	sim2:FirePromptEvent(thief2, prompt, "HoldBegan")
	sim2:Advance(S.BASE_HOLD + 0.05)
	sim2:FirePromptEvent(thief2, prompt, "HoldEnded")
	sim2:FirePromptEvent(thief2, prompt, "Triggered")
	sim2:Advance(0.1)
	t.eq(thief2:GetAttribute("Stealing"), "carry", "the Triggered after the HoldEnded still counts")
	S.out(sim2, thief2, victim2, "gate")
	t.ok(S.last(sim2, thief2, "Done"), "credited")
	sim:AssertNoErrors({ warnings = true })
	sim2:AssertNoErrors({ warnings = true })
end

tests["a late HoldBegan (UX-04): a Triggered at 1.6 s of 3 is taken — the carry at T0 + 3, not before; a walk-away in that wait is «far»"] = function(
	t
)
	local sim, victim, thief = pair(t)
	local prompt = S.prompt(sim, victim, 3)
	S.standAt(sim, thief, prompt)
	-- the honest phone held for 3 s, but its HoldBegan reached the server 1.4 s late
	local began = sim:Time()
	sim:FirePromptEvent(thief, prompt, "HoldBegan")
	sim:Advance(1.6)
	t.ok(1.6 >= S.BASE_HOLD * S.HOLD_CFG.LateShare, "1.6 s ≥ Need × LateShare")
	sim:FirePromptEvent(thief, prompt, "Triggered")
	sim:FirePromptEvent(thief, prompt, "HoldEnded") -- (the finger lifts after the ring: ignored now)
	sim:Advance(0.1)
	t.eq(#S.events(sim, thief, "Cancel"), 0, "not «early» any more")
	t.eq(thief:GetAttribute("Stealing"), "hold", "the server still holds for him")
	t.eq(cooldownLeft(sim, thief), 0, "no wait")
	local carried = sim:WaitFor(function()
		return thief:GetAttribute("Stealing") == "carry"
	end, S.BASE_HOLD, S.FRAME)
	t.ok(carried, "the carry")
	t.ok(sim:Time() - began >= S.BASE_HOLD - S.FRAME, `the carry at T0 + Need ({sim:Time() - began} s), never earlier`)
	S.out(sim, thief, victim, "gate")
	t.ok(S.last(sim, thief, "Done"), "credited once")
	t.eq(#S.events(sim, thief, "Done"), 1)

	-- the same late Triggered, then he walks off before T0 + Need: the watcher's radius → «far»
	local sim2, victim2, thief2 = pair(t)
	local prompt2 = S.prompt(sim2, victim2, 3)
	S.standAt(sim2, thief2, prompt2)
	sim2:FirePromptEvent(thief2, prompt2, "HoldBegan")
	sim2:Advance(1.6)
	sim2:FirePromptEvent(thief2, prompt2, "Triggered")
	sim2:Advance(0.2)
	local root = thief2.Character.HumanoidRootPart
	sim2:Teleport(thief2, root.Position - root.CFrame.LookVector * 12)
	sim2:Advance(0.3)
	t.eq(lastCancel(sim2, thief2) and lastCancel(sim2, thief2).Reason, "far", "walked off in the wait: «far»")
	t.eq(thief2:GetAttribute("Stealing"), nil)
	fishHome(t, sim2, victim2, 3, "f3", "far in the late wait")
	sim2:Advance(S.BASE_HOLD)
	t.eq(#S.events(sim2, thief2, "Carry"), 0, "no carry after all")
	sim:AssertNoErrors({ warnings = true })
	sim2:AssertNoErrors({ warnings = true })
end

return tests
