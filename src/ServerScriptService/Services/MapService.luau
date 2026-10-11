--!strict
--[[
	MapService — проверка мира при старте сервера.

	Рельеф «Рыбацкой долины» (озеро, горы, реки) запечён прямо в Place1.rbxl — его видно в Studio
	без запуска игры. На всякий случай сервер проверяет, что рельеф на месте (читает пару вокселей
	в центре острова). Если там пусто — генерирует весь рельеф заново тем же генератором
	(ServerStorage.WorldGen) через Terrain:WriteVoxels. Это занимает несколько секунд и в норме
	не нужно никогда.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)

local VOXEL = 4
local BLOCK = 32 -- колонок по X и Z за один вызов WriteVoxels

local MapService = {}

-- true, если в центре острова (под площадью) есть твёрдый рельеф.
local function terrainPresent(terrain: Terrain): boolean
	local y = MapConfig.GroundTop - VOXEL
	local region = Region3.new(Vector3.new(-VOXEL, y - VOXEL, -VOXEL), Vector3.new(VOXEL, y, VOXEL)):ExpandToGrid(VOXEL)
	local materials = terrain:ReadVoxels(region, VOXEL)
	for _, plane in materials do
		for _, column in plane do
			for _, material in column do
				if material ~= Enum.Material.Air and material ~= Enum.Material.Water then
					return true
				end
			end
		end
	end
	return false
end

-- Аварийная генерация всего рельефа (если в файле его нет).
local function regenerate(terrain: Terrain)
	local worldGen = ServerStorage:FindFirstChild("WorldGen")
	assert(worldGen and worldGen:IsA("ModuleScript"), "[MapService] нет ServerStorage.WorldGen")
	local WorldGen = require(worldGen) :: any
	local started = os.clock()
	local gen = WorldGen.new(MapConfig)
	gen:build()

	local yMin, yMax = gen:voxelRangeY()
	local height = yMax - yMin + 1
	local n = gen.n
	for bz = -n, n - 1, BLOCK do
		for bx = -n, n - 1, BLOCK do
			local sizeX, sizeZ = math.min(BLOCK, n - bx), math.min(BLOCK, n - bz)
			local materials: { { { Enum.Material } } } = {}
			local occupancies: { { { number } } } = {}
			for x = 1, sizeX do
				local mx: { { Enum.Material } } = {}
				local ox: { { number } } = {}
				for y = 1, height do
					mx[y] = table.create(sizeZ, Enum.Material.Air)
					ox[y] = table.create(sizeZ, 0)
				end
				materials[x], occupancies[x] = mx, ox
			end
			for dx = 0, sizeX - 1 do
				for dz = 0, sizeZ - 1 do
					gen:fillColumn(bx + dx, bz + dz, function(iy: number, material: string, occupancy: number)
						local y = iy - yMin + 1
						if y >= 1 and y <= height then
							materials[dx + 1][y][dz + 1] = (Enum.Material :: any)[material]
							occupancies[dx + 1][y][dz + 1] = occupancy
						end
					end)
				end
			end
			local corner = Vector3.new(bx * VOXEL, yMin * VOXEL, bz * VOXEL)
			local region = Region3.new(corner, corner + Vector3.new(sizeX, height, sizeZ) * VOXEL)
			terrain:WriteVoxels(region, VOXEL, materials, occupancies)
			task.wait() -- не подвешиваем сервер
		end
	end
	warn(`[MapService] рельеф сгенерирован заново за {math.floor(os.clock() - started)} c`)
end

function MapService:Init()
	local terrain = Workspace.Terrain
	local ok, present = pcall(terrainPresent, terrain)
	if not ok then
		warn(`[MapService] не удалось прочитать рельеф: {present}`)
		return
	end
	if present then
		print("[MapService] рельеф на месте")
	else
		warn("[MapService] рельеф в файле не найден — генерирую заново…")
		regenerate(terrain)
	end
end

return MapService
