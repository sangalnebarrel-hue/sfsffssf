--[[
	World FX of fishing: FishingService's FishFx broadcast + FishingFxController on every client,
	run in RbxSim against the built Place1.rbxl with the real server and real clients (nothing
	stubbed except FishingService.RollFishForTest, which forces the species).

	What is checked:
	  • FishFx is set before FishingState goes "Idle" ("<n>|caught|<Id>|<Mutation>|<Rarity>",
	    "<n>|lost|…"), so clients still see the bobber on the water;
	  • the caught fish (a client-side copy of Assets.Fish.<Id>.<Mutation>) leaps from the bobber's
	    water point in an arc and lands exactly where the server's HeldFish appears (LeapTime after
	    the catch) and at its size (FishingConfig.HeldScale — already bigger than the model out of
	    the water), then disappears; the bobber flies with it and is gone after the leap;
	  • v3 [anim-b]: the own bobber is tugged toward the pier by every minigame hit ("Zone");
	  • the fisher's own client: OwnFishLanded fires once, on the landing frame, at the held fish;
	    Humanoid.CameraOffset slides right/up while fishing and back once the held fish is gone;
	  • at the landing: a neon pop, a camera-facing halo; Rare and up: a nameplate (rarity, name,
	    mutation, price) and a rarity aura (a mutation recolours the aura, Neon glows) that last
	    FishingRules.HoldFishTime; Legendary/Mythic: a pillar (neon core + beams), confetti and a
	    ground wave;
	  • a lost fish: the line flashes red, the bobber pops up, a fish dives away under the water;
	  • the bobber: 1.7× bigger (the own one 2.2×), waterline still FloatDepth below the pivot; own one outlined and
	    with the big «!» (others: smaller, not on top, no stars); Nibble(); the bite plunge;
	    cast trail, landing rings, waiting ripples, a sagging line while waiting, the wake and the
	    pulsing line while reeling;
	  • v3 [fx]: the held fish lives on the watcher's client (HoldWeld / tail welds client-local,
    bob + flops within bounds, the nameplate does not shake, restored, LifeRange LOD); the fish
    shadow (appears, circles, pokes on a nibble, lunges on the bite, bigger in a rare fight,
    flees when lost; quiet SmoothPlastic parts; AmbientRange LOD); the rod tip's whip trail at
    the release, the curved line in flight, the landing plop, the taut line's tremble; the leap
    flexes and drips (drips gone before the hand-over); the landing is a crisp burst (no own
    pillar in the landing frame);
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
local UIConfig = loadConfig("UIConfig")
local Fx = FishingConfig.Fx

local Vector3 = roblox.Vector3
local UDim2 = roblox.UDim2
local Vector2 = roblox.Vector2

