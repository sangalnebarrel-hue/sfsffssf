-- members/instance.luau: members shared by every Instance.

return function(M)
	local function nameArg(name, what)
		if type(name) ~= "string" then
			error(string.format("Argument 1 missing or nil (%s expects a string)", what), 0)
		end
		return name
	end

	M.define("Instance", {
		-- events (fired at write time by the proxy layer)
		Changed = M.signal(),
		ChildAdded = M.signal(),
		ChildRemoved = M.signal(),
		DescendantAdded = M.signal(),
		DescendantRemoving = M.signal(),
		AncestryChanged = M.signal(),
		Destroying = M.signal(),
		AttributeChanged = M.signal(),

		GetAttributeChangedSignal = M.method(function(sim, real, name)
			nameArg(name, "GetAttributeChangedSignal")
			return sim.proxy:getSignal(real, "attr:" .. name):facade()
		end),

		GetPropertyChangedSignal = M.method(function(sim, real, name)
			nameArg(name, "GetPropertyChangedSignal")
			local cls = sim.proxy:className(real)
			local def = sim.members:resolve(cls)[name]
			local valid = (def and def.kind == "prop") or sim.members:propertyInfo(cls, name) ~= nil
			if not valid then
				error(string.format("%s is not a valid property name.", name), 0)
			end
			return sim.proxy:getSignal(real, "prop:" .. name):facade()
		end),

		SetAttribute = M.method(function(sim, real, name, value)
			nameArg(name, "SetAttribute")
			if sim.proxy:isProxy(value) then
				error("SetAttribute: Instance values are not supported as attributes", 0)
			end
			sim:_checkClientWrite(real, "@" .. name)
			local old = real:GetAttribute(name)
			local ok, err = pcall(real.SetAttribute, real, name, value)
			if not ok then
				error(sim.util.cleanError(err), 0)
			end
			local new = real:GetAttribute(name)
			if old ~= new and not (old ~= old and new ~= new) then
				local proxy = sim.proxy
				proxy:fire(real, "attr:" .. name)
				proxy:fire(real, "AttributeChanged", name)
			end
		end),

		Destroy = M.method(function(sim, real)
			sim:_checkClientWrite(real, "Destroy")
			sim.proxy:destroy(real)
		end),

		Remove = M.method(function(sim, real)
			sim.proxy:setParent(real, nil)
		end),

		ClearAllChildren = M.method(function(sim, real)
			for _, child in real:GetChildren() do
				sim.proxy:destroy(child)
			end
		end),

		Clone = M.method(function(sim, real)
			if real.Archivable == false then
				return nil
			end
			local copy = real:Clone()
			for _, d in copy:GetDescendants() do
				if d.Parent ~= nil and d.Archivable == false then
					d.Parent = nil
				end
			end
			local ctx = sim.sched:context()
			if ctx.kind == "client" then
				sim.proxy.createdBy[copy] = ctx
			end
			return sim.proxy:wrap(copy)
		end),

		WaitForChild = M.method(function(sim, real, name, timeout)
			nameArg(name, "WaitForChild")
			if timeout ~= nil and type(timeout) ~= "number" then
				error("WaitForChild: timeout must be a number", 0)
			end
			return sim.proxy:waitForChild(real, name, timeout)
		end),

		FindFirstDescendant = M.method(function(sim, real, name)
			nameArg(name, "FindFirstDescendant")
			return sim.proxy:wrap(real:FindFirstChild(name, true))
		end),

		GetActor = M.method(function()
			return nil
		end),

		AddTag = M.method(function(sim, real, tag)
			sim.collection:addTag(real, tag)
		end),

		RemoveTag = M.method(function(sim, real, tag)
			sim.collection:removeTag(real, tag)
		end),

		IsPropertyModified = M.method(function()
			return false
		end),

		GetStyled = M.method(function(sim, real, name)
			return sim.proxy:read(real, name)
		end),
	})

	-- Script enable/disable starts and stops scripts like Roblox.
	M.define("BaseScript", {
		Enabled = M.prop(function(sim, real)
			return not sim.runtime:isDisabled(real)
		end, function(sim, real, v)
			sim.runtime:setEnabled(real, v == true)
		end),
		Disabled = M.prop(function(sim, real)
			return sim.runtime:isDisabled(real)
		end, function(sim, real, v)
			sim.runtime:setEnabled(real, v ~= true)
		end),
	})
end
