--[[
	world_capture.luau — records the client's world FX in RbxSim over time and projects them
	into the GUI preview's pier frame, so gui_render.py can draw the world UNDER the HUD
	(tools/preview/gui_dump.luau, scenarios with `world = true`; see tools/preview/README.md,
	"World FX in the previews").

	What is captured (every 60 fps step of the capture window, drawn at the dumped frames):
	  • Workspace.FishingFx (FishingFxController's folder) — everything in it — and, in every
	    character, the HeldFish model and any ParticleEmitter / Trail / Beam / BillboardGui /
	    PointLight (character body parts themselves are not drawn: the backdrop has a stand-in);
	  • fish models (a Model with a Title attribute or named HeldFish / Leap / Dive): drawn as the
	    fish sprite (docs/gear) over the model's projected box, length and nose direction;
	    hidden when every part is invisible (LocalTransparencyModifier — the leap handoff);
	  • BaseParts: Block (visible faces, lit), Ball (disc), Cylinder (hull of the end circles),
	    with Color, Transparency x LocalTransparencyModifier, Neon (unlit + glow); parts with
	    Transparency 1 are carriers (their SurfaceGui, emitters and trails still draw);
	  • SurfaceGui on a part face: its GUI laid out at the canvas size (PixelsPerStud x face, or
	    CanvasSize), warped onto the projected face; back faces culled;
	  • BillboardGui (Adornee / parent part / attachment): placed at the projected point plus
	    StudsOffsetWorldSpace and the camera-relative StudsOffset, sized "studs x px-per-stud +
	    px" at its depth, MaxDistance applied, its GUI laid out at that size;
	  • Beam: a camera-facing ribbon along the Bezier (CurveSize0/1 along the attachments'
	    WorldAxis), Width0 -> Width1, Color / Transparency along it;
	  • Trail: the ribbon between its two attachments' positions over the last Lifetime
	    seconds, Color / Transparency / WidthScale by age;
	  • ParticleEmitter: simulated here — continuous Rate while Enabled and every Emit(n)
	    (installHooks() adds Emit to RbxSim, which has none): spawn in the parent part's box (or
	    at the attachment), EmissionDirection + SpreadAngle, Speed, Lifetime, Acceleration, Drag
	    (speed halves every 1/Drag s), LockedToPart; drawn as dots sized by Size / coloured by
	    Color / Transparency over the particle's life (deterministic random);
	  • PointLight: a faint glow of its Colour.
	Not captured: Highlights, Decals/Textures, meshes (drawn as their box), sounds, camera shake.

	Camera = the GUI backdrop's (gui/backdrop.py): the Roblox default third-person camera,
	12.5 studs from the focus, 18 deg down, vertical FOV 70, focus 4.6 studs above the top of
	the player's FishingSpot, looking along the base's LookVector, plus the local Humanoid's
	CameraOffset (in the character's frame). Coordinates in the dump are screen px of the
	device (the same as the HUD objects); the camera itself is written in the spot frame
	(right, up, forward) so the backdrop renders base 1's pier with the very same camera.
	The sim's character is lifted so its head matches the stand-in's (see Capture.HEAD) and the
	rod is moved so its TipAttachment sits at the stand-in's rod tip (Capture.ROD_TIP) — then
	the fishing line, the cast and the held fish line up with the drawn avatar. The client's
	Workspace.CurrentCamera is put on this camera every step too (observe), so the controllers'
	Camera:WorldToScreenPoint maths match the drawing.

	API (used by gui_dump.luau):
	  Capture.installHooks()                   before Sim.new: ParticleEmitter:Emit recorder
	  Capture.new(opts) -> capture             opts = { sim, player, W, H, spot (BasePart), look
	                                           (Vector3), dumpTree (function), fishByTitle }
	  capture:pose()                           puts the character / rod where the backdrop has them
	  capture:step(dt)                         call after every sim step of the capture window
	  capture:frame() -> { cam, items, marks } the world at the current time (JSON-ready)
	  capture:camera() -> { eye, focus, fov }  the base camera (no offset), spot frame
	  capture:begin()                          time 0 of the scenario (after `run`)
	  capture:observe()                        presence tracking during `run` (every step)
	  capture:eventList() -> { { name, kind = "appear" | "disappear" | "signal", t } }
	                                           what appeared / vanished when (scenario time)
]]

local roblox = require("@lune/roblox")
local SimMembers = require("../../sim/members")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local Capture = {}
Capture.__index = Capture

-- The backdrop camera (gui/backdrop.py CAM_*): keep in sync.
Capture.CAMERA = { distance = 12.5, pitch = 18, fov = 70, focusHeight = 4.6 }
-- The stand-in avatar (gui/backdrop.py avatar_parts), spot frame (right, up, forward) from the
-- spot's top: head centre and the tip of the raised rod.
Capture.HEAD = Vector3.new(0, 4.62, 0)
Capture.ROD_TIP = Vector3.new(1.5, 7.995, 7.868)

local MAX_PARTICLES = 400 -- alive per emitter
local MAX_EMIT = 200 -- per Emit() call
-- FX that get an x-ray box (besides fish models): the pillar, the halo, the nameplate.
local MARK_PREFIXES = { "PillarCore", "PillarBeam", "Halo", "Pop", "Nameplate" }
local FISH_NAMES = { HeldFish = true, Leap = true, Dive = true }
local LIGHT = Vector3.new(0.35, 1, -0.25).Unit

--------------------------------------------------------------------------------
-- Hooks
--------------------------------------------------------------------------------

local emitLog: { any } = {}

-- RbxSim has no ParticleEmitter:Emit (FishingFxController pcalls it); record the calls.
function Capture.installHooks()
	SimMembers.define("ParticleEmitter", {
		Emit = SimMembers.method(function(sim, real, count)
			local n = tonumber(count) or 16
			table.insert(emitLog, { sim = sim, real = real, count = math.clamp(math.floor(n), 0, MAX_EMIT) })
		end),
	})
end

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function get(inst: any, key: string, default: any?): any
	local ok, v = pcall(function()
		return inst[key]
	end)
	if ok and v ~= nil then
		return v
	end
	return default
end

local function r1(v: number): number
	if v ~= v or v == math.huge or v == -math.huge then
		return 0
	end
	return math.round(v * 10) / 10
end

local function rgb(c: any): { number }
	return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) }
