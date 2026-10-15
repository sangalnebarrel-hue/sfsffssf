--!strict
--[[
	UIConfig — общие настройки интерфейса «Кирпичики» (UI v3): уведомления, палитра (цвета
	кирпичиков-конструктора), стили редкостей и мутаций, виды уведомлений, конфетти, лимиты
	эффектов и размеры «кирпичика» (Brick). Стиль — tools/builder/gui/STYLE.md.

	Модуль «чистый» (без require, только Color3): его читают и клиент (контроллеры, UiFx), и сборщик
	интерфейса (tools/builder/gui/Theme.luau) — все цвета интерфейса заданы в одном месте.
	Здесь же шкала размеров текста (Type), время карточки улова по редкости (CatchCardTime) и
	цвета баз (BaseSwatches, swatchFor).

	Палитра: у каждого цвета (токена) есть
	  Top    — верх лицевой стороны (светлее; у кирпичика над ним ещё светлая «крышка»),
	  Bottom — низ лицевой стороны (насыщеннее),
	  Lip    — боковина: тёмная полоса под лицевой стороной (≈ 0.6 яркости цвета).
	Имена токенов прежние (Sky, Leaf, …) — контроллеры красят ими через UiFx.setCandy; цвета —
	яркие цвета конструктора: Sky — синий, Leaf — зелёный, Sun — оранжевый, Gold — жёлтый,
	Berry — красный, Grape — фиолетовый, Mint — лазурный («Домой»), Night — тёмно-серый камень,
	Cream — белая пластина, Slate — светло-серый (неактивное), Water — бирюза (ждём поклёвку),
	Coal — чёрная плитка (подпись кнопки действия, дорожка мини-игры).
]]

