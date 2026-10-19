--[[
	Stage 4 thief UI (docs/stage4_design.md §5.1, §6.4, §6.8–§6.10, §7.6 «Thief (C)») against the
	REAL server: StealService, DefenceService, TankService and the stage 3 services run (Kit.boot of
	tests/stage4_kit through tests/stage4_server); the thief (and, where it matters, the victim) is a
	real client (S.player opts.client) running TheftController, TheftPrompts, FishingController and
	TankButtonController. Holds go through sim:BeginHold like a stock prompt, the carry through
	Kit.drive, the owner's shield through "ShieldActivate".

	What is checked:
	  • the prompt filter (TheftPrompts): every own prompt hidden by a LOCAL MaxActivationDistance 0
	    (the server's value untouched), still hidden after the server writes Enabled (S1 / S2: a
	    hold reads the local value — "out of range"); a neighbour's fish shown; the whole base hidden
	    while waiting (cooldown), under protection, during someone else's theft, at few fish and for a
	    much weaker victim, and shown again on time (one timer); one fish hidden when fresh, in
	    escrow, or weaker than everything in a full tank; the held prompt kept, all hidden in the
	    carry;
	  • the banner on a phone: the first-time hint in the court, «КРАДЁШЬ: {SHORT}» with the bar
	    filling to the server's end, «БЕГИ ЗА ОГРАДУ!» draining, the red beam to the nearest exit
	    (re-aimed when he moves), «🐕 СОБАКА!» while Slowed, «ДОБЫЧА!» with the 🐟 flight while
	    HUD.TankIncoming holds the «САДОК» arrival (the chip rolls only on arrival); «ВЗЯТЬ» and the
	    fishing hint step aside and come back; HUD.Stealing mirrors the phase (D greys «ДОМОЙ» and
	    hides Status from it); no frame job and no UiFx job left after;
	  • the layout on phone, notched phone, small phone, tablet, desktop: the hint, the hold, the carry
	    with the dog chip and «ДОБЫЧА!» inside the screen, ≥ 16 px from the thumbstick, Jump and the
	    right column, written in scale, text ≥ 12 px; the robbed display (TankWorldController.
	    StealRect, the follow camera) never under the bar;
	  • the server's answers: "Denied" ends the named prompt's hold (InputHoldEnd) and shows its
	    reason on glass; a Quiet repeat ends it without a new text; no answer in Hold.NoReply s →
	    InputHoldEnd + «Подожди секунду»; "Cancel" → «СОРВАЛОСЬ!» with the server's reason, the beam
	    and the «САДОК» hold released; the thief's "Returned" (his fish went back) → a toast;
	  • FishingController.HurryCard (DC-02): a Mythic card up closes within 1 s through the normal
	    path (the card flies into «САДОК», CounterHold cleared on arrival); asked during the Epic+
	    delay it closes as soon as it has shown.

	Run: lune run tools/run_tests.luau stage4_hud_thief
]]

local roblox = require("@lune/roblox")

local S = require("./stage4_server")

local CFrame = roblox.CFrame
local Vector2 = roblox.Vector2
local Vector3 = roblox.Vector3

local STEAL = S.StealConfig
local TEXTS = STEAL.Texts
local BANNER = TEXTS.Banner
local UI = S.config("UIConfig")
local SPEC = UI.Theft
local BAR = SPEC.Bar
local MAX = STEAL.Prompt.MaxDistance
local GAP = 16

local VICTIM = { { Id = "Perch" }, { Id = "Perch" }, { Id = "Puffer", Age = 200 }, { Id = "Crucian" } }
local THIEF = { { Id = "Crucian" } }

