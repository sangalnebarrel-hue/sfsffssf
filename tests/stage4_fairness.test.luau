--[[
	Stage 4 wave 1 A — the lock, the client prompt filter's server half, exploits and the fairness
	limits (docs/stage4_design.md §2.3, §4.3, §5.1, §7.2), in RbxSim against the built Place1.rbxl
	with headless players (tests/stage4_server.luau) and one light client:
	  • lock level 1 (bought on the server): the 12 prompts at HoldDuration 4; a 3 s hold does not
	    trigger, 4 s does; a purchase mid-hold leaves the held prompt's HoldDuration alone and the
	    theft credits (BE-18), the prompt gets 4 at the end;
	  • client hiding (S1, BE-14): the owner's client hides his prompts with a local
	    MaxActivationDistance = 0; the server toggles Enabled 20 times (catches and removals) and runs
	    a theft and a shield on the base — in every frame the local value is still 0 and the owner
	    cannot hold his own prompt ("out of range");
	  • exploits: a Triggered with no hold → nothing; 100 HoldBegans on one prompt in a frame → one
	    theft, no answers; a HoldBegan fired after the player left → no bucket entry (BE-20);
	  • griefing (DC-10, BE-19): release loops → waits 3 / 10 / 30 s, at most one loud alert per 30 s
	    (≤ 3 in 60 s), holds under 1 s → Saved Quiet;
	  • the victim cap (DC-06): four thieves for 10 virtual minutes → exactly 2 losses, then «rest»
	    until the older loss is 600 s old; a steal by the victim clears his rest and his losses.

	Run: lune run tools/run_tests.luau stage4_fairness
]]

local S = require("./stage4_server")

local tests = {}

local TANK = {
	{ Id = "Perch" },
	{ Id = "Perch" },
	{ Id = "Puffer" },
	{ Id = "Crucian" },
}
local SIX = {
	{ Id = "Perch" },
	{ Id = "Perch" },
	{ Id = "Puffer" },
	{ Id = "Crucian" },
	{ Id = "Perch" },
	{ Id = "Crucian" },
}

local function loud(sim: any, victim: any): number
	local n = 0
	for _, e in S.events(sim, victim, "Alert") do
		if e.data.Quiet == nil then
			n += 1
		end
	end
	return n
end

local function cooldownLeft(sim: any, p: any): number
	local untilT = p:GetAttribute("StealCooldownUntil")
	return if type(untilT) == "number" then untilT - sim.workspace:GetServerTimeNow() else 0
end

--------------------------------------------------------------------------------
-- The lock
--------------------------------------------------------------------------------

