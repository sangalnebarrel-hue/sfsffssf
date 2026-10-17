--[[
	Stage 3 wave 0 — the contract (design §7.1, run inside RbxSim against the built Place1.rbxl):
	  • TankRules: the growth curve and its cap, CurrentValue / SellPrice in whole coins with
	    integer percents (45 at 150 % → 67, no 0.999… floors), Income10, ChooseReplacement (ties,
	    Locked and Dormant skipped, never a higher-income fish), the Uid format, FormatMoney /
	    FormatRate (incl. NaN / inf), AttrTime (exact through a sim attribute);
	  • PlayerData: the template, Reconcile (dictionaries only, unknown fields kept), Migrate,
	    every Sanitize rule (money, slots, uids — NextUid at the Uid length limit too — a
	    dictionary Tank, re-pack / dormant), future content kept verbatim (nothing dropped,
	    nothing sold), the ledger, Layout;
	  • Serialize: JSON-safe output, "_" keys and runtime junk dropped (with issues), unknown
	    JSON-safe fields kept (dropped under strict), skipUid, Stats.Species counts, a fish with
	    a bad Uid kept for Sanitize to renumber, 12 fish < 4 KB;
	  • config invariants (DataService's boot asserts, patchable timing knobs, the §5.3 world
	    numbers, ShortName, the shared «Загружаем твой садок…»);
	  • text widths (UiFx.textWidth): every toast ≤ 300 px at 12 px, every card / header string
	    fits its box at its tier on a phone card (112 × 160) and panel (717 × 221),
	    CatchFx.tankStamp and its stamp box;
	  • the contract names: every widget of design §6.1, the remotes, the services and
	    controllers with their API, both boot ORDERs, the template refs TankService needs and the
	    sell points exist in the built place.
	Pure functions only: one shared sim for the whole file (a server and one phone client for
	UiFx / CatchFx); nothing here changes it.

	Run: lune run tools/run_tests.luau stage3_rules
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

-- Pure modules are read straight from src/ (the same values the game uses).
local function loadPure(path: string): any
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum },
		injectGlobals = true,
	})
	return chunk()
end

local CONFIG = "src/ReplicatedStorage/Shared/Config"
local TankConfig = loadPure(`{CONFIG}/TankConfig.luau`)
local EconomyConfig = loadPure(`{CONFIG}/EconomyConfig.luau`)
local DataConfig = loadPure(`{CONFIG}/DataConfig.luau`)
local FishConfig = loadPure(`{CONFIG}/FishConfig.luau`)
local FishingConfig = loadPure(`{CONFIG}/FishingConfig.luau`)
local RodConfig = loadPure(`{CONFIG}/RodConfig.luau`)
local UIConfig = loadPure(`{CONFIG}/UIConfig.luau`)
local TextUtil = loadPure("src/ReplicatedStorage/Shared/TextUtil.luau")

local Vector2 = roblox.Vector2

local NBSP = "\u{00A0}"
local GROWTH_TIME = TankConfig.Growth.Time

-- A small deterministic generator (the random tank checks are the same every run).
local function lcg(seed: number): { int: (lo: number, hi: number) -> number, float: () -> number }
	local state = seed
	local function float(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	return {
		float = float,
		int = function(lo: number, hi: number): number
			return lo + math.floor(float() * (hi - lo + 1))
		end,
	}
end

-- One sim for the whole file (made by the first test that needs it).
local shared: any = nil
local function env(t: any): any
	if shared then
		return shared
	end
	local sim = t.sim({ place = t.place })
	sim:StartServer()
	sim:Advance(0.5)
	local p = sim:AddPlayer({ UserId = 1, Name = "Rules", DisplayName = "Правила", device = "phone" })
	sim:Advance(2)
	local scripts = p:FindFirstChildOfClass("PlayerScripts")
	shared = {
		sim = sim,
		p = p,
		TankRules = sim:Require(sim:Find("ReplicatedStorage.Shared.TankRules")),
		FishingRules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules")),
		PlayerData = sim:Require(sim:Find("ServerScriptService.Lib.PlayerData")),
		UiFx = sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p),
		CatchFx = sim:Require(sim:Find("Controllers.CatchFx", scripts), p),
	}
	return shared
end

local function fish(uid: string, id: string, slot: number, extra: { [string]: any }?): { [string]: any }
	local f: { [string]: any } = { Uid = uid, Id = id, Kg = 1.2, Age = 0, Slot = slot, CaughtAt = 1700000000 }
	for key, value in extra or {} do
		f[key] = value
	end
	return f
end

