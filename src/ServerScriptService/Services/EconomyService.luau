--!strict
--[[
	EconomyService — деньги игрока (Этап 3): ЕДИНСТВЕННЫЙ, кто пишет Money (и Stats.Earned /
	Stats.Spent) в данных игрока (DataService), таблица игроков (leaderstats) и атрибуты денег.
	Числа и названия — EconomyConfig, вид сумм — TankRules.FormatMoney.
	ЗАГЛУШКА (волна 0): API ниже, поведения ещё нет — GetMoney = 0, AddMoney / SpendMoney /
	CanAfford = false, MoneyChanged не срабатывает. Реализация — волна 1 (scratchpad design.md,
	§4.4).

	Что делает:
	  1. PlayerAdded: папка leaderstats — IntValue «Деньги» (первая: по ней сортируется список
	     игроков) и IntValue «Доход/с» (EconomyConfig.Leaderstats).
	  2. DataService.Loaded: атрибут Money и «Деньги» из данных; проверка книги
	     (PlayerData.Ledger: Money == StartMoney + Earned − Spent) — расхождение: один warn с обоими
	     числами, никогда не чинится (это ловушка дюпа и ошибок).
	  3. AddMoney / SpendMoney — только целые, конечные, > 0 суммы и только при
	     DataService:CanWrite (иначе false + warn: вызывающий уже проверил, так что false — ошибка);
	     Money обрезается на MaxMoney (лишнее — один warn); меняет данные, Stats.Earned /
	     Stats.Spent, атрибут Money, «Деньги» и зовёт MoneyChanged.
	  4. SetIncome — доход игрока от TankService (при изменении садка, не каждый тик): атрибут
	     Income ($/с, income10 / 10) и «Доход/с» (округлённо).
	Записи игроков — по самому Player с проверкой «это всё ещё она» (DataService, «Правила»);
	обработчики MoneyChanged — простые (Этап 5: значки «хватает денег»; ничего тяжёлого на
	каждый тик дохода).

	Атрибуты Player: Money (целое), Income ($/с, с десятыми). leaderstats: «Деньги», «Доход/с».
	В тестах деньги < 2^24 (Lune хранит целые атрибуты как float32) или читаются из leaderstats.

	API:
	  EconomyService:GetMoney(player) -> number
	  EconomyService:AddMoney(player, amount, reason) -> boolean      -- reason: "income" | "sell" |
	                                                                   -- "autosell" | …
	  EconomyService:SpendMoney(player, amount, reason) -> boolean    -- Этап 5 (Stats.Spent)
	  EconomyService:CanAfford(player, amount) -> boolean
	  EconomyService:SetIncome(player, income10)                       -- TankService
	  EconomyService.MoneyChanged    -- Signal (player, money, delta, reason)
	  EconomyService:SetMoneyForTest(player, n)   -- тесты: двигает и Earned / Spent (книга сходится)
	  EconomyService._debugSizes()                -- тесты: после выхода всех — нули
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Util.Signal)

local EconomyService = {
	MoneyChanged = Signal.new(), -- (player, money, delta, reason)
}

function EconomyService:Init() end

function EconomyService:Start() end

function EconomyService:GetMoney(_player: Player): number
	return 0
end

function EconomyService:AddMoney(_player: Player, _amount: number, _reason: string): boolean
	return false
end

function EconomyService:SpendMoney(_player: Player, _amount: number, _reason: string): boolean
	return false
end

function EconomyService:CanAfford(_player: Player, _amount: number): boolean
	return false
end

function EconomyService:SetIncome(_player: Player, _income10: number) end

function EconomyService:SetMoneyForTest(_player: Player, _money: number) end

function EconomyService._debugSizes(): { [string]: number }
	return { Records = 0 }
end

return EconomyService