tests["lock level 1: 12 prompts at 4 s, a 3 s hold does not trigger, 4 s does; a purchase mid-hold leaves the held prompt (BE-18)"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK, money = 1500 })
	local victim2 = S.player(t, sim, 103, { tank = TANK, money = 1500 })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	sim:FireServer(victim, "DefenceBuy", "Lock")
	sim:Advance(0.1)
	local bought = S.defenceEvents(sim, victim, "Bought")
	t.eq(#bought, 1, "bought")
	t.eq(bought[1].data.Level, 1)
	for i = 1, 12 do
		t.eq(S.prompt(sim, victim, i).HoldDuration, S.LOCK.Levels[1].Hold, `Slot_{i}: HoldDuration 4`)
	end
	t.eq(S.baseOf(sim, victim):GetAttribute("HoldTime"), S.LOCK.Levels[1].Hold)
	-- a 3 s hold: not enough
	local hold, prompt = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active)
	sim:Advance(3.05)
	t.eq(thief:GetAttribute("Stealing"), "hold", "still holding at 3 s")
	sim:ReleasePrompt(thief, prompt)
	sim:Advance(0.1)
	t.eq(S.last(sim, thief, "Cancel").Reason, "released")
	sim:Advance(S.LIMITS.FailCooldown[1] + 0.3)
	-- 4 s: the carry
	hold = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active)
	t.eq(S.last(sim, thief, "Hold").Need, S.LOCK.Levels[1].Hold, "Need 4")
	sim:Advance(S.LOCK.Levels[1].Hold + 0.1)
	t.eq(thief:GetAttribute("Stealing"), "carry", "4 s works")
	sim:ReleasePrompt(thief, prompt)
	sim:FireServer(victim, "ShieldActivate")
	sim:Advance(0.2)
	t.eq(S.last(sim, thief, "Cancel").Reason, "shield")

	-- a purchase mid-hold: the held prompt keeps its 3 s and the theft credits
	local p2 = S.prompt(sim, victim2, 3)
	hold = S.hold(t, sim, thief, victim2, 3)
	t.ok(hold.active)
	sim:Advance(1)
	sim:FireServer(victim2, "DefenceBuy", "Lock")
	sim:Advance(S.FRAME)
	t.eq(p2.HoldDuration, S.BASE_HOLD, "the held prompt is not rewritten")
	t.eq(S.prompt(sim, victim2, 1).HoldDuration, S.LOCK.Levels[1].Hold, "the others are")
	sim:Advance(S.BASE_HOLD - 1 + 0.1)
	t.eq(thief:GetAttribute("Stealing"), "carry", "the hold captured 3 s")
	sim:ReleasePrompt(thief, p2)
	S.out(sim, thief, victim2, "gate")
	t.ok(S.last(sim, thief, "Done"), "credited")
	t.eq(p2.HoldDuration, S.LOCK.Levels[1].Hold, "the prompt gets the lock's time at the end")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The client filter's server half (S1 / S2)
--------------------------------------------------------------------------------

tests["client hiding (BE-14): a local MaxActivationDistance = 0 survives 20 server Enabled toggles, a theft and a shield"] = function(
	t
)
	local sim = S.boot(t)
	local owner = S.player(t, sim, 101, { tank = TANK, client = true, device = "phone" })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local tank = S.service(sim, "TankService")
	-- the owner's client hides his own prompts (TheftController's local filter)
	local prompts = {}
	for i = 1, 12 do
		prompts[i] = S.prompt(sim, owner, i)
	end
	sim:Run(function()
		for _, prompt in prompts do
			prompt.MaxActivationDistance = 0
		end
	end, owner)
	local function checkHidden(what: string)
		for i, prompt in prompts do
			local seen = sim:Run(function()
				return prompt.MaxActivationDistance
			end, owner)
			t.eq(seen, 0, `{what}: Slot_{i} still hidden on the owner's client`)
		end
		t.eq(prompts[5].MaxActivationDistance, S.StealConfig.Prompt.MaxDistance, `{what}: the server's own value`)
	end
	local toggles = 0
	prompts[5].Changed:Connect(function(name)
		if name == "Enabled" then
			toggles += 1
		end
	end)
	for k = 1, 10 do
		local added = S.addFish(sim, owner, "Perch", nil, "stolen")
		sim:Advance(S.FRAME * k)
		checkHidden(`catch {k}`)
		sim:Run(function()
			tank:RemoveFish(owner, added.Uid, "test")
		end)
		sim:Advance(S.FRAME * (11 - k))
		checkHidden(`removal {k}`)
	end
	t.ok(toggles >= 20, `the server toggled Enabled {toggles} times`)
	-- the owner cannot hold his own prompt
	S.standAt(sim, owner, prompts[3])
	local ok, reason = sim:CanUsePrompt(owner, prompts[3])
	t.eq(ok, false, "the owner cannot hold his own prompt")
	t.ok(string.find(tostring(reason), "out of range", 1, true) ~= nil, tostring(reason))
	-- a theft and a shield on the base change nothing either
	sim:Teleport(owner, S.baseOf(sim, owner).SpawnPad.Position + S.Vector3up(3))
	S.toCarry(t, sim, thief, owner, 3)
	checkHidden("carry")
	sim:FireServer(owner, "ShieldActivate")
	sim:Advance(0.2)
	t.eq(S.last(sim, thief, "Cancel").Reason, "shield")
	checkHidden("shield")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Exploits
