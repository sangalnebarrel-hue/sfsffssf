--[[
	gui_scenarios_hud3.luau — stage 3 HUD states for the GUI previews (gui_dump.luau loads them
	after gui_scenarios.luau; the same scenario format, part of the standard set, so
	`gui_render.py --all` checks them on every device): the Wallet («💵 $1 234 +$42/с», the
	«$…» glass while loading, the 5 s income float), the «САДОК» button (the chip «4/6», the
	onboarding «!»), the catch card's tank stamp and the catch flying into «САДОК» (or, sold on the
	spot, as 💵 into the Wallet), the stage 3 toasts (design §7.8).

	The stage 3 services are stubs in the preview sim (gui_dump STUBBED_SERVICES): these
	scenarios play the server like TankService / EconomyService would — the player attributes
	(Money, Income, TankCount, TankSlots, DataMode) change in the same frame as the "Caught" that
	carries the TankResult (RemoteNames: crediting → attributes → remotes).

	  gui_render.py --scenario wallet_idle,wallet_loading,wallet_big,tank_button --devices \
	      phone,phone_small,phone_notch,tablet,desktop --out DIR
	  gui_render.py --scenario catch_to_tank,catch_replaced,catch_sold,catch_sold_notable --devices \
	      phone,desktop --out DIR
	  gui_render.py --scenario tank_button_badge,first_fish_toast,data_memory_toast --out DIR
]]

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3

local FISH = {
	Common = { Id = "Crucian", Rarity = "Common", Kg = 0.84, Value = 11, Income = 1.1 },
	Rare = { Id = "Puffer", Rarity = "Rare", Kg = 2.1, Value = 58, Income = 5.2 },
	Epic = { Id = "Swordfish", Rarity = "Epic", Kg = 63.5, Value = 182, Income = 15.6 },
	-- a NEW Gold Perch (Common, ×2) — weaker than every fish of a full tank of better ones
	GoldPerch = { Id = "Perch", Rarity = "Common", Mutation = "Gold", Kg = 1.1, Value = 35, Income = 3.2, New = true },
}

-- A full starting tank (StartSlots = 6): its weakest fish is the Crucian (h:tank list).
local FULL = {
	{ Id = "Crucian", Age = 40 },
	{ Id = "Perch", Age = 120 },
	{ Id = "Puffer", Age = 300 },
	{ Id = "Perch", Mutation = "Gold", Age = 15 },
	{ Id = "Puffer", Age = 200 },
	{ Id = "Swordfish", Age = 80 },
}

-- New money on a Wallet that is already shown is a jump: it waits for its celebration
-- (UIConfig.Wallet.SaleWait) and then counts up — let it land before the stills.
local function moneyLanded(h: any)
	h:advance(2)
end

-- Rod in hand at the own fishing spot.
local function readyAtSpot(h: any)
	h:standAtSpot()
	h:equipRod()
	h:advance(0.3)
end

-- From the cast to the minigame of `rarity` (the harness plays FishingService).
local function toMinigame(h: any, rarity: string)
	readyAtSpot(h)
	h:serverSays("Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
	h:advance(0.4)
	h:serverSays("Bite", { Window = 1.8 })
	h:advance(0.2)
	h:click("HUD.Fishing.ActionArea.ActionButton")
	h:advance(0.1)
	h:minigame(rarity)
	h:advance(0.6)
	h:click("HUD.Fishing.ActionArea.ActionButton", true)
	h:advance(0.05)
end

-- The server's catch with its TankResult: the player attributes first (TankService /
-- EconomyService), then "Caught" — the same frame. The income grows by the new fish's and, on
-- "replaced", drops by the replaced one's (its display's Income, written by h:tank); a fish sold
-- on the spot changes nothing — the Wallet's «+$/с» rolls when the fish lands (CounterHold).
local function serverCatch(h: any, fish: { [string]: any }, total: number, tank: { [string]: any }, money: number?)
	h.player:SetAttribute("FishCaught", total)
	h.player:SetAttribute("TankCount", tank.Count)
	h.player:SetAttribute("TankSlots", tank.Slots)
	if money then
		h.player:SetAttribute("Money", money)
	end
	if tank.Result == "stored" or tank.Result == "replaced" then
		local gone = 0
		local base = if tank.Result == "replaced" then h:base() else nil
		local slot = base and base.Tank.Slots:FindFirstChild(`Slot_{tank.Slot}`)
		if slot then
			gone = slot:GetAttribute("Income") or 0
		end
		local income = (h.player:GetAttribute("Income") or 0) + fish.Income - gone
		h.player:SetAttribute("Income", math.max(0, math.round(income * 10) / 10))
	end
	h:caught(fish, total, tank)
