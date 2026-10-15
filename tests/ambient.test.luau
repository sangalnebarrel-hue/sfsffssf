--[[
	The living world (AmbientController + AmbientEngine / AmbientWind / AmbientWorld /
	AmbientWater / AmbientCritters), run in RbxSim against the built Place1.rbxl with the real
	client: the test puts the client's camera where a player would look from and watches what that
	client sees (client-local CFrames, transparency, GlobalWind).

	What is checked:
	  • one RunService.PreRender connection for the whole living world; none (and the glints off)
	    when the camera is far from everything; back when it returns; nothing per character;
	  • culling: items behind the camera are not touched, items in view are; MID items update
	    ≈ 20 times a second and FAR items ≈ 7.5 (staggered: a share of the tier per frame);
	  • the per-frame budget (parts moved + properties written) holds on a phone;
	  • the builder's marks are honoured: Spin (about the pivot's LookVector, KeepUpright gondolas
	    stay level), Bob (up and down about the pivot), Sway (about the pivot's axis, the hang point
	    stays, the angle within Sway° × the strongest gust), Pulse (foam transparency around its own
	    value), Drift (clouds circle the island centre at their height);
	  • wind: Workspace.GlobalWind follows the gust, smoke / mist / petals follow the wind;
	  • water life: glints on the lagoon in view, a fish jumps on lagoon water ahead (splash rings)
	    and never while the own fish bites; foam rings round boats near the camera; waterfall flow
	    beams; schools, gulls (and the pier gull's swoop), butterflies, dragonflies exist and move;
	  • the client's own parts: no collisions / queries / touches / shadows, Material set (no
	    accidental LEGO studs), within MapConfig.PartBudget.RuntimeReserve.AmbientLife.

	Run: lune run tools/run_tests.luau ambient
]]

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local PLACE = "Place1.rbxl"

local function boot(t: any, device: string?): (any, any, any)
	local sim = t.sim({ place = PLACE })
	sim:StartServer()
	sim:Advance(0.5)
	local player = sim:AddPlayer({ UserId = 1, Name = "Viewer", device = device or "phone" })
	sim:Advance(1)
	local ambient = sim:Require(sim:Find("Controllers.AmbientController", player.PlayerScripts), player)
	sim:WaitFor(function()
		return ambient.Ready
	end, 10)
	t.ok(ambient.Ready, "the living world is collected")
	return sim, player, ambient
end

local function baseOf(sim: any, player: any): any
	return sim.workspace.Bases:FindFirstChild(`Base_{player:GetAttribute("BaseIndex")}`)
end

-- The fishing spot's follow camera (12.5 studs behind the focus, 18° down), as in the game.
local function spotCamera(sim: any, player: any): any
	local base = baseOf(sim, player)
	local spot = base.FishingSpot.Position
	local look = base:GetPivot().LookVector
	local focus = spot + Vector3.new(0, 4.8, 0)
	local eye = focus - look * 12.5 * math.cos(math.rad(18)) + Vector3.new(0, 12.5 * math.sin(math.rad(18)), 0)
	return CFrame.lookAt(eye, focus)
end

local function setCamera(sim: any, cf: any)
	sim.workspace.CurrentCamera.CFrame = cf
end

local function preRenderCount(sim: any, player: any): number
	local ctx = sim:ContextName(player)
	return sim:CountConnections(function(conn: any)
		return conn.ctx.name == ctx and string.find(conn.signal:describe(), "PreRender", 1, true) ~= nil
	end)
end

-- What the viewer's client sees.
local function seen(sim: any, player: any, fn: () -> any): any
	return sim:Run(fn, player)
end

local function itemsOf(ambient: any, kind: string): { any }
	local list = {}
	for _, item in ambient.Engine.items do
		if item.kind == kind then
			table.insert(list, item)
		end
	end
	return list
end

-- The tier (1 near, 2 mid, 3 far, 0 none) an item is in after the last refresh pass.
local function tierOf(ambient: any, item: any): number
	for tier, list in ambient.Engine.lists do
		for _, other in list do
			if other == item then
				return tier
			end
		end
	end
	return 0
end

local tests = {}

