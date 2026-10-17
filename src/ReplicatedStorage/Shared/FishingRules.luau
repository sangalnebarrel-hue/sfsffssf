--!strict
--[[
	FishingRules — правила рыбалки, общие для сервера и клиента (чистые функции, без состояния).

	Сервер решает всё сам (какая рыба, попал ли игрок в зону); клиент пользуется теми же
	функциями только для отрисовки (стрелка мини-игры, цвета редкости, названия), поэтому
	то, что видит игрок, совпадает с тем, что проверяет сервер.

	Стрелка мини-игры: Needle(u0, speed, t) — положение 0..1 на полосе через t секунд после
	старта; u0 — фаза старта 0..2 (0..1 — едет вправо из точки u0, 1..2 — едет влево из 2 − u0),
	движение «туда-обратно» с постоянной скоростью speed полос в секунду.

	Описание пойманной рыбы (FishData) — обычная таблица (её можно отправить клиенту):
	  { Id = "Perch", Rarity = "Common", Mutation = "Gold" | nil, Kg = 1.23, Value = 35, Income = 3.5 }
	(Mutation — Id из FishConfig.Mutations; Value и Income уже с размером и мутацией.)
	Этап 3: в "Caught" у рыбы ещё два необязательных поля — Uid (номер рыбы в садке игрока, "f7";
	нет — рыба в садок не легла) и New (true — первый улов этого вида за всё время, для
	«НОВИНКА!»). В DataStore рыба хранится по-своему (PlayerData: Uid, Id, Kg, Mutation, Age,
	Slot, CaughtAt) — Rarity, Value и Income сервер каждый раз считает заново (Price).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local FishConfig = require(Config:WaitForChild("FishConfig"))
local FishingConfig = require(Config:WaitForChild("FishingConfig"))
local RodConfig = require(Config:WaitForChild("RodConfig"))

export type FishData = {
	Id: string,
	Rarity: string,
	Mutation: string?,
	Kg: number,
	Value: number,
	Income: number,
	Uid: string?, -- (Этап 3, только в "Caught") номер рыбы в садке игрока
	New: boolean?, -- (Этап 3, только в "Caught") первый улов этого вида за всё время
}

export type Rng = { NextNumber: (self: any, min: number?, max: number?) -> number }

local FishingRules = {}

local rarityById: { [string]: FishConfig.Rarity } = {}
for _, rarity in FishConfig.Rarities do
	rarityById[rarity.Id] = rarity
end
local fishById: { [string]: FishConfig.Fish } = {}
for _, fish in FishConfig.Fish do
	fishById[fish.Id] = fish
end
local mutationById: { [string]: FishConfig.Mutation } = {}
for _, mutation in FishConfig.Mutations do
	mutationById[mutation.Id] = mutation
end
local rodById: { [string]: RodConfig.Rod } = {}
for _, rod in RodConfig.Rods do
	rodById[rod.Id] = rod
end

--------------------------------------------------------------------------------
-- Справочники
--------------------------------------------------------------------------------

function FishingRules.GetRarity(id: string): FishConfig.Rarity?
	return rarityById[id]
end

function FishingRules.GetFish(id: string): FishConfig.Fish?
	return fishById[id]
end

function FishingRules.GetMutation(id: string): FishConfig.Mutation?
	return mutationById[id]
end

-- Удочка по Id; неизвестный Id — стартовая удочка.
function FishingRules.GetRod(id: string?): RodConfig.Rod
	return (id and rodById[id]) or rodById[RodConfig.StartRod]
end

-- Сколько секунд пойманная рыба этой редкости висит над головой рыбака (после прыжка);
-- неизвестная редкость — как обычная.
function FishingRules.HoldFishTime(rarity: string): number
	local times = FishingConfig.HoldFishTime
	return times[rarity] or times.Common
end

-- Правила мини-игры для редкости.
function FishingRules.GetMinigameRule(rarity: string): FishingConfig.MinigameRule
	return FishingConfig.Minigame[rarity] or FishingConfig.Minigame.Common
end

-- Ширина зелёной зоны для рыбы этой редкости и удочки (не шире 0.9 полосы).
function FishingRules.ZoneWidth(rarity: string, rodId: string?): number
	local rule = FishingRules.GetMinigameRule(rarity)
	return math.min(0.9, rule.ZoneWidth + FishingRules.GetRod(rodId).ZoneBonus)
end

-- Название рыбы для интерфейса: «Карасик».
function FishingRules.DisplayName(fish: FishData): string
	local def = fishById[fish.Id]
	return if def then def.Name else fish.Id
end

-- Значок мутации: «Золотая мутация ×2»; без мутации — nil.
function FishingRules.MutationLabel(fish: FishData): string?
	local mutation = fish.Mutation and mutationById[fish.Mutation]
	if not mutation then
		return nil
	end
	return `{mutation.Name} мутация ×{mutation.Multiplier}`
end

-- Вес для карточки: «850 г», «1,2 кг», «64 кг».
function FishingRules.FormatKg(kg: number): string
	if kg < 1 then
		return `{math.round(kg * 1000 / 10) * 10} г`
	elseif kg < 10 then
		return (string.gsub(string.format("%.1f кг", kg), "%.", ","))
	end
	return `{math.round(kg)} кг`
end

-- Монеты с пробелами между тысячами: 2083 → «2 083» (неразрывный пробел — число
-- не разорвётся на две строки).
function FishingRules.FormatCoins(value: number): string
	local digits = string.format("%d", math.floor(math.abs(value) + 0.5))
	local head = #digits % 3
	if head == 0 then
		head = 3
	end
	local groups = { string.sub(digits, 1, head) }
	for index = head + 1, #digits, 3 do
		table.insert(groups, string.sub(digits, index, index + 2))
	end
	local text = table.concat(groups, "\u{00A0}")
	return if value <= -0.5 then "−" .. text else text
end

--------------------------------------------------------------------------------
-- Мини-игра
--------------------------------------------------------------------------------

-- Положение стрелки 0..1 через t секунд (см. шапку).
function FishingRules.Needle(u0: number, speed: number, t: number): number
	local u = (u0 + speed * math.max(t, 0)) % 2
	return if u <= 1 then u else 2 - u
end

-- Попала ли стрелка в зелёную зону (центр center, ширина width).
function FishingRules.IsHit(position: number, center: number, width: number): boolean
	return math.abs(position - center) <= width / 2 + 1e-6
end

-- Центр новой зоны: целиком на полосе (с отступом ZoneMargin от краёв) и не ближе
-- MinZoneJump к стрелке (needle), чтобы нельзя было попасть, не дождавшись стрелки, и к
-- прошлой зоне (previous), чтобы прыжок зоны после попадания было видно. Если так нельзя —
-- лучший из нескольких случайных вариантов (дальше всего от стрелки и прошлой зоны).
function FishingRules.PickZoneCenter(rng: Rng, width: number, needle: number?, previous: number?): number
	local lo = width / 2 + FishingConfig.ZoneMargin
	local hi = 1 - width / 2 - FishingConfig.ZoneMargin
	if hi <= lo then
		return 0.5
	end
	local function score(center: number): number
		local gap = math.huge
		if needle then
			gap = math.min(gap, math.abs(center - needle))
		end
		if previous then
			gap = math.min(gap, math.abs(center - previous))
		end
		return gap
	end
	local best, bestScore = lo, -1
	for _ = 1, 10 do
		local center = rng:NextNumber(lo, hi)
		local gap = score(center)
		if gap >= FishingConfig.MinZoneJump then
			return center
		end
		if gap > bestScore then
			best, bestScore = center, gap
		end
	end
	for _, edge in { lo, hi } do -- края полосы — самые далёкие точки
		local gap = score(edge)
		if gap > bestScore then
			best, bestScore = edge, gap
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- Улов
--------------------------------------------------------------------------------

-- Веса редкостей с учётом удачи удочки: { { Id, Weight } } по порядку FishConfig.Rarities.
function FishingRules.RarityWeights(luck: number): { { Id: string, Weight: number } }
	local weights = {}
	for _, rarity in FishConfig.Rarities do
		table.insert(weights, { Id = rarity.Id, Weight = rarity.Weight * math.max(luck, 0) ^ rarity.LuckPower })
	end
	return weights
end

-- Случайный элемент по весам (list[i].Weight).
local function pickWeighted<T>(rng: Rng, list: { T }, weightOf: (T) -> number): T
	local total = 0
	for _, item in list do
		total += math.max(weightOf(item), 0)
	end
	local roll = rng:NextNumber() * total
	for _, item in list do
		roll -= math.max(weightOf(item), 0)
		if roll < 0 then
			return item
		end
	end
	return list[#list]
end

function FishingRules.RollRarity(rng: Rng, luck: number): string
	local entry = pickWeighted(rng, FishingRules.RarityWeights(luck), function(e)
		return e.Weight
	end)
	return entry.Id
end

-- Вид рыбы заданной редкости (по весам видов).
function FishingRules.RollSpecies(rng: Rng, rarity: string): FishConfig.Fish
	local pool = {}
	for _, fish in FishConfig.Fish do
		if fish.Rarity == rarity then
			table.insert(pool, fish)
		end
	end
	assert(#pool > 0, `[FishingRules] нет рыб редкости {rarity}`)
	return pickWeighted(rng, pool, function(f)
		return f.Weight
	end)
end

-- Мутация (Id) или nil: один бросок, шансы мутаций складываются.
function FishingRules.RollMutation(rng: Rng): string?
	local roll = rng:NextNumber()
	for _, mutation in FishConfig.Mutations do
		roll -= mutation.Chance
		if roll < 0 then
			return mutation.Id
		end
	end
	return nil
end

-- Цена и доход рыбы данного вида, веса и мутации.
function FishingRules.Price(fishId: string, kg: number, mutation: string?): (number, number)
	local def = fishById[fishId]
	assert(def, `[FishingRules] неизвестная рыба {fishId}`)
	local span = math.max(def.MaxKg - def.MinKg, 1e-6)
	local t = math.clamp((kg - def.MinKg) / span, 0, 1)
	local size = FishConfig.SizeValue.Min + (FishConfig.SizeValue.Max - FishConfig.SizeValue.Min) * t
	local mult = 1
	local mutationDef = mutation and mutationById[mutation]
	if mutationDef then
		mult = mutationDef.Multiplier
	end
	local value = math.max(1, math.round(def.Value * size * mult))
	local income = math.round(def.Income * size * mult * 10) / 10
	return value, income
end

-- Полный бросок улова для удочки rodId (на сервере).
function FishingRules.RollFish(rng: Rng, rodId: string?): FishData
	local rod = FishingRules.GetRod(rodId)
	local rarity = FishingRules.RollRarity(rng, rod.Luck)
	local def = FishingRules.RollSpecies(rng, rarity)
	local t = rng:NextNumber() ^ FishConfig.SizeBias -- мелкие чаще
	local kg = math.round((def.MinKg + (def.MaxKg - def.MinKg) * t) * 100) / 100
	local mutation = FishingRules.RollMutation(rng)
	local value, income = FishingRules.Price(def.Id, kg, mutation)
	return {
		Id = def.Id,
		Rarity = def.Rarity,
		Mutation = mutation,
		Kg = kg,
		Value = value,
		Income = income,
	}
end

return FishingRules
