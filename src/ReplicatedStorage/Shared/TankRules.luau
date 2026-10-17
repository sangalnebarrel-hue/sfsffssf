--!strict
--[[
	TankRules — правила садка и денег (Этап 3), общие для сервера и клиента (чистые функции, без
	состояния). Сервер считает по ним доход и цену продажи, клиент — то, что показывает (панель
	садка, надписи над витринами, кошелёк): одна формула и одни часы
	(workspace:GetServerTimeNow) — цена в панели совпадает с серверной до монеты (кроме задержки
	сети на возрасте рыбы). Числа — TankConfig и EconomyConfig.

	  Growth(age)                 = 1 + (Cap − 1) · clamp(age / Time, 0, 1) — во сколько раз
	                                выросла цена рыбы за age секунд в садке (TankConfig.Growth)
	  CurrentValue(value, age)    = floor(value · Growth(age) · SellScalePct / 100) — цена сейчас
	                                (value — цена ×1, FishingRules.Price)
	  SellPrice(value, age, ratePct) = max(1, CurrentValue(value, age) · ratePct // 100) — сколько
	                                заплатят: ставка места — целые проценты (45 при 150 % → 67,
	                                54 → 81, без «0.999…»)
	  IsMaxed(age)                — age ≥ Time: цена больше не растёт («МАКС»)
	  AgeAt(growFrom, now)        — возраст рыбы в садке по атрибуту витрины GrowFrom:
	                                clamp(now − growFrom, 0, Time)
	  Income10(income)            = round(income · IncomeScale · 10) — доход рыбы в десятых монеты
	                                в секунду (целое: сумма за тик без ошибок округления)
	  ChooseReplacement(list, newIncome10) -> uid? — садок полон: кого заменит новая рыба. Самая
	                                слабая по доходу из активных (не Locked и не Dormant), при
	                                равенстве — дешевле сейчас, потом дольше в садке, потом
	                                раньше поймана (меньший номер); nil — новая не сильнее её
	                                (новую продают сразу). Рыба с большим доходом не заменяется
	                                никогда.
	  UidOf(n) / UidNumber(uid)   — номер рыбы в садке: 7 ↔ "f7" (TankConfig.Uid); UidNumber —
	                                nil, если это не номер рыбы (не строка, не «f + цифры», длиннее
	                                Uid.MaxLength) — так сервер проверяет TankSell(uid)
	  FormatMoney(n)              → «$0», «$1 234», «$999 999», «$1M», «$1.23M», «$12.3M», «$123M»,
	                                «$1.5B», …, «Qa»: до EconomyConfig.Format.ShortFrom — все цифры
	                                с неразрывными пробелами (FishingRules.FormatCoins), дальше — 3
	                                значащие цифры вниз (не завышаем), нули в конце не пишутся;
	                                меньше нуля — «−$5»; NaN и бесконечность → «$0»
	                                (string.format("%d") на них падает)
	  FormatRate(income10)        → «+$0.8/с», «+$4/с», «+$42/с», «+$1 234/с», «+$1.2M/с» (до $10 — с
	                                десятыми через точку, как «M»; дальше — целые вниз); меньше
	                                нуля — «−$4/с» (красная вспышка карточки при «ТОЧНО?»)
	  AttrTime(t)                 — время для атрибута: к целому числу +1/1024 с. Lune (симулятор)
	                                хранит целые атрибуты как float32 (1700000123 → 1700000128, а
	                                1700000123.5 — точно); 1/1024 — двоичная дробь, в Roblox ошибка
	                                меньше 1 мс (RemoteNames, «Время в атрибутах»)
	Не конечные цена или возраст дают не конечный ответ (кроме Format*): проверяет вызывающий
	(TankService: «цена не число → warn, продажи нет»).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TankConfig = require(Config:WaitForChild("TankConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local FishingRules = require(Shared:WaitForChild("FishingRules"))

-- Рыба-кандидат на замену (TankService: активные рыбы садка).
export type Candidate = {
	Uid: string,
	Income10: number,
	Value: number, -- цена ×1 (FishingRules.Price)
	Age: number, -- секунд в садке
	Locked: boolean?, -- (Этап 4) её сейчас крадут
	Dormant: boolean?, -- «спит»: незнакомый вид или нет своей витрины
}

local GROWTH = TankConfig.Growth
local FORMAT = EconomyConfig.Format
local UID_PREFIX = TankConfig.Uid.Prefix
local UID_MAX = TankConfig.Uid.MaxLength
local UID_PATTERN = "^" .. UID_PREFIX .. "(%d+)$"
-- Запас перед floor на ошибку двоичной дроби: 10 · 1.4 = 13.999999999999998 — это 14.
local EPS = 1e-6
-- Добавка к целому времени атрибута (AttrTime, см. шапку).
local ATTR_NUDGE = 1 / 1024
local MINUS = "−" -- U+2212, как FishingRules.FormatCoins

local TankRules = {}

local function finite(x: number): boolean
	return x == x and x ~= math.huge and x ~= -math.huge
end

--------------------------------------------------------------------------------
-- Цена и доход
--------------------------------------------------------------------------------

function TankRules.Growth(age: number): number
	return 1 + (GROWTH.Cap - 1) * math.clamp(age / GROWTH.Time, 0, 1)
end

function TankRules.CurrentValue(value: number, age: number): number
	return math.floor(value * TankRules.Growth(age) * EconomyConfig.SellScalePct / 100 + EPS)
end

function TankRules.SellPrice(value: number, age: number, ratePct: number): number
	local price = TankRules.CurrentValue(value, age) * ratePct // 100
	if price ~= price then
		return price -- NaN не превращается в «1 монету»: его видит TankService
	end
	return math.max(1, price)
end

function TankRules.IsMaxed(age: number): boolean
	return age >= GROWTH.Time
end

function TankRules.AgeAt(growFrom: number, now: number): number
	return math.clamp(now - growFrom, 0, GROWTH.Time)
end

function TankRules.Income10(income: number): number
	return math.round(income * EconomyConfig.IncomeScale * 10)
end

--------------------------------------------------------------------------------
-- Номера рыб и полный садок
--------------------------------------------------------------------------------

function TankRules.UidOf(n: number): string
	return UID_PREFIX .. string.format("%d", n)
end

function TankRules.UidNumber(uid: any): number?
	if type(uid) ~= "string" or #uid > UID_MAX then
		return nil
	end
	local digits = string.match(uid, UID_PATTERN)
	return if digits then tonumber(digits) else nil
end

-- a слабее b? (доход, потом цена сейчас, потом дольше в садке, потом меньший номер)
local function weaker(a: Candidate, aValue: number, b: Candidate, bValue: number): boolean
	if a.Income10 ~= b.Income10 then
		return a.Income10 < b.Income10
	elseif aValue ~= bValue then
		return aValue < bValue
	elseif a.Age ~= b.Age then
		return a.Age > b.Age
	end
	local an, bn = TankRules.UidNumber(a.Uid), TankRules.UidNumber(b.Uid)
	if an and bn and an ~= bn then
		return an < bn
	end
	return a.Uid < b.Uid
end

function TankRules.ChooseReplacement(list: { Candidate }, newIncome10: number): string?
	local weakest: Candidate? = nil
	local weakestValue = 0
	for _, fish in list do
		if fish.Locked or fish.Dormant then
			continue
		end
		local value = TankRules.CurrentValue(fish.Value, fish.Age)
		if weakest == nil or weaker(fish, value, weakest, weakestValue) then
			weakest, weakestValue = fish, value
		end
	end
	if weakest and newIncome10 > weakest.Income10 then
		return weakest.Uid
	end
	return nil
end

--------------------------------------------------------------------------------
-- Как писать суммы
--------------------------------------------------------------------------------

function TankRules.FormatMoney(n: number): string
	local currency = FORMAT.Currency
	if not finite(n) then
		return currency .. "0"
	end
	local sign = if n < 0 then MINUS else ""
	local whole = math.floor(math.abs(n))
	if whole < FORMAT.ShortFrom then
		return sign .. currency .. FishingRules.FormatCoins(whole)
	end
	-- Самая крупная единица, что не больше суммы (до первой — первая: ShortFrom меньше её).
	local suffixes = FORMAT.Suffixes
	local unit = suffixes[1]
	for _, candidate in suffixes do
		if whole >= candidate.Unit then
			unit = candidate
		end
	end
	local lead = whole / unit.Unit
	local decimals = if lead < 10 then 2 elseif lead < 100 then 1 else 0
	local scale = 10 ^ decimals
	-- (Целые делятся точно: unit.Unit / scale — целое, sum < 2^53.)
	local kept = math.floor(whole / (unit.Unit / scale))
	local text = FishingRules.FormatCoins(kept // scale)
	local fraction = kept % scale
	if fraction > 0 then
		local digits = string.format("%0" .. tostring(decimals) .. "d", fraction)
		text ..= "." .. (string.gsub(digits, "0+$", ""))
	end
	return sign .. currency .. text .. unit.Text
end

function TankRules.FormatRate(income10: number): string
	local currency, per = FORMAT.Currency, FORMAT.Rate
	if not finite(income10) then
		return "+" .. currency .. "0" .. per
	end
	local tenths = math.round(income10)
	local sign = if tenths < 0 then MINUS else "+"
	tenths = math.abs(tenths)
	if tenths < 100 then
		local whole, tenth = tenths // 10, tenths % 10
		local text = string.format("%d", whole)
		if tenth > 0 then
			text ..= "." .. string.format("%d", tenth)
		end
		return sign .. currency .. text .. per
	end
	return sign .. TankRules.FormatMoney(tenths // 10) .. per
end

function TankRules.AttrTime(t: number): number
	return if t % 1 == 0 then t + ATTR_NUDGE else t
end

return TankRules
