--!strict
--[[
	RemoteNames — список всех RemoteEvent / RemoteFunction игры.

	Сборщик места создаёт их в ReplicatedStorage.Remotes, а модуль Net выдаёт их по имени.
	Чистый модуль (без require), его читает сборщик.

	Правило безопасности: всё, что приходит от клиента, сервер проверяет сам
	(типы аргументов, расстояние, кулдауны, владение, деньги).
]]

local RemoteNames = {
	Events = {
		"Notify", -- сервер → клиент: (text: string, kind: "info"|"success"|"warning"|"danger")
		"RequestHome", -- клиент → сервер: () — телепорт на свою базу
	},
	Functions = {} :: { string },
}

return RemoteNames
