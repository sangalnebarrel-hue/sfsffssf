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
local UIConfig = loadConfig("UIConfig")

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

-- BaseService rule for Accent parts: the base colour, lerped towards white (AccentShade > 0) by
-- |AccentShade|, or darkened in HSV (AccentShade < 0: value down, saturation up, warm hues redder).
local function shaded(color: any, shade: any): any
	if typeof(shade) ~= "number" or shade == 0 then
		return color
	end
	local amount = math.clamp(math.abs(shade), 0, 1)
	if shade > 0 then
		return color:Lerp(roblox.Color3.new(1, 1, 1), amount)
	end
	local h, s, v = color:ToHSV()
	if h > 0.02 and h < 0.2 and amount > 0.3 then
		h -= 0.04 * (amount - 0.3) / 0.7 -- light shades keep their hue (yellow stays yellow)
	end
	return roblox.Color3.fromHSV(h, math.min(1, s * (1 + 0.15 * amount)), v * (1 - 0.6 * amount))
end

local function luminance(c: any): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

-- All TextLabels with the given name anywhere in the base model.
local function labelsNamed(model: any, name: string): { any }
	local found = {}
	for _, d in model:GetDescendants() do
		if d:IsA("TextLabel") and d.Name == name then
			table.insert(found, d)
		end
	end
	return found
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

tests["server boots: 8 coloured bases placed on their slots"] = function(t)
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
	-- Terrain is baked into the place (tests/worldgen.test.luau covers it); no water stand-ins.
	t.ok(ws.Map:FindFirstChild("Water") == nil, "no water stand-in parts")
	t.eq(sim.game:GetService("Players").CharacterAutoLoads, false)
	sim:AssertNoErrors()
end

tests["accent parts are painted in the base colour, AccentShade gives lighter/darker variants"] = function(t)
	local sim = boot(t)
	for i = 1, 8 do
		local model = bases(sim):FindFirstChild(`Base_{i}`)
		local color = BaseConfig.Colors[i].Color
		local plain, lighter, darker = 0, 0, 0
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d:GetAttribute("Accent") == true then
				local shade = d:GetAttribute("AccentShade")
				-- dark shades are scaled per colour (BaseConfig RoofShadeScale; 0 = no darkening)
				if typeof(shade) == "number" and shade < 0 then
					shade *= BaseConfig.Colors[i].RoofShadeScale or 1
				end
				local expected = shaded(color, shade)
				local delta = math.max(
					math.abs(d.Color.R - expected.R),
					math.abs(d.Color.G - expected.G),
					math.abs(d.Color.B - expected.B)
				)
				t.ok(delta < 1e-3, `Base_{i}.{d:GetFullName()}: colour {d.Color} ≠ {expected} (shade {shade})`)
				if typeof(shade) ~= "number" or shade == 0 then
					plain += 1
				elseif shade > 0 then
					lighter += 1
					t.ok(luminance(d.Color) > luminance(color), `Base_{i}: {d.Name} lighter than the base colour`)
				else
					darker += 1
					t.ok(luminance(d.Color) < luminance(color), `Base_{i}: {d.Name} darker than the base colour`)
				end
			end
		end
		local needDarker = (BaseConfig.Colors[i].RoofShadeScale or 1) > 0
		t.ok(
			plain > 0 and lighter > 0 and (darker > 0 or not needDarker),
			`Base_{i}: plain {plain}, lighter {lighter}, darker {darker}`
		)
	end
	sim:AssertNoErrors()
end

