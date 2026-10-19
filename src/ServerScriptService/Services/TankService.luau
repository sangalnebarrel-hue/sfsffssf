--!strict
--[[
	TankService — садок игрока (Этап 3): рыбы в витринах двора базы (Tank.Slots.Slot_1..12),
	открытые витрины, «спящие» рыбы, правило полного садка, продажа, общий цикл дохода раз в
	секунду, атрибуты витрин и садка, таблички и подсветка витрин, кнопка у большого аквариума,
	remote'ы садка и хук сохранения. Правила и вид сумм — TankRules, числа — TankConfig /
	EconomyConfig, данные — DataService (поля Tank, TankSlots, NextUid, Stats.Sold — его).
	Подробно — docs/stage3_design.md, §3.3, §4.3, §4.5, §4.6, §5.2.

	Что делает:
	  1. Init: у каждой базы ссылки витрин Slot_1..12 — Pedestal, Display, Display.FishPoint,
	     Pedestal.LabelGui.Label, LightBar и его SurfaceLight (нет — громкая ошибка), и вид
	     шаблона (его возвращают пустым витринам); у всех витрин State = "empty"; кнопка
	     ProximityPrompt "TankPrompt" на Tank.Glass.PromptAttachment (TankConfig.Prompt: «Открыть» /
	     «Садок», HoldDuration 0, MaxActivationDistance 10, RequiresLineOfSight false, Enabled
	     false); хук DataService:OnSerialize (обновить возраст рыб на базе; Этап 4 — skipUid: рыбы
	     «в пути» этого игрока не сохранять, есть у него запись или уже нет).
	  2. DataService.Loaded → записи рыб: Rarity, Value, Income10 — из FishingRules.Price; рыба
	     «спит» (Dormant), если вид незнаком или у неё нет своей витрины (PlayerData.Layout):
	     не видна, без дохода, не продаётся, не заменяется, сохраняется как есть. Атрибуты игрока
	     TankCount / TankSlots.
	  3. «Подключение» садка к базе — когда у игрока есть И данные, И база (что второе; и
	     BaseService.BaseAssigned): GrowFrom = AttrTime(сейчас − Age) каждой активной рыбы,
	     витрины 1..12 (атрибуты, таблички, подсветка) с Event "<n>|mount|", атрибуты садка и
	     игрока, доход, кнопка включена. Отключение (BaseReleased, выход): Age каждой рыбы замирает,
	     все витрины — "empty" / «Пусто» / вид шаблона, поля рыбы — nil, Event "<n>|mount|" (тихо
	     перечитать), атрибуты садка сняты, доход игрока 0, кнопка выключена.
	  4. Улов: FishingService.SetCatchSink(sink) (только если это функция — заглушки сервисов в
	     тестах); sink(player, fish) -> TankResult? — nil без CanWrite или без базы (это лишь
	     гонка выхода / закрытия: заброс до загрузки не принимается), иначе AddFish(player, fish,
	     "catch"). Синхронно, без ожиданий.
	  5. AddFish(player, fish, reason) — за DataService:CanWrite. Сначала посчитать: цену и
	     доход заново (FishingRules.Price — клиенту и улову не верим), решение полного садка, цены
	     продажи; потом менять: data.Tank (Uid = PlayerData.NewUid) → записи →
	     EconomyService:AddMoney(…, "autosell") при "replaced" / "sold" → Stats.Sold + 1 → атрибуты
	     витрины (Event последним) → доход → атрибуты → FishRemoved / FishAdded. Полный садок:
	       есть свободная открытая витрина → в самую младшую → "stored" (Event "<n>|in|<FishId>");
	       иначе слабейшая активная (не Locked: её не крадут и она не «в пути»; не Dormant) —
	       TankRules.ChooseReplacement: доход новой больше → слабейшую продать по SellPrice(…,
	       возраст сейчас, HomeRatePct), новая на её место → "replaced" (Event "<n>|swap|<цена>");
	       иначе новую продать сразу по SellPrice(Value, 0, HomeRatePct) → "sold" (витрины не
	       меняются, номер не тратится).
	     Возвращает TankResult { Result, Slot?, Uid?, Count, Slots, Replaced?, Price?, First? }
	     (First — улов и Stats.Caught == 1: первое уведомление и «!»). Price — ВСЕГДА монеты, которые
	     зачислил этот AddFish (клиент празднует именно их): "replaced" — Price == Replaced.Price
	     (цена проданной слабейшей), "sold" — цена новой рыбы, "stored" — nil. Рыба не из улова
	     (Этап 4: кража) — ещё и TankEvent("Stored", результат + { Fish }), и в запись идёт её
	     fish.Origin («<UserId жертвы>:<uid>»; строка не длиннее DataConfig.Limits.OriginMax, иначе
	     без него — у улова Origin нет). Без базы (Этап 4: вор в очереди) — только данные, витрины
	     покажет подключение.
	  6. Продажа TankSell(uid) — проверки по порядку из шапки RemoteNames (uid, лимит запросов
	     Lib.TankRequests — из него же каждый ответ, CanWrite, база, своя активная рыба, её не
	     крадут — "locked", она не «в пути» — "escrow", конечная цена), потом без ожиданий: возраст сейчас и цена
	     TankRules.SellPrice(Value, ageNow, MarketService:RatePct(player)), убрать из data.Tank
	     (плотно) и записей, AddMoney(…, "sell"), Stats.Sold + 1, витрина ("empty", поля nil, Event
	     "<n>|sold|<цена>"), доход, TankEvent("Sold", { Items, Amount, RatePct, Place }),
	     FishRemoved.
	  7. Кнопка "TankPrompt" (Triggered) — через тот же лимит запросов; только хозяину базы и после
	     проверки расстояния сервером (≤ MaxDistance + Slack): TankEvent("Open", { Place = "Tank",
	     RatePct = атрибут SellRatePct, Name = «Садок» }).
	  8. Цикл дохода — ОДИН task.spawn на сервер: dt = task.wait(IncomeTick), накопитель с
	     фиксированным шагом (acc += dt; n = floor(acc / IncomeTick); acc −= n · IncomeTick;
	     n = min(n, MaxCatchUp)); по записям ЭТОГО сервиса (не Players:GetPlayers), только
	     подключённым и с CanWrite: carry10 += n · Income10Sum, целые монеты — AddMoney(…, "income"),
	     остаток (десятые) копится; возраст рыб для сохранения; MarketService:Sample(player). Шаг
	     игрока — в xpcall (warn не чаще раза в WARN_EVERY с), сам цикл — вне pcall: одна плохая
	     запись не останавливает всех. Ничего не ждёт (HumanoidRootPart — FindFirstChild).
	  9. Возраст: ageNow = clamp(GetServerTimeNow() − GrowFrom, 0, Time) — та же формула и те же
	     часы, что у клиента (TankRules.AgeAt; GrowFrom записи = атрибут витрины); продажа — по
	     ageNow в её миг; без базы (очередь) — ни дохода, ни роста. Income10Sum пересчитывается
	     только при изменении садка; атрибуты Income (игрок и садок) и «Доход/с» — при изменении,
	     не каждый тик.
	Записи игроков — по самому Player (повторный вход — новый Player) с проверкой «это всё ещё
	она»; соединений на игрока нет (одно Triggered на базу, общие события сервисов), всё на игрока —
	записи этого модуля, удаляются при выходе; без бесконечных списков (DataService, «Правила»).

	Вид витрины на сервере (при изменении): "empty" / свободная база — табличка «Пусто», LightBar
	как в шаблоне (AquaGlow, Neon, свет есть), стекло как в шаблоне (0.66); "fish" — табличка с
	именем рыбы, TextColor3 = цвет редкости (FishConfig), LightBar.Color = цвет редкости
	(UIConfig.Rarity[r].Bottom; мифическая — UIConfig.Rainbow[6]), свет есть, стекло
	Display.Transparency = TankConfig.Display.GlassOccupied; "locked" — «🔒 Закрыто», LightBar
	SmoothPlastic цвета Slate.Bottom, SurfaceLight выключен. Новых деталей на сервере нет.

	Атрибуты (RemoteNames, «Состояние садка и денег»): Player — TankCount, TankSlots (и Income —
	через EconomyService:SetIncome); Base_N.Tank — Count, Slots, Income; витрины — State, FishUid,
	FishId, Rarity, Mutation, Kg, Value, Income, GrowFrom (TankRules.AttrTime), Event
	("<n>|in|<FishId>", "<n>|mount|" — подключение и отключение садка, тихо, "<n>|sold|<цена>",
	"<n>|swap|<цена>", Этап 4 "<n>|stolen|<UserId вора>" и "<n>|void|"; поля рыбы → State → канал
	кражи (StealBy, StealEnd, Escrow, FreshUntil, StealPhase последним) → Event последним; пишутся
	только изменившиеся; n растёт у базы всё время работы сервера).
	Remote'ы: TankSell (клиент → сервер), TankEvent (сервер → клиент), StealEvent "Returned" (сервер →
	клиент, Этап 4) — протокол в RemoteNames.

	Этап 5 (магазин): SetSlots(player, n) — открывает следующие витрины (только больше, до любых
	n ≥ текущего; в игре — не больше MaxSlots: атрибуты, таблички) и будит «спящих» знакомых рыб
	в новых витринах.

	Этап 4 — кража (docs/stage4_design.md §3.2–§3.4, §4.5; StealService только зовёт SetSteal и
	StealFish, весь переход рыбы — здесь):
	  10. SetSteal(owner, uid, token, phase, info?) — «держатель» рыбы: пока её крадут (hold /
	     carry), второй токен её не возьмёт; рыба «в пути» и спящая — никогда. Канал кражи витрины
	     (отдельно от Event): StealBy, StealEnd, потом StealPhase ПОСЛЕДНИМ; снятие — так же,
	     StealPhase последним. "carry" — рыба уже на голове вора: дохода хозяину не даёт. SetLocked —
	     тонкая обёртка (токен −1, без атрибутов: Этап 3).
	  11. StealFish(victim, thief, uid, token) — у ограды, в наблюдателе StealService, без ожиданий:
	     ПРОВЕРКА — полный план, ничего не меняя (оба CanWrite и подключены; рыба активна, её
	     токен и фаза "carry"; место у вора: свободная витрина или слабейшая не Locked рыба
	     слабее добычи — иначе nil, "full"; новый Uid вора подсмотрен; цены конечны; Origin
	     «<UserId жертвы>:<uid>» у вора ещё нет); ПОТОМ — по порядку, только таблицы и атрибуты:
	     0) запись «в пути» escrows[вор][новый uid] (Seq = ∞: с этого мига сохранения вора её
	     пропускают, и ни один Committed с ней не совпадёт); 1) жертва: рыба убрана (данные,
	     записи, витрина «empty» → Event "<n>|stolen|<UserId вора>"), доход, Stats.Lost + 1;
	     2) вор: NextUid + 1, при "replaced" — слабейшая убрана (денег пока нет), строка добычи
	     (Age — как у жертвы, CaughtAt — сейчас, Origin), её запись с Escrow, витрина (Escrow =
	     true до Event "in" / "swap"), доход (рыба «в пути» дохода не даёт), Stats.Stolen + 1;
	     3) Seq = SaveSoon(жертва); 4) не DataStore или запись жертвы уже ≥ Seq — снять «в пути»
	     сразу; 5) потом деньги ("replaced": AddMoney(вор, цена его слабейшей, "autosell"),
	     Stats.Sold + 1), SlotChanged ×2, FishRemoved / FishAdded, TankEvent("Stored") вору.
	  12. «В пути» (escrow) снимается ТОЛЬКО записью жертвы: DataService.Committed(жертва, seq ≥
	     Seq) — снять (запись первой, рыба начинает приносить доход, SaveSoon(вор));
	     DataService.Released(жертва, committed) — каждая её запись: committed ≥ Seq — снять,
	     иначе — «аннулировать» (void: рыба уходит из садка вора тихо, Event "<n>|void|",
	     Stats.Stolen − 1, вору StealEvent "Returned" «Рыба вернулась к хозяину»; монеты за его
	     проданную слабейшую остаются). НИКОГДА по таймеру: таймер — единственный путь к дюпу.
	     Записи — по самому Player жертвы (её запись, не UserId: перезаход — другая запись).
	     Без дюпа, но не без потерь при сбоях DataStore (§3.3, A1-03): после «снять» рыба только в
	     живых данных вора — его записи так и не легли до выхода — рыба пропала с остальным его
	     несохранённым (F10); «аннулировать» рыбу, которая сама пришла жертве-вору через
	     несохранённое «снять» / возврат, — тоже (F7): снять было бы дюпом.
	     Пока «в пути»: не сохраняется (хук OnSerialize — skipUid), не продаётся (Denied
	     "escrow"), не кандидат замены, не крадётся (TheftChecks "fresh"), без дохода.
	  13. Вор уходит с рыбой «в пути» (PlayerRemoving; и хук DataService:OnClose — при закрытии
	     сервера, раньше последних сохранений): вернуть каждую жертве — запись первой, потом у вора
	     строка убрана из живых данных (Stats.Stolen − 1), и только потом — жертве (упавшая вставка
	     потеряет одну рыбу, но не оставит две). Жертва пишет данные — та же строка (прежний uid;
	     своя витрина, если свободна, иначе младшая свободная), Stats.Lost − 1, SaveSoon(жертва),
	     StealEvent "Returned" «Вор ушёл — рыба вернулась!» { Result = "stored" }; свободных витрин
	     нет (жертва успела поймать рыбу в освободившуюся) — правило полного садка, как у AddFish
	     (A1-01): слабейшая не Locked рыба слабее вернувшейся продана (AddMoney "autosell", Stats.Sold
	     + 1, Event "<n>|swap|<цена>", Result "replaced", Price), иначе продана сама вернувшаяся (её
	     строки нет, Result "sold", Price, текст Result.LeftSold) — монеты жертве в любом случае, ни
	     одна рыба не «спит». Жертва уже уходит, а её последний снимок не снят —
	     DataService:AmendLeaving (та же строка в её живые данные; только Tank: денег уходящей не
	     начислить — при полном садке строка «спит» со своим Slot, пока загрузка не найдёт свободную
	     витрину или SetSlots Этапа 5 её не разбудит); снимок уже снят — правка ждёт: та попытка не
	     записалась — повтор возьмёт рыбу с собой, записалась — одна рыба потеряна (F8c, никогда не
	     две; A1-02). Повторное возвращение и вставка uid, который уже есть, — ничего не делают
	     (§3.4).
	  14. Улов ("catch") — свежий: FreshUntil = сейчас + StealConfig.Limits.FreshCatch (запись и
	     атрибут витрины); краденая и вернувшаяся рыба — без него.
	  15. Канал кражи не переживает подключение: пустая витрина снимает StealBy, StealEnd, Escrow,
	     FreshUntil, потом StealPhase; отключение садка снимает Steal со всех рыб ДО rt.Base = nil.
	  16. Сигналы: Mounted / Unmounted (player, base) — в конце mount / unmount (DefenceService,
	     StealService); SlotChanged (base, index) — после каждой записи витрины (улов, продажа,
	     кража, возврат, «в пути», подключение): StealService обновляет по нему кнопку «Украсть».

	API:
	  TankService:AddFish(player, fish: FishData, reason) -> TankResult?
	  TankService:RemoveFish(owner, uid, reason) -> PlayerData.Fish?
	  TankService:SetLocked(owner, uid, locked) -> boolean
	  TankService:SetSlots(player, n) -> boolean
	  TankService.FishAdded, TankService.FishRemoved   -- Signal (player, fish, reason)
	  Этап 4:
	  TankService:SetSteal(owner, uid, token, phase: "hold" | "carry" | nil, info?) -> boolean
	  TankService:StealFish(victim, thief, uid, token) -> (StealResult?, reason?)
	  TankService:PreviewAdd(player, income10) -> "stored" | "replaced" | nil   -- ляжет ли добыча
	  TankService:SlotFish(base, index) -> (owner?, view?)   -- view = { Uid, Id, ShortName, Rarity,
	                                                   -- Mutation?, Kg, Value, Income10, Steal?,
	                                                   -- Escrow, FreshUntil? }
	  TankService:ActiveCount(player) -> number        -- активные рыбы (и та, что сейчас несут)
	  TankService:IsMounted(player) -> boolean
	  TankService:EscrowCount(player) -> number        -- тесты: рыб «в пути» у вора
	  TankService:Income10(player) -> number           -- доход садка (десятые $/с; 0 — не подключён)
	  TankService.Mounted, TankService.Unmounted       -- Signal (player, base): конец mount / unmount
	  TankService.SlotChanged                          -- Signal (base, index): после записи витрины
	  TankService._debugSizes()                        -- тесты: после выхода всех — нули
	  TankService._runtimeFor(player)                  -- тесты: запись игрока (Ticks — тиков дохода)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local DataConfig = require(Shared.Config.DataConfig)
