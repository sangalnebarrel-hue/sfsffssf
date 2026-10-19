--[[
	Stage 4 wave 1 A — DefenceService on the real server (docs/stage4_design.md §2, §4.10, §7.4), in
	RbxSim against the built Place1.rbxl with headless players and the sim DataStore:
	  • the shield: ProtectUntil 60 s, a live hold cancelled; refused while ≥ 60 s of protection
	    remain (no cooldown spent), accepted with 30 s of after left → now + 60 (DC-03), refused while
	    stealing (the probe), on cooldown; ready again at 240 s; persisted: leave → restart(+100 s) →
	    rejoin → still ≈ 140 s to ready; «Щит погас» when it ends;
	  • the join protection (DC-07, BE-25): a fresh save → 300 s newbie; a second session → 90 s; a
	    quick rejoin → 20 s by LastOnline and, in Memory mode, by this server's leftAt; a player queued
	    behind a full server whose session already saved → 90 s at the mount, not 20; a steal ends it
	    and a manual shield once the hold outlasts the tap window (no refund: ShieldReadyAt kept; the
	    hold's first frame keeps it — stage 4 wave 3 UX-01);
	  • after / rest re-applied on a later session of this server;
	  • the Studio knob (DC-20): StudioProtect = 10 with IsStudio → newbie / after / rest ≤ 10 s, the
	    shield still 60 s, one print, no warning;
	  • purchases: Dog / Alarm / Lock (level 1): money, Stats.Spent, the ledger, the save, the
	    attributes; the dog shown at Dog.Rest (parts visible, the kennel solid) and hidden with the
	    template pivot back on unmount; every Denied reason (loading, nobase, owned, soon, max with
	    SaleMax patched, money); 50 buys in a frame → one purchase per item; SaleMax 5 → ≤ Burst
	    levels, each paid;
	  • no require cycle: DefenceService works with a stub StealService (the default probe).

	Run: lune run tools/run_tests.luau stage4_defence
]]

local S = require("./stage4_server")

local tests = {}

local TANK = {
	{ Id = "Perch" },
	{ Id = "Perch" },
	{ Id = "Puffer" },
	{ Id = "Crucian" },
}
local SHIELD = S.SHIELD
local DTEXTS = S.DEFENCE_TEXTS

local function now(sim: any): number
	return sim.workspace:GetServerTimeNow()
end

local function protectLeft(sim: any, defence: any, p: any): (string?, number)
	local kind, untilT = defence:IsProtected(p)
	return kind, if untilT then untilT - now(sim) else 0
end

local function lastDefence(sim: any, p: any, kind: string): any
	local list = S.defenceEvents(sim, p, kind)
	local e = list[#list]
	return e and e.data
end

local function lastNotify(sim: any, p: any): string?
	local events = sim:ClientEventsFor(p, "Notify")
	local e = events[#events]
	return e and e.args[1]
end

--------------------------------------------------------------------------------
-- The shield
--------------------------------------------------------------------------------

tests["shield: 60 s, cancels a live hold; refused while ≥ 60 s remain, tops up 30 s of after (DC-03); stealing; cooldown; ready at 240 s"] = function(
	t
)
	local sim = S.boot(t)
	local owner = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local defence = S.service(sim, "DefenceService")
	local base = S.baseOf(sim, owner)
	-- a live hold on his base is cancelled by the shield
	local hold = S.hold(t, sim, thief, owner, 3)
	t.ok(hold.active)
	sim:Advance(0.5)
	sim:FireServer(owner, "ShieldActivate")
	sim:Advance(0.1)
	t.eq(S.last(sim, thief, "Cancel").Reason, "shield")
	local kind, left = protectLeft(sim, defence, owner)
	t.eq(kind, "shield")
	t.near(left, SHIELD.Duration, 0.3, "60 s")
	t.eq(base:GetAttribute("ProtectKind"), "shield")
	t.near(base:GetAttribute("ProtectUntil") - now(sim), SHIELD.Duration, 0.3, "ProtectUntil")
	t.near(owner:GetAttribute("ShieldUntil") - now(sim), SHIELD.Duration, 0.3, "ShieldUntil")
	t.near(owner:GetAttribute("ShieldReadyAt") - now(sim), SHIELD.Duration + SHIELD.Cooldown, 0.3, "ready in 240 s")
	local event = lastDefence(sim, owner, "Shield")
	t.ok(event and event.Until and event.ReadyAt, "DefenceEvent Shield")
	sim:ReleasePrompt(thief, S.prompt(sim, owner, 3))
	-- refused while protected ≥ 60 s (here: the shield itself) — no cooldown spent either way
	sim:Advance(2.1)
	sim:FireServer(owner, "ShieldActivate")
	sim:Advance(0.1)
	local denied = lastDefence(sim, owner, "Denied")
	t.eq(denied and denied.Reason, "cooldown", "on cooldown (an active shield < 60 s left)")
	t.ok(string.find(denied.Text, "3:5", 1, true) ~= nil, denied.Text)
	-- the shield ends: «Щит погас»
	sim:Advance(SHIELD.Duration, 0.5)
	t.eq(defence:IsProtected(owner), nil, "the shield went out")
	t.eq(owner:GetAttribute("ShieldUntil"), nil)
	t.eq(base:GetAttribute("ProtectUntil"), nil)
	t.eq(base:GetAttribute("ProtectKind"), nil)
	local noted = false
	for _, e in sim:ClientEventsFor(owner, "Notify") do
		if e.args[1] == DTEXTS.Shield.Off and e.args[2] == "shield" then
			noted = true
		end
	end
	t.ok(noted, "«Щит погас» (kind shield)")
	-- ready again 240 s after the activation
	sim:Advance(owner:GetAttribute("ShieldReadyAt") - now(sim) - 2, 1)
	sim:FireServer(owner, "ShieldActivate")
	sim:Advance(0.1)
	t.eq(lastDefence(sim, owner, "Denied").Reason, "cooldown", "not yet at 238 s")
	sim:Advance(2.2)
	sim:FireServer(owner, "ShieldActivate")
	sim:Advance(0.1)
	t.eq(defence:IsProtected(owner), "shield", "ready again at 240 s")
	sim:AssertNoErrors({ warnings = true })
end

tests["shield: refused with ≥ 60 s of after left (no cooldown spent), accepted with 30 s left → now + 60; refused while stealing"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = TANK })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local defence = S.service(sim, "DefenceService")
	S.toCarry(t, sim, thief, victim, 3)
	S.out(sim, thief, victim, "gate")
	local kind, left = protectLeft(sim, defence, victim)
	t.eq(kind, "after")
	t.near(left, S.LIMITS.VictimImmunity, 0.5, "90 s after")
	sim:FireServer(victim, "ShieldActivate")
	sim:Advance(0.1)
	local denied = lastDefence(sim, victim, "Denied")
	t.eq(denied.Reason, "protected", "≥ 60 s left: refused")
	t.ok(
		string.find(denied.Text, "1:30", 1, true) ~= nil or string.find(denied.Text, "1:29", 1, true) ~= nil,
		denied.Text
	)
	t.eq(victim:GetAttribute("ShieldReadyAt"), nil, "no cooldown spent")
	sim:Advance(S.LIMITS.VictimImmunity - 30, 1)
	sim:FireServer(victim, "ShieldActivate")
	sim:Advance(0.1)
	kind, left = protectLeft(sim, defence, victim)
	t.eq(kind, "shield", "accepted with 30 s left (DC-03)")
	t.near(left, SHIELD.Duration, 0.3, "now + 60")
	-- refused while stealing himself
	local other = S.player(t, sim, 103, { tank = TANK })
	local thiefB = S.player(t, sim, 104, { tank = TANK })
	local hold = S.hold(t, sim, thiefB, other, 3)
	t.ok(hold.active)
	t.eq(defence._isStealing(thiefB), true, "the probe answers")
	sim:FireServer(thiefB, "ShieldActivate")
	sim:Advance(0.1)
	t.eq(lastDefence(sim, thiefB, "Denied").Reason, "stealing")
	t.eq(lastDefence(sim, thiefB, "Denied").Text, DTEXTS.Denied.stealing)
	sim:ReleasePrompt(thiefB, S.prompt(sim, other, 3))
	sim:Advance(0.2)
	sim:AssertNoErrors({ warnings = true })
end

tests["shield persisted: leave → restart(+100 s) → rejoin → still ≈ 140 s to ready"] = function(t)
	local sim = S.boot(t)
	local p = S.player(t, sim, 101, { tank = TANK })
	sim:FireServer(p, "ShieldActivate")
	sim:Advance(0.2)
	t.ok(p:GetAttribute("ShieldReadyAt"), "the shield is up")
	sim:Advance(S.GAP + 1, S.COARSE)
	local saved = S.peek(sim, 101)
	t.ok(type(saved.Upgrades.ShieldReadyAt) == "number", "Upgrades.ShieldReadyAt saved")
	sim:RemovePlayer(p)
	sim:Advance(S.GAP + 2, S.COARSE)
	local after = S.restart(t, sim, 100)
	local back = S.player(t, after, 101, { keep = true, protected = true })
	local readyIn = back:GetAttribute("ShieldReadyAt") - after.workspace:GetServerTimeNow()
	local elapsed = 0.2 + S.GAP + 1 + S.GAP + 2 -- the time since the activation on the old server
	t.near(readyIn, SHIELD.Duration + SHIELD.Cooldown - 100 - elapsed, 2, `≈ 140 s to ready ({readyIn})`)
	after:FireServer(back, "ShieldActivate")
	after:Advance(0.1)
	t.eq(lastDefence(after, back, "Denied").Reason, "cooldown", "still recharging after the rejoin")
	sim:AssertNoErrors({ warnings = true })
	after:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The join protection
--------------------------------------------------------------------------------

tests["join protection: a fresh save → 300 s newbie; a second session → 90 s; a quick rejoin (LastOnline) → 20 s"] = function(
	t
)
	local sim = S.boot(t)
	local defence = S.service(sim, "DefenceService")
	local fresh = S.player(t, sim, 101, { fresh = true, protected = true })
	local kind, left = protectLeft(sim, defence, fresh)
	t.eq(kind, "newbie")
	t.near(left, SHIELD.JoinProtectFirst, 1)
	t.eq(S.baseOf(sim, fresh):GetAttribute("ProtectKind"), "newbie")
	local second = S.player(t, sim, 102, { tank = TANK, lastOnline = 1, protected = true })
	kind, left = protectLeft(sim, defence, second)
	t.eq(kind, "join", "a second session")
	t.near(left, SHIELD.JoinProtect, 1)
	local quick = S.player(t, sim, 103, { tank = TANK, protected = true }) -- (LastOnline = the epoch: just now)
	kind, left = protectLeft(sim, defence, quick)
	t.eq(kind, "join", "a quick rejoin")
	t.near(left, SHIELD.QuickRejoinProtect, 1)
	-- a steal ends all of his protection and a manual shield, with no refund — once the hold has
	-- outlasted a tap (stage 4 wave 3 UX-01: not at its first frame)
	sim:FireServer(second, "ShieldActivate")
	sim:Advance(0.1)
	t.eq(lastDefence(sim, second, "Denied").Reason, "protected", "90 s of join: the shield is refused")
	S.unprotect(sim, quick)
	sim:Advance(2.1)
	S.unprotect(sim, second)
	sim:FireServer(second, "ShieldActivate")
	sim:Advance(0.1)
	t.eq(defence:IsProtected(second), "shield")
	local ready = second:GetAttribute("ShieldReadyAt")
	local hold = S.hold(t, sim, second, quick, 3)
	t.ok(hold.active)
	t.eq(defence:IsProtected(second), "shield", "the hold's first frame: still shielded (a tap costs nothing)")
	sim:Advance(1.5) -- (past the tap window: 1.4 s on this link)
	t.eq(second:GetAttribute("Stealing"), "hold", "still holding")
	t.eq(defence:IsProtected(second), nil, "stealing ended his shield")
	t.eq(second:GetAttribute("ShieldReadyAt"), ready, "no refund of the cooldown")
	t.eq(lastNotify(sim, second), S.STEAL_TEXTS.Hint.Ended)
	sim:ReleasePrompt(second, S.prompt(sim, quick, 3))
	sim:Advance(0.2)
	sim:AssertNoErrors({ warnings = true })
end

tests["join protection: Memory mode rejoin → 20 s by leftAt; queued behind a full server after a save → 90 s, not 20 (BE-25)"] = function(
	t
)
	-- Memory mode: LastOnline stays 0 — the rejoin is quick by this server's leftAt
	local memory = S.boot(t, {
		before = function(s: any)
			s.DataStore:SetEnabled(false)
		end,
	})
	local defence = S.service(memory, "DefenceService")
	local first = S.player(t, memory, 101, { fresh = true, protected = true })
	t.eq(defence:IsProtected(first), "newbie", "Memory mode: SaveCount stays 0 (R21)")
	memory:RemovePlayer(first)
	memory:Advance(3)
	local again = S.player(t, memory, 101, { fresh = true, protected = true })
	local kind, left = protectLeft(memory, defence, again)
	t.eq(kind, "join", "a rejoin to this server")
	t.near(left, SHIELD.QuickRejoinProtect, 1, "20 s by leftAt")
	S.takeWarnings(memory, "DataStore")
	S.takeWarnings(memory, "Memory")
	memory:AssertNoErrors({ warnings = true })

	-- a full server: he waits in the queue, his session saves (LastOnline = now), then he mounts
	local sim = S.boot(t)
	local fillers = {}
	for id = 201, 208 do
		table.insert(fillers, S.player(t, sim, id, { fresh = true, protected = true }))
	end
	S.seed(sim, 150, { tank = TANK })
	local key = S.key(150)
	local saved = sim.DataStore:Peek(S.STORE, key)
	saved.LastOnline = 1
	sim.DataStore:Poke(S.STORE, key, saved)
	local queued = sim:AddPlayer({ UserId = 150, Name = "Player150", DisplayName = "Игрок150", clientDelay = 1e9 })
	t.ok(
		sim:WaitFor(function()
			return queued:GetAttribute("DataMode") == "Ready"
		end, 10, S.COARSE),
		"loaded in the queue"
	)
	local data = S.service(sim, "DataService")
	sim:Run(function()
		data:SaveSoon(queued)
	end)
	t.ok(
		sim:WaitFor(function()
			return data:CommittedSeq(queued) > 0
		end, S.GAP + 3, S.COARSE),
		"his session saved while queued"
	)
	t.ok(math.abs(data:Get(queued).LastOnline - (S.EPOCH + sim:Time())) < 5, "LastOnline in the live data is now")
	sim:RemovePlayer(fillers[1])
	t.ok(
		sim:WaitFor(function()
			return S.service(sim, "TankService"):IsMounted(queued)
		end, 10, S.COARSE),
		"mounted"
	)
	local d = S.service(sim, "DefenceService")
	kind, left = protectLeft(sim, d, queued)
	t.eq(kind, "join")
	t.near(left, SHIELD.JoinProtect, 1, "90 s (read at load), not the quick 20")
	sim:AssertNoErrors({ warnings = true })
end

tests["after and rest are re-applied on a later session of this server (leaving never shortens them)"] = function(t)
	local sim = S.boot(t)
	local defence = S.service(sim, "DefenceService")
	local victim = S.player(t, sim, 101, {
		tank = { { Id = "Perch" }, { Id = "Perch" }, { Id = "Puffer" }, { Id = "Crucian" }, { Id = "Perch" } },
	})
	local thiefA = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	local thiefB = S.player(t, sim, 103, { tank = { { Id = "Crucian" } } })
	S.toCarry(t, sim, thiefA, victim, 1)
	S.out(sim, thiefA, victim, "gate")
	t.eq(defence:IsProtected(victim), "after")
	-- leave and rejoin within the after: it comes back (not a fresh 20 s)
	sim:Advance(S.GAP + 2, S.COARSE)
	sim:RemovePlayer(victim)
	sim:Advance(S.GAP + 3, S.COARSE)
	victim = S.player(t, sim, 101, { keep = true, protected = true })
	local kind, untilT = defence:IsProtected(victim)
	t.eq(kind, "after", "the after re-applied (it ends later than the quick-rejoin 20 s)")
	t.ok(untilT - now(sim) > S.SHIELD.QuickRejoinProtect, "not shortened")
	sim:Advance(S.LIMITS.VictimImmunity, 1)
	S.unprotect(sim, victim) -- (the quick-rejoin join protection; his losses list is cleared too …)
	t.eq(defence._debugSizes().Losses, 0, "… EndProtection forgets the losses")
	-- two losses → rest; leave and rejoin → rest again
	S.toCarry(t, sim, thiefB, victim, 2)
	S.out(sim, thiefB, victim, "gate")
	sim:Advance(S.LIMITS.VictimImmunity + 1, 1)
	S.toCarry(t, sim, thiefA, victim, 3)
	S.out(sim, thiefA, victim, "gate")
	local restKind, restUntil = defence:IsProtected(victim)
	t.eq(restKind, "rest")
	sim:Advance(S.GAP + 2, S.COARSE)
	sim:RemovePlayer(victim)
	sim:Advance(S.GAP + 3, S.COARSE)
	victim = S.player(t, sim, 101, { keep = true, protected = true })
	local k2, u2 = defence:IsProtected(victim)
	t.eq(k2, "rest", "the rest re-applied")
	t.near(u2, restUntil, 0.5, "with the same end")
	sim:AssertNoErrors({ warnings = true })
end

tests["Studio knob (DC-20): StudioProtect 10 → newbie / after / rest ≤ 10 s, the shield still 60 s, one print, no warning"] = function(
	t
)
	local sim = S.boot(t, { studio = true })
	local prints = 0
	for _, line in sim:Output() do
		if string.find(line, "[DefenceService] Studio", 1, true) then
			prints += 1
		end
	end
	t.eq(prints, 1, "one print line")
	local defence = S.service(sim, "DefenceService")
	local newbie = S.player(t, sim, 101, { tank = TANK, saveCount = 0, lastOnline = 0, protected = true })
	local kind, left = protectLeft(sim, defence, newbie)
	t.eq(kind, "newbie")
	t.near(left, 10, 0.5, "newbie clamped to 10 s")
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } } })
	sim:Advance(10.5)
	t.eq(defence:IsProtected(newbie), nil, "over after 10 s")
	S.toCarry(t, sim, thief, newbie, 3)
	S.out(sim, thief, newbie, "gate")
	kind, left = protectLeft(sim, defence, newbie)
	t.eq(kind, "after")
	t.near(left, 10, 0.5, "after clamped to 10 s")
	sim:Advance(10.5)
	sim:FireServer(newbie, "ShieldActivate")
	sim:Advance(0.1)
	kind, left = protectLeft(sim, defence, newbie)
	t.eq(kind, "shield")
	t.near(left, SHIELD.Duration, 0.3, "the shield is untouched: 60 s")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Purchases
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

