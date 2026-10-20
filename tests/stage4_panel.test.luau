--[[
	Stage 4 «ЗАЩИТА» sheet (DefenceController + the cards helper Controllers/DefenceCards on
	HUD.DefencePanel, built by tools/builder/gui/Sheet.luau + Defence.luau; docs/stage4_design.md
	§6.6, §6.7, §7.6 «Panel») and the tank panel during a theft, on the real client against the
	replicated state written by the test: the stage 3 / stage 4 services and FishingService are
	switched off ("return {}"), the test writes the player attributes DefenceService replicates
	(Money, HasDog, HasAlarm, LockLevel, ShieldUntil, ShieldReadyAt) and answers with DefenceEvent
	"Bought" / "Denied" / "Shield" itself (RemoteNames: crediting → attributes → remotes).

	What is checked:
	  • the contract names, four cards in one row, their looks: ЩИТ Guard «ВКЛЮЧИТЬ», the prices
	    (Gold), not enough money (Slate, the price still readable; a tap says «ЕЩЁ $3 000» right on
	    the button for Panel.NeedTime s — no toast over the sheet's header), bought (a flat tilted
	    Leaf stamp «✔️ КУПЛЕНО», one line, no shine — not a live button; the lock a one-time buy
	    whose action line becomes «Сильнее замки — скоро в магазине»);
	  • every card's action line fits between its name and its button on phone / phone_small /
	    tablet / desktop (lines × 12 px × 1.25 ≤ Buy.top − Effect.top; the short line when needed);
	  • the shield card while the player steals himself: Slate «ПОСЛЕ КРАЖИ», a tap fires nothing;
	  • the two-tap buy: the first tap says «КУПИТЬ?» and fires nothing; a tap 0.15 s later fires
	    nothing (the arm restarts); a tap 0.5 s after that fires DefenceBuy(item) once, «⏳» until the
	    answer; "Bought" → MoneyController.Spend(price, the button) once, the stamp and — once the
	    sheet closes — the toast; "Denied" → the card wiggles and the server's text shows;
	  • the shield card: «ВКЛЮЧИТЬ» → ShieldActivate at once (no confirm), «🛡️ 0:59» while on,
	    «⏳ 2:59» recharging and «ТЫ ПОД ЗАЩИТОЙ» (taps wiggle it: no request, no toast);
	  • one sheet at a time with the tank panel: open «САДОК», open «ЗАЩИТА» (the tank panel goes),
	    close «ЗАЩИТА» → the fishing layer (the action button) and Toasts.ZIndex are back as before;
	  • the layout on phone / phone_small / tablet / desktop: on screen, never over the Wallet or the
	    right column, Buy ≥ 44 px tall, names and effects ≥ 12 px; phone_small scrolls (the 4th card
	    past the window, an explicit CanvasSize); phone fill ≤ 2.5×;
	  • nothing left running after close (the 1 s ticker stops, connections back to the baseline);
	  • the tank panel's Sell during a theft (§6.7): «КРАДУТ!» while the slot's StealPhase is hold /
	    carry, «В ПУТИ…» while its Escrow is set — a tap asks the server NOTHING (the card wiggles,
	    the label flashes, no toast over the header), back to the price after; and on the
	    REAL server (latency 0.1): the thief lets go and in the same frame the victim taps
	    «КРАДУТ!» — no sale, the saved fish stays in its slot.

	Run: lune run tools/run_tests.luau stage4_panel
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local S = require("./stage4_server")

local Vector2 = roblox.Vector2

local PLACE = "Place1.rbxl"
local STUBBED = {
	"FishingService",
	"DataService",
	"EconomyService",
	"MarketService",
	"TankService",
	"DefenceService",
	"StealService",
}

local function loadConfig(name: string): any
	local path = `src/ReplicatedStorage/Shared/Config/{name}.luau`
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum },
		injectGlobals = true,
	})
	return chunk()
end

local DefenceConfig = loadConfig("DefenceConfig")
local StealConfig = loadConfig("StealConfig")
local TankConfig = loadConfig("TankConfig")
local TEXTS = DefenceConfig.Texts
local CARD_NAMES = { "ShieldCard", "DogCard", "AlarmCard", "LockCard" }

local DEVICES = {
	{ name = "phone", device = "phone" },
	{ name = "phone_small", device = "phone", viewport = Vector2.new(667, 375) },
	{ name = "tablet", device = "tablet" },
	{ name = "desktop", device = "desktop" },
}

local function fill(template: string, values: { [string]: any }): string
	return (
		string.gsub(template, "{(%w+)}", function(key: string): string
			local value = values[key]
			return if value == nil then "{" .. key .. "}" else tostring(value)
		end)
	)
end

--------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------

local function boot(t: any): any
	local sim = t.sim({ place = PLACE })
	for _, name in STUBBED do
		sim:Find(`ServerScriptService.Services.{name}`).Source = "return {}"
	end
	local baseConfig = sim:Find("ReplicatedStorage.Shared.Config.BaseConfig")
	baseConfig.Source = string.gsub(baseConfig.Source, "RandomAssignment%s*=%s*true", "RandomAssignment = false")
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

-- A loaded player (what DataService / DefenceService replicate), the intro played.
local function addPlayer(sim: any, id: number, device: string?, viewport: any?, money: number?): any
	local p = sim:AddPlayer({ UserId = id, Name = `Keeper{id}`, device = device or "phone", viewport = viewport })
	sim:Advance(1)
	for name, value in
		{
			DataMode = "Ready",
			Money = money or 3000,
			Income = 0,
			TankSlots = 6,
			TankCount = 0,
			SellRatePct = 100,
			SellPlace = "",
			LockLevel = 0,
		}
	do
		p:SetAttribute(name, value)
	end
	sim:Advance(5) -- the base banner has landed, the welcome toast is gone, «ЗАЩИТА» popped in
	return p
