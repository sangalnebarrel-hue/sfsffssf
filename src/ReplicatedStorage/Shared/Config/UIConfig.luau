--!strict
--[[
	UIConfig — общие настройки интерфейса: уведомления, палитра «Candy Splash», стили редкостей и
	мутаций, виды уведомлений, конфетти и лимиты эффектов. Стиль — tools/builder/gui/STYLE.md.

	Модуль «чистый» (без require, только Color3): его читают и клиент (контроллеры, UiFx), и сборщик
	интерфейса (tools/builder/gui/Theme.luau) — все цвета интерфейса заданы в одном месте.
	Здесь же шкала размеров текста (Type), время карточки улова по редкости (CatchCardTime) и
	«конфеты» цветов баз (BaseSwatches, swatchFor).

	Палитра: у каждого цвета (токена) есть
	  Top    — верх градиента лицевой стороны (светлее),
	  Bottom — низ градиента (насыщеннее),
	  Lip    — «губа»: тёмный низ конфетной кнопки (тень под лицевой стороной).
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

-- Цвета радуги (Mythic, мутация «Радужная», радужные конфетти).
local RAINBOW = {
	hex("#FF4D6D"),
	hex("#FF9F1C"),
	hex("#FFE14D"),
	hex("#5BE36B"),
	hex("#3DD6F5"),
	hex("#4D7CFF"),
	hex("#B45CFF"),
}

local Palette: { [string]: Swatch } = {
	Sky = swatch("#5FD8FF", "#1F7BF0", "#1553B0"), -- заброс, главное действие, инфо
	Sun = swatch("#FFD23F", "#FF6A1F", "#C2410C"), -- поклёвка, внимание
	Leaf = swatch("#8BF26A", "#1FB04F", "#137A37"), -- тянуть, успех, «Домой»
	Berry = swatch("#FF7A8A", "#E0304A", "#A11A34"), -- стоп, опасность, промах
	Grape = swatch("#D69BFF", "#7A35F0", "#5420B0"), -- особое, эпик
	Gold = swatch("#FFF07A", "#FFA51F", "#C46E0A"), -- деньги, улов, легендарное
	Night = swatch("#2E3A66", "#161C38", "#0A0E20"), -- панели, дорожки
	Cream = swatch("#FFFDF5", "#F2EADB", "#C9B994"), -- карточки
	Slate = swatch("#C3CDE0", "#7C89A6", "#4E5872"), -- неактивное («ЖДЁМ…», нет базы)
	Mint = swatch("#8CF5E0", "#14B8A6", "#0E7C70"), -- «Домой» (не путать с зелёным «ТЯНИ!»)
	Water = swatch("#5FD8FF", "#1FA5C8", "#137A96"), -- ожидание поклёвки (вода)
}

--[[
	«Конфеты» цветов баз (BaseConfig.Colors, ключ — Id): чистые цвета палитры вместо
	затемнённого цвета базы, чтобы плашка «Твоя база» не выглядела грязной рядом с остальным.
	Для цвета, которого здесь нет, — UIConfig.swatchFor(цвет).
]]
local BaseSwatches: { [string]: Swatch } = {
	Red = Palette.Berry,
	Purple = Palette.Grape,
	Cyan = Palette.Sky,
	Orange = Palette.Sun,
	Green = swatch("#6FF0B0", "#14A86A", "#0E7048"),
	Pink = swatch("#FF9AD5", "#E0489A", "#9E2468"),
	Blue = swatch("#7AA8FF", "#2F62E0", "#1D3F9E"),
	Yellow = swatch("#FFE65C", "#F0B400", "#A87A00"),
}

-- «Конфета» из произвольного цвета: светлый верх, сочный низ (не темнее 0.82 по яркости), тёмная губа.
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

local Rarity: { [string]: RarityStyle } = {
	Common = rarity(
		"#E3E9F0",
		"#9AA8B8",
		"#6B7789",
		{ hex("#FFFFFF"), hex("#C9D3DF") },
		{ WHITE, hex("#C9D3DF"), hex("#8BF26A"), hex("#5FD8FF") },
		24,
		false
	),
	Rare = rarity(
		"#6CD3FF",
		"#2468F0",
		"#1747A8",
		{ hex("#C2F1FF"), hex("#4FA8FF") },
		{ WHITE, hex("#6CD3FF"), hex("#2468F0"), hex("#8BF26A") },
		32,
		false
	),
	Epic = rarity(
		"#E08CFF",
		"#7B2FE8",
		"#511BA6",
		{ hex("#F3CCFF"), hex("#A15CFF") },
		{ WHITE, hex("#E08CFF"), hex("#7B2FE8"), hex("#FF7AD9"), hex("#5FD8FF") },
		44,
		false
	),
	Legendary = rarity(
		"#FFF27A",
		"#FF8A1F",
		"#B8560A",
		{ hex("#FFF6A8"), hex("#FFB13D") },
		{ WHITE, hex("#FFF27A"), hex("#FFD23F"), hex("#FF8A1F"), hex("#FF4D6D") },
		56,
		true
	),
	Mythic = {
		Top = hex("#FF8AD8"),
		Bottom = hex("#8A3CFF"),
		Lip = hex("#5A1FA8"),
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

	-- Тёмная обводка всего интерфейса (текст, кнопки, плашки).
	Ink = hex("#141A2E"),
	White = WHITE,

	Palette = Palette,
	Rarity = Rarity,
	Mutations = Mutations,
	Rainbow = RAINBOW,

	-- Конфетти по умолчанию (яркая смесь).
	Confetti = {
		hex("#FF4D6D"),
		hex("#FFD23F"),
		hex("#5BE36B"),
		hex("#3DD6F5"),
		hex("#B45CFF"),
		hex("#FF8A1F"),
		hex("#FF7AD9"),
		WHITE,
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
		TrackBottom = Color3.fromRGB(40, 50, 92), -- низ градиента дорожки мини-игры
		PipShade = Color3.fromRGB(190, 196, 210), -- тень пустого кружка
		NeedleShade = Color3.fromRGB(214, 224, 240), -- тень стрелки
		Muted = Color3.fromRGB(92, 80, 62), -- приглушённый текст на кремовой карточке
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
		TextStrokeMin = 2, -- обводка текста не тоньше, px (белое на жёлтом читается только с ней)
		FovPunchMax = 8, -- все «толчки» камеры вместе не больше стольких градусов (UiFx.fovPunch)
		SoundPool = 4, -- копий каждого звука (частые звуки не обрывают друг друга)
	},
}

return UIConfig