tests["one PreRender connection for the whole world; asleep (glints off) far from everything, awake again"] = function(
	t
)
	local sim, player, ambient = boot(t)
	setCamera(sim, spotCamera(sim, player))
	sim:Advance(1)
	t.eq(preRenderCount(sim, player), 1, "one connection")
	t.ok(ambient.Engine.Stats.connected, "running at the fishing spot")
	t.ok(ambient.Water.glints >= 1, `glints on the lagoon in view: {ambient.Water.glints}`)

	setCamera(sim, CFrame.lookAt(Vector3.new(0, 40, 6000), Vector3.new(0, 40, 7000)))
	sim:Advance(1)
	t.eq(preRenderCount(sim, player), 0, "nothing per frame when nothing is near")
	t.ok(not ambient.Engine.Stats.connected, "asleep")
	t.eq(ambient.Water.glints, 0, "glints off while asleep")
	local polls = ambient.Engine.Stats.idlePolls
	sim:Advance(2)
	t.eq(preRenderCount(sim, player), 0, "still asleep")
	t.ok(ambient.Engine.Stats.idlePolls > polls, "checked by a timer")

	setCamera(sim, spotCamera(sim, player))
	sim:Advance(0.7)
	t.eq(preRenderCount(sim, player), 1, "awake again")
	sim:AssertNoErrors({ warnings = true })
end

tests["no connections per character: the same count after a respawn"] = function(t)
	local sim, player, ambient = boot(t)
	setCamera(sim, spotCamera(sim, player))
	sim:Advance(1)
	local before = sim:CountConnections(player)
	sim:KillCharacter(player)
	sim:WaitFor(function()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		return humanoid and humanoid.Health > 0
	end, 15)
	sim:Advance(1)
	t.eq(sim:CountConnections(player), before, "connections unchanged")
	t.ok(ambient.Engine.Stats.connected, "still running")
	sim:AssertNoErrors()
end

tests["culling: in view moves, behind the camera does not; MID ≈ 20 Hz, FAR ≈ 7.5 Hz; the budget holds"] = function(
	t
)
	local sim, player, ambient = boot(t)
	local engine = ambient.Engine
	local Engine = sim:Require(sim:Find("Controllers.AmbientEngine", player.PlayerScripts), player)
	setCamera(sim, spotCamera(sim, player))
	sim:Advance(1)

	-- a swaying detail in range behind the camera, and one in view
	local behind, front = nil, nil
	for _, item in itemsOf(ambient, "Sway") do
		local d = (item.pos - engine.camPos).Magnitude
		if d < 200 and tierOf(ambient, item) > 0 then
			if not Engine.Visible(engine, item.pos, item.radius) then
				behind = behind or item
			else
				front = front or item
			end
		end
	end
	t.ok(behind and front, "a swaying detail behind and one in view")
	local function poseOf(item: any): any
		return seen(sim, player, function()
			return item.data.parts[1].CFrame
		end)
	end
	local b0, f0 = poseOf(behind), poseOf(front)
	sim:Advance(0.6)
	local b1, f1 = poseOf(behind), poseOf(front)
	t.ok(b0 == b1, "behind the camera: untouched")
	t.ok(f0 ~= f1, "in view: swinging")

	-- update rates per tier (counting write calls over 2 s)
	local counts: { [any]: number } = {}
	local picked: { [number]: any } = {}
	for tier = 1, 3 do
		for _, item in engine.lists[tier] do
			if not item.interval and not picked[tier] and Engine.Visible(engine, item.pos, item.radius) then
				picked[tier] = item
				counts[item] = 0
				local write = item.write
				item.write = function(self: any, now: number, e: any)
					counts[self] += 1
					write(self, now, e)
				end
			end
		end
	end
	local peak = 0
	for _ = 1, 120 do
		sim:Step()
		peak = math.max(peak, engine.Stats.moved + engine.Stats.writes)
	end
	t.ok(peak <= engine.Budget, `per-frame work {peak} within the phone budget {engine.Budget}`)
	t.eq(engine.Budget, 220, "phone budget")
	if picked[1] then
		t.ok(counts[picked[1]] >= 110, `NEAR: every frame ({counts[picked[1]]} of 120)`)
	end
	t.ok(picked[2] and picked[3], "MID and FAR items in view")
	local mid, far = counts[picked[2]], counts[picked[3]]
	t.ok(mid >= 30 and mid <= 44, `MID ≈ 20 Hz: {mid} updates in 2 s`)
	t.ok(far >= 10 and far <= 18, `FAR ≈ 7.5 Hz: {far} updates in 2 s`)
	sim:AssertNoErrors()
