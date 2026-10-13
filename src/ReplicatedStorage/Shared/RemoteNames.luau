--!strict
--[[
	RemoteNames — список всех RemoteEvent / RemoteFunction игры.

	Сборщик места создаёт их в ReplicatedStorage.Remotes, а модуль Net выдаёт их по имени.
	Чистый модуль (без require), его читает сборщик.

	Правило безопасности: всё, что приходит от клиента, сервер проверяет сам
	(типы аргументов, расстояние, кулдауны, владение, деньги).

	Рыбалка (Этап 2, FishingService ↔ FishingController). Клиент только просит, сервер решает:
	  FishingCast  клиент → сервер: () — забросить (удочка в руке, у точки рыбалки своей базы)
	  FishingHook  клиент → сервер: () — подсечь во время поклёвки
	  FishingTap   клиент → сервер: (elapsed: number) — нажатие в мини-игре; elapsed — сколько
	               секунд мини-игры прошло у клиента с получения состояния "Minigame"
	  FishingStop  клиент → сервер: () — смотать леску
	  FishingState сервер → клиент: (state: string, data: table?) — что происходит с рыбалкой
	               этого игрока:
	    "Waiting"  { Target: Vector3, FlightTime: number } — заброс принят, ждём поклёвку
	    "Bite"     { Window: number } — клюёт! есть Window секунд на подсечку
	    "Minigame" { Rarity, U0, Speed, ZoneCenter, ZoneWidth, Hits, HitsNeeded, Timeout } — старт
	               мини-игры (стрелка: FishingRules.Needle(U0, Speed, t))
	    "Zone"     { ZoneCenter, Hits } — попал, зона переехала (нужно ещё HitsNeeded − Hits)
	    "Caught"   { Fish: FishData, Total: number } — поймал (Total — рыб за сессию)
	    "Lost"     { Reason: "early" | "late" | "miss" | "timeout", Text: string } — рыба ушла
	    "Idle"     { Reason: "stop" | "moved" | "unequipped" | "died" | "base" } — рыбалка закончилась
	    "Denied"   { Reason: "far" | "nobase" | "busy" | "cooldown" | "norod", Text: string } — заброс
	               не принят
	Состояние для всех игроков (атрибуты Player, их видят все клиенты — поплавки и лески):
	  FishingState ("Idle" | "Waiting" | "Bite" | "Reeling"), BobberTarget (Vector3),
	  CastTime (workspace:GetServerTimeNow() в момент заброса), RodId, FishCaught (число).
]]

local RemoteNames = {
	Events = {
		"Notify", -- сервер → клиент: (text: string, kind: "info"|"success"|"warning"|"danger")
		"RequestHome", -- клиент → сервер: () — телепорт на свою базу
		"FishingCast", -- клиент → сервер: ()
		"FishingHook", -- клиент → сервер: ()
		"FishingTap", -- клиент → сервер: (elapsed: number)
		"FishingStop", -- клиент → сервер: ()
		"FishingState", -- сервер → клиент: (state: string, data: table?)
	},
	Functions = {} :: { string },
}

return RemoteNames
