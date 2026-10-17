--!strict
--[[
	DataService — сохранение прогресса игрока (Этап 3): единственный, кто трогает DataStore.
	Схема данных и её починка — ServerScriptService.Lib.PlayerData, числа — DataConfig
	(подробно — scratchpad design.md, §2.2).

	Что делает:
	  1. При старте одна проверка доступа (GetAsync("__probe"), не дольше ProbeTimeout; probed
	     ставится на любом пути). Хранилище — PlayerData.StoreNameFor(RunService:IsStudio()).
	     Режим Memory — ТОЛЬКО в Studio и если ошибка говорит, что API выключен (403 / publish /
	     not allowed): шаблон каждому, ни одной записи, одно предупреждение в Output
	     (DataConfig.Texts.MemoryWarn) и одно уведомление в игре (его показывает клиент по
	     DataMode = "Memory"); BindToClose выходит сразу. На живом сервере ошибка проверки только
	     пишется в лог. Внутренняя ошибка Start — режим Broken: громкий warn, дальше как Memory
	     (клиенты видят DataMode = "Memory"), никто не ждёт Loaded вечно.
	  2. Загрузка игрока — UpdateAsync(KeyFor(UserId), transform) через очередь ключа; transform
	     чистый, не ждёт и не кикает (только ставит флаги; их сбрасывает каждый вызов):
	       не таблица → corrupt; Session другого (не этот LoadId) и не «свой» (Server = TOKEN, но
	       записи игрока уже нет) и не старый (T старше LockStale) → lockedByOther; V > Version →
	       tooNew; иначе Sanitize(Migrate(Reconcile(data))), Session = { Id = LoadId, Server =
	       TOKEN, Job = game.JobId, T = os.time() }, Created при первой загрузке; userIds — {UserId}
	       только при UserId > 0. Живая таблица — то, что ВЕРНУЛ UpdateAsync (transform мог
	       выполниться не раз). Что починил Sanitize — один warn после UpdateAsync.
	     lockedByOther → ждать LockWait.Every и снова; после LockWait.Tries — забрать замок
	     (steal) с одним warn «[DataService] сессия игрока <id> занята другим сервером —
	     забираю» (ожидание замка — не неудачная попытка). tooNew → Released, Kick(TooNew),
	     ничего не пишется. corrupt → Released, warn, Kick(LoadFailed). Ошибка pcall → warn и повтор
	     через min(Retry.Max, Retry.Base · 2^(n−1)) × (1 + 0.5·random) (но не раньше паузы ключа),
	     до Retry.Load раз; коды 101–107 (наша ошибка) и 403 не повторяются; кончились — Released,
	     Kick(LoadFailed). Игрок ушёл (или сервер закрывается) во время загрузки — повторов больше
	     нет, ждём только попытку в пути; если она взяла замок — сохранение «только отпустить» (те
	     же данные, Session = nil), потом запись удаляется. Успех — Ready, сигнал Loaded(player,
	     data), потом атрибут игрока DataMode = "Ready".
	  3. Сохранение (Ready / Leaving): transform — нет таблицы, нет Session или чужой Session.Id
	     → lost (отсутствие замка — это «потерян», а не «всё хорошо»); иначе снимок seq = Dirty,
	     хук OnSerialize (TankService: обновить возраст рыб; Этап 4: какие uid не сохранять; его
	     ошибка — warn, сохранение идёт дальше), out = PlayerData.Serialize(rec.Data, { skipUid,
	     strict = rec.Strict }), Session (нет при отпускании), LastOnline = os.time(), SaveCount + 1,
	     rec.SnapshotSeq = seq. Что Serialize выбросил — один warn на путь поля за игру.
	     lost при обычном сохранении → Released, warn, Kick(Stolen), если игрок ещё здесь; при
	     ПОВТОРЕ отпускания пустой Session — это наша же прошлая запись или чужое отпускание:
	     Released тихо, без warn и кика. Ошибки 103/104/105 → один warn с путями issues и ОДИН
	     повтор с rec.Strict = true (то же плохое значение второй раз не уходит).
	  4. Очередь ключа: одна FIFO на UserId (на уровне модуля, переживает запись игрока; поток
	     живёт, только пока в очереди есть запросы); запрос начинается, когда кончился прошлый (с
	     повторами). Перед КАЖДОЙ попыткой UpdateAsync — ждать до lastRequest + MinWriteGap +
	     GapEpsilon; lastRequest ставится, когда pcall ВЕРНУЛСЯ (успех, ошибка, отмена). Пустая
	     очередь и lastRequest удаляются, когда пауза прошла.
	  5. Автосохранение: ОДИН цикл раз в секунду на весь сервер (никаких потоков и task.delay на
	     игрока): Ready-записи с now ≥ NextSave. Первое — загрузка + пауза + random() · (AutoSave −
	     пауза), дальше + AutoSave; обновляет Session.T. Бюджет UpdateAsync < BudgetMin → отложить
	     на BudgetDelay (всего не больше LockStale / 3 за цикл). Не вышло — ещё раз после паузы
	     (Retry.Save), дальше — обычный ритм. Проверки при старте: AutoSave < LockStale;
	     LeaveSaveWindow + MinWriteGap < LockWait.Tries × LockWait.Every.
	  6. Слияние: SaveSoon увеличивает rec.Dirty и возвращает его; запрос, пока сохранение ключа
	     ЖДЁТ в очереди, — отбрасывается (оно и так запишет свежее); пока сохранение В ПУТИ (снимок
	     взят, Dirty > SnapshotSeq) — ровно ОДНО следующее после записи. После успешной записи
	     rec.Committed = снимок и сигнал Committed(player, seq) (и у отпускания).
	  7. Выход (PlayerRemoving): сразу Leaving (CanWrite = false; ждущие WaitLoaded получают
	     nil), последнее сохранение с отпусканием (ждущее в очереди автосохранение им и
	     становится — одна запись, не две), повторы, пока не вышло или не прошло LeaveSaveWindow с
	     выхода (первая попытка — всегда, новых после окна нет); потом Released и запись удаляется
	     (если это всё ещё она). Memory — запись удаляется сразу.
	  8. BindToClose: СРАЗУ, до любого ожидания, closing = true и все Ready → Leaving (тогда
	     PlayerRemoving симулятора, пришедший после, ничего не пишет второй раз — одна последняя
	     запись на ключ); Memory / Broken — выход сразу; pending — набор записей с операцией в пути
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
	    TankSlots, NextUid, Stats.Sold; FishingService — RodId, Stats.Caught, Stats.Species;
	    DataService — V, Session, Created, LastOnline, SaveCount. Каждый меняет своё сразу, за
	    CanWrite; DataService сохраняет то, что лежит;
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
	  DataService:IsLoaded(player) -> boolean           -- Ready или Memory
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
	                                                    -- (_saveRecordForTest ждёт и отдаёт итог:
	                                                    -- "committed" | "lost" | "quiet" | "failed")
	Атрибут Player: DataMode ("Loading" | "Ready" | "Memory").
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local DataConfig = require(Shared.Config.DataConfig)
local Signal = require(Shared.Util.Signal)
local PlayerData = require(ServerScriptService.Lib.PlayerData)

export type Mode = "DataStore" | "Memory" | "Broken"
export type State = "Loading" | "Ready" | "Memory" | "Leaving" | "Released"
-- Хук сохранения: возвращает skipUid (Этап 4: рыбы «в пути») или nil.
export type SerializeHook = (player: Player, data: PlayerData.Data) -> ((uid: string) -> boolean)?
-- Итог одного запроса сохранения (_saveRecordForTest).
export type SaveResult = "committed" | "lost" | "quiet" | "failed" | "skipped"

type Waiter = { Thread: thread, Timer: thread? }

type Record = {
	Player: Player,
	UserId: number,
	Key: string,
	State: State,
	LoadId: string,
	Data: PlayerData.Data?,
	Announced: boolean, -- Loaded уже был (сервисы держат ссылки на Data)
	Left: boolean, -- игрок ушёл (или сервер закрывается)
	LeftAt: number, -- os.clock() выхода (окно LeaveSaveWindow)
	Dirty: number, -- последний SaveSoon
	SnapshotSeq: number, -- Dirty, когда снят последний снимок
	Committed: number, -- снимок последней успешной записи
	NextSave: number, -- os.clock() следующего автосохранения
	Postponed: number, -- секунд отложено в этом цикле (мало бюджета)
	Queued: Request?, -- сохранение ждёт в очереди ключа (ещё не начато)
	InFlight: boolean, -- сохранение идёт
	FinalPending: boolean, -- игрок ушёл, пока шло обычное сохранение: оно станет последним
	FinalClose: boolean, -- … при закрытии сервера (Retry.Close)
	Strict: boolean, -- без незнакомых полей (после ошибки 103/104/105)
	Waiters: { Waiter },
	Warned: { [string]: boolean }, -- пути полей, о которых уже предупреждали
}

type Request = {
	Kind: "load" | "save",
	Rec: Record,
	Release: boolean, -- последнее сохранение: Session = nil
	Close: boolean, -- при закрытии сервера (Retry.Close попыток)
	Test: boolean, -- _saveRecordForTest: сохранить даже отпущенную запись
	Done: boolean,
	Result: SaveResult?,
	Waiter: thread?,
}

type Queue = { Items: { Request }, Running: boolean }

local GAP = DataConfig.MinWriteGap + DataConfig.GapEpsilon
local RETRY = DataConfig.Retry
local TEXTS = DataConfig.Texts

local DataService = {
	Loaded = Signal.new(), -- (player, data)
	Committed = Signal.new(), -- (player, seq)
	Token = "", -- GUID этого запуска сервера (Init)
	StoreName = PlayerData.StoreNameFor(RunService:IsStudio()),
}

local records: { [Player]: Record } = {}
local queues: { [number]: Queue } = {}
local lastRequest: { [number]: number } = {}
local pending: { [Record]: boolean } = {} -- загрузки и последние сохранения в пути
local mode: Mode = "DataStore"
local probed = false
local probeWaiters: { thread } = {}
local closing = false
local store: DataStore? = nil
local serializeHook: SerializeHook? = nil
local TOKEN = ""

--------------------------------------------------------------------------------
-- Помощники
--------------------------------------------------------------------------------

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

local function num(x: any, default: number): number
	return if finite(x) then x else default
end

-- Обработчик xpcall: текст ошибки с трассировкой.
local function trace(err: any): string
	return debug.traceback(tostring(err), 2)
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

local function lockFor(rec: Record): PlayerData.Session
	return { Id = rec.LoadId, Server = TOKEN, Job = game.JobId, T = os.time() }
end

-- Кому принадлежат данные ключа (Roblox: GDPR); только настоящие UserId (в Studio они < 0).
local function userIdsOf(rec: Record): { number }?
	return if rec.UserId > 0 then { rec.UserId } else nil
end

-- Код ошибки DataStore («104: Cannot store …» → 104) или nil.
local function errorCode(err: any): number?
	local code = string.match(tostring(err), "(%d%d%d):")
	return if code then tonumber(code) else nil
end

-- Ошибка значения (наша): 103 / 104 / 105 — повтор только без незнакомых полей (strict).
local function badValue(err: any): boolean
	local code = errorCode(err)
	return code == 103 or code == 104 or code == 105
end

-- Повторять ли запрос после этой ошибки: 101–107 — наша ошибка, 403 — доступ запрещён.
local function retryable(err: any): boolean
	local code = errorCode(err)
	if code and code >= 101 and code <= 107 then
		return false
	end
	return string.find(tostring(err), "403", 1, true) == nil
end

-- Ошибка проверки, которая значит «в Studio выключен доступ к API».
local function accessError(err: any): boolean
	local text = string.lower(tostring(err))
	return string.find(text, "403", 1, true) ~= nil
		or string.find(text, "publish", 1, true) ~= nil
		or string.find(text, "not allowed", 1, true) ~= nil
end

local function backoff(attempt: number): number
	return math.min(RETRY.Max, RETRY.Base * 2 ^ (attempt - 1)) * (1 + 0.5 * math.random())
end

-- Есть ли ещё живая запись этого UserId, кроме rec (для «свой ли это замок»).
local function liveRecordFor(userId: number, except: Record): boolean
	for _, other in records do
		if other ~= except and other.UserId == userId and other.State ~= "Released" then
			return true
		end
	end
	return false
end

local function wakeWaiters(rec: Record, data: PlayerData.Data?)
	local waiters = rec.Waiters
	rec.Waiters = {}
	for _, waiter in waiters do
		local timer = waiter.Timer
		if timer and coroutine.status(timer) == "suspended" then
			task.cancel(timer)
		end
		task.spawn(waiter.Thread, data)
	end
end

local function getStore(): DataStore
	local current = store
	if current then
		return current
	end
	local created = DataStoreService:GetDataStore(DataService.StoreName)
	store = created
	return created
end

--------------------------------------------------------------------------------
-- Очередь ключа и пауза между запросами
--------------------------------------------------------------------------------

local function waitGap(userId: number)
	while true do
		local last = lastRequest[userId]
		local wait = if last then last + GAP - os.clock() else 0
		if wait <= 0 then
			return
		end
		task.wait(wait)
	end
end

-- Один UpdateAsync (пауза ключа уже выдержана): lastRequest — когда pcall вернулся.
local function attempt(rec: Record, transform: (any) -> (any, any)): (boolean, any)
	local ok, result = pcall(function(): any
		return (getStore() :: any):UpdateAsync(rec.Key, transform)
	end)
	lastRequest[rec.UserId] = os.clock()
	return ok, result
end

local process: (request: Request) -> ()
local recover: (request: Request) -> ()

local function runQueue(userId: number, queue: Queue)
	while #queue.Items > 0 do
		local request = table.remove(queue.Items, 1) :: Request
		local ok, err = xpcall(function(): any
			process(request)
			return nil
		end, trace)
		if not ok then
			warn(`[DataService] ❌ внутренняя ошибка очереди игрока {userId}: {err}`)
			recover(request)
		end
		request.Done = true
		local waiter = request.Waiter
		if waiter and coroutine.status(waiter) == "suspended" then
			request.Waiter = nil
			task.spawn(waiter, request.Result)
		end
	end
	queue.Running = false
end

local function enqueue(request: Request)
	local userId = request.Rec.UserId
	local queue = queues[userId]
	if not queue then
		queue = { Items = {}, Running = false }
		queues[userId] = queue
	end
	table.insert(queue.Items, request)
	if not queue.Running then
		queue.Running = true
		task.spawn(runQueue, userId, queue)
	end
end

local function newRequest(kind: "load" | "save", rec: Record, release: boolean, close: boolean): Request
	return {
		Kind = kind,
		Rec = rec,
		Release = release,
		Close = close,
		Test = false,
		Done = false,
		Result = nil,
		Waiter = nil,
	}
end

--------------------------------------------------------------------------------
-- Конец записи
--------------------------------------------------------------------------------

-- Released: запись больше ничего не пишет и удаляется (если это всё ещё она).
local function release(rec: Record)
	rec.State = "Released"
	pending[rec] = nil
	if records[rec.Player] == rec then
		records[rec.Player] = nil
	end
	wakeWaiters(rec, nil)
end

-- Released ДО Kick (Kick симулятора сразу вызывает PlayerRemoving).
local function kick(rec: Record, text: string)
	release(rec)
	local player = rec.Player
	if player.Parent == Players then
		player:Kick(text)
	end
end

-- Данные без DataStore (Memory / Broken): шаблон, можно играть, ничего не пишется.
local function becomeMemory(rec: Record)
	if rec.State ~= "Loading" then
		return
	end
	local data = PlayerData.Template()
	data.Created = os.time()
	rec.Data = data
	rec.State = "Memory"
	rec.Announced = true
	pending[rec] = nil
	DataService.Loaded:Fire(rec.Player, data)
	wakeWaiters(rec, data)
	rec.Player:SetAttribute("DataMode", "Memory")
end

local function becomeReady(rec: Record, data: PlayerData.Data)
	rec.Data = data
	rec.State = "Ready"
	rec.Announced = true
	rec.NextSave = os.clock() + GAP + math.random() * math.max(0, DataConfig.AutoSave - GAP)
	pending[rec] = nil
	DataService.Loaded:Fire(rec.Player, data)
	wakeWaiters(rec, data)
	rec.Player:SetAttribute("DataMode", "Ready")
end

--------------------------------------------------------------------------------
-- Сохранение
--------------------------------------------------------------------------------

-- Предупреждения Serialize: один warn на путь поля за игру (путь — до первого «: »).
local function reportIssues(rec: Record, issues: { string }, what: string)
	local fresh = {}
	for _, issue in issues do
		local path = string.match(issue, "^(.-): ") or issue
		if not rec.Warned[path] then
			rec.Warned[path] = true
			table.insert(fresh, issue)
		end
	end
	if #fresh > 0 then
		warn(`[DataService] {what} игрока {rec.UserId}: {table.concat(fresh, "; ")}`)
	end
end

-- Одна попытка сохранения (пауза ключа уже выдержана).
local function saveOnce(rec: Record, releaseLock: boolean, isRetry: boolean): (SaveResult, any)
	local quiet = false
	local snapshot = 0
	local issues: { string } = {}
	local data = rec.Data :: PlayerData.Data
	local function transform(old: any): (any, any)
		quiet = false
		issues = {}
		if type(old) ~= "table" or type(old.Session) ~= "table" or old.Session.Id ~= rec.LoadId then
			-- Не наш замок — «потерян» (lost); на ПОВТОРЕ отпускания пустой Session — тихо (quiet):
			-- наша же прошлая запись (ответ потерялся) или чужое отпускание.
			quiet = releaseLock and isRetry and type(old) == "table" and old.Session == nil
			return nil
		end
		snapshot = rec.Dirty
		local skip = nil
		local hook = serializeHook
		if hook and rec.Announced then
			local ok, result = pcall(hook, rec.Player, data)
			if ok then
				skip = result
			elseif not rec.Warned["<hook>"] then
				rec.Warned["<hook>"] = true
				warn(
					`[DataService] хук OnSerialize упал (игрок {rec.UserId}), сохраняю без него: {result}`
				)
			end
		end
		local out, found = PlayerData.Serialize(data, { skipUid = skip, strict = rec.Strict })
		issues = found
		out.Session = if releaseLock then nil else lockFor(rec)
		out.LastOnline = os.time()
		out.SaveCount = num(old.SaveCount, 0) + 1
		rec.SnapshotSeq = snapshot
		return out, userIdsOf(rec)
	end
	local ok, value = attempt(rec, transform)
	if not ok then
		return "failed", { err = value, issues = issues }
	end
	if value == nil then
		return if quiet then "quiet" else "lost", nil
	end
	reportIssues(rec, issues, "сохранение: выброшено")
	rec.Committed = math.max(rec.Committed, snapshot)
	if type(value) == "table" then
		data.SaveCount = num(value.SaveCount, data.SaveCount)
		data.LastOnline = num(value.LastOnline, data.LastOnline)
	end
	DataService.Committed:Fire(rec.Player, snapshot)
	return "committed", nil
end

local function requestSave(rec: Record)
	if rec.State ~= "Ready" or rec.Queued or rec.InFlight then
		return
	end
	local request = newRequest("save", rec, false, false)
	rec.Queued = request
	enqueue(request)
end

local function processSave(request: Request)
	local rec = request.Rec
	if rec.Queued == request then
		rec.Queued = nil
	end
	if not request.Test then
		if rec.State == "Released" or (not request.Release and rec.State ~= "Ready") then
			request.Result = "skipped"
			return
		end
	end
	if rec.Data == nil then
		request.Result = "skipped"
		return
	end
	rec.InFlight = true
	local maxAttempts = if request.Close then RETRY.Close elseif request.Release then math.huge else RETRY.Save
	local attempts = 0
	local strictRetried = false
	local result: SaveResult = "failed"
	while true do
		waitGap(rec.UserId)
		if rec.FinalPending and not request.Release and not request.Test then
			rec.FinalPending = false
			request.Release = true
			request.Close = rec.FinalClose
			maxAttempts = if request.Close then RETRY.Close else math.huge
		end
		if request.Release and not request.Close and attempts > 0 then
			if os.clock() - rec.LeftAt > DataConfig.LeaveSaveWindow then
				break -- окно вышло: новых попыток нет
			end
		end
		attempts += 1
		local status, info = saveOnce(rec, request.Release, attempts > 1)
		result = status
		if status ~= "failed" then
			break
		end
		local err = info and info.err
		if badValue(err) and not strictRetried then
			strictRetried = true
			rec.Strict = true
			local paths = if info and #info.issues > 0 then table.concat(info.issues, "; ") else "—"
			warn(
				`[DataService] сохранение игрока {rec.UserId} отклонено ({err}); поля: {paths} — повтор без незнакомых полей`
			)
			attempts -= 1 -- (повтор strict — не обычная попытка)
			continue
		end
		warn(
			`[DataService] сохранение игрока {rec.UserId} не удалось (попытка {attempts}): {err}`
		)
		if badValue(err) or not retryable(err) or attempts >= maxAttempts then
			break
		end
		task.wait(backoff(attempts))
	end
	rec.InFlight = false
	request.Result = result

	if rec.FinalPending and result ~= "lost" then
		-- Игрок ушёл, пока шла попытка обычного сохранения: последнее — следом.
		rec.FinalPending = false
		enqueue(newRequest("save", rec, true, rec.FinalClose))
		return
	end
	if result == "lost" then
		rec.FinalPending = false
		if request.Release or request.Test then
			release(rec)
			warn(
				`[DataService] замок игрока {rec.UserId} потерян — последнее сохранение не записано`
			)
		else
			warn(
				`[DataService] замок игрока {rec.UserId} забрал другой сервер — игра здесь закрыта`
			)
			kick(rec, TEXTS.Stolen)
		end
		return
	end
	if request.Release or result == "quiet" then
		release(rec) -- (и после неудачи: окно вышло, больше не пишем)
		return
	end
	if request.Test then
		return
	end
	rec.NextSave = os.clock() + DataConfig.AutoSave
	if result == "committed" and rec.State == "Ready" and rec.Dirty > rec.SnapshotSeq then
		requestSave(rec) -- ровно одно следующее: SaveSoon пришёл после снимка
	end
end

--------------------------------------------------------------------------------
-- Загрузка
--------------------------------------------------------------------------------

local function waitProbe()
	if probed then
		return
	end
	table.insert(probeWaiters, coroutine.running())
	coroutine.yield()
end

local function processLoad(request: Request)
	local rec = request.Rec
	waitProbe()
	if mode ~= "DataStore" then
		becomeMemory(rec)
		return
	end
	local failures, lockWaits = 0, 0
	local steal = false
	while true do
		if rec.State ~= "Loading" then
			return -- (уже Memory / Broken)
		end
		if rec.Left or closing then
			release(rec) -- попытки в пути нет: замок не взят
			return
		end
		waitGap(rec.UserId)
		if rec.State ~= "Loading" then
			return
		end
		if rec.Left or closing then
			release(rec)
			return
		end
		local lockedByOther, tooNew, corrupt = false, false, false
		local issues: { string } = {}
		local function transform(old: any): (any, any)
			lockedByOther, tooNew, corrupt = false, false, false
			issues = {}
			if old ~= nil and type(old) ~= "table" then
				corrupt = true
				return nil
			end
			local data = old or PlayerData.Template()
			local session = data.Session
			if type(session) == "table" and session.Id ~= rec.LoadId then
				local mine = session.Server == TOKEN and not liveRecordFor(rec.UserId, rec)
				local stale = os.time() - num(session.T, 0) >= DataConfig.LockStale
				if not (mine or stale or steal) then
					lockedByOther = true
					return nil
				end
			end
			if num(data.V, 1) > DataConfig.Version then
				tooNew = true
				return nil
			end
			local fixed, found = PlayerData.Sanitize(PlayerData.Migrate(PlayerData.Reconcile(data)))
			issues = found
			fixed.Session = lockFor(rec)
			if fixed.Created == 0 then
				fixed.Created = os.time()
			end
			return fixed, userIdsOf(rec)
		end
		local ok, value = attempt(rec, transform)
		if not ok then
			failures += 1
			warn(
				`[DataService] загрузка игрока {rec.UserId} не удалась (попытка {failures}): {value}`
			)
			if rec.Left or closing then
				release(rec)
				return
			end
			if not retryable(value) or failures >= RETRY.Load then
				kick(rec, TEXTS.LoadFailed)
				return
			end
			task.wait(backoff(failures))
			continue
		end
		if value == nil then
			if corrupt then
				warn(
					`[DataService] в ключе игрока {rec.UserId} не таблица — не трогаю, игрок не загружен`
				)
				kick(rec, TEXTS.LoadFailed)
				return
			elseif tooNew then
				kick(rec, TEXTS.TooNew)
				return
			elseif lockedByOther then
				lockWaits += 1
				if lockWaits >= DataConfig.LockWait.Tries and not steal then
					steal = true
					warn(
						`[DataService] сессия игрока {rec.UserId} занята другим сервером — забираю`
					)
				end
				task.wait(DataConfig.LockWait.Every)
				continue
			end
			failures += 1 -- (отмена без причины — как неудачная попытка)
			if failures >= RETRY.Load then
				kick(rec, TEXTS.LoadFailed)
				return
			end
			continue
		end
		-- Замок наш: живая таблица — то, что вернул UpdateAsync.
		if #issues > 0 then
			warn(
				`[DataService] данные игрока {rec.UserId} починены при загрузке: {table.concat(
					issues,
					"; "
				)}`
			)
		end
		rec.Data = value :: PlayerData.Data
		if rec.Left or closing then
			-- Игрок ушёл (сервер закрывается), пока шла попытка: только отпустить замок.
			rec.State = "Leaving"
			local status = "failed"
			for try = 1, RETRY.Close do
				waitGap(rec.UserId)
				status = saveOnce(rec, true, try > 1)
				if status ~= "failed" then
					break
				end
			end
			if status == "lost" then
				warn(
					`[DataService] замок игрока {rec.UserId} потерян, пока он уходил во время загрузки`
				)
			end
			release(rec)
			return
		end
		becomeReady(rec, value :: PlayerData.Data)
		return
	end
end

process = function(request: Request)
	if request.Kind == "load" then
		processLoad(request)
	else
		processSave(request)
	end
end

-- Ошибка в коде очереди (не DataStore): запись не должна зависнуть.
recover = function(request: Request)
	local rec = request.Rec
	rec.InFlight = false
	if rec.Queued == request then
		rec.Queued = nil
	end
	if request.Result == nil then
		request.Result = "failed"
	end
	if request.Kind == "load" then
		if rec.State == "Loading" then
			kick(rec, TEXTS.LoadFailed) -- (на шаблоне не играем: его нельзя сохранить)
		end
	elseif request.Release or rec.State == "Leaving" then
		release(rec)
	end
end

--------------------------------------------------------------------------------
-- Игроки, автосохранение, закрытие
--------------------------------------------------------------------------------

local function newRecord(player: Player): Record
	return {
		Player = player,
		UserId = player.UserId,
		Key = PlayerData.KeyFor(player.UserId),
		State = "Loading",
		LoadId = HttpService:GenerateGUID(false),
		Data = nil,
		Announced = false,
		Left = false,
		LeftAt = 0,
		Dirty = 0,
		SnapshotSeq = 0,
		Committed = 0,
		NextSave = math.huge,
		Postponed = 0,
		Queued = nil,
		InFlight = false,
		FinalPending = false,
		FinalClose = false,
		Strict = false,
		Waiters = {},
		Warned = {},
	}
end

local function onPlayerAdded(player: Player)
	if records[player] or closing then
		return -- (сервер закрывается: ни загрузки, ни замка)
	end
	local rec = newRecord(player)
	records[player] = rec
	player:SetAttribute("DataMode", "Loading")
	if probed and mode ~= "DataStore" then
		becomeMemory(rec)
		return
	end
	pending[rec] = true
	enqueue(newRequest("load", rec, false, false))
end

-- Последнее сохранение с отпусканием (ждущее в очереди автосохранение им и становится).
local function startFinal(rec: Record, close: boolean)
	pending[rec] = true
	local queued = rec.Queued
	if queued then
		queued.Release = true
		queued.Close = close
		rec.Queued = nil
	elseif rec.InFlight then
		-- Обычное сохранение в пути: до своей попытки оно само станет последним (иначе — следом).
		rec.FinalPending = true
		rec.FinalClose = close
	else
		enqueue(newRequest("save", rec, true, close))
	end
end

local function onPlayerRemoving(player: Player)
	local rec = records[player]
	if not rec then
		return
	end
	if not rec.Left then
		rec.Left = true
		rec.LeftAt = os.clock()
	end
	wakeWaiters(rec, nil)
	if rec.State == "Memory" then
		release(rec)
	elseif rec.State == "Ready" then
		rec.State = "Leaving"
		startFinal(rec, false)
	end
	-- Loading: загрузка сама увидит Left; Leaving: последнее сохранение уже идёт.
end

local function lowBudget(): boolean
	local ok, budget = pcall(function(): number
		return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.UpdateAsync)
	end)
	return ok and type(budget) == "number" and budget < DataConfig.BudgetMin
end

local function schedulerStep()
	local now = os.clock()
	for _, rec in records do
		if rec.State == "Ready" and not rec.Queued and not rec.InFlight and now >= rec.NextSave then
			if lowBudget() and rec.Postponed + DataConfig.BudgetDelay <= DataConfig.LockStale / 3 then
				rec.Postponed += DataConfig.BudgetDelay
				rec.NextSave = now + DataConfig.BudgetDelay
			else
				rec.Postponed = 0
				requestSave(rec)
			end
		end
	end
	-- Пустые очереди и старые отметки — когда пауза прошла.
	for userId, queue in queues do
		local last = lastRequest[userId]
		if not queue.Running and #queue.Items == 0 and (last == nil or now - last >= GAP) then
			queues[userId] = nil
		end
	end
	for userId, last in lastRequest do
		if queues[userId] == nil and now - last >= GAP then
			lastRequest[userId] = nil
		end
	end
end

local function schedulerLoop()
	while true do
		task.wait(1)
		local ok, err = xpcall(function(): any
			schedulerStep()
			return nil
		end, trace)
		if not ok then
			warn(`[DataService] ❌ ошибка автосохранения: {err}`)
		end
	end
end

local function finishProbe()
	if probed then
		return
	end
	probed = true
	local waiters = probeWaiters
	probeWaiters = {}
	for _, thread in waiters do
		task.spawn(thread)
	end
end

local function probe()
	task.delay(DataConfig.ProbeTimeout, function()
		if not probed then
			warn(
				`[DataService] проверка DataStore не ответила за {DataConfig.ProbeTimeout} с — работаю как обычно`
			)
			finishProbe()
		end
	end)
	local ok, err = pcall(function()
		local created = DataStoreService:GetDataStore(DataService.StoreName)
		store = created
		created:GetAsync("__probe")
	end)
	if probed then
		return -- (ответ пришёл после тайм-аута)
	end
	if not ok then
		if RunService:IsStudio() and accessError(err) then
			mode = "Memory"
			warn(TEXTS.MemoryWarn)
		else
			warn(`[DataService] проверка DataStore не удалась: {err}`)
		end
	end
	finishProbe()
end

local function onClose()
	closing = true
	for _, rec in table.clone(records) do
		if not rec.Left then
			rec.Left = true
			rec.LeftAt = os.clock()
		end
		if rec.State == "Ready" then
			rec.State = "Leaving"
			startFinal(rec, true)
		end
	end
	if mode ~= "DataStore" then
		return
	end
	local started = os.clock()
	while next(pending) and os.clock() - started < DataConfig.CloseBudget do
		task.wait()
	end
end

local function becomeBroken(err: any)
	mode = "Broken"
	warn(
		`[DataService] ❌ внутренняя ошибка запуска — режим Broken: игра идёт, прогресс НЕ сохраняется.\n{err}`
	)
	finishProbe()
	for _, rec in table.clone(records) do
		becomeMemory(rec)
	end
end

local function boot()
	assert(
		DataConfig.AutoSave < DataConfig.LockStale,
		"[DataService] AutoSave должен быть меньше LockStale"
	)
	assert(
		DataConfig.LeaveSaveWindow + DataConfig.MinWriteGap < DataConfig.LockWait.Tries * DataConfig.LockWait.Every,
		"[DataService] LeaveSaveWindow + MinWriteGap должно быть меньше LockWait.Tries × LockWait.Every"
	)
	task.spawn(schedulerLoop)
	task.spawn(probe)
end

--------------------------------------------------------------------------------
-- Публичное API
--------------------------------------------------------------------------------

function DataService:Get(player: Player): PlayerData.Data?
	local rec = records[player]
	if rec and (rec.State == "Ready" or rec.State == "Memory" or rec.State == "Leaving") then
		return rec.Data
	end
	return nil
end

function DataService:IsLoaded(player: Player): boolean
	local rec = records[player]
	return rec ~= nil and (rec.State == "Ready" or rec.State == "Memory")
end

function DataService:CanWrite(player: Player): boolean
	local rec = records[player]
	return rec ~= nil and (rec.State == "Ready" or rec.State == "Memory")
end

function DataService:WaitLoaded(player: Player, timeout: number?): PlayerData.Data?
	local rec = records[player]
	if not rec then
		return nil
	end
	if rec.State == "Ready" or rec.State == "Memory" then
		return rec.Data
	end
	if rec.State ~= "Loading" or rec.Left then
		return nil
	end
	local waiter: Waiter = { Thread = coroutine.running(), Timer = nil }
	table.insert(rec.Waiters, waiter)
	if timeout then
		waiter.Timer = task.delay(timeout, function()
			local index = table.find(rec.Waiters, waiter)
			if index then
				table.remove(rec.Waiters, index)
				task.spawn(waiter.Thread, nil)
			end
		end)
	end
	return coroutine.yield()
end

function DataService:Mode(): Mode
	return mode
end

function DataService:SaveSoon(player: Player): number
	local rec = records[player]
	if not rec then
		return 0
	end
	if rec.State ~= "Ready" then
		return rec.Dirty
	end
	rec.Dirty += 1
	requestSave(rec)
	return rec.Dirty
end

function DataService:CommittedSeq(player: Player): number
	local rec = records[player]
	return if rec then rec.Committed else 0
end

function DataService:OnSerialize(fn: SerializeHook)
	serializeHook = fn
end

-- Размеры внутренних таблиц (тесты: после выхода всех игроков и паузы ключа — нули).
function DataService._debugSizes(): { [string]: number }
	return {
		Records = count(records),
		Queues = count(queues),
		LastRequest = count(lastRequest),
		Pending = count(pending),
	}
end

function DataService._recordFor(player: Player): any
	return records[player]
end

-- Тесты: обычное сохранение этой записи через очередь её ключа (даже старой, отпущенной);
-- ждёт и возвращает итог.
function DataService._saveRecordForTest(rec: any): SaveResult?
	local request = newRequest("save", rec :: Record, false, false)
	request.Test = true
	request.Waiter = coroutine.running()
	enqueue(request)
	if request.Done then
		return request.Result
	end
	return coroutine.yield()
end

--------------------------------------------------------------------------------
-- Жизненный цикл сервиса
--------------------------------------------------------------------------------

function DataService:Init()
	TOKEN = HttpService:GenerateGUID(false)
	DataService.Token = TOKEN
end

function DataService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	game:BindToClose(onClose)
	local ok, err = xpcall(function(): any
		boot()
		return nil
	end, trace)
	if not ok then
		becomeBroken(err)
	end
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return DataService
