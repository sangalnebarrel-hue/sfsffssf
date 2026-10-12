--[[
	Gear — voxel fishing rods and fish built from block specs (tools/builder/gear/).

	A spec is plain data: a list of axis-aligned blocks on a grid of CELL studs (1 cell = 0.25
	studs). Blocks never overlap (so no two faces can z-fight) and all touch each other (no
	floating bits). The same spec drives the concept renders (tools/preview/gear_*.luau/py) and
	the in-game models, so what the concept sheet shows is exactly what the game builds.

	Spec (one module per rod or fish):
		return {
			id = "RodBamboo",          -- unique, PascalCase
			kind = "rod" | "fish",
			title = "Бамбуковая",       -- shown to players
			tier = 1,                   -- rods: upgrade level 1..5
			rarity = "Common",          -- fish: Common | Rare | Epic | Legendary | Mythic
			length = 24,                -- X extent in cells (checked)
			blocks = {
				-- { name, min corner {x, y, z}, size {x, y, z}, "RRGGBB", ru = "рукоять",
				--   [keep = true], [neon = true] }
				{ "Handle", { 0, -1, -1 }, { 6, 2, 2 }, "8B5A2B", ru = "рукоять" },
			},
			tip = { 24, 0.5, 0 },       -- rods: where the fishing line leaves the tip (cells)
			bobber = { blocks = { ... } }, -- rods: the matching float; its origin is where the line ties on
		}

	Axes (cells): +X forward (rod: handle at x = 0, tip at +X; fish: tail at -X, head at +X),
	+Y up, Z across (models are centred on z = 0). Coordinates and sizes are multiples of half a
	cell. Block names are unique per model; a rod's grip block is called "Handle" (the Tool's
	handle), a fish's main block "Body".

	Mutations (fish): every block is recoloured except the ones marked keep = true (eyes, mouth,
	teeth). Gold maps each colour's lightness onto a gold ramp, Neon turns the body into glowing
	Neon of its own hue, Rainbow paints hues along the fish (animated in game, frozen here).
]]

local U = require("./Util")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Color3 = U.Color3
local Enum = U.Enum

local Gear = {}

Gear.CELL = 0.25
Gear.Rarities = { "Common", "Rare", "Epic", "Legendary", "Mythic" }
Gear.Mutations = { "Gold", "Neon", "Rainbow" }
-- Block budgets (mobile): per rod / bobber, and per fish by rarity.
Gear.Limits = {
	rod = 14,
	bobber = 4,
	fish = { Common = 14, Rare = 16, Epic = 16, Legendary = 16, Mythic = 20 },
}

local function hexColor(hex: string): any
	assert(string.match(hex, "^%x%x%x%x%x%x$"), `bad colour "{hex}" (expected RRGGBB)`)
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end
Gear.hexColor = hexColor

-- Normalised block: name, lo/hi corners (cells), colour, flags.
export type Block = {
	name: string,
	lo: { number },
	hi: { number },
	color: any,
	hex: string,
	ru: string?,
	keep: boolean,
	neon: boolean,
}

local function normalise(list: { any }): { Block }
	local out = {}
	for _, b in list do
		local name, pos, size, hex = b[1], b[2], b[3], b[4]
		table.insert(out, {
			name = name,
			lo = { pos[1], pos[2], pos[3] },
			hi = { pos[1] + size[1], pos[2] + size[2], pos[3] + size[3] },
			color = hexColor(hex),
			hex = string.upper(hex),
			ru = b.ru,
			keep = b.keep == true,
			neon = b.neon == true,
		})
	end
	return out
end
Gear.normalise = normalise

--------------------------------------------------------------------------------
-- Validation

local function isHalf(v: number): boolean
	return math.abs(v * 2 - math.round(v * 2)) < 1e-6
end

-- Overlap length of [a0, a1] and [b0, b1] (negative = gap).
local function overlap1(a0: number, a1: number, b0: number, b1: number): number
	return math.min(a1, b1) - math.max(a0, b0)
end