export type Swatch = {
	Top: Color3,
	Bottom: Color3,
	Lip: Color3,
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
	Icon: string, -- эмодзи в кружке слева
	Rainbow: boolean?, -- «конфета» переливается радугой (вращающийся градиент)
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

-- Цвета радуги (Mythic, мутация «Радужная», радужные конфетти и пупырки).
local RAINBOW = {
	hex("#FF3B30"),
	hex("#FF9500"),
	hex("#FFD60A"),
	hex("#34C759"),
	hex("#32D2F5"),
	hex("#2F7BFF"),
	hex("#AF52DE"),
}

-- Яркие цвета конструктора (под экран: чуть сочнее настоящего пластика).
local Palette: { [string]: Swatch } = {
	Sky = swatch("#4FA3FF", "#0A6CD8", "#053E85"), -- синий: заброс, главное действие, инфо
	Sun = swatch("#FFB347", "#FF7A00", "#A34A00"), -- оранжевый: поклёвка, внимание
	Leaf = swatch("#7EDB5A", "#2FA82F", "#1A621C"), -- зелёный: тянуть, успех
	Berry = swatch("#FF4A3D", "#E3000B", "#8E0008"), -- красный: стоп, опасность, промах
	Grape = swatch("#C08CF0", "#8E44C6", "#522577"), -- фиолетовый: особое, эпик
	Gold = swatch("#FFE45C", "#FFC20E", "#B07A00"), -- жёлтый: деньги, улов, легендарное
	Night = swatch("#5B6168", "#3E4349", "#24282C"), -- тёмно-серый камень: панели, дорожки, подсказки
	Cream = swatch("#FFFFFF", "#E6E9EC", "#A9AFB5"), -- белая пластина: карточки, гнёзда значков
	Slate = swatch("#C9CED3", "#A0A5A9", "#6C7176"), -- светло-серый: неактивное («ЖДЁМ…», нет базы)
	Mint = swatch("#6FE0F5", "#1FA9D6", "#0E6585"), -- лазурный: «Домой» (не путать с зелёным «ТЯНИ!»)
	Water = swatch("#67D9E3", "#1593A6", "#0A5763"), -- бирюза: ожидание поклёвки (вода)
	Coal = swatch("#4A5058", "#262A30", "#101214"), -- чёрная плитка: подпись кнопки действия, дорожка
}

--[[
	Цвета баз (BaseConfig.Colors, ключ — Id): чистые цвета палитры вместо затемнённого цвета
	базы, чтобы кирпичик «ЛАЗУРНАЯ БАЗА» не выглядел грязным рядом с остальным. Для цвета,
	которого здесь нет, — UIConfig.swatchFor(цвет).
]]
local BaseSwatches: { [string]: Swatch } = {
	Red = Palette.Berry,
	Blue = Palette.Sky,
	Yellow = Palette.Gold,
	Purple = Palette.Grape,
	Orange = Palette.Sun,
	Cyan = Palette.Mint,
	Pink = swatch("#FF7EB6", "#E8448F", "#902A59"),
	Green = swatch("#5FE3A0", "#12A05E", "#0A6338"), -- изумрудный (не Leaf: его держит «успех»)
}

-- Кирпичик из произвольного цвета: светлый верх, сочный низ (не темнее 0.82 по яркости),
-- боковина ≈ 0.62 яркости низа.
local function swatchFor(color: Color3): Swatch
	local h, s, v = color:ToHSV()
	local bottom = Color3.fromHSV(h, math.min(1, s * 1.15), math.max(v, 0.82))
	return {
		Top = color:Lerp(Color3.new(1, 1, 1), 0.35),
		Bottom = bottom,
		Lip = Color3.new(bottom.R * 0.62, bottom.G * 0.62, bottom.B * 0.62),
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

-- Редкости — тоже цвета конструктора: обычная — светло-серая, редкая — синяя, эпическая —
-- фиолетовая, легендарная — жёлтая → оранжевая, мифическая — радуга (и пупырки радугой).
local Rarity: { [string]: RarityStyle } = {
	Common = rarity(
		"#E2E6EA",
		"#A0A5A9",
		"#6C7176",
		{ hex("#FFFFFF"), hex("#C9CED3") },
		{ WHITE, hex("#C9CED3"), hex("#7EDB5A"), hex("#4FA3FF") },
		24,
		false
	),
	Rare = rarity(
		"#4FA3FF",
		"#0A6CD8",
		"#053E85",
		{ hex("#BFE0FF"), hex("#4FA3FF") },
		{ WHITE, hex("#4FA3FF"), hex("#0A6CD8"), hex("#7EDB5A") },
		32,
		false
	),
	Epic = rarity(
		"#C08CF0",
		"#8E44C6",
		"#522577",
		{ hex("#EBD5FF"), hex("#A86BE0") },
		{ WHITE, hex("#C08CF0"), hex("#8E44C6"), hex("#FF7EB6"), hex("#4FA3FF") },
		44,
		false
	),
	Legendary = rarity(
		"#FFE45C",
		"#FF9A00",
		"#A35A00",
		{ hex("#FFF3A8"), hex("#FFB347") },
		{ WHITE, hex("#FFE45C"), hex("#FFC20E"), hex("#FF7A00"), hex("#FF4A3D") },
		56,
		true
	),
	Mythic = {
		Top = hex("#FF7EB6"),
		Bottom = hex("#8E44C6"),
		Lip = hex("#522577"),
		Rainbow = true,
		Rays = RAINBOW,
		Confetti = RAINBOW,
		ConfettiCount = 60,
		Flash = true,
	},
}

local Mutations: { [string]: MutationStyle } = {
	Gold = { Top = hex("#FFF07A"), Bottom = hex("#FFA51F"), Lip = hex("#C46E0A"), Icon = "👑", Effect = "sparkles" },
	Neon = { Top = hex("#4DFFF0"), Bottom = hex("#19C2FF"), Lip = hex("#0B7FB0"), Icon = "⚡", Effect = "pulse" },
	Rainbow = { Top = hex("#FF7AD9"), Bottom = hex("#7A5CFF"), Lip = hex("#4A2BB0"), Icon = "🌈", Effect = "rainbow" },
}

local UIConfig = {
	-- Всплывающие уведомления (тосты) вверху экрана.
	ToastDuration = 3.5, -- сколько секунд висит уведомление
	MaxToasts = 3, -- сколько уведомлений видно одновременно (компьютер)
	MaxToastsTouch = 1, -- … на планшете (второе легло бы на голову персонажа; остальные ждут в очереди)
	MaxToastsPhone = 1, -- … на телефоне (HUD ниже 500 px): второе легло бы на голову персонажа
	ToastGap = 0.7, -- уведомления уходят не чаще, чем раз в столько секунд

	--[[
		Шкала размеров текста (UiFx.fitText): размер в пикселях на экране высотой TypeHeight;
		на экранах выше растёт пропорционально, но не больше чем в TypeMaxScale раз. Надпись
		получает уровень атрибутом TextTier (Theme.label { Tier = "Body" }).
		  Title  — плашка базы, заголовки (мини-игра, баннер редкости, имя рыбы);
		  Button — подписи кнопок («ЗАБРОСИТЬ», «СМОТАТЬ», «ДОМОЙ»), громкие уведомления;
		  Body   — подсказки, уведомления, счётчик улова, «Тапни — забрать!»;
		  Small  — плашка-«чипс» веса. (Цена на карточке улова — «витринное» число по своей
		           коробке, до 1.4 Title: FishingController.)
	]]
	Type = {
		Title = 22,
		Button = 18,
		Body = 16,
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

	-- Тёмная обводка всего интерфейса (текст, кирпичики, пупырки): нейтральный почти чёрный.
	Ink = hex("#15171C"),
	White = WHITE,

	Palette = Palette,
	Rarity = Rarity,
	Mutations = Mutations,
	Rainbow = RAINBOW,

	-- Конфетти по умолчанию (яркая смесь цветов конструктора).
	Confetti = {
		hex("#E3000B"),
		hex("#FFC20E"),
		hex("#2FA82F"),
		hex("#1FA9D6"),
		hex("#8E44C6"),
		hex("#FF7A00"),
		hex("#FF7EB6"),
		WHITE,
	},

	--[[
		Устройство «кирпичика» (Theme.brick в сборщике и UiFx.setCandy / setStuds на клиенте читают
		одни и те же числа). Доли — от высоты кирпичика, если не сказано иное:
		  Lip, TileLip     — боковина (тёмная полоса снизу) у кирпичика / у гладкой плитки;
		  Radius, TileRadius — скругление углов (доля короткой стороны);
		  CapLight, CapStop — верхняя «крышка»: верх градиента лицевой стороны светлее Top на
		                   CapLight и переходит в Top на CapStop её высоты;
		  StudW, StudH     — коробка пупырки спереди (над кирпичиком видно StudShow её высоты,
		                   остальное прячется за кирпичиком); StudLight / StudShade — блик слева и
		                   тень справа (горизонтальный градиент);
		  TopLight, TopShade — круглая пупырка сверху (на пластинах): свет → тень;
		  SpecW, SpecH, SpecX, SpecY, SpecAlpha — белый блик-«чёрточка» на лицевой стороне (доли
		                   лицевой стороны, прозрачность); StudStroke — обводка пупырки (px при 720);
		                   MaxStuds — не больше пупырок на кирпичик.
	]]
	Brick = {
		Lip = 0.16,
		TileLip = 0.12,
		Radius = 0.16,
		TileRadius = 0.2,
		CapLight = 0.3,
		CapStop = 0.12,
		StudW = 0.56,
		StudH = 0.34,
		StudShow = 0.74,
		StudLight = 0.45,
		StudShade = 0.25,
		TopLight = 0.4,
		TopShade = 0.12,
		SpecW = 0.12,
		SpecH = 0.09,
		SpecX = 0.05,
		SpecY = 0.17,
		SpecAlpha = 0.5,
		StudStroke = 3,
		MaxStuds = 8,
	},

	-- Вид уведомления: цвет «конфеты» и значок. Неизвестный вид показывается как info.
	ToastKinds = {
		info = { Token = "Sky", Icon = "💬" },
		success = { Token = "Leaf", Icon = "🎉" },
		warning = { Token = "Sun", Icon = "⚠️", Priority = 2 },
		danger = { Token = "Berry", Icon = "🚨", Priority = 3 },
		-- Своя база (HudController красит «конфету» в цвет базы, см. BaseSwatches).
		base = { Token = "Leaf", Icon = "🚩", Priority = 2 },
		-- Громкие новости на весь сервер: легендарный и мифический улов (в две строки: кто — мелко,
		-- что поймал — крупно, золотом / радугой; у мифической ещё и радужные края экрана).
		Legendary = { Token = "Gold", Icon = "🌟", Big = true, Life = 4.5, Priority = 2 },
		Mythic = { Token = "Grape", Icon = "🌈", Rainbow = true, Big = true, Life = 4.5, Priority = 2 },
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

	-- «Конфеты» цветов баз по Id (BaseConfig.Colors) и «конфета» из любого цвета.
	BaseSwatches = BaseSwatches,
	swatchFor = swatchFor,

	-- Цвета рыбалки, которых нет в палитре (сборщик gui/Fishing.luau и FishingController).
	Fishing = {
		PipDone = Color3.fromRGB(64, 200, 96), -- закрашенный кружок попадания (его ищет e2e-бот — не менять)
		TrackBottom = hex("#3A3F45"), -- низ градиента дорожки мини-игры (тёмный камень)
		PipShade = Color3.fromRGB(190, 196, 210), -- тень пустого кружка
		NeedleShade = Color3.fromRGB(214, 224, 240), -- тень стрелки
		Muted = hex("#5E646B"), -- приглушённый текст на белой карточке
		Guide = Color3.fromRGB(255, 214, 80), -- луч-подсказка к месту рыбалки
		ZoneGlow = hex("#B8FF9A"), -- свечение зелёной зоны
		TimeBar = { hex("#BFEFFF"), hex("#FFD23F"), hex("#FF4D5E") }, -- время мини-игры: полно → мало
	},

	-- Лимиты и ритм эффектов (UiFx).
	Fx = {
		ConfettiMaxTouch = 40, -- конфетти одновременно на телефоне/планшете
		ConfettiMax = 60, -- … и на компьютере
		ShineInterval = 3.5, -- блик на «спокойных» главных кнопках, раз в столько секунд
		FlashMinInterval = 0.34, -- вспышки (и пульс виньетки) не чаще 3 раз в секунду
		StrokeHeight = 720, -- обводки нарисованы для экрана такой высоты (UiFx.fitStrokes)
		TextStrokeMin = 2.5, -- обводка текста не тоньше, px (белое на жёлтом читается только с ней)
		FovPunchMax = 8, -- все «толчки» камеры вместе не больше стольких градусов (UiFx.fovPunch)
		SoundPool = 4, -- копий каждого звука (частые звуки не обрывают друг друга)
	},
}

return UIConfig