local EconomyConfig = require(Shared.Config.EconomyConfig)
local StealConfig = require(Shared.Config.StealConfig)
local TankConfig = require(Shared.Config.TankConfig)
local UIConfig = require(Shared.Config.UIConfig)
local FishingRules = require(Shared.FishingRules)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local StealRules = require(Shared.StealRules)
local TankRules = require(Shared.TankRules)
local TextUtil = require(Shared.TextUtil)
local PlayerData = require(ServerScriptService.Lib.PlayerData)
local TankRequests = require(ServerScriptService.Lib.TankRequests)
local BaseService = require(ServerScriptService.Services.BaseService)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local FishingService = require(ServerScriptService.Services.FishingService)
local MarketService = require(ServerScriptService.Services.MarketService)

type FishData = FishingRules.FishData
type Base = BaseService.Base

-- Что продано при замене (TankResult.Replaced, TankEvent "Sold" Items).
export type SoldFish = {
	Uid: string,
	Id: string,
	Rarity: string,
	Mutation: string?,
	Price: number,
}

-- Что стало с рыбой (FishingState "Caught" Tank, TankEvent "Stored").
export type TankResult = {
	Result: "stored" | "replaced" | "sold",
	Slot: number?,
	Uid: string?,
	Count: number,
	Slots: number,
	Replaced: SoldFish?,
	-- монеты, зачисленные этим AddFish: "replaced" — == Replaced.Price, "sold" — цена новой, "stored" — nil
	Price: number?,
	First: boolean?,
}

-- Этап 4: кто держит рыбу для кражи (SetSteal). Quiet — обёртка SetLocked (без атрибутов).
type StealHold = {
	Token: number,
	Phase: string, -- "hold" | "carry"
	By: number?, -- UserId вора (атрибут StealBy)
	End: number?, -- серверное время конца удержания / выноса (атрибут StealEnd)
	Quiet: boolean,
}

-- Этап 4: краденая рыба «в пути» (escrows[вор][uid вора]): ждёт записи жертвы (§3.2).
type Entry = {
	Victim: Player, -- запись жертвы (её Player: перезаход — другая запись)
	VictimUserId: number,
	VictimUid: string,
	Thief: Player,
	ThiefUid: string,
	Seq: number, -- SaveSoon(жертва); до него — math.huge (ни один Committed не совпадёт)
	Row: PlayerData.Fish, -- строка жертвы, как была (её вернёт возврат)
	Fish: FishData, -- чистые данные рыбы (уведомления "Returned")
}