tests["gate sign: every OwnerLabel/BaseLabel shows the owner and the base name"] = function(t)
	local sim = boot(t)
	for i = 1, 8 do
		local model = bases(sim):FindFirstChild(`Base_{i}`)
		local owners = labelsNamed(model, "OwnerLabel")
		t.ok(#owners >= 3, `Base_{i}: flag + both gate faces carry OwnerLabel ({#owners})`)
		for _, label in owners do
			t.eq(label.Text, "Свободно", `Base_{i}: {label:GetFullName()}`)
		end
		for _, label in labelsNamed(model, "BaseLabel") do
			t.eq(label.Text, `{BaseConfig.Colors[i].Name} база`, `Base_{i}: {label:GetFullName()}`)
			t.eq(label.TextColor3, BaseConfig.Colors[i].Color, `Base_{i}: {label:GetFullName()} colour`)
		end
		t.eq(model.Gate.Board.SignFront.OwnerLabel.Text, "Свободно", `Base_{i}: gate sign`)
	end

	local p = addPlayer(sim, 1)
	local base = baseOf(sim, p)
	t.eq(base.Gate.Board.SignFront.OwnerLabel.Text, "Игрок1", "gate sign (promenade side) shows the owner")
	t.eq(base.Gate.Board.SignBack.OwnerLabel.Text, "Игрок1", "gate sign (yard side) shows the owner")
	for _, label in labelsNamed(base, "OwnerLabel") do
		t.eq(label.Text, "Игрок1", label:GetFullName())
	end

	sim:RemovePlayer(p)
	sim:Advance(0.5)
	for _, label in labelsNamed(base, "OwnerLabel") do
		t.eq(label.Text, "Свободно", `released: {label:GetFullName()}`)
	end
	sim:AssertNoErrors()
end

tests["base template: within the part budget, the base colour only on small parts or in a deep shade"] = function(t)
	local sim = boot(t)
	local model = bases(sim):FindFirstChild("Base_1")
	local parts = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			-- art direction v4 (tools/builder/DESIGN.md §1): the team colour never floods a big
			-- surface; big Accent parts (roofs) use a deep shade of it
			if d:GetAttribute("Accent") == true then
				local s = d.Size
				local area = s.X * s.Z + 2 * s.Y * (s.X + s.Z)
				local shade = d:GetAttribute("AccentShade")
				local deep = typeof(shade) == "number" and shade <= -0.25
				t.ok(
					area <= 400 or deep,
					`{d:GetFullName()}: {math.floor(area)} studs² of base colour (shade {shade})`
				)
			end
		end
	end
	t.ok(parts <= 940, `BaseTemplate has {parts} parts (budget 940)`)
	sim:AssertNoErrors()
end

tests["base template: market arcades keep a clear aisle, the displays stand against a solid back wall"] = function(t)
	local sim = boot(t)
	local model = bases(sim):FindFirstChild("Base_1")
	local root = model.PrimaryPart.CFrame
	-- |x| of a part's inner (aisle-side) and outer faces in the base-local frame
	local function span(part: any): (number, number)
		local c = root:PointToObjectSpace(part.Position)
		local half = part.Size.X / 2
		if math.abs(part.CFrame.RightVector:Dot(root.RightVector)) < 0.5 then
			half = part.Size.Z / 2 -- turned a quarter: its local Z runs across the arcade
		end
		return math.abs(c.X) - half, math.abs(c.X) + half
	end
	for _, side in { "West", "East" } do
		local arcade = model.Arcades:FindFirstChild(side)
		t.ok(arcade, `Arcades.{side}`)
		local wall = arcade:FindFirstChild("BackWall")
		t.ok(wall and wall:IsA("BasePart"), `Arcades.{side}.BackWall`)
		local wallInner = span(wall)
		local postOuter, roofs = 0, 0
		for _, d in arcade:GetChildren() do
			if d:IsA("BasePart") and d.Name == "Post" then
				local _, outer = span(d)
				postOuter = math.max(postOuter, outer)
			elseif d:IsA("BasePart") and d.Name == "Roof" then
				roofs += 1
			end
		end
		t.ok(roofs >= 6, `Arcades.{side}: gabled market bays ({roofs} roof slopes)`)
		for i = if side == "West" then 1 else 2, 12, 2 do
			local slot = model.Tank.Slots:FindFirstChild(`Slot_{i}`)
			local cabinetFront = span(slot.Pedestal)
			t.ok(cabinetFront - postOuter >= 6, `Slot_{i}: aisle {cabinetFront - postOuter} studs wide (>= 6)`)
			local _, backdropOuter = span(slot.Backdrop)
			t.ok(
				backdropOuter <= wallInner + 1e-3 and wallInner - backdropOuter < 0.3,
				`Slot_{i}: backdrop against the back wall ({wallInner - backdropOuter})`
			)
		end
	end
	sim:AssertNoErrors()
end

tests["base template: 12 display slots, tank prompt, alarm, dog (names the server relies on)"] = function(t)
	local sim = boot(t)
	local model = bases(sim):FindFirstChild("Base_1")
	t.ok(model.Tank.Glass:IsA("BasePart") and model.Tank.Glass.PromptAttachment:IsA("Attachment"), "tank prompt")
	t.ok(model.Alarm.Lamp:IsA("BasePart"), "alarm lamp")
	t.ok(model.Dog:IsA("Model") and model.Dog.PrimaryPart ~= nil, "dog with PrimaryPart")
	-- The guard dog is a stage 4 upgrade: hidden (not on display) until it is bought.
	t.eq(model.Dog:GetAttribute("Unlocked"), false, "dog not unlocked")
	for _, d in model.Dog:GetDescendants() do
		if d:IsA("BasePart") then
			t.eq(d.Transparency, 1, `{d.Name} invisible`)
			t.ok(not d.CanCollide and not d.CanQuery and not d.CastShadow, `{d.Name}: no collisions, raycasts, shadows`)
		end
	end
	t.ok(model.FishingSpot:IsA("BasePart"), "fishing spot")
	local spawnPos = model.SpawnPad.CFrame.Position
	local dist = {}
	for i = 1, 12 do
		local slot = model.Tank.Slots:FindFirstChild(`Slot_{i}`)
		t.ok(slot, `Slot_{i} exists`)
		t.eq(slot:GetAttribute("SlotIndex"), i, `Slot_{i} SlotIndex`)
		local pedestal, display = slot:FindFirstChild("Pedestal"), slot:FindFirstChild("Display")
		t.ok(pedestal and pedestal:IsA("BasePart"), `Slot_{i}.Pedestal`)
		t.ok(display and display:IsA("BasePart"), `Slot_{i}.Display`)
		t.ok(pedestal:FindFirstChild("PromptAttachment"), `Slot_{i}.Pedestal.PromptAttachment`)
		t.eq(pedestal.LabelGui.Label.Text, "Пусто", `Slot_{i} label`)
		local fishPoint = display:FindFirstChild("FishPoint")
		t.ok(fishPoint and fishPoint:IsA("Attachment"), `Slot_{i}.Display.FishPoint`)
		local fishWorld = (display.CFrame * fishPoint.CFrame).Position
		t.near(fishWorld, display.CFrame.Position, 1e-3, `Slot_{i}: fish point in the display centre`)
		dist[i] = distance(pedestal.CFrame.Position, spawnPos)
	end
	-- The starting slots 1..3 are the nearest to the entrance.
	local farthestStarter = math.max(dist[1], dist[2], dist[3])
	for i = 4, 12 do
		t.ok(dist[i] >= farthestStarter - 1e-3, `Slot_{i} is not nearer to the spawn than slots 1..3`)
	end
	sim:AssertNoErrors()
end

tests["join: player gets a free base, spawns on its pad, sees the base banner"] = function(t)
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
	-- The welcome is the client's big banner (HudController), not a server toast (UI v2, HUD-04).
	local banner = p.PlayerGui.HUD.BaseBanner
	t.eq(banner.Visible, true, "the base banner is up")
	t.eq(banner.Caption.Text, "ТВОЯ БАЗА")
	t.ok(#banner.NameLabel.Text > 1, "the banner names the base")
	t.eq(#notifiesFor(sim, p), 0, "no welcome toast from the server")
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
	local label = hud.Status.BaseBadge.Label
	local TextUtil = sim:Require(sim:Find("ReplicatedStorage.Shared.TextUtil"), p)
	t.eq(label.Text, `{TextUtil.upper(p:GetAttribute("BaseColorName"))} БАЗА`, "the base name in CAPS")
	-- The badge wears the base's clean swatch (UIConfig.BaseSwatches), not a tinted base colour
	-- (a brick: its Top sits under the light cap, at UIConfig.Brick.CapStop).
	local swatch = UIConfig.BaseSwatches[baseOf(sim, p):GetAttribute("ColorId")]
	local top = nil
	for _, key in hud.Status.BaseBadge.Swatch.Fill.Color.Keypoints do
		if math.abs(key.Time - UIConfig.Brick.CapStop) < 1e-3 then
			top = key.Value
		end
	end
	t.eq(top, swatch.Top)
	t.eq(hud.Status.BaseBadge.Lip.BackgroundColor3, swatch.Lip)
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
	t.eq(p.PlayerGui.HUD.BaseBanner.Visible, true, "join banner shown")
	sim:Find("ReplicatedStorage.Remotes.Notify"):FireClient(p, "Привет!", "info")
	sim:Advance(0.1)
	t.ok(visibleToasts() >= 1, "a server toast shown")
	sim:Advance(10)
	t.eq(visibleToasts(), 0, "toasts disappear")
	t.eq(p.PlayerGui.HUD.BaseBanner.Visible, false, "the banner has flown into the badge")
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

tests["debug knob BaseConfig.MaxBases limits the number of bases"] = function(t)
	local sim = bootPatched(t, {
		{
			path = "ReplicatedStorage.Shared.Config.BaseConfig",
			from = "MaxBases = nil :: number?",
			to = "MaxBases = 2 :: number?",
		},
	})
	t.eq(#bases(sim):GetChildren(), 2, "only 2 bases")
	addPlayer(sim, 1)
	addPlayer(sim, 2)
	local third = addPlayer(sim, 3)
	t.eq(third:GetAttribute("BaseIndex"), 0, "third player waits")
	sim:AssertNoErrors()
end

tests["spawn: a failed LoadCharacterAsync is retried"] = function(t)
	local sim = bootPatched(t, {
		{
			path = "ServerScriptService.Services.BaseService",
			from = "player:LoadCharacterAsync()",
			to = "if (_G.FailLoads or 0) > 0 then _G.FailLoads -= 1; error('test failure') end player:LoadCharacterAsync()",
		},
	})
	sim:Globals("server").FailLoads = 2
	local p = sim:AddPlayer({ UserId = 1, Name = "Player1", DisplayName = "Игрок1" })
	sim:Advance(0.5)
	t.ok(p.Character == nil, "no character after the first failure")
	sim:Advance(5)
	t.ok(p.Character ~= nil, "character created after retries")
	t.near(distance(rootPos(p), spawnPos(baseOf(sim, p))), 0, 0.01, "on its base")
	t.ok(p.PlayerGui:FindFirstChild("HUD"), "HUD arrived")
	sim:AssertNoErrors()
end

tests["spawn: after repeated failures the player is kicked with a message"] = function(t)
	local sim = bootPatched(t, {
		{
			path = "ServerScriptService.Services.BaseService",
			from = "player:LoadCharacterAsync()",
			to = "if (_G.FailLoads or 0) > 0 then _G.FailLoads -= 1; error('test failure') end player:LoadCharacterAsync()",
		},
	})
	sim:Globals("server").FailLoads = 100
	local p = sim:AddPlayer({ UserId = 1, Name = "Player1", DisplayName = "Игрок1" })
	sim:Advance(15)
	t.eq(#sim.Kicks, 1, "kicked once")
	t.eq(p.Parent, nil, "player removed")
	sim:AssertNoErrors()
end

tests["spawn: a pending retry does not respawn a character created meanwhile"] = function(t)
	local sim = bootPatched(t, {
		{
			path = "ServerScriptService.Services.BaseService",
			from = "player:LoadCharacterAsync()",
			to = "if (_G.FailLoads or 0) > 0 then _G.FailLoads -= 1; error('test failure') end player:LoadCharacterAsync()",
		},
	})
	sim:Globals("server").FailLoads = 1
	local p = sim:AddPlayer({ UserId = 1, Name = "Player1", DisplayName = "Игрок1" })
	sim:Advance(0.5) -- first load failed, retry scheduled in 2 s
	local BaseService = sim:Require(sim:Find("ServerScriptService.Services.BaseService"))
	sim:Run(function()
		BaseService:RespawnPlayer(p)
	end)
	sim:Advance(0.2)
	local character = p.Character
	t.ok(character ~= nil, "RespawnPlayer created a character")
	sim:Advance(3)
	t.eq(p.Character, character, "the old retry did not replace it")
	sim:AssertNoErrors()
end

tests["respawn: death + a failed RespawnPlayer give exactly one respawn"] = function(t)
	local sim = bootPatched(t, {
		{
			path = "ServerScriptService.Services.BaseService",
			from = "player:LoadCharacterAsync()",
			to = "if (_G.FailLoads or 0) > 0 then _G.FailLoads -= 1; error('test failure') end player:LoadCharacterAsync()",
		},
	})
	local p = addPlayer(sim, 1)
	local spawns = 0
	p.CharacterAdded:Connect(function()
		spawns += 1
	end)
	sim:KillCharacter(p) -- death respawn due in RespawnDelay (3 s)
	sim:Advance(2.5) -- the failed RespawnPlayer's retry (2 s later) lands after the death respawn
	sim:Globals("server").FailLoads = 1
	local BaseService = sim:Require(sim:Find("ServerScriptService.Services.BaseService"))
	sim:Run(function()
		BaseService:RespawnPlayer(p) -- fails, schedules a retry
	end)
	sim:Advance(6)
	t.eq(spawns, 1, "exactly one new character")
	t.near(distance(rootPos(p), spawnPos(baseOf(sim, p))), 0, 0.01, "on own base")
	sim:AssertNoErrors()
end

tests["spawn: a character loaded outside BaseService still ends up on the base"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	sim:Run(function()
		p:LoadCharacterAsync()
	end)
	sim:Advance(0.5)
	t.near(distance(rootPos(p), spawnPos(baseOf(sim, p))), 0, 0.01, "placed on own base")
	sim:AssertNoErrors()
end

tests["RespawnPlayer API respawns the character on the base"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local old = p.Character
	local BaseService = sim:Require(sim:Find("ServerScriptService.Services.BaseService"))
	sim:Run(function()
		BaseService:RespawnPlayer(p)
	end)
	sim:Advance(0.5)
	t.ok(p.Character ~= old, "new character")
	t.near(distance(rootPos(p), spawnPos(baseOf(sim, p))), 0, 0.01, "on own base")
	sim:AssertNoErrors()
end

tests["Main: a service whose Init fails is reported and the others still start"] = function(t)
	local sim = bootPatched(t, {
		{
			path = "ServerScriptService.Services.MapService",
			from = "function MapService:Init()",
			to = "function MapService:Init()\n\terror('broken map')",
		},
	})
	local p = addPlayer(sim, 1)
	t.ok(baseOf(sim, p), "BaseService still works")
	local found = false
	for _, w in sim.Warnings do
		local text = if typeof(w) == "table" then tostring(w.message) else tostring(w)
		if string.find(text, "MapService", 1, true) and string.find(text, "broken map", 1, true) then
			found = true
		end
	end
	t.ok(found, "failure of MapService reported in Output")
	sim:AssertNoErrors()
end

tests["home: the server tolerates network jitter at the end of the cooldown"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local base = baseOf(sim, p)
	sim:FireServer(p, "RequestHome")
	sim:Advance(BaseConfig.HomeCooldown - 0.3)
	p.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(0, 5, 0)
	sim:FireServer(p, "RequestHome")
	sim:Advance(0.1)
	t.near(distance(rootPos(p), spawnPos(base)), 0, 0.01, "accepted 0.3 s early")
	sim:AssertNoErrors()
end

tests["client HUD: right buttons move down on desktop, stay above the jump zone on phones"] = function(t)
	local sim = boot(t)
	local phone = sim:AddPlayer({ UserId = 1, Name = "Phone", device = "phone" })
	local desktop = sim:AddPlayer({ UserId = 2, Name = "Desktop", device = "desktop" })
	sim:Advance(1)
	t.near(phone.PlayerGui.HUD.RightButtons.Position.Y.Scale, 0.64, 1e-6, "phone keeps the column above Jump")
	t.near(desktop.PlayerGui.HUD.RightButtons.Position.Y.Scale, 0.96, 1e-6, "desktop column moved down")
	sim:AssertNoErrors()
end

return tests
