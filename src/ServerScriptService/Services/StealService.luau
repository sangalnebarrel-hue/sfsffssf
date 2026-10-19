--!strict
--[[
	StealService — кража (Этап 4): кнопки «Украсть» у витрин, удержание, вынос рыбы за ограду,
	касание хозяина, проверка скорости, собака, тревога жертве, ожидания и честные лимиты.
	Числа и тексты — StealConfig (защиты — DefenceConfig), проверки начала — Shared/TheftChecks,
	переход рыбы между садками — TankService:StealFish (только он; здесь — ни одной записи данных).
	Подробно — docs/stage4_design.md, §1, §4.2–§4.9.

	Что делает:
	  1. Init: у каждой витрины каждой базы (Tank.Slots.Slot_K.Pedestal.PromptAttachment) —
	     ProximityPrompt "StealPrompt": ActionText «Украсть», HoldDuration по замку хозяина,
	     MaxActivationDistance StealConfig.Prompt.MaxDistance (сервер больше его не пишет: это
	     свойство — фильтра клиента, BE-14), RequiresLineOfSight = false, Exclusivity
	     OnePerButton, E / ButtonX, Enabled = false. Enabled = «садок подключён и в витрине рыба»
	     (TankService.SlotChanged / Mounted / Unmounted; больше ничего, BE-15), ObjectText «Окунь ·
	     +$4/с» (пишется при изменении), HoldDuration = DefenceService:HoldTime(хозяин) — кроме
	     кнопки, которую держат (получит в конце кражи, BE-18).
	  2. PromptButtonHoldBegan → проверки Shared/TheftChecks по порядку: сначала строки 1–2 (не
	     кнопка кражи, повтор той же кнопки — молча, без жетона), потом жетон лимита (StartBurst /
	     StartRate; пусто — молча) и полный view. Отказ — StealEvent "Denied" { Reason, Text, Quiet?,
	     BaseIndex, Slot, Until? } (тот же отказ меньше DeniedEvery с назад — Quiet; Until —
	     серверное время, когда отказ кончится, у причин с ожиданием). Начало:
	     TankService:SetSteal(…, "hold", { By, End }), первая уборка кражи — Lib/Speed.ClearAll,
	     атрибуты базы Thief / AlarmState = "theft", собака просыпается (Lib/DogBrain), игрока
	     Stealing = "hold" (последним), StealEvent "Hold" вору и "Alert" жертве, наблюдатель.
	     Защита вора гаснет (DefenceService:EndProtection(вор, "stealing")) не в начале, а когда
	     удержание переживёт окно тапа (tapWindow: max(QuietSavedUnder, Hold.NoReply, пинг +
	     NoReplySlack) + NoReplySlack, не дольше Need − Tolerance; шаг наблюдателя, самое позднее — в
	     начале выноса): случайный тап новичка его защиту не гасит (UX-01). Время удержания считает
	     сервер: Need = HoldTime при начале; Triggered раньше Need × LateShare — "early" (строка в
	     Output, без кика; обычная ступень FailCooldown, UX-04); не раньше Need — вынос (раньше —
	     HoldBegan опоздал на медленной связи: по task.delay к T0 + Need, наблюдатель всё это время
	     проверяет жертву, радиус, щит, касание); отпустил — "released" / "far" / "died" по
	     состоянию в этот миг (BE-13; отпустил к концу — ждём его Triggered Grace с); нет Triggered
	     к Need + Deadline — "deadline". Triggered без кражи — молча (одна строка в Output не чаще
	     раза в 10 с).
	  3. Удержание кончилось → вынос: SetSteal(…, "carry", { End }), FishingService:DropHeldFish(вор),
	     Lib/HeldRig.Build(…, "StolenFish") (+ Owner = UserId хозяина), Lib/Speed "Carry",
	     Lib/CarryGuard (бюджет с Carry.Speed.Start, не полный: A2-01), Stealing = "carry", StealEvent "Carry" и "Alert" { Phase
	     = "carry" } (ЩИТ жертвы работает и сейчас: DC-01). StealConfig.Carry.Enabled = false —
	     рыба переходит сразу в конце удержания (без выноса и StolenFish; §9 R1).
	  4. Наблюдатель — ОДИН цикл task.wait(StealConfig.Tick), только пока идёт хоть одна кража
	     или бежит собака (сам кончается — без покадровой работы в простое); шаг каждой кражи — в
	     xpcall (warn не чаще раза в 30 с), ничего не ждёт. Удержание: жив, радиус (Prompt.MaxDistance
	     + Slack, 3D), хозяин пишет данные, защита базы ("shield"), касание хозяина (Tag.Range,
	     по горизонтали), Need + Deadline. Вынос: жив, хозяин, защита (щит вернёт рыбу), касание,
	     Carry.Timeout, бюджет скорости (Lib/CarryGuard по горизонтальному пути HRP; "speed"), выход
	     за ограду (StealRules.InPlot + ExitMargin) на тике с бюджетом ≥ 0 → TankService:StealFish
	     (nil → рыба вернулась: "full" / "busy"). Собаки (Lib/DogBrain.Step; кусает — Lib/Speed
	     "Dog" × Dog.Slow до SlowLinger, только пока кража на этой базе жива и её вор — цель).
	  5. Удачно: DefenceService:GiveAfterTheft(жертва), вор ждёт ThiefCooldown, StealEvent "Done" вору
	     и "Lost" жертве (Until / Kind — её защита теперь) — в xpcall: рыба уже у вора, и конец кражи
	     будет, что бы там ни упало (A2-02; ошибка шага наблюдателя после StealFish — тоже только
	     конец). Конец кражи: Ended — первым (второй конец ничего не делает, отложенные — проверяют
	     номер кражи), записи по вору и базе сняты (до уборки: упавшая уборка не оставит цикл),
	     Lib/Speed.ClearAll и уборка кражи (StolenFish), кнопка получает HoldDuration, Thief снят,
	     AlarmState — через Alarm.Linger, собака — домой, Stealing = nil (последним). Срыв: рыба
	     отпущена (SetSteal nil) — осталась или вернулась; ожидания вора: своя вина ("released",
	     "far", "died", "timeout", "speed", "deadline", "tag", "early") — FailCooldown по счёту
	     срывов за FailWindow; на одной базе Limits.BaseFails срывов за FailWindow — она закрыта для
	     него ещё BaseWait с ("wary", UX-03); пойман ("tag") — ещё TagCooldown на этой базе
	     ("tagged"); "released" в удержании короче окна тапа (тап или кольцо погасил сам клиент,
	     NoReply; защита вора ещё не погасла) — не срыв: без ожидания и счёта, Limits.FreeTaps раз за
	     FailWindow (дальше — как срыв: спам); щит хозяина — без ожидания, но эта база закрыта для
	     него до конца защиты и ещё ShieldWait ("shielded": щит не «выманить», UX-02); ушёл хозяин /
	     садок полон / ушёл вор — без ожидания. Закрытые базы — карта tagged (пара вор–хозяин, вид
	     «почему» — для отказа: строка «wait» TheftChecks, TagKind). StealEvent "Cancel" вору
	     { Reason, Text, Phase, BaseUntil?, BaseReason? } (база хозяина закрыта для него до
	     BaseUntil — серверное время — по причине BaseReason: клиент прячет её кнопки), "Saved"
	     жертве (Quiet — удержание, которое кончил не хозяин: короче QuietSavedUnder, прощённый тап
	     (DATA-01) или все его тревоги были тихими (UX-03); его "tag" и "shield" — всегда громко,
	     A2-04; вынос — всегда громко; жертве, которая ушла, — ничего).
	  6. Тревога жертве: "Alert" при начале удержания и выноса; ГРОМКО — не чаще раза в
	     AlertCoalesce с на пару (вор, жертва) от прошлой громкой (кража помнит Loud), остальные
	     Quiet. Никому другому — ничего (кража видна только двоим).
	  7. «ДОМОЙ» (BaseService:SetHomeGuard): с рыбой на голове — отказ «Сначала унеси рыбу за
	     ограду!» (кулдаун не тратится); у хозяина идёт кража — на площадку лицом во двор (+Z базы).
	  8. DefenceService.SetStealProbe(IsStealing) — в Init: защита спрашивает, не крадёт ли
	     игрок сам, не требуя этот модуль (иначе цикл require). DefenceService.ProtectionChanged —
	     база стала под защитой: удержание сорвано, несомая рыба — домой ("shield"); LockChanged —
	     HoldDuration кнопок базы (кроме той, что держат).
	  9. TankService.Unmounted: кража базы сорвана ("victim"), собака — DogBrain.Reset, кнопки —
	     Enabled false, ObjectText "", HoldDuration Lock.BaseHold, атрибуты Thief / AlarmState
	     сняты. Выход игрока: его кража — "left", кража у него — "victim"; лимит, отказы,
	     Lib/Speed.Forget.
	Записи — по самому Player с проверкой «это всё ещё она»; соединения — одно на
	ProximityPromptService (три события), ни одного на кнопку; карты по UserId (cooldowns, fails,
	taps, tagged, baseFails, alertCoalesce) — с границей по времени, чистятся при записи, в
	PlayerRemoving и в _debugSizes; ожидание переживает перезаход, и TankService.Mounted возвращает
	новому Player атрибут StealCooldownUntil (A2-03). Часы внутри — os.clock; в атрибуты — серверное время
	(TankRules.AttrTime).
	Каждый вызов другого сервиса — за type(...) == "function".

	Атрибуты (RemoteNames, «Кража и защита»): Player — Stealing, StealCooldownUntil (Slowed пишет
	Lib/Speed); база — Thief, AlarmState ("theft"); персонаж — модель StolenFish; Dog — DogState,
	DogPos, DogTarget (Lib/DogBrain).
	Remote: StealEvent (сервер → клиент; протокол — шапка RemoteNames).

	API:
	  StealService:IsStealing(player) -> "hold" | "carry" | nil
	  StealService:TheftOn(base) -> { Thief, Victim, Slot, Phase }?   -- base: BaseService.Base или модель Base_N
	  StealService:Cancel(player, reason)          -- BindToClose и тесты
	  StealService.TheftStarted, StealService.TheftEnded   -- Signal (thief, victim, result):
	                                               -- result = "hold" (начало) | "credited" | причина
	  StealService._debugSizes()                   -- Thefts, Buckets + Cooldowns, Fails, Taps, Tags, BaseFails,
	                                               -- Alerts, Denied, Dogs, Watcher (1 — цикл идёт)
]]

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local DefenceConfig = require(Shared.Config.DefenceConfig)
local StealConfig = require(Shared.Config.StealConfig)
local TankConfig = require(Shared.Config.TankConfig)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local StealRules = require(Shared.StealRules)
local TankRules = require(Shared.TankRules)
local TextUtil = require(Shared.TextUtil)
local TheftChecks = require(Shared.TheftChecks)
local Trove = require(Shared.Util.Trove)
local Bucket = require(ServerScriptService.Lib.Bucket)
local CarryGuard = require(ServerScriptService.Lib.CarryGuard)
local DogBrain = require(ServerScriptService.Lib.DogBrain)
local HeldRig = require(ServerScriptService.Lib.HeldRig)
local Speed = require(ServerScriptService.Lib.Speed)
local BaseService = require(ServerScriptService.Services.BaseService)
local DataService = require(ServerScriptService.Services.DataService)
local DefenceService = require(ServerScriptService.Services.DefenceService)
local FishingService = require(ServerScriptService.Services.FishingService)
local TankService = require(ServerScriptService.Services.TankService)

