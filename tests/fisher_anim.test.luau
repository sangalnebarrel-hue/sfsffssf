--[[
	Procedural fisher animation (FisherAnimController + FisherRig / FisherPoses / FisherRod), run
	in RbxSim against the built Place1.rbxl with the real server and real clients, on rigged
	characters (sim:AddPlayer{ rig = "R15" | "R6", joints = "Motor6D" | "AnimationConstraint" }):
	the sim's Animator stand-in resets every joint's Transform before PreSimulation (identity =
	"idle", or sim:SetAnimatorPose), forward kinematics moves limbs / the rod (RightGrip) /
	HeldFish per client view, so a client's Transform and rod-weld writes are seen by that
	client only.

	What is checked:
	  • every client poses every fisher nearby from replicated data (the watcher sees the
	    fisher's Wait pose), the server keeps the Animator pose (Transform is never replicated);
	  • no accumulation: the pose is stable over many frames, also with throttled Animator frames;
	  • the cast is synced with the bobber: wind-up (rod tip behind and above the head, the float
	    hanging at the tip) until CastTime = cast + FishingConfig.CastWindUp, then the rod whips
	    forward (tip in front) and the float leaves from the tip; trail and whoosh at the release;
	  • bite: the rod tip dips with the bobber (FishingFxController.GetBobberDip);
	  • reel: the rod bends (rod weld C0 + TipAttachment moved; the line still starts at the tip),
	    restored exactly when the fishing ends;
	  • catch: both hands go up under the HeldFish over the head, down again after it is gone;
	  • lost: the head hangs down;
	  • walking: torso and head go back to the normal animation at once, the arms stay posed;
	  • LOD: a fisher farther than 150 studs is not touched; nothing per frame (no PreSimulation
	    connection) when nobody fishes nearby; joints restored exactly afterwards;
	  • R6 and AnimationConstraint (Avatar Joint Upgrade) rigs; joints replaced mid-session;
	  • own client: Cue("castPress") winds up at once, an unanswered cast is put down again;
	  • v3 cartoon beats: the rod held right of the bobber, the 3/4 side-arm cast holding the
	    throw until the landing, the Epic+ hop, the landing squat + jump (+ spin for
	    Legendary / Mythic), the trophy show-off loop synced with a fish kick, the replay
	    celebration, wait fidgets, predicted tap pulls / miss fumbles, the rod's sideways whip
	    and bigger Epic+ bend; R6 never shifts the RootJoint; far fishers' layers / pulses stay
	    bounded; a steady rod bend is not rewritten every frame.

	Run: lune run tools/run_tests.luau fisher_anim
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local PLACE = "Place1.rbxl"
local FRAME = 1 / 60

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
local Poses = luau.load(fs.readFile("src/StarterPlayer/StarterPlayerScripts/Controllers/FisherPoses.luau"))()

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function boot(t: any): any
	local sim = t.sim({ place = PLACE })
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

local function addPlayer(sim: any, id: number, rig: string?, joints: string?): any
	local player = sim:AddPlayer({
		UserId = id,
		Name = `Player{id}`,
		DisplayName = `Игрок{id}`,
		device = "phone",
		rig = rig or "R15",
		joints = joints,
	})
	sim:Advance(0.5)
	return player
end

local function service(sim: any): any
	return sim:Require(sim:Find("ServerScriptService.Services.FishingService"))
end

local function rules(sim: any): any
	return sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"))
end

local function controller(sim: any, player: any, name: string): any
	local module = sim:Find(`Controllers.{name}`, player:FindFirstChildOfClass("PlayerScripts"))
	assert(module, `{name} in PlayerScripts`)
	return sim:Require(module, player)
end

local function baseOf(sim: any, player: any): any
	local base = sim.workspace.Bases:FindFirstChild(`Base_{player:GetAttribute("BaseIndex")}`)
	assert(base, `{player.Name}: own base`)
	return base
end

-- On its own fishing spot, facing out from the pier (the bobber flies that way), rod in hand.
local function ready(sim: any, player: any): any
	local base = baseOf(sim, player)
	local at = base.FishingSpot.Position + Vector3.new(0, 3, 0)
	local look = base:GetPivot().LookVector
	sim:Teleport(player, CFrame.lookAt(at, at + Vector3.new(look.X, 0, look.Z)))
	local rod = nil
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		for _, item in container:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute("RodId") ~= nil then
				rod = item
			end
		end
	end
	assert(rod, "no rod")
	sim:EquipTool(player, rod)
	sim:Advance(0.1)
	return rod
end

local function standBeside(sim: any, viewer: any, fisher: any)
	sim:Teleport(viewer, baseOf(sim, fisher).FishingSpot.Position + Vector3.new(6, 3, 6))
end

local function forceFish(sim: any, id: string)
	local fr = rules(sim)
	local def = fr.GetFish(id)
	local value, income = fr.Price(id, def.MinKg, nil)
	local fish = { Id = id, Rarity = def.Rarity, Kg = def.MinKg, Value = value, Income = income }
	service(sim).RollFishForTest = function()
		return table.clone(fish)
	end
end

-- Reads something as one client sees it (client-local joint / part / attachment values).
local function seen(sim: any, who: any, fn: () -> any): any
	return sim:Run(fn, who)
end

local function joint(player: any, name: string): any
	local found = player.Character:FindFirstChild(name, true)
	assert(found, `joint {name}`)
	return found
end

-- Rotation angle between two CFrames, degrees.
local function angle(a: any, b: any): number
	local _, _, _, r00, _, _, _, r11, _, _, _, r22 = (a:Inverse() * b):GetComponents()
	return math.deg(math.acos(math.clamp((r00 + r11 + r22 - 1) / 2, -1, 1)))
end

local function pose(name: string, channel: string): any
	local a = Poses.Poses[name][channel]
	return CFrame.fromEulerAnglesYXZ(math.rad(a[1]), math.rad(a[2]), math.rad(a[3]))
end

local function stateEvents(sim: any, player: any): { any }
	return sim:ClientEventsFor(player, "FishingState")
end

local function nextState(sim: any, player: any, start: number, timeout: number): (string?, any, number?)
	local entry = sim:WaitFor(function()
		return stateEvents(sim, player)[start + 1]
	end, timeout, FRAME)
	if not entry then
		return nil, nil, nil
	end
	return entry.args[1], entry.args[2], entry.time
end

-- Waits (frame by frame) until the server's bite, then hooks: the "Minigame" payload and time.
local function hookFish(t: any, sim: any, player: any): (any, number)
	local bite = nextState(sim, player, #stateEvents(sim, player), 10)
	t.eq(bite, "Bite", "the fish bites")
	sim:Advance(0.2)
	local count = #stateEvents(sim, player)
	sim:FireServer(player, "FishingHook")
	local name, data, time = nextState(sim, player, count, 1)
	t.eq(name, "Minigame", "hooked")
	return data, time :: number
end

-- A zero-latency perfect (or missing) player in the minigame. Returns the final event name.
local function playMinigame(sim: any, player: any, mg: any, startTime: number, miss: boolean?): string?
	local fr = rules(sim)
	local center = mg.ZoneCenter
	local from = if miss then FishingConfig.HookTapGrace + 0.05 else FishingConfig.TapInterval + 0.02
	for _ = 1, mg.HitsNeeded do
		local moment = from
		while true do
			local d = math.abs(fr.Needle(mg.U0, mg.Speed, moment) - center)
			if (not miss and d <= mg.ZoneWidth * 0.3) or (miss and d >= mg.ZoneWidth / 2 + 0.05) then
				break
			end
			moment += 0.005
		end
		sim:WaitFor(function()
			return sim:Time() >= startTime + moment - 1e-9
		end, 10, FRAME)
		local count = #stateEvents(sim, player)
		sim:FireServer(player, "FishingTap", moment)
		local name, data = nextState(sim, player, count, 0.2)
		if name ~= "Zone" then
			return name
		end
		center = data.ZoneCenter
		from = moment + FishingConfig.TapInterval + 0.02
	end
	return nil
end

local function preSimulationCount(sim: any, who: any?): number
	local ctxName = who and sim:ContextName(who)
	return sim:CountConnections(function(conn: any)
		return (ctxName == nil or conn.ctx.name == ctxName)
			and conn.ctx.kind == "client"
			and string.find(conn.signal:describe(), "PreSimulation", 1, true) ~= nil
	end)
end

-- Local position (in the fisher's HumanoidRootPart frame) of a world point.
local function rootLocal(player: any, point: any): any
	return player.Character.HumanoidRootPart.CFrame:PointToObjectSpace(point)
end

-- Heading of a point seen from the fisher's root (degrees, + = to his right).
local function heading(player: any, point: any): number
	local p = rootLocal(player, point)
	return math.deg(math.atan2(p.X, -p.Z))
end

-- The rod is held out over the water, to the RIGHT of the bobber (FisherPoses: the bend and the
-- line read from the camera behind him).
local function heldOut(t: any, player: any, tip: any, label: string)
	local p = rootLocal(player, tip)
	t.ok(
		math.sqrt(p.X * p.X + p.Z * p.Z) > 3 and p.Z < 0 and p.Y > 2.5,
		`{label}: rod held out over the water, tip at {p}`
	)
	local water = player:GetAttribute("BobberTarget")
	local tipHeading, waterHeading = heading(player, tip), heading(player, water)
	t.ok(
		tipHeading > waterHeading + 10 and tipHeading < waterHeading + 70,
		`{label}: the rod points right of the bobber ({tipHeading}° vs {waterHeading}°)`
	)
end

local tests = {}

--------------------------------------------------------------------------------
-- Waiting: every client poses the fisher, the server does not; no accumulation
--------------------------------------------------------------------------------

tests["waiting: the watcher poses the fisher locally, the server keeps the Animator pose, no drift"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	t.eq(preSimulationCount(sim), 0, "nothing per frame before anyone fishes")
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	sim:FireServer(fisher, "FishingCast")
	sim:Advance(FishingConfig.CastWindUp + FishingConfig.CastFlightTime + 0.8)
	t.eq(fisher:GetAttribute("FishingState"), "Waiting")
	local shoulder = joint(fisher, "RightShoulder")
	local wait = pose("Wait", "RShoulder")

	-- throttled Animator frames (every 3rd frame skipped): the base cache keeps the pose stable
	sim:ThrottleAnimator(fisher, 3)
	local first = seen(sim, watcher, function()
		return shoulder.Transform
	end)
	local worst, drift = 0, 0
	for _ = 1, 90 do
		sim:Step(FRAME)
		local now = seen(sim, watcher, function()
			return shoulder.Transform
		end)
		worst = math.max(worst, angle(now, wait))
		drift = math.max(drift, angle(now, first))
	end
	sim:ThrottleAnimator(fisher, nil)
	t.ok(worst < 6, `the watcher sees the Wait pose (± sway): {worst}°`)
	t.ok(drift < 6, `no accumulation over 90 frames with throttled frames: {drift}°`)
	t.near(shoulder.Transform, CFrame.identity, 1e-6, "the server still reads the Animator pose (not replicated)")
	local mine = seen(sim, fisher, function()
		return shoulder.Transform
	end)
	t.ok(angle(mine, wait) < 15, "the fisher's own client poses itself too")

	-- arms visibly in the pose on the watcher's client: the rod tip ≈48° up in front
	local rod = fisher.Character:FindFirstChildOfClass("Tool")
	local tip = seen(sim, watcher, function()
		return rod.Handle.TipAttachment.WorldPosition
	end)
	heldOut(t, fisher, tip, "R15")
	local anim = controller(sim, watcher, "FisherAnimController")
	t.eq(anim.GetPhase(fisher), "Wait")
	t.eq(anim.IsAnimating(fisher), true)
	t.eq(preSimulationCount(sim, watcher), 1, "one PreSimulation connection for all fishers")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Cast: synced with the bobber (CastWindUp)
--------------------------------------------------------------------------------

tests["cast: wind-up with the float at the tip, rod whips forward at CastTime, the float leaves from the tip"] = function(
	t
)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	local rod = ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	sim:Advance(1)
	local fx = controller(sim, watcher, "FishingFxController")
	local anim = controller(sim, watcher, "FisherAnimController")
	local phases = {}
	sim:Run(function()
		anim.PhaseChanged:Connect(function(player, phase)
			if player == fisher then
				table.insert(phases, phase)
			end
		end)
	end, watcher)

	sim:FireServer(fisher, "FishingCast")
	local castTime = fisher:GetAttribute("CastTime")
	t.near(castTime, sim.workspace:GetServerTimeNow() + FishingConfig.CastWindUp, 1e-3, "CastTime = cast + CastWindUp")
	local function tipNow(): any
		return seen(sim, watcher, function()
			return rod.Handle.TipAttachment.WorldPosition
		end)
	end
	local head = fisher.Character.Head

	-- cocked (3/4 side-arm): the tip high above the head and out to his right, not over the
	-- water yet; the float hangs on it
	sim:WaitFor(function()
		return sim.workspace:GetServerTimeNow() >= castTime - 0.07
	end, 1, FRAME)
	local cocked = tipNow()
	local cockedLocal = rootLocal(fisher, cocked)
	t.ok(cockedLocal.X > 1 and cockedLocal.Z > -1.5, `wind-up: the rod tip is up and out to the right ({cockedLocal})`)
	t.ok(cocked.Y > head.Position.Y + 2, "… and high above the head")
	local bobber = fx.GetBobber(fisher)
	t.ok(bobber, "the bobber exists during the wind-up")
	-- (the float follows the tip read in RenderStepped, one frame behind a fast swing)
	local hang = seen(sim, watcher, function()
		return bobber:GetPivot().Position
	end)
	t.ok(
		(hang - cocked).Magnitude < 2 and rootLocal(fisher, hang).Z > -1.5,
		`the float hangs at the rod tip during the wind-up ({(hang - cocked).Magnitude})`
	)
	t.eq(bobber.Root.CastTrail.Enabled, false, "no trail before the float leaves the tip")

	-- the release: rod forward, float leaves from the tip with the trail
	sim:WaitFor(function()
		return sim.workspace:GetServerTimeNow() >= castTime + FRAME
	end, 1, FRAME)
	local released = rootLocal(fisher, tipNow())
	t.ok(released.Z < -3, `at CastTime the rod tip is out in front ({released})`)
	t.ok((bobber:GetPivot().Position - tipNow()).Magnitude < 3, "the float leaves from the tip")
	t.eq(bobber.Root.CastTrail.Enabled, true, "the trail starts at the release")
	t.ok(table.find(phases, "Release") ~= nil, "PhaseChanged: Release")
	sim:Advance(0.12)
	t.ok(rootLocal(fisher, tipNow()).Y < released.Y, "follow-through: the rod goes down toward the water")
	-- the rod stays low and forward while the float is in the air (until it lands)
	sim:Advance(FishingConfig.CastFlightTime - 0.25)
	t.eq(anim.GetPhase(fisher), "Cast", "still following the float in the air")
	t.ok(rootLocal(fisher, tipNow()).Y < released.Y, "… the rod still low toward the water")
	sim:Advance(Poses.Timing.Settle + 0.2)
	t.eq(anim.GetPhase(fisher), "Wait", "settled into waiting after the landing")
	t.ok(table.find(phases, "Cast") ~= nil and table.find(phases, "Wait") ~= nil)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Bite and reel: the rod follows the bobber and bends
--------------------------------------------------------------------------------

tests["bite and reel: the tip dips with the bobber; the rod bends, the line stays on the tip; restored after"] = function(
	t
)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "Crucian")
	local rod = ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local fx = controller(sim, watcher, "FishingFxController")
	local anim = controller(sim, watcher, "FisherAnimController")
	local tip = rod.Handle.TipAttachment
	local tipOriginal = tip.CFrame
	local welds = {}
	for _, d in rod:GetDescendants() do
		if d:IsA("Weld") and d.Name == "Weld" then
			welds[d] = d.C0
		end
	end

	sim:FireServer(fisher, "FishingCast")
	local bite = nextState(sim, fisher, #stateEvents(sim, fisher), 10)
	t.eq(bite, "Bite")
	-- tip height vs the bobber's dip, sampled on the watcher's client
	local low, high = {}, {}
	for _ = 1, 80 do
		sim:Step(FRAME)
		local dip, y = seen(sim, watcher, function()
			return fx.GetBobberDip(fisher), tip.WorldPosition.Y
		end)
		if dip > 0.5 then
			table.insert(low, y)
		elseif dip < 0.1 then
			table.insert(high, y)
		end
	end
	local function mean(list: { number }): number
		local sum = 0
		for _, v in list do
			sum += v
		end
		return sum / math.max(#list, 1)
	end
	t.ok(#low > 3 and #high > 3, "both deep and shallow dips sampled")
	t.ok(mean(low) < mean(high) - 0.3, `the tip dips with the bobber ({mean(high)} → {mean(low)})`)

	local count = #stateEvents(sim, fisher)
	sim:FireServer(fisher, "FishingHook")
	local name, mg, start = nextState(sim, fisher, count, 1)
	t.eq(name, "Minigame")
	sim:Advance(0.6)
	t.eq(anim.GetPhase(fisher), "Reel", "Bite → Reeling: strike, then the fight")
	local bend = seen(sim, watcher, function()
		return anim.GetRodBend(fisher)
	end)
	t.ok(bend > math.rad(12), `the rod bends under the fish ({math.deg(bend)}°)`)
	local bentTip = seen(sim, watcher, function()
		return tip.CFrame
	end)
	t.ok((bentTip.Position - tipOriginal.Position).Magnitude > 0.5, "TipAttachment follows the bent tip")
	local line = fx.GetBobber(fisher):FindFirstChild("Line")
	t.ok(line.Attachment0 == tip, "the line still starts at the rod's TipAttachment")
	t.near(tip.CFrame, tipOriginal, 1e-6, "the bend is client-local (the server's rod is straight)")

	-- reel crank: the left elbow moves
	local elbow = joint(fisher, "LeftElbow")
	local a = seen(sim, watcher, function()
		return elbow.Transform
	end)
	sim:Advance(0.11)
	local b = seen(sim, watcher, function()
		return elbow.Transform
	end)
	t.ok(angle(a, b) > 5, "the left hand cranks the reel")

	t.eq(playMinigame(sim, fisher, mg, start :: number), "Caught")
	sim:Advance(FishingConfig.HoldFishTime.Common + 6)
	t.eq(fisher.Character:FindFirstChild("HeldFish"), nil)
	seen(sim, watcher, function()
		t.near(tip.CFrame, tipOriginal, 1e-6, "TipAttachment restored exactly")
		for weld, c0 in welds do
			t.near(weld.C0, c0, 1e-6, "rod welds restored exactly")
		end
	end)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Catch: hands up under the fish; lost: head down
--------------------------------------------------------------------------------

tests["catch: both hands up under the held fish, a hop; down again when it is gone; then released"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "Crucian")
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local anim = controller(sim, watcher, "FisherAnimController")
	sim:FireServer(fisher, "FishingCast")
	local mg, start = hookFish(t, sim, fisher)
	t.eq(playMinigame(sim, fisher, mg, start), "Caught")
	local caughtAt = sim:Time()
	sim:WaitFor(function()
		return fisher.Character:FindFirstChild("HeldFish") ~= nil
	end, FishingConfig.LeapTime + 1, FRAME)
	local held = fisher.Character:FindFirstChild("HeldFish")
	t.ok(held, "the fish is over the head")
	sim:Advance(0.5)
	t.ok(sim:Time() - caughtAt >= FishingConfig.LeapTime)
	t.eq(anim.GetPhase(fisher), "Trophy")
	local char = fisher.Character
	local head, right, left = char.Head, char.RightHand, char.LeftHand
	local headTop, rightY, leftY, fishBottom = seen(sim, watcher, function()
		local box, size = held:GetBoundingBox()
		return head.Position.Y + head.Size.Y / 2,
			right.Position.Y + right.Size.Y / 2,
			left.Position.Y + left.Size.Y / 2,
			box.Position.Y - size.Y / 2
	end)
	t.ok(rightY > headTop and leftY > headTop, `both hands above the head ({rightY}, {leftY} > {headTop})`)
	t.ok(math.abs(fishBottom - rightY) < 0.8 and math.abs(fishBottom - leftY) < 0.8, "hands right under the fish")
	t.ok(rightY < fishBottom + 0.5, "… not through it")

	sim:Advance(FishingConfig.HoldFishTime.Common)
	t.eq(char:FindFirstChild("HeldFish"), nil, "the fish is gone")
	sim:Advance(0.6)
	local after = seen(sim, watcher, function()
		return right.Position.Y + right.Size.Y / 2
	end)
	t.ok(after < head.Position.Y, "arms down again")

	-- the hold sway lingers, then everything is released: Animator pose, no per-frame work
	sim:Advance(Poses.Timing.Linger + Poses.Timing.FadeOut + 0.5)
	t.eq(anim.IsAnimating(fisher), false)
	t.eq(preSimulationCount(sim), 0, "no PreSimulation connection left on any client")
	seen(sim, watcher, function()
		for _, d in char:GetDescendants() do
			if d:IsA("Motor6D") then
				t.near(d.Transform, CFrame.identity, 1e-6, `{d.Name} back to the Animator pose`)
			end
		end
	end)
	sim:AssertNoErrors({ warnings = true })
end

tests["lost: the fisher slumps and hangs the head, then straightens up"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local anim = controller(sim, watcher, "FisherAnimController")
	sim:FireServer(fisher, "FishingCast")
	sim:Advance(1.2)
	sim:FireServer(fisher, "FishingHook") -- too early: the fish is scared away
	t.eq(fisher:GetAttribute("FishingState"), "Idle")
	sim:Advance(0.35)
	t.eq(anim.GetPhase(fisher), "Lost")
	local neck = joint(fisher, "Neck")
	local slump = seen(sim, watcher, function()
		return neck.Transform
	end)
	local pitch = math.deg(math.asin(-slump.LookVector.Y))
	t.ok(pitch > 12, `the head hangs down ({pitch}°)`)
	sim:Advance(Poses.Timing.Lost.Hold + Poses.Timing.Lost.Recover)
	t.eq(anim.GetPhase(fisher), "Hold", "straightened up, the rod in hand")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Moving, LOD, rebuild, rig kinds
--------------------------------------------------------------------------------

tests["walking: torso and head go back to the normal animation, the arms stay posed"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	sim:FireServer(fisher, "FishingCast")
	sim:Advance(1.6)
	local neck, waist, shoulder = joint(fisher, "Neck"), joint(fisher, "Waist"), joint(fisher, "RightShoulder")
	local function read(): (any, any, any)
		return seen(sim, watcher, function()
			return neck.Transform, waist.Transform, shoulder.Transform
		end)
	end
	local n0 = read()
	t.ok(angle(n0, CFrame.identity) > 3, "the head looks at the bobber while standing")
	local root = fisher.Character.HumanoidRootPart
	sim:Run(function()
		fisher.Character.Humanoid:MoveTo(root.Position + root.CFrame.RightVector * 8)
	end, fisher)
	sim:Advance(0.3)
	local n, w, s = read()
	t.ok(angle(n, CFrame.identity) < 1.5, `neck back to the Animator while walking ({angle(n, CFrame.identity)}°)`)
	t.ok(angle(w, CFrame.identity) < 1.5, "waist too")
	t.ok(angle(s, CFrame.identity) > 30, "the arm with the rod stays posed")
	sim:AssertNoErrors({ warnings = true })
end

tests["LOD: a fisher farther than 150 studs is left alone; a fisher coming close is animated"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	ready(sim, fisher)
	local spot = baseOf(sim, fisher).FishingSpot.Position
	sim:Teleport(watcher, spot + Vector3.new(300, 3, 0))
	local anim = controller(sim, watcher, "FisherAnimController")
	sim:FireServer(fisher, "FishingCast")
	sim:Advance(1.5)
	t.eq(anim.IsAnimating(fisher), false, "too far: not animated")
	t.eq(preSimulationCount(sim, watcher), 0, "no per-frame work on the far watcher")
	local shoulder = joint(fisher, "RightShoulder")
	t.near(
		seen(sim, watcher, function()
			return shoulder.Transform
		end),
		CFrame.identity,
		1e-6,
		"the far fisher keeps the Animator pose"
	)
	standBeside(sim, watcher, fisher)
	sim:Advance(1)
	t.eq(anim.IsAnimating(fisher), true, "came close: animated (polled)")
	t.ok(angle(
		seen(sim, watcher, function()
			return shoulder.Transform
		end),
		pose("Wait", "RShoulder")
	) < 6, "in the Wait pose")
	sim:AssertNoErrors({ warnings = true })
end

tests["rebuild: joints replaced mid-session (appearance loaded) are found again"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	sim:FireServer(fisher, "FishingCast")
	sim:Advance(1.5)
	local old = joint(fisher, "RightShoulder")
	local replacement = sim:Create("Motor6D", {
		Name = "RightShoulder",
		Part0 = old.Part0,
		Part1 = old.Part1,
		C0 = old.C0,
		C1 = old.C1,
		Transform = CFrame.identity,
	})
	old:Destroy()
	replacement.Parent = fisher.Character.RightUpperArm
	sim:Advance(1)
	t.ok(angle(
		seen(sim, watcher, function()
			return replacement.Transform
		end),
		pose("Wait", "RShoulder")
	) < 6, "the new joint is posed")
	sim:AssertNoErrors({ warnings = true })
end

tests["R6 and AnimationConstraint rigs are posed the same way; the AJU frames stay untouched"] = function(t)
	local sim = boot(t)
	local old = addPlayer(sim, 1, "R6")
	local aju = addPlayer(sim, 2, "R15", "AnimationConstraint")
	local watcher = addPlayer(sim, 3)
	local oldRod = ready(sim, old)
	local ajuRod = ready(sim, aju)
	standBeside(sim, watcher, old)
	sim:FireServer(old, "FishingCast")
	sim:FireServer(aju, "FishingCast")
	sim:Advance(1.6)
	-- R6: the elbow and wrist fold into the shoulder; the rod ends up ≈ as high as on R15
	local tip6 = seen(sim, watcher, function()
		return oldRod.Handle.TipAttachment.WorldPosition
	end)
	heldOut(t, old, tip6, "R6")
	local rootJoint = joint(old, "RootJoint")
	t.ok(seen(sim, watcher, function()
		return rootJoint.Transform.Position.Magnitude
	end) < 1e-6, "R6: no hip drop (the legs cannot bend)")
	-- AJU: Transform on the AnimationConstraint, the rig attachments never written
	local shoulder = joint(aju, "RightShoulder")
	t.ok(shoulder:IsA("AnimationConstraint"))
	local frame0 = shoulder.Attachment0.CFrame
	sim:Teleport(watcher, baseOf(sim, aju).FishingSpot.Position + Vector3.new(6, 3, 6))
	sim:Advance(0.6)
	local transform, attachment = seen(sim, watcher, function()
		return shoulder.Transform, shoulder.Attachment0.CFrame
	end)
	t.ok(angle(transform, pose("Wait", "RShoulder")) < 6, "AJU: posed through Transform")
	t.near(attachment, frame0, 1e-9, "AJU: RigAttachment untouched")
	local ajuTip = seen(sim, watcher, function()
		return ajuRod.Handle.TipAttachment.WorldPosition
	end)
	heldOut(t, aju, ajuTip, "AJU")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- v3 [anim-b]: big cartoon beats readable on a phone
--------------------------------------------------------------------------------

-- Samples fn() on the watcher's client every frame for `seconds`.
local function sample(sim: any, who: any, seconds: number, fn: () -> ()): ()
	local stop = sim:Time() + seconds
	while sim:Time() < stop do
		sim:Step(FRAME)
		seen(sim, who, fn)
	end
end

-- Yaw of a joint's Transform, degrees (+ = left).
local function yawOf(cf: any): number
	local look = cf.LookVector
	return math.deg(math.atan2(-look.X, -look.Z))
end

tests["catch (Legendary): hop at the yank, squat and jump with a spin on landing; the trophy show-off pumps the arms with a fish kick and sweeps the body"] = function(
	t
)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "SharkPup")
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local fx = controller(sim, watcher, "FishingFxController")
	local anim = controller(sim, watcher, "FisherAnimController")
	local kicks, landedAt = {}, nil
	sim:Run(function()
		local real = fx.KickHeldFish
		fx.KickHeldFish = function(player: any, power: number?): boolean
			if player == fisher then
				table.insert(kicks, sim:Time())
			end
			return real(player, power)
		end
		anim.PhaseChanged:Connect(function(player: any, phase: string)
			if player == fisher and phase == "Landed" then
				landedAt = sim:Time()
			end
		end)
	end, watcher)

	sim:FireServer(fisher, "FishingCast")
	local mg, start = hookFish(t, sim, fisher)
	t.eq(playMinigame(sim, fisher, mg, start), "Caught")
	local root, waist = joint(fisher, "Root"), joint(fisher, "Waist")
	local high, low, turn = -math.huge, math.huge, 0
	sample(sim, watcher, 0.5, function()
		high = math.max(high, root.Transform.Position.Y)
	end)
	t.ok(high > 0.3, `a hop at the yank (Epic+): the pelvis up {high} studs`)
	high = -math.huge
	sim:WaitFor(function()
		return landedAt ~= nil
	end, FishingConfig.LeapTime + 1, FRAME)
	t.ok(landedAt, "the fish landed over the head")
	sample(sim, watcher, Poses.Timing.Caught.Bounce + 0.3, function()
		local p = root.Transform.Position
		high, low = math.max(high, p.Y), math.min(low, p.Y)
		turn = math.max(turn, math.abs(yawOf(root.Transform)))
	end)
	t.ok(low < -0.15, `squats under the fish's weight ({low})`)
	t.ok(high > 0.4, `… and jumps for joy ({high})`)
	t.ok(turn > 120, `Legendary: a spin on the spot with the fish ({turn}°)`)

	-- the show-off loop: every ShowEvery s a kick of the fish (FishLife) with the arm pump and a sweep
	local trophy = Poses.Timing.Trophy
	local sweep = 0
	sim:WaitFor(function()
		return #kicks >= 1
	end, trophy.FirstShow + 1, FRAME)
	t.eq(#kicks, 1, "the first show-off after the landing beats")
	t.near(kicks[1] - landedAt, trophy.FirstShow, 0.15, "… Trophy.FirstShow after the landing")
	sample(sim, watcher, trophy.ShowSweep, function()
		sweep = math.max(sweep, math.abs(yawOf(waist.Transform)))
	end)
	t.ok(sweep > 8, `the body sweeps the fish left and right ({sweep}°)`)
	sim:WaitFor(function()
		return #kicks >= 2
	end, trophy.ShowEvery + 0.5, FRAME)
	t.ok(#kicks >= 2 and math.abs(kicks[2] - kicks[1] - trophy.ShowEvery) < 0.1, "again every Trophy.ShowEvery s")
	t.eq(anim.GetPhase(fisher), "Trophy")
	sim:AssertNoErrors({ warnings = true })
end

tests["own replay (TrophyReplayed after the card): a real celebration — squat, jumps, pumps, a sweep"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	forceFish(sim, "Crucian")
	ready(sim, fisher)
	local fx = controller(sim, fisher, "FishingFxController")
	sim:FireServer(fisher, "FishingCast")
	local mg, start = hookFish(t, sim, fisher)
	t.eq(playMinigame(sim, fisher, mg, start), "Caught")
	sim:Advance(FishingConfig.LeapTime + Poses.Timing.Caught.Bounce + 0.4)
	t.ok(fisher.Character:FindFirstChild("HeldFish"), "the fish over the head")
	local root, waist = joint(fisher, "Root"), joint(fisher, "Waist")
	t.eq(
		seen(sim, fisher, function()
			return fx.ReplayOwnTrophy()
		end),
		true,
		"the own trophy replays"
	)
	local high, low, sweep = -math.huge, math.huge, 0
	sample(sim, fisher, Poses.Timing.Celebrate + 0.1, function()
		local p = root.Transform.Position
		high, low = math.max(high, p.Y), math.min(low, p.Y)
		sweep = math.max(sweep, math.abs(yawOf(waist.Transform)))
	end)
	t.ok(low < -0.15 and high > 0.4, `squats and jumps ({low} .. {high})`)
	t.ok(sweep > 8, `sweeps the trophy left and right ({sweep}°)`)
	sim:AssertNoErrors({ warnings = true })
end

tests["R6: hops, bounces and the bite startle never move the RootJoint (the legs cannot bend)"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1, "R6")
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "SharkPup")
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local rootJoint = joint(fisher, "RootJoint")
	local worst = 0
	local function track()
		worst = math.max(worst, rootJoint.Transform.Position.Magnitude)
	end
	sim:FireServer(fisher, "FishingCast")
	local bite = nextState(sim, fisher, #stateEvents(sim, fisher), 10)
	t.eq(bite, "Bite")
	sample(sim, watcher, 0.3, track) -- the startle
	local count = #stateEvents(sim, fisher)
	sim:FireServer(fisher, "FishingHook")
	local name, mg, start = nextState(sim, fisher, count, 1)
	t.eq(name, "Minigame")
	t.eq(playMinigame(sim, fisher, mg, start :: number), "Caught")
	sample(sim, watcher, FishingConfig.LeapTime + Poses.Timing.Caught.Bounce + 1, track)
	t.ok(worst < 1e-6, `R6 RootJoint never shifted ({worst})`)
	sim:AssertNoErrors({ warnings = true })
end

tests["far fishers: their phase layers and pulses never pile up (nobody prunes them per frame)"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	ready(sim, fisher)
	sim:Teleport(watcher, baseOf(sim, fisher).FishingSpot.Position + Vector3.new(300, 3, 0))
	local anim = controller(sim, watcher, "FisherAnimController")
	for _ = 1, 4 do
		sim:FireServer(fisher, "FishingCast")
		sim:Advance(FishingConfig.CastWindUp + FishingConfig.CastFlightTime + 0.6)
		sim:FireServer(fisher, "FishingHook") -- too early: lost
		sim:Advance(Poses.Timing.Lost.Hold + Poses.Timing.Lost.Recover + FishingConfig.CastCooldown + 0.3)
	end
	local debug = seen(sim, watcher, function()
		return anim.GetDebug(fisher)
	end)
	t.eq(anim.IsAnimating(fisher), false, "too far: not animated")
	t.ok(debug.layers <= 1, `one phase layer at most ({debug.layers})`)
	t.eq(debug.pulses, 0, "no pulses queued")
	sim:AssertNoErrors({ warnings = true })
end

tests["waiting: every few seconds a fidget (shift, rod twitch, glance, foot tap) — the body never stands still"] = function(
	t
)
	local sim = boot(t)
	local config = sim:Require(sim:Find("ReplicatedStorage.Shared.Config.FishingConfig"))
	config.BiteDelay.Min, config.BiteDelay.Max = 12, 12
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local anim = controller(sim, watcher, "FisherAnimController")
	sim:FireServer(fisher, "FishingCast")
	sim:Advance(FishingConfig.CastWindUp + FishingConfig.CastFlightTime + Poses.Timing.Settle + 0.2)
	t.eq(anim.GetPhase(fisher), "Wait")
	local hip, root, neck = joint(fisher, "RightHip"), joint(fisher, "Root"), joint(fisher, "Neck")
	local legs, shift, look = 0, 0, 0
	local neck0 = seen(sim, watcher, function()
		return neck.Transform
	end)
	sample(sim, watcher, 2 * Poses.Timing.Fidget.Max + 0.5, function()
		legs = math.max(legs, angle(hip.Transform, CFrame.identity))
		shift = math.max(shift, math.abs(root.Transform.Position.X))
		look = math.max(look, angle(neck.Transform, neck0))
	end)
	local debug = seen(sim, watcher, function()
		return anim.GetDebug(fisher)
	end)
	t.ok(debug.fidgets >= 2, `fidgets while waiting ({debug.fidgets})`)
	t.ok(legs > 8 or shift > 0.08 or look > 15, `a visible fidget (hip {legs}°, shift {shift}, neck {look}°)`)
	t.eq(fisher:GetAttribute("FishingState"), "Waiting", "(still waiting for the bite)")
	sim:AssertNoErrors({ warnings = true })
end

tests["rod: a steady bend is not rewritten every frame; the fight whips it sideways and bends it further for Epic+"] = function(
	t
)
	local sim = boot(t)
	local config = sim:Require(sim:Find("ReplicatedStorage.Shared.Config.FishingConfig"))
	config.BiteDelay.Min, config.BiteDelay.Max = 4, 4
	local fisher = addPlayer(sim, 1)
	local watcher = addPlayer(sim, 2)
	forceFish(sim, "Swordfish") -- Epic
	local rod = ready(sim, fisher)
	standBeside(sim, watcher, fisher)
	local anim = controller(sim, fisher, "FisherAnimController")
	local weld = nil
	for _, d in rod:GetDescendants() do
		if d:IsA("Weld") and d.Name == "Weld" and (weld == nil or d.C0.Position.X > weld.C0.Position.X) then
			weld = d
		end
	end
	sim:FireServer(fisher, "FishingCast")
	sim:Advance(FishingConfig.CastWindUp + FishingConfig.CastFlightTime + Poses.Timing.Settle + 0.8)
	t.eq(anim.GetPhase(fisher), "Wait")
	-- (on the watcher's client: no nibbles of the own bobber there)
	local writes, last = 0, seen(sim, watcher, function()
		return weld.C0
	end)
	for _ = 1, 45 do
		sim:Step(FRAME)
		local now = seen(sim, watcher, function()
			return weld.C0
		end)
		if now ~= last then
			writes += 1
		end
		last = now
	end
	t.ok(writes < 15, `the waiting rod's welds are not rewritten every frame ({writes} of 45)`)

	local mg = hookFish(t, sim, fisher)
	t.eq(mg.Rarity, "Epic")
	sim:Advance(0.6)
	t.eq(anim.GetPhase(fisher), "Reel")
	local most, sideways = 0, {}
	sample(sim, fisher, 1, function()
		most = math.max(most, anim.GetRodBend(fisher))
		table.insert(sideways, weld.C0.Position)
	end)
	t.ok(most > math.rad(36), `an Epic fish bends the rod past the usual limit ({math.deg(most)}°)`)
	local lo, hi = math.huge, -math.huge
	for _, p in sideways do
		lo, hi = math.min(lo, p.Z), math.max(hi, p.Z)
	end
	t.ok(hi - lo > 0.15, `the rod whips sideways with the fish ({hi - lo} studs at the tip segment)`)
	sim:AssertNoErrors({ warnings = true })
end

tests["own taps: a predicted hit pulls the rod at once (the server's Zone adds no second pull); a miss fumbles"] = function(
	t
)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	forceFish(sim, "SharkPup") -- two hits
	ready(sim, fisher)
	local anim = controller(sim, fisher, "FisherAnimController")
	sim:FireServer(fisher, "FishingCast")
	local mg, start = hookFish(t, sim, fisher)
	sim:Advance(0.6)
	t.eq(anim.GetPhase(fisher), "Reel")
	local function pulses(): number
		return seen(sim, fisher, function()
			return anim.GetDebug(fisher).pulses
		end)
	end
	local shoulder = joint(fisher, "RightShoulder")
	local before = seen(sim, fisher, function()
		return shoulder.Transform
	end)
	local n0 = pulses()
	sim:Run(function()
		anim.Cue("tapMiss")
	end, fisher)
	t.eq(pulses(), n0 + 1, "a miss: the fumble pulse")
	sim:Advance(0.3)

	-- a hit at the needle: the body pulls at the tap (predicted), the server's Zone adds nothing
	local fr = rules(sim)
	local moment = math.max(FishingConfig.TapInterval + 0.02, sim:Time() - start + 0.02)
	while math.abs(fr.Needle(mg.U0, mg.Speed, moment) - mg.ZoneCenter) > mg.ZoneWidth * 0.3 do
		moment += 0.005
	end
	sim:WaitFor(function()
		return sim:Time() >= start + moment - 1e-9
	end, 10, FRAME)
	local n1 = pulses()
	sim:Run(function()
		anim.Cue("tapHit")
	end, fisher)
	t.eq(pulses(), n1 + 1, "the predicted hit: a rod pull right away")
	local count = #stateEvents(sim, fisher)
	sim:FireServer(fisher, "FishingTap", moment)
	local name = nextState(sim, fisher, count, 0.2)
	t.eq(name, "Zone", "the server counts the hit")
	sim:Step(FRAME)
	t.eq(pulses(), n1 + 1, "… and its Zone does not pull again")
	sim:Advance(0.05)
	local pulled = seen(sim, fisher, function()
		return shoulder.Transform
	end)
	t.ok(angle(pulled, before) > 5, "the rod arm moved")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Own client: predicted cues
--------------------------------------------------------------------------------

tests["own client: castPress winds up at once; without an answer the rod goes down again"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	ready(sim, fisher)
	sim:Advance(1)
	local anim = controller(sim, fisher, "FisherAnimController")
	sim:Run(function()
		anim.Cue("castPress")
	end, fisher)
	sim:Advance(0.25)
	t.eq(anim.GetPhase(fisher), "Cast", "winding up before the server answers")
	local shoulder = joint(fisher, "RightShoulder")
	t.ok(angle(
		seen(sim, fisher, function()
			return shoulder.Transform
		end),
		pose("WindUp", "RShoulder")
	) < 8, "cocked")
	sim:Advance(Poses.Timing.CastTimeout + 0.5)
	t.eq(anim.GetPhase(fisher), "Hold", "no answer: the rod goes down again")
	sim:AssertNoErrors({ warnings = true })
end

return tests
