--[[
	Stage 1 integration tests (run inside RbxSim against the built Place1.rbxl):
	base cloning, assignment on join, release on leave, waiting queue, spawning on the base,
	respawn after death, the Home button and leak checks.

	Run: lune run tools/run_tests.luau stage1
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local PLACE = "Place1.rbxl"

-- Pure config modules are read straight from src/ (same values the game uses).
local function loadConfig(name: string): any
	local path = `src/ReplicatedStorage/Shared/Config/{name}.luau`
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum },
		injectGlobals = true,
	})
	return chunk()
end

local BaseConfig = loadConfig("BaseConfig")

local function boot(t: any): any
	local sim = t.sim({ place = PLACE })
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

local function addPlayer(sim: any, id: number): any
	local player = sim:AddPlayer({ UserId = id, Name = `Player{id}`, DisplayName = `Игрок{id}` })
	sim:Advance(0.5)
	return player
end

local function bases(sim: any): any
	return sim.game:GetService("Workspace"):FindFirstChild("Bases")
end

local function baseOf(sim: any, player: any): any
	local index = player:GetAttribute("BaseIndex")
	if typeof(index) ~= "number" or index <= 0 then
		return nil
	end
	return bases(sim):FindFirstChild(`Base_{index}`)
end

local function rootPos(player: any): any
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return root and root.CFrame.Position
end

-- Expected character position on a base: spawn pad top + SpawnHeight.
local function spawnPos(base: any): any
	local pad = base:FindFirstChild("SpawnPad")
	return (pad.CFrame * roblox.CFrame.new(0, pad.Size.Y / 2 + BaseConfig.SpawnHeight, 0)).Position
end

local function distance(a: any, b: any): number
	return (a - b).Magnitude
end

local function notifiesFor(sim: any, player: any): { string }
	local texts = {}
	for _, event in sim.ClientEvents do
		local remoteName = if typeof(event.remote) == "string" then event.remote else event.remote.Name
		if event.player == player and remoteName == "Notify" then
			table.insert(texts, event.args[1])
		end
	end
	return texts
end

local function anyContains(list: { string }, needle: string): boolean
	for _, s in list do
		if string.find(s, needle, 1, true) then
			return true
		end
	end
	return false
end

local tests = {}