type Base = BaseService.Base

export type TheftView = {
	Thief: Player,
	Victim: Player,
	Slot: number,
	Phase: "hold" | "carry",
}

type PromptInfo = {
	Base: Base,
	Slot: number,
	Attachment: Attachment,
	Held: boolean, -- её держит кража: HoldDuration не трогать до конца (BE-18)
}

type Theft = {
	Token: number,
	Thief: Player,
	Victim: Player,
	Base: Base,
	Slot: number,
	Uid: string,
	Fish: TankService.SlotView,
	Prompt: ProximityPrompt,
	Info: PromptInfo,
	Character: Model,
	Phase: "hold" | "carry",
	T0: number, -- os.clock() начала удержания
	Need: number, -- секунд держать (по замку в миг начала)
	HoldEnd: number, -- серверное время конца удержания (атрибут)
	CarryEnd: number?, -- серверное время конца выноса (атрибут)
	CarryUntil: number, -- os.clock() конца выноса
	Finishing: boolean, -- Triggered пришёл: удержание кончается
	Committed: boolean, -- удержание пережило окно тапа: защита вора снята (UX-01)
	Loud: boolean, -- хоть одна тревога этой кражи жертве — громкая (не Quiet)
	Credited: boolean, -- рыба уже вора (StealFish)
	Ended: boolean,
	Guard: CarryGuard.Guard?,
	LastPos: Vector3?,
	Trove: Trove.Trove,
}