-- Checks one block list; appends problems to errs. Returns the X extent.
local function checkBlocks(label: string, blocks: { Block }, limit: number, errs: { string }): (number, number)
	if #blocks == 0 then
		table.insert(errs, `{label}: no blocks`)
		return 0, 0
	end
	if #blocks > limit then
		table.insert(errs, `{label}: {#blocks} blocks (limit {limit})`)
	end
	local names = {}
	for _, b in blocks do
		if names[b.name] then
			table.insert(errs, `{label}: duplicate block name "{b.name}"`)
		end
		names[b.name] = true
		if type(b.ru) ~= "string" or b.ru == "" then
			table.insert(errs, `{label}.{b.name}: needs a Russian label (ru = "...")`)
		end
		for k = 1, 3 do
			if not (isHalf(b.lo[k]) and isHalf(b.hi[k])) then
				table.insert(errs, `{label}.{b.name}: coordinates must be multiples of 0.5 cell`)
			end
			if b.hi[k] - b.lo[k] <= 0 then
				table.insert(errs, `{label}.{b.name}: size must be positive`)
			end
		end
	end
	-- No two blocks share volume (coplanar overlapping faces would z-fight).
	for i = 1, #blocks do
		for j = i + 1, #blocks do
			local a, b = blocks[i], blocks[j]
			local ox = overlap1(a.lo[1], a.hi[1], b.lo[1], b.hi[1])
			local oy = overlap1(a.lo[2], a.hi[2], b.lo[2], b.hi[2])
			local oz = overlap1(a.lo[3], a.hi[3], b.lo[3], b.hi[3])
			if ox > 1e-6 and oy > 1e-6 and oz > 1e-6 then
				table.insert(errs, `{label}: blocks "{a.name}" and "{b.name}" overlap`)
			end
		end
	end
	-- All blocks form one piece (face contact with a positive area).
	local seen, stack = { [1] = true }, { 1 }
	while #stack > 0 do
		local i = table.remove(stack) :: number
		local a = blocks[i]
		for j, b in blocks do
			if not seen[j] then
				local o = {
					overlap1(a.lo[1], a.hi[1], b.lo[1], b.hi[1]),
					overlap1(a.lo[2], a.hi[2], b.lo[2], b.hi[2]),
					overlap1(a.lo[3], a.hi[3], b.lo[3], b.hi[3]),
				}
				local touching, positive = 0, 0
				for k = 1, 3 do
					if math.abs(o[k]) < 1e-6 then
						touching += 1
					elseif o[k] > 1e-6 then
						positive += 1
					end
				end
				if touching == 1 and positive == 2 then
					seen[j] = true
					table.insert(stack, j)
				end
			end
		end
	end
	for j, b in blocks do
		if not seen[j] then
			table.insert(errs, `{label}: block "{b.name}" does not touch the rest (floating)`)
		end
	end
	local x0, x1 = math.huge, -math.huge
	for _, b in blocks do
		x0, x1 = math.min(x0, b.lo[1]), math.max(x1, b.hi[1])
	end
	return x0, x1
end

-- Returns a list of problems (empty = valid).
function Gear.validate(spec: any): { string }
	local errs = {}
	local label = tostring(spec.id)
	if type(spec.id) ~= "string" or not string.match(spec.id, "^%u%w+$") then
		table.insert(errs, `{label}: id must be PascalCase`)
	end
	if type(spec.title) ~= "string" or spec.title == "" then
		table.insert(errs, `{label}: missing title`)
	end
	local ok, blocks = pcall(normalise, spec.blocks or {})
	if not ok then
		table.insert(errs, `{label}: {blocks}`)
		return errs
	end
	local limit
	if spec.kind == "rod" then
		limit = Gear.Limits.rod
		if type(spec.tier) ~= "number" then
			table.insert(errs, `{label}: rods need a tier`)
		end
	elseif spec.kind == "fish" then
		limit = Gear.Limits.fish[spec.rarity]
		if not limit then
			table.insert(errs, `{label}: unknown rarity {spec.rarity}`)
			limit = 16
		end
	else
		table.insert(errs, `{label}: kind must be "rod" or "fish"`)
		limit = 16
	end
	local x0, x1 = checkBlocks(label, blocks, limit, errs)
	if spec.length and math.abs((x1 - x0) - spec.length) > 1 + 1e-6 then
		table.insert(errs, `{label}: length {x1 - x0} cells (expected {spec.length} ± 1)`)
	end
	local main = if spec.kind == "rod" then "Handle" elseif spec.kind == "fish" then "Body" else nil
	if main then
		local found = false
		for _, b in blocks do
			found = found or b.name == main
		end
		if not found then
			table.insert(errs, `{label}: needs a block named "{main}"`)
		end
	end
	if spec.kind == "rod" then
		if type(spec.tip) ~= "table" then
			table.insert(errs, `{label}: rods need a tip point`)
		end
		if type(spec.bobber) ~= "table" then
			table.insert(errs, `{label}: rods need a bobber`)
		else
			local okB, bobber = pcall(normalise, spec.bobber.blocks or {})
			if okB then
				checkBlocks(label .. ".bobber", bobber, Gear.Limits.bobber, errs)
			else
				table.insert(errs, `{label}.bobber: {bobber}`)
			end
		end
	end
	return errs
end

--------------------------------------------------------------------------------
-- Mutations

local GOLD_RAMP = {
	{ 0.0, Color3.fromRGB(122, 70, 0) },
	{ 0.45, Color3.fromRGB(230, 156, 14) },
	{ 0.75, Color3.fromRGB(255, 208, 36) },
	{ 1.0, Color3.fromRGB(255, 240, 140) },
}

local function lightness(c: any): number
	return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
end

