--!strict
--[[
	AmbientController — «живой» мир, только для красоты и только на клиенте:
	  • стайки разноцветных рыб плавают под водой по озеру;
	  • чайки кружат над островом-деревней и машут крыльями;
	  • крутятся лопасти мельницы, колесо обозрения и всё прочее, что строитель карты пометил:
	    любая Model внутри Workspace.Map с числовым атрибутом Spin (градусов в секунду)
	    вращается вокруг оси своей точки опоры (pivot, ось = LookVector). Вложенные модели с
	    атрибутом KeepUpright = true (кабинки колеса) при этом остаются ровными.
	Рыбы и чайки создаются локально (сервер о них не знает), без коллизий и теней. Всё двигается
	через Workspace:BulkMoveTo примерно 30 раз в секунду — дёшево даже для телефонов.
	Количество — в AMBIENT ниже.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MapConfig"))

local AMBIENT = {
	FishCount = 36,
	GullCount = 8,
	UpdateRate = 30, -- раз в секунду
}

local FISH_COLORS = {
	Color3.fromRGB(255, 150, 40),
	Color3.fromRGB(255, 210, 60),
	Color3.fromRGB(80, 170, 255),
	Color3.fromRGB(255, 100, 140),
	Color3.fromRGB(130, 220, 120),
	Color3.fromRGB(190, 120, 255),
}

type Mover = {
	parts: { BasePart },
	offsets: { CFrame },
	update: (self: Mover, t: number) -> CFrame,
	flap: boolean,
	phase: number,
}

-- Ровная часть вращающейся модели (кабинка колеса): где её точка опоры на колесе и как она
-- повёрнута в мире (этот поворот сохраняется).
type Upright = {
	pivot: Vector3, -- точка опоры в системе координат вращающейся модели
	rotation: CFrame, -- исходный поворот в мире
	parts: { BasePart },
	offsets: { CFrame }, -- детали относительно точки опоры
}

type Spinner = {
	model: Model,
	base: CFrame, -- исходная точка опоры (pivot) модели
	speed: number, -- радиан в секунду
	angle: number,
	parts: { BasePart },
	offsets: { CFrame }, -- детали относительно base
	uprights: { Upright },
}

local AmbientController = {}

local function decorPart(parent: Instance, size: Vector3, color: Color3, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		part.Shape = shape
	end
	part.Parent = parent
	return part
end

local function makeFish(folder: Instance, rng: Random): Mover
	local color = FISH_COLORS[rng:NextInteger(1, #FISH_COLORS)]
	local size = rng:NextNumber(0.8, 1.5)
	local body = decorPart(folder, Vector3.new(0.7, 0.8, 1.6) * size, color)
	local tail = decorPart(folder, Vector3.new(0.15, 0.7, 0.6) * size, color:Lerp(Color3.new(1, 1, 1), 0.25))

	-- Swims around the lake (between the island and the shore) at its own radius/speed/depth.
	local radius = rng:NextNumber(MapConfig.HubRadius + 15, MapConfig.LagoonRadius - 25)
	local speed = rng:NextNumber(4, 9) / radius * (if rng:NextNumber() < 0.5 then -1 else 1)
	local depth = rng:NextNumber(1.6, 3.2)
	local start = rng:NextNumber(0, math.pi * 2)
	local wobble = rng:NextNumber(4, 14)

	local mover = {
		parts = { body, tail },
		offsets = { CFrame.identity, CFrame.new(0, 0, 0.95 * size) },
		flap = false,
		phase = rng:NextNumber(0, 10),
	} :: any
	function mover.update(self: Mover, t: number): CFrame
		local a = start + t * speed
		local r = radius + math.sin(t * 0.3 + self.phase) * wobble
		local x, z = math.sin(a) * r, math.cos(a) * r
		local ahead = a + 0.05 * math.sign(speed)
		local nx, nz = math.sin(ahead) * r, math.cos(ahead) * r
		local position = Vector3.new(x, MapConfig.WaterTop - depth, z)
		return CFrame.lookAt(position, Vector3.new(nx, position.Y, nz))
	end
	return mover
end

local function makeGull(folder: Instance, rng: Random): Mover
	local white = Color3.fromRGB(245, 245, 245)
	local body = decorPart(folder, Vector3.new(0.9, 0.8, 2.2), white)
	local left = decorPart(folder, Vector3.new(2.6, 0.15, 0.9), Color3.fromRGB(225, 225, 230))
	local right = decorPart(folder, Vector3.new(2.6, 0.15, 0.9), Color3.fromRGB(225, 225, 230))
	local beak = decorPart(folder, Vector3.new(0.25, 0.25, 0.5), Color3.fromRGB(255, 190, 60))

	local radius = rng:NextNumber(40, MapConfig.HubRadius - 20)
	local height = rng:NextNumber(45, 75)
	local speed = rng:NextNumber(10, 16) / radius
	local start = rng:NextNumber(0, math.pi * 2)

	local mover = {
		parts = { body, left, right, beak },
		offsets = { CFrame.identity, CFrame.new(-1.6, 0.1, 0), CFrame.new(1.6, 0.1, 0), CFrame.new(0, 0, -1.3) },
		flap = true,
		phase = rng:NextNumber(0, 10),
	} :: any
	function mover.update(self: Mover, t: number): CFrame
		local a = start + t * speed
		local position =
			Vector3.new(math.sin(a) * radius, height + math.sin(t * 0.7 + self.phase) * 3, math.cos(a) * radius)
		local ahead = Vector3.new(math.sin(a + 0.05) * radius, position.Y, math.cos(a + 0.05) * radius)
		return CFrame.lookAt(position, ahead) * CFrame.Angles(0, 0, math.rad(-18)) -- banking into the turn
	end
	return mover
end

-- Ближайшая вложенная модель с KeepUpright = true между деталью и вращающейся моделью.
local function uprightAncestor(part: BasePart, root: Model): Model?
	local node = part.Parent
	while node and node ~= root do
		if node:IsA("Model") and node:GetAttribute("KeepUpright") == true then
			return node
		end
		node = node.Parent
	end
	return nil
end

-- Собирает вращающиеся модели карты: все Model с числовым атрибутом Spin.
local function collectSpinners(map: Instance): { Spinner }
	local spinners: { Spinner } = {}
	for _, inst in map:GetDescendants() do
		local spin = inst:GetAttribute("Spin")
		if not inst:IsA("Model") or typeof(spin) ~= "number" or spin == 0 then
			continue
		end
		local model = inst :: Model
		local base = model:GetPivot()
		local spinner: Spinner = {
			model = model,
			base = base,
			speed = math.rad(spin),
			angle = 0,
			parts = {},
			offsets = {},
			uprights = {},
		}
		local groups: { [Model]: Upright } = {}
		local origins: { [Model]: CFrame } = {}
		for _, d in model:GetDescendants() do
			if not d:IsA("BasePart") then
				continue
			end
			local part = d :: BasePart
			local holder = uprightAncestor(part, model)
			if holder then
				local group: Upright? = groups[holder]
				local origin: CFrame? = origins[holder]
				if not group or not origin then
					local pivot = holder:GetPivot()
					origin = pivot
					group = {
						pivot = base:PointToObjectSpace(pivot.Position),
						rotation = pivot.Rotation,
						parts = {},
						offsets = {},
					}
					origins[holder] = pivot
					groups[holder] = group
					table.insert(spinner.uprights, group :: Upright)
				end
				local g = group :: Upright
				table.insert(g.parts, part)
				table.insert(g.offsets, (origin :: CFrame):Inverse() * part.CFrame)
			else
				table.insert(spinner.parts, part)
				table.insert(spinner.offsets, base:Inverse() * part.CFrame)
			end
		end
		table.insert(spinners, spinner)
	end
	return spinners
end

function AmbientController:Start(_hud: ScreenGui)
	local folder = Instance.new("Folder")
	folder.Name = "Ambient (client)"
	folder.Parent = Workspace

	local rng = Random.new(7)
	local movers: { Mover } = {}
	for _ = 1, AMBIENT.FishCount do
		table.insert(movers, makeFish(folder, rng))
	end
	for _ = 1, AMBIENT.GullCount do
		table.insert(movers, makeGull(folder, rng))
	end

	local allParts: { BasePart } = {}
	for _, mover in movers do
		for _, part in mover.parts do
			table.insert(allParts, part)
		end
	end
	local cframes: { CFrame } = table.create(#allParts, CFrame.identity)

	-- Вращающиеся модели карты (мельница, колесо обозрения …). Карта уже лежит в месте
	-- (StreamingEnabled выключен) — коротко ждём её, не задерживая остальные контроллеры.
	local spinners: { Spinner } = {}
	local spinParts: { BasePart } = {}
	local spinFrames: { CFrame } = {}
	task.spawn(function()
		local map = Workspace:WaitForChild("Map", 10)
		if map then
			spinners = collectSpinners(map)
		end
	end)

	-- Поворачивает все вращающиеся модели на их угол. Позиции считаются заново от исходной
	-- точки опоры, поэтому ошибки округления не копятся.
	local function updateSpinners(elapsed: number)
		for index = #spinners, 1, -1 do
			if not spinners[index].model:IsDescendantOf(Workspace) then
				table.remove(spinners, index) -- модель удалили — больше не трогаем её детали
			end
		end
		local n = 0
		for _, spinner in spinners do
			spinner.angle = (spinner.angle + spinner.speed * elapsed) % (2 * math.pi)
			local frame = spinner.base * CFrame.Angles(0, 0, spinner.angle)
			for k, part in spinner.parts do
				n += 1
				spinParts[n] = part
				spinFrames[n] = frame * spinner.offsets[k]
			end
			for _, group in spinner.uprights do
				-- кабинка едет вместе с колесом, но сохраняет свой исходный поворот
				local pivot = CFrame.new(frame * group.pivot) * group.rotation
				for k, part in group.parts do
					n += 1
					spinParts[n] = part
					spinFrames[n] = pivot * group.offsets[k]
				end
			end
		end
		for k = #spinParts, n + 1, -1 do
			spinParts[k] = nil
			spinFrames[k] = nil
		end
		if n > 0 then
			Workspace:BulkMoveTo(spinParts, spinFrames, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end

	local accumulator = 0
	local interval = 1 / AMBIENT.UpdateRate
	RunService.Heartbeat:Connect(function(dt: number)
		accumulator += dt
		if accumulator < interval then
			return
		end
		local elapsed = accumulator
		accumulator = 0
		updateSpinners(elapsed)
		local t = os.clock()
		local i = 0
		for _, mover in movers do
			local root = mover:update(t)
			for k, offset in mover.offsets do
				local cf = root * offset
				if mover.flap and (k == 2 or k == 3) then
					local angle = math.sin(t * 9 + mover.phase) * 0.45 * (if k == 2 then 1 else -1)
					cf = root
						* CFrame.new(offset.Position.X * 0.15, 0.1, 0)
						* CFrame.Angles(0, 0, angle)
						* CFrame.new(offset.Position.X * 0.85, 0, 0)
				elseif not mover.flap and k == 2 then
					cf = cf * CFrame.Angles(0, math.sin(t * 10 + mover.phase) * 0.5, 0) -- tail wiggle
				end
				i += 1
				cframes[i] = cf
			end
		end
		Workspace:BulkMoveTo(allParts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

return AmbientController
