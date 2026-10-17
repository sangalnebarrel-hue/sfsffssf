--!strict
--[[
	EconomyService — деньги игрока (Этап 3): ЕДИНСТВЕННЫЙ, кто пишет Money (и Stats.Earned /
	Stats.Spent) в данных игрока (DataService), таблица игроков (leaderstats) и атрибуты денег.
	Числа и названия — EconomyConfig, вид сумм — TankRules.FormatMoney.

	Что делает:
	  1. PlayerAdded: папка leaderstats — IntValue «Деньги» (первая: по ней сортируется список
	     игроков) и IntValue «Доход/с» (EconomyConfig.Leaderstats); пока данные грузятся — 0.
	  2. DataService.Loaded: атрибут Money и «Деньги» из данных, Income = 0 (настоящий доход
	     ставит TankService, когда садок подключится к базе); проверка книги (PlayerData.Ledger:
	     Money == StartMoney + Earned − Spent) — расхождение: один warn с обоими числами, никогда не
	     чинится (это ловушка дюпа и ошибок).
	  3. AddMoney / SpendMoney — только целые, конечные, > 0 суммы и только при
	     DataService:CanWrite (иначе false + warn: вызывающий уже проверил, так что false — ошибка);
	     Money обрезается на MaxMoney (лишнее не зачисляется — один warn за игру); меняет данные,
	     Stats.Earned (ровно зачисленное) / Stats.Spent, атрибут Money, «Деньги» и зовёт
	     MoneyChanged. SpendMoney без денег — просто false (это не ошибка: «не хватает»).
	  4. SetIncome — доход игрока от TankService (при изменении садка, не каждый тик): атрибут
	     Income ($/с, income10 / 10) и «Доход/с» (округлённо) — только если изменился.
	Записи игроков — по самому Player с проверкой «это всё ещё она» (DataService, «Правила»); своих
	соединений на игрока нет (leaderstats уходят вместе с игроком). Обработчики MoneyChanged —
	простые (Этап 5: значки «хватает денег»; ничего тяжёлого на каждый тик дохода).

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

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Shared = ReplicatedStorage.Shared
local EconomyConfig = require(Shared.Config.EconomyConfig)
local Signal = require(Shared.Util.Signal)
local PlayerData = require(ServerScriptService.Lib.PlayerData)
local DataService = require(ServerScriptService.Services.DataService)

type Record = {
	Player: Player,
	Money: IntValue, -- leaderstats «Деньги»
	Income: IntValue, -- leaderstats «Доход/с»
	Income10: number?, -- последний записанный доход (десятые в секунду)
	WarnedMax: boolean, -- уже предупреждали про MaxMoney
}

local MAX_MONEY = EconomyConfig.MaxMoney

local EconomyService = {
	MoneyChanged = Signal.new(), -- (player, money, delta, reason)
}

local records: { [Player]: Record } = {}

local function isAmount(amount: any): boolean
	return type(amount) == "number"
		and amount == amount
		and amount ~= math.huge
		and amount % 1 == 0
		and amount > 0
		and amount <= MAX_MONEY
end

-- Данные игрока, если их можно менять (ворота записи DataService), иначе nil.
local function writable(player: Player): PlayerData.Data?
	if not DataService:CanWrite(player) then
		return nil
	end
	return DataService:Get(player)
end

-- Деньги в атрибут и в таблицу игроков.
local function publish(player: Player, money: number)
	player:SetAttribute("Money", money)
	local rec = records[player]
	if rec then
		rec.Money.Value = money
	end
end

local function onPlayerAdded(player: Player)
	if records[player] then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "leaderstats"
	local money = Instance.new("IntValue")
	money.Name = EconomyConfig.Leaderstats.Money
	money.Value = 0
	money.Parent = folder
	local income = Instance.new("IntValue")
	income.Name = EconomyConfig.Leaderstats.Income
	income.Value = 0
	income.Parent = folder
	folder.Parent = player
	records[player] = { Player = player, Money = money, Income = income, Income10 = nil, WarnedMax = false }
end

local function onLoaded(player: Player, data: PlayerData.Data)
	if not records[player] then
		onPlayerAdded(player)
	end
	publish(player, data.Money)
	if player:GetAttribute("Income") == nil then
		EconomyService:SetIncome(player, 0)
	end
	local ok, expected = PlayerData.Ledger(data)
	if not ok then
		warn(
			`[EconomyService] книга денег игрока {player.UserId} не сходится: Money = {data.Money}, а StartMoney + Earned − Spent = {expected}`
		)
	end
end

local function onPlayerRemoving(player: Player)
	records[player] = nil
end

--------------------------------------------------------------------------------
-- Публичное API
--------------------------------------------------------------------------------

function EconomyService:GetMoney(player: Player): number
	local data = DataService:Get(player)
	return if data then data.Money else 0
end

function EconomyService:AddMoney(player: Player, amount: number, reason: string): boolean
	if not isAmount(amount) then
		warn(
			`[EconomyService] AddMoney({player.UserId}, {amount}, {reason}): сумма не целое число > 0`
		)
		return false
	end
	local data = writable(player)
	if not data then
		warn(`[EconomyService] AddMoney({player.UserId}, {amount}, {reason}): данные нельзя менять`)
		return false
	end
	local before = data.Money
	local after = before + amount
	if after > MAX_MONEY then
		after = MAX_MONEY
		local rec = records[player]
		if rec and not rec.WarnedMax then
			rec.WarnedMax = true
			warn(
				`[EconomyService] игрок {player.UserId} упёрся в MaxMoney ({MAX_MONEY}) — лишнее не зачислено`
			)
		end
	end
	local delta = after - before
	data.Money = after
	data.Stats.Earned += delta
	publish(player, after)
	EconomyService.MoneyChanged:Fire(player, after, delta, reason)
	return true
end

function EconomyService:SpendMoney(player: Player, amount: number, reason: string): boolean
	if not isAmount(amount) then
		warn(
			`[EconomyService] SpendMoney({player.UserId}, {amount}, {reason}): сумма не целое число > 0`
		)
		return false
	end
	local data = writable(player)
	if not data then
		warn(`[EconomyService] SpendMoney({player.UserId}, {amount}, {reason}): данные нельзя менять`)
		return false
	end
	if data.Money < amount then
		return false -- не хватает (это не ошибка)
	end
	local after = data.Money - amount
	data.Money = after
	data.Stats.Spent += amount
	publish(player, after)
	EconomyService.MoneyChanged:Fire(player, after, -amount, reason)
	return true
end

function EconomyService:CanAfford(player: Player, amount: number): boolean
	local data = writable(player)
	return data ~= nil and type(amount) == "number" and amount == amount and data.Money >= amount
end

function EconomyService:SetIncome(player: Player, income10: number)
	local rec = records[player]
	if rec and rec.Income10 == income10 then
		return
	end
	if rec then
		rec.Income10 = income10
		rec.Income.Value = math.round(income10 / 10)
	end
	player:SetAttribute("Income", income10 / 10)
end

-- Тесты: деньги ровно n; Earned / Spent двигаются вместе с ними — книга сходится.
function EconomyService:SetMoneyForTest(player: Player, money: number)
	local data = DataService:Get(player)
	if not data then
		return
	end
	local delta = money - data.Money
	if delta > 0 then
		data.Stats.Earned += delta
	else
		data.Stats.Spent -= delta
	end
	data.Money = money
	publish(player, money)
	EconomyService.MoneyChanged:Fire(player, money, delta, "test")
end

function EconomyService._debugSizes(): { [string]: number }
	local n = 0
	for _ in records do
		n += 1
	end
	return { Records = n }
end

--------------------------------------------------------------------------------
-- Жизненный цикл сервиса
--------------------------------------------------------------------------------

function EconomyService:Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	DataService.Loaded:Connect(onLoaded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return EconomyService
