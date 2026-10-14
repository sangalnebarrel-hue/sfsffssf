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
	  • Улов (UI v2, порядок — в разделе «Улов» ниже): сначала мир, потом карточка. На
	    "Caught" копия мини-игры (FxMinigameWin) «побеждает» — ⭐, золотая зона, «ПОЙМАНА!» — и
	    уходит; кнопка «замирает» (тусклое «ЖДЁМ…»), подсказки нет; у эпической и выше по краям
	    экрана нарастает виньетка, у легендарной и мифической бьётся «сердце». Рыба
	    выпрыгивает и садится над головой (FishingFxController.OwnFishLanded): вспышка,
	    тряска и «толчок» камеры, конфетти из точки над головой, у эпической и выше — огромное
	    слово редкости (TitleSlam, у легендарной и мифической — буквами волной). Через миг
	    (по редкости) карточка (CatchCard) рождается в точке рыбы и встаёт на место: на
	    телефоне — широкая «трофейная» (рыба слева, имя и цены справа), на планшете и
	    компьютере — квадратная. Вокруг — затемнение (у обычной нет; на телефоне — полосы
	    сверху и снизу, как в кино) и лучи цветов редкости. Дальше доли: редкость (слово
	    влетает в баннер), имя, «НОВИНКА!» (вид пойман впервые за игру), вес и цена, цена
	    набегает, у мутации — штамп на углу рыбы, «×N» у цены, пересчёт и цветная обводка
	    карточки; последней — «Тапни, чтобы закрыть», и всё успокаивается. Тап (или действие)
	    раньше последней доли показывает всё сразу, потом — закрывает; сама карточка
	    закрывается через UIConfig.CatchCardTime[редкость]. Уходя, сжимается к счётчику, 🐟 со
	    ✨ летит в него. Счётчик улова (HUD.Status.CatchCounter) ведёт HudController: от
	    "Caught" до прилёта 🐟 у HUD стоит атрибут CounterHold (прошлое число), плашки
	    статуса под карточкой гаснут.
	  • Подсказка (Hint, «пилюля» в цвет вида — тёмная 💡 / солнечная ⚠️ / ягодная 🚨, значок в
	    белом кружке, въезжает снизу с пружиной; до двух строк): почему заброс не принят, почему
	    рыба ушла, куда идти. Тексты причин — общие с сервером (FishingConfig.Texts). Если игрок с
	    удочкой далеко от точки рыбалки своей базы — к ней тянется дорожка-луч (Beam, только у
	    него). Подсказка, поклёвка и мини-игра — одна колонка внизу по центру (между джойстиком
	    и кнопкой действия; на узком экране колонка сдвигается) и не показываются вместе.

	Уборка: всё, что живёт с персонажем, — в characterTrove; пока удочка в руке — в rodTrove;
	анимации текущего состояния — в phaseTrove (кадровые эффекты — шлейф, искры, радуга,
	полоска поклёвки — останавливаются вместе с состоянием); «фон» вида кнопки — в lookTrove;
	от "Caught" до карточки (ожидание приземления, слово редкости) — в catchTrove; карточка
	улова — в cardTrove, её лучи — в raysTrove; конфетти, дождь 💰 и полёт 🐟, которые
	доигрывают после карточки, — в celebrationTrove. В покое (ничего не происходит) — ни одного
	покадрового соединения: только таймеры и твины.
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
local CARD_FOV = 40 -- камера рыбы на квадратной карточке (широкая — CARD_FOV_WIDE)
local CARD_INPUT_LOCK = 0.35 -- столько секунд после появления карточка не слушает тапы
local PERFECT_SHARE = 0.25 -- «ИДЕАЛЬНО!»: стрелка не дальше этой доли ширины зоны от её центра
local MISS_HOLD = 0.55 -- столько «доигрывает» копия мини-игры после промаха, с
local DIM_TIME = 0.25 -- затемнение за карточкой появляется / уходит, с

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

-- Улов на экране (FUI-09): от "Caught" до прилёта 🐟 в счётчик кнопка «замирает» — тусклая,
-- без песочных часов, колец и «выскоков» (нажатие пропускает или закрывает карточку).
local CATCH_LOOK: Look = {
	Name = "Catch",
	Caption = "ЖДЁМ…",
	Icon = "⏳",
	Token = "Slate",
	Key = false,
	Ring = 1,
	RingColor = WHITE,
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

	-- Улов, UI v2 (FUI-01…12): корень Fishing, плашки статуса (гаснут под карточкой), подсказка
	-- «закрыть», рамка мутации, «×N» у цены, огромное слово редкости (TitleSlam).
	fishing: Frame,
	status: Frame,
	tapHint: TextLabel,
	cardOutline: UIStroke,
	priceMult: TextLabel,
	titleSlam: Frame,
	titleLabel: TextLabel,
	titleSlamFill: UIGradient,
	titleLetters: Frame,
	dimBands: { Frame },
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
local catchScreen = false -- улов на экране: от "Caught" до прилёта 🐟 в счётчик (FUI-09)
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
	local look = if catchScreen then CATCH_LOOK else currentLook()
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
		applyLook(look, visible and wasVisible and not first and look ~= CATCH_LOOK)
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
	if not catchScreen then
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
-- Улов: победа в мини-игре, прыжок рыбы, карточка (UI v2: FUI-01…04, 07, 09, 10, 12, 18)
--------------------------------------------------------------------------------

--[[
	Порядок (c — момент, когда карточка открылась):
	  "Caught"     панель мини-игры «побеждает» (FxMinigameWin: ⭐, золотая зона, искры,
	               «ПОЙМАНА!») и уходит; кнопка «замирает» (CATCH_LOOK), подсказки нет, счётчик
	               держит прошлое число (атрибут HUD CounterHold); у эпической и выше по краям
	               экрана растёт виньетка цвета редкости, у легендарной и мифической — «сердце».
	  приземление  рыба долетела до места над головой (FishingFxController.OwnFishLanded; нет
	               сигнала — через LeapTime + 0.3 с): вспышка, тряска, «толчок» камеры, конфетти
	               из точки над головой, у эпической и выше — огромное слово редкости.
	  + Hold       карточка рождается в точке рыбы и встаёт на место; затемнение и лучи.
	  c+0.20 редкость (баннер / слово влетает в баннер), c+0.50 имя, c+0.65 «НОВИНКА!»,
	  c+0.85 вес и цена, c+0.95 цена набегает, потом мутация (штамп, «×N», пересчёт),
	  последняя доля — «Тапни, чтобы закрыть», лучи и рыба успокаиваются.
	Тап по карточке (или действие) до последней доли — сразу всё показать, после — закрыть.
	Закрытие: карточка сжимается к счётчику, 🐟 со ✨ летит в него, счётчик +1 (CounterHold
	снят), кнопка «оживает» видом «ЗАБРОСИТЬ».
]]

local TweenService = game:GetService("TweenService")

-- Насколько «громко» встречают рыбу: чем реже, тем больше всего (FUI-03).
type Reveal = {
	Dim: number, -- прозрачность затемнения (1 — без затемнения)
	Rays: number, -- лучей
	Speed: number, -- их вращение, °/с
	Size: number, -- диаметр лучей в высотах карточки
	MaxPx: number, -- … но не больше стольких пикселей на тач-экране (заливка на телефоне)
	Alpha: number, -- прозрачность лучей
	Extra: boolean, -- второе кольцо лучей (вращается навстречу)
	Confetti: number, -- конфетти при приземлении
	Confetti2: number, -- второй залп (легендарная — при цене, мифическая — через 0.6 с)
	Sparkles: number, -- звёздочек вокруг рыбы в секунду
	Count: number, -- сколько секунд набегает цена
	Hold: number, -- от приземления до карточки, с
	Scale: number, -- размер карточки (обычная рыба — поменьше)
	Tension: boolean, -- виньетка по краям во время прыжка
	Heartbeat: boolean, -- «сердце» во время прыжка
	Title: boolean, -- огромное слово редкости
	Letters: boolean, -- … по буквам, волной
	Flash: Color3?, -- вспышка при приземлении
	FlashFrom: number,
	Shake: boolean, -- лёгкая тряска камеры при приземлении
	Fov: number, -- «толчок» поля зрения при приземлении, °
	Trail: number, -- ✨ за летящей в счётчик 🐟
}
local REVEAL: { [string]: Reveal } = {
	Common = {
		Dim = 1,
		Rays = 8,
		Speed = 12,
		Size = 1.7,
		MaxPx = 400,
		Alpha = 0.6,
		Extra = false,
		Confetti = 0,
		Confetti2 = 0,
		Sparkles = 1.5,
		Count = 0.5,
		Hold = 0.1,
		Scale = 0.85,
		Tension = false,
		Heartbeat = false,
		Title = false,
		Letters = false,
		Flash = nil,
		FlashFrom = 1,
		Shake = false,
		Fov = 0,
		Trail = 4,
	},
	Rare = {
		Dim = 0.6,
		Rays = 10,
		Speed = 16,
		Size = 1.95,
		MaxPx = 430,
		Alpha = 0.42,
		Extra = false,
		Confetti = 12,
		Confetti2 = 0,
		Sparkles = 1.5,
		Count = 0.6,
		Hold = 0.15,
		Scale = 1,
		Tension = false,
		Heartbeat = false,
		Title = false,
		Letters = false,
		Flash = nil,
		FlashFrom = 1,
		Shake = false,
		Fov = 0,
		Trail = 5,
	},
	Epic = {
		Dim = 0.45,
		Rays = 12,
		Speed = 20,
		Size = 2.15,
		MaxPx = 450,
		Alpha = 0.32,
		Extra = false,
		Confetti = 20,
		Confetti2 = 0,
		Sparkles = 2,
		Count = 0.7,
		Hold = 0.25,
		Scale = 1,
		Tension = true,
		Heartbeat = false,
		Title = true,
		Letters = false,
		Flash = nil,
		FlashFrom = 1,
		Shake = false,
		Fov = -3,
		Trail = 6,
	},
	Legendary = {
		Dim = 0.35,
		Rays = 14,
		Speed = 24,
		Size = 2.35,
		MaxPx = 470,
		Alpha = 0.3,
		Extra = true,
		Confetti = 26,
		Confetti2 = 12,
		Sparkles = 2,
		Count = 0.85,
		Hold = 0.4,
		Scale = 1,
		Tension = true,
		Heartbeat = true,
		Title = true,
		Letters = true,
		Flash = Palette.Gold.Top,
		FlashFrom = 0.15,
		Shake = true,
		Fov = -6,
		Trail = 7,
	},
	Mythic = {
		Dim = 0.25,
		Rays = 16,
		Speed = 28,
		Size = 2.55,
		MaxPx = 475,
		Alpha = 0.28,
		Extra = true,
		Confetti = 20,
		Confetti2 = 20,
		Sparkles = 2,
		Count = 1,
		Hold = 0.55,
		Scale = 1,
		Tension = true,
		Heartbeat = true,
		Title = true,
		Letters = true,
		Flash = WHITE,
		FlashFrom = 0.12,
		Shake = true,
		Fov = -8,
		Trail = 8,
	},
}

local CATCH_FALLBACK = FishingConfig.LeapTime + 0.3 -- сигнала приземления нет — открываем сами
local LANDING_MEMORY = 1.5 -- приземление пришло раньше "Caught" (без прыжка) — помним его, с
local CATCH_FAILSAFE = 20 -- улов «завис» (ошибка) — через столько секунд всё равно отпускаем
local STATUS_FADE = 0.2 -- плашка базы и счётчик гаснут / возвращаются, с
local BUTTON_FADE = 0.3 -- насколько прозрачнее «замёрзшая» кнопка действия
local WIN_TEXT = "ПОЙМАНА!" -- рыба поймана (про рыбу, а не про игрока)

-- Огромное слово редкости (эпическая и выше).
local TITLE_TEXT: { [string]: string } = {
	Epic = "ЭПИЧЕСКАЯ!",
	Legendary = "ЛЕГЕНДАРНАЯ!",
	Mythic = "МИФИЧЕСКАЯ!",
}
-- Ширина буквы (с запасом) в долях высоты строки: широкие, узкие, «!», остальные.
local WIDE_LETTERS = { ["Ж"] = true, ["Ш"] = true, ["Щ"] = true, ["Ы"] = true, ["Ю"] = true, ["М"] = true }
local NARROW_LETTERS = { ["Г"] = true, ["Е"] = true, ["З"] = true, ["С"] = true, ["Э"] = true, ["Р"] = true }

-- Карточка: широкая (телефоны) — на экране ниже WIDE_BELOW пикселей.
local WIDE_BELOW = 500
local CARD_ASPECT = 1.55 -- широкая карточка: ширина / высота
local CARD_TOP_GAP = 12 -- от верха HUD, px
local CARD_BOTTOM_CLEAR = 90 -- от низа HUD (хотбар Roblox — 65 px, зазор и рамка мутации), px
local CARD_SIDE_GAP = 16 -- до кнопки действия и края экрана, px
local THUMBSTICK_CLEAR = 111 -- джойстик Roblox на телефоне (до 95 px слева) + зазор, px
local THUMBSTICK_CLEAR_BIG = 196 -- … на планшете (до 180 px слева)
local CARD_FOV_WIDE = 32 -- камера рыбы на широкой карточке (уже — меньше искажений)
local CARD_YAW = math.rad(-25) -- рыба вполоборота: нос (+X) чуть к камере
local CARD_SWING = math.rad(30) -- … и покачивается ±30°, ребром не встаёт
local CARD_SWING_PERIOD = 3.2
local CARD_BOB = 0.03 -- лёгкое «дыхание» вверх-вниз (доля высоты рыбы)
local CARD_BOB_PERIOD = 1.6

-- Где что на широкой карточке (доли карточки): рыба слева, справа столбик — имя, вес, цена,
-- подсказка; баннер во всю ширину сверху, «НОВИНКА!» и мутация — штампы на углах рыбы.
type Place = {
	Position: UDim2,
	Size: UDim2,
	AnchorPoint: Vector2,
	Rotation: number,
	SizeConstraint: Enum.SizeConstraint,
}
local CARD_WIDE: { [string]: { [string]: any } } = {
	Banner = { Position = UDim2.fromScale(0.5, 0.025), Size = UDim2.fromScale(1.05, 0.2) },
	FishGlow = { Position = UDim2.fromScale(0.25, 0.6), Size = UDim2.fromScale(0.68, 0.68) },
	Viewport = { Position = UDim2.fromScale(0.25, 0.6), Size = UDim2.fromScale(0.46, 0.72) },
	NewStamp = { Position = UDim2.fromScale(0.14, 0.3), Size = UDim2.fromScale(0.25, 0.11) },
	MutationLabel = { Position = UDim2.fromScale(0.25, 0.9), Size = UDim2.fromScale(0.42, 0.12), Rotation = -4 },
	NameLabel = { Position = UDim2.fromScale(0.73, 0.25), Size = UDim2.fromScale(0.45, 0.2) },
	InfoLabel = { Position = UDim2.fromScale(0.73, 0.48), Size = UDim2.fromScale(0.42, 0.33) },
	["InfoLabel.Weight"] = {
		AnchorPoint = Vector2.new(0, 0),
		Position = UDim2.fromScale(0.08, 0),
		Size = UDim2.fromScale(0.92, 0.42),
	},
	["InfoLabel.Price"] = {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0.08, 1),
		Size = UDim2.fromScale(0.92, 0.48),
	},
	TapHint = { Position = UDim2.fromScale(0.73, 0.955), Size = UDim2.fromScale(0.44, 0.09) },
}

