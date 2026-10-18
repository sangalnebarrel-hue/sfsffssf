--[[
	Stage 4 wave 1 A — the HoldBegan checks of §4.3 on the real server (docs/stage4_design.md §4.3,
	§7.2 «Every Denied reason»), in RbxSim against the built Place1.rbxl with headless players
	(tests/stage4_server.luau): every row of Shared/TheftChecks answered as designed —
	  silent: an unknown prompt, a repeat on the held prompt (BE-17: the theft goes on), the start
	  bucket, the own base; Denied with the slot named (BE-16): loading, nobase, busy, far (a
	  HoldBegan from 200 studs), stealing (one thief, two prompts → one theft), cooldown, tagged,
	  shield / join / newbie / after / rest, taken (two thieves, one base), owner, few, weak
	  (thief $96/s vs victim $20/s → refused; vs $40/s → allowed; DC-09), missing, fresh (F11: the
	  escrowed fish of a thief), new (a catch → refused → allowed at 30 s; DC-08), full; the same
	  reason again within 2 s → Quiet.

	Run: lune run tools/run_tests.luau stage4_checks
]]

local S = require("./stage4_server")

local tests = {}

local TANK = {
	{ Id = "Perch" },
	{ Id = "Perch" },
	{ Id = "Puffer" },
	{ Id = "Crucian" },
}
local DENIED = S.STEAL_TEXTS.Denied

local function expect(t: any, d: any, reason: string, slot: number, what: string)
	t.ok(d, `{what}: a Denied came`)
	t.eq(d and d.Reason, reason, what)
	t.eq(d and d.Slot, slot, `{what}: Denied names the slot`)
	t.ok(d and type(d.BaseIndex) == "number", `{what}: Denied names the base`)
	t.ok(d and type(d.Text) == "string" and d.Text ~= "", `{what}: a text`)
end

--------------------------------------------------------------------------------
-- Silent rows, the repeat, the bucket, the own base
--------------------------------------------------------------------------------