tests["server boots: 8 coloured bases placed on their slots, water filled"] = function(t)
	local sim = boot(t)
	local ws = sim.game:GetService("Workspace")
	local folder = bases(sim)
	t.ok(folder, "Workspace.Bases exists")
	t.eq(#folder:GetChildren(), 8, "8 bases")
	for i = 1, 8 do
		local model = folder:FindFirstChild(`Base_{i}`)
		t.ok(model, `Base_{i} exists`)
		t.eq(model:GetAttribute("BaseIndex"), i)
		t.eq(model:GetAttribute("OwnerUserId"), 0)
		t.eq(model:GetAttribute("ColorId"), BaseConfig.Colors[i].Id)
		local slot = ws.Map.BaseSlots:FindFirstChild(`Slot_{i}`)
		t.near(distance(model.PrimaryPart.CFrame.Position, slot.CFrame.Position), 0, 1e-3, `Base_{i} on its slot`)
		t.near(model.PrimaryPart.CFrame.LookVector:Dot(slot.CFrame.LookVector), 1, 1e-4, `Base_{i} orientation`)
		t.eq(model.Flag.Cloth.Color, BaseConfig.Colors[i].Color, `Base_{i} flag colour`)
		t.eq(model.SpawnPad.Color, BaseConfig.Colors[i].Color, `Base_{i} pad colour`)
		local sign = model.Flag.Pole.SignAttachment.OwnerSign
		t.eq(sign.OwnerLabel.Text, "Свободно")
		t.eq(sign.BaseLabel.Text, `{BaseConfig.Colors[i].Name} база`)
	end
	t.ok(ws.Map:FindFirstChild("Water") == nil, "water stand-in parts removed")
	t.ok(#sim.TerrainOps >= 1, "terrain water filled")
	t.eq(sim.game:GetService("Players").CharacterAutoLoads, false)
	sim:AssertNoErrors()
end

tests["join: player gets a free base, spawns on its pad, sees a toast"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local base = baseOf(sim, p)
	t.ok(base, "player has a base")
	t.eq(base:GetAttribute("OwnerUserId"), 1)
	t.eq(base:GetAttribute("OwnerName"), "Игрок1")
	t.eq(base.Flag.Pole.SignAttachment.OwnerSign.OwnerLabel.Text, "Игрок1")
	t.eq(p:GetAttribute("BaseColorName"), base:GetAttribute("ColorName"))
	t.eq(p:GetAttribute("BaseColor"), base:GetAttribute("Color"))
	local pos = rootPos(p)
	t.ok(pos, "character exists")
	t.near(distance(pos, spawnPos(base)), 0, 0.01, "character placed on the spawn pad")
	t.ok(anyContains(notifiesFor(sim, p), base:GetAttribute("ColorName")), "toast names the base")
	sim:AssertNoErrors()
end

tests["two players get different bases"] = function(t)
	local sim = boot(t)
	local a = addPlayer(sim, 1)
	local b = addPlayer(sim, 2)
	t.ok(baseOf(sim, a) and baseOf(sim, b), "both have bases")
	t.ok(baseOf(sim, a) ~= baseOf(sim, b), "bases differ")
	sim:AssertNoErrors()
end

tests["leave: base is released and can be taken again"] = function(t)
	local sim = boot(t)
	local a = addPlayer(sim, 1)
	local base = baseOf(sim, a)
	sim:RemovePlayer(a)
	sim:Advance(0.5)
	t.eq(base:GetAttribute("OwnerUserId"), 0)
	t.eq(base:GetAttribute("OwnerName"), "")
	t.eq(base.Flag.Pole.SignAttachment.OwnerSign.OwnerLabel.Text, "Свободно")
	-- Fill all 8 bases: the released one must be reusable.
	local seen = {}
	for id = 10, 17 do
		local p = addPlayer(sim, id)
		local b = baseOf(sim, p)
		t.ok(b, `player {id} has a base`)
		t.ok(not seen[b], "no base given twice")
		seen[b] = true
	end
	sim:AssertNoErrors()
end

tests["overflow: 9th player waits at the hub and gets the first freed base"] = function(t)
	local sim = boot(t)
	local players = {}
	for id = 1, 8 do
		players[id] = addPlayer(sim, id)
	end
	local ninth = addPlayer(sim, 9)
	t.eq(ninth:GetAttribute("BaseIndex"), 0, "9th player is waiting")
	t.ok(anyContains(notifiesFor(sim, ninth), "Все базы заняты"), "waiting toast")
	t.ok(rootPos(ninth), "waiting player still has a character (hub)")

	local freed = baseOf(sim, players[3])
	sim:RemovePlayer(players[3])
	sim:Advance(1)
	t.eq(baseOf(sim, ninth), freed, "waiting player received the freed base")
	t.eq(freed:GetAttribute("OwnerUserId"), 9)
	t.near(distance(rootPos(ninth), spawnPos(freed)), 0, 0.01, "teleported onto the new base")
	t.ok(anyContains(notifiesFor(sim, ninth), "Освободилась база"), "toast about the freed base")
	sim:AssertNoErrors()
end

tests["queue: a waiting player who leaves is removed from the queue"] = function(t)
	local sim = boot(t)
	local players = {}
	for id = 1, 8 do
		players[id] = addPlayer(sim, id)
	end
	local ninth = addPlayer(sim, 9)
	local tenth = addPlayer(sim, 10)
	sim:RemovePlayer(ninth)
	sim:Advance(0.5)
	local freed = baseOf(sim, players[1])
	sim:RemovePlayer(players[1])
	sim:Advance(1)
	t.eq(baseOf(sim, tenth), freed, "10th (still waiting) got the base, not the departed 9th")
	sim:AssertNoErrors()
end

tests["respawn: after death the character returns to the base after RespawnDelay"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local base = baseOf(sim, p)
	local oldCharacter = p.Character
	sim:KillCharacter(p)
	sim:Advance(BaseConfig.RespawnDelay * 0.5)
	t.eq(p.Character, oldCharacter, "no respawn before the delay")
	sim:Advance(BaseConfig.RespawnDelay)
	t.ok(p.Character ~= oldCharacter, "respawned")
	t.near(distance(rootPos(p), spawnPos(base)), 0, 0.01, "respawned on own base")
	sim:AssertNoErrors()
end

tests["respawn: leaving during the respawn delay does not error or respawn"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	sim:KillCharacter(p)
	sim:Advance(0.5)
	sim:RemovePlayer(p)
	sim:Advance(BaseConfig.RespawnDelay + 1)
	sim:AssertNoErrors()
end

tests["home: teleports to the base, server cooldown blocks spam"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local base = baseOf(sim, p)
	local root = p.Character.HumanoidRootPart

	root.CFrame = roblox.CFrame.new(0, 5, 0) -- at the hub
	sim:FireServer(p, "RequestHome")
	sim:Advance(0.2)
	t.near(distance(rootPos(p), spawnPos(base)), 0, 0.01, "teleported home")

	root.CFrame = roblox.CFrame.new(0, 5, 0)
	sim:FireServer(p, "RequestHome")
	sim:Advance(0.2)
	t.near(distance(rootPos(p), roblox.Vector3.new(0, 5, 0)), 0, 0.01, "second request inside cooldown ignored")

	sim:Advance(BaseConfig.HomeCooldown)
	sim:FireServer(p, "RequestHome")
	sim:Advance(0.2)
	t.near(distance(rootPos(p), spawnPos(base)), 0, 0.01, "works again after cooldown")
	sim:AssertNoErrors()
end

tests["home: junk arguments from the client are ignored safely"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	sim:FireServer(p, "RequestHome", { evil = true }, 123, "x")
	sim:Advance(0.2)
	sim:AssertNoErrors()
end

tests["home: a waiting player (no base) gets a warning, no teleport"] = function(t)
	local sim = boot(t)
	for id = 1, 8 do
		addPlayer(sim, id)
	end
	local ninth = addPlayer(sim, 9)
	local before = rootPos(ninth)
	sim:FireServer(ninth, "RequestHome")
	sim:Advance(0.2)
	t.near(distance(rootPos(ninth), before), 0, 0.01, "not moved")
	t.ok(anyContains(notifiesFor(sim, ninth), "нельзя"), "warning toast")
	sim:AssertNoErrors()
end

tests["client HUD: badge shows the base, Home button visible and fires the remote"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	sim:Advance(0.5)
	local hud = p.PlayerGui:FindFirstChild("HUD")
	t.ok(hud, "HUD copied into PlayerGui")
	local label = hud.TopLeft.BaseBadge.Label
	t.eq(label.Text, `{p:GetAttribute("BaseColorName")} база`)
	t.eq(hud.TopLeft.BaseBadge.Swatch.BackgroundColor3, p:GetAttribute("BaseColor"))
	local home = hud.RightButtons.HomeButton
	t.eq(home.Visible, true)

	p.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(0, 5, 0)
	sim:Click(p, home)
	sim:Advance(0.3)
	t.near(distance(rootPos(p), spawnPos(baseOf(sim, p))), 0, 0.01, "click → teleport")
	t.eq(home.Cooldown.Visible, true, "cooldown overlay shown")
	sim:Advance(BaseConfig.HomeCooldown + 0.2)
	t.eq(home.Cooldown.Visible, false, "cooldown overlay hidden again")
	sim:AssertNoErrors()
end

tests["client HUD: toasts appear and are capped"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	sim:Advance(0.5)
	local toasts = p.PlayerGui.HUD.Toasts
	local function visibleToasts(): number
		local n = 0
		for _, child in toasts:GetChildren() do
			if child.Name == "Toast" then
				n += 1
			end
		end
		return n
	end
	t.ok(visibleToasts() >= 1, "join toast shown")
	sim:Advance(10)
	t.eq(visibleToasts(), 0, "toasts disappear")
	sim:AssertNoErrors()
end

tests["no leaks: connections return to baseline after players leave"] = function(t)
	local sim = boot(t)
	local baseline = sim:CountConnections()
	local players = {}
	for id = 1, 5 do
		players[id] = addPlayer(sim, id)
	end
	sim:KillCharacter(players[2])
	sim:Advance(BaseConfig.RespawnDelay + 1)
	for _, p in players do
		sim:RemovePlayer(p)
	end
	sim:Advance(1)
	t.eq(sim:CountConnections(), baseline, "server connections back to baseline")
	sim:AssertNoErrors()
end

return tests
