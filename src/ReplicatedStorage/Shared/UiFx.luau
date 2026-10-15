--!strict
--[[
	UiFx — «сочные» анимации интерфейса на клиенте: нажатия (сжатие, перелёт, «пинок» значка),
	наведение мыши, выскакивания и «удары», блики, вспышки ободка, кольца, лучи, конфетти, искры,
	всплывающий текст, счётчики и «слот-машина» чисел, «дыхание», подпрыгивания и покачивания,
	кружок «!», кольцо-таймер, радуга, вспышки, виньетка по краям экрана, «толчок» поля зрения
	камеры, звуки (с высотой тона и арпеджио редкости), подгонка обводок и шкалы текста под экран.
	Стиль и тайминги — tools/builder/gui/STYLE.md («Симулятор», UI v5), числа — UIConfig.Motion.

	Правила:
	  • Один общий планировщик (RenderStepped на клиенте, Heartbeat в остальных случаях) ведёт все
	    покадровые эффекты (конфетти, счётчики, радуга, полёт значков…) и ОТКЛЮЧАЕТСЯ, когда
	    ничего не идёт. Короткие эффекты и вся «жизнь в покое» (дыхание, подпрыгивания, кружок «!»,
	    блики) — только TweenService и цепочки task.delay, без соединений и покадровой работы.
	  • Каждый эффект сам удаляет свои временные объекты; каждый бесконечный эффект возвращает
	    функцию остановки (её можно положить в Trove: trove:Add(stop)); цепочка таймеров кончается
	    сама, когда элемент спрятан или удалён.
	  • Эффекты не перехватывают ввод (Active = false) и не меняют имена элементов (временные
	    объекты и UIScale зовутся Fx*).
	  • Кнопка «симулятора» (Theme.sim в сборщике, атрибут CandyStyle = "sim" | "glass"): прозрачный
	    корень → Lip (только толстая обводка в тёмный оттенок цвета) + лицевая сторона (атрибут
	    CandyFace, обычно "Face") с градиентом "Fill", светлым ободком Rim и спрятанным бликом
	    Shine. setCandy перекрашивает её (и переводит в «стекло» и обратно). Пупырок в интерфейсе
	    больше нет (они остались только на карте).
	  • У надписи может быть тень-близнец «<Имя>Shadow» (соседний элемент, Theme.label Shadow):
	    setText, popIn, bump, slam, punch и shake ведут её вместе с надписью.
	  • «Меньше движения» (UiFx.reducedMotion: настройка Roblox или setReducedMotion) учитывается
	    здесь, в одном месте: без перелётов, покачиваний и «жизни в покое», конфетти вдвое меньше.

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

-- Прозрачность «стекла» у цвета (UIConfig.Palette.Glass.Alpha); у обычных цветов — nil.
local function alphaOf(swatch: Swatch): number?
	local alpha = (swatch :: any).Alpha
	return if type(alpha) == "number" then alpha else nil
end

local Fx = UIConfig.Fx
local Palette = UIConfig.Palette
local WHITE = Color3.new(1, 1, 1)
local INK: Color3 = UIConfig.Ink
local SIM = UIConfig.Sim
local MOTION = UIConfig.Motion
-- Шрифт интерфейса (как Theme.FONT): Montserrat Heavy и его наклонный вариант (числа, «+1»).
local FONT = Font.new(UIConfig.Font.Family, Enum.FontWeight.Heavy)
local FONT_ITALIC = Font.new(UIConfig.Font.Family, Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local BACK = Enum.EasingStyle.Back
local QUAD = Enum.EasingStyle.Quad
local SINE = Enum.EasingStyle.Sine
local LINEAR = Enum.EasingStyle.Linear
local OUT = Enum.EasingDirection.Out
local IN = Enum.EasingDirection.In
local INOUT = Enum.EasingDirection.InOut
local BOUNCE = Enum.EasingStyle.Bounce

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
	ping = "rbxasset://sounds/electronicpingshort.wav", -- то же, что pop (ноты арпеджио)
	swoosh = "rbxasset://sounds/swoosh.wav",
	splash = "rbxasset://sounds/impact_water.mp3", -- на pitch 0.5 — «сердцебиение»
	swim = "rbxasset://sounds/action_swim.mp3",
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

local function swatchOf(look: string | Color3 | Swatch): Swatch?
	if typeof(look) == "Color3" then
		return UIConfig.swatchFor(look)
	elseif type(look) == "string" then
		return Palette[look]
	end
	return look :: Swatch
end

-- Тёмный цвет (Night, Coal, Glass): плашка, собранная «стеклом», в нём стеклом и остаётся.
local function isDark(swatch: Swatch): boolean
	local _, _, v = swatch.Top:ToHSV()
	return alphaOf(swatch) ~= nil or v < 0.42
end

--[[
	Перекрасить кнопку / плашку «симулятора» (Theme.sim):
	  токен палитры ("Leaf") или { Top, Bottom, Lip } — градиент лица Top → Bottom, обводка (Lip) —
	  тёмный оттенок того же цвета, лицо непрозрачно, светлый ободок виден;
	  Glass (или любой цвет с Alpha) — «стекло»: лицо — чёрное на Alpha прозрачности, без обводки и
	  ободка; плашка, собранная стеклом (атрибут CandyHome = "glass": подсказка, подпись кнопки),
	  остаётся стеклом и в тёмных цветах (Night, Coal), а в ярких (Sun, Berry) становится плашкой;
	  Color3 — произвольный цвет: чистая кнопка из него (UIConfig.swatchFor), без серого налёта.
	Цвет базы лучше брать из UIConfig.BaseSwatches (так делает HudController). Лицо снова белое
	(сбрасывает и затемнение нажатия).
]]
function UiFx.setCandy(root: GuiObject, look: string | Color3 | Swatch)
	local face = UiFx.faceOf(root)
	local fill = face:FindFirstChild("Fill")
	local lip = root:FindFirstChild("Lip")
	local swatch = swatchOf(look)
	if not swatch then
		return
	end
	local glass = alphaOf(swatch) ~= nil or (root:GetAttribute("CandyHome") == "glass" and isDark(swatch))
	if glass and alphaOf(swatch) == nil then
		swatch = Palette.Glass
	end
	face.BackgroundColor3 = WHITE
	if fill and fill:IsA("UIGradient") then
		fill.Color = ColorSequence.new(swatch.Top, swatch.Bottom)
	end
	local edge: UIStroke? = nil
	if lip and lip:IsA("GuiObject") then
		lip.BackgroundColor3 = swatch.Lip
		edge = lip:FindFirstChildOfClass("UIStroke")
	end
	if root:GetAttribute("CandyStyle") == nil then
		return -- (не «симулятор»: только градиент и цвет Lip)
	end
	face.BackgroundTransparency = if glass then alphaOf(swatch) or SIM.GlassAlpha else 0
	if edge then
		edge.Color = swatch.Lip
		edge.Transparency = if glass then 1 else 0
	end
	local rim = face:FindFirstChild("Rim")
	local ring = if rim then rim:FindFirstChildOfClass("UIStroke") else nil
	if ring then
		ring.Transparency = if glass then 1 else SIM.RimAlpha
	end
	root:SetAttribute("CandyStyle", if glass then "glass" else "sim")
end

-- Тень-близнец надписи (Theme.label Shadow: соседний элемент «<Имя>Shadow»), если есть.
local function twinOf(gui: Instance): GuiObject?
	local parent = gui.Parent
	local twin = if parent then parent:FindFirstChild(gui.Name .. "Shadow") else nil
	if twin and twin:IsA("GuiObject") and twin:GetAttribute("ShadowOf") == gui.Name then
		return twin
	end
	return nil
end
UiFx.twinOf = twinOf

-- Текст надписи вместе с её тенью-близнецом.
function UiFx.setText(label: TextLabel, text: string)
	label.Text = text
	local twin = twinOf(label)
	if twin and twin:IsA("TextLabel") then
		twin.Text = text
	end
end

--[[
	«Меньше движения»: настройка Roblox (GuiService.ReducedMotionEnabled, если клиент её знает)
	или явное setReducedMotion(true / false; nil — снова по настройке). Читается при каждом
	вызове эффекта, без соединений. При ней: без перелётов, покачиваний, тряски и «жизни в покое»,
	конфетти вдвое меньше, радуга медленнее, вспышки текста не мигают.
]]
local reducedOverride: boolean? = nil
function UiFx.setReducedMotion(value: boolean?)
	reducedOverride = value
end

function UiFx.reducedMotion(): boolean
	if reducedOverride ~= nil then
		return reducedOverride
	end
	local ok, value = pcall(function(): any
		return (game:GetService("GuiService") :: any).ReducedMotionEnabled
	end)
	return ok and value == true
end
local reduced = UiFx.reducedMotion

--[[
	Короткий звук интерфейса: "click" | "tick" | "pop" | "ping" | "swoosh" | "splash" | "swim"
	(или rbxasset://…). pitch — скорость воспроизведения (1 = как есть, 2 = на октаву выше).
	На каждый звук — UIConfig.Fx.SoundPool копий по кругу: частые звуки (тики счёта, попадания)
	не обрывают друг друга.
]]
type SoundPool = { sounds: { Sound }, nextIndex: number }
local soundPools: { [string]: SoundPool } = {}
function UiFx.sound(name: string, volume: number?, pitch: number?)
	local id = SOUNDS[name] or name
	local pool = soundPools[id]
	if not pool then
		pool = { sounds = {}, nextIndex = 1 }
		soundPools[id] = pool
	end
	local index = pool.nextIndex
	pool.nextIndex = index % math.max(Fx.SoundPool, 1) + 1
	local sound = pool.sounds[index]
	if not sound or sound.Parent == nil then
		sound = Instance.new("Sound")
		sound.Name = `UiFx_{name}_{index}`
		sound.SoundId = id
		sound.Parent = SoundService
		pool.sounds[index] = sound
	end
	sound.Volume = volume or 0.4
	sound.PlaybackSpeed = math.clamp(pitch or 1, 0.25, 4)
	pcall(function()
		sound.TimePosition = 0
		sound:Play()
	end)
end

-- Мажорное арпеджио «пинга» (тон, терция, квинта, октава) и сколько нот у какой редкости.
local ARPEGGIO = { 1, 1.26, 1.5, 2 }
local ARPEGGIO_NOTES: { [string]: number } = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 7 }
local ARPEGGIO_STEP = 0.07

--[[
	«Фанфара» редкости: Common — одна нота, Rare — две, Epic — три, Legendary — четыре, Mythic —
	четыре и ещё раз октавой выше. Ноты через 0.07 с. Возвращает stop (отменяет ещё не сыгранные).
]]
function UiFx.arpeggio(rarityId: string, volume: number?): Stop
	local notes = ARPEGGIO_NOTES[rarityId] or 1
	local threads: { thread } = {}
	for index = 1, notes do
		local pitch = if index <= #ARPEGGIO then ARPEGGIO[index] else ARPEGGIO[index - #ARPEGGIO + 1] * 2
		if index == 1 then
			UiFx.sound("ping", volume or 0.4, pitch)
		else
			table.insert(threads, task.delay(ARPEGGIO_STEP * (index - 1), UiFx.sound, "ping", volume or 0.4, pitch))
		end
	end
	return function()
		for _, thread in threads do
			if coroutine.status(thread) == "suspended" then
				pcall(task.cancel, thread)
			end
		end
		table.clear(threads)
	end
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
	scale: number?, -- насколько сжимать при нажатии (UIConfig.Motion.Press.Scale, 0.9)
	peak: number?, -- перелёт при отпускании (1.08)
	shade: number?, -- яркость лица, пока нажато (0.8: лицо темнеет на шаг, обводка — нет)
	sound: string?, -- звук нажатия ("click"; чуть разной высоты)
	icon: (string | false)?, -- значок, который «пинается» при отпускании ("Icon"; false — никакой)
	hover: boolean?, -- наведение мыши: чуть крупнее (по умолчанию — без тач-экрана)
	sink: number?, -- (UI v4: «тонуть» в боковину; у «симулятора» боковины нет — не используется)
}

-- Поколение анимации масштаба кнопки: новое нажатие отменяет отложенный второй шаг прошлого.
local pressGeneration: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

--[[
	Нажатие кнопки «симулятора» (UI v5): сжимается до scale (0.06 с) и лицо темнеет на шаг
	(белый фон под градиентом → серый: темнеет весь градиент, обводка остаётся); при отпускании —
	перелёт до peak (0.09 с; кнопка вырастает не больше чем на UIConfig.Motion.Press.MaxGrow px:
	большая кнопка у кнопки прыжка её не задевает) и пружина к 1 (Back Out 0.22 с), лицо светлеет,
	значок «пинается»
	(UIScale 1.18 → 1 и поворот −8° → на место, Back Out) — если его поворотом не владеет «жизнь»
	вида (атрибут IconBusy). Щелчок случайной высоты. Без тач-экрана — ещё и наведение: чуть
	крупнее (1.05), пока мышь над кнопкой. Соединения: нажатие, отпускание, уход мыши (+ наведение
	без тач-экрана) — один раз на кнопку; отпускание ловится и вне кнопки. Возвращает отвязку.
]]
function UiFx.press(button: GuiButton, opts: PressOptions?): Stop
	local o: PressOptions = opts or {}
	local cfg = MOTION.Press
	local scale = UiFx.scaleOf(button)
	local pressed = false
	local hovered = false
	local inputEnded: RBXScriptConnection? = nil
	local face = UiFx.faceOf(button)
	local shadeTo = o.shade or cfg.Shade
	local iconName = if o.icon == false then nil else (o.icon or "Icon")
	local withHover = if o.hover == nil then not UserInputService.TouchEnabled else o.hover

	local function kickIcon()
		local icon = if iconName then button:FindFirstChild(iconName) else nil
		if not icon or not icon:IsA("GuiObject") or not icon.Visible or reduced() then
			return
		end
		local iconScale = UiFx.scaleOf(icon)
		iconScale.Scale = cfg.IconKick
		tween(iconScale, 0.25, { Scale = 1 }, BACK, OUT)
		if icon:GetAttribute("IconBusy") == true or rotations[icon] then
			return -- поворотом значка сейчас владеет другое покачивание
		end
		local rest = icon.Rotation
		icon.Rotation = rest - cfg.IconTilt
		tween(icon, 0.25, { Rotation = rest }, BACK, OUT)
	end

	local function release()
		if inputEnded then
			inputEnded:Disconnect()
			inputEnded = nil
		end
		if not pressed then
			return
		end
		pressed = false
		local generation = (pressGeneration[button] or 0) + 1
		pressGeneration[button] = generation
		if face ~= button then
			tween(face, cfg.Unshade, { BackgroundColor3 = WHITE }, QUAD, OUT)
		end
		local rest = if hovered then MOTION.Hover.Scale else 1
		if reduced() then
			tween(scale, 0.12, { Scale = rest }, QUAD, OUT)
			return
		end
		local height = math.max(button.AbsoluteSize.Y, 1)
		local peak = math.min(o.peak or cfg.Peak, 1 + cfg.MaxGrow / height)
		tween(scale, cfg.Up, { Scale = math.max(peak, rest) }, QUAD, OUT)
		task.delay(cfg.Up, function()
			if pressGeneration[button] == generation and not pressed then
				tween(scale, cfg.Settle, { Scale = if hovered then MOTION.Hover.Scale else 1 }, BACK, OUT)
			end
		end)
		kickIcon()
	end

	local down = button.MouseButton1Down:Connect(function()
		if pressed then
			return
		end
		pressed = true
		pressGeneration[button] = (pressGeneration[button] or 0) + 1
		local squash = o.scale or cfg.Scale
		tween(scale, cfg.Down, { Scale = if reduced() then math.max(squash, 0.95) else squash }, QUAD, OUT)
		if face ~= button then
			tween(face, cfg.Down, { BackgroundColor3 = Color3.new(shadeTo, shadeTo, shadeTo) }, QUAD, OUT)
		end
		if o.sound then
			UiFx.sound(o.sound, nil, rng:NextNumber(cfg.Pitch[1], cfg.Pitch[2]))
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
	local leave = button.MouseLeave:Connect(function()
		if hovered then
			hovered = false
			if not pressed then
				tween(scale, MOTION.Hover.Time, { Scale = 1 }, QUAD, OUT)
			end
		end
		release()
	end)
	local enter: RBXScriptConnection? = nil
	if withHover then
		enter = button.MouseEnter:Connect(function()
			hovered = true
			if not pressed and not reduced() and math.abs(scale.Scale - 1) < 0.02 then
				tween(scale, MOTION.Hover.Time, { Scale = MOTION.Hover.Scale }, BACK, OUT)
			end
		end)
	end
	return function()
		down:Disconnect()
		up:Disconnect()
		leave:Disconnect()
		if enter then
			enter:Disconnect()
		end
		release()
		hovered = false
		scale.Scale = 1
		if face ~= button then
			face.BackgroundColor3 = WHITE
		end
	end
end

-- UIScale "FxScale" элемента и его тени-близнеца (они двигаются вместе).
local function scalesOf(gui: GuiObject): { UIScale }
	local list = { UiFx.scaleOf(gui) }
	local twin = twinOf(gui)
	if twin then
		table.insert(list, UiFx.scaleOf(twin))
	end
	return list
end

-- Масштаб всех: сразу value (если дан), потом твин к goal.
local function scaleAll(
	gui: GuiObject,
	value: number?,
	time: number,
	goal: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
	delay: number?
)
	for _, scale in scalesOf(gui) do
		if value then
			scale.Scale = value
		end
		tween(scale, time, { Scale = goal }, style, direction, delay)
	end
end

-- «Меньше движения»: вместо перелёта — короткое Quad Out от 0.9 (или от from, если он ближе к 1).
local function calmPop(gui: GuiObject, from: number?, delay: number?)
	local start = math.max(from or 0.9, 0.9)
	scaleAll(gui, if start < 1 then start else 1, MOTION.Reduced.PopTime, 1, QUAD, OUT, delay)
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
	if reduced() then
		calmPop(gui, o.from, o.delay)
		return
	end
	scaleAll(gui, o.from or 0, time, 1, BACK, OUT, o.delay)
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
	swell: boolean?, -- сперва чуть «вдохнуть» (1.06), потом уйти (по умолчанию да)
}

-- Исчезновение: короткий «вдох» (1 → 1.06), потом масштаб → to (Back In), потом удалить или
-- спрятать. Общее время — time.
function UiFx.popOut(gui: GuiObject, opts: PopOutOptions?)
	local o: PopOutOptions = opts or {}
	local time = o.time or 0.2
	local cfg = MOTION.Out
	local calm = reduced()
	local pre = if o.swell == false or calm then 0 else math.min(cfg.Pre, time * 0.35)
	if pre > 0 then
		scaleAll(gui, nil, pre, cfg.Swell, QUAD, OUT)
	end
	scaleAll(gui, nil, time - pre, o.to or 0, if calm then QUAD else BACK, IN, pre)
	task.delay(time, function()
		if o.destroy then
			gui:Destroy()
		elseif o.hide then
			gui.Visible = false
			for _, scale in scalesOf(gui) do
				scale.Scale = 1
			end
		end
	end)
end

export type PunchOptions = {
	from: number?, -- с какого масштаба (UIConfig.Motion.Punch.From, 0.84)
	peak: number?, -- до какого перелёта (1.1)
	up: number?, -- первый шаг, с (0.09, Quad Out)
	settle: number?, -- второй шаг к 1, с (0.22, Back Out)
	delay: number?, -- задержка
}

-- Поколение «удара»: новый удар отменяет отложенный второй шаг старого.
local punchGeneration: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

--[[
	«Удар» с ощутимым перелётом в два шага (у Back Out он фиксированный и мал): from → peak
	(Quad Out, up) → 1 (Back Out, settle). Смена вида кнопки, появление кружка «!», прилёт в
	счётчик. Только твины и таймер; тень-близнец — вместе с надписью.
]]
function UiFx.punch(gui: GuiObject, opts: PunchOptions?)
	local o: PunchOptions = opts or {}
	local cfg = MOTION.Punch
	if reduced() then
		calmPop(gui, o.from or cfg.From, o.delay)
		return
	end
	local up, settle = o.up or cfg.Up, o.settle or cfg.Settle
	local generation = (punchGeneration[gui] or 0) + 1
	punchGeneration[gui] = generation
	local function start()
		if punchGeneration[gui] ~= generation then
			return
		end
		scaleAll(gui, o.from or cfg.From, up, o.peak or cfg.Peak, QUAD, OUT)
		task.delay(up, function()
			if punchGeneration[gui] == generation then
				scaleAll(gui, nil, settle, 1, BACK, OUT)
			end
		end)
	end
	if o.delay and o.delay > 0 then
		task.delay(o.delay, start)
	else
		start()
	end
end

--------------------------------------------------------------------------------
-- Кнопки «симулятора»: «приземление», вспышка ободка, смена вида, значок
--------------------------------------------------------------------------------

export type SnapOptions = {
	drop: number?, -- с какой высоты падает, px (8)
	delay: number?, -- задержка
	squash: number?, -- насколько сплющивается на касании (0.08: 1.08 × 0.92)
	sound: boolean?, -- щелчок на касании (по умолчанию да)
}

--[[
	Панель «приземляется» на место: падает сверху на drop px (0.12 с, Quad In), на касании
	сплющивается (шире и ниже на squash) и пружинит (Back Out, 0.18 с), щелчок. Позиция и размер
	«в покое» — те, что были при вызове (в UIListLayout позиция не работает: только сплющивание).
	Только твины и таймеры.
]]
function UiFx.snapIn(gui: GuiObject, opts: SnapOptions?)
	local o: SnapOptions = opts or {}
	local calm = reduced()
	local drop = if calm then 0 else (o.drop or 8)
	local delay = o.delay or 0
	local squash = if calm then 0 else (o.squash or 0.08)
	local restPosition, restSize = gui.Position, gui.Size
	gui.Position = restPosition - UDim2.fromOffset(0, drop)
	tween(gui, 0.12, { Position = restPosition }, QUAD, IN, delay)
	task.delay(delay + 0.12, function()
		if gui.Parent == nil then
			return
		end
		local x, y = restSize.X, restSize.Y
		gui.Size = UDim2.new(
			x.Scale * (1 + squash),
			math.round(x.Offset * (1 + squash)),
			y.Scale * (1 - squash),
			math.round(y.Offset * (1 - squash))
		)
		tween(gui, 0.18, { Size = restSize }, BACK, OUT)
		if o.sound ~= false then
			UiFx.sound("tick", 0.3, 1.3)
		end
	end)
end

export type RimFlashOptions = {
	delay: number?, -- задержка
	time: number?, -- UIConfig.Motion.RimFlash.Time (0.3)
	bump: number?, -- лёгкий «вдох» (1.06; 1 — без него)
	sound: boolean?, -- тихий «тик»
}

--[[
	Вспышка ободка (UI v5, вместо «пупырок по очереди» v3): светлый ободок Rim лица на миг
	становится белым и сплошным и возвращается к UIConfig.Sim.RimAlpha (Quad Out), по лицу —
	белая накладка FxMorph 0.6 → 1, кнопка чуть «вдыхает» (1 → 1.06 → 1). Только твины.
]]
function UiFx.rimFlash(root: GuiObject, opts: RimFlashOptions?)
	local o: RimFlashOptions = opts or {}
	local cfg = MOTION.RimFlash
	local time = o.time or cfg.Time
	local delay = o.delay or 0
	local function run()
		if root.Parent == nil then
			return
		end
		local calm = reduced()
		local face = UiFx.faceOf(root)
		local rim = face:FindFirstChild("Rim")
		local ring = if rim then rim:FindFirstChildOfClass("UIStroke") else nil
		if ring and ring.Transparency < 1 then
			ring.Transparency = 0
			tween(ring, time, { Transparency = SIM.RimAlpha }, QUAD, OUT)
		end
		if face ~= root and not calm then
			local flash = Instance.new("Frame")
			flash.Name = "FxMorph"
			flash.Active = false
			flash.BackgroundColor3 = WHITE
			flash.BackgroundTransparency = 0.6
			flash.BorderSizePixel = 0
			flash.Size = UDim2.fromScale(1, 1)
			flash.ZIndex = 4
			copyCorner(root, flash)
			flash.Parent = face
			tween(flash, time, { BackgroundTransparency = 1 }, QUAD, OUT)
			task.delay(time + 0.02, function()
				flash:Destroy()
			end)
		end
		local peak = o.bump or cfg.Bump
		if peak > 1 and not calm then
			scaleAll(root, nil, time * 0.35, peak, QUAD, OUT)
			task.delay(time * 0.35, function()
				scaleAll(root, nil, time * 0.65, 1, BACK, OUT)
			end)
		end
		if o.sound then
			UiFx.sound("tick", 0.15, 1.5)
		end
	end
	if delay > 0 then
		task.delay(delay, run)
	else
		run()
	end
end

-- Значок элемента (Icon у корня или у лица) «выскакивает»: UIScale from (0.7) → 1.15 → 1.
function UiFx.iconPop(root: GuiObject, from: number?)
	local icon = root:FindFirstChild("Icon") or UiFx.faceOf(root):FindFirstChild("Icon")
	if icon and icon:IsA("GuiObject") then
		UiFx.punch(icon, { from = from or 0.7, peak = 1.15, up = 0.12, settle = 0.2 })
	end
end

--[[
	Вспышка «превращения» кнопки (важная смена вида: «ПОДСЕЧЬ!», «ЛОВИ!», «ЗАБРАТЬ!»): белая
	накладка на лицо UIConfig.Motion.Morph.Flash → 1 за FlashTime (значок и подпись — поверх неё),
	значок «выскакивает» (iconPop). Только твины. (Кольца от кнопки — у самих видов
	FishingController: у кнопки рядом с кнопкой прыжка лишнее кольцо её задевало бы.)
]]
function UiFx.morphFlash(root: GuiObject, color: Color3?)
	local cfg = MOTION.Morph
	local face = UiFx.faceOf(root)
	local flash = Instance.new("Frame")
	flash.Name = "FxMorph"
	flash.Active = false
	flash.BackgroundColor3 = color or WHITE
	flash.BackgroundTransparency = cfg.Flash
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 1)
	flash.ZIndex = 4
	copyCorner(root, flash)
	flash.Parent = face
	tween(flash, cfg.FlashTime, { BackgroundTransparency = 1 }, QUAD, OUT)
	task.delay(cfg.FlashTime + 0.02, function()
		flash:Destroy()
	end)
	UiFx.iconPop(root, 0.6)
end

-- «Подпрыгнуть»: резко увеличиться и пружинисто вернуться (счётчики, награды).
function UiFx.bump(gui: GuiObject, peak: number?, time: number?)
	if reduced() then
		return
	end
	scaleAll(gui, peak or 1.22, time or 0.3, 1, BACK, OUT)
end

-- «Удар»: влетает огромным (2.2) и с перелётом садится на место, потом лёгкая тряска.
function UiFx.slam(gui: GuiObject, from: number?, time: number?)
	if reduced() then
		calmPop(gui, 0.9)
		return
	end
	local duration = time or 0.35
	scaleAll(gui, from or 2.2, duration, 1, BACK, OUT)
	task.delay(duration * 0.55, function()
		UiFx.shake(gui, 0.012, 0.22)
	end)
end

-- «Печать»: падает сверху крупной и с поворотом (бейджи, «НОВАЯ!»).
function UiFx.stamp(gui: GuiObject, rotate: number?, time: number?)
	if reduced() then
		calmPop(gui, 0.9)
		return
	end
	local duration = time or 0.3
	scaleAll(gui, 3, duration, 1, BACK, OUT)
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

-- Бесконечный «пульс» масштаба 1 ↔ peak. Возвращает stop. («Меньше движения» — без пульса.)
function UiFx.pulse(gui: GuiObject, peak: number?, period: number?): Stop
	local scale = UiFx.scaleOf(gui)
	scale.Scale = 1
	if reduced() then
		return noop
	end
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
	if reduced() then
		return
	end
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

-- Тряска позиции ±amount (доля родителя, по умолчанию 1.5 %), затухающая за time (0.25 с); тень-
-- близнец трясётся с теми же сдвигами.
function UiFx.shake(gui: GuiObject, amount: number?, time: number?)
	if reduced() then
		return
	end
	local size = amount or 0.015
	local steps = 6
	local stepTime = (time or 0.25) / steps
	local targets: { GuiObject } = { gui }
	local twin = twinOf(gui)
	if twin then
		table.insert(targets, twin)
	end
	local offsets: { UDim2 } = {}
	for index = 1, steps do
		local k = 1 - (index - 1) / steps
		offsets[index] = if index == steps
			then UDim2.new()
			else UDim2.fromScale(rng:NextNumber(-size, size) * k, rng:NextNumber(-size, size) * k)
	end
	for _, target in targets do
		local motion = beginMotion(positions, target, target.Position)
		local rest: UDim2 = motion.rest
		for index = 1, steps do
			local goal = rest + offsets[index]
			local function move()
				tween(target, stepTime, { Position = goal }, SINE, OUT)
				if index == steps then
					positions[target] = nil
				end
			end
			if index == 1 then
				move()
			else
				table.insert(motion.threads, task.delay(stepTime * (index - 1), move))
			end
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

-- Сколько бликов сейчас идёт по слою Shine (несколько бликов подряд не прячут его раньше времени).
local shineSweeps: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

--[[
	Блик: белая косая полоса проходит по элементу (по лицевой стороне конфеты) за time (0.6 с).
	Слой во весь размер с тем же скруглением — блик не вылезает за круглые углы. У конфет слой
	Shine готов в сборщике и спрятан (Visible = false — не рисуется зря); здесь он показывается на
	время блика. У других элементов слой создаётся на время блика.
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
		return
	end
	overlay.Visible = true
	shineSweeps[overlay] = (shineSweeps[overlay] or 0) + 1
	task.delay(duration + 0.02, function()
		local left = (shineSweeps[overlay] or 1) - 1
		if left <= 0 then
			shineSweeps[overlay] = nil
			overlay.Visible = false
		else
			shineSweeps[overlay] = left
		end
	end)
end

export type ShineLoopOptions = {
	interval: number?, -- секунд между бликами (UIConfig.Motion.Shine.Interval)
	time: number?, -- длительность блика
	delay: number?, -- первый блик (по умолчанию — случайно в пределах интервала)
	when: (() -> boolean)?, -- блестеть, только если вернёт true
}

-- Блик раз в interval секунд, пока элемент виден. Таймеры, без соединений. Возвращает stop.
function UiFx.shineLoop(gui: GuiObject, opts: ShineLoopOptions?): Stop
	if reduced() then
		return noop
	end
	local o: ShineLoopOptions = opts or {}
	local interval = o.interval or MOTION.Shine.Interval
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

local function oneRing(gui: GuiObject, o: RingOptions): Frame
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
	return ring
end

--[[
	Расходящееся кольцо (или залитая копия формы) вокруг элемента. С loop — повторяется до stop.
	stop() гасит и уже летящие кольца этого вызова за 0.1 с (кольцо прошлого состояния кнопки не
	доигрывает поверх нового цвета).
]]
function UiFx.glowRing(gui: GuiObject, opts: RingOptions?): Stop
	local o: RingOptions = opts or {}
	local live: { [Frame]: boolean } = {}
	local function spawnRing()
		local ring = oneRing(gui, o)
		live[ring] = true
		task.delay(o.time or 0.6, function()
			live[ring] = nil
		end)
	end
	local running = true
	local pending: thread? = nil
	spawnRing()
	if o.loop and not reduced() then
		local gap = o.interval or ((o.time or 0.6) + 0.25)
		local function tick()
			pending = nil
			if not running or gui.Parent == nil then
				running = false
				return
			end
			if gui.Visible then
				spawnRing()
			end
			pending = task.delay(gap, tick)
		end
		pending = task.delay(gap, tick)
	end
	return function()
		running = false
		local thread = pending
		pending = nil
		if thread and coroutine.status(thread) == "suspended" then
			pcall(task.cancel, thread)
		end
		for ring in live do
			if ring.Parent then
				local stroke = ring:FindFirstChildOfClass("UIStroke")
				if stroke then
					tween(stroke, 0.1, { Transparency = 1 }, QUAD, OUT)
				end
				tween(ring, 0.1, { BackgroundTransparency = 1 }, QUAD, OUT)
				task.delay(0.1, function()
					ring:Destroy()
				end)
			end
		end
		table.clear(live)
	end
end

-- Одиночная «рябь» от касания (кольцо 1 → 1.35 за 0.4 с).
function UiFx.ripple(gui: GuiObject, color: Color3?)
	oneRing(gui, { color = color, time = 0.4, scale = 1.35, thickness = 3 })
end

export type RaysOptions = {
	colors: { Color3 }?, -- чередующиеся цвета лучей (белый / золотой)
	count: number?, -- лучей (14)
	speed: number?, -- градусов в секунду (20); со знаком: минус — вращение в обратную сторону
	size: number?, -- диаметр в высотах элемента (2.6)
	maxPx: number?, -- предел диаметра в пикселях (на телефоне лучи не на весь экран)
	width: number?, -- толщина луча (доля диаметра, 0.075)
	transparency: number?, -- прозрачность лучей (0.3)
	glow: boolean?, -- мягкое свечение в центре (true)
	halo: boolean?, -- мягкий широкий ореол у каждого луча (по умолчанию: на компьютере да,
	-- на тач-устройствах нет — вдвое меньше заливки; без ореола лучи в 1.4 раза толще и чуть ярче)
	breathe: boolean?, -- «дыхание» 1 ↔ 1.06 (по умолчанию как halo)
	grow: number?, -- время появления 0 → 1, Quad Out без перелёта (0.4 с)
	growFrom: number?, -- … начиная с этого размера (0; с hole — например 0.75: середина сразу пустая)
	z: number?, -- ZIndex (0: позади конфеты; для прочих элементов ставьте лучи в отдельный слой позади)
	hole: number?, -- пустая середина, доля радиуса (0; 0.3 — лучи бьют ВОКРУГ того, что в центре,
	-- например рыбы над головой в мире; свечения в центре тогда нет)
}

export type SettleOptions = {
	alphaAdd: number?, -- на сколько прозрачнее станут лучи (0.25)
	spinMul: number?, -- во сколько раз медленнее вращение (0.5)
	time: number?, -- за сколько секунд (0.6)
}

type RaysApi = {
	holder: Frame, -- слой FxRays (для тестов и тонкой настройки)
	stop: () -> (), -- то же, что вызвать саму ручку: лучи удаляются
	settle: (self: RaysApi, opts: SettleOptions?) -> (), -- «успокоиться» после кульминации
	Destroy: (self: RaysApi) -> (), -- для Trove:Add
}
-- Ручка лучей: её можно вызвать как функцию остановки (rays()), положить в Trove (Destroy) или
-- «успокоить» после кульминации: rays:settle({ alphaAdd = 0.25, spinMul = 0.5, time = 0.6 }).
export type Rays = typeof(setmetatable({} :: RaysApi, {} :: { __call: (RaysApi) -> () }))

--[[
	«Солнышко» за элементом: лучи от центра (чередуются цвета, к концу тают; на компьютере у
	каждого ещё широкий мягкий ореол) и круглое свечение; вырастает (Quad Out), медленно вращается
	(speed со знаком: два кольца в разные стороны не дают муара) и «дышит». С hole середина пустая:
	лучи бьют вокруг того, что в центре (рыба над головой в мире видна). Только твины (без
	соединений). Возвращает ручку Rays: rays() / rays.stop() — убрать, rays:settle() — сделать
	тише и медленнее (и перестать «дышать»), когда главное уже показано.
]]
function UiFx.rays(gui: GuiObject, opts: RaysOptions?): Rays
	local o: RaysOptions = opts or {}
	local touch = UserInputService.TouchEnabled
	local colors = o.colors or { WHITE, Palette.Gold.Top }
	local count = math.max(4, o.count or 14)
	local size = o.size or 2.6
	local withHalo = if o.halo == nil then not touch else o.halo
	local breathes = if o.breathe == nil then withHalo else o.breathe
	local alpha = math.max(0, (o.transparency or 0.3) - (if withHalo then 0 else 0.05))
	local width = (o.width or 0.075) * (if withHalo then 1 else 1.4)
	local speed = o.speed or 20
	local grow = o.grow or 0.4
	local hole = math.clamp(o.hole or 0, 0, 0.9)
	local holder = Instance.new("Frame")
	holder.Name = "FxRays"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.SizeConstraint = Enum.SizeConstraint.RelativeYY
	holder.Size = UDim2.fromScale(size, size)
	holder.ZIndex = o.z or 0
	if o.maxPx then
		local cap = Instance.new("UISizeConstraint")
		cap.MaxSize = Vector2.new(o.maxPx, o.maxPx)
		cap.Parent = holder
	end

	-- Вдоль луча (снаружи → к центру): снаружи тает, у центра чуть прозрачнее (там сам элемент).
	local function fade(base: number): NumberSequence
		return NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.45, base),
			NumberSequenceKeypoint.new(1, math.min(1, base + 0.25)),
		})
	end

	-- Всё, что гаснет при settle: кадр и его «пиковая» прозрачность.
	local fading: { { frame: Frame, peak: number, direct: boolean } } = {}

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
		table.insert(fading, { frame = frame, peak = transparency, direct = true })
	end
	if o.glow ~= false and hole <= 0 then
		disc("GlowOuter", 0.62, 0.78, colors[1])
		disc("GlowInner", 0.38, 0.55, colors[1])
	end

	-- Луч — прямоугольник от центра (или от края пустой середины) наружу, повёрнут по направлению.
	local length = 0.5 * (1 - hole) -- доля диаметра
	local middle = 0.25 * (1 + hole) -- его центр от центра лучей
	local function ray(index: number, name: string, thickness: number, peak: number)
		local angle = (index - 1) * 360 / count
		local radians = math.rad(angle)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5 + middle * math.sin(radians), 0.5 - middle * math.cos(radians))
		frame.Size = UDim2.fromScale(thickness, length)
		frame.Rotation = angle
		frame.BackgroundColor3 = colors[(index - 1) % #colors + 1]
		frame.BorderSizePixel = 0
		frame.ZIndex = holder.ZIndex
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = 90
		gradient.Transparency = fade(peak)
		gradient.Parent = frame
		frame.Parent = holder
		table.insert(fading, { frame = frame, peak = peak, direct = false })
	end
	for index = 1, count do
		if withHalo then
			ray(index, `Halo{index}`, width * 2.2, math.min(1, alpha + 0.45))
		end
		ray(index, `Ray{index}`, width, alpha)
	end

	holder.Parent = gui
	-- Появление: растёт из центра без перелёта (лучи бывают во весь экран — перелёт там лишний).
	local scale = UiFx.scaleOf(holder)
	scale.Scale = math.clamp(o.growFrom or 0, 0, 1)
	tween(scale, grow, { Scale = 1 }, QUAD, OUT)

	local spin: Tween? = nil
	local function spinAt(degreesPerSecond: number)
		if spin then
			spin:Cancel()
		end
		local rate = math.max(math.abs(degreesPerSecond), 1)
		local direction = if degreesPerSecond < 0 then -1 else 1
		local from = holder.Rotation % 360
		holder.Rotation = from
		local created = TweenService:Create(
			holder,
			TweenInfo.new(360 / rate, LINEAR, OUT, -1),
			{ Rotation = from + 360 * direction }
		)
		created:Play()
		spin = created
	end
	spinAt(speed)

	local breathe: Tween? = nil
	local alive = true
	local settled = false
	if breathes then
		task.delay(grow, function()
			if alive and not settled and holder.Parent then
				local looping = TweenService:Create(scale, TweenInfo.new(1.2, SINE, INOUT, -1, true), { Scale = 1.06 })
				looping:Play()
				breathe = looping
			end
		end)
	end

	local function stop()
		if not alive then
			return
		end
		alive = false
		if spin then
			spin:Cancel()
		end
		if breathe then
			breathe:Cancel()
		end
		holder:Destroy()
	end

	local handle = {} :: RaysApi
	handle.holder = holder
	handle.stop = stop
	function handle.settle(_self: RaysApi, settleOpts: SettleOptions?)
		if not alive or settled then
			return
		end
		settled = true
		local so: SettleOptions = settleOpts or {}
		local add = so.alphaAdd or 0.25
		local time = so.time or 0.6
		-- Пик прозрачности p → p + add. У лучей прозрачность в градиенте (он не твинится), поэтому
		-- их гасит фон кадра: 1 − (1 − фон)(1 − p) = p + add. У дисков свечения — сам фон.
		for _, item in fading do
			local target = math.min(1, item.peak + add)
			local keep = if item.peak >= 1 then 0 else (1 - target) / (1 - item.peak)
			local goal = if item.direct then target else 1 - keep
			tween(item.frame, time, { BackgroundTransparency = goal }, QUAD, OUT)
		end
		if breathe then
			breathe:Cancel()
			breathe = nil
		end
		tween(scale, time, { Scale = 1 }, SINE, OUT)
		spinAt(speed * (so.spinMul or 0.5))
	end
	function handle.Destroy(_self: RaysApi)
		stop()
	end
	return setmetatable(handle, {
		__call = function(_self: RaysApi)
			stop()
		end,
	})
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
	local wanted = (o.count or 40) * (if reduced() then MOTION.Reduced.Confetti else 1)
	local count = math.min(math.floor(wanted), UiFx.confettiCap() - liveConfetti)
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

--[[
	Конфетти на одних твинах (без покадровой работы): каждая бумажка взлетает по дуге (вверх —
	Quad Out, вниз — Quad In), кувыркается и тает. Беднее физики confetti (нет «парашюта»), зато
	ничего не держит общий планировщик — для моментов, когда остальной интерфейс спокоен (вход
	в игру, баннер базы) и для дешёвых залпов. Опции и общий лимит — как у confetti
	(power — высота дуги, duration — жизнь). Возвращает stop.
]]
function UiFx.confettiPop(container: GuiBase2d, opts: ConfettiOptions?): Stop
	local o: ConfettiOptions = opts or {}
	local wanted = (o.count or 20) * (if reduced() then MOTION.Reduced.Confetti else 1)
	local count = math.min(math.floor(wanted), UiFx.confettiCap() - liveConfetti)
	if count <= 0 then
		return noop
	end
	local area = container.AbsoluteSize
	local width, height = math.max(area.X, 1), math.max(area.Y, 1)
	local unit = screenUnit(container)
	local colors = o.colors or UIConfig.Confetti
	local origin = o.origin or Vector2.new(0.5, 0.5)
	local spread = math.rad(o.spread or 100)
	local power = o.power or 1
	local duration = o.duration or 1.6
	local holder = Instance.new("Frame")
	holder.Name = "FxConfetti"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = o.z or 50
	holder.Active = false
	for _ = 1, count do
		local strip = rng:NextNumber() < 0.45
		local w = unit * (if strip then 0.011 else 0.019) * rng:NextNumber(0.8, 1.25)
		local h = unit * (if strip then 0.032 else 0.019) * rng:NextNumber(0.8, 1.25)
		local angle = -math.pi / 2 + rng:NextNumber(-0.5, 0.5) * spread
		local reach = unit * 0.32 * power * rng:NextNumber(0.6, 1.2)
		local life = duration * rng:NextNumber(0.75, 1)
		local up = life * 0.38
		local x0, y0 = origin.X * width, origin.Y * height
		local x1, y1 = x0 + math.cos(angle) * reach, y0 + math.sin(angle) * reach
		local x2 = x1 + math.cos(angle) * reach * 0.6
		local y2 = y1 + unit * rng:NextNumber(0.35, 0.6)
		local piece = Instance.new("Frame")
		piece.Name = "Piece"
		piece.AnchorPoint = Vector2.new(0.5, 0.5)
		piece.BorderSizePixel = 0
		piece.BackgroundColor3 = colors[rng:NextInteger(1, #colors)]
		piece.Size = UDim2.fromScale(w / width, h / height)
		piece.Position = UDim2.fromScale(x0 / width, y0 / height)
		piece.Rotation = rng:NextNumber(0, 360)
		piece.ZIndex = holder.ZIndex
		piece.Parent = holder
		tween(piece, up, { Position = UDim2.fromScale(x1 / width, y1 / height) }, QUAD, OUT)
		-- Вторая половина дуги — отдельным твином после первой (два твина одного свойства сразу
		-- отменяют друг друга).
		task.delay(up, function()
			if piece.Parent then
				tween(piece, life - up, { Position = UDim2.fromScale(x2 / width, y2 / height) }, QUAD, IN)
			end
		end)
		tween(piece, life, { Rotation = piece.Rotation + rng:NextNumber(-540, 540) }, LINEAR, OUT)
		tween(piece, life * 0.3, { BackgroundTransparency = 1 }, QUAD, IN, life * 0.7)
	end
	holder.Parent = container
	liveConfetti += count
	local alive = true
	local function stop()
		if not alive then
			return
		end
		alive = false
		liveConfetti -= count
		holder:Destroy()
	end
	local thread = task.delay(duration + 0.05, stop)
	return function()
		if coroutine.status(thread) == "suspended" then
			pcall(task.cancel, thread)
		end
		stop()
	end
end

export type BurstOptions = {
	count: number?, -- искр (12)
	colors: { Color3 }?, -- цвета (белый, золото)
	origin: Vector2?, -- центр в долях контейнера (0.5, 0.5)
	power: number?, -- дальность (1)
	time: number?, -- 0.55 с
	z: number?, -- ZIndex (40)
	size: number?, -- множитель размера искр (1; попадание в мини-игре — крупнее)
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
		local size = unit * rng:NextNumber(0.011, 0.019) * (o.size or 1)
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
	if reduced() then
		return noop
	end
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
	to: UDim2?, -- сначала вылететь из position сюда (Back Out за travel), потом подниматься
	travel: number?, -- 0.3 с
}

-- «ОТЛИЧНО!», «+1 🐟»: жирный наклонный текст с толстой обводкой выскакивает (0.4 → 1, Back Out),
-- поднимается и тает; с `to` — сперва вылетает из position туда (растёт по пути: «+N 💰» из
-- фишки цены). Возвращает надпись (удалится сама).
function UiFx.floatText(container: GuiBase2d, text: string, opts: FloatOptions?): TextLabel
	local o: FloatOptions = opts or {}
	local time = o.time or 0.8
	local start = o.position or UDim2.fromScale(0.5, 0.5)
	local label = Instance.new("TextLabel")
	label.Name = "FxFloat"
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextScaled = true
	label.FontFace = FONT_ITALIC
	label.TextColor3 = o.color or WHITE
	label.TextStrokeTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = start
	label.Size = o.size or UDim2.fromScale(0.5, 0.2)
	label.Rotation = if reduced() then 0 else (o.rotate or rng:NextNumber(-6, 6))
	label.ZIndex = o.z or 20
	local outline = Instance.new("UIStroke")
	outline.Name = "Outline"
	outline.Color = INK
	outline.Thickness = 4
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	outline.LineJoinMode = Enum.LineJoinMode.Round
	outline:SetAttribute("BaseThickness", 4)
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
	local target = o.to
	if target then
		-- Вылет (Back Out), потом подъём — отдельным твином, когда вылет кончился.
		local travel = math.min(o.travel or 0.3, time * 0.6)
		tween(scale, travel, { Scale = 1 }, BACK, OUT)
		tween(label, travel, { Position = target }, BACK, OUT)
		task.delay(travel, function()
			if label.Parent then
				tween(label, time - travel, { Position = target - UDim2.fromScale(0, o.rise or 0.08) }, QUAD, OUT)
			end
		end)
	else
		tween(scale, 0.2, { Scale = 1 }, BACK, OUT)
		tween(label, time, { Position = start - UDim2.fromScale(0, o.rise or 0.08) }, QUAD, OUT)
	end
	tween(label, time * 0.5, { TextTransparency = 1 }, QUAD, IN, time * 0.5)
	tween(outline, time * 0.5, { Transparency = 1 }, QUAD, IN, time * 0.5)
	task.delay(time + 0.05, function()
		label:Destroy()
	end)
	return label
end

--------------------------------------------------------------------------------
-- Жизнь в покое (только таймеры и твины): дыхание, подпрыгивание, кружок «!», покачивание
--------------------------------------------------------------------------------

-- Цепочка task.delay, пока элемент виден: every() — пауза до следующего шага, step() — шаг.
-- Возвращает stop. Удалённый элемент обрывает цепочку на следующем шаге.
local function timerChain(gui: GuiObject, first: number, every: () -> number, step: () -> ()): Stop
	local running = true
	local pending: thread? = nil
	local function tick()
		pending = nil
		if not running or gui.Parent == nil then
			running = false
			return
		end
		if gui.Visible then
			step()
		end
		pending = task.delay(every(), tick)
	end
	pending = task.delay(first, tick)
	return function()
		running = false
		local thread = pending
		pending = nil
		if thread and coroutine.status(thread) == "suspended" then
			pcall(task.cancel, thread)
		end
	end
end

export type BreatheOptions = {
	peak: number?, -- до какого масштаба «вдох» (UIConfig.Motion.Breath.Peak, 1.04)
	period: number?, -- вдох-выдох, с (1.8)
	when: (() -> boolean)?, -- дышать, только если вернёт true
}

--[[
	«Дыхание» главной кнопки: раз в period секунд — один вдох-выдох (Sine InOut туда и обратно до
	peak), только если элемент виден и сейчас не нажат и не «ударен» (масштаб ≈ 1). Один твин и
	одна цепочка таймеров. Возвращает stop (масштаб возвращается к 1).
]]
function UiFx.breathe(gui: GuiObject, opts: BreatheOptions?): Stop
	if reduced() then
		return noop
	end
	local o: BreatheOptions = opts or {}
	local cfg = MOTION.Breath
	local period = o.period or cfg.Period
	local scale = UiFx.scaleOf(gui)
	local current: Tween? = nil
	local stop = timerChain(gui, period * rng:NextNumber(0.3, 1), function()
		return period
	end, function()
		if math.abs(scale.Scale - 1) < 0.01 and (o.when == nil or o.when()) then
			local info = TweenInfo.new(period / 2, SINE, INOUT, 0, true)
			local created = TweenService:Create(scale, info, { Scale = o.peak or cfg.Peak })
			created:Play()
			current = created
		end
	end)
	return function()
		stop()
		if current then
			current:Cancel()
			current = nil
			scale.Scale = 1
		end
	end
end

export type BobOptions = {
	lift: number?, -- на какую долю своей высоты подпрыгнуть (UIConfig.Motion.Bob.Lift, 0.08)
	every: { number }?, -- пауза между прыжками, с ({2.2, 3.0}: случайно)
	hops: number?, -- сколько прыжков и стоп (по умолчанию — пока не остановят)
	when: (() -> boolean)?, -- прыгать, только если вернёт true
}

--[[
	Значок подпрыгивает: AnchorPoint.Y + lift за 0.18 с (Quad Out) и обратно за 0.32 с (Bounce
	Out) — через AnchorPoint, так что позицией и масштабом владеют другие эффекты. Цепочка
	таймеров, пока элемент виден. Возвращает stop (значок встаёт на место).
]]
function UiFx.bob(icon: GuiObject, opts: BobOptions?): Stop
	if reduced() then
		return noop
	end
	local o: BobOptions = opts or {}
	local cfg = MOTION.Bob
	local every = o.every or cfg.Every
	local rest = icon.AnchorPoint
	local hops = 0
	local stop: Stop = noop
	stop = timerChain(icon, rng:NextNumber(every[1], every[2]) * 0.5, function()
		return rng:NextNumber(every[1], every[2])
	end, function()
		if o.when and not o.when() then
			return
		end
		hops += 1
		tween(icon, cfg.Up, { AnchorPoint = rest + Vector2.new(0, o.lift or cfg.Lift) }, QUAD, OUT)
		task.delay(cfg.Up, function()
			tween(icon, cfg.Down, { AnchorPoint = rest }, BOUNCE, OUT)
		end)
		if o.hops and hops >= o.hops then
			task.defer(stop)
		end
	end)
	return function()
		stop()
		icon.AnchorPoint = rest
	end
end

export type WobbleOptions = {
	angle: number?, -- ±градусов (UIConfig.Motion.Wobble.Angle, 12)
	bump: number?, -- «вдох» на каждом покачивании (1.12)
	every: { number }?, -- пауза, с ({2.8, 3.6}: случайно)
}

-- Покачивание «обратите внимание» (кружок «!»): раз в 2.8–3.6 с — качнуться ±12° и «вдохнуть».
-- Цепочка таймеров, пока элемент виден. Возвращает stop.
function UiFx.wobbleLoop(gui: GuiObject, opts: WobbleOptions?): Stop
	if reduced() then
		return noop
	end
	local o: WobbleOptions = opts or {}
	local cfg = MOTION.Wobble
	local every = o.every or cfg.Every
	return timerChain(gui, rng:NextNumber(every[1], every[2]) * 0.6, function()
		return rng:NextNumber(every[1], every[2])
	end, function()
		UiFx.wiggle(gui, o.angle or cfg.Angle, cfg.Swings, cfg.Time)
		UiFx.bump(gui, o.bump or cfg.Bump, 0.25)
	end)
end

export type SwayOptions = {
	angle: number?, -- ±градусов (UIConfig.Motion.Sway.Angle, 1.5)
	period: number?, -- туда-обратно, с (2.4)
}

-- Медленное покачивание поворотом (плашка ожидания): один бесконечный твин. stop — поворот на место.
function UiFx.sway(gui: GuiObject, opts: SwayOptions?): Stop
	if reduced() then
		return noop
	end
	local o: SwayOptions = opts or {}
	local cfg = MOTION.Sway
	local rest = gui.Rotation
	local angle = o.angle or cfg.Angle
	gui.Rotation = rest - angle
	local looping = TweenService:Create(gui, TweenInfo.new((o.period or cfg.Period) / 2, SINE, INOUT, -1, true), {
		Rotation = rest + angle,
	})
	looping:Play()
	return function()
		looping:Cancel()
		gui.Rotation = rest
	end
end

-- Остановка «живущего» кружка «!» (badgeBob) — по самому кружку.
local badgeLife: { [Instance]: Stop } = setmetatable({}, { __mode = "k" }) :: any

--[[
	Красный кружок «!» (Theme.badge) появляется: Visible, «удар» 0 → 1.25 → 1, белое кольцо и
	высокий «тик»; потом качается раз в 2.8–3.6 с (wobbleLoop), пока виден. Возвращает stop
	(то же делает badgeHide).
]]
function UiFx.badgeBob(badge: GuiObject): Stop
	local old = badgeLife[badge]
	if old then
		old()
	end
	badge.Visible = true
	UiFx.punch(badge, { from = 0, peak = 1.25, up = 0.12, settle = 0.25 })
	if not reduced() then
		UiFx.glowRing(badge, { color = WHITE, scale = 1.6, time = 0.45, thickness = 3 })
	end
	UiFx.sound("tick", 0.3, 1.6)
	local stopWobble = UiFx.wobbleLoop(badge)
	local function stop()
		stopWobble()
		if badgeLife[badge] == stop then
			badgeLife[badge] = nil
		end
	end
	badgeLife[badge] = stop
	return stop
end

-- Кружок «!» уходит: «вдох» и сжатие (popOut 0.16 с), потом Visible = false.
function UiFx.badgeHide(badge: GuiObject)
	local stop = badgeLife[badge]
	if stop then
		stop()
	end
	if badge.Visible then
		UiFx.popOut(badge, { time = MOTION.Out.Time, hide = true })
	end
end

export type StaggerPopOptions = {
	from: number?, -- начальный масштаб (UIConfig.Motion.Pop.ChildFrom, 0.3)
	gap: number?, -- между элементами, с (UIConfig.Motion.Pop.ChildDelay, 0.05)
	time: number?, -- выскакивание одного (UIConfig.Motion.Pop.Time)
	delay: number?, -- первый
}

-- Элементы выскакивают «лесенкой» (Back Out, один за другим): вход в игру, звёзды, кружки.
function UiFx.staggerPop(items: { GuiObject }, opts: StaggerPopOptions?)
	local o: StaggerPopOptions = opts or {}
	local cfg = MOTION.Pop
	for index, item in items do
		UiFx.popIn(item, {
			from = o.from or cfg.ChildFrom,
			time = o.time or cfg.Time,
			delay = (o.delay or 0) + (index - 1) * (o.gap or cfg.ChildDelay),
		})
	end
end

--------------------------------------------------------------------------------
-- Числа и цвета: «слот-машина», вспышка текста, перекраска с переходом, кольцо-таймер
--------------------------------------------------------------------------------

-- Позиция надписи «в покое» (swapText запоминает её при первом вызове: повторы не сдвигают).
local textRest: { [Instance]: UDim2 } = setmetatable({}, { __mode = "k" }) :: any

export type SwapOptions = {
	out: number?, -- старый текст уезжает, с (UIConfig.Motion.Roll.Out)
	inTime: number?, -- новый поднимается, с (Roll.In)
	lift: number?, -- на какую долю высоты (0.4)
}

--[[
	«Слот-машина»: копия FxSwap со старым текстом уезжает вверх и тает, надпись получает новый
	текст и поднимается снизу на место с пружинкой (Back Out). Позиция «в покое» запоминается.
	Тень-близнец получает текст сразу. Только твины.
]]
function UiFx.swapText(label: TextLabel, text: string, opts: SwapOptions?)
	local o: SwapOptions = opts or {}
	local cfg = MOTION.Roll
	if label.Text == text then
		return
	end
	local rest = textRest[label]
	if not rest then
		rest = label.Position
		textRest[label] = rest
	end
	local old = label.Text
	UiFx.setText(label, text)
	if reduced() or label.Parent == nil then
		label.Position = rest
		return
	end
	local lift =
		UDim2.new(0, 0, label.Size.Y.Scale * (o.lift or 0.4), math.round(label.Size.Y.Offset * (o.lift or 0.4)))
	local ghost = label:Clone()
	ghost.Name = "FxSwap"
	ghost.Text = old
	for _, item in ghost:GetChildren() do
		if string.sub(item.Name, 1, 2) == "Fx" then
			item:Destroy()
		end
	end
	ghost.Position = rest
	ghost.Parent = label.Parent
	local out = o.out or cfg.Out
	tween(ghost, out, { Position = rest - lift, TextTransparency = 1 }, QUAD, IN)
	local edge = ghost:FindFirstChildOfClass("UIStroke")
	if edge then
		tween(edge, out, { Transparency = 1 }, QUAD, IN)
	end
	task.delay(out + 0.02, function()
		ghost:Destroy()
	end)
	label.Position = rest + lift
	tween(label, o.inTime or cfg.In, { Position = rest }, BACK, OUT)
end

-- Цвет надписи «в покое» и время последней вспышки (flashText не чаще FlashMinInterval).
local textColorRest: { [Instance]: Color3 } = setmetatable({}, { __mode = "k" }) :: any
local textFlashAt: { [Instance]: number } = setmetatable({}, { __mode = "k" }) :: any

--[[
	Вспышка цвета надписи: TextColor3 → color сразу и обратно к цвету «в покое» за time (0.35 с,
	Quad Out). С градиентом TextFill цвета перемножаются (белое → золото — золотая вспышка). Не
	чаще раза в UIConfig.Fx.FlashMinInterval на надпись; «меньше движения» — без вспышки.
]]
function UiFx.flashText(label: TextLabel, color: Color3, time: number?)
	if reduced() then
		return
	end
	local now = os.clock()
	if now - (textFlashAt[label] or -math.huge) < Fx.FlashMinInterval then
		return
	end
	textFlashAt[label] = now
	local rest = textColorRest[label]
	if not rest then
		rest = label.TextColor3
		textColorRest[label] = rest
	end
	label.TextColor3 = color
	tween(label, time or MOTION.Roll.Flash, { TextColor3 = rest }, QUAD, OUT)
end

--[[
	Перекраска с переходом: копия градиента лица со СТАРЫМИ цветами накрывает лицо (FxRecolor) и
	тает за time (0.16 с), под ней setCandy уже поставил новые; обводка плавно меняет цвет.
	time = 0 — просто setCandy.
]]
function UiFx.recolor(root: GuiObject, look: string | Color3 | Swatch, time: number?)
	local duration = time or MOTION.Morph.Fade
	local face = UiFx.faceOf(root)
	local fill = face:FindFirstChild("Fill")
	local lip = root:FindFirstChild("Lip")
	local edge = if lip then lip:FindFirstChildOfClass("UIStroke") else nil
	local oldEdge = if edge then edge.Color else nil
	local overlay: Frame? = nil
	if duration > 0 and face ~= root and fill and fill:IsA("UIGradient") and face.BackgroundTransparency < 0.99 then
		local frame = Instance.new("Frame")
		frame.Name = "FxRecolor"
		frame.Active = false
		frame.BackgroundColor3 = WHITE
		frame.BackgroundTransparency = face.BackgroundTransparency
		frame.BorderSizePixel = 0
		frame.Size = UDim2.fromScale(1, 1)
		frame.ZIndex = 1
		copyCorner(root, frame)
		fill:Clone().Parent = frame
		frame.Parent = face
		overlay = frame
	end
	UiFx.setCandy(root, look)
	if overlay then
		local frame = overlay
		tween(frame, duration, { BackgroundTransparency = 1 }, QUAD, OUT)
		task.delay(duration + 0.02, function()
			frame:Destroy()
		end)
	end
	if edge and oldEdge and duration > 0 and edge.Color ~= oldEdge then
		local target = edge.Color
		edge.Color = oldEdge
		tween(edge, duration, { Color = target }, QUAD, OUT)
	end
end

export type RingTimerOptions = {
	colors: { Color3 }?, -- полно → мало (UIConfig.Fishing.TimeBar)
	thickness: number?, -- толщина кольца, px при 720 (UIConfig.Motion.Ring.Thickness)
	pad: number?, -- отступ от элемента, px (UIConfig.Motion.Ring.Pad)
}

--[[
	Кольцо-таймер вокруг элемента (круглого или квадратного): слой FxRingTimer (на pad px больше
	элемента, под его содержимым) из двух половин Left / Right (ClipsDescendants) с кругом в
	каждой; у круга обводка с градиентом прозрачности «половина видна». Убывает по часовой от
	12 часов: правая половина поворачивает свой градиент 180 → 360 за duration / 2, левая — 0 →
	180 следом; цвет идёт colors[1] → [2] → [3]. Только твины: ни одного покадрового эффекта.
	Возвращает stop (всё удаляется).
]]
function UiFx.ringTimer(gui: GuiObject, duration: number, opts: RingTimerOptions?): Stop
	local o: RingTimerOptions = opts or {}
	local cfg = MOTION.Ring
	local colors = o.colors or UIConfig.Fishing.TimeBar
	local thickness = o.thickness or cfg.Thickness
	local pad = o.pad or cfg.Pad
	local half = math.max(duration, 0.02) / 2
	local holder = Instance.new("Frame")
	holder.Name = "FxRingTimer"
	holder.Active = false
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.new(1, pad * 2, 1, pad * 2)
	holder.ZIndex = 0
	local tweens: { Tween } = {}
	local function sideOf(name: string, x: number, from: number, to: number, delay: number)
		local side = Instance.new("Frame")
		side.Name = name
		side.BackgroundTransparency = 1
		side.ClipsDescendants = true
		side.Position = UDim2.fromScale(x, 0)
		side.Size = UDim2.fromScale(0.5, 1)
		side.ZIndex = 0
		local circle = Instance.new("Frame")
		circle.Name = "Circle"
		circle.BackgroundTransparency = 1
		circle.Position = UDim2.fromScale(if x > 0 then -1 else 0, 0)
		circle.Size = UDim2.fromScale(2, 1)
		circle.ZIndex = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = circle
		local ring = Instance.new("UIStroke")
		ring.Color = colors[1] or WHITE
		ring.Thickness = thickness
		ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ring:SetAttribute("BaseThickness", thickness)
		ring.Parent = circle
		local mask = Instance.new("UIGradient")
		mask.Name = "Drain"
		mask.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.499, 0),
			NumberSequenceKeypoint.new(0.5, 1),
			NumberSequenceKeypoint.new(1, 1),
		})
		mask.Rotation = from
		mask.Parent = ring
		circle.Parent = side
		side.Parent = holder
		local info = TweenInfo.new(half, LINEAR, OUT, 0, false, delay)
		local turn = TweenService:Create(mask, info, { Rotation = to })
		turn:Play()
		table.insert(tweens, turn)
		if #colors >= 2 then
			table.insert(tweens, tween(ring, half, { Color = colors[2] }, LINEAR, OUT))
		end
		if #colors >= 3 then
			table.insert(tweens, tween(ring, half, { Color = colors[3] }, LINEAR, OUT, half))
		end
	end
	sideOf("Right", 0.5, 180, 360, 0)
	sideOf("Left", 0, 0, 180, half)
	holder.Parent = gui
	local thread = task.delay(duration + 0.05, function()
		holder:Destroy()
	end)
	return function()
		if coroutine.status(thread) == "suspended" then
			pcall(task.cancel, thread)
		end
		for _, playing in tweens do
			playing:Cancel()
		end
		holder:Destroy()
	end
