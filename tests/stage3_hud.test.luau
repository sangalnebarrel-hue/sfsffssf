--[[
	Stage 3 HUD (design §6.1–6.3, §6.5–6.8, §7.5) in RbxSim against the built Place1.rbxl: the
	Wallet (MoneyController), the «САДОК» button (TankButtonController) and the catch → tank on the
	catch card (FishingController + CatchFx), on the real client.

	The stage 3 services and FishingService are switched off ("return {}"; the nameplate test runs
	them for real): the test plays the server — it writes the player attributes (DataMode, Money,
	Income, TankCount, TankSlots, SellRatePct) the way DataService / EconomyService / TankService
	do, and sends FishingState "Caught" with its TankResult after them (RemoteNames: crediting →
	attributes → remotes). The
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
	  • the catch: the stamp, «САДОК» and the Wallet's «+$/с» frozen under CounterHold, the
	    arrival in rarity colours, the rate rolling to the new income (RateRoll) after it;
	    "sold" — the card flies into Wallet.Money as 💵, the Wallet counts up only then, «Садок
	    полон…» once per session; "replaced" — coins from «САДОК» to the Wallet, then the toast
	    naming both fish; the onboarding «!» after the first fish ever, gone on the first open; a
	    tap during the flight opens the panel after the arrival, on the new fish; the first-fish
	    toast and the memory-mode toast once; the catch toasts wait while the own trophy (HeldFish)
	    is over the head (a tablet: NotifyController holds them back only on phones);
	  • the own trophy's nameplate (FishingFxController + FishingLayout.plateFit, C-R2-01): the pure
	    rule (right of the fish, else left, else smaller; lower under the Wallet row), and with the
	    REAL server (FishingService and the stage 3 services on, a real Legendary and Mythic Rainbow
	    catch, the preview's follow camera) on a tablet and a small phone: ≥ 16 px from «САДОК», on
	    screen, ≥ 16 px under the Wallet row, while the fisher celebrates.

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
local STUBBED = {
	"FishingService",
	"DataService",
	"EconomyService",
	"MarketService",
	"TankService",
	"DefenceService", -- stage 4 (no protection, no thefts: these tests play the state themselves)
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
	money: number?,
	income: number?
)
	p:SetAttribute("FishCaught", total)
	p:SetAttribute("TankCount", tank.Count)
	p:SetAttribute("TankSlots", tank.Slots)
	if money then
		p:SetAttribute("Money", money)
	end
	if income then
		p:SetAttribute("Income", income)
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

-- Distance between two rects (0 when they touch, negative never: overlapping rects read 0 — the
-- caller asks for ≥ 16).
local function rectGap(a: Rect, b: Rect): number
	local dx = math.max(b.x - (a.x + a.w), a.x - (b.x + b.w), 0)
	local dy = math.max(b.y - (a.y + a.h), a.y - (b.y + b.h), 0)
	return math.sqrt(dx * dx + dy * dy)
end

local function grownBy(r: Rect, gui: any): Rect
	local lip = gui:FindFirstChild("Lip")
	local stroke = lip and lip:FindFirstChildOfClass("UIStroke")
	local e = if stroke then stroke.Thickness else 0
	return { x = r.x - e, y = r.y - e, w = r.w + 2 * e, h = r.h + 2 * e }
end

-- V-02: the «ТВОЯ БАЗА» banner's giant name (HudController) keeps 16 px to the status badge,
-- «ДОМОЙ» and the action disc («ВЗЯТЬ» may pop in under it at any moment) on every screen, at rest
-- and through its slam (it grows from its baseline, no bigger than the room; the banner's own
-- pop-in scale counts). The name is measured as it is drawn: its box and its drop-shadow twin, the
-- outline at the sides and a quarter of its height of font line above and below (what the preview
-- checker measures). On the small 667 px phone the disc stands under the name's end: the banner is
-- lifted (stage 3 shipped it 13 px over the disc).
tests["base banner: its name keeps 16 px to the badge, «ДОМОЙ» and the action disc on every screen — at rest and through its slam (V-02)"] = function(
	t
)
	local sim = boot(t)
	local screens = {
		{ name = "phone", device = "phone" },
		{ name = "phone_notch", device = "phone", viewport = Vector2.new(750, 369) },
		{ name = "phone_small", device = "phone", viewport = Vector2.new(667, 375) },
		{ name = "tablet", device = "tablet" },
		{ name = "desktop", device = "desktop" },
	}
	for i, screen in screens do
		local p = sim:AddPlayer({ UserId = i, Name = `Banner{i}`, device = screen.device, viewport = screen.viewport })
		local banner: any = nil
		local shown = sim:WaitFor(function()
			local hud = p.PlayerGui:FindFirstChild("HUD")
			banner = hud and hud:FindFirstChild("BaseBanner")
			return banner ~= nil and banner.Visible
		end, 10, 1 / 60)
		t.ok(shown, `{screen.name}: the banner shows`)
		local hud = hudOf(p)
		local name, twin = banner.NameLabel, banner.NameLabelShadow
		local disc = hud.Fishing.ActionArea.ActionButton
		local neighbours = {
			badge = grownBy(rectOf(sim, p, hud.Status.BaseBadge), hud.Status.BaseBadge),
			home = grownBy(rectOf(sim, p, hud.RightButtons.HomeButton), hud.RightButtons.HomeButton),
			disc = grownBy(rectOf(sim, p, disc), disc),
		}
		local outline = name:FindFirstChild("Outline")
		local edge = if outline then outline.Thickness else 0
		local worst: { [string]: number } = {}
		local biggest = 1
		for _ = 1, 66 do -- (1.1 s: pop-in, slam, rest; the banner flies into the badge at 2 s)
			local b = rectOf(sim, p, banner)
			local n = rectOf(sim, p, name)
			local s = rectOf(sim, p, twin)
			local sb = if banner:FindFirstChild("FxScale") then banner.FxScale.Scale else 1
			local sn = if name:FindFirstChild("FxScale") then name.FxScale.Scale else 1
			biggest = math.max(biggest, sn)
			local bc = Vector2.new(b.x + b.w / 2, b.y + b.h / 2)
			local anchor = Vector2.new(n.x + n.w / 2, n.y + n.h) -- (the name's baseline middle)
			local at = bc + (anchor - bc) * sb
			local k = sb * sn
			local ink = n.h * 0.25
			local x0, x1 = math.min(n.x, s.x) - edge, math.max(n.x + n.w, s.x + s.w) + edge
			local y0, y1 = n.y - ink, math.max(n.y + n.h, s.y + s.h) + ink
			local drawn: Rect = {
				x = at.X - (anchor.X - x0) * k,
				y = at.Y - (anchor.Y - y0) * k,
				w = (x1 - x0) * k,
				h = (y1 - y0) * k,
			}
			for what, rect in neighbours do
				worst[what] = math.min(worst[what] or math.huge, rectGap(drawn, rect))
			end
			sim:Advance(1 / 60)
		end
		t.ok(biggest > 1.15, `{screen.name}: the name still slams in ({biggest})`)
		for what, gap in worst do
			t.ok(gap >= 16, `{screen.name}: the name keeps 16 px to the {what} ({gap})`)
		end
		if screen.name == "phone_small" then
			local rest = INSET + 0.46 * (screen.viewport.Y - INSET)
			local b = rectOf(sim, p, banner)
			t.ok(
				b.y + b.h / 2 < rest - 4,
				`{screen.name}: the banner is lifted over «ВЗЯТЬ» ({b.y + b.h / 2} < {rest})`
			)
		end
	end
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

tests["catch stored: «В САДОК!», «САДОК» and the Wallet's «+$/с» frozen under CounterHold, the arrival in rarity colours, the rate rolls up"] = function(
	t
)
	local sim = boot(t)
	local p = join(sim, 1, { device = "phone", money = 100, income = 2.9 })
	t.ok(chromeIn(sim, p))
	ready(sim, p)
	local hud = hudOf(p)
	local card = hud.Fishing.CatchCard
	local button = hud.RightButtons.TankButton
	local chip = button.Count.Label
	local rate = hud.Status.Wallet.Rate
	t.eq(rate.Text, "+$2.9/с", "the rate before the catch")
	-- EconomyService credits the new fish's income with the catch (+$5.2/с).
	catchTank(sim, p, CATCHES.Rare, 1, { Result = "stored", Slot = 1, Uid = "f1", Count = 1, Slots = 6 }, nil, 8.1)
	t.eq(hud:GetAttribute("CounterHold"), 0, "the catch holds «САДОК»")
	t.ok(openCard(sim, p))
	t.ok(sim:WaitFor(function()
		return card.TankStamp.Visible
	end, 3) == true, "the stamp lands after the price")
	t.eq(card.TankStamp.Label.Text, TankConfig.Texts.Stamp.stored)
	t.eq(chip.Text, "0/6", "«САДОК» frozen while the card is up")
	t.eq(rate.Text, "+$2.9/с", "… and the rate too")
	t.ok(closeCard(sim, p), "a tap closes the card")
	t.eq(chip.Text, "0/6", "… still frozen while the fish flies")
	t.eq(rate.Text, "+$2.9/с", "… the rate too")
	t.ok(arrived(sim, p))
	sim:Advance(0.02)
	t.eq(chip.Text, "1/6", "the arrival rolls the chip")
	t.ok(rate.Text ~= "+$2.9/с" and rate.Text ~= "+$8.1/с", `… and the rate starts rolling ({rate.Text})`)
	local ring = button:FindFirstChild("FxRing")
	t.ok(ring and colorNear(ring:FindFirstChildOfClass("UIStroke").Color, UIConfig.Rarity.Rare.Top), "a Rare ring")
	t.ok(button.FxScale.Scale > 1.05, "«САДОК» jumps (RarityBump)")
	sim:Advance(WALLET.RateRoll + 0.1)
	t.eq(rate.Text, "+$8.1/с", "the rate has rolled up to the new income")
	sim:Advance(2)
	t.eq(button:FindFirstChild("FxRing"), nil, "the juice is over")
	t.eq(uiFx(sim, p).activeJobs(), 0)
	sim:AssertNoErrors({ warnings = true })
end

tests["catch sold: «САДОК ПОЛОН» over «ПРОДАНА», the card flies into Wallet.Money as 💵, the money counts up then; an ordinary fish — «Садок полон…» once"] = function(
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
	-- (an ordinary fish: a known Common without a mutation — the server says it is not new)
	local ordinary = table.clone(CATCHES.Common)
	ordinary.New = false
	for round = 1, 2 do
		local money = 500 + 11 * round
		catchTank(sim, p, ordinary, round, { Result = "sold", Count = 6, Slots = 6, Price = 11 }, money)
		t.ok(openCard(sim, p))
		t.ok(sim:WaitFor(function()
			return card.TankStamp.Visible
		end, 3) == true, `{round}: stamped`)
		t.eq(card.TankStamp.Label.Text, TankConfig.Texts.Stamp.sold)
		t.ok(card.TankStamp.Sub.Visible, `{round}: the cause over it`)
		t.eq(card.TankStamp.Sub.Text, TankConfig.Texts.Stamp.full, `{round}: «САДОК ПОЛОН»`)
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

tests["catch sold, notable (UX-01): the card names the full tank and stays SOLD_HOLD after its stamp, «6/6» pulses while it is up, and a NEW / mutated / Epic+ fish is explained every time"] = function(
	t
)
	local sim = boot(t)
	local p = join(sim, 1, { device = "phone", money = 500, count = 6 })
	t.ok(chromeIn(sim, p))
	ready(sim, p)
	local hud = hudOf(p)
	local card = hud.Fishing.CatchCard
	local button = hud.RightButtons.TankButton
	local chipScale = function(): number
		local scale = button.Count:FindFirstChild("FxScale")
		return if scale then scale.Scale else 1
	end
	local CatchFx = sim:Require(sim:Find("Controllers.CatchFx", p:FindFirstChildOfClass("PlayerScripts")), p)
	local gold = { Id = "Perch", Rarity = "Common", Mutation = "Gold", Kg = 1.1, Value = 35, Income = 3.2, New = false }
	local epic = table.clone(CATCHES.Epic)
	epic.New = false
	local fresh = table.clone(CATCHES.Rare)
	fresh.New = true
	local cases = {
		{ fish = gold, price = 35, name = "Окунь", what = "a Gold mutation" },
		{ fish = epic, price = 182, name = "Меч-рыба", what = "an Epic" },
		{ fish = fresh, price = 58, name = "Фугу", what = "a NEW species" },
		{ fish = gold, price = 35, name = "Окунь", what = "the same Gold Perch again" },
	}
	local money = 500
	for round, case in cases do
		money += case.price
		catchTank(sim, p, case.fish, round, { Result = "sold", Count = 6, Slots = 6, Price = case.price }, money)
		t.ok(openCard(sim, p), `{case.what}: the card`)
		-- the full chip pulses while the sold card is up
		local scales = {}
		local stampedAt = nil
		for _ = 1, 120 do
			sim:Advance(1 / 30)
			table.insert(scales, chipScale())
			if card.TankStamp.Visible and not stampedAt then
				stampedAt = sim:Time()
			end
			if stampedAt then
				break
			end
		end
		t.ok(stampedAt, `{case.what}: stamped`)
		t.eq(card.TankStamp.Sub.Text, TankConfig.Texts.Stamp.full)
		local lo, hi = math.huge, -math.huge
		for _ = 1, 24 do
			sim:Advance(1 / 30)
			lo, hi = math.min(lo, chipScale()), math.max(hi, chipScale())
		end
		t.ok(hi - lo > 0.05, `{case.what}: «6/6» pulses while the card is up ({lo}..{hi})`)
		t.eq(button.Count.Label.Text, "6/6")
		-- no tap: the card closes by itself, but not before SOLD_HOLD after the stamp
		local closed = sim:WaitFor(function()
			return not card.Visible
		end, 8, 1 / 30)
		t.ok(closed, `{case.what}: closes by itself`)
		local held = sim:Time() - (stampedAt :: number)
		t.ok(held >= CatchFx.SOLD_HOLD - 0.15, `{case.what}: the stamp stayed {held} s (≥ {CatchFx.SOLD_HOLD})`)
		t.ok(arrived(sim, p))
		sim:Advance(0.1)
		t.near(chipScale(), 1, 1e-3, `{case.what}: the pulse is over once the 💵 landed`)
		local seen = watchToasts(sim, p, 4)
		local want = string.gsub(
			string.gsub(TankConfig.Texts.SoldNotable, "{name}", case.name),
			"{price}",
			(string.gsub(`${case.price}`, "%%", "%%%%"))
		)
		t.eq(seen[want], 1, `{case.what}: «{want}» (every time for a notable fish)`)
		t.eq(seen[TankConfig.Texts.FullSold], nil, `{case.what}: not the generic «Садок полон…»`)
		sim:Advance(1)
	end
	-- an ordinary one after that: nothing more to say
	local ordinary = table.clone(CATCHES.Common)
	ordinary.New = false
	catchTank(sim, p, ordinary, 9, { Result = "sold", Count = 6, Slots = 6, Price = 11 }, money + 11)
	t.ok(openCard(sim, p))
	closeCard(sim, p)
	t.ok(arrived(sim, p))
	local seen = watchToasts(sim, p, 4)
	t.eq(next(seen), nil, "an ordinary sale after an explained one: no toast")
	t.eq(uiFx(sim, p).activeJobs(), 0)
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

tests["catch toasts wait for the held trophy (a tablet: the column is over the head), then show; nothing left connected"] = function(
	t
)
	local sim = boot(t)
	local p = join(sim, 1, { device = "tablet", money = 500, count = 0 })
	t.ok(chromeIn(sim, p))
	ready(sim, p)
	local hud = hudOf(p)
	local idle = sim:CountConnections(p)
	local Rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"), p)
	local TextUtil = sim:Require(sim:Find("ReplicatedStorage.Shared.TextUtil"), p)
	local replacedText = TextUtil.fill(TankConfig.Texts.Replaced, {
		new = Rules.GetFish("Swordfish").ShortName,
		old = Rules.GetFish("Crucian").ShortName,
		price = "$24",
	})
	local rounds = {
		{
			what = "the first fish ever",
			fish = CATCHES.Common,
			tank = { Result = "stored", Slot = 1, Uid = "f1", Count = 1, Slots = 6, First = true },
			text = TankConfig.Texts.FirstFish,
		},
		{
			what = "a replacement",
			fish = CATCHES.Epic,
			tank = {
				Result = "replaced",
				Slot = 1,
				Uid = "f7",
				Count = 6,
				Slots = 6,
				Price = 24,
				Replaced = { Uid = "f1", Id = "Crucian", Rarity = "Common", Mutation = nil, Price = 24 },
			},
			money = 524,
			text = replacedText,
		},
	}
	for i, round in rounds do
		catchTank(sim, p, round.fish, i, round.tank, round.money)
		t.ok(openCard(sim, p), `{round.what}: the card`)
		-- The trophy is over the head (FishingService's HeldFish: it stays ~3 s after the card).
		local held = sim:Create("Model", { Name = "HeldFish" }, p.Character)
		closeCard(sim, p)
		t.ok(arrived(sim, p), `{round.what}: the fish flew in`)
		local early = watchToasts(sim, p, SPEC.ReplacedToastAfter + 1.5)
		t.eq(next(early), nil, `{round.what}: no toast while the trophy is over the head`)
		if round.money then
			t.eq(hud.Status.Wallet.Money.Label.Text, "$524", `{round.what}: the coins are counted meanwhile`)
		end
		held:Destroy()
		-- (and Wallet.AfterTrophy more: the pier word punches first, UX-03)
		local soon = watchToasts(sim, p, UIConfig.Wallet.AfterTrophy - 0.15)
		t.eq(next(soon), nil, `{round.what}: the trophy just left — the pier word's beat first`)
		local seen = watchToasts(sim, p, 1)
		t.eq(seen[round.text], 1, `{round.what}: the trophy is gone — «{round.text}»`)
		sim:Advance(UIConfig.ToastDuration + 1)
	end
	sim:Advance(2)
	t.eq(sim:CountConnections(p), idle, "the waits are disconnected")
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

--------------------------------------------------------------------------------
-- The own trophy's nameplate and «САДОК» (C-R2-01)
--------------------------------------------------------------------------------

-- FishingLayout is pure rectangle maths: loaded straight from src/ (Vector2 from Lune).
local function loadLayout(): any
	local path = "src/StarterPlayer/StarterPlayerScripts/Controllers/FishingLayout.luau"
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Vector2 = roblox.Vector2, Vector3 = roblox.Vector3 },
		injectGlobals = true,
	})
	return chunk()
end

tests["FishingLayout.plateFit: right of the fish when it fits, else left, else smaller on the roomier side; under the Wallet row a little lower"] = function(
	t
)
	local L = loadLayout()
	local screen = L.rect(0, 0, 1024, 768)
	local column = { L.rect(902, 284, 1021, 403), L.rect(902, 409, 1021, 528) } -- «САДОК», «ДОМОЙ»
	local still = Vector2.new(0, 0)
	-- Room on the right: 902 − 16 − (500 + 50) = 336 px for a 300 px plate.
	local side, scale, drop = L.plateFit(Vector2.new(500, 340), 50, 300, 90, still, column, {}, screen, 0.7)
	t.eq(side, 1, "right of the fish")
	t.eq(scale, 1, "… full size")
	t.eq(drop, 0, "… where it is")
	-- Too little on the right (886 − 650 = 236), plenty on the left (550 − 16 = 534).
	side, scale = L.plateFit(Vector2.new(600, 340), 50, 300, 90, still, column, {}, screen, 0.7)
	t.eq(side, -1, "the column is in the way — left of the fish")
	t.eq(scale, 1, "… full size")
	-- Neither side: the roomier one, smaller (right 886 − 618 = 268 → 0.89; left 406 − 212 − 16 = 178).
	side, scale = L.plateFit(Vector2.new(406, 340), 212, 300, 90, still, column, {}, screen, 0.7)
	t.eq(side, 1, "no room either side — the roomier right")
	t.near(scale, 268 / 300, 0.001, "… shrunk to the gap")
	-- Its own sway counts: 12 px each way leaves 256.
	side, scale = L.plateFit(Vector2.new(406, 340), 212, 300, 90, Vector2.new(12, 20), column, {}, screen, 0.7)
	t.near(scale, 256 / 300, 0.001, "the sway is kept clear too")
	-- Never below minScale.
	side, scale = L.plateFit(Vector2.new(406, 340), 212, 600, 90, still, column, {}, screen, 0.7)
	t.eq(scale, 0.7, "not smaller than minScale")
	-- The column far below its band does not count.
	side, scale = L.plateFit(Vector2.new(600, 100), 50, 300, 90, still, column, {}, screen, 0.7)
	t.eq(side, 1, "a button outside its band is no obstacle")
	t.eq(scale, 1, "… full size")
	-- The Wallet row's content above it: its top goes ≥ 16 px under it (≤ half its height).
	local wallet = { L.rect(250, 97, 420, 127) }
	side, scale, drop = L.plateFit(Vector2.new(300, 165), 70, 200, 60, still, {}, wallet, screen, 0.7)
	t.eq(drop, 127 + 16 - (165 - 30), "under the Wallet row: lower by the missing gap")
	side, scale, drop = L.plateFit(Vector2.new(300, 175), 70, 200, 60, Vector2.new(0, 10), {}, wallet, screen, 0.7)
	t.eq(drop, 127 + 16 - (175 - 30 - 10), "… and at the top of its sway")
	side, scale, drop = L.plateFit(Vector2.new(300, 140), 70, 200, 60, still, {}, wallet, screen, 0.7)
	t.eq(drop, 30, "… but by half its height at most")
	side, scale, drop = L.plateFit(Vector2.new(600, 165), 70, 200, 60, still, {}, wallet, screen, 0.7)
	t.eq(drop, 0, "a Wallet row off to the side does not move it")
end

-- Everything real (FishingService and the stage 3 services) but the tank panel.
local function bootReal(t: any): any
	local sim = t.sim({ place = PLACE })
	sim:Find("StarterPlayer.StarterPlayerScripts.Controllers.TankPanelController").Source = FAKE_PANEL
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

local function rodIn(container: any): any
	for _, item in if container then container:GetChildren() else {} do
		if item:IsA("Tool") and item:GetAttribute("RodId") ~= nil then
			return item
		end
	end
	return nil
end

-- A real catch of `fish` ({ Id, Mutation? }, the biggest of its kind) with the real server, the
-- player posed on the own FishingSpot with the preview's follow camera (12.5 studs back, 18°
-- down, the Humanoid.CameraOffset FishingFxController sets): cast, hook, win the minigame by
-- tapping when the needle is in the zone, then the card opens, closes, the fish flies into
-- «САДОК» and the own trophy's nameplate pops out beside the fish. Returns the sim, the player
-- and the nameplate (nil if it never showed).
local function trophyPlate(t: any, screen: { [string]: any }, fish: { [string]: any }): (any, any, any)
	local sim = bootReal(t)
	local device = screen.name
	local p = sim:AddPlayer({ UserId = 1, Name = "Plate1", device = screen.device, viewport = screen.viewport })
	local loaded = sim:WaitFor(function()
		local gui = p:FindFirstChild("PlayerGui")
		local hud = gui and gui:FindFirstChild("HUD")
		return hud ~= nil
			and hud.RightButtons.TankButton.Visible
			and hud.Status.Wallet.Visible
			and rodIn(p:FindFirstChildOfClass("Backpack")) ~= nil
	end, 15)
	t.ok(loaded, `{device}: a base, the data, «САДОК», the Wallet and the rod`)
	local Rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"))
	local def = Rules.GetFish(fish.Id)
	local value, income = Rules.Price(fish.Id, def.MaxKg, fish.Mutation)
	local data =
		{ Id = fish.Id, Rarity = def.Rarity, Mutation = fish.Mutation, Kg = def.MaxKg, Value = value, Income = income }
	sim:Require(sim:Find("ServerScriptService.Services.FishingService")).RollFishForTest = function()
		return table.clone(data)
	end
	-- On the FishingSpot facing the lagoon (as the preview poses him), the rod in hand.
	local base = sim.workspace.Bases:FindFirstChild(`Base_{p:GetAttribute("BaseIndex")}`)
	local spot = base.FishingSpot
	local look = base:GetPivot().LookVector
	local fwd = Vector3.new(look.X, 0, look.Z).Unit
	local origin = spot.Position + Vector3.new(0, spot.Size.Y / 2, 0)
	local character = p.Character
	local root = character.HumanoidRootPart
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local at = origin + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	sim:Teleport(p, roblox.CFrame.lookAt(at, at + fwd))
	sim:EquipTool(p, rodIn(p:FindFirstChildOfClass("Backpack")))
	sim:Advance(0.4)
	local function aim()
		sim:Run(function() -- (CameraOffset is client-local: FishingFxController tweens it there)
			local offset = root.CFrame:VectorToWorldSpace(humanoid.CameraOffset)
			local focus = origin + Vector3.new(0, 4.6, 0) + offset
			local pitch = math.rad(18)
			local eye = focus + Vector3.new(0, 12.5 * math.sin(pitch), 0) - fwd * (12.5 * math.cos(pitch))
			sim.workspace.CurrentCamera.CFrame = roblox.CFrame.lookAt(eye, focus)
		end, p)
	end
	aim()
	-- Cast, hook on the bite, tap whenever the needle is well inside the zone (what the server
	-- judges: FishingRules.Needle at the tap's moment).
	local function events(): { any }
		return sim:ClientEventsFor(p, "FishingState")
	end
	local function after(count: number, timeout: number): any
		return sim:WaitFor(function()
			return events()[count + 1]
		end, timeout, 1 / 60)
	end
	sim:FireServer(p, "FishingCast")
	local count = #events()
	local bite = after(count, 12)
	t.ok(bite and bite.args[1] == "Bite", `{device} {fish.Id}: the bite`)
	sim:Advance(0.2)
	count = #events()
	sim:FireServer(p, "FishingHook")
	local hooked = after(count, 1)
	t.ok(hooked and hooked.args[1] == "Minigame", `{device} {fish.Id}: hooked`)
	if not (hooked and hooked.args[1] == "Minigame") then
		return sim, p, nil
	end
	local mg, start = hooked.args[2], hooked.time
	local center, from = mg.ZoneCenter, FishingConfig.TapInterval + 0.02
	local outcome = nil
	for _ = 1, mg.HitsNeeded do
		local moment = from
		while math.abs(Rules.Needle(mg.U0, mg.Speed, moment) - center) > mg.ZoneWidth * 0.3 and moment < from + 8 do
			moment += 0.005
		end
		sim:WaitFor(function()
			return sim:Time() >= start + moment - 1e-9
		end, 10, 1 / 60)
		count = #events()
		sim:FireServer(p, "FishingTap", moment)
		local reply = after(count, 0.3)
		outcome = reply and reply.args[1]
		if outcome ~= "Zone" then
			break
		end
		center, from = reply.args[2].ZoneCenter, moment + FishingConfig.TapInterval + 0.02
	end
	t.eq(outcome, "Caught", `{device} {fish.Id}: caught`)
	t.ok(openCard(sim, p), `{device} {fish.Id}: the card`)
	sim:Advance(0.8) -- (the trophy camera has moved up: FX.TrophyCamera)
	aim()
	t.ok(closeCard(sim, p), `{device} {fish.Id}: the card closes`)
	t.ok(arrived(sim, p), `{device} {fish.Id}: the fish flew into «САДОК»`)
	local fx = controller(sim, p, "FishingFxController")
	local plate = sim:WaitFor(function()
		for _, instance in fx.GetEffects(p) do
			if instance.Name == "Nameplate" and instance:IsA("BillboardGui") and instance.Enabled then
				return instance
			end
		end
		return nil
	end, 2, 1 / 60)
	sim:Advance(0.5) -- (its pop has settled)
	return sim, p, plate
end

-- Where a BillboardGui is on the client's screen (viewport px), as Roblox (and the preview) draw
-- it: the adornee plus StudsOffsetWorldSpace and the camera-relative StudsOffset, sized "studs ×
-- px per stud at its depth + px", moved by SizeOffset.
local function billboardRect(sim: any, p: any, gui: any): Rect
	return sim:Run(function()
		local camera = sim.workspace.CurrentCamera
		local cf = camera.CFrame
		local so = gui.StudsOffset
		local pos = gui.Adornee.Position + gui.StudsOffsetWorldSpace + cf.RightVector * so.X + cf.UpVector * so.Y
		local point = camera:WorldToScreenPoint(pos)
		local perStud = camera.ViewportSize.Y / (2 * point.Z * math.tan(math.rad(camera.FieldOfView) / 2))
		local w = gui.Size.X.Scale * perStud + gui.Size.X.Offset
		local h = gui.Size.Y.Scale * perStud + gui.Size.Y.Offset
		local x = point.X + gui.SizeOffset.X * w
		local y = point.Y - gui.SizeOffset.Y * h
		return { x = x - w / 2, y = y - h / 2, w = w, h = h }
	end, p)
end

tests["own trophy nameplate: an own Legendary and Mythic Rainbow keep ≥ 16 px from «САДОК» on a tablet and a small phone (right of the fish, left, or smaller), under the Wallet row"] = function(
	t
)
	local screens = {
		{ name = "tablet", device = "tablet" },
		{ name = "phone_small", device = "phone", viewport = Vector2.new(667, 375) },
	}
	for _, screen in screens do
		for _, fish in { { Id = "SharkPup" }, { Id = "DragonFish", Mutation = "Rainbow" } } do
			local what = `{screen.name} {fish.Id}`
			local sim, p, plate = trophyPlate(t, screen, fish)
			t.ok(plate ~= nil, `{what}: the own nameplate pops out after the card`)
			if plate then
				local hud = hudOf(p)
				local button = hud.RightButtons.TankButton
				local stroke = button.Lip:FindFirstChildOfClass("UIStroke").Thickness
				local tank = rectOf(sim, p, button)
				local vp = sim.players.state[sim:Unwrap(p)].viewport
				t.ok(
					plate.Size.X.Offset >= math.floor(150 * 0.7),
					`{what}: not smaller than 0.7 ({plate.Size.X.Offset} px of 150)`
				)
				-- The Wallet row's content (the 💵 number and «+$/с»).
				local wallet = hud.Status.Wallet
				local left, right, bottom = math.huge, -math.huge, -math.huge
				for _, part in { wallet.Money, wallet.Rate } do
					if part.Visible then
						local r = rectOf(sim, p, part)
						left, right, bottom =
							math.min(left, r.x), math.max(right, r.x + r.w), math.max(bottom, r.y + r.h)
					end
				end
				-- For 2 s while the fisher celebrates (crouch, jump, the fish shaken): the worst gaps.
				local worstTank, worstWallet, offScreen = math.huge, math.huge, nil
				for _ = 1, 20 do
					local box = billboardRect(sim, p, plate)
					if plate.StudsOffset.X > 0 then
						worstTank = math.min(worstTank, tank.x - stroke - (box.x + box.w))
					end
					if left < box.x + box.w + 16 and right > box.x - 16 then
						worstWallet = math.min(worstWallet, box.y - bottom)
					end
					if box.x < 15.5 or box.x + box.w > vp.X - 15.5 then
						offScreen = box
					end
					sim:Advance(0.1)
				end
				t.ok(
					worstTank >= 15.5,
					`{what}: ≥ 16 px from «САДОК»'s outline (worst {math.floor(worstTank)} px; «САДОК» {fmt(
						tank
					)})`
				)
				t.ok(worstWallet >= 15.5, `{what}: ≥ 16 px under the Wallet row (worst {math.floor(worstWallet)} px)`)
				t.ok(offScreen == nil, `{what}: ≥ 16 px inside the screen {if offScreen then fmt(offScreen) else ""}`)
			end
			sim:AssertNoErrors({ warnings = true })
		end
	end
end

return tests