tests["purchases: Dog / Alarm / Lock — money, Stats.Spent, the ledger, the save, attributes; the dog at Dog.Rest; hidden on unmount"] = function(
	t
)
	local sim = S.boot(t)
	local p = S.player(t, sim, 101, { tank = TANK, money = 12000 })
	local data = S.service(sim, "DataService")
	local base = S.baseOf(sim, p)
	local template = sim.game:GetService("ServerStorage"):FindFirstChild("BaseTemplate")
	local function pupLocal(b: any): any
		return b:GetPivot():ToObjectSpace(b.Dog.Pup:GetPivot())
	end
	local pupBefore = pupLocal(base)
	for _, item in { "Dog", "Alarm", "Lock" } do
		sim:FireServer(p, "DefenceBuy", item)
		sim:Advance(0.1)
		local bought = lastDefence(sim, p, "Bought")
		t.eq(bought and bought.Item, item, `{item} bought`)
	end
	local spent = S.DOG.Price + S.DefenceConfig.Alarm.Price + S.LOCK.Levels[1].Price
	local d = data:Get(p)
	t.eq(d.Money, 12000 - spent, "money down by the prices")
	t.eq(d.Stats.Spent, spent, "Stats.Spent")
	S.ledgerHolds(t, sim, d, "after the purchases")
	t.eq(d.Upgrades.Dog, true)
	t.eq(d.Upgrades.Alarm, true)
	t.eq(d.LockLevel, 1)
	for _, who in { p, base } do
		t.eq(who:GetAttribute("HasDog"), true, "HasDog")
		t.eq(who:GetAttribute("HasAlarm"), true, "HasAlarm")
		t.eq(who:GetAttribute("LockLevel"), 1, "LockLevel")
	end
	t.eq(base:GetAttribute("HoldTime"), S.LOCK.Levels[1].Hold)
	t.ok(
		sim:WaitFor(function()
			local saved = S.peek(sim, 101)
			return saved.Upgrades.Dog == true and saved.Upgrades.Alarm == true and saved.LockLevel == 1
		end, S.GAP + 2, S.COARSE),
		"saved soon"
	)
	-- the dog: shown, the pup at its guard spot in the court facing the gate, the kennel solid
	local dog = base.Dog
	t.eq(dog:GetAttribute("Unlocked"), true)
	for _, part in partsOf(dog) do
		t.eq(part.Transparency, 0, `{part.Name} visible`)
	end
	t.eq(dog.Pup.Body.CastShadow, true)
	t.eq(dog.Pup.Body.CanCollide, false, "the pup never collides")
	for _, part in partsOf(dog.DogHouse) do
		if part.Name == "Walls" or part.Name == "Roof" then
			t.eq(part.CanCollide, true, `kennel {part.Name} solid`)
		end
	end
	local rest = pupLocal(base)
	t.near(rest.Position.X, S.DOG.Rest.X, 1e-3, "Dog.Rest X")
	t.near(rest.Position.Z, S.DOG.Rest.Z, 1e-3, "Dog.Rest Z")
	t.near(rest.LookVector.Z, -1, 1e-3, "facing the gate (−Z)")
	-- unmount: exactly the template look and pivot
	sim:RemovePlayer(p)
	sim:Advance(0.2)
	t.eq(dog:GetAttribute("Unlocked"), false)
	for _, part in partsOf(dog) do
		t.eq(part.Transparency, 1, `{part.Name} hidden again`)
		t.eq(part.CanCollide, false, `{part.Name} not colliding`)
	end
	local back = pupLocal(base)
	t.near(back.Position, pupBefore.Position, 1e-3, "the pup at its template pivot")
	t.near(back.LookVector, pupBefore.LookVector, 1e-3)
	local tplPup = template.PrimaryPart.CFrame:ToObjectSpace(template.Dog.Pup:GetPivot())
	t.near(back.Position, tplPup.Position, 1e-3, "… the template's own")
	for _, name in { "HasDog", "HasAlarm", "LockLevel", "HoldTime", "ProtectUntil", "ProtectKind" } do
		t.eq(base:GetAttribute(name), nil, `base.{name} cleared`)
	end
	sim:AssertNoErrors({ warnings = true })
