--[[
	pose_dump.luau — fisher animation previews without Studio (FisherAnimController, FisherRig,
	FisherPoses, FisherRod). Runs the built place in RbxSim with a rigged fisher
	(sim:AddPlayer{ rig = ... }) and a watcher next to him, and dumps what the WATCHER's client
	sees (client-local joint Transforms, rod bend, bobber, leap, held fish) as parts JSON for
	tools/preview/pose_sheet.py:

	  --mode timeline (default)  a real fishing session played by the real server and the real
	                             controllers: equip, cast (wind-up → release → throw → wait),
	                             bite, strike, reel, catch (yank → leap → trophy → hold), then a
	                             second cast lost too early (slump, head shake) and a third one
	                             reeled in (retract); frames at the moments in TIMELINE below;
	  --mode poses               every key pose of FisherPoses on its own (the Animator stand-in
	                             holds it; FisherRig.fold / legBend applied like in the game), the
	                             rod straight — the contact sheet of the pose data.

	Usage (Lune 0.11, from the repo root; build Place1.rbxl first):
	  lune run tools/preview/pose_dump.luau OUT.json [--mode timeline|poses] [--rig R15|R6]
	      [--joints Motor6D|AnimationConstraint] [--fish Crucian] [--place Place1.rbxl]
	  python3 tools/preview/pose_sheet.py OUT.json OUT.png

	JSON: { mode, rig, scene = { parts }, frames = { { label, t, focus, look, right, parts } } }
	— parts in the export_parts.luau format (cf, size, color, transparency, shape, kind);
	focus / look / right: the fisher's default-camera focus (HumanoidRootPart + 1.5 up +
	Humanoid.CameraOffset in his frame) and his facing — pose_sheet.py puts the Roblox camera
	12.5 studs behind it, 18° down (the GUI previews' camera), plus a side view from his right.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Sim = require("../sim")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local opts = { mode = "timeline", rig = "R15", joints = "Motor6D", fish = "Crucian", place = "Place1.rbxl" }
local out = nil
local args = process.args
local i = 1
while i <= #args do
	local a = args[i]
	if string.sub(a, 1, 2) == "--" then
		opts[string.sub(a, 3)] = args[i + 1]
		i += 2
	else
		out = a
		i += 1
	end
end
assert(out, "usage: lune run tools/preview/pose_dump.luau OUT.json [--mode timeline|poses] [--rig R15|R6]")

local FRAME = 1 / 60

local sim = Sim.new({ place = opts.place })
sim:StartServer()
sim:Advance(0.5)
local fisher = sim:AddPlayer({ UserId = 1, Name = "Fisher", rig = opts.rig, joints = opts.joints })
local watcher = sim:AddPlayer({ UserId = 2, Name = "Watcher", rig = "R15" })
sim:Advance(0.5)

local base = sim.workspace.Bases:FindFirstChild(`Base_{fisher:GetAttribute("BaseIndex")}`)
assert(base, "the fisher has no base")
local spot = base.FishingSpot.Position
local look = base:GetPivot().LookVector
look = Vector3.new(look.X, 0, look.Z).Unit
local stand = spot + Vector3.new(0, 3, 0)
sim:Teleport(fisher, CFrame.lookAt(stand, stand + look))
-- the watcher stands behind, out of the picture
sim:Teleport(watcher, stand - look * 30 + Vector3.new(0, 0, 0))
sim:Advance(0.2)

local function round(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4
end

local function cframeArray(cf: any): { number }
	local c = { cf:GetComponents() }
	for k, v in c do
		c[k] = round(v)
	end
	return c
end

local function colorArray(color: any): { number }
	return {
		math.floor(color.R * 255 + 0.5),
		math.floor(color.G * 255 + 0.5),
		math.floor(color.B * 255 + 0.5),
	}
end

local function vec(v: any): { number }
	return { round(v.X), round(v.Y), round(v.Z) }
end

local function shapeOf(part: any): string
	if part:IsA("WedgePart") then
		return "Wedge"
	elseif part:IsA("CornerWedgePart") then
		return "CornerWedge"
	elseif part:IsA("Part") then
		local ok, shape = pcall(function()
			return part.Shape
		end)
		if ok and shape then
			return shape.Name
		end
	end
	return "Block"
end

-- RbxSim avatars have no appearance: body parts get readable colours by name.
local BODY_COLORS = {
	Head = { 255, 214, 120 },
	UpperTorso = { 70, 130, 220 },
	LowerTorso = { 60, 110, 190 },
	Torso = { 70, 130, 220 },
	RightUpperArm = { 230, 120, 90 },
	RightLowerArm = { 230, 120, 90 },
	RightHand = { 210, 100, 75 },
	["Right Arm"] = { 230, 120, 90 },
	LeftUpperArm = { 240, 170, 140 },
	LeftLowerArm = { 240, 170, 140 },
	LeftHand = { 225, 150, 120 },
	["Left Arm"] = { 240, 170, 140 },
}

local function partEntry(part: any, body: boolean?): any
	local color = if body then BODY_COLORS[part.Name] else nil
	if body and not color and (string.find(part.Name, "Leg", 1, true) or string.find(part.Name, "Foot", 1, true)) then
		color = { 60, 60, 80 }
	end
	return {
		name = part.Name,
		shape = shapeOf(part),
		cf = cframeArray(part.CFrame),
		size = vec(part.Size),
		color = color or colorArray(part.Color),
		transparency = round(part.Transparency),
		material = part.Material.Name,
	}
end

-- Static surroundings (server view): the pier and everything within 45 studs, no characters.
local scene = {}
for _, d in sim.workspace:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 0.98 and d.Name ~= "Terrain" then
		local model = d:FindFirstAncestorOfClass("Model")
		local inCharacter = model and model:FindFirstChildOfClass("Humanoid")
		local inFx = d:FindFirstAncestor("FishingFx")
		if not inCharacter and not inFx and (d.Position - spot).Magnitude < 45 then
			table.insert(scene, partEntry(d))
		end
	end
end
table.insert(scene, {
	name = "Water",
	kind = "water",
	shape = "Block",
	cf = cframeArray(CFrame.new(spot.X, -0.5, spot.Z)),
	size = { 160, 1, 160 },
	color = { 40, 120, 205 },
	transparency = 0.45,
})

local fx = sim:Require(sim:Find("Controllers.FishingFxController", watcher.PlayerScripts), watcher)
local anim = sim:Require(sim:Find("Controllers.FisherAnimController", watcher.PlayerScripts), watcher)

local frames = {}

-- One frame as the watcher sees it.
local function capture(label: string)
	local entry = sim:Run(function()
		local parts = {}
		local character = fisher.Character
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 0.98 then
				table.insert(parts, partEntry(d, d.Parent == character))
			end
		end
		local bobber = fx.GetBobber(fisher)
		if bobber then
			for _, d in bobber:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 0.98 then
					table.insert(parts, partEntry(d))
				end
			end
		end
		for _, instance in fx.GetEffects(fisher) do
			local items = instance:GetDescendants()
			table.insert(items, instance)
			for _, d in items do
				if d:IsA("BasePart") and d.Transparency < 0.98 and d.Size.Magnitude < 12 then
					table.insert(parts, partEntry(d))
				end
			end
		end
		-- the fishing line: a thin box from the rod tip to the bobber
		local tool = character:FindFirstChildOfClass("Tool")
		local tip = tool and tool:FindFirstChild("Handle") and tool.Handle:FindFirstChild("TipAttachment")
		local tie = bobber and bobber:FindFirstChild("LineAttachment", true)
		if tip and tie then
			local a, b = tip.WorldPosition, tie.WorldPosition
			local length = (b - a).Magnitude
			if length > 0.05 then
				local cf = CFrame.lookAt((a + b) / 2, b)
				table.insert(parts, {
					name = "Line",
					shape = "Block",
					cf = cframeArray(cf),
					size = { 0.07, 0.07, round(length) },
					color = { 250, 250, 240 },
					transparency = 0,
					material = "Neon",
				})
			end
		end
		local root = character.HumanoidRootPart
		local humanoid = character.Humanoid
		local offset = humanoid.CameraOffset
		local focus = root.Position + Vector3.new(0, 1.5, 0) + root.CFrame:VectorToWorldSpace(offset)
		local phase = anim.GetPhase(fisher)
		return {
			parts = parts,
			focus = vec(focus),
			root = vec(root.Position),
			look = vec(root.CFrame.LookVector),
			right = vec(root.CFrame.RightVector),
			phase = phase,
			bend = round(math.deg(anim.GetRodBend(fisher))),
		}
	end, watcher)
	entry.label = label
	entry.t = round(sim:Time())
	table.insert(frames, entry)
	print(string.format("  %-28s phase=%-7s bend=%5.1f°", label, entry.phase, entry.bend))
end

local function events(): { any }
	return sim:ClientEventsFor(fisher, "FishingState")
end

local function waitState(name: string, timeout: number): number?
	local start = #events()
	local entry = sim:WaitFor(function()
		for k = start + 1, #events() do
			if events()[k].args[1] == name then
				return events()[k]
			end
		end
		return nil
	end, timeout, FRAME)
	return entry and entry.time
end

-- Steps to an absolute sim time (frame by frame) and captures.
local function at(time: number, label: string)
	sim:WaitFor(function()
		return sim:Time() >= time - 1e-9
	end, 30, FRAME)
	capture(label)
end

local function equipRod()
	local rod
	for _, container in { fisher.Backpack, fisher.Character } do
		for _, item in container:GetChildren() do
			if item:IsA("Tool") and item:GetAttribute("RodId") then
				rod = item
			end
		end
	end
	assert(rod, "no rod")
	sim:EquipTool(fisher, rod)
	return rod
end

local LeapTime = 1

if opts.mode == "poses" then
	-- Key poses: the Animator stand-in holds each pose (FisherRig maths), the rod is in hand.
	local FisherRig = sim:Require(sim:Find("StarterPlayer.StarterPlayerScripts.Controllers.FisherRig"))
	local FisherPoses = sim:Require(sim:Find("StarterPlayer.StarterPlayerScripts.Controllers.FisherPoses"))
	equipRod()
	-- only the Animator stand-in poses the fisher here: the watcher's controller is switched off
	anim.Enabled = false
	sim:Advance(1)
	local rig = FisherRig.build(fisher.Character)
	assert(rig, "rig")
	local fishModel = sim:Find("ReplicatedStorage.Assets.Fish." .. opts.fish .. ".Normal")
	for _, name in FisherPoses.Order do
		local data = FisherPoses.Poses[name]
		local cf, w, add = {}, {}, {}
		for channel, a in data do
			local r = FisherRig.rot(a[1], a[2], a[3])
			if a[4] then
				r = CFrame.new(a[4] * rig.scale, a[5] * rig.scale, a[6] * rig.scale) * r
			end
			cf[channel], w[channel] = r, 1
		end
		if rig.rigType == "R15" and cf.Root then
			local theta = math.deg(FisherRig.legBend(rig, -cf.Root.Y))
			if theta > 0.01 then
				for _, leg in { "RHip", "LHip", "RAnkle", "LAnkle" } do
					add[leg] = FisherRig.rot(theta, 0, 0)
				end
				add.RKnee, add.LKnee = FisherRig.rot(-2 * theta, 0, 0), FisherRig.rot(-2 * theta, 0, 0)
			end
		end
		FisherRig.fold(rig, cf, w, add)
		local animatorPose = {}
		for channel, j in rig.joints do
			local target = cf[channel] or CFrame.identity
			if add[channel] then
				target = add[channel] * target
			end
			animatorPose[j.instance.Name] = j.inv * target * j.rot
		end
		sim:SetAnimatorPose(fisher, animatorPose)
		sim:Advance(2 * FRAME)
		local held = nil
		if string.sub(name, 1, 6) == "Trophy" and fishModel then
			-- a stand-in for the server's HeldFish over the head (FishingService.holdFish)
			held = fishModel:Clone()
			local head = fisher.Character.Head
			local box, size = held:GetBoundingBox()
			local center = held:GetPivot():PointToObjectSpace(box.Position)
			held:PivotTo(head.CFrame * CFrame.new(0, head.Size.Y / 2 + 0.5 + size.Y / 2, 0) * CFrame.new(-center))
			held.Name = "HeldFish"
			held.Parent = fisher.Character
		end
		capture(name)
		if held then
			held:Destroy()
		end
	end
else
	print("timeline:")
	local service = sim:Require(sim:Find("ServerScriptService.Services.FishingService"))
	local rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"))
	local config = sim:Require(sim:Find("ReplicatedStorage.Shared.Config.FishingConfig"))
	LeapTime = config.LeapTime
	local def = rules.GetFish(opts.fish)
	local value, income = rules.Price(opts.fish, def.MinKg, nil)
	service.RollFishForTest = function()
		return { Id = opts.fish, Rarity = def.Rarity, Kg = def.MinKg, Value = value, Income = income }
	end

	equipRod()
	local equipped = sim:Time()
	at(equipped + 0.25, "ready (took the rod)")
	at(equipped + 1.5, "hold")

	-- 1) cast → bite → strike → reel → caught → trophy
	sim:Advance(1.037) -- (RbxSim stores whole-number attributes as float32: keep CastTime fractional)
	sim:FireServer(fisher, "FishingCast")
	local castAt = sim:Time()
	local release = castAt + config.CastWindUp
	at(release - 0.2, "wind-up")
	at(release - 0.05, "cocked")
	at(release, "release (CastTime)")
	at(release + 0.05, "whip")
	at(release + 0.1, "throw")
	at(release + 0.3, "settle")
	at(release + 1, "waiting")
	local bite = waitState("Bite", 10)
	assert(bite, "no bite")
	at(bite + 0.05, "bite: startle")
	sim:WaitFor(function()
		return sim:Run(function()
			return fx.GetBobberDip(fisher)
		end, watcher) > 0.8
	end, 2, FRAME)
	capture("bite: deep dip")
	sim:Advance(0.1)
	local count = #events()
	sim:FireServer(fisher, "FishingHook")
	local hookAt = sim:Time()
	at(hookAt + 0.09, "strike")
	at(hookAt + 0.5, "reel")
	at(hookAt + 0.62, "reel (swing)")
	local mgEntry = events()[count + 1]
	assert(mgEntry and mgEntry.args[1] == "Minigame", "no minigame")
	local mg = mgEntry.args[2]
	local center = mg.ZoneCenter
	local from = config.TapInterval + 0.02
	local caughtAt = nil
	for _ = 1, mg.HitsNeeded do
		local moment = math.max(from, sim:Time() - hookAt + 0.02)
		while math.abs(rules.Needle(mg.U0, mg.Speed, moment) - center) > mg.ZoneWidth * 0.3 do
			moment += 0.005
		end
		sim:WaitFor(function()
			return sim:Time() >= hookAt + moment - 1e-9
		end, 10, FRAME)
		local before = #events()
		sim:FireServer(fisher, "FishingTap", moment)
		local e = events()[before + 1]
		if e and e.args[1] == "Zone" then
			center = e.args[2].ZoneCenter
			from = moment + config.TapInterval + 0.02
		else
			caughtAt = sim:Time()
			break
		end
	end
	assert(caughtAt, "not caught")
	at(caughtAt + 0.12, "caught: yank")
	at(caughtAt + 0.5, "caught: look up")
	at(caughtAt + LeapTime - 0.1, "caught: arms up")
	at(caughtAt + LeapTime + 0.12, "landed: hop")
	at(caughtAt + LeapTime + 0.9, "trophy")
	local holdTime = rules.HoldFishTime(def.Rarity)
	at(caughtAt + LeapTime + holdTime + 0.5, "trophy gone: arms down")

	-- 2) lost: hooked too early
	sim:Advance(1.537)
	sim:FireServer(fisher, "FishingCast")
	sim:Advance(config.CastWindUp + config.CastFlightTime + 0.4)
	sim:FireServer(fisher, "FishingHook")
	local lostAt = sim:Time()
	at(lostAt + 0.3, "lost: slump")
	at(lostAt + 0.55, "lost: head shake")
	at(lostAt + 1.6, "lost: recovered")

	-- 3) reeled in without a fish
	sim:Advance(1.537)
	sim:FireServer(fisher, "FishingCast")
	sim:Advance(config.CastWindUp + config.CastFlightTime + 0.6)
	sim:FireServer(fisher, "FishingStop")
	local stopAt = sim:Time()
	at(stopAt + 0.2, "retract: crank")
	at(stopAt + 0.9, "retract: hold")
end

local errors = sim.Errors
for _, e in errors do
	print("ERROR", e.context, e.message)
end
fs.writeFile(
	out,
	serde.encode("json", {
		mode = opts.mode,
		rig = opts.rig .. (if opts.joints == "AnimationConstraint" then " AJU" else ""),
		scene = { parts = scene },
		frames = frames,
	})
)
print(`wrote {#frames} frames to {out}`)