local function hasIssue(issues: { string }, prefix: string): boolean
	for _, issue in issues do
		if string.sub(issue, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

-- What a DataStore would refuse: NaN / inf, functions and userdata, mixed or sparse tables,
-- non-string keys; also any "_" key (runtime state). Returns the problem paths.
local function jsonProblems(value: any, path: string, out: { string })
	local kind = typeof(value)
	if kind == "number" then
		if value ~= value or value == math.huge or value == -math.huge then
			table.insert(out, `{path}: {value}`)
		end
	elseif kind == "table" then
		local count, strings, numbers = 0, 0, 0
		for key, item in value do
			count += 1
			if type(key) == "string" then
				strings += 1
				if string.sub(key, 1, 1) == "_" then
					table.insert(out, `{path}.{key}: a runtime key`)
				end
			elseif type(key) == "number" then
				numbers += 1
			else
				table.insert(out, `{path}: a {type(key)} key`)
			end
			jsonProblems(item, `{path}.{tostring(key)}`, out)
		end
		if numbers > 0 and (strings > 0 or numbers ~= #value or count ~= #value) then
			table.insert(out, `{path}: a mixed or sparse table`)
		end
	elseif kind ~= "string" and kind ~= "boolean" then
		table.insert(out, `{path}: {kind}`)
	end
end

local tests = {}

--------------------------------------------------------------------------------
-- TankRules
--------------------------------------------------------------------------------

tests["TankRules: the growth curve ×1 → ×Cap over Growth.Time, capped, «МАКС»; AgeAt clamps"] = function(t)
	local R = env(t).TankRules
	local cap = TankConfig.Growth.Cap
	t.eq(R.Growth(0), 1, "a new fish ×1")
	t.near(R.Growth(GROWTH_TIME / 2), 1 + (cap - 1) / 2, 1e-12, "half way")
	t.eq(R.Growth(GROWTH_TIME), cap, "×Cap at Time")
	t.eq(R.Growth(GROWTH_TIME * 10), cap, "never more")
	t.eq(R.Growth(-5), 1, "never less")
	local last = 0
	for age = 0, GROWTH_TIME + 20, 7.3 do
		local g = R.Growth(age)
		t.ok(g >= last, `monotonic at {age}`)
		last = g
	end
	t.eq(R.IsMaxed(GROWTH_TIME - 0.1), false)
	t.eq(R.IsMaxed(GROWTH_TIME), true, "МАКС from Time on")
	t.eq(R.AgeAt(100, 160), 60)
	t.eq(R.AgeAt(100, 50), 0, "a clock behind GrowFrom: 0")
	t.eq(R.AgeAt(0, 1e9), GROWTH_TIME, "capped at Time")
	t.eq(EconomyConfig.SellScalePct, 100, "(the checks below assume the Stage 3 knob)")
end

tests["TankRules: CurrentValue / SellPrice in whole coins with integer percents (no 0.999… floors)"] = function(t)
	local R = env(t).TankRules
	t.eq(R.SellPrice(45, 0, 150), 67, "45 at 150 % → 67")
	t.eq(R.SellPrice(54, 0, 150), 81, "54 at 150 % → 81, exact")
	t.eq(R.SellPrice(45, 0, 100), 45)
	t.eq(R.CurrentValue(45, GROWTH_TIME), 135, "maxed ×3")
	t.eq(R.SellPrice(45, GROWTH_TIME, 150), 202, "135 at 150 % → 202 (down)")
	t.eq(R.SellPrice(0.2, 0, 100), 1, "never under 1 coin")
	local nan = R.SellPrice(0 / 0, 0, 150)
	t.ok(nan ~= nan, "a NaN value stays NaN (TankService refuses the sale), never «1 coin»")
	-- Every whole tenth of growth: the exact rational answer, for every price up to 13 500.
	local cap = TankConfig.Growth.Cap
	local steps = (cap - 1) * 10
	local bad = {}
	for value = 1, 13500, 7 do
		for k = 0, steps do
			local age = GROWTH_TIME * k / steps
			local exact = (value * (10 + k)) // 10
			local current = R.CurrentValue(value, age)
			if current ~= exact then
				table.insert(bad, `{value} at ×{1 + k / 10}: {current} ≠ {exact}`)
			end
			local price = R.SellPrice(value, age, EconomyConfig.MarketRatePct)
			if price ~= math.max(1, exact * EconomyConfig.MarketRatePct // 100) then
				table.insert(bad, `{value} at ×{1 + k / 10} at the stall: {price}`)
			end
		end
	end
	t.eq(#bad, 0, `exact whole coins ({table.concat(bad, "; ", 1, math.min(#bad, 5))})`)
end

tests["TankRules: Income10 in whole tenths for every species, size and mutation"] = function(t)
	local s = env(t)
	local R, F = s.TankRules, s.FishingRules
	t.eq(R.Income10(4), 40)
	t.eq(R.Income10(1.2), 12)
	t.eq(R.Income10(0.8), 8)
	t.eq(R.Income10(1125), 11250, "a maxed Rainbow Dragon")
	for _, def in FishConfig.Fish do
		for _, mutationId in { "", "Gold", "Neon", "Rainbow" } do
			local mutation = if mutationId == "" then nil else mutationId
			for i = 0, 10 do
				local kg = def.MinKg + (def.MaxKg - def.MinKg) * i / 10
				local _, income = F.Price(def.Id, kg, mutation)
				local tenths = R.Income10(income)
				t.ok(tenths % 1 == 0 and tenths > 0, `{def.Id} {mutationId} {kg} kg: {tenths} tenths`)
				t.near(tenths / 10, income * EconomyConfig.IncomeScale, 0.05 + 1e-9, `{def.Id}: the same income`)
			end
		end
	end
end

tests["TankRules: ChooseReplacement — the weakest active fish, ties, Locked / Dormant skipped, never a stronger one"] = function(
	t
)
	local R = env(t).TankRules
	local list = {
		{ Uid = "f1", Income10 = 20, Value = 15, Age = 10 },
		{ Uid = "f2", Income10 = 10, Value = 10, Age = 0 },
		{ Uid = "f3", Income10 = 10, Value = 10, Age = 50 }, -- the same income, worth more now
		{ Uid = "f4", Income10 = 5, Value = 8, Age = 0, Locked = true },
		{ Uid = "f5", Income10 = 1, Value = 1, Age = 0, Dormant = true },
	}
	t.eq(R.ChooseReplacement(list, 11), "f2", "the lowest income, then the cheapest now")
	t.eq(R.ChooseReplacement(list, 10), nil, "an equal income does not replace (the new one is sold)")
	t.eq(R.ChooseReplacement(list, 1000), "f2", "a Locked (being stolen) or Dormant fish is never replaced")
	t.eq(R.ChooseReplacement({}, 100), nil, "nothing to replace")
	t.eq(R.ChooseReplacement({ list[4], list[5] }, 100), nil, "only Locked / Dormant: nothing")
	-- Ties: the cheaper now first, then longer in the tank, then the older number (numerically).
	t.eq(
		R.ChooseReplacement({
			{ Uid = "f2", Income10 = 10, Value = 20, Age = 0 },
			{ Uid = "f3", Income10 = 10, Value = 10, Age = GROWTH_TIME },
		}, 11),
		"f2",
		"$20 now beats $30 now"
	)
	t.eq(
		R.ChooseReplacement({
			{ Uid = "f1", Income10 = 10, Value = 10, Age = 0 },
			{ Uid = "f2", Income10 = 10, Value = 10, Age = 0.4 },
		}, 11),
		"f2",
		"the same price now: the one longer in the tank"
	)
	t.eq(
		R.ChooseReplacement({
			{ Uid = "f12", Income10 = 10, Value = 10, Age = GROWTH_TIME },
			{ Uid = "f9", Income10 = 10, Value = 10, Age = GROWTH_TIME },
		}, 11),
		"f9",
		"all equal: the lower number (9 < 12, not the string order)"
	)
	-- Random tanks: the chosen fish is never stronger than any active one, nor than the new one.
	local rng = lcg(7)
	for _ = 1, 200 do
		local tank = {}
		for i = 1, 6 do
			table.insert(tank, {
				Uid = `f{i}`,
				Income10 = rng.int(5, 200),
				Value = rng.int(5, 500),
				Age = rng.float() * GROWTH_TIME,
				Locked = rng.float() < 0.1,
				Dormant = rng.float() < 0.1,
			})
		end
		local new = rng.int(1, 250)
		local uid = R.ChooseReplacement(tank, new)
		if uid then
			local chosen
			for _, f in tank do
				if f.Uid == uid then
					chosen = f
				end
			end
			t.ok(chosen and not chosen.Locked and not chosen.Dormant, "an active fish")
			t.ok(chosen.Income10 < new, "weaker than the new one")
			for _, f in tank do
				if not f.Locked and not f.Dormant then
					t.ok(chosen.Income10 <= f.Income10, "the lowest income of the active fish")
				end
			end
		else
			for _, f in tank do
				if not f.Locked and not f.Dormant then
					t.ok(f.Income10 >= new, "nil only when no active fish is weaker")
				end
			end
		end
	end
end

tests["TankRules: uids «f<n>» ≤ Uid.MaxLength; UidNumber refuses everything else"] = function(t)
	local R = env(t).TankRules
	t.eq(R.UidOf(7), "f7")
	t.eq(R.UidOf(123456), "f123456")
	t.eq(R.UidNumber("f7"), 7)
	t.eq(R.UidNumber("f" .. string.rep("9", TankConfig.Uid.MaxLength - 1)), 99999999999, "the longest allowed")
	for _, junk in { "f" .. string.rep("1", TankConfig.Uid.MaxLength), "f1x", "F7", "f-1", "f", "", "7", "f 7" } do
		t.eq(R.UidNumber(junk), nil, `«{junk}» is not a uid`)
	end
	for _, junk in { 7, true, {}, 0 / 0 } do
		t.eq(R.UidNumber(junk), nil, `a {typeof(junk)} is not a uid`)
	end
end

tests["TankRules: FormatMoney / FormatRate — groups, 3 significant digits down, M B T Qa, NaN and inf"] = function(t)
	local R = env(t).TankRules
	local money = {
		{ 0, "$0" },
		{ 7, "$7" },
		{ 12.7, "$12" },
		{ 1234, "$1" .. NBSP .. "234" },
		{ 999999, "$999" .. NBSP .. "999" },
		{ 1e6, "$1M" },
		{ 1230000, "$1.23M" },
		{ 1999999, "$1.99M" },
		{ 12345678, "$12.3M" },
		{ 123456789, "$123M" },
		{ 999999999, "$999M" },
		{ 1.5e9, "$1.5B" },
		{ 1e12, "$1T" },
		{ 1e15, "$1Qa" },
		{ EconomyConfig.MaxMoney, "$1Qa" },
		{ -5, "−$5" },
		{ 0 / 0, "$0" },
		{ math.huge, "$0" },
		{ -math.huge, "$0" },
	}
	for _, case in money do
		t.eq(R.FormatMoney(case[1]), case[2], `FormatMoney({case[1]})`)
	end
	local rates = {
		{ 0, "+$0/с" },
		{ 8, "+$0.8/с" },
		{ 40, "+$4/с" },
		{ 95, "+$9.5/с" },
		{ 100, "+$10/с" },
		{ 420, "+$42/с" },
		{ 425, "+$42/с" },
		{ 11250, "+$1" .. NBSP .. "125/с" },
		{ 12340, "+$1" .. NBSP .. "234/с" },
		{ 12000000, "+$1.2M/с" },
		{ -40, "−$4/с" },
		{ -11250, "−$1" .. NBSP .. "125/с" },
		{ 0 / 0, "+$0/с" },
		{ math.huge, "+$0/с" },
	}
	for _, case in rates do
		t.eq(R.FormatRate(case[1]), case[2], `FormatRate({case[1]})`)
	end
end

tests["TankRules: AttrTime survives a sim attribute exactly (the float32 whole-number trap)"] = function(t)
	local s = env(t)
	local R, sim = s.TankRules, s.sim
	t.eq(R.AttrTime(1700000123), 1700000123 + 1 / 1024, "a whole second gets +1/1024 s")
	t.eq(R.AttrTime(1700000123.5), 1700000123.5, "a fraction is kept")
	local probe = sim:Create("Folder", { Name = "AttrTimeProbe" }, sim.workspace)
	for _, at in { 1700000000, 1700000123, 1700003599, 1700000123.5, 1700000123.25 } do
		local value = R.AttrTime(at)
		probe:SetAttribute("GrowFrom", value)
		t.eq(probe:GetAttribute("GrowFrom"), value, `{at}: read back exactly`)
		t.ok(math.abs(probe:GetAttribute("GrowFrom") - at) < 1e-3, `{at}: off by under 1 ms`)
	end
	probe:Destroy()
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- PlayerData
--------------------------------------------------------------------------------

tests["PlayerData: the template, names, NewUid, Migrate, the ledger"] = function(t)
	local D = env(t).PlayerData
	local data = D.Template()
	t.eq(data, {
		V = DataConfig.Version,
		Money = EconomyConfig.StartMoney,
		RodId = RodConfig.StartRod,
		TankSlots = TankConfig.StartSlots,
		LockLevel = 0,
		Upgrades = {},
		Tank = {},
		NextUid = 1,
		Stats = { Caught = 0, Sold = 0, Earned = 0, Spent = 0, Species = {} },
		Created = 0,
		LastOnline = 0,
		SaveCount = 0,
	}, "schema v1")
	t.eq(data.Session, nil, "no lock in the template")
	t.ok(D.Template().Tank ~= D.Template().Tank, "a new table every call")
	t.eq(D.StoreNameFor(false), "PlayerData")
	t.eq(D.StoreNameFor(true), "PlayerData_Studio")
	t.eq(D.KeyFor(123), "Player_123")
	t.eq(D.KeyFor(-1), "Player_-1", "Studio test players")
	t.eq(D.NewUid(data), "f1")
	t.eq(D.NewUid(data), "f2")
	t.eq(data.NextUid, 3, "never reused")
	t.eq(D.SlotCap({ TankSlots = 16 }), TankConfig.MaxSlots, "the runtime mounts min(TankSlots, MaxSlots)")
	t.eq(D.SlotCap({ TankSlots = 7 }), 7)
	-- Migrate: nothing to migrate in v1; a missing or broken V is 1; newer data is not touched.
	t.eq(D.Migrate({}).V, 1)
	t.eq(D.Migrate({ V = "x" }).V, 1)
	t.eq(D.Migrate({ V = 1 }).V, 1)
	t.eq(D.Migrate({ V = 99 }).V, 99, "a newer server's data stays as it is (DataService kicks TooNew)")
	-- The ledger: Money == StartMoney + Earned − Spent, never corrected.
	local ok, expected = D.Ledger(D.Template())
	t.eq(ok, true)
	t.eq(expected, EconomyConfig.StartMoney)
	local rich = D.Template()
	rich.Money, rich.Stats.Earned, rich.Stats.Spent = 100, 150, 50
	t.eq(D.Ledger(rich), true)
	rich.Money = 101
	local okDupe, expectedDupe = D.Ledger(rich)
	t.eq(okDupe, false, "a dupe shows")
	t.eq(expectedDupe, 100)
	D.Sanitize(rich)
	t.eq(rich.Money, 101, "Sanitize never 'fixes' the ledger")
end

tests["PlayerData: Reconcile fills dictionaries only, copies Tank only when missing, keeps unknown fields"] = function(
	t
)
	local D = env(t).PlayerData
	local only = fish("f1", "Perch", 1)
	local data = { Money = 50, Stats = { Caught = 3 }, Future = { a = 1 }, Tank = { only } }
	D.Reconcile(data)
	t.eq(data.Money, 50)
	t.eq(data.Stats, { Caught = 3, Sold = 0, Earned = 0, Spent = 0, Species = {} }, "Stats deep-filled")
	t.eq(data.Upgrades, {})
	t.eq(data.TankSlots, TankConfig.StartSlots)
	t.eq(data.Future, { a = 1 }, "an unknown field stays")
	t.eq(#data.Tank, 1, "the array is not merged element by element")
	t.ok(data.Tank[1] == only, "… the same fish")
	t.eq(data.Tank[1], fish("f1", "Perch", 1), "… nothing added to it")
	t.eq(data.Session, nil, "no lock invented")
	local empty = D.Reconcile({})
	t.eq(empty.Tank, {}, "a missing Tank is copied")
	local broken = D.Reconcile({ Stats = 5 })
	t.eq(broken.Stats, 5, "a wrong type is Sanitize's job, not Reconcile's")
end

tests["PlayerData: Sanitize repairs what is provably invalid (money, slots, uids, Tank, Stats)"] = function(t)
	local D = env(t).PlayerData
	local function clean(data: any): (any, { string })
		return D.Sanitize(D.Migrate(D.Reconcile(data)))
	end
	local _, none = clean(D.Template())
	t.eq(none, {}, "a fresh template has no issues")

	-- Numbers: one num() rule (NaN / inf → default, then clamp), integers floored.
	for _, case in
		{
			{ -5, 0 },
			{ 0 / 0, 0 },
			{ math.huge, 0 },
			{ 12.7, 12 },
			{ 2e15, EconomyConfig.MaxMoney },
			{ "100", 0 },
		}
	do
		local data, issues = clean({ Money = case[1] })
		t.eq(data.Money, case[2], `Money {tostring(case[1])}`)
		t.ok(hasIssue(issues, "Money"), `Money {tostring(case[1])}: reported`)
	end
	for _, case in { { 3, TankConfig.StartSlots }, { 16, 16 }, { 0 / 0, TankConfig.StartSlots }, { 7.5, 7 } } do
		t.eq(clean({ TankSlots = case[1] }).TankSlots, case[2], `TankSlots {tostring(case[1])}: only the lower bound`)
	end
	t.eq(clean({ LockLevel = -1 }).LockLevel, 0)
	t.eq(clean({ LockLevel = 2.5 }).LockLevel, 2)
	t.eq(clean({ Upgrades = 5 }).Upgrades, {}, "Upgrades not a table → {}")
	t.eq(clean({ Upgrades = { Dog = 1, [1] = "x" } }).Upgrades, { Dog = 1 }, "string keys only")
	t.eq(clean({ RodId = 5 }).RodId, RodConfig.StartRod)
	t.eq(clean({ RodId = "RodFuture" }).RodId, "RodFuture", "an unknown rod is kept verbatim")
	t.eq(clean({ Created = -3, LastOnline = 0 / 0, SaveCount = 4.2 }).SaveCount, 4)

	-- Stats: numbers ≥ 0 floored; Species string keys, whole counts ≥ 0.
	local stats = clean({
		Stats = { Caught = -2, Sold = 1.9, Earned = 0 / 0, Spent = 3, Species = { Perch = 2.5, [5] = 1, Crucian = -1 } },
	}).Stats
	t.eq(stats, { Caught = 0, Sold = 1, Earned = 0, Spent = 3, Species = { Perch = 2, Crucian = 0 } })
	t.eq(clean({ Stats = 5 }).Stats, D.Template().Stats, "Stats not a table → the template")

	-- Tank: a dictionary or a sparse table is re-packed densely; entries without Id / Kg dropped.
	local dict, dictIssues = clean({ Tank = { a = fish("f1", "Perch", 1), b = fish("f2", "Crucian", 2) } })
	t.eq(#dict.Tank, 2, "a dictionary Tank → a dense array")
	t.ok(hasIssue(dictIssues, "Tank: "), "… reported")
	local sparse = clean({ Tank = { [1] = fish("f1", "Perch", 1), [3] = fish("f3", "Perch", 3) } })
	t.eq(#sparse.Tank, 2, "a sparse Tank → dense")
	t.eq(sparse.Tank[2].Uid, "f3", "… in key order")
	local dropped, dropIssues = clean({
		Tank = {
			fish("f1", "Perch", 1),
			{ Uid = "f2", Kg = 1, Slot = 2 }, -- no Id
			fish("f3", "Perch", 3, { Kg = 0 / 0 }),
			fish("f4", "Perch", 4, { Kg = 0 }),
			fish("f5", "Perch", 5, { Kg = -1 }),
			"a string",
		},
	})
	t.eq(#dropped.Tank, 1, "only the valid fish is left")
	local drops = 0
	for _, issue in dropIssues do
		if string.find(issue, "выброшена", 1, true) then
			drops += 1
		end
	end
	t.eq(drops, 5, "each drop reported")
	-- Fish fields.
	local fields = clean({
		Tank = {
			fish("f1", "Perch", 1, { Age = 0 / 0, Mutation = 5, CaughtAt = "x" }),
			fish("f2", "Perch", 2, { Age = 500, Mutation = "Cosmic" }),
			fish("f3", "Perch", 3, { Age = -3, Origin = 7 }),
		},
	}).Tank
	t.eq(fields[1].Age, 0, "Age NaN → 0")
	t.eq(fields[1].Mutation, nil, "a non-string mutation → none")
	t.eq(fields[1].CaughtAt, 0)
	t.eq(fields[2].Age, GROWTH_TIME, "Age capped at Growth.Time")
	t.eq(fields[2].Mutation, "Cosmic", "an unknown mutation string is kept (counts as none at runtime)")
	t.eq(fields[3].Age, 0)
	t.eq(fields[3].Origin, nil)

	-- Uids: the first owner keeps it; invalid / duplicate ones get new numbers past the highest.
	local uids, uidIssues = clean({
		NextUid = 2,
		Tank = { fish("f9", "Perch", 1), fish("f9", "Perch", 2), fish("x", "Perch", 3), fish("f3", "Perch", 4) },
	})
	t.eq(uids.Tank[1].Uid, "f9", "the first f9 keeps it")
	t.eq(uids.Tank[2].Uid, "f10", "the duplicate → past the highest")
	t.eq(uids.Tank[3].Uid, "f11", "an invalid uid → a new one")
	t.eq(uids.Tank[4].Uid, "f3", "a valid unique one stays")
	t.eq(uids.NextUid, 12, "NextUid ≥ 1 + the highest number")
	t.ok(hasIssue(uidIssues, "NextUid"), "NextUid reported")
	t.ok(hasIssue(uidIssues, "Tank[2].Uid"), "the duplicate reported")
	t.eq(clean({ NextUid = 0 / 0, Tank = {} }).NextUid, 1)
	-- NextUid (or a fish's number) at the Uid length limit — only corruption: the whole tank is
	-- renumbered from f1, so every fish and every new catch stays sellable (TankRules.UidNumber).
	local limit = 10 ^ (TankConfig.Uid.MaxLength - #TankConfig.Uid.Prefix) - 1
	local topUid = TankConfig.Uid.Prefix .. string.format("%d", limit)
	t.eq(#topUid, TankConfig.Uid.MaxLength, "the highest number still fits")
	for _, case in
		{
			{ NextUid = 1e300, Tank = { fish("f5", "Perch", 1), fish("f2", "Perch", 2) } },
			{ NextUid = limit + 1, Tank = { fish("f5", "Perch", 1), fish("f2", "Perch", 2) } },
			{ NextUid = 7, Tank = { fish(topUid, "Perch", 1), fish("f2", "Perch", 2) } },
		}
	do
		local was = case.NextUid
		local fixed, fixIssues = clean(case)
		t.eq({ fixed.Tank[1].Uid, fixed.Tank[2].Uid, fixed.NextUid }, { "f1", "f2", 3 }, `NextUid {was}: renumbered`)
		t.ok(hasIssue(fixIssues, "NextUid") and hasIssue(fixIssues, "Tank[1].Uid"), "reported")
		local uid = D.NewUid(fixed)
		t.eq(uid, "f3")
		t.ok(env(t).TankRules.UidNumber(uid) ~= nil, "a new catch gets a sellable uid")
	end
	local edge = clean({ NextUid = limit, Tank = { fish("f3", "Perch", 1) } })
	t.eq(edge.NextUid, limit, "the last valid NextUid is kept")
	t.eq(D.NewUid(edge), topUid, "… and gives the last valid uid")
	-- NewUid past the limit (live data only): the lowest free number, NextUid unchanged.
	local over = { NextUid = 1e300, Tank = { fish("f1", "Perch", 1), fish("f2", "Perch", 2), fish("f4", "Perch", 3) } }
	t.eq(D.NewUid(over), "f3", "the lowest free number")
	t.eq(over.NextUid, 1e300, "NextUid unchanged (the next load renumbers)")

	-- Slots: a known fish keeps a free whole slot 1..cap; duplicates / out of range → the lowest
	-- free; none free → dormant, Slot unchanged. An unknown fish takes no slot.
	local slots = clean({
		Tank = {
			fish("f1", "Perch", 1),
			fish("f2", "Crucian", 1),
			fish("f3", "Puffer", 9),
			fish("f4", "Perch", 2.5),
			fish("f5", "FutureFish", 2),
			fish("f6", "Perch", 0 / 0),
		},
	}).Tank
	t.eq(slots[1].Slot, 1, "first come keeps slot 1")
	t.eq(slots[2].Slot, 2, "a duplicate → the lowest free")
	t.eq(slots[3].Slot, 3, "out of range (9 > 6) → the lowest free")
	t.eq(slots[4].Slot, 4, "not a whole number → re-packed")
	t.eq(slots[5].Slot, 2, "an unknown fish keeps its slot verbatim and reserves nothing")
	t.eq(slots[6].Slot, 5, "a NaN slot → re-packed")
	local full = { Tank = {}, NextUid = 8 }
	for i = 1, 7 do
		table.insert(full.Tank, fish(`f{i}`, "Perch", i))
	end
	local packed, fullIssues = clean(full)
	t.eq(#packed.Tank, 7, "nothing dropped …")
	t.eq(packed.Money, 0, "… nothing sold")
	t.eq(packed.Tank[7].Slot, 7, "no free slot: dormant, Slot unchanged")
	t.eq(fullIssues, {}, "dormancy is not a repair")
	local active, dormant = env(t).PlayerData.Layout(packed)
	local count = 0
	for _ in active do
		count += 1
	end
	t.eq(count, 6, "6 active")
	t.eq(#dormant, 1, "1 dormant")
	t.eq(dormant[1].Uid, "f7")
end

tests["PlayerData: future content survives verbatim (rolling updates: nothing dropped, nothing sold)"] = function(t)
	local D = env(t).PlayerData
	local ids = { "Crucian", "Perch", "Puffer", "Swordfish", "SharkPup", "DragonFish" }
	local data = D.Template()
	data.RodId = "RodFuture"
	data.TankSlots = 16
	data.Money = 777
	data.Stats.Earned = 777
	data.NextUid = 15
	data.Upgrades = { Shield = { Level = 3 }, Dog = true }
	data.Pets = { "cat", "dog" } -- a field of a newer schema
	for i = 1, 13 do
		table.insert(data.Tank, fish(`f{i}`, ids[(i - 1) % #ids + 1], i, { Age = 100 }))
	end
	table.insert(data.Tank, fish("f14", "FutureFish", 14, { Mutation = "Cosmic", Shiny = true }))
	local loaded, issues = D.Sanitize(D.Migrate(D.Reconcile(data)))
	t.eq(issues, {}, "nothing to repair")
	t.eq(#loaded.Tank, 14, "all 14 fish kept")
	for i, f in loaded.Tank do
		t.eq(f.Slot, i, `fish {i}: slot unchanged`)
		t.eq(f.Uid, `f{i}`, `fish {i}: uid unchanged`)
	end
	t.eq(loaded.Tank[14].Id, "FutureFish")
	t.eq(loaded.Tank[14].Mutation, "Cosmic")
	t.eq(loaded.RodId, "RodFuture")
	t.eq(loaded.TankSlots, 16)
	t.eq(loaded.Money, 777, "nothing sold")
	local active, dormant = D.Layout(loaded)
	local count = 0
	for _ in active do
		count += 1
	end
	t.eq(count, TankConfig.MaxSlots, "the 12 displays are full")
	t.eq(#dormant, 2, "slot 13 (over MaxSlots here) and the unknown species sleep")
	local out, outIssues = D.Serialize(loaded)
	t.eq(outIssues, {}, "a clean save")
	t.eq(#out.Tank, 14, "all saved back")
	t.eq(out.Tank[14].Shiny, true, "an unknown fish field is kept")
	t.eq(out.Pets, { "cat", "dog" }, "an unknown top-level field is kept")
	t.eq(out.Upgrades, { Shield = { Level = 3 }, Dog = true })
	t.eq(out.RodId, "RodFuture")
	t.eq(out.TankSlots, 16)
end

--------------------------------------------------------------------------------
-- Serialize
--------------------------------------------------------------------------------

tests["Serialize: a validating whitelist — JSON-safe, '_' keys and runtime junk dropped, unknown JSON kept"] = function(
	t
)
	local s = env(t)
	local D = s.PlayerData
	local data = D.Template()
	data.Tank = { fish("f1", "Perch", 1, { Age = 212.44 }), fish("f2", "DragonFish", 2, { Mutation = "Rainbow" }) }
	data.NextUid = 3
	data.Session = { Id = "load", Server = "token", Job = "", T = 1700000000 }
	-- Runtime state that must never reach the DataStore:
	data._Runtime = { GrowFrom = 123 }
	data.Tank[1]._GrowFrom = 1700000000.5
	data.Tank[1].Junk = s.sim.workspace -- an Instance
	data.Stats.Where = roblox.Vector3.new(1, 2, 3)
	data.Hook = function() end
	data.Money = 0 / 0
	-- Unknown fields from a newer server: JSON-safe ones are kept.
	data.Settings = { Music = true, Volume = 0.5, Deep = { A = { B = { C = 1 } } } }
	data.TooDeep = { A = { B = { C = { D = { E = 1 } } } } }
	data.Mixed = { 1, x = 2 }
	data.Sparse = { [1] = 1, [3] = 3 }
	local out, issues = D.Serialize(data)
	local problems = {}
	jsonProblems(out, "out", problems)
	t.eq(problems, {}, "nothing a DataStore would refuse")
	local encoded = serde.encode("json", out)
	t.eq(serde.decode("json", encoded), out, "JSON round trip")
	t.eq(out._Runtime, nil, "'_' keys are never written")
	t.eq(out.Tank[1]._GrowFrom, nil)
	t.eq(out.Tank[1].Junk, nil, "an Instance is dropped …")
	t.ok(hasIssue(issues, "Tank[1].Junk"), "… with an issue")
	t.eq(out.Stats.Where, nil)
	t.ok(hasIssue(issues, "Stats.Where"), "a Vector3 dropped with an issue")
	t.eq(out.Hook, nil)
	t.ok(hasIssue(issues, "Hook"), "a function dropped with an issue")
	t.eq(out.Money, 0, "Money NaN → the template's 0 …")
	t.ok(hasIssue(issues, "Money"), "… with an issue")
	t.eq(out.Settings, { Music = true, Volume = 0.5, Deep = { A = { B = { C = 1 } } } }, "JSON-safe, depth 4: kept")
	t.eq(out.TooDeep, { A = { B = { C = {} } } }, "the 5th level is dropped …")
	t.ok(hasIssue(issues, "TooDeep.A.B.C.D"), "… with an issue")
	t.eq(out.Mixed, nil)
	t.ok(hasIssue(issues, "Mixed"), "a mixed table dropped")
	t.eq(out.Sparse, nil)
	t.ok(hasIssue(issues, "Sparse"), "a sparse array dropped")
	t.eq(out.Tank[1].Age, 212.4, "Age with one decimal")
	t.eq(out.Tank[2].Mutation, "Rainbow")
	t.eq(out.Session, { Id = "load", Server = "token", Job = "", T = 1700000000 })
	t.ok(out.Tank[1] ~= data.Tank[1] and out.Stats ~= data.Stats, "a new table: no aliasing with the live data")
	t.eq(data.Tank[1]._GrowFrom, 1700000000.5, "the live data is untouched")

	-- strict (the one retry after 103/104/105): every unknown field goes.
	local strict, strictIssues = D.Serialize(data, { strict = true })
	t.eq(strict.Settings, nil, "unknown top-level fields dropped")
	t.eq(strict.Pets, nil)
	t.ok(hasIssue(strictIssues, "Settings"), "… reported")
	t.eq(strict.Tank[1].Junk, nil)
	t.eq(#strict.Tank, 2, "known content stays")
	t.eq(strict.Upgrades, {}, "Upgrades is a known field")

	-- skipUid (Stage 4 escrow): the fish is left out of this save, the live data keeps it.
	local skipped = D.Serialize(data, {
		skipUid = function(uid: string): boolean
			return uid == "f2"
		end,
	})
	t.eq(#skipped.Tank, 1)
	t.eq(skipped.Tank[1].Uid, "f1")
	t.eq(#data.Tank, 2, "the live tank still has it")
end

tests["Serialize: a fish with a bad Uid is kept for Sanitize to renumber; Species counts whole, no '_' keys"] = function(
	t
)
	local D = env(t).PlayerData
	local data = D.Template()
	data.Tank = {
		fish("f1", "Perch", 1),
		fish("oops", "Crucian", 2), -- a string, but not a uid
		fish("f1", "Puffer", 3), -- a duplicate (Sanitize's job, kept as is)
		fish(string.rep("x", 80), "Swordfish", 4), -- longer than any string field may be
		fish("f2", "SharkPup", 5),
	}
	data.Tank[5].Uid = 7 :: any -- not a string at all
	data.NextUid = 3
	data.Stats.Species = { Perch = 2, Crucian = -1, Puffer = 2.7, Swordfish = 0 / 0, _Seen = 1 }
	local seen: { any } = {}
	local out, issues = D.Serialize(data, {
		skipUid = function(uid: any): boolean
			table.insert(seen, uid)
			return false
		end,
	})
	t.eq(#out.Tank, 5, "no fish is dropped for its Uid")
	t.eq(out.Tank[2].Uid, "oops", "a bad string uid is written as is …")
	t.ok(hasIssue(issues, "Tank[2].Uid"), "… with an issue")
	t.eq(out.Tank[3].Uid, "f1", "a duplicate is written as is (Sanitize dedupes on load)")
	t.eq(out.Tank[4].Uid, nil, "an over-long uid is left out …")
	t.ok(hasIssue(issues, "Tank[4].Uid"), "… with an issue")
	t.eq(out.Tank[5].Uid, nil, "a number uid is left out …")
	t.eq(out.Tank[5].Id, "SharkPup", "… the fish is kept")
	t.ok(hasIssue(issues, "Tank[5].Uid"), "… with an issue")
	t.eq(seen, { "f1", "oops", "f1", string.rep("x", 80) }, "skipUid only ever sees string uids")
	t.eq(out.Stats.Species, { Perch = 2, Crucian = 0, Puffer = 2, Swordfish = 0 }, "whole counts ≥ 0, no '_' key")
	t.ok(hasIssue(issues, "Stats.Species.Crucian"), "a negative count reported")
	t.ok(hasIssue(issues, "Stats.Species.Puffer"), "a fractional count reported")
	t.ok(hasIssue(issues, "Stats.Species.Swordfish"), "a NaN count reported")
	t.ok(not hasIssue(issues, "Stats.Species._Seen"), "a '_' key is runtime state: skipped quietly")
	-- The next load repairs every uid: unique, valid, past the highest, nothing dropped.
	local loaded, loadIssues = D.Sanitize(serde.decode("json", serde.encode("json", out)))
	t.eq(#loaded.Tank, 5, "all five fish come back")
	local uids = {}
	for i, f in loaded.Tank do
		uids[i] = f.Uid
	end
	t.eq(uids, { "f1", "f3", "f4", "f5", "f6" }, "renumbered past the highest")
	t.eq(loaded.NextUid, 7)
	t.ok(hasIssue(loadIssues, "Tank[2].Uid") and hasIssue(loadIssues, "Tank[5].Uid"), "Sanitize reports them")
end

tests["Serialize: 12 maxed fish with full stats < 4 KB of JSON"] = function(t)
	local D = env(t).PlayerData
	local data = D.Template()
	for i = 1, TankConfig.MaxSlots do
		table.insert(data.Tank, {
			Uid = `f{99990 + i}`,
			Id = "DragonFish",
			Kg = 17.99,
			Mutation = "Rainbow",
			Age = GROWTH_TIME - 0.1,
			Slot = i,
			CaughtAt = 1700000123,
		})
	end
	data.NextUid = 100003
	data.Money = 123456789012
	data.Stats = { Caught = 99999, Sold = 99999, Earned = 123456789012, Spent = 0, Species = {} }
	for _, def in FishConfig.Fish do
		data.Stats.Species[def.Id] = 99999
	end
	data.Session = { Id = string.rep("a", 36), Server = string.rep("b", 36), Job = string.rep("c", 36), T = 1700000123 }
	local out, issues = D.Serialize(data)
	t.eq(issues, {})
	local size = #serde.encode("json", out)
	t.log(`12 fish + stats + lock: {size} bytes of JSON`)
	t.ok(size < 4096, `{size} B < 4 KB (the limit is 4 MB)`)
end

--------------------------------------------------------------------------------
-- Configs
--------------------------------------------------------------------------------

-- How many times plain text occurs in a source (a patch anchor must be unique).
local function occurrences(source: string, text: string): number
	local n, at = 0, 1
	while true do
		local found = string.find(source, text, at, true)
		if not found then
			return n
		end
		n += 1
		at = found + #text
	end
end

tests["configs: DataService's boot invariants, patchable knobs, ShortName, shared texts"] = function(t)
	t.ok(DataConfig.AutoSave < DataConfig.LockStale, "AutoSave < LockStale: a live lock never looks stale")
	t.ok(
		DataConfig.LeaveSaveWindow + DataConfig.MinWriteGap < DataConfig.LockWait.Tries * DataConfig.LockWait.Every,
		"the leave save lands before another server steals the lock"
	)
	t.ok(DataConfig.Retry.Base <= DataConfig.Retry.Max)
	t.ok(DataConfig.CloseBudget < 30, "BindToClose inside Roblox's 30 s")
	t.ok(TankConfig.StartSlots <= TankConfig.MaxSlots)
	t.ok(TankConfig.ConfirmArm < TankConfig.ConfirmTime, "the double-tap guard is shorter than the confirm window")
	t.ok(TankConfig.Display.Range < TankConfig.Display.DropRange, "hysteresis")
	-- §5.3's world numbers live in TankConfig too (Wave 1 B owns Display / Pier).
	local display, pier = TankConfig.Display, TankConfig.Pier
	local tag, fx = display.Tag, display.Fx
	t.eq({
		display.TagEvery,
		display.MarketWordRange,
		display.Life,
		{ tag.Lift, tag.Forward, tag.Width, tag.Height, tag.PixelsX, tag.PixelsY },
		{ fx.Shrink, fx.Grow, fx.MaxEmitters, fx.EmitterLife },
	}, {
		1,
		200,
		{ Bob = 0.12, Turn = 6, TimeMin = 2.4, TimeMax = 3.2 },
		{ 3.3, 3.6, 5.6, 1.9, 44, 16 },
		{ 0.25, 0.35, 2, 1.2 },
	}, "Display: the tag timer, the hub word, the calm life, the slot tag, the event FX")
	t.eq({ pier.Rise, pier.PopTime, pier.Width, pier.Height }, { 2.5, 1.2, 4.4, 1.6 }, "Pier: the pop and the word")
	t.ok(display.Life.TimeMin <= display.Life.TimeMax, "the bob period range")
	t.ok(pier.PopRange < pier.Range, "income pops only where the word is visible")
	t.ok(EconomyConfig.HomeRatePct < EconomyConfig.MarketRatePct, "the stall pays more")
	for _, key in { "SellScalePct", "HomeRatePct", "MarketRatePct" } do
		t.ok(EconomyConfig[key] % 1 == 0, `{key}: an integer percent`)
	end
	t.eq(EconomyConfig.MaxMoney, 1e15, "exact integers")
	-- Every timing knob on its own line: a test patch (boot with patches) finds exactly one anchor.
	local anchors = {
		[`{CONFIG}/DataConfig.luau`] = {
			"AutoSave = 60,",
			"MinWriteGap = 6,",
			"GapEpsilon = 0.05,",
			"LockStale = 150,",
			"Every = 6,",
			"LeaveSaveWindow = 15,",
			"CloseBudget = 25,",
			"ProbeTimeout = 5,",
			"BudgetDelay = 10,",
		},
		[`{CONFIG}/TankConfig.luau`] = {
			"Time = 300,",
			"ConfirmTime = 3,",
			"ConfirmArm = 0.4,",
			"CheckEvery = 0.5,",
			"TagEvery = 1,",
			"TimeMin = 2.4,",
			"TimeMax = 3.2,",
			"Shrink = 0.25,",
			"PopEvery = 5,",
			"PopTime = 1.2,",
		},
		[`{CONFIG}/EconomyConfig.luau`] = { "IncomeTick = 1,", "MaxCatchUp = 3,", "MarketDwell = 2," },
	}
	for path, list in anchors do
		local source = fs.readFile(path)
		for _, anchor in list do
			t.eq(occurrences(source, anchor), 1, `{path}: «{anchor}» once`)
		end
	end
	-- Short names (K-6), sentence case; cards upper-case them.
	local expected = {
		Crucian = "Карасик",
		Perch = "Окунь",
		Puffer = "Фугу",
		Swordfish = "Меч-рыба",
		SharkPup = "Акулёнок",
		DragonFish = "Дракон",
	}
	for _, def in FishConfig.Fish do
		t.eq(def.ShortName, expected[def.Id], `{def.Id}: ShortName`)
	end
	t.eq(
		FishingConfig.Texts.Denied.loading,
		"Загружаем твой садок…",
		"the cast refusal while loading"
	)
	t.eq(TankConfig.Texts.Denied.loading, FishingConfig.Texts.Denied.loading, "… the same words as the sale's")
	for _, point in EconomyConfig.SellPoints do
		t.ok(point.Range > 0 and type(point.Id) == "string" and type(point.Name) == "string", `{point.Id}`)
	end
	t.eq(#EconomyConfig.SellPoints, 5, "the hub market + 4 bridge kiosks")
end

--------------------------------------------------------------------------------
-- Text widths (K-6, K-7)
--------------------------------------------------------------------------------

local SHORT_NAMES = {}
local FULL_NAMES = {}
for _, def in FishConfig.Fish do
	table.insert(SHORT_NAMES, def.ShortName)
	table.insert(FULL_NAMES, def.Name)
end

-- The biggest numbers the panel can show (a maxed Rainbow Dragon of the biggest size).
local function extremes(F: any, R: any): { [string]: number }
	local value, income = F.Price("DragonFish", 1000, "Rainbow")
	local maxed = R.CurrentValue(value, GROWTH_TIME)
	return {
		price = maxed, -- at home
		stall = R.SellPrice(value, GROWTH_TIME, EconomyConfig.MarketRatePct),
		income10 = R.Income10(income),
		tankIncome10 = R.Income10(income) * TankConfig.MaxSlots,
		tankValue = R.SellPrice(value, GROWTH_TIME, EconomyConfig.MarketRatePct) * TankConfig.MaxSlots,
	}
end

tests["text widths: every toast ≤ 300 px at 12 px with the longest names and prices"] = function(t)
	local s = env(t)
	local UiFx, R = s.UiFx, s.TankRules
	local big = extremes(s.FishingRules, R)
	t.eq(big.stall, 60750, "the longest sale on a card: «💵 $60 750»")
	local texts = {
		TankConfig.Texts.FirstFish,
		TankConfig.Texts.FullSold,
		TextUtil.fill(
			TankConfig.Texts.Milestone,
			{ money = R.FormatMoney(EconomyConfig.Milestones[#EconomyConfig.Milestones]) }
		),
		TextUtil.fill(TankConfig.Texts.Milestone, { money = R.FormatMoney(100000) }),
		DataConfig.Texts.MemoryToast,
	}
	for _, text in TankConfig.Texts.Denied do
		table.insert(texts, text)
	end
	for _, new in SHORT_NAMES do
		for _, old in SHORT_NAMES do
			table.insert(
				texts,
				TextUtil.fill(TankConfig.Texts.Replaced, { new = new, old = old, price = R.FormatMoney(big.price) })
			)
		end
	end
	for _, text in texts do
		t.ok(not string.find(text, "{", 1, true), `«{text}»: every field filled`)
		local w = UiFx.textWidth(text, 12)
		t.ok(w <= 300, `«{text}»: {math.floor(w)} px ≤ 300 at 12 px`)
	end
end

-- A label's box in px on a card / panel of the given size: the product of the Size scales from
-- the label up to (not including) the root.
local function boxOf(label: any, root: any, size: Vector2): Vector2
	local w, h = size.X, size.Y
	local node = label
	local sx, sy = 1, 1
	while node and node ~= root do
		sx *= node.Size.X.Scale
		sy *= node.Size.Y.Scale
		node = node.Parent
	end
	return Vector2.new(w * sx, h * sy)
end

local function fits(t: any, UiFx: any, text: string, label: any, root: any, size: Vector2, what: string)
	local tier = label:GetAttribute("TextTier")
	local px = if tier then UIConfig.Type[tier] else 12
	local box = boxOf(label, root, size)
	local w = UiFx.textWidth(text, px)
	t.ok(w <= box.X, `{what} «{text}»: {math.floor(w)} px at {px} px fits {math.floor(box.X)} px`)
	t.ok(box.Y >= px, `{what}: the box is {math.floor(box.Y)} px tall for {px} px text`)
end

tests["text widths: card, header and stamp strings fit their boxes at their tier (phone card 112 × 160)"] = function(t)
	local s = env(t)
	local UiFx, R, sim = s.UiFx, s.TankRules, s.sim
	local big = extremes(s.FishingRules, R)
	local hud = sim:Find("StarterGui.HUD")
	local panel = hud.TankPanel.Panel
	local card = panel.Cards.CardTemplate
	local phone = Vector2.new(112, 160)
	local wide = Vector2.new(TankConfig.Panel.WideCard, TankConfig.Panel.WideCard * 160 / 112)
	for _, name in SHORT_NAMES do
		fits(t, UiFx, TextUtil.upper(name), card.NameLabel, card, phone, "phone card name")
	end
	for _, name in FULL_NAMES do
		fits(t, UiFx, TextUtil.upper(name), card.NameLabel, card, wide, "wide card name")
	end
	local caption = card.Sell.Caption
	fits(t, UiFx, "💵 " .. R.FormatMoney(big.stall), caption, card, phone, "phone sell")
	fits(t, UiFx, TankConfig.Texts.Confirm, caption, card, phone, "confirm")
	fits(t, UiFx, TankConfig.Texts.Sell .. " " .. R.FormatMoney(big.stall), caption, card, wide, "wide sell")
	fits(t, UiFx, R.FormatRate(-big.income10), card.Rate, card, phone, "the red rate flash")
	fits(t, UiFx, R.FormatRate(big.income10), card.Rate, card, phone, "rate")
	fits(t, UiFx, "×3", card.Growth.Label, card, phone, "growth")
	fits(t, UiFx, TankConfig.Texts.Max, card.Growth.Max.Label, card, phone, "МАКС")
	for _, which in { "EmptyTemplate", "LockedTemplate" } do
		local slot = panel.Cards[which]
		fits(t, UiFx, slot.Title.Text, slot.Title, slot, phone, which)
		-- the hint wraps: every word fits a line, and two lines fit the box
		local box = boxOf(slot.Hint, slot, phone)
		local px = UIConfig.Type[slot.Hint:GetAttribute("TextTier")]
		for word in string.gmatch(slot.Hint.Text, "%S+") do
			t.ok(UiFx.textWidth(word, px) <= box.X, `{which} hint word «{word}»`)
		end
		t.ok(UiFx.textWidth(slot.Hint.Text, px) <= 2 * box.X and box.Y >= 2 * px, `{which} hint: two lines`)
	end
	-- The header on the phone panel (≈ 717 × 221).
	local sheet = Vector2.new(717, 221)
	local header = panel.Header
	fits(t, UiFx, header.Title.Text, header.Title, panel, sheet, "title")
	local slots = TankConfig.MaxSlots
	fits(t, UiFx, `{slots}/{slots}`, header.Count.Label, panel, sheet, "count")
	fits(t, UiFx, R.FormatRate(big.tankIncome10), header.Rate, panel, sheet, "tank income")
	fits(t, UiFx, "💵 " .. R.FormatMoney(big.tankValue) .. " ▲", header.Total, panel, sheet, "tank value")
	fits(t, UiFx, header.Market.Label.Text, header.Market.Label, panel, sheet, "market chip")
	-- The tank stamp on the catch card (wave 2 C): CatchFx.tankRow sizes its plate to its words in
	-- the close-hint row — on the smallest docked card (phone_small) the label is ≥ 12 px and holds
	-- every stamp; the builder's label shares are the ones tankRow computes with.
	local stamp = hud.Fishing.CatchCard.TankStamp
	local CatchFx = s.CatchFx
	t.ok(CatchFx.STAMP_TEXT >= 12, "the stamp is never under 12 px")
	t.near(stamp.Label.Size.Y.Scale, CatchFx.STAMP_LABEL, 1e-6, "the label's height share (tankRow)")
	t.near(stamp.Label.Size.X.Scale, CatchFx.STAMP_INNER, 1e-6, "the label's width share (tankRow)")
	local smallest = Vector2.new(260, 165)
	for _, result in { "stored", "replaced", "sold" } do
		local text = CatchFx.tankStamp({ Result = result })
		local plate, hint = stamp:Clone(), hud.Fishing.CatchCard.TapHint:Clone()
		CatchFx.tankRow(plate, hint, { Result = result }, smallest, true, smallest.X)
		local size = Vector2.new(plate.Size.X.Scale * smallest.X, plate.Size.Y.Scale * smallest.Y)
		local inner = Vector2.new(size.X * plate.Label.Size.X.Scale, size.Y * plate.Label.Size.Y.Scale)
		t.ok(inner.Y >= 12 - 1e-6, `stamp «{text}»: its label box is {math.floor(inner.Y)} px tall`)
		local w = UiFx.textWidth(text, 12)
		t.ok(w <= inner.X, `stamp «{text}»: {math.floor(w)} px fits {math.floor(inner.X)} px at 12 px`)
		plate:Destroy()
		hint:Destroy()
	end
end

tests["CatchFx.tankStamp: the result's words and colours; nothing without Tank"] = function(t)
	local CatchFx = env(t).CatchFx
	local cases = {
		{ "stored", TankConfig.Texts.Stamp.stored, "Water" },
		{ "replaced", TankConfig.Texts.Stamp.replaced, "Leaf" },
		{ "sold", TankConfig.Texts.Stamp.sold, "Gold" },
	}
	for _, case in cases do
		local text, token = CatchFx.tankStamp({ Result = case[1], Count = 1, Slots = 6 })
		t.eq(text, case[2], `{case[1]}: the words`)
		t.eq(token, case[3], `{case[1]}: the colour`)
		t.ok(UIConfig.Palette[token] ~= nil, `{token} is a palette token`)
	end
	t.eq(TankConfig.Texts.Stamp.stored, "В САДОК!")
	t.eq(TankConfig.Texts.Stamp.replaced, "ЗАМЕНА!")
	t.eq(TankConfig.Texts.Stamp.sold, "ПРОДАНА")
	for _, junk in { nil, {}, { Result = "pending" }, { Result = 5 }, "stored" } do
		local text, token = CatchFx.tankStamp(junk)
		t.eq(text, nil, `{typeof(junk)}: no stamp`)
		t.eq(token, nil)
	end
	-- (stampText, the mutation-stamp fitter, keeps its contract)
	t.eq(CatchFx.stampText("Радужная", 5, false), "РАДУЖНАЯ ×5!")
end

--------------------------------------------------------------------------------
-- The contract names
--------------------------------------------------------------------------------

tests["contract: every Stage 3 name (design §6.1, §4.5, §4.6) exists in the built place, hidden"] = function(t)
	local s = env(t)
	local sim = s.sim
	local function find(path: string): any
		local inst = sim:Find(path)
		t.ok(inst, path)
		return inst
	end
	-- Remotes (§4.5).
	for _, name in { "TankSell", "TankEvent" } do
		t.ok(find(`ReplicatedStorage.Remotes.{name}`):IsA("RemoteEvent"), `{name} is a RemoteEvent`)
	end
	-- GUI (§6.1), in StarterGui and in the player's own copy.
	local paths = {
		"Status.Wallet",
		"Status.Wallet.Money",
		"Status.Wallet.Money.Icon",
		"Status.Wallet.Money.Label",
		"Status.Wallet.Money.Back",
		"Status.Wallet.Rate",
		"RightButtons.TankButton",
		"RightButtons.TankButton.Icon",
		"RightButtons.TankButton.Caption",
		"RightButtons.TankButton.Count",
		"RightButtons.TankButton.Count.Label",
		"RightButtons.TankButton.Badge",
		"TankPanel",
		"TankPanel.Panel",
		"TankPanel.Panel.Header",
		"TankPanel.Panel.Header.Icon",
		"TankPanel.Panel.Header.Title",
		"TankPanel.Panel.Header.Count",
		"TankPanel.Panel.Header.Rate",
		"TankPanel.Panel.Header.Total",
		"TankPanel.Panel.Header.Market",
		"TankPanel.Panel.Close",
		"TankPanel.Panel.Cards",
		"TankPanel.Panel.Cards.CardTemplate",
		"TankPanel.Panel.Cards.CardTemplate.NameLabel", -- (§6.4 "Name": shadowed by Instance.Name)
		"TankPanel.Panel.Cards.CardTemplate.Viewport",
		"TankPanel.Panel.Cards.CardTemplate.Mutation",
		"TankPanel.Panel.Cards.CardTemplate.Rate",
		"TankPanel.Panel.Cards.CardTemplate.Growth",
		"TankPanel.Panel.Cards.CardTemplate.Growth.Track.Fill",
		"TankPanel.Panel.Cards.CardTemplate.Growth.Label",
		"TankPanel.Panel.Cards.CardTemplate.Growth.Max",
		"TankPanel.Panel.Cards.CardTemplate.Sell",
		"TankPanel.Panel.Cards.CardTemplate.Sell.Caption",
		"TankPanel.Panel.Cards.EmptyTemplate",
		"TankPanel.Panel.Cards.EmptyTemplate.Icon",
		"TankPanel.Panel.Cards.EmptyTemplate.Title",
		"TankPanel.Panel.Cards.EmptyTemplate.Hint",
		"TankPanel.Panel.Cards.LockedTemplate",
		"TankPanel.Panel.Cards.LockedTemplate.Icon",
		"TankPanel.Panel.Cards.LockedTemplate.Title",
		"TankPanel.Panel.Cards.LockedTemplate.Hint",
		"Fishing.CatchCard.TankStamp",
		"Fishing.CatchCard.TankStamp.Label",
	}
	for _, path in paths do
		find(`StarterGui.HUD.{path}`)
		t.ok(sim:Gui(s.p, `HUD.{path}`), `the player's HUD.{path}`)
	end
	local hud = sim:Gui(s.p, "HUD")
	for _, widget in { hud.Status.Wallet, hud.RightButtons.TankButton, hud.TankPanel, hud.Fishing.CatchCard.TankStamp } do
		t.eq(widget.Visible, false, `{widget.Name} hidden (wave 0: no visible change)`)
	end
	t.eq(hud.Status.Wallet.LayoutOrder, 30, "the Wallet takes the counter's row")
	t.eq(hud.RightButtons.TankButton.LayoutOrder, 90, "«САДОК» above «ДОМОЙ» (100)")
	t.ok(hud.RightButtons.TankButton:IsA("GuiButton"), "«САДОК» is a button")
	t.eq(hud.RightButtons.TankButton.Caption.Text, "САДОК")
	t.eq(hud.RightButtons.TankButton.Icon.Text, "🐠")
	t.eq(hud.TankPanel.ZIndex, 30, "the sheet over the fishing widgets and the banner")
	t.ok(hud.TankPanel.Panel.Close:IsA("GuiButton"), "✕ is a button")
	t.ok(hud.TankPanel.Panel.Cards.CardTemplate.Sell:IsA("GuiButton"), "Sell is a button")
	t.ok(hud.TankPanel.Panel.Cards:IsA("ScrollingFrame"), "Cards scrolls")
	t.ok(hud.TankPanel.Panel.Cards:FindFirstChildOfClass("UIGridLayout"), "… in a grid")
	t.eq(hud.TankPanel.Panel.Header.Title.Text, TankConfig.Texts.Title)
	t.eq(hud.TankPanel.Panel.Cards.EmptyTemplate.Title.Text, TankConfig.Texts.Empty)
	t.eq(hud.TankPanel.Panel.Cards.EmptyTemplate.Hint.Text, TankConfig.Texts.EmptyHint)
	t.eq(hud.TankPanel.Panel.Cards.LockedTemplate.Title.Text, TankConfig.Texts.Locked)
	t.eq(hud.TankPanel.Panel.Cards.LockedTemplate.Hint.Text, TankConfig.Texts.LockedHint)
	t.eq(hud.TankPanel.Panel.Header.Market.Visible, false, "the market chip waits for SellRatePct > 100")
	t.eq(hud.Fishing.CatchCard.TankStamp.Label.Text, TankConfig.Texts.Stamp.stored)
	-- Scale-only sizes (the spec: «UDim2 через scale»).
	for _, d in hud.TankPanel:GetDescendants() do
		if d:IsA("GuiObject") then
			t.ok(d.Size.X.Offset == 0 and d.Size.Y.Offset == 0, `{d:GetFullName()}: a scale size`)
		end
	end

	-- Server modules and their API (wave 0: signatures, no behaviour).
	local function server(name: string): any
		return sim:Require(find(`ServerScriptService.Services.{name}`))
	end
	local DataService = server("DataService")
	for _, key in
		{
			"Get",
			"IsLoaded",
			"CanWrite",
			"WaitLoaded",
			"Mode",
			"SaveSoon",
			"CommittedSeq",
			"OnSerialize",
			"_debugSizes",
			"_recordFor",
			"_saveRecordForTest",
		}
	do
		t.eq(type(DataService[key]), "function", `DataService.{key}`)
	end
	t.ok(DataService.Loaded and DataService.Loaded.Connect, "DataService.Loaded is a Signal")
	t.ok(DataService.Committed and DataService.Committed.Connect, "DataService.Committed is a Signal")
	t.eq(DataService.StoreName, "PlayerData_Studio", "the sim reports Studio")
	t.eq(type(DataService.Token), "string")
	local EconomyService = server("EconomyService")
	for _, key in { "GetMoney", "AddMoney", "SpendMoney", "CanAfford", "SetIncome", "SetMoneyForTest", "_debugSizes" } do
		t.eq(type(EconomyService[key]), "function", `EconomyService.{key}`)
	end
	t.ok(EconomyService.MoneyChanged.Connect, "EconomyService.MoneyChanged is a Signal")
	local MarketService = server("MarketService")
	for _, key in { "Sample", "RatePct", "_debugSizes" } do
		t.eq(type(MarketService[key]), "function", `MarketService.{key}`)
	end
	t.eq(MarketService:RatePct(s.p), EconomyConfig.HomeRatePct, "at home ×1")
	local TankService = server("TankService")
	for _, key in { "AddFish", "RemoveFish", "SetLocked", "SetSlots", "_debugSizes" } do
		t.eq(type(TankService[key]), "function", `TankService.{key}`)
	end
	t.ok(TankService.FishAdded.Connect and TankService.FishRemoved.Connect, "TankService signals")
	find("ServerScriptService.Lib.PlayerData")
	find("ReplicatedStorage.Shared.TankRules")
	for _, name in { "TankConfig", "EconomyConfig", "DataConfig" } do
		find(`ReplicatedStorage.Shared.Config.{name}`)
	end

	-- Client modules.
	local scripts = s.p:FindFirstChildOfClass("PlayerScripts")
	local function client(name: string): any
		local module = sim:Find(`Controllers.{name}`, scripts)
		t.ok(module, `Controllers.{name}`)
		return sim:Require(module, s.p)
	end
	t.eq(type(client("MoneyController").Celebrate), "function", "MoneyController.Celebrate")
	t.eq(type(client("TankButtonController").Start), "function")
	local panel = client("TankPanelController")
	for _, key in { "Toggle", "Open", "Close", "IsOpen" } do
		t.eq(type(panel[key]), "function", `TankPanelController.{key}`)
	end
	t.eq(panel.IsOpen(), false)
	t.eq(type(client("TankWorldController").Start), "function")
	t.eq(type(client("Sheet").new), "function", "the client Sheet helper")

	-- Boot orders (design §4.1, §6.1).
	local function inOrder(source: string, names: { string }, what: string)
		local at = 1
		for _, name in names do
			local found = string.find(source, `"{name}"`, at, true)
			t.ok(found, `{what}: {name} after the previous one`)
			at = (found or at) + 1
		end
	end
	inOrder(find("ServerScriptService.Main").Source, {
		"MapService",
		"BaseService",
		"DataService",
		"EconomyService",
		"MarketService",
		"FishingService",
		"TankService",
	}, "Main ORDER")
	inOrder(find("StarterPlayer.StarterPlayerScripts.ClientMain").Source, {
		"NotifyController",
		"HudController",
		"MoneyController",
		"TankButtonController",
		"TankPanelController",
		"TankWorldController",
		"FishingController",
	}, "ClientMain ORDER")

	-- The replicated state of §4.6 is written down where both sides read it (RemoteNames).
	local protocol = find("ReplicatedStorage.Shared.RemoteNames").Source
	for _, word in
		{
			"Money",
			"Income",
			"TankCount",
			"TankSlots",
			"SellRatePct",
			"SellPlace",
			"DataMode",
			"State",
			"FishUid",
			"FishId",
			"GrowFrom",
			"Event",
			"|in|",
			"|mount|",
			"|sold|",
			"|swap|",
			"|stolen|",
			"TankResult",
			"Stored",
			"Denied",
		}
	do
		t.ok(string.find(protocol, word, 1, true), `RemoteNames documents {word}`)
	end

	-- What TankService and MarketService will look up (§4.3, §4.4, §5.1).
	local base = sim.workspace.Bases:FindFirstChild("Base_1")
	t.ok(base, "a base")
	for i = 1, TankConfig.MaxSlots do
		local slot = base.Tank.Slots:FindFirstChild(`Slot_{i}`)
		t.ok(slot, `Slot_{i}`)
		t.eq(slot:GetAttribute("SlotIndex"), i, `Slot_{i}: SlotIndex`)
		for _, part in { "Pedestal", "Display", "LightBar" } do
			t.ok(slot:FindFirstChild(part), `Slot_{i}.{part}`)
		end
		t.ok(slot.Display:FindFirstChild("FishPoint"), `Slot_{i}.Display.FishPoint`)
		t.ok(slot.Pedestal.LabelGui:FindFirstChild("Label"), `Slot_{i}.Pedestal.LabelGui.Label`)
		t.ok(slot.Pedestal:FindFirstChild("PromptAttachment"), `Slot_{i}.Pedestal.PromptAttachment (Stage 4)`)
		t.ok(slot.LightBar:FindFirstChildOfClass("SurfaceLight"), `Slot_{i}.LightBar SurfaceLight`)
	end
	t.eq(base.Tank.Slots:FindFirstChild(`Slot_{TankConfig.MaxSlots + 1}`), nil, "MaxSlots = the displays built")
	t.ok(base.Tank.Glass:FindFirstChild("PromptAttachment"), "Tank.Glass.PromptAttachment (TankPrompt)")
	t.ok(base:FindFirstChild("Platform") and base.Platform:FindFirstChild("Bucket"), "Platform.Bucket (the pier word)")
	for _, point in EconomyConfig.SellPoints do
		local node = sim.workspace
		for part in string.gmatch(point.Path, "[^%.]+") do
			node = node and node:FindFirstChild(part)
		end
		t.ok(node and node:IsA("Attachment"), `{point.Id}: Workspace.{point.Path}`)
	end
	sim:AssertNoErrors({ warnings = true })
end

return tests
