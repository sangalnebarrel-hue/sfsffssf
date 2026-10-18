--[[
	Stage 4 world (TankWorldController + TankDisplay, TheftWorldController, FisherAnimController) on
	the real clients, against the replicated state of design §4.11 written by the test (Wave 1 B:
	StealService / DefenceService / TankService are switched off, "return {}"): a fake server below
	writes the slot steal channel (StealBy, StealEnd, then StealPhase LAST; cleared the same way),
	the base attributes (AlarmState, Thief, HasDog, HasAlarm, LockLevel, ProtectUntil /
	ProtectKind), the dog's (Unlocked, DogState, DogPos — world, on the ground — and DogTarget, the
	pup shown and pivoted to DefenceConfig.Dog.Rest like DefenceService), the thief's Player
	attribute Slowed and his "StolenFish" (built by the real Lib/HeldRig on the server).

	What is checked (design §7.5):
	  • displays: the hold lifts the fish Steal.Lift, tilts it towards the aisle and struggles (a
	    looping tween), hides the aisle tag, shows «КРАДУТ!» with a ring timer and a red pulse at
	    the LightBar; a release drops it back with a splash; the carry flies it OUT OF THE FRONT
	    GLASS (never through the top, its top under FishPoint + ArcTop) onto the thief's head and
	    destroys it («УНОСЯТ!»); a return flies a new one back in; "stolen" pops «УКРАДЕНО!» and red
	    sparks, "void" is quiet; a base built mid-carry shows no display fish; ≤ MaxEmitters;
	  • the lamp: Neon + one looping Color tween + a PointLight while AlarmState, the colour and
	    material exactly back after (and beyond World.Range);
	  • the siren (two spinning SpotLights + beeps) and the thief's Highlight + «ВОР!» only with
	    HasAlarm (AlwaysOnTop for the owner, Occluded for others), gone at the end; the bell and the
	    lanterns untouched;
	  • the dome: the shield kind only, in range only, ≤ PhoneMax on touch, Inside transparency,
	    fades in and out;
	  • the tank sign's defences row «🛡️ 0:42» + «🔐1 · 🐕 · 🚨» (ticking), the flag label
	    «🛡️ 4:12» for any kind;
	  • the pier word «🚨 КРАДУТ!» red during the bite, hidden under CounterHold, back after;
	  • the dog: RenderStepped only while awake, follows DogPos facing its motion, «ГАВ!», dust
	    while its target is Slowed, back to the rest pivot asleep;
	  • the carried fish: the head weld's C0 alive (a looping tween), «🥷 Окунь $45» over it (+ «ВОР!»
	    with the alarm), C0 restored and the plate gone with it; FisherAnimController holds it
	    with both arms up (Trophy);
	  • HUD: a world word under ShieldChip / TheftBar / TheftAlert fades (hudRects);
	  • idle: no frame connections, no check chain, UiFx.activeJobs() == 0, nothing left after the
	    base is released; the client's own parts within MapConfig.PartBudget.RuntimeReserve.Theft.

	Run: lune run tools/run_tests.luau stage4_world
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

local PLACE = "Place1.rbxl"
local STUBBED = {
	"FishingService",
	"DataService",
	"EconomyService",
	"MarketService",
	"TankService",
	"DefenceService",
	"StealService",
}

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
local StealConfig = loadConfig("StealConfig")
local DefenceConfig = loadConfig("DefenceConfig")
local MapConfig = loadConfig("MapConfig")
local DISPLAY = TankConfig.Display
local STEAL = DISPLAY.Steal
local FX = DISPLAY.Fx
local WORLD = DefenceConfig.World
local DOME = WORLD.Dome
local WORDS = StealConfig.Texts.World
local FRAME = 1 / 60

--------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------

type Patch = { path: string, from: string, to: string }