-- Рыба садка в игре (сама запись — Rec, живая строка data.Tank).
type FishRt = {
	Rec: PlayerData.Fish,
	Uid: string,
	Rarity: string,
	Mutation: string?, -- знакомая мутация (незнакомая — как без мутации)
	Value: number, -- цена ×1
	Income10: number, -- доход, десятые в секунду
	GrowFrom: number, -- серверное время «в садке с» (атрибут витрины), пока садок подключён
	Dormant: boolean,
	Steal: StealHold?, -- (Этап 4) её сейчас крадут (или SetLocked)
	Escrow: Entry?, -- (Этап 4) у вора: «в пути», пока запись жертвы не легла
	FreshUntil: number?, -- (Этап 4) свежий улов: не крадётся до этого серверного времени (AttrTime)
}

type Runtime = {
	Player: Player,
	Data: PlayerData.Data,
	Fish: { [string]: FishRt }, -- все рыбы садка по Uid (и спящие)
	BySlot: { [number]: FishRt }, -- активные по витрине
	Base: Base?,
	Mounted: boolean,
	Income10Sum: number,
	Carry10: number, -- десятые монеты, ещё не зачисленные
	Ticks: number, -- тиков дохода зачислено (тесты)
}

-- Вид витрины в шаблоне (его получает пустая витрина).
type SlotLook = {
	LabelText: string,
	LabelColor: Color3,
	BarColor: Color3,
	BarMaterial: Enum.Material,
	LightEnabled: boolean,
	DisplayTransparency: number,
}

type SlotRefs = {
	Index: number,
	Model: Model,
	Display: BasePart,
	Label: TextLabel,
	LightBar: BasePart,
	Light: SurfaceLight,
	Template: SlotLook,
	Attrs: { [string]: any }, -- что уже записано в атрибуты (пишем только изменившееся)
	Look: string, -- что уже показано на табличке и подсветке
}

type BaseRefs = {
	Base: Base,
	Slots: { SlotRefs },
	Prompt: ProximityPrompt,
	PromptAttachment: Attachment,
	Serial: number, -- n событий витрин этой базы (растёт всё время работы сервера)
	Owner: Runtime?, -- чей садок подключён
	TankAttrs: { [string]: any },
}

local GROWTH_TIME = TankConfig.Growth.Time
local HOME = EconomyConfig.HomeRatePct
local TEXTS = TankConfig.Texts
local STEAL_TEXTS = StealConfig.Texts
local FRESH_CATCH = StealConfig.Limits.FreshCatch
local PROMPT = TankConfig.Prompt
local FISH_FIELDS = { "FishUid", "FishId", "Rarity", "Mutation", "Kg", "Value", "Income", "GrowFrom" }
local WARN_EVERY = 30 -- секунд между предупреждениями цикла дохода

local TankService = {
	FishAdded = Signal.new(), -- (player, fish, reason)
	FishRemoved = Signal.new(), -- (player, fish, reason)
	-- Этап 4 (волна 0 — контракт; стреляют с Wave 1 A):
	Mounted = Signal.new(), -- (player, base): садок подключён к базе
	Unmounted = Signal.new(), -- (player, base): отключён
	SlotChanged = Signal.new(), -- (base, index): витрина записана
}

-- Что вернёт StealFish (Этап 4, §3.2): TankResult вора, чистая FishData добычи, номера рыбы.
export type StealResult = {
	Result: TankResult,
	Fish: FishData,
	ThiefUid: string,
	VictimUid: string,
}

-- Рыба витрины для кражи (SlotFish, Этап 4).
export type SlotView = {
	Uid: string,
	Id: string,
	ShortName: string,
	Rarity: string,
	Mutation: string?,
	Kg: number,
	Value: number,
	Income10: number,
	Steal: { Token: number, Phase: string }?,
	Escrow: boolean,
	FreshUntil: number?,
}

local runtimes: { [Player]: Runtime } = {}
local baseRefs: { [Base]: BaseRefs } = {}
-- Этап 4: рыбы «в пути» — вор (сам Player: ключ живёт и после его записи) → uid у вора → запись.
local escrows: { [Player]: { [string]: Entry } } = {}
local tankEvent: RemoteEvent? = nil
local stealEvent: RemoteEvent? = nil
local lastLoopWarn = -math.huge

--------------------------------------------------------------------------------
-- Помощники
--------------------------------------------------------------------------------

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Обработчик xpcall: текст ошибки с трассировкой.
local function trace(err: any): string
	return debug.traceback(tostring(err), 2)
end

-- Цена продажи годится: целое, конечное, ≥ 1.
local function goodPrice(price: number): boolean
	return finite(price) and price >= 1 and price % 1 == 0
end

local function send(player: Player, kind: string, data: { [string]: any })
	local remote = tankEvent
	if remote and player.Parent == Players then
		remote:FireClient(player, kind, data)
	end
end

local function deny(player: Player, reason: string)
	send(player, "Denied", { Reason = reason, Text = TEXTS.Denied[reason] or "" })
end

-- StealEvent "Returned" (Этап 4): краденая рыба вернулась хозяину.
local function returned(player: Player, fish: FishData, text: string)
	local remote = stealEvent
	if remote and player.Parent == Players then
		remote:FireClient(player, "Returned", { Fish = fish, Text = text })
	end
end

-- Рыбу сейчас нельзя продать, заменить или украсть (её крадут или она «в пути»).
local function locked(fish: FishRt): boolean
	return fish.Steal ~= nil or fish.Escrow ~= nil
end

-- Даёт ли рыба доход: не «в пути» и не на голове у вора.
local function earning(fish: FishRt): boolean
	local steal = fish.Steal
	return fish.Escrow == nil and not (steal ~= nil and steal.Phase == "carry")
end

local function knownMutation(mutation: any): string?
	return if type(mutation) == "string" and FishingRules.GetMutation(mutation) then mutation else nil
end

-- Возраст рыбы сейчас: у подключённого садка — по GrowFrom, иначе замерший Age.
local function ageOf(rt: Runtime, fish: FishRt, now: number): number
	if rt.Mounted then
		return TankRules.AgeAt(fish.GrowFrom, now)
	end
	return math.clamp(fish.Rec.Age, 0, GROWTH_TIME)
end

-- Рыба в игре по её записи данных (вид знаком: Price только для знакомых Id).
local function activeFish(rec: PlayerData.Fish): FishRt
	local def = FishingRules.GetFish(rec.Id) :: any
	local mutation = knownMutation(rec.Mutation)
	local value, income = FishingRules.Price(rec.Id, rec.Kg, mutation)
	return {
		Rec = rec,
		Uid = rec.Uid,
		Rarity = def.Rarity,
		Mutation = mutation,
		Value = value,
		Income10 = TankRules.Income10(income),
		GrowFrom = 0,
		Dormant = false,
		Steal = nil,
		Escrow = nil,
		FreshUntil = nil,
	}
end

-- Спящая рыба: не видна, без дохода, не продаётся, не заменяется, сохраняется как есть.
local function dormantFish(rec: PlayerData.Fish): FishRt
	return {
		Rec = rec,
		Uid = rec.Uid,
		Rarity = "",
		Mutation = nil,
		Value = 0,
		Income10 = 0,
		GrowFrom = 0,
		Dormant = true,
		Steal = nil,
		Escrow = nil,
		FreshUntil = nil,
	}
end

local function soldFish(fish: FishRt, price: number): SoldFish
	return { Uid = fish.Uid, Id = fish.Rec.Id, Rarity = fish.Rarity, Mutation = fish.Mutation, Price = price }
end

local function activeCount(rt: Runtime): number
	local n = 0
	for _ in rt.BySlot do
		n += 1
	end
	return n
end

-- Убрать строку из data.Tank (плотный массив).
local function removeEntry(data: PlayerData.Data, entry: PlayerData.Fish)
	local index = table.find(data.Tank, entry)
	if index then
		table.remove(data.Tank, index)
	end
end

--------------------------------------------------------------------------------
-- Витрины
--------------------------------------------------------------------------------

local function setAttr(slot: SlotRefs, name: string, value: any)
	if slot.Attrs[name] ~= value then
		slot.Attrs[name] = value
		slot.Model:SetAttribute(name, value)
	end
end

local function setTankAttr(refs: BaseRefs, name: string, value: any)
	if refs.TankAttrs[name] ~= value then
		refs.TankAttrs[name] = value
		refs.Base.Tank:SetAttribute(name, value)
	end
end

-- Event — ПОСЛЕДНИМ (после полей рыбы и State); n растёт у базы всегда.
local function event(refs: BaseRefs, slot: SlotRefs, kind: string, detail: string)
	refs.Serial += 1
	slot.Model:SetAttribute("Event", `{refs.Serial}|{kind}|{detail}`)
end

local function look(slot: SlotRefs, key: string, apply: () -> ())
	if slot.Look ~= key then
		slot.Look = key
		apply()
	end
end

local function lookTemplate(slot: SlotRefs)
	look(slot, "empty", function()
		local t = slot.Template
		slot.Label.Text = t.LabelText
		slot.Label.TextColor3 = t.LabelColor
		slot.LightBar.Color = t.BarColor
		slot.LightBar.Material = t.BarMaterial
		slot.Light.Enabled = t.LightEnabled
		slot.Display.Transparency = t.DisplayTransparency
	end)
end

local function clearFishFields(slot: SlotRefs)
	for _, name in FISH_FIELDS do
		setAttr(slot, name, nil)
	end
end