end

local function module(sim: any, p: any, name: string): any
	local scripts = p:FindFirstChildOfClass("PlayerScripts")
	local found = sim:Find(`Controllers.{name}`, scripts)
	assert(found, `{name} in PlayerScripts`)
	return sim:Require(found, p)
end

local function call(sim: any, p: any, fn: () -> any): any
	return sim:Run(fn, p)
end

local function hudOf(p: any): any
	return p.PlayerGui.HUD
end

local function cardOf(p: any, name: string): any
	return hudOf(p).DefencePanel.Panel.Cards:FindFirstChild(name)
end

local function defenceEvent(sim: any, p: any, kind: string, data: any)
	sim:Find("ReplicatedStorage.Remotes.DefenceEvent"):FireClient(p, kind, data)
	sim:Advance(0.05)
end

-- A time for an attribute (TankRules.AttrTime: RbxSim keeps whole-number attributes as float32).
local function T(t: number): number
	return if t % 1 == 0 then t + 1 / 1024 else t
end

-- The server's clock (what DefenceService writes attributes with).
local function now(sim: any): number
	return sim:Run(function()
		return sim.workspace:GetServerTimeNow()
	end)
end

local function toastTexts(p: any): { string }
	local out = {}
	for _, toast in hudOf(p).Toasts:GetChildren() do
		if toast:IsA("GuiObject") and toast.Visible then
			for _, item in toast:GetDescendants() do
				if item:IsA("TextLabel") and item.Text ~= "" then
					table.insert(out, item.Text)
				end
			end
		end
	end
	return out
end

local function hasToast(p: any, text: string): boolean
	for _, s in toastTexts(p) do
		if string.find(s, text, 1, true) then
			return true
		end
	end
	return false
end

local function clientConnections(sim: any, p: any): number
	local ctx = sim:ContextName(p)
	return sim:CountConnections(function(conn: any): boolean
		return conn.ctx.name == ctx
	end)
end

type Rect = { x0: number, y0: number, x1: number, y1: number }

local function rectOf(gui: any): Rect
	local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
	return { x0 = pos.X, y0 = pos.Y, x1 = pos.X + size.X, y1 = pos.Y + size.Y }
end

local function fmt(r: Rect): string
	return string.format("(%d..%d × %d..%d)", r.x0, r.x1, r.y0, r.y1)
end

