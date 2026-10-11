--!strict
--[[
	Cooldown — кулдаун по ключу (обычно ключ — Player). Используется на сервере для защиты
	RemoteEvent от спама.

	local homeCooldown = Cooldown.new(5)
	if homeCooldown:TryUse(player) then ... end
	homeCooldown:Clear(player) -- при выходе игрока, чтобы таблица не росла
]]

export type Cooldown = {
	Duration: number,
	TryUse: (self: Cooldown, key: any) -> boolean,
	Remaining: (self: Cooldown, key: any) -> number,
	Clear: (self: Cooldown, key: any) -> (),
}

local Cooldown = {}

function Cooldown.new(duration: number): Cooldown
	local lastUse: { [any]: number } = {}
	local self = { Duration = duration }

	-- true, если кулдаун прошёл (и сразу запускает новый).
	function self.TryUse(this: Cooldown, key: any): boolean
		local now = os.clock()
		local last = lastUse[key]
		if last and now - last < this.Duration then
			return false
		end
		lastUse[key] = now
		return true
	end

	-- Сколько секунд осталось до конца кулдауна (0 — готово).
	function self.Remaining(this: Cooldown, key: any): number
		local last = lastUse[key]
		if not last then
			return 0
		end
		return math.max(0, this.Duration - (os.clock() - last))
	end

	function self.Clear(_: any, key: any)
		lastUse[key] = nil
	end

	return (self :: any) :: Cooldown
end

return Cooldown
