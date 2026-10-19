--[[
	Stage 4 wave 1 A — the dog, the alarm's early warning and the unmount reset on the real server
	(docs/stage4_design.md §2.1, §2.2, §4.4, §4.9, §4.11, §7.4), in RbxSim against the built
	Place1.rbxl with headless players:
	  • the dog brain: from Dog.Rest it reaches the thief at each of slots 1–6 before Lock.BaseHold
	    (DC-05); DogPos written at most every Dog.Replicate s and never while it stands; it never bites
	    once the theft ended (Return); it stays on its leash (the plot + Dog.Leash) during a chase out
	    of the side fence; asleep → nothing ticks (no brain, the watcher stopped);
	  • the alarm (upgrade only): a visitor in the plot → one Intruder per IntruderCoalesce s and
	    AlarmState "intruder" for IntruderLamp s; none without the alarm, none while protected; the
	    1 Hz loop stops when no alarmed base is mounted;
	  • the unmount reset (BE-27): an owner with a dog, the alarm and a lock leaves mid-theft → the
	    base, its slots, its dog (hidden, its template pivot, no DogState / DogPos / DogTarget) and its
	    prompts are those of a fresh base; the next owner mounts that clean base.

	Run: lune run tools/run_tests.luau stage4_defence_dog
]]

local S = require("./stage4_server")

local tests = {}

local SIX = {
	{ Id = "Perch" },
	{ Id = "Perch" },
	{ Id = "Puffer" },
	{ Id = "Crucian" },
	{ Id = "Perch" },
	{ Id = "Crucian" },
}
local DOG = S.DOG

local function dogLib(sim: any): any
	return sim:Require(sim:Find("ServerScriptService.Lib.DogBrain"))
end

local function baseRecord(sim: any, p: any): any
	return S.service(sim, "BaseService"):GetBase(p)
end

local function cooldownLeft(sim: any, p: any): number
	local untilT = p:GetAttribute("StealCooldownUntil")
	return if type(untilT) == "number" then untilT - sim.workspace:GetServerTimeNow() else 0
end

--------------------------------------------------------------------------------
-- The dog
--------------------------------------------------------------------------------

