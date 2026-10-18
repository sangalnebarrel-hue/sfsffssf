--[[
	Stage 3 END-TO-END, part 2 — the full tank and the stalls (design §1.1 steps 8–9, §1.2, §7.6
	items 4–5): the real server and a real phone client (tests/stage3_e2e_kit.luau), a save poked
	into the sim DataStore before the join (the kid comes back with a tank).

	  (3) a full tank (6/6 loaded from the save): a stronger catch replaces the weakest fish —
	      «ЗАМЕНА!» on the card, the weakest sold at its value now (server: "autosell"), the toast
	      «Замена! «Меч-рыба» вместо «Карасик» +$N», the income rolls up, the court display swaps
	      its fish; a weaker catch is sold on the spot — «ПРОДАНА», the card flies into the Wallet as
	      💵, «Садок полон — лови рыбу получше!» once; the next weak catch is quiet; the tank stays
	      6/6, the stats and the ledger hold;
	  (4) the stalls: the kid WALKS from the base to the hub «РЫБНЫЙ РЫНОК» and holds E «Продать
	      рыбу» the moment he arrives — the hold counts as the dwell (UX-05): SellRatePct 150
	      before "Open", so the panel opens straight in market mode (the chip, Gold buttons,
	      ×1.5 prices, never ×1 first); the «РЫНОК +50%!» word; two fish sold one by one at
	      ×1.5, coins at the scales; walking away → ×1 again; a bridge kiosk («Ларёк»): after a
	      teleport onto the bridge (its hold waited out) he walks in and the server's own
	      samples (dwell) switch the rate to ×1.5; its prompt opens the panel; it pays ×1.5 too.

	Run: lune run tools/run_tests.luau stage3_e2e_tank
]]

local roblox = require("@lune/roblox")
local Kit = require("./stage3_e2e_kit")

local Vector3 = roblox.Vector3

local TEXTS = Kit.TEXTS
local TankConfig = Kit.TankConfig
local EconomyConfig = Kit.EconomyConfig
local FishingConfig = Kit.FishingConfig
local UIConfig = Kit.UIConfig

local tests = {}

-- Waits until the own court shows `count` display fish (quiet builds: ≤ BuildPerCheck per check).
local function courtBuilt(sim: any, world: any, count: number): boolean
	return sim:WaitFor(function()
		return world.Stats().fish >= count
	end, 5, Kit.COARSE) == true
end

-- The HUD's flying 💵 / 🐟 (FxFly labels) from now on.
local function flights(hud: any): { string }
	local log = {}
	hud.screen.ChildAdded:Connect(function(c)
		if c.Name == "FxFly" and c:IsA("TextLabel") then
			table.insert(log, c.Text)
		end
	end)
	return log
end

