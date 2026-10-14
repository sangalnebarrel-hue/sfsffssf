--!strict
--[[
	RemoteNames — список всех RemoteEvent / RemoteFunction игры.

	Сборщик места создаёт их в ReplicatedStorage.Remotes, а модуль Net выдаёт их по имени.
	Чистый модуль (без require), его читает сборщик.

	Правило безопасности: всё, что приходит от клиента, сервер проверяет сам
	(типы аргументов, расстояние, кулдауны, владение, деньги).

	Уведомления: Notify сервер → клиент: (text, kind). kind — "info" | "success" | "warning" |
	"danger" или Id редкости ("Legendary" | "Mythic") для объявления о редкой рыбе другого
	игрока («Рыбак: мифическая рыба «Рыба-дракон» ×2!»; NotifyController рисует его в цветах редкости,
	незнакомый kind — как "info").

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
	  CastTime (workspace:GetServerTimeNow() в момент заброса), RodId, FishCaught (число),
	  FishFx (строка) — событие для эффектов в мире (FishingFxController), ставится ДО того, как
	    FishingState станет "Idle" (поплавок ещё на воде):
	    "<номер>|caught|<FishId>|<Mutation или ''>|<Rarity>" — поймал: рыба выпрыгивает у поплавка
	      и за FishingConfig.LeapTime летит к рыбаку; рыба над головой (модель HeldFish в персонаже,
	      её ставит сервер) появляется, когда прыжок закончился, и висит
	      FishingRules.HoldFishTime(Rarity) секунд; у HeldFish атрибуты FishId, Rarity, Mutation,
	      Kg, Value (по ним клиенты рисуют табличку над рыбой). На клиенте самого рыбака
	      FishingFxController.OwnFishLanded срабатывает в кадр, когда его рыба долетела;
	    "<номер>|lost|<FishId или ''>|<Mutation или ''>|<Rarity или ''>" — рыба ушла (до подсечки
	      рыбы ещё нет — поля пустые).
	    Номер растёт с каждым событием игрока (одинаковые события подряд — разные строки).
]]

local RemoteNames = {
	Events = {
		"Notify", -- сервер → клиент: (text: string, kind: "info"|"success"|"warning"|"danger"|<Rarity Id>)
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
