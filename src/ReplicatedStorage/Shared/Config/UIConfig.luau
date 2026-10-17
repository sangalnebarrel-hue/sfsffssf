--!strict
--[[
	UIConfig — общие настройки интерфейса «Симулятор» (UI v5, как у популярных симуляторов Roblox:
	сочные кнопки с градиентом, толстая тёмная обводка в цвет кнопки, жирный белый текст с
	обводкой, крупные наклонные цифры без плашки, огромные заголовки с тенью, полупрозрачные
	тёмные «таблетки»; гладкие поверхности — LEGO остаётся только на карте). Здесь: уведомления,
	палитра, стили редкостей и мутаций, виды уведомлений, конфетти, шрифт (Font), устройство
	кнопки (Sim), движение (Motion) и лимиты эффектов (Fx). Стиль — tools/builder/gui/STYLE.md.

	Модуль «чистый» (без require, только Color3): его читают и клиент (контроллеры, UiFx), и сборщик
	интерфейса (tools/builder/gui/Theme.luau) — все цвета и числа интерфейса заданы в одном месте.
	Здесь же шкала размеров текста (Type), время карточки улова по редкости (CatchCardTime),
	цвета баз (BaseSwatches, swatchFor) и числа HUD Этапа 3: кошелёк (Wallet) и кнопка «САДОК»
	(TankButton).

	Палитра: у каждого цвета (токена) есть
	  Top    — верх лицевой стороны (светлее),
	  Bottom — низ лицевой стороны (сочнее; градиент сверху вниз),
	  Lip    — обводка: тёмный оттенок того же цвета (яркость ≈ 0.29, как у образца), не чёрный;
	  Alpha  — (только Glass) прозрачность «стекла» вместо градиента и обводки.
	Имена токенов прежние (Sky, Leaf, …) — контроллеры красят ими через UiFx.setCandy. Цвета сняты
	с образца: Leaf — салатовый («ЛОВИ!», успех), Sky — голубой («ЗАБРОСИТЬ», инфо), Berry —
	красный, Sun — оранжевый («ПОДСЕЧЬ!»), Gold — жёлтый («ВЗЯТЬ», цена), Grape — фиолетовый
	(«ДОМОЙ»), Pink, Mint — бирюзовый, Slate — светло-серый (неактивное), Night — тёмно-синяя
	панель, Cream — белая карточка, Pond — приглушённая бирюза («ЖДИ КЛЁВА…»), Glass — тёмное
	стекло (подсказка, подпись кнопки, жёлоб).
]]

export type Swatch = {
	Top: Color3,
	Bottom: Color3,
	Lip: Color3,
	Alpha: number?, -- стекло: прозрачность лица (обводки нет)
}

export type RarityStyle = {
	Top: Color3,
	Bottom: Color3,
	Lip: Color3,
	Rainbow: boolean, -- переливается радугой (Mythic)
	Rays: { Color3 }, -- лучи за карточкой улова (чередуются)
	Confetti: { Color3 }, -- цвета конфетти
	ConfettiCount: number, -- сколько конфетти (UiFx всё равно урежет до лимита устройства)
	Flash: boolean, -- «большой» улов: столб света в мире, блик по баннеру карточки, звон ниже
}

export type MutationStyle = {
	Top: Color3,
	Bottom: Color3,
	Lip: Color3,
	Icon: string,
	Effect: string, -- "sparkles" | "pulse" | "rainbow"
}

export type ToastKind = {
	Token: string, -- цвет из Palette
	Icon: string, -- эмодзи слева
	Rainbow: boolean?, -- радужная обводка (вращающийся градиент)
	Big: boolean?, -- крупнее обычного (громкие новости: легендарный и мифический улов)
	Life: number?, -- сколько секунд висит (иначе ToastDuration)
	Priority: number?, -- кого вытеснять первым, когда места нет (меньше — раньше; по умолчанию 1)
}

-- "#RRGGBB" → Color3 (цвета записаны так же, как в STYLE.md).
local function hex(code: string): Color3
	local r = tonumber(string.sub(code, 2, 3), 16) or 0
	local g = tonumber(string.sub(code, 4, 5), 16) or 0
	local b = tonumber(string.sub(code, 6, 7), 16) or 0
	return Color3.fromRGB(r, g, b)
