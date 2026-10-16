-- players.luau: player lifecycle (join/leave), characters, humanoid health,
-- death/respawn, StarterGui/StarterPack copying, tools and humanoid walking.

local roblox = require("@lune/roblox")

local Instance = roblox.Instance
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local Players = {}
Players.__index = Players

local DEVICES = {
	desktop = {
		TouchEnabled = false,
		KeyboardEnabled = true,
		MouseEnabled = true,
		GamepadEnabled = false,
		viewport = { 1280, 720 },
	},
	phone = {
		TouchEnabled = true,
		KeyboardEnabled = false,
		MouseEnabled = false,
		GamepadEnabled = false,
		viewport = { 844, 390 },
	},
	tablet = {
		TouchEnabled = true,
		KeyboardEnabled = false,
		MouseEnabled = false,
		GamepadEnabled = false,
		viewport = { 1024, 768 },
	},
	console = {
		TouchEnabled = false,
		KeyboardEnabled = false,
		MouseEnabled = false,
		GamepadEnabled = true,
		viewport = { 1920, 1080 },
	},
}
Players.DEVICES = DEVICES

local MOVE_TIMEOUT = 8

function Players.new(sim)
	local self = setmetatable({}, Players)
	self.sim = sim
	self.order = {} -- raw players in join order
	self.state = {} -- raw player -> state table
	self.byChar = setmetatable({}, { __mode = "k" }) -- raw character -> raw player
	-- (Strong keys, like Rigs.throttled: read later through fresh lookups, a weak entry could be
	-- collected with its userdata and a dead humanoid would look alive. Lives as long as the sim.)
	self.dead = {} -- raw humanoid -> true
	self.humState = {} -- raw humanoid -> HumanoidStateType
	self.walks = {} -- raw humanoid -> { target, started }
	self.mice = setmetatable({}, { __mode = "k" }) -- raw PlayerMouse -> state
	self.count = 0
	return self
end

