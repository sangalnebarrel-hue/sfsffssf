--!strict
--[[
	AlertController — тревога хозяина (Этап 4): «у тебя крадут» и всё, что это сопровождает
	(docs/stage4_design.md §1.2, §6.3; плашка — HUD.TheftAlert, tools/builder/gui/Alert.luau;
	числа — UIConfig.Theft, тексты — StealConfig.Texts.Alert / Result).

	Что делает (Wave 2 D; волна 0 — контракт: модуль, имя в ClientMain.ORDER, ничего не делает):
	  • по StealEvent "Alert" — плашка «ВОР В САДКЕ!» / «ВОР УБЕГАЕТ!» в слоте уведомлений
	    (NotifyController.Reserve("alert", px)) с большой кнопкой «🛡️ ЩИТ» (≥ ShieldMin px и ≥
	    ShieldShare ширины плашки; на перезарядке — Slate «⏳ 1:12») и «🏠 ДОМОЙ»; пока сам крадёшь —
	    без кнопок и «Пока крадёшь сам, щит не включить»; на телефоне, если плашка легла бы на
	    рыбака (FishingLayout.fisherBox), — «таблетка» Compact;
	  • всегда (без места на экране): тонкая красная пульсация краёв (UiFx.edgeVignette, не больше
	    Theft.Edge.Alpha), HudController.HomeAlert(true), кнопка «ЗАЩИТА» в режиме «ЩИТ!» (атрибут
	    HUD AlertPhase = "hold" | "carry"), 3 «пина» (не при Quiet);
	  • тревога важнее карточки улова (DC-02): ставя AlertPhase, зовёт FishingController.HurryCard()
	    — карточка закрывается обычным путём, плашка выходит, когда она закрыта и CounterHold снят;
	  • кнопки не забирают ввод мини-игры (её ввод — только ActionButton);
	  • итог: «Украдено: …» (вид theft, «Садок отдыхает 1:30…», один совет) или «Рыба спасена!»
	    (вид saved; без уведомления при Quiet); «👀 … у тебя во дворе!» по "Intruder".
	Соединения — в Trove; покой — ни одного покадрового соединения (пульсации — таймеры).
]]

local AlertController = {}

function AlertController:Start(_hud: ScreenGui) end

return AlertController
