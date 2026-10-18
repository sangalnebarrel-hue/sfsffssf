--[[
	gui_scenarios_theft_world.luau — stage 4 world views for the GUI previews (gui_dump.luau loads
	them after the stage 3 files; same scenario format, none in the standard set): what
	TheftWorldController and TankWorldController draw on this client during a theft — the
	display fish lifted in a hold with «КРАДУТ!», the carry (the fish on the thief's head, its
	plate, the dog chasing), the alarm lamp and the siren, the thief's Highlight with «ВОР!», the
	shield dome, the protection flag label, the dog at its court spot by the kennel, the tank
	sign's defences row and the pier word «🚨 КРАДУТ!» (docs/stage4_design.md §5.1–5.4, §7.9).

	The stage 4 services are stubs in the preview sims (gui_dump STUBBED_SERVICES): the scenarios
	write what StealService / DefenceService / DogBrain would — the slot steal channel
	(StealBy, StealEnd, StealPhase LAST), the base's AlarmState / Thief / HasAlarm / HasDog /
	ProtectUntil, the dog's DogState / DogPos / DogTarget, the thief's Slowed and his StolenFish
	(the real Lib/HeldRig) — on base 1 (the player's own: the viewer is its owner) with a second
	player as the thief (h:extraPlayer; he leaves at the scenario's end, h:atEnd puts base 1
	back). The court views use their own camera (world capture setCamera, base-local points)
	and freeze the display fish's life like gui_scenarios_tank.luau; the parts the services
	change (the lamp, the shown dog and kennel, the displays' light bars and glass) are drawn
	from the sim (addLive). The world capture walks the client's Workspace.TheftWorld (the dome
	— ForceField, rim-lit by gui/solids.py —, the siren's SpotLights as their lit ground patch,
	the Highlight as a filled + ringed silhouette, the words).

	  gui_render.py --scenario steal_hold_follow,steal_carry_dog,alarm_lamp_court,\
	      alarm_siren_highlight,shield_dome_gate,dog_court_rest,tank_sign_defences \
	      --devices phone --no-hud --out DIR      (the world views; HUD-less)
	  gui_render.py --scenario owner_pier_alert,owner_pier_alert_wait --devices phone,desktop \
	      --out DIR                               (the fishing camera with the HUD)
]]

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

-- The court's six fish (gui_scenarios_tank.luau's SIX).
local SIX = {
	{ Id = "Crucian", Age = 40 },
	{ Id = "Perch", Mutation = "Gold", Age = 120 },
	{ Id = "Puffer", Age = 310 },
	{ Id = "Swordfish", Mutation = "Neon", Age = 15 },
	{ Id = "SharkPup", Age = 200 },
	{ Id = "DragonFish", Mutation = "Rainbow", Age = 80 },
}
local STEAL_FIELDS = { "StealBy", "StealEnd", "StealPhase" } -- (StealPhase written last)
local BASE_FIELDS = {
	"AlarmState",
	"Thief",
	"HasAlarm",
	"HasDog",
	"LockLevel",
	"HoldTime",
	"ProtectUntil",
	"ProtectKind",
}
local DOG_FIELDS = { "DogState", "DogPos", "DogTarget" }

