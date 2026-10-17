--!strict
--[[
	TankPanelController — панель садка (Этап 3): HUD.TankPanel — лист (Panel) с шапкой
	🐠 «САДОК» · «4/6» · «+$42/с» · «💵 $2 783 ▲» · фишка «🏪 РЫНОК +50%», круглый ✕ и
	карточками рыб (Cards: CardTemplate / EmptyTemplate / LockedTemplate). Лист открывает,
	раскладывает и закрывает помощник Controllers.Sheet (его же возьмёт магазин Этапа 5).
	Строят их tools/builder/gui/Sheet.luau (оболочка) и Tank.luau (содержимое); стиль —
	tools/builder/gui/STYLE.md.
	ЗАГЛУШКА (волна 0): Start, Toggle, Open, Close ничего не делают, IsOpen — false, панель
	спрятана. Реализация — волна 2 (scratchpad design.md, §6.4).

	Что делает:
	  • Место — в px при открытии, записанное как UDim2.fromScale(x / W, y / H) от HUD, и заново
	    при смене ViewportSize: слева 16 px (+ безопасный отступ), справа min(RightButtons.left,
	    Jump.left) − 16, сверху низ Status + 16, снизу HUD − 16 (телефон 844×390 ≈ 717 × 221); на
	    планшете и ПК — не больше 900 × 560, по центру этого места. Не закрывает ни кошелёк, ни
	    кнопку «САДОК»; без затемнения.
	  • Фон: на телефоне — «стекло» с тонкой полосой Night под шапкой, на планшете и ПК — Night;
	    карточки — Theme.sim без блика, глянца и тени.
	  • Карточки: на телефоне один ряд (ScrollingFrame, явный CanvasSize), на HUD ≥ TankConfig.Panel
	    .TallFrom px — RowsTall ряда; витрины 1..TankSlots, потом ОДНА закрытая (Locked). Рыба:
	    плашка цвета редкости (мифическая — радужная обводка, только пока открыта); Name —
	    TextUtil.upper(ShortName) (на карточке шире Panel.WideCard — полное имя); Viewport — сама
	    рыба (создаётся при открытии, удаляется при закрытии); Mutation — фишка «✨ ×2»; Rate
	    «+$4/с»; Growth — полоска (Track / Fill) с «×1.4» или золотое «МАКС»; Sell — «💵 $45» на
	    телефоне, «ПРОДАТЬ $45» на широкой: Leaf дома, Gold у ларька, Berry «ТОЧНО?» с ringTimer
	    при подтверждении. Пустая — стекло, 🎣, «ПУСТО», «Поймай рыбу!»; закрытая — Slate, 🔒,
	    «ЕЩЁ МЕСТО», «Скоро в магазине» (тексты — TankConfig.Texts).
	  • Числа — из атрибутов своих витрин (RemoteNames, «Состояние садка») и SellRatePct, одна
	    цепочка task.delay раз в Panel.Tick секунд, пока открыта (цены, полоски, сумма садка в
	    шапке); покадровой работы при открытой панели в покое — нет. Витрина перечитывается только
	    по её Event.
	  • Рынок: SellRatePct > 100 (атрибут сервера — единственный источник) — фишка «РЫНОК +50%»
	    выскакивает, цены — по ставке ларька, кнопки — Gold (до ≈ 2 с после прихода к ларьку:
	    сервер ждёт MarketDwell проверок). TankEvent "Open" с ларька только открывает панель.
	  • Продажа — каждая рыба в два нажатия: первое — «ТОЧНО?» + ringTimer ConfirmTime с и Rate
	    карточки мигает красным «−$4/с»; второе раньше ConfirmArm не считается; 0.4–3 с —
	    TankSell(uid), на кнопке ⏳ до ответа; через 3 с — назад. "Sold" — карточка сжимается,
	    Viewport исчезает, карточка становится пустой (popIn), MoneyController.Celebrate(Amount,
	    карточка, { Rate = "down" }); рыбу в мире убирает событие витрины. "Denied" — карточка
	    качается, подсказка — Text сервера.
	  • Открытие: snapIn + staggerPop карточек / закрытие popOut. Пока CounterHold — открытие
	    откладывается до прилёта (TankButtonController); во время поклёвки, мини-игры, открытой
	    карточки улова — отказ (кнопка качается). Закрывается САМА, когда FishingState становится
	    "Bite" или "Reeling", появляется CounterHold, видны BiteAlert / Minigame / CatchCard —
	    рыбака на экране не закрывает никогда; и по ✕ или кнопке «САДОК».
	  • Бюджеты: заливка телефона ≤ 2.5× с открытой панелью (gui_render.py; не хватает —
	    вместо Viewport на телефоне эмодзи редкостей 🐟 🐠 🐡 🦈 🐉); ≤ 60 временных объектов;
	    UiFx.activeJobs() == 0 после каждого эффекта; соединений после закрытия — как до открытия.
	Атрибуты витрин требуют StreamingEnabled = false (tools/build.luau).

	API:
	  TankPanelController:Start(hud)
	  TankPanelController.Toggle()                  -- кнопка «САДОК»
	  TankPanelController.Open(focusUid: string?)   -- открыть (прокрутить к рыбе focusUid: прилёт улова)
	  TankPanelController.Close()
	  TankPanelController.IsOpen() -> boolean
]]

local TankPanelController = {}

function TankPanelController:Start(_hud: ScreenGui) end

function TankPanelController.Toggle() end

function TankPanelController.Open(_focusUid: string?) end

function TankPanelController.Close() end

function TankPanelController.IsOpen(): boolean
	return false
end

return TankPanelController