tests["(3) a full tank: a stronger catch replaces the weakest («ЗАМЕНА!», the toast, the court swaps); weaker ones are sold at once («ПРОДАНА», 💵 into the Wallet, «Садок полон…» once)"] = function(
	t
)
	local sim = Kit.boot(t)
	-- The weakest by income is the 0.3 kg Crucian in Slot_1 (asserted below from the real prices).
	local saved = {
		Kit.savedFish("Crucian", "f1", 1, { Kg = 0.3, Age = 40 }),
		Kit.savedFish("Perch", "f2", 2, { Kg = 0.4, Age = 80 }),
		Kit.savedFish("Crucian", "f3", 3, { Kg = 1.2, Age = 120 }),
		Kit.savedFish("Perch", "f4", 4, { Kg = 1.8, Age = 160 }),
		Kit.savedFish("Puffer", "f5", 5, { Kg = 0.8, Age = 200 }),
		Kit.savedFish("Puffer", "f6", 6, { Kg = 3, Age = 240 }),
	}
	Kit.pokeSave(sim, 1, { Money = 200, Tank = saved })
	local p = Kit.join(t, sim, 1, "phone")
	local hud = Kit.hud(sim, p)
	local R = Kit.shared(sim, "TankRules")
	local world = Kit.client(sim, p, "TankWorldController")
	local base = Kit.baseOf(sim, p)
	local log = Kit.moneyLog(sim)
	local seen = Kit.toasts(hud)
	local flown = flights(hud)

	local incomes, sum = {}, 0
	for i, f in saved do
		local _, income10 = Kit.priceOf(sim, f.Id, f.Kg)
		incomes[i] = income10
		sum += income10
	end
	for i = 2, 6 do
		t.ok(incomes[i] > incomes[1], `the 0.3 kg Crucian earns least ({incomes[1]} < {incomes[i]})`)
	end

	-- The tank comes back from the save: 6/6 everywhere.
	t.eq(p:GetAttribute("TankCount"), 6, "server: 6 fish loaded")
	sim:Advance(2)
	t.eq(hud.tankChip.Text, "6/6", "«САДОК» 6/6")
	t.ok(p:GetAttribute("Money") >= 200, "the saved money (and the income since the load)")
	t.eq(hud.money.Text, R.FormatMoney(p:GetAttribute("Money")), "the Wallet shows it")
	t.eq(hud.rate.Text, R.FormatRate(sum), "the Wallet: the tank's income")
	t.eq(world.GetPierWord().Plate.Count.Text, "🐠 6/6", "the pier word 6/6")
	t.ok(courtBuilt(sim, world, 6), "the court shows all 6 fish")

	-- A stronger catch (a 25 kg Swordfish) replaces the weakest.
	Kit.goFish(t, sim, p)
	Kit.forceFish(sim, "Swordfish", 25)
	local _, swordIncome = Kit.priceOf(sim, "Swordfish", 25)
	local caught = Kit.catch(t, sim, p, hud, "the stronger catch")
	local tank = caught.Tank
	t.eq(tank.Result, "replaced", "server: replaced")
	t.eq(tank.Slot, 1, "… in the weakest fish's display")
	t.eq(tank.Replaced.Id, "Crucian", "the weakest fish was sold")
	t.eq(tank.Replaced.Uid, "f1")
	t.eq(tank.Price, tank.Replaced.Price, "Price = what the weakest fetched")
	t.eq(Kit.earned(log, p, "autosell"), tank.Price, "server: credited at once")
	t.ok(sim:WaitFor(function()
		return hud.stamp.Visible
	end, 4, Kit.FRAME) == true, "stamped")
	t.eq(hud.stampLabel.Text, TEXTS.Stamp.replaced, "«ЗАМЕНА!»")
	Kit.landed(t, sim, p, hud, "the replacement")
	t.eq(hud.tankChip.Text, "6/6", "still 6/6")
	sim:WaitFor(function()
		return p.Character:FindFirstChild("HeldFish") == nil
	end, FishingConfig.HoldFishTime.Epic + 1, Kit.COARSE)
	sim:Advance(UIConfig.TankButton.ReplacedToastAfter + 1.5)
	local replacedText = Kit.fill(TEXTS.Replaced, {
		new = Kit.fishDef("Swordfish").ShortName,
		old = Kit.fishDef("Crucian").ShortName,
		price = R.FormatMoney(tank.Price),
	})
	t.ok(seen[replacedText] ~= nil, `the toast «{replacedText}»`)
	local newSum = sum - incomes[1] + swordIncome
	t.eq(hud.rate.Text, R.FormatRate(newSum), "the Wallet's rate rolled up")
	t.eq(hud.money.Text, R.FormatMoney(p:GetAttribute("Money")), "the Wallet counted the sale in")
	local swapped = world.GetFish(base, 1)
	t.ok(swapped and swapped:GetAttribute("FishId") == "Swordfish", "the court display swapped its fish")
	t.eq(base.Tank.Slots.Slot_1:GetAttribute("FishUid"), caught.Fish.Uid, "Slot_1 holds the new fish")

	-- Weaker catches are sold on the spot: quiet, one toast per session.
	for round = 1, 2 do
		Kit.forceFish(sim, "Crucian", 0.3)
		local value = Kit.priceOf(sim, "Crucian", 0.3)
		local autosold = Kit.earned(log, p, "autosell")
		local weak = Kit.catch(t, sim, p, hud, `weak catch {round}`)
		t.eq(weak.Tank.Result, "sold", `{round}: server: sold on the spot`)
		t.eq(weak.Tank.Price, R.SellPrice(value, 0, EconomyConfig.HomeRatePct), `{round}: at its value`)
		t.eq(weak.Tank.Slot, nil, `{round}: no display`)
		t.eq(Kit.earned(log, p, "autosell") - autosold, weak.Tank.Price, `{round}: credited`)
		t.ok(sim:WaitFor(function()
			return hud.stamp.Visible
		end, 4, Kit.FRAME) == true, `{round}: stamped`)
		t.eq(hud.stampLabel.Text, TEXTS.Stamp.sold, `{round}: «ПРОДАНА»`)
		local bills = #flown
		Kit.landed(t, sim, p, hud, `weak catch {round}`)
		local bill = false
		for i = bills + 1, #flown do
			bill = bill or flown[i] == "💵"
		end
		t.ok(bill, `{round}: the card flew into the Wallet as 💵`)
		t.eq(hud.tankChip.Text, "6/6", `{round}: «САДОК» untouched`)
		sim:WaitFor(function()
			return p.Character:FindFirstChild("HeldFish") == nil
		end, FishingConfig.HoldFishTime.Common + 1, Kit.COARSE)
		sim:Advance(UIConfig.Wallet.SoldToastGap + 2)
		t.eq(hud.money.Text, R.FormatMoney(p:GetAttribute("Money")), `{round}: the Wallet counted it in`)
		if round == 1 then
			t.ok(seen[TEXTS.FullSold] ~= nil, `the first time: «{TEXTS.FullSold}»`)
		end
	end
	t.eq(seen[TEXTS.FullSold], 1, `«{TEXTS.FullSold}» only once per session`)

	-- Server truth: still 6 fish; 1 replaced + 2 sold; 9 caught ever; the ledger.
	local data = Kit.service(sim, "DataService"):Get(p)
	t.eq(#data.Tank, 6, "the save's tank holds 6")
	t.eq(data.Stats.Sold, 3, "Stats.Sold: the replaced one and two sold on the spot")
	t.eq(data.Stats.Caught, 9, "Stats.Caught: 6 saved + 3")
	Kit.ledgerHolds(t, sim, data, "after the catches")
	sim:AssertNoErrors({ warnings = true })
end

tests["(4) stalls: walk to the hub market, hold E at once → the panel opens in market mode (×1.5), «РЫНОК +50%!»; two fish sold at ×1.5; away → ×1; a bridge kiosk: ×1.5 after the dwell, pays ×1.5 too"] = function(
	t
)
	local sim = Kit.boot(t)
	local maxAge = TankConfig.Growth.Time
	local saved = {
		Kit.savedFish("Puffer", "f1", 1, { Kg = 2, Age = maxAge }),
		Kit.savedFish("Perch", "f2", 2, { Kg = 1, Age = maxAge, Mutation = "Neon" }),
		Kit.savedFish("Crucian", "f3", 3, { Kg = 1, Age = 0 }),
	}
	Kit.pokeSave(sim, 1, { Money = 50, Tank = saved })
	local p = Kit.join(t, sim, 1, "phone")
	local hud = Kit.hud(sim, p)
	local R = Kit.shared(sim, "TankRules")
	local world = Kit.client(sim, p, "TankWorldController")
	local log = Kit.moneyLog(sim)
	local MARKET = EconomyConfig.MarketRatePct
	local HOME = EconomyConfig.HomeRatePct
	local bonus = MARKET - 100

	-- Walk from the base to the hub market (≈ 300 studs: the server samples once a second).
	local market = sim:Find("Workspace.Map.Hub.FishMarket.Scales.SellPromptAttachment")
	local prompt = market:FindFirstChild("SellPrompt")
	t.ok(prompt and prompt:IsA("ProximityPrompt"), "the market's «Продать рыбу» prompt")
	t.eq(prompt.ActionText, EconomyConfig.Prompt.Action, "«Продать рыбу»")
	local stand = market.WorldPosition + Vector3.new(4, 0, 4)
	t.eq(p:GetAttribute("SellRatePct"), HOME, "at the base: ×1")
	t.ok(Kit.walkTo(sim, p, stand), "the kid walks to the market")
	t.eq(p:GetAttribute("SellRatePct"), HOME, "just arrived: no dwell yet")

	-- Holds E «Продать рыбу» at once → the panel opens in market mode (UX-05: the hold is the
	-- dwell, SellRatePct 150 before "Open").
	local opens = #Kit.tankEvents(sim, p, "Open")
	local rates = {}
	local rateConn = p:GetAttributeChangedSignal("SellRatePct"):Connect(function()
		table.insert(rates, p:GetAttribute("SellRatePct"))
	end)
	t.ok(sim:HoldPrompt(p, prompt), "the prompt is held to the end")
	t.ok(sim:WaitFor(function()
		return #Kit.tankEvents(sim, p, "Open") > opens and hud.panel.Visible
	end, 2, Kit.FRAME) == true, "TankEvent Open → the panel opens")
	local open = Kit.tankEvents(sim, p, "Open")[opens + 1]
	t.eq(open.Place, "Market")
	t.eq(open.RatePct, MARKET, "the hold gave ×1.5 at once")
	t.eq(p:GetAttribute("SellRatePct"), MARKET)
	t.eq(p:GetAttribute("SellPlace"), "Market")
	local values = {}
	for i, f in saved do
		values[i] = Kit.priceOf(sim, f.Id, f.Kg, f.Mutation)
	end
	local card1 = Kit.card(hud, 1)
	local price1 = R.SellPrice(values[1], maxAge, MARKET)
	-- From the first frame the panel shows: never a ×1 price or a Leaf button first.
	t.eq(card1.Sell.Caption.Text, Kit.fill(TEXTS.SellPhone, { price = R.FormatMoney(price1) }), "×1.5 on the button")
	t.ok(Kit.colorNear(Kit.faceTop(card1.Sell), UIConfig.Palette.Gold.Top), "Gold buttons at a stall")
	sim:Advance(1)
	t.ok(hud.header.Market.Visible, "the «💰 РЫНОК +50%» chip")
	t.eq(card1.Sell.Caption.Text, Kit.fill(TEXTS.SellPhone, { price = R.FormatMoney(price1) }), "still ×1.5")
	t.ok(Kit.colorNear(Kit.faceTop(card1.Sell), UIConfig.Palette.Gold.Top), "still Gold")
	local word = world.Stats().folder:FindFirstChild("FxMarketWord", true)
	local board = word and word:FindFirstChildOfClass("BillboardGui")
	t.ok(board and board.Enabled, "the «РЫНОК +50%!» word over the market")
	t.eq(board.Plate.Word.Text, Kit.fill(TEXTS.MarketWord, { bonus = bonus }))
	sim:Advance(1.2)
	rateConn:Disconnect()
	t.eq(rates, { MARKET }, "SellRatePct went 100 → 150 once (the server's samples keep it)")

	-- Two fish sold one by one at ×1.5.
	local coins = {}
	world.Stats().folder.DescendantAdded:Connect(function(d)
		if d:IsA("ParticleEmitter") then
			table.insert(coins, d)
		end
	end)
	local sold1 = Kit.sell(t, sim, p, hud, 1)
	t.eq(sold1.Amount, price1, "the maxed Puffer at ×1.5")
	t.eq(sold1.RatePct, MARKET)
	t.eq(sold1.Place, "Market")
	sim:Advance(1.5)
	t.ok(#coins >= 1, "coins burst at the market's scales")
	local price2 = R.SellPrice(values[2], maxAge, MARKET)
	local sold2 = Kit.sell(t, sim, p, hud, 2)
	t.eq(sold2.Amount, price2, "the maxed Neon Perch at ×1.5")
	t.eq(Kit.earned(log, p, "sell"), price1 + price2, "server: both sales credited")
	sim:Advance(1.5)
	t.eq(hud.tankChip.Text, "1/6", "one fish left")
	t.eq(hud.money.Text, R.FormatMoney(p:GetAttribute("Money")), "the Wallet counted both in")

	-- Walking away: ×1 again; the chip pops out.
	t.ok(Kit.walkTo(sim, p, market.WorldPosition + Vector3.new(40, 0, 40)), "the kid walks off")
	t.ok(sim:WaitFor(function()
		return p:GetAttribute("SellRatePct") == HOME
	end, 2, Kit.COARSE) == true, "away from the stall: ×1")
	sim:Advance(1.2)
	t.eq(hud.header.Market.Visible, false, "the market chip is gone")
	local card3 = Kit.card(hud, 3)
	t.ok(Kit.colorNear(Kit.faceTop(card3.Sell), UIConfig.Palette.Leaf.Top), "Leaf buttons at home rate")
	sim:Click(p, hud.close)
	sim:Advance(0.6)
	t.eq(hud.panel.Visible, false, "✕ closes the panel")

	-- A bridge kiosk: teleported onto the bridge (the hold of a jump waited out: no stall rate
	-- for MarketJump.Penalty samples), he walks in and the server's samples give ×1.5.
	local kiosk = sim:Find("Workspace.Map.Bridges.Bridge_1.Lookout.SellKiosk.Scales.SellPromptAttachment")
	sim:Teleport(p, kiosk.WorldPosition + Vector3.new(0, 3, 24))
	sim:Advance(EconomyConfig.MarketJump.Penalty + 1.2, Kit.COARSE)
	t.ok(Kit.walkTo(sim, p, kiosk.WorldPosition + Vector3.new(3, 0, 0)), "the kid walks up to the kiosk")
	t.ok(sim:WaitFor(function()
		return p:GetAttribute("SellRatePct") == MARKET
	end, EconomyConfig.MarketDwell + 1.5, Kit.COARSE) == true, "the kiosk's rate after the dwell")
	t.eq(p:GetAttribute("SellPlace"), "Kiosk1")
	t.ok(sim:HoldPrompt(p, kiosk.SellPrompt), "the kiosk prompt")
	t.ok(sim:WaitFor(function()
		return hud.panel.Visible
	end, 2, Kit.FRAME) == true, "… opens the panel")
	sim:Advance(1)
	local slot3 = Kit.baseOf(sim, p).Tank.Slots.Slot_3
	local growFrom = slot3:GetAttribute("GrowFrom")
	local sold3 = Kit.sell(t, sim, p, hud, 3)
	local age = sim.workspace:GetServerTimeNow() - growFrom
	t.eq(sold3.Place, "Kiosk1")
	t.eq(sold3.RatePct, MARKET)
	t.ok(
		sold3.Amount >= R.SellPrice(values[3], age - 0.5, MARKET)
			and sold3.Amount <= R.SellPrice(values[3], age + 0.5, MARKET),
		`the young Crucian at ×1.5 of its value now ({sold3.Amount})`
	)
	sim:Advance(1.5)
	t.eq(hud.tankChip.Text, "0/6")
	Kit.ledgerHolds(t, sim, Kit.service(sim, "DataService"):Get(p), "after the sales")
	sim:AssertNoErrors({ warnings = true })
end

return tests
