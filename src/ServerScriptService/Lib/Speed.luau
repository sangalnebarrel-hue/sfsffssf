--!strict
--[[
	Speed — скорость ходьбы игроков (Этап 4, docs/stage4_design.md §4.7): стопка множителей по
	ключам и их сроки. ЕДИНСТВЕННЫЙ, кто пишет Humanoid.WalkSpeed:
	  WalkSpeed = StarterPlayer.CharacterWalkSpeed × max(StealConfig.Speed.MinFactor, Π множителей).
	Ключи: "Carry" (вор с рыбой, StealConfig.Carry.SpeedFactor) и "Dog" (собака рядом,
	DefenceConfig.Dog.Slow, со сроком). Каждый конец кражи сначала снимает всё (ClearAll).

	  Speed.Set(player, key, factor, untilClock?)  -- поставить / обновить множитель (до
	                                                -- os.clock() untilClock; nil — бессрочно)
	  Speed.Clear(player, key)                      -- снять один
	  Speed.ClearAll(player)                        -- снять все (WalkSpeed — обычная)
	  Speed.Forget(player)                          -- игрок ушёл (PlayerRemoving): ничего не пишет
	  Speed.Factor(player) -> number                -- Π живых множителей, не меньше MinFactor
	  Speed.Allowed(player, grace?) -> number       -- CharacterWalkSpeed × самый большой множитель
	                                                -- за последние grace с (WalkSpeed доходит до
	                                                -- клиента с задержкой — проверка выноса,
	                                                -- Lib/CarryGuard, не наказывает за неё)
	  Speed._debugSizes() -> { Players }            -- тесты: после выхода — 0

	Сроки — свои: ОДИН task.delay на игрока до ближайшего срока (с номером поколения — старый
	таймер ничего не делает); он снимает истёкшие ключи и переписывает WalkSpeed. «При чтении»
	ничего не снимается: замедление не переживёт свой срок оттого, что его никто не прочёл.
	Атрибут игрока Slowed (true / nil) пишется только когда ключ "Dog" появляется или уходит, не
	каждый тик (BE-11). Новый персонаж сам начинает с обычной скорости: на CharacterAdded ничего
	не подключено. Часы — os.clock (внутри); в атрибуты время не уходит. Без ожиданий.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local StealConfig = require(ReplicatedStorage.Shared.Config.StealConfig)

type Modifier = { Factor: number, Until: number? }
type Change = { At: number, Factor: number }
type State = {
	Mods: { [string]: Modifier },
	History: { Change }, -- как менялся общий множитель (для Allowed)
	Gen: number, -- поколение таймера сроков
	Timer: thread?,
	Slowed: boolean,
}

local SLOWED_KEY = "Dog" -- этот ключ — атрибут Slowed
local MIN_FACTOR = StealConfig.Speed.MinFactor
local HISTORY = StealConfig.Speed.History

local states: { [Player]: State } = {}

local Speed = {}

local function baseSpeed(): number
	local speed = StarterPlayer.CharacterWalkSpeed
	return if type(speed) == "number" and speed > 0 then speed else 16
end

local function live(mod: Modifier, now: number): boolean
	return mod.Until == nil or (mod.Until :: number) > now
end

local function factorOf(state: State, now: number): number
	local product = 1
	for _, mod in state.Mods do
		if live(mod, now) then
			product *= mod.Factor
		end
	end
	return math.max(MIN_FACTOR, product)
end

local function writeWalkSpeed(player: Player, factor: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local speed = baseSpeed() * factor
		if humanoid.WalkSpeed ~= speed then
			humanoid.WalkSpeed = speed
		end
	end
end

-- Запомнить новый общий множитель (история — не старше HISTORY с, но всегда с тем, что было на
-- её начале).
local function record(state: State, factor: number, now: number)
	local history = state.History
	local last = history[#history]
	if last and last.Factor == factor then
		return
	end
	table.insert(history, { At = now, Factor = factor })
	while #history >= 2 and history[2].At <= now - HISTORY do
		table.remove(history, 1)
	end
end

local schedule: (player: Player, state: State) -> ()

-- После любого изменения: WalkSpeed, история, Slowed, таймер; пустая стопка — запись удаляется.
local function apply(player: Player, state: State)
	local now = os.clock()
	local factor = factorOf(state, now)
	record(state, factor, now)
	writeWalkSpeed(player, factor)
	local dog = state.Mods[SLOWED_KEY]
	local slowed = dog ~= nil and live(dog, now)
	if slowed ~= state.Slowed then
		state.Slowed = slowed
		player:SetAttribute("Slowed", if slowed then true else nil)
	end
	if next(state.Mods) == nil then
		state.Gen += 1
		local timer = state.Timer
		state.Timer = nil
		if timer and coroutine.status(timer) == "suspended" then
			task.cancel(timer)
		end
		if states[player] == state then
			states[player] = nil
		end
		return
	end
	schedule(player, state)
end

schedule = function(player: Player, state: State)
	state.Gen += 1
	local gen = state.Gen
	local timer = state.Timer
	state.Timer = nil
	if timer and coroutine.status(timer) == "suspended" then
		task.cancel(timer)
	end
	local earliest: number? = nil
	for _, mod in state.Mods do
		local untilClock = mod.Until
		if untilClock and (earliest == nil or untilClock < earliest) then
			earliest = untilClock
		end
	end
	if earliest == nil then
		return
	end
	state.Timer = task.delay(math.max(0, earliest - os.clock()), function()
		if state.Gen ~= gen or states[player] ~= state then
			return
		end
		state.Timer = nil
		local now = os.clock()
		for key, mod in table.clone(state.Mods) do
			if not live(mod, now) then
				state.Mods[key] = nil
			end
		end
		apply(player, state)
	end)
end

local function stateFor(player: Player): State?
	local state = states[player]
	if state then
		return state
	end
	if player.Parent ~= Players then
		return nil -- (ушедший игрок: записи не заводим)
	end
	local created: State = {
		Mods = {},
		History = { { At = -math.huge, Factor = 1 } },
		Gen = 0,
		Timer = nil,
		Slowed = false,
	}
	states[player] = created
	return created
end

function Speed.Set(player: Player, key: string, factor: number, untilClock: number?)
	if type(factor) ~= "number" or factor ~= factor or factor <= 0 then
		return
	end
	local state = stateFor(player)
	if not state then
		return
	end
	local mod = state.Mods[key]
	if mod and mod.Factor == factor then
		-- Обновить срок: атрибуты и WalkSpeed не меняются, только таймер.
		mod.Until = untilClock
		schedule(player, state)
		return
	end
	state.Mods[key] = { Factor = factor, Until = untilClock }
	apply(player, state)
end

function Speed.Clear(player: Player, key: string)
	local state = states[player]
	if not state or state.Mods[key] == nil then
		return
	end
	state.Mods[key] = nil
	apply(player, state)
end

function Speed.ClearAll(player: Player)
	local state = states[player]
	if not state then
		return
	end
	table.clear(state.Mods)
	apply(player, state)
end

function Speed.Forget(player: Player)
	local state = states[player]
	if not state then
		return
	end
	state.Gen += 1
	local timer = state.Timer
	state.Timer = nil
	if timer and coroutine.status(timer) == "suspended" then
		task.cancel(timer)
	end
	states[player] = nil
end

function Speed.Factor(player: Player): number
	local state = states[player]
	return if state then factorOf(state, os.clock()) else 1
end

function Speed.Allowed(player: Player, grace: number?): number
	local state = states[player]
	if not state then
		return baseSpeed()
	end
	local now = os.clock()
	local from = now - (grace or 0)
	local highest = factorOf(state, now)
	local history = state.History
	for i, change in history do
		local nextChange = history[i + 1]
		local ends = if nextChange then nextChange.At else now
		if ends >= from then
			highest = math.max(highest, change.Factor)
		end
	end
	return baseSpeed() * highest
end

function Speed._debugSizes(): { [string]: number }
	local n = 0
	for _ in states do
		n += 1
	end
	return { Players = n }
end

return Speed
