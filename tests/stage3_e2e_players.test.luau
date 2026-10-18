--[[
	Stage 3 END-TO-END, part 4 — several players and a cheater (design §4.5, §4.7, §7.6): the real
	server and real clients (tests/stage3_e2e_kit.luau).

	  (9)  two players at once (a phone and a desktop) fish side by side: each catch lands in its
	       catcher's own tank and court, each «САДОК», Wallet and «Деньги» / «Доход/с» row is its
	       own; the other base's tank prompt is hidden on each client, and holding it anyway
	       opens nothing; the own prompt opens the own panel; a sale touches only the seller;
	  (10) a cheating client fires TankSell by hand: junk arguments (wrong types, NaN, a 200-char
	       string, bad patterns) are dropped without an answer, someone else's uid is
	       «Этой рыбы уже нет», 100 sells of an own fish in one frame pay once and answer at most
	       Burst times; the honest player's panel keeps working, nothing errors.

	Run: lune run tools/run_tests.luau stage3_e2e_players
]]

local roblox = require("@lune/roblox")
local Kit = require("./stage3_e2e_kit")

local Vector3 = roblox.Vector3

local TEXTS = Kit.TEXTS
local TankConfig = Kit.TankConfig

local tests = {}

local function promptOf(base: any): any
	return base.Tank.Glass.PromptAttachment:FindFirstChild("TankPrompt")
end

-- Stands next to a base's big tank (its prompt is on Tank.Glass).
local function toTank(sim: any, p: any, base: any)
	sim:Teleport(p, promptOf(base).Parent.WorldPosition + Vector3.new(0, 1, 4))
	sim:Advance(0.3)
end