end

tests["marks: Spin about the pivot (gondolas level), Bob about the pivot, Sway about the hang point, Pulse, Drift"] = function(
	t
)
	local sim, player, ambient = boot(t, "desktop")
	local engine = ambient.Engine
	t.eq(engine.Budget, 400, "desktop budget")
	local function look(eye: any, target: any)
		setCamera(sim, CFrame.lookAt(eye, target))
		sim:Advance(0.6) -- (a refresh pass puts the items in their tiers)
	end
	local function clientCFrame(part: any): any
		return seen(sim, player, function()
			return part.CFrame
		end)
	end

	-- Spin: next to the fun fair; the Ferris wheel turns about its pivot's LookVector
	look(Vector3.new(-30, 10, -15), Vector3.new(-85, 18, -70))
	local wheel = nil
	for _, item in itemsOf(ambient, "Spin") do
		if item.anchor.Name == "Wheel" then
			wheel = item
		end
	end
	t.ok(wheel, "the Ferris wheel spins")
	local d = wheel.data
	local spin = wheel.anchor:GetAttribute("Spin")
	local rim, reach = d.parts[1], 0 -- (the part farthest from the axle)
	for _, part in d.parts do
		local o = d.base:PointToObjectSpace(part.Position)
		if Vector3.new(o.X, o.Y, 0).Magnitude > reach then
			rim, reach = part, Vector3.new(o.X, o.Y, 0).Magnitude
		end
	end
	local p0, g0 = clientCFrame(rim), clientCFrame(d.uprights[1].parts[1])
	sim:Advance(1)
	local p1, g1 = clientCFrame(rim), clientCFrame(d.uprights[1].parts[1])
	local o0, o1 = d.base:PointToObjectSpace(p0.Position), d.base:PointToObjectSpace(p1.Position)
	t.near(o0.Z, o1.Z, 1e-3, "stays in its plane (axis = LookVector)")
	t.near(Vector3.new(o0.X, o0.Y, 0).Magnitude, Vector3.new(o1.X, o1.Y, 0).Magnitude, 1e-3, "same radius")
	local turned = math.deg(math.atan2(o1.Y, o1.X) - math.atan2(o0.Y, o0.X)) % 360
	local expected = spin % 360
	local err = math.min(math.abs(turned - expected), 360 - math.abs(turned - expected))
	t.ok(err < math.abs(spin) * 0.25 + 0.5, `turned {turned}° in 1 s (Spin {spin} °/s)`)
	t.ok(g0.Position ~= g1.Position, "the gondola rides the wheel")
	t.ok(g0.UpVector:Dot(g1.UpVector) > 0.9999, "… and stays level (KeepUpright)")

	-- Bob: the base's boat rises and falls about its pivot, never sideways
	local base = baseOf(sim, player)
	local boatModel = base:FindFirstChild("Boat")
	local bob = nil
	for _, item in itemsOf(ambient, "Bob") do
		if item.anchor == boatModel then
			bob = item
		end
	end
	t.ok(bob, "the base's boat bobs")
	local bp = bob.data.base.Position
	look(bp + Vector3.new(8, 10, 8), bp)
	local lowest, highest = math.huge, -math.huge
	for _ = 1, 40 do
		sim:Advance(0.1)
		local pivotNow = clientCFrame(bob.data.parts[1]) * bob.data.offsets[1]:Inverse()
		local rel = bob.data.base:PointToObjectSpace(pivotNow.Position)
		t.ok(math.abs(rel.X) < 1e-3 and math.abs(rel.Z) < 1e-3, "the pivot only moves vertically")
		lowest, highest = math.min(lowest, rel.Y), math.max(highest, rel.Y)
	end
	local amp = bob.data.amplitude
	t.ok(highest <= amp + 1e-3 and lowest >= -amp - 1e-3, "within its Bob amplitude")
	t.ok(highest - lowest > amp, `rises and falls ({lowest} … {highest}, Bob {amp})`)

	-- Sway: on the fishing platform (windsock, chime, roof flag, pennants): the hang point stays,
	-- the turn is about the pivot's axis only, within Sway° × the strongest gust (1.4)
	local pivot = base:GetPivot()
	look(pivot * Vector3.new(-4, 9, -86), pivot * Vector3.new(2, 9, -48))
	local checked = 0
	for _, item in itemsOf(ambient, "Sway") do
		local s = item.data
		local Engine = sim:Require(sim:Find("Controllers.AmbientEngine", player.PlayerScripts), player)
		if checked < 3 and tierOf(ambient, item) > 0 and Engine.Visible(engine, item.pos, item.radius) then
			checked += 1
			local ampDeg = math.deg(s.amp)
			local maxAngle = 0
			for _ = 1, 16 do
				sim:Advance(0.17)
				local turn = s.pivot:Inverse() * clientCFrame(s.parts[1]) * s.offsets[1]:Inverse()
				t.near(turn.Position, Vector3.new(0, 0, 0), 1e-3, "the hang point stays")
				local r = { turn:ToEulerAnglesXYZ() }
				for axis = 1, 3 do
					if axis ~= s.axis then
						t.ok(math.abs(r[axis]) < 1e-4, `turns only about its {s.axis} axis ({item.anchor.Name})`)
					end
				end
				maxAngle = math.max(maxAngle, math.abs(math.deg(r[s.axis])))
			end
			t.ok(maxAngle > 0.15 * ampDeg, `{item.anchor.Name} swings ({maxAngle}° of {ampDeg}°)`)
			t.ok(maxAngle <= ampDeg * 1.4 + 1e-3, `{item.anchor.Name} within Sway × the strongest gust`)
		end
	end
	t.eq(checked, 3, "three swaying details in view of the platform")

	-- Drift: a cloud circles the island centre at its height
	local cloud = itemsOf(ambient, "Drift")[1]
	t.ok(cloud, "drifting clouds")
	look(Vector3.new(0, 60, 0), cloud.pos)
	local c0 = clientCFrame(cloud.data.parts[1]).Position
	sim:Advance(4)
	local c1 = clientCFrame(cloud.data.parts[1]).Position
	t.near(c0.Y, c1.Y, 1e-3, "same height")
	t.near(Vector3.new(c0.X, 0, c0.Z).Magnitude, Vector3.new(c1.X, 0, c1.Z).Magnitude, 0.05, "same radius")
	local moved = (c1 - c0).Magnitude
	local speed = cloud.anchor:GetAttribute("Drift")
	t.ok(moved > speed * 4 * 0.6 and moved < speed * 4 * 1.6, `moved {moved} studs in 4 s (Drift {speed})`)

	-- Pulse: the shore foam breathes around its own transparency
	local pulse = itemsOf(ambient, "Pulse")[1]
	t.ok(pulse, "the shore foam pulses")
	look(pulse.pos + Vector3.new(15, 20, 15), pulse.pos)
	local foamPart = pulse.data.parts[1]
	local baseT, pulseAmp = pulse.data.base[1], pulse.data.amp
	local lo, hi = math.huge, -math.huge
	for _ = 1, 20 do
		sim:Advance(0.2)
		local v = seen(sim, player, function()
			return foamPart.Transparency
		end)
		lo, hi = math.min(lo, v), math.max(hi, v)
	end
	t.ok(hi - lo > 0.1, `breathes ({lo} … {hi})`)
	t.ok(lo >= baseT - pulseAmp - 1e-3 and hi <= baseT + pulseAmp + 1e-3, "around its own value")
	sim:AssertNoErrors()
