--!strict
--[[
	TankRequests — общий лимит запросов игрока к садку (Этап 3): TankSell, кнопки "TankPrompt"
	(TankService) и "SellPrompt" (MarketService). Один «кошелёк жетонов» на игрока: запас
	TankConfig.Requests.Burst, пополняется Rate жетонов в секунду; каждый запрос берёт жетон, его
	ответ (и "Denied" тоже) идёт за счёт этого же жетона — пустой кошелёк: запрос молча
	отбрасывается, ответа нет (спамер не умножит трафик сервер → клиент). Без ожиданий.

	API:
	  TankRequests.Take(player) -> boolean   -- true: запрос можно обработать
	  TankRequests.Forget(player)            -- игрок вышел (TankService и MarketService — оба)
	  TankRequests.Size() -> number          -- сколько игроков в таблице (тесты: _debugSizes)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TankConfig = require(ReplicatedStorage.Shared.Config.TankConfig)

local BURST = TankConfig.Requests.Burst
local RATE = TankConfig.Requests.Rate

type Bucket = { Tokens: number, At: number }

local buckets: { [Player]: Bucket } = {}

local TankRequests = {}

function TankRequests.Take(player: Player): boolean
	local now = os.clock()
	local bucket = buckets[player]
	if not bucket then
		if player.Parent ~= Players then
			return false -- (запрос ушедшего игрока: записи не заводим)
		end
		bucket = { Tokens = BURST, At = now }
		buckets[player] = bucket
	end
	bucket.Tokens = math.min(BURST, bucket.Tokens + (now - bucket.At) * RATE)
	bucket.At = now
	if bucket.Tokens < 1 then
		return false
	end
	bucket.Tokens -= 1
	return true
end

function TankRequests.Forget(player: Player)
	buckets[player] = nil
end

function TankRequests.Size(): number
	local n = 0
	for _ in buckets do
		n += 1
	end
	return n
end

return TankRequests
