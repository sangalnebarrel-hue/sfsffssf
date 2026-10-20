--[[
	Stage 4 wave 1 A — how a theft ends and what it leaves behind (docs/stage4_design.md §4.2 End,
	§4.6 home guard, §4.7 speed, §4.11 unmount, §3.4 #5, §7.2), in RbxSim against the built
	Place1.rbxl with headless players (tests/stage4_server.luau):
	  • speed: carry 13.6, the dog 6.8, 16 after every end, after a death (the new character) and
	    on leave (no Lib/Speed record left); a Dog key expiring mid-carry → 13.6 within SlowLinger +
	    0.1 (Speed owns expiry, BE-10); MinFactor;
	  • the home guard: carrying → «Сначала унеси рыбу за ограду!», no teleport, no cooldown spent;
	    the owner during a live theft on his base → lands on his spawn facing +Z (the court);
	  • unmount (BE-5): the victim leaves mid-carry → no StealBy / StealEnd / StealPhase / Escrow /
	    FreshUntil on any of the 12 slots of the freed base, no Thief / AlarmState; a new owner
	    mounts → a clean base;
	  • leaks: connections back to baseline after both leave; every _debugSizes zero after
	    Advance(VictimWindow) with no further writes (pruned inside _debugSizes, BE-26); the
	    watcher ends by itself (no loop while idle);
	  • robust end (A2-02): an error thrown after StealFish (a patched GiveAfterTheft) still ends
	    the theft — Stealing nil, 16, no record, no StolenFish, the watcher stops, one warning;
	  • rejoin (A2-03): the wait survives a rejoin and the new Player gets StealCooldownUntil back
	    (the client filter matches the server's «cooldown»); none once the wait is over;
	  • quiet (A2-04): a tag or the shield inside the first second → Saved loud (though no Alert
	    reached the owner yet); the thief's own release inside it → nothing to the owner (V-UX-01);
	  • BindToClose during the hold and the carry → the fish home, once (the victim's close save
	    has it, the thief's has none).

	Run: lune run tools/run_tests.luau stage4_theft_end
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

local function pair(t: any, opts: { [string]: any }?): (any, any, any)
	local o = opts or {}
	local sim = S.boot(t, o.boot)
	local victim = S.player(t, sim, 101, { tank = o.victimTank or TANK, upgrades = o.victimUpgrades })
	local thief = S.player(t, sim, 102, { tank = o.thiefTank or { { Id = "Crucian" } } })
	return sim, victim, thief
end

local function speedLib(sim: any): any
	return sim:Require(sim:Find("ServerScriptService.Lib.Speed"))
end

local function lastNotify(sim: any, p: any): string?
	local events = sim:ClientEventsFor(p, "Notify")
	local e = events[#events]
	return e and e.args[1]
end

--------------------------------------------------------------------------------
-- Speed
--------------------------------------------------------------------------------

tests["speed: carry 13.6, dog 6.8, 16 after the end, after a death and on leave; a Dog key expiring → 13.6; MinFactor"] = function(
	t
)
	local sim, victim, thief = pair(t, { victimUpgrades = { Dog = true } })
	local Speed = speedLib(sim)
	S.toCarry(t, sim, thief, victim, 3)
	t.near(S.walk(thief), S.CARRY * S.DOG.Slow, 1e-6, "the dog bit during the hold: 6.8")
	t.eq(thief:GetAttribute("Slowed"), true)
	-- a death mid-carry: the theft ends, the new character walks at 16
	sim:KillCharacter(thief)
	sim:Advance(0.2)
	t.eq(S.last(sim, thief, "Cancel").Reason, "died")
	t.eq(thief:GetAttribute("Slowed"), nil, "Slowed cleared")
	t.eq(Speed._debugSizes().Players, 0, "no modifier left")
	t.ok(
		sim:WaitFor(function()
			local humanoid = thief.Character and thief.Character:FindFirstChildOfClass("Humanoid")
			return humanoid ~= nil and humanoid.Health > 0
		end, 8, S.COARSE),
		"a new character"
	)
	sim:Advance(0.5)
	t.eq(S.walk(thief), S.WALK, "the new character at 16")
	sim:Advance(S.LIMITS.FailCooldown[1] + 0.5)

	-- a Dog key that expires mid-carry (no dog near any more) → back to 13.6 in SlowLinger + 0.1
	local victim2 = S.player(t, sim, 103, { tank = TANK })
	S.toCarry(t, sim, thief, victim2, 3)
	t.near(S.walk(thief), S.CARRY, 1e-6, "13.6")
	local clock = sim:Env().os.clock -- (the sim's virtual clock: what Lib/Speed reads)
	sim:Run(function()
		Speed.Set(thief, "Dog", S.DOG.Slow, clock() + 0.3)
	end)
	sim:Advance(S.FRAME)
	t.near(S.walk(thief), S.CARRY * S.DOG.Slow, 1e-6, "slowed")
	sim:Advance(0.3 + 0.1)
	t.near(S.walk(thief), S.CARRY, 1e-6, "the key expired by itself: 13.6")
	t.eq(thief:GetAttribute("Slowed"), nil, "Slowed gone with the key")
	-- MinFactor: the product never goes under it
	sim:Run(function()
		Speed.Set(thief, "Test", 0.1)
	end)
	t.near(S.walk(thief), S.WALK * S.StealConfig.Speed.MinFactor, 1e-6, "MinFactor")
	sim:Run(function()
		Speed.Clear(thief, "Test")
	end)
	-- leave mid-carry: nothing left in Lib/Speed
	sim:RemovePlayer(thief)
	sim:Advance(0.2)
	t.eq(Speed._debugSizes().Players, 0, "no record of a player who left")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The home guard
--------------------------------------------------------------------------------

tests["home guard: carrying → refused, no teleport, no cooldown spent; the owner during a theft → his spawn facing +Z"] = function(
	t
)
	local sim, victim, thief = pair(t)
	S.toCarry(t, sim, thief, victim, 3)
	local root = thief.Character.HumanoidRootPart
	local at = root.Position
	sim:FireServer(thief, "RequestHome")
	sim:Advance(0.2)
	t.eq(lastNotify(sim, thief), S.STEAL_TEXTS.HomeGuard, "the guard's text")
	t.ok((root.Position - at).Magnitude < 0.5, "no teleport")
	-- the owner presses «ДОМОЙ» during the theft on his base: his spawn, facing the court
	sim:FireServer(victim, "RequestHome")
	sim:Advance(0.2)
	local base = S.baseOf(sim, victim)
	local vroot = victim.Character.HumanoidRootPart
	local look = base:GetPivot():VectorToObjectSpace(vroot.CFrame.LookVector)
	t.ok(look.Z > 0.99, `facing +Z of the base (local look {look})`)
	t.ok((vroot.Position - (base.SpawnPad.Position + Vector3.new(0, 3, 0))).Magnitude < 6, "on the spawn pad")
	-- the carry ends (shield); «ДОМОЙ» works at once: the refusal spent no cooldown
	sim:FireServer(victim, "ShieldActivate")
	sim:Advance(0.2)
	t.eq(thief:GetAttribute("Stealing"), nil)
	sim:FireServer(thief, "RequestHome")
	sim:Advance(0.2)
	local thiefBase = S.baseOf(sim, thief)
	t.ok((root.Position - thiefBase.SpawnPad.Position).Magnitude < 8, "home at once (no cooldown was spent)")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Unmount, leaks, BindToClose
--------------------------------------------------------------------------------

local STEAL_ATTRS = { "StealBy", "StealEnd", "StealPhase", "Escrow", "FreshUntil" }

tests["unmount (BE-5): the victim leaves mid-carry → the freed base has no steal channel; a new owner mounts a clean base"] = function(
	t
)
	local sim, victim, thief = pair(t)
	local base = S.baseOf(sim, victim)
	local index = victim:GetAttribute("BaseIndex")
	-- every other base taken, one player waiting in the queue: he gets exactly the freed base
	for id = 201, 206 do
		S.player(t, sim, id, { fresh = true, protected = true })
	end
	local queued = sim:AddPlayer({ UserId = 107, Name = "Player107", DisplayName = "Игрок107", clientDelay = 1e9 })
	sim:Advance(0.5)
	t.eq(queued:GetAttribute("BaseIndex"), 0, "the 9th player waits for a base")
	S.toCarry(t, sim, thief, victim, 3)
	t.eq(S.slot(sim, victim, 3):GetAttribute("StealPhase"), "carry")
	sim:RemovePlayer(victim)
	sim:Advance(0.3)
	for i = 1, 12 do
		local slot = base.Tank.Slots[`Slot_{i}`]
		for _, name in STEAL_ATTRS do
			t.eq(slot:GetAttribute(name), nil, `Slot_{i}.{name} cleared`)
		end
		local prompt = slot.Pedestal.PromptAttachment.StealPrompt
		t.eq(prompt.Enabled, false, `Slot_{i}: the prompt off`)
		t.eq(prompt.ObjectText, "", `Slot_{i}: no ObjectText`)
		t.eq(prompt.HoldDuration, S.BASE_HOLD, `Slot_{i}: the base hold`)
	end
	t.eq(base:GetAttribute("Thief"), nil, "base.Thief cleared")
	t.eq(base:GetAttribute("AlarmState"), nil, "base.AlarmState cleared")
	t.eq(thief:GetAttribute("Stealing"), nil, "the thief's theft ended")
	-- the queued player mounts the freed base
	local tank = S.service(sim, "TankService")
	t.ok(
		sim:WaitFor(function()
			return tank:IsMounted(queued)
		end, 10, S.COARSE),
		"the queued player mounts"
	)
	t.eq(queued:GetAttribute("BaseIndex"), index, "the freed base")
	for i = 1, 12 do
		local slot = base.Tank.Slots[`Slot_{i}`]
		for _, name in { "StealBy", "StealEnd", "StealPhase", "Escrow" } do
			t.eq(slot:GetAttribute(name), nil, `new owner: Slot_{i}.{name}`)
		end
	end
	t.eq(base:GetAttribute("Thief"), nil)
	t.eq(base:GetAttribute("AlarmState"), nil)
	-- the base's defence attributes are the new owner's own (a fresh save: newbie, nothing bought)
	t.eq(base:GetAttribute("ProtectKind"), "newbie", "his own protection")
	t.eq(base:GetAttribute("HasDog"), false)
	t.eq(base:GetAttribute("HasAlarm"), false)
	t.eq(base:GetAttribute("LockLevel"), 0)
	t.eq(base:GetAttribute("HoldTime"), S.BASE_HOLD)
	sim:AssertNoErrors({ warnings = true })
end

tests["leaks: connections back to baseline, _debugSizes zero after Advance(VictimWindow) with no writes, the watcher ends"] = function(
	t
)
	local sim = S.boot(t)
	sim:Advance(1)
	local baseline = sim:CountConnections("server")
	local victim = S.player(t, sim, 101, { tank = TANK, upgrades = { Dog = true, Alarm = true } })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local steal = S.service(sim, "StealService")
	-- one credited theft (cooldown, after, alert) and one failed (fails, tagged)
	S.toCarry(t, sim, thief, victim, 3)
	S.out(sim, thief, victim, "gate", S.CARRY * S.DOG.Slow)
	t.ok(S.last(sim, thief, "Done"), "credited")
	sim:Advance(S.LIMITS.ThiefCooldown + 1, S.COARSE)
	S.unprotect(sim, victim)
	S.toCarry(t, sim, thief, victim, 2)
	sim:Teleport(victim, S.beside(thief, 4))
	sim:Advance(0.3)
	t.eq(S.last(sim, thief, "Cancel").Reason, "tag")
	t.ok(steal._debugSizes().Tags > 0, "a tag wait is kept")
	sim:Advance(2, S.COARSE)
	t.ok(
		sim:WaitFor(function()
			return steal._debugSizes().Watcher == 0
		end, 30, S.COARSE),
		"the watcher stops once nothing is stolen and the dog sleeps"
	)
	sim:RemovePlayer(thief)
	sim:RemovePlayer(victim)
	sim:Advance(S.GAP + 6, S.COARSE)
	t.eq(sim:CountConnections("server"), baseline, `server connections back to baseline\n{sim:FormatConnections()}`)
	-- the time-bounded maps empty themselves without any write (pruned inside _debugSizes)
	sim:Advance(S.LIMITS.VictimWindow + 1, 1)
	S.sizesZero4(t, sim, "after both left")
	t.eq(S.service(sim, "TankService")._debugSizes().Escrows, 0)
	sim:AssertNoErrors({ warnings = true })
end

-- A2-02: anything that throws after StealFish moved the fish must still end the theft.
local BOOM = {
	path = "ServerScriptService.Services.DefenceService",
	from = "function DefenceService:GiveAfterTheft(victim: Player)",
	to = 'function DefenceService:GiveAfterTheft(victim: Player)\n\tif victim then error("boom (test: after StealFish)") end',
}

tests["robust end (A2-02): an error after StealFish (in the credit) still ends the theft — Stealing nil, 16, no record, the watcher stops"] = function(
	t
)
	local sim, victim, thief = pair(t, { boot = { patches = { BOOM } } })
	local steal = S.service(sim, "StealService")
	S.toCarry(t, sim, thief, victim, 3)
	S.out(sim, thief, victim, "gate")
	t.ok(S.rowByOrigin(S.tankOf(sim, thief), `{victim.UserId}:f3`), "StealFish ran: the fish is the thief's")
	t.eq(S.rowOf(S.tankOf(sim, victim), "f3"), nil, "… and not the victim's")
	t.eq(thief:GetAttribute("Stealing"), nil, "the theft ended (Stealing nil)")
	t.eq(S.walk(thief), S.WALK, "the thief walks at 16 again")
	t.eq(
		sim:Run(function()
			return steal:IsStealing(thief)
		end),
		nil,
		"IsStealing nil"
	)
	t.eq(thief.Character:FindFirstChild("StolenFish"), nil, "no StolenFish left")
	t.eq(steal._debugSizes().Thefts, 0, "no theft record")
	t.ok(
		sim:WaitFor(function()
			return steal._debugSizes().Watcher == 0
		end, 15, S.COARSE),
		"the watcher stops"
	)
	local warned = false
	for _, w in sim.Warnings do
		if string.find(w.message, "после StealFish", 1, true) then
			warned = true
		end
	end
	t.ok(warned, "one warning names the failure")
	sim:AssertNoErrors()
end

-- A2-03: the wait survives a rejoin (by UserId), and so does the attribute the client filter reads.
tests["rejoin (A2-03): the thief's wait survives a rejoin — the new Player gets StealCooldownUntil back, the server denies «cooldown»"] = function(
	t
)
	local sim, victim, thief = pair(t)
	local other = S.player(t, sim, 103, { tank = TANK })
	S.toCarry(t, sim, thief, victim, 3)
	S.out(sim, thief, victim, "gate")
	t.ok(S.last(sim, thief, "Done"), "credited")
	local untilT = thief:GetAttribute("StealCooldownUntil")
	t.ok(type(untilT) == "number", "StealCooldownUntil set")
	sim:RemovePlayer(thief)
	sim:Advance(1)
	local again = S.player(t, sim, 102, { keep = true })
	local restored = again:GetAttribute("StealCooldownUntil")
	t.ok(type(restored) == "number", `the new Player has StealCooldownUntil ({restored})`)
	t.ok(restored and math.abs(restored - untilT) < 0.5, `… the same end ({restored} vs {untilT})`)
	local denied = S.denied(t, sim, again, other, 1)
	t.eq(denied and denied.Reason, "cooldown", "the server still denies «cooldown»")
	-- after the wait, a rejoin writes nothing
	sim:Advance(S.LIMITS.ThiefCooldown + 1, S.COARSE)
	sim:RemovePlayer(again)
	sim:Advance(1)
	local third = S.player(t, sim, 102, { keep = true })
	t.eq(third:GetAttribute("StealCooldownUntil"), nil, "no stale attribute once the wait is over")
	sim:AssertNoErrors({ warnings = true })
end

-- A2-04: the owner's own defence is celebrated even inside the first QuietSavedUnder second.
tests["quiet (A2-04): a tag or the shield within 1 s → Saved loud (though no Alert reached him yet); the thief's own release within 1 s → nothing to the victim (V-UX-01)"] = function(
	t
)
	local sim, victim, thief = pair(t)
	local prompt = S.prompt(sim, victim, 3)
	S.standAt(sim, thief, prompt)
	S.moveTo(sim, victim, S.beside(thief, S.StealConfig.Tag.Range + 1)) -- row 13 lets the hold begin
	sim:BeginHold(thief, prompt)
	sim:Advance(S.FRAME)
	t.eq(thief:GetAttribute("Stealing"), "hold", "the hold began")
	sim:Advance(0.3)
	S.moveTo(sim, victim, S.beside(thief, 4)) -- the owner steps in
	sim:Advance(0.2)
	local saved = S.last(sim, victim, "Saved")
	t.eq(saved and saved.Reason, "tag", "a tag after ≈ 0.5 s")
	t.eq(saved and saved.Quiet, nil, "the owner's tag is celebrated (not Quiet)")
	t.eq(#S.events(sim, victim, "Alert"), 0, "… inside the tap window: no Alert had reached him (V-UX-01)")
	sim:Advance(S.LIMITS.TagCooldown + 1, S.COARSE)

	-- the shield 0.5 s into a hold (on another victim: the tag wait is per base)
	local victim2 = S.player(t, sim, 103, { tank = TANK })
	S.hold(t, sim, thief, victim2, 3)
	t.eq(thief:GetAttribute("Stealing"), "hold", "a second hold began")
	sim:Advance(0.5)
	sim:FireServer(victim2, "ShieldActivate")
	sim:Advance(0.2)
	saved = S.last(sim, victim2, "Saved")
	t.eq(saved and saved.Reason, "shield", "the shield after ≈ 0.7 s")
	t.eq(saved and saved.Quiet, nil, "the owner's shield save is celebrated (not Quiet)")

	-- the thief's own release within 1 s: the victim never heard of that hold — nothing (BE-19, V-UX-01)
	local victim3 = S.player(t, sim, 104, { tank = TANK })
	local _, prompt3 = S.hold(t, sim, thief, victim3, 3)
	t.eq(thief:GetAttribute("Stealing"), "hold", "a third hold began")
	sim:Advance(0.4)
	sim:ReleasePrompt(thief, prompt3)
	sim:Advance(0.2)
	t.eq(S.last(sim, thief, "Cancel").Reason, "released", "the thief let go")
	t.eq(#S.events(sim, victim3, "Alert"), 0, "a release under 1 s: no Alert …")
	t.eq(#S.events(sim, victim3, "Saved"), 0, "… and no Saved")
	sim:AssertNoErrors({ warnings = true })
end

tests["BindToClose during the hold and the carry → each fish home once (the victim's close save has it)"] = function(
	t
)
	local sim = S.boot(t)
	local victimA = S.player(t, sim, 101, { tank = TANK })
	local victimB = S.player(t, sim, 103, { tank = TANK })
	local thiefA = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local thiefB = S.player(t, sim, 104, { tank = { { Id = "Crucian" } } })
	S.hold(t, sim, thiefA, victimA, 3)
	t.eq(thiefA:GetAttribute("Stealing"), "hold")
	S.toCarry(t, sim, thiefB, victimB, 3)
	sim:Shutdown({ timeout = 30 })
	for _, id in { 101, 103 } do
		local saved = S.peek(sim, id)
		local n = 0
		for _, row in saved.Tank do
			if row.Uid == "f3" then
				n += 1
			end
		end
		t.eq(n, 1, `victim {id}: the fish once in the close save`)
		t.eq(saved.Session, nil, `victim {id}: the lock released`)
	end
	for _, id in { 102, 104 } do
		local saved = S.peek(sim, id)
		for _, row in saved.Tank do
			t.eq(row.Origin, nil, `thief {id}: no stolen fish`)
		end
	end
	sim:AssertNoErrors({ warnings = true })
end

return tests
