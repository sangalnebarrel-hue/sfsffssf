--[[
	fx_dump.luau — the fishing world FX in 3D, frame by frame, without Studio
	(FishingFxController + FishLife / FishShadow / FishingLine, with FisherAnimController posing
	the rigged fisher). Runs the built place in RbxSim with an R15 fisher and dumps what the
	FISHER's OWN client sees (his bobber 2.2×, his fish shadow, his line, his held trophy) as
	parts JSON for tools/preview/pose_sheet.py — the same format as pose_dump.luau, plus:
	  • the fishing line as its Bézier curve (Beam CurveSize0/1 along the attachments' axes),
	    10 thin boxes;
	  • trails (the rod tip's Whip, the bobber's CastTrail, the leap's LeapTrail) as streaks of
	    the positions their first attachment had over the trail's Lifetime;
	  • FishShadow parts (SpecialMesh «Sphere» → shape "Ellipsoid"), drips, the leap copy;
	  • per frame a `close` camera { eye, target, fov } aimed at what the segment is about.

	Segments (frames are labelled "<segment> <time>"; pose_sheet.py --only picks one):
	  cast    the tap → wind-up → release with the rod tip's whip trail, 30 fps (side view);
	  land    the bobber's flight on its curved line → the landing plop, 20 fps;
	  nibble  the own nibble: the shadow pokes the bobber, 15 fps;
	  wait    the shadow swims in and circles, the own nibble pokes it, the slack line, 4 fps;
	  bite    the lunge and the taut-on-every-jerk line, 20 fps;
	  reel    the thrashing shadow (Legendary scale) and the vibrating line, 20 fps;
	  leap    the caught fish flexes and drips on its way over the head, 30 fps;
	  trophy  the held fish flops, bobs and wiggles over the head, 10 fps.

	Usage (Lune 0.11, from the repo root; build Place1.rbxl first):
	  lune run tools/preview/fx_dump.luau OUT.json [--fish SharkPup] [--place Place1.rbxl]
	  python3 tools/preview/pose_sheet.py OUT.json OUT_cast.png --only cast --views close,game
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Sim = require("../sim")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local opts = { fish = "SharkPup", place = "Place1.rbxl" }
local out = nil
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if string.sub(a, 1, 2) == "--" then
		opts[string.sub(a, 3)] = process.args[i + 1]
		i += 2
	else
		out = a
		i += 1
	end
end
assert(out, "usage: lune run tools/preview/fx_dump.luau OUT.json [--fish SharkPup]")

local FRAME = 1 / 60

local sim = Sim.new({ place = opts.place })
sim:StartServer()
sim:Advance(0.5)
local fisher = sim:AddPlayer({ UserId = 1, Name = "Fisher", rig = "R15" })
sim:Advance(0.5)

local base = sim.workspace.Bases:FindFirstChild(`Base_{fisher:GetAttribute("BaseIndex")}`)
assert(base, "the fisher has no base")
local spot = base.FishingSpot.Position
local look = base:GetPivot().LookVector
look = Vector3.new(look.X, 0, look.Z).Unit
local right = look:Cross(Vector3.new(0, 1, 0)).Unit
local stand = spot + Vector3.new(0, 3, 0)
sim:Teleport(fisher, CFrame.lookAt(stand, stand + look))
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

local function vec(v: any): { number }
	return { round(v.X), round(v.Y), round(v.Z) }
end

local function rgb(color: any): { number }
	return { math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5) }
end

local BODY_COLORS = {
	Head = { 255, 214, 120 },
	UpperTorso = { 70, 130, 220 },
	LowerTorso = { 60, 110, 190 },
	RightUpperArm = { 230, 120, 90 },
	RightLowerArm = { 230, 120, 90 },
	RightHand = { 210, 100, 75 },
	LeftUpperArm = { 240, 170, 140 },
	LeftLowerArm = { 240, 170, 140 },
	LeftHand = { 225, 150, 120 },
}

local function shapeOf(part: any): string
	local mesh = part:FindFirstChildOfClass("SpecialMesh")
	if mesh and mesh.MeshType == roblox.Enum.MeshType.Sphere then
		return "Ellipsoid"
	end
	if part:IsA("Part") then
		local ok, shape = pcall(function()
			return part.Shape
		end)
		if ok and shape then
			return shape.Name
		end
	end
	return "Block"
end

local function partEntry(part: any, body: boolean?): any
	local color = if body then BODY_COLORS[part.Name] else nil
	if body and not color and (string.find(part.Name, "Leg", 1, true) or string.find(part.Name, "Foot", 1, true)) then
		color = { 60, 60, 80 }
	end
	local transparency = part.Transparency
	local ok, ltm = pcall(function()
		return part.LocalTransparencyModifier
	end)
	if ok and type(ltm) == "number" then
		transparency = 1 - (1 - transparency) * (1 - ltm)
	end
	color = color or rgb(part.Color)
	if string.sub(part.Name, 1, 10) == "FishShadow" and transparency < 0.98 then
		-- render.py blends only the nearest see-through surface (the water above): the shadow
		-- under it goes in opaque, its colour pre-mixed with the water's by its transparency
		local water = { 40, 120, 205 }
		local k = 1 - transparency
		color = {
			math.round(water[1] + (color[1] - water[1]) * k),
			math.round(water[2] + (color[2] - water[2]) * k),
			math.round(water[3] + (color[3] - water[3]) * k),
		}
		transparency = 0
	end
	return {
		name = part.Name,
		shape = shapeOf(part),
		cf = cframeArray(part.CFrame),
		size = vec(part.Size),
		color = color,
		transparency = round(transparency),
		material = part.Material.Name,
	}
end

-- A thin box from a to b (line pieces, trail streaks).
local function stick(name: string, a: any, b: any, width: number, color: { number }, transparency: number?): any?
	local length = (b - a).Magnitude
	if length < 0.02 then
		return nil
	end
	return {
		name = name,
		shape = "Block",
		cf = cframeArray(CFrame.lookAt((a + b) / 2, b)),
		size = { width, width, round(length) },
		color = color,
		transparency = transparency or 0,
		material = "Neon",
	}
end

-- Static surroundings: the pier and everything within 60 studs (no characters, no FX).
local scene = {}
for _, d in sim.workspace:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 0.98 and d.Name ~= "Terrain" then
		local model = d:FindFirstAncestorOfClass("Model")
		local inCharacter = model and model:FindFirstChildOfClass("Humanoid")
		if not inCharacter and not d:FindFirstAncestor("FishingFx") and (d.Position - spot).Magnitude < 60 then
			table.insert(scene, partEntry(d))
		end
	end
end
table.insert(scene, {
	name = "Water",
	kind = "water",
	shape = "Block",
	-- a thin surface layer: what is under the water (the fish shadow) shows through it
	cf = cframeArray(CFrame.new(spot.X, -0.05, spot.Z)),
	size = { 200, 0.1, 200 },
	color = { 40, 120, 205 },
	transparency = 0.45,
})

local scripts = fisher:FindFirstChildOfClass("PlayerScripts")
local fx = sim:Require(sim:Find("Controllers.FishingFxController", scripts), fisher)
local anim = sim:Require(sim:Find("Controllers.FisherAnimController", scripts), fisher)
local service = sim:Require(sim:Find("ServerScriptService.Services.FishingService"))
local rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"))
local config = sim:Require(sim:Find("ReplicatedStorage.Shared.Config.FishingConfig"))

local def = rules.GetFish(opts.fish)
local value, income = rules.Price(opts.fish, def.MinKg, nil)
service.RollFishForTest = function()
	return { Id = opts.fish, Rarity = def.Rarity, Kg = def.MinKg, Value = value, Income = income }
end

local frames = {}
local folder = nil -- the fisher's client's Workspace.FishingFx
local trails = {} -- trail -> { { t, p } }
-- current close-up camera: function(seen) -> { eye, target, fov }; seen = this frame's client
-- positions { tipAt, bobberAt, heldAt, headAt } (rod tip, bobber, held fish, head)
local close: any = nil

-- Every 60 fps step: where the trails' first attachments are (their streaks).
local function tick()
	sim:Run(function()
		local now = sim:Time()
		local roots = { fisher.Character }
		if folder then
			table.insert(roots, folder)
		end
		for _, root in roots do
			for _, d in root:GetDescendants() do
				if d:IsA("Trail") and d.Enabled and d.Attachment0 then
					local list = trails[d] or {}
					trails[d] = list
					table.insert(list, { t = now, p = d.Attachment0.WorldPosition, q = d.Attachment1.WorldPosition })
				end
			end
		end
	end, fisher)
end

local function advanceTo(time: number)
	while sim:Time() < time - 1e-9 do
		sim:Advance(FRAME)
		tick()
	end
end

local function bezier(beam: any): { any }
	local a0, a1 = beam.Attachment0, beam.Attachment1
	if not a0 or not a1 then
		return {}
	end
	local p0, p3 = a0.WorldPosition, a1.WorldPosition
	local p1 = p0 + a0.WorldCFrame.XVector * beam.CurveSize0
	local p2 = p3 - a1.WorldCFrame.XVector * beam.CurveSize1
	local pts = {}
	for k = 0, 10 do
		local u = k / 10
		local v = 1 - u
		table.insert(pts, p0 * (v * v * v) + p1 * (3 * v * v * u) + p2 * (3 * v * u * u) + p3 * (u * u * u))
	end
	return pts
end

local function capture(label: string)
	local entry = sim:Run(function()
		local parts = {}
		local character = fisher.Character
		for _, d in character:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 0.98 and d.Name ~= "HumanoidRootPart" then
				table.insert(parts, partEntry(d, d.Parent == character))
			end
		end
		local bobber = fx.GetBobber(fisher)
		if bobber then
			folder = bobber.Parent
		end
		if folder then
			for _, d in folder:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 0.98 and d.Size.Magnitude < 14 then
					table.insert(parts, partEntry(d))
				end
			end
		end
		-- the line: its Bézier curve
		local line = bobber and bobber:FindFirstChild("Line")
		if line and line.Enabled then
			local pts = bezier(line)
			local color = rgb(line.Color.Keypoints[1].Value)
			for k = 1, #pts - 1 do
				local piece = stick("Line", pts[k], pts[k + 1], 0.06, color)
				if piece then
					table.insert(parts, piece)
				end
			end
		end
		-- trails: their streaks over the last Lifetime
		local now = sim:Time()
		for trail, list in trails do
			if trail.Parent then
				local life = trail.Lifetime
				local color = rgb(trail.Color.Keypoints[1].Value)
				local prev = nil
				for _, sample in list do
					if now - sample.t <= life then
						local mid = (sample.p + sample.q) / 2
						if prev then
							local age = (now - sample.t) / life
							local piece = stick(trail.Name, prev, mid, 0.12 * (1 - age) + 0.03, color, 0.2 + 0.6 * age)
							if piece then
								table.insert(parts, piece)
							end
						end
						prev = mid
					end
				end
			end
		end
		local root = character.HumanoidRootPart
		local offset = character.Humanoid.CameraOffset
		local focus = root.Position + Vector3.new(0, 1.5, 0) + root.CFrame:VectorToWorldSpace(offset)
		local tip = anim.GetRodTip(fisher)
		local held = character:FindFirstChild("HeldFish")
		return {
			tipAt = if tip then tip.WorldPosition else nil,
			bobberAt = if bobber then bobber:GetPivot().Position else nil,
			heldAt = if held then held:GetBoundingBox().Position else nil,
			leapAt = if folder and folder:FindFirstChild("Leap")
				then folder:FindFirstChild("Leap"):GetBoundingBox().Position
				else nil,
			headAt = character.Head.Position,
			parts = parts,
			focus = vec(focus),
			root = vec(root.Position),
			look = vec(root.CFrame.LookVector),
			right = vec(root.CFrame.RightVector),
			phase = anim.GetPhase(fisher),
			bend = round(math.deg(anim.GetRodBend(fisher))),
		}
	end, fisher)
	if close then
		local c = close(entry)
		entry.close = { eye = vec(c.eye), target = vec(c.target), fov = c.fov or 50 }
	end
	entry.tipAt, entry.bobberAt, entry.heldAt, entry.headAt, entry.leapAt = nil, nil, nil, nil, nil
	entry.label = label
	entry.t = round(sim:Time())
	table.insert(frames, entry)
	print(string.format("  %-22s phase=%-8s bend=%5.1f°", label, entry.phase, entry.bend))
end

local function shoot(name: string, from: number, to: number, fps: number)
	local t = from
	while t <= to + 1e-6 do
		advanceTo(t)
		capture(string.format("%s %.2f", name, t - from))
		t += 1 / fps
	end
end

local function events(): { any }
	return sim:ClientEventsFor(fisher, "FishingState")
end

local function waitState(name: string, timeout: number): any
	local start = #events()
	return sim:WaitFor(function()
		tick()
		for k = start + 1, #events() do
			if events()[k].args[1] == name then
				return events()[k]
			end
		end
		return nil
	end, timeout, FRAME)
end

local function bobberWater(): any
	local target = fisher:GetAttribute("BobberTarget")
	return target or (stand + look * 20)
end

-- rod in hand
local rod = nil
for _, container in { fisher.Backpack, fisher.Character } do
	for _, item in container:GetChildren() do
		if item:IsA("Tool") and item:GetAttribute("RodId") then
			rod = item
		end
	end
end
assert(rod, "no rod")
sim:EquipTool(fisher, rod)
-- (RbxSim stores whole-number attributes as float32: keep CastTime fractional, as pose_dump does)
advanceTo(sim:Time() + 1.537)

-- cast: the rod tip from the side (wind-up, release, whip trail) …
sim:FireServer(fisher, "FishingCast")
local castAt = sim:Time()
close = function()
	local at = stand + look * 2 + Vector3.new(0, 4.5, 0)
	return { eye = at + right * 13 - look * 1 + Vector3.new(0, 1, 0), target = at, fov = 50 }
end
shoot("cast", castAt, castAt + config.CastWindUp + 0.35, 30)
-- … then the bobber's flight on its curved line and the landing plop, close to the water
close = function()
	local water = bobberWater()
	return {
		eye = water + right * 9 - look * 6 + Vector3.new(0, 3.5, 0),
		target = water + Vector3.new(0, 1.5, 0),
		fov = 55,
	}
end
shoot("land", sim:Time(), castAt + config.CastWindUp + config.CastFlightTime + 0.8, 20)

-- waiting: the shadow (from above the bobber), a nibble
close = function()
	local water = bobberWater()
	return { eye = water - look * 9 + right * 2 + Vector3.new(0, 10, 0), target = water, fov = 50 }
end
local waitFrom = sim:Time()
shoot("wait", waitFrom, waitFrom + 2.2, 4)
sim:Run(function()
	fx.Nibble()
end, fisher)
shoot("nibble", sim:Time(), sim:Time() + 0.6, 15)

-- bite and reel
local bite = waitState("Bite", 10)
assert(bite, "no bite")
shoot("bite", sim:Time(), sim:Time() + 0.8, 20)
local count = #events()
sim:FireServer(fisher, "FishingHook")
local mgEntry = events()[count + 1]
assert(mgEntry and mgEntry.args[1] == "Minigame", "no minigame")
local hookAt = sim:Time()
shoot("reel", hookAt, hookAt + 1.0, 20)

-- win the minigame
local mg = mgEntry.args[2]
local center = mg.ZoneCenter
local from = math.max(config.TapInterval + 0.02, sim:Time() - hookAt + 0.02)
local caughtAt = nil
for _ = 1, mg.HitsNeeded do
	local moment = from
	while math.abs(rules.Needle(mg.U0, mg.Speed, moment) - center) > mg.ZoneWidth * 0.3 do
		moment += 0.005
	end
	advanceTo(hookAt + moment)
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

-- the leap (from the side), then the trophy over the head (close-up)
close = function(seen: any)
	-- following the leaping fish from its side (it flexes and drips)
	local at = seen.leapAt or seen.heldAt or (seen.headAt + Vector3.new(0, 2.4, 0))
	return { eye = at - look * 9 + right * 3 + Vector3.new(0, 1.5, 0), target = at, fov = 45 }
end
shoot("leap", caughtAt, caughtAt + config.LeapTime + 0.1, 30)
close = function(seen: any)
	-- straight behind the fisher, level with the fish: its side, as the own camera sees it
	local at = seen.heldAt or (seen.headAt + Vector3.new(0, 2.4, 0))
	return { eye = at - look * 8 + Vector3.new(0, 0.3, 0), target = at, fov = 45 }
end
shoot("trophy", sim:Time(), sim:Time() + 2.7, 15)

for _, e in sim.Errors do
	print("ERROR", e.context, e.message)
end
fs.writeFile(out, serde.encode("json", { mode = "fx", rig = "R15", scene = { parts = scene }, frames = frames }))
print(`wrote {#frames} frames to {out}`)