local function ramp(stops: { any }, t: number): any
	t = math.clamp(t, 0, 1)
	for i = 2, #stops do
		local a, b = stops[i - 1], stops[i]
		if t <= b[1] then
			return a[2]:Lerp(b[2], (t - a[1]) / (b[1] - a[1]))
		end
	end
	return stops[#stops][2]
end

-- Colour (and Neon flag) of a block under a mutation. u = position along the fish 0..1.
function Gear.mutate(block: Block, mutation: string?, u: number): (any, boolean)
	if not mutation or block.keep then
		return block.color, block.neon
	end
	local c = block.color
	if mutation == "Gold" then
		-- stretch the lightness so dark stripes stay readable on the gold
		return ramp(GOLD_RAMP, 0.1 + lightness(c) * 0.9), false
	elseif mutation == "Neon" then
		local h, s, v = c:ToHSV()
		return Color3.fromHSV(h, math.clamp(s * 1.1 + 0.15, 0, 1), math.max(v, 0.85)), true
	elseif mutation == "Rainbow" then
		local _, _, v = c:ToHSV()
		return Color3.fromHSV((u * 0.85) % 1, 0.72, 0.55 + 0.45 * v), block.neon
	end
	error(`unknown mutation {mutation}`)
end

--------------------------------------------------------------------------------
-- Building

-- Builds one block list into `model`; origin = the spec's (0, 0, 0) at `cframe`.
local function buildBlocks(model: any, blocks: { Block }, cframe: any, mutation: string?): { [string]: any }
	local cell = Gear.CELL
	local x0, x1 = math.huge, -math.huge
	for _, b in blocks do
		x0, x1 = math.min(x0, b.lo[1]), math.max(x1, b.hi[1])
	end
	local byName = {}
	for _, b in blocks do
		local size = Vector3.new(b.hi[1] - b.lo[1], b.hi[2] - b.lo[2], b.hi[3] - b.lo[3]) * cell
		local centre = Vector3.new(b.lo[1] + b.hi[1], b.lo[2] + b.hi[2], b.lo[3] + b.hi[3]) * (cell / 2)
		local u = ((b.lo[1] + b.hi[1]) / 2 - x0) / math.max(x1 - x0, 1)
		local color, neon = Gear.mutate(b, mutation, u)
		byName[b.name] = U.part(
			model,
			b.name,
			size,
			cframe * CFrame.new(centre),
			color,
			if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic,
			{ CanCollide = false, CanQuery = false, CastShadow = false, Locked = true }
		)
	end
	return byName
end

--[[
	Builds the model of a spec under `parent` at `cframe` (the spec origin).
	opts.mutation: "Gold" | "Neon" | "Rainbow" (fish).
	Rods get PrimaryPart = Handle and a TipAttachment where the line leaves; the bobber is not
	part of the rod model (see Gear.buildBobber). Fish get PrimaryPart = Body.
]]
function Gear.build(spec: any, parent: any, cframe: any, opts: { mutation: string? }?): any
	local errs = Gear.validate(spec)
	assert(#errs == 0, table.concat(errs, "\n"))
	local model = U.model(parent, spec.id)
	model:SetAttribute("Kind", spec.kind)
	model:SetAttribute("Title", spec.title)
	if spec.rarity then
		model:SetAttribute("Rarity", spec.rarity)
	end
	if spec.tier then
		model:SetAttribute("Tier", spec.tier)
	end
	local mutation = opts and opts.mutation
	if mutation then
		model:SetAttribute("Mutation", mutation)
	end
	local parts = buildBlocks(model, normalise(spec.blocks), cframe, mutation)
	local primary = if spec.kind == "rod" then parts.Handle else parts.Body
	model.PrimaryPart = primary
	if spec.kind == "rod" then
		local tip = Vector3.new(spec.tip[1], spec.tip[2], spec.tip[3]) * Gear.CELL
		local worldTip = cframe * CFrame.new(tip)
		U.new("Attachment", { Name = "TipAttachment", CFrame = primary.CFrame:ToObjectSpace(worldTip) }, primary)
	end
	return model
end

-- The rod's bobber as its own model (origin = where the line ties on).
function Gear.buildBobber(spec: any, parent: any, cframe: any): any
	local model = U.model(parent, spec.id .. "Bobber")
	model:SetAttribute("Kind", "bobber")
	local parts = buildBlocks(model, normalise(spec.bobber.blocks), cframe, nil)
	local _, first = next(parts)
	model.PrimaryPart = first
	return model
end

-- Block table for documentation: { name, ru, size {x, y, z} cells, hex, keep, neon }.
function Gear.blockTable(blocks: { any }): { any }
	local rows = {}
	for _, b in normalise(blocks) do
		table.insert(rows, {
			name = b.name,
			ru = b.ru,
			size = { b.hi[1] - b.lo[1], b.hi[2] - b.lo[2], b.hi[3] - b.lo[3] },
			hex = "#" .. b.hex,
			keep = b.keep,
			neon = b.neon,
		})
	end
	return rows
end

return Gear
