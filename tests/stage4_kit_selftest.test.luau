--[[
	Stage 4 kit self-test — tests/stage4_kit.luau against the merged RbxSim (S1–S8 of
	docs/stage4_design.md §7.0) and the built Place1.rbxl, before any stage 4 suite leans on it:
	  • Kit.boot: the Studio knob off (DefenceConfig.Debug.StudioProtect = false on the server and on a
	    client), opts.studio keeps it (10), opts.patches stack on top of the knob, opts.removingOrder
	    reaches Sim.new (S7: our two PlayerRemoving handlers run backwards), no warnings;
	  • Kit.drive: the HRP moves at the asked speed whatever the WalkSpeed (16 stays untouched), faces the
	    goal and keeps its height; opts.stall stands still and pays the distance back in one jump (a 1.5 s
	    stall at the honest carry is more than a carry tick and less than StealConfig.Carry.Speed.Teleport),
	    opts.hop jumps first (a 30-stud hop is more than Teleport), opts.stop and opts.timeout end early;
	  • the prompts through the kit on a real display: Kit.stealPrompt (Wave 0: no StealPrompt yet —
	    StealService creates them in Wave 1 A), Kit.standAt in reach of a StealPrompt-like prompt on
	    Pedestal.PromptAttachment, the client-local MaxActivationDistance = 0 hide (S1) surviving a server
	    Enabled write (S2), a real hold with Kit.boot's latency (S8: the client at once, the server one
	    latency later), sim:FirePromptEvent (S3) from 200 studs away — HoldBegan, HoldEnded before
	    Triggered — reaching the server only, in call order, unchecked, one latency later, and the
	    client's own InputHoldEnd ending its hold (TheftController's Denied / Cancel path);
	    Kit.theftEvents / Kit.defenceEvents read the StealEvent / DefenceEvent logs by kind;
	  • Kit.seed (a poked save: tank with Kg / Age, money, lock, upgrades, saveCount, partial stats), the
	    seeded data live on the server (the ledger holds), Kit.basePoint / Kit.exitPoint against
	    StealRules (LocalOf, InPlot with ExitMargin, NearestExit), Kit.sizesZero4 after the leave, and
	    Kit.restart (the knob off again, the clock moved, the save kept).
	The prompt here is the test's own «KitPrompt», so StealService (Wave 1 A: unknown prompts are row 1,
	silent) never answers it and this file keeps passing as the waves land.
]]

local roblox = require("@lune/roblox")

local Kit = require("./stage4_kit")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local StealConfig = Kit.StealConfig
local DefenceConfig = Kit.DefenceConfig
local FRAME = Kit.FRAME

local tests = {}

local function knob(sim: any, who: any?): any
	return Kit.shared(sim, "Config.DefenceConfig", who).Debug.StudioProtect
end

local function flat(v: any): any
	return Vector3.new(v.X, 0, v.Z)
end

-- Every Heartbeat: { time, HRP position, Humanoid.WalkSpeed } of `p` (the harness is the server).
local function track(sim: any, p: any): ({ any }, () -> ())
	local samples = {}
	local root = p.Character.HumanoidRootPart
	local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
	local conn = sim.game:GetService("RunService").Heartbeat:Connect(function()
		table.insert(samples, { time = sim:Time(), pos = root.Position, walk = humanoid.WalkSpeed })
	end)
	return samples, function()
		conn:Disconnect()
	end
end

-- Horizontal steps between consecutive samples (the first from `from`).
local function steps(samples: { any }, from: any): { number }
	local out = {}
	local last = from
	for _, s in samples do
		table.insert(out, (flat(s.pos) - flat(last)).Magnitude)
		last = s.pos
	end
	return out
end

--------------------------------------------------------------------------------
-- Kit.boot
--------------------------------------------------------------------------------

