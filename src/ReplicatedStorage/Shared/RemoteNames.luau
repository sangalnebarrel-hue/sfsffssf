--!strict
--[[
	RemoteNames — список всех RemoteEvent / RemoteFunction игры.

	Сборщик места создаёт их в ReplicatedStorage.Remotes, а модуль Net выдаёт их по имени.
	Чистый модуль (без require), его читает сборщик.

	Правило безопасности: всё, что приходит от клиента, сервер проверяет сам
	(типы аргументов, расстояние, кулдауны, владение, деньги).

	Уведомления: Notify сервер → клиент: (text, kind). kind — "info" | "success" | "warning" |
	"danger" или Id редкости ("Legendary" | "Mythic") для объявления о редкой рыбе другого
	игрока — одной строкой «Кто: что» («Рыбак (Лазурная база): мифическая радужная рыба
	«Рыба-дракон» ×5!»; NotifyController делит её по первому ": " на две строки и рисует в цветах
	редкости, незнакомый kind — как "info").

	Рыбалка (Этап 2, FishingService ↔ FishingController). Клиент только просит, сервер решает:
	  FishingCast  клиент → сервер: () — забросить (удочка в руке, у точки рыбалки своей базы)
	  FishingHook  клиент → сервер: () — подсечь во время поклёвки
	  FishingTap   клиент → сервер: (elapsed: number) — нажатие в мини-игре; elapsed — сколько
	               секунд мини-игры прошло у клиента с получения состояния "Minigame"
	  FishingStop  клиент → сервер: () — смотать леску
	  FishingState сервер → клиент: (state: string, data: table?) — что происходит с рыбалкой
	               этого игрока:
	    "Waiting"  { Target: Vector3, WindUp: number, FlightTime: number } — заброс принят, ждём
	               поклёвку (замах WindUp с, потом полёт FlightTime с)
	    "Bite"     { Window: number } — клюёт! есть Window секунд на подсечку
	    "Minigame" { Rarity, U0, Speed, ZoneCenter, ZoneWidth, Hits, HitsNeeded, Timeout } — старт
	               мини-игры (стрелка: FishingRules.Needle(U0, Speed, t))
	    "Zone"     { ZoneCenter, Hits } — попал, зона переехала (нужно ещё HitsNeeded − Hits)
	    "Caught"   { Fish: FishData, Total: number, Tank: TankResult? } — поймал (Total — рыб за
	               сессию). Этап 3: у Fish ещё Uid? (номер рыбы в садке) и New? (первый улов вида за
	               всё время); Tank — что стало с рыбой в садке (TankResult, ниже); нет Tank — садок
	               её не принял (выход / закрытие сервера): карточка играет, счётчик садка не меняется
	    "Lost"     { Reason: "early" | "late" | "miss" | "timeout", Text: string } — рыба ушла
	    "Idle"     { Reason: "stop" | "moved" | "unequipped" | "died" | "base" } — рыбалка закончилась
	    "Denied"   { Reason: "far" | "nobase" | "busy" | "cooldown" | "norod" | "loading", Text: string }
	               — заброс не принят ("loading", Этап 3: данные игрока ещё грузятся)
	Состояние для всех игроков (атрибуты Player, их видят все клиенты — поплавки и лески):
	  FishingState ("Idle" | "Waiting" | "Bite" | "Reeling"), BobberTarget (Vector3),
	  CastTime (workspace:GetServerTimeNow() в миг, когда поплавок срывается с кончика удочки:
	    заброс + FishingConfig.CastWindUp — до него клиенты показывают замах), RodId, FishCaught (число),
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

	Садок и деньги (Этап 3, TankService / MarketService ↔ TankPanelController и др.). Клиент
	никогда не присылает суммы, цены, слоты и описания рыб — только номер рыбы:
	  TankSell  клиент → сервер: (uid: string) — продать одну рыбу своего садка. Проверки по
	            порядку: 1) uid — строка вида "f<цифры>" не длиннее 12 знаков (иначе молча
	            отбросить); 2) лимит запросов игрока TankConfig.Requests (Burst 6, Rate 3 в секунду;
	            из него же и каждый ответ, "Denied" тоже; пусто — молча отбросить); 3) данные
	            игрока можно менять (DataService:CanWrite, иначе Denied "loading"); 4) у игрока есть
	            база (иначе "nobase"); 5) рыба есть в садке ЭТОГО игрока и не спит (иначе "missing" —
	            это же и двойное нажатие); 6) рыбу сейчас не крадут (Этап 4, иначе "locked");
	            7) цену и ставку считает сервер (TankRules.SellPrice); не конечное число — warn,
	            ничего не меняется. Между проверкой и изменением — ни одного ожидания.
	  TankEvent сервер → клиент: (kind: string, data: table):
	    "Open"   { Place: "Tank" | "Market" | "Kiosk1".."Kiosk4", RatePct: number, Name: string } —
	             кнопка ProximityPrompt открыла панель садка (только открыть; ставку в миг продажи
	             решает сервер)
	    "Sold"   { Items: { { Uid, Id, Rarity, Mutation?, Price } }, Amount: number, RatePct: number,
	             Place: string? } — продано (в Этапе 3 — одна рыба; список — на будущее)
	    "Stored" TankResult + { Fish: FishData } — рыба легла в садок не из улова (Этап 4: кража)
	    "Denied" { Reason: "loading" | "nobase" | "missing" | "locked", Text: string } — продажа
	             не принята (тексты — TankConfig.Texts.Denied)
	  TankResult = { Result: "stored" | "replaced" | "sold", Slot: number?, Uid: string?,
	    Count: number, Slots: number, Replaced: { Uid, Id, Rarity, Mutation?, Price }?, Price: number?,
	    First: boolean? } — "stored": легла в свободную витрину Slot; "replaced": садок был полон,
	    она заменила рыбу послабее (Replaced — та, что продана за Price); "sold": садок полон и она
	    слабее всех — сразу продана за Price; Count / Slots — рыб в садке / открыто витрин после
	    этого; First — первая рыба за всё время (уведомление и «!» на кнопке «САДОК»).
	Нет RemoteFunction и InvokeClient.

	Состояние садка и денег (атрибуты; StreamingEnabled = false — tools/build.luau):
	  Player: Money (целое), Income ($/с, с десятыми), TankCount (рыб в садке, не спящих),
	    TankSlots (открытых витрин: min(TankSlots, MaxSlots)), SellRatePct (100 | 150 — ставка по
	    последней проверке сервера), SellPlace ("" | "Market" | "Kiosk1".."Kiosk4"), DataMode
	    ("Loading" | "Ready" | "Memory"; сломанный DataStore — тоже "Memory").
	  leaderstats: IntValue «Деньги», IntValue «Доход/с» (EconomyConfig.Leaderstats).
	  Модель садка Base_N.Tank: Count, Slots, Income — пишутся при изменении (их видят все).
	  Витрина Base_N.Tank.Slots.Slot_K (пишутся только при изменении): State ("empty" | "fish" |
	    "locked"; у свободной базы — все "empty"); при State = "fish" — FishUid, FishId, Rarity,
	    Mutation (нет — без мутации или незнакомая), Kg, Value (цена ×1), Income (Income10 / 10),
	    GrowFrom (= TankRules.AttrTime(workspace:GetServerTimeNow() − Age): цена сейчас —
	    TankRules.CurrentValue(Value, GetServerTimeNow() − GrowFrom)); Event — что случилось:
	    "<n>|in|<FishId>" (легла), "<n>|mount|" (база заняла витрины: тихо, без всплеска),
	    "<n>|sold|<цена>" (продана), "<n>|swap|<цена>" (заменена другой), Этап 4: "<n>|stolen|".
	    Порядок записи: поля рыбы → State → Event ПОСЛЕДНИМ; у "empty" и "locked" все поля рыбы —
	    nil. n растёт у базы всё время работы сервера (не сбрасывается — новая строка всегда
	    другая). За кадр до клиента доходит только последнее Event витрины — поэтому "swap"
	    одним событием. Клиент перечитывает витрину ТОЛЬКО по Event (и один раз, когда строит
	    базу): при "swap" State остаётся "fish", а FishUid меняется.
	  Время в атрибутах — через TankRules.AttrTime (+1/1024 с к целым): Lune (симулятор) хранит
	    целые числа атрибутов как float32 (1700000123 читается 1700000128); в Roblox атрибуты —
	    double, добавка меньше 1 мс.
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
		"TankSell", -- клиент → сервер: (uid: string) — продать рыбу садка (Этап 3)
		"TankEvent", -- сервер → клиент: (kind: string, data: table) — события садка (Этап 3)
	},
	Functions = {} :: { string },
}

return RemoteNames