-- Этап 4: канал кражи витрины (отдельно от Event) — по рыбе в ней (nil — пусто): StealBy, StealEnd,
-- Escrow, FreshUntil, потом StealPhase ПОСЛЕДНИМ (и при снятии — тоже последним).
local function writeSteal(slot: SlotRefs, fish: FishRt?)
	local steal = fish and fish.Steal
	local shown = if steal and not steal.Quiet then steal else nil
	local fresh = fish and fish.FreshUntil
	setAttr(slot, "StealBy", shown and shown.By)
	setAttr(slot, "StealEnd", shown and shown.End)
	setAttr(slot, "Escrow", if fish and fish.Escrow then true else nil)
	setAttr(slot, "FreshUntil", if fresh and fresh > Workspace:GetServerTimeNow() then fresh else nil)
	setAttr(slot, "StealPhase", shown and shown.Phase)
end

-- Этап 4: витрина записана — StealService обновляет её кнопку «Украсть» (BE-22).
local function changed(refs: BaseRefs?, index: number)
	if refs then
		TankService.SlotChanged:Fire(refs.Base, index)
	end
end

local function showEmpty(refs: BaseRefs, slot: SlotRefs, kind: string?, detail: string?)
	clearFishFields(slot)
	setAttr(slot, "State", "empty")
	writeSteal(slot, nil)
	lookTemplate(slot)
	if kind then
		event(refs, slot, kind, detail or "")
	end
end

local function showLocked(refs: BaseRefs, slot: SlotRefs, kind: string?)
	clearFishFields(slot)
	setAttr(slot, "State", "locked")
	writeSteal(slot, nil)
	look(slot, "locked", function()
		local t = slot.Template
		slot.Label.Text = TEXTS.SlotLocked
		slot.Label.TextColor3 = t.LabelColor
		slot.LightBar.Material = Enum.Material.SmoothPlastic
		slot.LightBar.Color = UIConfig.Palette.Slate.Bottom
		slot.Light.Enabled = false
		slot.Display.Transparency = t.DisplayTransparency
	end)
	if kind then
		event(refs, slot, kind, "")
	end
end

local function rarityBarColor(rarity: string): Color3
	if rarity == "Mythic" then
		return UIConfig.Rainbow[6]
	end
	local style = UIConfig.Rarity[rarity]
	return if style then style.Bottom else UIConfig.Rarity.Common.Bottom
end

local function showFish(refs: BaseRefs, slot: SlotRefs, fish: FishRt, kind: string, detail: string)
	local rec = fish.Rec
	setAttr(slot, "FishUid", fish.Uid)
	setAttr(slot, "FishId", rec.Id)
	setAttr(slot, "Rarity", fish.Rarity)
	setAttr(slot, "Mutation", fish.Mutation)
	setAttr(slot, "Kg", rec.Kg)
	setAttr(slot, "Value", fish.Value)
	setAttr(slot, "Income", fish.Income10 / 10)
	setAttr(slot, "GrowFrom", fish.GrowFrom)
	setAttr(slot, "State", "fish")
	writeSteal(slot, fish)
	look(slot, `fish|{rec.Id}|{fish.Rarity}`, function()
		local def = FishingRules.GetFish(rec.Id)
		local rarity = FishingRules.GetRarity(fish.Rarity)
		slot.Label.Text = if def then def.Name else rec.Id
		slot.Label.TextColor3 = if rarity then rarity.Color else slot.Template.LabelColor
		slot.LightBar.Material = slot.Template.BarMaterial
		slot.LightBar.Color = rarityBarColor(fish.Rarity)
		slot.Light.Enabled = true
		slot.Display.Transparency = TankConfig.Display.GlassOccupied
	end)
	event(refs, slot, kind, detail)
end

-- Витрина index садка rt (подключённого к refs) — как сейчас в данных.
local function showSlot(refs: BaseRefs, rt: Runtime, index: number, kind: string, detail: string)
	local slot = refs.Slots[index]
	local fish = rt.BySlot[index]
	if index > PlayerData.SlotCap(rt.Data) then
		showLocked(refs, slot, kind)
	elseif fish then
		showFish(refs, slot, fish, kind, detail)
	else
		showEmpty(refs, slot, kind, detail)
	end
end

--------------------------------------------------------------------------------
-- Доход и атрибуты
--------------------------------------------------------------------------------

-- После любого изменения садка: сумма дохода, атрибуты игрока и садка, «Доход/с».
local function refresh(rt: Runtime)
	local sum = 0
	for _, fish in rt.BySlot do
		if earning(fish) then
			sum += fish.Income10 -- (Этап 4: «в пути» и на голове у вора — без дохода)
		end
	end
	rt.Income10Sum = sum
	local player = rt.Player
	local count = activeCount(rt)
	local slots = PlayerData.SlotCap(rt.Data)
	if player:GetAttribute("TankCount") ~= count then
		player:SetAttribute("TankCount", count)
	end
	if player:GetAttribute("TankSlots") ~= slots then
		player:SetAttribute("TankSlots", slots)
	end
	EconomyService:SetIncome(player, if rt.Mounted then sum else 0)
	local base = rt.Base
	local refs = base and baseRefs[base]
	if rt.Mounted and refs then
		setTankAttr(refs, "Count", count)
		setTankAttr(refs, "Slots", slots)
		setTankAttr(refs, "Income", sum / 10)
	end
end

--------------------------------------------------------------------------------
-- Подключение садка к базе
--------------------------------------------------------------------------------

local function mount(rt: Runtime, base: Base)
	if rt.Mounted or base.Owner ~= rt.Player then
		return
	end
	local refs = baseRefs[base]
	if not refs then
		return
	end
	rt.Base = base
	rt.Mounted = true
	refs.Owner = rt
	local now = Workspace:GetServerTimeNow()
	for _, fish in rt.BySlot do
		fish.GrowFrom = TankRules.AttrTime(now - math.clamp(fish.Rec.Age, 0, GROWTH_TIME))
	end
	for index in refs.Slots do
		showSlot(refs, rt, index, "mount", "")
	end
	refresh(rt)
	refs.Prompt.Enabled = true
	for index in refs.Slots do
		changed(refs, index)
	end
	TankService.Mounted:Fire(rt.Player, base)
end

local function unmount(rt: Runtime)
	if not rt.Mounted then
		return
	end
	local base = rt.Base :: Base
	local refs = baseRefs[base]
	local now = Workspace:GetServerTimeNow()
	for _, fish in rt.BySlot do
		fish.Rec.Age = TankRules.AgeAt(fish.GrowFrom, now) -- возраст замирает
	end
	-- Этап 4 (BE-5): канал кражи не переживает подключение — Steal снят со всех рыб ДО rt.Base = nil
	-- (пустые витрины ниже снимают и атрибуты; StealService в Unmounted чистит только своё).
	for _, fish in rt.Fish do
		fish.Steal = nil
	end
	rt.Mounted = false
	rt.Base = nil
	if refs then
		if refs.Owner == rt then
			refs.Owner = nil
		end
		for _, slot in refs.Slots do
			showEmpty(refs, slot, "mount", "")
		end
		setTankAttr(refs, "Count", nil)
		setTankAttr(refs, "Slots", nil)
		setTankAttr(refs, "Income", nil)
		refs.Prompt.Enabled = false
	end
	refresh(rt)
	if refs then
		for index in refs.Slots do
			changed(refs, index)
		end
	end
	TankService.Unmounted:Fire(rt.Player, base)
end

local function newRuntime(player: Player, data: PlayerData.Data): Runtime
	local rt: Runtime = {
		Player = player,
		Data = data,
		Fish = {},
		BySlot = {},
		Base = nil,
		Mounted = false,
		Income10Sum = 0,
		Carry10 = 0,
		Ticks = 0,
	}
	local active, dormant = PlayerData.Layout(data)
	for slot, rec in active do
		local fish = activeFish(rec)
		rt.Fish[fish.Uid] = fish
		rt.BySlot[slot] = fish
	end
	for _, rec in dormant do
		rt.Fish[rec.Uid] = dormantFish(rec)
	end
	return rt
end

-- Данные и база игрока на месте (что второе) — подключить.
local function tryMount(rt: Runtime)
	local base = BaseService:GetBase(rt.Player)
	if base and base.Owner == rt.Player then
		mount(rt, base)
	end
end

local function onLoaded(player: Player, data: PlayerData.Data)
	if runtimes[player] or player.Parent ~= Players then
		return
	end
	local rt = newRuntime(player, data)
	runtimes[player] = rt
	refresh(rt)
	tryMount(rt)
end

local returnEscrows: (player: Player) -> ()

local function onPlayerRemoving(player: Player)
	TankRequests.Forget(player)
	-- Этап 4 (F8a / F8b / F8c): рыбы «в пути» этого вора — назад жертвам и прочь из его живых
	-- данных; как жертва — ничего (её последнее сохранение уже без рыбы).
	returnEscrows(player)
	local rt = runtimes[player]
	if not rt then
		return
	end
	unmount(rt)
	if runtimes[player] == rt then
		runtimes[player] = nil
	end
end

--------------------------------------------------------------------------------
-- Рыбы: добавить, убрать
--------------------------------------------------------------------------------

-- Записи и данные, если игрок может их менять (ворота CanWrite), иначе nil.
local function writable(player: Player): (Runtime?, PlayerData.Data?)
	if not DataService:CanWrite(player) then
		return nil, nil
	end
	local rt = runtimes[player]
	local data = DataService:Get(player)
	if not rt or not data or rt.Data ~= data then
		return nil, nil
	end
	return rt, data
end

-- Убрать активную рыбу из данных и записей (без денег, витрин и сигналов).
local function detach(rt: Runtime, fish: FishRt)
	removeEntry(rt.Data, fish.Rec)
	rt.Fish[fish.Uid] = nil
	if rt.BySlot[fish.Rec.Slot] == fish then
		rt.BySlot[fish.Rec.Slot] = nil
	end
