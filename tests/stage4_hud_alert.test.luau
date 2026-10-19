--[[
	Stage 4 — the victim's alert and the defence HUD (AlertController + AlertLayout on
	HUD.TheftAlert, DefenceController on «ЗАЩИТА» and the ShieldChip, HudController's «ДОМОЙ!»,
	carry lock and Status hiding; docs/stage4_design.md §6.2, §6.3, §6.5, §6.9, §7.6 «Alert»).

	Two kinds of tests:
	  • the REAL server (tests/stage4_server.luau: every service on, a victim with a client, a
	    headless thief): the victim fishes for real (cast, bite, hook → the minigame) when the
	    thief's hold — or carry — starts on his tank; ONE tap on ЩИТ (the phone pill in the hold, the
	    column's «ЩИТ!» on a tablet in the carry) fires ShieldActivate, the server saves the fish
	    (StealEvent "Saved" shield, the thief stopped) and the minigame keeps its input (no
	    FishingState change, the action button still sends FishingTap);
	  • the client against a stubbed server (Stage 3 pattern: the services "return {}", the test
	    fires StealEvent / DefenceEvent and writes the attributes DefenceService / StealService
	    replicate):
	      – the plate in the toast column on a tablet and a desktop, the Compact pill on phones
	        (phone, phone_small), never on the own fisher (AlertController.Stats().fisher), ≥ 16 px
	        from the status stack and the right column; ЩИТ ≥ 56 px tall and ≥ 35 % of the plate /
	        pill, ДОМОЙ ≥ 44 px;
	      – recharging: Slate «⏳ 1:12» (a tap wiggles, fires nothing), the carry line without «жми
	        ЩИТ!»; stealing himself: no buttons, «Пока крадёшь сам, щит не включить» (DC-04);
	      – ЩИТ: «⏳» until the server answers, one ShieldActivate for several taps; the column
	        «ЩИТ!» in the alert (Berry, rings, «!»); a shield save shows ONE toast «Щит спас рыбу!
	        🛡️ 1:00» whichever of Shield / Saved comes first (no «Щит включён» beside it);
	      – loud alerts ping three times and shake; coalesced Quiet ones do neither;
	      – an alert with a catch card up (CounterHold): FishingController.HurryCard (a spy) is
	        called at once, the plate waits and shows once the hold is gone; a catch that lands
	        while the alert is up hurries the card again and hides the plate until it is gone;
	      – a sheet open when the alert starts: «САДОК» closes at once, «ЗАЩИТА» stays and its
	        shield card is the «ЩИТ!» (one tap); a sheet opened during the alert hides the plate —
	        it is never drawn over a sheet;
	      – a second alert right after the first one ended shows (the first one's hide timer does
	        not hide it);
	      – the phone pill (AlertLayout): the topmost free spot, kept while it stays free, never by
	        the Roblox buttons (no spot — no pill); its label «ВОР! ФУГУ» → «ВОР!» when tight, the
	        reason while the victim steals himself;
	      – the layers: the edge pulse ≤ 0.35 opacity (in its clipping layer FxAlertEdge; asleep
	        while the fishing has its own edge glow, the rings resting with it on a phone),
	        «ДОМОЙ!» with its rings, «ДОМОЙ» locked 🔒 in the own carry (taps ask the server
	        nothing), HUD.Status hidden while HUD.Stealing is set; all gone at the end,
	        connections back to the baseline;
	      – results: Lost → «Украдено: Фугу (Ника)», «Садок отдыхает …» and one tip; Saved shield
	        → the shield toast; a Quiet save → nothing; Intruder → «👀 Ника у тебя во дворе!» and
	        «ЗАЩИТА» bobs;
	      – the ShieldChip on phone / phone_small / tablet / desktop: on screen right of the badge,
	        the time, the pulse in the last WarnLast s, gone at 0; the EndingWarn toast for the
	        newbie protection;
	      – the «ЗАЩИТА» «!» once, when the first defence becomes affordable.
	(The trophy chip left of the three-button column on phones: tests/hud_style.)

	Run: lune run tools/run_tests.luau stage4_hud_alert
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local S = require("./stage4_server")

local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3

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

local StealConfig = loadConfig("StealConfig")
local DefenceConfig = loadConfig("DefenceConfig")
local FishingConfig = loadConfig("FishingConfig")
local UIConfig = loadConfig("UIConfig")
local ALERT = StealConfig.Texts.Alert
local RESULT = StealConfig.Texts.Result
local DTEXTS = DefenceConfig.Texts
local THEFT = UIConfig.Theft

local SCREENS = {
	{ name = "phone", device = "phone", phone = true },
	{ name = "phone_small", device = "phone", viewport = Vector2.new(667, 375), phone = true },
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

local function gap(a: Rect, b: Rect): number
	local dx = math.max(b.x0 - a.x1, a.x0 - b.x1, 0)
	local dy = math.max(b.y0 - a.y1, a.y0 - b.y1, 0)
	return math.sqrt(dx * dx + dy * dy)
end

--------------------------------------------------------------------------------
-- Shared helpers (both kinds)
--------------------------------------------------------------------------------

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

local function alertStats(sim: any, p: any): { [string]: any }
	local alert = module(sim, p, "AlertController")
	return call(sim, p, function()
		return alert.Stats()
	end)
end

-- A time for an attribute (TankRules.AttrTime: RbxSim keeps whole-number attributes as float32).
local function T(t: number): number
	return if t % 1 == 0 then t + 1 / 1024 else t
end

-- The server's clock (what StealService / DefenceService write attributes with).
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

-- Every toast text seen during `seconds` (they come and go).
local function watchToasts(sim: any, p: any, seconds: number): { string }
	local seen, list = {}, {}
	local t0 = sim:Time()
	while sim:Time() - t0 < seconds do
		for _, s in toastTexts(p) do
			if not seen[s] then
				seen[s] = true
				table.insert(list, s)
			end
		end
		sim:Advance(0.1)
	end
	return list
end

local function anyHas(list: { string }, text: string): boolean
	for _, s in list do
		if string.find(s, text, 1, true) then
			return true
		end
	end
	return false
end

-- The ЩИТ button the victim sees now: the pill's on a phone, the plate's elsewhere.
local function shieldButton(p: any): any
	local root = hudOf(p).TheftAlert
	if root.Compact.Visible then
		return root.Compact.Shield
	end
	return root.Buttons.Shield
end

--------------------------------------------------------------------------------
-- The REAL server: one tap on ЩИТ during the minigame
--------------------------------------------------------------------------------

local VICTIM_TANK = {
	{ Id = "Perch" },
	{ Id = "Perch" },
	{ Id = "Puffer", Age = 200 },
	{ Id = "Crucian" },
}

local function rodIn(container: any): any
	for _, item in if container then container:GetChildren() else {} do
		if item:IsA("Tool") and item:GetAttribute("RodId") ~= nil then
			return item
		end
	end
	return nil
end

-- The victim (a client on `device`) and a headless thief, both loaded, nobody protected.
local function realPair(t: any, device: string): (any, any, any)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = VICTIM_TANK, client = true, device = device, name = "Хозяин" })
	local thief = S.player(t, sim, 102, { tank = { { Id = "Crucian" } }, name = "Ника" })
	local ready = sim:WaitFor(function()
		local gui = victim:FindFirstChild("PlayerGui")
		local hud = gui and gui:FindFirstChild("HUD")
		return hud ~= nil
			and hud.RightButtons.DefenceButton.Visible
			and rodIn(victim:FindFirstChildOfClass("Backpack")) ~= nil
	end, 15, S.COARSE)
	t.ok(ready, `{device}: the victim's HUD («ЗАЩИТА») and the rod`)
	sim:Advance(5) -- the intro and the welcome toasts are done
	return sim, victim, thief