--------------------------------------------------------------------------------

tests["exploits: Triggered with no hold → nothing; 100 HoldBegans in a frame → one theft; a HoldBegan after leaving → no bucket (BE-20)"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local steal = S.service(sim, "StealService")
	local prompt = S.prompt(sim, victim, 3)
	S.standAt(sim, thief, prompt)
	sim:FirePromptEvent(thief, prompt, "Triggered")
	sim:Advance(0.1)
	t.eq(thief:GetAttribute("Stealing"), nil, "a Triggered with no hold does nothing")
	t.eq(#S.events(sim, thief), 0, "… and gets no answer")
	t.eq(S.rowOf(S.tankOf(sim, victim), "f3") ~= nil, true)
	for _ = 1, 100 do
		sim:FirePromptEvent(thief, prompt, "HoldBegan")
	end
	sim:Advance(S.FRAME)
	t.eq(steal._debugSizes().Thefts, 1, "one theft")
	t.eq(#S.events(sim, thief, "Hold"), 1, "one Hold")
	t.eq(#S.events(sim, thief, "Denied"), 0, "the repeats get no answer (BE-17)")
	sim:FirePromptEvent(thief, prompt, "HoldEnded")
	sim:Advance(0.1)
	t.eq(S.last(sim, thief, "Cancel").Reason, "released")
	-- a HoldBegan that arrives after the player left
	sim:RemovePlayer(thief)
	sim:Advance(0.1)
	sim:FirePromptEvent(thief, S.prompt(sim, victim, 2), "HoldBegan")
	sim:Advance(0.1)
	t.eq(steal._debugSizes().Buckets, 0, "no bucket entry for a player who left")
	t.eq(steal._debugSizes().Thefts, 0)
	t.eq(steal._debugSizes().Denied, 0)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Griefing
--------------------------------------------------------------------------------

tests["griefing (DC-10, BE-19): release loops → waits 3 / 10 / 30 s, ≤ one loud alert per 30 s (≤ 3 in 60 s), short holds Quiet"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local start = sim:Time()
	local waits = {}
	local attempts = 0
	while sim:Time() - start < 60 do
		local left = cooldownLeft(sim, thief)
		if left > 0 then
			sim:Advance(left + 0.1, 0.25)
			continue
		end
		local hold, prompt = S.hold(t, sim, thief, victim, 3)
		t.ok(hold.active, `attempt {attempts + 1}`)
		attempts += 1
		sim:Advance(0.5) -- a short hold: under QuietSavedUnder
		sim:ReleasePrompt(thief, prompt)
		sim:Advance(0.1)
		t.eq(S.last(sim, thief, "Cancel").Reason, "released")
		t.eq(S.last(sim, victim, "Saved").Quiet, true, "a hold under 1 s ends quietly for the victim")
		table.insert(waits, math.floor(cooldownLeft(sim, thief) + 0.5))
	end
	t.eq(waits[1], S.LIMITS.FailCooldown[1], "1st failure: 3 s")
	t.eq(waits[2], S.LIMITS.FailCooldown[2], "2nd: 10 s")
	t.eq(waits[3], S.LIMITS.FailCooldown[3], "3rd: 30 s")
	local n = loud(sim, victim)
	t.ok(n >= 1 and n <= 3, `loud alerts in 60 s: {n} (attempts {attempts})`)
	-- loud ones at least AlertCoalesce apart
	local last = -math.huge
	for _, e in S.events(sim, victim, "Alert") do
		if e.data.Quiet == nil then
			t.ok(e.time - last >= S.LIMITS.AlertCoalesce - 0.1, `loud alerts {e.time - last} s apart`)
			last = e.time
		end
	end
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The victim cap
--------------------------------------------------------------------------------

tests["victim cap (DC-06): four thieves for 10 minutes → exactly 2 losses, then rest until the older loss is 600 s old"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = SIX })
	local thieves = {}
	for i = 1, 4 do
		thieves[i] = S.player(t, sim, 110 + i, { tank = { { Id = "Crucian" } } })
	end
	local defence = S.service(sim, "DefenceService")
	local losses, lossTimes = 0, {}
	local function try(thief: any, slot: number): string
		local d = S.denied(t, sim, thief, victim, slot, { holdOpts = {} })
		if d then
			return d.Reason
		end
		return "started?"
	end
	local function steal(thief: any, slot: number)
		S.toCarry(t, sim, thief, victim, slot)
		S.out(sim, thief, victim, "gate")
		t.ok(S.last(sim, thief, "Done"), `{thief.Name} credited`)
		losses += 1
		table.insert(lossTimes, sim.workspace:GetServerTimeNow())
	end
	local first = sim:Time()
	steal(thieves[1], 1)
	t.eq(defence:IsProtected(victim), "after")
	t.eq(try(thieves[2], 2), "after", "the after immunity")
	sim:Advance(S.LIMITS.VictimImmunity + 0.5, 1)
	steal(thieves[2], 2)
	local kind, untilT = defence:IsProtected(victim)
	t.eq(kind, "rest", "the 2nd loss → rest")
	t.near(untilT, lossTimes[1] + S.LIMITS.VictimWindow, 0.5, "rest until the older loss + 600")
	-- the others keep trying for the rest of the 10 minutes: refused every time
	local refusals = 0
	while sim:Time() - first < S.LIMITS.VictimWindow - 15 do
		sim:Advance(60, 1)
		for i = 3, 4 do
			local reason = try(thieves[i], 3 + i - 3)
			t.eq(reason, "rest", `{thieves[i].Name} at {math.floor(sim:Time() - first)} s`)
			refusals += 1
		end
	end
	t.eq(losses, 2, "exactly 2 losses in 10 minutes")
	t.ok(refusals >= 8, `refused {refusals} times`)
	-- the rest ends when the older loss is 600 s old
	sim:Advance(lossTimes[1] + S.LIMITS.VictimWindow - sim.workspace:GetServerTimeNow() + 0.5, 1)
	t.eq(defence:IsProtected(victim), nil, "the rest is over")
	local hold = S.hold(t, sim, thieves[3], victim, 3)
	t.ok(hold.active)
	t.eq(thieves[3]:GetAttribute("Stealing"), "hold", "a third theft is possible again")
	sim:ReleasePrompt(thieves[3], S.prompt(sim, victim, 3))
	sim:Advance(0.2)
	sim:AssertNoErrors({ warnings = true })
end

tests["a steal by the victim clears his rest and his losses (D6)"] = function(t)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = SIX })
	local thiefA = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local thiefB = S.player(t, sim, 103, { tank = { { Id = "Crucian" } } })
	local other = S.player(t, sim, 104, { tank = TANK })
	local defence = S.service(sim, "DefenceService")
	S.toCarry(t, sim, thiefA, victim, 1)
	S.out(sim, thiefA, victim, "gate")
	sim:Advance(S.LIMITS.VictimImmunity + 0.5, 1)
	S.toCarry(t, sim, thiefB, victim, 2)
	S.out(sim, thiefB, victim, "gate")
	t.eq(defence:IsProtected(victim), "rest")
	t.eq(defence._debugSizes().Losses, 1, "his losses are kept")
	-- he steals himself: his protection and his losses are gone
	local hold = S.hold(t, sim, victim, other, 3)
	t.ok(hold.active)
	t.eq(victim:GetAttribute("Stealing"), "hold")
	t.eq(defence:IsProtected(victim), nil, "the rest ended")
	t.eq(defence._debugSizes().Losses, 0, "his losses forgotten")
	local notes = sim:ClientEventsFor(victim, "Notify")
	t.eq(
		notes[#notes].args[1],
		S.STEAL_TEXTS.Hint.Ended,
		"«Кража погасила твою защиту»"
	)
	sim:ReleasePrompt(victim, S.prompt(sim, other, 3))
	sim:Advance(0.2)
	sim:AssertNoErrors({ warnings = true })
end

return tests