end

-- Кандидаты замены полного садка (TankRules.ChooseReplacement): активные рыбы; Locked — те, что
-- крадут или «в пути» (Этап 4).
local function candidatesOf(rt: Runtime, now: number): { TankRules.Candidate }
	local list: { TankRules.Candidate } = {}
	for _, other in rt.BySlot do
		table.insert(list, {
			Uid = other.Uid,
			Income10 = other.Income10,
			Value = other.Value,
			Age = ageOf(rt, other, now),
			Locked = locked(other),
			Dormant = false,
		})
	end
	return list
end

local function freeSlot(rt: Runtime, cap: number): number?
	for index = 1, cap do
		if rt.BySlot[index] == nil then
			return index
		end
	end
	return nil
end

function TankService:AddFish(player: Player, fish: FishData, reason: string): TankResult?
	local rt, data = writable(player)
	if not rt or not data or type(fish) ~= "table" then
		return nil
	end
	-- 1. Посчитать и проверить (ничего не меняя).
	local id = fish.Id
	local def = if type(id) == "string" then FishingRules.GetFish(id) else nil
	if not def or not finite(fish.Kg) or fish.Kg <= 0 then
		return nil
	end
	local mutation = knownMutation(fish.Mutation)
	-- Этап 4: откуда рыба («<UserId жертвы>:<uid>» у краденой) — только не у улова и только
	-- строкой не длиннее Limits.OriginMax (PlayerData сохраняет то же самое).
	local origin = (fish :: any).Origin
	if reason == "catch" or type(origin) ~= "string" or #origin > DataConfig.Limits.OriginMax then
		origin = nil
	end
	local value, income = FishingRules.Price(id, fish.Kg, mutation)
	local income10 = TankRules.Income10(income)
	local now = Workspace:GetServerTimeNow()
	local cap = PlayerData.SlotCap(data)
	local slot: number? = freeSlot(rt, cap)
	local result: "stored" | "replaced" | "sold" = "stored"
	local weak: FishRt? = nil
	local price: number? = nil
	if not slot then
		local weakUid = TankRules.ChooseReplacement(candidatesOf(rt, now), income10)
		local chosen = weakUid and rt.Fish[weakUid]
		if chosen then
			weak = chosen
			result = "replaced"
			slot = chosen.Rec.Slot
			price = TankRules.SellPrice(chosen.Value, ageOf(rt, chosen, now), HOME)
		else
			result = "sold"
			price = TankRules.SellPrice(value, 0, HOME)
		end
	end
	if price and not goodPrice(price) then
		warn(
			`[TankService] цена продажи не число ({price}) — улов игрока {player.UserId} не принят`
		)
		return nil
	end

	-- 2. Менять: данные → записи → деньги → статистика → витрина → доход → атрибуты → сигналы.
	local entry: PlayerData.Fish? = nil
	local added: FishRt? = nil
	if weak then
		detach(rt, weak)
	end
	if result ~= "sold" then
		local index: number = slot :: number
		local newEntry: PlayerData.Fish = {
			Uid = PlayerData.NewUid(data),
			Id = id,
			Kg = fish.Kg,
			Mutation = mutation,
			Age = 0,
			Slot = index,
			CaughtAt = os.time(),
			Origin = origin,
		}
		table.insert(data.Tank, newEntry)
		local fishRt = activeFish(newEntry)
		fishRt.GrowFrom = TankRules.AttrTime(now)
		if reason == "catch" then
			fishRt.FreshUntil = TankRules.AttrTime(now + FRESH_CATCH) -- (Этап 4: свежий улов не крадётся)
		end
		rt.Fish[fishRt.Uid] = fishRt
		rt.BySlot[index] = fishRt
		entry, added = newEntry, fishRt
	end
	if price then
		EconomyService:AddMoney(player, price, "autosell")
		data.Stats.Sold += 1
	end
	local base = rt.Base
	local refs = base and baseRefs[base]
	if rt.Mounted and refs and added then
		local slotRefs = refs.Slots[added.Rec.Slot]
		if weak then
			showFish(refs, slotRefs, added, "swap", string.format("%d", price :: number))
		else
			showFish(refs, slotRefs, added, "in", id)
		end
	end
	refresh(rt)
	if rt.Mounted and refs and added then
		changed(refs, added.Rec.Slot)
	end

	local tank: TankResult = {
		Result = result,
		Slot = if added then added.Rec.Slot else nil,
		Uid = if added then added.Uid else nil,
		Count = activeCount(rt),
		Slots = cap,
		Replaced = if weak then soldFish(weak, price :: number) else nil,
		Price = price,
		First = if reason == "catch" and data.Stats.Caught == 1 then true else nil,
	}
	if weak then
		TankService.FishRemoved:Fire(player, table.clone(weak.Rec), "autosell")
	end
	if entry then
		TankService.FishAdded:Fire(player, table.clone(entry), reason)
	end
	if reason ~= "catch" then
		local stored = table.clone(tank) :: any
		stored.Fish = table.clone(fish)
		send(player, "Stored", stored)
	end
	return tank
end

function TankService:RemoveFish(owner: Player, uid: string, reason: string): PlayerData.Fish?
	local rt = writable(owner)
	local fish = rt and type(uid) == "string" and rt.Fish[uid]
	if not rt or not fish or fish.Dormant then
		return nil
	end
	detach(rt, fish)
	local base = rt.Base
	local refs = base and baseRefs[base]
	if rt.Mounted and refs then
		showEmpty(refs, refs.Slots[fish.Rec.Slot], if reason == "stolen" then "stolen" else "mount", "")
	end
	refresh(rt)
	if rt.Mounted then
		changed(refs, fish.Rec.Slot)
	end
	local copy = table.clone(fish.Rec)
	TankService.FishRemoved:Fire(owner, copy, reason)
	return copy
end

function TankService:SetSlots(player: Player, slots: number): boolean
	local rt, data = writable(player)
	if not rt or not data or not finite(slots) or slots % 1 ~= 0 or slots < data.TankSlots then
		return false
	end
	local before = PlayerData.SlotCap(data)
	data.TankSlots = slots
	local cap = PlayerData.SlotCap(data)
	-- Спящие знакомые рыбы — в новые свободные витрины (по порядку Tank).
	for _, rec in data.Tank do
		local fish = rt.Fish[rec.Uid]
		if fish and fish.Dormant and FishingRules.GetFish(rec.Id) then
			for index = 1, cap do
				if rt.BySlot[index] == nil then
					rec.Slot = index
					local awake = activeFish(rec)
					if rt.Mounted then
						awake.GrowFrom =
							TankRules.AttrTime(Workspace:GetServerTimeNow() - math.clamp(rec.Age, 0, GROWTH_TIME))
					end
					rt.Fish[rec.Uid] = awake
					rt.BySlot[index] = awake
					break
				end
			end
		end
	end
	local base = rt.Base
	local refs = base and baseRefs[base]
	if rt.Mounted and refs then
		for index = 1, cap do
			if index > before or rt.BySlot[index] ~= nil then
				showSlot(refs, rt, index, "mount", "")
			end
		end
	end
	refresh(rt)
	if rt.Mounted and refs then
		for index = 1, cap do
			changed(refs, index)
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Этап 4: кража (docs/stage4_design.md §3.2–§3.4, §4.5)
--------------------------------------------------------------------------------

-- Рыба, которую можно держать для кражи: активная, в своей витрине, не спит и не «в пути».
local function stealable(rt: Runtime, uid: any): FishRt?
	local fish = if type(uid) == "string" then rt.Fish[uid] else nil
	if not fish or fish.Dormant or fish.Escrow or rt.BySlot[fish.Rec.Slot] ~= fish then
		return nil
	end
	return fish
end

-- Подключённая база записи (nil — садок не подключён).
local function mountedRefs(rt: Runtime): BaseRefs?
	local base = rt.Base
	return if rt.Mounted and base then baseRefs[base] else nil
end

-- Держатель рыбы: token берёт её (phase "hold" | "carry"), nil — отпустить (только тот же token).
local function holdFish(owner: Player, uid: any, token: number, phase: string?, info: any?, quiet: boolean): boolean
	local rt = runtimes[owner]
	local fish = rt and stealable(rt, uid)
	if not rt or not fish or type(token) ~= "number" then
		return false
	end
	local current = fish.Steal
	if phase == nil then
		if not current or current.Token ~= token then
			return false
		end
		fish.Steal = nil
	else
		if phase ~= "hold" and phase ~= "carry" then
			return false
		end
		if current and current.Token ~= token then
			return false -- (её держит другая кража)
		end
		local given = if type(info) == "table" then info else {}
		fish.Steal = {
			Token = token,
			Phase = phase,
			By = if given.By ~= nil then given.By elseif current then current.By else nil,
			End = if given.End ~= nil then given.End elseif current then current.End else nil,
			Quiet = quiet,
		}
	end
	local refs = mountedRefs(rt)
	if refs then
		writeSteal(refs.Slots[fish.Rec.Slot], fish)
	end
	refresh(rt)
	changed(refs, fish.Rec.Slot)
	return true
end

function TankService:SetSteal(owner: Player, uid: string, token: number, phase: string?, info: any?): boolean
	if token == -1 then
		return false -- (−1 — только SetLocked)
	end
	return holdFish(owner, uid, token, phase, info, false)
end

-- Этап 3: «рыбу крадут» без кражи — тонкая обёртка держателя (токен −1, без атрибутов).
function TankService:SetLocked(owner: Player, uid: string, isLocked: boolean): boolean
	return holdFish(owner, uid, -1, if isLocked == true then "hold" else nil, nil, true)
end