local function boot(t: any, patches: { Patch }?): any
	local sim = t.sim({ place = PLACE })
	for _, name in STUBBED do
		sim:Find(`ServerScriptService.Services.{name}`).Source = "return {}"
	end
	local baseConfig = sim:Find("ReplicatedStorage.Shared.Config.BaseConfig")
	baseConfig.Source = string.gsub(baseConfig.Source, "RandomAssignment%s*=%s*true", "RandomAssignment = false")
	for _, patch in patches or {} do
		local module = sim:Find(patch.path)
		local source = module.Source
		local at = string.find(source, patch.from, 1, true)
		assert(at, `patch: «{patch.from}» not in {patch.path}`)
		module.Source = string.sub(source, 1, at - 1) .. patch.to .. string.sub(source, at + #patch.from)
	end
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

local function addPlayer(sim: any, id: number, device: string?): any
	local player =
		sim:AddPlayer({ UserId = id, Name = `Keeper{id}`, DisplayName = `Игрок{id}`, device = device or "phone" })
	sim:Advance(1)
	return player
end

local function baseOf(sim: any, player: any): any
	local base = sim.workspace.Bases:FindFirstChild(`Base_{player:GetAttribute("BaseIndex")}`)
	assert(base, `{player.Name}: own base`)
	return base
end

local function client(sim: any, player: any, name: string): any
	local module = sim:Find(`Controllers.{name}`, player:FindFirstChildOfClass("PlayerScripts"))
	assert(module, `{name} in PlayerScripts`)
	return sim:Require(module, player)
end

local function seen(sim: any, who: any, fn: () -> any): any
	return sim:Run(fn, who)
end

local function slotModel(base: any, index: number): any
	return base.Tank.Slots[`Slot_{index}`]
end

-- The client's own folder: Workspace.TankWorld (TankWorldController) / TheftWorld.
local function folder(sim: any, player: any, name: string): any
	local controller = if name == "TankWorld" then "TankWorldController" else "TheftWorldController"
	local found = client(sim, player, controller).Stats().folder
	assert(found, `{player.Name}: Workspace.{name}`)
	return found
end

local function named(root: any, name: string, class: string?): { any }
	local list = {}
	for _, d in root:GetDescendants() do
		if d.Name == name and (class == nil or d:IsA(class)) then
			table.insert(list, d)
		end
	end
	return list
end

local function countClass(root: any, class: string): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d:IsA(class) then
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

local FAR = CFrame.new(0, 3000, 0)

-- A base-local point (StealRules coordinates) in the world.
local function at(base: any, x: number, y: number, z: number): any
	return (base:GetPivot() * CFrame.new(x, y, z)).Position
end

-- The character in the aisle in front of a display (where a thief holds «Украсть»).
local function inFront(sim: any, player: any, base: any, index: number)
	sim.workspace.CurrentCamera.CFrame = FAR
	sim:Teleport(player, (slotModel(base, index).Display.CFrame * CFrame.new(0, -4, -5)).Position)
end

--------------------------------------------------------------------------------
-- The fake server (design §4.11)
--------------------------------------------------------------------------------

local Fake = {}
Fake.__index = Fake

local FISH_FIELDS = { "FishUid", "FishId", "Rarity", "Mutation", "Kg", "Value", "Income", "GrowFrom" }
local STEAL_FIELDS = { "StealBy", "StealEnd", "StealPhase" } -- (StealPhase last)

function Fake.new(sim: any, owner: any): any
	return setmetatable({
		sim = sim,
		owner = owner,
		base = baseOf(sim, owner),
		serial = 0,
		rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules")),
		tank = sim:Require(sim:Find("ReplicatedStorage.Shared.TankRules")),
		fish = {},
		uid = 0,
	}, Fake)
end

function Fake:now(): number
	return self.sim.workspace:GetServerTimeNow()
end

function Fake:event(slot: any, kind: string, detail: string?)
	self.serial += 1
	slot:SetAttribute("Event", `{self.serial}|{kind}|{detail or ""}`)
end

function Fake:record(id: string): any
	local def = self.rules.GetFish(id)
	local kg = (def.MinKg + def.MaxKg) / 2
	local value, income = self.rules.Price(id, kg, nil)
	self.uid += 1
	return {
		Uid = `f{self.uid}`,
		Id = id,
		Rarity = def.Rarity,
		Kg = kg,
		Value = value,
		Income10 = self.tank.Income10(income),
	}
end

function Fake:writeFish(slot: any, fish: any)
	slot:SetAttribute("FishUid", fish.Uid)
	slot:SetAttribute("FishId", fish.Id)
	slot:SetAttribute("Rarity", fish.Rarity)
	slot:SetAttribute("Kg", fish.Kg)
	slot:SetAttribute("Value", fish.Value)
	slot:SetAttribute("Income", fish.Income10 / 10)
	slot:SetAttribute("GrowFrom", self.tank.AttrTime(self:now() - 30))
end

function Fake:totals()
	local count, income10 = 0, 0
	for _, fish in self.fish do
		count += 1
		income10 += fish.Income10
	end
	self.base.Tank:SetAttribute("Count", count)
	self.base.Tank:SetAttribute("Slots", TankConfig.StartSlots)
	self.base.Tank:SetAttribute("Income", income10 / 10)
	self.owner:SetAttribute("TankCount", count)
	self.owner:SetAttribute("TankSlots", TankConfig.StartSlots)
	self.owner:SetAttribute("Income", income10 / 10)
end

function Fake:mount(ids: { string })
	self.fish = {}
	for index = 1, TankConfig.MaxSlots do
		local slot = slotModel(self.base, index)
		local id = ids[index]
		local state = if index > TankConfig.StartSlots then "locked" elseif id then "fish" else "empty"
		if state == "fish" then
			local fish = self:record(id)
			self:writeFish(slot, fish)
			self.fish[index] = fish
		else
			for _, name in FISH_FIELDS do
				slot:SetAttribute(name, nil)
			end
		end
		slot:SetAttribute("State", state)
		self:event(slot, "mount")
	end
	self:totals()
	self.sim:Advance(0.05)
end

-- The steal channel of a display: StealBy, StealEnd (AttrTime), then StealPhase LAST.
function Fake:steal(index: number, phase: string, thief: any, left: number)
	local slot = slotModel(self.base, index)
	slot:SetAttribute("StealBy", thief.UserId)
	slot:SetAttribute("StealEnd", self.tank.AttrTime(self:now() + left))
	slot:SetAttribute("StealPhase", phase)
	self.sim:Advance(FRAME)
end

function Fake:unsteal(index: number)
	local slot = slotModel(self.base, index)
	for _, name in STEAL_FIELDS do
		slot:SetAttribute(name, nil)
	end
	self.sim:Advance(FRAME)
end

-- The credit (TankService:StealFish step 1): the steal channel cleared, the fish fields nil,
-- State "empty", Event "<n>|stolen|<thief>" (kind "void" for a void: quiet).
function Fake:take(index: number, kind: string, thief: any?)
	local slot = slotModel(self.base, index)
	for _, name in STEAL_FIELDS do
		slot:SetAttribute(name, nil)
	end
	for _, name in FISH_FIELDS do
		slot:SetAttribute(name, nil)
	end
	slot:SetAttribute("State", "empty")
	self.fish[index] = nil
	self:event(slot, kind, if thief then tostring(thief.UserId) else "")
	self:totals()
	self.sim:Advance(FRAME)
end

-- The thief's StolenFish (the real Lib/HeldRig on the server) / gone.
function Fake:carry(thief: any, id: string): any
	local heldRig = self.sim:Require(self.sim:Find("ServerScriptService.Lib.HeldRig"))
	local fish = self:record(id)
	local model = heldRig.Build(
		thief.Character,
		{ Id = fish.Id, Rarity = fish.Rarity, Kg = fish.Kg, Value = fish.Value, Income = fish.Income10 / 10 },
		"StolenFish"
	)
	assert(model, "HeldRig built the StolenFish")
	self.sim:Advance(FRAME)
	return model
end

function Fake:drop(thief: any)
	local model = thief.Character and thief.Character:FindFirstChild("StolenFish")
	if model then
		model:Destroy()
	end
	self.sim:Advance(FRAME)
end

-- Base attributes: AlarmState / Thief (a theft on the base).
function Fake:alarm(state: string?, thief: any?)
	self.base:SetAttribute("Thief", if thief then thief.UserId else nil)
	self.base:SetAttribute("AlarmState", state)
	self.sim:Advance(FRAME)
end

-- What the base owns (DefenceService): HasDog / HasAlarm / LockLevel on the base and the owner.
function Fake:defence(owned: { [string]: any })
	for name, value in owned do
		self.base:SetAttribute(name, value)
		self.owner:SetAttribute(name, value)
	end
	self.sim:Advance(FRAME)
end

-- The base's protection (ProtectUntil AttrTime / ProtectKind); nil = none.
function Fake:protect(kind: string?, left: number?)
	if kind and left then
		self.base:SetAttribute("ProtectUntil", self.tank.AttrTime(self:now() + left))
		self.base:SetAttribute("ProtectKind", kind)
	else
		self.base:SetAttribute("ProtectUntil", nil)
		self.base:SetAttribute("ProtectKind", nil)
	end
	self.sim:Advance(FRAME)
end

-- The dog shown like DefenceService: every part opaque, the pup pivoted to Dog.Rest (its template
-- height over the ground, facing the gate), Unlocked = true. Returns the rest pivot.
function Fake:showDog(): any
	local dog = self.base.Dog
	for _, d in dog:GetDescendants() do
		if d:IsA("BasePart") then
			d.Transparency = 0
		end
	end
	local pivot = self.base:GetPivot()
	local height = (pivot:Inverse() * dog.Pup:GetPivot()).Position.Y
	local rest = pivot * CFrame.new(DefenceConfig.Dog.Rest.X, height, DefenceConfig.Dog.Rest.Z)
	dog.Pup:PivotTo(rest)
	dog:SetAttribute("Unlocked", true)
	self.sim:Advance(FRAME)
	return rest
end

-- The dog's brain (DogBrain attributes): state, a base-local ground point (x, z) → DogPos (world).
function Fake:dog(state: string?, x: number?, z: number?, target: any?)
	local dog = self.base.Dog
	dog:SetAttribute("DogState", state)
	dog:SetAttribute("DogPos", if x and z then at(self.base, x, 0, z) else nil)
	dog:SetAttribute("DogTarget", if target then target.UserId else nil)
	self.sim:Advance(FRAME)
end

--------------------------------------------------------------------------------
-- Display checks
--------------------------------------------------------------------------------

-- The display fish's box centre and its top in the FishPoint frame (client view).
local function fishLocal(sim: any, viewer: any, model: any, point: any): (any, number)
	return seen(sim, viewer, function()
		local box, size = model:GetBoundingBox()
		local frame = point.WorldCFrame
		local c = frame:PointToObjectSpace(box.Position)
		local top = 0
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				local half = part.Size / 2
				for _, sx in { -1, 1 } do
					for _, sy in { -1, 1 } do
						for _, sz in { -1, 1 } do
							local p = frame:PointToObjectSpace(
								part.CFrame * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
							)
							top = math.max(top, p.Y)
						end
					end
				end
			end
		end
		local _ = size
		return c, top
	end)
end

local function wordIn(root: any, name: string, text: string): any?
	for _, gui in named(root, name, "BillboardGui") do
		for _, d in gui:GetDescendants() do
			if d:IsA("TextLabel") and d.Text == text then
				return gui
			end
		end
	end
	return nil
end

local tests = {}

tests["hold: the fish rises Lift, tilts towards the aisle and struggles; «КРАДУТ!» with a ring, a red pulse, the tag hidden; released → it drops back with a splash"] = function(
	t
)
	local sim = boot(t)
	local owner = addPlayer(sim, 1)
	local thief = addPlayer(sim, 2)
	local fake = Fake.new(sim, owner)
	local base = fake.base
	local world = client(sim, owner, "TankWorldController")
	world.SetLife(false) -- (RbxSim does not carry welded parts with a tweened Body)
	fake:mount({ "Perch", "Puffer", "Crucian" })
	inFront(sim, owner, base, 3)
	sim:Advance(2.2, FRAME * 2)
	local model = world.GetFish(base, 3)
	t.ok(model, "Slot_3 has its display fish")
	local point = slotModel(base, 3).Display.FishPoint
	local display = slotModel(base, 3).Display
	local c0 = fishLocal(sim, owner, model, point)
	t.ok(c0.Magnitude < 0.1, "at rest: centred on FishPoint")
	local tankWorld = folder(sim, owner, "TankWorld")
	t.eq(#named(tankWorld, "FxTankSteal"), 0, "no steal word yet")

	fake:steal(3, "hold", thief, 3)
	sim:Advance(0.05)
	local word = wordIn(tankWorld, "FxTankSteal", WORDS.Stealing)
	t.ok(word, "«КРАДУТ!» over the display")
	t.eq(word.MaxDistance, WORLD.StealWordRange, "… seen from the spawn (StealWordRange)")
	t.ok(#named(word, "FxRingTimer") == 1, "… with a ring timer to StealEnd")
	local wordAt = word.Parent.WorldPosition
	local local0 = point.WorldCFrame:PointToObjectSpace(wordAt)
	t.near(local0.Y, DISPLAY.Tag.Lift, 0.01, "… at the LightBar's height")
	t.near(local0.Z, -DISPLAY.Tag.Forward, 0.01, "… in front of the glass (like the aisle tag)")
	t.eq(world.GetTag(base, 3).Enabled, false, "the aisle tag hides meanwhile")
	t.eq(#named(tankWorld, "FxStealPulse", "PointLight"), 1, "a red pulse at the LightBar")
	sim:Advance(STEAL.LiftTime + 0.05)
	local c1, top1 = fishLocal(sim, owner, model, point)
	local s = STEAL.Struggle
	t.ok(
		c1.Y > STEAL.LiftMin - s.Bob - 0.05 and c1.Y < STEAL.Lift + s.Bob + 0.05,
		`lifted (LiftMin..Lift; got {math.floor(c1.Y * 100) / 100})`
	)
	t.ok(c1.Y > 1, "… a small fish by about Lift")
	t.ok(top1 <= display.Size.Y / 2, `… and still under the glass top ({top1})`)
	local tilt = seen(sim, owner, function()
		return model.PrimaryPart.CFrame.UpVector:Dot(display.CFrame.LookVector)
	end)
	t.ok(tilt > math.sin(math.rad(STEAL.Tilt)) * 0.7, `tilted towards the aisle (up·front = {tilt})`)
	local a = seen(sim, owner, function()
		return model.PrimaryPart.CFrame
	end)
	sim:Advance(s.Time * 0.6)
	local b = seen(sim, owner, function()
		return model.PrimaryPart.CFrame
	end)
	t.ok((a.Position - b.Position).Magnitude > 0.01 or a.LookVector:Dot(b.LookVector) < 0.9999, "it struggles (moving)")
	t.ok(s.Time * 2 >= 1 / 3, "struggle ≤ 3 Hz (STYLE)")
	-- life never starts on a stolen fish
	world.SetLife(true)
	sim:Advance(1)
	t.eq(world.IsAlive(base, 3), false, "no life tween while it is being stolen")
	world.SetLife(false)

	-- released: back down with the stage 3 splash, the word goes, the tag returns
	fake:unsteal(3)
	sim:Advance(STEAL.DropTime + 0.1)
	local c2 = fishLocal(sim, owner, model, point)
	t.ok(c2.Magnitude < 0.05, "dropped back onto FishPoint")
	t.ok(#named(tankWorld, "Fxsplash", "ParticleEmitter") >= 1, "the «in» splash")
	sim:Advance(FX.TagOut + 0.1)
	t.eq(#named(tankWorld, "FxTankSteal"), 0, "the word is gone")
	t.eq(#named(tankWorld, "FxStealPulse"), 0, "the pulse is gone")
	t.eq(world.GetTag(base, 3).Enabled, true, "the tag is back")
	t.eq(world.GetFish(base, 3), model, "the same fish (no rebuild)")
	sim:Advance(FX.EmitterLife + 0.2)
	t.ok(world.Stats().emitters <= FX.MaxEmitters, "≤ MaxEmitters")
	sim:AssertNoErrors({ warnings = true })
end

tests["carry: the fish flies out of the FRONT glass under the ceiling onto the thief's head, the display empties («УНОСЯТ!»); returned → it flies back in"] = function(
	t
)
	local sim = boot(t)
	local owner = addPlayer(sim, 1)
	local thief = addPlayer(sim, 2)
	local fake = Fake.new(sim, owner)
	local base = fake.base
	local world = client(sim, owner, "TankWorldController")
	world.SetLife(false)
	fake:mount({ "Perch", "Puffer", "Swordfish" })
	inFront(sim, owner, base, 3)
	sim:Advance(2.2, FRAME * 2)
	-- the thief at Slot_3's prompt
	local prompt = slotModel(base, 3).Pedestal.PromptAttachment.WorldPosition
	sim:Teleport(thief, prompt + Vector3.new(0, 1, 0))
	sim:Advance(0.1)
	local model = world.GetFish(base, 3)
	local point = slotModel(base, 3).Display.FishPoint
	local display = slotModel(base, 3).Display
	fake:steal(3, "hold", thief, 3)
	sim:Advance(STEAL.LiftTime + 0.3)
	-- the hold completes: StolenFish on the thief's head, then the carry
	local stolen = fake:carry(thief, "Swordfish")
	fake:steal(3, "carry", thief, StealConfig.Carry.Timeout)
	local tankWorld = folder(sim, owner, "TankWorld")
	t.eq(world.GetFish(base, 3), nil, "the display has no fish any more")
	t.ok(wordIn(tankWorld, "FxTankSteal", WORDS.Carrying), "«КРАДУТ!» → «УНОСЯТ!»")
	t.ok(model.Parent ~= nil, "… the display fish flies (a copy in the air)")
	local hidden = seen(sim, owner, function()
		return stolen.PrimaryPart.LocalTransparencyModifier
	end)
	t.eq(hidden, 1, "the StolenFish is hidden on this client while the fish flies to it")
	-- watch the flight: never through the top of the glass, never above FishPoint + ArcTop
	local face = display.Size.Z / 2
	local highest, pokedTop, outFront = -math.huge, false, false
	local frames = 0
	while model.Parent and frames < 60 do
		local c, top = fishLocal(sim, owner, model, point)
		highest = math.max(highest, top)
		if c.Z > -face and top > display.Size.Y / 2 + 0.35 then
			pokedTop = true -- (inside the cube's depth and above its top: through the top glass)
		end
		if c.Z < -face then
			outFront = true
		end
		sim:Advance(FRAME)
		frames += 1
	end
	t.ok(frames >= math.floor(STEAL.ArcTime * 60) - 2, `the flight takes ≈ ArcTime ({frames} frames)`)
	t.ok(outFront, "it leaves through the FRONT face (towards the aisle)")
	t.eq(pokedTop, false, "never through the top of the glass")
	t.ok(highest <= STEAL.ArcTop + 0.1, `its top never above FishPoint + ArcTop ({highest})`)
	t.eq(model.Parent, nil, "the flying copy is gone (the StolenFish took over)")
	local shown = seen(sim, owner, function()
		return stolen.PrimaryPart.LocalTransparencyModifier
	end)
	t.eq(shown, 0, "the StolenFish shows again")

	-- returned (a shield, a tag…): the StolenFish goes, a fish flies back into the display
	fake:drop(thief)
	fake:unsteal(3)
	local back = world.GetFish(base, 3)
	t.ok(back, "a display fish again at once (it flies back in)")
	t.eq(world.GetTag(base, 3).Enabled, false, "… its tag waits for the landing")
	sim:Advance(STEAL.ArcTime + 0.1)
	local c = fishLocal(sim, owner, back, point)
	t.ok(c.Magnitude < 0.05, "landed on FishPoint")
	t.ok(#named(tankWorld, "Fxsplash", "ParticleEmitter") >= 1, "with the «in» splash")
	t.eq(world.GetTag(base, 3).Enabled, true, "the tag is back")
	sim:Advance(FX.TagOut + 0.1)
	t.eq(#named(tankWorld, "FxTankSteal"), 0, "no steal word left")
	sim:AssertNoErrors({ warnings = true })
end

tests["stolen: «УКРАДЕНО!» pops and fades in StolenTime, red sparks; void is quiet; a base built mid-carry shows no fish; unmount clears it all"] = function(
	t
)
	local sim = boot(t)
	local owner = addPlayer(sim, 1)
	local thief = addPlayer(sim, 2)
	local fake = Fake.new(sim, owner)
	local base = fake.base
	local world = client(sim, owner, "TankWorldController")
	world.SetLife(false)
	fake:mount({ "Perch", "Puffer", "Swordfish", "Crucian" })
	inFront(sim, owner, base, 3)
	sim:Advance(2.2, FRAME * 2)
	local tankWorld = folder(sim, owner, "TankWorld")
	fake:steal(3, "hold", thief, 3)
	sim:Advance(0.4)
	fake:carry(thief, "Swordfish")
	fake:steal(3, "carry", thief, 25)
	sim:Advance(0.5)
	-- the credit at the plot edge
	fake:drop(thief)
	fake:take(3, "stolen", thief)
	t.ok(wordIn(tankWorld, "FxTankPop", WORDS.Stolen), "«УКРАДЕНО!» pops at the display")
	local sparks = named(tankWorld, "Fxsparkle", "ParticleEmitter")
	t.ok(#sparks >= 1, "red sparks")
	if sparks[1] then
		local color = sparks[1].Color.Keypoints[2].Value
		t.ok(color.R > color.G and color.R > color.B, "… Berry")
	end
	t.eq(#named(tankWorld, "FxTankSteal"), 0, "the «УНОСЯТ!» word is replaced")
	t.eq(world.GetFish(base, 3), nil, "the display stays empty")
	sim:Advance(STEAL.StolenTime + 0.2)
	t.eq(wordIn(tankWorld, "FxTankPop", WORDS.Stolen), nil, "faded away after StolenTime")
	t.ok(world.Stats().emitters <= FX.MaxEmitters, "≤ MaxEmitters")
	sim:Advance(FX.EmitterLife)
	-- void (the escrowed copy returned to its owner): quiet
	local before = world.Stats().emitters
	fake:take(4, "void")
	sim:Advance(0.05)
	t.eq(world.GetFish(base, 4), nil, "void: the fish is gone")
	t.eq(#named(tankWorld, "FxTankPop"), 0, "… no word")
	t.eq(world.Stats().emitters, before, "… no FX")

	-- a base that comes into range mid-carry: no display fish, the word «УНОСЯТ!»
	sim:Teleport(owner, base.FishingSpot.Position + Vector3.new(0, 3, 0))
	sim:Teleport(owner, base:GetPivot().Position + Vector3.new(0, 3, -900))
	sim:Advance(1.2)
	t.eq(world.IsBuilt(base), false, "far away: torn down")
	fake:steal(2, "hold", thief, 3)
	fake:carry(thief, "Puffer")
	fake:steal(2, "carry", thief, 25)
	inFront(sim, owner, base, 2)
	sim:Advance(2.2, FRAME * 2)
	t.eq(world.IsBuilt(base), true, "built again")
	t.eq(world.GetFish(base, 2), nil, "mid-carry: no fish in Slot_2")
	t.ok(wordIn(tankWorld, "FxTankSteal", WORDS.Carrying), "… «УНОСЯТ!» over it")
	t.ok(world.GetFish(base, 1), "Slot_1 still shows its fish")
	-- the owner leaves (unmount): the steal channel cleared, all empty → nothing left
	fake:drop(thief)
	for index = 1, TankConfig.MaxSlots do
		local slot = slotModel(base, index)
		for _, name in STEAL_FIELDS do
			slot:SetAttribute(name, nil)
		end
		for _, name in FISH_FIELDS do
			slot:SetAttribute(name, nil)
		end
		slot:SetAttribute("State", "empty")
		fake:event(slot, "mount")
	end
	sim:Advance(0.6)
	t.eq(world.Stats().fish, 0, "no fish")
	t.eq(#named(tankWorld, "FxTankSteal"), 0, "no steal word")
	t.eq(#named(tankWorld, "FxStealPulse"), 0, "no pulse")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The base: lamp, siren, mark, dome, sign, flag
--------------------------------------------------------------------------------

local function nearCourt(sim: any, player: any, base: any)
	sim.workspace.CurrentCamera.CFrame = FAR
	sim:Teleport(player, at(base, 0, 3, 50))
end

tests["lamp: AlarmState → Neon + one looping Color tween + a red PointLight; intruder slower; the template look exactly back after (and beyond Range)"] = function(
	t
)
	local sim = boot(t)
	local owner = addPlayer(sim, 1)
	local thief = addPlayer(sim, 2)
	local fake = Fake.new(sim, owner)
	local base = fake.base
	local theft = client(sim, owner, "TheftWorldController")
	nearCourt(sim, owner, base)
	local lamp = base.Alarm.Lamp
	local color0, material0 = lamp.Color, lamp.Material
	local view = function(): (any, any)
		return seen(sim, owner, function()
			return lamp.Color, lamp.Material
		end)
	end
	fake:alarm("theft", thief)
	sim:Advance(0.1)
	local info = theft.Get(base)
	t.ok(info.lamp, "the lamp is lit")
	local _, material = view()
	t.eq(material, Enum.Material.Neon, "Neon on this client")
	t.eq(lamp.Material, material0, "… the server's lamp untouched")
	local colors = {}
	for _ = 1, 6 do
		local c = view()
		table.insert(colors, c)
		sim:Advance(WORLD.LampPeriod / 6)
	end
	local moved = false
	for i = 2, #colors do
		if colors[i] ~= colors[1] then
			moved = true
		end
	end
	t.ok(moved, "the colour tweens (flashing)")
	t.ok(info.light and info.light:IsA("PointLight"), "a client PointLight")
	t.eq(info.light.Range, WORLD.LampLight.Range)
	t.eq(info.light.Shadows, false)
	t.ok(WORLD.LampPeriod >= 1 / 3, "≤ 3 Hz")
	local lights = #named(folder(sim, owner, "TheftWorld"), "FxAlarmGlow")
	t.eq(lights, 1, "one light")
	-- the theft over: back exactly
	fake:alarm(nil)
	sim:Advance(WORLD.CheckEvery + 0.1)
	local c, m = view()
	t.eq(c, color0, "the colour exactly as the template")
	t.eq(m, material0, "the material exactly as the template")
	t.eq(#named(folder(sim, owner, "TheftWorld"), "FxAlarmGlow"), 0, "no light")
	t.eq(theft.Stats().running, false, "nothing on: the check chain stops")
	-- an intruder (alarm upgrade): flashes too, then far away → the template look
	fake:alarm("intruder")
	sim:Advance(0.1)
	t.ok(theft.Get(base).lamp, "intruder: lit")
	sim.workspace.CurrentCamera.CFrame = FAR
	sim:Teleport(owner, base:GetPivot().Position + Vector3.new(0, 3, -WORLD.Range - 200))
	sim:Advance(WORLD.CheckEvery + 0.1)
	t.eq(theft.Get(base).lamp, false, "beyond Range: off")
	local c2, m2 = view()
	t.eq(c2, color0, "… colour back")
	t.eq(m2, material0, "… material back")
	sim:AssertNoErrors({ warnings = true })
end

tests["siren and the thief's mark only with HasAlarm: two spinning SpotLights + beeps; Highlight AlwaysOnTop for the owner, Occluded for a bystander; «ВОР!»; gone at the end; bell and lanterns untouched"] = function(
	t
)
	local sim = boot(t)
	local owner = addPlayer(sim, 1)
	local thief = addPlayer(sim, 2)
	local bystander = addPlayer(sim, 3, "desktop")
	local fake = Fake.new(sim, owner)
	local base = fake.base
	local theftOwner = client(sim, owner, "TheftWorldController")
	local theftBy = client(sim, bystander, "TheftWorldController")
	nearCourt(sim, owner, base)
	nearCourt(sim, bystander, base)
	local bell = base.Alarm.Bell
	local bellCF, bellColor = bell.CFrame, bell.Color
	-- without the alarm upgrade: the lamp only
	fake:alarm("theft", thief)
	sim:Advance(0.2)
	t.ok(theftOwner.Get(base).lamp, "the lamp flashes for everyone")
	t.eq(theftOwner.Get(base).siren, nil, "no siren without HasAlarm")
	t.eq(theftOwner.Get(base).mark, nil, "no Highlight without HasAlarm")
	-- with it
	fake:defence({ HasAlarm = true })
	sim:Advance(WORLD.CheckEvery + 0.1)
	local info = theftOwner.Get(base)
	t.ok(info.siren, "the siren")
	t.eq(#named(info.siren, "FxSirenBeam", "SpotLight"), 2, "two SpotLights back to back")
	local r0 = seen(sim, owner, function()
		return info.siren.CFrame
	end)
	sim:Advance(WORLD.SirenSpin / 8)
	local r1 = seen(sim, owner, function()
		return info.siren.CFrame
	end)
	t.ok(r0.LookVector:Dot(r1.LookVector) < 0.999, "… spinning")
	local beeps0 = theftOwner.Get(base).beeps
	sim:Advance(WORLD.Siren.BeepPeriod * 3 + 0.05)
	t.ok(theftOwner.Get(base).beeps >= beeps0 + 2, "beeps every BeepPeriod (camera within BeepRange)")
	local mark = info.mark
	t.ok(mark and mark:IsA("Highlight"), "the thief's Highlight")
	t.eq(mark.Adornee, thief.Character, "… on his character")
	t.eq(mark.DepthMode, Enum.HighlightDepthMode.AlwaysOnTop, "… seen through walls by the owner")
	local other = theftBy.Get(base).mark
	t.ok(other, "the bystander sees it too")
	t.eq(other.DepthMode, Enum.HighlightDepthMode.Occluded, "… occluded for him")
	local tag = info.tag
	t.ok(tag and tag.Enabled, "«ВОР!» over his head")
	t.eq(tag.Adornee, thief.Character.Head)
	t.ok(wordIn(folder(sim, owner, "TheftWorld"), "FxThiefTag", WORDS.Thief), "… reading «ВОР!»")
	-- the end
	fake:alarm(nil)
	sim:Advance(WORLD.CheckEvery + 0.1)
	t.eq(theftOwner.Get(base).siren, nil, "the siren off")
	t.eq(theftOwner.Get(base).mark, nil, "the Highlight destroyed")
	t.eq(countClass(folder(sim, owner, "TheftWorld"), "Highlight"), 0, "… none left in the folder")
	t.eq(#named(folder(sim, owner, "TheftWorld"), "FxThiefTag"), 0, "no «ВОР!»")
	t.eq(bell.CFrame, bellCF, "the bell untouched (P2)")
	t.eq(bell.Color, bellColor)
	sim:AssertNoErrors({ warnings = true })
end

tests["dome: the shield only, in range only, ≤ PhoneMax on touch (all on a PC), Inside when the camera is in, fades in and out"] = function(
	t
)
	local sim = boot(t, {
		{
			path = "ReplicatedStorage.Shared.Config.DefenceConfig",
			from = "Inside = 0.8,\n\t\t\tRange = 260,",
			to = "Inside = 0.8,\n\t\t\tRange = 5000,",
		},
	})
	local players = {}
	for id = 1, 4 do
		table.insert(players, addPlayer(sim, id, if id == 4 then "desktop" else "phone"))
	end
	local phone, desk = players[1], players[4]
	local fakes = {}
	for i = 1, 4 do
		fakes[i] = Fake.new(sim, players[i])
	end
	local onPhone = client(sim, phone, "TheftWorldController")
	local onDesk = client(sim, desk, "TheftWorldController")
	nearCourt(sim, phone, fakes[1].base)
	nearCourt(sim, desk, fakes[1].base)
	-- a join protection: no dome
	fakes[1]:protect("join", 90)
	sim:Advance(WORLD.CheckEvery + 0.1)
	t.eq(onPhone.Get(fakes[1].base).dome, nil, "join protection: no dome (DC-15)")
	-- the shield: a dome
	fakes[1]:protect("shield", 60)
	sim:Advance(0.1)
	local dome = onPhone.Get(fakes[1].base).dome
	t.ok(dome, "the shield: a dome")
	t.eq(dome.Shape, Enum.PartType.Ball)
	t.eq(dome.Material, Enum.Material.ForceField)
	t.near(dome.Size.X, DOME.Radius * 2, 1e-3, "Ø 2 × Radius")
	t.near(dome.Position, at(fakes[1].base, DOME.Center.X, DOME.Center.Y, DOME.Center.Z), 1e-3, "at Dome.Center")
	t.eq(dome.CanCollide, false)
	t.eq(dome.CanQuery, false)
	t.eq(dome.CanTouch, false)
	t.eq(dome.CastShadow, false)
	-- from outside: Transparency; the camera inside: Inside (faint)
	sim:Advance(DOME.Fade + WORLD.CheckEvery)
	local outside0 = seen(sim, phone, function()
		return dome.Transparency
	end)
	t.near(outside0, DOME.Transparency, 0.02, "faded in to Transparency (camera outside)")
	local court = at(fakes[1].base, DOME.Center.X, 8, DOME.Center.Z)
	seen(sim, phone, function()
		sim.workspace.CurrentCamera.CFrame = CFrame.new(court)
	end)
	sim:Advance(WORLD.CheckEvery + DOME.Fade + 0.1)
	local inside = seen(sim, phone, function()
		return dome.Transparency
	end)
	t.near(inside, DOME.Inside, 0.02, "camera inside the dome: faint (Inside)")
	seen(sim, phone, function()
		sim.workspace.CurrentCamera.CFrame = FAR
	end)
	sim:Advance(WORLD.CheckEvery + DOME.Fade + 0.1)
	local outside = seen(sim, phone, function()
		return dome.Transparency
	end)
	t.near(outside, DOME.Transparency, 0.02, "from outside: Transparency")
	-- three shields: the phone keeps the PhoneMax nearest, the PC all
	fakes[2]:protect("shield", 60)
	fakes[3]:protect("shield", 60)
	sim:Advance(WORLD.CheckEvery + 0.1)
	t.eq(onPhone.Stats().domes, DOME.PhoneMax, `touch: ≤ PhoneMax ({DOME.PhoneMax})`)
	t.eq(onDesk.Stats().domes, 3, "PC: every shielded base in range")
	t.ok(onPhone.Get(fakes[1].base).dome, "… the nearest kept")
	-- the shield over: it fades out, then it is gone
	fakes[1]:protect(nil)
	fakes[2]:protect(nil)
	fakes[3]:protect(nil)
	sim:Advance(WORLD.CheckEvery + 0.05)
	t.eq(onPhone.Stats().domes, 0, "no dome kept")
	t.ok(onPhone.Stats().fading >= 1, "… fading out")
	sim:Advance(DOME.Fade + WORLD.CheckEvery + 0.1)
	t.eq(countClass(folder(sim, phone, "TheftWorld"), "Part"), 1, "only the Anchor part left")
	t.eq(onPhone.Stats().running, false, "the chain stopped")
	sim:AssertNoErrors({ warnings = true })
end

tests["tank sign defences row «🛡️ 0:42» + «🔐1 · 🐕 · 🚨» (ticks, any kind); the flag label «🛡️ 4:12» under the owner sign"] = function(
	t
)
	local sim = boot(t)
	local owner = addPlayer(sim, 1)
	local visitor = addPlayer(sim, 2)
	local fake = Fake.new(sim, owner)
	local base = fake.base
	local world = client(sim, visitor, "TankWorldController")
	local theft = client(sim, visitor, "TheftWorldController")
	fake:mount({ "Perch", "Puffer" })
	nearCourt(sim, visitor, base)
	sim:Advance(1)
	local sign = world.GetSign(base)
	t.ok(sign and sign.Enabled, "the tank sign")
	local size0 = sign.Size
	t.eq(sign.Plate:FindFirstChild("Owned"), nil, "nothing owned, no protection: no third row")
	fake:defence({ LockLevel = 1, HasDog = true, HasAlarm = true })
	sim:Advance(0.1)
	local owned = sign.Plate:FindFirstChild("Owned")
	t.ok(owned and owned.Visible, "the defences row")
	t.eq(owned.Text, "🔐1 · 🐕 · 🚨", "«🔐1 · 🐕 · 🚨»")
	t.eq(sign.Plate.Protect.Visible, false, "no protection: no «🛡️»")
	t.ok(sign.Size.Y.Scale > size0.Y.Scale, "the sign grew (downwards) for the row")
	fake:protect("join", 42)
	sim:Advance(0.05)
	t.eq(sign.Plate.Protect.Text, "🛡️ 0:42", "«🛡️ 0:42» for a join protection too")
	t.eq(sign.Plate.Owned.Text, "· 🔐1 · 🐕 · 🚨", "… then the owned defences")
	sim:Advance(2 * DISPLAY.TagEvery + DISPLAY.CheckEvery + 0.1)
	local ticked = sign.Plate.Protect.Text
	t.ok(ticked == "🛡️ 0:41" or ticked == "🛡️ 0:40", `it ticks once a second ({ticked})`)
	-- the shield's readiness is never shown: a ready shield with no protection shows nothing
	fake:protect(nil)
	fake:defence({ LockLevel = 0, HasDog = false, HasAlarm = false })
	sim:Advance(0.05)
	t.eq(sign.Plate.Protect.Visible, false)
	t.eq(sign.Plate.Owned.Visible, false)
	t.eq(sign.Size, size0, "the sign back to its size")
	-- the flag: any kind, under the owner sign, seen across the map
	fake:protect("rest", 252)
	sim:Advance(0.1)
	local flag = theft.Get(base).flag
	t.ok(flag, "the flag label")
	local ownerSign = base.Flag.Pole.SignAttachment.OwnerSign
	t.eq(flag.Adornee, base.Flag.Pole.SignAttachment, "on the flag's SignAttachment")
	t.eq(flag.MaxDistance, ownerSign.MaxDistance, "seen as far as the owner sign")
	t.ok(flag.SizeOffset.Y < -0.9, "under the owner sign")
	t.ok(wordIn(folder(sim, visitor, "TheftWorld"), "FxFlagProtect", "🛡️ 4:12"), "«🛡️ 4:12»")
	sim:Advance(1.6)
	local theftWorld = folder(sim, visitor, "TheftWorld")
	t.ok(
		wordIn(theftWorld, "FxFlagProtect", "🛡️ 4:11") or wordIn(theftWorld, "FxFlagProtect", "🛡️ 4:10"),
		"ticks"
	)
	fake:protect(nil)
	sim:Advance(WORLD.CheckEvery + 0.1)
	t.eq(theft.Get(base).flag, nil, "gone with the protection")
	sim:AssertNoErrors({ warnings = true })
end

tests["pier word: «🚨 КРАДУТ!» red during the bite while the own base is robbed, hidden under CounterHold, the tank lines back after"] = function(
	t
)
	local sim = boot(t)
	local owner = addPlayer(sim, 1)
	local thief = addPlayer(sim, 2)
	local fake = Fake.new(sim, owner)
	local base = fake.base
	local world = client(sim, owner, "TankWorldController")
	local hud = owner.PlayerGui.HUD
	fake:mount({ "Perch", "Puffer", "Crucian" })
	sim:Teleport(owner, base.FishingSpot.Position + Vector3.new(0, 3, 0))
	sim:Advance(0.2)
	local word = world.GetPierWord()
	t.eq(word.Enabled, true, "the pier word")
	owner:SetAttribute("FishingState", "Bite")
	sim:Advance(0.05)
	t.eq(word.Enabled, false, "the bite hides it (stage 3)")
	fake:alarm("theft", thief)
	sim:Advance(0.05)
	t.eq(word.Enabled, true, "a theft: shown during the bite")
	local alarm = word.Plate:FindFirstChild("Alarm")
	t.ok(alarm and alarm.Visible, "«🚨 КРАДУТ!»")
	t.eq(alarm.Text, WORDS.Pier)
	t.eq(word.Plate.Count.Visible, false, "the tank lines hide")
	local outline = alarm:FindFirstChild("Outline")
	t.ok(outline and outline.Color.R > outline.Color.B, "red (Berry)")
	owner:SetAttribute("FishingState", "Reeling")
	sim:Advance(0.05)
	t.eq(word.Enabled, true, "… and in the minigame")
	hud:SetAttribute("CounterHold", 0)
	sim:Advance(0.05)
	t.eq(word.Enabled, false, "hidden under CounterHold (the catch card)")
	hud:SetAttribute("CounterHold", nil)
	sim:Advance(0.05)
	t.eq(word.Enabled, true)
	fake:alarm(nil)
	owner:SetAttribute("FishingState", "Idle")
	sim:Advance(0.05)
	t.eq(alarm.Visible, false, "the theft over: the alarm word goes")
	t.eq(word.Plate.Count.Visible, true, "… the tank lines are back")
	t.eq(word.Plate.Count.Text, "🐠 3/6")
	sim:AssertNoErrors({ warnings = true })
end

tests["dog: RenderStepped only while awake, follows DogPos facing its motion, «ГАВ!», dust while its target is Slowed; asleep → the rest pivot exactly"] = function(
	t
)
	local sim = boot(t)
	local owner = addPlayer(sim, 1)
	local thief = addPlayer(sim, 2)
	local fake = Fake.new(sim, owner)
	local base = fake.base
	local theft = client(sim, owner, "TheftWorldController")
	nearCourt(sim, owner, base)
	sim:Advance(0.5)
	local frames0 = frameConnections(sim, owner)
	local rest = fake:showDog()
	fake:dog("Sleep")
	sim:Advance(0.6)
	t.eq(frameConnections(sim, owner), frames0, "asleep: no frame connection")
	t.eq(theft.Get(base).dog, false)
	local pup = base.Dog.Pup
	-- wake: «ГАВ!», then the chase
	fake:dog("Alert", DefenceConfig.Dog.Rest.X, DefenceConfig.Dog.Rest.Z, thief)
	sim:Advance(0.1)
	t.ok(wordIn(folder(sim, owner, "TheftWorld"), "FxTankPop", WORDS.Bark), "«ГАВ!» on Alert")
	t.eq(frameConnections(sim, owner), frames0 + 1, "awake: one RenderStepped")
	fake:dog("Chase", 26, 72, thief)
	sim:Advance(1.2)
	-- (the client's view of the pup: its parts — RbxSim's GetPivot reads the server's)
	local function pupAt(): any
		return seen(sim, owner, function()
			return pup.PrimaryPart.CFrame
		end)
	end
	local pivot = pupAt()
	local goal = at(base, 26, 0, 72)
	local flat = Vector3.new(pivot.Position.X - goal.X, 0, pivot.Position.Z - goal.Z)
	t.ok(flat.Magnitude < 0.5, `follows DogPos ({flat.Magnitude} studs off)`)
	t.near(pup:GetPivot(), rest, 1e-3, "… on this client only (the server's pup stays at Dog.Rest)")
	fake:dog("Chase", 26, 92, thief)
	sim:Advance(0.15)
	local look = pupAt().LookVector
	local dir = (at(base, 26, 0, 92) - at(base, 26, 0, 72)).Unit
	t.ok(look:Dot(dir) > 0.95, "faces its motion")
	-- a bite: the target slowed → «ГАВ!» + dust; free again → no dust
	thief:SetAttribute("Slowed", true)
	sim:Advance(0.3)
	t.ok(theft.Get(base).dust, "dust at the slowed thief's feet")
	t.ok(#named(folder(sim, owner, "TheftWorld"), "Fxdust", "ParticleEmitter") == 1, "one dust emitter")
	thief:SetAttribute("Slowed", nil)
	sim:Advance(0.1)
	t.eq(theft.Get(base).dust, false, "free again: no dust")
	-- home and asleep: the connection goes, the pivot exactly the server's
	fake:dog("Return", DefenceConfig.Dog.Rest.X, DefenceConfig.Dog.Rest.Z)
	sim:Advance(1)
	fake:dog("Sleep", DefenceConfig.Dog.Rest.X, DefenceConfig.Dog.Rest.Z)
	sim:Advance(WORLD.CheckEvery + 0.1)
	t.eq(frameConnections(sim, owner), frames0, "asleep: the RenderStepped is gone")
	local back = pupAt()
	t.near(back, rest, 1e-4, "the rest pivot exactly")
	t.eq(theft.Stats().running, false, "nothing on: no chain")
	sim:AssertNoErrors({ warnings = true })
end

tests["carried fish: the head weld alive, «🥷 Окунь $45» over it (+ «ВОР!» with the alarm); C0 back and the plate gone with it; both arms up (FisherAnimController)"] = function(
	t
)
	local sim = boot(t)
	local owner = addPlayer(sim, 1)
	local thief = addPlayer(sim, 2)
	local fake = Fake.new(sim, owner)
	local base = fake.base
	local theft = client(sim, owner, "TheftWorldController")
	local anim = client(sim, owner, "FisherAnimController")
	nearCourt(sim, owner, base)
	sim:Teleport(thief, at(base, 0, 3, 56))
	sim:Advance(0.3)
	fake:alarm("theft", thief)
	local model = fake:carry(thief, "Perch")
	sim:Advance(0.1)
	local info = theft.Get(base)
	t.eq(info.carried, model, "the StolenFish is watched")
	local plate = info.plate
	t.ok(plate, "its nameplate")
	t.eq(plate.Adornee, model.PrimaryPart)
	local rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"))
	local tankRules = sim:Require(sim:Find("ReplicatedStorage.Shared.TankRules"))
	local expected = string.gsub(WORDS.Carried, "{short}", rules.GetFish("Perch").ShortName)
	expected = string.gsub(expected, "{price}", tankRules.FormatMoney(model:GetAttribute("Value")))
	t.ok(wordIn(folder(sim, owner, "TheftWorld"), "FxCarriedPlate", expected), `«{expected}»`)
	t.eq(plate.Plate.Thief.Visible, false, "no «ВОР!» line without the alarm")
	-- alive: the head weld's C0 moves (client-local), the server's stays
	local weld = nil
	for _, w in model.PrimaryPart:GetChildren() do
		if w:IsA("Weld") and w.Part0 == thief.Character.Head then
			weld = w
		end
	end
	t.ok(weld, "the head weld")
	local server0 = weld.C0
	local a = seen(sim, owner, function()
		return weld.C0
	end)
	sim:Advance(WORLD.Carried.Period / 3)
	local b = seen(sim, owner, function()
		return weld.C0
	end)
	t.ok((a.Position - b.Position).Magnitude > 0.005, "it bobs (a looping tween of the weld)")
	t.eq(weld.C0, server0, "… on this client only")
	-- arms up under it (FisherAnimController treats StolenFish like HeldFish, no show-off)
	sim:Advance(0.6)
	t.eq(anim.GetPhase(thief), "Trophy", "the thief holds it with both arms (Trophy)")
	-- the alarm upgrade: «ВОР!» joins the plate, the head tag hides
	fake:defence({ HasAlarm = true })
	sim:Advance(WORLD.CheckEvery + 0.1)
	t.eq(plate.Plate.Thief.Visible, true, "«ВОР!» line over the fish's plate")
	t.eq(theft.Get(base).tag.Enabled, false, "… the head tag hidden (one billboard)")
	-- gone: C0 back, plate gone, arms down
	fake:drop(thief)
	sim:Advance(0.1)
	t.eq(theft.Get(base).carried, nil, "dropped")
	t.eq(#named(folder(sim, owner, "TheftWorld"), "FxCarriedPlate"), 0, "the plate is gone")
	t.eq(theft.Get(base).tag.Enabled, true, "the head tag again")
	sim:Advance(1)
	t.ok(anim.GetPhase(thief) ~= "Trophy", "arms down again")
	fake:alarm(nil)
	sim:Advance(WORLD.CheckEvery + 0.1)
	sim:AssertNoErrors({ warnings = true })
end

tests["HUD: a world word under the ShieldChip, the TheftBar or the TheftAlert fades (TankWorldController.hudRects)"] = function(
	t
)
	local sim = boot(t)
	local owner = addPlayer(sim, 1)
	local fake = Fake.new(sim, owner)
	local base = fake.base
	local world = client(sim, owner, "TankWorldController")
	local hud = owner.PlayerGui.HUD
	fake:mount({ "Perch", "Puffer", "Crucian" })
	local d3 = slotModel(base, 3).Display
	sim:Teleport(owner, (d3.CFrame * CFrame.new(0, -4, -9)).Position)
	sim:Advance(2.2, FRAME * 2)
	local tag = world.GetTag(base, 3)
	local point = tag.Parent.WorldPosition
	local view = seen(sim, owner, function()
		return sim.workspace.CurrentCamera.ViewportSize
	end)
	-- the camera that puts `point` at screen (x, y), 12 studs deep, looking at the display
	local look = CFrame.lookAt(Vector3.zero, d3.CFrame.LookVector)
	local function aimAt(x: number, y: number)
		seen(sim, owner, function()
			local camera = sim.workspace.CurrentCamera
			camera.CFrame = look.Rotation
			local dir = camera:ScreenPointToRay(x, y).Direction.Unit
			local along = look.LookVector:Dot(dir)
			camera.CFrame = CFrame.new(point - dir * (12 / along)) * look.Rotation
		end)
	end
	local function centre(gui: any): (number, number)
		local p, s = gui.AbsolutePosition, gui.AbsoluteSize
		return p.X + s.X / 2, p.Y + s.Y / 2
	end
	aimAt(view.X / 2, view.Y * 0.65)
	sim:Advance(DISPLAY.CheckEvery + DISPLAY.Clear.Show + 0.1)
	t.eq(world.IsFaded(tag), false, "clear of the HUD")
	for _, path in { "TheftBar", "TheftAlert" } do
		local widget = hud:FindFirstChild(path)
		t.ok(widget, `HUD.{path}`)
		widget.Visible = true
		for _, child in widget:GetChildren() do
			if child:IsA("GuiObject") and child.Name ~= "Compact" and child.Name ~= "DogChip" then
				child.Visible = true
			end
		end
		sim:Advance(0.05)
		local plate = widget:FindFirstChild("Plate")
		local x, y = centre(plate)
		aimAt(x, y)
		sim:Advance(DISPLAY.CheckEvery + DISPLAY.Clear.Fade + 0.1)
		t.ok(world.IsFaded(tag), `under HUD.{path}: faded`)
		widget.Visible = false
		aimAt(view.X / 2, view.Y * 0.65)
		sim:Advance(DISPLAY.CheckEvery + DISPLAY.Clear.Show + 0.1)
		t.eq(world.IsFaded(tag), false, `HUD.{path} gone: back`)
	end
	local chip = hud.Status.BaseBadge:FindFirstChild("ShieldChip")
	t.ok(chip, "Status.BaseBadge.ShieldChip")
	local before = #world.HudRects()
	chip.Visible = true
	sim:Advance(0.05)
	local rects = world.HudRects()
	t.eq(#rects, before + 1, "the ShieldChip is measured")
	local found = nil
	for _, r in rects do
		if math.abs((r.x1 - r.x0) - chip.AbsoluteSize.X) < 1 and math.abs((r.y1 - r.y0) - chip.AbsoluteSize.Y) < 1 then
			found = r
		end
	end
	t.ok(found, "… its own rect (where the status stack lays the badge out)")
	if found then
		aimAt((found.x0 + found.x1) / 2, (found.y0 + found.y1) / 2)
		sim:Advance(DISPLAY.CheckEvery + DISPLAY.Clear.Fade + 0.1)
		t.ok(world.IsFaded(tag), "under the ShieldChip: faded")
	end
	sim:AssertNoErrors({ warnings = true })
end

-- (RbxSim, needed by this file: two clients tween the local look of one server instance — the
-- lamp, a StolenFish weld — and each client's TweenService is its own: neither cancels the other)
tests["RbxSim: two clients tweening the same server instance do not cancel each other (per-context tween ownership)"] = function(
	t
)
	local sim = boot(t)
	local a = addPlayer(sim, 1)
	local b = addPlayer(sim, 2)
	local base = baseOf(sim, a)
	local lamp = base.Alarm.Lamp
	local env = sim:Env()
	local tweens = sim.game:GetService("TweenService")
	local function play(who: any, goal: number): any
		return seen(sim, who, function()
			local tween = tweens:Create(lamp, env.TweenInfo.new(0.5), { Transparency = goal })
			tween:Play()
			return tween
		end)
	end
	local ta = play(a, 0.9)
	local tb = play(b, 0.05)
	sim:Advance(0.6)
	t.eq(ta.PlaybackState, Enum.PlaybackState.Completed, "A's tween ran to its end")
	t.eq(tb.PlaybackState, Enum.PlaybackState.Completed, "B's too")
	t.near(
		seen(sim, a, function()
			return lamp.Transparency
		end),
		0.9,
		1e-3,
		"A sees its goal"
	)
	t.near(
		seen(sim, b, function()
			return lamp.Transparency
		end),
		0.05,
		1e-3,
		"B sees its own"
	)
	-- within ONE client the newer tween still cancels the older on the same property
	local first = play(a, 0.4)
	local second = play(a, 0.6)
	sim:Advance(0.05)
	t.eq(first.PlaybackState, Enum.PlaybackState.Cancelled, "same client: the older tween is cancelled")
	t.eq(second.PlaybackState, Enum.PlaybackState.Playing)
	sim:Advance(0.6)
	sim:AssertNoErrors({ warnings = true })
end

tests["idle: no frame connection and no check chain while nothing happens; activeJobs 0; a released base leaves nothing; client parts within the Theft reserve"] = function(
	t
)
	local sim = boot(t)
	local owner = addPlayer(sim, 1)
	local thief = addPlayer(sim, 2)
	local fake = Fake.new(sim, owner)
	local base = fake.base
	local theft = client(sim, owner, "TheftWorldController")
	local world = client(sim, owner, "TankWorldController")
	world.SetLife(false)
	fake:mount({ "Perch", "Puffer", "Swordfish" })
	sim:Teleport(owner, base.FishingSpot.Position + Vector3.new(0, 3, 0))
	sim:Advance(2.5, FRAME * 2)
	local frames0 = frameConnections(sim, owner)
	t.eq(theft.Stats().running, false, "idle: no check chain")
	sim:Advance(3)
	t.eq(frameConnections(sim, owner), frames0, "idle: no frame connection added")
	-- a whole theft with every defence, then all of it over
	fake:defence({ HasAlarm = true, HasDog = true, LockLevel = 1 })
	fake:showDog()
	inFront(sim, owner, base, 3)
	sim:Advance(2.2, FRAME * 2)
	fake:protect("shield", 30)
	fake:alarm("theft", thief)
	fake:steal(3, "hold", thief, 3)
	fake:dog("Chase", 20, 70, thief)
	sim:Advance(0.5)
	fake:carry(thief, "Swordfish")
	fake:steal(3, "carry", thief, 25)
	sim:Advance(0.1)
	-- the client's own parts (TheftWorld + the flying copy) within the Theft reserve
	local own = countClass(folder(sim, owner, "TheftWorld"), "BasePart")
	t.ok(own <= MapConfig.PartBudget.RuntimeReserve.Theft, `TheftWorld parts {own} ≤ Theft reserve`)
	sim:Advance(1)
	fake:drop(thief)
	fake:take(3, "stolen", thief)
	fake:alarm(nil)
	fake:protect(nil)
	fake:dog("Sleep", DefenceConfig.Dog.Rest.X, DefenceConfig.Dog.Rest.Z)
	sim:Advance(STEAL.StolenTime + DOME.Fade + 1.2)
	local ui = sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), owner)
	t.eq(ui.activeJobs(), 0, "no UiFx frame jobs left")
	t.eq(theft.Stats().running, false, "the check chain stopped")
	t.ok(frameConnections(sim, owner) <= frames0, "no frame connection left")
	local stats = theft.Stats()
	t.eq(
		stats.lamps + stats.sirens + stats.marks + stats.domes + stats.flags + stats.dogs + stats.carried,
		0,
		"nothing on"
	)
	-- released (the owner leaves): the defences cleared, the dog hidden
	fake:defence({ HasAlarm = false, HasDog = false, LockLevel = 0 })
	base.Dog:SetAttribute("Unlocked", false)
	sim:Advance(0.6)
	local left = folder(sim, owner, "TheftWorld")
	local extra = 0
	for _, d in left:GetDescendants() do
		if not (d:IsA("BasePart") and d.Name == "Anchor") then
			extra += 1
		end
	end
	t.eq(extra, 0, "TheftWorld: only its Anchor left")
	t.eq(#named(folder(sim, owner, "TankWorld"), "FxTankSteal"), 0, "no steal word")
	sim:AssertNoErrors({ warnings = true })
end

return tests