end

local function swatch(top: string, bottom: string, lip: string): Swatch
	return { Top = hex(top), Bottom = hex(bottom), Lip = hex(lip) }
end

-- Цвета радуги (Mythic, мутация «Радужная», радужные конфетти и обводки).
local RAINBOW = {
	hex("#FF3B30"),
	hex("#FF9500"),
	hex("#FFE600"),
	hex("#3CFF1F"),
	hex("#1FE4FF"),
	hex("#3B6BFF"),
	hex("#C04BFF"),
}

-- Сочные цвета «симулятора» (сняты с образца; остальные — по тому же рецепту).
local Palette: { [string]: Swatch } = {
	Leaf = swatch("#8BFA0C", "#3FFF03", "#0A4800"), -- салатовый: «ЛОВИ!», «ЗАБРАТЬ!», успех
	Sky = swatch("#25FCFF", "#03C6FF", "#180149"), -- голубой: «ЗАБРОСИТЬ», инфо
	Berry = swatch("#FF5357", "#F8060B", "#490100"), -- красный: «СМОТАТЬ», опасность, «НОВИНКА!»
	Sun = swatch("#FDC073", "#F77718", "#490C00"), -- оранжевый: «КЛЮЁТ!», «ПОДСЕЧЬ!», внимание
	Gold = swatch("#FFF06A", "#FECE08", "#4B2000"), -- жёлтый: «ВЗЯТЬ», цена, легендарное
	Grape = swatch("#E08CFF", "#A43BFF", "#2C0057"), -- фиолетовый: «ДОМОЙ», эпическое
	Pink = swatch("#FF9AD5", "#FF3FA8", "#4A0029"), -- розовый (цвет базы)
	Mint = swatch("#6CFFE0", "#12D6B0", "#003D33"), -- бирюзовый (цвет базы)
	Slate = swatch("#EEF1F4", "#AEB6BF", "#252B33"), -- светло-серый: неактивное («ЖДЁМ…», нет базы)
	Night = swatch("#4A4F6A", "#23263A", "#06070D"), -- тёмно-синяя панель: мини-игра, мифическое
	Cream = swatch("#FFFFFF", "#DDE6F0", "#141A26"), -- белая карточка улова, клавиша, стрелка
	-- приглушённая бирюза: «ЖДИ КЛЁВА…» — ждём, нажимать не нужно
	Pond = swatch("#A9E4EE", "#58AFC4", "#0B3440"),
	Water = swatch("#6FF2FF", "#13B8D6", "#003A4D"), -- бирюза (вода)
	Coal = swatch("#3C414D", "#14171D", "#000000"), -- чёрная «фишка»
	-- Тёмное стекло (таймер образца): лицо чёрное на Alpha прозрачности, без обводки и градиента.
	Glass = { Top = hex("#0B0D14"), Bottom = hex("#0B0D14"), Lip = hex("#000000"), Alpha = 0.5 },
}

--[[
	Цвета баз (BaseConfig.Colors, ключ — Id): чистые цвета палитры вместо затемнённого цвета
	базы, чтобы плашка «ЛАЗУРНАЯ БАЗА» не выглядела грязной рядом с остальным. Для цвета,
	которого здесь нет, — UIConfig.swatchFor(цвет).
]]
local BaseSwatches: { [string]: Swatch } = {
	Red = Palette.Berry,
	Blue = Palette.Sky,
	Yellow = Palette.Gold,
	Purple = Palette.Grape,
	Orange = Palette.Sun,
	Cyan = Palette.Mint,
	Pink = Palette.Pink,
	Green = swatch("#5FF5A8", "#14C76E", "#00401F"), -- изумрудный (не Leaf: его держит «успех»)
}

