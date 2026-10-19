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
	так (ширина — по буквам, UiFx.textWidth): плашка не ложится на голову персонажа. Чужой
	улов не красит экран (никаких радужных краёв: новичок не подумает, что это он поймал).
	Неизвестный вид — как "info".
	look = { swatch = {Top, Bottom, Lip}?, icon = "🚩"? } заменяет цвет и значок вида.

	Каждое уведомление — копия HUD.Toasts.ToastTemplate (имя "Toast"), ширина — по длине текста
	(текст по шкале UiFx.fitText: Body); длинный текст — в две строки. Если уведомлений
	несколько, все тянутся до ширины самого широкого (значки встают в столбик). Колонку
	раскладывает этот модуль (без UIListLayout): новое уведомление съезжает сверху в свой слот с
	пружинкой, значок «вкручивается» (−180° → 0), когда плашка села (у предупреждения и громких —
	потом ещё качается), по плашке пробегает блик, у громких вспыхивает ободок; «успех» и
	громкие — со звёздочками по бокам плашки (не на буквах), «опасность» — встряхивается.
	Соседи съезжают на новые места с лёгким перелётом (Back Out). Без тач-экрана колонка (по центру) сужается так,
	чтобы не задевать окно чата Roblox слева вверху (CHAT_RIGHT, CHAT_GAP), и при смене размера окна.

	Сколько видно сразу: UIConfig.MaxToasts на компьютере, MaxToastsTouch на планшете,
	MaxToastsPhone на телефоне (HUD ниже PHONE_HEIGHT px: второе легло бы на голову персонажа).
	Пока улов на экране (у HUD атрибут CounterHold — от "Caught" до прилёта 🐟 в счётчик — или
	видна HUD.Fishing.CatchCard) — ни одного; на телефоне ни одного (кроме «опасности») и пока
	своя рыба над головой (HeldFish в своём персонаже, v3: трофей не под уведомлением); пока мини-игра или «КЛЮЁТ!» (Minigame / BiteAlert)
	— одно, а на телефоне ни одного, кроме «опасности»; пока доигрывает копия мини-игры
	(FxMinigameWin / FxMinigameMiss: «ПОЙМАНА!», «МИМО!») или над панелью поднимается слово
	попадания (Minigame.FxFloat) — ни одного, кроме «опасности», на любом экране: эти слова
	поднимаются в колонку уведомлений, а уведомление, которое не прочесть, зря тратит свой срок.
	Остальные ждут в очереди и выходят, когда место освободится; уведомление, которое такой
	виджет согнал с экрана в первой половине срока, встаёт в начало очереди. Когда места нет,
	уходит самое старое из самых неважных (Priority вида; «опасность» вытесняет обычные); если
	все на экране важнее нового — новое ждёт в очереди.
	Уход: через Life (или UIConfig.ToastDuration) секунд уведомление поднимается на 20 px, чуть
	поворачивается (+4°) и тает (имя "ToastLeaving"), остальные через 0.12 с съезжают вверх; уходят не чаще, чем раз в
	UIConfig.ToastGap секунд.

	Только твины и таймеры: ни одного покадрового соединения на уведомление.

	Место сверху колонки (Этап 4): NotifyController.Reserve(key, px) — виджет, который стоит в
	слоте уведомлений (полоса вора "theft" — TheftController, плашка тревоги "alert" —
	AlertController), занимает px сверху колонки; уведомления едут ниже (каждой полосе — ещё
	зазор GAP колонки); px = 0 или nil — место освобождено, ждущие выходят. Полосы стоят друг под
	другом в порядке RESERVE_ORDER («theft», потом «alert»; незнакомые — следом, по имени):
	NotifyController.Offset(key) — сколько px от верха колонки до полосы key (виджет ставит себя
	туда). Если под полосами не помещается ни одно уведомление, они ждут в очереди (на телефоне
	иначе легли бы на голову персонажа). NotifyController.Reserved() — сколько px занято (тесты).

	Чужой легендарный / мифический улов (FishingFxController.OtherTrophy), чей столб света сейчас
	не на экране (за спиной или за краем кадра): у края экрана с его стороны — маленький значок
	(копия HUD.TrophyPointer, «TrophyChip»: 🌟 на золотой / 🌈 на радужной круглой кнопке в кольце
	цвета базы рыбака, острый край «тычет» к краю экрана), пока столб горит (FishingConfig.Fx.
	PillarTimeOther); столб попал в кадр — значка нет. На телефоне — не во время своей поклёвки,
	мини-игры и улова (то же правило, что у уведомлений). Пока есть хоть один значок — один
	покадровый эффект планировщика UiFx (где столб относительно камеры); нет значков — ничего.
	Этап 4: в колонке справа три кнопки («ЗАЩИТА» над «САДОК» и «ДОМОЙ») — на HUD ниже
	POINTER.ThreeTall px (телефоны) над колонкой места нет: значок с правой стороны встаёт СЛЕВА от
	колонки, у её верха (его острый край — в POINTER.Gap px от неё; следующий — ниже); планшет и
	компьютер — как раньше.
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

type Swatch = UIConfig.Swatch
type ToastKind = UIConfig.ToastKind

export type Look = {
	swatch: Swatch?, -- цвет «конфеты» вместо цвета вида
	icon: string?, -- значок вместо значка вида
}

