--[[
	Stage 4 END-TO-END kit — the helpers shared by tests/stage4_e2e*.test.luau (docs/stage4_design.md
	§7.7, Wave 3 E). Not a test file itself (tools/run_tests.luau only runs tests/*.test.luau).
	Everything of tests/stage4_kit.luau (and through it tests/stage3_e2e_kit.luau) is here too: E
	falls back to Kit.

	Everything runs for real: the built Place1.rbxl in RbxSim, every server service (StealService,
	DefenceService, TankService, DataService with the sim DataStore …) and the REAL clients of 2–3
	players (TheftController, AlertController, DefenceController, TheftWorldController, the fishing
	and tank controllers). The players only do what a player can: stand, walk (Humanoid:MoveTo at
	the WalkSpeed the server gives them — the carry's 13.6 and the dog's 6.8 are felt, not faked),
	hold «Украсть» like a stock prompt (sim:BeginHold reads the prompt as THAT client sees it: a
	locally hidden prompt cannot be held), tap a button (sim:Click), read the screen. The only
	stage setters are the saves poked before a join (Kit.seed) and, where a case says so, the
	forced next catch (FishingService.RollFishForTest).

	  E.VICTIM_TANK / E.THIEF_TANK  the §7.7 tanks: the victim's 4 fish with a Legendary (SharkPup,
	                                slot 3) aged 200 s; the thief's 3 weaker ones
	  E.trio(t, opts?)              a server and the players of a case: opts.victim / thief /
	                                bystander = { device, tank, money, upgrades, lock } (false — no
	                                such player; defaults: tablet victim, phone thief, desktop
	                                bystander), opts.latency, opts.patches; waits for every HUD
	                                («ЗАЩИТА» popped in) and — unless opts.protected — for the join
	                                protection of every base to run out (a quick rejoin: 20 s; the
	                                ShieldChip goes); returns { sim, victim, thief, bystander }
	  E.ui(sim, p)                  the widgets a player looks at (TheftBar, TheftTitle, TheftAlert,
	                                ShieldChip, «ЗАЩИТА», «САДОК», «ДОМОЙ», Toasts, the sheet)
	  E.mode / E.alert / E.defenceStats / E.world(sim, p, base)  the controllers' test views
	  E.toCourt(t, sim, thief, owner, slot)  from outside the owner's gate the thief walks up to the
	                                display and faces it; returns its StealPrompt
	  E.seen(sim, p, prompt)        the prompt's MaxActivationDistance as that client sees it
	  E.walkOut(sim, p, owner, exit?) Humanoid:MoveTo out of the owner's plot (gate by default),
	                                leg by leg, until the theft is over or he is outside
	  E.phaseLog(p)                 the thief's Stealing changes from now on: { { time, value } }
	  E.writeLog(sim)               every DataStore write that LANDS from now on: { key, time,
	                                uids = { [uid] = true }, origins = { [origin] = row } }
	  E.toastLog(sim, p, seconds)   every toast text seen while stepping `seconds`
	  E.shieldTap(sim, p, where)    one tap on the visible ЩИТ: "plate" (the pill's on a phone, the
	                                plate's elsewhere) or "column" (the «ЩИТ!» button)
	  E.rodIn / E.toMinigame(t, sim, p)  the victim casts from his spot and hooks: the minigame
	  E.minigameAnswers(t, sim, p, what)  the minigame still answers (FishingState and FishingTap)
	  E.copies(sim, victimId, uid)  across all saved keys: rows of that fish (the victim's uid in his
	                                key, `<victimId>:<uid>` as an Origin anywhere)
]]

local roblox = require("@lune/roblox")

local Kit = require("./stage4_kit")

local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3

local E = setmetatable({}, { __index = Kit })

E.UI = Kit.config("UIConfig")
E.THEFT_UI = E.UI.Theft
E.ALERT = Kit.STEAL_TEXTS.Alert
E.RESULT = Kit.STEAL_TEXTS.Result
E.BANNER = Kit.STEAL_TEXTS.Banner
E.CANCEL = Kit.STEAL_TEXTS.Cancel
E.DENIED = Kit.STEAL_TEXTS.Denied
E.LIMITS = Kit.StealConfig.Limits
E.SHIELD = Kit.DefenceConfig.Shield
E.DOG = Kit.DefenceConfig.Dog
E.LOCK = Kit.DefenceConfig.Lock
E.BASE_HOLD = Kit.DefenceConfig.Lock.BaseHold

E.VICTIM_TANK = {
	{ Id = "Perch" },
	{ Id = "Perch" },
	{ Id = "SharkPup", Age = 200 },
	{ Id = "Crucian" },
}
E.THIEF_TANK = { { Id = "Crucian" }, { Id = "Crucian" }, { Id = "Perch" } }
E.BYSTANDER_TANK = { { Id = "Perch" }, { Id = "Crucian" } }

E.VICTIM, E.THIEF, E.BYSTANDER = 1, 2, 3

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

function E.module(sim: any, p: any, name: string): any
	return Kit.client(sim, p, name)
end

function E.call(sim: any, p: any, fn: () -> any): any
	return sim:Run(fn, p)
end

function E.serverNow(sim: any): number
	return sim.workspace:GetServerTimeNow()
end

function E.rodIn(container: any): any
	return Kit.rodIn(container)
end

--------------------------------------------------------------------------------
-- The players of a case
--------------------------------------------------------------------------------

local DEFAULTS = {
	victim = { id = 1, device = "tablet" },
	thief = { id = 2, device = "phone" },
	bystander = { id = 3, device = "desktop" },
}

local function hudReady(p: any): boolean
	local gui = p:FindFirstChild("PlayerGui")
	local hud = gui and gui:FindFirstChild("HUD")
	return hud ~= nil and hud.RightButtons.DefenceButton.Visible and hud.RightButtons.TankButton.Visible
end

function E.trio(t: any, opts: { [string]: any }?): { [string]: any }
	local o = opts or {}
	local sim = Kit.boot(t, { latency = o.latency, patches = o.patches })
	local out: { [string]: any } = { sim = sim }
	local order = { "victim", "thief", "bystander" }
	local specs = {}
	for _, role in order do
		local spec = o[role]
		if spec ~= false then
			local s = table.clone(DEFAULTS[role])
			for k, v in spec or {} do
				s[k] = v
			end
			s.tank = s.tank
				or (
					if role == "victim" then E.VICTIM_TANK elseif role == "thief" then E.THIEF_TANK else E.BYSTANDER_TANK
				)
			specs[role] = s
			Kit.seed(sim, s.id, { tank = s.tank, money = s.money or 0, upgrades = s.upgrades, lock = s.lock })
		end
	end
	for _, role in order do
		local s = specs[role]
		if s then
			out[role] = Kit.join(t, sim, s.id, s.device)
		end
	end
	t.ok(
		sim:WaitFor(function()
			for _, role in order do
				if out[role] and not hudReady(out[role]) then
					return false
				end
			end
			return true
		end, 15, Kit.COARSE),
		"every HUD is up («САДОК», «ЗАЩИТА»)"
	)
	if not o.protected then
		t.ok(
			sim:WaitFor(function()
				for _, role in order do
					local p = out[role]
					if p and Kit.baseOf(sim, p):GetAttribute("ProtectUntil") ~= nil then
						return false
					end
				end
				return true
			end, E.SHIELD.QuickRejoinProtect + E.SHIELD.JoinProtect + 2, Kit.COARSE),
			"the join protections ran out"
		)
		sim:Advance(1.2) -- (the ShieldChip pops out)
	end
	return out
end

--------------------------------------------------------------------------------
-- What a player sees
--------------------------------------------------------------------------------

function E.ui(sim: any, p: any): { [string]: any }
	local function find(path: string): any
		local found = sim:Gui(p, `HUD.{path}`)
		assert(found, `HUD.{path} not found`)
		return found
	end
	return {
		hud = find("TheftBar").Parent,
		bar = find("TheftBar"),
		barTitle = find("TheftBar.Title"),
		barReason = find("TheftBar.Reason"),
		barLine = find("TheftBar.Line"),
		fill = find("TheftBar.Bar.Fill"),
		dogChip = find("TheftBar.DogChip"),
		slam = find("TheftTitle"),
		slamTitle = find("TheftTitle.Title"),
		slamSub = find("TheftTitle.Sub"),
		alert = find("TheftAlert"),
		status = find("Status"),
		chip = find("Status.BaseBadge.ShieldChip"),
		chipLabel = find("Status.BaseBadge.ShieldChip.Label"),
		right = find("RightButtons"),
		defence = find("RightButtons.DefenceButton"),
		defenceCaption = find("RightButtons.DefenceButton.Caption"),
		tank = find("RightButtons.TankButton"),
		tankChip = find("RightButtons.TankButton.Count.Label"),
		home = find("RightButtons.HomeButton"),
		toasts = find("Toasts"),
		sheet = find("DefencePanel"),
		cards = find("DefencePanel.Panel.Cards"),
		action = find("Fishing.ActionArea.ActionButton"),
		minigame = find("Fishing.Minigame"),
		card = find("Fishing.CatchCard"),
	}
end

function E.mode(sim: any, p: any): string
	local controller = E.module(sim, p, "TheftController")
	return E.call(sim, p, function()
		return controller.Mode()
	end)
end

function E.alert(sim: any, p: any): { [string]: any }
	local controller = E.module(sim, p, "AlertController")
	return E.call(sim, p, function()
		return controller.Stats()
	end)
end

function E.defenceStats(sim: any, p: any): { [string]: any }
	local controller = E.module(sim, p, "DefenceController")
	return E.call(sim, p, function()
		return controller.Stats()
	end)
end

function E.world(sim: any, p: any, base: any): { [string]: any }?
	local controller = E.module(sim, p, "TheftWorldController")
	return E.call(sim, p, function()
		return controller.Get(base)
	end)
end

function E.worldStats(sim: any, p: any): { [string]: any }
	local controller = E.module(sim, p, "TheftWorldController")
	return E.call(sim, p, function()
		return controller.Stats()
	end)
end

-- The prompt's reach as this client sees it (TheftPrompts hides by a LOCAL 0).
function E.seen(sim: any, p: any, prompt: any): number
	return E.call(sim, p, function()
		return prompt.MaxActivationDistance
	end)
end

-- Every visible toast text right now.
function E.toastTexts(p: any): { string }
	local out = {}
	for _, toast in p.PlayerGui.HUD.Toasts:GetChildren() do
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

-- Every toast text seen while stepping `seconds` (they come and go).
function E.toastLog(sim: any, p: any, seconds: number): { string }
	local seen, list = {}, {}
	local t0 = sim:Time()
	repeat
		for _, s in E.toastTexts(p) do
			if not seen[s] then
				seen[s] = true
				table.insert(list, s)
			end
		end
		sim:Advance(0.1)
	until sim:Time() - t0 >= seconds
	return list
end

-- Every toast text that comes up from now on (HUD.Toasts.ChildAdded: the texts of the new toast's
-- labels), in order; the list grows while the test steps.
function E.toastWatch(p: any): { string }
	local list = {}
	p.PlayerGui.HUD.Toasts.ChildAdded:Connect(function(toast)
		for _, item in toast:GetDescendants() do
			if item:IsA("TextLabel") and item.Text ~= "" then
				table.insert(list, item.Text)
			end
		end
	end)
	return list
end

function E.has(list: { string }, text: string): boolean
	for _, s in list do
		if string.find(s, text, 1, true) then
			return true
		end
	end
	return false
end

function E.list(list: { string }): string
	return "«" .. table.concat(list, "», «") .. "»"
end

--------------------------------------------------------------------------------
-- Moving like a player
--------------------------------------------------------------------------------

-- Outside the owner's gate, then a walk up to the display; faces it. Returns its StealPrompt.
function E.toCourt(t: any, sim: any, thief: any, owner: any, slot: number): any
	local base = Kit.baseOf(sim, owner)
	local prompt = Kit.stealPrompt(sim, owner, slot)
	t.ok(prompt, `Slot_{slot} of {owner.Name} has a StealPrompt`)
	sim:Teleport(thief, Kit.exitPoint(base, "gate") + Vector3.new(0, 0, 0))
	sim:Advance(0.2)
	local attachment = prompt.Parent
	local pedestal = attachment.Parent
	local at = (pedestal.CFrame * attachment.CFrame).Position
	local out = at - pedestal.CFrame.Position
	local dir = Vector3.new(out.X, 0, out.Z)
	dir = if dir.Magnitude > 1e-3 then dir.Unit else Vector3.new(0, 0, -1)
	local spot = at + dir * 2
	t.ok(Kit.walkTo(sim, thief, spot), `{thief.Name} walks up to Slot_{slot}`)
	Kit.standAt(sim, thief, prompt)
	return prompt
end

-- Humanoid:MoveTo legs out of the owner's plot (at the WalkSpeed the server sets), until the theft
-- is over or he stands outside. Returns true when the theft ended on the way.
function E.walkOut(sim: any, p: any, owner: any, exit: string?): boolean
	local base = Kit.baseOf(sim, owner)
	local goal = Kit.exitPoint(base, exit or "gate")
	local root = p.Character.HumanoidRootPart
	local target = Vector3.new(goal.X, root.Position.Y, goal.Z)
	for _ = 1, 30 do
		if p:GetAttribute("Stealing") == nil then
			return true
		end
		local here = root.Position
		local flat = Vector3.new(target.X - here.X, 0, target.Z - here.Z)
		if flat.Magnitude < 0.2 then
			break
		end
		local leg = if flat.Magnitude > 40 then here + flat.Unit * 40 else target
		sim:WalkTo(p, leg, 9)
	end
	sim:Advance(0.2)
	return p:GetAttribute("Stealing") == nil
end

-- The thief's Stealing changes from now on (server attribute): { { time, value } }.
function E.phaseLog(sim: any, p: any): { any }
	local log = {}
	p:GetAttributeChangedSignal("Stealing"):Connect(function()
		table.insert(log, { time = sim:Time(), value = p:GetAttribute("Stealing") })
	end)
	return log
end

function E.phaseAt(log: { any }, value: string?): number?
	for _, e in log do
		if e.value == value then
			return e.time
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- The victim's buttons
--------------------------------------------------------------------------------

-- The ЩИТ the victim taps: "plate" (the pill's on a phone, the plate's elsewhere) or "column".
function E.shieldButton(p: any, where: string): any
	local hud = p.PlayerGui.HUD
	if where == "column" then
		return hud.RightButtons.DefenceButton
	end
	local root = hud.TheftAlert
	if root.Compact.Visible then
		return root.Compact.Shield
	end
	return root.Buttons.Shield
end

function E.shieldTap(sim: any, p: any, where: string)
	sim:Click(p, E.shieldButton(p, where))
	sim:Advance(Kit.FRAME)
end

--------------------------------------------------------------------------------
-- Fishing (the victim is busy)
--------------------------------------------------------------------------------

-- The victim casts from his FishingSpot and hooks the bite: FishingState "Minigame".
function E.toMinigame(t: any, sim: any, p: any): boolean
	local base = Kit.baseOf(sim, p)
	local spot = base.FishingSpot
	local look = base:GetPivot().LookVector
	local fwd = Vector3.new(look.X, 0, look.Z).Unit
	local origin = spot.Position + Vector3.new(0, spot.Size.Y / 2, 0)
	local character = p.Character
	local root = character.HumanoidRootPart
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local at = origin + Vector3.new(0, humanoid.HipHeight + root.Size.Y / 2, 0)
	sim:Teleport(p, CFrame.lookAt(at, at + fwd))
	local rod = Kit.rodIn(p:FindFirstChildOfClass("Backpack"))
	if rod then
		sim:EquipTool(p, rod)
	end
	sim:Advance(0.4)
	local function events(): { any }
		return sim:ClientEventsFor(p, "FishingState")
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
	t.ok(bite, `{p.Name}: the bite`)
	sim:Advance(0.2)
	count = #events()
	sim:FireServer(p, "FishingHook")
	local hooked = sim:WaitFor(function()
		return events()[count + 1]
	end, 1, 1 / 60)
	t.ok(hooked and hooked.args[1] == "Minigame", `{p.Name}: hooked — the minigame`)
	sim:Advance(0.3)
	return hooked ~= nil and hooked.args[1] == "Minigame"
end

function E.lastFishingState(sim: any, p: any): string?
	local list = sim:ClientEventsFor(p, "FishingState")
	local last = list[#list]
	return last and last.args[1]
end

-- The minigame still is the state and «ЛОВИ!» still sends FishingTap.
function E.minigameAnswers(t: any, sim: any, p: any, what: string)
	t.eq(E.lastFishingState(sim, p), "Minigame", `{what}: no FishingState change (the minigame goes on)`)
	t.ok(p.PlayerGui.HUD.Fishing.Minigame.Visible, `{what}: the minigame stays on screen`)
	local before = #sim:ServerEventsFor(p, "FishingTap")
	sim:Advance(Kit.FishingConfig.TapInterval + 0.05)
	sim:Click(p, p.PlayerGui.HUD.Fishing.ActionArea.ActionButton)
	sim:Advance(Kit.FRAME)
	t.eq(#sim:ServerEventsFor(p, "FishingTap"), before + 1, `{what}: «ЛОВИ!» still sends FishingTap`)
end

--------------------------------------------------------------------------------
-- Saves
--------------------------------------------------------------------------------

local function decodeRows(json: string): ({ [string]: boolean }, { [string]: any })
	local serde = require("@lune/serde")
	local ok, value = pcall(serde.decode, "json", json)
	local uids, origins = {}, {}
	if ok and type(value) == "table" and type(value.Tank) == "table" then
		for _, row in value.Tank do
			if type(row) == "table" then
				if type(row.Uid) == "string" then
					uids[row.Uid] = true
				end
				if type(row.Origin) == "string" then
					origins[row.Origin] = row
				end
			end
		end
	end
	return uids, origins
end

-- Every DataStore write that LANDS from now on (the sim's _write: after the latency, when the
-- value is in the store): { key, time, uids, origins }.
function E.writeLog(sim: any): { any }
	local log = {}
	local store = sim.DataStore
	local original = store._write
	store._write = function(self: any, id: string, key: string, json: string, ...: any): any
		local uids, origins = decodeRows(json)
		table.insert(log, { key = key, time = sim:Time(), uids = uids, origins = origins })
		return original(self, id, key, json, ...)
	end
	return log
end

-- Rows of one fish across every saved key: the victim's uid in his key, its Origin anywhere.
function E.copies(sim: any, victimId: number, uid: string): ({ string }, { any })
	local where, rows = {}, {}
	local origin = `{victimId}:{uid}`
	for _, key in sim.DataStore:Keys(Kit.STORE) do
		local value = sim.DataStore:Peek(Kit.STORE, key)
		if type(value) == "table" and type(value.Tank) == "table" then
			for _, row in value.Tank do
				if (key == Kit.key(victimId) and row.Uid == uid and row.Origin == nil) or row.Origin == origin then
					table.insert(where, key)
					table.insert(rows, row)
				end
			end
		end
	end
	return where, rows
end

-- The server's view of a slot's fish age now (GrowFrom attribute).
function E.ageOf(sim: any, owner: any, slot: number): number?
	local grow = Kit.slot(sim, owner, slot):GetAttribute("GrowFrom")
	return if type(grow) == "number" then E.serverNow(sim) - grow else nil
end

-- The thief's display holding the fish of this Origin (or nil).
function E.slotByOrigin(sim: any, thief: any, origin: string): (number?, any)
	local data = Kit.service(sim, "DataService"):Get(thief)
	for _, row in if data then data.Tank else {} do
		if row.Origin == origin then
			return row.Slot, row
		end
	end
	return nil, nil
end

return E
