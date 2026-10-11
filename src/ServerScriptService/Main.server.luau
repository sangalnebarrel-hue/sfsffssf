--[[
	Main (Script) — точка входа сервера.

	Загружает сервисы из папки ServerScriptService.Services и запускает их по порядку:
	  1) у всех вызывается Init() — подготовка мира (карта, базы), без ожидания игроков;
	  2) у всех вызывается Start() — подписки на события игроков, RemoteEvent'ы, игровые циклы.
	Ошибка в одном сервисе выводится в Output, но не мешает запуститься остальным.

	Новый сервис = ModuleScript в папке Services + его имя в списке ORDER.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")

-- Порядок важен: карта → базы → (следующие этапы: данные, рыбалка, садок, кража, магазин).
local ORDER = {
	"MapService",
	"BaseService",
}

local loaded = {}

for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		loaded[name] = require(module)
	else
		warn(`[Main] сервис {name} не найден в ServerScriptService.Services`)
	end
end

local function runPhase(phase: string)
	for _, name in ORDER do
		local service = loaded[name]
		if service and type(service[phase]) == "function" then
			local ok, err = xpcall(service[phase], debug.traceback, service)
			if not ok then
				warn(`[Main] {name}:{phase}() упал:\n{err}`)
			end
		end
	end
end

runPhase("Init")
runPhase("Start")

print("[Main] сервер запущен")
