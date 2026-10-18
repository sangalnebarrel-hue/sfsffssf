--[[
	Stage 3 tank panel (TankPanelController + the sheet helper Controllers/Sheet + the cards helper
	Controllers/TankCards on HUD.TankPanel, built by tools/builder/gui/Sheet.luau + Tank.luau) on
	the real client, against the replicated state of design §4.6 written by the test: the stage 3
	services (TankService, DataService, EconomyService, MarketService) and FishingService are
	switched off ("return {}"), and a small fake server below writes the display / tank / player
	attributes exactly like TankService does (fish fields → State → Event LAST, "<n>|kind|detail",
	AttrTime for GrowFrom) and answers TankSell with TankEvent "Sold" / "Denied".

	What is checked (design §7.5, the panel):
	  • the contract names and the sim look (no studs in the GUI);
	  • open / close by Toggle (the «САДОК» press: Wave 2 C binds the button to it), by TankEvent
	    "Open" and by ✕; refused during a bite and while the catch card shows, deferred while the
	    fish flies into the button (CounterHold) — it opens right after; closes itself on Bite /
	    Reeling / CounterHold / CatchCard;
	  • cards for fish / empty / locked; phone labels (ShortName, «💵 $45») vs wide labels (the full
	    name, «ПРОДАТЬ $45» only where they fit); the mutation chip, «МАКС», the header (count, rate,
	    total);
	  • values tick on one 1 s chain (no frame job, no frame connection); the header total grows;
	  • market mode on SellRatePct only (not on TankEvent "Open"'s RatePct);
	  • confirm on every sale: the first tap fires nothing («ПРОДАТЬ?»); a tap sooner than ConfirmArm after the
	    previous one fires nothing and restarts the arm (+0.15 s, +0.5 s: nothing; mashing every
	    0.2 s for 2 s: nothing); a tap after a pause ≥ ConfirmArm fires TankSell(uid) once; a 3 s
	    timeout reverts; the red «−$X/с»; another card cancels;
	  • after "Sold": the card turns empty, MoneyController.Celebrate(Amount, card, { Rate = "down" })
	    exactly once (and with no flight when the panel is closed); the juice ends (activeJobs 0);
	    "Denied" → the button is back, a warning toast over the sheet;
	  • slot events while open ("in", "swap") refresh only their card;
	  • the layout is scale-based, never over the Wallet (status stack) or the right column, ≥ 16 px
	    from Jump and off the thumbstick on touch screens and the screen edges, on phone /
	    phone_small / tablet / desktop, and survives a ViewportSize change; sell buttons ≥ 44 px
	    tall; on every card the income and the growth pill («МАКС») share one row clear of the
	    sell button, and the fish window (the freed row) is ≥ 36 % of the card; several rows fill
	    by columns, every fish card in the window at rest; the first tap says «ПРОДАТЬ?»; the
	    header before the ✕ (also at a stall with a full tank: the chip sized to its text; at a
	    stall with 3/6 on a desktop the income stays); one sell label style per panel; a name
	    right of its mutation chip; ✕ only shrinks;
	  • Open(uid) scrolls to the fish and rings it; the «!» on «САДОК» hides on open;
	  • nothing is left running after close (connections back to the baseline, no clones);
	  • phone fill ≤ 2.5× with 6 cards and the teaser (the quads the HUD draws, like
	    tools/preview/gui/checks.py fill_metric).

	Run: lune run tools/run_tests.luau stage3_panel
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Vector2 = roblox.Vector2

local PLACE = "Place1.rbxl"
local INSET = 58 -- RbxSim's top bar inset for ScreenGuis without IgnoreGuiInset
local STUBBED = { "FishingService", "DataService", "EconomyService", "MarketService", "TankService" }

local function loadConfig(name: string): any
	local path = `src/ReplicatedStorage/Shared/Config/{name}.luau`
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum },
		injectGlobals = true,
	})
	return chunk()
end

local TankConfig = loadConfig("TankConfig")
local UIConfig = loadConfig("UIConfig")
local EconomyConfig = loadConfig("EconomyConfig")
local TEXTS = TankConfig.Texts
local PANEL = TankConfig.Panel

-- TextUtil.fill for the test's own expectations (the same {field} templates as TankConfig).
local function TextFill(template: string, values: { [string]: any }): string
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

-- A player with the stage 3 state of a loaded tank (what DataService / TankService replicate).
local function addPlayer(sim: any, id: number, device: string?, viewport: any?): any
	local p = sim:AddPlayer({ UserId = id, Name = `Keeper{id}`, device = device or "phone", viewport = viewport })
	sim:Advance(1)
	for name, value in
		{ DataMode = "Ready", Money = 100, Income = 0, TankSlots = 6, TankCount = 0, SellRatePct = 100, SellPlace = "" }
	do
		p:SetAttribute(name, value)
	end
	sim:Advance(4.5) -- the base banner has landed, the welcome toast is gone
	return p
end

local function module(sim: any, p: any, name: string): any
	local scripts = p:FindFirstChildOfClass("PlayerScripts")
	local found = sim:Find(`Controllers.{name}`, scripts)
	assert(found, `{name} in PlayerScripts`)
	return sim:Require(found, p)
end

local function panelOf(sim: any, p: any): any
	return module(sim, p, "TankPanelController")
end

local function uifx(sim: any, p: any): any
	return sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p)
end

-- Calls the controller in the client's context (the sheet reads its UserInputService and camera).
local function call(sim: any, p: any, fn: () -> any): any
	return sim:Run(fn, p)
end

local function hudOf(p: any): any
	return p.PlayerGui.HUD
end

local function cardsOf(p: any): any
	return hudOf(p).TankPanel.Panel.Cards
end

local function card(p: any, slot: number | string): any
	return cardsOf(p):FindFirstChild(if slot == "locked" then "Locked" else `Card{slot}`)
end

local function tankEvent(sim: any, p: any, kind: string, data: any)
	sim:Find("ReplicatedStorage.Remotes.TankEvent"):FireClient(p, kind, data)
	sim:Advance(0.05)
end

local function sellsOf(sim: any, p: any): { any }
	return sim:ServerEventsFor(p, "TankSell")
end

local function frameConnections(sim: any, p: any): number
	local ctx = sim:ContextName(p)
	return sim:CountConnections(function(conn: any): boolean
		local signal = conn.signal:describe()
		return conn.ctx.name == ctx
			and (
				string.find(signal, "RenderStepped", 1, true) ~= nil
				or string.find(signal, "Heartbeat", 1, true) ~= nil
				or string.find(signal, "Stepped", 1, true) ~= nil
				or string.find(signal, "PreRender", 1, true) ~= nil
			)
	end)
end

local function clientConnections(sim: any, p: any): number
	local ctx = sim:ContextName(p)
	return sim:CountConnections(function(conn: any): boolean
		return conn.ctx.name == ctx
	end)
end

local function colorNear(a: any, b: any): boolean
	return math.abs(a.R - b.R) <= 0.01 and math.abs(a.G - b.G) <= 0.01 and math.abs(a.B - b.B) <= 0.01
end

-- The Top colour of a sim surface's face.
local function faceTop(root: any): any
	local face = root:FindFirstChild(root:GetAttribute("CandyFace") or "Face")
	return face.Fill.Color.Keypoints[1].Value
end

--------------------------------------------------------------------------------
-- The fake server: TankService's replicated state (design §4.6) and its answers
--------------------------------------------------------------------------------

local Fake = {}
Fake.__index = Fake

local FISH_FIELDS = { "FishUid", "FishId", "Rarity", "Mutation", "Kg", "Value", "Income", "GrowFrom" }

function Fake.new(sim: any, p: any): any
	local index = p:GetAttribute("BaseIndex")
	local base = sim.workspace.Bases:FindFirstChild(`Base_{index}`)
	assert(base, "the player's base")
	return setmetatable({
		sim = sim,
		p = p,
		base = base,
		serial = 0,
		rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules")),
		tank = sim:Require(sim:Find("ReplicatedStorage.Shared.TankRules")),
		fish = {},
		uid = 0,
	}, Fake)
end

function Fake:slot(index: number): any
	return self.base.Tank.Slots[`Slot_{index}`]
end