end

--------------------------------------------------------------------------------
-- Счётчики, радуга, полоски, вспышка, полёт значка, шлейф, тряска камеры
--------------------------------------------------------------------------------

export type CountOptions = {
	bump: boolean?, -- каждое новое число чуть «подпрыгивает» (1.06 → 1 за 0.1 с), не чаще 12 раз в секунду
}

-- Число «набегает» от from до to за time (0.8 с, Quad Out). format — функция или "%d" и т.п.
function UiFx.countUp(
	label: GuiObject,
	from: number,
	to: number,
	time: number?,
	format: ((value: number) -> string) | string | nil,
	opts: CountOptions?
): Stop
	local bump = opts ~= nil and opts.bump == true
	local lastBump = -math.huge
	local shown = math.floor(from + 0.5)
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
		local value = from + (to - from) * eased
		target.Text = render(value)
		local whole = math.floor(value + 0.5)
		if bump and whole ~= shown and elapsed - lastBump >= 1 / 12 then
			lastBump = elapsed
			UiFx.bump(label, 1.06, 0.1)
		end
		shown = whole
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
	local speed = (o.speed or 0.35) * (if reduced() then MOTION.Reduced.Rainbow else 1)
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

--[[
	Вспышка на весь экран: цвет с прозрачностью from (0.6 — лёгкий отсвет) держится hold секунд и
	тает за time (0.25 с). Не чаще 3 раз в секунду (UIConfig.Fx.FlashMinInterval): лишние вызовы
	молча пропускаются. Для кульминаций — UiFx.flashBig (но не для приземления улова: почти
	сплошной экран на телефоне слепит и прячет саму рыбу — там UiFx.shockwave и края экрана).
]]
local lastFlash = -math.huge
function UiFx.flash(layer: GuiBase2d, color: Color3?, time: number?, from: number?, hold: number?)
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
	frame.BackgroundTransparency = math.clamp(from or 0.6, 0, 1)
	frame.BorderSizePixel = 0
	frame.ZIndex = 100
	frame.Active = false
	frame.Parent = layer
	local duration = time or 0.25
	local wait = math.max(hold or 0, 0)
	tween(frame, duration, { BackgroundTransparency = 1 }, QUAD, OUT, wait)
	task.delay(wait + duration + 0.02, function()
		frame:Destroy()
	end)