end

tests["wind: GlobalWind follows the gust; smoke, mist and petals follow the wind"] = function(t)
	local sim, player, ambient = boot(t)
	setCamera(sim, spotCamera(sim, player))
	local winds = {}
	for k = 1, 6 do
		sim:Advance(1.3)
		winds[k] = seen(sim, player, function()
			return sim.workspace.GlobalWind
		end)
	end
	local lo, hi = math.huge, 0
	for _, w in winds do
		t.ok(w.Magnitude > 3 and w.Magnitude < 12, `a breeze ({w.Magnitude} studs/s)`)
		t.near(w.Y, 0, 1e-6, "horizontal")
		lo, hi = math.min(lo, w.Magnitude), math.max(hi, w.Magnitude)
	end
	t.ok(hi - lo > 0.2, "gusts")
	t.ok(ambient.Summary.windEmitters >= 20, `emitters that follow the wind: {ambient.Summary.windEmitters}`)
	local smoke = nil
	for _, d in sim.workspace.Map:GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Name == "Smoke" then
			smoke = d
			break
		end
	end
	t.ok(smoke, "chimney smoke")
	local follows, drag = seen(sim, player, function()
		return smoke.WindAffectsDrag, smoke.Drag
	end)
	t.ok(follows and drag > 0, "smoke drifts with the wind")
	sim:AssertNoErrors()
