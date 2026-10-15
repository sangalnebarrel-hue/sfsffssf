--!strict
--[[
	FishLife — пойманная рыба живая (FishingFxController ведёт её из своего покадрового цикла;
	только на клиенте, у каждого игрока своя копия движения — записи C0 не реплицируются).

	Рыба над головой (HeldFish — модель сервера, FishingService.holdFish: детали приварены к
	Body, Body — к голове сваркой «HoldWeld»): каждый кадр пишем C0 этих сварок поверх исходных
	(запомнены при hold, возвращаются в release — точь-в-точь).
	  • Покачивание: вверх-вниз на BOB studs (легендарная и мифическая — BOB_RARE) с периодом
	    BOB_PERIOD, хвост лениво ходит из стороны в сторону (IDLE_WAG рад у кончика), рыба чуть
	    качается «носом» (IDLE_ROCK).
	  • Шлепки: первый — через FIRST_FLOP после начала (рыба только что приземлилась), потом каждые
	    FLOP_EVERY с (случайно, своё зерно у каждой рыбы): подскок на HOP studs, хвост бьёт вбок
	    и вверх-вниз (FishBody — тело гнётся дугой), рыба качается «носом» и чуть заваливается
	    на бок; за FLOP_TIME всё затухает. kick() — шлепок сейчас (повтор трофея).
	  • Все повороты — вокруг центра рамки рыбы: она не «уплывает», это всё тот же трофей над
	    головой (карточка, заголовок и повтор трофея целятся в него). Начало — с нуля, плавно
	    (RAMP), поэтому прыжок-копия передаёт рыбу без скачка.
	  • Табличка (BillboardGui, Adornee = Body): plate() — её StudsOffsetWorldSpace каждый кадр
	    гасит сдвиг Body (шлепки её не трясут) и добавляет своё мягкое покачивание (PLATE_BOB,
	    чуть вдогонку подскоку).
	  Уровни детализации (step(..., detail)): 2 — всё (≤ 1 + число деталей за шарниром записей
	  C0 за кадр), 1 — только сварка головы (рыба качается целиком, тело не гнётся), 0 — покой
	  (всё возвращено, записей нет).

	Рыба в прыжке (копия-«Leap», закреплена): leapPose() ставит детали BulkMoveTo по позе прыжка
	(pivot) — хвост бьёт (LEAP_WAG, LEAP_HZ), к концу прыжка затихает до нуля (передача рыбе над
	головой — без скачка). Капли (drips): с рыбы падают шарики воды — несколько при выходе из
	воды и по паре каждые DRIP_EVERY с первые DRIP_UNTIL доли прыжка; живут не дольше DRIP_LIFE и
	исчезают в воде.

	Бюджет: ни одного соединения и ни одного Instance за кадр (кроме капель: ≤ DRIP_MAX деталей на
	прыжок, создаются по одной); на рыбу над головой ≤ 1 + (детали за шарниром, ≈ 6–14) записей C0
	за кадр вблизи, 1 — дальше, 0 — далеко (решает FishingFxController); прыжок — один BulkMoveTo
	деталей рыбы (≤ 30) за кадр, 1 с.

	API:
	  FishLife.hold(model, seed, rarity, delay?) -> Life?   -- nil: не та модель (нет сварок)
	  FishLife.step(life, now, detail)                      -- detail: 0 | 1 | 2
	  FishLife.kick(life, now, power?)
	  FishLife.plate(life, gui)                             -- табличка рыбы: не трясётся, покачивается
	  FishLife.release(life)                                -- всё как было (C0, табличка)
	  FishLife.shift(life) -> Vector3                       -- куда сейчас сдвинута Body (мир)
	  FishLife.leap(model) -> Leap?
	  FishLife.leapPose(leap, pivot, u, t, scale)           -- u — доля прыжка, t — os.clock()
	  FishLife.drips(parent, waterY) -> Drips
	  FishLife.drip(drips, position, velocity, now) -> BasePart?
	  FishLife.stepDrips(drips, now, dt) -> number          -- сколько капель ещё летит
]]

local Workspace = game:GetService("Workspace")

local FishBody = require(script.Parent:WaitForChild("FishBody"))

