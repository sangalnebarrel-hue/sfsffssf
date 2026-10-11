--!strict
--[[
	MapService — проверка мира при старте сервера.

	Земля «Острова Рыбаков» — это детали (Workspace.Map.Ground), а вода лагуны и океана —
	Terrain, «запечённый» прямо в Place1.rbxl (её видно в Studio без запуска игры).
	На всякий случай сервер проверяет, что вода на месте (читает пару вокселей посреди лагуны).
	Если её нет (например, Terrain случайно очистили) — заливает воду заново блоками
	Terrain:FillBlock до глубины океана. Внутри деталей земли вода не видна и не мешает.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapConfig = require(ReplicatedStorage.Shared.Config.MapConfig)

local VOXEL = 4
local TILE = 512 -- сторона одного блока заливки (studs)

local MapService = {}

-- true, если посреди лагуны (между островом и берегом) есть вода.
local function waterPresent(terrain: Terrain): boolean
	local r = (MapConfig.HubRadius + MapConfig.LagoonRadius) / 2
	local y = MapConfig.WaterTop - VOXEL
	local region = Region3.new(Vector3.new(-VOXEL, y, r - VOXEL), Vector3.new(VOXEL, y + VOXEL, r + VOXEL))
		:ExpandToGrid(VOXEL)
	local materials = terrain:ReadVoxels(region, VOXEL)
	for _, plane in materials do
		for _, column in plane do
			for _, material in column do
				if material == Enum.Material.Water then
					return true
				end
			end
		end
	end
	return false
end

-- Аварийная заливка: вода от дна океана до поверхности по всему квадрату ±OceanHalf.
local function refill(terrain: Terrain)
	local started = os.clock()
	local depth = MapConfig.OceanDepth
	local half = MapConfig.OceanHalf
	local y = MapConfig.WaterTop - depth / 2
	for x = -half, half - 1, TILE do
		for z = -half, half - 1, TILE do
			local sizeX, sizeZ = math.min(TILE, half - x), math.min(TILE, half - z)
			local centre = Vector3.new(x + sizeX / 2, y, z + sizeZ / 2)
			terrain:FillBlock(CFrame.new(centre), Vector3.new(sizeX, depth, sizeZ), Enum.Material.Water)
			task.wait() -- не подвешиваем сервер
		end
	end
	warn(`[MapService] вода залита заново за {math.floor(os.clock() - started)} c`)
end

function MapService:Init()
	local terrain = Workspace.Terrain
	local ok, present = pcall(waterPresent, terrain)
	if not ok then
		warn(`[MapService] не удалось прочитать воду: {present}`)
		return
	end
	if present then
		print("[MapService] вода на месте")
	else
		warn("[MapService] воды в файле нет — заливаю заново…")
		refill(terrain)
	end
end

return MapService