-- Карточка, её лучи и заготовка «как в сборщике» (квадратная): возвращаются при смене экрана.
local cardDefaults: { [Instance]: Place }? = nil
local cardBox: { center: Vector2, size: Vector2, wide: boolean }? = nil

local catchTrove = Trove.new() -- от "Caught" до карточки: ожидание приземления, слово редкости
local raysTrove = Trove.new() -- лучи за карточкой (на закрытии сжимаются, потом удаляются)
local catchSerial = 0 -- номер улова (новый улов отменяет хвосты прошлого)
local heldSerial = 0 -- чей CounterHold сейчас стоит
local landingWaiter: ((Vector3?) -> ())? = nil -- ждёт OwnFishLanded
local lastLanding: { at: number, position: Vector3 }? = nil -- приземление до "Caught"
local cardSettled = true -- все доли показаны: тап закрывает
local cardReveal: Reveal = REVEAL.Common -- «громкость» открытой карточки
local cardBeats: { { at: number, run: (instant: boolean) -> (), done: boolean } } = {}
local skipHooks: { () -> () } = {} -- что ещё довести до конца при пропуске (слово → баннер)
local stopPriceCount: (() -> ())? = nil
local faded: { [Instance]: { [string]: number } } = {} -- погашенное (плашки статуса, кнопка)

-- Буква «по ширине» для огромного слова.
local function letterWidth(ch: string): number
	if ch == "!" then
		return 0.34
	elseif WIDE_LETTERS[ch] then
		return 0.8
	elseif NARROW_LETTERS[ch] then
		return 0.56
	end
	return 0.64
end

-- Буквы слова (UTF-8) и их общая ширина в высотах строки.
local function splitLetters(text: string): ({ string }, number)
	local letters: { string } = {}
	local total = 0
	for _, code in utf8.codes(text) do
		local ch = utf8.char(code)
		table.insert(letters, ch)
		total += letterWidth(ch)
	end
	return letters, total
end

-- Погасить элемент со всем содержимым (add = на сколько прозрачнее; 1 — совсем) и запомнить,
-- как было. Только твины.
local function fadeGroup(root: Instance, add: number, time: number)
	local items: { Instance } = root:GetDescendants()
	table.insert(items, root)
	for _, item in items do
		local props: { string } = {}
		if item:IsA("GuiObject") then
			table.insert(props, "BackgroundTransparency")
		end
		if item:IsA("TextLabel") or item:IsA("TextButton") then
			table.insert(props, "TextTransparency")
			table.insert(props, "TextStrokeTransparency")
		elseif item:IsA("ImageLabel") or item:IsA("ImageButton") then
			table.insert(props, "ImageTransparency")
		elseif item:IsA("UIStroke") then
			table.insert(props, "Transparency")
		end
		if #props > 0 then
			local saved = faded[item] or {}
			faded[item] = saved
			local goals: { [string]: number } = {}
			for _, prop in props do
				local now = (item :: any)[prop] :: number
				local rest = saved[prop] or now
				saved[prop] = rest
				if rest < 1 then
					goals[prop] = math.min(1, rest + add)
				end
			end
			if next(goals) then
				UiFx.tween(item, time, goals)
			end
		end
	end
end

-- Вернуть погашенное под root как было.
local function unfadeGroup(root: Instance, time: number)
	for item, saved in faded do
		if item == root or item:IsDescendantOf(root) then
			faded[item] = nil
			if item.Parent and time > 0 then
				UiFx.tween(item, time, saved)
			elseif item.Parent then
				for prop, rest in saved do
					(item :: any)[prop] = rest
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Счётчик улова держит прошлое число, пока 🐟 не прилетит (договор с HudController)
--------------------------------------------------------------------------------

local function holdCounter(serial: number, total: number)
	if total >= 1 then
		heldSerial = serial
		ui.hud:SetAttribute("CounterHold", math.floor(total) - 1)
	end
end

local function releaseCounter(serial: number)
	if heldSerial == serial then
		heldSerial = 0
		ui.hud:SetAttribute("CounterHold", nil)
	end
end

--------------------------------------------------------------------------------
-- Раскладка карточки (квадратная / широкая) и рыба в ней
--------------------------------------------------------------------------------

-- UDim2 в пикселях (целые; не число — 0): Offset у UDim — целое.
local function offset(x: number, y: number): UDim2
	local function whole(v: number): number
		return if v == v and math.abs(v) < 1e6 then math.round(v) else 0
	end
	return UDim2.fromOffset(whole(x), whole(y))
end

