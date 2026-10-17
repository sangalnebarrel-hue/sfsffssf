--!strict
--[[
	MarketService — ларьки «ПРОДАТЬ РЫБУ» (Этап 3): рынок на острове и 4 ларька на мостах
	(EconomyConfig.SellPoints) — их кнопки и ставка продажи игрока по проверкам сервера.
	ЗАГЛУШКА (волна 0): API ниже, поведения ещё нет — RatePct всегда HomeRatePct, Sample ничего
	не делает. Реализация — волна 1 (scratchpad design.md, §4.4).

	Что делает:
	  1. Start: для каждого ларька SellPoints (Attachment по Path; нет — один warn и дальше)
	     ProximityPrompt "SellPrompt": ActionText «Продать рыбу», ObjectText «Рыбный рынок · +50%» /
	     «Ларёк · +50%» (EconomyConfig.Prompt), HoldDuration 0.25, MaxActivationDistance 10,
	     RequiresLineOfSight false.
	  2. Sample(player) — зовёт TankService из своего цикла раз в секунду (не каждый кадр): позиция
	     HumanoidRootPart (FindFirstChild, без ожиданий); скачок с прошлой проверки дальше
	     WalkSpeed × dt × MarketJump.SpeedFactor + MarketJump.Slack — счёт обнуляется (телепорт: «к
	     ларьку и сразу продать» — по ×1; законные телепорты — «Домой», возрождение — только
	     уводят от ларьков); в Range ларька — dwell + 1, иначе 0. SellRatePct = MarketRatePct, если
	     dwell ≥ MarketDwell и игрок всё ещё в Range, иначе HomeRatePct; атрибуты SellRatePct /
	     SellPlace — только при изменении.
	  3. RatePct(player) -> (ratePct, pointId?) — ставка по проверкам + живая проверка расстояния
	     до того же ларька; никогда не ждёт (TankService зовёт её в миг продажи).
	  4. Нажатие кнопки ларька — через лимит запросов игрока (TankConfig.Requests), проверка
	     расстояния сервером (не дальше MaxDistance + Slack), потом TankEvent("Open", { Place =
	     Id ларька, RatePct = сейчас, Name }) — только открыть панель; цену в миг продажи решает
	     RatePct.
	Записи игроков — по самому Player с проверкой «это всё ещё она» (DataService, «Правила»).

	Атрибуты Player: SellRatePct (100 | 150), SellPlace ("" | "Market" | "Kiosk1".."Kiosk4").

	API:
	  MarketService:Sample(player)                 -- TankService, раз в секунду
	  MarketService:RatePct(player) -> (number, string?)
	  MarketService._debugSizes()                  -- тесты: после выхода всех — нули
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyConfig = require(ReplicatedStorage.Shared.Config.EconomyConfig)

local MarketService = {}

function MarketService:Init() end

function MarketService:Start() end

function MarketService:Sample(_player: Player) end

function MarketService:RatePct(_player: Player): (number, string?)
	return EconomyConfig.HomeRatePct, nil
end

function MarketService._debugSizes(): { [string]: number }
	return { Records = 0 }
end

return MarketService
