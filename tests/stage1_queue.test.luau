--[[
	Stage 1 integration tests, the waiting queue (run inside RbxSim against the built
	Place1.rbxl): all 8 bases taken — the 9th player waits at the hub, gets the first freed
	base (FIFO, also while dead), a waiting player who leaves drops out of the queue, Home
	without a base warns; a released base can be taken again; no connection leaks after many
	players leave. Split out of stage1_bases.test.luau (these fill all 8 bases — the slowest
	tests, kept well inside the runner's per-file time limit).

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
-- A free base's sign (UI v5 billboard words, BaseService).
local FREE = "СВОБОДНО!"

-- Toast texts on a player's own screen (HUD.Toasts.Toast.Label).
local function toastTexts(player: any): { string }
	local texts = {}
	local hud = player.PlayerGui:FindFirstChild("HUD")
	for _, child in (if hud then hud.Toasts:GetChildren() else {}) do
		if child.Name == "Toast" then
			table.insert(texts, child.Label.Text)
		end
	end
	return texts
end

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

-- Boots a sim whose ModuleScript sources are patched before the server starts.
local function bootPatched(t: any, patches: { { path: string, from: string, to: string } }): any
	local sim = t.sim({ place = PLACE })
	for _, patch in patches do
		local module = sim:Find(patch.path)
		t.ok(module, `module {patch.path} exists`)
		local source = module.Source
		local start = string.find(source, patch.from, 1, true)
		t.ok(start, `patch anchor found in {patch.path}`)
		module.Source = string.sub(source, 1, start - 1) .. patch.to .. string.sub(source, start + #patch.from)
	end
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

local tests = {}

tests["leave: base is released and can be taken again"] = function(t)
	local sim = boot(t)
	local a = addPlayer(sim, 1)
	local base = baseOf(sim, a)
	sim:RemovePlayer(a)
	sim:Advance(0.5)
	t.eq(base:GetAttribute("OwnerUserId"), 0)
	t.eq(base:GetAttribute("OwnerName"), "")
	t.eq(base.Flag.Pole.SignAttachment.OwnerSign.OwnerLabel.Text, FREE)
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
	-- The client announces it (in the base's colours): «Тебе досталась <Цвет> база!».
	t.ok(
		anyContains(toastTexts(ninth), `Тебе досталась {freed:GetAttribute("ColorName")} база!`),
		"toast about the freed base"
	)
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

tests["queue is FIFO: a newcomer in the same frame does not overtake a waiting player"] = function(t)
	-- In Roblox (Deferred events) a join processed in the same cycle as a leave runs BEFORE the
	-- deferred serveQueue. The sim flushes on RemovePlayer, so widen that window explicitly.
	local sim = bootPatched(t, {
		{
			path = "ServerScriptService.Services.BaseService",
			from = "task.defer(serveQueue)",
			to = "task.delay(0.5, serveQueue)",
		},
	})
	local players = {}
	for id = 1, 8 do
		players[id] = addPlayer(sim, id)
	end
	local waiting = addPlayer(sim, 9)
	local freed = baseOf(sim, players[4])
	-- Leave + join without advancing time in between (same frame).
	sim:RemovePlayer(players[4])
	local newcomer = sim:AddPlayer({ UserId = 10, Name = "Player10", DisplayName = "Игрок10" })
	sim:Advance(1)
	t.eq(baseOf(sim, waiting), freed, "the waiting player got the freed base")
	t.eq(newcomer:GetAttribute("BaseIndex"), 0, "the newcomer waits")
	sim:AssertNoErrors()
end

tests["queue: a dead waiting player's body is not moved; they respawn on the new base"] = function(t)
	local sim = boot(t)
	local players = {}
	for id = 1, 8 do
		players[id] = addPlayer(sim, id)
	end
	local waiting = addPlayer(sim, 9)
	local corpse = waiting.Character
	sim:KillCharacter(waiting)
	sim:Advance(0.2)
	local corpsePos = corpse.HumanoidRootPart.CFrame.Position
	local freed = baseOf(sim, players[2])
	sim:RemovePlayer(players[2])
	sim:Advance(0.5)
	t.eq(baseOf(sim, waiting), freed, "got the base while dead")
	t.near(distance(corpse.HumanoidRootPart.CFrame.Position, corpsePos), 0, 0.01, "corpse not teleported")
	sim:Advance(BaseConfig.RespawnDelay + 0.5)
	t.ok(waiting.Character ~= corpse, "respawned")
	t.near(distance(rootPos(waiting), spawnPos(freed)), 0, 0.01, "respawned on the new base")
	sim:AssertNoErrors()
end

return tests
