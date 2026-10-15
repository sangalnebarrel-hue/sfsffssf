--[[
	ClientMain (LocalScript) — точка входа клиента.

	Ждёт интерфейс HUD (StarterGui.HUD копируется в PlayerGui при первом появлении персонажа)
	и запускает контроллеры из папки Controllers по порядку.
	Новый контроллер = ModuleScript с функцией Start(hud) + его имя в списке ORDER.

	Контроллеры:
	  NotifyController     — всплывающие уведомления (сервер и другие контроллеры);
	  HudController        — плашка базы, кнопка «Домой» (Этап 1);
	  FishingController    — рыбалка своего игрока: кнопка действия, мини-игра, карточка улова (Этап 2);
	  FishingFxController  — поплавки и лески всех игроков, переливы радужных рыб (Этап 2);
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

local hud = player:WaitForChild("PlayerGui"):WaitForChild("HUD")

for _, name in ORDER do
	local module = controllers:WaitForChild(name, 10)
	if module and module:IsA("ModuleScript") then
		local controller = require(module)
		local ok, err = xpcall(controller.Start, debug.traceback, controller, hud)
		if not ok then
			warn(`[ClientMain] {name}.Start упал:\n{err}`)
		end
	else
		warn(`[ClientMain] контроллер {name} не найден`)
	end
end
