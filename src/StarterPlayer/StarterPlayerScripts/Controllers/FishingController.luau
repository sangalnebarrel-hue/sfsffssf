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
	    единственная «живая» кнопка в покое: блик и лёгкое дыхание) → «ЖДЁМ…» (Water: поплавок
	    покачивается, по кнопке расходятся круги, точки бегут, рыба 1–2 раза «пробует» наживку —
	    кнопка вздрагивает, всплывает «?», поплавок в мире притапливается) → «ПОДСЕЧЬ!» (Sun,
	    знак «!», пульсирует и светится кольцами в такт поклёвке) → «ЛОВИ!» (Leaf 🎯). «ЖДЁМ…» на
	    Slate ⏳ (песочные часы переворачиваются; нажатия не работают) — пока сервер отвечает на
	    заброс, после подсечки и CastCooldown секунд после конца рыбалки. С удочкой, но далеко
	    от точки рыбалки — «К ПИРСУ» (Slate 🧭): нажатие не забрасывает, а показывает дорогу
	    (подсказка и луч к точке вспыхивают). Удочка в рюкзаке, а игрок у точки рыбалки своей
	    базы — «ВЗЯТЬ» (Gold 🎣, зовёт белыми кольцами) берёт удочку в руку. Смена состояния —
	    кнопка выскакивает; нажатие — сжимается (UiFx.press), от каждого касания — рябь.
	    То же действие — тап/клик удочкой по миру (Tool.Activated; на тач-экране — не в
	    мини-игре: туда попадают и движения камеры) и клавиша F / R2 на геймпаде
	    (ContextActionService, только пока удочка в руке; не E — E нужна ProximityPrompt).
	    Без тач-экрана клавиша нарисована на плече кнопки — «клавиша» KeyChip («F» / «R2»).
	  • В мини-игре нажатие засчитывается в момент касания кнопки (MouseButton1Down), а не
	    отпускания (двойной тап по «ПОДСЕЧЬ!» сервер не считает промахом — FishingConfig.HookTapGrace).
	    На тач-экране так же считается касание самой панели мини-игры (Minigame.TapPad).
	  • «СМОТАТЬ» (StopButton, ягодная «пилюля» с 🧵) — пока леска в воде.
	  • Поклёвка (BiteAlert): «КЛЮЁТ!» влетает «ударом», солнечная вспышка, камера на миг
	    «приближается» (UiFx.fovPunch), края экрана светятся солнцем; всё дальше — в одном такте
	    BITE_BEAT: плашка и кнопка пульсируют вместе, кольцо от кнопки на каждый такт, знаки «!»
	    по краям качаются по очереди; к концу окна такт ускоряется. Полоска времени тает за
	    Window секунд (зелёная → жёлтая → красная), за плашкой — спокойные лучи.
	  • Мини-игра (Minigame): стрелка = FishingRules.Needle(U0, Speed, t), где t — сколько секунд
	    прошло с получения "Minigame" (os.clock). Нажатие отправляет серверу это же t, а сервер
	    проверяет попадание по той же формуле — игрок видит ровно то, что проверяет сервер (и
	    зона по ширине всегда нарисована ровно такой, какой её проверяет сервер: «выскакивает»
	    она только по высоте). Заголовок — белый в цвет редкости (мифическая — бегущая радуга),
	    у стрелки — головка ▼ и шлейф из двух голубых теней (ПОД зоной), на зоне едет 🐟
	    (под стрелкой), зона мягко «дышит» светом. Эпическая и выше — обводка панели в цвет
	    редкости, лучи за панелью и цветные края экрана; легендарная и мифическая — ещё «удар»
	    заголовка со вспышкой и стук сердца. Новичку (первые мини-игры за игру) 👆 показывает на
	    кнопку, пока стрелка в зоне. Попадание видно сразу, не дожидаясь сервера (он судит по
	    тому же t): стрелка на миг замирает и вспыхивает золотом, панель вздрагивает, искры, звук
	    всё выше, слово «ОТЛИЧНО!» → «СУПЕР!» → «МЕГА!» (или «ИДЕАЛЬНО!» — стрелка была не дальше
	    PERFECT_SHARE ширины зоны от центра: золото, звёзды, вспышка, края экрана). Последнее,
	    победное попадание здесь не празднуется — это начало карточки улова. Ответ сервера
	    ("Zone") переносит зону (🐟 перепрыгивает за ней) и «печатает» ⭐ в кружке попаданий.
	    Промах (Lost miss) или конец времени: мини-игра сразу закрывается, а её копия
	    (FxMinigameMiss) ещё полсекунды краснеет, качается и показывает «МИМО!» / «ВРЕМЯ!»
	    (🐟 уплывает за край), потом уходит вверх и тает; подсказка с причиной — следом.
	    Эффекты никогда не закрывают стрелку и зону.
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
	  • Подсказка (Hint, «пилюля» в цвет вида — тёмная 💡 / солнечная ⚠️ / ягодная 🚨, значок в
	    белом кружке, въезжает снизу с пружиной; до двух строк): почему заброс не принят, почему
	    рыба ушла, куда идти. Тексты причин — общие с сервером (FishingConfig.Texts). Если игрок с
	    удочкой далеко от точки рыбалки своей базы — к ней тянется дорожка-луч (Beam, только у
	    него). Подсказка, поклёвка и мини-игра — одна колонка внизу по центру (между джойстиком
	    и кнопкой действия; на узком экране колонка сдвигается) и не показываются вместе.

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

-- Подсказки по месту (только клиент). «Встань в круг» — тот же текст, что у сервера (Denied far).
local TEXTS = FishingConfig.Texts
local HINT_NEAR = "Жми «Забросить»"
local HINT_FAR = TEXTS.Denied.far
local HINT_TAKE = "Возьми удочку — кнопка справа"
local HINT_FIRST = "Иди на край своего пирса!"

-- Значок подсказки по её виду (в белом кружке) и цвет «пилюли» (палитра UIConfig).
local HINT_ICONS: { [string]: string } = {
	info = "💡",
	warning = "⚠️",
	success = "🎉",
	danger = "🚨",
}
local HINT_TOKENS: { [string]: string } = {
	warning = "Sun",
	danger = "Berry",
}

-- Почему рыба ушла / почему рыбалка закончилась: общие с сервером тексты по коду причины
-- (FishingConfig.Texts; сервер присылает и сам текст — он важнее). Причины без текста — молча.
local LOST_TEXT: { [string]: string } = TEXTS.Lost
local IDLE_TEXT: { [string]: string } = TEXTS.Idle

local Palette = UIConfig.Palette
local WHITE = UIConfig.White

local COLORS = {
	PipDone = UIConfig.Fishing.PipDone, -- закрашенный кружок попадания (его ищут тесты)
	Guide = UIConfig.Fishing.Guide,
}

-- Полоска поклёвки: зелёная → жёлтая → красная (в мини-игре — своя, без зелёного: UIConfig.Fishing.TimeBar).
local TIME_COLORS = { Palette.Leaf.Top, Palette.Sun.Top, Palette.Berry.Bottom }

type Phase = "Idle" | "Pending" | "Waiting" | "Bite" | "Reeling"