tests["silent rows: an unknown prompt, a repeat on the held prompt (the theft goes on, BE-17), the own base, the bucket"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = TANK })
	-- the own base: nothing at all
	local own = S.denied(t, sim, thief, thief, 3)
	t.eq(own, nil, "no Denied on the own base")
	t.eq(thief:GetAttribute("Stealing"), nil, "no theft on the own base")
	-- a repeat on the held prompt: ignored, no token spent, the theft goes on
	local hold, prompt = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active)
	for _ = 1, 10 do
		sim:FirePromptEvent(thief, prompt, "HoldBegan")
	end
	sim:Advance(S.FRAME)
	t.eq(#S.events(sim, thief, "Denied"), 0, "a repeat gets no answer")
	t.eq(thief:GetAttribute("Stealing"), "hold", "the theft goes on")
	t.eq(S.service(sim, "StealService")._debugSizes().Thefts, 1)
	sim:Advance(S.BASE_HOLD)
	t.eq(thief:GetAttribute("Stealing"), "carry", "… and completes")
	sim:ReleasePrompt(thief, prompt)
	S.out(sim, thief, victim, "gate")
	t.ok(S.last(sim, thief, "Done"), "credited")
	-- the bucket: 100 HoldBegans from far away in one frame → at most StartBurst answers
	local other = S.player(t, sim, 103, { tank = TANK })
	local far = S.prompt(sim, other, 2)
	local before = #S.events(sim, thief, "Denied")
	for _ = 1, 100 do
		sim:FirePromptEvent(thief, far, "HoldBegan")
	end
	sim:Advance(0.1)
	local answers = #S.events(sim, thief, "Denied") - before
	t.ok(answers >= 1 and answers <= S.LIMITS.StartBurst, `≤ Burst answers ({answers})`)
	t.eq(S.service(sim, "StealService")._debugSizes().Thefts, 0, "no theft started")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The thief: loading, nobase, far, stealing, cooldown, tagged
--------------------------------------------------------------------------------

tests["thief rows: loading, nobase (the queue), far (200 studs), stealing (two prompts → one theft), cooldown"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	-- loading: his data is still on its way
	S.seed(sim, 120, { tank = TANK })
	sim.DataStore:SetKeyLatency(S.key(120), 30)
	local loading =
		sim:AddPlayer({ UserId = 120, Name = "Player120", DisplayName = "Игрок120", clientDelay = 1e9 })
	t.ok(
		sim:WaitFor(function()
			return loading.Character ~= nil
		end, 8, S.COARSE),
		"a character while loading"
	)
	sim:Advance(1) -- (the spawn settles: BaseService places the character)
	expect(t, S.denied(t, sim, loading, victim, 3), "loading", 3, "loading")
	t.eq(S.denied(t, sim, loading, victim, 3).Quiet, true, "the same reason again within 2 s: Quiet")
	sim:RemovePlayer(loading)
	-- far: a HoldBegan from 200 studs (fireproximityprompt)
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	sim:Teleport(thief, S.basePoint(S.baseOf(sim, victim), 0, -200, S.HRP_HEIGHT))
	sim:Advance(S.FRAME)
	expect(t, S.denied(t, sim, thief, victim, 3, { fire = true }), "far", 3, "far")
	-- stealing: one thief on two prompts (the sim lets him) → one theft; he stands between two
	-- neighbouring displays of one arcade (odd slots: 3 and 5, 11 apart — 5.5 studs from each)
	S.addFish(sim, victim, "Perch", nil, "stolen") -- (slot 5; not a fresh catch)
	local prompt = S.prompt(sim, victim, 3)
	local second = S.prompt(sim, victim, 5)
	S.standAt(sim, thief, prompt)
	local function at(p: any): any
		return (p.Parent.Parent.CFrame * p.Parent.CFrame).Position -- (Pedestal × PromptAttachment)
	end
	local between = (at(second) - at(prompt)) / 2
	local root = thief.Character.HumanoidRootPart
	sim:Teleport(thief, root.Position + S.Vector3.new(between.X, 0, between.Z))
	sim:Advance(S.FRAME)
	local hold = sim:BeginHold(thief, prompt)
	sim:Advance(S.FRAME)
	t.ok(hold.active, `the first hold ({hold.cancelReason})`)
	t.eq(thief:GetAttribute("Stealing"), "hold")
	local h2 = sim:BeginHold(thief, second)
	sim:Advance(S.FRAME)
	expect(t, S.last(sim, thief, "Denied"), "stealing", 5, "stealing")
	if h2.active then
		sim:ReleasePrompt(thief, second)
	end
	t.eq(S.service(sim, "StealService")._debugSizes().Thefts, 1, "one theft")
	sim:Advance(S.BASE_HOLD)
	sim:ReleasePrompt(thief, prompt)
	S.out(sim, thief, victim, "gate")
	t.ok(S.last(sim, thief, "Done"), "the first theft credits")
	-- cooldown after the success (another victim: the first one is protected now)
	local victim2 = S.player(t, sim, 104, { tank = TANK })
	local d = S.denied(t, sim, thief, victim2, 3)
	expect(t, d, "cooldown", 3, "cooldown")
	t.ok(string.find(d.Text, "0:2", 1, true) ~= nil or string.find(d.Text, "0:3", 1, true) ~= nil, d.Text)
	-- nobase: every base taken, the 9th waits in the queue
	for id = 201, 205 do
		S.player(t, sim, id, { fresh = true, protected = true })
	end
	local waiting =
		sim:AddPlayer({ UserId = 130, Name = "Player130", DisplayName = "Игрок130", clientDelay = 1e9 })
	t.ok(
		sim:WaitFor(function()
			return waiting:GetAttribute("DataMode") == "Ready" and waiting.Character ~= nil
		end, 10, S.COARSE),
		"loaded, no base"
	)
	t.eq(waiting:GetAttribute("BaseIndex"), 0)
	expect(t, S.denied(t, sim, waiting, victim2, 3), "nobase", 3, "nobase")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The victim: busy, protection kinds, taken, owner, few, weak
--------------------------------------------------------------------------------

tests["victim rows: busy (still loading), shield / join / newbie / after / rest, taken, owner, few"] = function(t)
	local sim = S.boot(t)
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local defence = S.service(sim, "DefenceService")
	-- busy: the owner of the base is still loading (base assigned, tank not mounted)
	S.seed(sim, 140, { tank = TANK })
	sim.DataStore:SetKeyLatency(S.key(140), 30)
	local loadingOwner =
		sim:AddPlayer({ UserId = 140, Name = "Player140", DisplayName = "Игрок140", clientDelay = 1e9 })
	sim:Advance(1)
	t.ok((loadingOwner:GetAttribute("BaseIndex") or 0) > 0, "the loading owner has a base")
	expect(t, S.denied(t, sim, thief, loadingOwner, 3), "busy", 3, "busy")
	sim:RemovePlayer(loadingOwner)
	sim:Advance(0.5)

	-- newbie: a new save's first session (SaveCount 0 at load)
	local newbie = S.player(t, sim, 141, { tank = TANK, saveCount = 0, lastOnline = 0, protected = true })
	t.eq(defence:IsProtected(newbie), "newbie")
	local d = S.denied(t, sim, thief, newbie, 3)
	expect(t, d, "newbie", 3, "newbie")
	t.ok(string.find(d.Text, "4:5", 1, true) ~= nil or string.find(d.Text, "5:00", 1, true) ~= nil, d.Text)
	-- join: a returning player (last online long ago) → 90 s; a quick rejoin → 20 s
	local back = S.player(t, sim, 142, { tank = TANK, lastOnline = 1, protected = true })
	t.eq(defence:IsProtected(back), "join")
	expect(t, S.denied(t, sim, thief, back, 3), "join", 3, "join")
	-- shield
	S.unprotect(sim, back)
	sim:FireServer(back, "ShieldActivate")
	sim:Advance(0.1)
	t.eq(defence:IsProtected(back), "shield")
	sim:Advance(2.1)
	expect(t, S.denied(t, sim, thief, back, 3), "shield", 3, "shield")
	sim:RemovePlayer(newbie)
	sim:RemovePlayer(back)
	sim:Advance(0.5)

	-- after and rest: two losses within the window
	local victim = S.player(
		t,
		sim,
		101,
		{ tank = { { Id = "Perch" }, { Id = "Perch" }, { Id = "Puffer" }, { Id = "Crucian" }, { Id = "Perch" } } }
	)
	local thiefB = S.player(t, sim, 103, { tank = { { Id = "Crucian" } } })
	sim:Advance(6) -- (the start bucket refills after the attempts above)
	S.toCarry(t, sim, thief, victim, 3)
	S.out(sim, thief, victim, "gate")
	t.ok(S.last(sim, thief, "Done"), "the first loss")
	sim:Advance(2.1)
	expect(t, S.denied(t, sim, thiefB, victim, 1), "after", 1, "after")
	sim:Advance(S.LIMITS.VictimImmunity, 0.5)
	t.eq(defence:IsProtected(victim), nil, "the after immunity ended")
	S.toCarry(t, sim, thiefB, victim, 1)
	S.out(sim, thiefB, victim, "gate")
	t.ok(S.last(sim, thiefB, "Done"), "the second loss")
	t.eq(defence:IsProtected(victim), "rest", "2 losses in 600 s → rest")
	local thiefC = S.player(t, sim, 105, { tank = { { Id = "Crucian" } } })
	expect(t, S.denied(t, sim, thiefC, victim, 2), "rest", 2, "rest")

	-- taken: two thieves on one base; owner: the owner next to the thief; few: < 3 fish
	local base = S.player(t, sim, 106, { tank = TANK })
	local thiefD = S.player(t, sim, 107, { tank = { { Id = "Crucian" } } })
	local hold = S.hold(t, sim, thiefC, base, 3)
	t.ok(hold.active)
	expect(t, S.denied(t, sim, thiefD, base, 1), "taken", 1, "taken")
	sim:ReleasePrompt(thiefC, S.prompt(sim, base, 3))
	sim:Advance(0.2)
	S.standAt(sim, thiefD, S.prompt(sim, base, 2))
	sim:Teleport(base, S.beside(thiefD, 4))
	sim:Advance(S.FRAME)
	local h = sim:BeginHold(thiefD, S.prompt(sim, base, 2))
	sim:Advance(S.FRAME)
	expect(t, S.last(sim, thiefD, "Denied"), "owner", 2, "owner")
	if h.active then
		sim:ReleasePrompt(thiefD, S.prompt(sim, base, 2))
	end
	local poor = S.player(t, sim, 108, { tank = { { Id = "Perch" }, { Id = "Perch" } } })
	expect(t, S.denied(t, sim, thiefD, poor, 1), "few", 1, "few")
	t.eq(S.last(sim, thiefD, "Denied").Text, DENIED.few)
	sim:AssertNoErrors({ warnings = true })
end

tests["weak (DC-09): a thief at $96/s vs a victim at $20/s → refused; vs $40/s → allowed"] = function(t)
	local sim = S.boot(t)
	local rich = S.player(t, sim, 102, { tank = { { Id = "SharkPup" }, { Id = "SharkPup" }, { Id = "SharkPup" } } })
	t.near(rich:GetAttribute("Income"), 96, 1e-6, "the thief earns $96/s")
	local poor = S.player(t, sim, 101, { tank = { { Id = "Swordfish" }, { Id = "Swordfish" }, { Id = "Crucian" } } })
	t.near(poor:GetAttribute("Income"), 20, 1e-6, "the victim earns $20/s")
	local d = S.denied(t, sim, rich, poor, 1)
	expect(t, d, "weak", 1, "weak")
	t.eq(d.Text, DENIED.weak)
	local fair = S.player(t, sim, 103, {
		tank = {
			{ Id = "Swordfish" },
			{ Id = "Swordfish" },
			{ Id = "Swordfish" },
			{ Id = "Puffer" },
			{ Id = "Puffer" },
			{ Id = "Puffer" },
		},
	})
	t.ok(fair:GetAttribute("Income") * 3 >= 96, `a victim at ${fair:GetAttribute("Income")}/s`)
	local hold = S.hold(t, sim, rich, fair, 1)
	t.ok(hold.active)
	t.eq(rich:GetAttribute("Stealing"), "hold", "a fair victim can be robbed")
	sim:ReleasePrompt(rich, S.prompt(sim, fair, 1))
	sim:Advance(0.2)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The fish: missing, fresh (escrow, F11), new (DC-08), full
--------------------------------------------------------------------------------

tests["fish rows: missing, fresh (the escrowed fish of a thief, F11), new (a catch: refused, allowed at 30 s), full"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" }, { Id = "Perch" }, { Id = "Perch" } } })
	local third = S.player(t, sim, 103, { tank = { { Id = "Crucian" } } })
	-- missing: an empty display (its prompt is off: ignoreEnabled)
	expect(t, S.denied(t, sim, third, victim, 6), "missing", 6, "missing")
	-- fresh: the thief's escrowed fish (the victim's save is slow)
	sim.DataStore:SetKeyLatency(S.key(101), 8)
	S.toCarry(t, sim, thief, victim, 3)
	S.out(sim, thief, victim, "gate")
	local tank = S.service(sim, "TankService")
	t.eq(tank:EscrowCount(thief), 1, "escrowed while the victim's save is in flight")
	local row = S.rowByOrigin(S.tankOf(sim, thief), `{victim.UserId}:f3`)
	t.eq(S.slot(sim, thief, row.Slot):GetAttribute("Escrow"), true)
	local d = S.denied(t, sim, third, thief, row.Slot)
	expect(t, d, "fresh", row.Slot, "fresh (escrow)")
	t.eq(d.Text, DENIED.fresh)
	sim.DataStore:SetKeyLatency(S.key(101), nil)
	-- new: a catch is not stealable for FreshCatch s
	local caught = S.addFish(sim, victim, "Puffer", nil, "catch")
	t.eq(caught.Result, "stored")
	t.ok(type(S.slot(sim, victim, caught.Slot):GetAttribute("FreshUntil")) == "number", "FreshUntil on the slot")
	sim:Advance(2.1)
	S.unprotect(sim, victim)
	d = S.denied(t, sim, third, victim, caught.Slot)
	expect(t, d, "new", caught.Slot, "new")
	sim:Advance(S.LIMITS.FreshCatch, 0.5)
	S.unprotect(sim, victim)
	local hold = S.hold(t, sim, third, victim, caught.Slot)
	t.ok(hold.active)
	t.eq(third:GetAttribute("Stealing"), "hold", "allowed once FreshCatch passed")
	sim:ReleasePrompt(third, S.prompt(sim, victim, caught.Slot))
	sim:Advance(S.LIMITS.FailCooldown[1] + 0.5)
	-- full: the thief's tank is full of fish stronger than the loot
	local strong = S.player(t, sim, 104, {
		tank = {
			{ Id = "SharkPup" },
			{ Id = "Swordfish" },
			{ Id = "Swordfish" },
			{ Id = "Swordfish" },
			{ Id = "Swordfish" },
			{ Id = "Swordfish" },
		},
	})
	local weakVictim = S.player(t, sim, 105, {
		tank = { { Id = "Perch" }, { Id = "Perch" }, { Id = "Perch" }, { Id = "SharkPup" }, { Id = "SharkPup" } },
	})
	d = S.denied(t, sim, strong, weakVictim, 1)
	expect(t, d, "full", 1, "full")
	t.eq(d.Text, DENIED.full)
	sim:AssertNoErrors({ warnings = true })
end

tests["tagged: a tag forbids that base for TagCooldown (with the time in the text)"] = function(t)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	S.toCarry(t, sim, thief, victim, 3)
	sim:Teleport(victim, S.beside(thief, 3))
	sim:Advance(0.2)
	t.eq(S.last(sim, thief, "Cancel").Reason, "tag")
	sim:Teleport(victim, S.baseOf(sim, victim).SpawnPad.Position + S.Vector3up(3))
	sim:Advance(S.LIMITS.FailCooldown[1] + 0.2)
	local d = S.denied(t, sim, thief, victim, 3)
	expect(t, d, "tagged", 3, "tagged")
	t.ok(string.find(d.Text, "0:1", 1, true) ~= nil, d.Text)
	sim:Advance(S.LIMITS.TagCooldown, 0.5)
	local hold = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active)
	t.eq(thief:GetAttribute("Stealing"), "hold", "allowed again after TagCooldown")
	sim:ReleasePrompt(thief, S.prompt(sim, victim, 3))
	sim:Advance(0.2)
	sim:AssertNoErrors({ warnings = true })
end

return tests
