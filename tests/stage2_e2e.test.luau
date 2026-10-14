--[[
	Stage 2 END-TO-END tests: the real server (FishingService) and the real client
	(FishingController + FishingFxController) together in RbxSim against the built Place1.rbxl.
	Nothing is stubbed: every step is something a player can do —
	  • stand on the FishingSpot of their own base (Workspace.Bases.Base_<BaseIndex>.FishingSpot),
	  • take the rod from the Backpack (sim:EquipTool),
	  • tap HUD.Fishing.ActionArea.ActionButton on a phone, or press F on a PC,
	  • watch the screen for the bite (BiteAlert visible, the button says «ПОДСЕЧЬ!») and hook,
	  • in the minigame, every frame look at HUD.Fishing.Minigame.Track.Needle and .Zone and tap
	    when THEY see the needle inside the green zone (the bot reads only the client's HUD,
	    never the server's minigame data).
	Then the outcome is checked on both sides: the catch card, «Улов: N», the server's
	FishingService:GetCatch, the fish held above the head, the hint after a miss, the bobbers
	other players see, and that no script errored.

	The bot (Fisher) plays like a careful player by default: one tap when the whole needle is
	inside the zone, then it waits to see the answer (the zone jumping away) before aiming again.
	The «eager» player taps whenever the needle is inside the zone on screen.

	Cases: (1) phone, no latency; (2) phone, remoteLatency 0.15; (3)/(3b) a forced Mythic (3 hits)
	without / with latency; (3c) the eager player, no latency; (4) a deliberate miss; (5) two
	players at once; (6) PC, key F. Regression cases for two latency bugs found in review:
	(2c) hooking at the end of the bite bar on a 0.5 s round trip (LatencyGrace must cover the
	round trip), (3d) the eager player with latency (taps on the stale zone after a hit are not
	judged against the new zone).

	The only test hook used is FishingService.RollFishForTest (server-only, forces a Mythic fish).

	Run: lune run tools/run_tests.luau stage2_e2e
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3
local Color3 = roblox.Color3

local PLACE = "Place1.rbxl"
local FRAME = 1 / 60

-- Pure config modules are read straight from src/ (same values the game uses).
local function loadConfig(name: string): any
	local path = `src/ReplicatedStorage/Shared/Config/{name}.luau`
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum },
		injectGlobals = true,
	})
	return chunk()
end

local FishConfig = loadConfig("FishConfig")
local FishingConfig = loadConfig("FishingConfig")

-- What the player sees on the action button (FishingController LOOKS) and in the HUD.
local CAPTION_CAST = "ЗАБРОСИТЬ"
local CAPTION_WAIT = "ЖДЁМ…"
local CAPTION_HOOK = "ПОДСЕЧЬ!"
local CAPTION_REEL = "ЛОВИ!"
local PIP_DONE = Color3.fromRGB(64, 200, 96) -- a filled «hit» pip of the minigame
local RETRACT_TIME = 0.45 -- FishingFxController: a bobber reels back in this long after Idle

