--[[
	Stage 4 last mile — the thief's client half of the server fixer's closed bases (docs/
	stage4_design.md §11.7 S-02, S-05, S-06 and the rows F-01…F-03) against the REAL server
	(tests/stage4_server: StealService, DefenceService, TankService and the stage 3 services run);
	the thief is a real client (TheftController, TheftPrompts), the owners are headless.

	What is checked:
	  • the shield bait (S-02): the owner's shield against his hold closes that base to him until
	    the owner's shield is ready again — on the client every «Украсть» of that base hides at once
	    (the Cancel's BaseUntil / BaseReason → TheftPrompts.SetTagged, TagKind «shielded»), the
	    court says «Хозяин включил щит — здесь красть снова через 3:5x» with 🛡️ and a live clock
	    (the base's wait, not the shield's own minute), still after the shield is over; another
	    base stays shown; the prompts come back when ShieldReadyAt passes;
	  • the wary base (S-05): two own-fault failures on one base — every base hidden while his 10 s
	    wait runs, but that court says 👀 «Хозяин настороже — здесь красть снова через …» with the
	    base's clock at once (the later wait is the true time there, F-11), then only that base
	    hidden; a rejoin forgets the client's map — the server's
	    "Denied" with Until (S-06) hides the base again, with its reason and clock, until Until;
	  • a "Denied" with Until for the other waits: «new» hides that one display, «cooldown» every
	    base, «shield» the whole base — each until Until, then back; a newer write of the same
	    attribute by the server lifts it;
	  • the protection warning (UX-01's client half, F-03): a fresh newbie in a neighbour's court
	    reads «Начнёшь красть — твоя защита погаснет» first, then the how-to; a tap keeps the
	    protection and the warning does not come back for it; a hold past the tap window ends it
	    (the server) and the next protection would warn again.

	Run: lune run tools/run_tests.luau stage4_hud_thief_base
]]

local S = require("./stage4_server")

local STEAL = S.StealConfig
local TEXTS = STEAL.Texts
local ICONS = TEXTS.Icons
local LIMITS = STEAL.Limits
local FAIL = LIMITS.FailCooldown
local SHIELD = S.SHIELD
local UI = S.config("UIConfig")
local SPEC = UI.Theft
local BAR = SPEC.Bar
local LONG = 0.25 -- the step of the long waits (the client's chains are task.delay ones)

local VICTIM = { { Id = "Perch" }, { Id = "Perch" }, { Id = "Puffer", Age = 200 }, { Id = "Crucian" } }
local THIEF = { { Id = "Crucian" } }

local function serverTime(sim: any): number
	return sim.workspace:GetServerTimeNow()
end

local function seen(sim: any, p: any, prompt: any): number
	return sim:Run(function()
		return prompt.MaxActivationDistance
	end, p)
end

local function shownOn(sim: any, p: any, owner: any): string
	local out = {}
	for slot = 1, 6 do
		local prompt = S.prompt(sim, owner, slot)
		if prompt and seen(sim, p, prompt) > 0 then
			table.insert(out, tostring(slot))
		end
	end
	return "{" .. table.concat(out, ",") .. "}"
end

local function bar(sim: any, p: any): { [string]: any }
	local root = sim:Gui(p, "HUD.TheftBar")
	assert(root, "HUD.TheftBar")
	return { bar = root, line = root.Line, icon = root.Icon.Icon }
end

-- TheftPrompts.BaseReason of the owner's base on the thief's client: (reason, left).
local function baseReason(sim: any, thief: any, owner: any): (string?, number?)
	local tp = S.client(sim, thief, "TheftPrompts")
	local base = S.baseOf(sim, owner)
	return sim:Run(function()
		return tp.BaseReason(base)
	end, thief)
end

-- The thief stands at the owner's Slot_k (his court chain sees him inside).
local function intoCourt(sim: any, thief: any, owner: any, slot: number)
	S.standAt(sim, thief, S.prompt(sim, owner, slot))
	sim:Advance(SPEC.HintEvery + 0.2)
end

-- «… через m:ss» of a refusal text → seconds (nil — no clock in it).
local function clockOf(text: string): number?
	local m, s = string.match(text, "(%d+):(%d%d)$")
	return if m then tonumber(m) * 60 + tonumber(s) else nil
end

-- The court's line reads the Denied text of `reason` with a clock ≈ `left` (± 1.5 s) and `icon`.
local function courtSays(t: any, u: { [string]: any }, reason: string, left: number, icon: string, label: string)
	local template = TEXTS.Denied[reason]
	local head = string.match(template, "^(.-){t}") or template
	local text = u.line.Text
	t.ok(u.bar.Visible and u.line.Visible, `{label}: a reason on glass`)
	t.eq(string.sub(text, 1, #head), head, `{label}: «{text}»`)
	local clock = clockOf(text)
	t.ok(clock ~= nil and math.abs(clock - left) <= 1.5, `{label}: the clock {clock} ≈ {left}`)
	t.eq(u.icon.Text, icon, `{label}: its icon`)
end

-- A hold of `seconds` on the owner's display, then let go: the thief's Cancel.
local function holdFor(t: any, sim: any, thief: any, owner: any, slot: number, seconds: number): any
	local hold, prompt = S.hold(t, sim, thief, owner, slot)
	t.ok(hold.active, `the hold on Slot_{slot} began ({hold.cancelReason})`)
	sim:Advance(seconds)
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	sim:Advance(0.2)
	return S.last(sim, thief, "Cancel")
end

local tests = {}

tests["the shield bait (S-02): the base hides at once with 🛡️ «Хозяин включил щит — здесь красть снова через 3:5x», still after the shield; another base shown; back when ShieldReadyAt passes"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 301, { tank = VICTIM })
	local thief = S.player(t, sim, 302, { tank = THIEF, client = true, device = "phone" })
	local other = S.player(t, sim, 303, { tank = VICTIM })
	sim:Teleport(victim, S.exitPoint(S.baseOf(sim, thief), "gate"))
	sim:Advance(1.5)
	local u = bar(sim, thief)
	t.eq(shownOn(sim, thief, victim), "{1,2,3,4}", "before: his fish shown")

	-- the bait: a hold, the kid taps ЩИТ
	local hold, prompt = S.hold(t, sim, thief, victim, 3)
	t.ok(hold.active, "the bait hold")
	sim:Advance(1)
	sim:FireServer(victim, "ShieldActivate")
	sim:Advance(0.2)
	local cancel = S.last(sim, thief, "Cancel")
	t.eq(cancel and cancel.Reason, "shield", "Cancel «shield»")
	t.eq(cancel and cancel.BaseReason, "shielded", "… BaseReason «shielded»")
	t.ok(cancel and type(cancel.BaseUntil) == "number", "… with BaseUntil")
	if hold.active then
		sim:ReleasePrompt(thief, prompt)
	end
	sim:Advance(0.2)
	local untilT = cancel.BaseUntil
	t.near(untilT, victim:GetAttribute("ShieldReadyAt"), 0.5, "BaseUntil = the owner's ShieldReadyAt")
	t.eq(shownOn(sim, thief, victim), "{}", "every «Украсть» of that base hidden at once")
	local reason, left = baseReason(sim, thief, victim)
	t.eq(reason, "shielded", "the client's reason: «shielded» (TagKind), not the shield's «shield»")
	t.near(left, untilT - serverTime(sim), 0.5, "… its clock to BaseUntil")
	t.eq(shownOn(sim, thief, other), "{1,2,3,4}", "another base stays shown")

	-- after «СОРВАЛОСЬ!» the court says why: 🛡️, the base's whole wait
	sim:Advance(SPEC.FailTime + 0.3)
	intoCourt(sim, thief, victim, 2)
	courtSays(t, u, "shielded", untilT - serverTime(sim), ICONS.Shield, "under the shield")
	t.ok(untilT - serverTime(sim) > 3 * 60 + 50, "«через 3:5x»")
	local first = u.line.Text
	sim:Advance(1.2)
	t.ok(u.line.Text ~= first, `a live clock («{first}» → «{u.line.Text}»)`)

	-- the shield is over: still closed, the same reason (the bait costs him the owner's recharge)
	sim:Advance(SHIELD.Duration + 0.5, LONG)
	t.eq(
		S.baseOf(sim, victim):GetAttribute("ProtectUntil") == nil
			or S.baseOf(sim, victim):GetAttribute("ProtectUntil") <= serverTime(sim),
		true,
		"the shield is over"
	)
	t.eq(shownOn(sim, thief, victim), "{}", "still hidden after the shield")
	courtSays(t, u, "shielded", untilT - serverTime(sim), ICONS.Shield, "after the shield")

	-- back when the owner's shield is ready again
	sim:Advance(untilT - serverTime(sim) - 2, LONG)
	t.eq(shownOn(sim, thief, victim), "{}", "2 s before: still hidden")
	sim:Advance(2.5)
	t.ok((victim:GetAttribute("ShieldReadyAt") or 0) <= serverTime(sim), "the owner's shield is ready")
	t.eq(shownOn(sim, thief, victim), "{1,2,3,4}", "the prompts are back")
	t.eq((baseReason(sim, thief, victim)), nil, "no reason left")
	sim:Advance(SPEC.HintEvery + 0.2)
	t.ok(not (u.bar.Visible and u.line.Text == first), "the reason left the glass")
	sim:AssertNoErrors({ warnings = true })
end

tests["the wary base (S-05): two own failures — 👀 «Хозяин настороже…» with the base's clock at once (F-11; his 10 s hides every base meanwhile), then that base only; a rejoin forgets it, the server's Denied with Until hides it again (S-06); back at BaseUntil"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 311, { tank = VICTIM })
	local thief = S.player(t, sim, 312, { tank = THIEF, client = true, device = "phone" })
	local other = S.player(t, sim, 313, { tank = VICTIM })
	sim:Teleport(victim, S.exitPoint(S.baseOf(sim, thief), "gate"))
	sim:Advance(1.5)

	-- the 1st failure: the base stays open (a 3 s wait only)
	local cancel = holdFor(t, sim, thief, victim, 3, 1.5)
	t.eq(cancel and cancel.Reason, "released", "1st: «released»")
	t.eq(cancel and cancel.BaseUntil, nil, "1st: no closed base")
	sim:Advance(FAIL[1] + 0.3)
	t.eq(shownOn(sim, thief, victim), "{1,2,3,4}", "1st: after his 3 s the base is shown")

	-- the 2nd failure on the same base: «wary» for BaseWait
	cancel = holdFor(t, sim, thief, victim, 2, 1.5)
	t.eq(cancel and cancel.BaseReason, "wary", "2nd: BaseReason «wary»")
	local untilT = cancel and cancel.BaseUntil
	t.near(untilT, serverTime(sim) + LIMITS.BaseWait, 0.6, "BaseUntil = now + BaseWait")
	local u = bar(sim, thief)
	sim:Advance(SPEC.FailTime + 0.3)
	intoCourt(sim, thief, victim, 3)
	local wait = thief:GetAttribute("StealCooldownUntil") - serverTime(sim)
	t.ok(wait > 0, "his own 10 s wait still runs")
	-- here both apply: the court names the one that ends later — the base's, the true time here
	-- (F-11: «⏳ 0:07» first and then «👀 0:50» moved the goalposts)
	courtSays(
		t,
		u,
		"wary",
		untilT - serverTime(sim),
		ICONS.Wary,
		"the base's wait at once (the later of his 10 s and the base's: F-11)"
	)
	t.eq((baseReason(sim, thief, victim)), "wary", "… its reason «wary» from the first moment")
	t.eq(shownOn(sim, thief, other), "{}", "… every base hidden meanwhile (his own wait)")
	sim:Advance(wait + 0.5)
	t.eq(shownOn(sim, thief, other), "{1,2,3,4}", "his wait over: another base shown")
	t.eq(shownOn(sim, thief, victim), "{}", "… this one still closed")
	t.eq((baseReason(sim, thief, victim)), "wary", "its reason «wary»")
	sim:Advance(SPEC.HintEvery + 0.2)
	courtSays(t, u, "wary", untilT - serverTime(sim), ICONS.Wary, "the base's own wait")

	-- a rejoin: the new client knows nothing of it — the server's Denied with Until hides it again
	sim:RemovePlayer(thief)
	sim:Advance(3, LONG)
	thief = S.player(t, sim, 312, { keep = true, client = true, device = "phone" })
	sim:Advance(1.5)
	t.ok(untilT - serverTime(sim) > 10, "still well inside BaseWait after the rejoin")
	t.eq(shownOn(sim, thief, victim), "{1,2,3,4}", "the new client shows «Украсть» there (A2-03's gap)")
	local d = S.denied(t, sim, thief, victim, 3, { holdOpts = {} })
	t.eq(d and d.Reason, "wary", "the server refuses «wary»")
	t.near(d and d.Until, untilT, 1, "… with Until = BaseUntil")
	sim:Advance(0.2)
	t.eq(shownOn(sim, thief, victim), "{}", "the Denied hid every «Украсть» of that base")
	t.eq((baseReason(sim, thief, victim)), "wary", "… «wary» on the client too")
	t.eq(shownOn(sim, thief, other), "{1,2,3,4}", "another base untouched")
	u = bar(sim, thief)
	sim:Advance(SPEC.DeniedHint + SPEC.HintEvery + 0.3)
	courtSays(t, u, "wary", untilT - serverTime(sim), ICONS.Wary, "after the rejoin")

	-- back at BaseUntil
	sim:Advance(untilT - serverTime(sim) + 0.4, LONG)
	t.eq(shownOn(sim, thief, victim), "{1,2,3,4}", "back at BaseUntil")
	sim:AssertNoErrors({ warnings = true })
end

tests["a Denied with Until for the other waits: «new» hides that display, «cooldown» every base, «shield» the whole base — each until Until; a newer write of its attribute lifts it"] = function(
	t
)
	local sim = S.boot(t)
	local victim = S.player(t, sim, 321, { tank = VICTIM })
	local thief = S.player(t, sim, 322, { tank = THIEF, client = true, device = "desktop" })
	local other = S.player(t, sim, 323, { tank = VICTIM })
	sim:Advance(1.5)
	local remote = sim:Find("ReplicatedStorage.Remotes.StealEvent")
	local index = S.baseOf(sim, victim):GetAttribute("BaseIndex")
	local function deny(reason: string, slot: number, seconds: number)
		remote:FireClient(thief, "Denied", {
			Reason = reason,
			Text = S.shared(sim, "StealRules").DeniedText(reason, seconds),
			Quiet = true,
			BaseIndex = index,
			Slot = slot,
			Until = serverTime(sim) + seconds,
		})
		sim:Advance(0.2)
	end
	t.eq(shownOn(sim, thief, victim), "{1,2,3,4}", "before")

	deny("new", 2, 3)
	t.eq(shownOn(sim, thief, victim), "{1,3,4}", "«new»: only that display hidden")
	sim:Advance(3)
	t.eq(shownOn(sim, thief, victim), "{1,2,3,4}", "… back at Until")

	deny("cooldown", 2, 3)
	t.eq(shownOn(sim, thief, victim), "{}", "«cooldown»: every base hidden")
	t.eq(shownOn(sim, thief, other), "{}", "… another one too")
	thief:SetAttribute("StealCooldownUntil", 0) -- (the server writes his wait: newer than the refusal)
	sim:Advance(0.2)
	t.eq(shownOn(sim, thief, other), "{1,2,3,4}", "a newer StealCooldownUntil lifts it")

	deny("shield", 1, 3)
	t.eq(shownOn(sim, thief, victim), "{}", "«shield»: the whole base hidden")
	t.eq((baseReason(sim, thief, victim)), "shield", "… for the shield")
	t.eq(shownOn(sim, thief, other), "{1,2,3,4}", "… another base shown")
	sim:Advance(3)
	t.eq(shownOn(sim, thief, victim), "{1,2,3,4}", "… back at Until")
	sim:AssertNoErrors({ warnings = true })
end

tests["the protection warning (F-03): a fresh newbie reads «Начнёшь красть — твоя защита погаснет» first, then the how-to; a tap keeps the protection and the warning does not come back; a real hold ends it"] = function(
	t
)
	local sim = S.boot(t)
	local defence = S.service(sim, "DefenceService")
	local victim = S.player(t, sim, 331, { tank = VICTIM })
	local kid = S.player(t, sim, 332, { fresh = true, protected = true, client = true, device = "phone" })
	sim:Teleport(victim, S.exitPoint(S.baseOf(sim, kid), "gate"))
	sim:Advance(3)
	t.eq(defence:IsProtected(kid), "newbie", "a fresh save: the newbie protection")
	local u = bar(sim, kid)
	intoCourt(sim, kid, victim, 3)
	t.ok(u.bar.Visible and u.line.Visible, "a hint on his first entry")
	t.eq(u.line.Text, TEXTS.Hint.Protected, "the warning first — before his first hold")
	t.eq(u.icon.Text, ICONS.Shield, "… with 🛡️")
	sim:Advance(BAR.HintTime + SPEC.HintEvery + 0.2)
	t.eq(u.line.Text, TEXTS.Hint.Touch, "then the how-to (touch)")
	sim:Advance(BAR.HintTime + SPEC.HintEvery + 0.2)
	t.ok(not u.bar.Visible, "both gone after their time")

	-- a curious tap: the protection stays (the server), the warning does not come back for it
	local cancel = holdFor(t, sim, kid, victim, 3, 0.3)
	t.eq(cancel and cancel.Reason, "released", "the tap: «released»")
	t.eq(defence:IsProtected(kid), "newbie", "the tap kept his protection")
	sim:Advance(SPEC.DeniedHint + 0.3)
	S.moveTo(sim, kid, S.exitPoint(S.baseOf(sim, victim), "gate"))
	sim:Advance(SPEC.HintEvery + 0.2)
	intoCourt(sim, kid, victim, 3)
	t.ok(not (u.bar.Visible and u.line.Text == TEXTS.Hint.Protected), "no second warning for the same protection")

	-- a real hold: past the tap window the server ends the protection
	sim:Advance(1 / LIMITS.StartRate)
	local hold, prompt = S.hold(t, sim, kid, victim, 3)
	t.ok(hold.active, "the real hold")
	sim:Advance(1.5)
	t.eq(defence:IsProtected(kid), nil, "past the tap window his protection is gone")
	if hold.active then
		sim:ReleasePrompt(kid, prompt)
	end
	sim:Advance(0.3)
	sim:AssertNoErrors({ warnings = true })
end

return tests
