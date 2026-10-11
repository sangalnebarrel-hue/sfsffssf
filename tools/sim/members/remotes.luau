-- members/remotes.luau: RemoteEvent, UnreliableRemoteEvent, RemoteFunction,
-- BindableEvent and BindableFunction.

return function(M)
	local function serverOnly(message: string)
		return function(ctx)
			if ctx.kind ~= "server" then
				return message
			end
			return nil
		end
	end

	local function clientOnly(message: string)
		return function(ctx)
			if ctx.kind ~= "client" then
				return message
			end
			return nil
		end
	end

	local remoteEvent = {
		OnServerEvent = M.signal({
			check = serverOnly("OnServerEvent can only be used on the server"),
			onConnect = function(sim, real)
				sim.remotes:flushServerQueue(real)
			end,
		}),
		OnClientEvent = M.signal({
			check = clientOnly("OnClientEvent can only be used on the client"),
			onConnect = function(sim, real, _, conn)
				sim.remotes:flushClientQueue(real, conn.ctx)
			end,
		}),
		FireServer = M.method(function(sim, real, ...)
			sim.remotes:fireServer(real, ...)
		end),
		FireClient = M.method(function(sim, real, player, ...)
			sim.remotes:fireClient(real, player, ...)
		end),
		FireAllClients = M.method(function(sim, real, ...)
			sim.remotes:fireAllClients(real, ...)
		end),
	}
	M.define("RemoteEvent", remoteEvent)
	M.define("UnreliableRemoteEvent", remoteEvent)

	M.define("RemoteFunction", {
		OnServerInvoke = M.callback(function(sim, real, fn)
			sim.remotes:setServerInvoke(real, fn)
		end),
		OnClientInvoke = M.callback(function(sim, real, fn)
			sim.remotes:setClientInvoke(real, fn)
		end),
		InvokeServer = M.method(function(sim, real, ...)
			return sim.remotes:invokeServer(real, ...)
		end),
		InvokeClient = M.method(function(sim, real, player, ...)
			return sim.remotes:invokeClient(real, player, ...)
		end),
	})

	M.define("BindableEvent", {
		Event = M.signal(),
		Fire = M.method(function(sim, real, ...)
			sim.remotes:fireBindable(real, ...)
		end),
	})

	M.define("BindableFunction", {
		OnInvoke = M.callback(function(sim, real, fn)
			sim.remotes:setBindableInvoke(real, fn)
		end),
		Invoke = M.method(function(sim, real, ...)
			return sim.remotes:invokeBindable(real, ...)
		end),
	})
end
