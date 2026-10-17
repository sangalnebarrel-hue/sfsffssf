--[[
	Stage 3 world (TankWorldController + TankDisplay) on the real client, against the replicated
	state of design §4.6 written by the test: the stage 3 services (TankService, DataService,
	EconomyService, MarketService) and FishingService are switched off ("return {}"), and a small
	fake server below writes the display / tank / player attributes exactly like TankService does
	(fish fields → State → Event LAST, "<n>|kind|detail" with n monotonic per base, AttrTime for
	GrowFrom) and makes the "TankPrompt" of every base.

	What is checked (design §7.4):
	  • display fish: a model per occupied display, its bounding box centred on Display.FishPoint
	    (≤ 0.1) and inside the 6.2 cube, the right species / mutation, ≤ 20 parts, no collisions /
	    queries / touches / shadows; removed on "empty"; a swap (State stays "fish", FishUid
	    changes) replaces the model; nothing beyond Display.Range, torn down only beyond
	    DropRange (hysteresis); ≤ BuildPerCheck quiet builds per check; the life tween only within
	    LifeRange (the Body moves), cancelled beyond (the fish rests);
	  • words: the tags «+$4/с» / «$45 ▲» ticking to «МАКС»; the tank sign «+$42/с» / «🐠 4/6» on
	    an owned, mounted tank only; the pier word «🐠 4/6» / «+$42/с» on the own base only,
	    hidden on Bite / Reeling / CounterHold / HeldFish, a splash on a stored arrival, income
	    pops only within Pier.PopRange of the bucket, every Pier.PopEvery s;
	  • slot events: "in", "sold", "swap" make their FX (emitters, the LightBar flash, the rising
	    «+$45») and clean them up; "mount" makes none; ≤ Fx.MaxEmitters emitters at once;
	  • other players' TankPrompt hidden on this client (the server's stays enabled), the own one
	    untouched; the market word over the hub market, coins at a stall on "Sold";
	  • budgets and leaks: no RenderStepped / Heartbeat / Stepped connections from the tank
	    scripts, nothing left of a released base, nothing at all after the base is left behind.

	Run: lune run tools/run_tests.luau stage3_world
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local PLACE = "Place1.rbxl"
local STUBBED = { "FishingService", "DataService", "EconomyService", "MarketService", "TankService" }

-- Pure config modules straight from src/ (the same values the game uses).
local function loadConfig(name: string): any
	local path = `src/ReplicatedStorage/Shared/Config/{name}.luau`
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum },
		injectGlobals = true,
	})
	return chunk()
end

local TankConfig = loadConfig("TankConfig")
local EconomyConfig = loadConfig("EconomyConfig")
local DISPLAY = TankConfig.Display
local PIER = TankConfig.Pier
local FX = DISPLAY.Fx

--------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------

local function boot(t: any): any
	local sim = t.sim({ place = PLACE })
	for _, name in STUBBED do
		sim:Find(`ServerScriptService.Services.{name}`).Source = "return {}"
	end
	-- every player gets the lowest free base (base 1 first): predictable geometry
	local baseConfig = sim:Find("ReplicatedStorage.Shared.Config.BaseConfig")
	baseConfig.Source = string.gsub(baseConfig.Source, "RandomAssignment%s*=%s*true", "RandomAssignment = false")
	sim:StartServer()
	sim:Advance(0.5)
	-- what TankService.Init does: a disabled "TankPrompt" at every tank
	for _, base in sim.workspace.Bases:GetChildren() do
		sim:Create("ProximityPrompt", {
			Name = "TankPrompt",
			ActionText = TankConfig.Prompt.Action,
			ObjectText = TankConfig.Prompt.Object,
			Enabled = false,
		}, base.Tank.Glass.PromptAttachment)
	end
	return sim
end

local function addPlayer(sim: any, id: number): any
	local player = sim:AddPlayer({ UserId = id, Name = `Keeper{id}`, device = "phone" })
	sim:Advance(1)
	return player
end

local function baseOf(sim: any, player: any): any
	local base = sim.workspace.Bases:FindFirstChild(`Base_{player:GetAttribute("BaseIndex")}`)
	assert(base, `{player.Name}: own base`)
	return base
end

local function controller(sim: any, player: any): any
	local module = sim:Find("Controllers.TankWorldController", player:FindFirstChildOfClass("PlayerScripts"))
	assert(module, "TankWorldController in PlayerScripts")
	return sim:Require(module, player)
end

local function folderOf(sim: any, player: any): any
	local folder = controller(sim, player).Stats().folder
	assert(folder, "the TankWorld folder")
	return folder
end

local function slotModel(base: any, index: number): any
	return base.Tank.Slots[`Slot_{index}`]
end

-- The camera far away (the controller measures from the camera AND the own character).
local FAR = CFrame.new(0, 3000, 0)
local function setCamera(sim: any, cf: any)
	sim.workspace.CurrentCamera.CFrame = cf
end

local function glassOf(base: any): any
	return base.Tank.Glass.Position
end

