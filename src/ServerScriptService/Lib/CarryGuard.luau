--!strict
--[[
	CarryGuard — проверка скорости вора с рыбой (Этап 4, docs/stage4_design.md §4.4; BE-9, BE-28):
	«дырявый бюджет» пути. Чистый объект без часов и Instance: dt и пройденное приходят снаружи
	(наблюдатель StealService раз в StealConfig.Tick), поэтому каждый случай проверяется без
	сервера (tests/stage4_rules).

	  local guard = CarryGuard.new(cfg?, allowed)   -- cfg — StealConfig.Carry.Speed (по умолчанию);
	                                                -- allowed — разрешённая скорость, studs/с
	                                                -- (Lib/Speed.Allowed); бюджет в начале —
	                                                -- Start (не больше cap), НЕ полный (A2-01)
	  guard:Step(dt, displacement, allowed) -> "ok" | "speed"
	      cap    = allowed × CapSeconds + CapSlack
	      budget = min(cap, budget + allowed × dt × Rate) − displacement
	      displacement > Teleport + allowed × Rate × max(0, dt − Tick) за один тик → "speed"
	      (длинный тик сервера — не вина вора: за лишнее время честный прошёл бы столько; A2-05);
	      budget < −Debt → "speed"
	  guard:CanCredit() -> boolean                  -- бюджет ≥ 0: на этом тике можно засчитать
	                                                -- выход за ограду (телепорт наружу не засчитан)
	  guard:Budget() -> number                      -- тесты

	Честный вор (13.6 studs/с, с собакой 6.8) бюджет не тратит (Rate > 1: он копится до cap);
	WalkSpeed 16 под собакой — «speed» за ≈ 2.5 с; ускорение ×2 — за ≈ 0.9 с, раньше любой ограды
	(бюджет начинается с Start: запас на задержку сети накапливается ходьбой, а не дан сразу);
	задержка сети телефона 1.5 с и рывок ≈ 20 studs — не «speed» (меньше Teleport и в пределах
	cap; задержка в самом начале выноса — тоже: за неё бюджет пополнится). Штрафов «по счёту»
	нет: две задержки за долгий вынос не складываются.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StealConfig = require(ReplicatedStorage.Shared.Config.StealConfig)

export type Config = {
	Rate: number,
	CapSeconds: number,
	CapSlack: number,
	Debt: number,
	Teleport: number,
	Start: number,
}

export type Guard = {
	Step: (self: Guard, dt: number, displacement: number, allowed: number) -> "ok" | "speed",
	CanCredit: (self: Guard) -> boolean,
	Budget: (self: Guard) -> number,
}

local TICK = StealConfig.Tick

local CarryGuard = {}

function CarryGuard.new(cfg: Config?, allowed: number): Guard
	local c: Config = cfg or StealConfig.Carry.Speed
	local function cap(speed: number): number
		return math.max(0, speed) * c.CapSeconds + c.CapSlack
	end
	local budget = math.min(cap(allowed), c.Start)
	local self = {}

	function self.Step(_: any, dt: number, displacement: number, speed: number): "ok" | "speed"
		local d = if displacement == displacement then math.max(0, displacement) else math.huge
		local step = if dt == dt then math.max(0, dt) else 0
		local walk = math.max(0, speed) * c.Rate
		budget = math.min(cap(speed), budget + walk * step) - d
		if d > c.Teleport + walk * math.max(0, step - TICK) then
			return "speed"
		end
		if budget < -c.Debt then
			return "speed"
		end
		return "ok"
	end

	function self.CanCredit(_: any): boolean
		return budget >= 0
	end

	function self.Budget(_: any): number
		return budget
	end

	return (self :: any) :: Guard
end

return CarryGuard
