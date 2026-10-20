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
	      – its pop-in, tilt, shake and punch stay in the room the placement left (AlertLayout.room
	        / motion, last-mile F-09): every frame of the first 0.8 s on 4 screens, the scaled and
	        turned plate keeps the placement's box gap (16 px + inks) to the status rows and the
	        column (was 10–15 px of drawn gap on a tablet and phone_small); the numbers of room /
	        motion themselves;
	      – recharging: Slate «⏳ 1:12» (a tap wiggles, fires nothing), the carry line without «жми
	        ЩИТ!»; stealing himself: no buttons, «Пока крадёшь сам, щит не включить» (DC-04);
	      – ЩИТ: «⏳» until the server answers, one ShieldActivate for several taps; the column
	        «ЩИТ!» in the alert (Berry, rings, «!»); a shield save shows ONE toast «Щит спас рыбу!
	        🛡️ 1:00» whichever of Shield / Saved comes first (no «Щит включён» beside it);
	      – loud alerts ping three times and shake; coalesced Quiet ones do neither;
	      – an alert with a catch card up (CounterHold): FishingController.HurryCard (a spy) is
	        called at once, the plate waits and shows once the hold is gone; a catch that lands
	        while the alert is up hurries the card again and hides the plate until it is gone; a
	        coalesced (Quiet) hold of a thief who already failed here within FailWindow does not
	        (UX-03, F-04), his carry and another thief do;
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
	        «ЗАЩИТА» bobs; one clock (F-12): «Садок отдыхает 1:25» and «Щит спас рыбу! 🛡️ 0:59»
	        tick with the ShieldChip beside them — the same time in every 0.1 s sample on a phone
	        and a tablet (the toast froze at its show before);
	      – toasts during the alert (phone, tablet, desktop): the intruder toast goes the moment
	        its thief's hold starts; toasts that arrive never land on the own fisher (on a tablet /
	        desktop they wait: no room above his head under the plate) and keep BandGap + the
	        plate's ink from it; they come out after the alert; bands stack ≥ 16 px + ink apart;
	      – an open sheet: the «ЗАЩИТА» header says «ВОР В САДКЕ!» / «ВОР УБЕГАЕТ!» (Berry, 🚨 / 🏃)
	        while the alert lasts; one tap on the card's «ЩИТ!» saves, the shield toast waits for
	        the sheet to close (then «Щит спас рыбу! 🛡️ …»); a loss — «Украдено» at once, «Садок
	        отдыхает …» after the sheet closes;
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
	end, 2.5, 1 / 30)
	t.ok(shown, "the alert shows once the hold outlasts the tap window (in the minigame)")
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

