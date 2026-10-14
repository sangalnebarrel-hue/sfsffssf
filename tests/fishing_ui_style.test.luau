--[[
	The fishing UI in the "Candy Splash" style (tools/builder/gui/Fishing.luau + FishingController,
	look and rules: tools/builder/gui/STYLE.md §3 / §6.5) in RbxSim against the built Place1.rbxl:
	  • the parts: every widget is a candy (or a candy-styled bar) with the documented decorations;
	  • each state's look: the action button per state (Sky / Slate / Sun / Leaf / Gold, icon,
	    ring), the bite alert (slam, rays, flash, draining timer), the minigame (rarity title,
	    trail under the zone, hit juice: «ОТЛИЧНО!» / «СУПЕР!» / «ИДЕАЛЬНО!», stamped stars,
	    sparks), the miss ghost («МИМО!»), the catch card per rarity (dim, rays, pop-in with a
	    turn, «НОВАЯ!», count-up, confetti; Legendary/Mythic: flash, second ring, rainbow), the
	    mutation badge effects and the hint pill by kind;
	  • effects start and are cleaned up: no Fx* instances left after a full catch/close and after
	    a miss, no frame effect (RenderStepped/Heartbeat) running while idle, connection counts
	    back to their baseline;
	  • the layout fits on a phone, a tablet and a desktop: nothing overlaps the status stack, the
	    Home button, the hotbar, the thumbstick or the Jump button, and the widgets do not overlap
	    each other.
	The server's FishingService is switched off (like tests/stage2_client.test.luau): the harness
	plays the server and fires FishingState itself.

	Run: lune run tools/run_tests.luau fishing_ui_style
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3

local INSET = 58 -- RbxSim's top bar inset for ScreenGuis without IgnoreGuiInset
local HOTBAR_TOP = 65 -- the Roblox hotbar: 60 px slots, 5..65 px above the bottom

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
local FishingConfig = loadConfig("FishingConfig")
local Palette = UIConfig.Palette

local CATCHES = {
	Common = { Id = "Crucian", Rarity = "Common", Kg = 0.84, Value = 11, Income = 1.1 },
	Rare = { Id = "Puffer", Rarity = "Rare", Kg = 2.1, Value = 58, Income = 5.2 },
	Legendary = { Id = "SharkPup", Rarity = "Legendary", Kg = 27.3, Value = 590, Income = 52 },
	Mythic = { Id = "DragonFish", Rarity = "Mythic", Kg = 14.2, Value = 2400, Income = 200 },
}

--------------------------------------------------------------------------------
-- Harness
--------------------------------------------------------------------------------

local function boot(t: any): any
	local sim = t.sim({ place = t.place })
	sim:Find("ServerScriptService.Services.FishingService").Source = "return {}"
	sim:StartServer()
	sim:Advance(0.5)
	return sim
end

local function addPlayer(sim: any, id: number, device: string?): any
	local p = sim:AddPlayer({ UserId = id, Name = `Ui{id}`, device = device or "desktop" })
	sim:Advance(1)
	return p
end

local function giveRod(sim: any, p: any): any
	local template = sim:Find("ReplicatedStorage.Assets.Rods.RodBamboo")
	local rod = template:Clone()
	rod.Name = template:GetAttribute("DisplayName")
	rod.Parent = p:FindFirstChildOfClass("Backpack")
	p:SetAttribute("RodId", "RodBamboo")
	p:SetAttribute("FishingState", "Idle")
	p:SetAttribute("FishCaught", 0)
	sim:Advance(0.05)
	return rod
end

local function standAtSpot(sim: any, p: any)
	local base = sim.workspace.Bases:FindFirstChild(`Base_{p:GetAttribute("BaseIndex")}`)
	sim:Teleport(p, base.FishingSpot.CFrame.Position + Vector3.new(0, 3, 0))
	sim:Advance(0.3)
end

-- Rod in hand at the own fishing spot.
local function ready(sim: any, p: any): any
	local rod = giveRod(sim, p)
	standAtSpot(sim, p)
	sim:EquipTool(p, rod)
	sim:Advance(0.3)
	return rod
end

local function fishing(p: any): any
	return p.PlayerGui.HUD.Fishing
end

local function serverSays(sim: any, p: any, state: string, data: any?)
	sim:Find("ReplicatedStorage.Remotes.FishingState"):FireClient(p, state, data)
	sim:Advance(0.05)
end

local function pressF(sim: any, p: any)
	sim:PressKey(p, Enum.KeyCode.F)
	sim:Advance(0.02)
end

local function minigame(rarity: string, extra: { [string]: any }?): { [string]: any }
	local rule = FishingConfig.Minigame[rarity]
	local data = {
		Rarity = rarity,
		U0 = 0.1,
		Speed = rule.Speed,
		ZoneCenter = 0.6,
		ZoneWidth = rule.ZoneWidth,
		Hits = 0,
		HitsNeeded = rule.Hits,
		Timeout = FishingConfig.MinigameTimeout,
	}
	for key, value in extra or {} do
		data[key] = value
	end
	return data
end

-- The catch: "Caught" with the fish and the counter attribute, like FishingService.
local function catch(sim: any, p: any, fish: { [string]: any }, total: number)
	p:SetAttribute("FishCaught", total)
	serverSays(sim, p, "Caught", { Fish = fish, Total = total })
end

local function uiFx(sim: any, p: any): any
	return sim:Require(sim:Find("ReplicatedStorage.Shared.UiFx"), p)
end

local function colorNear(a: any, b: any, eps: number?): boolean
	local e = eps or 0.01
	return math.abs(a.R - b.R) <= e and math.abs(a.G - b.G) <= e and math.abs(a.B - b.B) <= e
end

-- The candy shows a style (palette token / rarity / mutation): face gradient and lip.
local function isCandy(root: any, style: any): boolean
	local face = root:FindFirstChild(root:GetAttribute("CandyFace") or "Face")
	local keys = face.Fill.Color.Keypoints
	return colorNear(keys[1].Value, style.Top)
		and colorNear(keys[#keys].Value, style.Bottom)
		and colorNear(root.Lip.BackgroundColor3, style.Lip)
end

local function checkCandy(t: any, root: any, what: string)
	local faceName = root:GetAttribute("CandyFace")
	t.ok(type(faceName) == "string", `{what}: CandyFace attribute`)
	t.eq(root.BackgroundTransparency, 1, `{what}: transparent root`)
	local lip, face = root:FindFirstChild("Lip"), root:FindFirstChild(faceName)
	t.ok(lip and face, `{what}: Lip and {faceName}`)
	t.ok(lip.ZIndex < face.ZIndex, `{what}: the lip is behind the face`)
	local outline = lip:FindFirstChildOfClass("UIStroke")
	t.ok(outline and colorNear(outline.Color, UIConfig.Ink), `{what}: Ink outline on the lip`)
	t.ok(type(outline:GetAttribute("BaseThickness")) == "number", `{what}: outline fitted to the screen`)
	local fill = face:FindFirstChild("Fill")
	t.ok(fill and fill:IsA("UIGradient"), `{what}: Fill gradient`)
	t.ok(face:FindFirstChild("Gloss"), `{what}: Gloss`)
end

-- Every effect instance (Fx*) under the player's GUI, except the persistent FxScale UIScales.
local function leftovers(p: any): { string }
	local found = {}
	for _, d in p.PlayerGui:GetDescendants() do
		if string.sub(d.Name, 1, 2) == "Fx" and d.Name ~= "FxScale" then
			table.insert(found, d:GetFullName())
		end
	end
	return found
end

local function count(root: any, name: string): number
	local n = 0
	for _, d in root:GetDescendants() do
		if d.Name == name then
			n += 1
		end
	end
	return n
end

local function frameConnections(sim: any, p: any): number
	local ctx = sim:ContextName(p)
	return sim:CountConnections(function(conn: any)
		local what = conn.signal:describe()
		return conn.ctx.name == ctx
			and (string.find(what, "RenderStepped", 1, true) ~= nil or string.find(what, "Heartbeat", 1, true) ~= nil)
	end)
end

local tests = {}

--------------------------------------------------------------------------------
-- Parts
--------------------------------------------------------------------------------

tests["parts: the fishing widgets are candies with their decorations; text never too small"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local f = fishing(p)
	local area = f.ActionArea

	checkCandy(t, area.ActionButton, "ActionButton")
	t.ok(isCandy(area.ActionButton, Palette.Gold), "ActionButton: painted with the «ВЗЯТЬ» look (no rod)")
	t.ok(area.ActionButton.Ring:IsA("UIStroke"), "ActionButton.Ring halo")
	t.eq(area.ActionButton:GetAttribute("CandyRadius"), 0.5, "a round button")
	checkCandy(t, area.ActionButton.CaptionRibbon, "CaptionRibbon")
	t.ok(area.ActionButton.Caption.ZIndex > area.ActionButton.CaptionRibbon.ZIndex, "caption over its ribbon")
	t.ok(area.ActionButton.Caption:FindFirstChild("Outline"), "outlined caption")
	checkCandy(t, area.StopButton, "StopButton")
	t.ok(isCandy(area.StopButton, Palette.Berry), "StopButton: a Berry pill")
	t.eq(area.StopButton.Icon.Text, "🧵")

	local alert = f.BiteAlert
	checkCandy(t, alert, "BiteAlert")
	t.ok(isCandy(alert, Palette.Sun), "BiteAlert: Sun")
	t.eq(alert.Label.Text, "КЛЮЁТ!")
	t.ok(alert.Label:FindFirstChild("TextFill") and alert.Label:FindFirstChild("Outline"), "gradient, outlined title")
	t.eq(alert.IconLeft.Text, "❗")
	t.eq(alert.IconRight.Text, "❗")
	t.ok(alert.TimerTrack.ZIndex < alert.Timer.ZIndex, "the timer bar sits on its track")

	local mini = f.Minigame
	checkCandy(t, mini, "Minigame")
	t.ok(isCandy(mini, Palette.Night), "Minigame: a Night panel")
	t.ok(mini.Title:FindFirstChild("TextFill") and mini.Title:FindFirstChild("Outline"), "rarity-gradient title")
	for i = 1, 5 do
		t.eq(mini.Pips[`Pip{i}`].Star.Text, "⭐", `Pip{i} has a star`)
	end
	local track, zone, needle = mini.Track, mini.Track.Zone, mini.Track.Needle
	checkCandy(t, zone, "Zone")
	t.ok(isCandy(zone, Palette.Leaf), "Zone: a glossy Leaf candy")
	t.ok(zone.Glow.ZIndex < zone.Lip.ZIndex, "the zone's glow is behind it")
	t.ok(zone.Flash.ZIndex > zone.Face.ZIndex, "hit flash over the zone")
	t.ok(needle.ZIndex > zone.ZIndex, "the needle is drawn over the zone")
	t.ok(needle:FindFirstChildOfClass("UICorner") and needle:FindFirstChildOfClass("UIStroke"), "a candy capsule")
	t.ok(needle.Size.X.Scale <= 0.03, "the needle stays thin (the e2e bot aims with its width)")
	t.ok(track:FindFirstChildOfClass("UIStroke"), "outlined track")
	t.ok(mini.TimeBar.Fill:FindFirstChild("Gloss"), "glossy time bar")

	checkCandy(t, f.Hint, "Hint")
	t.ok(isCandy(f.Hint, Palette.Night), "Hint: a Night pill")
	t.eq(f.Hint.TextTransparency, 1, "Hint.Text is the value, Hint.Label shows it")

	local card = f.CatchCard
	checkCandy(t, card, "CatchCard")
	t.ok(isCandy(card, Palette.Cream), "CatchCard: a Cream card")
	checkCandy(t, card.Banner, "Banner")
	checkCandy(t, card.MutationLabel, "MutationLabel")
	checkCandy(t, card.NewStamp, "NewStamp")
	checkCandy(t, card.InfoLabel.Weight, "Weight chip")
	checkCandy(t, card.InfoLabel.Price, "Price chip")
	t.ok(isCandy(card.InfoLabel.Price, Palette.Gold), "price on a Gold chip")
	t.ok(card.FishGlow.ZIndex < card.Viewport.ZIndex, "the glow is behind the fish")
	t.ok(card.NameLabel:FindFirstChild("Outline") and card.NameLabel:FindFirstChild("TextFill"), "big outlined name")

	-- Z order inside HUD.Fishing: dim < rays < action area < card; the dim never takes input.
	t.ok(f.CatchDim.ZIndex < f.CatchRays.ZIndex, "rays above the dim")
	t.ok(f.CatchRays.ZIndex < card.ZIndex, "the card above its rays")
	t.ok(f.ActionArea.ZIndex > f.CatchDim.ZIndex, "the action button is not dimmed (it closes the card too)")
	t.eq(f.CatchDim.Active, false, "the dim does not sink input")

	-- Text: every scaled label (not the emoji icons) has a size constraint, never below 9 px.
	local icons = { Icon = true, IconLeft = true, IconRight = true, Star = true, StarLeft = true, StarRight = true }
	for _, d in f:GetDescendants() do
		if d:IsA("TextLabel") and d.TextScaled and d.TextTransparency < 1 then
			local constraint = d:FindFirstChildOfClass("UITextSizeConstraint")
			if not icons[d.Name] then
				t.ok(constraint, `{d:GetFullName()}: UITextSizeConstraint`)
				if constraint then
					t.ok(constraint.MinTextSize >= 9, `{d:GetFullName()}: min text {constraint.MinTextSize}`)
				end
			end
		end
	end
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Action button states
--------------------------------------------------------------------------------

tests["action button: a look per state (Take, Cast, Wait, Bite, Reel), pop on change, ripple on tap"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	local button = fishing(p).ActionArea.ActionButton
	local rod = giveRod(sim, p)
	standAtSpot(sim, p)

	-- «ВЗЯТЬ»: Gold, the ring lit gold, glow rings call the player.
	t.eq(button.Visible, true)
	t.eq(button.Caption.Text, "ВЗЯТЬ")
	t.ok(isCandy(button, Palette.Gold), "«ВЗЯТЬ» is a Gold candy")
	t.ok(button.Ring.Transparency < 0.5, "the ring is lit")
	sim:Advance(1.4)
	t.ok(count(button, "FxRing") > 0, "gold glow rings while «ВЗЯТЬ» waits")

	-- «ЗАБРОСИТЬ»: Sky 🎣, the button pops in when the rod comes into the hand.
	sim:EquipTool(p, rod)
	sim:Advance(0.05)
	t.eq(button.Caption.Text, "ЗАБРОСИТЬ")
	t.ok(isCandy(button, Palette.Sky), "Sky while ready to cast")
	t.eq(button.Icon.Text, "🎣")
	t.ok(button.FxScale.Scale < 1, "pops in")
	sim:Advance(0.6)
	t.near(button.FxScale.Scale, 1, 1e-3, "settles")

	-- A tap: ripple + squash; «ЖДЁМ…»: Slate ⏳ that flips.
	sim:Click(p, button)
	sim:Advance(0.05)
	t.ok(count(button, "FxRing") > 0, "a ripple on the tap")
	t.eq(button.Caption.Text, "ЖДЁМ…")
	t.ok(isCandy(button, Palette.Slate), "Slate while waiting")
	t.eq(button.Icon.Text, "⏳")
	serverSays(sim, p, "Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
	local rest = button.Icon.Rotation
	sim:Advance(1.4)
	t.ok(math.abs(button.Icon.Rotation - rest) > 90, "the hourglass flips")
	t.ok(fishing(p).ActionArea.StopButton.Visible, "«СМОТАТЬ» while the line is out")

	-- «ПОДСЕЧЬ!»: Sun ❗, white halo, pulse and glow rings.
	serverSays(sim, p, "Bite", { Window = 1.8 })
	sim:Advance(0.5)
	t.eq(button.Caption.Text, "ПОДСЕЧЬ!")
	t.ok(isCandy(button, Palette.Sun), "Sun on the bite")
	t.eq(button.Icon.Text, "❗")
	t.ok(button.Ring.Transparency < 0.1, "white halo")
	t.ok(count(button, "FxRing") > 0, "glow rings")
	local scales = {}
	for _ = 1, 6 do
		sim:Advance(0.07)
		table.insert(scales, button.FxScale.Scale)
	end
	t.ok(math.max(table.unpack(scales)) - math.min(table.unpack(scales)) > 0.02, "the button pulses")
	t.near(button.Icon.Rotation, rest, 1e-3, "the hourglass is back at rest")

	-- Hook: dims until the minigame; «ТЯНИ!»: Leaf 💪.
	sim:Click(p, button)
	sim:Advance(0.3)
	t.ok(isCandy(button, Palette.Slate), "dim after the hook")
	t.near(button.FxScale.Scale, 1, 1e-3, "the pulse stopped with the hook")
	serverSays(sim, p, "Minigame", minigame("Common"))
	t.eq(button.Caption.Text, "ТЯНИ!")
	t.ok(isCandy(button, Palette.Leaf), "Leaf while reeling")
	t.eq(button.Icon.Text, "💪")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Bite alert
--------------------------------------------------------------------------------

tests["bite alert: slams in with a Sun flash and rays, the timer drains green → red, all gone after"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local alert = fishing(p).BiteAlert
	local timer = alert.Timer
	local full = timer.Size.X.Scale
	serverSays(sim, p, "Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
	local idleFrames = frameConnections(sim, p)

	serverSays(sim, p, "Bite", { Window = 1.8 })
	t.eq(alert.Visible, true)
	t.ok(alert.FxScale.Scale > 1.2, `slams in from big ({alert.FxScale.Scale})`)
	t.ok(p.PlayerGui.HUD:FindFirstChild("FxFlash"), "a quick flash")
	t.ok(alert:FindFirstChild("FxRays"), "rays behind the alert")
	t.eq(alert.FxRays.ZIndex, 0, "the rays are behind the candy")
	t.ok(colorNear(timer.BackgroundColor3, Palette.Leaf.Top, 0.05), "the timer starts green")
	sim:Advance(0.5)
	t.near(alert.FxScale.Scale, 1, 0.08, "settled (and pulsing gently)")
	t.eq(p.PlayerGui.HUD:FindFirstChild("FxFlash"), nil, "the flash is short")
	local wiggled = false
	for _ = 1, 22 do
		sim:Advance(0.05)
		if math.abs(alert.IconLeft.Rotation + 14) > 2 or math.abs(alert.IconRight.Rotation - 14) > 2 then
			wiggled = true
		end
	end
	t.ok(wiggled, "the ❗ wiggle")
	t.ok(timer.Size.X.Scale < full * 0.2, "the timer drained")
	t.ok(timer.BackgroundColor3.R > timer.BackgroundColor3.G, "…and turned red")

	pressF(sim, p)
	serverSays(sim, p, "Minigame", minigame("Rare"))
	t.eq(alert.Visible, false)
	t.eq(alert:FindFirstChild("FxRays"), nil, "rays removed with the alert")
	t.near(timer.Size.X.Scale, full, 1e-6, "the timer is reset")
	serverSays(sim, p, "Lost", { Reason = "timeout", Text = "" })
	sim:Advance(1.2)
	t.eq(frameConnections(sim, p), idleFrames, "no frame work left after the bite and the minigame")
	t.eq(#leftovers(p), 0, `no effect instances left: {table.concat(leftovers(p), ", ")}`)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Minigame
--------------------------------------------------------------------------------

tests["minigame: rarity title, needle trail under the zone, hit juice: ИДЕАЛЬНО / СУПЕР / ОТЛИЧНО"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local mini = fishing(p).Minigame
	local track, zone, needle = mini.Track, mini.Track.Zone, mini.Track.Needle
	local button = fishing(p).ActionArea.ActionButton

	-- A slow needle right at the zone centre: the first tap is perfect.
	serverSays(sim, p, "Minigame", minigame("Legendary", { U0 = 0.5, Speed = 0.05, ZoneCenter = 0.5, HitsNeeded = 3 }))
	t.eq(mini.Visible, true)
	local fill = mini.Title.TextFill
	t.ok(colorNear(fill.Color.Keypoints[1].Value, UIConfig.Rarity.Legendary.Top), "Legendary gradient title")
	sim:Advance(0.5) -- the pips and the zone have popped in
	local ghosts = 0
	for _, c in track:GetChildren() do
		if c.Name == "FxGhost" then
			ghosts += 1
			t.ok(c.ZIndex < zone.ZIndex, "the trail passes UNDER the zone")
		end
	end
	t.eq(ghosts, 3, "three ghost copies trail the needle")
	t.ok(needle.ZIndex > zone.ZIndex, "the needle over the zone")
	t.eq(mini.Pips.Pip1.Star.TextTransparency > 0.5, true, "pips start as ghost stars")

	pressF(sim, p)
	serverSays(sim, p, "Zone", { ZoneCenter = 0.15, Hits = 1 })
	local float = mini:FindFirstChild("FxFloat")
	t.ok(float, "a float text over the panel")
	t.eq(float.Text, "ИДЕАЛЬНО!", "a tap at the zone centre is perfect")
	t.ok(float.Position.Y.Scale < 0, "the float text is above the panel (never over the needle or zone)")
	local burst = mini:FindFirstChild("FxBurst")
	t.ok(burst, "sparks burst from the zone")
	t.ok(burst.ZIndex < track.ZIndex, "…from behind the track")
	t.ok(zone.FxScale.Scale < 1, "the zone pops in at its new place")
	t.near(zone.Position.X.Scale, 0.15, 1e-6, "the zone jumped (no slide)")
	t.ok(mini.Pips.Pip1.Star.FxScale.Scale > 1, "the star is stamped")
	t.eq(mini.Pips.Pip1.Star.TextTransparency, 0)
	t.ok(button.FxScale.Scale > 1, "the button bumps")
	sim:Advance(0.9)
	t.eq(mini:FindFirstChild("FxFloat"), nil, "float gone")
	t.eq(mini:FindFirstChild("FxBurst"), nil, "sparks gone")
	t.near(zone.FxScale.Scale, 1, 1e-3)

	-- Second hit, away from the centre: «СУПЕР!».
	pressF(sim, p)
	serverSays(sim, p, "Zone", { ZoneCenter = 0.8, Hits = 2 })
	t.eq(mini.FxFloat.Text, "СУПЕР!", "the second hit")
	sim:Advance(1)

	-- A fresh minigame, a hit without a perfect tap: «ОТЛИЧНО!».
	serverSays(sim, p, "Minigame", minigame("Epic"))
	t.eq(count(mini, "FxGhost"), 3, "the old trail is gone, a new one follows the needle")
	serverSays(sim, p, "Zone", { ZoneCenter = 0.2, Hits = 1 })
	t.eq(mini.FxFloat.Text, "ОТЛИЧНО!", "the first hit")

	-- Mythic: the title runs a rainbow (a frame effect that stops with the minigame).
	serverSays(sim, p, "Minigame", minigame("Mythic"))
	local before = mini.Title.TextFill.Color.Keypoints[1].Value
	sim:Advance(0.4)
	t.ok(not colorNear(before, mini.Title.TextFill.Color.Keypoints[1].Value, 0.02), "the Mythic title runs a rainbow")
	sim:AssertNoErrors({ warnings = true })
end

tests["miss: the minigame closes at once, its ghost flashes red with «МИМО!», then nothing is left"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local f = fishing(p)
	local idleFrames = frameConnections(sim, p)
	local idleConnections = sim:CountConnections(p)
	local UiFx = uiFx(sim, p)

	serverSays(sim, p, "Minigame", minigame("Rare", { ZoneCenter = 0.8, U0 = 0.05 }))
	sim:Advance(0.3)
	pressF(sim, p)
	serverSays(sim, p, "Lost", { Reason = "miss", Text = "Мимо! Рыба сорвалась" })
	t.eq(f.Minigame.Visible, false, "the real minigame is hidden at once")
	local ghost = f:FindFirstChild("FxMinigameMiss")
	t.ok(ghost and ghost.Visible, "a ghost copy plays the miss")
	t.ok(ghost:FindFirstChild("FxFloat") and ghost.FxFloat.Text == "МИМО!", "«МИМО!»")
	t.ok(ghost.Track:FindFirstChild("FxMissFlash"), "a red flash on the track")
	t.ok(isCandy(ghost.Track.Zone, Palette.Berry), "the ghost's zone turns red")
	t.eq(f.Hint.Visible, true)
	t.eq(f.Hint.Label.Text, "Мимо! Рыба сорвалась", "the hint shows the reason")
	t.eq(f.Hint.Icon.Text, "⚠️", "a warning hint")
	t.eq(UiFx.activeJobs(), 0, "the ghost runs on timers only")

	sim:Advance(1.2)
	t.eq(f:FindFirstChild("FxMinigameMiss"), nil, "the ghost is gone")
	t.eq(#leftovers(p), 0, `no effect instances left: {table.concat(leftovers(p), ", ")}`)
	t.eq(frameConnections(sim, p), idleFrames, "no frame connection left")
	sim:Advance(4) -- the hint and the cast cooldown are over
	t.eq(sim:CountConnections(p), idleConnections, "back to the idle connection count")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Catch (UI v2, FUI-01…12: the world first, then the card; tiers; beats; skip; exit)
--------------------------------------------------------------------------------

-- The card opens when the fish has landed over the head (FishingFxController.OwnFishLanded;
-- without a leap — here "Caught" comes without the server's FishFx — LeapTime + 0.3 s) plus a
-- per-rarity hold (at most 0.55 s).
local CARD_OPENS = FishingConfig.LeapTime + 0.3 + 0.6

local function waitFor(sim: any, fn: () -> boolean, timeout: number): boolean
	return sim:WaitFor(fn, timeout, 1 / 60) == true
end

local function openCard(sim: any, p: any): boolean
	local card = fishing(p).CatchCard
	return waitFor(sim, function()
		return card.Visible
	end, CARD_OPENS + 0.5)
end

-- (Deliberate UI v2 changes against the v1 version of this test: a Common fish has no dim and
-- no confetti; the texts appear by beats; «НОВИНКА!» instead of «НОВАЯ!».)
tests["catch card: Common reveal — calm (no dim, no confetti), pop-in with a turn, beats, «НОВИНКА!», count-up"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local f = fishing(p)
	local card = f.CatchCard
	local price = card.InfoLabel.Price.Label

	catch(sim, p, CATCHES.Common, 1)
	t.eq(card.Visible, false, "the fish leaps first")
	t.ok(openCard(sim, p), "the card opens after the landing")
	t.eq(f.CatchDim.Visible, false, "no dim for a Common fish")
	t.ok(f.CatchRays.Visible and f.CatchRays:FindFirstChild("FxRays"), "calm rays behind the card")
	t.eq(count(f.CatchRays, "FxRays"), 1, "one ring of rays for a Common fish")
	t.ok(colorNear(f.CatchRays.FxRays.Ray1.BackgroundColor3, UIConfig.Rarity.Common.Rays[1]), "rays in rarity colours")
	t.ok(card.FxScale.Scale < 1, "the card pops in")
	t.ok(card.Rotation < 0, "…with a little turn")
	t.ok(isCandy(card.Banner, UIConfig.Rarity.Common), "the banner in the rarity gradient")
	t.eq(card.InfoLabel.Text, "840 г · цена 11 💰", "InfoLabel holds the summary at once")
	t.eq(card.InfoLabel.Weight.Label.Text, "840 г")
	t.eq(price.Text, "0", "the price starts at 0")
	t.eq(card.Banner.FxScale.Scale, 0, "the rarity waits for its beat")
	t.eq(card.NameLabel.FxScale.Scale, 0, "…so does the name")
	t.eq(card.TapHint.TextTransparency, 1, "…and the close hint")
	t.eq(p.PlayerGui.HUD:FindFirstChild("FxConfetti"), nil, "no confetti for a Common fish")
	t.eq(p.PlayerGui.HUD:FindFirstChild("FxFlash"), nil, "no screen flash for a Common fish")
	t.eq(f.TitleSlam.Visible, false, "no giant title for a Common fish")
	t.eq(card.NewStamp.Visible, true, "the first Crucian of the session is «НОВИНКА!»")
	t.eq(card.NewStamp.Label.Text, "НОВИНКА!")

	sim:Advance(0.55)
	t.near(card.FxScale.Scale, 1, 1e-3, "popped in")
	t.near(card.Rotation, 0, 1e-3, "and turned straight")
	t.ok(card.Banner.FxScale.Scale > 0.5, "the rarity is up (c+0.2)")
	sim:Advance(0.6)
	local partial = price.Text
	t.ok(tonumber(partial) ~= nil, "the price is a number while counting")
	sim:Advance(1)
	t.eq(price.Text, "11", "the price counted up to the value")
	t.near(card.NewStamp.FxScale.Scale, 1, 1e-3, "«НОВИНКА!» stamped")
	t.ok(card.TapHint.TextTransparency < 0.5, "the close hint shows after the last beat")
	t.ok(count(card.FishGlow, "FxSparkle") > 0 or count(card, "FxSparkle") > 0, "sparkles around the fish")

	-- The same species again: no «НОВИНКА!».
	sim:Advance(UIConfig.CatchCardTime.Common)
	t.eq(card.Visible, false, "closed by itself")
	sim:Advance(1)
	catch(sim, p, CATCHES.Common, 2)
	t.ok(openCard(sim, p))
	t.eq(card.NewStamp.Visible, false, "a second Crucian is not new")
	sim:AssertNoErrors({ warnings = true })
end

tests["catch: Legendary and Mythic are louder — tension, flash at the landing, giant title, dim, second ring, rainbow"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local f = fishing(p)
	local card = f.CatchCard
	local hud = p.PlayerGui.HUD

	catch(sim, p, CATCHES.Common, 1)
	t.ok(openCard(sim, p))
	local commonRays = count(f.CatchRays.FxRays, "Ray1") > 0 and #f.CatchRays.FxRays:GetChildren() or 0
	sim:Advance(1)
	sim:Click(p, card)
	sim:Advance(0.1)
	sim:Click(p, card)
	sim:Advance(3)

	catch(sim, p, CATCHES.Legendary, 2)
	sim:Advance(0.6)
	t.ok(hud:FindFirstChild("FxVignette"), "Legendary: the screen edges glow while the fish leaps")
	t.ok(
		waitFor(sim, function()
			return f.TitleSlam.Visible
		end, CARD_OPENS),
		"Legendary: the giant title"
	)
	t.ok(hud:FindFirstChild("FxFlash"), "…right after the landing flash")
	t.eq(f.TitleSlam.Letters:FindFirstChild("L12").Text, "!", "«ЛЕГЕНДАРНАЯ!» letter by letter")
	t.eq(f.TitleSlam.Label.Visible, false)
	t.ok(openCard(sim, p))
	t.eq(f.CatchDim.Visible, true, "Legendary: the screen dims around the card")
	t.eq(count(f.CatchRays, "FxRays"), 2, "Legendary: an extra ring of rays")
	t.ok(isCandy(card.Banner, UIConfig.Rarity.Legendary), "Legendary banner")
	sim:Advance(0.7)
	t.eq(f.TitleSlam.Visible, false, "the title flew into the banner")
	t.eq(#f.TitleSlam.Letters:GetChildren(), 0, "…its letters are gone")
	t.near(card.Banner.FxScale.Scale, 1, 0.15, "the banner took over")
	sim:Click(p, card)
	sim:Advance(0.1)
	sim:Click(p, card)
	sim:Advance(3)

	catch(sim, p, CATCHES.Mythic, 3)
	t.ok(
		waitFor(sim, function()
			return f.TitleSlam.Visible
		end, CARD_OPENS),
		"Mythic: the giant title"
	)
	t.ok(hud:FindFirstChild("FxFlash"), "Mythic: a screen flash")
	t.ok(openCard(sim, p))
	t.eq(count(f.CatchRays, "FxRays"), 2, "Mythic: an extra ring of rays")
	local mythicRays = 0
	for _, holder in f.CatchRays:GetChildren() do
		if holder.Name == "FxRays" then
			mythicRays = math.max(mythicRays, #holder:GetChildren())
		end
	end
	t.ok(mythicRays > commonRays, `more rays for rarer fish ({mythicRays} > {commonRays})`)
	local fill = card.Banner.Face.Fill
	t.eq(fill.Rotation, 0, "a horizontal rainbow banner")
	local before = fill.Color.Keypoints[1].Value
	sim:Advance(0.6)
	t.ok(not colorNear(before, fill.Color.Keypoints[1].Value, 0.02), "the rainbow runs")
	t.ok(count(card.Banner, "FxSparkle") > 0, "sparkles on the Mythic banner")
	sim:Advance(1)
	sim:Click(p, card)
	sim:Advance(0.1)
	sim:Click(p, card)
	sim:Advance(3)
	t.eq(#leftovers(p), 0, `no effect instances left: {table.concat(leftovers(p), ", ")}`)
	t.eq(uiFx(sim, p).activeJobs(), 0, "no frame effects left (rainbow stopped with the card)")

	-- Back to a common catch: the banner is vertical again.
	catch(sim, p, CATCHES.Rare, 4)
	t.ok(openCard(sim, p))
	t.eq(card.Banner.Face.Fill.Rotation, 90, "a Rare banner is a vertical gradient again")
	t.ok(isCandy(card.Banner, UIConfig.Rarity.Rare), "Rare banner")
	sim:AssertNoErrors({ warnings = true })
end

-- (UI v2: the mutation is a stamp on the fish's corner after the base price lands, «ЗОЛОТАЯ ×2!»
-- on it, «×N» slammed on the price, the price recounted, the card outline in its colours.)
tests["mutation: stamped after the base price — «×N», recount, outline; Gold sparkles, Neon glows, Rainbow runs"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local card = fishing(p).CatchCard
	local badge = card.MutationLabel
	local outline = card.Lip:FindFirstChildOfClass("UIStroke")
	local price = card.InfoLabel.Price.Label
	local cases = {
		{ "Gold", "Золотая мутация ×2", "ЗОЛОТАЯ ×2!", "×2", 2 },
		{ "Neon", "Неоновая мутация ×3", "НЕОНОВАЯ ×3!", "×3", 3 },
		{ "Rainbow", "Радужная мутация ×5", "РАДУЖНАЯ ×5!", "×5", 5 },
	}
	for index, case in cases do
		local fish = table.clone(CATCHES.Rare)
		fish.Mutation = case[1]
		fish.Value = CATCHES.Rare.Value * case[5]
		catch(sim, p, fish, index)
		t.ok(openCard(sim, p))
		t.eq(badge.Visible, true)
		t.eq(badge.Text, case[2], `{case[1]}: the value`)
		t.eq(badge.Caption.Text, case[3], `{case[1]}: the stamp`)
		t.eq(card.InfoLabel.Price.Multiplier.Text, case[4], `{case[1]}: «×N» for the price`)
		t.eq(badge.Icon.Text, UIConfig.Mutations[case[1]].Icon)
		local style = UIConfig.Mutations[case[1]]
		if style.Effect == "rainbow" then
			t.ok(colorNear(badge.Lip.BackgroundColor3, style.Lip), "Rainbow: its lip")
			t.ok(#badge.Face.Fill.Color.Keypoints >= #UIConfig.Rainbow, "Rainbow: a rainbow face")
		else
			t.ok(isCandy(badge, style), `{case[1]}: its style`)
		end
		t.eq(badge.FxScale.Scale, 0, `{case[1]}: waits for its beat`)
		-- The base price lands first (Rare: c+0.95 + 0.6 s), the stamp 0.15 s later.
		sim:Advance(1.62)
		t.eq(price.Text, tostring(CATCHES.Rare.Value), `{case[1]}: the base price first`)
		t.eq(badge.FxScale.Scale, 0, `{case[1]}: the stamp not yet`)
		sim:Advance(0.9)
		t.near(badge.FxScale.Scale, 1, 0.02, `{case[1]}: stamped in`)
		t.eq(card.InfoLabel.Price.Multiplier.Visible, true, `{case[1]}: «×N» slammed`)
		t.eq(price.Text, tostring(fish.Value), `{case[1]}: recounted to the full price`)
		t.ok(outline:FindFirstChild("FxRimFill"), `{case[1]}: the card outline in its colours`)
		if case[1] == "Gold" then
			t.ok(count(badge, "FxSparkle") > 0, "Gold: sparkles")
		elseif case[1] == "Neon" then
			t.ok(count(badge, "FxRing") > 0, "Neon: a glowing pulse")
		else
			local before = badge.Face.Fill.Color.Keypoints[1].Value
			sim:Advance(0.3)
			t.ok(not colorNear(before, badge.Face.Fill.Color.Keypoints[1].Value, 0.02), "Rainbow: runs")
		end
		sim:Advance(0.3) -- past the last beat: a tap closes
		sim:Click(p, card)
		sim:Advance(0.05)
		t.eq(card.Visible, false, `{case[1]}: closed`)
		t.eq(outline:FindFirstChild("FxRimFill"), nil, `{case[1]}: the outline is Ink again`)
		t.ok(colorNear(outline.Color, UIConfig.Ink), `{case[1]}: Ink outline`)
		sim:Advance(1)
	end
	sim:Advance(3)
	t.eq(#leftovers(p), 0, `no effect instances left: {table.concat(leftovers(p), ", ")}`)
	sim:AssertNoErrors({ warnings = true })
end

-- (UI v2: a tap during the reveal skips it; the card shrinks towards the counter and a 🐟 with
-- ✨ flies in 0.05 s later; the rays shrink with it — timings this test checked before.)
tests["closing: skip, then close — the card hides, its ghost shrinks to the counter, 🐟 flies, +1; nothing leaks"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	sim:Advance(5)
	local f = fishing(p)
	local card = f.CatchCard
	local hud = p.PlayerGui.HUD
	local counter = hud.Status.CatchCounter
	local UiFx = uiFx(sim, p)
	local idleConnections = sim:CountConnections(p)
	local idleFrames = frameConnections(sim, p)
	t.eq(UiFx.activeJobs(), 0, "idle")

	catch(sim, p, CATCHES.Rare, 1)
	t.eq(hud:GetAttribute("CounterHold"), 0, "the counter holds the old number")
	t.ok(openCard(sim, p))
	t.ok(frameConnections(sim, p) > idleFrames, "the reveal animates per frame")
	sim:Advance(0.02)
	sim:Click(p, card)
	sim:Advance(0.02)
	t.eq(card.Visible, true, "locked for CARD_INPUT_LOCK (a trailing tap does nothing)")
	t.eq(card.Banner.FxScale.Scale, 0, "…and does not skip either")
	sim:Advance(0.4)
	sim:Click(p, card)
	sim:Advance(0.02)
	t.eq(card.Visible, true, "a tap during the reveal skips it")
	t.near(card.Banner.FxScale.Scale, 1, 0.2, "…every beat at once")
	t.eq(card.InfoLabel.Price.Label.Text, "58")
	sim:Advance(0.3)
	sim:Click(p, card)
	sim:Advance(0.02)
	t.eq(card.Visible, false, "hidden at once")
	t.eq(card.Viewport:FindFirstChildOfClass("Model"), nil, "the fish model is gone from the card")
	t.ok(f:FindFirstChild("FxCardOut"), "its ghost shrinks away")
	sim:Advance(0.06)
	t.ok(hud:FindFirstChild("FxFly"), "a 🐟 flies")
	sim:Advance(0.25)
	t.eq(f.CatchRays:FindFirstChild("FxRays"), nil, "the rays shrank with the card")
	t.eq(f:FindFirstChild("FxCardOut"), nil, "the ghost is gone")
	t.eq(f.CatchDim.Visible, false, "the dim faded away")
	sim:Advance(0.3)
	t.eq(hud:GetAttribute("CounterHold"), nil, "the 🐟 arrived: the hold is released")
	t.eq(counter.Label.Text, "Улов: 1")
	t.ok(counter.FxScale.Scale > 1, "the counter bumps when the fish arrives")
	sim:Advance(3)
	t.eq(#leftovers(p), 0, `no effect instances left: {table.concat(leftovers(p), ", ")}`)
	t.eq(UiFx.activeJobs(), 0, "no frame effects")
	t.eq(frameConnections(sim, p), idleFrames, "no RenderStepped/Heartbeat left")
	t.eq(sim:CountConnections(p), idleConnections, "connections back to the idle count")

	-- Closing by itself (UIConfig.CatchCardTime) does the same.
	catch(sim, p, CATCHES.Legendary, 2)
	t.ok(openCard(sim, p))
	sim:Advance(UIConfig.CatchCardTime.Legendary + 0.05)
	t.eq(card.Visible, false, "closed by itself")
	sim:Advance(3)
	t.eq(counter.Label.Text, "Улов: 2")
	t.eq(#leftovers(p), 0, `no effect instances left: {table.concat(leftovers(p), ", ")}`)
	t.eq(frameConnections(sim, p), idleFrames)
	t.eq(sim:CountConnections(p), idleConnections)
	sim:AssertNoErrors({ warnings = true })
end

tests["catch: the card owns the screen — frozen button, no hint, status faded; all back after the 🐟"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	ready(sim, p)
	sim:Advance(1)
	local f = fishing(p)
	local hud = p.PlayerGui.HUD
	local button = f.ActionArea.ActionButton
	local badgeLabel = hud.Status.BaseBadge.Label
	t.eq(f.Hint.Visible, true, "the standing hint by the spot")
	t.eq(button.Caption.Text, "ЗАБРОСИТЬ")

	serverSays(sim, p, "Minigame", minigame("Epic"))
	sim:Advance(0.3)
	catch(sim, p, CATCHES.Rare, 1)
	t.ok(f:FindFirstChild("FxMinigameWin"), "the minigame plays its win")
	t.eq(button.Caption.Text, "ЖДЁМ…", "the button is frozen")
	t.eq(f.Hint.Visible, false, "no hint over the catch")
	local rotation = button.Icon.Rotation
	t.ok(openCard(sim, p))
	t.ok(button.Face.BackgroundTransparency > 0.2, "…and dimmed")
	sim:Advance(1.2)
	t.eq(button.Icon.Rotation, rotation, "no hourglass flips while the card is up")
	t.ok(badgeLabel.TextTransparency > 0.95, "the base badge faded under the card")
	pressF(sim, p)
	t.eq(#sim:ServerEventsFor(p, "FishingCast"), 0, "no cast while the catch is on screen")

	sim:Advance(1.5)
	sim:Click(p, f.CatchCard)
	sim:Advance(0.05)
	t.eq(f.CatchCard.Visible, false)
	sim:Advance(0.25)
	t.ok(badgeLabel.TextTransparency < 0.05, "the badge is back")
	sim:Advance(1)
	t.eq(button.Caption.Text, "ЗАБРОСИТЬ", "the button is back")
	t.ok(button.Face.BackgroundTransparency < 0.05, "…at full colour")
	t.eq(f.Hint.Visible, true, "the hint is back")
	sim:AssertNoErrors({ warnings = true })
end

tests["catch: the card opens on the landing signal (OwnFishLanded) plus the rarity's hold, sooner than the fallback"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local card = fishing(p).CatchCard
	local module = sim:Find("Controllers.FishingFxController", p:FindFirstChildOfClass("PlayerScripts"))
	local fx = sim:Require(module, p)

	catch(sim, p, CATCHES.Legendary, 1)
	sim:Advance(0.3)
	t.eq(card.Visible, false, "the fish is still in the air")
	sim:Run(function()
		fx.OwnFishLanded:Fire("Legendary", Vector3.new(0, 10, 0))
	end, p)
	sim:Advance(0.3)
	t.eq(card.Visible, false, "Legendary: a 0.4 s hold after the landing")
	sim:Advance(0.2)
	t.eq(card.Visible, true, "the card is up — well before LeapTime + 0.3 s")
	sim:Advance(6)

	-- No leap at all (no character / no model): the signal comes before "Caught" — still used.
	sim:Run(function()
		fx.OwnFishLanded:Fire("Common", Vector3.new(0, 10, 0))
	end, p)
	sim:Advance(0.05)
	catch(sim, p, CATCHES.Common, 2)
	sim:Advance(0.2)
	t.eq(card.Visible, true, 'a landing just before "Caught" opens the card at once (+ hold)')
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Hint, idle
--------------------------------------------------------------------------------

tests["hint: a Night pill with an icon by kind, slides up with a bounce"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local hint = fishing(p).Hint
	sim:Advance(1)
	t.eq(hint.Visible, true)
	t.eq(hint.Text, "Жми «Забросить»")
	t.eq(hint.Label.Text, hint.Text, "the label shows the value")
	t.eq(hint.Icon.Text, "💡", "info: 💡")
	local rest = hint.Position

	serverSays(sim, p, "Denied", { Reason = "far", Text = "Подойди к краю своего пирса" })
	t.eq(hint.Label.Text, "Подойди к краю своего пирса")
	t.eq(hint.Icon.Text, "⚠️", "warning: ⚠️")
	t.ok(hint.Position.Y.Scale > rest.Y.Scale, "slides up from below")
	t.ok(hint.FxScale.Scale < 1, "pops")
	sim:Advance(0.6)
	t.near(hint.Position.Y.Scale, rest.Y.Scale, 1e-3, "at rest")
	t.near(hint.FxScale.Scale, 1, 1e-3)

	serverSays(sim, p, "Idle", { Reason = "stop" })
	t.eq(hint.Label.Text, "Леска смотана")
	t.eq(hint.Icon.Text, "💡", "info again")
	sim:AssertNoErrors({ warnings = true })
end

tests["idle with the rod: only timers (shine, wiggle) — no frame effects, no connection churn"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	ready(sim, p)
	sim:Advance(6)
	local UiFx = uiFx(sim, p)
	t.eq(UiFx.activeJobs(), 0, "nothing runs per frame")
	local idle = sim:CountConnections(p)
	local frames = frameConnections(sim, p)
	local band = fishing(p).ActionArea.ActionButton.Face.Shine.Band
	local sawShine = false
	for _ = 1, 100 do
		sim:Advance(0.1)
		if band.Offset.X > -1 and band.Offset.X < 1 then
			sawShine = true
		end
	end
	t.ok(sawShine, "the idle button shines now and then")
	t.eq(sim:CountConnections(p), idle, "no connection churn")
	t.eq(frameConnections(sim, p), frames, "no frame connection")
	t.eq(UiFx.activeJobs(), 0)
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Layout
--------------------------------------------------------------------------------

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

-- Absolute rectangle like Roblox lays it out (incl. list alignment; RbxSim ignores it).
local function rectOf(sim: any, p: any, gui: any): Rect
	local parent = gui.Parent
	local size = gui.AbsoluteSize
	if parent:IsA("LayerCollector") then
		local vp = sim.players.state[sim:Unwrap(p)].viewport
		local pos, anchor = gui.Position, gui.AnchorPoint
		return {
			x = pos.X.Scale * vp.X + pos.X.Offset - anchor.X * size.X,
			y = INSET + pos.Y.Scale * (vp.Y - INSET) + pos.Y.Offset - anchor.Y * size.Y,
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
			local extent = if vertical then c.AbsoluteSize.Y else c.AbsoluteSize.X
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

tests["layout: the fishing UI fits on phone, tablet and desktop without overlaps"] = function(t)
	local sim = boot(t)
	local devices = { "phone", "tablet", "desktop" }
	local players = {}
	for i, device in devices do
		players[device] = addPlayer(sim, i, device)
	end
	for _, device in devices do
		local p = players[device]
		ready(sim, p)
		p:SetAttribute("FishCaught", 3) -- the catch counter shows
		serverSays(sim, p, "Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
		serverSays(sim, p, "Minigame", minigame("Mythic"))
	end
	sim:Advance(1)

	for _, device in devices do
		local p = players[device]
		local hud = p.PlayerGui.HUD
		local f = hud.Fishing
		local vp = sim.players.state[sim:Unwrap(p)].viewport
		local touch = device ~= "desktop"
		local function r(gui: any): Rect
			return rectOf(sim, p, gui)
		end
		t.ok(f.ActionArea.ActionButton.Visible and f.ActionArea.StopButton.Visible, `{device}: buttons shown`)
		t.ok(f.Minigame.Visible, `{device}: minigame shown`)

		local button = r(f.ActionArea.ActionButton)
		local ribbon = r(f.ActionArea.ActionButton.CaptionRibbon)
		local stop = r(f.ActionArea.StopButton)
		local mini = r(f.Minigame)
		local alert = r(f.BiteAlert)
		local hint = r(f.Hint)
		local card = r(f.CatchCard)
		local badge = r(hud.Status.BaseBadge)
		local counter = r(hud.Status.CatchCounter)
		local home = r(hud.RightButtons.HomeButton)

		local all = {
			button = button,
			ribbon = ribbon,
			stop = stop,
			minigame = mini,
			alert = alert,
			hint = hint,
			card = card,
		}
		for name, rect in all do
			t.ok(rect.x >= 0 and rect.x + rect.w <= vp.X, `{device}: {name} {fmt(rect)} inside the width`)
			t.ok(rect.y >= INSET and rect.y + rect.h <= vp.Y, `{device}: {name} {fmt(rect)} inside the height`)
		end
		-- The centre column stands above the hotbar.
		for _, name in { "minigame", "alert", "hint", "card" } do
			local rect = all[name]
			t.ok(rect.y + rect.h <= vp.Y - HOTBAR_TOP, `{device}: {name} {fmt(rect)} above the hotbar`)
		end
		-- No overlaps: the action column vs the centre column, the chrome vs everything.
		local pairs = {
			{ "button", "minigame" },
			{ "button", "alert" },
			{ "button", "hint" },
			{ "button", "card" },
			{ "ribbon", "minigame" },
			{ "ribbon", "alert" },
			{ "ribbon", "hint" },
			{ "stop", "minigame" },
			{ "stop", "alert" },
			{ "stop", "hint" },
			{ "stop", "card" },
			{ "stop", "button" },
			{ "minigame", "hint" },
			{ "alert", "hint" },
		}
		for _, pair in pairs do
			local a, b = all[pair[1]], all[pair[2]]
			t.eq(overlap(a, b), 0, `{device}: {pair[1]} {fmt(a)} overlaps {pair[2]} {fmt(b)}`)
		end
		local chrome = { badge = badge, counter = counter, home = home }
		for cname, crect in chrome do
			for name, rect in all do
				-- (UI v2: the catch card is placed when it opens, and the status stack fades
				-- under it — see "catch card layout"; its unopened builder box is not checked
				-- against the status stack.)
				if not (name == "card" and cname ~= "home") then
					t.eq(overlap(crect, rect), 0, `{device}: {name} {fmt(rect)} overlaps {cname} {fmt(crect)}`)
				end
			end
		end
		-- Touch screens: clear of the Jump button and the thumbstick (CoreGui).
		if touch then
			local small = math.min(vp.X, vp.Y) <= 500
			local jump: Rect = if small
				then { x = vp.X - 95, y = vp.Y - 90, w = 70, h = 70 }
				else { x = vp.X - 170, y = vp.Y - 210, w = 120, h = 120 }
			local stick: Rect = if small
				then { x = 25, y = vp.Y - 90, w = 70, h = 70 }
				else { x = 60, y = vp.Y - 210, w = 120, h = 120 }
			for _, name in { "button", "ribbon", "stop" } do
				t.eq(overlap(all[name], jump), 0, `{device}: {name} {fmt(all[name])} clear of the Jump button`)
			end
			for _, name in { "minigame", "alert", "hint", "card" } do
				t.eq(overlap(all[name], stick), 0, `{device}: {name} {fmt(all[name])} clear of the thumbstick`)
			end
		end
		-- Big enough to hit.
		t.ok(button.w >= 56 and button.h >= 56, `{device}: the action button is big ({fmt(button)})`)
		t.ok(stop.h >= 24, `{device}: «СМОТАТЬ» tall enough ({fmt(stop)})`)
		t.ok(mini.h >= 90, `{device}: the minigame is readable ({fmt(mini)})`)
	end
	sim:AssertNoErrors({ warnings = true })
end

tests["catch card layout: a landscape trophy card on phones, square on tablet / desktop; clear of the controls"] = function(
	t
)
	local sim = boot(t)
	local devices = { "phone", "tablet", "desktop" }
	local players = {}
	for i, device in devices do
		players[device] = addPlayer(sim, i, device)
	end
	for _, device in devices do
		local p = players[device]
		ready(sim, p)
		p:SetAttribute("FishCaught", 2)
		sim:Advance(0.2)
		catch(sim, p, CATCHES.Legendary, 3)
	end
	sim:Advance(CARD_OPENS + 0.8)
	for _, device in devices do
		local p = players[device]
		local hud = p.PlayerGui.HUD
		local f = hud.Fishing
		local vp = sim.players.state[sim:Unwrap(p)].viewport
		local card = rectOf(sim, p, f.CatchCard)
		local button = rectOf(sim, p, f.ActionArea.ActionButton.CaptionRibbon)
		t.ok(f.CatchCard.Visible, `{device}: the card is up`)
		if device == "phone" then
			t.ok(card.w > card.h * 1.4, `{device}: a landscape card {fmt(card)}`)
			t.ok(card.h >= 200, `{device}: big on the phone {fmt(card)}`)
			local fish = rectOf(sim, p, f.CatchCard.Viewport)
			t.ok(fish.h >= 150, `{device}: a big fish {fmt(fish)}`)
		else
			t.near(card.w / card.h, 380 / 384, 0.05, `{device}: the square card {fmt(card)}`)
		end
		t.ok(card.x + card.w * 1.04 <= button.x, `{device}: clear of the action button {fmt(card)} / {fmt(button)}`)
		t.ok(card.y + card.h <= vp.Y - HOTBAR_TOP - 16, `{device}: above the hotbar {fmt(card)}`)
		t.ok(card.y >= INSET, `{device}: below the top bar {fmt(card)}`)
		if device ~= "desktop" then
			local small = math.min(vp.X, vp.Y) <= 500
			local stickRight = if small then 95 else 180
			t.ok(card.x >= stickRight + 8, `{device}: clear of the thumbstick {fmt(card)}`)
		end
		t.ok(hud.Status.BaseBadge.Label.TextTransparency > 0.95, `{device}: the status stack faded under the card`)
	end
	sim:AssertNoErrors({ warnings = true })
end

return tests
