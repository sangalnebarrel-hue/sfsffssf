--[[
	Stage 4 wave 0 — the contract (docs/stage4_design.md §7.1, run inside RbxSim against the built
	Place1.rbxl):
	  • StealRules: HoldTime (0..5 and above the max), InPlot / ExitMargin corners, NearestExit
	    (gate, side, back), LocalOf, DogWaypoint (in front of the arcades vs in the court), DogStep
	    (speed, overshoot, leash clamp), DogArrival, ProtectState (all five kinds, the last-ending
	    wins, the tie order), CanStealView, CanPlace, FormatClock (0:42, 6:12), FormatSeconds,
	    DeniedText, NextLock with SaleMax;
	  • TheftChecks: the 17 rows of §4.3 headless over a view struct — the order (every pair), the
	    Client tags, every reason has its text, nil fields pass, Missing, Quiet for a repeat;
	  • CarryGuard: the §4.4 table with dt steps (the budget starts at Start, not full — A2-01;
	    honest 13.6 and 6.8; WalkSpeed 16 under the dog; 2× / 2.5× / 3× hacks caught within a
	    second; 1.2 s and 1.5 s stalls with the catch-up, also at the carry start; a 30-stud hop;
	    a 2 s server tick is not a teleport — A2-05; CanCredit after an overdraft);
	  • DogBrain's pure steps (Sleep → Alert → Chase → bite → Return → Sleep, the Pending throttle),
	    Lib/Speed (the factor stack, Slowed, the expiry, Allowed's history) and Lib/Bucket;
	  • PlayerData §3.1: Stats.Stolen / Lost (template, reconcile, sanitize, serialize), the typed
	    Upgrades keys (bad Dog / Alarm / ShieldReadyAt removed, a newer server's number ≥ 0 and a
	    future key kept), PlayerData.Owned (true or a number > 0), LockLevel 9 kept,
	    the Origin dedupe, an 11-digit UserId + 12-character uid Origin survives (OriginMax 32);
	  • config invariants (lock, prompt reach, carry timeout and speed budget, shield, lamp, dog
	    speed) and the fairness rules of DC-21 (VictimMax, FreshCatch, the dog's arrival to every
	    starting slot inside the base hold, the fail waits, the alert coalescing);
	  • text widths (§6.10): every toast ≤ 300 px at 12 px (two lines for the long tips) with the
	    longest name, fish and price; banner and plate titles fit their boxes at their tier on
	    phone_small; card names fit at the Small tier («СИГНАЛКА» under 120 px);
	  • static S5: every Instance.new("ProximityPrompt") in src sets RequiresLineOfSight = false;
	  • the contract: services and controllers with their API (incl. SetStealProbe, AmendLeaving,
	    SlotChanged, HurryCard, NotifyController.Reserve), the remotes, both boot ORDERs, the
	    replicated state written down in RemoteNames, the probe wired, the home guard, empty
	    _debugSizes;
	  • the server require graph has no cycle (BE-8: DefenceService never requires StealService).
	Pure functions only: one shared sim for the whole file (a server and one phone client for UiFx
	and the controllers); nothing here depends on tests/stage4_kit.luau.

	Run: lune run tools/run_tests.luau stage4_rules
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

-- Pure modules are read straight from src/ (the same values the game uses).
local function loadPure(path: string): any
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = {
			Color3 = roblox.Color3,
			Vector3 = roblox.Vector3,
			Vector2 = roblox.Vector2,
			CFrame = roblox.CFrame,
			Enum = roblox.Enum,
		},
		injectGlobals = true,
	})
	return chunk()
end

local CONFIG = "src/ReplicatedStorage/Shared/Config"
local StealConfig = loadPure(`{CONFIG}/StealConfig.luau`)
local DefenceConfig = loadPure(`{CONFIG}/DefenceConfig.luau`)
local UIConfig = loadPure(`{CONFIG}/UIConfig.luau`)
local MapConfig = loadPure(`{CONFIG}/MapConfig.luau`)
local TankConfig = loadPure(`{CONFIG}/TankConfig.luau`)
local DataConfig = loadPure(`{CONFIG}/DataConfig.luau`)
local FishConfig = loadPure(`{CONFIG}/FishConfig.luau`)
local TextUtil = loadPure("src/ReplicatedStorage/Shared/TextUtil.luau")

local HALF = MapConfig.PlotHalfWidth
local FRONT = MapConfig.PlotFront
local BACK = MapConfig.PlotFront + MapConfig.PlotDepth
local MARGIN = StealConfig.Carry.ExitMargin
local LOCK = DefenceConfig.Lock
local DOG = DefenceConfig.Dog
local WALK = 16 -- StarterPlayer.CharacterWalkSpeed (the Roblox default the place keeps)
local CARRY = WALK * StealConfig.Carry.SpeedFactor -- 13.6
local UNDER_DOG = CARRY * DOG.Slow -- 6.8

-- One sim for the whole file (made by the first test that needs it).
local shared: any = nil
local function env(t: any): any
	if shared then
		return shared
	end
	local sim = t.sim({ place = t.place })
	sim:StartServer()
	sim:Advance(0.5)
	local p = sim:AddPlayer({ UserId = 1, Name = "Rules4", DisplayName = "Правила", device = "phone" })
	sim:Advance(2)
	local function server(path: string): any
		return sim:Require(sim:Find(`ServerScriptService.{path}`))
	end
	local function sharedModule(name: string): any
		return sim:Require(sim:Find(`ReplicatedStorage.Shared.{name}`))
	end
	shared = {
		sim = sim,
		p = p,
		StealRules = sharedModule("StealRules"),
		TheftChecks = sharedModule("TheftChecks"),
		TankRules = sharedModule("TankRules"),
		CarryGuard = server("Lib.CarryGuard"),
		DogBrain = server("Lib.DogBrain"),
		Speed = server("Lib.Speed"),
		Bucket = server("Lib.Bucket"),
		PlayerData = server("Lib.PlayerData"),
		UiFx = sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p),
	}
	return shared
end

local function near(t: any, a: any, b: any, what: string, eps: number?)
	local e = eps or 1e-6
	t.ok((a - b).Magnitude <= e, `{what}: {a} ≈ {b}`)
end

