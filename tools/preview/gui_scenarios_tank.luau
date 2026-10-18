--[[
	gui_scenarios_tank.luau — stage 3 world views for the GUI previews (gui_dump.luau loads them
	after gui_scenarios.luau; same scenario format, none in the standard set): what
	TankWorldController draws on this client — the display fish in the court, the words over the
	displays and the big tank, the pier word over the bucket by the fishing spot, the slot FX —
	seen from the cameras of design §7.8.

	The stage 3 services are stubs in the preview sims: `h:tank` writes the display / tank /
	player attributes like TankService, and serverLook() below paints the displays like
	TankService does (design §5.2: the label's fish name in its rarity colour / «🔒 Закрыто»,
	the LightBar in the rarity colour / a dim Slate bar with its light off, occupied glass at
	Display.GlassOccupied); those parts are drawn from the sim (world capture addLive). The
	court views use their own camera (world capture setCamera, base-local points of base 1) and
	freeze the display fish's life (TankWorldController.SetLife(false): RbxSim does not carry
	welded parts with a tweened Body).

	  gui_render.py --scenario tank_court,tank_aisle,tank_display,tank_rainbow,tank_sign \
	      --devices phone --no-hud --out DIR      (the world views; HUD-less)
	  gui_render.py --scenario tank_aisle_walk,tank_front,tank_front_east,tank_court_low \
	      --devices phone,desktop --out DIR       (the follow / eye-level cameras: tag size, the
	                                               light bar behind the value, the lock words)
	  gui_render.py --scenario pier_tank_word,pier_tank_wait,pier_tank_arrival \
	      --devices phone,desktop --out DIR       (the fishing camera with the HUD)
	  gui_render.py --scenario market_word,tank_events --devices phone --no-hud --out DIR
]]

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame
local Enum = roblox.Enum

-- The six species, a mix of mutations and ages (one МАКС): the court's 6 open displays.
local SIX = {
	{ Id = "Crucian", Age = 40 },
	{ Id = "Perch", Mutation = "Gold", Age = 120 },
	{ Id = "Puffer", Age = 310 },
	{ Id = "Swordfish", Mutation = "Neon", Age = 15 },
	{ Id = "SharkPup", Age = 200 },
	{ Id = "DragonFish", Mutation = "Rainbow", Age = 80 },
}

-- A base-local point of the player's base (y = 0 = GroundTop) in world coordinates.
local function at(h: any, x: number, y: number, z: number): any
	return (h:base():GetPivot() * CFrame.new(x, y, z)).Position
end

-- What TankService writes on the displays (design §5.2) after `h:tank(list)`; every LightBar
-- and Display is then drawn from the sim (the backdrop has them at rest).
local function serverLook(h: any, slots: number?)
	local base = h:base()
	local tankConfig = h:config("TankConfig")
	local ui = h:config("UIConfig")
	local rules = h.sim:Require(h.sim:Find("ReplicatedStorage.Shared.FishingRules"))
	local open = slots or tankConfig.StartSlots
	for index = 1, tankConfig.MaxSlots do
		local slot = base.Tank.Slots:FindFirstChild(`Slot_{index}`)
		if not slot then
			continue
		end
		local label = slot.Pedestal.LabelGui.Label
		local bar = slot.LightBar
		local light = bar:FindFirstChildOfClass("SurfaceLight")
		local display = slot.Display
		local fishId = slot:GetAttribute("FishId")
		if index > open then
			label.Text = tankConfig.Texts.SlotLocked
			label.TextColor3 = ui.Palette.Slate.Top
			bar.Material = Enum.Material.SmoothPlastic
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
			display.Transparency = tankConfig.Display.GlassOccupied
		else
			label.Text = tankConfig.Texts.SlotEmpty
		end
		if h.world then
			h.world:addLive(bar)
			h.world:addLive(display)
		end
	end
end

-- The court with the six fish (+ the locked rows): the tank written, painted, the life frozen,
-- the own camera at base-local eye → target; the fish built (≤ 3 per 0.5 s check).
local function court(h: any, eye: { number }, target: { number }, fov: number?, list: { any }?)
	h:tank(list or SIX)
	serverLook(h)
	local world = h:clientModule("TankWorldController")
	if world and world.SetLife then
		world.SetLife(false)
	end
	if h.world then
		h.world:setCamera(at(h, eye[1], eye[2], eye[3]), at(h, target[1], target[2], target[3]), fov)
	end
	h:advance(2.2, 1 / 15)
end