-- Строка data.Tank с этим Uid (защита от вставки uid, который уже есть: §3.2).
local function hasUid(data: PlayerData.Data, uid: string): boolean
	for _, row in data.Tank do
		if row.Uid == uid then
			return true
		end
	end
	return false
end

-- Витрина для вернувшейся рыбы: своя, если свободна, иначе младшая свободная; nil — заняты все
-- (жертва успела поймать рыбу в витрину, которую освободила кража).
local function homeSlot(data: PlayerData.Data, wanted: number): number?
	local cap = PlayerData.SlotCap(data)
	local used: { [number]: boolean } = {}
	for _, row in data.Tank do
		used[row.Slot] = true
	end
	if wanted >= 1 and wanted <= cap and not used[wanted] then
		return wanted
	end
	for index = 1, cap do
		if not used[index] then
			return index
		end
	end
	return nil
end

local function minusOne(stats: any, key: string)
	stats[key] = math.max(0, (tonumber(stats[key]) or 0) - 1)
end

-- Снять «в пути»: запись — ПЕРВОЙ (второй вызов ничего не найдёт), рыба начинает приносить доход,
-- SaveSoon(вор). Только из Committed / Released жертвы (или сразу, шаг 4 StealFish) — не по таймеру.
local function clearEscrow(thief: Player, uid: string)
	local map = escrows[thief]
	local entry = map and map[uid]
	if not map or not entry then
		return
	end
	map[uid] = nil
	if next(map) == nil then
		escrows[thief] = nil
	end
	local rt = runtimes[thief]
	local fish = rt and rt.Fish[uid]
	if rt and fish and fish.Escrow == entry then
		fish.Escrow = nil
		local refs = mountedRefs(rt)
		if refs and rt.BySlot[fish.Rec.Slot] == fish then
			writeSteal(refs.Slots[fish.Rec.Slot], fish)
		end
		refresh(rt)
		changed(refs, fish.Rec.Slot)
	end
	DataService:SaveSoon(thief)
end

-- Убрать краденую рыбу из садка вора (данные — живые, даже если он уже уходит: её строку не
-- сохраняло ни одно сохранение — хук пропускал), Stats.Stolen − 1. Тихо: Event "<n>|void|".
local function stripFromThief(entry: Entry): boolean
	local thief = entry.Thief
	local rt = runtimes[thief]
	local data = if rt then rt.Data else nil
	if not rt or not data then
		return false
	end
	local fish = rt.Fish[entry.ThiefUid]
	if not fish or fish.Escrow ~= entry then
		return false
	end
	local slot = fish.Rec.Slot
	local active = rt.BySlot[slot] == fish
	detach(rt, fish)
	fish.Escrow = nil
	minusOne(data.Stats, "Stolen")
	local refs = mountedRefs(rt)
	if refs and active then
		showEmpty(refs, refs.Slots[slot], "void", "")
	end
	refresh(rt)
	if active then
		changed(refs, slot)
	end
	TankService.FishRemoved:Fire(thief, table.clone(fish.Rec), "void")
	return true
end

-- Аннулировать (F7): запись жертвы так и не легла — её ключ всё ещё хранит рыбу; у вора её нет.
local function voidEscrow(thief: Player, uid: string)
	local map = escrows[thief]
	local entry = map and map[uid]
	if not map or not entry then
		return
	end
	map[uid] = nil
	if next(map) == nil then
		escrows[thief] = nil
	end
	if stripFromThief(entry) then
		returned(thief, entry.Fish, STEAL_TEXTS.Result.Void)
	end
end

-- Вернуть рыбу играющей жертве (F8a / F9): та же строка (прежний uid) в свою витрину или младшую
-- свободную. Свободных нет — правило полного садка, как у AddFish (A1-01): слабейшая не Locked рыба
-- слабее вернувшейся — продана, вернувшаяся на её место ("replaced"); иначе продана сама
-- вернувшаяся ("sold") — жертва получает монеты в любом случае, ни одна рыба не «спит».
local function backToVictim(vrt: Runtime, vdata: PlayerData.Data, entry: Entry): boolean
	local victim = entry.Victim
	local now = Workspace:GetServerTimeNow()
	local row = table.clone(entry.Row)
	row.Uid = entry.VictimUid
	local cap = PlayerData.SlotCap(vdata)
	local known = FishingRules.GetFish(row.Id) ~= nil
	local slot = homeSlot(vdata, entry.Row.Slot)
	if slot and vrt.BySlot[slot] ~= nil then
		slot = nil -- (строки и витрины разошлись: как полный садок)
	end
	-- ПРОВЕРКА: план полного садка (ничего не меняя).
	local weak: FishRt? = nil
	local price: number? = nil
	local sell = false
	if known and not slot then
		local value, income = FishingRules.Price(row.Id, row.Kg, knownMutation(row.Mutation))
		local weakUid = TankRules.ChooseReplacement(candidatesOf(vrt, now), TankRules.Income10(income))
		weak = if weakUid then vrt.Fish[weakUid] else nil
		if weak then
			slot = weak.Rec.Slot
			price = TankRules.SellPrice(weak.Value, ageOf(vrt, weak, now), HOME)
		else
			sell = true
			price = TankRules.SellPrice(value, math.clamp(row.Age, 0, GROWTH_TIME), HOME)
		end
		if not goodPrice(price :: number) then
			warn(
				`[TankService] цена продажи не число ({price}) — вернувшаяся рыба {row.Uid} спит`
			)
			weak, price, sell, slot = nil, nil, false, nil
		end
	end
	-- ПОТОМ: убрать → строка → деньги → статистика → витрина → доход → сигналы.
	if weak then
		detach(vrt, weak)
	end
	local fishRt: FishRt? = nil
	if not sell then
		row.Slot = slot or entry.Row.Slot
		table.insert(vdata.Tank, row)
		local fresh: FishRt
		if slot and known and slot <= cap and vrt.BySlot[slot] == nil then
			fresh = activeFish(row)
			fresh.GrowFrom = TankRules.AttrTime(now - math.clamp(row.Age, 0, GROWTH_TIME))
			vrt.BySlot[slot] = fresh
		else
			fresh = dormantFish(row) -- (незнакомый вид или цена не число: «спит», данные целы)
		end
		vrt.Fish[row.Uid] = fresh
		fishRt = fresh
	end
	if price then
		EconomyService:AddMoney(victim, price, "autosell")
		vdata.Stats.Sold += 1
	end
	minusOne(vdata.Stats, "Lost")
	local refs = mountedRefs(vrt)
	local shown = fishRt ~= nil and not fishRt.Dormant
	if refs and shown then
		local f = fishRt :: FishRt
		if weak then
			showFish(refs, refs.Slots[f.Rec.Slot], f, "swap", string.format("%d", price :: number))
		else
			showFish(refs, refs.Slots[f.Rec.Slot], f, "in", row.Id)
		end
	end
	refresh(vrt)
	if shown then
		changed(refs, (fishRt :: FishRt).Rec.Slot)
	end
	if weak then
		TankService.FishRemoved:Fire(victim, table.clone(weak.Rec), "autosell")
	end
	if fishRt then
		TankService.FishAdded:Fire(victim, table.clone(row), "returned")
	end
	DataService:SaveSoon(victim)
	local remote = stealEvent
	if remote and victim.Parent == Players then
		remote:FireClient(victim, "Returned", {
			Fish = entry.Fish,
			Text = if sell
				then TextUtil.fill(STEAL_TEXTS.Result.LeftSold, { price = TankRules.FormatMoney(price :: number) })
				else STEAL_TEXTS.Result.Saved.left,
			Result = if sell then "sold" elseif weak then "replaced" else "stored",
			Price = price,
		})
	end
	return true
end

-- Вернуть краденую рыбу «в пути» жертве (F8a / F8b / F9; F8c — снимок жертвы уже снят: рыба
-- потеряна, никогда не две) и убрать у вора. Запись — ПЕРВОЙ, потом — прочь у вора, и только потом
-- — жертве: упавшая вставка потеряет одну рыбу, но никогда не оставит две. true — рыба снова у
-- жертвы (или монеты за неё: полный садок).
local function returnEscrow(thief: Player, uid: string): boolean
	local map = escrows[thief]
	local entry = map and map[uid]
	if not map or not entry then
		return false
	end
	map[uid] = nil
	if next(map) == nil then
		escrows[thief] = nil
	end
	stripFromThief(entry)
	local victim = entry.Victim
	local vrt, vdata = writable(victim)
	if vrt and vdata and vrt.Player == victim then
		-- F8a / F9: жертва играет.
		if hasUid(vdata, entry.VictimUid) then
			return false
		end
		return backToVictim(vrt, vdata, entry)
	end
	-- F8b: жертва уже уходит, а снимок её последнего сохранения не снят — правка её данных (только
	-- Tank: денег уходящей жертве не начислить). Свободной витрины нет — строка «спит» со своим Slot
	-- (PlayerData.Layout: проснётся на загрузке, где витрина свободна, или по SetSlots Этапа 5).
	-- Снимок уже снят (F8c) — правка ждёт повтора, если эта попытка не запишется (DataService).
	return DataService:AmendLeaving(victim, function(data: PlayerData.Data)
		if hasUid(data, entry.VictimUid) then
			return
		end
		local row = table.clone(entry.Row)
		row.Uid = entry.VictimUid
		row.Slot = homeSlot(data, entry.Row.Slot) or entry.Row.Slot
		table.insert(data.Tank, row)
		minusOne(data.Stats, "Lost")
	end)
end

