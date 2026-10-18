--!strict
--[[
	DogBrain — «логическая» собака базы на сервере (Этап 4, docs/stage4_design.md §2.1): точка,
	которая во время кражи бежит к вору и рядом замедляет его. Модель собаки (Base_N.Dog.Pup)
	двигают клиенты (TheftWorldController) по атрибутам; сервер деталь не двигает.

	Состояния: Sleep (спит у DefenceConfig.Dog.Rest) → кража началась: Alert («ГАВ!»,
	Dog.AlertDelay с) → Chase (к вору со скоростью RunSpeed, по прямой: двор открыт к проходам
	галерей; собака перед галереями, а вор в проходе — сначала к его открытому концу,
	StealRules.DogWaypoint) → кража кончилась: Return (домой, HomeSpeed; в Return не кусает
	никогда) → Sleep. Поводок: не дальше Dog.Leash studs за край участка (StealRules.DogStep).
	Укус: по горизонтали не дальше BiteRange от вора — Step возвращает true; замедлить вора
	(Lib/Speed, ключ "Dog") — дело StealService, и только пока его кража на этой базе жива.
	Координаты — базы (StealRules.LocalOf): y = 0.

	Чистые шаги (без часов и Instance; tests/stage4_rules):
	  DogBrain.Rest() -> Vector3                          -- где спит (точка базы)
	  DogBrain.New() -> Brain                             -- спящая у Rest
	  DogBrain.WakeBrain(brain, targetUserId)             -- кража началась: Alert
	  DogBrain.ReturnBrain(brain)                         -- кража кончилась: Return
	  DogBrain.Advance(brain, dt, thief: Vector3?) -> boolean   -- шаг; true — кусает (Chase и
	                                                      -- вор ближе BiteRange)
	  DogBrain.Pending(brain, now) -> { DogState?, DogPos?, DogTarget? }  -- что пора записать в
	                                                      -- атрибуты: не чаще Dog.Replicate с,
	                                                      -- DogPos — только после сдвига больше
	                                                      -- MoveEpsilon (BE-23); смена состояния —
	                                                      -- сразу; пусто — ничего
	Собаки баз (сервер; наблюдатель StealService тикает их раз в StealConfig.Tick, только пока
	хоть одна не спит):
	  DogBrain.Wake(base, targetUserId)                   -- база: { Model, Dog } (BaseService.Base)
	  DogBrain.Return(base)
	  DogBrain.Step(base, dt, thief: Vector3?) -> boolean -- шаг собаки базы (+ атрибуты)
	  DogBrain.Reset(base)                                -- отключение садка (BE-27): домой, Sleep,
	                                                      -- атрибуты сняты, записи нет
	  DogBrain.AnyAwake() -> boolean
	  DogBrain.Get(base) -> Brain?                        -- тесты
	  DogBrain._debugSizes() -> { Brains }
	Атрибуты модели Base_N.Dog (RemoteNames): DogState, DogPos (Vector3 мира), DogTarget (UserId).
	Волна 0 (контракт): чистые шаги готовы, запись атрибутов (writeAttributes) — заглушка; её тело —
	Wave 1 A (вместе с показом собаки DefenceService).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local DefenceConfig = require(Shared.Config.DefenceConfig)
local StealRules = require(Shared.StealRules)

export type DogState = "Sleep" | "Alert" | "Chase" | "Return"

export type Brain = {
	Pos: Vector3, -- точка базы, y = 0
	State: DogState,
	Target: number?, -- UserId вора
	AlertLeft: number, -- сколько ещё лаять до бега, с
	-- что уже записано в атрибуты (Pending):
	WrittenAt: number,
	WrittenPos: Vector3?,
	WrittenState: DogState?,
	WrittenTarget: number?,
}

local DOG = DefenceConfig.Dog

local brains: { [any]: Brain } = {} -- база → собака (только не спящие)

local DogBrain = {}

local function flat(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function DogBrain.Rest(): Vector3
	return Vector3.new(DOG.Rest.X, 0, DOG.Rest.Z)
end

function DogBrain.New(): Brain
	return {
		Pos = DogBrain.Rest(),
		State = "Sleep",
		Target = nil,
		AlertLeft = 0,
		WrittenAt = -math.huge,
		WrittenPos = nil,
		WrittenState = nil,
		WrittenTarget = nil,
	}
end

function DogBrain.WakeBrain(brain: Brain, targetUserId: number?)
	brain.Target = targetUserId
	if brain.State ~= "Chase" then
		brain.State = "Alert"
		brain.AlertLeft = DOG.AlertDelay
	end
end

function DogBrain.ReturnBrain(brain: Brain)
	brain.Target = nil
	if brain.State ~= "Sleep" then
		brain.State = "Return"
	end
end

function DogBrain.Advance(brain: Brain, dt: number, thief: Vector3?): boolean
	local step = math.max(0, dt)
	if brain.State == "Alert" then
		brain.AlertLeft -= step
		if brain.AlertLeft > 0 then
			return false
		end
		step = -brain.AlertLeft -- (остаток тика — уже бег)
		brain.AlertLeft = 0
		brain.State = "Chase"
	end
	if brain.State == "Chase" then
		if not thief then
			return false
		end
		local target = StealRules.DogWaypoint(brain.Pos, thief)
		brain.Pos = StealRules.DogStep(brain.Pos, target, step, DOG.RunSpeed, DOG.Leash)
		return flat(brain.Pos, thief) <= DOG.BiteRange
	elseif brain.State == "Return" then
		local rest = DogBrain.Rest()
		brain.Pos = StealRules.DogStep(brain.Pos, rest, step, DOG.HomeSpeed, DOG.Leash)
		if flat(brain.Pos, rest) <= 1e-3 then
			brain.Pos = rest
			brain.State = "Sleep"
		end
	end
	return false
end

function DogBrain.Pending(brain: Brain, now: number): { [string]: any }
	local out: { [string]: any } = {}
	if brain.State ~= brain.WrittenState then
		out.DogState = brain.State -- (смена состояния — сразу)
	end
	if brain.Target ~= brain.WrittenTarget then
		out.DogTarget = brain.Target or false
	end
	if now - brain.WrittenAt >= DOG.Replicate then
		local written = brain.WrittenPos
		if written == nil or flat(brain.Pos, written) > DOG.MoveEpsilon then
			out.DogPos = brain.Pos
		end
	end
	return out
end

-- Записать в атрибуты Base_N.Dog то, что вернул Pending (DogPos — в координаты мира: pivot базы).
-- Волна 0: заглушка — атрибуты пишет Wave 1 A (здесь же помечается, что «записано»).
local function writeAttributes(_base: any, brain: Brain, pending: { [string]: any }, now: number)
	if pending.DogState ~= nil then
		brain.WrittenState = brain.State
	end
	if pending.DogTarget ~= nil then
		brain.WrittenTarget = brain.Target
	end
	if pending.DogPos ~= nil then
		brain.WrittenPos = brain.Pos
		brain.WrittenAt = now
	end
end

function DogBrain.Wake(base: any, targetUserId: number?)
	local brain = brains[base]
	if not brain then
		brain = DogBrain.New()
		brains[base] = brain
	end
	DogBrain.WakeBrain(brain, targetUserId)
end

function DogBrain.Return(base: any)
	local brain = brains[base]
	if brain then
		DogBrain.ReturnBrain(brain)
	end
end

function DogBrain.Step(base: any, dt: number, thief: Vector3?): boolean
	local brain = brains[base]
	if not brain then
		return false
	end
	local bite = DogBrain.Advance(brain, dt, thief)
	local now = os.clock()
	local pending = DogBrain.Pending(brain, now)
	if next(pending) then
		writeAttributes(base, brain, pending, now)
	end
	if brain.State == "Sleep" then
		brains[base] = nil
	end
	return bite
end

function DogBrain.Reset(base: any)
	local brain = brains[base]
	brains[base] = nil
	if brain then
		local rest = DogBrain.New()
		writeAttributes(base, rest, { DogState = false, DogPos = false, DogTarget = false }, os.clock())
	end
end

function DogBrain.AnyAwake(): boolean
	return next(brains) ~= nil
end

function DogBrain.Get(base: any): Brain?
	return brains[base]
end

function DogBrain._debugSizes(): { [string]: number }
	local n = 0
	for _ in brains do
		n += 1
	end
	return { Brains = n }
end

return DogBrain