tests["(9) two players at once: each catch in its own tank, court, «САДОК», Wallet and leaderstats; the other's tank prompt hidden and dead; the own one opens the own panel; a sale touches only the seller"] = function(
	t
)
	local sim = Kit.boot(t)
	local a = Kit.join(t, sim, 1, "phone")
	local b = Kit.join(t, sim, 2, "desktop")
	local hudA, hudB = Kit.hud(sim, a), Kit.hud(sim, b)
	local R = Kit.shared(sim, "TankRules")
	local baseA, baseB = Kit.baseOf(sim, a), Kit.baseOf(sim, b)
	t.ok(baseA ~= baseB, "two bases")
	local log = Kit.moneyLog(sim)

	-- Both fish at the same time (the bites, hooks and minigames interleave).
	Kit.goFish(t, sim, a)
	Kit.goFish(t, sim, b)
	Kit.forceFish(sim, "Puffer", 1.5)
	local _, puffer10 = Kit.priceOf(sim, "Puffer", 1.5)
	local fa, fb = Kit.Fisher.new(sim, a, hudA), Kit.Fisher.new(sim, b, hudB)
	fa:cast()
	sim:Advance(0.2)
	fb:cast()
	t.ok(Kit.play(sim, { fa, fb }, 30), `both tries end\n{fa:describe()}\n{fb:describe()}`)
	t.eq(fa.stage, "caught", "A caught")
	t.eq(fb.stage, "caught", "B caught")
	Kit.landed(t, sim, a, hudA)
	Kit.landed(t, sim, b, hudB)
	-- B catches one more on its own.
	Kit.forceFish(sim, "Perch", 1)
	local _, perch10 = Kit.priceOf(sim, "Perch", 1)
	Kit.catch(t, sim, b, hudB, "B's second fish")
	Kit.landed(t, sim, b, hudB)

	t.eq(a:GetAttribute("TankCount"), 1, "A: one fish")
	t.eq(b:GetAttribute("TankCount"), 2, "B: two fish")
	t.eq(hudA.tankChip.Text, "1/6", "A's «САДОК»")
	t.eq(hudB.tankChip.Text, "2/6", "B's «САДОК»")
	t.eq(baseA.Tank.Slots.Slot_1:GetAttribute("FishId"), "Puffer", "A's Slot_1")
	t.eq(baseA.Tank.Slots.Slot_2:GetAttribute("State"), "empty", "A's Slot_2 is empty")
	t.eq(baseB.Tank.Slots.Slot_2:GetAttribute("FishId"), "Perch", "B's Slot_2")
	t.eq(hudA.rate.Text, R.FormatRate(puffer10), "A's Wallet rate")
	t.eq(hudB.rate.Text, R.FormatRate(puffer10 + perch10), "B's Wallet rate")
	local _, incomeA = Kit.leader(a)
	local _, incomeB = Kit.leader(b)
	t.eq(incomeA, math.floor(puffer10 / 10 + 0.5), "A's «Доход/с»")
	t.eq(incomeB, math.floor((puffer10 + perch10) / 10 + 0.5), "B's «Доход/с»")
	t.eq(a.leaderstats[Kit.EconomyConfig.Leaderstats.Money].Value, a:GetAttribute("Money"), "A's «Деньги»")
	t.eq(b.leaderstats[Kit.EconomyConfig.Leaderstats.Money].Value, b:GetAttribute("Money"), "B's «Деньги»")
	t.eq(baseA.Tank:GetAttribute("Count"), 1, "A's Tank model: Count")
	t.eq(baseB.Tank:GetAttribute("Count"), 2, "B's Tank model: Count")

	-- The tank prompts: hidden on the other's base (client-local), the server checks the owner.
	local promptA, promptB = promptOf(baseA), promptOf(baseB)
	t.ok(promptA and promptB, "every base has its TankPrompt")
	t.eq(promptA.Enabled, true, "A's own tank prompt is on")
	local function seenBy(viewer: any, prompt: any): boolean
		return sim:Run(function()
			return prompt.Enabled
		end, viewer)
	end
	t.eq(seenBy(a, promptA), true, "A's client shows A's tank prompt")
	t.eq(seenBy(b, promptB), true, "B's client shows B's own")
	local opensA = #Kit.tankEvents(sim, a, "Open")
	-- A walks up to B's big tank: A's client builds B's base (within Display.Range) and hides its
	-- prompt there (only on A's screen: the server keeps it on for B).
	toTank(sim, a, baseB)
	sim:Advance(TankConfig.Display.CheckEvery * 2 + 0.1)
	t.eq(seenBy(a, promptB), false, "A's client hides B's tank prompt")
	t.eq(seenBy(b, promptB), true, "… B's client still shows it")
	sim:HoldPrompt(a, promptB, nil, { ignoreEnabled = true })
	sim:Advance(0.5)
	t.eq(#Kit.tankEvents(sim, a, "Open"), opensA, "holding B's tank prompt anyway opens nothing for A")
	t.eq(hudA.panel.Visible, false, "A's panel stays closed")
	toTank(sim, a, baseA)
	t.ok(sim:HoldPrompt(a, promptA), "A holds the own tank prompt")
	t.ok(sim:WaitFor(function()
		return hudA.panel.Visible
	end, 2, Kit.FRAME) == true, "… and the panel opens")
	t.eq(Kit.tankEvents(sim, a, "Open")[opensA + 1].Place, "Tank")
	sim:Advance(0.8)
	t.ok(Kit.card(hudA, 1):FindFirstChild("Sell"), "A's panel: A's Puffer")
	t.eq(Kit.card(hudA, 2).Title.Text, TEXTS.Empty, "… and not B's Perch")

	-- A sells; B is untouched.
	local moneyB = b:GetAttribute("Money")
	local soldBefore = #Kit.tankEvents(sim, b, "Sold")
	local sold = Kit.sell(t, sim, a, hudA, 1)
	t.eq(Kit.earned(log, a, "sell"), sold.Amount, "A is paid")
	t.eq(Kit.earned(log, b, "sell"), 0, "B is not")
	sim:Advance(1)
	t.eq(a:GetAttribute("TankCount"), 0, "A's tank is empty")
	t.eq(b:GetAttribute("TankCount"), 2, "B still has both fish")
	t.eq(#Kit.tankEvents(sim, b, "Sold"), soldBefore, "B got no Sold")
	t.ok(b:GetAttribute("Money") >= moneyB, "B's money only grows (income)")
	Kit.openPanel(t, sim, b, hudB)
	t.ok(Kit.card(hudB, 1):FindFirstChild("Sell") and Kit.card(hudB, 2):FindFirstChild("Sell"), "B's panel: both fish")
	sim:AssertNoErrors({ warnings = true })
end

tests["(10) a cheating client: junk TankSell args dropped silently, someone else's uid denied, 100 sells in a frame pay once (≤ Burst answers); the honest panel still works"] = function(
	t
)
	local sim = Kit.boot(t)
	Kit.pokeSave(sim, 1, { Money = 10, Tank = { Kit.savedFish("Perch", "f1", 1, { Kg = 1 }) } })
	Kit.pokeSave(sim, 2, {
		Money = 10,
		Tank = {
			Kit.savedFish("Perch", "f1", 1, { Kg = 1 }),
			Kit.savedFish("Puffer", "f2", 2, { Kg = 1 }),
			Kit.savedFish("SharkPup", "f3", 3, { Kg = 20 }),
		},
	})
	local cheat = Kit.join(t, sim, 1, "phone")
	local honest = Kit.join(t, sim, 2, "phone")
	local hudC, hudH = Kit.hud(sim, cheat), Kit.hud(sim, honest)
	local seenC = Kit.toasts(hudC)
	local log = Kit.moneyLog(sim)
	sim:Advance(2)

	-- Junk: wrong types, NaN, inf, a 200-char string, bad patterns — no answer at all.
	local answers = #sim:ClientEventsFor(cheat, "TankEvent")
	local junk =
		{ 5, {}, { Uid = "f1" }, 0 / 0, math.huge, string.rep("f", 200), "f1x", "F1", "f", "f-1", "f 1", "", true }
	for _, value in junk do
		sim:FireServer(cheat, "TankSell", value)
	end
	sim:FireServer(cheat, "TankSell")
	sim:Advance(0.2)
	t.eq(#sim:ClientEventsFor(cheat, "TankEvent"), answers, "junk is dropped without an answer")
	t.eq(cheat:GetAttribute("TankCount"), 1, "nothing sold")

	-- Someone else's uid: the honest player's SharkPup is "f3"; the cheater has no "f3".
	sim:FireServer(cheat, "TankSell", "f3")
	sim:Advance(0.3)
	local denied = Kit.tankEvents(sim, cheat, "Denied")
	t.eq(#denied, 1, "one answer")
	t.eq(denied[1].Reason, "missing", "«missing»")
	t.eq(denied[1].Text, TEXTS.Denied.missing)
	sim:Advance(1)
	t.ok(seenC[TEXTS.Denied.missing] ~= nil, `the cheater's screen: «{TEXTS.Denied.missing}»`)
	t.eq(honest:GetAttribute("TankCount"), 3, "the honest tank is untouched")
	t.eq(Kit.baseOf(sim, honest).Tank.Slots.Slot_3:GetAttribute("FishUid"), "f3", "… the SharkPup is still there")

	-- 100 sells of the own fish in one frame: paid once, answers bounded by the bucket.
	sim:Advance(3)
	local before = #sim:ClientEventsFor(cheat, "TankEvent")
	for _ = 1, 100 do
		sim:FireServer(cheat, "TankSell", "f1")
	end
	sim:Advance(0.3)
	local got = #sim:ClientEventsFor(cheat, "TankEvent") - before
	t.ok(got >= 1 and got <= TankConfig.Requests.Burst, `{got} answers ≤ Burst {TankConfig.Requests.Burst}`)
	local _, sales = Kit.earned(log, cheat, "sell")
	t.eq(sales, 1, "sold exactly once")
	t.eq(Kit.earned(log, cheat, "sell"), Kit.tankEvents(sim, cheat, "Sold")[1].Amount, "paid exactly once")
	t.eq(cheat:GetAttribute("TankCount"), 0)
	t.eq(Kit.service(sim, "DataService"):Get(cheat).Stats.Sold, 1, "Stats.Sold 1")

	-- The honest player was never touched and sells through the panel as usual.
	t.eq(Kit.earned(log, honest, "sell"), 0, "no money moved for the honest player")
	Kit.openPanel(t, sim, honest, hudH)
	local sold, kind = Kit.sell(t, sim, honest, hudH, 3)
	t.eq(kind, "Sold", "the honest sale goes through")
	t.eq(sold.Items[1].Uid, "f3")
	sim:Advance(1)
	t.eq(honest:GetAttribute("TankCount"), 2)
	Kit.ledgerHolds(t, sim, Kit.service(sim, "DataService"):Get(cheat), "the cheater")
	Kit.ledgerHolds(t, sim, Kit.service(sim, "DataService"):Get(honest), "the honest player")
	sim:AssertNoErrors({ warnings = true })
end

return tests