local BOB, BOB_RARE, BOB_PERIOD = 0.1, 0.16, 1.8
local IDLE_WAG, IDLE_HZ = 0.2, 1.3
local IDLE_ROCK, ROCK_PERIOD = 0.035, 2.3
local RAMP = 0.3 -- движения нарастают от нуля, с
local FIRST_FLOP = 0.35
local FLOP_EVERY = { 1.3, 2.2 }
local FLOP_TIME = 0.6
local HOP, HOP_RARE = 0.28, 0.38
local PLATE_BOB, PLATE_PERIOD, PLATE_FOLLOW = 0.08, 2.2, 0.35
local LEAP_WAG, LEAP_UP, LEAP_HZ = 0.55, 0.2, 4.5
local DRIP_LIFE, DRIP_MAX, DRIP_SIZE = 0.5, 12, { 0.22, 0.36 }
local DRIP_COLOR = Color3.fromRGB(214, 242, 255)
local GRAVITY = 60
local TAU = 2 * math.pi

local RARE: { [string]: boolean } = { Legendary = true, Mythic = true }

type Plate = { gui: BillboardGui, base: Vector3 }

export type Life = {
	model: Model,
	weld: Weld,
	c0: CFrame,
	body: FishBody.Body,
	welds: { [number]: Weld }, -- welds[i] — сварка детали i к Body (i ≥ 2; у Body её нет)
	c1: { CFrame },
	start: number,
	phase: number,
	rng: Random,
	nextFlop: number,
	flopAt: number?,
	power: number,
	bob: number,
	hop: number,
	plates: { Plate },
	shiftLocal: Vector3, -- сдвиг Body в осях головы (последний кадр)
	bentInside: boolean, -- C0 деталей сейчас не исходные
	moved: boolean, -- C0 головы сейчас не исходный
}

export type Leap = { body: FishBody.Body, cframes: { CFrame } }

export type Drips = {
	parent: Instance,
	waterY: number,
	parts: { BasePart },
	velocity: { Vector3 },
	born: { number },
	made: number,
}

local FishLife = {}

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

