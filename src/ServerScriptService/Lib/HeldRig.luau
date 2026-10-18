--!strict
--[[
	HeldRig — рыба над головой персонажа (сервер): общий рецепт трофея улова (FishingService,
	модель "HeldFish", Этап 2) и краденой рыбы на голове вора (StealService, модель "StolenFish",
	Этап 4; docs/stage4_design.md §4.8). Копия ReplicatedStorage.Assets.Fish.<Id>.<мутация или
	Normal> крупнее настоящей (heldScale — по редкости FishingConfig.HeldScale и не длиннее
	HeldMaxLength studs; Model:ScaleTo до сварок), над макушкой на HeldFishGap, оси модели — оси
	головы (голова рыбы, +X модели, смотрит вправо от персонажа), не закреплена, без массы,
	столкновений, запросов и касаний, приварена к голове (Weld "HoldWeld" с явным C0) — двигается
	вместе с персонажем; атрибуты для табличек у клиентов: FishId, Rarity, Mutation, Kg, Value,
	Scale (во сколько раз крупнее модели; прыжок рыбы у клиентов растёт до него).

	  HeldRig.Build(character, fish: FishData, name) -> (model, scale)?   -- модель уже в персонаже;
	      nil — нет головы, нет модели рыбы или персонаж не жив (ничего не создано)
	  HeldRig.Scale(fish, model) -> number                                -- то же число отдельно
	Таймеры, кто и когда убирает рыбу, — у вызывающего (FishingService — HoldFishTime,
	StealService — конец кражи). Без ожиданий.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local FishingConfig = require(Shared.Config.FishingConfig)
local FishingRules = require(Shared.FishingRules)

type FishData = FishingRules.FishData

local HeldRig = {}

local function isAlive(character: Model): boolean
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and character.Parent ~= nil
end

local function weld(part0: BasePart, part1: BasePart, c0: CFrame)
	local joint = Instance.new("Weld")
	joint.Name = "HoldWeld"
	joint.Part0 = part0
	joint.Part1 = part1
	joint.C0 = c0
	joint.C1 = CFrame.identity
	joint.Parent = part1
end

local function fishModel(fish: FishData): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local all = assets and assets:FindFirstChild("Fish")
	local variants = all and all:FindFirstChild(fish.Id)
	local model = variants and variants:FindFirstChild(fish.Mutation or "Normal")
	return if model and model:IsA("Model") and model.PrimaryPart then model else nil
end

-- Во сколько раз рыба над головой крупнее модели: по редкости и не длиннее HeldMaxLength studs
-- (так же считает прыжок рыбы у клиентов — FishingFxController heldScale).
function HeldRig.Scale(fish: FishData, model: Model): number
	local scale = FishingConfig.HeldScale[fish.Rarity] or 1
	local _, size = model:GetBoundingBox()
	local length = math.max(size.X, size.Z)
	if length > 0 then
		scale = math.min(scale, FishingConfig.HeldMaxLength / length)
	end
	return math.max(scale, 1)
end

function HeldRig.Build(character: Model, fish: FishData, name: string): (Model?, number?)
	local head = character:FindFirstChild("Head")
	local template = fishModel(fish)
	if not head or not head:IsA("BasePart") or not template or not isAlive(character) then
		return nil, nil
	end
	local model = template:Clone()
	local body = model.PrimaryPart :: BasePart
	model.Name = name
	local scale = HeldRig.Scale(fish, model)
	if scale ~= 1 then
		model:ScaleTo(scale)
	end

	-- Центр рамки рыбы встаёт над макушкой; оси модели совпадают с осями головы.
	local pivot = model:GetPivot()
	local boxCFrame, boxSize = model:GetBoundingBox()
	local center = pivot:PointToObjectSpace(boxCFrame.Position)
	local lift = head.Size.Y / 2 + FishingConfig.HeldFishGap + boxSize.Y / 2
	local modelInHead = CFrame.new(0, lift, 0) * CFrame.new(-center)
	model:PivotTo(head.CFrame * modelInHead)

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Massless = true
			if part ~= body then
				weld(body, part, body.CFrame:ToObjectSpace(part.CFrame))
			end
		end
	end
	weld(head, body, head.CFrame:ToObjectSpace(body.CFrame))
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
	-- Что за рыба — для табличек над ней у клиентов (FishingFxController, TheftWorldController).
	model:SetAttribute("FishId", fish.Id)
	model:SetAttribute("Rarity", fish.Rarity)
	model:SetAttribute("Mutation", fish.Mutation)
	model:SetAttribute("Kg", fish.Kg)
	model:SetAttribute("Value", fish.Value)
	model:SetAttribute("Scale", scale)
	model.Parent = character
	return model, scale
end

return HeldRig