-- Перенести рыбу жертвы вору (§3.2): ПРОВЕРКА — план, ничего не меняя; потом — без ожиданий.
function TankService:StealFish(victim: Player, thief: Player, uid: string, token: number): (StealResult?, string?)
	-- ПРОВЕРКА
	if victim == thief or type(uid) ~= "string" then
		return nil, "busy"
	end
	local vrt, vdata = writable(victim)
	local trt, tdata = writable(thief)
	if not vrt or not vdata or not trt or not tdata or not vrt.Mounted or not trt.Mounted then
		return nil, "busy"
	end
	local fish = stealable(vrt, uid)
	local steal = fish and fish.Steal
	if not fish or not steal or steal.Token ~= token or steal.Phase ~= "carry" then
		return nil, "busy"
	end
	local now = Workspace:GetServerTimeNow()
	local origin: string? = `{victim.UserId}:{uid}`
	if #(origin :: string) > DataConfig.Limits.OriginMax then
		origin = nil
	end
	for _, row in tdata.Tank do
		if origin and row.Origin == origin then
			return nil, "busy" -- (такая уже есть у вора: дюп — никогда)
		end
	end
	local cap = PlayerData.SlotCap(tdata)
	local slot = freeSlot(trt, cap)
	local weak: FishRt? = nil
	local price: number? = nil
	if not slot then
		local weakUid = TankRules.ChooseReplacement(candidatesOf(trt, now), fish.Income10)
		weak = if weakUid then trt.Fish[weakUid] else nil
		if not weak then
			return nil, "full"
		end
		slot = weak.Rec.Slot
		price = TankRules.SellPrice(weak.Value, ageOf(trt, weak, now), HOME)
		if not goodPrice(price :: number) then
			warn(
				`[TankService] цена продажи не число ({price}) — кража у {victim.UserId} отменена`
			)
			return nil, "busy"
		end
	end
	local index = slot :: number
	-- Новый Uid вора — подсмотреть (на копии), взять — в шаге 2.
	local newUid = PlayerData.NewUid({ NextUid = tdata.NextUid, Tank = tdata.Tank })
	if trt.Fish[newUid] or hasUid(tdata, newUid) then
		return nil, "busy"
	end
	local value, income = FishingRules.Price(fish.Rec.Id, fish.Rec.Kg, fish.Mutation)
	if not finite(value) or not finite(income) then
		return nil, "busy"
	end
	local age = ageOf(vrt, fish, now)
	local row: PlayerData.Fish = {
		Uid = newUid,
		Id = fish.Rec.Id,
		Kg = fish.Rec.Kg,
		Mutation = fish.Rec.Mutation,
		Age = age,
		Slot = index,
		CaughtAt = os.time(),
		Origin = origin,
	}
	local clean: FishData = {
		Id = fish.Rec.Id,
		Rarity = fish.Rarity,
		Kg = fish.Rec.Kg,
		Mutation = fish.Mutation,
		Value = value,
		Income = income,
	}
	local victimRow = table.clone(fish.Rec)
	victimRow.Age = age
	local victimSlot = fish.Rec.Slot

	-- ПОТОМ: только таблицы и атрибуты, ни сигнала, ни remote'а до шага 5.
	-- 0. «В пути» — раньше, чем рыба появится у вора: все его сохранения её пропустят.
	local entry: Entry = {
		Victim = victim,
		VictimUserId = victim.UserId,
		VictimUid = uid,
		Thief = thief,
		ThiefUid = newUid,
		Seq = math.huge,
		Row = victimRow,
		Fish = clean,
	}
	local map = escrows[thief]
	if not map then
		map = {}
		escrows[thief] = map
	end
	map[newUid] = entry
	-- 1. Жертва.
	fish.Steal = nil
	detach(vrt, fish)
	vdata.Stats.Lost += 1
	local vrefs = mountedRefs(vrt)
	if vrefs then
		showEmpty(vrefs, vrefs.Slots[victimSlot], "stolen", tostring(thief.UserId))
	end
	refresh(vrt)
	-- 2. Вор.
	PlayerData.NewUid(tdata) -- (тот самый newUid — подсмотрен выше на копии тех же данных: NextUid + 1)
	if weak then
		detach(trt, weak)
	end
	table.insert(tdata.Tank, row)
	local loot = activeFish(row)
	loot.GrowFrom = TankRules.AttrTime(now - age)
	loot.Escrow = entry
	trt.Fish[newUid] = loot
	trt.BySlot[index] = loot
	tdata.Stats.Stolen += 1
	local trefs = mountedRefs(trt)
	if trefs then
		if weak then
			showFish(trefs, trefs.Slots[index], loot, "swap", string.format("%d", price :: number))
		else
			showFish(trefs, trefs.Slots[index], loot, "in", row.Id)
		end
	end
	refresh(trt)
	-- 3. Сохранение жертвы (с задержкой 0 оно может записаться прямо здесь: его Committed с
	-- Seq = ∞ не совпал — поэтому шаг 4).
	entry.Seq = DataService:SaveSoon(victim)
	-- 4. Уже записано (или DataStore нет) — снять «в пути» сразу.
	if DataService:Mode() ~= "DataStore" or DataService:CommittedSeq(victim) >= entry.Seq then
		clearEscrow(thief, newUid)
	end
	-- 5. Деньги, сигналы, remote — «в пути» уже действует.
	if weak and price then
		EconomyService:AddMoney(thief, price, "autosell")
		tdata.Stats.Sold += 1
	end
	changed(vrefs, victimSlot)
	changed(trefs, index)
	TankService.FishRemoved:Fire(victim, table.clone(victimRow), "stolen")
	if weak then
		TankService.FishRemoved:Fire(thief, table.clone(weak.Rec), "autosell")
	end
	TankService.FishAdded:Fire(thief, table.clone(row), "stolen")
	local tank: TankResult = {
		Result = if weak then "replaced" else "stored",
		Slot = index,
		Uid = newUid,
		Count = activeCount(trt),
		Slots = cap,
		Replaced = if weak then soldFish(weak, price :: number) else nil,
		Price = price,
	}
	local stored = table.clone(tank) :: any
	stored.Fish = table.clone(clean)
	send(thief, "Stored", stored)
	return { Result = tank, Fish = clean, ThiefUid = newUid, VictimUid = uid }, nil
end

-- Ляжет ли рыба с доходом income10 в садок игрока: "stored" (свободная витрина) | "replaced"
-- (сильнее его слабейшей не Locked — не краденой и не «в пути») | nil. Только чтение.
function TankService:PreviewAdd(player: Player, income10: number): ("stored" | "replaced")?
	local rt = runtimes[player]
	if not rt then
		return nil
	end
	local free = freeSlot(rt, PlayerData.SlotCap(rt.Data)) ~= nil
	return StealRules.CanPlace(candidatesOf(rt, Workspace:GetServerTimeNow()), free, income10)
end

-- Рыба в витрине index базы base: (хозяин, вид) или nil (свободная база, пусто, «спит»).
function TankService:SlotFish(base: Base, index: number): (Player?, SlotView?)
	local refs = baseRefs[base]
	local rt = refs and refs.Owner
	if not rt or not rt.Mounted then
		return nil, nil
	end
	local fish = rt.BySlot[index]
	if not fish then
		return rt.Player, nil
	end
	local def = FishingRules.GetFish(fish.Rec.Id)
	local steal = fish.Steal
	return rt.Player,
		{
			Uid = fish.Uid,
			Id = fish.Rec.Id,
			ShortName = if def then def.ShortName else fish.Rec.Id,
			Rarity = fish.Rarity,
			Mutation = fish.Mutation,
			Kg = fish.Rec.Kg,
			Value = fish.Value,
			Income10 = fish.Income10,
			Steal = if steal then { Token = steal.Token, Phase = steal.Phase } else nil,
			Escrow = fish.Escrow ~= nil,
			FreshUntil = fish.FreshUntil,
		}
end

function TankService:ActiveCount(player: Player): number
	local rt = runtimes[player]
	return if rt then activeCount(rt) else 0
end

function TankService:IsMounted(player: Player): boolean
	local rt = runtimes[player]
	return rt ~= nil and rt.Mounted
end

-- Доход садка (десятые $/с; без «в пути» и несомой рыбы), 0 — не подключён (фильтр "weak").
function TankService:Income10(player: Player): number
	local rt = runtimes[player]
	return if rt and rt.Mounted then rt.Income10Sum else 0
end

function TankService:EscrowCount(player: Player): number
	local n = 0
	for _ in escrows[player] or {} do
		n += 1
	end
	return n
end

-- Хуки записи жертвы (§3.2): Committed(seq) — снять её записи с Seq ≤ seq; Released(committed) —
-- КАЖДУЮ её запись: снять или аннулировать (ни одна не переживёт её запись).
local function onCommitted(player: Player, seq: number)
	for thief, map in table.clone(escrows) do
		for uid, entry in table.clone(map) do
			if entry.Victim == player and seq >= entry.Seq then
				clearEscrow(thief, uid)
			end
		end
	end
end

local function onReleased(player: Player, committed: number)
	for thief, map in table.clone(escrows) do
		for uid, entry in table.clone(map) do
			if entry.Victim == player then
				if committed >= entry.Seq then
					clearEscrow(thief, uid)
				else
					voidEscrow(thief, uid)
				end
			end
		end
	end
end

-- Закрытие сервера (F9): синхронно, раньше, чем хоть одна запись станет Leaving, — вернуть все
-- рыбы «в пути» жертвам (их последние сохранения возьмут рыбу с собой).
local function onClose()
	for thief in table.clone(escrows) do
		returnEscrows(thief)
	end
end

returnEscrows = function(player: Player)
	local map = escrows[player]
	if map then
		for uid in table.clone(map) do
			returnEscrow(player, uid)
		end
	end
end

--------------------------------------------------------------------------------
-- Запросы клиента
--------------------------------------------------------------------------------

