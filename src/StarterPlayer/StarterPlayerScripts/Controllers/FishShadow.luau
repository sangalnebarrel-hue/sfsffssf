--!strict
--[[
	FishShadow — тень рыбы под водой у поплавка (FishingFxController ведёт её из своего
	покадрового цикла, у своего поплавка и у чужих не дальше Fx.AmbientRange; только на клиенте).

	Две закреплённые детали чуть под водой (DEPTH studs): тело — сплющенный эллипсоид
	(SpecialMesh «Sphere»), хвост — ромб за ним; тёмно-синие, полупрозрачные, без столкновений,
	запросов и теней, SmoothPlastic (без LEGO-шипов). Двигаются одним BulkMoveTo за кадр.
	Поведение (mode — что сейчас с поплавком):
	  "wait"   — через APPEAR после приводнения проявляется вдали (ENTER_R studs, на дальней от
	             рыбака стороне), подплывает и кружит вокруг поплавка (CIRCLE_R, CIRCLE_SPEED);
	             раз в APPROACH_EVERY с подплывает к самому поплавку («присматривается») и уходит;
	  nibble   — (своя «примерка», 0..1) — бросок к поплавку и тычок, потом отходит;
	  "bite"   — бросок под поплавок за LUNGE с, тянет его прочь от рыбака в такт рывкам (dip),
	             темнеет и светлеет, хвост бьёт часто;
	  "reel"   — под поплавком, мечется вместе с ним (swing — та же фаза, что у метаний
	             поплавка), тянет прочь, хвост бьёт широко; крупнее у редкой рыбы (scale —
	             своя рыба: размер по редкости из мини-игры; чужая — OTHER_SCALE); на каждом
	             крайнем положении — короткая «вспышка бока» (светлее, ≤ 2,4 раза в секунду);
	  "caught" — исчезает сразу (рыба выпрыгнула — дальше прыжок FishingFxController);
	  "lost" / "gone" — рывком уходит прочь от рыбака (FLEE studs за FLEE_TIME), тает.
	Движение — пружина к цели (своя «жёсткость» у каждого режима), поворот — по скорости,
	хвост машет (частота и размах — по режиму).

	Бюджет: 2 детали на тень, 1 BulkMoveTo и ≤ 2 записи Transparency за кадр; ни одного
	соединения; детали создаются один раз (new) и удаляются destroy (вместе с поплавком).

	API:
	  FishShadow.new(parent, own, seed, water) -> Shadow   -- water — точка на воде под поплавком
	  FishShadow.step(shadow, now, mode, since, water, fisher, dip, nibble, swing, scale)
	  FishShadow.parts(shadow) -> { BasePart }
	  FishShadow.destroy(shadow)
]]

local Workspace = game:GetService("Workspace")

local DEPTH = 0.45 -- под водой, studs
local COLOR = Color3.fromRGB(14, 40, 60)
local FLASH_COLOR = Color3.fromRGB(70, 120, 150)
local OWN_ALPHA, OTHER_ALPHA = 0.42, 0.55 -- прозрачность тени (своя заметнее)
local BODY = Vector3.new(2.6, 0.12, 1.05)
local TAIL = Vector3.new(0.75, 0.1, 0.75)
local APPEAR, FADE = 0.8, 0.35 -- с после приводнения; проявляется / тает (постоянная времени), с
local ENTER_R, CIRCLE_R, NEAR_R = 7.5, 3.4, 1.1
local CIRCLE_SPEED = 0.35 -- рад/с
local APPROACH_EVERY, APPROACH_TIME = 2.4, 0.9
local LUNGE = 0.12
local FLEE, FLEE_TIME = 10, 0.4
local FLASH_TIME = 0.08
local TAU = 2 * math.pi

-- Жёсткость пружины к цели (обратное время, 1/с) и хвост (Гц, рад) по режиму.
local FOLLOW: { [string]: number } = { wait = 2.2, nibble = 14, bite = 22, reel = 16, gone = 9 }
local WAG: { [string]: { number } } = {
	wait = { 2.2, 0.32 },
	nibble = { 5, 0.45 },
	bite = { 6, 0.5 },
	reel = { 4.5, 0.6 },
	gone = { 6, 0.5 },
}

