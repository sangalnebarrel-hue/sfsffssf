--!strict
--[[
	Bucket — «кошелёк жетонов» на игрока (Этап 4): лимит запросов, общий рецепт для
	StealService (начала удержания: StealConfig.Limits.StartBurst / StartRate) и DefenceService
	(ShieldActivate + DefenceBuy: DefenceConfig.Requests). Запас burst, пополняется rate жетонов в
	секунду; каждый запрос берёт жетон; пусто — запрос молча отбрасывается. Без ожиданий.
	Для игрока, которого уже нет в Players (запрос пришёл после выхода), запись НЕ заводится
	(как Lib/TankRequests, BE-20) — таблица не растёт от ушедших. Lib/TankRequests (Этап 3) — как
	было, отдельно.

	  local bucket = Bucket.new(burst, rate)
	  bucket:Take(player) -> boolean   -- true: запрос можно обработать
	  bucket:Forget(player)            -- игрок вышел (PlayerRemoving владельца лимита)
	  bucket:Size() -> number          -- сколько игроков в таблице (тесты: _debugSizes)
]]

local Players = game:GetService("Players")

type Entry = { Tokens: number, At: number }

export type Bucket = {
	Take: (self: Bucket, player: Player) -> boolean,
	Forget: (self: Bucket, player: Player) -> (),
	Size: (self: Bucket) -> number,
}

local Bucket = {}

function Bucket.new(burst: number, rate: number): Bucket
	local entries: { [Player]: Entry } = {}
	local self = {}

	function self.Take(_: any, player: Player): boolean
		local now = os.clock()
		local entry = entries[player]
		if not entry then
			if player.Parent ~= Players then
				return false -- (запрос ушедшего игрока: записи не заводим)
			end
			entry = { Tokens = burst, At = now }
			entries[player] = entry
		end
		entry.Tokens = math.min(burst, entry.Tokens + (now - entry.At) * rate)
		entry.At = now
		if entry.Tokens < 1 then
			return false
		end
		entry.Tokens -= 1
		return true
	end

	function self.Forget(_: any, player: Player)
		entries[player] = nil
	end

	function self.Size(_: any): number
		local n = 0
		for _ in entries do
			n += 1
		end
		return n
	end

	return (self :: any) :: Bucket
end

return Bucket