type Pending = { text: string, kind: string, look: Look? }

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
local LEAVE_TIME = 0.2
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
-- Этап 4: три кнопки в колонке на HUD ниже ThreeTall px — значок слева от колонки, у её верха.
local POINTER = {
	Y = 0.38,
	Stack = 1.35,
	Gap = 16,
	ColumnGap = 20,
	Bob = 6,
	Period = 0.8,
	Lift = 40,
	Max = 3,
	ThreeTall = 600,
}

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

-- Ключи полос сверху вниз: сначала RESERVE_ORDER, потом незнакомые по имени.
local function reserveKeys(): { string }
	local keys = {}
	for _, key in RESERVE_ORDER do
		if reserved[key] then
			table.insert(keys, key)
		end
	end
	local others = {}
	for key in reserved do
		if not table.find(RESERVE_ORDER, key) then
			table.insert(others, key)
		end
	end
	table.sort(others)
	for _, key in others do
		table.insert(keys, key)
	end
	return keys
end

-- Доля высоты колонки, занятая полосами (у каждой — ещё зазор GAP).
local function reservedShare(): number
	local height = columnHeight()
	if height <= 1 or next(reserved) == nil then
		return 0
	end
	local share = 0
	for _, px in reserved do
		share += px / height + GAP
	end
	return share
end

-- Сколько уведомлений обычной высоты помещается под полосами (без полос — без предела).
local function roomBelowReserve(): number
	if next(reserved) == nil then
		return math.huge
	end
	local free = 1 - reservedShare()
	return math.max(0, math.floor((free + GAP) / (SLOT + GAP) + 1e-6))
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

-- Выпустить ждущих, пока есть место (с маленьким шагом, чтобы не въезжали разом); первым —
-- первый, кому сейчас можно (на телефоне при мини-игре — только «опасность»).
local function drain()
	local started = 0
	while true do
		local found: number? = nil
		for index, item in queue do
			if #active + started < capacity(styleOf(item.kind).Priority) then
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
	-- Уходит вверх на 20 px с лёгким поворотом (+4°), сжимается и тает (Quad In).
	local quad, inDir = Enum.EasingStyle.Quad, Enum.EasingDirection.In
	UiFx.tween(frame, time, { Position = frame.Position - UDim2.fromOffset(0, 20), Rotation = 4 }, quad, inDir)
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
	local need = math.max(width(byline, small), width(headline, head) / lines)
	local natural = math.clamp(need / (LABEL_SHARE * 0.94) / area.X, MIN_WIDTH, widest)
	local px = ((if byline then small else 0) + head * lines) * BIG_LINE / BIG_PAD
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

present = function(item: Pending)
	local parent, source = container, template
	if not parent or not source then
		return
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
	frame.Position = slotPosition(slot) - UDim2.fromScale(0, 0.3)
	frame.Visible = true
	frame.Parent = parent

	-- Въезд: сверху в слот с пружиной, значок выскакивает следом, потом блик. Громкие — «удар» с
	-- перелётом (0.3 → 1.12 → 1), при посадке — кольцо цвета редкости, вспышка ободка и строки.
	UiFx.tween(frame, ENTER_TIME, { Position = slotPosition(slot) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
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
	if #active < cap then
		present(item)
		return
	end
	-- Места нет: вытесняем неважное (с открытой рыбалкой — только ради более важного); при
	-- карточке улова (и на телефоне при мини-игре) места нет вовсе — ждём.
	local victim = if cap > 0 then victimFor(priority, busy()) else nil
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
	-- Уведомления, которым под полосами больше нет места, уходят (снова в очередь).
	local room = roomBelowReserve()
	while #active > room do
		local last = active[#active]
		table.insert(queue, 1, last.item)
		dismiss(last, true)
	end
	reflow()
	drain()
end

-- Сколько px от верха колонки до полосы key (полосы — друг под другом в порядке RESERVE_ORDER;
-- у каждой — зазор GAP колонки). Полосы key нет — где встала бы следующая.
function NotifyController.Offset(key: string): number
	local height = columnHeight()
	local gap = if height > 1 then GAP * height else 0
	local y = 0
	for _, other in reserveKeys() do
		if other == key then
			return y
		end
		y += reserved[other] + gap
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
	local side = math.clamp(area.Y * 0.118, 46, 72) -- размер значка (HUD.TrophyPointer)
	local reach = side * 0.92 -- от центра до кончика острого края
	-- Справа внизу — колонка кнопок («ДОМОЙ»): значок над ней, не ближе POINTER.ColumnGap.
	local column = hud:FindFirstChild("RightButtons")
	local columnTop = math.huge
	local columnLeft = math.huge
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
			-- (кнопки — по центру колонки: левый край самой широкой)
			columnLeft = column.AbsolutePosition.X - hud.AbsolutePosition.X + (column.AbsoluteSize.X - widest) / 2
		end
		buttons = count
	end
	-- Этап 4: три кнопки на низком HUD — над колонкой места нет, значок слева от неё у её верха.
	local besideColumn = buttons >= 3 and area.Y < POINTER.ThreeTall
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
			if right and besideColumn then
				-- слева от колонки, кольцо — у её верха; следующий — ниже
				x = columnLeft - POINTER.Gap - reach - wave
				y = columnTop + side * 0.62 + slots[edge] * side * POINTER.Stack
			else
				if right then
					y = math.min(y, columnTop - POINTER.ColumnGap - side * 0.75)
				end
				y -= slots[edge] * side * POINTER.Stack
			end
			slots[edge] += 1
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
