--[[
	Main (Script) — точка входа сервера.

	Загружает сервисы из папки ServerScriptService.Services и запускает их по порядку:
	  1) у всех вызывается Init() — подготовка мира (карта, базы), без ожидания игроков;
	  2) у всех, чей Init прошёл успешно, вызывается Start() — подписки на события игроков,
	     RemoteEvent'ы, игровые циклы.
	Если сервис не загрузился или его Init упал — в Output будет ошибка с трассировкой,
	его Start не вызывается (чтобы он не работал «наполовину»), остальные сервисы запускаются.

	Новый сервис = ModuleScript в папке Services + его имя в списке ORDER.
]]

local ServerScriptService = game:GetService("ServerScriptService")

local Services = ServerScriptService:WaitForChild("Services")

-- Порядок важен: карта → базы → данные игроков (DataService) → деньги (EconomyService, ему
-- нужны данные) → ларьки (MarketService) → рыбалка (ей нужны базы и данные) → садок
-- (TankService: ему нужны все, он подключается к улову рыбалки) → защита базы (DefenceService,
-- Этап 4: щит, собака, сигнализация, замок; StealService не требует — спрашивает его через
-- SetStealProbe) → кража (StealService: ей нужны садок и защита) → (Этап 5: магазин).
local ORDER = {
	"MapService",
	"BaseService",
	"DataService",
	"EconomyService",
	"MarketService",
	"FishingService",
	"TankService",
	"DefenceService",
	"StealService",
}

local loaded = {}
local failed = {}

local function report(name: string, phase: string, err: any)
	failed[name] = true
	warn(`[Main] ❌ {name}: {phase} не удался — сервис выключен.\n{err}`)
end

for _, name in ORDER do
	local module = Services:FindFirstChild(name)
	if module and module:IsA("ModuleScript") then
		local ok, result = xpcall(require, debug.traceback, module)
		if ok then
			loaded[name] = result
		else
			report(name, "require", result)
		end
	else
		report(name, "поиск", "нет ModuleScript в ServerScriptService.Services")
	end
end

local function runPhase(phase: string)
	for _, name in ORDER do
		local service = loaded[name]
		if service and not failed[name] and type(service[phase]) == "function" then
			local ok, err = xpcall(service[phase], debug.traceback, service)
			if not ok then
				report(name, `{phase}()`, err)
			end
		end
	end
end

runPhase("Init")
runPhase("Start")

if next(failed) then
	warn("[Main] сервер запущен С ОШИБКАМИ — смотри сообщения ❌ выше")
else
	print("[Main] сервер запущен")
end