tests["the pop-in, tilt, shake and punch stay in the room the placement left: no frame nearer the status rows or the column than the placement keeps (AlertLayout.room / motion, F-09)"] = function(
	t
)
	-- The numbers (px HUD): a 520 × 72 plate starting exactly where the status stack's 16 px end.
	do
		local sim = boot(t)
		local p = addPlayer(sim, 1, SCREENS[3])
		local layout = module(sim, p, "AlertLayout")
		local spec = { from = 0.4, over = 0.1, tilt = 5, tiltMin = 1, shake = 5, punch = 1.1 }
		local function R(x0: number, y0: number, x1: number, y1: number): Rect
			return { x0 = x0, y0 = y0, x1 = x1, y1 = y1 }
		end
		local screen = R(11, 17, 1013, 700)
		local function roomOf(r: Rect, keepouts: { Rect }): any
			return call(sim, p, function()
				return layout.room(r, keepouts, 24, screen, 60)
			end)
		end
		local function motionOf(r: Rect, room: any): any
			return call(sim, p, function()
				return layout.motion(r, room, spec)
			end)
		end
		local plate = R(252, 182, 772, 254)
		local status = R(280, 8, 744, 158) -- (its rows with their ink; 24 px over the plate)
		local room = roomOf(plate, { status })
		t.ok(math.abs(room.up) < 0.01, `no room above under the status stack ({room.up})`)
		t.ok(room.left >= 59.9 and room.right >= 59.9 and room.down >= 59.9, "room on the other sides")
		local m = motionOf(plate, room)
		t.eq(m.tilt, 0, "no tilt: its raised corner would go up")
		t.ok(m.shake.Y == 0 and m.shake.X == 5, `the shake is sideways only ({m.shake.X}, {m.shake.Y})`)
		t.eq(m.flat, false, "the overshoot grows right and down: it fits")
		-- the own fisher's rod behind the plate (a box spanning it): no side is limited by it
		local rod = R(386, 15, 664, 547)
		local spanned = roomOf(plate, { status, rod })
		t.ok(spanned.down >= 59.9 and spanned.left >= 59.9, "a neighbour spanning the plate limits nothing")
		-- the fisher's hair under the plate's lip (U-11 on a PC): it may not go lower
		local hair = R(400, 240, 620, 600)
		local lip = roomOf(plate, { status, hair })
		t.eq(lip.down, 0, "a neighbour under its lip: no room below")
		local low = motionOf(plate, lip)
		t.eq(low.flat, true, "then the pop has no overshoot")
		t.ok(math.abs(low.punch - 1) < 1e-6, "and no punch over 1")
		-- the phone_small pill 0.4 px from the Wallet's 16 px: no overshoot, no sideways shake
		local pill = R(16, 24, 157, 80)
		local wallet = R(181.4, 0, 500, 90)
		local tight = roomOf(pill, { wallet })
		t.ok(tight.right < 1, `≈ no room on the right ({tight.right})`)
		local pm = motionOf(pill, tight)
		t.eq(pm.flat, true, "the pill pops without overshoot")
		t.ok(pm.shake.X < 1, `and does not shake sideways ({pm.shake.X})`)
		t.ok(pm.tilt > 1, `but still tilts (room above and left: {pm.tilt}°)`)
		-- room everywhere: the full Back pop, the 5° tilt, the 5 px shake, the 1.1 punch
		local free = motionOf(R(300, 300, 500, 356), roomOf(R(300, 300, 500, 356), {}))
		t.ok(not free.flat and math.abs(free.tilt - 5) < 1e-6, "with room: Back and 5°")
		t.ok(free.shake.X == 5 and free.shake.Y == 5 and math.abs(free.punch - 1.1) < 1e-6, "5 px, 1.1")
	end
	-- Live on 4 screens: every 1/60 s of the first 0.8 s, the plate as drawn (UIScale about its
	-- top-left corner, Rotation about the scaled centre, the shake's Position) keeps the box gap
	-- the placement keeps to every status row and column button within 40 px at rest — 16 px plus
	-- the inks (the plate under the Wallet: its 💵 10 + the plate's 8; the pill beside a widget:
	-- 6 + 4), or its rest gap if that is less.
	local known = 0
	for _, screen in SCREENS do
		local sim = boot(t)
		local p = addPlayer(sim, 1, screen)
		local hud = hudOf(p)
		local root = hud.TheftAlert
		local neighbours: { any } = {}
		for _, item in hud.Status:GetChildren() do
			if item:IsA("GuiObject") and item.Visible then
				table.insert(neighbours, item)
			end
		end
		for _, button in hud.RightButtons:GetChildren() do
			if button:IsA("GuiObject") and button.Visible then
				table.insert(neighbours, button)
			end
		end
		local function drawn(): Rect
			local r = rectOf(root)
			local scale = root:FindFirstChildOfClass("UIScale")
			local k = if scale then scale.Scale else 1
			local w, h = (r.x1 - r.x0) * k, (r.y1 - r.y0) * k
			local a = math.rad(root.Rotation)
			local hx = w / 2 * math.abs(math.cos(a)) + h / 2 * math.abs(math.sin(a))
			local hy = w / 2 * math.abs(math.sin(a)) + h / 2 * math.abs(math.cos(a))
			local cx, cy = r.x0 + w / 2, r.y0 + h / 2
			return { x0 = cx - hx, y0 = cy - hy, x1 = cx + hx, y1 = cy + hy }
		end
		local closest: { number } = {}
		local frames, peak, swayX = 0, 1, 0
		local rest0: Rect? = nil
		alert(sim, p)
		for _ = 1, 48 do
			sim:Advance(1 / 60)
			if root.Visible then
				frames += 1
				local box = drawn()
				for i, n in neighbours do
					closest[i] = math.min(closest[i] or math.huge, gap(box, rectOf(n)))
				end
				local scale = root:FindFirstChildOfClass("UIScale")
				peak = math.max(peak, if scale then scale.Scale else 1)
				rest0 = rest0 or rectOf(root)
				swayX = math.max(swayX, math.abs(rectOf(root).x0 - (rest0 :: Rect).x0))
			end
		end
		sim:Advance(1)
		local stats = alertStats(sim, p)
		local rest = rectOf(root)
		t.ok(frames > 30, `{screen.name}: the plate was seen popping ({frames} frames)`)
		local margin = if stats.shown == "plate" then 16 + 10 + 8 else 16 + 6 + 4
		for i, n in neighbours do
			local atRest = gap(rest, rectOf(n))
			if atRest < 40 and closest[i] then
				t.ok(
					closest[i] >= math.min(atRest, margin) - 0.5,
					`{screen.name}: {n.Name} {string.format("%.1f", closest[i])} px in the motion, {string.format(
						"%.1f",
						atRest
					)} at rest`
				)
			end
		end
		local m = stats.motion
		known += if m then 1 else 0
		if m then
			print(
				`[F-09] {screen.name}: {stats.shown} flat {m.flat} tilt {string.format("%.1f", m.tilt)} shake {m.shake.X},{m.shake.Y} punch {string.format(
					"%.3f",
					m.punch
				)}; peak scale {string.format("%.3f", peak)}, sideways {string.format("%.1f", swayX)} px`
			)
			-- still lively where there is room: an overshoot, or a shake, or a tilt
			t.ok(peak > 1.01 or swayX > 1 or m.tilt > 1 or m.shake.Y > 1, `{screen.name}: it still moves`)
		end
		sim:AssertNoErrors({ warnings = true })
	end
	t.eq(known, #SCREENS, "AlertController.Stats().motion on every screen")
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

tests["UX-03's client half (F-04): a coalesced (Quiet) hold of a thief who already failed here leaves the catch card alone — no HurryCard, the plate waits; his carry hurries it; another thief and an old failure hurry as before"] = function(
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
	-- the 1st attempt: a loud alert hurries the card; it fails («Кража сорвалась»)
	hud:SetAttribute("CounterHold", "f1")
	alert(sim, p)
	sim:Advance(0.1)
	t.eq(hurried, 1, "the 1st (loud) alert hurries the card")
	t.eq(alertStats(sim, p).calm, false)
	hud:SetAttribute("CounterHold", nil)
	over(sim, p, "Saved", { Reason = "released", Slot = 2, Text = RESULT.Saved.failed })
	sim:Advance(1)

	-- the same thief again within FailWindow, coalesced (Quiet): the card is left alone
	hud:SetAttribute("CounterHold", "f2")
	alert(sim, p, { Quiet = true })
	sim:Advance(0.1)
	t.eq(hurried, 1, "his Quiet hold: no HurryCard")
	local stats = alertStats(sim, p)
	t.eq(stats.calm, true, "calm")
	t.eq(hud:GetAttribute("AlertPhase"), "hold", "the column «ЩИТ!» is there all the same")
	t.eq(stats.shown, nil, "the plate waits for the card")
	hud:SetAttribute("CounterHold", "f3") -- (another catch lands during it: not hurried either)
	sim:Advance(0.1)
	t.eq(hurried, 1, "a catch during his calm hold: not hurried")
	-- his carry: the fish is leaving — hurried as always
	alert(sim, p, { Phase = "carry", Quiet = true })
	sim:Advance(0.1)
	t.eq(hurried, 2, "his carry hurries the card")
	t.eq(alertStats(sim, p).calm, false)
	hud:SetAttribute("CounterHold", nil)
	over(sim, p, "Saved", { Reason = "shield", Slot = 2, Text = RESULT.Saved.shield })
	sim:Advance(1)

	-- another thief's Quiet hold (a first attempt of his here) hurries
	hud:SetAttribute("CounterHold", "f4")
	alert(sim, p, { Quiet = true, Thief = 3003, Name = "Вова" })
	sim:Advance(0.1)
	t.eq(hurried, 3, "another thief: hurried")
	hud:SetAttribute("CounterHold", nil)
	over(sim, p, "Lost", { Fish = { Id = "Puffer", Rarity = "Rare" }, Name = "Вова" })
	sim:Advance(1)

	-- the first thief after FailWindow: an old failure no longer counts
	sim:Advance(StealConfig.Limits.FailWindow)
	hud:SetAttribute("CounterHold", "f5")
	alert(sim, p, { Quiet = true })
	sim:Advance(0.1)
	t.eq(hurried, 4, "after FailWindow: hurried again")
	hud:SetAttribute("CounterHold", nil)
	over(sim, p, "Saved", { Reason = "released", Slot = 2, Text = RESULT.Saved.failed, Quiet = true })
	sim:Advance(1)
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

-- The clock («1:25») in a text, nil — none.
local function clockOf(text: string?): string?
	return if type(text) == "string" then string.match(text, "(%d+:%d%d)") else nil
end

-- Every 0.1 s for `seconds`: the visible toast that has `needle` in its text against the ShieldChip.
-- Returns the samples where both were on screen, the mismatches and the distinct times seen.
local function sameClock(sim: any, p: any, needle: string, seconds: number): (number, { string }, number)
	local chip = hudOf(p).Status.BaseBadge.ShieldChip
	local samples, wrong, values, distinct = 0, {}, {}, 0
	local t0 = sim:Time()
	while sim:Time() - t0 < seconds do
		local toastClock: string? = nil
		for _, text in toastTexts(p) do
			if string.find(text, needle, 1, true) then
				toastClock = clockOf(text)
			end
		end
		local chipClock = if chip.Visible then clockOf(chip.Label.Text) else nil
		if toastClock and chipClock then
			samples += 1
			if toastClock ~= chipClock then
				table.insert(wrong, `{string.format("%.1f", sim:Time() - t0)} s: toast {toastClock}, chip {chipClock}`)
			end
			if not values[toastClock] then
				values[toastClock] = true
				distinct += 1
			end
		end
		sim:Advance(0.1)
	end
	return samples, wrong, distinct
end

tests["one clock (F-12): «Садок отдыхает …» and «Щит спас рыбу! 🛡️ …» tick with the ShieldChip — the same time in every 0.1 s sample while they are on screen (phone, tablet)"] = function(
	t
)
	for _, screen in { SCREENS[1], SCREENS[3] } do
		-- a loss: the «after» protection with a fraction of a second, as a real one has
		local sim = boot(t)
		local p = addPlayer(sim, 1, screen)
		local tankRules = sim:Require(sim:Find("ReplicatedStorage.Shared.TankRules"))
		local base = baseOf(sim, p)
		alert(sim, p)
		sim:Advance(1.5)
		local untilAt = tankRules.AttrTime(now(sim) + DefenceConfig.Shield.Duration + 25.3)
		base:SetAttribute("ProtectUntil", untilAt)
		base:SetAttribute("ProtectKind", "after")
		over(sim, p, "Lost", {
			Fish = { Id = "Puffer", Rarity = "Rare", Kg = 2.1, Value = 58 },
			Name = "Ника",
			Until = untilAt,
			Kind = "after",
		})
		local head = string.match(RESULT.LostSub, "^(.-) ?{t}") or RESULT.LostSub
		local samples, wrong, distinct = sameClock(sim, p, head, 14)
		t.ok(samples >= 15, `{screen.name}: «{head} …» beside the chip in {samples} samples`)
		t.ok(distinct >= 2, `{screen.name}: … and it ticked on screen ({distinct} times seen)`)
		t.eq(#wrong, 0, `{screen.name}: the toast and the chip say one time ({table.concat(wrong, "; ")})`)
		sim:AssertNoErrors({ warnings = true })

		-- a shield save: «Щит спас рыбу! 🛡️ 1:00» beside the chip's shield
		sim = boot(t)
		p = addPlayer(sim, 1, screen)
		tankRules = sim:Require(sim:Find("ReplicatedStorage.Shared.TankRules"))
		base = baseOf(sim, p)
		alert(sim, p)
		sim:Advance(1)
		local shieldUntil = tankRules.AttrTime(now(sim) + DefenceConfig.Shield.Duration - 0.6)
		p:SetAttribute("ShieldUntil", shieldUntil)
		base:SetAttribute("ProtectUntil", shieldUntil)
		base:SetAttribute("ProtectKind", "shield")
		over(sim, p, "Saved", { Reason = "shield", Slot = 2, Text = RESULT.Saved.shield })
		local shieldHead = string.match(RESULT.SavedShield, "^(.-) ?{t}") or RESULT.SavedShield
		samples, wrong, distinct = sameClock(sim, p, shieldHead, 6)
		t.ok(samples >= 15, `{screen.name}: «{shieldHead} …» beside the chip in {samples} samples`)
		t.ok(distinct >= 2, `{screen.name}: … and it ticked on screen ({distinct} times seen)`)
		t.eq(#wrong, 0, `{screen.name}: the shield toast and the chip say one time ({table.concat(wrong, "; ")})`)
		sim:AssertNoErrors({ warnings = true })
	end
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

-- The own fisher on screen (px, with FishingLayout's pad), as the controllers see him; nil — not
-- projected (no camera on him).
local function fisherOf(sim: any, p: any): Rect?
	local hud = hudOf(p)
	local Layout = module(sim, p, "FishingLayout")
	local origin = hud.AbsolutePosition
	local box = call(sim, p, function()
		return Layout.fisherBox(p.Character, sim.workspace.CurrentCamera, origin)
	end)
	if not box then
		return nil
	end
	return { x0 = box.x0 + origin.X, y0 = box.y0 + origin.Y, x1 = box.x1 + origin.X, y1 = box.y1 + origin.Y }
end

-- At the own fishing spot with the default follow camera behind him (12.5 studs back, 18° down;
-- RbxSim has no camera scripts — as tests/fishing_keepout): the controllers project him from it.
local function atSpotFollowed(sim: any, p: any)
	local base = baseOf(sim, p)
	sim:Teleport(p, base.FishingSpot.CFrame.Position + Vector3.new(0, 3, 0))
	sim:Advance(0.3)
	local look = base:GetPivot().LookVector
	local focus = p.Character.HumanoidRootPart.Position + Vector3.new(0, 1.5, 0)
	local eye = focus - look * (12.5 * math.cos(math.rad(18))) + Vector3.new(0, 12.5 * math.sin(math.rad(18)), 0)
	local camera = sim.workspace.CurrentCamera
	call(sim, p, function()
		camera.CFrame = roblox.CFrame.lookAt(eye, focus)
	end)
	sim:Advance(0.1)
end

local function liveToasts(p: any): { any }
	local out = {}
	for _, toast in hudOf(p).Toasts:GetChildren() do
		if toast.Name == "Toast" and toast:IsA("GuiObject") and toast.Visible then
			table.insert(out, toast)
		end
	end
	return out
end

tests["the plate on a tablet / PC stays clear of the own fisher's head (≥ 16 px from its drawn lip to his hair): it lifts towards the status stack, and only then gets shorter, never under Theft.PlateHeight (wave 3 ART-06)"] = function(
	t
)
	for _, screen in { SCREENS[3], SCREENS[4] } do
		local sim = boot(t)
		local p = addPlayer(sim, 1, screen)
		local hud = hudOf(p)
		local Layout = module(sim, p, "FishingLayout")
		atSpotFollowed(sim, p)
		alert(sim, p)
		t.ok(waitShown(sim, p), `{screen.name}: the alert shows`)
		sim:Advance(0.6)
		t.eq(alertStats(sim, p).shown, "plate", `{screen.name}: the plate`)
		local fisher = fisherOf(sim, p)
		t.ok(fisher ~= nil, `{screen.name}: the own fisher on screen`)
		local plate = rectOf(hud.TheftAlert)
		local wallet = rectOf(hud.Status.Wallet)
		if fisher then
			local hair = fisher.y0 + Layout.FISHER_PAD
			local clear = hair - (plate.y1 + 8)
			print(`[ART-06] {screen.name}: plate {fmt(plate)} hair {hair} clear {clear} wallet {fmt(wallet)}`)
			t.ok(plate.y1 - plate.y0 >= THEFT.PlateHeight - 0.5, `{screen.name}: never shorter than PlateHeight`)
			t.ok(plate.y0 >= wallet.y1 + 16 - 0.5, `{screen.name}: still ≥ 16 px under the Wallet row`)
			-- the lip (8 px ink) ≥ 16 px over his hair, unless the plate already sits at its
			-- highest and shortest (then as far as the screen allows)
			local atBest = plate.y1 - plate.y0 <= THEFT.PlateHeight + 0.5
			t.ok(clear >= 16 - 0.5 or atBest, `{screen.name}: the lip clear of his hair ({clear} px)`)
			t.ok(clear >= 8, `{screen.name}: never on his hair ({clear} px; was 0–3)`)
		end
		sim:AssertNoErrors({ warnings = true })
	end
end

tests["toasts during the alert: none pushed onto the own fisher or within the band gap of the plate; the intruder toast goes with its thief's hold; the waiting ones come out after the alert"] = function(
	t
)
	local intruder = fill(StealConfig.Texts.Intruder, { name = "Ника" })
	local news = {
		"Рыбка подросла: Окунь стоит $40!",
		"КапитанКрюк поймал легендарную рыбу!",
	}
	for _, screen in { SCREENS[1], SCREENS[3], SCREENS[4] } do
		local sim = boot(t)
		local p = addPlayer(sim, 1, screen)
		local notify = module(sim, p, "NotifyController")
		local hud = hudOf(p)
		atSpotFollowed(sim, p)
		-- The alarm's early warning, then Ника's hold 1.2 s later (the usual alarm-owner flow).
		stealEvent(sim, p, "Intruder", { Thief = 2002, Name = "Ника" })
		sim:Advance(1.2)
		t.ok(anyHas(toastTexts(p), intruder), `{screen.name}: «{intruder}» up`)
		alert(sim, p, { Thief = 2002 })
		local still = false
		for _, toast in hud.Toasts:GetChildren() do
			for _, item in toast:GetDescendants() do
				if item:IsA("TextLabel") and string.find(item.Text, intruder, 1, true) then
					still = true
				end
			end
		end
		t.ok(not still, `{screen.name}: the hold of the same thief drops it at once (the plate says it louder)`)
		t.ok(waitShown(sim, p), `{screen.name}: the alert shows`)
		sim:Advance(0.5)
		call(sim, p, function()
			for _, text in news do
				notify.Show(text, "info")
			end
		end)
		local fisher = if screen.phone then alertStats(sim, p).fisher else fisherOf(sim, p)
		if not screen.phone then
			t.ok(fisher ~= nil, `{screen.name}: the own fisher is on screen ({fisher and fmt(fisher)})`)
		end
		local shown, worst, near = 0, math.huge, math.huge
		for _ = 1, 15 do
			local plate = hud.TheftAlert
			for _, toast in liveToasts(p) do
				shown += 1
				local r = rectOf(toast)
				if fisher then
					local f = fisher :: Rect
					if hits(r, f) then
						worst = math.min(worst, -1)
					end
				end
				if plate.Visible and alertStats(sim, p).shown == "plate" then
					near = math.min(near, gap(r, rectOf(plate)))
				end
			end
			sim:Advance(0.1)
		end
		t.ok(worst > 0, `{screen.name}: no toast on the own fisher while the alert is up`)
		t.ok(
			near >= notify.BandGap() + 8 - 0.5,
			`{screen.name}: a toast under the plate keeps ≥ BandGap + the plate's ink ({near})`
		)
		if not screen.phone then
			t.eq(shown, 0, `{screen.name}: no room above the fisher's head under the plate — the toasts wait`)
		end
		over(sim, p, "Saved", { Reason = "failed", Slot = 2, Text = RESULT.Saved.failed })
		local seen = watchToasts(sim, p, 4)
		for _, text in news do
			t.ok(anyHas(seen, text), `{screen.name}: «{text}» after the alert`)
		end
		sim:AssertNoErrors({ warnings = true })
	end
	-- No fisher under the column (the camera turned away from him): a toast does show under the
	-- plate — BandGap below the plate's drawn bottom (its INK), not touching it.
	do
		local sim = boot(t)
		local p = addPlayer(sim, 1, SCREENS[4])
		local notify = module(sim, p, "NotifyController")
		atSpotFollowed(sim, p)
		local base = baseOf(sim, p)
		local look = base:GetPivot().LookVector
		local at = p.Character.HumanoidRootPart.Position
		local camera = sim.workspace.CurrentCamera
		call(sim, p, function()
			camera.CFrame = roblox.CFrame.lookAt(at - look * 2 + Vector3.new(0, 4, 0), at - look * 40)
		end)
		sim:Advance(0.1)
		t.eq(fisherOf(sim, p), nil, "desktop: the own fisher is off screen")
		alert(sim, p)
		t.ok(waitShown(sim, p), "desktop: the plate shows")
		sim:Advance(0.6)
		call(sim, p, function()
			notify.Show(news[1], "info")
		end)
		sim:Advance(0.8)
		local toasts = liveToasts(p)
		t.eq(#toasts, 1, "desktop: the toast shows under the plate")
		if toasts[1] then
			local plate, r = rectOf(hudOf(p).TheftAlert), rectOf(toasts[1])
			t.ok(r.y0 >= plate.y1, "below the plate")
			t.ok(
				r.y0 - plate.y1 >= notify.BandGap() + 8 - 0.5,
				`≥ BandGap + the plate's ink between the boxes ({r.y0 - plate.y1})`
			)
		end
		sim:AssertNoErrors({ warnings = true })
	end
	-- Bands stack with BandGap between them (the plate under the thief's band).
	local sim = boot(t)
	local p = addPlayer(sim, 1, SCREENS[3])
	local notify = module(sim, p, "NotifyController")
	local offset = call(sim, p, function()
		notify.Reserve("theft", 50)
		notify.Reserve("alert", 72)
		local at = notify.Offset("alert")
		notify.Reserve("theft", nil)
		notify.Reserve("alert", nil)
		return at
	end)
	t.ok(offset >= 50 + 16 + 8 - 0.01, `the second band ≥ 16 px + ink under the first ({offset})`)
	sim:AssertNoErrors({ warnings = true })
end

tests["an open sheet: result and protection toasts wait for it to close (its header and Wallet stay clear), «Украдено» shows at once; the «ЗАЩИТА» header says «ВОР В САДКЕ!» while the alert lasts"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, SCREENS[1], 3000)
	local hud = hudOf(p)
	local defence = module(sim, p, "DefenceController")
	local header = hud.DefencePanel.Panel.Header
	local function toggle()
		call(sim, p, function()
			return defence.Toggle()
		end)
		sim:Advance(0.6)
	end
	toggle()
	t.eq(header.Title.Text, DTEXTS.Title, "«ЗАЩИТА» in the header")
	alert(sim, p)
	sim:Advance(0.5)
	t.eq(header.Title.Text, ALERT.Hold, `the alert: «{ALERT.Hold}» in the header`)
	t.eq(header.Icon.Text, ALERT.IconHold, `with {ALERT.IconHold}`)
	t.ok(header.Title.TextColor3.R > header.Title.TextColor3.B, "in Berry")
	alert(sim, p, { Phase = "carry", Quiet = true })
	sim:Advance(0.1)
	t.eq(header.Title.Text, ALERT.Carry, `the carry: «{ALERT.Carry}»`)
	-- One tap on the card's «ЩИТ!» ends it with the shield: the toast waits for the sheet.
	sim:Click(p, hud.DefencePanel.Panel.Cards.ShieldCard.Buy)
	sim:Advance(0.1)
	t.eq(#sim:ServerEventsFor(p, "ShieldActivate"), 1, "one ShieldActivate")
	local at = now(sim)
	p:SetAttribute("ShieldUntil", T(at + DefenceConfig.Shield.Duration))
	p:SetAttribute("ShieldReadyAt", T(at + DefenceConfig.Shield.Duration + DefenceConfig.Shield.Cooldown))
	local base = baseOf(sim, p)
	base:SetAttribute("ProtectUntil", T(at + DefenceConfig.Shield.Duration))
	base:SetAttribute("ProtectKind", "shield")
	defenceEvent(sim, p, "Shield", { Until = at + DefenceConfig.Shield.Duration })
	over(sim, p, "Saved", { Reason = "shield", Slot = 2, Text = RESULT.Saved.shield })
	local merged = string.match(RESULT.SavedShield, "^(.-){t}") or RESULT.SavedShield
	local open = watchToasts(sim, p, 2.5)
	t.ok(not anyHas(open, "Щит"), `no shield toast over the open sheet ({table.concat(open, " | ")})`)
	t.eq(header.Title.Text, DTEXTS.Title, "the header is «ЗАЩИТА» again")
	t.eq(
		call(sim, p, function()
			return defence.Stats().cards.looks.Shield
		end),
		"active",
		"the card shows the shield «🛡️ 0:5x»"
	)
	toggle()
	local after = watchToasts(sim, p, 2)
	t.ok(anyHas(after, merged), `closed: «{RESULT.SavedShield}» comes ({table.concat(after, " | ")})`)
	t.ok(not anyHas(after, "Щит включён"), "one toast (not «Щит включён» too)")
	-- A loss with the sheet open: «Украдено» at once, the rest and the tip after it closes.
	p:SetAttribute("ShieldUntil", nil)
	base:SetAttribute("ProtectUntil", nil)
	base:SetAttribute("ProtectKind", nil)
	sim:Advance(3)
	toggle()
	alert(sim, p, { Thief = 2003, Name = "Вика" })
	sim:Advance(1)
	over(sim, p, "Lost", {
		Fish = { Id = "Puffer", Rarity = "Rare", Kg = 2.1, Value = 58 },
		Name = "Вика",
		Until = now(sim) + 90,
		Kind = "after",
	})
	open = watchToasts(sim, p, 3)
	t.ok(anyHas(open, "Украдено"), "«Украдено» over the sheet at once (the end of the alert)")
	t.ok(not anyHas(open, "Садок отдыхает"), "the rest waits for the sheet")
	toggle()
	after = watchToasts(sim, p, 10)
	t.ok(anyHas(after, "Садок отдыхает"), `closed: «{RESULT.LostSub}» with the time now`)
	t.eq(header.Title.Text, DTEXTS.Title, "the header is «ЗАЩИТА» when closed")
	sim:AssertNoErrors({ warnings = true })
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
