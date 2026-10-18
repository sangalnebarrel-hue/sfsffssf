--[[
	Stage 1 integration tests (run inside RbxSim against the built Place1.rbxl):
	base cloning, assignment on join, signs, the base template, spawning on the base, respawn
	after death and the Home button. The waiting queue, a released base taken again and the
	leak check (all 8 bases filled — the slowest tests) are in stage1_queue.test.luau.

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
local TextUtil = luau.load(fs.readFile("src/ReplicatedStorage/Shared/TextUtil.luau"))()
local upper = TextUtil.upper
-- A free base's sign (UI v5 billboard words, BaseService).
local FREE = "СВОБОДНО!"

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
		t.eq(sign.OwnerLabel.Text, FREE)
		t.eq(sign.BaseLabel.Text, upper(`{BaseConfig.Colors[i].Name} база`))
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

-- The fill gradient "Fill" of a sign's words (UI v5 billboard text): its top and bottom colours.
local function fillOf(label: any): (any, any)
	local keys = label.Fill.Color.Keypoints
	return keys[1].Value, keys[#keys].Value
end

local function near(a: any, b: any): boolean
	return math.abs(a.R - b.R) < 0.01 and math.abs(a.G - b.G) < 0.01 and math.abs(a.B - b.B) < 0.01
end

-- UI v5 «Симулятор»: the owner sign is the reference's billboard text — no plate, no studs.
tests["owner sign: billboard words over the flag — «СВОБОДНО!» green, the base name in its colour, no plate or studs"] = function(
	t
)
	local sim = boot(t)
	for i = 1, 8 do
		local model = bases(sim):FindFirstChild(`Base_{i}`)
		local swatch = UIConfig.BaseSwatches[BaseConfig.Colors[i].Id]
		local sign = model.Flag.Pole.SignAttachment.OwnerSign
		t.eq(sign.MaxDistance, 500, "readable across the lagoon")
		t.ok(sign.Size.X.Scale > 0 and sign.Size.X.Offset > 0, "studs + pixels")
		for _, d in sign:GetDescendants() do
			t.ok(not d:IsA("Frame"), `Base_{i}: no plate or stud ({d:GetFullName()})`)
		end
		-- the words: Montserrat Heavy, a round dark outline, white under a fill gradient
		local owner = sign.OwnerLabel
		t.eq(owner.FontFace.Weight, roblox.Enum.FontWeight.Heavy, "Heavy letters")
		t.ok(string.find(owner.FontFace.Family, "Montserrat", 1, true) ~= nil, "the UI font (Montserrat)")
		-- (SIMC-C2-05: a thin outline like the reference's billboard words — ≈ 0.06–0.1 of the cap
		-- across the lagoon, not a chunky HUD sticker)
		t.ok(
			owner.Outline.Thickness >= 1.5 and owner.Outline.Thickness <= 2.5,
			`a thin outline ({owner.Outline.Thickness} px)`
		)
		t.ok(sign.BaseLabel.Outline.Thickness <= owner.Outline.Thickness, "the base name's no heavier")
		t.ok(sign.YoursLabel.Outline.Thickness <= 2.5, "«ТВОЯ БАЗА!» thin too")
		t.eq(owner.Outline.LineJoinMode, roblox.Enum.LineJoinMode.Round, "round joins")
		local top, bottom = fillOf(owner)
		t.ok(
			near(top, UIConfig.BillboardGreen.Top) and near(bottom, UIConfig.BillboardGreen.Bottom),
			`Base_{i}: «СВОБОДНО!» in billboard green`
		)
		t.eq(owner.Outline.Color, UIConfig.BillboardGreen.Lip, "…outlined in its dark shade")
		local baseName = sign.BaseLabel
		top, bottom = fillOf(baseName)
		t.ok(near(top, swatch.Top) and near(bottom, swatch.Bottom), `Base_{i}: the base name in its colour`)
		t.eq(baseName.Outline.Color, swatch.Lip, "…outlined in its dark shade")
		t.eq(baseName.TextColor3, roblox.Color3.new(1, 1, 1), "white letters under the fill")
		-- «ТВОЯ БАЗА!»: there, hidden — only the owner's own client shows it
		t.eq(sign.YoursLabel.Text, "ТВОЯ БАЗА!")
		top = fillOf(sign.YoursLabel)
		t.ok(near(top, UIConfig.BillboardGreen.Top), "…in billboard green")
		-- the gate's labels in the same style
		local gate = model.Gate.Board.SignFront.OwnerLabel
		t.eq(gate.FontFace.Weight, roblox.Enum.FontWeight.Heavy, "gate: Heavy letters")
		t.ok(
			gate:FindFirstChild("Outline") ~= nil and gate:FindFirstChild("Fill") ~= nil,
			"gate: outlined billboard words"
		)
		t.ok(gate.Outline.Thickness <= 3, "gate: a thin outline (32 px per stud)")
	end
	sim:AssertNoErrors()
end

tests["owner sign: the owner's name in white; «ТВОЯ БАЗА!» shows on the owner's own client"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local base = baseOf(sim, p)
	local sign = base.Flag.Pole.SignAttachment.OwnerSign
	t.eq(sign.OwnerLabel.Text, "Игрок1")
	local top = fillOf(sign.OwnerLabel)
	t.ok(near(top, roblox.Color3.new(1, 1, 1)), "the owner's name in white")
	-- (the owner's client shows it: a client-local write, so read it as that client sees it)
	local function seen(who: any): boolean
		return sim:Run(function()
			return sign.YoursLabel.Visible
		end, who)
	end
	t.ok(
		sim:WaitFor(function()
			return seen(p)
		end, 2),
		"«ТВОЯ БАЗА!» over the own base (HudController)"
	)
	t.eq(seen(nil), false, "…only on the owner's client (others see the name and the base)")
	sim:RemovePlayer(p)
	sim:Advance(0.5)
	t.eq(sign.OwnerLabel.Text, FREE, "released")
	top = fillOf(sign.OwnerLabel)
	t.ok(near(top, UIConfig.BillboardGreen.Top), "…green again")
	sim:AssertNoErrors()
end

tests["sign GUIs: every SurfaceGui of a base has a MaxDistance; pedestal labels 30 px/stud within 60"] = function(t)
	local sim = boot(t)
	local model = bases(sim):FindFirstChild("Base_1")
	local count = 0
	for _, d in model:GetDescendants() do
		if d:IsA("SurfaceGui") then
			count += 1
			t.ok(d.MaxDistance > 0 and d.MaxDistance <= 250, `{d:GetFullName()}: MaxDistance {d.MaxDistance}`)
			if d.Name == "LabelGui" then
				t.eq(d.PixelsPerStud, 30, `{d:GetFullName()}: 30 px per stud`)
				t.eq(d.MaxDistance, 60, `{d:GetFullName()}: drawn within 60 studs`)
			end
		end
	end
	t.ok(count >= 15, `SurfaceGuis on a base: {count}`)
	sim:AssertNoErrors()
end

tests["movers: the base's boat and every swinging detail never collide, take rays or touches"] = function(t)
	local sim = boot(t)
	local model = bases(sim):FindFirstChild("Base_1")
	local movers = 0
	for _, d in model:GetDescendants() do
		local moving = false
		for _, kind in { "Bob", "Sway", "Spin", "Pulse", "Drift" } do
			local v = d:GetAttribute(kind)
			moving = moving or (typeof(v) == "number" and v ~= 0)
		end
		if moving then
			movers += 1
			for _, p in (if d:IsA("BasePart") then { d } else d:GetDescendants()) do
				if p:IsA("BasePart") then
					t.ok(
						not p.CanCollide and not p.CanQuery and not p.CanTouch,
						`{p:GetFullName()}: moved by the client, so no collisions / rays / touches`
					)
				end
			end
		end
	end
	t.ok(movers >= 10, `movers on a base: {movers}`)
	t.ok(model:FindFirstChild("Boat") and model.Boat:GetAttribute("Bob") ~= nil, "the moored boat bobs")
	sim:AssertNoErrors()
end

tests["pavilion: out of the fishing view (phone frame from the default follow camera)"] = function(t)
	local sim = boot(t)
	-- the Roblox default camera 12.5 studs behind the head over the spot, 18° down, vertical FOV 70,
	-- on a 844 x 390 phone: tan of the half angles 0.70 (vertical) and 0.70 × 844 / 390 across
	local tanV = math.tan(math.rad(35))
	local tanH = tanV * 844 / 390
	local pitch = math.rad(18)
	for i = 1, 8 do
		local model = bases(sim):FindFirstChild(`Base_{i}`)
		local root = model.PrimaryPart.CFrame
		local spot = root:PointToObjectSpace(model.FishingSpot.Position)
		local focus = roblox.Vector3.new(spot.X, spot.Y + 4.6, spot.Z)
		local eye = focus + roblox.Vector3.new(0, 12.5 * math.sin(pitch), 12.5 * math.cos(pitch))
		local fwd = roblox.Vector3.new(0, -math.sin(pitch), -math.cos(pitch))
		local up = roblox.Vector3.new(0, math.cos(pitch), -math.sin(pitch))
		for _, post in model.Pavilion:GetChildren() do
			if post:IsA("BasePart") and post.Name == "Post" then
				local cf = root:ToObjectSpace(post.CFrame)
				local h = post.Size / 2
				local inside = 0
				-- points over the post's box (corners, edges and faces at 1/10 steps)
				for a = 0, 10 do
					for b = 0, 10 do
						for _, c in { 0, 10 } do
							for _, perm in { { a, b, c }, { a, c, b }, { c, a, b } } do
								local q = cf
									* roblox.Vector3.new(
										(perm[1] / 5 - 1) * h.X,
										(perm[2] / 5 - 1) * h.Y,
										(perm[3] / 5 - 1) * h.Z
									)
								local r = q - eye
								local depth = r:Dot(fwd)
								local x = r.X
								local y = r:Dot(up)
								if depth > 0.3 and math.abs(x) <= tanH * depth and math.abs(y) <= tanV * depth then
									inside += 1
								end
							end
						end
					end
				end
				t.eq(inside, 0, `Base_{i}: {post:GetFullName()} in the phone's fishing view`)
			end
		end
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
			t.eq(label.Text, FREE, `Base_{i}: {label:GetFullName()}`)
		end
		local swatch = UIConfig.BaseSwatches[BaseConfig.Colors[i].Id]
		for _, label in labelsNamed(model, "BaseLabel") do
			t.eq(label.Text, upper(`{BaseConfig.Colors[i].Name} база`), `Base_{i}: {label:GetFullName()}`)
			local fill = label.Fill.Color.Keypoints[1].Value
			t.ok(
				math.abs(fill.R - swatch.Top.R) < 0.01 and math.abs(fill.B - swatch.Top.B) < 0.01,
				`Base_{i}: {label:GetFullName()} colour`
			)
		end
		t.eq(model.Gate.Board.SignFront.OwnerLabel.Text, FREE, `Base_{i}: gate sign`)
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
		t.eq(label.Text, FREE, `released: {label:GetFullName()}`)
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
	-- (tools/builder/BaseTemplate.luau BUDGET, DESIGN.md §3: one base at runtime, its own variant only)
	t.ok(parts <= 1060, `Base_1 has {parts} parts (budget 1060)`)
	sim:AssertNoErrors()
end

-- Base-local position (Root frame: -Z to the lagoon, y = 0 GroundTop) and the box half-extents of
-- a part in that frame.
local function localBox(root: any, part: any): (any, any)
	local cf = root:ToObjectSpace(part.CFrame)
	local s = part.Size / 2
	local ex = math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y + math.abs(cf.LookVector.X) * s.Z
	local ey = math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z
	local ez = math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z
	return cf.Position, roblox.Vector3.new(ex, ey, ez)
end

tests["base variants: every base keeps one pier scene, the 4 scenes repeat every 4 bases"] = function(t)
	local sim = boot(t)
	local seen = {}
	for i = 1, 8 do
		local model = bases(sim):FindFirstChild(`Base_{i}`)
		local scenes = model.PierKit.Scenes:GetChildren()
		t.eq(#scenes, 1, `Base_{i}: one scene left ({#scenes})`)
		local scene = scenes[1]
		t.eq(scene:GetAttribute("Variant"), (i - 1) % 4 + 1, `Base_{i}: its own variant`)
		seen[scene.Name] = true
		-- no instance of another base's variant anywhere in the base
		for _, d in model:GetDescendants() do
			local k, of = d:GetAttribute("Variant"), d:GetAttribute("VariantOf")
			if typeof(k) == "number" and typeof(of) == "number" then
				t.eq((i - 1) % of + 1, k, `Base_{i}: {d:GetFullName()} belongs here`)
			end
		end
	end
	local kinds = 0
	for _ in seen do
		kinds += 1
	end
	t.eq(kinds, 4, "four different pier scenes")
	sim:AssertNoErrors()
end

tests["pier and yard kits: decor only, clear walkway lane, camera and cast zones kept"] = function(t)
	local sim = boot(t)
	for i = 1, 8 do
		local model = bases(sim):FindFirstChild(`Base_{i}`)
		local root = model.PrimaryPart.CFrame
		local spot = root:PointToObjectSpace(model.FishingSpot.Position)
		for _, kitName in { "PierKit", "YardKit" } do
			for _, d in model[kitName]:GetDescendants() do
				if not d:IsA("BasePart") then
					continue
				end
				local name = d:GetFullName()
				t.ok(
					not d.CanCollide and not d.CanQuery and not d.CanTouch and not d.CastShadow,
					`{name}: decor flags (no collisions, raycasts, touches, shadows)`
				)
				if kitName ~= "PierKit" then
					continue
				end
				local p, e = localBox(root, d)
				-- the walkway's middle lane (x ±4.5 over the deck, z -50..0) stays free
				local onWalk = p.Z + e.Z > -50 and p.Z - e.Z < 0 and p.Y - e.Y < 3
				local battens = d.Name == "Batten"
				t.ok(battens or not onWalk or p.X - e.X >= 4.5 or p.X + e.X <= -4.5, `{name}: off the walkway lane`)
				-- the follow camera: nothing above y 7 within 13 studs of the spot, nothing over
				-- 1.5 tall right behind the player
				local dx, dz = p.X - spot.X, p.Z - spot.Z
				if math.sqrt(dx * dx + dz * dz) < 13 then
					t.ok(p.Y + e.Y <= 7.01, `{name}: below y 7 near the fishing spot ({p.Y + e.Y})`)
				end
				if math.abs(p.X) - e.X < 7 and p.Z + e.Z > -67 and p.Z - e.Z < -55 then
					t.ok(p.Y + e.Y <= 0.75 + 1.5, `{name}: low behind the player ({p.Y + e.Y})`)
				end
			end
		end
		-- the cast clear zone (x -6..16, z -72..-115): nothing of the base above the water there
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				local p, e = localBox(root, d)
				if p.X + e.X > -6 and p.X - e.X < 16 and p.Z - e.Z < -72 and p.Z + e.Z > -115 then
					t.ok(p.Y + e.Y <= -4.6, `Base_{i}: {d:GetFullName()} above the water in the cast zone`)
				end
			end
		end
	end
	sim:AssertNoErrors()
end

tests["moving details: Sway marks carry a valid axis, period and a hang point on the part"] = function(t)
	local sim = boot(t)
	local model = bases(sim):FindFirstChild("Base_1")
	local count = 0
	for _, d in model:GetDescendants() do
		local amp = d:GetAttribute("Sway")
		if amp == nil then
			continue
		end
		count += 1
		local name = d:GetFullName()
		t.ok(typeof(amp) == "number" and amp > 0 and amp <= 30, `{name}: Sway {amp}°`)
		local axis = d:GetAttribute("SwayAxis")
		t.ok(axis == "X" or axis == "Y" or axis == "Z", `{name}: SwayAxis {axis}`)
		local period = d:GetAttribute("SwayPeriod")
		t.ok(typeof(period) == "number" and period > 0.5, `{name}: SwayPeriod {period}`)
		local primary = if d:IsA("BasePart") then d else d.PrimaryPart
		t.ok(primary ~= nil, `{name}: has a pivot part`)
		if primary then
			local pivot = (primary.CFrame * primary.PivotOffset).Position
			-- the hang point lies on (or right beside) the swinging part
			local o = primary.CFrame:PointToObjectSpace(pivot)
			local h = primary.Size / 2 + roblox.Vector3.new(4, 4, 4)
			t.ok(math.abs(o.X) <= h.X and math.abs(o.Y) <= h.Y and math.abs(o.Z) <= h.Z, `{name}: pivot near the part`)
		end
		local parts = if d:IsA("BasePart") then { d } else {}
		for _, p in d:GetDescendants() do
			if p:IsA("BasePart") then
				table.insert(parts, p)
			end
		end
		for _, p in parts do
			t.ok(not p.CanCollide and not p.CanQuery, `{p:GetFullName()}: a swinging part never collides or takes rays`)
		end
	end
	t.ok(count >= 10, `swinging details on a base: {count}`)
	t.ok(model.Flag.Cloth:GetAttribute("Sway") ~= nil, "the flag's cloth flutters")
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
	-- Stage 4: the pup is its own sub-model (one PivotTo moves it, the kennel stays), and a fresh
	-- base has it at the template's pivot (DefenceService restores exactly that on unmount).
	local pup = model.Dog:FindFirstChild("Pup")
	t.ok(pup and pup:IsA("Model") and pup.PrimaryPart and pup.PrimaryPart.Name == "Body", "Dog.Pup (PrimaryPart Body)")
	t.ok(model.Dog.PrimaryPart == pup.PrimaryPart, "Dog.PrimaryPart is the pup's Body")
	local pupParts = 0
	for _, d in pup:GetDescendants() do
		if d:IsA("BasePart") then
			pupParts += 1
		end
	end
	t.eq(pupParts, 13, "the pup's 13 parts")
	t.ok(model.Dog:FindFirstChild("DogHouse"), "the kennel Dog.DogHouse")
	local template = sim.game:GetService("ServerStorage"):FindFirstChild("BaseTemplate")
	local function pupOffset(base: any): any
		return base.PrimaryPart.CFrame:ToObjectSpace(base.Dog.Pup:GetPivot())
	end
	local want, got = pupOffset(template), pupOffset(model)
	t.near(got.Position, want.Position, 1e-3, "the pup at its template pivot (position)")
	t.near(got.LookVector, want.LookVector, 1e-3, "the pup at its template pivot (facing)")
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

-- Stage 3 (TankService): an owned base shows its tank — the open displays «Пусто», the closed
-- ones «🔒 Закрыто»; a free base again shows «Пусто» everywhere.
tests["owned base: open displays «Пусто», closed ones «🔒 Закрыто»; free again after leave"] = function(
	t
)
	local sim = boot(t)
	local TankConfig = loadConfig("TankConfig")
	local p = addPlayer(sim, 1)
	sim:WaitFor(function()
		return p:GetAttribute("DataMode") ~= "Loading"
	end, 5)
	local base = baseOf(sim, p)
	for i = 1, TankConfig.MaxSlots do
		local slot = base.Tank.Slots:FindFirstChild(`Slot_{i}`)
		local open = i <= TankConfig.StartSlots
		t.eq(
			slot.Pedestal.LabelGui.Label.Text,
			if open then TankConfig.Texts.SlotEmpty else TankConfig.Texts.SlotLocked,
			`Slot_{i} label`
		)
		t.eq(slot:GetAttribute("State"), if open then "empty" else "locked", `Slot_{i} State`)
	end
	t.eq(base.Tank:GetAttribute("Slots"), TankConfig.StartSlots)
	t.eq(base.Tank.Glass.PromptAttachment.TankPrompt.Enabled, true, "the tank prompt is on for the owner")
	sim:RemovePlayer(p)
	sim:Advance(0.5)
	for i = 1, TankConfig.MaxSlots do
		local slot = base.Tank.Slots:FindFirstChild(`Slot_{i}`)
		t.eq(slot.Pedestal.LabelGui.Label.Text, TankConfig.Texts.SlotEmpty, `Slot_{i} free again`)
		t.eq(slot:GetAttribute("State"), "empty")
	end
	t.eq(base.Tank.Glass.PromptAttachment.TankPrompt.Enabled, false, "the prompt is off on a free base")
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
	-- (a plain Top → Bottom gradient).
	local swatch = UIConfig.BaseSwatches[baseOf(sim, p):GetAttribute("ColorId")]
	local top = hud.Status.BaseBadge.Swatch.Fill.Color.Keypoints[1].Value
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
