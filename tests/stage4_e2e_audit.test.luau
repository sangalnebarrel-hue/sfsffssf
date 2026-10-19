--[[
	Stage 4 END-TO-END, part 5 — the budget and leak audit (docs/stage4_design.md §8 Wave 3 E, §5.5,
	§3.4 #5, R17): the real server and the REAL clients of a phone thief, a tablet victim with the
	dog and the alarm, and a desktop bystander at the victim's gate (tests/stage4_e2e_kit.luau). It
	measures what a theft costs and checks that it all goes away again; the numbers are printed
	(run with --verbose) for the integration report.

	  • the parts each client sees (the server's parts + the ones that client made; RbxSim shares one
	    DataModel, so another client's local parts are left out) before, at the theft's peak (the
	    dog awake, the siren spinning, the Highlight, the carry with the guide, then the owner's
	    shield in the carry: the dome and the fish flying home) and after: the theft's own parts
	    within MapConfig.PartBudget.RuntimeReserve.Theft (60) on every client, and the absolute peak
	    within RuntimePeak (26 500);
	  • Highlights: at most one per active thief, on every client; domes: at most Dome.PhoneMax on
	    the phone (and the map's geometry: adjacent courts are farther apart than Dome.Range, so a
	    client sees at most two domes anywhere);
	  • idle: no frame connection (RenderStepped / Heartbeat / Stepped / PreRender) left on any client
	    and no UiFx job; StealService's watcher stopped (no loop without a theft or an awake dog);
	    DefenceService's intruder loop only while an alarmed base is mounted (1 Hz, never per frame)
	    and stopped after its owner leaves;
	  • connections: the server's back to the count before the theft, and to the count before the
	    joins after everybody leaves; the per-player tables (_debugSizes) zero 10 s after the last
	    player left, the time-bounded maps zero once their windows passed (VictimWindow).

	Run: lune run tools/run_tests.luau stage4_e2e_audit --verbose
]]

local roblox = require("@lune/roblox")

local E = require("./stage4_e2e_kit")

local Vector3 = roblox.Vector3

local tests = {}

local FRAME_SIGNALS = { "RenderStepped", "Heartbeat", "Stepped", "PreRender" }

local function frameConnections(sim: any, p: any?): number
	local ctx = sim:ContextName(p)
	return sim:CountConnections(function(conn: any): boolean
		if conn.ctx.name ~= ctx then
			return false
		end
		local what = conn.signal:describe()
		for _, name in FRAME_SIGNALS do
			if string.find(what, name, 1, true) then
				return true
			end
		end
		return false
	end)
end

local function contextConnections(sim: any, p: any?): number
	local ctx = sim:ContextName(p)
	return sim:CountConnections(function(conn: any): boolean
		return conn.ctx.name == ctx
	end)
end

-- Who made this instance (a client context) — nil: the server (replicated to everyone).
local function creatorOf(sim: any, real: any): any
	local cur = real
	while cur ~= nil do
		local ctx = sim.proxy.createdBy[cur]
		if ctx ~= nil then
			return ctx
		end
		cur = cur.Parent
	end
	return nil
end

-- What one client sees: { parts, highlights, domes } (server parts + its own; nil = the server).
local function seenBy(sim: any, p: any?): { [string]: number }
	local ctx = if p then sim:_ctxFor(p) else nil
	local out = { parts = 0, highlights = 0, own = 0 }
	for _, d in sim.workspace:GetDescendants() do
		local isPart = d:IsA("BasePart")
		local isHighlight = d:IsA("Highlight")
		if isPart or isHighlight then
			local creator = creatorOf(sim, sim:Unwrap(d))
			if creator == nil or creator == ctx then
				if isPart then
					out.parts += 1
					if creator ~= nil then
						out.own += 1
					end
				else
					out.highlights += 1
				end
			end
		end
	end
	return out
end

local function report(lines: { string }, text: string)
	table.insert(lines, text)
	print(text)
end

tests["audit: a theft with the dog, the siren, the Highlight, the guide and then the shield dome — parts within the Theft reserve, one Highlight, nothing left running, no connection growth, zero tables after leave"] = function(
	t
)
	local MapConfig = E.MapConfig
	local RESERVE = MapConfig.PartBudget.RuntimeReserve.Theft
	local PEAK = MapConfig.PartBudget.RuntimePeak
	local lines = {}
	local cast = E.trio(t, {
		quick = true,
		victim = { upgrades = { Dog = true, Alarm = true } },
		patches = {},
	})
	local sim, victim, thief, bystander = cast.sim, cast.victim, cast.thief, cast.bystander
	local base = E.baseOf(sim, victim)
	local steal = E.service(sim, "StealService")
	local defence = E.service(sim, "DefenceService")
	local players = { thief = thief, victim = victim, bystander = bystander }
	sim:Teleport(bystander, E.exitPoint(base, "gate") + Vector3.new(14, 0, -6))
	local prompt = E.toCourt(t, sim, thief, victim, 3)
	sim:Advance(2)

	-- Before: per client, the server.
	local before, framesBefore = {}, {}
	for role, p in players do
		before[role] = seenBy(sim, p)
		framesBefore[role] = frameConnections(sim, p)
	end
	local serverConns0 = contextConnections(sim, nil)
	t.eq(steal._debugSizes().Watcher, 0, "idle: StealService's watcher is not running")
	t.eq(defence._debugSizes().IntruderLoop, 1, "the intruder loop runs: an alarmed base is mounted (1 Hz)")
	local serverFrames0 = frameConnections(sim, nil) -- (FishingService's stage 2 Heartbeat watch: always one)
	report(
		lines,
		string.format(
			"before: parts seen thief %d (own %d), victim %d (own %d), bystander %d (own %d); frame connections thief %d, victim %d, bystander %d, server %d; server connections %d",
			before.thief.parts,
			before.thief.own,
			before.victim.parts,
			before.victim.own,
			before.bystander.parts,
			before.bystander.own,
			framesBefore.thief,
			framesBefore.victim,
			framesBefore.bystander,
			frameConnections(sim, nil),
			serverConns0
		)
	)

	-- The theft: sample every 0.1 s through the hold, the carry and the shield's return.
	local peak = { thief = 0, victim = 0, bystander = 0 }
	local peakOwn = { thief = 0, victim = 0, bystander = 0 }
	local highlights = { thief = 0, victim = 0, bystander = 0 }
	local domes = { thief = 0, victim = 0, bystander = 0 }
	local watcherSeen = 0
	local serverFramesMax = 0
	local function sample()
		for role, p in players do
			local seen = seenBy(sim, p)
			peak[role] = math.max(peak[role], seen.parts)
			peakOwn[role] = math.max(peakOwn[role], seen.own - before[role].own)
			highlights[role] = math.max(highlights[role], seen.highlights)
			local stats = E.worldStats(sim, p)
			domes[role] = math.max(domes[role], stats.domes)
		end
		watcherSeen = math.max(watcherSeen, steal._debugSizes().Watcher)
		serverFramesMax = math.max(serverFramesMax, frameConnections(sim, nil))
	end
	local hold = sim:BeginHold(thief, prompt)
	t.ok(hold.active, "the hold began")
	sim:WaitFor(function()
		sample()
		return thief:GetAttribute("Stealing") == "carry"
	end, prompt.HoldDuration + 1, 0.1)
	t.eq(thief:GetAttribute("Stealing"), "carry", "the carry")
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	t.ok(thief:GetAttribute("Slowed") == true, "the dog has him")
	E.moveTo(sim, thief, E.exitPoint(base, "gate"))
	sim:WaitFor(function()
		sample()
		return false
	end, 1.2, 0.1)
	t.ok(E.alert(sim, victim).shown ~= nil, "the victim's alert is up")
	E.shieldTap(sim, victim, "plate")
	sim:WaitFor(function()
		sample()
		return false
	end, 2.5, 0.1)
	t.eq(thief:GetAttribute("Stealing"), nil, "the shield returned the fish")
	t.eq(watcherSeen, 1, "the watcher ran during the theft")
	t.eq(serverFramesMax, serverFrames0, "… as a task.wait loop: no frame connection on the server during the theft")
	for role in players do
		t.ok(peakOwn[role] <= RESERVE, `{role}: the theft's own parts {peakOwn[role]} ≤ the Theft reserve {RESERVE}`)
		t.ok(peak[role] <= PEAK, `{role}: the peak {peak[role]} ≤ RuntimePeak {PEAK}`)
		t.ok(highlights[role] <= 1, `{role}: ≤ one Highlight for one thief ({highlights[role]})`)
		t.ok(domes[role] <= E.DefenceConfig.World.Dome.PhoneMax, `{role}: domes {domes[role]}`)
	end
	t.ok(highlights.bystander == 1 and highlights.victim == 1, "the thief was marked for the bystander and the owner")
	t.eq(domes.bystander, 1, "the bystander saw the dome")
	report(
		lines,
		string.format(
			"peak during the theft: parts seen thief %d (+%d own), victim %d (+%d own), bystander %d (+%d own) of RuntimePeak %d, Theft reserve %d; Highlights thief %d, victim %d, bystander %d; domes thief %d, victim %d, bystander %d",
			peak.thief,
			peakOwn.thief,
			peak.victim,
			peakOwn.victim,
			peak.bystander,
			peakOwn.bystander,
			PEAK,
			RESERVE,
			highlights.thief,
			highlights.victim,
			highlights.bystander,
			domes.thief,
			domes.victim,
			domes.bystander
		)
	)

	-- After: the dog home, the lamp out; nothing per frame left anywhere.
	sim:Advance(E.StealConfig.Alarm.Linger + 8)
	t.eq(steal._debugSizes().Watcher, 0, "the watcher stopped (the dog asleep)")
	t.eq(base.Dog:GetAttribute("DogState"), "Sleep", "the dog sleeps")
	for role, p in players do
		local ui = E.shared(sim, "UiFx", p)
		t.eq(ui.activeJobs(), 0, `{role}: no UiFx job left`)
		t.eq(frameConnections(sim, p), framesBefore[role], `{role}: frame connections back to {framesBefore[role]}`)
		local seen = seenBy(sim, p)
		t.ok(seen.own <= before[role].own + 1, `{role}: own parts back ({seen.own} vs {before[role].own})`)
		t.eq(seen.highlights, 0, `{role}: no Highlight left`)
	end
	local serverConns1 = contextConnections(sim, nil)
	t.eq(serverConns1, serverConns0, `the server's connections back to {serverConns0}`)
	t.eq(frameConnections(sim, nil), serverFrames0, "the theft left no frame connection on the server")
	report(
		lines,
		string.format(
			"after the theft: server connections %d (before %d); frame connections thief %d, victim %d, bystander %d; watcher %d, intruder loop %d",
			serverConns1,
			serverConns0,
			frameConnections(sim, thief),
			frameConnections(sim, victim),
			frameConnections(sim, bystander),
			steal._debugSizes().Watcher,
			defence._debugSizes().IntruderLoop
		)
	)

	-- Everyone leaves: the intruder loop stops, the tables empty.
	for _, p in players do
		sim:RemovePlayer(p)
	end
	sim:Advance(10, E.COARSE)
	t.eq(defence._debugSizes().IntruderLoop, 0, "the intruder loop stopped with the alarmed base gone")
	local serverConns2 = contextConnections(sim, nil)
	local sizes = {}
	for _, name in { "StealService", "DefenceService", "TankService", "DataService" } do
		for k, v in E.service(sim, name)._debugSizes() do
			if v ~= 0 then
				table.insert(sizes, `{name}.{k}={v}`)
			end
		end
	end
	report(
		lines,
		string.format(
			"10 s after everyone left: server connections %d; non-zero _debugSizes: %s",
			serverConns2,
			if #sizes > 0 then table.concat(sizes, ", ") else "none"
		)
	)
	sim:Advance(E.LIMITS.VictimWindow + 1, 1)
	E.sizesZero4(t, sim, `{E.LIMITS.VictimWindow} s after everyone left`)
	t.ok(serverConns2 <= serverConns0, `the server's connections after leave {serverConns2} ≤ {serverConns0}`)
	sim:AssertNoErrors({ warnings = true })
end

return tests
