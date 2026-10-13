--[[
	Builds ReplicatedStorage.Assets — the game's ready-made models (stage 2):

	  Assets.Rods.<RodId>     Tool «<rod name>» (attributes RodId, Tier): the rod from its block spec
	                          (tools/builder/gear/rods); Handle is the grip block, every other block
	                          is welded to it (Weld with explicit C0, unanchored, massless, no
	                          collisions); Handle.TipAttachment is where the fishing line leaves.
	                          Grip: the rod points forward and GRIP_TILT up from the hand.
	                          FishingService clones the player's rod into their Backpack.
	  Assets.Bobbers.<RodId>  Model: the rod's float (anchored, no collisions/queries/touch);
	                          PrimaryPart = Root, an invisible 0.2-stud part at the point where the
	                          line ties on, with Root.LineAttachment. Pivot it to the water: the
	                          waterline sits BOBBER_FLOAT studs below the tie point.
	  Assets.Fish.<FishId>.Normal|Gold|Neon|Rainbow
	                          Model per mutation (attributes Kind, Title, Rarity, Mutation),
	                          PrimaryPart = Body, anchored, no collisions/queries/touch; the spec's
	                          +X (head) is the model's +X. Rainbow models carry the tag
	                          "RainbowFish" and every recoloured part the attributes RainbowU
	                          (0..1 along the fish) and RainbowV (brightness of the base colour):
	                          the client animates the hues (Color3.fromHSV((U * 0.85 + t * speed) % 1,
	                          0.72, 0.55 + 0.45 * V)), see Gear.mutate.

	Ids must match src/ReplicatedStorage/Shared/Config/FishConfig.luau and RodConfig.luau (checked).
	Returns { rods, fish, bobbers, partCount, expectedAttachments }.
]]

local fs = require("@lune/fs")

local U = require("./Util")
local Gear = require("./Gear")

local CFrame = U.CFrame
local Vector3 = U.Vector3

local GRIP_TILT = math.rad(35) -- the rod rises this much above horizontal in the hand
local BOBBER_FLOAT = 0.6 -- studs from the tie point down to the waterline (between the halves)

local Assets = {}
Assets.BOBBER_FLOAT = BOBBER_FLOAT

-- Block specs of one gear folder (pure data modules), keyed by id.
local function loadSpecs(dir: string): { [string]: any }
	local specs = {}
	local names = fs.readDir(dir)
	table.sort(names)
	for _, name in names do
		if string.match(name, "%.luau$") then
			local spec = U.loadPure(`{dir}/{name}`)
			assert(specs[spec.id] == nil, `duplicate gear id {spec.id} in {dir}`)
			specs[spec.id] = spec
		end
	end
	return specs
end

-- Every BasePart below `root`: no collisions, queries, touch or shadows; locked in Studio.
local function quiet(root: any, anchored: boolean)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = anchored
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.CastShadow = false
			d.Locked = true
			if not anchored then
				d.Massless = true
			end
		end
	end
end

-- The rod Tool: parts of the Gear model moved into the Tool, welded to the Handle.
local function buildRodTool(spec: any, rod: any, parent: any, expected: { any }): any
	local temp = Gear.build(spec, nil, CFrame.new())
	local handle = temp.PrimaryPart
	assert(handle and handle.Name == "Handle", `{spec.id}: no Handle block`)
	local tool = U.new("Tool", {
		Name = rod.Name,
		ToolTip = "Нажми, чтобы забросить",
		CanBeDropped = false,
		RequiresHandle = true,
		ManualActivationOnly = false,
		Attributes = { RodId = rod.Id, Tier = rod.Tier },
	}, parent)
	-- Hand frame (RightGripAttachment / RightGrip C0, arm raised in the tool pose): -Z forward,
	-- +Y up, +X to the character's right. The rod runs along the Handle's +X (spec axes), the
	-- reel hangs below (-Y): map Handle +X to forward-up, Handle +Y to up-back, Handle +Z to right.
	local s, c = math.sin(GRIP_TILT), math.cos(GRIP_TILT)
	local handInHandle =
		CFrame.fromMatrix(Vector3.new(0, 0, 0), Vector3.new(0, s, -c), Vector3.new(0, c, s), Vector3.new(1, 0, 0))
	tool.Grip = handInHandle:Inverse()

	local rodModel = U.model(tool, "Rod")
	for _, part in temp:GetChildren() do
		if part:IsA("BasePart") and part ~= handle then
			part.Parent = rodModel
			U.new("Weld", {
				Name = "Weld",
				Part0 = handle,
				Part1 = part,
				C0 = handle.CFrame:Inverse() * part.CFrame,
				C1 = CFrame.new(),
			}, part)
		end
	end
	handle.Parent = tool
	temp:Destroy()
	quiet(tool, false)
	local tip = handle:FindFirstChild("TipAttachment")
	assert(tip, `{spec.id}: no TipAttachment`)
	table.insert(expected, {
		root = "replicated",
		path = { "Assets", "Rods", rod.Id, "Handle", "TipAttachment" },
		offset = tip.CFrame.Position,
	})
	return tool
