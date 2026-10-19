--[[
	gui_scenarios_theft_ui.luau — stage 4 wave 2 C: the THIEF's own screen (TheftController,
	docs/stage4_design.md §6.4 rev. 3, §6.9) over the 3D court: the banner HUD.TheftBar in the
	bottom band (hold / carry / «СОРВАЛОСЬ!» / the hints on glass), «ДОБЫЧА!» (HUD.TheftTitle) with
	the 🐟 flying into «САДОК», the red guide beam to the nearest exit, «🐕 СОБАКА!». Loaded by
	gui_scenarios_theft_world.luau (its court helpers come in as `H`); world = true, not in
	--all; by name.

	The stage 4 services are stubs in the preview sims (gui_dump STUBBED_SERVICES): the scenarios
	play StealService the way it talks to the thief — h:steal (StealEvent "Hold" / "Carry" and
	Player.Stealing), h:stealEvent ("Done" / "Cancel" / "Denied"), TankEvent "Stored" — and write
	the slot steal channel and the StolenFish (H.steal / H.carry) so the world reads like a real
	theft. The thief is the LOCAL player; in the held / carried views he "robs" his own base 1 (the
	court helpers paint base 1), the court hints use a neighbour's base 2 (h:extraPlayer as its
	owner) with the StealPrompts StealService would have made there, so the client filter
	(TheftPrompts) and the hint chain run for real. HUD.Status hiding while HUD.Stealing is set is
	HudController's (wave 2 D): until that is merged the scenarios mock it (statusRule) — the
	mock steps aside by itself once HudController handles HUD.Stealing.

	  thief_court_hint   a neighbour's court with fish he can take: the first-time glass hint
	                     («Зажми «Украсть» у витрины…» / «Держи E…» on a PC)
	  thief_court_wait   the same court while he waits after a theft: «⏳ Красть снова можно через
	                     0:24», counting (no prompts)
	  thief_court_shield the neighbour's base under a shield: «🛡️ Здесь щит — ещё 0:42»
	  thief_denied       a server "Denied" at the display (cooldown text, 2.5 s on glass)
	  thief_hold         the hold on Slot_3 from the follow camera: «🥷 КРАДЁШЬ: ФУГУ», the bar to
	                     the server's end, «1,8 с»; the lifted fish and «КРАДУТ!» in the clear
	                     (the [band] line prints StealRect vs the HUD with gui_render -v)
	  thief_carry        the carry: «🏃 БЕГИ ЗА ОГРАДУ!» draining, «🐕 СОБАКА!» (Slowed), the
	                     StolenFish on his head, the red beam to the gate
	  thief_done         over the gate: «ДОБЫЧА!» + «Фугу — в твоём садке · +$3.2/с», confetti,
	                     the 🐟 into «САДОК» (the chip 2/6 → 3/6)
	  thief_fail         the owner raised the shield: «💨 СОРВАЛОСЬ!» + the reason, shaking
	  thief_timeline     the whole run on a timeline: hold → carry (walking to the gate, the beam
	                     re-aimed) → «ДОБЫЧА!» (render it on every device: --devices …)
	  thief_timeline_fail hold → the shield → «СОРВАЛОСЬ!»

	  gui_render.py --scenario thief_hold,thief_carry,thief_done,thief_fail \
	      --devices phone,phone_small,phone_notch,tablet,desktop --out DIR
]]

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

-- The thief's own small tank (free displays: the loot always fits).
local OWN = { { Id = "Crucian", Age = 30 }, { Id = "Perch", Age = 60 } }
-- The neighbour's tank (base 2).
local NEIGHBOUR = {
	{ Id = "Perch", Age = 90 },
	{ Id = "Crucian", Age = 40 },
	{ Id = "Puffer", Age = 200 },
	{ Id = "Perch", Age = 10 },
}