-- Stands the character `d` studs from the base's tank glass (on the gate side), camera far.
local function standFrom(sim: any, player: any, base: any, d: number)
	local glass = base.Tank.Glass
	local back = -glass.CFrame.LookVector -- towards the gate (the tank's front is its −Z)
	setCamera(sim, FAR)
	sim:Teleport(player, glass.Position + Vector3.new(back.X, 0, back.Z).Unit * d)
end

--------------------------------------------------------------------------------
-- The fake server: TankService's replicated state (design §4.6)
--------------------------------------------------------------------------------

local Fake = {}
Fake.__index = Fake

local FISH_FIELDS = { "FishUid", "FishId", "Rarity", "Mutation", "Kg", "Value", "Income", "GrowFrom" }

function Fake.new(sim: any, player: any, base: any?): any
	local self = setmetatable({
		sim = sim,
		player = player,
		base = base or baseOf(sim, player),
		serial = 0,
		rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules")),
		tank = sim:Require(sim:Find("ReplicatedStorage.Shared.TankRules")),
		fish = {},
		uid = 0,
	}, Fake)
	return self
end

function Fake:event(slot: any, kind: string, detail: string?)
	self.serial += 1
	slot:SetAttribute("Event", `{self.serial}|{kind}|{detail or ""}`)
end

-- The fish record of an id (Kg = the middle of its range unless given).
function Fake:record(id: string, opts: any?): any
	local o = opts or {}
	local def = self.rules.GetFish(id)
	local kg = o.kg or (def.MinKg + def.MaxKg) / 2
	local value, income = self.rules.Price(id, kg, o.mutation)
	self.uid += 1
	return {
		Uid = o.uid or `f{self.uid}`,
		Id = id,
		Rarity = def.Rarity,
		Mutation = o.mutation,
		Kg = kg,
		Value = value,
		Income10 = self.tank.Income10(income),
		Age = o.age or 0,
	}
end

function Fake:writeFish(slot: any, fish: any)
	slot:SetAttribute("FishUid", fish.Uid)
	slot:SetAttribute("FishId", fish.Id)
	slot:SetAttribute("Rarity", fish.Rarity)
	slot:SetAttribute("Mutation", fish.Mutation)
	slot:SetAttribute("Kg", fish.Kg)
	slot:SetAttribute("Value", fish.Value)
	slot:SetAttribute("Income", fish.Income10 / 10)
	slot:SetAttribute("GrowFrom", self.tank.AttrTime(self.sim.workspace:GetServerTimeNow() - fish.Age))
end

function Fake:clearFish(slot: any)
	for _, name in FISH_FIELDS do
		slot:SetAttribute(name, nil)
	end
end

-- Count / Slots / Income on the tank model and TankCount / TankSlots / Income on the player.
function Fake:totals(slots: number?)
	local count, income10 = 0, 0
	for _, fish in self.fish do
		count += 1
		income10 += fish.Income10
	end
	local open = slots or self.slots or TankConfig.StartSlots
	self.slots = open
	self.base.Tank:SetAttribute("Count", count)
	self.base.Tank:SetAttribute("Slots", open)
	self.base.Tank:SetAttribute("Income", income10 / 10)
	self.player:SetAttribute("TankCount", count)
	self.player:SetAttribute("TankSlots", open)
	self.player:SetAttribute("Income", income10 / 10)
end

-- Mount: every display (fish 1..#list in slots by index, the rest empty up to `slots`, then
-- locked) with "<n>|mount|", then the totals and the prompt enabled.
function Fake:mount(list: { [number]: any }, slots: number?)
	local open = slots or TankConfig.StartSlots
	self.fish = {}
	for index = 1, TankConfig.MaxSlots do
		local slot = slotModel(self.base, index)
		local fish = list[index]
		local state = if index > open then "locked" elseif fish then "fish" else "empty"
		if state == "fish" then
			self:writeFish(slot, fish)
			self.fish[index] = fish
		else
			self:clearFish(slot)
		end
		slot:SetAttribute("State", state)
		self:event(slot, "mount")
	end
	self:totals(open)
	self.base.Tank.Glass.PromptAttachment.TankPrompt.Enabled = true
	self.sim:Advance(0.05)
end

-- A catch stored in a display: "in".
function Fake:store(index: number, fish: any)
	local slot = slotModel(self.base, index)
	self:writeFish(slot, fish)
	slot:SetAttribute("State", "fish")
	self.fish[index] = fish
	self:event(slot, "in", fish.Id)
	self:totals()
	self.sim:Advance(0.05)
end

-- A sale: "sold" with the price.
function Fake:sell(index: number, price: number)
	local slot = slotModel(self.base, index)
	self:clearFish(slot)
	slot:SetAttribute("State", "empty")
	self.fish[index] = nil
	self:event(slot, "sold", string.format("%d", price))
	self:totals()
	self.sim:Advance(0.05)
end

-- A replacement: the new fish in place of the old (State stays "fish"), "swap" with the price.
function Fake:swap(index: number, fish: any, price: number)
	local slot = slotModel(self.base, index)
	self:writeFish(slot, fish)
	slot:SetAttribute("State", "fish")
	self.fish[index] = fish
	self:event(slot, "swap", string.format("%d", price))
	self:totals()
	self.sim:Advance(0.05)
end

-- The base released (BaseReleased): every display empty, fish fields nil, tank attributes off.
function Fake:unmount()
	for index = 1, TankConfig.MaxSlots do
		local slot = slotModel(self.base, index)
		self:clearFish(slot)
		slot:SetAttribute("State", "empty")
	end
	self.fish = {}
	for _, name in { "Count", "Slots", "Income" } do
		self.base.Tank:SetAttribute(name, nil)
	end
	self.base.Tank.Glass.PromptAttachment.TankPrompt.Enabled = false
	self.sim:Advance(0.05)
end

local SIX = { "Crucian", "Perch", "Puffer", "Swordfish", "SharkPup", "DragonFish" }

local function sixFish(fake: any, mutations: { [number]: string }?): { any }
	local list = {}
	for i, id in SIX do
		list[i] = fake:record(id, { mutation = mutations and mutations[i] })
	end
	return list
end

-- Steps until every queued quiet build is done (≤ BuildPerCheck per check).
local function settle(sim: any, seconds: number?)
	sim:Advance(seconds or 2.2, 1 / 30)
end

--------------------------------------------------------------------------------
-- Checks
--------------------------------------------------------------------------------

local function partsOf(model: any): { any }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

-- AABB of a model's parts (every part's corners) in the axes of `frame` (default: the world).
local function aabb(model: any, frame: any?): (any, any)
	local lo = Vector3.new(math.huge, math.huge, math.huge)
	local hi = Vector3.new(-math.huge, -math.huge, -math.huge)
	local inv = if frame then frame:Inverse() else CFrame.new()
	for _, part in partsOf(model) do
		local half = part.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = inv * (part.CFrame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
					lo = Vector3.new(math.min(lo.X, p.X), math.min(lo.Y, p.Y), math.min(lo.Z, p.Z))
					hi = Vector3.new(math.max(hi.X, p.X), math.max(hi.Y, p.Y), math.max(hi.Z, p.Z))
				end
			end
		end
	end
	return lo, hi
end

local function countClass(root: any, class: string, name: string?): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA(class) and (name == nil or d.Name == name) then
			n += 1
		end
	end
	return n
end

local function frameConnections(sim: any, player: any): number
	local ctx = sim:ContextName(player)
	return sim:CountConnections(function(conn: any): boolean
		local signal = conn.signal:describe()
		return conn.ctx.name == ctx
			and (
				string.find(signal, "RenderStepped", 1, true) ~= nil
				or string.find(signal, "Heartbeat", 1, true) ~= nil
				or string.find(signal, "Stepped", 1, true) ~= nil
				or string.find(signal, "PreRender", 1, true) ~= nil
				or string.find(signal, "PreSimulation", 1, true) ~= nil
			)
	end)
end

local function tankConnections(sim: any, player: any): number
	local ctx = sim:ContextName(player)
	return sim:CountConnections(function(conn: any): boolean
		local script = conn.script
		return conn.ctx.name == ctx
			and script ~= nil
			and (script.Name == "TankWorldController" or script.Name == "TankDisplay")
	end)
end

local tests = {}

tests["display fish: one per occupied display, centred on FishPoint, inside the cube, right species and mutation; gone on empty"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local fake = Fake.new(sim, p)
	local base = fake.base
	local list = sixFish(fake, { [3] = "Gold", [5] = "Neon", [6] = "Rainbow" })
	fake:mount(list)
	settle(sim)
	local world = controller(sim, p)
	t.ok(world.IsBuilt(base), "the own base is built (the character stands in the yard)")
	-- at rest (beyond LifeRange, within Range): RbxSim does not carry welded parts with a
	-- tweened Body, so the layout is measured on resting fish
	standFrom(sim, p, base, (DISPLAY.LifeRange + DISPLAY.Range) / 2 + 20)
	sim:Advance(1)
	t.eq(world.Stats().life, 0, "no life tweens out here")
	t.eq(world.Stats().locks, TankConfig.MaxSlots - 6, "a dim «🔒 Закрыто» over every locked display")
	for index = 1, TankConfig.MaxSlots do
		local fish = world.GetFish(base, index)
		local slot = slotModel(base, index)
		if index > 6 then
			t.eq(fish, nil, `Slot_{index}: no fish ({slot:GetAttribute("State")})`)
			continue
		end
		t.ok(fish, `Slot_{index}: a display fish`)
		local spec = list[index]
		t.eq(fish:GetAttribute("FishId"), spec.Id, `Slot_{index}: species`)
		t.eq(fish:GetAttribute("Mutation"), spec.Mutation, `Slot_{index}: mutation`)
		t.eq(fish:GetAttribute("Rarity"), spec.Rarity, `Slot_{index}: rarity`)
		t.eq(fish:GetAttribute("Value"), spec.Value, `Slot_{index}: value`)
		t.eq(fish:GetAttribute("FishUid"), spec.Uid, `Slot_{index}: uid`)
		t.eq(fish.Parent, folderOf(sim, p), `Slot_{index}: in Workspace.TankWorld`)
		local parts = partsOf(fish)
		t.ok(#parts > 0 and #parts <= 20, `Slot_{index}: ≤ 20 parts ({#parts})`)
		for _, part in parts do
			t.ok(
				not part.CanCollide and not part.CanQuery and not part.CanTouch and not part.CastShadow,
				`Slot_{index}.{part.Name}: quiet`
			)
		end
		-- the bounding box (Model:GetBoundingBox, in the fish's own axes) centred on FishPoint;
		-- every part inside the glass cube (corners in the display's axes)
		local display = slot.Display
		local point = display.FishPoint.WorldPosition
		local box = fish:GetBoundingBox()
		t.ok(
			(box.Position - point).Magnitude <= 0.1,
			`Slot_{index}: centred on FishPoint ({(box.Position - point).Magnitude})`
		)
		local lo, hi = aabb(fish, display.CFrame)
		local half = display.Size / 2
		t.ok(
			lo.X >= -half.X
				and lo.Y >= -half.Y
				and lo.Z >= -half.Z
				and hi.X <= half.X
				and hi.Y <= half.Y
				and hi.Z <= half.Z,
			`Slot_{index}: inside the 6.2 cube ({lo} .. {hi})`
		)
		local size = hi - lo
		local longest = math.max(size.X, size.Y, size.Z)
		t.ok(longest >= 3, `Slot_{index}: not tiny ({longest})`)
		if spec.Mutation == "Rainbow" then
			t.ok(fish:HasTag("RainbowFish"), "the rainbow fish keeps its RainbowFish tag")
		end
	end
	-- the head alternates (SlotIndex % 4 < 2: +X of the display)
	local look1 = world.GetFish(base, 1).PrimaryPart.CFrame.XVector
	local look3 = world.GetFish(base, 3).PrimaryPart.CFrame.XVector
	local x1 = slotModel(base, 1).Display.CFrame.XVector
	local x3 = slotModel(base, 3).Display.CFrame.XVector
	t.ok(look1:Dot(x1) > 0.9, "Slot_1: head along +X of the display, yawed 18°")
	t.ok(look3:Dot(x3) < -0.9, "Slot_3: head along −X of the display")
	t.near(math.deg(math.acos(math.clamp(look1:Dot(x1), -1, 1))), DISPLAY.Yaw, 0.5, "Slot_1: the yaw")

	-- empty → gone (a quiet change: no Event kind in range of FX would still remove it)
	fake:sell(2, 30)
	sim:Advance(FX.Shrink + 0.2)
	t.eq(world.GetFish(base, 2), nil, "Slot_2 sold → no fish")
	local names = {}
	for _, child in folderOf(sim, p):GetChildren() do
		names[child.Name] = true
	end
	t.ok(not names["DisplayFish_1_2"], "the sold fish's model is destroyed")
	t.eq(world.Stats().fish, 5, "five fish left")
	sim:AssertNoErrors({ warnings = true })
end

tests["swap: the Event alone (State stays fish, FishUid changes) replaces the model; mount is quiet"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 2)
	local fake = Fake.new(sim, p)
	local base = fake.base
	fake:mount({ [1] = fake:record("Crucian") })
	settle(sim)
	local world = controller(sim, p)
	local before = world.GetFish(base, 1)
	t.ok(before, "a Crucian on Slot_1")
	local stats0 = world.Stats()
	t.eq(stats0.emitters, 0, "mount: no particles")
	t.eq(countClass(folderOf(sim, p), "PointLight"), 0, "mount: no flash")
	t.eq(countClass(folderOf(sim, p), "BillboardGui", "FxTankPop"), 0, "mount: no rising price")

	local swordfish = fake:record("Swordfish")
	fake:swap(1, swordfish, 24)
	t.eq(slotModel(base, 1):GetAttribute("State"), "fish", "State stayed fish")
	sim:Advance(FX.Shrink + FX.Grow + 0.2)
	local after = world.GetFish(base, 1)
	t.ok(after and after ~= before, "a new model")
	t.eq(after:GetAttribute("FishId"), "Swordfish", "the new species")
	t.eq(after:GetAttribute("FishUid"), swordfish.Uid, "the new uid")
	t.eq(before.Parent, nil, "the old model is gone")

	-- a remount (another server writes "mount" for every display): quiet, the fish stays
	fake:mount({ [1] = swordfish })
	sim:Advance(0.6)
	t.eq(world.GetFish(base, 1), after, "mount of the same fish: the same model")
	sim:Advance(2)
	sim:AssertNoErrors({ warnings = true })
end

tests["range: built within Display.Range, kept until DropRange, ≤ BuildPerCheck quiet builds per check"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 3)
	local fake = Fake.new(sim, p)
	local base = fake.base
	local list = {}
	for i = 1, 12 do
		list[i] = fake:record(SIX[(i - 1) % 6 + 1])
	end
	-- far away first (beyond DropRange: the yard's build is torn down), then just outside Range
	local world = controller(sim, p)
	standFrom(sim, p, base, DISPLAY.DropRange + 20)
	sim:Advance(1)
	t.ok(not world.IsBuilt(base), "beyond DropRange: not built")
	fake:mount(list, 12)
	standFrom(sim, p, base, DISPLAY.Range + 10)
	sim:Advance(1)
	t.ok(not world.IsBuilt(base), "beyond Display.Range: not built")
	t.eq(world.Stats().fish, 0, "no fish")
	-- step inside: the base builds, the 12 fish come ≤ BuildPerCheck per check
	standFrom(sim, p, base, DISPLAY.Range - 20)
	local maxPerCheck, checks = 0, 0
	local lastFish = 0
	for _ = 1, 12 do
		sim:Advance(DISPLAY.CheckEvery, 1 / 30)
		local stats = world.Stats()
		checks += 1
		maxPerCheck = math.max(maxPerCheck, stats.fish - lastFish)
		lastFish = stats.fish
		if stats.fish == 12 then
			break
		end
	end
	t.ok(world.IsBuilt(base), "within Display.Range: built")
	t.eq(world.Stats().fish, 12, "all 12 fish built")
	t.ok(maxPerCheck <= DISPLAY.BuildPerCheck, `≤ {DISPLAY.BuildPerCheck} per check (max {maxPerCheck})`)
	t.ok(checks >= 4, `12 fish took ≥ 4 checks ({checks})`)
	-- hysteresis: between Range and DropRange it stays; beyond DropRange it goes
	standFrom(sim, p, base, (DISPLAY.Range + DISPLAY.DropRange) / 2)
	sim:Advance(1)
	t.ok(world.IsBuilt(base), "between Range and DropRange: kept")
	t.eq(world.Stats().fish, 12, "fish kept")
	standFrom(sim, p, base, DISPLAY.DropRange + 15)
	sim:Advance(1)
	t.ok(not world.IsBuilt(base), "beyond DropRange: torn down")
	t.eq(world.Stats().fish, 0, "no fish")
	t.eq(world.Stats().tags, 0, "no tags")
	t.eq(#folderOf(sim, p):GetChildren(), 1, "only the Anchor part is left in the folder")
	local left = {}
	for _, child in folderOf(sim, p).Anchor:GetChildren() do
		table.insert(left, child.Name)
	end
	table.sort(left)
	t.eq(left, { "FxMarketWord", "FxPierTank" }, "… holding only the market word and the pier word (not range-bound)")
	sim:AssertNoErrors({ warnings = true })
end

tests["life: one looped Body tween within LifeRange (the fish bobs), none beyond (it rests)"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 4)
	local fake = Fake.new(sim, p)
	local base = fake.base
	fake:mount(sixFish(fake))
	settle(sim)
	local world = controller(sim, p)
	-- the character at the gate end of the tank, camera far: some fish within LifeRange
	standFrom(sim, p, base, 30)
	sim:Advance(1.2)
	local root = p.Character.HumanoidRootPart.Position
	local alive = 0
	for index = 1, 6 do
		local d = (slotModel(base, index).Display.FishPoint.WorldPosition - root).Magnitude
		if math.abs(d - DISPLAY.LifeRange) < 2 then
			continue -- (too close to the edge to judge in one check)
		end
		local inRange = d <= DISPLAY.LifeRange
		t.eq(world.IsAlive(base, index), inRange, `Slot_{index} at {math.floor(d)} studs: life {inRange}`)
		if inRange then
			alive += 1
		end
	end
	t.ok(alive >= 2, `some fish live ({alive})`)
	-- a living fish's Body moves (bob + yaw), within ±Bob of its rest
	local live = nil
	for index = 1, 6 do
		if world.IsAlive(base, index) then
			live = index
			break
		end
	end
	local body = world.GetFish(base, live).PrimaryPart
	local lo, hi = math.huge, -math.huge
	for _ = 1, 16 do
		sim:Advance(0.25)
		lo = math.min(lo, body.CFrame.Position.Y)
		hi = math.max(hi, body.CFrame.Position.Y)
	end
	t.ok(hi - lo > DISPLAY.Life.Bob * 0.5, `the living Body bobs ({hi - lo})`)
	t.ok(hi - lo <= DISPLAY.Life.Bob * 2 + 0.05, `… gently (≤ ±Bob: {hi - lo})`)
	-- away beyond LifeRange (still within Range): the tweens stop and the fish rests
	standFrom(sim, p, base, DISPLAY.LifeRange + 50)
	sim:Advance(1)
	t.eq(world.Stats().life, 0, "beyond LifeRange: no life tweens")
	local rest = body.CFrame
	sim:Advance(1.5)
	t.near(body.CFrame.Position, rest.Position, 1e-4, "the resting fish does not move")
	t.ok(world.IsBuilt(base), "still built (within Range)")
	sim:AssertNoErrors({ warnings = true })
end

tests["tags: «+$X/с» and the value ticking to «МАКС» in front of the glass; ticks only within TagRange"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 5)
	local fake = Fake.new(sim, p)
	local base = fake.base
	local young = fake:record("Perch", { age = 0 })
	local old = fake:record("Swordfish", { age = TankConfig.Growth.Time + 5 })
	local far = fake:record("Crucian", { age = 0 })
	fake:mount({ [1] = young, [2] = old, [11] = far }, 12)
	settle(sim)
	local world = controller(sim, p)
	local tank = fake.tank
	-- stand right in front of Slot_1 (the west aisle), Slot_11's tag beyond TagRange
	local d1 = slotModel(base, 1).Display
	sim:Teleport(p, (d1.CFrame * CFrame.new(0, -4, -9)).Position)
	setCamera(sim, FAR)
	sim:Advance(1.1)
	local tag1 = world.GetTag(base, 1)
	t.ok(tag1, "Slot_1 has a tag")
	t.eq(tag1.Name, "FxTankTag")
	t.eq(tag1.MaxDistance, DISPLAY.TagRange, "MaxDistance = TagRange")
	t.eq(tag1.LightInfluence, 0)
	t.eq(tag1.AlwaysOnTop, false)
	local plate = tag1.Plate
	t.eq(plate.Rate.Text, tank.FormatRate(young.Income10), "line 1: the income")
	local function valueText(fish: any, age: number): string
		local price = tank.FormatMoney(tank.CurrentValue(fish.Value, age))
		local template = if tank.IsMaxed(age) then TankConfig.Texts.TagMax else TankConfig.Texts.TagValue
		return (string.gsub(string.gsub(template, "{price}", price), "{max}", TankConfig.Texts.Max))
	end
	t.eq(plate.Value.Text, valueText(young, 0), "line 2: the value now «$X ▲»")
	t.match(plate.Value.Text, "▲$")
	t.match(world.GetTag(base, 2).Plate.Value.Text, TankConfig.Texts.Max .. "$")
	-- where: over the glass, in front of its face, under the arcade ceiling
	local holder = tag1.Parent
	local rel = d1.CFrame:PointToObjectSpace(holder.WorldPosition)
	t.near(rel, Vector3.new(0, DISPLAY.Tag.Lift, -DISPLAY.Tag.Forward), 0.01, "at FishPoint + (0, Lift, −Forward)")
	t.ok(rel.Z < -d1.Size.Z / 2, "in front of the glass's face (the aisle side)")
	local top = holder.WorldPosition.Y + DISPLAY.Tag.Height / 2
	t.ok(top < base.Root.Position.Y + 13.15, `under the arcade ceiling ({top})`)
	-- the value ticks (1 s chain), the far tag does not
	local farBefore = world.GetTag(base, 11).Plate.Value.Text
	sim:Advance(60)
	local age = sim.workspace:GetServerTimeNow() - slotModel(base, 1):GetAttribute("GrowFrom")
	t.eq(plate.Value.Text, valueText(young, age), "the near value ticks")
	t.neq(plate.Value.Text, valueText(young, 0), "… and grew")
	t.eq(world.GetTag(base, 11).Plate.Value.Text, farBefore, "beyond TagRange the tag is not refreshed")
	sim:AssertNoErrors({ warnings = true })
end

tests["tank sign: «+$42/с» / «🐠 4/6» over the big tank of an owned, mounted base only"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 6)
	local world = controller(sim, p)
	local fake = Fake.new(sim, p)
	local base = fake.base
	sim:Advance(0.6)
	local sign = world.GetSign(base)
	t.ok(sign == nil or not sign.Enabled, "before the mount (no Count): no sign")
	local list = sixFish(fake)
	fake:mount({ list[1], list[2], list[3], list[4] })
	sim:Advance(0.1)
	sign = world.GetSign(base)
	t.ok(sign and sign.Enabled, "mounted: the sign shows")
	t.eq(sign.MaxDistance, DISPLAY.SignRange)
	local income10 = list[1].Income10 + list[2].Income10 + list[3].Income10 + list[4].Income10
	t.eq(sign.Plate.Rate.Text, fake.tank.FormatRate(income10), "big green income")
	t.eq(sign.Plate.Count.Text, "🐠 4/6", "the count")
	local glass = base.Tank.Glass
	local rel = glass.CFrame:PointToObjectSpace(sign.Parent.WorldPosition)
	t.ok(rel.Y > glass.Size.Y / 2, "above the glass")
	t.ok(rel.Z < 0, "over its front half (the «АКВАРИУМ» plaque side)")
	-- a free base has none
	local other = sim.workspace.Bases:FindFirstChild("Base_2")
	t.eq(other:GetAttribute("OwnerUserId"), 0, "Base_2 is free")
	sim:Teleport(p, other.Tank.Glass.Position + Vector3.new(0, 4, -30))
	sim:Advance(1)
	t.ok(world.IsBuilt(other), "the free base is built (in range)")
	local free = world.GetSign(other)
	t.ok(free == nil or not free.Enabled, "a free base: no sign")
	-- unmount: hidden
	fake:unmount()
	sim:Advance(0.1)
	t.ok(not sign.Enabled or sign.Parent == nil, "unmounted: hidden")
	sim:AssertNoErrors({ warnings = true })
end

tests["pier word: own base only, hidden on Bite / Reeling / CounterHold / HeldFish; splash on a stored arrival"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 7)
	local world = controller(sim, p)
	local fake = Fake.new(sim, p)
	local base = fake.base
	local hud = p.PlayerGui.HUD
	local word = world.GetPierWord()
	t.ok(word, "the pier word exists for the own base")
	t.eq(word.Name, "FxPierTank")
	t.eq(word.Enabled, false, "no TankSlots yet (data not loaded): hidden")
	t.eq(word.MaxDistance, PIER.Range)
	-- over the bucket of the OWN base
	local bucket = base.Platform.Bucket
	local at = word.Parent.WorldPosition
	local flat = Vector3.new(at.X - bucket.Position.X, 0, at.Z - bucket.Position.Z)
	t.near(flat.Magnitude, PIER.Out, 0.01, "over the bucket (Pier.Out beyond its centre)")
	local spot = base.FishingSpot.Position
	local fromSpot = Vector3.new(at.X - spot.X, 0, at.Z - spot.Z).Magnitude
	t.ok(
		fromSpot > Vector3.new(bucket.Position.X - spot.X, 0, bucket.Position.Z - spot.Z).Magnitude,
		"… on its far side from the spot"
	)
	t.ok(at.Y > bucket.Position.Y + 1, "above it")
	fake:mount({ fake:record("Perch"), fake:record("Puffer") })
	sim:Advance(0.1)
	t.eq(word.Enabled, true, "loaded: shown")
	t.eq(word.Plate.Count.Text, "🐠 2/6")
	t.eq(word.Plate.Rate.Text, fake.tank.FormatRate(fake.fish[1].Income10 + fake.fish[2].Income10))
	local function busy(label: string, set: () -> (), clear: () -> ())
		set()
		sim:Advance(0.05)
		t.eq(word.Enabled, false, `{label}: hidden`)
		clear()
		sim:Advance(0.05)
		t.eq(word.Enabled, true, `{label} over: shown again`)
	end
	busy("Bite", function()
		p:SetAttribute("FishingState", "Bite")
	end, function()
		p:SetAttribute("FishingState", "Waiting")
	end)
	busy("Reeling", function()
		p:SetAttribute("FishingState", "Reeling")
	end, function()
		p:SetAttribute("FishingState", "Idle")
	end)
	busy("CounterHold", function()
		hud:SetAttribute("CounterHold", 0)
	end, function()
		hud:SetAttribute("CounterHold", nil)
	end)
	busy("HeldFish", function()
		sim:Create("Model", { Name = "HeldFish" }, p.Character)
	end, function()
		p.Character.HeldFish:Destroy()
	end)
	-- a stored arrival: held by CounterHold → no splash; released → a splash at the bucket
	hud:SetAttribute("CounterHold", 0)
	sim:Advance(0.05)
	local remote = sim:Find("ReplicatedStorage.Remotes.FishingState")
	local fish = fake:record("Crucian")
	remote:FireClient(p, "Caught", {
		Fish = { Id = fish.Id, Rarity = fish.Rarity, Kg = fish.Kg, Value = fish.Value, Income = fish.Income10 / 10 },
		Total = 0,
		Tank = { Result = "stored", Slot = 3, Uid = fish.Uid, Count = 3, Slots = 6 },
	})
	sim:Advance(1.5)
	t.eq(world.Stats().emitters, 0, "held: no splash yet")
	fake:store(3, fish)
	standFrom(sim, p, base, DISPLAY.DropRange + 30) -- (the court far: no slot FX in the count)
	sim:Teleport(p, base.FishingSpot.Position + Vector3.new(0, 3, 0))
	sim:Advance(0.1)
	hud:SetAttribute("CounterHold", nil)
	sim:Advance(0.05)
	local splash = nil
	for _, d in folderOf(sim, p):GetDescendants() do
		if d:IsA("ParticleEmitter") and d.Name == "Fxsplash" then
			local pos = d.Parent.WorldPosition
			if
				(Vector3.new(pos.X, 0, pos.Z) - Vector3.new(bucket.Position.X, 0, bucket.Position.Z)).Magnitude < 0.5
			then
				splash = d
			end
		end
	end
	t.ok(splash, "released: a splash at the bucket rim")
	t.eq(word.Plate.Count.Text, "🐠 3/6", "the word counts the new fish")
	sim:Advance(FX.EmitterLife + 0.2)
	t.eq(world.Stats().emitters, 0, "the splash emitter is gone")
	-- a sold catch: no splash; without CounterHold a stored one splashes after a moment
	remote:FireClient(p, "Caught", {
		Fish = { Id = "Crucian", Rarity = "Common", Kg = 0.5, Value = 9 },
		Total = 0,
		Tank = { Result = "sold", Count = 3, Slots = 6, Price = 9 },
	})
	sim:Advance(1.5)
	t.eq(world.Stats().emitters, 0, "sold: no splash")
	remote:FireClient(p, "Caught", {
		Fish = { Id = "Crucian", Rarity = "Common", Kg = 0.5, Value = 9 },
		Total = 0,
		Tank = { Result = "stored", Slot = 4, Uid = "f99", Count = 4, Slots = 6 },
	})
	sim:Advance(1.2)
	t.ok(world.Stats().emitters >= 1, "stored without CounterHold: the splash comes anyway")
	sim:Advance(2)
	t.eq(countClass(folderOf(sim, p), "BillboardGui", "FxPierTank"), 1, "one pier word (the own bucket only)")
	sim:AssertNoErrors({ warnings = true })
end

tests["pier pops: «+$X» every PopEvery s only within PopRange of the bucket and with income"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 8)
	local world = controller(sim, p)
	local fake = Fake.new(sim, p)
	local base = fake.base
	fake:mount({ fake:record("Swordfish") })
	sim:Advance(0.2)
	local bucket = base.Platform.Bucket.Position
	local function pops(): { any }
		local list = {}
		for _, d in folderOf(sim, p):GetDescendants() do
			if d:IsA("BillboardGui") and d.Name == "FxTankPop" then
				table.insert(list, d)
			end
		end
		return list
	end
	-- on the fishing spot, by the bucket
	sim:Teleport(p, base.FishingSpot.Position + Vector3.new(0, 3, 0))
	setCamera(sim, FAR)
	local seen, texts, was = 0, {}, false
	local span = PIER.PopEvery * 2 + 1
	for _ = 1, math.floor(span / 0.1) do
		sim:Advance(0.1)
		local now = pops()
		if #now > 0 and not was then
			seen += 1
			table.insert(texts, now[1].Plate.Amount.Text)
		end
		was = #now > 0
	end
	t.ok(seen >= 2 and seen <= 3, `≈ one pop every {PIER.PopEvery} s by the bucket ({seen} in {span} s)`)
	local amount = string.sub(fake.tank.FormatRate(fake.fish[1].Income10), 2, -1 - #EconomyConfig.Format.Rate)
	t.eq(texts[1], "+" .. amount, "the pop is the income per second")
	-- away from the bucket: none
	sim:Teleport(p, bucket + Vector3.new(0, 3, PIER.PopRange + 15))
	sim:Advance(PIER.PopTime + 0.2)
	local quiet = true
	for _ = 1, math.floor(PIER.PopEvery * 2 / 0.25) do
		sim:Advance(0.25)
		if #pops() > 0 then
			quiet = false
		end
	end
	t.ok(quiet, "beyond PopRange: no pops")
	-- no income: none
	sim:Teleport(p, base.FishingSpot.Position + Vector3.new(0, 3, 0))
	p:SetAttribute("Income", 0)
	sim:Advance(0.1)
	for _ = 1, math.floor(PIER.PopEvery * 2 / 0.25) do
		sim:Advance(0.25)
		if #pops() > 0 then
			quiet = false
		end
	end
	t.ok(quiet, "no income: no pops")
	t.ok(world.GetPierWord().Enabled, "the word itself is still there")
	sim:AssertNoErrors({ warnings = true })
end

tests["slot events: in / sold / swap make their FX and clean them up; mount none; far bases quiet; ≤ MaxEmitters"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 9)
	local world = controller(sim, p)
	local fake = Fake.new(sim, p)
	local base = fake.base
	fake:mount({})
	settle(sim, 1)
	local folder = folderOf(sim, p)
	local function fx(): (number, number, number)
		return countClass(folder, "ParticleEmitter"),
			countClass(folder, "PointLight", "FxFlash"),
			countClass(folder, "BillboardGui", "FxTankPop")
	end
	local e0, l0, p0 = fx()
	t.eq(e0 + l0 + p0, 0, "mount: no FX")
	-- "in": splash + sparkles over the display's top, a flash at the LightBar, the fish grows
	fake:store(1, fake:record("Puffer"))
	local e1, l1 = fx()
	t.ok(e1 >= 1 and e1 <= FX.MaxEmitters, `in: particles (≤ {FX.MaxEmitters}: {e1})`)
	t.eq(l1, 1, "in: the LightBar flash")
	local display = slotModel(base, 1).Display
	for _, d in folder:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local rel = display.CFrame:PointToObjectSpace(d.Parent.WorldPosition)
			t.ok(rel.Y > display.Size.Y / 2, "the burst is above the glass, not inside it")
		end
	end
	t.ok(world.GetFish(base, 1), "the fish is there at once")
	sim:Advance(math.max(FX.EmitterLife, FX.FlashTime, FX.Grow) + 0.3)
	local e2, l2 = fx()
	t.eq(e2 + l2, 0, "in: FX cleaned up")
	-- two events at once: never more than MaxEmitters emitters
	fake:store(2, fake:record("Crucian"))
	fake:store(4, fake:record("Perch"))
	t.ok(countClass(folder, "ParticleEmitter") <= FX.MaxEmitters, "≤ MaxEmitters at once")
	sim:Advance(1.5)
	-- "sold": the fish shrinks away, gold sparkles, «+$45» rises
	fake:sell(1, 45)
	local e3, _, p3 = fx()
	t.ok(e3 >= 1, "sold: sparkles")
	t.eq(p3, 1, "sold: the rising price")
	local pop = nil
	for _, d in folder:GetDescendants() do
		if d:IsA("BillboardGui") and d.Name == "FxTankPop" then
			pop = d
		end
	end
	t.eq(pop.Plate.Amount.Text, "+" .. fake.tank.FormatMoney(45), "«+$45»")
	sim:Advance(FX.Shrink + 0.1)
	t.eq(world.GetFish(base, 1), nil, "sold: the fish is gone after the shrink")
	sim:Advance(FX.RiseTime + 0.3)
	local e4, l4, p4 = fx()
	t.eq(e4 + l4 + p4, 0, "sold: FX cleaned up")
	-- "swap": price + the new fish
	local old = world.GetFish(base, 2)
	fake:swap(2, fake:record("SharkPup"), 12)
	local _, _, p5 = fx()
	t.eq(p5, 1, "swap: the rising price of the replaced fish")
	sim:Advance(FX.Shrink + FX.Grow + 0.2)
	t.eq(world.GetFish(base, 2):GetAttribute("FishId"), "SharkPup", "swap: the new fish")
	t.eq(old.Parent, nil, "swap: the old model is gone")
	sim:Advance(FX.RiseTime + 0.3)
	local e6, l6, p6 = fx()
	t.eq(e6 + l6 + p6, 0, "swap: FX cleaned up")
	-- a base beyond EventRange (still within Range): quiet, the fish still comes
	standFrom(sim, p, base, DISPLAY.EventRange + 25)
	sim:Advance(1)
	t.ok(world.IsBuilt(base), "still built")
	fake:store(5, fake:record("Swordfish"))
	local e7, l7, p7 = fx()
	t.eq(e7 + l7 + p7, 0, "beyond EventRange: no FX")
	sim:Advance(1.2)
	t.ok(world.GetFish(base, 5), "… but the fish is built (quietly)")
	sim:AssertNoErrors({ warnings = true })
end

tests["prompts: other players' TankPrompt hidden on this client only; the own one untouched"] = function(t)
	local sim = boot(t)
	local p1 = addPlayer(sim, 11)
	local p2 = addPlayer(sim, 12)
	local fake1 = Fake.new(sim, p1)
	local fake2 = Fake.new(sim, p2)
	fake1:mount({ fake1:record("Crucian") })
	fake2:mount({ fake2:record("Perch") })
	local own = fake1.base.Tank.Glass.PromptAttachment.TankPrompt
	local foreign = fake2.base.Tank.Glass.PromptAttachment.TankPrompt
	local function enabledFor(player: any, prompt: any): boolean
		return sim:Run(function()
			return prompt.Enabled
		end, player)
	end
	-- p1 walks into p2's court (in range of it)
	sim:Teleport(p1, fake2.base.Tank.Glass.Position + Vector3.new(0, 4, -25))
	setCamera(sim, FAR)
	sim:Advance(1.2)
	local world = controller(sim, p1)
	t.ok(world.IsBuilt(fake2.base), "p2's base is built on p1's client")
	t.eq(enabledFor(p1, foreign), false, "p1 sees no prompt on p2's tank")
	t.eq(foreign.Enabled, true, "the server's stays enabled")
	t.eq(enabledFor(p2, foreign), true, "p2 still has its own")
	-- the server re-enables it (a remount): hidden again on p1's client
	fake2:mount({ fake2:record("Perch") })
	sim:Advance(0.6)
	t.eq(enabledFor(p1, foreign), false, "after a remount: still hidden for p1")
	-- the own prompt is never written by the client
	sim:Teleport(p1, fake1.base.Tank.Glass.Position + Vector3.new(0, 4, -25))
	sim:Advance(1.2)
	t.eq(enabledFor(p1, own), true, "p1's own prompt: enabled")
	local writes = 0
	for _, write in sim.ClientWrites do
		if write.property == "Enabled" and write.instance == own then
			writes += 1
		end
	end
	t.eq(writes, 0, "no client write to the own base's prompt")
	local foreignWrites = 0
	for _, write in sim.ClientWrites do
		if write.property == "Enabled" and write.instance == foreign then
			foreignWrites += 1
		end
	end
	t.ok(foreignWrites >= 1, "the foreign prompt was hidden by a client-local write")
	sim:AssertNoErrors({ warnings = true })
end

tests["market: «РЫНОК +50%!» over the hub market; coins at a stall's scales on a Sold there"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 13)
	local world = controller(sim, p)
	local folder = folderOf(sim, p)
	local word = nil
	for _, d in folder:GetDescendants() do
		if d:IsA("BillboardGui") and d.Name == "FxMarketWord" then
			word = d
		end
	end
	t.ok(word, "the market word exists")
	local bonus = EconomyConfig.MarketRatePct - 100
	t.eq(
		word.Plate.Word.Text,
		(string.gsub(TankConfig.Texts.MarketWord, "{bonus}", tostring(bonus))),
		"«РЫНОК +50%!»"
	)
	t.eq(word.MaxDistance, DISPLAY.MarketWordRange)
	local sign = sim.workspace.Map.Hub.FishMarket.Sign
	local at = word.Parent.WorldPosition
	t.ok(at.Y > sign.Position.Y + sign.Size.Y / 2, "above the «РЫБНЫЙ РЫНОК» sign")
	t.ok((Vector3.new(at.X, 0, at.Z) - Vector3.new(sign.Position.X, 0, sign.Position.Z)).Magnitude < 3, "… over it")
	-- a Sold at Kiosk1 with the player there: coins; elsewhere / at home: none
	local kiosk = sim:Find("Workspace.Map.Bridges.Bridge_1.Lookout.SellKiosk.Scales.SellPromptAttachment")
	sim:Teleport(p, kiosk.WorldPosition + Vector3.new(0, 2, -6))
	setCamera(sim, FAR)
	sim:Advance(0.6)
	local event = sim:Find("ReplicatedStorage.Remotes.TankEvent")
	event:FireClient(p, "Sold", { Items = {}, Amount = 67, RatePct = 150, Place = "Kiosk1" })
	sim:Advance(0.05)
	t.eq(countClass(folder, "ParticleEmitter", "Fxcoins"), 1, "coins at the kiosk")
	sim:Advance(FX.EmitterLife + 0.2)
	t.eq(countClass(folder, "ParticleEmitter"), 0, "gone")
	event:FireClient(p, "Sold", { Items = {}, Amount = 67, RatePct = 150, Place = "Market" })
	sim:Advance(0.05)
	t.eq(countClass(folder, "ParticleEmitter"), 0, "a far stall: no coins")
	event:FireClient(p, "Sold", { Items = {}, Amount = 12, RatePct = 100 })
	sim:Advance(0.05)
	t.eq(countClass(folder, "ParticleEmitter"), 0, "a home sale (no Place): no coins")
	sim:AssertNoErrors({ warnings = true })
end

tests["budget and leaks: no frame connections from the tank scripts; a released base leaves nothing; tear-down restores the connections"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 14)
	local world = controller(sim, p)
	local fake = Fake.new(sim, p)
	local base = fake.base
	-- leave the yard so the base is torn down, measure the baseline
	standFrom(sim, p, base, DISPLAY.DropRange + 30)
	sim:Advance(1)
	t.ok(not world.IsBuilt(base), "torn down")
	local frames0 = frameConnections(sim, p)
	local tank0 = tankConnections(sim, p)
	-- back in: six non-rainbow fish, living, tags, the sign
	fake:mount(sixFish(fake, { [3] = "Gold", [5] = "Neon" }))
	standFrom(sim, p, base, 30)
	settle(sim)
	t.eq(world.Stats().fish, 6, "six fish")
	t.ok(world.Stats().life > 0, "some living")
	sim:Advance(3)
	t.eq(frameConnections(sim, p), frames0, "no RenderStepped / Heartbeat / Stepped connection added")
	local total = 0
	for index = 1, 6 do
		total += #partsOf(world.GetFish(base, index))
	end
	t.ok(total <= 6 * 20, `display fish parts ≤ 20 each ({total} for 6)`)
	-- released: every display empty (no Event: BaseReleased) → nothing left
	fake:unmount()
	base:SetAttribute("OwnerUserId", 0)
	sim:Advance(0.6)
	t.eq(world.Stats().fish, 0, "released: no fish")
	t.eq(world.Stats().tags, 0, "released: no tags")
	t.eq(world.Stats().locks, 0, "released: no lock words (a free base is all empty)")
	local sign = world.GetSign(base)
	t.ok(sign == nil or not sign.Enabled, "released: no sign")
	local fishLeft = 0
	for _, child in folderOf(sim, p):GetChildren() do
		if child:IsA("Model") then
			fishLeft += 1
		end
	end
	t.eq(fishLeft, 0, "no fish model in the folder")
	-- torn down: the tank scripts' connections are back to the baseline
	standFrom(sim, p, base, DISPLAY.DropRange + 30)
	sim:Advance(1.5)
	t.eq(tankConnections(sim, p), tank0, "connections back to the baseline after the tear-down")
	sim:AssertNoErrors({ warnings = true })
end

return tests