end

tests["water: a fish jumps ahead on the lagoon (not near bobbers, not while the own fish bites); foam, falls"] = function(
	t
)
	local sim, player, ambient = boot(t)
	setCamera(sim, spotCamera(sim, player))
	sim:Advance(1)
	local Water = sim:Require(sim:Find("Controllers.AmbientWater", player.PlayerScripts), player)
	local jumps = ambient.Water.jumps
	ambient.JumpSoon()
	sim:Advance(0.4)
	t.ok(ambient.Water.jumping, "jumping")
	t.eq(ambient.Water.jumps, jumps + 1)
	local at = ambient.Water.lastJump
	local cam = sim.workspace.CurrentCamera.CFrame
	local rel = at - cam.Position
	t.ok(rel.Magnitude >= 25 and rel.Magnitude <= 95, `ahead, {rel.Magnitude} studs away`)
	t.ok(
		Vector3.new(rel.X, 0, rel.Z).Unit:Dot(Vector3.new(cam.LookVector.X, 0, cam.LookVector.Z).Unit) > 0.8,
		"in view"
	)
	t.ok(Water.LagoonWater(at.X, at.Z, {}), "on lagoon water")
	-- the leaping fish is a real fish model (Assets.Fish) above the water mid-arc
	local fish = sim.workspace:FindFirstChild("Ambient (client)"):FindFirstChild("JumpFish")
	t.ok(fish and fish:IsA("Model"), "a fish model")
	local y = seen(sim, player, function()
		return fish.PrimaryPart.Position.Y
	end)
	t.ok(y > 0.5, `above the water mid-arc ({y})`)
	sim:Advance(1)
	t.ok(not ambient.Water.jumping, "back in the water")
	local hidden = seen(sim, player, function()
		return fish.PrimaryPart.Position.Y
	end)
	t.ok(hidden < -100, "parked far below until the next jump")

	-- never near a bobber, never while the own fish bites
	local target = at
	player:SetAttribute("BobberTarget", target)
	player:SetAttribute("FishingState", "Bite")
	jumps = ambient.Water.jumps
	ambient.JumpSoon()
	sim:Advance(1.5)
	t.eq(ambient.Water.jumps, jumps, "no jump while the own fish bites")
	player:SetAttribute("FishingState", "Waiting")
	local jumped = 0
	for _ = 1, 4 do
		local before = ambient.Water.jumps
		ambient.JumpSoon()
		sim:Advance(1.3)
		if ambient.Water.jumps > before then
			jumped += 1
			local spot = ambient.Water.lastJump
			local gap = (Vector3.new(spot.X, 0, spot.Z) - Vector3.new(target.X, 0, target.Z)).Magnitude
			t.ok(gap >= 15, `15+ studs from the bobber ({gap})`)
		end
	end
	t.ok(jumped >= 2, `jumps go on while waiting for a bite ({jumped} of 4)`)
	player:SetAttribute("FishingState", "Idle")

	-- foam rings round the boats near the camera, flow beams on the waterfall
	t.ok(ambient.Water.foamSpecs >= 30, `boats and buoys with a foam ring: {ambient.Water.foamSpecs}`)
	t.ok(ambient.Water.foam >= 1, `foam rings near the fishing spot: {ambient.Water.foam}`)
	t.ok(ambient.Water.waterfallBeams >= 10, `flow beams on the waterfall: {ambient.Water.waterfallBeams}`)
	sim:AssertNoErrors()