local PROMPT = StealConfig.Prompt
local HOLD = StealConfig.Hold
local CARRY = StealConfig.Carry
local LIMITS = StealConfig.Limits
local TEXTS = StealConfig.Texts
local DOG = DefenceConfig.Dog
local BASE_HOLD = DefenceConfig.Lock.BaseHold
local WARN_EVERY = 30 -- секунд между предупреждениями наблюдателя
local LOG_EVERY = 10 -- секунд между строками «подозрительно» в Output
-- Срыв по своей вине — ожидание (FailCooldown); остальные причины — без ожидания.
local OWN_FAULT = {
	released = true,
	far = true,
	died = true,
	timeout = true,
	speed = true,
	deadline = true,
	tag = true,
	early = true,
}
-- Конец, который сделала защита хозяина: «Saved» ему — всегда громко (A2-04).
local OWNER_SAVE = {
	tag = true,
	shield = true,
}

local StealService = {
	TheftStarted = Signal.new(), -- (thief, victim, result)
	TheftEnded = Signal.new(), -- (thief, victim, result)
}

local promptInfo: { [ProximityPrompt]: PromptInfo } = {}
local prompts: { [Base]: { ProximityPrompt } } = {}
local byThief: { [Player]: Theft } = {}
local byBase: { [Base]: Theft } = {}
local lastDenied: { [Player]: { Reason: string, At: number } } = {}
local cooldowns: { [number]: number } = {} -- UserId вора → os.clock() конца ожидания
local fails: { [number]: { number } } = {} -- UserId вора → срывы по своей вине (окно FailWindow)
local taps: { [number]: { number } } = {} -- UserId вора → прощённые короткие «отпустил» (окно FailWindow)
-- "вор:хозяин" (UserId) → база закрыта для вора до Until (os.clock): Kind "tagged" (поймал, TagCooldown),
-- "shielded" (щит против его кражи: до конца защиты + ShieldWait), "wary" (BaseFails срывов: BaseWait)
local tagged: { [string]: { Until: number, Kind: string } } = {}
local baseFails: { [string]: { number } } = {} -- "вор:хозяин" → срывы вора по своей вине на этой базе (FailWindow)
local alerts: { [string]: number } = {} -- "вор:жертва" (UserId) → os.clock() последней громкой тревоги
local dogs: { [Base]: boolean } = {} -- базы, чья собака не спит (их тикает наблюдатель)
local alarmTokens: { [Base]: number } = {} -- лампа после кражи (Alarm.Linger): номер последней
local startBucket = Bucket.new(LIMITS.StartBurst, LIMITS.StartRate)
local stealEvent: RemoteEvent? = nil
local nextToken = 0
local watching = false
local lastWarn = -math.huge
local lastLog = -math.huge

--------------------------------------------------------------------------------
-- Помощники
--------------------------------------------------------------------------------

local function now(): number
	return Workspace:GetServerTimeNow()
end

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