export type Shadow = {
	body: BasePart,
	tail: BasePart,
	list: { BasePart },
	frames: { CFrame },
	alpha: number,
	seed: number,
	position: Vector3?, -- где сейчас (на глубине DEPTH)
	heading: number, -- рад, вокруг вертикали (0 — нос в +X)
	visible: number, -- 0..1
	scale: number,
	mode: string,
	modeSince: number,
	fleeFrom: Vector3?,
	fleeDir: Vector3,
	lastSwing: number,
	flashUntil: number,
	dir: number, -- по часовой / против
	alphaWritten: number,
	flashWritten: boolean,
	last: number, -- os.clock() прошлого шага
	arriveAt: number?, -- os.clock(): приплыла (видна)
}

local FishShadow = {}

local function quiet(name: string, size: Vector3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.SmoothPlastic -- без LEGO-шипов (их рисует только Plastic)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Color = COLOR
	part.Transparency = 1
	part.Size = size
	part.Parent = parent
	return part
end

function FishShadow.new(parent: Instance, own: boolean, seed: number, water: Vector3): Shadow
	local body = quiet("FishShadow", BODY, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body
	local tail = quiet("FishShadowTail", TAIL, parent)
	local frame = CFrame.new(water - Vector3.new(0, DEPTH, 0))
	body.CFrame = frame
	tail.CFrame = frame
	return {
		body = body,
		tail = tail,
		list = { body, tail },
		frames = { frame, frame },
		alpha = if own then OWN_ALPHA else OTHER_ALPHA,
		seed = seed,
		position = nil,
		heading = 0,
		visible = 0,
		scale = 1,
		mode = "wait",
		modeSince = os.clock(),
		fleeFrom = nil,
		fleeDir = Vector3.xAxis,
		lastSwing = 0,
		flashUntil = 0,
		dir = if seed % 2 < 1 then 1 else -1,
		alphaWritten = 1,
		flashWritten = false,
		last = os.clock(),
		arriveAt = nil,
	}
end

function FishShadow.parts(shadow: Shadow): { BasePart }
	return shadow.list
end

function FishShadow.destroy(shadow: Shadow)
	shadow.body:Destroy()
	shadow.tail:Destroy()
end

local function flatUnit(v: Vector3, fallback: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else fallback
end

local function setScale(shadow: Shadow, scale: number)
	if math.abs(scale - shadow.scale) < 1e-3 then
		return
	end
	shadow.scale = scale
	shadow.body.Size = BODY * Vector3.new(scale, 1, scale)
	shadow.tail.Size = TAIL * Vector3.new(scale, 1, scale)
end

-- Один кадр. mode: "wait" | "bite" | "reel" | "caught" | "lost" | "gone"; since — os.clock()
-- начала этого состояния поплавка (у "wait" — приводнения); water — точка на воде под
-- поплавком; fisher — где рыбак; dip — нырок поклёвки 0..1; nibble — «примерка» 0..1 (nil —
-- нет); swing — метания поплавка −1..1; scale — размер рыбы.
function FishShadow.step(
	shadow: Shadow,
	now: number,
	mode: string,
	since: number,
	water: Vector3,
	fisher: Vector3,
	dip: number,
	nibble: number?,
	swing: number,
	scale: number
)
	local dt = math.clamp(now - shadow.last, 0, 0.1)
	shadow.last = now
	local away = flatUnit(water - fisher, Vector3.xAxis)
	local side = away:Cross(Vector3.yAxis)
	local depth = water - Vector3.new(0, DEPTH, 0)
	local t = now - since
	local key = mode
	local target: Vector3
	local visible = 1
	local wantScale = 1

	if mode == "lost" or mode == "gone" or mode == "caught" then
		if shadow.fleeFrom == nil then
			shadow.fleeFrom = shadow.position or depth
			shadow.fleeDir = away
			shadow.modeSince = now
		end
		local u = math.clamp((now - shadow.modeSince) / FLEE_TIME, 0, 1)
		local from = shadow.fleeFrom :: Vector3
		target = from + shadow.fleeDir * FLEE * u * u
		key = "gone"
		visible = if mode == "caught" then 0 else shadow.visible * (1 - u)
		shadow.position = target
		if mode == "caught" then
			shadow.visible = 0
		end
	else
		shadow.fleeFrom = nil
		wantScale = scale
		if mode == "wait" then
			-- приплывает через APPEAR после приводнения — или раньше, если уже «примеряется»
			if nibble and not shadow.arriveAt then
				shadow.arriveAt = now
			end
			local arrive = shadow.arriveAt or (since + APPEAR)
			if not shadow.arriveAt and now >= arrive then
				shadow.arriveAt = arrive
			end
			local age = now - arrive
			visible = if age >= 0 then 1 else 0
			local angle = shadow.seed + shadow.dir * CIRCLE_SPEED * t
			-- вход издалека (с дальней стороны), потом круги и «присматривания»
			local enter = math.clamp(math.max(age, 0) / 1.6, 0, 1)
			local r = ENTER_R + (CIRCLE_R - ENTER_R) * (1 - (1 - enter) ^ 2)
			local cycle = (math.max(age, 0) % APPROACH_EVERY) / APPROACH_TIME
			if enter >= 1 and cycle < 1 then
				r -= (CIRCLE_R - NEAR_R) * math.sin(math.pi * cycle) ^ 2
			end
			local around = away * math.cos(angle) + side * math.sin(angle)
			target = depth + around * r
			if nibble then
				key = "nibble"
				-- бросок к поплавку и тычок (nibble 0..1), потом отходит
				local poke = math.sin(math.pi * math.clamp(nibble, 0, 1))
				target = depth + around * (0.35 + (r - 0.35) * (1 - poke))
				visible = 1
			end
		elseif mode == "bite" then
			-- бросок под поплавок, тянет прочь в такт рывкам
			target = depth + away * (0.4 + 0.9 * dip) + side * math.sin(now * 13 + shadow.seed) * 0.15
			visible = 1 - 0.45 * dip
		else -- "reel"
			key = "reel"
			target = depth + away * 0.7 + side * swing * 0.35
			visible = 1
			if math.abs(swing) > 0.95 and math.abs(shadow.lastSwing) <= 0.95 then
				shadow.flashUntil = now + FLASH_TIME
			end
		end
		shadow.lastSwing = swing
		local position = shadow.position
		if position == nil then
			-- первое появление: сразу на месте (у поклёвки / борьбы — под поплавком)
			position = if mode == "wait" then target else depth
		end
		local k = 1 - math.exp(-(FOLLOW[key] or 3) * dt)
		if mode == "bite" and t < LUNGE then
			k = math.max(k, math.clamp(t / LUNGE, 0, 1))
		end
		shadow.position = (position :: Vector3):Lerp(target, k)
		-- проявляется и тает плавно (у тычка и поклёвки — быстро)
		local fade = if key == "nibble" then 0.08 elseif mode == "bite" then 0.05 else FADE
		shadow.visible += (visible - shadow.visible) * (1 - math.exp(-dt / fade))
		visible = shadow.visible
	end
	setScale(shadow, wantScale)

	-- нос — по скорости (у борьбы и поклёвки — прочь от рыбака)
	local position = shadow.position :: Vector3
	local wantHeading: number
	if key == "bite" or key == "reel" or key == "gone" then
		local dirv = if key == "gone" then shadow.fleeDir else away
		wantHeading = math.atan2(-dirv.Z, dirv.X) + (if key == "reel" then swing * 0.5 else 0)
	else
		local d = target - position
		if Vector3.new(d.X, 0, d.Z).Magnitude > 0.05 then
			wantHeading = math.atan2(-d.Z, d.X)
		else
			-- кружит: нос по касательной
			local radial = flatUnit(position - depth, away)
			local tangent = radial:Cross(Vector3.yAxis) * -shadow.dir
			wantHeading = math.atan2(-tangent.Z, tangent.X)
		end
	end
	local delta = (wantHeading - shadow.heading + math.pi) % TAU - math.pi
	shadow.heading += delta * (1 - math.exp(-8 * dt))

	local wag = WAG[key] or WAG.wait
	local tailAngle = wag[2] * math.sin(TAU * wag[1] * now + shadow.seed)
	local s = shadow.scale
	local base = CFrame.new(position) * CFrame.Angles(0, shadow.heading + tailAngle * 0.15, 0)
	local frames = shadow.frames
	frames[1] = base
	frames[2] = base
		* CFrame.new(-BODY.X * 0.42 * s, 0, 0)
		* CFrame.Angles(0, tailAngle, 0)
		* CFrame.new(-TAIL.X * 0.55 * s, 0, 0)
		* CFrame.Angles(0, math.pi / 4, 0)
	Workspace:BulkMoveTo(shadow.list, frames, Enum.BulkMoveMode.FireCFrameChanged)

	local flash = now < shadow.flashUntil
	local alpha = 1 - (1 - shadow.alpha) * math.clamp(visible, 0, 1)
	alpha = math.round(alpha * 100) / 100
	if alpha ~= shadow.alphaWritten then
		shadow.alphaWritten = alpha
		shadow.body.Transparency = alpha
		shadow.tail.Transparency = alpha
	end
	if flash ~= shadow.flashWritten then
		shadow.flashWritten = flash
		shadow.body.Color = if flash then FLASH_COLOR else COLOR
	end
end

return FishShadow