local function hits(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
end

local function visibleChain(gui: any, stop: any): boolean
	local node = gui
	while node and node ~= stop do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return true
end

-- The quads the HUD draws, in screens (like gui/checks.py fill_metric).
local function fillOf(p: any, viewport: any): number
	local hud = hudOf(p)
	local W, H = viewport.X, viewport.Y
	local strip = rectOf(hud.DefencePanel.Panel.Cards)
	local total = 0
	local function add(r: Rect, clip: Rect?)
		local x0, y0 = math.max(r.x0, 0), math.max(r.y0, 0)
		local x1, y1 = math.min(r.x1, W), math.min(r.y1, H)
		if clip then
			x0, y0 = math.max(x0, clip.x0), math.max(y0, clip.y0)
			x1, y1 = math.min(x1, clip.x1), math.min(y1, clip.y1)
		end
		if x1 > x0 and y1 > y0 then
			total += (x1 - x0) * (y1 - y0)
		end
	end
	for _, item in hud:GetDescendants() do
		if not item:IsA("GuiObject") or not visibleChain(item, hud) then
			continue
		end
		local clip = if item:IsDescendantOf(hud.DefencePanel.Panel.Cards) then strip else nil
		local r = rectOf(item)
		local drawn = item.BackgroundTransparency < 1
			or item:IsA("ViewportFrame")
			or ((item:IsA("TextLabel") or item:IsA("TextButton")) and item.Text ~= "" and item.TextTransparency < 1)
		if drawn then
			add(r, clip)
		end
		for _, stroke in item:GetChildren() do
			if
				stroke:IsA("UIStroke")
				and stroke.Transparency < 0.999
				and stroke.ApplyStrokeMode == roblox.Enum.ApplyStrokeMode.Border
			then
				local g = stroke.Thickness
				add({ x0 = r.x0 - g, y0 = r.y0 - g, x1 = r.x1 + g, y1 = r.y1 + g }, clip)
			end
		end
	end
	return total / (W * H)
end

-- A player with the «ЗАЩИТА» sheet open (Toggle, like the button press).
local function opened(t: any, opts: { [string]: any }?): (any, any, any)
	local o = opts or {}
	local sim = boot(t)
	local p = addPlayer(sim, 1, o.device, o.viewport, o.money)
	for name, value in o.attrs or {} do
		p:SetAttribute(name, value)
	end
	local defence = module(sim, p, "DefenceController")
	t.ok(
		call(sim, p, function()
			return defence.Toggle()
		end),
		"Toggle opens the «ЗАЩИТА» sheet"
	)
	sim:Advance(0.6)
	return sim, p, defence
end

local function looks(sim: any, p: any, defence: any): { [string]: string }
	local stats = call(sim, p, function()
		return defence.Stats()
	end)
	return stats.cards and stats.cards.looks or {}
end

local function tapBuy(sim: any, p: any, name: string)
	sim:Click(p, cardOf(p, name).Buy)
	sim:Advance(1 / 60)
end

local function buyText(p: any, name: string): string
	local buy = cardOf(p, name).Buy
	local label, price = buy:FindFirstChild("Label"), buy:FindFirstChild("Price")
	if label and label.Visible and label.Text ~= "" then
		return label.Text
	end
	return if price then price.Text else ""
end

local tests = {}

--------------------------------------------------------------------------------
-- Names, cards, looks
--------------------------------------------------------------------------------

tests["names: the sheet shell, the header with the money chip, four cards in one row"] = function(t)
	local sim = boot(t)
	local root = sim:Find("StarterGui.HUD").DefencePanel
	t.eq(root.Visible, false, "hidden until opened")
	t.ok(root.ZIndex >= 30, "above HUD.Fishing and the base banner")
	local panel = root.Panel
	for _, name in { "Strip", "Header", "Close", "Cards" } do
		t.ok(panel:FindFirstChild(name), `Panel.{name}`)
	end
	for _, name in { "Icon", "Title", "Money" } do
		t.ok(panel.Header:FindFirstChild(name), `Header.{name}`)
	end
	t.ok(panel.Cards:IsA("ScrollingFrame"), "Cards: a ScrollingFrame")
	t.ok(panel.Cards:FindFirstChildOfClass("UIGridLayout"), "with a UIGridLayout")
	for order, name in CARD_NAMES do
		local card = panel.Cards:FindFirstChild(name)
		t.ok(card, name)
		if card then
			t.eq(card.LayoutOrder, order, `{name}: LayoutOrder {order}`)
			for _, child in { "Icon", "Name", "Effect", "State", "Buy" } do
				t.ok(card:FindFirstChild(child), `{name}.{child}`)
			end
			t.ok(card.Buy:FindFirstChild("Label") and card.Buy:FindFirstChild("Price"), `{name}.Buy.Label / Price`)
		end
	end
	t.eq(panel.Cards.ShieldCard:FindFirstChild("Name").Text, TEXTS.Cards.Shield.Name, "«ЩИТ»")
	t.eq(panel.Cards.LockCard:FindFirstChild("Name").Text, TEXTS.Cards.Lock.Name, "«ЗАМОК»")
	sim:AssertNoErrors({ warnings = true })
end

tests["looks: ЩИТ «ВКЛЮЧИТЬ», prices, not enough money, bought; the lock a one-time buy with the shop line"] = function(
	t
)
	local sim, p, defence = opened(t, { money = 3000 })
	local l = looks(sim, p, defence)
	t.eq(l.Shield, "on", "the shield card: «ВКЛЮЧИТЬ» (Guard)")
	t.eq(l.Dog, "poor", "the dog ($6 000) with $3 000: Slate")
	t.eq(l.Alarm, "price", "the alarm ($2 500): Gold")
	t.eq(l.Lock, "price", "the lock ($1 500): Gold")
	t.eq(buyText(p, "ShieldCard"), TEXTS.Buy.On, "«ВКЛЮЧИТЬ»")
	t.ok(
		string.find(buyText(p, "DogCard"), "6", 1, true) ~= nil,
		`the dog's price stays readable («{buyText(p, "DogCard")}»)`
	)
	t.ok(string.find(buyText(p, "AlarmCard"), "2", 1, true) ~= nil, "the alarm's price")
	t.eq(cardOf(p, "LockCard").State.Visible, false, "no shop line before the lock is bought")
	-- Not enough money: a tap says it right on the button (no toast over the header / Wallet).
	tapBuy(sim, p, "DogCard")
	sim:Advance(0.1)
	t.eq(looks(sim, p, defence).Dog, "need", "the dog's button says what is missing")
	local tankRules = sim:Require(sim:Find("ReplicatedStorage.Shared.TankRules"))
	local need = fill(TEXTS.Buy.Need, { price = tankRules.FormatMoney(3000) })
	t.eq(buyText(p, "DogCard"), need, `«{need}» under the finger`)
	t.ok(not hasToast(p, "Не хватает"), "no toast over the sheet")
	tapBuy(sim, p, "DogCard")
	sim:Advance(0.1)
	t.ok(not hasToast(p, "Не хватает"), "a second tap: still no stack of toasts")
	t.eq(#sim:ServerEventsFor(p, "DefenceBuy"), 0, "nothing asked")
	sim:Advance(DefenceConfig.Panel.NeedTime + 0.3)
	t.eq(looks(sim, p, defence).Dog, "poor", "back to the (readable) price")
	-- Bought (DefenceService writes the attributes): the dog and the lock.
	p:SetAttribute("HasDog", true)
	p:SetAttribute("LockLevel", 1)
	sim:Advance(0.2)
	l = looks(sim, p, defence)
	t.eq(l.Dog, "bought", "the dog: «КУПЛЕНО»")
	t.eq(l.Lock, "bought", "the lock: «КУПЛЕНО» (one level in stage 4)")
	t.eq(buyText(p, "DogCard"), TEXTS.Buy.Bought, "«КУПЛЕНО»")
	t.eq(buyText(p, "LockCard"), TEXTS.Buy.Bought, "«КУПЛЕНО»")
	local lock = cardOf(p, "LockCard")
	t.eq(lock.State.Visible, false, "no separate shop line (it collided with the effect and the button)")
	t.ok(
		lock.Effect.Text == TEXTS.LockSoon or lock.Effect.Text == TEXTS.LockSoonShort,
		`the bought lock's action line: «{lock.Effect.Text}»`
	)
	-- Money changes the looks live (the header chip too).
	p:SetAttribute("Money", 1000)
	sim:Advance(0.2)
	t.eq(looks(sim, p, defence).Alarm, "poor", "the alarm with $1 000: Slate")
	t.ok(
		string.find(hudOf(p).DefencePanel.Panel.Header.Money.Label.Text, "1", 1, true) ~= nil,
		"the header's money follows the Wallet"
	)
	sim:AssertNoErrors({ warnings = true })
end

tests["every card's action line fits between its name and its button on 4 screens (the short line when needed); the bought lock too"] = function(
	t
)
	for _, spec in DEVICES do
		local sim, p = opened(t, { device = spec.device, viewport = spec.viewport, money = 3000 })
		local cards = module(sim, p, "DefenceCards")
		local function check(what: string)
			for _, name in CARD_NAMES do
				local card = cardOf(p, name)
				local effect, title, buy = card.Effect, card:FindFirstChild("Name"), card.Buy
				local box = effect.AbsoluteSize.X
				local lines = call(sim, p, function()
					return cards.LineCount(effect.Text, 12, box)
				end)
				local room = buy.AbsolutePosition.Y - effect.AbsolutePosition.Y
				t.ok(
					lines * 12 * 1.25 <= room + 0.5,
					`{spec.name} {what} {name}: {lines} line(s) of «{effect.Text}» fit {math.floor(room)} px`
				)
				t.ok(
					effect.AbsolutePosition.Y >= title.AbsolutePosition.Y + title.AbsoluteSize.Y - 0.5,
					`{spec.name} {what} {name}: the line under the name`
				)
				t.ok(
					effect.AbsolutePosition.Y + effect.AbsoluteSize.Y <= buy.AbsolutePosition.Y + 0.5,
					`{spec.name} {what} {name}: the line above the button`
				)
				local texts = TEXTS.Cards[string.gsub(name, "Card$", "")]
				t.ok(effect.Text ~= "" and texts ~= nil, `{spec.name} {what} {name}: an action line`)
			end
		end
		check("fresh")
		p:SetAttribute("HasDog", true)
		p:SetAttribute("HasAlarm", true)
		p:SetAttribute("LockLevel", 1)
		sim:Advance(1.2)
		check("all bought")
		local lock = cardOf(p, "LockCard")
		t.ok(
			lock.Effect.Text == TEXTS.LockSoon or lock.Effect.Text == TEXTS.LockSoonShort,
			`{spec.name}: the bought lock says «скоро» in its line`
		)
		t.eq(lock.State.Visible, false, `{spec.name}: no second line`)
		sim:AssertNoErrors({ warnings = true })
	end
end

tests["the shield card while stealing himself: Slate «ПОСЛЕ КРАЖИ», a tap fires nothing"] = function(t)
	local sim, p, defence = opened(t, { money = 0 })
	p:SetAttribute("Stealing", "carry")
	sim:Advance(0.2)
	t.eq(looks(sim, p, defence).Shield, "after", "«ПОСЛЕ КРАЖИ» (the server would refuse)")
	t.eq(buyText(p, "ShieldCard"), TEXTS.Buy.AfterTheft, `«{TEXTS.Buy.AfterTheft}»`)
	tapBuy(sim, p, "ShieldCard")
	sim:Advance(0.2)
	t.eq(#sim:ServerEventsFor(p, "ShieldActivate"), 0, "a tap fires nothing")
	p:SetAttribute("Stealing", nil)
	sim:Advance(0.2)
	t.eq(looks(sim, p, defence).Shield, "on", "«ВКЛЮЧИТЬ» after the theft")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Buying
--------------------------------------------------------------------------------

tests["two-tap buy: «КУПИТЬ?», 0.15 s ignored (the arm restarts), 0.5 s fires DefenceBuy once; ⏳ until the answer"] = function(
	t
)
	local sim, p, defence = opened(t, { money = 3000 })
	local function buys(): { any }
		return sim:ServerEventsFor(p, "DefenceBuy")
	end
	tapBuy(sim, p, "AlarmCard")
	t.eq(#buys(), 0, "the first tap fires nothing")
	t.eq(looks(sim, p, defence).Alarm, "confirm", "Berry «КУПИТЬ?»")
	t.eq(buyText(p, "AlarmCard"), TEXTS.Buy.Confirm, "«КУПИТЬ?»")
	sim:Advance(0.15)
	tapBuy(sim, p, "AlarmCard")
	t.eq(#buys(), 0, "a tap 0.15 s later fires nothing")
	t.eq(looks(sim, p, defence).Alarm, "confirm", "still «КУПИТЬ?» (the arm restarted)")
	sim:Advance(0.5)
	tapBuy(sim, p, "AlarmCard")
	local list = buys()
	t.eq(#list, 1, "a tap 0.5 s later fires DefenceBuy once")
	t.eq(list[1] and list[1].args[1], "Alarm", 'DefenceBuy("Alarm")')
	t.eq(looks(sim, p, defence).Alarm, "busy", "«⏳» until the answer")
	tapBuy(sim, p, "AlarmCard")
	t.eq(#buys(), 1, "a tap while waiting fires nothing")
	-- Another card cancels a pending confirm.
	tapBuy(sim, p, "LockCard")
	t.eq(looks(sim, p, defence).Lock, "confirm", "the lock asks «КУПИТЬ?»")
	tapBuy(sim, p, "ShieldCard")
	t.ok(looks(sim, p, defence).Lock ~= "confirm", "another card cancels it")
	-- The confirm times out by itself.
	sim:Advance(1)
	tapBuy(sim, p, "LockCard")
	sim:Advance(TankConfig.ConfirmTime + 0.3)
	t.eq(looks(sim, p, defence).Lock, "price", `back to the price after {TankConfig.ConfirmTime} s`)
	sim:AssertNoErrors({ warnings = true })
end

tests["Bought → MoneyController.Spend(price, button) once, the flat tilted stamp «✔️ КУПЛЕНО», the toast after the sheet closes; Denied → wiggle + the server's text"] = function(
	t
)
	local sim, p, defence = opened(t, { money = 9000 })
	local money = module(sim, p, "MoneyController")
	local UiFx = sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p)
	local spent: { any } = {}
	local spend = money.Spend
	money.Spend = function(amount: number, to: any)
		table.insert(spent, { amount = amount, to = to })
		return spend(amount, to)
	end
	local wiggles: { any } = {}
	local wiggle = UiFx.wiggle
	UiFx.wiggle = function(gui: any, ...)
		table.insert(wiggles, gui)
		return wiggle(gui, ...)
	end
	tapBuy(sim, p, "DogCard")
	sim:Advance(0.5)
	tapBuy(sim, p, "DogCard")
	t.eq(#sim:ServerEventsFor(p, "DefenceBuy"), 1, 'DefenceBuy("Dog")')
	-- The server: money and HasDog first, then the event.
	p:SetAttribute("Money", 3000)
	p:SetAttribute("HasDog", true)
	defenceEvent(sim, p, "Bought", { Item = "Dog", Price = 6000 })
	local floated = sim:WaitFor(function()
		for _, item in hudOf(p):GetDescendants() do
			if item:IsA("TextLabel") and string.find(item.Text, "−$6", 1, true) then
				return true
			end
		end
		return nil
	end, 1, 1 / 30)
	t.ok(floated, "«−$6 000» floats by the Wallet")
	sim:Advance(0.3)
	t.eq(#spent, 1, "MoneyController.Spend once")
	t.eq(spent[1] and spent[1].amount, 6000, "with the price")
	t.ok(spent[1] and spent[1].to and spent[1].to:IsDescendantOf(cardOf(p, "DogCard")), "the 💵 fly into the card")
	t.eq(looks(sim, p, defence).Dog, "bought", "«КУПЛЕНО»")
	local stamp = cardOf(p, "DogCard").Buy
	t.eq(stamp.Label.Text, TEXTS.Buy.Bought, `the stamp «{TEXTS.Buy.Bought}»`)
	t.ok(math.abs(stamp.Rotation) > 1, `tilted like a stamp ({stamp.Rotation}°)`)
	t.ok(stamp.Size.X.Scale < cardOf(p, "ShieldCard").Buy.Size.X.Scale - 0.05, "narrower than a button")
	local face = stamp:FindFirstChild("Face")
	local shine = face and face:FindFirstChild("Shine")
	t.ok(shine == nil or not shine.Visible, "no shine (not a live button)")
	t.eq(stamp.Label.TextWrapped, false, "one line")
	t.ok(not hasToast(p, TEXTS.Bought.Dog), "the toast waits for the sheet (it would cover the header and Wallet)")
	local counted = sim:WaitFor(function()
		return string.find(hudOf(p).Status.Wallet.Money.Label.Text, "3", 1, true) ~= nil
			and string.find(hudOf(p).Status.Wallet.Money.Label.Text, "9", 1, true) == nil
	end, 3, 0.1)
	t.ok(counted, `the Wallet counts down to $3 000 («{hudOf(p).Status.Wallet.Money.Label.Text}»)`)
	-- Denied: the card wiggles, the server's text shows.
	tapBuy(sim, p, "AlarmCard")
	sim:Advance(0.5)
	tapBuy(sim, p, "AlarmCard")
	t.eq(#sim:ServerEventsFor(p, "DefenceBuy"), 2, 'DefenceBuy("Alarm")')
	local before = #wiggles
	defenceEvent(
		sim,
		p,
		"Denied",
		{ Item = "Alarm", Reason = "money", Text = "Не хватает: нужно $2 500" }
	)
	sim:Advance(0.3)
	local wiggled = false
	for i = before + 1, #wiggles do
		wiggled = wiggled or wiggles[i]:IsDescendantOf(cardOf(p, "AlarmCard")) or wiggles[i] == cardOf(p, "AlarmCard")
	end
	t.ok(wiggled, "the alarm card wiggles")
	t.ok(hasToast(p, "Не хватает: нужно $2 500"), "the server's text")
	t.ok(looks(sim, p, defence).Alarm ~= "busy", "the button is back")
	t.eq(#spent, 1, "no spend on a refusal")
	call(sim, p, function()
		return defence.Toggle()
	end)
	local shown = sim:WaitFor(function()
		return if hasToast(p, TEXTS.Bought.Dog) then true else nil
	end, 6, 0.1)
	t.ok(shown, `closed: «{TEXTS.Bought.Dog}»`)
	sim:AssertNoErrors({ warnings = true })
end

tests["the shield card: «ВКЛЮЧИТЬ» → ShieldActivate at once; «🛡️ 0:59» while on; «⏳ 2:59» recharging and «ТЫ ПОД ЗАЩИТОЙ» (taps wiggle — no request, no toast)"] = function(
	t
)
	local sim, p, defence = opened(t, { money = 0 })
	tapBuy(sim, p, "ShieldCard")
	t.eq(#sim:ServerEventsFor(p, "ShieldActivate"), 1, "one tap: ShieldActivate (no confirm)")
	-- The server: the attributes, then DefenceEvent "Shield".
	local at = now(sim)
	local shield = DefenceConfig.Shield
	p:SetAttribute("ShieldUntil", T(at + shield.Duration))
	p:SetAttribute("ShieldReadyAt", T(at + shield.Duration + shield.Cooldown))
	defenceEvent(sim, p, "Shield", { Until = at + shield.Duration, ReadyAt = at + shield.Duration + shield.Cooldown })
	sim:Advance(2.2) -- (the 1 s ticker has run at least twice)
	t.eq(looks(sim, p, defence).Shield, "active", "on: glass «🛡️ 0:59»")
	t.ok(string.find(buyText(p, "ShieldCard"), "0:5", 1, true) ~= nil, `the time left («{buyText(p, "ShieldCard")}»)`)
	-- The shield over, recharging.
	p:SetAttribute("ShieldUntil", T(at))
	sim:Advance(1.1)
	t.eq(looks(sim, p, defence).Shield, "wait", "recharging: Slate «⏳ …»")
	t.ok(string.find(buyText(p, "ShieldCard"), "⏳", 1, true) ~= nil, `«⏳ …» («{buyText(p, "ShieldCard")}»)`)
	for _ = 1, 5 do
		tapBuy(sim, p, "ShieldCard")
		sim:Advance(0.3)
	end
	t.eq(#sim:ServerEventsFor(p, "ShieldActivate"), 1, "taps while recharging fire nothing")
	t.eq(#toastTexts(p), 0, "5 taps: no toast (the button says «⏳ 2:59»; it wiggles and flashes)")
	-- Another protection ≥ StackBelow: glass «ТЫ ПОД ЗАЩИТОЙ» — a tap only wiggles too.
	p:SetAttribute("ShieldReadyAt", 0)
	local base = sim.workspace.Bases:FindFirstChild(`Base_{p:GetAttribute("BaseIndex")}`)
	base:SetAttribute("ProtectUntil", T(now(sim) + 300))
	base:SetAttribute("ProtectKind", "join")
	sim:Advance(1.1)
	t.eq(looks(sim, p, defence).Shield, "protected", "«ТЫ ПОД ЗАЩИТОЙ»")
	for _ = 1, 3 do
		tapBuy(sim, p, "ShieldCard")
		sim:Advance(0.3)
	end
	t.eq(#sim:ServerEventsFor(p, "ShieldActivate"), 1, "protected: taps fire nothing")
	t.eq(#toastTexts(p), 0, "protected: no toast either")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- One sheet at a time
--------------------------------------------------------------------------------

tests["one sheet at a time: «САДОК» open, «ЗАЩИТА» opens (the tank panel goes), close → the action button and Toasts.ZIndex back"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	local hud = hudOf(p)
	local area = hud.Fishing.ActionArea
	local layerBefore, areaBefore = hud.Fishing.Visible, area.Visible
	local zBefore = hud.Toasts.ZIndex
	local tank, defence = module(sim, p, "TankPanelController"), module(sim, p, "DefenceController")
	t.ok(
		call(sim, p, function()
			return tank.Toggle()
		end),
		"«САДОК» opens"
	)
	sim:Advance(0.6)
	t.ok(hud.TankPanel.Visible, "the tank panel is up")
	t.ok(hud.Toasts.ZIndex > zBefore, "toasts over the sheet")
	t.ok(
		call(sim, p, function()
			return defence.Toggle()
		end),
		"«ЗАЩИТА» opens"
	)
	sim:Advance(0.6)
	t.eq(
		call(sim, p, function()
			return tank.IsOpen()
		end),
		false,
		"the tank panel closed itself"
	)
	t.eq(hud.TankPanel.Visible, false, "and is hidden")
	t.ok(hud.DefencePanel.Visible, "the «ЗАЩИТА» sheet is up")
	t.ok(hud.Toasts.ZIndex > zBefore, "toasts still over the sheet")
	t.ok(call(sim, p, function()
		return defence.Toggle()
	end) ~= nil, "«ЗАЩИТА» toggles closed")
	sim:Advance(0.8)
	t.eq(hud.DefencePanel.Visible, false, "the sheet is gone")
	t.eq(hud.Toasts.ZIndex, zBefore, "Toasts.ZIndex restored")
	t.eq(hud.Fishing.Visible, layerBefore, "the fishing layer as before")
	t.eq(area.Visible, areaBefore, "the action button («ВЗЯТЬ») as before")
	-- And the other way round.
	call(sim, p, function()
		return defence.Toggle()
	end)
	sim:Advance(0.6)
	call(sim, p, function()
		return tank.Toggle()
	end)
	sim:Advance(0.6)
	t.eq(
		call(sim, p, function()
			return defence.IsOpen()
		end),
		false,
		"«САДОК» closes «ЗАЩИТА»"
	)
	call(sim, p, function()
		return tank.Toggle()
	end)
	sim:Advance(0.8)
	t.eq(hud.Toasts.ZIndex, zBefore, "Toasts.ZIndex restored again")
	t.eq(hud.Fishing.Visible, layerBefore, "the fishing layer as before")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

tests["layout on phone / phone_small / tablet / desktop: on screen, off the Wallet and the column, Buy ≥ 44 px, text ≥ 12 px; phone_small scrolls"] = function(
	t
)
	for _, spec in DEVICES do
		local sim, p = opened(t, { device = spec.device, viewport = spec.viewport, money = 3000 })
		local hud = hudOf(p)
		local viewport = spec.viewport or sim.players.state[sim:Unwrap(p)].viewport
		local panel = rectOf(hud.DefencePanel.Panel)
		t.ok(
			panel.x0 >= 0 and panel.y0 >= 0 and panel.x1 <= viewport.X and panel.y1 <= viewport.Y,
			`{spec.name}: the sheet on screen {fmt(panel)}`
		)
		t.ok(not hits(panel, rectOf(hud.Status.Wallet)), `{spec.name}: not over the Wallet`)
		for _, button in hud.RightButtons:GetChildren() do
			if button:IsA("GuiObject") and button.Visible then
				t.ok(not hits(panel, rectOf(button)), `{spec.name}: not over {button.Name}`)
			end
		end
		local window = rectOf(hud.DefencePanel.Panel.Cards)
		local inside = 0
		for _, name in CARD_NAMES do
			local card = cardOf(p, name)
			local r = rectOf(card)
			if r.x1 <= window.x1 + 1 then
				inside += 1
			end
			t.ok(card.Buy.AbsoluteSize.Y >= 44 - 0.5, `{spec.name} {name}: Buy ≥ 44 px ({card.Buy.AbsoluteSize.Y})`)
			for _, label in { card:FindFirstChild("Name"), card.Effect } do
				t.ok(
					label.TextSize >= 12 or (label.TextScaled and label.AbsoluteSize.Y >= 12),
					`{spec.name} {name}.{label.Name}: ≥ 12 px`
				)
			end
		end
		if spec.name == "phone_small" then
			local cards = hud.DefencePanel.Panel.Cards
			t.ok(cards.CanvasSize.X.Scale > 1, `phone_small: an explicit CanvasSize ({cards.CanvasSize.X.Scale})`)
			t.ok(inside < 4, `phone_small: the 4th card past the window ({inside} inside)`)
		else
			t.eq(inside, 4, `{spec.name}: all four cards in the window`)
		end
		sim:AssertNoErrors({ warnings = true })
	end
end

tests["phone fill ≤ 2.5× with the sheet open; closed — the ticker stops, connections back to the baseline"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone", nil, 3000)
	local defence = module(sim, p, "DefenceController")
	sim:Advance(2)
	local baseline = clientConnections(sim, p)
	call(sim, p, function()
		return defence.Toggle()
	end)
	sim:Advance(1.2)
	local viewport = sim.players.state[sim:Unwrap(p)].viewport
	local f = fillOf(p, Vector2.new(viewport.X, viewport.Y))
	t.ok(f <= 2.5, `phone: fill {string.format("%.2f", f)}× ≤ 2.5×`)
	local stats = call(sim, p, function()
		return defence.Stats()
	end)
	t.ok(stats.cards and stats.cards.ticking, "the 1 s ticker runs while open")
	call(sim, p, function()
		return defence.Toggle()
	end)
	sim:Advance(1.5)
	stats = call(sim, p, function()
		return defence.Stats()
	end)
	t.eq(stats.cards and stats.cards.ticking, false, "the ticker stopped")
	t.eq(clientConnections(sim, p), baseline, "connections back to the baseline")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The tank panel during a theft (§6.7)
--------------------------------------------------------------------------------

tests["the tank panel: «КРАДУТ!» while the slot is held / carried, «В ПУТИ…» with Escrow — a tap asks nothing (a wiggle, no toast), the price after"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "tablet")
	local base = sim.workspace.Bases:FindFirstChild(`Base_{p:GetAttribute("BaseIndex")}`)
	local rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"))
	local tankRules = sim:Require(sim:Find("ReplicatedStorage.Shared.TankRules"))
	local serial = 0
	local function slot(index: number): any
		return base.Tank.Slots[`Slot_{index}`]
	end
	local function event(s: any, kind: string)
		serial += 1
		s:SetAttribute("Event", `{serial}|{kind}|`)
	end
	-- Two fish (TankService's replicated state: fish fields → State → Event last).
	for index = 1, TankConfig.MaxSlots do
		local s = slot(index)
		local id = if index == 1 then "Perch" elseif index == 2 then "Puffer" else nil
		if id then
			local def = rules.GetFish(id)
			local kg = (def.MinKg + def.MaxKg) / 2
			local value, income = rules.Price(id, kg)
			s:SetAttribute("FishUid", `f{index}`)
			s:SetAttribute("FishId", id)
			s:SetAttribute("Rarity", def.Rarity)
			s:SetAttribute("Kg", kg)
			s:SetAttribute("Value", value)
			s:SetAttribute("Income", income)
			s:SetAttribute("GrowFrom", tankRules.AttrTime(now(sim) - 30))
			s:SetAttribute("State", "fish")
		else
			s:SetAttribute("State", if index > TankConfig.StartSlots then "locked" else "empty")
		end
		event(s, "mount")
	end
	p:SetAttribute("TankCount", 2)
	p:SetAttribute("TankSlots", TankConfig.StartSlots)
	sim:Advance(0.1)
	local tank = module(sim, p, "TankPanelController")
	t.ok(
		call(sim, p, function()
			return tank.Toggle()
		end),
		"«САДОК» opens"
	)
	sim:Advance(0.6)
	local cards = hudOf(p).TankPanel.Panel.Cards
	local function caption(index: number): string
		return cards:FindFirstChild(`Card{index}`).Sell.Caption.Text
	end
	local price = caption(2)
	t.ok(price ~= StealConfig.Texts.Panel.Stealing, `the Puffer's price («{price}»)`)
	-- The hold on Slot_2.
	slot(2):SetAttribute("StealBy", 777)
	slot(2):SetAttribute("StealEnd", T(now(sim) + 3))
	slot(2):SetAttribute("StealPhase", "hold")
	sim:Advance(0.1)
	t.eq(caption(2), StealConfig.Texts.Panel.Stealing, "«КРАДУТ!» in the hold")
	t.ok(caption(1) ~= StealConfig.Texts.Panel.Stealing, "the other card keeps its price")
	sim:Click(p, cards.Card2.Sell)
	sim:Advance(0.1)
	t.eq(#sim:ServerEventsFor(p, "TankSell"), 0, "a tap asks the server nothing (no sale of a fish being stolen)")
	sim:Click(p, cards.Card2.Sell)
	sim:Advance(0.1)
	sim:Click(p, cards.Card2.Sell)
	sim:Advance(0.1)
	t.eq(#toastTexts(p), 0, "no toast over the sheet's header («КРАДУТ!» says it; the card wiggles)")
	t.eq(#sim:ServerEventsFor(p, "TankSell"), 0, "still nothing asked")
	slot(2):SetAttribute("StealPhase", "carry")
	sim:Advance(0.1)
	t.eq(caption(2), StealConfig.Texts.Panel.Stealing, "«КРАДУТ!» in the carry")
	-- Saved: the channel clears, the price is back.
	slot(2):SetAttribute("StealPhase", nil)
	slot(2):SetAttribute("StealBy", nil)
	slot(2):SetAttribute("StealEnd", nil)
	sim:Advance(0.1)
	t.eq(caption(2), price, "the price is back after the theft")
	-- Escrow (the thief's fresh fish): «В ПУТИ…» until it clears.
	slot(1):SetAttribute("Escrow", true)
	sim:Advance(0.1)
	t.eq(caption(1), StealConfig.Texts.Panel.Escrow, "«В ПУТИ…» while Escrow is set")
	sim:Advance(2.1)
	sim:Click(p, cards.Card1.Sell)
	sim:Advance(0.1)
	t.eq(#sim:ServerEventsFor(p, "TankSell"), 0, "a tap on «В ПУТИ…» asks nothing")
	t.eq(#toastTexts(p), 0, "and shows no toast")
	slot(1):SetAttribute("Escrow", nil)
	sim:Advance(0.1)
	t.ok(caption(1) ~= StealConfig.Texts.Panel.Escrow, "the price after the escrow")
	sim:AssertNoErrors({ warnings = true })
end

tests["real server: the thief lets go and in the same frame the victim taps «КРАДУТ!» — no sale, the saved fish stays"] = function(
	t
)
	local sim = S.boot(t, { latency = 0.1 })
	local victim = S.player(t, sim, 101, {
		tank = { { Id = "Perch" }, { Id = "Perch" }, { Id = "Puffer", Age = 200 }, { Id = "Crucian" } },
		client = true,
		device = "tablet",
		name = "Хозяин",
	})
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } }, name = "Ника" })
	local ready = sim:WaitFor(function()
		local gui = victim:FindFirstChild("PlayerGui")
		local hud = gui and gui:FindFirstChild("HUD")
		return hud ~= nil and hud.RightButtons.DefenceButton.Visible and hud.RightButtons.TankButton.Visible
	end, 15, S.COARSE)
	t.ok(ready, "the victim's HUD")
	sim:Advance(5)
	local hud = hudOf(victim)
	local tank = module(sim, victim, "TankPanelController")
	local hold, prompt = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active, "the hold began")
	sim:Advance(0.3)
	-- (a loud alert closes an open «САДОК»; this hold is let go inside the tap window, so the victim
	-- never gets one: the kid has his «САДОК» open during the hold)
	t.ok(
		call(sim, victim, function()
			return tank.Toggle()
		end),
		"«САДОК» opens during the theft"
	)
	sim:Advance(0.5)
	t.ok(hud.TankPanel.Visible, "the tank panel is up")
	local card = hud.TankPanel.Panel.Cards:FindFirstChild("Card3")
	local names = {}
	for _, c in hud.TankPanel.Panel.Cards:GetChildren() do
		table.insert(names, c.Name)
	end
	t.ok(card ~= nil, `Card3 ({table.concat(names, ", ")})`)
	if not card then
		return
	end
	t.eq(card.Sell.Caption.Text, StealConfig.Texts.Panel.Stealing, "«КРАДУТ!» on the card")
	local soldBefore = #S.tankEvents(sim, victim, "Sold")
	sim:ReleasePrompt(thief, prompt)
	sim:Click(victim, card.Sell) -- (his screen still says «КРАДУТ!»)
	sim:Advance(1.5)
	t.eq(#sim:ServerEventsFor(victim, "TankSell"), 0, "no TankSell from «КРАДУТ!»")
	t.eq(#S.tankEvents(sim, victim, "Sold"), soldBefore, "nothing sold")
	local slot3 = S.slotAttrs(sim, victim, 3)
	t.eq(slot3.State, "fish", "the saved fish stays in its slot")
	t.eq(slot3.FishId, "Puffer", "the Puffer")
	t.ok(card.Sell.Caption.Text ~= StealConfig.Texts.Panel.Stealing, "the price is back")
	sim:AssertNoErrors({ warnings = true })
end

return tests