-- Прямоугольник элемента «в покое» (без UIScale и поворота) в пикселях родителя размера
-- parentSize: Size, Position, AnchorPoint, SizeConstraint и UISizeConstraint.
local function restRect(gui: GuiObject, place: Place, parentSize: Vector2): (Vector2, Vector2)
	local basis = parentSize
	if place.SizeConstraint == Enum.SizeConstraint.RelativeYY then
		basis = Vector2.new(parentSize.Y, parentSize.Y)
	elseif place.SizeConstraint == Enum.SizeConstraint.RelativeXX then
		basis = Vector2.new(parentSize.X, parentSize.X)
	end
	local size, pos = place.Size, place.Position
	local w = size.X.Scale * basis.X + size.X.Offset
	local h = size.Y.Scale * basis.Y + size.Y.Offset
	local cap = gui:FindFirstChildOfClass("UISizeConstraint")
	if cap and gui ~= ui.card and gui ~= ui.rays then
		w = math.clamp(w, cap.MinSize.X, cap.MaxSize.X)
		h = math.clamp(h, cap.MinSize.Y, cap.MaxSize.Y)
	end
	local x = pos.X.Scale * parentSize.X + pos.X.Offset - place.AnchorPoint.X * w
	local y = pos.Y.Scale * parentSize.Y + pos.Y.Offset - place.AnchorPoint.Y * h
	return Vector2.new(x, y), Vector2.new(w, h)
end

local function placeOf(gui: GuiObject): Place
	return {
		Position = gui.Position,
		Size = gui.Size,
		AnchorPoint = gui.AnchorPoint,
		Rotation = gui.Rotation,
		SizeConstraint = gui.SizeConstraint,
	}
end

-- Элементы карточки, которые раскладываются заново (путь от карточки → элемент).
local function cardParts(): { [string]: GuiObject }
	local parts: { [string]: GuiObject } = {}
	for path in CARD_WIDE do
		local node: Instance? = ui.card
		for name in string.gmatch(path, "[^%.]+") do
			node = if node then node:FindFirstChild(name) else nil
		end
		if node and node:IsA("GuiObject") then
			parts[path] = node
		end
	end
	return parts
end

-- Заготовка из сборщика (квадратная раскладка): запоминается один раз, до первой перестановки.
local function rememberDefaults(): { [Instance]: Place }
	local saved = cardDefaults
	if saved then
		return saved
	end
	local fresh: { [Instance]: Place } = {}
	fresh[ui.card] = placeOf(ui.card)
	fresh[ui.rays] = placeOf(ui.rays)
	for _, gui in cardParts() do
		fresh[gui] = placeOf(gui)
	end
	local cap = ui.card:FindFirstChildOfClass("UISizeConstraint")
	if cap then
		-- Предел размера квадратной карточки (её UISizeConstraint ниже отпускается).
		fresh[cap] = {
			Position = UDim2.new(),
			Size = offset(cap.MaxSize.X, cap.MaxSize.Y),
			AnchorPoint = Vector2.zero,
			Rotation = 0,
			SizeConstraint = Enum.SizeConstraint.RelativeXY,
		}
	end
	cardDefaults = fresh
	return fresh
end

local function applyPlace(gui: GuiObject, place: Place)
	gui.AnchorPoint = place.AnchorPoint
	gui.SizeConstraint = place.SizeConstraint
	gui.Size = place.Size
	gui.Position = place.Position
	gui.Rotation = place.Rotation
end

-- Свободное место для широкой карточки (пиксели HUD.Fishing): от верха до хотбара, от джойстика
-- (или края) до кнопки действия (её подпись-лента выступает на 8 % ширины).
local function sideLimits(rootSize: Vector2): (number, number)
	local root = ui.fishing
	local left = CARD_SIDE_GAP
	if UserInputService.TouchEnabled then
		left = if math.min(rootSize.X, rootSize.Y) <= WIDE_BELOW then THUMBSTICK_CLEAR else THUMBSTICK_CLEAR_BIG
	end
	local button = ui.actionButton
	local area = button.Parent
	local right = rootSize.X - CARD_SIDE_GAP
	if area and area:IsA("GuiObject") then
		local areaLeft = area.AbsolutePosition.X - root.AbsolutePosition.X
		right = math.min(right, areaLeft - button.AbsoluteSize.X * 0.08 - CARD_SIDE_GAP)
	end
	return left, right
end

local function wideSlot(rootSize: Vector2): (Vector2, Vector2)
	local top = CARD_TOP_GAP
	local bottom = rootSize.Y - CARD_BOTTOM_CLEAR
	local left, right = sideLimits(rootSize)
	local h = math.max(bottom - top, 60)
	-- Баннер шире карточки на 5 %: он тоже должен влезть.
	local w = math.min(h * CARD_ASPECT, math.max(right - left, 120) / 1.05)
	h = math.min(h, w / CARD_ASPECT)
	local cx = math.clamp(rootSize.X / 2, left + w * 0.525, math.max(left + w * 0.525, right - w * 0.525))
	local cy = top + (bottom - top) / 2
	return Vector2.new(cx, cy), Vector2.new(w, h)
end

-- Затемнение — четыре полосы ВОКРУГ карточки (заходят под её скруглённые края на r px и далеко
-- за края экрана): середину закрывает сама карточка, второй раз её не затемняем (заливка). У
-- широкой карточки (телефон) — только верх и низ, как кадр в кино: по бокам от неё узкие
-- полоски мира, а лучи видны над и под ней.
local function placeDim(center: Vector2, size: Vector2, wide: boolean)
	local r = math.min(size.Y * 0.1, 22)
	local left, right = center.X - size.X / 2 + r, center.X + size.X / 2 - r
	local top, bottom = center.Y - size.Y / 2 + r, center.Y + size.Y / 2 - r
	local function whole(v: number): number
		return math.round(v)
	end
	local topBand, bottomBand, leftBand, rightBand = table.unpack(ui.dimBands)
	topBand.Position = UDim2.new(-1, 0, -1, 0)
	topBand.Size = UDim2.new(3, 0, 1, whole(top))
	bottomBand.Position = UDim2.new(-1, 0, 0, whole(bottom))
	bottomBand.Size = UDim2.new(3, 0, 2, -whole(bottom))
	leftBand.Position = UDim2.new(-1, 0, 0, whole(top))
	leftBand.Size = UDim2.new(1, whole(left), 0, whole(bottom - top))
	rightBand.Position = UDim2.new(0, whole(right), 0, whole(top))
	rightBand.Size = UDim2.new(2, -whole(right), 0, whole(bottom - top))
	leftBand.Visible = not wide
	rightBand.Visible = not wide
end

-- Затемнение: прозрачность полос → target за time (после delay).
local function dimTo(target: number, time: number, delay: number?)
	for _, band in ui.dimBands do
		UiFx.tween(
			band,
			time,
			{ BackgroundTransparency = target },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out,
			delay
		)
	end
end

-- Поставить карточку (и её лучи) на место: центр и размер в пикселях; внутри — широкая или
-- квадратная раскладка. scale — меньше для обычной рыбы.
local function placeCard(scale: number)
	local defaults = rememberDefaults()
	local root = ui.fishing
	local rootSize = root.AbsoluteSize
	local wide = rootSize.Y < WIDE_BELOW
	local center: Vector2, size: Vector2
	if wide then
		center, size = wideSlot(rootSize)
	else
		local pos, box = restRect(ui.card, defaults[ui.card], rootSize)
		local capPlace = nil
		local cap = ui.card:FindFirstChildOfClass("UISizeConstraint")
		if cap then
			capPlace = defaults[cap]
		end
		if capPlace then
			local limit = capPlace.Size
			local w = math.min(box.X, limit.X.Offset)
			local h = math.min(box.Y, limit.Y.Offset)
			pos = Vector2.new(
				pos.X + (box.X - w) * defaults[ui.card].AnchorPoint.X,
				pos.Y + (box.Y - h) * defaults[ui.card].AnchorPoint.Y
			)
			box = Vector2.new(w, h)
		end
		center, size = pos + box / 2, box
		-- Квадратная тоже не налезает на кнопку действия и джойстик (планшет 4:3): сдвиг влево,
		-- а не хватает места — меньше (баннер шире карточки на 8 %).
		local left, right = sideLimits(rootSize)
		local half = size.X * 0.54
		if center.X + half > right then
			local fit = math.min(1, (right - left) / (2 * half))
			size *= fit
			half *= fit
			center = Vector2.new(math.max(right - half, left + half), center.Y + (box.Y - size.Y) / 2)
		end
	end
	-- Обычная рыба — карточка поменьше, низ остаётся на месте (над хотбаром).
	local scaled = size * scale
	center += Vector2.new(0, (size.Y - scaled.Y) / 2)
	size = scaled
	for _, gui in { ui.card, ui.rays } do
		local cap = gui:FindFirstChildOfClass("UISizeConstraint")
		if cap then
			cap.MaxSize = Vector2.new(4096, 4096)
		end
		applyPlace(gui, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			SizeConstraint = Enum.SizeConstraint.RelativeXY,
			Size = offset(size.X, size.Y),
			Position = offset(center.X, center.Y),
			Rotation = 0,
		})
	end
	for path, gui in cardParts() do
		local base = defaults[gui]
		local place = base
		local wideSpec = if wide then CARD_WIDE[path] else nil
		if wideSpec then
			place = {
				Position = wideSpec.Position or base.Position,
				Size = wideSpec.Size or base.Size,
				AnchorPoint = wideSpec.AnchorPoint or base.AnchorPoint,
				Rotation = wideSpec.Rotation or base.Rotation,
				SizeConstraint = base.SizeConstraint,
			}
		end
		applyPlace(gui, place)
	end
	cardBox = { center = center, size = size, wide = wide }
	placeDim(center, size, wide)
end

