--!strict
--[[
	FishingController — рыбалка локального игрока: кнопка действия, поклёвка, мини-игра,
	карточка улова и подсказки (Этап 2). Интерфейс — HUD.Fishing (tools/builder/gui/Fishing.luau),
	стиль «Candy Splash» и вся анимация — tools/builder/gui/STYLE.md §3 и ReplicatedStorage.Shared.UiFx.

	Сервер (FishingService) решает всё сам. Клиент только просит (FishingCast / FishingHook /
	FishingTap / FishingStop) и показывает то, что сервер прислал в FishingState
	(протокол — в шапке RemoteNames).

	  • Кнопка действия (ActionArea.ActionButton) видна, пока удочка в руке персонажа. Это
	    большая круглая «конфета»; цвет, значок и надпись — по состоянию: «ЗАБРОСИТЬ» (Sky 🎣,
	    блик раз в несколько секунд) → «ЖДЁМ…» (Slate ⏳, песочные часы переворачиваются; нажатия
	    не работают; так же после подсечки и CastCooldown секунд после конца рыбалки) →
	    «ПОДСЕЧЬ!» (Sun ❗, пульсирует, светится кольцами) → «ТЯНИ!» (Leaf 💪). Удочка в рюкзаке,
	    а игрок стоит у точки рыбалки своей базы — кнопка «ВЗЯТЬ» (Gold 🎣, зовёт сиянием) берёт
	    удочку в руку. Смена состояния — кнопка выскакивает; нажатие — сжимается (UiFx.press),
	    от каждого касания расходится рябь.
	    То же действие — тап/клик удочкой по миру (Tool.Activated; на тач-экране — не в
	    мини-игре: туда попадают и движения камеры) и клавиша F / R2 на геймпаде
	    (ContextActionService, только пока удочка в руке; не E — E нужна ProximityPrompt).
	    Без тач-экрана на кнопке — подсказка клавиши: «ЗАБРОСИТЬ [F]».
	  • В мини-игре нажатие засчитывается в момент касания кнопки (MouseButton1Down), а не
	    отпускания (двойной тап по «ПОДСЕЧЬ!» сервер не считает промахом — FishingConfig.HookTapGrace).
	  • «СМОТАТЬ» (StopButton, ягодная «пилюля») — пока леска в воде.
	  • Поклёвка (BiteAlert): «КЛЮЁТ!» влетает «ударом», короткая солнечная вспышка, за плашкой
	    вращаются лучи, ❗ по краям качаются, полоска времени тает за Window секунд
	    (зелёная → жёлтая → красная).
	  • Мини-игра (Minigame): стрелка = FishingRules.Needle(U0, Speed, t), где t — сколько секунд
	    прошло с получения "Minigame" (os.clock). Нажатие отправляет серверу это же t, а сервер
	    проверяет попадание по той же формуле — игрок видит ровно то, что проверяет сервер.
	    Заголовок — в цветах редкости (мифическая — бегущая радуга), за стрелкой — шлейф
	    (он проходит ПОД зоной), зона мягко светится. Попал: искры из зоны (из-под полосы),
	    над панелью «ОТЛИЧНО!» / «СУПЕР!» (второе попадание) / «ИДЕАЛЬНО!» (стрелка была не дальше
	    PERFECT_SHARE ширины зоны от её центра), зона выскакивает на новом месте, в кружке
	    попаданий «печатается» ⭐, кнопка подпрыгивает. Промах (Lost miss) или конец времени:
	    мини-игра сразу закрывается, а её копия (FxMinigameMiss) ещё полсекунды краснеет,
	    качается и показывает «МИМО!» / «ВРЕМЯ!». Эффекты никогда не закрывают стрелку и зону.
	  • Карточка улова (CatchCard) — «большое открытие»: экран притемняется, за карточкой
	    вращаются лучи цветов редкости (у редких больше и быстрее; у легендарной и мифической —
	    второе кольцо, вспышка экрана и лёгкая тряска камеры), карточка выскакивает с доворотом,
	    по ней пробегает блик, баннер редкости (мифическая — бегущая радуга со звёздочками),
	    3D-модель рыбы во ViewportFrame (медленно вращается) на мягком свечении со звёздочками,
	    значок мутации «печатается», «НОВАЯ!» — если этот вид пойман впервые за игру, цена
	    «набегает» от 0, конфетти. Закрывается тапом, действием (не раньше CARD_INPUT_LOCK —
	    лишний тап после победного не закроет её) или сама через CatchCardTime: карточка
	    сразу прячется, её копия (FxCardOut) сжимается и тает, а 🐟 летит в счётчик улова
	    (HUD.Status.CatchCounter), и тот подпрыгивает.
	  • Подсказка (Hint, тёмная «пилюля» со значком 💡 / ⚠️, въезжает снизу с пружиной): почему
	    заброс не принят, почему рыба ушла, куда идти. Если игрок с удочкой далеко от точки
	    рыбалки своей базы — к ней тянется дорожка-луч (Beam, только у него).

	Уборка: всё, что живёт с персонажем, — в characterTrove; пока удочка в руке — в rodTrove;
	анимации текущего состояния — в phaseTrove (кадровые эффекты — шлейф, искры, радуга,
	полоска поклёвки — останавливаются вместе с состоянием); «фон» вида кнопки — в lookTrove;
	карточка улова — в cardTrove; конфетти и полёт 🐟, которые доигрывают после карточки, —
	в celebrationTrove. В покое (ничего не происходит) — ни одного покадрового соединения:
	только таймеры и твины.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local FishingConfig = require(Config:WaitForChild("FishingConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local FishingRules = require(Shared:WaitForChild("FishingRules"))
local Net = require(Shared:WaitForChild("Net"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))

local player = Players.LocalPlayer

local ACTION_NAME = "FishingAction"
local PENDING_TIMEOUT = 1.5 -- ответа на заброс нет столько секунд — кнопка снова «Забросить»
local ACTION_DEBOUNCE = 0.05 -- одно нажатие могут поймать два пути ввода (кнопка + удочка)
local HINT_TIME = 3.5 -- сколько висит подсказка о событии, с
local CONTEXT_CHECK_INTERVAL = 0.25 -- как часто проверять, у точки ли рыбалки игрок, с
local CARD_TURN_SPEED = 0.8 -- рыба в карточке поворачивается, радиан в секунду
local CARD_FOV = 40
local CARD_INPUT_LOCK = 0.5 -- столько секунд после появления карточку нельзя закрыть
local PERFECT_SHARE = 0.25 -- «ИДЕАЛЬНО!»: стрелка не дальше этой доли ширины зоны от её центра
local MISS_HOLD = 0.55 -- столько «доигрывает» копия мини-игры после промаха, с
local DIM_TIME = 0.3 -- затемнение за карточкой появляется / уходит, с

local HINT_NEAR = "Жми «Забросить»"
local HINT_FAR = "Встань в сверкающий круг на своём пирсе"
local HINT_TAKE = "Возьми удочку — кнопка справа"
local HINT_FIRST =
	"Удочка — в рюкзаке внизу экрана. Иди на край своего пирса!"

-- Значок подсказки по её виду.
local HINT_ICONS: { [string]: string } = {
	info = "💡",
	warning = "⚠️",
	success = "🎉",
	danger = "⛔",
}

-- Почему рыба ушла (если сервер не прислал свой текст).
local LOST_TEXT: { [string]: string } = {
	early = "Рано! Рыба испугалась и уплыла",
	late = "Поздно — рыба ушла",
	miss = "Мимо! Рыба сорвалась",
	timeout = "Рыба устала ждать и уплыла",
}

-- Почему рыбалка закончилась ("Idle"); причины без текста — молча.
local IDLE_TEXT: { [string]: string } = {
	stop = "Леска смотана",
	moved = "Слишком далеко от края пирса — леска смотана",
	unequipped = "Удочка убрана — леска смотана",
	base = "Леска смотана",
}

local Palette = UIConfig.Palette
local WHITE = UIConfig.White

local COLORS = {
	PipDone = Color3.fromRGB(64, 200, 96), -- закрашенный кружок попадания (его ищут тесты)
	Guide = Color3.fromRGB(255, 214, 80),
}

-- Полоска времени: зелёная → жёлтая → красная.
local TIME_COLORS = { Palette.Leaf.Top, Palette.Sun.Top, Palette.Berry.Bottom }

type Phase = "Idle" | "Pending" | "Waiting" | "Bite" | "Reeling"

-- Вид кнопки действия: цвет — токен палитры UIConfig, Ring — белый ореол (прозрачность, цвет).
type Look = {
	Name: string,
	Caption: string,
	Icon: string,
	Token: string,
	Key: boolean,
	Ring: number,
	RingColor: Color3,
}

local CAST_LOOK: Look = {
	Name = "Cast",
	Caption = "ЗАБРОСИТЬ",
	Icon = "🎣",
	Token = "Sky",
	Key = true,
	Ring = 0.6,
	RingColor = WHITE,
}
local WAIT_LOOK: Look = {
	Name = "Wait",
	Caption = "ЖДЁМ…",
	Icon = "⏳",
	Token = "Slate",
	Key = false,
	Ring = 1,
	RingColor = WHITE,
}
local BITE_LOOK: Look = {
	Name = "Bite",
	Caption = "ПОДСЕЧЬ!",
	Icon = "❗",
	Token = "Sun",
	Key = true,
	Ring = 0,
	RingColor = WHITE,
}
local REEL_LOOK: Look = {
	Name = "Reel",
	Caption = "ТЯНИ!",
	Icon = "💪",
	Token = "Leaf",
	Key = true,
	Ring = 0.35,
	RingColor = Palette.Leaf.Top,
}
-- Удочка в рюкзаке, игрок у точки рыбалки: кнопка берёт удочку в руку.
local TAKE_LOOK: Look = {
	Name = "Take",
	Caption = "ВЗЯТЬ",
	Icon = "🎣",
	Token = "Gold",
	Key = false,
	Ring = 0.15,
	RingColor = Palette.Gold.Top,
}

-- Как выглядит кнопка действия в каждом состоянии.
local LOOKS: { [Phase]: Look } = {
	Idle = CAST_LOOK,
	Pending = WAIT_LOOK,
	Waiting = WAIT_LOOK,
	Bite = BITE_LOOK,
	Reeling = REEL_LOOK,
}

-- Насколько «громко» открывается карточка: чем редче рыба, тем больше лучей, быстрее вращение,
-- ярче лучи, больше звёздочек и дольше набегает цена; Extra — второе кольцо лучей.
type Reveal = {
	Rays: number,
	Speed: number,
	Size: number,
	Alpha: number, -- прозрачность лучей
	Extra: boolean,
	Sparkles: number,
	Count: number,
}
local REVEAL: { [string]: Reveal } = {
	Common = { Rays = 10, Speed = 14, Size = 2.2, Alpha = 0.42, Extra = false, Sparkles = 2.5, Count = 0.7 },
	Rare = { Rays = 12, Speed = 18, Size = 2.35, Alpha = 0.34, Extra = false, Sparkles = 3.5, Count = 0.8 },
	Epic = { Rays = 14, Speed = 22, Size = 2.5, Alpha = 0.27, Extra = false, Sparkles = 5, Count = 0.9 },
	Legendary = { Rays = 14, Speed = 26, Size = 2.6, Alpha = 0.2, Extra = true, Sparkles = 6.5, Count = 1.0 },
	Mythic = { Rays = 16, Speed = 32, Size = 2.75, Alpha = 0.16, Extra = true, Sparkles = 8, Count = 1.1 },
}

-- Надписи и цвета попаданий.
local HIT_FIRST = { text = "ОТЛИЧНО!", colors = { WHITE, Palette.Leaf.Top } }
local HIT_NEXT = { text = "СУПЕР!", colors = { WHITE, Palette.Sky.Top } }
local HIT_PERFECT = { text = "ИДЕАЛЬНО!", colors = { Palette.Gold.Top, Palette.Sun.Bottom } }

type Minigame = {
	Rarity: string,
	U0: number,
	Speed: number,
	ZoneCenter: number,
	ZoneWidth: number,
	Hits: number,
	HitsNeeded: number,
	Timeout: number,
}

type Ui = {
	hud: ScreenGui,
	actionButton: GuiButton,
	actionIcon: TextLabel,
	actionCaption: TextLabel,
	actionRing: UIStroke,
	stopButton: GuiButton,
	biteAlert: Frame,
	biteLabel: TextLabel,
	biteTimer: Frame,
	biteIcons: { GuiObject },
	minigame: Frame,
	title: TextLabel,
	titleFill: UIGradient,
	pips: { Frame },
	track: Frame,
	zone: Frame,
	zoneGlow: Frame,
	zoneFlash: Frame,
	needle: Frame,
	timeFill: Frame,
	hint: TextLabel,
	hintLabel: TextLabel,
	hintIcon: TextLabel,
	dim: Frame,
	rays: Frame,
	card: GuiButton,
	banner: Frame,
	bannerFill: UIGradient,
	rarityLabel: TextLabel,
	fishGlow: Frame,
	viewport: ViewportFrame,
	newStamp: Frame,
	nameLabel: TextLabel,
	nameFill: UIGradient,
	mutationLabel: TextLabel,
	mutationFill: UIGradient,
	mutationIcon: TextLabel,
	mutationCaption: TextLabel,
	infoLabel: TextLabel,
	weightChip: Frame,
	weightLabel: TextLabel,
	priceChip: Frame,
	priceIcon: GuiObject,
	priceLabel: TextLabel,
	counter: Frame,
	counterLabel: TextLabel,
}

-- Исходные значения из шаблона HUD (возвращаются после анимаций).
type Defaults = {
	minigamePosition: UDim2,
	biteTimerSize: UDim2,
	biteTimerColor: Color3,
	zoneHeight: number,
	needleY: number,
	pipColor: Color3,
	hintPosition: UDim2,
	iconRotation: number,
	dimTransparency: number,
	trackLeft: number,
	trackWidth: number,
	trackMidY: number,
	namePosition: UDim2,
	mutationPosition: UDim2,
}

type Guide = { beam: Beam, from: Attachment, to: Attachment, spot: BasePart }

local FishingController = {}

local ui: Ui
local defaults: Defaults
local keyHint = ""

local phase: Phase = "Idle"
local rod: Tool? = nil -- удочка в руке
local offerTake = false -- кнопка «ВЗЯТЬ» (удочка в рюкзаке, игрок у точки рыбалки)
local everEquipped = false -- брал ли игрок удочку в руку за эту игру (подсказка новичку)
local castReadyAt = 0 -- os.clock(), с которого сервер снова примет заброс (CastCooldown)
local cooldownThread: thread? = nil -- вернёт кнопке вид «ЗАБРОСИТЬ», когда кулдаун пройдёт
local cardOpenedAt = -math.huge
local hookSent = false
local minigame: Minigame? = nil
local minigameStart = 0 -- os.clock() получения "Minigame"
local lastTap = -math.huge
local lastAction = -math.huge
local tapNeedle: number? = nil -- где была стрелка при последнем нажатии в мини-игре
local tapZone: number? = nil -- … и где была зона
local pendingThread: thread? = nil
local hintThread: thread? = nil
local eventHint: { text: string, kind: string }? = nil
local contextHint: string? = nil
local guide: Guide? = nil
local shownLook: Look? = nil -- вид кнопки, который сейчас нарисован
local seenSpecies: { [string]: boolean } = {} -- какие виды уже ловили за эту игру («НОВАЯ!»)

local characterTrove = Trove.new()
local rodTrove = Trove.new()
local phaseTrove = Trove.new()
local actionPulseTrove = Trove.new() -- пульс и свечение кнопки на поклёвке (гаснут после подсечки)
local lookTrove = Trove.new() -- «фон» текущего вида кнопки (блик, песочные часы, сияние)
local cardTrove = Trove.new()
local celebrationTrove = Trove.new() -- конфетти и полёт 🐟 (доигрывают после карточки)

--------------------------------------------------------------------------------
-- Мелкие помощники
--------------------------------------------------------------------------------

-- Число из данных сервера: только конечные числа, иначе default.
local function number(value: any, default: number): number
	if typeof(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
	return default
end

-- Заглавные буквы, включая кириллицу (string.upper меняет только латиницу).
local function upper(text: string): string
	local out = {}
	for _, code in utf8.codes(text) do
		if (code >= 0x430 and code <= 0x44F) or (code >= 0x61 and code <= 0x7A) then
			code -= 0x20
		elseif code == 0x451 then
			code = 0x401 -- ё → Ё
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

local function child(parent: Instance, name: string): any
	return parent:WaitForChild(name)
end

-- fn() через delay секунд; отменяется уборкой trove.
local function later(trove: Trove.Trove, delay: number, fn: () -> ())
	trove:Add(task.delay(delay, fn))
end

-- fn() каждые interval секунд (первый раз — через first), пока trove не убран. Только таймеры.
local function every(trove: Trove.Trove, interval: number, fn: () -> (), first: number?)
	local running = true
	local pending: thread? = nil
	local function tick()
		pending = nil
		if not running then
			return
		end
		fn()
		pending = task.delay(interval, tick)
	end
	pending = task.delay(first or interval, tick)
	trove:Add(function()
		running = false
		local thread = pending
		pending = nil
		if thread and coroutine.status(thread) == "suspended" then
			task.cancel(thread)
		end
	end)
end

local function swatchOf(
	style: { Top: Color3, Bottom: Color3, Lip: Color3 }
): { Top: Color3, Bottom: Color3, Lip: Color3 }
	return { Top = style.Top, Bottom = style.Bottom, Lip = style.Lip }
end

local function isRod(instance: Instance): boolean
	return instance:IsA("Tool") and typeof(instance:GetAttribute("RodId")) == "string"
end

local function isAlive(): boolean
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0
end

local function hasBase(): boolean
	local index = player:GetAttribute("BaseIndex")
	return typeof(index) == "number" and index > 0
end

-- Удочка в рюкзаке (не в руке).
local function backpackRod(): Tool?
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return nil
	end
	for _, item in backpack:GetChildren() do
		if isRod(item) then
			return item :: Tool
		end
	end
	return nil
end

local function isLineOut(): boolean
	return phase == "Waiting" or phase == "Bite" or phase == "Reeling"
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Точка рыбалки своей базы: Workspace.Bases.* с тем же BaseIndex, что у игрока.
local function ownFishingSpot(): BasePart?
	local index = player:GetAttribute("BaseIndex")
	local bases = Workspace:FindFirstChild("Bases")
	if typeof(index) ~= "number" or index <= 0 or not bases then
		return nil
	end
	for _, base in bases:GetChildren() do
		if base:GetAttribute("BaseIndex") == index then
			local spot = base:FindFirstChild("FishingSpot")
			return if spot and spot:IsA("BasePart") then spot else nil
		end
	end
	return nil
end

-- Тот же допуск, что проверяет сервер: SpotRadius по горизонтали, SpotMaxHeight по высоте.
local function isNearSpot(root: BasePart, spot: BasePart): boolean
	local offset = root.Position - spot.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return horizontal <= FishingConfig.SpotRadius and math.abs(offset.Y) <= FishingConfig.SpotMaxHeight
end

--------------------------------------------------------------------------------
-- Подсказка внизу экрана и дорожка к точке рыбалки
--------------------------------------------------------------------------------

-- Подсказка въезжает снизу с пружиной, значок выскакивает (у предупреждения — ещё и качается).
local function animateHint(kind: string)
	local hint = ui.hint
	local rest = defaults.hintPosition
	hint.Position = rest + UDim2.fromScale(0, 0.05)
	UiFx.tween(hint, 0.42, { Position = rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UiFx.popIn(hint, { from = 0.7, time = 0.35 })
	UiFx.popIn(ui.hintIcon, { from = 0, time = 0.4, delay = 0.08, rotate = -25 })
	if kind == "warning" or kind == "danger" then
		task.delay(0.45, function()
			if hint.Visible then
				UiFx.wiggle(ui.hintIcon, 16, 3, 0.45)
			end
		end)
	end
end

-- Подсказка о событии (eventHint) важнее постоянной подсказки по месту (contextHint).
local function renderHint(force: boolean?)
	local hint = ui.hint
	local text: string? = nil
	local kind = "info"
	if eventHint then
		text, kind = eventHint.text, eventHint.kind
	elseif contextHint then
		text = contextHint
	end
	if not text then
		hint.Visible = false
		return
	end
	local changed = force == true or not hint.Visible or hint.Text ~= text
	hint.Text = text
	ui.hintLabel.Text = text
	ui.hintIcon.Text = HINT_ICONS[kind] or HINT_ICONS.info
	hint.Visible = true
	if changed then
		animateHint(kind)
	end
end

-- Подсказка о событии: висит HINT_TIME секунд и прячется сама.
local function showHint(text: string, kind: string)
	if hintThread then
		task.cancel(hintThread)
	end
	eventHint = { text = text, kind = kind }
	renderHint(true)
	hintThread = task.delay(HINT_TIME, function()
		hintThread = nil
		eventHint = nil
		renderHint()
	end)
end

local function setContextHint(text: string?)
	if contextHint == text then
		return
	end
	contextHint = text
	renderHint()
end

local function destroyGuide()
	local current = guide
	guide = nil
	if current then
		current.beam:Destroy()
		current.from:Destroy()
		current.to:Destroy()
	end
end

-- Луч от персонажа к точке рыбалки (создаётся только на этом клиенте).
local function createGuide(root: BasePart, spot: BasePart): Guide
	local from = Instance.new("Attachment")
	from.Name = "FishingGuideFrom"
	from.Parent = root
	local to = Instance.new("Attachment")
	to.Name = "FishingGuideTo"
	to.Position = Vector3.new(0, spot.Size.Y / 2 + 0.4, 0)
	to.Parent = spot

	local beam = Instance.new("Beam")
	beam.Name = "FishingGuide"
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = 0.3
	beam.Width1 = 0.8
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(COLORS.Guide)
	beam.Transparency = NumberSequence.new(0.55, 0.15)
	beam.Parent = root
	return { beam = beam, from = from, to = to, spot = spot }
end

local function setGuide(spot: BasePart?)
	local root = rootPart()
	if not spot or not root then
		if guide then
			guide.beam.Enabled = false
		end
		return
	end
	local old = guide
	if old and (old.spot ~= spot or old.from.Parent ~= root) then
		destroyGuide() -- другая база или новый персонаж
	end
	local current = guide or createGuide(root, spot)
	guide = current
	current.beam.Enabled = true
end

--------------------------------------------------------------------------------
-- Кнопка действия и состояния рыбалки
--------------------------------------------------------------------------------

local function currentLook(): Look
	if not rod then
		return TAKE_LOOK
	elseif phase == "Bite" and hookSent then
		return WAIT_LOOK -- подсечка отправлена, ждём мини-игру
	elseif phase == "Idle" and os.clock() < castReadyAt then
		return WAIT_LOOK -- сервер ещё не примет заброс (CastCooldown)
	end
	return LOOKS[phase]
end

-- «Фон» вида кнопки: только таймеры и твины (без покадровых соединений).
local function startLookFx(look: Look)
	lookTrove:Clean()
	local button = ui.actionButton
	local icon = ui.actionIcon
	icon.Rotation = defaults.iconRotation
	if look == CAST_LOOK then
		lookTrove:Add(UiFx.shineLoop(button, { interval = UIConfig.Fx.ShineInterval }))
		every(lookTrove, 4.6, function()
			if button.Visible then
				UiFx.wiggle(icon, 12, 2, 0.5)
			end
		end, 2.2)
	elseif look == TAKE_LOOK then
		lookTrove:Add(UiFx.shineLoop(button, { interval = 2.4, delay = 0.6 }))
		lookTrove:Add(UiFx.glowRing(button, {
			loop = true,
			filled = true,
			color = Palette.Gold.Top,
			scale = 1.45,
			time = 0.9,
			interval = 1.3,
		}))
		every(lookTrove, 2.6, function()
			if button.Visible then
				UiFx.wiggle(icon, 14, 3, 0.5)
			end
		end, 1.2)
	elseif look == WAIT_LOOK then
		-- Песочные часы переворачиваются.
		local turns = 0
		local flip: Tween? = nil
		every(lookTrove, 1.1, function()
			turns += 1
			flip = UiFx.tween(
				icon,
				0.45,
				{ Rotation = defaults.iconRotation + 180 * turns },
				Enum.EasingStyle.Back,
				Enum.EasingDirection.Out
			)
		end, 0.55)
		lookTrove:Add(function()
			if flip then
				flip:Cancel()
			end
			icon.Rotation = defaults.iconRotation
		end)
	elseif look == REEL_LOOK then
		lookTrove:Add(UiFx.glowRing(button, {
			loop = true,
			color = Palette.Leaf.Top,
			scale = 1.32,
			thickness = 4,
			time = 0.7,
			interval = 1.1,
		}))
	end
	-- BITE_LOOK: пульс и свечение — в actionPulseTrove (enterBite), до подсечки.
end

-- Перекрасить кнопку под вид; animate — кнопка выскакивает (смена состояния).
local function applyLook(look: Look, animate: boolean)
	local button = ui.actionButton
	UiFx.setCandy(button, look.Token)
	ui.actionIcon.Text = look.Icon
	ui.actionRing.Color = look.RingColor
	ui.actionRing.Transparency = look.Ring
	startLookFx(look)
	if animate then
		UiFx.popIn(button, { from = 0.8, time = 0.28 })
		UiFx.popIn(ui.actionIcon, { from = 0.2, time = 0.34, delay = 0.04 })
	end
end

local function refreshButtons()
	local look = currentLook()
	local button = ui.actionButton
	local wasVisible = button.Visible
	local visible = rod ~= nil or offerTake
	button.Visible = visible
	ui.actionCaption.Text = look.Caption .. (if look.Key then keyHint else "")
	if look ~= shownLook then
		local first = shownLook == nil
		shownLook = look
		applyLook(look, visible and wasVisible and not first)
	end
	if visible and not wasVisible then
		-- Кнопка появилась (удочка в руке / «ВЗЯТЬ»): выскакивает с доворотом.
		UiFx.popIn(button, { from = 0.3, time = 0.4, rotate = -12 })
		UiFx.popIn(ui.actionIcon, { from = 0, time = 0.4, delay = 0.12, rotate = -30 })
	end
	local stop = ui.stopButton
	local stopVisible = rod ~= nil and isLineOut()
	if stopVisible and not stop.Visible then
		stop.Visible = true
		UiFx.popIn(stop, { from = 0.2, time = 0.35, delay = 0.05 })
	elseif not stopVisible then
		stop.Visible = false
	end
end

-- Подсказка по месту: с удочкой, без рыбалки — «жми» у точки или «иди к кругу» + луч;
-- без удочки в руке у точки рыбалки — «возьми удочку» (и кнопка «ВЗЯТЬ»); новичку,
-- который ещё ни разу не брал удочку, — где она и куда идти.
local function refreshContextHint()
	local text: string? = nil
	local guideTo: BasePart? = nil
	local root = rootPart()
	local spot = ownFishingSpot()
	local near = root ~= nil and spot ~= nil and isNearSpot(root, spot)
	local take = rod == nil and phase == "Idle" and near and isAlive() and backpackRod() ~= nil
	if take ~= offerTake then
		offerTake = take
		refreshButtons()
	end
	if not ui.card.Visible then
		if rod and phase == "Idle" and root and spot then
			if near then
				text = HINT_NEAR
			else
				text = HINT_FAR
				guideTo = spot
			end
		elseif take then
			text = HINT_TAKE
		elseif not rod and not everEquipped and hasBase() and backpackRod() then
			text = HINT_FIRST
		end
	end
	setGuide(guideTo)
	setContextHint(text)
end

local function cancelPending()
	local thread = pendingThread
	pendingThread = nil
	if thread and thread ~= coroutine.running() then
		task.cancel(thread)
	end
end

-- Новое состояние: убираем анимации и окна прошлого, обновляем кнопки.
local function setPhase(newPhase: Phase)
	cancelPending()
	phaseTrove:Clean()
	actionPulseTrove:Clean()
	phase = newPhase
	if newPhase ~= "Reeling" then
		minigame = nil
	end
	ui.biteAlert.Visible = false
	ui.minigame.Visible = false
	refreshButtons()
	refreshContextHint()
end

-- Сервер не примет новый заброс ещё CastCooldown секунд — кнопка до тех пор тусклая.
local function startCastCooldown()
	castReadyAt = os.clock() + FishingConfig.CastCooldown
	local previous = cooldownThread
	if previous and coroutine.status(previous) == "suspended" then
		task.cancel(previous)
	end
	cooldownThread = task.delay(FishingConfig.CastCooldown, function()
		cooldownThread = nil
		castReadyAt = 0 -- таймер может сработать на долю микросекунды «раньше» os.clock()
		refreshButtons()
	end)
end

-- Конец рыбалки (кулдаун заброса — только если леска была в воде).
local function endSession()
	local cooldown = isLineOut() or phase == "Pending"
	hookSent = false
	setPhase("Idle")
	if cooldown then
		startCastCooldown()
		refreshButtons()
	end
end

--------------------------------------------------------------------------------
-- Карточка улова
--------------------------------------------------------------------------------

local function updateCounter(total: number)
	if total <= 0 then
		return
	end
	local text = `Улов: {math.floor(total)}`
	if ui.counterLabel.Text ~= text or not ui.counter.Visible then
		ui.counter.Visible = true
		ui.counterLabel.Text = text
		UiFx.bump(ui.counter, 1.3, 0.3)
	end
end

-- Копия карточки сжимается и тает, пока сама карточка уже спрятана (её модель убирается сразу).
local function ghostCard(): GuiObject
	local ghost = ui.card:Clone()
	ghost.Name = "FxCardOut"
	ghost.Active = false
	pcall(function()
		(ghost :: any).Interactable = false -- копия не ловит нажатия (где свойство есть)
	end)
	for _, item in ghost:GetDescendants() do
		if item.Name == "FxSparkle" then
			item:Destroy() -- застывшие звёздочки выглядят странно
		end
	end
	local viewport = ghost:FindFirstChild("Viewport")
	local camera = viewport and viewport:FindFirstChildOfClass("Camera")
	if viewport and viewport:IsA("ViewportFrame") and camera then
		viewport.CurrentCamera = camera
	end
	ghost.Parent = ui.card.Parent
	UiFx.popOut(ghost, { time = 0.22, to = 0.45, destroy = true })
	UiFx.fadeOut(ghost, 0.2)
	return ghost
end

local function closeCard()
	local card = ui.card
	local wasOpen = card.Visible
	if wasOpen then
		ghostCard()
	end
	cardTrove:Clean()
	card.Visible = false
	if wasOpen then
		-- Затемнение уходит, 🐟 летит в счётчик улова.
		local dim = ui.dim
		UiFx.tween(dim, DIM_TIME * 0.8, { BackgroundTransparency = 1 })
		later(cardTrove, DIM_TIME * 0.8, function()
			dim.Visible = false
		end)
		local counter = ui.counter
		if counter.Visible then
			celebrationTrove:Add(UiFx.flyTo(ui.hud, card, counter, {
				text = "🐟",
				time = 0.6,
				size = 0.1,
				onArrive = function()
					if counter.Visible then
						UiFx.bump(counter, 1.32, 0.35)
						UiFx.shine(counter, 0.5)
						UiFx.sound("pop", 0.35)
					end
				end,
			}))
		end
		UiFx.sound("swoosh", 0.3)
	end
	refreshContextHint()
end

-- Модель рыбы: Assets.Fish.<Id>.<мутация или Normal>.
local function fishTemplate(fish: FishingRules.FishData): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local fishFolder = assets and assets:FindFirstChild("Fish")
	local variants = fishFolder and fishFolder:FindFirstChild(fish.Id)
	if not variants then
		return nil
	end
	local model = variants:FindFirstChild(fish.Mutation or "Normal") or variants:FindFirstChild("Normal")
	return if model and model:IsA("Model") then model else nil
end

-- Рыба во ViewportFrame: центр габаритов в нуле, камера сбоку, рыба медленно вращается.
local function showFishModel(fish: FishingRules.FishData)
	local template = fishTemplate(fish)
	if not template then
		return
	end
	local model = cardTrove:Add(template:Clone())
	local box, size = model:GetBoundingBox()
	local centred = model:GetPivot() - box.Position
	model:PivotTo(centred)
	model.Parent = ui.viewport

	local camera = cardTrove:Add(Instance.new("Camera"))
	camera.FieldOfView = CARD_FOV
	local radius = math.max(size.Magnitude / 2, 0.5)
	local distance = radius / math.tan(math.rad(CARD_FOV / 2)) * 1.05
	camera.CFrame = CFrame.lookAt(Vector3.new(0, radius * 0.35, distance), Vector3.zero)
	camera.Parent = ui.viewport
	ui.viewport.CurrentCamera = camera

	local yaw = 0
	cardTrove:Connect(RunService.RenderStepped, function(dt: number)
		yaw = (yaw + dt * CARD_TURN_SPEED) % (2 * math.pi)
		model:PivotTo(CFrame.Angles(0, yaw, 0) * centred)
	end)
end

local function fillCard(fish: FishingRules.FishData)
	local rarity = FishingRules.GetRarity(fish.Rarity)
	local style = UIConfig.Rarity[fish.Rarity] or UIConfig.Rarity.Common

	-- Баннер редкости (мифическая — радуга, её запускает openCard).
	UiFx.setCandy(ui.banner, swatchOf(style))
	if style.Rainbow then
		ui.bannerFill.Color = UiFx.sequence(UIConfig.Rainbow)
		ui.bannerFill.Rotation = 0
	else
		ui.bannerFill.Rotation = 90
	end
	ui.rarityLabel.Text = upper(if rarity then rarity.Name else fish.Rarity)
	for _, name in { "Halo", "Disc" } do
		local disc = ui.fishGlow:FindFirstChild(name)
		if disc and disc:IsA("GuiObject") then
			disc.BackgroundColor3 = style.Top
		end
	end
	ui.nameLabel.Text = FishingRules.DisplayName(fish)
	ui.nameFill.Color = ColorSequence.new(WHITE, UiFx.lighten(style.Top, 0.25))

	-- Значок мутации (Gold / Neon / Rainbow); без мутации имя опускается на его место.
	local mutationText = FishingRules.MutationLabel(fish)
	local mutationStyle = if fish.Mutation then UIConfig.Mutations[fish.Mutation] else nil
	ui.mutationLabel.Visible = mutationText ~= nil
	ui.mutationLabel.Text = mutationText or ""
	ui.mutationCaption.Text = mutationText or ""
	if mutationStyle then
		UiFx.setCandy(ui.mutationLabel, swatchOf(mutationStyle))
		ui.mutationIcon.Text = mutationStyle.Icon
		if mutationStyle.Effect == "rainbow" then
			ui.mutationFill.Color = UiFx.sequence(UIConfig.Rainbow)
			ui.mutationFill.Rotation = 0
		else
			ui.mutationFill.Rotation = 90
		end
	end
	ui.nameLabel.Position = if mutationText
		then defaults.namePosition
		else defaults.namePosition:Lerp(defaults.mutationPosition, 0.5)

	local kg = FishingRules.FormatKg(fish.Kg)
	local value = math.round(fish.Value)
	ui.infoLabel.Text = `{kg} · цена {value} 💰`
	ui.weightLabel.Text = kg
	ui.priceLabel.Text = "0"
end

-- Эффект значка мутации по её стилю: золото — звёздочки, неон — светится, радуга — бежит.
local function mutationFx(style: { Effect: string, Top: Color3 })
	local badge = ui.mutationLabel
	if style.Effect == "sparkles" then
		cardTrove:Add(UiFx.sparkles(badge, { rate = 4, size = 0.9, area = 0.12 }))
	elseif style.Effect == "pulse" then
		cardTrove:Add(UiFx.glowRing(badge, {
			loop = true,
			filled = true,
			color = style.Top,
			scale = 1.25,
			time = 0.7,
			interval = 0.8,
		}))
	elseif style.Effect == "rainbow" then
		cardTrove:Add(UiFx.rainbow(ui.mutationFill, { speed = 0.6 }))
		cardTrove:Add(UiFx.sparkles(badge, { rate = 3, size = 0.8, area = 0.12, icons = { "✨", "🌈" } }))
	end
end

local function openCard(fish: FishingRules.FishData)
	cardTrove:Clean()
	celebrationTrove:Clean()
	cardOpenedAt = os.clock()
	fillCard(fish)
	showFishModel(fish)

	local style = UIConfig.Rarity[fish.Rarity] or UIConfig.Rarity.Common
	local reveal = REVEAL[fish.Rarity] or REVEAL.Common
	local card = ui.card
	local isNew = not seenSpecies[fish.Id]
	seenSpecies[fish.Id] = true
	card.Visible = true

	-- Затемнение и лучи позади карточки.
	local dim = ui.dim
	dim.Visible = true
	dim.BackgroundTransparency = 1
	UiFx.tween(dim, DIM_TIME, { BackgroundTransparency = defaults.dimTransparency })
	ui.rays.Visible = true
	cardTrove:Add(UiFx.rays(ui.rays, {
		colors = style.Rays,
		count = reveal.Rays,
		speed = reveal.Speed,
		size = reveal.Size,
		transparency = reveal.Alpha,
	}))
	if reveal.Extra then
		cardTrove:Add(UiFx.rays(ui.rays, {
			colors = style.Rays,
			count = math.floor(reveal.Rays * 0.75),
			speed = reveal.Speed * 0.6,
			size = reveal.Size * 1.32,
			width = 0.045,
			transparency = math.min(reveal.Alpha + 0.24, 0.8),
			glow = false,
		}))
	end
	cardTrove:Add(function()
		ui.rays.Visible = false
	end)

	-- Карточка выскакивает с доворотом, блик, баннер, имя.
	UiFx.popIn(card, { from = 0.3, time = 0.4, rotate = -6 })
	later(cardTrove, 0.34, function()
		UiFx.shine(card, 0.75)
	end)
	UiFx.popIn(ui.banner, { from = 0.2, time = 0.36, delay = 0.08 })
	UiFx.popIn(ui.nameLabel, { from = 0.3, time = 0.36, delay = 0.16 })
	if style.Rainbow then
		cardTrove:Add(UiFx.rainbow(ui.bannerFill, { speed = 0.45 }))
		cardTrove:Add(UiFx.sparkles(ui.banner, { rate = 6, size = 0.9, area = 0.1 }))
	end
	later(cardTrove, 0.5, function()
		UiFx.wiggle(child(ui.banner, "StarLeft"), 18, 3, 0.5)
		UiFx.wiggle(child(ui.banner, "StarRight"), 18, 3, 0.5)
	end)

	-- Рыба на мягком свечении, вокруг звёздочки.
	cardTrove:Add(UiFx.pulse(ui.fishGlow, 1.1, 1.4))
	cardTrove:Add(UiFx.sparkles(ui.fishGlow, { rate = reveal.Sparkles, size = 0.24, area = 0.32 }))

	-- Значок мутации «печатается», «НОВАЯ!» — следом.
	local mutationStyle = if fish.Mutation then UIConfig.Mutations[fish.Mutation] else nil
	if ui.mutationLabel.Visible and mutationStyle then
		UiFx.scaleOf(ui.mutationLabel).Scale = 0
		later(cardTrove, 0.45, function()
			UiFx.stamp(ui.mutationLabel, -14, 0.32)
			UiFx.sound("pop", 0.4)
			mutationFx(mutationStyle)
		end)
	end
	local stamp = ui.newStamp
	stamp.Visible = isNew
	if isNew then
		UiFx.scaleOf(stamp).Scale = 0
		later(cardTrove, 0.62, function()
			UiFx.stamp(stamp, 18, 0.3)
			UiFx.sound("pop", 0.35)
		end)
	end

	-- Вес и цена: «пилюли» выскакивают, цена набегает от 0, в конце 💰 подпрыгивает.
	UiFx.popIn(ui.weightChip, { from = 0, time = 0.3, delay = 0.22 })
	UiFx.popIn(ui.priceChip, { from = 0, time = 0.3, delay = 0.28 })
	local value = math.round(fish.Value)
	local countTime = reveal.Count
	later(cardTrove, 0.3, function()
		cardTrove:Add(UiFx.countUp(ui.priceLabel, 0, value, countTime, "%d"))
		local ticks = 0
		every(cardTrove, 0.1, function()
			ticks += 1
			if ticks * 0.1 < countTime then
				UiFx.sound("tick", 0.18)
			end
		end, 0.05)
		later(cardTrove, countTime, function()
			UiFx.bump(ui.priceChip, 1.2, 0.35)
			UiFx.wiggle(ui.priceIcon, 18, 3, 0.45)
			UiFx.shine(ui.priceChip, 0.5)
			UiFx.sound("pop", 0.4)
		end)
	end)

	-- Конфетти; легендарная и мифическая — вспышка и лёгкая тряска камеры.
	celebrationTrove:Add(UiFx.confetti(ui.hud, {
		count = style.ConfettiCount,
		colors = style.Confetti,
		origin = Vector2.new(0.5, 0.42),
		spread = 120,
		power = 1.15,
	}))
	if style.Flash then
		UiFx.flash(ui.hud, style.Top, 0.35)
		cardTrove:Add(UiFx.cameraShake(0.3, 0.5))
		UiFx.sound("swoosh", 0.45)
	end
	UiFx.sound("pop", 0.55)

	cardTrove:Add(task.delay(FishingConfig.CatchCardTime, closeCard))
	refreshContextHint()
end

-- FishData из данных сервера (только нужные поля, с проверкой типов).
local function parseFish(value: any): FishingRules.FishData?
	if typeof(value) ~= "table" or typeof(value.Id) ~= "string" then
		return nil
	end
	local def = FishingRules.GetFish(value.Id)
	local rarity = if typeof(value.Rarity) == "string" then value.Rarity elseif def then def.Rarity else "Common"
	return {
		Id = value.Id,
		Rarity = rarity,
		Mutation = if typeof(value.Mutation) == "string" then value.Mutation else nil,
		Kg = number(value.Kg, 0),
		Value = number(value.Value, 0),
		Income = number(value.Income, 0),
	}
end

--------------------------------------------------------------------------------
-- Поклёвка и мини-игра
--------------------------------------------------------------------------------

local function enterBite(window: number)
	setPhase("Bite")
	hookSent = false
	local alert = ui.biteAlert
	alert.Visible = true

	-- «КЛЮЁТ!» влетает ударом, солнечная вспышка, лучи позади.
	UiFx.slam(alert, 2.3, 0.38)
	UiFx.flash(ui.hud, Palette.Sun.Top, 0.22)
	UiFx.sound("pop", 0.5)
	phaseTrove:Add(UiFx.rays(alert, {
		colors = { Palette.Sun.Top, WHITE, Palette.Gold.Top },
		count = 12,
		speed = 45,
		size = 3.4,
		transparency = 0.22,
	}))
	later(phaseTrove, 0.42, function()
		phaseTrove:Add(UiFx.pulse(alert, 1.06, 0.36))
	end)
	for index, icon in ui.biteIcons do
		every(phaseTrove, 0.55, function()
			UiFx.wiggle(icon, 18, 2, 0.4)
		end, 0.1 + index * 0.14)
	end
	every(phaseTrove, 0.9, function()
		UiFx.wiggle(ui.biteLabel, 4, 2, 0.3)
	end, 0.5)

	-- Полоска времени тает (зелёная → жёлтая → красная).
	local timer = ui.biteTimer
	timer.Size = defaults.biteTimerSize
	local stopTimer = UiFx.timerBar(timer, math.max(window, 0.05), TIME_COLORS)
	phaseTrove:Add(function()
		stopTimer()
		timer.Size = defaults.biteTimerSize
		timer.BackgroundColor3 = defaults.biteTimerColor
	end)

	-- Кнопка зовёт: пульс, солнечное сияние, белый ореол (Ring — в виде BITE_LOOK).
	actionPulseTrove:Add(UiFx.pulse(ui.actionButton, 1.1, 0.4))
	actionPulseTrove:Add(UiFx.glowRing(ui.actionButton, {
		loop = true,
		filled = true,
		color = Palette.Sun.Top,
		scale = 1.6,
		time = 0.55,
		interval = 0.45,
	}))
end

-- Сервер прислал непонятное — подстраиваемся под атрибут FishingState (его ставит сервер).
local function syncFromAttribute()
	local state = player:GetAttribute("FishingState")
	if state == "Waiting" or state == "Reeling" then
		setPhase("Waiting") -- без данных мини-игры можно только ждать или смотать
	elseif state == "Bite" then
		enterBite(FishingConfig.BiteWindow)
	else
		setPhase("Idle")
	end
end

local function startPending()
	setPhase("Pending")
	pendingThread = task.delay(PENDING_TIMEOUT, function()
		pendingThread = nil
		if phase == "Pending" then
			syncFromAttribute()
		end
	end)
end

local function refreshPips(mg: Minigame)
	for index, pip in ui.pips do
		local done = index <= mg.Hits
		pip.Visible = index <= mg.HitsNeeded
		pip.BackgroundColor3 = if done then COLORS.PipDone else defaults.pipColor
		local star = pip:FindFirstChild("Star")
		if star and star:IsA("TextLabel") then
			star.TextTransparency = if done then 0 else 0.72
		end
	end
end

-- Каждый кадр: стрелка по общей формуле и полоска оставшегося времени.
local function updateMinigameFrame()
	local mg = minigame
	if not mg then
		return
	end
	local elapsed = os.clock() - minigameStart
	ui.needle.Position = UDim2.fromScale(FishingRules.Needle(mg.U0, mg.Speed, elapsed), defaults.needleY)
	local spent = math.clamp(elapsed / mg.Timeout, 0, 1)
	ui.timeFill.Size = UDim2.fromScale(1 - spent, 1)
	ui.timeFill.BackgroundColor3 = UiFx.sampleColors(TIME_COLORS, spent)
end

-- Заголовок в цветах редкости (мифическая — бегущая радуга).
local function styleTitle(rarityId: string)
	local style = UIConfig.Rarity[rarityId] or UIConfig.Rarity.Common
	local fill = ui.titleFill
	if style.Rainbow then
		fill.Color = UiFx.sequence(UIConfig.Rainbow)
		fill.Rotation = 0
		phaseTrove:Add(UiFx.rainbow(fill, { speed = 0.5 }))
	else
		-- Низ градиента чуть светлее: на тёмной панели буквы читаются целиком.
		fill.Color = ColorSequence.new(style.Top, UiFx.lighten(style.Bottom, 0.3))
		fill.Rotation = 90
	end
end

local function showMinigame(mg: Minigame)
	local rarity = FishingRules.GetRarity(mg.Rarity)
	ui.title.Text = `{upper(if rarity then rarity.Name else "Неизвестная")} РЫБА!`
	styleTitle(mg.Rarity)
	refreshPips(mg)
	ui.zone.Position = UDim2.fromScale(mg.ZoneCenter, 0.5)
	ui.zone.Size = UDim2.fromScale(mg.ZoneWidth, defaults.zoneHeight)
	ui.zoneFlash.BackgroundTransparency = 1
	ui.minigame.Position = defaults.minigamePosition
	updateMinigameFrame()
	ui.minigame.Visible = true
	UiFx.popIn(ui.minigame, { from = 0.6, time = 0.3 })
	UiFx.popIn(ui.zone, { from = 0.3, time = 0.32, delay = 0.08 })
	for index, pip in ui.pips do
		if pip.Visible then
			local star = pip:FindFirstChild("Star")
			if star and star:IsA("GuiObject") then
				UiFx.popIn(star, { from = 0, time = 0.3, delay = 0.1 + index * 0.06 })
			end
		end
	end
	phaseTrove:Connect(RunService.RenderStepped, updateMinigameFrame)

	-- Шлейф стрелки: копии идут ПОД зоной (не закрывают её); зона мягко «дышит» свечением.
	phaseTrove:Add(UiFx.trail(ui.needle, { count = 3, lag = 0.03, transparency = 0.6 }))
	for _, item in ui.track:GetChildren() do
		if item.Name == "FxGhost" and item:IsA("GuiObject") then
			item.ZIndex = 2
		end
	end
	phaseTrove:Add(UiFx.pulse(ui.zoneGlow, 1.12, 0.9))
end

-- Точка на полосе (доля 0..1) в долях панели мини-игры: центр по высоте полосы.
local function trackPoint(u: number): Vector2
	return Vector2.new(defaults.trackLeft + u * defaults.trackWidth, defaults.trackMidY)
end

-- Попадание: искры из зоны, надпись над панелью, зона выскакивает на новом месте, ⭐, кнопка.
local function celebrateHit(mg: Minigame, oldCenter: number)
	local hitNeedle, hitZone = tapNeedle, tapZone
	local perfect = hitNeedle ~= nil
		and hitZone ~= nil
		and math.abs(hitNeedle - hitZone) <= mg.ZoneWidth * PERFECT_SHARE
	local hit = if perfect then HIT_PERFECT elseif mg.Hits >= 2 then HIT_NEXT else HIT_FIRST
	local origin = trackPoint(oldCenter)

	-- Искры вылетают из-под полосы (ZIndex 3 < полосы): стрелку и зону не закрывают.
	phaseTrove:Add(UiFx.burst(ui.minigame, {
		origin = origin,
		count = if perfect then 24 else 18,
		colors = if perfect
			then { WHITE, Palette.Gold.Top, Palette.Sun.Top, Palette.Berry.Top }
			else { WHITE, Palette.Leaf.Top, Palette.Gold.Top },
		power = if perfect then 1.7 else 1.4,
		z = 3,
	}))
	UiFx.floatText(ui.minigame, hit.text, {
		position = UDim2.fromScale(math.clamp(origin.X, 0.2, 0.8), -0.16),
		size = UDim2.fromScale(if perfect then 0.5 else 0.42, 0.34),
		colors = hit.colors,
		rise = 0.22,
		time = 0.85,
		z = 8,
	})

	-- Зона выскакивает на новом месте и вспыхивает.
	UiFx.popIn(ui.zone, { from = 0.35, time = 0.3 })
	ui.zoneFlash.BackgroundTransparency = 0.05
	UiFx.tween(ui.zoneFlash, 0.35, { BackgroundTransparency = 1 })
	-- Кольцо от зоны (позади неё: ни зону, ни стрелку не закрывает); у идеального — золотое и шире.
	UiFx.glowRing(ui.zone, {
		color = if perfect then Palette.Gold.Top else Palette.Leaf.Top,
		scale = if perfect then 1.8 else 1.5,
		thickness = 3,
		time = 0.45,
	})

	-- ⭐ «печатается» в кружке попадания, кнопка подпрыгивает.
	local pip = ui.pips[mg.Hits]
	local star = pip and pip:FindFirstChild("Star")
	if star and star:IsA("GuiObject") then
		UiFx.stamp(star, -24, 0.3)
	end
	UiFx.bump(ui.actionButton, 1.2, 0.3)
	UiFx.sound("pop", if perfect then 0.55 else 0.4)
end

-- Промах / время вышло: мини-игра закрывается сразу, а её копия ещё полсекунды краснеет,
-- качается и показывает надпись, потом сжимается и тает.
local function missGhost(text: string)
	local source = ui.minigame
	if not source.Visible then
		return
	end
	local ghost = source:Clone()
	ghost.Name = "FxMinigameMiss"
	ghost.Parent = source.Parent
	local track = ghost:FindFirstChild("Track")
	if track and track:IsA("GuiObject") then
		local flash = Instance.new("Frame")
		flash.Name = "FxMissFlash"
		flash.BackgroundColor3 = Palette.Berry.Top
		flash.BackgroundTransparency = 0.2
		flash.BorderSizePixel = 0
		flash.Size = UDim2.fromScale(1, 1)
		flash.ZIndex = 9
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.4, 0)
		corner.Parent = flash
		flash.Parent = track
		UiFx.tween(flash, 0.5, { BackgroundTransparency = 1 })
		local zone = track:FindFirstChild("Zone")
		if zone and zone:IsA("GuiObject") then
			UiFx.setCandy(zone, "Berry")
		end
	end
	UiFx.wiggle(ghost, 4, 3, 0.4)
	UiFx.floatText(ghost, text, {
		position = UDim2.fromScale(0.5, -0.16),
		size = UDim2.fromScale(0.46, 0.36),
		colors = { Palette.Berry.Top, Palette.Berry.Bottom },
		rise = 0.2,
		time = MISS_HOLD + 0.15,
		rotate = -6,
		z = 8,
	})
	UiFx.sound("tick", 0.4)
	task.delay(MISS_HOLD, function()
		UiFx.popOut(ghost, { time = 0.22, to = 0.6, destroy = true })
		UiFx.fadeOut(ghost, 0.2)
	end)
end

--------------------------------------------------------------------------------
-- Действие игрока: забросить / подсечь / тянуть / закрыть карточку
--------------------------------------------------------------------------------

local function tap(now: number)
	if now - lastTap < FishingConfig.TapInterval then
		return -- сервер всё равно не примет чаще
	end
	lastTap = now
	local mg = minigame
	if mg then
		tapNeedle = FishingRules.Needle(mg.U0, mg.Speed, now - minigameStart)
		tapZone = mg.ZoneCenter
	end
	Net.Event("FishingTap"):FireServer(now - minigameStart)
end

-- Взять удочку из рюкзака в руку.
local function takeRod()
	local tool = backpackRod()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if tool and humanoid then
		humanoid:EquipTool(tool)
	end
end

local function tryCloseCard()
	if os.clock() - cardOpenedAt >= CARD_INPUT_LOCK then
		closeCard()
	end
end

-- fromButton: нажатие пришло с самой кнопки (её сжимает UiFx.press); клавиша и тап удочкой
-- по миру «нажимают» кнопку анимацией здесь.
local function doAction(fromButton: boolean?)
	local now = os.clock()
	if now - lastAction < ACTION_DEBOUNCE then
		return
	end
	lastAction = now
	local button = ui.actionButton
	if not fromButton and button.Visible then
		UiFx.bump(button, 0.88, 0.25)
		UiFx.ripple(button, WHITE)
	end
	if ui.card.Visible then
		tryCloseCard()
	elseif not rod then
		if offerTake then
			takeRod()
		end
	elseif phase == "Idle" then
		if now < castReadyAt then
			return -- кулдаун заброса: кнопка тусклая, сервер всё равно откажет
		end
		Net.Event("FishingCast"):FireServer()
		startPending()
		UiFx.sound("swoosh", 0.35)
	elseif phase == "Bite" then
		if not hookSent then
			hookSent = true
			Net.Event("FishingHook"):FireServer()
			actionPulseTrove:Clean() -- подсечка принята: кнопка гаснет до мини-игры
			refreshButtons()
			UiFx.bump(ui.biteAlert, 1.15, 0.25)
		end
	elseif phase == "Reeling" then
		tap(now)
	end
end

local function onActionInput(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		doAction(false)
	end
	return Enum.ContextActionResult.Sink
end

local function requestStop()
	if not isLineOut() then
		return
	end
	Net.Event("FishingStop"):FireServer()
	endSession() -- сервер подтвердит "Idle" { Reason = "stop" }
end

--------------------------------------------------------------------------------
-- Ответы сервера (FishingState)
--------------------------------------------------------------------------------

local function onWaiting(_data: { [string]: any })
	hookSent = false
	setPhase("Waiting")
end

local function onBite(data: { [string]: any })
	enterBite(number(data.Window, FishingConfig.BiteWindow))
end

local function onMinigame(data: { [string]: any })
	local rarity = if typeof(data.Rarity) == "string" then data.Rarity else "Common"
	local rule = FishingRules.GetMinigameRule(rarity)
	local mg: Minigame = {
		Rarity = rarity,
		U0 = number(data.U0, 0),
		Speed = number(data.Speed, rule.Speed),
		ZoneCenter = number(data.ZoneCenter, 0.5),
		ZoneWidth = number(data.ZoneWidth, rule.ZoneWidth),
		Hits = number(data.Hits, 0),
		HitsNeeded = math.clamp(math.floor(number(data.HitsNeeded, rule.Hits)), 1, #ui.pips),
		Timeout = math.max(number(data.Timeout, FishingConfig.MinigameTimeout), 0.1),
	}
	setPhase("Reeling")
	minigame = mg
	minigameStart = os.clock()
	lastTap = -math.huge
	tapNeedle, tapZone = nil, nil
	showMinigame(mg)
end

local function onZone(data: { [string]: any })
	local mg = minigame
	if phase ~= "Reeling" or not mg then
		return
	end
	local oldCenter = mg.ZoneCenter
	mg.ZoneCenter = number(data.ZoneCenter, mg.ZoneCenter)
	mg.Hits = number(data.Hits, mg.Hits + 1)
	refreshPips(mg)
	-- Зона прыгает сразу (без скольжения): где она нарисована, там её и проверяет сервер.
	ui.zone.Position = UDim2.fromScale(mg.ZoneCenter, 0.5)
	celebrateHit(mg, oldCenter)
end

-- Конец рыбалки по слову сервера: его CastCooldown пошёл сейчас — и наш отсчёт заново
-- (если леску сматывал сам игрок, сервер узнал об этом позже клиента).
local function endSessionByServer()
	endSession()
	startCastCooldown()
	refreshButtons()
end

local function onCaught(data: { [string]: any })
	endSessionByServer()
	local fish = parseFish(data.Fish)
	if fish then
		openCard(fish)
	end
	if data.Total ~= nil then
		updateCounter(number(data.Total, 0))
	end
end

local function onLost(data: { [string]: any })
	local reason = if typeof(data.Reason) == "string" then data.Reason else ""
	if phase == "Reeling" then
		missGhost(if reason == "timeout" then "ВРЕМЯ!" else "МИМО!")
	end
	endSessionByServer()
	local text = if typeof(data.Text) == "string" and data.Text ~= "" then data.Text else LOST_TEXT[reason]
	showHint(text or "Рыба ушла", "warning")
end

local function onIdle(data: { [string]: any })
	endSessionByServer()
	local text = if typeof(data.Reason) == "string" then IDLE_TEXT[data.Reason] else nil
	if text then
		showHint(text, "info")
	end
end

local function onDenied(data: { [string]: any })
	if data.Reason == "busy" then
		syncFromAttribute() -- сервер считает, что леска уже в воде
	elseif phase == "Pending" then
		setPhase("Idle")
	end
	if typeof(data.Text) == "string" and data.Text ~= "" then
		showHint(data.Text, "warning")
		UiFx.wiggle(ui.actionButton, 7, 2, 0.3) -- «нет»
	end
end

local HANDLERS: { [string]: ({ [string]: any }) -> () } = {
	Waiting = onWaiting,
	Bite = onBite,
	Minigame = onMinigame,
	Zone = onZone,
	Caught = onCaught,
	Lost = onLost,
	Idle = onIdle,
	Denied = onDenied,
}

local function onFishingState(state: any, data: any)
	local handler = if typeof(state) == "string" then HANDLERS[state] else nil
	if handler then
		handler(if typeof(data) == "table" then data else {})
	end
end

--------------------------------------------------------------------------------
-- Удочка в руке и персонаж
--------------------------------------------------------------------------------

local function unequipRod()
	if not rod then
		return
	end
	rod = nil
	rodTrove:Clean()
	endSession() -- сервер сам смотает леску ("Idle" { Reason = "unequipped" })
end

local function equipRod(tool: Tool)
	if rod == tool then
		return
	end
	unequipRod()
	rod = tool
	offerTake = false
	everEquipped = true
	rodTrove:Connect(tool.Activated, function()
		-- С тач-экрана Activated приходит и от движения камеры / джойстика: в мини-игре
		-- такое «нажатие» мимо зоны стоило бы рыбы, там считается только кнопка.
		-- (Клик мышью по миру на ноутбуке с тач-экраном работает.)
		if phase == "Reeling" and UserInputService:GetLastInputType() == Enum.UserInputType.Touch then
			return
		end
		doAction(false)
	end)
	ContextActionService:BindAction(ACTION_NAME, onActionInput, false, Enum.KeyCode.F, Enum.KeyCode.ButtonR2)
	rodTrove:Add(function()
		ContextActionService:UnbindAction(ACTION_NAME)
	end)
	refreshButtons()
	refreshContextHint()
end

local function onCharacterAdded(character: Model)
	characterTrove:Clean()
	characterTrove:Add(unequipRod)
	characterTrove:Add(destroyGuide)
	local alive = true
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		characterTrove:Connect(humanoid.Died, function()
			alive = false
			unequipRod() -- мёртвым не рыбачат: кнопка прячется сразу, а не при возрождении
		end)
	end
	characterTrove:Connect(character.ChildAdded, function(item: Instance)
		if alive and isRod(item) then
			equipRod(item :: Tool)
		end
	end)
	characterTrove:Connect(character.ChildRemoved, function(item: Instance)
		if item == rod then
			unequipRod()
		end
	end)
	-- Подсказки по месту («возьми удочку», «встань в круг», новичку — где удочка).
	local sinceCheck = 0
	characterTrove:Connect(RunService.Heartbeat, function(dt: number)
		sinceCheck += dt
		if sinceCheck < CONTEXT_CHECK_INTERVAL then
			return
		end
		sinceCheck = 0
		refreshContextHint()
	end)
	endSession()
	for _, item in character:GetChildren() do
		if isRod(item) then
			equipRod(item :: Tool)
		end
	end
end

local function onCharacterRemoving()
	characterTrove:Clean()
	endSession()
end

--------------------------------------------------------------------------------
-- Запуск
--------------------------------------------------------------------------------

local function collectUi(hud: ScreenGui): Ui
	local fishing = child(hud, "Fishing")
	local area = child(fishing, "ActionArea")
	local action = child(area, "ActionButton")
	local alert = child(fishing, "BiteAlert")
	local mini = child(fishing, "Minigame")
	local title = child(mini, "Title")
	local track = child(mini, "Track")
	local zone = child(track, "Zone")
	local pipsFolder = child(mini, "Pips")
	local hint = child(fishing, "Hint")
	local card = child(fishing, "CatchCard")
	local banner = child(card, "Banner")
	local nameLabel = child(card, "NameLabel")
	local mutation = child(card, "MutationLabel")
	local info = child(card, "InfoLabel")
	local weight = child(info, "Weight")
	local price = child(info, "Price")
	local counter = child(child(hud, "Status"), "CatchCounter")

	local pips: { Frame } = {}
	for index = 1, 5 do
		local pip = pipsFolder:FindFirstChild(`Pip{index}`)
		if not pip then
			break
		end
		table.insert(pips, pip :: Frame)
	end

	return {
		hud = hud,
		actionButton = action,
		actionIcon = child(action, "Icon"),
		actionCaption = child(action, "Caption"),
		actionRing = child(action, "Ring"),
		stopButton = child(area, "StopButton"),
		biteAlert = alert,
		biteLabel = child(alert, "Label"),
		biteTimer = child(alert, "Timer"),
		biteIcons = { child(alert, "IconLeft"), child(alert, "IconRight") },
		minigame = mini,
		title = title,
		titleFill = child(title, "TextFill"),
		pips = pips,
		track = track,
		zone = zone,
		zoneGlow = child(zone, "Glow"),
		zoneFlash = child(zone, "Flash"),
		needle = child(track, "Needle"),
		timeFill = child(child(mini, "TimeBar"), "Fill"),
		hint = hint,
		hintLabel = child(hint, "Label"),
		hintIcon = child(hint, "Icon"),
		dim = child(fishing, "CatchDim"),
		rays = child(fishing, "CatchRays"),
		card = card,
		banner = banner,
		bannerFill = child(child(banner, "Face"), "Fill"),
		rarityLabel = child(banner, "RarityLabel"),
		fishGlow = child(card, "FishGlow"),
		viewport = child(card, "Viewport"),
		newStamp = child(card, "NewStamp"),
		nameLabel = nameLabel,
		nameFill = child(nameLabel, "TextFill"),
		mutationLabel = mutation,
		mutationFill = child(child(mutation, "Face"), "Fill"),
		mutationIcon = child(mutation, "Icon"),
		mutationCaption = child(mutation, "Caption"),
		infoLabel = info,
		weightChip = weight,
		weightLabel = child(weight, "Label"),
		priceChip = price,
		priceIcon = child(price, "Icon"),
		priceLabel = child(price, "Label"),
		counter = counter,
		counterLabel = child(counter, "Label"),
	}
end

local function readDefaults(): Defaults
	local track = ui.track
	return {
		minigamePosition = ui.minigame.Position,
		biteTimerSize = ui.biteTimer.Size,
		biteTimerColor = ui.biteTimer.BackgroundColor3,
		zoneHeight = ui.zone.Size.Y.Scale,
		needleY = ui.needle.Position.Y.Scale,
		pipColor = if ui.pips[1] then ui.pips[1].BackgroundColor3 else Palette.Slate.Lip,
		hintPosition = ui.hint.Position,
		iconRotation = ui.actionIcon.Rotation,
		dimTransparency = ui.dim.BackgroundTransparency,
		trackLeft = track.Position.X.Scale - track.AnchorPoint.X * track.Size.X.Scale,
		trackWidth = track.Size.X.Scale,
		trackMidY = track.Position.Y.Scale + (0.5 - track.AnchorPoint.Y) * track.Size.Y.Scale,
		namePosition = ui.nameLabel.Position,
		mutationPosition = ui.mutationLabel.Position,
	}
end

-- Подсказка клавиши на кнопке: есть клавиатура — [F], геймпад — [R2] (на телефоне — ничего).
local function detectKeyHint(): string
	if UserInputService.KeyboardEnabled then
		return " [F]"
	elseif UserInputService.GamepadEnabled then
		return " [R2]"
	end
	return ""
end

-- Текущее состояние (для других контроллеров и тестов).
function FishingController.GetPhase(): string
	return phase
end

function FishingController:Start(hud: ScreenGui)
	ui = collectUi(hud)
	defaults = readDefaults()
	keyHint = detectKeyHint()

	ui.actionButton.Visible = false
	ui.stopButton.Visible = false
	ui.biteAlert.Visible = false
	ui.minigame.Visible = false
	ui.card.Visible = false
	ui.dim.Visible = false
	ui.rays.Visible = false
	ui.hint.Visible = false

	-- Нажатие «сжимает» кнопки (связи живут, пока жив HUD — всю сессию).
	UiFx.press(ui.actionButton, { sound = "click" })
	UiFx.press(ui.stopButton, { sound = "click" })

	-- В мини-игре нажатие считается в момент касания (MouseButton1Down приходит и от касания
	-- пальцем), а не отпускания (Activated): стрелка за время касания успевает уехать.
	ui.actionButton.MouseButton1Down:Connect(function()
		UiFx.ripple(ui.actionButton, WHITE) -- рябь от каждого касания
		if phase == "Reeling" then
			doAction(true)
		end
	end)
	ui.actionButton.Activated:Connect(function()
		if phase ~= "Reeling" then
			doAction(true)
		end
	end)
	ui.stopButton.Activated:Connect(requestStop)
	ui.card.Activated:Connect(tryCloseCard)
	Net.Event("FishingState").OnClientEvent:Connect(onFishingState)

	-- Подстраховка: сервер закончил рыбалку, а ответ потерялся — не держим старое состояние.
	player:GetAttributeChangedSignal("FishingState"):Connect(function()
		local state = player:GetAttribute("FishingState")
		if (state == nil or state == "Idle") and isLineOut() then
			endSession()
		end
	end)
	player:GetAttributeChangedSignal("FishCaught"):Connect(function()
		updateCounter(number(player:GetAttribute("FishCaught"), 0))
	end)
	updateCounter(number(player:GetAttribute("FishCaught"), 0))

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(onCharacterRemoving)
	if player.Character then
		onCharacterAdded(player.Character)
	end
	refreshButtons()
end

return FishingController
