--[[
	Stage 3 END-TO-END, part 1 — the loop (design §1.1, §7.6 items 1–3 and 7): the real server
	(every service, real persistence in the sim DataStore) and the real client of a phone player,
	nothing stubbed; the player only stands, taps and reads the screen (the bot of
	tests/stage3_e2e_kit.luau), the one server hook forces the next fish.

	  (1) at the REAL numbers (Growth.Time 300 s, real bites): join → the Wallet «$0», «САДОК 0/6»
	      and the pier word «🐠 0/6» → a catch → the card says «цена $N», «В САДОК!» → the card flies
	      into «САДОК» → «1/6», the Wallet's «+$X/с», the pier word «🐠 1/6» with a splash, the fish
	      in its court display (centred), its tag «+$X/с · $N ▲» and the big tank's sign; the
	      first-fish toast and the «!» → money ticks every second (≈ income × 30 s, Wallet and
	      «Деньги» agree) → five minutes later the fish is at «МАКС» (×3: the tag and the card) →
	      «САДОК» opens the panel (the «!» goes out) → a two-tap sale → +×3 value, the card turns
	      empty, the court fish shrinks away, «0/6», no income;
	  (2) remoteLatency 0.15 (a 0.3 s round trip): the same catch → «В САДОК!» → «1/6», and the
	      panel's sale shows ⏳ until the server's answer arrives.
	Parts 2–4: stage3_e2e_tank (full tank, stalls), stage3_e2e_save (persistence, shutdown, Studio
	memory mode), stage3_e2e_players (two players, TankSell exploits).

	Run: lune run tools/run_tests.luau stage3_e2e.test
]]

local Kit = require("./stage3_e2e_kit")

local TEXTS = Kit.TEXTS
local TankConfig = Kit.TankConfig
local FishingConfig = Kit.FishingConfig

local tests = {}

-- The TankWorld folder's new ParticleEmitters from now on (the splash at the bucket, slot FX).
local function emitterLog(world: any): { any }
	local log = {}
	world.Stats().folder.DescendantAdded:Connect(function(d)
		if d:IsA("ParticleEmitter") then
			table.insert(log, d)
		end
	end)
	return log
end

