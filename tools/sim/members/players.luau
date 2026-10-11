-- members/players.luau: Players service, Player objects and the client Mouse.

local roblox = require("@lune/roblox")

return function(M)
	local function noop()
		return nil
	end

	local function localPlayer(sim)
		local ctx = sim.sched:context()
		if ctx.player then
			return sim.proxy:wrap(ctx.player)
		end
		return nil
	end

	M.define("Players", {
		LocalPlayer = M.prop(localPlayer),
		localPlayer = M.prop(localPlayer),
		NumPlayers = M.prop(function(sim)
			return #sim.players.order
		end),
		PlayerAdded = M.signal(),
		PlayerRemoving = M.signal(),
		PlayerMembershipChanged = M.signal(),
		GetPlayers = M.method(function(sim)
			return sim.players:list()
		end),
		getPlayers = M.method(function(sim)
			return sim.players:list()
		end),
		GetPlayerByUserId = M.method(function(sim, _, userId)
			for _, p in sim.players.order do
				if p.UserId == userId then
					return sim.proxy:wrap(p)
				end
			end
			return nil
		end),
		GetPlayerFromCharacter = M.method(function(sim, _, char)
			local r = sim.proxy:toReal(char)
			local p = r and sim.players.byChar[r]
			return p and sim.proxy:wrap(p) or nil
		end),
		playerFromCharacter = M.method(function(sim, _, char)
			local r = sim.proxy:toReal(char)
			local p = r and sim.players.byChar[r]
			return p and sim.proxy:wrap(p) or nil
		end),
		GetUserIdFromNameAsync = M.method(function(sim, _, name)
			for _, p in sim.players.order do
				if p.Name == name then
					return p.UserId
				end
			end
			error("Players:GetUserIdFromNameAsync() failed: Unknown user", 0)
		end),
		GetNameFromUserIdAsync = M.method(function(sim, _, userId)
			for _, p in sim.players.order do
				if p.UserId == userId then
					return p.Name
				end
			end
			return "User" .. tostring(userId)
		end),
		GetUserThumbnailAsync = M.method(function(_, _, userId)
			return "rbxthumb://type=AvatarHeadShot&id=" .. tostring(userId) .. "&w=150&h=150", true
		end),
		GetHumanoidDescriptionFromUserId = M.method(function(sim)
			return sim.proxy:wrap(roblox.Instance.new("HumanoidDescription"))
		end),
		GetFriendsAsync = M.method(function()
			error("RbxSim: Players:GetFriendsAsync is not supported", 0)
		end),
		BanAsync = M.method(noop),
		UnbanAsync = M.method(noop),
	})

	M.define("Player", {
		CharacterAdded = M.signal(),
		CharacterRemoving = M.signal(),
		CharacterAppearanceLoaded = M.signal(),
		Chatted = M.signal(),
		Idled = M.signal(),
		OnTeleport = M.signal(),
		Character = M.prop(function(sim, real)
			return sim.proxy:toScript(real.Character)
		end, function(sim, real, v)
			sim.players:setCharacter(real, sim.proxy:toReal(v))
		end),
		LoadCharacter = M.method(function(sim, real)
			sim.players:loadCharacter(real)
			if sim.sched:inSimThread() then
				sim.sched:taskWait(0)
			end
		end),
		LoadCharacterAsync = M.method(function(sim, real)
			sim.players:loadCharacter(real)
			if sim.sched:inSimThread() then
				sim.sched:taskWait(0)
			end
		end),
		RemoveCharacter = M.method(function(sim, real)
			local char = real.Character
			if char then
				sim.players.byChar[char] = nil
				sim.proxy:destroy(char)
				sim.proxy:setProperty(real, "Character", nil)
			end
		end),
		Kick = M.method(function(sim, real, message)
			sim.players:kick(real, message)
		end),
		GetMouse = M.method(function(sim, real)
			return sim.players:getMouse(real)
		end),
		IsInGroup = M.method(function()
			return false
		end),
		GetRankInGroup = M.method(function()
			return 0
		end),
		GetRoleInGroup = M.method(function()
			return "Guest"
		end),
		IsFriendsWith = M.method(function()
			return false
		end),
		IsVerified = M.method(function()
			return false
		end),
		HasAppearanceLoaded = M.method(function()
			return true
		end),
		ClearCharacterAppearance = M.method(noop),
		DistanceFromCharacter = M.method(function(_, real, pos)
			local char = real.Character
			local head = char and (char:FindFirstChild("Head") or char:FindFirstChild("HumanoidRootPart"))
			if head == nil then
				return 0
			end
			return (head.CFrame.Position - pos).Magnitude
		end),
		GetNetworkPing = M.method(function()
			return 0
		end),
		GetJoinData = M.method(function()
			return {}
		end),
		GetFriendsOnline = M.method(function()
			return {}
		end),
		RequestStreamAroundAsync = M.method(noop),
		SetSuperSafeChat = M.method(noop),
		GetUnder13 = M.method(function()
			return false
		end),
	})

	-- Legacy mouse returned by Player:GetMouse() (clients only).
	M.define("PlayerMouse", {
		Hit = M.prop(function(sim, real)
			return sim.players:mouseState(real).hit
		end),
		Target = M.prop(function(sim, real)
			return sim.proxy:toScript(sim.players:mouseState(real).target)
		end),
		X = M.prop(function(sim, real)
			return sim.players:mouseState(real).x
		end),
		Y = M.prop(function(sim, real)
			return sim.players:mouseState(real).y
		end),
		UnitRay = M.prop(function(sim, real)
			local st = sim.players:mouseState(real)
			return roblox.Ray.new(st.hit.Position + roblox.Vector3.new(0, 10, 0), roblox.Vector3.new(0, -1, 0))
		end),
		Origin = M.prop(function(sim, real)
			return sim.players:mouseState(real).hit + roblox.Vector3.new(0, 10, 0)
		end),
		ViewSizeX = M.prop(function(sim)
			return sim:_viewportFor(sim.sched:context()).X
		end),
		ViewSizeY = M.prop(function(sim)
			return sim:_viewportFor(sim.sched:context()).Y
		end),
		TargetFilter = M.prop(function(sim, real)
			return sim.proxy:toScript(sim.players:mouseState(real).filter)
		end, function(sim, real, v)
			sim.players:mouseState(real).filter = sim.proxy:toReal(v)
		end),
		Button1Down = M.signal(),
		Button1Up = M.signal(),
		Button2Down = M.signal(),
		Button2Up = M.signal(),
		Move = M.signal(),
		Idle = M.signal(),
		WheelForward = M.signal(),
		WheelBackward = M.signal(),
	})
end
