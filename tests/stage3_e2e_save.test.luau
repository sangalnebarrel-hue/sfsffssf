--[[
	Stage 3 END-TO-END, part 3 — saving (design §2, §7.6 items 6–7): the real server with real
	persistence in the sim DataStore and real clients (tests/stage3_e2e_kit.luau); a «restart» is
	a NEW sim on the old one's DataStore snapshot, an hour later, with a new server token.

	  (5) leave → the final save → a new server → rejoin: the same money, the same fish in the same
	      displays with the same ages (no growth while offline), the same slots — on the server, in
	      the court, in the Wallet, on «САДОК» and in the panel; the services keep nothing of a player
	      who left;
	  (6) BindToClose with 3 players (phone, tablet, desktop) who all just caught a fish: the
	      shutdown completes inside CloseBudget with exactly one final write per player, every
	      lock released; a new server gives everyone their money and fish back;
	  (7) Studio without API access (memory mode): one Output warning with the instructions, the
	      toast «💾 Studio: прогресс не сохраняется» once after the base banner, the game still plays
	      (catch → «В САДОК!», income), not one DataStore write; a rejoin starts from zero; the
	      shutdown is instant;
	  (8) a flaky DataStore and remoteLatency 0.15: the first load fails (the Wallet waits on glass
	      «$…», a cast says «Загружаем твой садок…»), the retry loads; the leave save fails twice
	      and still lands inside LeaveSaveWindow; the new server has it all.

	Run: lune run tools/run_tests.luau stage3_e2e_save
]]

local Kit = require("./stage3_e2e_kit")

local TEXTS = Kit.TEXTS
local DataConfig = Kit.DataConfig
local EconomyConfig = Kit.EconomyConfig
local FishingConfig = Kit.FishingConfig

local tests = {}

-- The player leaves; waits for the final save to release the lock; returns the saved value.
local function leave(t: any, sim: any, p: any): any
	sim:RemovePlayer(p)
	t.ok(sim:WaitFor(function()
		local saved = Kit.peek(sim, p.UserId)
		return saved ~= nil and saved.Session == nil
	end, DataConfig.LeaveSaveWindow + 2, Kit.COARSE) == true, `{p.Name}: the final save released the lock`)
	return Kit.peek(sim, p.UserId)
end

-- What the server shows of a player's tank: per slot { Uid, Id, Mutation, Kg, Value, Age }.
local function tankOf(sim: any, p: any): { [number]: any }
	local out = {}
	local now = sim.workspace:GetServerTimeNow()
	for _, slot in Kit.baseOf(sim, p).Tank.Slots:GetChildren() do
		if slot:GetAttribute("State") == "fish" then
			out[slot:GetAttribute("SlotIndex") or tonumber(string.match(slot.Name, "%d+"))] = {
				Uid = slot:GetAttribute("FishUid"),
				Id = slot:GetAttribute("FishId"),
				Mutation = slot:GetAttribute("Mutation"),
				Kg = slot:GetAttribute("Kg"),
				Value = slot:GetAttribute("Value"),
				Age = now - slot:GetAttribute("GrowFrom"),
			}
		end
	end
	return out
end

-- Shutdown, then: every save keeps its ledger and no lock of this server; writes ≥ 6 s apart.
local function finish(t: any, sim: any)
	local result = sim:Shutdown()
	t.ok(result.completed, "Shutdown completed")
	local token = Kit.service(sim, "DataService").Token
	for _, k in sim.DataStore:Keys(Kit.STORE) do
		local value = sim.DataStore:Peek(Kit.STORE, k)
		if type(value) == "table" and value.Stats then
			Kit.ledgerHolds(t, sim, value, k)
			t.ok(value.Session == nil or value.Session.Server ~= token, `{k}: no lock of this server left`)
		end
	end
	Kit.assertGaps(t, sim)
end