tests["Kit.boot: the Studio knob off, studio = true keeps it, patches on top, removingOrder reaches Sim.new"] = function(
	t
)
	local sim = Kit.boot(t)
	t.eq(knob(sim), false, "the server reads StudioProtect = false (RbxSim answers IsStudio() == true)")
	t.eq(DefenceConfig.Debug.StudioProtect, 10, "src keeps 10 (the kit patches the place's module, not the file)")
	t.eq(sim.opts.removingOrder, nil, "no removingOrder by default (the sim's FIFO)")
	local p = Kit.join(t, sim, 1, "phone")
	t.eq(knob(sim, p), false, "a client reads the patched module too")
	sim:AssertNoErrors({ warnings = true })

	local studio = Kit.boot(t, { studio = true })
	t.eq(knob(studio), 10, "opts.studio keeps the knob (its own test, DC-20)")
	studio:AssertNoErrors({ warnings = true })

	local reversed = Kit.boot(t, {
		removingOrder = "reverse",
		patches = {
			{
				path = "ReplicatedStorage.Shared.Config.StealConfig",
				from = "Timeout = 25,",
				to = "Timeout = 26,",
			},
		},
	})
	t.eq(knob(reversed), false, "the knob is still off with patches of the test's own")
	t.eq(Kit.shared(reversed, "Config.StealConfig").Carry.Timeout, 26, "the test's patch applied")
	t.eq(reversed.opts.removingOrder, "reverse", "opts.removingOrder → Sim.new (S7)")
	local order = {}
	local Players = reversed.game:GetService("Players")
	Players.PlayerRemoving:Connect(function(who)
		table.insert(order, "first:" .. who.Name)
	end)
	Players.PlayerRemoving:Connect(function(who)
		table.insert(order, "second:" .. who.Name)
	end)
	local q = Kit.join(t, reversed, 2, "desktop")
	reversed:RemovePlayer(q)
	reversed:Advance(0.2)
	t.eq(order, { "second:Keeper2", "first:Keeper2" }, "PlayerRemoving handlers last-connected first")
	reversed:Advance(10, Kit.COARSE)
	reversed:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Kit.drive
--------------------------------------------------------------------------------

tests["Kit.drive: any speed whatever the WalkSpeed; stall pays back in one jump; hop; stop; timeout"] = function(t)
	local sim = Kit.boot(t)
	local p = Kit.join(t, sim, 1, "phone")
	local base = Kit.baseOf(sim, p)
	local root = p.Character.HumanoidRootPart
	local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
	local walk = humanoid.WalkSpeed
	t.eq(walk, Kit.WALK, "the character walks at 16")

	local function startAt(z: number): any
		local at = Kit.basePoint(base, 0, z, Kit.HRP_HEIGHT)
		sim:Teleport(p, CFrame.lookAt(at, Kit.basePoint(base, 0, z + 10, Kit.HRP_HEIGHT)))
		sim:Advance(FRAME)
		return root.Position
	end

	-- (a) a speed hack: 30 studs/s for 40 studs in the court, the WalkSpeed still 16
	local from = startAt(40)
	local goal = Kit.basePoint(base, 0, 80, Kit.HRP_HEIGHT)
	local samples, stop = track(sim, p)
	local t0 = sim:Time()
	t.ok(Kit.drive(sim, p, goal, 30), "(a) arrived")
	stop()
	t.near(sim:Time() - t0, 40 / 30, 2.5 * FRAME, "(a) 40 studs at 30 st/s")
	local most = 0
	for _, step in steps(samples, from) do
		most = math.max(most, step)
	end
	t.near(most, 30 * FRAME, 1e-3, "(a) every frame moves speed × frame, no more")
	t.near(flat(root.Position), flat(goal), 0.05, "(a) at the goal")
	t.near(root.Position.Y, from.Y, 1e-3, "(a) the height kept")
	local dir = (flat(goal) - flat(from)).Unit
	t.ok(flat(root.CFrame.LookVector).Unit:Dot(dir) > 0.99, "(a) facing the way it went")
	for _, s in samples do
		t.eq(s.walk, walk, "(a) Kit.drive never writes WalkSpeed")
	end
	t.eq(humanoid.WalkSpeed, walk)

	-- (b) a lagging phone at the honest carry: 1.5 s standing still, then the catch-up in one jump
	local STALL = 1.5
	from = startAt(30)
	goal = Kit.basePoint(base, 0, 100, Kit.HRP_HEIGHT)
	samples, stop = track(sim, p)
	t0 = sim:Time()
	t.ok(Kit.drive(sim, p, goal, Kit.CARRY, { stall = { at = 0.5, seconds = STALL } }), "(b) arrived")
	stop()
	t.near(sim:Time() - t0, 70 / Kit.CARRY, 2.5 * FRAME, "(b) the stall costs no time: it is paid back")
	local still, jump = 0, 0
	for _, step in steps(samples, from) do
		if step < 1e-6 then
			still += 1
		end
		jump = math.max(jump, step)
	end
	t.ok(math.abs(still - STALL / FRAME) <= 2, `(b) ≈ {STALL / FRAME} frames standing still (got {still})`)
	t.near(jump, Kit.CARRY * (STALL + FRAME), 1.5 * Kit.CARRY * FRAME, "(b) one jump pays the stall back")
	local speedCfg = StealConfig.Carry.Speed
	t.ok(jump > Kit.CARRY * STALL, "(b) more than any honest tick")
	t.ok(jump < speedCfg.Teleport, `(b) a 1.5 s stall ({jump}) is no teleport (< {speedCfg.Teleport})`)

	-- (c) a 30-stud hop first, then 16 st/s
	from = startAt(30)
	goal = Kit.basePoint(base, 0, 90, Kit.HRP_HEIGHT)
	samples, stop = track(sim, p)
	t.ok(Kit.drive(sim, p, goal, Kit.WALK, { hop = 30 }), "(c) arrived")
	stop()
	local hopSteps = steps(samples, from)
	t.near(hopSteps[1], 30 + Kit.WALK * FRAME, 1e-3, "(c) the first frame jumps the hop (+ one frame of walking)")
	t.ok(hopSteps[1] > speedCfg.Teleport, "(c) a 30-stud hop is more than Teleport")
	t.near(hopSteps[2], Kit.WALK * FRAME, 1e-3, "(c) then walking")

	-- (d) opts.stop ends early (false), (e) opts.timeout too
	from = startAt(30)
	goal = Kit.basePoint(base, 0, 130, Kit.HRP_HEIGHT)
	t0 = sim:Time()
	local arrived = Kit.drive(sim, p, goal, 20, {
		stop = function(s)
			return s:Time() >= t0 + 0.5
		end,
	})
	t.eq(arrived, false, "(d) stopped")
	t.near((flat(root.Position) - flat(from)).Magnitude, 20 * 0.5, 2 * 20 * FRAME, "(d) half a second of driving")
	t.eq(Kit.drive(sim, p, goal, 20, { timeout = 0.25 }), false, "(e) timed out")
	t.ok((flat(root.Position) - flat(goal)).Magnitude > 1, "(e) short of the goal")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Prompts through the kit
