--[[
	Builds ServerStorage.BaseTemplate — one player base. BaseService clones it into the
	8 slots at runtime and paints every part with attribute Accent = true in the base colour.

	Local frame (Root at the origin = shore line, ground top):
	  y = 0      ground top (MapConfig.GroundTop in world space)
	  -Z         towards the lake centre (pier direction)
	  +Z         inland (spawn pad, fence)
	  +X / -X    right / left when facing the lake

	Names below are referenced by server code (BaseService.createBase) — keep them in sync:
	  Root, SpawnPad, FishingSpot, Tank.Glass.PromptAttachment, Alarm.Lamp, Dog,
	  Flag.Pole.SignAttachment.OwnerSign.{OwnerLabel, BaseLabel}
]]

local U = require("./Util")

local Vector3 = U.Vector3
local CFrame = U.CFrame
local Enum = U.Enum
local UDim2 = U.UDim2
local rgb = U.rgb

local ACCENT_DEFAULT = rgb(200, 200, 200) -- replaced by the base colour at runtime
local ACCENT = { Attributes = { Accent = true } }

local C = {
	wood = rgb(166, 118, 72),
	woodDark = rgb(102, 70, 44),
	post = rgb(92, 64, 40),
	glass = rgb(175, 228, 248),
	metal = rgb(205, 205, 212),
	stone = rgb(150, 150, 155),
	gold = rgb(240, 200, 60),
	lampOff = rgb(110, 25, 25),
	lampGlow = rgb(255, 205, 120),
	dog = rgb(196, 196, 206),
	dogDark = rgb(112, 112, 124),
	white = rgb(242, 242, 242),
	black = rgb(22, 22, 22),
}

local function withAccent(extra: { [string]: any }?): { [string]: any }
	local props = { Attributes = { Accent = true } }
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	return props
end

local function noCollide(extra: { [string]: any }?): { [string]: any }
	local props: { [string]: any } = { CanCollide = false }
	if extra then
		for key, value in extra do
			props[key] = value
		end
	end
	return props
end

local function buildPier(template: any, lakeBottomLocal: number)
	local pier = U.model(template, "Pier")
	local deckTop = 0.6

	U.part(pier, "Deck", Vector3.new(8, 1, 30), CFrame.new(0, deckTop - 0.5, -9), C.wood, Enum.Material.WoodPlanks)
	U.part(
		pier,
		"Platform",
		Vector3.new(16, 1, 14),
		CFrame.new(0, deckTop - 0.5, -31),
		C.wood,
		Enum.Material.WoodPlanks
	)

	-- Low coloured curbs along the deck and around the platform.
	U.part(
		pier,
		"CurbLeft",
		Vector3.new(0.6, 0.5, 30),
		CFrame.new(-3.7, deckTop + 0.25, -9),
		ACCENT_DEFAULT,
		nil,
		ACCENT
	)
	U.part(
		pier,
		"CurbRight",
		Vector3.new(0.6, 0.5, 30),
		CFrame.new(3.7, deckTop + 0.25, -9),
		ACCENT_DEFAULT,
		nil,
		ACCENT
	)
	U.part(
		pier,
		"CurbFront",
		Vector3.new(16, 0.5, 0.6),
		CFrame.new(0, deckTop + 0.25, -37.7),
		ACCENT_DEFAULT,
		nil,
		ACCENT
	)
	U.part(
		pier,
		"CurbPlatformLeft",
		Vector3.new(0.6, 0.5, 13.4),
		CFrame.new(-7.7, deckTop + 0.25, -31),
		ACCENT_DEFAULT,
		nil,
		ACCENT
	)
	U.part(
		pier,
		"CurbPlatformRight",
		Vector3.new(0.6, 0.5, 13.4),
		CFrame.new(7.7, deckTop + 0.25, -31),
		ACCENT_DEFAULT,
		nil,
		ACCENT
	)

	-- Support piles down to the lake bed.
	local postBottom = lakeBottomLocal
	local postTop = deckTop - 1
	local postH = postTop - postBottom
	local postY = (postTop + postBottom) / 2
	for _, p in
		{
			{ -3.6, -8 },
			{ 3.6, -8 },
			{ -3.6, -18 },
			{ 3.6, -18 },
			{ -7.4, -25 },
			{ 7.4, -25 },
			{ -7.4, -37 },
			{ 7.4, -37 },
		}
	do
		U.part(
			pier,
			"Pile",
			Vector3.new(0.9, postH, 0.9),
			CFrame.new(p[1], postY, p[2]),
			C.post,
			Enum.Material.Wood,
			{ CastShadow = false }
		)
	end

	-- Where the owner stands to fish (stage 2 checks the distance to this part).
	U.part(
		template,
		"FishingSpot",
		Vector3.new(3, 0.12, 3),
		CFrame.new(-4, deckTop + 0.06, -34.5),
		ACCENT_DEFAULT,
		Enum.Material.Fabric,
		withAccent({ CastShadow = false })
	)

	-- Lanterns at the pier entrance.
	local lanterns = U.model(template, "Lanterns")
	for _, x in { -4.8, 4.8 } do
		U.part(
			lanterns,
			"Post",
			Vector3.new(0.5, 4, 0.5),
			CFrame.new(x, 2, 6.6),
			C.woodDark,
			Enum.Material.Wood,
			{ CastShadow = false }
		)
		U.part(
			lanterns,
			"Light",
			Vector3.new(1, 1, 1),
			CFrame.new(x, 4.5, 6.6),
			C.lampGlow,
			Enum.Material.Neon,
			{ CastShadow = false }
		)
	end