local function hasIssue(issues: { string }, prefix: string): boolean
	for _, issue in issues do
		if string.sub(issue, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local tests = {}

--------------------------------------------------------------------------------
-- StealRules
--------------------------------------------------------------------------------

tests["StealRules: HoldTime, InPlot with ExitMargin, NearestExit, LocalOf"] = function(t)
	local R = env(t).StealRules
	-- HoldTime: 0 / not a number → the base hold; 1..#Levels → that level; above → the best.
	t.eq(R.HoldTime(0), LOCK.BaseHold, "no lock")
	t.eq(R.HoldTime(nil), LOCK.BaseHold, "nil")
	t.eq(R.HoldTime(-1), LOCK.BaseHold, "negative")
	t.eq(R.HoldTime(0 / 0), LOCK.BaseHold, "NaN")
	t.eq(R.HoldTime("3"), LOCK.BaseHold, "a string")
	for level, entry in LOCK.Levels do
		t.eq(R.HoldTime(level), entry.Hold, `level {level}`)
	end
	t.eq(R.HoldTime(2.7), LOCK.Levels[2].Hold, "a fraction floors")
	t.eq(R.HoldTime(#LOCK.Levels + 3), LOCK.Levels[#LOCK.Levels].Hold, "above the max: the best (a newer server)")

	-- InPlot: the plot's corners, then the margin's.
	for _, x in { -HALF, HALF } do
		for _, z in { FRONT, BACK } do
			t.ok(R.InPlot(Vector3.new(x, 0, z), 0), `corner ({x}, {z}) inside`)
			local out = Vector3.new(x + (if x > 0 then 0.01 else -0.01), 0, z)
			t.ok(not R.InPlot(out, 0), `just past ({x}, {z}) outside`)
			t.ok(R.InPlot(out, MARGIN), `… inside with the exit margin`)
			local far = Vector3.new(x + (if x > 0 then MARGIN + 0.01 else -MARGIN - 0.01), 0, z)
			t.ok(not R.InPlot(far, MARGIN), `past the margin at ({x}, {z}) outside`)
		end
	end
	t.ok(R.InPlot(Vector3.new(0, 0, FRONT - MARGIN + 0.01), MARGIN), "the gate's margin inside")
	t.ok(not R.InPlot(Vector3.new(0, 0, FRONT - MARGIN - 0.01), MARGIN), "past the gate's margin outside")
	t.ok(R.InPlot(Vector3.new(0, 0, BACK + MARGIN - 0.01), MARGIN), "the back margin inside")
	t.ok(not R.InPlot(Vector3.new(0, 0, BACK + MARGIN + 0.01), MARGIN), "past the back margin outside")
	t.ok(R.InPlot(Vector3.new(0, 500, 60)), "the height does not matter")

	-- NearestExit: the gate, a side fence (z clamped to Exits.SideFrom..SideTo), a back arch.
	local EX = StealConfig.Exits
	local cases = {
		{ Vector3.new(0, 0, FRONT + 3), Vector3.new(0, 0, FRONT - MARGIN), "gate" },
		{ Vector3.new(10, 3, 22), Vector3.new(0, 0, FRONT - MARGIN), "gate (from the side of the court)" },
		{ Vector3.new(HALF - 3, 0, 80), Vector3.new(HALF + MARGIN, 0, 80), "east fence" },
		{ Vector3.new(-HALF + 3, 0, 70), Vector3.new(-HALF - MARGIN, 0, 70), "west fence" },
		{ Vector3.new(HALF - 1, 0, FRONT + 1), Vector3.new(HALF + MARGIN, 0, EX.SideFrom), "fence, z clamped low" },
		{ Vector3.new(HALF - 4, 0, 140), Vector3.new(HALF + MARGIN, 0, EX.SideTo), "fence, z clamped high" },
		{ Vector3.new(35, 0, BACK - 2), Vector3.new(EX.ArchX, 0, BACK + MARGIN), "east back arch" },
		{ Vector3.new(-38, 0, BACK - 1), Vector3.new(-EX.ArchX, 0, BACK + MARGIN), "west back arch" },
	}
	for _, case in cases do
		local exit = R.NearestExit(case[1])
		near(t, exit, case[2], case[3])
		t.eq(exit.Y, 0, `{case[3]}: on the ground`)
		t.ok(not R.InPlot(exit, 0), `{case[3]}: outside the plot`)
	end

	-- LocalOf: the world point back into the base's frame.
	local pivot = CFrame.new(100, 5, -40) * CFrame.Angles(0, math.rad(90), 0)
	local p = Vector3.new(3, 0, 50)
	near(t, R.LocalOf(pivot, pivot * p), p, "LocalOf inverts the pivot", 1e-4)
end

tests["StealRules: DogWaypoint (arcades vs court), DogStep (speed, overshoot, leash), DogArrival"] = function(t)
	local R = env(t).StealRules
	local W = DOG.Waypoint
	local inAisleEast = Vector3.new((W.Inner + W.Outer) / 2, 3, 80)
	local inAisleWest = Vector3.new(-(W.Inner + W.Outer) / 2, 3, 80)
	local front = Vector3.new(0, 0, W.Front - 10) -- the dog in front of the arcades
	near(t, R.DogWaypoint(front, inAisleEast), Vector3.new(W.X, 0, W.Z), "in front → the east aisle's mouth")
	near(t, R.DogWaypoint(front, inAisleWest), Vector3.new(-W.X, 0, W.Z), "in front → the west aisle's mouth")
	local court = Vector3.new(DOG.Rest.X, 0, DOG.Rest.Z)
	near(t, R.DogWaypoint(court, inAisleEast), Vector3.new(inAisleEast.X, 0, inAisleEast.Z), "from the court: straight")
	local open = Vector3.new(5, 0, 80)
	near(t, R.DogWaypoint(front, open), Vector3.new(5, 0, 80), "the thief in the open court: straight")
	local mouth = Vector3.new(W.X, 0, W.Z - W.Reach / 2)
	near(t, R.DogWaypoint(mouth, inAisleEast), Vector3.new(inAisleEast.X, 0, inAisleEast.Z), "at the mouth: on to him")

	local from = Vector3.new(0, 7, 60)
	near(
		t,
		R.DogStep(from, Vector3.new(0, 0, 100), 0.1, DOG.RunSpeed, DOG.Leash),
		Vector3.new(0, 0, 60 + 2.4),
		"one step at RunSpeed"
	)
	near(t, R.DogStep(from, Vector3.new(0, 0, 61), 0.1, DOG.RunSpeed, DOG.Leash), Vector3.new(0, 0, 61), "no overshoot")
	near(t, R.DogStep(from, Vector3.new(0, 9, 60), 1, DOG.RunSpeed, DOG.Leash), Vector3.new(0, 0, 60), "already there")
	local east = R.DogStep(Vector3.new(HALF + 1, 0, 60), Vector3.new(HALF + 30, 0, 60), 1, DOG.RunSpeed, DOG.Leash)
	t.eq(east.X, HALF + DOG.Leash, "the leash past the east fence")
	local gate = R.DogStep(Vector3.new(0, 0, FRONT), Vector3.new(0, 0, FRONT - 40), 2, DOG.RunSpeed, DOG.Leash)
	t.eq(gate.Z, FRONT - DOG.Leash, "the leash past the gate")
	local back = R.DogStep(Vector3.new(0, 0, BACK), Vector3.new(0, 0, BACK + 40), 2, DOG.RunSpeed, DOG.Leash)
	t.eq(back.Z, BACK + DOG.Leash, "the leash past the back")
	t.eq(R.DogStep(from, Vector3.new(0, 0, 100), -1, DOG.RunSpeed, DOG.Leash).Z, 60, "a negative dt does not move")

	local run = DOG.RunSpeed
	t.near(
		R.DogArrival(Vector3.new(0, 0, 60), Vector3.new(0, 0, 60 + run + DOG.BiteRange)),
		DOG.AlertDelay + 1,
		1e-9,
		"arrival"
	)
	t.eq(R.DogArrival(Vector3.new(0, 0, 60), Vector3.new(0, 0, 62)), DOG.AlertDelay, "already in bite range")
end

tests["StealRules: ProtectState, FormatClock, FormatSeconds, DeniedText, NextLock, CanPlace"] = function(t)
	local R = env(t).StealRules
	local now = 100
	t.eq({ R.ProtectState(now, {}) }, {}, "nothing")
	for _, kind in { "shield", "join", "newbie", "after", "rest" } do
		local kindOf, untilAt = R.ProtectState(now, { [kind] = 160 })
		t.eq(kindOf, kind, `{kind} alone`)
		t.eq(untilAt, 160, `{kind}: until`)
	end
	t.eq({ R.ProtectState(now, { shield = 99, join = 150 }) }, { "join", 150 }, "an ended kind is ignored")
	t.eq({ R.ProtectState(now, { shield = now }) }, {}, "ending now = ended")
	t.eq(
		{ R.ProtectState(now, { shield = 160, join = 190, newbie = 400, after = 130, rest = 250 }) },
		{ "newbie", 400 },
		"the last-ending wins"
	)
	t.eq({ R.ProtectState(now, { join = 200, shield = 200 }) }, { "shield", 200 }, "tie: shield first")
	t.eq({ R.ProtectState(now, { join = 200, newbie = 200, after = 200, rest = 200 }) }, { "rest", 200 }, "tie: rest")
	t.eq({ R.ProtectState(now, { join = 200, newbie = 200, after = 200 }) }, { "after", 200 }, "tie: after")
	t.eq({ R.ProtectState(now, { join = 200, newbie = 200 }) }, { "newbie", 200 }, "tie: newbie before join")
	t.eq({ R.ProtectState(now, { shield = math.huge, join = 0 / 0 }) }, {}, "non-finite ends are ignored")

	for _, case in
		{
			{ 42, "0:42" },
			{ 41.2, "0:42" },
			{ 372, "6:12" },
			{ 60, "1:00" },
			{ 59.5, "1:00" },
			{ 0.2, "0:01" },
			{ 600, "10:00" },
			{ 0, "0:00" },
			{ -5, "0:00" },
			{ 0 / 0, "0:00" },
			{ math.huge, "0:00" },
		}
	do
		t.eq(R.FormatClock(case[1]), case[2], `FormatClock({case[1]})`)
	end
	for _, case in { { 1.8, "1,8" }, { 1.84, "1,8" }, { 1.86, "1,9" }, { 3, "3,0" }, { -1, "0,0" }, { 0 / 0, "0,0" } } do
		t.eq(R.FormatSeconds(case[1]), case[2], `FormatSeconds({case[1]})`)
	end

	t.eq(R.DeniedText("cooldown", 42), TextUtil.fill(StealConfig.Texts.Denied.cooldown, { t = "0:42" }), "{t} filled")
	t.eq(R.DeniedText("far"), StealConfig.Texts.Denied.far, "a text without {t}")
	t.eq(R.DeniedText("bogus", 5), "", "an unknown reason: no text")

	t.eq({ R.NextLock(0, 1) }, { LOCK.Levels[1].Hold, LOCK.Levels[1].Price }, "level 1 for sale")
	t.eq({ R.NextLock(nil, 1) }, { LOCK.Levels[1].Hold, LOCK.Levels[1].Price }, "no level yet")
	t.eq({ R.NextLock(1, 1) }, { nil, "soon" }, "above SaleMax: soon (Stage 5)")
	t.eq({ R.NextLock(0, 0) }, { nil, "soon" }, "SaleMax 0: nothing for sale")
	t.eq({ R.NextLock(2, #LOCK.Levels) }, { LOCK.Levels[3].Hold, LOCK.Levels[3].Price }, "level 3 when sold")
	t.eq({ R.NextLock(#LOCK.Levels, #LOCK.Levels) }, { nil, "max" }, "the best lock: max")
	t.eq({ R.NextLock(9, #LOCK.Levels) }, { nil, "max" }, "above the levels: max")

	local fishA = { Uid = "f1", Income10 = 40, Value = 40, Age = 0 }
	local fishB = { Uid = "f2", Income10 = 90, Value = 90, Age = 0 }
	t.eq(R.CanPlace({}, true, 0), "stored", "a free display")
	t.eq(R.CanPlace({ fishA, fishB }, false, 50), "replaced", "stronger than the weakest")
	t.eq(R.CanPlace({ fishA, fishB }, false, 40), nil, "not stronger: no room")
	local locked = table.clone(fishA)
	locked.Locked = true
	t.eq(R.CanPlace({ locked, fishB }, false, 50), nil, "a fish being stolen / escrowed is never replaced")
end

--------------------------------------------------------------------------------
-- TheftChecks
--------------------------------------------------------------------------------

local ROW_IDS = {
	"prompt",
	"repeat",
	"bucket",
	"self",
	"loading",
	"nobase",
	"busy",
	"far",
	"stealing",
	"wait",
	"protect",
	"taken",
	"owner",
	"few",
	"weak",
	"fish",
	"full",
}
local CLIENT_ROWS = {
	self = true,
	nobase = true,
	stealing = true,
	wait = true,
	protect = true,
	taken = true,
	few = true,
	weak = true,
	fish = true,
	full = true,
}

-- A view every row passes (what the server fills for an allowed start).
local function goodView(): { [string]: any }
	local L = StealConfig.Limits
	return {
		Known = true,
		Repeat = false,
		Bucket = true,
		Own = false,
		ThiefWritable = true,
		ThiefMounted = true,
		VictimReady = true,
		Alive = true,
		Distance = 2,
		Stealing = false,
		CooldownLeft = 0,
		TagLeft = 0,
		ProtectLeft = 0,
		BaseTheft = false,
		OwnerDistance = StealConfig.Tag.Range + 10,
		VictimActive = L.MinFishToRob,
		ThiefIncome10 = 100,
		VictimIncome10 = 100,
		FishMissing = false,
		FishTaken = false,
		FreshLeft = 0,
		Placeable = true,
		Now = 1000,
	}
end

-- One failing change per row (the first is the row's main case; the reason and the {t} seconds).
local function failures(): { [string]: { { change: { [string]: any }, reason: string, left: number? } } }
	local L, P = StealConfig.Limits, StealConfig.Prompt
	return {
		prompt = { { change = { Known = false }, reason = "prompt" } },
		["repeat"] = { { change = { Repeat = true }, reason = "repeat" } },
		bucket = { { change = { Bucket = false }, reason = "bucket" } },
		self = { { change = { Own = true }, reason = "self" } },
		loading = { { change = { ThiefWritable = false }, reason = "loading" } },
		nobase = { { change = { ThiefMounted = false }, reason = "nobase" } },
		busy = { { change = { VictimReady = false }, reason = "busy" } },
		far = {
			{ change = { Distance = P.MaxDistance + P.Slack + 0.01 }, reason = "far" },
			{ change = { Alive = false }, reason = "far" },
			{ change = { Distance = 0 / 0 }, reason = "far" },
		},
		stealing = { { change = { Stealing = true }, reason = "stealing" } },
		wait = {
			{ change = { CooldownLeft = 12 }, reason = "cooldown", left = 12 },
			{ change = { TagLeft = 7 }, reason = "tagged", left = 7 },
			{ change = { CooldownLeft = 12, TagLeft = 7 }, reason = "cooldown", left = 12 },
		},
		protect = {
			{ change = { ProtectLeft = 30, ProtectKind = "shield" }, reason = "shield", left = 30 },
			{ change = { ProtectLeft = 30, ProtectKind = "join" }, reason = "join", left = 30 },
			{ change = { ProtectLeft = 30, ProtectKind = "newbie" }, reason = "newbie", left = 30 },
			{ change = { ProtectLeft = 30, ProtectKind = "after" }, reason = "after", left = 30 },
			{ change = { ProtectLeft = 30, ProtectKind = "rest" }, reason = "rest", left = 30 },
			{ change = { ProtectLeft = 30, ProtectKind = "bogus" }, reason = "shield", left = 30 },
		},
		taken = { { change = { BaseTheft = true }, reason = "taken" } },
		owner = { { change = { OwnerDistance = StealConfig.Tag.Range }, reason = "owner" } },
		few = { { change = { VictimActive = L.MinFishToRob - 1 }, reason = "few" } },
		weak = {
			-- DC-09: a thief at $100/s against a victim at $20/s is refused …
			{ change = { ThiefIncome10 = 1000, VictimIncome10 = 200 }, reason = "weak" },
			{ change = { ThiefIncome10 = L.RichMin * 10, VictimIncome10 = 0 }, reason = "weak" },
		},
		fish = {
			{ change = { FishMissing = true }, reason = "missing" },
			{ change = { FishTaken = true }, reason = "fresh" },
			{ change = { FreshLeft = 20 }, reason = "new", left = 20 },
		},
		full = { { change = { Placeable = false }, reason = "full" } },
	}
end

local function with(view: { [string]: any }, change: { [string]: any }): { [string]: any }
	local copy = table.clone(view)
	for k, v in change do
		copy[k] = v
	end
	return copy
end

tests["TheftChecks: the 17 rows of §4.3 in order, Client tags, texts, every row headless"] = function(t)
	local C = env(t).TheftChecks
	t.eq(#C.Rows, 17, "17 rows")
	for i, id in ROW_IDS do
		local row = C.Rows[i]
		t.eq(row and row.Id, id, `row {i} is {id}`)
		if row then
			t.eq(row.Client, CLIENT_ROWS[id] == true, `{id}: Client tag`)
			for _, reason in row.Reasons do
				if not C.Silent[reason] then
					t.ok(StealConfig.Texts.Denied[reason], `{id}: «{reason}» has a Denied text`)
				end
			end
		end
	end
	t.eq(C.Silent, { prompt = true, ["repeat"] = true, bucket = true, self = true }, "the silent reasons")

	local good = goodView()
	t.eq({ C.Check(good) }, {}, "an allowed start passes every row")
	t.eq(C.Missing(good), {}, "the server view is complete")
	t.eq({ C.Check({}) }, {}, "nil = unknown = pass (the client knows less)")
	local missing = C.Missing({})
	t.eq(#missing, #C.Fields - 1, "Missing lists every field but the optional ProtectKind")

	-- Each row alone, with its reason, its {t} seconds and silence.
	local F = failures()
	for _, id in ROW_IDS do
		for _, case in F[id] do
			local reason, quiet, left = C.Check(with(good, case.change))
			t.eq(reason, case.reason, `{id}: reason`)
			t.eq(quiet, nil, `{id}: not quiet the first time`)
			t.eq(left, case.left, `{id} ({case.reason}): left`)
		end
	end
	-- The boundaries pass.
	local P, L = StealConfig.Prompt, StealConfig.Limits
	t.eq(C.Check(with(good, { Distance = P.MaxDistance + P.Slack })), nil, "far: the exact reach passes")
	t.eq(C.Check(with(good, { OwnerDistance = StealConfig.Tag.Range + 0.01 })), nil, "owner: just out of range")
	t.eq(C.Check(with(good, { VictimActive = L.MinFishToRob })), nil, "few: MinFishToRob passes")
	-- DC-09: … and $40/s is allowed; a thief under RichMin is never «weak».
	t.eq(C.Check(with(good, { ThiefIncome10 = 1000, VictimIncome10 = 400 })), nil, "weak: $100 vs $40 allowed")
	t.eq(C.Check(with(good, { ThiefIncome10 = L.RichMin * 10 - 1, VictimIncome10 = 0 })), nil, "weak: under RichMin")

	-- The order: when two rows fail, the earlier one answers (every pair).
	for i = 1, #ROW_IDS do
		for j = i + 1, #ROW_IDS do
			local a, b = F[ROW_IDS[i]][1], F[ROW_IDS[j]][1]
			local view = with(with(good, b.change), a.change)
			t.eq(C.Check(view), a.reason, `{ROW_IDS[i]} before {ROW_IDS[j]}`)
		end
	end

	-- Client rows only (the button filter): the server-only rows never hide a button.
	local R = env(t).StealRules
	for _, id in ROW_IDS do
		local case = F[id][1]
		local view = with(good, case.change)
		local reason = C.Check(view, true)
		if CLIENT_ROWS[id] then
			t.eq(reason, case.reason, `client filter: {id}`)
			t.eq({ R.CanStealView(view) }, { case.reason, case.left }, `CanStealView: {id}`)
		else
			t.eq(reason, nil, `client filter skips the server row {id}`)
		end
	end

	-- Quiet: the same reason again within DeniedEvery; silent reasons are never "quiet".
	local again = with(good, { CooldownLeft = 5, LastReason = "cooldown", LastAt = 1000, Now = 1001 })
	t.eq({ C.Check(again) }, { "cooldown", true, 5 }, "a repeat within DeniedEvery is quiet")
	local later = with(again, { Now = 1000 + L.DeniedEvery })
	t.eq({ C.Check(later) }, { "cooldown", nil, 5 }, "after DeniedEvery: loud again")
	local other = with(again, { LastReason = "far" })
	t.eq({ C.Check(other) }, { "cooldown", nil, 5 }, "another reason: loud")
	local silent = with(good, { Known = false, LastReason = "prompt", LastAt = 1000, Now = 1000 })
	t.eq({ C.Check(silent) }, { "prompt" }, "a silent reason has no quiet flag")
end

--------------------------------------------------------------------------------
-- CarryGuard (§4.4)
--------------------------------------------------------------------------------

tests["CarryGuard: the §4.4 table — honest carries, the dog cheat, a 2× hack, stalls, a hop, CanCredit"] = function(
	t
)
	local G = env(t).CarryGuard
	local S = StealConfig.Carry.Speed
	local TICK = StealConfig.Tick
	local function cap(allowed: number): number
		return allowed * S.CapSeconds + S.CapSlack
	end
	-- Runs `seconds` of ticks at `speed` studs/s against `allowed`; the first "speed" time or nil.
	local function run(guard: any, seconds: number, speed: number, allowed: number): number?
		local ticks = math.round(seconds / TICK)
		for i = 1, ticks do
			if guard:Step(TICK, speed * TICK, allowed) == "speed" then
				return i * TICK
			end
		end
		return nil
	end

	local honest = G.new(nil, CARRY)
	t.near(honest:Budget(), S.Start, 1e-9, "the budget starts at Start, not full (A2-01)")
	t.ok(S.Start < cap(CARRY), "Start is below the cap")
	t.near(G.new(nil, 0):Budget(), math.min(S.Start, cap(0)), 1e-9, "… and never above the cap")
	t.eq(run(honest, StealConfig.Carry.Timeout, CARRY, CARRY), nil, "an honest carry (13.6) is never caught")
	t.ok(
		honest:Budget() >= cap(CARRY) - CARRY * TICK - 1e-9,
		`… the budget fills up while walking ({honest:Budget()})`
	)
	t.ok(honest:CanCredit(), "… so it can be credited")
	local fresh = G.new(nil, CARRY)
	t.eq(run(fresh, 1, CARRY, CARRY), nil, "an honest first second")
	t.ok(fresh:CanCredit(), "… is creditable at every tick")
	local dog = G.new(nil, UNDER_DOG)
	t.eq(run(dog, StealConfig.Carry.Timeout, UNDER_DOG, UNDER_DOG), nil, "an honest carry under the dog (6.8)")

	-- A client that keeps WalkSpeed 16 under the dog (the bite comes mid-carry, on a full budget):
	-- drains ≈ 8 studs/s → caught in ≈ 2.5 s.
	local cheat = G.new(nil, CARRY)
	t.eq(run(cheat, 10, CARRY, CARRY), nil, "walking until the dog bites")
	local caught = run(cheat, 5, WALK, UNDER_DOG)
	t.ok(caught and caught > 1.5 and caught <= 3, `WalkSpeed 16 under the dog: caught at {caught} s (≤ 3)`)
	-- A speed hack in the carry: caught within a second, long before any fence (the nearest exit
	-- is ≈ 44 studs from a display: tests/stage4_theft drives it on the real place).
	for _, factor in { 2, 2.5, 3 } do
		local hacked = run(G.new(nil, CARRY), 5, factor * CARRY, CARRY)
		t.ok(hacked and hacked <= 1, `a {factor}× hack: caught at {hacked} s`)
		t.ok(hacked and hacked * factor * CARRY < 30, `… after {hacked and hacked * factor * CARRY} studs`)
	end
	-- … also when the hack starts later, on a full budget (≈ 2.5 s, as §4.4 says).
	local late = G.new(nil, CARRY)
	run(late, 10, CARRY, CARRY)
	local lateAt = run(late, 5, 2 * CARRY, CARRY)
	t.ok(lateAt and lateAt <= 3, `a 2× hack after 10 s of walking: caught at {lateAt} s`)
	-- WalkSpeed 16 kept in the carry without the dog: 18 % faster, accepted (Rate 1.15).
	t.eq(run(G.new(nil, CARRY), StealConfig.Carry.Timeout, WALK, CARRY), nil, "×0.85 ignored: accepted")
	-- The first FactorGrace s: the client's WalkSpeed is still 16 (allowed is 16 too).
	t.eq(run(G.new(nil, WALK), S.FactorGrace, WALK, WALK), nil, "WalkSpeed 16 in the grace: ok")

	-- A phone's network stall, then the catch-up in one tick: not caught (under Teleport, in the cap).
	for _, case in { { 1.2, CARRY, 2 }, { 1.5, CARRY, 2 }, { 1.5, UNDER_DOG, 2 }, { 1.5, CARRY, 0 }, { 1.2, WALK, 0 } } do
		local stall, allowed, before = case[1], case[2], case[3]
		local guard = G.new(nil, allowed)
		t.eq(run(guard, before, allowed, allowed), nil, `walking {before} s before the stall`)
		t.eq(run(guard, stall, 0, allowed), nil, "the stall")
		local catchUp = allowed * (stall + TICK)
		t.ok(catchUp < S.Teleport, `the {stall} s catch-up {catchUp} studs is under Teleport`)
		t.eq(
			guard:Step(TICK, catchUp, allowed),
			"ok",
			`a {stall} s stall (after {before} s) + catch-up at {allowed}: ok`
		)
		t.eq(run(guard, 5, allowed, allowed), nil, "… and walking on")
	end

	-- A 30-stud hop in one tick: caught at once.
	local hop = G.new(nil, CARRY)
	t.eq(hop:Step(TICK, 30, CARRY), "speed", "a 30-stud hop")
	t.eq(G.new(nil, CARRY):Step(TICK, 0 / 0, CARRY), "speed", "a NaN displacement")

	-- A server hitch (A2-05): one 2 s tick while an honest thief walked 27 studs — not a teleport;
	-- the jump limit grows only by what an allowed walker covers in the extra time.
	local hitch = G.new(nil, CARRY)
	t.eq(run(hitch, 0.5, CARRY, CARRY), nil, "walking before the hitch")
	t.ok(CARRY * 2 > S.Teleport, "the hitch's displacement is over Teleport")
	t.eq(hitch:Step(2, CARRY * 2, CARRY), "ok", "a 2 s server tick at 13.6: ok")
	t.eq(run(hitch, 5, CARRY, CARRY), nil, "… and walking on")
	local limit = S.Teleport + CARRY * S.Rate * (2 - TICK)
	t.eq(G.new(nil, CARRY):Step(2, limit + 1, CARRY), "speed", `a 2 s tick over {limit} studs: a teleport`)
	t.eq(G.new(nil, CARRY):Step(TICK + 1e-3, 30, CARRY), "speed", "a normal-length tick keeps Teleport")
	t.eq(G.new(nil, CARRY):Step(0 / 0, 1, CARRY), "ok", "a NaN dt refills nothing and is not a jump")

	-- An overdraft inside the debt: not caught, but no credit until the budget is back ≥ 0.
	local over = G.new(nil, CARRY)
	t.eq(run(over, 10, CARRY, CARRY), nil, "walking until the budget is full")
	t.eq(over:Step(TICK, S.Teleport - 1, CARRY), "ok", "a big tick under Teleport")
	t.eq(over:Step(TICK, 6, CARRY), "ok", "another step into the debt")
	t.ok(over:Budget() < 0 and over:Budget() >= -S.Debt, `in the debt ({over:Budget()})`)
	t.ok(not over:CanCredit(), "no credit right after an overdraft (a teleport out is never credited early)")
	t.eq(run(over, 2, CARRY, CARRY), nil, "walking on honestly")
	t.ok(over:CanCredit(), "the budget refills: the exit can be credited again")
end

--------------------------------------------------------------------------------
-- DogBrain, Lib/Speed, Lib/Bucket
--------------------------------------------------------------------------------

tests["DogBrain: pure steps — Sleep → Alert → Chase → bite → Return → Sleep; the Pending throttle"] = function(
	t
)
	local s = env(t)
	local B = s.DogBrain
	local rest = B.Rest()
	near(t, rest, Vector3.new(DOG.Rest.X, 0, DOG.Rest.Z), "Rest = DefenceConfig.Dog.Rest")
	local brain = B.New()
	t.eq(brain.State, "Sleep", "a new dog sleeps")
	near(t, brain.Pos, rest, "… at its rest spot")
	local thief = Vector3.new(30, 3, 80)
	t.eq(B.Advance(brain, 1, thief), false, "a sleeping dog never bites")
	near(t, brain.Pos, rest, "… nor moves")
	B.WakeBrain(brain, 42)
	t.eq(brain.State, "Alert", "a theft wakes it («ГАВ!»)")
	t.eq(brain.Target, 42)
	B.Advance(brain, DOG.AlertDelay / 2, thief)
	t.eq(brain.State, "Alert", "barking for AlertDelay")
	near(t, brain.Pos, rest, "… in place")
	local bit = false
	for _ = 1, 100 do
		if B.Advance(brain, 0.1, thief) then
			bit = true
			break
		end
	end
	t.eq(brain.State, "Chase", "then the chase")
	t.ok(bit, "it reaches the thief and bites")
	t.ok(
		(Vector3.new(brain.Pos.X, 0, brain.Pos.Z) - Vector3.new(thief.X, 0, thief.Z)).Magnitude <= DOG.BiteRange + 1e-6,
		"within BiteRange"
	)
	B.ReturnBrain(brain)
	t.eq(brain.State, "Return", "the theft ended: home")
	t.eq(B.Advance(brain, 0.1, thief), false, "a returning dog never bites")
	for _ = 1, 200 do
		B.Advance(brain, 0.1, nil)
		if brain.State == "Sleep" then
			break
		end
	end
	t.eq(brain.State, "Sleep", "asleep again")
	near(t, brain.Pos, rest, "… at the rest spot")

	-- Pending: the state at once, the position at most every Replicate s and only after a move.
	local fresh = B.New()
	local first = B.Pending(fresh, 10)
	t.eq(first.DogState, "Sleep", "the first write: the state")
	t.ok(first.DogPos ~= nil, "… and the position")
	B.Mark(fresh, first, 10)
	t.eq(B.Pending(fresh, 10.05), {}, "nothing new")
	t.eq(B.Pending(fresh, 10 + DOG.Replicate + 0.01), {}, "nothing new after Replicate either (no move)")
	B.WakeBrain(fresh, 7)
	local woke = B.Pending(fresh, 10.06)
	t.eq(woke.DogState, "Alert", "a state change is written at once")
	t.eq(woke.DogTarget, 7, "… with the target")
	t.eq(woke.DogPos, nil, "… the position waits for Replicate")
	B.Mark(fresh, woke, 10.06)
	B.Advance(fresh, DOG.AlertDelay, thief)
	B.Advance(fresh, DOG.MoveEpsilon / DOG.RunSpeed / 2, thief) -- a tiny move (under MoveEpsilon)
	local tiny = B.Pending(fresh, 10 + DOG.Replicate + 0.02)
	t.eq(tiny.DogState, "Chase", "the chase is written at once")
	t.eq(tiny.DogPos, nil, "a move under MoveEpsilon is not written")
	B.Mark(fresh, tiny, 10 + DOG.Replicate + 0.02)
	B.Advance(fresh, 0.5, thief)
	t.ok(B.Pending(fresh, 10 + DOG.Replicate + 0.03).DogPos ~= nil, "a real move after Replicate is written")
	local moved = B.Pending(fresh, 10 + DOG.Replicate + 0.03)
	B.Mark(fresh, moved, 10 + DOG.Replicate + 0.03)
	B.Advance(fresh, 0.5, thief)
	t.eq(B.Pending(fresh, 10 + DOG.Replicate + 0.05).DogPos, nil, "not again before Replicate")
	B.ReturnBrain(fresh)
	t.eq(B.Pending(fresh, 10 + DOG.Replicate + 0.06).DogTarget, false, "the target cleared (false = remove)")
	t.eq(B.AnyAwake(), false, "no base dog woken (the brains above are pure)")
	t.eq(B._debugSizes(), { Brains = 0 }, "no brains kept")
end

tests["Lib/Speed: the factor stack, MinFactor, Slowed on the Dog key, the expiry, Allowed; Lib/Bucket"] = function(t)
	local s = env(t)
	local sim, p, Speed, Bucket = s.sim, s.p, s.Speed, s.Bucket
	local humanoid = p.Character:FindFirstChildOfClass("Humanoid")
	local function clock(): number
		return sim:Env().os.clock() -- (the sim's virtual clock: Lib/Speed's os.clock)
	end
	t.eq(humanoid.WalkSpeed, WALK, "the default walk")
	Speed.Set(p, "Carry", StealConfig.Carry.SpeedFactor)
	t.near(humanoid.WalkSpeed, CARRY, 1e-6, "carry: 13.6")
	t.eq(p:GetAttribute("Slowed"), nil, "Slowed only for the Dog key")
	t.near(Speed.Allowed(p, 0.5), WALK, 1e-6, "Allowed: the 16 of a moment ago still counts")
	sim:Advance(0.6)
	t.near(Speed.Allowed(p, 0.5), CARRY, 1e-6, "… and 0.5 s later only the carry")
	Speed.Set(p, "Dog", DOG.Slow, clock() + 1)
	t.near(humanoid.WalkSpeed, UNDER_DOG, 1e-6, "carry under the dog: 6.8")
	t.eq(p:GetAttribute("Slowed"), true, "Slowed")
	t.near(Speed.Allowed(p, 0.5), CARRY, 1e-6, "Allowed keeps the higher factor of the last 0.5 s")
	sim:Advance(1.2)
	t.near(humanoid.WalkSpeed, CARRY, 1e-6, "the Dog key expired by itself")
	t.eq(p:GetAttribute("Slowed"), nil, "Slowed cleared with it")
	Speed.Set(p, "Dog", 0.1)
	t.near(humanoid.WalkSpeed, WALK * StealConfig.Speed.MinFactor, 1e-6, "never under MinFactor")
	Speed.ClearAll(p)
	t.eq(humanoid.WalkSpeed, WALK, "ClearAll: 16")
	t.eq(p:GetAttribute("Slowed"), nil)
	sim:Advance(StealConfig.Speed.History + 0.1)
	t.eq(Speed.Factor(p), 1)
	for key, size in Speed._debugSizes() do
		t.eq(size, 0, `Speed._debugSizes().{key} after ClearAll`)
	end

	local bucket = Bucket.new(2, 1)
	t.ok(bucket:Take(p) and bucket:Take(p), "the burst")
	t.ok(not bucket:Take(p), "then empty")
	sim:Advance(1.05)
	t.ok(bucket:Take(p), "one token a second")
	t.eq(bucket:Size(), 1, "one player in it")
	bucket:Forget(p)
	t.eq(bucket:Size(), 0, "Forget")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- PlayerData (§3.1)
--------------------------------------------------------------------------------

local function fish(uid: string, id: string, slot: number, extra: { [string]: any }?): { [string]: any }
	local f: { [string]: any } = { Uid = uid, Id = id, Kg = 1.2, Age = 0, Slot = slot, CaughtAt = 1700000000 }
	for key, value in extra or {} do
		f[key] = value
	end
	return f
end

tests["PlayerData: Stats.Stolen / Lost, typed Upgrades keys, LockLevel 9, Origin dedupe and OriginMax"] = function(t)
	local D = env(t).PlayerData
	local function clean(data: any): (any, { string })
		return D.Sanitize(D.Migrate(D.Reconcile(data)))
	end
	local template = D.Template()
	t.eq(template.Stats.Stolen, 0, "template Stolen")
	t.eq(template.Stats.Lost, 0, "template Lost")
	local old = D.Reconcile({ Stats = { Caught = 3, Sold = 1, Earned = 0, Spent = 0, Species = {} } })
	t.eq(old.Stats.Stolen, 0, "an old save gets Stolen 0")
	t.eq(old.Stats.Lost, 0, "… and Lost 0")
	t.eq(old.Stats.Caught, 3, "… its own stats kept")
	local stats = clean({ Stats = { Stolen = 2.7, Lost = -4 } }).Stats
	t.eq(stats.Stolen, 2, "Stolen floored")
	t.eq(stats.Lost, 0, "Lost ≥ 0")

	-- Upgrades: Dog / Alarm — a boolean (or a newer server's number ≥ 0); ShieldReadyAt — a whole
	-- os.time ≥ 0; any other key kept verbatim.
	local good, goodIssues = clean({
		Upgrades = { Dog = true, Alarm = 2, ShieldReadyAt = 1700000123, Future = { Level = 3 } },
	})
	t.eq(good.Upgrades, { Dog = true, Alarm = 2, ShieldReadyAt = 1700000123, Future = { Level = 3 } }, "good keys kept")
	t.eq(goodIssues, {}, "no issues")
	local frac, fracIssues = clean({ Upgrades = { ShieldReadyAt = 1700000123.6 } })
	t.eq(frac.Upgrades.ShieldReadyAt, 1700000123, "ShieldReadyAt: a whole os.time")
	t.ok(hasIssue(fracIssues, "Upgrades.ShieldReadyAt"), "… floored with an issue")
	local bad, badIssues = clean({ Upgrades = { Dog = "yes", Alarm = { 1 }, ShieldReadyAt = 0 / 0, Shop = "kept" } })
	t.eq(bad.Upgrades, { Shop = "kept" }, "bad Dog / Alarm / ShieldReadyAt removed, a future key kept")
	for _, key in { "Dog", "Alarm", "ShieldReadyAt" } do
		t.ok(hasIssue(badIssues, `Upgrades.{key}`), `an issue for Upgrades.{key}`)
	end
	t.eq(clean({ Upgrades = { Dog = -1 } }).Upgrades, {}, "a negative Dog removed")
	-- Owned: the one ownership predicate (§3.1, §4.12; W0-02) — a newer server's level counts.
	for _, case in
		{
			{ true, true, "true" },
			{ 2, true, "a newer server's level 2" },
			{ 0.5, true, "any number > 0" },
			{ false, false, "false" },
			{ 0, false, "level 0" },
			{ -1, false, "a negative number" },
			{ 0 / 0, false, "NaN" },
			{ nil, false, "missing" },
			{ "yes", false, "a string" },
			{ { 1 }, false, "a table" },
		}
	do
		t.eq(D.Owned(case[1]), case[2], `Owned: {case[3]}`)
	end
	t.eq(clean({ Upgrades = { ShieldReadyAt = -50 } }).Upgrades.ShieldReadyAt, 0, "ShieldReadyAt ≥ 0")
	local saved, saveIssues = D.Serialize(clean({ Upgrades = { Dog = true, Future = { Level = 3 } } }))
	t.eq(saved.Upgrades, { Dog = true, Future = { Level = 3 } }, "Serialize keeps the upgrades")
	t.eq(saveIssues, {}, "… cleanly")
	local raw = clean({})
	raw.Upgrades.Dog = "corrupted at runtime"
	local out, outIssues = D.Serialize(raw)
	t.eq(out.Upgrades.Dog, nil, "Serialize drops a typed key with a wrong type")
	t.ok(hasIssue(outIssues, "Upgrades.Dog"), "… with an issue")

	t.eq(clean({ LockLevel = 9 }).LockLevel, 9, "LockLevel 9 (a newer server's level) kept verbatim")

	-- Origin: the first fish with an Origin stays, a second one with the same Origin is a dupe.
	local data, issues = clean({
		Tank = {
			fish("f1", "Perch", 1, { Origin = "123:f9" }),
			fish("f2", "Crucian", 2, { Origin = "123:f9" }),
			fish("f3", "Perch", 3, { Origin = "456:f1" }),
		},
		NextUid = 4,
	})
	local uids = {}
	for _, f in data.Tank do
		table.insert(uids, f.Uid)
	end
	table.sort(uids)
	t.eq(uids, { "f1", "f3" }, "the duplicate Origin dropped, the first kept")
	t.ok(
		hasIssue(issues, "Tank[2].Origin") or hasIssue(issues, "Tank"),
		`an issue for the dupe ({table.concat(issues, "; ")})`
	)

	-- OriginMax 32: an 11-digit UserId and a 12-character uid survive; 33 characters do not.
	local long = "12345678901:" .. "f12345678901"
	t.ok(#long <= DataConfig.Limits.OriginMax, `the longest real Origin ({#long}) ≤ OriginMax`)
	t.eq(DataConfig.Limits.OriginMax, 32, "OriginMax 32")
	local keep = clean({ Tank = { fish("f1", "Perch", 1, { Origin = long }) }, NextUid = 2 })
	local kept = D.Serialize(keep)
	t.eq(kept.Tank[1].Origin, long, "a 24-character Origin survives Serialize")
	local tooLong = string.rep("9", DataConfig.Limits.OriginMax + 1)
	local cut = clean({ Tank = { fish("f1", "Perch", 1, { Origin = tooLong }) }, NextUid = 2 })
	local dropped, droppedIssues = D.Serialize(cut)
	t.eq(dropped.Tank[1].Origin, nil, "an Origin over OriginMax is dropped")
	t.ok(hasIssue(droppedIssues, "Tank[1].Origin"), "… with an issue")
	-- Serialize: a missing new stat is 0 without an issue (old records in memory).
	local noStats = clean({})
	noStats.Stats.Stolen = nil
	local s2, s2Issues = D.Serialize(noStats)
	t.eq(s2.Stats.Stolen, 0, "Serialize: a missing Stolen → 0")
	t.eq(s2Issues, {}, "… without an issue")
end

--------------------------------------------------------------------------------
-- Config invariants and fairness (DC-21)
--------------------------------------------------------------------------------

tests["config invariants: lock, prompt reach, carry timeout and speed budget, shield, lamp, dog speed"] = function(t)
	local R = env(t).StealRules
	-- The lock.
	local lastHold, lastPrice = LOCK.BaseHold, 0
	for i, level in LOCK.Levels do
		t.ok(level.Hold > lastHold, `lock {i}: the hold grows ({level.Hold})`)
		t.ok(level.Price > lastPrice, `lock {i}: the price grows ({level.Price})`)
		t.ok(level.Hold <= 10, `lock {i}: Hold ≤ 10`)
		lastHold, lastPrice = level.Hold, level.Price
	end
	t.ok(LOCK.SaleMax >= 1 and LOCK.SaleMax <= #LOCK.Levels, "1 ≤ SaleMax ≤ #Levels")
	-- The prompt: under the back-wall reach, and two displays' midpoint (5.5 studs) both in range.
	local P = StealConfig.Prompt
	t.ok(P.MaxDistance + P.Slack < 10, "MaxDistance + Slack < 10 (the back-wall reach)")
	t.ok(P.MaxDistance <= 6, "MaxDistance ≤ 6")
	t.ok(StealConfig.Hold.Tolerance < P.Slack, "the hold tolerance under the slack")
	-- The carry timeout covers the longest exit under the dog.
	local longest = 0
	for x = -HALF, HALF, 2 do
		for z = FRONT, BACK, 2 do
			local p = Vector3.new(x, 0, z)
			local e = R.NearestExit(p)
			longest = math.max(longest, (Vector3.new(e.X, 0, e.Z) - p).Magnitude)
		end
	end
	t.ok(
		StealConfig.Carry.Timeout > longest / UNDER_DOG,
		`Carry.Timeout {StealConfig.Carry.Timeout} > the longest exit {math.floor(longest)} / {UNDER_DOG}`
	)
	-- The speed budget (§4.4).
	local S = StealConfig.Carry.Speed
	t.ok(S.Rate * UNDER_DOG < WALK - 1, "a WalkSpeed 16 cheat under the dog drains the budget")
	t.ok(CARRY * 1.5 < S.Teleport, "a 1.5 s stall's catch-up is no teleport")
	t.ok(S.Teleport < S.CapSeconds * CARRY + S.CapSlack, "a teleport is more than the cap")
	-- The shield and the free protections.
	local SH = DefenceConfig.Shield
	t.ok(SH.Duration < SH.Cooldown, "Shield.Duration < Cooldown")
	t.ok(SH.StackBelow <= SH.Duration, "StackBelow ≤ Duration")
	t.ok(SH.JoinProtectFirst >= SH.JoinProtect and SH.JoinProtect > SH.QuickRejoinProtect, "join protections")
	t.ok(SH.EndingWarn < SH.JoinProtect, "the ending warning fits in the join protection")
	t.eq(SH.Price, 0, "the shield is free")
	-- The lamp at most 3 Hz (photosensitivity), the dog faster than a carrier.
	t.ok(DefenceConfig.World.LampPeriod >= 1 / 3, "LampPeriod ≥ 1/3 s")
	t.ok(DOG.RunSpeed > CARRY, "the dog outruns a carrier")
	t.ok(DOG.HomeSpeed < DOG.RunSpeed, "home at a trot")
	t.ok(StealConfig.Speed.MinFactor <= StealConfig.Carry.SpeedFactor * DOG.Slow, "MinFactor under carry × dog")
	-- The Studio knob: a number (the kit switches it off).
	t.eq(DefenceConfig.Debug.StudioProtect, 10, "Debug.StudioProtect = 10 (on its own line: tests patch it)")
	t.ok(
		string.find(fs.readFile(`{CONFIG}/DefenceConfig.luau`), "\n\t\tStudioProtect = 10,", 1, true),
		"the StudioProtect line the kit patches"
	)
	-- Every Stage 4 remote and text table is there.
	for _, key in { "Prompt", "Hold", "Carry", "Tag", "Exits", "Limits", "Alarm", "Speed", "Texts" } do
		t.ok(StealConfig[key], `StealConfig.{key}`)
	end
	for _, key in { "Shield", "Dog", "Alarm", "Lock", "Requests", "World", "Panel", "Debug", "Texts" } do
		t.ok(DefenceConfig[key], `DefenceConfig.{key}`)
	end
	t.eq(MapConfig.PartBudget.RuntimeReserve.Theft, 60, "PartBudget.RuntimeReserve.Theft")
	for _, kind in { "theft", "saved", "shield" } do
		t.ok(UIConfig.ToastKinds[kind], `UIConfig.ToastKinds.{kind}`)
	end
	t.ok(UIConfig.Palette.Guard, "UIConfig.Palette.Guard")
	t.ok(UIConfig.Theft.ShieldMin >= 56 and UIConfig.Theft.HomeMin >= 44, "the alert's target sizes")
	t.ok(TankConfig.Texts.Denied.locked and TankConfig.Texts.Denied.escrow, "TankConfig Denied locked / escrow")
end

tests["fairness (DC-21): VictimMax, FreshCatch, the dog inside the base hold, fail waits, alert coalescing"] = function(
	t
)
	local s = env(t)
	local R, sim = s.StealRules, s.sim
	local L = StealConfig.Limits
	t.ok(L.VictimMax <= 3, "VictimMax ≤ 3")
	local longestCard = 0
	for _, seconds in UIConfig.CatchCardTime do
		longestCard = math.max(longestCard, seconds)
	end
	t.ok(L.FreshCatch >= longestCard + 1, `FreshCatch {L.FreshCatch} ≥ the longest catch card {longestCard} + 1`)
	for i = 2, #L.FailCooldown do
		t.ok(L.FailCooldown[i] > L.FailCooldown[i - 1], `FailCooldown[{i}] grows`)
	end
	t.ok(L.TagCooldown > L.FailCooldown[1], "TagCooldown > FailCooldown[1]")
	t.ok(
		L.AlertCoalesce >= 2 * (LOCK.BaseHold + L.FailCooldown[1]),
		"AlertCoalesce ≥ 2 × (BaseHold + FailCooldown[1])"
	)
	t.ok(L.VictimImmunity >= L.ThiefCooldown, "the victim's rest outlasts the thief's wait")

	-- The dog from its rest spot reaches a thief at any display unlocked at the start before the
	-- base hold ends (the prompt's point: the thief stands within MaxDistance of it).
	local base = sim.workspace.Bases:FindFirstChild("Base_1")
	local pivot = base:GetPivot()
	local rest = Vector3.new(DOG.Rest.X, 0, DOG.Rest.Z)
	local function flat(a: any, b: any): number
		return (Vector3.new(a.X, 0, a.Z) - Vector3.new(b.X, 0, b.Z)).Magnitude
	end
	local worst = 0
	for i = 1, TankConfig.StartSlots do
		local slot = base.Tank.Slots:FindFirstChild(`Slot_{i}`)
		local att = slot.Pedestal.PromptAttachment
		local world = (slot.Pedestal.CFrame * att.CFrame).Position
		local here = R.LocalOf(pivot, world)
		-- (straight to him, or through an aisle's mouth when the dog starts in front of the arcades)
		local via = R.DogWaypoint(rest, here)
		local run = flat(rest, via) + flat(via, here)
		local arrival = DOG.AlertDelay + math.max(0, run - DOG.BiteRange) / DOG.RunSpeed
		worst = math.max(worst, arrival)
		t.ok(
			arrival < LOCK.BaseHold,
			`Slot_{i} at ({math.floor(here.X)}, {math.floor(here.Z)}): the dog in {arrival} s < {LOCK.BaseHold}`
		)
	end
	t.ok(worst > 0, `the slowest arrival {worst} s`)
end

--------------------------------------------------------------------------------
-- Text widths (§6.10)
--------------------------------------------------------------------------------

-- The longest names the strings can carry: a 20-character display name (the Roblox maximum),
-- the widest short fish name, the dearest defence price.
local LONGEST_NAME = "Ж" .. string.rep("ж", 19)

local function shortNames(): { string }
	local list = {}
	for _, def in FishConfig.Fish do
		table.insert(list, def.ShortName)
	end
	return list
end

tests["text widths: toasts ≤ 300 px at 12 px with the longest name, fish and price"] = function(t)
	local s = env(t)
	local UiFx, TankRules = s.UiFx, s.TankRules
	local ST, DT = StealConfig.Texts, DefenceConfig.Texts
	local widest, widestW = "", 0
	for _, name in shortNames() do
		local w = UiFx.textWidth(name, 12)
		if w > widestW then
			widest, widestW = name, w
		end
	end
	local clock = "10:00"
	local price = TankRules.FormatMoney(DOG.Price)
	local oneLine = {
		TextUtil.fill(ST.Result.Lost, { short = widest, name = LONGEST_NAME }),
		TextUtil.fill(ST.Result.LostSub, { t = clock }),
		ST.Result.Void,
		TextUtil.fill(ST.Result.LeftSold, { price = TankRules.FormatMoney(99999) }),
		TextUtil.fill(ST.Intruder, { name = LONGEST_NAME }),
		ST.HomeGuard,
		TextUtil.fill(DT.Shield.On, { t = clock }),
		DT.Shield.Off,
		DT.Shield.Ready,
		TextUtil.fill(DT.Protect.newbie, { t = clock }),
		TextUtil.fill(DT.Protect.join, { t = clock }),
	}
	for _, text in ST.Result.Saved do
		table.insert(oneLine, text)
	end
	for _, text in DT.Denied do
		table.insert(oneLine, TextUtil.fill(text, { t = clock, price = price }))
	end
	for item, text in DT.Bought do
		table.insert(oneLine, TextUtil.fill(text, { s = TextUtil.fill("{s}", { s = LOCK.Levels[1].Hold }) }))
		t.ok(item == "Dog" or item == "Alarm" or item == "Lock", `Bought.{item}`)
	end
	-- Two-line toasts (NotifyController makes a long toast taller): the tips and the ending
	-- warning; each word still fits a line.
	local twoLines = { DT.Protect.Ending }
	for key, text in DT.Tips do
		local cost = if key == "Lock"
			then LOCK.Levels[1].Price
			elseif key == "Alarm" then DefenceConfig.Alarm.Price
			else DOG.Price
		table.insert(twoLines, TextUtil.fill(text, { price = TankRules.FormatMoney(cost) }))
	end
	for _, text in oneLine do
		t.ok(not string.find(text, "{", 1, true), `«{text}»: every field filled`)
		local w = UiFx.textWidth(text, 12)
		t.ok(w <= 300, `«{text}»: {math.floor(w)} px ≤ 300 at 12 px`)
	end
	for _, text in twoLines do
		t.ok(not string.find(text, "{", 1, true), `«{text}»: every field filled`)
		local w = UiFx.textWidth(text, 12)
		t.ok(w <= 2 * 300 - 40, `«{text}»: {math.floor(w)} px fits two toast lines at 12 px`)
	end
	-- The thief's banner lines (hints, Denied, Cancel): two lines of the banner's Sub box on
	-- phone_small at the minimum 12 px.
	local plate = math.min(UIConfig.Theft.Width * 667, UIConfig.Theft.WidthMax, 0.56 * 667)
	local subBox = 0.88 * plate
	local banner = { ST.Banner.NoReply, ST.Banner.HoldSub, ST.Banner.CarrySub }
	for _, text in ST.Hint do
		table.insert(banner, text)
	end
	for _, text in ST.Cancel do
		table.insert(banner, text)
	end
	for _, text in ST.Denied do
		table.insert(banner, TextUtil.fill(text, { t = clock }))
	end
	for _, text in banner do
		local w = UiFx.textWidth(text, 12)
		t.ok(w <= 2 * subBox, `banner «{text}»: {math.floor(w)} px in two lines of {math.floor(subBox)} px`)
	end
end

-- A label's box in px inside a root of the given size: the product of the Size scales up to the root.
local function boxOf(label: any, root: any, size: any): any
	local sx, sy = 1, 1
	local node = label
	while node and node ~= root do
		sx *= node.Size.X.Scale
		sy *= node.Size.Y.Scale
		node = node.Parent
	end
	return Vector2.new(size.X * sx, size.Y * sy)
end

tests["text widths: banner and plate titles at their tier on phone_small, card names at Small"] = function(t)
	local s = env(t)
	local UiFx, sim = s.UiFx, s.sim
	local hud = sim:Find("StarterGui.HUD")
	local ST, DT = StealConfig.Texts, DefenceConfig.Texts
	local function fits(text: string, label: any, root: any, size: any, what: string, minPx: number?)
		local tier = label:GetAttribute("TextTier")
		local px = minPx or (if tier then UIConfig.Type[tier] else 12)
		local box = boxOf(label, root, size)
		local w = UiFx.textWidth(text, px)
		t.ok(w <= box.X, `{what} «{text}»: {math.floor(w)} px at {px} px fits {math.floor(box.X)} px`)
		t.ok(box.Y >= px, `{what}: the box is {math.floor(box.Y)} px tall for {px} px`)
	end
	-- phone_small: 667 × 375, the HUD 317 px under the top bar; the plates stay inside the toast
	-- column (0.56 of the width) and under Theft.Width / WidthMax.
	local W, H = 667, 375 - 58
	local plateW = math.min(UIConfig.Theft.Width * W, UIConfig.Theft.WidthMax, 0.56 * W)
	local barSize = Vector2.new(plateW, UIConfig.Theft.BarHeight * H)
	local alertSize = Vector2.new(plateW, math.max(0.22 * H, UIConfig.Theft.PlateHeight))
	local bar, alert = hud.TheftBar, hud.TheftAlert
	for _, name in shortNames() do
		local short = TextUtil.upper(name)
		fits(TextUtil.fill(ST.Banner.Hold, { short = short }), bar.Title, bar, barSize, "banner hold")
		fits(TextUtil.fill(ST.Alert.Compact, { short = short }), alert.Compact.Label, alert, alertSize, "compact")
	end
	fits(ST.Banner.Carry, bar.Title, bar, barSize, "banner carry")
	fits(ST.Banner.HoldSub, bar.Sub, bar, barSize, "banner sub")
	fits(ST.Banner.CarrySub, bar.Sub, bar, barSize, "banner carry sub")
	fits(TextUtil.fill(ST.Banner.Time, { s = "10,0" }), bar.Time, bar, barSize, "banner time")
	fits(ST.Alert.Hold, alert.Text.Title, alert, alertSize, "alert hold")
	fits(ST.Alert.Carry, alert.Text.Title, alert, alertSize, "alert carry")
	fits(ST.Alert.Shield, alert.Buttons.Shield.Caption, alert, alertSize, "ЩИТ")
	fits(
		TextUtil.fill(ST.Alert.ShieldWait, { t = "2:59" }),
		alert.Buttons.Shield.Caption,
		alert,
		alertSize,
		"ЩИТ wait"
	)
	fits(ST.Alert.Home, alert.Buttons.Home.Caption, alert, alertSize, "ДОМОЙ (≥ 12 px)", 12)
	-- The «ЗАЩИТА» sheet's cards (phone ≈ 117 × 150; CardMin 96 at the Aspect): the names at the
	-- Small tier — «СИГНАЛИЗАЦИЯ» from 120 px, «СИГНАЛКА» below.
	local cards = hud.DefencePanel.Panel.Cards
	local aspect = DefenceConfig.Panel.CardAspect
	local wide = Vector2.new(120, 120 / aspect)
	local small = Vector2.new(DefenceConfig.Panel.CardMin, DefenceConfig.Panel.CardMin / aspect)
	for card, key in { ShieldCard = "Shield", DogCard = "Dog", AlarmCard = "Alarm", LockCard = "Lock" } do
		local root = cards[card]
		local texts = DT.Cards[key]
		local name = root:FindFirstChild("Name") -- (root.Name is the Instance's own name)
		fits(texts.Name, name, root, wide, `{card} at 120 px`)
		fits(texts.Short or texts.Name, name, root, small, `{card} at CardMin`)
		fits(
			TextUtil.fill(DT.Buy.Price, { price = s.TankRules.FormatMoney(DOG.Price) }),
			root.Buy.Price,
			root,
			small,
			`{card} price`
		)
	end
	fits(DT.Buy.On, cards.ShieldCard.Buy.Label, cards.ShieldCard, small, "ВКЛЮЧИТЬ")
	fits(DT.Buy.Confirm, cards.DogCard.Buy.Label, cards.DogCard, small, "КУПИТЬ?")
	fits(DT.Buy.Bought, cards.DogCard.Buy.Label, cards.DogCard, small, "КУПЛЕНО")
	-- The column button and the shield chip (≤ ChipMax px).
	t.ok(
		UiFx.textWidth(TextUtil.fill(DT.Chip, { t = "10:00" }), 14) + 36 <= UIConfig.Theft.ChipMax,
		"«🛡️ 10:00» in the chip"
	)
	t.ok(UiFx.textWidth(DT.ButtonAlert, 12) <= 56, "«ЩИТ!» on the column button")
end

--------------------------------------------------------------------------------
-- Static S5, the contract, the require graph
--------------------------------------------------------------------------------

local function sourcesUnder(dir: string, out: { { path: string, text: string } })
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			sourcesUnder(path, out)
		elseif string.match(name, "%.luau$") or string.match(name, "%.lua$") then
			table.insert(out, { path = path, text = fs.readFile(path) })
		end
	end
end

tests["static S5: every ProximityPrompt made in src sets RequiresLineOfSight = false"] = function(t)
	local files = {}
	sourcesUnder("src", files)
	local found = 0
	for _, file in files do
		local lines = string.split(file.text, "\n")
		for i, line in lines do
			if string.find(line, 'Instance.new("ProximityPrompt"', 1, true) then
				found += 1
				local var = string.match(line, "local%s+([%w_]+)%s*=%s*Instance%.new%(")
					or string.match(line, "([%w_%.]+)%s*=%s*Instance%.new%(")
				t.ok(var, `{file.path}:{i}: the prompt is kept in a variable`)
				local set = false
				for j = i + 1, math.min(#lines, i + 40) do
					if var and string.find(lines[j], `{var}.RequiresLineOfSight = false`, 1, true) then
						set = true
						break
					end
				end
				t.ok(set, `{file.path}:{i}: {var}.RequiresLineOfSight = false (the Roblox default is true)`)
			end
		end
	end
	t.ok(found >= 2, `{found} prompts checked (TankPrompt, the stalls)`)
end

tests["contract: services, controllers and their API, remotes, ORDERs, the replicated state, the probe"] = function(t)
	local s = env(t)
	local sim, p = s.sim, s.p
	local function find(path: string): any
		local found = sim:Find(path)
		t.ok(found, path)
		return found
	end
	local function server(name: string): any
		return sim:Require(find(`ServerScriptService.Services.{name}`))
	end
	local function fns(module: any, what: string, keys: { string })
		for _, key in keys do
			t.eq(type(module[key]), "function", `{what}.{key}`)
		end
	end
	local function signals(module: any, what: string, keys: { string })
		for _, key in keys do
			t.ok(module[key] and module[key].Connect, `{what}.{key} is a Signal`)
		end
	end
	local Steal = server("StealService")
	fns(Steal, "StealService", { "IsStealing", "TheftOn", "Cancel", "_debugSizes", "Init", "Start" })
	signals(Steal, "StealService", { "TheftStarted", "TheftEnded" })
	local Defence = server("DefenceService")
	fns(Defence, "DefenceService", {
		"IsProtected",
		"EndProtection",
		"GiveAfterTheft",
		"HasDog",
		"HasAlarm",
		"LockLevel",
		"HoldTime",
		"SetLockLevel",
		"SetStealProbe",
		"_debugSizes",
		"Init",
		"Start",
	})
	signals(Defence, "DefenceService", { "ProtectionChanged", "LockChanged" })
	local Tank = server("TankService")
	fns(
		Tank,
		"TankService",
		{ "SetSteal", "StealFish", "PreviewAdd", "SlotFish", "ActiveCount", "IsMounted", "EscrowCount", "SetLocked" }
	)
	signals(Tank, "TankService", { "Mounted", "Unmounted", "SlotChanged", "FishAdded", "FishRemoved" })
	local Data = server("DataService")
	fns(Data, "DataService", { "OnClose", "AmendLeaving" })
	signals(Data, "DataService", { "Released", "Loaded", "Committed" })
	local Base = server("BaseService")
	fns(Base, "BaseService", { "SetHomeGuard", "TeleportHome" })
	for _, lib in { "Speed", "Bucket", "CarryGuard", "DogBrain", "HeldRig" } do
		find(`ServerScriptService.Lib.{lib}`)
	end
	fns(sim:Require(find("ServerScriptService.Lib.HeldRig")), "HeldRig", { "Build" })
	fns(server("FishingService"), "FishingService", { "DropHeldFish" })

	-- Wave 1 behaviour: a first visit (SaveCount 0) is the newbie protection (the Studio knob
	-- shortens it — it may be over by now), nobody stealing, the probe wired.
	local kind, untilT = Defence:IsProtected(p)
	if kind ~= nil then
		t.eq(kind, "newbie", "a first visit: the newbie protection")
		t.ok(untilT > sim.workspace:GetServerTimeNow(), "… still running")
		local model = Base:GetBase(p).Model
		t.eq(model:GetAttribute("ProtectKind"), kind, "the base's ProtectKind")
		t.ok(
			math.abs(model:GetAttribute("ProtectUntil") - untilT) < 0.01,
			"the base's ProtectUntil = IsProtected's end"
		)
	end
	t.eq(Steal:IsStealing(p), nil, "nobody stealing")
	t.eq(Defence._isStealing(p), false, "StealService registered the probe (SetStealProbe)")
	t.eq(Defence:HoldTime(p), LOCK.BaseHold, "the base hold")
	t.eq(Tank:EscrowCount(p), 0)
	t.eq(Tank:IsMounted(p), true, "the player's tank is mounted")
	t.eq(
		Data:AmendLeaving(p, function()
			error("must not run for a player who is not leaving")
		end),
		false,
		"AmendLeaving only while leaving"
	)
	for key, size in Steal._debugSizes() do
		t.eq(size, 0, `StealService._debugSizes().{key} (nobody stealing)`)
	end
	-- (one player: at most one entry per player map; no alarm bought — no early-warning loop)
	local players = #sim.game:GetService("Players"):GetPlayers()
	for key, size in Defence._debugSizes() do
		if key == "Alarmed" or key == "IntruderLoop" or key == "IntruderSeen" then
			t.eq(size, 0, `DefenceService._debugSizes().{key} (no alarm)`)
		else
			t.ok(size <= players, `DefenceService._debugSizes().{key} = {size} ≤ {players} players`)
		end
	end

	-- The home guard: a text refuses «ДОМОЙ» with that warning, no teleport.
	local asked = nil
	Base:SetHomeGuard(function(who: any): (string?, any)
		asked = who
		return StealConfig.Texts.HomeGuard, nil
	end)
	local root = p.Character.HumanoidRootPart
	local before = root.Position
	local seen = #sim:ClientEventsFor(p, "Notify")
	sim:FireServer(p, "RequestHome")
	sim:Advance(0.3)
	t.ok(asked == p, "the guard is asked with the player")
	local notes = sim:ClientEventsFor(p, "Notify")
	t.ok(#notes > seen and notes[#notes].args[1] == StealConfig.Texts.HomeGuard, "the guard's text as a warning")
	t.ok((root.Position - before).Magnitude < 0.5, "no teleport")
	Base:SetHomeGuard(nil)

	-- The remotes (§4.10).
	for _, name in { "StealEvent", "ShieldActivate", "DefenceBuy", "DefenceEvent" } do
		local remote = find(`ReplicatedStorage.Remotes.{name}`)
		t.ok(remote and remote:IsA("RemoteEvent"), `{name} is a RemoteEvent`)
	end

	-- Client modules.
	local scripts = p:FindFirstChildOfClass("PlayerScripts")
	local function client(name: string): any
		local module = sim:Find(`Controllers.{name}`, scripts)
		t.ok(module, `Controllers.{name}`)
		return sim:Require(module, p)
	end
	for _, name in { "TheftController", "AlertController", "DefenceController", "TheftWorldController" } do
		t.eq(type(client(name).Start), "function", `{name}.Start`)
	end
	local defence = client("DefenceController")
	fns(defence, "DefenceController", { "Toggle", "IsOpen" })
	t.eq(defence.IsOpen(), false)
	fns(client("NotifyController"), "NotifyController", { "Reserve", "Offset", "Reserved" })
	fns(client("HudController"), "HudController", { "HomeAlert" })
	fns(client("FishingController"), "FishingController", { "HurryCard" })
	local notify = client("NotifyController")
	notify.Reserve("theft", 50)
	notify.Reserve("alert", 72)
	t.eq(notify.Reserved(), 122, "two bands reserved")
	t.eq(notify.Offset("theft"), 0, "the thief's banner on top")
	t.ok(notify.Offset("alert") >= 50, "the alert under it")
	notify.Reserve("theft", nil)
	notify.Reserve("alert", 0)
	t.eq(notify.Reserved(), 0, "released")

	-- Boot orders (§4.1, §6.1).
	local function inOrder(source: string, names: { string }, what: string)
		local at = 1
		for _, name in names do
			local found = string.find(source, `"{name}"`, at, true)
			t.ok(found, `{what}: {name} after the previous one`)
			at = (found or at) + 1
		end
	end
	inOrder(find("ServerScriptService.Main").Source, { "TankService", "DefenceService", "StealService" }, "Main ORDER")
	inOrder(find("StarterPlayer.StarterPlayerScripts.ClientMain").Source, {
		"TankWorldController",
		"DefenceController",
		"AlertController",
		"TheftController",
		"TheftWorldController",
		"FishingController",
	}, "ClientMain ORDER")

	-- The replicated state of §4.10 / §4.11 is written down where both sides read it.
	local protocol = find("ReplicatedStorage.Shared.RemoteNames").Source
	for _, word in
		{
			"StealEvent",
			"ShieldActivate",
			"DefenceBuy",
			"DefenceEvent",
			'"Denied"',
			'"Hold"',
			'"Carry"',
			'"Cancel"',
			'"Done"',
			'"Alert"',
			'"Saved"',
			'"Lost"',
			'"Intruder"',
			'"Returned"',
			'"Bought"',
			'"Shield"',
			"Stealing",
			"StealCooldownUntil",
			"Slowed",
			"ShieldUntil",
			"ShieldReadyAt",
			"HasDog",
			"HasAlarm",
			"LockLevel",
			"ProtectUntil",
			"ProtectKind",
			"AlarmState",
			"Thief",
			"HoldTime",
			"StealBy",
			"StealEnd",
			"StealPhase",
			"Escrow",
			"FreshUntil",
			"DogState",
			"DogPos",
			"DogTarget",
			"StolenFish",
			"|stolen|",
			"|void|",
		}
	do
		t.ok(string.find(protocol, word, 1, true), `RemoteNames documents {word}`)
	end
	-- The template refs Stage 4 moves (the pup) and the prompt points.
	local base = sim.workspace.Bases:FindFirstChild("Base_1")
	t.ok(base.Dog:FindFirstChild("Pup") and base.Dog.Pup.PrimaryPart, "Dog.Pup with its PrimaryPart")
	t.ok(base:FindFirstChild("Alarm") and base.Alarm:FindFirstChild("Lamp"), "Alarm.Lamp")
	sim:AssertNoErrors({ warnings = true })
end

-- The server's require graph: ServerScriptService and ReplicatedStorage.Shared modules, an edge
-- for every module named inside a require(...) call (loads at the top and lazy ones alike).
tests["the server require graph has no cycle (BE-8: DefenceService asks StealService through a probe)"] = function(t)
	local s = env(t)
	local sim = s.sim
	local modules: { [string]: string } = {}
	local function collect(root: any)
		for _, d in root:GetDescendants() do
			if d:IsA("ModuleScript") then
				t.eq(modules[d.Name], nil, `one module named {d.Name}`)
				modules[d.Name] = d.Source
			end
		end
	end
	collect(sim:Find("ServerScriptService"))
	collect(sim:Find("ReplicatedStorage.Shared"))
	local edges: { [string]: { string } } = {}
	for name, source in modules do
		local list = {}
		for call in string.gmatch(source, "require(%b())") do
			for other in modules do
				if other ~= name and string.find(call, `%f[%w]{other}%f[^%w]`) then
					table.insert(list, other)
				end
			end
		end
		edges[name] = list
	end
	t.ok(#edges.StealService > 0, "StealService requires something")
	t.ok(table.find(edges.StealService, "DefenceService") ~= nil, "StealService → DefenceService")
	t.eq(table.find(edges.DefenceService, "StealService"), nil, "DefenceService never requires StealService")
	-- Depth-first search for a cycle.
	local state: { [string]: string } = {}
	local cycle: { string }? = nil
	local stack: { string } = {}
	local function visit(name: string)
		if cycle then
			return
		end
		state[name] = "open"
		table.insert(stack, name)
		for _, other in edges[name] or {} do
			if state[other] == "open" then
				local from = table.find(stack, other) or 1
				local path = {}
				for i = from, #stack do
					table.insert(path, stack[i])
				end
				table.insert(path, other)
				cycle = path
				return
			elseif state[other] == nil then
				visit(other)
			end
		end
		table.remove(stack)
		state[name] = "done"
	end
	for name in modules do
		if state[name] == nil then
			visit(name)
		end
	end
	t.eq(cycle, nil, `no require cycle{if cycle then ": " .. table.concat(cycle, " → ") else ""}`)
end

return tests
