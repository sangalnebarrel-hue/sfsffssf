--!strict
--[[
	Signal — простое событие для связи модулей на одной стороне (сервер↔сервер, клиент↔клиент).

	Каждый обработчик вызывается в своём потоке (task.spawn): ошибка в одном обработчике
	не ломает остальные, а обработчик может безопасно ждать (task.wait и т.п.).

	local changed = Signal.new()
	local connection = changed:Connect(function(a, b) print(a, b) end)
	changed:Fire(1, 2)
	connection:Disconnect()
]]

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Once: (self: Signal, handler: (...any) -> ()) -> Connection,
	Wait: (self: Signal) -> ...any,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
	Destroy: (self: Signal) -> (),
}

type ConnectionImpl = {
	Connected: boolean,
	_handler: (...any) -> (),
	_list: { ConnectionImpl },
	Disconnect: (self: ConnectionImpl) -> (),
}

local function disconnect(self: ConnectionImpl)
	if not self.Connected then
		return
	end
	self.Connected = false
	local index = table.find(self._list, self)
	if index then
		table.remove(self._list, index)
	end
end

local function newConnection(list: { ConnectionImpl }, handler: (...any) -> ()): ConnectionImpl
	local connection: ConnectionImpl = {
		Connected = true,
		_handler = handler,
		_list = list,
		Disconnect = disconnect,
	}
	table.insert(list, connection)
	return connection
end

local Signal = {}

function Signal.new(): Signal
	local connections: { ConnectionImpl } = {}
	local self = {}

	function self.Connect(_: any, handler: (...any) -> ()): Connection
		return (newConnection(connections, handler) :: any) :: Connection
	end

	function self.Once(_: any, handler: (...any) -> ()): Connection
		local connection: ConnectionImpl
		connection = newConnection(connections, function(...)
			connection:Disconnect()
			handler(...)
		end)
		return (connection :: any) :: Connection
	end

	function self.Wait(_: any): ...any
		local thread = coroutine.running()
		local connection: ConnectionImpl
		connection = newConnection(connections, function(...)
			connection:Disconnect()
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	function self.Fire(_: any, ...: any)
		-- Копия списка: обработчики могут отключаться прямо во время Fire.
		for _, connection in table.clone(connections) do
			if connection.Connected then
				task.spawn(connection._handler, ...)
			end
		end
	end

	function self.DisconnectAll(_: any)
		for _, connection in table.clone(connections) do
			connection:Disconnect()
		end
	end

	self.Destroy = self.DisconnectAll

	return (self :: any) :: Signal
end

return Signal