local function setAttr(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

local function send(player: Player, kind: string, data: { [string]: any })
	local remote = stealEvent
	if remote and player.Parent == Players then
		remote:FireClient(player, kind, data)
	end
end

-- Строка «подозрительно» в Output (не warn: это не ошибка сервера), не чаще раза в LOG_EVERY с.
local function suspicion(text: string)
	if os.clock() - lastLog >= LOG_EVERY then
		lastLog = os.clock()
		print(`[StealService] {text}`)
	end
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

local function flatten(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function pairKey(a: Player, b: Player): string
	return `{a.UserId}:{b.UserId}`
end

-- Карты с границей по времени (BE-26): чистятся при записи, в PlayerRemoving и в _debugSizes.
local function pruneMaps()
	local t = os.clock()
	for userId, untilT in table.clone(cooldowns) do
		if untilT <= t then
			cooldowns[userId] = nil
		end
	end
	for userId, list in table.clone(fails) do
		local kept = {}
		for _, at in list do
			if t - at < LIMITS.FailWindow then
				table.insert(kept, at)
			end
		end
		fails[userId] = if #kept > 0 then kept else nil
	end
	for userId, list in table.clone(taps) do
		local kept = {}
		for _, at in list do
			if t - at < LIMITS.FailWindow then
				table.insert(kept, at)
			end
		end
		taps[userId] = if #kept > 0 then kept else nil
	end
	for key, closed in table.clone(tagged) do
		if closed.Until <= t then
			tagged[key] = nil
		end
	end
	for key, list in table.clone(baseFails) do
		local kept = {}
		for _, at in list do
			if t - at < LIMITS.FailWindow then
				table.insert(kept, at)
			end
		end
		baseFails[key] = if #kept > 0 then kept else nil
	end
	for key, at in table.clone(alerts) do
		if t - at >= LIMITS.AlertCoalesce then
			alerts[key] = nil
		end
	end
end

local function current(theft: Theft): boolean
	return not theft.Ended and not theft.Credited and byThief[theft.Thief] == theft
end

local function alive(theft: Theft): boolean
	local player = theft.Thief
	local character = theft.Character
	if player.Character ~= character or character.Parent == nil then
		return false
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and rootOf(player) ~= nil
end

-- Вор ждёт: после удачи или срывов (os.clock, атрибут — серверное время).
local function setCooldown(player: Player, seconds: number)
	local t = os.clock()
	local untilT = math.max(cooldowns[player.UserId] or 0, t + seconds)
	cooldowns[player.UserId] = untilT
	if player.Parent == Players then
		setAttr(player, "StealCooldownUntil", TankRules.AttrTime(now() + (untilT - t)))
	end
end

-- Ожидание — по UserId и переживает перезаход, а атрибут был у прежнего Player: вернуть его новому,
-- иначе фильтр клиента (строка 10, Client) покажет «Украсть», а сервер ответит "cooldown" (A2-03).
local function restoreCooldown(player: Player)
	local t = os.clock()
	local untilT = cooldowns[player.UserId]
	if untilT and untilT > t and player.Parent == Players then
		setAttr(player, "StealCooldownUntil", TankRules.AttrTime(now() + (untilT - t)))
	end
end

--------------------------------------------------------------------------------
-- Кнопки «Украсть»
--------------------------------------------------------------------------------

local function refreshPrompt(base: Base, index: number)
	local list = prompts[base]
	local prompt = list and list[index]
	local info = prompt and promptInfo[prompt]
	if not prompt or not info then
		return
	end
	local owner, view = nil, nil
	if type(TankService.SlotFish) == "function" then
		owner, view = TankService:SlotFish(base, index)
	end
	local enabled = owner ~= nil and view ~= nil
	if prompt.Enabled ~= enabled then
		prompt.Enabled = enabled
	end
	local text = if view
		then TextUtil.fill(TEXTS.PromptObject, { short = view.ShortName, rate = TankRules.FormatRate(view.Income10) })
		else ""
	if prompt.ObjectText ~= text then
		prompt.ObjectText = text
	end
	if not info.Held then
		local hold = if owner then DefenceService:HoldTime(owner) else BASE_HOLD
		if prompt.HoldDuration ~= hold then
			prompt.HoldDuration = hold
		end
	end
end

local function refreshBase(base: Base)
	for index in prompts[base] or {} do
		refreshPrompt(base, index)
	end
end

local function resetPrompts(base: Base)
	for _, prompt in prompts[base] or {} do
		local info = promptInfo[prompt]
		if info then
			info.Held = false
		end
		prompt.Enabled = false
		prompt.ObjectText = ""
		prompt.HoldDuration = BASE_HOLD
	end
end

--------------------------------------------------------------------------------
-- Конец кражи
--------------------------------------------------------------------------------

local function finish(theft: Theft, result: string)
	if theft.Ended then
		return
	end
	theft.Ended = true
	local thief, victim, base = theft.Thief, theft.Victim, theft.Base
	-- Записи — сразу (только таблицы): даже если уборка ниже упадёт, наблюдатель её больше не
	-- увидит и кончится сам (A2-02).
	if byThief[thief] == theft then
		byThief[thief] = nil
	end
	if byBase[base] == theft then
		byBase[base] = nil
	end
	Speed.ClearAll(thief) -- (первая уборка: вор никогда не остаётся медленным, BE-10)
	theft.Trove:Destroy()
	theft.Info.Held = false
	refreshPrompt(base, theft.Slot)
	local model = base.Model
	setAttr(model, "Thief", nil)
	local token = theft.Token
	alarmTokens[base] = token
	task.delay(StealConfig.Alarm.Linger, function()
		if alarmTokens[base] == token and byBase[base] == nil then
			alarmTokens[base] = nil
			if model:GetAttribute("AlarmState") == "theft" then
				model:SetAttribute("AlarmState", nil)
			end
		end
	end)
	DogBrain.Return(base)
	if thief.Parent == Players then
		setAttr(thief, "Stealing", nil) -- (последним)
	end
	StealService.TheftEnded:Fire(thief, victim, result)
end

local function savedText(reason: string): string
	local saved = TEXTS.Result.Saved
	if reason == "tag" or reason == "shield" then
		return saved[reason]
	elseif reason == "left" then
		return saved.left
	end
	return saved.failed
end

-- Пинг вора (туда и обратно, с); нет — 0.
local function pingOf(player: Player): number
	local ok, ping = pcall(function(): any
		return player:GetNetworkPing()
	end)
	return if ok and type(ping) == "number" and ping == ping and ping >= 0 and ping < math.huge then ping else 0
end

-- Окно тапа (C-20, C-28): сколько клиент ждёт ответа — max(QuietSavedUnder, NoReply, пинг +
-- NoReplySlack): короткий тап или кольцо погасил сам клиент, не дождавшись "Hold", — плюс
-- NoReplySlack на разброс связи; не дольше need − Tolerance. Удержание короче него — ещё не
-- попытка: «отпустил» в нём прощается (freeTap), и защита вора в нём не гаснет (UX-01).
local function tapWindow(theft: Theft): number
	local waitFor = math.max(LIMITS.QuietSavedUnder, HOLD.NoReply, pingOf(theft.Thief) + HOLD.NoReplySlack)
	return math.min(waitFor + HOLD.NoReplySlack, theft.Need - HOLD.Tolerance)
end

-- Удержание пережило окно тапа — это попытка: защита вора гаснет (DefenceService, «Кража погасила
-- твою защиту»). Не в начале удержания: случайный тап новичка не стоит ему защиты (UX-01); до
-- выноса — всегда (toCarry): под защитой ничего не украсть.
local function commit(theft: Theft)
	if theft.Committed then
		return
	end
	theft.Committed = true
	DefenceService:EndProtection(theft.Thief, "stealing")
end

-- «Отпустил» почти сразу — не срыв по своей вине (C-20, C-28, C-34): удержание held (с) короче
-- окна тапа, и защита вора ещё не погасла. Прощается Limits.FreeTaps раз за FailWindow, дальше —
-- обычный срыв (спам).
local function freeTap(theft: Theft, reason: string, held: number): boolean
	if reason ~= "released" or theft.Phase ~= "hold" or theft.Committed or held >= tapWindow(theft) then
		return false
	end
	local userId = theft.Thief.UserId
	local list = taps[userId] or {}
	if #list >= LIMITS.FreeTaps then
		return false
	end
	table.insert(list, os.clock())
	taps[userId] = list
	return true
end

-- База закрыта для вора ещё seconds с (почему — kind); раньше кончавшееся ожидание продлевается,
-- более долгое остаётся.
local function closeBase(key: string, seconds: number, kind: string)
	local untilT = os.clock() + seconds
	local old = tagged[key]
	if not old or untilT >= old.Until then
		tagged[key] = { Until = untilT, Kind = kind }
	end
end

-- Срыв: рыба отпущена (осталась в витрине или вернулась), ожидания вора, ответы, конец. at —
-- os.clock() мига, когда он отпустил (по умолчанию — сейчас).
local function cancel(theft: Theft, reason: string, at: number?)
	if theft.Ended or theft.Credited then
		return
	end
	local thief, victim = theft.Thief, theft.Victim
	local held = (at or os.clock()) - theft.T0
	local key = pairKey(thief, victim)
	TankService:SetSteal(victim, theft.Uid, theft.Token, nil)
	local own = OWN_FAULT[reason] == true
	if own then
		pruneMaps()
	end
	local free = own and freeTap(theft, reason, held)
	if own and not free then
		local userId = thief.UserId
		local list = fails[userId] or {}
		table.insert(list, os.clock())
		fails[userId] = list
		local steps = LIMITS.FailCooldown
		setCooldown(thief, steps[math.min(#list, #steps)]) -- ("early" — обычная ступень, UX-04)
		if reason == "tag" then
			closeBase(key, LIMITS.TagCooldown, "tagged")
		end
		-- Срывы на этой базе: BaseFails за FailWindow — она закрыта для него (UX-03).
		local onBase = baseFails[key] or {}
		table.insert(onBase, os.clock())
		baseFails[key] = onBase
		if LIMITS.BaseFails > 0 and #onBase >= LIMITS.BaseFails then
			closeBase(key, LIMITS.BaseWait, "wary")
		end
	elseif reason == "shield" then
		-- Щит хозяина против его кражи: не его вина (без ожидания), но эта база закрыта до конца
		-- защиты и ещё ShieldWait — щит не «выманить» (UX-02).
		local _, untilT = DefenceService:IsProtected(victim)
		closeBase(key, math.max(0, (untilT or now()) - now()) + LIMITS.ShieldWait, "shielded")
	end
	local closed = tagged[key]
	local closedLeft = if closed then closed.Until - os.clock() else 0
	send(thief, "Cancel", {
		Reason = reason,
		Text = TEXTS.Cancel[reason] or TEXTS.Cancel.busy,
		Phase = theft.Phase,
		BaseUntil = if closedLeft > 0 then TankRules.AttrTime(now() + closedLeft) else nil,
		BaseReason = if closed and closedLeft > 0 then closed.Kind else nil,
	})
	if reason ~= "victim" then
		-- Тихо — удержание, которое кончил сам вор (или никто): короче QuietSavedUnder, прощённый тап
		-- (DATA-01) или кража, чьи тревоги все были тихими (UX-03: тот же вор за AlertCoalesce);
		-- защиту хозяина (поймал, щит) празднуют всегда (D20; A2-04). Вынос — всегда громко.
		local quiet = theft.Phase == "hold"
			and not OWNER_SAVE[reason]
			and (held < LIMITS.QuietSavedUnder or free or not theft.Loud)
		send(victim, "Saved", {
			Reason = reason,
			Slot = theft.Slot,
			Text = savedText(reason),
			Quiet = if quiet then true else nil,
		})
	end
	finish(theft, reason)
end

-- Рыба у ограды: TankService:StealFish (nil — рыба вернулась), защита жертвы, ожидание вора.
local function credit(theft: Theft)
	local thief, victim = theft.Thief, theft.Victim
	local ok, result, why = xpcall(function(): (any, any)
		return TankService:StealFish(victim, thief, theft.Uid, theft.Token)
	end, trace)
	if not ok then
		warn(`[StealService] ❌ StealFish: {result}`)
		result, why = nil, "busy"
	end
	if not result then
		cancel(theft, if why == "full" then "full" else "busy")
		return
	end
	theft.Credited = true -- (дальше ни один срыв её не тронет: защита жертвы — ниже)
	-- Рыба уже у вора: конец кражи — всегда, что бы ни упало ниже (A2-02).
	local done, err = xpcall(function(): any
		DefenceService:GiveAfterTheft(victim)
		setCooldown(thief, LIMITS.ThiefCooldown)
		local kind, untilT = DefenceService:IsProtected(victim)
		send(thief, "Done", { Fish = result.Fish, Result = result.Result, Name = victim.DisplayName })
		send(victim, "Lost", {
			Fish = result.Fish,
			Name = thief.DisplayName,
			Until = if untilT then TankRules.AttrTime(untilT) else nil,
			Kind = kind,
		})
		return nil
	end, trace)
	if not done then
		warn(`[StealService] ❌ после StealFish: {err}`)
	end
	finish(theft, "credited")
end

--------------------------------------------------------------------------------
-- Проверки по ходу кражи
--------------------------------------------------------------------------------

local function victimGone(theft: Theft): boolean
	local victim = theft.Victim
	return victim.Parent ~= Players
		or theft.Base.Owner ~= victim
		or not DataService:CanWrite(victim)
		or not TankService:IsMounted(victim)
end

local function ownerNear(theft: Theft): boolean
	local thiefRoot, ownerRoot = rootOf(theft.Thief), rootOf(theft.Victim)
	return thiefRoot ~= nil
		and ownerRoot ~= nil
		and flat(thiefRoot.Position, ownerRoot.Position) <= StealConfig.Tag.Range
end

-- Что сорвёт удержание сейчас (nil — ничего): жив, радиус, хозяин, щит, касание, рыба та же.
local function holdProblem(theft: Theft): string?
	if not alive(theft) then
		return "died"
	end
	local root = rootOf(theft.Thief) :: BasePart
	if (theft.Info.Attachment.WorldPosition - root.Position).Magnitude > PROMPT.MaxDistance + PROMPT.Slack then
		return "far"
	end
	if victimGone(theft) then
		return "victim"
	end
	if DefenceService:IsProtected(theft.Victim) ~= nil then
		return "shield"
	end
	if ownerNear(theft) then
		return "tag"
	end
	local _, view = TankService:SlotFish(theft.Base, theft.Slot)
	if not view or view.Uid ~= theft.Uid then
		return "busy"
	end
	return nil
end

local startWatcher: () -> ()

local function alert(theft: Theft, phase: string)
	local key = pairKey(theft.Thief, theft.Victim)
	local t = os.clock()
	pruneMaps()
	local quiet = alerts[key] ~= nil
	if not quiet then
		alerts[key] = t
		theft.Loud = true
	end
	local fish = theft.Fish
	send(theft.Victim, "Alert", {
		Phase = phase,
		Thief = theft.Thief.UserId,
		Name = theft.Thief.DisplayName,
		Slot = theft.Slot,
		FishId = fish.Id,
		Rarity = fish.Rarity,
		Mutation = fish.Mutation,
		Short = fish.ShortName,
		Income10 = fish.Income10,
		End = if phase == "carry" then theft.CarryEnd else theft.HoldEnd,
		Quiet = if quiet then true else nil,
	})
end

-- Удержание кончилось (Triggered вовремя): вынос — или сразу кража без выноса (Carry.Enabled).
local function toCarry(theft: Theft)
	if not current(theft) or theft.Phase ~= "hold" then
		return
	end
	local problem = holdProblem(theft)
	if problem then
		cancel(theft, problem)
		return
	end
	commit(theft) -- (наблюдатель это уже сделал; под защитой рыбу не унести)
	local thief, victim = theft.Thief, theft.Victim
	theft.CarryUntil = os.clock() + CARRY.Timeout
	theft.CarryEnd = TankRules.AttrTime(now() + CARRY.Timeout)
	if not TankService:SetSteal(victim, theft.Uid, theft.Token, "carry", { End = theft.CarryEnd }) then
		cancel(theft, "busy")
		return
	end
	theft.Phase = "carry"
	if not CARRY.Enabled then
		credit(theft) -- (буквально по заданию: рыба — вора в конце удержания)
		return
	end
	if type(FishingService.DropHeldFish) == "function" then
		FishingService:DropHeldFish(thief)
	end
	local fish = theft.Fish
	local model = HeldRig.Build(theft.Character, {
		Id = fish.Id,
		Rarity = fish.Rarity,
		Mutation = fish.Mutation,
		Kg = fish.Kg,
		Value = fish.Value,
		Income = fish.Income10 / 10,
	}, "StolenFish")
	if model then
		model:SetAttribute("Owner", victim.UserId)
		theft.Trove:Add(model)
	end
	Speed.Set(thief, "Carry", CARRY.SpeedFactor)
	theft.Guard = CarryGuard.new(CARRY.Speed, Speed.Allowed(thief, CARRY.Speed.FactorGrace))
	local root = rootOf(thief)
	theft.LastPos = if root then flatten(root.Position) else nil
	setAttr(thief, "Stealing", "carry")
	send(thief, "Carry", { End = theft.CarryEnd })
	alert(theft, "carry")
end

-- Один шаг наблюдателя для кражи (dt — с прошлого шага).
local function stepTheft(theft: Theft, dt: number)
	if not current(theft) then
		return
	end
	if theft.Phase == "hold" then
		local problem = holdProblem(theft)
		if problem then
			cancel(theft, problem)
		elseif not theft.Finishing and os.clock() - theft.T0 > theft.Need + HOLD.Deadline then
			cancel(theft, "deadline")
		elseif not theft.Committed and os.clock() - theft.T0 >= tapWindow(theft) then
			commit(theft) -- (дольше тапа — попытка: защита вора гаснет, UX-01)
		end
		return
	end
	-- Вынос.
	if not alive(theft) then
		cancel(theft, "died")
		return
	end
	if victimGone(theft) then
		cancel(theft, "victim")
		return
	end
	if DefenceService:IsProtected(theft.Victim) ~= nil then
		cancel(theft, "shield")
		return
	end
	if ownerNear(theft) then
		cancel(theft, "tag")
		return
	end
	if os.clock() > theft.CarryUntil then
		cancel(theft, "timeout")
		return
	end
	local root = rootOf(theft.Thief) :: BasePart
	local pos = flatten(root.Position)
	local last = theft.LastPos or pos
	theft.LastPos = pos
	local guard = theft.Guard :: CarryGuard.Guard
	if guard:Step(dt, (pos - last).Magnitude, Speed.Allowed(theft.Thief, CARRY.Speed.FactorGrace)) == "speed" then
		cancel(theft, "speed")
		return
	end
	local here = StealRules.LocalOf(theft.Base.Model:GetPivot(), root.Position)
	if not StealRules.InPlot(here, CARRY.ExitMargin) and guard:CanCredit() then
		credit(theft)
	end
end

local function stepDog(base: Base, dt: number)
	local theft = byBase[base]
	local live = theft ~= nil and current(theft)
	local thiefAt: Vector3? = nil
	if live then
		local root = rootOf((theft :: Theft).Thief)
		if root then
			thiefAt = StealRules.LocalOf(base.Model:GetPivot(), root.Position)
		end
	end
	local bite = DogBrain.Step(base, dt, thiefAt)
	local brain = DogBrain.Get(base)
	if bite and live and brain and brain.Target == (theft :: Theft).Thief.UserId then
		Speed.Set((theft :: Theft).Thief, "Dog", DOG.Slow, os.clock() + DOG.SlowLinger)
	end
	if not brain then
		dogs[base] = nil -- (уснула)
	end
end

startWatcher = function()
	if watching then
		return
	end
	watching = true
	task.spawn(function()
		local last = os.clock()
		while next(byThief) ~= nil or next(dogs) ~= nil do
			task.wait(StealConfig.Tick)
			local t = os.clock()
			local dt = t - last
			last = t
			for _, theft in table.clone(byThief) do
				local ok, err = xpcall(function(): any
					stepTheft(theft, dt)
					return nil
				end, trace)
				if not ok then
					if os.clock() - lastWarn >= WARN_EVERY then
						lastWarn = os.clock()
						warn(`[StealService] ❌ шаг кражи: {err}`)
					end
					if theft.Credited then
						pcall(finish, theft, "credited") -- (рыба уже у вора: только конец, A2-02)
					else
						pcall(cancel, theft, "busy", nil)
					end
				end
			end
			for base in table.clone(dogs) do
				local ok, err = xpcall(function(): any
					stepDog(base, dt)
					return nil
				end, trace)
				if not ok then
					if os.clock() - lastWarn >= WARN_EVERY then
						lastWarn = os.clock()
						warn(`[StealService] ❌ шаг собаки: {err}`)
					end
					dogs[base] = nil
				end
			end
		end
		watching = false
	end)
end

--------------------------------------------------------------------------------
-- Начало кражи
--------------------------------------------------------------------------------

local function begin(player: Player, prompt: ProximityPrompt, info: PromptInfo, fish: TankService.SlotView)
	local base = info.Base
	local victim = base.Owner :: Player
	local character = player.Character :: Model
	nextToken += 1
	local need = DefenceService:HoldTime(victim)
	local theft: Theft = {
		Token = nextToken,
		Thief = player,
		Victim = victim,
		Base = base,
		Slot = info.Slot,
		Uid = fish.Uid,
		Fish = fish,
		Prompt = prompt,
		Info = info,
		Character = character,
		Phase = "hold",
		T0 = os.clock(),
		Need = need,
		HoldEnd = TankRules.AttrTime(now() + need),
		CarryEnd = nil,
		CarryUntil = math.huge,
		Finishing = false,
		Committed = false,
		Loud = false,
		Credited = false,
		Ended = false,
		Guard = nil,
		LastPos = nil,
		Trove = Trove.new(),
	}
	if not TankService:SetSteal(victim, fish.Uid, theft.Token, "hold", { By = player.UserId, End = theft.HoldEnd }) then
		send(player, "Denied", {
			Reason = "busy",
			Text = StealRules.DeniedText("busy"),
			BaseIndex = base.Index,
			Slot = info.Slot,
		})
		return
	end
	byThief[player] = theft
	byBase[base] = theft
	info.Held = true
	theft.Trove:Add(function()
		Speed.ClearAll(player) -- (первая уборка кражи: вор не останется медленным, BE-10)
	end)
	-- (защита вора гаснет не здесь, а когда удержание переживёт окно тапа: commit, UX-01)
	local model = base.Model
	alarmTokens[base] = nil
	setAttr(model, "Thief", player.UserId)
	setAttr(model, "AlarmState", "theft")
	if DefenceService:HasDog(victim) then
		DogBrain.Wake(base, player.UserId)
		dogs[base] = true
	end
	setAttr(player, "Stealing", "hold") -- (последним)
	send(player, "Hold", {
		Slot = info.Slot,
		BaseIndex = base.Index,
		Uid = fish.Uid,
		FishId = fish.Id,
		Rarity = fish.Rarity,
		Mutation = fish.Mutation,
		Short = fish.ShortName,
		Income10 = fish.Income10,
		End = theft.HoldEnd,
		Need = need,
	})
	alert(theft, "hold")
	StealService.TheftStarted:Fire(player, victim, "hold")
	startWatcher()
end

-- Полный view проверок §4.3 (TheftChecks.Fields — сервер заполняет каждое поле).
local function viewFor(player: Player, info: PromptInfo, bucket: boolean): (TheftChecks.View, TankService.SlotView?)
	local base = info.Base
	local victim = base.Owner
	local t, serverNow = os.clock(), now()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = rootOf(player)
	local owner, fish = TankService:SlotFish(base, info.Slot)
	local kind, untilT = nil, nil
	if victim then
		kind, untilT = DefenceService:IsProtected(victim)
	end
	local ownerRoot = if victim then rootOf(victim) else nil
	local closed = if victim then tagged[pairKey(player, victim)] else nil
	local last = lastDenied[player]
	local view: TheftChecks.View = {
		Known = true,
		Repeat = false,
		Bucket = bucket,
		Own = victim == player,
		ThiefWritable = DataService:CanWrite(player),
		ThiefMounted = TankService:IsMounted(player),
		VictimReady = victim ~= nil and owner == victim and DataService:CanWrite(victim) and TankService:IsMounted(
			victim
		),
		Alive = humanoid ~= nil and humanoid.Health > 0 and root ~= nil,
		Distance = if root then (info.Attachment.WorldPosition - root.Position).Magnitude else math.huge,
		Stealing = byThief[player] ~= nil,
		CooldownLeft = math.max(0, (cooldowns[player.UserId] or 0) - t),
		TagLeft = if closed then math.max(0, closed.Until - t) else 0,
		TagKind = if closed then closed.Kind else nil,
		ProtectLeft = if untilT then untilT - serverNow else 0,
		ProtectKind = kind,
		BaseTheft = byBase[base] ~= nil,
		OwnerDistance = if root and ownerRoot then flat(root.Position, ownerRoot.Position) else math.huge,
		VictimActive = if victim then TankService:ActiveCount(victim) else 0,
		ThiefIncome10 = TankService:Income10(player),
		VictimIncome10 = if victim then TankService:Income10(victim) else 0,
		FishMissing = fish == nil,
		FishTaken = fish ~= nil and (fish.Steal ~= nil or fish.Escrow),
		FreshLeft = if fish and fish.FreshUntil then fish.FreshUntil - serverNow else 0,
		Placeable = if fish then TankService:PreviewAdd(player, fish.Income10) ~= nil else true,
		LastReason = if last then last.Reason else nil,
		LastAt = if last then last.At else nil,
		Now = t,
	}
	return view, fish
end

local function onHoldBegan(prompt: ProximityPrompt, player: Player)
	local info = promptInfo[prompt]
	local held = byThief[player]
	-- Строки 1–2 — до жетона: двойное нажатие на ту же кнопку ничего не стоит (BE-17).
	if TheftChecks.Check({ Known = info ~= nil, Repeat = held ~= nil and held.Prompt == prompt }) then
		return
	end
	local pinfo = info :: PromptInfo
	local view, fish = viewFor(player, pinfo, startBucket:Take(player))
	local reason, quiet, left = TheftChecks.Check(view)
	if reason then
		if TheftChecks.Silent[reason] then
			return
		end
		send(player, "Denied", {
			Reason = reason,
			Text = StealRules.DeniedText(reason, left),
			Quiet = quiet,
			BaseIndex = pinfo.Base.Index,
			Slot = pinfo.Slot,
			Until = if type(left) == "number" and left > 0 then TankRules.AttrTime(now() + left) else nil,
		})
		if not quiet and player.Parent == Players then
			lastDenied[player] = { Reason = reason, At = os.clock() }
		end
		return
	end
	begin(player, prompt, pinfo, fish :: TankService.SlotView)
end

local function onTriggered(prompt: ProximityPrompt, player: Player)
	if not promptInfo[prompt] then
		return
	end
	local theft = byThief[player]
	if not theft or theft.Prompt ~= prompt then
		suspicion(`Triggered без удержания (игрок {player.UserId})`)
		return
	end
	if not current(theft) or theft.Phase ~= "hold" or theft.Finishing then
		return
	end
	local elapsed = os.clock() - theft.T0
	if elapsed < theft.Need * HOLD.LateShare then
		suspicion(
			`Triggered через {string.format("%.2f", elapsed)} с из {theft.Need} (игрок {player.UserId})`
		)
		cancel(theft, "early")
		return
	end
	-- Раньше need, но не раньше need × LateShare: его HoldBegan опоздал (медленная связь) — удержание
	-- кончит сервер сам в T0 + need; наблюдатель до тех пор проверяет радиус, жизнь, щит и касание
	-- (UX-04: честный телефон на плохой связи больше не «early»; fireproximityprompt раньше need не
	-- кончит).
	theft.Finishing = true
	if elapsed < theft.Need then
		task.delay(theft.Need - elapsed, function()
			if current(theft) and theft.Phase == "hold" then
				toCarry(theft)
			end
		end)
	else
		toCarry(theft)
	end
end

local function onHoldEnded(prompt: ProximityPrompt, player: Player)
	local theft = byThief[player]
	if not theft or theft.Prompt ~= prompt or not current(theft) or theft.Phase ~= "hold" or theft.Finishing then
		return
	end
	-- Причина — по состоянию в этот миг (BE-13): стандартная кнопка сама гасит удержание раньше,
	-- чем наблюдатель увидит смерть или радиус.
	local reason = "released"
	if not alive(theft) then
		reason = "died"
	else
		local root = rootOf(player) :: BasePart
		if (theft.Info.Attachment.WorldPosition - root.Position).Magnitude > PROMPT.MaxDistance then
			reason = "far"
		end
	end
	local at = os.clock()
	if reason == "released" and at - theft.T0 >= theft.Need - HOLD.Tolerance then
		-- Отпустил у самого конца: Triggered может прийти следом (порядок двух событий клиента).
		task.delay(HOLD.Grace, function()
			if current(theft) and theft.Phase == "hold" and not theft.Finishing then
				cancel(theft, "released", at)
			end
		end)
		return
	end
	cancel(theft, reason, at)
end

--------------------------------------------------------------------------------
-- Публичное API
--------------------------------------------------------------------------------

function StealService:IsStealing(player: Player): ("hold" | "carry")?
	local theft = byThief[player]
	return if theft and not theft.Ended then theft.Phase else nil
end

function StealService:TheftOn(base: any): TheftView?
	if typeof(base) == "Instance" then
		base = BaseService:GetBaseFromInstance(base) -- (модель базы Base_N — тоже можно)
	end
	local theft = if base then byBase[base] else nil
	if not theft or theft.Ended then
		return nil
	end
	return { Thief = theft.Thief, Victim = theft.Victim, Slot = theft.Slot, Phase = theft.Phase }
end

function StealService:Cancel(player: Player, reason: string)
	local theft = byThief[player]
	if theft then
		cancel(theft, reason)
		return
	end
	for _, other in table.clone(byBase) do
		if other.Victim == player then
			cancel(other, reason)
		end
	end
end

function StealService._debugSizes(): { [string]: number }
	pruneMaps()
	return {
		Thefts = count(byThief),
		Buckets = startBucket:Size(),
		Cooldowns = count(cooldowns),
		Fails = count(fails),
		Taps = count(taps),
		Tags = count(tagged),
		BaseFails = count(baseFails),
		Alerts = count(alerts),
		Denied = count(lastDenied),
		Dogs = count(dogs),
		Watcher = if watching then 1 else 0,
	}
end

--------------------------------------------------------------------------------
-- Жизненный цикл сервиса
--------------------------------------------------------------------------------

local function homeGuard(player: Player): (string?, CFrame?)
	local theft = byThief[player]
	if theft and not theft.Ended and theft.Phase == "carry" then
		return TEXTS.HomeGuard, nil
	end
	local base = BaseService:GetBase(player)
	if base and byBase[base] then
		-- На площадку лицом во двор (+Z базы), не к воротам.
		local spawn = BaseService:GetSpawnCFrame(base)
		local forward = base.Model:GetPivot():VectorToWorldSpace(Vector3.new(0, 0, 1))
		return nil, CFrame.lookAt(spawn.Position, spawn.Position + forward)
	end
	return nil, nil
end

local function onUnmounted(_player: Player, base: Base)
	local theft = byBase[base]
	if theft then
		cancel(theft, "victim")
	end
	DogBrain.Reset(base)
	dogs[base] = nil
	resetPrompts(base)
	alarmTokens[base] = nil
	setAttr(base.Model, "Thief", nil)
	setAttr(base.Model, "AlarmState", nil)
end

local function onPlayerRemoving(player: Player)
	local theft = byThief[player]
	if theft then
		cancel(theft, "left")
	end
	for _, other in table.clone(byBase) do
		if other.Victim == player then
			cancel(other, "victim")
		end
	end
	startBucket:Forget(player)
	lastDenied[player] = nil
	Speed.Forget(player)
	pruneMaps()
end

function StealService:Init()
	stealEvent = Net.Event("StealEvent")
	for _, base in BaseService:GetBases() do
		local list: { ProximityPrompt } = {}
		for index = 1, TankConfig.MaxSlots do
			local slots = base.Tank:FindFirstChild("Slots")
			local slot = slots and slots:FindFirstChild(`Slot_{index}`)
			local pedestal = slot and slot:FindFirstChild("Pedestal")
			local attachment = pedestal and pedestal:FindFirstChild("PromptAttachment")
			if not attachment or not attachment:IsA("Attachment") then
				error(`[StealService] у {base.Model:GetFullName()} нет Slot_{index}.Pedestal.PromptAttachment`)
			end
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "StealPrompt"
			prompt.ActionText = PROMPT.Action
			prompt.ObjectText = ""
			prompt.HoldDuration = BASE_HOLD
			prompt.MaxActivationDistance = PROMPT.MaxDistance -- (больше сервер его не пишет: BE-14)
			prompt.RequiresLineOfSight = false
			prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.ClickablePrompt = true
			prompt.Style = Enum.ProximityPromptStyle.Default
			prompt.Enabled = false
			prompt.Parent = attachment
			promptInfo[prompt] = { Base = base, Slot = index, Attachment = attachment, Held = false }
			list[index] = prompt
		end
		prompts[base] = list
	end
	if type(DefenceService.SetStealProbe) == "function" then
		DefenceService.SetStealProbe(function(player: Player): boolean
			return StealService:IsStealing(player) ~= nil
		end)
	end
end

function StealService:Start()
	ProximityPromptService.PromptButtonHoldBegan:Connect(onHoldBegan)
	ProximityPromptService.PromptButtonHoldEnded:Connect(onHoldEnded)
	ProximityPromptService.PromptTriggered:Connect(onTriggered)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	if TankService.SlotChanged then
		TankService.SlotChanged:Connect(refreshPrompt)
	end
	if TankService.Mounted then
		TankService.Mounted:Connect(function(player: Player, base: Base)
			restoreCooldown(player)
			refreshBase(base)
		end)
	end
	if TankService.Unmounted then
		TankService.Unmounted:Connect(onUnmounted)
	end
	DefenceService.ProtectionChanged:Connect(function(player: Player, base: Base?)
		local theft = if base then byBase[base] else nil
		if theft and current(theft) and theft.Victim == player and DefenceService:IsProtected(player) ~= nil then
			cancel(theft, "shield") -- (щит: удержание сорвано, несомая рыба — домой; DC-01)
		end
	end)
	DefenceService.LockChanged:Connect(function(_player: Player, base: Base?)
		if base then
			refreshBase(base)
		end
	end)
	if type(BaseService.SetHomeGuard) == "function" then
		BaseService:SetHomeGuard(homeGuard)
	end
	-- Уже подключённые садки (Studio: игрок успел раньше скрипта).
	for _, base in BaseService:GetBases() do
		refreshBase(base)
	end
end

return StealService
