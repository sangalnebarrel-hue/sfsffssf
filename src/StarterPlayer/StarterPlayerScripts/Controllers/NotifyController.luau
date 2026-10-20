--!strict
--[[
	NotifyController — всплывающие уведомления (HUD.Toasts) в стиле «Симулятор» (UI v5: сочные
	плашки цвета вида с толстой обводкой в тёмный оттенок цвета, эмодзи с тёмным контуром на левом
	краю, белый текст с обводкой; tools/builder/gui/STYLE.md; анимации — ReplicatedStorage.Shared.UiFx).

	Источники:
	  • сервер: RemoteEvent "Notify" (text, kind);
	  • другие контроллеры: NotifyController.Show(text, kind?, look?).
	kind — вид из UIConfig.ToastKinds: "info" | "success" | "warning" | "danger" (Sky 💬 / Leaf 🎉 /
	Sun ⚠️ / Berry 🚨), "base" (цвета своей базы, 🚩 — look.swatch передаёт HudController),
	"Legendary" (золотая плашка с 🌟) и "Mythic" (тёмная плашка в радужной обводке, 🌈) — громкие
	новости о редком улове: крупнее и дольше (4.5 с), со звёздочками, в две строки, влетают
	«ударом» с перелётом, от них расходится кольцо цвета редкости, строка «что» вспыхивает
	золотом. Сервер присылает их одной строкой «Кто: что поймал» (FishingService) — здесь она
	делится по первому ": ": сверху кто (Byline, не мельче BYLINE_MIN px), снизу крупно что
	(Label: первое слово — редкость — заглавными; белые буквы с толстой обводкой, у легендарной
	снизу в золото). Радуга мифической — только по обводке (она вращается): на тёмной плашке
	белые буквы читаются; уведомление не шире колонки (на тач-экране — 1.25 колонки), длинная
	строка «что» на тач-экране сначала мельчает (до 12 px), переносится, только если не влезает и
	так (ширина — по буквам, UiFx.textWidth): плашка не ложится на голову персонажа; на телефоне,
	если и так две строки дошли бы до макушки своего рыбака (его видно под колонкой), — одна строка
	«Кто: ЧТО» над ней, не мельче BIG_ONE_LINE px (Этап 4 wave 3, ART-08: «Украдено / ФУГУ (Ника)»
	ложилось на макушку). Чужой
	улов не красит экран (никаких радужных краёв: новичок не подумает, что это он поймал).
	Неизвестный вид — как "info".
	look = { swatch = {Top, Bottom, Lip}?, icon = "🚩"? } заменяет цвет и значок вида.

	Каждое уведомление — копия HUD.Toasts.ToastTemplate (имя "Toast"), ширина — по длине текста
	(текст по шкале UiFx.fitText: Body); длинный текст — в две строки. Если уведомлений
	несколько, все тянутся до ширины самого широкого (значки встают в столбик). Колонку
	раскладывает этот модуль (без UIListLayout): новое уведомление съезжает сверху в свой слот с
	пружинкой (ENTER_DROP высоты колонки — но не выше её свободного верха: плашки статуса над
	колонкой и полосы тревоги оно не пересекает, Этап 4 C-31; у верхнего слота — только пружина
	масштаба), значок «вкручивается» (−180° → 0), когда плашка села (у предупреждения и громких —
	потом ещё качается), по плашке пробегает блик, у громких вспыхивает ободок; «успех» и
	громкие — со звёздочками по бокам плашки (не на буквах), «опасность» — встряхивается.
	Соседи съезжают на новые места с лёгким перелётом (Back Out). Без тач-экрана колонка (по центру) сужается так,
	чтобы не задевать окно чата Roblox слева вверху (CHAT_RIGHT, CHAT_GAP), и при смене размера окна.

	Сколько видно сразу: UIConfig.MaxToasts на компьютере, MaxToastsTouch на планшете,
	MaxToastsPhone на телефоне (HUD ниже PHONE_HEIGHT px: второе легло бы на голову персонажа); на
	планшете и компьютере стопка ещё и кончается не ниже FISHER_GAP над своим рыбаком, если его видно
	под колонкой (первое уведомление — всегда; остальные ждут своей очереди: Этап 4 wave 3, UX-06 —
	после кражи «Украдено», отдых садка и совет ложились втроём на его голову и грудь).
	Пока улов на экране (у HUD атрибут CounterHold — от "Caught" до прилёта 🐟 в счётчик — или
	видна HUD.Fishing.CatchCard) — ни одного; на телефоне ни одного (кроме «опасности») и пока
	своя рыба над головой (HeldFish в своём персонаже, v3: трофей не под уведомлением); пока мини-игра или «КЛЮЁТ!» (Minigame / BiteAlert)
	— одно, а на телефоне ни одного, кроме «опасности»; пока доигрывает копия мини-игры
	(FxMinigameWin / FxMinigameMiss: «ПОЙМАНА!», «МИМО!») или над панелью поднимается слово
	попадания (Minigame.FxFloat) — ни одного, кроме «опасности», на любом экране: эти слова
	поднимаются в колонку уведомлений, а уведомление, которое не прочесть, зря тратит свой срок.
	Остальные ждут в очереди и выходят, когда место освободится; уведомление, которое такой
	виджет согнал с экрана в первой половине срока, встаёт в начало очереди (согнанное полосой и
	прождавшее дольше своего срока — уже несвежее: не показываем; UX-05 — «Щит погас» мигал 8 с
	спустя, перед «Украдено»); провисевшее UIConfig.ToastSeen с — уже прочитано: полоса сгоняет
	его насовсем (сервер прислал одно «Щит погас», а ребёнок видел его дважды — до тревоги и
	после неё). Когда места нет,
	уходит самое старое из самых неважных (Priority вида; «опасность» вытесняет обычные); если
	все на экране важнее нового — новое ждёт в очереди.
	Уход: через Life (или UIConfig.ToastDuration) секунд уведомление поднимается на LEAVE_RISE px
	(не выше свободного верха колонки: верхнее не заезжает на плашки статуса), чуть
	поворачивается (+4°) и тает (имя "ToastLeaving"), остальные через 0.12 с съезжают вверх; уходят не чаще, чем раз в
	UIConfig.ToastGap секунд.

	Только твины и таймеры: ни одного покадрового соединения на уведомление.

	Место сверху колонки (Этап 4): NotifyController.Reserve(key, px) — виджет, который стоит в
	слоте уведомлений (полоса вора "theft" — TheftController, плашка тревоги "alert" —
	AlertController), занимает px сверху колонки — до своего нарисованного низа (с обводкой);
	уведомления едут ниже (каждой полосе — ещё зазор NotifyController.BandGap(): GAP колонки, но не
	меньше BAND_GAP — 16 px и обводка уведомления); px = 0 или nil — место освобождено, ждущие
	выходят. Полосы стоят друг под другом в порядке RESERVE_ORDER («theft», потом «alert»;
	незнакомые — следом, по имени, как «thief» вора, что держит всю колонку):
	NotifyController.Offset(key) — сколько px от верха колонки до полосы key (виджет ставит себя
	туда; полосы key ещё нет — где она встанет по этому порядку: тревога хозяина, которого
	обворовывают, пока он крадёт сам, — вверху, а не под всей колонкой вора, Stage 4 wave 3).
	Пока полосы стоят, уведомление под ними кончается не
	ниже FISHER_GAP px над своим рыбаком (FishingLayout.fisherBox; на телефоне не вышло — где он у
	камеры по умолчанию) и не ближе 16 px к кнопкам рыбалки под колонкой: полоса толкает
	уведомления вниз — на планшете и компьютере под плашкой тревоги места до головы нет, и
	уведомления (любые, и «опасность») ждут в очереди, пока плашка не уйдёт (тревога — секунды);
	не помещается то, что уже на экране, — снова в очередь. NotifyController.Reserved() — сколько
	px занято (тесты).
	Look (третий аргумент Show): tag — метка (NotifyController.Drop(tag) убирает такие с экрана и
	из очереди: тревога убирает «👀 Ника у тебя во дворе!» того же вора); afterSheet — ждёт, пока
	открыт лист (атрибут HUD Sheet: легло бы на шапку листа с его кошельком; открылся лист — такое
	уведомление уходит с экрана, в первой половине срока — снова в очередь); live — функция:
	текст в миг показа (таймер ждавшего уведомления — на сейчас; nil — уже нечего сказать);
	clock — серверное время, к которому идёт таймер в тексте live: пока уведомление на экране,
	live перечитывается на каждой целой секунде до clock (цепочка task.delay в его Trove, как у
	фишки щита — одни часы: «Садок отдыхает 1:25» рядом с «🛡️ 1:25», last-mile F-12; кончилось —
	последний текст до ухода; без покадровой работы).

	Чужой легендарный / мифический улов (FishingFxController.OtherTrophy), чей столб света сейчас
	не на экране (за спиной или за краем кадра): у края экрана с его стороны — маленький значок
	(копия HUD.TrophyPointer, «TrophyChip»: 🌟 на золотой / 🌈 на радужной круглой кнопке в кольце
	цвета базы рыбака, острый край «тычет» к краю экрана), пока столб горит (FishingConfig.Fx.
	PillarTimeOther); столб попал в кадр — значка нет. На телефоне — не во время своей поклёвки,
	мини-игры и улова (то же правило, что у уведомлений). Пока есть хоть один значок — один
	покадровый эффект планировщика UiFx (где столб относительно камеры); нет значков — ничего.
	Этап 4: в колонке справа три кнопки («ЗАЩИТА» над «САДОК» и «ДОМОЙ») — над ней места для
	значка нет (телефоны, планшет): значок с правой стороны встаёт СЛЕВА от колонки (острый край —
	в POINTER.SideGap px от кнопок) на самом нижнем свободном месте этой полосы — от низа колонки
	(на тач-экране — над кнопкой прыжка) вверх шагами POINTER.Step: ≥ 16 px (и POINTER.Ink на
	обводки) от кнопок рыбалки (HUD.Fishing.ActionArea: «ЗАБРОСИТЬ», «СМОТАТЬ» с подписями — там
	правый большой палец), видимых уведомлений, плашки тревоги, плашек статуса (с фишкой щита и
	цифрами кошелька) и прочих значков; свободного места нет — значок спрятан, пока не появится
	(рука ребёнка важнее подсказки, где чужой улов); места над колонкой хватает (компьютер) — как
	раньше.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local UIConfig = require(Shared:WaitForChild("Config"):WaitForChild("UIConfig"))
local FishingConfig = require(Shared:WaitForChild("Config"):WaitForChild("FishingConfig"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local FishingLayout = require(script.Parent:WaitForChild("FishingLayout"))

type Swatch = UIConfig.Swatch
type ToastKind = UIConfig.ToastKind

export type Look = {
	swatch: Swatch?, -- цвет «конфеты» вместо цвета вида
	icon: string?, -- значок вместо значка вида
	tag: string?, -- метка: NotifyController.Drop(tag) уберёт с экрана и из очереди
	afterSheet: boolean?, -- ждёт, пока открыт лист (легло бы на его шапку с кошельком)
	live: (() -> string?)?, -- текст — в миг показа (ждавшее не врёт о таймере); nil — не показывать
	clock: number?, -- серверное время конца таймера в тексте live: на экране — каждую целую секунду
}

-- requeued — os.clock(), когда полоса согнала его с экрана в первой половине срока (снова в
-- очереди): прождал дольше своего срока — уже несвежее, не показываем (Wave 3 UX-05).
type Pending = { text: string, kind: string, look: Look?, requeued: number? }

type Toast = {
	frame: Frame,
	priority: number,
	height: number, -- высота, доля колонки
	natural: number, -- своя ширина по тексту, доля колонки
	trove: Trove.Trove, -- его эффекты и таймеры
	entering: boolean, -- ещё въезжает (позицию ведёт твин въезда)
	item: Pending, -- что показано (виджет рыбалки согнал — можно показать снова)
	shownAt: number, -- os.clock() появления
	life: number, -- срок, с
}

local SLOT = 0.28 -- высота уведомления, доля высоты колонки
local GAP = 0.08 -- зазор между уведомлениями
local BIG = 1.2 -- громкие уведомления выше во столько раз
local TWO_LINES = 1.6 -- … и длинные (в две строки)
local ENTER_TIME = 0.45
local ENTER_DROP = 0.3 -- въезд сверху: столько высоты колонки над слотом (не выше её свободного верха)
local LEAVE_TIME = 0.2
local LEAVE_RISE = 20 -- уход вверх, px (не выше свободного верха колонки)
local REFLOW_DELAY = 0.12
local LABEL_SHARE = 0.8 -- ширина надписи, доля уведомления (Hud.luau: LabelProps)
local MIN_WIDTH = 0.42
local MAX_QUEUE = 4
local BUSY_WIDGETS = { "Minigame", "BiteAlert" } -- + CatchCard (её — отдельно: при ней ни одного)
local PHONE_HEIGHT = 500 -- HUD ниже — телефон (одно уведомление; при виджетах рыбалки — ни одного)
local URGENT = 3 -- приоритет «опасности»: на телефоне выходит и при мини-игре
-- Без тач-экрана слева вверху окно чата Roblox (правый край ≈ CHAT_RIGHT px от края экрана):
-- колонка по центру не доходит до него на CHAT_GAP px (с запасом на значок громкого
-- уведомления, он выступает влево), но не уже COLUMN_MIN px.
local CHAT_RIGHT = 368
local CHAT_GAP = 76
local COLUMN_MIN = 320
-- Громкие (две строки): строка «кто» — уровня Small, «что» — до Title (не мельче Body, иначе
-- переносится). На тач-экране такое уведомление может быть шире колонки (до BIG_WIDE_TOUCH её
-- ширины, по центру — до кнопки «Домой» не достаёт): «что» помещается одной строкой хотя бы
-- уровня Body, и плашка ниже — не ложится на голову персонажа (SIM-C1-02).
local BIG_WIDE_TOUCH = 1.25
local BYLINE_MIN = 14 -- «кто» не мельче стольких px (v3, UIM-06)
local BIG_ONE_LINE = 12 -- «что» на тач-экране сжимается до стольких px, прежде чем переноситься
local BIG_OUTLINE = 4 -- обводка букв громкого уведомления (при 720 px; на телефоне ≈ 2.6 px)
local RIM_THICK = 1.4 -- радужная обводка мифической толще обычной во столько раз
local BIG_PAD = 0.9 -- доля высоты плашки под строки (остальное — поля)
local BIG_LINE = 1.22 -- высота строки в размерах её текста
-- Значок чужого улова вне экрана (см. шапку): центр — на Y высоты HUD (справа — не ниже, чем Gap
-- над кнопками «ДОМОЙ»; следующий у того же края — выше на Stack своих высот), от края — Gap
-- px, «тычет» к краю на Bob px за Period с; смотрим на точку столба на Lift studs над землёй;
-- значков не больше Max (лишний уходит — самый старый). Над колонкой кнопок — ColumnGap px от
-- края кольца (толстая обводка и кольцо цвета базы выходят за значок; правило — ≥ 16 px).
-- Этап 4: три кнопки в колонке и над ней нет места — значок слева от колонки, SideGap px от кнопок
-- (ColumnGap и острый край с обводкой, они выступают за «reach»), на самом нижнем свободном месте:
-- от низа колонки (на тач-экране — кольцо (Ring его размера от центра) JumpGap px над кнопкой
-- прыжка; SmallTouch — маленькая кнопка) вверх шагами Step px, не выше Top px от верха HUD; до
-- соседей — 16 px и Ink на обводки.
local POINTER = {
	Y = 0.38,
	Stack = 1.35,
	Gap = 16,
	ColumnGap = 20,
	Bob = 6,
	Period = 0.8,
	Lift = 40,
	Max = 3,
	SideGap = 28,
	JumpGap = 17,
	Ring = 0.71,
	SmallTouch = 500,
	Step = 4,
	Ink = 6,
	Top = 8,
}
local MIN_GAP = 16 -- значок у колонки — до соседних виджетов (правило 16 px), px
-- Полосы сверху колонки (Reserve): уведомление под полосой — не ближе BAND_GAP px к её нарисованному
-- низу (16 px правила и TOAST_INK — обводка и значок уведомления над его коробкой); пока полосы
-- стоят, уведомление кончается не ниже FISHER_GAP px над своим рыбаком (FishingLayout.fisherBox —
-- уже с запасом FISHER_PAD) и 16 px + AREA_INK (обводки, подписи) над кнопками рыбалки
-- (HUD.Fishing.ActionArea), если они под колонкой: полоса толкает уведомления вниз, на голову.
local TOAST_INK = 8
local BAND_GAP = MIN_GAP + TOAST_INK
local FISHER_GAP = 16
local AREA_INK = 6 + TOAST_INK

local NotifyController = {}

local container: Frame? = nil
local template: Frame? = nil
local active: { Toast } = {}
local queue: { Pending } = {}
local busyWidgets: { GuiObject } = {}
local cardWidget: GuiObject? = nil
local ghosts = 0 -- копий мини-игры (FxMinigameWin / FxMinigameMiss) на экране
local words = 0 -- слов попадания над панелью мини-игры (Minigame.FxFloat) на экране
local counter = 0
local lastDismiss = -math.huge

local function busy(): boolean
	if ghosts > 0 or words > 0 then
		return true -- мини-игра закрылась, но её копия ещё доигрывает «ПОЙМАНА!» / «МИМО!»
	end
	for _, widget in busyWidgets do
		if widget.Visible then
			return true
		end
	end
	return false
end

-- v3: своя рыба над головой (HeldFish в своём персонаже) — на телефоне уведомление легло бы
-- поверх трофея (колонка уведомлений — над головой персонажа).
local trophyHeld = false

local function isPhone(): boolean
	local hud = container and container.Parent
	return UserInputService.TouchEnabled
		and hud ~= nil
		and hud:IsA("GuiBase2d")
		and hud.AbsoluteSize.Y > 1
		and hud.AbsoluteSize.Y < PHONE_HEIGHT
end

-- Этап 4: место сверху колонки под полосы (Reserve): px по ключу; порядок полос — RESERVE_ORDER.
local RESERVE_ORDER = { "theft", "alert" }
local reserved: { [string]: number } = {}

local function columnHeight(): number
	local column = container
	return if column then column.AbsoluteSize.Y else 0
end

-- Ключи полос сверху вниз: сначала RESERVE_ORDER, потом незнакомые по имени; with — ещё и этот
-- ключ на своём месте в порядке (полосы ещё нет: где она встанет).
local function reserveKeys(with: string?): { string }
	local keys = {}
	for _, key in RESERVE_ORDER do
		if reserved[key] or key == with then
			table.insert(keys, key)
		end
	end
	local others = {}
	for key in reserved do
		if not table.find(RESERVE_ORDER, key) then
			table.insert(others, key)
		end
	end
	if with and not reserved[with] and not table.find(RESERVE_ORDER, with) then
		table.insert(others, with)
	end
	table.sort(others)
	for _, key in others do
		table.insert(keys, key)
	end
	return keys
end

-- Зазор под полосой, px: GAP колонки, но не меньше BAND_GAP.
local function bandGapPx(height: number): number
	return math.max(GAP * height, BAND_GAP)
end

-- Доля высоты колонки, занятая полосами (у каждой — ещё зазор bandGapPx).
local function reservedShare(): number
	local height = columnHeight()
	if height <= 1 or next(reserved) == nil then
		return 0
	end
	local share = 0
	for _, px in reserved do
		share += (px + bandGapPx(height)) / height
	end
	return share
end

-- Докуда (доля колонки от её верха) могут доходить уведомления — над своим рыбаком (fallback:
-- на телефоне не вышло спроецировать — где он у камеры по умолчанию) и над кнопками рыбалки,
-- если они под колонкой; nil — без предела (рыбака не видно).
local function fisherLimit(fallback: boolean): number?
	local column = container
	local hud = column and column.Parent
	if not column or not hud or not hud:IsA("GuiBase2d") then
		return nil
	end
	local height = column.AbsoluteSize.Y
	if height <= 1 then
		return nil
	end
	local origin = hud.AbsolutePosition
	local x0 = column.AbsolutePosition.X - origin.X
	local x1 = x0 + column.AbsoluteSize.X
	local top = column.AbsolutePosition.Y - origin.Y
	local limit: number? = nil
	local function cap(y: number, x0b: number, x1b: number)
		if x1b > x0 and x0b < x1 then
			local share = (y - top) / height
			limit = if limit then math.min(limit, share) else share
		end
	end
	local player = Players.LocalPlayer
	local fisher = FishingLayout.fisherBox(if player then player.Character else nil, Workspace.CurrentCamera, origin)
		or (if fallback and isPhone() then FishingLayout.fallbackFisher(hud.AbsoluteSize) else nil)
	if fisher then
		cap(fisher.y0 - FISHER_GAP, fisher.x0, fisher.x1)
	end
	local fishing = hud:FindFirstChild("Fishing")
	local area = if fishing
			and fishing:IsA("GuiObject")
			and fishing.Visible
		then fishing:FindFirstChild("ActionArea")
		else nil
	if area and area:IsA("GuiObject") and area.Visible then
		for _, button in area:GetChildren() do
			if button:IsA("GuiObject") and button.Visible and button.AbsoluteSize.Y > 0 then
				local at = button.AbsolutePosition - origin
				cap(at.Y - MIN_GAP - AREA_INK, at.X, at.X + button.AbsoluteSize.X)
			end
		end
	end
	return limit
end

-- Предел низа уведомлений (доля колонки), nil — без предела. Пока стоят полосы — над рыбаком и
-- кнопками рыбалки всегда (на телефоне — и где рыбак у камеры по умолчанию). Без полос — на
-- планшете и компьютере тоже над своим рыбаком, если его видно (Wave 3 UX-06: на компьютере
-- три уведомления после кражи — «Украдено», отдых садка, совет — ложились ему на голову и
-- грудь); первое уведомление выходит всегда (см. canShow), остальные ждут. На телефоне без полос
-- — одно уведомление, предела нет.
local function stackLimit(): number?
	if next(reserved) ~= nil then
		return fisherLimit(true)
	end
	if isPhone() then
		return nil
	end
	return fisherLimit(false)
end

-- Сколько уведомлений обычной высоты помещается под полосами и над рыбаком (без предела — сколько
-- угодно; без полос — хотя бы одно).
local function roomBelowReserve(): number
	local banded = next(reserved) ~= nil
	local limit = stackLimit()
	if not banded and not limit then
		return math.huge
	end
	local bottom = 1
	if limit then
		bottom = math.min(bottom, limit)
	end
	local free = bottom - reservedShare()
	local room = math.max(0, math.floor((free + GAP) / (SLOT + GAP) + 1e-6))
	return if banded then room else math.max(room, 1)
end

-- Сколько уведомлений приоритета priority может быть на экране, если полос сверху нет.
local function baseCapacity(priority: number?): number
	local hud = container and container.Parent
	if (cardWidget and cardWidget.Visible) or (hud and hud:GetAttribute("CounterHold") ~= nil) then
		return 0 -- улов на экране: от "Caught" (прыжок, карточка) до прилёта 🐟 в счётчик
	end
	local phone = isPhone()
	if phone and trophyHeld and (priority or 1) < URGENT then
		return 0 -- своя рыба над головой: уведомления ждут, пока трофей не уйдёт
	end
	if busy() then
		-- «МИМО!», «ПОЙМАНА!» и слова попаданий поднимаются в колонку: пока они на экране — ни одного.
		local covered = phone or ghosts > 0 or words > 0
		return if covered and (priority or 1) < URGENT then 0 else 1
	end
	if not UserInputService.TouchEnabled then
		return UIConfig.MaxToasts
	end
	return if phone then UIConfig.MaxToastsPhone else UIConfig.MaxToastsTouch
end

-- Сколько уведомлений приоритета priority может быть на экране сейчас (см. шапку).
local function capacity(priority: number?): number
	return math.min(baseCapacity(priority), roomBelowReserve())
end

local function styleOf(kind: string): ToastKind
	return UIConfig.ToastKinds[kind] or UIConfig.ToastKinds.info
end

local function slotPosition(index: number): UDim2
	local y = reservedShare()
	for i = 1, index - 1 do
		local toast = active[i]
		y += (if toast then toast.height else SLOT) + GAP
	end
	return UDim2.fromScale(0.5, y)
end

-- Все видимые уведомления едут к своим слотам и тянутся до ширины самого широкого.
-- Позицию въезжающего не трогаем (иначе пропадёт пружинка въезда): он сам доедет и позовёт reflow.
local function reflow()
	local widest = 0
	for _, toast in active do
		widest = math.max(widest, toast.natural)
	end
	for index, toast in active do
		local width = if #active >= 2 then widest else toast.natural
		local quad, out = Enum.EasingStyle.Quad, Enum.EasingDirection.Out
		UiFx.tween(toast.frame, 0.28, { Size = UDim2.fromScale(width, toast.height) }, quad, out)
		if not toast.entering and toast.frame.Position ~= slotPosition(index) then
			-- Соседи съезжают на новое место с лёгким перелётом (Back Out): плашки пружинят.
			UiFx.tween(toast.frame, 0.3, { Position = slotPosition(index) }, Enum.EasingStyle.Back, out)
		end
	end
end

local present: (item: Pending) -> ()
local canShow: (item: Pending, count: number) -> boolean

-- Выпустить ждущих, пока есть место (с маленьким шагом, чтобы не въезжали разом); первым —
-- первый, кому сейчас можно (на телефоне при мини-игре — только «опасность»; при открытом листе —
-- не те, что ждут его ухода).
local function drain()
	local started = 0
	local now = os.clock()
	for index = #queue, 1, -1 do
		local item = queue[index]
		local requeued = item.requeued
		if requeued and now - requeued > (styleOf(item.kind).Life or UIConfig.ToastDuration) then
			table.remove(queue, index) -- (согнанное полосой и прождавшее дольше своего срока — несвежее)
		end
	end
	while true do
		local found: number? = nil
		for index, item in queue do
			if canShow(item, #active + started) then
				found = index
				break
			end
		end
		if not found then
			return
		end
		local item = table.remove(queue, found) :: Pending
		if started == 0 then
			present(item)
		else
			task.delay(0.15 * started, present, item)
		end
		started += 1
	end
end

local function dismiss(toast: Toast, quick: boolean?)
	local index = table.find(active, toast)
	if not index then
		return -- уже уходит
	end
	table.remove(active, index)
	toast.trove:Clean()
	local frame = toast.frame
	frame.Name = "ToastLeaving"
	frame.ZIndex = math.max(frame.ZIndex - 1, 0) -- остальные проезжают поверх
	local time = if quick then 0.15 else LEAVE_TIME
	-- Уходит вверх на LEAVE_RISE px с лёгким поворотом (+4°), сжимается и тает (Quad In); вверх — не
	-- выше свободного верха колонки (верхнее не заезжает на плашки статуса, C-31).
	local quad, inDir = Enum.EasingStyle.Quad, Enum.EasingDirection.In
	local column = container
	local columnHeight = if column then column.AbsoluteSize.Y else 0
	local room = math.max(0, frame.Position.Y.Scale - reservedShare()) * columnHeight
	-- (колонка ещё не разложена — высота 0, доля слота не число: не двигаем, px — целые)
	local rise = if room == room and room < math.huge then math.round(math.min(LEAVE_RISE, room)) else 0
	UiFx.tween(frame, time, { Position = frame.Position - UDim2.fromOffset(0, rise), Rotation = 4 }, quad, inDir)
	UiFx.tween(UiFx.scaleOf(frame), time, { Scale = 0.92 }, quad, inDir)
	UiFx.fadeOut(frame, time)
	task.delay(time + 0.02, function()
		frame:Destroy()
	end)
	task.delay(REFLOW_DELAY, function()
		reflow()
		drain()
	end)
end

-- Срок вышел: уходит, но не раньше чем через UIConfig.ToastGap после предыдущего ухода.
local function expire(toast: Toast)
	if not table.find(active, toast) then
		return
	end
	local now = os.clock()
	local wait = lastDismiss + UIConfig.ToastGap - now
	if wait > 0 then
		toast.trove:Add(task.delay(wait, expire, toast))
		return
	end
	lastDismiss = now
	dismiss(toast)
end

-- Кого вытеснить ради уведомления с приоритетом priority: самое старое из самых неважных.
local function victimFor(priority: number, strict: boolean): Toast?
	local chosen: Toast? = nil
	for _, toast in active do
		local fits = if strict then toast.priority < priority else toast.priority <= priority
		if fits and (chosen == nil or toast.priority < chosen.priority) then
			chosen = toast
		end
	end
	return chosen
end

-- Сколько текста влезает: ширина уведомления под надпись (доля колонки) и нужна ли вторая строка.
local function measure(text: string, tier: string): (number, boolean)
	local column = container
	local columnWidth = if column then column.AbsoluteSize.X else 0
	if columnWidth <= 1 then
		local length = utf8.len(text) or #text
		return math.clamp(0.34 + length * 0.021, 0.56, 1), false -- раскладки ещё нет
	end
	-- Ширина по буквам (UiFx.textWidth: заглавные шире строчных — SIM-C1-02).
	local textWidth = UiFx.textWidth(text, UiFx.textSize(tier))
	local share = textWidth / (LABEL_SHARE * 0.94) / columnWidth
	if share <= 1 then
		return math.max(share, MIN_WIDTH), false
	end
	return 1, true
end

type BigLayout = {
	natural: number, -- ширина, доля колонки
	height: number, -- высота, доля колонки
	byline: string?, -- кто (мелко сверху)
	headline: string, -- что (крупно; первое слово заглавными)
	lines: number, -- строк у «что» (1 или 2)
	head: number, -- размер текста «что», px
}

-- Сколько px от верха первого слота колонки (под полосами) до его макушки (fisherBox без своего
-- запаса FISHER_PAD) за вычетом TOAST_INK — обводки и кольца уведомления, если рыбака видно под
-- колонкой (только настоящий, не «где у камеры по умолчанию»); nil — не видно. (На телефоне от
-- верха колонки до макушки ≈ 32 px: полные FISHER_GAP над запасом не оставили бы места и одной
-- строке не мельче 12 px.)
local function roomAboveFisher(): number?
	local column = container
	local hud = column and column.Parent
	if not column or not hud or not hud:IsA("GuiBase2d") or column.AbsoluteSize.Y <= 1 then
		return nil
	end
	local player = Players.LocalPlayer
	local origin = hud.AbsolutePosition
	local fisher = FishingLayout.fisherBox(if player then player.Character else nil, Workspace.CurrentCamera, origin)
	local x0 = column.AbsolutePosition.X - origin.X
	if not fisher or fisher.x1 <= x0 or fisher.x0 >= x0 + column.AbsoluteSize.X then
		return nil
	end
	local top = column.AbsolutePosition.Y - origin.Y + reservedShare() * column.AbsoluteSize.Y
	return math.max(0, fisher.y0 + FishingLayout.FISHER_PAD - TOAST_INK - top)
end

-- Размеры текста громкого уведомления, px: «кто», нижний предел «что», «что». На телефоне «что» —
-- Title − 2 (нижний предел Title): так обе строки помещаются над головой персонажа.
local function bigSizes(): (number, number, number)
	local title = UiFx.textSize("Title")
	return UiFx.textSize("Small"), UiFx.textSize("Body"), if isPhone() then title - 2 else title
end

-- Громкое уведомление «Кто: что поймал» — две строки (см. шапку): размеры по тексту.
local function bigLayout(text: string): BigLayout
	local cut = string.find(text, ": ", 1, true)
	local byline = if cut then string.sub(text, 1, cut - 1) else nil
	local rest = if cut then string.sub(text, cut + 2) else text
	local space = string.find(rest, " ", 1, true)
	local headline = if space
		then TextUtil.upper(string.sub(rest, 1, space - 1)) .. string.sub(rest, space)
		else TextUtil.upper(rest)
	local column = container
	local area = if column then column.AbsoluteSize else Vector2.zero
	local small, body, title = bigSizes()
	if area.X <= 1 or area.Y <= 1 then
		local height = SLOT * BIG * TWO_LINES
		return { natural = 1, height = height, byline = byline, headline = headline, lines = 1, head = title }
	end
	local touch = UserInputService.TouchEnabled
	local widest = if touch then BIG_WIDE_TOUCH else 1
	local room = widest * area.X * LABEL_SHARE * 0.94
	local function width(line: string?, px: number): number
		return if line then UiFx.textWidth(line, px) else 0
	end
	-- «Что» в одну строку; на тач-экране — мельче (до BIG_ONE_LINE px), но в одну: плашка в две
	-- строки на коротком экране ложится на голову персонажа (SIM-C1-02); не влезает и так — две
	-- строки уровня Body. Ширина — по буквам (UiFx.textWidth): «ЛЕГЕНДАРНАЯ рыба «Акулёнок»!» —
	-- заглавные только в первом слове (оценка «все заглавные» переносила её в три строки).
	local head, lines = title, 1
	if width(headline, title) > room then
		local fits = math.floor(room / math.max(width(headline, 1), 1))
		if touch and fits >= BIG_ONE_LINE then
			head = math.min(fits, title)
		else
			head, lines = if touch then body else title, 2
		end
	end
	local px = ((if byline then small else 0) + head * lines) * BIG_LINE / BIG_PAD
	-- Телефон: две строки «кто» + «что» доходят до головы своего рыбака (его видно под колонкой) —
	-- одна строка «Кто: ЧТО» (Wave 3 ART-08: «Украдено / ФУГУ (Ника)» ложилось на макушку), не
	-- выше места над ним и не мельче BIG_ONE_LINE px.
	local above = if byline and isPhone() then roomAboveFisher() else nil
	if above and px > above then
		local line = `{byline}: {headline}`
		local byWidth = math.floor(room / math.max(width(line, 1), 1))
		local byHeight = math.floor(above * BIG_PAD / BIG_LINE)
		byline, headline, lines = nil, line, 1
		head = math.max(math.min(title, byWidth, byHeight), BIG_ONE_LINE)
		px = head * BIG_LINE / BIG_PAD
	end
	local need = math.max(width(byline, small), width(headline, head) / lines)
	local natural = math.clamp(need / (LABEL_SHARE * 0.94) / area.X, MIN_WIDTH, widest)
	return {
		natural = natural,
		height = px / area.Y,
		byline = byline,
		headline = headline,
		lines = lines,
		head = head,
	}
end

-- Две строки громкого уведомления: Label — «что» (до Title, золотом / радугой), над ним
-- Byline — «кто» (Small). Доли — от высоты уведомления (строки занимают BIG_PAD её).
local function dressBig(frame: Frame, label: TextLabel, style: ToastKind, layout: BigLayout)
	local small, body = UiFx.textSize("Small"), UiFx.textSize("Body")
	local title = layout.head
	local total = (if layout.byline then small else 0) + title * layout.lines
	local top = (1 - BIG_PAD) / 2
	local bylineShare = if layout.byline then BIG_PAD * small / total else 0
	if layout.byline then
		local byline = label:Clone()
		byline.Name = "Byline"
		byline.Text = layout.byline
		byline.TextWrapped = false
		byline.AnchorPoint = Vector2.new(1, 0)
		byline.Position = UDim2.fromScale(label.Position.X.Scale, top)
		byline.Size = UDim2.fromScale(label.Size.X.Scale, bylineShare)
		-- Уровень Small, но не мельче BYLINE_MIN px (на телефоне Small — 14, его нижний предел был 12).
		byline:SetAttribute("TextTier", nil)
		local bylineFit = byline:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
		bylineFit.MinTextSize = 1
		bylineFit.MaxTextSize = math.max(small, BYLINE_MIN)
		bylineFit.MinTextSize = math.max(BYLINE_MIN, small - 2)
		bylineFit.Parent = byline
		byline.Parent = frame
	end
	label.Text = layout.headline
	label.TextScaled = true
	label.TextWrapped = layout.lines > 1
	label.AnchorPoint = Vector2.new(1, 0)
	label.Position = UDim2.fromScale(label.Position.X.Scale, top + bylineShare)
	label.Size = UDim2.fromScale(label.Size.X.Scale, BIG_PAD - bylineShare)
	label:SetAttribute("TextTier", nil) -- размер — по месту (Title … Body), не по шкале
	local fit = label:FindFirstChildOfClass("UITextSizeConstraint") or Instance.new("UITextSizeConstraint")
	fit.MaxTextSize = title
	-- Не мельче Body; «что», сжатое в одну строку мельче Body, — с запасом на ошибку оценки ширины
	-- по буквам, но не мельче BIG_ONE_LINE px.
	fit.MinTextSize = if title < body then math.max(title - 2, BIG_ONE_LINE) else body
	fit.Parent = label
	local outline = label:FindFirstChild("Outline")
	if outline and outline:IsA("UIStroke") then
		outline:SetAttribute("BaseThickness", BIG_OUTLINE)
		outline.Thickness = UiFx.strokeThickness(outline)
	end
	-- Значок — не выше плашки: громкая плашка в две строки выше обычной (значок растёт с ней).
	local socket = frame:FindFirstChild("IconSocket")
	if socket and socket:IsA("GuiObject") then
		socket.Size = UDim2.fromScale(socket.Size.X.Scale * 0.85, socket.Size.Y.Scale * 0.85)
	end
	-- Буквы: белые с толстой обводкой (у легендарной книзу светлое золото — на жёлтой плашке
	-- читается); у мифической — просто белые на тёмной плашке (радуга — на обводке).
	if not style.Rainbow then
		local gradient = Instance.new("UIGradient")
		gradient.Name = "TextFill"
		gradient.Color = UiFx.sequence({ UIConfig.White, UIConfig.White, UIConfig.Palette.Gold.Top })
		gradient.Rotation = 90
		gradient.Parent = label
	end
end

-- Мифическая: радуга по обводке плашки (UIGradient "FxRim" на её UIStroke), обводка толще в
-- RIM_THICK раз; градиент медленно вращается (твин до уборки trove).
local function rainbowRim(frame: Frame, trove: Trove.Trove)
	local strokes: { UIStroke } = {}
	local lip = frame:FindFirstChild("Lip")
	local ring = lip and lip:FindFirstChildOfClass("UIStroke")
	if ring then
		ring.Thickness = UiFx.strokeThickness(ring) * RIM_THICK
		table.insert(strokes, ring)
	end
	for _, stroke in strokes do
		stroke.Color = UIConfig.White
		local fill = Instance.new("UIGradient")
		fill.Name = "FxRim"
		fill.Color = UiFx.sequence(UIConfig.Rainbow)
		fill.Rotation = 0
		fill.Parent = stroke
		local spin = TweenService:Create(
			fill,
			TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
			{ Rotation = 360 }
		)
		spin:Play()
		trove:Add(function()
			spin:Cancel()
		end)
	end
end

-- Открыт ли лист (Controllers.Sheet: атрибут HUD Sheet, пока лист на экране).
local function sheetOpen(): boolean
	local hud = container and container.Parent
	return hud ~= nil and hud:GetAttribute("Sheet") ~= nil
end

-- Высота уведомления item, доля колонки (как её даст present).
local function heightOf(item: Pending): number
	if styleOf(item.kind).Big then
		return bigLayout(item.text).height
	end
	local _, twoLines = measure(item.text, "Body")
	return SLOT * (if twoLines then TWO_LINES else 1)
end

-- Можно ли показать item, когда на экране уже count уведомлений: место по виду (capacity), лист
-- (afterSheet ждёт его ухода) и низ item не ниже stackLimit (без полос первое — всегда).
canShow = function(item: Pending, count: number): boolean
	if count >= capacity(styleOf(item.kind).Priority) then
		return false
	end
	if item.look and item.look.afterSheet and sheetOpen() then
		return false
	end
	local limit = stackLimit()
	if not limit or (count == 0 and next(reserved) == nil) then
		return true
	end
	local y = reservedShare()
	for i = 1, count do
		local toast = active[i]
		y += (if toast then toast.height else SLOT) + GAP
	end
	return y + heightOf(item) <= limit + 1e-6
end

-- Уведомления, что больше не помещаются (полосы, предел над рыбаком), уходят; кто не дожил и до
-- половины срока и ещё не прочитан (на экране меньше UIConfig.ToastSeen с) — снова в начало
-- очереди (с пометкой requeued: прождёт дольше своего срока — уже не покажем, Wave 3 UX-05:
-- «Щит погас» 8 с спустя, на миг перед «Украдено»); прочитанное уходит насовсем (одно
-- уведомление сервера — один показ: «Щит погас» после короткой тревоги не выходит второй раз).
local function requeueOverflow()
	while #active > 0 do
		local last = active[#active]
		local fits = #active <= roomBelowReserve()
		local limit = if fits and (next(reserved) ~= nil or #active > 1) then stackLimit() else nil
		if fits and limit then
			local y = reservedShare()
			for i, toast in active do
				y += toast.height + (if i < #active then GAP else 0)
			end
			fits = y <= limit + 1e-6
		end
		if fits then
			return
		end
		local now = os.clock()
		if now - last.shownAt < math.min(last.life / 2, UIConfig.ToastSeen) then
			last.item.requeued = now
			table.insert(queue, 1, last.item)
		end
		dismiss(last, true)
	end
end

-- Таймер в тексте (Look.clock): пока уведомление на экране, live перечитывается на каждой целой
-- секунде до clock — как фишка щита (DefenceController: task.delay ровно до смены числа), поэтому
-- в одном кадре оба говорят одно время (F-12). Кончилось (live — nil или clock прошёл) — цепочки
-- нет, последний текст до ухода; ушло с экрана (Trove) — шаг ничего не делает.
local function tickLive(toast: Toast, label: TextLabel, live: () -> string?, clock: number)
	local on = true
	toast.trove:Add(function()
		on = false
	end)
	local step: () -> ()
	local function after()
		local left = clock - Workspace:GetServerTimeNow()
		if left > 0 then
			task.delay(math.max(left - math.floor(left), 0.01), step)
		end
	end
	step = function()
		if not on then
			return
		end
		local text = live()
		if not text then
			return
		end
		if label.Text ~= text then
			label.Text = text
		end
		after()
	end
	after()
end

present = function(item: Pending)
	local parent, source = container, template
	if not parent or not source then
		return
	end
	item.requeued = nil -- (снова на экране: пометка «согнано полосой» — только до показа)
	local live = item.look and item.look.live
	if live then
		-- (ждавшее уведомление: таймер — на сейчас; нечего сказать — не показываем)
		local text = live()
		if not text then
			task.defer(drain)
			return
		end
		item.text = text
	end
	counter += 1
	local style = styleOf(item.kind)
	local look: Look = item.look or {} :: Look
	local big = style.Big == true
	local layout = if big then bigLayout(item.text) else nil
	local natural, twoLines = measure(item.text, "Body")
	local height = SLOT * (if twoLines then TWO_LINES else 1)
	if layout then
		natural, height = layout.natural, layout.height
	end

	local frame = source:Clone()
	frame.Name = "Toast"
	frame.LayoutOrder = counter
	frame.Size = UDim2.fromScale(natural, height)
	frame:SetAttribute("Kind", item.kind)
	frame:SetAttribute("NaturalWidth", natural) -- своя ширина по тексту (в стопке — по самому широкому)
	UiFx.setCandy(frame, look.swatch or style.Token)
	local trove = Trove.new()
	local toast: Toast = {
		frame = frame,
		priority = style.Priority or 1,
		height = height,
		natural = natural,
		trove = trove,
		entering = true,
		item = item,
		shownAt = os.clock(),
		life = style.Life or UIConfig.ToastDuration,
	}

	local label = frame:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = item.text
		label.TextWrapped = true
		label:SetAttribute("TextTier", "Body") -- до вставки: UiFx.fitText подгонит при добавлении
		if layout then
			dressBig(frame, label, style, layout)
		end
	end
	local clock = look.clock
	if live and type(clock) == "number" and not layout and label and label:IsA("TextLabel") then
		tickLive(toast, label, live, clock) -- (одни часы с фишкой щита, F-12)
	end
	local socket = frame:FindFirstChild("IconSocket")
	local icon = if socket then socket:FindFirstChild("Icon") else nil
	if icon and icon:IsA("TextLabel") then
		icon.Text = look.icon or style.Icon
	end
	if style.Rainbow then
		-- Мифическая: тёмная плашка (Night, цвет вида) — радуга только по обводке; белые буквы
		-- читаются.
		rainbowRim(frame, trove)
	end

	table.insert(active, toast)
	local slot = #active
	-- Въезд сверху — но не выше свободного верха колонки (под полосами): над колонкой плашки
	-- статуса (и плашка тревоги), выезжающее уведомление их не пересекает (Этап 4, C-31); у
	-- верхнего слота въезд — пружина масштаба (popIn / «удар»).
	local target = slotPosition(slot)
	local drop = math.min(ENTER_DROP, math.max(0, target.Y.Scale - reservedShare()))
	frame.Position = target - UDim2.fromScale(0, drop)
	frame.Visible = true
	frame.Parent = parent

	-- Въезд: сверху в слот с пружиной, значок выскакивает следом, потом блик. Громкие — «удар» с
	-- перелётом (0.3 → 1.12 → 1), при посадке — кольцо цвета редкости, вспышка ободка и строки.
	UiFx.tween(frame, ENTER_TIME, { Position = target }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	if big then
		UiFx.punch(frame, { from = 0.3, peak = 1.12, up = 0.2, settle = 0.25 })
		trove:Add(task.delay(ENTER_TIME, function()
			local rarity = UIConfig.Rarity[item.kind]
			UiFx.glowRing(frame, {
				color = if rarity and not rarity.Rainbow then rarity.Top else UIConfig.White,
				scale = 1.25,
				time = 0.45,
				thickness = 4,
			})
			UiFx.rimFlash(frame, { bump = 1 })
			if label and label:IsA("TextLabel") then
				UiFx.flashText(label, UIConfig.Palette.Gold.Top, 0.4)
			end
		end))
	else
		UiFx.popIn(frame, { from = 0.5, time = ENTER_TIME })
	end
	if socket and socket:IsA("GuiObject") then
		-- Значок «вкручивается» (−180° → 0, Back Out), когда плашка села; у предупреждения и
		-- громких новостей потом ещё и качается.
		UiFx.popIn(socket, { from = 0, time = 0.35, delay = 0.22, rotate = -180 })
		if item.kind == "warning" or big then
			trove:Add(task.delay(0.62, function()
				local glyph = socket:FindFirstChild("Icon")
				if glyph and glyph:IsA("GuiObject") then
					UiFx.wiggle(glyph, 16, 3, 0.45)
				end
			end))
		end
	end
	trove:Add(task.delay(0.3, function()
		UiFx.shine(frame, if big then 0.8 else 0.6)
	end))
	if big then
		-- (Звёздочки — только по бокам плашки и мельче: на буквах они закрыли бы «×5!», ART-02.)
		trove:Add(UiFx.sparkles(frame, { rate = 7, duration = 2, size = 0.3, outside = true }))
		trove:Add(UiFx.arpeggio(if style.Rainbow then "Legendary" else "Epic", 0.25))
		-- (v3, UIM-06: чужой улов экран не красит — края экрана только у своего.)
	elseif item.kind == "success" or item.kind == "base" then
		trove:Add(UiFx.sparkles(frame, { rate = 6, duration = 1.2, size = 0.5, outside = true }))
	elseif item.kind == "danger" then
		trove:Add(task.delay(ENTER_TIME, function()
			UiFx.wiggle(frame, 4, 3, 0.4)
		end))
	end
	reflow()
	trove:Add(task.delay(ENTER_TIME, function()
		toast.entering = false
		reflow() -- пока въезжал, слот мог сдвинуться
	end))

	trove:Add(task.delay(toast.life, expire, toast))
end

-- Показать уведомление. Можно вызывать из любых клиентских модулей.
function NotifyController.Show(text: string, kind: string?, look: Look?)
	if not container or not template then
		return -- контроллер ещё не запущен
	end
	local name = kind or "info"
	if not UIConfig.ToastKinds[name] then
		name = "info"
	end
	local item: Pending = { text = text, kind = name, look = look }
	local priority = styleOf(name).Priority or 1
	local cap = capacity(priority)
	if canShow(item, #active) then
		present(item)
		return
	end
	-- Места нет: вытесняем неважное (с открытой рыбалкой — только ради более важного); при
	-- карточке улова (и на телефоне при мини-игре) места нет вовсе — ждём; пока стоят полосы
	-- (место — до головы рыбака) или ждём ухода листа — тоже ждём.
	local waits = next(reserved) ~= nil or (look ~= nil and look.afterSheet == true and sheetOpen())
	local victim = if cap > 0 and not waits then victimFor(priority, busy()) else nil
	if victim then
		dismiss(victim, true)
		present(item)
		return
	end
	table.insert(queue, item)
	while #queue > MAX_QUEUE do
		table.remove(queue, 1)
	end
end

-- Этап 4: занять px сверху колонки под полосу key ("theft" — вор, "alert" — тревога хозяина);
-- px = 0 или nil — освободить. Уведомления переезжают ниже (или ждут, если места не осталось).
function NotifyController.Reserve(key: string, px: number?)
	local value = if type(px) == "number" and px == px and px > 0 then px else nil
	if reserved[key] == value then
		return
	end
	reserved[key] = value
	if not container then
		return -- (контроллер ещё не запущен: место учтётся при первом уведомлении)
	end
	-- Уведомления, которым под полосами больше нет места (или легли бы на рыбака), уходят (снова в
	-- очередь).
	requeueOverflow()
	reflow()
	drain()
end

-- Зазор под полосой до первого уведомления, px (GAP колонки, но не меньше BAND_GAP).
function NotifyController.BandGap(): number
	local height = columnHeight()
	return if height > 1 then bandGapPx(height) else BAND_GAP
end

-- Убрать уведомления с меткой tag (Look.tag) — с экрана (сразу, без ухода) и из очереди (тревога:
-- «у тебя во дворе!» того же вора больше не нужно — плашка говорит то же громче).
function NotifyController.Drop(tag: string)
	for index = #queue, 1, -1 do
		local look = queue[index].look
		if look and look.tag == tag then
			table.remove(queue, index)
		end
	end
	local removed = false
	for index = #active, 1, -1 do
		local toast = active[index]
		local look = toast.item.look
		if look and look.tag == tag then
			-- сразу, без ухода: на его месте уже встаёт то, что говорит то же громче (плашка)
			table.remove(active, index)
			toast.trove:Clean()
			toast.frame:Destroy()
			removed = true
		end
	end
	if removed then
		reflow()
		drain()
	end
end

-- Сколько px от верха колонки до полосы key (полосы — друг под другом в порядке RESERVE_ORDER;
-- у каждой — зазор BandGap). Полосы key ещё нет — где она встанет по этому порядку (тревога
-- хозяина над полосой вора «thief», которая держит всю колонку, — а не под ней: Stage 4 wave 3).
function NotifyController.Offset(key: string): number
	local height = columnHeight()
	local gap = if height > 1 then bandGapPx(height) else 0
	local y = 0
	for _, other in reserveKeys(key) do
		if other == key then
			return y
		end
		y += (reserved[other] or 0) + gap
	end
	return y
end

-- Сколько px занято полосами сверху колонки (без зазоров; тесты).
function NotifyController.Reserved(): number
	local total = 0
	for _, px in reserved do
		total += px
	end
	return total
end

-- Рыбалка открыла/закрыла свой виджет: лишние уведомления уходят (кто не дожил и до половины
-- срока — снова в начало очереди), ждущие выходят.
local function onBusyChanged()
	local now = os.clock()
	local function remove(toast: Toast)
		if now - toast.shownAt < toast.life / 2 then
			table.insert(queue, 1, toast.item)
		end
		dismiss(toast, true)
	end
	for _, toast in table.clone(active) do
		if capacity(toast.priority) == 0 then
			remove(toast)
		end
	end
	while #active > capacity(math.huge) do
		local victim = victimFor(math.huge, false)
		if not victim then
			break
		end
		remove(victim)
	end
	while #queue > MAX_QUEUE do
		table.remove(queue)
	end
	drain()
end

-- Лист открылся / ушёл (атрибут HUD Sheet): те, что ждут его ухода (Look.afterSheet), уходят с
-- экрана (кто не дожил до половины срока — снова в начало очереди); ушёл — ждущие выходят.
local function onSheetChanged()
	if sheetOpen() then
		local now = os.clock()
		for _, toast in table.clone(active) do
			local look = toast.item.look
			if look and look.afterSheet then
				if now - toast.shownAt < toast.life / 2 then
					table.insert(queue, 1, toast.item)
				end
				dismiss(toast, true)
			end
		end
		while #queue > MAX_QUEUE do
			table.remove(queue)
		end
	end
	drain()
end

--------------------------------------------------------------------------------
-- Значок чужого улова вне экрана (см. шапку)
--------------------------------------------------------------------------------

type Pointer = { frame: Frame, base: Vector3, player: Player, ends: number, shown: boolean, right: boolean? }

local pointers: { Pointer } = {}
local pointerTemplate: Frame? = nil
local pointerJob: (() -> ())? = nil

-- Острый край — к краю экрана со стороны столба.
local function aimPointer(pointer: Pointer, right: boolean)
	pointer.right = right
	local tip = pointer.frame:FindFirstChild("Tip")
	if tip and tip:IsA("GuiObject") then
		tip.Position = UDim2.fromScale(if right then 1.1 else -0.1, tip.Position.Y.Scale)
	end
end

type Box = { x0: number, y0: number, x1: number, y1: number }

-- Виден ли элемент (он и все его предки до stop).
local function shownUnder(item: Instance, stop: Instance): boolean
	local node: Instance? = item
	while node and node ~= stop do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return node == stop
end

-- Что значок у колонки не закрывает (px HUD): кнопки рыбалки с подписями, видимые уведомления,
-- плашка тревоги, плашки статуса (их цифры свисают на POINTER.Ink ниже).
local function pointerKeepouts(hud: GuiObject): { Box }
	local origin = hud.AbsolutePosition
	local out: { Box } = {}
	local function add(item: Instance?, below: number?)
		if item and item:IsA("GuiObject") and shownUnder(item, hud) then
			local at, size = item.AbsolutePosition - origin, item.AbsoluteSize
			if size.X > 0 and size.Y > 0 then
				table.insert(out, { x0 = at.X, y0 = at.Y, x1 = at.X + size.X, y1 = at.Y + size.Y + (below or 0) })
			end
		end
	end
	local status = hud:FindFirstChild("Status")
	if status then
		for _, row in status:GetChildren() do
			add(row, POINTER.Ink)
			add(row:FindFirstChild("ShieldChip"))
		end
	end
	if container then
		for _, toast in container:GetChildren() do
			if toast.Name == "Toast" then
				add(toast)
			end
		end
	end
	add(hud:FindFirstChild("TheftAlert"))
	local fishing = hud:FindFirstChild("Fishing")
	local area = if fishing then fishing:FindFirstChild("ActionArea") else nil
	if area then
		for _, button in area:GetChildren() do
			add(button)
			add(button:FindFirstChild("Caption"))
		end
	end
	return out
end

local function boxesClear(box: Box, keepouts: { Box }, gap: number): boolean
	for _, k in keepouts do
		if box.x0 < k.x1 + gap and k.x0 < box.x1 + gap and box.y0 < k.y1 + gap and k.y0 < box.y1 + gap then
			return false
		end
	end
	return true
end

-- Каждый кадр, пока есть значки: где столб относительно камеры; false — значков больше нет.
local function stepPointers(): boolean
	local now = os.clock()
	for index = #pointers, 1, -1 do
		local pointer = pointers[index]
		if now >= pointer.ends or pointer.player.Parent == nil or pointer.frame.Parent == nil then
			pointer.frame:Destroy()
			table.remove(pointers, index)
		end
	end
	local hud = container and container.Parent
	local camera = Workspace.CurrentCamera
	if #pointers == 0 or not hud or not hud:IsA("GuiBase2d") or not camera then
		for _, pointer in pointers do
			pointer.frame:Destroy()
		end
		table.clear(pointers)
		pointerJob = nil
		return false
	end
	-- На телефоне — не во время своей поклёвки, мини-игры и улова (как уведомления).
	local hidden = isPhone() and capacity(1) == 0
	local area = hud.AbsoluteSize
	local view = camera.ViewportSize
	local side = math.clamp(area.Y * 0.118, 44, 72) -- размер значка (HUD.TrophyPointer)
	local reach = side * 0.92 -- от центра до кончика острого края
	-- Справа внизу — колонка кнопок («ДОМОЙ»): значок над ней, не ближе POINTER.ColumnGap.
	local column = hud:FindFirstChild("RightButtons")
	local columnTop = math.huge
	local columnLeft = math.huge
	local columnBottom = math.huge
	local buttons = 0
	if column and column:IsA("GuiObject") and column.Visible then
		-- Кнопки прижаты к низу колонки (UIListLayout, VerticalAlignment Bottom): верх их стопки
		-- считаем от низа колонки.
		local list = column:FindFirstChildOfClass("UIListLayout")
		local gap = if list then list.Padding.Scale * column.AbsoluteSize.Y + list.Padding.Offset else 0
		local stack, count = 0, 0
		local widest = 0
		for _, button in column:GetChildren() do
			if button:IsA("GuiObject") and button.Visible then
				stack += button.AbsoluteSize.Y
				widest = math.max(widest, button.AbsoluteSize.X)
				count += 1
			end
		end
		if count > 0 then
			local bottom = column.AbsolutePosition.Y + column.AbsoluteSize.Y - hud.AbsolutePosition.Y
			columnTop = bottom - stack - gap * (count - 1)
			columnBottom = bottom
			-- (кнопки — по центру колонки: левый край самой широкой)
			columnLeft = column.AbsolutePosition.X - hud.AbsolutePosition.X + (column.AbsoluteSize.X - widest) / 2
		end
		buttons = count
	end
	-- Этап 4: три кнопки, и над колонкой места нет — значок слева от неё, на самом нижнем свободном
	-- месте полосы: от низа колонки (на тач-экране — над кнопкой прыжка: его кольцо ≥ 16 px от неё)
	-- вверх, мимо кнопок рыбалки, уведомлений, плашки тревоги и статуса (pointerKeepouts).
	local besideColumn = buttons >= 3 and columnTop - POINTER.ColumnGap - side * 0.75 < side * 0.7
	local footY = columnBottom - side * 0.62
	if besideColumn and UserInputService.TouchEnabled then
		local small = math.min(view.X, view.Y) <= POINTER.SmallTouch
		local jump, r = FishingLayout.jumpCircle(area, small)
		footY = jump.Y - r - POINTER.JumpGap - side * POINTER.Ring
	end
	local laneKeepouts = if besideColumn then pointerKeepouts(hud :: GuiObject) else {}
	local ringHalf = side * POINTER.Ring
	-- значок в полосе у колонки с центром на высоте y (с запасом на покачивание и кольцо)
	local function laneBox(y: number): Box
		local x = columnLeft - POINTER.SideGap - reach
		return { x0 = x - ringHalf - POINTER.Bob, y0 = y - ringHalf, x1 = x + reach, y1 = y + ringHalf }
	end
	local function laneSpot(): number?
		local y = footY
		local top = POINTER.Top + ringHalf
		while y >= top do
			local box = laneBox(y)
			if boxesClear(box, laneKeepouts, MIN_GAP + POINTER.Ink) then
				return y
			end
			y -= POINTER.Step
		end
		return nil
	end
	local wave = POINTER.Bob * (0.5 - 0.5 * math.cos(now * 2 * math.pi / POINTER.Period))
	-- Сколько значков уже стоит у каждого края: следующий — выше (стопкой вверх).
	local slots: { [string]: number } = { left = 0, right = 0 }
	for _, pointer in pointers do
		local world = pointer.base + Vector3.new(0, POINTER.Lift, 0)
		local point = camera:WorldToViewportPoint(world)
		local onScreen = point.Z > 0 and point.X >= 0 and point.X <= view.X
		local frame = pointer.frame
		if onScreen or hidden then
			frame.Visible = false
			pointer.shown = false
		else
			local right = camera.CFrame:PointToObjectSpace(world).X > 0
			if right ~= pointer.right then
				aimPointer(pointer, right)
			end
			local x = if right then area.X - POINTER.Gap - reach - wave else POINTER.Gap + reach + wave
			local y = area.Y * POINTER.Y
			local edge = if right then "right" else "left"
			local spot: number? = nil
			if right and besideColumn then
				-- слева от колонки, на самом нижнем свободном месте; следующий — над ним (его коробка —
				-- в помехах); места нет — значок спрятан
				spot = laneSpot()
				x = columnLeft - POINTER.SideGap - reach - wave
				y = spot or 0
				if spot then
					table.insert(laneKeepouts, laneBox(spot))
				end
			else
				if right then
					y = math.min(y, columnTop - POINTER.ColumnGap - side * 0.75)
				end
				y -= slots[edge] * side * POINTER.Stack
			end
			slots[edge] += 1
			if right and besideColumn and spot == nil then
				frame.Visible = false
				pointer.shown = false
				continue
			end
			frame.Position = UDim2.fromOffset(math.round(x), math.round(math.max(y, side * 0.7)))
			if not pointer.shown then
				pointer.shown = true
				frame.Visible = true
				UiFx.popIn(frame, { from = 0.3, time = 0.3 })
			end
		end
	end
	return true
end

-- У другого рыбака встал столб света легендарной / мифической рыбы (FishingFxController).
local function onOtherTrophy(player: any, base: any, rarity: any)
	local source = pointerTemplate
	local hud = container and container.Parent
	local style = if typeof(rarity) == "string" then UIConfig.Rarity[rarity] else nil
	if not source or not hud or typeof(base) ~= "Vector3" or typeof(player) ~= "Instance" or not style then
		return
	end
	while #pointers >= POINTER.Max do
		local oldest = table.remove(pointers, 1) :: Pointer
		oldest.frame:Destroy()
	end
	local life = FishingConfig.Fx.PillarTimeOther[rarity] or FishingConfig.Fx.PillarTimeOther.Legendary
	local frame = source:Clone()
	frame.Name = "TrophyChip"
	frame.Visible = false
	frame:SetAttribute("Rarity", rarity)
	local body = frame:FindFirstChild("Body")
	if body and body:IsA("GuiObject") then
		local socket = body:FindFirstChild("IconSocket")
		local icon = socket and socket:FindFirstChild("Icon")
		if icon and icon:IsA("TextLabel") then
			icon.Text = if style.Rainbow then "🌈" else "🌟"
		end
		if style.Rainbow then
			local fill = UiFx.faceOf(body):FindFirstChild("Fill")
			if fill and fill:IsA("UIGradient") then
				fill.Color = UiFx.sequence(UIConfig.Rainbow)
				fill.Rotation = 0
			end
		else
			UiFx.setCandy(body, { Top = style.Top, Bottom = style.Bottom, Lip = style.Lip })
		end
		local lip = body:FindFirstChild("Lip")
		if lip and lip:IsA("GuiObject") then
			lip.BackgroundColor3 = style.Lip
			local edge = lip:FindFirstChildOfClass("UIStroke")
			if edge then
				edge.Color = style.Lip
			end
		end
	end
	local tip = frame:FindFirstChild("Tip")
	if tip and tip:IsA("GuiObject") then
		tip.BackgroundColor3 = if style.Rainbow then UIConfig.Rainbow[1] else style.Bottom
		local edge = tip:FindFirstChildOfClass("UIStroke")
		if edge then
			edge.Color = style.Lip
		end
	end
	local ring = frame:FindFirstChild("BaseRing")
	local stroke = ring and ring:FindFirstChild("Stroke")
	local color = (player :: Player):GetAttribute("BaseColor")
	if stroke and stroke:IsA("UIStroke") then
		stroke.Color = if typeof(color) == "Color3" then color else UIConfig.White
	end
	frame.Parent = hud
	table.insert(pointers, {
		frame = frame,
		base = base,
		player = player :: Player,
		ends = os.clock() + life,
		shown = false,
		right = nil,
	})
	if not pointerJob then
		pointerJob = UiFx.schedule(function(): boolean
			return stepPointers()
		end)
	end
	stepPointers()
end

function NotifyController:Start(hud: ScreenGui)
	local toasts = hud:WaitForChild("Toasts") :: Frame
	local toastTemplate = toasts:WaitForChild("ToastTemplate") :: Frame
	toastTemplate.Visible = false
	container = toasts
	template = toastTemplate
	local cap = toasts:FindFirstChildOfClass("UISizeConstraint")
	if cap and not UserInputService.TouchEnabled then
		-- Без тач-экрана слева вверху окно чата Roblox: колонка уже, чтобы его не задевать.
		local widest = cap.MaxSize.X
		local function fitColumn()
			local width = hud.AbsoluteSize.X
			if width > 1 then
				local room = 2 * (width / 2 - CHAT_RIGHT - CHAT_GAP)
				cap.MaxSize = Vector2.new(math.clamp(room, COLUMN_MIN, widest), cap.MaxSize.Y)
			end
		end
		fitColumn()
		hud:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitColumn)
	end

	local pointer = hud:FindFirstChild("TrophyPointer")
	if pointer and pointer:IsA("Frame") then
		pointer.Visible = false
		pointerTemplate = pointer
		local module = script.Parent and script.Parent:FindFirstChild("FishingFxController")
		local ok, fx = pcall(function(): any
			return if module and module:IsA("ModuleScript") then require(module) :: any else nil
		end)
		if ok and fx and fx.OtherTrophy then
			fx.OtherTrophy:Connect(onOtherTrophy)
		end
	end

	local fishing = hud:FindFirstChild("Fishing")
	if fishing then
		for _, name in BUSY_WIDGETS do
			local widget = fishing:FindFirstChild(name)
			if widget and widget:IsA("GuiObject") then
				table.insert(busyWidgets, widget)
				widget:GetPropertyChangedSignal("Visible"):Connect(onBusyChanged)
			end
		end
		local card = fishing:FindFirstChild("CatchCard")
		if card and card:IsA("GuiObject") then
			cardWidget = card
			card:GetPropertyChangedSignal("Visible"):Connect(onBusyChanged)
		end
		local function isGhost(item: Instance): boolean
			return item.Name == "FxMinigameWin" or item.Name == "FxMinigameMiss"
		end
		fishing.ChildAdded:Connect(function(item: Instance)
			if isGhost(item) then
				ghosts += 1
				onBusyChanged()
			end
		end)
		fishing.ChildRemoved:Connect(function(item: Instance)
			if isGhost(item) then
				ghosts = math.max(ghosts - 1, 0)
				onBusyChanged()
			end
		end)
		-- Слова попаданий над панелью мини-игры (UiFx.floatText «FxFloat»).
		local minigame = fishing:FindFirstChild("Minigame")
		if minigame then
			minigame.ChildAdded:Connect(function(item: Instance)
				if item.Name == "FxFloat" then
					words += 1
					onBusyChanged()
				end
			end)
			minigame.ChildRemoved:Connect(function(item: Instance)
				if item.Name == "FxFloat" then
					words = math.max(words - 1, 0)
					onBusyChanged()
				end
			end)
		end
		-- Улов на экране держит счётчик (атрибут HUD CounterHold, FishingController): всё это
		-- время — ни одного уведомления.
		hud:GetAttributeChangedSignal("CounterHold"):Connect(onBusyChanged)
	end
	-- Этап 4: лист открыт — те, что ждут его ухода (Look.afterSheet), ждут (см. canShow).
	hud:GetAttributeChangedSignal("Sheet"):Connect(onSheetChanged)
	-- v3: на телефоне, пока своя рыба над головой (HeldFish), — тоже (см. capacity).
	local player = Players.LocalPlayer
	local function watchCharacter(character: Model)
		local function update()
			local held = character:FindFirstChild("HeldFish") ~= nil
			if held ~= trophyHeld then
				trophyHeld = held
				onBusyChanged()
			end
		end
		character.ChildAdded:Connect(update)
		character.ChildRemoved:Connect(update)
		update()
	end
	if player then
		player.CharacterAdded:Connect(watchCharacter)
		if player.Character then
			watchCharacter(player.Character)
		end
	end

	Net.Event("Notify").OnClientEvent:Connect(function(text: any, kind: any)
		if typeof(text) ~= "string" then
			return
		end
		NotifyController.Show(text, if typeof(kind) == "string" then kind else "info")
	end)
end

return NotifyController
