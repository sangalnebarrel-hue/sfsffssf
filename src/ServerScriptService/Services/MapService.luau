--!strict
--[[
	MapService — подготовка карты при старте сервера.

	Вода в озере и океане — это настоящая вода Terrain (в ней можно плавать). Сборщик места
	не умеет записывать воксели Terrain, поэтому в Place1.rbxl вода лежит как полупрозрачные
	блоки Workspace.Map.Water (их видно в Studio — можно двигать/растягивать).
	При запуске игры MapService заливает каждый такой блок водой Terrain и удаляет сам блок.
]]

local Workspace = game:GetService("Workspace")

local MapService = {}

function MapService:Init()
	local map = Workspace:FindFirstChild("Map")
	local water = map and map:FindFirstChild("Water")
	if not water then
		warn("[MapService] Workspace.Map.Water не найден — вода не создана")
		return
	end

	local terrain = Workspace.Terrain
	local filled = 0
	for _, volume in water:GetDescendants() do
		if volume:IsA("BasePart") then
			terrain:FillBlock(volume.CFrame, volume.Size, Enum.Material.Water)
			filled += 1
		end
	end
	water:Destroy()

	print(`[MapService] вода залита ({filled} блоков)`)
end

return MapService
