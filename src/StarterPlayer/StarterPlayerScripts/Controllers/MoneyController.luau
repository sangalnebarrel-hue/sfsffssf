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
	  • Один хозяин надписи: shown = Money − held. Пока идёт countUp, тик раз в секунду надпись
	    не пишет, а прибавляет своё к цели countUp; кончился countUp — тик снова пишет. Число
	    никогда не прыгает туда-обратно.
	  • Celebrate(amount, from?, opts?) — праздник денег: flyTo(hud, from, Money.Icon, { text = "💵",
	    count = 3..8 по сумме }) (from = nil — без полёта); на первом прилёте countUp(label, shown,
	    shown + amount, 0.6–1.0, TankRules.FormatMoney, { bump = true }) и flashText(Gold.Top);
	    золотое «+$1 234» уровня Button и звук "ping"; покадровая работа — только пока идёт.
	    opts.Rate = "down" — после ручной продажи доход «+$/с» катится ВНИЗ (countUp 0.5 с) с
	    короткой вспышкой Berry («продал — дохода меньше»); "up" — после замены, вверх с золотой.
	  • Пока у HUD есть CounterHold (улов на экране), продажа из улова (Tank.Result "replaced" /
	    "sold": Price) придержана (shown = Money − held); CounterHold снят: "replaced" —
	    Celebrate(Price, TankButton) (монеты летят из «САДОК» в кошелёк), "sold" — призрак
	    карточки уже прилетел в Wallet.Money как 💵 (FishingController), Celebrate(Price, nil) —
	    только счёт.
	Атрибуты, которые читает: Player — Money, Income, DataMode; HUD — CounterHold.

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