return function(H: { [string]: any }): { any }
	local at = H.at

	-- HUD.Status hides while HUD.Stealing is set (HudController, wave 2 D): mocked until D's
	-- HudController handles it (then this does nothing).
	local function statusRule(h: any)
		local scripts = h.player:FindFirstChildOfClass("PlayerScripts")
		local module = scripts and h.sim:Find("Controllers.HudController", scripts)
		if module and string.find(module.Source, '"Stealing"', 1, true) then
			return
		end
		local hud = h:gui("HUD")
		local status = h:gui("HUD.Status")
		if not (hud and status) then
			return
		end
		local connection = hud:GetAttributeChangedSignal("Stealing"):Connect(function()
			status.Visible = hud:GetAttribute("Stealing") == nil
		end)
		h:atEnd(function()
			connection:Disconnect()
			status.Visible = true
		end)
	end

	-- The follow camera behind `who` (12.5 studs, 20° down, like Roblox's default and the
	-- preview's): from the HRP and its facing.
	local function follow(h: any, who: any)
		local root = who.Character and who.Character:FindFirstChild("HumanoidRootPart")
		if not (root and h.world) then
			return
		end
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z).Unit
		local eye = root.Position - flat * 11.7 + Vector3.new(0, 5.7, 0)
		h.world:setCamera(eye, root.Position + Vector3.new(0, 1.4, 0), 70)
	end

	-- The thief's base and own tank (the attributes TheftPrompts reads: a mounted tank).
	local function ownBaseIndex(h: any): number
		local index = h.player:GetAttribute("BaseIndex")
		return if typeof(index) == "number" then index else 1
	end

	-- The theft on base 1's Slot_3 as StealService plays it to the thief and the world.
	local function holdOn(h: any, slot: number, left: number, fishId: string?)
		H.steal(h, slot, "hold", h.player, left)
		H.alarm(h, h.player)
		h:steal("hold", { FishId = fishId or "Puffer", Slot = slot, BaseIndex = ownBaseIndex(h), Left = left })
		h:atEnd(function()
			h.player:SetAttribute("Stealing", nil)
			h.player:SetAttribute("Slowed", nil)
			local fish = h.player.Character and h.player.Character:FindFirstChild("StolenFish")
			if fish then
				fish:Destroy()
			end
		end)
	end

	local function carryOn(h: any, slot: number, fishId: string?, slowed: boolean?)
		H.carry(h, h.player, fishId or "Puffer")
		H.steal(h, slot, "carry", h.player, 25)
		h:steal("carry", { Left = 25, Slowed = slowed })
	end

	-- The credit as the thief's client gets it: the StolenFish and the slot channel gone, the
	-- display's Event stolen, TankEvent "Stored" (TankCount up), StealEvent "Done", Stealing nil.
	local function credit(h: any, slot: number, fishId: string)
		local fish = h.player.Character and h.player.Character:FindFirstChild("StolenFish")
		if fish then
			fish:Destroy()
		end
		H.steal(h, slot, nil)
		local data = h:theftFish(fishId)
		local count = (h.player:GetAttribute("TankCount") or 0) + 1
		h.player:SetAttribute("TankCount", count)
		local stored = {
			Result = "stored",
			Slot = count,
			Uid = "harness-stolen",
			Count = count,
			Slots = h.player:GetAttribute("TankSlots") or 6,
			Fish = { Id = data.Id, Rarity = data.Rarity, Kg = data.Kg, Value = data.Value, Income = data.Income },
		}
		h:tankEvent("Stored", stored)
		h:stealEvent("Done", {
			Fish = stored.Fish,
			Result = { Result = "stored", Slot = count, Count = count, Slots = stored.Slots },
			Name = "Ника",
		})
		h:steal(nil)
	end

	-- A neighbour (base 2) with a tank written like TankService and the StealPrompts StealService
	-- makes (Enabled where a fish is), so TheftPrompts and the hint chain run for real.
	local function neighbourCourt(h: any): (any, any)
		local owner = h:extraPlayer({ DisplayName = "Ника" })
		local other = h.sim.workspace.Bases:FindFirstChild(`Base_{owner:GetAttribute("BaseIndex")}`)
		local cfg = h:config("TankConfig")
		local steal = h:config("StealConfig")
		local ui = h:config("UIConfig")
		local rules = h.sim:Require(h.sim:Find("ReplicatedStorage.Shared.FishingRules"))
		local tankRules = h.sim:Require(h.sim:Find("ReplicatedStorage.Shared.TankRules"))
		local now = h.sim.workspace:GetServerTimeNow()
		local income10 = 0
		local prompts = {}
		for index = 1, cfg.MaxSlots do
			local slot = other.Tank.Slots:FindFirstChild(`Slot_{index}`)
			local spec = NEIGHBOUR[index]
			if not slot then
				continue
			end
			if spec and index <= cfg.StartSlots then
				local def = rules.GetFish(spec.Id)
				local kg = (def.MinKg + def.MaxKg) / 2
				local value, income = rules.Price(spec.Id, kg, nil)
				local tenths = tankRules.Income10(income)
				income10 += tenths
				slot:SetAttribute("FishUid", `n{index}`)
				slot:SetAttribute("FishId", spec.Id)
				slot:SetAttribute("Rarity", def.Rarity)
				slot:SetAttribute("Kg", kg)
				slot:SetAttribute("Value", value)
				slot:SetAttribute("Income", tenths / 10)
				slot:SetAttribute("GrowFrom", tankRules.AttrTime(now - spec.Age))
				slot:SetAttribute("State", "fish")
				-- (the pedestal label, the light bar and the occupied glass as TankService writes them)
				local flat = rules.GetRarity(def.Rarity)
				local style = ui.Rarity[def.Rarity]
				local label = slot.Pedestal.LabelGui.Label
				label.Text = def.Name
				if flat then
					label.TextColor3 = flat.Color
				end
				if style then
					slot.LightBar.Color = if style.Rainbow then ui.Rainbow[6] else style.Bottom
				end
				slot.Display.Transparency = cfg.Display.GlassOccupied
				if h.world then
					h.world:addLive(slot.LightBar)
					h.world:addLive(slot.Display)
				end
				local attachment = slot.Pedestal:FindFirstChild("PromptAttachment")
				if attachment then
					local prompt = h.sim:Create("ProximityPrompt", {
						Name = "StealPrompt",
						ActionText = steal.Prompt.Action,
						ObjectText = `{def.ShortName} · {tankRules.FormatRate(tenths)}`,
						HoldDuration = 3,
						MaxActivationDistance = steal.Prompt.MaxDistance,
						RequiresLineOfSight = false,
						Enabled = true,
					}, attachment)
					table.insert(prompts, prompt)
				end
			else
				slot:SetAttribute("State", if index <= cfg.StartSlots then "empty" else "locked")
			end
			slot:SetAttribute("Event", `{900 + index}|mount|`)
		end
		other.Tank:SetAttribute("Count", #prompts)
		other.Tank:SetAttribute("Slots", cfg.StartSlots)
		other.Tank:SetAttribute("Income", income10 / 10)
		owner:SetAttribute("Income", income10 / 10)
		h:atEnd(function()
			for _, prompt in prompts do
				prompt:Destroy()
			end
			for index = 1, cfg.MaxSlots do
				local slot = other.Tank.Slots:FindFirstChild(`Slot_{index}`)
				if slot then
					for _, name in { "FishUid", "FishId", "Rarity", "Kg", "Value", "Income", "GrowFrom", "State" } do
						slot:SetAttribute(name, nil)
					end
					if index <= cfg.StartSlots then
						slot.Pedestal.LabelGui.Label.Text = cfg.Texts.SlotEmpty
					end
				end
			end
			for _, name in { "Count", "Slots", "Income" } do
				other.Tank:SetAttribute(name, nil)
			end
			for _, name in { "ProtectUntil", "ProtectKind" } do
				other:SetAttribute(name, nil)
			end
		end)
		return owner, other
	end

	-- The local player in base 2's west aisle facing Slot_3, seen from B's court camera there
	-- (the world capture draws the local body on his own pier, so the camera is not his follow
	-- camera: it frames the neighbour's displays the way it does in steal_hold_thief_rule).
	local function intoCourt(h: any, other: any)
		h:tank(OWN)
		local from = at(h, -28.2, 3.2, 71.5, other)
		local toward = at(h, -33.5, 3.2, 71.5, other)
		h.sim:Teleport(h.player, CFrame.lookAt(from, Vector3.new(toward.X, from.Y, toward.Z)))
		if h.world then
			h.world:setCamera(at(h, -16.5, 8.9, 71.5, other), at(h, -28.2, 4.6, 71.5, other), 70)
		end
		h:advance(0.1)
	end

	-- The thief walks from where he stands towards a base-local point at `speed` studs/s for
	-- `seconds` (the camera follows; one teleport per 1/15 s).
	local function walk(h: any, to: { number }, speed: number, seconds: number)
		local root = h.player.Character and h.player.Character:FindFirstChild("HumanoidRootPart")
		if not root then
			return
		end
		local goal = at(h, to[1], to[2], to[3])
		local step = 1 / 15
		local t = 0
		while t < seconds - 1e-6 do
			local here = root.Position
			local ahead = Vector3.new(goal.X - here.X, 0, goal.Z - here.Z)
			if ahead.Magnitude > 0.1 then
				local move = ahead.Unit * math.min(ahead.Magnitude, speed * step)
				local next = here + move
				h.sim:Teleport(h.player, CFrame.lookAt(next, next + ahead.Unit))
			end
			follow(h, h.player)
			h:advance(step)
			t += step
		end
	end

	-- The hold camera of B's steal_hold_thief_rule (the robbed display's band): behind the thief
	-- at Slot_3 in the west aisle.
	local function holdCourt(h: any)
		h:money(1215, 459)
		H.court(h, { -16.5, 8.9, 71.5 }, { -28.2, 4.6, 71.5 }, 70)
		H.place(h, h.player, { -28.2, 3.2, 71.5 }, { -33.5, 0, 71.5 })
		h:advance(0.2)
	end

	return {
		{
			name = "thief_court_hint",
			desc = "A neighbour's court with fish he can take (TheftPrompts shows them): the first-time hint on glass in the bottom band — «Зажми «Украсть» у витрины и унеси рыбу за ограду!» (PC: «Держи E…»); «ВЗЯТЬ» and the fishing hint step aside",
			world = true,
			standard = false,
			still = { 0.4, 2.5 },
			burst = false,
			run = function(h: any)
				local _, other = neighbourCourt(h)
				intoCourt(h, other)
			end,
			during = function(h: any)
				h:advance(2.6)
			end,
		},
		{
			name = "thief_court_wait",
			desc = "The same court while he waits after a theft (StealCooldownUntil): «⏳ Красть снова можно через 0:24», counting down; every prompt hidden",
			world = true,
			standard = false,
			still = { 0.6, 1.6 },
			burst = false,
			run = function(h: any)
				local _, other = neighbourCourt(h)
				local tankRules = h.sim:Require(h.sim:Find("ReplicatedStorage.Shared.TankRules"))
				h.player:SetAttribute(
					"StealCooldownUntil",
					tankRules.AttrTime(h.sim.workspace:GetServerTimeNow() + 24.5)
				)
				h:atEnd(function()
					h.player:SetAttribute("StealCooldownUntil", nil)
				end)
				intoCourt(h, other)
			end,
			during = function(h: any)
				h:advance(1.6)
			end,
		},
		{
			name = "thief_court_shield",
			desc = "The neighbour's base under a shield (ProtectUntil, kind shield): «🛡️ Здесь щит — ещё 0:42» on glass; no prompts",
			world = true,
			standard = false,
			still = { 0.6 },
			burst = false,
			run = function(h: any)
				local _, other = neighbourCourt(h)
				local tankRules = h.sim:Require(h.sim:Find("ReplicatedStorage.Shared.TankRules"))
				other:SetAttribute("ProtectUntil", tankRules.AttrTime(h.sim.workspace:GetServerTimeNow() + 41.9))
				other:SetAttribute("ProtectKind", "shield")
				intoCourt(h, other)
			end,
			during = function(h: any)
				h:advance(0.6)
			end,
		},
		{
			name = "thief_denied",
			desc = 'A server "Denied" at a display (the cooldown): its text on glass for DeniedHint s with ⏳, the ring of the named prompt ended',
			world = true,
			standard = false,
			still = { 0.3, 2.2 },
			burst = false,
			run = function(h: any)
				holdCourt(h)
				h:stealEvent("Denied", {
					Reason = "cooldown",
					Text = "Красть снова можно через 0:24",
					BaseIndex = ownBaseIndex(h),
					Slot = 3,
				})
			end,
		},
		{
			name = "thief_hold",
			desc = "THE THIEF holds Slot_3 (follow camera): «🥷 КРАДЁШЬ: ФУГУ» on Night in the bottom band, the Berry bar filling to the server's end, «1,8 с», «Не отходи!»; the lifted fish and «КРАДУТ!» stay in the clear (Status hidden); [band] prints StealRect vs the HUD",
			world = true,
			standard = false,
			still = { 0.4, 1.2 },
			burst = false,
			run = function(h: any)
				statusRule(h)
				holdCourt(h)
				holdOn(h, 3, 3)
				h:advance(0.1)
			end,
			during = function(h: any)
				h:advance(1.2)
				H.measure(h, 3, "thief_hold")
			end,
		},
		{
			name = "thief_carry",
			desc = "The carry: «🏃 БЕГИ ЗА ОГРАДУ!» on Berry, the Gold bar draining, «21 с», «🐕 СОБАКА!» over its right end (Slowed), the StolenFish on his head, the red beam to the gate",
			world = true,
			standard = false,
			still = { 0.5, 1.4 },
			burst = false,
			run = function(h: any)
				statusRule(h)
				h:money(1215, 459)
				H.court(h, { -14, 8.9, 66.7 }, { -14, 4.6, 55 }, 70)
				H.place(h, h.player, { -14, 3.2, 55 }, { -14, 0, 40 })
				holdOn(h, 3, 3)
				h:advance(0.3)
				carryOn(h, 3, "Puffer", true)
				H.showDog(h)
				H.dogTo(h, "Chase", -14, 59, h.player)
			end,
			during = function(h: any)
				walk(h, { 0, 3.2, 20 }, 6.8, 1.4)
			end,
		},
		{
			name = "thief_done",
			desc = "Over the gate: «ДОБЫЧА!» slams into the bottom band (Gold → Leaf), «Фугу — в твоём садке · +$3.2/с», confetti from over his head, the 🐟 flies into «САДОК» and the chip rolls 2/6 → 3/6",
			world = true,
			standard = false,
			still = { 0.15, 0.5, 1.2 },
			sheet = { from = 0, to = 1.6, fps = 10, roi = { "HUD.TheftTitle", "HUD.RightButtons" } },
			burst = false,
			run = function(h: any)
				statusRule(h)
				h:money(1215, 459)
				H.court(h, { -2, 8.9, 25 }, { 0, 4.6, 12 }, 70)
				h:tank(OWN)
				H.place(h, h.player, { 0, 3.2, 14 }, { 0, 0, 0 })
				holdOn(h, 3, 3)
				h:advance(0.2)
				carryOn(h, 3, "Puffer", false)
				h:advance(0.4)
				credit(h, 3, "Puffer")
			end,
		},
		{
			name = "thief_fail",
			desc = "The owner raised the shield mid-hold: «💨 СОРВАЛОСЬ!» on Berry, shaking, «Хозяин включил щит — рыба вернулась домой»; gone after FailTime",
			world = true,
			standard = false,
			still = { 0.2, 1.0 },
			burst = false,
			run = function(h: any)
				statusRule(h)
				holdCourt(h)
				holdOn(h, 3, 3)
				h:advance(1.2)
				H.steal(h, 3, nil)
				h:stealEvent("Cancel", {
					Reason = "shield",
					Text = h:config("StealConfig").Texts.Cancel.shield,
					Phase = "hold",
				})
				h:steal(nil)
			end,
		},
		{
			name = "thief_timeline",
			desc = "The whole run from the thief's follow camera: the hold on Slot_3 (the bar fills to the server's end), the carry out of the aisle to the gate (the bar drains, the red beam re-aimed, «🐕 СОБАКА!» for a while), «ДОБЫЧА!» over the gate with the 🐟 into «САДОК»",
			world = true,
			standard = false,
			still = { 1.5, 4.2, 6.6 },
			timeline = { from = 0, to = 9.6, fps = 4 },
			extraBeats = {
				{ name = "hold", appear = "HUD.TheftBar" },
				{
					name = "carry",
					fn = function(h: any): boolean
						return h.player:GetAttribute("Stealing") == "carry"
					end,
				},
				{ name = "dog", appear = "HUD.TheftBar.DogChip" },
				{ name = "ДОБЫЧА", appear = "HUD.TheftTitle" },
				{ name = "slam gone", disappear = "HUD.TheftTitle" },
			},
			burst = false,
			run = function(h: any)
				statusRule(h)
				holdCourt(h)
				h:tank(OWN)
				follow(h, h.player)
			end,
			during = function(h: any)
				holdOn(h, 3, 3)
				h:advance(3.05)
				carryOn(h, 3, "Puffer", false)
				walk(h, { -14, 3.2, 62 }, 13.6, 1.0)
				h.player:SetAttribute("Slowed", true)
				walk(h, { -6, 3.2, 40 }, 6.8, 1.2)
				h.player:SetAttribute("Slowed", nil)
				walk(h, { 0, 3.2, 12 }, 13.6, 1.6)
				credit(h, 3, "Puffer")
				h:advance(2.8)
			end,
		},
		{
			name = "thief_timeline_fail",
			desc = "The hold on Slot_3, then the owner's shield: «СОРВАЛОСЬ!» with the reason, the fish drops back into its display, the banner leaves after FailTime",
			world = true,
			standard = false,
			still = { 1.0, 2.0 },
			timeline = { from = 0, to = 4.5, fps = 4 },
			extraBeats = {
				{ name = "hold", appear = "HUD.TheftBar" },
				{
					name = "fail",
					fn = function(h: any): boolean
						local title = h:gui("HUD.TheftBar.Title")
						return title ~= nil and title.Text == h:config("StealConfig").Texts.Banner.Fail
					end,
				},
				{ name = "gone", disappear = "HUD.TheftBar" },
			},
			burst = false,
			run = function(h: any)
				statusRule(h)
				holdCourt(h)
				follow(h, h.player)
			end,
			during = function(h: any)
				holdOn(h, 3, 3)
				h:advance(1.6)
				H.steal(h, 3, nil)
				h:stealEvent("Cancel", {
					Reason = "shield",
					Text = h:config("StealConfig").Texts.Cancel.shield,
					Phase = "hold",
				})
				h:steal(nil)
				h:advance(2.9)
			end,
		},
	}
end