function FishLife.hold(model: Model, seed: number, rarity: string?, delay: number?): Life?
	local body = model.PrimaryPart
	if not body then
		return nil
	end
	local headWeld: Weld? = nil
	for _, child in body:GetChildren() do
		local part0 = if child:IsA("Weld") then child.Part0 else nil
		if part0 and child:IsA("Weld") and child.Part1 == body and not part0:IsDescendantOf(model) then
			headWeld = child
			break
		end
	end
	if not headWeld then
		return nil
	end
	local parts: { BasePart } = { body }
	local rest: { CFrame } = { CFrame.identity }
	local welds: { [number]: Weld } = {} -- (по номеру детали; у Body, №1, сварки нет)
	local c1s: { CFrame } = { CFrame.identity }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= body then
			for _, child in d:GetChildren() do
				if child:IsA("Weld") and child.Part0 == body and child.Part1 == d then
					table.insert(parts, d)
					table.insert(rest, child.C0 * child.C1:Inverse())
					welds[#parts] = child
					table.insert(c1s, child.C1)
					break
				end
			end
		end
	end
	local rng = Random.new(seed)
	local start = os.clock() + (delay or 0)
	return {
		model = model,
		weld = headWeld,
		c0 = headWeld.C0,
		body = FishBody.new(parts, rest),
		welds = welds,
		c1 = c1s,
		start = start,
		phase = rng:NextNumber(0, TAU),
		rng = rng,
		nextFlop = start + FIRST_FLOP,
		flopAt = nil,
		power = 1,
		bob = if rarity and RARE[rarity] then BOB_RARE else BOB,
		hop = if rarity and RARE[rarity] then HOP_RARE else HOP,
		plates = {},
		shiftLocal = Vector3.zero,
		bentInside = false,
		moved = false,
	}
end

-- Подскок шлепка (studs) в момент now.
local function hopAt(life: Life, now: number): number
	local flopAt = life.flopAt
	if not flopAt then
		return 0
	end
	local u = (now - flopAt) / FLOP_TIME
	if u <= 0 or u >= 1 then
		return 0
	end
	return life.hop * life.power * math.sin(math.pi * math.min(u / 0.5, 1))
end

local function restoreInside(life: Life)
	if not life.bentInside then
		return
	end
	life.bentInside = false
	local body = life.body
	for i = 2, #body.parts do
		local weld = life.welds[i]
		if weld then
			weld.C0 = body.rest[i] * life.c1[i]
		end
	end
end

local function writePlates(life: Life, head: BasePart?, extra: number)
	if #life.plates == 0 then
		return
	end
	local shift = if head then head.CFrame:VectorToWorldSpace(life.shiftLocal) else Vector3.zero
	for i = #life.plates, 1, -1 do
		local plate = life.plates[i]
		if plate.gui.Parent == nil then
			table.remove(life.plates, i)
		else
			plate.gui.StudsOffsetWorldSpace = plate.base - shift + Vector3.new(0, extra, 0)
		end
	end
end

function FishLife.step(life: Life, now: number, detail: number)
	local weld = life.weld
	local head = weld.Part0
	if detail <= 0 or now < life.start then
		if life.moved then
			life.moved = false
			weld.C0 = life.c0
		end
		restoreInside(life)
		life.shiftLocal = Vector3.zero
		writePlates(life, head, 0)
		return
	end
	local t = now - life.start
	local env = smooth(t / RAMP)
	local phase = life.phase
	local lift = life.bob * math.sin(TAU * t / BOB_PERIOD + phase) * env
	local yaw = IDLE_WAG * math.sin(TAU * IDLE_HZ * t + phase) * env
	local up = 0
	local rock = IDLE_ROCK * math.sin(TAU * t / ROCK_PERIOD + phase * 1.7) * env
	local roll = 0

	if now >= life.nextFlop then
		life.flopAt = now
		life.power = 1
		life.nextFlop = now + life.rng:NextNumber(FLOP_EVERY[1], FLOP_EVERY[2])
	end
	local flopAt = life.flopAt
	if flopAt then
		local u = (now - flopAt) / FLOP_TIME
		if u >= 1 then
			life.flopAt = nil
		elseif u >= 0 then
			local p = life.power * env
			lift += hopAt(life, now) * env
			rock += 0.3 * p * math.exp(-4.5 * u) * math.sin(TAU * 2.2 * u)
			yaw += 0.55 * p * math.exp(-3.2 * u) * math.sin(TAU * 3 * u + 0.5)
			up += 0.4 * p * math.exp(-4 * u) * math.sin(TAU * 2.4 * u + 1.3)
			roll += 0.22 * p * math.exp(-6 * u) * math.sin(TAU * 1.6 * u)
		end
	end

	local body = life.body
	local c = body.center
	-- повороты вокруг центра рамки; нос слегка навстречу хвосту (центр не «уплывает»)
	local rigid = CFrame.new(c.X, c.Y + lift, c.Z)
		* CFrame.Angles(roll, -0.25 * yaw * (if detail >= 2 then 1 else 0), rock)
		* CFrame.new(-c)
	local bodyBent = CFrame.identity
	if detail >= 2 then
		bodyBent = FishBody.bent(body, 1, yaw, up)
		local inverse = bodyBent:Inverse()
		local bodyBends = FishBody.bends(body, 1)
		for i = 2, #body.parts do
			local partWeld = life.welds[i]
			if partWeld and (bodyBends or FishBody.bends(body, i)) then
				partWeld.C0 = inverse * FishBody.bent(body, i, yaw, up) * life.c1[i]
			end
		end
		life.bentInside = true
	else
		restoreInside(life)
	end
	local c0 = life.c0 * rigid * bodyBent
	weld.C0 = c0
	life.moved = true
	life.shiftLocal = c0.Position - life.c0.Position
	local plateLift = PLATE_BOB * math.sin(TAU * t / PLATE_PERIOD + 1) * env + PLATE_FOLLOW * hopAt(life, now - 0.1)
	writePlates(life, head, plateLift)
end

function FishLife.kick(life: Life, now: number, power: number?)
	local at = math.max(now, life.start)
	life.flopAt = at
	life.power = power or 1.3
	life.nextFlop = at + life.rng:NextNumber(FLOP_EVERY[1], FLOP_EVERY[2]) + FLOP_TIME
end

function FishLife.shift(life: Life): Vector3
	local head = life.weld.Part0
	return if head then head.CFrame:VectorToWorldSpace(life.shiftLocal) else Vector3.zero
end

function FishLife.plate(life: Life, gui: BillboardGui)
	table.insert(life.plates, { gui = gui, base = gui.StudsOffsetWorldSpace + FishLife.shift(life) })
end

function FishLife.release(life: Life)
	if life.moved then
		life.moved = false
		life.weld.C0 = life.c0
	end
	restoreInside(life)
	for _, plate in life.plates do
		if plate.gui.Parent then
			plate.gui.StudsOffsetWorldSpace = plate.base
		end
	end
	table.clear(life.plates)
	life.shiftLocal = Vector3.zero
end

--------------------------------------------------------------------------------
-- Прыжок: изгиб копии и капли
--------------------------------------------------------------------------------

function FishLife.leap(model: Model): Leap?
	local body = FishBody.fromModel(model)
	if not body then
		return nil
	end
	return { body = body, cframes = table.clone(body.rest) }
end

-- Детали копии по позе прыжка pivot (с масштабом scale — «плюх» в конце), хвост бьёт.
function FishLife.leapPose(leap: Leap, pivot: CFrame, u: number, t: number, scale: number)
	local env = math.min(u / 0.06, 1) * (1 - math.clamp(u, 0, 1)) ^ 1.3
	local yaw = LEAP_WAG * math.sin(TAU * LEAP_HZ * t) * env
	local up = LEAP_UP * math.sin(TAU * LEAP_HZ * t + 1.1) * env
	local body = leap.body
	local cframes = leap.cframes
	for i = 1, #body.parts do
		local cf = FishBody.bent(body, i, yaw, up)
		if scale ~= 1 then
			cf = CFrame.new(cf.Position * scale) * cf.Rotation
		end
		cframes[i] = pivot * cf
	end
	Workspace:BulkMoveTo(body.parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
end

function FishLife.drips(parent: Instance, waterY: number): Drips
	return { parent = parent, waterY = waterY, parts = {}, velocity = {}, born = {}, made = 0 }
end

-- Новая капля (nil — лимит DRIP_MAX на прыжок).
function FishLife.drip(drips: Drips, position: Vector3, velocity: Vector3, now: number): BasePart?
	if drips.made >= DRIP_MAX then
		return nil
	end
	drips.made += 1
	local size = DRIP_SIZE[1] + (DRIP_SIZE[2] - DRIP_SIZE[1]) * ((drips.made * 0.618) % 1)
	local part = Instance.new("Part")
	part.Name = "Drip"
	part.Shape = Enum.PartType.Ball
	part.Material = Enum.Material.SmoothPlastic -- без LEGO-шипов
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = DRIP_COLOR
	part.Transparency = 0.15
	part.Size = Vector3.new(size, size, size)
	part.CFrame = CFrame.new(position)
	part.Parent = drips.parent
	table.insert(drips.parts, part)
	table.insert(drips.velocity, velocity)
	table.insert(drips.born, now)
	return part
end

-- Капли падают; упавшие в воду и старые исчезают. Возвращает, сколько ещё летит.
function FishLife.stepDrips(drips: Drips, now: number, dt: number): number
	local parts, velocity, born = drips.parts, drips.velocity, drips.born
	local moving: { BasePart } = {}
	local frames: { CFrame } = {}
	for i = #parts, 1, -1 do
		local part = parts[i]
		local v = velocity[i] - Vector3.new(0, GRAVITY * dt, 0)
		velocity[i] = v
		local position = part.Position + v * dt
		local age = now - born[i]
		if age >= DRIP_LIFE or position.Y < drips.waterY or part.Parent == nil then
			part:Destroy()
			table.remove(parts, i)
			table.remove(velocity, i)
			table.remove(born, i)
		else
			table.insert(moving, part)
			frames[#moving] = CFrame.new(position)
			part.Transparency = 0.15 + 0.6 * (age / DRIP_LIFE) ^ 2
		end
	end
	if #moving > 0 then
		Workspace:BulkMoveTo(moving, frames, Enum.BulkMoveMode.FireCFrameChanged)
	end
	return #parts
end

return FishLife
