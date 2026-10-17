--[[
	Stage 3 HUD (design §6.1–6.3, §6.5–6.8, §7.5) in RbxSim against the built Place1.rbxl: the
	Wallet (MoneyController), the «САДОК» button (TankButtonController) and the catch → tank on the
	catch card (FishingController + CatchFx), on the real client.

	The stage 3 services and FishingService are switched off ("return {}"): the test plays the
	server — it writes the player attributes (DataMode, Money, Income, TankCount, TankSlots,
	SellRatePct) the way DataService / EconomyService / TankService do, and sends FishingState
	"Caught" with its TankResult after them (RemoteNames: crediting → attributes → remotes). The
	tank panel (wave 2 D) is replaced by a recorder that writes what «САДОК» asked of it on the HUD
	(attributes PanelCalls / PanelLast), so this file checks only the button's side of that contract.

	What is checked:
	  • the names and the layout on phone / notched phone / small phone / tablet / desktop: nothing
	    overlaps, the long Wallet row fits (the number ≥ 22 px), «САДОК» ≥ 44 px over «ДОМОЙ» and
	    ≥ 16 px above the Jump button, its chip inside it;
	  • the Wallet's texts (TankRules.FormatMoney / FormatRate: «$1 234», «$1.23M», «+$4.2/с»; the
	    rate hidden at 0), the Wallet with no base (a queued player owns money too), «$…» on glass
	    after 3 s of loading, the pop-in order badge → Wallet → «САДОК»;
	  • idle with income: plain-text ticks, the 5 s «+$N» float only, no frame job, no connection
	    churn; the tick never fights a count-up (K-11), a sale's jump waits for its celebration;
	  • the catch: the stamp, «САДОК» frozen under CounterHold and the arrival in rarity colours;
	    "sold" — the card flies into Wallet.Money as 💵, the Wallet counts up only then, «Садок
	    полон…» once per session; "replaced" — coins from «САДОК» to the Wallet, then the toast
	    naming both fish; the onboarding «!» after the first fish ever, gone on the first open; a
	    tap during the flight opens the panel after the arrival, on the new fish; the first-fish
	    toast and the memory-mode toast once.

	Run: lune run tools/run_tests.luau stage3_hud
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Enum = roblox.Enum
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3

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

local UIConfig = loadConfig("UIConfig")
local TankConfig = loadConfig("TankConfig")
local EconomyConfig = loadConfig("EconomyConfig")
local DataConfig = loadConfig("DataConfig")
local FishingConfig = loadConfig("FishingConfig")
local WALLET = UIConfig.Wallet
local SPEC = UIConfig.TankButton

local CATCHES = {
	Common = { Id = "Crucian", Rarity = "Common", Kg = 0.84, Value = 11, Income = 1.1 },
	Rare = { Id = "Puffer", Rarity = "Rare", Kg = 2.1, Value = 58, Income = 5.2 },
	Epic = { Id = "Swordfish", Rarity = "Epic", Kg = 63.5, Value = 182, Income = 15.6 },
}

-- The tank panel's stand-in: what «САДОК» asks of TankPanelController, written on the HUD.
local FAKE_PANEL = [[
local Panel = {}
local hud = nil
local function log(what)
	if hud then
		hud:SetAttribute("PanelCalls", (hud:GetAttribute("PanelCalls") or 0) + 1)
		hud:SetAttribute("PanelLast", what)
	end
end
function Panel:Start(screen)
	hud = screen
end
function Panel.Toggle()
	log("Toggle")
end
function Panel.Open(uid)
	log("Open:" .. tostring(uid))
end
function Panel.Close() end
function Panel.IsOpen()
	return false
end
return Panel
]]

--------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------

type Opts = {
	device: string?,
	viewport: any?,
	mode: string?, -- DataMode ("Ready" by default; "none" — not written)
	money: number?,
	income: number?,
	count: number?,
}

local function boot(t: any, oneBase: boolean?): any
	local sim = t.sim({ place = PLACE })
	for _, name in STUBBED do
		sim:Find(`ServerScriptService.Services.{name}`).Source = "return {}"
	end
	if oneBase then -- (BaseConfig's debug knob: the second player waits in the queue)
		local config = sim:Find("ReplicatedStorage.Shared.Config.BaseConfig")
		local source, n = string.gsub(config.Source, "MaxBases = nil :: number%?", "MaxBases = 1 :: number?")
		assert(n == 1, "BaseConfig.MaxBases")
		config.Source = source
	end
	sim:Find("StarterPlayer.StarterPlayerScripts.Controllers.TankPanelController").Source = FAKE_PANEL
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

-- A player whose data has loaded (what DataService / EconomyService / TankService write).
local function join(sim: any, id: number, opts: Opts?): any
	local o: Opts = opts or {}
	local p = sim:AddPlayer({
		UserId = id,
		Name = `Wallet{id}`,
		device = o.device or "desktop",
		viewport = o.viewport,
	})
	if o.mode ~= "none" then
		p:SetAttribute("DataMode", o.mode or "Ready")
	end
	p:SetAttribute("Money", o.money or 0)
	p:SetAttribute("Income", o.income or 0)
	p:SetAttribute("TankCount", o.count or 0)
	p:SetAttribute("TankSlots", TankConfig.StartSlots)
	p:SetAttribute("SellRatePct", 100)
	sim:Advance(0.5)
	return p
end

local function hudOf(p: any): any
	return p.PlayerGui.HUD
end

-- The Wallet and «САДОК» have popped in (after the base banner) and settled.
local function chromeIn(sim: any, p: any, noTank: boolean?): boolean
	local hud = hudOf(p)
	local ok = sim:WaitFor(function()
		return hud.Status.Wallet.Visible and (noTank or hud.RightButtons.TankButton.Visible)
	end, 10) == true
	sim:Advance(1.5)
	return ok
end

local function controller(sim: any, p: any, name: string): any
	local module = sim:Find(`Controllers.{name}`, p:FindFirstChildOfClass("PlayerScripts"))
	assert(module, `{name} in PlayerScripts`)
	return sim:Require(module, p)
end

local function uiFx(sim: any, p: any): any
	return sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p)
end

local function tankRules(sim: any, p: any): any
	return sim:Require(sim:Find("ReplicatedStorage.Shared.TankRules"), p)
end

local function colorNear(a: any, b: any, eps: number?): boolean
	local e = eps or 0.01
	return math.abs(a.R - b.R) <= e and math.abs(a.G - b.G) <= e and math.abs(a.B - b.B) <= e
end

local function toastTexts(p: any): { string }
	local list = {}
	for _, c in hudOf(p).Toasts:GetChildren() do
		if c.Name == "Toast" then
			table.insert(list, c.Label.Text)
		end
	end
	return list
end

-- Every toast text seen while stepping `seconds` (toasts come and go).
local function watchToasts(sim: any, p: any, seconds: number): { [string]: number }
	local seen: { [string]: number } = {}
	local live: { [any]: boolean } = {}
	local steps = math.ceil(seconds / 0.05)
	for _ = 1, steps do
		sim:Advance(0.05)
		for _, c in hudOf(p).Toasts:GetChildren() do
			if c.Name == "Toast" and not live[c] then
				live[c] = true
				seen[c.Label.Text] = (seen[c.Label.Text] or 0) + 1
			end
		end
	end
	return seen
end

-- Rod in hand at the own fishing spot (FishingService is off: the test gives the rod).
local function ready(sim: any, p: any)
	local template = sim:Find("ReplicatedStorage.Assets.Rods.RodBamboo")
	local rod = template:Clone()
	rod.Name = template:GetAttribute("DisplayName")
	rod.Parent = p:FindFirstChildOfClass("Backpack")
	p:SetAttribute("RodId", "RodBamboo")
	p:SetAttribute("FishingState", "Idle")
	p:SetAttribute("FishCaught", 0)
	sim:Advance(0.05)
	local base = sim.workspace.Bases:FindFirstChild(`Base_{p:GetAttribute("BaseIndex")}`)
	sim:Teleport(p, base.FishingSpot.CFrame.Position + Vector3.new(0, 3, 0))
	sim:Advance(0.3)
	sim:EquipTool(p, rod)
	sim:Advance(0.3)
end

-- The server's catch: the tank (and money) attributes first, then "Caught" with the TankResult.
local function catchTank(
	sim: any,
	p: any,
	fish: { [string]: any },
	total: number,
	tank: { [string]: any },
	money: number?
)
	p:SetAttribute("FishCaught", total)
	p:SetAttribute("TankCount", tank.Count)
	p:SetAttribute("TankSlots", tank.Slots)
	if money then
		p:SetAttribute("Money", money)
	end
	sim:Find("ReplicatedStorage.Remotes.FishingState"):FireClient(p, "Caught", {
		Fish = fish,
		Total = total,
		Tank = tank,
	})
	sim:Advance(0.05)
end

local CARD_OPENS = FishingConfig.LeapTime + 0.3 + 1.8

local function openCard(sim: any, p: any): boolean
	local card = hudOf(p).Fishing.CatchCard
	return sim:WaitFor(function()
		return card.Visible
	end, CARD_OPENS + 0.5, 1 / 60) == true
end

-- Tap the card closed once it is shown whole (its close hint is in); true if a tap closed it.
local function closeCard(sim: any, p: any): boolean
	local card = hudOf(p).Fishing.CatchCard
	sim:WaitFor(function()
		return not card.Visible or card.TapHint.TextTransparency < 0.5
	end, 4, 1 / 60)
	if not card.Visible then
		return false
	end
	sim:Advance(0.1)
	sim:Click(p, card)
	sim:Advance(0.02)
	return not card.Visible
end

-- The 🐟 (or 💵) has flown in: the catch card's CounterHold is gone.
local function arrived(sim: any, p: any): boolean
	local hud = hudOf(p)
	return sim:WaitFor(function()
		return hud:GetAttribute("CounterHold") == nil
	end, 3, 1 / 60) == true
end

local function center(gui: any): any
	return gui.AbsolutePosition + gui.AbsoluteSize / 2
end

-- Layout ---------------------------------------------------------------------------------------

type Rect = { x: number, y: number, w: number, h: number }

local function visibleItems(parent: any): { any }
	local items = {}
	for _, c in parent:GetChildren() do
		if c:IsA("GuiObject") and c.Visible then
			table.insert(items, c)
		end
	end
	table.sort(items, function(a, b)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return a.Name < b.Name
	end)
	return items
end

-- Absolute rectangle like Roblox lays it out (incl. list alignment, which the sim ignores).
local function rectOf(sim: any, p: any, gui: any): Rect
	local parent = gui.Parent
	local size = gui.AbsoluteSize
	if parent:IsA("LayerCollector") then
		local vp = sim.players.state[sim:Unwrap(p)].viewport
		local prect = { x = 0, y = INSET, w = vp.X, h = vp.Y - INSET }
		local pos, anchor = gui.Position, gui.AnchorPoint
		return {
			x = prect.x + pos.X.Scale * prect.w + pos.X.Offset - anchor.X * size.X,
			y = prect.y + pos.Y.Scale * prect.h + pos.Y.Offset - anchor.Y * size.Y,
			w = size.X,
			h = size.Y,
		}
	end
	local prect = rectOf(sim, p, parent)
	local list = parent:FindFirstChildOfClass("UIListLayout")
	if list then
		local vertical = list.FillDirection == Enum.FillDirection.Vertical
		local pad = list.Padding
		local padPx = pad.Scale * (if vertical then prect.h else prect.w) + pad.Offset
		local total, along, found = 0, 0, false
		for i, c in visibleItems(parent) do
			local s = c.AbsoluteSize
			local extent = if vertical then s.Y else s.X
			if c == gui then
				found = true
			end
			if not found then
				along += extent + padPx
			end
			total += extent + (if i > 1 then padPx else 0)
		end
		local main = if vertical then prect.h else prect.w
		local cross = if vertical then prect.w else prect.h
		local mainAlign = if vertical then list.VerticalAlignment.Name else list.HorizontalAlignment.Name
		local crossAlign = if vertical then list.HorizontalAlignment.Name else list.VerticalAlignment.Name
		local start = if mainAlign == "Center"
			then (main - total) / 2
			elseif mainAlign == "Bottom" or mainAlign == "Right" then main - total
			else 0
		local crossSize = if vertical then size.X else size.Y
		local crossPos = if crossAlign == "Center"
			then (cross - crossSize) / 2
			elseif crossAlign == "Bottom" or crossAlign == "Right" then cross - crossSize
			else 0
		if vertical then
			return { x = prect.x + crossPos, y = prect.y + start + along, w = size.X, h = size.Y }
		end
		return { x = prect.x + start + along, y = prect.y + crossPos, w = size.X, h = size.Y }
	end
	local pos, anchor = gui.Position, gui.AnchorPoint
	return {
		x = prect.x + pos.X.Scale * prect.w + pos.X.Offset - anchor.X * size.X,
		y = prect.y + pos.Y.Scale * prect.h + pos.Y.Offset - anchor.Y * size.Y,
		w = size.X,
		h = size.Y,
	}
end

local function overlap(a: Rect, b: Rect): number
	local dx = math.min(a.x + a.w, b.x + b.w) - math.max(a.x, b.x)
	local dy = math.min(a.y + a.h, b.y + b.h) - math.max(a.y, b.y)
	if dx <= 0 or dy <= 0 then
		return 0
	end
	return dx * dy
end

local function fmt(r: Rect): string
	return string.format("(%d,%d %dx%d)", r.x, r.y, r.w, r.h)
end

local tests = {}

--------------------------------------------------------------------------------
-- Names, look, layout
--------------------------------------------------------------------------------

tests["names and layout: phone, notched phone, small phone, tablet, desktop — the long Wallet row fits, «САДОК» over «ДОМОЙ» clear of Jump"] = function(
	t
)
	local sim = boot(t)
	local devices = {
		{ name = "phone", device = "phone" },
		-- (the notched phone's safe area: 844 × 390 less the 47 / 47 / 21 px insets)
		{ name = "phone_notch", device = "phone", viewport = Vector2.new(750, 369) },
		{ name = "phone_small", device = "phone", viewport = Vector2.new(667, 375) },
		{ name = "tablet", device = "tablet" },
		{ name = "desktop", device = "desktop" },
	}
	local players = {}
	for i, d in devices do
		players[d.name] = join(sim, i, {
			device = d.device,
			viewport = d.viewport,
			money = 999999,
			income = 1234,
			count = 4,
		})
	end
	for _, d in devices do
		t.ok(chromeIn(sim, players[d.name]), `{d.name}: the Wallet and «САДОК» popped in`)
	end
	for _, d in devices do
		sim:Find("ReplicatedStorage.Remotes.Notify"):FireClient(players[d.name], "Ура!", "success")
	end
	sim:Advance(1)

	for _, d in devices do
		local p = players[d.name]
		local hud = hudOf(p)
		local vp = sim.players.state[sim:Unwrap(p)].viewport
		local what = d.name
		-- The contract names (controllers, tests and scenarios find widgets by name).
		for _, path in
			{
				"Status.Wallet.Money.Icon",
				"Status.Wallet.Money.Label",
				"Status.Wallet.Money.Back",
				"Status.Wallet.Rate",
				"RightButtons.TankButton.Icon",
				"RightButtons.TankButton.Caption",
				"RightButtons.TankButton.Count.Label",
				"RightButtons.TankButton.Badge",
				"Fishing.CatchCard.TankStamp.Label",
			}
		do
			t.ok(sim:Gui(p, `HUD.{path}`), `{what}: HUD.{path}`)
		end
		t.eq(hud.Status.Wallet.Money.Label.Text, "$999\u{00A0}999", `{what}: the money`)
		t.eq(hud.Status.Wallet.Rate.Text, "+$1\u{00A0}234/с", `{what}: the rate`)
		t.eq(hud.RightButtons.TankButton.Count.Label.Text, "4/6", `{what}: the chip`)
		t.eq(hud.Fishing.CatchCard.TankStamp.Visible, false, `{what}: no stamp at rest`)

		local function r(gui: any): Rect
			return rectOf(sim, p, gui)
		end
		local rects: { [string]: Rect } = {
			badge = r(hud.Status.BaseBadge),
			money = r(hud.Status.Wallet.Money),
			tank = r(hud.RightButtons.TankButton),
			home = r(hud.RightButtons.HomeButton),
		}
		if hud.Status.Wallet.Rate.Visible then
			rects.rate = r(hud.Status.Wallet.Rate)
		end
		for _, c in hud.Toasts:GetChildren() do
			if c.Name == "Toast" then
				rects.toast = r(c)
			end
		end
		for name, rect in rects do
			t.ok(rect.x >= 0 and rect.x + rect.w <= vp.X, `{what}: {name} {fmt(rect)} inside the width`)
			t.ok(rect.y >= INSET and rect.y + rect.h <= vp.Y, `{what}: {name} {fmt(rect)} inside the height`)
		end
		local names = {}
		for name in rects do
			table.insert(names, name)
		end
		table.sort(names)
		for i = 1, #names do
			for j = i + 1, #names do
				local a, b = rects[names[i]], rects[names[j]]
				t.eq(overlap(a, b), 0, `{what}: {names[i]} {fmt(a)} overlaps {names[j]} {fmt(b)}`)
			end
		end
		-- The long number stays readable: shrunk, never under MinMoney px (else the rate goes).
		local label = hud.Status.Wallet.Money.Label
		t.ok(
			label.AbsoluteSize.Y >= WALLET.MinMoney - 0.5,
			`{what}: «$999 999» ≥ {WALLET.MinMoney} px ({label.AbsoluteSize.Y})`
		)
		-- «САДОК»: a full tap target over «ДОМОЙ», the column above the Jump button.
		local tank, home = rects.tank, rects.home
		t.ok(tank.w >= 44 and tank.h >= 44, `{what}: «САДОК» ≥ 44 px {fmt(tank)}`)
		t.ok(tank.y + tank.h <= home.y, `{what}: «САДОК» over «ДОМОЙ»`)
		if d.device ~= "desktop" then
			local small = math.min(vp.X, vp.Y) <= 500
			local jumpTop = if small then vp.Y - 90 else vp.Y - 210
			t.ok(home.y + home.h + 16 <= jumpTop, `{what}: the column {fmt(home)} ≥ 16 px above Jump (y {jumpTop})`)
		end
		local chip = r(hud.RightButtons.TankButton.Count)
		t.ok(
			chip.x >= tank.x - 3 and chip.y >= tank.y - 3 and chip.x + chip.w <= tank.x + tank.w + 3,
			`{what}: the chip {fmt(chip)} inside «САДОК» {fmt(tank)}`
		)
	end
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The Wallet
--------------------------------------------------------------------------------

tests["Wallet: «$0», «$1 234», «$1.23M»; the rate «+$4.2/с» rolls in, hidden at 0"] = function(t)
	local sim = boot(t)
	local p = join(sim, 1, { device = "phone" })
	t.ok(chromeIn(sim, p))
	local wallet = hudOf(p).Status.Wallet
	local TankRules = tankRules(sim, p)
	t.eq(wallet.Money.Label.Text, "$0", "a new player: «$0»")
	t.eq(wallet.Rate.Visible, false, "no rate while the income is 0")
	t.eq(TankRules.FormatMoney(1234567), "$1.23M", "big sums are short")
	for _, case in { { 1234, "$1\u{00A0}234" }, { 999999, "$999\u{00A0}999" }, { 1234567, "$1.23M" } } do
		p:SetAttribute("Money", case[1])
		sim:Advance(WALLET.SaleWait + WALLET.Count.Max + 0.3) -- (a jump: it waits, then counts up)
		t.eq(wallet.Money.Label.Text, case[2], `the Wallet shows {case[2]}`)
	end
	p:SetAttribute("Income", 4.2)
	sim:Advance(0.05)
	t.eq(wallet.Rate.Visible, true, "the rate appears with the income")
	sim:Advance(WALLET.RateRoll + 0.1)
	t.eq(wallet.Rate.Text, "+$4.2/с", "… and rolls to «+$4.2/с»")
	p:SetAttribute("Income", 1234)
	sim:Advance(WALLET.RateRoll + 0.1)
	t.eq(wallet.Rate.Text, "+$1\u{00A0}234/с")
	p:SetAttribute("Income", 0)
	sim:Advance(WALLET.RateRoll + 0.3)
	t.eq(wallet.Rate.Visible, false, "hidden again at 0")
	sim:AssertNoErrors({ warnings = true })
end

tests["Wallet with no base: a queued player's money shows when the data loads; «САДОК» waits for a base"] = function(
	t
)
	local sim = boot(t, true)
	join(sim, 1, { device = "phone" })
	local p = join(sim, 2, { device = "phone", money = 345 })
	local hud = hudOf(p)
	t.eq(p:GetAttribute("BaseIndex"), 0, "the second player waits in the queue")
	t.ok(sim:WaitFor(function()
		return hud.Status.Wallet.Visible
	end, WALLET.IntroWait + 1) == true, "the Wallet shows without a base")
	sim:Advance(1)
	t.eq(hud.Status.Wallet.Money.Label.Text, "$345")
	t.eq(hud.RightButtons.TankButton.Visible, false, "no «САДОК» without a base")
	sim:AssertNoErrors() -- (BaseService warns about its MaxBases debug knob)
end

tests["Wallet while loading: «$…» on glass after 3 s; the data comes — the glass goes, the money pops in"] = function(
	t
)
	local sim = boot(t)
	local p = join(sim, 1, { device = "phone", mode = "Loading" })
	local hud = hudOf(p)
	local wallet = hud.Status.Wallet
	sim:Advance(WALLET.LoadingAfter - 1.2)
	t.eq(wallet.Visible, false, "a short load shows nothing")
	sim:Advance(1.5)
	t.eq(wallet.Visible, true, `after {WALLET.LoadingAfter} s the Wallet is there…`)
	t.eq(wallet.Money.Label.Text, EconomyConfig.Format.Loading, "… with «$…»")
	t.eq(wallet.Money.Back.Visible, true, "… on its glass pill")
	t.eq(wallet.Rate.Visible, false, "… without a rate")
	t.eq(hud.RightButtons.TankButton.Visible, false, "«САДОК» waits for the data")
	p:SetAttribute("Money", 120)
	p:SetAttribute("Income", 3)
	p:SetAttribute("DataMode", "Ready")
	sim:Advance(1)
	t.eq(wallet.Money.Back.Visible, false, "the glass goes")
	t.eq(wallet.Money.Label.Text, "$120", "the money is in")
	t.eq(wallet.Rate.Visible, true, "and the rate")
	sim:Advance(1)
	t.eq(hud.RightButtons.TankButton.Visible, true, "«САДОК» follows")
	sim:AssertNoErrors({ warnings = true })
end

tests["pop-in order: the base banner lands in the badge → the Wallet (+0.3 s) → «САДОК» (+0.6 s)"] = function(
	t
)
	local sim = boot(t)
	local p = join(sim, 1, { device = "phone", money = 50 })
	local hud = hudOf(p)
	local landed, walletAt, tankAt = nil, nil, nil
	local wallet, tank = hud.Status.Wallet, hud.RightButtons.TankButton
	local function grown(gui: any): boolean
		local scale = gui:FindFirstChild("FxScale")
		return gui.Visible and scale ~= nil and scale.Scale > WALLET.PopFrom + 0.05
	end
	for _ = 1, 8 * 60 do
		sim:Advance(1 / 60)
		local now = sim:Time()
		landed = landed or (if hud:GetAttribute("IntroAt") ~= nil then now else nil)
		walletAt = walletAt or (if grown(wallet) then now else nil)
		tankAt = tankAt or (if grown(tank) then now else nil)
		if landed and walletAt and tankAt then
			break
		end
	end
	t.ok(landed and walletAt and tankAt, "all three happened")
	t.eq(hud.BaseBanner.Visible, false, "the banner has flown into the badge")
	t.near(walletAt - landed, WALLET.IntroGap, 0.1, "the Wallet pops in IntroGap after the banner")
	t.near(tankAt - landed, 2 * WALLET.IntroGap, 0.12, "«САДОК» another IntroGap later")
	sim:Advance(1)
	t.near(wallet.FxScale.Scale, 1, 1e-3, "settled")
	t.near(tank.FxScale.Scale, 1, 1e-3)
	sim:AssertNoErrors({ warnings = true })
end

tests["idle with income: plain-text ticks, a «+$N» float every 5 s only; no frame job, no connection churn"] = function(
	t
)
	local sim = boot(t)
	local p = join(sim, 1, { device = "phone", money = 1000, income = 19 })
	t.ok(chromeIn(sim, p))
	sim:Advance(6) -- (past the first float)
	local hud = hudOf(p)
	local label = hud.Status.Wallet.Money.Label
	local money = hud.Status.Wallet.Money
	local function scaled(gui: any): boolean
		local scale = gui:FindFirstChild("FxScale")
		return scale ~= nil and math.abs(scale.Scale - 1) > 1e-3
	end
	local UiFx = uiFx(sim, p)
	local TankRules = tankRules(sim, p)
	local idle = sim:CountConnections(p)
	local floats: { [any]: boolean } = {}
	local jobs, bumped = 0, false
	local value = 1000
	for second = 1, 12 do
		value += 19 -- what EconomyService credits every second
		p:SetAttribute("Money", value)
		for _ = 1, 10 do
			sim:Advance(0.1)
			jobs = math.max(jobs, UiFx.activeJobs())
			bumped = bumped or scaled(money) or scaled(label)
			for _, c in hud:GetChildren() do
				if c.Name == "FxFloat" then
					floats[c] = true
				end
			end
		end
		t.eq(label.Text, TankRules.FormatMoney(value), `second {second}: the tick writes the money`)
	end
	local count, text = 0, nil
	for float in floats do
		count += 1
		text = float.Text
	end
	t.eq(jobs, 0, "no frame job while idle (the floats are tweens)")
	t.eq(bumped, false, "the tick does not bump the Wallet")
	t.ok(count >= 2 and count <= 3, `a float every {WALLET.FloatEvery} s ({count} in 12 s)`)
	t.eq(text, "+$19", "the float is the income of a second")
	sim:Advance(2)
	t.eq(sim:CountConnections(p), idle, "no connection churn")
	sim:AssertNoErrors({ warnings = true })
end

tests["the tick never fights a count-up (K-11): a sale waits for its celebration, then counts up with the ticks"] = function(
	t
)
	local sim = boot(t)
	local p = join(sim, 1, { device = "desktop", money = 1000, income = 20 })
	t.ok(chromeIn(sim, p))
	local label = hudOf(p).Status.Wallet.Money.Label
	local Money = controller(sim, p, "MoneyController")
	local UiFx = uiFx(sim, p)
	t.eq(Money.Shown(), 1000)
	-- A sale: the server credits $500 (the attribute) — its "Sold" (Celebrate) arrives later.
	local value = 1500
	p:SetAttribute("Money", value)
	sim:Advance(0.2)
	t.eq(Money.Shown(), 1000, "the jump waits for its celebration")
	sim:Run(function()
		Money.Celebrate(500, nil, { Rate = "down" })
	end, p)
	local last = Money.Shown()
	local back, over = false, false
	for step = 1, 90 do
		if step % 15 == 0 then
			value += 20 -- the income ticks on during the count-up
			p:SetAttribute("Money", value)
		end
		sim:Advance(1 / 60)
		local now = Money.Shown()
		back = back or now < last
		over = over or now > value
		last = now
	end
	t.eq(back, false, "the number never steps back")
	t.eq(over, false, "… and never runs ahead of Money")
	sim:Advance(1)
	t.eq(Money.Shown(), value, "it ends on Money")
	t.eq(label.Text, "$1\u{00A0}620")
	t.eq(UiFx.activeJobs(), 0, "the count-up's frame job is over")
	-- Nobody celebrates a jump: it still counts up by itself, a moment later.
	p:SetAttribute("Money", value + 300)
	sim:Advance(0.2)
	t.eq(Money.Shown(), value, "an unclaimed jump waits too")
	sim:Advance(WALLET.SaleWait + WALLET.Count.Max + 0.3)
	t.eq(Money.Shown(), value + 300, "… then counts up to Money")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The catch → the tank
--------------------------------------------------------------------------------

tests["catch stored: «В САДОК!», «САДОК» frozen under CounterHold, the arrival in rarity colours"] = function(
	t
)
	local sim = boot(t)
	local p = join(sim, 1, { device = "phone", money = 100 })
	t.ok(chromeIn(sim, p))
	ready(sim, p)
	local hud = hudOf(p)
	local card = hud.Fishing.CatchCard
	local button = hud.RightButtons.TankButton
	local chip = button.Count.Label
	catchTank(sim, p, CATCHES.Rare, 1, { Result = "stored", Slot = 1, Uid = "f1", Count = 1, Slots = 6 })
	t.eq(hud:GetAttribute("CounterHold"), 0, "the catch holds «САДОК»")
	t.ok(openCard(sim, p))
	t.ok(sim:WaitFor(function()
		return card.TankStamp.Visible
	end, 3) == true, "the stamp lands after the price")
	t.eq(card.TankStamp.Label.Text, TankConfig.Texts.Stamp.stored)
	t.eq(chip.Text, "0/6", "«САДОК» frozen while the card is up")
	t.ok(closeCard(sim, p), "a tap closes the card")
	t.eq(chip.Text, "0/6", "… still frozen while the fish flies")
	t.ok(arrived(sim, p))
	sim:Advance(0.02)
	t.eq(chip.Text, "1/6", "the arrival rolls the chip")
	local ring = button:FindFirstChild("FxRing")
	t.ok(ring and colorNear(ring:FindFirstChildOfClass("UIStroke").Color, UIConfig.Rarity.Rare.Top), "a Rare ring")
	t.ok(button.FxScale.Scale > 1.05, "«САДОК» jumps (RarityBump)")
	sim:Advance(2)
	t.eq(button:FindFirstChild("FxRing"), nil, "the juice is over")
	t.eq(uiFx(sim, p).activeJobs(), 0)
	sim:AssertNoErrors({ warnings = true })
end

tests["catch sold: «ПРОДАНА», the card flies into Wallet.Money as 💵, the money counts up then; «Садок полон…» once"] = function(
	t
)
	local sim = boot(t)
	local p = join(sim, 1, { device = "desktop", money = 500, count = 6 })
	t.ok(chromeIn(sim, p))
	ready(sim, p)
	local hud = hudOf(p)
	local card = hud.Fishing.CatchCard
	local wallet = hud.Status.Wallet.Money
	local button = hud.RightButtons.TankButton
	for round = 1, 2 do
		local money = 500 + 11 * round
		catchTank(sim, p, CATCHES.Common, round, { Result = "sold", Count = 6, Slots = 6, Price = 11 }, money)
		t.ok(openCard(sim, p))
		t.ok(sim:WaitFor(function()
			return card.TankStamp.Visible
		end, 3) == true, `{round}: stamped`)
		t.eq(card.TankStamp.Label.Text, TankConfig.Texts.Stamp.sold)
		t.eq(wallet.Label.Text, `${money - 11}`, `{round}: the Wallet holds the sale while the card is up`)
		local closed = closeCard(sim, p)
		local ghost = hud.Fishing:FindFirstChild("FxCardOut")
		if closed then
			t.ok(ghost, `{round}: the card flies…`)
			local start = (center(ghost) - center(wallet)).Magnitude
			sim:Advance(0.2)
			t.ok((center(ghost) - center(wallet)).Magnitude < start - 20, `{round}: … into the Wallet`)
			local bill = false
			for _, c in hud:GetChildren() do
				if c.Name == "FxFly" and c.Text == "💵" then
					bill = true
				end
			end
			t.ok(bill, `{round}: a 💵 instead of the 🐟`)
		end
		local seen = watchToasts(sim, p, 3)
		t.eq(wallet.Label.Text, `${money}`, `{round}: the 💵 landed — the Wallet counted up`)
		t.eq(button.Count.Label.Text, "6/6", `{round}: «САДОК» untouched`)
		t.eq(button:FindFirstChild("FxRing"), nil, `{round}: no arrival on «САДОК»`)
		t.eq(
			seen[TankConfig.Texts.FullSold],
			if round == 1 then 1 else nil,
			`{round}: «{TankConfig.Texts.FullSold}» only the first time`
		)
		sim:Advance(2)
	end
	sim:AssertNoErrors({ warnings = true })
end

tests["catch replaced: «ЗАМЕНА!», coins from «САДОК» to the Wallet, then the toast names both fish"] = function(
	t
)
	local sim = boot(t)
	local p = join(sim, 1, { device = "desktop", money = 500, count = 6 })
	t.ok(chromeIn(sim, p))
	ready(sim, p)
	local hud = hudOf(p)
	local card = hud.Fishing.CatchCard
	local wallet = hud.Status.Wallet.Money
	local button = hud.RightButtons.TankButton
	catchTank(sim, p, CATCHES.Epic, 1, {
		Result = "replaced",
		Slot = 1,
		Uid = "f7",
		Count = 6,
		Slots = 6,
		Price = 24,
		Replaced = { Uid = "f1", Id = "Crucian", Rarity = "Common", Mutation = nil, Price = 24 },
	}, 524)
	t.ok(openCard(sim, p))
	t.ok(sim:WaitFor(function()
		return card.TankStamp.Visible
	end, 4) == true, "stamped")
	t.eq(card.TankStamp.Label.Text, TankConfig.Texts.Stamp.replaced)
	t.eq(wallet.Label.Text, "$500", "the Wallet holds the sale")
	closeCard(sim, p)
	t.ok(arrived(sim, p))
	-- The fish lands in «САДОК»; a beat later coins fly out of it into the Wallet.
	local coins, fromButton = 0, false
	local seen: { [string]: number } = {}
	local counted = false
	for _ = 1, 60 do
		sim:Advance(0.05)
		for _, c in hud:GetChildren() do
			if c.Name == "FxFly" and c.Text == "💵" then
				coins += 1
				if (center(c) - center(button)).Magnitude < button.AbsoluteSize.X then
					fromButton = true
				end
			end
		end
		counted = counted or wallet.Label.Text == "$524"
		for _, c in hud.Toasts:GetChildren() do
			if c.Name == "Toast" then
				seen[c.Label.Text] = (seen[c.Label.Text] or 0) + 1
			end
		end
	end
	t.ok(coins > 0, "💵 fly")
	t.ok(fromButton, "… out of «САДОК»")
	t.ok(counted, "the Wallet counts the price up")
	local Rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"), p)
	local TextUtil = sim:Require(sim:Find("ReplicatedStorage.Shared.TextUtil"), p)
	local expected = TextUtil.fill(TankConfig.Texts.Replaced, {
		new = Rules.GetFish("Swordfish").ShortName,
		old = Rules.GetFish("Crucian").ShortName,
		price = "$24",
	})
	t.ok(seen[expected] ~= nil, `the toast «{expected}»`)
	t.eq(button.Count.Label.Text, "6/6")
	sim:AssertNoErrors({ warnings = true })
end

tests["onboarding: the first fish ever lights «!» on «САДОК» and its toast once; the first open puts it out"] = function(
	t
)
	local sim = boot(t)
	local p = join(sim, 1, { device = "desktop", money = 0 })
	t.ok(chromeIn(sim, p))
	ready(sim, p)
	local hud = hudOf(p)
	local badge = hud.RightButtons.TankButton.Badge
	t.eq(badge.Visible, false, "no «!» before the first fish")
	catchTank(
		sim,
		p,
		CATCHES.Common,
		1,
		{ Result = "stored", Slot = 1, Uid = "f1", Count = 1, Slots = 6, First = true }
	)
	t.ok(openCard(sim, p))
	closeCard(sim, p)
	t.ok(arrived(sim, p))
	local seen = watchToasts(sim, p, 2)
	t.eq(badge.Visible, true, "«!» on «САДОК» after the first fish ever")
	t.eq(seen[TankConfig.Texts.FirstFish], 1, "the first-fish toast")
	-- The panel opens (from the button, the tank prompt or the market): «!» goes for the session.
	sim:Run(function()
		hud.TankPanel.Visible = true
	end, p)
	sim:Advance(0.5)
	t.eq(badge.Visible, false, "the first open puts «!» out")
	sim:Run(function()
		hud.TankPanel.Visible = false
	end, p)
	-- The next fish is not the first: no «!», no toast.
	sim:Advance(2)
	catchTank(sim, p, CATCHES.Rare, 2, { Result = "stored", Slot = 2, Uid = "f2", Count = 2, Slots = 6 })
	t.ok(openCard(sim, p))
	closeCard(sim, p)
	t.ok(arrived(sim, p))
	local again = watchToasts(sim, p, 2)
	t.eq(badge.Visible, false, "no «!» again")
	t.eq(again[TankConfig.Texts.FirstFish], nil, "the first-fish toast once")
	sim:AssertNoErrors({ warnings = true })
end

tests["«САДОК» taps: «нет» on a bite, nothing during the card; during the flight — the panel opens after the arrival on the new fish; else Toggle"] = function(
	t
)
	local sim = boot(t)
	local p = join(sim, 1, { device = "desktop", money = 0 })
	t.ok(chromeIn(sim, p))
	ready(sim, p)
	local hud = hudOf(p)
	local button = hud.RightButtons.TankButton
	local function calls(): number
		return hud:GetAttribute("PanelCalls") or 0
	end
	sim:Click(p, button)
	sim:Advance(0.05)
	t.eq(calls(), 1, "a tap at rest asks the panel")
	t.eq(hud:GetAttribute("PanelLast"), "Toggle", "… to toggle")
	-- A bite: «САДОК» shakes «no» (the fisher is never covered).
	sim:Advance(0.5)
	local rest = button.Rotation
	p:SetAttribute("FishingState", "Bite")
	sim:Advance(0.05)
	sim:Click(p, button)
	local swing = 0
	for _ = 1, 24 do
		sim:Advance(1 / 60)
		swing = math.max(swing, math.abs(button.Rotation - rest))
	end
	t.eq(calls(), 1, "a bite: nothing asked")
	t.ok(swing > 2, `… «САДОК» shakes «no» ({swing}°)`)
	p:SetAttribute("FishingState", "Idle")
	sim:Advance(0.5)
	catchTank(sim, p, CATCHES.Rare, 1, { Result = "stored", Slot = 1, Uid = "f9", Count = 1, Slots = 6 })
	t.ok(openCard(sim, p))
	sim:Click(p, button)
	sim:Advance(0.1)
	t.eq(calls(), 1, "the catch card is up: nothing asked")
	sim:Advance(0.5)
	t.ok(closeCard(sim, p), "the card closes")
	-- The fish flies: a tap now is remembered.
	t.ok(hud:GetAttribute("CounterHold") ~= nil, "the fish is in flight")
	sim:Click(p, button)
	sim:Advance(0.05)
	t.eq(calls(), 1, "nothing asked during the flight")
	t.ok(arrived(sim, p))
	sim:Advance(SPEC.OpenAfter + 0.1)
	t.eq(calls(), 2, "the panel opens after the arrival")
	t.eq(hud:GetAttribute("PanelLast"), "Open:f9", "… on the new fish")
	sim:AssertNoErrors({ warnings = true })
end

tests["memory mode: «💾 Studio: прогресс не сохраняется» once, after the base banner"] = function(
	t
)
	local sim = boot(t)
	local p = join(sim, 1, { device = "desktop", mode = "Memory" })
	local seen = watchToasts(sim, p, 7)
	t.eq(seen[DataConfig.Texts.MemoryToast], 1, "the memory toast, once")
	t.eq(hudOf(p).Status.Wallet.Visible, true, "the Wallet works in memory mode")
	p:SetAttribute("DataMode", "Ready")
	sim:Advance(0.2)
	p:SetAttribute("DataMode", "Memory")
	local again = watchToasts(sim, p, 2)
	t.eq(again[DataConfig.Texts.MemoryToast], nil, "not again")
	sim:AssertNoErrors({ warnings = true })
end

return tests
