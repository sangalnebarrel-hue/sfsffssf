--[[
	Stage 2 client tests (RbxSim against the built Place1.rbxl): FishingController (the local
	player's fishing UI and input) and FishingFxController (bobbers, lines, rainbow fish).

	The server half (FishingService) is replaced by an empty module in boot(), so the harness alone
	plays the server — it puts
	the rod Tool into the Backpack, sets the Player attributes (FishingState, BobberTarget,
	CastTime, RodId, FishCaught) and fires the FishingState RemoteEvent; what the client asked
	for is read back with sim:ServerEventsFor(player, "FishingCast" | ...).

	Run: lune run tools/run_tests.luau stage2_client
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local PLACE = "Place1.rbxl"

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

local BaseConfig = loadConfig("BaseConfig")
local FishingConfig = loadConfig("FishingConfig")
local UIConfig = loadConfig("UIConfig")

local RETRACT_TIME = 0.45 -- FishingFxController: the bobber reels back to the rod tip
local HINT_TIME = 3.5 -- FishingController: event hints hide after this

-- The look of a candy (Theme.candy / UiFx.setCandy): the face's "Fill" gradient, top and bottom,
-- and the lip colour. The fishing widgets are candies since the Candy Splash restyle
-- (tools/builder/gui/STYLE.md), so their colour is the gradient, not BackgroundColor3.
local function candyLook(root: any): (any, any, any)
	local face = root:FindFirstChild(root:GetAttribute("CandyFace") or "Face")
	local keys = face.Fill.Color.Keypoints
	return keys[1].Value, keys[#keys].Value, root.Lip.BackgroundColor3
end

--------------------------------------------------------------------------------
-- Harness helpers
--------------------------------------------------------------------------------

local function boot(t: any): any
	local sim = t.sim({ place = PLACE })
	-- Switch the real FishingService off (an empty module: Main finds it but runs nothing), so
	-- every FishingState the client sees comes from the test (tests/stage2_fishing and
	-- tests/stage2_e2e cover the real server).
	sim:Find("ServerScriptService.Services.FishingService").Source = "return {}"
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

local function addPlayer(sim: any, id: number, device: string?): any
	local player = sim:AddPlayer({ UserId = id, Name = `Fisher{id}`, device = device or "desktop" })
	sim:Advance(1)
	return player
end

-- What FishingService does on every spawn: the start rod into the Backpack + attributes.
local function giveRod(sim: any, player: any): any
	local template = sim:Find("ReplicatedStorage.Assets.Rods.RodBamboo")
	local rod = template:Clone()
	rod.Name = template:GetAttribute("DisplayName")
	rod.Parent = player:FindFirstChildOfClass("Backpack")
	player:SetAttribute("RodId", "RodBamboo")
	player:SetAttribute("FishingState", "Idle")
	player:SetAttribute("FishCaught", 0)
	sim:Advance(0.05)
	return rod
end

local function ownBase(sim: any, player: any): any
	return sim.workspace.Bases:FindFirstChild(`Base_{player:GetAttribute("BaseIndex")}`)
end

local function standAtSpot(sim: any, player: any)
	local spot = ownBase(sim, player).FishingSpot
	sim:Teleport(player, spot.CFrame.Position + Vector3.new(0, 3, 0))
	sim:Advance(0.3)
end

-- The rod in hand at the own fishing spot (far from it the button is «К ПИРСУ» and casts
-- nothing — UI v2); `far` = equip it where the player stands.
local function equipRod(sim: any, player: any, far: boolean?): any
	local rod = giveRod(sim, player)
	if not far then
		standAtSpot(sim, player)
	end
	sim:EquipTool(player, rod)
	sim:Advance(0.1)
	return rod
end

local function gui(sim: any, player: any, path: string): any
	local found = sim:Gui(player, `HUD.Fishing.{path}`)
	assert(found, `HUD.Fishing.{path} not found`)
	return found
end

local function caption(sim: any, player: any): string
	return gui(sim, player, "ActionArea.ActionButton.Caption").Text
end

-- The key on the button's key chip ("" = no chip shown). UI v2: «F» / «R2» on a key cap instead
-- of a «[F]» suffix in the caption.
local function keyChip(sim: any, player: any): string
	local chip = gui(sim, player, "ActionArea.ActionButton.KeyChip")
	return if chip.Visible then chip.Key.Text else ""
end

-- The harness counts as the server: fire FishingState to one client.
local function serverSays(sim: any, player: any, state: string, data: any?)
	sim:Find("ReplicatedStorage.Remotes.FishingState"):FireClient(player, state, data)
	sim:Advance(0.05)
end

local function sent(sim: any, player: any, name: string): { any }
	return sim:ServerEventsFor(player, name)
end

-- The PC action key (F; E belongs to ProximityPrompts).
local function pressF(sim: any, player: any)
	sim:PressKey(player, Enum.KeyCode.F)
	sim:Advance(0.02)
end

local function controller(sim: any, player: any, name: string): any
	local module = sim:Find(`Controllers.{name}`, player:FindFirstChildOfClass("PlayerScripts"))
	assert(module, `{name} not found in PlayerScripts`)
	return sim:Require(module, player)
end

local function colorNear(a: any, b: any, eps: number?): boolean
	local e = eps or 0.01
	return math.abs(a.R - b.R) < e and math.abs(a.G - b.G) < e and math.abs(a.B - b.B) < e
end

-- The candy shows a style (a UIConfig palette token, rarity or mutation): gradient and lip.
local function isCandy(root: any, style: any): boolean
	local top, bottom, lip = candyLook(root)
	return colorNear(top, style.Top) and colorNear(bottom, style.Bottom) and colorNear(lip, style.Lip)
end

-- Client connections of `viewer` that mention `name` (a player's name) in their signal.
local function connectionsAbout(sim: any, viewer: any, name: string): number
	local ctxName = sim:ContextName(viewer)
	return sim:CountConnections(function(conn: any)
		return conn.ctx.name == ctxName and string.find(conn.signal:describe(), name, 1, true) ~= nil
	end)
end

local function renderSteppedCount(sim: any, viewer: any): number
	local ctxName = sim:ContextName(viewer)
	return sim:CountConnections(function(conn: any)
		return conn.ctx.name == ctxName and string.find(conn.signal:describe(), "RenderStepped", 1, true) ~= nil
	end)
end

local MINIGAME = {
	Rarity = "Legendary",
	U0 = 0.25,
	Speed = 1.25,
	ZoneCenter = 0.7,
	ZoneWidth = 0.17,
	Hits = 0,
	HitsNeeded = 2,
	Timeout = 12,
}

local tests = {}

--------------------------------------------------------------------------------
-- Action button
--------------------------------------------------------------------------------

tests["action button: hidden without the rod, shown while it is equipped, key hint on desktop"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local button = gui(sim, p, "ActionArea.ActionButton")
	t.eq(button.Visible, false, "no rod")
	local rod = giveRod(sim, p)
	t.eq(button.Visible, false, "rod only in the Backpack")
	sim:EquipTool(p, rod)
	sim:Advance(0.1)
	t.eq(button.Visible, true, "rod in hand")
	-- UI v2 (FUI-16): far from the fishing spot the button shows the way instead of casting.
	t.eq(caption(sim, p), "К ПИРСУ", "far from the spot")
	t.eq(keyChip(sim, p), "", "no key chip: the key does not cast here")
	t.ok(isCandy(button, UIConfig.Palette.Slate), "a calm Slate candy far from the spot")
	standAtSpot(sim, p)
	t.eq(caption(sim, p), "ЗАБРОСИТЬ")
	t.eq(keyChip(sim, p), "F", "the key chip on desktop")
	t.ok(isCandy(button, UIConfig.Palette.Sky), "a Sky (blue) candy while Idle")
	t.eq(gui(sim, p, "ActionArea.StopButton").Visible, false, "no line out")
	sim:Teleport(p, ownBase(sim, p).SpawnPad.Position + Vector3.new(0, 5, 0))
	sim:Advance(0.3)
	sim:UnequipTools(p)
	sim:Advance(0.1)
	t.eq(button.Visible, false, "rod back in the Backpack")
	sim:AssertNoErrors({ warnings = true })
end

tests["phone: the button is clickable, a tap casts once, ЖДЁМ… ignores taps, a lost reply unlocks it"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	equipRod(sim, p)
	local button = gui(sim, p, "ActionArea.ActionButton")
	local ok, why = sim:CanClick(p, button)
	t.ok(ok, `ActionButton clickable on a phone: {why}`)
	t.eq(caption(sim, p), "ЗАБРОСИТЬ")
	t.eq(keyChip(sim, p), "", "no key chip on touch screens")

	local info = sim:Run(function()
		return sim:Env(p).game:GetService("ContextActionService"):GetBoundActionInfo("FishingAction")
	end, p)
	t.eq(info.createTouchButton, false, "no CAS touch button")

	sim:Click(p, button)
	sim:Advance(0.1)
	t.eq(#sent(sim, p, "FishingCast"), 1, "cast sent")
	t.eq(caption(sim, p), "ЖДЁМ…")
	sim:Click(p, button)
	sim:Advance(0.1)
	t.eq(#sent(sim, p, "FishingCast"), 1, "taps while waiting are ignored")

	sim:Advance(1.5) -- the server never answered
	t.eq(caption(sim, p), "ЗАБРОСИТЬ", "pending times out")
	sim:Click(p, button)
	sim:Advance(0.1)
	t.eq(#sent(sim, p, "FishingCast"), 2, "can cast again")
	sim:AssertNoErrors({ warnings = true })
end

tests["states: captions, colours, Stop button; Hook is sent once from button, tool or key"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	equipRod(sim, p)
	local button = gui(sim, p, "ActionArea.ActionButton")
	local stop = gui(sim, p, "ActionArea.StopButton")
	local alert = gui(sim, p, "BiteAlert")

	pressF(sim, p)
	t.eq(#sent(sim, p, "FishingCast"), 1, "F casts")
	serverSays(sim, p, "Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = FishingConfig.CastFlightTime })
	t.eq(caption(sim, p), "ЖДЁМ…")
	t.eq(stop.Visible, true, "line is out")
	t.ok(isCandy(button, UIConfig.Palette.Water), "a Water candy while the line is in the water (UI v2)")
	pressF(sim, p)
	sim:ActivateTool(p)
	sim:Advance(0.1)
	t.eq(#sent(sim, p, "FishingCast"), 1, "no cast while waiting")
	t.eq(#sent(sim, p, "FishingHook"), 0, "no hook while waiting (only cheaters hook early)")

	serverSays(sim, p, "Bite", { Window = 1.8 })
	t.eq(caption(sim, p), "ПОДСЕЧЬ!")
	t.eq(keyChip(sim, p), "F")
	t.ok(isCandy(button, UIConfig.Palette.Sun), "a Sun (orange) candy on bite")
	t.eq(alert.Visible, true, "bite alert")
	-- UI v2 (M1): a fish on the hook — «СМОТАТЬ» leaves (a slip off «ПОДСЕЧЬ!» must not cost it).
	sim:Advance(0.2)
	t.eq(stop.Visible, false, "no «СМОТАТЬ» during the bite")
	local timer = alert.Timer
	local full = timer.Size.X.Scale
	sim:Advance(0.9)
	t.near(timer.Size.X.Scale, full * (1 - 0.95 / 1.8), 0.05, "bite timer shrinks over Window")
	sim:ActivateTool(p) -- tap in the world
	sim:Advance(0.1)
	t.eq(#sent(sim, p, "FishingHook"), 1, "hook sent")
	t.eq(caption(sim, p), "ЖДЁМ…", "after the hook the button dims until the minigame (no double tap)")
	sim:Click(p, button)
	sim:Advance(0.1)
	pressF(sim, p)
	t.eq(#sent(sim, p, "FishingHook"), 1, "hook sent only once")

	serverSays(sim, p, "Minigame", MINIGAME)
	t.eq(caption(sim, p), "ЛОВИ!")
	t.eq(keyChip(sim, p), "F")
	t.ok(isCandy(button, UIConfig.Palette.Leaf), "a Leaf (green) candy while reeling")
	t.eq(alert.Visible, false, "bite alert gone")
	t.eq(gui(sim, p, "Minigame").Visible, true)
	t.eq(stop.Visible, false, "no «СМОТАТЬ» in the minigame either")

	-- The fish got away: a new cast; «СМОТАТЬ» is back while waiting and reels in.
	serverSays(sim, p, "Lost", { Reason = "timeout", Text = "" })
	sim:Advance(FishingConfig.CastCooldown + 0.1)
	pressF(sim, p)
	serverSays(sim, p, "Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = FishingConfig.CastFlightTime })
	sim:Advance(0.5)
	t.eq(stop.Visible, true, "«СМОТАТЬ» while waiting")
	t.ok(stop.AbsoluteSize.Y >= 44, `«СМОТАТЬ» is a full tap target ({stop.AbsoluteSize.Y} px)`)
	sim:Click(p, stop)
	sim:Advance(0.1)
	t.eq(#sent(sim, p, "FishingStop"), 1, "stop sent")
	t.eq(caption(sim, p), "ЖДЁМ…", "dim during CastCooldown (the server would refuse a cast)")
	pressF(sim, p)
	t.eq(#sent(sim, p, "FishingCast"), 2, "no cast request during CastCooldown")
	t.eq(gui(sim, p, "Minigame").Visible, false)
	t.eq(stop.Visible, false)
	serverSays(sim, p, "Idle", { Reason = "stop" })
	t.eq(gui(sim, p, "Hint").Text, "Леска смотана")
	sim:Advance(FishingConfig.CastCooldown)
	t.eq(caption(sim, p), "ЗАБРОСИТЬ", "back to «ЗАБРОСИТЬ» after CastCooldown")
	sim:AssertNoErrors({ warnings = true })
end

tests["console: R2 does the action and the key chip shows R2"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "console")
	equipRod(sim, p)
	t.eq(caption(sim, p), "ЗАБРОСИТЬ")
	t.eq(keyChip(sim, p), "R2")
	sim:PressKey(p, Enum.KeyCode.ButtonR2)
	sim:Advance(0.05)
	t.eq(#sent(sim, p, "FishingCast"), 1)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Minigame
--------------------------------------------------------------------------------

tests["minigame: title, pips, zone, needle and time bar follow the payload; taps carry elapsed, rate-limited"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	equipRod(sim, p)
	local rules = sim:Require(sim:Find("ReplicatedStorage.Shared.FishingRules"), p)
	local mini = gui(sim, p, "Minigame")
	local zone = mini.Track.Zone
	local needle = mini.Track.Needle
	local fill = mini.TimeBar.Fill
	local idleRender = renderSteppedCount(sim, p)

	local t0 = sim:Time()
	serverSays(sim, p, "Minigame", MINIGAME)
	t.eq(mini.Visible, true)
	t.eq(mini.Title.Text, "ЛЕГЕНДАРНАЯ РЫБА!")
	local titleKeys = mini.Title.TextFill.Color.Keypoints
	t.ok(
		colorNear(titleKeys[#titleKeys].Value, UIConfig.Rarity.Legendary.Top),
		"title in the rarity gradient (UI v2: white → rarity colour)"
	)
	t.eq(mini.Pips.Pip1.Visible, true)
	t.eq(mini.Pips.Pip2.Visible, true)
	t.eq(mini.Pips.Pip3.Visible, false, "only HitsNeeded pips")
	local pipColor = mini.Pips.Pip1.BackgroundColor3
	t.near(zone.Position.X.Scale, 0.7, 1e-6, "zone centre")
	t.near(zone.Size.X.Scale, 0.17, 1e-6, "zone width")
	t.ok(renderSteppedCount(sim, p) > idleRender, "needle animates on RenderStepped")

	sim:Advance(0.5)
	local elapsed = sim:Time() - t0
	t.near(needle.Position.X.Scale, rules.Needle(0.25, 1.25, elapsed), 0.03, "needle = FishingRules.Needle")
	t.near(fill.Size.X.Scale, 1 - elapsed / 12, 0.01, "time bar shrinks over Timeout")

	local pressedAt = sim:Time()
	pressF(sim, p)
	local taps = sent(sim, p, "FishingTap")
	t.eq(#taps, 1, "tap sent")
	local tapElapsed = taps[1].args[1]
	t.eq(type(tapElapsed), "number")
	t.near(tapElapsed, pressedAt - t0, 0.03, "elapsed since Minigame was received")
	pressF(sim, p)
	sim:Advance(0.05)
	pressF(sim, p)
	t.eq(#sent(sim, p, "FishingTap"), 1, "taps faster than TapInterval are not sent")
	sim:Advance(FishingConfig.TapInterval)
	pressF(sim, p)
	taps = sent(sim, p, "FishingTap")
	t.eq(#taps, 2, "next tap after TapInterval")
	t.ok(taps[2].args[1] - taps[1].args[1] >= FishingConfig.TapInterval - 1e-6, "taps spaced by TapInterval")

	serverSays(sim, p, "Zone", { ZoneCenter = 0.2, Hits = 1 })
	sim:Advance(0.3)
	t.near(zone.Position.X.Scale, 0.2, 1e-3, "zone moved")
	t.ok(colorNear(mini.Pips.Pip1.BackgroundColor3, roblox.Color3.fromRGB(64, 200, 96)), "first pip done")
	t.ok(colorNear(mini.Pips.Pip2.BackgroundColor3, pipColor), "second pip still to do")
	t.near(mini.Position.X.Scale, 0.5, 1e-6, "shake settles back")

	serverSays(sim, p, "Lost", { Reason = "miss", Text = "Мимо! Рыба сорвалась" })
	t.eq(mini.Visible, false, "minigame closed")
	t.eq(caption(sim, p), "ЖДЁМ…", "dim during CastCooldown")
	sim:Advance(0.8) -- UI v2: the hint comes once the miss ghost has left (they share the column)
	t.eq(gui(sim, p, "Hint").Text, "Мимо! Рыба сорвалась")
	t.eq(gui(sim, p, "Hint").Visible, true)
	t.eq(renderSteppedCount(sim, p), idleRender, "no RenderStepped while the minigame is hidden")
	sim:Advance(FishingConfig.CastCooldown)
	t.eq(caption(sim, p), "ЗАБРОСИТЬ")
	sim:AssertNoErrors({ warnings = true })
end

tests["minigame: garbage payloads are ignored safely"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	equipRod(sim, p)
	serverSays(sim, p, "Minigame", { Rarity = 5, U0 = 0 / 0, Speed = math.huge, HitsNeeded = 99, Timeout = -1 })
	sim:Advance(0.2)
	local mini = gui(sim, p, "Minigame")
	t.eq(mini.Visible, true)
	t.eq(mini.Pips.Pip5.Visible, true, "HitsNeeded clamped to the pips")
	local x = mini.Track.Needle.Position.X.Scale
	t.ok(x == x and x >= 0 and x <= 1, "needle stays on the track")
	serverSays(sim, p, 42, "nonsense")
	serverSays(sim, p, "Zone", "nonsense")
	serverSays(sim, p, "Caught", { Fish = { Id = 7 } })
	t.eq(gui(sim, p, "CatchCard").Visible, false, "no card for a broken fish")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Catch card and counter
--------------------------------------------------------------------------------

-- UI v2 (FUI-01): the card opens when the caught fish has landed over the head
-- (FishingFxController.OwnFishLanded; without a leap — the harness sends "Caught" without the
-- server's FishFx — LeapTime + 0.3 s) plus a per-rarity hold of at most 0.9 s.
local CARD_OPENS = FishingConfig.LeapTime + 0.3 + 1.0
-- After a tap skips the reveal the card ignores taps this long (FishingController CLIMAX.SkipDwell).
local SKIP_DWELL = 0.6

local function waitCard(sim: any, player: any): boolean
	local card = gui(sim, player, "CatchCard")
	return sim:WaitFor(function()
		return card.Visible
	end, CARD_OPENS + 0.5, 1 / 60) == true
end

-- (UI v2: the card opens after the leap, not on "Caught"; a tap during its reveal skips to the
-- end and the next one closes it; the counter keeps the previous number until the 🐟 flies in —
-- deliberate changes of the timing this test checked before.)
tests["catch card: opens after the fish lands; rarity, name, mutation, info, turning model; counter held; tap skips, then closes"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	equipRod(sim, p)
	local card = gui(sim, p, "CatchCard")
	local hud = sim:Gui(p, "HUD")
	local counter = sim:Gui(p, "HUD.Status.CatchCounter")
	t.eq(counter.Visible, false, "no catches yet")

	serverSays(sim, p, "Minigame", MINIGAME)
	p:SetAttribute("FishCaught", 1)
	serverSays(sim, p, "Caught", {
		Fish = { Id = "Perch", Rarity = "Common", Mutation = "Gold", Kg = 1.23, Value = 35, Income = 3.5 },
		Total = 1,
	})
	t.eq(gui(sim, p, "Minigame").Visible, false, "minigame closed by the catch")
	t.ok(gui(sim, p, "FxMinigameWin"), "…its copy plays the win")
	t.eq(card.Visible, false, "no card yet: the fish leaps first (the world is shown first)")
	t.eq(caption(sim, p), "ЖДЁМ…", "the action button is frozen meanwhile")
	t.eq(hud:GetAttribute("CounterHold"), 0, "the counter holds the previous number")
	t.eq(counter.Visible, false, "…so it stays hidden until the first 🐟 flies in")
	pressF(sim, p)
	t.eq(#sent(sim, p, "FishingCast"), 0, "the action does not cast while the catch is on screen")

	t.ok(waitCard(sim, p), "the card opens after the landing")
	t.ok(card.FxScale.Scale < 1, "card pops in")
	t.ok(isCandy(card.Banner, UIConfig.Rarity.Common), "banner in the rarity gradient")
	t.eq(card.Banner.RarityLabel.Text, "ОБЫЧНАЯ")
	t.eq(card.NameLabel.Text, "Окунь-полосатик")
	t.eq(card.MutationLabel.Visible, true)
	t.eq(card.MutationLabel.Text, "Золотая мутация ×2")
	t.ok(isCandy(card.MutationLabel, UIConfig.Mutations.Gold), "mutation stamp in the Gold style")
	t.eq(card.InfoLabel.Text, "1,2 кг · цена 35 💰")

	local model = card.Viewport:FindFirstChildOfClass("Model")
	t.ok(model, "fish model in the viewport")
	t.eq(model.Name, "Gold", "the mutation's model")
	t.ok(card.Viewport:FindFirstChildOfClass("Camera"), "viewport camera")
	local look = model:GetPivot().LookVector
	sim:Advance(0.5)
	t.near(card.FxScale.Scale, 1, 1e-3, "pop-in finished")
	t.ok(model:GetPivot().LookVector:Dot(look) < 0.999, "the fish turns")

	sim:Click(p, card)
	sim:Advance(0.05)
	t.eq(card.Visible, true, "a tap during the reveal skips to its end")
	t.eq(card.InfoLabel.Price.Label.Text, "35", "…the whole price at once")
	sim:Advance(0.15)
	sim:Click(p, card)
	sim:Advance(0.05)
	t.eq(card.Visible, true, "a double tap does not close it: the whole card stays SKIP_DWELL")
	sim:Advance(SKIP_DWELL)
	sim:Click(p, card)
	sim:Advance(0.05)
	t.eq(card.Visible, false, "the next tap closes the card")
	t.eq(card.Viewport:FindFirstChildOfClass("Model"), nil, "model removed")
	sim:Advance(0.9)
	t.eq(hud:GetAttribute("CounterHold"), nil, "the 🐟 flew in: the hold is released")
	t.eq(counter.Visible, true, "counter shown")
	t.eq(counter.Label.Text, "Улов: 1")
	t.eq(caption(sim, p), "ЗАБРОСИТЬ", "the button is back")
	t.eq(keyChip(sim, p), "F", "…with its F key chip")

	p:SetAttribute("FishCaught", 2)
	serverSays(sim, p, "Caught", {
		Fish = { Id = "DragonFish", Rarity = "Mythic", Kg = 14, Value = 2400, Income = 200 },
		Total = 2,
	})
	t.ok(waitCard(sim, p))
	t.eq(card.Banner.RarityLabel.Text, "МИФИЧЕСКАЯ")
	t.eq(card.NameLabel.Text, "Рыба-дракон")
	t.eq(card.MutationLabel.Visible, false, "no mutation stamp without a mutation")
	t.eq(card.InfoLabel.Text, "14 кг · цена 2400 💰")
	t.eq(card.Viewport:FindFirstChildOfClass("Model").Name, "Normal")
	t.eq(counter.Label.Text, "Улов: 1", "the counter still holds the previous number")
	pressF(sim, p)
	t.eq(card.Visible, true, "a trailing tap right after the card opens does nothing")
	sim:Advance(0.5)
	pressF(sim, p)
	t.eq(card.Visible, true, "the action skips the reveal…")
	t.eq(card.InfoLabel.Price.Label.Text, "2\u{00A0}400", "…the price with a thousands space")
	sim:Advance(0.2)
	pressF(sim, p)
	t.eq(card.Visible, true, "…a mashed F right after the skip leaves it up")
	sim:Advance(SKIP_DWELL)
	pressF(sim, p)
	t.eq(card.Visible, false, "…and then closes the card")
	t.eq(#sent(sim, p, "FishingCast"), 0, "...and does not cast")
	sim:Advance(0.9)
	t.eq(counter.Label.Text, "Улов: 2", "+1 when the 🐟 arrives")

	p:SetAttribute("FishCaught", 3)
	serverSays(sim, p, "Caught", { Fish = { Id = "Crucian", Rarity = "Common", Kg = 0.5, Value = 9 }, Total = 3 })
	t.ok(waitCard(sim, p))
	t.eq(card.InfoLabel.Text, "500 г · цена 9 💰")
	-- Closes by itself: UIConfig.CatchCardTime per rarity, never sooner than a second after its
	-- last beat (a new Common species: about 3.05 s — its beats are ≥ 0.25 s apart).
	sim:Advance(UIConfig.CatchCardTime.Common + 1.1)
	t.eq(card.Visible, false, "closes by itself")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Hints and the guide beam
--------------------------------------------------------------------------------

tests["hints: far → guide beam to the own FishingSpot, near → «Жми», Denied/Lost/Idle texts auto-hide"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local hint = gui(sim, p, "Hint")
	equipRod(sim, p, true)
	sim:Advance(0.3)
	t.eq(hint.Visible, true)
	t.eq(hint.Text, FishingConfig.Texts.Denied.far, "the same words as the server's refusal")
	t.eq(hint.Text, "Иди в сверкающий круг на краю пирса")
	local root = sim:GetRoot(p)
	local beam = root:FindFirstChild("FishingGuide")
	t.ok(beam and beam:IsA("Beam"), "guide beam from the character")
	t.eq(beam.Enabled, true)
	t.ok(beam.Attachment1.Parent == ownBase(sim, p).FishingSpot, "beam goes to the own FishingSpot")

	standAtSpot(sim, p)
	t.eq(hint.Text, "Жми «Забросить»")
	t.eq(beam.Enabled, false, "no guide at the spot")

	serverSays(sim, p, "Denied", { Reason = "far", Text = "Подойди к краю своего пирса" })
	t.eq(hint.Text, "Подойди к краю своего пирса")
	sim:Advance(HINT_TIME + 0.3)
	t.eq(hint.Text, "Жми «Забросить»", "event hint hides, the contextual one comes back")

	serverSays(sim, p, "Denied", { Reason = "cooldown", Text = "" })
	t.eq(hint.Text, "Жми «Забросить»", "empty Text shows nothing new")

	serverSays(sim, p, "Waiting", { Target = Vector3.new(0, 0, 0), FlightTime = 0.7 })
	sim:Advance(0.3)
	t.eq(hint.Visible, false, "no contextual hint while fishing")
	serverSays(sim, p, "Lost", { Reason = "late", Text = "Не успел подсечь!" })
	t.eq(hint.Text, "Не успел подсечь!")
	serverSays(sim, p, "Lost", { Reason = "timeout" })
	t.eq(
		hint.Text,
		"Время вышло — рыба ушла",
		"default text (shared with the server) when it sends none"
	)
	serverSays(sim, p, "Idle", { Reason = "moved" })
	t.match(hint.Text, "далеко от края пирса")
	serverSays(sim, p, "Idle", { Reason = "stop" })
	t.eq(hint.Text, "Леска смотана")

	-- Without the rod in hand at the own spot: «возьми удочку» and a button that takes it.
	sim:UnequipTools(p)
	sim:Advance(HINT_TIME + 0.3)
	t.eq(hint.Text, "Возьми удочку — кнопка справа")
	local button = gui(sim, p, "ActionArea.ActionButton")
	t.eq(button.Visible, true, "the button offers to take the rod")
	t.eq(caption(sim, p), "ВЗЯТЬ")
	sim:Click(p, button)
	sim:Advance(0.3)
	local inHand = p.Character:FindFirstChildOfClass("Tool")
	t.ok(inHand and inHand:GetAttribute("RodId") == "RodBamboo", "the rod is in hand")
	t.eq(caption(sim, p), "ЗАБРОСИТЬ")

	-- Away from the spot without the rod in hand: no button, no hint.
	sim:UnequipTools(p)
	sim:Teleport(p, ownBase(sim, p).SpawnPad.Position + Vector3.new(0, 5, 0))
	sim:Advance(0.5)
	t.eq(button.Visible, false, "no button away from the spot without the rod")
	t.eq(hint.Visible, false, "no hints away from the spot without the rod (the rod was taken before)")
	sim:AssertNoErrors({ warnings = true })
end

tests["newcomer: «where is the rod» hint until the rod is first taken"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	local hint = gui(sim, p, "Hint")
	giveRod(sim, p)
	sim:Advance(0.5)
	t.eq(hint.Visible, true)
	t.eq(hint.Text, FishingConfig.Texts.Denied.far, "UI v2 (M4): one name for the goal everywhere")
	t.eq(gui(sim, p, "ActionArea.ActionButton").Visible, false, "no button away from the spot")
	standAtSpot(sim, p)
	t.eq(hint.Text, "Возьми удочку — кнопка справа", "at the spot: take the rod")
	t.eq(caption(sim, p), "ВЗЯТЬ")
	sim:Click(p, gui(sim, p, "ActionArea.ActionButton"))
	sim:Advance(0.3)
	t.eq(caption(sim, p), "ЗАБРОСИТЬ", "the rod is in hand")
	t.eq(keyChip(sim, p), "", "phone: no key chip")
	t.eq(hint.Text, "Жми «Забросить»")
	sim:AssertNoErrors({ warnings = true })
end

tests["the «ВЗЯТЬ» button is not offered to a dead character"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	giveRod(sim, p)
	standAtSpot(sim, p)
	local button = gui(sim, p, "ActionArea.ActionButton")
	t.eq(button.Visible, true, "alive at the spot: «ВЗЯТЬ»")
	sim:GetHumanoid(p).Health = 0
	sim:Advance(0.5)
	t.eq(button.Visible, false, "dead: no button")
	sim:AssertNoErrors({ warnings = true })
end

tests["phone: a world tap (Tool.Activated, also fired by camera drags) never taps in the minigame"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	equipRod(sim, p)
	serverSays(sim, p, "Minigame", MINIGAME)
	sim:Advance(0.5)
	sim:ActivateTool(p)
	sim:Advance(0.1)
	t.eq(#sent(sim, p, "FishingTap"), 0, "Tool.Activated is ignored in the minigame on a touch screen")
	sim:Click(p, gui(sim, p, "ActionArea.ActionButton"))
	sim:Advance(0.05)
	local taps = sent(sim, p, "FishingTap")
	t.eq(#taps, 1, "the button taps (once: on touch down, not again on release)")

	-- The catch screen: a camera drag must not skip the reveal or close the card (the player
	-- turns the camera to look at the fish over the head).
	local card = gui(sim, p, "CatchCard")
	local price = card.InfoLabel.Price.Label
	p:SetAttribute("FishCaught", 1)
	serverSays(sim, p, "Caught", { Fish = { Id = "Crucian", Rarity = "Common", Kg = 0.5, Value = 9 }, Total = 1 })
	t.ok(waitCard(sim, p))
	sim:Advance(0.45)
	sim:ActivateTool(p)
	sim:Advance(0.05)
	t.eq(card.Visible, true, "a world drag on the catch screen does not close the card")
	t.eq(price.Text, "0", "…nor skip its reveal")
	sim:Click(p, card)
	sim:Advance(0.05)
	t.eq(price.Text, "9", "the card itself still skips")
	sim:Advance(SKIP_DWELL + 0.1)
	sim:ActivateTool(p)
	sim:Advance(0.05)
	t.eq(card.Visible, true, "…and a drag still does not close it")
	sim:Click(p, card)
	sim:Advance(1.5)
	t.eq(card.Visible, false)

	-- «К ПИРСУ» (far from the spot): walking there with drags does not re-fire the far warning.
	sim:Teleport(p, ownBase(sim, p).SpawnPad.Position + Vector3.new(0, 5, 0))
	sim:Advance(1)
	t.eq(caption(sim, p), "К ПИРСУ")
	local icon = gui(sim, p, "Hint.IconSocket.Icon")
	local before = icon.Text
	local button = gui(sim, p, "ActionArea.ActionButton")
	sim:ActivateTool(p)
	sim:Advance(0.05)
	t.eq(icon.Text, before, "the far hint is not re-fired by a drag")
	t.ok(button.FxScale.Scale > 0.99, "…and the button does not «press» itself")
	t.eq(#sent(sim, p, "FishingCast"), 0, "nothing is cast")
	sim:AssertNoErrors({ warnings = true })
end

tests["attribute safety net: FishingState back to Idle without an event resets the UI"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	equipRod(sim, p)
	p:SetAttribute("FishingState", "Waiting")
	serverSays(sim, p, "Waiting", { Target = Vector3.new(0, 0, 0), FlightTime = 0.7 })
	serverSays(sim, p, "Bite", { Window = 1.8 })
	t.eq(caption(sim, p), "ПОДСЕЧЬ!")
	p:SetAttribute("FishingState", "Idle")
	sim:Advance(0.1)
	t.eq(caption(sim, p), "ПОДСЕЧЬ!", "the event usually follows the attribute: the net waits for it")
	sim:Advance(0.5)
	t.eq(caption(sim, p), "ЖДЁМ…", "no event came: line in, dim during CastCooldown")
	sim:Advance(FishingConfig.CastCooldown)
	t.eq(caption(sim, p), "ЗАБРОСИТЬ")
	t.eq(gui(sim, p, "BiteAlert").Visible, false)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Respawn / unequip
--------------------------------------------------------------------------------

tests["unequip and respawn reset the fishing UI; no connections pile up"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	equipRod(sim, p)
	sim:Advance(0.3)
	local equippedConnections = sim:CountConnections(p)

	serverSays(sim, p, "Waiting", { Target = Vector3.new(0, 0, 0), FlightTime = 0.7 })
	serverSays(sim, p, "Bite", { Window = 1.8 })
	t.eq(gui(sim, p, "BiteAlert").Visible, true)
	sim:UnequipTools(p)
	sim:Advance(0.1)
	-- At the fishing spot without the rod in hand the button offers to take it again.
	t.eq(caption(sim, p), "ВЗЯТЬ", "the fishing look is gone: «ВЗЯТЬ» at the spot")
	t.eq(gui(sim, p, "ActionArea.StopButton").Visible, false)
	t.eq(gui(sim, p, "BiteAlert").Visible, false, "bite alert closed on unequip")
	local info = sim:Run(function()
		return sim:Env(p).game:GetService("ContextActionService"):GetBoundActionInfo("FishingAction")
	end, p)
	t.eq(next(info), nil, "F/R2 unbound without the rod")
	pressF(sim, p)
	t.eq(#sent(sim, p, "FishingCast"), 0, "F does nothing without the rod")

	sim:EquipTool(p, p.Backpack:FindFirstChildOfClass("Tool"))
	sim:Advance(0.1)
	t.eq(caption(sim, p), "ЖДЁМ…", "re-equipped within CastCooldown of the unequip")
	sim:Advance(FishingConfig.CastCooldown)
	t.eq(caption(sim, p), "ЗАБРОСИТЬ", "fresh state after re-equip")
	serverSays(sim, p, "Minigame", MINIGAME)
	t.eq(gui(sim, p, "Minigame").Visible, true)

	sim:KillCharacter(p)
	sim:Advance(0.1)
	t.eq(gui(sim, p, "ActionArea.ActionButton").Visible, false, "hidden as soon as the character dies")
	t.eq(gui(sim, p, "Minigame").Visible, false)
	sim:Advance(BaseConfig.RespawnDelay + 1)
	t.ok(sim:GetHumanoid(p) and sim:GetHumanoid(p).Health > 0, "respawned")
	t.eq(gui(sim, p, "ActionArea.ActionButton").Visible, false, "no rod on the new character yet")
	equipRod(sim, p)
	sim:Advance(0.3)
	t.eq(caption(sim, p), "ЗАБРОСИТЬ")
	t.eq(gui(sim, p, "ActionArea.ActionButton").Visible, true)
	t.eq(sim:CountConnections(p), equippedConnections, "same client connections as before the respawn")
	pressF(sim, p)
	t.eq(#sent(sim, p, "FishingCast"), 1, "casting works on the new character")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Bobbers and lines (FishingFxController)
--------------------------------------------------------------------------------

tests["bobber: another player's cast flies to BobberTarget, bites, reels and is reeled in after Idle"] = function(t)
	local sim = boot(t)
	local watcher = addPlayer(sim, 1)
	local fisher = addPlayer(sim, 2)
	local fx = controller(sim, watcher, "FishingFxController")
	local rod = equipRod(sim, fisher)
	standAtSpot(sim, fisher)
	t.eq(fx.GetBobber(fisher), nil, "no bobber while Idle")

	local spot = ownBase(sim, fisher).FishingSpot
	local out = spot.CFrame * CFrame.new(0, 0, -22)
	local target = Vector3.new(out.Position.X, 0, out.Position.Z)
	fisher:SetAttribute("BobberTarget", target)
	fisher:SetAttribute("CastTime", sim.workspace:GetServerTimeNow())
	fisher:SetAttribute("FishingState", "Waiting")
	sim:Advance(0.05)

	local bobber = fx.GetBobber(fisher)
	t.ok(bobber, "bobber created for the other player")
	t.eq(bobber.Parent.Name, "FishingFx")
	t.ok(bobber.Parent.Parent == sim.workspace, "client folder in the Workspace")
	local line = bobber:FindFirstChild("Line")
	t.ok(line and line:IsA("Beam"), "fishing line")
	t.ok(line.Attachment0 == rod.Handle.TipAttachment, "line starts at the rod tip")
	t.ok(line.Attachment1 == bobber.Root.LineAttachment, "line ends at the bobber")
	t.eq(line.Enabled, true)
	local rest = target + Vector3.new(0, bobber:GetAttribute("FloatDepth"), 0)

	sim:Advance(FishingConfig.CastFlightTime / 2 - 0.05)
	local tip = rod.Handle.TipAttachment.WorldPosition
	local mid = bobber:GetPivot().Position
	t.ok(mid.Y > (tip.Y + rest.Y) / 2 + 1, "flies along an arc")

	sim:Advance(FishingConfig.CastFlightTime / 2 + 0.3)
	t.near(bobber:GetPivot().Position, rest, 0.2, "floats at the target, waterline on the water")

	fisher:SetAttribute("FishingState", "Bite")
	sim:Advance(0.2)
	t.eq(bobber.Root.BiteAlert.Enabled, true, "«!» over the bobber on a bite")
	t.ok(bobber.Root:FindFirstChildOfClass("ParticleEmitter"), "splash emitter")

	fisher:SetAttribute("FishingState", "Reeling")
	sim:Advance(1)
	t.eq(bobber.Root.BiteAlert.Enabled, false)
	local reel = bobber:GetPivot().Position
	t.ok((reel - rest).Magnitude > 0.05, "thrashes / is drawn in while reeling")

	-- every client draws the bobber (both the watcher's and the fisher's own)
	local copies = 0
	for _, folder in sim.workspace:GetChildren() do
		if folder.Name == "FishingFx" and folder:FindFirstChild(`Bobber_{fisher.UserId}`) then
			copies += 1
		end
	end
	t.eq(copies, 2, "one bobber per client")

	fisher:SetAttribute("FishingState", "Idle")
	sim:Advance(0.1)
	t.ok(fx.GetBobber(fisher) ~= nil, "still reeling in")
	sim:Advance(RETRACT_TIME + 0.2)
	t.eq(fx.GetBobber(fisher), nil, "removed after the reel-in")
	t.eq(bobber.Parent, nil, "bobber destroyed")
	for _, folder in sim.workspace:GetChildren() do
		if folder.Name == "FishingFx" then
			t.eq(#folder:GetChildren(), 0, "nothing left in FishingFx")
		end
	end
	t.eq(renderSteppedCount(sim, watcher), 0, "no per-frame work without active bobbers")
	sim:AssertNoErrors({ warnings = true })
end

tests["bobber: a late joiner sees a bobber already on the water"] = function(t)
	local sim = boot(t)
	local fisher = addPlayer(sim, 1)
	equipRod(sim, fisher, true)
	fisher:SetAttribute("BobberTarget", Vector3.new(10, 0, 10))
	fisher:SetAttribute("CastTime", sim.workspace:GetServerTimeNow())
	fisher:SetAttribute("FishingState", "Waiting")
	sim:Advance(2)
	local late = addPlayer(sim, 2)
	local fx = controller(sim, late, "FishingFxController")
	sim:Advance(0.1)
	local bobber = fx.GetBobber(fisher)
	t.ok(bobber, "bobber exists for the late joiner")
	t.near(bobber:GetPivot().Position, Vector3.new(10, 0.6, 10), 0.2, "already floating, no flight replay")
	sim:AssertNoErrors({ warnings = true })
end

tests["leaks: a leaving player's bobber and connections disappear from other clients"] = function(t)
	local sim = boot(t)
	local watcher = addPlayer(sim, 1)
	sim:Advance(0.5)
	local baseline = sim:CountConnections(watcher)
	local fisher = addPlayer(sim, 2)
	local fx = controller(sim, watcher, "FishingFxController")
	equipRod(sim, fisher, true)
	fisher:SetAttribute("BobberTarget", Vector3.new(0, 0, 30))
	fisher:SetAttribute("CastTime", sim.workspace:GetServerTimeNow())
	fisher:SetAttribute("FishingState", "Bite")
	sim:Advance(0.5)
	local bobber = fx.GetBobber(fisher)
	t.ok(bobber, "bobber while fishing")
	t.ok(connectionsAbout(sim, watcher, fisher.Name) > 0, "watcher follows the fisher's attributes")
	t.ok(sim:CountConnections(watcher) > baseline)

	sim:RemovePlayer(fisher)
	sim:Advance(0.2)
	t.eq(connectionsAbout(sim, watcher, fisher.Name), 0, "no connections about the player who left")
	t.eq(sim:CountConnections(watcher), baseline, "watcher back to its baseline")
	t.eq(sim:CountConnections(fisher), 0, "the leaver's client is gone")
	t.eq(fx.GetBobber(fisher), nil)
	t.eq(bobber.Parent, nil, "bobber destroyed")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Rainbow fish
--------------------------------------------------------------------------------

tests["rainbow fish: tagged models in the world and in the catch card shimmer; templates stay put"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local template = sim:Find("ReplicatedStorage.Assets.Fish.Perch.Rainbow")
	local fish = template:Clone()
	fish.Parent = sim.workspace
	sim:Advance(0.1)

	local part, templatePart
	for _, d in fish:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("RainbowU") ~= nil then
			part = d
			templatePart = template:FindFirstChild(d.Name, true)
			break
		end
	end
	t.ok(part, "a rainbow part")
	local function clientColor(target: any): any
		return sim:Run(function()
			return target.Color
		end, p)
	end
	local c1 = clientColor(part)
	sim:Advance(0.5)
	local c2 = clientColor(part)
	t.ok(not colorNear(c1, c2, 0.02), "colour changes over time")
	local _, s, v = c2:ToHSV()
	t.near(s, 0.72, 0.02, "saturation from the formula")
	t.near(v, 0.55 + 0.45 * part:GetAttribute("RainbowV"), 0.02, "brightness from RainbowV")
	t.ok(colorNear(clientColor(templatePart), templatePart.Color), "the ReplicatedStorage template is not animated")

	fish:Destroy()
	sim:Advance(0.1)
	local gone = clientColor(part)
	sim:Advance(0.5)
	t.ok(colorNear(clientColor(part), gone), "no more recolouring once the model left the DataModel")

	-- the same model in the catch card's ViewportFrame
	equipRod(sim, p)
	serverSays(sim, p, "Caught", {
		Fish = { Id = "Perch", Rarity = "Common", Mutation = "Rainbow", Kg = 1, Value = 120 },
		Total = 1,
	})
	local card = gui(sim, p, "CatchCard")
	t.ok(waitCard(sim, p), "the card opens after the landing")
	t.eq(card.MutationLabel.Text, "Радужная мутация ×5")
	local cardFish = card.Viewport:FindFirstChildOfClass("Model")
	t.eq(cardFish.Name, "Rainbow")
	local cardPart = cardFish:FindFirstChild(part.Name, true)
	local before = cardPart.Color
	sim:Advance(0.5)
	t.ok(not colorNear(before, cardPart.Color, 0.02), "the card's fish shimmers too")
	sim:AssertNoErrors({ warnings = true })
end

return tests
