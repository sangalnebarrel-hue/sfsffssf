--!strict
--[[
	CatchFx — помощник карточки улова FishingController (стиль «Симулятор», UI v5): то, что не
	влезло бы в контроллер (у него мало свободных регистров, см. tests/compile_limits). Только
	цвета и движение карточки; где она встаёт — FishingLayout, когда что показывается — сам
	FishingController (раздел «Улов»). Ничего не подключает: только твины и таймеры.

	  • podiumLook / paintPodium — подиум-стойка под рыбой (CatchCard.Pedestal) в цветах редкости:
	    светлая крышка (с тенью рыбы), колонна со ⭐ (светлее цвета редкости → её цвет), тёмное
	    основание; обводки — её тёмный оттенок.
	  • nameColors — имя рыбы: белое → цвет редкости (с тёмной обводкой, как все надписи образца;
	    мифическая — радуга вдоль букв).
	  • birthPoint — где карточка рождается: в точке рыбы над головой; у карточки сбоку от рыбака —
	    там же, но внутри своего места (маленькая карточка не заходит на рыбака и трофей: растёт от
	    своего края к середине).
	  • birth — рождение: летит из этой точки на место (Quint Out), растёт с лёгким перелётом
	    (0.4 → 1.04 → 1) и доворачивается.
	  • slap — «наклейка» «НОВИНКА!» шлёпается на угол окна: падает крупной с доворотом, на касании
	    вздрагивает, белое кольцо и горсть искр; fitStamp — на карточке сбоку от рыбака наклейка и
	    в покое, и в шлепке не вылезает за карточку (ни на рыбака, ни на слово баннера).
	  • popStars — звёзды баннера выскакивают по очереди и качаются.
	  • punchChips — фишки веса и цены поднимаются по очереди с «ударом» (0.85 → 1.1 → 1), «тик»
	    всё выше.
	  • outline — толщина обводки плашки «Симулятора» (Lip) на этом экране, px, × factor («живая»
	    обводка карточки толще): на сколько она рисуется за своим прямоугольником
	    (FishingController держит карточку на 16 px от кнопок по рисунку).
	  • clearRadius — радиус пустой середины лучей сцены слова, чтобы спицы не перечёркивали трофей
	    (огромная мифическая рыба на маленьком телефоне).
	  • stampText / tapHint — надписи штампа мутации и подсказки «закрыть» под размер карточки: на
	    узкой широкой карточке длинные не влезают в строку не мельче 12–13 px (TextScaled тогда
	    рвёт слово посередине) — короче («РАДУГА», «Тапни!»); stampMin — наклейка «НОВИНКА!» на
	    узкой карточке уже (не на имя).
	  • raysClip / raysFrame / raysSize / aimRays / ghostRays — лучи за карточкой: крупные (не
	    меньше RAYS_MIN её высот), но слой CatchRays у карточки рядом с рыбаком обрезает их у его
	    края (ClipsDescendants; полуплоскость по одну сторону от него): до рыбака с трофеем они не
	    достают; спицы сцены слова уходят копией в середину карточки, а за ней вырастают её
	    собственные лучи.
	  • fitChip — подпись фишки начинается правее её значка (узкие фишки маленькой квадратной
	    карточки); floatSpot — куда вылетает «+$4/с» у карточки сбоку от рыбака: над баннером или у
	    внешнего края, а не на окно с рыбой (и не в ряд верхней панели Roblox, и не на наклейку
	    «НОВИНКА!»; места нет — не вылетает).
	  • tankStamp (Этап 3) — штамп садка (CatchCard.TankStamp): что стало с рыбой по Tank из
	    "Caught" — «В САДОК!» (Water), «ЗАМЕНА!» (Leaf), «САДОК ПОЛОН» над «ПРОДАНА» (Sun: рыба
	    продана сразу — причина названа на карточке); тексты — TankConfig.Texts.Stamp; без Tank
	    (садок её не принял) — nil, штамп спрятан. Чистая функция: это НЕ stampText (тот — подгонка
	    штампа мутации). tankRow — наклейка штампа на правом нижнем углу карточки (как «НОВИНКА!»:
	    наклон, свисает за угол; строка не мельче STAMP_TEXT px, у проданной — SOLD_TEXT,
	    stampSize), подсказка «закрыть» — на ряду левее неё (короче, если тесно; не влезает и
	    короткая — штамп важнее, подсказки нет); showTankStamp — штамп шлёпается (slap) своей
	    долей; cardTime — карточку с проданной рыбой видно ещё SOLD_HOLD с после штампа.
	  • Этап 3, копия и цель карточки (design §6.5): money — цена на фишке «$58» (TankRules.FormatMoney,
	    как в кошельке); infoText — «1,2 кг · цена $35» (значение
	    InfoLabel); priceFloat — что вылетает из фишки цены: доход рыбы «+$4/с» (зелёный) или
	    золотое «+$15», если она сразу продана; flyTarget / flyIcon — куда летит карточка и что
	    летит с ней: «sold» — 💵 в кошелёк (Wallet.Money), иначе 🐟 в кнопку «САДОК», её нет (нет
	    базы) — в середину колонки кнопок.
	Всё, что живёт дольше вызова, отменяется уборкой trove (карточка закрылась — хвостов нет).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UIConfig = require(Shared:WaitForChild("Config"):WaitForChild("UIConfig"))
local TankConfig = require(Shared:WaitForChild("Config"):WaitForChild("TankConfig"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local TankRules = require(Shared:WaitForChild("TankRules"))

local CatchFx = {}

-- Широкая карточка уже стольких px — подсказка «закрыть» короткая («Тапни — забрать!» в Body
-- не мельче 13 px — ≈ 114 px строки, это 0.48 ширины карточки).
CatchFx.SHORT_HINT = 238
-- Квадратная карточка уже стольких px — штамп мутации без «×N» (не влезает в строку).
CatchFx.FULL_STAMP = 340
-- Широкая карточка уже стольких px (запасное место у огромного трофея, 0.85–0.95 DockMin) —
-- штамп мутации коротким словом STAMP_SHORT («РАДУЖНАЯ» и без «!» не влезает в строку не мельче
-- 12 px: TextScaled рвал её в «РАДУЖНА / Я», SIMC-C2-01).
CatchFx.SHORT_STAMP = 190
CatchFx.STAMP_SHORT =
	{ ["РАДУЖНАЯ"] = "РАДУГА", ["НЕОНОВАЯ"] = "НЕОН", ["ЗОЛОТАЯ"] = "ЗОЛОТО" }
-- Наклейка «НОВИНКА!» не шире такой доли карточки (но и не уже STAMP_MIN px; не шире, чем в
-- сборщике): на узкой карточке она иначе наезжает на имя.
CatchFx.STAMP_SHARE = 0.5
CatchFx.STAMP_MIN = 84

local WHITE = UIConfig.White
local QUINT, QUAD, BACK = Enum.EasingStyle.Quint, Enum.EasingStyle.Quad, Enum.EasingStyle.Back
local OUT = Enum.EasingDirection.Out

type Style = UIConfig.RarityStyle

-- Рождение карточки: с какого масштаба, до какого перелёта, за сколько (рост; доворот и полёт —
-- за Time, Quint Out: без перелёта по месту, у рыбака).
local BIRTH = { From = 0.4, Peak = 1.04, Grow = 0.24, Settle = 0.18, Time = 0.35, Turn = -6 }

local function after(trove: Trove.Trove, delay: number, fn: () -> ())
	trove:Add(task.delay(delay, fn))
end

-- Подиум (стойка): колонна — от светлого цвета редкости к её цвету, обводки — её тёмный оттенок.
function CatchFx.podiumLook(style: Style): UIConfig.Swatch
	return { Top = UiFx.lighten(style.Top, 0.2), Bottom = style.Bottom, Lip = style.Lip }
end

-- Покрасить подиум: колонна (сам Pedestal), светлая крышка Cap (её видно сверху) и тёмное
-- основание Base.
function CatchFx.paintPodium(pedestal: GuiObject, style: Style)
	UiFx.setCandy(pedestal, CatchFx.podiumLook(style))
	local cap = pedestal:FindFirstChild("Cap")
	if cap and cap:IsA("GuiObject") then
		UiFx.setCandy(
			cap,
			{ Top = UiFx.lighten(style.Top, 0.7), Bottom = UiFx.lighten(style.Top, 0.3), Lip = style.Lip }
		)
	end
	local base = pedestal:FindFirstChild("Base")
	if base and base:IsA("GuiObject") then
		UiFx.setCandy(base, { Top = style.Bottom, Bottom = UiFx.darken(style.Bottom, 0.25), Lip = style.Lip })
	end
end

-- Имя рыбы: заливка (TextFill) и её поворот. Обводка — тёмная (сборщик), как у всех надписей.
function CatchFx.nameColors(rarityId: string, style: Style): (ColorSequence, number)
	if style.Rainbow then
		return UiFx.sequence(UIConfig.Rainbow), 0
	elseif rarityId == "Common" then
		return ColorSequence.new(WHITE, UiFx.lighten(style.Bottom, 0.4)), 90
	end
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, WHITE),
		ColorSequenceKeypoint.new(0.45, style.Top),
		ColorSequenceKeypoint.new(1, style.Bottom),
	}),
		90
end

--[[
	Точка рождения карточки (px родителя): from — где рыба над головой (nil — середина места). У
	карточки сбоку от рыбака (docked) — ближайшая к рыбе точка, где карточка размером BIRTH.From
	ещё целиком на своём месте: она рождается у своего края со стороны рыбака и растёт к середине,
	ни на миг не заходя на рыбака и трофей.
]]
function CatchFx.birthPoint(from: Vector2?, center: Vector2, size: Vector2, docked: boolean): Vector2
	if not from then
		return center
	elseif not docked then
		return from
	end
	local half = size * (1 - BIRTH.From) / 2
	return Vector2.new(
		math.clamp(from.X, center.X - half.X, center.X + half.X),
		math.clamp(from.Y, center.Y - half.Y, center.Y + half.Y)
	)
end

-- Рождение: из start (px) на место rest (Position) — полёт и доворот Quint Out, рост с перелётом.
function CatchFx.birth(card: GuiObject, start: Vector2, rest: UDim2)
	card.Position = UDim2.fromOffset(math.round(start.X), math.round(start.Y))
	UiFx.tween(card, BIRTH.Time, { Position = rest }, QUINT, OUT)
	UiFx.punch(card, { from = BIRTH.From, peak = BIRTH.Peak, up = BIRTH.Grow, settle = BIRTH.Settle })
	card.Rotation = BIRTH.Turn
	UiFx.tween(card, BIRTH.Time, { Rotation = 0 }, QUINT, OUT)
end

--[[
	«НОВИНКА!» шлёпается, как наклейка: падает крупной (peak, по умолчанию 2.4; на карточке сбоку
	от рыбака — fitStamp: не крупнее SLAP_DOCKED) с доворотом (−18°; с меньшего размера — −10°) и
	садится (Back Out), на касании вздрагивает (лёгкая тряска), от неё — белое кольцо и горсть
	искр (в слое layer, точка at — её середина в долях слоя). Возвращает stop искр (в уборку
	карточки).
]]
function CatchFx.slap(stamp: GuiObject, layer: GuiBase2d, at: Vector2, trove: Trove.Trove, peak: number?): () -> ()
	local scale = UiFx.scaleOf(stamp)
	local from = peak or 2.4
	scale.Scale = from
	UiFx.tween(scale, 0.26, { Scale = 1 }, BACK, OUT)
	local rest = stamp.Rotation
	stamp.Rotation = rest - (if from < 2 then 10 else 18)
	UiFx.tween(stamp, 0.26, { Rotation = rest }, BACK, OUT)
	local sparks: () -> () = function() end
	after(trove, 0.16, function()
		if not stamp.Visible then
			return
		end
		UiFx.shake(stamp, 0.012, 0.16)
		UiFx.glowRing(stamp, { color = WHITE, scale = 1.35, thickness = 3, time = 0.32 })
		sparks = UiFx.burst(layer, {
			origin = at,
			count = 8,
			colors = { WHITE, UIConfig.Palette.Berry.Top, UIConfig.Palette.Gold.Top },
			power = 0.55,
			z = 13,
		})
		UiFx.sound("pop", 0.45, 1.35)
	end)
	return function()
		sparks()
	end
end

-- Звёзды баннера выскакивают по очереди (с доворотом наружу) и, встав, качаются.
function CatchFx.popStars(banner: GuiObject, delay: number, trove: Trove.Trove)
	for index, name in { "StarLeft", "StarRight" } do
		local star = banner:FindFirstChild(name)
		if star and star:IsA("GuiObject") then
			local wait = delay + (index - 1) * 0.06
			UiFx.popIn(star, { from = 0, time = 0.3, delay = wait, rotate = if index == 1 then -40 else 40 })
			after(trove, wait + 0.3, function()
				UiFx.wiggle(star, 16, 3, 0.5)
			end)
		end
	end
end

--[[
	Фишки поднимаются по очереди (через gap): каждая — из-под своего места (на rise px ниже) с
	«ударом» 0.85 → 1.1 → 1, «тик» всё выше (1.1 → 1.25). homes — их места «в покое».
]]
function CatchFx.punchChips(chips: { GuiObject }, homes: { UDim2 }, rise: number, gap: number, trove: Trove.Trove)
	for index, chip in chips do
		local home = homes[index]
		after(trove, (index - 1) * gap, function()
			chip.Position = home + UDim2.fromOffset(0, math.round(rise))
			UiFx.tween(chip, 0.25, { Position = home }, QUAD, OUT)
			UiFx.punch(chip, { from = 0.85, peak = 1.1, up = 0.1, settle = 0.22 })
			UiFx.sound("tick", 0.3, 1.1 + 0.15 * (index - 1) / math.max(#chips - 1, 1))
		end)
	end
end

--[[
	Сколько px от центра лучей at (точка рыбы) до самого дальнего края трофея trophy по осям —
	радиус пустой середины, при котором спицы начинаются за рыбой (по диагонали они могут чуть
	задеть её углы — так лучи не сжимаются в огрызки). nil — трофея не видно.
]]
function CatchFx.clearRadius(trophy: { x0: number, y0: number, x1: number, y1: number }?, at: Vector2): number?
	if not trophy then
		return nil
	end
	return math.max(at.X - trophy.x0, trophy.x1 - at.X, at.Y - trophy.y0, trophy.y1 - at.Y, 0)
end

-- Штамп мутации: «ЗОЛОТАЯ ×2!»; на широкой карточке (телефон) и на квадратной уже FULL_STAMP px
-- (сбоку от рыбака) штамп маленький — без «×N» («×N» и так впечатывается в угол фишки цены); на
-- широкой уже SHORT_STAMP — коротким словом («РАДУГА»). room — ширина строки штампа, px: и из
-- этого — первое, что в ней помещается не мельче 12 px (маленькая квадратная карточка у огромного
-- трофея: «РАДУЖНАЯ!» иначе рвалась в «РАДУЖНА / Я!»).
function CatchFx.stampText(name: string, multiplier: number, wide: boolean, width: number?, room: number?): string
	local upper = TextUtil.upper(name)
	local short = CatchFx.STAMP_SHORT[upper] or upper
	local text = if wide
			and width
			and width < CatchFx.SHORT_STAMP
		then short
		elseif wide or (width and width < CatchFx.FULL_STAMP) then `{upper}!`
		else `{upper} ×{multiplier}!`
	if room then
		for _, candidate in { text, `{upper}!`, upper, short } do
			if UiFx.textWidth(candidate, 12) * 1.05 <= room then -- (+5 %: оценка по буквам, с запасом)
				return candidate
			end
		end
		return short
	end
	return text
end

--[[
	Наименьший размер наклейки «НОВИНКА!» (её UISizeConstraint) под ширину карточки width: не
	шире STAMP_SHARE карточки (на узкой карточке у огромного трофея она иначе закрывает начало
	имени), но не уже STAMP_MIN (текст не мельче 12 px) и не шире, чем в сборщике (RestMin).
]]
function CatchFx.stampMin(stamp: GuiObject, width: number)
	local cap = stamp:FindFirstChildOfClass("UISizeConstraint")
	if not cap then
		return
	end
	local rest = cap:GetAttribute("RestMin")
	if typeof(rest) ~= "Vector2" then
		rest = cap.MinSize
		cap:SetAttribute("RestMin", rest)
	end
	local full = rest :: Vector2
	local w = math.clamp(width * CatchFx.STAMP_SHARE, math.min(CatchFx.STAMP_MIN, full.X), full.X)
	cap.MinSize = Vector2.new(math.round(w), math.round(w * full.Y / math.max(full.X, 1)))
end

-- Штамп садка (Этап 3): цвет плашки (UIConfig.Palette) по исходу TankResult.Result. Рыба продана
-- сразу — Sun (как уведомление «Садок полон…»), не золото: золотая надпись под золотой фишкой
-- цены не читалась (UX-01).
CatchFx.TANK_STAMP = { stored = "Water", replaced = "Leaf", sold = "Sun" } :: { [string]: string }

-- Штамп садка на карточке: (текст, токен цвета, строка причины над ним или nil) по Tank из
-- "Caught"; рыба продана сразу — причина «САДОК ПОЛОН» над «ПРОДАНА» (ребёнок видит, ПОЧЕМУ
-- хорошая рыба ушла); без Tank / незнакомый исход — nil (штамп спрятан).
function CatchFx.tankStamp(result: any): (string?, string?, string?)
	local kind = if type(result) == "table" then result.Result else nil
	local token = if type(kind) == "string" then CatchFx.TANK_STAMP[kind] else nil
	if not token then
		return nil, nil, nil
	end
	local stamp = TankConfig.Texts.Stamp
	return stamp[kind], token, if kind == "sold" then stamp.full else nil
end

-- Штамп садка — наклейка, как «НОВИНКА!» на окне рыбы (ART-04): шлёпается на правый нижний угол
-- карточки, наклон STAMP_TILT, свисает за правый край на OVER_X своей ширины и за нижний — на
-- OVER_Y своей высоты (широкая карточка телефона — OVER_WIDE: так наклейка не ложится на фишку
-- цены над ней; квадратная — ниже лишь чуть-чуть: под ней на планшете джойстик), ряду подсказки
-- «закрыть» остаётся место левее. Строка надписи — STAMP_SHARE высоты карточки, но не мельче
-- STAMP_TEXT px (плашка ≥ 26 px) и не крупнее STAMP_MAX; надпись в одну строку — STAMP_LABEL
-- высоты плашки. Рыба продана сразу — две строки: «ПРОДАНА» SOLD_TEXT..SOLD_MAX px (MAIN2
-- высоты плашки, внизу; выше — наклейка легла бы на фишку цены), над ней причина «САДОК ПОЛОН»
-- (SUB2 высоты). По ширине надписи —
-- STAMP_INNER плашки. Между подсказкой и штампом — STAMP_GAP высоты ряда.
CatchFx.STAMP_TEXT = 19
CatchFx.SOLD_TEXT = 19
CatchFx.SOLD_MAX = 22
CatchFx.STAMP_MAX = 26
CatchFx.STAMP_SHARE = 0.11
CatchFx.STAMP_TILT = -8
CatchFx.STAMP_LABEL = 0.72 -- надпись штампа в одну строку — такая доля высоты плашки (Fishing.luau)
CatchFx.STAMP_MAIN2 = 0.42 -- … в две: «ПРОДАНА» (её низ — на 0.9 плашки) …
CatchFx.STAMP_SUB2 = 0.34 -- … и причина над ней (её верх — на 0.08 плашки)
CatchFx.STAMP_INNER = 0.88 -- … и такая доля ширины
CatchFx.OVER_X = 0.12
CatchFx.OVER_Y = 0.15
CatchFx.OVER_WIDE = 0.45
CatchFx.STAMP_GAP = 0.3
-- Рыба продана сразу: карточка сама закрывается не раньше, чем через SOLD_HOLD с после доли
-- штампа (шлепок ≈ 0.3 с + полторы секунды его читать).
CatchFx.SOLD_HOLD = 1.8

-- Видно ли на экране (сам и все предки-GuiObject).
local function shown(gui: Instance?): boolean
	local node: Instance? = gui
	while node and node:IsA("GuiObject") do
		if not node.Visible then
			return false
		end
		node = node.Parent
	end
	return gui ~= nil
end

-- Ширина строки Montserrat Heavy (UiFx.textWidth) с запасом на обводку.
local function lineWidth(text: string, px: number): number
	return UiFx.textWidth(text, px) * 1.08 + 4
end

-- Размер наклейки штампа (px) на карточке высотой cardH: (ширина, высота, px надписи, px строки
-- причины) для надписи text и причины sub (или nil — одна строка); outline — обводка плашки, px.
function CatchFx.stampSize(text: string, sub: string?, cardH: number, outline: number): (number, number, number, number)
	local least = if sub then CatchFx.SOLD_TEXT else CatchFx.STAMP_TEXT
	local most = if sub then CatchFx.SOLD_MAX else CatchFx.STAMP_MAX
	local px = math.clamp(cardH * CatchFx.STAMP_SHARE, least, math.max(most, least))
	local plateH = px / (if sub then CatchFx.STAMP_MAIN2 else CatchFx.STAMP_LABEL)
	local subPx = if sub then plateH * CatchFx.STAMP_SUB2 else 0
	local lineW = lineWidth(text, px)
	if sub then
		lineW = math.max(lineW, lineWidth(sub, subPx))
	end
	return lineW / CatchFx.STAMP_INNER + outline * 2, plateH, px, subPx
end

-- Штамп садка и подсказка «закрыть» (после placeCard: подсказка уже на месте своей раскладки,
-- card — размер карточки в px): наклейка штампа на правом нижнем углу карточки, свисает за него
-- (OVER_X / OVER_Y), наклон STAMP_TILT; подсказка — на ряду левее неё: полная, короткая или
-- никакой (штамп важнее). Без штампа подсказка — во весь ряд (tapHint). Возвращает, виден ли
-- текст подсказки. wide — ширина широкой карточки (px; nil — квадратная): подсказка без штампа,
-- как tapHint. Рыба продана сразу — две строки: Sub «САДОК ПОЛОН» над Label «ПРОДАНА».
function CatchFx.tankRow(
	stamp: GuiObject,
	hint: TextLabel,
	tank: any,
	card: Vector2,
	touch: boolean,
	wide: number?
): boolean
	-- (видимость штампа не трогает: прячет его fillCard, а раскладку зовут и на поворот экрана)
	local text, token, sub = CatchFx.tankStamp(tank)
	local rowW = hint.Size.X.Scale * card.X
	if not text or not token then
		hint.Text = CatchFx.tapHint(touch, wide)
		return true
	end
	local label = stamp:FindFirstChild("Label")
	local subLabel = stamp:FindFirstChild("Sub")
	if label and label:IsA("TextLabel") then
		label.Text = text
		-- одна строка — посередине плашки; две — «ПРОДАНА» внизу (низ на 0.9), причина над ней
		label.Position = UDim2.fromScale(0.5, if sub then 0.9 - CatchFx.STAMP_MAIN2 / 2 else 0.5)
		label.Size = UDim2.fromScale(CatchFx.STAMP_INNER, if sub then CatchFx.STAMP_MAIN2 else CatchFx.STAMP_LABEL)
	end
	if subLabel and subLabel:IsA("TextLabel") then
		subLabel.Visible = sub ~= nil
		subLabel.Text = sub or ""
		subLabel.Position = UDim2.fromScale(0.5, 0.08 + CatchFx.STAMP_SUB2 / 2)
		subLabel.Size = UDim2.fromScale(CatchFx.STAMP_INNER, CatchFx.STAMP_SUB2)
	end
	UiFx.setCandy(stamp, token)
	local plateW, plateH = CatchFx.stampSize(text, sub, card.Y, CatchFx.outline(stamp))
	-- Наклейка на углу: середина — на (1 − OVER) её размера внутрь от угла.
	local overY = if wide then CatchFx.OVER_WIDE else CatchFx.OVER_Y
	local cx = card.X - plateW * (0.5 - CatchFx.OVER_X)
	local cy = card.Y - plateH * (0.5 - overY)
	stamp.AnchorPoint = Vector2.new(0.5, 0.5)
	stamp.Position = UDim2.fromScale(cx / card.X, cy / card.Y)
	stamp.Size = UDim2.fromScale(plateW / card.X, plateH / card.Y)
	stamp.Rotation = CatchFx.STAMP_TILT
	-- Подсказка — на ряду левее наклейки (её ряд — у нижнего края, наклейка заходит на него).
	local rowH = hint.Size.Y.Scale * card.Y
	local gap = rowH * CatchFx.STAMP_GAP
	local x0 = hint.Position.X.Scale - hint.AnchorPoint.X * hint.Size.X.Scale -- левый край ряда (доля)
	local rowTop = (hint.Position.Y.Scale - hint.AnchorPoint.Y * hint.Size.Y.Scale) * card.Y
	local stampTop = cy - plateH / 2
	local stampLeft = cx - plateW / 2
	local room = if rowTop + rowH <= stampTop then rowW else math.min(rowW, stampLeft - gap - x0 * card.X)
	local bodyPx = UiFx.textSize("Body") - 2 -- (fitText: Min = Max − 2)
	local full, short = CatchFx.tapHint(touch, nil), CatchFx.tapHint(touch, 0)
	local hintText = if lineWidth(full, bodyPx) <= room
		then full
		elseif lineWidth(short, bodyPx) <= room then short
		else ""
	if hintText ~= "" and room < rowW then
		hint.AnchorPoint = Vector2.new(0, hint.AnchorPoint.Y)
		hint.Position = UDim2.new(x0, 0, hint.Position.Y.Scale, hint.Position.Y.Offset)
		hint.Size = UDim2.fromScale(math.max(room, 1) / card.X, hint.Size.Y.Scale)
	end
	hint.Text = hintText
	return hintText ~= ""
end

-- Когда карточка закрывается сама (с от её появления): base (по редкости и последней доле), но
-- рыбу, проданную сразу, — не раньше SOLD_HOLD с после доли штампа stampAt: «САДОК ПОЛОН /
-- ПРОДАНА» успевают прочесть (UX-01; обычная карточка закрылась бы через ≈ 1 с после него).
function CatchFx.cardTime(base: number, stampAt: number, tank: any): number
	if CatchFx.isSold(tank) then
		return math.max(base, stampAt + CatchFx.SOLD_HOLD)
	end
	return base
end

-- Штамп садка шлёпается (доля карточки): наклейкой с доворотом (slap; instant — сразу на месте);
-- at — его середина в долях слоя layer (искры).
function CatchFx.showTankStamp(stamp: GuiObject, layer: GuiBase2d, at: Vector2, trove: Trove.Trove, instant: boolean)
	stamp.Visible = true
	if instant then
		UiFx.scaleOf(stamp).Scale = 1
		return
	end
	trove:Add(CatchFx.slap(stamp, layer, at, trove, CatchFx.SLAP_DOCKED))
	UiFx.sound("swoosh", 0.3, 1.3)
end

-- Цена на фишке цены карточки (и её набегание): «$58» — тем же видом, что кошелёк, панель и
-- всплывающие суммы (TankRules.FormatMoney; был голый «58» рядом с «+$5.2/с», UX-06).
function CatchFx.money(value: number): string
	return TankRules.FormatMoney(value)
end

-- Сводка карточки (значение InfoLabel.Text): «1,2 кг · цена $35».
function CatchFx.infoText(kg: string, value: number): string
	return `{kg} · цена {TankRules.FormatMoney(value)}`
end

-- Что вылетает из фишки цены: (текст, цвета сверху вниз) — доход рыбы «+$4/с» в цвете денег или,
-- если её сразу продали (садок полон), золотое «+$15» (её цена).
function CatchFx.priceFloat(income: number, tank: any): (string, { Color3 })
	if type(tank) == "table" and tank.Result == "sold" and typeof(tank.Price) == "number" and tank.Price > 0 then
		return "+" .. TankRules.FormatMoney(tank.Price), { UIConfig.Palette.Gold.Top, UIConfig.Palette.Sun.Bottom }
	end
	return TankRules.FormatRate(TankRules.Income10(income)),
		{ WHITE:Lerp(UIConfig.MoneyText, 0.55), UIConfig.MoneyText }
end

-- Куда летит карточка: рыба сразу продана — в кошелёк (Wallet.Money, если виден), иначе — в
-- кнопку «САДОК»; её нет (нет базы) — в середину колонки кнопок справа.
function CatchFx.flyTarget(button: GuiObject, wallet: GuiObject, tank: any): GuiObject
	if type(tank) == "table" and tank.Result == "sold" and shown(wallet) then
		return wallet
	end
	if shown(button) then
		return button
	end
	local column = button.Parent
	return if column and column:IsA("GuiObject") then column else button
end

-- Рыба продана сразу (садок полон, она слабее всех).
function CatchFx.isSold(tank: any): boolean
	return type(tank) == "table" and tank.Result == "sold"
end

-- Что летит с карточкой: 💵 — рыба продана сразу (монеты в кошелёк), иначе 🐟.
function CatchFx.flyIcon(tank: any): string
	return if type(tank) == "table" and tank.Result == "sold" then "💵" else "🐟"
end

-- Подсказка «закрыть» по устройству; на узкой широкой карточке (width — её ширина, px) — короткая.
function CatchFx.tapHint(touch: boolean, width: number?): string
	if width and width < CatchFx.SHORT_HINT then
		return if touch then "Тапни!" else "Жми!"
	end
	return if touch then "Тапни — забрать!" else "Жми — забрать!"
end

-- Толщина обводки плашки «Симулятора» (её Lip, см. STYLE.md §6.2) на этом экране (как её
-- ставит сборщик, UiFx.strokeThickness — не текущая, которую может раздувать твин), × factor;
-- 0 — без обводки.
function CatchFx.outline(gui: Instance?, factor: number?): number
	local lip = gui and gui:FindFirstChild("Lip")
	local stroke = lip and lip:FindFirstChildOfClass("UIStroke")
	return if stroke then UiFx.strokeThickness(stroke) * (factor or 1) else 0
end

--------------------------------------------------------------------------------
-- Лучи за карточкой (UI v5, SIMC-C1-01): крупные, но у рыбака обрезаны
--------------------------------------------------------------------------------

-- Лучи за карточкой — не меньше стольких её высот в поперечнике (видны вокруг неё и у
-- карточки сбоку от рыбака).
CatchFx.RAYS_MIN = 1.6

local function whole(v: number): number
	return if v == v and math.abs(v) < 1e6 then math.round(v) else 0
end

type Rect = { x0: number, y0: number, x1: number, y1: number }

--[[
	Где лучи карточки видны (UI v5, SIMC-C1-01), px HUD.Fishing размера root: карточка center /
	size стоит рядом с рыбаком с трофеем keepout (сбоку или запасное место у огромного трофея) —
	полуплоскость по одну сторону от него (слева, справа, над или под ним), где карточки больше
	всего (при равенстве — сбоку); лучи в ней крупные, но до рыбака с трофеем не достают.
]]
function CatchFx.raysClip(keepout: Rect, center: Vector2, size: Vector2, root: Vector2): Rect
	local far = 3 * math.max(root.X, root.Y, 1)
	local card = {
		x0 = center.X - size.X / 2,
		y0 = center.Y - size.Y / 2,
		x1 = center.X + size.X / 2,
		y1 = center.Y + size.Y / 2,
	}
	local candidates: { Rect } = {
		{ x0 = -far, y0 = -far, x1 = keepout.x0, y1 = far },
		{ x0 = keepout.x1, y0 = -far, x1 = far, y1 = far },
		{ x0 = -far, y0 = -far, x1 = far, y1 = keepout.y0 },
		{ x0 = -far, y0 = keepout.y1, x1 = far, y1 = far },
	}
	local best, bestArea = candidates[1], -1
	for _, clip in candidates do
		local area = math.max(0, math.min(card.x1, clip.x1) - math.max(card.x0, clip.x0))
			* math.max(0, math.min(card.y1, clip.y1) - math.max(card.y0, clip.y0))
		if area > bestArea + 0.5 then
			best, bestArea = clip, area
		end
	end
	return best
end

--[[
	Слой лучей (CatchRays) — «окно», где их видно (px HUD.Fishing размера root): clip (raysClip:
	карточка рядом с рыбаком — по одну сторону от него, ClipsDescendants) или nil — без обрезки
	(втрое больше экрана: лучи слова у рыбы над головой, карточка посередине).
]]
function CatchFx.raysFrame(rays: GuiObject, root: Vector2, clip: Rect?)
	local left, top, right, bottom = -root.X, -root.Y, 2 * root.X, 2 * root.Y
	local x0: number = if clip then math.clamp(clip.x0, left, right) else left
	local x1: number = if clip then math.clamp(clip.x1, left, right) else right
	local y0: number = if clip then math.clamp(clip.y0, top, bottom) else top
	local y1: number = if clip then math.clamp(clip.y1, top, bottom) else bottom
	rays.AnchorPoint = Vector2.zero
	rays.SizeConstraint = Enum.SizeConstraint.RelativeXY
	rays.Rotation = 0
	rays.Position = UDim2.fromOffset(whole(x0), whole(y0))
	rays.Size = UDim2.fromOffset(whole(math.max(x1 - x0, 0)), whole(math.max(y1 - y0, 0)))
	rays.ClipsDescendants = clip ~= nil
end

-- Поперечник лучей, px: size высот карточки height, не больше maxPx; за карточкой (не сцена
-- слова, hole = false) — не меньше RAYS_MIN её высот.
function CatchFx.raysSize(size: number, height: number, maxPx: number, hole: boolean): number
	local across = math.min(size * height, maxPx)
	return if hole then across else math.max(across, CatchFx.RAYS_MIN * height)
end

-- Кольцо лучей (UiFx.rays(…).holder в слое rays) — с центром center (px HUD.Fishing) и
-- поперечником across px.
function CatchFx.aimRays(holder: GuiObject, rays: GuiObject, center: Vector2, across: number)
	local origin = Vector2.new(rays.Position.X.Offset, rays.Position.Y.Offset)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.SizeConstraint = Enum.SizeConstraint.RelativeXY
	holder.Position = UDim2.fromOffset(whole(center.X - origin.X), whole(center.Y - origin.Y))
	holder.Size = UDim2.fromOffset(whole(across), whole(across))
end

--[[
	Спицы сцены слова уходят за карточку: их копии (в слое layer, над затемнением; без обрезки)
	летят в её середину to (px слоя), докручиваясь, и сжимаются за 0.3 с — а за карточкой
	вырастают её собственные лучи (обрезанные у рыбака).
]]
function CatchFx.ghostRays(rays: GuiObject, layer: GuiObject, to: Vector2, trove: Trove.Trove)
	local origin = UDim2.fromOffset(rays.Position.X.Offset, rays.Position.Y.Offset)
	for _, holder in rays:GetChildren() do
		if holder.Name == "FxRays" and holder:IsA("GuiObject") then
			local ghost = holder:Clone()
			ghost.Name = "FxRaysGhost"
			ghost.Position = holder.Position + origin
			ghost.ZIndex = rays.ZIndex
			ghost.Parent = layer
			trove:Add(ghost)
			UiFx.tween(ghost, 0.3, {
				Position = UDim2.fromOffset(whole(to.X), whole(to.Y)),
				Rotation = ghost.Rotation + 25,
			}, QUAD, OUT)
			UiFx.tween(UiFx.scaleOf(ghost), 0.3, { Scale = 0 }, QUAD, Enum.EasingDirection.In)
			after(trove, 0.32, function()
				ghost:Destroy()
			end)
		end
	end
end

--------------------------------------------------------------------------------
-- Наклейка, фишки, «+$4/с» у карточки сбоку от рыбака (UI v5, SIMC-C1-02 / 03 / 05)
--------------------------------------------------------------------------------

-- Наклейка «НОВИНКА!» на карточке сбоку от рыбака шлёпается не крупнее стольких своих размеров.
CatchFx.SLAP_DOCKED = 1.6

--[[
	Наклейка «НОВИНКА!» на карточке сбоку от рыбака (её прямоугольник «в покое» pos / size и
	карточка ниже баннера area — px одного слоя): в покое не вылезает за карточку по ширине (на
	маленькой карточке наклейка не уже 96 px и свисала бы к рыбаку), а шлёпается не крупнее
	SLAP_DOCKED (и не шире карточки), растя туда, где у неё есть место (точка опоры UIScale —
	AnchorPoint — по свободному месту с каждой стороны): ни на рыбака, ни на слово баннера.
	Ставит наклейку (AnchorPoint и Position; её прямоугольник «в покое» не меняется, кроме сдвига
	внутрь) и возвращает, с какого размера шлёпаться.
]]
function CatchFx.fitStamp(
	stamp: GuiObject,
	pos: Vector2,
	size: Vector2,
	area: { x0: number, y0: number, x1: number, y1: number }
): number
	local dx = 0
	if size.X <= area.x1 - area.x0 then
		dx = math.max(area.x0 - pos.X, 0) - math.max(pos.X + size.X - area.x1, 0)
	end
	local x0, y0 = pos.X + dx, pos.Y
	local x1, y1 = x0 + size.X, y0 + size.Y
	local peak =
		math.clamp(math.min(CatchFx.SLAP_DOCKED, (area.x1 - area.x0) / math.max(size.X, 1)), 1, CatchFx.SLAP_DOCKED)
	local function anchor(before: number, after: number): number
		before, after = math.max(before, 0), math.max(after, 0)
		return if before + after > 0 then before / (before + after) else 0.5
	end
	local new = Vector2.new(anchor(x0 - area.x0, area.x1 - x1), anchor(y0 - area.y0, area.y1 - y1))
	local old = stamp.AnchorPoint
	stamp.AnchorPoint = new
	stamp.Position = stamp.Position
		+ UDim2.fromOffset(whole(dx + (new.X - old.X) * size.X), whole((new.Y - old.Y) * size.Y))
	return peak
end

-- Значок фишки, чтобы не наезжать на её подпись, уменьшается до стольких своих размеров.
CatchFx.CHIP_ICON_MIN = 0.86

-- Размер элемента из сборщика (запоминается в атрибут RestSize при первой подгонке).
local function restSize(gui: GuiObject): UDim2
	local rest = gui:GetAttribute("RestSize")
	if typeof(rest) ~= "UDim2" then
		gui:SetAttribute("RestSize", gui.Size)
		return gui.Size
	end
	return rest
end

--[[
	Подпись фишки (вес, цена) не заходит под её выступающий значок (+3 px; правый край подписи —
	на месте; SIMC-C1-05): на узкой фишке квадратной карточки сбоку от рыбака значок сначала
	становится меньше (до CHIP_ICON_MIN своего размера), потом подпись начинается правее него.
	size — фишка «в покое», px. На широкой фишке всё как в сборщике.
]]
function CatchFx.fitChip(chip: GuiObject, size: Vector2)
	local icon = chip:FindFirstChild("Icon")
	local label = chip:FindFirstChild("Label")
	if not (icon and label and icon:IsA("GuiObject") and label:IsA("GuiObject")) or size.X <= 0 then
		return
	end
	local iconRest, labelRest = restSize(icon), restSize(label)
	local width = labelRest.X.Scale * size.X + labelRest.X.Offset
	local right = label.Position.X.Scale * size.X + label.Position.X.Offset + (1 - label.AnchorPoint.X) * width
	local left = right - width
	-- Значок (RelativeYY): его правый край — at + (1 − AnchorPoint.X) × scale × высота фишки.
	local at = icon.Position.X.Scale * size.X + icon.Position.X.Offset
	local reach = (1 - icon.AnchorPoint.X) * size.Y
	local scale = iconRest.X.Scale
	if reach > 0 then
		scale = math.clamp((left - 3 - at) / reach, iconRest.X.Scale * CatchFx.CHIP_ICON_MIN, iconRest.X.Scale)
	end
	icon.Size = if scale >= iconRest.X.Scale
		then iconRest
		else UDim2.new(
			scale,
			iconRest.X.Offset,
			scale * iconRest.Y.Scale / math.max(iconRest.X.Scale, 1e-6),
			iconRest.Y.Offset
		)
	local fit = math.min(width, right - (at + reach * scale + 3))
	label.Size = if fit >= width
		then labelRest
		else UDim2.new(math.max(fit, width * 0.5) / size.X, 0, labelRest.Y.Scale, labelRest.Y.Offset)
	-- Нижний предел текста — не выше 0.8 высоты подписи (не меньше 12 px): иначе на маленькой
	-- фишке «2 400» не влезает в строку не мельче Button − 2 и TextScaled рвёт число.
	local limits = label:FindFirstChildOfClass("UITextSizeConstraint")
	if limits then
		local restMin = label:GetAttribute("RestMin")
		if type(restMin) ~= "number" then
			restMin = limits.MinTextSize
			label:SetAttribute("RestMin", restMin)
		end
		local boxHeight = labelRest.Y.Scale * size.Y + labelRest.Y.Offset
		limits.MinTextSize = math.max(12, math.min(restMin :: number, math.floor(boxHeight * 0.8)))
	end
end

export type FloatSpot = {
	root: Vector2, -- HUD.Fishing, px
	card: { x0: number, y0: number, x1: number, y1: number }, -- «отпечаток» карточки (с баннером)
	side: number, -- карточка слева (−1) или справа (1) от рыбака
	edge: number, -- его край с её стороны
	window: { x0: number, y0: number, x1: number, y1: number }, -- окно рыбы на карточке
	source: Vector2, -- откуда вылетает (фишка цены)
	perHeight: number, -- ширина надписи в её высотах
	want: number, -- высота надписи, px
	least: number, -- … не меньше (иначе — следующее место)
	gap: number, -- зазор до карточки, px
	-- свободно по X в полосе (sideLimits; и не у кнопок меню и чата Roblox вверху слева)
	limits: (top: number, bottom: number) -> (number, number),
	rise: number?, -- на столько px надпись поднимается, уже долетев (UiFx.floatText rise): её верх
	-- на пике подъёма тоже в полосе (не в ряду верхней панели Roblox)
	sticker: { x0: number, y0: number, x1: number, y1: number }?, -- «НОВИНКА!» на окне (рисунок), nil — нет
}

--[[
	Куда вылетает «+$4/с» у карточки сбоку от рыбака (SIMC-C1-03: не на окно с рыбой — ребёнок как
	раз смотрит на свою рыбу): над баннером, если там помещается надпись не ниже least (по X — над
	карточкой, не за край рыбака; с подъёмом rise — не выше верха HUD и, у верхней панели Roblox, не
	левее её кнопок: limits); иначе — у внешнего края карточки (от рыбака) на высоте цены, иначе —
	под карточкой; нет и там — на верхнюю полоску окна у его правого края (центр — 0.18 его высоты,
	высота — не больше 0.3 окна) правее наклейки «НОВИНКА!» (sticker; SIMC-C2-02: на узком окне
	телефона надпись иначе ложилась на неё) и тает раньше (третье — true). Возвращает центр и
	высоту надписи; nil — места нет нигде (тогда «+$4/с» не вылетает: фишка цены и так пружинит и
	сыплет искры, а цена — самое крупное число карточки).
]]
function CatchFx.floatSpot(o: FloatSpot): (Vector2?, number, boolean)
	local rise = o.rise or 0
	-- Над баннером или под карточкой (room — высота полосы; down — под карточкой): по X — над
	-- ней, не за край рыбака.
	local function band(room: number, down: boolean): (Vector2?, number)
		local h = math.min(o.want, room)
		if h < o.least then
			return nil, h
		end
		local cy = if down then o.card.y1 + o.gap + h / 2 else o.card.y0 - o.gap - h / 2
		local left, right = o.limits(cy - h / 2 - rise, cy + h / 2)
		if o.side < 0 then
			right = math.min(right, o.edge - o.gap)
		else
			left = math.max(left, o.edge + o.gap)
		end
		h = math.min(h, (right - left) / o.perHeight)
		if h < o.least then
			return nil, h
		end
		local half = h * o.perHeight / 2
		local cx = math.clamp((o.card.x0 + o.card.x1) / 2, left + half, math.max(left + half, right - half))
		return Vector2.new(cx, cy), h
	end
	local above, high = band(o.card.y0 - o.gap - 4 - rise, false)
	if above then
		return above, high, false
	end
	-- У внешнего края карточки, на высоте цены.
	local y = math.max(o.source.Y, o.want / 2 + 4 + rise)
	local left, right = o.limits(y - o.want / 2 - rise, y + o.want / 2)
	local room = if o.side < 0 then o.card.x0 - o.gap - left else right - (o.card.x1 + o.gap)
	local h = math.min(o.want, room / o.perHeight)
	if h >= o.least then
		local w = h * o.perHeight
		local cx = if o.side < 0 then o.card.x0 - o.gap - w / 2 else o.card.x1 + o.gap + w / 2
		return Vector2.new(cx, math.clamp(y, h / 2 + 4 + rise, o.root.Y - h / 2 - 4)), h, false
	end
	-- Под карточкой.
	local below, low = band(o.root.Y - 4 - o.card.y1 - o.gap, true)
	if below then
		return below, low, false
	end
	-- Верхняя полоска окна (у его правого края; правее наклейки «НОВИНКА!», если она в этой
	-- полоске) — и тает раньше. Не влезает не ниже least — места нет.
	local window = o.window
	local ww, wh = window.x1 - window.x0, window.y1 - window.y0
	local from, to = window.x0 + ww * 0.02, window.x1 - ww * 0.02
	h = math.min(o.want, wh * 0.3)
	local cy = window.y0 + wh * 0.18
	local sticker = o.sticker
	if sticker and sticker.y1 > cy - h / 2 and sticker.y0 < cy + h / 2 then
		from = math.max(from, sticker.x1 + o.gap)
	end
	h = math.min(h, math.max(to - from, 0) / o.perHeight)
	if h < o.least then
		return nil, h, true
	end
	return Vector2.new(to - h * o.perHeight / 2, cy), h, true
end

return CatchFx
