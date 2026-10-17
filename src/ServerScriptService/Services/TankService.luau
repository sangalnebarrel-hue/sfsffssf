--!strict
--[[
	TankService — садок игрока (Этап 3): рыбы в витринах двора базы (Tank.Slots.Slot_1..12),
	открытые витрины, «спящие» рыбы, правило полного садка, продажа, общий цикл дохода раз в
	секунду, атрибуты витрин и садка, таблички и подсветка витрин, кнопка у большого аквариума,
	remote'ы садка и хук сохранения. Правила и вид сумм — TankRules, числа — TankConfig /
	EconomyConfig, данные — DataService (поля Tank, TankSlots, NextUid, Stats.Sold — его).
	ЗАГЛУШКА (волна 0): API и договор ниже, поведения ещё нет — AddFish / RemoveFish отдают nil,
	SetLocked / SetSlots — false, сигналы не срабатывают, remote'ы не слушаются. Реализация —
	волна 1 (scratchpad design.md, §3.3, §4.3, §4.5, §4.6, §5.2).

	Что делает:
	  1. Init: у каждой базы ссылки витрин Slot_1..12 — Pedestal, Display, Display.FishPoint,
	     Pedestal.LabelGui.Label, LightBar и его SurfaceLight (нет — громкая ошибка); кнопка
	     ProximityPrompt "TankPrompt" на Tank.Glass.PromptAttachment (TankConfig.Prompt: «Открыть» /
	     «Садок», HoldDuration 0, MaxActivationDistance 10, RequiresLineOfSight false, Enabled
	     false); хук DataService:OnSerialize (обновить возраст рыб на базе; Этап 4 — какие uid не
	     сохранять).
	  2. DataService.Loaded → записи рыб: Rarity, Value, Income10 — из FishingRules.Price; рыба
	     «спит» (Dormant), если вид незнаком или у неё нет своей витрины (PlayerData.Layout).
	  3. «Подключение» садка к базе — когда у игрока есть И данные, И база (что второе; и
	     BaseService.BaseAssigned): витрины 1..12 (атрибуты, таблички, подсветка) с Event
	     "<n>|mount|", GrowFrom = сейчас − Age каждой активной рыбы, атрибуты садка и игрока,
	     кнопка включена. Отключение (BaseReleased, выход): Age каждой рыбы замирает, все витрины —
	     "empty" / «Пусто» / вид шаблона, поля рыбы — nil, атрибуты садка сняты, кнопка выключена.
	  4. Улов: FishingService.SetCatchSink(sink) (только если это функция — заглушки сервисов в
	     тестах); sink(player, fish) -> TankResult? — nil без CanWrite или без базы (это лишь
	     гонка выхода / закрытия: заброс до загрузки не принимается), иначе AddFish(player, fish,
	     "catch"). Синхронно, без ожиданий.
	  5. AddFish(player, fish, reason) — за DataService:CanWrite. Сначала посчитать: Uid =
	     PlayerData.NewUid(data), решение полного садка, цены; потом менять: data.Tank → записи →
	     EconomyService:AddMoney(…, "autosell") при "replaced" / "sold" → Stats.Sold + 1 → атрибуты
	     витрины (Event последним) → доход → атрибуты → FishAdded / FishRemoved. Полный садок:
	       есть свободная открытая витрина → в самую младшую → "stored";
	       иначе слабейшая активная (не Locked, не Dormant) — TankRules.ChooseReplacement: доход
	       новой больше → слабейшую продать по SellPrice(…, HomeRatePct), новая на её место →
	       "replaced"; иначе новую продать сразу по SellPrice(Value, 0, HomeRatePct) → "sold".
	     Возвращает TankResult { Result, Slot?, Uid?, Count, Slots, Replaced?, Price?, First? }
	     (First — Stats.Caught == 1: первое уведомление и «!»). Рыба не из улова (Этап 4: кража) —
	     ещё и TankEvent("Stored", результат + { Fish }).
	  6. Продажа TankSell(uid) — проверки по порядку из шапки RemoteNames (uid, лимит запросов
	     TankConfig.Requests — из него же каждый ответ, CanWrite, база, своя активная рыба, не
	     Locked, конечная цена), потом без ожиданий: возраст сейчас и цена
	     TankRules.SellPrice(Value, ageNow, MarketService:RatePct(player)), убрать из data.Tank
	     (плотно) и записей, AddMoney, статистика, витрина ("empty", поля nil, Event "sold"), доход,
	     TankEvent("Sold", …), FishRemoved.
	  7. Кнопка "TankPrompt" (Triggered) — через тот же лимит запросов; только хозяину базы и после
	     проверки расстояния сервером (≤ MaxDistance + Slack): TankEvent("Open", { Place = "Tank",
	     RatePct = атрибут SellRatePct, Name = «Садок» }).
	  8. Цикл дохода — ОДИН task.spawn на сервер: dt = task.wait(IncomeTick), накопитель с
	     фиксированным шагом (acc += dt; n = floor(acc / IncomeTick); acc −= n · IncomeTick;
	     n = min(n, MaxCatchUp)); по записям ЭТОГО сервиса (не Players:GetPlayers), только
	     подключённым и с CanWrite: carry10 += n · Income10Sum, целые монеты — AddMoney(…, "income"),
	     остаток (десятые) копится; возраст рыб для сохранения; MarketService:Sample(player). Шаг
	     игрока — в xpcall (warn с ограничением частоты), сам цикл — вне pcall: одна плохая запись
	     не останавливает всех. Ничего не ждёт (HumanoidRootPart — FindFirstChild).
	  9. Возраст: ageNow = min(Time, GetServerTimeNow() − GrowFrom) — та же формула и те же часы,
	     что у клиента (TankRules.AgeAt); продажа — по ageNow в её миг; без базы (очередь) — ни
	     дохода, ни роста. Income10Sum пересчитывается только при изменении садка; атрибуты Income
	     (игрок и садок) и «Доход/с» — при изменении, не каждый тик.
	Записи игроков — по самому Player с проверкой «это всё ещё она»; всё на игрока — в его Trove,
	чистится при выходе; без бесконечных списков (DataService, «Правила»).

	Вид витрины на сервере (при изменении): "empty" / свободная база — табличка «Пусто», LightBar
	как в шаблоне (AquaGlow, Neon, свет есть), стекло как в шаблоне (0.66); "fish" — табличка с
	именем рыбы, TextColor3 = цвет редкости (FishConfig), LightBar.Color = цвет редкости
	(UIConfig.Rarity[r].Bottom; мифическая — UIConfig.Rainbow[6]), свет есть, стекло
	Display.Transparency = TankConfig.Display.GlassOccupied; "locked" — «🔒 Закрыто», LightBar
	SmoothPlastic цвета Slate.Bottom, SurfaceLight выключен. Новых деталей на сервере нет.

	Атрибуты (RemoteNames, «Состояние садка и денег»): Player — TankCount, TankSlots (и Income —
	через EconomyService:SetIncome); Base_N.Tank — Count, Slots, Income; витрины — State, FishUid,
	FishId, Rarity, Mutation, Kg, Value, Income, GrowFrom (TankRules.AttrTime), Event
	("<n>|in|<FishId>", "<n>|mount|", "<n>|sold|<цена>", "<n>|swap|<цена>", Этап 4 "<n>|stolen|";
	поля рыбы → State → Event последним; n растёт у базы всё время работы сервера).
	Remote'ы: TankSell (клиент → сервер), TankEvent (сервер → клиент) — протокол в RemoteNames.

	Этап 4 (кража) — уже есть: RemoveFish(owner, uid, reason) и AddFish(thief, fish, "stolen")
	(то же правило полного садка; оба nil без CanWrite своего игрока), сигналы FishAdded /
	FishRemoved, Event "stolen" одним событием, SetLocked(owner, uid, bool) (продажа — Denied
	"locked", рыба не заменяется), Pedestal.PromptAttachment свободна под кнопки кражи. Порядок
	кражи (никогда не дюп; худшее — одна потерянная рыба): 1) RemoveFish(жертва, uid) → seqV =
	DataService:SaveSoon(жертва); 2) AddFish(вор, рыба, "stolen") — новый Uid из счётчика вора,
	Origin = "<UserId жертвы>:<uid>", в записи Escrow = { жертва, seqV }: пока так — не
	продаётся, хук OnSerialize её не сохраняет; 3) когда Committed(жертва) ≥ seqV — Escrow
	снимается, SaveSoon(вор); 4) запись жертвы так и не легла (замок потерян) — рыба «в пути»
	пропадает, когда вор уходит. Две рыбы с одним Origin в садке — оставить одну.
	Этап 5 (магазин): SetSlots(player, n) — открывает следующие витрины (атрибуты, таблички) и
	будит «спящих» знакомых рыб в новых витринах.

	API:
	  TankService:AddFish(player, fish: FishData, reason) -> TankResult?
	  TankService:RemoveFish(owner, uid, reason) -> PlayerData.Fish?
	  TankService:SetLocked(owner, uid, locked) -> boolean
	  TankService:SetSlots(player, n) -> boolean
	  TankService.FishAdded, TankService.FishRemoved   -- Signal (player, fish, reason)
	  TankService._debugSizes()                        -- тесты: после выхода всех — нули
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local FishingRules = require(Shared.FishingRules)
local Signal = require(Shared.Util.Signal)
local PlayerData = require(ServerScriptService.Lib.PlayerData)

type FishData = FishingRules.FishData

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
	Price: number?,
	First: boolean?,
}

local TankService = {
	FishAdded = Signal.new(), -- (player, fish, reason)
	FishRemoved = Signal.new(), -- (player, fish, reason)
}

function TankService:Init() end

function TankService:Start() end

function TankService:AddFish(_player: Player, _fish: FishData, _reason: string): TankResult?
	return nil
end

function TankService:RemoveFish(_owner: Player, _uid: string, _reason: string): PlayerData.Fish?
	return nil
end

function TankService:SetLocked(_owner: Player, _uid: string, _locked: boolean): boolean
	return false
end

function TankService:SetSlots(_player: Player, _slots: number): boolean
	return false
end

function TankService._debugSizes(): { [string]: number }
	return { Records = 0, Bases = 0 }
end

return TankService
