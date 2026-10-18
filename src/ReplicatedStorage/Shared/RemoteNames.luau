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
	            6b) это не краденая рыба «в пути» (Этап 4, Escrow, иначе "escrow"); 7) цену и ставку
	            считает сервер (TankRules.SellPrice); не конечное число — warn, ничего не меняется.
	            Между проверкой и изменением — ни одного ожидания.
	  TankEvent сервер → клиент: (kind: string, data: table):
	    "Open"   { Place: "Tank" | "Market" | "Kiosk1".."Kiosk4", RatePct: number, Name: string } —
	             кнопка ProximityPrompt открыла панель садка (только открыть; ставку в миг продажи
	             решает сервер)
	    "Sold"   { Items: { { Uid, Id, Rarity, Mutation?, Price } }, Amount: number, RatePct: number,
	             Place: string? } — продано (в Этапе 3 — одна рыба; список — на будущее)
	    "Stored" TankResult + { Fish: FishData } — рыба легла в садок не из улова (Этап 4: кража)
	    "Denied" { Reason: "loading" | "nobase" | "missing" | "locked" | "escrow", Text: string } —
	             продажа не принята (тексты — TankConfig.Texts.Denied)
	  TankResult = { Result: "stored" | "replaced" | "sold", Slot: number?, Uid: string?,
	    Count: number, Slots: number, Replaced: { Uid, Id, Rarity, Mutation?, Price }?, Price: number?,
	    First: boolean? } — "stored": легла в свободную витрину Slot; "replaced": садок был полон,
	    она легла в витрину Slot вместо рыбы послабее (Replaced — та, что продана, Replaced.Price —
	    за сколько); "sold": садок полон и она слабее всех — сразу продана; Count / Slots — рыб в
	    садке / открыто витрин после этого; First — первая рыба за всё время (уведомление и «!» на
	    кнопке «САДОК»). Price — ВСЕГДА монеты, которые этот улов зачислил (их и празднует клиент:
	    MoneyController.Celebrate(Price, …)): "replaced" — Price == Replaced.Price (продана старая),
	    "sold" — цена самой новой рыбы, "stored" — nil (ничего не продано). Деньги уже в атрибуте
	    Money, когда приходит "Caught" (порядок сервера: зачисление → атрибуты → remote'ы).
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
	    "<n>|in|<FishId>" (легла), "<n>|mount|" (садок занял или освободил витрины базы: тихо,
	    без всплеска),
	    "<n>|sold|<цена>" (продана), "<n>|swap|<цена>" (заменена другой), Этап 4:
	    "<n>|stolen|<UserId вора>" (украдена: громко, искры к вору) и "<n>|void|" (краденую рыбу
	    вернули хозяину — её запись у жертвы так и не легла: тихо).
	    Порядок записи: поля рыбы → State → Event ПОСЛЕДНИМ; у "empty" и "locked" все поля рыбы —
	    nil. n растёт у базы всё время работы сервера (не сбрасывается — новая строка всегда
	    другая). За кадр до клиента доходит только последнее Event витрины — поэтому "swap"
	    одним событием. Клиент перечитывает витрину ТОЛЬКО по Event (и один раз, когда строит
	    базу): при "swap" State остаётся "fish", а FishUid меняется.
	  Время в атрибутах — через TankRules.AttrTime (+1/1024 с к целым): Lune (симулятор) хранит
	    целые числа атрибутов как float32 (1700000123 читается 1700000128); в Roblox атрибуты —
	    double, добавка меньше 1 мс.

	Кража и защита (Этап 4, StealService / DefenceService ↔ TheftController, AlertController,
	DefenceController, TheftWorldController; docs/stage4_design.md §4.10, §4.11). У кражи НЕТ
	remote'а клиент → сервер: только кнопки ProximityPrompt "StealPrompt" у витрин (сервер сам
	считает удержание). Клиент никогда не присылает цены, уровни, слоты, uid и позиции:
	  StealEvent     сервер → клиент: (kind: string, data: table):
	    вору:   "Denied" { Reason, Text, Quiet?, BaseIndex, Slot } — кража не началась (причины и
	            тексты — Shared/TheftChecks и StealConfig.Texts.Denied; Quiet — тот же отказ
	            меньше Limits.DeniedEvery с назад: без текста, но клиент гасит кольцо этой кнопки);
	            "Hold" { Slot, BaseIndex, Uid, FishId, Rarity, Mutation?, Short, Income10, End,
	            Need } — удержание началось (End — серверное время конца, Need — секунд);
	            "Carry" { End } — рыба на голове, неси за ограду до End; "Cancel" { Reason, Text,
	            Phase } — сорвалось (Phase "hold" | "carry"; тексты — StealConfig.Texts.Cancel);
	            "Done" { Fish, Result, Name } — рыба твоя (Fish — FishData, Result — TankResult,
	            Name — DisplayName хозяина);
	    жертве: "Alert" { Phase, Thief, Name, Slot, FishId, Rarity, Mutation?, Short, Income10,
	            End, Quiet? } — у тебя крадут (при начале удержания и при начале выноса; громко —
	            не чаще раза в Limits.AlertCoalesce с на пару вор–жертва, остальные Quiet);
	            "Saved" { Reason, Slot, Text, Quiet? } — рыба спасена; "Lost" { Fish, Name, Until,
	            Kind } — украли (Until / Kind — твоя защита теперь: "after" | "rest");
	            "Intruder" { Thief, Name } — гость во дворе (только с сигнализацией);
	    обоим:  "Returned" { Fish, Text } — краденую рыбу вернули хозяину (вор ушёл или запись
	            жертвы так и не легла: StealConfig.Texts.Result).
	  ShieldActivate клиент → сервер: () (аргументы не читаются) — включить щит. Проверки по
	            порядку: 1) лимит DefenceConfig.Requests (Burst 4, Rate 1/с; пусто — молча);
	            2) CanWrite ("loading"); 3) своя подключённая база ("nobase"); 4) игрок не крадёт
	            сам — спросить StealService через DefenceService:SetStealProbe ("stealing");
	            5) защиты осталось меньше Shield.StackBelow с ("protected"); 6) щит готов —
	            сейчас ≥ ShieldReadyAt ("cooldown"). Принято → защита, атрибуты, SaveSoon, кража на
	            базе отменена (удержание) или рыба вернулась (вынос), DefenceEvent("Shield").
	  DefenceBuy     клиент → сервер: (item: "Dog" | "Alarm" | "Lock") — купить защиту. Проверки по
	            порядку: 1) строка и знакомый предмет (иначе молча); 2) лимит; 3) CanWrite
	            ("loading"); 4) своя база ("nobase"); 5) Dog / Alarm уже есть — "owned"; Lock на
	            #Levels — "max", на Lock.SaleMax — "soon"; 6) цена только из DefenceConfig,
	            EconomyService:SpendMoney(…, "defence:<item>") не вышел — "money"; 7) купить
	            (Upgrades или уровень замка), атрибуты, SaveSoon, DefenceEvent("Bought").
	  DefenceEvent   сервер → клиент: (kind: string, data: table): "Bought" { Item, Level?, Price },
	            "Denied" { Item?, Reason, Text } (тексты — DefenceConfig.Texts.Denied), "Shield"
	            { Until, ReadyAt } (серверное время).
	Состояние (атрибуты; время — через TankRules.AttrTime):
	  Player: Stealing ("hold" | "carry"; пишется ПОСЛЕДНИМ), StealCooldownUntil, Slowed (true, пока
	    собака держит вора — пишет Lib/Speed при появлении и уходе), ShieldUntil, ShieldReadyAt
	    (открыты всем, но чужую готовность щита интерфейс не показывает), HasDog, HasAlarm,
	    LockLevel; доход Income (Этап 3) — для фильтра «намного слабее».
	  Модель базы Base_N: ProtectUntil, ProtectKind ("shield" | "join" | "newbie" | "after" |
	    "rest"; nil, когда кончилась), AlarmState ("theft" | "intruder"), Thief (UserId вора),
	    HasDog, HasAlarm, LockLevel, HoldTime. Всё снимается при отключении садка (до того, как базу
	    получит другой).
	  Витрина Slot_K — отдельный канал, Event не трогает: StealBy (UserId вора), StealEnd (конец
	    удержания / выноса), StealPhase ("hold" | "carry"; пишется ПОСЛЕДНИМ и снимается последним),
	    Escrow (true — у вора: рыба «в пути», не продаётся и не крадётся), FreshUntil (свежий улов:
	    до этого времени не крадётся). Клиенты слушают StealPhase, Escrow и FreshUntil.
	  Собака Base_N.Dog: Unlocked, DogState ("Sleep" | "Alert" | "Chase" | "Return"), DogPos
	    (Vector3 мира; не чаще Dog.Replicate с и только после сдвига), DogTarget (UserId вора).
	  Персонаж вора: модель StolenFish (рыба на голове: FishId, Rarity, Mutation, Kg, Value, Scale,
	    Owner = UserId хозяина).
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
		"StealEvent", -- сервер → клиент: (kind: string, data: table) — кража: вору и жертве (Этап 4)
		"ShieldActivate", -- клиент → сервер: () — включить щит (Этап 4)
		"DefenceBuy", -- клиент → сервер: (item: "Dog" | "Alarm" | "Lock") — купить защиту (Этап 4)
		"DefenceEvent", -- сервер → клиент: (kind: string, data: table) — щит и покупки (Этап 4)
	},
	Functions = {} :: { string },
}

return RemoteNames