end

-- Большая вспышка: почти сплошной цвет (0.12), держится 0.05 с и тает за 0.45 с. То же
-- ограничение частоты, что у flash. Сейчас не используется (приземление улова — UiFx.shockwave).
function UiFx.flashBig(layer: GuiBase2d, color: Color3?)
	UiFx.flash(layer, color, 0.45, 0.12, 0.05)
end

export type ShockwaveOptions = {
	color: Color3?, -- цвет толстого кольца (белый)
	colors: { Color3 }?, -- … или градиент по кольцу (радуга мифической)
	size: number?, -- до какого диаметра расходится кольцо, в высотах слоя (1.3)
	time: number?, -- 0.45 с
	thickness: number?, -- толщина кольца на экране 720 px (14; на телефоне тоньше)
	glow: number?, -- мягкий диск в центре: прозрачность в начале (0.55; 1 — без диска)
	z: number?, -- ZIndex (60: над виджетами, под вспышкой и краями экрана)
}

--[[
	Удар в точке (приземление рыбы): из origin (доли слоя) расходится толстое кольцо цвета (или
	градиента), за ним — тонкое белое; в центре на миг мягкий диск, он тает быстрее колец. Середина
	не закрыта (то, что приземлилось, видно) и на весь экран ничего не светит — это не вспышка.
	Только твины; всё удаляется само (FxShock*).
]]
function UiFx.shockwave(layer: GuiBase2d, origin: Vector2, opts: ShockwaveOptions?)
	local o: ShockwaveOptions = opts or {}
	local time = o.time or 0.45
	local size = o.size or 1.3
	local z = o.z or 60
	local k = math.clamp(screenUnit(layer) / Fx.StrokeHeight, 0.65, 1.5)
	local made: { Instance } = {}
	local function circle(name: string, from: number): Frame
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(origin.X, origin.Y)
		frame.SizeConstraint = Enum.SizeConstraint.RelativeYY
		frame.Size = UDim2.fromScale(from, from)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.ZIndex = z
		frame.Active = false
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = frame
		frame.Parent = layer
		table.insert(made, frame)
		return frame
	end
	-- Кольцо начинается чуть шире того, что приземлилось (0.3 высоты слоя: снаружи ореола рыбы), и расходится.
	local function ring(name: string, color: Color3, px: number, to: number, ringTime: number)
		local frame = circle(name, math.min(0.3, to))
		local stroke = Instance.new("UIStroke")
		stroke.Color = color
		stroke.Thickness = px
		stroke.Transparency = 0.05
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = frame
		if name == "FxShock" and o.colors and #o.colors > 1 then
			stroke.Color = WHITE
			local gradient = Instance.new("UIGradient")
			gradient.Color = UiFx.sequence(o.colors)
			gradient.Rotation = 30
			gradient.Parent = stroke
		end
		tween(frame, ringTime, { Size = UDim2.fromScale(to, to) }, QUAD, OUT)
		tween(stroke, ringTime, { Transparency = 1, Thickness = px * 0.35 }, QUAD, IN)
	end
	local thick = (o.thickness or 14) * k
	ring("FxShock", o.color or WHITE, thick, size, time)
	task.delay(0.06, function()
		if layer.Parent then
			ring("FxShockInner", WHITE, math.max(thick * 0.4, 2), size * 0.72, time * 0.9)
		end
	end)
	local glow = o.glow or 0.55
	if glow < 1 then
		local disc = circle("FxShockGlow", 0.08)
		disc.BackgroundColor3 = o.color or WHITE
		disc.BackgroundTransparency = glow
		tween(disc, time * 0.55, { Size = UDim2.fromScale(size * 0.4, size * 0.4) }, QUAD, OUT)
		tween(disc, time * 0.55, { BackgroundTransparency = 1 }, QUAD, IN)
	end
	task.delay(time + 0.1, function()
		for _, item in made do
			item:Destroy()
		end
	end)
