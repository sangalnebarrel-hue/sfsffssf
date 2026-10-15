--!strict
--[[
	AmbientWater — жизнь на воде там, куда игрок смотрит (помощник AmbientController, модуль):

	  • блики солнца: 3 невидимые площадки с искрами (ParticleEmitter) раз в 0,5 с встают на воду
	    лагуны там, куда смотрит камера (лучи через центр и бока экрана, 25–150 studs), не на
	    пирсы и мосты; камера под водой — выключены. ≈ 10 искр одновременно;
	  • рыба выпрыгивает: раз в 5–9 с на воде лагуны 28–90 studs от камеры (±35° от взгляда),
	    не ближе 15 studs к поплавкам: карась или окунь из Assets.Fish (×1,6), дуга 2,5–4 studs
	    вверх и 6–9 вперёд за 0,9 с носом по касательной, хвост бьёт, брызги и круг на выходе и
	    на входе, тихий «плюх» вблизи. Не прыгает, пока у своего игрока клюёт / идёт
	    борьба / рыба над головой (не путать с поклёвкой);
	  • стайки рыб у поверхности: 6 стай по 5 рыб (крупнее и мельче, чем раньше: 1,4–2,4, на
	    глубине 0,8–1,6). 4 кружат по лагуне, 2 ходят перед ближайшим к камере пирсом. Тело
	    виляет, хвост — на шарнире у тела. У чужого и своего поплавка стая уходит глубже;
	  • пена вокруг всего, что качается на воде (лодки, буйки, плоты, садки) и у свай ближайшего
	    пирса: кольцо-овал по корпусу у ватерлинии (SurfaceGui: белая обводка, едва заметная
	    заливка; мачты, верёвки и швартовы не в счёт; корпус — по всем 8 углам деталей, так что
	    и поставленный «на попа» цилиндр-поплавок получает круг). Пул из FOAM_POOL колец
	    раздаётся ближайшим (≤ FOAM_RANGE) раз в 0,5 с; обводка белее, когда корпус внизу качания
	    (в такт Bob): проверка FOAM_HZ (2) раза в секунду, а запись — только когда прозрачность
	    ушла от записанной на FOAM_STEP и больше (не больше 2 записей в секунду на кольцо, заливка
	    не «дышит» — v3 fix F5);
	  • водопад: лучи (Beam) с бегущей вниз текстурой поверх «занавесей» воды (без деталей).
	AmbientWater.Start(engine, folder, map, context)
	AmbientWater.State — для тестов и превью (прыжки, стаи, пена).
	AmbientWater.JumpSoon() — рыба выпрыгнет на ближайшем тике (тесты, превью).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AmbientEngine = require(script.Parent:WaitForChild("AmbientEngine"))
local AmbientWorld = require(script.Parent:WaitForChild("AmbientWorld"))
local MapConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MapConfig"))

type Engine = AmbientEngine.Engine
type Item = AmbientEngine.Item
type Bob = AmbientWorld.Bob

export type Base = { model: Model, spot: Vector3, cf: CFrame, posts: { Vector3 } }
export type Context = {
	bobs: { Bob },
	bases: () -> { Base },
	nearestBase: () -> Base?,
	rng: Random,
}

local WATER = MapConfig.WaterTop
local LAGOON_IN = MapConfig.HubRadius + 6
local LAGOON_OUT = MapConfig.LagoonRadius - 6
local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local SPLASH_SOUND = "rbxasset://sounds/impact_water.mp3"

local GLINT_HOSTS = 3
local GLINT_SIZE = Vector3.new(26, 0.2, 26)
local GLINT_RATE = 4 -- искр в секунду на площадку
local GLINT_NEAR, GLINT_FAR = 25, 150

local JUMP_EVERY = { 5, 9 } -- с
local JUMP_TIME = 0.9
local JUMP_HEIGHT = { 2.5, 4 } -- studs над водой
local JUMP_SPAN = { 6, 9 } -- studs по горизонтали (дуга, не «свечка»)
local JUMP_SPECIES = { "Crucian", "Perch" } -- модели из ReplicatedStorage.Assets.Fish
local JUMP_DIST = { 28, 90 } -- studs от камеры
local JUMP_SCALE = 1.6 -- модель рыбы из Assets — в 1,6 раза крупнее
local JUMP_CONE = math.rad(35)
local BOBBER_CLEAR = 15
local SOUND_RANGE = 70

local SCHOOLS_RING, SCHOOLS_PIER, SCHOOL_SIZE = 4, 2, 5
local FISH_COLORS = {
	Color3.fromRGB(255, 150, 40),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(255, 100, 140),
	Color3.fromRGB(130, 220, 120),
	Color3.fromRGB(190, 120, 255),
}

local FOAM_POOL = 24
local FOAM_RANGE = 110
local FOAM_LIFT = 0.12 -- над водой (выше гребней WaterWaveSize 0,15)
local FOAM_PAD = 1.3 -- кольцо шире корпуса на столько, studs
local FOAM_MIN_HULL = 1.4 -- корпус меньше (поплавки сетей) — без пены, studs
local FOAM_MIN_BOB = 0.1 -- качается слабее (кувшинки) — без пены, studs
local FOAM_POST = 3.4 -- кольцо вокруг сваи, studs
local FOAM_PPS = 12 -- пикселей SurfaceGui на stud
local FOAM_STROKE = 0.35 -- толщина белой обводки, studs
local FOAM_COLOR = Color3.fromRGB(240, 250, 255)
local FOAM_T, FOAM_SWING = 0.38, 0.16 -- прозрачность обводки и её «дыхание»
local FOAM_FILL = 0.84 -- заливка внутри кольца (почти прозрачная, не «дышит»)
local FOAM_HZ = 2 -- «дыхание» пены проверяется столько раз в секунду …
local FOAM_STEP = 0.05 -- … и пишется, только если прозрачность изменилась хотя бы на столько

local AmbientWater = {}
AmbientWater.JumpSoon = function() end -- (до старта — ничего)
AmbientWater.State = {
	jumps = 0,
	jumping = false,
	lastJump = nil :: Vector3?,
	glints = 0, -- сколько площадок бликов включено
	foam = 0, -- сколько колец пены роздано
	foamSpecs = 0, -- лодок / буйков, вокруг которых бывает пена
	waterfallBeams = 0,
	schools = {} :: { Item },
}

local function quietPart(folder: Instance, name: string, size: Vector3, color: Color3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.Color = color
	part.Parent = folder
	return part
end

local function numbers(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2]))
	end
	return NumberSequence.new(keys)
end

-- Вода лагуны (не остров, не берег), не пирс и не мост.
local function lagoonWater(x: number, z: number, bases: { Base }): boolean
	local r = math.sqrt(x * x + z * z)
	if r < LAGOON_IN or r > LAGOON_OUT then
		return false
	end
	local p = Vector3.new(x, WATER, z)
	for _, base in bases do
		local l = base.cf:PointToObjectSpace(p)
		-- пирс: от метки базы (lz = 0) до точки рыбалки и чуть дальше, ±(PierHalfWidth + 4)
		if math.abs(l.X) < MapConfig.PierHalfWidth + 4 and l.Z < 4 and l.Z > -(MapConfig.PierLength + 6) then
			return false
		end
	end
	local theta = math.deg(math.atan2(x, z))
	for _, a in MapConfig.BridgeAngles do
		local diff = math.rad((theta - a + 540) % 360 - 180)
		if math.abs(diff) < math.pi / 2 and math.abs(r * math.sin(diff)) < MapConfig.BridgeWidth / 2 + 5 then
			return false
		end
	end
	return true
end
AmbientWater.LagoonWater = lagoonWater

-- Поплавки на воде (свои и чужие): цели заброса тех, кто рыбачит.
local function bobberTargets(): { Vector3 }
	local list = {}
	for _, player in Players:GetPlayers() do
		local state = player:GetAttribute("FishingState")
		local target = player:GetAttribute("BobberTarget")
		if typeof(state) == "string" and state ~= "Idle" and typeof(target) == "Vector3" then
			table.insert(list, target)
		end
	end
	return list
end

-- У своего игрока сейчас главное — рыба (клюёт, борьба, улов над головой).
local function ownBusy(): boolean
	local player = Players.LocalPlayer
	if not player then
		return false
	end
	local state = player:GetAttribute("FishingState")
	if state == "Bite" or state == "Reeling" then
		return true
	end
	local character = player.Character
	return character ~= nil and character:FindFirstChild("HeldFish") ~= nil
end

-- Точка на воде вдоль луча из камеры через точку экрана (sx, sy ∈ −1…1).
local function rayToWater(engine: Engine, sx: number, sy: number): Vector3?
	local dir = engine.look + engine.right * (sx * engine.tanX / 1.15) + engine.up * (sy * engine.tanY / 1.15)
	if dir.Y >= -0.02 then
		return nil
	end
	local origin = engine.camPos
	local k = (WATER - origin.Y) / dir.Y
	if k <= 0 then
		return nil
	end
	return origin + dir * k
end

--------------------------------------------------------------------------------------------
-- Блики
--------------------------------------------------------------------------------------------

local function startGlints(engine: Engine, folder: Instance, context: Context)
	local hosts: { { part: Part, emitter: ParticleEmitter } } = {}
	for k = 1, GLINT_HOSTS do
		local part = quietPart(folder, "WaterGlints", GLINT_SIZE, Color3.new(1, 1, 1))
		part.Transparency = 1
		local emitter = Instance.new("ParticleEmitter")
		emitter.Name = "Glints"
		emitter.Texture = SPARKLE
		emitter.Shape = Enum.ParticleEmitterShape.Box
		emitter.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		emitter.Rate = GLINT_RATE
		emitter.Lifetime = NumberRange.new(0.25, 0.55)
		emitter.Size = numbers({ { 0, 0 }, { 0.4, 1.1 }, { 1, 0 } })
		emitter.Transparency = numbers({ { 0, 0.1 }, { 1, 0.3 } })
		emitter.LightEmission = 1
		emitter.LightInfluence = 0
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 250, 225))
		emitter.Speed = NumberRange.new(0)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.ZOffset = 0.3
		emitter.Enabled = false
		emitter.Parent = part
		hosts[k] = { part = part, emitter = emitter }
	end
	local SCREEN = { { 0, -0.25 }, { -0.55, -0.45 }, { 0.55, -0.45 } } -- центр и бока, ниже середины
	engine:Every(0.5, function()
		local on = 0
		local bases = context.bases()
		local below = engine.camPos.Y < WATER
		for k, host in hosts do
			local point = if below then nil else rayToWater(engine, SCREEN[k][1], SCREEN[k][2])
			local ok = false
			if point then
				local d = (point - engine.camPos).Magnitude
				ok = d >= GLINT_NEAR and d <= GLINT_FAR and lagoonWater(point.X, point.Z, bases)
			end
			if ok and point then
				host.part.CFrame = CFrame.new(point.X, WATER + 0.15, point.Z)
				on += 1
			end
			if host.emitter.Enabled ~= ok then
				host.emitter.Enabled = ok
			end
		end
		AmbientWater.State.glints = on
	end)
	engine:OnSleep(function()
		for _, host in hosts do
			host.emitter.Enabled = false
		end
		AmbientWater.State.glints = 0
	end)
