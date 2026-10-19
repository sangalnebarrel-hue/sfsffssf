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
	Wave 1 B review (design §11.5), with the HUD:
	  steal_hold_thief_hud / steal_hold_thief_rule, steal_carry_thief_hud / steal_carry_thief_rule —
	      the THIEF'S OWN screen (the local player holds / carries) from his follow camera: rev. 2's
	      top TheftBar vs the §6.4 rule mocked here (HUD.Status hidden, the TheftBar in the bottom
	      band); `gui_render -v` prints a [band] line: the robbed display's screen rect
	      (TankWorldController.StealRect) and the HUD's rects (B1-01; phone, phone_small, tablet,
	      desktop);
	  steal_hold_spawn (B1-06), shield_dome_spawn (B1-02), alarm_lamp_far (B1-03 / B1-05),
	  tank_sign_gate (B1-04), dog_rest_side (B1-09), flag_label_neighbour (B1-10, base 2 is blue).
]]

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Vector2 = roblox.Vector2
local UDim2 = roblox.UDim2

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

-- The robbed display on screen (TankWorldController.StealRect, px, in the client's own camera)
-- next to the HUD's rects and the TheftBar plate — printed (gui_render -v) for the §6.4 / §6.9
-- band contract (design, DESIGN.md).
local function measure(h: any, index: number, label: string)
	local world = h:clientModule("TankWorldController")
	if not world then
		return
	end
	local rect, rects = h.sim:Run(function()
		return world.StealRect(h:base(), index), world.HudRects()
	end, h.player)
	local function fmt(r: any): string
		return if r then string.format("x %d..%d y %d..%d", r.x0, r.x1, r.y0, r.y1) else "-"
	end
	local parts = { `[band] {h.scenario}/{h.device} {label}: display Slot_{index} {fmt(rect)}` }
	for i, r in rects do
		table.insert(parts, `hud{i} {fmt(r)}`)
	end
	print(table.concat(parts, " · "))
end

-- The wave-0 TheftBar shown where wave 2 builds it (until TheftController drives it).
local function showBar(h: any)
	local bar = h:gui("HUD.TheftBar")
	if bar then
		bar.Visible = true
		h:atEnd(function()
			bar.Visible = false
		end)
	end
end

-- The §6.4 layout rule mocked until Wave 2 builds it (TheftController / HudController): while
-- HUD.Stealing is set, HUD.Status hides and the TheftBar docks in the bottom band (its top at
-- Steal.BandTop of the screen height), clear of the robbed display's band.
local function ruleLayout(h: any)
	local status = h:gui("HUD.Status")
	local bar = h:gui("HUD.TheftBar")
	if status then
		status.Visible = false
		h:atEnd(function()
			status.Visible = true
		end)
	end
	if bar then
		local anchor, position = bar.AnchorPoint, bar.Position
		bar.AnchorPoint = Vector2.new(0.5, 0)
		bar.Position = UDim2.fromScale(0.5, 0.74)
		h:atEnd(function()
			bar.AnchorPoint = anchor
			bar.Position = position
		end)
	end
end

-- The dog's brain (DogBrain): state, a base-local ground point → DogPos (world), the target.
local function dogTo(h: any, state: string, x: number, z: number, target: any?)
	local dog = h:base().Dog
	dog:SetAttribute("DogTarget", if target then target.UserId else nil)
	dog:SetAttribute("DogPos", at(h, x, 0, z))
	dog:SetAttribute("DogState", state)
end

local scenarios = {
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
			-- (aimed a little high: the thief's plate stays under the status stack, which fades it)
			court(h, { -15, 7, 33 }, { -19, 9.5, 62 }, 70)
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
		name = "tank_sign_join",
		desc = "Stage 3's tank_sign camera (the spawn pad) with only a join protection, after its greeting toast (Wave 3 ART-01): «+$/с · 🐠 6/6» keep their Stage 3 look; the protection row «🛡️ 3:55» is its own word (FxTankSignRow) over them — on phones it fades under the Wallet alone",
		world = true,
		standard = false,
		still = { 6.0 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, 4, 3.2, 40))
			court(h, { -12, 9.5, 33 }, { 0, 11, 78 }, 70)
			h:shield(240, nil, "join")
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
	{
		name = "steal_hold_thief_hud",
		desc = "THE THIEF'S OWN screen (HUD on) holding Slot_3 from the follow camera (12.5 studs behind, 20° down): where the robbed display, the lifted fish and «КРАДУТ!» land against the status stack and the wave-0 TheftBar (y 152) — the §6.4 band contract; the [band] line prints the rects",
		world = true,
		standard = false,
		still = { 0.7 },
		burst = false,
		run = function(h: any)
			h:money(1215, 459)
			court(h, { -16.5, 8.9, 71.5 }, { -28.2, 4.6, 71.5 }, 70)
			place(h, h.player, { -28.2, 3.2, 71.5 }, { -33.5, 0, 71.5 })
			h:advance(0.2)
			steal(h, 3, "hold", h.player, 4)
			alarm(h, h.player)
			h.player:SetAttribute("Stealing", "hold")
			h:atEnd(function()
				h.player:SetAttribute("Stealing", nil)
			end)
			showBar(h)
			h:advance(0.4)
			measure(h, 3, "hold")
		end,
	},
	{
		name = "steal_hold_thief_rule",
		desc = "The same hold with the §6.4 rule (mocked until Wave 2): HUD.Status hidden while stealing, the TheftBar in the bottom band — the robbed display, the lifted fish and «КРАДУТ!» in the clear",
		world = true,
		standard = false,
		still = { 0.7 },
		burst = false,
		run = function(h: any)
			h:money(1215, 459)
			court(h, { -16.5, 8.9, 71.5 }, { -28.2, 4.6, 71.5 }, 70)
			place(h, h.player, { -28.2, 3.2, 71.5 }, { -33.5, 0, 71.5 })
			h:advance(0.2)
			steal(h, 3, "hold", h.player, 4)
			alarm(h, h.player)
			h.player:SetAttribute("Stealing", "hold")
			h:atEnd(function()
				h.player:SetAttribute("Stealing", nil)
			end)
			showBar(h)
			ruleLayout(h)
			h:advance(0.4)
			measure(h, 3, "hold, rule")
		end,
	},
	{
		name = "steal_carry_thief_hud",
		desc = "THE THIEF'S OWN screen (HUD on) running out with the fish on his head (the owner bought the alarm): his plate «🥷 Фугу $52» + «ВОР!» fade under the status stack (TrackWord), the Highlight stays",
		world = true,
		standard = false,
		still = { 0.9 },
		burst = false,
		run = function(h: any)
			h:money(1215, 459)
			court(h, { -14, 8.9, 66.7 }, { -14, 4.6, 55 }, 70)
			h:defence({ alarm = true })
			place(h, h.player, { -14, 3.2, 55 }, { -14, 0, 40 })
			steal(h, 3, "hold", h.player, 4)
			alarm(h, h.player)
			h:advance(0.3)
			carry(h, h.player, "Puffer")
			steal(h, 3, "carry", h.player, 30)
			h.player:SetAttribute("Stealing", "carry")
			showBar(h)
			h:atEnd(function()
				h.player:SetAttribute("Stealing", nil)
				local fish = h.player.Character and h.player.Character:FindFirstChild("StolenFish")
				if fish then
					fish:Destroy()
				end
			end)
			h:advance(0.6)
		end,
	},
	{
		name = "steal_carry_thief_rule",
		desc = "The carry with the §6.4 rule (mocked): Status hidden, the TheftBar in the bottom band — the fish on his head, its plate «🥷 Фугу $52» + «ВОР!» in the clear",
		world = true,
		standard = false,
		still = { 0.9 },
		burst = false,
		run = function(h: any)
			h:money(1215, 459)
			court(h, { -14, 8.9, 66.7 }, { -14, 4.6, 55 }, 70)
			h:defence({ alarm = true })
			place(h, h.player, { -14, 3.2, 55 }, { -14, 0, 40 })
			steal(h, 3, "hold", h.player, 4)
			alarm(h, h.player)
			h:advance(0.3)
			carry(h, h.player, "Puffer")
			steal(h, 3, "carry", h.player, 30)
			h.player:SetAttribute("Stealing", "carry")
			showBar(h)
			ruleLayout(h)
			h:atEnd(function()
				h.player:SetAttribute("Stealing", nil)
				local fish = h.player.Character and h.player.Character:FindFirstChild("StolenFish")
				if fish then
					fish:Destroy()
				end
			end)
			h:advance(0.6)
		end,
	},
	{
		name = "steal_hold_spawn",
		desc = "The owner just landed on his spawn (ДОМОЙ) while Slot_5 is held: «КРАДУТ!» with its ring in front of the arcade lanterns (AlwaysOnTop), the lifted fish",
		world = true,
		standard = false,
		still = { 0.6 },
		burst = false,
		run = function(h: any)
			local thief = h:extraPlayer({ DisplayName = "Ника" })
			h.sim:Teleport(h.player, at(h, 0, 3.2, 40))
			court(h, { 0, 10.5, 28 }, { 0, 5, 80 }, 70)
			place(h, thief, { -27.4, 3.2, 82.2 }, { -33.5, 0, 82.5 })
			h:advance(0.2)
			steal(h, 5, "hold", thief, 4)
			alarm(h, thief)
		end,
	},
	{
		name = "shield_dome_spawn",
		desc = "The owner on his spawn pad (inside the dome) with his follow camera 12.5 studs behind (outside it): the dome goes faint (Dome.Near), not a full-screen layer; then from 8 studs outside the skin (the Near band) and from 30 studs out (a bubble)",
		world = true,
		standard = false,
		still = { 0.8, 1.8, 2.8 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, CFrame.lookAt(at(h, 0, 3.2, 36), at(h, 0, 3.2, 60)))
			h:money(1215, 459)
			court(h, { 0, 9.0, 24.3 }, { 0, 4.7, 36 }, 70)
			h:shield(52, nil, "shield")
			h:advance(0.6)
		end,
		during = function(h: any)
			h:advance(1.0)
			h.sim:Teleport(h.player, CFrame.lookAt(at(h, 0, 3.2, 22), at(h, 0, 3.2, 60)))
			if h.world then
				h.world:setCamera(at(h, 0, 9, 10.3), at(h, 0, 4.7, 22), 70)
			end
			h:advance(1.0)
			h.sim:Teleport(h.player, CFrame.lookAt(at(h, 0, 3.2, 0), at(h, 0, 3.2, 60)))
			if h.world then
				h.world:setCamera(at(h, -6, 12, -18), at(h, 0, 10, 60), 70)
			end
			h:advance(1.0)
		end,
	},
	{
		name = "alarm_lamp_far",
		desc = "A passer-by on the lane ~45 studs from the mast during a theft (alarm bought): the lamp blinks dark ↔ hot (frames half a period apart) and the siren's two pitched beams sweep the court",
		world = true,
		standard = false,
		still = { 0.1, 0.35, 0.6 },
		sheet = { from = 0, to = 1.2, fps = 10, roi = { { frac = { 0, 0, 1, 1 } } } },
		burst = false,
		run = function(h: any)
			local thief = h:extraPlayer({ DisplayName = "Ника" })
			h.sim:Teleport(h.player, at(h, 30, 3.2, 120))
			court(h, { 40, 8, -14 }, { 18, 10, 40 }, 70)
			h:defence({ alarm = true })
			place(h, thief, { -28.2, 3.2, 71.5 }, { -33.5, 0, 71.5 })
			steal(h, 3, "hold", thief, 4)
			alarm(h, thief)
			h:advance(0.3)
		end,
	},
	{
		name = "tank_sign_gate",
		desc = "The tank sign with its defences row «🛡️ 0:42 · 🔐1 · 🐕 · 🚨» ON TOP, seen from the gate (a thief walking in), then from the spawn follow camera: the row clear of the fountain statue",
		world = true,
		standard = false,
		still = { 0.6, 1.6 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, 4, 3.2, 40))
			court(h, { 0, 9, 16 }, { 0, 10, 75 }, 70)
			showDog(h)
			h:defence({ alarm = true, lock = 1 })
			h:shield(42, nil, "join")
			h:advance(1.2)
		end,
		during = function(h: any)
			h:advance(1.0)
			if h.world then
				h.world:setCamera(at(h, 0, 9, 24.3), at(h, 0, 4.7, 36), 70)
			end
			h:advance(1.0)
		end,
	},
	{
		name = "dog_rest_side",
		desc = "The shown dog asleep at Dog.Rest seen from the side (14 studs): its paws on the crosswalk paving (not sunk), «💤» over it",
		world = true,
		standard = false,
		still = { 0.4 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, 30, 3.2, 120))
			court(h, { 17, 5.5, 47 }, { 6, 1.6, 58 }, 60)
			showDog(h)
			h:advance(0.3)
		end,
	},
	{
		name = "flag_label_neighbour",
		desc = "The neighbour's (blue) flag with its join protection: «🛡️ 0:42» OVER the owner sign, on the sky — not on the blue cloth; then from ~140 studs",
		world = true,
		standard = false,
		still = { 0.6, 1.6 },
		burst = false,
		run = function(h: any)
			local neighbour = h:extraPlayer({ DisplayName = "Ника" })
			h.sim:Teleport(h.player, at(h, 30, 3.2, 120))
			court(h, nil, nil, nil)
			local tankRules = h.sim:Require(h.sim:Find("ReplicatedStorage.Shared.TankRules"))
			local other = h.sim.workspace.Bases:FindFirstChild(`Base_{neighbour:GetAttribute("BaseIndex")}`)
			h.otherBase = other
			if not other then
				h:warn("flag_label_neighbour: no base for the neighbour")
				return
			end
			other:SetAttribute("ProtectUntil", tankRules.AttrTime(h.sim.workspace:GetServerTimeNow() + 42))
			other:SetAttribute("ProtectKind", "join")
			h:atEnd(function()
				other:SetAttribute("ProtectUntil", nil)
				other:SetAttribute("ProtectKind", nil)
			end)
			if h.world then
				h.world:setCamera(at(h, -2, 50, 6, other), at(h, -20, 60, 31, other), 60)
			end
			h:advance(0.6)
		end,
		during = function(h: any)
			h:advance(1.0)
			local other = h.otherBase
			if other and h.world then
				h.world:setCamera(at(h, 60, 14, -70, other), at(h, -20, 46, 31, other), 70)
			end
			h:advance(1.0)
		end,
	},
}

-- Wave 2 C: the thief's own HUD over these courts (gui_scenarios_theft_ui.luau: thief_*), drawn
-- with the same helpers.
local helpers = {
	at = at,
	court = court,
	place = place,
	steal = steal,
	carry = carry,
	alarm = alarm,
	measure = measure,
	showDog = showDog,
	dogTo = dogTo,
	serverLook = serverLook,
}
for _, s in require("./gui_scenarios_theft_ui")(helpers) do
	table.insert(scenarios, s)
end

return scenarios