-- How the bot plays.
local REACTION = 0.25 -- hooks this long after the bite alert shows up
local PATIENCE = 0.6 -- a tap with no visible answer for this long → the player taps again
local MISS_GAP = 0.15 -- «clearly outside»: the needle at least this far beyond the zone edge
local MISS_AFTER = 0.4 -- the deliberate miss comes this long after the minigame shows up
-- The button went back to «ЗАБРОСИТЬ» but neither the card nor a hint showed for this long →
-- the try ended without an outcome on screen. (RbxSim replicates attributes instantly but
-- delays remotes by remoteLatency, so the FishingState attribute can end the session on the
-- client a moment before the "Caught" / "Lost" event arrives.)
local OUTCOME_WAIT = 1
-- Standing hints (not about an event) that FishingController shows by the fishing spot.
-- Hints that are not an outcome (FishingController's context and first-spawn hints).
local CONTEXT_HINTS = {
	["Жми «Забросить»"] = true,
	["Встань в сверкающий круг"] = true,
	["Возьми удочку — кнопка справа"] = true,
	["Иди на край своего пирса!"] = true,
}

local SERVICE_PATH = "ServerScriptService.Services.FishingService"

--------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------

local function fishDef(id: string): any
	for _, fish in FishConfig.Fish do
		if fish.Id == id then
			return fish
		end
	end
	error(`no fish {id}`)
end

local function rarityDef(id: string): any
	for _, rarity in FishConfig.Rarities do
		if rarity.Id == id then
			return rarity
		end
	end
	error(`no rarity {id}`)
end

local function mythicFish(): any
	for _, fish in FishConfig.Fish do
		if fish.Rarity == "Mythic" then
			return fish
		end
	end
	error("no Mythic fish in FishConfig")
end

-- Capitals incl. Cyrillic (the card shows the rarity name in capitals).
local function upper(text: string): string
	local out = {}
	for _, code in utf8.codes(text) do
		if (code >= 0x430 and code <= 0x44F) or (code >= 0x61 and code <= 0x7A) then
			code -= 0x20
		elseif code == 0x451 then
			code = 0x401
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

local function startsWith(text: string, prefix: string): boolean
	return string.sub(text, 1, #prefix) == prefix
end

local function colorNear(a: any, b: any): boolean
	return math.abs(a.R - b.R) < 0.01 and math.abs(a.G - b.G) < 0.01 and math.abs(a.B - b.B) < 0.01
end

local function flat(v: any): any
	return Vector3.new(v.X, 0, v.Z)
end

--------------------------------------------------------------------------------
-- Sim / player helpers (only what a player has: a base, a character, a Backpack, a HUD)
--------------------------------------------------------------------------------

local function boot(t: any, latency: number?, seed: number?): any
	local sim = t.sim({ place = PLACE, remoteLatency = latency or 0, seed = seed or 1 })
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

local function service(sim: any): any
	return sim:Require(sim:Find(SERVICE_PATH))
end

local function clientModule(sim: any, player: any, name: string): any
	local module = sim:Find(`Controllers.{name}`, player:FindFirstChildOfClass("PlayerScripts"))
	assert(module, `{name} not found in PlayerScripts`)
	return sim:Require(module, player)
end

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

local function join(t: any, sim: any, id: number, device: string): any
	local player = sim:AddPlayer({ UserId = id, Name = `Fisher{id}`, DisplayName = `Рыбак{id}`, device = device })
	local ready = sim:WaitFor(function()
		local index = player:GetAttribute("BaseIndex")
		return typeof(index) == "number"
			and index > 0
			and player.Character ~= nil
			and rodIn(player:FindFirstChildOfClass("Backpack")) ~= nil
			and sim:Gui(player, "HUD.Fishing.ActionArea.ActionButton") ~= nil
	end, 10)
	t.ok(ready, `{player.Name}: a base, a character, the rod in the Backpack and the HUD`)
	sim:Advance(0.5) -- client controllers are running
	return player
end

-- The HUD elements a player looks at.
local function hudOf(sim: any, player: any): any
	local function find(path: string): any
		local found = sim:Gui(player, `HUD.{path}`)
		assert(found, `HUD.{path} not found`)
		return found
	end
	local pips = {}
	for i = 1, 5 do
		table.insert(pips, find(`Fishing.Minigame.Pips.Pip{i}`))
	end
	return {
		action = find("Fishing.ActionArea.ActionButton"),
		caption = find("Fishing.ActionArea.ActionButton.Caption"),
		keyChip = find("Fishing.ActionArea.ActionButton.KeyChip"),
		stop = find("Fishing.ActionArea.StopButton"),
		bite = find("Fishing.BiteAlert"),
		minigame = find("Fishing.Minigame"),
		title = find("Fishing.Minigame.Title"),
		needle = find("Fishing.Minigame.Track.Needle"),
		zone = find("Fishing.Minigame.Track.Zone"),
		pips = pips,
		hint = find("Fishing.Hint"),
		card = find("Fishing.CatchCard"),
		cardRarity = find("Fishing.CatchCard.Banner.RarityLabel"),
		cardName = find("Fishing.CatchCard.NameLabel"),
		cardViewport = find("Fishing.CatchCard.Viewport"),
		counter = find("Status.CatchCounter"),
		counterLabel = find("Status.CatchCounter.Label"),
		toasts = find("Toasts"),
	}
end

local function ownSpot(sim: any, player: any): any
	local base = sim.workspace.Bases:FindFirstChild(`Base_{player:GetAttribute("BaseIndex")}`)
	assert(base, `{player.Name}: own base model`)
	return base.FishingSpot
end

-- Onto the FishingSpot of the own base, rod from the Backpack into the hand.
local function goFish(t: any, sim: any, player: any): (any, any)
	local spot = ownSpot(sim, player)
	sim:Teleport(player, spot.Position + Vector3.new(0, 3, 0))
	local rod = rodIn(player:FindFirstChildOfClass("Backpack"))
	t.ok(rod, `{player.Name}: the rod is in the Backpack`)
	sim:EquipTool(player, rod)
	sim:Advance(0.3)
	local hud = hudOf(sim, player)
	t.eq(hud.action.Visible, true, "the action button shows with the rod in hand")
	local ok, why = sim:CanClick(player, hud.action)
	t.ok(ok, `the action button can be tapped: {why}`)
	return hud, rod
end

-- Test-only server hook: every roll gives this fish.
local function forceFish(sim: any, id: string, kg: number?): any
	local rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"))
	local def = fishDef(id)
	local weight = kg or def.MinKg
	local value, income = rules.Price(id, weight, nil)
	local fish = { Id = id, Rarity = def.Rarity, Kg = weight, Value = value, Income = income }
	service(sim).RollFishForTest = function()
		return table.clone(fish)
	end
	return fish
end

--------------------------------------------------------------------------------
-- The player bot: looks at its own HUD once per frame and acts like a person would
--------------------------------------------------------------------------------

local Fisher = {}
Fisher.__index = Fisher

-- How the player plays the minigame:
--   default       «careful»: taps once when the whole needle is inside the zone on screen, then
--                 waits to see the answer (the zone jumping away / the minigame closing) and
--                 for the new zone to stop sliding before aiming again;
--   opts.eager    taps whenever the needle is inside the zone on screen, every frame (the game
--                 itself says «Жми, когда стрелка в зелёной зоне!»);
--   opts.miss     taps once when the needle is clearly OUTSIDE the zone (a deliberate miss).
-- opts.key: presses F instead of tapping the button (PC).
function Fisher.new(sim: any, player: any, hud: any, opts: { key: boolean?, miss: boolean?, eager: boolean? }?): any
	local o = opts or {}
	return setmetatable({
		sim = sim,
		player = player,
		hud = hud,
		key = o.key == true,
		miss = o.miss == true,
		eager = o.eager == true,
		stage = "idle", -- idle → waiting → bite → hooked → reeling → caught | lost
		presses = 0,
		taps = {}, -- every minigame tap: { at, needle, zone, width, hits }
		retries = 0, -- taps repeated because nothing visible happened
		hitsNeeded = 0, -- pips shown when the minigame opened
		title = nil,
		pending = nil,
		lastZone = nil,
		trace = {},
		endHint = nil,
		onEnd = nil :: ((any) -> ())?,
	}, Fisher)
end

function Fisher:press()
	self.presses += 1
	if self.key then
		self.sim:PressKey(self.player, Enum.KeyCode.F)
	else
		self.sim:Click(self.player, self.hud.action) -- errors if a player could not tap it
	end
end

function Fisher:caption(): string
	return self.hud.caption.Text
end

function Fisher:done(): boolean
	return self.stage == "caught" or self.stage == "lost"
end

function Fisher:note(text: string)
	table.insert(self.trace, string.format("%.3f %s", self.sim:Time(), text))
	if #self.trace > 40 then
		table.remove(self.trace, 1)
	end
end

function Fisher:describe(): string
	local lines = { `{self.player.Name}: stage={self.stage} presses={self.presses} retries={self.retries}` }
	for i, tap in self.taps do
		table.insert(
			lines,
			string.format(
				"  tap %d at %.3f: needle %.3f zone %.3f±%.3f hits %d",
				i,
				tap.at,
				tap.needle,
				tap.zone,
				tap.width / 2,
				tap.hits
			)
		)
	end
	if self.endHint then
		table.insert(lines, `  hint: {self.endHint}`)
	end
	table.insert(lines, "  last frames:")
	for _, line in self.trace do
		table.insert(lines, "    " .. line)
	end
	return table.concat(lines, "\n")
end

-- Tap «ЗАБРОСИТЬ».
function Fisher:cast()
	self.stage = "waiting"
	self.castAt = self.sim:Time()
	self:note(`cast («{self:caption()}»)`)
	self:press()
end

-- Filled pips = hits so far, as the player sees them.
function Fisher:hits(): number
	local count = 0
	for _, pip in self.hud.pips do
		if pip.Visible and colorNear(pip.BackgroundColor3, PIP_DONE) then
			count += 1
		end
	end
	return count
end

-- One minigame frame: the needle and the zone as drawn right now.
function Fisher:play(now: number)
	local hud = self.hud
	local needle = hud.needle.Position.X.Scale
	local needleHalf = hud.needle.Size.X.Scale / 2
	local zone = hud.zone.Position.X.Scale
	local width = hud.zone.Size.X.Scale
	local hits = self:hits()
	local moving = self.lastZone ~= nil and math.abs(zone - self.lastZone) > 1e-6
	self.lastZone = zone
	self:note(
		string.format(
			"needle %.3f zone %.3f±%.3f hits %d%s",
			needle,
			zone,
			width / 2,
			hits,
			if moving then " (zone sliding)" else ""
		)
	)

	local offset = math.abs(needle - zone)
	local inside = offset + needleHalf <= width / 2 -- the whole needle is inside the green zone
	if self.eager then
		-- Taps whenever the needle is in the zone on screen (FishingController itself lets
		-- through one tap per TapInterval).
		if inside then
			table.insert(self.taps, { at = now, needle = needle, zone = zone, width = width, hits = hits })
			self:note("TAP")
			self:press()
		end
		return
	end

	local pending = self.pending
	if pending then
		if math.abs(zone - pending.zone) > 1e-6 then
			self.pending = nil -- the answer: the zone jumps away (a hit; a new zone to aim at)
		elseif now - pending.at >= PATIENCE then
			self.pending = nil -- nothing visible happened: tap again
			if hits == pending.hits then
				self.retries += 1
			end
		end
	end
	if self.pending or moving then
		return -- waits for the answer to the last tap / for the zone to stop
	end

	local tap
	if self.miss then
		tap = now - self.reelAt >= MISS_AFTER and offset >= width / 2 + needleHalf + MISS_GAP
	else
		tap = inside
	end
	if tap then
		table.insert(self.taps, { at = now, needle = needle, zone = zone, width = width, hits = hits })
		self.pending = { at = now, hits = hits, zone = zone }
		self:note("TAP")
		self:press()
	end
end

-- One frame of the player looking at the screen (call after every sim:Step).
function Fisher:look()
	local hud = self.hud
	local now = self.sim:Time()
	local stage = self.stage
	if stage == "idle" or self:done() then
		return
	end
	-- With the line out «СМОТАТЬ» is on screen and the button never says «ЗАБРОСИТЬ». Once the
	-- line is in (after the cast was answered) — or the card shows — this try is over and the
	-- player waits to see how it went: the catch card, or a hint why the fish got away. (Right
	-- after it the button says «ЖДЁМ…» for CastCooldown, then «ЗАБРОСИТЬ».)
	local lineIn = not hud.stop.Visible and stage ~= "waiting"
	if (startsWith(self:caption(), CAPTION_CAST) or hud.card.Visible or lineIn) and not hud.minigame.Visible then
		self.idleAt = self.idleAt or now
		local eventHint = hud.hint.Visible and not CONTEXT_HINTS[hud.hint.Text]
		if hud.card.Visible or eventHint or now - self.idleAt >= OUTCOME_WAIT then
			self.stage = if hud.card.Visible then "caught" else "lost"
			self.endedAt = now
			self.endHint = if hud.hint.Visible then hud.hint.Text else nil
			self:note(`end: {self.stage} ({string.format("%.3f", now - self.idleAt)} s after the button went back)`)
			if self.onEnd then
				self.onEnd(self) -- checks that must run the moment the outcome shows
			end
		end
		return
	end
	self.idleAt = nil
	if stage == "waiting" then
		if hud.bite.Visible and startsWith(self:caption(), CAPTION_HOOK) then
			self.stage = "bite"
			self.biteAt = now
			self.biteCaption = self:caption()
			self:note(`bite seen («{self.biteCaption}»)`)
		end
	elseif stage == "bite" then
		if now - self.biteAt >= REACTION - 1e-9 then
			self.stage = "hooked"
			self:note("hook")
			self:press()
		end
	elseif stage == "hooked" then
		if hud.minigame.Visible then
			self.stage = "reeling"
			self.reelAt = now
			self.title = hud.title.Text
			self.reelCaption = self:caption()
			local shown = 0
			for _, pip in hud.pips do
				if pip.Visible then
					shown += 1
				end
			end
			self.hitsNeeded = shown
			self:note(`minigame: {self.title}, {shown} pips`)
			self:play(now)
		end
	elseif stage == "reeling" then
		self:play(now)
	end
end

-- Steps frame by frame, every fisher looking at the screen, until all are done (or timeout).
local function fishUntilDone(sim: any, fishers: { any }, timeout: number): boolean
	return sim:WaitFor(function()
		local all = true
		for _, fisher in fishers do
			fisher:look()
			if not fisher:done() then
				all = false
			end
		end
		return all
	end, timeout, FRAME) == true
end

--------------------------------------------------------------------------------
-- Shared checks
--------------------------------------------------------------------------------

-- The caught fish first leaps from the water to the fisher (clients draw it), and the server hangs
-- it above the head when it lands (FishingConfig.LeapTime after the catch). Waits for it; the
-- other bots (others) keep looking at their screens meanwhile.
local function waitHeldFish(sim: any, character: any, others: { any }?): any
	return sim:WaitFor(function()
		for _, other in others or {} do
			other:look()
		end
		return character:FindFirstChild("HeldFish")
	end, FishingConfig.LeapTime + 0.3, FRAME)
end

-- After a catch: the card, the counter, the server's catch, the fish above the head (after its leap).
local function checkCatch(t: any, sim: any, player: any, hud: any, fisher: any, total: number, others: { any }?): any
	local story = fisher:describe()
	t.eq(fisher.stage, "caught", `{player.Name} caught the fish\n{story}`)
	if not fisher.eager then
		t.eq(#fisher.taps, fisher.hitsNeeded, `every tap counted (taps = hits needed)\n{story}`)
		t.eq(fisher.retries, 0, `no tap went unanswered\n{story}`)
	end

	local catch = service(sim):GetCatch(player)
	t.eq(#catch, total, "server: FishingService:GetCatch has the fish")
	local fish = catch[#catch]
	t.ok(fish and typeof(fish.Id) == "string", "server: a FishData")

	-- the catch card
	t.eq(hud.card.Visible, true, "the catch card shows")
	t.eq(hud.cardName.Text, fishDef(fish.Id).Name, "the card names the caught fish")
	t.eq(hud.cardRarity.Text, upper(rarityDef(fish.Rarity).Name), "the card shows its rarity")
	t.ok(hud.cardViewport:FindFirstChildOfClass("Model"), "the fish model is in the card")
	-- the counter
	t.eq(hud.counter.Visible, true, "the catch counter shows")
	t.eq(hud.counterLabel.Text, `Улов: {total}`, "the catch counter")
	t.eq(player:GetAttribute("FishCaught"), total, "FishCaught attribute")

	-- the fish above the head (server-side model in the character: everyone sees it)
	local character = player.Character
	local held = waitHeldFish(sim, character, others)
	t.ok(held and held:IsA("Model"), "the caught fish is held above the head")
	if held then
		local template = sim:Find(`ReplicatedStorage.Assets.Fish.{fish.Id}.{fish.Mutation or "Normal"}`)
		t.eq(held:GetAttribute("Kind"), template:GetAttribute("Kind"), "it is the caught fish's model")
		local head = character.Head
		local box, size = held:GetBoundingBox()
		t.ok(box.Position.Y - size.Y / 2 >= head.Position.Y + head.Size.Y / 2 - 0.05, "above the head")
		t.ok(flat(box.Position - head.Position).Magnitude < 0.1, "centred over the head")
	end

	-- back to Idle on both sides
	t.eq(player:GetAttribute("FishingState"), "Idle", "server state Idle")
	t.ok(
		startsWith(hud.caption.Text, CAPTION_CAST) or hud.caption.Text == CAPTION_WAIT,
		`the button says «{CAPTION_CAST}» again (or «{CAPTION_WAIT}» during CastCooldown)`
	)
	t.eq(hud.minigame.Visible, false, "the minigame is closed")
	t.eq(hud.bite.Visible, false, "no bite alert")
	return fish
end

-- Cast, check the cast was accepted, play to the end.
local function castAndPlay(t: any, sim: any, fisher: any, timeout: number?)
	fisher:cast()
	t.eq(fisher:caption(), CAPTION_WAIT, "the button says «ЖДЁМ…» right after the tap")
	local accepted = sim:WaitFor(function()
		return fisher.player:GetAttribute("FishingState") == "Waiting"
	end, 1, FRAME)
	t.ok(accepted, "server: the cast is accepted (FishingState Waiting)")
	t.ok(fishUntilDone(sim, { fisher }, timeout or 20), `the try ends in time\n{fisher:describe()}`)
end

local tests = {}

--------------------------------------------------------------------------------
-- (1) and (2): a clean catch on a phone, without and with network latency
--------------------------------------------------------------------------------

local function cleanCatch(t: any, latency: number)
	local sim = boot(t, latency)
	local p = join(t, sim, 1, "phone")
	local hud = goFish(t, sim, p)
	t.eq(hud.caption.Text, CAPTION_CAST, "phone: «ЗАБРОСИТЬ» without a key hint")
	t.eq(hud.counter.Visible, false, "no catch counter before the first fish")

	local fisher = Fisher.new(sim, p, hud)
	castAndPlay(t, sim, fisher)
	t.ok(fisher.biteAt ~= nil, "the player saw the bite (BiteAlert + «ПОДСЕЧЬ!»)")
	t.eq(fisher.biteCaption, CAPTION_HOOK, "the button says «ПОДСЕЧЬ!» on the bite")
	t.eq(fisher.reelCaption, CAPTION_REEL, "the button says «ЛОВИ!» in the minigame")
	local fish = checkCatch(t, sim, p, hud, fisher, 1)
	local landedAt = sim:Time() -- checkCatch waited for the held fish (the leap landed)

	-- The card closes by itself; the held fish stays a little longer (HoldFishTime per rarity);
	-- the player can fish again.
	sim:Advance(FishingConfig.CatchCardTime + 0.1)
	t.eq(hud.card.Visible, false, "the card closes after CatchCardTime")
	sim:Advance(math.max(0, landedAt + FishingConfig.HoldFishTime[fish.Rarity] + 0.1 - sim:Time()))
	t.eq(p.Character:FindFirstChild("HeldFish"), nil, "the held fish is gone after HoldFishTime")
	t.eq(hud.counterLabel.Text, "Улов: 1", "the counter stays")

	-- A second catch on the same rod, counted on.
	local again = Fisher.new(sim, p, hud)
	castAndPlay(t, sim, again)
	checkCatch(t, sim, p, hud, again, 2)
	sim:AssertNoErrors({ warnings = true })
end

tests["(1) phone, no latency: cast, hook on the bite, tap when the needle is in the zone, catch"] = function(t)
	cleanCatch(t, 0)
end

tests["(2) phone, remoteLatency 0.15 (0.3 s round trip): tapping on what the player sees still catches"] = function(t)
	cleanCatch(t, 0.15)
end

--------------------------------------------------------------------------------
-- (2c) hooking at the end of the visible bite bar on a 0.5 s round trip (within MaxLag)
--------------------------------------------------------------------------------

-- Regression (review): the hook is accepted until BiteWindow + LatencyGrace after the server's
-- bite; LatencyGrace must cover the round trip, or the last moments of the bite bar the player
-- sees are already «too late».
tests["(2c) remoteLatency 0.25: hooking while the bite bar still runs hooks the fish"] = function(t)
	local latency = 0.25
	t.ok(
		2 * latency <= FishingConfig.MaxLag,
		"the round trip is within MaxLag (the network the game promises to handle)"
	)
	local sim = boot(t, latency)
	local p = join(t, sim, 1, "phone")
	local hud = goFish(t, sim, p)
	local fisher = Fisher.new(sim, p, hud)
	fisher:cast()
	t.ok(
		sim:WaitFor(function()
			return hud.bite.Visible
		end, 10, FRAME),
		"the bite shows"
	)
	local timer = hud.bite.Timer
	local full = timer.Size.X.Scale
	-- The player hesitates and taps «ПОДСЕЧЬ!» when the bar is almost (not yet) empty.
	t.ok(
		sim:WaitFor(function()
			return timer.Size.X.Scale <= full * 0.05
		end, FishingConfig.BiteWindow + 0.2, FRAME),
		"the bite bar runs down"
	)
	t.ok(timer.Size.X.Scale > 0, "there is still time left on the bar")
	t.eq(hud.bite.Visible, true, "the bite alert is still on screen")
	t.ok(startsWith(hud.caption.Text, CAPTION_HOOK), "the button still says «ПОДСЕЧЬ!»")
	fisher.stage = "hooked"
	fisher:note("hook at the end of the bar")
	fisher:press()
	t.ok(fishUntilDone(sim, { fisher }, 15), `the try ends\n{fisher:describe()}`)
	t.eq(
		fisher.stage,
		"caught",
		"a hook tapped while the bite bar still runs must be accepted (LatencyGrace ≥ round trip) "
			.. `→ «{fisher.endHint}»\n{fisher:describe()}`
	)
	if fisher.stage == "caught" then
		checkCatch(t, sim, p, hud, fisher, 1)
	end
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- (3) a forced Mythic fish: 3 hits, the zone jumps after each
--------------------------------------------------------------------------------

local function mythicCatch(t: any, latency: number)
	local sim = boot(t, latency)
	local p = join(t, sim, 1, "phone")
	local other = join(t, sim, 2, "phone")
	local hud = goFish(t, sim, p)
	local otherHud = hudOf(sim, other)
	local dragon = mythicFish()
	forceFish(sim, dragon.Id, (dragon.MinKg + dragon.MaxKg) / 2)

	local fisher = Fisher.new(sim, p, hud)
	castAndPlay(t, sim, fisher, 25)
	t.eq(fisher.title, `{upper(rarityDef("Mythic").Name)} РЫБА!`, "the minigame title says it is Mythic")
	t.eq(fisher.hitsNeeded, FishingConfig.Minigame.Mythic.Hits, "3 pips to fill")
	t.eq(fisher.hitsNeeded, 3)
	local fish = checkCatch(t, sim, p, hud, fisher, 1)
	t.eq(fish.Id, dragon.Id, "server: the Mythic fish is in the catch")
	t.eq(fish.Rarity, "Mythic")
	t.eq(hud.cardRarity.Text, "МИФИЧЕСКАЯ")
	t.eq(hud.cardName.Text, dragon.Name)

	-- The zone jumped after each hit: the taps were at three different zones.
	for i = 2, #fisher.taps do
		local before, now = fisher.taps[i - 1], fisher.taps[i]
		t.ok(math.abs(now.zone - before.zone) > 0.05, `the zone moved after hit {i - 1}\n{fisher:describe()}`)
		t.eq(now.hits, i - 1, `pip {i - 1} was filled before tap {i}`)
	end

	-- Everyone hears about it (a toast on the other player's screen).
	sim:Advance(0.5)
	local heard = false
	for _, item in otherHud.toasts:GetDescendants() do
		if item:IsA("TextLabel") and string.find(item.Text, dragon.Name, 1, true) then
			heard = true
		end
	end
	t.ok(heard, "the other player sees a toast about the Mythic catch")
	sim:AssertNoErrors({ warnings = true })
end

tests["(3) a forced Mythic (3 hits) is caught by tapping on what the player sees"] = function(t)
	mythicCatch(t, 0)
end

tests["(3b) a forced Mythic (3 hits) with remoteLatency 0.15"] = function(t)
	mythicCatch(t, 0.15)
end

--------------------------------------------------------------------------------
-- (3c) / (3d): the EAGER player — taps whenever the needle is in the zone on screen
--------------------------------------------------------------------------------

-- A forced Mythic played by the eager player on several seeds (zone and needle start differ).
-- With remoteLatency 0.15 about half of all seeds lose the fish (11 of seeds 1..24); these four
-- all do, and all four are caught without latency.
local EAGER_SEEDS = { 7, 10, 13, 14 }

local function eagerMythic(t: any, latency: number, failMessage: string)
	local lost = {}
	for _, seed in EAGER_SEEDS do
		local sim = boot(t, latency, seed)
		local p = join(t, sim, 1, "phone")
		local hud = goFish(t, sim, p)
		forceFish(sim, mythicFish().Id)
		local fisher = Fisher.new(sim, p, hud, { eager = true })
		castAndPlay(t, sim, fisher, 25)
		if fisher.stage == "caught" then
			checkCatch(t, sim, p, hud, fisher, 1)
		else
			table.insert(lost, `seed {seed}: «{fisher.endHint}»\n{fisher:describe()}`)
		end
		sim:AssertNoErrors({ warnings = true })
	end
	t.eq(#lost, 0, `{failMessage}\n{table.concat(lost, "\n")}`)
end

tests["(3c) no latency: the eager player catches a Mythic on every seed"] = function(t)
	eagerMythic(t, 0, "the eager player lost the fish without latency")
end

-- Regression (review): after a hit the client keeps drawing the OLD zone for one round trip
-- (until "Zone" arrives); a tap the player makes in that window must not be judged against the
-- NEW zone (FishingService.applyTap moves the time floor to when the client sees the new zone).
tests["(3d) remoteLatency 0.15: the eager player catches a Mythic on every seed"] = function(t)
	eagerMythic(
		t,
		0.15,
		"a tap on the zone the player still sees during the round trip after a hit must not lose the fish"
	)
end

--------------------------------------------------------------------------------
-- (4) a deliberate miss
--------------------------------------------------------------------------------

tests["(4) a deliberate miss: hint, back to Idle, a new cast works after the cooldown"] = function(t)
	local sim = boot(t, 0)
	local p = join(t, sim, 1, "phone")
	local hud = goFish(t, sim, p)

	local missing = Fisher.new(sim, p, hud, { miss = true })
	castAndPlay(t, sim, missing)
	local story = missing:describe()
	t.eq(missing.stage, "lost", `the fish got away\n{story}`)
	t.eq(#missing.taps, 1, `one tap, clearly outside the zone\n{story}`)
	local tap = missing.taps[1]
	t.ok(math.abs(tap.needle - tap.zone) > tap.width / 2 + 0.1, "the tap was clearly outside")

	-- The hint says why, the state is Idle on both sides, nothing was caught.
	t.eq(hud.hint.Visible, true, "a hint shows")
	t.ok(string.find(hud.hint.Text, "Мимо", 1, true) ~= nil, `the hint says it was a miss: «{hud.hint.Text}»`)
	t.eq(p:GetAttribute("FishingState"), "Idle", "server: Idle")
	t.ok(
		startsWith(hud.caption.Text, CAPTION_CAST) or hud.caption.Text == CAPTION_WAIT,
		"the button says «ЗАБРОСИТЬ» (or «ЖДЁМ…» during CastCooldown)"
	)
	t.eq(hud.minigame.Visible, false, "the minigame is closed")
	t.eq(hud.stop.Visible, false, "no «СМОТАТЬ»: the line is in")
	t.eq(hud.card.Visible, false, "no catch card")
	t.eq(hud.counter.Visible, false, "no catch counter")
	t.eq(#service(sim):GetCatch(p), 0, "server: nothing caught")
	t.eq(p.Character:FindFirstChild("HeldFish"), nil, "nothing above the head")

	-- An impatient tap during the cooldown: the dim «ЖДЁМ…» button ignores it (nothing is sent),
	-- then it comes back as «ЗАБРОСИТЬ» by itself (nothing gets stuck).
	local lostAt = missing.endedAt
	local casts = #sim:ServerEventsFor(p, "FishingCast")
	sim:Advance(0.1)
	t.eq(hud.caption.Text, CAPTION_WAIT, "«ЖДЁМ…» during CastCooldown")
	sim:Click(p, hud.action)
	sim:Advance(0.2)
	t.eq(#sim:ServerEventsFor(p, "FishingCast"), casts, "no cast request during CastCooldown")
	t.eq(p:GetAttribute("FishingState"), "Idle", "server: still Idle")
	sim:Advance(math.max(0, lostAt + FishingConfig.CastCooldown + 0.05 - sim:Time()))
	t.eq(hud.caption.Text, CAPTION_CAST, "the button is back to «ЗАБРОСИТЬ»")

	-- After the cooldown a new cast works and can be played to a catch.
	sim:Advance(math.max(0, lostAt + FishingConfig.CastCooldown + 0.05 - sim:Time()))
	local fisher = Fisher.new(sim, p, hud)
	castAndPlay(t, sim, fisher)
	checkCatch(t, sim, p, hud, fisher, 1)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- (5) two players at once
--------------------------------------------------------------------------------

tests["(5) two players fish at once: each sees the other's bobber and line, both catch"] = function(t)
	local sim = boot(t, 0)
	local a = join(t, sim, 1, "phone")
	local b = join(t, sim, 2, "phone")
	t.ok(a:GetAttribute("BaseIndex") ~= b:GetAttribute("BaseIndex"), "different bases")
	local hudA, rodA = goFish(t, sim, a)
	local hudB, rodB = goFish(t, sim, b)
	local fxA = clientModule(sim, a, "FishingFxController")
	local fxB = clientModule(sim, b, "FishingFxController")
	t.eq(fxA.GetBobber(b), nil, "no bobber before the cast")

	local fisherA = Fisher.new(sim, a, hudA)
	local fisherB = Fisher.new(sim, b, hudB)
	fisherA:cast()
	sim:Advance(0.2)
	fisherB:cast()
	-- Both bobbers fly out and land; nobody bites before CastFlightTime + BiteDelay.Min.
	fishUntilDone(sim, { fisherA, fisherB }, FishingConfig.CastFlightTime + 0.4)
	t.eq(a:GetAttribute("FishingState"), "Waiting", "A is fishing")
	t.eq(b:GetAttribute("FishingState"), "Waiting", "B is fishing")

	local function seesBobber(viewerFx: any, viewerName: string, fisher: any, rod: any)
		local bobber = viewerFx.GetBobber(fisher)
		t.ok(bobber, `{viewerName} sees {fisher.Name}'s bobber`)
		if not bobber then
			return
		end
		t.ok(bobber:IsDescendantOf(sim.workspace), "the bobber is in the Workspace")
		local target = fisher:GetAttribute("BobberTarget")
		t.ok(target ~= nil, "server: BobberTarget is set")
		local position = bobber:GetPivot().Position
		t.ok(
			flat(position - target).Magnitude < 1,
			`{viewerName}: {fisher.Name}'s bobber is on the water at the cast target ({flat(position - target).Magnitude})`
		)
		t.ok(math.abs(position.Y - (target.Y + bobber:GetAttribute("FloatDepth"))) < 0.5, "floating on the water")
		local line = bobber:FindFirstChild("Line")
		t.ok(line and line:IsA("Beam") and line.Enabled, "with a fishing line")
		t.ok(line.Attachment0 == rod.Handle.TipAttachment, `the line starts at {fisher.Name}'s rod tip`)
	end
	seesBobber(fxA, "A", b, rodB)
	seesBobber(fxB, "B", a, rodA)
	seesBobber(fxA, "A", a, rodA)
	seesBobber(fxB, "B", b, rodB)

	-- Both play on at the same time (bites, hooks and minigames interleave). Each catch is
	-- checked the moment it happens (the card and the held fish go away after a few seconds).
	local checked = {}
	fisherA.onEnd = function()
		checkCatch(t, sim, a, hudA, fisherA, 1, { fisherB })
		checked.A = true
	end
	fisherB.onEnd = function()
		checkCatch(t, sim, b, hudB, fisherB, 1, { fisherA })
		checked.B = true
	end
	t.ok(fishUntilDone(sim, { fisherA, fisherB }, 25), `both tries end\n{fisherA:describe()}\n{fisherB:describe()}`)
	t.ok(checked.A and checked.B, "both catches checked")
	t.eq(hudA.counterLabel.Text, "Улов: 1", "A's own counter")
	t.eq(hudB.counterLabel.Text, "Улов: 1", "B's own counter")

	-- The bobbers reel in and disappear on both screens.
	sim:Advance(RETRACT_TIME + 0.3)
	t.eq(fxA.GetBobber(b), nil, "A: B's bobber reeled in")
	t.eq(fxB.GetBobber(a), nil, "B: A's bobber reeled in")
	t.eq(fxA.GetBobber(a), nil, "A: own bobber reeled in")
	t.eq(fxB.GetBobber(b), nil, "B: own bobber reeled in")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- (6) PC: the F key (not E — E belongs to ProximityPrompts)
--------------------------------------------------------------------------------

tests["(6) desktop: F casts, hooks and taps; F closes the catch card; the button shows the F key"] = function(t)
	local sim = boot(t, 0)
	local p = join(t, sim, 1, "desktop")
	local hud = goFish(t, sim, p)
	t.eq(hud.caption.Text, CAPTION_CAST)
	t.ok(hud.keyChip.Visible and hud.keyChip.Key.Text == "F", "desktop: the F key chip on the button")

	local fisher = Fisher.new(sim, p, hud, { key = true })
	fisher:cast()
	t.eq(hud.caption.Text, CAPTION_WAIT, "F cast the line")
	t.ok(fishUntilDone(sim, { fisher }, 20), `the try ends\n{fisher:describe()}`)
	t.eq(fisher.biteCaption, CAPTION_HOOK, "«ПОДСЕЧЬ!» on the bite")
	t.eq(fisher.reelCaption, CAPTION_REEL, "«ЛОВИ!» in the minigame")
	checkCatch(t, sim, p, hud, fisher, 1)
	t.eq(#sim:ServerEventsFor(p, "FishingCast"), 1, "one cast request")
	t.eq(#sim:ServerEventsFor(p, "FishingHook"), 1, "one hook request")
	t.eq(#sim:ServerEventsFor(p, "FishingTap"), #fisher.taps, "one tap request per F press in the minigame")

	-- F with the card open closes the card (no cast; not in the first CARD_INPUT_LOCK 0.5 s);
	-- the next F casts.
	sim:Advance(0.5)
	sim:PressKey(p, Enum.KeyCode.F)
	sim:Advance(0.1)
	t.eq(hud.card.Visible, false, "F closed the card")
	t.eq(#sim:ServerEventsFor(p, "FishingCast"), 1, "…without casting")
	sim:Advance(FishingConfig.CastCooldown)
	local again = Fisher.new(sim, p, hud, { key = true })
	castAndPlay(t, sim, again)
	checkCatch(t, sim, p, hud, again, 2)
	sim:AssertNoErrors({ warnings = true })
end

return tests