end

--------------------------------------------------------------------------------------------
-- Выпрыгивающая рыба
--------------------------------------------------------------------------------------------

type JumpRing = { part: Part, frame: Frame, stroke: UIStroke }

local function makeRing(folder: Instance): JumpRing
	local part = quietPart(folder, "JumpRing", Vector3.new(8, 0.05, 8), Color3.new(1, 1, 1))
	part.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Ring"
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.Brightness = 1.3
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.MaxDistance = 200
	gui.Parent = part
	local frame = Instance.new("Frame")
	frame.Name = "Circle"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(0.15, 0.15)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(1, 1, 1)
	stroke.Thickness = 10
	stroke.Transparency = 1
	stroke.Parent = frame
	return { part = part, frame = frame, stroke = stroke }
end

type Jumper = { parts: { BasePart }, offsets: { CFrame }, tail: { boolean }, hinge: CFrame }

-- Рыба для прыжка: копия настоящей модели из Assets.Fish (карась, окунь — нос по +X), иначе
-- простая из блоков. Пока не прыгает — спрятана глубоко под картой (без записи прозрачности).
local function makeJumper(folder: Instance, template: Model?): Jumper
	local parts: { BasePart } = {}
	local offsets: { CFrame } = {}
	local tail: { boolean } = {}
	if template and template.PrimaryPart then
		local model = template:Clone()
		model.Name = "JumpFish"
		model:ScaleTo(JUMP_SCALE) -- (крупнее рыбы в руке: видно с пирса за 30–90 studs)
		local origin = (model.PrimaryPart :: BasePart).CFrame
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
				table.insert(parts, d)
				table.insert(offsets, origin:Inverse() * d.CFrame)
				table.insert(tail, string.sub(d.Name, 1, 4) == "Tail")
			end
		end
		model.Parent = folder
		return {
			parts = parts,
			offsets = offsets,
			tail = tail,
			hinge = CFrame.new(-0.75 * JUMP_SCALE, -0.125 * JUMP_SCALE, 0),
		}
	end
	local color = Color3.fromRGB(255, 170, 60)
	local s = 1.4
	local body = quietPart(folder, "JumpFish", Vector3.new(1.6, 0.8, 0.7) * s, color)
	local fin = quietPart(folder, "JumpFin", Vector3.new(0.6, 0.35, 0.1) * s, color:Lerp(Color3.new(1, 0.4, 0.2), 0.4))
	local tailPart =
		quietPart(folder, "JumpTail", Vector3.new(0.6, 0.7, 0.15) * s, color:Lerp(Color3.new(1, 1, 1), 0.25))
	return {
		parts = { body, fin, tailPart },
		offsets = { CFrame.identity, CFrame.new(-0.1 * s, 0.5 * s, 0), CFrame.new(-1.1 * s, 0, 0) },
		tail = { false, false, true },
		hinge = CFrame.new(-0.8 * s, 0, 0),
	}