function Fake:event(slot: any, kind: string, detail: string?)
	self.serial += 1
	slot:SetAttribute("Event", `{self.serial}|{kind}|{detail or ""}`)
end

-- A fish record (Kg = the middle of its range); Age = seconds in the tank.
function Fake:record(id: string, opts: any?): any
	local o = opts or {}
	local def = self.rules.GetFish(id)
	local kg = (def.MinKg + def.MaxKg) / 2
	local value, income = self.rules.Price(id, kg, o.mutation)
	self.uid += 1
	return {
		Uid = o.uid or `f{self.uid}`,
		Id = id,
		Rarity = def.Rarity,
		Mutation = o.mutation,
		Kg = kg,
		Value = value,
		Income10 = self.tank.Income10(income),
		Age = o.age or 0,
		Name = def.Name,
		ShortName = def.ShortName,
	}
end

function Fake:writeFish(slot: any, fish: any)
	slot:SetAttribute("FishUid", fish.Uid)
	slot:SetAttribute("FishId", fish.Id)
	slot:SetAttribute("Rarity", fish.Rarity)
	slot:SetAttribute("Mutation", fish.Mutation)
	slot:SetAttribute("Kg", fish.Kg)
	slot:SetAttribute("Value", fish.Value)
	slot:SetAttribute("Income", fish.Income10 / 10)
	slot:SetAttribute("GrowFrom", self.tank.AttrTime(self.sim.workspace:GetServerTimeNow() - fish.Age))
end

function Fake:totals()
	local count, income10 = 0, 0
	for _, fish in self.fish do
		count += 1
		income10 += fish.Income10
	end
	self.p:SetAttribute("TankCount", count)
	self.p:SetAttribute("TankSlots", self.slots or TankConfig.StartSlots)
	self.p:SetAttribute("Income", income10 / 10)
end

-- Every display: fish 1..#list, the rest empty up to `slots`, then locked; Event "mount".
function Fake:mount(list: { any }, slots: number?)
	local open = slots or TankConfig.StartSlots
	self.slots = open
	self.fish = {}
	for index = 1, TankConfig.MaxSlots do
		local slot = self:slot(index)
		local fish = list[index]
		local state = if index > open then "locked" elseif fish then "fish" else "empty"
		if state == "fish" then
			self:writeFish(slot, fish)
			self.fish[index] = fish
		else
			for _, name in FISH_FIELDS do
				slot:SetAttribute(name, nil)
			end
		end
		slot:SetAttribute("State", state)
		self:event(slot, "mount")
	end
	self:totals()
	self.sim:Advance(0.05)
end

function Fake:store(index: number, fish: any)
	local slot = self:slot(index)
	self:writeFish(slot, fish)
	slot:SetAttribute("State", "fish")
	self.fish[index] = fish
	self:event(slot, "in", fish.Id)
	self:totals()
	self.sim:Advance(0.05)
end

function Fake:swap(index: number, fish: any, price: number)
	local slot = self:slot(index)
	self:writeFish(slot, fish)
	slot:SetAttribute("State", "fish")
	self.fish[index] = fish
	self:event(slot, "swap", string.format("%d", price))
	self:totals()
	self.sim:Advance(0.05)
end

-- The price TankService would pay now for the fish in display index (at ratePct).
function Fake:price(index: number, ratePct: number?): number
	local fish = self.fish[index]
	local slot = self:slot(index)
	local age = self.tank.AgeAt(slot:GetAttribute("GrowFrom"), self.sim.workspace:GetServerTimeNow())
	return self.tank.SellPrice(fish.Value, age, ratePct or 100)
end

-- TankService's sale: the display empties (Event "sold" last), then TankEvent "Sold".
function Fake:sell(index: number): number
	local fish = self.fish[index]
	local price = self:price(index)
	local slot = self:slot(index)
	for _, name in FISH_FIELDS do
		slot:SetAttribute(name, nil)
	end
	slot:SetAttribute("State", "empty")
	self.fish[index] = nil
	self:event(slot, "sold", string.format("%d", price))
	self:totals()
	self.p:SetAttribute("Money", (self.p:GetAttribute("Money") or 0) + price)
	self.sim:Find("ReplicatedStorage.Remotes.TankEvent"):FireClient(self.p, "Sold", {
		Items = { { Uid = fish.Uid, Id = fish.Id, Rarity = fish.Rarity, Mutation = fish.Mutation, Price = price } },
		Amount = price,
		RatePct = 100,
	})
	self.sim:Advance(0.05)
	return price
end

-- 3/6 at home: a Gold Perch, a maxed Puffer, a young Crucian.
local function homeTank(fake: any): { any }
	return {
		fake:record("Perch", { mutation = "Gold", age = 60 }),
		fake:record("Puffer", { age = TankConfig.Growth.Time + 20 }),
		fake:record("Crucian", { age = 20 }),
	}
end

local SIX = { "Crucian", "Perch", "Puffer", "Swordfish", "SharkPup", "DragonFish" }

local function sixTank(fake: any): { any }
	local list = {}
	for i, id in SIX do
		list[i] = fake:record(id, { age = 30 * i, mutation = if i == 6 then "Rainbow" else nil })
	end
	return list
end

-- A player with a mounted tank and the panel open (Toggle, like the «САДОК» press).
local function opened(t: any, device: string?, list: ((fake: any) -> { any })?): (any, any, any, any)
	local sim = boot(t)
	local p = addPlayer(sim, 1, device)
	local fake = Fake.new(sim, p)
	fake:mount((list or homeTank)(fake))
	local panel = panelOf(sim, p)
	t.ok(
		call(sim, p, function()
			return panel.Toggle()
		end),
		"Toggle opens the panel"
	)
	sim:Advance(0.6)
	return sim, p, fake, panel
end

local function tapSell(sim: any, p: any, slot: number)
	sim:Click(p, card(p, slot).Sell)
	sim:Advance(1 / 60)
end

