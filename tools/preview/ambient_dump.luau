--[[
	ambient_dump.luau — the living world over time, without Studio (AmbientController and its
	helpers AmbientEngine / AmbientWind / AmbientWorld / AmbientWater / AmbientCritters). Runs the
	built place in RbxSim with one player, puts the client's camera at named views (the fishing
	spot's follow camera, the pier walk, the hub plaza …), lets the real client controllers run and
	dumps what THAT client sees (client-local CFrames and transparency of every swaying flag, bobbing
	boat, fish, gull, foam disc …) every --step seconds, as parts JSON for
	tools/preview/ambient_sheet.py (contact sheets + a "what moved" map per view). It also measures
	the engine per view: parts moved and properties written per frame (average / peak), items
	updated / culled, tier sizes — the same numbers the module header quotes.

	Particles, SurfaceGui rings and Beams are not parts: the dump adds stand-ins so they show in the
	renders — glints as small bright balls inside an enabled glint box, the jump splash as droplets
	for 0.6 s after the splash host moved, the jump rings as 16 segments at their current size and
	transparency, the foam rings round hulls and posts as 24 segments along their rounded outline,
	the waterfall beams as streaks sliding down with the texture.

	Usage (Lune 0.11, from the repo root; build Place1.rbxl first):
	  lune run tools/preview/ambient_dump.luau OUT.json [--views spot,pier,hub] [--frames 8]
	      [--step 0.25] [--warmup 3] [--radius 320] [--device phone] [--place Place1.rbxl]
	      [--jump spot,pier]   (a fish jumps right at the start of these views' frames)
	      [--swoop spot]       (the pier gull's swoop is scheduled at the start of these views)
	  python3 tools/preview/ambient_sheet.py OUT.json OUT_DIR [--terrain smoothgrid.bin]

	Views (base 1 = the player's base): spot (the fishing camera: 12.5 studs behind the spot's
	focus, 18° down), spot_wide (the same spot, looking along the lagoon), pier (walking out on the
	pier), platform (from the water back at the fishing platform: windsock, chime, roof flag,
	pennants), hub (the avenue towards the tower), beach (the ring beach next to the pier),
	waterfall (the cascade from the pond), fair (the fun fair: Ferris wheel and its chase lights),
	garden (the flower bed nearest to the base: butterflies), boat (the base's boat: bobbing and foam).

	JSON: { views = { { name, eye, target, fov, stats, scene = { parts }, frames = { { t, parts } } } },
	        water, grade, atmosphere } — parts in the export_parts.luau format plus `id` (a frame's
	part with the same id replaces the scene's).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Sim = require("../sim")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local opts = {
	views = "spot,pier,hub",
	frames = "8",
	jump = "",
	swoop = "",
	step = "0.25",
	warmup = "3",
	radius = "320",
	device = "phone",
	place = "Place1.rbxl",
}
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
assert(out, "usage: lune run tools/preview/ambient_dump.luau OUT.json [--views spot,pier,hub] [--frames 8]")
local FRAMES = tonumber(opts.frames) :: number
local STEP = tonumber(opts.step) :: number
local WARMUP = tonumber(opts.warmup) :: number
local RADIUS = tonumber(opts.radius) :: number

local sim = Sim.new({ place = opts.place })
sim:StartServer()
sim:Advance(0.5)
local player = sim:AddPlayer({ UserId = 1, Name = "Viewer", device = opts.device })
sim:Advance(1)
local ambient = sim:Require(sim:Find("Controllers.AmbientController", player.PlayerScripts), player)
sim:WaitFor(function()
	return ambient.Ready
end, 10)
local engine = ambient.Engine

local base = sim.workspace.Bases:FindFirstChild(`Base_{player:GetAttribute("BaseIndex")}`)
assert(base, "the viewer has no base")
local pivot = base:GetPivot()
local spot = base.FishingSpot.Position
local look = pivot.LookVector
local function polar(theta: number, r: number, y: number): any
	local a = math.rad(theta)
	return Vector3.new(r * math.sin(a), y, r * math.cos(a))
end
local focus = spot + Vector3.new(0, 4.8, 0)
local spotEye = focus - look * 12.5 * math.cos(math.rad(18)) + Vector3.new(0, 12.5 * math.sin(math.rad(18)), 0)
local function baseLocal(x: number, y: number, z: number): any
	return pivot * Vector3.new(x, y, z)
end
local VIEWS = {
	spot = { eye = spotEye, target = focus + (focus - spotEye).Unit * 100 },
	spot_wide = { eye = spotEye, target = spot + pivot.RightVector * 60 - look * 25 },
	pier = { eye = pivot * Vector3.new(0, 9.5, -6), target = pivot * Vector3.new(0, 4, -60) },
	platform = { eye = baseLocal(-4, 9, -86), target = baseLocal(2, 9, -48) },
	hub = { eye = polar(0, 140, 10), target = polar(0, 20, 8) },
	beach = { eye = polar(22.5 + 9, 304, 7.5), target = polar(22.5 + 20, 298, 2.5) },
	waterfall = { eye = Vector3.new(232, 12, 232), target = Vector3.new(276, 26, 280) },
	fair = { eye = Vector3.new(-30, 10, -15), target = Vector3.new(-85, 18, -70) },
}

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
	return { math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5) }
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
local FACES = { "Top", "Bottom", "Front", "Back", "Left", "Right" }

local ids: { [any]: number } = {}
local nextId = 0
local function idOf(part: any): number
	local id = ids[part]
	if not id then
		nextId += 1
		id = nextId
		ids[part] = id
	end
	return id
end

local function entry(part: any, withSurfaces: boolean): any
	local e = {
		id = idOf(part),
		name = part.Name,
		shape = shapeOf(part),
		cf = cframeArray(part.CFrame),
		size = vec(part.Size),
		color = colorArray(part.Color),
		transparency = round(part.Transparency),
		material = part.Material.Name,
	}
	if withSurfaces and part.Material == Enum.Material.Plastic then
		local surfaces = {}
		local any = false
		for _, face in FACES do
			local s = part[face .. "Surface"]
			if s and s.Name ~= "Smooth" then
				surfaces[face] = s.Name
				any = true
			end
		end
		if any then
			e.surfaces = surfaces
		end
	end
	return e
end

local function ball(name: string, pos: any, size: number, color: { number }, transparency: number): any
	return {
		name = name,
		shape = "Ball",
		cf = cframeArray(CFrame.new(pos)),
		size = { size, size, size },
		color = color,
		transparency = transparency,
		material = "Neon",
	}
end

-- Parts the camera can see (in front, within RADIUS), as the viewer's client sees them.
local function gather(eye: any, forward: any): { any }
	local list = {}
	for _, d in sim.workspace:GetDescendants() do
		if d:IsA("BasePart") and d.Name ~= "Terrain" then
			local p = d.Position
			local rel = p - eye
			local dist = rel.Magnitude
			local reach = d.Size.Magnitude / 2
			if dist - reach < RADIUS and rel:Dot(forward) > -reach - 8 then
				local model = d:FindFirstAncestorOfClass("Model")
				if not (model and model:FindFirstChildOfClass("Humanoid")) then
					table.insert(list, d)
				end
			end
		end
	end
	return list
end

-- A tiny deterministic generator (Lune has no Random): rng:NextNumber(a, b).
local Random = {}
function Random.new(seed: number): any
	local state = (math.floor(seed) % 2147483646) + 1
	return {
		NextNumber = function(_, a: number, b: number): number
			state = (state * 16807) % 2147483647
			return a + (b - a) * (state / 2147483647)
		end,
	}
end

-- Stand-ins for particles, rings and beams (see the header).
local splashSeen: { [any]: { pos: any, at: number } } = {}
local function fxEntries(now: number): { any }
	local list = {}
	local folder = sim.workspace:FindFirstChild("Ambient (client)")
	local rng = Random.new(math.floor(now * 1000))
	if folder then
		for _, host in folder:GetChildren() do
			if host.Name == "WaterGlints" then
				local emitter = host:FindFirstChild("Glints")
				if emitter and emitter.Enabled then
					for _ = 1, 5 do
						local p = host.CFrame
							* Vector3.new(
								rng:NextNumber(-0.5, 0.5) * host.Size.X,
								0.2,
								rng:NextNumber(-0.5, 0.5) * host.Size.Z
							)
						table.insert(list, ball("Glint", p, rng:NextNumber(0.5, 1.1), { 255, 250, 225 }, 0.1))
					end
				end
			elseif host.Name == "JumpSplash" then
				local pos = host.Position
				local seen = splashSeen[host]
				if not seen or (seen.pos - pos).Magnitude > 0.5 then
					splashSeen[host] = { pos = pos, at = now }
					seen = splashSeen[host]
				end
				local age = now - seen.at
				if pos.Y > -5 and age < 0.6 then
					local drops = Random.new(math.floor(seen.at * 100))
					for _ = 1, 10 do
						local a = drops:NextNumber(0, 2 * math.pi)
						local v = drops:NextNumber(7, 12)
						local spread = drops:NextNumber(0.1, 0.45)
						local h = Vector3.new(math.cos(a), 0, math.sin(a)) * v * spread * age
						local y = v * age - 17 * age * age
						if y > -0.2 then
							table.insert(
								list,
								ball(
									"Droplet",
									pos + h + Vector3.new(0, y, 0),
									0.45 * (1 - age),
									{ 255, 255, 255 },
									0.15 + age
								)
							)
						end
					end
				end
			elseif host.Name == "FoamRing" and host.Position.Y > -50 then
				-- a rounded ring (stadium) round the hull: 24 short segments along its outline
				local gui = host:FindFirstChild("Foam")
				local ring = gui and gui:FindFirstChild("Ring")
				local stroke = ring and ring:FindFirstChildOfClass("UIStroke")
				if stroke and stroke.Transparency < 0.98 then
					local w, l = host.Size.X / 2, host.Size.Z / 2
					local r = math.min(w, l)
					local points = {}
					for k = 0, 23 do
						local a = k / 24 * 2 * math.pi
						local x, z = math.cos(a), math.sin(a)
						-- (corner circle centres at ±(w - r), ±(l - r))
						local px = (w - r) * (if x >= 0 then 1 else -1) + r * x
						local pz = (l - r) * (if z >= 0 then 1 else -1) + r * z
						table.insert(points, host.CFrame * Vector3.new(px, 0.03, pz))
					end
					for k = 1, #points do
						local p0, p1 = points[k], points[k % #points + 1]
						local mid = (p0 + p1) / 2
						local len = (p1 - p0).Magnitude
						if len > 0.01 then
							table.insert(list, {
								name = "FoamSegment",
								shape = "Block",
								cf = cframeArray(CFrame.lookAt(mid, p1)),
								size = { 0.35, 0.06, round(len + 0.1) },
								color = { 245, 252, 255 },
								transparency = round(stroke.Transparency),
								material = "SmoothPlastic",
							})
						end
					end
				end
			elseif host.Name == "JumpRing" then
				local gui = host:FindFirstChild("Ring")
				local circle = gui and gui:FindFirstChild("Circle")
				local stroke = circle and circle:FindFirstChildOfClass("UIStroke")
				if stroke and stroke.Transparency < 0.98 then
					local r = circle.Size.X.Scale * host.Size.X / 2
					for k = 1, 16 do
						local a = (k - 0.5) / 16 * 2 * math.pi
						local cf = host.CFrame * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.05, -r)
						table.insert(list, {
							name = "RingSegment",
							shape = "Block",
							cf = cframeArray(cf),
							size = { round(2 * math.pi * r / 16 + 0.05), 0.08, 0.25 },
							color = { 255, 255, 255 },
							transparency = round(stroke.Transparency),
							material = "Neon",
						})
					end
				end
			end
		end
	end
	local landmarks = sim.workspace.Map:FindFirstChild("Landmarks")
	local falls = landmarks and landmarks:FindFirstChild("Waterfall")
	falls = falls and falls:FindFirstChild("Waterfall")
	if falls then
		for _, curtain in falls:GetChildren() do
			local beam = curtain:FindFirstChild("Flow")
			if beam and beam:IsA("Beam") then
				-- (the beam runs down the curtain's local Y, on its front face)
				local top, bottom = beam.Attachment0.Position, beam.Attachment1.Position
				local length = top.Y - bottom.Y
				local stripe = beam.TextureLength
				local offset = (now * beam.TextureSpeed * stripe) % stripe
				local s = -stripe + offset
				while s < length do
					local s0, s1 = math.max(s, 0), math.min(s + stripe * 0.45, length)
					if s1 > s0 then
						local cf = curtain.CFrame * CFrame.new(0, top.Y - (s0 + s1) / 2, top.Z - 0.05)
						table.insert(list, {
							name = "FlowStreak",
							shape = "Block",
							cf = cframeArray(cf),
							size = { round(beam.Width0 * 0.7), round(s1 - s0), 0.1 },
							color = { 250, 253, 255 },
							transparency = 0.35,
							material = "SmoothPlastic",
						})
					end
					s += stripe
				end
			end
		end
	end
	return list
end

-- Views found in the place: the base's flower bed (butterflies) and its boat (foam, bobbing).
do
	-- the flower bed (butterfly anchor) nearest to the base
	local best, bestDist = nil, math.huge
	for _, flower in ambient.Flowers do
		local d = (flower - pivot.Position).Magnitude
		if d < bestDist then
			best, bestDist = flower, d
		end
	end
	if best then
		local p = best
		local away = (Vector3.new(pivot.Position.X, p.Y, pivot.Position.Z) - p)
		away = if away.Magnitude > 1 then away.Unit else Vector3.new(1, 0, 0)
		VIEWS.garden = { eye = p + away * 10 + Vector3.new(0, 9, 0), target = p + Vector3.new(0, 1, 0) }
	end
	local boat = base:FindFirstChild("Boat")
	if boat then
		local p = boat:GetPivot().Position
		local toSpot = (Vector3.new(spot.X, p.Y, spot.Z) - p).Unit
		VIEWS.boat = { eye = p + toSpot * 12 + Vector3.new(0, 15, 0), target = p }
	end
end

local names = {}
for name in string.gmatch(opts.views, "[^,]+") do
	table.insert(names, name)
end

local result = { views = {} }
local camera = sim.workspace.CurrentCamera
for _, name in names do
	local view = VIEWS[name]
	assert(view, `unknown view {name}`)
	local eye, target = view.eye, view.target
	camera.CFrame = CFrame.lookAt(eye, target)
	sim:Advance(WARMUP)
	local forward = (target - eye).Unit

	-- engine numbers over the next second
	engine.Profile = {}
	local moved, writes, peak, updated, culled, frames = 0, 0, 0, 0, 0, 0
	for _ = 1, 60 do
		sim:Step()
		local s = engine.Stats
		moved += s.moved
		writes += s.writes
		peak = math.max(peak, s.moved + s.writes)
		updated += s.updated
		culled += s.culled
		frames += 1
	end
	local profile = {}
	for kind, n in engine.Profile do
		profile[kind] = round(n / frames)
	end
	engine.Profile = nil
	local s = engine.Stats
	local stats = {
		moved = round(moved / frames),
		writes = round(writes / frames),
		peak = peak,
		updated = round(updated / frames),
		culled = round(culled / frames),
		near = s.near,
		mid = s.mid,
		far = s.far,
		budget = engine.Budget,
		byKind = profile,
	}
	print(
		string.format(
			"[ambient_dump] %-9s parts/frame %.1f + props %.1f (peak %d, budget %d), items %.1f updated / %.1f culled, tiers %d/%d/%d",
			name,
			stats.moved,
			stats.writes,
			peak,
			engine.Budget,
			stats.updated,
			stats.culled,
			s.near,
			s.mid,
			s.far
		)
	)

	local parts = sim:Run(function()
		return gather(eye, forward)
	end, player)
	local scene = sim:Run(function()
		local list = {}
		for _, part in parts do
			if part.Transparency < 0.98 then
				table.insert(list, entry(part, true))
			end
		end
		return list
	end, player)
	local byId = {}
	for _, e in scene do
		byId[e.id] = e
	end
	local frameList = {}
	if string.find("," .. opts.swoop .. ",", "," .. name .. ",", 1, true) then
		ambient.SwoopSoon()
		sim:WaitFor(function()
			return ambient.Critters.swooping
		end, 3)
		local dive = ambient.Critters.swoopStart
		sim:WaitFor(function()
			return sim:Time() >= dive - 0.2
		end, 12)
	end
	if string.find("," .. opts.jump .. ",", "," .. name .. ",", 1, true) then
		ambient.JumpSoon()
		sim:WaitFor(function()
			return ambient.Water.jumping
		end, 3)
	end
	local start = sim:Time()
	for f = 1, FRAMES do
		if f > 1 then
			sim:Advance(STEP)
		end
		local now = sim:Time()
		local changed = sim:Run(function()
			local list = {}
			-- the client's own movers come and go (the jumping fish is parked far below the map)
			local frameParts = table.clone(parts)
			local known = {}
			for _, part in parts do
				known[part] = true
			end
			local ownFolder = sim.workspace:FindFirstChild("Ambient (client)")
			if ownFolder then
				for _, d in ownFolder:GetDescendants() do
					if d:IsA("BasePart") and not known[d] and (d.Position - eye).Magnitude < RADIUS then
						table.insert(frameParts, d)
					end
				end
			end
			for _, part in frameParts do
				local e = entry(part, false)
				local old = byId[e.id]
				local differs = old == nil and e.transparency < 0.98
				if old and not differs then
					if old.transparency ~= e.transparency then
						differs = true
					else
						for k = 1, 12 do
							if math.abs(old.cf[k] - e.cf[k]) > 1e-3 then
								differs = true
								break
							end
						end
					end
				end
				if differs then
					if old and old.surfaces then
						e.surfaces = old.surfaces
					end
					table.insert(list, e)
				end
			end
			for _, fx in fxEntries(now) do
				table.insert(list, fx)
			end
			return list
		end, player)
		table.insert(frameList, { t = round(now - start), parts = changed })
	end
	print(`[ambient_dump] {name}: {#scene} parts in view, {#frameList} frames`)
	table.insert(result.views, {
		name = name,
		eye = vec(eye),
		target = vec(target),
		fov = 70,
		stats = stats,
		scene = scene,
		frames = frameList,
	})
end

-- The place's look (like export_parts.luau): grading, water, atmosphere.
local lighting = sim.game:GetService("Lighting")
local cc = lighting:FindFirstChildOfClass("ColorCorrectionEffect")
if cc and cc.Enabled then
	result.grade = {
		saturation = round(cc.Saturation),
		contrast = round(cc.Contrast),
		brightness = round(cc.Brightness),
		tint = colorArray(cc.TintColor),
	}
end
local terrain = sim.workspace:FindFirstChildOfClass("Terrain")
if terrain then
	result.water = { color = colorArray(terrain.WaterColor), transparency = round(terrain.WaterTransparency) }
end
local atm = lighting:FindFirstChildOfClass("Atmosphere")
if atm then
	result.atmosphere = {
		density = round(atm.Density),
		offset = round(atm.Offset),
		haze = round(atm.Haze),
		color = colorArray(atm.Color),
		decay = colorArray(atm.Decay),
	}
end
result.summary = ambient.Summary
fs.writeFile(out, serde.encode("json", result))
print(`[ambient_dump] wrote {out}`)
local errors = sim:FormatErrors()
if errors ~= "" then
	print(errors)
	process.exit(2)
end
