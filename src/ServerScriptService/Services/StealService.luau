--!strict
--[[
	StealService — кража (Этап 4): кнопки «Украсть» у витрин, удержание, вынос рыбы за ограду,
	касание хозяина, проверка скорости, собака, тревога жертве, ожидания и честные лимиты.
	Числа и тексты — StealConfig (защиты — DefenceConfig), проверки начала — Shared/TheftChecks,
	переход рыбы между садками — TankService:StealFish (только он; здесь — ни одной записи данных).
	Подробно — docs/stage4_design.md, §1, §4.2–§4.9.

	Что делает (Wave 1 A; волна 0 — контракт: шапка и подписи API, поведения нет):
	  1. Init: у каждой витрины каждой базы (Tank.Slots.Slot_K.Pedestal.PromptAttachment) —
	     ProximityPrompt "StealPrompt": ActionText «Украсть», HoldDuration по замку хозяина,
	     MaxActivationDistance StealConfig.Prompt.MaxDistance (сервер больше его не пишет: это
	     свойство — фильтра клиента, BE-14), RequiresLineOfSight = false, Exclusivity
	     OnePerButton, E / ButtonX, Enabled = false. Enabled = «садок подключён и в витрине рыба»
	     (TankService.SlotChanged / Mounted / Unmounted), ObjectText «Окунь · +$4/с», HoldDuration
	     = DefenceService:HoldTime(хозяин) — кроме кнопки, которую держат (получит в конце).
	  2. PromptButtonHoldBegan → проверки Shared/TheftChecks по порядку (отказ — StealEvent
	     "Denied" с Quiet для повтора), начало: TankService:SetSteal(…, "hold"),
	     DefenceService:EndProtection(вор, "stealing"), первая уборка кражи — Lib/Speed.ClearAll,
	     атрибуты базы Thief / AlarmState = "theft" и игрока Stealing = "hold" (последним),
	     собака просыпается (Lib/DogBrain), StealEvent "Hold" вору и "Alert" жертве. Время
	     удержания считает сервер: Need = HoldTime при начале, Triggered раньше Need − Tolerance —
	     "early"; отпустил — "released" / "far" / "died" по состоянию в этот миг; нет Triggered к
	     Need + Deadline — "deadline".
	  3. Удержание кончилось → вынос: SetSteal(…, "carry"), FishingService:DropHeldFish(вор),
	     Lib/HeldRig.Build(…, "StolenFish") (+ Owner), Lib/Speed "Carry", Lib/CarryGuard на
	     полном бюджете, Stealing = "carry", StealEvent "Carry" и "Alert" { Phase = "carry" }.
	  4. Наблюдатель — ОДИН цикл task.wait(StealConfig.Tick), только пока идёт хоть одна кража
	     или бежит собака (сам кончается — без покадровой работы в простое): жив, радиус, хозяин
	     пишет данные, защита базы (щит вернёт рыбу), касание хозяина (Tag.Range), время, бюджет
	     скорости (Lib/CarryGuard), выход за ограду (StealRules.InPlot + ExitMargin, бюджет ≥ 0)
	     → TankService:StealFish; собаки (Lib/DogBrain; укус — Lib/Speed "Dog" на SlowLinger).
	  5. Конец кражи: Ended — первым (второй конец ничего не делает), уборка (скорость — первой),
	     атрибуты сняты (Stealing — последним), лампа гаснет через Alarm.Linger, собака — домой;
	     ожидания вора (своя вина — FailCooldown по счёту за FailWindow, "early" — последний
	     шаг, пойман — ещё TagCooldown на этой базе; щит / ушёл хозяин / садок полон — без
	     ожидания); StealEvent "Cancel" / "Done" вору, "Saved" / "Lost" жертве (Quiet — удержание
	     короче QuietSavedUnder).
	  6. «ДОМОЙ» (BaseService:SetHomeGuard): с рыбой на голове — отказ «Сначала унеси рыбу за
	     ограду!»; у хозяина идёт кража — на площадку лицом во двор.
	  7. DefenceService.SetStealProbe(IsStealing) — в Init: защита спрашивает, не крадёт ли
	     игрок сам, не требуя этот модуль (иначе цикл require).
	Записи — по самому Player с проверкой «это всё ещё она»; соединения — одно на
	ProximityPromptService (три события), ни одного на кнопку; карты по UserId (cooldowns, fails,
	tagged, alertCoalesce) — с границей по времени, чистятся при записи, в PlayerRemoving и в
	_debugSizes. Каждый вызов другого сервиса — за type(...) == "function".

	Атрибуты (RemoteNames, «Кража и защита»): Player — Stealing, StealCooldownUntil (Slowed пишет
	Lib/Speed); база — Thief, AlarmState; персонаж — модель StolenFish.
	Remote: StealEvent (сервер → клиент; протокол — шапка RemoteNames).

	API:
	  StealService:IsStealing(player) -> "hold" | "carry" | nil
	  StealService:TheftOn(base) -> { Thief, Victim, Slot, Phase }?
	  StealService:Cancel(player, reason)          -- BindToClose и тесты
	  StealService.TheftStarted, StealService.TheftEnded   -- Signal (thief, victim, result):
	                                               -- result = "credited" | причина отмены
	  StealService._debugSizes()                   -- Thefts, Buckets + Cooldowns, Fails, Tags, Alerts
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)
local DefenceService = require(ServerScriptService.Services.DefenceService)

export type TheftView = {
	Thief: Player,
	Victim: Player,
	Slot: number,
	Phase: "hold" | "carry",
}

local StealService = {
	TheftStarted = Signal.new(), -- (thief, victim, result)
	TheftEnded = Signal.new(), -- (thief, victim, result)
}

--------------------------------------------------------------------------------
-- Публичное API (волна 0: подписи; тела — Wave 1 A)
--------------------------------------------------------------------------------

function StealService:IsStealing(_player: Player): ("hold" | "carry")?
	return nil
end

function StealService:TheftOn(_base: any): TheftView?
	return nil
end

function StealService:Cancel(_player: Player, _reason: string) end

function StealService._debugSizes(): { [string]: number }
	return {
		Thefts = 0,
		Buckets = 0,
		Cooldowns = 0,
		Fails = 0,
		Tags = 0,
		Alerts = 0,
	}
end

--------------------------------------------------------------------------------
-- Жизненный цикл сервиса
--------------------------------------------------------------------------------

function StealService:Init()
	if type(DefenceService.SetStealProbe) == "function" then
		DefenceService.SetStealProbe(function(player: Player): boolean
			return StealService:IsStealing(player) ~= nil
		end)
	end
end

function StealService:Start() end

return StealService
