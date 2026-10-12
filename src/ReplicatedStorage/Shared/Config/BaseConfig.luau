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
}

local BaseConfig = {
	-- Соседние базы чередуют тёплые и холодные цвета, чтобы их было легко различить издалека.
	Colors = {
		{ Id = "Red", Name = "Красная", Color = Color3.fromRGB(212, 74, 64) },
		{ Id = "Blue", Name = "Синяя", Color = Color3.fromRGB(62, 114, 200) },
		{ Id = "Yellow", Name = "Жёлтая", Color = Color3.fromRGB(230, 190, 62) },
		{ Id = "Purple", Name = "Фиолетовая", Color = Color3.fromRGB(128, 92, 192) },
		{ Id = "Orange", Name = "Оранжевая", Color = Color3.fromRGB(226, 136, 56) },
		{ Id = "Cyan", Name = "Лазурная", Color = Color3.fromRGB(40, 160, 214) },
		{ Id = "Pink", Name = "Розовая", Color = Color3.fromRGB(210, 108, 158) },
		{ Id = "Green", Name = "Изумрудная", Color = Color3.fromRGB(50, 156, 110) },
	} :: { BaseColor },

	-- Спокойные тона стен домов (по номеру базы), чтобы 8 участков не были одинаковыми.
	-- Красятся детали шаблона с атрибутом WallTone = true (оттенок — атрибут WallShade, как AccentShade).
	WallTones = {
		Color3.fromRGB(238, 226, 200), -- сливочный
		Color3.fromRGB(206, 222, 180), -- шалфей
		Color3.fromRGB(232, 210, 170), -- песочный
		Color3.fromRGB(196, 214, 230), -- голубоватый
		Color3.fromRGB(244, 240, 230), -- белёный
		Color3.fromRGB(222, 196, 160), -- светлое дерево
		Color3.fromRGB(236, 214, 204), -- розоватый
		Color3.fromRGB(232, 214, 160), -- светлая охра
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
