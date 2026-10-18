--!strict
--[[
	DataConfig — сохранение прогресса игрока (Этап 3, DataService + PlayerData).

	Один ключ DataStore на игрока: хранилище StoreName (в Studio — StoreName .. StudioSuffix,
	чтобы тесты в Studio не трогали живые данные), ключ KeyPrefix .. UserId («Player_123»); версия
	схемы Version лежит внутри значения (поле V), поэтому миграциям не нужно новое хранилище.
	Пишется только через UpdateAsync, внутри значения — «замок» сессии (Session): другой сервер не
	перезапишет данные, пока этот игрок играет здесь. Подробно — шапка DataService и
	docs/stage3_design.md, §2.

	Время — в секундах; каждое число — на своей строке: тесты подменяют его в тексте модуля
	(boot с patches), чтобы не ждать минуту автосохранения.
	Проверки при старте сервера (DataService; tests/stage3_rules проверяет их тоже):
	  AutoSave < LockStale — живой замок никогда не выглядит брошенным;
	  LeaveSaveWindow + MinWriteGap < LockWait.Tries × LockWait.Every — сохранение при выходе
	  успевает раньше, чем другой сервер решит забрать замок.
	Модуль «чистый» (без require).
]]

local DataConfig = {
	StoreName = "PlayerData",
	StudioSuffix = "_Studio",
	KeyPrefix = "Player_",
	Version = 1, -- версия схемы PlayerData (поле V); данные новее — игрока просят перезайти
	-- Первая настоящая миграция (v2): старое значение один раз копируется сюда
	-- (ключ «Player_<id>_v<старая версия>», SetAsync) — правило в шапке DataService.
	BackupStore = "PlayerData_Backup",

	AutoSave = 60, -- автосохранение каждого игрока раз в столько секунд
	MinWriteGap = 6, -- не чаще одной записи ключа за столько секунд (лимит Roblox) …
	GapEpsilon = 0.05, -- … плюс запас (часы симулятора — сумма шагов по 1/60 с)
	LockStale = 150, -- замок старше стольких секунд — брошен (2.5 × AutoSave), его можно забрать
	-- Замок занят другим сервером: ждём Every секунд, Tries раз (≈ 24 с), потом забираем.
	LockWait = {
		Tries = 4,
		Every = 6,
	},
	LeaveSaveWindow = 15, -- игрок вышел: последнее сохранение повторяется не дольше стольких секунд
	-- Сколько раз пробовать: загрузку, сохранение, сохранение при закрытии сервера; пауза между
	-- попытками — min(Max, Base × 2^(n−1)) × (1 + 0.5 × случайное) секунд.
	Retry = {
		Load = 5,
		Save = 2,
		Close = 2,
		Base = 1,
		Max = 8,
	},
	CloseBudget = 25, -- BindToClose ждёт сохранения не дольше стольких секунд (Roblox даёт 30)
	ProbeTimeout = 5, -- проверка доступа к DataStore при старте — не дольше, с
	-- Мало запросов в запасе (GetRequestBudgetForRequestType < BudgetMin) — автосохранение
	-- откладывается на BudgetDelay секунд (всего не дольше LockStale / 3 за цикл).
	BudgetMin = 5,
	BudgetDelay = 10,

	-- PlayerData.Serialize: строки известных полей не длиннее MaxString знаков, Origin рыбы
	-- (Этап 4, «<UserId жертвы>:<uid>») — не длиннее OriginMax; незнакомые поля (от сервера
	-- новее) — только JSON-совместимые и не глубже MaxDepth уровней таблиц.
	Limits = {
		MaxString = 64,
		OriginMax = 24,
		MaxDepth = 4,
	},

	Texts = {
		-- Кик, если данные не загрузились (≈ 30 с попыток): ничего не обещаем.
		LoadFailed = "Не получилось загрузить твой прогресс — серверы Roblox заняты. Зайди ещё раз через минуту!",
		-- Кик, если данные записаны сервером новее этого (V > Version).
		TooNew = "Игра обновилась — перезайди, чтобы продолжить.",
		-- Кик, если замок сессии забрал другой сервер (игрок зашёл в игру ещё раз).
		Stolen = "Ты зашёл в игру на другом сервере — здесь эта игра закрыта.",
		-- Studio без доступа к API: одно предупреждение в Output при старте …
		MemoryWarn = "[DataService] DataStore недоступен — прогресс НЕ сохраняется. Studio: опубликуй место (File → Publish to Roblox) и включи Game Settings → Security → Enable Studio Access to API Services.",
		-- … и одно уведомление в игре (после баннера базы).
		MemoryToast = "💾 Studio: прогресс не сохраняется",
	},
}

return DataConfig