end

local PARKED = CFrame.new(0, -200, 0)

local function startJumps(engine: Engine, folder: Instance, context: Context)
	local rng = context.rng
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local fishFolder = assets and assets:FindFirstChild("Fish")
	local jumpers: { Jumper } = {}
	for _, species in JUMP_SPECIES do
		local variants = fishFolder and fishFolder:FindFirstChild(species)
		local template = variants and variants:FindFirstChild("Normal")
		table.insert(jumpers, makeJumper(folder, if template and template:IsA("Model") then template else nil))
	end
	for _, jumper in jumpers do
		for _, part in jumper.parts do
			part.CFrame = PARKED
		end
	end
	local splashHost = quietPart(folder, "JumpSplash", Vector3.new(1, 0.2, 1), Color3.new(1, 1, 1))
	splashHost.Transparency = 1
	splashHost.CFrame = CFrame.new(0, WATER - 30, 0)
	local splash = Instance.new("ParticleEmitter")
	splash.Name = "Splash"
	splash.Texture = SMOKE
	splash.Enabled = false
	splash.Rate = 0
	splash.Lifetime = NumberRange.new(0.35, 0.65)
	splash.Speed = NumberRange.new(7, 12)
	splash.SpreadAngle = Vector2.new(28, 28)
	splash.EmissionDirection = Enum.NormalId.Top
	splash.Acceleration = Vector3.new(0, -34, 0)
	splash.Size = numbers({ { 0, 0.55 }, { 1, 0.15 } })
	splash.Transparency = numbers({ { 0, 0.15 }, { 1, 1 } })
	splash.Color = ColorSequence.new(Color3.new(1, 1, 1))
	splash.LightEmission = 0.3
	splash.Parent = splashHost
	local sound = Instance.new("Sound")
	sound.Name = "Plop"
	sound.SoundId = SPLASH_SOUND
	sound.Volume = 0.12
	sound.RollOffMaxDistance = SOUND_RANGE
	sound.Parent = splashHost
	local rings = { makeRing(folder), makeRing(folder) }

	local function ringAt(index: number, point: Vector3)
		local ring = rings[index]
		local part, frame, stroke = ring.part, ring.frame, ring.stroke
		part.CFrame = CFrame.new(point.X, WATER + 0.3, point.Z)
		frame.Size = UDim2.fromScale(0.15, 0.15)
		stroke.Transparency = 0.2
		stroke.Thickness = 10
		local info = TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(frame, info, { Size = UDim2.fromScale(0.92, 0.92) }):Play()
		TweenService:Create(stroke, info, { Transparency = 1, Thickness = 4 }):Play()
	end

	local function splashAt(point: Vector3, power: number, index: number)
		splashHost.CFrame = CFrame.new(point.X, WATER + 0.1, point.Z)
		pcall(function() -- (в эмуляторе тестов RbxSim у ParticleEmitter нет Emit)
			splash:Emit(math.floor(10 * power))
		end)
		ringAt(index, point)
		if (point - engine.camPos).Magnitude < SOUND_RANGE then
			sound.PlaybackSpeed = rng:NextNumber(1.25, 1.6)
			sound:Play()
		end
	end

	-- Где прыгнуть: вода лагуны впереди камеры, далеко от поплавков.
	local function pickSpot(): (Vector3?, Vector3?)
		local bases = context.bases()
		local targets = bobberTargets()
		local flatLook = Vector3.new(engine.look.X, 0, engine.look.Z)
		if flatLook.Magnitude < 0.2 then
			return nil, nil
		end
		flatLook = flatLook.Unit
		for _ = 1, 8 do
			local yaw = rng:NextNumber(-JUMP_CONE, JUMP_CONE)
			local dist = rng:NextNumber(JUMP_DIST[1], JUMP_DIST[2])
			local dir = CFrame.Angles(0, yaw, 0):VectorToWorldSpace(flatLook)
			local a = engine.camPos + dir * dist
			a = Vector3.new(a.X, WATER, a.Z)
			local clear = lagoonWater(a.X, a.Z, bases)
			for _, target in targets do
				if (Vector3.new(target.X, WATER, target.Z) - a).Magnitude < BOBBER_CLEAR then
					clear = false
				end
			end
			if clear then
				-- прыжок поперёк взгляда (так дугу видно лучше всего)
				local across = Vector3.new(-dir.Z, 0, dir.X) * (if rng:NextNumber() < 0.5 then -1 else 1)
				local span = rng:NextNumber(JUMP_SPAN[1], JUMP_SPAN[2])
				local b = a + across * span
				if lagoonWater(b.X, b.Z, bases) then
					return a, b
				end
			end
		end
		return nil, nil
	end

	local nextJump = os.clock() + rng:NextNumber(2, 4)
	-- (тесты и превью: прыжок на ближайшем тике, по обычным правилам места)
	AmbientWater.JumpSoon = function()
		nextJump = 0
	end
	engine:Every(0.25, function(now: number)
		if now < nextJump or AmbientWater.State.jumping then
			return
		end
		if ownBusy() or engine.camPos.Y < WATER then
			nextJump = now + 2
			return
		end
		local a, b = pickSpot()
		if not a or not b then
			nextJump = now + 1
			return
		end
		nextJump = now + rng:NextNumber(JUMP_EVERY[1], JUMP_EVERY[2])
		local from, to = a :: Vector3, b :: Vector3
		local height = rng:NextNumber(JUMP_HEIGHT[1], JUMP_HEIGHT[2])
		local start = now
		local jumper = jumpers[rng:NextInteger(1, #jumpers)]
		AmbientWater.State.jumping = true
		AmbientWater.State.jumps += 1
		AmbientWater.State.lastJump = from
		splashAt(from, 1, 1)
		local flat = to - from
		local rise = height + 1.2 -- (из-под воды: старт на 0,6 ниже поверхности)
		local hinge, inverse = jumper.hinge, jumper.hinge:Inverse()
		engine:OnFrame(function(t: number): boolean
			local u = (t - start) / JUMP_TIME
			if u >= 1 then
				for _, part in jumper.parts do
					engine:Push(part, PARKED)
				end
				splashAt(to, 1.2, 2)
				AmbientWater.State.jumping = false
				return false
			end
			local pos = from + flat * u + Vector3.new(0, WATER - 0.6 + rise * 4 * u * (1 - u), 0)
			local velocity = flat / JUMP_TIME + Vector3.new(0, rise * 4 * (1 - 2 * u) / JUMP_TIME, 0)
			-- нос (+X модели) — по касательной к дуге; тело чуть изгибается, хвост бьёт
			local root = CFrame.lookAt(pos, pos + velocity) * CFrame.Angles(0, math.pi / 2, 0)
			local wag = math.rad(32) * math.sin(2 * math.pi * 9 * (t - start)) * (1 - 0.5 * u)
			local body = root * CFrame.Angles(0, -wag * 0.25, 0)
			local swing = body * hinge * CFrame.Angles(0, wag, 0) * inverse
			for k, part in jumper.parts do
				engine:Push(part, (if jumper.tail[k] then swing else body) * jumper.offsets[k])
			end
			return true
		end)
	end)
end

--------------------------------------------------------------------------------------------
-- Стайки рыб
--------------------------------------------------------------------------------------------

local function writeSchool(item: Item, t: number, engine: Engine)
	local d = item.data
	local center, heading = d.path(t)
	-- у поплавка стая уходит глубже
	local dive = 0
	for _, target in d.targets do
		local flat = Vector3.new(target.X - center.X, 0, target.Z - center.Z).Magnitude
		if flat < 12 then
			dive = math.max(dive, 1.6 * (1 - flat / 12))
		end
	end
	d.dive += (dive - d.dive) * 0.1
	item.pos = center
	local right = Vector3.new(-heading.Z, 0, heading.X)
	local n = engine.n
	local P, C = engine.parts, engine.cframes
	for _, fish in d.fish do
		local wobble = math.sin(t * 0.9 + fish.seed)
		local p = center
			+ right * (fish.side + 0.5 * wobble)
			- heading * (fish.back + 0.4 * math.sin(t * 0.7 + fish.seed * 2))
			+ Vector3.new(0, -(fish.depth + d.dive), 0)
		local yaw = math.rad(8) * math.sin(2 * math.pi * 3 * t + fish.seed)
		local root = CFrame.lookAt(p, p + heading) * CFrame.Angles(0, yaw + 0.12 * wobble, 0)
		local s = fish.size
		local tailYaw = math.rad(28) * math.sin(2 * math.pi * 3 * t + fish.seed - 1.2)
		n += 1
		P[n] = fish.body
		C[n] = root
		n += 1
		P[n] = fish.tail
		C[n] = root * CFrame.new(0, 0, 0.8 * s) * CFrame.Angles(0, tailYaw, 0) * CFrame.new(0, 0, 0.3 * s)
	end
	engine.n = n
end

local function makeSchool(engine: Engine, folder: Instance, rng: Random, path: (number) -> (Vector3, Vector3)): Item
	local fish = {}
	local color = FISH_COLORS[rng:NextInteger(1, #FISH_COLORS)]
	for k = 1, SCHOOL_SIZE do
		local s = rng:NextNumber(1.4, 2.4)
		local tint = color:Lerp(FISH_COLORS[rng:NextInteger(1, #FISH_COLORS)], 0.25)
		local body = quietPart(folder, "SchoolFish", Vector3.new(0.7, 0.8, 1.6) * s * 0.6, tint)
		local tail =
			quietPart(folder, "SchoolTail", Vector3.new(0.15, 0.7, 0.6) * s * 0.6, tint:Lerp(Color3.new(1, 1, 1), 0.3))
		fish[k] = {
			body = body,
			tail = tail,
			size = s * 0.6,
			side = (k - (SCHOOL_SIZE + 1) / 2) * 1.7 + rng:NextNumber(-0.4, 0.4),
			back = math.abs(k - (SCHOOL_SIZE + 1) / 2) * 1.6 + rng:NextNumber(0, 0.8),
			depth = rng:NextNumber(0.8, 1.6),
			seed = rng:NextNumber(0, 2 * math.pi),
		}
	end
	local start = path(0)
	return engine:Add({
		pos = start,
		radius = 8,
		speed = 8, -- плывут 3–5 studs/с, хвосты бьют быстрее
		range = 220,
		cost = SCHOOL_SIZE * 2,
		kind = "School",
		write = writeSchool,
		locate = function(item: Item, t: number)
			item.pos = (path(t))
		end,
		data = { fish = fish, path = path, targets = {}, dive = 0 },
	} :: any)
end

local function startSchools(engine: Engine, folder: Instance, context: Context)
	local rng = context.rng
	local schools = AmbientWater.State.schools
	for _ = 1, SCHOOLS_RING do
		local r0 = rng:NextNumber(LAGOON_IN + 14, LAGOON_OUT - 14)
		local a0 = rng:NextNumber(0, 2 * math.pi)
		local speed = rng:NextNumber(3, 5) / r0 * (if rng:NextNumber() < 0.5 then -1 else 1)
		local p = rng:NextNumber(0, 10)
		local function at(t: number): Vector3
			local a = a0 + t * speed
			local r = r0 + 10 * math.sin(0.07 * t + p)
			return Vector3.new(math.sin(a) * r, WATER, math.cos(a) * r)
		end
		table.insert(
			schools,
			makeSchool(engine, folder, rng, function(t: number): (Vector3, Vector3)
				local c, ahead = at(t), at(t + 0.3)
				local h = ahead - c
				return c, if h.Magnitude > 1e-3 then h.Unit else Vector3.new(0, 0, -1)
			end)
		)
	end
	-- две стаи перед ближайшим к камере пирсом (раз в секунду смотрим, у какого мы пирса)
	for k = 1, SCHOOLS_PIER do
		local px, pz = rng:NextNumber(0, 10), rng:NextNumber(0, 10)
		local frame = CFrame.new(0, WATER, 0)
		local side = if k == 1 then -1 else 1
		local function at(t: number): Vector3
			local lx = side * (12 + 22 * (0.5 + 0.5 * math.sin(0.09 * t + px)))
			local lz = -(MapConfig.PierLength + 18 + 26 * (0.5 + 0.5 * math.sin(0.13 * t + pz)))
			local p = frame:PointToWorldSpace(Vector3.new(lx, 0, lz))
			return Vector3.new(p.X, WATER, p.Z)
		end
		local item = makeSchool(engine, folder, rng, function(t: number): (Vector3, Vector3)
			local c, ahead = at(t), at(t + 0.3)
			local h = ahead - c
			h = Vector3.new(h.X, 0, h.Z)
			return c, if h.Magnitude > 1e-3 then h.Unit else Vector3.new(0, 0, -1)
		end)
		table.insert(schools, item)
		local current: Model? = nil
		engine:Every(1, function()
			local base = context.nearestBase()
			if base and base.model ~= current then
				-- переехать к другому пирсу только незаметно (стая не на экране)
				if current == nil or not AmbientEngine.Visible(engine, item.pos, item.radius) then
					current = base.model
					local cf = base.cf
					frame = CFrame.new(cf.Position.X, WATER, cf.Position.Z) * cf.Rotation
					item.pos = at(os.clock())
				end
			end
		end)
	end
	engine:Every(0.5, function()
		local targets = bobberTargets()
		for _, school in schools do
			school.data.targets = targets
		end
	end)
end

--------------------------------------------------------------------------------------------
-- Пена
--------------------------------------------------------------------------------------------

type Foam = {
	pos: Vector3, -- центр на воде
	width: number, -- поперёк корпуса, studs
	length: number, -- вдоль корпуса
	rot: CFrame, -- поворот (только по горизонтали): X — поперёк, Z — вдоль
	omega: number, -- фаза качания Bob: пена белее, когда корпус внизу
	phase: number,
}

-- Корпус на воде: детали лодки у ватерлинии (не мачты, не тонкие верёвки и швартовы), в осях
-- модели; пена — овал вокруг них на FOAM_PAD шире.
local function hullSpec(bob: Bob): Foam?
	if bob.amplitude < FOAM_MIN_BOB then
		return nil -- (кувшинки лежат на воде — им пена не нужна)
	end
	local frame = bob.box
	local flatRot =
		CFrame.fromMatrix(Vector3.zero, Vector3.new(frame.RightVector.X, 0, frame.RightVector.Z).Unit, Vector3.yAxis)
	local lo, hi = nil :: Vector3?, nil :: Vector3?
	for _, d in bob.model:GetDescendants() do
		if d:IsA("BasePart") then
			local size = d.Size
			local thin = math.min(size.X, size.Z) < 0.35 and math.max(size.X, size.Z) > 2.5
			local y, half = d.Position.Y, d.Size.Y / 2
			if not thin and y - half < WATER + 1.2 and y + half > WATER - 1.5 then
				-- (все 8 углов: у повёрнутой детали — цилиндра-поплавка осью вверх — ширина
				-- по горизонтали лежит в её локальной Y)
				for sx = -1, 1, 2 do
					for sy = -1, 1, 2 do
						for sz = -1, 1, 2 do
							local corner = d.CFrame * Vector3.new(sx * size.X / 2, sy * size.Y / 2, sz * size.Z / 2)
							local l = flatRot:PointToObjectSpace(
								Vector3.new(corner.X - frame.Position.X, 0, corner.Z - frame.Position.Z)
							)
							local a, b = lo, hi
							lo = if a then Vector3.new(math.min(a.X, l.X), 0, math.min(a.Z, l.Z)) else l
							hi = if b then Vector3.new(math.max(b.X, l.X), 0, math.max(b.Z, l.Z)) else l
						end
					end
				end
			end
		end
	end
	if not lo or not hi then
		return nil
	end
	local extent = (hi :: Vector3) - (lo :: Vector3)
	local mid = flatRot:PointToWorldSpace(((hi :: Vector3) + (lo :: Vector3)) / 2)
	if math.max(extent.X, extent.Z) < FOAM_MIN_HULL then
		return nil -- (поплавки сетей — мелочь, пены не нужно)
	end
	local width, length = extent.X + FOAM_PAD, extent.Z + FOAM_PAD
	if math.max(width, length) > 40 then
		return nil
	end
	return {
		pos = Vector3.new(frame.Position.X + mid.X, WATER, frame.Position.Z + mid.Z),
		width = width,
		length = length,
		rot = flatRot,
		omega = bob.omega,
		phase = bob.phase,
	}
end

type Ring = { part: Part, fill: Frame, stroke: UIStroke, written: number }

-- Кольцо пены: плоская невидимая деталь с SurfaceGui — скруглённая рамка (овал / круг) с
-- белой обводкой и едва заметной заливкой. Одна деталь на кольцо любой длины.
local function makeFoamRing(folder: Instance): Ring
	local part = quietPart(folder, "FoamRing", Vector3.new(2, 0.05, 2), FOAM_COLOR)
	part.Transparency = 1
	part.CFrame = CFrame.new(0, -200, 0)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Foam"
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.Brightness = 1.15
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = FOAM_PPS
	gui.MaxDistance = FOAM_RANGE + 20
	gui.Parent = part
	local thick = math.floor(FOAM_STROKE * FOAM_PPS + 0.5)
	local fill = Instance.new("Frame")
	fill.Name = "Ring"
	fill.AnchorPoint = Vector2.new(0.5, 0.5)
	fill.Position = UDim2.fromScale(0.5, 0.5)
	fill.Size = UDim2.new(1, -2 * thick, 1, -2 * thick)
	fill.BackgroundColor3 = FOAM_COLOR
	fill.BackgroundTransparency = 1
	fill.BorderSizePixel = 0
	fill.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = fill
	local stroke = Instance.new("UIStroke")
	stroke.Color = FOAM_COLOR
	stroke.Thickness = thick
	stroke.Transparency = 1
	stroke.Parent = fill
	return { part = part, fill = fill, stroke = stroke, written = FOAM_T }
end

local function startFoam(engine: Engine, folder: Instance, context: Context)
	local rings: { Ring } = {}
	for k = 1, FOAM_POOL do
		rings[k] = makeFoamRing(folder)
	end
	local boatSpecs: { Foam } = {}
	for _, bob in context.bobs do
		local spec = hullSpec(bob)
		if spec then
			table.insert(boatSpecs, spec)
		end
	end
	AmbientWater.State.foamSpecs = #boatSpecs
	local postSpecs: { [Model]: { Foam } } = {} -- сваи пирса: один раз на базу
	local assigned: { [number]: Foam } = {}
	local item = engine:Add({
		pos = Vector3.new(0, -1e6, 0),
		radius = FOAM_RANGE,
		speed = 0,
		minRate = 10,
		range = 60, -- (pos — у камеры, пока роздано хоть одно кольцо; иначе далеко: не работает)
		cost = FOAM_POOL,
		interval = 1 / FOAM_HZ,
		kind = "Foam",
		write = function(_: Item, t: number, e: Engine)
			for k, spec in assigned do
				-- белее, когда корпус внизу качания (Bob: смещение A·sin); пишем только заметное
				local s = math.sin(spec.omega * t + spec.phase)
				local ring = rings[k]
				local transparency = FOAM_T + FOAM_SWING * s
				if math.abs(transparency - ring.written) >= FOAM_STEP then
					ring.written = transparency
					ring.stroke.Transparency = transparency
					e.w += 1
				end
			end
		end,
		data = {},
	} :: any)

	engine:Every(0.5, function()
		local cam = engine.camPos
		local candidates: { { spec: Foam, d: number } } = {}
		local function consider(spec: Foam, range: number)
			local d = (spec.pos - cam).Magnitude
			if d <= range then
				table.insert(candidates, { spec = spec, d = d })
			end
		end
		for _, spec in boatSpecs do
			consider(spec, FOAM_RANGE)
		end
		local base = context.nearestBase()
		if base then
			local posts = postSpecs[base.model]
			if not posts then
				posts = {}
				for _, post in base.posts do
					table.insert(posts, {
						pos = post,
						width = FOAM_POST,
						length = FOAM_POST,
						rot = CFrame.identity,
						omega = 2 * math.pi / 3,
						phase = (post.X * 0.37 + post.Z * 0.61) % (2 * math.pi),
					})
				end
				postSpecs[base.model] = posts
			end
			for _, spec in posts do
				consider(spec, FOAM_RANGE * 0.6)
			end
		end
		table.sort(candidates, function(a: { spec: Foam, d: number }, b: { spec: Foam, d: number }): boolean
			return a.d < b.d
		end)
		local wanted: { [Foam]: boolean } = {}
		for k = 1, math.min(#candidates, FOAM_POOL) do
			wanted[candidates[k].spec] = true
		end
		-- уже розданные остаются на месте, ненужные прячутся
		local free: { number } = {}
		local have: { [Foam]: boolean } = {}
		for k = FOAM_POOL, 1, -1 do
			local spec = assigned[k]
			if spec and wanted[spec] then
				have[spec] = true
			else
				if spec then
					assigned[k] = nil
					rings[k].part.CFrame = CFrame.new(0, -200, 0)
				end
				table.insert(free, k)
			end
		end
		for spec in wanted do
			if not have[spec] then
				local slot = table.remove(free)
				if not slot then
					break
				end
				assigned[slot] = spec
				local ring = rings[slot]
				ring.part.Size = Vector3.new(spec.width, 0.05, spec.length)
				ring.part.CFrame = CFrame.new(spec.pos.X, WATER + FOAM_LIFT, spec.pos.Z) * spec.rot
				ring.stroke.Transparency = FOAM_T
				ring.fill.BackgroundTransparency = FOAM_FILL
				ring.written = FOAM_T
			end
		end
		local count = 0
		for _ in assigned do
			count += 1
		end
		AmbientWater.State.foam = count
		-- пена «живёт» у камеры (ближний ярус), пока есть кольца; нет — предмет не в работе
		item.pos = if count > 0 then cam else Vector3.new(0, -1e6, 0)
	end)
end

--------------------------------------------------------------------------------------------
-- Водопад
--------------------------------------------------------------------------------------------

local function startWaterfall(map: Instance): number
	local landmarks = map:FindFirstChild("Landmarks")
	local waterfall = landmarks and landmarks:FindFirstChild("Waterfall")
	local falls = waterfall and waterfall:FindFirstChild("Waterfall")
	if not falls then
		return 0
	end
	local count = 0
	for _, curtain in falls:GetChildren() do
		if curtain:IsA("BasePart") and string.match(curtain.Name, "^Curtain%d+_%d+$") then
			local size = curtain.Size
			local front = -size.Z / 2 - 0.12
			local top = Instance.new("Attachment")
			top.Name = "FlowTop"
			top.Position = Vector3.new(0, size.Y / 2 - 0.3, front)
			top.Parent = curtain
			local bottom = Instance.new("Attachment")
			bottom.Name = "FlowBottom"
			bottom.Position = Vector3.new(0, -size.Y / 2 + 0.3, front)
			bottom.Parent = curtain
			local beam = Instance.new("Beam")
			beam.Name = "Flow"
			beam.Attachment0 = top
			beam.Attachment1 = bottom
			beam.FaceCamera = true
			beam.Segments = 2
			beam.Width0 = size.X * 0.9
			beam.Width1 = size.X * 0.95
			beam.Texture = SMOKE
			beam.TextureMode = Enum.TextureMode.Wrap
			beam.TextureLength = 5
			beam.TextureSpeed = 1.4 + 0.15 * (count % 3)
			beam.LightEmission = 0.15
			beam.LightInfluence = 0.6
			beam.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(200, 240, 255))
			beam.Transparency = numbers({ { 0, 0.35 }, { 1, 0.6 } })
			beam.Parent = curtain
			count += 1
		end
	end
	return count
end

function AmbientWater.Start(engine: Engine, folder: Instance, map: Instance?, context: Context)
	startGlints(engine, folder, context)
	startJumps(engine, folder, context)
	startSchools(engine, folder, context)
	startFoam(engine, folder, context)
	if map then
		AmbientWater.State.waterfallBeams = startWaterfall(map)
	end
end

return AmbientWater