-- Прямоугольник элемента карточки «в покое» (пиксели HUD.Fishing) — куда влетает слово
-- редкости и откуда вылетает 🐟 (карточка в этот миг может ещё расти или уже сжиматься).
local function cardRect(gui: GuiObject): (Vector2, Vector2)
	local box = cardBox
	if not box then
		return gui.AbsolutePosition - ui.fishing.AbsolutePosition, gui.AbsoluteSize
	end
	local origin = box.center - box.size / 2
	local parentPos, parentSize = origin, box.size
	local chain: { GuiObject } = {}
	local node: Instance? = gui
	while node and node ~= ui.card do
		if node:IsA("GuiObject") then
			table.insert(chain, 1, node)
		end
		node = node.Parent
	end
	for _, item in chain do
		local pos, size = restRect(item, placeOf(item), parentSize)
		parentPos, parentSize = parentPos + pos, size
	end
	return parentPos, parentSize
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

--[[
	Рыба во ViewportFrame: центр габаритов в нуле, вполоборота, покачивается ±30° и чуть «дышит»
	(ребром к камере не встаёт). Камера вписывает рыбу по обеим осям окна (FUI-02): по высоте —
	её высоту, по ширине — диагональ (X, Z), какой бы стороной она ни повернулась.
]]
local function showFishModel(fish: FishingRules.FishData)
	local template = fishTemplate(fish)
	if not template then
		return
	end
	local model = cardTrove:Add(template:Clone())
	local box, size = model:GetBoundingBox()
	local centred = model:GetPivot() - box.Position
	model:PivotTo(CFrame.Angles(0, CARD_YAW, 0) * centred)
	model.Parent = ui.viewport

	local fov = if cardBox and cardBox.wide then CARD_FOV_WIDE else CARD_FOV
	local _, view = cardRect(ui.viewport)
	local vTan = math.tan(math.rad(fov / 2))
	local hTan = vTan * view.X / math.max(view.Y, 1)
	local halfLen = Vector2.new(size.X, size.Z).Magnitude / 2
	local halfH = size.Y / 2
	local distance = math.max(halfH * 1.18 / vTan, halfLen * 1.08 / hTan, 0.5)
	local camera = cardTrove:Add(Instance.new("Camera"))
	camera.FieldOfView = fov
	camera.CFrame = CFrame.lookAt(Vector3.new(0, halfH * 0.35, distance), Vector3.zero)
	camera.Parent = ui.viewport
	ui.viewport.CurrentCamera = camera

	local elapsed = 0
	cardTrove:Add(UiFx.schedule(function(dt: number): boolean
		if model.Parent == nil then
			return false
		end
		elapsed += dt
		local yaw = CARD_YAW + CARD_SWING * math.sin(elapsed * 2 * math.pi / CARD_SWING_PERIOD)
		local bob = size.Y * CARD_BOB * math.sin(elapsed * 2 * math.pi / CARD_BOB_PERIOD)
		model:PivotTo(CFrame.new(0, bob, 0) * CFrame.Angles(0, yaw, 0) * centred)
		return true
	end))
end

-- Имя на кремовой карточке: тёмный градиент редкости с белой обводкой (мифическая — тёмная радуга).
local function nameColors(rarityId: string, style: UIConfig.RarityStyle): (ColorSequence, number)
	if style.Rainbow then
		local stops = {}
		for _, index in { 1, 2, 4, 6, 7 } do
			table.insert(stops, UiFx.darken(UIConfig.Rainbow[index], 0.15))
		end
		return UiFx.sequence(stops), 0
	elseif rarityId == "Common" then
		return ColorSequence.new(Palette.Night.Top, UIConfig.Ink), 90
	end
	return ColorSequence.new(style.Bottom, style.Lip), 90
end

local function fillCard(fish: FishingRules.FishData, style: UIConfig.RarityStyle)
	local rarity = FishingRules.GetRarity(fish.Rarity)

	-- Баннер редкости (мифическая — радуга, её запускает openCard).
	UiFx.setCandy(ui.banner, swatchOf(style))
	if style.Rainbow then
		ui.bannerFill.Color = UiFx.sequence(UIConfig.Rainbow)
		ui.bannerFill.Rotation = 0
	else
		ui.bannerFill.Rotation = 90
	end
	ui.rarityLabel.Text = upper(if rarity then rarity.Name else fish.Rarity)
	local disc = ui.fishGlow:FindFirstChild("Disc")
	if disc and disc:IsA("GuiObject") then
		disc.BackgroundColor3 = style.Top
	end
	ui.nameLabel.Text = FishingRules.DisplayName(fish)
	ui.nameFill.Color, ui.nameFill.Rotation = nameColors(fish.Rarity, style)

	-- Штамп мутации на углу рыбы: «ЗОЛОТАЯ ×2!»; Text — значение «Золотая мутация ×2».
	local mutationText = FishingRules.MutationLabel(fish)
	local mutation = if fish.Mutation then FishingRules.GetMutation(fish.Mutation) else nil
	local mutationStyle = if fish.Mutation then UIConfig.Mutations[fish.Mutation] else nil
	ui.mutationLabel.Visible = mutationText ~= nil
	ui.mutationLabel.Text = mutationText or ""
	ui.mutationCaption.Text = if mutation then `{upper(mutation.Name)} ×{mutation.Multiplier}!` else ""
	ui.priceMult.Text = if mutation then `×{mutation.Multiplier}` else ""
	ui.priceMult.Visible = false
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

	local kg = FishingRules.FormatKg(fish.Kg)
	local value = math.round(fish.Value)
	ui.infoLabel.Text = `{kg} · цена {value} 💰`
	ui.weightLabel.Text = kg
	ui.priceLabel.Text = "0"
end

--------------------------------------------------------------------------------
-- Мутация: рамка карточки, эффекты штампа
--------------------------------------------------------------------------------

-- Эффект штампа мутации по её стилю: золото — звёздочки, неон — светится, радуга — бежит.
local function mutationFx(style: UIConfig.MutationStyle)
	local badge = ui.mutationLabel
	if style.Effect == "sparkles" then
		cardTrove:Add(UiFx.sparkles(badge, { rate = 3, size = 0.9, area = 0.12 }))
	elseif style.Effect == "pulse" then
		cardTrove:Add(UiFx.glowRing(badge, {
			loop = true,
			color = style.Top,
			scale = 1.2,
			thickness = 3,
			time = 0.8,
			interval = 0.7,
		}))
	elseif style.Effect == "rainbow" then
		cardTrove:Add(UiFx.rainbow(ui.mutationFill, { speed = 0.6 }))
		cardTrove:Add(UiFx.sparkles(badge, { rate = 2, size = 0.8, area = 0.12, icons = { "✨", "🌈" } }))
	end
end

