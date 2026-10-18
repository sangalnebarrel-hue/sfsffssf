--!strict
--[[
	CarryGuard — проверка скорости вора с рыбой (Этап 4, docs/stage4_design.md §4.4; BE-9, BE-28):
	«дырявый бюджет» пути. Чистый объект без часов и Instance: dt и пройденное приходят снаружи
	(наблюдатель StealService раз в StealConfig.Tick), поэтому каждый случай проверяется без
	сервера (tests/stage4_rules).

	  local guard = CarryGuard.new(cfg?, allowed)   -- cfg — StealConfig.Carry.Speed (по умолчанию);
	                                                -- allowed — разрешённая скорость, studs/с
	                                                -- (Lib/Speed.Allowed); бюджет сразу полный
	  guard:Step(dt, displacement, allowed) -> "ok" | "speed"
	      cap    = allowed × CapSeconds + CapSlack
	      budget = min(cap, budget + allowed × dt × Rate) − displacement
	      displacement > Teleport за один тик → "speed"; budget < −Debt → "speed"
	  guard:CanCredit() -> boolean                  -- бюджет ≥ 0: на этом тике можно засчитать
	                                                -- выход за ограду (телепорт наружу не засчитан)
	  guard:Budget() -> number                      -- тесты

	Честный вор (13.6 studs/с, с собакой 6.8) бюджет не тратит; WalkSpeed 16 под собакой —
	«speed» за ≈ 2.5 с; задержка сети телефона 1.5 с и рывок ≈ 20 studs — не «speed» (меньше
	Teleport и в пределах cap). Штрафов «по счёту» нет: две задержки за долгий вынос не
	складываются.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StealConfig = require(ReplicatedStorage.Shared.Config.StealConfig)

export type Config = {
	Rate: number,
	CapSeconds: number,
	CapSlack: number,
	Debt: number,
	Teleport: number,
}

export type Guard = {
	Step: (self: Guard, dt: number, displacement: number, allowed: number) -> "ok" | "speed",
	CanCredit: (self: Guard) -> boolean,
	Budget: (self: Guard) -> number,
}

local CarryGuard = {}

function CarryGuard.new(cfg: Config?, allowed: number): Guard
	local c: Config = cfg or StealConfig.Carry.Speed
	local function cap(speed: number): number
		return math.max(0, speed) * c.CapSeconds + c.CapSlack
	end
	local budget = cap(allowed)
	local self = {}

	function self.Step(_: any, dt: number, displacement: number, speed: number): "ok" | "speed"
		local d = if displacement == displacement then math.max(0, displacement) else math.huge
		local refill = math.max(0, speed) * math.max(0, dt) * c.Rate
		budget = math.min(cap(speed), budget + refill) - d
		if d > c.Teleport then
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