end

tests["critters: schools swim, gulls fly (the pier gull swoops low), butterflies and dragonflies near the camera"] = function(
	t
)
	local sim, player, ambient = boot(t)
	setCamera(sim, spotCamera(sim, player))
	sim:Advance(1)
	local critters = ambient.Critters
	t.eq(#critters.gulls, 8, "8 gulls")
	t.eq(#ambient.Water.schools, 6, "6 schools")
	t.eq(#critters.butterflies, 6, "6 butterflies")
	t.eq(#critters.dragonflies, 3, "3 dragonflies")

	-- the school in front of the pier is near and under water
	local base = baseOf(sim, player)
	local pierSchool = ambient.Water.schools[#ambient.Water.schools]
	local fish = pierSchool.data.fish[1].body
	local p0 = seen(sim, player, function()
		return fish.Position
	end)
	sim:Advance(1)
	local p1 = seen(sim, player, function()
		return fish.Position
	end)
	t.ok((p1 - p0).Magnitude > 1, "the school swims")
	t.ok(p1.Y < 0 and p1.Y > -4, `just under the surface ({p1.Y})`)
	t.ok((p1 - base.FishingSpot.Position).Magnitude < 90, "in front of the nearest pier")

	-- the pier gull dives past the pier tip and climbs again
	ambient.SwoopSoon()
	sim:Advance(0.6)
	t.ok(critters.swooping, "a swoop is planned")
	local dive = critters.swoopStart
	sim:WaitFor(function()
		return sim:Time() >= dive + 1.5
	end, 25)
	local gull = critters.gulls[7]
	local low = gull.pos
	local tipLocal = base:GetPivot():PointToObjectSpace(low)
	t.ok(low.Y < 16, `low over the water at the middle of the swoop ({low.Y})`)
	t.ok(math.abs(tipLocal.X) < 20 and tipLocal.Z < -60 and tipLocal.Z > -100, "next to the pier tip")
	sim:Advance(2)
	t.ok(gull.pos.Y > 22, "climbs back")

	-- butterflies flutter near the flower beds within reach of the camera
	local flowers = ambient.Flowers
	t.ok(#flowers >= 20, `flower beds: {#flowers}`)
	local bed = flowers[1]
	setCamera(sim, CFrame.lookAt(bed + Vector3.new(10, 9, 0), bed))
	sim:Advance(3)
	local near = 0
	for _, item in critters.butterflies do
		local wing = item.data.wingL
		local pos = seen(sim, player, function()
			return wing.Position
		end)
		if (pos - bed).Magnitude < 75 then
			near += 1
		end
	end
	t.ok(near >= 3, `butterflies near the camera's flower beds: {near}`)
	sim:AssertNoErrors()
end

tests["own parts: quiet (no collisions, queries, touches, shadows), Material set, within the AmbientLife reserve"] = function(
	t
)
	local sim, player, ambient = boot(t)
	local _ = ambient
	local folder = sim.workspace:FindFirstChild("Ambient (client)")
	t.ok(folder, "the client's folder")
	local count = 0
	local loud = {}
	for _, d in folder:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
			if d.CanCollide or d.CanQuery or d.CanTouch or d.CastShadow or d.Material == Enum.Material.Plastic then
				table.insert(loud, d:GetFullName())
			end
		end
	end
	t.eq(#loud, 0, `quiet parts: {table.concat(loud, ", ", 1, math.min(#loud, 4))}`)
	local MapConfig = sim:Require(sim:Find("ReplicatedStorage.Shared.Config.MapConfig"), player)
	local reserve = MapConfig.PartBudget.RuntimeReserve.AmbientLife
	t.ok(count <= reserve, `{count} parts within the AmbientLife reserve {reserve}`)
	t.ok(count >= 150, `the living world is there ({count} parts)`)
	sim:AssertNoErrors()
end

return tests