tests["(5) leave → save → a NEW server → rejoin: the same money, fish, ages (no offline growth) and slots — server, court, Wallet, «САДОК», panel"] = function(
	t
)
	local sim = Kit.boot(t)
	local p = Kit.join(t, sim, 1, "phone")
	local hud = Kit.hud(sim, p)
	Kit.goFish(t, sim, p)
	Kit.forceFish(sim, "Swordfish", 30, "Gold")
	Kit.catch(t, sim, p, hud, "the Gold Swordfish")
	Kit.landed(t, sim, p, hud)
	sim:Advance(20)
	Kit.forceFish(sim, "Perch", 1)
	Kit.catch(t, sim, p, hud, "the Perch")
	Kit.landed(t, sim, p, hud)
	sim:Advance(15)
	t.eq(hud.tankChip.Text, "2/6")

	local money = p:GetAttribute("Money")
	local fish = tankOf(sim, p)
	t.ok(fish[1] and fish[1].Id == "Swordfish" and fish[2] and fish[2].Id == "Perch", "two fish in Slot_1 and Slot_2")
	local saved = leave(t, sim, p)
	t.eq(saved.Money, money, "saved: the money at leave")
	t.eq(#saved.Tank, 2, "saved: two fish")
	t.eq(saved.TankSlots, Kit.TankConfig.StartSlots, "saved: the slots")
	t.eq(saved.Stats.Caught, 2, "saved: two caught")
	for _, f in saved.Tank do
		local live = fish[f.Slot]
		t.ok(live and live.Uid == f.Uid and live.Id == f.Id, `saved: {f.Uid} {f.Id} in slot {f.Slot}`)
		t.near(f.Age, live.Age, 0.2, `saved: {f.Uid}'s age`)
		t.eq(f.Rarity, nil, "Rarity is never stored (derived on load)")
		t.eq(f.Value, nil, "Value is never stored")
	end
	Kit.ledgerHolds(t, sim, saved, "the leave save")
	sim:Advance(10, Kit.COARSE)
	Kit.sizesZero(t, sim, "10 s after the last player left")
	sim:AssertNoErrors({ warnings = true })

	-- An hour later, another server.
	local later = Kit.restart(t, sim, 3600)
	t.ok(Kit.service(later, "DataService").Token ~= Kit.service(sim, "DataService").Token, "a new server token")
	local joinAt = later:Time()
	local back = Kit.join(t, later, 1, "phone")
	local hud2 = Kit.hud(later, back)
	local R = Kit.shared(later, "TankRules")
	local since = later:Time() - joinAt
	local income10 = 0
	for _, f in saved.Tank do
		local _, i10 = Kit.priceOf(later, f.Id, f.Kg, f.Mutation)
		income10 += i10
	end
	t.ok(
		back:GetAttribute("Money") - money >= 0
			and back:GetAttribute("Money") - money <= math.ceil((since + 1) * income10 / 10),
		`the same money (+ the income since the rejoin): {money} → {back:GetAttribute("Money")}`
	)
	t.eq(back:GetAttribute("TankCount"), 2, "the same two fish")
	t.eq(back:GetAttribute("TankSlots"), Kit.TankConfig.StartSlots, "the same slots")
	local now = tankOf(later, back)
	for _, f in saved.Tank do
		local live = now[f.Slot]
		t.ok(live, `slot {f.Slot} holds a fish again`)
		t.eq(live.Uid, f.Uid, `slot {f.Slot}: the same Uid`)
		t.eq(live.Id, f.Id, `slot {f.Slot}: the same species`)
		t.eq(live.Mutation, f.Mutation, `slot {f.Slot}: the same mutation`)
		t.near(live.Kg, f.Kg, 1e-6, `slot {f.Slot}: the same weight`)
		t.ok(
			live.Age >= f.Age - 0.2 and live.Age <= f.Age + since + 0.2,
			`slot {f.Slot}: the same age, no growth while offline ({f.Age} → {live.Age})`
		)
	end
	-- The screens show it.
	later:Advance(2)
	t.eq(hud2.tankChip.Text, "2/6", "«САДОК» 2/6")
	t.eq(hud2.money.Text, R.FormatMoney(back:GetAttribute("Money")), "the Wallet shows the money")
	t.eq(hud2.rate.Text, R.FormatRate(income10), "… and the income")
	local money2, income2 = Kit.leader(back)
	t.eq(money2, back:GetAttribute("Money"), "leaderstats «Деньги»")
	t.eq(income2, math.floor(income10 / 10 + 0.5), "leaderstats «Доход/с»")
	local world = Kit.client(later, back, "TankWorldController")
	local base = Kit.baseOf(later, back)
	later:WaitFor(function()
		return world.GetFish(base, 2) ~= nil
	end, 3, Kit.COARSE)
	local sword = world.GetFish(base, 1)
	t.ok(sword and sword:GetAttribute("FishId") == "Swordfish", "the court shows the Swordfish again")
	t.eq(sword and sword:GetAttribute("Mutation"), "Gold", "… Gold")
	t.ok(world.GetFish(base, 2), "… and the Perch")
	Kit.openPanel(t, later, back, hud2)
	local nowAge = later.workspace:GetServerTimeNow() - base.Tank.Slots.Slot_1:GetAttribute("GrowFrom")
	local value = base.Tank.Slots.Slot_1:GetAttribute("Value")
	local caption = Kit.card(hud2, 1).Sell.Caption.Text
	local shown = tonumber((string.gsub(caption, "%D", "")))
	local low = R.SellPrice(value, nowAge - 1.1, 100) -- the panel ticks once a second
	local high = R.SellPrice(value, nowAge + 0.1, 100)
	t.ok(
		shown ~= nil and shown >= low and shown <= high,
		`the panel prices the fish by its saved age («{caption}», {low}..{high})`
	)
	t.eq(Kit.card(hud2, 3).Title.Text, TEXTS.Empty, "slot 3 is still empty")
	finish(t, later)
	later:AssertNoErrors({ warnings = true })
end

tests["(6) BindToClose with 3 players who just caught: one final write each inside CloseBudget, locks released; a new server gives it all back"] = function(
	t
)
	local sim = Kit.boot(t)
	local devices = { "phone", "tablet", "desktop" }
	for id = 1, 3 do
		Kit.pokeSave(sim, id, { Money = id * 100 })
	end
	local players, huds, fishers = {}, {}, {}
	for id = 1, 3 do
		players[id] = Kit.join(t, sim, id, devices[id])
		huds[id] = Kit.hud(sim, players[id])
	end
	for id = 1, 3 do
		Kit.goFish(t, sim, players[id])
	end
	Kit.forceFish(sim, "Puffer", 1.5)
	-- All three fish at once (bites, hooks and minigames interleave).
	for id = 1, 3 do
		fishers[id] = Kit.Fisher.new(sim, players[id], huds[id])
		fishers[id]:cast()
		sim:Advance(0.1)
	end
	t.ok(Kit.play(sim, fishers, 30), "all three tries end")
	for id = 1, 3 do
		t.eq(fishers[id].stage, "caught", `player {id} caught\n{fishers[id]:describe()}`)
	end
	for id = 1, 3 do
		Kit.landed(t, sim, players[id], huds[id])
		t.eq(huds[id].tankChip.Text, "1/6", `player {id}: «САДОК» 1/6`)
	end
	sim:Advance(8)
	-- Let the autosaves in flight land (one final write each is counted from here).
	local data = Kit.service(sim, "DataService")
	sim:WaitFor(function()
		for _, p in players do
			local rec = data._recordFor(p)
			if rec and (rec.InFlight or rec.Queued) then
				return false
			end
		end
		return true
	end, 10, Kit.COARSE)
	sim.DataStore:ClearCalls()
	local money = {}
	for id = 1, 3 do
		money[id] = players[id]:GetAttribute("Money")
	end
	local result = sim:Shutdown()
	t.ok(result.completed, "the shutdown completed")
	t.ok(result.elapsed < DataConfig.CloseBudget, `inside CloseBudget ({result.elapsed} s)`)
	for id = 1, 3 do
		t.eq(Kit.writes(sim, id), 1, `player {id}: exactly one final write`)
		local saved = Kit.peek(sim, id)
		t.eq(saved.Session, nil, `player {id}: the lock is released`)
		t.eq(saved.Money, money[id], `player {id}: the money at the shutdown`)
		t.eq(#saved.Tank, 1, `player {id}: the fish`)
		t.ok(saved.Tank[1].Age > 0, `player {id}: its age`)
		Kit.ledgerHolds(t, sim, saved, `player {id}`)
	end
	sim:AssertNoErrors({ warnings = true })

	local later = Kit.restart(t, sim, 600)
	for id = 1, 3 do
		local back = Kit.join(t, later, id, devices[id])
		local hud = Kit.hud(later, back)
		t.ok(back:GetAttribute("Money") >= money[id], `player {id}: the money is back`)
		t.eq(back:GetAttribute("TankCount"), 1, `player {id}: the fish is back`)
		later:Advance(1.5)
		t.eq(hud.tankChip.Text, "1/6", `player {id}: «САДОК» 1/6`)
	end
	finish(t, later)
	later:AssertNoErrors({ warnings = true })
end

tests["(7) Studio without API access: one warning, the «прогресс не сохраняется» toast once, the game plays, zero writes, a rejoin starts from zero, an instant shutdown"] = function(
	t
)
	local sim = Kit.boot(t, {
		before = function(s: any)
			s.DataStore:SetEnabled(false)
		end,
	})
	t.eq(Kit.service(sim, "DataService"):Mode(), "Memory", "memory mode")
	t.eq(Kit.takeWarnings(sim, DataConfig.Texts.MemoryWarn), 1, "one Output warning with the instructions")
	local p = sim:AddPlayer({ UserId = 1, Name = "Keeper1", device = "phone" })
	local hud
	sim:WaitFor(function()
		hud = p:FindFirstChild("PlayerGui") and p.PlayerGui:FindFirstChild("HUD")
		return hud ~= nil and hud:FindFirstChild("Toasts") ~= nil
	end, 5, Kit.FRAME)
	local seen = Kit.toasts({ toasts = hud.Toasts })
	t.ok(
		sim:WaitFor(function()
			return p:GetAttribute("BaseIndex") ~= nil and p.Character ~= nil
		end, 10, Kit.COARSE),
		"a base and a character"
	)
	t.eq(p:GetAttribute("DataMode"), "Memory", "DataMode Memory")
	sim:Advance(8)
	t.eq(seen[DataConfig.Texts.MemoryToast], 1, `the toast «{DataConfig.Texts.MemoryToast}» once`)
	local h = Kit.hud(sim, p)
	t.ok(h.wallet.Visible, "the Wallet shows (memory mode is playable)")
	t.eq(h.money.Text, "$0")

	-- The game plays: a catch lands in the tank, money ticks.
	Kit.goFish(t, sim, p)
	Kit.forceFish(sim, "Puffer", 1)
	local caught = Kit.catch(t, sim, p, h, "a catch in memory mode")
	t.eq(caught.Tank.Result, "stored", "stored")
	Kit.landed(t, sim, p, h)
	t.eq(h.tankChip.Text, "1/6")
	sim:Advance(5)
	t.ok(p:GetAttribute("Money") > 0, "income ticks")
	sim:Advance(8)
	t.eq(seen[DataConfig.Texts.MemoryToast], 1, "the memory toast never again this session")
	t.eq(sim.DataStore:CountCalls("UpdateAsync"), 0, "not one write")

	-- Leave and rejoin the same server: nothing was kept.
	sim:RemovePlayer(p)
	sim:Advance(2)
	t.eq(sim.DataStore:CountCalls("UpdateAsync"), 0, "no write on leave")
	local back = Kit.join(t, sim, 1, "phone")
	t.eq(back:GetAttribute("DataMode"), "Memory")
	t.eq(back:GetAttribute("Money"), 0, "a rejoin starts from $0 (progress is not saved in memory mode)")
	t.eq(back:GetAttribute("TankCount"), 0, "… with an empty tank")
	local closed = sim:Shutdown()
	t.ok(closed.completed and closed.elapsed < 0.5, `an instant shutdown ({closed.elapsed} s)`)
	t.eq(sim.DataStore:CountCalls("UpdateAsync"), 0, "still zero writes")
	t.eq(Kit.takeWarnings(sim, DataConfig.Texts.MemoryWarn), 0, "the warning was printed once, at boot")
	sim:AssertNoErrors({ warnings = true })
end

tests["(8) a flaky DataStore over remoteLatency 0.15: the first load fails (Wallet «$…», «Загружаем твой садок…»), the retry loads; the leave save fails twice and still lands"] = function(
	t
)
	local sim = Kit.boot(t, { latency = 0.15 })
	sim.DataStore:FailNext(1, nil, { "UpdateAsync" })
	local p = Kit.join(t, sim, 1, "phone", { loading = true })
	local hud = Kit.hud(sim, p)
	t.eq(p:GetAttribute("DataMode"), "Loading", "the first load failed: still loading")
	sim:Advance(Kit.UIConfig.Wallet.LoadingAfter + 0.5)
	-- The retry waits for the key's write gap (≈ 6 s after the failed attempt).
	t.eq(p:GetAttribute("DataMode"), "Loading", "still loading after 3.5 s")
	t.ok(hud.wallet.Visible, "after 3 s the Wallet waits on glass …")
	t.eq(hud.money.Text, EconomyConfig.Format.Loading, "… «$…» (the money is not gone)")
	-- A cast now: the server says the tank is still loading.
	Kit.goFish(t, sim, p)
	sim:Click(p, hud.action)
	t.ok(sim:WaitFor(function()
		return hud.hint.Visible and hud.hint.Text == FishingConfig.Texts.Denied.loading
	end, 2, Kit.FRAME) == true, `a cast while loading: «{FishingConfig.Texts.Denied.loading}»`)
	t.ok(sim:WaitFor(function()
		return p:GetAttribute("DataMode") == "Ready"
	end, 15, Kit.COARSE) == true, "the retry loads the save")
	t.eq(
		Kit.takeWarnings(sim, "загрузка игрока 1 не удалась"),
		1,
		"one warning for the failed attempt"
	)
	sim:Advance(1.5)
	t.eq(hud.money.Text, "$0", "the Wallet: «$0» (off the glass)")

	Kit.goFish(t, sim, p)
	sim:Advance(FishingConfig.CastCooldown + 0.5)
	Kit.forceFish(sim, "Perch", 1.5, "Gold")
	local caught = Kit.catch(t, sim, p, hud, "the catch after the retry")
	t.eq(caught.Tank.Result, "stored")
	Kit.landed(t, sim, p, hud)
	sim:Advance(10)
	local money = p:GetAttribute("Money")

	sim.DataStore:FailNext(2, nil, { "UpdateAsync" })
	local leftAt = sim:Time()
	local saved = leave(t, sim, p)
	t.ok(sim:Time() - leftAt <= DataConfig.LeaveSaveWindow, "inside LeaveSaveWindow")
	t.eq(
		Kit.takeWarnings(sim, "сохранение игрока 1 не удалось"),
		2,
		"two warnings for the failed attempts"
	)
	t.eq(saved.Money, money, "saved: the money")
	t.eq(#saved.Tank, 1, "saved: the fish")
	t.eq(saved.Tank[1].Mutation, "Gold")
	Kit.assertGaps(t, sim)
	sim:AssertNoErrors({ warnings = true })

	local later = Kit.restart(t, sim, 120, { latency = 0.15 })
	local back = Kit.join(t, later, 1, "phone")
	local hud2 = Kit.hud(later, back)
	t.ok(back:GetAttribute("Money") >= money, "the money is back")
	t.eq(back:GetAttribute("TankCount"), 1, "the fish is back")
	later:Advance(1.5)
	t.eq(hud2.tankChip.Text, "1/6")
	finish(t, later)
	later:AssertNoErrors({ warnings = true })
end

return tests
