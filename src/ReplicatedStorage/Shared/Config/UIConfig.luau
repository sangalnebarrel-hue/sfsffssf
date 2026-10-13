--!strict
--[[
	UIConfig — общие настройки интерфейса: уведомления, палитра «Candy Splash», стили редкостей и
	мутаций, виды уведомлений, конфетти и лимиты эффектов. Стиль — tools/builder/gui/STYLE.md.

	Модуль «чистый» (без require, только Color3): его читают и клиент (контроллеры, UiFx), и сборщик
	интерфейса (tools/builder/gui/Theme.luau) — все цвета интерфейса заданы в одном месте.

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
	Flash: boolean, -- вспышка экрана и лёгкая тряска камеры
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
}

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
	MaxToasts = 3, -- сколько уведомлений видно одновременно

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

	-- Вид уведомления: цвет «конфеты» и значок.
	ToastKinds = {
		info = { Token = "Sky", Icon = "💬" },
		success = { Token = "Leaf", Icon = "🎉" },
		warning = { Token = "Sun", Icon = "⚠️" },
		danger = { Token = "Berry", Icon = "⛔" },
	} :: { [string]: ToastKind },

	-- Сплошной цвет по виду (подсказки рыбалки и всё, что без градиента).
	KindColors = {
		info = Palette.Sky.Bottom,
		success = Palette.Leaf.Bottom,
		warning = Palette.Sun.Bottom,
		danger = Palette.Berry.Bottom,
	} :: { [string]: Color3 },

	-- Цвет-заглушка, пока у игрока нет базы.
	NoBaseColor = Palette.Slate.Bottom,

	-- «Конфета» в произвольном цвете (цвет базы): лицевая сторона — этот цвет с градиентом
	-- от белого к серому Bottom (умножение), губа — цвет × Lip.
	Tint = {
		Bottom = 0.8,
		Lip = 0.58,
	},

	-- Лимиты и ритм эффектов (UiFx).
	Fx = {
		ConfettiMaxTouch = 40, -- конфетти одновременно на телефоне/планшете
		ConfettiMax = 60, -- … и на компьютере
		ShineInterval = 3.5, -- блик на «спокойных» главных кнопках, раз в столько секунд
		FlashMinInterval = 0.34, -- вспышки не чаще 3 раз в секунду
		StrokeHeight = 720, -- обводки нарисованы для экрана такой высоты (UiFx.fitStrokes)
	},
}

return UIConfig