return {
	{
		name = "tank_court",
		desc = "The court of base 1 from the gate side: six fish in their displays (rows 1–3 of both arcades), the locked rows 4–6 dim with «🔒 Закрыто», the tags «+$X/с · $Y», the big tank's sign «+$/с · 🐠 6/6»",
		world = true,
		standard = false,
		still = { 0.4 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, -6, 3.2, 52))
			court(h, { -12, 15.5, 44 }, { 4, 7, 94 }, 70)
		end,
	},
	{
		name = "tank_aisle",
		desc = "The follow camera in the west aisle (under the arcade ceiling): the tags readable over the displays, the lanterns",
		world = true,
		standard = false,
		still = { 0.4 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, -26.5, 4, 62))
			court(h, { -24.5, 9.6, 50 }, { -30.5, 8.2, 76 }, 70)
		end,
	},
	{
		name = "tank_locked",
		desc = "The far end of the west aisle: the last open display (Slot_5) and the locked rows 4–6 — a dim Slate light bar, no light, «🔒 Закрыто»",
		world = true,
		standard = false,
		still = { 0.4 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, -26.5, 4, 80))
			court(h, { -24.8, 9.6, 78 }, { -32, 7.5, 104 }, 70)
		end,
	},
	{
		name = "tank_aisle_walk",
		desc = "Walking down the west aisle (character mid-aisle, the follow camera behind and above it): the next displays' tags readable, the farther ones hidden (TagShow) instead of piling up, the locked rows' «🔒 Закрыто» far down",
		world = true,
		standard = false,
		still = { 0.4 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, -26.5, 3.2, 66))
			court(h, { -25.5, 10.5, 54 }, { -27.5, 6.5, 80 }, 70)
		end,
	},
	{
		name = "tank_front",
		desc = "A kid in the west aisle facing Slot_3 (the follow camera ≈ 12 studs behind): the tag's size on a phone, its value line over the light bar",
		world = true,
		standard = false,
		still = { 0.4 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, -26.0, 3.2, 71.5))
			court(h, { -15.5, 10.5, 71.5 }, { -33.5, 7.5, 71.5 }, 70)
		end,
	},
	{
		name = "tank_front_east",
		desc = "A kid in the east aisle facing Slot_6 (the Rainbow DragonFish), the camera ≈ 12 behind: a tag over a coloured light bar",
		world = true,
		standard = false,
		still = { 0.4 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, 26.0, 3.2, 82.5))
			court(h, { 15.5, 10.5, 82.5 }, { 33.5, 7.5, 82.5 }, 70)
		end,
	},
	{
		name = "tank_court_low",
		desc = "Walking into the court from the gate at eye height: the tank sign, the locked rows' «🔒 Закрыто» (LockRange), no far tags",
		world = true,
		standard = false,
		still = { 0.4 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, 0, 3.2, 52))
			court(h, { 0, 9.5, 40 }, { 0, 7, 90 }, 70)
		end,
	},
	{
		name = "tank_display",
		desc = "A display close-up from the aisle: the Puffer on Slot_3 (at «МАКС») centred in the glass, its tag over the light bar, the pedestal label in the rarity colour",
		world = true,
		standard = false,
		still = { 0.4 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, -20, 3.2, 62))
			court(h, { -22.5, 9.4, 64 }, { -33.5, 8.9, 71.5 }, 55)
		end,
	},
	{
		name = "tank_rainbow",
		desc = "The Rainbow DragonFish close-up (Slot_6, the east arcade): the biggest fish still inside its cube, the rainbow parts",
		world = true,
		standard = false,
		still = { 0.4 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, 20, 3.2, 92))
			court(h, { 24.8, 9.8, 91 }, { 33.5, 10.2, 82.5 }, 55)
		end,
	},
	{
		name = "tank_sign",
		desc = "The big tank from the spawn pad: its sign «+$/с» / «🐠 6/6» over the «АКВАРИУМ» plaque",
		world = true,
		standard = false,
		still = { 0.4 },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, 4, 3.2, 40))
			court(h, { -12, 9.5, 33 }, { 0, 11, 78 }, 70)
		end,
	},
	{
		name = "tank_events",
		desc = "Slot events in the west aisle: a catch lands on Slot_3 («in»: the fish grows, splash + rarity sparkles over the glass, the light bar flashes, the tag pops), Slot_1 is sold («+$45» rises, gold sparkles, the fish shrinks away), Slot_5 is replaced («swap»)",
		world = true,
		standard = false,
		still = { 0.2, 0.6 },
		sheet = { from = 0, to = 1.6, fps = 8, roi = { { frac = { 0, 0, 1, 1 } } } },
		burst = false,
		run = function(h: any)
			h.sim:Teleport(h.player, at(h, -20, 3.2, 58))
			court(h, { -22, 10.5, 52 }, { -32, 8.4, 76 }, 70, {
				{ Id = "Crucian", Slot = 1 },
				{ Id = "Swordfish", Mutation = "Neon", Slot = 4 },
				{ Id = "SharkPup", Slot = 5 },
			})
		end,
		during = function(h: any)
			local puffer = { Id = "Puffer", Mutation = "Gold", Slot = 3 }
			local sword = { Id = "Swordfish", Mutation = "Neon", Slot = 4 }
			h:tank(
				{ { Id = "Crucian", Slot = 1 }, puffer, sword, { Id = "SharkPup", Slot = 5 } },
				{ event = "in", at = 3 }
			)
			serverLook(h)
			h:advance(0.05)
			h:tank({ puffer, sword, { Id = "SharkPup", Slot = 5 } }, { event = "sold", at = 1, price = 45 })
			serverLook(h)
			h:advance(0.05)
			h:tank({ puffer, sword, { Id = "DragonFish", Slot = 5 } }, { event = "swap", at = 5, price = 210 })
			serverLook(h)
			h:advance(1.6)
		end,
	},
	{
		name = "pier_tank_word",
		desc = "The fishing camera at the own spot, rod in hand, idle: the pier word «🐠 4/6 · +$X/с» over the bucket, clear of the fisher",
		world = true,
		standard = false,
		still = { 0.6 },
		burst = false,
		run = function(h: any)
			h:tank({ SIX[1], SIX[2], SIX[3], SIX[4] })
			h:standAtSpot()
			h:equipRod()
			h:poseLikeBackdrop()
			h:advance(1.0)
		end,
	},
	{
		name = "pier_tank_wait",
		desc = "Waiting on the water (the real cast, the camera shifted right): the pier word stays clear of the bobber and the fisher",
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
			h:advance(0.4)
			h:click("HUD.Fishing.ActionArea.ActionButton")
			h:advance(1.6)
		end,
	},
	{
		name = "pier_tank_arrival",
		desc = "A catch lands in the tank (CounterHold released): a splash at the bucket rim, the word «punches» to «🐠 5/6», then an income pop «+$X» rises over it",
		world = true,
		standard = false,
		still = { 0.15, 1.2 },
		sheet = { from = 0, to = 1.4, fps = 10, roi = { { frac = { 0.35, 0.2, 0.95, 0.85 } } } },
		burst = false,
		run = function(h: any)
			h:tank({ SIX[1], SIX[2], SIX[3], SIX[4] })
			h:standAtSpot()
			h:equipRod()
			h:poseLikeBackdrop()
			h:advance(0.6)
			-- (the arrival of a catch once its card has closed; TankEvent "Stored" plays the same
			-- splash without the card — FishingController would open one for a "Caught")
			h:tank({ SIX[1], SIX[2], SIX[3], SIX[4], { Id = "Swordfish", Slot = 5 } }, { event = "in", at = 5 })
			h:tankEvent("Stored", { Result = "stored", Slot = 5, Uid = "f5", Count = 5, Slots = 6 })
		end,
		during = function(h: any)
			-- (the income pop comes on the 5 s chain: nudge it into the window)
			h:advance(0.6)
		end,
	},
	{
		name = "market_word",
		desc = "The hub fish market from the plaza: «РЫНОК +50%!» over the «РЫБНЫЙ РЫНОК» sign",
		world = true,
		standard = false,
		still = { 0.4 },
		burst = false,
		run = function(h: any)
			local market = h.sim:Find("Workspace.Map.Hub.FishMarket.Sign")
			if not market or not h.world then
				h:warn("market_word: no FishMarket.Sign")
				return
			end
			local sign = market.Position
			local out = Vector3.new(-sign.X, 0, -sign.Z).Unit -- towards the tower (the plaza)
			local eye = Vector3.new(sign.X, 0, sign.Z) + out * 40 + Vector3.new(0, 13, 0)
			h.sim:Teleport(h.player, Vector3.new(sign.X, 0, sign.Z) + out * 30 + Vector3.new(0, 8, 0))
			h.world:setCamera(eye, sign + Vector3.new(0, -2, 0), 70)
			h:advance(1.0)
		end,
	},
}