end

--------------------------------------------------------------------------------
-- «Толчок» поля зрения камеры (один владелец Camera.FieldOfView)
--------------------------------------------------------------------------------

type Punch = { deg: number, tIn: number, tOut: number, t: number, cancelled: boolean, easeIn: boolean }
local punches: { Punch } = {}
local fovJob: Stop? = nil
local fovCamera: Camera? = nil
local fovBase = 70
local fovWritten: number? = nil

local function punchOffset(p: Punch): number?
	if p.cancelled then
		return nil
	end
	if p.t < p.tIn then
		local k = p.t / p.tIn
		if p.easeIn then
			return p.deg * (1 - math.cos(k * math.pi / 2)) -- Sine In: «замах» набирает ход
		end
		return p.deg * (1 - (1 - k) * (1 - k)) -- Quad Out
	end
	local k = (p.t - p.tIn) / p.tOut
	if k >= 1 then
		return nil
	end
	return p.deg * (0.5 + 0.5 * math.cos(math.pi * k)) -- Sine InOut обратно к 0
end

--[[
	Камера на миг «приближается» (deg < 0 — уже поле зрения) или «отъезжает» (deg > 0): за tIn
	(0.08 с, Quad Out) до base + deg, за tOut (0.35 с, Sine) обратно. Единственный владелец
	Camera.FieldOfView: запоминает базовое значение, складывает одновременные толчки, ограничивает
	сумму ±UIConfig.Fx.FovPunchMax (8°) и в конце возвращает базу. Если FOV поменял кто-то другой,
	его значение становится новой базой. Покадрово (общий планировщик). Возвращает stop (этот толчок
	перестаёт действовать со следующего кадра). easeIn — «замах» (Sine In вместо Quad Out): камера
	плавно набирает ход к пику, например +2° перед ударом −6° (кульминация улова).
]]
function UiFx.fovPunch(deg: number, tIn: number?, tOut: number?, easeIn: boolean?): Stop
	local camera = Workspace.CurrentCamera
	if not camera or deg == 0 then
		return noop
	end
	local punch: Punch = {
		deg = deg,
		tIn = math.max(tIn or 0.08, 0.001),
		tOut = math.max(tOut or 0.35, 0.001),
		t = 0,
		cancelled = false,
		easeIn = easeIn == true,
	}
	table.insert(punches, punch)
	if not fovJob then
		fovCamera = camera
		fovBase = camera.FieldOfView
		fovWritten = nil
		fovJob = UiFx.schedule(function(dt: number): boolean
			local current = Workspace.CurrentCamera
			if current ~= fovCamera then
				-- Камеру заменили: новая начинает со своего значения.
				fovCamera = current
				fovWritten = nil
				if current then
					fovBase = current.FieldOfView
				end
			end
			if not current then
				return false
			end
			if fovWritten and math.abs(current.FieldOfView - fovWritten) > 1e-3 then
				fovBase = current.FieldOfView -- поле зрения поменял кто-то другой
			end
			local sum = 0
			local index = 1
			while index <= #punches do
				local p = punches[index]
				p.t += dt
				local offset = punchOffset(p)
				if offset then
					sum += offset
					index += 1
				else
					table.remove(punches, index)
				end
			end
			local limit = Fx.FovPunchMax
			local written = fovBase + math.clamp(sum, -limit, limit)
			current.FieldOfView = written
			fovWritten = written
			return #punches > 0
		end, function()
			local current = fovCamera
			if current and (fovWritten == nil or math.abs(current.FieldOfView - fovWritten) <= 1e-3) then
				current.FieldOfView = fovBase
			end
			table.clear(punches)
			fovJob = nil
			fovCamera = nil
			fovWritten = nil
		end)
	end
	return function()
		punch.cancelled = true
	end
