--[[
	World FX of fishing: FishingService's FishFx broadcast + FishingFxController on every client,
	run in RbxSim against the built Place1.rbxl with the real server and real clients (nothing
	stubbed except FishingService.RollFishForTest, which forces the species).

	What is checked:
	  • FishFx is set before FishingState goes "Idle" ("<n>|caught|<Id>|<Mutation>|<Rarity>",
	    "<n>|lost|…"), so clients still see the bobber on the water;
	  • the caught fish (a client-side copy of Assets.Fish.<Id>.<Mutation>) leaps from the bobber's
	    water point in an arc and lands exactly where the server's HeldFish appears (LeapTime after
	    the catch), then disappears; the bobber flies with it and is gone after the leap;
	  • rarity aura on the held fish (Rare and up); Legendary/Mythic: pillar, confetti, ground wave;
	  • a lost fish: a small fish dives away from the fisher under the water;
	  • cast trail, landing splash rings, waiting ripples, the bouncing «!» and the pulsing line;
	  • budgets: ≤ Fx.MaxEmitters ParticleEmitters per fisher, every FX part anchored without
	    collisions/queries/touch/shadows, nothing left in Workspace.FishingFx afterwards, no
	    RenderStepped and no extra connections when idle; viewers farther than Fx.Range see only
	    the pillar; a leaving fisher's FX disappear on other clients; late joiners do not replay.

	Run: lune run tools/run_tests.luau fishing_fx
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local PLACE = "Place1.rbxl"
local FRAME = 1 / 60
local COARSE = 0.05

-- Pure config modules are read straight from src/ (same values the game uses).
local function loadConfig(name: string): any
	local path = `src/ReplicatedStorage/Shared/Config/{name}.luau`
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum },
		injectGlobals = true,
	})
	return chunk()
end

local FishingConfig = loadConfig("FishingConfig")
local Fx = FishingConfig.Fx

local Vector3 = roblox.Vector3

--------------------------------------------------------------------------------
-- Sim helpers
--------------------------------------------------------------------------------

local function boot(t: any): any
	local sim = t.sim({ place = PLACE })
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

local function addPlayer(sim: any, id: number): any
	local player = sim:AddPlayer({ UserId = id, Name = `Player{id}`, DisplayName = `Игрок{id}`, device = "phone" })
	sim:Advance(0.5)
	return player
end

local function service(sim: any): any
	return sim:Require(sim:Find("ServerScriptService.Services.FishingService"))
end

local function rules(sim: any): any
	return sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"))
end

local function clientFx(sim: any, player: any): any
	local module = sim:Find("Controllers.FishingFxController", player:FindFirstChildOfClass("PlayerScripts"))
	assert(module, "FishingFxController in PlayerScripts")
	return sim:Require(module, player)
end

local function spotOf(sim: any, player: any): any
	local base = sim.workspace.Bases:FindFirstChild(`Base_{player:GetAttribute("BaseIndex")}`)
	assert(base, `{player.Name}: own base`)
	return base.FishingSpot
end

-- On its own fishing spot with the rod in hand.
local function ready(sim: any, player: any)
	sim:Teleport(player, spotOf(sim, player).Position + Vector3.new(0, 3, 0))
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		for _, item in container:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute("RodId") ~= nil then
				sim:EquipTool(player, item)
				return
			end
		end
	end
	error("no rod")
end

-- The viewer stands next to the fisher (well within Fx.Range).
local function standBeside(sim: any, viewer: any, fisher: any)
	sim:Teleport(viewer, spotOf(sim, fisher).Position + Vector3.new(5, 3, 5))
end

local function forceFish(sim: any, id: string, mutation: string?): any
	local fr = rules(sim)
	local def = fr.GetFish(id)
	local value, income = fr.Price(id, def.MinKg, mutation)
	local fish = { Id = id, Rarity = def.Rarity, Mutation = mutation, Kg = def.MinKg, Value = value, Income = income }
	service(sim).RollFishForTest = function()
		return table.clone(fish)
	end
	return fish
end

local function stateEvents(sim: any, player: any): { any }
	return sim:ClientEventsFor(player, "FishingState")
end