end

local function buildTank(template: any)
	local tank = U.model(template, "Tank")
	local cx, cz = 3.5, -31
	local bottom = 0.6 -- platform top

	U.part(
		tank,
		"Stand",
		Vector3.new(7.6, 0.8, 7.6),
		CFrame.new(cx, bottom + 0.4, cz),
		C.woodDark,
		Enum.Material.WoodPlanks
	)
	local glass = U.part(
		tank,
		"Glass",
		Vector3.new(7, 5, 7),
		CFrame.new(cx, bottom + 0.8 + 2.5, cz),
		C.glass,
		Enum.Material.Glass,
		{
			Transparency = 0.5,
			CastShadow = false,
		}
	)
	-- Stage 3/4: tank / steal ProximityPrompts live here, on the side facing the pier deck.
	U.new("Attachment", { Name = "PromptAttachment", CFrame = CFrame.new(0, -1, 3.9) }, glass)
	for _, p in { { -3.5, -3.5 }, { 3.5, -3.5 }, { -3.5, 3.5 }, { 3.5, 3.5 } } do
		U.part(
			tank,
			"Frame",
			Vector3.new(0.6, 5.4, 0.6),
			CFrame.new(cx + p[1], bottom + 0.8 + 2.7, cz + p[2]),
			C.post,
			Enum.Material.Wood,
			{ CastShadow = false }
		)
	end
	tank.PrimaryPart = glass

	-- Alarm lamp on a post at the platform corner (stage 4 makes it blink).
	local alarm = U.model(template, "Alarm")
	U.part(
		alarm,
		"Post",
		Vector3.new(0.6, 6, 0.6),
		CFrame.new(7.4, bottom + 3, -25),
		C.metal,
		Enum.Material.Metal,
		{ CastShadow = false }
	)
	U.part(
		alarm,
		"Lamp",
		Vector3.new(1.4, 1.4, 1.4),
		CFrame.new(7.4, bottom + 6.7, -25),
		C.lampOff,
		Enum.Material.SmoothPlastic,
		{ CastShadow = false }
	)
end