-- Вид кнопки действия: цвет — токен палитры UIConfig, Ring — белый ореол (прозрачность, цвет).
-- Glyph — значок не эмодзи, а знак текстом (белый → золотой, с обводкой): «!» поклёвки;
-- Bobber — вместо значка нарисованный поплавок (ожидание поклёвки).
type Look = {
	Name: string,
	Caption: string,
	Icon: string,
	Token: string,
	Key: boolean,
	Ring: number,
	RingColor: Color3,
	Glyph: boolean?,
	Bobber: boolean?,
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
-- Леска в воде, ждём поклёвку: «водяная» кнопка с поплавком (WATER_DOTS — бегущие точки).
local WATER_LOOK: Look = {
	Name = "Water",
	Caption = "ЖДЁМ…",
	Icon = "",
	Token = "Water",
	Key = false,
	Ring = 1,
	RingColor = WHITE,
	Bobber = true,
}
local BITE_LOOK: Look = {
	Name = "Bite",
	Caption = "ПОДСЕЧЬ!",
	Icon = "!",
	Token = "Sun",
	Key = true,
	Ring = 0,
	RingColor = WHITE,
	Glyph = true,
}
local REEL_LOOK: Look = {
	Name = "Reel",
	Caption = "ЛОВИ!",
	Icon = "🎯",
	Token = "Leaf",
	Key = true,
	Ring = 0.35,
	RingColor = WHITE,
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
-- Удочка в руке, но до точки рыбалки далеко: кнопка не забрасывает, а показывает дорогу.
local FAR_LOOK: Look = {
	Name = "Far",
	Caption = "К ПИРСУ",
	Icon = "🧭",
	Token = "Slate",
	Key = false,
	Ring = 1,
	RingColor = WHITE,
}

-- Как выглядит кнопка действия в каждом состоянии.
local LOOKS: { [Phase]: Look } = {
	Idle = CAST_LOOK,
	Pending = WAIT_LOOK,
	Waiting = WATER_LOOK,
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

-- Надписи и цвета попаданий: от попадания к попаданию всё громче (третье и дальше — радуга),
-- идеальное — золотом.
type HitWord = { text: string, colors: { Color3 }, rainbow: boolean? }
local HIT_FIRST: HitWord = { text = "ОТЛИЧНО!", colors = { Palette.Leaf.Top, Palette.Leaf.Bottom } }
local HIT_NEXT: HitWord = { text = "СУПЕР!", colors = { Palette.Sky.Top, Palette.Sky.Bottom } }
local HIT_MEGA: HitWord = { text = "МЕГА!", colors = UIConfig.Rainbow, rainbow = true }
local HIT_PERFECT: HitWord = {
	text = "ИДЕАЛЬНО!",
	colors = { Palette.Gold.Top, Palette.Gold.Top, WHITE, Palette.Gold.Top, Palette.Gold.Top },
}

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
	-- UI v2, игра (кнопка, поклёвка, мини-игра, подсказка):
	actionArea: Frame,
	actionOutline: UIStroke, -- обводка знака «!» на кнопке (у эмодзи выключена)
	actionFill: UIGradient, -- его заливка белый → золотой
	actionBobber: Frame, -- поплавок вместо значка, пока ждём поклёвку
	keyChip: Frame,
	keyLabel: TextLabel,
	tapCue: TextLabel, -- 👆 новичку
	stopCaption: TextLabel,
	aura: UIStroke, -- обводка панели мини-игры в цвет редкости (эпическая и выше)
	auraFill: UIGradient,
	rider: TextLabel, -- 🐟 на зоне
	timeBar: Frame,
	pipsFrame: Frame,
	tapPad: GuiButton, -- касание панели мини-игры = нажатие (тач-экран)
	hintSocket: Frame,
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
	-- UI v2, игра:
	alertPosition: UDim2,
	hintSize: UDim2,
	riderY: number,
	glowSize: UDim2,
	timeBarSize: UDim2,
	bobberPosition: UDim2,
	tapCuePosition: UDim2,
	stopPosition: UDim2,
	stopSize: UDim2,
	minigameSize: UDim2,
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

--[[
	Центральная колонка (подсказка, поклёвка, мини-игра) стоит по центру экрана, но не ближе
	COLUMN_GAP к джойстику (тач-экран) и к кнопке действия с её лентой подписи: на узком
	экране (маленький телефон, планшет 4:3) колонка сдвигается влево, а подсказка ещё и
	сужается. Сдвиг — Position.X.Offset (X.Scale остаётся 0.5); пересчёт — при смене размера HUD.
]]
local COLUMN_GAP = 24 -- до джойстика и кнопки действия (с запасом на обводки и рамку редкости), px
-- Кнопки Roblox на тач-экране (короткая сторона экрана ≤ 500 px — маленькие): правый край
-- джойстика от левого края; кнопка прыжка — отступы от правого и нижнего края и размер, px.
local STICK_SMALL, STICK_BIG = 95, 180
local JUMP_SMALL = { right = 25, bottom = 20, size = 70 }
local JUMP_BIG = { right = 50, bottom = 90, size = 120 }

local function smallTouchScreen(): boolean
	local camera = Workspace.CurrentCamera
	local view = if camera then camera.ViewportSize else Vector2.new(1280, 720)
	return math.min(view.X, view.Y) <= 500
end

-- Ширина и высота элемента по его Size, SizeConstraint и UISizeConstraint (в px) — без
-- AbsoluteSize: раскладка верна, даже пока HUD ещё не измерен.
local function boxSize(gui: GuiObject, width: number, height: number): Vector2
	local size = gui.Size
	local yy = gui.SizeConstraint == Enum.SizeConstraint.RelativeYY
	local w = size.X.Scale * (if yy then height else width) + size.X.Offset
	local h = size.Y.Scale * height + size.Y.Offset
	local cap = gui:FindFirstChildOfClass("UISizeConstraint")
	if cap then
		w = math.clamp(w, cap.MinSize.X, cap.MaxSize.X)
		h = math.clamp(h, cap.MinSize.Y, cap.MaxSize.Y)
	end
	return Vector2.new(w, h)
end

-- Свойство меняется, только если значение другое (без лишних событий раскладки).
local function assign(gui: GuiObject, key: "Size" | "Position", value: UDim2)
	if (gui :: any)[key] ~= value then
		(gui :: any)[key] = value
	end
end

local laidOutFor: Vector2? = nil -- размер HUD, под который колонка разложена

local function layoutColumn()
	local size = ui.hud.AbsoluteSize
	local width, height = size.X, size.Y
	if width < 2 or height < 2 then
		return
	end
	laidOutFor = size
	local touch = UserInputService.TouchEnabled
	local small = smallTouchScreen()
	-- Кнопка действия — у левого края своей области; лента подписи шире круга.
	local area = boxSize(ui.actionArea, width, height)
	local button = ui.actionButton.Size.Y.Scale * area.Y
	local ribbon = ui.actionButton:FindFirstChild("CaptionRibbon")
	local overhang = if ribbon and ribbon:IsA("GuiObject") then button * math.max(ribbon.Size.X.Scale - 1, 0) / 2 else 0
	local right = width - area.X - overhang - COLUMN_GAP
	-- Слева — джойстик; значок подсказки в кружке выступает за её левый край.
	local socket = ui.hintSocket
	local hintHeight = boxSize(ui.hint, width, height).Y
	local socketOut = socket.Size.X.Scale * hintHeight * socket.AnchorPoint.X
	local left = (if touch then (if small then STICK_SMALL else STICK_BIG) else 0) + COLUMN_GAP + socketOut
	-- Подсказка и мини-игра сужаются до просвета (планшет 4:3, маленький телефон); их
	-- содержимое — в долях, а MinSize панели не даёт ей стать нечитаемой.
	local function fit(gui: GuiObject, rest: UDim2): number
		local target = rest
		local yy = gui.SizeConstraint == Enum.SizeConstraint.RelativeYY
		local cap = gui:FindFirstChildOfClass("UISizeConstraint")
		local w = rest.X.Scale * (if yy then height else width) + rest.X.Offset
		if cap then
			w = math.clamp(w, cap.MinSize.X, cap.MaxSize.X)
		end
		if w > right - left and right - left > 0 then
			w = math.floor(math.max(right - left, if cap then cap.MinSize.X else 0))
			target = UDim2.new(0, w, rest.Y.Scale, rest.Y.Offset) -- смещение UDim — целые пиксели
		end
		assign(gui, "Size", target)
		return w
	end
	local hint = ui.hint
	local widest = math.max(
		fit(hint, defaults.hintSize),
		boxSize(ui.biteAlert, width, height).X,
		fit(ui.minigame, defaults.minigameSize)
	)
	local center = width / 2
	if right - left >= widest then
		center = math.clamp(center, left + widest / 2, right - widest / 2)
	else
		center = (left + right) / 2
	end
	local shift = math.floor(center - width / 2 + 0.5)
	local function place(gui: GuiObject, rest: UDim2): UDim2
		local placed = UDim2.new(rest.X.Scale, shift, rest.Y.Scale, rest.Y.Offset)
		assign(gui, "Position", placed)
		return placed
	end
	defaults.hintPosition = place(hint, defaults.hintPosition)
	defaults.alertPosition = place(ui.biteAlert, defaults.alertPosition)
	defaults.minigamePosition = place(ui.minigame, defaults.minigamePosition)

	-- «СМОТАТЬ» над кнопкой действия: на большом тач-экране (планшет) кнопка прыжка выше —
	-- тогда «пилюля» поднимается, чтобы между ними было COLUMN_GAP; поднятая, она встаёт рядом
	-- с колонкой кнопок справа («ДОМОЙ») — и сужается, если до неё ближе COLUMN_GAP (левый край
	-- не двигается: слева от него — карточка улова).
	local stop = ui.stopButton
	local rest = defaults.stopPosition
	local restSize = defaults.stopSize
	local stopSize =
		Vector2.new(restSize.X.Scale * area.X + restSize.X.Offset, restSize.Y.Scale * area.Y + restSize.Y.Offset)
	local stopRight = width - area.X + rest.X.Scale * area.X + rest.X.Offset + stopSize.X
	local stopBottom = height - area.Y + rest.Y.Scale * area.Y + rest.Y.Offset
	local lift = 0
	if touch then
		local jump = if small then JUMP_SMALL else JUMP_BIG
		local jumpLeft = width - jump.right - jump.size
		local jumpTop = height - jump.bottom - jump.size
		if stopRight + COLUMN_GAP > jumpLeft and stopBottom + COLUMN_GAP > jumpTop then
			lift = math.ceil(stopBottom + COLUMN_GAP - jumpTop)
		end
	end
	local narrow = 0
	local column = ui.hud:FindFirstChild("RightButtons")
	if column and column:IsA("GuiObject") then
		local box = boxSize(column, width, height)
		local columnLeft = column.Position.X.Scale * width + column.Position.X.Offset - column.AnchorPoint.X * box.X
		local columnBottom = column.Position.Y.Scale * height
			+ column.Position.Y.Offset
			+ (1 - column.AnchorPoint.Y) * box.Y
		-- Лента подписи кнопок колонки шире самих кнопок.
		local ribbonOut = 0
		for _, item in column:GetChildren() do
			local band = item:FindFirstChild("CaptionRibbon")
			if item:IsA("GuiObject") and band and band:IsA("GuiObject") then
				ribbonOut = math.max(ribbonOut, box.X * (band.Size.X.Scale - 1) / 2)
			end
		end
		columnLeft -= ribbonOut
		local stopTop = stopBottom - lift - stopSize.Y
		if stopTop < columnBottom + COLUMN_GAP then
			narrow = math.max(math.ceil(stopRight + COLUMN_GAP - columnLeft), 0)
		end
	end
	assign(stop, "Position", UDim2.new(rest.X.Scale, rest.X.Offset, rest.Y.Scale, rest.Y.Offset - lift))
	assign(stop, "Size", UDim2.new(restSize.X.Scale, restSize.X.Offset - narrow, restSize.Y.Scale, restSize.Y.Offset))
end

-- Подсказка въезжает снизу с пружиной, значок выскакивает (у предупреждения — ещё и качается).
local function animateHint(kind: string)
	local hint = ui.hint
	local rest = defaults.hintPosition
	hint.Position = rest + UDim2.fromScale(0, 0.05)
	UiFx.tween(hint, 0.42, { Position = rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UiFx.popIn(hint, { from = 0.7, time = 0.35 })
	UiFx.popIn(ui.hintSocket, { from = 0, time = 0.4, delay = 0.08, rotate = -25 })
	if kind == "warning" or kind == "danger" then
		task.delay(0.45, function()
			if hint.Visible then
				UiFx.wiggle(ui.hintSocket, 16, 3, 0.45)
			end
		end)
	end
end

-- Пока на месте подсказки доигрывает копия мини-игры (промах), подсказка ждёт (os.clock()).
local hintHeldUntil = 0

-- Подсказка о событии (eventHint) важнее постоянной подсказки по месту (contextHint).
-- Цвет «пилюли» — по виду: предупреждение — солнечная, опасность — ягодная, остальное — тёмная.
local function renderHint(force: boolean?)
	local hint = ui.hint
	local text: string? = nil
	local kind = "info"
	if eventHint then
		text, kind = eventHint.text, eventHint.kind
	elseif contextHint then
		text = contextHint
	end
	if not text or os.clock() < hintHeldUntil then
		hint.Visible = false
		return
	end
	local changed = force == true or not hint.Visible or hint.Text ~= text
	if not hint.Visible then
		layoutColumn()
	end
	hint.Text = text
	ui.hintLabel.Text = text
	ui.hintIcon.Text = HINT_ICONS[kind] or HINT_ICONS.info
	UiFx.setCandy(hint, HINT_TOKENS[kind] or "Night")
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

-- Убрать подсказку о событии сразу (поклёвка и мини-игра занимают её место в колонке).
local function clearEventHint()
	local thread = hintThread
	hintThread = nil
	if thread and thread ~= coroutine.running() and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
	if eventHint then
		eventHint = nil
		renderHint()
	end
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

local TweenService = game:GetService("TweenService")

-- Удочка в руке, леска не в воде, а до точки рыбалки своей базы далеко (тот же допуск, что у
-- сервера): кнопка «К ПИРСУ» не забрасывает. Без базы — «ЗАБРОСИТЬ» (сервер объяснит отказ).
local function isFar(): boolean
	if not rod or phase ~= "Idle" then
		return false
	end
	local root = rootPart()
	local spot = ownFishingSpot()
	return root ~= nil and spot ~= nil and not isNearSpot(root, spot)
end

local function currentLook(): Look
	if not rod then
		return TAKE_LOOK
	elseif phase == "Bite" and hookSent then
		return WAIT_LOOK -- подсечка отправлена, ждём мини-игру
	elseif phase == "Idle" and os.clock() < castReadyAt then
		return WAIT_LOOK -- сервер ещё не примет заброс (CastCooldown)
	elseif isFar() then
		return FAR_LOOK
	end
	return LOOKS[phase]
end

local BREATHE_PEAK, BREATHE_PERIOD = 1.04, 1.6 -- «дыхание» главной кнопки в покое
local WATER_DOTS = { "ЖДЁМ…", "ЖДЁМ.", "ЖДЁМ.." } -- бегущие точки ожидания (по 0.4 с)
local WATER_DOTS_STEP = 0.4
local BOBBER_BOB = 0.06 -- поплавок на кнопке качается на столько (доля кнопки) …
local BOBBER_PERIOD = 1.2 -- … за столько секунд туда-обратно; так же часто — круг по воде

-- Белые кольца от кнопки (ВЗЯТЬ, ЛОВИ!, такт поклёвки): тонкий чёткий контур, 1 → 1.3 —
-- читается на дереве, воде и небе и не дотягивается до кнопки прыжка.
local function whiteRings(interval: number): UiFx.Stop
	return UiFx.glowRing(ui.actionButton, {
		loop = true,
		color = WHITE,
		scale = 1.3,
		thickness = 5,
		time = 0.6,
		interval = interval,
	})
end

-- «Фон» вида кнопки: только таймеры и твины (без покадровых соединений).
local function startLookFx(look: Look)
	lookTrove:Clean()
	local button = ui.actionButton
	local icon = ui.actionIcon
	icon.Rotation = defaults.iconRotation
	if look == CAST_LOOK then
		-- Главная кнопка «дышит» и блестит; больше в покое на экране ничего не шевелится.
		lookTrove:Add(UiFx.shineLoop(button, { interval = UIConfig.Fx.ShineInterval }))
		-- Вдох-выдох — один твин туда-обратно за такт; нажатие (свой твин масштаба) его прерывает,
		-- а следующий такт начинается, только когда кнопка снова в покое.
		local scale = UiFx.scaleOf(button)
		local breathInfo = TweenInfo.new(BREATHE_PERIOD / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true)
		local breath: Tween? = nil
		every(lookTrove, BREATHE_PERIOD, function()
			if button.Visible and math.abs(scale.Scale - 1) < 0.01 then
				local created = TweenService:Create(scale, breathInfo, { Scale = BREATHE_PEAK })
				created:Play()
				breath = created
			end
		end, 0.8)
		lookTrove:Add(function()
			if breath and breath.PlaybackState == Enum.PlaybackState.Playing then
				breath:Cancel()
				scale.Scale = 1
			end
		end)
	elseif look == TAKE_LOOK then
		lookTrove:Add(UiFx.shineLoop(button, { interval = 2.4, delay = 0.6 }))
		lookTrove:Add(whiteRings(1.0))
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
	elseif look == WATER_LOOK then
		-- Поплавок качается на «воде» кнопки, от него расходятся круги, точки бегут.
		local bobber = ui.actionBobber
		local rest = defaults.bobberPosition
		bobber.Position = rest - UDim2.fromScale(0, BOBBER_BOB / 2)
		local bob = TweenService:Create(
			bobber,
			TweenInfo.new(BOBBER_PERIOD / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = rest + UDim2.fromScale(0, BOBBER_BOB / 2) }
		)
		bob:Play()
		lookTrove:Add(function()
			bob:Cancel()
			bobber.Position = rest
		end)
		lookTrove:Add(UiFx.glowRing(bobber, {
			loop = true,
			color = WHITE,
			scale = 2.1,
			thickness = 2.5,
			time = 1,
			interval = BOBBER_PERIOD,
		}))
		local step = 0
		every(lookTrove, WATER_DOTS_STEP, function()
			step = step % #WATER_DOTS + 1
			ui.actionCaption.Text = WATER_DOTS[step]
		end)
	elseif look == REEL_LOOK then
		lookTrove:Add(whiteRings(1.1))
	end
	-- BITE_LOOK: пульс и кольца в такт — в actionPulseTrove (enterBite), до подсечки.
	-- FAR_LOOK: спокойная серая кнопка (без блика и колец).
end

-- Перекрасить кнопку под вид; animate — кнопка выскакивает (смена состояния).
local function applyLook(look: Look, animate: boolean)
	local button = ui.actionButton
	UiFx.setCandy(button, look.Token)
	ui.actionIcon.Text = look.Icon
	-- «!» — знак текстом: белый → золотой с обводкой; эмодзи — как есть.
	ui.actionOutline.Enabled = look.Glyph == true
	ui.actionFill.Enabled = look.Glyph == true
	ui.actionBobber.Visible = look.Bobber == true
	ui.actionRing.Color = look.RingColor
	ui.actionRing.Transparency = look.Ring
	startLookFx(look)
	if animate then
		UiFx.popIn(button, { from = 0.8, time = 0.28 })
		UiFx.popIn(if look.Bobber then ui.actionBobber else ui.actionIcon, { from = 0.2, time = 0.34, delay = 0.04 })
	end
end

local function refreshButtons()
	local look = currentLook()
	local button = ui.actionButton
	local wasVisible = button.Visible
	local visible = rod ~= nil or offerTake
	button.Visible = visible
	ui.actionCaption.Text = look.Caption
	-- Клавиша действия (F / R2) — на «клавише» у плеча кнопки, когда действие ею доступно.
	ui.keyChip.Visible = look.Key and keyHint ~= ""
	ui.keyLabel.Text = keyHint
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
-- который ещё ни разу не брал удочку, — куда идти. Ушёл от точки / вернулся — кнопка
-- меняется между «ЗАБРОСИТЬ» и «К ПИРСУ».
local shownFar = false
local function refreshContextHint()
	local text: string? = nil
	local guideTo: BasePart? = nil
	local root = rootPart()
	local spot = ownFishingSpot()
	local near = root ~= nil and spot ~= nil and isNearSpot(root, spot)
	local take = rod == nil and phase == "Idle" and near and isAlive() and backpackRod() ~= nil
	local far = isFar()
	if take ~= offerTake or far ~= shownFar then
		offerTake = take
		shownFar = far
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

-- «К ПИРСУ» нажата: вместо заброса — показать дорогу (подсказка выскакивает заново, луч к
-- точке рыбалки на миг становится толще и ярче).
local function pointToSpot()
	showHint(HINT_FAR, "warning")
	UiFx.wiggle(ui.actionIcon, 18, 3, 0.45)
	UiFx.sound("tick", 0.35, 0.9)
	local current = guide
	if current and current.beam.Enabled then
		local beam = current.beam
		beam.Width0, beam.Width1 = 0.7, 2.2
		beam.Transparency = NumberSequence.new(0.2, 0)
		UiFx.tween(beam, 0.6, { Width0 = 0.3, Width1 = 0.8 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.6, function()
			if beam.Parent then
				beam.Transparency = NumberSequence.new(0.55, 0.15)
			end
		end)
	end
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

-- Поклёвка в одном такте: плашка и кнопка пульсируют вместе, кольцо от кнопки и край экрана —
-- на каждый такт, знаки «!» качаются по очереди (каждый — раз в два такта). После
-- BITE_HURRY окна такт ускоряется (пульс сильнее). Вспышки края экрана не чаще 3 раз в секунду.
local BITE_BEAT = 0.45
local BITE_FAST_BEAT = 0.3
local BITE_HURRY = 0.65
local BITE_EDGE = 0.2 -- толщина солнечных краёв экрана, доля высоты

local function enterBite(window: number)
	setPhase("Bite")
	hookSent = false
	clearEventHint() -- колонка внизу — для поклёвки
	layoutColumn()
	local alert = ui.biteAlert
	alert.Position = defaults.alertPosition
	alert.Visible = true

	-- «КЛЮЁТ!» влетает ударом (2.3 → 1 и лёгкая тряска — небольшая: плашка стоит у самой
	-- панели предметов): солнечная вспышка, камера на миг «приближается», свист и звон.
	local slam = UiFx.scaleOf(alert)
	slam.Scale = 2.3
	UiFx.tween(slam, 0.38, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	later(phaseTrove, 0.21, function()
		UiFx.shake(alert, 0.006, 0.22)
	end)
	UiFx.flash(ui.hud, Palette.Sun.Top, 0.22)
	UiFx.fovPunch(-4, 0.06, 0.25)
	UiFx.sound("swoosh", 0.4, 1.4)
	UiFx.sound("ping", 0.45, 1.8)
	-- Спокойные лучи (не закрывают «!» над головой в мире) и солнечные края экрана в такт.
	phaseTrove:Add(UiFx.rays(alert, {
		colors = { Palette.Sun.Top, WHITE, Palette.Gold.Top },
		count = 12,
		speed = 24,
		size = 1.6,
		transparency = 0.45,
		halo = false,
		breathe = false,
	}))
	-- Края экрана начинают светиться с первым тактом (после удара и вспышки — заливка на
	-- телефоне не складывается).
	local stopVignette: ((number?) -> ())? = nil
	later(phaseTrove, BITE_BEAT, function()
		stopVignette = UiFx.edgeVignette(
			ui.hud,
			{ Palette.Sun.Top, Palette.Sun.Bottom },
			0.55,
			BITE_BEAT,
			{ fadeIn = 0.15, size = BITE_EDGE }
		)
	end)
	phaseTrove:Add(function()
		if stopVignette then
			stopVignette()
		end
	end)

	-- Такт: после удара плашка и кнопка пульсируют вместе; к концу окна — быстрее и сильнее.
	local stopAlertPulse: UiFx.Stop? = nil
	phaseTrove:Add(function()
		if stopAlertPulse then
			stopAlertPulse()
		end
	end)
	local function pulseBoth(period: number, peak: number)
		actionPulseTrove:Clean()
		if stopAlertPulse then
			stopAlertPulse()
		end
		stopAlertPulse = UiFx.pulse(alert, peak, period)
		actionPulseTrove:Add(UiFx.pulse(ui.actionButton, peak + 0.04, period))
		actionPulseTrove:Add(whiteRings(BITE_BEAT))
	end
	later(phaseTrove, BITE_BEAT, function()
		if not hookSent then
			pulseBoth(BITE_BEAT, 1.06)
		end
	end)
	later(phaseTrove, math.max(window * BITE_HURRY, BITE_BEAT * 1.5), function()
		if not hookSent then
			pulseBoth(BITE_FAST_BEAT, 1.1)
		end
	end)
	for index, icon in ui.biteIcons do
		every(phaseTrove, BITE_BEAT * 2, function()
			UiFx.wiggle(icon, 16, 2, 0.36)
		end, BITE_BEAT * index)
	end

	-- Полоска времени тает (зелёная → жёлтая → красная).
	local timer = ui.biteTimer
	timer.Size = defaults.biteTimerSize
	local stopTimer = UiFx.timerBar(timer, math.max(window, 0.05), TIME_COLORS)
	phaseTrove:Add(function()
		stopTimer()
		timer.Size = defaults.biteTimerSize
		timer.BackgroundColor3 = defaults.biteTimerColor
	end)

	-- Кнопка зовёт с первого кадра: кольцо сразу (пульс — с первого такта).
	actionPulseTrove:Add(whiteRings(BITE_BEAT))
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

-- Мини-игра: предсказанные попадания, 🐟 на зоне, подсказка новичку, обводка редкости.
local NEEDLE_HOLD = 0.05 -- при попадании стрелка на миг «замирает» (только картинка)
local CUE_MINIGAMES = 2 -- первые столько мини-игр за игру 👆 показывает на кнопку
local RIDER_TILT = 12 -- 🐟 покачивается ±градусов …
local RIDER_SWING = 0.3 -- … раз в столько секунд
local PIPS_SHARE, PIPS_PAD = 0.3, 0.04 -- рамка кружков попаданий: доля ширины панели, зазор (доля рамки)
local TIME_BAR_LEFT, PANEL_EDGE = 0.105, 0.955 -- полоска времени начинается тут; кружки кончаются тут
local RARITY_RANK: { [string]: number } = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }
-- Мифический заголовок — радуга без самых тёмных (синего и фиолетового) цветов: на тёмной
-- панели они не читаются.
local MYTHIC_TITLE = { table.unpack(UIConfig.Rainbow, 1, 5) }
local AURA_EDGE = 0.16 -- толщина цветных краёв экрана в мини-игре, доля высоты

local needleHoldUntil = 0
local needleHoldAt = 0
local predictedHit: number? = nil -- номер попадания, уже отыгранного по предсказанию (до "Zone")
local minigamesShown = 0
local cueOn = false
local riderWiggle: Tween? = nil
local auraEdge = false -- края экрана уже светятся цветом редкости (идеальное — без второй виньетки)

local function refreshPips(mg: Minigame)
	for index, pip in ui.pips do
		local done = index <= mg.Hits
		pip.Visible = index <= mg.HitsNeeded
		pip.BackgroundColor3 = if done then COLORS.PipDone else defaults.pipColor
		local star = pip:FindFirstChild("Star")
		if star and star:IsA("TextLabel") then
			star.Text = if done then "⭐" else "★"
			star.TextTransparency = if done then 0 else 0.55
		end
	end
	-- Полоска времени тянется до кружков (их 1–5): без пустого места посередине.
	local frame = ui.pipsFrame.AbsoluteSize
	local count = math.clamp(mg.HitsNeeded, 1, #ui.pips)
	local base = defaults.timeBarSize
	if frame.X > 1 then
		local used = PIPS_SHARE * (count * frame.Y / frame.X + (count - 1) * PIPS_PAD)
		local width = math.clamp(PANEL_EDGE - used - 0.035 - TIME_BAR_LEFT, 0.2, base.X.Scale + PIPS_SHARE)
		ui.timeBar.Size = UDim2.new(width, 0, base.Y.Scale, base.Y.Offset)
	else
		ui.timeBar.Size = base
	end
end

-- Центр кружка попадания index из count видимых, в долях панели (кружки прижаты вправо).
local function pipPoint(index: number, count: number): Vector2
	local panel = ui.minigame.AbsoluteSize
	local frame = ui.pipsFrame.AbsoluteSize
	if panel.X < 1 or frame.X < 1 then
		return Vector2.new(PANEL_EDGE, 0.72)
	end
	local pip = frame.Y / panel.X -- кружок (квадрат по высоте рамки) в долях ширины панели
	local pad = PIPS_PAD * frame.X / panel.X
	local fromRight = count - index
	local x = PANEL_EDGE - (fromRight + 0.5) * pip - fromRight * pad
	return Vector2.new(x, 0.72)
end

-- Каждый кадр: стрелка по общей формуле, полоска оставшегося времени и 👆 новичку.
local function updateMinigameFrame()
	local mg = minigame
	if not mg then
		return
	end
	local now = os.clock()
	local elapsed = now - minigameStart
	local u = FishingRules.Needle(mg.U0, mg.Speed, elapsed)
	ui.needle.Position = UDim2.fromScale(if now < needleHoldUntil then needleHoldAt else u, defaults.needleY)
	local spent = math.clamp(elapsed / mg.Timeout, 0, 1)
	ui.timeFill.Size = UDim2.fromScale(1 - spent, 1)
	ui.timeFill.BackgroundColor3 = UiFx.sampleColors(UIConfig.Fishing.TimeBar, spent)
	if cueOn then
		ui.tapCue.Visible = predictedHit == nil and FishingRules.IsHit(u, mg.ZoneCenter, mg.ZoneWidth)
	end
end

-- Заголовок: белый сверху, цвет редкости снизу (мифическая — бегущая радуга).
local function styleTitle(rarityId: string)
	local style = UIConfig.Rarity[rarityId] or UIConfig.Rarity.Common
	local fill = ui.titleFill
	if style.Rainbow then
		fill.Color = UiFx.sequence(MYTHIC_TITLE)
		fill.Rotation = 0
		phaseTrove:Add(UiFx.rainbow(fill, { speed = 0.5, colors = MYTHIC_TITLE }))
	else
		fill.Color = ColorSequence.new(WHITE, style.Top)
		fill.Rotation = 90
	end
end

local function startRiderWiggle()
	local rider = ui.rider
	if riderWiggle then
		riderWiggle:Cancel()
	end
	rider.Rotation = -RIDER_TILT
	local wiggle = TweenService:Create(
		rider,
		TweenInfo.new(RIDER_SWING, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Rotation = RIDER_TILT }
	)
	wiggle:Play()
	riderWiggle = wiggle
end

local function stopRiderWiggle()
	local wiggle = riderWiggle
	riderWiggle = nil
	if wiggle then
		wiggle:Cancel()
	end
end

-- 🐟 на зоне: стоит на её верхнем крае (над зоной, под стрелкой) и покачивается; у легендарной
-- и мифической — светится кольцами.
local function showRider(mg: Minigame)
	local rider = ui.rider
	rider.Position = UDim2.fromScale(mg.ZoneCenter, defaults.riderY)
	rider.Visible = true
	UiFx.popIn(rider, { from = 0, time = 0.35, delay = 0.15 })
	startRiderWiggle()
	if (RARITY_RANK[mg.Rarity] or 1) >= 4 then
		local style = UIConfig.Rarity[mg.Rarity] or UIConfig.Rarity.Common
		phaseTrove:Add(UiFx.glowRing(rider, {
			loop = true,
			color = if style.Rainbow then WHITE else style.Top,
			scale = 1.9,
			thickness = 2.5,
			time = 0.7,
			interval = 0.8,
		}))
	end
	phaseTrove:Add(function()
		stopRiderWiggle()
		rider.Visible = false
		rider.Rotation = 0
		rider.Position = UDim2.fromScale(0.5, defaults.riderY)
	end)
end

-- Зона прыгнула: 🐟 перелетает за ней дугой с кувырком, в конце — всплеск 💦.
local function hopRider(to: number)
	local rider = ui.rider
	if not rider.Visible then
		return
	end
	stopRiderWiggle()
	local from = rider.Position.X.Scale
	local y = defaults.riderY
	local quad = Enum.EasingStyle.Quad
	UiFx.tween(rider, 0.1, { Position = UDim2.fromScale((from + to) / 2, y - 0.9) }, quad, Enum.EasingDirection.Out)
	UiFx.tween(rider, 0.2, { Rotation = rider.Rotation + 360 }, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
	later(phaseTrove, 0.1, function()
		UiFx.tween(rider, 0.1, { Position = UDim2.fromScale(to, y) }, quad, Enum.EasingDirection.In)
	end)
	later(phaseTrove, 0.2, function()
		startRiderWiggle()
		UiFx.bump(rider, 1.25, 0.25)
		UiFx.floatText(ui.track, "💦", {
			position = UDim2.fromScale(to, -0.45),
			size = UDim2.fromScale(0.1, 0.9),
			rise = 0.5,
			time = 0.45,
			z = 5,
		})
	end)
end

-- Эпическая и выше: обводка панели в цвет редкости (легендарная — с золотым бликом по кругу,
-- мифическая — вращающаяся радуга), лучи за панелью, края экрана «дышат» цветом редкости;
-- легендарная и мифическая — ещё «удар» заголовка со вспышкой и стук сердца.
local function minigameAura(mg: Minigame)
	local rank = RARITY_RANK[mg.Rarity] or 1
	if rank < 3 then
		return
	end
	local style = UIConfig.Rarity[mg.Rarity] or UIConfig.Rarity.Common
	local aura, fill = ui.aura, ui.auraFill
	aura.Enabled = true
	local loop: Tween? = nil
	if style.Rainbow then
		fill.Color = UiFx.sequence(UIConfig.Rainbow)
		fill.Rotation = 0
		loop = TweenService:Create(
			fill,
			TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1),
			{ Rotation = 360 }
		)
	elseif rank >= 4 then
		fill.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Palette.Gold.Bottom),
			ColorSequenceKeypoint.new(0.4, Palette.Gold.Top),
			ColorSequenceKeypoint.new(0.5, WHITE),
			ColorSequenceKeypoint.new(0.6, Palette.Gold.Top),
			ColorSequenceKeypoint.new(1, Palette.Gold.Bottom),
		})
		fill.Rotation = 0
		fill.Offset = Vector2.new(-1, 0)
		loop = TweenService:Create(
			fill,
			TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1),
			{ Offset = Vector2.new(1, 0) }
		)
	else
		fill.Color = ColorSequence.new(style.Top, style.Bottom)
		fill.Rotation = 90
	end
	if loop then
		loop:Play()
	end
	phaseTrove:Add(function()
		if loop then
			loop:Cancel()
		end
		aura.Enabled = false
		fill.Rotation = 0
		fill.Offset = Vector2.zero
	end)
	phaseTrove:Add(UiFx.rays(ui.minigame, {
		colors = style.Rays,
		count = 12,
		size = 1.9,
		transparency = 0.55,
		speed = 30,
		halo = false,
		breathe = false,
	}))
	-- Узкие полосы (AURA_EDGE экрана): виньетка живёт всю мини-игру — бережём заливку на телефоне
	-- (у легендарной и мифической — после вспышки входа, чтобы не сложились).
	local edge: Color3 | { Color3 } = if style.Rainbow then { UIConfig.Rainbow[1], UIConfig.Rainbow[7] } else style.Top
	local stopEdge: ((number?) -> ())? = nil
	auraEdge = true
	later(phaseTrove, if rank >= 4 then 0.35 else 0, function()
		stopEdge = UiFx.edgeVignette(ui.hud, edge, 0.85, 0.9, { pulseTo = 0.65, fadeIn = 0.5, size = AURA_EDGE })
	end)
	phaseTrove:Add(function()
		auraEdge = false
		if stopEdge then
			stopEdge()
		end
	end)
	if rank >= 4 then
		UiFx.slam(ui.title, 2.2, 0.35)
		UiFx.flash(ui.hud, style.Top, 0.3, 0.7)
		every(phaseTrove, 0.8, function()
			UiFx.sound("splash", 0.2, 0.5)
		end, 0.4)
	end
end

local function showMinigame(mg: Minigame)
	clearEventHint() -- колонка внизу — для мини-игры
	layoutColumn()
	minigamesShown += 1
	cueOn = minigamesShown <= CUE_MINIGAMES
	predictedHit = nil
	needleHoldUntil = 0
	local rarity = FishingRules.GetRarity(mg.Rarity)
	ui.title.Text = `{upper(if rarity then rarity.Name else "Неизвестная")} РЫБА!`
	styleTitle(mg.Rarity)
	refreshPips(mg)
	-- Зона по ширине с первого кадра такая, какой её проверяет сервер; «вырастает» по высоте.
	ui.zone.Position = UDim2.fromScale(mg.ZoneCenter, 0.5)
	ui.zone.Size = UDim2.fromScale(mg.ZoneWidth, 0)
	UiFx.tween(
		ui.zone,
		0.3,
		{ Size = UDim2.fromScale(mg.ZoneWidth, defaults.zoneHeight) },
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out,
		0.08
	)
	ui.zoneFlash.BackgroundTransparency = 1
	ui.minigame.Position = defaults.minigamePosition
	updateMinigameFrame()
	ui.minigame.Visible = true
	UiFx.popIn(ui.minigame, { from = 0.6, time = 0.3 })
	for index, pip in ui.pips do
		if pip.Visible then
			local star = pip:FindFirstChild("Star")
			if star and star:IsA("GuiObject") then
				UiFx.popIn(star, { from = 0, time = 0.3, delay = 0.1 + index * 0.06 })
			end
		end
	end
	phaseTrove:Connect(RunService.RenderStepped, updateMinigameFrame)

	-- Шлейф стрелки: две голубые тени ПОД зоной (ни зону не закрывают, ни за стрелки не сойдут).
	phaseTrove:Add(UiFx.trail(ui.needle, { count = 2, lag = 0.035, transparency = 0.75 }))
	for _, item in ui.track:GetChildren() do
		if item.Name == "FxGhost" and item:IsA("GuiObject") then
			item.ZIndex = 2
			item.BackgroundColor3 = Palette.Sky.Top
			item.Size = UDim2.fromScale(ui.needle.Size.X.Scale, 0.9)
		end
	end
	-- Свет под зоной «дышит» — только по высоте (по ширине зона не врёт).
	local glow = ui.zoneGlow
	local glowRest = defaults.glowSize
	glow.Size = glowRest
	local breathe = TweenService:Create(
		glow,
		TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Size = UDim2.new(glowRest.X.Scale, glowRest.X.Offset, glowRest.Y.Scale * 1.25, glowRest.Y.Offset) }
	)
	breathe:Play()
	phaseTrove:Add(function()
		breathe:Cancel()
		glow.Size = glowRest
	end)

	showRider(mg)
	-- Тач-экран: касание панели — тоже нажатие.
	ui.tapPad.Visible = UserInputService.TouchEnabled
	-- Новичку: 👆 «нажимает» кнопку, пока стрелка в зоне (видимость — каждый кадр).
	local cue = ui.tapCue
	if cueOn then
		cue.Position = defaults.tapCuePosition
		local bounce = TweenService:Create(
			cue,
			TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Position = defaults.tapCuePosition + UDim2.fromScale(0, 0.08) }
		)
		bounce:Play()
		phaseTrove:Add(function()
			bounce:Cancel()
			cue.Position = defaults.tapCuePosition
		end)
	end
	phaseTrove:Add(function()
		ui.tapPad.Visible = false
		cue.Visible = false
	end)
	minigameAura(mg)
end

-- Точка на полосе (доля 0..1) в долях панели мини-игры: центр по высоте полосы.
local function trackPoint(u: number): Vector2
	return Vector2.new(defaults.trackLeft + u * defaults.trackWidth, defaults.trackMidY)
end

-- Слово попадания над зоной: выскакивает 0 → 1.3 → 1 и поднимается; «ИДЕАЛЬНО!» — «удар»
-- 2 → 1 и белый блик по золотым буквам; «МЕГА!» — радуга вдоль букв.
local function hitWord(word: HitWord, x: number, perfect: boolean)
	local label = UiFx.floatText(ui.minigame, word.text, {
		position = UDim2.fromScale(math.clamp(x, 0.36, 0.64), -0.14),
		size = UDim2.fromScale(0.7, if perfect then 0.62 else 0.55),
		colors = word.colors,
		rise = 0.35,
		time = 0.85,
		rotate = if perfect then -4 else nil,
		z = 8,
	})
	local gradient = label:FindFirstChild("TextFill")
	local scale = label:FindFirstChildOfClass("UIScale")
	if word.rainbow and gradient and gradient:IsA("UIGradient") then
		gradient.Rotation = 0
	end
	if not scale then
		return
	end
	if perfect then
		scale.Scale = 2
		UiFx.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		if gradient and gradient:IsA("UIGradient") then
			gradient.Rotation = 20
			gradient.Offset = Vector2.new(-1, 0)
			UiFx.tween(
				gradient,
				0.5,
				{ Offset = Vector2.new(1, 0) },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.InOut,
				0.15
			)
		end
	else
		scale.Scale = 0
		UiFx.tween(scale, 0.12, { Scale = 1.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		task.delay(0.12, function()
			if scale.Parent then
				UiFx.tween(scale, 0.13, { Scale = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
		end)
	end
end

-- «ИДЕАЛЬНО!»: 8 ⭐ разлетаются от зоны, панель на миг вспыхивает белым, края экрана —
-- золотом, камера на миг «приближается».
local function perfectBurst(origin: Vector2)
	local panel = ui.minigame
	local size = panel.AbsoluteSize
	local aspect = if size.X > 1 then size.Y / size.X else 0.35
	for index = 1, 8 do
		local star = Instance.new("TextLabel")
		star.Name = "FxStar"
		star.BackgroundTransparency = 1
		star.Text = "⭐"
		star.TextScaled = true
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.SizeConstraint = Enum.SizeConstraint.RelativeYY
		local s = 0.12 + 0.025 * (index % 3)
		star.Size = UDim2.fromScale(s, s)
		star.Position = UDim2.fromScale(origin.X, origin.Y)
		star.Rotation = (index * 37) % 50 - 25
		star.ZIndex = 8
		star.Parent = panel
		local angle = math.rad(index * 45 + 20)
		local reach = 0.62
		local target = UDim2.fromScale(origin.X + math.cos(angle) * reach * aspect, origin.Y + math.sin(angle) * reach)
		UiFx.tween(
			star,
			0.55,
			{ Position = target, Rotation = star.Rotation + 140 },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		)
		UiFx.tween(star, 0.25, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0.32)
		task.delay(0.6, function()
			star:Destroy()
		end)
	end
	local flash = Instance.new("Frame")
	flash.Name = "FxPanelFlash"
	flash.BackgroundColor3 = WHITE
	flash.BackgroundTransparency = 0.35
	flash.BorderSizePixel = 0
	flash.Size = UDim2.fromScale(1, 0.95)
	flash.ZIndex = 7
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = flash
	flash.Parent = panel
	UiFx.tween(flash, 0.12, { BackgroundTransparency = 1 })
	task.delay(0.14, function()
		flash:Destroy()
	end)
	if not auraEdge then
		UiFx.edgeVignette(ui.hud, Palette.Gold.Top, 0.8, nil, { fadeIn = 0, hold = 0, size = AURA_EDGE })
	end
	UiFx.fovPunch(-3, 0.05, 0.15)
end

-- Удар попадания (сразу по нажатию — сервер судит по тому же t): стрелка на миг замирает и
-- вспыхивает золотом, панель вздрагивает, зона вспыхивает, крупные искры над панелью, слово
-- (от попадания к попаданию громче), звук всё выше, кнопка подпрыгивает.
local function punchHit(mg: Minigame, index: number, perfect: boolean, tapU: number, zoneCenter: number)
	local word = if perfect
		then HIT_PERFECT
		elseif index >= 3 then HIT_MEGA
		elseif index == 2 then HIT_NEXT
		else HIT_FIRST
	local origin = trackPoint(zoneCenter)
	needleHoldUntil = os.clock() + NEEDLE_HOLD
	needleHoldAt = tapU
	ui.needle.BackgroundColor3 = Palette.Gold.Top
	UiFx.tween(ui.needle, 0.15, { BackgroundColor3 = WHITE })
	UiFx.bump(ui.minigame, 1.06, 0.18)
	if index == 2 and not perfect then
		UiFx.shake(ui.minigame, 3 / math.max(ui.hud.AbsoluteSize.X, 1), 0.2) -- ±3 px
	end
	ui.zoneFlash.BackgroundTransparency = 0.2
	UiFx.tween(ui.zoneFlash, 0.2, { BackgroundTransparency = 1 })
	UiFx.glowRing(ui.zone, {
		color = if perfect then Palette.Gold.Top else WHITE,
		scale = if perfect then 1.8 else 1.5,
		thickness = 3,
		time = 0.45,
	})
	phaseTrove:Add(UiFx.burst(ui.minigame, {
		origin = origin,
		count = if perfect then 24 else 18,
		colors = if perfect
			then { WHITE, Palette.Gold.Top, Palette.Sun.Top, Palette.Berry.Top }
			else { WHITE, Palette.Leaf.Top, Palette.Gold.Top },
		power = if perfect then 1.7 else 1.4,
		size = 2.4,
		z = 8,
	}))
	hitWord(word, origin.X, perfect)
	UiFx.sound("pop", if perfect then 0.6 else 0.5, if perfect then 1.25 else 1 + 0.15 * index)
	UiFx.bump(ui.actionButton, 1.15, 0.3)
	if perfect then
		perfectBurst(origin)
	end
end

-- Ответ сервера на попадание ("Zone"): зона на новом месте «вырастает» по высоте, 🐟 прыгает
-- за ней, ⭐ «печатается» в кружке попадания (от 2 до 1, с искрами). Если удар не был
-- предсказан (нажатие не отсюда / зона уже ждала ответа) — он играется сейчас.
local function celebrateHit(mg: Minigame, oldCenter: number, predicted: boolean)
	if not predicted then
		local perfect = tapNeedle ~= nil
			and tapZone ~= nil
			and math.abs(tapNeedle - tapZone) <= mg.ZoneWidth * PERFECT_SHARE
		punchHit(mg, mg.Hits, perfect, tapNeedle or oldCenter, oldCenter)
	end
	ui.zone.Size = UDim2.fromScale(mg.ZoneWidth, defaults.zoneHeight * 0.3)
	UiFx.tween(
		ui.zone,
		0.3,
		{ Size = UDim2.fromScale(mg.ZoneWidth, defaults.zoneHeight) },
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)
	UiFx.glowRing(ui.zone, { color = Palette.Leaf.Top, scale = 1.4, thickness = 3, time = 0.4 })
	hopRider(mg.ZoneCenter)
	local pip = ui.pips[mg.Hits]
	local star = pip and pip:FindFirstChild("Star")
	if star and star:IsA("GuiObject") then
		local scale = UiFx.scaleOf(star)
		scale.Scale = 2
		UiFx.tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		UiFx.wiggle(star, 20, 2, 0.35)
		phaseTrove:Add(UiFx.burst(ui.minigame, {
			origin = pipPoint(mg.Hits, math.clamp(mg.HitsNeeded, 1, #ui.pips)),
			count = 6,
			colors = { WHITE, Palette.Gold.Top, Palette.Leaf.Top },
			power = 0.45,
			time = 0.45,
			z = 8,
		}))
	end
	UiFx.sound("tick", 0.3, 1.5)
end

-- Промах / время вышло: мини-игра закрывается сразу, а её копия ещё полсекунды краснеет,
-- качается и показывает надпись (🐟 уплывает за край), потом уходит вверх, сжимается и тает.
local function missGhost(text: string)
	local source = ui.minigame
	if not source.Visible then
		return
	end
	local ghost = source:Clone()
	ghost.Name = "FxMinigameMiss"
	ghost.Active = false
	-- Копия не ловит касания и не тащит за собой эффекты живой панели (слова, искры, лучи).
	local strip: { Instance } = {}
	for _, item in ghost:GetDescendants() do
		local name = item.Name
		if name == "TapPad" or (string.sub(name, 1, 2) == "Fx" and name ~= "FxScale" and name ~= "FxGhost") then
			table.insert(strip, item)
		end
	end
	for _, item in strip do
		if item.Parent then
			item:Destroy()
		end
	end
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
		local rider = track:FindFirstChild("Rider")
		if rider and rider:IsA("TextLabel") and rider.Visible then
			local quad, inDir = Enum.EasingStyle.Quad, Enum.EasingDirection.In
			UiFx.tween(
				rider,
				0.3,
				{ Position = UDim2.fromScale(1.12, rider.Position.Y.Scale), Rotation = 30 },
				quad,
				inDir
			)
			UiFx.tween(rider, 0.3, { TextTransparency = 1 }, quad, inDir)
		end
	end
	UiFx.wiggle(ghost, 4, 3, 0.4)
	UiFx.floatText(ghost, text, {
		position = UDim2.fromScale(0.5, -0.14),
		size = UDim2.fromScale(0.62, 0.5),
		colors = { Palette.Berry.Top, Palette.Berry.Bottom },
		rise = 0.2,
		time = MISS_HOLD + 0.15,
		rotate = -6,
		z = 8,
	})
	UiFx.sound("tick", 0.4)
	UiFx.sound("pop", 0.35, 0.6)
	task.delay(MISS_HOLD, function()
		if ghost.Parent == nil then
			return
		end
		local quad, inDir = Enum.EasingStyle.Quad, Enum.EasingDirection.In
		UiFx.tween(ghost, 0.25, { Position = ghost.Position - UDim2.fromScale(0, 0.05) }, quad, inDir)
		UiFx.tween(UiFx.scaleOf(ghost), 0.25, { Scale = 0.6 }, quad, inDir)
		UiFx.fadeOut(ghost, 0.25)
		task.delay(0.27, function()
			ghost:Destroy()
		end)
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
		local u = FishingRules.Needle(mg.U0, mg.Speed, now - minigameStart)
		tapNeedle = u
		tapZone = mg.ZoneCenter
		-- Попадание видно сразу: сервер судит по этому же t. Не предсказываем победное (это
		-- начало карточки улова — onCaught) и пока ждём новую зону (сервер не засчитает старую);
		-- промах решает сервер ("Lost" → копия мини-игры краснеет, даже после удара).
		if
			predictedHit == nil
			and mg.Hits + 1 < mg.HitsNeeded
			and FishingRules.IsHit(u, mg.ZoneCenter, mg.ZoneWidth)
		then
			predictedHit = mg.Hits + 1
			punchHit(mg, mg.Hits + 1, math.abs(u - mg.ZoneCenter) <= mg.ZoneWidth * PERFECT_SHARE, u, mg.ZoneCenter)
		end
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
		if isFar() then
			pointToSpot() -- «К ПИРСУ»: сервер всё равно откажет — показываем дорогу
			return
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

--[[
	Ожидание поклёвки «живое»: 1–2 раза за ожидание рыба «пробует» наживку (только на этом
	клиенте, через NIBBLE_FROM..NIBBLE_TO с после заброса — поклёвка не раньше BiteDelay.Min):
	кнопка вздрагивает и качается, над ней всплывает «?», поплавок в мире притапливается
	(FishingFxController.Nibble). Нажатия в это время по-прежнему ничего не отправляют.
]]
local NIBBLE_FROM, NIBBLE_TO = 0.8, 1.9
local nibbleRandom = Random.new()
local fishingFx: any = nil -- FishingFxController (берётся при первой «примерке»), false — нет

local function nibbleWorld()
	if fishingFx == nil then
		local module = script.Parent and script.Parent:FindFirstChild("FishingFxController")
		local ok, controller = pcall(function(): any
			return if module and module:IsA("ModuleScript") then require(module) :: any else nil
		end)
		fishingFx = if ok and controller then controller else false
	end
	if fishingFx and type(fishingFx.Nibble) == "function" then
		pcall(fishingFx.Nibble)
	end
end

local function nibble()
	local button = ui.actionButton
	if phase ~= "Waiting" or not button.Visible then
		return
	end
	-- Кнопка вздрагивает, поплавок на ней качается (качается не вся кнопка: справа кнопка прыжка).
	UiFx.bump(button, 0.94, 0.3)
	UiFx.wiggle(ui.actionBobber, 14, 2, 0.35)
	-- «?» — над левым плечом кнопки: справа кнопка прыжка.
	UiFx.floatText(button, "?", {
		position = UDim2.fromScale(0.22, 0.1),
		size = UDim2.fromScale(0.42, 0.42),
		rise = 0.14,
		time = 0.4,
		rotate = -12,
		z = 12,
	})
	UiFx.sound("tick", 0.25, 1.6)
	nibbleWorld()
end

local function onWaiting(_data: { [string]: any })
	hookSent = false
	setPhase("Waiting")
	local first = nibbleRandom:NextNumber(NIBBLE_FROM, NIBBLE_TO - 0.5)
	later(phaseTrove, first, nibble)
	if nibbleRandom:NextNumber() < 0.5 then
		later(phaseTrove, math.min(first + nibbleRandom:NextNumber(0.35, 0.6), NIBBLE_TO), nibble)
	end
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
	local predicted = predictedHit == mg.Hits -- удар уже сыгран по нажатию
	predictedHit = nil
	refreshPips(mg)
	-- Зона прыгает сразу (без скольжения): где она нарисована, там её и проверяет сервер.
	ui.zone.Position = UDim2.fromScale(mg.ZoneCenter, 0.5)
	celebrateHit(mg, oldCenter, predicted)
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
	local ghost = phase == "Reeling" and ui.minigame.Visible
	if ghost then
		missGhost(if reason == "timeout" then "ВРЕМЯ!" else "МИМО!")
	end
	endSessionByServer()
	local text = if typeof(data.Text) == "string" and data.Text ~= "" then data.Text else LOST_TEXT[reason]
	if ghost then
		-- Подсказка — когда копия мини-игры уходит (они стоят в одной колонке и не спорят).
		hintHeldUntil = os.clock() + MISS_HOLD - 0.02
		ui.hint.Visible = false
		later(phaseTrove, MISS_HOLD, function()
			showHint(text or "Рыба ушла", "warning")
		end)
	else
		showHint(text or "Рыба ушла", "warning")
	end
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
		hintIcon = child(child(hint, "IconSocket"), "Icon"),
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
		-- UI v2, игра:
		actionArea = area,
		actionOutline = child(child(action, "Icon"), "Outline"),
		actionFill = child(child(action, "Icon"), "TextFill"),
		actionBobber = child(action, "Bobber"),
		keyChip = child(action, "KeyChip"),
		keyLabel = child(child(action, "KeyChip"), "Key"),
		tapCue = child(action, "TapCue"),
		stopCaption = child(child(area, "StopButton"), "Caption"),
		aura = child(mini, "AuraStroke"),
		auraFill = child(child(mini, "AuraStroke"), "AuraFill"),
		rider = child(track, "Rider"),
		timeBar = child(mini, "TimeBar"),
		pipsFrame = pipsFolder,
		tapPad = child(mini, "TapPad"),
		hintSocket = child(hint, "IconSocket"),
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
		-- UI v2, игра:
		alertPosition = ui.biteAlert.Position,
		hintSize = ui.hint.Size,
		riderY = ui.rider.Position.Y.Scale,
		glowSize = ui.zoneGlow.Size,
		timeBarSize = ui.timeBar.Size,
		bobberPosition = ui.actionBobber.Position,
		tapCuePosition = ui.tapCue.Position,
		stopPosition = ui.stopButton.Position,
		stopSize = ui.stopButton.Size,
		minigameSize = ui.minigame.Size,
	}
end

-- Клавиша действия на «клавише» у кнопки: есть клавиатура — F, геймпад — R2 (на телефоне — нет).
local function detectKeyHint(): string
	if UserInputService.KeyboardEnabled then
		return "F"
	elseif UserInputService.GamepadEnabled then
		return "R2"
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
	ui.tapPad.Visible = false
	ui.tapCue.Visible = false
	ui.actionBobber.Visible = false
	ui.keyChip.Visible = false

	-- Центральная колонка — между джойстиком и кнопкой действия (и при смене размера экрана).
	layoutColumn()
	hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if hud.AbsoluteSize ~= laidOutFor then
			layoutColumn()
		end
	end)

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
	-- Тач-экран: касание панели мини-игры — то же, что касание «ЛОВИ!» (кнопка отзывается).
	ui.tapPad.MouseButton1Down:Connect(function()
		if phase == "Reeling" then
			doAction(false)
		end
	end)
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
