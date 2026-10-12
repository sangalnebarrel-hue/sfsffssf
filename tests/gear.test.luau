--[[
	Voxel gear specs (tools/builder/gear/, built by tools/builder/Gear.luau): every rod and fish spec
	is valid (no overlapping or floating blocks, block budgets, lengths, labels), the expected
	five rod tiers and six fish exist, and the models build with the right primary parts.

	Run: lune run tools/run_tests.luau gear
]]

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local U = require("../tools/builder/Util")
local Gear = require("../tools/builder/Gear")

local ROOT = "tools/builder/gear"

local function loadSpecs(sub: string): { any }
	local list = {}
	local dir = `{ROOT}/{sub}`
	if not fs.isDir(dir) then
		return list
	end
	for _, file in fs.readDir(dir) do
		if string.match(file, "%.luau$") then
			local spec = U.loadPure(`{dir}/{file}`)
			spec.file = `{dir}/{file}`
			table.insert(list, spec)
		end
	end
	return list
end

local rods = loadSpecs("rods")
local fish = loadSpecs("fish")

local tests = {}

tests["every spec is valid"] = function(t)
	for _, spec in rods do
		local errs = Gear.validate(spec)
		t.eq(#errs, 0, `{spec.file}: {table.concat(errs, "; ")}`)
	end
	for _, spec in fish do
		local errs = Gear.validate(spec)
		t.eq(#errs, 0, `{spec.file}: {table.concat(errs, "; ")}`)
	end
end

tests["five rod tiers and six fish across all rarities"] = function(t)
	local tiers = {}
	for _, spec in rods do
		t.eq(spec.kind, "rod", spec.file)
		tiers[spec.tier] = (tiers[spec.tier] or 0) + 1
	end
	for tier = 1, 5 do
		t.eq(tiers[tier], 1, `exactly one rod of tier {tier}`)
	end
	t.eq(#fish, 6, "six fish")
	local rarities = {}
	for _, spec in fish do
		t.eq(spec.kind, "fish", spec.file)
		rarities[spec.rarity] = true
	end
	for _, rarity in Gear.Rarities do
		t.ok(rarities[rarity], `a {rarity} fish exists`)
	end
end

tests["ids are unique"] = function(t)
	local seen = {}
	for _, list in { rods, fish } do
		for _, spec in list do
			t.ok(not seen[spec.id], `duplicate id {spec.id}`)
			seen[spec.id] = true
		end
	end
end

tests["models build with primary parts, tip attachment and mutations"] = function(t)
	local holder = roblox.Instance.new("Folder")
	for _, spec in rods do
		local model = Gear.build(spec, holder, roblox.CFrame.new())
		t.ok(model.PrimaryPart and model.PrimaryPart.Name == "Handle", `{spec.id} primary part`)
		t.ok(model.PrimaryPart:FindFirstChild("TipAttachment") ~= nil, `{spec.id} tip attachment`)
		local bobber = Gear.buildBobber(spec, holder, roblox.CFrame.new())
		t.ok(#bobber:GetChildren() >= 1, `{spec.id} bobber`)
	end
	for _, spec in fish do
		local plain = Gear.build(spec, holder, roblox.CFrame.new())
		t.ok(plain.PrimaryPart and plain.PrimaryPart.Name == "Body", `{spec.id} primary part`)
		for _, mutation in Gear.Mutations do
			local model = Gear.build(spec, holder, roblox.CFrame.new(), { mutation = mutation })
			t.eq(model:GetAttribute("Mutation"), mutation, `{spec.id} {mutation}`)
			-- kept blocks (eyes, mouth) keep their colour
			for _, b in Gear.normalise(spec.blocks) do
				if b.keep then
					local part = model:FindFirstChild(b.name)
					t.ok(part and part.Color == b.color, `{spec.id} {mutation}: {b.name} keeps its colour`)
				end
			end
		end
	end
end

tests["validator rejects overlap, floating blocks and missing labels"] = function(t)
	local base = {
		id = "TestFish",
		kind = "fish",
		title = "Тест",
		rarity = "Common",
		blocks = {
			{ "Body", { 0, 0, 0 }, { 4, 4, 4 }, "FF9A3C", ru = "тело" },
			{ "Tail", { -2, 1, 1 }, { 2, 2, 2 }, "E07A20", ru = "хвост" },
		},
	}
	t.eq(#Gear.validate(base), 0, "base spec is valid")
	local overlap = table.clone(base)
	overlap.blocks = table.clone(base.blocks)
	table.insert(overlap.blocks, { "Fin", { 3, 1, 1 }, { 2, 2, 2 }, "E07A20", ru = "плавник" })
	t.ok(#Gear.validate(overlap) > 0, "overlap is rejected")
	local floating = table.clone(base)
	floating.blocks = table.clone(base.blocks)
	table.insert(floating.blocks, { "Fin", { 6, 0, 0 }, { 1, 1, 1 }, "E07A20", ru = "плавник" })
	t.ok(#Gear.validate(floating) > 0, "floating block is rejected")
	local unlabelled = table.clone(base)
	unlabelled.blocks = { { "Body", { 0, 0, 0 }, { 4, 4, 4 }, "FF9A3C" } }
	t.ok(#Gear.validate(unlabelled) > 0, "missing ru label is rejected")
end

return tests
