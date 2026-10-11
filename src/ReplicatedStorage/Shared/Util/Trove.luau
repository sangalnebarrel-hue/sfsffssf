--!strict
--[[
	Trove — «уборщик». Собирает всё, что потом надо убрать: соединения событий, объекты,
	потоки и функции очистки — и удаляет одним вызовом Clean().

	Так мы избегаем утечек памяти: у каждого игрока (и у каждого его персонажа) свой Trove,
	который чистится при выходе игрока / смене персонажа.

	local trove = Trove.new()
	trove:Connect(humanoid.Died, onDied)      -- соединение
	trove:Add(part)                            -- Instance → Destroy()
	trove:Add(function() print("cleanup") end) -- функция → вызов
	trove:Clean()
]]

export type Trove = {
	Add: <T>(self: Trove, item: T) -> T,
	Connect: (self: Trove, signal: any, handler: (...any) -> ()) -> any,
	Clean: (self: Trove) -> (),
	Destroy: (self: Trove) -> (),
}

local function cleanupItem(item: any)
	local kind = typeof(item)
	if kind == "RBXScriptConnection" then
		item:Disconnect()
	elseif kind == "Instance" then
		item:Destroy()
	elseif kind == "function" then
		item()
	elseif kind == "thread" then
		-- Отменять можно только поток, который сейчас ждёт (не тот, что выполняется).
		if coroutine.status(item) == "suspended" then
			task.cancel(item)
		end
	elseif kind == "table" then
		-- Наши объекты (Signal, Trove и т.п.): вызываем первый найденный метод очистки.
		for _, methodName in { "Disconnect", "Destroy", "Clean" } do
			local method: any = item[methodName]
			if type(method) == "function" then
				(method :: (any) -> ())(item)
				return
			end
		end
	end
end

local Trove = {}

function Trove.new(): Trove
	local items: { any } = {}
	local self = {}

	function self.Add<T>(_: any, item: T): T
		table.insert(items, item)
		return item
	end

	function self.Connect(_: any, signal: any, handler: (...any) -> ()): any
		local connection = signal:Connect(handler)
		table.insert(items, connection)
		return connection
	end

	function self.Clean(_: any)
		-- Забираем список целиком: если во время очистки что-то добавят, оно попадёт в новый список.
		local toClean = table.clone(items)
		table.clear(items)
		for index = #toClean, 1, -1 do
			local item = toClean[index]
			local ok, err = pcall(function()
				cleanupItem(item)
				return nil
			end)
			if not ok then
				warn("[Trove] ошибка очистки:", err)
			end
		end
	end

	self.Destroy = self.Clean

	return (self :: any) :: Trove
end

return Trove