local DEVICES = {
	{ name = "phone", device = "phone" },
	-- (the notched phone's safe area: 844 × 390 less the 47 / 47 / 21 px insets)
	{ name = "phone_notch", device = "phone", viewport = Vector2.new(750, 369) },
	{ name = "phone_small", device = "phone", viewport = Vector2.new(667, 375) },
	{ name = "tablet", device = "tablet" },
	{ name = "desktop", device = "desktop" },
}

type Rect = { x0: number, y0: number, x1: number, y1: number }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

-- What this client sees of a prompt's reach (its local value, S1).
local function seen(sim: any, p: any, prompt: any): number
	return sim:Run(function()
		return prompt.MaxActivationDistance
	end, p)
end

local function shownOn(sim: any, p: any, owner: any): { number }
	local out = {}
	for slot = 1, 6 do
		local prompt = S.prompt(sim, owner, slot)
		if prompt and seen(sim, p, prompt) > 0 then
			table.insert(out, slot)
		end
	end
	return out
end

local function list(xs: { number }): string
	local parts = {}
	for _, x in xs do
		table.insert(parts, tostring(x))
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function serverTime(sim: any): number
	return sim.workspace:GetServerTimeNow()
end

local function attrTime(sim: any, t: number): number
	return S.shared(sim, "TankRules").AttrTime(t)
end

-- The thief's HUD handles.
local function ui(sim: any, p: any): { [string]: any }
	local function find(path: string): any
		local found = sim:Gui(p, `HUD.{path}`)
		assert(found, `HUD.{path} not found`)
		return found
	end
	return {
		hud = find("TheftBar").Parent,
		bar = find("TheftBar"),
		title = find("TheftBar.Title"),
		sub = find("TheftBar.Sub"),
		time = find("TheftBar.Time"),
		line = find("TheftBar.Line"),
		icon = find("TheftBar.Icon"),
		fill = find("TheftBar.Bar.Fill"),
		dog = find("TheftBar.DogChip"),
		slam = find("TheftTitle"),
		slamTitle = find("TheftTitle.Title"),
		slamSub = find("TheftTitle.Sub"),
		action = find("Fishing.ActionArea.ActionButton"),
		hint = find("Fishing.Hint"),
		right = find("RightButtons"),
		chip = find("RightButtons.TankButton.Count.Label"),
		toasts = find("Toasts"),
	}
end

local function modeOf(sim: any, p: any): string
	local controller = S.client(sim, p, "TheftController")
	return sim:Run(function()
		return controller.Mode()
	end, p)
end

local function prompts(sim: any, p: any): any
	return S.client(sim, p, "TheftPrompts")
end

local function call(sim: any, p: any, fn: () -> any): any
	return sim:Run(fn, p)
end

local function rect(gui: any): Rect
	local at, size = gui.AbsolutePosition, gui.AbsoluteSize
	return { x0 = at.X, y0 = at.Y, x1 = at.X + size.X, y1 = at.Y + size.Y }
end

local function grow(r: Rect, pad: number): Rect
	return { x0 = r.x0 - pad, y0 = r.y0 - pad, x1 = r.x1 + pad, y1 = r.y1 + pad }
end

local function hits(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 - 0.5 and b.x0 < a.x1 - 0.5 and a.y0 < b.y1 - 0.5 and b.y0 < a.y1 - 0.5
end

local function fmt(r: Rect?): string
	if not r then
		return "-"
	end
	return string.format("(%d,%d..%d,%d)", r.x0, r.y0, r.x1, r.y1)
end

local function viewportOf(sim: any, p: any): any
	return sim.players.state[sim:Unwrap(p)].viewport
end

-- The Roblox thumbstick and Jump button on a touch screen (px; fishing_keepout's).
local function touchControls(sim: any, p: any): (Rect, Rect)
	local vp = viewportOf(sim, p)
	if math.min(vp.X, vp.Y) <= 500 then
		return { x0 = 25, y0 = vp.Y - 90, x1 = 95, y1 = vp.Y - 20 }, {
			x0 = vp.X - 95,
			y0 = vp.Y - 90,
			x1 = vp.X - 25,
			y1 = vp.Y - 20,
		}
	end
	return { x0 = 60, y0 = vp.Y - 210, x1 = 180, y1 = vp.Y - 90 }, {
		x0 = vp.X - 170,
		y0 = vp.Y - 210,
		x1 = vp.X - 50,
		y1 = vp.Y - 90,
	}
end

local function setScreen(sim: any, p: any, d: { [string]: any })
	sim:SetDevice(p, d.device)
	if d.viewport then
		sim:SetViewport(p, d.viewport)
	end
	sim:Advance(0.1)
end

-- The thief's follow camera (12.5 studs behind, 20° down; the preview's and B's band contract).
local function follow(sim: any, p: any)
	local root = p.Character.HumanoidRootPart
	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z).Unit
	local eye = root.Position - flat * 11.7 + Vector3.new(0, 5.7, 0)
	local focus = root.Position + Vector3.new(0, 1.4, 0)
	local camera = sim.workspace.CurrentCamera
	sim:Run(function()
		camera.CFrame = CFrame.lookAt(eye, focus)
		camera.FieldOfView = 70
	end, p)
end

-- Every visible text of a widget: ≥ 12 px.
local function smallTexts(gui: any): { string }
	local out = {}
	local function check(item: any)
		if item:IsA("TextLabel") and item.Visible and item.Text ~= "" then
			local size = item.TextSize
			if item.TextScaled then -- (fits its box: an emoji socket; a constraint caps it)
				local limit = item:FindFirstChildOfClass("UITextSizeConstraint")
				size = if limit then math.max(limit.MinTextSize, 0) else item.AbsoluteSize.Y
				if limit and item.AbsoluteSize.Y < size then
					size = item.AbsoluteSize.Y
				end
			end
			if size < 12 then
				table.insert(out, `{item.Name} {size}`)
			end
		end
	end
	check(gui)
	for _, d in gui:GetDescendants() do
		check(d)
	end
	return out
end

local function scaleOnly(gui: any): boolean
	return gui.Position.X.Offset == 0
		and gui.Position.Y.Offset == 0
		and gui.Size.X.Offset == 0
		and gui.Size.Y.Offset == 0
end

-- A widget on this screen: inside it, ≥ 16 px from the touch controls and the right column.
local function placed(t: any, sim: any, p: any, gui: any, label: string)
	local vp = viewportOf(sim, p)
	local r = rect(gui)
	t.ok(r.x0 >= 0 and r.x1 <= vp.X and r.y1 <= vp.Y, `{label}: {fmt(r)} inside {vp.X}×{vp.Y}`)
	if sim.players.state[sim:Unwrap(p)].device.TouchEnabled then
		local stick, jump = touchControls(sim, p)
		t.ok(not hits(grow(r, GAP), stick), `{label}: {fmt(r)} ≥ 16 px from the thumbstick {fmt(stick)}`)
		t.ok(not hits(grow(r, GAP), jump), `{label}: {fmt(r)} ≥ 16 px from Jump {fmt(jump)}`)
	end
	local u = ui(sim, p)
	for _, item in u.right:GetChildren() do
		if item:IsA("GuiObject") and item.Visible and u.right.Visible then
			local c = rect(item)
			t.ok(not hits(grow(r, GAP), c), `{label}: {fmt(r)} ≥ 16 px from {item.Name} {fmt(c)}`)
		end
	end
	local small = smallTexts(gui)
	t.eq(#small, 0, `{label}: no text under 12 px ({table.concat(small, ", ")})`)
end

local function frameConnections(sim: any, p: any): number
	local ctx = sim:ContextName(p)
	return sim:CountConnections(function(conn: any)
		local what = conn.signal:describe()
		return conn.ctx.name == ctx
			and (string.find(what, "RenderStepped", 1, true) ~= nil or string.find(what, "Heartbeat", 1, true) ~= nil)
	end)
end

-- The frame connections of this client, for a failure message.
local function frameReport(sim: any, p: any): string
	local ctx = sim:ContextName(p)
	local out = {}
	for conn in sim.connections do
		local what = conn.signal:describe()
		if
			conn.ctx.name == ctx
			and (string.find(what, "RenderStepped", 1, true) ~= nil or string.find(what, "Heartbeat", 1, true) ~= nil)
		then
			table.insert(out, `{what} ({conn.script and conn.script:GetFullName() or "?"})`)
		end
	end
	return table.concat(out, "; ")
end

-- The StealEvent kinds this player got, in order (failure messages).
local function kinds(sim: any, p: any): string
	local out = {}
	for _, e in S.events(sim, p) do
		table.insert(out, `{e.kind}{if type(e.data) == "table" and e.data.Reason then ":" .. e.data.Reason else ""}`)
	end
	return table.concat(out, " ")
end

local function upper(sim: any, text: string): string
	return S.shared(sim, "TextUtil").upper(text)
end

-- The court of `owner` with the thief at Slot_k (so the hint chain sees him inside).
local function intoCourt(sim: any, thief: any, owner: any, slot: number)
	S.standAt(sim, thief, S.prompt(sim, owner, slot))
	sim:Advance(SPEC.HintEvery + 0.2)
end

local function waitFor(sim: any, fn: () -> boolean, timeout: number): boolean
	return sim:WaitFor(fn, timeout, S.FRAME) == true
end

local tests = {}

--------------------------------------------------------------------------------
-- The prompt filter (§5.1)
--------------------------------------------------------------------------------

tests["prompts: the own base hidden locally (the server's value untouched), a neighbour's fish shown, a server Enabled write keeps the hide (S1/S2)"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 101, { tank = VICTIM, client = true, device = "desktop" })
	local thief = S.player(t, sim, 102, { tank = THIEF, client = true, device = "phone" })
	sim:Advance(1)
	for slot = 1, 4 do
		local prompt = S.prompt(sim, victim, slot)
		t.eq(prompt.MaxActivationDistance, MAX, `Slot_{slot}: the server's reach stays {MAX}`)
		t.ok(prompt.Enabled, `Slot_{slot}: enabled on the server (a fish)`)
		t.eq(seen(sim, victim, prompt), 0, `Slot_{slot}: hidden on the owner's own client`)
		t.eq(seen(sim, thief, prompt), MAX, `Slot_{slot}: shown to the neighbour`)
	end
	for slot = 5, 6 do
		local prompt = S.prompt(sim, victim, slot)
		if prompt then
			t.eq(seen(sim, thief, prompt), 0, `Slot_{slot} (no fish): hidden`)
		end
	end
	local own = S.prompt(sim, thief, 1)
	t.eq(seen(sim, thief, own), 0, "the thief's own display: hidden on his client")

	-- S2: the server writes Enabled (off, on): the owner's local 0 stays, a hold is out of range.
	local first = S.prompt(sim, victim, 1)
	sim:Run(function()
		first.Enabled = false
	end)
	sim:Advance(0.1)
	sim:Run(function()
		first.Enabled = true
	end)
	sim:Advance(0.1)
	t.eq(seen(sim, victim, first), 0, "after the server's Enabled writes the owner's prompt is still hidden")
	S.standAt(sim, victim, first)
	local ok, reason = sim:CanUsePrompt(victim, first)
	t.ok(
		not ok and string.find(tostring(reason), "out of range", 1, true) ~= nil,
		`the owner cannot hold it ({reason})`
	)
	local hold = sim:BeginHold(victim, first)
	t.ok(not hold.active, "BeginHold on the own display does not start")
	S.standAt(sim, thief, first)
	t.ok(sim:CanUsePrompt(thief, first), "the neighbour can hold it")
	local stats = call(sim, thief, function()
		return prompts(sim, thief).Stats()
	end)
	t.ok(stats.Prompts >= 12, `TheftPrompts knows every display of both bases ({stats.Prompts})`)
	t.eq(#sim.Errors, 0, sim:FormatErrors())
end

tests["prompts: the whole base hidden while waiting, under protection, during another theft, at few fish, for a much weaker victim — back on time"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 111, { tank = VICTIM })
	local thief = S.player(t, sim, 112, { tank = THIEF, client = true, device = "phone" })
	local other = S.player(t, sim, 113, { tank = THIEF })
	local poor = S.player(t, sim, 114, { tank = { { Id = "Perch" }, { Id = "Crucian" } } })
	sim:Advance(3) -- (the HUD's pop-ins over: the frame-job baseline at rest)
	local tp = prompts(sim, thief)
	local base = S.baseOf(sim, victim)
	local function reason(): string?
		return call(sim, thief, function()
			return (tp.BaseReason(base))
		end)
	end
	t.eq(list(shownOn(sim, thief, victim)), "{1,2,3,4}", "every fish shown at first")
	local connections = call(sim, thief, function()
		return tp.Stats().Connections
	end)
	local frames = frameConnections(sim, thief)

	-- Waiting after a theft (StealCooldownUntil, server time): hidden, then shown on its own.
	thief:SetAttribute("StealCooldownUntil", attrTime(sim, serverTime(sim) + 2))
	sim:Advance(0.1)
	t.eq(list(shownOn(sim, thief, victim)), "{}", "cooldown: every prompt hidden")
	t.eq(reason(), "cooldown", "cooldown: the base's reason")
	sim:Advance(2.3)
	t.eq(list(shownOn(sim, thief, victim)), "{1,2,3,4}", "cooldown over: shown again (the expiry timer)")

	-- Protection (ProtectUntil / ProtectKind on the base model).
	base:SetAttribute("ProtectKind", "shield")
	base:SetAttribute("ProtectUntil", attrTime(sim, serverTime(sim) + 2))
	sim:Advance(0.1)
	t.eq(list(shownOn(sim, thief, victim)), "{}", "a shield: every prompt hidden")
	t.eq(reason(), "shield", "a shield: the base's reason")
	sim:Advance(2.3)
	t.eq(list(shownOn(sim, thief, victim)), "{1,2,3,4}", "the shield over: shown again")
	base:SetAttribute("ProtectKind", nil)
	base:SetAttribute("ProtectUntil", nil)

	-- Someone else's theft on the base (StealService writes the base's Thief).
	local hold, prompt = S.hold(t, sim, other, victim, 2)
	t.ok(hold.active and other:GetAttribute("Stealing") == "hold", "another thief holds Slot_2")
	sim:Advance(0.1)
	t.eq(list(shownOn(sim, thief, victim)), "{}", "another theft on the base: every prompt hidden")
	t.eq(reason(), "taken", "another theft: the base's reason")
	sim:ReleasePrompt(other, prompt)
	sim:Advance(0.5)
	t.eq(base:GetAttribute("Thief"), nil, "his theft is over")
	t.eq(list(shownOn(sim, thief, victim)), "{1,2,3,4}", "shown again")

	-- Few fish (Tank.Count < Limits.MinFishToRob).
	t.eq(list(shownOn(sim, thief, poor)), "{}", "a base with 2 fish: hidden")
	t.eq(
		call(sim, thief, function()
			return (tp.BaseReason(S.baseOf(sim, poor)))
		end),
		"few",
		"its reason"
	)

	-- A much weaker victim (the players' Income: RichMin / RichRatio).
	local income = thief:GetAttribute("Income")
	thief:SetAttribute("Income", STEAL.Limits.RichMin * 10)
	sim:Advance(0.1)
	t.eq(list(shownOn(sim, thief, victim)), "{}", "a much richer thief: hidden")
	t.eq(reason(), "weak", "its reason")
	thief:SetAttribute("Income", income)
	sim:Advance(0.1)
	t.eq(list(shownOn(sim, thief, victim)), "{1,2,3,4}", "back")
	sim:Advance(3) -- (the Wallet's rate roll over)

	t.eq(
		call(sim, thief, function()
			return tp.Stats().Connections
		end),
		connections,
		"no connection churn"
	)
	t.eq(
		frameConnections(sim, thief),
		frames,
		`no frame job (one task.delay to the soonest end): {frameReport(sim, thief)}`
	)
	t.eq(#sim.Errors, 0, sim:FormatErrors())
end

tests["prompts: one fish hidden when fresh, in escrow or weaker than everything in a full tank; the held prompt kept, all hidden in the carry"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 121, { tank = VICTIM })
	local full = {}
	for _ = 1, S.config("TankConfig").StartSlots do
		table.insert(full, { Id = "Perch", Kg = 1.8 })
	end
	local thief = S.player(t, sim, 122, { tank = full, client = true, device = "phone" })
	sim:Advance(1)
	t.eq(thief:GetAttribute("TankCount"), thief:GetAttribute("TankSlots"), "the thief's tank is full")
	-- (Perches of MaxKg: the victim's Perch / Crucian are weaker, the Puffer stronger)
	t.eq(list(shownOn(sim, thief, victim)), "{3}", "a full tank: only the fish stronger than his weakest")

	-- Fresh catch (FreshUntil) and escrow on the victim's displays: those hidden only.
	local roomy = S.player(t, sim, 123, { tank = THIEF, client = true, device = "phone" })
	sim:Advance(0.5)
	t.eq(list(shownOn(sim, roomy, victim)), "{1,2,3,4}", "a thief with room: all four")
	S.addFish(sim, victim, "Puffer", nil, "catch")
	sim:Advance(0.2)
	local fresh = S.slotAttrs(sim, victim, 5)
	t.ok(fresh.FreshUntil ~= nil, "Slot_5: a fresh catch")
	t.eq(list(shownOn(sim, roomy, victim)), "{1,2,3,4}", "the fresh fish hidden, the rest shown")
	local reason = call(sim, roomy, function()
		return (prompts(sim, roomy).FishReason(S.baseOf(sim, victim)))
	end)
	t.eq(reason, "new", "the base's fish reason: the fresh one (the soonest timed)")
	local slot4 = S.slot(sim, victim, 4)
	slot4:SetAttribute("Escrow", true)
	sim:Advance(0.1)
	t.eq(list(shownOn(sim, roomy, victim)), "{1,2,3}", "a fish in escrow: hidden")
	slot4:SetAttribute("Escrow", nil)
	sim:Advance(0.1)
	t.eq(list(shownOn(sim, roomy, victim)), "{1,2,3,4}", "escrow cleared: shown")

	-- The hold keeps the held prompt (only it), the carry hides it too.
	local hold, prompt = S.hold(t, sim, roomy, victim, 3)
	t.ok(hold.active, "the hold began")
	sim:Advance(0.1)
	t.eq(list(shownOn(sim, roomy, victim)), "{3}", "holding: only the held prompt")
	t.ok(
		waitFor(sim, function()
			return roomy:GetAttribute("Stealing") == "carry"
		end, prompt.HoldDuration + 1),
		"the carry began"
	)
	sim:Advance(0.1)
	t.eq(list(shownOn(sim, roomy, victim)), "{}", "carrying: every prompt hidden, the held one too")
	t.eq(#sim.Errors, 0, sim:FormatErrors())
end

--------------------------------------------------------------------------------
-- The banner (§6.4, §6.8)
--------------------------------------------------------------------------------

tests["a theft on a phone: the hint, «КРАДЁШЬ», the carry with the beam and the dog, «ДОБЫЧА!» with the flight held by TankIncoming; «ВЗЯТЬ» steps aside; nothing left after"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 131, { tank = VICTIM, client = true, device = "desktop" })
	local thief = S.player(t, sim, 132, { tank = THIEF, client = true, device = "phone" })
	sim:Teleport(victim, S.exitPoint(S.baseOf(sim, thief), "gate")) -- (the owner away: no tag)
	sim:Advance(1.5)
	local u = ui(sim, thief)
	local victimChip = ui(sim, victim).chip
	local victimCount = victimChip.Text
	local UiFx = S.shared(sim, "UiFx", thief)
	local frames = frameConnections(sim, thief)
	t.ok(u.action.Visible, "«ВЗЯТЬ» / the rod button at first")
	t.eq(modeOf(sim, thief), "none", "no banner at first")

	-- The court: the first-time hint on glass (touch), «ВЗЯТЬ» and the fishing hint step aside.
	intoCourt(sim, thief, victim, 3)
	t.ok(u.bar.Visible and u.line.Visible, "the hint in the court")
	t.eq(u.line.Text, TEXTS.Hint.Touch, "the first-time hint (touch)")
	t.ok(not u.title.Visible and not u.fill.Parent.Visible, "the hint: no title, no bar")
	t.ok(not u.action.Visible, "«ВЗЯТЬ» steps aside for the banner")
	t.ok(not u.hint.Visible, "the fishing hint steps aside")

	-- The hold.
	local def = S.fishDef("Puffer")
	local hold, prompt = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active, "the hold began")
	sim:Advance(0.2)
	t.eq(u.hud:GetAttribute("Stealing"), "hold", "HUD.Stealing = hold")
	t.eq(modeOf(sim, thief), "hold", "the banner holds")
	t.eq(u.title.Text, S.fill(BANNER.Hold, { short = upper(sim, def.ShortName) }), "«КРАДЁШЬ: ФУГУ»")
	t.eq(u.sub.Text, BANNER.HoldSub, "«Не отходи!»")
	t.ok(string.match(u.time.Text, "^%d+,%d с$") ~= nil, `the time «{u.time.Text}»`)
	t.ok(not u.line.Visible and u.title.Visible, "the bar replaces the hint")
	local fill0 = u.fill.Size.X.Scale
	sim:Advance(0.8)
	local fill1 = u.fill.Size.X.Scale
	t.ok(fill1 > fill0 + 0.15, `the bar fills to the server's end ({fill0} → {fill1})`)
	t.ok(not u.action.Visible, "«ВЗЯТЬ» still aside")

	-- The carry: draining, the beam to the nearest exit, «САДОК» holds the arrival.
	t.ok(
		waitFor(sim, function()
			return thief:GetAttribute("Stealing") == "carry"
		end, prompt.HoldDuration + 1),
		"the carry began"
	)
	sim:ReleasePrompt(thief, prompt)
	sim:Advance(0.3)
	t.eq(u.hud:GetAttribute("Stealing"), "carry", "HUD.Stealing = carry (D greys «ДОМОЙ» from it)")
	t.eq(u.title.Text, BANNER.Carry, "«БЕГИ ЗА ОГРАДУ!»")
	t.eq(u.sub.Text, BANNER.CarrySub, "«Не попадись хозяину»")
	t.ok(string.match(u.time.Text, "^%d+ с$") ~= nil, `whole seconds «{u.time.Text}»`)
	t.eq(u.hud:GetAttribute("TankIncoming"), def.Rarity, "HUD.TankIncoming holds «САДОК» for the loot")
	local drain0 = u.fill.Size.X.Scale
	sim:Advance(1)
	t.ok(u.fill.Size.X.Scale < drain0, `the bar drains ({drain0} → {u.fill.Size.X.Scale})`)
	local root = thief.Character.HumanoidRootPart
	local rules = S.shared(sim, "StealRules")
	local base = S.baseOf(sim, victim)
	local function exitNow(): any
		local pivot = base:GetPivot()
		local exit = rules.NearestExit(rules.LocalOf(pivot, root.Position))
		return pivot * Vector3.new(exit.X, 0.3, exit.Z)
	end
	local beam = root:FindFirstChild("TheftGuide")
	t.ok(beam and beam:IsA("Beam"), "the red guide beam from the thief")
	if beam then
		local target = beam.Attachment1.WorldPosition
		t.ok((target - exitNow()).Magnitude < 0.5, `aimed at the nearest exit ({target} vs {exitNow()})`)
		local side = S.exitPoint(base, "side")
		S.drive(sim, thief, root.Position + (side - root.Position).Unit * 14, S.CARRY, { timeout = 2 })
		sim:Advance(SPEC.BeamEvery + 0.1)
		target = beam.Attachment1.WorldPosition
		t.ok((target - exitNow()).Magnitude < 0.5, `re-aimed after the move ({target} vs {exitNow()})`)
	end
	thief:SetAttribute("Slowed", true)
	sim:Advance(0.1)
	t.ok(u.dog.Visible, "«🐕 СОБАКА!» while Slowed")
	t.eq(u.dog:FindFirstChildWhichIsA("TextLabel", true).Text, BANNER.Dog, "its text")
	thief:SetAttribute("Slowed", nil)
	sim:Advance(0.4)
	t.ok(not u.dog.Visible, "gone when the dog lets go")

	-- Out over the gate: «ДОБЫЧА!», the 🐟 flight, the chip rolls on arrival only.
	local before = u.chip.Text
	local arrived = S.drive(sim, thief, S.exitPoint(base, "gate"), S.CARRY, {
		stop = function()
			return thief:GetAttribute("Stealing") == nil
		end,
		timeout = 25,
	})
	t.ok(not arrived and thief:GetAttribute("Stealing") == nil, "the theft ended at the fence")
	sim:Advance(S.FRAME * 2)
	t.ok(S.last(sim, thief, "Done") ~= nil, `StealEvent Done ({kinds(sim, thief)})`)
	t.eq(modeOf(sim, thief), "done", "the celebration")
	t.ok(u.slam.Visible and not u.bar.Visible, "«ДОБЫЧА!» replaces the bar")
	t.eq(u.slamTitle.Text, BANNER.Done, "«ДОБЫЧА!»")
	t.ok(string.find(u.slamSub.Text, def.ShortName, 1, true) ~= nil, `its line names the fish «{u.slamSub.Text}»`)
	t.eq(u.hud:GetAttribute("TankIncoming"), def.Rarity, "the arrival held while the 🐟 flies")
	t.eq(u.chip.Text, before, "the chip waits for the 🐟")
	t.ok(
		waitFor(sim, function()
			return u.hud:GetAttribute("TankIncoming") == nil
		end, BAR.FlyTime + 0.5),
		"the 🐟 arrives and lets «САДОК» go"
	)
	sim:Advance(0.6)
	t.ok(u.chip.Text ~= before, `the chip rolled on arrival ({before} → {u.chip.Text})`)
	t.eq(root:FindFirstChild("TheftGuide"), nil, "the beam is gone")
	t.eq(u.hud:GetAttribute("Stealing"), nil, "HUD.Stealing cleared")
	sim:Advance(SPEC.DoneTime + 0.5)
	t.eq(modeOf(sim, thief), "none", "the celebration over")
	t.ok(not u.slam.Visible and not u.bar.Visible, "nothing of the banner left")
	t.ok(u.action.Visible, "«ВЗЯТЬ» back")
	t.ok(
		victimChip.Text ~= victimCount,
		`the victim's «САДОК» rolled down on "Lost" ({victimCount} → {victimChip.Text})`
	)

	-- Back in the court: the wait after a theft, on glass, counting down (no prompt shown).
	intoCourt(sim, thief, victim, 2)
	t.ok(
		u.bar.Visible and string.find(u.line.Text, "Красть снова можно через", 1, true) ~= nil,
		`«{u.line.Text}»`
	)
	t.eq(list(shownOn(sim, thief, victim)), "{}", "no prompt while waiting")
	sim:Teleport(thief, S.exitPoint(S.baseOf(sim, thief), "gate"))
	sim:Advance(SPEC.HintEvery + 0.5)
	t.ok(not u.bar.Visible, "gone outside")
	sim:Advance(2)
	t.eq(UiFx.activeJobs(), 0, "no UiFx job left")
	t.eq(frameConnections(sim, thief), frames, `no frame job left: {frameReport(sim, thief)}`)
	t.eq(#sim.Errors, 0, sim:FormatErrors())
end

tests["the banner on 5 screens: the hint, the hold, the carry with the dog, «ДОБЫЧА!» — inside, ≥ 16 px from the controls and the column, in scale, text ≥ 12 px, the robbed display uncovered"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 141, { tank = VICTIM })
	local thief = S.player(t, sim, 142, { tank = THIEF, client = true, device = "phone" })
	sim:Teleport(victim, S.exitPoint(S.baseOf(sim, thief), "gate")) -- (the owner away: no tag)
	sim:Advance(1.5)
	local u = ui(sim, thief)
	local world = S.client(sim, thief, "TankWorldController")
	local base = S.baseOf(sim, victim)

	intoCourt(sim, thief, victim, 3)
	for _, d in DEVICES do
		setScreen(sim, thief, d)
		t.ok(u.bar.Visible and u.line.Visible, `{d.name}: the hint`)
		placed(t, sim, thief, u.bar, `{d.name} hint`)
		t.ok(scaleOnly(u.bar), `{d.name}: the hint in scale`)
	end

	setScreen(sim, thief, DEVICES[1])
	local hold, prompt = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active, "the hold began")
	sim:Advance(0.35)
	for _, d in DEVICES do
		setScreen(sim, thief, d)
		follow(sim, thief)
		sim:Advance(S.FRAME)
		placed(t, sim, thief, u.bar, `{d.name} hold`)
		t.ok(scaleOnly(u.bar), `{d.name}: the bar in scale`)
		local display = call(sim, thief, function()
			return world.StealRect(base, 3)
		end)
		t.ok(display ~= nil, `{d.name}: the robbed display on screen`)
		if display then
			t.ok(not hits(rect(u.bar), display), `{d.name}: the bar {fmt(rect(u.bar))} off the display {fmt(display)}`)
		end
	end
	setScreen(sim, thief, DEVICES[1])
	t.ok(
		waitFor(sim, function()
			return thief:GetAttribute("Stealing") == "carry"
		end, prompt.HoldDuration + 1),
		"the carry began"
	)
	sim:ReleasePrompt(thief, prompt)
	thief:SetAttribute("Slowed", true)
	sim:Advance(0.4)
	for _, d in DEVICES do
		setScreen(sim, thief, d)
		t.ok(u.dog.Visible, `{d.name}: the dog chip`)
		placed(t, sim, thief, u.bar, `{d.name} carry`)
		placed(t, sim, thief, u.dog, `{d.name} dog chip`)
		t.ok(not hits(grow(rect(u.dog), -1), rect(u.right)), `{d.name}: the chip off the column`)
	end
	thief:SetAttribute("Slowed", nil)
	setScreen(sim, thief, DEVICES[1])
	S.drive(sim, thief, S.exitPoint(base, "gate"), S.CARRY, {
		stop = function()
			return thief:GetAttribute("Stealing") == nil
		end,
		timeout = 25,
	})
	sim:Advance(0.5)
	t.eq(modeOf(sim, thief), "done", "«ДОБЫЧА!»")
	for _, d in DEVICES do
		setScreen(sim, thief, d)
		placed(t, sim, thief, u.slam, `{d.name} «ДОБЫЧА!»`)
		t.ok(scaleOnly(u.slam), `{d.name}: «ДОБЫЧА!» in scale`)
	end
	t.eq(#sim.Errors, 0, sim:FormatErrors())
end

tests["court hints: the own protection warning on every entry, the first-time hint once, a wait with a live countdown"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 181, { tank = VICTIM })
	local thief = S.player(t, sim, 182, { tank = THIEF, client = true, device = "desktop" })
	local home = S.exitPoint(S.baseOf(sim, thief), "gate")
	sim:Teleport(victim, home)
	sim:Advance(1)
	local u = ui(sim, thief)
	local own = S.baseOf(sim, thief)
	local function leave()
		sim:Teleport(thief, home)
		sim:Advance(SPEC.HintEvery + 0.2)
	end

	-- His own protection (DefenceService writes it on his base): a warning on each entry.
	own:SetAttribute("ProtectKind", "newbie")
	own:SetAttribute("ProtectUntil", attrTime(sim, serverTime(sim) + 120))
	intoCourt(sim, thief, victim, 3)
	t.ok(u.bar.Visible and u.line.Visible, "a hint on entry")
	t.eq(
		u.line.Text,
		TEXTS.Hint.Protected,
		"«Начнёшь красть — твоя защита погаснет»"
	)
	sim:Advance(BAR.HintTime + SPEC.HintEvery + 0.2)
	t.ok(not u.bar.Visible, `it leaves after HintTime ({BAR.HintTime} s)`)
	leave()
	intoCourt(sim, thief, victim, 3)
	t.eq(u.line.Text, TEXTS.Hint.Protected, "again on the next entry")
	leave()
	t.ok(not u.bar.Visible, "gone when he leaves the plot")

	-- No protection: the first-time hint (keyboard), once per session.
	own:SetAttribute("ProtectKind", nil)
	own:SetAttribute("ProtectUntil", nil)
	intoCourt(sim, thief, victim, 3)
	t.eq(u.line.Text, TEXTS.Hint.Keyboard, "«Держи E у витрины…» (PC)")
	leave()
	intoCourt(sim, thief, victim, 3)
	t.ok(not u.bar.Visible, "only once per session")

	-- Waiting after a theft: the reason stays while he is in the court, counting down.
	thief:SetAttribute("StealCooldownUntil", attrTime(sim, serverTime(sim) + 25))
	sim:Advance(SPEC.HintEvery + 0.2)
	local first = u.line.Text
	t.ok(
		u.bar.Visible and string.find(first, "Красть снова можно через", 1, true) ~= nil,
		`the wait «{first}»`
	)
	sim:Advance(1.2)
	t.ok(u.line.Text ~= first and u.bar.Visible, `counting down («{first}» → «{u.line.Text}»)`)
	sim:Advance(BAR.HintTime + 0.5)
	t.ok(u.bar.Visible, "still there: a reason, not a timed hint")
	leave()
	t.ok(not u.bar.Visible, "gone outside the plot")
	t.eq(#sim.Errors, 0, sim:FormatErrors())
end

--------------------------------------------------------------------------------
-- The server's answers
--------------------------------------------------------------------------------

tests["Denied ends the named hold and shows its reason; a Quiet repeat ends it silently; no answer in 1 s → InputHoldEnd + «Подожди секунду»"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 151, { tank = VICTIM })
	local thief = S.player(t, sim, 152, { tank = THIEF, client = true, device = "phone" })
	sim:Advance(1.5)
	local u = ui(sim, thief)
	intoCourt(sim, thief, victim, 3)
	sim:Advance(BAR.HintTime + 0.5) -- (the first-time hint is over)
	t.ok(not u.bar.Visible, "no hint left in the court")

	-- The owner next to the thief: the server refuses («Хозяин рядом!» — the client cannot know).
	local prompt = S.prompt(sim, victim, 3)
	S.standAt(sim, thief, prompt)
	local root = thief.Character.HumanoidRootPart
	sim:Teleport(victim, root.Position + root.CFrame.RightVector * (STEAL.Tag.Range - 2))
	sim:Advance(0.1)
	local hold = sim:BeginHold(thief, prompt)
	-- (remoteLatency 0: HoldBegan → Denied → InputHoldEnd within BeginHold itself)
	t.eq(hold.cancelReason, nil, "the hold began on the client (the prompt let it)")
	t.ok(
		waitFor(sim, function()
			return not hold.active
		end, 0.5),
		`Denied: the named prompt's hold ended (InputHoldEnd; {kinds(sim, thief)})`
	)
	local denied = S.last(sim, thief, "Denied")
	t.ok(
		denied and denied.Reason == "owner" and not denied.Quiet,
		`a loud Denied «owner» ({denied and denied.Reason})`
	)
	t.ok(u.bar.Visible and u.line.Visible, "its reason on glass")
	t.eq(u.line.Text, denied and denied.Text, "the server's text")
	local shownAt = sim:Time()

	-- The same refusal within DeniedEvery: Quiet — the hold ends, no new text (the old one leaves on time).
	sim:Advance(0.8)
	local again = sim:BeginHold(thief, prompt)
	t.eq(again.cancelReason, nil, "a second hold began")
	t.ok(
		waitFor(sim, function()
			return not again.active
		end, 0.5),
		"the quiet Denied ended it too"
	)
	t.eq(S.last(sim, thief, "Denied").Quiet, true, "the repeat was Quiet")
	sim:Advance(math.max(0, shownAt + SPEC.DeniedHint + 0.3 - sim:Time()))
	t.ok(not u.bar.Visible, "the first reason left on its own time: the quiet one showed nothing")

	-- No answer at all (a prompt the server does not know: silent) → NoReply.
	sim:Teleport(victim, S.exitPoint(S.baseOf(sim, victim), "gate"))
	sim:Advance(0.2)
	local fake = sim:Create("ProximityPrompt", {
		Name = "StealPrompt",
		HoldDuration = 3,
		RequiresLineOfSight = false,
	}, S.prompt(sim, victim, 4).Parent)
	sim:Advance(0.2)
	t.eq(seen(sim, thief, fake), MAX, "the client shows the unknown prompt (a fish is there)")
	S.standAt(sim, thief, fake)
	local silent = sim:BeginHold(thief, fake)
	t.ok(silent.active, "the hold began")
	sim:Advance(STEAL.Hold.NoReply - 0.2)
	t.ok(silent.active, "still held before NoReply")
	t.ok(
		waitFor(sim, function()
			return not silent.active
		end, 0.5),
		"no answer: the client ended the hold"
	)
	t.ok(u.bar.Visible and u.line.Text == BANNER.NoReply, `«Подожди секунду» («{u.line.Text}»)`)
	fake:Destroy()

	-- His fish went back (the victim's write never landed): "Returned" without Result → a toast.
	sim:Find("ReplicatedStorage.Remotes.StealEvent"):FireClient(thief, "Returned", {
		Fish = { Id = "Puffer", Rarity = "Rare" },
		Text = TEXTS.Result.Void,
	})
	sim:Advance(0.5)
	local toasted = false
	for _, d in u.toasts:GetDescendants() do
		if d:IsA("TextLabel") and d.Text == TEXTS.Result.Void then
			toasted = true
		end
	end
	t.ok(toasted, "«Рыба вернулась к хозяину» as a toast")
	t.eq(#sim.Errors, 0, sim:FormatErrors())
end

tests["Cancel: the owner's shield mid-hold → «СОРВАЛОСЬ!» with the reason; caught in the carry → the beam and «САДОК» released"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 161, { tank = VICTIM })
	local thief = S.player(t, sim, 162, { tank = THIEF, client = true, device = "phone" })
	local victim2 = S.player(t, sim, 163, { tank = VICTIM })
	sim:Advance(1.5)
	local u = ui(sim, thief)

	local result = S.steal(t, sim, thief, victim, 3, { cancel = "shield" })
	t.ok(result.hold and not result.hold.active, "the hold is over")
	local cancel = S.last(sim, thief, "Cancel")
	t.ok(cancel and cancel.Reason == "shield", `Cancel «shield» ({cancel and cancel.Reason})`)
	t.eq(modeOf(sim, thief), "fail", "«СОРВАЛОСЬ!»")
	t.eq(u.title.Text, BANNER.Fail, "the title")
	t.eq(u.sub.Text, cancel and cancel.Text, "the server's reason")
	t.eq(
		u.sub.Text,
		TEXTS.Cancel.shield,
		"«Хозяин включил щит — рыба вернулась домой»"
	)
	t.eq(u.hud:GetAttribute("Stealing"), nil, "HUD.Stealing cleared")
	sim:Advance(SPEC.FailTime + 0.4)
	t.ok(modeOf(sim, thief) ~= "fail", "gone after FailTime")

	-- Caught by the owner in the carry: «Хозяин тебя поймал!», nothing of the carry left.
	thief:SetAttribute("StealCooldownUntil", nil)
	sim:Advance(0.2)
	local caught = S.steal(t, sim, thief, victim2, 3, { cancel = "tag", phase = "carry" })
	t.ok(caught.hold ~= nil, "the second theft")
	sim:Advance(0.2)
	local tag = S.last(sim, thief, "Cancel")
	t.ok(tag and tag.Reason == "tag", `Cancel «tag» ({tag and tag.Reason})`)
	t.eq(u.sub.Text, TEXTS.Cancel.tag, "«Хозяин тебя поймал!»")
	t.eq(thief.Character.HumanoidRootPart:FindFirstChild("TheftGuide"), nil, "the beam is gone")
	t.eq(u.hud:GetAttribute("TankIncoming"), nil, "«САДОК» not held")
	t.ok(not u.dog.Visible, "no dog chip")
	t.eq(#sim.Errors, 0, sim:FormatErrors())
end

--------------------------------------------------------------------------------
-- FishingController.HurryCard (DC-02)
--------------------------------------------------------------------------------

tests["HurryCard: a Mythic card up closes within 1 s through the normal path; asked in the Epic+ delay it closes as soon as it has shown"] = function(
	t
)
	local sim = S.boot(t)
	local fisher = S.player(t, sim, 171, { tank = THIEF, client = true, device = "phone" })
	sim:Advance(1)
	local hud = S.hud(sim, fisher)
	local fishing = S.client(sim, fisher, "FishingController")
	local function hurry()
		sim:Run(function()
			fishing.HurryCard()
		end, fisher)
	end
	S.goFish(t, sim, fisher)
	S.forceFish(sim, "DragonFish")
	local count = fisher:GetAttribute("TankCount")
	S.catch(t, sim, fisher, hud, "Mythic")
	t.ok(hud.card.Visible, "the Mythic card is up")
	hurry()
	local at = sim:Time()
	t.ok(
		waitFor(sim, function()
			return not hud.card.Visible
		end, 1),
		`closed within 1 s ({string.format("%.2f", sim:Time() - at)} s)`
	)
	t.ok(
		waitFor(sim, function()
			return hud.screen:GetAttribute("CounterHold") == nil
		end, 2),
		"the 🐟 flew into «САДОК» (CounterHold cleared on arrival)"
	)
	t.eq(fisher:GetAttribute("TankCount"), count + 1, "the fish is in the tank")
	sim:Advance(2)

	-- Asked while the card waits out the Epic+ delay: closes as soon as it has shown.
	local before = #S.caughtEvents(sim, fisher)
	local bot = S.Fisher.new(sim, fisher, hud)
	bot:cast()
	local hurried, shownAt, closedAt = false, nil, nil
	sim:WaitFor(function()
		bot:look()
		if not hurried and #S.caughtEvents(sim, fisher) > before then
			hurried = true
			t.ok(not hud.card.Visible, "the card is still in its delay")
			hurry()
		end
		if hurried and hud.card.Visible and not shownAt then
			shownAt = sim:Time()
		end
		if shownAt and not hud.card.Visible then
			closedAt = sim:Time()
			return true
		end
		return false
	end, 30, S.FRAME)
	t.ok(hurried, "caught again")
	t.ok(shownAt ~= nil, "the card showed")
	t.ok(closedAt ~= nil, "and closed")
	if shownAt and closedAt then
		local up = closedAt - shownAt
		t.ok(up <= 1.5, `up for {string.format("%.2f", up)} s only (its own time is {UI.CatchCardTime.Mythic} s)`)
	end
	t.ok(
		waitFor(sim, function()
			return hud.screen:GetAttribute("CounterHold") == nil
		end, 2),
		"the arrival still played"
	)
	t.eq(#sim.Errors, 0, sim:FormatErrors())
end

return tests
