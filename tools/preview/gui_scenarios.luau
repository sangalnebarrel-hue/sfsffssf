--[[
	gui_scenarios.luau — the standard set of HUD states for the GUI preview renderer
	(tools/preview/gui_dump.luau → gui_render.py, see tools/preview/README.md "GUI previews").

	Every scenario drives the REAL client (HudController, NotifyController, FishingController
	from Place1.rbxl) of a fresh player in RbxSim. The server's FishingService is switched off
	(its module source becomes "return {}", like tests/stage2_client.test.luau does), so the
	harness plays the server: it hands out the rod and fires FishingState / Notify itself.
	The rest of the server (BaseService: base assignment, Home teleport) is real.

	Scenarios find widgets by NAME only (HUD.Fishing.ActionArea.ActionButton, ...), never by
	look, so they keep working when the HUD is restyled.

	A scenario:
	  name    unique id (file names: <out>/<device>/<name>.png)
	  desc    one line for listings and contact-sheet titles
	  run     function(h) — sets the state up; time 0 of the scenario is the moment it returns
	          (usually right after the event of interest: the bite, the catch, the toast...)
	  still   seconds after time 0 for the still image(s): a number or a list (default 0.6)
	  sheet   optional animation contact sheet: { from, to, fps, roi = { paths... }, margin }
	          frames every 1/fps s from `from` to `to`; each frame is cropped to the union
	          of the screen boxes of the `roi` objects over all frames (+ margin, a fraction
	          of the screen height; default 0.04); roi = nil or {} → the whole screen
	  standard  false = not part of `--all` (still available by name)
	  fresh   true = `run` starts right after the player joins; otherwise only once the
	          base is assigned, the character exists and `settle` more seconds have passed
	  settle  seconds to wait after the base assignment (default 4.2: the welcome toast
	          «Твоя база — …» is gone); 0.5 keeps it on screen

	The harness `h` (built by gui_dump.luau):
	  h.sim, h.player, h.device ("phone" | "tablet" | "desktop"), h.touch (bool)
	  h:advance(seconds, step?)        virtual time, 60 fps (or `step`-second frames)
	  h:gui(path) -> Instance?         under the player's PlayerGui ("HUD.Fishing.Hint")
	  h:visible(path) -> bool          the object and every GuiObject ancestor are Visible
	  h:waitFor(fn, timeout?) -> any   steps until fn() is truthy (or the timeout)
	  h:waitVisible(path, timeout?)    steps until h:visible(path)
	  h:click(path, down?)             taps a GuiButton (down = only MouseButton1Down)
	  h:press()                        the PC action key (F)
	  h:serverSays(state, data?)       FishingState to this client (FishingService protocol)
	  h:notify(text, kind)             Notify toast to this client ("info"|"success"|"warning"|"danger")
	  h:giveRod() -> Tool              the start rod into the Backpack (+ attributes)
	  h:equipRod() -> Tool             give + equip
	  h:standAtSpot() / h:standFar()   onto the own FishingSpot / 40 studs inland of it
	  h:config(name) -> table          ReplicatedStorage.Shared.Config.<name>
	  h:minigame(rarity, extra?)       "Minigame" with the rarity's rule from FishingConfig
	  h:caught(fish, total?)           "Caught" { Fish = fish, Total = total }
]]

local roblox = require("@lune/roblox")

local Vector3 = roblox.Vector3

local CATCHES = {
	Common = { Id = "Crucian", Rarity = "Common", Kg = 0.84, Value = 11, Income = 1.1 },
	Rare = { Id = "Puffer", Rarity = "Rare", Kg = 2.1, Value = 58, Income = 5.2 },
	Epic = { Id = "Swordfish", Rarity = "Epic", Kg = 63.5, Value = 182, Income = 15.6 },
	Legendary = { Id = "SharkPup", Rarity = "Legendary", Kg = 27.3, Value = 590, Income = 52 },
	Mythic = { Id = "DragonFish", Rarity = "Mythic", Kg = 14.2, Value = 2400, Income = 200 },
}

local function withMutation(fish: { [string]: any }, mutation: string, multiplier: number): { [string]: any }
	local copy = table.clone(fish)
	copy.Mutation = mutation
	copy.Value = math.round(fish.Value * multiplier)
	copy.Income = fish.Income * multiplier
	return copy
end