-- Кнопка из произвольного цвета: светлый верх, сочный низ (не темнее 0.9 по яркости), обводка —
-- тот же оттенок на яркости 0.29 (как у образца; у серых — тёмно-серая).
local function swatchFor(color: Color3): Swatch
	local h, s, v = color:ToHSV()
	local bottom = Color3.fromHSV(h, math.min(1, s * 1.1), math.max(v, 0.9))
	local edge = if s < 0.15 then Color3.fromHSV(h, s, 0.2) else Color3.fromHSV(h, 1, 0.29)
	return {
		Top = color:Lerp(Color3.new(1, 1, 1), 0.3),
		Bottom = bottom,
		Lip = edge,
	}
end

local function rarity(
	top: string,
	bottom: string,
	lip: string,
	rays: { Color3 },
	confetti: { Color3 },
	count: number,
	flash: boolean
): RarityStyle
	return {
		Top = hex(top),
		Bottom = hex(bottom),
		Lip = hex(lip),
		Rainbow = false,
		Rays = rays,
		Confetti = confetti,
		ConfettiCount = count,
		Flash = flash,
	}
end

local WHITE = hex("#FFFFFF")

-- Редкости: обычная — светло-серая, редкая — синяя, эпическая — фиолетовая, легендарная —
-- жёлтая → оранжевая, мифическая — радуга.
local Rarity: { [string]: RarityStyle } = {
	Common = rarity(
		"#F4F7FA",
		"#B8C2CC",
		"#252B33",
		{ hex("#FFFFFF"), hex("#DDE3EA") },
		{ WHITE, hex("#DDE3EA"), hex("#8BFA0C"), hex("#25FCFF") },
		24,
		false
	),
	Rare = rarity(
		"#5FD0FF",
		"#1E7BFF",
		"#08205C",
		{ hex("#CFF0FF"), hex("#5FD0FF") },
		{ WHITE, hex("#5FD0FF"), hex("#1E7BFF"), hex("#8BFA0C") },
		32,
		false
	),
	Epic = rarity(
		"#E08CFF",
		"#A43BFF",
		"#2C0057",
		{ hex("#F3D6FF"), hex("#C46BFF") },
		{ WHITE, hex("#E08CFF"), hex("#A43BFF"), hex("#FF3FA8"), hex("#25FCFF") },
		44,
		false
	),
	Legendary = rarity(
		"#FFF06A",
		"#FF9A00",
		"#4B2000",
		{ hex("#FFF7B8"), hex("#FFC233") },
		{ WHITE, hex("#FFF06A"), hex("#FECE08"), hex("#F77718"), hex("#F8060B") },
		56,
		true
	),
	Mythic = {
		Top = hex("#FF7EB6"),
		Bottom = hex("#A43BFF"),
		Lip = hex("#1A0033"),
		Rainbow = true,
		Rays = RAINBOW,
		Confetti = RAINBOW,
		ConfettiCount = 60,
		Flash = true,
	},
}

local Mutations: { [string]: MutationStyle } = {
	Gold = { Top = hex("#FFF27A"), Bottom = hex("#FFB300"), Lip = hex("#4B2000"), Icon = "👑", Effect = "sparkles" },
	Neon = { Top = hex("#6BFFF4"), Bottom = hex("#00C8FF"), Lip = hex("#00314D"), Icon = "⚡", Effect = "pulse" },
	Rainbow = { Top = hex("#FF7AD9"), Bottom = hex("#7A5CFF"), Lip = hex("#1A0033"), Icon = "🌈", Effect = "rainbow" },
}

