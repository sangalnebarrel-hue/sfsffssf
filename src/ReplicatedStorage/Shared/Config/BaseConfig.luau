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
		{ Id = "Red", Name = "Красная", Color = Color3.fromRGB(232, 65, 58) },
		{ Id = "Orange", Name = "Оранжевая", Color = Color3.fromRGB(245, 145, 40) },
		{ Id = "Yellow", Name = "Жёлтая", Color = Color3.fromRGB(250, 208, 45) },
		{ Id = "Green", Name = "Изумрудная", Color = Color3.fromRGB(16, 160, 104) }, -- темнее травы
		{ Id = "Cyan", Name = "Бирюзовая", Color = Color3.fromRGB(40, 200, 210) },
		{ Id = "Blue", Name = "Синяя", Color = Color3.fromRGB(50, 120, 235) },
		{ Id = "Purple", Name = "Фиолетовая", Color = Color3.fromRGB(150, 85, 225) },
		{ Id = "Pink", Name = "Розовая", Color = Color3.fromRGB(240, 110, 190) },
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