-- A base-local point (y = 0 = GroundTop) of `base` (default the player's) in world coordinates.
local function at(h: any, x: number, y: number, z: number, base: any?): any
	return ((base or h:base()):GetPivot() * CFrame.new(x, y, z)).Position
end

-- What TankService writes on the displays after `h:tank(list)` (gui_scenarios_tank serverLook):
-- the label, the light bar, the occupied glass; drawn from the sim.
local function serverLook(h: any)
	local base = h:base()
	local tankConfig = h:config("TankConfig")
	local ui = h:config("UIConfig")
	local rules = h.sim:Require(h.sim:Find("ReplicatedStorage.Shared.FishingRules"))
	for index = 1, tankConfig.MaxSlots do
		local slot = base.Tank.Slots:FindFirstChild(`Slot_{index}`)
		if not slot then
			continue
		end
		local label = slot.Pedestal.LabelGui.Label
		local bar = slot.LightBar
		local light = bar:FindFirstChildOfClass("SurfaceLight")
		local fishId = slot:GetAttribute("FishId")
		if index > tankConfig.StartSlots then
			label.Text = tankConfig.Texts.SlotLocked
			label.TextColor3 = ui.Palette.Slate.Top
			bar.Material = roblox.Enum.Material.SmoothPlastic
			bar.Color = ui.Palette.Slate.Bottom
			if light then
				light.Enabled = false
			end
		elseif typeof(fishId) == "string" then
			local def = rules.GetFish(fishId)
			local rarity = slot:GetAttribute("Rarity")
			local style = ui.Rarity[rarity]
			local flat = rules.GetRarity(rarity)
			label.Text = if def then def.Name else fishId
			label.TextColor3 = if flat then flat.Color else label.TextColor3
			bar.Color = if style and style.Rainbow then ui.Rainbow[6] elseif style then style.Bottom else bar.Color
			slot.Display.Transparency = tankConfig.Display.GlassOccupied
		else
			label.Text = tankConfig.Texts.SlotEmpty
		end
		if h.world then
			h.world:addLive(bar)
			h.world:addLive(slot.Display)
		end
	end
end

local function slotOf(h: any, index: number): any
	return h:base().Tank.Slots:FindFirstChild(`Slot_{index}`)
end

-- The slot steal channel like StealService (TankService:SetSteal): StealBy, StealEnd, then
-- StealPhase LAST; phase nil = released (StealPhase cleared last).
local function steal(h: any, index: number, phase: string?, thief: any?, left: number?)
	local slot = slotOf(h, index)
	local tankRules = h.sim:Require(h.sim:Find("ReplicatedStorage.Shared.TankRules"))
	if phase and thief then
		slot:SetAttribute("StealBy", thief.UserId)
		slot:SetAttribute("StealEnd", tankRules.AttrTime(h.sim.workspace:GetServerTimeNow() + (left or 4)))
		slot:SetAttribute("StealPhase", phase)
	else
		for _, name in STEAL_FIELDS do
			slot:SetAttribute(name, nil)
		end
	end
end

-- The court, written and painted, the life frozen, the own camera at base-local eye → target;
-- `h:atEnd` clears what these scenarios add to base 1 (the steal channel, the base and dog
-- attributes, a shown dog moved back to its template pivot, the lamp drawn from the sim).
local function court(h: any, eye: { number }?, target: { number }?, fov: number?, list: { any }?)
	local base = h:base()
	local pup = base.Dog:FindFirstChild("Pup")
	local pupPivot = pup and pup:GetPivot()
	h:atEnd(function()
		for index = 1, 6 do
			local slot = slotOf(h, index)
			if slot then
				for _, name in STEAL_FIELDS do
					slot:SetAttribute(name, nil)
				end
			end
		end
		for _, name in BASE_FIELDS do
			base:SetAttribute(name, nil)
		end
		for _, name in DOG_FIELDS do
			base.Dog:SetAttribute(name, nil)
		end
		h:defence({ dog = false, alarm = false, lock = 0 })
		base:SetAttribute("HoldTime", nil)
		if pup and pupPivot then
			pup:PivotTo(pupPivot)
		end
	end)
	h:tank(list or SIX)
	serverLook(h)
	local world = h:clientModule("TankWorldController")
	if world and world.SetLife then
		world.SetLife(false)
	end
	if h.world then
		local lamp = base:FindFirstChild("Alarm") and base.Alarm:FindFirstChild("Lamp")
		if lamp then
			h.world:addLive(lamp)
		end
		if eye and target then
			h.world:setCamera(at(h, eye[1], eye[2], eye[3]), at(h, target[1], target[2], target[3]), fov)
		end
	end
	h:advance(2.2, 1 / 15)
end

-- The dog shown like DefenceService (h:defence) and pivoted to its court spot Dog.Rest (its
-- template height, facing the gate); its parts and the kennel's drawn from the sim.
local function showDog(h: any)
	h:defence({ dog = true })
	local base = h:base()
	local dog = base.Dog
	local rest = h:config("DefenceConfig").Dog.Rest
	local pivot = base:GetPivot()
	local height = (pivot:Inverse() * dog.Pup:GetPivot()).Position.Y
	dog.Pup:PivotTo(pivot * CFrame.new(rest.X, height, rest.Z))
	if h.world then
		for _, d in dog:GetDescendants() do
			if d:IsA("BasePart") then
				h.world:addLive(d)
			end
		end
	end
	h:advance(0.1)
end

-- The thief (a second player) at a base-local point of base 1, facing another one.
local function place(h: any, who: any, from: { number }, toward: { number })
	local p = at(h, from[1], from[2], from[3])
	local q = at(h, toward[1], from[2], toward[3])
	h.sim:Teleport(who, CFrame.lookAt(p, q))
end

-- The thief's StolenFish (the real Lib/HeldRig on the server, like StealService at the carry).
local function carry(h: any, thief: any, fishId: string): any?
	local heldRig = h.sim:Require(h.sim:Find("ServerScriptService.Lib.HeldRig"))
	local fish = h:theftFish(fishId)
	local ok, model = pcall(heldRig.Build, thief.Character, {
		Id = fish.FishId,
		Rarity = fish.Rarity,
		Kg = fish.Kg,
		Value = fish.Value,
		Income = fish.Income,
	}, "StolenFish")
	if not ok or not model then
		h:warn(`carry: HeldRig.Build failed: {model}`)
		return nil
	end
	return model
end

local function alarm(h: any, thief: any, state: string?)
	local base = h:base()
	base:SetAttribute("Thief", thief.UserId)
	base:SetAttribute("AlarmState", state or "theft")
end

-- The dog's brain (DogBrain): state, a base-local ground point → DogPos (world), the target.
local function dogTo(h: any, state: string, x: number, z: number, target: any?)
	local dog = h:base().Dog
	dog:SetAttribute("DogTarget", if target then target.UserId else nil)
	dog:SetAttribute("DogPos", at(h, x, 0, z))
	dog:SetAttribute("DogState", state)
end

return {
	{
		name = "steal_hold_follow",
		desc = "The thief's follow camera in the west aisle during a hold on Slot_3 (the Puffer): the fish lifted under the glass top and tilted to the aisle, struggling, the red pulse at the light bar, «КРАДУТ!» with its ring in front of the glass",
		world = true,
		standard = false,
		still = { 0.15, 0.7 },
		sheet = { from = 0, to = 0.9, fps = 10, roi = { { frac = { 0.15, 0.05, 0.85, 0.95 } } } },
		burst = false,
		run = function(h: any)
			local thief = h:extraPlayer({ DisplayName = "Ника" })
			h.sim:Teleport(h.player, at(h, 0, 3.2, 40)) -- (the owner at the spawn, out of frame)
			-- (behind and a little above the thief, level enough that «КРАДУТ!» stays below the
			-- phone's status stack: under it the word fades — TankWorldController's HUD rule)
			court(h, { -16.5, 7.6, 75.5 }, { -33.5, 10.2, 71.5 }, 70)
			place(h, thief, { -27.4, 3.2, 72.2 }, { -33.5, 0, 71.5 })
			h:advance(0.2)
			steal(h, 3, "hold", thief, 4)
		end,
	},
	{
		name = "steal_carry_dog",
		desc = "The carry from the court: the Puffer leaves the front glass of Slot_3 on an arc to the thief's head (his StolenFish, arms up, «🥷 Фугу $X» and «ВОР!»), the alarm lamp and the siren beams, the Highlight, the dog running from its spot after the slowed thief («ГАВ!», dust)",
		world = true,
		standard = false,
		still = { 0.2, 1.4 },
		sheet = { from = 0, to = 2.0, fps = 6, roi = { { frac = { 0, 0, 1, 1 } } } },
		burst = false,
		run = function(h: any)
			local thief = h:extraPlayer({ DisplayName = "Ника" })
			h.sim:Teleport(h.player, at(h, 0, 3.2, 40))
			court(h, { -15, 9, 38 }, { -19, 4, 62 }, 70)
			h:defence({ alarm = true })
			showDog(h)
			place(h, thief, { -27.4, 3.2, 72.2 }, { -33.5, 0, 71.5 })
			steal(h, 3, "hold", thief, 4)
			alarm(h, thief)
			h:advance(0.6)
			-- the hold is done: the carry (StealService: the StolenFish on the head, the slot's
			-- phase "carry" — the display fish flies to it), the dog wakes
			carry(h, thief, "Puffer")
			steal(h, 3, "carry", thief, 30)
			thief:SetAttribute("Stealing", "carry")
			dogTo(h, "Alert", 6, 58)
		end,
		during = function(h: any)
			local thief = h.extras and h.extras[1]
			if not thief then
				return
			end
			h:advance(0.4)
			-- the thief runs for the gate, the dog after him; he is slowed at 1.0 s
			local path = { { -24, 68 }, { -20, 64 }, { -16, 60 }, { -12, 56 }, { -9, 52 }, { -6, 48 } }
			for i, p in path do
				place(h, thief, { p[1], 3.2, p[2] }, { p[1] + 3, 0, p[2] - 4 })
				dogTo(h, "Chase", p[1] + 4 + (6 - i) * 1.5, p[2] + 6, thief)
				if i == 3 then
					thief:SetAttribute("Slowed", true)
				end
				h:advance(0.25)
			end
		end,
	},
	{
		name = "alarm_lamp_court",
		desc = "The owner in his court while a thief holds a display (no alarm bought: the lamp only): the signal mast's lamp by the gate blinks red (Neon + glow, 2 Hz) — the frames half a period apart",
		world = true,
		standard = false,
		still = { 0.0, 0.25 },
		sheet = { from = 0, to = 1.0, fps = 8, roi = { { frac = { 0, 0, 1, 1 } } } },
		burst = false,
		run = function(h: any)
			local thief = h:extraPlayer({ DisplayName = "Ника" })
			h.sim:Teleport(h.player, at(h, -2, 3.2, 12))
			court(h, { 4, 8, 50 }, { 20, 14.5, 31 }, 70)
			place(h, thief, { -27.4, 3.2, 72.2 }, { -33.5, 0, 71.5 })
			steal(h, 3, "hold", thief, 4)
			alarm(h, thief)
			h:advance(0.5)
		end,
	},
	{
		name = "alarm_siren_highlight",
		desc = "The owner's view of the thief in his court with an alarm: the Highlight (Berry fill, outline, AlwaysOnTop for the owner) and «ВОР!» over the head, the lamp, the siren's two red beams sweeping the ground",
		world = true,
		standard = false,
		still = { 0.1, 0.4 },
		sheet = { from = 0, to = 0.6, fps = 10, roi = { { frac = { 0, 0, 1, 1 } } } },
		burst = false,
		run = function(h: any)
			local thief = h:extraPlayer({ DisplayName = "Ника" })
			h.sim:Teleport(h.player, at(h, -6, 3.2, 14))
			court(h, { -5, 10, 27 }, { 10, 8.5, 44 }, 70)
			h:defence({ alarm = true })
			place(h, thief, { 8, 3.2, 46 }, { 8, 0, 30 })
			alarm(h, thief)
			h:advance(0.6)
		end,
	},
	{
		name = "shield_dome_gate",
		desc = "A shield dome over base 1's court seen from outside its gate (ForceField, faded in), the flag label «🛡️ 4:12»; then base 2 (join-protected) from its gate: no dome, only its flag label «🛡️ 0:42»; then the camera inside base 1's dome (no full-screen tint)",
		world = true,
		standard = false,
		still = { 0.6, 1.6, 2.6 },
		burst = false,
		run = function(h: any)
			local neighbour = h:extraPlayer({ DisplayName = "Ника" })
			h.sim:Teleport(h.player, at(h, -4, 3.2, -6))
			court(h, { -34, 26, -40 }, { 0, 14, 70 }, 70)
			h:shield(252, nil, "shield")
			local tankRules = h.sim:Require(h.sim:Find("ReplicatedStorage.Shared.TankRules"))
			local other = h.sim.workspace.Bases:FindFirstChild(`Base_{neighbour:GetAttribute("BaseIndex")}`)
			h.otherBase = other
			if other then
				other:SetAttribute("ProtectUntil", tankRules.AttrTime(h.sim.workspace:GetServerTimeNow() + 42))
				other:SetAttribute("ProtectKind", "join")
				h:atEnd(function()
					other:SetAttribute("ProtectUntil", nil)
					other:SetAttribute("ProtectKind", nil)
				end)
			else
				h:warn("shield_dome_gate: no base for the neighbour")
			end
			h:advance(0.6)
		end,
		during = function(h: any)
			h:advance(1.0)
			local other = h.otherBase
			if other and h.world then
				h.world:setCamera(at(h, -34, 26, -40, other), at(h, 0, 14, 70, other), 70)
			end
			h:advance(1.0)
			if h.world then
				h.world:setCamera(at(h, -10, 9, 60), at(h, 10, 7, 100), 70)
			end
			h:advance(1.0)
		end,
	},
	{
		name = "dog_court_rest",
		desc = "The shown dog asleep at its court spot (Dog.Rest, facing the gate) seen through the gate; then its kennel in the front corner of the court",
		world = true,
		standard = false,
		still = { 0.4, 1.4 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, -2, 3.2, 12))
			court(h, { 1, 7, 12 }, { 6, 1.5, 58 }, 70)
			showDog(h)
			h:advance(0.6)
		end,
		during = function(h: any)
			h:advance(1.0)
			if h.world then
				h.world:setCamera(at(h, 20, 8, 42), at(h, 34, 2.5, 26), 70)
			end
			h:advance(0.6)
		end,
	},
	{
		name = "tank_sign_defences",
		desc = "The big tank's sign from the spawn with the base's defences: «🔐1 · 🐕 · 🚨» and «🛡️ 0:42» under «+$/с · 🐠 6/6» (a join protection: no dome)",
		world = true,
		standard = false,
		still = { 0.6 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, 4, 3.2, 40))
			court(h, { -4, 13, 50 }, { 0, 11, 80 }, 70)
			showDog(h)
			h:defence({ alarm = true, lock = 1 })
			h:shield(42, nil, "join")
			h:advance(1.2)
		end,
	},
	{
		name = "owner_pier_alert",
		desc = "The owner fishing at his own spot (the fishing camera) while his base is robbed: the pier word «🚨 КРАДУТ!» pulsing over the bucket, clear of the fisher",
		world = true,
		standard = false,
		still = { 0.6 },
		burst = false,
		run = function(h: any)
			h:tank({ SIX[1], SIX[2], SIX[3], SIX[4] })
			h:standAtSpot()
			h:equipRod()
			h:poseLikeBackdrop()
			h:advance(0.6)
			local base = h:base()
			h:atEnd(function()
				base:SetAttribute("AlarmState", nil)
				base:SetAttribute("Thief", nil)
			end)
			h:alert({ Phase = "hold", Name = "Ника" })
			h:advance(1.2)
		end,
	},
	{
		name = "owner_pier_alert_wait",
		desc = "Waiting on the water (the real cast) while the base is robbed: «🚨 КРАДУТ!» stays clear of the bobber and the fisher",
		server = true,
		world = true,
		standard = false,
		still = { 0.4, 2.0 },
		burst = false,
		run = function(h: any)
			h:forceFish({ Id = "Crucian" })
			h:tank({ SIX[1], SIX[2], SIX[3], SIX[4] })
			h:standAtSpot()
			h:equipRod()
			h:poseLikeBackdrop()
			local base = h:base()
			h:atEnd(function()
				base:SetAttribute("AlarmState", nil)
				base:SetAttribute("Thief", nil)
			end)
			h:alert({ Phase = "hold", Name = "Ника" })
			h:advance(0.4)
			h:click("HUD.Fishing.ActionArea.ActionButton")
			h:advance(1.6)
		end,
	},
}
