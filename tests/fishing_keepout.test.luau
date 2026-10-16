--[[
	The fishing widgets and their big words keep clear of the own fisher, the Roblox thumbstick and
	the base badge's flag (FishingController + FishingLayout; rules: tools/builder/gui/STYLE.md)
	in RbxSim against the built Place1.rbxl, with the default follow camera behind the fisher (the
	controller projects him from it — FishingLayout.fisherBox):
	  • the minigame on a tablet and a PC docks beside the fisher instead of covering his legs at
	    the bottom of the screen (UX-01); its rarity word lies beside him too, and its slam from big
	    grows away from him (ART-03);
	  • «ПОЙМАНА!» rests off the thumbstick (≥ 16 px) and off the fisher, and its slam from 2.4
	    grows from the edge away from them (UX-02, UX-03);
	  • on a phone the words over the docked minigame («ЛЕГЕНДАРНАЯ!», «ИДЕАЛЬНО!», «МИМО!») stay off
	    the base badge and the flag hanging over its left end (ART-04): they rise less, and stay
	    over their panel.
	The server's FishingService is switched off (like tests/fishing_ui_style.test.luau): the harness
	plays the server and fires FishingState itself.

	Run: lune run tools/run_tests.luau fishing_keepout
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Enum = roblox.Enum
local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local function loadConfig(name: string): any
	local path = `src/ReplicatedStorage/Shared/Config/{name}.luau`
	local chunk = luau.load(fs.readFile(path), {
		debugName = path,
		environment = { Color3 = roblox.Color3, Vector3 = roblox.Vector3, Enum = roblox.Enum },
		injectGlobals = true,
	})
	return chunk()
end

local FishingConfig = loadConfig("FishingConfig")

local COMMON = { Id = "Crucian", Rarity = "Common", Kg = 0.84, Value = 11, Income = 1.1 }

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

local function addPlayer(sim: any, id: number, device: string): any
	local p = sim:AddPlayer({ UserId = id, Name = `Keep{id}`, device = device })
	sim:Advance(1)
	return p
end

-- Rod in hand at the own fishing spot.
local function ready(sim: any, p: any)
	local template = sim:Find("ReplicatedStorage.Assets.Rods.RodBamboo")
	local rod = template:Clone()
	rod.Name = template:GetAttribute("DisplayName")
	rod.Parent = p:FindFirstChildOfClass("Backpack")
	p:SetAttribute("RodId", "RodBamboo")
	p:SetAttribute("FishingState", "Idle")
	p:SetAttribute("FishCaught", 0)
	sim:Advance(0.05)
	local base = sim.workspace.Bases:FindFirstChild(`Base_{p:GetAttribute("BaseIndex")}`)
	sim:Teleport(p, base.FishingSpot.CFrame.Position + Vector3.new(0, 3, 0))
	sim:Advance(0.3)
	sim:EquipTool(p, rod)
	sim:Advance(0.3)
end

-- The default follow camera behind the fisher (12.5 studs back, 18° down; RbxSim has no camera
-- scripts): the controller projects him from it.
local function followCamera(sim: any, p: any)
	local base = sim.workspace.Bases:FindFirstChild(`Base_{p:GetAttribute("BaseIndex")}`)
	local look = base:GetPivot().LookVector
	local focus = p.Character.HumanoidRootPart.Position + Vector3.new(0, 1.5, 0)
	local eye = focus - look * (12.5 * math.cos(math.rad(18))) + Vector3.new(0, 12.5 * math.sin(math.rad(18)), 0)
	local camera = sim.workspace.CurrentCamera
	sim:Run(function()
		camera.CFrame = CFrame.lookAt(eye, focus)
	end, p)
end

local function serverSays(sim: any, p: any, state: string, data: any?)
	sim:Find("ReplicatedStorage.Remotes.FishingState"):FireClient(p, state, data)
	sim:Advance(0.05)
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

type Rect = { x0: number, y0: number, x1: number, y1: number }

-- A GUI object's box on screen (px), at rest: from its Position, Size and AnchorPoint in its
-- parent's box (RbxSim's AbsoluteSize of a scaled-text label is not its Size; UIScale ignored).
local function boxOf(gui: any): Rect
	local parent = gui.Parent
	local at, room = parent.AbsolutePosition, parent.AbsoluteSize
	local pos, size = gui.Position, gui.Size
	local w = size.X.Scale * room.X + size.X.Offset
	local h = size.Y.Scale * room.Y + size.Y.Offset
	local x = at.X + pos.X.Scale * room.X + pos.X.Offset - gui.AnchorPoint.X * w
	local y = at.Y + pos.Y.Scale * room.Y + pos.Y.Offset - gui.AnchorPoint.Y * h
	return { x0 = x, y0 = y, x1 = x + w, y1 = y + h }
end

-- What the controller sees of a plate (its AbsolutePosition / AbsoluteSize).
local function seenOf(gui: any): Rect
	local at, size = gui.AbsolutePosition, gui.AbsoluteSize
	return { x0 = at.X, y0 = at.Y, x1 = at.X + size.X, y1 = at.Y + size.Y }
end

-- The same box grown by its UIScale about its AnchorPoint (what Roblox draws).
local function drawnOf(gui: any): Rect
	local box = boxOf(gui)
	local scale = gui:FindFirstChildOfClass("UIScale")
	local k = if scale then scale.Scale else 1
	local w, h = box.x1 - box.x0, box.y1 - box.y0
	local px, py = box.x0 + gui.AnchorPoint.X * w, box.y0 + gui.AnchorPoint.Y * h
	return {
		x0 = px - gui.AnchorPoint.X * w * k,
		y0 = py - gui.AnchorPoint.Y * h * k,
		x1 = px + (1 - gui.AnchorPoint.X) * w * k,
		y1 = py + (1 - gui.AnchorPoint.Y) * h * k,
	}
end

local function grow(r: Rect, pad: number): Rect
	return { x0 = r.x0 - pad, y0 = r.y0 - pad, x1 = r.x1 + pad, y1 = r.y1 + pad }
end

local function hits(a: Rect, b: Rect): boolean
	return a.x0 < b.x1 and b.x0 < a.x1 and a.y0 < b.y1 and b.y0 < a.y1
end

local function fmt(r: Rect): string
	return string.format("(%d,%d..%d,%d)", r.x0, r.y0, r.x1, r.y1)
end

-- The own fisher on screen (px), as the controller sees him (FishingLayout.fisherBox, with its pad).
local function fisherOf(sim: any, p: any): Rect?
	local f = p.PlayerGui.HUD.Fishing
	local scripts = p:FindFirstChildOfClass("PlayerScripts")
	local Layout = sim:Require(sim:Find("Controllers.FishingLayout", scripts), p)
	local origin = f.AbsolutePosition
	local box = sim:Run(function()
		return Layout.fisherBox(p.Character, sim.workspace.CurrentCamera, origin)
	end, p)
	if not box then
		return nil
	end
	return { x0 = box.x0 + origin.X, y0 = box.y0 + origin.Y, x1 = box.x1 + origin.X, y1 = box.y1 + origin.Y }
end

-- The Roblox thumbstick on a touch screen (the Jump button's mirror; px).
local function thumbstickOf(sim: any, p: any): Rect
	local vp = sim.players.state[sim:Unwrap(p)].viewport
	local small = math.min(vp.X, vp.Y) <= 500
	return if small
		then { x0 = 25, y0 = vp.Y - 90, x1 = 95, y1 = vp.Y - 20 }
		else { x0 = 60, y0 = vp.Y - 210, x1 = 180, y1 = vp.Y - 90 }
end

local function floatNamed(root: any, text: string): any
	for _, item in root:GetDescendants() do
		if item.Name == "FxFloat" and item.Text == text then
			return item
		end
	end
	return nil
end

local tests = {}

tests["minigame on a tablet and a PC: beside the projected fisher, never on his legs; its rarity word beside him too"] = function(
	t
)
	for _, device in { "tablet", "desktop" } do
		local sim = boot(t)
		local p = addPlayer(sim, 1, device)
		ready(sim, p)
		followCamera(sim, p)
		local f = p.PlayerGui.HUD.Fishing
		local vp = sim.players.state[sim:Unwrap(p)].viewport
		p:SetAttribute("FishingState", "Reeling")
		serverSays(sim, p, "Minigame", minigame("Mythic"))
		local fisher = fisherOf(sim, p)
		t.ok(fisher ~= nil, `{device}: the own fisher is on screen`)
		-- The «МИФИЧЕСКАЯ!» word slams in from big at once: even its first frame grows away from him.
		local word = floatNamed(f, "МИФИЧЕСКАЯ!")
		t.ok(word ~= nil, `{device}: the rarity word`)
		if fisher and word then
			local drawn = drawnOf(word)
			t.ok(
				(word:FindFirstChildOfClass("UIScale") :: any).Scale > 1.3,
				`{device}: (the word is still big: {(word:FindFirstChildOfClass("UIScale") :: any).Scale})`
			)
			t.ok(not hits(drawn, fisher), `{device}: the slamming word {fmt(drawn)} is off the fisher {fmt(fisher)}`)
		end
		sim:Advance(0.4)
		local mini = seenOf(f.Minigame)
		if fisher then
			t.ok(not hits(mini, fisher), `{device}: the minigame {fmt(mini)} is beside the fisher {fmt(fisher)}`)
		end
		if fisher and word and word.Parent then
			local rest = boxOf(word)
			t.ok(not hits(rest, fisher), `{device}: the rarity word {fmt(rest)} rests off the fisher {fmt(fisher)}`)
		end
		t.ok(mini.y1 <= vp.Y - 16, `{device}: ≥ 16 px above the bottom {fmt(mini)}`)
		t.ok(mini.x0 >= 0 and mini.x1 <= vp.X, `{device}: inside the screen {fmt(mini)}`)
		t.ok(mini.y1 - mini.y0 >= 90 and mini.x1 - mini.x0 >= 208, `{device}: still readable {fmt(mini)}`)
		if device == "tablet" then
			local stick = grow(thumbstickOf(sim, p), 16)
			t.ok(not hits(mini, stick), `{device}: ≥ 16 px from the thumbstick {fmt(mini)}`)
		end
		-- The minigame ends: the panel is back in the centre column at its builder size.
		p:SetAttribute("FishingState", "Idle")
		serverSays(sim, p, "Lost", { Reason = "timeout", Text = "" })
		sim:Advance(1)
		t.eq(f.Minigame.Visible, false)
		t.eq(f.Minigame.Size.X.Scale > 0 or f.Minigame.Size.X.Offset > 0, true)
		sim:AssertNoErrors({ warnings = true })
	end
end

tests["«ПОЙМАНА!»: off the thumbstick and the fisher; its slam from big grows away from them"] = function(t)
	for _, device in { "tablet", "phone" } do
		local sim = boot(t)
		local p = addPlayer(sim, 1, device)
		ready(sim, p)
		followCamera(sim, p)
		p:SetAttribute("FishingState", "Reeling")
		serverSays(sim, p, "Minigame", minigame("Common", { U0 = 0.6, Speed = 0.05, ZoneCenter = 0.62 }))
		sim:Advance(0.4)
		sim:PressKey(p, Enum.KeyCode.F)
		sim:Advance(0.2)
		p:SetAttribute("FishCaught", 1)
		serverSays(sim, p, "Caught", { Fish = COMMON, Total = 1 })
		local word = floatNamed(p.PlayerGui.HUD, "ПОЙМАНА!")
		t.ok(word ~= nil, `{device}: «ПОЙМАНА!»`)
		local fisher = fisherOf(sim, p)
		t.ok(fisher ~= nil, `{device}: the own fisher is on screen`)
		local stick = grow(thumbstickOf(sim, p), 16)
		if word then
			local scale = word:FindFirstChildOfClass("UIScale")
			t.ok(scale and scale.Scale > 1.3, `{device}: slammed in from big ({scale and scale.Scale})`)
			local drawn = drawnOf(word)
			t.ok(not hits(drawn, stick), `{device}: the slam {fmt(drawn)} stays off the thumbstick {fmt(stick)}`)
			if fisher then
				t.ok(not hits(drawn, fisher), `{device}: the slam {fmt(drawn)} stays off the fisher {fmt(fisher)}`)
			end
			sim:Advance(0.3)
			local rest = boxOf(word)
			t.ok(not hits(rest, stick), `{device}: at rest {fmt(rest)} ≥ 16 px from the thumbstick`)
			if fisher then
				t.ok(not hits(rest, fisher), `{device}: at rest {fmt(rest)} off the fisher {fmt(fisher)}`)
			end
			t.ok(rest.y1 - rest.y0 >= 40, `{device}: still the loudest word ({rest.y1 - rest.y0} px)`)
		end
		sim:AssertNoErrors({ warnings = true })
	end
end

tests["phone: the words over the docked minigame stay off the base badge and its flag"] = function(t)
	local sim = boot(t)
	local p = addPlayer(sim, 1, "phone")
	ready(sim, p)
	local hud = p.PlayerGui.HUD
	local f = hud.Fishing
	local badge = hud.Status.BaseBadge
	t.ok(badge.Visible and badge.FlagSocket.Visible, "the base badge with its flag")
	local blocks = { seenOf(badge), seenOf(badge.FlagSocket) }
	-- A word's box while it lives: it rises (rise of its host) and its tilt lifts one end.
	local function swept(word: any, up: number): Rect
		local box = boxOf(word)
		local lift = math.sin(math.rad(math.abs(word.Rotation))) * (box.x1 - box.x0) / 2
		return { x0 = box.x0, y0 = box.y0 - up - lift, x1 = box.x1, y1 = box.y1 }
	end
	p:SetAttribute("FishingState", "Reeling")
	serverSays(sim, p, "Minigame", minigame("Legendary"))
	local word = floatNamed(f, "ЛЕГЕНДАРНАЯ!") -- (just born: it has not risen yet)
	t.ok(word ~= nil, "«ЛЕГЕНДАРНАЯ!» over the panel")
	if word then
		local box = swept(word, 0.01 * f.AbsoluteSize.Y)
		for i, block in blocks do
			t.ok(
				not hits(box, block),
				`the rarity word {fmt(box)} stays off {if i == 1 then "the badge" else "the flag"} {fmt(block)}`
			)
		end
	end
	-- «ИДЕАЛЬНО!» (the zone centre: a perfect hit) rises from the panel's top edge, but only as far
	-- as the badge lets it — it stays over its panel, never pushed across the screen.
	p:SetAttribute("FishingState", "Idle")
	serverSays(sim, p, "Lost", { Reason = "timeout", Text = "" })
	sim:Advance(1.5)
	p:SetAttribute("FishingState", "Reeling")
	serverSays(sim, p, "Minigame", minigame("Epic", { U0 = 0.5, Speed = 0.05, ZoneCenter = 0.5, HitsNeeded = 3 }))
	sim:Advance(0.3)
	sim:PressKey(p, Enum.KeyCode.F)
	sim:Advance(0.02)
	local perfect = floatNamed(f.Minigame, "ИДЕАЛЬНО!")
	t.ok(perfect ~= nil, "«ИДЕАЛЬНО!»")
	if perfect then
		local panel = seenOf(f.Minigame)
		local born = boxOf(perfect)
		local middle = (born.x0 + born.x1) / 2
		t.ok(
			middle > panel.x0 and middle < panel.x1,
			`«ИДЕАЛЬНО!» {fmt(born)} stays over its panel {fmt(panel)}`
		)
		sim:Advance(0.75) -- (nearly the end of its rise)
		if perfect.Parent then
			local risen = boxOf(perfect)
			local lift = math.sin(math.rad(math.abs(perfect.Rotation))) * (risen.x1 - risen.x0) / 2
			risen.y0 -= lift
			for i, block in blocks do
				t.ok(
					not hits(risen, block),
					`«ИДЕАЛЬНО!» {fmt(risen)} rises no higher than {if i == 1 then "the badge" else "the flag"} {fmt(
						block
					)}`
				)
			end
		end
	end
	-- A miss: the ghost's «МИМО!» rises over the panel's top edge, right under the badge.
	p:SetAttribute("FishingState", "Idle")
	serverSays(sim, p, "Lost", { Reason = "miss", Text = "" })
	local ghost = f:FindFirstChild("FxMinigameMiss")
	t.ok(ghost ~= nil, "the miss ghost")
	local miss = ghost and floatNamed(ghost, "МИМО!")
	t.ok(miss ~= nil, "«МИМО!»")
	if miss then
		local box = swept(miss, 0.2 * ghost.AbsoluteSize.Y)
		for i, block in blocks do
			t.ok(
				not hits(box, grow(block, 4)),
				`«МИМО!» {fmt(box)} stays off {if i == 1 then "the badge" else "the flag"} {fmt(block)}`
			)
		end
	end
	sim:Advance(1)
	sim:AssertNoErrors({ warnings = true })
end

return tests