-- FishingFxController's camera offset while the player's own fishing is on screen.
local CAMERA_OFFSET = Vector3.new(2.2, 1, 0)
local TROPHY_CAMERA = Vector3.new(2.2, 1.6, 0) -- own fish over the head after the card opened
local OWN_PILLAR_DELAY = 0.3 -- FishingFxController FX.OwnPillarDelay: the own pillar after the burst

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
	local audit = {
		seen = {},
		maxEmitters = 0,
		maxApi = 0,
		loud = {},
		pillarHeight = 0,
		pillarBottom = math.huge,
		pillarBeams = false,
	}
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
				audit.pillarBottom = math.min(audit.pillarBottom, instance.Position.Y - instance.Size.X / 2)
			elseif instance.Name == "PillarGlow" then
				local glow, sparkle = instance:FindFirstChild("Glow"), instance:FindFirstChild("Sparkle")
				if glow and sparkle and glow:IsA("Beam") and sparkle:IsA("Beam") and glow.FaceCamera then
					audit.pillarBeams = true
				end
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
			local box, size = leap:GetBoundingBox()
			table.insert(path, { time = sim:Time(), pivot = leap:GetPivot(), center = box.Position, size = size })
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
	-- … and at its size: the held fish is bigger than the model (FishingConfig.HeldScale), the leap
	-- grows to it (out of the water already bigger than the model)
	local scale = held:GetAttribute("Scale")
	t.ok(typeof(scale) == "number" and scale >= FishingConfig.HeldScale.Rare - 1e-3, `held fish Scale {scale}`)
	local _, heldSize = held:GetBoundingBox()
	local _, templateSize = template:GetBoundingBox()
	t.near(last.size, heldSize, 0.05, "the leap ends at the held fish's size")
	t.ok(
		first.size.X > templateSize.X * 1.05,
		`out of the water already bigger than the model ({first.size.X} vs {templateSize.X})`
	)
	t.ok(last.time >= heldAt - 1e-9, "the copy disappears only when the held fish is there")
	t.eq(leap.Parent, nil, "the copy is gone")
	t.eq(fx.GetBobber(fisher), nil, "the bobber flew in with the fish and is gone")

	-- Rare: sparkles (and a glow) around the held fish on the watcher's client.
	local aura = findEffect(fx, fisher, "RarityAura")
	t.ok(aura and aura:IsA("ParticleEmitter"), "a rarity aura on the held fish")
	t.ok(aura.Parent == held.PrimaryPart, "attached to the held fish")
	sim:Advance(FishingConfig.HoldFishTime.Rare + 0.5)
	t.eq(fisher.Character:FindFirstChild("HeldFish"), nil, "the held fish is gone after HoldFishTime.Rare")
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
	local trophies = {}
	local heard = sim:Run(function()
		return fx.OtherTrophy:Connect(function(player, base, rarity)
			table.insert(trophies, { player = player, base = base, rarity = rarity })
		end)
	end, watcher)
	local mg, startTime = startMinigame(t, sim, fisher, audit.step)
	t.ok(renderSteppedCount(sim, watcher) > rendering, "per-frame work while the bobber is out")
	local name, caughtAt = playMinigame(sim, fisher, mg, startTime, false, audit.step)
	t.eq(name, "Caught")
	local pillarAt = nil
	local plateTop = nil
	sim:WaitFor(function()
		audit.step()
		if not pillarAt and findEffect(fx, fisher, "PillarCore") then
			pillarAt = sim:Time()
			local held = fisher.Character:FindFirstChild("HeldFish")
			if held then
				local box, size = held:GetBoundingBox()
				plateTop = box.Position.Y + size.Y / 2 + 0.4 + 1.25 -- the plate's bottom + its studs part
			end
		end
		return sim:Time() >= caughtAt + FishingConfig.LeapTime + Fx.PillarTimeOther.Legendary + 0.5
	end, 12, FRAME)
	heard:Disconnect()
	t.eq(#trophies, 1, "OtherTrophy fires once on the watcher's client (the HUD points at off-screen pillars)")
	t.eq(trophies[1] and trophies[1].player, fisher, "…for the fisher")
	t.eq(trophies[1] and trophies[1].rarity, "Legendary", "…with the rarity")
	t.ok(trophies[1] and flat(trophies[1].base - sim:GetRoot(fisher).Position).Magnitude < 1, "…at the fisher's feet")
	t.ok(
		plateTop and audit.pillarBottom > plateTop,
		`nearby, the pillar starts above the fisher's nameplate ({audit.pillarBottom} > {plateTop})`
	)

	for _, effect in
		{ "Leap", "Ripple", "Spout", "Pop", "Halo", "Nameplate", "PillarCore", "PillarGlow", "Confetti", "RarityAura" }
	do
		t.ok(audit.seen[effect], `{effect} was shown (seen: {keys(audit.seen)})`)
	end
	t.ok(pillarAt and pillarAt >= caughtAt + FishingConfig.LeapTime - FRAME, "the pillar rises when the fish lands")
	t.near(audit.pillarHeight, Fx.PillarHeight.Legendary, 1, "the pillar shoots up to PillarHeight.Legendary")
	t.ok(audit.pillarBeams, "the pillar glows with camera-facing beams (Glow + Sparkle in PillarGlow)")
	t.ok(
		audit.maxEmitters <= Fx.MaxEmitters,
		`at most {Fx.MaxEmitters} ParticleEmitters at a time ({audit.maxEmitters})`
	)
	t.ok(audit.maxApi <= Fx.MaxEmitters, "CountEmitters agrees")
	t.eq(audit.maxEmitters, Fx.MaxEmitters, "and the budget is used (leap sparkles + splash; aura + confetti)")
	t.eq(keys(audit.loud), "", "every FX part is anchored, without collisions, queries, touch or shadows")

	sim:Advance(FishingConfig.HoldFishTime.Legendary + 1, COARSE)
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
	local pillarAt, distance = nil, 0
	sim:WaitFor(function()
		audit.step()
		local core = findEffect(fx, fisher, "PillarCore")
		if not pillarAt and core then
			pillarAt = sim:Time()
			distance = (core.Position - Vector3.new(0, core.Size.X / 2, 0) - sim:GetRoot(far).Position).Magnitude
		end
		return sim:Time() >= caughtAt + FishingConfig.LeapTime + 1.5
	end, 5, FRAME)
	t.eq(keys(audit.seen), "PillarCore, PillarGlow", "only the pillar is drawn for a far viewer")
	t.ok(audit.pillarHeight > Fx.PillarHeight.Mythic, "from far away the pillar is taller than PillarHeight.Mythic…")
	t.near(audit.pillarHeight, 40 + 0.5 * distance, 3, `…a beam to the sky: 40 + distance / 2 studs ({distance})`)
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

	-- The bobber (still on the water at FishFx) pops up and drops back before it reels in; the
	-- line flashes red.
	local bobber = fx.GetBobber(fisher)
	t.ok(bobber, "the bobber is still there")
	local bobberTop, flashed = -math.huge, false
	local dive, path = nil, {}
	sim:WaitFor(function()
		dive = dive or findEffect(fx, fisher, "Dive")
		if dive and dive.Parent then
			table.insert(path, (dive:GetBoundingBox()).Position)
		end
		if bobber.Parent then
			bobberTop = math.max(bobberTop, bobber:GetPivot().Position.Y)
			local color = bobber.Line.Color.Keypoints[1].Value
			flashed = flashed or (color.R > 0.8 and color.G < 0.3 and bobber.Line.Width0 >= 0.2 - 1e-6)
		end
		return dive ~= nil and dive.Parent == nil
	end, Fx.DiveTime + 0.5, FRAME)
	local rest = fisher:GetAttribute("BobberTarget").Y + bobber:GetAttribute("FloatDepth")
	t.ok(flashed, "the line flashes red (Berry) when the fish gets away")
	t.ok(bobberTop >= rest + 2, `the bobber pops up ({bobberTop - rest} studs)`)
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
	-- the float hangs on the rod tip for CastWindUp (the wind-up), then flies CastFlightTime
	local landing = sim:Time() + FishingConfig.CastWindUp + FishingConfig.CastFlightTime
	sim:Advance(FishingConfig.CastWindUp / 2)
	t.eq(fx.GetBobber(fisher).Root.CastTrail.Enabled, false, "wind-up: no trail while the float hangs on the tip")
	sim:Advance(FishingConfig.CastWindUp / 2 + FishingConfig.CastFlightTime / 2)
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
	-- The first (biggest) ring: the burst shrinks each next ring by 14 %, and `next` would pick
	-- any of them (table order changes from run to run).
	local ring = nil
	for candidate in rings do
		if ring == nil or candidate.Size.X > ring.Size.X then
			ring = candidate
		end
	end
	t.ok(ring.Ring:IsA("SurfaceGui") and ring.Ring.Outer.UIStroke ~= nil, "a ring: SurfaceGui with a stroke circle")
	local lift = ring.Position.Y - fisher:GetAttribute("BobberTarget").Y
	t.ok(lift > 0.2 and lift < 0.4, `on the water, above its small waves ({lift} above it)`)
	t.eq(ring.Size.X, ring.Size.Z, "a flat square part…")
	t.ok(ring.Size.X >= 7, `…made at its final size at once (only the frames inside grow): {ring.Size.X}`)

	-- Waiting: a slow ripple every RippleEvery seconds; the line sags (its far end lies on the water).
	table.clear(rings)
	local bite = nil
	local sag = 0
	sim:WaitFor(function()
		countRings()
		sag = math.max(sag, bobber.Line.CurveSize1)
		if fisher:GetAttribute("FishingState") == "Bite" then
			bite = sim:Time()
		end
		return bite ~= nil
	end, 10, FRAME)
	t.ok(sag > 0.5, `the line sags while waiting (CurveSize1 {sag})`)
	t.eq(bobber.Line.Segments, 10, "a curved line has segments")
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
	local guiSize = alert.Size
	local low = math.huge
	sim:WaitFor(function()
		countRings()
		offsets[alert.StudsOffset.Y] = true
		sizes[alert.Holder.FxScale.Scale] = true
		low = math.min(low, bobber:GetPivot().Position.Y)
		return sim:Time() >= bite + 0.5
	end, 1, FRAME)
	t.eq(alert.Enabled, true, "«!» over the bobber")
	t.ok(alert.Holder.Badge.Fill:IsA("UIGradient"), "a candy badge in Sun colours")
	t.eq(alert.Holder.Label.Text, "!")
	t.eq(alert.Holder.Label.TextScaled, false, "fixed TextSize (no TextScaled refit every frame)")
	t.eq(alert.Size, guiSize, "the gui keeps its size; the UIScale inside animates")
	t.eq(alert.AlwaysOnTop, false, "another player's «!» does not show through walls")
	t.eq(alert.MaxDistance, 90, "…and only up to 90 studs")
	t.eq(alert.Holder:FindFirstChild("Star1"), nil, "…and has no orbiting stars")
	local rest = fisher:GetAttribute("BobberTarget").Y + bobber:GetAttribute("FloatDepth")
	t.ok(low < rest - 1.2, `the bite plunges the bobber under the water (down to {low - rest})`)
	local count = 0
	for _ in offsets do
		count += 1
	end
	t.ok(count > 10, "it bounces (StudsOffset changes every frame)")
	count = 0
	for _ in sizes do
		count += 1
	end
	t.ok(count > 3, "it pulses (its UIScale changes)")
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
	-- Taut: no sag, but the string trembles sideways (FishingLine: CurveSize1 along a side axis).
	local bends, slack = {}, 0
	sim:WaitFor(function()
		local line = bobber.Line
		bends[math.floor(line.CurveSize1 * 100)] = true
		slack = math.max(slack, math.abs(line.CurveSize1), math.abs(line.CurveSize0))
		return false
	end, 0.3, FRAME)
	count = 0
	for _ in bends do
		count += 1
	end
	t.ok(slack <= 0.25, `taut under tension: no sag, only a tremble ({slack} studs)`)
	t.ok(count > 4, "…the taut line vibrates (CurveSize1 changes every frame)")
	t.eq(bobber.Root.Wake.Enabled, true, "a foam wake behind the thrashing bobber")
	t.eq(alert.Enabled, false, "no «!» while reeling")
	sim:FireServer(fisher, "FishingStop")
	sim:Advance(0.1)
	t.eq(bobber.Root.Wake.Enabled, false, "no wake while it reels in")
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
	sim:Advance(FishingConfig.LeapTime + Fx.PillarTimeOther.Legendary)
	local empty, left = fxFoldersEmpty(sim)
	t.ok(empty, `nothing left in Workspace.FishingFx, no pillar either ({left})`)
	t.eq(renderSteppedCount(sim, watcher), rendering, "no per-frame work left")
	sim:RemovePlayer(late)
	sim:Advance(0.2)
	t.eq(sim:CountConnections(watcher), baseline, `watcher back to its baseline\n{sim:FormatConnections(watcher)}`)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The fisher's own client: the landing signal, the camera, the own bobber, Nibble()
--------------------------------------------------------------------------------

-- Humanoid.CameraOffset as the player's own client sees it (a client-local value).
local function cameraOffset(sim: any, player: any): any
	return sim:Run(function()
		local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		return if humanoid then humanoid.CameraOffset else nil
	end, player)
end

local function colorNear(a: any, b: any): boolean
	return math.abs(a.R - b.R) + math.abs(a.G - b.G) + math.abs(a.B - b.B) < 0.01
end

-- Records OwnFishLanded on a client: { { time, rarity, position } }.
local function landings(sim: any, fx: any): { any }
	local list = {}
	fx.OwnFishLanded:Connect(function(rarity: string, position: any)
		table.insert(list, { time = sim:Time(), rarity = rarity, position = position })
	end)
	return list
end

tests["own client: OwnFishLanded fires once, on the landing frame, at the held fish; the camera slides aside and back"] = function(
	t
)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "SharkPup") -- Legendary: held for HoldFishTime.Legendary
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local landed = landings(sim, clientFx(sim, fisher))
	local heard = landings(sim, clientFx(sim, watcher))
	t.near(cameraOffset(sim, fisher), Vector3.zero, 1e-6, "no camera offset before fishing")

	local mg, startTime = startMinigame(t, sim, fisher)
	t.near(
		cameraOffset(sim, fisher),
		CAMERA_OFFSET,
		0.01,
		"fishing: the camera slides right and up (the bobber shows right of the head, not behind it)"
	)
	t.near(cameraOffset(sim, watcher), Vector3.zero, 1e-6, "the watcher's camera stays put")
	local name, caughtAt = playMinigame(sim, fisher, mg, startTime)
	t.eq(name, "Caught")
	t.eq(#landed, 0, "no signal while the fish is in the air")
	local heldAt = nil
	sim:WaitFor(function()
		if not heldAt and fisher.Character:FindFirstChild("HeldFish") then
			heldAt = sim:Time()
		end
		return heldAt ~= nil and #landed > 0
	end, FishingConfig.LeapTime + 1, FRAME)
	t.eq(#landed, 1, "OwnFishLanded fired on the fisher's own client")
	t.eq(landed[1].rarity, "Legendary", "with the rarity")
	t.ok(
		math.abs(landed[1].time - (caughtAt + FishingConfig.LeapTime)) <= 2 * FRAME,
		`on the landing frame (LeapTime after the catch: +{landed[1].time - caughtAt} s)`
	)
	local held = fisher.Character.HeldFish
	t.near(landed[1].position, held:GetBoundingBox().Position, 0.05, "at the centre of the held fish")
	t.near(cameraOffset(sim, fisher), CAMERA_OFFSET, 0.01, "the camera stays aside while the trophy is up")

	-- The own nameplate sits beside the fish (the status badge and the counter are above it).
	local ownFx = clientFx(sim, fisher)
	local plate = sim:WaitFor(function()
		return findEffect(ownFx, fisher, "Nameplate")
	end, 0.5, FRAME)
	t.ok(plate, "the own client shows a nameplate too")
	t.eq(plate.SizeOffset, Vector2.new(0.5, 0), "…its left edge on the anchor point")
	t.ok(plate.StudsOffset.X > 0.4, "…to the right of the fish (camera space)")
	t.near(
		plate.StudsOffsetWorldSpace.Y,
		held:GetBoundingBox().Position.Y - held.PrimaryPart.Position.Y,
		0.05,
		"…level with it (FishLife only adds a gentle bob)"
	)
	t.eq(
		findEffect(ownFx, fisher, "PillarCore"),
		nil,
		"the landing frame is a crisp burst at the fish: no own pillar yet"
	)
	t.ok(findEffect(ownFx, fisher, "Burst"), "…a star burst of thin rays around the fish")
	sim:Advance(0.35, FRAME)
	t.ok(findEffect(ownFx, fisher, "PillarCore"), "the own pillar rises right after the burst (OwnPillarDelay)")
	t.eq(fisher.PlayerGui.HUD:GetAttribute("CounterHold") ~= nil, true, "(the catch is on the fisher's screen)")
	t.eq(
		plate.Enabled,
		false,
		"…the own nameplate waits: no second rarity word under the title, no price by the card"
	)

	-- The card closes (FishingController): the trophy flashes again — pop, halo; the nameplate pops in
	-- as the new thing. On a phone (a short screen) no replay pillar: it would rise behind the counter.
	sim:Advance(FishingConfig.Fx.PillarTime.Legendary + 0.2, COARSE)
	t.eq(findEffect(ownFx, fisher, "PillarCore"), nil, "the landing pillar is over")
	local replayed = sim:Run(function()
		return ownFx.ReplayOwnTrophy()
	end, fisher)
	t.eq(replayed, true, "ReplayOwnTrophy: the fish is still over the head")
	t.ok(findEffect(ownFx, fisher, "Halo") and findEffect(ownFx, fisher, "Pop"), "…a halo and a pop again")
	t.eq(findEffect(ownFx, fisher, "PillarCore"), nil, "…no replay pillar on a phone")
	t.eq(plate.Enabled, true, "…the nameplate shows up now")
	t.ok(plate.Plate.FxScale.Scale < 0.2, "…popping in from nothing")
	sim:Advance(0.45, FRAME)
	t.ok(plate.Plate.FxScale.Scale > 0.9, `…and it is in ({plate.Plate.FxScale.Scale})`)
	sim:Advance(1.5, COARSE)
	local watcherFx = clientFx(sim, watcher)
	t.eq(
		sim:Run(function()
			return watcherFx.ReplayOwnTrophy()
		end, watcher),
		false,
		"the watcher has no trophy of its own: nothing"
	)
	sim:Advance(
		math.max(
			0,
			FishingConfig.HoldFishTime.Legendary
				- 0.5
				- 0.35 -- (the wait for the own pillar above)
				- FishingConfig.Fx.PillarTime.Legendary
				- 1.7
		),
		COARSE
	)
	t.ok(fisher.Character:FindFirstChild("HeldFish"), "still holding the fish")
	-- (a bigger fish — attribute Scale, FishingConfig.HeldScale — grows up from the head: the camera
	-- rises by half of that growth more)
	local heldFish = fisher.Character.HeldFish
	local heldScale = heldFish:GetAttribute("Scale")
	t.ok(typeof(heldScale) == "number" and heldScale > 1, `the held fish is bigger than life ({heldScale})`)
	local _, heldBox = heldFish:GetBoundingBox()
	t.near(
		cameraOffset(sim, fisher),
		TROPHY_CAMERA + Vector3.new(0, 0.5 * heldBox.Y * (1 - 1 / heldScale), 0),
		0.01,
		"…and the camera stays aside, a little higher since the card opened (the trophy clears the counter)"
	)
	sim:Advance(1.5, COARSE)
	t.eq(fisher.Character:FindFirstChild("HeldFish"), nil, "the held fish is gone")
	t.near(cameraOffset(sim, fisher), Vector3.zero, 1e-3, "the camera is back")
	t.eq(#landed, 1, "exactly one signal per catch")
	t.eq(#heard, 0, "the watcher's client never fires it (not their fish)")
	sim:AssertNoErrors({ warnings = true })
end

tests["own client: no leap (no fish model on the client) — OwnFishLanded fires right away, once"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	forceFish(sim, "Puffer")
	ready(sim, fisher)
	local landed = landings(sim, clientFx(sim, fisher))
	local mg, startTime = startMinigame(t, sim, fisher)
	-- The client cannot find the caught fish's model: nothing to leap, nothing to wait for.
	sim:Find("ReplicatedStorage.Assets.Fish.Puffer").Name = "PufferHidden"
	local name, caughtAt = playMinigame(sim, fisher, mg, startTime)
	t.eq(name, "Caught")
	sim:Advance(0.1)
	t.eq(#landed, 1, "fired once")
	t.ok(landed[1].time - caughtAt <= 2 * FRAME, `right away (+{landed[1].time - caughtAt} s)`)
	t.eq(landed[1].rarity, "Rare")
	t.ok((landed[1].position - fisher.Character.Head.Position).Magnitude < 3, "over the fisher's head")
	sim:Advance(FishingConfig.LeapTime + 0.5)
	t.eq(#landed, 1, "no second signal")
	sim:AssertNoErrors({ warnings = true })
end

tests["bobber: 1.7× bigger (own 2.2×), waterline kept; the own one outlined with the big «!»; Nibble() only on the own bobber"] = function(
	t
)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "Crucian")
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local own = clientFx(sim, fisher)
	local other = clientFx(sim, watcher)
	local function nibble(player: any, fx: any): boolean
		return sim:Run(function()
			return fx.Nibble()
		end, player)
	end
	t.eq(nibble(fisher, own), false, "no bobber: Nibble() does nothing")
	sim:FireServer(fisher, "FishingCast")
	sim:Advance(0.2)
	t.eq(nibble(fisher, own), false, "still flying: nothing")
	sim:Advance(FishingConfig.CastFlightTime + 0.3)
	t.eq(fisher:GetAttribute("FishingState"), "Waiting")

	local mine, theirs = own.GetBobber(fisher), other.GetBobber(fisher)
	local template = sim:Find(`ReplicatedStorage.Assets.Bobbers.{fisher:GetAttribute("RodId")}`)
	local _, templateSize = template:GetBoundingBox()
	local _, size = mine:GetBoundingBox()
	local _, otherSize = theirs:GetBoundingBox()
	t.near(
		otherSize.Y / templateSize.Y,
		1.7,
		0.02,
		"the client's copy is 1.7× the template (readable at 30–40 studs)"
	)
	t.near(size.Y / templateSize.Y, 2.2, 0.02, "the own one 2.2× (the player watches it the whole time)")
	local depth = mine:GetAttribute("FloatDepth")
	t.eq(depth, template:GetAttribute("FloatDepth"), "FloatDepth (pivot → waterline) as on the template")
	t.near(
		mine.Root.Position.Y - mine:GetPivot().Position.Y,
		1.2 * depth,
		0.01,
		"the pivot sits below the tie point: the bigger float's waterline is still FloatDepth below it"
	)
	local water = fisher:GetAttribute("BobberTarget").Y
	-- (the watcher's copy: the own one may be mid-nibble now — FishingController nibbles by itself)
	t.ok(math.abs(theirs:GetPivot().Position.Y - (water + depth)) <= 0.25, "floating with its waterline on the water")
	local glow = mine:FindFirstChild("OwnGlow")
	t.ok(glow and glow:IsA("Highlight"), "own bobber: a white outline (Highlight)")
	t.eq(glow.FillTransparency, 1, "…not filled while waiting")
	t.eq(theirs:FindFirstChild("OwnGlow"), nil, "someone else's bobber: no outline")
	t.eq(mine.Root.BiteAlert.AlwaysOnTop, true, "own «!» shows through everything")
	t.ok(mine.Root.BiteAlert.Holder:FindFirstChild("Star5"), "…with orbiting stars")
	t.eq(mine.Root.BiteAlert.Holder.Star1.TextScaled, false, "…sized once (TextSize)")
	t.eq(theirs.Root.BiteAlert.AlwaysOnTop, false, "another player's «!» does not")

	-- Nibble: only on the local player's own bobber, only while waiting, only on this client.
	-- UI v2 (FUI-19): FishingController nibbles by itself 1–2 times within NIBBLE_TO (2.2 s)
	-- of the cast; let those dips (and the landing rings) pass before measuring one of our own
	-- (the bite comes no earlier than CastWindUp + CastFlightTime + BiteDelay.Min = 3.5 s after
	-- the cast).
	sim:Advance(1.1 + FishingConfig.CastWindUp)
	local function smallRings(fx: any): number
		local count = 0
		for _, instance in fx.GetEffects(fisher) do
			if instance.Name == "Ripple" and instance.Size.X < 6 then
				count += 1
			end
		end
		return count
	end
	local before = smallRings(own)
	t.eq(nibble(watcher, other), false, "the watcher has no bobber of their own to nibble")
	t.eq(nibble(fisher, own), true, "own bobber waiting on the water: a nibble")
	t.eq(smallRings(own), before + 1, "a small ring")
	t.eq(smallRings(other), 0, "client-only: the watcher sees nothing")
	local mark = mine.Root:FindFirstChild("NibbleMark")
	t.ok(mark and mark:IsA("BillboardGui") and mark.Label.Text == "?", "a «?» pops over the own bobber")
	t.eq(theirs.Root:FindFirstChild("NibbleMark"), nil, "… only on this client")
	-- Both clients bob the same bobber the same way: the difference is the nibble.
	local deepest = 0
	sim:WaitFor(function()
		deepest = math.min(deepest, mine:GetPivot().Position.Y - theirs:GetPivot().Position.Y)
		return false
	end, 0.35, FRAME)
	t.near(deepest, -0.5, 0.03, "the own bobber dips 0.5 studs (readable from the pier)…")
	t.near(mine:GetPivot().Position.Y, theirs:GetPivot().Position.Y, 1e-3, "…and floats back up")

	-- The bite: own outline blinks yellow (2.5 Hz, under the 3 Hz rule); no nibbles now.
	sim:WaitFor(function()
		return fisher:GetAttribute("FishingState") == "Bite"
	end, 10, FRAME)
	local lo, hi = 1, 0
	sim:WaitFor(function()
		lo, hi = math.min(lo, glow.FillTransparency), math.max(hi, glow.FillTransparency)
		return false
	end, 0.5, FRAME)
	t.ok(lo <= 0.4 and hi >= 0.75, `the outline fills and fades yellow on the bite ({lo}..{hi})`)
	t.eq(glow.FillColor, UIConfig.Palette.Sun.Top)
	t.eq(nibble(fisher, own), false, "no nibble during the bite")
	sim:AssertNoErrors({ warnings = true })
end

tests["nameplate and mutation aura: Rare+ fish get a nameplate; a mutation recolours the aura, Neon glows"] = function(
	t
)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	local fish = forceFish(sim, "Puffer", "Gold") -- Rare with a Gold mutation
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local fx = clientFx(sim, watcher)
	local mg, startTime = startMinigame(t, sim, fisher)
	t.eq((playMinigame(sim, fisher, mg, startTime)), "Caught")
	local plate = sim:WaitFor(function()
		return findEffect(fx, fisher, "Nameplate")
	end, FishingConfig.LeapTime + 0.5, FRAME)
	t.ok(plate and plate:IsA("BillboardGui"), "a nameplate over the held fish (on another player's client)")
	local held = fisher.Character.HeldFish
	t.eq(held:GetAttribute("Value"), fish.Value, "the server stamps the price on the held fish…")
	t.eq(held:GetAttribute("FishId"), "Puffer", "…and what it is")
	t.eq(plate.Adornee, held.PrimaryPart, "it follows the held fish")
	t.eq(plate.Size, UDim2.new(4, 150, 1.25, 48), "studs + pixels: still readable from the next pier")
	-- UI v5: the reference's world billboard text — Montserrat Heavy, outlined, no plate.
	t.eq(plate.Plate.FishName.FontFace.Weight, roblox.Enum.FontWeight.Heavy, "Heavy letters")
	t.ok(string.find(plate.Plate.FishName.FontFace.Family, "Montserrat", 1, true) ~= nil, "the UI font (Montserrat)")
	t.ok(plate.Plate.FishName.Outline.Thickness >= 2, "a dark outline")
	t.eq(plate.Plate.FishName.TextColor3, roblox.Color3.new(1, 1, 1), "the name in white")
	t.eq(plate.Plate:FindFirstChildWhichIsA("Frame"), nil, "no plate behind the letters")
	t.eq(plate.AlwaysOnTop, false, "not through walls")
	t.eq(plate.MaxDistance, Fx.Range)
	t.eq(plate.LightInfluence, 0)
	local box, boxSize = held:GetBoundingBox()
	local bottom = held.PrimaryPart.Position.Y + plate.StudsOffsetWorldSpace.Y
	t.eq(plate.SizeOffset, Vector2.new(0, 0.5), "its bottom edge on the anchor point…")
	t.ok(bottom >= box.Position.Y + boxSize.Y / 2 - 0.05, "…above the fish")
	t.eq(plate.Plate.Rarity.Text, "РЕДКАЯ")
	t.ok(plate.Plate.Rarity.Fill:IsA("UIGradient"), "the rarity word in rarity colours")
	t.eq(plate.Plate.FishName.Text, "Фугу-пуфик")
	t.eq(plate.Plate.Mutation.Text, "👑 Золотая ×2")
	t.eq(plate.Plate.Price.Text, `💰 {rules(sim).FormatCoins(fish.Value)}`)
	t.eq(plate.Plate.Price.FontFace.Style, roblox.Enum.FontStyle.Italic, "the price in italic digits")
	t.ok(colorNear(plate.Plate.Price.TextColor3, UIConfig.BillboardYellow.Top), "…billboard yellow")
	sim:Advance(0.6)
	t.near(plate.Plate.FxScale.Scale, 1, 1e-3, "popped in")
	local aura = findEffect(fx, fisher, "RarityAura")
	t.ok(aura and aura.Parent == held.PrimaryPart, "an aura on the held fish")
	local gold = UIConfig.Mutations.Gold
	t.ok(colorNear(aura.Color.Keypoints[2].Value, gold.Top), "in the mutation's colours (Gold)")
	t.ok(aura.Rate >= Fx.MutationAuraRate, "at least MutationAuraRate sparkles a second")
	t.near(aura.Size.Keypoints[2].Value, 0.7, 1e-3, "Gold sparkles peak bigger")
	sim:Advance(FishingConfig.HoldFishTime.Rare, COARSE)
	t.eq(plate.Parent, nil, "the nameplate goes with the held fish (HoldFishTime.Rare)")

	-- A Common fish with a Neon mutation: a nameplate with its name and price (no rarity line),
	-- an aura; the cyan glow (a PointLight that walks with the fisher) only on the fisher's own
	-- client (v3 fix F9).
	local own = clientFx(sim, fisher)
	forceFish(sim, "Perch", "Neon")
	sim:Advance(FishingConfig.CastCooldown)
	mg, startTime = startMinigame(t, sim, fisher)
	t.eq((playMinigame(sim, fisher, mg, startTime)), "Caught")
	local neon = sim:WaitFor(function()
		return findEffect(fx, fisher, "RarityAura")
	end, FishingConfig.LeapTime + 0.5, FRAME)
	t.ok(neon, "a mutated Common fish sparkles too")
	t.eq(findEffect(fx, fisher, "RarityGlow"), nil, "no moving light for another player's trophy")
	local light = sim:WaitFor(function()
		return findEffect(own, fisher, "RarityGlow")
	end, 0.5, FRAME)
	t.ok(light and light:IsA("PointLight"), "Neon glows (own client)")
	t.eq(light.Brightness, 3)
	t.ok(colorNear(light.Color, UIConfig.Mutations.Neon.Top), "cyan")
	local commonPlate = sim:WaitFor(function()
		return findEffect(fx, fisher, "Nameplate")
	end, 0.5, FRAME)
	t.ok(commonPlate ~= nil, "Common: a nameplate too (v3 fix WOW-5)")
	t.eq(commonPlate.Plate:FindFirstChild("Rarity"), nil, "Common: no rarity line")
	t.eq(commonPlate.Plate.FishName.Text, "Окунь-полосатик")
	t.ok(commonPlate.Plate:FindFirstChild("Price") ~= nil, "…and its price")
	sim:AssertNoErrors({ warnings = true })
end

tests["rainbow painter: Heartbeat only while a rainbow fish is out; far fish are not repainted"] = function(t)
	local sim = boot(t)
	local viewer = addPlayer(sim, 1)
	sim:Advance(0.5)
	local ctx = sim:ContextName(viewer)
	local function heartbeats(): number
		return sim:CountConnections(function(conn: any)
			return conn.ctx.name == ctx and string.find(conn.signal:describe(), "Heartbeat", 1, true) ~= nil
		end)
	end
	local idle = heartbeats()
	local template = sim:Find("ReplicatedStorage.Assets.Fish.Perch.Rainbow")
	local root = viewer.Character.HumanoidRootPart.Position
	local near = template:Clone()
	near:PivotTo(roblox.CFrame.new(root + Vector3.new(6, 2, 0)))
	near.Parent = sim.workspace
	sim:Advance(0.1)
	t.eq(heartbeats(), idle + 1, "a rainbow fish in the world: the painter runs")
	local far = template:Clone()
	far:PivotTo(roblox.CFrame.new(root + Vector3.new(0, Fx.Range + 400, 0)))
	far.Parent = sim.workspace
	local function part(model: any): any
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("RainbowU") ~= nil then
				return d
			end
		end
		return nil
	end
	local function color(target: any): any
		return sim:Run(function()
			return target.Color
		end, viewer)
	end
	local nearPart, farPart = part(near), part(far)
	local n0, f0 = color(nearPart), color(farPart)
	sim:Advance(0.5)
	local n1, f1 = color(nearPart), color(farPart)
	t.ok(math.abs(n0.R - n1.R) + math.abs(n0.G - n1.G) + math.abs(n0.B - n1.B) > 0.03, "a near one shimmers")
	t.ok(colorNear(f0, f1), "one beyond Fx.Range is left alone")
	-- v3 fix F3: a rainbow fish in a character's hands (HeldFish) is repainted at most
	-- RAINBOW_HELD_RATE (5) times a second, in hue steps, and only within FX.LifeNear
	local held = template:Clone()
	held.Name = "RainbowHeld" -- (not "HeldFish": FishLife would try to animate it)
	held:PivotTo(viewer.Character.HumanoidRootPart.CFrame + Vector3.new(0, 4, 0))
	held.Parent = viewer.Character
	local heldPart = part(held)
	local changes, last = 0, color(heldPart)
	for _ = 1, 60 do -- 1 s of frames
		sim:Advance(1 / 60)
		local c = color(heldPart)
		if not colorNear(c, last) then
			changes += 1
			last = c
		end
	end
	t.ok(changes >= 2 and changes <= 6, `held: repainted {changes} times in 1 s (≤ 5 Hz, stepped)`)
	held:Destroy()
	near:Destroy()
	far:Destroy()
	sim:Advance(0.1)
	t.eq(heartbeats(), idle, "no rainbow fish out: no Heartbeat (the templates do not count)")
	sim:AssertNoErrors({ warnings = true })
end

tests["far bobbers (beyond Fx.Range): no line, moved a few times a second; ripples reuse their rigs"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local far = addPlayer(sim, 2)
	ready(sim, fisher)
	-- the far watcher across the lagoon (the opposite base, ~ 500 studs)
	local spot = spotOf(sim, fisher).Position
	sim:Teleport(far, Vector3.new(-spot.X, spot.Y + 3, -spot.Z))
	local own, other = clientFx(sim, fisher), clientFx(sim, far)
	sim:FireServer(fisher, "FishingCast")
	sim:Advance(FishingConfig.CastWindUp + FishingConfig.CastFlightTime + 0.6)
	local mine, theirs = own.GetBobber(fisher), other.GetBobber(fisher)
	t.ok(mine and theirs, "both clients have the bobber")
	local function beamOf(model: any): any
		return model:FindFirstChildWhichIsA("Beam", true)
	end
	t.eq(beamOf(mine).Enabled, true, "near: the line is drawn")
	t.eq(beamOf(theirs).Enabled, false, "far: no line across the lagoon")
	-- far: PivotTo at most every FAR_PIVOT (0.25 s) — count the moves over one second
	local root = theirs.PrimaryPart or theirs:FindFirstChildWhichIsA("BasePart")
	local moves, last = 0, root.Position
	for _ = 1, 60 do
		sim:Advance(1 / 60)
		local p = root.Position
		if (p - last).Magnitude > 1e-4 then
			moves += 1
			last = p
		end
	end
	t.ok(moves <= 5, `far bobber moved {moves} times in 1 s (≤ 4–5)`)
	-- ripples: the rigs go back to the fisher's pool and come out again (no new Instances)
	local seen = {}
	for _ = 1, 10 do
		sim:Advance(Fx.RippleEvery)
		for _, instance in own.GetEffects(fisher) do
			if instance.Name == "Ripple" then
				seen[instance] = true
			end
		end
	end
	local distinct = 0
	for _ in seen do
		distinct += 1
	end
	t.ok(distinct >= 1 and distinct <= 8, `ripple rigs reused: {distinct} distinct parts over 10 ripples`)
	sim:AssertNoErrors({ warnings = true })
end

tests["pillar for the others: wider with distance (≥ 25 px from the neighbouring pier), longer than the own one"] = function(
	t
)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local neighbour = addPlayer(sim, 2)
	forceFish(sim, "SharkPup") -- Legendary
	ready(sim, fisher)
	-- The neighbour stands on their own pier (the next base round the lagoon).
	sim:Teleport(neighbour, spotOf(sim, neighbour).Position + Vector3.new(0, 3, 0))
	local own, other = clientFx(sim, fisher), clientFx(sim, neighbour)
	local mg, startTime = startMinigame(t, sim, fisher)
	local name, caughtAt = playMinigame(sim, fisher, mg, startTime, false)
	t.eq(name, "Caught")
	sim:WaitFor(function()
		return findEffect(other, fisher, "PillarGlow") ~= nil and findEffect(own, fisher, "PillarGlow") ~= nil
	end, FishingConfig.LeapTime + 1, FRAME)
	local theirs, mine = findEffect(other, fisher, "PillarGlow"), findEffect(own, fisher, "PillarGlow")
	t.ok(theirs and mine, "both clients raise the pillar")
	local distance = (theirs.Position - sim:GetRoot(neighbour).Position).Magnitude
	t.ok(distance > 150, `the neighbour is far ({math.floor(distance)} studs)`)
	-- Phone (390 px tall, vertical FOV 70): px per stud at that distance.
	local px = theirs.Glow.Width0 * (390 / 2) / math.tan(math.rad(35)) / distance
	t.ok(px >= 25, `the glow is {math.floor(px)} px wide from the neighbouring pier (≥ 25)`)
	t.ok(mine.Glow.Width0 < theirs.Glow.Width0, "the fisher's own pillar stays narrow")
	-- Lifetimes: the own pillar goes after PillarTime, the neighbour's lives PillarTimeOther.
	local landed = caughtAt + FishingConfig.LeapTime
	sim:Advance(math.max(landed + OWN_PILLAR_DELAY + Fx.PillarTime.Legendary + 0.2 - sim:Time(), 0))
	t.eq(findEffect(own, fisher, "PillarGlow"), nil, "the own pillar is gone (the card covers it anyway)")
	t.ok(findEffect(other, fisher, "PillarGlow"), "the neighbour still sees it")
	sim:Advance(Fx.PillarTimeOther.Legendary - Fx.PillarTime.Legendary - OWN_PILLAR_DELAY)
	t.eq(findEffect(other, fisher, "PillarGlow"), nil, "… until PillarTimeOther")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- v3 [fx]: the held fish alive, the fish shadow, the cast / line polish, the leap flex
--------------------------------------------------------------------------------

-- A player with an R15 rig (the sim then solves the welds per client: HeldFish follows the
-- watcher's client-local HoldWeld C0).
local function addRigged(sim: any, id: number): any
	local player = sim:AddPlayer({
		UserId = id,
		Name = `Player{id}`,
		DisplayName = `Игрок{id}`,
		device = "phone",
		rig = "R15",
	})
	sim:Advance(0.5)
	return player
end

local function angleBetween(a: any, b: any): number
	local _, angle = (a:Inverse() * b):ToAxisAngle()
	return math.deg(math.abs(angle))
end

tests["held fish alive: flops, bobs and wiggles on the watcher's client only; the nameplate stays put; restored; nothing per frame after"] = function(
	t
)
	local sim = boot(t)
	local fisher = addRigged(sim, 1)
	local watcher = addPlayer(sim, 2)
	local far = addPlayer(sim, 3)
	forceFish(sim, "Puffer") -- Rare: a nameplate
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	sim:Teleport(far, spotOf(sim, fisher).Position + Vector3.new(0, 170, 0)) -- within Fx.Range, beyond LifeRange
	local fx = clientFx(sim, watcher)
	sim:Advance(0.5)
	local rendering = renderSteppedCount(sim, watcher)
	local connections = sim:CountConnections(watcher)

	local mg, startTime = startMinigame(t, sim, fisher)
	t.eq((playMinigame(sim, fisher, mg, startTime)), "Caught")
	local held = sim:WaitFor(function()
		local leap = findEffect(fx, fisher, "Leap")
		local model = fisher.Character:FindFirstChild("HeldFish")
		return if model and leap == nil then model else nil
	end, FishingConfig.LeapTime + 1, FRAME)
	t.ok(held, "the held fish is over the head, the leap handed it over")
	local body = held.PrimaryPart
	local weld = body.HoldWeld
	local serverC0 = weld.C0 -- the replicated value (the server never changes it)
	local tail, tailWeld = nil, nil
	for _, d in held:GetDescendants() do
		if d:IsA("BasePart") and d.Name == "Tail" then
			tail = d
			tailWeld = d:FindFirstChild("HoldWeld")
		end
	end
	t.ok(tail and tailWeld, "the Puffer's tail is welded to its body")
	local tailC0 = tailWeld.C0
	local plate = sim:WaitFor(function()
		return findEffect(fx, fisher, "Nameplate")
	end, 0.5, FRAME)
	t.ok(plate, "a nameplate over it")

	-- What the watcher sees over 3 s (at least one flop: FIRST_FLOP 0.35 s, then every ≤ 2.2 s).
	local rest = body.CFrame -- the pose the leap handed over
	local headRest = fisher.Character.Head.CFrame
	local maxMove, maxTurn, tailMoved, weldMoved = 0, 0, 0, 0
	local plateLo, plateHi, bodyLo, bodyHi = math.huge, -math.huge, math.huge, -math.huge
	local farMoved = 0
	sim:WaitFor(function()
		sim:Run(function()
			local head = fisher.Character.Head.CFrame
			local seen = head * headRest:Inverse() * rest -- the rest pose where the head is now
			maxMove = math.max(maxMove, (body.Position - seen.Position).Magnitude)
			maxTurn = math.max(maxTurn, angleBetween(seen, body.CFrame))
			weldMoved = math.max(weldMoved, (weld.C0.Position - serverC0.Position).Magnitude)
			tailMoved = math.max(tailMoved, angleBetween(tailWeld.C0, tailC0))
			-- (relative to the head: the fisher himself squats, jumps and pumps with the trophy now)
			local headY = fisher.Character.Head.Position.Y
			local y = body.Position.Y + plate.StudsOffsetWorldSpace.Y - headY
			local bodyY = body.Position.Y - headY
			plateLo, plateHi = math.min(plateLo, y), math.max(plateHi, y)
			bodyLo, bodyHi = math.min(bodyLo, bodyY), math.max(bodyHi, bodyY)
		end, watcher)
		sim:Run(function()
			farMoved = math.max(farMoved, (weld.C0.Position - serverC0.Position).Magnitude)
		end, far)
		return false
	end, 3, FRAME)
	t.ok(weldMoved > 0.05, `the watcher's client moves the HoldWeld ({weldMoved} studs)`)
	t.near(weld.C0, serverC0, 1e-6, "…client-locally: the server's C0 never changes")
	t.ok(maxMove > 0.1 and maxMove < 1.2, `it bobs and hops a little ({maxMove} studs)…`)
	t.ok(maxTurn > 5 and maxTurn < 45, `…and flops, but stays the same trophy ({maxTurn}°)`)
	t.ok(tailMoved > 4, `the body bends: the tail swings on its weld ({tailMoved}°)`)
	t.ok(
		plateHi - plateLo < (bodyHi - bodyLo) * 0.8 and plateHi - plateLo < 0.4,
		`the nameplate bobs gently, not with every flop (plate {plateHi - plateLo}, body {bodyHi - bodyLo})`
	)
	t.eq(farMoved, 0, "a viewer farther than LifeRange: the fish is left at rest (no weld writes)")

	sim:Advance(FishingConfig.HoldFishTime.Rare, COARSE)
	t.eq(fisher.Character:FindFirstChild("HeldFish"), nil, "the held fish is gone")
	sim:Advance(0.5)
	t.eq(renderSteppedCount(sim, watcher), rendering, "no per-frame work left on the watcher's client")
	t.eq(sim:CountConnections(watcher), connections, `no connections left\n{sim:FormatConnections(watcher)}`)
	sim:AssertNoErrors({ warnings = true })
end

-- The own client's FishingFx folder (where its bobber lives).
local function shadowOf(fx: any, fisher: any): (any, any)
	local bobber = fx.GetBobber(fisher)
	local folder = bobber and bobber.Parent
	if not folder then
		return nil, nil
	end
	return folder:FindFirstChild("FishShadow"), folder:FindFirstChild("FishShadowTail")
end

local function flatDistance(a: any, b: any): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

tests["cast and line: the tip's whip trail at the release, a curved line in flight, the landing plop"] = function(t)
	local sim = boot(t)
	local fisher = addRigged(sim, 1) -- (the rod tip in the hand: RbxSim poses only rigged characters)
	forceFish(sim, "Crucian")
	local rod = nil
	ready(sim, fisher)
	for _, item in fisher.Character:GetChildren() do
		if item:IsA("Tool") then
			rod = item
		end
	end
	local fx = clientFx(sim, fisher)
	sim:Advance(1.037) -- (keep CastTime fractional: RbxSim stores whole-number attributes as float32)
	sim:FireServer(fisher, "FishingCast")
	local castAt = sim:Time()
	local release = castAt + FishingConfig.CastWindUp
	local landing = release + FishingConfig.CastFlightTime
	local whipFrom, whipOff, whipGone, curved = nil, nil, nil, 0
	local lowest, restY, backUp = math.huge, nil, false
	local launched = nil -- the client's own release moment (its CastTrail turns on)
	sim:WaitFor(function()
		local whip = rod.Handle:FindFirstChild("Whip")
		local now = sim:Time()
		local cast = fx.GetBobber(fisher)
		if not launched and cast and cast.Root.CastTrail.Enabled then
			launched = now
		end
		if whip and whip.Enabled and not whipFrom then
			whipFrom = now
		elseif whip and not whip.Enabled and whipFrom and not whipOff then
			whipOff = now
		elseif not whip and whipFrom and not whipGone then
			whipGone = now
		end
		local bobber = fx.GetBobber(fisher)
		if bobber and now > release + 0.1 and now < landing - 0.1 then
			curved = math.max(curved, bobber.Line.CurveSize0)
		end
		if bobber and now >= landing then
			restY = restY or (fisher:GetAttribute("BobberTarget").Y + bobber:GetAttribute("FloatDepth"))
			local y = bobber:GetPivot().Position.Y
			lowest = math.min(lowest, y)
			backUp = backUp or (now > landing + 0.5 and math.abs(y - restY) <= 0.25)
		end
		return now >= landing + 1.2
	end, 3, FRAME)
	t.ok(whipFrom and launched, "a whip trail on the rod tip (Handle.Whip)")
	-- (against the client's own release: its server clock runs a little behind in RbxSim)
	t.ok(
		whipFrom >= launched - 0.15 - FRAME and whipFrom <= launched,
		`…from the forward swing, just before the float leaves the tip ({whipFrom - launched} s)`
	)
	t.ok(whipOff and whipOff - launched <= 0.25, "…off right after the release")
	t.ok(whipGone and whipGone - launched <= 0.6, "…and removed with its attachment")
	t.eq(rod.Handle:FindFirstChild("WhipBase"), nil, "no attachment left on the rod")
	t.ok(curved > 1, `the line trails the flying float in a curve (CurveSize0 {curved})`)
	t.ok(lowest < restY - 0.2, `the landing plop: the float dips under its waterline ({lowest - restY})`)
	t.ok(backUp, "…and floats back up")
	sim:AssertNoErrors({ warnings = true })
end

tests["fish shadow: swims in and circles, pokes on a nibble, lunges on the bite, bigger in a rare fight, flees when lost"] = function(
	t
)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "SharkPup") -- Legendary: a big shadow in the fight
	ready(sim, fisher)
	sim:Teleport(watcher, spotOf(sim, fisher).Position + Vector3.new(0, Fx.AmbientRange + 30, 0))
	local own = clientFx(sim, fisher)
	local other = clientFx(sim, watcher)
	sim:Advance(1.037)
	sim:FireServer(fisher, "FishingCast")
	local landing = sim:Time() + FishingConfig.CastWindUp + FishingConfig.CastFlightTime
	sim:WaitFor(function()
		return sim:Time() >= landing + 0.05
	end, 2, FRAME)
	local body, tail = shadowOf(own, fisher)
	t.ok(body and tail, "a fish shadow under the own bobber (FishShadow + FishShadowTail)")
	t.eq(body.Transparency, 1, "…unseen right after the landing")
	t.eq(body.Material, roblox.Enum.Material.SmoothPlastic, "SmoothPlastic: no LEGO studs")
	t.ok(body.Anchored and not body.CanCollide and not body.CanQuery and not body.CanTouch, "anchored and quiet")
	t.eq(body.CastShadow, false)
	t.ok(body:FindFirstChildOfClass("SpecialMesh"), "an ellipsoid body (SpecialMesh «Sphere»)")
	t.eq(shadowOf(other, fisher), nil, "a viewer farther than Fx.AmbientRange: no shadow")

	local water = fisher:GetAttribute("BobberTarget")
	local seen, near, far = 1, math.huge, 0
	sim:WaitFor(function()
		seen = math.min(seen, body.Transparency)
		local d = flatDistance(body.Position, water)
		near, far = math.min(near, d), math.max(far, d)
		return sim:Time() >= landing + 2.2
	end, 3, FRAME)
	t.ok(seen < 0.6, `it shows up (transparency {seen})`)
	t.ok(body.Position.Y < water.Y, "under the water")
	t.ok(far < 8.5 and near < 4, `it swims in and around the bobber ({near}..{far} studs)`)

	-- the own nibble: a poke right at the bobber
	local poked = math.huge
	t.eq(
		sim:Run(function()
			return own.Nibble()
		end, fisher),
		true,
		"a nibble"
	)
	sim:WaitFor(function()
		poked = math.min(poked, flatDistance(body.Position, water))
		return false
	end, 0.3, FRAME)
	t.ok(poked < 1.4, `…the shadow pokes the bobber ({poked} studs)`)

	-- the bite: it lunges under the bobber
	sim:WaitFor(function()
		return fisher:GetAttribute("FishingState") == "Bite"
	end, 10, FRAME)
	sim:Advance(0.2)
	t.ok(flatDistance(body.Position, water) < 2, "the bite: right under the bobber")

	-- the fight (own Legendary): bigger
	local count = #stateEvents(sim, fisher)
	sim:FireServer(fisher, "FishingHook")
	local name = nextState(sim, fisher, count, 1)
	t.eq(name, "Minigame")
	sim:Advance(0.3)
	t.near(body.Size.X, 2.6 * 1.6, 0.05, "the own Legendary fight: a 1.6× shadow (FX.ShadowScale)")

	-- lost (a miss): it darts away from the fisher and fades, then goes with the bobber
	local root = sim:GetRoot(fisher).Position
	local before = flatDistance(body.Position, root)
	local mg = stateEvents(sim, fisher)[count + 1].args[2]
	local moment = findMoment(sim, mg, mg.ZoneCenter, FishingConfig.HookTapGrace + 0.05, false)
	sim:WaitFor(function()
		return sim:Time() >= stateEvents(sim, fisher)[count + 1].time + moment
	end, 10, FRAME)
	sim:FireServer(fisher, "FishingTap", moment)
	local fled, faded = 0, 0
	sim:WaitFor(function()
		if body.Parent then
			fled = math.max(fled, flatDistance(body.Position, root) - before)
			faded = math.max(faded, body.Transparency)
		end
		return body.Parent == nil
	end, 2, FRAME)
	t.ok(fled > 4, `it flees away from the fisher ({fled} studs)`)
	t.ok(faded > 0.9, "…fading out")
	t.eq(body.Parent, nil, "gone with the bobber")
	sim:AssertNoErrors({ warnings = true })
end

tests["leap: the caught fish flexes its tail and drips water; the drips are gone before the hand-over"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "Perch")
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local fx = clientFx(sim, watcher)
	local mg, startTime = startMinigame(t, sim, fisher)
	t.eq((playMinigame(sim, fisher, mg, startTime)), "Caught")
	local leap = sim:WaitFor(function()
		return findEffect(fx, fisher, "Leap")
	end, 0.3, FRAME)
	t.ok(leap, "the leap")
	local tail = leap:FindFirstChild("Tail")
	t.ok(tail, "the Perch's tail")
	local restTail = leap:GetPivot():ToObjectSpace(tail.CFrame)
	local bend, drips, maxDrips = 0, {}, 0
	local quiet = true
	sim:WaitFor(function()
		if leap.Parent then
			local now = leap:GetPivot():ToObjectSpace(tail.CFrame)
			bend = math.max(bend, angleBetween(now, restTail))
		end
		local alive = 0
		for _, instance in fx.GetEffects(fisher) do
			if instance.Name == "Drip" then
				drips[instance] = true
				alive += 1
				if
					not instance.Anchored
					or instance.CanCollide
					or instance.CanQuery
					or instance.CastShadow
					or instance.Material ~= roblox.Enum.Material.SmoothPlastic
				then
					quiet = false
				end
			end
		end
		maxDrips = math.max(maxDrips, alive)
		return leap.Parent == nil
	end, FishingConfig.LeapTime + 1, FRAME)
	local made = 0
	for drip in drips do
		made += 1
		t.eq(drip.Parent, nil, "every drip is gone")
	end
	t.ok(bend > 8, `the tail flexes against the body in the air ({bend}°)`)
	t.ok(made >= 5 and made <= 12, `water drips off the fish ({made} drops, ≤ 12)`)
	t.ok(quiet, "drips are anchored, quiet, SmoothPlastic")
	sim:AssertNoErrors({ warnings = true })
end

tests["own bobber in the fight: every hit (Zone) tugs it toward the pier"] = function(t)
	local sim = boot(t)
	local fisher = addRigged(sim, 1) -- (a rig: the rod tip, where the line pulls, is in the hand)
	forceFish(sim, "SharkPup") -- two hits: the first one is a Zone
	ready(sim, fisher)
	local fx = clientFx(sim, fisher)
	local mg, startTime = startMinigame(t, sim, fisher)
	local samples = {}
	local zoneAt = nil
	local before = #stateEvents(sim, fisher)
	local name = playMinigame(sim, fisher, mg, startTime, false, function()
		sim:Run(function()
			local bobber = fx.GetBobber(fisher)
			local root = fisher.Character and fisher.Character:FindFirstChild("HumanoidRootPart")
			if bobber and root then
				local d = flat(bobber:GetPivot().Position - root.Position).Magnitude
				table.insert(samples, { time = sim:Time(), d = d })
			end
		end, fisher)
		local entry = stateEvents(sim, fisher)[before + 1]
		if not zoneAt and entry and entry.args[1] == "Zone" then
			zoneAt = entry.time
		end
	end)
	t.eq(name, "Caught")
	t.ok(zoneAt ~= nil, "the first hit was a Zone")
	local function at(time: number): number
		local best = math.huge
		for _, s in samples do
			if s.time <= time + 1e-6 then
				best = s.d
			end
		end
		return best
	end
	local zone = zoneAt :: number
	local at0, after = at(zone), at(zone + 0.3)
	t.ok(at0 - after > 2.5, `the hit tugs the bobber toward the pier ({at0} → {after} studs)`)
	sim:AssertNoErrors({ warnings = true })
end

return tests
