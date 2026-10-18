--[[
	Stage 4 wave 0 — the server hooks the transfer protocol stands on (docs/stage4_design.md §4.6,
	§3.3 F8b / F8c / F9 / F9'), run inside RbxSim against the built Place1.rbxl with headless players
	(no client) and the sim DataStore; the theft itself is Wave 1 A's (tests/stage4_data):
	  • DataService.Released fires once per record, with its committed seq, and only after the
	    final save; AmendLeaving runs while the record is Leaving and the final snapshot is not taken
	    (also while that request is in flight but its transform has not run), its rows reach the final
	    save, and it is refused once the record is gone;
	  • a failed final attempt (the transform ran, the store rejected the value: an invalid UTF-8
	    unknown field → 104 → the strict retry) voids its snapshot: FinalTaken is cleared, an
	    AmendLeaving between the attempts runs and its row is in the committed retry (W0 review: the
	    F8c window stays one request, not every retry);
	  • DataService:OnClose hooks run once, first and synchronously in the close: with the close first
	    the record is still Ready and writable inside the hook, with the players removed first (S6)
	    it is already leaving; Released once per record in both orders;
	  • BaseService:SetHomeGuard returning a CFrame lands «ДОМОЙ» there and spends the Home cooldown
	    (the next request inside it does not move the player).
	Every test asserts no unexpected warnings.

	Run: lune run tools/run_tests.luau stage4_data_hooks
]]

local roblox = require("@lune/roblox")

local Kit = require("./stage4_kit")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local GAP = Kit.GAP
local COARSE = Kit.COARSE

local tests = {}

-- A headless player (no client), waited until its data is loaded.
local function addPlayer(t: any, sim: any, id: number): any
	local p = sim:AddPlayer({ UserId = id, Name = `Player{id}`, DisplayName = `Игрок{id}`, clientDelay = 1e9 })
	local loaded = sim:WaitFor(function()
		return p:GetAttribute("DataMode") ~= nil and p:GetAttribute("DataMode") ~= "Loading"
	end, 10, COARSE)
	t.ok(loaded, `{p.Name}: loaded`)
	t.eq(p:GetAttribute("DataMode"), "Ready", `{p.Name}: DataStore mode`)
	sim:Advance(0.1)
	return p
end

-- One committed save (the lock is ours, the key's pause starts now).
local function commitOnce(t: any, sim: any, data: any, p: any): number
	local before = data:CommittedSeq(p)
	sim:Run(function()
		data:SaveSoon(p)
	end)
	local ok = sim:WaitFor(function()
		return data:CommittedSeq(p) > before
	end, 2 * GAP + 2, COARSE)
	t.ok(ok, "a save committed")
	return data:CommittedSeq(p)
end

local function uids(saved: any): { [string]: boolean }
	local out = {}
	for _, fish in (saved and saved.Tank) or {} do
		out[fish.Uid] = true
	end
	return out
end

local function releasedLog(data: any): { any }
	local log = {}
	data.Released:Connect(function(who: any, committed: number)
		table.insert(log, { who = who, committed = committed })
	end)
	return log
end

--------------------------------------------------------------------------------
-- Released and AmendLeaving
--------------------------------------------------------------------------------

tests["Released once per record with its seq; AmendLeaving until the final snapshot, its rows saved"] = function(t)
	local sim = Kit.boot(t)
	local Data = Kit.service(sim, "DataService")
	local released = releasedLog(Data)
	local p = addPlayer(t, sim, 401)
	local committed = commitOnce(t, sim, Data, p)
	t.eq(
		Data:AmendLeaving(p, function()
			error("must not run for a player who is still playing")
		end),
		false,
		"AmendLeaving: not while playing"
	)

	-- The leave: the final save waits for the key's pause, then its request takes 3 s.
	sim.DataStore:SetKeyLatency(Kit.key(401), 3)
	sim:RemovePlayer(p)
	local rec = Data._recordFor(p)
	t.eq(rec and rec.State, "Leaving", "Leaving at once")
	t.eq(rec and rec.FinalTaken, false, "… no snapshot yet")
	t.eq(
		Data:AmendLeaving(p, function(data: any)
			table.insert(data.Tank, Kit.savedFish("Perch", "f50", 6))
		end),
		true,
		"AmendLeaving runs right after the leave"
	)
	sim:Advance(GAP, COARSE) -- the pause is over: the request is in flight, its transform not run yet
	t.eq(Data._recordFor(p) and Data._recordFor(p).FinalTaken, false, "in flight, the snapshot not taken")
	t.eq(
		Data:AmendLeaving(p, function(data: any)
			table.insert(data.Tank, Kit.savedFish("Crucian", "f51", 5))
		end),
		true,
		"… so AmendLeaving still runs"
	)
	t.eq(#released, 0, "Released only after the final save")
	local gone = sim:WaitFor(function()
		return Data._recordFor(p) == nil
	end, 20, COARSE)
	t.ok(gone, "the record released")
	t.eq(
		Data:AmendLeaving(p, function()
			error("must not run after the release")
		end),
		false,
		"AmendLeaving refused once the record is gone"
	)
	sim:Advance(10, COARSE)
	t.eq(#released, 1, "Released exactly once")
	t.ok(released[1] and released[1].who == p, "… for that player")
	t.ok(released[1] and released[1].committed >= committed, "… with its committed seq")
	local saved = Kit.peek(sim, 401)
	local have = uids(saved)
	t.ok(have.f50 and have.f51, "both amended rows reached the final save")
	t.eq(saved and saved.Session, nil, "the lock released")
	Kit.ledgerHolds(t, sim, saved, "the final save")
	sim:AssertNoErrors({ warnings = true })
end

tests["a failed final attempt voids its snapshot: FinalTaken cleared, an AmendLeaving between the attempts is saved"] = function(
	t
)
	local sim = Kit.boot(t)
	local Data = Kit.service(sim, "DataService")
	local released = releasedLog(Data)
	local p = addPlayer(t, sim, 402)
	commitOnce(t, sim, Data, p)
	-- An unknown field the store rejects AFTER the transform ran (invalid UTF-8 → 104): the first
	-- final attempt takes its snapshot (FinalTaken) and fails; the strict retry drops the field.
	Data:Get(p).Future = "\xff\xfe"
	sim:RemovePlayer(p)
	local retrying = sim:WaitFor(function()
		local r = Data._recordFor(p)
		return r ~= nil and r.Strict == true
	end, 2 * GAP + 4, COARSE)
	t.ok(retrying, "the first final attempt failed (104) and the strict retry waits for the pause")
	local rec = Data._recordFor(p)
	t.eq(rec and rec.State, "Leaving", "still Leaving")
	t.eq(rec and rec.FinalTaken, false, "the failed attempt's snapshot is void: FinalTaken cleared")
	t.eq(
		Data:AmendLeaving(p, function(data: any)
			table.insert(data.Tank, Kit.savedFish("Perch", "f60", 6))
		end),
		true,
		"AmendLeaving runs between the attempts"
	)
	local gone = sim:WaitFor(function()
		return Data._recordFor(p) == nil
	end, 2 * GAP + 4, COARSE)
	t.ok(gone, "the strict retry committed and released the record")
	local saved = Kit.peek(sim, 402)
	t.ok(uids(saved).f60, "the amended row is in the committed retry")
	t.eq(saved and saved.Future, nil, "strict: the rejected field dropped")
	t.eq(saved and saved.Session, nil, "the lock released")
	sim:Advance(5, COARSE)
	t.eq(#released, 1, "Released exactly once")
	t.eq(
		Kit.takeWarnings(sim, "повтор без незнакомых полей"),
		1,
		"one warn for the rejected save"
	)
	t.eq(
		Kit.takeWarnings(sim, "Future: незнакомое поле → выброшено (strict)"),
		1,
		"what strict dropped is logged"
	)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- OnClose
--------------------------------------------------------------------------------

tests["OnClose hooks: once, first and synchronously in the close (both shutdown orders)"] = function(t)
	for _, order in { "closeFirst", "playersFirst" } do
		local sim = Kit.boot(t)
		local Data = Kit.service(sim, "DataService")
		local released = releasedLog(Data)
		local p = addPlayer(t, sim, 403)
		local q = addPlayer(t, sim, 404)
		local calls = 0
		local seen: { [string]: any } = {}
		Data:OnClose(function()
			calls += 1
			local r = Data._recordFor(p)
			seen.state = r and r.State
			seen.canWrite = Data:CanWrite(p)
			seen.amend = Data:AmendLeaving(q, function() end)
		end)
		sim:Advance(1, COARSE)
		local result = sim:Shutdown({ order = order })
		t.log(order, "state", seen.state, "canWrite", tostring(seen.canWrite), "completed", tostring(result.completed))
		t.eq(calls, 1, `{order}: the hook ran once`)
		if order == "closeFirst" then
			t.eq(seen.state, "Ready", "closeFirst: the record is still Ready in the hook")
			t.eq(seen.canWrite, true, "closeFirst: still writable in the hook")
			t.eq(seen.amend, false, "closeFirst: nobody is leaving yet")
		else
			t.ok(seen.state ~= "Ready", "playersFirst: the players left before the close")
			t.eq(seen.canWrite, false, "playersFirst: no longer writable")
		end
		sim:Advance(30, COARSE)
		local per = {}
		for _, entry in released do
			per[entry.who] = (per[entry.who] or 0) + 1
		end
		t.eq(per[p], 1, `{order}: Released once for the first player`)
		t.eq(per[q], 1, `{order}: … and once for the second`)
		for _, id in { 403, 404 } do
			t.eq(Kit.peek(sim, id).Session, nil, `{order}: lock {id} released`)
		end
		sim:AssertNoErrors({ warnings = true })
	end
end

--------------------------------------------------------------------------------
-- The home guard
--------------------------------------------------------------------------------

tests["SetHomeGuard: a CFrame lands «ДОМОЙ» there and spends the Home cooldown"] = function(t)
	local sim = Kit.boot(t)
	local p = Kit.join(t, sim, 405, "desktop")
	local BaseService = Kit.service(sim, "BaseService")
	local base = Kit.baseOf(sim, p)
	local target = base:GetPivot() * CFrame.new(10, 3, 60)
	local asked = 0
	BaseService:SetHomeGuard(function(_who: any): (string?, any)
		asked += 1
		return nil, target
	end)
	local away = base:GetPivot() * Vector3.new(0, 3, -200)
	sim:Teleport(p, away)
	sim:Advance(0.2)
	sim:FireServer(p, "RequestHome")
	sim:Advance(0.3)
	local root = p.Character.HumanoidRootPart
	t.eq(asked, 1, "the guard asked once")
	t.ok((root.Position - target.Position).Magnitude < 0.5, `landed at the guard's CFrame ({root.Position})`)
	-- The cooldown was spent: a second request inside it does not move the player.
	sim:Teleport(p, away)
	sim:Advance(0.2)
	sim:FireServer(p, "RequestHome")
	sim:Advance(0.3)
	t.ok((root.Position - away).Magnitude < 0.5, "inside the Home cooldown: no second teleport")
	BaseService:SetHomeGuard(nil)
	sim:AssertNoErrors({ warnings = true })
end

return tests
