--!strict
--[[
	MoneyController — кошелёк (Этап 3): HUD.Status.Wallet — 💵 «$1 234» (Money.Label, цвет
	UIConfig.MoneyText) и доход «+$42/с» (Rate) во второй строке статуса, там, где был счётчик
	улова. Вид сумм — TankRules.FormatMoney / FormatRate, стиль — tools/builder/gui/STYLE.md.
	ЗАГЛУШКА (волна 0): Start и Celebrate ничего не делают, кошелёк спрятан (его строит
	tools/builder/gui/Hud.luau). Реализация — волна 2 (scratchpad design.md, §6.2).

	Что делает:
	  • Показ: кошелёк виден, как только атрибут игрока DataMode ≠ "Loading" (база не нужна:
	    деньги есть и у ждущего в очереди); грузится дольше 3 с — кошелёк на «стекле»
	    (Wallet.Back) с «$…» (EconomyConfig.Format.Loading) и без дохода — деньги не «пропадают».
	    Появления — после того как баннер базы влетел в плашку: плашка → кошелёк → «САДОК» через
	    0.3 с (popIn с 0.3, 💵 крутится); в очереди — когда загрузились данные.
	  • Доход каждую секунду — ПРОСТО ТЕКСТ (без countUp и подпрыгиваний: покой HUD без
	    покадровой работы); раз в 5 с при доходе > 0 справа от числа всплывает маленькое «+$13»
	    (floatText на таймере). «+$/с» скрыт, пока доход 0; не мельче 14 px на phone_small, а
	    «$999 999» — не ниже 22 px.
	  • Один хозяин надписи. shown — число на надписи; held — монеты, которые сервер УЖЕ зачислил
	    (они в атрибуте Money), но праздник их ещё не долетел. Без countUp тик раз в секунду пишет
	    shown = Money − held. Пока идёт countUp, тик надпись не пишет, а двигает цель countUp к
	    Money − held; кончился countUp — тик снова пишет. Число никогда не прыгает туда-обратно и
	    никогда не обгоняет Money − held.
	  • Celebrate(amount, from?, opts?) — праздник денег, ОДИН вызов на каждую зачисленную сумму
	    (кто зовёт — ниже). amount только задаёт число монет и подпись, к надписи он НЕ
	    прибавляется: деньги уже в Money (сервер: зачисление → атрибуты → remote'ы).
	      1) В миг вызова сумма придержана до первого прилёта: часть, уже придержанная уловом (ниже),
	         берётся оттуда (дважды не держится), остальное — held += min(остаток, Money − held −
	         shown), т. е. только то, чего надпись ещё не показала (тик успел показать — держать
	         нечего, надпись назад не шагнёт).
	      2) flyTo(hud, from, Money.Icon, { text = "💵", count = 3..8 по сумме }); from = nil — без
	         полёта, сразу шаг 3.
	      3) На первом прилёте: придержанное этим вызовом отпущено (held −= …), countUp(label,
	         shown, Money − held, 0.6–1.0, TankRules.FormatMoney, { bump = true }) — от того, что
	         видно, до правды (не shown + amount), — и flashText(Gold.Top); золотое «+$1 234»
	         (amount) уровня Button и звук "ping"; покадровая работа — только пока идёт.
	    opts.Rate = "down" — после ручной продажи доход «+$/с» катится ВНИЗ (countUp 0.5 с от
	    показанного к атрибуту Income) с короткой вспышкой Berry («продал — дохода меньше»); "up" —
	    после замены, вверх с золотой.
	  • Кто зовёт Celebrate (каждая сумма — ровно один раз):
	      ручная продажа (TankEvent "Sold") — TankPanelController: Celebrate(Amount, карточка,
	        { Rate = "down" });
	      улов "replaced" — ТОЛЬКО TankButtonController, после своего кольца: Celebrate(Price,
	        TankButton, { Rate = "up" }) (кнопка не видна — from = nil); MoneyController сам эту
	        сумму не празднует, только держит её;
	      улов "sold" — ТОЛЬКО MoneyController, когда снят CounterHold: Celebrate(Price, nil) —
	        призрак карточки уже прилетел в Wallet.Money как 💵 (FishingController), только счёт.
	  • Придержка улова: на "Caught" с Tank.Result "replaced" / "sold" (Tank.Price — монеты этого
	    улова, RemoteNames) MoneyController держит Price (held += min(Price, Money − held − shown)),
	    пока у HUD есть CounterHold и до Celebrate этой суммы (шаг 1 берёт её отсюда).
	Атрибуты, которые читает: Player — Money, Income, DataMode; HUD — CounterHold. Remote:
	FishingState "Caught" (Tank.Result, Tank.Price — только для придержки).

	API:
	  MoneyController:Start(hud)
	  MoneyController.Celebrate(amount: number, from: GuiObject?, opts: { Rate: ("down" | "up")? }?)
]]

export type CelebrateOptions = {
	Rate: ("down" | "up")?, -- куда катится доход «+$/с» вместе с праздником (продажа / замена)
}

local MoneyController = {}

function MoneyController:Start(_hud: ScreenGui) end

function MoneyController.Celebrate(_amount: number, _from: GuiObject?, _opts: CelebrateOptions?) end

return MoneyController
