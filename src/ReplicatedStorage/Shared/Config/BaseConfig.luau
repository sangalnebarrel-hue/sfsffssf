--!strict
--[[
	BaseConfig — настройки баз игроков.

	Colors — цвета баз по порядку слотов: база 1 получает первый цвет, база 2 — второй и т.д.
	Id — служебное имя (латиница), Name — как показывать игроку («Красная база»).

	Модуль «чистый» (без require), его читает и сборщик места.
]]

export type BaseColor = {
	Id: string,
	Name: string,
	Color: Color3,
	-- Насколько затемнять тёмные оттенки (AccentShade < 0) этого цвета: 1 — как задано в шаблоне,
	-- меньше — светлее (жёлтый не уходит в горчичный, зелёный не сливается с соснами).
	RoofShadeScale: number?,
}

local BaseConfig = {
	-- Соседние базы чередуют тёплые и холодные цвета, чтобы их было легко различить издалека.
	Colors = {
		{ Id = "Red", Name = "Красная", Color = Color3.fromRGB(212, 74, 64) },
		{ Id = "Blue", Name = "Синяя", Color = Color3.fromRGB(62, 114, 200) },
		{ Id = "Yellow", Name = "Жёлтая", Color = Color3.fromRGB(236, 192, 48), RoofShadeScale = 0.55 },
		{ Id = "Purple", Name = "Фиолетовая", Color = Color3.fromRGB(128, 92, 192) },
		{ Id = "Orange", Name = "Оранжевая", Color = Color3.fromRGB(226, 136, 56), RoofShadeScale = 0.6 },
		{ Id = "Cyan", Name = "Лазурная", Color = Color3.fromRGB(52, 178, 226), RoofShadeScale = 0.45 },
		{ Id = "Pink", Name = "Розовая", Color = Color3.fromRGB(210, 108, 158) },
		{ Id = "Green", Name = "Изумрудная", Color = Color3.fromRGB(36, 172, 118), RoofShadeScale = 0.45 },
	} :: { BaseColor },

	-- Спокойные тона стен домов (по номеру базы), чтобы 8 участков не были одинаковыми.
	-- Красятся детали шаблона с атрибутом WallTone = true (оттенок — атрибут WallShade, как AccentShade).
	WallTones = {
		Color3.fromRGB(224, 212, 188), -- сливочный
		Color3.fromRGB(196, 212, 170), -- шалфей
		Color3.fromRGB(218, 198, 160), -- песочный
		Color3.fromRGB(186, 202, 218), -- голубоватый
		Color3.fromRGB(230, 226, 216), -- белёный
		Color3.fromRGB(210, 184, 150), -- светлое дерево
		Color3.fromRGB(222, 202, 192), -- розоватый
		Color3.fromRGB(218, 202, 150), -- светлая охра
	} :: { Color3 },

	-- true — свободная база выбирается случайно; false — первая свободная по номеру.
	RandomAssignment = true,

	-- Через сколько секунд персонаж возрождается после смерти (на своей базе).
	RespawnDelay = 3,

	-- На сколько studs выше площадки спауна появляется персонаж.
	SpawnHeight = 3.5,

	-- Кулдаун кнопки «Домой» (секунды). Проверяется на сервере.
	HomeCooldown = 5,

	-- ОТЛАДКА: ограничить число баз. nil — по числу меток Workspace.Map.BaseSlots (8).
	-- Например, 2 — и очередь ожидания можно проверить в Studio всего с 3 клиентами.
	MaxBases = nil :: number?,
}

return BaseConfig