local function buildDogHouse(template: any)
	local house = U.model(template, "DogHouse")
	local cx, cz = 11, 12
	-- Walls from y = -0.5 (sunk into the ground) up to 4.4, where the roof panels rest.
	local wallTop = 4.4
	local wallH = wallTop + 0.5
	local wallY = wallTop - wallH / 2

	U.part(
		house,
		"WallBack",
		Vector3.new(6, wallH, 0.6),
		CFrame.new(cx, wallY, cz + 2.7),
		C.wood,
		Enum.Material.WoodPlanks
	)
	U.part(
		house,
		"WallLeft",
		Vector3.new(0.6, wallH, 6),
		CFrame.new(cx - 2.7, wallY, cz),
		C.wood,
		Enum.Material.WoodPlanks
	)
	U.part(
		house,
		"WallRight",
		Vector3.new(0.6, wallH, 6),
		CFrame.new(cx + 2.7, wallY, cz),
		C.wood,
		Enum.Material.WoodPlanks
	)
	U.part(
		house,
		"FrontLeft",
		Vector3.new(1.8, wallH, 0.6),
		CFrame.new(cx - 2.1, wallY, cz - 2.7),
		C.wood,
		Enum.Material.WoodPlanks
	)
	U.part(
		house,
		"FrontRight",
		Vector3.new(1.8, wallH, 0.6),
		CFrame.new(cx + 2.1, wallY, cz - 2.7),
		C.wood,
		Enum.Material.WoodPlanks
	)
	U.part(
		house,
		"Lintel",
		Vector3.new(2.4, wallTop - 2.7, 0.6),
		CFrame.new(cx, (2.7 + wallTop) / 2, cz - 2.7),
		C.wood,
		Enum.Material.WoodPlanks
	)
	U.part(
		house,
		"RoofLeft",
		Vector3.new(4.4, 0.5, 7.2),
		CFrame.new(cx - 1.8, 5.3, cz) * CFrame.Angles(0, 0, math.rad(35)),
		ACCENT_DEFAULT,
		nil,
		ACCENT
	)
	U.part(
		house,
		"RoofRight",
		Vector3.new(4.4, 0.5, 7.2),
		CFrame.new(cx + 1.8, 5.3, cz) * CFrame.Angles(0, 0, math.rad(-35)),
		ACCENT_DEFAULT,
		nil,
		ACCENT
	)
	-- Triangular gables (front and back) under the roof: two wedges each, tall side at the ridge.
	local gableH = 1.9
	for _, z in { cz - 2.7, cz + 2.7 } do
		for _, side in { -1, 1 } do
			U.wedge(
				house,
				"Gable",
				Vector3.new(0.6, gableH, 2.7),
				CFrame.new(cx + side * 1.35, wallTop + gableH / 2, z) * CFrame.Angles(0, math.rad(-90 * side), 0),
				C.wood,
				Enum.Material.WoodPlanks
			)
		end
	end
end

-- Blocky husky sitting in front of the dog house, facing the pier (-Z).
local function buildDog(template: any)
	local dog = U.model(template, "Dog")
	local x = 11
	local function piece(name: string, size: any, cf: any, color: any, extra: { [string]: any }?)
		return U.part(dog, name, size, cf, color, nil, noCollide(extra))
	end
	local body = piece("Body", Vector3.new(1.6, 1.4, 2.8), CFrame.new(x, 1.6, 6.2), C.dog)
	piece("Head", Vector3.new(1.4, 1.3, 1.3), CFrame.new(x, 2.6, 4.4), C.dog)
	piece("Snout", Vector3.new(0.8, 0.6, 0.7), CFrame.new(x, 2.35, 3.5), C.white, { CastShadow = false })
	piece("Nose", Vector3.new(0.3, 0.25, 0.15), CFrame.new(x, 2.55, 3.12), C.black, { CastShadow = false })
	piece("EarLeft", Vector3.new(0.4, 0.6, 0.3), CFrame.new(x - 0.4, 3.5, 4.5), C.dogDark, { CastShadow = false })
	piece("EarRight", Vector3.new(0.4, 0.6, 0.3), CFrame.new(x + 0.4, 3.5, 4.5), C.dogDark, { CastShadow = false })
	piece("EyeLeft", Vector3.new(0.22, 0.22, 0.1), CFrame.new(x - 0.3, 2.85, 3.72), C.black, { CastShadow = false })
	piece("EyeRight", Vector3.new(0.22, 0.22, 0.1), CFrame.new(x + 0.3, 2.85, 3.72), C.black, { CastShadow = false })
	for _, p in { { -0.45, 5.2 }, { 0.45, 5.2 }, { -0.45, 7.2 }, { 0.45, 7.2 } } do
		piece("Leg", Vector3.new(0.45, 0.9, 0.45), CFrame.new(x + p[1], 0.45, p[2]), C.dog, { CastShadow = false })
	end
	piece(
		"Tail",
		Vector3.new(0.35, 0.35, 1.2),
		CFrame.new(x, 2.5, 7.95) * CFrame.Angles(math.rad(-40), 0, 0),
		C.dogDark,
		{ CastShadow = false }
	)
	U.part(
		dog,
		"Collar",
		Vector3.new(1.55, 0.3, 0.6),
		CFrame.new(x, 2.05, 5.0),
		ACCENT_DEFAULT,
		nil,
		withAccent({ CanCollide = false, CastShadow = false })
	)
	dog.PrimaryPart = body
end

