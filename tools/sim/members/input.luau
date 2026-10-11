-- members/input.luau: UserInputService, ContextActionService, ProximityPrompt.

local roblox = require("@lune/roblox")

return function(M)
	local function noop()
		return nil
	end

	local function deviceProp(name: string)
		return M.prop(function(sim)
			return sim.input:device(name)
		end)
	end

	M.define("UserInputService", {
		TouchEnabled = deviceProp("TouchEnabled"),
		KeyboardEnabled = deviceProp("KeyboardEnabled"),
		MouseEnabled = deviceProp("MouseEnabled"),
		GamepadEnabled = deviceProp("GamepadEnabled"),
		AccelerometerEnabled = M.prop(function()
			return false
		end),
		GyroscopeEnabled = M.prop(function()
			return false
		end),
		VREnabled = M.prop(function()
			return false
		end),
		InputBegan = M.signal(),
		InputEnded = M.signal(),
		InputChanged = M.signal(),
		TouchTap = M.signal(),
		TouchStarted = M.signal(),
		TouchEnded = M.signal(),
		TouchMoved = M.signal(),
		TouchLongPress = M.signal(),
		TouchPinch = M.signal(),
		TouchSwipe = M.signal(),
		TouchPan = M.signal(),
		TouchRotate = M.signal(),
		JumpRequest = M.signal(),
		LastInputTypeChanged = M.signal(),
		WindowFocused = M.signal(),
		WindowFocusReleased = M.signal(),
		TextBoxFocused = M.signal(),
		TextBoxFocusReleased = M.signal(),
		GamepadConnected = M.signal(),
		GamepadDisconnected = M.signal(),
		IsKeyDown = M.method(function(sim, _, keyCode)
			return sim.input:isKeyDown(keyCode)
		end),
		GetKeysPressed = M.method(function(sim)
			return sim.input:keysPressed()
		end),
		IsMouseButtonPressed = M.method(function()
			return false
		end),
		GetMouseLocation = M.method(function(sim)
			local vp = sim:_viewportFor(sim.sched:context())
			return roblox.Vector2.new(vp.X / 2, vp.Y / 2)
		end),
		GetMouseDelta = M.method(function()
			return roblox.Vector2.zero
		end),
		GetLastInputType = M.method(function(sim)
			return sim.input:lastInputType()
		end),
		GetFocusedTextBox = M.method(function(sim)
			return sim.proxy:toScript(sim.input.focused[sim.sched:context()])
		end),
		GetConnectedGamepads = M.method(function()
			return {}
		end),
		GetNavigationGamepads = M.method(function()
			return {}
		end),
		GetGamepadConnected = M.method(function()
			return false
		end),
		GetStringForKeyCode = M.method(function(_, _, keyCode)
			return keyCode and keyCode.Name or ""
		end),
		GetUserCFrame = M.method(function()
			return roblox.CFrame.identity
		end),
	})

	M.define("ContextActionService", {
		BindAction = M.method(function(sim, _, name, fn, touchButton, ...)
			sim.input:bindAction(name, fn, touchButton, nil, ...)
		end),
		BindActionAtPriority = M.method(function(sim, _, name, fn, touchButton, priority, ...)
			sim.input:bindAction(name, fn, touchButton, priority, ...)
		end),
		UnbindAction = M.method(function(sim, _, name)
			sim.input:unbindAction(name)
		end),
		UnbindAllActions = M.method(function(sim)
			sim.input:unbindAll()
		end),
		GetBoundActionInfo = M.method(function(sim, _, name)
			return sim.input:actionInfo(name)
		end),
		GetAllBoundActionInfo = M.method(function(sim)
			return sim.input:allActionInfo()
		end),
		GetButton = M.method(noop),
		SetTitle = M.method(noop),
		SetDescription = M.method(noop),
		SetImage = M.method(noop),
		SetPosition = M.method(noop),
		BindActivate = M.method(noop),
		UnbindActivate = M.method(noop),
		LocalToolEquipped = M.signal(),
		LocalToolUnequipped = M.signal(),
	})

	M.define("ProximityPrompt", {
		Triggered = M.signal(),
		TriggerEnded = M.signal(),
		PromptButtonHoldBegan = M.signal(),
		PromptButtonHoldEnded = M.signal(),
		PromptShown = M.signal(),
		PromptHidden = M.signal(),
		InputHoldBegin = M.method(function(sim, real)
			local ctx = sim.sched:context()
			if ctx.kind ~= "client" then
				error("InputHoldBegin can only be called from the client", 0)
			end
			sim.input:beginHold(ctx.player, real, {})
		end),
		InputHoldEnd = M.method(function(sim, real)
			local ctx = sim.sched:context()
			if ctx.kind ~= "client" then
				error("InputHoldEnd can only be called from the client", 0)
			end
			sim.input:releaseHold(ctx.player, real)
		end),
	})
end
