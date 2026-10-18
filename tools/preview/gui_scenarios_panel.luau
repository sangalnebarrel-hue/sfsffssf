--[[
	gui_scenarios_panel.luau — stage 3 tank panel states for the GUI previews (gui_dump.luau lists
	them after gui_scenarios.luau and its built-in states; the same scenario format, part of the
	standard set `--all`): HUD.TankPanel (TankPanelController on the sheet shell
	Controllers/Sheet, cards by Controllers/TankCards) — design §7.8 «tank_panel_home»,
	«tank_panel_full», «tank_panel_market», «tank_sell_confirm», «tank_sell», «panel_bite_yield»; plus
	«tank_panel_market_full» (the crowded header at a stall) and «tank_panel_close» (the ✕ shrink).

	The stage 3 services are stubs in the preview sim: `h:tank` writes the displays' attributes like
	TankService, `h:tankEvent` plays its TankEvent answers. Until Wave 2 C's MoneyController /
	TankButtonController show the Wallet and «САДОК», showChrome() below stands in for them (it
	only shows what is still hidden: their texts from the same attributes), so the panel's place
	under the status stack and left of the right column can be judged.

	  gui_render.py --scenario tank_panel_home,tank_panel_full,tank_panel_market,tank_panel_market_full,\
	      tank_panel_close,tank_sell_confirm,tank_sell,panel_bite_yield \
	      --devices phone,phone_small,phone_notch,tablet,desktop --out DIR
]]

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3

local PANEL_ROI = { "HUD.TankPanel" }

-- 3/6 at home: a Gold Perch, a maxed Puffer, a young Crucian.
local HOME = {
	{ Id = "Perch", Mutation = "Gold", Age = 60 },
	{ Id = "Puffer", Age = 320 },
	{ Id = "Crucian", Age = 20 },
}

-- 6/6 with a Rainbow Mythic.
local FULL = {
	{ Id = "Crucian", Age = 40 },
	{ Id = "Perch", Mutation = "Gold", Age = 120 },
	{ Id = "Puffer", Age = 310 },
	{ Id = "Swordfish", Mutation = "Neon", Age = 15 },
	{ Id = "SharkPup", Age = 200 },
	{ Id = "DragonFish", Mutation = "Rainbow", Age = 80 },
}

-- Stand-in for Wave 2 C until it merges: the Wallet «$…» and «САДОК» with its chip, if hidden.
local function showChrome(h: any)
	local rules = h.sim:Require(h.sim:Find("ReplicatedStorage.Shared.TankRules"))
	local wallet = h:gui("HUD.Status.Wallet")
	if wallet and not wallet.Visible then
		wallet.Visible = true
		local money = wallet:FindFirstChild("Money")
		local label = money and money:FindFirstChild("Label")
		if label then
			label.Text = rules.FormatMoney(h.player:GetAttribute("Money") or 0)
		end
		local rate = wallet:FindFirstChild("Rate")
		local income = h.player:GetAttribute("Income") or 0
		if rate then
			rate.Visible = income > 0
			rate.Text = rules.FormatRate(math.round(income * 10))
		end
	end
	local button = h:gui("HUD.RightButtons.TankButton")
	if button and not button.Visible then
		button.Visible = true
		local chip = button:FindFirstChild("Count")
		local label = chip and chip:FindFirstChild("Label")
		if label then
			label.Text = `{h.player:GetAttribute("TankCount") or 0}/{h.player:GetAttribute("TankSlots") or 6}`
		end
	end
end

local function panel(h: any): any
	return h:clientModule("TankPanelController")
end

