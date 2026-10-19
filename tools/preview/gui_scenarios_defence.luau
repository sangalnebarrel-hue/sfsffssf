--[[
	gui_scenarios_defence.luau — stage 4 victim and defence HUD states for the GUI previews
	(gui_dump.luau loads them after gui_scenarios_panel.luau; the same scenario format, part of the
	standard set, so `gui_render.py --all` checks them on every device; docs/stage4_design.md §7.9):
	the owner's alert «🚨 ВОР В САДКЕ!» (the plate in the toast column on a tablet / desktop, the
	Compact pill beside the fisher on phones; idle, the bite, the minigame, the trophy, a catch
	card hurried away, the carry, the shield recharging, while stealing himself), the result toasts,
	the intruder toast, the shield chip «🛡️ 0:42» (all kinds), the protection's ending lesson, the
	«ЗАЩИТА» button (idle, «ЩИТ!», recharging), the «ЗАЩИТА» sheet (cards, bought, the two-tap
	«КУПИТЬ?», the shield recharging) and the tank panel's «КРАДУТ!» / «В ПУТИ…».

	StealService and DefenceService are stubs in the preview sim (gui_dump STUBBED_SERVICES): the
	scenarios play the server like they would — h:alert / h:stealEvent (StealEvent), h:shield (the
	own base's protection and the player's ShieldReadyAt), h:defence (HasDog / HasAlarm /
	LockLevel), defenceEvent below (DefenceEvent). HurryCard is wave 2 C's (a no-op stub here): the
	catch scenario taps the card closed the way HurryCard would close it.

	  gui_render.py --scenario victim_alert_idle,victim_alert_carry,defence_panel --devices \
	      phone,phone_small,phone_notch,tablet,desktop --out DIR
]]

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3

local RARE = { Id = "Puffer", Rarity = "Rare", Kg = 2.1, Value = 58, Income = 5.2 }

