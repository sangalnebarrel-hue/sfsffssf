--!strict
--[[
	DefenceService — защита базы (Этап 4): щит, бесплатные защиты (вход, «новичок», после кражи,
	«садок отдыхает»), покупки собаки, сигнализации и замка, показ собаки во дворе, раннее
	предупреждение о госте (сигнализация). Числа и тексты — DefenceConfig (и StealConfig.Limits),
	данные — DataService (поля LockLevel, Upgrades.Dog / Alarm / ShieldReadyAt — его).
	Подробно — docs/stage4_design.md, §2, §4.1, §4.10, §4.11.

	Что делает (Wave 1 A; волна 0 — контракт: шапка и подписи API, поведения нет):
	  1. Защита базы — одна на базу: ProtectUntil = позднейшая из щита, защиты входа / новичка,
	     «после кражи» и «отдыха»; ProtectKind — та, что кончается позже (StealRules.ProtectState).
	     Конец — один task.delay на базу с номером поколения: атрибуты сняты, ProtectionChanged,
	     владельцу «Щит погас» (только щит).
	  2. Щит (ShieldActivate, проверки — шапка RemoteNames): ShieldUntil = сейчас + Duration,
	     ShieldReadyAt = сейчас + Duration + Cooldown (и Upgrades.ShieldReadyAt = os.time() + …,
	     SaveSoon); ProtectionChanged — StealService отменяет удержание и возвращает несомую рыбу.
	     При загрузке: до готовности = clamp(ShieldReadyAt − os.time(), 0, Duration + Cooldown);
	     включённый щит не сохраняется (кончается с игрой).
	  3. Защита входа — на первом подключении садка за игру (TankService.Mounted), что первым
	     подошло: быстрый перезаход (LastOnline при загрузке или leftAt этого сервера новее
	     QuickRejoin) — QuickRejoinProtect, kind "join"; новое сохранение (SaveCount == 0 при
	     загрузке) — JoinProtectFirst, kind "newbie"; иначе JoinProtect, "join". Что нужно, —
	     loadInfo[player] = { SaveCount, LastOnline }, снятое в DataService.Loaded (до первого
	     сохранения игры).
	  4. После кражи (GiveAfterTheft): losses[UserId] (окно VictimWindow), after = сейчас +
	     VictimImmunity; вторая кража за окно — rest до (VictimMax-я с конца) + VictimWindow.
	     Следующая игра на этом сервере снова ставит идущие after / rest из того же списка.
	  5. EndProtection(player, "stealing") — начал красть сам: все виды сняты и его losses
	     забыты (ShieldReadyAt не возвращается), уведомление «Твоя защита снята…».
	  6. Покупки (DefenceBuy): цена только из DefenceConfig, EconomyService:SpendMoney(…,
	     "defence:<item>"), Upgrades / SetLockLevel, атрибуты, SaveSoon, DefenceEvent("Bought").
	     Собака показана на базе владельца (все детали видны, будка твёрдая, Dog.Pup:PivotTo на
	     Dog.Rest), снята при отключении (вид шаблона и его pivot щенка).
	  7. Гость во дворе (сигнализация): цикл раз в Alarm.IntruderEvery с, только пока есть база с
	     сигнализацией; не под защитой; раз в IntruderCoalesce с на пару (гость, хозяин):
	     StealEvent("Intruder") хозяину и AlarmState = "intruder" на Alarm.IntruderLamp с.
	  8. Studio (DC-20): RunService:IsStudio() и Debug.StudioProtect — число → вход / новичок /
	     после кражи / отдых не дольше него (щит — как есть); одна строка print при Init
	     (Texts.StudioPrint), не warn.
	StealService этот модуль НЕ требует (иначе цикл require — ошибка Roblox): «крадёт ли он сам»
	спрашивает через SetStealProbe (StealService регистрирует IsStealing в своём Init; без него —
	«никто не крадёт»). Каждый вызов другого сервиса — за type(...) == "function" (заглушки
	сервисов в тестах клиента). Записи игроков — по самому Player (повторный вход — новый Player),
	чистятся в PlayerRemoving; карты по UserId (losses, leftAt, intruderSeen) — с границей по
	времени, чистятся при каждой записи, в PlayerRemoving и в _debugSizes.

	Атрибуты (RemoteNames, «Кража и защита»): Player — ShieldUntil, ShieldReadyAt, HasDog, HasAlarm,
	LockLevel; база — ProtectUntil, ProtectKind, HasDog, HasAlarm, LockLevel, HoldTime (сняты при
	отключении садка); Dog — Unlocked.
	Remote'ы: ShieldActivate, DefenceBuy (клиент → сервер), DefenceEvent (сервер → клиент).

	API:
	  DefenceService:IsProtected(player) -> (kind?, until?)   -- защита его базы сейчас
	  DefenceService:EndProtection(player, reason)            -- снять все виды и забыть его losses
	  DefenceService:GiveAfterTheft(victim)                   -- after 90 с, rest на 2-й краже за 600 с
	  DefenceService:HasDog(player) -> boolean
	  DefenceService:HasAlarm(player) -> boolean
	  DefenceService:LockLevel(player) -> number              -- в игре — min(LockLevel, #Levels)
	  DefenceService:HoldTime(player) -> number               -- StealRules.HoldTime(LockLevel)
	  DefenceService:SetLockLevel(player, n) -> boolean       -- за CanWrite; атрибуты; LockChanged
	                                                          -- (магазин Этапа 5 зовёт его же)
	  DefenceService.SetStealProbe(fn: (Player) -> boolean)   -- кто сейчас крадёт (StealService)
	  DefenceService.ProtectionChanged, DefenceService.LockChanged   -- Signal (player, base)
	  DefenceService._debugSizes()   -- Protections, Buckets, LoadInfo + Losses, LeftAt, IntruderSeen
	  DefenceService._isStealing(player) -> boolean   -- тесты и отказ "stealing": ответ пробы
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Signal = require(Shared.Util.Signal)
local StealRules = require(Shared.StealRules)

local DefenceService = {
	ProtectionChanged = Signal.new(), -- (player, base)
	LockChanged = Signal.new(), -- (player, base)
}

-- Кто сейчас крадёт (StealService:IsStealing через SetStealProbe); по умолчанию — никто.
local stealProbe: (player: Player) -> boolean = function(_player: Player): boolean
	return false
end

--------------------------------------------------------------------------------
-- Публичное API (волна 0: подписи; тела — Wave 1 A)
--------------------------------------------------------------------------------

function DefenceService:IsProtected(_player: Player): (string?, number?)
	return nil, nil
end

function DefenceService:EndProtection(_player: Player, _reason: string) end

function DefenceService:GiveAfterTheft(_victim: Player) end

function DefenceService:HasDog(_player: Player): boolean
	return false
end

function DefenceService:HasAlarm(_player: Player): boolean
	return false
end

function DefenceService:LockLevel(_player: Player): number
	return 0
end

function DefenceService:HoldTime(player: Player): number
	return StealRules.HoldTime(DefenceService:LockLevel(player))
end

function DefenceService:SetLockLevel(_player: Player, _level: number): boolean
	return false
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
	return {
		Protections = 0,
		Buckets = 0,
		LoadInfo = 0,
		Losses = 0,
		LeftAt = 0,
		IntruderSeen = 0,
	}
end

--------------------------------------------------------------------------------
-- Жизненный цикл сервиса
--------------------------------------------------------------------------------

function DefenceService:Init() end

function DefenceService:Start() end

return DefenceService