end

-- The catch card of `fish` with `tank` (time 0 = the card is on screen).
local function catchCard(h: any, fish: { [string]: any }, tank: { [string]: any }, money: number?)
	toMinigame(h, fish.Rarity)
	serverCatch(h, fish, 1, tank, money)
	h:waitVisible("HUD.Fishing.CatchCard", 5)
end

-- The card's last beat (the stamp is in) — then tap it closed after `after` s.
local function closeLater(after: number): (h: any) -> ()
	return function(h: any)
		h:advance(after)
		h:click("HUD.Fishing.CatchCard")
	end
end

-- The first fish ever (Tank.First) into an empty tank: its Common card is tapped closed while it
-- is still up — «В САДОК!» lands at ≈ 1.25 s, the card would close by itself at
-- UIConfig.CatchCardTime.Common (2.2 s) — then the fish flies into «САДОК» and lands (V-04: a
-- tap at 2.4 s hit a card already gone).
local function firstFish(h: any)
	catchCard(h, FISH.Common, { Result = "stored", Slot = 1, Uid = "f1", Count = 1, Slots = 6, First = true })
	h:advance(1.6)
	if not h:visible("HUD.Fishing.CatchCard") then
		h:warn("the first fish's card closed before the tap")
	end
	h:click("HUD.Fishing.CatchCard")
end