-- A tank of four fish (the victim's): the alert is about one of them.
local TANK = {
	{ Id = "Perch", Age = 120 },
	{ Id = "Puffer", Age = 300 },
	{ Id = "Crucian", Age = 40 },
	{ Id = "Swordfish", Age = 80 },
}

local function defenceEvent(h: any, kind: string, data: { [string]: any })
	h.sim:Find("ReplicatedStorage.Remotes.DefenceEvent"):FireClient(h.player, kind, data)
	h:advance(1 / 60)
end

-- Rod in hand at the own fishing spot.
local function readyAtSpot(h: any)
	h:standAtSpot()
	h:equipRod()
	h:advance(0.3)
end

-- From the cast to the bite (the harness plays FishingService).
local function toBite(h: any)
	readyAtSpot(h)
	h:serverSays("Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
	h:advance(0.4)
	h:serverSays("Bite", { Window = 1.8 })
	h:advance(0.3)
end

local function toMinigame(h: any, rarity: string)
	toBite(h)
	h:click("HUD.Fishing.ActionArea.ActionButton")
	h:advance(0.1)
	h:minigame(rarity)
	h:advance(0.6)
end

-- The alert of a hold on Slot 2 (the Puffer) by «Ника»; settle — let the plate pop and shake.
local function alertHold(h: any, extra: { [string]: any }?)
	local data: { [string]: any } = { Phase = "hold", Slot = 2, FishId = "Puffer", Short = "Фугу" }
	for k, v in extra or {} do
		data[k] = v
	end
	h:alert(data)
end

local scenarios = {}

local function add(s: { [string]: any })
	table.insert(scenarios, s)
end

--------------------------------------------------------------------------------
-- The victim's alert
--------------------------------------------------------------------------------

add({
	name = "victim_alert_idle",
	desc = "A hold starts on the own base, the owner idle at his spot: «🚨 ВОР В САДКЕ!» / «Ника крадёт: Фугу» with the big [🛡️ ЩИТ] and [🏠 ДОМОЙ] in the toast column (tablet, desktop); on phones the Compact pill beside the fisher; the thin Berry edge pulse, «ДОМОЙ!» ringing, «ЗАЩИТА» → «ЩИТ!»",
	run = function(h: any)
		h:tank(TANK)
		h:money(1234, 120)
		readyAtSpot(h)
		alertHold(h)
	end,
	still = { 0.7 },
	sheet = { from = 0, to = 0.9, fps = 10 },
})

add({
	name = "victim_alert_bite",
	desc = "The alert during a bite: «КЛЮЁТ!» keeps its slot under the fisher, the plate (pill on phones) never covers the fisher",
	run = function(h: any)
		h:tank(TANK)
		toBite(h)
		alertHold(h)
	end,
	still = { 0.6 },
})

add({
	name = "victim_alert_minigame",
	desc = "The alert during the minigame: the minigame docks left of the fisher on phones, the Compact pill right of him (≥ 16 px from the column), the minigame keeps its input (ЛОВИ!)",
	run = function(h: any)
		h:tank(TANK)
		toMinigame(h, "Rare")
		alertHold(h)
	end,
	still = { 0.6 },
})

add({
	name = "victim_alert_compact",
	desc = "Phones: the longest short name «🚨 ВОР! МЕЧ-РЫБА» in the Compact pill during a Legendary minigame — beside the fisher, ≥ 16 px from the minigame, the status stack and the column (a tight screen: 🚨 + the full ЩИТ, no label)",
	run = function(h: any)
		h:tank(TANK)
		toMinigame(h, "Legendary")
		alertHold(h, { Slot = 4, FishId = "Swordfish", Short = "Меч-рыба" })
	end,
	still = { 0.7 },
})

add({
	name = "victim_alert_catch",
	desc = "DC-02: a hold starts while a Rare catch card is up — the card closes through its normal path (HurryCard; tapped here), the fish flies into «САДОК», then the plate pops in (≈ 1 s)",
	run = function(h: any)
		h:tank(TANK)
		toMinigame(h, "Rare")
		h:caught(RARE, 1, { Result = "stored", Slot = 5, Uid = "f9", Count = 5, Slots = 6 })
		h:waitVisible("HUD.Fishing.CatchCard", 5)
		h:advance(1.0)
		alertHold(h)
		h:advance(0.1)
		h:click("HUD.Fishing.ActionArea.ActionButton") -- (what HurryCard does: «ЗАБРАТЬ!»)
	end,
	still = { 0.2, 1.6 },
	sheet = { from = 0, to = 1.8, fps = 8 },
})

add({
	name = "victim_alert_carry",
	desc = "The carry: «🏃 ВОР УБЕГАЕТ!» / «Ника уносит: Фугу — жми ЩИТ!» with the same two buttons (the shield also returns a carried fish, DC-01)",
	run = function(h: any)
		h:tank(TANK)
		readyAtSpot(h)
		alertHold(h)
		h:advance(1.0)
		alertHold(h, { Phase = "carry", Quiet = true })
	end,
	still = { 0.6 },
})

add({
	name = "victim_alert_cooldown",
	desc = "The shield recharging (1:12 left): the ЩИТ button stays as a Slate «⏳ 1:12» (a tap wiggles it), the carry line without «жми ЩИТ!», «ЗАЩИТА» stays itself with its veil",
	run = function(h: any)
		h:tank(TANK)
		readyAtSpot(h)
		h:shield(nil, 72)
		alertHold(h, { Phase = "carry" })
	end,
	still = { 0.7 },
})

add({
	name = "victim_alert_while_stealing",
	desc = "Robbed while stealing himself: the plate (pill on phones) without buttons, «Пока крадёшь сам, щит не включить»; HUD.Status hidden (§6.4 rev. 3), the TheftBar's bottom band left free",
	run = function(h: any)
		h:tank(TANK)
		h:standFar()
		h:advance(0.3)
		h:steal("hold", { Slot = 3, FishId = "Perch" })
		h:gui("HUD"):SetAttribute("Stealing", "hold") -- (TheftController's, wave 2 C)
		h:advance(0.4)
		alertHold(h)
		h:atEnd(function()
			h:gui("HUD"):SetAttribute("Stealing", nil)
			h:steal(nil)
		end)
	end,
	still = { 0.7 },
})

add({
	name = "victim_lost_toast",
	desc = "The fish is gone: the plate leaves, «Украдено: Фугу (Ника)» (theft, big), «Садок отдыхает 1:30 — никто не украдёт», the 90 s chip «🛡️ 1:30» and one tip (the shield was ready and unused)",
	run = function(h: any)
		h:tank(TANK)
		h:money(1234, 120)
		readyAtSpot(h)
		alertHold(h)
		h:advance(1.5)
		h:alert(false)
		h:shield(90, 0, "after")
		h:stealEvent("Lost", {
			Fish = { Id = "Puffer", Rarity = "Rare", Kg = 2.1, Value = 58 },
			Name = "Ника",
			Until = h.sim.workspace:GetServerTimeNow() + 90,
			Kind = "after",
		})
	end,
	still = { 0.9, 5.4 },
})

add({
	name = "victim_saved_toast",
	desc = "The owner tagged the thief: «Вор пойман — рыба спасена!» (saved, 💪) with confetti; the plate and the layers gone",
	run = function(h: any)
		h:tank(TANK)
		readyAtSpot(h)
		alertHold(h)
		h:advance(1.5)
		h:alert(false)
		h:stealEvent("Saved", { Reason = "tag", Slot = 2, Text = "Вор пойман — рыба спасена!" })
	end,
	still = { 0.8 },
})

add({
	name = "victim_intruder",
	desc = "The alarm's early warning: «👀 Ника у тебя во дворе!» (warning) and the «ЗАЩИТА» button bobs",
	run = function(h: any)
		h:tank(TANK)
		readyAtSpot(h)
		h:defence({ alarm = true })
		h:stealEvent("Intruder", { Thief = 2002, Name = "Ника" })
	end,
	still = { 0.8 },
})

--------------------------------------------------------------------------------
-- The shield chip and the «ЗАЩИТА» button
--------------------------------------------------------------------------------

add({
	name = "defence_shield_chip",
	desc = "The shield on: the solid Guard chip «🛡️ 0:42» at the right end of the base badge; «ЗАЩИТА» recharging (the veil, «3:42»)",
	run = function(h: any)
		h:money(1234, 120)
		h:shield(42, 222, "shield")
	end,
	still = { 0.8 },
})

add({
	name = "defence_shield_chip_join",
	desc = "The join protection: the glass chip «🛡️ 1:18» (any kind shows), the shield ready",
	run = function(h: any)
		h:money(1234, 120)
		h:shield(78, 0, "join")
	end,
	still = { 0.8 },
})

add({
	name = "defence_shield_chip_rest",
	desc = "«Садок отдыхает» after a second loss: the glass chip «🛡️ 6:12»",
	run = function(h: any)
		h:money(1234, 120)
		h:shield(372, 0, "rest")
	end,
	still = { 0.8 },
})

add({
	name = "defence_newbie_ending",
	desc = "DC-07: 15 s before the newbie protection ends — «Скоро воры смогут красть. Увидишь «ВОР В САДКЕ!» — жми 🛡️ ЩИТ!», the «ЗАЩИТА» button bobs, the chip pulses in its last 10 s",
	run = function(h: any)
		h:money(1234, 120)
		h:shield(16, 0, "newbie")
		h:advance(1.4)
	end,
	still = { 0.6, 6.2 },
})

add({
	name = "defence_button",
	desc = "The right column with three squares: «ЗАЩИТА» (Guard 🛡️) over «САДОК» and «ДОМОЙ»; the first affordable defence lights its «!» once",
	run = function(h: any)
		h:tank(TANK)
		h:money(1800, 120)
		readyAtSpot(h)
	end,
	still = { 0.8 },
})

add({
	name = "defence_button_alert",
	desc = "During an alert with the shield ready: «ЗАЩИТА» → «ЩИТ!» (Berry, glowing rings, «!»): one tap raises the shield, even mid-minigame",
	run = function(h: any)
		h:tank(TANK)
		toMinigame(h, "Rare")
		alertHold(h)
	end,
	still = { 0.6, 1.3 },
})

--------------------------------------------------------------------------------
-- The «ЗАЩИТА» sheet
--------------------------------------------------------------------------------

local function openSheet(h: any)
	h:click("HUD.RightButtons.DefenceButton")
	h:waitVisible("HUD.DefencePanel", 2)
	h:advance(0.6)
end

add({
	name = "defence_panel",
	desc = "The «ЗАЩИТА» sheet: ЩИТ «ВКЛЮЧИТЬ» (Guard), СОБАКА / СИГНАЛИЗАЦИЯ / ЗАМОК with their prices — Gold when affordable, Slate (still readable) when not; the Wallet chip in the header",
	run = function(h: any)
		h:money(3000, 120)
		readyAtSpot(h)
		openSheet(h)
	end,
	still = { 0.3 },
	sheet = { from = 0, to = 0.5, fps = 10 },
})

add({
	name = "defence_panel_bought",
	desc = "Everything bought: Leaf «КУПЛЕНО» stamps, the lock «Сильнее замки — скоро в магазине» (DC-11); the shield on (glass «🛡️ 0:42»)",
	run = function(h: any)
		h:money(12345, 120)
		h:defence({ dog = true, alarm = true, lock = 1 })
		h:shield(42, 222, "shield")
		h.player:SetAttribute("ShieldUntil", h.player:GetAttribute("ShieldReadyAt") - 180)
		readyAtSpot(h)
		openSheet(h)
	end,
	still = { 0.3 },
})

add({
	name = "defence_buy_confirm",
	desc = "The first tap on the dog's «💵 $6 000»: Berry «КУПИТЬ?» with its 3 s ring (a second tap counts only after 0.4 s); then the second tap and «Bought»: the stamp, confetti, 💵 fly out of the Wallet into the card, «−$6 000»",
	run = function(h: any)
		h:money(9000, 120)
		readyAtSpot(h)
		openSheet(h)
		h:click("HUD.DefencePanel.Panel.Cards.DogCard.Buy")
		h:advance(0.5)
	end,
	still = { 0.2 },
	sheet = { from = 0, to = 1.6, fps = 8 },
	during = function(h: any)
		h:advance(0.4)
		h:click("HUD.DefencePanel.Panel.Cards.DogCard.Buy")
		h:advance(0.1)
		h.player:SetAttribute("Money", 3000)
		h:defence({ dog = true })
		defenceEvent(h, "Bought", { Item = "Dog", Price = 6000 })
	end,
})

add({
	name = "defence_panel_shield_wait",
	desc = "The shield card recharging: Slate «⏳ 2:59» with its ring timer; protected by the join protection ≥ 60 s instead: «ТЫ ПОД ЗАЩИТОЙ»",
	run = function(h: any)
		h:money(800, 40)
		h:shield(nil, 179)
		readyAtSpot(h)
		openSheet(h)
	end,
	still = { 0.3 },
})

--------------------------------------------------------------------------------
-- The tank panel during a theft (§6.7)
--------------------------------------------------------------------------------

add({
	name = "victim_tank_panel_stealing",
	desc = "The tank panel while Slot 2 is being stolen («КРАДУТ!», Berry; a tap asks the server: «Её сейчас крадут!») and Slot 4 is the thief's own fish still on the way («В ПУТИ…», Slate)",
	run = function(h: any)
		h:tank(TANK)
		h:money(1234, 120)
		readyAtSpot(h)
		local base = h:base()
		local slots = base.Tank.Slots
		slots.Slot_2:SetAttribute("StealPhase", "hold")
		slots.Slot_4:SetAttribute("Escrow", true)
		h:atEnd(function()
			slots.Slot_2:SetAttribute("StealPhase", nil)
			slots.Slot_4:SetAttribute("Escrow", nil)
		end)
		h:click("HUD.RightButtons.TankButton")
		h:waitVisible("HUD.TankPanel", 2)
		h:advance(0.8)
	end,
	still = { 0.2 },
})

return scenarios