-- Обводка карточки — в цветах мутации и толще (4 px вместо 3; она уже есть — лишней заливки
-- нет): золото переливается, неон пульсирует, радуга вращается (180°/с). Только твины.
local function mutationRim(style: UIConfig.MutationStyle)
	local stroke = ui.cardOutline
	local color, thickness, transparency = stroke.Color, stroke.Thickness, stroke.Transparency
	local fill = Instance.new("UIGradient")
	fill.Name = "FxRimFill"
	fill.Rotation = 45
	fill.Color = if style.Effect == "rainbow"
		then UiFx.sequence(UIConfig.Rainbow)
		else UiFx.sequence({ style.Top, style.Bottom, style.Top })
	fill.Parent = stroke
	stroke.Color = WHITE
	stroke.Thickness = thickness * 4 / 3
	local loop = if style.Effect == "rainbow"
		then TweenService:Create(
			fill,
			TweenInfo.new(2, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
			{ Rotation = 405 }
		)
		else TweenService:Create(
			stroke,
			TweenInfo.new(
				if style.Effect == "pulse" then 0.45 else 0.9,
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.InOut,
				-1,
				true
			),
			{ Transparency = if style.Effect == "pulse" then 0.6 else 0.3 }
		)
	loop:Play()
	cardTrove:Add(function()
		loop:Cancel()
		fill:Destroy()
		stroke.Color = color
		stroke.Thickness = thickness
		stroke.Transparency = transparency
	end)
end

--------------------------------------------------------------------------------
-- Огромное слово редкости (эпическая и выше)
--------------------------------------------------------------------------------

local titleTweens: { Tween } = {} -- волна букв

-- Спрятать огромное слово: буквы и их волна — прочь.
local function clearTitle()
	ui.titleSlam.Visible = false
	for _, swing in titleTweens do
		swing:Cancel()
	end
	table.clear(titleTweens)
	for _, old in ui.titleLetters:GetChildren() do
		old:Destroy()
	end
end

-- Слово (одной надписью или по буквам) — в центре экрана, размер в пикселях HUD.Fishing.
local function slamTitle(rarityId: string, reveal: Reveal, style: UIConfig.RarityStyle)
	local text = TITLE_TEXT[rarityId]
	if not text then
		return
	end
	local title = ui.titleSlam
	local rootSize = ui.fishing.AbsoluteSize
	local letters, total = splitLetters(text)
	local height = math.max(rootSize.Y * 0.17, 28)
	local width = math.min(total * height, rootSize.X * 0.94)
	height = math.min(height, width / total)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.42)
	title.Size = UDim2.fromScale(width / math.max(rootSize.X, 1), height / math.max(rootSize.Y, 1))
	clearTitle()
	local single = not reveal.Letters
	ui.titleLabel.Visible = single
	ui.titleLabel.Text = text
	ui.titleSlamFill.Color = ColorSequence.new(WHITE, UiFx.lighten(style.Top, 0.1))

	if not single then
		-- По букве на надпись: волна вверх-вниз (твины), легендарная — золото, мифическая — радуга.
		local x = 0
		local labels: { TextLabel } = {}
		for index, ch in letters do
			local w = letterWidth(ch)
			local letter = Instance.new("TextLabel")
			letter.Name = `L{index}`
			letter.BackgroundTransparency = 1
			letter.FontFace = ui.titleLabel.FontFace
			letter.Text = ch
			letter.TextScaled = true
			letter.TextColor3 = WHITE
			letter.TextStrokeTransparency = 1
			letter.AnchorPoint = Vector2.new(0, 0.5)
			letter.Position = UDim2.fromScale(x / total, 0.5)
			letter.Size = UDim2.fromScale(w / total, 1)
			letter.ZIndex = 2
			local outline = Instance.new("UIStroke")
			outline.Name = "Outline"
			outline.Color = UIConfig.Ink
			outline.Thickness = 3
			outline.LineJoinMode = Enum.LineJoinMode.Round
			outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
			outline:SetAttribute("BaseThickness", 5)
			outline.Parent = letter
			local fill = Instance.new("UIGradient")
			fill.Name = "TextFill"
			fill.Rotation = 90
			if style.Rainbow then
				letter.TextColor3 = UIConfig.Rainbow[(index - 1) % #UIConfig.Rainbow + 1]
				fill.Color = ColorSequence.new(WHITE, Color3.fromRGB(215, 215, 215))
			else
				fill.Color = ColorSequence.new(Color3.fromRGB(255, 251, 214), style.Bottom)
			end
			fill.Parent = letter
			letter.Parent = ui.titleLetters
			table.insert(labels, letter)
			x += w
			UiFx.popIn(letter, { from = 0.2, time = 0.24, delay = 0.015 * index })
			-- Волна: каждая буква качается вверх-вниз со своим сдвигом фазы.
			later(catchTrove, 0.3 + 0.06 * index, function()
				local swing = TweenService:Create(
					letter,
					TweenInfo.new(0.32, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
					{ Position = UDim2.new(letter.Position.X.Scale, 0, 0.5, -4) }
				)
				swing:Play()
				table.insert(titleTweens, swing)
			end)
		end
		if style.Rainbow then
			-- Радуга бежит по буквам (один покадровый эффект на все).
			local phase = 0
			catchTrove:Add(UiFx.schedule(function(dt: number): boolean
				phase += dt * 0.8
				for index, letter in labels do
					if letter.Parent == nil then
						return false
					end
					local hue = (index * 0.085 + phase) % 1
					letter.TextColor3 = Color3.fromHSV(hue, 0.7, 1)
				end
				return true
			end))
		end
	end
	title.Visible = true
	local slam = UiFx.scaleOf(title)
	slam.Scale = if single then 2.5 else 1.7 -- буквы и так выскакивают по одной
	UiFx.tween(slam, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UiFx.sound("swoosh", 0.5, 0.8)
	UiFx.sound("pop", 0.55, 0.9)
	catchTrove:Add(clearTitle)
end

-- Слово влетает в баннер карточки (его надпись «в покое») и превращается в него.
local function morphTitle(time: number, onDone: () -> ())
	local title = ui.titleSlam
	if not title.Visible then
		onDone()
		return
	end
	local rootSize = ui.fishing.AbsoluteSize
	local pos, size = cardRect(ui.rarityLabel)
	local _, total = splitLetters(ui.titleLabel.Text)
	local h = size.Y * 1.05
	local w = math.min(total * h, size.X * 1.15)
	h = math.min(h, w / total)
	local center = pos + size / 2
	UiFx.tween(title, time, {
		Position = UDim2.fromScale(center.X / math.max(rootSize.X, 1), center.Y / math.max(rootSize.Y, 1)),
		Size = UDim2.fromScale(w / math.max(rootSize.X, 1), h / math.max(rootSize.Y, 1)),
	}, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	later(catchTrove, time, function()
		clearTitle()
		if ui.card.Visible then
			onDone()
		end
	end)
end

--------------------------------------------------------------------------------
-- Победа в мини-игре и ожидание приземления
--------------------------------------------------------------------------------

-- Когда мини-игра последний раз появилась: "Caught" бывает только после неё, но атрибут
-- FishingState = "Idle" может обогнать событие и спрятать панель раньше — копия всё равно нужна.
local minigameShownAt = -math.huge

-- Копия мини-игры «побеждает»: последний ⭐ печатается, зона вспыхивает золотом, искры,
-- «ПОЙМАНА!»; через 0.3 с подпрыгивает и уходит (сжимается, поднимается, тает). Панель могла
-- уже спрятаться (сервер закончил рыбалку атрибутом чуть раньше события) — копия всё равно видна.
local function winGhost(rarityId: string)
	local source = ui.minigame
	if not source.Visible and os.clock() - minigameShownAt > FishingConfig.MinigameTimeout + 1 then
		return
	end
	local style = UIConfig.Rarity[rarityId] or UIConfig.Rarity.Common
	local legendary = rarityId == "Legendary" or rarityId == "Mythic"
	local ghost = source:Clone()
	ghost.Name = "FxMinigameWin"
	ghost.Visible = true
	for _, item in ghost:GetDescendants() do
		if item.Name == "FxGhost" or item.Name == "FxFloat" or item.Name == "FxBurst" then
			item:Destroy() -- застывший шлейф стрелки похож на лишние стрелки
		end
	end
	ghost.Parent = source.Parent

	-- Последний нужный кружок попадания (сколько их видно) — с ⭐.
	local pips = ghost:FindFirstChild("Pips")
	local last = 1
	for index = 1, 5 do
		local candidate = pips and pips:FindFirstChild(`Pip{index}`)
		if candidate and candidate:IsA("GuiObject") and candidate.Visible then
			last = index
		end
	end
	local pip = pips and pips:FindFirstChild(`Pip{last}`)
	if pip and pip:IsA("GuiObject") then
		pip.BackgroundColor3 = COLORS.PipDone
		local star = pip:FindFirstChild("Star")
		if star and star:IsA("TextLabel") then
			star.TextTransparency = 0
			local scale = UiFx.scaleOf(star)
			scale.Scale = 2
			UiFx.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		end
	end
	local track = ghost:FindFirstChild("Track")
	local zone = track and track:FindFirstChild("Zone")
	local flash = zone and zone:FindFirstChild("Flash")
	local zoneX = if zone and zone:IsA("GuiObject") then zone.Position.X.Scale else 0.5
	local origin = Vector2.new(defaults.trackLeft + zoneX * defaults.trackWidth, defaults.trackMidY)
	if flash and flash:IsA("GuiObject") then
		flash.BackgroundColor3 = Palette.Gold.Top
		flash.BackgroundTransparency = 0.05
		UiFx.tween(flash, 0.3, { BackgroundTransparency = 1 })
	end
	UiFx.burst(ghost, {
		origin = origin,
		count = 24,
		colors = { style.Top, WHITE, Palette.Gold.Top },
		power = 1.7,
		z = 9,
	})

	-- «ПОЙМАНА!» над панелью (≈40 px), на слое HUD — панель сейчас уйдёт.
	local hud = ui.hud
	local hudSize = hud.AbsoluteSize
	local top = source.AbsolutePosition - hud.AbsolutePosition
	local textHeight = math.clamp(hudSize.Y * 0.12, 34, 64)
	UiFx.floatText(hud, WIN_TEXT, {
		position = offset(top.X + source.AbsoluteSize.X / 2, top.Y - textHeight * 0.2),
		size = offset(textHeight * 5, textHeight),
		colors = if legendary
			then { Palette.Gold.Top, Palette.Sun.Bottom }
			else { Palette.Leaf.Top, Palette.Leaf.Bottom },
		rise = 0.1,
		time = 1.0,
		rotate = -4,
		z = 30,
	})
	UiFx.sound("pop", 0.55, 1.25)

	task.delay(0.3, function()
		if ghost.Parent == nil then
			return
		end
		UiFx.bump(ghost, 1.06, 0.14)
		task.delay(0.12, function()
			if ghost.Parent == nil then
				return
			end
			UiFx.tween(UiFx.scaleOf(ghost), 0.25, { Scale = 0.6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			UiFx.tween(
				ghost,
				0.25,
				{ Position = ghost.Position - UDim2.fromScale(0, 0.05) },
				Enum.EasingStyle.Quad,
				Enum.EasingDirection.In
			)
			UiFx.fadeOut(ghost, 0.25)
			task.delay(0.27, function()
				ghost:Destroy()
			end)
		end)
	end)
end

-- Точка над головой своего персонажа (если сигнала с точкой рыбы нет).
local function headPoint(): Vector3?
	local character = player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.new(0, 2.5, 0)
	end
	return nil
end

-- Точка мира на экране в пикселях HUD.Fishing (в пределах экрана), или nil — не видно.
local function screenPoint(world: Vector3?): Vector2?
	local camera = Workspace.CurrentCamera
	if not camera or not world then
		return nil
	end
	local point, onScreen = camera:WorldToScreenPoint(world)
	if not onScreen or point.Z <= 0 then
		return nil
	end
	local root = ui.fishing
	local local2 = Vector2.new(point.X, point.Y) - root.AbsolutePosition
	local size = root.AbsoluteSize
	return Vector2.new(
		math.clamp(local2.X, size.X * 0.08, size.X * 0.92),
		math.clamp(local2.Y, size.Y * 0.1, size.Y * 0.85)
	)
end

--------------------------------------------------------------------------------
-- Доли карточки, пропуск, закрытие
--------------------------------------------------------------------------------

local function addBeat(at: number, run: (instant: boolean) -> ())
	local beat = { at = at, run = run, done = false }
	table.insert(cardBeats, beat)
	later(cardTrove, at, function()
		if not beat.done then
			beat.done = true
			run(false)
		end
	end)
end

-- Тап до последней доли: всё оставшееся — сразу в конечном виде, карточка подпрыгивает.
local function skipBeats()
	for _, beat in cardBeats do
		if not beat.done then
			beat.done = true
			beat.run(true)
		end
	end
	for _, hook in skipHooks do
		hook()
	end
	UiFx.bump(ui.card, 1.06, 0.25)
end

-- Карточка уходит: копия сжимается и сдвигается на четверть пути к счётчику, тает.
local function ghostCard(): GuiObject
	local ghost = ui.card:Clone()
	ghost.Name = "FxCardOut"
	ghost.Active = false
	pcall(function()
		(ghost :: any).Interactable = false -- копия не ловит нажатия (где свойство есть)
	end)
	for _, item in ghost:GetDescendants() do
		if item.Name == "FxSparkle" or item.Name == "FxRing" or item.Name == "FxGlitter" then
			item:Destroy() -- застывшие звёздочки и кольца выглядят странно
		end
	end
	local viewport = ghost:FindFirstChild("Viewport")
	local camera = viewport and viewport:FindFirstChildOfClass("Camera")
	if viewport and viewport:IsA("ViewportFrame") and camera then
		viewport.CurrentCamera = camera
	end
	ghost.Parent = ui.card.Parent
	local root = ui.fishing
	local counter = ui.counter
	local target = counter.AbsolutePosition + counter.AbsoluteSize / 2 - root.AbsolutePosition
	local box = cardBox
	local from = if box then box.center else ghost.AbsolutePosition + ghost.AbsoluteSize / 2 - root.AbsolutePosition
	local to = from:Lerp(target, 0.25)
	local quad, inward = Enum.EasingStyle.Quad, Enum.EasingDirection.In
	UiFx.tween(ghost, 0.22, { Position = offset(to.X, to.Y) }, quad, inward)
	UiFx.tween(UiFx.scaleOf(ghost), 0.22, { Scale = 0.6 }, quad, inward)
	UiFx.fadeOut(ghost, 0.2)
	task.delay(0.24, function()
		ghost:Destroy()
	end)
	return ghost
end

-- 🐟 прилетела: счётчик +1 (CounterHold снят), через 0.15 с кнопка снова «ЗАБРОСИТЬ».
local function finishCatch(serial: number, animate: boolean)
	releaseCounter(serial)
	if serial ~= catchSerial or not catchScreen then
		return
	end
	catchScreen = false
	unfadeGroup(ui.actionButton, 0) -- сразу: вид кнопки ставит refreshButtons (а «выскок» скрывает смену)
	refreshButtons()
	local button = ui.actionButton
	if animate and button.Visible then
		UiFx.popIn(button, { from = 0.3, time = 0.35 })
		UiFx.glowRing(button, { color = WHITE, scale = 1.3, thickness = 5, time = 0.6 })
	end
	refreshContextHint()
end

-- 🐟 (и ✨ цвета редкости следом) летит из карточки в счётчик улова.
local function flyHome(from: GuiObject, reveal: Reveal, serial: number)
	local hud = ui.hud
	local height = math.max(hud.AbsoluteSize.Y, 1)
	local fishPx = math.max(28, height * 0.075) -- 🐟 ≈ 28 px на телефоне, крупнее на больших
	local counter = ui.counter
	celebrationTrove:Add(UiFx.flyTo(hud, from, counter, {
		text = "🐟",
		time = 0.5,
		size = fishPx / height,
		onArrive = function()
			releaseCounter(serial) -- счётчик +1 (его «прилёт» играет HudController)
			UiFx.sound("pop", 0.35, 1.2)
			task.delay(0.15, finishCatch, serial, true)
		end,
	}))
	for index = 1, reveal.Trail do
		later(celebrationTrove, 0.04 * index, function()
			celebrationTrove:Add(UiFx.flyTo(hud, from, counter, {
				text = "✨",
				time = 0.5,
				size = fishPx * (0.7 - 0.04 * index) / height,
				arc = 0.18 + 0.02 * (index % 3),
			}))
		end)
	end
end

local function closeCard()
	local card = ui.card
	if not card.Visible then
		return
	end
	local serial = catchSerial
	local reveal = cardReveal
	local ghost = ghostCard()
	local glow = ghost:FindFirstChild("FishGlow")
	cardTrove:Clean()
	card.Visible = false
	cardSettled = true
	clearTitle()

	-- Лучи сжимаются вместе с карточкой, затемнение тает.
	for _, holder in ui.rays:GetChildren() do
		if holder.Name == "FxRays" and holder:IsA("GuiObject") then
			UiFx.tween(UiFx.scaleOf(holder), 0.2, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
	end
	later(raysTrove, 0.22, function()
		raysTrove:Clean()
	end)
	local dim = ui.dim
	dimTo(1, DIM_TIME * 0.8)
	later(celebrationTrove, DIM_TIME * 0.8, function()
		if not ui.card.Visible then
			dim.Visible = false
		end
	end)
	-- Счётчик — цель полёта: плашки статуса возвращаются сразу (полёт начнётся через 0.05 с).
	unfadeGroup(ui.status, STATUS_FADE)
	later(celebrationTrove, 0.05, function()
		flyHome(if glow and glow:IsA("GuiObject") then glow else ghost, reveal, serial)
	end)
	UiFx.sound("swoosh", 0.3)
end

-- Тап по карточке / действие: до неё — ничего (рыба ещё летит), в первые CARD_INPUT_LOCK —
-- ничего (лишний тап после победного), до последней доли — пропуск, потом — закрыть.
local function tapCard()
	if not catchScreen or not ui.card.Visible then
		return
	end
	if os.clock() - cardOpenedAt < CARD_INPUT_LOCK then
		return
	end
	if cardSettled then
		closeCard()
	else
		skipBeats()
	end
end

-- «Печать» из from: масштаб from → 1 и доворот rotate → место (Back Out).
local function stampIn(gui: GuiObject, from: number, rotate: number, time: number)
	local scale = UiFx.scaleOf(gui)
	scale.Scale = from
	UiFx.tween(scale, time, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local rest = gui.Rotation
	gui.Rotation = rest + rotate
	UiFx.tween(gui, time, { Rotation = rest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
end

-- Цена набегает (Cubic Out) от from до to; тик — только когда число сменилось, не чаще 20 раз
-- в секунду, тон растёт pitchFrom → pitchTo. Возвращает stop (сразу конечное число).
local function countPrice(from: number, to: number, time: number, pitchFrom: number, pitchTo: number): () -> ()
	local label = ui.priceLabel
	local shown = math.floor(from + 0.5)
	label.Text = FishingRules.FormatCoins(shown)
	local elapsed = 0
	local lastTick = -math.huge
	return UiFx.schedule(function(dt: number): boolean
		elapsed += dt
		local k = math.min(1, elapsed / math.max(time, 0.01))
		local eased = 1 - (1 - k) ^ 3
		local value = math.floor(from + (to - from) * eased + 0.5)
		if value ~= shown then
			shown = value
			label.Text = FishingRules.FormatCoins(value)
			if elapsed - lastTick >= 0.05 then
				lastTick = elapsed
				UiFx.sound("tick", 0.18, pitchFrom + (pitchTo - pitchFrom) * k)
			end
		end
		return k < 1
	end, function()
		label.Text = FishingRules.FormatCoins(to)
	end)
end

-- Дождь 💰 сверху экрана (легендарная рыба, когда цена «приземлилась»). Только твины.
local function coinRain(count: number, time: number)
	local hud = ui.hud
	local rng = Random.new()
	for index = 1, count do
		local coin = Instance.new("TextLabel")
		coin.Name = "FxCoin"
		coin.BackgroundTransparency = 1
		coin.Text = "💰"
		coin.TextScaled = true
		coin.AnchorPoint = Vector2.new(0.5, 0.5)
		coin.SizeConstraint = Enum.SizeConstraint.RelativeYY
		coin.Size = UDim2.fromScale(0.075, 0.075)
		local x = rng:NextNumber(0.12, 0.88)
		coin.Position = UDim2.fromScale(x, -0.08)
		coin.Rotation = rng:NextNumber(-30, 30)
		coin.ZIndex = 55
		coin.Parent = hud
		celebrationTrove:Add(coin)
		local fall = time * rng:NextNumber(0.7, 1)
		local wait = (index - 1) * time * 0.035
		UiFx.tween(coin, fall, {
			Position = UDim2.fromScale(x + rng:NextNumber(-0.06, 0.06), 1.1),
			Rotation = coin.Rotation + rng:NextNumber(-220, 220),
		}, Enum.EasingStyle.Quad, Enum.EasingDirection.In, wait)
		task.delay(wait + fall + 0.05, function()
			coin:Destroy()
		end)
	end
end

-- Мифическая: после последней доли вокруг карточки медленно всплывают и тают ✨.
local function glitter(count: number)
	local card = ui.card
	local rng = Random.new()
	for index = 1, count do
		local star = Instance.new("TextLabel")
		star.Name = "FxGlitter"
		star.BackgroundTransparency = 1
		star.Text = if index % 3 == 0 then "⭐" else "✨"
		star.TextScaled = true
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.SizeConstraint = Enum.SizeConstraint.RelativeYY
		star.Size = UDim2.fromScale(0.09, 0.09)
		local side = index % 4
		local x = if side == 0 then -0.03 elseif side == 1 then 1.03 else rng:NextNumber(0.05, 0.95)
		local y = if side == 2 then -0.04 elseif side == 3 then 1.02 else rng:NextNumber(0.1, 0.9)
		star.Position = UDim2.fromScale(x, y)
		star.ZIndex = 9
		star.Parent = card
		cardTrove:Add(star)
		local scale = UiFx.scaleOf(star)
		scale.Scale = 0
		local wait = (index - 1) * 0.22
		UiFx.tween(scale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out, wait)
		UiFx.tween(
			star,
			2.2,
			{ Position = UDim2.fromScale(x, y - 0.12), Rotation = rng:NextNumber(-40, 40) },
			Enum.EasingStyle.Sine,
			Enum.EasingDirection.Out,
			wait
		)
		UiFx.tween(star, 0.8, { TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In, wait + 1.4)
		task.delay(wait + 2.25, function()
			star:Destroy()
		end)
	end
end

--------------------------------------------------------------------------------
-- Карточка: открытие и доли
--------------------------------------------------------------------------------

local function openCard(fish: FishingRules.FishData, from: Vector2?)
	cardTrove:Clean()
	raysTrove:Clean()
	table.clear(cardBeats)
	table.clear(skipHooks)
	cardSettled = false
	cardOpenedAt = os.clock()

	local style = UIConfig.Rarity[fish.Rarity] or UIConfig.Rarity.Common
	local reveal = REVEAL[fish.Rarity] or REVEAL.Common
	local mutationStyle = if fish.Mutation then UIConfig.Mutations[fish.Mutation] else nil
	local mutation = if fish.Mutation then FishingRules.GetMutation(fish.Mutation) else nil
	local card = ui.card
	local isNew = not seenSpecies[fish.Id]
	seenSpecies[fish.Id] = true
	cardReveal = reveal

	placeCard(reveal.Scale)
	fillCard(fish, style)
	showFishModel(fish)
	card.Visible = true
	ui.rays.Visible = true
	local box = cardBox :: { center: Vector2, size: Vector2, wide: boolean }

	-- Всё, что появится по долям, пока спрятано.
	local hidden: { GuiObject } = { ui.banner, ui.nameLabel, ui.weightChip, ui.priceChip, ui.newStamp }
	for _, gui in hidden do
		UiFx.scaleOf(gui).Scale = 0
	end
	ui.newStamp.Visible = isNew
	if mutationStyle then
		UiFx.scaleOf(ui.mutationLabel).Scale = 0
	end
	ui.tapHint.TextTransparency = 1

	-- Карточка рождается в точке рыбы над головой и встаёт на место с доворотом.
	local start = from or box.center
	card.Position = offset(start.X, start.Y)
	UiFx.tween(
		card,
		0.35,
		{ Position = offset(box.center.X, box.center.Y) },
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)
	UiFx.popIn(card, { from = 0.4, time = 0.35, rotate = -6 })
	UiFx.sound("pop", 0.5, 0.9)

	-- Затемнение (у обычной — нет) и лучи растут вместе с карточкой.
	local dim = ui.dim
	if reveal.Dim < 1 then
		dim.Visible = true
		for _, band in ui.dimBands do
			band.BackgroundTransparency = 1
		end
		-- Чуть позже карточки: пока она летит на место, «дырка» под ней не видна.
		dimTo(reveal.Dim, DIM_TIME, 0.1)
	else
		dim.Visible = false
	end
	-- На тач-экране лучей меньше и они короче (заливка на телефоне: карточка и затемнение уже
	-- занимают почти весь экран), без ореолов, «дыхания» и свечения в центре (оно под карточкой).
	local touch = UserInputService.TouchEnabled
	local maxPx = if touch then reveal.MaxPx else nil
	local rays = raysTrove:Add(UiFx.rays(ui.rays, {
		colors = style.Rays,
		count = if touch then math.max(8, reveal.Rays - 4) else reveal.Rays,
		speed = reveal.Speed,
		size = reveal.Size,
		maxPx = maxPx,
		transparency = reveal.Alpha,
		glow = not touch,
		grow = 0.5,
	}))
	local extraColors: { Color3 }? = if reveal.Extra then style.Rays else nil
	if mutationStyle then
		extraColors = if mutationStyle.Effect == "rainbow"
			then UIConfig.Rainbow
			else { mutationStyle.Top, mutationStyle.Bottom }
	end
	local extra: UiFx.Rays? = nil
	if extraColors then
		extra = raysTrove:Add(UiFx.rays(ui.rays, {
			colors = extraColors,
			count = if touch then 6 else 8,
			speed = -reveal.Speed * 0.6,
			size = reveal.Size * 1.2,
			maxPx = if maxPx then maxPx * 1.12 else nil,
			width = 0.045,
			transparency = math.min(reveal.Alpha + 0.2, 0.8),
			glow = false,
			halo = false,
			breathe = false,
			grow = 0.6,
		}))
	end
	raysTrove:Add(function()
		ui.rays.Visible = false
	end)

	-- Рыба на мягком свечении (пульс — до последней доли), редкие звёздочки вокруг.
	local stopGlow = cardTrove:Add(UiFx.pulse(ui.fishGlow, 1.08, 1.4))
	cardTrove:Add(UiFx.sparkles(ui.fishGlow, { rate = reveal.Sparkles, size = 0.22, area = 0.3 }))
	if style.Rainbow then
		cardTrove:Add(UiFx.rainbow(ui.bannerFill, { speed = 0.45 }))
	end

	-- c+0.20 — редкость: огромное слово влетает в баннер (эпическая и выше) или баннер «бьёт».
	local bannerShown = false
	local function showBanner(instant: boolean, fromTitle: boolean?)
		if bannerShown then
			return
		end
		bannerShown = true
		UiFx.scaleOf(ui.banner).Scale = 1
		if instant then
			return
		end
		if fromTitle then
			UiFx.bump(ui.banner, 1.12, 0.3) -- слово уже «стало» баннером: только толчок
		else
			UiFx.slam(ui.banner, 1.8, 0.3)
		end
		UiFx.glowRing(ui.banner, { color = style.Top, scale = 1.3, thickness = 3, time = 0.4 })
		UiFx.wiggle(child(ui.banner, "StarLeft"), 18, 3, 0.5)
		UiFx.wiggle(child(ui.banner, "StarRight"), 18, 3, 0.5)
		if style.Rainbow then
			cardTrove:Add(UiFx.sparkles(ui.banner, { rate = 3, size = 0.9, area = 0.1 }))
		end
	end
	table.insert(skipHooks, function()
		if not bannerShown then
			clearTitle() -- слово ещё летит в баннер: сразу баннер
			showBanner(true)
		end
	end)
	addBeat(0.2, function(instant: boolean)
		if instant then
			clearTitle()
			showBanner(true)
			return
		end
		cardTrove:Add(UiFx.arpeggio(fish.Rarity, 0.4))
		if ui.titleSlam.Visible then
			morphTitle(0.3, function()
				showBanner(false, true)
			end)
		else
			showBanner(false)
		end
	end)
	-- c+0.50 — имя.
	addBeat(0.5, function(instant: boolean)
		if instant then
			UiFx.scaleOf(ui.nameLabel).Scale = 1
			return
		end
		UiFx.popIn(ui.nameLabel, { from = 0.3, time = 0.3 })
		UiFx.sound("pop", 0.35, 1.1)
	end)
	-- c+0.65 — «НОВИНКА!».
	if isNew then
		addBeat(0.65, function(instant: boolean)
			if instant then
				UiFx.scaleOf(ui.newStamp).Scale = 1
				return
			end
			stampIn(ui.newStamp, 2.2, -16, 0.3)
			UiFx.sound("pop", 0.4, 1.3)
		end)
	end
	-- c+0.85 — вес и цена.
	addBeat(0.85, function(instant: boolean)
		if instant then
			UiFx.scaleOf(ui.weightChip).Scale = 1
			UiFx.scaleOf(ui.priceChip).Scale = 1
			return
		end
		UiFx.popIn(ui.weightChip, { from = 0, time = 0.3 })
		UiFx.popIn(ui.priceChip, { from = 0, time = 0.3, delay = 0.06 })
		UiFx.sound("tick", 0.3, 1.1)
	end)

	-- c+0.95 — цена набегает (с мутацией — сначала до цены без неё).
	local value = math.round(fish.Value)
	local multiplier = if mutation then math.max(mutation.Multiplier, 1) else 1
	local base = math.round(value / multiplier)
	local countStart = 0.95
	local landed = countStart + reveal.Count
	addBeat(countStart, function(instant: boolean)
		if instant then
			ui.priceLabel.Text = FishingRules.FormatCoins(base)
			return
		end
		local count = countPrice(0, base, reveal.Count, 1, 1.4)
		stopPriceCount = count
		cardTrove:Add(count)
	end)
	-- Цена «приземлилась»: подпрыгивает, искры, монетный «дзынь»; легендарная — дождь 💰.
	addBeat(landed, function(instant: boolean)
		local count = stopPriceCount
		stopPriceCount = nil
		if count then
			count()
		end
		ui.priceLabel.Text = FishingRules.FormatCoins(base)
		if instant then
			return
		end
		UiFx.bump(ui.priceChip, 1.3, 0.35)
		UiFx.wiggle(ui.priceIcon, 18, 3, 0.45)
		UiFx.shine(ui.priceChip, 0.5)
		UiFx.sound("pop", 0.45, 1.5)
		local pos, size = cardRect(ui.priceChip)
		local root = ui.fishing.AbsoluteSize
		local center = pos + size / 2
		cardTrove:Add(UiFx.burst(ui.fishing, {
			origin = Vector2.new(center.X / math.max(root.X, 1), center.Y / math.max(root.Y, 1)),
			count = 10,
			colors = { WHITE, Palette.Gold.Top, Palette.Sun.Top },
			power = 0.8,
			z = 13,
		}))
		if fish.Rarity == "Legendary" then
			coinRain(10, 1.5)
			if reveal.Confetti2 > 0 then
				celebrationTrove:Add(UiFx.confetti(ui.hud, {
					count = reveal.Confetti2,
					colors = style.Confetti,
					origin = Vector2.new(0.5, 0.25),
					spread = 160,
					power = 0.9,
				}))
			end
		end
	end)

	-- Мутация: штамп на углу рыбы, «×N» у цены, цена пересчитывается до полной, рамка карточки.
	local finish = landed
	if mutationStyle and mutation then
		local stampAt = landed + 0.15
		finish = stampAt + 0.65
		addBeat(stampAt, function(instant: boolean)
			mutationRim(mutationStyle)
			mutationFx(mutationStyle)
			ui.priceMult.Visible = true
			if instant then
				UiFx.scaleOf(ui.mutationLabel).Scale = 1
				UiFx.scaleOf(ui.priceMult).Scale = 1
				ui.priceLabel.Text = FishingRules.FormatCoins(value)
				return
			end
			stampIn(ui.mutationLabel, 1.8, 12, 0.3)
			UiFx.sound("swoosh", 0.4, 1.2)
			UiFx.sound("pop", 0.5, 1.1)
			later(cardTrove, 0.15, function()
				UiFx.stamp(ui.priceMult, 16, 0.25)
				UiFx.sound("pop", 0.45, 1.4)
			end)
			later(cardTrove, 0.2, function()
				local recount = countPrice(base, value, 0.4, 1.2, 1.8)
				stopPriceCount = recount
				cardTrove:Add(recount)
			end)
			later(cardTrove, 0.62, function()
				ui.priceLabel.Text = FishingRules.FormatCoins(value)
				UiFx.bump(ui.priceChip, 1.4, 0.4)
				UiFx.shine(ui.priceChip, 0.5)
				local pos, size = cardRect(ui.priceChip)
				local root = ui.fishing.AbsoluteSize
				local center = pos + size / 2
				cardTrove:Add(UiFx.burst(ui.fishing, {
					origin = Vector2.new(center.X / math.max(root.X, 1), center.Y / math.max(root.Y, 1)),
					count = 12,
					colors = if mutationStyle.Effect == "rainbow"
						then UIConfig.Rainbow
						else { WHITE, mutationStyle.Top, mutationStyle.Bottom },
					power = 1,
					z = 13,
				}))
			end)
		end)
		addBeat(finish - 0.02, function(_instant: boolean)
			local recount = stopPriceCount
			stopPriceCount = nil
			if recount then
				recount()
			end
			ui.priceLabel.Text = FishingRules.FormatCoins(value)
		end)
	end

	-- Последняя доля: подсказка «закрыть», всё успокаивается (лучи, свечение, звёзды реже).
	local last = finish + 0.2
	addBeat(last, function(instant: boolean)
		cardSettled = true
		stopGlow()
		rays:settle({ alphaAdd = 0.18, spinMul = 0.5, time = 0.6 })
		if extra then
			extra:settle({ alphaAdd = 0.18, spinMul = 0.5, time = 0.6 })
		end
		-- Подсказка проявляется, потом «дышит» 0 ↔ 0.35 (период 1.2 с).
		local hint = ui.tapHint
		hint.TextTransparency = if instant then 0 else 1
		local appear = UiFx.tween(hint, 0.25, { TextTransparency = 0 })
		local breathe = TweenService:Create(
			hint,
			TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ TextTransparency = 0.35 }
		)
		later(cardTrove, 0.3, function()
			hint.TextTransparency = 0
			breathe:Play()
		end)
		cardTrove:Add(function()
			appear:Cancel()
			breathe:Cancel()
			hint.TextTransparency = 0
		end)
		if style.Flash then
			cardTrove:Add(UiFx.shineLoop(ui.banner, { interval = 2.4, delay = 0.4 }))
		end
		if style.Rainbow then
			glitter(8)
		end
	end)

	-- Сама закроется: по редкости (UIConfig.CatchCardTime), но не раньше, чем через секунду
	-- после последней доли.
	local auto = math.max(UIConfig.CatchCardTime[fish.Rarity] or UIConfig.CatchCardTime.Common, last + 1)
	later(cardTrove, auto, closeCard)
	cardTrove:Add(function()
		local count = stopPriceCount
		stopPriceCount = nil
		if count then
			count()
		end
	end)

	refreshContextHint()
end

-- Рыба приземлилась над головой (или прыжка нет): вспышка, тряска, «толчок», конфетти из точки
-- над головой; у эпической и выше — огромное слово; через Hold — карточка.
local function onLanded(fish: FishingRules.FishData, serial: number, world: Vector3?)
	if serial ~= catchSerial then
		return
	end
	local style = UIConfig.Rarity[fish.Rarity] or UIConfig.Rarity.Common
	local reveal = REVEAL[fish.Rarity] or REVEAL.Common
	local point = screenPoint(world or headPoint())
	-- Плашки статуса гаснут: дальше главная — карточка (на телефоне она встаёт на их место).
	fadeGroup(ui.status, 1, STATUS_FADE)
	local rootSize = ui.fishing.AbsoluteSize
	local origin = if point
		then Vector2.new(point.X / math.max(rootSize.X, 1), point.Y / math.max(rootSize.Y, 1))
		else Vector2.new(0.45, 0.32)

	if reveal.Flash then
		-- Вспышка гаснет до появления карточки (затемнение и вспышка вместе — лишняя заливка).
		UiFx.flash(ui.hud, reveal.Flash, math.max(reveal.Hold - 0.1, 0.2), reveal.FlashFrom, 0.05)
	end
	if reveal.Shake then
		UiFx.cameraShake(0.35, 0.4)
	end
	if reveal.Fov ~= 0 then
		UiFx.fovPunch(reveal.Fov)
	end
	if reveal.Confetti > 0 then
		celebrationTrove:Add(UiFx.confetti(ui.hud, {
			count = reveal.Confetti,
			colors = style.Confetti,
			origin = origin,
			spread = 150,
			power = 1.05,
		}))
		if fish.Rarity == "Mythic" and reveal.Confetti2 > 0 then
			later(celebrationTrove, 0.6, function()
				celebrationTrove:Add(UiFx.confetti(ui.hud, {
					count = reveal.Confetti2,
					colors = style.Confetti,
					origin = Vector2.new(0.5, 0.2),
					spread = 170,
					power = 0.9,
				}))
			end)
		end
	end
	UiFx.sound("pop", 0.5, if reveal.Flash then 0.8 else 1)
	if reveal.Flash then
		UiFx.sound("swoosh", 0.5, 0.7)
	end
	if reveal.Title then
		later(catchTrove, 0.1, function()
			slamTitle(fish.Rarity, reveal, style)
		end)
	end
	later(catchTrove, reveal.Hold, function()
		openCard(fish, point)
	end)
end

-- Начало улова (сразу после "Caught"): кнопка замирает, счётчик держит число, напряжение
-- нарастает, ждём приземления рыбы.
local function beginCatch(fish: FishingRules.FishData, total: number)
	catchTrove:Clean()
	celebrationTrove:Clean()
	if ui.card.Visible then
		closeCard() -- прошлая карточка ещё открыта (редко): уходит сразу
	end
	catchSerial += 1
	local serial = catchSerial
	catchScreen = true
	holdCounter(serial, total)
	refreshButtons()
	fadeGroup(ui.actionButton, BUTTON_FADE, 0.2)
	refreshContextHint()

	local style = UIConfig.Rarity[fish.Rarity] or UIConfig.Rarity.Common
	local reveal = REVEAL[fish.Rarity] or REVEAL.Common
	if reveal.Tension then
		later(catchTrove, 0.3, function()
			local colors = if style.Rainbow
				then { UIConfig.Rainbow[7], UIConfig.Rainbow[1] }
				else { style.Bottom, style.Top }
			local stop = UiFx.edgeVignette(ui.hud, colors, 0.55, nil, { fadeIn = 0.5 })
			catchTrove:Add(function()
				stop(0.2)
			end)
		end)
	end
	if reveal.Heartbeat then
		for _, at in { 0.3, 0.48 } do
			later(catchTrove, at, function()
				UiFx.sound("splash", 0.5, 0.5)
			end)
		end
	end

	-- Приземление: сигнал FishingFxController (или он уже был — прыжка нет), иначе — сами.
	local done = false
	local function landed(world: Vector3?)
		if done then
			return
		end
		done = true
		landingWaiter = nil
		catchTrove:Clean() -- виньетка и «сердце» кончаются, ожидание тоже
		onLanded(fish, serial, world)
	end
	local early = lastLanding
	lastLanding = nil
	if early and os.clock() - early.at <= LANDING_MEMORY then
		landed(early.position)
	else
		landingWaiter = landed
		later(catchTrove, CATCH_FALLBACK, function()
			landed(nil)
		end)
	end
	-- Подстраховка: что бы ни случилось, кнопка и счётчик не останутся «замороженными».
	task.delay(CATCH_FAILSAFE, function()
		if serial == catchSerial and catchScreen and not ui.card.Visible then
			finishCatch(serial, false)
		end
	end)
end

-- FishingFxController.OwnFishLanded: своя рыба долетела (может прийти раньше "Caught").
local function onOwnFishLanded(_rarity: string, position: Vector3)
	local waiter = landingWaiter
	if waiter then
		waiter(position)
	else
		lastLanding = { at = os.clock(), position = position }
	end
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

-- Тап по карточке улова / действие, пока улов на экране: пропустить доли или закрыть (tapCard).
local function tryCloseCard()
	tapCard()
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
	if catchScreen then
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

-- Поймал: мини-игра «побеждает», потом прыжок рыбы и карточка (beginCatch). Счётчик улова
-- ведёт HudController; пока 🐟 не прилетела, он держит прошлое число (CounterHold).
local function onCaught(data: { [string]: any })
	local fish = parseFish(data.Fish)
	if fish then
		winGhost(fish.Rarity)
	end
	if fish then
		catchScreen = true -- кнопка сразу «замирает» (без промежуточного «ЖДЁМ…» с выскоком)
	end
	endSessionByServer()
	if fish then
		beginCatch(fish, number(data.Total, 0))
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

		-- Улов, UI v2 (FUI-01…12).
		fishing = fishing,
		status = child(hud, "Status"),
		tapHint = child(card, "TapHint"),
		cardOutline = child(card, "Lip"):FindFirstChildOfClass("UIStroke") :: UIStroke,
		priceMult = child(price, "Multiplier"),
		titleSlam = child(fishing, "TitleSlam"),
		titleLabel = child(child(fishing, "TitleSlam"), "Label"),
		titleSlamFill = child(child(child(fishing, "TitleSlam"), "Label"), "TextFill"),
		titleLetters = child(child(fishing, "TitleSlam"), "Letters"),
		dimBands = {
			child(child(fishing, "CatchDim"), "Top"),
			child(child(fishing, "CatchDim"), "Bottom"),
			child(child(fishing, "CatchDim"), "Left"),
			child(child(fishing, "CatchDim"), "Right"),
		},
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
	-- Улов (UI v2): своя рыба долетела до места над головой — сигнал FishingFxController
	-- (подписка заранее: без прыжка он приходит раньше "Caught"). Подпись «закрыть» — по
	-- устройству; карточка переставляется, если экран поменял размер.
	local fx = require(script.Parent:WaitForChild("FishingFxController")) :: any
	fx.OwnFishLanded:Connect(onOwnFishLanded)
	ui.tapHint.Text = if UserInputService.TouchEnabled
		then "Тапни, чтобы закрыть"
		else "Жми, чтобы закрыть"
	ui.titleSlam.Visible = false
	ui.minigame:GetPropertyChangedSignal("Visible"):Connect(function()
		if ui.minigame.Visible then
			minigameShownAt = os.clock()
		end
	end)
	ui.fishing:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if ui.card.Visible then
			placeCard(cardReveal.Scale)
		end
	end)

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(onCharacterRemoving)
	if player.Character then
		onCharacterAdded(player.Character)
	end
	refreshButtons()
end

return FishingController
