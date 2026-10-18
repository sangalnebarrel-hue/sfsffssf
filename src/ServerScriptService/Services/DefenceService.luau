--!strict
--[[
	DefenceService — защита базы (Этап 4): щит, бесплатные защиты (вход, «новичок», после кражи,
	«садок отдыхает»), покупки собаки, сигнализации и замка, показ собаки во дворе, раннее
	предупреждение о госте (сигнализация). Числа и тексты — DefenceConfig (и StealConfig.Limits),
	данные — DataService (поля LockLevel, Upgrades.Dog / Alarm / ShieldReadyAt — его).
	Подробно — docs/stage4_design.md, §2, §4.1, §4.10, §4.11.

	Что делает:
	  1. Защита базы — одна на базу: ProtectUntil = позднейшая из щита, защиты входа / новичка,
	     «после кражи» и «отдыха»; ProtectKind — та, что кончается позже (StealRules.ProtectState).
	     Время — серверное (Workspace:GetServerTimeNow; в атрибуты — через TankRules.AttrTime).
	     Конец каждого вида — один task.delay на базу (до ближайшего конца) с номером поколения
	     (старый таймер ничего не делает): атрибуты переписаны, ProtectionChanged, кончился щит —
	     владельцу «Щит погас» (Notify, вид "shield") и атрибут ShieldUntil снят.
	     ProtectionChanged(player, base) — при каждой смене вида или конца (StealService отменяет
	     удержание и возвращает несомую рыбу, когда база стала под защитой: щит, DC-01).
	  2. Щит (ShieldActivate, проверки по порядку — шапка RemoteNames): лимит DefenceConfig.Requests
	     (пусто — молча), CanWrite ("loading"), своя подключённая база ("nobase"), не крадёт сам —
	     проба StealService ("stealing"), защиты осталось меньше Shield.StackBelow с ("protected",
	     DC-03: истекающую защиту щит продлевает), щит готов ("cooldown"). Принято: ShieldUntil =
	     сейчас + Duration, ShieldReadyAt = сейчас + Duration + Cooldown (атрибуты игрока),
	     Upgrades.ShieldReadyAt = os.time() + Duration + Cooldown и SaveSoon, ProtectionChanged,
	     DefenceEvent("Shield", { Until, ReadyAt }). Отказ — DefenceEvent("Denied", { Reason, Text }).
	     При загрузке: до готовности = clamp(Upgrades.ShieldReadyAt − os.time(), 0, Duration +
	     Cooldown) → атрибут ShieldReadyAt = сейчас + столько (0 — атрибута нет); включённый щит не
	     сохраняется (кончается с игрой; перезаход прикрывает защита входа).
	  3. Защита входа — на первом подключении садка за игру (TankService.Mounted), что первым
	     подошло: быстрый перезаход (LastOnline при загрузке или leftAt этого сервера новее
	     QuickRejoin) — QuickRejoinProtect, kind "join"; новое сохранение (SaveCount == 0 при
	     загрузке) — JoinProtectFirst, kind "newbie"; иначе JoinProtect, "join". Что нужно, —
	     loadInfo[player] = { SaveCount, LastOnline }, снятое в DataService.Loaded (до первого
	     сохранения игры: его запись переписывает оба поля в живых данных, BE-25). Там же — идущие
	     after / rest из losses (выйти и зайти — их не укорачивает). Тосты о защите входа и
	     «Скоро воры смогут красть…» (EndingWarn) показывает клиент (DefenceController) по
	     ProtectUntil / ProtectKind.
	  4. После кражи (GiveAfterTheft): losses[UserId] (окно VictimWindow), after = сейчас +
	     VictimImmunity; стало ≥ VictimMax краж за окно — rest до (VictimMax-я с конца) +
	     VictimWindow (DC-06).
	  5. EndProtection(player, "stealing") — начал красть сам: все виды сняты и его losses
	     забыты (ShieldReadyAt не возвращается), была защита — уведомление «Твоя защита снята: ты
	     пошёл на дело!» (StealConfig.Texts.Hint.Ended, Notify "shield").
	  6. Покупки (DefenceBuy, проверки по порядку — шапка RemoteNames): строка и знакомый предмет
	     (иначе молча), лимит, CanWrite, база, "owned" / "max" / "soon", цена только из
	     DefenceConfig, EconomyService:SpendMoney(…, "defence:<item>") не вышел — "money" (с ценой);
	     потом Upgrades.Dog / Alarm = true или SetLockLevel(уровень + 1), атрибуты, собака показана,
	     SaveSoon, DefenceEvent("Bought", { Item, Level?, Price }). Без ожиданий между проверкой и
	     изменением.
	     Есть ли собака / сигнализация — ТОЛЬКО PlayerData.Owned(Upgrades.Dog / Alarm): true или
	     число > 0 (уровень сервера новее, §4.12). Так читают HasDog / HasAlarm, атрибуты и
	     проверку "owned"; с «== true» уровень 2 продался бы снова и затёрся бы значением true
	     (откат, запрещённый правилом Этапа 3 B-6). Покупка пишет true, только если не Owned.
	     Собака показана на базе владельца (все детали видны, Body / Head / будка с тенью, стены и
	     крыша будки твёрдые, Dog.Pup:PivotTo на Dog.Rest мордой к воротам, Dog.Unlocked = true),
	     снята при отключении садка — ровно вид шаблона (запомнен в Init) и его pivot щенка.
	  7. Гость во дворе (сигнализация): ОДИН цикл раз в Alarm.IntruderEvery с, только пока есть
	     подключённая база с сигнализацией (сам кончается); база не под защитой и на ней не идёт
	     кража; гость — другой игрок, его HRP на участке (StealRules.InPlot); раз в
	     IntruderCoalesce с на пару (гость, хозяин): StealEvent("Intruder", { Thief, Name }) хозяину
	     и AlarmState = "intruder" на Alarm.IntruderLamp с (если не "theft": её пишет StealService).
	  8. Studio (DC-20): RunService:IsStudio() и Debug.StudioProtect — число → вход / новичок /
	     после кражи / отдых не дольше него (щит — как есть); одна строка print при Init
	     (Texts.StudioPrint), не warn.
	  9. Отключение садка (TankService.Unmounted): атрибуты базы сняты (ProtectUntil, ProtectKind,
	     HasDog, HasAlarm, LockLevel, HoldTime), собака — как в шаблоне, база выпала из цикла
	     гостей; поколение таймера защиты сменилось.
	StealService этот модуль НЕ требует (иначе цикл require — ошибка Roblox): «крадёт ли он сам»
	спрашивает через SetStealProbe (StealService регистрирует IsStealing в своём Init; без него —
	«никто не крадёт»). Каждый вызов другого сервиса — за type(...) == "function" (заглушки
	сервисов в тестах клиента). Записи игроков — по самому Player (повторный вход — новый Player),
	чистятся в PlayerRemoving; карты по UserId (losses, leftAt, intruderSeen) — с границей по
	времени, чистятся при каждой записи, в PlayerRemoving и в _debugSizes.

	Атрибуты (RemoteNames, «Кража и защита»): Player — ShieldUntil, ShieldReadyAt, HasDog, HasAlarm,
	LockLevel; база — ProtectUntil, ProtectKind, HasDog, HasAlarm, LockLevel, HoldTime (сняты при
	отключении садка), AlarmState = "intruder" (лампа гостя); Dog — Unlocked.
	Remote'ы: ShieldActivate, DefenceBuy (клиент → сервер), DefenceEvent, StealEvent "Intruder"
	(сервер → клиент).

	API:
	  DefenceService:IsProtected(player) -> (kind?, until?)   -- защита его базы сейчас
	  DefenceService:EndProtection(player, reason)            -- снять все виды и забыть его losses
	  DefenceService:GiveAfterTheft(victim)                   -- after 90 с, rest на 2-й краже за 600 с
	  DefenceService:HasDog(player) -> boolean                -- PlayerData.Owned(Upgrades.Dog)
	  DefenceService:HasAlarm(player) -> boolean              -- PlayerData.Owned(Upgrades.Alarm)
	  DefenceService:LockLevel(player) -> number              -- в игре — min(LockLevel, #Levels)
	  DefenceService:HoldTime(player) -> number               -- StealRules.HoldTime(LockLevel)
	  DefenceService:SetLockLevel(player, n) -> boolean       -- за CanWrite; атрибуты; LockChanged
	                                                          -- (магазин Этапа 5 зовёт его же)
	  DefenceService.SetStealProbe(fn: (Player) -> boolean)   -- кто сейчас крадёт (StealService)
	  DefenceService.ProtectionChanged, DefenceService.LockChanged   -- Signal (player, base)
	  DefenceService._debugSizes()   -- Protections, Buckets, LoadInfo + Losses, LeftAt, IntruderSeen,
	                                 -- Alarmed, IntruderLoop (1 — цикл гостей идёт)
	  DefenceService._isStealing(player) -> boolean   -- тесты и отказ "stealing": ответ пробы
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local DefenceConfig = require(Shared.Config.DefenceConfig)
local StealConfig = require(Shared.Config.StealConfig)
local Net = require(Shared.Net)
local Signal = require(Shared.Util.Signal)
local StealRules = require(Shared.StealRules)
local TankRules = require(Shared.TankRules)
local TextUtil = require(Shared.TextUtil)
local Bucket = require(ServerScriptService.Lib.Bucket)
local Notify = require(ServerScriptService.Lib.Notify)
local PlayerData = require(ServerScriptService.Lib.PlayerData)
local BaseService = require(ServerScriptService.Services.BaseService)
local DataService = require(ServerScriptService.Services.DataService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local TankService = require(ServerScriptService.Services.TankService)

type Base = BaseService.Base

-- Защита одной базы (по игроку-владельцу; времена — серверные, nil — этого вида нет).
type Protect = {
	Player: Player,
	Base: Base?, -- подключённая база
	Mounted: boolean, -- первое подключение за игру уже было (защита входа выдана)
	Shield: number?,
	Join: number?,
	Newbie: number?,
	After: number?,
	Rest: number?,
	ReadyAt: number, -- щит снова готов (серверное время; 0 — готов)
	Kind: string?, -- что записано в атрибуты
	Until: number?,
	Gen: number, -- поколение таймера
	Timer: thread?,
}

type LoadInfo = { SaveCount: number, LastOnline: number }

-- Вид собаки в шаблоне (его возвращает отключение садка).
type PartLook = { Transparency: number, CastShadow: boolean, CanCollide: boolean, CanQuery: boolean }
type DogLook = { Parts: { [BasePart]: PartLook }, Pup: Model?, PupLocal: CFrame }

local SHIELD = DefenceConfig.Shield
local DOG = DefenceConfig.Dog
local ALARM = DefenceConfig.Alarm
local LOCK = DefenceConfig.Lock
local TEXTS = DefenceConfig.Texts
local LIMITS = StealConfig.Limits
local ITEMS = { Dog = true, Alarm = true, Lock = true }
-- Тень у показанной собаки — только у крупных деталей; твёрдые — стены и крыша будки.
local SHADOW = { Body = true, Head = true, Walls = true, Roof = true }
local SOLID = { Walls = true, Roof = true }
local WARN_EVERY = 30 -- секунд между предупреждениями цикла гостей

local DefenceService = {
	ProtectionChanged = Signal.new(), -- (player, base)
	LockChanged = Signal.new(), -- (player, base)
}

-- Кто сейчас крадёт (StealService:IsStealing через SetStealProbe); по умолчанию — никто.
local stealProbe: (player: Player) -> boolean = function(_player: Player): boolean
	return false
end

local states: { [Player]: Protect } = {}
local loadInfo: { [Player]: LoadInfo } = {}
local losses: { [number]: { number } } = {} -- UserId жертвы → серверные времена краж (окно VictimWindow)
local leftAt: { [number]: number } = {} -- UserId → когда ушёл с этого сервера (окно QuickRejoin)
local intruderSeen: { [string]: number } = {} -- "гость:хозяин" (UserId) → последнее предупреждение
local alarmed: { [Base]: Player } = {} -- подключённые базы с сигнализацией (цикл гостей)
local lampTokens: { [Base]: number } = {} -- лампа гостя (AlarmState "intruder"): номер последней
local dogLooks: { [Base]: DogLook } = {} -- вид собаки в шаблоне (Init; не по игрокам)
local requests = Bucket.new(DefenceConfig.Requests.Burst, DefenceConfig.Requests.Rate)
local defenceEvent: RemoteEvent? = nil
local stealEvent: RemoteEvent? = nil
local studioCap: number? = nil
local intruderRunning = false
local lastLoopWarn = -math.huge

--------------------------------------------------------------------------------
-- Помощники
--------------------------------------------------------------------------------

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

-- Studio: вход / новичок / после кражи / отдых не дольше StudioProtect (DC-20).
local function capped(seconds: number): number
	local cap = studioCap
	return if cap then math.min(seconds, cap) else seconds
end

local function attrTime(t: number?): number?
	return if t then TankRules.AttrTime(t) else nil
end

local function setAttr(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

local function sendDefence(player: Player, kind: string, data: { [string]: any })
	local remote = defenceEvent
	if remote and player.Parent == Players then
		remote:FireClient(player, kind, data)
	end
end

local function deny(player: Player, reason: string, item: string?, values: { [string]: any }?)
	local template = TEXTS.Denied[reason] or ""
	sendDefence(player, "Denied", { Item = item, Reason = reason, Text = TextUtil.fill(template, values or {}) })
end

-- Список времён без устаревших (старше window) — карты с границей по времени (BE-26).
local function pruneList(list: { number }?, window: number, t: number): { number }?
	if not list then
		return nil
	end
	local kept = {}
	for _, at in list do
		if t - at < window then
			table.insert(kept, at)
		end
	end
	return if #kept > 0 then kept else nil
end

local function pruneMaps()
	local t = now()
	for userId, list in table.clone(losses) do
		losses[userId] = pruneList(list, LIMITS.VictimWindow, t)
	end
	for userId, at in table.clone(leftAt) do
		if t - at >= SHIELD.QuickRejoin then
			leftAt[userId] = nil
		end
	end
	for key, at in table.clone(intruderSeen) do
		if t - at >= ALARM.IntruderCoalesce then
			intruderSeen[key] = nil
		end
	end
end

local function dataOf(player: Player): PlayerData.Data?
	return DataService:Get(player)
end

--------------------------------------------------------------------------------
-- Защита базы
--------------------------------------------------------------------------------

local function untilsOf(st: Protect): StealRules.Untils
	return { shield = st.Shield, join = st.Join, newbie = st.Newbie, after = st.After, rest = st.Rest }
end

local schedule: (st: Protect) -> ()

-- Переписать защиту: истёкшие виды убраны (щит — «Щит погас»), атрибуты базы, сигнал при смене,
-- таймер до ближайшего конца.
local function apply(st: Protect)
	local t = now()
	local player = st.Player
	if st.Shield and st.Shield <= t then
		st.Shield = nil
		setAttr(player, "ShieldUntil", nil)
		Notify.Send(player, TEXTS.Shield.Off, "shield" :: any)
	end
	for _, key in { "Join", "Newbie", "After", "Rest" } do
		local value = (st :: any)[key]
		if value and value <= t then
			(st :: any)[key] = nil
		end
	end
	local kind, untilT = StealRules.ProtectState(t, untilsOf(st))
	local base = st.Base
	if base then
		setAttr(base.Model, "ProtectUntil", attrTime(untilT))
		setAttr(base.Model, "ProtectKind", kind)
	end
	local changedNow = kind ~= st.Kind or untilT ~= st.Until
	st.Kind, st.Until = kind, untilT
	schedule(st)
	if changedNow then
		DefenceService.ProtectionChanged:Fire(player, base)
	end
end

schedule = function(st: Protect)
	st.Gen += 1
	local gen = st.Gen
	local timer = st.Timer
	st.Timer = nil
	if timer and coroutine.status(timer) == "suspended" then
		task.cancel(timer)
	end
	local earliest: number? = nil
	for _, t in { st.Shield, st.Join, st.Newbie, st.After, st.Rest } do
		if t and (earliest == nil or t < earliest) then
			earliest = t
		end
	end
	if not earliest then
		return
	end
	st.Timer = task.delay(math.max(0, earliest - now()), function()
		if st.Gen ~= gen or states[st.Player] ~= st then
			return
		end
		st.Timer = nil
		apply(st)
	end)
end

local function stop(st: Protect)
	st.Gen += 1
	local timer = st.Timer
	st.Timer = nil
	if timer and coroutine.status(timer) == "suspended" then
		task.cancel(timer)
	end
end

local function stateFor(player: Player): Protect?
	local st = states[player]
	if st then
		return st
	end
	if player.Parent ~= Players then
		return nil
	end
	local created: Protect = {
		Player = player,
		Base = nil,
		Mounted = false,
		Shield = nil,
		Join = nil,
		Newbie = nil,
		After = nil,
		Rest = nil,
		ReadyAt = 0,
		Kind = nil,
		Until = nil,
		Gen = 0,
		Timer = nil,
	}
	states[player] = created
	return created
end

-- after / rest из списка краж (на кражу и на первое подключение следующей игры).
local function applyLosses(st: Protect, t: number)
	local userId = st.Player.UserId
	local list = pruneList(losses[userId], LIMITS.VictimWindow, t)
	losses[userId] = list
	if not list then
		return
	end
	local latest = list[#list]
	local after = latest + capped(LIMITS.VictimImmunity)
	if after > t then
		st.After = math.max(st.After or 0, after)
	end
	if #list >= LIMITS.VictimMax then
		local older = list[#list - LIMITS.VictimMax + 1]
		local rest = older + LIMITS.VictimWindow
		if studioCap then
			rest = math.min(rest, latest + studioCap)
		end
		if rest > t then
			st.Rest = math.max(st.Rest or 0, rest)
		end
	end
end

-- Защита входа (первое подключение садка за игру; §2.4).
local function joinProtect(st: Protect, t: number)
	local player = st.Player
	local info = loadInfo[player]
	pruneMaps()
	local left = leftAt[player.UserId]
	local lastOnline = if info then info.LastOnline else 0
	local quick = (lastOnline > 0 and os.time() - lastOnline < SHIELD.QuickRejoin)
		or (left ~= nil and t - left < SHIELD.QuickRejoin)
	if quick then
		st.Join = t + capped(SHIELD.QuickRejoinProtect)
	elseif info and info.SaveCount == 0 then
		st.Newbie = t + capped(SHIELD.JoinProtectFirst)
	else
		st.Join = t + capped(SHIELD.JoinProtect)
	end
	applyLosses(st, t)
end

--------------------------------------------------------------------------------
-- Собака: показать / как в шаблоне
--------------------------------------------------------------------------------

local function inKennel(part: Instance, dog: Model): boolean
	local kennel = dog:FindFirstChild("DogHouse")
	return kennel ~= nil and part:IsDescendantOf(kennel)
end

local function restCFrame(base: Base, look: DogLook): CFrame
	-- Dog.Rest (точка базы) на высоте шаблона, мордой к воротам (−Z базы: −Z модели щенка — морда).
	return base.Model:GetPivot() * CFrame.new(DOG.Rest.X, look.PupLocal.Y, DOG.Rest.Z)
end

local function showDog(base: Base)
	local look = dogLooks[base]
	local dog = base.Dog
	if not look then
		return
	end
	for part in look.Parts do
		part.Transparency = 0
		if SHADOW[part.Name] then
			part.CastShadow = true
		end
		if SOLID[part.Name] and inKennel(part, dog) then
			part.CanCollide = true
		end
	end
	local pup = look.Pup
	if pup then
		pup:PivotTo(restCFrame(base, look))
	end
	setAttr(dog, "Unlocked", true)
end

local function hideDog(base: Base)
	local look = dogLooks[base]
	if not look then
		return
	end
	for part, was in look.Parts do
		part.Transparency = was.Transparency
		part.CastShadow = was.CastShadow
		part.CanCollide = was.CanCollide
		part.CanQuery = was.CanQuery
	end
	local pup = look.Pup
	if pup then
		pup:PivotTo(base.Model:GetPivot() * look.PupLocal)
	end
	setAttr(base.Dog, "Unlocked", false)
end

local function rememberDog(base: Base)
	local dog = base.Dog
	local parts: { [BasePart]: PartLook } = {}
	for _, d in dog:GetDescendants() do
		if d:IsA("BasePart") then
			parts[d] = {
				Transparency = d.Transparency,
				CastShadow = d.CastShadow,
				CanCollide = d.CanCollide,
				CanQuery = d.CanQuery,
			}
		end
	end
	local pup = dog:FindFirstChild("Pup")
	local pupModel = if pup and pup:IsA("Model") then pup else nil
	dogLooks[base] = {
		Parts = parts,
		Pup = pupModel,
		PupLocal = if pupModel then base.Model:GetPivot():ToObjectSpace(pupModel:GetPivot()) else CFrame.identity,
	}
end

--------------------------------------------------------------------------------
-- Гость во дворе (сигнализация)
--------------------------------------------------------------------------------

local function intruderLamp(base: Base)
	local model = base.Model
	if model:GetAttribute("AlarmState") == "theft" then
		return -- (кража громче: лампу ведёт StealService)
	end
	local token = (lampTokens[base] or 0) + 1
	lampTokens[base] = token
	model:SetAttribute("AlarmState", "intruder")
	task.delay(ALARM.IntruderLamp, function()
		if lampTokens[base] == token then
			lampTokens[base] = nil
			if model:GetAttribute("AlarmState") == "intruder" then
				model:SetAttribute("AlarmState", nil)
			end
		end
	end)
end

local function intruderStep()
	local t = now()
	pruneMaps()
	for base, owner in table.clone(alarmed) do
		local st = states[owner]
		if base.Owner ~= owner or not st or st.Base ~= base then
			continue
		end
		if StealRules.ProtectState(t, untilsOf(st)) ~= nil or base.Model:GetAttribute("Thief") ~= nil then
			continue -- (под защитой гостей не объявляем; во время кражи — своя тревога)
		end
		local pivot = base.Model:GetPivot()
		for _, other in Players:GetPlayers() do
			if other == owner then
				continue
			end
			local character = other.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") then
				continue
			end
			if not StealRules.InPlot(StealRules.LocalOf(pivot, root.Position), 0) then
				continue
			end
			local key = `{other.UserId}:{owner.UserId}`
			local seen = intruderSeen[key]
			if seen and t - seen < ALARM.IntruderCoalesce then
				continue
			end
			intruderSeen[key] = t
			local remote = stealEvent
			if remote and owner.Parent == Players then
				remote:FireClient(owner, "Intruder", { Thief = other.UserId, Name = other.DisplayName })
			end
			intruderLamp(base)
		end
	end
end

local function startIntruders()
	if intruderRunning or next(alarmed) == nil then
		return
	end
	intruderRunning = true
	task.spawn(function()
		while next(alarmed) ~= nil do
			task.wait(ALARM.IntruderEvery)
			local ok, err = xpcall(function(): any
				intruderStep()
				return nil
			end, function(e: any): string
				return debug.traceback(tostring(e), 2)
			end)
			if not ok and os.clock() - lastLoopWarn >= WARN_EVERY then
				lastLoopWarn = os.clock()
				warn(`[DefenceService] ❌ цикл гостей: {err}`)
			end
		end
		intruderRunning = false
	end)
end

--------------------------------------------------------------------------------
-- Публичное API
--------------------------------------------------------------------------------

function DefenceService:IsProtected(player: Player): (string?, number?)
	local st = states[player]
	if not st then
		return nil, nil
	end
	return StealRules.ProtectState(now(), untilsOf(st))
end

function DefenceService:EndProtection(player: Player, reason: string)
	losses[player.UserId] = nil
	local st = states[player]
	if not st then
		return
	end
	local had = StealRules.ProtectState(now(), untilsOf(st)) ~= nil
	st.Shield, st.Join, st.Newbie, st.After, st.Rest = nil, nil, nil, nil, nil
	setAttr(player, "ShieldUntil", nil)
	apply(st)
	if had and reason == "stealing" then
		Notify.Send(player, StealConfig.Texts.Hint.Ended, "shield" :: any)
	end
end

function DefenceService:GiveAfterTheft(victim: Player)
	local st = states[victim]
	if not st then
		return
	end
	local t = now()
	local userId = victim.UserId
	local list = pruneList(losses[userId], LIMITS.VictimWindow, t) or {}
	table.insert(list, t)
	while #list > LIMITS.VictimMax do
		table.remove(list, 1) -- (важны только последние VictimMax)
	end
	losses[userId] = list
	applyLosses(st, t)
	apply(st)
end

function DefenceService:HasDog(player: Player): boolean
	local data = dataOf(player)
	return data ~= nil and PlayerData.Owned(data.Upgrades.Dog)
end

function DefenceService:HasAlarm(player: Player): boolean
	local data = dataOf(player)
	return data ~= nil and PlayerData.Owned(data.Upgrades.Alarm)
end

function DefenceService:LockLevel(player: Player): number
	local data = dataOf(player)
	local level = if data and finite(data.LockLevel) then math.max(0, math.floor(data.LockLevel)) else 0
	return math.min(level, #LOCK.Levels)
end

function DefenceService:HoldTime(player: Player): number
	return StealRules.HoldTime(DefenceService:LockLevel(player))
end

-- Атрибуты замка у игрока и его подключённой базы.
local function writeLock(player: Player)
	local level = DefenceService:LockLevel(player)
	setAttr(player, "LockLevel", level)
	local st = states[player]
	local base = st and st.Base
	if base then
		setAttr(base.Model, "LockLevel", level)
		setAttr(base.Model, "HoldTime", StealRules.HoldTime(level))
	end
end

function DefenceService:SetLockLevel(player: Player, level: number): boolean
	if not DataService:CanWrite(player) or not finite(level) or level < 0 or level % 1 ~= 0 then
		return false
	end
	local data = dataOf(player)
	if not data then
		return false
	end
	data.LockLevel = level
	writeLock(player)
	local st = states[player]
	DefenceService.LockChanged:Fire(player, st and st.Base)
	return true
end

function DefenceService.SetStealProbe(fn: ((player: Player) -> boolean)?)
	stealProbe = fn or function(_player: Player): boolean
		return false
	end
end

-- (Для отказа ShieldActivate "stealing": крадёт ли игрок сам — через пробу.)
function DefenceService._isStealing(player: Player): boolean
	return stealProbe(player) == true
end

function DefenceService._debugSizes(): { [string]: number }
	pruneMaps()
	local function count(t: { [any]: any }): number
		local n = 0
		for _ in t do
			n += 1
		end
		return n
	end
	return {
		Protections = count(states),
		Buckets = requests:Size(),
		LoadInfo = count(loadInfo),
		Losses = count(losses),
		LeftAt = count(leftAt),
		IntruderSeen = count(intruderSeen),
		Alarmed = count(alarmed),
		IntruderLoop = if intruderRunning then 1 else 0,
	}
end

--------------------------------------------------------------------------------
-- Remote'ы
--------------------------------------------------------------------------------

local function onShield(player: Player)
	if not requests:Take(player) then
		return -- лимит: молча
	end
	if not DataService:CanWrite(player) then
		deny(player, "loading")
		return
	end
	local st = states[player]
	if not st or not TankService:IsMounted(player) or not st.Base then
		deny(player, "nobase")
		return
	end
	if stealProbe(player) == true then
		deny(player, "stealing")
		return
	end
	local t = now()
	local _, untilT = StealRules.ProtectState(t, untilsOf(st))
	if untilT and untilT - t >= SHIELD.StackBelow then
		deny(player, "protected", nil, { t = StealRules.FormatClock(untilT - t) })
		return
	end
	if st.ReadyAt > t then
		deny(player, "cooldown", nil, { t = StealRules.FormatClock(st.ReadyAt - t) })
		return
	end
	local data = dataOf(player)
	if not data then
		deny(player, "loading")
		return
	end
	-- Менять (без ожиданий).
	local cycle = SHIELD.Duration + SHIELD.Cooldown
	st.Shield = t + SHIELD.Duration
	st.ReadyAt = t + cycle
	data.Upgrades.ShieldReadyAt = os.time() + cycle
	setAttr(player, "ShieldUntil", attrTime(st.Shield))
	setAttr(player, "ShieldReadyAt", attrTime(st.ReadyAt))
	DataService:SaveSoon(player)
	apply(st)
	sendDefence(player, "Shield", { Until = attrTime(st.Shield), ReadyAt = attrTime(st.ReadyAt) })
end

local function onBuy(player: Player, item: unknown)
	if type(item) ~= "string" or not ITEMS[item] then
		return -- незнакомое: молча
	end
	if not requests:Take(player) then
		return
	end
	local name = item :: string
	if not DataService:CanWrite(player) then
		deny(player, "loading", name)
		return
	end
	local st = states[player]
	local base = st and st.Base
	if not st or not base or not TankService:IsMounted(player) then
		deny(player, "nobase", name)
		return
	end
	local data = dataOf(player)
	if not data then
		deny(player, "loading", name)
		return
	end
	local price: number
	local level: number? = nil
	if name == "Lock" then
		local current = DefenceService:LockLevel(player)
		local _, answer = StealRules.NextLock(current, LOCK.SaleMax)
		if type(answer) ~= "number" then
			deny(player, if answer == "max" then "max" else "soon", name)
			return
		end
		price = answer
		level = current + 1
	else
		if PlayerData.Owned(data.Upgrades[name]) then
			deny(player, "owned", name)
			return
		end
		price = if name == "Dog" then DOG.Price else ALARM.Price
	end
	if not EconomyService:SpendMoney(player, price, "defence:" .. name) then
		deny(player, "money", name, { price = TankRules.FormatMoney(price) })
		return
	end
	if name == "Lock" then
		DefenceService:SetLockLevel(player, level :: number)
	elseif name == "Dog" then
		data.Upgrades.Dog = true
		setAttr(player, "HasDog", true)
		setAttr(base.Model, "HasDog", true)
		showDog(base)
	else
		data.Upgrades.Alarm = true
		setAttr(player, "HasAlarm", true)
		setAttr(base.Model, "HasAlarm", true)
		alarmed[base] = player
		startIntruders()
	end
	DataService:SaveSoon(player)
	sendDefence(player, "Bought", { Item = name, Level = level, Price = price })
end

--------------------------------------------------------------------------------
-- Игроки и базы
--------------------------------------------------------------------------------

local function onLoaded(player: Player, data: PlayerData.Data)
	if player.Parent ~= Players then
		return
	end
	local st = stateFor(player)
	if not st then
		return
	end
	loadInfo[player] = {
		SaveCount = if finite(data.SaveCount) then data.SaveCount else 0,
		LastOnline = if finite(data.LastOnline) then data.LastOnline else 0,
	}
	local cycle = SHIELD.Duration + SHIELD.Cooldown
	local savedReady = data.Upgrades.ShieldReadyAt
	local readyIn = if finite(savedReady) then math.clamp(savedReady - os.time(), 0, cycle) else 0
	st.ReadyAt = if readyIn > 0 then now() + readyIn else 0
	setAttr(player, "ShieldReadyAt", if readyIn > 0 then attrTime(st.ReadyAt) else nil)
	setAttr(player, "HasDog", DefenceService:HasDog(player))
	setAttr(player, "HasAlarm", DefenceService:HasAlarm(player))
	setAttr(player, "LockLevel", DefenceService:LockLevel(player))
end

local function onMounted(player: Player, base: Base)
	local st = states[player]
	if not st then
		local data = dataOf(player)
		if not data then
			return
		end
		onLoaded(player, data)
		st = states[player]
		if not st then
			return
		end
	end
	st.Base = base
	local model = base.Model
	local hasDog, hasAlarm = DefenceService:HasDog(player), DefenceService:HasAlarm(player)
	setAttr(model, "HasDog", hasDog)
	setAttr(model, "HasAlarm", hasAlarm)
	writeLock(player)
	if hasDog then
		showDog(base)
	end
	if hasAlarm then
		alarmed[base] = player
		startIntruders()
	end
	if not st.Mounted then
		st.Mounted = true
		joinProtect(st, now())
	end
	apply(st)
end

local function clearBase(base: Base)
	local model = base.Model
	for _, name in { "ProtectUntil", "ProtectKind", "HasDog", "HasAlarm", "LockLevel", "HoldTime" } do
		setAttr(model, name, nil)
	end
	if lampTokens[base] then
		lampTokens[base] = nil
		if model:GetAttribute("AlarmState") == "intruder" then
			model:SetAttribute("AlarmState", nil)
		end
	end
	alarmed[base] = nil
	hideDog(base)
end

local function onUnmounted(player: Player, base: Base)
	local st = states[player]
	if st and st.Base == base then
		st.Base = nil
		stop(st)
	end
	clearBase(base)
end

local function onPlayerRemoving(player: Player)
	leftAt[player.UserId] = now()
	local st = states[player]
	if st then
		stop(st)
		states[player] = nil
	end
	loadInfo[player] = nil
	requests:Forget(player)
	pruneMaps()
end

--------------------------------------------------------------------------------
-- Жизненный цикл сервиса
--------------------------------------------------------------------------------

function DefenceService:Init()
	defenceEvent = Net.Event("DefenceEvent")
	stealEvent = Net.Event("StealEvent")
	local knob = DefenceConfig.Debug.StudioProtect
	if RunService:IsStudio() and type(knob) == "number" then
		studioCap = knob
		print(TextUtil.fill(TEXTS.StudioPrint, { s = knob }))
	end
	for _, base in BaseService:GetBases() do
		rememberDog(base)
	end
end

function DefenceService:Start()
	DataService.Loaded:Connect(onLoaded)
	if TankService.Mounted then
		TankService.Mounted:Connect(onMounted)
	end
	if TankService.Unmounted then
		TankService.Unmounted:Connect(onUnmounted)
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	Net.Event("ShieldActivate").OnServerEvent:Connect(onShield)
	Net.Event("DefenceBuy").OnServerEvent:Connect(onBuy)
	-- Уже загруженные и подключённые (Studio: игрок успел раньше скрипта).
	for _, player in Players:GetPlayers() do
		local data = DataService:IsLoaded(player) and DataService:Get(player)
		if data then
			onLoaded(player, data)
			local base = BaseService:GetBase(player)
			if base and type(TankService.IsMounted) == "function" and TankService:IsMounted(player) then
				onMounted(player, base)
			end
		end
	end
end

return DefenceService
