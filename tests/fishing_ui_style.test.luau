--[[
	The fishing UI (tools/builder/gui/Fishing.luau + FishingController, look and rules:
	tools/builder/gui/STYLE.md) in RbxSim against the built Place1.rbxl:
	  • the parts: UI v5 «Симулятор» — every widget is a sim plate / button (a gradient face, a thick
	    outline in the dark shade of its hue) or glass, with the documented decorations, and no studs;
	  • each state's look: the action button per state (Sky / Slate / Sun / Leaf / Gold, icon,
	    ring), the bite alert (slam, rays, flash, draining timer), the minigame (rarity title,
	    trail under the zone, hit juice: «ОТЛИЧНО!» / «СУПЕР!» / «ИДЕАЛЬНО!», stamped stars,
	    sparks), the miss ghost («МИМО!»), the catch card per rarity (dim, rays, pop-in with a
	    turn, «НОВАЯ!», count-up, confetti; Legendary/Mythic: a crisp burst at the fish — no edge
	    flash —, second ring, rainbow), the mutation badge effects and the hint pill by kind;
	  • effects start and are cleaned up: no Fx* instances left after a full catch/close and after
	    a miss, no frame effect (RenderStepped/Heartbeat) running while idle, connection counts
	    back to their baseline;
	  • the layout fits on a phone, a tablet and a desktop: nothing overlaps the status stack, the
	    Home button, the thumbstick or the Jump button, and the widgets do not overlap each other
	    (v3: the Roblox hotbar is off; on a phone the minigame docks LEFT of the own fisher, the
	    catch card beside him — FishingLayout).
	The server's FishingService is switched off (like tests/stage2_client.test.luau): the harness
	plays the server and fires FishingState itself.

	Run: lune run tools/run_tests.luau fishing_ui_style
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local INSET = 58 -- RbxSim's top bar inset for ScreenGuis without IgnoreGuiInset
local BOTTOM_GAP = 16 -- v3: no Roblox hotbar (HudController switches the Backpack CoreGui off)

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

-- The sim plate shows a style (palette token / rarity / mutation): face gradient and the Lip (the
-- outline's colour). Its Top sits at UIConfig.Brick.CapStop (0 since UI v5: no cap).
local function isCandy(root: any, style: any): boolean
	local face = root:FindFirstChild(root:GetAttribute("CandyFace") or "Face")
	local keys = face.Fill.Color.Keypoints
	local top = keys[1].Value
	if root:GetAttribute("CandyStyle") ~= nil then
		for _, key in keys do
			if math.abs(key.Time - UIConfig.Brick.CapStop) < 1e-3 then
				top = key.Value
			end
		end
	end
	return colorNear(top, style.Top)
		and colorNear(keys[#keys].Value, style.Bottom)
		and colorNear(root.Lip.BackgroundColor3, style.Lip)
end

-- UI v5: every fishing widget is a sim plate (Theme.sim, or the compat brick / tile / roundPlate
-- that build it): the Lip carries the outline (no fill) in the dark shade of the swatch, the face
-- (a Top → Bottom gradient) covers the whole root; or the glass look (no outline).
local function checkCandy(t: any, root: any, what: string)
	local faceName = root:GetAttribute("CandyFace")
	t.ok(type(faceName) == "string", `{what}: CandyFace attribute`)
	local style = root:GetAttribute("CandyStyle")
	t.ok(style == "sim" or style == "glass", `{what}: a sim plate or glass ({style})`)
	t.eq(root.BackgroundTransparency, 1, `{what}: transparent root`)
	local lip, face = root:FindFirstChild("Lip"), root:FindFirstChild(faceName)
	t.ok(lip and face, `{what}: Lip and {faceName}`)
	t.ok(lip.ZIndex < face.ZIndex, `{what}: the outline is behind the face`)
	t.eq(lip.BackgroundTransparency, 1, `{what}: the Lip draws no band`)
	t.eq(face.Size.Y.Scale, 1, `{what}: the face covers the whole root (no side band)`)
	local outline = lip:FindFirstChildOfClass("UIStroke")
	t.ok(outline and colorNear(outline.Color, lip.BackgroundColor3), `{what}: the outline in the swatch's dark shade`)
	t.ok(type(outline:GetAttribute("BaseThickness")) == "number", `{what}: outline fitted to the screen`)
	if style == "sim" then
		t.ok(
			outline:GetAttribute("BaseThickness") >= 3,
			`{what}: a thick outline ({outline:GetAttribute("BaseThickness")})`
		)
	end
	local fill = face:FindFirstChild("Fill")
	t.ok(fill and fill:IsA("UIGradient"), `{what}: Fill gradient`)
end

-- Anything stud-like under root (UI v5: the GUI has no studs; empty v3 holders left by
-- Fishing.luau until the fishing waves delete them draw nothing).
local function studsUnder(root: any): { string }
	local found = {}
	for _, d in root:GetDescendants() do
		local name = d.Name
		if
			string.match(name, "^Stud%d*$")
			or d:GetAttribute("CandyStud") ~= nil
			or name == "Spec"
			or ((string.match(name, "^Studs") ~= nil or name == "StudRow") and #d:GetChildren() > 0)
		then
			table.insert(found, d:GetFullName())
		end
	end
	return found
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

tests["parts: the fishing widgets are sim plates with their decorations, no studs; text never too small"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local f = fishing(p)
	local area = f.ActionArea

	-- UI v5: the action button is a round sim button (no raised stud), its caption on a glass pill
	-- (the reference's timer pill); «СМОТАТЬ» a red sim button; the key chip a white plate.
	local action = area.ActionButton
	checkCandy(t, action, "ActionButton")
	t.ok(isCandy(action, Palette.Gold), "ActionButton: painted with the «ВЗЯТЬ» look (no rod)")
	t.ok(action.Ring:IsA("UIStroke"), "ActionButton.Ring halo")
	t.eq(action:GetAttribute("CandyRadius"), 0.5, "a round button")
	t.eq(action.Face:FindFirstChild("Stud"), nil, "no raised stud")
	checkCandy(t, action.CaptionRibbon, "CaptionRibbon")
	t.eq(action.CaptionRibbon:GetAttribute("CandyStyle"), "glass", "the caption on a glass pill")
	t.ok(action.Caption.ZIndex > action.CaptionRibbon.ZIndex, "caption over its pill")
	t.ok(action.Caption:FindFirstChild("Outline"), "outlined caption")
	checkCandy(t, action.KeyChip, "KeyChip")
	checkCandy(t, area.StopButton, "StopButton")
	t.ok(isCandy(area.StopButton, Palette.Berry), "StopButton: a red button")
	t.eq(area.StopButton.Icon.Text, "🎣", "v3 (UIM-09): the rod — «reel it in», not a sewing thread")

	local alert = f.BiteAlert
	checkCandy(t, alert, "BiteAlert")
	t.ok(isCandy(alert, Palette.Sun), "BiteAlert: an orange plate")
	t.eq(alert.Label.Text, "КЛЮЁТ!")
	t.ok(alert.Label:FindFirstChild("TextFill") and alert.Label:FindFirstChild("Outline"), "gradient, outlined title")
	-- UI v2 (FUI-08): «!» glyphs — white → gold text with an Ink outline, not the ❗ emoji.
	for _, side in { alert.IconLeft, alert.IconRight } do
		t.eq(side.Text, "!")
		t.ok(
			side:FindFirstChild("TextFill") and side:FindFirstChild("Outline"),
			`{side.Name}: gradient, outlined glyph`
		)
		t.ok(side.Outline:GetAttribute("BaseThickness") >= 5, "a thick glyph outline")
	end
	t.ok(alert.TimerTrack.ZIndex < alert.Timer.ZIndex, "the timer bar sits on its track")

	-- The minigame: a dark navy sim panel (no studs along its top edge any more).
	local mini = f.Minigame
	checkCandy(t, mini, "Minigame")
	t.ok(isCandy(mini, Palette.Night), "Minigame: a dark navy panel")
	t.eq(mini.Face.BackgroundTransparency, 0, "…opaque")
	t.eq(mini.Face:FindFirstChild("StudRow"), nil, "no row of studs")
	t.ok(mini.Title:FindFirstChild("TextFill") and mini.Title:FindFirstChild("Outline"), "rarity-gradient title")
	for i = 1, 5 do
		local pip = mini.Pips[`Pip{i}`]
		t.eq(pip.Star.Text, "★", `Pip{i} has a white star glyph (⭐ when stamped)`)
	end
	local track, zone, needle = mini.Track, mini.Track.Zone, mini.Track.Needle
	checkCandy(t, zone, "Zone")
	t.ok(isCandy(zone, Palette.Leaf), "Zone: a green plate")
	t.ok(zone.Glow.ZIndex < zone.Lip.ZIndex, "the zone's glow is behind it")
	t.ok(zone.Flash.ZIndex > zone.Face.ZIndex, "hit flash over the zone")
	t.ok(needle.ZIndex > zone.ZIndex, "the needle is drawn over the zone")
	t.ok(needle:FindFirstChildOfClass("UICorner") and needle:FindFirstChildOfClass("UIStroke"), "an outlined bar")
	t.ok(needle.Size.X.Scale <= 0.03, "the needle stays thin (the e2e bot aims with its width)")
	t.ok(track:FindFirstChildOfClass("UIStroke"), "outlined track")
	t.ok(mini.TimeBar.Fill:FindFirstChild("Gloss"), "glossy time bar")

	checkCandy(t, f.Hint, "Hint")
	t.eq(f.Hint:GetAttribute("CandyStyle"), "glass", "Hint: the reference's timer pill (glass)")
	t.ok(isCandy(f.Hint, Palette.Glass), "Hint: dark glass")
	t.eq(f.Hint.TextTransparency, 1, "Hint.Text is the value, Hint.Label shows it")
	t.eq(f.Hint.IconSocket.Rotation, 0, "an upright outlined icon")

	-- The catch card: a white plate — the fish in a window on a pedestal in the rarity's colour,
	-- the rarity banner, the price on a yellow chip. No studs anywhere.
	local card = f.CatchCard
	checkCandy(t, card, "CatchCard")
	t.ok(isCandy(card, Palette.Cream), "CatchCard: a white plate")
	t.ok(card.Face:FindFirstChild("Window"), "a display window behind the fish")
	checkCandy(t, card.Banner, "Banner")
	checkCandy(t, card.Pedestal, "Pedestal")
	t.ok(card.Pedestal.ZIndex < card.Viewport.ZIndex, "the fish stands in front of its pedestal")
	t.ok(card.Pedestal.ZIndex > card.FishGlow.ZIndex, "…which stands in front of the glow")
	checkCandy(t, card.MutationLabel, "MutationLabel")
	checkCandy(t, card.NewStamp, "NewStamp")
	checkCandy(t, card.InfoLabel.Weight, "Weight chip")
	t.eq(card.InfoLabel.Weight:GetAttribute("CandyRadius"), 0.5, "the weight on a grey round chip")
	checkCandy(t, card.InfoLabel.Price, "Price chip")
	t.ok(isCandy(card.InfoLabel.Price, Palette.Gold), "price on a yellow chip")
	local studs = studsUnder(f)
	t.eq(#studs, 0, `no studs in the fishing UI ({table.concat(studs, ", ")})`)
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

	-- «ВЗЯТЬ»: Gold, the ring lit gold, white glow rings call the player (UI v2: a crisp white
	-- ring every 1 s, 0.6 s long — sampled over a second).
	t.eq(button.Visible, true)
	t.eq(button.Caption.Text, "ВЗЯТЬ")
	t.ok(isCandy(button, Palette.Gold), "«ВЗЯТЬ» is a yellow plate")
	t.ok(button.Ring.Transparency < 0.5, "the ring is lit")
	local sawRing = false
	for _ = 1, 12 do
		sim:Advance(0.1)
		if count(button, "FxRing") > 0 then
			sawRing = true
		end
	end
	t.ok(sawRing, "glow rings while «ВЗЯТЬ» waits")

	-- «ЗАБРОСИТЬ»: Sky 🎣, the button pops in when the rod comes into the hand.
	sim:EquipTool(p, rod)
	sim:Advance(0.05)
	t.eq(button.Caption.Text, "ЗАБРОСИТЬ")
	t.ok(isCandy(button, Palette.Sky), "Sky while ready to cast")
	t.eq(button.Icon.Text, "🎣")
	t.ok(button.FxScale.Scale < 1, "pops in")
	sim:Advance(0.6)
	t.near(button.FxScale.Scale, 1, 1e-3, "settles")

	-- A tap: ripple + squash; «ЖДЁМ…» while the server answers: Slate ⏳ that flips. (The icon's
	-- rest rotation is read before the tap: UI v5's press kicks the icon −8° for 0.25 s.)
	local rest = button.Icon.Rotation
	sim:Click(p, button)
	sim:Advance(0.05)
	t.ok(count(button, "FxRing") > 0, "a ripple on the tap")
	t.eq(button.Caption.Text, "ЖДЁМ…")
	t.ok(isCandy(button, Palette.Slate), "Slate while the cast is pending")
	t.eq(button.Icon.Text, "⏳")
	sim:Advance(0.8)
	t.ok(math.abs(button.Icon.Rotation - rest) > 90, "the hourglass flips")
	-- UI v2 (FUI-19): the line in the water — a bobbing bobber and running dots. v3 (UIM-09): it
	-- does not look like a button to press — a muted Pond plate, 15 % smaller, no rings, «ЖДИ КЛЁВА…»,
	-- and the first wait of the session explains it with a hint.
	local restHeight = button.Size.Y.Scale
	serverSays(sim, p, "Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
	t.ok(isCandy(button, Palette.Pond), "Pond while waiting for a bite")
	t.eq(fishing(p).Hint.Text, "Жди, пока клюнет — потом жми!", "the first wait explains itself")
	t.eq(button.Icon.Text, "", "the bobber replaces the emoji")
	t.eq(button.Bobber.Visible, true, "a drawn bobber")
	local bobY = button.Bobber.Position.Y.Scale
	local captions = {}
	for _ = 1, 14 do
		sim:Advance(0.1)
		captions[button.Caption.Text] = true
	end
	t.ok(math.abs(button.Bobber.Position.Y.Scale - bobY) > 1e-3, "the bobber bobs")
	t.ok(captions["ЖДИ КЛЁВА."] and captions["ЖДИ КЛЁВА.."], "the dots run")
	t.ok(math.abs(button.Size.Y.Scale - restHeight * 0.85) < 0.01, "a smaller plate: nothing to press")
	t.eq(count(button, "FxRing"), 0, "no rings calling for a tap")
	t.ok(fishing(p).ActionArea.StopButton.Visible, "«СМОТАТЬ» while the line is out")

	-- «ПОДСЕЧЬ!»: Sun with the «!» glyph, white halo, pulse and glow rings.
	serverSays(sim, p, "Bite", { Window = 1.8 })
	sim:Advance(0.5)
	t.eq(button.Caption.Text, "ПОДСЕЧЬ!")
	t.ok(isCandy(button, Palette.Sun), "Sun on the bite")
	t.eq(button.Icon.Text, "!")
	t.ok(button.Icon.Outline.Enabled and button.Icon.TextFill.Enabled, "the «!» is an outlined white → gold glyph")
	t.eq(button.Icon.Outline:GetAttribute("BaseThickness"), 5, "… with a thicker contour than the emoji")
	t.eq(button.Bobber.Visible, false)
	t.ok(button.Ring.Transparency < 0.1, "white halo")
	t.ok(count(button, "FxRing") > 0, "glow rings")
	local scales = {}
	for _ = 1, 6 do
		sim:Advance(0.07)
		table.insert(scales, button.FxScale.Scale)
	end
	t.ok(math.max(table.unpack(scales)) - math.min(table.unpack(scales)) > 0.02, "the button pulses")
	t.near(button.Icon.Rotation, rest, 1e-3, "the hourglass is back at rest")

	-- Hook: dims until the minigame; «ЛОВИ!»: Leaf 🎯 (UI v2 FUI-06: not «ТЯНИ!» 💪 — one tap, not mashing).
	sim:Click(p, button)
	sim:Advance(0.3)
	t.ok(isCandy(button, Palette.Slate), "dim after the hook")
	t.near(button.FxScale.Scale, 1, 1e-3, "the pulse stopped with the hook")
	serverSays(sim, p, "Minigame", minigame("Common"))
	t.eq(button.Caption.Text, "ЛОВИ!")
	t.ok(isCandy(button, Palette.Leaf), "Leaf while reeling")
	t.eq(button.Icon.Text, "🎯")
	t.ok(button.Icon.Outline.Enabled, "an emoji again: it keeps its dark contour (never switched off)")
	t.eq(button.Icon.Outline:GetAttribute("BaseThickness"), 3.5, "… at the emoji's weight")
	t.eq(button.Icon.TextFill.Enabled, false, "… and no glyph fill")
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
		if math.abs(alert.IconLeft.Rotation + 10) > 2 or math.abs(alert.IconRight.Rotation - 10) > 2 then
			wiggled = true
		end
	end
	t.ok(wiggled, "the «!» glyphs wiggle")
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
	-- UI v2 (FUI-14): white → rarity colour, so the title reads on the dark panel.
	local fill = mini.Title.TextFill
	local keys = fill.Color.Keypoints
	t.ok(colorNear(keys[1].Value, roblox.Color3.new(1, 1, 1)), "white at the top of the title")
	t.ok(colorNear(keys[#keys].Value, UIConfig.Rarity.Legendary.Top), "Legendary colour at the bottom")
	sim:Advance(0.5) -- the pips and the zone have popped in
	local zoneHeight = zone.Size.Y.Scale
	local ghosts = 0
	for _, c in track:GetChildren() do
		if c.Name == "FxGhost" then
			ghosts += 1
			t.ok(c.ZIndex < zone.ZIndex, "the trail passes UNDER the zone")
			t.ok(c.BackgroundTransparency >= 0.75 - 1e-6, "faint ghosts (never read as more needles)")
		end
	end
	t.eq(ghosts, 2, "two ghost copies trail the needle (UI v2 FUI-06)")
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
	t.ok(burst.ZIndex > track.ZIndex, "…big, over the panel (UI v2 FUI-11)")
	-- UI v2 (FUI-13): the zone pops in HEIGHT only — its width is what the server checks.
	t.ok(zone.Size.Y.Scale < zoneHeight, "the zone pops in at its new place (height)")
	t.near(zone.Size.X.Scale, 0.17, 1e-6, "…its width stays the server's from the first frame")
	t.near(zone.Position.X.Scale, 0.15, 1e-6, "the zone jumped (no slide)")
	t.ok(mini.Pips.Pip1.Star.FxScale.Scale > 1, "the star is stamped")
	t.eq(mini.Pips.Pip1.Star.TextTransparency, 0)
	t.ok(button.FxScale.Scale > 1, "the button bumps")
	sim:Advance(0.9)
	t.eq(mini:FindFirstChild("FxFloat"), nil, "float gone")
	t.eq(mini:FindFirstChild("FxBurst"), nil, "sparks gone")
	t.near(zone.Size.Y.Scale, zoneHeight, 1e-3)

	-- Second hit, away from the centre: «СУПЕР!».
	pressF(sim, p)
	serverSays(sim, p, "Zone", { ZoneCenter = 0.8, Hits = 2 })
	t.eq(mini.FxFloat.Text, "СУПЕР!", "the second hit")
	sim:Advance(1)

	-- A fresh minigame, a hit without a perfect tap: «ОТЛИЧНО!».
	serverSays(sim, p, "Minigame", minigame("Epic"))
	t.eq(count(mini, "FxGhost"), 2, "the old trail is gone, a new one follows the needle")
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
	t.eq(ghost:FindFirstChild("TapPad"), nil, "the ghost never takes taps")
	t.eq(UiFx.activeJobs(), 0, "the ghost runs on timers only")
	-- UI v2 (FUI-15): the hint shares the column with the minigame — it comes once the ghost has
	-- left (M10: no two red panels on top of each other).
	t.eq(f.Hint.Visible, false, "no hint over the ghost")
	sim:Advance(0.6)
	t.eq(f.Hint.Visible, false, "still no hint while the ghost leaves")
	sim:Advance(0.2)
	t.eq(f:FindFirstChild("FxMinigameMiss"), nil, "the ghost has left …")
	t.eq(f.Hint.Visible, true, "… and the hint springs up")
	t.eq(f.Hint.Label.Text, "Мимо! Рыба сорвалась", "the hint shows the reason")
	t.eq(f.Hint.IconSocket.Icon.Text, "⚠️", "a warning hint")
	t.ok(isCandy(f.Hint, Palette.Sun), "a warning is an orange tile")

	sim:Advance(0.4)
	t.eq(f:FindFirstChild("FxMinigameMiss"), nil, "the ghost is gone")
	t.eq(#leftovers(p), 0, `no effect instances left: {table.concat(leftovers(p), ", ")}`)
	t.eq(frameConnections(sim, p), idleFrames, "no frame connection left")
	sim:Advance(4) -- the hint and the cast cooldown are over
	t.eq(sim:CountConnections(p), idleConnections, "back to the idle connection count")
	sim:AssertNoErrors({ warnings = true })
end

-- The real server order (FishingService.endSession): the FishingState attribute goes "Idle"
-- first, then the event follows. The attribute's safety net must not end the session before the
-- event plays its ghost («МИМО!» / «ВРЕМЯ!») or freezes the button for the catch.
tests["server order: attribute Idle, then Lost / Caught — the ghosts still play, the frozen button does not pop"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local f = fishing(p)
	local button = f.ActionArea.ActionButton

	for _, case in { { "miss", "МИМО!" }, { "timeout", "ВРЕМЯ!" } } do
		p:SetAttribute("FishingState", "Reeling")
		serverSays(sim, p, "Minigame", minigame("Rare", { ZoneCenter = 0.8, U0 = 0.05 }))
		sim:Advance(0.3)
		p:SetAttribute("FishingState", "Idle")
		serverSays(sim, p, "Lost", { Reason = case[1], Text = "Рыба ушла" })
		local ghost = f:FindFirstChild("FxMinigameMiss")
		t.ok(ghost, `{case[1]}: the miss ghost plays in the real server order`)
		t.ok(ghost and ghost:FindFirstChild("FxFloat") and ghost.FxFloat.Text == case[2], `{case[1]}: «{case[2]}»`)
		t.eq(f.Hint.Visible, false, `{case[1]}: the hint waits for the ghost`)
		sim:Advance(0.8) -- MISS_HOLD (0.75 s): the ghost has left
		t.eq(f.Hint.Visible, true, `{case[1]}: then the reason`)
		sim:Advance(1.5)
	end

	p:SetAttribute("FishingState", "Reeling")
	serverSays(sim, p, "Minigame", minigame("Rare"))
	sim:Advance(0.3)
	p:SetAttribute("FishingState", "Idle")
	catch(sim, p, CATCHES.Rare, 1)
	t.ok(f:FindFirstChild("FxMinigameWin"), "the win ghost plays")
	t.eq(button.Caption.Text, "ЖДЁМ…", "the button is frozen")
	local lowest = button.FxScale.Scale
	for _ = 1, 20 do
		sim:Advance(1 / 60)
		lowest = math.min(lowest, button.FxScale.Scale)
	end
	t.ok(lowest > 0.95, `the frozen button does not pop (scale down to {lowest})`)
	sim:Advance(0.8)
	t.eq(button.Caption.Text, "ЖДЁМ…", "still frozen after the safety net's delay")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Catch (UI v2, FUI-01…12: the world first, then the card; tiers; beats; skip; exit)
--------------------------------------------------------------------------------

-- The card opens when the fish has landed over the head (FishingFxController.OwnFishLanded;
-- without a leap — here "Caught" comes without the server's FishFx — LeapTime + 0.3 s) plus a
-- per-rarity hold (at most 1.6 s: v3 — Epic and rarer +0.6 s, the arms-up landing with the fish
-- and the giant title stand alone first).
local CARD_OPENS = FishingConfig.LeapTime + 0.3 + 1.8
-- After a tap skips the reveal the card ignores taps this long (FishingController CLIMAX.SkipDwell).
local SKIP_DWELL = 0.6

local function waitFor(sim: any, fn: () -> boolean, timeout: number): boolean
	return sim:WaitFor(fn, timeout, 1 / 60) == true
end

local function openCard(sim: any, p: any): boolean
	local card = fishing(p).CatchCard
	return waitFor(sim, function()
		return card.Visible
	end, CARD_OPENS + 0.5)
end

-- (Deliberate UI v2 changes against the v1 version of this test: a known Common fish has no dim
-- and no confetti; the texts appear by beats; «НОВИНКА!» instead of «НОВАЯ!». Wave D: the name is
-- born with the card, and a NEW Common species gets a small fanfare — a light dim, brighter rays
-- with gold and green, sparks + confetti + a ping at «НОВИНКА!», a «+N 💰»; the same species again
-- is calm.)
tests["catch card: Common reveal — a new species gets a small fanfare, a known one stays calm"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local f = fishing(p)
	local card = f.CatchCard
	local price = card.InfoLabel.Price.Label

	catch(sim, p, CATCHES.Common, 1)
	t.eq(card.Visible, false, "the fish leaps first")
	t.ok(openCard(sim, p), "the card opens after the landing")
	t.eq(f.CatchDim.Visible, true, "a NEW Common species: a light dim (its small fanfare)")
	t.ok(f.CatchRays.Visible and f.CatchRays:FindFirstChild("FxRays"), "rays behind the card")
	t.eq(count(f.CatchRays, "FxRays"), 1, "one ring of rays for a Common fish")
	t.ok(colorNear(f.CatchRays.FxRays.Ray1.BackgroundColor3, Palette.Gold.Top), "…brighter: gold among them")
	t.ok(card.FxScale.Scale < 1, "the card pops in")
	t.ok(card.Rotation < 0, "…with a little turn")
	t.ok(isCandy(card.Banner, UIConfig.Rarity.Common), "the banner in the rarity gradient")
	t.eq(card.InfoLabel.Text, "840 г · цена 11 💰", "InfoLabel holds the summary at once")
	t.eq(card.InfoLabel.Weight.Label.Text, "840 Г", "the weight chip in CAPS")
	t.eq(price.Text, "0", "the price starts at 0")
	t.eq(card.Banner.FxScale.Scale, 0, "the rarity waits for its beat")
	t.eq(card.NameLabel.FxScale.Scale, 1, "the name is born with the card (no blank right half)")
	t.eq(card.NameLabel.TextTransparency, 0, "…readable at once")
	t.eq(card.TapHint.TextTransparency, 1, "the close hint waits for the last beat")
	t.eq(f:FindFirstChild("FxConfetti"), nil, "no confetti before «НОВИНКА!»")
	t.eq(p.PlayerGui.HUD:FindFirstChild("FxFlash"), nil, "no screen flash for a Common fish")
	t.eq(f.TitleSlam.Visible, false, "no giant title for a Common fish")
	t.eq(card.NewStamp.Visible, true, "the first Crucian of the session is «НОВИНКА!»")
	t.eq(card.NewStamp.Label.Text, "НОВИНКА!")

	sim:Advance(0.45)
	t.near(card.FxScale.Scale, 1, 1e-3, "popped in")
	t.near(card.Rotation, 0, 1e-3, "and turned straight")
	t.ok(card.Banner.FxScale.Scale > 0.5, "the rarity is up (c+0.18)")
	t.ok(card.FishGlow:FindFirstChild("FxRays"), "small rays behind the fish")
	t.ok(card.NewStamp.FxScale.Scale > 0, "«НОВИНКА!» stamps in (c+0.38)…")
	t.ok(f:FindFirstChild("FxConfetti"), "…with a handful of confetti")
	t.ok(f:FindFirstChild("FxBurst"), "…and sparks from the stamp")
	sim:Advance(0.45)
	local partial = price.Text
	t.ok(tonumber(partial) ~= nil, "the price is a number while counting")
	t.ok(
		waitFor(sim, function()
			return f:FindFirstChild("FxPriceFloat") ~= nil
		end, 1),
		"a new species: «+11 💰» flies out of the price"
	)
	t.eq(f.FxPriceFloat.Text, "+11 💰")
	sim:Advance(0.5)
	t.eq(price.Text, "11", "the price counted up to the value")
	t.near(card.NewStamp.FxScale.Scale, 1, 1e-3, "«НОВИНКА!» stamped")
	t.ok(card.TapHint.TextTransparency < 0.5, "the close hint shows after the last beat")
	t.ok(
		waitFor(sim, function()
			return count(card.FishGlow, "FxSparkle") > 0 or count(card, "FxSparkle") > 0
		end, 1.5),
		"sparkles around the fish"
	)
	t.eq(
		card.Lip:FindFirstChildOfClass("UIStroke"):FindFirstChild("FxRimFill"),
		nil,
		"a plain Common card keeps its own outline"
	)

	-- The same species again: calm — no «НОВИНКА!», no dim, no confetti, no «+N 💰», rarity rays.
	sim:Advance(UIConfig.CatchCardTime.Common + 1)
	t.eq(card.Visible, false, "closed by itself")
	sim:Advance(2)
	catch(sim, p, CATCHES.Common, 2)
	t.ok(openCard(sim, p))
	t.eq(card.NewStamp.Visible, false, "a second Crucian is not new")
	t.eq(f.CatchDim.Visible, false, "…no dim")
	t.ok(colorNear(f.CatchRays.FxRays.Ray1.BackgroundColor3, UIConfig.Rarity.Common.Rays[1]), "…calm rarity rays")
	local float, confetti = false, false
	for _ = 1, 90 do
		sim:Advance(1 / 30)
		float = float or f:FindFirstChild("FxPriceFloat") ~= nil
		confetti = confetti
			or f:FindFirstChild("FxConfetti") ~= nil
			or p.PlayerGui.HUD:FindFirstChild("FxConfetti") ~= nil
	end
	t.eq(price.Text, "11", "…the price lands")
	t.eq(float, false, "…without «+N 💰»")
	t.eq(confetti, false, "…and without confetti")
	sim:AssertNoErrors({ warnings = true })
end

tests["catch: Legendary and Mythic are louder — tension, a crisp burst at the landing, giant title, dim, second ring, rainbow"] = function(
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
	t.eq(hud:FindFirstChild("FxFlash"), nil, "Common: no screen tint at the landing")
	sim:Advance(1)
	sim:Click(p, card)
	sim:Advance(SKIP_DWELL + 0.1)
	sim:Click(p, card)
	sim:Advance(3)

	catch(sim, p, CATCHES.Legendary, 2)
	sim:Advance(0.6)
	t.ok(hud:FindFirstChild("FxVignette"), "Legendary: the screen edges glow while the fish leaps")
	t.ok(
		waitFor(sim, function()
			return hud:FindFirstChild("FxShock") ~= nil
		end, CARD_OPENS),
		"Legendary: the landing is a burst at the fish (rings, FxShock)"
	)
	t.eq(hud:FindFirstChild("FxFlash"), nil, "…no full-screen flash: the landing stays visible")
	t.ok(
		waitFor(sim, function()
			return hud:FindFirstChild("FxVignette") == nil
		end, 0.1),
		"…and no edge flash either: the tension frame cuts off (v3: a crisp burst at the fish, no wash)"
	)
	t.ok(
		waitFor(sim, function()
			return f.TitleSlam.Visible
		end, 0.2),
		"Legendary: the giant title right after the landing…"
	)
	t.ok(f.CatchRays.Visible and f.CatchRays:FindFirstChild("FxRays"), "…on rays that burst from the fish")
	t.eq(card.Visible, false, "…the card is not up yet")
	t.eq(f.TitleSlam.Letters:FindFirstChild("L12").Text, "!", "«ЛЕГЕНДАРНАЯ!» letter by letter")
	t.eq(f.TitleSlam.Label.Visible, false)
	sim:Advance(0.65)
	t.eq(card.Visible, false, "the title stands alone until it is complete")
	t.near(f.TitleSlam.Letters.L12.FxScale.Scale, 1, 0.02, "…every letter is in")
	t.ok(openCard(sim, p))
	t.eq(f.CatchDim.Visible, true, "Legendary: the screen dims around the card")
	t.eq(count(f.CatchRays, "FxRays"), 2, "Legendary: an extra ring of rays")
	t.ok(isCandy(card.Banner, UIConfig.Rarity.Legendary), "Legendary banner")
	sim:Advance(0.1)
	-- v4: the word left for the banner before the card (CLIMAX.Lead); once the card is born the
	-- word is a transient effect (FxTitleMorph), the title widget is gone — never under the card.
	t.eq(f.TitleSlam.Visible, false, "the title widget is handed off when the card is born")
	local morph = f:FindFirstChild("FxTitleMorph")
	local titleY = if morph then morph.Position.Y.Scale else 1
	t.ok(morph and morph.Visible and titleY < 0.55, `…its copy settles into the banner slot (y {titleY})`)
	t.ok(morph and #morph.Letters:GetChildren() == 12, "…the same word, letter by letter")
	t.eq(card.Banner.FxScale.Scale, 0, "the banner waits for the title")
	sim:Advance(0.2)
	t.near(card.Banner.FxScale.Scale, 1, 1e-3, "the banner grows out of the arriving title (c+0.26)…")
	t.ok(card.Banner.Size.X.Scale < 1.04, `…from narrow ({card.Banner.Size.X.Scale})`)
	sim:Advance(0.2)
	t.eq(f.TitleSlam.Visible, false, "the title became the banner (c+0.4)")
	t.eq(f:FindFirstChild("FxTitleMorph"), nil, "…the melting copy is gone")
	t.eq(#f.TitleSlam.Letters:GetChildren(), 0, "…its letters are gone")
	t.eq(f.TitleSlam.Label.TextTransparency, 0, "…and the faded title label is reset for the next one")
	t.ok(
		card.Lip:FindFirstChildOfClass("UIStroke"):FindFirstChild("FxRimFill"),
		"Legendary: a live gold rim on the card"
	)
	local faceKeys = card.Face.Fill.Color.Keypoints
	t.ok(not colorNear(faceKeys[#faceKeys].Value, Palette.Cream.Bottom, 0.02), "…and a face tinted gold")
	sim:Click(p, card)
	sim:Advance(SKIP_DWELL + 0.1)
	sim:Click(p, card)
	sim:Advance(3)

	catch(sim, p, CATCHES.Mythic, 3)
	t.ok(
		waitFor(sim, function()
			return f.TitleSlam.Visible
		end, CARD_OPENS),
		"Mythic: the giant title"
	)
	t.eq(hud:FindFirstChild("FxFlash"), nil, "Mythic: no screen tint…")
	t.ok(hud:FindFirstChild("FxShock"), "…a burst at the fish (rainbow rings)")
	t.eq(hud:FindFirstChild("FxVignette"), nil, "…no rainbow edge flash (v3: no wash on phones)")
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
	sim:Advance(SKIP_DWELL + 0.1)
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
	local outlineRest = outline.Color -- (UI v5: the card's dark navy outline, Palette.Cream.Lip)
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
		-- The base price lands first (only a tick), then it breathes one beat (0.2 s for a Rare)
		-- before the stamp.
		t.ok(
			waitFor(sim, function()
				return price.Text == tostring(CATCHES.Rare.Value)
			end, 2.5),
			`{case[1]}: the base price first`
		)
		sim:Advance(0.1)
		t.eq(badge.FxScale.Scale, 0, `{case[1]}: the stamp not yet (the base price breathes)`)
		t.eq(fishing(p):FindFirstChild("FxPriceFloat"), nil, `{case[1]}: no «+N 💰» for the base price`)
		sim:Advance(1.0)
		t.near(badge.FxScale.Scale, 1, 0.02, `{case[1]}: stamped in`)
		t.eq(card.InfoLabel.Price.Multiplier.Visible, true, `{case[1]}: «×N» slammed`)
		t.eq(price.Text, tostring(fish.Value), `{case[1]}: recounted to the full price`)
		t.ok(outline:FindFirstChild("FxRimFill"), `{case[1]}: the card outline in its colours`)
		local float = fishing(p):FindFirstChild("FxPriceFloat")
		t.ok(float and float.Text == `+{fish.Value} 💰`, `{case[1]}: «+N 💰» with the full price`)
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
		t.eq(outline:FindFirstChild("FxRimFill"), nil, `{case[1]}: the outline is plain again`)
		t.ok(colorNear(outline.Color, outlineRest), `{case[1]}: the card's own outline colour`)
		sim:Advance(1)
	end
	sim:Advance(3)
	t.eq(#leftovers(p), 0, `no effect instances left: {table.concat(leftovers(p), ", ")}`)
	sim:AssertNoErrors({ warnings = true })
end

-- UI v2 (motion M4): the card's beats come one by one — rarity → «НОВИНКА!» → chips → price
-- landing (→ mutation stamp → full price) → close hint; the name is born with the card (wave D:
-- no blank right half). Tempo by rarity (wave D, R3-3): Common and Rare — fished dozens of times —
-- never two within ~0.18 s (a 0.2 s ladder; the banner unrolls at c+0.18), Epic and rarer never
-- within ~0.25 s (0.27 s; the giant title flies into the banner from c+0, the banner grows out of
-- it at its end). The count-up runs into the landing (R3-2): 0.15 s before it the label shows at
-- most ~92 % of the price.
local BEAT_MIN_CALM = 0.18 - 1 / 60 -- one 60 fps frame of measuring slack
local BEAT_MIN = 0.25 - 1 / 60

tests["catch card beats: one at a time, ≥ 0.18 s (Common / Rare) or ≥ 0.25 s (Epic+) apart, in order"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	ready(sim, p)
	local f = fishing(p)
	local card = f.CatchCard
	local price = card.InfoLabel.Price.Label
	local gold = table.clone(CATCHES.Rare)
	gold.Id = "Perch"
	gold.Mutation = "Gold"
	gold.Value = CATCHES.Rare.Value * 2
	local cases = {
		{ name = "Common", fish = CATCHES.Common, base = CATCHES.Common.Value, gap = BEAT_MIN_CALM, new = true },
		{ name = "Legendary", fish = CATCHES.Legendary, base = CATCHES.Legendary.Value, gap = BEAT_MIN, new = true },
		{ name = "Gold Perch", fish = gold, base = CATCHES.Rare.Value, gap = BEAT_MIN_CALM, new = true },
		{ name = "Common again", fish = CATCHES.Common, base = CATCHES.Common.Value, gap = BEAT_MIN_CALM, new = false },
	}
	local function scale(gui: any): number
		local found = gui:FindFirstChild("FxScale")
		return if found then found.Scale else 1
	end
	for index, case in cases do
		catch(sim, p, case.fish, index)
		t.ok(openCard(sim, p), `{case.name}: the card opens`)
		t.ok(
			scale(card.NameLabel) > 0.95 and card.NameLabel.TextTransparency < 0.05,
			`{case.name}: the name is born with the card`
		)
		local mutated = case.fish.Mutation ~= nil
		local probes: { { name: string, shown: () -> boolean } } = {
			{
				name = "banner",
				shown = function()
					return scale(card.Banner) > 0.05
				end,
			},
			{
				name = "chips",
				shown = function()
					return scale(card.InfoLabel.Weight) > 0.05
				end,
			},
			{
				name = "price",
				shown = function()
					return price.Text == tostring(case.base)
				end,
			},
			{
				name = "hint",
				shown = function()
					return card.TapHint.TextTransparency < 0.95
				end,
			},
		}
		if case.new then
			table.insert(probes, 2, {
				name = "new",
				shown = function()
					return card.NewStamp.Visible and scale(card.NewStamp) > 0.05
				end,
			})
		else
			t.eq(card.NewStamp.Visible, false, `{case.name}: a known species is not «НОВИНКА!»`)
		end
		if mutated then
			local at = #probes -- before the close hint
			table.insert(probes, at, {
				name = "mutation",
				shown = function()
					return scale(card.MutationLabel) > 0.05
				end,
			})
			table.insert(probes, at + 1, {
				name = "full price",
				shown = function()
					return price.Text == tostring(case.fish.Value)
				end,
			})
		end
		local times: { [string]: number } = { card = 0 }
		local shownPrice: { { at: number, value: number } } = {}
		local elapsed, found = 0, 0
		while elapsed < 4 and found < #probes do
			for _, probe in probes do
				if times[probe.name] == nil and probe.shown() then
					times[probe.name] = elapsed
					found += 1
				end
			end
			local value = tonumber((string.gsub(price.Text, "\u{00A0}", "")))
			if value then
				table.insert(shownPrice, { at = elapsed, value = value })
			end
			sim:Advance(1 / 60)
			elapsed += 1 / 60
		end
		-- The count-up runs into the landing: 0.15 s before it, at most ~92 % of the price.
		local landedAt = times.price
		if landedAt then
			local before = 0
			for _, sample in shownPrice do
				if sample.at <= landedAt - 0.15 then
					before = sample.value
				end
			end
			t.ok(
				before <= case.base * 0.93,
				`{case.name}: still counting 0.15 s before the landing ({before} of {case.base})`
			)
		end
		local order = { "card" }
		for _, probe in probes do
			t.ok(times[probe.name] ~= nil, `{case.name}: {probe.name} shows`)
			table.insert(order, probe.name)
		end
		local line = {}
		for _, name in order do
			table.insert(line, `{name} {string.format("%.2f", times[name] or -1)}`)
		end
		local summary = table.concat(line, ", ")
		for i = 2, #order do
			local a, b = times[order[i - 1]], times[order[i]]
			if a and b then
				t.ok(
					b - a >= case.gap,
					`{case.name}: {order[i - 1]} → {order[i]} ≥ {string.format("%.2f", case.gap)} s apart ({summary})`
				)
			end
		end
		sim:Click(p, card)
		sim:Advance(0.05)
		t.eq(card.Visible, false, `{case.name}: a tap on the settled card closes it`)
		sim:Advance(2)
	end
	sim:AssertNoErrors({ warnings = true })
end

-- A skip in the middle of the mutation beat: its tails (the «×N» stamp, the recount, the bump) do
-- not play on the settled card — the price never drops back to the base price.
tests["mutation: a skip mid-stamp settles it — no recount from the base price afterwards"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local card = fishing(p).CatchCard
	local price = card.InfoLabel.Price.Label
	local fish = table.clone(CATCHES.Rare)
	fish.Mutation = "Gold"
	fish.Value = CATCHES.Rare.Value * 2
	catch(sim, p, fish, 1)
	t.ok(openCard(sim, p))
	-- The stamp beat begins one beat (0.2 s, Rare) after the base price lands; its «×N» comes
	-- 0.15 s later, the recount 0.25 s later.
	t.ok(
		waitFor(sim, function()
			return card.InfoLabel.Price.Multiplier.Visible
		end, 3),
		"the mutation beat has begun (its tails not yet)"
	)
	sim:Advance(0.05)
	sim:Click(p, card)
	sim:Advance(1 / 60)
	t.eq(price.Text, tostring(fish.Value), "the skip shows the full price")
	local dropped = false
	for _ = 1, 45 do
		sim:Advance(1 / 60)
		if price.Text ~= tostring(fish.Value) then
			dropped = true
		end
	end
	t.eq(dropped, false, "the price stays (no recount from the base price after the skip)")
	t.near(card.InfoLabel.Price.Multiplier.FxScale.Scale, 1, 1e-3, "«×N» in place")
	t.eq(card.Visible, true)
	sim:AssertNoErrors({ warnings = true })
end

-- (UI v2: a tap during the reveal skips it; wave D: the card itself is the projectile — it flies
-- into the counter shrinking to a speck, a 🐟 with ★ leaves beside it 0.05 s later and they land
-- together; the rays shrink with it — timings this test checked before. The first catch: the
-- counter appears with «🐟 0» as the card leaves, so the 🐟 has a target.)
tests["closing: skip, then close — the card itself flies into the counter, 🐟 ★ with it, +1 ≈ 0.35 s; nothing leaks"] = function(
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
	local button = f.ActionArea.ActionButton
	t.eq(button.Caption.Text, "ЗАБРАТЬ!", "the settled card: the button says «ЗАБРАТЬ!»")
	t.ok(isCandy(button, Palette.Leaf), "…a green plate, awake")
	t.eq(counter.Visible, false, "the first catch: no counter yet")
	sim:Advance(0.2)
	sim:Click(p, card)
	sim:Advance(0.02)
	t.eq(card.Visible, true, "a second tap right after the skip does not close it (SKIP_DWELL)")
	sim:Advance(SKIP_DWELL)
	sim:Click(p, card)
	sim:Advance(0.02)
	t.eq(card.Visible, false, "hidden at once")
	t.eq(button.Caption.Text, "ЖДЁМ…", "the button freezes again until the 🐟 arrives")
	t.eq(card.Viewport:FindFirstChildOfClass("Model"), nil, "the fish model is gone from the card")
	local ghost = f:FindFirstChild("FxCardOut")
	t.ok(ghost, "its ghost shrinks away…")
	t.eq(hud:GetAttribute("CounterIncoming"), "Rare", "…towards the counter, which knows what flies in")
	t.eq(counter.Visible, true, "the first catch: the counter appears…")
	t.eq(counter.Label.Text, "0", "…with the number before the fish")
	t.eq(button.Ring.Transparency, 1, "the frozen button has no halo during the flight")
	-- (Wave D, R3-6: the card itself is the projectile — it flies almost into the counter,
	-- shrinking to a speck; the 🐟 and ★ leave at once from near its start and land with it.)
	sim:Advance(0.06)
	t.ok(hud:FindFirstChild("FxFly"), "a 🐟 leaves right away, beside the flying card")
	sim:Advance(0.16)
	t.ok(ghost.FxScale.Scale < 0.6, `the card shrinks as it flies ({ghost.FxScale.Scale})`)
	local stars = 0
	for _, item in hud:GetChildren() do
		if item.Name == "FxFly" and item.Text == "★" then
			stars += 1
		end
	end
	t.ok(stars > 0, "★ in the rarity colours follow it")
	t.ok(
		UiFx.activeJobs() <= 3,
		`the close flight: ≤ 3 frame effects — the card, the 🐟, the ★ flock ({UiFx.activeJobs()})`
	)
	t.eq(hud:GetAttribute("CounterHold"), 0, "the counter still holds its number while they fly")
	t.eq(button.Ring.Transparency, 1, "…still no halo on the frozen button")
	sim:Advance(0.15) -- close + 0.39 s
	t.eq(f.CatchRays:FindFirstChild("FxRays"), nil, "the rays shrank with the card")
	t.eq(f:FindFirstChild("FxCardOut"), nil, "the card is gone into the counter")
	t.eq(f.CatchDim.Visible, false, "the dim faded away")
	t.eq(hud:GetAttribute("CounterHold"), nil, "the 🐟 arrived with the card (tap → +1 ≈ 0.35 s)")
	t.eq(hud:GetAttribute("CounterIncoming"), nil, "…and the incoming mark is cleared")
	t.eq(counter.Label.Text, "1")
	t.ok(counter.FxScale.Scale > 1, "the counter bumps when the fish arrives")
	t.ok(counter:FindFirstChild("FxRing", true), "…with a ring in the rarity colour (round the 🐟)")
	sim:Advance(0.3)
	t.eq(hud:FindFirstChild("FxFlyFrom"), nil, "the 🐟's start point is gone once the last ★ left")
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
	t.eq(counter.Label.Text, "2")
	t.eq(#leftovers(p), 0, `no effect instances left: {table.concat(leftovers(p), ", ")}`)
	t.eq(frameConnections(sim, p), idleFrames)
	t.eq(sim:CountConnections(p), idleConnections)
	sim:AssertNoErrors({ warnings = true })
end

-- Wave D (F1, F2): after the winning tap the kid keeps mashing the action button (now the frozen
-- «ЖДЁМ…»). An action input never skips the reveal — only a tap on the card does — and closes the
-- card only once it is shown whole («ЗАБРАТЬ!») and the mashing has paused (CARD.Mash 0.3 s).
-- «ЗАБРАТЬ!» keeps its white halo (the button's unfade does not fight its look) and the frozen
-- button has none during the 🐟 flight.
tests["catch: mashing the action button never skips the reveal; «ЗАБРАТЬ!» (with its halo) closes after a pause"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	ready(sim, p)
	local f = fishing(p)
	local card = f.CatchCard
	local button = f.ActionArea.ActionButton
	local price = card.InfoLabel.Price.Label
	serverSays(sim, p, "Minigame", minigame("Legendary"))
	sim:Advance(0.3)
	catch(sim, p, CATCHES.Legendary, 1)

	-- 5 Hz from the win.
	local elapsed = 0
	local opened: number? = nil
	local settledAt: number? = nil
	local midPrice: string? = nil
	local seen: { [string]: boolean } = {}
	local distinct = 0
	local function mash(untilOpen: number)
		while opened == nil or elapsed < opened + untilOpen do
			sim:Click(p, button)
			for _ = 1, 12 do
				sim:Advance(1 / 60)
				elapsed += 1 / 60
				if card.Visible then
					opened = opened or elapsed
					if not seen[price.Text] then
						seen[price.Text] = true
						distinct += 1
					end
					if midPrice == nil and elapsed >= (opened :: number) + 1.2 then
						midPrice = price.Text
					end
					if settledAt == nil and button.Caption.Text == "ЗАБРАТЬ!" then
						settledAt = elapsed
					end
				end
			end
			if elapsed > CARD_OPENS + 5 then
				break
			end
		end
	end
	mash(1.5)
	t.ok(opened ~= nil, "the card opened while the button was mashed")
	t.eq(card.Visible, true, "open + 1.5 s: still up (the mashing neither skipped nor closed it)")
	t.ok(midPrice ~= nil and midPrice ~= "590", `open + 1.2 s: the price still counting ({midPrice})`)
	t.ok(distinct >= 4, `the price counted up through {distinct} values`)
	mash(2.6) -- the card settles at ≈ c + 1.84 (Legendary): keep mashing past it
	t.ok(settledAt ~= nil, "the card settled by itself: «ЗАБРАТЬ!»")
	t.eq(card.Visible, true, "…and the mashing does not close it")
	t.eq(price.Text, "590")
	t.ok(
		button.Ring.Transparency < 0.3,
		`«ЗАБРАТЬ!» has its white halo 0.3 s after settling (Ring {button.Ring.Transparency})`
	)
	sim:Advance(0.4)
	sim:Click(p, button)
	sim:Advance(0.02)
	t.eq(card.Visible, false, "a press after a pause closes the card")
	t.eq(button.Caption.Text, "ЖДЁМ…", "the button freezes while the 🐟 flies…")
	for _ = 1, 12 do
		sim:Advance(1 / 60)
		t.eq(button.Ring.Transparency, 1, "…with no halo")
	end
	sim:AssertNoErrors({ warnings = true })
end

-- Wave D (F6): the Mythic price flare (rim 1.35× thicker for 0.4 s) dies with the card — a tap in
-- its last 0.1 s used to leave the card outline fat for the rest of the session — and a rim takes
-- its base thickness from the builder (BaseThickness), never from the live stroke.
tests["rims: the Mythic price flare dies with the card; a rim restores the builder's thickness"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	ready(sim, p)
	local card = fishing(p).CatchCard
	local outline = card.Lip:FindFirstChildOfClass("UIStroke")
	local price = card.InfoLabel.Price.Label
	local base = outline.Thickness
	catch(sim, p, CATCHES.Mythic, 1)
	t.ok(openCard(sim, p))
	t.ok(
		waitFor(sim, function()
			return price.Text == "2\u{00A0}400"
		end, 3),
		"the Mythic price lands (its rim flares)"
	)
	t.ok(
		waitFor(sim, function()
			return card.TapHint.TextTransparency < 0.95
		end, 0.4),
		"…the card settles one beat later, inside the 0.4 s flare"
	)
	sim:Click(p, card)
	sim:Advance(0.6)
	t.eq(card.Visible, false, "closed during the flare")
	t.near(outline.Thickness, base, 1e-3, "the outline is back to its own thickness")

	-- Whatever leaves the stroke thick, the next rim does not take that for its base.
	outline.Thickness = base * 3
	sim:Advance(2)
	catch(sim, p, CATCHES.Legendary, 2)
	t.ok(openCard(sim, p))
	t.ok(outline:FindFirstChild("FxRimFill"), "a Legendary rim on the card")
	sim:Advance(0.5)
	sim:Click(p, card)
	sim:Advance(SKIP_DWELL + 0.1)
	sim:Click(p, card)
	sim:Advance(0.6)
	t.eq(card.Visible, false)
	t.near(outline.Thickness, base, 1e-3, "the rim restores the builder's thickness")
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
	sim:Advance(1.2)
	t.eq(card.Visible, false, "Legendary: a 1.5 s hold after the landing (the arms-up landing and the giant title)")
	t.eq(fishing(p).TitleSlam.Visible, true, "…the title is up meanwhile")
	sim:Advance(0.4)
	t.eq(card.Visible, true, "the card is up — well before the fallback (LeapTime + 0.3 s, then the hold)")
	sim:Advance(6)

	-- No leap at all (no character / no model): the signal comes before "Caught" — still used.
	sim:Run(function()
		fx.OwnFishLanded:Fire("Common", Vector3.new(0, 10, 0))
	end, p)
	sim:Advance(0.05)
	catch(sim, p, CATCHES.Common, 2)
	sim:Advance(0.45)
	t.eq(card.Visible, true, 'a landing just before "Caught" opens the card at once (+ hold)')
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- Hint, idle
--------------------------------------------------------------------------------

tests["hint: a glass pill with an icon by kind, slides up with a bounce"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local hint = fishing(p).Hint
	sim:Advance(1)
	t.eq(hint.Visible, true)
	t.eq(hint.Text, "Жми «Забросить»")
	t.eq(hint.Label.Text, hint.Text, "the label shows the value")
	t.eq(hint.IconSocket.Icon.Text, "💡", "info: 💡 (outlined, overhanging, like the toasts)")
	t.ok(isCandy(hint, Palette.Glass), "info: the dark glass pill")
	t.eq(hint:GetAttribute("CandyStyle"), "glass")
	local rest = hint.Position

	serverSays(sim, p, "Denied", { Reason = "far", Text = "Подойди к краю своего пирса" })
	t.eq(hint.Label.Text, "Подойди к краю своего пирса")
	t.eq(hint.IconSocket.Icon.Text, "⚠️", "warning: ⚠️")
	t.ok(isCandy(hint, Palette.Sun), "warning: an orange plate")
	t.eq(hint:GetAttribute("CandyStyle"), "sim", "… solid, with its outline")
	-- UI v2 (M6): it slides up by a few px only (the hotbar is right under it) and pops.
	t.near(hint.Position.Y.Scale, rest.Y.Scale, 1e-6, "slides by pixels, not by a share of the screen")
	t.ok(hint.Position.Y.Offset > rest.Y.Offset, "slides up from below")
	t.ok(hint.Position.Y.Offset - rest.Y.Offset <= 8, "… by a few px: ≥ 16 px from the hotbar all the way")
	t.ok(hint.FxScale.Scale < 1, "pops")
	sim:Advance(0.6)
	t.near(hint.Position.Y.Offset, rest.Y.Offset, 1e-3, "at rest")
	t.near(hint.FxScale.Scale, 1, 1e-3)

	serverSays(sim, p, "Idle", { Reason = "stop" })
	t.eq(hint.Label.Text, "Леска смотана")
	t.eq(hint.IconSocket.Icon.Text, "💡", "info again")
	t.ok(isCandy(hint, Palette.Glass), "glass again")
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
-- UI v2, playing: key chip, «КУДА ИДТИ?», predicted hits, rider, aura, tap pad, cue, nibbles
--------------------------------------------------------------------------------

tests["v2 parts: tiers on the playing widgets, key chip, «!» glyph slot, bobber, rider, ▼ head, ⏱, tap pad"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local f = fishing(p)
	local button = f.ActionArea.ActionButton
	-- Type tiers (FND-03): the caption scale is the same on every screen; never under 12 px.
	local tiers = {
		[button.Caption] = "Button",
		[f.ActionArea.StopButton.Caption] = "Button",
		[f.Minigame.Title] = "Title",
		[f.Minigame.Help] = "Body",
		[f.Hint.Label] = "Body",
		[button.KeyChip.Key] = "Small",
	}
	for label, tier in tiers do
		t.eq(label:GetAttribute("TextTier"), tier, `{label:GetFullName()}: tier {tier}`)
	end
	for _, root in { f.ActionArea, f.BiteAlert, f.Minigame, f.Hint } do
		for _, d in root:GetDescendants() do
			local constraint = d:FindFirstChildOfClass("UITextSizeConstraint")
			if d:IsA("TextLabel") and constraint then
				t.ok(constraint.MinTextSize >= 12, `{d:GetFullName()}: min text {constraint.MinTextSize} ≥ 12`)
			end
		end
	end
	-- The key chip instead of a «[F]» suffix. The icon is an outlined emoji (SIM-C1-01: exactly one
	-- "Outline" stroke, on, 3.5 at 720 — the «!» glyph only thickens it and turns its fill on).
	t.eq(button.KeyChip.Key.Text, "F")
	local iconStrokes = 0
	for _, c in button.Icon:GetChildren() do
		if c:IsA("UIStroke") then
			iconStrokes += 1
		end
	end
	t.eq(iconStrokes, 1, "one contour on the action icon")
	t.ok(button.Icon.Outline.Enabled, "the emoji is outlined like the reference's icons")
	t.eq(button.Icon.Outline:GetAttribute("BaseThickness"), 3.5)
	t.eq(button.Icon.TextFill.Enabled, false)
	t.eq(button.TapCue.Text, "👆")
	t.eq(button.TapCue.Visible, false)
	t.eq(button.Bobber.Visible, false)
	-- Minigame: the 🐟 rider under the needle, the ▼ head on the needle, ⏱ by the time bar.
	local track = f.Minigame.Track
	t.eq(track.Rider.Text, "🐟")
	t.ok(
		track.Rider.ZIndex > track.Zone.ZIndex and track.Rider.ZIndex < track.Needle.ZIndex,
		"rider: over the zone, under the needle"
	)
	t.eq(track.Needle.Head.Text, "▼")
	t.eq(f.Minigame.Clock.Text, "⏱")
	t.ok(f.Minigame.TapPad:IsA("GuiButton") and f.Minigame.TapPad.BackgroundTransparency == 1, "a transparent tap pad")
	t.eq(f.Minigame.AuraStroke.Enabled, false, "no rarity rim until an Epic+ minigame")
	sim:AssertNoErrors({ warnings = true })
end

tests["far from the spot: «КУДА ИДТИ?» 🧭 casts nothing — the hint pops and the beam flares"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local rod = giveRod(sim, p)
	sim:EquipTool(p, rod) -- at the spawn, far from the fishing spot
	sim:Advance(0.5)
	local f = fishing(p)
	local button = f.ActionArea.ActionButton
	t.eq(button.Caption.Text, "КУДА ИДТИ?")
	t.eq(button.Icon.Text, "🧭")
	t.ok(isCandy(button, Palette.Slate), "a calm Slate button")
	t.eq(button.KeyChip.Visible, false, "no key: the key does not cast here")
	t.eq(f.Hint.Label.Text, "Иди в сверкающий круг на\u{00A0}краю\u{00A0}пирса")
	local beam = sim:GetRoot(p):FindFirstChild("FishingGuide")
	local width = beam.Width1
	sim:Advance(0.4)
	pressF(sim, p)
	t.eq(#sim:ServerEventsFor(p, "FishingCast"), 0, "no cast far from the spot")
	t.ok(beam.Width1 > width, "the guide beam flares")
	-- UI v2 (M4): the button shows the way, it does not scold: a calm info hint 💡 pops again.
	t.ok(isCandy(f.Hint, Palette.Glass), "the hint pops again, calm (info, not a warning)")
	t.eq(f.Hint.IconSocket.Icon.Text, "💡")
	t.ok(f.Hint.FxScale.Scale < 1, "… with a pop")
	standAtSpot(sim, p)
	t.eq(button.Caption.Text, "ЗАБРОСИТЬ", "at the spot: «ЗАБРОСИТЬ»")
	t.eq(button.KeyChip.Visible, true, "the F key chip on a PC")
	pressF(sim, p)
	t.eq(#sim:ServerEventsFor(p, "FishingCast"), 1, "casts at the spot")
	sim:AssertNoErrors({ warnings = true })
end

tests["predicted hit: the punch plays on the tap; the final hit is the catch's; a rejected hit ends in the miss ghost"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local mini = fishing(p).Minigame
	-- A slow needle right in the zone, 2 hits needed: the first tap is a hit.
	serverSays(sim, p, "Minigame", minigame("Common", { U0 = 0.6, Speed = 0.02, ZoneCenter = 0.62, HitsNeeded = 2 }))
	sim:Advance(0.4)
	pressF(sim, p)
	t.eq(#sim:ServerEventsFor(p, "FishingTap"), 1)
	local word = mini:FindFirstChild("FxFloat")
	t.ok(word, "the word before the server answers")
	t.eq(word.Text, "ИДЕАЛЬНО!", "at the zone centre: perfect")
	t.ok(mini:FindFirstChild("FxBurst") and mini:FindFirstChild("FxStar"), "sparks and ⭐ fly")
	t.near(mini.Track.Zone.Position.X.Scale, 0.62, 1e-6, "the zone waits for the server")
	serverSays(sim, p, "Zone", { ZoneCenter = 0.2, Hits = 1 })
	t.eq(count(mini, "FxFloat"), 1, "no second word when the server confirms")
	t.near(mini.Track.Zone.Position.X.Scale, 0.2, 1e-6, "the zone jumps on the answer")
	t.ok(mini.Pips.Pip1.Star.FxScale.Scale > 1, "the pip is stamped on the answer")
	sim:Advance(1)

	-- The last hit: no punch here (it starts the catch card — onCaught).
	serverSays(
		sim,
		p,
		"Minigame",
		minigame("Common", { U0 = 0.6, Speed = 0.02, ZoneCenter = 0.62, Hits = 1, HitsNeeded = 2 })
	)
	sim:Advance(0.4)
	pressF(sim, p)
	t.eq(count(mini, "FxFloat"), 0, "the winning tap is not celebrated as a hit")
	sim:Advance(0.5)

	-- A predicted hit the server rejects: the miss ghost wins.
	serverSays(sim, p, "Minigame", minigame("Rare", { U0 = 0.6, Speed = 0.02, ZoneCenter = 0.62, HitsNeeded = 2 }))
	sim:Advance(0.4)
	pressF(sim, p)
	t.ok(mini:FindFirstChild("FxFloat"), "predicted")
	serverSays(sim, p, "Lost", { Reason = "miss", Text = "" })
	local ghost = fishing(p):FindFirstChild("FxMinigameMiss")
	t.ok(ghost and ghost.FxFloat.Text == "МИМО!", "«МИМО!» overrides the prediction")
	t.eq(count(ghost, "FxFloat"), 1, "the ghost carries no copy of the predicted word")
	sim:Advance(1.5)
	t.eq(#leftovers(p), 0, `no effect instances left: {table.concat(leftovers(p), ", ")}`)
	sim:AssertNoErrors({ warnings = true })
end

-- The winning tap (UI v2.1): no hit word — the needle freezes gold where the player tapped and the
-- zone glows gold until the server answers; the win ghost keeps the needle there.
tests["winning tap: the needle freezes gold until Caught (or a timeout); the win ghost keeps it, «ПОЙМАНА!» is big"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local f = fishing(p)
	local mini = f.Minigame
	local needle, flash = mini.Track.Needle, mini.Track.Zone.Flash
	local function taps(): number
		return #sim:ServerEventsFor(p, "FishingTap")
	end

	-- No answer: the hold ends by itself and the game goes on.
	serverSays(sim, p, "Minigame", minigame("Common", { U0 = 0.6, Speed = 0.05, ZoneCenter = 0.62 }))
	sim:Advance(0.4)
	pressF(sim, p)
	t.eq(taps(), 1)
	t.eq(count(mini, "FxFloat"), 0, "no hit word: the win is the catch's")
	t.ok(colorNear(needle.BackgroundColor3, Palette.Gold.Top), "the needle turns gold")
	t.ok(
		flash.BackgroundTransparency < 0.5 and colorNear(flash.BackgroundColor3, Palette.Gold.Top),
		"the zone glows gold"
	)
	t.ok(count(mini.Track.Zone, "FxRing") > 0, "a ring from the zone")
	local held = needle.Position.X.Scale
	sim:Advance(0.25)
	t.near(needle.Position.X.Scale, held, 1e-6, "the needle stays where the player tapped")
	pressF(sim, p)
	t.eq(taps(), 1, "no more taps go out while the answer is on its way")
	sim:Advance(1.4)
	t.ok(math.abs(needle.Position.X.Scale - held) > 1e-3, "no answer within the hold: the needle runs again")
	t.ok(colorNear(needle.BackgroundColor3, UIConfig.White), "…white")
	t.eq(flash.BackgroundTransparency, 1, "…and the zone is calm")
	pressF(sim, p)
	t.eq(taps(), 2, "taps go out again")

	-- The answer comes: the win ghost shows the needle where the player tapped.
	serverSays(sim, p, "Minigame", minigame("Common", { U0 = 0.6, Speed = 0.05, ZoneCenter = 0.62 }))
	sim:Advance(0.4)
	pressF(sim, p)
	held = needle.Position.X.Scale
	sim:Advance(0.2)
	catch(sim, p, CATCHES.Common, 1)
	local ghost = f:FindFirstChild("FxMinigameWin")
	t.ok(ghost, "the win ghost")
	t.near(ghost.Track.Needle.Position.X.Scale, held, 1e-6, "…shows the needle where the player tapped")
	t.eq(ghost:FindFirstChild("TapPad"), nil, "…takes no taps")
	t.eq(ghost.Active, false)
	t.eq(count(ghost, "FxGhost"), 0, "…without the frozen needle trail")
	local word = p.PlayerGui.HUD:FindFirstChild("FxFloat")
	t.ok(word and word.Text == "ПОЙМАНА!", "«ПОЙМАНА!»")
	t.ok(word and word.Size.Y.Offset >= 56, `the loudest word of the minigame ({word and word.Size.Y.Offset} px)`)
	local slam = word and word:FindFirstChildOfClass("UIScale")
	t.ok(slam and slam.Scale > 1.2, `…slammed in from big ({slam and slam.Scale})`)
	sim:Advance(0.45)
	t.eq(f:FindFirstChild("FxMinigameWin"), nil, "the ghost leaves early (the leap starts there)")
	t.eq(f.Minigame.Visible, false)
	t.ok(colorNear(needle.BackgroundColor3, UIConfig.White), "the live needle is reset for the next game")
	sim:AssertNoErrors({ warnings = true })
end

tests["minigame rarity: the rider by rarity rides the zone and hops; Rare light rim, Epic+ rim, rays, edges; Legendary+ word"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local hud = p.PlayerGui.HUD
	local mini = fishing(p).Minigame
	local rider = mini.Track.Rider
	local idleFrames = frameConnections(sim, p)

	local riderSize = rider.Size
	serverSays(sim, p, "Minigame", minigame("Common", { ZoneCenter = 0.4 }))
	sim:Advance(0.4)
	t.eq(rider.Text, "🐟", "Common: 🐟")
	t.eq(mini.AuraStroke.Enabled, false, "Common: no rim")
	serverSays(sim, p, "Minigame", minigame("Rare", { ZoneCenter = 0.4 }))
	sim:Advance(0.4)
	t.eq(rider.Visible, true)
	t.eq(rider.Text, "🐠", "Rare: 🐠")
	t.near(rider.Position.X.Scale, 0.4, 1e-6, "the rider sits on the zone")
	t.eq(mini.AuraStroke.Enabled, true, "Rare: a light rim (UI v2, W7)")
	t.eq(mini:FindFirstChild("FxRays"), nil, "Rare: no rays")
	t.eq(hud:FindFirstChild("FxVignette"), nil, "Rare: no screen edges")
	t.eq(fishing(p):FindFirstChild("FxFloat"), nil, "Rare: no rarity word over the panel")
	serverSays(sim, p, "Zone", { ZoneCenter = 0.8, Hits = 1 })
	sim:Advance(0.3)
	t.near(rider.Position.X.Scale, 0.8, 1e-3, "the rider hopped to the new zone")

	serverSays(sim, p, "Minigame", minigame("Legendary", { ZoneCenter = 0.3 }))
	local word = fishing(p):FindFirstChild("FxFloat")
	t.ok(word and word.Text == "ЛЕГЕНДАРНАЯ!", "Legendary: the rarity word floats over the panel once")
	t.eq(word.Active, false, "… and takes no taps")
	t.ok(
		word.AbsolutePosition.Y + word.AbsoluteSize.Y * 0.5 < mini.AbsolutePosition.Y,
		"… above the panel (never over the needle and the zone)"
	)
	t.eq(rider.Text, "🦈", "Legendary: 🦈")
	t.ok(rider.Size.Y.Scale > riderSize.Y.Scale * 1.2, "… bigger")
	sim:Advance(0.6)
	t.eq(mini.AuraStroke.Enabled, true, "Legendary: a gold rim")
	t.ok(mini:FindFirstChild("FxRays"), "rays behind the panel")
	t.eq(mini.FxRays.ZIndex, 0, "…behind the candy")
	t.ok(hud:FindFirstChild("FxVignette"), "the screen edges glow")
	serverSays(sim, p, "Lost", { Reason = "timeout", Text = "" })
	t.eq(mini.AuraStroke.Enabled, false, "the rim goes with the minigame")
	t.eq(rider.Visible, false)
	t.eq(rider.Size, riderSize, "the rider back to its size")
	sim:Advance(1.5)
	t.eq(hud:FindFirstChild("FxVignette"), nil, "the edges faded away")
	t.eq(#leftovers(p), 0, `no effect instances left: {table.concat(leftovers(p), ", ")}`)
	t.eq(frameConnections(sim, p), idleFrames, "no frame work left")
	sim:AssertNoErrors({ warnings = true })
end

tests["touch: a tap on the minigame panel counts; 👆 shows a first-timer the button while the needle is in"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	ready(sim, p)
	local mini = fishing(p).Minigame
	local cue = fishing(p).ActionArea.ActionButton.TapCue
	-- The needle runs 0.1 → 0.9 (speed 0.4): out of the zone, then in it.
	serverSays(sim, p, "Minigame", minigame("Common", { U0 = 0.1, Speed = 0.4, ZoneCenter = 0.75 }))
	t.eq(mini.TapPad.Visible, true, "the tap pad is on with a touch screen")
	t.eq(cue.Visible, false, "no cue while the needle is out of the zone")
	local shown = false
	for _ = 1, 30 do
		sim:Advance(0.05)
		if cue.Visible then
			shown = true
			break
		end
	end
	t.ok(shown, "👆 while the needle is in the zone")
	sim:Click(p, mini.TapPad)
	sim:Advance(0.05)
	t.eq(#sim:ServerEventsFor(p, "FishingTap"), 1, "a panel tap is a tap")
	serverSays(sim, p, "Lost", { Reason = "miss", Text = "" })
	t.eq(mini.TapPad.Visible, false, "the pad goes with the minigame")
	t.eq(cue.Visible, false)
	sim:AssertNoErrors({ warnings = true })
end

tests["hint: hidden while the bite and the minigame are up (they share the column)"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local f = fishing(p)
	serverSays(sim, p, "Denied", { Reason = "busy", Text = "Удочка уже заброшена" })
	t.eq(f.Hint.Visible, true)
	serverSays(sim, p, "Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
	serverSays(sim, p, "Bite", { Window = 1.8 })
	t.eq(f.Hint.Visible, false, "the bite takes the column")
	t.eq(f.BiteAlert.Position.Y.Offset, f.Minigame.Position.Y.Offset, "one bottom line")
	pressF(sim, p)
	serverSays(sim, p, "Minigame", minigame("Common"))
	t.eq(f.Hint.Visible, false, "the minigame takes the column")
	sim:AssertNoErrors({ warnings = true })
end

tests["waiting: 1–2 nibbles twitch the button with «?» and send nothing"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	ready(sim, p)
	local button = fishing(p).ActionArea.ActionButton
	local idleConnections = sim:CountConnections(p)
	serverSays(sim, p, "Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
	local nibbles = 0
	local seen = false
	for _ = 1, 44 do
		sim:Advance(0.05)
		local q = button:FindFirstChild("FxFloat")
		if q and q.Text == "?" then
			if not seen then
				nibbles += 1
			end
			seen = true
		else
			seen = false
		end
	end
	t.ok(nibbles >= 1 and nibbles <= 2, `1–2 nibbles (saw {nibbles})`)
	t.eq(#sim:ServerEventsFor(p, "FishingHook"), 0, "a nibble is not a bite")
	t.eq(#sim:ServerEventsFor(p, "FishingTap"), 0)
	serverSays(sim, p, "Idle", { Reason = "stop" })
	sim:Advance(4)
	t.eq(sim:CountConnections(p), idleConnections, "timers only")
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
	end
	sim:Advance(0.5)
	-- «СМОТАТЬ» shows while waiting (UI v2, M1: it hides once a fish is on the hook).
	local stops = {}
	for _, device in devices do
		local p = players[device]
		local stop = p.PlayerGui.HUD.Fishing.ActionArea.StopButton
		t.ok(stop.Visible, `{device}: «СМОТАТЬ» while waiting`)
		stops[device] = rectOf(sim, p, stop)
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
		t.ok(f.ActionArea.ActionButton.Visible, `{device}: the action button shown`)
		t.eq(f.ActionArea.StopButton.Visible, false, `{device}: no «СМОТАТЬ» with a fish on the hook`)
		t.ok(f.Minigame.Visible, `{device}: minigame shown`)

		local button = r(f.ActionArea.ActionButton)
		local ribbon = r(f.ActionArea.ActionButton.CaptionRibbon)
		local stop = stops[device]
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
		-- v3: no hotbar — the Backpack CoreGui is off; the centre column keeps 16 px to the bottom.
		t.eq(sim.coreGui[tostring(Enum.CoreGuiType.Backpack)], false, "the Roblox hotbar (Backpack CoreGui) is off")
		for _, name in { "minigame", "alert", "hint", "card" } do
			local rect = all[name]
			t.ok(rect.y + rect.h <= vp.Y - BOTTOM_GAP, `{device}: {name} {fmt(rect)} ≥ 16 px above the bottom`)
		end
		if device == "phone" then
			-- v3 (UIM-01): the minigame docks left of the fisher (here, without a camera on him,
			-- where he stands at the default camera: the middle of the screen).
			t.ok(mini.x + mini.w <= vp.X / 2 - 50, `{device}: the minigame {fmt(mini)} docks left of the fisher`)
			t.ok(mini.x >= 16, `{device}: … 16 px from the screen edge`)
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
			-- UI v2: the hint, the bite alert and the minigame share the column's bottom line and
			-- never show together (see "hint: hidden while the bite and the minigame are up").
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
		t.ok(stop.h >= 44, `{device}: «СМОТАТЬ» is a full tap target ({fmt(stop)})`)
		if touch then
			t.ok(
				button.y - (stop.y + stop.h) >= 22,
				`{device}: «СМОТАТЬ» {fmt(stop)} ≥ 22 px above the action circle`
			)
		end
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
			-- v3 (UIM-04): docked beside the fisher (here where he stands at the default camera:
			-- the middle of the screen), so smaller than the old centred one, still readable.
			t.ok(card.w > card.h * 1.4, `{device}: a landscape card {fmt(card)}`)
			t.ok(card.h >= 165, `{device}: big enough on the phone {fmt(card)}`)
			t.ok(card.x + card.w <= vp.X / 2 - 50 or card.x >= vp.X / 2 + 50, `{device}: beside the fisher {fmt(card)}`)
			local fish = rectOf(sim, p, f.CatchCard.Viewport)
			t.ok(fish.h >= 120, `{device}: a big fish {fmt(fish)}`)
			-- The dim: one side band on the card's side that melts towards the fisher.
			local fades = 0
			for _, side in { "Left", "Right" } do
				local fade = f.CatchDim[side]:FindFirstChild("Fade")
				if fade and fade.Enabled then
					fades += 1
				end
			end
			t.eq(fades, 1, `{device}: one side band of the dim fades towards the fisher`)
		else
			t.near(card.w / card.h, 380 / 384, 0.05, `{device}: the square card {fmt(card)}`)
		end
		t.ok(card.x + card.w * 1.04 <= button.x, `{device}: clear of the action button {fmt(card)} / {fmt(button)}`)
		t.ok(card.y + card.h <= vp.Y - BOTTOM_GAP, `{device}: ≥ 16 px above the bottom {fmt(card)}`)
		t.ok(card.y >= INSET, `{device}: below the top bar {fmt(card)}`)
		if device ~= "desktop" then
			local small = math.min(vp.X, vp.Y) <= 500
			local stick: Rect = if small
				then { x = 25, y = vp.Y - 90, w = 70, h = 70 }
				else { x = 60, y = vp.Y - 210, w = 120, h = 120 }
			local grown: Rect = { x = stick.x - 8, y = stick.y - 8, w = stick.w + 16, h = stick.h + 16 }
			t.eq(overlap(card, grown), 0, `{device}: clear of the thumbstick {fmt(card)}`)
		end
		t.ok(hud.Status.BaseBadge.Label.TextTransparency > 0.95, `{device}: the status stack faded under the card`)
	end
	sim:AssertNoErrors({ warnings = true })
end

tests["bite: «СМОТАТЬ» leaves; touch: a tap on «КЛЮЁТ!» hooks; 👆 shows the first two bites"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	ready(sim, p)
	local f = fishing(p)
	local cue = f.ActionArea.ActionButton.TapCue
	local function bite()
		serverSays(sim, p, "Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
		sim:Advance(0.3)
		t.eq(f.ActionArea.StopButton.Visible, true, "«СМОТАТЬ» while waiting")
		serverSays(sim, p, "Bite", { Window = 1.8 })
		sim:Advance(0.3)
	end
	for round = 1, 3 do
		bite()
		t.eq(f.ActionArea.StopButton.Visible, false, `bite {round}: no «СМОТАТЬ»`)
		t.eq(f.BiteAlert.TapPad.Visible, true, `bite {round}: the plate is a tap pad on touch`)
		t.eq(cue.Visible, round <= 2, `bite {round}: 👆 only for the first two bites`)
		sim:Click(p, f.BiteAlert.TapPad)
		sim:Advance(0.05)
		t.eq(#sim:ServerEventsFor(p, "FishingHook"), round, `bite {round}: a tap on the plate hooks`)
		t.eq(cue.Visible, false, "the cue goes with the hook")
		serverSays(sim, p, "Lost", { Reason = "late", Text = "" })
		t.eq(f.BiteAlert.TapPad.Visible, false, "the pad goes with the bite")
		sim:Advance(FishingConfig.CastCooldown + 0.2)
	end
	sim:AssertNoErrors({ warnings = true })
end

tests["predicted hit: forgotten without an answer; taps keep a margin over TapInterval"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	ready(sim, p)
	local mini = fishing(p).Minigame
	-- A slow needle right in the zone, 3 hits needed: every tap is a hit.
	serverSays(sim, p, "Minigame", minigame("Common", { U0 = 0.6, Speed = 0.01, ZoneCenter = 0.62, HitsNeeded = 3 }))
	sim:Advance(0.4)
	pressF(sim, p)
	t.eq(#sim:ServerEventsFor(p, "FishingTap"), 1)
	t.ok(mini:FindFirstChild("FxFloat"), "the hit plays at once")
	-- The server drops this tap silently (no "Zone"): the prediction must not stick.
	sim:Advance(FishingConfig.TapInterval)
	pressF(sim, p)
	t.eq(#sim:ServerEventsFor(p, "FishingTap"), 1, "not sent exactly TapInterval later (jitter margin)")
	sim:Advance(0.05)
	pressF(sim, p)
	t.eq(#sim:ServerEventsFor(p, "FishingTap"), 2, "sent a little later")
	sim:Advance(FishingConfig.MaxLag + 0.3)
	t.eq(mini:FindFirstChild("FxFloat"), nil, "the words have floated away")
	pressF(sim, p)
	t.eq(#sim:ServerEventsFor(p, "FishingTap"), 3)
	t.ok(mini:FindFirstChild("FxFloat"), "with no answer the prediction expires: the next hit plays again")
	sim:AssertNoErrors({ warnings = true })
end

tests["minigame on a phone: beside the own bobber when it would cover it (world FX stay visible)"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	ready(sim, p)
	local f = fishing(p)
	-- What FishingService sets on a cast (it is switched off here): the bobber flies out.
	local base = sim.workspace.Bases:FindFirstChild(`Base_{p:GetAttribute("BaseIndex")}`)
	local spot = base.FishingSpot.Position
	p:SetAttribute("BobberTarget", Vector3.new(spot.X, spot.Y - 4, spot.Z) + base:GetPivot().LookVector * 30)
	p:SetAttribute("CastTime", sim.workspace:GetServerTimeNow())
	p:SetAttribute("FishingState", "Waiting")
	serverSays(sim, p, "Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
	sim:Advance(FishingConfig.CastFlightTime + 0.3)
	local scripts = p:FindFirstChildOfClass("PlayerScripts")
	local fx = sim:Require(sim:Find("Controllers.FishingFxController", scripts), p)
	local bobber = fx.GetBobber(p)
	t.ok(bobber, "the own bobber is on the water")
	-- Look at the bobber from the pier, so it is in the middle of the minigame's spot.
	local camera = sim.workspace.CurrentCamera
	local at = bobber:GetPivot().Position
	sim:Run(function()
		camera.CFrame = CFrame.lookAt(at + Vector3.new(0, 8, 28), at + Vector3.new(0, 3, 0))
	end, p)
	p:SetAttribute("FishingState", "Reeling")
	serverSays(sim, p, "Minigame", minigame("Common", { ZoneCenter = 0.5 }))
	sim:Advance(0.4)
	local mini = f.Minigame
	local point = sim:Run(function()
		return camera:WorldToScreenPoint(bobber:GetPivot().Position)
	end, p)
	local left, right = mini.AbsolutePosition.X, mini.AbsolutePosition.X + mini.AbsoluteSize.X
	t.ok(point.X < left or point.X > right, `the panel ({left}..{right}) is beside the bobber (x {point.X})`)
	t.ok(mini.AbsoluteSize.X >= 280, "still readable")
	local column = f.Hint.Position.X.Offset
	p:SetAttribute("FishingState", "Idle")
	serverSays(sim, p, "Lost", { Reason = "timeout", Text = "" })
	sim:Advance(1)
	t.eq(mini.Position.X.Offset, column, "back to the centre column after the minigame")
	sim:AssertNoErrors({ warnings = true })
end

--------------------------------------------------------------------------------
-- UI v5 [sim-c]: the catch reward — the card's parts, its dock beside the fisher
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

tests["card parts: the catch reward is built from the sim primitives — chunky card, ribbon, trophy stand, round chips, panel-less title"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1)
	local f = fishing(p)
	local card = f.CatchCard
	-- The card: a Cream sim plate with the chunky outline (UIConfig.Sim.Stroke), its light rim.
	checkCandy(t, card, "CatchCard")
	t.eq(card.Lip.UIStroke:GetAttribute("BaseThickness"), UIConfig.Sim.Stroke, "the card has the chunky outline")
	t.ok(card.Face:FindFirstChild("Rim"), "…and the light inner rim")
	t.ok(card.Face.Window:FindFirstChildOfClass("UIStroke"), "the fish window is framed")
	-- The rarity ribbon: a label-radius sim plate overhanging both sides, outlined stars tilted out.
	local banner = card.Banner
	t.eq(banner:GetAttribute("CandyRadius"), UIConfig.Sim.PlateRadius, "the banner is a ribbon")
	t.ok(banner.Size.X.Scale > 1, "…wider than the card")
	t.ok(banner.StarLeft.Rotation < 0 and banner.StarRight.Rotation > 0, "…its stars tilt outwards")
	t.ok(banner.StarLeft:FindFirstChild("Outline"), "…and are outlined")
	t.ok(banner.RarityLabel.Outline:GetAttribute("BaseThickness") >= 4.5, "the rarity word: a display outline")
	-- The podium (SIM-C1-05): a trophy stand — cap, column with a star, base — not an empty bar.
	local stand = card.Pedestal
	checkCandy(t, stand, "Pedestal")
	checkCandy(t, stand.Cap, "Pedestal.Cap")
	checkCandy(t, stand.Base, "Pedestal.Base")
	t.ok(stand.Cap.Face:FindFirstChild("Shadow"), "the fish's shadow on the cap")
	t.eq(stand.Star.Text, "⭐", "a star on the column")
	local starSize = stand.Star:FindFirstChildOfClass("UITextSizeConstraint")
	t.ok(starSize and starSize.MinTextSize >= 12, "…never drawn under 12 px (the smallest card)")
	t.ok(stand.Cap.Size.X.Scale > 1 and stand.Base.Size.X.Scale > 1, "cap and base wider than the column")
	-- The chips: round; the weight a grey chip with Ink text, the price gold with italic digits.
	local weight, price = card.InfoLabel.Weight, card.InfoLabel.Price
	t.eq(weight:GetAttribute("CandyRadius"), 0.5, "a round weight chip")
	t.eq(price:GetAttribute("CandyRadius"), 0.5, "a round price chip")
	t.ok(isCandy(weight, Palette.Slate) and isCandy(price, Palette.Gold), "grey weight, gold price")
	t.eq(price.Label.FontFace.Style, Enum.FontStyle.Italic, "the price in italic digits")
	t.ok(price.Label.Outline:GetAttribute("BaseThickness") >= 4.5, "…with a display outline")
	t.ok(price.Icon:FindFirstChild("Outline"), "an outlined 💰")
	t.eq(price.Multiplier.FontFace.Style, Enum.FontStyle.Italic, "«×N» italic")
	-- The sticker, the name, the hint.
	checkCandy(t, card.NewStamp, "NewStamp")
	t.ok(isCandy(card.NewStamp, Palette.Berry), "«НОВИНКА!» a red sticker")
	t.ok(card.NewStamp.Rotation < 0, "…slapped on at an angle")
	t.eq(card.NameLabel.Outline.Color, UIConfig.Ink, "the name: white → rarity colours with an Ink outline")
	t.eq(card.TapHint.FontFace.Style, Enum.FontStyle.Italic, "the tap hint in italic")
	-- The giant title: panel-less outlined letters with the drop-shadow twin.
	local title = f.TitleSlam
	t.eq(title.BackgroundTransparency, 1, "no panel behind the title")
	t.ok(title.Label.Outline:GetAttribute("BaseThickness") >= 8, "the giant outline")
	t.ok(title:FindFirstChild("LabelShadow"), "…and its drop shadow")
	-- No compat leftovers in the card: every shape is a sim (or glass) surface.
	for _, d in card:GetDescendants() do
		local style = d:GetAttribute("CandyStyle")
		if style ~= nil then
			t.ok(style == "sim" or style == "glass", `{d:GetFullName()}: a sim surface ({style})`)
		end
	end
	sim:AssertNoErrors({ warnings = true })
end

tests["card dock: FishingLayout.cardDock puts the card beside the fisher and his trophy (tablet), nil when no side fits"] = function(
	t
)
	local Layout = loadLayout()
	-- A 1024 x 768 tablet (HUD.Fishing 1024 x 710): the fisher with an Epic trophy over his head
	-- in the middle-left, the action button bottom-right, «ДОМОЙ» above it, the thumbstick
	-- bottom-left — the bands the controller measures (full height, above the button, above
	-- the thumbstick, above «ДОМОЙ»).
	local keepout = Layout.rect(179, 45, 613, 563)
	local function bands(sides: { number }): { any }
		local out = {}
		for _, side in sides do
			table.insert(out, { side = side, top = 24, bottom = 686, left = 196, right = 659 })
			table.insert(out, { side = side, top = 24, bottom = 528, left = 196, right = 894 })
			table.insert(out, { side = side, top = 24, bottom = 476, left = 16, right = 894 })
			table.insert(out, { side = side, top = 24, bottom = 326, left = 16, right = 1008 })
		end
		return out
	end
	local want, least, aspect, span = 380, 274, 380 / 384, 1.08 * 1.025
	local rect, side, edge = Layout.cardDock(keepout, bands({ -1, 1 }), want, least, aspect, span)
	t.ok(rect, "a side band fits the card")
	t.eq(side, 1, "…on the right (the left of him is too narrow above the thumbstick)")
	t.eq(edge, keepout.x1, "…its edge is the fisher's right edge")
	local w, h = rect.x1 - rect.x0, rect.y1 - rect.y0
	t.ok(w >= least, `readable: {math.floor(w)} px wide (≥ {least})`)
	t.near(w / h, aspect, 0.01, "the square card keeps its shape")
	local foot = (w * span - w) / 2 -- the banner overhangs both sides
	t.ok(rect.x0 - foot >= keepout.x1 - 1e-6, "never over the fisher or his trophy (banner included)")
	t.ok(rect.x1 + foot <= 1008 + 1e-6, "inside the screen's 16 px")
	t.ok(rect.y0 >= 24 - 1e-6 and rect.y1 <= 326 + 1e-6, "above «ДОМОЙ», under the top bar")
	-- Mirrored room: the left wins (×1.1) — the fisher between the card and «ЗАБРАТЬ!».
	local wideOpen = { { side = -1, top = 24, bottom = 600, left = 16, right = 1008 } }
	table.insert(wideOpen, { side = 1, top = 24, bottom = 600, left = 16, right = 1008 })
	local _, leftSide = Layout.cardDock(Layout.rect(420, 60, 604, 560), wideOpen, 300, 250, 1, 1.1)
	t.eq(leftSide, -1, "equal room: the card docks on the left")
	-- No side fits at a readable size: nil (the controller then centres it, as before).
	local tight = Layout.rect(150, 40, 870, 600)
	local none = Layout.cardDock(tight, bands({ -1, 1 }), want, least, aspect, span)
	t.eq(none, nil, "a fisher filling the screen: no dock")
	-- A slot exactly as tall as its band: top + h/2 and bottom − h/2 differ by a float's last
	-- bit (these two numbers do) — that must not break math.clamp (it did: the Mythic card on
	-- the tablet threw "max must be greater than or equal to min" and stayed in the middle).
	local top, bottom = 28.15787603227047, 90.9142404671733
	local ok, slot =
		pcall(Layout.dockSide, -1, Layout.rect(600, 0, 700, 400), roblox.Vector2.new(2000, 2000), 10, top, bottom, 1)
	t.ok(ok, `dockSide survives a band-tall slot ({slot})`)
	t.ok(ok and slot and slot.y0 >= top - 1e-6 and slot.y1 <= bottom + 1e-6, "…and keeps it inside the band")
	local fit = pcall(Layout.cardDock, Layout.rect(600, 0, 700, 400), {
		{ side = -1, top = top, bottom = bottom, left = 16, right = 1008 },
	}, 2000, 10, 1, 1)
	t.ok(fit, "cardDock too")
	local band = pcall(Layout.topBand, Layout.rect(0, bottom, 10, 400), 0, 2000, top, 10)
	t.ok(band, "topBand too")
end

tests["title on a PC: beside the fisher and his trophy when the band above is thin — big, clear of him and the chat"] = function(
	t
)
	local sim = boot(t)
	local p = addPlayer(sim, 1) -- desktop 1280 x 720 (the chat window top-left, no touch)
	ready(sim, p)
	p:SetAttribute("FishCaught", 2)
	sim:Advance(0.2)
	local f = fishing(p)
	-- The default follow camera (as in the tablet dock test): over a trophy that big only a thin
	-- band is left (the word there was 34 px tall).
	local base = sim.workspace.Bases:FindFirstChild(`Base_{p:GetAttribute("BaseIndex")}`)
	local look = base:GetPivot().LookVector
	local focus = p.Character.HumanoidRootPart.Position + Vector3.new(0, 1.5, 0)
	local eye = focus - look * (12.5 * math.cos(math.rad(18))) + Vector3.new(0, 12.5 * math.sin(math.rad(18)), 0)
	sim:Run(function()
		sim.workspace.CurrentCamera.CFrame = CFrame.lookAt(eye, focus)
	end, p)
	catch(sim, p, { Id = "Swordfish", Rarity = "Epic", Kg = 58.2, Value = 161, Income = 14 }, 3)
	local title = f.TitleSlam
	t.ok(
		waitFor(sim, function()
			return title.Visible
		end, CARD_OPENS),
		"the giant title slams in"
	)
	sim:Advance(0.45) -- (the slam has settled)
	local box = rectOf(sim, p, title)
	t.ok(box.h >= 60, `big letters beside him {fmt(box)} (over the trophy they were 34 px)`)
	local scripts = p:FindFirstChildOfClass("PlayerScripts")
	local Layout = sim:Require(sim:Find("Controllers.FishingLayout", scripts), p)
	local origin = f.AbsolutePosition
	local fisher = sim:Run(function()
		return Layout.fisherBox(p.Character, sim.workspace.CurrentCamera, origin)
	end, p)
	t.ok(fisher ~= nil, "the own fisher is on screen")
	if fisher then
		local him: Rect = {
			x = fisher.x0 + origin.X,
			y = fisher.y0 + origin.Y,
			w = fisher.x1 - fisher.x0,
			h = fisher.y1 - fisher.y0,
		}
		t.eq(overlap(box, him), 0, `the title {fmt(box)} is beside the fisher {fmt(him)}, not on him`)
	end
	-- Roblox's chat window (top-left, 8..368 x, INSET + 4..INSET + 184 y): 16 px from it.
	local chat: Rect = { x = 8 - 16, y = INSET + 4 - 16, w = 360 + 32, h = 180 + 32 }
	t.eq(overlap(box, chat), 0, `16 px from the chat window {fmt(box)}`)
	t.ok(box.y >= INSET + 16 - 1, `16 px under the top bar {fmt(box)}`)
	sim:AssertNoErrors({ warnings = true })
end

tests["card spare slot: FishingLayout.leastCover puts a card where it hides the least of a giant trophy (small phone)"] = function(
	t
)
	local Layout = loadLayout()
	-- A 667 x 375 phone (HUD.Fishing 667 x 317): a Mythic trophy over the fisher fills the middle
	-- (x 148..398); left of it the band over the thumbstick, right of it the band over the action
	-- button up to «ДОМОЙ» — neither fits a 128 px landscape card beside him (213 px with the
	-- banner), so the old fallback centred it right over the fish.
	local keepout = Layout.rect(148, 0, 398, 290)
	local bands = {
		{ side = -1, top = 26, bottom = 200, left = 20, right = 600 },
		{ side = 1, top = 26, bottom = 166, left = 20, right = 584 },
	}
	local w, h, span = 128 * 1.55, 128, 1.05 * 1.025
	local rect, side, cover = Layout.leastCover(keepout, bands, w, h, span)
	t.ok(rect, "a spare slot")
	t.near(rect.x1 - rect.x0, w, 0.01, "the card keeps its size")
	t.near(rect.y1 - rect.y0, h, 0.01)
	local foot = (w * span - w) / 2
	local centred = Layout.overlapArea(Layout.rect(333.5 - w * span / 2, 26, 333.5 + w * span / 2, 26 + h), keepout)
	t.ok(cover < centred * 0.5, `it hides far less of him ({math.floor(cover)} vs {math.floor(centred)} px²)`)
	t.eq(cover, Layout.overlapArea(Layout.rect(rect.x0 - foot, rect.y0, rect.x1 + foot, rect.y1), keepout))
	t.eq(side, 1, "…right of his middle: there a band reaches past his edge farther")
	local inside = false
	for _, band in bands do
		inside = inside
			or (
				rect.x0 - foot >= band.left - 1e-6
				and rect.x1 + foot <= band.right + 1e-6
				and rect.y0 >= band.top - 1e-6
				and rect.y1 <= band.bottom + 1e-6
			)
	end
	t.ok(inside, "inside one of the bands")
	-- A band too small for the card: nil.
	local none =
		Layout.leastCover(keepout, { { side = 1, top = 26, bottom = 100, left = 400, right = 584 } }, w, h, span)
	t.eq(none, nil, "no band holds it")
	-- Room beside him after all: no overlap at all.
	local _, _, free =
		Layout.leastCover(keepout, { { side = 1, top = 26, bottom = 300, left = 400, right = 660 } }, w, h, span)
	t.eq(free, 0, "a free band: nothing hidden")
end

tests["card helpers: rays clear the trophy, the stamp and the close hint fit a small landscape card"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	local scripts = p:FindFirstChildOfClass("PlayerScripts")
	local CatchFx = sim:Require(sim:Find("Controllers.CatchFx", scripts), p)
	local trophy = { x0 = 150, y0 = 50, x1 = 390, y1 = 200 }
	t.eq(CatchFx.clearRadius(trophy, roblox.Vector2.new(270, 140)), 120, "the farthest edge of the fish by the axes")
	t.eq(CatchFx.clearRadius(nil, roblox.Vector2.new(0, 0)), nil, "no trophy: the default hole")
	t.eq(CatchFx.stampText("Радужная", 5, false), "РАДУЖНАЯ ×5!", "the square card: name and ×N")
	t.eq(
		CatchFx.stampText("Радужная", 5, true),
		"РАДУЖНАЯ!",
		"the landscape card: the name (×N is on the price chip)"
	)
	t.eq(
		CatchFx.stampText("Радужная", 5, false, 300),
		"РАДУЖНАЯ!",
		"a smaller square card (docked) too"
	)
	t.eq(CatchFx.stampText("Золотая", 2, false, 380), "ЗОЛОТАЯ ×2!", "the full square card keeps ×N")
	t.eq(CatchFx.tapHint(true, nil), "Тапни — забрать!")
	t.eq(CatchFx.tapHint(false, nil), "Жми — забрать!")
	t.eq(CatchFx.tapHint(true, 300), "Тапни — забрать!", "a roomy landscape card: the full hint")
	t.eq(CatchFx.tapHint(true, 198), "Тапни!", "a narrow one: short (the long one would wrap under 13 px)")
	sim:AssertNoErrors({ warnings = true })
end

tests["card dock on a tablet: the square card stands beside the projected fisher and trophy, never on them; its rays big, clipped at him"] = function(
	t
)
	for _, fish in { CATCHES.Legendary, CATCHES.Mythic } do
		local what = fish.Rarity
		local sim = boot(t)
		local p = addPlayer(sim, 1, "tablet")
		ready(sim, p)
		p:SetAttribute("FishCaught", 2)
		sim:Advance(0.2)
		local f = fishing(p)
		-- The default follow camera behind the fisher (12.5 studs back, 18° down; RbxSim has no
		-- camera scripts): the controller projects him and his trophy from it.
		local base = sim.workspace.Bases:FindFirstChild(`Base_{p:GetAttribute("BaseIndex")}`)
		local look = base:GetPivot().LookVector
		local focus = p.Character.HumanoidRootPart.Position + Vector3.new(0, 1.5, 0)
		local eye = focus - look * (12.5 * math.cos(math.rad(18))) + Vector3.new(0, 12.5 * math.sin(math.rad(18)), 0)
		local camera = sim.workspace.CurrentCamera
		sim:Run(function()
			camera.CFrame = CFrame.lookAt(eye, focus)
		end, p)
		catch(sim, p, fish, 3)
		t.ok(openCard(sim, p), `{what}: the card opens`)
		sim:Advance(0.8)
		local scripts = p:FindFirstChildOfClass("PlayerScripts")
		local Layout = sim:Require(sim:Find("Controllers.FishingLayout", scripts), p)
		local origin = f.AbsolutePosition
		local fisher = sim:Run(function()
			return Layout.fisherBox(p.Character, sim.workspace.CurrentCamera, origin)
		end, p)
		local card = rectOf(sim, p, f.CatchCard)
		local vp = sim.players.state[sim:Unwrap(p)].viewport
		t.near(card.w / card.h, 380 / 384, 0.05, `{what}: still the square card {fmt(card)}`)
		t.ok(fisher ~= nil, `{what}: the own fisher is on screen (the tablet has no fallback box)`)
		local layer = f.CatchRays
		if fisher then
			local box: Rect = {
				x = fisher.x0 + origin.X,
				y = fisher.y0 + origin.Y,
				w = fisher.x1 - fisher.x0,
				h = fisher.y1 - fisher.y0,
			}
			t.eq(overlap(card, box), 0, `{what}: the card {fmt(card)} is beside the fisher {fmt(box)}`)
			local fades = 0
			for _, side in { "Left", "Right" } do
				local fade = f.CatchDim[side]:FindFirstChild("Fade")
				if fade and fade.Enabled then
					fades += 1
				end
			end
			t.eq(fades, 1, `{what}: the dim: one side band that melts towards him (he stays bright)`)
			-- SIMC-C1-01: the sunburst behind a docked card is not shortened to the card any more —
			-- its layer clips it at the fisher's edge on the card's side (he and his trophy stay
			-- clear), so the rays stay big around the card.
			t.ok(layer.ClipsDescendants, `{what}: the rays' layer clips them`)
			local clip = rectOf(sim, p, layer)
			-- (≤ 1.5 px: his box now and at the card's birth differ by a fraction of a pixel)
			t.ok(
				overlap(clip, box) <= 1.5 * math.max(box.w, box.h),
				`{what}: the rays' window {fmt(clip)} stops at him {fmt(box)}`
			)
			t.ok(overlap(clip, card) >= card.w * card.h * 0.99, `{what}: …and holds the card {fmt(card)}`)
		end
		local longest, rings = 0, 0
		for _, holder in layer:GetChildren() do
			if holder.Name == "FxRays" then
				rings += 1
				for _, ray in holder:GetChildren() do
					if string.sub(ray.Name, 1, 3) == "Ray" then
						longest = math.max(longest, ray.Size.Y.Scale * holder.Size.Y.Offset)
					end
				end
			end
		end
		t.eq(rings, 2, `{what}: two rings of rays`)
		t.ok(longest >= 0.6 * card.h, `{what}: long rays ({math.floor(longest)} px for a {card.h} px card)`)
		t.ok(card.y + card.h <= vp.Y - BOTTOM_GAP, `{what}: ≥ 16 px above the bottom {fmt(card)}`)
		t.ok(card.y >= INSET, `{what}: below the top bar {fmt(card)}`)
		-- SIMC-C1-05: the chips' labels start right of their icons.
		for _, name in { "Weight", "Price" } do
			local chip = f.CatchCard.InfoLabel[name]
			local icon, label = rectOf(sim, p, chip.Icon), rectOf(sim, p, chip.Label)
			t.ok(
				label.x >= icon.x + icon.w + 2,
				`{what}: {name}: the label {fmt(label)} starts right of its icon {fmt(icon)}`
			)
		end
		sim:AssertNoErrors({ warnings = true })
	end
end

tests["card juice helpers: the spare slot shrinks to stay off the trophy; sticker, chips, rays and «+N 💰» keep clear"] = function(
	t
)
	-- SIMC-C1-02: a 667 x 375 phone, a giant Mythic trophy (x 148..396): the 128 px landscape
	-- card overlaps it on either side; a 0.9 one fits right of it, between it and «ДОМОЙ».
	local Layout = loadLayout()
	local keepout = Layout.rect(148, 30, 396, 300)
	local bands = {
		{ side = -1, top = 30, bottom = 197, left = 20, right = 584 },
		{ side = 1, top = 30, bottom = 160, left = 20, right = 584 },
	}
	local aspect, span = 1.54, 1.05 * 1.025
	local scales = { 1, 0.95, 0.9, 0.85 }
	local tolerance = 0.03 * (396 - 148) * (300 - 30)
	local _, _, full = Layout.leastCover(keepout, bands, 128 * aspect, 128, span)
	local rect, side, cover, scale = Layout.leastCoverScaled(keepout, bands, 128 * aspect, 128, span, scales, tolerance)
	t.ok(full > tolerance, `the full card hides {math.floor(full)} px² of him`)
	t.ok(rect and cover <= tolerance, `a smaller one stays off him ({cover} px² at {scale})`)
	t.ok(scale < 1 and scale >= 0.85, `…not smaller than 0.85 ({scale})`)
	t.eq(side, 1, "…right of him")
	t.near((rect.y1 - rect.y0) / 128, scale, 1e-6, "the card keeps its proportions at that scale")
	local none, _, least = Layout.leastCoverScaled(keepout, bands, 128 * aspect, 128, span, { 1 }, 0)
	t.ok(none and least == full, "no scale fits: the one that hides the least")

	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	local f = fishing(p)
	local scripts = p:FindFirstChildOfClass("PlayerScripts")
	local CatchFx = sim:Require(sim:Find("Controllers.CatchFx", scripts), p)
	local V2 = roblox.Vector2.new
	-- The rays behind a card: at least RAYS_MIN card heights across (the scene of the title keeps
	-- its own size).
	t.eq(CatchFx.raysSize(2.55, 251, 470, false), 470, "capped by MaxPx")
	t.eq(CatchFx.raysSize(2.55, 390, 600, false), CatchFx.RAYS_MIN * 390, "never under RAYS_MIN card heights")
	t.eq(CatchFx.raysSize(2.55, 390, 600, true), 600, "the title's spokes: MaxPx")
	-- The rays' layer: on the card's side of the fisher with his trophy (beside him, or under him
	-- for a spare slot below the giant trophy), or the whole screen.
	local keepout = { x0 = 300, y0 = 50, x1 = 500, y1 = 300 }
	local root = V2(844, 332)
	local left = CatchFx.raysClip(keepout, V2(150, 150), V2(200, 200), root)
	t.eq(left.x1, 300, "a card left of him: the rays end at his left edge")
	t.ok(left.y0 < -332 and left.y1 > 664, "…all the way up and down")
	local right = CatchFx.raysClip(keepout, V2(650, 150), V2(200, 200), root)
	t.eq(right.x0, 500, "right of him: they start at his right edge")
	local under = CatchFx.raysClip(keepout, V2(390, 380), V2(200, 150), root)
	t.eq(under.y0, 300, "a spare slot under the trophy: they start below him")
	local layer = f.CatchRays
	CatchFx.raysFrame(layer, root, left)
	t.ok(layer.ClipsDescendants, "a docked card: clipped")
	t.eq(layer.Position.X.Offset + layer.Size.X.Offset, 300, "…up to his edge")
	t.ok(layer.Position.X.Offset <= -844, "…from beyond the screen")
	CatchFx.raysFrame(layer, root, nil)
	t.eq(layer.ClipsDescendants, false, "no dock: not clipped")
	t.ok(layer.Position.X.Offset <= -844 and layer.Size.X.Offset >= 3 * 844, "…three screens wide")

	-- «НОВИНКА!» on a small docked card: inside at rest, its slap from ≤ SLAP_DOCKED, anchored
	-- where it has room (the scaled sticker stays on the card, under the banner).
	local stamp = f.CatchCard.NewStamp
	stamp.AnchorPoint = roblox.Vector2.new(0.5, 0.5)
	stamp.Position = roblox.UDim2.fromOffset(28, 41)
	local area = { x0 = 0, y0 = 28, x1 = 197, y1 = 129 }
	local peak = CatchFx.fitStamp(stamp, V2(-20, 27), V2(96, 28), area)
	t.ok(peak <= CatchFx.SLAP_DOCKED and peak >= 1, `a modest slap ({peak})`)
	t.near(stamp.Position.X.Offset - stamp.AnchorPoint.X * 96, 0, 0.5, "moved inside the card at rest")
	t.near(stamp.Position.Y.Offset - stamp.AnchorPoint.Y * 28, 27, 0.5, "…not up or down")
	local a = stamp.AnchorPoint
	local x0 = stamp.Position.X.Offset - a.X * 96 * peak
	local y0 = stamp.Position.Y.Offset - a.Y * 28 * peak
	t.ok(x0 >= area.x0 - 0.5 and x0 + 96 * peak <= area.x1 + 0.5, `its slap stays on the card ({x0})`)
	t.ok(y0 >= area.y0 - 1.5, `…and off the banner ({y0})`)

	-- A narrow chip: the icon shrinks a little and the label starts right of it.
	local chip = f.CatchCard.InfoLabel.Price
	CatchFx.fitChip(chip, V2(93, 29))
	local iconRight = chip.Icon.Position.X.Scale * 93 + (1 - chip.Icon.AnchorPoint.X) * chip.Icon.Size.X.Scale * 29
	local labelLeft = chip.Label.Position.X.Scale * 93 - chip.Label.AnchorPoint.X * chip.Label.Size.X.Scale * 93
	t.ok(labelLeft >= iconRight + 2.9, `the price starts right of 💰 ({labelLeft} / {iconRight})`)
	t.ok(chip.Label.UITextSizeConstraint.MinTextSize <= math.floor(0.8 * 0.8 * 29), "its text may fit the small chip")
	CatchFx.fitChip(chip, V2(300, 29))
	t.eq(chip.Icon.Size, chip.Icon:GetAttribute("RestSize"), "a wide chip: the builder's icon")
	t.eq(chip.Label.Size, chip.Label:GetAttribute("RestSize"), "…and label")

	-- «+N 💰» beside a docked card: above the banner when there is room, else at the outer
	-- edge, else under the card, else the window's top strip (fading early) — never on the fish
	-- in the window.
	local function spot(cardTop: number, outer: number, tall: number?): any
		local h = tall or 300
		local c, size, early = CatchFx.floatSpot({
			root = V2(1024, 710),
			card = { x0 = 600, y0 = cardTop, x1 = 900, y1 = cardTop + h },
			side = 1,
			edge = 580,
			window = { x0 = 630, y0 = cardTop + 60, x1 = 870, y1 = cardTop + 160 },
			source = V2(800, cardTop + h - 70),
			perHeight = 5.4,
			want = 80,
			least = 36,
			gap = 10,
			limits = function()
				return 16, outer
			end,
		})
		return { c = c, h = size, early = early }
	end
	local above = spot(200, 1008)
	t.ok(above.c.Y + above.h / 2 <= 190 + 1e-6 and not above.early, "room above: over the banner")
	t.ok(above.c.X - above.h * 5.4 / 2 >= 590 - 1e-6, "…not over the fisher")
	local beside = spot(30, 1300)
	t.ok(beside.c.X - beside.h * 5.4 / 2 >= 910 - 1e-6 and not beside.early, "no room above: at the outer edge")
	local under = spot(30, 1008)
	t.ok(under.c.Y - under.h / 2 >= 340 - 1e-6 and not under.early, "…else under the card")
	t.ok(under.c.X - under.h * 5.4 / 2 >= 590 - 1e-6, "…not over the fisher")
	local strip = spot(30, 950, 660)
	t.ok(strip.early, "no room at all: the window's top strip, fading early")
	t.ok(strip.c.Y + strip.h / 2 <= 30 + 60 + 0.5 * 100, "…in its top half")
	t.ok(strip.h <= 30 + 1e-6, "…at most 0.3 of the window tall")
	t.ok(strip.c.X + strip.h * 5.4 / 2 <= 870 + 1e-6, "…inside the window, by its right end")
	sim:AssertNoErrors({ warnings = true })
end

return tests