-- The tank, the money, the chrome; then the panel opens (as «САДОК» does: Toggle).
local function openWith(h: any, list: { any }, money: number)
	local written = h:tank(list)
	local income10 = 0
	for _, fish in written do
		income10 += fish.Income10
	end
	h:money(money, income10)
	showChrome(h)
	h:advance(0.2)
	local controller = panel(h)
	if controller then
		-- (in the client's context: the sheet reads its UserInputService and camera)
		h.sim:Run(function()
			controller.Toggle()
		end, h.player)
	else
		h:warn("no TankPanelController")
	end
	return written
end

return {
	{
		name = "tank_panel_home",
		desc = "The tank panel at home, 3/6: a Gold Perch (👑 ×2), a maxed Puffer («МАКС»), a young Crucian, 3 empty cards and the locked teaser; the header «🐠 САДОК · 3/6 · +$X/с · 💵 $Y ▲»",
		still = { 0.12, 0.9 },
		sheet = { from = 0, to = 0.7, fps = 15, roi = PANEL_ROI, margin = 0.03 },
		run = function(h: any)
			openWith(h, HOME, 1234)
		end,
	},
	{
		name = "tank_panel_take",
		desc = "Opened with the rod still in the backpack (the action button «ВЗЯТЬ» with its newcomer «!» and the «where to go» hint up): the open sheet hides the fishing layer, nothing shows through the phone's glass sheet (UX-04); ✕ brings «ВЗЯТЬ» back",
		still = { 0.9, 1.6 },
		run = function(h: any)
			h:giveRod()
			h:advance(1)
			openWith(h, HOME, 1234)
		end,
		during = function(h: any)
			h:advance(1.2)
			h:click("HUD.TankPanel.Panel.Close")
		end,
	},
	{
		name = "tank_panel_full",
		desc = "The tank panel full, 6/6 (the chip turns Gold): every species, a Neon Swordfish, a Rainbow Dragon (Mythic: the rainbow outline turns), the teaser cut off at the right edge (it scrolls)",
		still = 0.9,
		run = function(h: any)
			openWith(h, FULL, 98765)
		end,
	},
	{
		name = "tank_panel_market",
		desc = "Opened by «САДОК» on the way, then at a stall the server's SellRatePct 150 — the Gold «🏪 РЫНОК +50%» chip pops in, the prices jump ×1.5, the buttons turn Gold (a stall's own prompt opens the panel at 150 already)",
		still = { 0.1, 0.8 },
		sheet = { from = 0, to = 0.8, fps = 15, roi = PANEL_ROI, margin = 0.03 },
		run = function(h: any)
			local written = h:tank(HOME)
			local income10 = 0
			for _, fish in written do
				income10 += fish.Income10
			end
			h:money(5400, income10)
			showChrome(h)
			h:tankEvent("Open", { Place = "Tank", RatePct = 100, Name = "Садок" })
			h:advance(1.2)
			h.player:SetAttribute("SellRatePct", 150)
			h.player:SetAttribute("SellPlace", "Market")
		end,
	},
	{
		name = "tank_sell_confirm",
		desc = "The first tap on «💵 $X»: Berry «ПРОДАТЬ?» with its 3 s ring, the card's income red «−$X/с» (a second tap counts only after 0.4 s)",
		still = { 0.3, 1.6 },
		sheet = { from = 0, to = 0.6, fps = 15, roi = PANEL_ROI, margin = 0.03 },
		run = function(h: any)
			openWith(h, HOME, 1234)
			h:advance(1)
			h:click("HUD.TankPanel.Panel.Cards.Card1.Sell")
		end,
	},
	{
		name = "tank_sell",
		desc = "The second tap sells: ⏳, the server answers (the display empties, «Sold»): the card squashes, the fish pops out, an empty card pops in with a gold ring, 💵 fly to the Wallet (MoneyController.Celebrate)",
		still = { 0.05, 0.7 },
		sheet = { from = 0, to = 1.2, fps = 15, roi = PANEL_ROI, margin = 0.03 },
		run = function(h: any)
			local written = openWith(h, HOME, 1234)
			h:advance(1)
			h:click("HUD.TankPanel.Panel.Cards.Card1.Sell")
			h:advance(0.6)
			h:click("HUD.TankPanel.Panel.Cards.Card1.Sell")
			h:advance(0.1)
			-- the stub server: what TankService does on TankSell("f1")
			local rules = h.sim:Require(h.sim:Find("ReplicatedStorage.Shared.TankRules"))
			local sold = written[1]
			local price = rules.SellPrice(sold.Value, HOME[1].Age + 1.9, 100)
			local rest = {}
			for i = 2, #HOME do
				local spec = table.clone(HOME[i])
				spec.Slot = i
				table.insert(rest, spec)
			end
			h:tank(rest, { event = "sold", at = 1, price = price })
			h:money(1234 + price)
			h:tankEvent("Sold", {
				Items = {
					{ Uid = sold.Uid, Id = sold.Id, Rarity = sold.Rarity, Mutation = sold.Mutation, Price = price },
				},
				Amount = price,
				RatePct = 100,
			})
		end,
	},
	{
		name = "tank_panel_market_full",
		desc = "At a stall with a full tank (6/6, a 5-digit total ▲): the header still fits before the ✕ — «+$X/с» gives way first (the Wallet above shows it), then the chip shortens to «💰 +50%»",
		still = 0.9,
		run = function(h: any)
			local written = h:tank(FULL)
			local income10 = 0
			for _, fish in written do
				income10 += fish.Income10
			end
			h:money(98765, income10)
			showChrome(h)
			h.player:SetAttribute("SellRatePct", 150)
			h.player:SetAttribute("SellPlace", "Market")
			h:tankEvent("Open", { Place = "Market", RatePct = 150, Name = "Рыбный рынок" })
		end,
	},
	{
		name = "tank_panel_close",
		desc = "✕: the sheet only shrinks to its middle (Quad In, never bigger than at rest), then hides",
		still = { 0.05, 0.1 },
		sheet = { from = 0, to = 0.2, fps = 30, roi = PANEL_ROI, margin = 0.03 },
		run = function(h: any)
			openWith(h, FULL, 98765)
			h:advance(1)
			h:click("HUD.TankPanel.Panel.Close")
		end,
	},
	{
		name = "panel_bite_yield",
		desc = "A bite while the panel is open (waiting with the bobber out): the panel pops out at once, «КЛЮЁТ!» and «ПОДСЕЧЬ!» have the screen",
		still = { 0.05, 0.5 },
		sheet = { from = 0, to = 0.5, fps = 15, margin = 0.03 },
		run = function(h: any)
			h:standAtSpot()
			h:equipRod()
			h:advance(0.3)
			h:serverSays("Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
			h.player:SetAttribute("FishingState", "Waiting")
			h:advance(0.5)
			openWith(h, HOME, 1234)
			h:advance(0.8)
			h.player:SetAttribute("FishingState", "Bite")
			h:serverSays("Bite", { Window = 1.8 })
		end,
	},
}
