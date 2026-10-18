--!strict
--[[
	DefenceController — защита своей базы на экране (Этап 4): кнопка «ЗАЩИТА» справа, фишка щита у
	плашки базы и лист «ЗАЩИТА» с карточками Щит · Собака · Сигнализация · Замок
	(docs/stage4_design.md §6.2, §6.5, §6.6; виджеты — HUD.RightButtons.DefenceButton,
	HUD.Status.BaseBadge.ShieldChip (tools/builder/gui/Hud.luau), HUD.DefencePanel
	(tools/builder/gui/Defence.luau на оболочке gui/Sheet.luau); числа — DefenceConfig, UIConfig.Theft,
	тексты — DefenceConfig.Texts).

	Что делает (Wave 2 D; волна 0 — контракт: модуль, имя в ClientMain.ORDER, подписи):
	  • кнопка «ЗАЩИТА» (Guard 🛡️) — открыть / закрыть лист (Toggle; правила «занято» листа — как у
	    садка); во время кражи у тебя, пока щит готов и ты не крадёшь сам (атрибут HUD AlertPhase),
	    — «ЩИТ!»: одно нажатие — ShieldActivate, даже во время мини-игры; перезарядка — вуаль и
	    «2:59» (рецепт «ДОМОЙ»), готов — «ГОТОВ!»;
	  • фишка «🛡️ 0:42» справа от плашки базы, пока ProtectUntil своей базы > сейчас (любая
	    защита; щит — на сплошной Guard), цепочка task.delay раз в секунду, последние WarnLast с —
	    пульс; «Скоро воры смогут красть…» за EndingWarn с до конца защиты входа / новичка;
	  • лист: карточки, покупка в два нажатия (DefenceBuy), ответы DefenceEvent "Bought" /
	    "Denied" / "Shield"; один лист на экране (Controllers/Sheet).
	Покой — ни одного покадрового соединения.

	API:
	  DefenceController.Toggle()        -- открыть / закрыть лист «ЗАЩИТА»
	  DefenceController.IsOpen() -> boolean
]]

local DefenceController = {}

function DefenceController.Toggle() end

function DefenceController.IsOpen(): boolean
	return false
end

function DefenceController:Start(_hud: ScreenGui) end

return DefenceController