-- Steps frame by frame (calling each(), if given) until the FishingState event after number
-- `start` (sim:FireServer runs the server handler at once: count the events before firing).
local function nextState(
	sim: any,
	player: any,
	start: number,
	timeout: number,
	each: (() -> ())?
): (string?, any, number?)
	local entry = sim:WaitFor(function()
		if each then
			each()
		end
		return stateEvents(sim, player)[start + 1]
	end, timeout, FRAME)
	if not entry then
		return nil, nil, nil
	end
	return entry.args[1], entry.args[2], entry.time
end

-- Cast, wait for the bite (each() every frame), hook: returns the "Minigame" payload and time.
local function startMinigame(t: any, sim: any, player: any, each: (() -> ())?): (any, number)
	sim:FireServer(player, "FishingCast")
	t.eq(player:GetAttribute("FishingState"), "Waiting", "cast accepted")
	local bite = nextState(sim, player, #stateEvents(sim, player), 10, each)
	t.eq(bite, "Bite", "the fish bites")
	sim:Advance(0.2)
	local count = #stateEvents(sim, player)
	sim:FireServer(player, "FishingHook")
	local name, data, time = nextState(sim, player, count, 1, each)
	t.eq(name, "Minigame", "hooked")
	return data, time :: number
end

-- A moment (minigame time ≥ from) when the needle is well inside / clearly outside the zone.
local function findMoment(sim: any, mg: any, center: number, from: number, wantHit: boolean): number
	local fr = rules(sim)
	local half = mg.ZoneWidth / 2
	local t = from
	while t < from + 8 do
		local d = math.abs(fr.Needle(mg.U0, mg.Speed, t) - center)
		if (wantHit and d <= half * 0.6) or (not wantHit and d >= half + 0.05) then
			return t
		end
		t += 0.005
	end
	error("no such moment")
end

-- Plays the minigame like a perfect (or, with miss, a clumsy) zero-latency client, frame by
-- frame (each() every frame). Returns the final event name and the sim time of the catch / loss.
local function playMinigame(
	sim: any,
	player: any,
	mg: any,
	startTime: number,
	miss: boolean?,
	each: (() -> ())?
): (string?, number)
	local center = mg.ZoneCenter
	local from = FishingConfig.TapInterval + 0.02
	if miss then
		from = FishingConfig.HookTapGrace + 0.05
	end
	for _ = 1, mg.HitsNeeded do
		local moment = findMoment(sim, mg, center, from, not miss)
		sim:WaitFor(function()
			if each then
				each()
			end
			return sim:Time() >= startTime + moment - 1e-9
		end, 10, FRAME)
		local count = #stateEvents(sim, player)
		sim:FireServer(player, "FishingTap", moment)
		local name, data, time = nextState(sim, player, count, 0.2, each)
		if name ~= "Zone" then
			return name, time :: number
		end
		center = data.ZoneCenter
		from = moment + FishingConfig.TapInterval + 0.02
	end
	error("the minigame did not end")
end

-- Records the order of FishFx / FishingState changes on the fisher (harness connection).
local function watchOrder(player: any): ({ string }, any)
	local order = {}
	local connection = player.AttributeChanged:Connect(function(name: string)
		if name == "FishFx" or name == "FishingState" then
			table.insert(order, name)
		end
	end)
	return order, connection
end

local function lastIndex(list: { string }, value: string): number?
	for i = #list, 1, -1 do
		if list[i] == value then
			return i
		end
	end
	return nil
end

local function renderSteppedCount(sim: any, viewer: any): number
	local ctxName = sim:ContextName(viewer)
	return sim:CountConnections(function(conn: any)
		return conn.ctx.name == ctxName and string.find(conn.signal:describe(), "RenderStepped", 1, true) ~= nil
	end)
end

local function findEffect(fx: any, player: any, name: string): any
	for _, instance in fx.GetEffects(player) do
		if instance.Name == name then
			return instance
		end
	end
	return nil
end

-- Every FishingFx folder (one per client) is empty.
local function fxFoldersEmpty(sim: any): (boolean, string)
	for _, folder in sim.workspace:GetChildren() do
		if folder.Name == "FishingFx" and #folder:GetChildren() > 0 then
			local names = {}
			for _, child in folder:GetChildren() do
				table.insert(names, child.Name)
			end
			return false, table.concat(names, ", ")
		end
	end
	return true, ""
end

local function flat(v: any): any
	return Vector3.new(v.X, 0, v.Z)
end

-- Audits the fisher's FX on a viewer's client every frame: names seen, the emitter budget, and
-- that every FX part is anchored and quiet (no collisions, queries, touch, shadows).
local function auditor(fx: any, fisher: any): any
	local audit = { seen = {}, maxEmitters = 0, maxApi = 0, loud = {}, pillarHeight = 0 }
	function audit.step()
		local emitters = 0
		local bobber = fx.GetBobber(fisher)
		if bobber then
			for _, d in bobber:GetDescendants() do
				if d:IsA("ParticleEmitter") then
					emitters += 1
				end
			end
		end
		for _, instance in fx.GetEffects(fisher) do
			audit.seen[instance.Name] = true
			local items = instance:GetDescendants()
			table.insert(items, instance)
			for _, d in items do
				if d:IsA("ParticleEmitter") then
					emitters += 1
				elseif d:IsA("BasePart") then
					if not d.Anchored or d.CanCollide or d.CanQuery or d.CanTouch or d.CastShadow then
						audit.loud[d.Name] = true
					end
				end
			end
			if instance.Name == "PillarCore" then
				audit.pillarHeight = math.max(audit.pillarHeight, instance.Size.X)
			end
		end
		audit.maxEmitters = math.max(audit.maxEmitters, emitters)
		audit.maxApi = math.max(audit.maxApi, fx.CountEmitters(fisher))
	end
	return audit
end

local function keys(set: { [string]: boolean }): string
	local list = {}
	for name in set do
		table.insert(list, name)
	end
	table.sort(list)
	return table.concat(list, ", ")
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

local tests = {}

tests["catch: FishFx before Idle; the fish leaps from the bobber to exactly where the held fish hangs"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "Puffer") -- Rare: one hit, an aura above the head
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local fx = clientFx(sim, watcher)
	local template = sim:Find("ReplicatedStorage.Assets.Fish.Puffer.Normal")

	local mg, startTime = startMinigame(t, sim, fisher)
	local order, connection = watchOrder(fisher)
	local bobberAt = nil
	local name, caughtAt = playMinigame(sim, fisher, mg, startTime, false, function()
		local bobber = fx.GetBobber(fisher)
		if bobber and fisher:GetAttribute("FishingState") == "Reeling" then
			bobberAt = bobber:GetPivot().Position
		end
	end)
	t.eq(name, "Caught")
	sim:Flush()
	connection:Disconnect()
	local fxAt, idleAt = lastIndex(order, "FishFx"), lastIndex(order, "FishingState")
	t.ok(fxAt and idleAt and fxAt < idleAt, `FishFx is set before FishingState goes Idle ({table.concat(order, ", ")})`)
	local value = fisher:GetAttribute("FishFx")
	t.ok(string.match(value, "^%d+|caught|Puffer||Rare$") ~= nil, `FishFx = «{value}»`)
	t.eq(fisher.Character:FindFirstChild("HeldFish"), nil, "nothing above the head while the fish is in the air")
	t.ok(bobberAt ~= nil, "the watcher saw the bobber on the water")

	-- Follow the leap on the watcher's client, frame by frame.
	local leap, path, heldAt = nil, {}, nil
	local quiet = true
	local head = fisher.Character.Head
	sim:WaitFor(function()
		leap = leap or findEffect(fx, fisher, "Leap")
		if leap and leap.Parent then
			local box = leap:GetBoundingBox()
			table.insert(path, { time = sim:Time(), pivot = leap:GetPivot(), center = box.Position })
			for _, d in leap:GetDescendants() do
				if
					d:IsA("BasePart") and (not d.Anchored or d.CanCollide or d.CanQuery or d.CanTouch or d.CastShadow)
				then
					quiet = false
				end
			end
		end
		if not heldAt and fisher.Character:FindFirstChild("HeldFish") then
			heldAt = sim:Time()
		end
		return heldAt ~= nil and leap ~= nil and leap.Parent == nil
	end, FishingConfig.LeapTime + 1, FRAME)
	t.ok(leap, "a leaping copy of the caught fish on the watcher's client")
	t.eq(leap:GetAttribute("Kind"), template:GetAttribute("Kind"), "the caught species (Assets.Fish.Puffer.Normal)")
	t.ok(quiet, "the leaping fish is anchored, without collisions, queries, touch or shadows")
	t.ok(#path >= 40, `the leap runs every frame ({#path} frames)`)

	local first = path[1]
	t.ok(flat(first.center - bobberAt).Magnitude < 1.5, "it leaves the water where the bobber was")
	t.ok(first.center.Y < 1 and first.center.Y > -3, `out of the water at the waterline (y = {first.center.Y})`)
	local top = -math.huge
	for _, point in path do
		top = math.max(top, point.center.Y)
	end
	t.ok(top > head.Position.Y + 3, `a high arc above the fisher's head (top {top}, head {head.Position.Y})`)

	local held = fisher.Character:FindFirstChild("HeldFish")
	t.ok(held, "the server's held fish appeared")
	t.ok(heldAt >= caughtAt + FishingConfig.LeapTime - FRAME, "…LeapTime after the catch")
	t.ok(heldAt <= caughtAt + FishingConfig.LeapTime + 3 * FRAME, "…not later")
	local last = path[#path]
	t.near(last.pivot, held:GetPivot(), 0.02, "the leap ends exactly where the held fish hangs")
	t.ok(last.time >= heldAt - 1e-9, "the copy disappears only when the held fish is there")
	t.eq(leap.Parent, nil, "the copy is gone")
	t.eq(fx.GetBobber(fisher), nil, "the bobber flew in with the fish and is gone")

	-- Rare: sparkles (and a glow) around the held fish on the watcher's client.
	local aura = findEffect(fx, fisher, "RarityAura")
	t.ok(aura and aura:IsA("ParticleEmitter"), "a rarity aura on the held fish")
	t.ok(aura.Parent == held.PrimaryPart, "attached to the held fish")
	sim:Advance(FishingConfig.HoldFishTime + 0.5)
	t.eq(fisher.Character:FindFirstChild("HeldFish"), nil, "the held fish is gone after HoldFishTime")
	t.eq(#fx.GetEffects(fisher), 0, "no FX left")
	local empty, left = fxFoldersEmpty(sim)
	t.ok(empty, `nothing left in Workspace.FishingFx ({left})`)
	sim:AssertNoErrors({ warnings = true })
end

tests["legendary: pillar, confetti, ground wave, aura; emitter budget; nothing left, no connections"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "SharkPup") -- Legendary: two hits
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local fx = clientFx(sim, watcher)
	sim:Advance(0.5)
	local connections = sim:CountConnections(watcher)
	local rendering = renderSteppedCount(sim, watcher)
	local fisherConnections = sim:CountConnections(fisher)

	local audit = auditor(fx, fisher)
	local mg, startTime = startMinigame(t, sim, fisher, audit.step)
	t.ok(renderSteppedCount(sim, watcher) > rendering, "per-frame work while the bobber is out")
	local name, caughtAt = playMinigame(sim, fisher, mg, startTime, false, audit.step)
	t.eq(name, "Caught")
	local pillarAt = nil
	sim:WaitFor(function()
		audit.step()
		if not pillarAt and findEffect(fx, fisher, "PillarCore") then
			pillarAt = sim:Time()
		end
		return sim:Time() >= caughtAt + FishingConfig.LeapTime + Fx.PillarTime + 0.5
	end, 10, FRAME)

	for _, effect in { "Leap", "Ripple", "PillarCore", "PillarGlow", "Confetti", "RarityAura" } do
		t.ok(audit.seen[effect], `{effect} was shown (seen: {keys(audit.seen)})`)
	end
	t.ok(pillarAt and pillarAt >= caughtAt + FishingConfig.LeapTime - FRAME, "the pillar rises when the fish lands")
	t.near(audit.pillarHeight, Fx.PillarHeight, 1, "the pillar shoots up to PillarHeight")
	t.ok(
		audit.maxEmitters <= Fx.MaxEmitters,
		`at most {Fx.MaxEmitters} ParticleEmitters at a time ({audit.maxEmitters})`
	)
	t.ok(audit.maxApi <= Fx.MaxEmitters, "CountEmitters agrees")
	t.eq(audit.maxEmitters, Fx.MaxEmitters, "and the budget is used (leap sparkles + splash; aura + confetti)")
	t.eq(keys(audit.loud), "", "every FX part is anchored, without collisions, queries, touch or shadows")

	sim:Advance(FishingConfig.HoldFishTime + 1, COARSE)
	t.eq(#fx.GetEffects(fisher), 0, "every effect ended")
	local empty, left = fxFoldersEmpty(sim)
	t.ok(empty, `nothing left in Workspace.FishingFx ({left})`)
	t.eq(renderSteppedCount(sim, watcher), rendering, "no per-frame work when nothing is active")
	t.eq(sim:CountConnections(watcher), connections, `watcher: no connections left\n{sim:FormatConnections(watcher)}`)
	t.eq(sim:CountConnections(fisher), fisherConnections, "fisher's own client: no connections left either")
	sim:AssertNoErrors({ warnings = true })
end

tests["far away (> Fx.Range): no splashes, rings or leap — only the pillar of a Mythic catch"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local far = addPlayer(sim, 2)
	forceFish(sim, "DragonFish") -- Mythic: three hits
	ready(sim, fisher)
	sim:Teleport(far, spotOf(sim, fisher).Position + Vector3.new(0, Fx.Range + 300, 0))
	local fx = clientFx(sim, far)
	local audit = auditor(fx, fisher)
	local mg, startTime = startMinigame(t, sim, fisher, audit.step)
	local name, caughtAt = playMinigame(sim, fisher, mg, startTime, false, audit.step)
	t.eq(name, "Caught")
	local pillarAt = nil
	sim:WaitFor(function()
		audit.step()
		if not pillarAt and findEffect(fx, fisher, "PillarCore") then
			pillarAt = sim:Time()
		end
		return sim:Time() >= caughtAt + FishingConfig.LeapTime + 0.5
	end, 5, FRAME)
	t.eq(keys(audit.seen), "PillarCore, PillarGlow", "only the pillar is drawn for a far viewer")
	t.ok(pillarAt and pillarAt >= caughtAt + FishingConfig.LeapTime - FRAME, "when the fish would have landed")
	t.ok(fisher.Character:FindFirstChild("HeldFish"), "the held fish itself is server-side (everyone sees it)")
	sim:AssertNoErrors({ warnings = true })
end

tests["lost (miss): FishFx before Idle; a small fish dives away from the fisher under the water"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "Swordfish", "Neon") -- Epic: the one that got away
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local fx = clientFx(sim, watcher)
	local mg, startTime = startMinigame(t, sim, fisher)
	local order, connection = watchOrder(fisher)
	local name, lostAt = playMinigame(sim, fisher, mg, startTime, true)
	t.eq(name, "Lost")
	sim:Flush()
	connection:Disconnect()
	local fxAt, idleAt = lastIndex(order, "FishFx"), lastIndex(order, "FishingState")
	t.ok(fxAt and idleAt and fxAt < idleAt, `FishFx is set before Idle ({table.concat(order, ", ")})`)
	local value = fisher:GetAttribute("FishFx")
	t.ok(string.match(value, "^%d+|lost|Swordfish|Neon|Epic$") ~= nil, `FishFx = «{value}»`)

	local dive, path = nil, {}
	sim:WaitFor(function()
		dive = dive or findEffect(fx, fisher, "Dive")
		if dive and dive.Parent then
			table.insert(path, (dive:GetBoundingBox()).Position)
		end
		return dive ~= nil and dive.Parent == nil
	end, Fx.DiveTime + 0.5, FRAME)
	t.ok(dive, "a diving fish on the watcher's client")
	t.eq(
		dive:GetAttribute("Kind"),
		sim:Find("ReplicatedStorage.Assets.Fish.Swordfish.Neon"):GetAttribute("Kind"),
		"the fish that got away"
	)
	t.ok(sim:Time() - lostAt <= Fx.DiveTime + 3 * FRAME, "gone after DiveTime")
	local root = fisher.Character.HumanoidRootPart.Position
	local target = fisher:GetAttribute("BobberTarget")
	t.ok(flat(path[1] - target).Magnitude < 6, "it starts at the bobber")
	t.ok(flat(path[#path] - root).Magnitude > flat(path[1] - root).Magnitude + 2, "it swims away from the fisher")
	local top = -math.huge
	for _, p in path do
		top = math.max(top, p.Y)
	end
	t.ok(top > 0.3, "a flick of the tail above the water")
	t.ok(path[#path].Y < -2, "then under the water")
	t.eq(fisher.Character:FindFirstChild("HeldFish"), nil, "nothing above the head")
	sim:Advance(1.5)
	t.eq(#fx.GetEffects(fisher), 0, "no FX left")
	local empty, left = fxFoldersEmpty(sim)
	t.ok(empty, `nothing left in Workspace.FishingFx ({left})`)
	sim:AssertNoErrors({ warnings = true })
end

tests["lost (hooked too early): FishFx with empty fields, a generic small fish dives"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local fx = clientFx(sim, watcher)
	sim:FireServer(fisher, "FishingCast")
	sim:Advance(FishingConfig.CastFlightTime + 0.3)
	t.eq(fisher:GetAttribute("FishingState"), "Waiting")
	sim:FireServer(fisher, "FishingHook")
	t.eq(fisher:GetAttribute("FishingState"), "Idle", "hooked before the bite: the fish is scared")
	t.ok(string.match(fisher:GetAttribute("FishFx"), "^%d+|lost|||$") ~= nil, "no fish yet: empty fields")
	local dive = sim:WaitFor(function()
		return findEffect(fx, fisher, "Dive")
	end, 0.3, FRAME)
	t.ok(dive, "a small fish dives away")
	t.eq(dive:GetAttribute("Kind"), sim:Find("ReplicatedStorage.Assets.Fish.Crucian.Normal"):GetAttribute("Kind"))
	sim:AssertNoErrors({ warnings = true })
end

tests["cast, waiting, bite, reeling: trail, landing rings, ripples, bouncing «!», pulsing line"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "Crucian")
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local fx = clientFx(sim, watcher)

	sim:FireServer(fisher, "FishingCast")
	local landing = sim:Time() + FishingConfig.CastFlightTime
	sim:Advance(FishingConfig.CastFlightTime / 2)
	local bobber = fx.GetBobber(fisher)
	t.ok(bobber, "the bobber flies")
	t.eq(bobber.Root.CastTrail.Enabled, true, "a trail behind the flying bobber")
	t.eq(bobber.Root.CastSparkle.Enabled, true, "…with sparkles")
	local rings = {}
	local function countRings()
		for _, instance in fx.GetEffects(fisher) do
			if instance.Name == "Ripple" then
				rings[instance] = sim:Time()
			end
		end
	end
	sim:WaitFor(function()
		countRings()
		return sim:Time() >= landing + 0.4
	end, 2, FRAME)
	t.eq(bobber.Root.CastTrail.Enabled, false, "no trail on the water")
	local landingRings = 0
	for _ in rings do
		landingRings += 1
	end
	t.eq(landingRings, 3, "three rings spread when the bobber lands")
	local ring = next(rings)
	t.ok(ring.Ring:IsA("SurfaceGui") and ring.Ring.Outer.UIStroke ~= nil, "a ring: SurfaceGui with a stroke circle")
	local lift = ring.Position.Y - fisher:GetAttribute("BobberTarget").Y
	t.ok(lift > 0 and lift < 0.3, `on the water ({lift} above it)`)

	-- Waiting: a slow ripple every RippleEvery seconds.
	table.clear(rings)
	local bite = nil
	sim:WaitFor(function()
		countRings()
		if fisher:GetAttribute("FishingState") == "Bite" then
			bite = sim:Time()
		end
		return bite ~= nil
	end, 10, FRAME)
	t.ok(bite, "a bite")
	local waitingRings = 0
	for _, at in rings do
		if at < bite then
			waitingRings += 1
		end
	end
	local waited = bite - landing
	t.ok(
		waitingRings >= math.floor(waited / Fx.RippleEvery) - 1,
		`a ripple every {Fx.RippleEvery} s while waiting ({waitingRings} in {waited} s)`
	)

	-- Bite: «!» bounces and pulses, a burst of three rings.
	table.clear(rings)
	local alert = bobber.Root.BiteAlert
	local offsets, sizes = {}, {}
	sim:WaitFor(function()
		countRings()
		offsets[alert.StudsOffset.Y] = true
		sizes[alert.Size.X.Offset] = true
		return sim:Time() >= bite + 0.5
	end, 1, FRAME)
	t.eq(alert.Enabled, true, "«!» over the bobber")
	t.ok(alert.Badge.Fill:IsA("UIGradient"), "a candy badge in Sun colours")
	t.eq(alert.Label.Text, "!")
	local count = 0
	for _ in offsets do
		count += 1
	end
	t.ok(count > 10, "it bounces (StudsOffset changes every frame)")
	count = 0
	for _ in sizes do
		count += 1
	end
	t.ok(count > 3, "it pulses (size changes)")
	local biteRings = 0
	for _ in rings do
		biteRings += 1
	end
	t.ok(biteRings >= 3, `a burst of rings on the bite ({biteRings})`)

	-- Reeling: the line pulses (width and colour).
	sim:FireServer(fisher, "FishingHook")
	sim:Advance(0.1)
	t.eq(fisher:GetAttribute("FishingState"), "Reeling")
	local widths, tinted = {}, false
	sim:WaitFor(function()
		local line = bobber.Line
		widths[math.floor(line.Width0 * 1000)] = true
		local color = line.Color.Keypoints[1].Value
		if color.B < color.R - 0.2 then
			tinted = true
		end
		return false
	end, 0.6, FRAME)
	count = 0
	for _ in widths do
		count += 1
	end
	t.ok(count > 5, "the line's width pulses while reeling")
	t.ok(tinted, "the line glows orange under tension")
	t.eq(alert.Enabled, false, "no «!» while reeling")
	sim:AssertNoErrors({ warnings = true })
end

tests["rainbow: the leaping copy of a Rainbow fish shimmers too"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "Perch", "Rainbow")
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local fx = clientFx(sim, watcher)
	local mg, startTime = startMinigame(t, sim, fisher)
	t.eq((playMinigame(sim, fisher, mg, startTime)), "Caught")
	local leap = sim:WaitFor(function()
		return findEffect(fx, fisher, "Leap")
	end, 0.2, FRAME)
	t.ok(leap, "the leap")
	local part = nil
	for _, d in leap:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("RainbowU") ~= nil then
			part = d
			break
		end
	end
	t.ok(part, "a rainbow part on the leaping fish")
	local function color(): any
		return sim:Run(function()
			return part.Color
		end, watcher)
	end
	local before = color()
	sim:Advance(0.25)
	local after = color()
	t.ok(
		math.abs(before.R - after.R) + math.abs(before.G - after.G) + math.abs(before.B - after.B) > 0.03,
		"it shimmers"
	)
	sim:AssertNoErrors({ warnings = true })
end

tests["leaving: a fisher leaving mid-leap takes all FX along on other clients; late joiners do not replay"] = function(
	t
)
	local sim = boot(t)
	local watcher = addPlayer(sim, 2)
	sim:Advance(0.5)
	local baseline = sim:CountConnections(watcher) -- before the fisher (and the late joiner) came
	local rendering = renderSteppedCount(sim, watcher)
	local fisher = addPlayer(sim, 1)
	forceFish(sim, "SharkPup")
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local fx = clientFx(sim, watcher)
	local mg, startTime = startMinigame(t, sim, fisher)
	local name, caughtAt = playMinigame(sim, fisher, mg, startTime)
	t.eq(name, "Caught")

	-- A player who joins right after the catch (standing beside the fisher as soon as the
	-- character appears) does not replay it.
	local late = sim:AddPlayer({ UserId = 3, Name = "Player3", device = "phone" })
	sim:WaitFor(function()
		if late.Character and late.Character:FindFirstChild("HumanoidRootPart") then
			standBeside(sim, late, fisher)
			return true
		end
		return false
	end, 1, FRAME)
	local lateFx = clientFx(sim, late)
	sim:WaitFor(function()
		return sim:Time() >= caughtAt + FishingConfig.LeapTime / 2
	end, 1, FRAME)
	local alive = fx.GetEffects(fisher)
	local leap = findEffect(fx, fisher, "Leap")
	t.ok(leap, "mid-leap")
	t.ok(#alive >= 2, "rings and the leap are out")
	t.eq(findEffect(lateFx, fisher, "Leap"), nil, "the late joiner does not replay the old FishFx")

	sim:RemovePlayer(fisher)
	sim:Advance(0.2)
	for _, instance in alive do
		t.eq(instance.Parent, nil, `{instance.Name} removed on the watcher's client`)
	end
	sim:Advance(FishingConfig.LeapTime + Fx.PillarTime)
	local empty, left = fxFoldersEmpty(sim)
	t.ok(empty, `nothing left in Workspace.FishingFx, no pillar either ({left})`)
	t.eq(renderSteppedCount(sim, watcher), rendering, "no per-frame work left")
	sim:RemovePlayer(late)
	sim:Advance(0.2)
	t.eq(sim:CountConnections(watcher), baseline, `watcher back to its baseline\n{sim:FormatConnections(watcher)}`)
	sim:AssertNoErrors({ warnings = true })
end

return tests
