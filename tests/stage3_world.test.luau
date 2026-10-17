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
			lo.X >= -half.X and lo.Y >= -half.Y and lo.Z >= -half.Z and hi.X <= half.X and hi.Y <= half.Y and hi.Z <= half.Z,
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

return tests
