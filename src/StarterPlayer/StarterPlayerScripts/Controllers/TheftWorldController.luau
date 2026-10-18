--!strict
--[[
	TheftWorldController — кража в мире (Этап 4; всё на клиенте, ни одной детали сервера):
	лампа и сирена базы, подсветка вора, купол щита, табличка флага, собака, рыба на голове вора
	(docs/stage4_design.md §5.3, §5.4; числа — DefenceConfig.World / Dog, тексты —
	StealConfig.Texts.World, DefenceConfig.Texts.World). Витрины во время кражи, строка защит над
	аквариумом и слово у ведра — TankWorldController.

	Что делает (Wave 1 B; волна 0 — контракт: модуль, имя в ClientMain.ORDER, ничего не делает):
	  • лампа Alarm.Lamp: пока у базы AlarmState — один зацикленный твин цвета (Neon,
	    World.LampPeriod; гость — IntruderPeriod) и мигающий PointLight на своём Attachment;
	    кончилось или база дальше 260 studs — вид шаблона ровно как был;
	  • сигнализация куплена (HasAlarm) и идёт кража: вращающийся красный SpotLight и писк
	    (BeepRange); вор подсвечен (Highlight: хозяину — AlwaysOnTop, остальным — Occluded) и
	    «ВОР!» над головой — создаются в начале, убираются в конце;
	  • купол — только у щита (World.Dome.Kinds), только у баз ближе Range, на тач-экране — не
	    больше PhoneMax; ForceField, цвет Guard;
	  • табличка флага OwnerSign: «🛡️ 4:12», пока база под любой защитой;
	  • собака (Dog.Unlocked): по DogPos с плавным догоном — покадровое соединение ТОЛЬКО пока
	    DogState ≠ "Sleep"; «ГАВ!»; во сне — поза сервера (pivot щенка у Dog.Rest);
	  • рыба на голове вора (StolenFish): жизнь (твин), табличка «🥷 Окунь $45».
	Покой — ни одного покадрового соединения; всё убирается вместе с базой.
]]

local TheftWorldController = {}

function TheftWorldController:Start(_hud: ScreenGui) end

return TheftWorldController