-- Rod in hand at the own fishing spot, line in the water.
local function readyAtSpot(h: any)
	h:standAtSpot()
	h:equipRod()
	h:advance(0.3)
end

local function toMinigame(h: any, rarity: string, extra: { [string]: any }?)
	readyAtSpot(h)
	h:serverSays("Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
	h:advance(0.4)
	h:serverSays("Bite", { Window = 1.8 })
	h:advance(0.2)
	h:click("HUD.Fishing.ActionArea.ActionButton")
	h:advance(0.1)
	h:minigame(rarity, extra)
end

-- The catch card of `fish`: time 0 = the moment the card is on screen.
local function catchScenario(h: any, fish: { [string]: any })
	toMinigame(h, fish.Rarity)
	h:advance(0.6)
	h:click("HUD.Fishing.ActionArea.ActionButton", true)
	h:advance(0.05)
	h.player:SetAttribute("FishCaught", 1)
	h:caught(fish, 1)
	h:waitVisible("HUD.Fishing.CatchCard", 3)
end

local CARD_ROI = { "HUD.Fishing.CatchCard" }
local FISHING_ROI = { "HUD.Fishing.Minigame", "HUD.Fishing.BiteAlert", "HUD.Fishing.ActionArea" }
local HIT_ROI = { "HUD.Fishing.Minigame", "HUD.Fishing.ActionArea" }

--[[
	selftest: a synthetic ScreenGui with one cell per renderer feature (strokes, corners, gradient
	types, rotation, UIScale, clipping, CanvasGroup, text fitting and strokes, emoji, layouts),
	so the renderer's Roblox rules can be checked by eye. Not part of the standard set.
]]
local function buildSelfTest(h: any)
	local UDim2, UDim, Color3, Vector2 = roblox.UDim2, roblox.UDim, roblox.Color3, roblox.Vector2
	local Enum = roblox.Enum
	local font = roblox.Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold)
	local sim = h.sim
	local playerGui = h.player:FindFirstChildOfClass("PlayerGui")
	local hud = playerGui:FindFirstChild("HUD")
	if hud then
		hud.Enabled = false
	end
	local function new(class: string, props: { [string]: any }, parent: any): any
		local inst = sim:Create(class, {}, nil)
		for key, value in props do
			local ok, err = pcall(function()
				inst[key] = value
			end)
			if not ok then
				h:warn(`selftest: {class}.{key}: {err}`)
			end
		end
		inst.Parent = parent
		return inst
	end
	local function seq(...: Color3): any
		local colors = { ... }
		local kps = {}
		for i, c in colors do
			table.insert(kps, roblox.ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
		end
		return roblox.ColorSequence.new(kps)
	end
	local rainbow = seq(
		Color3.fromRGB(255, 70, 70),
		Color3.fromRGB(255, 190, 40),
		Color3.fromRGB(90, 230, 90),
		Color3.fromRGB(60, 200, 255),
		Color3.fromRGB(150, 90, 255),
		Color3.fromRGB(255, 80, 200)
	)
	local white, ink = Color3.new(1, 1, 1), Color3.fromRGB(20, 26, 46)

	local root = new("ScreenGui", { Name = "SelfTest", IgnoreGuiInset = true, DisplayOrder = 50 }, playerGui)
	new("Frame", {
		Name = "Backdrop",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(46, 54, 84),
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}, root)
	local n = 0
	local function cell(caption: string): any
		n += 1
		local col, row = (n - 1) % 6, (n - 1) // 6
		local frame = new("Frame", {
			Name = `Cell{n}`,
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(col / 6, 0.02 + row * 0.196),
			Size = UDim2.fromScale(1 / 6, 0.196),
		}, root)
		new("TextLabel", {
			Name = "Caption",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.03, 0.8),
			Size = UDim2.fromScale(0.94, 0.18),
			Text = `{n}. {caption}`,
			TextScaled = true,
			FontFace = font,
			TextColor3 = Color3.fromRGB(220, 226, 240),
		}, frame)
		return new("Frame", {
			Name = "Area",
			BackgroundTransparency = 1,
			Position = UDim2.fromScale(0.1, 0.08),
			Size = UDim2.fromScale(0.8, 0.68),
		}, frame)
	end
	local function box(parent: any, props: { [string]: any }?): any
		local p = {
			Name = "Box",
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.8, 0.7),
			BackgroundColor3 = white,
			BorderSizePixel = 0,
		}
		for key, value in props or {} do
			p[key] = value
		end
		return new("Frame", p, parent)
	end
	local function corner(parent: any, scale: number, offset: number?)
		new("UICorner", { CornerRadius = UDim.new(scale, offset or 0) }, parent)
	end
	local function stroke(parent: any, thickness: number, props: { [string]: any }?): any
		local p = { Color = ink, Thickness = thickness, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }
		for key, value in props or {} do
			p[key] = value
		end
		return new("UIStroke", p, parent)
	end
	local function text(parent: any, s: string, props: { [string]: any }?): any
		local p = {
			Name = "Text",
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = s,
			TextScaled = true,
			FontFace = font,
			TextColor3 = white,
		}
		for key, value in props or {} do
			p[key] = value
		end
		return new("TextLabel", p, parent)
	end

	-- Row 1: borders, strokes, corners.
	box(cell("legacy border 3 px"), { BorderSizePixel = 3, BorderColor3 = Color3.fromRGB(230, 60, 60) })
	local b = box(cell("pill + stroke 4 Outer"))
	corner(b, 0.5)
	stroke(b, 4)
	b = box(cell("stroke 4 Center"))
	corner(b, 0.5)
	stroke(b, 4, { BorderStrokePosition = Enum.BorderStrokePosition.Center })
	b = box(cell("stroke 4 Inner"))
	corner(b, 0.5)
	stroke(b, 4, { BorderStrokePosition = Enum.BorderStrokePosition.Inner })
	b = box(cell("per-corner radii 24/0/12/0"))
	new("UICorner", {
		TopLeftRadius = UDim.new(0, 24),
		TopRightRadius = UDim.new(0, 0),
		BottomRightRadius = UDim.new(0, 12),
		BottomLeftRadius = UDim.new(0, 0),
	}, b)
	stroke(b, 2)
	b = box(cell("circle, rainbow stroke 6"), { BackgroundColor3 = Color3.fromRGB(255, 210, 63) })
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, b)
	corner(b, 0.5)
	new("UIGradient", { Color = rainbow }, stroke(b, 6, { Color = white }))

	-- Row 2: gradients.
	b = box(cell("linear 0°"))
	new("UIGradient", { Color = seq(white, Color3.fromRGB(31, 123, 240)) }, b)
	b = box(cell("linear 90° candy"))
	corner(b, 0.3)
	stroke(b, 3)
	new("UIGradient", { Color = seq(Color3.fromRGB(95, 216, 255), Color3.fromRGB(31, 123, 240)), Rotation = 90 }, b)
	b = box(cell("linear 45°, offset .25"))
	new("UIGradient", { Color = rainbow, Rotation = 45, Offset = Vector2.new(0.25, 0) }, b)
	b = box(cell("transparency 0→1"), { BackgroundColor3 = Color3.fromRGB(224, 48, 74) })
	new("UIGradient", { Transparency = roblox.NumberSequence.new(0, 1) }, b)
	b = box(cell("Radial"), { BackgroundColor3 = Color3.fromRGB(255, 240, 122) })
	corner(b, 0.2)
	new("UIGradient", {
		Type = Enum.GradientType.Radial,
		Color = seq(white, Color3.fromRGB(255, 165, 31)),
	}, b)
	b = box(cell("Conical rainbow"))
	new("UIAspectRatioConstraint", { AspectRatio = 1 }, b)
	corner(b, 0.5)
	new("UIGradient", { Type = Enum.GradientType.Conical, Color = rainbow }, b)

	-- Row 3: transforms, clipping, groups.
	b = box(cell("Rotation 20° + child"), { Rotation = 20, BackgroundColor3 = Color3.fromRGB(139, 242, 106) })
	corner(b, 0.25)
	stroke(b, 3)
	text(b, "ЖМИ!", { Size = UDim2.fromScale(1, 0.5), TextColor3 = ink })
	b = box(cell("UIScale 1.4, anchor .5"), { Size = UDim2.fromScale(0.5, 0.5) })
	corner(b, 0.3)
	stroke(b, 3)
	new("UIScale", { Scale = 1.4 }, b)
	text(b, "1.4", { TextColor3 = ink })
	b = box(cell("UIScale 0.5 → child 2"), { BackgroundColor3 = Color3.fromRGB(214, 155, 255) })
	new("UIScale", { Scale = 0.5 }, b)
	local inner = box(b, { Size = UDim2.fromScale(0.3, 0.3), BackgroundColor3 = white })
	new("UIScale", { Scale = 2 }, inner)
	stroke(inner, 2)
	b = box(cell("ClipsDescendants"), { ClipsDescendants = true, BackgroundColor3 = Color3.fromRGB(95, 216, 255) })
	box(b, { Size = UDim2.fromScale(0.6, 1.6), Position = UDim2.fromScale(0.8, 0.5), BackgroundColor3 = ink })
	b = box(cell("clip ignored (rotated)"), {
		ClipsDescendants = true,
		Rotation = 10,
		BackgroundColor3 = Color3.fromRGB(95, 216, 255),
	})
	box(b, { Size = UDim2.fromScale(0.6, 1.6), Position = UDim2.fromScale(0.8, 0.5), BackgroundColor3 = ink })
	b = new("CanvasGroup", {
		Name = "Group",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.8, 0.7),
		BackgroundColor3 = Color3.fromRGB(224, 48, 74),
		GroupTransparency = 0.5,
	}, cell("CanvasGroup 0.5"))
	box(b, { Size = UDim2.fromScale(0.5, 0.5) })

	-- Row 4: text.
	text(cell("TextScaled, wide box"), "ДОМОЙ")
	local narrow = text(cell("TextScaled narrow, min 9"), "ДОМОЙ", { Size = UDim2.fromScale(0.3, 1) })
	new("UITextSizeConstraint", { MinTextSize = 9, MaxTextSize = 40 }, narrow)
	text(cell("TextScaled wraps"), "Встань в сверкающий круг на своём пирсе")
	text(cell("18 px, Left/Top, wrapped"), "Удочка — в рюкзаке внизу экрана", {
		TextScaled = false,
		TextSize = 18,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		BackgroundTransparency = 0.6,
		BackgroundColor3 = ink,
	})
	local title =
		text(cell("UIStroke 3 + TextStroke"), "КЛЮЁТ!", { TextStrokeTransparency = 0, TextStrokeColor3 = ink })
	new("UIStroke", { Thickness = 3, Color = ink }, title)
	text(cell("emoji + text"), "🎣 Улов: 12 💰", { TextColor3 = Color3.fromRGB(255, 240, 122) })

	-- Row 5: gradient text, graphemes, layouts, images.
	local gold = text(cell("text gradient"), "ЛЕГЕНДА!")
	new("UIGradient", { Color = seq(white, Color3.fromRGB(255, 165, 31)), Rotation = 90 }, gold)
	new("UIStroke", { Thickness = 2, Color = ink }, gold)
	text(cell("MaxVisibleGraphemes 5"), "ЗАБРОСИТЬ", { MaxVisibleGraphemes = 5 })
	local row = cell("UIListLayout H, centred")
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0.04, 0),
	}, row)
	for i = 1, 3 do
		local sq = new("Frame", {
			Name = `Item{i}`,
			LayoutOrder = i,
			Size = UDim2.fromScale(0.2, 0.5),
			BackgroundColor3 = Color3.fromRGB(255, 122, 138),
			BorderSizePixel = 0,
		}, row)
		corner(sq, 0.3)
	end
	local grid = cell("UIGridLayout 3x2")
	new("UIGridLayout", {
		CellSize = UDim2.fromScale(0.3, 0.45),
		CellPadding = UDim2.fromScale(0.05, 0.1),
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, grid)
	for i = 1, 6 do
		local c = new("Frame", {
			Name = `G{i}`,
			LayoutOrder = i,
			BackgroundColor3 = Color3.fromHSV(i / 7, 0.6, 1),
			BorderSizePixel = 0,
		}, grid)
		corner(c, 0.2)
	end
	local col = cell("UIListLayout V, bottom/right")
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Padding = UDim.new(0, 4),
	}, col)
	for i = 1, 2 do
		local bar = new("Frame", {
			Name = `Bar{i}`,
			LayoutOrder = i,
			Size = UDim2.fromScale(0.3 * i, 0.25),
			BackgroundColor3 = Color3.fromRGB(139, 242, 106),
			BorderSizePixel = 0,
		}, col)
		corner(bar, 0.5)
	end
	new("ImageLabel", {
		Name = "Glow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(0.7, 1),
		BackgroundTransparency = 1,
		Image = "rbxasset://textures/particles/sparkles_main.dds",
		ImageColor3 = Color3.fromRGB(255, 210, 63),
	}, cell("ImageLabel (glow stand-in)"))