local function onTankSell(player: Player, rawUid: unknown)
	if TankRules.UidNumber(rawUid) == nil then
		return -- не номер рыбы: молча
	end
	if not TankRequests.Take(player) then
		return -- лимит: молча (и без ответа)
	end
	local uid = rawUid :: string
	local rt, data = writable(player)
	if not rt or not data then
		deny(player, "loading")
		return
	end
	if not rt.Mounted then
		deny(player, "nobase")
		return
	end
	local fish = rt.Fish[uid]
	if not fish or fish.Dormant or rt.BySlot[fish.Rec.Slot] ~= fish then
		deny(player, "missing")
		return
	end
	if fish.Steal then
		deny(player, "locked") -- (Этап 4: её сейчас крадут)
		return
	end
	if fish.Escrow then
		deny(player, "escrow") -- (Этап 4: краденая, ещё «в пути»)
		return
	end
	local ratePct, place = MarketService:RatePct(player)
	local price = TankRules.SellPrice(fish.Value, ageOf(rt, fish, Workspace:GetServerTimeNow()), ratePct)
	if not goodPrice(price) then
		warn(
			`[TankService] цена продажи не число ({price}) — продажа {uid} игрока {player.UserId} отменена`
		)
		return
	end
	-- Менять (без ожиданий): данные → деньги → статистика → витрина → доход → remote → сигнал.
	detach(rt, fish)
	EconomyService:AddMoney(player, price, "sell")
	data.Stats.Sold += 1
	local refs = baseRefs[rt.Base :: Base]
	if refs then
		showEmpty(refs, refs.Slots[fish.Rec.Slot], "sold", string.format("%d", price))
	end
	refresh(rt)
	changed(refs, fish.Rec.Slot)
	send(player, "Sold", {
		Items = { soldFish(fish, price) },
		Amount = price,
		RatePct = ratePct,
		Place = place,
	})
	TankService.FishRemoved:Fire(player, table.clone(fish.Rec), "sell")
end

local function onTankPrompt(refs: BaseRefs, player: Player)
	if not TankRequests.Take(player) then
		return
	end
	if refs.Base.Owner ~= player then
		return -- чужая база: кнопка только хозяину
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return
	end
	if (refs.PromptAttachment.WorldPosition - root.Position).Magnitude > PROMPT.MaxDistance + PROMPT.Slack then
		return
	end
	local rate = player:GetAttribute("SellRatePct")
	send(player, "Open", {
		Place = "Tank",
		RatePct = if type(rate) == "number" then rate else HOME,
		Name = PROMPT.Object,
	})
end

--------------------------------------------------------------------------------
-- Цикл дохода
--------------------------------------------------------------------------------

local function tickPlayer(player: Player, rt: Runtime, ticks: number, now: number)
	if not rt.Mounted or not DataService:CanWrite(player) then
		return
	end
	rt.Ticks += ticks
	rt.Carry10 += ticks * rt.Income10Sum
	local whole = rt.Carry10 // 10
	rt.Carry10 -= whole * 10
	if whole > 0 then
		EconomyService:AddMoney(player, whole, "income")
	end
	for _, fish in rt.BySlot do
		fish.Rec.Age = TankRules.AgeAt(fish.GrowFrom, now)
	end
	MarketService:Sample(player)
end

local function incomeLoop()
	local tick = EconomyConfig.IncomeTick
	local acc = 0
	while true do
		local dt = task.wait(tick)
		acc += dt
		local ticks = math.floor(acc / tick)
		acc -= ticks * tick
		ticks = math.min(ticks, EconomyConfig.MaxCatchUp)
		if ticks > 0 then
			local now = Workspace:GetServerTimeNow()
			for player, rt in runtimes do
				local ok, err = xpcall(function(): any
					tickPlayer(player, rt, ticks, now)
					return nil
				end, trace)
				if not ok and os.clock() - lastLoopWarn >= WARN_EVERY then
					lastLoopWarn = os.clock()
					warn(`[TankService] ❌ тик дохода игрока {player.UserId}: {err}`)
				end
			end
		end
	end
end

-- Хук сохранения (внутри transform DataService, не ждёт): свежий возраст рыб подключённого
-- садка. Этап 4: skipUid — рыбы «в пути» этого игрока не сохранять (каждое его сохранение, есть
-- у него запись этого сервиса или уже нет: ключ карты — сам Player).
local function onSerialize(player: Player, data: PlayerData.Data): ((uid: string) -> boolean)?
	local rt = runtimes[player]
	if rt and rt.Data == data and rt.Mounted then
		local now = Workspace:GetServerTimeNow()
		for _, fish in rt.BySlot do
			fish.Rec.Age = TankRules.AgeAt(fish.GrowFrom, now)
		end
	end
	return function(uid: string): boolean
		local map = escrows[player]
		return map ~= nil and map[uid] ~= nil
	end
end

--------------------------------------------------------------------------------
-- Тесты
--------------------------------------------------------------------------------

function TankService._debugSizes(): { [string]: number }
	local records, mounted = 0, 0
	for _ in runtimes do
		records += 1
	end
	for _, refs in baseRefs do
		if refs.Owner then
			mounted += 1
		end
	end
	local inFlight = 0
	for _, map in escrows do
		for _ in map do
			inFlight += 1
		end
	end
	return { Records = records, Bases = mounted, Requests = TankRequests.Size(), Escrows = inFlight }
end

function TankService._runtimeFor(player: Player): any
	return runtimes[player]
end

--------------------------------------------------------------------------------
-- Жизненный цикл сервиса
--------------------------------------------------------------------------------

local function required(root: Instance, path: { string }, className: string): any
	local node: Instance = root
	for _, name in path do
		local child = node:FindFirstChild(name)
		if not child then
			error(`[TankService] в {root:GetFullName()} нет {table.concat(path, ".")}`)
		end
		node = child
	end
	if not node:IsA(className) then
		error(`[TankService] {node:GetFullName()} должен быть {className}, а это {node.ClassName}`)
	end
	return node
end

local function resolveBase(base: Base): BaseRefs
	local slots: { SlotRefs } = {}
	local tank = base.Tank
	for index = 1, TankConfig.MaxSlots do
		local name = `Slot_{index}`
		local model = required(tank, { "Slots", name }, "Model") :: Model
		required(model, { "Display", "FishPoint" }, "Attachment")
		local display = required(model, { "Display" }, "BasePart") :: BasePart
		local label = required(model, { "Pedestal", "LabelGui", "Label" }, "TextLabel") :: TextLabel
		local bar = required(model, { "LightBar" }, "BasePart") :: BasePart
		local light = bar:FindFirstChildOfClass("SurfaceLight")
		if not light then
			error(`[TankService] у {bar:GetFullName()} нет SurfaceLight`)
		end
		local slot: SlotRefs = {
			Index = index,
			Model = model,
			Display = display,
			Label = label,
			LightBar = bar,
			Light = light,
			Template = {
				LabelText = TEXTS.SlotEmpty,
				LabelColor = label.TextColor3,
				BarColor = bar.Color,
				BarMaterial = bar.Material,
				LightEnabled = light.Enabled,
				DisplayTransparency = display.Transparency,
			},
			Attrs = {},
			Look = "",
		}
		slots[index] = slot
	end
	local attachment = base.TankPromptAttachment
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TankPrompt"
	prompt.ActionText = PROMPT.Action
	prompt.ObjectText = PROMPT.Object
	prompt.HoldDuration = PROMPT.HoldDuration
	prompt.MaxActivationDistance = PROMPT.MaxDistance
	prompt.RequiresLineOfSight = false
	prompt.Enabled = false
	prompt.Parent = attachment
	local refs: BaseRefs = {
		Base = base,
		Slots = slots,
		Prompt = prompt,
		PromptAttachment = attachment,
		Serial = 0,
		Owner = nil,
		TankAttrs = {},
	}
	for _, slot in slots do
		showEmpty(refs, slot, nil, nil)
	end
	return refs
end

function TankService:Init()
	tankEvent = Net.Event("TankEvent")
	stealEvent = Net.Event("StealEvent")
	for _, base in BaseService:GetBases() do
		baseRefs[base] = resolveBase(base)
	end
	if type(DataService.OnSerialize) == "function" then
		DataService:OnSerialize(onSerialize)
	end
	if type(DataService.OnClose) == "function" then
		DataService:OnClose(onClose)
	end
end

function TankService:Start()
	for _, refs in baseRefs do
		refs.Prompt.Triggered:Connect(function(player: Player)
			onTankPrompt(refs, player)
		end)
	end
	DataService.Loaded:Connect(onLoaded)
	DataService.Committed:Connect(onCommitted)
	if DataService.Released then
		DataService.Released:Connect(onReleased)
	end
	BaseService.BaseAssigned:Connect(function(player: Player, _base: Base)
		local rt = runtimes[player]
		if rt then
			tryMount(rt)
		end
	end)
	BaseService.BaseReleased:Connect(function(player: Player, base: Base)
		local rt = runtimes[player]
		if rt and rt.Base == base then
			unmount(rt)
		end
	end)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Net.Event("TankSell").OnServerEvent:Connect(onTankSell)
	if type(FishingService.SetCatchSink) == "function" then
		FishingService.SetCatchSink(function(player: Player, fish: FishData): any
			local rt = runtimes[player]
			if not rt or not rt.Mounted or not DataService:CanWrite(player) then
				return nil
			end
			return TankService:AddFish(player, fish, "catch")
		end)
	end
	-- Уже загруженные (Studio: игрок успел раньше скрипта).
	for _, player in Players:GetPlayers() do
		local data = DataService:IsLoaded(player) and DataService:Get(player)
		if data then
			onLoaded(player, data)
		end
	end
	task.spawn(incomeLoop)
end

return TankService
