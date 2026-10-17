--!strict
--[[
	DataService — сохранение прогресса игрока (Этап 3): единственный, кто трогает DataStore.
	Схема данных и её починка — ServerScriptService.Lib.PlayerData, числа — DataConfig.
	ЗАГЛУШКА (волна 0): API и договор ниже, поведения ещё нет — Get / WaitLoaded отдают nil,
	CanWrite / IsLoaded — false, сигналы не срабатывают. Реализация — волна 1 (scratchpad
	design.md, §2.2).

	Что делает:
	  1. При старте одна проверка доступа (GetAsync("__probe"), не дольше ProbeTimeout; probed
	     ставится на любом пути). Хранилище — PlayerData.StoreNameFor(RunService:IsStudio()).
	     Режим Memory — ТОЛЬКО в Studio и если ошибка говорит, что API выключен (403 / publish /
	     not allowed): шаблон каждому, ни одной записи, одно предупреждение в Output
	     (DataConfig.Texts.MemoryWarn) и одно уведомление в игре; BindToClose выходит сразу. На
	     живом сервере ошибка проверки только пишется в лог. Внутренняя ошибка Start — режим
	     Broken: громкий warn, дальше как Memory (клиенты видят DataMode = "Memory"), никто не
	     ждёт Loaded вечно.
	  2. Загрузка игрока — UpdateAsync(KeyFor(UserId), transform) через очередь ключа; transform
	     чистый, не ждёт и не кикает (только ставит флаги; их сбрасывает каждый вызов):
	       не таблица → corrupt; Session другого (не этот LoadId) и не «свой» (Server = TOKEN, но
	       записи игрока уже нет) и не старый (T старше LockStale) → lockedByOther; V > Version →
	       tooNew; иначе Sanitize(Migrate(Reconcile(data))), Session = { Id = LoadId, Server =
	       TOKEN, Job = game.JobId, T = os.time() }, Created при первой загрузке; userIds — {UserId}
	       только при UserId > 0. Живая таблица — то, что ВЕРНУЛ UpdateAsync (transform мог
	       выполниться не раз).
	     lockedByOther → ждать LockWait.Every и снова; после LockWait.Tries — забрать замок
	     (steal) с одним warn «[DataService] сессия игрока <id> занята другим сервером —
	     забираю» (ожидание замка — не неудачная попытка). tooNew → Released, Kick(TooNew),
	     ничего не пишется. corrupt → Released, warn, Kick(LoadFailed). Ошибка pcall → повтор
	     через min(Retry.Max, Retry.Base · 2^(n−1)) × (1 + 0.5·random), до Retry.Load раз; коды
	     101–107 (наша ошибка) и 403 не повторяются; кончились — Released, Kick(LoadFailed).
	     Игрок ушёл во время загрузки — повторов больше нет; если попытка в пути взяла замок —
	     сохранение «только отпустить» (те же данные, Session = nil). Успех — Ready, атрибут
	     игрока DataMode = "Ready", сигнал Loaded(player, data).
	  3. Сохранение (Ready / Leaving): transform — нет таблицы, нет Session или чужой Session.Id
	     → lost (отсутствие замка — это «потерян», а не «всё хорошо»); иначе хук OnSerialize
	     (TankService: обновить возраст рыб; Этап 4: какие uid не сохранять), out =
	     PlayerData.Serialize(rec.Data, { skipUid, strict = rec.Strict }), Session (нет при
	     отпускании), LastOnline = os.time(), SaveCount + 1, rec.SnapshotSeq = rec.Dirty.
	     lost при обычном сохранении → Released, warn, Kick(Stolen), если игрок ещё здесь; при
	     ПОВТОРЕ отпускания пустой Session — это наша же прошлая запись или чужое отпускание:
	     Released тихо, без warn и кика. Ошибки 103/104/105 → один warn с путями issues и ОДИН
	     повтор с rec.Strict = true.
	  4. Очередь ключа: одна FIFO на UserId (на уровне модуля, переживает запись игрока); запрос
	     начинается, когда кончился прошлый (с повторами). Перед КАЖДОЙ попыткой UpdateAsync —
	     ждать до lastRequest + MinWriteGap + GapEpsilon; lastRequest ставится, когда pcall
	     ВЕРНУЛСЯ (успех, ошибка, отмена). Пустая очередь после паузы — удаляется.
	  5. Автосохранение: ОДИН цикл раз в секунду на весь сервер (никаких потоков и task.delay на
	     игрока): Ready-записи с now ≥ NextSave. Первое — загрузка + пауза + random() · (AutoSave −
	     пауза), дальше + AutoSave; обновляет Session.T. Бюджет UpdateAsync < BudgetMin → отложить
	     на BudgetDelay (всего не больше LockStale / 3 за цикл). Не вышло — ещё раз после паузы,
	     дальше — обычный ритм. Проверки при старте: AutoSave < LockStale; LeaveSaveWindow +
	     MinWriteGap < LockWait.Tries × LockWait.Every.
	  6. Слияние: SaveSoon увеличивает rec.Dirty и возвращает его; запрос, пока сохранение ключа
	     ЖДЁТ в очереди, — отбрасывается (оно и так запишет свежее); пока сохранение В ПУТИ
	     (снимок взят, Dirty > SnapshotSeq) — ровно ОДНО следующее после записи. После успешной
	     записи rec.Committed = SnapshotSeq и сигнал Committed(player, seq) (и у отпускания).
	  7. Выход (PlayerRemoving): сразу Leaving (CanWrite = false), последнее сохранение с
	     отпусканием, повторы, пока не вышло или не прошло LeaveSaveWindow с выхода (новых попыток
	     после окна нет); потом Released и запись удаляется (если это всё ещё она).
	  8. BindToClose: СРАЗУ, до любого ожидания, closing = true и все Ready → Leaving (тогда
	     PlayerRemoving симулятора, пришедший после, ничего не пишет второй раз — одна последняя
	     запись на ключ); Memory / Broken — выход сразу; pending — набор операций в пути
	     (последние сохранения всех Leaving и все Loading: загрузка, взявшая замок при closing,
	     сразу отпускает его); PlayerAdded при closing — без загрузки; ждать, пока pending не
	     пуст, не дольше CloseBudget; сохранения при закрытии — Retry.Close попытки.
	  9. Кики: только после возврата UpdateAsync, запись — Released ДО Kick (Kick симулятора
	     сразу вызывает PlayerRemoving); после Kick запись могла исчезнуть.

	Состояния записи игрока (DataService:CanWrite — единственные ворота записи):
	  состояние | загрузка                      | сохранение                 | CanWrite | доход
	  Loading   | в пути; повторы — пока игрок тут | —                        | нет      | нет   (заброс: Denied "loading")
	  Ready     | —                             | авто, SaveSoon             | ДА       | да
	  Memory    | —                             | никогда                    | ДА       | да    (только Studio; Broken — так же)
	  Leaving   | —                             | одно последнее с отпусканием | нет    | нет   (сразу в PlayerRemoving и BindToClose)
	  Released  | —                             | никогда                    | нет      | нет   (ставится ДО любого Kick; запись удаляется)

	Правила для всех сервисов, меняющих данные (AddFish, RemoveFish, продажа, AddMoney,
	SpendMoney, SetSlots, SetRod, статистика рыбалки):
	  • первым делом DataService:CanWrite(player); false → nil / false, ничего не меняется;
	  • сначала всё посчитать и проверить (слот, uid, цена, конечность), потом менять в одном
	    порядке без того, что может упасть: убрать → начислить → статистика → атрибуты (поля рыбы →
	    State → Event) → сигналы и remote'ы;
	  • обработчики MoneyChanged / FishAdded / FishRemoved не зовут изменяющие функции сразу
	    (Signal:Fire — task.spawn, они бегут внутри изменения): только через task.defer;
	  • записи игроков — по самому Player (повторный вход — новый Player), и каждое завершение
	    проверяет «records[player] == rec» перед удалением (EconomyService, TankService,
	    MarketService — так же);
	  • поля живой таблицы: EconomyService — Money, Stats.Earned, Stats.Spent; TankService — Tank,
	    TankSlots, NextUid, Stats.Sold; FishingService — RodId, Stats.Caught, Stats.Species. Каждый
	    меняет своё сразу, за CanWrite; DataService сохраняет то, что лежит;
	  • SaveSoon — на редкие моменты: легендарная и мифическая рыба, кража (обе стороны, Этап 4),
	    покупки (Этап 5). Никаких RBXScriptConnection на игрока здесь: ожидание — запись или
	    поток; ждущие WaitLoaded получают nil при выходе и по тайм-ауту.
	Личность: TOKEN = HttpService:GenerateGUID(false) — один на запуск сервера (не JobId: в Studio
	он "", в симуляторе — постоянный); rec.LoadId — один на загрузку (и на все её повторы).

	Первая настоящая миграция (v2): когда Migrate меняет V, старое значение ОДИН раз пишется
	SetAsync в DataConfig.BackupStore, ключ «Player_<id>_v<старая версия>». Повышая Version,
	публикуй с «Migrate to latest update» (иначе кикнутого старым сервером снова пустит старый).

	API (Этапы 4–5 пользуются только им):
	  DataService.Loaded                                -- Signal (player, data): один раз, Ready или Memory
	  DataService:Get(player) -> PlayerData.Data?       -- живая таблица (nil до загрузки / после отпускания)
	  DataService:IsLoaded(player) -> boolean
	  DataService:CanWrite(player) -> boolean           -- Ready или Memory: ворота записи
	  DataService:WaitLoaded(player, timeout?) -> PlayerData.Data?   -- nil при выходе / тайм-ауте
	  DataService:Mode() -> "DataStore" | "Memory" | "Broken"
	  DataService:SaveSoon(player) -> number            -- seq: слитое сохранение с паузой ключа
	  DataService:CommittedSeq(player) -> number
	  DataService.Committed                             -- Signal (player, seq): записан снимок со всеми SaveSoon до seq
	  DataService:OnSerialize(fn: (player, data) -> skipUid?)   -- один хук (TankService); внутри
	                                                    -- transform сохранения, не ждёт
	  DataService.Token, DataService.StoreName          -- только для чтения (тесты)
	  DataService._debugSizes(), _recordFor(player), _saveRecordForTest(rec)   -- для тестов
	Атрибут Player: DataMode ("Loading" | "Ready" | "Memory").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local Signal = require(Shared.Util.Signal)
local PlayerData = require(ServerScriptService.Lib.PlayerData)

export type Mode = "DataStore" | "Memory" | "Broken"
export type State = "Loading" | "Ready" | "Memory" | "Leaving" | "Released"
-- Хук сохранения: возвращает skipUid (Этап 4: рыбы «в пути») или nil.
export type SerializeHook = (player: Player, data: PlayerData.Data) -> ((uid: string) -> boolean)?

local DataService = {
	Loaded = Signal.new(), -- (player, data)
	Committed = Signal.new(), -- (player, seq)
	Token = "", -- GUID этого запуска сервера (волна 1)
	StoreName = PlayerData.StoreNameFor(RunService:IsStudio()),
}

function DataService:Init() end

function DataService:Start() end

function DataService:Get(_player: Player): PlayerData.Data?
	return nil
end

function DataService:IsLoaded(_player: Player): boolean
	return false
end

function DataService:CanWrite(_player: Player): boolean
	return false
end

function DataService:WaitLoaded(_player: Player, _timeout: number?): PlayerData.Data?
	return nil
end

function DataService:Mode(): Mode
	return "DataStore"
end

function DataService:SaveSoon(_player: Player): number
	return 0
end

function DataService:CommittedSeq(_player: Player): number
	return 0
end

function DataService:OnSerialize(_fn: SerializeHook) end

-- Размеры внутренних таблиц (тесты: после выхода всех игроков — нули).
function DataService._debugSizes(): { [string]: number }
	return { Records = 0, Queues = 0, LastRequest = 0, Pending = 0 }
end

function DataService._recordFor(_player: Player): any
	return nil
end

function DataService._saveRecordForTest(_rec: any) end

return DataService