end

local scenarios = {
	{
		name = "spawn_base",
		desc = "The base arrives: «ТВОЯ БАЗА» banner, then it flies into the badge (lands ≈2.4 s)",
		fresh = true, -- run right after the player joins (no waiting for the base)
		still = { 0.6, 2.25, 2.9 },
		sheet = { from = 0, to = 3.2, fps = 8, roi = { "HUD.Status", "HUD.BaseBanner" }, margin = 0.05 },
		run = function(h: any)
			h:waitFor(function()
				local index = h.player:GetAttribute("BaseIndex")
				return typeof(index) == "number" and index > 0
			end, 5)
		end,
	},
	{
		name = "no_base",
		desc = "All bases taken: the badge waits",
		still = 0.6,
		run = function(h: any)
			h.player:SetAttribute("BaseIndex", 0)
			h.player:SetAttribute("BaseColorName", nil)
			h.player:SetAttribute("BaseColor", nil)
		end,
	},
	{
		name = "start",
		desc = "Just spawned: rod in the backpack, newcomer hint",
		still = 0.8,
		run = function(h: any)
			h:giveRod()
		end,
	},
	{
		name = "rod_far",
		desc = "Rod in hand, far from the fishing spot: «К ПИРСУ» 🧭 + hint + guide beam",
		still = 0.8,
		run = function(h: any)
			h:giveRod()
			h:standFar()
			h:equipRod()
		end,
	},
	{
		name = "spot_take",
		desc = "At the fishing spot, rod still in the backpack: «ВЗЯТЬ»",
		still = 0.8,
		run = function(h: any)
			h:giveRod()
			h:standAtSpot()
			h:advance(0.6)
		end,
	},
	{
		name = "take_rod",
		desc = "Tap «ВЗЯТЬ»: the rod comes into the hand, the button pops into «ЗАБРОСИТЬ»",
		still = 0.6,
		sheet = { from = 0, to = 0.8, fps = 15, roi = { "HUD.Fishing.ActionArea" }, margin = 0.06 },
		run = function(h: any)
			h:giveRod()
			h:standAtSpot()
			h:advance(0.6)
			h:click("HUD.Fishing.ActionArea.ActionButton")
		end,
	},
	{
		name = "spot_ready",
		desc = "At the fishing spot with the rod: ready to cast (idle shine)",
		still = 0.8,
		sheet = { from = 0, to = 4, fps = 6, roi = { "HUD.Fishing.ActionArea" }, margin = 0.04 },
		run = function(h: any)
			readyAtSpot(h)
		end,
	},
	{
		name = "cast",
		desc = "Tap «ЗАБРОСИТЬ»: press squash, then waiting for a bite",
		still = 0.9,
		sheet = { from = 0, to = 1.0, fps = 15, roi = { "HUD.Fishing.ActionArea" }, margin = 0.04 },
		run = function(h: any)
			readyAtSpot(h)
			h:click("HUD.Fishing.ActionArea.ActionButton")
			h:advance(0.1)
			h:serverSays("Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
		end,
	},
	{
		name = "waiting",
		desc = "Line in the water: Water «ЖДЁМ…» with the bobbing bobber, ripples, dots, nibbles; «СМОТАТЬ»",
		still = 1.5,
		sheet = { from = 0, to = 2.4, fps = 10, roi = { "HUD.Fishing.ActionArea" }, margin = 0.06 },
		run = function(h: any)
			readyAtSpot(h)
			h:serverSays("Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
		end,
	},
	{
		name = "bite",
		desc = "A bite: «КЛЮЁТ!» slam, «!» glyphs, Sun edges, one 0.45 s beat; «ПОДСЕЧЬ!»",
		still = 0.35,
		sheet = { from = 0, to = 1.2, fps = 15, roi = FISHING_ROI, margin = 0.04 },
		run = function(h: any)
			readyAtSpot(h)
			h:serverSays("Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
			h:advance(0.5)
			h:serverSays("Bite", { Window = 1.8 })
		end,
	},
	{
		name = "minigame_common",
		desc = "Minigame, Common fish (needle mid-run)",
		still = 0.55,
		run = function(h: any)
			toMinigame(h, "Common", { ZoneCenter = 0.66, U0 = 0.05 })
		end,
	},
	{
		name = "minigame_rare",
		desc = "Minigame, Rare fish (needle mid-run)",
		still = 0.55,
		run = function(h: any)
			toMinigame(h, "Rare", { ZoneCenter = 0.3, U0 = 0.1 })
		end,
	},
	{
		name = "minigame_epic",
		desc = "Minigame, Epic fish, 1 of 2 hits done",
		still = 0.55,
		run = function(h: any)
			toMinigame(h, "Epic", { ZoneCenter = 0.72, U0 = 0.12, Hits = 1 })
		end,
	},
	{
		name = "minigame_legendary",
		desc = "Minigame, Legendary fish (needle sweep)",
		still = 0.55,
		sheet = { from = 0, to = 1.0, fps = 15, roi = { "HUD.Fishing.Minigame" }, margin = 0.04 },
		run = function(h: any)
			toMinigame(h, "Legendary", { ZoneCenter = 0.4, U0 = 0.02 })
		end,
	},
	{
		name = "minigame_mythic",
		desc = "Minigame, Mythic fish, 2 of 3 hits done",
		still = 0.55,
		run = function(h: any)
			toMinigame(h, "Mythic", { ZoneCenter = 0.58, U0 = 0.08, Hits = 2 })
		end,
	},
	{
		name = "hit",
		desc = "A hit in the minigame (off-centre): «ОТЛИЧНО!», sparks, zone jumps, star stamped",
		still = 0.15,
		sheet = { from = 0, to = 0.9, fps = 15, roi = HIT_ROI, margin = 0.14 },
		run = function(h: any)
			-- Epic, needle ≈ 0.52 at the tap, zone 0.5..0.7: inside, but not near the centre.
			toMinigame(h, "Epic", { ZoneCenter = 0.6, U0 = 0.3 })
			h:advance(0.2)
			h:click("HUD.Fishing.ActionArea.ActionButton", true)
			h:advance(0.05)
			h:serverSays("Zone", { ZoneCenter = 0.15, Hits = 1 })
		end,
	},
	{
		name = "hit_perfect",
		desc = "A perfect hit (needle at the zone centre): «ИДЕАЛЬНО!», gold ring, more sparks",
		still = 0.15,
		sheet = { from = 0, to = 0.9, fps = 15, roi = HIT_ROI, margin = 0.14 },
		run = function(h: any)
			toMinigame(h, "Epic", { ZoneCenter = 0.52, U0 = 0.3 })
			h:advance(0.2)
			h:click("HUD.Fishing.ActionArea.ActionButton", true)
			h:advance(0.05)
			h:serverSays("Zone", { ZoneCenter = 0.15, Hits = 1 })
		end,
	},
	{
		name = "hit_super",
		desc = "The second hit of a Mythic fish: «СУПЕР!», the second star",
		still = 0.15,
		run = function(h: any)
			toMinigame(h, "Mythic", { ZoneCenter = 0.75, U0 = 0.3, Hits = 1 })
			h:advance(0.2)
			h:click("HUD.Fishing.ActionArea.ActionButton", true)
			h:advance(0.05)
			h:serverSays("Zone", { ZoneCenter = 0.2, Hits = 2 })
		end,
	},
	{
		name = "miss",
		desc = "A miss: the ghost turns red with «МИМО!» (🐟 swims off), then the hint as it leaves",
		still = { 0.25, 0.9 },
		sheet = {
			from = 0,
			to = 1.2,
			fps = 15,
			roi = { "HUD.Fishing.Minigame", "HUD.Fishing.Hint", "HUD.Fishing.ActionArea" },
			margin = 0.05,
		},
		run = function(h: any)
			toMinigame(h, "Rare", { ZoneCenter = 0.8, U0 = 0.05 })
			h:advance(0.3)
			h:click("HUD.Fishing.ActionArea.ActionButton", true)
			h:advance(0.05)
			h:serverSays("Lost", { Reason = "miss", Text = "Мимо! Рыба сорвалась с крючка" })
		end,
	},
	{
		name = "minigame_timeout",
		desc = "Time is up in the minigame: «ВРЕМЯ!» on the fading ghost",
		still = 0.25,
		run = function(h: any)
			toMinigame(h, "Common", { ZoneCenter = 0.4, U0 = 0.6, Timeout = 1.2 })
			h:advance(1.2)
			h:serverSays("Lost", { Reason = "timeout", Text = "Время вышло — рыба ушла" })
		end,
	},
	{
		name = "lost_late",
		desc = "Too late to hook: hint",
		still = 0.5,
		run = function(h: any)
			readyAtSpot(h)
			h:serverSays("Waiting", { Target = Vector3.new(0, 0, -22), FlightTime = 0.7 })
			h:advance(0.3)
			h:serverSays("Bite", { Window = 1.8 })
			h:advance(1.9)
			h:serverSays("Lost", { Reason = "late", Text = "Слишком поздно — рыба уплыла" })
		end,
	},
	{
		name = "denied_far",
		desc = "Cast refused: too far from the edge of the pier",
		still = 0.5,
		run = function(h: any)
			readyAtSpot(h)
			h:click("HUD.Fishing.ActionArea.ActionButton")
			h:advance(0.1)
			h:serverSays("Denied", { Reason = "far", Text = "Встань в сверкающий круг" })
		end,
	},
	{
		name = "catch_common",
		desc = "Catch card: Common (Карасик)",
		still = 1.0,
		sheet = { from = 0, to = 1.6, fps = 10, roi = CARD_ROI, margin = 0.08 },
		run = function(h: any)
			catchScenario(h, CATCHES.Common)
		end,
	},
	{
		name = "catch_rare",
		desc = "Catch card: Rare (Фугу-пуфик)",
		still = 1.0,
		run = function(h: any)
			catchScenario(h, CATCHES.Rare)
		end,
	},
	{
		name = "catch_epic",
		desc = "Catch card: Epic (Меч-рыба)",
		still = 1.0,
		run = function(h: any)
			catchScenario(h, CATCHES.Epic)
		end,
	},
	{
		name = "catch_legendary",
		desc = "Catch card: Legendary (Акулёнок) — flash, camera shake, two rings of rays",
		still = 1.0,
		sheet = { from = 0, to = 2.4, fps = 10, roi = {}, margin = 0 },
		run = function(h: any)
			catchScenario(h, CATCHES.Legendary)
		end,
	},
	{
		name = "catch_mythic",
		desc = "Catch card: Mythic (Рыба-дракон) — the big reveal",
		still = 1.0,
		sheet = { from = 0, to = 2.4, fps = 10, roi = {}, margin = 0 },
		run = function(h: any)
			catchScenario(h, CATCHES.Mythic)
		end,
	},
	{
		name = "catch_gold",
		desc = "Catch card: Gold mutation (Окунь-полосатик)",
		still = 1.0,
		run = function(h: any)
			local perch = { Id = "Perch", Rarity = "Common", Kg = 1.23, Value = 18, Income = 1.8 }
			catchScenario(h, withMutation(perch, "Gold", 2))
		end,
	},
	{
		name = "catch_neon",
		desc = "Catch card: Neon mutation (Фугу-пуфик)",
		still = 1.0,
		run = function(h: any)
			catchScenario(h, withMutation(CATCHES.Rare, "Neon", 3))
		end,
	},
	{
		name = "catch_rainbow",
		desc = "Catch card: Rainbow mutation (Акулёнок)",
		still = 1.0,
		sheet = { from = 0, to = 1.6, fps = 10, roi = CARD_ROI, margin = 0.08 },
		run = function(h: any)
			catchScenario(h, withMutation(CATCHES.Legendary, "Rainbow", 5))
		end,
	},
	{
		name = "catch_close",
		desc = "Closing the catch card (tap): the card leaves, the counter bumps",
		still = 0.6,
		sheet = { from = 0, to = 1.0, fps = 15, roi = {}, margin = 0 },
		run = function(h: any)
			catchScenario(h, CATCHES.Rare)
			h:advance(0.8)
			h:click("HUD.Fishing.CatchCard")
		end,
	},
	{
		name = "toast_info",
		desc = "Toast: info",
		still = 0.6,
		run = function(h: any)
			h:notify("Сервер перезапустится через минуту", "info")
		end,
	},
	{
		name = "toast_success",
		desc = "Toast: success (slide in)",
		still = 0.6,
		sheet = { from = 0, to = 0.8, fps = 15, roi = { "HUD.Toasts" }, margin = 0.05 },
		run = function(h: any)
			h:notify("Отличный улов!", "success")
		end,
	},
	{
		name = "toast_warning",
		desc = "Toast: warning",
		still = 0.6,
		run = function(h: any)
			h:notify("Сейчас нельзя вернуться домой", "warning")
		end,
	},
	{
		name = "toast_danger",
		desc = "Toast: danger",
		still = 0.6,
		run = function(h: any)
			h:notify("Твою базу грабят!", "danger")
		end,
	},
	{
		name = "toast_stack",
		desc = "Three toasts at once (the cap), then the oldest leaves",
		still = 0.7,
		sheet = { from = 3.0, to = 4.4, fps = 10, roi = { "HUD.Toasts" }, margin = 0.05 },
		run = function(h: any)
			h:notify("Твоя база — Красная!", "success")
			h:advance(0.25)
			h:notify("Сервер перезапустится через минуту", "info")
			h:advance(0.25)
			h:notify("Сейчас нельзя вернуться домой", "warning")
		end,
	},
	{
		name = "home_cooldown",
		desc = "«ДОМОЙ» pressed: the cooldown drains",
		still = 1.5,
		sheet = { from = 0, to = 0.8, fps = 15, roi = { "HUD.RightButtons" }, margin = 0.05 },
		run = function(h: any)
			h:standFar()
			h:click("HUD.RightButtons.HomeButton")
		end,
	},
	--------------------------------------------------------------------------------
	-- UI v2, playing: the far-from-spot tap, the first-timer cue, the «МЕГА!» word, the
	-- rare-catch broadcasts (the server's Notify kinds "Legendary" / "Mythic") and a long toast.
	--------------------------------------------------------------------------------
	{
		name = "far_tap",
		desc = "Tap «К ПИРСУ» far from the spot: no cast — the hint pops again, the guide beam flares",
		still = 0.3,
		sheet = {
			from = 0,
			to = 0.8,
			fps = 15,
			roi = { "HUD.Fishing.ActionArea", "HUD.Fishing.Hint" },
			margin = 0.05,
		},
		run = function(h: any)
			h:giveRod()
			h:standFar()
			h:equipRod()
			h:advance(0.8)
			h:click("HUD.Fishing.ActionArea.ActionButton")
		end,
	},
	{
		name = "minigame_cue",
		desc = "A first-timer's minigame: the needle in the zone, 👆 taps «ЛОВИ!» (first 2 per session)",
		still = 0.55,
		run = function(h: any)
			-- Common: the needle runs 0.05 → 0.49 by 0.55 s, inside the zone 0.35..0.65.
			toMinigame(h, "Common", { ZoneCenter = 0.5, U0 = 0.05 })
		end,
	},
	{
		name = "hit_mega",
		desc = "A third hit before the last one (a 4-hit payload): «МЕГА!» in rainbow",
		still = 0.15,
		run = function(h: any)
			toMinigame(h, "Mythic", { ZoneCenter = 0.75, U0 = 0.3, Hits = 2, HitsNeeded = 4 })
			h:advance(0.2)
			h:click("HUD.Fishing.ActionArea.ActionButton", true)
			h:advance(0.05)
			h:serverSays("Zone", { ZoneCenter = 0.2, Hits = 3 })
		end,
	},
	{
		name = "toast_legendary",
		desc = "Broadcast of someone's Legendary catch: the big Gold toast with 👑",
		still = 0.7,
		sheet = { from = 0, to = 0.9, fps = 15, roi = { "HUD.Toasts" }, margin = 0.05 },
		run = function(h: any)
			h:notify("КапитанКрюк: легендарная «Акулёнок»!", "Legendary")
		end,
	},
	{
		name = "toast_mythic",
		desc = "Broadcast of someone's Mythic catch with a mutation: the rainbow toast with 👑",
		still = 0.7,
		sheet = { from = 0, to = 0.9, fps = 15, roi = { "HUD.Toasts" }, margin = 0.05 },
		run = function(h: any)
			h:notify("КапитанКрюк: мифическая «Рыба-дракон» ×2!", "Mythic")
		end,
	},
	{
		name = "toast_long",
		desc = "A long toast: wraps to two lines, the pill grows taller",
		still = 0.7,
		run = function(h: any)
			h:notify(
				"Сервер перезапустится через минуту — успей поймать ещё одну рыбу!",
				"info"
			)
		end,
	},
	{
		name = "selftest",
		desc = "Renderer self-test: one cell per supported GUI feature",
		standard = false,
		settle = 0.2,
		still = 0.1,
		run = buildSelfTest,
	},
}

return scenarios
