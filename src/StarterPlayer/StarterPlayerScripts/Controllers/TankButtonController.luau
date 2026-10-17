--!strict
--[[
	TankButtonController — кнопка «САДОК» (Этап 3): HUD.RightButtons.TankButton — квадратная
	бирюзовая (Water) кнопка 🐠 «САДОК» над «ДОМОЙ», фишка «4/6» (Count) на левом плече и
	красный «!» (Badge). Стиль — tools/builder/gui/STYLE.md.
	ЗАГЛУШКА (волна 0): Start ничего не делает, кнопка спрятана (её строит
	tools/builder/gui/Hud.luau). Реализация — волна 2 (scratchpad design.md, §6.3).

	Что делает:
	  • Видна, когда у игрока есть база и загружены данные (popIn на своём месте; Position колонки
	    не анимируется никогда — по ней раскладывает FishingController). Нажатие — UiFx.press один
	    раз в Start → TankPanelController.Toggle().
	  • Фишка «4/6» — ТОЛЬКО из атрибутов игрока TankCount / TankSlots (Tank из "Caught" решает лишь,
	    какой прилёт играть); Cream, Gold — когда садок полон.
	  • Прилёт улова (прежний договор счётчика): FishingController ставит HUD CounterHold на
	    "Caught" и CounterIncoming = редкость при закрытии карточки; пока CounterHold — фишка
	    заморожена на числе до улова. Снят: "stored" — одометр фишки, подпрыгивание 1.3 (1.45 в
	    цветах редкости), кольцо цвета редкости, 🐠 плющится и качается, тик; "replaced" — фишка
	    та же, 🐠 качается, кольцо, потом MoneyController.Celebrate(Price, TankButton); "sold" —
	    на кнопке НИЧЕГО (призрак улетел в кошелёк). Без CounterHold (Этап 4: "Stored") — тот же
	    прилёт через кадр после изменения TankCount.
	  • «!» новичка: после прилёта первой рыбы за всё время (Tank.First) — UiFx.badgeBob(Badge);
	    первое открытие панели — UiFx.badgeHide (на сессию, без remote: First и так один раз).
	  • Нажатие во время полёта рыбы (CounterHold) запоминается (без «нет»-качания): панель
	    откроется сразу после прилёта, прокрученная к новой рыбе, с кольцом цвета редкости
	    (TankPanelController.Open(uid)); нажатие во время поклёвки, мини-игры или открытой
	    карточки — качание «нет» (wiggle).
	  • Цвет: Water (#6FF2FF → #13B8D6) близок к Sky («ЗАБРОСИТЬ» под ней на телефоне) — если на
	    рендере tank_button это «та же голубая кнопка», заливку этой кнопки сделать глубже или 🐠
	    крупнее. «Жизнь» HUD (HudController) вместо 🐟 счётчика качает 🐠 этой кнопки.
	Атрибуты, которые читает: Player — TankCount, TankSlots, DataMode, BaseIndex; HUD —
	CounterHold, CounterIncoming.

	API:
	  TankButtonController:Start(hud)
]]

local TankButtonController = {}

function TankButtonController:Start(_hud: ScreenGui) end

return TankButtonController