local function buildFlag(template: any)
	local flag = U.model(template, "Flag")
	local fx, fz = -11, 11
	U.part(flag, "Base", Vector3.new(1.6, 0.6, 1.6), CFrame.new(fx, 0.3, fz), C.stone, Enum.Material.Slate)
	local pole = U.part(flag, "Pole", Vector3.new(0.5, 15, 0.5), CFrame.new(fx, 7.5, fz), C.metal, Enum.Material.Metal)
	U.part(
		flag,
		"Cloth",
		Vector3.new(5, 3, 0.2),
		CFrame.new(fx - 2.75, 13.2, fz),
		ACCENT_DEFAULT,
		Enum.Material.Fabric,
		withAccent({ CanCollide = false })
	)
	U.part(
		flag,
		"Top",
		Vector3.new(0.8, 0.8, 0.8),
		CFrame.new(fx, 15.3, fz),
		C.gold,
		Enum.Material.SmoothPlastic,
		{ Shape = Enum.PartType.Ball, CastShadow = false }
	)

	-- Owner sign above the flag (BaseService writes the owner name / base name).
	local attachment = U.new("Attachment", { Name = "SignAttachment", CFrame = CFrame.new(0, 9.6, 0) }, pole)
	local sign = U.new("BillboardGui", {
		Name = "OwnerSign",
		Size = UDim2.new(14, 0, 4, 0), -- studs
		LightInfluence = 0,
		MaxDistance = 170,
		AlwaysOnTop = false,
	}, attachment)
	local font = U.FONT
	U.new("TextLabel", {
		Name = "OwnerLabel",
		Size = UDim2.fromScale(1, 0.58),
		BackgroundTransparency = 1,
		Text = "Свободно",
		TextScaled = true,
		FontFace = font,
		TextColor3 = C.white,
		TextStrokeColor3 = C.black,
		TextStrokeTransparency = 0.35,
	}, sign)
	U.new("TextLabel", {
		Name = "BaseLabel",
		Position = UDim2.fromScale(0, 0.6),
		Size = UDim2.fromScale(1, 0.4),
		BackgroundTransparency = 1,
		Text = "База",
		TextScaled = true,
		FontFace = font,
		TextColor3 = C.white,
		TextStrokeColor3 = C.black,
		TextStrokeTransparency = 0.35,
	}, sign)
end

local function buildYard(template: any)
	-- Spawn pad (players appear here; BaseService pivots the character on top of it).
	U.part(
		template,
		"SpawnPad",
		Vector3.new(8, 0.4, 8),
		CFrame.new(0, 0.2, 24),
		ACCENT_DEFAULT,
		Enum.Material.SmoothPlastic,
		withAccent({ CastShadow = false })
	)

	-- Side fences.
	local fence = U.model(template, "Fence")
	for _, x in { -20, 20 } do
		U.part(
			fence,
			"Rail",
			Vector3.new(0.4, 0.4, 30),
			CFrame.new(x, 1.6, 19),
			C.wood,
			Enum.Material.Wood,
			{ CastShadow = false }
		)
		for _, z in { 4, 19, 34 } do
			U.part(
				fence,
				"Post",
				Vector3.new(0.6, 2.4, 0.6),
				CFrame.new(x, 1.0, z),
				C.woodDark,
				Enum.Material.Wood,
				{ CastShadow = false }
			)
		end
	end

	local props = U.model(template, "Props")
	U.part(
		props,
		"Crate",
		Vector3.new(2, 2, 2),
		CFrame.new(-6.8, 1, 3.6) * CFrame.Angles(0, math.rad(12), 0),
		C.wood,
		Enum.Material.WoodPlanks
	)
	U.cylinderY(props, "Barrel", 1.8, 2.2, Vector3.new(-7.2, 1.1, 7), C.woodDark, Enum.Material.Wood)
end

return function(game: any, mapCfg: any)
	local serverStorage = game:GetService("ServerStorage")
	local template = U.new("Model", { Name = "BaseTemplate" }, serverStorage)

	local root = U.marker(template, "Root", Vector3.new(2, 0.2, 2), CFrame.new(0, 0, 0))
	template.PrimaryPart = root

	local lakeBottomLocal = mapCfg.LakeBottom - mapCfg.GroundTop
	buildPier(template, lakeBottomLocal)
	buildTank(template)
	buildDogHouse(template)
	buildDog(template)
	buildFlag(template)
	buildYard(template)

	local count = 0
	for _, d in template:GetDescendants() do
		if d:IsA("BasePart") then
			count += 1
		end
	end
	return { template = template, partCount = count }
end
