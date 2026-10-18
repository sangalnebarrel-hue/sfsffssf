--!strict
--[[
	TheftController — вор (Этап 4): кнопки «Украсть» у чужих витрин и всё, что видит крадущий
	(docs/stage4_design.md §5.1, §6.4; виджеты — HUD.TheftBar и HUD.TheftTitle,
	tools/builder/gui/Steal.luau; числа — UIConfig.Theft, тексты — StealConfig.Texts).

	Что делает (Wave 2 C; волна 0 — контракт: модуль, имя в ClientMain.ORDER, ничего не делает):
	  • прячет кнопки, которые красть нельзя, — МЕСТНЫМ MaxActivationDistance = 0 (сервер это
	    свойство после создания не пишет: повтор с сервера не вернёт кнопку, BE-14): все на своей
	    базе и без базы, пока крадёшь или ждёшь (StealCooldownUntil), всю базу под защитой
	    (ProtectUntil) или с кражей (Thief), витрину с кражей / «в пути» / свежим уловом, жертву с
	    меньше чем 3 рыбами или намного слабее, рыбу, которой нет места в своём садке; фильтр —
	    StealRules.CanStealView (строки Shared/TheftChecks с Client = true); кнопку, которую сейчас
	    держишь, — никогда (её гасит только сервер: Cancel / Denied → InputHoldEnd);
	  • полоса вверху (TheftBar; NotifyController.Reserve("theft", px)): подсказка во дворе,
	    «КРАДЁШЬ: ОКУНЬ» с полосой до конца удержания, «БЕГИ ЗА ОГРАДУ!» со сливающейся полосой,
	    «🐕 СОБАКА!» пока Slowed; TheftTitle — «ДОБЫЧА!» (конфетти, 🐟 летит в «САДОК») и
	    «СОРВАЛОСЬ!» с причиной; нет ответа сервера за Hold.NoReply с — InputHoldEnd и «Подожди
	    секунду»;
	  • красная дорожка к ближайшему выходу (StealRules.NearestExit) во время выноса;
	  • атрибуты HUD: Stealing (= фаза, для подсказки рыбалки и «ДОМОЙ»), TankIncoming (прилёт
	    рыбы в «САДОК» ждёт полёта 🐟).
	Покой — ни одного покадрового соединения (цепочки task.delay; кадры — только во время кражи).
]]

local TheftController = {}

function TheftController:Start(_hud: ScreenGui) end

return TheftController