end

local function buildBobber(spec: any, rodId: string, parent: any, expected: { any }): any
	local model = Gear.buildBobber(spec, parent, CFrame.new())
	model.Name = rodId
	local root = U.part(model, "Root", Vector3.new(0.2, 0.2, 0.2), CFrame.new(), U.rgb(255, 255, 255), nil, {
		Transparency = 1,
	})
	U.new("Attachment", { Name = "LineAttachment", CFrame = CFrame.new() }, root)
	model.PrimaryPart = root
	model:SetAttribute("FloatDepth", BOBBER_FLOAT)
	quiet(model, true)
	table.insert(expected, {
		root = "replicated",
		path = { "Assets", "Bobbers", rodId, "Root", "LineAttachment" },
		offset = Vector3.new(0, 0, 0),
	})
	return model
end

local function buildFishVariants(spec: any, parent: any): any
	local folder = U.folder(parent, spec.id)
	local blocks = Gear.normalise(spec.blocks)
	local x0, x1 = math.huge, -math.huge
	for _, b in blocks do
		x0, x1 = math.min(x0, b.lo[1]), math.max(x1, b.hi[1])
	end
	for _, variant in { "Normal", "Gold", "Neon", "Rainbow" } do
		local mutation = if variant == "Normal" then nil else variant
		local model = Gear.build(spec, folder, CFrame.new(), { mutation = mutation })
		model.Name = variant
		if mutation == "Rainbow" then
			model:AddTag("RainbowFish")
			for _, b in blocks do
				if not b.keep then
					local part = model:FindFirstChild(b.name)
					local _, _, v = b.color:ToHSV()
					part:SetAttribute("RainbowU", ((b.lo[1] + b.hi[1]) / 2 - x0) / math.max(x1 - x0, 1))
					part:SetAttribute("RainbowV", v)
				end
			end
		end
		quiet(model, true)
	end
	return folder
end

return function(game: any, config: { FishConfig: any, RodConfig: any }): any
	local replicated = game:GetService("ReplicatedStorage")
	local assets = U.folder(replicated, "Assets")
	local rodsFolder = U.folder(assets, "Rods")
	local bobbersFolder = U.folder(assets, "Bobbers")
	local fishFolder = U.folder(assets, "Fish")
	local before = U.partCount
	local expected = {}

	local rodSpecs = loadSpecs("tools/builder/gear/rods")
	local fishSpecs = loadSpecs("tools/builder/gear/fish")

	local rods = 0
	for _, rod in config.RodConfig.Rods do
		local spec = rodSpecs[rod.Id]
		assert(spec, `RodConfig: no block spec for rod {rod.Id} in tools/builder/gear/rods`)
		assert(spec.tier == rod.Tier, `RodConfig: {rod.Id} tier {rod.Tier} ≠ spec tier {spec.tier}`)
		local tool = buildRodTool(spec, rod, rodsFolder, expected)
		tool.Name = rod.Id -- the folder is keyed by id; the Backpack copy gets the display name
		tool:SetAttribute("DisplayName", rod.Name)
		buildBobber(spec, rod.Id, bobbersFolder, expected)
		rods += 1
	end
	for id in rodSpecs do
		local found = false
		for _, rod in config.RodConfig.Rods do
			found = found or rod.Id == id
		end
		assert(found, `rod spec {id} is not in RodConfig.Rods`)
	end

	local fish = 0
	for _, def in config.FishConfig.Fish do
		local spec = fishSpecs[def.Id]
		assert(spec, `FishConfig: no block spec for fish {def.Id} in tools/builder/gear/fish`)
		assert(spec.rarity == def.Rarity, `FishConfig: {def.Id} rarity {def.Rarity} ≠ spec rarity {spec.rarity}`)
		buildFishVariants(spec, fishFolder)
		fish += 1
	end
	for id in fishSpecs do
		local found = false
		for _, def in config.FishConfig.Fish do
			found = found or def.Id == id
		end
		assert(found, `fish spec {id} is not in FishConfig.Fish`)
	end

	local partCount = 0
	for _, d in assets:GetDescendants() do
		if d:IsA("BasePart") then
			partCount += 1
		end
	end
	U.partCount = before -- assets are not in the Workspace: keep them out of the map's part stats

	return {
		assets = assets,
		rods = rods,
		fish = fish,
		partCount = partCount,
		expectedAttachments = expected,
	}
end
