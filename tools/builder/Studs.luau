--[[
	Studs — the LEGO look (art direction v5, DESIGN.md §1): one post-pass over a finished model
	tree (Workspace.Map, ServerStorage.BaseTemplate), run by tools/build.luau after every builder.

	The engine's own surfaces do the work: SurfaceType.Studs / Inlet draw the classic 1-stud LEGO
	studs / holes, but ONLY on Material.Plastic (2019 engine change; SmoothPlastic shows none).
	No uploaded textures, no extra instances, no extra draw calls; studs stay crisp on phones.

	Studs.apply(root) — a qualifying part (Studs.qualifies) gets Material = Plastic, Studs on the
	face that points world-up and Smooth on the other five (all six set explicitly, whichever local
	axis points up). Inlet (LEGO's hollow underside) on the face that points world-down only where
	asked: attribute StudsBottom = true on the part or an ancestor (a ceiling you walk under, e.g.
	the market arcades') and never on foliage (FOLIAGE_NAME) — v3 fix W7: canopies, roofs and decks
	seen from below no longer show rows of dark holes. Everything else is untouched (builders make
	SmoothPlastic + Smooth surfaces, so it stays flat).

	A part qualifies when it is
	  * a Part / SpawnLocation with Shape Block (no wedges = LEGO slopes are smooth, no cylinders,
	    balls, trusses, meshes), opaque (Transparency <= 0.02), SmoothPlastic or Plastic (Neon,
	    Glass and other materials stay as they are);
	  * not under an ancestor named Sky / Boundaries / Underwater / BaseSlots / Water and not
	    named like water, foam, glass, clouds … (SKIP_NAME, lower-case substrings; pool rims,
	    breakwaters, splash rocks and jetties are solid: SKIP_NAME_EXCEPT);
	  * axis-aligned with the world up (one local axis within 2.6° of +Y or -Y; tilted parts stay
	    smooth) and its up face is at least 2 x 2 studs; a face under 6 studs on both sides must
	    also be whole studs (± 0.1) — no cut studs on small props.
	Overrides: attribute Studs = false on the part or any ancestor (up to root) is a hard
	opt-out; Studs = true skips the name / ancestor filters (geometry, opacity and material
	checks still apply).
	Knobs: PATHS_AS_TILES (variant B: paving, avenues, plaza, bridges and walks stay smooth LEGO
	"tiles"; default false = variant A, studs on paths too), FOLIAGE (studs on tree/bush tops).

	Studs.resolveCoplanar(roots) — two overlapping up faces at (nearly) one height — closer than
	COPLANAR_EPS (0.05: a phone's depth buffer cannot tell them apart from 150+ studs) — z-fight. With the
	old SmoothPlastic in one colour that was invisible; with two stud grids out of phase (or studs
	against a flat face) it shimmers. Every such pair (unless both are studded, the same colour and
	their grids line up) is separated by moving one top RAISE (0.06) studs: the smaller part up,
	else the smaller down, else the bigger up / down (a part grows or shrinks, its bottom stays).
	A move is allowed only if it does not reach another overlapping layer that was above / below
	(layers never swap) and keeps the part's first direction; gameplay parts never move (tags,
	SpawnLocation, attributes other than the decor ones in DECOR_ATTR, PROTECTED_NAME). Repeats
	until nothing moves (a moved face may meet another one at its new height; passes 2+ only
	re-test moved faces), at most MAX_PASSES; a pair no move can fix (a paving disc of three
	pieces squeezed between two layers) is flattened: its studded pieces — with every same-colour
	piece of that surface — become SmoothPlastic tiles. Typical map + template: ~245 parts moved
	0.06–0.12, none flattened (builders keep their layers 0.06 apart). Studs.coplanarPairs(roots)
	counts what is left (self-check, tests: 0).
]]

local U = require("./Util")

local Enum = U.Enum
local Vector3 = U.Vector3

local Studs = {}

Studs.MIN_DIM = 2 -- both sides of the up face >= this (studs)
Studs.CLEAN_BELOW = 6 -- up faces under this on BOTH sides need whole-stud sides (no cut studs on small props)
Studs.INT_TOL = 0.1 -- "whole stud" tolerance
Studs.UP_DOT = 0.999 -- |local axis · world up| above this = the axis points up
Studs.MAX_TRANSPARENCY = 0.02
-- Sanity bands for the studded part counts (build self-check, tests): a broken rule shows up as
-- a count far off. v3 map: ~6 370 studded parts, base template ~180. Widen when a builder adds
-- many flat parts on purpose.
Studs.EXPECTED = { map = { 5500, 9000 }, template = { 150, 350 } }
Studs.PATHS_AS_TILES = false -- variant B: paved walks stay smooth LEGO tiles; default (A): studs there too
Studs.FOLIAGE = true -- studs on tree / bush / hedge tops
-- Variant B: paved walkways (ancestor names and Lua patterns on the part name).
Studs.TILE_ANCESTOR = { Paving = true, Avenues = true, Plaza = true, Bridges = true }
Studs.TILE_NAME = { "Walk$", "^Path%d*$", "^PathSide$" }
Studs.FOLIAGE_NAME = { "^Canopy", "^Frond", "Leaves$", "^Clump", "^Hedge", "^Bush", "^Crown$", "^Tier$", "^Skirt$" }
-- Ancestors (by name) whose parts never get studs: the sky, invisible walls, the seabed, slot
-- markers, edit-mode water stand-ins (export_parts draws Map.Water / WaterVolumes as water).
Studs.SKIP_ANCESTOR =
	{ Sky = true, Boundaries = true, Underwater = true, BaseSlots = true, Water = true, WaterVolumes = true }
-- Lower-case substrings of part names that never get studs (water-like, soft or glassy things).
Studs.SKIP_NAME = {
	"water",
	"pool",
	"pond",
	"foam",
	"splash",
	"glass",
	"cloud",
	"puff",
	"mist",
	"ripple",
	"wave",
	"spray",
	"jet",
}
-- ...except these: solid things whose names contain such a word (pool / pond rims, breakwaters,
-- splash rocks, jetties).
Studs.SKIP_NAME_EXCEPT = { "rim", "breakwater", "rock", "jetty" }

-- local axis (1 = X, 2 = Y, 3 = Z) -> { face along +axis, face along -axis }
local FACES = {
	{ "RightSurface", "LeftSurface" },
	{ "TopSurface", "BottomSurface" },
	{ "BackSurface", "FrontSurface" },
}
local ALL_FACES = { "TopSurface", "BottomSurface", "LeftSurface", "RightSurface", "FrontSurface", "BackSurface" }
Studs.ALL_FACES = ALL_FACES

local function nearInt(x: number): boolean
	return math.abs(x - math.floor(x + 0.5)) <= Studs.INT_TOL
end

-- The nearest value of an attribute on the part or an ancestor up to (and including) root.
local function attrUp(part: any, root: any, name: string): any
	local stop = root.Parent
	local x = part
	while x and x ~= stop do
		local value = x:GetAttribute(name)
		if value ~= nil then
			return value
		end
		x = x.Parent
	end
	return nil
end

local function underAncestor(part: any, root: any, names: { [string]: boolean }): boolean
	local stop = root.Parent
	local x = part.Parent
	while x and x ~= stop do
		if names[x.Name] then
			return true
		end
		x = x.Parent
	end
	return false
end

local function skippedByName(name: string): boolean
	local lower = string.lower(name)
	for _, word in Studs.SKIP_NAME do
		if string.find(lower, word, 1, true) then
			for _, keep in Studs.SKIP_NAME_EXCEPT do
				if string.find(lower, keep, 1, true) then
					return false
				end
			end
			return true
		end
	end
	return false
end

local function matchesAny(name: string, patterns: { string }): boolean
	for _, pattern in patterns do
		if string.find(name, pattern) then
			return true
		end
	end
	return false
end

-- The local axis that points world-up: (axis 1..3 or nil, sign +1 = its + face is on top,
-- the two side lengths of the up face).
local function upAxis(part: any): (number?, number, number, number)
	local cf = part.CFrame
	local ys = { cf.RightVector.Y, cf.UpVector.Y, -cf.LookVector.Y } -- local +X, +Y, +Z
	for i, y in ys do
		if math.abs(y) > Studs.UP_DOT then
			local size = part.Size
			local dims = { size.X, size.Y, size.Z }
			return i, if y > 0 then 1 else -1, dims[i % 3 + 1], dims[(i + 1) % 3 + 1]
		end
	end
	return nil, 0, 0, 0
end

function Studs.qualifies(part: any, root: any): (boolean, string)
	if not (part.ClassName == "Part" or part.ClassName == "SpawnLocation") then
		return false, "class"
	end
	if part.Shape ~= Enum.PartType.Block then
		return false, "shape"
	end
	local forced = attrUp(part, root, "Studs")
	if forced == false then
		return false, "optout"
	end
	if part.Transparency > Studs.MAX_TRANSPARENCY then
		return false, "transparent"
	end
	if part.Material ~= Enum.Material.SmoothPlastic and part.Material ~= Enum.Material.Plastic then
		return false, "material"
	end
	if forced ~= true then
		if underAncestor(part, root, Studs.SKIP_ANCESTOR) then
			return false, "ancestor"
		end
		if skippedByName(part.Name) then
			return false, "name"
		end
		if
			Studs.PATHS_AS_TILES
			and (underAncestor(part, root, Studs.TILE_ANCESTOR) or matchesAny(part.Name, Studs.TILE_NAME))
		then
			return false, "tile"
		end
		if not Studs.FOLIAGE and matchesAny(part.Name, Studs.FOLIAGE_NAME) then
			return false, "foliage"
		end
	end
	local axis, _, a, b = upAxis(part)
	if not axis then
		return false, "tilted"
	end
	if math.min(a, b) < Studs.MIN_DIM - 1e-3 then
		return false, "small"
	end
	if math.max(a, b) < Studs.CLEAN_BELOW and not (nearInt(a) and nearInt(b)) then
		return false, "fractional"
	end
	return true, "ok"
end

-- Does this studded part show LEGO's hollow underside (Inlet on the world-down face)? Only where
-- StudsBottom = true (part or ancestor) and never on foliage.
function Studs.wantsInlet(part: any, root: any): boolean
	return attrUp(part, root, "StudsBottom") == true and not matchesAny(part.Name, Studs.FOLIAGE_NAME)
end

-- Plastic + Studs on the world-up face, Inlet on the world-down face where wanted, the rest Smooth.
local function studify(part: any, root: any)
	local axis, sign = upAxis(part)
	local faces = FACES[axis :: number]
	part.Material = Enum.Material.Plastic
	for _, face in ALL_FACES do
		part[face] = Enum.SurfaceType.Smooth
	end
	part[if sign > 0 then faces[1] else faces[2]] = Enum.SurfaceType.Studs
	if Studs.wantsInlet(part, root) then
		part[if sign > 0 then faces[2] else faces[1]] = Enum.SurfaceType.Inlet
	end
end

-- Applies the studs to every qualifying BasePart under root. Returns counts per reason
-- (ok = studded; class / shape / optout / transparent / material / ancestor / name / tile /
-- foliage / tilted / small / fractional = left as it was).
function Studs.apply(root: any): { [string]: number }
	local stats: { [string]: number } = { ok = 0 }
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") then
			local ok, why = Studs.qualifies(part, root)
			stats[why] = (stats[why] or 0) + 1
			if ok then
				studify(part, root)
			end
		end
	end
	return stats
end

-- Faces of the part that carry studs (names of the *Surface properties).
function Studs.studFaces(part: any): { string }
	local list = {}
	for _, face in ALL_FACES do
		if part[face] == Enum.SurfaceType.Studs then
			table.insert(list, face)
		end
	end
	return list
end

-- A Plastic part with a Studs face: what the engine draws studs on.
function Studs.isStudded(part: any): boolean
	return part.Material == Enum.Material.Plastic and #Studs.studFaces(part) > 0
end

-- Studded parts whose up face is big (a side >= minSide studs, default CLEAN_BELOW) but not whole
-- studs on both sides (± 0.02): the engine draws cut half-studs along an edge there, and the rows
-- run out of phase with the neighbours'. `filter(part)` picks the parts to check (nil = all).
-- The build lists them (v3 fix W4) and fails on the hero surfaces in HERO_FACES.
function Studs.fractionalFaces(root: any, filter: ((any) -> boolean)?, minSide: number?): { any }
	local list = {}
	local least = minSide or Studs.CLEAN_BELOW
	for _, part in root:GetDescendants() do
		if part:IsA("BasePart") and Studs.isStudded(part) and (filter == nil or filter(part)) then
			local axis, _, a, b = upAxis(part)
			if axis and math.max(a, b) >= least - 1e-3 then
				local function whole(x: number): boolean
					return math.abs(x - math.floor(x + 0.5)) <= 0.02
				end
				if not (whole(a) and whole(b)) then
					table.insert(list, part)
				end
			end
		end
	end
	return list
end

-- Does the Studs face of a studded part point world-up?
function Studs.studsFaceUp(part: any): boolean
	local faces = Studs.studFaces(part)
	if #faces ~= 1 then
		return false
	end
	local axis, sign = upAxis(part)
	return axis ~= nil and faces[1] == FACES[axis :: number][if sign > 0 then 1 else 2]
end

--------------------------------------------------------------------------------
-- Coplanar resolver
--------------------------------------------------------------------------------

-- studs a top moves per fix: 0.06 (v3 fix W3; 0.02 was within z-fight range of a phone's depth
-- buffer at 150+ studs), still too small to see as a step
Studs.RAISE = 0.06
Studs.COPLANAR_EPS = 0.05 -- two tops closer than this are coplanar (z-fight range: v3 fix W3)
Studs.OVERLAP_MARGIN = 0.05 -- faces must overlap by more than this (touching edges do not count)
Studs.MAX_PASSES = 8 -- (the map needs 7 with the wider z-fight range of W3)
local CELL = 16 -- XZ grid of the pair search (studs)

-- Decor-only attributes: they do not protect a part from the RAISE move.
local DECOR_ATTR = {
	Accent = true,
	AccentShade = true,
	WallTone = true,
	Studs = true,
	Bob = true,
	BobPeriod = true,
	Spin = true,
}
-- Parts the server code finds by name (DESIGN.md §2 "Names the server code relies on").
local PROTECTED_NAME = {
	Root = true,
	SpawnPad = true,
	FishingSpot = true,
	Pedestal = true,
	Display = true,
	Glass = true,
	Lamp = true,
}

local function isProtected(part: any): boolean
	if part.ClassName == "SpawnLocation" or PROTECTED_NAME[part.Name] or #part:GetTags() > 0 then
		return true
	end
	for name in part:GetAttributes() do
		if not DECOR_ATTR[name] then
			return true
		end
	end
	return false
end

-- Up-face record of an opaque block part with an axis pointing up (nil otherwise).
local function faceOf(part: any): any
	if
		not (part.ClassName == "Part" or part.ClassName == "SpawnLocation")
		or part.Shape ~= Enum.PartType.Block
		or part.Transparency >= 0.05
	then
		return nil
	end
	local axis, sign = upAxis(part)
	if not axis then
		return nil
	end
	local cf, size = part.CFrame, part.Size
	local vecs = { cf.RightVector, cf.UpVector, -cf.LookVector }
	local dims = { size.X, size.Y, size.Z }
	local ia, ib = axis % 3 + 1, (axis + 1) % 3 + 1
	local uDir, vDir = vecs[ia], vecs[ib]
	local pos = cf.Position
	local accentShade = part:GetAttribute("AccentShade")
	return {
		part = part,
		top = pos.Y + dims[axis] / 2,
		top0 = pos.Y + dims[axis] / 2, -- before any move
		cx = pos.X,
		cz = pos.Z,
		ax = { { uDir.X, uDir.Z }, { vDir.X, vDir.Z } },
		ext = { dims[ia] / 2, dims[ib] / 2 },
		uDir = uDir,
		vDir = vDir,
		uo = -uDir:Dot(pos) + dims[ia] / 2,
		vo = -vDir:Dot(pos) + dims[ib] / 2,
		area = dims[ia] * dims[ib],
		thick = dims[axis],
		axis = axis,
		studs = Studs.isStudded(part),
		dir = 0, -- +1 / -1 once the top was moved up / down
		-- Accent parts are painted at runtime: same colour only with the same shade.
		colour = if part:GetAttribute("Accent") == true then `accent:{accentShade or 0}` else part.Color:ToHex(),
		protected = isProtected(part),
	}
end

-- Separating-axis test of two face rectangles in XZ.
local function overlap(a: any, b: any): boolean
	local dx, dz = b.cx - a.cx, b.cz - a.cz
	for _, n in { a.ax[1], a.ax[2], b.ax[1], b.ax[2] } do
		local ra = a.ext[1] * math.abs(n[1] * a.ax[1][1] + n[2] * a.ax[1][2])
			+ a.ext[2] * math.abs(n[1] * a.ax[2][1] + n[2] * a.ax[2][2])
		local rb = b.ext[1] * math.abs(n[1] * b.ax[1][1] + n[2] * b.ax[1][2])
			+ b.ext[2] * math.abs(n[1] * b.ax[2][1] + n[2] * b.ax[2][2])
		if math.abs(n[1] * dx + n[2] * dz) >= ra + rb - Studs.OVERLAP_MARGIN then
			return false
		end
	end
	return true
end

local function frac(x: number): number
	return x - math.floor(x)
end
-- Same stud-cell fraction (mod 1), also when one grid runs the other way.
local function nearFrac(x: number, y: number): boolean
	local d = math.abs(x - y)
	local e = math.abs(x - (1 - y))
	return math.min(d, 1 - d) < 0.05 or math.min(e, 1 - e) < 0.05
end
-- Do the stud grids of two faces line up (checked at three points near the pair's middle,
-- axes may be swapped or flipped)?
local function inPhase(a: any, b: any): boolean
	local cx, cz = (a.cx + b.cx) / 2, (a.cz + b.cz) / 2
	for _, o in { { 0, 0 }, { 0.37, 0.21 }, { -0.29, 0.43 } } do
		local q = Vector3.new(cx + o[1], a.top, cz + o[2])
		local a1, a2 = frac(a.uDir:Dot(q) + a.uo), frac(a.vDir:Dot(q) + a.vo)
		local b1, b2 = frac(b.uDir:Dot(q) + b.uo), frac(b.vDir:Dot(q) + b.vo)
		if not ((nearFrac(a1, b1) and nearFrac(a2, b2)) or (nearFrac(a1, b2) and nearFrac(a2, b1))) then
			return false
		end
	end
	return true
end

-- Does this pair shimmer? (overlapping, at least one studded, not two identical aligned grids)
local function conflicting(a: any, b: any): boolean
	if not (a.studs or b.studs) or math.abs(a.top - b.top) >= Studs.COPLANAR_EPS or not overlap(a, b) then
		return false
	end
	return not (a.studs and b.studs and a.colour == b.colour and inPhase(a, b))
end

local function collect(roots: { any }): { any }
	local faces = {}
	for _, root in roots do
		for _, part in root:GetDescendants() do
			if part:IsA("BasePart") then
				local face = faceOf(part)
				if face then
					table.insert(faces, face)
				end
			end
		end
	end
	return faces
end

local function keyOf(top: number): number
	return math.floor(top / Studs.COPLANAR_EPS + 0.5)
end

-- Height buckets -> XZ grid cells -> face indices.
local function index(faces: { any }): { [number]: { [string]: { number } } }
	local buckets = {}
	for i, f in faces do
		local key = keyOf(f.top)
		local grid = buckets[key]
		if not grid then
			grid = {}
			buckets[key] = grid
		end
		local r = math.abs(f.ext[1]) + math.abs(f.ext[2])
		for gx = math.floor((f.cx - r) / CELL), math.floor((f.cx + r) / CELL) do
			for gz = math.floor((f.cz - r) / CELL), math.floor((f.cz + r) / CELL) do
				local cellKey = gx .. ":" .. gz
				local cell = grid[cellKey]
				if not cell then
					cell = {}
					grid[cellKey] = cell
				end
				table.insert(cell, i)
			end
		end
	end
	return buckets
end

-- Calls fn(j) for every face index j in the height buckets within `window` of f's and in the
-- grid cells f's rectangle touches (j may repeat and may be f itself).
local function near(f: any, buckets: any, window: number, fn: (number) -> ())
	local key = keyOf(f.top)
	local r = math.abs(f.ext[1]) + math.abs(f.ext[2])
	local gx0, gx1 = math.floor((f.cx - r) / CELL), math.floor((f.cx + r) / CELL)
	local gz0, gz1 = math.floor((f.cz - r) / CELL), math.floor((f.cz + r) / CELL)
	for k = key - window, key + window do
		local grid = buckets[k]
		if grid then
			for gx = gx0, gx1 do
				for gz = gz0, gz1 do
					local cell = grid[gx .. ":" .. gz]
					if cell then
						for _, j in cell do
							fn(j)
						end
					end
				end
			end
		end
	end
end

-- Every conflicting pair { i, j } (i < j) that involves a face in `only` (nil = all faces).
local function pairs_(faces: { any }, buckets: any, only: { [number]: boolean }?): { { number } }
	local found, seen = {}, {}
	local function consider(i: number, j: number)
		if i == j then
			return
		end
		if i > j then
			i, j = j, i
		end
		local pk = i * 1048576 + j
		if seen[pk] then
			return
		end
		seen[pk] = true
		if conflicting(faces[i], faces[j]) then
			table.insert(found, { i, j })
		end
	end
	local function scan(i: number)
		near(faces[i], buckets, 1, function(j)
			consider(i, j)
		end)
	end
	if only then
		for i in only do
			scan(i)
		end
	else
		for i, f in faces do
			if f.studs then -- every conflicting pair has a studded face
				scan(i)
			end
		end
	end
	table.sort(found, function(p, q)
		return if p[1] ~= q[1] then p[1] < q[1] else p[2] < q[2]
	end)
	return found
end

local AXES = { Vector3.new(1, 0, 0), Vector3.new(0, 1, 0), Vector3.new(0, 0, 1) }

-- Moves the top of a face by dy (the part grows / shrinks; its bottom stays).
local function shift(f: any, dy: number)
	local part = f.part
	part.Size += AXES[f.axis] * dy
	part.CFrame = part.CFrame + Vector3.new(0, dy / 2, 0)
	f.top += dy
	f.thick += dy
	f.dir = if dy > 0 then 1 else -1
end

-- May the top of face i move by dy? Never onto or past an overlapping face that was above
-- (or below) it before any move: a fix must not change which of two layers shows. `buckets`
-- may be up to one move old (every face moves at most once per pass).
local function canShift(faces: { any }, buckets: any, i: number, dy: number): boolean
	local f = faces[i]
	-- a face keeps moving the way it first moved (no ping-pong between two of its neighbours)
	if f.protected or (dy < 0 and f.thick + dy < 0.05) or f.dir * dy < 0 then
		return false
	end
	local eps = Studs.COPLANAR_EPS
	local newTop = f.top + dy
	local ok = true
	near(f, buckets, math.ceil(2 * math.abs(dy) / eps) + 2, function(j)
		local g = faces[j]
		if not ok or j == i then
			return
		end
		local blocked = (g.top0 > f.top0 + eps and newTop > g.top - eps)
			or (g.top0 < f.top0 - eps and newTop < g.top + eps)
		if blocked and overlap(f, g) then
			ok = false
		end
	end)
	return ok
end

-- Overlapping faces whose height order the fixes flipped (a lower layer now level with or above
-- an upper one). canShift prevents it; the self-check and tests want 0.
local function inversions(faces: { any }, buckets: any): { { any } }
	local list, seen = {}, {}
	local eps = Studs.COPLANAR_EPS
	local window = math.ceil(Studs.RAISE * Studs.MAX_PASSES / eps) + 1
	for i, f in faces do
		if f.top ~= f.top0 then
			near(f, buckets, window, function(j)
				local g = faces[j]
				local pk = math.min(i, j) * 1048576 + math.max(i, j)
				if j == i or seen[pk] then
					return
				end
				seen[pk] = true
				local before = if f.top0 < g.top0 - eps then -1 elseif f.top0 > g.top0 + eps then 1 else 0
				local after = if f.top < g.top - eps then -1 elseif f.top > g.top + eps then 1 else 0
				if before ~= 0 and after ~= before and overlap(f, g) then
					table.insert(list, { f.part, g.part })
				end
			end)
		end
	end
	return list
end

-- Last resort for a pair no move can fix (e.g. three pieces of one paving disc squeezed between
-- the layers below and above): its studded parts become flat SmoothPlastic tiles.
local function flatten(f: any)
	local part = f.part
	part.Material = Enum.Material.SmoothPlastic
	for _, face in ALL_FACES do
		part[face] = Enum.SurfaceType.Smooth
	end
	f.studs = false
end

-- One round of passes: per conflicting pair, the first allowed of: the smaller face up RAISE,
-- the smaller face down RAISE, the bigger face up, the bigger face down (ties: the later part
-- counts as smaller). Returns the pairs left and the faces to re-test.
local function movePasses(faces: { any }, total: any, dirty: { [number]: boolean }?, maxPasses: number): { { number } }
	for _ = 1, maxPasses do
		local buckets = index(faces)
		local found = pairs_(faces, buckets, dirty)
		total.passes += 1
		local moved: { [number]: boolean } = {}
		local movedNow = 0
		for _, pair in found do
			local i, j = pair[1], pair[2]
			if moved[i] or moved[j] then
				continue -- one of them already moved in this pass: re-tested in the next one
			end
			local a, b = faces[i], faces[j]
			local small, big = i, j
			if b.area < a.area or (b.area == a.area and j > i) then
				small, big = j, i
			end
			for _, move in { { small, 1 }, { small, -1 }, { big, 1 }, { big, -1 } } do
				local dy = move[2] * Studs.RAISE
				if canShift(faces, buckets, move[1], dy) then
					shift(faces[move[1]], dy)
					moved[move[1]] = true
					movedNow += 1
					if dy > 0 then
						total.raised += 1
					else
						total.lowered += 1
					end
					break
				end
			end
		end
		if movedNow == 0 then
			return found
		end
		-- Every pair that can still conflict involves a face moved in this pass (a skipped pair
		-- had one) or one that could not move: re-test only those faces.
		dirty = moved
		for _, pair in found do
			if not (moved[pair[1]] or moved[pair[2]]) then
				moved[pair[1]] = true
				moved[pair[2]] = true
			end
		end
	end
	return pairs_(faces, index(faces), dirty)
end

-- Fixes every stud/stud (out of phase or different colour) and stud/flat coplanar overlap:
-- moves tops by RAISE (movePasses; protected parts never move, nothing moves onto or past
-- another layer, a face keeps its direction), and flattens the studded parts of pairs no move
-- can fix. Returns { raised, lowered, flattened, passes, left (pairs still there: 0 unless
-- maxPasses ran out), inverted (should be 0) } and the flipped pairs of parts.
function Studs.resolveCoplanar(roots: { any }, maxPasses: number?): ({ [string]: number }, { { any } })
	local faces = collect(roots)
	local total = { raised = 0, lowered = 0, flattened = 0, passes = 0, left = 0 }
	local passes = maxPasses or Studs.MAX_PASSES
	local left = movePasses(faces, total, nil, passes)
	for _ = 1, 3 do
		if #left == 0 then
			break
		end
		-- Flatten the whole piece: every studded face of the same colour that overlaps it and
		-- was coplanar with it before any move (a paving disc of three boxes stays one tile).
		local dirty = {}
		local buckets = index(faces)
		local stack = {}
		for _, pair in left do
			for _, i in pair do
				table.insert(stack, i)
			end
		end
		while #stack > 0 do
			local i = table.remove(stack)
			if dirty[i] then
				continue
			end
			dirty[i] = true
			local f = faces[i]
			if not f.studs then
				continue
			end
			flatten(f)
			total.flattened += 1
			near(f, buckets, math.ceil(Studs.RAISE * Studs.MAX_PASSES / Studs.COPLANAR_EPS) + 1, function(j)
				local g = faces[j]
				if
					not dirty[j]
					and g.studs
					and g.colour == f.colour
					and math.abs(g.top0 - f.top0) < Studs.COPLANAR_EPS
					and overlap(f, g)
				then
					table.insert(stack, j)
				end
			end)
		end
		left = movePasses(faces, total, dirty, passes)
	end
	total.left = #left
	local flipped = inversions(faces, index(faces))
	total.inverted = #flipped
	return total, flipped
end

-- Conflicting coplanar pairs left under roots (0 after resolveCoplanar): the count and the
-- pairs of parts.
function Studs.coplanarPairs(roots: { any }): (number, { { any } })
	local faces = collect(roots)
	local list = {}
	for _, pair in pairs_(faces, index(faces), nil) do
		table.insert(list, { faces[pair[1]].part, faces[pair[2]].part })
	end
	return #list, list
end

return Studs
