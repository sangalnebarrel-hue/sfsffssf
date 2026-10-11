--!strict
--[[
	UIConfig — общие настройки интерфейса: уведомления, цвета.
	Модуль «чистый» (без require).
]]

local UIConfig = {
	-- Всплывающие уведомления (тосты) вверху экрана.
	ToastDuration = 3.5, -- сколько секунд висит уведомление
	MaxToasts = 3, -- сколько уведомлений видно одновременно

	-- Цвет фона уведомления по типу.
	KindColors = {
		info = Color3.fromRGB(45, 120, 220),
		success = Color3.fromRGB(40, 165, 85),
		warning = Color3.fromRGB(230, 150, 25),
		danger = Color3.fromRGB(215, 50, 50),
	} :: { [string]: Color3 },

	-- Цвет-заглушка, пока у игрока нет базы.
	NoBaseColor = Color3.fromRGB(140, 140, 150),
}

return UIConfig
