--[[
	ClientMain (LocalScript) — точка входа клиента.

	Ждёт интерфейс HUD (StarterGui.HUD копируется в PlayerGui при первом появлении персонажа)
	и запускает контроллеры из папки Controllers по порядку.
	Новый контроллер = ModuleScript с функцией Start(hud) + его имя в списке ORDER.

	Каждый контроллер — под защитой: не загрузился или упал его Start — красная ошибка в Output
	(с путём), а остальные всё равно запускаются; Start, который ждёт дольше START_WAIT секунд
	(WaitForChild без конца), не держит следующие — о нём тоже громко.

	Контроллеры:
	  NotifyController     — всплывающие уведомления (сервер и другие контроллеры);
	  HudController        — плашка базы, кнопка «Домой» (Этап 1);
	  FishingController    — рыбалка своего игрока: кнопка действия, мини-игра, карточка улова (Этап 2);
	  FishingFxController  — поплавки и лески всех игроков, переливы радужных рыб (Этап 2); тень
	                         рыбы, живая рыба над головой (помощники FishingLine, FishShadow,
	                         FishLife, FishBody — модули, не контроллеры);
	  FisherAnimController — тело рыбаков рядом: замах, ожидание, поклёвка, борьба, улов над
	                         головой; гнущаяся удочка (помощники FisherRig, FisherPoses, FisherRod —
	                         модули, не контроллеры);
	  AmbientController    — «живой» мир: ветер (флаги, пальмы, дым), лодки и пена, блики,
	                         выпрыгивающие рыбы и стайки, чайки, бабочки, стрекозы, облака, огоньки
	                         (помощники AmbientEngine, AmbientWind, AmbientWorld, AmbientWater,
	                         AmbientCritters — модули, не контроллеры).
]]

local Players = game:GetService("Players")

local player = Players.LocalPlayer
local controllers = script.Parent:WaitForChild("Controllers")

-- NotifyController первым: остальные могут показывать через него уведомления.
local ORDER = {
	"NotifyController",
	"HudController",
	"FishingController",
	"FishingFxController",
	"FisherAnimController",
	"AmbientController",
}

local START_WAIT = 10 -- столько секунд ждём Start, прежде чем запускать следующие

-- Красным в Output (error в своём потоке), а не жёлтым warn, который легко пропустить.
local function fail(message: string)
	task.spawn(error, message, 0)
end

local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")

for _, name in ORDER do
	local module = controllers:WaitForChild(name, 10)
	if not (module and module:IsA("ModuleScript")) then
		fail(`[ClientMain] контроллер {name} не найден`)
		continue
	end
	local finished = false
	task.spawn(function()
		local ok, err = xpcall(function()
			local controller = require(module) :: any
			controller:Start(hud)
		end, debug.traceback)
		finished = true
		if not ok then
			fail(`[ClientMain] {name}.Start упал:\n{err}`)
		end
	end)
	-- Обычно Start закончился сразу (ничего не ждёт) — следующий запускается в том же кадре.
	local deadline = os.clock() + START_WAIT
	while not finished and os.clock() < deadline do
		task.wait()
	end
	if not finished then
		fail(
			`[ClientMain] {name}.Start ждёт дольше {START_WAIT} с (WaitForChild?) — запускаю остальные`
		)
	end
end