tests["(1) phone, real numbers: catch → «В САДОК!» → «САДОК 1/6», the pier bucket and the court display; money ticks; ×3 «МАКС» after 5 min; a two-tap sale"] = function(
	t
)
	local sim = Kit.boot(t)
	local p = Kit.join(t, sim, 1, "phone")
	local hud = Kit.hud(sim, p)
	local R = Kit.shared(sim, "TankRules")
	local world = Kit.client(sim, p, "TankWorldController")
	local base = Kit.baseOf(sim, p)
	local log = Kit.moneyLog(sim)
	local seen = Kit.toasts(hud)

	-- The chrome after the base banner: badge → Wallet «$0» → «САДОК 0/6» (design §1.1 step 1).
	t.ok(
		sim:WaitFor(function()
			return hud.wallet.Visible and hud.tank.Visible
		end, 5, Kit.FRAME),
		"the Wallet and «САДОК» pop in after the base banner"
	)
	sim:Advance(1)
	t.eq(p:GetAttribute("DataMode"), "Ready", "the save is loaded (DataMode Ready)")
	t.eq(hud.money.Text, "$0", "the Wallet: «$0»")
	t.eq(hud.rate.Visible, false, "no «+$/с» while nothing earns")
	t.eq(hud.tankChip.Text, "0/6", "«САДОК» 0/6")
	t.eq(hud.badge.Visible, false, "no «!» yet")
	local money0, income0 = Kit.leader(p)
	t.eq(money0, 0, "leaderstats «Деньги» 0")
	t.eq(income0, 0, "leaderstats «Доход/с» 0")
	local word = world.GetPierWord()
	t.ok(word and word.Enabled, "the pier word over the bucket")
	t.eq(word.Plate.Count.Text, "🐠 0/6", "the pier word «🐠 0/6»")
	t.eq(world.GetFish(base, 1), nil, "an empty court")

	-- The catch (a forced Puffer: one Rare, 2 kg).
	Kit.goFish(t, sim, p)
	Kit.forceFish(sim, "Puffer", 2)
	local value, income10 = Kit.priceOf(sim, "Puffer", 2)
	local splashes = emitterLog(world)
	local caught = Kit.catch(t, sim, p, hud, "the first catch")
	t.eq(caught.Fish.Id, "Puffer")
	t.eq(caught.Fish.Uid, "f1", "the payload names the fish's Uid")
	t.eq(caught.Fish.New, true, "a new species («НОВИНКА!»)")
	t.eq(caught.Tank.Result, "stored", "server: stored in the tank")
	t.eq(caught.Tank.Slot, 1, "… in the lowest free display")
	t.eq(caught.Tank.First, true, "… the first fish ever")
	t.eq(p:GetAttribute("TankCount"), 1, "server: TankCount 1")
	local slot1 = base.Tank.Slots.Slot_1
	t.eq(slot1:GetAttribute("State"), "fish", "Slot_1 holds a fish")
	t.eq(slot1:GetAttribute("FishUid"), "f1")
	t.eq(slot1:GetAttribute("FishId"), "Puffer")
	t.eq(slot1:GetAttribute("Value"), value, "the display's Value (×1)")
	t.eq(slot1.Pedestal.LabelGui.Label.Text, Kit.fishDef("Puffer").Name, "the pedestal names the fish")

	-- The card: «2 кг · цена $N», then the stamp «В САДОК!»; «САДОК» waits for the 🐟.
	t.ok(
		string.find(hud.cardInfo.Text, `цена {R.FormatMoney(value)}`, 1, true) ~= nil,
		`the card: «{hud.cardInfo.Text}»`
	)
	t.ok(sim:WaitFor(function()
		return hud.stamp.Visible
	end, 4, Kit.FRAME) == true, "the tank stamp slaps onto the card")
	t.eq(hud.stampLabel.Text, TEXTS.Stamp.stored, "«В САДОК!»")
	t.eq(hud.tankChip.Text, "0/6", "«САДОК» keeps 0/6 while the card is up")
	t.eq(hud.screen:GetAttribute("CounterHold"), 0, "… held by the catch")
	t.eq(word.Enabled, false, "the pier word hides while the catch is on screen")

	-- The flight: the card flies into «САДОК».
	Kit.landed(t, sim, p, hud, "the first catch")
	t.eq(hud.tankChip.Text, "1/6", "the 🐟 landed: «САДОК» 1/6")
	t.ok(hud.rate.Visible, "the Wallet shows the income now")
	t.eq(hud.rate.Text, R.FormatRate(income10), "… «+$X/с» of the fish")
	t.ok(hud.badge.Visible, "the onboarding «!» on «САДОК»")
	t.ok(#splashes >= 1, "a splash at the pier bucket when the fish went in")
	t.ok(
		sim:WaitFor(function()
			return p.Character:FindFirstChild("HeldFish") == nil
		end, FishingConfig.HoldFishTime.Rare + 1, Kit.COARSE),
		"the trophy over the head is gone"
	)
	sim:Advance(0.5)
	t.ok(word.Enabled, "the pier word is back")
	t.eq(word.Plate.Count.Text, "🐠 1/6", "the pier word «🐠 1/6»")
	t.eq(word.Plate.Rate.Text, R.FormatRate(income10), "… and «+$X/с»")
	sim:Advance(2)
	t.eq(seen[TEXTS.FirstFish], 1, `the first-fish toast «{TEXTS.FirstFish}»`)

	-- The court: the fish in its display, centred; its tag; the big tank's sign.
	local model = world.GetFish(base, 1)
	t.ok(model, "the client built the fish in Slot_1's display (the court is ≈ 155 studs from the spot)")
	t.eq(model:GetAttribute("FishId"), "Puffer", "… the caught species")
	local box = model:GetBoundingBox()
	local point = slot1.Display.FishPoint
	local at = if point:IsA("Attachment") then point.WorldPosition else point.Position
	t.ok((box.Position - at).Magnitude < 0.15, "… centred on the display's FishPoint")
	local tag = world.GetTag(base, 1)
	t.ok(tag, "the slot's tag")
	t.eq(tag.Plate.Rate.Text, R.FormatRate(income10), "the tag «+$X/с»")
	local sign = world.GetSign(base)
	t.ok(sign and sign.Enabled, "the big tank's sign")
	t.eq(sign.Plate.Rate.Text, R.FormatRate(income10), "the sign «+$X/с»")
	t.eq(sign.Plate.Count.Text, "🐠 1/6", "the sign «🐠 1/6»")

	-- Money ticks every second: ≈ income × 30 s; the Wallet and «Деньги» say the same.
	local m0 = p:GetAttribute("Money")
	sim:Advance(30)
	local m1 = p:GetAttribute("Money")
	local expected = 30 * income10 / 10
	t.ok(math.abs(m1 - m0 - expected) <= income10 / 10 + 1, `30 s of income: +{m1 - m0} (≈ {expected})`)
	t.ok(sim:WaitFor(function()
		return hud.money.Text == R.FormatMoney(p:GetAttribute("Money"))
	end, 1.5, Kit.FRAME) == true, `the Wallet shows the money («{hud.money.Text}»)`)
	local money, income = Kit.leader(p)
	t.eq(money, p:GetAttribute("Money"), "leaderstats «Деньги»")
	t.eq(income, math.floor(income10 / 10 + 0.5), "leaderstats «Доход/с»")
	local fromIncome, ticks = Kit.earned(log, p, "income")
	t.eq(fromIncome, p:GetAttribute("Money"), "every coin so far is income")
	t.ok(ticks >= 30, "credited every second (whole coins, the tenths carried)")

	-- Five minutes of tank time: ×3, «МАКС». The kid walks over to the court to look: the tag
	-- (refreshed only within TagRange, shown within TagShow) says «$3V МАКС», the fish lives.
	sim:Advance(TankConfig.Growth.Time, 0.1)
	local maxed = R.CurrentValue(value, TankConfig.Growth.Time)
	t.eq(maxed, math.floor(value * TankConfig.Growth.Cap), "the value grew ×3")
	t.eq(world.IsAlive(base, 1), false, "from the fishing spot the court fish is still (no tween)")
	local front = tag.Parent.WorldPosition
	t.ok(Kit.walkTo(sim, p, front), "the kid walks to Slot_1's display")
	sim:Advance(TankConfig.Display.TagEvery + TankConfig.Display.CheckEvery + 0.2)
	t.eq(
		tag.Plate.Value.Text,
		Kit.fill(TEXTS.TagMax, { price = R.FormatMoney(maxed), max = TEXTS.Max }),
		"the court tag says «$N МАКС»"
	)
	t.ok(world.IsAlive(base, 1), "up close the fish bobs in its display (a looped tween)")

	-- «САДОК» → the panel: the fish card at «МАКС», «💵 $3V»; the «!» goes out.
	Kit.openPanel(t, sim, p, hud)
	t.eq(hud.badge.Visible, false, "the first open puts the «!» out")
	local card = Kit.card(hud, 1)
	t.ok(card.Growth.Max.Visible, "the card says «МАКС»")
	local price = R.SellPrice(value, TankConfig.Growth.Time, 100)
	t.eq(
		card.Sell.Caption.Text,
		Kit.fill(TEXTS.SellPhone, { price = R.FormatMoney(price) }),
		"«💵 $N» on the button"
	)
	t.eq(hud.header.Total.Text, Kit.fill(TEXTS.TotalDone, { money = R.FormatMoney(price) }), "the header total")
	t.eq(Kit.card(hud, 2).Title.Text, TEXTS.Empty, "the other cards are empty …")
	t.ok(Kit.card(hud, "locked"), "… and one locked teaser")

	-- The two-tap sale.
	local before = p:GetAttribute("Money")
	local sold, kind = Kit.sell(t, sim, p, hud, 1)
	t.eq(kind, "Sold", "the server sold it")
	t.eq(sold.Amount, price, "at its ×3 value")
	t.eq(sold.RatePct, 100, "at home (×1)")
	t.eq(sold.Items[1].Uid, "f1")
	t.eq(Kit.earned(log, p, "sell"), price, "server: +price for the sale")
	sim:Advance(2)
	t.eq(p:GetAttribute("TankCount"), 0, "server: the tank is empty")
	t.eq(slot1:GetAttribute("State"), "empty", "Slot_1 is empty")
	t.eq(slot1.Pedestal.LabelGui.Label.Text, TEXTS.SlotEmpty, "… «Пусто»")
	t.eq(Kit.card(hud, 1).Title.Text, TEXTS.Empty, "the card turned empty")
	t.eq(hud.tankChip.Text, "0/6", "«САДОК» 0/6")
	t.eq(world.GetFish(base, 1), nil, "the court fish shrank away")
	local after = p:GetAttribute("Money")
	t.ok(after >= before + price, `the money grew by the price (+{after - before})`)
	t.eq(hud.money.Text, R.FormatMoney(after), "the Wallet counted up to it")
	t.eq(hud.rate.Visible, false, "no income left: «+$/с» hides")
	local _, incomeLeft = Kit.leader(p)
	t.eq(incomeLeft, 0, "«Доход/с» 0")
	sim:Advance(3)
	t.eq(p:GetAttribute("Money"), after, "no more income")
	sim:AssertNoErrors({ warnings = true })
end

tests["(2) phone, remoteLatency 0.15: catch → «В САДОК!» → «1/6»; the panel's sale waits ⏳ for the answer"] = function(
	t
)
	local sim = Kit.boot(t, { latency = 0.15 })
	local p = Kit.join(t, sim, 1, "phone")
	local hud = Kit.hud(sim, p)
	local R = Kit.shared(sim, "TankRules")
	Kit.goFish(t, sim, p)
	Kit.forceFish(sim, "Perch", 1.2, "Gold")
	local value, income10 = Kit.priceOf(sim, "Perch", 1.2, "Gold")
	local caught = Kit.catch(t, sim, p, hud, "a catch over the lag")
	t.eq(caught.Tank.Result, "stored")
	t.eq(caught.Fish.Mutation, "Gold")
	t.ok(sim:WaitFor(function()
		return hud.stamp.Visible
	end, 4, Kit.FRAME) == true, "stamped")
	t.eq(hud.stampLabel.Text, TEXTS.Stamp.stored, "«В САДОК!»")
	Kit.landed(t, sim, p, hud, "the catch over the lag")
	t.eq(hud.tankChip.Text, "1/6")
	t.eq(hud.rate.Text, R.FormatRate(income10), "the Wallet's rate")
	sim:Advance(5)

	Kit.openPanel(t, sim, p, hud)
	local card = Kit.card(hud, 1)
	t.ok(card.Mutation.Visible, "the Gold mutation chip on the card")
	local sells = #sim:ServerEventsFor(p, "TankSell")
	sim:Click(p, card.Sell)
	sim:Advance(TankConfig.ConfirmArm + 0.1)
	sim:Click(p, card.Sell)
	sim:Advance(Kit.FRAME)
	t.eq(#sim:ServerEventsFor(p, "TankSell"), sells + 1, "TankSell sent")
	t.eq(card.Sell.Caption.Text, TEXTS.Busy, "⏳ while the answer travels back")
	t.ok(
		sim:WaitFor(function()
			return #Kit.tankEvents(sim, p, "Sold") == 1
		end, 1, Kit.FRAME),
		"the answer arrives after the round trip"
	)
	local sold = Kit.tankEvents(sim, p, "Sold")[1]
	t.ok(sold.Amount >= R.SellPrice(value, 0, 100), `sold at its value now ({sold.Amount})`)
	sim:Advance(1.5)
	t.eq(Kit.card(hud, 1).Title.Text, TEXTS.Empty, "the card turned empty")
	t.eq(hud.tankChip.Text, "0/6")
	t.eq(hud.money.Text, R.FormatMoney(p:GetAttribute("Money")), "the Wallet shows the money")
	sim:AssertNoErrors({ warnings = true })
end

return tests
