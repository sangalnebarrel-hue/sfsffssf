--[[
	Stage 3 end-to-end kit — the helpers shared by tests/stage3_e2e*.test.luau (design §7.6). It is
	not a test file itself: tools/run_tests.luau only runs tests/*.test.luau.

	Everything runs for real: the built Place1.rbxl in RbxSim, every server service with real
	persistence (the sim DataStore), every client controller of every player. The helpers only do
	what a player can do — stand somewhere, walk, take the rod, tap a button, hold a prompt, read
	the screen — or what a test has to do to set the stage: force the next fish
	(FishingService.RollFishForTest, the one server test hook), poke a save before a join,
	restart a server on the same DataStore, log the server's money changes by reason (a listener
	on EconomyService.MoneyChanged — it changes nothing).

	  Kit.boot(t, opts?)            a server: opts.patches edit ModuleScript sources before it
	                                starts, opts.latency (remoteLatency), opts.dataStore / epoch /
	                                seed (a restart), opts.before(sim) (e.g. DataStore:SetEnabled)
	  Kit.restart(t, old, gap, opts?) a NEW server on the old server's DataStore: the clock
	                                `gap` s later, a new seed (a new server token, design R10)
	  Kit.join(t, sim, id, device, opts?) a real client; waits for the base, the character, the
	                                rod and the HUD, and (unless opts.loading) the loaded data
	  Kit.hud(sim, p)               the widgets a player looks at (catch card, Wallet, «САДОК»,
	                                the tank panel, toasts)
	  Kit.goFish(t, sim, p)         onto the own FishingSpot, the rod from the Backpack in hand
	  Kit.forceFish(sim, id, kg?, mutation?) the next roll gives this fish (returns its FishData)
	  Kit.Fisher / Kit.play         the careful player bot of stage2_e2e: reads only its HUD
	  Kit.catch(t, sim, p, hud, what) cast → bite → hook → minigame → the card; returns the
	                                "Caught" payload { Fish, Total, Tank }
	  Kit.landed(t, sim, p, hud, what) waits until the card is gone and the fish has flown in
	                                (CounterHold cleared), plus the arrival juice
	  Kit.openPanel / Kit.card / Kit.sell  tap «САДОК», a card, a two-tap sale («ПРОДАТЬ?» →
	                                a pause ≥ ConfirmArm → again); returns TankEvent "Sold" / "Denied"
	  Kit.walkTo(sim, p, pos)       walks (Humanoid:MoveTo legs ≤ 100 studs: MoveTo times out at 8 s)
	  Kit.moneyLog(sim) / Kit.earned(log, p, reason)  the server's money changes by reason
	  Kit.toasts(hud)               every toast text shown from now on (HUD.Toasts.ChildAdded)
	  Kit.pokeSave / Kit.savedFish / Kit.template     a save written before the player joins
	  Kit.peek, Kit.writes, Kit.assertGaps, Kit.ledgerHolds, Kit.takeWarnings, Kit.sizesZero
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3

local Kit = {}

Kit.PLACE = "Place1.rbxl"
Kit.FRAME = 1 / 60
Kit.COARSE = 0.05
Kit.EPOCH = 1700000000 -- RbxSim's default os.time() at t = 0
Kit.STORE = "PlayerData_Studio" -- the sim reports Studio (DataService.StoreName)

-- Pure config modules straight from src/ (the same values the game uses).
function Kit.config(name: string): any
	local path = `src/ReplicatedStorage/Shared/Config/{name}.luau`
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum },
		injectGlobals = true,
	})
	return chunk()
end

local DataConfig = Kit.config("DataConfig")
local EconomyConfig = Kit.config("EconomyConfig")
local FishConfig = Kit.config("FishConfig")
local FishingConfig = Kit.config("FishingConfig")
local RodConfig = Kit.config("RodConfig")
local TankConfig = Kit.config("TankConfig")
local UIConfig = Kit.config("UIConfig")
Kit.DataConfig, Kit.EconomyConfig, Kit.FishConfig = DataConfig, EconomyConfig, FishConfig
Kit.FishingConfig, Kit.TankConfig, Kit.UIConfig = FishingConfig, TankConfig, UIConfig
Kit.TEXTS = TankConfig.Texts
Kit.GAP = DataConfig.MinWriteGap + DataConfig.GapEpsilon

-- The longest a catch card stays up by itself, plus the 🐟 flying into «САДОК».
Kit.CARD_GONE = UIConfig.CatchCardTime.Mythic + 1.6

-- What the action button says (FishingController LOOKS).
local CAPTION_CAST = "ЗАБРОСИТЬ"
local CAPTION_WAIT = "ЖДЁМ…"
local CAPTION_WATER = "ЖДИ КЛЁВА…"
local CAPTION_HOOK = "ПОДСЕЧЬ!"
local PIP_DONE = Color3.fromRGB(64, 200, 96)
-- How the bot plays (stage2_e2e's careful player).
local REACTION = 0.25
local PATIENCE = 0.6
local OUTCOME_WAIT = FishingConfig.LeapTime + 2.2
local CONTEXT_HINTS = {
	["Жми «Забросить»"] = true,
	[FishingConfig.Texts.Denied.far] = true,
	["Возьми удочку — кнопка справа"] = true,
}

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

function Kit.startsWith(text: string, prefix: string): boolean
	return string.sub(text, 1, #prefix) == prefix
end

function Kit.colorNear(a: any, b: any, eps: number?): boolean
	local e = eps or 0.01
	return math.abs(a.R - b.R) <= e and math.abs(a.G - b.G) <= e and math.abs(a.B - b.B) <= e
end

-- The Top colour of a sim surface (Theme.sim / UiFx.setCandy: its Face's gradient).
function Kit.faceTop(root: any): any
	local face = root:FindFirstChild(root:GetAttribute("CandyFace") or "Face")
	return face.Fill.Color.Keypoints[1].Value
end

function Kit.fishDef(id: string): any
	for _, fish in FishConfig.Fish do
		if fish.Id == id then
			return fish
		end
	end
	error(`no fish {id}`)
end

-- TextUtil.fill for the tests' own expectations (the same {field} templates as the configs).
function Kit.fill(template: string, values: { [string]: any }): string
	return (
		string.gsub(template, "{(%w+)}", function(key: string): string
			local value = values[key]
			return if value == nil then "{" .. key .. "}" else tostring(value)
		end)
	)
end

--------------------------------------------------------------------------------
-- Servers
--------------------------------------------------------------------------------

type Patch = { path: string, from: string, to: string }

function Kit.boot(t: any, opts: { [string]: any }?): any
	local o = opts or {}
	local sim = t.sim({
		place = Kit.PLACE,
		remoteLatency = o.latency or 0,
		dataStore = o.dataStore,
		epoch = o.epoch,
		seed = o.seed or 1,
	})
	for _, patch: Patch in o.patches or {} do
		local module = sim:Find(patch.path)
		t.ok(module, `module {patch.path} exists`)
		local source = module.Source
		local start = string.find(source, patch.from, 1, true)
		t.ok(start, `patch anchor «{patch.from}» found in {patch.path}`)
		module.Source = string.sub(source, 1, start - 1) .. patch.to .. string.sub(source, start + #patch.from)
	end
	if o.before then
		o.before(sim)
	end
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

-- A new server on the old server's DataStore, `gap` seconds later, with a new seed (token).
function Kit.restart(t: any, old: any, gap: number, opts: { [string]: any }?): any
	local o = table.clone(opts or {})
	o.dataStore = old.DataStore:Snapshot()
	o.epoch = Kit.EPOCH + math.floor(old:Time()) + gap
	o.seed = o.seed or 2
	return Kit.boot(t, o)
end

function Kit.service(sim: any, name: string): any
	return sim:Require(sim:Find(`ServerScriptService.Services.{name}`))
end

function Kit.shared(sim: any, name: string, who: any?): any
	return sim:Require(sim:Find(`ReplicatedStorage.Shared.{name}`), who)
end

function Kit.client(sim: any, p: any, name: string): any
	local module = sim:Find(`Controllers.{name}`, p:FindFirstChildOfClass("PlayerScripts"))
	assert(module, `{name} not found in PlayerScripts`)
	return sim:Require(module, p)
end

--------------------------------------------------------------------------------
-- Players
--------------------------------------------------------------------------------

local function rodIn(container: any): any
	if not container then
		return nil
	end
	for _, item in container:GetChildren() do
		if item:IsA("Tool") and item:GetAttribute("RodId") ~= nil then
			return item
		end
	end
	return nil
end
Kit.rodIn = rodIn

-- A real client. opts.loading: do not wait for the data (DataMode may still be "Loading").
function Kit.join(t: any, sim: any, id: number, device: string, opts: { [string]: any }?): any
	local o = opts or {}
	local p = sim:AddPlayer({ UserId = id, Name = `Keeper{id}`, DisplayName = `Рыбак{id}`, device = device })
	local ready = sim:WaitFor(function()
		local index = p:GetAttribute("BaseIndex")
		return typeof(index) == "number"
			and index > 0
			and p.Character ~= nil
			and rodIn(p:FindFirstChildOfClass("Backpack")) ~= nil
			and sim:Gui(p, "HUD.Fishing.ActionArea.ActionButton") ~= nil
			and (o.loading or p:GetAttribute("DataMode") ~= "Loading")
	end, o.timeout or 10)
	t.ok(ready, `{p.Name}: a base, a character, the rod, the HUD{if o.loading then "" else " and the data"}`)
	sim:Advance(0.5)
	return p
end

function Kit.hud(sim: any, p: any): any
	local function find(path: string): any
		local found = sim:Gui(p, `HUD.{path}`)
		assert(found, `HUD.{path} not found`)
		return found
	end
	local pips = {}
	for i = 1, 5 do
		table.insert(pips, find(`Fishing.Minigame.Pips.Pip{i}`))
	end
	return {
		screen = find("Fishing").Parent,
		action = find("Fishing.ActionArea.ActionButton"),
		caption = find("Fishing.ActionArea.ActionButton.Caption"),
		stop = find("Fishing.ActionArea.StopButton"),
		bite = find("Fishing.BiteAlert"),
		minigame = find("Fishing.Minigame"),
		needle = find("Fishing.Minigame.Track.Needle"),
		zone = find("Fishing.Minigame.Track.Zone"),
		pips = pips,
		hint = find("Fishing.Hint"),
		card = find("Fishing.CatchCard"),
		cardName = find("Fishing.CatchCard.NameLabel"),
		cardInfo = find("Fishing.CatchCard.InfoLabel"),
		stamp = find("Fishing.CatchCard.TankStamp"),
		stampLabel = find("Fishing.CatchCard.TankStamp.Label"),
		wallet = find("Status.Wallet"),
		money = find("Status.Wallet.Money.Label"),
		rate = find("Status.Wallet.Rate"),
		tank = find("RightButtons.TankButton"),
		tankChip = find("RightButtons.TankButton.Count.Label"),
		badge = find("RightButtons.TankButton.Badge"),
		home = find("RightButtons.HomeButton"),
		panel = find("TankPanel"),
		header = find("TankPanel.Panel.Header"),
		cards = find("TankPanel.Panel.Cards"),
		close = find("TankPanel.Panel.Close"),
		toasts = find("Toasts"),
	}
end

function Kit.baseOf(sim: any, p: any): any
	local index = p:GetAttribute("BaseIndex")
	assert(typeof(index) == "number" and index > 0, `{p.Name} has a base`)
	return sim.workspace.Bases:FindFirstChild(`Base_{index}`)
end

function Kit.slot(sim: any, p: any, index: number): any
	return Kit.baseOf(sim, p).Tank.Slots:FindFirstChild(`Slot_{index}`)
end

function Kit.leader(p: any): (number, number)
	local stats = p:FindFirstChild("leaderstats")
	return stats[EconomyConfig.Leaderstats.Money].Value, stats[EconomyConfig.Leaderstats.Income].Value
end

-- Onto the own FishingSpot, the rod from the Backpack into the hand.
function Kit.goFish(t: any, sim: any, p: any)
	local spot = Kit.baseOf(sim, p).FishingSpot
	sim:Teleport(p, spot.Position + Vector3.new(0, 3, 0))
	local rod = rodIn(p:FindFirstChildOfClass("Backpack")) or rodIn(p.Character)
	t.ok(rod, `{p.Name}: the rod`)
	if rod.Parent ~= p.Character then
		sim:EquipTool(p, rod)
	end
	sim:Advance(0.3)
end

-- Walks there in Humanoid:MoveTo legs (each ≤ 100 studs: MoveTo gives up after 8 s).
function Kit.walkTo(sim: any, p: any, goal: any): boolean
	local root = p.Character.HumanoidRootPart
	local target = Vector3.new(goal.X, root.Position.Y, goal.Z)
	for _ = 1, 20 do
		local here = root.Position
		local flat = Vector3.new(target.X - here.X, 0, target.Z - here.Z)
		if flat.Magnitude < 0.2 then
			return true
		end
		local leg = if flat.Magnitude > 100 then here + flat.Unit * 100 else target
		sim:WalkTo(p, leg, 9)
	end
	return false
end

-- Test-only server hook: every roll gives this fish (its price from FishingRules.Price).
function Kit.forceFish(sim: any, id: string, kg: number?, mutation: string?): any
	local rules = Kit.shared(sim, "FishingRules")
	local def = Kit.fishDef(id)
	local weight = kg or def.MinKg
	local value, income = rules.Price(id, weight, mutation)
	local fish = { Id = id, Rarity = def.Rarity, Kg = weight, Mutation = mutation, Value = value, Income = income }
	Kit.service(sim, "FishingService").RollFishForTest = function()
		return table.clone(fish)
	end
	return fish
end

-- The price and income FishingRules gives a fish (Value ×1, Income10 tenths).
function Kit.priceOf(sim: any, id: string, kg: number, mutation: string?): (number, number)
	local rules = Kit.shared(sim, "FishingRules")
	local value, income = rules.Price(id, kg, mutation)
	return value, Kit.shared(sim, "TankRules").Income10(income)
end

--------------------------------------------------------------------------------
-- The player bot (stage2_e2e's careful player): looks at its HUD once per frame
--------------------------------------------------------------------------------

local Fisher = {}
Fisher.__index = Fisher
Kit.Fisher = Fisher

function Fisher.new(sim: any, player: any, hud: any): any
	return setmetatable({
		sim = sim,
		player = player,
		hud = hud,
		stage = "idle", -- idle → waiting → bite → hooked → reeling → caught | lost
		taps = 0,
		pending = nil,
		lastZone = nil,
		trace = {},
	}, Fisher)
end

function Fisher:press()
	self.sim:Click(self.player, self.hud.action)
end

function Fisher:caption(): string
	return self.hud.caption.Text
end

function Fisher:done(): boolean
	return self.stage == "caught" or self.stage == "lost"
end

function Fisher:note(text: string)
	table.insert(self.trace, string.format("%.3f %s", self.sim:Time(), text))
	if #self.trace > 30 then
		table.remove(self.trace, 1)
	end
end

function Fisher:describe(): string
	return `{self.player.Name}: stage={self.stage} taps={self.taps}\n  ` .. table.concat(self.trace, "\n  ")
end

function Fisher:cast()
	self.stage = "waiting"
	self:note(`cast («{self:caption()}»)`)
	self:press()
end

function Fisher:hits(): number
	local count = 0
	for _, pip in self.hud.pips do
		if pip.Visible and Kit.colorNear(pip.BackgroundColor3, PIP_DONE) then
			count += 1
		end
	end
	return count
end

-- One minigame frame: one tap when the whole needle is inside the zone, then wait for the answer.
function Fisher:play(now: number)
	local hud = self.hud
	local needle = hud.needle.Position.X.Scale
	local needleHalf = hud.needle.Size.X.Scale / 2
	local zone = hud.zone.Position.X.Scale
	local width = hud.zone.Size.X.Scale
	local moving = self.lastZone ~= nil and math.abs(zone - self.lastZone) > 1e-6
	self.lastZone = zone
	local pending = self.pending
	if pending and (math.abs(zone - pending.zone) > 1e-6 or now - pending.at >= PATIENCE) then
		self.pending = nil
	end
	if self.pending or moving then
		return
	end
	if math.abs(needle - zone) + needleHalf <= width / 2 then
		self.taps += 1
		self.pending = { at = now, zone = zone }
		self:note("TAP")
		self:press()
	end
end

function Fisher:look()
	local hud = self.hud
	local now = self.sim:Time()
	if self.stage == "idle" or self:done() then
		return
	end
	local lineIn = not hud.stop.Visible and not hud.bite.Visible and self.stage ~= "waiting"
	if (Kit.startsWith(self:caption(), CAPTION_CAST) or hud.card.Visible or lineIn) and not hud.minigame.Visible then
		self.idleAt = self.idleAt or now
		local eventHint = hud.hint.Visible and not CONTEXT_HINTS[hud.hint.Text]
		local missGhost = hud.minigame.Parent:FindFirstChild("FxMinigameMiss") ~= nil
		if hud.card.Visible or eventHint or missGhost or now - self.idleAt >= OUTCOME_WAIT then
			self.stage = if hud.card.Visible then "caught" else "lost"
			self.endHint = if hud.hint.Visible then hud.hint.Text else nil
			self:note(`end: {self.stage}`)
		end
		return
	end
	self.idleAt = nil
	if self.stage == "waiting" then
		if hud.bite.Visible and Kit.startsWith(self:caption(), CAPTION_HOOK) then
			self.stage = "bite"
			self.biteAt = now
			self:note("bite seen")
		end
	elseif self.stage == "bite" then
		if now - self.biteAt >= REACTION - 1e-9 then
			self.stage = "hooked"
			self:note("hook")
			self:press()
		end
	elseif self.stage == "hooked" then
		if hud.minigame.Visible then
			self.stage = "reeling"
			self:note("minigame")
			self:play(now)
		end
	elseif self.stage == "reeling" then
		self:play(now)
	end
end

-- Steps frame by frame, every fisher looking at its screen, until all are done (or timeout).
function Kit.play(sim: any, fishers: { any }, timeout: number): boolean
	return sim:WaitFor(function()
		local all = true
		for _, fisher in fishers do
			fisher:look()
			if not fisher:done() then
				all = false
			end
		end
		return all
	end, timeout, Kit.FRAME) == true
end

-- The "Caught" payloads the server sent this player so far.
function Kit.caughtEvents(sim: any, p: any): { any }
	local out = {}
	for _, e in sim:ClientEventsFor(p, "FishingState") do
		if e.args[1] == "Caught" then
			table.insert(out, e.args[2])
		end
	end
	return out
end

-- Cast, play like a careful player, until the catch card shows; returns the "Caught" payload.
function Kit.catch(t: any, sim: any, p: any, hud: any, what: string?): any
	local label = what or p.Name
	local before = #Kit.caughtEvents(sim, p)
	local caption = hud.caption.Text
	t.ok(Kit.startsWith(caption, CAPTION_CAST), `{label}: «{CAPTION_CAST}» before the cast (got «{caption}»)`)
	local fisher = Fisher.new(sim, p, hud)
	fisher:cast()
	t.ok(
		fisher:caption() == CAPTION_WAIT or fisher:caption() == CAPTION_WATER,
		`{label}: the button answers the cast («{fisher:caption()}»)`
	)
	t.ok(
		sim:WaitFor(function()
			return p:GetAttribute("FishingState") == "Waiting"
		end, 1.5, Kit.FRAME),
		`{label}: the server accepted the cast`
	)
	t.ok(Kit.play(sim, { fisher }, 25), `{label}: the try ends\n{fisher:describe()}`)
	t.eq(fisher.stage, "caught", `{label}: caught\n{fisher:describe()}`)
	local events = Kit.caughtEvents(sim, p)
	t.eq(#events, before + 1, `{label}: one "Caught"`)
	return events[#events], fisher
end

-- The card has closed and the fish has flown in (CounterHold cleared), plus the arrival juice.
function Kit.landed(t: any, sim: any, p: any, hud: any, what: string?)
	t.ok(
		sim:WaitFor(function()
			return not hud.card.Visible and hud.screen:GetAttribute("CounterHold") == nil
		end, Kit.CARD_GONE + 3, Kit.FRAME),
		`{what or p.Name}: the card closed and the fish flew in`
	)
	sim:Advance(1)
end

--------------------------------------------------------------------------------
-- The tank panel
--------------------------------------------------------------------------------

function Kit.card(hud: any, slot: number | string): any
	return hud.cards:FindFirstChild(if slot == "locked" then "Locked" else `Card{slot}`)
end

-- Taps «САДОК»; waits for the sheet to rise.
function Kit.openPanel(t: any, sim: any, p: any, hud: any)
	sim:Click(p, hud.tank)
	t.ok(
		sim:WaitFor(function()
			return hud.panel.Visible and Kit.card(hud, 1) ~= nil
		end, 2, Kit.FRAME),
		`{p.Name}: «САДОК» opens the panel`
	)
	sim:Advance(0.8) -- the cards' stagger
end

function Kit.tankEvents(sim: any, p: any, kind: string?): { any }
	local out = {}
	for _, e in sim:ClientEventsFor(p, "TankEvent") do
		if kind == nil or e.args[1] == kind then
			table.insert(out, e.args[2])
		end
	end
	return out
end

-- A two-tap sale from the panel: «ПРОДАТЬ?» (nothing sent), a pause ≥ ConfirmArm, the second
-- tap → TankSell(uid). Returns the answer (TankEvent "Sold" data, or "Denied" data and "Denied").
function Kit.sell(t: any, sim: any, p: any, hud: any, slot: number): (any, string?)
	local card = Kit.card(hud, slot)
	t.ok(card and card:FindFirstChild("Sell"), `{p.Name}: a fish card in slot {slot}`)
	local sells = #sim:ServerEventsFor(p, "TankSell")
	local answers = #Kit.tankEvents(sim, p, "Sold") + #Kit.tankEvents(sim, p, "Denied")
	sim:Click(p, card.Sell)
	sim:Advance(Kit.FRAME)
	t.ok(
		card.Sell.Caption.Text == Kit.TEXTS.Confirm or card.Sell.Caption.Text == Kit.TEXTS.ConfirmShort,
		`{p.Name}: the first tap asks «{Kit.TEXTS.Confirm}» (got «{card.Sell.Caption.Text}»)`
	)
	t.eq(#sim:ServerEventsFor(p, "TankSell"), sells, `{p.Name}: the first tap sends nothing`)
	sim:Advance(TankConfig.ConfirmArm + 0.1)
	sim:Click(p, card.Sell)
	t.ok(
		sim:WaitFor(function()
			return #Kit.tankEvents(sim, p, "Sold") + #Kit.tankEvents(sim, p, "Denied") > answers
		end, 3, Kit.FRAME),
		`{p.Name}: the server answers the second tap`
	)
	t.eq(#sim:ServerEventsFor(p, "TankSell"), sells + 1, `{p.Name}: one TankSell`)
	local events = sim:ClientEventsFor(p, "TankEvent")
	local last = events[#events]
	return last.args[2], last.args[1]
end

--------------------------------------------------------------------------------
-- Observers
--------------------------------------------------------------------------------

-- The server's money changes from now on: { userId, money, delta, reason, time }.
function Kit.moneyLog(sim: any): { any }
	local log = {}
	Kit.service(sim, "EconomyService").MoneyChanged:Connect(function(player, money, delta, reason)
		table.insert(log, { userId = player.UserId, money = money, delta = delta, reason = reason, time = sim:Time() })
	end)
	return log
end

function Kit.earned(log: { any }, p: any, reason: string, since: number?): (number, number)
	local sum, count = 0, 0
	for _, entry in log do
		if entry.userId == p.UserId and entry.reason == reason and entry.time >= (since or -math.huge) then
			sum += entry.delta
			count += 1
		end
	end
	return sum, count
end

-- Every toast text shown on this HUD from now on (texts → how many times).
function Kit.toasts(hud: any): { [string]: number }
	local seen: { [string]: number } = {}
	hud.toasts.ChildAdded:Connect(function(c)
		if c.Name == "Toast" then
			local label = c:FindFirstChild("Label")
			local text = if label then label.Text else "?"
			seen[text] = (seen[text] or 0) + 1
		end
	end)
	return seen
end

-- Takes the warnings containing `text` out of sim.Warnings; returns how many there were.
function Kit.takeWarnings(sim: any, text: string): number
	local n = 0
	for i = #sim.Warnings, 1, -1 do
		if string.find(sim.Warnings[i].message, text, 1, true) then
			table.remove(sim.Warnings, i)
			n += 1
		end
	end
	return n
end

--------------------------------------------------------------------------------
-- Saves
--------------------------------------------------------------------------------

function Kit.key(id: number): string
	return `Player_{id}`
end

function Kit.peek(sim: any, id: number): any
	return sim.DataStore:Peek(Kit.STORE, Kit.key(id))
end

-- A saved fish for a poked save (Rarity / Value / Income are never stored: derived on load).
function Kit.savedFish(id: string, uid: string, slot: number, extra: { [string]: any }?): { [string]: any }
	local f: { [string]: any } = { Uid = uid, Id = id, Kg = Kit.fishDef(id).MinKg, Age = 0, Slot = slot }
	f.CaughtAt = Kit.EPOCH
	for k, v in extra or {} do
		f[k] = v
	end
	return f
end

-- A saved player: the template with changes; Stats.Earned follows Money (the ledger holds).
function Kit.template(changes: { [string]: any }?): { [string]: any }
	local data: { [string]: any } = {
		V = 1,
		Money = 0,
		RodId = RodConfig.StartRod,
		TankSlots = TankConfig.StartSlots,
		LockLevel = 0,
		Upgrades = {},
		Tank = {},
		NextUid = 1,
		Stats = { Caught = 0, Sold = 0, Earned = 0, Spent = 0, Species = {} },
		Created = Kit.EPOCH,
		LastOnline = Kit.EPOCH,
		SaveCount = 1,
	}
	for k, v in changes or {} do
		data[k] = v
	end
	data.Stats.Earned = data.Money + data.Stats.Spent
	local top = 0
	for _, fish in data.Tank do
		top = math.max(top, tonumber(string.match(fish.Uid, "%d+")) or 0)
		data.Stats.Species[fish.Id] = (data.Stats.Species[fish.Id] or 0) + 1
		data.Stats.Caught += 1
	end
	data.NextUid = math.max(data.NextUid, top + 1)
	return data
end

function Kit.pokeSave(sim: any, id: number, changes: { [string]: any }?): { [string]: any }
	local data = Kit.template(changes)
	sim.DataStore:Poke(Kit.STORE, Kit.key(id), data)
	return data
end

-- Writes (UpdateAsync / SetAsync / RemoveAsync, failed and cancelled too) per key, in order.
function Kit.writesByKey(sim: any): { [string]: { number } }
	local out = {}
	for _, call in sim.DataStore.Calls do
		if call.op == "UpdateAsync" or call.op == "SetAsync" or call.op == "RemoveAsync" then
			local list = out[call.key]
			if not list then
				list = {}
				out[call.key] = list
			end
			table.insert(list, call.time)
		end
	end
	return out
end

function Kit.writes(sim: any, id: number): number
	return #(Kit.writesByKey(sim)[Kit.key(id)] or {})
end

-- No two writes to one key closer than the write gap (design B-9).
function Kit.assertGaps(t: any, sim: any)
	for key, times in Kit.writesByKey(sim) do
		for i = 2, #times do
			t.ok(
				times[i] - times[i - 1] >= DataConfig.MinWriteGap - 1e-6,
				`{key}: writes {i - 1} and {i} are {times[i] - times[i - 1]} s apart`
			)
		end
	end
end

function Kit.ledgerHolds(t: any, sim: any, value: any, what: string)
	local PlayerData = sim:Require(sim:Find("ServerScriptService.Lib.PlayerData"))
	local ok, expected = PlayerData.Ledger(value)
	t.ok(ok, `{what}: the ledger holds (Money {value.Money}, expected {expected})`)
end

-- Nothing left of the players in the four stage 3 services (design B-27).
function Kit.sizesZero(t: any, sim: any, what: string)
	for _, name in { "DataService", "TankService", "EconomyService", "MarketService" } do
		for k, size in Kit.service(sim, name)._debugSizes() do
			t.eq(size, 0, `{what}: {name}._debugSizes().{k}`)
		end
	end
end

return Kit