end

tests["purchase denials: loading, nobase, owned, soon, money (with the price); 50 buys in a frame → one purchase per item"] = function(
	t
)
	local sim = S.boot(t)
	local rich = S.player(t, sim, 101, { tank = TANK, money = 20000 })
	local poor = S.player(t, sim, 102, { tank = TANK, money = 100 })
	local data = S.service(sim, "DataService")
	-- 50 buys of each in one frame: one purchase per item
	for _ = 1, 50 do
		sim:FireServer(rich, "DefenceBuy", "Dog")
	end
	sim:Advance(0.1)
	t.eq(#S.defenceEvents(sim, rich, "Bought"), 1, "one Dog")
	t.eq(data:Get(rich).Money, 20000 - S.DOG.Price, "paid once")
	sim:Advance(5)
	local mark = #S.defenceEvents(sim, rich, "Denied")
	for _, item in { "Dog", "Lock", "Lock" } do
		sim:FireServer(rich, "DefenceBuy", item)
	end
	sim:Advance(0.1)
	local denied = S.defenceEvents(sim, rich, "Denied")
	t.eq(denied[mark + 1].data.Reason, "owned", "Dog again → owned")
	t.eq(denied[mark + 1].data.Text, DTEXTS.Denied.owned)
	t.eq(denied[mark + 2].data.Reason, "soon", "the lock beyond SaleMax → soon")
	t.eq(denied[mark + 2].data.Item, "Lock")
	t.eq(data:Get(rich).LockLevel, 1, "level 1 only (SaleMax)")
	-- not enough money
	sim:FireServer(poor, "DefenceBuy", "Alarm")
	sim:Advance(0.1)
	local d = lastDefence(sim, poor, "Denied")
	t.eq(d.Reason, "money")
	t.ok(string.find(d.Text, "2", 1, true) ~= nil and string.find(d.Text, "500", 1, true) ~= nil, d.Text)
	t.eq(data:Get(poor).Stats.Spent, 0, "nothing paid")
	-- junk is silent
	for _, junk in { 5, "Rocket", {}, nil } do
		sim:FireServer(poor, "DefenceBuy", junk)
	end
	sim:Advance(0.1)
	t.eq(#S.defenceEvents(sim, poor), 1, "junk items get no answer")
	-- loading and nobase
	S.seed(sim, 140, { tank = TANK, money = 9000 })
	sim.DataStore:SetKeyLatency(S.key(140), 30)
	local loading =
		sim:AddPlayer({ UserId = 140, Name = "Player140", DisplayName = "Игрок140", clientDelay = 1e9 })
	sim:Advance(0.5)
	sim:FireServer(loading, "DefenceBuy", "Dog")
	sim:FireServer(loading, "ShieldActivate")
	sim:Advance(0.1)
	local ld = S.defenceEvents(sim, loading, "Denied")
	t.eq(ld[1].data.Reason, "loading")
	t.eq(ld[2].data.Reason, "loading", "the shield too")
	sim:RemovePlayer(loading)
	for id = 201, 206 do
		S.player(t, sim, id, { fresh = true, protected = true })
	end
	local queued = sim:AddPlayer({ UserId = 150, Name = "Player150", DisplayName = "Игрок150", clientDelay = 1e9 })
	t.ok(
		sim:WaitFor(function()
			return queued:GetAttribute("DataMode") == "Ready"
		end, 10, S.COARSE),
		"loaded, no base"
	)
	sim:FireServer(queued, "DefenceBuy", "Alarm")
	sim:FireServer(queued, "ShieldActivate")
	sim:Advance(0.1)
	local qd = S.defenceEvents(sim, queued, "Denied")
	t.eq(qd[1].data.Reason, "nobase")
	t.eq(qd[2].data.Reason, "nobase", "the shield too")
	S.ledgerHolds(t, sim, data:Get(rich), "rich")
	sim:AssertNoErrors({ warnings = true })
end

tests["SaleMax patched to 5: the lock levels one by one, each paid, ≤ Burst per frame; level 5 → max"] = function(t)
	local sim = S.boot(t, {
		patches = {
			{
				path = "ReplicatedStorage.Shared.Config.DefenceConfig",
				from = "SaleMax = 1,",
				to = "SaleMax = 5,",
			},
		},
	})
	local p = S.player(t, sim, 101, { tank = TANK, money = 200000 })
	local data = S.service(sim, "DataService")
	for _ = 1, 50 do
		sim:FireServer(p, "DefenceBuy", "Lock")
	end
	sim:Advance(0.1)
	local bought = #S.defenceEvents(sim, p, "Bought")
	t.ok(bought >= 1 and bought <= S.DefenceConfig.Requests.Burst, `≤ Burst levels in one frame ({bought})`)
	local paid = 0
	for level = 1, bought do
		paid += S.LOCK.Levels[level].Price
	end
	t.eq(data:Get(p).Money, 200000 - paid, "each level paid")
	sim:Advance(6)
	for _ = 1, 8 do
		sim:FireServer(p, "DefenceBuy", "Lock")
		sim:Advance(1.1)
	end
	t.eq(data:Get(p).LockLevel, 5, "the best lock")
	t.eq(lastDefence(sim, p, "Denied").Reason, "max")
	t.eq(S.prompt(sim, p, 1).HoldDuration, S.LOCK.Levels[5].Hold, "the prompts at 9 s")
	S.ledgerHolds(t, sim, data:Get(p), "after the locks")
	sim:AssertNoErrors({ warnings = true })
end

tests["no require cycle: DefenceService works with a stub StealService (the default probe)"] = function(t)
	local sim = S.boot(t, {
		before = function(s: any)
			local module = s:Find("ServerScriptService.Services.StealService")
			module.Source = "return { Init = function() end, Start = function() end }"
		end,
	})
	local p = S.player(t, sim, 101, { tank = TANK })
	local defence = S.service(sim, "DefenceService")
	t.eq(defence._isStealing(p), false, "the default probe: nobody steals")
	sim:FireServer(p, "ShieldActivate")
	sim:Advance(0.1)
	t.eq(defence:IsProtected(p), "shield", "the shield works without StealService")
	sim:AssertNoErrors({ warnings = true })
end

return tests
