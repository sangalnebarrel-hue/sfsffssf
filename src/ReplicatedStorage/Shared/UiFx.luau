--!strict
--[[
	UiFx — «сочные» анимации интерфейса на клиенте: нажатия, выскакивания, блики, кольца, лучи,
	конфетти, искры, всплывающий текст, счётчики, радуга, вспышки. Стиль и тайминги —
	tools/builder/gui/STYLE.md §2, список функций и примеры — STYLE.md «API».

	Правила:
	  • Один общий планировщик (RenderStepped на клиенте, Heartbeat в остальных случаях) ведёт все
	    покадровые эффекты (конфетти, счётчики, радуга, полёт значка…) и ОТКЛЮЧАЕТСЯ, когда
	    ничего не идёт. Короткие эффекты (нажатие, выскакивание, покачивание, тряска, блик, кольца,
	    лучи, искры, всплывающий текст) — только TweenService и task.delay, без соединений.
	  • Каждый эффект сам удаляет свои временные объекты; каждый бесконечный эффект возвращает
	    функцию остановки (её можно положить в Trove: trove:Add(stop)).
	  • Эффекты не перехватывают ввод (Active = false) и не меняют имена элементов.
	  • «Конфета» (Theme.candy в сборщике): прозрачный корень → Lip (губа, обводка) + лицевая
	    сторона (атрибут CandyFace, обычно "Face") с градиентом "Fill", бликом Gloss и Shine.

	Только для клиента (LocalScript-контроллеры); на сервере не используется.
]]

local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local UIConfig = require(script.Parent:WaitForChild("Config"):WaitForChild("UIConfig"))

export type Stop = () -> ()

type Swatch = { Top: Color3, Bottom: Color3, Lip: Color3 }

local Fx = UIConfig.Fx
local Palette = UIConfig.Palette
local WHITE = Color3.new(1, 1, 1)
local INK: Color3 = UIConfig.Ink
local FONT = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold)
local BACK = Enum.EasingStyle.Back
local QUAD = Enum.EasingStyle.Quad
local SINE = Enum.EasingStyle.Sine
local LINEAR = Enum.EasingStyle.Linear
local OUT = Enum.EasingDirection.Out
local IN = Enum.EasingDirection.In
local INOUT = Enum.EasingDirection.InOut

-- Полоса блика: прозрачно → белая полоса посередине → прозрачно (сдвигается Offset −1 → 1).
local SHINE_BAND = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 1),
	NumberSequenceKeypoint.new(0.36, 1),
	NumberSequenceKeypoint.new(0.45, 0.55),
	NumberSequenceKeypoint.new(0.5, 0.25),
	NumberSequenceKeypoint.new(0.55, 0.55),
	NumberSequenceKeypoint.new(0.64, 1),
	NumberSequenceKeypoint.new(1, 1),
})

-- Встроенные звуки клиента (загружать ничего не нужно; если файла нет — просто тишина).
local SOUNDS: { [string]: string } = {
	click = "rbxasset://sounds/button.wav",
	tick = "rbxasset://sounds/clickfast.wav",
	pop = "rbxasset://sounds/electronicpingshort.wav",
	swoosh = "rbxasset://sounds/swoosh.wav",
	splash = "rbxasset://sounds/impact_water.mp3",
}

local rng = Random.new()

local function noop() end

local UiFx = {}

--------------------------------------------------------------------------------
-- Планировщик: одно соединение на все покадровые эффекты
--------------------------------------------------------------------------------

type Job = {
	step: (dt: number) -> boolean,
	cleanup: (() -> ())?,
	alive: boolean,
}

local jobs: { Job } = {}
local liveJobs = 0
local frameConnection: RBXScriptConnection? = nil

local function finishJob(job: Job)
	if not job.alive then
		return
	end
	job.alive = false
	liveJobs -= 1
	local cleanup = job.cleanup
	job.cleanup = nil
	if cleanup then
		local ok, err = pcall(cleanup)
		if not ok then
			warn("[UiFx] ошибка очистки эффекта:", err)
		end
	end
	if liveJobs <= 0 then
		liveJobs = 0
		table.clear(jobs)
		if frameConnection then
			frameConnection:Disconnect()
			frameConnection = nil
		end
	end
end

local function onFrame(dt: number)
	local index = 1
	while index <= #jobs do
		local job = jobs[index]
		if job.alive then
			local ok, result = pcall(job.step, dt)
			if not ok then
				warn("[UiFx] эффект упал:", result)
				finishJob(job)
			elseif result == false then
				finishJob(job)
			end
		end
		if jobs[index] == job then
			if job.alive then
				index += 1
			else
				table.remove(jobs, index)
			end
		end
	end
end

--[[
	Покадровый эффект: step(dt) вызывается каждый кадр, пока возвращает true; cleanup — один раз
	в конце (или при остановке). Возвращает stop.
]]
function UiFx.schedule(step: (dt: number) -> boolean, cleanup: (() -> ())?): Stop
	local job: Job = { step = step, cleanup = cleanup, alive = true }
	table.insert(jobs, job)
	liveJobs += 1
	if not frameConnection then
		local signal = if RunService:IsClient() then RunService.RenderStepped else RunService.Heartbeat
		frameConnection = signal:Connect(onFrame)
	end
	return function()
		finishJob(job)
	end
end

-- Сколько покадровых эффектов идёт сейчас (для тестов и отладки).
function UiFx.activeJobs(): number
	return liveJobs
end

--------------------------------------------------------------------------------
-- Мелочи
--------------------------------------------------------------------------------

local function tween(
	instance: Instance,
	time: number,
	goals: { [string]: any },
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?,
	delay: number?
): Tween
	local info = TweenInfo.new(time, style or QUAD, direction or OUT, 0, false, delay or 0)
	local created = TweenService:Create(instance, info, goals)
	created:Play()
	return created
end
UiFx.tween = tween

local function scaled(color: Color3, k: number): Color3
	return Color3.new(color.R * k, color.G * k, color.B * k)
end

function UiFx.lighten(color: Color3, k: number): Color3
	return color:Lerp(WHITE, k)
end

function UiFx.darken(color: Color3, k: number): Color3
	return scaled(color, 1 - k)
end

-- Цвет из списка по доле k ∈ [0, 1] (плавно между соседними).
local function sampleColors(colors: { Color3 }, k: number): Color3
	local count = #colors
	if count == 0 then
		return WHITE
	elseif count == 1 then
		return colors[1]
	end
	local x = math.clamp(k, 0, 1) * (count - 1)
	local index = math.min(math.floor(x), count - 2)
	return colors[index + 1]:Lerp(colors[index + 2], x - index)
end
UiFx.sampleColors = sampleColors