local UIConfig = {
	-- Всплывающие уведомления (тосты) вверху экрана.
	ToastDuration = 3.5, -- сколько секунд висит уведомление
	MaxToasts = 3, -- сколько уведомлений видно одновременно (компьютер)
	MaxToastsTouch = 1, -- … на планшете (второе легло бы на голову персонажа; остальные ждут в очереди)
	MaxToastsPhone = 1, -- … на телефоне (HUD ниже 500 px): второе легло бы на голову персонажа
	ToastGap = 0.7, -- уведомления уходят не чаще, чем раз в столько секунд

	--[[
		Шрифт интерфейса: Montserrat Heavy (900) — шрифт образца, с кириллицей; цифры, подсказки,
		всплывающие числа и слова попаданий — тем же шрифтом с наклоном (Italic). Theme и UiFx
		берут семейство отсюда: вернуть Nunito — одна строка.
	]]
	Font = {
		Family = "rbxasset://fonts/families/Montserrat.json",
	},

	--[[
		Шкала размеров текста (UiFx.fitText): размер в пикселях на экране высотой TypeHeight;
		на экранах выше растёт пропорционально, но не больше чем в TypeMaxScale раз. Надпись
		получает уровень атрибутом TextTier (Theme.label { Tier = "Body" }).
		  Title  — плашка базы, заголовки (мини-игра, баннер редкости);
		  Button — подписи кнопок («ЗАБРОСИТЬ», «СМОТАТЬ»), громкие уведомления;
		  Body   — подсказки, уведомления, «Тапни — забрать!»;
		  Small  — «ДОМОЙ», чипс веса, строка «кто» громкого уведомления.
		(Счётчик улова, цена и «КЛЮЁТ!» — «витринные» числа и слова по своей коробке.)
		Montserrat шире Nunito: размеры чуть меньше прежних, высота заглавных — та же.
	]]
	Type = {
		Title = 20,
		Button = 17,
		Body = 15,
		Small = 14,
	} :: { [string]: number },
	TypeHeight = 390,
	TypeMaxScale = 1.6,

	-- Сколько секунд карточка улова открыта сама (по редкости; тап закрывает раньше). Только клиент.
	-- (У легендарной и мифической перед карточкой ещё стоит огромное слово редкости — 0.8 / 0.9 с;
	-- рыба над головой висит дольше карточки: FishingConfig.HoldFishTime.)
	CatchCardTime = {
		Common = 2.2,
		Rare = 2.8,
		Epic = 3.4,
		Legendary = 4.2,
		Mythic = 5.1,
	} :: { [string]: number },

	-- Тёмная обводка текста и значков: нейтральный почти чёрный.
	Ink = hex("#15171C"),
	White = WHITE,

	Palette = Palette,
	Rarity = Rarity,
	Mutations = Mutations,
	Rainbow = RAINBOW,

	-- Красный кружок «!» (уведомление на кнопке): верх → низ и тёмно-красная обводка.
	BadgeRed = swatch("#FF4A3D", "#F00A00", "#4A0000"),
	-- Деньги (этап 3): ярко-зелёные цифры, как «$0» образца.
	MoneyText = hex("#1BFF00"),
	-- Надписи в мире (следующий проход — таблички баз, имя рыбы над головой): жёлтые и зелёные
	-- буквы с тёмной обводкой, как «МАГАЗИН СЛЕДОВ» / «БЕСПЛАТНО!» образца.
	BillboardYellow = swatch("#F7DC00", "#F4ED00", "#0E1A00"),
	BillboardGreen = swatch("#08EC00", "#08EC00", "#001100"),

	-- Конфетти по умолчанию (яркая смесь цветов палитры).
	Confetti = {
		hex("#F8060B"),
		hex("#FECE08"),
		hex("#3FFF03"),
		hex("#03C6FF"),
		hex("#A43BFF"),
		hex("#F77718"),
		hex("#FF3FA8"),
		WHITE,
	},

	--[[
		Устройство кнопки и плашки «симулятора» (Theme.sim в сборщике, UiFx.setCandy на клиенте —
		одни и те же числа). Обводки — в пикселях на экране высотой 720 (UiFx.fitStrokes):
		  Radius       — скругление кнопок и панелей (доля короткой стороны; почти прямые углы,
		                 круглит толстая обводка);
		  PlateRadius  — плашки-надписи (база, уведомления, фишки): «не кнопка»;
		  Stroke       — толстая обводка формы (на телефоне ≈ 4 px); MinorStroke — мелкие детали;
		  Rim, RimAlpha — тонкий светлый ободок по краю лица изнутри (белый, полупрозрачный);
		  GlassAlpha   — прозрачность тёмного стекла;
		  Gloss        — белый отсвет в верхней половине лица (прозрачность вверху; 1 — нет);
		  ShadowY, ShadowAlpha — тень под кнопкой: сдвиг вниз (доля высоты) и прозрачность.
	]]
	Sim = {
		Radius = 0.08,
		PlateRadius = 0.3,
		Stroke = 6,
		MinorStroke = 4,
		Rim = 2,
		RimAlpha = 0.5,
		GlassAlpha = 0.5,
		Gloss = 0.8,
		ShadowY = 0.08,
		ShadowAlpha = 0.55,
	},

	--[[
		Движение интерфейса (UiFx берёт значения по умолчанию отсюда; время — в секундах):
		  Press   — нажатие: сжатие до Scale за Down, лицо темнеет до Shade, при отпускании
		            перелёт до Peak (но не больше MaxGrow px роста) за Up и пружина к 1 за Settle;
		            значок «пинается» (IconKick, IconTilt°); щелчок случайной высоты Pitch;
		  Hover   — наведение мыши (не на тач-экране): чуть крупнее;
		  Pop, Punch, Out — появление (Back Out), «удар» (два шага с перелётом), уход;
		  Morph   — смена вида кнопки; Breath — «дыхание» главной кнопки; Shine — блик;
		  Bob     — значок подпрыгивает (доля AnchorPoint); Sway — покачивание плашки ожидания;
		  Wobble  — кружок «!» качается и подпрыгивает; Roll — «одометр» чисел;
		  Fly     — значки улова летят в счётчик (сколько — по редкости); Ring — кольцо-таймер;
		  RimFlash — ободок вспыхивает белым; Reduced — «меньше движения».
	]]
	Motion = {
		Press = {
			Down = 0.06,
			Scale = 0.9,
			Shade = 0.8,
			Peak = 1.08,
			MaxGrow = 3, -- … но не больше чем на столько px (крупная кнопка у кнопки прыжка)
			Up = 0.09,
			Settle = 0.22,
			Unshade = 0.14,
			IconKick = 1.18,
			IconTilt = 8,
			Pitch = { 0.95, 1.08 },
		},
		Hover = { Scale = 1.05, Time = 0.14 },
		Pop = { Time = 0.32, ChildDelay = 0.05, ChildFrom = 0.3 },
		Punch = { From = 0.84, Peak = 1.1, Up = 0.09, Settle = 0.22 },
		Out = { Swell = 1.06, Pre = 0.06, Time = 0.16 },
		Morph = { Fade = 0.16, Spin = -120, IconTime = 0.32, Flash = 0.4, FlashTime = 0.2 },
		Breath = { Peak = 1.04, Period = 1.8 },
		Shine = { Interval = 3.5, Time = 0.6 },
		Bob = { Lift = 0.08, Up = 0.18, Down = 0.32, Every = { 2.2, 3.0 } },
		Sway = { Angle = 1.5, Period = 2.4 },
		Wobble = { Angle = 12, Swings = 3, Time = 0.5, Bump = 1.12, Every = { 2.8, 3.6 } },
		Roll = { Out = 0.16, In = 0.24, Punch = 1.25, Flash = 0.35 },
		Fly = {
			Time = 0.45,
			Gap = 0.05,
			Scatter = 0.18,
			Spread = { 40, 70 },
			Count = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 6 },
		},
		Ring = { Thickness = 5, Pad = 6 },
		RimFlash = { Time = 0.3, Bump = 1.06 },
		Reduced = { PopTime = 0.15, Confetti = 0.5, Rainbow = 0.3 },
	},

	-- Вид уведомления: цвет плашки и значок. Неизвестный вид показывается как info.
	ToastKinds = {
		info = { Token = "Sky", Icon = "💬" },
		success = { Token = "Leaf", Icon = "🎉" },
		warning = { Token = "Sun", Icon = "⚠️", Priority = 2 },
		danger = { Token = "Berry", Icon = "🚨", Priority = 3 },
		-- Своя база (HudController красит плашку в цвет базы, см. BaseSwatches).
		base = { Token = "Leaf", Icon = "🚩", Priority = 2 },
		-- Громкие новости на весь сервер: легендарный и мифический улов (в две строки: кто — мелко,
		-- что поймал — крупно, золотом / белым на тёмном в радужной обводке).
		Legendary = { Token = "Gold", Icon = "🌟", Big = true, Life = 4.5, Priority = 2 },
		Mythic = { Token = "Night", Icon = "🌈", Rainbow = true, Big = true, Life = 4.5, Priority = 2 },
	} :: { [string]: ToastKind },

	-- Сплошной цвет по виду (подсказки рыбалки и всё, что без градиента).
	KindColors = {
		info = Palette.Sky.Bottom,
		success = Palette.Leaf.Bottom,
		warning = Palette.Sun.Bottom,
		danger = Palette.Berry.Bottom,
	} :: { [string]: Color3 },

	-- Цвет-заглушка, пока у игрока нет базы (плашка — Palette.Slate).
	NoBaseColor = Palette.Slate.Bottom,

	-- Цвета баз по Id (BaseConfig.Colors) и кнопка из любого цвета.
	BaseSwatches = BaseSwatches,
	swatchFor = swatchFor,

	-- Цвета рыбалки, которых нет в палитре (сборщик gui/Fishing.luau и FishingController).
	Fishing = {
		PipDone = Color3.fromRGB(64, 200, 96), -- закрашенный кружок попадания (его ищет e2e-бот — не менять)
		TrackBottom = hex("#23263A"), -- низ градиента дорожки мини-игры
		PipShade = Color3.fromRGB(190, 196, 210), -- тень пустого кружка
		NeedleShade = Color3.fromRGB(214, 224, 240), -- тень стрелки
		NeedleGhost = hex("#C8FAFF"), -- шлейф стрелки: белый с голубым отливом
		Muted = hex("#5E646B"), -- приглушённый текст на белой карточке
		Guide = Color3.fromRGB(255, 214, 80), -- луч-подсказка к месту рыбалки
		ZoneGlow = hex("#B8FF9A"), -- свечение зелёной зоны
		TimeBar = { hex("#BFEFFF"), hex("#FFD23F"), hex("#FF4D5E") }, -- время мини-игры: полно → мало
	},

	--[[
		Кошелёк (Этап 3, MoneyController: HUD.Status.Wallet — «💵 $1 234» и «+$42/с»):
		  LoadingAfter — данные игрока грузятся дольше стольких секунд: кошелёк на «стекле» с «$…»;
		  IntroGap     — появления после баннера базы: плашка → кошелёк → «САДОК», через столько с
		                 (кнопку «САДОК» выпускает TankButtonController через 2 × IntroGap);
		  IntroWait    — баннера базы так и не было (нет данных о базе) — не ждать дольше стольких с;
		  PopFrom, PopTime, IconSpin — появление: масштаб от PopFrom за PopTime, 💵 вкручивается
		                 с IconSpin°;
		  FloatEvery   — «+$13» дохода (в секунду) всплывает справа от числа раз в столько секунд
		                 (при доходе > 0; цепочка таймеров; не в FloatQuiet с после праздника денег),
		                 FloatTime — за сколько тает, FloatRise — на какую долю высоты строки
		                 поднимается (не выше строки: над ней плашка базы), FloatSize — его высота;
		  Count        — праздник денег (Celebrate): число «набегает» от Min до Max секунд — дольше
		                 у больших сумм (до CountBig монет); Coins — сколько 💵 летит (Min..Max, по сумме);
		  RateRoll     — доход «+$/с» катится к новому числу за столько секунд;
		  HoldRelease  — замена при улове: TankButtonController зовёт Celebrate после своего прилёта;
		                 не позвал за столько секунд после снятия CounterHold — монеты отпускаются
		                 (надпись не застревает);
		  JumpSeconds, SaleWait — Money вырос больше, чем на JumpSeconds секунд дохода: это продажа,
		                 её праздник (remote) идёт следом за атрибутом — надпись ждёт его SaleWait с,
		                 потом число «набегает» само (не прыгает);
		  TrophyWait   — уведомления улова (первая рыба, замена, «Садок полон…» — CatchToast) ждут,
		                 пока своя рыба над головой уйдёт, но не дольше стольких секунд (трофей
		                 держится FishingConfig.HoldFishTime ≤ 10 с); SoldToastGap — «Садок полон…»
		                 через столько секунд после того, как число продажи набежало;
		  RowGap       — промежуток между числом и доходом (доля высоты строки); IconShare — сколько
		                 ширины строки занимает 💵 (в высотах строки); TextFill — текст числа от высоты
		                 строки; MinMoney — число не мельче стольких px (длинная строка — сжимается
		                 до него, потом прячется доход).
	]]
	Wallet = {
		LoadingAfter = 3,
		IntroGap = 0.3,
		IntroWait = 6,
		PopFrom = 0.3,
		PopTime = 0.4,
		IconSpin = -180,
		FloatEvery = 5,
		FloatTime = 1.1,
		FloatRise = 0.3,
		FloatSize = 0.55,
		FloatQuiet = 2,
		Count = { Min = 0.6, Max = 1.0 },
		CountBig = 2000,
		Coins = { Min = 3, Max = 8 },
		RateRoll = 0.5,
		HoldRelease = 2.5,
		JumpSeconds = 2,
		SaleWait = 0.6,
		TrophyWait = 11,
		SoldToastGap = 0.25,
		RowGap = 0.22,
		IconShare = 1.0,
		TextFill = 1.0,
		MinMoney = 22,
	},

	--[[
		Кнопка «САДОК» (Этап 3, TankButtonController: HUD.RightButtons.TankButton, фишка «4/6»):
		  Bump, RarityBump — прилёт рыбы в садок: подпрыгивание кнопки (в цветах редкости — выше);
		  Ring         — кольцо цвета редкости от кнопки: масштаб, толщина px, время;
		  Squash       — 🐠 «плющится» до этого масштаба и пружинит (Elastic) за SquashTime;
		  OpenAfter    — нажали во время полёта: панель открывается через столько секунд после
		                 прилёта (кольцо успело разойтись);
		  ToastAfter   — уведомление о первой рыбе — через столько секунд после прилёта, о замене —
		                 через ReplacedToastAfter (монеты уже долетели в кошелёк); оба — и не раньше,
		                 чем своя рыба над головой ушла (MoneyController.CatchToast, Wallet.TrophyWait);
		  ArrivalWait  — улов без CounterHold (нет карточки): прилёт через столько секунд;
		  StoredWait   — TankCount вырос без улова на экране (Этап 4: рыба легла не из улова): прилёт
		                 через столько секунд, если за это время не пришёл "Caught".
	]]
	TankButton = {
		Bump = 1.3,
		RarityBump = 1.45,
		Ring = { Scale = 1.6, Thickness = 5, Time = 0.55 },
		Squash = 1.35,
		SquashTime = 0.45,
		OpenAfter = 0.3,
		ToastAfter = 0.35,
		ReplacedToastAfter = 1.1,
		ArrivalWait = 0.05,
		StoredWait = 0.3,
	},

	-- Лимиты и ритм эффектов (UiFx).
	Fx = {
		ConfettiMaxTouch = 40, -- конфетти одновременно на телефоне/планшете
		ConfettiMax = 60, -- … и на компьютере
		ShineInterval = 3.5, -- блик на «спокойных» главных кнопках, раз в столько секунд (= Motion.Shine)
		FlashMinInterval = 0.34, -- вспышки (и пульс виньетки) не чаще 3 раз в секунду
		StrokeHeight = 720, -- обводки нарисованы для экрана такой высоты (UiFx.fitStrokes)
		StrokeMax = 1.2, -- обводки форм на больших экранах толще не больше чем во столько раз
		TextStrokeMax = 1.0, -- обводка текста не толще, чем на 720 px (текст растёт до 1.6 раз и стоп)
		TextStrokeMin = 2, -- обводка текста не тоньше, px (белое на жёлтом читается только с ней)
		FovPunchMax = 8, -- все «толчки» камеры вместе не больше стольких градусов (UiFx.fovPunch)
		SoundPool = 4, -- копий каждого звука (частые звуки не обрывают друг друга)
	},
}

return UIConfig