--------------------------------------------------------------------------------
-- Layout helpers (screen px; the sim's own AbsolutePosition / AbsoluteSize)
--------------------------------------------------------------------------------

type Rect = { x0: number, y0: number, x1: number, y1: number }

local function rectOf(gui: any): Rect
	local pos, size = gui.AbsolutePosition, gui.AbsoluteSize
	return { x0 = pos.X, y0 = pos.Y, x1 = pos.X + size.X, y1 = pos.Y + size.Y }
end

local function fmt(r: Rect): string
	return string.format("(%d..%d × %d..%d)", r.x0, r.x1, r.y0, r.y1)
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

-- The quads the HUD draws, in screens (like gui/checks.py fill_metric): every visible GuiObject's
-- background (BackgroundTransparency < 1), text box, ViewportFrame, and each Border UIStroke that
-- shows (its rect grown by its thickness); clipped to the screen and to the card strip (a
-- ScrollingFrame clips its descendants).
local function fillOf(p: any, viewport: any): number
	local hud = hudOf(p)
	local W, H = viewport.X, viewport.Y
	local strip = rectOf(cardsOf(p))
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
		local clip = if item:IsDescendantOf(cardsOf(p)) then strip else nil
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

local tests = {}

--------------------------------------------------------------------------------
-- Names and look
--------------------------------------------------------------------------------

tests["names: the sheet shell, the header, the card templates; the sim look, no studs"] = function(t)
	local sim = boot(t)
	local hud = sim:Find("StarterGui.HUD")
	local root = hud.TankPanel
	t.eq(root.Visible, false, "hidden until opened")
	t.ok(root.ZIndex >= 30, "above HUD.Fishing and the base banner")
	local panel = root.Panel
	t.eq(panel:GetAttribute("CandyStyle"), "sim", "the plate is a sim surface (Night; glass on phones)")
	t.ok(panel.Active, "taps on the plate never reach the world")
	for _, name in { "Strip", "Header", "Close", "Cards" } do
		t.ok(panel:FindFirstChild(name), `Panel.{name}`)
	end
	for _, name in { "Icon", "Title", "Count", "Rate", "Total", "Market" } do
		t.ok(panel.Header:FindFirstChild(name), `Header.{name}`)
	end
	t.eq(panel.Header.Title.Text, TEXTS.Title)
	t.eq(panel.Header.Market.Visible, false, "the market chip waits for SellRatePct > 100")
	t.ok(
		panel.Close:IsA("GuiButton") and panel.Close:FindFirstChildOfClass("UISizeConstraint").MinSize.X >= 44,
		"✕ ≥ 44 px"
	)
	local cards = panel.Cards
	t.ok(cards:IsA("ScrollingFrame") and cards:FindFirstChildOfClass("UIGridLayout"), "Cards: ScrollingFrame + grid")
	t.ok(cards:FindFirstChildOfClass("UIPadding"), "Cards: padding (the mutation chip overhangs)")
	local tpl = cards.CardTemplate
	for _, path in { "NameLabel", "Viewport", "Mutation", "Rate", "Growth", "Sell" } do
		t.ok(tpl:FindFirstChild(path), `CardTemplate.{path}`)
	end
	t.ok(
		tpl.Growth.Track:FindFirstChild("Fill")
			and tpl.Growth:FindFirstChild("Label")
			and tpl.Growth:FindFirstChild("Max"),
		"Growth.{Track.Fill, Label, Max}"
	)
	t.ok(tpl.Sell:FindFirstChild("Caption"), "Sell.Caption")
	t.ok(tpl.Viewport:IsA("ViewportFrame"), "the fish in a ViewportFrame")
	t.eq(tpl:GetAttribute("CandyStyle"), "sim", "a fish card is a sim plate")
	t.eq(cards.EmptyTemplate:GetAttribute("CandyStyle"), "glass", "an empty slot is glass")
	t.eq(cards.EmptyTemplate.Title.Text, TEXTS.Empty)
	t.eq(cards.EmptyTemplate.Hint.Text, TEXTS.EmptyHint)
	t.eq(cards.LockedTemplate.Title.Text, TEXTS.Locked)
	t.eq(cards.LockedTemplate.Hint.Text, TEXTS.LockedHint)
	for _, item in root:GetDescendants() do
		local name = item.Name
		t.ok(not string.find(name, "Stud", 1, true), `no studs in the GUI ({item:GetFullName()})`)
	end
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Open / close
--------------------------------------------------------------------------------

tests["open / close: Toggle, TankEvent Open, ✕; refused during a bite or the catch card; deferred while the fish flies in; closes itself for fishing"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	local fake = Fake.new(sim, p)
	fake:mount(homeTank(fake))
	local panel = panelOf(sim, p)
	local root = hudOf(p).TankPanel
	local function toggle(): boolean
		return call(sim, p, function()
			return panel.Toggle()
		end)
	end
	t.ok(toggle(), "Toggle opens")
	sim:Advance(0.4)
	t.ok(root.Visible and panel.IsOpen(), "open")
	toggle()
	sim:Advance(0.4)
	t.ok(not root.Visible and not panel.IsOpen(), "Toggle again closes (after the pop-out)")

	tankEvent(sim, p, "Open", { Place = "Market", RatePct = 150, Name = "Рыбный рынок" })
	sim:Advance(0.4)
	t.ok(panel.IsOpen(), "TankEvent Open opens it")
	local scale = root.Panel:FindFirstChildOfClass("UIScale")
	sim:Click(p, root.Panel.Close)
	local biggest = 0
	for _ = 1, 8 do
		sim:Advance(0.02)
		scale = scale or root.Panel:FindFirstChildOfClass("UIScale")
		if scale and root.Visible then
			biggest = math.max(biggest, scale.Scale)
		end
	end
	t.ok(biggest <= 1 + 1e-6, `the close only shrinks the sheet (largest UIScale {biggest})`)
	sim:Advance(0.3)
	t.ok(not panel.IsOpen() and not root.Visible, "✕ closes it")

	-- a bite: refused; open → closes at once
	p:SetAttribute("FishingState", "Bite")
	sim:Advance(0.05)
	t.eq(toggle(), false, "refused during a bite")
	t.ok(not root.Visible, "still closed")
	for _, state in { "Bite", "Reeling" } do
		p:SetAttribute("FishingState", "Waiting")
		sim:Advance(0.05)
		t.ok(toggle(), `opens while waiting ({state} next)`)
		sim:Advance(0.3)
		p:SetAttribute("FishingState", state)
		sim:Advance(0.05)
		t.ok(not panel.IsOpen() and not root.Visible, `{state}: the panel is gone at once`)
	end
	p:SetAttribute("FishingState", "Idle")
	sim:Advance(0.05)

	-- the catch card on screen: refused; open → closes
	local catchCard = hudOf(p).Fishing.CatchCard
	toggle()
	sim:Advance(0.3)
	catchCard.Visible = true
	sim:Advance(0.05)
	t.ok(not panel.IsOpen(), "the catch card shows: closed")
	t.eq(toggle(), false, "refused while the catch card shows")
	catchCard.Visible = false
	sim:Advance(0.05)

	-- the fish flies into the button (CounterHold): an open is remembered and happens after it
	local hud = hudOf(p)
	toggle()
	sim:Advance(0.3)
	hud:SetAttribute("CounterHold", 2)
	sim:Advance(0.05)
	t.ok(not panel.IsOpen(), "CounterHold appears: closed")
	t.eq(toggle(), false, "a tap during the flight does not open yet")
	t.ok(panel.Stats().pending, "… it is remembered")
	sim:Advance(0.5)
	t.ok(not panel.IsOpen(), "still closed while the fish flies")
	hud:SetAttribute("CounterHold", nil)
	sim:Advance(0.1)
	t.ok(panel.IsOpen(), "opens right after the arrival")
	t.ok(not panel.Stats().pending, "nothing pending any more")
	sim:AssertNoErrors({ warnings = true })
end

tests["the open sheet covers the fishing layer (UX-04): «ВЗЯТЬ» and its «!» do not show through the glass; back on close and when fishing takes the screen"] = function(
	t
)
	for _, device in { "phone", "tablet" } do
		local sim = boot(t)
		local p = addPlayer(sim, 1, device)
		local fake = Fake.new(sim, p)
		fake:mount(homeTank(fake))
		local panel = panelOf(sim, p)
		local fishing = hudOf(p).Fishing
		local area = fishing.ActionArea
		local root = hudOf(p).TankPanel
		local function toggle(): boolean
			return call(sim, p, function()
				return panel.Toggle()
			end)
		end
		t.ok(
			fishing.Visible and area.Visible,
			`{device}: the action button is up (rod in the backpack: «ВЗЯТЬ»)`
		)
		t.ok(toggle(), `{device}: opens`)
		sim:Advance(0.4)
		local a0, a1 = area.AbsolutePosition, area.AbsolutePosition + area.AbsoluteSize
		local r0, r1 = root.AbsolutePosition, root.AbsolutePosition + root.AbsoluteSize
		local under = a0.X < r1.X and a1.X > r0.X and a0.Y < r1.Y and a1.Y > r0.Y
		t.ok(under, `{device}: the action area lies under the sheet`)
		t.eq(fishing.Visible, false, `{device}: the fishing layer is hidden under the open sheet`)
		t.ok(area.Visible, `{device}: … the widgets' own Visible untouched`)
		toggle()
		sim:Advance(0.05)
		t.eq(fishing.Visible, true, `{device}: back at once when it closes`)
		sim:Advance(0.4)
		-- a bite while open: the sheet goes at once, the layer with it comes back
		toggle()
		sim:Advance(0.3)
		t.eq(fishing.Visible, false, `{device}: hidden again`)
		p:SetAttribute("FishingState", "Waiting")
		sim:Advance(0.05)
		p:SetAttribute("FishingState", "Bite")
		sim:Advance(0.05)
		t.ok(not panel.IsOpen(), `{device}: the bite closes the sheet`)
		t.eq(fishing.Visible, true, `{device}: the fishing layer is back for the bite`)
		p:SetAttribute("FishingState", "Idle")
		sim:Advance(0.05)
		sim:AssertNoErrors({ warnings = true })
	end
end

--------------------------------------------------------------------------------
-- Cards
--------------------------------------------------------------------------------

tests["cards: fish / empty / locked teaser; phone labels (ShortName, «💵 $45»), mutation chip, МАКС, rate; the header"] = function(
	t
)
	local sim, p, fake, panel = opened(t, "phone")
	local R = fake.tank
	local cards = cardsOf(p)
	t.eq(panel.Stats().cards, 7, "6 slots + 1 locked teaser")
	t.ok(card(p, "locked") and card(p, 7) == nil, "one locked card after the open slots")
	t.eq(card(p, "locked").Title.Text, TEXTS.Locked)
	t.eq(card(p, "locked").LayoutOrder, 7, "the teaser comes last")
	for slot = 4, 6 do
		t.eq(card(p, slot).Title.Text, TEXTS.Empty, `Card{slot} is empty`)
	end
	t.eq(cards.CardTemplate.Visible, false, "the templates stay hidden")
	for slot = 1, 3 do
		local fish = fake.fish[slot]
		local c = card(p, slot)
		t.eq(c:GetAttribute("FishUid"), fish.Uid, `Card{slot}: its fish`)
		t.eq(c.Rate.Text, R.FormatRate(fish.Income10), `Card{slot}: «+$X/с»`)
		t.ok(colorNear(c.Rate.TextColor3, UIConfig.MoneyText), "green money text")
		local want = TextFill(TEXTS.SellPhone, { price = R.FormatMoney(fake:price(slot)) })
		t.eq(c.Sell.Caption.Text, want, `Card{slot}: phone caption «💵 $X»`)
		t.ok(colorNear(faceTop(c), UIConfig.Rarity[fish.Rarity].Top), `Card{slot}: the {fish.Rarity} plate`)
		local models = 0
		for _, d in c.Viewport:GetChildren() do
			if d:IsA("Model") then
				models += 1
			end
		end
		t.eq(models, 1, `Card{slot}: one fish model in the viewport`)
		t.ok(c.Viewport:FindFirstChildOfClass("Camera") ~= nil, "its camera framed once")
	end
	t.eq(card(p, 1).NameLabel.Text, "ОКУНЬ", "the phone name is the CAPS ShortName")
	t.eq(card(p, 3).NameLabel.Text, "КАРАСИК")
	t.ok(card(p, 1).Mutation.Visible, "the Gold Perch has its mutation chip")
	t.eq(card(p, 1).Mutation.Label.Text, "×2")
	t.eq(card(p, 1).Mutation.Icon.Text, UIConfig.Mutations.Gold.Icon)
	t.ok(not card(p, 3).Mutation.Visible, "no chip without a mutation")
	t.ok(card(p, 2).Growth.Max.Visible, "the Puffer (past Growth.Time) shows «МАКС»")
	t.ok(not card(p, 2).Growth.Track.Visible, "… instead of its bar")
	t.ok(not card(p, 1).Growth.Max.Visible and card(p, 1).Growth.Label.Text ~= "", "a growing fish shows «×N»")
	-- the header
	local header = hudOf(p).TankPanel.Panel.Header
	t.eq(header.Count.Label.Text, "3/6")
	t.ok(colorNear(faceTop(header.Count), UIConfig.Palette.Cream.Top), "not full: a Cream chip")
	local income10 = 0
	local total = 0
	for slot = 1, 3 do
		income10 += fake.fish[slot].Income10
		total += fake:price(slot)
	end
	t.eq(header.Rate.Text, R.FormatRate(income10), "the tank's income")
	t.eq(
		header.Total.Text,
		TextFill(TEXTS.Total, { money = R.FormatMoney(total) }),
		"«💵 $total 📈» (the Gold Perch still grows)"
	)
	sim:AssertNoErrors({ warnings = true })
end

tests["wide labels: full names and «ПРОДАТЬ $X» only on wide cards and only where they fit; a full tank's chip is Gold"] = function(
	t
)
	local sim, p, fake, panel = opened(t, "desktop", sixTank)
	local stats = panel.Stats()
	t.ok(stats.wide, `desktop cards are ≥ WideCard ({math.floor(stats.cell.X)} px)`)
	local UiFx = uifx(sim, p)
	local full = 0
	for slot = 1, 6 do
		local fish = fake.fish[slot]
		local c = card(p, slot)
		local name = c.NameLabel.Text
		t.ok(name == string.upper(name), "CAPS")
		local px = call(sim, p, function()
			return UiFx.textSize("Small")
		end)
		t.ok(
			UiFx.textWidth(name, px) <= c.NameLabel.AbsoluteSize.X + 0.5,
			`Card{slot}: «{name}» fits its line at {px} px`
		)
		if name ~= fake.rules.GetFish(fish.Id).ShortName and #name > 0 then
			full += 1
		end
		local caption = c.Sell.Caption
		t.ok(UiFx.textWidth(caption.Text, px) <= caption.AbsoluteSize.X + 0.5, `Card{slot}: «{caption.Text}» fits`)
	end
	t.ok(full >= 1, `some desktop cards show the full name ({full})`)
	-- one sell label style for the whole panel (TankCards.sellStyle)
	local styles = {}
	for slot = 1, 6 do
		local caption = card(p, slot).Sell.Caption.Text
		styles[if string.sub(caption, 1, 4) == "💵" then "phone" else "wide"] = true
	end
	t.ok(not (styles.phone and styles.wide), "every sell button of the panel has the same label style")
	t.eq(styles.wide == true, panel.Stats().wideSell, "… the one the panel chose (wideSell) for its longest price")
	-- a mutation chip: the name starts right of its icon
	for slot = 1, 6 do
		local c = card(p, slot)
		if c.Mutation.Visible then
			local icon = rectOf(c.Mutation.Icon)
			t.ok(
				rectOf(c.NameLabel).x0 >= icon.x1 - 0.5,
				`Card{slot}: the name {fmt(rectOf(c.NameLabel))} starts right of the chip's icon {fmt(icon)}`
			)
		end
	end
	t.ok(
		colorNear(faceTop(hudOf(p).TankPanel.Panel.Header.Count), UIConfig.Palette.Gold.Top),
		"6/6: the chip turns Gold"
	)
	-- the phone: every name is the short one
	local sim2 = boot(t)
	local p2 = addPlayer(sim2, 2, "phone")
	local fake2 = Fake.new(sim2, p2)
	fake2:mount(sixTank(fake2))
	local panel2 = panelOf(sim2, p2)
	call(sim2, p2, function()
		return panel2.Open()
	end)
	sim2:Advance(0.5)
	t.ok(not panel2.Stats().wide, "phone cards are narrow")
	for slot = 1, 6 do
		local def = fake2.rules.GetFish(fake2.fish[slot].Id)
		local short = call(sim2, p2, function()
			local TextUtil = sim2:Require(sim2:Find("ReplicatedStorage.Shared.TextUtil"), p2)
			return TextUtil.upper(def.ShortName)
		end)
		t.eq(card(p2, slot).NameLabel.Text, short, `phone Card{slot}: the ShortName`)
		t.ok(string.sub(card(p2, slot).Sell.Caption.Text, 1, 4) == "💵", "phone caption «💵 $X»")
	end
	sim:AssertNoErrors({ warnings = true })
	sim2:AssertNoErrors({ warnings = true })
end

tests["the header fits before the ✕ at a stall with a full tank: «+$X/с» gives way first, the chip sizes to its text; a desktop at 3/6 keeps everything, no dead gap"] = function(
	t
)
	for i, spec in
		{
			{ device = "desktop" },
			{ device = "tablet" },
			{ device = "phone", viewport = Vector2.new(667, 375), name = "phone_small" },
		}
	do
		local sim = boot(t)
		local p = addPlayer(sim, i, spec.device, spec.viewport)
		local fake = Fake.new(sim, p)
		fake:mount(sixTank(fake))
		local panel = panelOf(sim, p)
		call(sim, p, function()
			return panel.Toggle()
		end)
		sim:Advance(0.6)
		local what = spec.name or spec.device
		local header = hudOf(p).TankPanel.Panel.Header
		local close = rectOf(hudOf(p).TankPanel.Panel.Close)
		t.ok(header.Rate.Visible or what ~= "desktop", `{what}: at home the income fits (desktop)`)
		p:SetAttribute("SellRatePct", 150)
		sim:Advance(1)
		t.ok(header.Market.Visible, `{what}: the market chip shows`)
		local UiFx = uifx(sim, p)
		local px = call(sim, p, function()
			return UiFx.textSize("Small")
		end)
		local label = header.Market.Label
		t.ok(
			UiFx.textWidth(label.Text, px) <= label.AbsoluteSize.X + 0.5,
			`{what}: «{label.Text}» fits its chip at {px} px`
		)
		for _, item in header:GetChildren() do
			if item:IsA("GuiObject") and item.Visible then
				local b = rectOf(item)
				t.ok(b.x1 <= close.x0 + 0.5, `{what}: {item.Name} {fmt(b)} left of the ✕ {fmt(close)}`)
			end
		end
		local market = rectOf(header.Market)
		local total = rectOf(header.Total)
		t.ok(market.x0 >= total.x1 - 0.5, `{what}: the chip comes after the total`)
		local shown = {}
		for _, name in { "Title", "Count", "Total", "Market" } do
			if header[name].Visible then
				table.insert(shown, name)
			end
		end
		t.ok(
			header.Count.Visible and header.Total.Visible,
			`{what}: the count and the total always show ({table.concat(shown, ", ")})`
		)
		if header.Rate.Visible then
			t.ok(header.Title.Visible, `{what}: «+$X/с» only shows when everything else fits`)
		end
		p:SetAttribute("SellRatePct", 100)
		sim:Advance(1)
		t.ok(not header.Market.Visible, `{what}: back home: no chip`)
		t.ok(header.Title.Visible, `{what}: «САДОК» is back`)
		sim:AssertNoErrors({ warnings = true })
	end
	-- a desktop at a stall with 3/6: there is room, so nothing gives way (the bare text widths are
	-- tried before anything hides), and the total leaves no dead gap before the chip's 💰
	local sim, p = opened(t, "desktop")
	p:SetAttribute("SellRatePct", 150)
	sim:Advance(1)
	local header = hudOf(p).TankPanel.Panel.Header
	t.ok(
		header.Market.Visible and header.Rate.Visible and header.Title.Visible,
		"desktop 3/6 at a stall: «+$X/с» stays"
	)
	t.eq(
		header.Market.Label.Text,
		TextFill(TEXTS.MarketChip, { bonus = EconomyConfig.MarketRatePct - 100 }),
		"… the full chip"
	)
	local close = rectOf(hudOf(p).TankPanel.Panel.Close)
	for _, item in header:GetChildren() do
		if item:IsA("GuiObject") and item.Visible then
			t.ok(rectOf(item).x1 <= close.x0 + 0.5, `desktop 3/6: {item.Name} left of the ✕`)
		end
	end
	local total, icon = rectOf(header.Total), rectOf(header.Market.Icon)
	local UiFx = uifx(sim, p)
	local px = call(sim, p, function()
		return UiFx.textSize("Body")
	end)
	local ink = UiFx.textWidth(header.Total.Text, px)
	t.ok(icon.x0 >= total.x0 + UiFx.textWidth(header.Total.Text, px - 2) - 0.5, "the 💰 starts past the total's text")
	t.ok(
		icon.x0 - (total.x0 + ink) <= 16,
		`no dead gap: the 💰 at {icon.x0} is ≤ 16 px past the total's text ({total.x0 + ink}; the critic saw 35)`
	)
	sim:AssertNoErrors({ warnings = true })
end

tests["values tick on one 1 s chain while open: prices, bars, the header total; no frame job, no frame connection"] = function(
	t
)
	local sim, p, fake, panel = opened(t, "phone", function(f)
		return { f:record("Puffer", { age = 0 }), f:record("Crucian", { age = TankConfig.Growth.Time - 3 }) }
	end)
	local R = fake.tank
	sim:Advance(1.5) -- the open's pops are over
	t.eq(uifx(sim, p).activeJobs(), 0, "idle and open: no frame job")
	local frames = frameConnections(sim, p)
	call(sim, p, function()
		panel.Close()
	end)
	sim:Advance(0.5)
	t.eq(frameConnections(sim, p), frames, "the open panel adds no RenderStepped / Heartbeat connection")
	call(sim, p, function()
		panel.Open()
	end)
	sim:Advance(1.5)
	t.ok(panel.Stats().ticking, "one task.delay chain")
	local caption = card(p, 1).Sell.Caption
	local before = caption.Text
	local total0 = hudOf(p).TankPanel.Panel.Header.Total.Text
	sim:Advance(30)
	t.ok(caption.Text ~= before, `the Puffer's price grew ({before} → {caption.Text})`)
	t.eq(
		caption.Text,
		TextFill(TEXTS.SellPhone, { price = R.FormatMoney(fake:price(1)) }),
		"the client's price = TankRules.SellPrice now"
	)
	t.ok(hudOf(p).TankPanel.Panel.Header.Total.Text ~= total0, "the header total grows too")
	t.ok(card(p, 2).Growth.Max.Visible, "the Crucian reached «МАКС» while open")
	t.eq(uifx(sim, p).activeJobs(), 0, "still no frame job")
	t.eq(frameConnections(sim, p), frames, "still no frame connection of its own")
	sim:AssertNoErrors({ warnings = true })
end

-- The light rim's stroke of a sim button (Theme.sim: Face.Rim.UIStroke).
local function rimOf(root: any): any
	local face = root:FindFirstChild(root:GetAttribute("CandyFace") or "Face")
	return face.Rim:FindFirstChildOfClass("UIStroke")
end

tests["market mode follows SellRatePct only: chip, ×1.5 prices, Gold buttons (Sun with a white rim on a Legendary card, ART-07) — and back"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	local fake = Fake.new(sim, p)
	local list = homeTank(fake)
	list[4] = fake:record("SharkPup", { age = 30 }) -- Legendary: a yellow → orange card
	fake:mount(list)
	local RIM = UIConfig.Sim.RimAlpha
	local R = fake.tank
	local panel = panelOf(sim, p)
	tankEvent(sim, p, "Open", { Place = "Market", RatePct = 150, Name = "Рыбный рынок" })
	sim:Advance(0.5)
	t.ok(panel.IsOpen(), "the stall's prompt opened the panel")
	local chip = hudOf(p).TankPanel.Panel.Header.Market
	local sell = card(p, 3).Sell
	t.eq(chip.Visible, false, "TankEvent Open's RatePct does not switch the market mode")
	t.eq(sell.Caption.Text, TextFill(TEXTS.SellPhone, { price = R.FormatMoney(fake:price(3, 100)) }), "home prices")
	p:SetAttribute("SellRatePct", 150)
	sim:Advance(0.5)
	t.ok(chip.Visible, "SellRatePct 150: the «РЫНОК +50%» chip pops in")
	t.eq(chip.Label.Text, TextFill(TEXTS.MarketChip, { bonus = EconomyConfig.MarketRatePct - 100 }))
	t.eq(sell.Caption.Text, TextFill(TEXTS.SellPhone, { price = R.FormatMoney(fake:price(3, 150)) }), "×1.5 prices")
	t.ok(colorNear(faceTop(sell), UIConfig.Palette.Gold.Top), "Gold sell buttons")
	t.near(rimOf(sell).Transparency, RIM, 1e-3, "… with the usual light rim")
	local legend = card(p, 4).Sell
	t.ok(
		colorNear(faceTop(legend), UIConfig.Palette.Sun.Top),
		"on the Legendary card (the Gold button's own colours) the market button is darker: Sun"
	)
	t.eq(rimOf(legend).Transparency, 0, "… and its rim is solid white, so it pops off the card")
	p:SetAttribute("SellRatePct", 100)
	sim:Advance(0.5)
	t.eq(chip.Visible, false, "back home: the chip pops out")
	t.ok(colorNear(faceTop(sell), UIConfig.Palette.Leaf.Top), "Leaf again")
	t.ok(colorNear(faceTop(legend), UIConfig.Palette.Leaf.Top), "Leaf on the Legendary card too")
	t.near(rimOf(legend).Transparency, RIM, 1e-3, "… with the usual rim")
	t.eq(
		sell.Caption.Text,
		TextFill(TEXTS.SellPhone, { price = R.FormatMoney(fake:price(3, 100)) }),
		"home prices again"
	)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Selling
--------------------------------------------------------------------------------

tests["confirm on every sale: the first tap and a tap < ConfirmArm after the previous one fire nothing (each restarts the arm); a tap after a pause fires TankSell(uid) once; 3 s reverts; red «−$X/с»; another card cancels"] = function(
	t
)
	local sim, p, fake = opened(t, "phone")
	local R = fake.tank
	sim:Advance(0.6)
	local c1 = card(p, 1)
	local price = c1.Sell.Caption.Text
	tapSell(sim, p, 1)
	t.eq(#sellsOf(sim, p), 0, "the first tap fires nothing")
	t.eq(c1.Sell.Caption.Text, TEXTS.Confirm, "«ПРОДАТЬ?»: the button says what the second tap does")
	t.ok(colorNear(faceTop(c1.Sell), UIConfig.Palette.Berry.Top), "Berry")
	t.ok(c1.Sell:FindFirstChild("FxRingTimer"), "the 3 s ring timer")
	t.eq(c1.Rate.Text, R.FormatRate(-fake.fish[1].Income10), "the card's income flashes «−$X/с»")
	t.ok(colorNear(c1.Rate.TextColor3, UIConfig.Palette.Berry.Top), "… in red")
	sim:Advance(0.15)
	tapSell(sim, p, 1)
	t.eq(#sellsOf(sim, p), 0, "a second tap at +0.15 s (double tap) fires nothing")
	sim:Advance(0.33)
	tapSell(sim, p, 1)
	t.eq(#sellsOf(sim, p), 0, "+0.5 s is only 0.35 s after the previous tap: the arm restarted, nothing")
	t.eq(c1.Sell.Caption.Text, TEXTS.Confirm, "still «ПРОДАТЬ?»")
	sim:Advance(TankConfig.ConfirmArm + 0.05)
	tapSell(sim, p, 1)
	local sells = sellsOf(sim, p)
	t.eq(#sells, 1, "a tap after a pause ≥ ConfirmArm sells")
	t.eq(sells[1] and sells[1].args[1], fake.fish[1].Uid, "TankSell(uid) — only the uid")
	t.eq(sells[1] and sells[1].args.n, 1, "no amount, no price, no slot")
	t.eq(c1.Sell.Caption.Text, TEXTS.Busy, "⏳ until the answer")
	t.ok(not c1.Sell:FindFirstChild("FxRingTimer"), "the ring is gone")
	t.ok(colorNear(c1.Rate.TextColor3, UIConfig.MoneyText), "the rate is green again")
	tapSell(sim, p, 1)
	t.eq(#sellsOf(sim, p), 1, "taps while waiting fire nothing")
	-- no answer: after Panel.SellWait the button comes back
	sim:Advance(PANEL.SellWait + 0.2)
	t.ok(c1.Sell.Caption.Text ~= TEXTS.Busy, "no answer: the button comes back")

	-- 3 s timeout reverts
	local c3 = card(p, 3)
	tapSell(sim, p, 3)
	t.eq(c3.Sell.Caption.Text, TEXTS.Confirm)
	sim:Advance(TankConfig.ConfirmTime + 0.2)
	t.eq(
		c3.Sell.Caption.Text,
		TextFill(TEXTS.SellPhone, { price = R.FormatMoney(fake:price(3)) }),
		"after 3 s: back to the price"
	)
	t.ok(colorNear(faceTop(c3.Sell), UIConfig.Palette.Leaf.Top), "Leaf again")
	t.eq(c3.Rate.Text, R.FormatRate(fake.fish[3].Income10), "«+$X/с» again")
	t.ok(not c3.Sell:FindFirstChild("FxRingTimer"), "no ring left")
	tapSell(sim, p, 3)
	t.eq(#sellsOf(sim, p), 1, "a tap after the timeout is a first tap again")
	-- another card cancels the first
	tapSell(sim, p, 2)
	t.eq(c3.Sell.Caption.Text ~= TEXTS.Confirm, true, "tapping another card cancels the first «ПРОДАТЬ?»")
	t.eq(card(p, 2).Sell.Caption.Text, TEXTS.Confirm, "… and asks on the new one")
	t.eq(#sellsOf(sim, p), 1, "nothing sold")
	t.ok(price ~= "", "(phone caption)")
	sim:AssertNoErrors({ warnings = true })
end

tests["mashing the sell button never sells: taps every 0.2 s for 2 s fire nothing; a deliberate tap after a pause does"] = function(
	t
)
	local sim, p, fake = opened(t, "phone")
	sim:Advance(0.6)
	local c1 = card(p, 1)
	for _ = 1, 10 do
		tapSell(sim, p, 1)
		sim:Advance(0.2 - 1 / 60)
	end
	t.eq(#sellsOf(sim, p), 0, "10 taps 0.2 s apart (a kid mashing): nothing sold")
	t.eq(c1.Sell.Caption.Text, TEXTS.Confirm, "«ПРОДАТЬ?» still asks")
	-- taps at 0, 0.2, 0.45 (the critic's case) on another card
	tapSell(sim, p, 3)
	sim:Advance(0.2 - 1 / 60)
	tapSell(sim, p, 3)
	sim:Advance(0.25 - 1 / 60)
	tapSell(sim, p, 3)
	t.eq(#sellsOf(sim, p), 0, "taps at 0, 0.2, 0.45 s: nothing sold")
	sim:Advance(TankConfig.ConfirmArm + 0.1)
	tapSell(sim, p, 3)
	local sells = sellsOf(sim, p)
	t.eq(#sells, 1, "a tap after a pause ≥ ConfirmArm sells")
	t.eq(sells[1] and sells[1].args[1], fake.fish[3].Uid, "… that card's fish")
	sim:Advance(1)
	t.eq(uifx(sim, p).activeJobs(), 0, "the wiggles are over")
	sim:AssertNoErrors({ warnings = true })
end

tests["Sold: the card turns empty, Celebrate(Amount, card, Rate down) once, the juice ends; closed → no flight; Denied → back + a toast over the sheet"] = function(
	t
)
	local sim, p, fake, panel = opened(t, "phone")
	local money = module(sim, p, "MoneyController")
	local calls = {}
	money.Celebrate = function(amount: number, from: any, opts: any)
		table.insert(calls, { amount = amount, from = from, opts = opts })
	end
	sim:Advance(0.6)
	tapSell(sim, p, 1)
	sim:Advance(0.5)
	tapSell(sim, p, 1)
	t.eq(#sellsOf(sim, p), 1, "sold")
	local before = card(p, 1)
	local amount = fake:sell(1)
	t.eq(#calls, 1, "Celebrate once per Sold")
	t.eq(calls[1] and calls[1].amount, amount, "with the server's Amount")
	t.ok(
		calls[1] and calls[1].from ~= nil and calls[1].from:IsA("GuiObject"),
		"from the card (💵 fly into the Wallet)"
	)
	t.eq(calls[1] and calls[1].opts and calls[1].opts.Rate, "down", "the Wallet's rate rolls down")
	local peak = 0
	for _ = 1, 12 do
		local live = 0
		for _, d in p.PlayerGui:GetDescendants() do
			if string.sub(d.Name, 1, 2) == "Fx" and d.Name ~= "FxScale" then
				live += 1
			end
		end
		peak = math.max(peak, live)
		sim:Advance(0.05)
	end
	t.ok(peak <= 60, `≤ 60 temporary GUI objects during the sale's juice ({peak})`)
	local after = card(p, 1)
	t.ok(after ~= nil and after.Title and after.Title.Text == TEXTS.Empty, "the card turned into an empty card")
	t.ok(before.Parent == nil, "the fish card is gone (its viewport with it)")
	t.eq(hudOf(p).TankPanel.Panel.Header.Count.Label.Text, "2/6", "the header count")
	sim:Advance(2)
	t.eq(uifx(sim, p).activeJobs(), 0, "the juice ends: no frame job left")
	t.eq(#calls, 1, "no second Celebrate from the slot's own «sold» event")

	-- Denied: the button comes back, the card wiggles, a warning toast shows over the sheet
	tapSell(sim, p, 2)
	sim:Advance(0.5)
	tapSell(sim, p, 2)
	t.eq(card(p, 2).Sell.Caption.Text, TEXTS.Busy)
	tankEvent(sim, p, "Denied", { Reason = "missing", Text = TEXTS.Denied.missing })
	sim:Advance(0.3)
	t.ok(card(p, 2).Sell.Caption.Text ~= TEXTS.Busy, "Denied: the button is back")
	local found = false
	for _, toast in hudOf(p).Toasts:GetChildren() do
		local label = toast:FindFirstChild("Label")
		if toast.Name == "Toast" and label and label.Text == TEXTS.Denied.missing then
			found = true
		end
	end
	t.ok(found, "the server's text in a toast")
	t.ok(hudOf(p).Toasts.ZIndex > hudOf(p).TankPanel.ZIndex, "the toasts show over the open sheet")

	-- a Sold while closed: Celebrate without a flight
	call(sim, p, function()
		panel.Close()
	end)
	sim:Advance(0.4)
	t.ok(hudOf(p).Toasts.ZIndex < hudOf(p).TankPanel.ZIndex, "closed: the toasts' layer is back")
	fake:sell(3)
	t.eq(#calls, 2, "Celebrate for the Sold while closed")
	t.eq(calls[2] and calls[2].from, nil, "… with no flight (the card is not on screen)")
	sim:AssertNoErrors({ warnings = true })
end

tests["slot events while open: «in» and «swap» refresh their card only (with a pop)"] = function(t)
	local sim, p, fake = opened(t, "phone")
	sim:Advance(0.6)
	local untouched = card(p, 2)
	fake:store(4, fake:record("SharkPup", { age = 5 }))
	sim:Advance(0.3)
	t.eq(card(p, 4):GetAttribute("FishUid"), fake.fish[4].Uid, "«in»: Card4 shows the new fish")
	t.eq(card(p, 4).NameLabel.Text, "АКУЛЁНОК")
	local swapped = fake:record("Swordfish", { age = 0 })
	fake:swap(1, swapped, 70)
	sim:Advance(0.3)
	t.eq(
		card(p, 1):GetAttribute("FishUid"),
		swapped.Uid,
		"«swap»: State stays fish, the uid changes, the card follows"
	)
	t.eq(card(p, 1).NameLabel.Text, "МЕЧ-РЫБА")
	t.eq(card(p, 2), untouched, "other cards are not rebuilt")
	t.eq(hudOf(p).TankPanel.Panel.Header.Count.Label.Text, "4/6")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

local DEVICES = {
	{ name = "phone", device = "phone" },
	{ name = "phone_small", device = "phone", viewport = Vector2.new(667, 375) },
	{ name = "tablet", device = "tablet" },
	{ name = "desktop", device = "desktop" },
}

-- The Jump button's left edge on a touch screen (FishingLayout.JUMP_SMALL / BIG), screen px.
local function jumpLeft(viewport: any): number
	local small = math.min(viewport.X, viewport.Y) <= 500
	local jump = if small then { right = 25, size = 70 } else { right = 50, size = 120 }
	return viewport.X - jump.right - jump.size
end

local function checkLayout(t: any, sim: any, p: any, viewport: any, touch: boolean, what: string)
	local hud = hudOf(p)
	local root = hud.TankPanel
	local m = PANEL.Margin
	for _, gui in { root, root.Panel, root.Panel.Header, root.Panel.Cards, root.Panel.Close } do
		t.ok(gui.Size.X.Offset == 0 and gui.Size.Y.Offset == 0, `{what}: {gui.Name}.Size is scale-only`)
		t.ok(gui.Position.X.Offset == 0 and gui.Position.Y.Offset == 0, `{what}: {gui.Name}.Position is scale-only`)
	end
	local grid = root.Panel.Cards:FindFirstChildOfClass("UIGridLayout")
	t.ok(grid.CellSize.X.Offset == 0 and grid.CellSize.Y.Offset == 0, `{what}: the card cells are scale-only`)
	t.ok(root.Panel.Cards.CanvasSize.X.Offset == 0, `{what}: the canvas is scale-only`)
	for _, c in root.Panel.Cards:GetChildren() do
		if c:IsA("GuiObject") and c.Visible then
			t.ok(c.Size.X.Offset == 0 and c.Size.Y.Offset == 0, `{what}: {c.Name} is scale-only`)
		end
	end
	local r = rectOf(root)
	t.ok(r.x0 >= m - 0.5, `{what}: ≥ {m} px from the left edge {fmt(r)}`)
	t.ok(r.y1 <= viewport.Y - m + 0.5, `{what}: ≥ {m} px from the bottom`)
	-- never over the status stack (the Wallet) …
	for _, item in hud.Status:GetDescendants() do
		if item:IsA("GuiObject") and visibleChain(item, hud) then
			local s = rectOf(item)
			t.ok(
				s.y1 + m <= r.y0 + 0.5 or s.x1 <= r.x0 or s.x0 >= r.x1,
				`{what}: {item.Name} {fmt(s)} ≥ {m} px above the sheet {fmt(r)}`
			)
		end
	end
	-- … nor the right column («САДОК», «ДОМОЙ»)
	for _, button in hud.RightButtons:GetChildren() do
		if button:IsA("GuiObject") and button.Visible then
			local b = rectOf(button)
			t.ok(r.x1 + m <= b.x0 + 0.5, `{what}: {button.Name} {fmt(b)} right of the sheet {fmt(r)} by ≥ {m} px`)
		end
	end
	if touch then
		t.ok(
			r.x1 + m <= jumpLeft(viewport) + 0.5,
			`{what}: ≥ {m} px left of the Jump button ({r.x1} vs {jumpLeft(viewport)})`
		)
	end
	if touch then
		-- the thumbstick (bottom-left, like gui/backdrop.py): the sheet starts right of it or ends above it
		local small = math.min(viewport.X, viewport.Y) <= 500
		local stickRight, stickTop = if small then 95 else 180, viewport.Y - (if small then 90 else 210)
		t.ok(
			r.x0 >= stickRight + m - 0.5 or r.y1 <= stickTop - m + 0.5,
			`{what}: the sheet {fmt(r)} keeps ≥ {m} px off the thumbstick (to x {stickRight}, from y {stickTop})`
		)
	end
	if hud.AbsoluteSize.Y >= PANEL.TallFrom then
		-- several rows fill by columns ([1, 2] [3, 4] [5, 6] [🔒]): at rest every fish card is fully
		-- in the window — only the teaser's column may peek past its edge
		local window = rectOf(root.Panel.Cards)
		local one, two, three = rectOf(card(p, 1)), rectOf(card(p, 2)), rectOf(card(p, 3))
		t.ok(math.abs(two.x0 - one.x0) < 1 and two.y0 > one.y1, `{what}: Card2 {fmt(two)} under Card1 {fmt(one)}`)
		t.ok(three.x0 > one.x1 and math.abs(three.y0 - one.y0) < 1, `{what}: Card3 {fmt(three)} right of Card1`)
		for _, c in root.Panel.Cards:GetChildren() do
			if c:IsA("GuiObject") and c.Visible and c:GetAttribute("FishUid") then
				local r = rectOf(c)
				t.ok(
					r.x0 >= window.x0 - 1 and r.x1 <= window.x1 + 1 and r.y0 >= window.y0 - 1 and r.y1 <= window.y1 + 1,
					`{what}: fish {c.Name} {fmt(r)} fully in the window {fmt(window)}`
				)
			end
		end
	end
	local close = rectOf(root.Panel.Close)
	t.ok(close.x1 - close.x0 >= 44 - 0.5, `{what}: ✕ ≥ 44 px`)
	-- the header: everything before the ✕
	for _, item in root.Panel.Header:GetChildren() do
		if item:IsA("GuiObject") and item.Visible then
			local b = rectOf(item)
			t.ok(b.x1 <= close.x0 + 0.5, `{what}: header {item.Name} {fmt(b)} left of the ✕ {fmt(close)}`)
		end
	end
	local function edgeOf(gui: any): number
		return gui.Lip:FindFirstChildOfClass("UIStroke").Thickness
	end
	for _, c in root.Panel.Cards:GetChildren() do
		local sell = c:FindFirstChild("Sell")
		if c:IsA("GuiObject") and c.Visible and sell then
			t.ok(sell.AbsoluteSize.Y >= 44 - 0.5, `{what}: {c.Name}'s sell button ≥ 44 px tall`)
			-- one row above the sell button's outline: the income on the left, the growth pill (and
			-- «МАКС» with its outline) on the right, side by side
			local s, g, stamp, rate = rectOf(sell), rectOf(c.Growth), rectOf(c.Growth.Max), rectOf(c.Rate)
			local top = s.y0 - edgeOf(sell)
			t.ok(g.y1 <= top + 0.5, `{what}: {c.Name}'s growth pill {fmt(g)} above the sell outline (y {top})`)
			t.ok(rate.y1 <= top + 0.5, `{what}: {c.Name}'s income {fmt(rate)} above the sell outline (y {top})`)
			t.ok(
				stamp.y1 + edgeOf(c.Growth.Max) <= top + 0.5,
				`{what}: {c.Name}'s «МАКС» {fmt(stamp)} + outline above the sell outline (y {top})`
			)
			t.ok(math.abs(rate.y0 - g.y0) < 1, `{what}: {c.Name}'s income and growth share a row`)
			t.ok(
				rate.x1 <= stamp.x0 - edgeOf(c.Growth.Max) + 0.5,
				`{what}: {c.Name}'s income {fmt(rate)} left of «МАКС» + outline {fmt(stamp)}`
			)
			local UiFx = uifx(sim, p)
			local least = call(sim, p, function()
				return UiFx.textSize("Body")
			end) - 2
			t.ok(
				UiFx.textWidth(c.Rate.Text, least) <= rate.x1 - rate.x0 + 0.5,
				`{what}: {c.Name}'s «{c.Rate.Text}» fits its box at {least} px`
			)
			-- the fish is the card's biggest piece: the freed row is its (design: ≥ 40 % «aim»; the
			-- smallest phone's card is 131 px tall and its texts are a phone's)
			local fish, cardRect = rectOf(c.Viewport), rectOf(c)
			local share = (fish.y1 - fish.y0) / (cardRect.y1 - cardRect.y0)
			t.ok(
				share >= 0.36,
				`{what}: {c.Name}'s fish window {string.format("%.0f", share * 100)} % of the card ≥ 36 %`
			)
			t.ok(fish.y1 <= rate.y0 + 0.5, `{what}: {c.Name}'s fish {fmt(fish)} above the income row`)
		end
	end
end

tests["layout: scale-based, under the Wallet, left of the right column and Jump, on phone / small phone / tablet / desktop; survives a ViewportSize change"] = function(
	t
)
	for i, spec in DEVICES do
		local sim = boot(t)
		local p = addPlayer(sim, i, spec.device, spec.viewport)
		hudOf(p).Status.Wallet.Visible = true -- (Wave 2 C shows it once the data is loaded)
		local fake = Fake.new(sim, p)
		fake:mount(sixTank(fake))
		local panel = panelOf(sim, p)
		call(sim, p, function()
			return panel.Toggle()
		end)
		sim:Advance(1)
		local viewport = spec.viewport or sim.players.state[sim:Unwrap(p)].viewport
		local touch = spec.device ~= "desktop"
		checkLayout(t, sim, p, viewport, touch, spec.name)
		-- the first tap names the action: «ПРОДАТЬ?» fits every device's card (it falls back to
		-- «ТОЧНО?» only on a card too narrow for it)
		tapSell(sim, p, 1)
		local caption = card(p, 1).Sell.Caption
		t.eq(caption.Text, TEXTS.Confirm, `{spec.name}: «{TEXTS.Confirm}» on the first tap`)
		local UiFx = uifx(sim, p)
		local least = call(sim, p, function()
			return UiFx.textSize("Small")
		end) - 2
		t.ok(
			UiFx.textWidth(caption.Text, least) <= caption.AbsoluteSize.X + 0.5,
			`{spec.name}: «{caption.Text}» fits its button at {least} px`
		)
		sim:Advance(TankConfig.ConfirmTime + 0.2)
		local plate = rectOf(hudOf(p).TankPanel)
		if spec.device ~= "phone" then
			t.ok(
				plate.x1 - plate.x0 <= PANEL.MaxWidth + 0.5 and plate.y1 - plate.y0 <= PANEL.MaxHeight + 0.5,
				`{spec.name}: capped`
			)
		end
		if spec.name == "phone" then
			-- the screen turns into a smaller phone while open
			local small = Vector2.new(667, 375)
			sim:SetViewport(p, small)
			call(sim, p, function()
				panel.Relayout()
			end)
			sim:Advance(0.1)
			checkLayout(t, sim, p, small, true, "phone → 667×375")
		end
		sim:AssertNoErrors({ warnings = true })
	end
end

tests["Open(uid) scrolls to the fish and rings it; opening hides the «!» on «САДОК»"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	local fake = Fake.new(sim, p)
	fake:mount(sixTank(fake))
	local badge = hudOf(p).RightButtons.TankButton.Badge
	hudOf(p).RightButtons.TankButton.Visible = true
	badge.Visible = true -- (Wave 2 C's onboarding «!» after the first fish ever)
	local panel = panelOf(sim, p)
	t.ok(
		call(sim, p, function()
			return panel.Open(fake.fish[6].Uid)
		end),
		"Open(uid)"
	)
	sim:Advance(0.05)
	local cards = cardsOf(p)
	t.ok(cards.CanvasPosition.X > 0, `the strip scrolled to the last fish ({cards.CanvasPosition.X})`)
	local six = card(p, 6)
	local window = rectOf(cards)
	local r = rectOf(six)
	t.ok(r.x0 >= window.x0 - 1 and r.x1 <= window.x1 + 1, `Card6 {fmt(r)} is in the window {fmt(window)}`)
	t.ok(six:FindFirstChild("FxRing"), "a ring in its rarity colour")
	sim:Advance(0.5)
	t.eq(badge.Visible, false, "the onboarding «!» is gone on the first open")
	sim:AssertNoErrors({ warnings = true })
end

tests["nothing left running after close: connections back to the baseline, no clones, no frame job"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	local fake = Fake.new(sim, p)
	fake:mount(sixTank(fake))
	local panel = panelOf(sim, p)
	sim:Advance(1)
	local base = clientConnections(sim, p)
	for round = 1, 2 do
		call(sim, p, function()
			return panel.Toggle()
		end)
		sim:Advance(0.8)
		t.ok(clientConnections(sim, p) > base, `round {round}: open — the slots, the presses, the sheet listen`)
		tapSell(sim, p, 2) -- a confirm with its ring left running …
		p:SetAttribute("SellRatePct", 150)
		sim:Advance(0.2)
		call(sim, p, function()
			panel.Close()
		end) -- … and closed in the middle of it
		sim:Advance(1.5)
		p:SetAttribute("SellRatePct", 100)
		sim:Advance(0.1)
		t.eq(
			clientConnections(sim, p),
			base,
			`round {round}: closed — the client's connections are back to the baseline`
		)
		t.eq(uifx(sim, p).activeJobs(), 0, "no frame job")
		local left = 0
		for _, c in cardsOf(p):GetChildren() do
			if c:IsA("GuiObject") and not string.find(c.Name, "Template", 1, true) then
				left += 1
			end
		end
		t.eq(left, 0, "no card clones (no viewports, no fish models) left")
		t.ok(not panel.Stats().ticking, "the 1 s chain has stopped")
		t.eq(panel.Stats().confirm, nil, "no confirm left")
	end
	sim:AssertNoErrors({ warnings = true })
end

tests["phone fill ≤ 2.5× with the panel open: 6 cards and the teaser"] = function(t)
	for _, spec in { DEVICES[1], DEVICES[2] } do
		local sim = boot(t)
		local p = addPlayer(sim, 1, spec.device, spec.viewport)
		local hud = hudOf(p)
		hud.Status.Wallet.Visible = true
		hud.RightButtons.TankButton.Visible = true
		local fake = Fake.new(sim, p)
		fake:mount(sixTank(fake))
		local panel = panelOf(sim, p)
		call(sim, p, function()
			return panel.Toggle()
		end)
		sim:Advance(1.2)
		local viewport = spec.viewport or sim.players.state[sim:Unwrap(p)].viewport
		local fill = fillOf(p, Vector2.new(viewport.X, viewport.Y))
		t.ok(fill <= 2.5, `{spec.name}: fill {string.format("%.2f", fill)}× ≤ 2.5× (6 fish cards + the teaser)`)
		sim:AssertNoErrors({ warnings = true })
	end
end

return tests