end

-- The victim casts from his FishingSpot and hooks the bite: the minigame (FishingState
-- "Minigame"). Returns true when it began.
local function toMinigame(t: any, sim: any, p: any): boolean
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
	local bite = sim:WaitFor(function()
		for i = count + 1, #events() do
			if events()[i].args[1] == "Bite" then
				return events()[i]
			end
		end
		return nil
	end, 14, 1 / 30)
	t.ok(bite, "the bite")
	sim:Advance(0.2)
	count = #events()
	sim:FireServer(p, "FishingHook")
	local hooked = after(count, 1)
	t.ok(hooked and hooked.args[1] == "Minigame", "hooked: the minigame")
	sim:Advance(0.3)
	t.ok(hudOf(p).Fishing.Minigame.Visible, "the minigame is on screen")
	return hooked ~= nil and hooked.args[1] == "Minigame"
end

local function lastFishingState(sim: any, p: any): string?
	local list = sim:ClientEventsFor(p, "FishingState")
	local last = list[#list]
	return last and last.args[1]
end

-- After the shield: the minigame is still the state and its button still sends FishingTap.
local function minigameAnswers(t: any, sim: any, p: any, what: string)
	t.eq(lastFishingState(sim, p), "Minigame", `{what}: no FishingState change`)
	t.ok(hudOf(p).Fishing.Minigame.Visible, `{what}: the minigame stays on screen`)
	local before = #sim:ServerEventsFor(p, "FishingTap")
	sim:Advance(FishingConfig.TapInterval + 0.05)
	sim:Click(p, hudOf(p).Fishing.ActionArea.ActionButton)
	sim:Advance(1 / 60)
	t.eq(#sim:ServerEventsFor(p, "FishingTap"), before + 1, `{what}: «ЛОВИ!» still sends FishingTap`)
end

local tests = {}

tests["real server, phone: a hold during the minigame — one tap on the pill's ЩИТ saves the fish, the minigame keeps its input"] = function(
	t
)
	local sim, victim, thief = realPair(t, "phone")
	if not toMinigame(t, sim, victim) then
		return
	end
	local hold = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active, "the thief's hold began")
	local shown = sim:WaitFor(function()
		local stats = alertStats(sim, victim)
		return stats.phase == "hold" and stats.shown ~= nil
	end, 1.5, 1 / 30)
	t.ok(shown, "the alert shows within a moment (in the minigame)")
	local stats = alertStats(sim, victim)
	t.eq(stats.shown, "compact", "a phone: the Compact pill (the plate would cover the fisher)")
	t.ok(
		stats.fisher ~= nil and stats.rect ~= nil and not hits(stats.rect, stats.fisher),
		"the pill is not on the fisher"
	)
	t.eq(hudOf(victim):GetAttribute("AlertPhase"), "hold", "AlertPhase = hold")
	local button = shieldButton(victim)
	t.ok(button.Visible and button.AbsoluteSize.Y >= 56 - 0.5, `the pill's ЩИТ ≥ 56 px ({button.AbsoluteSize.Y})`)
	sim:Click(victim, button)
	sim:Advance(1 / 60)
	sim:Click(victim, button) -- (a second tap while waiting: nothing more)
	sim:Advance(0.5)
	t.eq(#sim:ServerEventsFor(victim, "ShieldActivate"), 1, "one ShieldActivate")
	local saved = sim:WaitFor(function()
		return #S.theftEvents(sim, victim, "Saved") > 0
	end, 2, 1 / 30)
	t.ok(saved, "StealEvent Saved to the victim")
	local event = S.theftEvents(sim, victim, "Saved")[1]
	t.eq(event and event.data.Reason, "shield", "saved by the shield")
	t.eq(thief:GetAttribute("Stealing"), nil, "the thief stopped")
	t.ok(#S.defenceEvents(sim, victim, "Shield") >= 1, "DefenceEvent Shield")
	minigameAnswers(t, sim, victim, "after the shield")
	sim:Advance(0.6)
	t.eq(alertStats(sim, victim).shown, nil, "the pill is gone")
	t.eq(hudOf(victim):GetAttribute("AlertPhase"), nil, "AlertPhase cleared")
	sim:AssertNoErrors({ warnings = true })
end

tests["real server, tablet: the carry during the minigame — the plate, the column «ЩИТ!» returns the fish, the minigame keeps its input"] = function(
	t
)
	local sim, victim, thief = realPair(t, "tablet")
	if not toMinigame(t, sim, victim) then
		return
	end
	S.toCarry(t, sim, thief, victim, 3)
	local carry = sim:WaitFor(function()
		local stats = alertStats(sim, victim)
		return stats.phase == "carry" and stats.shown ~= nil
	end, 1.5, 1 / 30)
	t.ok(carry, "the alert says the carry")
	local stats = alertStats(sim, victim)
	t.eq(stats.shown, "plate", "a tablet: the full plate")
	local plate = hudOf(victim).TheftAlert
	local shield = plate.Buttons.Shield
	t.ok(shield.AbsoluteSize.Y >= 56 - 0.5, `the plate's ЩИТ ≥ 56 px ({shield.AbsoluteSize.Y})`)
	t.ok(
		shield.AbsoluteSize.X >= THEFT.ShieldShare * plate.AbsoluteSize.X - 1,
		`the plate's ЩИТ ≥ {THEFT.ShieldShare * 100} % ({shield.AbsoluteSize.X} of {plate.AbsoluteSize.X})`
	)
	local column = hudOf(victim).RightButtons.DefenceButton
	local defence = module(sim, victim, "DefenceController")
	t.ok(
		call(sim, victim, function()
			return defence.Stats().alert
		end),
		"the column button is «ЩИТ!»"
	)
	sim:Click(victim, column)
	sim:Advance(0.5)
	t.eq(#sim:ServerEventsFor(victim, "ShieldActivate"), 1, "one ShieldActivate from the column")
	t.eq(
		call(sim, victim, function()
			return defence.IsOpen()
		end),
		false,
		"no sheet opened"
	)
	local saved = sim:WaitFor(function()
		return #S.theftEvents(sim, victim, "Saved") > 0
	end, 2, 1 / 30)
	t.ok(saved, "the carried fish is returned (Saved)")
	t.eq(thief:GetAttribute("Stealing"), nil, "the thief stopped")
	minigameAnswers(t, sim, victim, "after the shield in the carry")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- The client against a stubbed server
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

local function addPlayer(sim: any, id: number, screen: { [string]: any }?, money: number?): any
	local s = screen or SCREENS[1]
	local p = sim:AddPlayer({ UserId = id, Name = `Keeper{id}`, device = s.device, viewport = s.viewport })
	sim:Advance(1)
	for name, value in
		{
			DataMode = "Ready",
			Money = money or 0,
			Income = 0,
			TankSlots = 6,
			TankCount = 4,
			SellRatePct = 100,
			SellPlace = "",
			LockLevel = 0,
			ShieldReadyAt = 0,
		}
	do
		p:SetAttribute(name, value)
	end
	sim:Advance(5) -- the base banner has landed, «ЗАЩИТА» popped in, the welcome toast is gone
	return p
end

local function baseOf(sim: any, p: any): any
	return sim.workspace.Bases:FindFirstChild(`Base_{p:GetAttribute("BaseIndex")}`)
end

local function stealEvent(sim: any, p: any, kind: string, data: any)
	sim:Find("ReplicatedStorage.Remotes.StealEvent"):FireClient(p, kind, data)
	sim:Advance(1 / 60)
end

local function defenceEvent(sim: any, p: any, kind: string, data: any)
	sim:Find("ReplicatedStorage.Remotes.DefenceEvent"):FireClient(p, kind, data)
	sim:Advance(1 / 60)
end

-- StealService's alert to the victim (the base's Thief first, like the server).
local function alert(sim: any, p: any, extra: { [string]: any }?)
	local d: { [string]: any } = {
		Phase = "hold",
		Thief = 2002,
		Name = "Ника",
		Slot = 2,
		FishId = "Puffer",
		Rarity = "Rare",
		Short = "Фугу",
		Income10 = 52,
		End = now(sim) + DefenceConfig.Lock.BaseHold,
	}
	for k, v in extra or {} do
		d[k] = v
	end
	local base = baseOf(sim, p)
	base:SetAttribute("Thief", d.Thief)
	base:SetAttribute("AlarmState", "theft")
	stealEvent(sim, p, "Alert", d)
end

-- The theft over (the base's Thief cleared), then the result event.
local function over(sim: any, p: any, kind: string?, data: any?)
	local base = baseOf(sim, p)
	base:SetAttribute("Thief", nil)
	base:SetAttribute("AlarmState", nil)
	if kind then
		stealEvent(sim, p, kind, data)
	end
end

local function waitShown(sim: any, p: any, timeout: number?): boolean
	return sim:WaitFor(function()
		return alertStats(sim, p).shown ~= nil
	end, timeout or 2, 1 / 30) ~= nil
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

tests["the plate on tablet / desktop, the pill on phones never on the fisher; ЩИТ ≥ 56 px and ≥ 35 %, ДОМОЙ ≥ 44 px, ≥ 16 px to the status stack and the column"] = function(
	t
)
	for _, screen in SCREENS do
		local sim = boot(t)
		local p = addPlayer(sim, 1, screen)
		alert(sim, p)
		t.ok(waitShown(sim, p), `{screen.name}: the alert shows`)
		sim:Advance(1) -- (popped in, the shake over)
		local stats = alertStats(sim, p)
		local hud = hudOf(p)
		local root = hud.TheftAlert
		local r = rectOf(root)
		local viewport = screen.viewport or sim.players.state[sim:Unwrap(p)].viewport
		t.ok(r.x0 >= 0 and r.y0 >= 0 and r.x1 <= viewport.X and r.y1 <= viewport.Y, `{screen.name}: on screen {fmt(r)}`)
		if screen.phone then
			t.eq(stats.shown, "compact", `{screen.name}: the Compact pill`)
			t.ok(stats.fisher ~= nil, `{screen.name}: the fisher's box is known`)
			if stats.fisher and stats.rect then
				t.ok(not hits(stats.rect, stats.fisher), `{screen.name}: the pill is not on the own fisher`)
			end
			local shield = root.Compact.Shield
			t.ok(
				shield.AbsoluteSize.Y >= 56 - 0.5,
				`{screen.name}: the pill's ЩИТ ≥ 56 px ({shield.AbsoluteSize.Y})`
			)
			t.ok(
				shield.AbsoluteSize.X >= THEFT.ShieldShare * root.AbsoluteSize.X - 1,
				`{screen.name}: the pill's ЩИТ ≥ 35 % of it ({shield.AbsoluteSize.X} of {root.AbsoluteSize.X})`
			)
		else
			t.eq(stats.shown, "plate", `{screen.name}: the full plate`)
			local shield, home = root.Buttons.Shield, root.Buttons.Home
			t.ok(shield.AbsoluteSize.Y >= 56 - 0.5, `{screen.name}: ЩИТ ≥ 56 px ({shield.AbsoluteSize.Y})`)
			t.ok(
				shield.AbsoluteSize.X >= THEFT.ShieldShare * root.AbsoluteSize.X - 1,
				`{screen.name}: ЩИТ ≥ 35 % of the plate ({shield.AbsoluteSize.X} of {root.AbsoluteSize.X})`
			)
			t.ok(home.AbsoluteSize.Y >= 44 - 0.5, `{screen.name}: ДОМОЙ ≥ 44 px ({home.AbsoluteSize.Y})`)
			t.ok(rectOf(root.Text).x1 <= rectOf(shield).x0, `{screen.name}: the text ends before the buttons`)
			t.eq(root.Text.Title.Text, ALERT.Hold, "«ВОР В САДКЕ!»")
			t.eq(
				root.Text.Sub.Text,
				fill(ALERT.HoldSub, { name = "Ника", short = "Фугу" }),
				"«Ника крадёт: Фугу»"
			)
		end
		for _, name in { "Wallet", "BaseBadge" } do
			local item = hud.Status:FindFirstChild(name)
			if item and item.Visible then
				t.ok(
					gap(r, rectOf(item)) >= 16 - 0.5,
					`{screen.name}: ≥ 16 px from Status.{name} ({gap(r, rectOf(item))})`
				)
			end
		end
		for _, button in hud.RightButtons:GetChildren() do
			if button:IsA("GuiObject") and button.Visible then
				t.ok(
					gap(r, rectOf(button)) >= 16 - 0.5,
					`{screen.name}: ≥ 16 px from {button.Name} ({gap(r, rectOf(button))})`
				)
			end
		end
		sim:AssertNoErrors({ warnings = true })
	end
end

tests["recharging: Slate «⏳ 1:12» (a tap wiggles, fires nothing), the carry line without «жми ЩИТ!»; stealing himself: no buttons (DC-04)"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, SCREENS[3])
	local UiFx = sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p)
	local wiggled: { any } = {}
	local wiggle = UiFx.wiggle
	UiFx.wiggle = function(gui: any, ...)
		table.insert(wiggled, gui)
		return wiggle(gui, ...)
	end
	p:SetAttribute("ShieldReadyAt", T(now(sim) + 72.5))
	alert(sim, p, { Phase = "carry" })
	t.ok(waitShown(sim, p), "the plate shows")
	sim:Advance(0.8)
	local root = hudOf(p).TheftAlert
	local caption = root.Buttons.Shield.Caption.Text
	t.ok(string.find(caption, "⏳", 1, true) and string.find(caption, "1:1", 1, true), `«⏳ 1:12» («{caption}»)`)
	t.eq(root.Text.Title.Text, ALERT.Carry, "«ВОР УБЕГАЕТ!»")
	t.eq(
		root.Text.Sub.Text,
		fill(ALERT.CarrySubWait, { name = "Ника", short = "Фугу" }),
		"the carry line without «жми ЩИТ!»"
	)
	sim:Click(p, root.Buttons.Shield)
	sim:Advance(0.1)
	t.eq(#sim:ServerEventsFor(p, "ShieldActivate"), 0, "a tap while recharging fires nothing")
	local hit = false
	for _, gui in wiggled do
		hit = hit or gui == root.Buttons.Shield
	end
	t.ok(hit, "it wiggles «no»")
	-- The second ticks on.
	sim:Advance(2)
	t.ok(root.Buttons.Shield.Caption.Text ~= caption, "the time ticks")
	-- Stealing himself (his own theft on another base): no buttons, the honest line.
	p:SetAttribute("ShieldReadyAt", 0)
	p:SetAttribute("Stealing", "hold")
	sim:Advance(0.3)
	t.eq(root.Buttons.Visible, false, "no buttons while stealing")
	t.eq(root.Text.Sub.Text, ALERT.Stealing, `«{ALERT.Stealing}»`)
	sim:AssertNoErrors({ warnings = true })
end

tests["ЩИТ: «⏳» until the server answers — one ShieldActivate for several taps; Shield clears it; the column «ЩИТ!» in the alert"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, SCREENS[3])
	local defence = module(sim, p, "DefenceController")
	alert(sim, p)
	t.ok(waitShown(sim, p), "the plate shows")
	sim:Advance(0.6)
	local stats = call(sim, p, function()
		return defence.Stats()
	end)
	t.ok(stats.alert, "the column button: «ЩИТ!»")
	local button = hudOf(p).RightButtons.DefenceButton
	t.eq(button.Caption.Text, DTEXTS.ButtonAlert, `«{DTEXTS.ButtonAlert}»`)
	t.ok(button.Badge.Visible, "with its «!»")
	local shield = hudOf(p).TheftAlert.Buttons.Shield
	sim:Click(p, shield)
	sim:Advance(1 / 60)
	t.ok(alertStats(sim, p).busy, "⏳ until the answer")
	t.ok(string.find(shield.Caption.Text, "⏳", 1, true) ~= nil, "«⏳» on the button")
	sim:Click(p, shield)
	sim:Click(p, button)
	sim:Advance(0.2)
	t.eq(#sim:ServerEventsFor(p, "ShieldActivate"), 1, "one ShieldActivate for three taps")
	-- The server: the attributes, then DefenceEvent "Shield", then the save.
	local at = now(sim)
	p:SetAttribute("ShieldUntil", T(at + DefenceConfig.Shield.Duration))
	p:SetAttribute("ShieldReadyAt", T(at + DefenceConfig.Shield.Duration + DefenceConfig.Shield.Cooldown))
	defenceEvent(sim, p, "Shield", { Until = at + DefenceConfig.Shield.Duration })
	t.eq(alertStats(sim, p).busy, false, "the answer clears ⏳")
	over(sim, p, "Saved", { Reason = "shield", Slot = 2, Text = RESULT.Saved.shield })
	local seen = watchToasts(sim, p, 2)
	local merged = string.match(RESULT.SavedShield, "^(.-){t}") or RESULT.SavedShield
	t.ok(anyHas(seen, merged), `one toast «{RESULT.SavedShield}» ({table.concat(seen, " | ")})`)
	t.ok(not anyHas(seen, "Щит включён"), "not «Щит включён» beside it")
	t.eq(alertStats(sim, p).shown, nil, "the plate is gone")
	-- The other order (Saved first, then the server's Shield): still one toast.
	p:SetAttribute("ShieldReadyAt", 0)
	p:SetAttribute("ShieldUntil", nil)
	sim:Advance(4) -- (the toasts above are gone)
	alert(sim, p)
	t.ok(waitShown(sim, p), "another alert")
	sim:Advance(0.6)
	sim:Click(p, hudOf(p).TheftAlert.Buttons.Shield)
	sim:Advance(0.1)
	at = now(sim)
	p:SetAttribute("ShieldUntil", T(at + DefenceConfig.Shield.Duration))
	p:SetAttribute("ShieldReadyAt", T(at + DefenceConfig.Shield.Duration + DefenceConfig.Shield.Cooldown))
	over(sim, p, "Saved", { Reason = "shield", Slot = 2, Text = RESULT.Saved.shield })
	defenceEvent(sim, p, "Shield", { Until = at + DefenceConfig.Shield.Duration })
	seen = watchToasts(sim, p, 2)
	t.ok(anyHas(seen, merged), "Saved first: the merged toast")
	t.ok(not anyHas(seen, "Щит включён"), "Saved first: no «Щит включён»")
	sim:Advance(4)
	-- A Denied with no item (the server refused the shield) clears ⏳ too.
	p:SetAttribute("ShieldReadyAt", 0)
	p:SetAttribute("ShieldUntil", nil)
	over(sim, p)
	sim:Advance(0.5)
	alert(sim, p)
	t.ok(waitShown(sim, p), "a new alert")
	sim:Advance(0.6)
	sim:Click(p, hudOf(p).TheftAlert.Buttons.Shield)
	sim:Advance(1 / 60)
	t.ok(alertStats(sim, p).busy, "⏳")
	defenceEvent(
		sim,
		p,
		"Denied",
		{ Reason = "stealing", Text = "Пока крадёшь сам, щит не включить" }
	)
	t.eq(alertStats(sim, p).busy, false, "Denied clears ⏳")
	sim:AssertNoErrors({ warnings = true })
end

tests["loud alerts ping three times and shake; coalesced Quiet ones do neither"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, SCREENS[3])
	local UiFx = sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p)
	local pings, shakes = 0, 0
	local sound, shake = UiFx.sound, UiFx.shake
	UiFx.sound = function(name: any, ...)
		if name == "ping" then
			pings += 1
		end
		return sound(name, ...)
	end
	UiFx.shake = function(gui: any, ...)
		if gui == hudOf(p).TheftAlert then
			shakes += 1
		end
		return shake(gui, ...)
	end
	alert(sim, p)
	sim:Advance(2)
	t.eq(pings, THEFT.Pings, `{THEFT.Pings} pings`)
	t.eq(shakes, 1, "one shake")
	-- The carry, coalesced (Quiet): the plate updates silently.
	alert(sim, p, { Phase = "carry", Quiet = true })
	sim:Advance(2)
	t.eq(pings, THEFT.Pings, "no ping for a Quiet alert")
	t.eq(shakes, 1, "no shake for a Quiet alert")
	t.eq(hudOf(p).TheftAlert.Text.Title.Text, ALERT.Carry, "but it says the carry")
	-- A Quiet save says nothing at all.
	over(sim, p, "Saved", { Reason = "failed", Slot = 2, Text = RESULT.Saved.failed, Quiet = true })
	local seen = watchToasts(sim, p, 1.2)
	t.ok(not anyHas(seen, RESULT.Saved.failed), "a Quiet save: no toast")
	t.eq(alertStats(sim, p).shown, nil, "the plate is gone")
	sim:AssertNoErrors({ warnings = true })
end

tests["a catch card up (CounterHold): HurryCard is called at once, the plate waits and shows once it is gone"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, SCREENS[3])
	local fishing = module(sim, p, "FishingController")
	local hurried = 0
	fishing.HurryCard = function()
		hurried += 1
	end
	local hud = hudOf(p)
	hud:SetAttribute("CounterHold", "f9") -- (the fish flies into «САДОК»)
	alert(sim, p)
	sim:Advance(0.1)
	t.eq(hurried, 1, "FishingController.HurryCard() once")
	t.eq(hud:GetAttribute("AlertPhase"), "hold", "AlertPhase set at once («ЩИТ!» in the column)")
	local stats = alertStats(sim, p)
	t.eq(stats.shown, nil, "the plate waits")
	t.ok(stats.waiting, "waiting for the card")
	sim:Advance(0.8)
	t.eq(alertStats(sim, p).shown, nil, "still waiting while the hold lasts")
	hud:SetAttribute("CounterHold", nil)
	t.ok(waitShown(sim, p, THEFT.CardAfter + 1), "the plate shows once the hold is gone")
	sim:AssertNoErrors({ warnings = true })
end

tests["a sheet open when the alert starts: «САДОК» closes at once, «ЗАЩИТА» stays and its shield card is «ЩИТ!»; a sheet opened during the alert hides the plate — never over a sheet"] = function(
	t
)
	for _, screen in { SCREENS[1], SCREENS[3] } do
		local sim = boot(t)
		local p = addPlayer(sim, 1, screen, 3000)
		local hud = hudOf(p)
		local tank = module(sim, p, "TankPanelController")
		local defence = module(sim, p, "DefenceController")
		local function never(what: string)
			local root = hud.TheftAlert
			for _, sheet in { hud.TankPanel, hud.DefencePanel } do
				if root.Visible and sheet.Visible then
					t.ok(
						not hits(rectOf(root), rectOf(sheet.Panel)),
						`{screen.name} {what}: the alert is not over {sheet.Name}`
					)
				end
			end
		end
		call(sim, p, function()
			return tank.Toggle()
		end)
		sim:Advance(0.6)
		t.ok(hud.TankPanel.Visible, `{screen.name}: «САДОК» open`)
		alert(sim, p)
		t.eq(
			call(sim, p, function()
				return tank.IsOpen()
			end),
			false,
			`{screen.name}: the alert closes «САДОК»`
		)
		t.eq(hud.TankPanel.Visible, false, `{screen.name}: at once (no closing animation under the plate)`)
		t.ok(waitShown(sim, p), `{screen.name}: then the alert shows`)
		never("after «САДОК»")
		-- «САДОК» opened during the alert: the plate steps aside while it is open.
		call(sim, p, function()
			return tank.Toggle()
		end)
		sim:Advance(0.4)
		t.ok(hud.TankPanel.Visible, `{screen.name}: «САДОК» opened during the alert`)
		t.eq(alertStats(sim, p).shown, nil, `{screen.name}: the plate waits`)
		t.eq(hud.TheftAlert.Visible, false, `{screen.name}: not drawn over the sheet`)
		never("«САДОК» during the alert")
		call(sim, p, function()
			return tank.Toggle()
		end)
		t.ok(waitShown(sim, p, 1.5), `{screen.name}: back once the sheet is closed`)
		over(sim, p, "Saved", { Reason = "failed", Slot = 2, Text = RESULT.Saved.failed, Quiet = true })
		sim:Advance(1)
		-- «ЗАЩИТА» open: it stays; its shield card is the «ЩИТ!».
		call(sim, p, function()
			return defence.Toggle()
		end)
		sim:Advance(0.6)
		alert(sim, p)
		sim:Advance(0.8)
		t.ok(
			call(sim, p, function()
				return defence.IsOpen()
			end),
			`{screen.name}: «ЗАЩИТА» stays open`
		)
		t.eq(alertStats(sim, p).shown, nil, `{screen.name}: no plate over it`)
		local looks = call(sim, p, function()
			return defence.Stats().cards.looks
		end)
		t.eq(looks.Shield, "alert", `{screen.name}: the shield card is the alert target`)
		local buy = hud.DefencePanel.Panel.Cards.ShieldCard.Buy
		t.eq(buy.Label.Text, DTEXTS.ButtonAlert, `{screen.name}: «{DTEXTS.ButtonAlert}» on it`)
		t.ok(buy:FindFirstChild("FxRing") ~= nil or sim:WaitFor(function()
			return buy:FindFirstChild("FxRing") ~= nil
		end, 1.5, 0.05) ~= nil, `{screen.name}: with red rings`)
		never("«ЗАЩИТА»")
		sim:Click(p, buy)
		sim:Advance(0.1)
		t.eq(#sim:ServerEventsFor(p, "ShieldActivate"), 1, `{screen.name}: one tap — ShieldActivate`)
		call(sim, p, function()
			return defence.Toggle()
		end)
		t.ok(waitShown(sim, p, 1.5), `{screen.name}: the alert shows once the sheet is closed`)
		never("after «ЗАЩИТА»")
		sim:AssertNoErrors({ warnings = true })
	end
end

tests["a catch while the alert is up: HurryCard again, the plate / pill hides until the card and its flight are gone"] = function(
	t
)
	for _, screen in { SCREENS[1], SCREENS[3] } do
		local sim = boot(t)
		local p = addPlayer(sim, 1, screen)
		local fishing = module(sim, p, "FishingController")
		local hurried = 0
		fishing.HurryCard = function()
			hurried += 1
		end
		local hud = hudOf(p)
		alert(sim, p)
		t.ok(waitShown(sim, p), `{screen.name}: the alert shows`)
		sim:Advance(0.5)
		local before = hurried
		hud:SetAttribute("CounterHold", "f9") -- (a new catch: the counter holds its number)
		sim:Advance(0.05)
		t.eq(hurried, before + 1, `{screen.name}: the new catch is hurried (HurryCard)`)
		t.eq(alertStats(sim, p).shown, nil, `{screen.name}: the alert steps aside`)
		sim:Advance(0.3)
		t.eq(hud.TheftAlert.Visible, false, `{screen.name}: not drawn over the card`)
		hud.Fishing.CatchCard.Visible = true
		sim:Advance(0.6)
		t.eq(alertStats(sim, p).shown, nil, `{screen.name}: still aside while the card is up`)
		t.eq(hud:GetAttribute("AlertPhase"), "hold", `{screen.name}: the alert lives on («ЩИТ!» in the column)`)
		hud.Fishing.CatchCard.Visible = false
		hud:SetAttribute("CounterHold", nil)
		t.ok(waitShown(sim, p, THEFT.CardAfter + 1), `{screen.name}: back once the card and its flight are gone`)
		local stats = alertStats(sim, p)
		if screen.phone and stats.rect then
			-- never by the Roblox buttons: the thumbstick and Jump keep 16 px
			local viewport = sim.players.state[sim:Unwrap(p)].viewport
			local hudTop = hud.AbsolutePosition.Y
			local r = {
				x0 = stats.rect.x0,
				y0 = stats.rect.y0 + hudTop,
				x1 = stats.rect.x1,
				y1 = stats.rect.y1 + hudTop,
			}
			local stick = { x0 = 0, y0 = viewport.Y - 90 - 16, x1 = 95 + 16, y1 = viewport.Y }
			t.ok(not hits(r, stick), `{screen.name}: ≥ 16 px from the thumbstick {fmt(r)}`)
		end
		sim:AssertNoErrors({ warnings = true })
	end
end

tests["a second alert right after the first one ended shows (the first one's hide does not hide it)"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, SCREENS[3])
	alert(sim, p)
	t.ok(waitShown(sim, p), "the first alert shows")
	sim:Advance(1.5)
	over(sim, p, "Saved", { Reason = "failed", Slot = 2, Text = RESULT.Saved.failed })
	sim:Advance(0.05) -- (a second thief starts at once)
	alert(sim, p, { Thief = 2003, Name = "Вика" })
	sim:Advance(0.8)
	local root = hudOf(p).TheftAlert
	t.ok(alertStats(sim, p).shown ~= nil, "the second alert is shown")
	t.ok(root.Visible, "its plate is visible")
	local scale = root:FindFirstChildOfClass("UIScale")
	t.ok(scale == nil or math.abs(scale.Scale - 1) < 0.05, `at full size ({scale and scale.Scale})`)
	t.eq(root.Text.Sub.Text, fill(ALERT.HoldSub, { name = "Вика", short = "Фугу" }), "about the new thief")
	sim:AssertNoErrors({ warnings = true })
end

tests["the phone pill (AlertLayout): the topmost free spot, kept while free, never by the Roblox buttons; the label shortens; the stealing reason"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, SCREENS[2])
	local layout = module(sim, p, "AlertLayout")
	local function R(x0: number, y0: number, x1: number, y1: number): Rect
		return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
	end
	local fisher = R(300, 100, 370, 250)
	local function spec(keepouts: { Rect }, extra: { [string]: any }?): { [string]: any }
		local list = { fisher }
		for _, k in keepouts do
			table.insert(list, k)
		end
		local out: { [string]: any } = {
			fisher = fisher,
			keepouts = list,
			top = 24,
			bottom = 300,
			left = 30,
			right = 560,
			column = { x0 = 150, x1 = 520 },
			height = 56,
			min = 160,
			narrow = 132,
			max = 300,
			gap = 24,
			tight = 20,
			step = 8,
		}
		for k, v in extra or {} do
			out[k] = v
		end
		return out
	end
	local function place(sp: { [string]: any }): (Rect?, string)
		return call(sim, p, function()
			return layout.compact(sp)
		end)
	end
	-- The status stack across the top (x 200..600): wide room only lower down, a narrow pill fits at
	-- the top left — the topmost wins (the top stays free in the bite and the minigame).
	local status = R(200, 0, 600, 90)
	local r, spot = place(spec({ status }))
	t.ok(r ~= nil and math.abs(r.y0 - 24) < 0.5, `the topmost spot ({spot} {r and fmt(r)})`)
	-- Kept while it stays free; a minigame lower down does not move it.
	local minigame = R(40, 170, 290, 300)
	local again, how = place(spec({ status, minigame }, { keep = r }))
	t.eq(how, "keep", "the same spot is kept")
	t.ok(again == r or (again and math.abs(again.y0 - r.y0) < 0.5), "it does not move")
	-- A keep spot that is covered now moves.
	local _, moved = place(spec({ status, R(0, 0, 200, 120) }, { keep = r }))
	t.ok(moved ~= "keep", `a covered spot is left ({moved})`)
	-- No room anywhere but by the thumbstick: never there — no pill at all.
	local everything = R(0, 0, 700, 240)
	local stick = R(0, 240, 120, 320)
	local last, why = place(spec({ everything }, { hard = { stick }, bottom = 320 }))
	if last then
		local gapX = math.max(stick.x0 - last.x1, last.x0 - stick.x1, 0)
		local gapY = math.max(stick.y0 - last.y1, last.y0 - stick.y1, 0)
		t.ok(math.max(gapX, gapY) >= 20 - 0.5, `the last resort keeps off the thumbstick ({why} {fmt(last)})`)
	end
	local none, noneWhy = place(spec({ everything }, { hard = { R(0, 0, 700, 400) } }))
	t.eq(none, nil, "no free spot at all: no pill")
	t.eq(noneWhy, "none", "«none»")
	-- The live pill on the smallest phone: a label that fits («ВОР! ФУГУ» or «ВОР!»).
	alert(sim, p)
	t.ok(waitShown(sim, p), "the alert shows")
	sim:Advance(1)
	local stats = alertStats(sim, p)
	t.eq(stats.shown, "compact", "phone_small: the pill")
	local label = hudOf(p).TheftAlert.Compact.Label
	t.ok(stats.label ~= nil and label.Visible, `a label («{stats.label}»)`)
	local UiFx = sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p)
	if stats.label then
		t.ok(
			stats.label == fill(ALERT.Compact, { short = "ФУГУ" }) or stats.label == ALERT.CompactShort,
			`«ВОР! ФУГУ» or «ВОР!» («{stats.label}»)`
		)
		t.ok(
			UiFx.textWidth(stats.label, 13) <= label.AbsoluteSize.X + 0.5,
			`it fits its box ({UiFx.textWidth(stats.label, 13)} ≤ {label.AbsoluteSize.X})`
		)
	end
	-- Stealing himself: no buttons, the label says why.
	p:SetAttribute("Stealing", "hold")
	sim:Advance(0.3)
	stats = alertStats(sim, p)
	local reasons = {
		[fill(ALERT.CompactStealing, { short = "ФУГУ" })] = true,
		[ALERT.CompactStealingShort] = true,
		[ALERT.CompactShort] = true,
	}
	t.ok(stats.label ~= nil and reasons[stats.label], `the stealing label («{stats.label}»)`)
	t.eq(hudOf(p).TheftAlert.Compact.Shield.Visible, false, "no ЩИТ while stealing")
	sim:AssertNoErrors({ warnings = true })
end

tests["the layers: edge pulse ≤ 0.35, «ДОМОЙ!» rings, «ДОМОЙ» 🔒 in the own carry, Status hidden while HUD.Stealing; all gone at the end"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, SCREENS[1])
	local hud = hudOf(p)
	sim:Advance(1)
	local baseline = clientConnections(sim, p)
	local frames = frameConnections(sim, p)
	alert(sim, p)
	local home = hud.RightButtons.HomeButton
	local strongest = 0
	for _ = 1, 30 do
		sim:Advance(0.1)
		for _, layer in hud:GetChildren() do
			if layer.Name == "FxAlertEdge" then
				for _, item in layer:GetDescendants() do
					if item:IsA("GuiObject") and item.Visible then
						local opacity = 1 - item.BackgroundTransparency
						local gradient = item:FindFirstChildOfClass("UIGradient")
						if gradient then
							local most = 0
							for _, k in gradient.Transparency.Keypoints do
								most = math.max(most, 1 - k.Value)
							end
							opacity *= most
						end
						strongest = math.max(strongest, opacity)
					end
				end
			end
		end
	end
	t.ok(strongest > 0, "the edges pulse")
	t.ok(strongest <= 0.35 + 1e-3, `the edge pulse ≤ 0.35 opacity ({string.format("%.3f", strongest)})`)
	t.eq(home.Caption.Text, ALERT.HomeAlert, `«{ALERT.HomeAlert}» on the home button`)
	t.ok(sim:WaitFor(function()
		return home:FindFirstChild("FxRing") ~= nil
	end, 1.5, 0.05) ~= nil, "rings around it")
	t.ok(hud.FxAlertEdge.ClipsDescendants, "the pulse in its own clipping layer (no fill under the top bar)")
	-- The fishing's own edge glow (a bite, a minigame aura): the pulse sleeps, the rings rest (phone).
	local glow = sim:Create("Frame", { Name = "FxVignette", BackgroundTransparency = 1 }, hud)
	sim:Advance(1.2)
	t.eq(alertStats(sim, p).edge, "asleep", "the pulse sleeps while the fishing glows")
	t.eq(hud.FxAlertEdge.Visible, false, "its layer hidden")
	t.eq(home:FindFirstChild("FxRing"), nil, "the «ДОМОЙ!» rings rest on a phone")
	t.eq(hud.RightButtons.DefenceButton:FindFirstChild("FxRing"), nil, "the «ЩИТ!» rings too")
	t.eq(home.Caption.Text, ALERT.HomeAlert, "«ДОМОЙ!» stays")
	glow:Destroy()
	sim:Advance(0.1)
	t.eq(alertStats(sim, p).edge, "on", "awake again")
	t.ok(sim:WaitFor(function()
		return home:FindFirstChild("FxRing") ~= nil
	end, 1.5, 0.05) ~= nil, "the rings are back")
	-- The own carry (he is the thief somewhere else): «ДОМОЙ» locked.
	p:SetAttribute("Stealing", "carry")
	hud:SetAttribute("Stealing", "carry")
	sim:Advance(0.3)
	t.eq(home.Icon.Text, ALERT.HomeLocked, "🔒 on «ДОМОЙ» in the carry")
	-- Mashing it asks the server nothing (its guard would answer each tap with a toast).
	for _ = 1, 4 do
		sim:Click(p, home)
		sim:Advance(0.25)
	end
	t.eq(#sim:ServerEventsFor(p, "RequestHome"), 0, "no RequestHome while locked")
	t.ok(not anyHas(toastTexts(p), StealConfig.Texts.HomeGuard), "no stack of guard toasts")
	t.eq(hud.Status.Visible, false, "HUD.Status hidden while HUD.Stealing is set (§6.4 rev. 3)")
	p:SetAttribute("Stealing", nil)
	hud:SetAttribute("Stealing", nil)
	sim:Advance(0.6)
	t.ok(home.Icon.Text ~= ALERT.HomeLocked, "unlocked after")
	t.ok(hud.Status.Visible, "Status back")
	-- The end (Thief cleared, the result): every layer goes.
	over(sim, p, "Saved", { Reason = "tag", Slot = 2, Text = RESULT.Saved.tag })
	sim:Advance(3)
	t.eq(hud:GetAttribute("AlertPhase"), nil, "AlertPhase cleared")
	t.eq(home.Caption.Text, ALERT.Home, "«ДОМОЙ» again")
	t.eq(alertStats(sim, p).shown, nil, "the pill is gone")
	t.eq(frameConnections(sim, p), frames, "no frame connection left")
	t.ok(
		clientConnections(sim, p) <= baseline,
		`connections back to the baseline ({clientConnections(sim, p)} ≤ {baseline})`
	)
	sim:AssertNoErrors({ warnings = true })
end

tests["results: Lost → «Украдено…», «Садок отдыхает …», one tip; Intruder → «👀 Ника у тебя во дворе!», «ЗАЩИТА» bobs"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, SCREENS[3])
	local defence = module(sim, p, "DefenceController")
	alert(sim, p)
	sim:Advance(1.5)
	over(sim, p, "Lost", {
		Fish = { Id = "Puffer", Rarity = "Rare", Kg = 2.1, Value = 58 },
		Name = "Ника",
		Until = now(sim) + 90,
		Kind = "after",
	})
	local seen = watchToasts(sim, p, 12) -- (the tip may queue behind the big theft toast)
	-- (the theft kind: the byline «Украдено» over the headline «ФУГУ (Ника)»)
	t.ok(anyHas(seen, "Украдено"), "«Украдено: Фугу (Ника)»")
	t.ok(anyHas(seen, "(Ника)"), "with the thief's name")
	t.ok(anyHas(seen, "Садок отдыхает"), `«{RESULT.LostSub}»`)
	local tips = 0
	for _, s in seen do
		for key, tip in DTEXTS.Tips do
			local head = string.match(tip, "^(.-) ?%(") or tip
			if s == tip or (key ~= "Shield" and string.find(s, head, 1, true) == 1) then
				tips += 1
			end
		end
	end
	t.eq(tips, 1, `one tip ({table.concat(seen, " | ")})`)
	t.ok(anyHas(seen, DTEXTS.Tips.Shield), "the shield was ready and unused: the shield tip")
	t.ok(anyHas(seen, DTEXTS.TipIcon), `with the tip's icon {DTEXTS.TipIcon}`)
	-- The alarm: someone in the yard.
	stealEvent(sim, p, "Intruder", { Thief = 2002, Name = "Ника" })
	sim:Advance(0.2)
	seen = watchToasts(sim, p, 1)
	t.ok(
		anyHas(seen, fill(StealConfig.Texts.Intruder, { name = "Ника" })),
		"«Ника у тебя во дворе!»"
	)
	t.ok(
		call(sim, p, function()
			return defence.Stats().bob
		end),
		"«ЗАЩИТА» bobs"
	)
	sim:AssertNoErrors({ warnings = true })
end

tests["the ShieldChip on 4 screens: on screen right of the badge, the time, the pulse in the last 10 s, gone at 0; the newbie EndingWarn toast"] = function(
	t
)
	for _, screen in SCREENS do
		local sim = boot(t)
		local p = addPlayer(sim, 1, screen)
		local tankRules = sim:Require(sim:Find("ReplicatedStorage.Shared.TankRules"))
		local base = baseOf(sim, p)
		local hud = hudOf(p)
		local defence = module(sim, p, "DefenceController")
		local left = DefenceConfig.Shield.EndingWarn + 3
		base:SetAttribute("ProtectUntil", tankRules.AttrTime(now(sim) + left))
		base:SetAttribute("ProtectKind", "newbie")
		sim:Advance(1.2)
		local chip = hud.Status.BaseBadge.ShieldChip
		t.ok(chip.Visible, `{screen.name}: the chip shows`)
		t.ok(
			call(sim, p, function()
				return defence.Stats().chip
			end),
			`{screen.name}: chip on`
		)
		local viewport = screen.viewport or sim.players.state[sim:Unwrap(p)].viewport
		local r = rectOf(chip)
		t.ok(r.x0 >= 0 and r.x1 <= viewport.X and r.y0 >= 0, `{screen.name}: on screen {fmt(r)}`)
		t.ok(
			r.x1 > rectOf(hud.Status.BaseBadge).x1 - 1 or r.x0 > rectOf(hud.Status.BaseBadge).x0,
			`{screen.name}: at the badge's right end`
		)
		t.ok(string.find(chip.Label.Text, ":", 1, true) ~= nil, `{screen.name}: the time («{chip.Label.Text}»)`)
		for _, button in hud.RightButtons:GetChildren() do
			if button:IsA("GuiObject") and button.Visible then
				t.ok(gap(r, rectOf(button)) >= 16 - 0.5, `{screen.name}: ≥ 16 px from {button.Name}`)
			end
		end
		-- The newbie protection ends soon: the lesson toast.
		local seen = watchToasts(sim, p, 4)
		t.ok(anyHas(seen, DTEXTS.Protect.Ending), `{screen.name}: the EndingWarn toast`)
		-- The last WarnLast s: Sun pulses; then it goes.
		sim:Advance(math.max(left - 4 - 1.2 - DefenceConfig.Shield.WarnLast + 2, 0))
		t.ok(chip.Visible, `{screen.name}: still there in the last seconds`)
		sim:Advance(DefenceConfig.Shield.WarnLast + 1)
		base:SetAttribute("ProtectUntil", nil)
		base:SetAttribute("ProtectKind", nil)
		sim:Advance(1)
		t.eq(chip.Visible, false, `{screen.name}: gone at 0`)
		sim:AssertNoErrors({ warnings = true })
	end
end

tests["«ЗАЩИТА» «!» once: when the first defence becomes affordable"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, SCREENS[1], 100)
	local badge = hudOf(p).RightButtons.DefenceButton.Badge
	sim:Advance(0.5)
	t.eq(badge.Visible, false, "no «!» while nothing is affordable")
	p:SetAttribute("Money", DefenceConfig.Lock.Levels[1].Price + 10)
	sim:Advance(0.6)
	t.ok(badge.Visible, "«!» when the lock becomes affordable")
	local defence = module(sim, p, "DefenceController")
	call(sim, p, function()
		return defence.Toggle()
	end)
	sim:Advance(0.6)
	t.eq(badge.Visible, false, "it goes when the sheet opens")
	call(sim, p, function()
		return defence.Toggle()
	end)
	sim:Advance(0.6)
	p:SetAttribute("Money", 50)
	sim:Advance(0.3)
	p:SetAttribute("Money", 50000)
	sim:Advance(0.6)
	t.eq(badge.Visible, false, "once per game: no second «!»")
	sim:AssertNoErrors({ warnings = true })
end

return tests