return {
	{
		name = "wallet_idle",
		desc = "Wallet: «💵 $1 234» + «+$20/с» panel-less under the badge; every 5 s a small «+$20» floats off it",
		still = { 0.6, 1.6 },
		run = function(h: any)
			h:tank({ { Id = "Perch", Age = 60 }, { Id = "Puffer", Age = 20 }, { Id = "Swordfish", Age = 200 } })
			h:money(1234)
			moneyLanded(h)
		end,
	},
	{
		name = "wallet_loading",
		desc = "The data loads longer than 3 s: «$…» on a glass pill, no rate — then it loads (punch, «$0»)",
		fresh = true,
		still = { 0, 1.0 },
		run = function(h: any)
			h.player:SetAttribute("DataMode", "Loading")
			h:advance(4.6)
		end,
		during = function(h: any)
			h:advance(0.5)
			h.player:SetAttribute("DataMode", "Ready")
		end,
	},
	{
		name = "wallet_big",
		desc = "A long Wallet row: «$999 999» with «+$1 234/с» (the number stays ≥ 22 px on the small phone)",
		still = 0.6,
		run = function(h: any)
			h:money(999999, 12340)
			moneyLanded(h)
		end,
	},
	{
		name = "tank_button",
		desc = "«САДОК» 🐠 with the chip «4/6» above «ДОМОЙ», the aqua button next to the cyan «ЗАБРОСИТЬ»",
		still = 0.6,
		run = function(h: any)
			h:tank({ { Id = "Crucian" }, { Id = "Perch" }, { Id = "Puffer" }, { Id = "Swordfish" } })
			h:money(86)
			moneyLanded(h)
			readyAtSpot(h)
		end,
	},
	{
		name = "tank_full",
		desc = "A full tank: the chip «6/6» turns gold",
		still = 0.6,
		run = function(h: any)
			h:tank(FULL)
			h:money(4321)
			moneyLanded(h)
			readyAtSpot(h)
		end,
	},
	{
		name = "catch_to_tank",
		desc = "A Rare catch into the tank: «+$5.2/с» flies out of the price, «В САДОК!» stamped, then the card flies into «САДОК» (chip 2 → 3) and the Wallet's «+$/с» rolls up",
		still = { 1.75, 2.85, 3.05, 3.4 },
		sheet = { from = 2.6, to = 3.5, fps = 15, roi = {}, margin = 0 },
		run = function(h: any)
			h:tank({ { Id = "Perch" }, { Id = "Crucian" } })
			h:money(120)
			catchCard(h, FISH.Rare, { Result = "stored", Slot = 3, Uid = "f3", Count = 3, Slots = 6 })
		end,
		during = closeLater(2.6),
	},
	{
		name = "catch_replaced",
		desc = "A full tank, an Epic catch: «ЗАМЕНА!» — it flies into «САДОК», coins fly to the Wallet, «+$/с» rolls up, the toast names both fish",
		still = { 2.45, 3.5, 3.8, 4.4 },
		run = function(h: any)
			h:tank(FULL)
			h:money(500)
			catchCard(h, FISH.Epic, {
				Result = "replaced",
				Slot = 1,
				Uid = "f7",
				Count = 6,
				Slots = 6,
				Price = 24,
				Replaced = { Uid = "f1", Id = "Crucian", Rarity = "Common", Price = 24 },
			}, 524)
		end,
		during = closeLater(3.2),
	},
	{
		name = "catch_sold",
		desc = "A full tank, a weaker catch: «ПРОДАНА», a gold «+$11», the card flies into the Wallet as 💵, «Садок полон…» once",
		still = { 1.75, 2.85, 3.05, 3.6 },
		run = function(h: any)
			h:tank(FULL)
			h:money(500)
			catchCard(h, FISH.Common, { Result = "sold", Count = 6, Slots = 6, Price = 11 }, 511)
		end, -- a Common card closes by itself (UIConfig.CatchCardTime)
	},
	{
		name = "catch_sold_notable",
		desc = "A full tank of better fish, a NEW Gold Perch is weaker: «САДОК ПОЛОН» over «ПРОДАНА» (Sun) slapped on the card's corner, the gold «6/6» pulses on «САДОК», the card stays ≥ 1.5 s after the stamp; then «Садок полон: «Окунь» слабее всех, +$35» — every time for a notable fish (new, mutated, Epic+)",
		still = { 2.6, 3.4, 5.4 },
		run = function(h: any)
			h:tank(FULL)
			h:money(500)
			catchCard(h, FISH.GoldPerch, { Result = "sold", Count = 6, Slots = 6, Price = 35 }, 535)
		end, -- (it closes by itself: CatchFx.cardTime holds a sold card SOLD_HOLD after its stamp)
	},
	{
		name = "tank_button_badge",
		desc = "The first fish ever arrived: the red «!» wobbles on «САДОК» until the panel opens",
		still = 0.2,
		run = function(h: any)
			firstFish(h)
			h:advance(5.5) -- the arrival, the toast came and went
		end,
	},
	{
		name = "first_fish_toast",
		desc = "Right after the first fish ever: «Твоя рыба приносит $ каждую секунду!» (Water 🐠)",
		still = 0.8,
		run = function(h: any)
			firstFish(h)
			-- (the toast waits for the arrival and the held trophy: MoneyController.CatchToast)
			h:waitVisible("HUD.Toasts.Toast", 6)
		end,
	},
	{
		name = "data_memory_toast",
		desc = "Studio without DataStore access: «💾 Studio: прогресс не сохраняется» once, after the base banner",
		fresh = true,
		still = 0.5,
		run = function(h: any)
			h.player:SetAttribute("DataMode", "Memory")
			h:waitFor(function()
				return h:visible("HUD.Status.Wallet")
			end, 10)
			h:advance(0.6)
		end,
	},
}
