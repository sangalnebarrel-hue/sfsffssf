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
	  MoneyController      — кошелёк: деньги и доход «+$/с», праздник продажи (Этап 3);
	  TankButtonController — кнопка «САДОК» с фишкой «4/6», прилёт улова в садок (Этап 3);
	  TankPanelController  — панель садка: карточки рыб, продажа в два нажатия (Этап 3; лист
	                         открывает помощник Sheet, карточки рисует помощник TankCards —
	                         модули, не контроллеры);
	  TankWorldController  — рыбы в витринах двора, надписи над ними, слово садка у ведра на
	                         пирсе, слово рынка (Этап 3);
	  DefenceController    — кнопка «ЗАЩИТА», фишка щита у плашки базы, лист «ЗАЩИТА» (Этап 4);
	  AlertController      — тревога хозяина: плашка «ВОР В САДКЕ!» с кнопкой «ЩИТ» (Этап 4);
	  TheftController      — вор: кнопки «Украсть», полоса «КРАДЁШЬ…», «ДОБЫЧА!» (Этап 4);
	  TheftWorldController — кража в мире: лампа, сирена, купол щита, собака, рыба на голове
	                         вора (Этап 4);
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

-- NotifyController первым: остальные могут показывать через него уведомления. Контроллеры садка
-- и денег — после HudController и до FishingController (рыбалка летит улов в их кнопки);
-- контроллеры кражи и защиты (Этап 4) — после садка и до рыбалки (тревога закрывает карточку
-- улова через FishingController.HurryCard — функцию модуля, не зависящую от порядка Start).
local ORDER = {
	"NotifyController",
	"HudController",
	"MoneyController",
	"TankButtonController",
	"TankPanelController",
	"TankWorldController",
	"DefenceController",
	"AlertController",
	"TheftController",
	"TheftWorldController",
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
