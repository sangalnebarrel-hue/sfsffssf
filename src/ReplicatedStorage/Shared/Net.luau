--!strict
--[[
	Net — единая точка доступа к RemoteEvent / RemoteFunction (папка ReplicatedStorage.Remotes).

	Все удалённые объекты уже лежат в Place1.rbxl (их список — модуль RemoteNames).
	На сервере недостающие создаются автоматически — на случай, если имя добавили
	в RemoteNames, а место не пересобрали. Клиент ждёт их через WaitForChild.

	Использование:
	  local Net = require(ReplicatedStorage.Shared.Net)
	  Net.Event("Notify"):FireClient(player, "Привет", "info")
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local RemoteNames = require(script.Parent:WaitForChild("RemoteNames"))

local IS_SERVER = RunService:IsServer()
local FOLDER_NAME = "Remotes"

local function ensureChild(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

local folder: Instance
if IS_SERVER then
	folder = ensureChild(ReplicatedStorage, "Folder", FOLDER_NAME)
	for _, name in RemoteNames.Events do
		ensureChild(folder, "RemoteEvent", name)
	end
	for _, name in RemoteNames.Functions do
		ensureChild(folder, "RemoteFunction", name)
	end
else
	folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
end

local function getRemote(name: string): Instance
	local remote = if IS_SERVER then folder:FindFirstChild(name) else folder:WaitForChild(name)
	assert(remote, `[Net] remote "{name}" не найден`)
	return remote
end

local Net = {}

-- RemoteEvent по имени из RemoteNames.Events.
function Net.Event(name: string): RemoteEvent
	assert(table.find(RemoteNames.Events, name), `[Net] "{name}" нет в RemoteNames.Events`)
	local remote = getRemote(name)
	assert(remote:IsA("RemoteEvent"), `[Net] "{name}" не RemoteEvent`)
	return remote
end

-- RemoteFunction по имени из RemoteNames.Functions.
function Net.Function(name: string): RemoteFunction
	assert(table.find(RemoteNames.Functions, name), `[Net] "{name}" нет в RemoteNames.Functions`)
	local remote = getRemote(name)
	assert(remote:IsA("RemoteFunction"), `[Net] "{name}" не RemoteFunction`)
	return remote
end

return Net