-- ColorSequence через цвета, равномерно.
function UiFx.sequence(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local points = {}
	for index, color in colors do
		table.insert(points, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(points)
end

-- UIScale "FxScale" элемента (тот же, что использует FishingController): создаётся один раз.
function UiFx.scaleOf(gui: GuiObject): UIScale
	local existing = gui:FindFirstChild("FxScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "FxScale"
	scale.Parent = gui
	return scale
end

-- Лицевая сторона «конфеты» (или сам элемент, если это не конфета).
function UiFx.faceOf(root: GuiObject): GuiObject
	local name = root:GetAttribute("CandyFace")
	if typeof(name) == "string" then
		local face = root:FindFirstChild(name)
		if face and face:IsA("GuiObject") then
			return face
		end
	end
	return root
end

-- Скругление для временных слоёв: как у конфеты (CandyRadius) или копия UICorner элемента.
local function copyCorner(from: GuiObject, to: GuiObject)
	local radius = from:GetAttribute("CandyRadius")
	if typeof(radius) == "number" then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(radius, 0)
		corner.Parent = to
		return
	end
	local corner = from:FindFirstChildOfClass("UICorner")
	if corner then
		corner:Clone().Parent = to
	end
end

--[[
	Перекрасить «конфету»:
	  токен палитры ("Leaf") или { Top, Bottom, Lip } — градиент верх → низ и губа;
	  Color3 — произвольный цвет (цвет базы): лицевая сторона этого цвета с затемнением книзу.
]]
function UiFx.setCandy(root: GuiObject, look: string | Color3 | Swatch)
	local face = UiFx.faceOf(root)
	local fill = face:FindFirstChild("Fill")
	local lip = root:FindFirstChild("Lip")
	if typeof(look) == "Color3" then
		face.BackgroundColor3 = look
		if fill and fill:IsA("UIGradient") then
			local k = UIConfig.Tint.Bottom
			fill.Color = ColorSequence.new(WHITE, Color3.new(k, k, k))
		end
		if lip and lip:IsA("GuiObject") then
			lip.BackgroundColor3 = scaled(look, UIConfig.Tint.Lip)
		end
		return
	end
	local swatch: Swatch? = if type(look) == "string" then Palette[look] else look
	if not swatch then
		return
	end
	face.BackgroundColor3 = WHITE
	if fill and fill:IsA("UIGradient") then
		fill.Color = ColorSequence.new(swatch.Top, swatch.Bottom)
	end
	if lip and lip:IsA("GuiObject") then
		lip.BackgroundColor3 = swatch.Lip
	end
end

-- Короткий звук интерфейса: "click" | "tick" | "pop" | "swoosh" | "splash" (или rbxasset://…).
local soundCache: { [string]: Sound } = {}
function UiFx.sound(name: string, volume: number?)
	local id = SOUNDS[name] or name
	local sound = soundCache[id]
	if not sound or sound.Parent == nil then
		sound = Instance.new("Sound")
		sound.Name = `UiFx_{name}`
		sound.SoundId = id
		sound.Parent = SoundService
		soundCache[id] = sound
	end
	sound.Volume = volume or 0.4
	pcall(function()
		sound:Play()
	end)
end

-- Запомненные «спокойные» значения на время покачивания / тряски (чтобы эффекты не копились).
type Motion = { rest: any, threads: { thread } }
local rotations: { [Instance]: Motion } = setmetatable({}, { __mode = "k" }) :: any
local positions: { [Instance]: Motion } = setmetatable({}, { __mode = "k" }) :: any

local function cancelThreads(threads: { thread })
	for _, thread in threads do
		if coroutine.status(thread) == "suspended" then
			pcall(task.cancel, thread)
		end
	end
	table.clear(threads)
end

local function beginMotion(store: { [Instance]: Motion }, gui: GuiObject, current: any): Motion
	local motion = store[gui]
	if motion then
		cancelThreads(motion.threads)
	else
		motion = { rest = current, threads = {} }
		store[gui] = motion
	end
	return motion
end

--------------------------------------------------------------------------------
-- Нажатие, выскакивание, пульс, покачивание, тряска
--------------------------------------------------------------------------------

export type PressOptions = {
	scale: number?, -- насколько сжимать (0.88)
	sound: string?, -- звук нажатия ("click")
}

-- Кнопка «сжимается» при нажатии и пружинит обратно. Возвращает функцию отвязки.
function UiFx.press(button: GuiButton, opts: PressOptions?): Stop
	local o: PressOptions = opts or {}
	local scale = UiFx.scaleOf(button)
	local pressed = false
	local inputEnded: RBXScriptConnection? = nil

	local function release()
		if inputEnded then
			inputEnded:Disconnect()
			inputEnded = nil
		end
		if not pressed then
			return
		end
		pressed = false
		tween(scale, 0.25, { Scale = 1 }, BACK, OUT)
	end

	local down = button.MouseButton1Down:Connect(function()
		if pressed then
			return
		end
		pressed = true
		tween(scale, 0.06, { Scale = o.scale or 0.88 }, QUAD, OUT)
		if o.sound then
			UiFx.sound(o.sound)
		end
		-- Палец мог уйти с кнопки: отпускание ловим и вне её.
		inputEnded = UserInputService.InputEnded:Connect(function(input: InputObject)
			local kind = input.UserInputType
			if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
				release()
			end
		end)
	end)
	local up = button.MouseButton1Up:Connect(release)
	local leave = button.MouseLeave:Connect(release)
	return function()
		down:Disconnect()
		up:Disconnect()
		leave:Disconnect()
		release()
		scale.Scale = 1
	end
end

export type PopOptions = {
	from: number?, -- начальный масштаб (0)
	time: number?, -- 0.3
	delay: number?, -- задержка (для «лесенки»)
	rotate: number?, -- начальный поворот, градусы (например −6)
}

-- Выскакивание: масштаб from → 1 с перелётом (Back Out), по желанию с доворотом.
function UiFx.popIn(gui: GuiObject, opts: PopOptions?)
	local o: PopOptions = opts or {}
	local time = o.time or 0.3
	local scale = UiFx.scaleOf(gui)
	scale.Scale = o.from or 0
	tween(scale, time, { Scale = 1 }, BACK, OUT, o.delay)
	if o.rotate and o.rotate ~= 0 then
		local motion = beginMotion(rotations, gui, gui.Rotation)
		gui.Rotation = motion.rest + o.rotate
		tween(gui, time, { Rotation = motion.rest }, BACK, OUT, o.delay)
		table.insert(
			motion.threads,
			task.delay(time + (o.delay or 0), function()
				rotations[gui] = nil
			end)
		)
	end
end

export type PopOutOptions = {
	time: number?, -- 0.2
	to: number?, -- конечный масштаб (0)
	destroy: boolean?, -- удалить элемент в конце
	hide: boolean?, -- спрятать (Visible = false) и вернуть масштаб 1
}

-- Исчезновение: масштаб → to (Back In), потом удалить или спрятать.
function UiFx.popOut(gui: GuiObject, opts: PopOutOptions?)
	local o: PopOutOptions = opts or {}
	local time = o.time or 0.2
	local scale = UiFx.scaleOf(gui)
	tween(scale, time, { Scale = o.to or 0 }, BACK, IN)
	task.delay(time, function()
		if o.destroy then
			gui:Destroy()
		elseif o.hide then
			gui.Visible = false
			scale.Scale = 1
		end
	end)
end

-- «Подпрыгнуть»: резко увеличиться и пружинисто вернуться (счётчики, награды).
function UiFx.bump(gui: GuiObject, peak: number?, time: number?)
	local scale = UiFx.scaleOf(gui)
	scale.Scale = peak or 1.22
	tween(scale, time or 0.3, { Scale = 1 }, BACK, OUT)
end

-- «Удар»: влетает огромным (2.2) и с перелётом садится на место, потом лёгкая тряска.
function UiFx.slam(gui: GuiObject, from: number?, time: number?)
	local duration = time or 0.35
	local scale = UiFx.scaleOf(gui)
	scale.Scale = from or 2.2
	tween(scale, duration, { Scale = 1 }, BACK, OUT)
	task.delay(duration * 0.55, function()
		UiFx.shake(gui, 0.012, 0.22)
	end)
end

-- «Печать»: падает сверху крупной и с поворотом (бейджи, «НОВАЯ!»).
function UiFx.stamp(gui: GuiObject, rotate: number?, time: number?)
	local duration = time or 0.3
	local scale = UiFx.scaleOf(gui)
	scale.Scale = 3
	tween(scale, duration, { Scale = 1 }, BACK, OUT)
	local motion = beginMotion(rotations, gui, gui.Rotation)
	gui.Rotation = motion.rest + (rotate or -16)
	tween(gui, duration, { Rotation = motion.rest }, BACK, OUT)
	table.insert(
		motion.threads,
		task.delay(duration, function()
			rotations[gui] = nil
		end)
	)
end

-- Бесконечный «пульс» масштаба 1 ↔ peak. Возвращает stop.
function UiFx.pulse(gui: GuiObject, peak: number?, period: number?): Stop
	local scale = UiFx.scaleOf(gui)
	scale.Scale = 1
	local info = TweenInfo.new((period or 0.8) / 2, SINE, INOUT, -1, true)
	local looping = TweenService:Create(scale, info, { Scale = peak or 1.08 })
	looping:Play()
	return function()
		looping:Cancel()
		scale.Scale = 1
	end
end

-- Покачивание ±angle° (по умолчанию 6°, 3 качания за 0.4 с), затухающее.
function UiFx.wiggle(gui: GuiObject, angle: number?, swings: number?, time: number?)
	local amplitude = angle or 6
	local halfSwings = (swings or 3) * 2
	local stepTime = (time or 0.4) / (halfSwings + 1)
	local motion = beginMotion(rotations, gui, gui.Rotation)
	local rest: number = motion.rest
	for index = 1, halfSwings do
		local sign = if index % 2 == 1 then 1 else -1
		local target = rest + sign * amplitude * (1 - (index - 1) / halfSwings)
		if index == 1 then
			tween(gui, stepTime, { Rotation = target }, SINE, INOUT)
		else
			table.insert(
				motion.threads,
				task.delay(stepTime * (index - 1), function()
					tween(gui, stepTime, { Rotation = target }, SINE, INOUT)
				end)
			)
		end
	end
	table.insert(
		motion.threads,
		task.delay(stepTime * halfSwings, function()
			tween(gui, stepTime, { Rotation = rest }, SINE, OUT)
			rotations[gui] = nil
		end)
	)
end

-- Тряска позиции ±amount (доля родителя, по умолчанию 1.5 %), затухающая за time (0.25 с).
function UiFx.shake(gui: GuiObject, amount: number?, time: number?)
	local size = amount or 0.015
	local steps = 6
	local stepTime = (time or 0.25) / steps
	local motion = beginMotion(positions, gui, gui.Position)
	local rest: UDim2 = motion.rest
	for index = 1, steps do
		local k = 1 - (index - 1) / steps
		local target = if index == steps
			then rest
			else rest + UDim2.fromScale(rng:NextNumber(-size, size) * k, rng:NextNumber(-size, size) * k)
		local function move()
			tween(gui, stepTime, { Position = target }, SINE, OUT)
			if index == steps then
				positions[gui] = nil
			end
		end
		if index == 1 then
			move()
		else
			table.insert(motion.threads, task.delay(stepTime * (index - 1), move))
		end
	end
end

--------------------------------------------------------------------------------
-- Блик, кольца, лучи
--------------------------------------------------------------------------------

local function makeShine(face: GuiObject): Frame
	local frame = Instance.new("Frame")
	frame.Name = "Shine"
	frame.BackgroundColor3 = WHITE
	frame.BorderSizePixel = 0
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = 10
	copyCorner(face, frame)
	local band = Instance.new("UIGradient")
	band.Name = "Band"
	band.Rotation = 20
	band.Offset = Vector2.new(-1, 0)
	band.Transparency = SHINE_BAND
	band.Parent = frame
	frame.Parent = face
	return frame
end

--[[
	Блик: белая косая полоса проходит по элементу (по лицевой стороне конфеты) за time (0.6 с).
	Слой во весь размер с тем же скруглением — блик не вылезает за круглые углы. У конфет слой
	Shine готов в сборщике; у других элементов создаётся на время блика.
]]
function UiFx.shine(gui: GuiObject, time: number?)
	local duration = time or 0.6
	local face = UiFx.faceOf(gui)
	local found = face:FindFirstChild("Shine")
	local overlay: GuiObject
	local temporary = false
	if found and found:IsA("GuiObject") then
		overlay = found
	else
		overlay = makeShine(face)
		temporary = true
	end
	local band = overlay:FindFirstChild("Band")
	if band and band:IsA("UIGradient") then
		band.Offset = Vector2.new(-1, 0)
		tween(band, duration, { Offset = Vector2.new(1, 0) }, QUAD, INOUT)
	end
	if temporary then
		task.delay(duration + 0.05, function()
			overlay:Destroy()
		end)
	end
end

export type ShineLoopOptions = {
	interval: number?, -- секунд между бликами (UIConfig.Fx.ShineInterval)
	time: number?, -- длительность блика
	delay: number?, -- первый блик (по умолчанию — случайно в пределах интервала)
	when: (() -> boolean)?, -- блестеть, только если вернёт true
}

-- Блик раз в interval секунд, пока элемент виден. Таймеры, без соединений. Возвращает stop.
function UiFx.shineLoop(gui: GuiObject, opts: ShineLoopOptions?): Stop
	local o: ShineLoopOptions = opts or {}
	local interval = o.interval or Fx.ShineInterval
	local running = true
	local pending: thread? = nil
	local function tick()
		pending = nil
		if not running then
			return
		end
		if gui.Parent == nil then
			running = false
			return
		end
		if gui.Visible and (o.when == nil or o.when()) then
			UiFx.shine(gui, o.time)
		end
		pending = task.delay(interval, tick)
	end
	pending = task.delay(o.delay or interval * rng:NextNumber(0.35, 1), tick)
	return function()
		running = false
		local thread = pending
		pending = nil
		if thread and coroutine.status(thread) == "suspended" then
			pcall(task.cancel, thread)
		end
	end
end

export type RingOptions = {
	color: Color3?, -- цвет (белый)
	time: number?, -- 0.6
	scale: number?, -- во сколько раз вырастает (1.5)
	thickness: number?, -- толщина кольца, px (4)
	filled: boolean?, -- залитая копия формы вместо кольца (видна позади конфеты)
	loop: boolean?, -- повторять до stop()
	interval: number?, -- пауза между кольцами при loop
	z: number?, -- ZIndex (0: позади Lip/Face конфеты)
}

local function oneRing(gui: GuiObject, o: RingOptions)
	local time = o.time or 0.6
	local grow = o.scale or 1.5
	local ring = Instance.new("Frame")
	ring.Name = "FxRing"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BorderSizePixel = 0
	ring.ZIndex = o.z or 0
	copyCorner(gui, ring)
	local color = o.color or WHITE
	local stroke: UIStroke? = nil
	if o.filled then
		ring.BackgroundColor3 = color
		ring.BackgroundTransparency = 0.3
	else
		ring.BackgroundTransparency = 1
		local s = Instance.new("UIStroke")
		s.Color = color
		s.Thickness = o.thickness or 4
		s.Transparency = 0.1
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s:SetAttribute("BaseThickness", o.thickness or 4)
		s.Parent = ring
		stroke = s
	end
	ring.Parent = gui
	if o.filled then
		tween(ring, time, { Size = UDim2.fromScale(grow, grow), BackgroundTransparency = 1 }, QUAD, OUT)
	else
		tween(ring, time, { Size = UDim2.fromScale(grow, grow) }, QUAD, OUT)
	end
	if stroke then
		tween(stroke, time, { Transparency = 1 }, QUAD, IN)
	end
	task.delay(time, function()
		ring:Destroy()
	end)
end

-- Расходящееся кольцо (или залитая копия формы) вокруг элемента. С loop — повторяется до stop.
function UiFx.glowRing(gui: GuiObject, opts: RingOptions?): Stop
	local o: RingOptions = opts or {}
	oneRing(gui, o)
	if not o.loop then
		return noop
	end
	local running = true
	local pending: thread? = nil
	local gap = o.interval or ((o.time or 0.6) + 0.25)
	local function tick()
		pending = nil
		if not running or gui.Parent == nil then
			running = false
			return
		end
		if gui.Visible then
			oneRing(gui, o)
		end
		pending = task.delay(gap, tick)
	end
	pending = task.delay(gap, tick)
	return function()
		running = false
		local thread = pending
		pending = nil
		if thread and coroutine.status(thread) == "suspended" then
			pcall(task.cancel, thread)
		end
	end
end

-- Одиночная «рябь» от касания (кольцо 1 → 1.35 за 0.4 с).
function UiFx.ripple(gui: GuiObject, color: Color3?)
	oneRing(gui, { color = color, time = 0.4, scale = 1.35, thickness = 3 })
end

export type RaysOptions = {
	colors: { Color3 }?, -- чередующиеся цвета лучей (белый / золотой)
	count: number?, -- лучей (14)
	speed: number?, -- градусов в секунду (20)
	size: number?, -- диаметр в высотах элемента (2.6)
	width: number?, -- толщина луча (доля диаметра, 0.075)
	transparency: number?, -- прозрачность лучей (0.3)
	glow: boolean?, -- мягкое свечение в центре (true)
	z: number?, -- ZIndex (0: позади конфеты; для прочих элементов ставьте лучи в отдельный слой позади)
}

--[[
	«Солнышко» за элементом: лучи от центра (чередуются цвета, каждый — яркая сердцевина и
	широкий мягкий ореол, к концу тают) и круглое свечение; медленно вращается и «дышит».
	Только твины (без соединений). Возвращает stop (лучи удаляются).
]]
function UiFx.rays(gui: GuiObject, opts: RaysOptions?): Stop
	local o: RaysOptions = opts or {}
	local colors = o.colors or { WHITE, Palette.Gold.Top }
	local count = math.max(4, o.count or 14)
	local size = o.size or 2.6
	local alpha = o.transparency or 0.3
	local width = o.width or 0.075
	local holder = Instance.new("Frame")
	holder.Name = "FxRays"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.SizeConstraint = Enum.SizeConstraint.RelativeYY
	holder.Size = UDim2.fromScale(size, size)
	holder.ZIndex = o.z or 0

	-- Вдоль луча (снаружи → к центру): снаружи тает, у центра чуть прозрачнее (там сам элемент).
	local function fade(base: number): NumberSequence
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, base),
			NumberSequenceKeypoint.new(1, math.min(1, base + 0.25)),
		})
	end
	local core = fade(alpha)
	local halo = fade(math.min(1, alpha + 0.45))

	local function disc(name: string, scale: number, transparency: number, color: Color3)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		frame.Size = UDim2.fromScale(scale, scale)
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = transparency
		frame.BorderSizePixel = 0
		frame.ZIndex = holder.ZIndex
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
		frame.Parent = holder
	end
	if o.glow ~= false then
		disc("GlowOuter", 0.62, 0.78, colors[1])
		disc("GlowInner", 0.38, 0.55, colors[1])
	end

	-- Луч — прямоугольник от центра наружу: центр на половине радиуса, повёрнут по направлению.
	local function ray(index: number, name: string, thickness: number, sequence: NumberSequence)
		local angle = (index - 1) * 360 / count
		local radians = math.rad(angle)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5 + 0.25 * math.sin(radians), 0.5 - 0.25 * math.cos(radians))
		frame.Size = UDim2.fromScale(thickness, 0.5)
		frame.Rotation = angle
		frame.BackgroundColor3 = colors[(index - 1) % #colors + 1]
		frame.BorderSizePixel = 0
		frame.ZIndex = holder.ZIndex
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = sequence
		gradient.Parent = frame
		frame.Parent = holder
	end
	for index = 1, count do
		ray(index, `Halo{index}`, width * 2.2, halo)
		ray(index, `Ray{index}`, width, core)
	end

	holder.Parent = gui
	UiFx.popIn(holder, { time = 0.4 })
	local spin = TweenService:Create(
		holder,
		TweenInfo.new(360 / math.max(o.speed or 20, 1), LINEAR, OUT, -1),
		{ Rotation = 360 }
	)
	spin:Play()
	local breathe: Stop = noop
	local alive = true
	task.delay(0.4, function()
		if alive and holder.Parent then
			breathe = UiFx.pulse(holder, 1.06, 2.4)
		end
	end)
	return function()
		alive = false
		spin:Cancel()
		breathe()
		holder:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Частицы: конфетти и искры (покадрово, общий планировщик)
--------------------------------------------------------------------------------

local liveConfetti = 0

-- Высота экрана (слоя ScreenGui) — мера размеров частиц, чтобы они были одинаковыми в любом контейнере.
local function screenUnit(container: GuiBase2d): number
	local layer: Instance? = if container:IsA("LayerCollector")
		then container
		else container:FindFirstAncestorWhichIsA("LayerCollector")
	if layer and layer:IsA("GuiBase2d") and layer.AbsoluteSize.Y > 1 then
		return layer.AbsoluteSize.Y
	end
	local size = container.AbsoluteSize
	return math.max(math.min(size.X, size.Y), 1)
end

type Particle = {
	frame: Frame,
	x: number,
	y: number,
	vx: number,
	vy: number,
	rot: number,
	spin: number,
	flip: number,
	flipSpeed: number,
	sway: number,
	w: number,
	h: number,
	life: number,
	done: boolean,
}

export type ConfettiOptions = {
	count: number?, -- сколько (40; на тач-устройствах не больше 40, иначе 60 — на все залпы сразу)
	colors: { Color3 }?, -- цвета (UIConfig.Confetti)
	origin: Vector2?, -- точка вылета в долях контейнера (0.5, 0.5)
	spread: number?, -- разлёт, градусы вокруг «вверх» (80; 360 — во все стороны)
	power: number?, -- сила залпа (1)
	duration: number?, -- жизнь, с (2)
	z: number?, -- ZIndex слоя (50)
}

-- Предел конфетти на этом устройстве (одновременно, все залпы вместе).
function UiFx.confettiCap(): number
	return if UserInputService.TouchEnabled then Fx.ConfettiMaxTouch else Fx.ConfettiMax
end

-- Сколько конфетти живёт сейчас.
function UiFx.liveConfetti(): number
	return liveConfetti
end

--[[
	Конфетти: квадратики и полоски взлетают из origin, кувыркаются, падают с «парашютом» и
	тают в последние 30 % жизни. container — GuiObject или ScreenGui (координаты в его долях).
	Возвращает stop (всё удаляется сразу).
]]
function UiFx.confetti(container: GuiBase2d, opts: ConfettiOptions?): Stop
	local o: ConfettiOptions = opts or {}
	local count = math.min(o.count or 40, UiFx.confettiCap() - liveConfetti)
	if count <= 0 then
		return noop
	end
	local area = container.AbsoluteSize
	local width, height = math.max(area.X, 1), math.max(area.Y, 1)
	local unit = screenUnit(container)
	local colors = o.colors or UIConfig.Confetti
	local origin = o.origin or Vector2.new(0.5, 0.5)
	local spread = math.rad(o.spread or 80)
	local power = o.power or 1
	local duration = o.duration or 2
	local gravity = unit * 2.4
	local terminal = unit * 0.42

	local holder = Instance.new("Frame")
	holder.Name = "FxConfetti"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = o.z or 50

	local particles: { Particle } = {}
	for _ = 1, count do
		local strip = rng:NextNumber() < 0.45
		local w = unit * (if strip then 0.011 else 0.019) * rng:NextNumber(0.8, 1.25)
		local h = unit * (if strip then 0.032 else 0.019) * rng:NextNumber(0.8, 1.25)
		local angle = -math.pi / 2 + rng:NextNumber(-0.5, 0.5) * spread
		local speed = unit * power * rng:NextNumber(0.9, 1.9)
		local frame = Instance.new("Frame")
		frame.Name = "Piece"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = colors[rng:NextInteger(1, #colors)]
		frame.ZIndex = holder.ZIndex
		local particle: Particle = {
			frame = frame,
			x = origin.X * width,
			y = origin.Y * height,
			vx = math.cos(angle) * speed,
			vy = math.sin(angle) * speed,
			rot = rng:NextNumber(0, 360),
			spin = rng:NextNumber(-540, 540),
			flip = rng:NextNumber(0, math.pi * 2),
			flipSpeed = rng:NextNumber(6, 14),
			sway = rng:NextNumber(0, math.pi * 2),
			w = w,
			h = h,
			life = duration * rng:NextNumber(0.7, 1),
			done = false,
		}
		frame.Size = UDim2.fromScale(w / width, h / height)
		frame.Position = UDim2.fromScale(particle.x / width, particle.y / height)
		frame.Rotation = particle.rot
		frame.Parent = holder
		table.insert(particles, particle)
	end
	holder.Parent = container
	liveConfetti += count

	local elapsed = 0
	return UiFx.schedule(function(dt: number): boolean
		elapsed += dt
		local alive = false
		local drag = math.max(0, 1 - 1.4 * dt)
		for _, p in particles do
			if not p.done then
				if elapsed >= p.life then
					p.done = true
					p.frame:Destroy()
				else
					alive = true
					p.vx *= drag
					p.vy = math.min(p.vy + gravity * dt, terminal)
					p.x += (p.vx + math.sin(elapsed * 5 + p.sway) * unit * 0.06) * dt
					p.y += p.vy * dt
					p.rot += p.spin * dt
					p.flip += p.flipSpeed * dt
					local k = elapsed / p.life
					local frame = p.frame
					frame.Position = UDim2.fromScale(p.x / width, p.y / height)
					frame.Rotation = p.rot
					frame.Size = UDim2.fromScale(p.w * (0.25 + 0.75 * math.abs(math.cos(p.flip))) / width, p.h / height)
					frame.BackgroundTransparency = if k > 0.7 then (k - 0.7) / 0.3 else 0
				end
			end
		end
		return alive
	end, function()
		liveConfetti -= count
		holder:Destroy()
	end)
end

export type BurstOptions = {
	count: number?, -- искр (12)
	colors: { Color3 }?, -- цвета (белый, золото)
	origin: Vector2?, -- центр в долях контейнера (0.5, 0.5)
	power: number?, -- дальность (1)
	time: number?, -- 0.55 с
	z: number?, -- ZIndex (40)
}

-- Взрыв искр во все стороны (попадание в зону, награда): круглые точки разлетаются и гаснут.
function UiFx.burst(container: GuiBase2d, opts: BurstOptions?): Stop
	local o: BurstOptions = opts or {}
	local area = container.AbsoluteSize
	local width, height = math.max(area.X, 1), math.max(area.Y, 1)
	local unit = screenUnit(container)
	local count = math.min(o.count or 12, 24)
	local colors = o.colors or { WHITE, Palette.Gold.Top, Palette.Sun.Top }
	local origin = o.origin or Vector2.new(0.5, 0.5)
	local life = o.time or 0.55
	local holder = Instance.new("Frame")
	holder.Name = "FxBurst"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = o.z or 40
	local sparks: { { frame: Frame, x: number, y: number, vx: number, vy: number, size: number } } = {}
	for index = 1, count do
		local angle = (index / count) * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
		local speed = unit * 0.55 * (o.power or 1) * rng:NextNumber(0.8, 1.3)
		local size = unit * rng:NextNumber(0.011, 0.019)
		local frame = Instance.new("Frame")
		frame.Name = "Spark"
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.BorderSizePixel = 0
		frame.BackgroundColor3 = colors[rng:NextInteger(1, #colors)]
		frame.ZIndex = holder.ZIndex
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
		local x, y = origin.X * width, origin.Y * height
		frame.Position = UDim2.fromScale(x / width, y / height)
		frame.Size = UDim2.fromScale(size / width, size / height)
		frame.Parent = holder
		table.insert(
			sparks,
			{ frame = frame, x = x, y = y, vx = math.cos(angle) * speed, vy = math.sin(angle) * speed, size = size }
		)
	end
	holder.Parent = container
	local elapsed = 0
	return UiFx.schedule(function(dt: number): boolean
		elapsed += dt
		local k = math.min(1, elapsed / life)
		local drag = math.max(0, 1 - 5 * dt)
		for _, s in sparks do
			s.vx *= drag
			s.vy *= drag
			s.x += s.vx * dt
			s.y += s.vy * dt
			local size = s.size * (1 - k * 0.7)
			s.frame.Position = UDim2.fromScale(s.x / width, s.y / height)
			s.frame.Size = UDim2.fromScale(size / width, size / height)
			s.frame.BackgroundTransparency = k * k
		end
		return k < 1
	end, function()
		holder:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Звёздочки вокруг, всплывающий текст
--------------------------------------------------------------------------------

export type SparkleOptions = {
	icons: { string }?, -- {"✨", "⭐"}
	rate: number?, -- в секунду (5)
	size: number?, -- размер в высотах элемента (0.45)
	area: number?, -- насколько выходить за края (0.18)
	duration: number?, -- сами остановятся через столько секунд
	z: number?, -- ZIndex (8)
}

--[[
	✨ / ⭐ то тут, то там по краям элемента: выскакивают, поворачиваются и гаснут. Таймеры и твины,
	без соединений. Возвращает stop (живые звёздочки удаляются сразу).
]]
function UiFx.sparkles(gui: GuiObject, opts: SparkleOptions?): Stop
	local o: SparkleOptions = opts or {}
	local icons = o.icons or { "✨", "⭐" }
	local rate = math.max(o.rate or 5, 0.5)
	local size = o.size or 0.45
	local area = o.area or 0.18
	local running = true
	local pending: thread? = nil
	local live: { [TextLabel]: boolean } = {}

	local function stop()
		running = false
		local thread = pending
		pending = nil
		if thread and coroutine.status(thread) == "suspended" then
			pcall(task.cancel, thread)
		end
		for label in live do
			label:Destroy()
		end
		table.clear(live)
	end

	local function spawnOne()
		local x, y
		if rng:NextNumber() < 0.5 then
			x = rng:NextNumber(-area, 1 + area)
			y = if rng:NextNumber() < 0.5 then rng:NextNumber(-area, 0.12) else rng:NextNumber(0.88, 1 + area)
		else
			y = rng:NextNumber(-area, 1 + area)
			x = if rng:NextNumber() < 0.5
				then rng:NextNumber(-area * 0.6, 0.08)
				else rng:NextNumber(0.92, 1 + area * 0.6)
		end
		local label = Instance.new("TextLabel")
		label.Name = "FxSparkle"
		label.BackgroundTransparency = 1
		label.Text = icons[rng:NextInteger(1, #icons)]
		label.TextScaled = true
		label.FontFace = FONT
		label.TextColor3 = WHITE
		label.AnchorPoint = Vector2.new(0.5, 0.5)
		label.Position = UDim2.fromScale(x, y)
		label.SizeConstraint = Enum.SizeConstraint.RelativeYY
		local s = size * rng:NextNumber(0.7, 1.15)
		label.Size = UDim2.fromScale(s, s)
		label.Rotation = rng:NextNumber(-25, 25)
		label.ZIndex = o.z or 8
		local scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = label
		label.Parent = gui
		live[label] = true
		tween(scale, 0.22, { Scale = 1 }, BACK, OUT)
		tween(label, 0.62, { Rotation = label.Rotation + rng:NextNumber(25, 60) }, LINEAR, OUT)
		task.delay(0.38, function()
			tween(scale, 0.24, { Scale = 0 }, QUAD, IN)
		end)
		task.delay(0.64, function()
			live[label] = nil
			label:Destroy()
		end)
	end

	local function tick()
		pending = nil
		if not running then
			return
		end
		if gui.Parent == nil then
			stop()
			return
		end
		if gui.Visible then
			spawnOne()
		end
		pending = task.delay(rng:NextNumber(0.6, 1.4) / rate, tick)
	end
	tick()
	if o.duration then
		task.delay(o.duration, function()
			if running then
				running = false
				local thread = pending
				pending = nil
				if thread and coroutine.status(thread) == "suspended" then
					pcall(task.cancel, thread)
				end
			end
		end)
	end
	return stop
end

export type FloatOptions = {
	position: UDim2?, -- откуда (центр контейнера)
	size: UDim2?, -- размер надписи (0.5 × 0.2 контейнера)
	color: Color3?, -- цвет текста (белый)
	colors: { Color3 }?, -- градиент текста {верх, низ} вместо цвета
	rise: number?, -- на сколько подняться (доля контейнера, 0.08)
	time: number?, -- 0.8 с
	rotate: number?, -- поворот (случайно ±6°)
	z: number?, -- ZIndex (20)
}

-- «ОТЛИЧНО!», «+1 🐟»: выскакивает, поднимается и тает. Возвращает надпись (удалится сама).
function UiFx.floatText(container: GuiBase2d, text: string, opts: FloatOptions?): TextLabel
	local o: FloatOptions = opts or {}
	local time = o.time or 0.8
	local start = o.position or UDim2.fromScale(0.5, 0.5)
	local label = Instance.new("TextLabel")
	label.Name = "FxFloat"
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.FontFace = FONT
	label.TextColor3 = o.color or WHITE
	label.TextStrokeTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = start
	label.Size = o.size or UDim2.fromScale(0.5, 0.2)
	label.Rotation = o.rotate or rng:NextNumber(-6, 6)
	label.ZIndex = o.z or 20
	local outline = Instance.new("UIStroke")
	outline.Name = "Outline"
	outline.Color = INK
	outline.Thickness = 2.5
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline:SetAttribute("BaseThickness", 2.5)
	outline.Parent = label
	if o.colors and #o.colors > 0 then
		local gradient = Instance.new("UIGradient")
		gradient.Name = "TextFill"
		gradient.Rotation = 90
		gradient.Color = UiFx.sequence(o.colors)
		gradient.Parent = label
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 0.4
	scale.Parent = label
	label.Parent = container
	tween(scale, 0.2, { Scale = 1 }, BACK, OUT)
	tween(label, time, { Position = start - UDim2.fromScale(0, o.rise or 0.08) }, QUAD, OUT)
	tween(label, time * 0.5, { TextTransparency = 1 }, QUAD, IN, time * 0.5)
	tween(outline, time * 0.5, { Transparency = 1 }, QUAD, IN, time * 0.5)
	task.delay(time + 0.05, function()
		label:Destroy()
	end)
	return label
end

--------------------------------------------------------------------------------
-- Счётчики, радуга, полоски, вспышка, полёт значка, шлейф, тряска камеры
--------------------------------------------------------------------------------

-- Число «набегает» от from до to за time (0.8 с, Quad Out). format — функция или "%d" и т.п.
function UiFx.countUp(
	label: GuiObject,
	from: number,
	to: number,
	time: number?,
	format: ((value: number) -> string) | string | nil
): Stop
	local duration = math.max(time or 0.8, 0.01)
	local function render(value: number): string
		local whole = math.floor(value + 0.5)
		if type(format) == "function" then
			return format(whole)
		elseif type(format) == "string" then
			return string.format(format, whole)
		end
		return tostring(whole)
	end
	local target = label :: any
	target.Text = render(from)
	local elapsed = 0
	return UiFx.schedule(function(dt: number): boolean
		elapsed += dt
		local k = math.min(1, elapsed / duration)
		local eased = 1 - (1 - k) * (1 - k)
		target.Text = render(from + (to - from) * eased)
		return k < 1
	end, function()
		target.Text = render(to)
	end)
end

export type RainbowOptions = {
	speed: number?, -- оборотов цвета в секунду (0.35)
	colors: { Color3 }?, -- цвета (UIConfig.Rainbow)
	spin: number?, -- ещё и вращать градиент, градусов в секунду
}

-- Радуга: цвета градиента бегут по кругу (Mythic, мутация «Радужная»). Возвращает stop.
function UiFx.rainbow(gradient: UIGradient, opts: RainbowOptions?): Stop
	local o: RainbowOptions = opts or {}
	local colors = o.colors or UIConfig.Rainbow
	local count = #colors
	local speed = o.speed or 0.35
	local original = gradient.Color
	local originalRotation = gradient.Rotation
	local points = math.min(count * 2, 18)
	local phase = 0
	local sinceApply = 0
	local function sample(t: number): Color3
		local x = (t % 1) * count
		local index = math.floor(x)
		return colors[index % count + 1]:Lerp(colors[(index + 1) % count + 1], x - index)
	end
	local function apply()
		local keypoints: { ColorSequenceKeypoint } = {}
		for index = 0, points do
			local t = index / points
			table.insert(keypoints, ColorSequenceKeypoint.new(t, sample(t + phase)))
		end
		gradient.Color = ColorSequence.new(keypoints)
	end
	apply()
	return UiFx.schedule(function(dt: number): boolean
		if gradient.Parent == nil then
			return false
		end
		phase += dt * speed
		sinceApply += dt
		if o.spin then
			gradient.Rotation = (gradient.Rotation + o.spin * dt) % 360
		end
		if sinceApply >= 1 / 30 then
			sinceApply = 0
			apply()
		end
		return true
	end, function()
		gradient.Color = original
		gradient.Rotation = originalRotation
	end)
end

-- Полоса-таймер: ширина тает от полной до 0 за duration, цвет идёт зелёный → жёлтый → красный.
function UiFx.timerBar(fill: GuiObject, duration: number, colors: { Color3 }?): Stop
	local list = colors or { Palette.Leaf.Top, Palette.Sun.Top, Palette.Berry.Bottom }
	local base = fill.Size
	local total = math.max(duration, 0.01)
	local elapsed = 0
	local function apply(k: number)
		fill.Size = UDim2.new(base.X.Scale * (1 - k), base.X.Offset, base.Y.Scale, base.Y.Offset)
		fill.BackgroundColor3 = sampleColors(list, k)
	end
	apply(0)
	return UiFx.schedule(function(dt: number): boolean
		elapsed += dt
		local k = math.min(1, elapsed / total)
		apply(k)
		return k < 1
	end)
end

-- Вспышка на весь экран (цвет 0.6 → прозрачно за 0.25 с); не чаще 3 раз в секунду.
local lastFlash = -math.huge
function UiFx.flash(layer: GuiBase2d, color: Color3?, time: number?)
	local now = os.clock()
	if now - lastFlash < Fx.FlashMinInterval then
		return
	end
	lastFlash = now
	local frame = Instance.new("Frame")
	frame.Name = "FxFlash"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1.6, 2) -- с запасом: закрывает и вырезы экрана
	frame.BackgroundColor3 = color or WHITE
	frame.BackgroundTransparency = 0.6
	frame.BorderSizePixel = 0
	frame.ZIndex = 100
	frame.Parent = layer
	local duration = time or 0.25
	tween(frame, duration, { BackgroundTransparency = 1 }, QUAD, OUT)
	task.delay(duration + 0.02, function()
		frame:Destroy()
	end)
end

export type FlyOptions = {
	text: string?, -- значок ("🐟")
	time: number?, -- 0.6 с
	size: number?, -- размер в высотах слоя (0.09)
	arc: number?, -- высота дуги (доля высоты слоя, 0.22)
	onArrive: (() -> ())?, -- на месте (например, UiFx.bump(счётчика))
}

-- Значок летит по дуге от одного элемента к другому (рыба из карточки в счётчик улова).
function UiFx.flyTo(layer: GuiBase2d, from: GuiObject, to: GuiObject, opts: FlyOptions?): Stop
	local o: FlyOptions = opts or {}
	local base = layer.AbsolutePosition
	local area = layer.AbsoluteSize
	local width, height = math.max(area.X, 1), math.max(area.Y, 1)
	local a = from.AbsolutePosition + from.AbsoluteSize / 2 - base
	local b = to.AbsolutePosition + to.AbsoluteSize / 2 - base
	local c = (a + b) / 2 - Vector2.new(0, height * (o.arc or 0.22))
	local duration = o.time or 0.6
	local icon = Instance.new("TextLabel")
	icon.Name = "FxFly"
	icon.BackgroundTransparency = 1
	icon.Text = o.text or "🐟"
	icon.TextScaled = true
	icon.FontFace = FONT
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
	local size = o.size or 0.09
	icon.Size = UDim2.fromScale(size, size)
	icon.Position = UDim2.fromScale(a.X / width, a.Y / height)
	icon.ZIndex = 60
	icon.Parent = layer
	local elapsed = 0
	local arrived = false
	return UiFx.schedule(function(dt: number): boolean
		elapsed += dt
		local k = math.min(1, elapsed / duration)
		local e = if k < 0.5 then 2 * k * k else 1 - (-2 * k + 2) ^ 2 / 2
		local p = a:Lerp(c, e):Lerp(c:Lerp(b, e), e)
		icon.Position = UDim2.fromScale(p.X / width, p.Y / height)
		icon.Rotation = -20 + 40 * e
		local s = size * (1 + 0.35 * math.sin(math.pi * e) - 0.35 * e)
		icon.Size = UDim2.fromScale(s, s)
		if k >= 1 and not arrived then
			arrived = true
			if o.onArrive then
				task.spawn(o.onArrive)
			end
		end
		return k < 1
	end, function()
		icon:Destroy()
	end)
end

export type TrailOptions = {
	count: number?, -- копий (3)
	lag: number?, -- отставание каждой копии, с (0.035)
	transparency: number?, -- прозрачность первой копии (0.55)
}

-- «Шлейф»: полупрозрачные копии элемента догоняют его (стрелка мини-игры). Возвращает stop.
function UiFx.trail(gui: GuiObject, opts: TrailOptions?): Stop
	local o: TrailOptions = opts or {}
	local count = o.count or 3
	local lag = o.lag or 0.035
	local first = o.transparency or 0.55
	local parent = gui.Parent
	if not parent then
		return noop
	end
	local ghosts: { Frame } = {}
	for index = 1, count do
		local ghost = Instance.new("Frame")
		ghost.Name = "FxGhost"
		ghost.AnchorPoint = gui.AnchorPoint
		ghost.Size = gui.Size
		ghost.Position = gui.Position
		ghost.BackgroundColor3 = gui.BackgroundColor3
		ghost.BackgroundTransparency = first + (1 - first) * (index - 1) / count
		ghost.BorderSizePixel = 0
		ghost.ZIndex = math.max(gui.ZIndex - 1, 0)
		copyCorner(gui, ghost)
		ghost.Parent = parent
		table.insert(ghosts, ghost)
	end
	local history: { { t: number, p: UDim2 } } = {}
	local elapsed = 0
	return UiFx.schedule(function(dt: number): boolean
		if gui.Parent == nil then
			return false
		end
		elapsed += dt
		table.insert(history, { t = elapsed, p = gui.Position })
		while #history > 2 and history[2].t < elapsed - lag * (count + 1) do
			table.remove(history, 1)
		end
		for index, ghost in ghosts do
			local want = elapsed - lag * index
			local chosen = history[1].p
			for _, entry in history do
				if entry.t <= want then
					chosen = entry.p
				else
					break
				end
			end
			ghost.Position = chosen
			ghost.Visible = gui.Visible
		end
		return true
	end, function()
		for _, ghost in ghosts do
			ghost:Destroy()
		end
	end)
end

-- Лёгкая тряска камеры (сдвиг без поворота, затухает за time). Возвращает stop.
local shakeCounter = 0
function UiFx.cameraShake(amplitude: number?, time: number?): Stop
	local camera = Workspace.CurrentCamera
	if not camera then
		return noop
	end
	shakeCounter += 1
	local name = `UiFxCameraShake{shakeCounter}`
	local duration = time or 0.45
	local size = amplitude or 0.25
	local elapsed = 0
	local seed = rng:NextNumber(0, 100)
	local bound = true
	local function unbind()
		if bound then
			bound = false
			pcall(function()
				RunService:UnbindFromRenderStep(name)
			end)
		end
	end
	RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		elapsed += dt
		local k = 1 - elapsed / duration
		if k <= 0 then
			unbind()
			return
		end
		local t = elapsed * 18
		local offset = Vector3.new(math.noise(t, seed), math.noise(seed, t), 0) * size * k
		camera.CFrame = camera.CFrame * CFrame.new(offset)
	end)
	return unbind
end

--------------------------------------------------------------------------------
-- Появление/исчезновение целиком, обводки под экран, «лесенка»
--------------------------------------------------------------------------------

-- Всё содержимое элемента плавно становится прозрачным (фон, текст, обводки).
function UiFx.fadeOut(gui: GuiObject, time: number?)
	local duration = time or 0.2
	local items: { Instance } = gui:GetDescendants()
	table.insert(items, gui)
	for _, item in items do
		if item:IsA("GuiObject") and item.BackgroundTransparency < 1 then
			tween(item, duration, { BackgroundTransparency = 1 }, QUAD, IN)
		end
		if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
			tween(item, duration, { TextTransparency = 1, TextStrokeTransparency = 1 }, QUAD, IN)
		elseif item:IsA("ImageLabel") or item:IsA("ImageButton") then
			tween(item, duration, { ImageTransparency = 1 }, QUAD, IN)
		elseif item:IsA("UIStroke") then
			tween(item, duration, { Transparency = 1 }, QUAD, IN)
		end
	end
end

--[[
	Обводки (UIStroke с атрибутом BaseThickness — их ставит Theme) нарисованы для экрана высотой
	720 px; здесь их толщина подгоняется под настоящий экран (телефон — тоньше, 4K — толще), в том
	числе у элементов, добавленных позже. Возвращает функцию отвязки.
]]
function UiFx.fitStrokes(root: Instance): Stop
	local camera = Workspace.CurrentCamera
	local factor = 1
	local function measure()
		local height = if camera then camera.ViewportSize.Y else Fx.StrokeHeight
		factor = if height > 1 then math.clamp(height / Fx.StrokeHeight, 0.65, 1.5) else 1
	end
	local function apply(item: Instance)
		if item:IsA("UIStroke") then
			local base = item:GetAttribute("BaseThickness")
			if typeof(base) == "number" then
				item.Thickness = math.max(1, math.floor(base * factor * 2 + 0.5) / 2)
			end
		end
	end
	local function applyAll()
		measure()
		for _, item in root:GetDescendants() do
			apply(item)
		end
	end
	applyAll()
	local added = root.DescendantAdded:Connect(apply)
	local resized = if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(applyAll) else nil
	return function()
		added:Disconnect()
		if resized then
			resized:Disconnect()
		end
	end
end

-- Вызвать fn(item, index) для каждого элемента с шагом gap секунд (по умолчанию 0.045).
function UiFx.stagger<T>(items: { T }, gap: number?, fn: (item: T, index: number) -> ())
	local step = gap or 0.045
	for index, item in items do
		if index == 1 then
			fn(item, index)
		else
			task.delay(step * (index - 1), fn, item, index)
		end
	end
end

return UiFx
