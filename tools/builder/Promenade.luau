--[[
	Promenade — the 4 bridges (hub plaza ↔ promenade) and the promenade ring along the lagoon
	(World v3, tools/builder/DESIGN.md §2/§6).

	  Map.Bridges     Bridge_1..4 at θ = BridgeAngles: chunky Props.bridge from the hub plaza
	                  (r ≈ 118) to the promenade (r ≈ 312), deck top GroundTop + 0.6, no end
	                  arches (the hub's avenue gates and the gateway arches frame the crossing);
	                  planks in two woods with every fourth one in the gateway's pastel, white
	                  posts and kerbs, a chunky top rail in the gateway's colour (pastel mid rail
	                  and pile caps; dark wood only on the piles under the deck), lanterns in the
	                  gateway's colour, a landing plate where the deck meets the promenade and a
	                  mid-span lookout: bump-outs on both sides with a lamp and a flag each,
	                  bunting across the deck between the flags; on the left (deeper) one a sell
	                  kiosk «ПРОДАТЬ РЫБУ» (SellKiosk.Scales.SellPromptAttachment, bound by the
	                  server like the hub market's), on the right a bench facing the water and a
	                  telescope. Pile bents buried in the sand at the two ends are left out.
	                  buildBridges returns the kiosks' attachments for the build's self-check.
	  Map.Promenade   the ring walk r 312..330 on flat GroundTop: warm sand paving with darker
	                  joint strips, a smooth coral middle band and white kerbs (open where the
	                  gateway roads and landmark paths leave the ring); a sea wall on the lagoon
	                  side (light stone face from the beach up, white coping) with a low white
	                  railing and a blue rail on it, open at the 8 pier entrances (base ± 6°, with
	                  two broad sand steps down to the beach on both sides of the pier) and 4
	                  sand steps down to the beach (between two plots); chunky lamps (caps in the
	                  colour of the nearest gateway: each quarter of the ring has its own),
	                  bunting, benches and planters in front of the plots and along the stretches
	                  between them, big billboards at the landmark paths.

	Nothing is placed on the walking surface except along its two edges, so players can run
	all the way round. Returns { lamps = number }.
]]

local U = require("./Util")
local Kit = require("./MapKit")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local rgb = U.rgb
local C = Kit.C

local rad, cos, tan, floor = math.rad, math.cos, math.tan, math.floor

local Promenade = {}

-- Gateway themes by bridge angle (shared with Gateways.luau): name, colour (and the bridge's
-- accent plank when the pastel would read as water: white on the blue bridge).
-- `accent`: the lookout's theme accent (wingAccent), matching the gateway district behind.
Promenade.Themes = {
	[0] = { gate = "ЮЖНЫЕ ВОРОТА", bridge = "ЮЖНЫЙ МОСТ", color = C.Orange, accent = "balloons" },
	[90] = {
		gate = "ВОСТОЧНЫЕ ВОРОТА",
		bridge = "ВОСТОЧНЫЙ МОСТ",
		color = C.Pink,
		accent = "flowers",
	},
	[180] = {
		gate = "СЕВЕРНЫЕ ВОРОТА",
		bridge = "СЕВЕРНЫЙ МОСТ",
		color = C.Blue,
		plank = C.White,
		accent = "anchor",
	},
	[270] = {
		gate = "ЗАПАДНЫЕ ВОРОТА",
		bridge = "ЗАПАДНЫЙ МОСТ",
		color = rgb(64, 196, 92),
		accent = "picnic",
	},
}

-- Landmark path mouths on the promenade's land side: a big billboard beside each path, on the
-- `side` (+1: towards larger angles) that stays clear (the waterfall's stepping stones round
-- the pond start on its + side).
local PATH_SIGNS = {
	{ angle = 45, text = "ВОДОПАД →", color = rgb(40, 170, 230), side = -1 },
	{ angle = 135, text = "МЕЛЬНИЦА →", color = rgb(240, 76, 64) },
	{ angle = 225, text = "БОЛЬШОЕ ДЕРЕВО →", color = rgb(64, 180, 80) },
	{ angle = 315, text = "ВЕРШИНА →", color = rgb(110, 110, 230) },
}

-- Flat pieces on the ground cast no shadows (cheaper on phones, nothing visible is lost).
local FLAT = { CastShadow = false }

local DECK_TOP = 0.64 -- above GroundTop: a hair above the bridge and pier decks (0.6)

--------------------------------------------------------------------------------------------
-- Bridges
--------------------------------------------------------------------------------------------

-- Half length (studs, along the bridge) of the mid-span lookout and how far it sticks out (the
-- left wing, with the sell kiosk, sticks out further).
local LOOKOUT_HALF = 10
local LOOKOUT_OUT = 6.5
local KIOSK_OUT = 9

-- Path of the sell kiosk's scales under a bridge model, and its prompt attachment's offset in
-- the Scales part (like the hub's FishMarket.Scales: in front of the counter, over the deck).
local KIOSK_PROMPT_OFFSET = Vector3.new(0, -0.7, -2.3)
local SKIN = rgb(255, 206, 160)
local ICE = rgb(222, 246, 255)

--[[
	Sell kiosk «ПРОДАТЬ РЫБУ» on a lookout wing (24 parts), standing on `cf` (y = 0 the wing's
	deck top, front -Z towards the bridge deck, local X along the bridge): a white counter with a
	panel in the gateway's colour and an ice top with two fish, red scales (Scales part with the
	SellPromptAttachment the server binds, like the hub market's), a fishmonger in an apron and
	a bucket hat behind it, four posts under a striped awning with a white valance and a yellow
	board on top. Everything stays within 3 studs in front of / 4.2 behind cf and ±7 along X.
	Returns the Scales part.
]]
local function sellKiosk(parent: any, cf: any, theme: any, k: number): any
	local b = Kit.builder(parent, "SellKiosk", cf)
	local color = theme.color
	local shirts = { C.Cyan, C.Blue, C.Red, C.Orange }
	-- counter: white body, a panel in the gateway's colour (the sign) and an ice top with fish
	local counter = b:box("Counter", -5.5, -0.05, -2.8, 5.5, 3.2, -1.4, C.White)
	local panel = b:box("Panel", -5.0, 0.5, -2.95, 5.0, 2.7, -2.75, color, Kit.NOSHADOW)
	Kit.sign(panel, U.Enum.NormalId.Front, "ПРОДАТЬ РЫБУ", C.White, C.Navy, { pps = 24 })
	b:box("Ice", -5.8, 3.2, -3.1, 5.8, 3.7, -1.2, ICE)
	b:box("FishA", -4.7, 3.7, -2.55, -2.3, 4.3, -1.75, C.Orange, Kit.DECOR)
	b:box("FishATail", -2.35, 3.75, -2.45, -1.75, 4.25, -1.85, C.Yellow, Kit.DECOR)
	b:box("FishB", 2.3, 3.7, -2.65, 4.7, 4.3, -1.85, C.Pink, Kit.DECOR)
	b:box("FishBTail", 1.75, 3.75, -2.55, 2.35, 4.25, -1.95, C.Purple, Kit.DECOR)
	-- the scales in the middle of the counter (low: the fishmonger's face shows above them)
	local scales = b:box("Scales", -1.1, 3.7, -2.6, 1.1, 4.5, -1.6, C.Red)
	b:box("ScalesDial", -0.7, 4.5, -2.35, 0.7, 5.6, -1.85, C.White)
	b:box("ScalesPan", -1.4, 5.6, -2.75, 1.4, 5.85, -1.45, C.Yellow, Kit.NOSHADOW)
	U.new("Attachment", { Name = "SellPromptAttachment", CFrame = CFrame.new(KIOSK_PROMPT_OFFSET) }, scales)
	-- the fishmonger
	b:box("Body", -1.0, -0.05, -0.6, 1.0, 4.9, 0.8, shirts[(k - 1) % #shirts + 1])
	b:box("Apron", -0.8, 2.2, -0.75, 0.8, 4.6, -0.5, C.White, Kit.NOSHADOW)
	b:box("Head", -0.85, 4.9, -0.65, 0.85, 6.5, 0.95, SKIN)
	b:box("EyeL", -0.55, 5.7, -0.75, -0.25, 6.05, -0.6, C.Dark, Kit.DECOR)
	b:box("EyeR", 0.25, 5.7, -0.75, 0.55, 6.05, -0.6, C.Dark, Kit.DECOR)
	b:box("Hat", -1.1, 6.4, -0.9, 1.1, 7.1, 1.2, C.Yellow, Kit.NOSHADOW)
	-- four posts under a striped awning, a valance along its front and a board on top
	for i, p in { { -6.3, -2.6 }, { 5.7, -2.6 }, { -6.3, 3.4 }, { 5.7, 3.4 } } do
		b:box(`Post{i}`, p[1], -0.05, p[2], p[1] + 0.6, 7.6, p[2] + 0.6, C.White)
	end
	b:box("Awning", -7, 7.6, -3.9, 7, 8.4, 4.4, color)
	b:box("AwningStripeA", -4.4, 8.35, -3.75, -2.2, 8.7, 4.25, C.White, Kit.NOSHADOW)
	b:box("AwningStripeB", 2.2, 8.35, -3.75, 4.4, 8.7, 4.25, C.White, Kit.NOSHADOW)
	b:box("Valance", -7.15, 6.9, -4.1, 7.15, 7.65, -3.75, C.White, Kit.NOSHADOW)
	local board = b:box("Board", -4.2, 8.3, 0.0, 4.2, 11.3, 0.6, C.Yellow)
	Kit.sign(board, U.Enum.NormalId.Front, "РЫБА", C.Navy, nil, { pps = 24 })
	Kit.sign(board, U.Enum.NormalId.Back, "РЫБА", C.Navy, nil, { pps = 24 })
	b:finish(counter)
	return scales
end

--[[
	The right wing's accent in the theme of the gateway district behind the bridge, so the four
	crossings tell themselves apart (4-10 parts; lookout builder frame, the bench at x = bx,
	seat z -3..3, its back on the deck side, the outer rail at ox): balloons tied to the bench
	(playground), a flower box on the outer rail and a planter by the bench (garden), an anchor
	leaning on the rail and a lifebuoy hung on it (fish market), a picnic basket on a checked
	cloth on the bench (picnic).
]]
local function wingAccent(b: any, theme: any, bx: number, ox: number)
	local kind = theme.accent
	if kind == "balloons" then
		-- three balloons tied along the outer rail
		for i, p in { { -6.2, 8.4, C.Red }, { -4.2, 9.3, C.Yellow }, { -2.2, 8.7, C.Blue } } do
			local z, y = p[1], p[2]
			b:box(`String{i}`, ox - 0.07, 4.3, z - 0.07, ox + 0.07, y + 0.1, z + 0.07, C.White, Kit.DECOR)
			b:box(`Balloon{i}`, ox - 0.8, y, z - 0.8, ox + 0.8, y + 1.9, z + 0.8, p[3], Kit.DECOR)
		end
	elseif kind == "flowers" then
		-- a flower box along the top of the outer rail, a planter at the bench's end
		b:box("RailBox", ox - 0.65, 4.35, -6.5, ox + 0.65, 5.2, 4.5, theme.color)
		b:box("RailGreens", ox - 0.45, 5.1, -6.2, ox + 0.45, 5.9, 4.2, C.Leaf2, Kit.DECOR)
		b:box("RailBloomsA", ox - 0.55, 5.6, -5.8, ox + 0.55, 6.6, -1.2, C.Yellow, Kit.DECOR)
		b:box("RailBloomsB", ox - 0.58, 5.7, -0.4, ox + 0.58, 6.5, 3.8, C.Purple, Kit.DECOR)
		b:box("Planter", bx - 1.3, -0.05, -6.6, bx + 1.3, 1.5, -4.0, C.White)
		b:box("PlanterGreens", bx - 1.0, 1.4, -6.3, bx + 1.0, 2.6, -4.3, C.Leaf2, Kit.DECOR)
		b:box("PlanterBloom", bx - 0.7, 2.4, -5.9, bx + 0.6, 3.5, -4.7, C.Red, Kit.DECOR)
	elseif kind == "anchor" then
		-- an anchor leaning on the outer rail (shank, stock, arms, flukes, ring) and a lifebuoy
		local x, z = ox - 1.3, -5.2
		b:box("AnchorShank", x - 0.35, -0.05, z - 0.35, x + 0.35, 5.6, z + 0.35, C.Navy)
		b:box("AnchorStock", x - 0.25, 4.5, z - 1.7, x + 0.25, 5.0, z + 1.7, C.Navy, Kit.NOSHADOW)
		b:box("AnchorArms", x - 0.45, 0.4, z - 2.0, x + 0.45, 1.1, z + 2.0, C.Navy, Kit.NOSHADOW)
		b:box("AnchorFlukeA", x - 0.55, 1.0, z - 2.1, x + 0.55, 2.1, z - 1.3, C.Navy, Kit.NOSHADOW)
		b:box("AnchorFlukeB", x - 0.55, 1.0, z + 1.3, x + 0.55, 2.1, z + 2.1, C.Navy, Kit.NOSHADOW)
		b:box("AnchorRing", x - 0.2, 5.55, z - 0.6, x + 0.2, 6.6, z + 0.6, C.Gold, Kit.NOSHADOW)
		-- (the lifebuoy hangs on the hub-side end rail, facing along the wing)
		local endZ = -(LOOKOUT_HALF - 0.75) + 0.75 + 0.4
		Kit.prop("lifebuoy", b.model, b.cf * CFrame.new(ox - 3.4, 2.6, endZ), {})
	elseif kind == "picnic" then
		-- a red cloth with a white check on the bench and a basket on it
		b:box("Cloth", bx - 0.95, 2.05, -2.9, bx + 1.05, 2.2, -0.2, C.Red, Kit.DECOR)
		b:box("ClothCheck", bx - 0.5, 2.1, -1.2, bx + 0.5, 2.3, -0.45, C.White, Kit.DECOR)
		b:box("Basket", bx - 0.7, 2.15, -2.6, bx + 0.6, 3.3, -1.5, C.Wood)
		b:box("BasketLid", bx - 0.8, 3.25, -2.7, bx + 0.7, 3.6, -1.4, C.WoodLight, Kit.NOSHADOW)
		b:box("BasketHandle", bx - 0.15, 3.55, -2.25, bx + 0.05, 4.4, -1.85, C.WoodDark, Kit.DECOR)
	end
end

-- Mid-span lookout of a bridge (Props.bridge local frame `cf`: y = 0 is the deck top, local -Z
-- runs from the hub to the promenade, ±hw are the deck edges): a bump-out on both sides in the
-- gateway's colour with a thick railing, a lamp and a flag on the outer corners, a stone pier
-- under each; the left wing (deeper) carries the sell kiosk, the right one a bench facing the
-- water and a telescope. The bridge's own railing is cut open there (see buildBridges). ~65
-- parts.
local function lookout(bridge: any, cf: any, hw: number, bedLocal: number, theme: any, k: number)
	local b = Kit.builder(bridge, "Lookout", cf)
	local zh = LOOKOUT_HALF
	local deckC = Kit.lerpColor(theme.color, C.White, 0.55)
	local railC = theme.color
	local first
	local flagX = {}
	for i, sx in { -1, 1 } do
		local out = if i == 1 then KIOSK_OUT else LOOKOUT_OUT
		local x0, x1 = sx * (hw + 0.25), sx * (hw + out)
		local lo, hi = math.min(x0, x1), math.max(x0, x1)
		local deck = b:box(`Deck{i}`, lo, -1.2, -zh, hi, 0, zh, deckC)
		first = first or deck
		-- one stone pier under the bump-out
		local px0, px1 = sx * (hw + 1.4), sx * (hw + out - 1)
		b:box(`Pier{i}`, math.min(px0, px1), bedLocal, -3, math.max(px0, px1), -1.2, 3, C.StoneLight)
		-- railing: the outer rail and two end rails, on posts at the corners
		-- (rails 1.5 thick, inner posts 1.8: their faces stay clear of the lamp posts' 1.1)
		local ox = sx * (hw + out - 0.75)
		b:box(`Rail{i}`, ox - 0.75, 3.0, -zh + 0.75, ox + 0.75, 4.4, zh - 0.75, railC, Kit.NOSHADOW)
		for j, sz in { -1, 1 } do
			local z = sz * (zh - 0.75)
			local ix = sx * (hw - 0.45)
			-- (the end rails' tops 0.1 under the side rails': no shared top face)
			b:box(
				`EndRail{i}_{j}`,
				math.min(ix, ox),
				3.0,
				z - 0.75,
				math.max(ix, ox),
				4.3,
				z + 0.75,
				railC,
				Kit.NOSHADOW
			)
			b:box(`InnerPost{i}_{j}`, ix - 0.9, -0.05, z - 0.9, ix + 0.9, 4.8, z + 0.9, C.White)
		end
		-- a lamp (theme-coloured caps) on one outer corner, a flag on the other
		local lampCf = cf * CFrame.new(ox, 0, -(zh - 0.75))
		Kit.lamp(b.model, lampCf, { height = 6.5, trim = theme.color, light = i == 2 })
		b:pole(`FlagPole{i}`, 0.7, ox, zh - 0.75, -0.05, 13, C.White)
		local fx0, fx1 = ox + sx * 0.3, ox + sx * 5.3
		b:box(`Flag{i}`, math.min(fx0, fx1), 9.4, zh - 0.9, math.max(fx0, fx1), 12.6, zh - 0.6, theme.color, Kit.DECOR)
		flagX[i] = ox
		if i == 1 then
			-- the sell kiosk, its counter at the wing's inner edge facing the bridge deck
			local kx = sx * (hw + 3.2)
			sellKiosk(b.model, cf * CFrame.new(kx, 0, 0) * CFrame.Angles(0, math.rad(90 * sx), 0), theme, k)
		else
			-- a chunky bench facing the water
			local bx = sx * (hw + 3.6)
			local backX0, backX1 = bx - sx * 1.5, bx - sx * 1.0
			b:box(`BenchBase{i}`, bx - 0.7, -0.05, -2.2, bx + 0.7, 1.5, 2.2, C.Wood)
			b:box(`BenchSeat{i}`, bx - 1.2, 1.5, -3, bx + 1.2, 2.1, 3, C.WoodLight)
			b:box(`BenchBack{i}`, math.min(backX0, backX1), 2.1, -3, math.max(backX0, backX1), 4.0, 3, theme.color)
			wingAccent(b, theme, bx, ox)
		end
	end
	-- a telescope on the right-hand bump-out, looking out over the lagoon
	local tx = hw + LOOKOUT_OUT - 2.4
	b:box("ScopeStand", tx - 0.4, -0.05, 6.1, tx + 0.4, 3.6, 6.9, C.Navy)
	b:box("ScopeTube", tx - 1.2, 3.6, 5.95, tx + 1.9, 4.7, 7.05, C.Gold)
	b:box("ScopeLens", tx + 1.9, 3.45, 5.8, tx + 2.2, 4.85, 7.2, C.Glass, Kit.NOSHADOW)
	-- bunting across the deck between the two flag poles (well above the players' heads)
	local fz = zh - 0.75
	Kit.prop(
		"bunting",
		b.model,
		(cf * CFrame.new(flagX[1], 12.2, fz)).Position,
		(cf * CFrame.new(flagX[2], 12.2, fz)).Position,
		{ seed = 3, count = 4, sag = 1.6, name = "Bunting" }
	)
	b:finish(first)
	return b.model
end

-- Returns the attachments it placed (the sell kiosks' prompts) for the build's self-check:
-- { { root = "workspace", path = {...}, offset = Vector3 }, ... }.
function Promenade.buildBridges(map: any, cfg: any, world: any): { any }
	local bridges = U.model(map, "Bridges")
	local top = cfg.GroundTop + DECK_TOP
	local attachments = {}
	for i, angle in cfg.BridgeAngles do
		local theme = Promenade.Themes[angle % 360] or Promenade.Themes[0]
		local from = U.polar(angle, cfg.HubPlazaRadius - 6, 0)
		-- the deck runs 0.4 stud under the promenade tiles (the landing plate covers the seam)
		local to = U.polar(angle, cfg.PromenadeRadius + 0.4, 0)
		local deckY = cfg.GroundTop + 0.6
		local width = cfg.BridgeWidth
		-- no end arches: the hub's avenue gates and the gateway arches frame every crossing
		local bridge = Kit.prop("bridge", bridges, from, to, {
			deckY = deckY,
			width = width,
			bedY = -cfg.LagoonDepth,
			plankLength = 10,
			postSpacing = 16,
			bentSpacing = 48,
			roof = theme.color,
			gates = false,
			lights = false,
			seed = i * 31,
		})
		bridge.Name = `Bridge_{i}`
		-- the Props.bridge frame: y = 0 on the deck, local -Z from the hub to the promenade
		local a = Vector3.new(from.X, deckY, from.Z)
		local c = Vector3.new(to.X, deckY, to.Z)
		local cf = CFrame.lookAt((a + c) / 2, c)
		local hw = width / 2
		local L = (c - a).Magnitude
		local inv = cf:Inverse()
		local pastel = Kit.lerpColor(theme.color, C.White, 0.6)
		local honey = Kit.lerpColor(C.Wood, C.WoodLight, 0.45)
		local open = LOOKOUT_HALF - 0.75 -- rails end inside the lookout's inner corner posts
		for _, d in bridge:GetChildren() do
			if not d:IsA("BasePart") then
				continue
			end
			local name = d.Name
			local lp = (inv * d.CFrame).Position
			if string.match(name, "^Deck%d+$") then
				-- planks: light / honey wood, every fourth one in the gateway's pastel
				local k = tonumber(string.sub(name, 5)) :: number
				d.Color = if k % 4 == 3 then theme.plank or pastel elseif k % 2 == 1 then C.WoodLight else honey
			elseif string.match(name, "^TopRail") or string.match(name, "^MidRail") then
				-- split round the lookout; the top rail gets chunkier (1.2 x 1.4) and the
				-- gateway's colour, the mid rail its pastel
				local isTop = string.match(name, "^TopRail") ~= nil
				local size = if isTop then Vector3.new(1.2, 1.4, 0) else Vector3.new(d.Size.X, d.Size.Y, 0)
				local y = if isTop then 3.7 else lp.Y
				for j, seg in { { open, L / 2 }, { -L / 2, -open } } do
					local len = seg[2] - seg[1]
					U.part(
						bridge,
						`{name}_{j}`,
						Vector3.new(size.X, size.Y, len),
						cf * CFrame.new(lp.X, y, (seg[1] + seg[2]) / 2),
						if isTop then theme.color else pastel,
						nil,
						if isTop then nil else Kit.NOSHADOW
					)
				end
				d:Destroy()
			elseif math.abs(lp.Z) < LOOKOUT_HALF + 0.5 and math.abs(lp.X) > hw - 2 and lp.Y > -0.2 and d.Size.Z < 4 then
				-- posts and lanterns in the opening
				d:Destroy()
			elseif string.match(name, "^Pile") or string.match(name, "^Cap%d") then
				-- dark wood stays on the piles under the deck; the end bents stand in the sand
				-- (hub plaza / beach) and are never seen
				local p = d.CFrame.Position
				if world and world:heightAt(p.X, p.Z) >= p.Y + d.Size.Y / 2 - 0.25 then
					d:Destroy()
				elseif string.match(name, "^Cap") then
					d.Color = pastel
				end
			elseif string.match(name, "^Post") or string.match(name, "^LampPost") or string.match(name, "^Kerb") then
				d.Color = C.White
			elseif string.match(name, "^Stringer") then
				d.Color = C.Wood
			end
		end
		lookout(bridge, cf, hw, -cfg.LagoonDepth - deckY, theme, i)
		table.insert(attachments, {
			root = "workspace",
			path = { "Map", "Bridges", bridge.Name, "Lookout", "SellKiosk", "Scales", "SellPromptAttachment" },
			offset = KIOSK_PROMPT_OFFSET,
		})
		-- landing plate where the deck meets the promenade: it covers the deck end and the tile
		-- edge (their tops are only 0.04-0.16 apart) with one clear top 0.1 above the tiles
		local land = U.polar(angle, cfg.PromenadeRadius + 0.6, 0)
		U.part(
			bridge,
			"Landing",
			Vector3.new(width + 1.2, 0.7, 3.4),
			CFrame.new(land.X, top + 0.22 - 0.35, land.Z) * CFrame.Angles(0, math.rad(angle), 0),
			pastel,
			nil,
			FLAT
		)
	end
	return attachments
end

--------------------------------------------------------------------------------------------
-- Promenade ring
--------------------------------------------------------------------------------------------

-- Ring piece between angles a0..a1 (degrees) and radii r0..r1, top at y, as one block along
-- the chord (wide enough to cover the outer arc).
local function ringPiece(
	parent: any,
	name: string,
	a0: number,
	a1: number,
	r0: number,
	r1: number,
	y0: number,
	y1: number,
	color: any,
	extra: any?
): any
	local am = (a0 + a1) / 2
	local half = rad(a1 - a0) / 2
	local length = 2 * r1 * tan(half) + 0.1
	local rm = (r0 + r1) / 2 * cos(half) -- chord midpoint of the band
	local cf = U.polarCFrame(am, rm, (y0 + y1) / 2)
	return U.part(parent, name, Vector3.new(length, y1 - y0, r1 - r0), cf, color, nil, extra)
end

-- The sea wall: its lagoon face (r = WALL_IN) hides the beach/grass step under the promenade's
-- lagoon edge; open only where a pier or bridge deck meets the promenade (± DECK_HALF studs).
local WALL_IN = 308.2
local DECK_HALF = 10

-- Railing gaps: piers (base angle ± PIER_GAP: the pier deck plus a broad flight of sand steps
-- on each side), bridge landings (the deck only: the railing runs right up to the bridge) and
-- the sand steps down to the beach (± STEP_GAP at STEP_ANGLES, between two plots).
local PIER_GAP = 6
local BRIDGE_GAP = math.deg(math.asin(DECK_HALF / WALL_IN))
local STEP_GAP = 1.3
local STEP_ANGLES = { 45, 135, 225, 315 }

local function inGap(cfg: any, a: number): boolean
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		if Kit.angleDistance(a, base) < PIER_GAP then
			return true
		end
	end
	for _, b in cfg.BridgeAngles do
		if Kit.angleDistance(a, b) < BRIDGE_GAP then
			return true
		end
	end
	for _, s in STEP_ANGLES do
		if Kit.angleDistance(a, s) < STEP_GAP then
			return true
		end
	end
	return false
end

-- True where a pier or bridge deck crosses the sea wall line.
local function onDeck(cfg: any, a: number): boolean
	local half = math.deg(math.asin(DECK_HALF / WALL_IN))
	for i = 1, cfg.BaseCount do
		if Kit.angleDistance(a, cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount) < half then
			return true
		end
	end
	for _, b in cfg.BridgeAngles do
		if Kit.angleDistance(a, b) < half then
			return true
		end
	end
	return false
end

-- Continuous runs { a0, a1, class } of the ring (degrees, increasing) where class(a) is the
-- same; the scan starts on a pier (deck) so no run wraps around 360.
local function runs(cfg: any, class: (number) -> string): { { any } }
	local list = {}
	local step = 0.25
	local start, current = nil, nil
	local origin = cfg.BaseAngleOffset
	for k = 0, 360 / step do
		local a = origin + k * step
		local c = class(a)
		if c ~= current then
			if start then
				table.insert(list, { start, a - step, current })
			end
			start, current = a, c
		end
	end
	if start then
		table.insert(list, { start, origin + 360, current })
	end
	return list
end

-- Railing runs [a0, a1] outside the gaps.
local function railRuns(cfg: any): { { any } }
	local list = {}
	for _, run in
		runs(cfg, function(a)
			return if inGap(cfg, a) then "gap" else "rail"
		end)
	do
		if run[3] == "rail" then
			table.insert(list, run)
		end
	end
	return list
end

-- Splits [a0, a1] into pieces of at most `maxStep` degrees.
local function pieces(a0: number, a1: number, maxStep: number): { { number } }
	local n = math.max(1, math.ceil((a1 - a0) / maxStep - 1e-6))
	local list = {}
	for p = 0, n - 1 do
		table.insert(list, { a0 + (a1 - a0) * p / n, a0 + (a1 - a0) * (p + 1) / n })
	end
	return list
end

-- Colour of the promenade quarter around angle a: the theme of the nearest bridge/gateway, so
-- each quarter of the ring is recognisable (orange south, pink east, blue north, green west).
local function quarterColor(a: number): any
	local best, color = math.huge, C.Navy
	for angle, theme in Promenade.Themes do
		local d = Kit.angleDistance(a, angle)
		if d < best then
			best, color = d, theme.color
		end
	end
	return color
end

-- Chunky planter (4 parts): a bright box (4.8 along the ring), a leafy mound and two blooms in
-- two colours poking out of it at different heights. Stands on cf (local X along the ring).
local function planter(parent: any, cf: any, boxColor: any, c1: any, c2: any)
	local b = Kit.builder(parent, "Planter", cf)
	local box = b:box("Box", -2.4, -0.2, -1.4, 2.4, 1.2, 1.4, boxColor)
	b:box("Greens", -2.05, 0.9, -1.05, 2.05, 2.2, 1.05, C.Leaf2, Kit.DECOR)
	b:box("Bloom1", -1.6, 2.0, -0.65, -0.5, 3.1, 0.45, c1, Kit.DECOR)
	b:box("Bloom2", 0.45, 2.05, -0.4, 1.55, 3.35, 0.7, c2, Kit.DECOR)
	return b:finish(box)
end

-- Bloom colours for the planters (never the box's own colour).
local PLANTER_BLOOMS = { C.Yellow, C.Red, C.Pink, C.Purple, C.Orange, C.Blue }

function Promenade.buildPromenade(map: any, cfg: any, world: any): number
	local promenade = U.model(map, "Promenade")
	local G = cfg.GroundTop
	local inner = cfg.PromenadeRadius
	local outer = inner + cfg.PromenadeWidth
	local top = G + DECK_TOP

	-- Paving: 48 warm sand tiles (7.5°), all one colour at one height (the chord rectangles
	-- overlap near the inner edge: same colour, so no seam, no lip and no shimmer), a coral
	-- middle band in 96 short chords (3.75°: it reads as a smooth curve at eye level) and white
	-- kerbs. A darker sand joint strip across the walk every 15° gives the paving its rhythm.
	local paving = U.model(promenade, "Paving")
	local tileColor = rgb(244, 210, 154)
	local step = 360 / 96 -- railing post grid (3.75°)
	for k = 0, 47 do
		local a0 = k * 2 * step
		ringPiece(paving, "Tile", a0, a0 + 2 * step, inner + 0.2, outer, G - 1, top, tileColor, FLAT)
	end
	local bandColor = rgb(255, 128, 104)
	local mid = (inner + outer) / 2
	for k = 0, 95 do
		local a0 = k * step
		ringPiece(paving, "Band", a0, a0 + step, mid - 2.2, mid + 2.2, top, top + 0.28, bandColor, Kit.NOSHADOW)
	end
	-- joint strips (2 wide, 0.12 proud) from the coping to the kerb, under the band's top
	local jointColor = rgb(228, 178, 116)
	for k = 0, 23 do
		local a = k * 4 * step
		local p = U.polar(a, (inner + 1.6 + outer - 1.4) / 2, 0)
		U.part(
			paving,
			"Joint",
			Vector3.new(2, 0.24, outer - inner - 3.0),
			CFrame.new(p.X, top, p.Z) * CFrame.Angles(0, rad(a), 0),
			jointColor,
			nil,
			FLAT
		)
	end
	-- outer kerb (0.5 high: walkable) between the plots; in front of a plot its own front wall
	-- already edges the walk, and it opens where the gateway roads (± 9 studs) and the landmark
	-- paths (± 6) leave the ring. It overhangs the tiles' outer face by ~0.2 (no shimmer).
	local roadGap = math.deg(math.asin(11 / outer))
	local pathGap = math.deg(math.asin(8 / outer))
	for _, run in
		runs(cfg, function(a)
			for i = 1, cfg.BaseCount do
				if Kit.angleDistance(a, cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount) < 11 then
					return "open"
				end
			end
			for _, b in cfg.BridgeAngles do
				if Kit.angleDistance(a, b) < roadGap then
					return "open"
				end
			end
			for _, s in STEP_ANGLES do
				if Kit.angleDistance(a, s) < pathGap then
					return "open"
				end
			end
			return "kerb"
		end)
	do
		if run[3] == "kerb" then
			for _, pc in pieces(run[1], run[2], 7.5) do
				ringPiece(paving, "KerbOuter", pc[1], pc[2], outer - 1.4, outer + 0.2, top, top + 0.5, C.White, FLAT)
			end
		end
	end

	-- Railing on the lagoon side, on the sea wall's coping: white posts every 3.75°, a blue top
	-- rail; lamps replace some posts; open at piers, bridges and the beach steps.
	local railing = U.model(promenade, "Railing")
	local railColor = rgb(70, 176, 255)
	local postR = inner + 0.9
	local lampModel = U.model(promenade, "Lamps")
	local lamps = 0
	local lampAngles = {}
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		for _, off in { 7.5, 15, 30, 37.5 } do
			lampAngles[floor(((base + off) % 360) * 100 + 0.5)] = true
		end
	end
	local function isLamp(a: number): boolean
		return lampAngles[floor((a % 360) * 100 + 0.5)] == true
	end
	-- Sea wall along the lagoon edge: a light stone face from the beach (y 1.5) up to the walk,
	-- under a white coping that is also the railing's kerb; where the railing is open (beside
	-- the piers and bridge landings, at the beach steps) the wall stops just under the tiles.
	local seaWall = U.model(promenade, "SeaWall")
	local stone = Kit.lerpColor(C.StoneLight, C.White, 0.25)
	for _, run in
		runs(cfg, function(a)
			return if onDeck(cfg, a) then "deck" elseif inGap(cfg, a) then "open" else "rail"
		end)
	do
		if run[3] == "deck" then
			continue
		end
		for _, pc in pieces(run[1], run[2], 7.5) do
			if run[3] == "rail" then
				ringPiece(seaWall, "Wall", pc[1], pc[2], WALL_IN + 0.2, inner + 0.3, 1.5, top - 0.2, stone, FLAT)
				ringPiece(seaWall, "Coping", pc[1], pc[2], WALL_IN, inner + 1.6, top - 0.2, top + 0.6, C.White, FLAT)
			else
				ringPiece(seaWall, "Wall", pc[1], pc[2], WALL_IN, inner + 0.3, 1.5, top - 0.12, stone, FLAT)
				-- two sand steps down to the beach along the whole opening (beside the piers and
				-- at the step gaps between two plots): no ledge to jump back up
				ringPiece(seaWall, "Step1", pc[1], pc[2], WALL_IN - 2.8, WALL_IN + 0.1, 1.5, 3.85, C.Cream, FLAT)
				ringPiece(seaWall, "Step2", pc[1], pc[2], WALL_IN - 5.6, WALL_IN - 2.8, 1.5, 2.95, C.SandDark, FLAT)
			end
		end
	end

	local posts = {}
	-- (the end posts stand 0.75 inside the run, so their sides stay clear of the coping's end)
	local inset = math.deg(0.75 / postR)
	for _, run in railRuns(cfg) do
		local a0, a1 = run[1] + inset, run[2] - inset
		-- posts at the run ends and on the 3.75° grid between them
		local list = { a0 }
		local g = math.ceil(a0 / step + 0.01) * step
		while g < a1 - 1 do
			table.insert(list, g)
			g += step
		end
		table.insert(list, a1)
		for j, a in list do
			local p = U.polar(a, postR, 0)
			if isLamp(a) then
				Kit.lamp(lampModel, CFrame.new(p.X, top + 0.6, p.Z) * CFrame.Angles(0, rad(a), 0), {
					height = 8,
					trim = quarterColor(a),
					light = lamps % 4 == 0,
				})
				lamps += 1
			else
				U.part(
					railing,
					"Post",
					Vector3.new(1.3, 3.2, 1.3),
					CFrame.new(p.X, top + 0.6 + 1.5, p.Z) * CFrame.Angles(0, rad(a), 0),
					C.White,
					nil,
					Kit.NOSHADOW
				)
			end
			if j > 1 then
				local q = U.polar(list[j - 1], postR, 0)
				local d = Vector3.new(p.X - q.X, 0, p.Z - q.Z)
				local m = (p + q) / 2
				U.part(
					railing,
					"Rail",
					Vector3.new(0.8, 0.7, d.Magnitude),
					CFrame.lookAt(Vector3.new(m.X, top + 3.0, m.Z), Vector3.new(p.X, top + 3.0, p.Z)),
					railColor,
					nil,
					Kit.NOSHADOW
				)
			end
			table.insert(posts, a)
		end
	end
	-- life rings on the lagoon side of the posts next to the sand steps (one beside each flight)
	for k, sa in STEP_ANGLES do
		local a = sa + (if k % 2 == 0 then step else -step)
		local p = U.polar(a, postR - 0.95, 0)
		-- (front, local -Z, towards the lagoon)
		Kit.prop("lifebuoy", railing, CFrame.new(p.X, top + 2.3, p.Z) * CFrame.Angles(0, rad(a), 0), { seed = k })
	end

	-- Bunting between the first two lamps after each pier (lantern tops ~ y + 11).
	local bunting = U.model(promenade, "Bunting")
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		local pa = U.polar(base + 7.5, postR, top + 10.9)
		local pb = U.polar(base + 15, postR, top + 10.9)
		Kit.prop("bunting", bunting, pa, pb, { seed = i * 7, count = 4, sag = 2.4, name = "Bunting" })
	end

	-- A bench facing the lagoon and planters on both sides of each plot's gate; more planters
	-- along the land edge of the stretches between two plots (both sides of the gateway road
	-- or landmark path), so something colourful passes by every ~35 studs. The lagoon edge keeps
	-- its lamps only: the running lane stays clear.
	local furniture = U.model(promenade, "Furniture")
	-- (boxes in the colour of the ring quarter, like the lamp caps)
	local n = 0
	local function planterAt(a: number, r: number)
		n += 1
		local q = U.polar(a, r, 0)
		local boxColor = quarterColor(a)
		local blooms = {}
		for _, c in PLANTER_BLOOMS do
			if c ~= boxColor then
				table.insert(blooms, c)
			end
		end
		planter(
			furniture,
			CFrame.new(q.X, top, q.Z) * CFrame.Angles(0, rad(a), 0),
			boxColor,
			blooms[(n * 2) % #blooms + 1],
			blooms[(n * 2 + 3) % #blooms + 1]
		)
	end
	for i = 1, cfg.BaseCount do
		local base = cfg.BaseAngleOffset + (i - 1) * 360 / cfg.BaseCount
		local ab = base + 9
		local p = U.polar(ab, outer - 3.2, 0)
		Kit.bench(furniture, CFrame.new(p.X, top, p.Z) * CFrame.Angles(0, rad(ab), 0), {
			length = 7,
			color = C.WoodLight,
			legs = quarterColor(ab),
		})
		for _, sgn in { -1, 1 } do
			planterAt(base + sgn * 5.6, outer - 2.6)
		end
		-- the stretch from this plot to the next one (centre = base + 22.5)
		local gap = base + 180 / cfg.BaseCount
		for _, off in { -6.2, 6.2 } do
			planterAt(gap + off, outer - 2.6)
		end
	end

	-- Big billboards at the landmark path mouths (land side, beside the path, facing the
	-- lagoon), on the first spot where both feet stand on the same flat ground (the waterfall
	-- pond's sand rim reaches the promenade). Each sign is claimed (Nature keeps off it).
	for _, sign in PATH_SIGNS do
		local spot = nil
		local side = sign.side or 1
		for _, d in { 2.7, 3.4, 4.1, -2.7, -3.4, 4.8, 5.5 } do
			for _, dr in { 5, 4, 7 } do
				local a = sign.angle + d * side
				local ok = true
				-- (the feet reach 6 studs to the sides and 2 behind the board)
				for _, f in { -6.5, -4, 0, 4, 6.5 } do
					for _, back in { -0.5, 2.5 } do
						local x, z = Kit.radial(a, outer + dr + back, f, 0)
						local h, kind, water = world:surfaceAt(x, z)
						if water or h ~= G or kind == "sand" then
							ok = false
						end
					end
				end
				if ok then
					spot = { a, outer + dr }
					break
				end
			end
			if spot then
				break
			end
		end
		local fallback = { sign.angle + 2.7 * side, outer + 5 }
		local a, r = (spot or fallback)[1], (spot or fallback)[2]
		local p = U.polar(a, r, 0)
		Kit.claim(p.X, p.Z, 8)
		Kit.prop(
			"billboard",
			promenade,
			CFrame.new(p.X, world:heightAt(p.X, p.Z), p.Z) * CFrame.Angles(0, rad(sign.angle), 0),
			{
				text = sign.text,
				width = 13,
				height = 4,
				lift = 3.5,
				color = sign.color,
				back = false,
				name = "PathSign",
			}
		)
	end

	return lamps
end

return Promenade
