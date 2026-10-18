--!strict
--[[
	StealRules — правила кражи и защиты (Этап 4), общие для сервера и клиента: чистые функции без
	состояния (числа — StealConfig, DefenceConfig, MapConfig; docs/stage4_design.md §1.5, §2, §4).
	Координаты «базы» — в системе координат модели базы (BaseService: Model:GetPivot()): Root в
	начале, y = 0 — земля, −Z — к лагуне, участок x ±PlotHalfWidth, z PlotFront..PlotFront +
	PlotDepth.

	  HoldTime(level)            — сколько держать «Украсть» у замка уровня level: 0 (и не число) —
	                               Lock.BaseHold, 1..#Levels — Levels[level].Hold, выше (сервер
	                               новее) — как #Levels (правило Этапа 3 B-6)
	  LocalOf(pivot, pos)        — точка мира → точка базы (pivot = Model:GetPivot() базы)
	  InPlot(p, margin)          — точка базы внутри участка, расширенного на margin studs
	                               (|x| ≤ PlotHalfWidth + margin, PlotFront − margin ≤ z ≤
	                               PlotFront + PlotDepth + margin; высота не важна)
	  NearestExit(p)             — ближайший выход с участка (точка базы, y = 0): ворота, боковая
	                               ограда (через неё перепрыгивают; до террасы дома) или арка сзади
	                               (StealConfig.Exits) — туда ведёт красная дорожка вора
	  DogWaypoint(dog, thief)    — куда бежать собаке: собака перед галереями, а вор в проходе
	                               галереи — сначала к открытому концу прохода
	                               (DefenceConfig.Dog.Waypoint; дошла — к вору), иначе прямо к вору
	  DogStep(pos, target, dt, speed, leash) — шаг собаки к цели (по горизонтали, y = 0, без
	                               перелёта), не дальше leash studs за край участка
	  DogArrival(from, to)       — за сколько секунд собака от from добежит до вора в to (с «ГАВ!»
	                               AlertDelay; до BiteRange) — тесты честности (DC-05)
	  ProtectState(now, untils)  -> (kind?, until?) — защита базы: из { shield = t?, join = t?,
	                               newbie = t?, after = t?, rest = t? } (серверное время конца) —
	                               та, что кончается позже всех (из ещё не кончившихся; при
	                               равенстве — по порядку shield, rest, after, newbie, join)
	  CanPlace(candidates, hasFree, income10) -> "stored" | "replaced" | nil — ляжет ли добыча в
	                               садок вора (TankService:PreviewAdd и фильтр кнопок клиента —
	                               одна формула): есть свободная витрина — "stored"; иначе
	                               TankRules.ChooseReplacement по кандидатам (Locked — краденые,
	                               «в пути» и спящие) — "replaced", иначе nil
	  CanStealView(view)         -> (reason?, left?) — фильтр кнопок клиента: строки
	                               Shared/TheftChecks с Client = true
	  DeniedText(reason, left?)  — текст отказа (StealConfig.Texts.Denied, {t} — FormatClock(left))
	  FormatClock(s)             — «0:42», «6:12», «1:00»: целые секунды вверх (до конца —
	                               «0:01»), меньше нуля и не число — «0:00»
	  FormatSeconds(s)           — «1,8» (десятые через запятую, для «1,8 с»)
	  NextLock(level, saleMax)   -> (hold, price) | (nil, "max" | "soon") — следующий уровень
	                               замка в продаже: "max" — лучше нет (#Levels), "soon" — сильнее
	                               только в магазине (выше saleMax; Этап 5)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local StealConfig = require(Config:WaitForChild("StealConfig"))
local DefenceConfig = require(Config:WaitForChild("DefenceConfig"))
local MapConfig = require(Config:WaitForChild("MapConfig"))
local TankRules = require(Shared:WaitForChild("TankRules"))
local TheftChecks = require(Shared:WaitForChild("TheftChecks"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))

export type Untils = {
	shield: number?,
	join: number?,
	newbie: number?,
	after: number?,
	rest: number?,
}

local LOCK = DefenceConfig.Lock
local DOG = DefenceConfig.Dog
local WAYPOINT = DOG.Waypoint
local EXITS = StealConfig.Exits
local HALF = MapConfig.PlotHalfWidth
local FRONT = MapConfig.PlotFront
local BACK = MapConfig.PlotFront + MapConfig.PlotDepth
local EXIT_MARGIN = StealConfig.Carry.ExitMargin
-- Порядок видов защиты при равном конце (щит — первым: у него купол).
local KINDS = { "shield", "rest", "after", "newbie", "join" }

local StealRules = {}

local function finite(x: any): boolean
	return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end

function StealRules.HoldTime(level: any): number
	if not finite(level) or level < 1 then
		return LOCK.BaseHold
	end
	local index = math.min(math.floor(level), #LOCK.Levels)
	return LOCK.Levels[index].Hold
end

function StealRules.LocalOf(pivot: CFrame, pos: Vector3): Vector3
	return pivot:Inverse() * pos
end

function StealRules.InPlot(p: Vector3, margin: number?): boolean
	local m = margin or 0
	return math.abs(p.X) <= HALF + m and p.Z >= FRONT - m and p.Z <= BACK + m
end

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function StealRules.NearestExit(p: Vector3): Vector3
	local side = HALF + EXIT_MARGIN
	local z = math.clamp(p.Z, EXITS.SideFrom, EXITS.SideTo)
	local candidates = {
		Vector3.new(0, 0, FRONT - EXIT_MARGIN), -- ворота
		Vector3.new(side, 0, z),
		Vector3.new(-side, 0, z),
		Vector3.new(EXITS.ArchX, 0, BACK + EXIT_MARGIN),
		Vector3.new(-EXITS.ArchX, 0, BACK + EXIT_MARGIN),
	}
	local best: Vector3, bestDistance = candidates[1], math.huge
	for _, point in candidates do
		local d = flat(p, point)
		if d < bestDistance then
			best, bestDistance = point, d
		end
	end
	return best
end

local function inAisle(p: Vector3): boolean
	local x = math.abs(p.X)
	return x >= WAYPOINT.Inner and x <= WAYPOINT.Outer and p.Z >= WAYPOINT.Front and p.Z <= WAYPOINT.Back
end

function StealRules.DogWaypoint(dog: Vector3, thief: Vector3): Vector3
	if dog.Z < WAYPOINT.Front and inAisle(thief) then
		local mouth = Vector3.new(if thief.X < 0 then -WAYPOINT.X else WAYPOINT.X, 0, WAYPOINT.Z)
		if flat(dog, mouth) > WAYPOINT.Reach then
			return mouth
		end
	end
	return Vector3.new(thief.X, 0, thief.Z)
end

function StealRules.DogStep(pos: Vector3, target: Vector3, dt: number, speed: number, leash: number): Vector3
	local here = Vector3.new(pos.X, 0, pos.Z)
	local delta = Vector3.new(target.X - here.X, 0, target.Z - here.Z)
	local distance = delta.Magnitude
	local step = math.max(0, speed * dt)
	local nextPos = if distance <= step or distance == 0
		then Vector3.new(target.X, 0, target.Z)
		else here + delta.Unit * step
	local x = math.clamp(nextPos.X, -(HALF + leash), HALF + leash)
	local z = math.clamp(nextPos.Z, FRONT - leash, BACK + leash)
	return Vector3.new(x, 0, z)
end

function StealRules.DogArrival(from: Vector3, to: Vector3): number
	local run = math.max(0, flat(from, to) - DOG.BiteRange)
	return DOG.AlertDelay + run / DOG.RunSpeed
end

function StealRules.ProtectState(now: number, untils: Untils): (string?, number?)
	local raw = untils :: any
	local kind: string?, last: number? = nil, nil
	for _, name in KINDS do
		local t = raw[name]
		if finite(t) and t > now and (last == nil or t > last) then
			kind, last = name, t
		end
	end
	return kind, last
end

function StealRules.CanPlace(
	candidates: { TankRules.Candidate },
	hasFree: boolean,
	income10: number
): ("stored" | "replaced")?
	if hasFree then
		return "stored"
	end
	if TankRules.ChooseReplacement(candidates, income10) ~= nil then
		return "replaced"
	end
	return nil
end

function StealRules.CanStealView(view: TheftChecks.View): (string?, number?)
	local reason, _, left = TheftChecks.Check(view, true)
	return reason, left
end

function StealRules.FormatClock(seconds: number): string
	if not finite(seconds) or seconds <= 0 then
		return "0:00"
	end
	local whole = math.ceil(seconds - 1e-6)
	return string.format("%d:%02d", whole // 60, whole % 60)
end

function StealRules.FormatSeconds(seconds: number): string
	local s = if finite(seconds) then math.max(0, seconds) else 0
	local tenths = math.floor(s * 10 + 0.5)
	return string.format("%d,%d", tenths // 10, tenths % 10)
end

function StealRules.DeniedText(reason: string, left: number?): string
	local template = StealConfig.Texts.Denied[reason]
	if not template then
		return ""
	end
	return TextUtil.fill(template, { t = StealRules.FormatClock(left or 0) })
end

function StealRules.NextLock(level: any, saleMax: number): (number?, any)
	local current = if finite(level) and level > 0 then math.floor(level) else 0
	local nextLevel = current + 1
	if nextLevel > #LOCK.Levels then
		return nil, "max"
	end
	if nextLevel > saleMax then
		return nil, "soon"
	end
	local entry = LOCK.Levels[nextLevel]
	return entry.Hold, entry.Price
end

return StealRules
