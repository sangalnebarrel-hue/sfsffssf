--!strict
--[[
	NotifyController — всплывающие уведомления (HUD.Toasts) в стиле Candy Splash
	(tools/builder/gui/STYLE.md; анимации — ReplicatedStorage.Shared.UiFx).

	Источники:
	  • сервер: RemoteEvent "Notify" (text, kind);
	  • другие контроллеры: NotifyController.Show(text, kind?, look?).
	kind — вид из UIConfig.ToastKinds: "info" | "success" | "warning" | "danger" (Sky 💬 / Leaf 🎉 /
	Sun ⚠️ / Berry 🚨), "base" (цвета своей базы, 🚩 — look.swatch передаёт HudController),
	"Legendary" (золотая «конфета» с 🌟) и "Mythic" (переливается радугой, 🌈) — громкие новости о
	редком улове: дольше (4.5 с), со звёздочками, в две строки. Сервер присылает их одной строкой
	«Кто: что поймал» (FishingService) — здесь она делится по первому ": ": сверху мелко кто
	(Byline), снизу крупно что (Label: первое слово — редкость — заглавными, буквы золотом /
	радугой, у мифической радуга бежит); на тач-экране такое уведомление может быть шире колонки
	(до BIG_WIDE_TOUCH), без тач-экрана строка «что» переносится. Мифическая ещё один раз
	проводит тонкой радугой по краям экрана. Неизвестный вид — как "info".
	look = { swatch = {Top, Bottom, Lip}?, icon = "🚩"? } заменяет цвет и значок вида.

	Каждое уведомление — копия HUD.Toasts.ToastTemplate (имя "Toast"), ширина — по длине текста
	(текст по шкале UiFx.fitText: Body); длинный текст — в две строки. Если уведомлений
	несколько, все тянутся до ширины самого широкого (значки встают в столбик). Колонку
	раскладывает этот модуль (без UIListLayout): новое уведомление съезжает сверху в свой слот с
	пружинкой, значок выскакивает и качается, по «конфете» пробегает блик; «успех» и громкие —
	со звёздочками, «опасность» — встряхивается. Без тач-экрана колонка (по центру) сужается так,
	чтобы не задевать окно чата Roblox слева вверху (CHAT_RIGHT, CHAT_GAP), и при смене размера окна.

	Сколько видно сразу: UIConfig.MaxToasts на компьютере, MaxToastsTouch на планшете,
	MaxToastsPhone на телефоне (HUD ниже PHONE_HEIGHT px: второе легло бы на голову персонажа).
	Пока улов на экране (у HUD атрибут CounterHold — от "Caught" до прилёта 🐟 в счётчик — или
	видна HUD.Fishing.CatchCard) — ни одного; пока мини-игра или «КЛЮЁТ!» (Minigame / BiteAlert)
	или доигрывает её копия (FxMinigameWin / FxMinigameMiss) — одно, а на телефоне ни одного,
	кроме «опасности»: виджеты рыбалки рисуются поверх колонки, а уведомление, которое не
	прочесть, зря тратит свой срок.
	Остальные ждут в очереди и выходят, когда место освободится; уведомление, которое такой
	виджет согнал с экрана в первой половине срока, встаёт в начало очереди. Когда места нет,
	уходит самое старое из самых неважных (Priority вида; «опасность» вытесняет обычные); если
	все на экране важнее нового — новое ждёт в очереди.
	Уход: через Life (или UIConfig.ToastDuration) секунд уведомление чуть поднимается и тает
	(имя "ToastLeaving"), остальные через 0.12 с съезжают вверх; уходят не чаще, чем раз в
	UIConfig.ToastGap секунд.

	Только твины и таймеры: ни одного покадрового соединения на уведомление.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local UIConfig = require(Shared:WaitForChild("Config"):WaitForChild("UIConfig"))
local UiFx = require(Shared:WaitForChild("UiFx"))

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
local CHAT_GAP = 72
local COLUMN_MIN = 320
-- Громкие (две строки): строка «кто» — уровня Small, «что» — до Title (не мельче Body, иначе
-- переносится); на тач-экране такое уведомление может быть шире колонки во столько раз.
local BIG_WIDE_TOUCH = 1.4
local BIG_CHAR = 0.56 -- средняя ширина буквы в долях размера текста (Nunito ExtraBold)
local BIG_PAD = 0.86 -- доля высоты «конфеты» под строки (остальное — поля и губа)
local BIG_LINE = 1.25 -- высота строки в размерах её текста
local BIG_RAINBOW_LIGHT = 0.45 -- радужные буквы на радужной «конфете» светлее (читаются с обводкой)
local CANDY_LIP = 0.08 -- «губа» конфеты, доля высоты (Theme.LIP)
-- Радуга по краям экрана при мифической новости: тонко, один раз (UiFx.edgeVignette).
local MYTHIC_EDGE: UiFx.VignetteOptions = { fadeIn = 0.25, hold = 0.5, fadeOut = 0.5, size = 0.1 }

local NotifyController = {}

local container: Frame? = nil
local template: Frame? = nil
local active: { Toast } = {}
local queue: { Pending } = {}
local busyWidgets: { GuiObject } = {}
local cardWidget: GuiObject? = nil
local ghosts = 0 -- копий мини-игры (FxMinigameWin / FxMinigameMiss) на экране
local counter = 0
local lastDismiss = -math.huge

local function busy(): boolean
	if ghosts > 0 then
		return true -- мини-игра закрылась, но её копия ещё доигрывает «ПОЙМАНА!» / «МИМО!»
	end
	for _, widget in busyWidgets do
		if widget.Visible then
			return true
		end
	end
	return false
end

local function isPhone(): boolean
	local hud = container and container.Parent
	return UserInputService.TouchEnabled
		and hud ~= nil
		and hud:IsA("GuiBase2d")
		and hud.AbsoluteSize.Y > 1
		and hud.AbsoluteSize.Y < PHONE_HEIGHT
end

-- Сколько уведомлений приоритета priority может быть на экране сейчас (см. шапку).
local function capacity(priority: number?): number
	local hud = container and container.Parent
	if (cardWidget and cardWidget.Visible) or (hud and hud:GetAttribute("CounterHold") ~= nil) then
		return 0 -- улов на экране: от "Caught" (прыжок, карточка) до прилёта 🐟 в счётчик
	end
	local phone = isPhone()
	if busy() then
		return if phone and (priority or 1) < URGENT then 0 else 1
	end
	if not UserInputService.TouchEnabled then
		return UIConfig.MaxToasts
	end
	return if phone then UIConfig.MaxToastsPhone else UIConfig.MaxToastsTouch
end

local function styleOf(kind: string): ToastKind
	return UIConfig.ToastKinds[kind] or UIConfig.ToastKinds.info
end

local function slotPosition(index: number): UDim2
	local y = 0
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
		if not toast.entering then
			UiFx.tween(toast.frame, 0.28, { Position = slotPosition(index) }, quad, out)
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
	UiFx.tween(
		frame,
		time,
		{ Position = frame.Position - UDim2.fromScale(0, toast.height * 0.15) },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	UiFx.tween(UiFx.scaleOf(frame), time, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
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
	local length = utf8.len(text) or #text
	local column = container
	local columnWidth = if column then column.AbsoluteSize.X else 0
	if columnWidth <= 1 then
		return math.clamp(0.34 + length * 0.021, 0.56, 1), false -- раскладки ещё нет
	end
	local textWidth = length * 0.5 * UiFx.textSize(tier)
	local share = textWidth / (LABEL_SHARE * 0.94) / columnWidth
	if share <= 1 then
		return math.max(share, MIN_WIDTH), false
	end
	return 1, true
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
	local headline = if space then upper(string.sub(rest, 1, space - 1)) .. string.sub(rest, space) else upper(rest)
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
		return if line then (utf8.len(line) or #line) * BIG_CHAR * px else 0
	end
	-- «Что» в одну строку (на тач-экране — мельче, но не мельче Body), иначе в две.
	local lines = if width(headline, if touch then body else title) > room then 2 else 1
	local need = math.max(width(byline, small), width(headline, title) / lines)
	local natural = math.clamp(need / (LABEL_SHARE * 0.94) / area.X, MIN_WIDTH, widest)
	local px = ((if byline then small else 0) + title * lines) * BIG_LINE / BIG_PAD
	return {
		natural = natural,
		height = px / area.Y,
		byline = byline,
		headline = headline,
		lines = lines,
		head = title,
	}
end

-- Две строки громкого уведомления: Label — «что» (до Title, золотом / радугой), над ним
-- Byline — «кто» (Small). Доли — от высоты уведомления (строки занимают BIG_PAD её).
local function dressBig(frame: Frame, label: TextLabel, style: ToastKind, layout: BigLayout, trove: Trove.Trove)
	local small, body = UiFx.textSize("Small"), UiFx.textSize("Body")
	local title = layout.head
	local total = (if layout.byline then small else 0) + title * layout.lines
	local top = (1 - CANDY_LIP - BIG_PAD) / 2
	local bylineShare = if layout.byline then BIG_PAD * small / total else 0
	if layout.byline then
		local byline = label:Clone()
		byline.Name = "Byline"
		byline.Text = layout.byline
		byline.TextWrapped = false
		byline.AnchorPoint = Vector2.new(1, 0)
		byline.Position = UDim2.fromScale(label.Position.X.Scale, top)
		byline.Size = UDim2.fromScale(label.Size.X.Scale, bylineShare)
		byline:SetAttribute("TextTier", "Small")
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
	fit.MinTextSize = math.min(body, title)
	fit.Parent = label
	local outline = label:FindFirstChild("Outline")
	if outline and outline:IsA("UIStroke") then
		outline:SetAttribute("BaseThickness", 3)
		outline.Thickness = 3
	end
	-- Буквы: золото сверху вниз (светлое — чтобы читалось на золотой «конфете») или радуга
	-- вдоль строки, которая бежит.
	local gradient = Instance.new("UIGradient")
	gradient.Name = "TextFill"
	if style.Rainbow then
		local colors = {}
		for _, color in UIConfig.Rainbow do
			table.insert(colors, UiFx.lighten(color, BIG_RAINBOW_LIGHT))
		end
		gradient.Color = UiFx.sequence(colors)
		gradient.Rotation = 0
		gradient.Parent = label
		trove:Add(UiFx.rainbow(gradient, { speed = 0.35, colors = colors }))
	else
		gradient.Color = UiFx.sequence({ UIConfig.White, UIConfig.White, UIConfig.Palette.Gold.Top })
		gradient.Rotation = 90
		gradient.Parent = label
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
			dressBig(frame, label, style, layout, trove)
		end
	end
	local socket = frame:FindFirstChild("IconSocket")
	local icon = if socket then socket:FindFirstChild("Icon") else nil
	if icon and icon:IsA("TextLabel") then
		icon.Text = look.icon or style.Icon
	end
	if style.Rainbow then
		-- Радужная «конфета»: цвета радуги по лицевой стороне, градиент медленно вращается.
		local face = UiFx.faceOf(frame)
		local fill = face:FindFirstChild("Fill")
		if fill and fill:IsA("UIGradient") then
			fill.Color = UiFx.sequence(UIConfig.Rainbow)
			fill.Rotation = 0
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
		local lip = frame:FindFirstChild("Lip")
		if lip and lip:IsA("GuiObject") then
			lip.BackgroundColor3 = UIConfig.Rarity.Mythic.Lip
		end
	end

	table.insert(active, toast)
	local slot = #active
	frame.Position = slotPosition(slot) - UDim2.fromScale(0, 0.3)
	frame.Visible = true
	frame.Parent = parent

	-- Въезд: сверху в слот с пружиной, значок выскакивает следом, потом блик.
	UiFx.tween(frame, ENTER_TIME, { Position = slotPosition(slot) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UiFx.popIn(frame, { from = if big then 0.3 else 0.5, time = ENTER_TIME })
	if socket and socket:IsA("GuiObject") then
		UiFx.popIn(socket, { from = 0, time = 0.4, delay = 0.12, rotate = -25 })
		trove:Add(task.delay(0.5, function()
			if socket.Parent then
				UiFx.wiggle(socket, if item.kind == "warning" or big then 16 else 9, 3, 0.45)
			end
		end))
	end
	trove:Add(task.delay(0.3, function()
		UiFx.shine(frame, if big then 0.8 else 0.6)
	end))
	if big then
		trove:Add(UiFx.sparkles(frame, { rate = 7, duration = 2, size = 0.45 }))
		trove:Add(UiFx.arpeggio(if style.Rainbow then "Legendary" else "Epic", 0.25))
		local hud = parent.Parent
		if style.Rainbow and hud and hud:IsA("GuiBase2d") then
			-- Мифическая: один раз тонкая радуга по краям экрана — «весь сервер почувствовал».
			trove:Add(task.delay(0.15, function()
				UiFx.edgeVignette(hud, UIConfig.Rainbow, 0.7, nil, MYTHIC_EDGE)
			end))
		end
	elseif item.kind == "success" or item.kind == "base" then
		trove:Add(UiFx.sparkles(frame, { rate = 6, duration = 1.2, size = 0.75 }))
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
		-- Улов на экране держит счётчик (атрибут HUD CounterHold, FishingController): всё это
		-- время — ни одного уведомления.
		hud:GetAttributeChangedSignal("CounterHold"):Connect(onBusyChanged)
	end

	Net.Event("Notify").OnClientEvent:Connect(function(text: any, kind: any)
		if typeof(text) ~= "string" then
			return
		end
		NotifyController.Show(text, if typeof(kind) == "string" then kind else "info")
	end)
end

return NotifyController