end

local function seqAt(seq: any, t: number): number
	if typeof(seq) == "number" then
		return seq
	end
	local kps = seq.Keypoints
	if #kps == 0 then
		return 0
	end
	if t <= kps[1].Time then
		return kps[1].Value
	end
	for i = 2, #kps do
		local a, b = kps[i - 1], kps[i]
		if t <= b.Time then
			local span = b.Time - a.Time
			local u = if span > 0 then (t - a.Time) / span else 0
			return a.Value + (b.Value - a.Value) * u
		end
	end
	return kps[#kps].Value
end

local function colorAt(seq: any, t: number): any
	if typeof(seq) == "Color3" then
		return seq
	end
	local kps = seq.Keypoints
	if t <= kps[1].Time then
		return kps[1].Value
	end
	for i = 2, #kps do
		local a, b = kps[i - 1], kps[i]
		if t <= b.Time then
			local span = b.Time - a.Time
			local u = if span > 0 then (t - a.Time) / span else 0
			return a.Value:Lerp(b.Value, u)
		end
	end
	return kps[#kps].Value
end

local function rangeRandom(range: any, rand: () -> number): number
	if typeof(range) == "NumberRange" then
		return range.Min + (range.Max - range.Min) * rand()
	end
	return tonumber(range) or 0
end

local function enumNameOf(v: any, default: string): string
	if typeof(v) == "EnumItem" then
		return v.Name
	end
	return default
end

local function startsWithAny(name: string, prefixes: { string }): boolean
	for _, p in prefixes do
		if string.sub(name, 1, #p) == p then
			return true
		end
	end
	return false
end

-- Convex hull (monotone chain) of 2D points { {x, y} }.
local function hull(points: { { number } }): { { number } }
	table.sort(points, function(a, b)
		return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
	end)
	local function cross(o, a, b)
		return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
	end
	local lower, upper = {}, {}
	for _, p in points do
		while #lower >= 2 and cross(lower[#lower - 1], lower[#lower], p) <= 0 do
			table.remove(lower)
		end
		table.insert(lower, p)
	end
	for i = #points, 1, -1 do
		local p = points[i]
		while #upper >= 2 and cross(upper[#upper - 1], upper[#upper], p) <= 0 do
			table.remove(upper)
		end
		table.insert(upper, p)
	end
	table.remove(lower)
	table.remove(upper)
	for _, p in upper do
		table.insert(lower, p)
	end
	return lower
end

-- World CFrame of what a BillboardGui / emitter / trail hangs on.
local function anchorCFrame(inst: any): any?
	if inst == nil then
		return nil
	end
	if inst:IsA("Attachment") then
		return get(inst, "WorldCFrame", nil)
	elseif inst:IsA("BasePart") then
		return inst.CFrame
	elseif inst:IsA("Model") then
		local ok, pivot = pcall(function()
			return inst:GetPivot()
		end)
		return if ok then pivot else nil
	end
	return nil
end

local function effectiveTransparency(part: any): number
	local t = get(part, "Transparency", 0)
	local ltm = get(part, "LocalTransparencyModifier", 0)
	return 1 - (1 - t) * (1 - ltm)
end

--------------------------------------------------------------------------------
-- Capture
--------------------------------------------------------------------------------

function Capture.new(opts: any): any
	local spot = opts.spot
	local look = Vector3.new(opts.look.X, 0, opts.look.Z).Unit
	local self = setmetatable({
		sim = opts.sim,
		player = opts.player,
		W = opts.W,
		H = opts.H,
		dumpTree = opts.dumpTree,
		fishByTitle = opts.fishByTitle or {},
		origin = spot.Position + Vector3.new(0, spot.Size.Y / 2, 0),
		fwd = look,
		up = Vector3.new(0, 1, 0),
		right = look:Cross(Vector3.new(0, 1, 0)).Unit,
		emitters = {}, -- real emitter -> { acc, particles }
		trails = {}, -- trail -> { samples }
		paths = {}, -- fish model -> { screen centres }
		present = {}, -- name -> true (top-level FX and HeldFish)
		events = {},
		seed = 1,
		logIndex = #emitLog,
		time = 0,
		t0 = 0,
	}, Capture)
	self:connectSignals()
	return self
end

function Capture:random(): number
	-- deterministic LCG (no global math.random state is touched)
	self.seed = (self.seed * 1103515245 + 12345) % 2147483648
	return self.seed / 2147483648
end

function Capture:toWorld(v: any): any
	return self.origin + self.right * v.X + self.up * v.Y + self.fwd * v.Z
end

function Capture:toLocal(p: any): any
	local d = p - self.origin
	return Vector3.new(d:Dot(self.right), d:Dot(self.up), d:Dot(self.fwd))
end

-- The sim's character where the backdrop's stand-in is: head at Capture.HEAD, facing `look`;
-- the rod's TipAttachment at Capture.ROD_TIP.
function Capture:pose()
	local character = self.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	if not root or not head then
		return
	end
	local headWorld = self:toWorld(Capture.HEAD)
	local rootPos = root.Position + (headWorld - head.Position)
	self.sim:Teleport(self.player, CFrame.lookAt(rootPos, rootPos + self.fwd))
	for _, tool in character:GetChildren() do
		if tool:IsA("Tool") then
			local handle = tool:FindFirstChild("Handle")
			local tip = handle and handle:FindFirstChild("TipAttachment", true)
			if handle and tip then
				local delta = self:toWorld(Capture.ROD_TIP) - tip.WorldPosition
				for _, d in tool:GetDescendants() do
					if d:IsA("BasePart") then
						d.CFrame = d.CFrame + delta
					end
				end
			end
		end
	end
end

function Capture:connectSignals()
	-- FishingFxController.OwnFishLanded (UI v2, WFX-02), if the controller has it.
	local ok, fx = pcall(function()
		local scripts = self.player:FindFirstChildOfClass("PlayerScripts")
		local module = scripts and self.sim:Find("Controllers.FishingFxController", scripts)
		return module and self.sim:Require(module, self.player)
	end)
	if not ok or type(fx) ~= "table" then
		return
	end
	local signal = fx.OwnFishLanded
	local event = if typeof(signal) == "Instance" and signal:IsA("BindableEvent") then signal.Event else signal
	if event and (typeof(event) == "RBXScriptSignal" or (type(event) == "table" and event.Connect)) then
		pcall(function()
			event:Connect(function()
				table.insert(self.events, { name = "OwnFishLanded", kind = "signal", at = self.sim:Time() })
			end)
		end)
	end
end

-- Camera of the current frame: { eye, focus, fov } in the spot frame, and world vectors.
function Capture:cameraNow(): any
	local cam = Capture.CAMERA
	local offset = Vector3.zero
	local character = self.player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and root then
		local ok, value = pcall(function()
			return humanoid.CameraOffset
		end)
		if ok and typeof(value) == "Vector3" then
			offset = self:toLocal(self.origin + root.CFrame:VectorToWorldSpace(value))
		end
	end
	local p = math.rad(cam.pitch)
	local focus = Vector3.new(0, cam.focusHeight, 0) + offset
	local eye = focus + Vector3.new(0, cam.distance * math.sin(p), -cam.distance * math.cos(p))
	local eyeW, focusW = self:toWorld(eye), self:toWorld(focus)
	local f = (focusW - eyeW).Unit
	local r = f:Cross(Vector3.new(0, 1, 0)).Unit
	local u = r:Cross(f)
	return {
		eye = eye,
		focus = focus,
		offset = offset,
		eyeW = eyeW,
		f = f,
		r = r,
		u = u,
		fp = (self.H / 2) / math.tan(math.rad(cam.fov) / 2),
	}
end

function Capture:camera(): any
	local cam = Capture.CAMERA
	local p = math.rad(cam.pitch)
	local focus = Vector3.new(0, cam.focusHeight, 0)
	local eye = focus + Vector3.new(0, cam.distance * math.sin(p), -cam.distance * math.cos(p))
	return { eye = { eye.X, eye.Y, eye.Z }, focus = { focus.X, focus.Y, focus.Z }, fov = cam.fov }
end

-- (x, y, depth) of a world point in screen px; depth <= 0 = behind the camera.
local function project(cam: any, W: number, H: number, p: any): (number, number, number)
	local rel = p - cam.eyeW
	local z = rel:Dot(cam.f)
	if z <= 0.05 then
		return 0, 0, z
	end
	return W / 2 + cam.fp * rel:Dot(cam.r) / z, H / 2 - cam.fp * rel:Dot(cam.u) / z, z
end

--------------------------------------------------------------------------------
-- What to look at
--------------------------------------------------------------------------------

-- This player's Workspace.FishingFx: every client of the sim makes its own (RbxSim shares one
-- DataModel), and a folder of a client that has left may still be there.
function Capture:fxFolder(): any?
	local sim = self.sim
	local ctx = sim:_ctxFor(self.player)
	local fallback = nil
	for _, c in sim.workspace:GetChildren() do
		if c.Name == "FishingFx" then
			local real = sim:Unwrap(c)
			if sim.proxy.createdBy[real] == ctx then
				return c
			end
			fallback = c
		end
	end
	return fallback
end

local function isFishModel(inst: any): boolean
	return inst:IsA("Model") and (FISH_NAMES[inst.Name] == true or inst:GetAttribute("Title") ~= nil)
end

-- { inst, fish = model?, character = bool } for every instance to consider.
function Capture:scan(): { any }
	local out = {}
	local folder = self:fxFolder()
	local function walk(inst: any, fish: any?, inCharacter: boolean)
		for _, c in inst:GetChildren() do
			local f = fish
			if not f and isFishModel(c) then
				f = c
				table.insert(out, { inst = c, fish = c, top = true })
			end
			if inCharacter and not f then
				if not c:IsA("BasePart") then
					table.insert(out, { inst = c, character = true })
				end
			else
				table.insert(out, { inst = c, fish = f })
			end
			walk(c, f, inCharacter)
		end
	end
	if folder then
		walk(folder, nil, false)
	end
	for _, plr in self.sim:GetPlayers() do
		local character = plr.Character
		if character then
			walk(character, nil, true)
		end
	end
	return out
end

--------------------------------------------------------------------------------
-- Stepping: trails, particles, events
--------------------------------------------------------------------------------

function Capture:spawnParticles(emitter: any, count: number)
	local state = self.emitters[emitter]
	if not state then
		state = { acc = 0, particles = {} }
		self.emitters[emitter] = state
	end
	local parent = emitter.Parent
	local cf = anchorCFrame(parent)
	if not cf then
		return
	end
	local size = if parent:IsA("BasePart") then parent.Size else Vector3.zero
	local dirName = enumNameOf(get(emitter, "EmissionDirection", nil), "Top")
	local dirs = {
		Top = Vector3.new(0, 1, 0),
		Bottom = Vector3.new(0, -1, 0),
		Front = Vector3.new(0, 0, -1),
		Back = Vector3.new(0, 0, 1),
		Right = Vector3.new(1, 0, 0),
		Left = Vector3.new(-1, 0, 0),
	}
	local localDir = dirs[dirName] or dirs.Top
	local spread = get(emitter, "SpreadAngle", roblox.Vector2.zero)
	local locked = get(emitter, "LockedToPart", false)
	local snapshot = {
		size = get(emitter, "Size", 1),
		transparency = get(emitter, "Transparency", 0),
		color = get(emitter, "Color", roblox.Color3.new(1, 1, 1)),
		accel = get(emitter, "Acceleration", Vector3.zero),
		drag = get(emitter, "Drag", 0),
		emission = get(emitter, "LightEmission", 0),
	}
	for _ = 1, count do
		if #state.particles >= MAX_PARTICLES then
			table.remove(state.particles, 1)
		end
		local rand = function()
			return self:random()
		end
		local offset = Vector3.new((rand() - 0.5) * size.X, (rand() - 0.5) * size.Y, (rand() - 0.5) * size.Z)
		local ax = math.rad((rand() * 2 - 1) * spread.X)
		local ay = math.rad((rand() * 2 - 1) * spread.Y)
		-- spread about the two axes perpendicular to the emission direction (local frame)
		local d = localDir
		local p1 = if math.abs(d.Y) < 0.9
			then d:Cross(Vector3.new(0, 1, 0)).Unit
			else d:Cross(Vector3.new(1, 0, 0)).Unit
		local p2 = d:Cross(p1)
		local dir = (d * math.cos(ax) + p1 * math.sin(ax))
		dir = (dir * math.cos(ay) + p2 * math.sin(ay)).Unit
		local speed = rangeRandom(get(emitter, "Speed", 5), rand)
		local life = math.max(rangeRandom(get(emitter, "Lifetime", 1), rand), 0.05)
		local particle = {
			t0 = self.time,
			life = life,
			snap = snapshot,
		}
		if locked then
			particle.parent = parent
			particle.p0 = offset
			particle.v0 = dir * speed
			particle.locked = true
		else
			particle.p0 = cf * offset
			particle.v0 = cf:VectorToWorldSpace(dir) * speed
		end
		table.insert(state.particles, particle)
	end
end

-- Appearances / disappearances of the top-level FishingFx children and of HeldFish, at the
-- sim's time (client context). Runs on every step from the capture's creation on. It also puts
-- the client's camera where the backdrop's camera is (with the CameraOffset), so the
-- controllers' own screen maths (Camera:WorldToScreenPoint: where the catch card is born, what
-- the bobber is under) agree with what is drawn.
function Capture:_observe()
	local cam = self:cameraNow()
	local camera = self.sim.workspace.CurrentCamera
	if camera then
		camera.CFrame = CFrame.lookAt(cam.eyeW, cam.eyeW + cam.f)
	end
	local now = {}
	local folder = self:fxFolder()
	if folder then
		for _, c in folder:GetChildren() do
			now[c.Name] = true
		end
	end
	for _, plr in self.sim:GetPlayers() do
		local held = plr.Character and plr.Character:FindFirstChild("HeldFish")
		if held then
			now.HeldFish = true
		end
	end
	local t = self.sim:Time()
	for name in now do
		if not self.present[name] then
			table.insert(self.events, { name = name, kind = "appear", at = t })
		end
	end
	for name in self.present do
		if not now[name] then
			table.insert(self.events, { name = name, kind = "disappear", at = t })
		end
	end
	self.present = now
end

-- The events in scenario time (0 = begin()), from 1 s before time 0 on.
function Capture:eventList(): { any }
	local out = {}
	for _, e in self.events do
		local t = e.at - self.t0
		if t >= -1 then
			table.insert(out, { name = e.name, kind = e.kind, t = math.round(t * 1000) / 1000 })
		end
	end
	return out
end

function Capture:_step(dt: number)
	self.time += dt
	local scan = self:scan()
	self:_observe()

	for _, entry in scan do
		local inst = entry.inst
		if inst:IsA("ParticleEmitter") then
			if get(inst, "Enabled", true) then
				local rate = get(inst, "Rate", 0)
				local state = self.emitters[inst]
				if not state then
					state = { acc = 0, particles = {} }
					self.emitters[inst] = state
				end
				state.acc += rate * get(inst, "TimeScale", 1) * dt
				local n = math.floor(state.acc)
				if n > 0 then
					state.acc -= n
					self:spawnParticles(inst, math.min(n, MAX_EMIT))
				end
			end
		elseif inst:IsA("Trail") then
			local a0, a1 = get(inst, "Attachment0", nil), get(inst, "Attachment1", nil)
			local hist = self.trails[inst]
			if not hist then
				hist = { samples = {} }
				self.trails[inst] = hist
			end
			if get(inst, "Enabled", true) and a0 and a1 and a0.Parent and a1.Parent then
				table.insert(hist.samples, { t = self.time, a = a0.WorldPosition, b = a1.WorldPosition })
			end
			local life = get(inst, "Lifetime", 2)
			while #hist.samples > 0 and self.time - hist.samples[1].t > life do
				table.remove(hist.samples, 1)
			end
		end
	end
	-- Emit() calls since the last step
	for i = self.logIndex + 1, #emitLog do
		local e = emitLog[i]
		if e.sim == self.sim or e.sim == nil then
			local proxy = self.sim:Wrap(e.real)
			self:spawnParticles(proxy, e.count)
		end
	end
	self.logIndex = #emitLog
	-- drop dead particles and forgotten instances
	for emitter, state in self.emitters do
		local alive = {}
		for _, p in state.particles do
			if self.time - p.t0 <= p.life then
				table.insert(alive, p)
			end
		end
		state.particles = alive
		if #alive == 0 and emitter.Parent == nil then
			self.emitters[emitter] = nil
		end
	end
	for trail, hist in self.trails do
		if trail.Parent == nil and #hist.samples == 0 then
			self.trails[trail] = nil
		end
	end
	-- fish paths (screen centres, for the x-ray arc)
	local cam = self:cameraNow()
	for _, entry in scan do
		if entry.top and entry.fish then
			local ok, box = pcall(function()
				return entry.fish:GetBoundingBox()
			end)
			if ok then
				local x, y, z = project(cam, self.W, self.H, box.Position)
				if z > 0 then
					local path = self.paths[entry.fish]
					if not path then
						path = {}
						self.paths[entry.fish] = path
					end
					table.insert(path, { r1(x), r1(y) })
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Frame: projected items
--------------------------------------------------------------------------------

local BOX_CORNERS = {
	Vector3.new(-1, -1, -1),
	Vector3.new(1, -1, -1),
	Vector3.new(1, 1, -1),
	Vector3.new(-1, 1, -1),
	Vector3.new(-1, -1, 1),
	Vector3.new(1, -1, 1),
	Vector3.new(1, 1, 1),
	Vector3.new(-1, 1, 1),
}
local BOX_FACES = {
	{ n = Vector3.new(1, 0, 0), c = { 2, 6, 7, 3 } },
	{ n = Vector3.new(-1, 0, 0), c = { 1, 4, 8, 5 } },
	{ n = Vector3.new(0, 1, 0), c = { 4, 3, 7, 8 } },
	{ n = Vector3.new(0, -1, 0), c = { 1, 5, 6, 2 } },
	{ n = Vector3.new(0, 0, 1), c = { 5, 8, 7, 6 } },
	{ n = Vector3.new(0, 0, -1), c = { 1, 2, 3, 4 } },
}
local NEAR = 0.1

-- A world polygon clipped to the camera's near plane (depth >= NEAR) and projected:
-- { {x, y} } (fewer than 3 points = nothing in front of the camera).
local function clipProject(cam: any, W: number, H: number, poly: { any }): { { number } }
	local function depth(p: any): number
		return (p - cam.eyeW):Dot(cam.f)
	end
	local kept = {}
	local n = #poly
	for i = 1, n do
		local a, b = poly[i], poly[i % n + 1]
		local da, db = depth(a), depth(b)
		if da >= NEAR then
			table.insert(kept, a)
		end
		if (da >= NEAR) ~= (db >= NEAR) then
			local t = (NEAR - da) / (db - da)
			table.insert(kept, a + (b - a) * t)
		end
	end
	local out = {}
	for _, p in kept do
		local x, y = project(cam, W, H, p)
		table.insert(out, { r1(x), r1(y) })
	end
	return out
end

local function boxCorner(cf: any, size: any, i: number): any
	local c = BOX_CORNERS[i]
	return cf * Vector3.new(c.X * size.X / 2, c.Y * size.Y / 2, c.Z * size.Z / 2)
end

-- Screen AABB of a box (clipped to the near plane) and its centre depth.
function Capture:screenBox(cam: any, cf: any, size: any): ({ number }?, number)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, face in BOX_FACES do
		local poly = {}
		for _, i in face.c do
			table.insert(poly, boxCorner(cf, size, i))
		end
		for _, p in clipProject(cam, self.W, self.H, poly) do
			x0, y0, x1, y1 = math.min(x0, p[1]), math.min(y0, p[2]), math.max(x1, p[1]), math.max(y1, p[2])
		end
	end
	if x0 == math.huge then
		return nil, 0
	end
	local _, _, depth = project(cam, self.W, self.H, cf.Position)
	return { r1(x0), r1(y0), r1(x1), r1(y1) }, math.max(depth, NEAR)
end

function Capture:partItems(cam: any, part: any, items: { any })
	local t = effectiveTransparency(part)
	if t >= 0.98 then
		return
	end
	local color = part.Color
	local neon = get(part, "Material", nil) == Enum.Material.Neon
	local shape = if part:IsA("Part") then enumNameOf(get(part, "Shape", nil), "Block") else "Block"
	local cf, size = part.CFrame, part.Size
	local alpha = r1((1 - t) * 100) / 100
	local _, _, depth = project(cam, self.W, self.H, cf.Position)
	depth = math.max(depth, NEAR)
	local near = math.max(depth - size.Magnitude / 2, NEAR)
	local function shaded(n: any): { number }
		local k = if neon then 1.15 else 0.62 + 0.38 * math.max(0, n:Dot(LIGHT))
		return {
			math.min(255, math.round(color.R * 255 * k)),
			math.min(255, math.round(color.G * 255 * k)),
			math.min(255, math.round(color.B * 255 * k)),
		}
	end
	if shape == "Ball" then
		local x, y, z = project(cam, self.W, self.H, cf.Position)
		if z <= NEAR then
			return
		end
		local r = math.min(size.X, size.Y, size.Z) / 2 * cam.fp / z
		table.insert(items, {
			k = "circle",
			x = r1(x),
			y = r1(y),
			r = r1(r),
			c = shaded(Vector3.new(0, 1, 0)),
			a = alpha,
			neon = neon,
			d = depth,
			dn = near,
		})
		return
	end
	if shape == "Cylinder" then
		-- the hull of the clipped side quads and caps (12-gon prism along the part's X axis)
		local axis = cf.XVector
		local radius = math.min(size.Y, size.Z) / 2
		local rings = {}
		for k, sx in { -1, 1 } do
			local centre = cf.Position + axis * (sx * size.X / 2)
			rings[k] = {}
			for i = 0, 11 do
				local a = i / 12 * math.pi * 2
				table.insert(
					rings[k],
					centre + cf.YVector * (math.cos(a) * radius) + cf.ZVector * (math.sin(a) * radius)
				)
			end
		end
		local pts = {}
		local function add(poly: { any })
			for _, p in clipProject(cam, self.W, self.H, poly) do
				table.insert(pts, p)
			end
		end
		for i = 1, 12 do
			local j = i % 12 + 1
			add({ rings[1][i], rings[1][j], rings[2][j], rings[2][i] })
		end
		add(rings[1])
		add(rings[2])
		if #pts < 3 then
			return
		end
		table.insert(items, {
			k = "poly",
			pts = hull(pts),
			c = shaded(Vector3.new(0, 1, 0)),
			a = alpha,
			neon = neon,
			d = depth,
			dn = near,
		})
		return
	end
	-- Block (and anything else as its box): the faces turned to the camera.
	for _, face in BOX_FACES do
		local nw = cf:VectorToWorldSpace(face.n)
		local centre = cf.Position + nw * math.abs(face.n:Dot(size)) / 2
		if (cam.eyeW - centre):Dot(nw) > 0 then
			local poly = {}
			for _, i in face.c do
				table.insert(poly, boxCorner(cf, size, i))
			end
			local pts = clipProject(cam, self.W, self.H, poly)
			if #pts >= 3 then
				table.insert(items, {
					k = "poly",
					pts = pts,
					c = shaded(nw),
					a = alpha,
					neon = neon,
					d = depth,
					dn = near,
				})
			end
		end
	end
end

-- Face corners (TL, TR, BR, BL of the canvas) in the part's local space, and the normal.
local FACES = {
	Front = { n = Vector3.new(0, 0, -1), c = { { 1, 1, -1 }, { -1, 1, -1 }, { -1, -1, -1 }, { 1, -1, -1 } } },
	Back = { n = Vector3.new(0, 0, 1), c = { { -1, 1, 1 }, { 1, 1, 1 }, { 1, -1, 1 }, { -1, -1, 1 } } },
	Right = { n = Vector3.new(1, 0, 0), c = { { 1, 1, 1 }, { 1, 1, -1 }, { 1, -1, -1 }, { 1, -1, 1 } } },
	Left = { n = Vector3.new(-1, 0, 0), c = { { -1, 1, -1 }, { -1, 1, 1 }, { -1, -1, 1 }, { -1, -1, -1 } } },
	Top = { n = Vector3.new(0, 1, 0), c = { { -1, 1, -1 }, { 1, 1, -1 }, { 1, 1, 1 }, { -1, 1, 1 } } },
	Bottom = { n = Vector3.new(0, -1, 0), c = { { 1, -1, -1 }, { -1, -1, -1 }, { -1, -1, 1 }, { 1, -1, 1 } } },
}

function Capture:surfaceItem(cam: any, gui: any, items: { any })
	if not get(gui, "Enabled", true) then
		return
	end
	local part = get(gui, "Adornee", nil) or gui.Parent
	if not part or not part:IsA("BasePart") then
		return
	end
	local face = FACES[enumNameOf(get(gui, "Face", nil), "Front")] or FACES.Front
	local cf, size = part.CFrame, part.Size
	local nw = cf:VectorToWorldSpace(face.n)
	local centre = cf * Vector3.new(face.n.X * size.X / 2, face.n.Y * size.Y / 2, face.n.Z * size.Z / 2)
	if (cam.eyeW - centre):Dot(nw) <= 0 then
		return -- back face
	end
	local quad = {}
	local depth = 0
	local near = math.huge
	for _, c in face.c do
		local p = cf * Vector3.new(c[1] * size.X / 2, c[2] * size.Y / 2, c[3] * size.Z / 2)
		local x, y, z = project(cam, self.W, self.H, p)
		if z <= 0.05 then
			return
		end
		depth += z / 4
		near = math.min(near, z)
		table.insert(quad, { r1(x), r1(y) })
	end
	-- canvas size: face extent in studs x PixelsPerStud, or CanvasSize
	local fw, fh
	if math.abs(face.n.X) > 0 then
		fw, fh = size.Z, size.Y
	elseif math.abs(face.n.Y) > 0 then
		fw, fh = size.X, size.Z
	else
		fw, fh = size.X, size.Y
	end
	local cw, ch
	if enumNameOf(get(gui, "SizingMode", nil), "FixedSize") == "PixelsPerStud" then
		local pps = get(gui, "PixelsPerStud", 50)
		cw, ch = fw * pps, fh * pps
	else
		local canvas = get(gui, "CanvasSize", roblox.Vector2.new(800, 600))
		cw, ch = canvas.X, canvas.Y
	end
	local objects = self.dumpTree(gui, { x = 0, y = 0, w = cw, h = ch }, gui.Parent)
	if #objects == 0 then
		return
	end
	table.insert(items, {
		k = "surface",
		objects = objects,
		size = { r1(cw), r1(ch) },
		quad = quad,
		d = depth,
		dn = near,
		name = gui.Name,
	})
end

function Capture:billboardItem(cam: any, gui: any, items: { any }, marks: { any })
	if not get(gui, "Enabled", true) then
		return
	end
	local anchor = anchorCFrame(get(gui, "Adornee", nil) or gui.Parent)
	if not anchor then
		return
	end
	local so = get(gui, "StudsOffset", Vector3.zero)
	local sow = get(gui, "StudsOffsetWorldSpace", Vector3.zero)
	local pos = anchor.Position + sow + cam.r * so.X + cam.u * so.Y - cam.f * so.Z
	local x, y, z = project(cam, self.W, self.H, pos)
	if z <= 0.05 then
		return
	end
	if (pos - cam.eyeW).Magnitude > get(gui, "MaxDistance", math.huge) then
		return
	end
	local pps = cam.fp / z
	local size = get(gui, "Size", roblox.UDim2.new())
	local w = size.X.Scale * pps + size.X.Offset
	local h = size.Y.Scale * pps + size.Y.Offset
	local offset = get(gui, "SizeOffset", roblox.Vector2.zero)
	x += offset.X * w
	y -= offset.Y * h
	if w < 0.5 or h < 0.5 then
		return
	end
	local rect = { x = x - w / 2, y = y - h / 2, w = w, h = h }
	local objects = self.dumpTree(gui, rect, gui.Parent)
	if #objects == 0 then
		return
	end
	table.insert(items, { k = "gui", objects = objects, d = z, name = gui.Name })
	if startsWithAny(gui.Name, MARK_PREFIXES) then
		table.insert(marks, { name = gui.Name, box = { r1(rect.x), r1(rect.y), r1(rect.x + w), r1(rect.y + h) } })
	end
end

function Capture:beamItem(cam: any, beam: any, items: { any })
	if not get(beam, "Enabled", true) then
		return
	end
	local a0, a1 = get(beam, "Attachment0", nil), get(beam, "Attachment1", nil)
	if not a0 or not a1 or not a0.Parent or not a1.Parent then
		return
	end
	local p0, p3 = a0.WorldPosition, a1.WorldPosition
	local c0, c1 = get(beam, "CurveSize0", 0), get(beam, "CurveSize1", 0)
	local p1 = p0 + a0.WorldAxis * c0
	local p2 = p3 - a1.WorldAxis * c1
	local curved = math.abs(c0) + math.abs(c1) > 1e-3
	local n = if curved then math.clamp(get(beam, "Segments", 10), 2, 20) else 2
	local w0, w1 = get(beam, "Width0", 1), get(beam, "Width1", 1)
	local color, transparency = get(beam, "Color", nil), get(beam, "Transparency", 0)
	local pts, depths = {}, {}
	for i = 0, n do
		local t = i / n
		local u = 1 - t
		local p = p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
		local x, y, z = project(cam, self.W, self.H, p)
		if z <= 0.05 then
			return
		end
		table.insert(pts, { x, y, z, t })
		table.insert(depths, z)
	end
	self:ribbon(cam, pts, function(t: number, z: number)
		local w = (w0 + (w1 - w0) * t) * cam.fp / z
		local c = if color then colorAt(color, t) else roblox.Color3.new(1, 1, 1)
		return w, c, 1 - seqAt(transparency, t)
	end, get(beam, "LightEmission", 0), items, beam.Name)
end

-- Screen ribbon along points { x, y, depth, t } with style(t, depth) -> (width px, Color3, alpha).
function Capture:ribbon(_cam: any, pts: { any }, style: any, emission: number, items: { any }, name: string)
	if #pts < 2 then
		return
	end
	local left, right, colors, alphas, depths = {}, {}, {}, {}, {}
	local depth = 0
	for i, p in pts do
		local q0 = pts[math.max(i - 1, 1)]
		local q1 = pts[math.min(i + 1, #pts)]
		local dx, dy = q1[1] - q0[1], q1[2] - q0[2]
		local len = math.sqrt(dx * dx + dy * dy)
		local nx, ny = 0, 1
		if len > 1e-6 then
			nx, ny = -dy / len, dx / len
		end
		local w, c, a = style(p[4], p[3])
		w = math.max(w, 0.6)
		table.insert(left, { r1(p[1] + nx * w / 2), r1(p[2] + ny * w / 2) })
		table.insert(right, { r1(p[1] - nx * w / 2), r1(p[2] - ny * w / 2) })
		table.insert(colors, rgb(c))
		table.insert(alphas, math.round(math.clamp(a, 0, 1) * 100) / 100)
		depth += p[3] / #pts
		table.insert(depths, r1(p[3]))
	end
	table.insert(
		items,
		{ k = "ribbon", l = left, r = right, c = colors, a = alphas, z = depths, e = emission, d = depth, name = name }
	)
end

function Capture:trailItem(cam: any, trail: any, items: { any })
	local hist = self.trails[trail]
	if not hist or #hist.samples < 2 then
		return
	end
	local life = math.max(get(trail, "Lifetime", 2), 1e-3)
	local color, transparency = get(trail, "Color", nil), get(trail, "Transparency", 0)
	local widthScale = get(trail, "WidthScale", 1)
	local left, right, colors, alphas, depths = {}, {}, {}, {}, {}
	local depth, count = 0, 0
	for i = #hist.samples, 1, -1 do
		local s = hist.samples[i]
		local age = math.clamp((self.time - s.t) / life, 0, 1)
		local mid = (s.a + s.b) / 2
		local k = seqAt(widthScale, age)
		local a = mid + (s.a - mid) * k
		local b = mid + (s.b - mid) * k
		local ax, ay, az = project(cam, self.W, self.H, a)
		local bx, by, bz = project(cam, self.W, self.H, b)
		if az > 0.05 and bz > 0.05 then
			table.insert(left, { r1(ax), r1(ay) })
			table.insert(right, { r1(bx), r1(by) })
			table.insert(colors, rgb(if color then colorAt(color, age) else roblox.Color3.new(1, 1, 1)))
			table.insert(alphas, math.round(math.clamp(1 - seqAt(transparency, age), 0, 1) * 100) / 100)
			depth += (az + bz) / 2
			table.insert(depths, r1(math.min(az, bz)))
			count += 1
		end
	end
	if count < 2 then
		return
	end
	table.insert(items, {
		k = "ribbon",
		l = left,
		r = right,
		c = colors,
		a = alphas,
		z = depths,
		e = get(trail, "LightEmission", 0),
		d = depth / count,
		name = trail.Name,
	})
end

function Capture:particleItem(cam: any, emitter: any, state: any, items: { any })
	if #state.particles == 0 then
		return
	end
	local texture = string.lower(tostring(get(emitter, "Texture", "")))
	local shape = if string.find(texture, "spark")
		then "spark"
		elseif string.find(texture, "smoke") then "soft"
		else "square"
	local dots = {}
	local depth, count = 0, 0
	for _, p in state.particles do
		local age = self.time - p.t0
		local frac = math.clamp(age / p.life, 0, 1)
		local s = p.snap
		local disp
		if s.drag > 0 then
			local k = math.log(2) * s.drag
			disp = p.v0 * ((1 - math.exp(-k * age)) / k)
		else
			disp = p.v0 * age
		end
		local pos = p.p0 + disp + s.accel * (0.5 * age * age)
		if p.locked then
			local cf = anchorCFrame(p.parent)
			if not cf then
				continue
			end
			pos = cf * (p.p0 + disp) + s.accel * (0.5 * age * age)
		end
		local x, y, z = project(cam, self.W, self.H, pos)
		if z > 0.05 then
			local alpha = 1 - seqAt(s.transparency, frac)
			local px = seqAt(s.size, frac) * cam.fp / z
			if alpha > 0.02 and px > 0.2 then
				local c = colorAt(s.color, frac)
				table.insert(dots, {
					r1(x),
					r1(y),
					r1(px),
					math.round(c.R * 255),
					math.round(c.G * 255),
					math.round(c.B * 255),
					math.round(alpha * 100) / 100,
					r1(z),
				})
				depth += z
				count += 1
			end
		end
	end
	if count == 0 then
		return
	end
	table.insert(items, {
		k = "dots",
		p = dots,
		shape = shape,
		e = get(emitter, "LightEmission", 0),
		d = depth / count,
		name = emitter.Name,
	})
end

function Capture:fishItem(cam: any, model: any, items: { any }, marks: { any })
	local ok, box, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok then
		return
	end
	local screen, depth = self:screenBox(cam, box, size)
	if not screen then
		return
	end
	local hidden = true
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and effectiveTransparency(d) < 0.98 then
			hidden = false
			break
		end
	end
	local nose = box.Position + box.XVector * (size.X / 2)
	local tail = box.Position - box.XVector * (size.X / 2)
	local nx, ny = project(cam, self.W, self.H, nose)
	local tx, ty = project(cam, self.W, self.H, tail)
	local cx, cy = project(cam, self.W, self.H, box.Position)
	local title = model:GetAttribute("Title")
	local fish = model:GetAttribute("FishId") or (if typeof(title) == "string" then self.fishByTitle[title] else nil)
	local mark = {
		name = model.Name,
		box = screen,
		path = self.paths[model],
		hidden = hidden,
	}
	table.insert(marks, mark)
	if hidden or not fish then
		return
	end
	table.insert(items, {
		k = "fish",
		fish = fish,
		mutation = model:GetAttribute("Mutation"),
		x = r1(cx),
		y = r1(cy),
		len = r1(math.sqrt((nx - tx) ^ 2 + (ny - ty) ^ 2)),
		ang = r1(math.deg(math.atan2(ny - ty, nx - tx))),
		box = screen,
		d = depth,
		dn = math.max(depth - size.Magnitude / 2, NEAR),
		name = model.Name,
	})
end

function Capture:_frame(): any
	local cam = self:cameraNow()
	local items, marks = {}, {}
	for _, entry in self:scan() do
		local inst = entry.inst
		if entry.top and entry.fish then
			self:fishItem(cam, entry.fish, items, marks)
		elseif inst:IsA("BasePart") then
			if not entry.fish and not entry.character then
				self:partItems(cam, inst, items)
				if inst.Parent and inst.Parent.Name == "FishingFx" and startsWithAny(inst.Name, MARK_PREFIXES) then
					local screen = self:screenBox(cam, inst.CFrame, inst.Size)
					if screen then
						table.insert(marks, { name = inst.Name, box = screen })
					end
				end
			end
		elseif inst:IsA("SurfaceGui") then
			self:surfaceItem(cam, inst, items)
		elseif inst:IsA("BillboardGui") then
			self:billboardItem(cam, inst, items, marks)
		elseif inst:IsA("Beam") then
			self:beamItem(cam, inst, items)
		elseif inst:IsA("Trail") then
			self:trailItem(cam, inst, items)
		elseif inst:IsA("ParticleEmitter") then
			local state = self.emitters[inst]
			if state then
				self:particleItem(cam, inst, state, items)
			end
		elseif inst:IsA("PointLight") and get(inst, "Enabled", true) then
			local anchor = anchorCFrame(inst.Parent)
			if anchor then
				local x, y, z = project(cam, self.W, self.H, anchor.Position)
				if z > 0.05 then
					table.insert(items, {
						k = "glow",
						x = r1(x),
						y = r1(y),
						r = r1(math.min(get(inst, "Range", 8), 16) * cam.fp / z),
						c = rgb(get(inst, "Color", roblox.Color3.new(1, 1, 1))),
						a = math.round(math.clamp(get(inst, "Brightness", 1) * 0.08, 0, 0.3) * 100) / 100,
						d = z,
						name = inst.Name,
					})
				end
			end
		end
	end
	-- particles of emitters that are gone already
	local seen = {}
	for _, entry in self:scan() do
		seen[entry.inst] = true
	end
	for emitter, state in self.emitters do
		if not seen[emitter] then
			self:particleItem(cam, emitter, state, items)
		end
	end
	for _, item in items do
		item.d = r1(item.d)
		if item.dn then
			item.dn = r1(item.dn)
		end
	end
	-- x-ray boxes: only their on-screen part (a pillar reaches far above the frame)
	local shown = {}
	for _, m in marks do
		local b = m.box
		local box = { math.max(b[1], 0), math.max(b[2], 0), math.min(b[3], self.W), math.min(b[4], self.H) }
		if box[3] > box[1] and box[4] > box[2] then
			m.box = box
			table.insert(shown, m)
		end
	end
	return {
		cam = {
			eye = { cam.eye.X, cam.eye.Y, cam.eye.Z },
			focus = { cam.focus.X, cam.focus.Y, cam.focus.Z },
			fov = Capture.CAMERA.fov,
		},
		items = items,
		marks = shown,
	}
end

-- Time 0 of the scenario (right after `run`): the capture clock restarts.
function Capture:begin()
	self.t0 = self.sim:Time()
	self.time = 0
end

-- Presence tracking only (cheap): gui_dump's harness calls it after every step of `run`.
function Capture:observe()
	self.sim:Run(function()
		self:_observe()
	end, self.player)
end

-- Both run in the player's client context: client-local values (LocalTransparencyModifier,
-- Humanoid.CameraOffset set by the client) are read as that client sees them.
function Capture:step(dt: number)
	self.sim:Run(function()
		self:_step(dt)
	end, self.player)
end

function Capture:frame(): any
	return self.sim:Run(function()
		return self:_frame()
	end, self.player)
end

return Capture
