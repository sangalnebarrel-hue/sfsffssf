--[[
	gear_export.luau (Lune 0.11) — builds every rod and fish spec of tools/builder/gear/ with
	tools/builder/Gear.luau and writes the parts as JSON for gear_render.py.

	Usage (from the repo root):
		lune run tools/preview/gear_export.luau <out.json> [id ...]

	With ids, only those specs are exported. Every spec is validated first (no overlapping or
	floating blocks, block budgets, lengths); the script prints the problems and exits with code 1
	when any spec is invalid. Exported models: each rod (variant "base") and its bobber (variant
	"bobber"); each fish plain ("base") and with every mutation ("Gold", "Neon", "Rainbow").
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local roblox = require("@lune/roblox")

local U = require("../builder/Util")
local Gear = require("../builder/Gear")

local out = process.args[1] or "gear.json"
local only: { [string]: boolean }? = nil
if #process.args > 1 then
	local set: { [string]: boolean } = {}
	for i = 2, #process.args do
		set[process.args[i]] = true
	end
	only = set
end

local ROOT = "tools/builder/gear"
local specs = {}
for _, sub in { "rods", "fish" } do
	local dir = `{ROOT}/{sub}`
	if fs.isDir(dir) then
		local files = fs.readDir(dir)
		table.sort(files)
		for _, file in files do
			if string.match(file, "%.luau$") then
				local ok, spec = pcall(U.loadPure, `{dir}/{file}`)
				if not ok then
					-- with an id filter, other (maybe half-written) specs do not matter
					print(`{if only then "SKIP" else "ERROR"} {dir}/{file}: {spec}`)
					if not only then
						process.exit(1)
					end
					continue
				end
				spec.file = `{dir}/{file}`
				if not only or only[spec.id] then
					table.insert(specs, spec)
				end
			end
		end
	end
end
-- rods by tier, fish by rarity
local rarityRank = {}
for i, r in Gear.Rarities do
	rarityRank[r] = i
end
table.sort(specs, function(a, b)
	if a.kind ~= b.kind then
		return a.kind == "rod"
	end
	local ka = if a.kind == "rod" then a.tier else rarityRank[a.rarity] or 99
	local kb = if b.kind == "rod" then b.tier else rarityRank[b.rarity] or 99
	if ka ~= kb then
		return ka < kb
	end
	return a.id < b.id
end)

local function round(v: number, digits: number): number
	local m = 10 ^ digits
	return math.round(v * m) / m
end

local function partsOf(model: any): { any }
	local list = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local c = { d.CFrame:GetComponents() }
			for i, v in c do
				c[i] = round(v, 5)
			end
			table.insert(list, {
				name = d.Name,
				shape = "Block",
				cf = c,
				size = { round(d.Size.X, 4), round(d.Size.Y, 4), round(d.Size.Z, 4) },
				color = {
					math.round(d.Color.R * 255),
					math.round(d.Color.G * 255),
					math.round(d.Color.B * 255),
				},
				transparency = d.Transparency,
				material = d.Material.Name,
				kind = "part",
			})
		end
	end
	return list
end

local problems = 0
local models = {}
local holder = roblox.Instance.new("Folder")
for _, spec in specs do
	local errs = Gear.validate(spec)
	if #errs > 0 then
		problems += #errs
		for _, e in errs do
			print(`INVALID {spec.file}: {e}`)
		end
		continue
	end
	local blocks = Gear.normalise(spec.blocks)
	local x0, x1 = math.huge, -math.huge
	for _, b in blocks do
		x0, x1 = math.min(x0, b.lo[1]), math.max(x1, b.hi[1])
	end
	local info = {
		id = spec.id,
		kind = spec.kind,
		title = spec.title,
		tier = spec.tier,
		rarity = spec.rarity,
		blockCount = #blocks,
		length = x1 - x0,
		blocks = Gear.blockTable(spec.blocks),
	}
	local variants = { "base" }
	if spec.kind == "fish" then
		for _, m in Gear.Mutations do
			table.insert(variants, m)
		end
	else
		table.insert(variants, "bobber")
	end
	for _, variant in variants do
		local model
		if variant == "bobber" then
			model = Gear.buildBobber(spec, holder, roblox.CFrame.new())
		else
			model = Gear.build(spec, holder, roblox.CFrame.new(), {
				mutation = if variant == "base" then nil else variant,
			})
		end
		local entry = table.clone(info)
		entry.variant = variant
		entry.parts = partsOf(model)
		if variant == "bobber" then
			entry.blocks = Gear.blockTable(spec.bobber.blocks)
			entry.blockCount = #spec.bobber.blocks
		end
		table.insert(models, entry)
		model:Destroy()
	end
	print(
		`{spec.id} ({spec.title}): {#blocks} blocks, length {x1 - x0} cells`
			.. (if spec.bobber then `, bobber {#spec.bobber.blocks} blocks` else "")
	)
end

fs.writeFile(out, serde.encode("json", { cell = Gear.CELL, models = models }))
print(`wrote {#models} models to {out}`)
if problems > 0 then
	print(`{problems} problem(s) — fix the specs above`)
	process.exit(1)
end