function Players:list()
	local out = table.create(#self.order)
	for i, p in self.order do
		out[i] = self.sim.proxy:wrap(p)
	end
	return out
end

function Players:service()
	return self.sim.playersReal
end

local function deviceProfile(opts)
	local name = opts.device or "desktop"
	local base = DEVICES[name]
	if base == nil then
		error("RbxSim: unknown device '" .. tostring(name) .. "' (desktop, phone, tablet, console)", 3)
	end
	local d = table.clone(base)
	d.name = name
	d.viewport = nil
	return d, roblox.Vector2.new(base.viewport[1], base.viewport[2])
end

-- Joins a new player. Returns the raw Player.
function Players:add(opts)
	opts = opts or {}
	local sim = self.sim
	local proxy = sim.proxy
	self.count += 1
	local userId = opts.UserId or (1000 + self.count)
	for _, p in self.order do
		if p.UserId == userId then
			error("RbxSim: a player with UserId " .. tostring(userId) .. " is already in the game", 3)
		end
	end
	local name = opts.Name or ("Player" .. self.count)
	local real = Instance.new("Player")
	real.Name = name
	real.UserId = userId
	real.DisplayName = opts.DisplayName or name
	pcall(function()
		real.AccountAge = opts.AccountAge or 365
		real.MembershipType = opts.MembershipType or Enum.MembershipType.None
	end)
	for _, cls in { "Backpack", "PlayerGui", "PlayerScripts", "StarterGear" } do
		local c = Instance.new(cls)
		c.Name = cls
		c.Parent = real
	end
	local device, viewport = deviceProfile(opts)
	if opts.viewport then
		viewport = opts.viewport
	end
	local st = {
		real = real,
		device = device,
		viewport = viewport,
		keysDown = {},
		fromStarterGui = setmetatable({}, { __mode = "k" }),
		persistentClones = {},
		removed = false,
		clientStarted = false,
		clientDelay = opts.clientDelay,
		rig = opts.rig, -- nil | "R15" | "R6" (tools/sim/rigs.luau)
		joints = opts.joints, -- nil | "Motor6D" | "AnimationConstraint"
	}
	st.ctx = sim:_newContext("client", real)
	self.state[real] = st
	table.insert(self.order, real)

	proxy:setParent(real, self:service())
	proxy:getSignal(self:service(), "PlayerAdded"):Fire(proxy:wrap(real))

	if sim.started then
		self:_scheduleClientStart(real)
	end
	if self:service().CharacterAutoLoads then
		sim.sched:after(opts.characterDelay or 0, function()
			if not st.removed and real.Character == nil then
				self:loadCharacter(real)
			end
		end)
	end
	sim.sched:flush()
	return real
end

function Players:_scheduleClientStart(real)
	local st = self.state[real]
	local sim = self.sim
	if st.clientDelay and st.clientDelay > 0 then
		sim.sched:after(st.clientDelay, function()
			self:startClient(real)
		end)
	else
		-- queued behind the server's PlayerAdded handlers
		sim.sched:queueFn(function()
			self:startClient(real)
		end)
	end
end

-- Starts a player's client: ReplicatedFirst, StarterPlayerScripts, client scripts.
function Players:startClient(real)
	local st = self.state[real]
	if st == nil or st.clientStarted or st.removed then
		return
	end
	st.clientStarted = true
	local sim = self.sim
	local proxy = sim.proxy
	local runtime = sim.runtime
	local ctx = st.ctx
	local rf = sim.real:FindFirstChildOfClass("ReplicatedFirst")
	if rf then
		for _, s in rf:GetDescendants() do
			if s.ClassName == "LocalScript" then
				runtime:runOnce(s, ctx)
			end
		end
	end
	runtime:batch(function()
		local ps = real:FindFirstChildOfClass("PlayerScripts")
		local starterPlayer = sim.real:FindFirstChildOfClass("StarterPlayer")
		local sps = starterPlayer and starterPlayer:FindFirstChildOfClass("StarterPlayerScripts")
		if ps and sps then
			for _, c in sps:GetChildren() do
				local clone = c:Clone()
				if clone then
					proxy:setParent(clone, ps)
				end
			end
		end
	end)
	runtime:startClientRunContextScripts(ctx)
	-- LocalScripts placed into this player's containers before the client started
	for _, container in
		{ real:FindFirstChildOfClass("PlayerGui"), real:FindFirstChildOfClass("Backpack"), real.Character }
	do
		if container then
			for _, s in container:GetDescendants() do
				runtime:maybeRun(s)
			end
		end
	end
end

-- Removes a player like a disconnect (PlayerRemoving, character removal, client stop).
function Players:remove(real)
	local st = self.state[real]
	if st == nil or st.removed then
		return
	end
	st.removed = true
	local sim = self.sim
	local proxy = sim.proxy
	local sched = sim.sched
	proxy:getSignal(self:service(), "PlayerRemoving"):Fire(proxy:wrap(real))
	sched:queueFn(function()
		local char = real.Character
		if char then
			proxy:fire(real, "CharacterRemoving", proxy:wrap(char))
		end
		sched:queueFn(function()
			if char then
				self.byChar[char] = nil
				proxy:destroy(char)
			end
			sim:_killContext(st.ctx)
			sim.input:clearPlayer(real)
			local i = table.find(self.order, real)
			if i then
				table.remove(self.order, i)
			end
			proxy:setParent(real, nil)
			if sim.opts.destroyPlayerOnLeave then
				proxy:destroy(real)
			end
		end)
	end)
	sched:flush()
end

function Players:kick(real, message)
	table.insert(self.sim.Kicks, {
		player = self.sim.proxy:wrap(real),
		message = message and tostring(message) or "",
		time = self.sim.sched.clock,
	})
	self:remove(real)
end

-- Resolves the player owning an instance through PlayerGui/Backpack/PlayerScripts or a character.
function Players:ownerOf(inst)
	local cur = inst
	while cur ~= nil do
		local p = self.byChar[cur]
		if p then
			return p
		end
		local cls = cur.ClassName
		if cls == "PlayerGui" or cls == "Backpack" or cls == "PlayerScripts" or cls == "StarterGear" then
			local parent = cur.Parent
			if parent and parent.ClassName == "Player" then
				return parent
			end
			return nil
		end
		if cls == "Player" then
			return cur
		end
		cur = cur.Parent
	end
	return nil
end

function Players:setCharacter(real, char)
	local old = real.Character
	if old == char then
		return
	end
	if old then
		self.byChar[old] = nil
	end
	if char then
		self.byChar[char] = real
	end
	self.sim.proxy:setProperty(real, "Character", char)
end

-- Character -------------------------------------------------------------------------------

local function resetsOnSpawn(st, g)
	if g:IsA("LayerCollector") then
		local ok, v = pcall(function()
			return g.ResetOnSpawn
		end)
		return not ok or v ~= false
	end
	return st.fromStarterGui[g] == true
end

function Players:_spawnCFrame(real)
	local sim = self.sim
	local spawn = nil
	local loc = real.RespawnLocation
	if loc and loc:IsA("SpawnLocation") and loc:IsDescendantOf(sim.workspaceReal) then
		spawn = loc
	else
		local spawns = {}
		for _, d in sim.workspaceReal:GetDescendants() do
			if d:IsA("SpawnLocation") and d.Enabled then
				table.insert(spawns, d)
			end
		end
		if #spawns > 0 then
			spawn = spawns[sim.rng:NextInteger(1, #spawns)]
		end
	end
	if spawn then
		local top = spawn.CFrame.Position + Vector3.new(0, spawn.Size.Y / 2 + 3, 0)
		return CFrame.new(top)
	end
	return CFrame.new(0, 10, 0)
end

function Players:_buildCharacter(real)
	local char = Instance.new("Model")
	char.Name = real.Name
	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 100
	hum.Health = 100
	hum.WalkSpeed = 16
	hum.JumpPower = 50
	hum.JumpHeight = 7.2
	hum.HipHeight = 2
	local animator = Instance.new("Animator")
	animator.Parent = hum
	local hrp = Instance.new("Part")
	hrp.Name = "HumanoidRootPart"
	hrp.Size = Vector3.new(2, 2, 1)
	hrp.Transparency = 1
	hrp.CanCollide = false
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	hum.Parent = char
	hrp.Parent = char
	head.Parent = char
	char.PrimaryPart = hrp
	local cf = self:_spawnCFrame(real)
	hrp.CFrame = cf
	head.CFrame = cf * CFrame.new(0, 1.5, 0)
	local st = self.state[real]
	if st and st.rig then
		self.sim.rigs:build(char, real, st.rig, st.joints)
	end
	return char
end

function Players:loadCharacter(real)
	local st = self.state[real]
	if st == nil or st.removed then
		error("LoadCharacter can only be called when Player is in the world", 0)
	end
	local char
	self.sim.runtime:batch(function()
		char = self:_spawnCharacter(real, st)
	end)
	return char
end

function Players:_spawnCharacter(real, st)
	local sim = self.sim
	local proxy = sim.proxy
	local old = real.Character
	if old then
		proxy:fire(real, "CharacterRemoving", proxy:wrap(old))
		self.byChar[old] = nil
		proxy:destroy(old)
	end
	local pg = real:FindFirstChildOfClass("PlayerGui")
	if pg then
		for _, g in pg:GetChildren() do
			if resetsOnSpawn(st, g) then
				proxy:destroy(g)
			end
		end
	end
	local bp = real:FindFirstChildOfClass("Backpack")
	if bp then
		for _, t in bp:GetChildren() do
			proxy:destroy(t)
		end
	end

	local char = self:_buildCharacter(real)
	local starterPlayer = sim.real:FindFirstChildOfClass("StarterPlayer")
	local scs = starterPlayer and starterPlayer:FindFirstChildOfClass("StarterCharacterScripts")
	if scs then
		for _, c in scs:GetChildren() do
			local clone = c:Clone()
			if clone then
				clone.Parent = char
			end
		end
	end
	self.byChar[char] = real
	proxy:setParent(char, sim.workspaceReal)
	proxy:setProperty(real, "Character", char)
	proxy:fire(real, "CharacterAdded", proxy:wrap(char))

	local starterGui = sim.real:FindFirstChildOfClass("StarterGui")
	if pg and starterGui then
		for _, g in starterGui:GetChildren() do
			local persistent = g:IsA("LayerCollector") and g.ResetOnSpawn == false
			local skip = false
			if persistent then
				local prev = st.persistentClones[g]
				skip = prev ~= nil and not proxy:isDestroyed(prev) and prev.Parent == pg
			end
			if not skip then
				local clone = g:Clone()
				if clone then
					st.fromStarterGui[clone] = true
					if persistent then
						st.persistentClones[g] = clone
					end
					proxy:setParent(clone, pg)
				end
			end
		end
	end
	local starterPack = sim.real:FindFirstChildOfClass("StarterPack")
	if bp and starterPack then
		for _, t in starterPack:GetChildren() do
			local clone = t:Clone()
			if clone then
				proxy:setParent(clone, bp)
			end
		end
	end
	proxy:fire(real, "CharacterAppearanceLoaded", proxy:wrap(char))
	return char
end

-- Humanoid -----------------------------------------------------------------------------------

function Players:getHealth(hum)
	local ok, v = pcall(function()
		return hum.Health
	end)
	if ok and type(v) == "number" then
		return v
	end
	return hum.MaxHealth
end

function Players:setState(hum, state)
	local old = self.humState[hum] or Enum.HumanoidStateType.Running
	if old == state then
		return
	end
	self.humState[hum] = state
	self.sim.proxy:fire(hum, "StateChanged", old, state)
end

function Players:getState(hum)
	if self.dead[hum] then
		return Enum.HumanoidStateType.Dead
	end
	return self.humState[hum] or Enum.HumanoidStateType.Running
end

function Players:changeState(hum, state)
	if state == Enum.HumanoidStateType.Dead then
		self:setHealth(hum, 0)
	else
		self:setState(hum, state)
	end
end

function Players:setHealth(hum, value)
	if type(value) ~= "number" then
		error("Unable to assign property Health. number expected, got " .. typeof(value), 0)
	end
	local sim = self.sim
	local proxy = sim.proxy
	sim:_checkClientWrite(hum, "Health")
	local old = self:getHealth(hum)
	local new = math.clamp(value, 0, hum.MaxHealth)
	if new ~= new then
		new = 0
	end
	hum.Health = new
	if new ~= old then
		proxy:emitChanged(hum, "Health", new)
		proxy:fire(hum, "HealthChanged", new)
	end
	if new <= 0 and not self.dead[hum] then
		self.dead[hum] = true
		self:setState(hum, Enum.HumanoidStateType.Dead)
		self.walks[hum] = nil
		proxy:fire(hum, "Died")
		self:_scheduleRespawn(hum)
	end
end

function Players:isDead(hum): boolean
	return self.dead[hum] == true
end

function Players:_scheduleRespawn(hum)
	local char = hum.Parent
	local player = char and self.byChar[char]
	if player == nil then
		return
	end
	local service = self:service()
	if not service.CharacterAutoLoads then
		return
	end
	local st = self.state[player]
	self.sim.sched:after(service.RespawnTime, function()
		if st and not st.removed and player.Character == char then
			self:loadCharacter(player)
		end
	end)
end

-- Humanoid:MoveTo walks the root part at WalkSpeed (8s timeout like Roblox).
function Players:humanoidMoveTo(hum, pos, part)
	local target = pos
	local partReal = self.sim.proxy:toReal(part)
	if partReal and partReal:IsA("BasePart") then
		target = partReal.CFrame.Position + (typeof(pos) == "Vector3" and pos or Vector3.zero)
	end
	if typeof(target) ~= "Vector3" then
		error("Humanoid:MoveTo expects a Vector3", 0)
	end
	if self.dead[hum] then
		return
	end
	if self.sim.opts.instantMoveTo then
		local char = hum.Parent
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp then
			local y = hrp.CFrame.Position.Y
			self.sim.world:setPartCFrame(hrp, CFrame.new(target.X, y, target.Z) * hrp.CFrame.Rotation)
		end
		self.sim.proxy:fire(hum, "MoveToFinished", true)
		return
	end
	self.walks[hum] = { target = target, started = self.sim.sched.clock }
end

-- Per-frame walking update (called by the sim each frame).
function Players:update(dt: number)
	local sim = self.sim
	for hum, walk in self.walks do
		local char = hum.Parent
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp == nil or self.dead[hum] or sim.proxy:isDestroyed(hum) then
			self.walks[hum] = nil
		else
			local pos = hrp.CFrame.Position
			local goal = Vector3.new(walk.target.X, pos.Y, walk.target.Z)
			local delta = goal - pos
			local dist = delta.Magnitude
			local step = math.max(hum.WalkSpeed, 0) * dt
			if dist <= math.max(step, 0.05) then
				sim.world:setPartCFrame(hrp, CFrame.new(goal) * hrp.CFrame.Rotation)
				self.walks[hum] = nil
				sim.proxy:fire(hum, "MoveToFinished", true)
			elseif sim.sched.clock - walk.started >= MOVE_TIMEOUT then
				self.walks[hum] = nil
				sim.proxy:fire(hum, "MoveToFinished", false)
			elseif step > 0 then
				local newPos = pos + delta.Unit * step
				sim.world:setPartCFrame(hrp, CFrame.new(newPos) * hrp.CFrame.Rotation)
			end
		end
	end
end

function Players:isWalking(hum): boolean
	return self.walks[hum] ~= nil
end

-- Tools ---------------------------------------------------------------------------------------

local function toolFilter(_sim, player)
	return function(ctx)
		return ctx.kind == "server" or ctx.player == player
	end
end

function Players:equipTool(hum, tool)
	if tool == nil or not tool:IsA("Tool") then
		error("EquipTool: Tool expected", 0)
	end
	local char = hum.Parent
	if char == nil then
		return
	end
	self:unequipTools(hum)
	self.sim.proxy:setParent(tool, char)
end

function Players:unequipTools(hum)
	local char = hum.Parent
	local player = char and self.byChar[char]
	local bp = player and player:FindFirstChildOfClass("Backpack")
	if char == nil then
		return
	end
	for _, c in char:GetChildren() do
		if c:IsA("Tool") then
			if bp then
				self.sim.proxy:setParent(c, bp)
			else
				self.sim.proxy:setParent(c, nil)
			end
		end
	end
end

-- Called by the sim when a Tool moves between containers.
function Players:onToolMoved(tool, oldParent, newParent)
	local sim = self.sim
	local oldOwner = oldParent and self.byChar[oldParent]
	local newOwner = newParent and self.byChar[newParent]
	if oldOwner then
		sim.proxy:fireFiltered(tool, "Unequipped", toolFilter(sim, oldOwner))
	end
	if newOwner then
		sim.proxy:fireFiltered(tool, "Equipped", toolFilter(sim, newOwner), self:getMouse(newOwner))
	end
end

function Players:activateTool(tool)
	local char = tool.Parent
	local player = char and self.byChar[char]
	if player == nil or tool.Enabled == false then
		return false
	end
	self.sim.proxy:fireFiltered(tool, "Activated", toolFilter(self.sim, player))
	return true
end

function Players:deactivateTool(tool)
	local char = tool.Parent
	local player = char and self.byChar[char]
	if player == nil then
		return
	end
	self.sim.proxy:fireFiltered(tool, "Deactivated", toolFilter(self.sim, player))
end

-- Mouse -----------------------------------------------------------------------------------------

function Players:getMouse(real)
	local st = self.state[real]
	if st == nil then
		return nil
	end
	if st.mouse == nil then
		local m = Instance.new("PlayerMouse")
		m.Name = "Mouse"
		st.mouse = m
		self.mice[m] = { hit = CFrame.new(0, 0, -50), target = nil, x = 0, y = 0, filter = nil }
	end
	return self.sim.proxy:wrap(st.mouse)
end

function Players:mouseState(mouse)
	local s = self.mice[mouse]
	if s == nil then
		s = { hit = CFrame.new(), target = nil, x = 0, y = 0 }
		self.mice[mouse] = s
	end
	return s
end

return Players