tests["dog: from Dog.Rest it reaches the thief at slots 1–6 before BaseHold; DogPos ≤ 5 Hz, none while standing; no bite in Return"] = function(
	t
)
	-- (six let-gos on one base: Limits.BaseFails off, or the base would close after two — stage 4
	-- wave 3 UX-03, tested in stage4_fairness_grief)
	local sim = S.boot(t, {
		patches = {
			{
				path = "ReplicatedStorage.Shared.Config.StealConfig",
				from = "\t\tBaseFails = 2,",
				to = "\t\tBaseFails = 0,",
			},
		},
	})
	local victim = S.player(t, sim, 101, { tank = SIX, upgrades = { Dog = true } })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local brains = dogLib(sim)
	local steal = S.service(sim, "StealService")
	local base = baseRecord(sim, victim)
	local dog = base.Dog
	local writes = {}
	dog:GetAttributeChangedSignal("DogPos"):Connect(function()
		table.insert(writes, sim:Time())
	end)
	for slot = 1, 6 do
		t.ok(
			sim:WaitFor(function()
				return brains.Get(base) == nil and cooldownLeft(sim, thief) <= 0
			end, 40, S.COARSE),
			`slot {slot}: the dog asleep at its rest spot, the thief ready`
		)
		sim:Advance(0.1)
		local hold, prompt = S.hold(t, sim, thief, victim, slot)
		t.ok(hold.active, `slot {slot}: hold`)
		local began = sim:Time()
		t.eq(dog:GetAttribute("DogState"), "Alert", `slot {slot}: «ГАВ!» first`)
		t.eq(dog:GetAttribute("DogTarget"), thief.UserId, `slot {slot}: the target`)
		local bit = sim:WaitFor(function()
			return thief:GetAttribute("Slowed") == true
		end, S.BASE_HOLD, S.FRAME)
		local arrival = sim:Time() - began
		t.ok(bit, `slot {slot}: the dog reached him during the hold ({arrival} s)`)
		t.ok(arrival < S.BASE_HOLD, `slot {slot}: before BaseHold ({arrival} s)`)
		t.log(`dog arrival at slot {slot}: {string.format("%.2f", arrival)} s`)
		-- let go before the end (≥ need − Tolerance would wait for Triggered): an ordinary "released"
		sim:Advance(math.max(0, began + S.BASE_HOLD - S.HOLD_CFG.Tolerance - 0.1 - sim:Time()))
		sim:ReleasePrompt(thief, prompt)
		sim:Advance(0.1)
		t.eq(S.last(sim, thief, "Cancel").Reason, "released")
		t.eq(dog:GetAttribute("DogState"), "Return", "home")
		t.eq(thief:GetAttribute("Slowed"), nil, "the end cleared the slow")
		sim:Advance(1.5)
		t.eq(thief:GetAttribute("Slowed"), nil, "a returning dog never bites")
		t.eq(S.walk(thief), S.WALK)
	end
	-- standing next to the thief (a long hold: a base with the lock's last level) — no DogPos write
	local locked = S.player(t, sim, 103, { tank = SIX, upgrades = { Dog = true }, lock = #S.LOCK.Levels })
	local lockedBase = baseRecord(sim, locked)
	local standing = 0
	lockedBase.Dog:GetAttributeChangedSignal("DogPos"):Connect(function()
		standing += 1
	end)
	t.ok(
		sim:WaitFor(function()
			return cooldownLeft(sim, thief) <= 0
		end, 40, S.COARSE),
		"the thief ready for the long hold"
	)
	sim:Advance(0.1)
	local hold, prompt = S.hold(t, sim, thief, locked, 4)
	t.ok(hold.active, "the long hold")
	t.eq(prompt.HoldDuration, S.LOCK.Levels[#S.LOCK.Levels].Hold, "Lock: the last level's hold")
	local lastPos: any, since = nil, sim:Time()
	t.ok(
		sim:WaitFor(function()
			local b = brains.Get(lockedBase)
			local here = b and b.Pos
			if here ~= lastPos then
				lastPos, since = here, sim:Time()
			end
			-- (the watcher steps every Tick: unchanged for longer than a step and the last move written)
			return here ~= nil
				and b.State == "Chase"
				and thief:GetAttribute("Slowed") == true
				and sim:Time() - since > 2 * S.TICK
				and b.WrittenPos ~= nil
				and (here - b.WrittenPos).Magnitude <= DOG.MoveEpsilon
		end, 5, S.FRAME),
		"the dog stands at the thief"
	)
	t.eq(lockedBase.Dog:GetAttribute("DogState"), "Chase", "still chasing")
	t.eq(thief:GetAttribute("Slowed"), true, "biting")
	local mark = standing
	sim:Advance(1.5)
	t.eq(standing, mark, "no DogPos write while it stands")
	sim:ReleasePrompt(thief, prompt)
	sim:Advance(0.1)
	t.eq(S.last(sim, thief, "Cancel").Reason, "released")
	-- the write rate: never two DogPos writes closer than Replicate
	for i = 2, #writes do
		t.ok(writes[i] - writes[i - 1] >= DOG.Replicate - 1e-3, `DogPos writes {writes[i] - writes[i - 1]} s apart`)
	end
	t.ok(
		sim:WaitFor(function()
			return brains.Get(base) == nil and brains.Get(lockedBase) == nil
		end, 20, S.COARSE),
		"asleep again"
	)
	t.eq(dog:GetAttribute("DogState"), "Sleep")
	t.ok(
		sim:WaitFor(function()
			return steal._debugSizes().Watcher == 0
		end, 2, S.COARSE),
		"nothing ticks while it sleeps"
	)
	t.eq(steal._debugSizes().Dogs, 0)
	t.eq(brains._debugSizes().Brains, 0)
	sim:AssertNoErrors({ warnings = true })
end

tests["dog: the leash (the plot + Dog.Leash) during a chase out of the side fence; the credit leaves the thief at 16"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = SIX, upgrades = { Dog = true } })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local base = baseRecord(sim, victim)
	local pivot = base.Model:GetPivot()
	local worst = 0
	base.Dog:GetAttributeChangedSignal("DogPos"):Connect(function()
		local pos = base.Dog:GetAttribute("DogPos")
		if pos then
			local here = pivot:PointToObjectSpace(pos)
			local outX = math.abs(here.X) - S.MapConfig.PlotHalfWidth
			local outZ =
				math.max(S.MapConfig.PlotFront - here.Z, here.Z - (S.MapConfig.PlotFront + S.MapConfig.PlotDepth))
			worst = math.max(worst, outX, outZ)
		end
	end)
	S.toCarry(t, sim, thief, victim, 2) -- (an east display: the side fence is close)
	S.out(sim, thief, victim, "side", S.CARRY * DOG.Slow)
	t.ok(S.last(sim, thief, "Done"), "credited")
	t.ok(worst <= DOG.Leash + 1e-3, `the dog stayed on its leash ({worst} studs out)`)
	sim:Advance(0.1)
	t.eq(S.walk(thief), S.WALK, "16 right after the credit")
	t.eq(thief:GetAttribute("Slowed"), nil)
	sim:Advance(5, S.COARSE)
	t.eq(S.walk(thief), S.WALK, "… and 5 s later")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The alarm's early warning
--------------------------------------------------------------------------------

tests["alarm: a visitor → one Intruder per 45 s and the «intruder» lamp; none without the alarm or while protected; the loop stops"] = function(
	t
)
	local sim = S.boot(t)
	local alarmed = S.player(t, sim, 101, { tank = SIX, upgrades = { Alarm = true } })
	local plain = S.player(t, sim, 103, { tank = SIX })
	local visitor = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local defence = S.service(sim, "DefenceService")
	t.eq(defence._debugSizes().IntruderLoop, 1, "the loop runs for an alarmed base")
	local base = baseRecord(sim, alarmed)
	sim:Teleport(visitor, S.basePoint(base.Model, 20, 90, S.HRP_HEIGHT))
	sim:Advance(1.5)
	local warned = S.events(sim, alarmed, "Intruder")
	t.eq(#warned, 1, "one early warning")
	t.eq(warned[1].data.Thief, visitor.UserId)
	t.eq(warned[1].data.Name, visitor.DisplayName)
	t.eq(base.Model:GetAttribute("AlarmState"), "intruder", "the lamp blinks «intruder»")
	sim:Advance(S.DefenceConfig.Alarm.IntruderLamp + 0.5)
	t.eq(base.Model:GetAttribute("AlarmState"), nil, "… for IntruderLamp s")
	sim:Advance(S.DefenceConfig.Alarm.IntruderCoalesce - 10, 0.5)
	t.eq(#S.events(sim, alarmed, "Intruder"), 1, "not again within 45 s")
	sim:Advance(10, 0.5)
	t.eq(#S.events(sim, alarmed, "Intruder"), 2, "again after 45 s while he stays")
	-- no alarm, no warning
	sim:Teleport(visitor, S.basePoint(baseRecord(sim, plain).Model, 20, 90, S.HRP_HEIGHT))
	sim:Advance(3)
	t.eq(#S.events(sim, plain, "Intruder"), 0, "a base without the alarm warns nobody")
	-- protected: no warning
	sim:FireServer(alarmed, "ShieldActivate")
	sim:Advance(0.1)
	sim:Teleport(visitor, S.basePoint(base.Model, -20, 90, S.HRP_HEIGHT))
	sim:Advance(S.DefenceConfig.Alarm.IntruderCoalesce + 2, 0.5)
	t.eq(#S.events(sim, alarmed, "Intruder"), 2, "none while protected")
	-- the loop stops once no alarmed base is mounted
	sim:RemovePlayer(alarmed)
	t.ok(
		sim:WaitFor(function()
			return defence._debugSizes().IntruderLoop == 0
		end, 3, S.COARSE),
		"the loop stopped"
	)
	t.eq(defence._debugSizes().Alarmed, 0)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The unmount reset
--------------------------------------------------------------------------------

local function partsOf(model: any): { any }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

local function assertFresh(t: any, sim: any, model: any, what: string)
	for _, name in
		{ "ProtectUntil", "ProtectKind", "HasDog", "HasAlarm", "LockLevel", "HoldTime", "AlarmState", "Thief" }
	do
		t.eq(model:GetAttribute(name), nil, `{what}: base.{name}`)
	end
	local dog = model.Dog
	t.eq(dog:GetAttribute("Unlocked"), false, `{what}: the dog locked`)
	for _, name in { "DogState", "DogPos", "DogTarget" } do
		t.eq(dog:GetAttribute(name), nil, `{what}: Dog.{name}`)
	end
	for _, part in partsOf(dog) do
		t.eq(part.Transparency, 1, `{what}: {part.Name} invisible`)
		t.eq(part.CanCollide, false, `{what}: {part.Name} not colliding`)
	end
	local template = sim.game:GetService("ServerStorage"):FindFirstChild("BaseTemplate")
	local want = template.PrimaryPart.CFrame:ToObjectSpace(template.Dog.Pup:GetPivot())
	local got = model.PrimaryPart.CFrame:ToObjectSpace(dog.Pup:GetPivot())
	t.near(got.Position, want.Position, 1e-3, `{what}: the pup at its template pivot`)
	t.near(got.LookVector, want.LookVector, 1e-3, `{what}: … facing`)
	for i = 1, 12 do
		local slot = model.Tank.Slots[`Slot_{i}`]
		for _, name in { "StealBy", "StealEnd", "StealPhase", "Escrow", "FreshUntil" } do
			t.eq(slot:GetAttribute(name), nil, `{what}: Slot_{i}.{name}`)
		end
		local prompt = slot.Pedestal.PromptAttachment.StealPrompt
		t.eq(prompt.Enabled, false, `{what}: Slot_{i} prompt off`)
		t.eq(prompt.HoldDuration, S.BASE_HOLD, `{what}: Slot_{i} HoldDuration`)
		t.eq(prompt.ObjectText, "", `{what}: Slot_{i} ObjectText`)
	end
end

tests["unmount reset (BE-27): an owner with dog, alarm and lock leaves mid-theft → a fresh base; the next owner mounts it clean"] = function(
	t
)
	local sim = S.boot(t)
	local owner = S.player(t, sim, 101, { tank = SIX, upgrades = { Dog = true, Alarm = true }, lock = 1 })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	-- every other base taken: the next player to join gets exactly the freed one
	for id = 201, 206 do
		S.player(t, sim, id, { fresh = true, protected = true })
	end
	local model = S.baseOf(sim, owner)
	local index = owner:GetAttribute("BaseIndex")
	t.eq(model:GetAttribute("HasDog"), true)
	t.eq(model:GetAttribute("LockLevel"), 1)
	t.eq(S.prompt(sim, owner, 1).HoldDuration, S.LOCK.Levels[1].Hold)
	S.toCarry(t, sim, thief, owner, 3)
	t.ok(model.Dog:GetAttribute("DogState") ~= nil, "the dog is awake")
	t.eq(model:GetAttribute("AlarmState"), "theft")
	sim:RemovePlayer(owner)
	sim:Advance(0.2)
	assertFresh(t, sim, model, "after the leave")
	t.eq(thief:GetAttribute("Stealing"), nil, "the theft ended")
	t.eq(S.walk(thief), S.WALK)
	sim:Advance(2)
	assertFresh(t, sim, model, "2 s later (no late writes)")
	-- the next owner of exactly this base
	local free = 0
	for _, b in sim.workspace.Bases:GetChildren() do
		if b:GetAttribute("OwnerUserId") == 0 then
			free += 1
		end
	end
	t.eq(free, 1, "one base left: the freed one")
	local next = S.player(t, sim, 107, { tank = SIX, protected = true })
	t.eq(next:GetAttribute("BaseIndex"), index, "the same base")
	t.eq(model:GetAttribute("HasDog"), false, "his own (no dog)")
	t.eq(model.Dog:GetAttribute("Unlocked"), false)
	t.eq(model:GetAttribute("LockLevel"), 0)
	t.eq(S.prompt(sim, next, 1).HoldDuration, S.BASE_HOLD)
	t.eq(model:GetAttribute("AlarmState"), nil)
	t.eq(model:GetAttribute("Thief"), nil)
	sim:AssertNoErrors({ warnings = true })
end

return tests