end

--------------------------------------------------------------------------------
-- Виньетка по краям экрана
--------------------------------------------------------------------------------

export type VignetteOptions = {
	fadeIn: number?, -- появление, с (0.35, Sine Out; 0 — сразу)
	from: number?, -- прозрачность в начале появления (1 — не видно)
	build: boolean?, -- появление нарастает к концу (Quad In): напряжение «въезжает» в удар
	cycle: { Color3 }?, -- переливаться этими цветами: у каждой стороны свой, бегут по кругу
	pulseTo: number?, -- вторая прозрачность пульса (alpha + 0.2)
	hold: number?, -- сама уйдёт через столько секунд (разовая подсветка)
	fadeOut: number?, -- исчезновение по stop / hold, с (0.25)
	size: number?, -- толщина полос, доля высоты экрана (0.24)
	z: number?, -- ZIndex (90: под вспышкой, над остальным)
}

-- Остановка с плавным исчезновением: fade — за сколько секунд (по умолчанию opts.fadeOut).
export type FadeStop = (fade: number?) -> ()

--[[
	Цветные края экрана (тревога, напряжение, «сердцебиение» редкой рыбы): 4 полосы с градиентом
	от края (прозрачность alpha; 1 — не видно) к середине (прозрачно). color — Color3 или список
	цветов от края внутрь. period — пульс между alpha и opts.pulseTo, полный цикл за period
	секунд (не быстрее UIConfig.Fx.FlashMinInterval — правило «не чаще 3 раз в секунду»).
	opts.cycle — края переливаются (мифическая): цвет каждой стороны бежит по списку по кругу
	(верх → право → низ → лево), один покадровый эффект планировщика, пока виньетка жива; иначе
	только твины. Слой — ScreenGui (полосы заходят и под верхнюю панель, и в вырезы экрана).
	Возвращает stop(fade?): плавно гасит и удаляет (fade 0 — сразу, «обрыв» перед ударом).
	Примеры: напряжение Epic+ — edgeVignette(hud, цвет, 0.5, nil, { from = 0.85, fadeIn = 0.7,
	build = true, size = 0.13 });
	поклёвка — edgeVignette(hud, { Sun.Top, Sun.Bottom }, 0.55, 0.45);
	разовая подсветка — edgeVignette(hud, Gold.Top, 0.8, nil, { fadeIn = 0, hold = 0 }).
]]
function UiFx.edgeVignette(
	layer: GuiBase2d,
	color: Color3 | { Color3 },
	alpha: number,
	period: number?,
	opts: VignetteOptions?
): FadeStop
	local o: VignetteOptions = opts or {}
	local edge = math.clamp(alpha, 0, 1)
	local fadeIn = o.fadeIn or 0.35
	local band = o.size or 0.24
	local area = layer.AbsoluteSize
	local aspect = if area.X > 1 then area.Y / area.X else 0.5
	local holder = Instance.new("Frame")
	holder.Name = "FxVignette"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = o.z or 90
	holder.Active = false

	-- Полоса: часть «за краем» (под панелью/вырезом) сплошная, дальше тает к середине экрана.
	local extra = 0.15
	local bands: { Frame } = {}
	local function makeBand(name: string, position: UDim2, size: UDim2, rotation: number, depth: number)
		local frame = Instance.new("Frame")
		frame.Name = name
		frame.BorderSizePixel = 0
		frame.Position = position
		frame.Size = size
		frame.ZIndex = holder.ZIndex
		frame.BackgroundTransparency = 1
		frame.Active = false
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = rotation
		local solid = extra / (depth + extra)
		gradient.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(solid, 0),
			NumberSequenceKeypoint.new(math.min(0.999, solid + (1 - solid) * 0.4), 0.55),
			NumberSequenceKeypoint.new(1, 1),
		})
		if o.cycle then
			frame.BackgroundColor3 = o.cycle[1] or WHITE -- цвет ведёт планировщик (ниже)
		elseif typeof(color) == "Color3" then
			frame.BackgroundColor3 = color
		else
			frame.BackgroundColor3 = WHITE
			local list = color :: { Color3 }
			-- Цвет: снаружи первый, внутрь — следующие (часть «за краем» — первым цветом).
			local points = { ColorSequenceKeypoint.new(0, list[1] or WHITE) }
			for index, c in list do
				local t = solid + (1 - solid) * (index - 1) / math.max(#list - 1, 1)
				if t > 0 and t < 1 then
					table.insert(points, ColorSequenceKeypoint.new(t, c))
				end
			end
			table.insert(points, ColorSequenceKeypoint.new(1, list[#list] or WHITE))
			gradient.Color = ColorSequence.new(points)
		end
		gradient.Parent = frame
		frame.Parent = holder
		table.insert(bands, frame)
	end
	local bandX = band * aspect -- та же толщина в пикселях по бокам
	local extraX = extra * aspect
	makeBand("Top", UDim2.fromScale(-0.1, -extra), UDim2.fromScale(1.2, band + extra), 90, band)
	makeBand("Bottom", UDim2.fromScale(-0.1, 1 - band), UDim2.fromScale(1.2, band + extra), -90, band)
	makeBand("Left", UDim2.fromScale(-extraX, -0.1), UDim2.fromScale(bandX + extraX, 1.2), 0, bandX)
	makeBand("Right", UDim2.fromScale(1 - bandX, -0.1), UDim2.fromScale(bandX + extraX, 1.2), 180, bandX)
	holder.Parent = layer

	local tweens: { Tween } = {}
	local function setAll(value: number, time: number, style: Enum.EasingStyle, direction: Enum.EasingDirection)
		for _, frame in bands do
			if time <= 0 then
				frame.BackgroundTransparency = value
			else
				table.insert(tweens, tween(frame, time, { BackgroundTransparency = value }, style, direction))
			end
		end
	end
	if o.from then
		for _, frame in bands do
			frame.BackgroundTransparency = math.clamp(o.from, 0, 1)
		end
	end
	if o.build then
		setAll(edge, fadeIn, QUAD, IN)
	else
		setAll(edge, fadeIn, SINE, OUT)
	end

	local alive = true
	local stopCycle: Stop? = nil
	local colors = o.cycle
	if colors and #colors > 0 then
		-- Стороны по кругу: верх, право, низ, лево — каждая на четверть списка дальше.
		local list: { Color3 } = colors
		local count = #list
		local offsets: { [string]: number } = { Top = 0, Right = 0.25, Bottom = 0.5, Left = 0.75 }
		local phase = 0
		local function paint()
			for _, frame in bands do
				local x = ((phase + (offsets[frame.Name] or 0)) % 1) * count
				local index = math.floor(x)
				frame.BackgroundColor3 = list[index % count + 1]:Lerp(list[(index + 1) % count + 1], x - index)
			end
		end
		paint()
		stopCycle = UiFx.schedule(function(dt: number): boolean
			if holder.Parent == nil then
				return false
			end
			phase += dt * 0.8
			paint()
			return true
		end)
	end
	local pulseThread: thread? = nil
	if period then
		local cycle = math.max(period, Fx.FlashMinInterval)
		local low = math.clamp(o.pulseTo or (edge + 0.2), 0, 1)
		pulseThread = task.delay(fadeIn, function()
			pulseThread = nil
			if not alive then
				return
			end
			for _, frame in bands do
				local looping = TweenService:Create(
					frame,
					TweenInfo.new(cycle / 2, SINE, INOUT, -1, true),
					{ BackgroundTransparency = low }
				)
				looping:Play()
				table.insert(tweens, looping)
			end
		end)
	end

	local function stop(fade: number?)
		if not alive then
			return
		end
		alive = false
		local thread = pulseThread
		pulseThread = nil
		if thread and coroutine.status(thread) == "suspended" then
			pcall(task.cancel, thread)
		end
		for _, playing in tweens do
			playing:Cancel()
		end
		table.clear(tweens)
		local time = fade or o.fadeOut or 0.25
		if time <= 0 or holder.Parent == nil then
			if stopCycle then
				stopCycle()
			end
			holder:Destroy()
			return
		end
		for _, frame in bands do
			tween(frame, time, { BackgroundTransparency = 1 }, QUAD, IN)
		end
		task.delay(time + 0.02, function()
			holder:Destroy()
		end)
	end
	if o.hold then
		task.delay(fadeIn + o.hold, function()
			stop()
		end)
	end
	return stop
end

export type FlyOptions = {
	text: string?, -- значок ("🐟")
	color: Color3?, -- цвет значка-знака (не эмодзи: «★» и т. п.; с тёмной обводкой)
	time: number?, -- 0.6 с (у каждого значка)
	size: number?, -- размер в высотах слоя (0.09)
	arc: number?, -- высота дуги (доля высоты слоя, 0.22)
	onArrive: (() -> ())?, -- на месте последний значок (например, UiFx.bump(счётчика))
	count: number?, -- сколько значков летит (1; UIConfig.Motion.Fly.Count по редкости, до 6)
	gap: number?, -- между вылетами значков, с (UIConfig.Motion.Fly.Gap)
	onEach: ((index: number) -> ())?, -- на месте i-й значок (маленький «тик» счётчика)
	texts: { string }?, -- значки по очереди вместо одного text (🐟, ★, …)
}

--[[
	Значки летят по дуге от одного элемента к другому (рыба из карточки в счётчик улова). С count
	больше 1 они сперва разлетаются из центра from (Quad Out, UIConfig.Motion.Fly.Scatter, на
	Spread px в случайные стороны), потом летят по очереди через gap; onEach(i) — на прилёте
	каждого, onArrive — после последнего. Один покадровый эффект на все значки.
]]
function UiFx.flyTo(layer: GuiBase2d, from: GuiObject, to: GuiObject, opts: FlyOptions?): Stop
	local o: FlyOptions = opts or {}
	local cfg = MOTION.Fly
	local base = layer.AbsolutePosition
	local area = layer.AbsoluteSize
	local width, height = math.max(area.X, 1), math.max(area.Y, 1)
	local a = from.AbsolutePosition + from.AbsoluteSize / 2 - base
	local b = to.AbsolutePosition + to.AbsoluteSize / 2 - base
	local duration = o.time or 0.6
	local count = math.clamp(math.floor(o.count or 1), 1, 6)
	local scatter = if count > 1 then cfg.Scatter else 0
	local gap = if count > 1 then (o.gap or cfg.Gap) else 0
	local size = o.size or 0.09
	type Flyer = { icon: TextLabel, start: Vector2, apex: Vector2, arrived: boolean }
	local flyers: { Flyer } = {}
	for index = 1, count do
		local icon = Instance.new("TextLabel")
		icon.Name = "FxFly"
		icon.BackgroundTransparency = 1
		icon.Text = if o.texts and #o.texts > 0 then o.texts[(index - 1) % #o.texts + 1] else (o.text or "🐟")
		icon.TextScaled = true
		icon.FontFace = FONT
		if o.color then
			icon.TextColor3 = o.color
			icon.TextStrokeColor3 = INK
			icon.TextStrokeTransparency = 0.4
		end
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.SizeConstraint = Enum.SizeConstraint.RelativeYY
		icon.Size = UDim2.fromScale(size, size)
		icon.Position = UDim2.fromScale(a.X / width, a.Y / height)
		icon.ZIndex = 60
		icon.Parent = layer
		local start = a
		if count > 1 then
			local angle = rng:NextNumber(0, math.pi * 2)
			local reach = rng:NextNumber(cfg.Spread[1], cfg.Spread[2])
			start = a + Vector2.new(math.cos(angle), math.sin(angle)) * reach
		end
		local apex = (start + b) / 2 - Vector2.new(0, height * (o.arc or 0.22))
		table.insert(flyers, { icon = icon, start = start, apex = apex, arrived = false })
	end
	local elapsed = 0
	local landed = 0
	return UiFx.schedule(function(dt: number): boolean
		elapsed += dt
		for index, f in flyers do
			if not f.arrived then
				local icon = f.icon
				local s = elapsed / math.max(scatter, 1e-3)
				local t = elapsed - scatter - gap * (index - 1)
				if scatter > 0 and elapsed < scatter then
					-- Разлёт из центра (Quad Out), значок растёт.
					local e = 1 - (1 - s) * (1 - s)
					local p = a:Lerp(f.start, e)
					icon.Position = UDim2.fromScale(p.X / width, p.Y / height)
					local grow = size * (0.4 + 0.6 * e)
					icon.Size = UDim2.fromScale(grow, grow)
				elseif t > 0 then
					local k = math.min(1, t / duration)
					local e = if k < 0.5 then 2 * k * k else 1 - (-2 * k + 2) ^ 2 / 2
					local p = f.start:Lerp(f.apex, e):Lerp(f.apex:Lerp(b, e), e)
					icon.Position = UDim2.fromScale(p.X / width, p.Y / height)
					icon.Rotation = -20 + 40 * e
					local grown = size * (1 + 0.35 * math.sin(math.pi * e) - 0.35 * e)
					icon.Size = UDim2.fromScale(grown, grown)
					if k >= 1 then
						f.arrived = true
						icon.Visible = false
						landed += 1
						local onEach, onArrive = o.onEach, o.onArrive
						if onEach then
							task.spawn(onEach, index)
						end
						if landed == count and onArrive then
							task.spawn(onArrive)
						end
					end
				end
			end
		end
		return landed < count
	end, function()
		for _, f in flyers do
			f.icon:Destroy()
		end
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

-- Всё содержимое элемента плавно становится прозрачным (фон, текст, обводки, 3D-окно).
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
		elseif item:IsA("ViewportFrame") then
			tween(item, duration, { ImageTransparency = 1 }, QUAD, IN) -- 3D-модель (рыба на карточке)
		elseif item:IsA("ImageLabel") or item:IsA("ImageButton") then
			tween(item, duration, { ImageTransparency = 1 }, QUAD, IN)
		elseif item:IsA("UIStroke") then
			tween(item, duration, { Transparency = 1 }, QUAD, IN)
		end
	end
end

local function isText(item: Instance?): boolean
	return item ~= nil and (item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox"))
end

-- Множитель толщины обводок под высоту экрана (fitStrokes): 0.65 на телефоне … до
-- UIConfig.Fx.StrokeMax (обводки форм) / TextStrokeMax (обводки текста: текст перестаёт расти на
-- 1.6 своей «телефонной» величины, обводка — тоже) на больших экранах.
local function screenFactor(): number
	local camera = Workspace.CurrentCamera
	local height = if camera then camera.ViewportSize.Y else Fx.StrokeHeight
	return if height > 1 then height / Fx.StrokeHeight else 1
end

local function fittedStroke(stroke: UIStroke, base: number, raw: number): number
	local text = isText(stroke.Parent)
	local factor = math.clamp(raw, 0.65, if text then Fx.TextStrokeMax else Fx.StrokeMax)
	local floor = if text then Fx.TextStrokeMin else 1
	return math.max(floor, math.floor(base * factor * 2 + 0.5) / 2)
end

--[[
	Обводки (UIStroke с атрибутом BaseThickness — их ставит Theme) нарисованы для экрана высотой
	720 px; здесь их толщина подгоняется под настоящий экран (телефон — тоньше, большой экран —
	толще, но не больше StrokeMax / TextStrokeMax), в том числе у элементов, добавленных позже.
	Обводка текста не тоньше UIConfig.Fx.TextStrokeMin (2 px): белый текст на жёлтом и зелёном
	читается только благодаря ей. Возвращает функцию отвязки.
]]
function UiFx.fitStrokes(root: Instance): Stop
	local camera = Workspace.CurrentCamera
	local factor = 1
	local function apply(item: Instance)
		if item:IsA("UIStroke") then
			local base = item:GetAttribute("BaseThickness")
			if typeof(base) == "number" then
				item.Thickness = fittedStroke(item, base, factor)
			end
		end
	end
	local function applyAll()
		factor = screenFactor()
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

-- Толщина обводки «в покое» на этом экране — та, что ставит fitStrokes (BaseThickness под высоту
-- экрана); без атрибута — текущая. Для эффектов, которые обводку утолщают и потом возвращают.
function UiFx.strokeThickness(stroke: UIStroke): number
	local base = stroke:GetAttribute("BaseThickness")
	if typeof(base) == "number" then
		return fittedStroke(stroke, base, screenFactor())
	end
	return stroke.Thickness
end

-- Множитель шкалы текста для экрана высотой height: 1 на телефоне (390 px), до 1.6 на больших.
local function typeScale(height: number): number
	if height <= 1 then
		return 1
	end
	return math.clamp(height / UIConfig.TypeHeight, 1, UIConfig.TypeMaxScale)
end

--[[
	Размер текста уровня tier ("Title" | "Button" | "Body" | "Small", UIConfig.Type) в пикселях на
	этом экране — столько ставит fitText. Полезно, чтобы рассчитать ширину плашки под текст.
]]
function UiFx.textSize(tier: string): number
	local camera = Workspace.CurrentCamera
	local base = UIConfig.Type[tier] or UIConfig.Type.Body
	return math.floor(base * typeScale(if camera then camera.ViewportSize.Y else 0) + 0.5)
end

-- Ширина символов Montserrat Heavy в долях размера текста (TextSize = высота строки; замерено по
-- шрифту превью, tools/preview/fonts): заглавные и строчные кириллицы и латиницы, цифры, знаки.
local GLYPH_WIDTH: { [number]: number } = {
	[32] = 0.25, -- пробел
	[33] = 0.26, -- !
	[34] = 0.4, -- "
	[40] = 0.31, -- (
	[41] = 0.31, -- )
	[43] = 0.5, -- +
	[44] = 0.25, -- ,
	[45] = 0.32, -- -
	[46] = 0.25, -- .
	[58] = 0.25, -- :
	[63] = 0.5, -- ?
	[171] = 0.53, -- «
	[187] = 0.53, -- »
	[215] = 0.5, -- ×
	[8212] = 0.82, -- —
	[8230] = 0.76, -- …
}

--[[
	Ширина строки text при размере текста px (Montserrat Heavy, как в Theme.label) — оценка по
	символам: заглавная кириллица ≈ 0.68 размера, строчная ≈ 0.59, латиница и цифры уже, пробел и
	знаки препинания ≈ 0.25, эмодзи ≈ 0.82. Для раскладки плашек под текст до того, как он нарисован
	(уведомления); средняя «на букву» для смешанного текста ошибается на 20 % в обе стороны.
]]
function UiFx.textWidth(text: string, px: number): number
	local units = 0
	for _, code in utf8.codes(text) do
		local w = GLYPH_WIDTH[code]
		if w == nil then
			if (code >= 0x410 and code <= 0x42F) or code == 0x401 then
				w = 0.68 -- А…Я, Ё
			elseif (code >= 0x430 and code <= 0x44F) or code == 0x451 then
				w = 0.59 -- а…я, ё
			elseif code >= 65 and code <= 90 then
				w = 0.62 -- A…Z
			elseif (code >= 97 and code <= 122) or (code >= 48 and code <= 57) then
				w = 0.52 -- a…z, 0…9
			elseif code >= 0x2000 then
				w = if code == 0xFE0F or code == 0x200D then 0 else 0.82 -- эмодзи (селектор и ZWJ — без ширины)
			else
				w = 0.55
			end
		end
		units += w
	end
	return units * px
end

--[[
	Шкала текста: у каждой надписи с атрибутом TextTier (Theme.label { Tier = … }) ограничение
	UITextSizeConstraint становится Max = UIConfig.Type[tier] × clamp(H / 390, 1, 1.6), Min = Max − 2
	(H — высота экрана), так что одинаковые по смыслу надписи одного размера на всём экране.
	Работает и для элементов, добавленных позже (копии уведомлений, призраки карточки), и при смене
	размера экрана. Возвращает функцию отвязки (как fitStrokes; вызывается один раз на HUD).
]]
function UiFx.fitText(root: Instance): Stop
	local camera = Workspace.CurrentCamera
	local scale = 1
	local function measure()
		scale = typeScale(if camera then camera.ViewportSize.Y else 0)
	end
	local function apply(item: Instance)
		if not isText(item) then
			return
		end
		local tier = item:GetAttribute("TextTier")
		local base = if typeof(tier) == "string" then UIConfig.Type[tier] else nil
		if not base then
			return
		end
		local size = math.floor(base * scale + 0.5)
		local found = item:FindFirstChildOfClass("UITextSizeConstraint")
		local constraint: UITextSizeConstraint
		if found then
			constraint = found
		else
			constraint = Instance.new("UITextSizeConstraint")
			constraint.Name = "FitText"
			constraint.MaxTextSize = size
			constraint.Parent = item
		end
		-- Порядок: сначала та граница, что не даст Min > Max в промежутке.
		if size >= constraint.MaxTextSize then
			constraint.MaxTextSize = size
			constraint.MinTextSize = math.max(1, size - 2)
		else
			constraint.MinTextSize = math.max(1, size - 2)
			constraint.MaxTextSize = size
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