--------------------------------------------------------------------------------

tests["prompts via the kit: standAt in reach, the local hide (S1/S2), a hold and FirePromptEvent under latency (S3/S8)"] = function(
	t
)
	local LAT = 0.15
	local sim = Kit.boot(t, { latency = LAT })
	local owner = Kit.join(t, sim, 1, "tablet")
	local thief = Kit.join(t, sim, 2, "phone")

	-- Wave 0 creates no StealPrompt (StealService:Init does in Wave 1 A): the helper finds what is there
	local slot = Kit.slot(sim, owner, 1)
	local attachment = slot.Pedestal:FindFirstChild("PromptAttachment")
	t.ok(attachment and attachment:IsA("Attachment"), "Slot_1.Pedestal.PromptAttachment (the StealPrompt's parent)")
	t.eq(Kit.stealPrompt(sim, owner, 1), attachment:FindFirstChild("StealPrompt"), "Kit.stealPrompt")
	t.eq(Kit.stealPrompt(sim, owner, 99), nil, "no such slot → nil")

	-- a StealPrompt-like prompt of the test's own (§4.3 creation values)
	local prompt = sim:Create("ProximityPrompt", {
		Name = "KitPrompt",
		ActionText = StealConfig.Prompt.Action,
		HoldDuration = DefenceConfig.Lock.BaseHold,
		MaxActivationDistance = StealConfig.Prompt.MaxDistance,
		RequiresLineOfSight = false,
		Enabled = true,
	}, attachment)
	local server, client = {}, {}
	local PPS = sim.game:GetService("ProximityPromptService")
	local kinds = {
		PromptButtonHoldBegan = "HoldBegan",
		PromptButtonHoldEnded = "HoldEnded",
		PromptTriggered = "Triggered",
		PromptTriggerEnded = "TriggerEnded",
	}
	for event, kind in kinds do
		PPS[event]:Connect(function(pr, who)
			if pr == prompt then
				table.insert(server, { kind = kind, who = who.Name, time = sim:Time() })
			end
		end)
	end
	sim:Run(function()
		local own =
			{ PromptButtonHoldBegan = "HoldBegan", PromptButtonHoldEnded = "HoldEnded", Triggered = "Triggered" }
		for event, kind in own do
			prompt[event]:Connect(function()
				table.insert(client, { kind = kind, time = sim:Time() })
			end)
		end
	end, thief)
	local function kindsOf(log: { any }): { string }
		local out = {}
		for i, e in log do
			out[i] = e.kind
		end
		return out
	end

	-- Kit.standAt: 2 studs in front of the cabinet, facing it, in reach
	Kit.standAt(sim, thief, prompt)
	local root = thief.Character.HumanoidRootPart
	local at = attachment.WorldPosition
	t.near((flat(root.Position) - flat(at)).Magnitude, 2, 1e-3, "standAt: 2 studs from the attachment")
	t.ok((root.Position - at).Magnitude <= StealConfig.Prompt.MaxDistance, "standAt: inside the prompt's reach")
	t.ok(flat(root.CFrame.LookVector).Unit:Dot((flat(at) - flat(root.Position)).Unit) > 0.99, "standAt: facing it")
	local cabinet = slot.Pedestal
	local inside = cabinet.CFrame:PointToObjectSpace(root.Position)
	t.ok(
		math.abs(inside.X) > cabinet.Size.X / 2 or math.abs(inside.Z) > cabinet.Size.Z / 2,
		"standAt: outside the pedestal (in the aisle)"
	)
	t.ok(sim:CanUsePrompt(thief, prompt), "the thief can hold it")

	-- D14 / BE-14: the client hides it with a local MaxActivationDistance = 0 (S1) …
	sim:Run(function()
		prompt.MaxActivationDistance = 0
	end, thief)
	local ok, why = sim:CanUsePrompt(thief, prompt)
	t.eq(ok, false, "hidden on the thief's client")
	t.match(tostring(why), "out of range")
	t.eq(prompt.MaxActivationDistance, StealConfig.Prompt.MaxDistance, "the server still reads 6")
	-- … and a server Enabled write (false → true) does not undo it (S2: only that key is replaced)
	prompt.Enabled = false
	sim:Advance(FRAME)
	prompt.Enabled = true
	sim:Advance(FRAME)
	ok = sim:CanUsePrompt(thief, prompt)
	t.eq(ok, false, "still hidden through the server's Enabled writes")
	sim:Run(function()
		prompt.MaxActivationDistance = StealConfig.Prompt.MaxDistance
	end, thief)
	t.ok(sim:CanUsePrompt(thief, prompt), "shown again with the config's reach")

	-- a real hold with Kit.boot's latency (S8): the holding client at once, the server one latency later
	local t0 = sim:Time()
	local hold = sim:BeginHold(thief, prompt)
	t.ok(hold.active, "the hold began")
	t.eq(kindsOf(client), { "HoldBegan" }, "the client hears HoldBegan at once")
	t.eq(#server, 0, "the server not yet")
	sim:Advance(LAT + 2 * FRAME)
	t.eq(kindsOf(server), { "HoldBegan" })
	t.near(server[1].time - t0, LAT, 2 * FRAME, "one latency later")
	sim:ReleasePrompt(thief, prompt)
	sim:Advance(LAT + 2 * FRAME)
	t.eq(kindsOf(server), { "HoldBegan", "HoldEnded" }, "released before the hold time: no Triggered")
	t.eq(hold.triggered, false)

	-- FirePromptEvent (S3): from 200 studs, HoldEnded before Triggered — the server only, unchecked, in order
	table.clear(server)
	table.clear(client)
	sim:Teleport(thief, root.Position + Vector3.new(200, 0, 0))
	sim:Advance(FRAME)
	t0 = sim:Time()
	sim:FirePromptEvent(thief, prompt, "HoldBegan")
	sim:FirePromptEvent(thief, prompt, "HoldEnded")
	sim:FirePromptEvent(thief, prompt, "Triggered")
	t.eq(#server, 0, "in flight (latency)")
	sim:Advance(LAT + 2 * FRAME)
	t.eq(kindsOf(server), { "HoldBegan", "HoldEnded", "Triggered" }, "the server gets them in call order")
	for _, e in server do
		t.eq(e.who, thief.Name)
		t.near(e.time - t0, LAT, 2 * FRAME, `{e.kind}: one latency later`)
	end
	t.eq(#client, 0, "the sender's own client hears nothing")
	t.eq(#sim.input.holds, 0, "no sim hold started")

	-- the thief's client ends its own ring with InputHoldEnd (TheftController on Denied / Cancel, §6.4)
	table.clear(server)
	Kit.standAt(sim, thief, prompt)
	hold = sim:BeginHold(thief, prompt)
	t.ok(hold.active, "held again")
	sim:Advance(0.5)
	sim:Run(function()
		prompt:InputHoldEnd()
	end, thief)
	t.eq(hold.active, false, "InputHoldEnd on the client ends the hold")
	t.eq(hold.triggered, false)
	sim:Advance(LAT + 2 * FRAME)
	t.eq(kindsOf(server), { "HoldBegan", "HoldEnded" }, "the server hears the end (one latency later)")

	-- Kit.theftEvents / Kit.defenceEvents: the StealEvent / DefenceEvent logs by kind
	t.eq(Kit.theftEvents(sim, thief), {}, "a prompt StealService does not know gets no StealEvent")
	local remotes = sim.game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
	t.ok(remotes:FindFirstChild("StealEvent") and remotes:FindFirstChild("DefenceEvent"), "both remotes exist")
	remotes.StealEvent:FireClient(owner, "Saved", { Reason = "released", Slot = 1, Text = "", Quiet = true })
	sim:Advance(LAT + 2 * FRAME)
	local saved = Kit.theftEvents(sim, owner, "Saved")
	t.eq(#saved, 1, "Kit.theftEvents(owner, 'Saved')")
	t.eq(saved[1].kind, "Saved")
	t.eq(saved[1].data.Slot, 1)
	t.eq(saved[1].data.Quiet, true)
	t.eq(Kit.theftEvents(sim, owner, "Lost"), {}, "filtered by kind")
	t.eq(#Kit.theftEvents(sim, owner), 1, "every kind")
	t.eq(Kit.defenceEvents(sim, owner), {}, "no DefenceEvent sent")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Saves, points, leaks, restart
--------------------------------------------------------------------------------

tests["Kit.seed, basePoint / exitPoint vs StealRules, sizesZero4 after the leave, Kit.restart"] = function(t)
	local sim = Kit.boot(t)
	local readyAt = Kit.EPOCH + 100
	Kit.seed(sim, 3, {
		tank = { { Id = "Perch", Kg = 1 }, { Id = "Puffer" }, { Id = "SharkPup", Kg = 20, Age = 200 } },
		money = 1234,
		lock = 1,
		upgrades = { Dog = true, Alarm = false, ShieldReadyAt = readyAt },
		saveCount = 0,
		stats = { Stolen = 2 },
	})
	local poked = Kit.peek(sim, 3)
	t.eq(poked.SaveCount, 0, "seed: saveCount")
	t.eq(poked.Stats.Stolen, 2, "seed: a partial stats table merges into the template's")
	t.eq(poked.Stats.Caught, 3, "seed: the template's stats are kept")
	local p = Kit.join(t, sim, 3, "phone")
	local data = Kit.service(sim, "DataService"):Get(p)
	t.ok(data, "loaded")
	t.ok(data.Money >= 1234, `seed: money (1234 + the income since the mount, got {data.Money})`)
	t.eq(data.LockLevel, 1, "seed: lock")
	t.eq(data.Upgrades.Dog, true, "seed: upgrades")
	t.eq(data.Upgrades.Alarm, false)
	t.eq(data.Upgrades.ShieldReadyAt, readyAt)
	t.eq(data.Stats.Stolen, 2, "seed: stats")
	t.eq(data.Stats.Lost, 0, "Stats.Lost reconciled on an old save")
	t.eq(#data.Tank, 3, "seed: three fish")
	for i, id in { "Perch", "Puffer", "SharkPup" } do
		local fish = data.Tank[i]
		t.eq(fish and fish.Id, id, `seed: slot {i}`)
		t.eq(fish and fish.Uid, `f{i}`)
	end
	t.near(data.Tank[3].Kg, 20, 1e-6, "seed: Kg")
	t.ok(data.Tank[3].Age >= 200, "seed: Age kept")
	t.eq(Kit.service(sim, "TankService"):ActiveCount(p), 3, "three active fish in the runtime")
	Kit.ledgerHolds(t, sim, data, "the seeded save")

	-- base-local points: StealRules coordinates
	local base = Kit.baseOf(sim, p)
	local Rules = Kit.shared(sim, "StealRules")
	local pivot = base:GetPivot()
	t.near(Kit.basePoint(base, 0, 0), pivot.Position, 1e-4, "basePoint(0, 0) is the Root")
	t.near(Rules.LocalOf(pivot, Kit.basePoint(base, 6, 58)), Vector3.new(6, 0, 58), 1e-3, "basePoint ↔ LocalOf")
	local margin = StealConfig.Carry.ExitMargin
	local MapConfig = Kit.MapConfig
	local exits = StealConfig.Exits
	local from = {
		gate = Vector3.new(0, 0, MapConfig.PlotFront + 12),
		side = Vector3.new(MapConfig.PlotHalfWidth - 8, 0, (exits.SideFrom + exits.SideTo) / 2),
		west = Vector3.new(-(MapConfig.PlotHalfWidth - 8), 0, (exits.SideFrom + exits.SideTo) / 2),
		back = Vector3.new(exits.ArchX, 0, MapConfig.PlotFront + MapConfig.PlotDepth - 8),
	}
	for kind, inside in from do
		local point = Kit.exitPoint(base, kind)
		local here = Rules.LocalOf(pivot, point)
		t.near(here.Y, Kit.HRP_HEIGHT, 1e-3, `exitPoint {kind}: at the HRP's height`)
		t.eq(Rules.InPlot(here, margin), false, `exitPoint {kind}: past the plot edge + ExitMargin (a credit)`)
		t.eq(Rules.InPlot(here, margin + 2.5), true, `exitPoint {kind}: only just (2 studs past it)`)
		local target = Rules.NearestExit(inside)
		t.near(flat(here - target).Magnitude, 2, 1e-3, `exitPoint {kind}: 2 studs beyond StealRules.NearestExit`)
	end
	t.throws(function()
		Kit.exitPoint(base, "roof")
	end, "unknown exit")

	-- leaks: nothing left of the player once the leave save and its key's pause are over (the stage 3
	-- services and the stage 4 ones; a join a few seconds earlier makes the leave save wait for the gap)
	-- (wave 1: DefenceService remembers the leave for the quick-rejoin protection, a time-bounded map
	-- keyed by UserId — §4.11; it is pruned once DefenceConfig.Shield.QuickRejoin has passed)
	sim:RemovePlayer(p)
	sim:Advance(2 * Kit.GAP + 2, Kit.COARSE)
	t.eq(Kit.service(sim, "DefenceService")._debugSizes().LeftAt, 1, "the quick-rejoin mark kept")
	sim:Advance(DefenceConfig.Shield.QuickRejoin, Kit.COARSE)
	Kit.sizesZero4(t, sim, "after the leave save, the key's pause and the quick-rejoin window")
	local left = Kit.peek(sim, 3)
	t.ok(left.Money >= 1234, "the leave save")
	sim:AssertNoErrors({ warnings = true })

	-- a restart on the same DataStore: the knob off again, the clock moved, the save kept
	local GAP = 30
	local later = Kit.restart(t, sim, GAP)
	t.eq(knob(later), false, "Kit.restart: the knob off on the new server")
	t.near(later:Env().os.time(), Kit.EPOCH + math.floor(sim:Time()) + GAP, 1, "Kit.restart: the clock moved")
	local back = Kit.join(t, later, 3, "phone")
	local again = Kit.service(later, "DataService"):Get(back)
	t.ok(again and again.Money >= left.Money, "the save kept")
	t.eq(again and #again.Tank, 3)
	t.eq(again and again.LockLevel, 1)
	later:AssertNoErrors({ warnings = true })
end

return tests
