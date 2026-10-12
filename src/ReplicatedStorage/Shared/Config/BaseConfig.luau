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
	Colors = {
		{ Id = "Red", Name = "Красная", Color = Color3.fromRGB(212, 74, 64) },
		{ Id = "Orange", Name = "Оранжевая", Color = Color3.fromRGB(226, 136, 56) },
		{ Id = "Yellow", Name = "Жёлтая", Color = Color3.fromRGB(228, 188, 62) },
		{ Id = "Green", Name = "Изумрудная", Color = Color3.fromRGB(50, 156, 110) }, -- холоднее травы
		{ Id = "Cyan", Name = "Бирюзовая", Color = Color3.fromRGB(48, 156, 170) },
		{ Id = "Blue", Name = "Синяя", Color = Color3.fromRGB(62, 114, 200) },
		{ Id = "Purple", Name = "Фиолетовая", Color = Color3.fromRGB(128, 92, 192) },
		{ Id = "Pink", Name = "Розовая", Color = Color3.fromRGB(210, 108, 158) },
	} :: { BaseColor },

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
