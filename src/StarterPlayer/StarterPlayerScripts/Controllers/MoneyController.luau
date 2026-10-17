--!strict
--[[
	MoneyController — кошелёк (Этап 3): HUD.Status.Wallet — 💵 «$1 234» (Money.Label, цвет
	UIConfig.MoneyText) и доход «+$42/с» (Rate) во второй строке статуса, там, где был счётчик
	улова; как «$0» образца — без плашки, крупное наклонное зелёное число с толстой обводкой.
	Вид сумм — TankRules.FormatMoney / FormatRate, числа — UIConfig.Wallet, стиль —
	tools/builder/gui/STYLE.md.

	Что делает:
	  • Показ: кошелёк виден, как только атрибут игрока DataMode — "Ready" или "Memory" (база не
	    нужна: деньги есть и у ждущего в очереди); грузится дольше Wallet.LoadingAfter с — кошелёк
	    на «стекле» (Money.Back) с «$…» (EconomyConfig.Format.Loading) и без дохода — деньги не
	    «пропадают». Появление — после того как баннер базы влетел в плашку (атрибут HUD IntroAt,
	    его ставит HudController): плашка → кошелёк через Wallet.IntroGap → «САДОК» ещё через
	    столько же (TankButtonController); popIn с PopFrom, 💵 вкручивается. В очереди — когда
	    загрузились данные. Studio без доступа к DataStore (DataMode "Memory") — один раз
	    уведомление DataConfig.Texts.MemoryToast (после баннера).
	  • Строка подгоняется под текст (layout): 💵, число, промежуток, доход — группа стоит по центру
	    под плашкой базы; не влезает — число мельчает (не мельче Wallet.MinMoney px), потом
	    прячется доход. Подгонка — при смене текста, числа цифр и размера экрана; ширина букв —
	    по меркам шрифта (GLYPHS ниже), а не по средней UiFx.textWidth (цифры у Heavy шире).
	  • Доход каждую секунду — ПРОСТО ТЕКСТ (без countUp и подпрыгиваний: покой HUD без
	    покадровой работы): надпись пишет атрибут Money (через кадр — улов успевает придержать
	    свою сумму, см. ниже). Раз в Wallet.FloatEvery с при доходе > 0 справа от числа всплывает
	    маленькое зелёное «+$13» (доход в секунду; floatText на цепочке task.delay). «+$/с» скрыт,
	    пока доход 0; не мельче Button.
	  • Один хозяин надписи. shown — число на надписи; held — монеты, которые сервер УЖЕ зачислил
	    (они в атрибуте Money), а их праздник ещё не долетел. Без «набегания» тик пишет
	    shown = Money − held. Пока число «набегает» (своя покадровая работа, только пока идёт),
	    тик надпись не пишет, а двигает цель к Money − held; кончилось — тик снова пишет. Число
	    никогда не прыгает туда-обратно и никогда не обгоняет Money − held.
	  • Celebrate(amount, from?, opts?) — праздник денег, ОДИН вызов на каждую зачисленную сумму
	    (кто зовёт — ниже). amount только задаёт число монет и подпись, к надписи он НЕ
	    прибавляется: деньги уже в Money (сервер: зачисление → атрибуты → remote'ы).
	      1) В миг вызова сумма придержана до первого прилёта: часть, уже придержанная уловом (ниже),
	         берётся оттуда (дважды не держится), остальное — held += min(остаток, Money − held −
	         shown), т. е. только то, чего надпись ещё не показала (тик успел показать — держать
	         нечего, надпись назад не шагнёт).
	      2) flyTo(hud, from, Money.Icon, { text = "💵", count = Wallet.Coins по сумме }); from = nil
	         (или кошелёк не виден) — без полёта, сразу шаг 3.
	      3) На первом прилёте: придержанное этим вызовом отпущено (held −= …), число «набегает» от
	         того, что видно, до правды Money − held (Wallet.Count — дольше у больших сумм; каждое
	         новое число подпрыгивает 1.06, не чаще 12 раз в секунду), вспыхивает золотом; золотое
	         «+$1 234» (amount) уровня Button и звук "ping".
	    opts.Rate ("down" | "up") — подсказка, куда покатится доход «+$/с»; катит его сам атрибут
	    Income (ниже), так что продажа и замена катятся и без неё.
	  • Доход «+$/с» катится (countUp Wallet.RateRoll с, FormatRate) к атрибуту Income: вниз — с
	    короткой красной вспышкой Berry («продал — дохода меньше»), вверх — с золотой. Пока у HUD
	    CounterHold (улов летит в садок), доход стоит на прежнем и катится, когда рыба долетела.
	  • Кто зовёт Celebrate (каждая сумма — ровно один раз):
	      ручная продажа (TankEvent "Sold") — TankPanelController: Celebrate(Amount, карточка,
	        { Rate = "down" });
	      улов "replaced" — ТОЛЬКО TankButtonController, после своего кольца: Celebrate(Price,
	        TankButton, { Rate = "up" }) (кнопка не видна — from = nil); MoneyController сам эту
	        сумму не празднует, только держит её (не позвали за Wallet.HoldRelease с после снятия
	        CounterHold — отпускает: надпись не застревает);
	      улов "sold" — ТОЛЬКО MoneyController, когда снят CounterHold: Celebrate(Price, nil) —
	        призрак карточки уже прилетел в Wallet.Money как 💵 (FishingController), только счёт;
	        первый раз за игру — уведомление TankConfig.Texts.FullSold (Sun, 💵).
	  • Придержка улова: на "Caught" с Tank.Result "replaced" / "sold" (Tank.Price — монеты этого
	    улова, RemoteNames) MoneyController держит Price (held += min(Price, Money − held − shown)),
	    пока у HUD есть CounterHold и до Celebrate этой суммы (шаг 1 берёт её отсюда).
	Атрибуты, которые читает: Player — Money, Income, DataMode; HUD — CounterHold, IntroAt. Remote:
	FishingState "Caught" (Tank.Result, Tank.Price — только для придержки). Соединения — один раз
	на сессию (HUD живёт всю игру).

	API:
	  MoneyController:Start(hud)
	  MoneyController.Celebrate(amount: number, from: GuiObject?, opts: { Rate: ("down" | "up")? }?)
	  MoneyController.Shown() -> number     -- число на надписи (тесты, сценарии)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local UIConfig = require(Config:WaitForChild("UIConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local TankConfig = require(Config:WaitForChild("TankConfig"))
local DataConfig = require(Config:WaitForChild("DataConfig"))
local TankRules = require(Shared:WaitForChild("TankRules"))
local Net = require(Shared:WaitForChild("Net"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))

export type CelebrateOptions = {
	Rate: ("down" | "up")?, -- куда катится доход «+$/с» вместе с праздником (продажа / замена)
}

local player = Players.LocalPlayer
local WALLET = UIConfig.Wallet
local Palette = UIConfig.Palette

-- Ширина знаков сумм в em (Montserrat Heavy = Black, курсив; сняты со шрифта tools/preview/fonts;
-- TextSize — высота строки = LINE em): узкие «1», «/», пробел у UiFx.textWidth шире, а строка
-- кошелька стоит по центру — ошибка в ширине сдвинула бы группу.
local GLYPHS: { [string]: number } = {
	["0"] = 0.692,
	["1"] = 0.418,
	["2"] = 0.608,
	["3"] = 0.614,
	["4"] = 0.712,
	["5"] = 0.619,
	["6"] = 0.661,
	["7"] = 0.645,
	["8"] = 0.678,
	["9"] = 0.661,
	["$"] = 0.658,
	["\u{00A0}"] = 0.3,
	[" "] = 0.3,
	["+"] = 0.62,
	["/"] = 0.44,
	["с"] = 0.628,
	["."] = 0.304,
	["M"] = 0.954,
	["B"] = 0.773,
	["T"] = 0.654,
	["Q"] = 0.848,
	["a"] = 0.7,
	["…"] = 0.922,
	["−"] = 0.62,
}
local LINE = 1.219 -- высота строки Montserrat в em (ascent + descent)
local ITALIC_SLACK = 1.06 -- наклон букв выступает вправо за их ширину
local ICON_GAP = 0.08 -- между 💵 и числом, высот строки
local LABEL_TALL = 0.92 -- коробка числа — почти вся строка (уведомления — сразу под ней)

local MoneyController = {}

local started = false
local hud: ScreenGui
local wallet: Frame
local money: Frame
local icon: GuiObject
local label: TextLabel
local back: GuiObject
local rate: TextLabel
local list: UIListLayout?

local shown = 0 -- число на надписи
local held = 0 -- зачислено, но ещё не отпраздновано
local counting: { target: number }? = nil -- идёт «набегание» к target
local rateShown = 0 -- доход на надписи, десятые монеты в секунду
local stopRate: (() -> ())? = nil
local state: "hidden" | "loading" | "ready" = "hidden"
local startedAt = 0
local memoryToast = false -- уведомление «прогресс не сохраняется» уже было
local soldToast = false -- «Садок полон…» уже было за эту игру
local floatChain = 0 -- поколение цепочки «+$13»
local lastParty = -math.huge -- os.clock() последнего праздника денег (Celebrate)

-- Придержка улова "replaced" / "sold" (до прилёта рыбы и Celebrate этой суммы).
type CatchHold = { amount: number, held: number, result: string }
local catchHold: CatchHold? = nil

local function number(value: any): number
	if typeof(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge then
		return value
	end
	return 0
end

local function moneyNow(): number
	return math.max(0, math.floor(number(player:GetAttribute("Money"))))
end

local function income10(): number
	return math.max(0, math.round(number(player:GetAttribute("Income")) * 10))
end

local function loaded(): boolean
	local mode = player:GetAttribute("DataMode")
	return mode == "Ready" or mode == "Memory"
end

local function holding(): boolean
	return hud:GetAttribute("CounterHold") ~= nil
end

-- Ширина строки суммы при размере текста px.
local function textWidth(text: string, px: number): number
	local units = 0
	for _, code in utf8.codes(text) do
		local ch = utf8.char(code)
		units += GLYPHS[ch] or 0.68
	end
	return units * px / LINE * ITALIC_SLACK
end

--------------------------------------------------------------------------------
-- Строка кошелька: 💵, число, промежуток, доход — по центру, по своему тексту
--------------------------------------------------------------------------------

local lastFit = ""
local floatOnHud: (text: string, at: Vector2, size: Vector2, o: { [string]: any }) -> ()
-- Строка, как её разложил layout (px от левого края кошелька): где кончается число и вся группа.
local fitted = { rowLeft = 0, labelRight = 0, rowRight = 0 }

local function setScale(gui: GuiObject, prop: string, value: UDim2)
	local now = (gui :: any)[prop] :: UDim2
	if
		math.abs(now.X.Scale - value.X.Scale) > 1e-3
		or math.abs(now.Y.Scale - value.Y.Scale) > 1e-3
		or now.X.Offset ~= value.X.Offset
		or now.Y.Offset ~= value.Y.Offset
	then
		(gui :: any)[prop] = value
	end
end

local function layout(force: boolean?)
	local size = wallet.AbsoluteSize
	local W, H = size.X, size.Y
	if W < 4 or H < 4 then
		return
	end
	local key = `{label.Text}|{if rate.Visible then rate.Text else ""}|{W}|{H}`
	if key == lastFit and not force then
		return
	end
	lastFit = key
	local iconSize = H * (if icon.Size.Y.Scale > 0 then icon.Size.Y.Scale else 1)
	local labelX = iconSize * WALLET.IconShare + H * ICON_GAP
	local fit = label:FindFirstChildOfClass("UITextSizeConstraint")
	local maxPx = if fit then fit.MaxTextSize else 48
	local px = math.min(maxPx, H * LABEL_TALL * WALLET.TextFill)
	local textW = textWidth(label.Text, px)
	local ratePx = math.min(UiFx.textSize("Button"), H * rate.Size.Y.Scale)
	local rateW = if rate.Visible then textWidth(rate.Text, ratePx) else 0
	local gap = if rate.Visible then H * WALLET.RowGap else 0
	local room = W - labelX - gap - rateW
	if textW > room then
		-- Тесно: число мельчает (TextScaled по коробке), не мельче MinMoney; и так не влезает —
		-- доход уходит (число важнее).
		local least = textWidth(label.Text, WALLET.MinMoney)
		if room < least and rate.Visible then
			rateW, gap = 0, 0
			room = W - labelX
		end
		textW = math.max(math.min(textW, room), least)
	end
	local moneyW = labelX + textW
	local left = (W - moneyW - gap - rateW) / 2 -- UIListLayout ставит группу по центру
	fitted.rowLeft = left
	fitted.labelRight = left + moneyW
	fitted.rowRight = left + moneyW + gap + rateW
	setScale(money, "Size", UDim2.fromScale(moneyW / W, 1))
	setScale(icon, "Position", UDim2.fromScale(iconSize * 0.5 / moneyW, 0.5))
	setScale(label, "Position", UDim2.fromScale(labelX / moneyW, 0.5))
	setScale(label, "Size", UDim2.fromScale(textW / moneyW, LABEL_TALL))
	if rate.Visible then
		setScale(rate, "Size", UDim2.fromScale(math.max(rateW, 1) / W, rate.Size.Y.Scale))
	end
	if list then
		local pad = UDim.new(gap / W, 0)
		if list.Padding ~= pad then
			list.Padding = pad
		end
	end
end

local function setMoneyText(value: number)
	local text = TankRules.FormatMoney(value)
	if label.Text ~= text then
		label.Text = text
		layout()
	end
end

--------------------------------------------------------------------------------
-- Число: тик раз в секунду (текст) и «набегание» праздника
--------------------------------------------------------------------------------

local function truth(): number
	return math.max(0, moneyNow() - held)
end

local function tick()
	if state ~= "ready" then
		return
	end
	local goal = truth()
	local run = counting
	if run then
		run.target = goal -- «набегание» само дойдёт до правды
		return
	end
	shown = goal
	setMoneyText(shown)
end

-- Число «набегает» от shown до правды (цель двигает тик) за time с; Quad Out, каждое новое
-- число подпрыгивает (≤ 12 Гц). Покадровая работа — только пока идёт.
local function countTo(time: number)
	local run = counting
	if run then
		run.target = truth()
		return
	end
	local mine = { target = truth() }
	counting = mine
	local from = shown
	local elapsed, lastBump = 0, -math.huge
	UiFx.schedule(function(dt: number): boolean
		if counting ~= mine then
			return false
		end
		elapsed += dt
		local k = math.min(1, elapsed / time)
		local eased = 1 - (1 - k) * (1 - k)
		local value = math.floor(from + (mine.target - from) * eased + 0.5)
		if value ~= shown then
			shown = value
			setMoneyText(shown)
			if elapsed - lastBump >= 1 / 12 then
				lastBump = elapsed
				UiFx.bump(label, 1.06, 0.1)
			end
		end
		return k < 1
	end, function()
		if counting == mine then
			counting = nil
			shown = mine.target
			setMoneyText(shown)
			tick() -- пока шло, правда могла уйти дальше
		end
	end)
end

--------------------------------------------------------------------------------
-- Доход «+$/с»
--------------------------------------------------------------------------------

local function rollRate(force: boolean?)
	local goal = income10()
	if state ~= "ready" then
		return
	end
	if holding() and not force then
		return -- улов летит в садок: доход катится, когда долетел
	end
	if goal == rateShown then
		if rate.Visible ~= (goal > 0) then
			rate.Visible = goal > 0
			rate.Text = TankRules.FormatRate(goal)
			layout()
		end
		return
	end
	local from = rateShown
	rateShown = goal
	if stopRate then
		stopRate()
		stopRate = nil
	end
	if goal <= 0 then
		rate.Visible = false
		layout()
		return
	end
	local appear = not rate.Visible
	rate.Visible = true
	rate.Text = TankRules.FormatRate(goal)
	layout(true)
	if appear then
		UiFx.popIn(rate, { from = 0.4, time = 0.3 })
		return
	end
	stopRate = UiFx.countUp(rate, from, goal, WALLET.RateRoll, function(value: number): string
		return TankRules.FormatRate(value)
	end)
	UiFx.flashText(rate, if goal < from then Palette.Berry.Bottom else Palette.Gold.Top, 0.4)
	UiFx.bump(rate, if goal < from then 1.08 else 1.14, 0.3)
end

--------------------------------------------------------------------------------
-- «+$13» раз в FloatEvery секунд (цепочка таймеров, пока кошелёк виден и есть доход)
--------------------------------------------------------------------------------

local function floatIncome()
	local tenths = income10()
	if
		tenths <= 0
		or not wallet.Visible
		or state ~= "ready"
		or catchHold
		or os.clock() - lastParty < WALLET.FloatQuiet
	then
		return -- (и пока ждут или летят 💵 улова — праздник не перебивать)
	end
	local text = TankRules.FormatRate(tenths)
	text = string.sub(text, 1, #text - #EconomyConfig.Format.Rate) -- «+$13/с» → «+$13»
	-- Справа от строки (от правого края дохода), чуть выше середины; поднимается и тает.
	local H = math.max(wallet.AbsoluteSize.Y, 1)
	local h = H * WALLET.FloatSize
	local w = textWidth(text, h)
	floatOnHud(text, Vector2.new(fitted.rowRight + w * 0.5 + H * 0.12, H * 0.35), Vector2.new(w, h), {
		color = UIConfig.MoneyText,
		rise = WALLET.FloatRise * H,
		time = WALLET.FloatTime,
		rotate = 6,
	})
end

local function startFloats()
	floatChain += 1
	local mine = floatChain
	local function step()
		if floatChain ~= mine or state ~= "ready" then
			return
		end
		if not holding() then
			floatIncome()
		end
		task.delay(WALLET.FloatEvery, step)
	end
	task.delay(WALLET.FloatEvery, step)
end

--------------------------------------------------------------------------------
-- Праздник денег
--------------------------------------------------------------------------------

local function coinsFor(amount: number): number
	local spec = WALLET.Coins
	local k = math.clamp(math.log10(math.max(amount, 1)) / 4, 0, 1)
	return math.floor(spec.Min + (spec.Max - spec.Min) * k + 0.5)
end

local function countTime(amount: number): number
	local spec = WALLET.Count
	return spec.Min + (spec.Max - spec.Min) * math.clamp(amount / WALLET.CountBig, 0, 1)
end

-- Всплывающая надпись у кошелька: на слое HUD (в самом кошельке её поставил бы в ряд его
-- UIListLayout); at — середина надписи в px от левого верхнего угла кошелька, rise — px.
function floatOnHud(text: string, at: Vector2, size: Vector2, o: { [string]: any })
	local area = hud.AbsoluteSize
	local W, Hh = math.max(area.X, 1), math.max(area.Y, 1)
	-- (кошелёк стоит по центру стопки статуса: x — от её середины, так и в RbxSim, который
	-- выравнивание UIListLayout не считает)
	local status = wallet.Parent :: GuiObject
	local left = status.AbsolutePosition.X + (status.AbsoluteSize.X - wallet.AbsoluteSize.X) / 2
	local origin = Vector2.new(left, wallet.AbsolutePosition.Y) - hud.AbsolutePosition
	local center = origin + at
	UiFx.floatText(hud, text, {
		position = UDim2.fromScale(center.X / W, center.Y / Hh),
		size = UDim2.fromScale(size.X / W, size.Y / Hh),
		color = o.color,
		colors = o.colors,
		rise = (o.rise or 0) / Hh,
		time = o.time,
		rotate = o.rotate,
		z = 9,
	})
end

-- Золотое «+$1 234» слева от 💵 (уровень Button; над строкой — плашка базы, туда не поднимается).
local function floatAmount(amount: number)
	local text = "+" .. TankRules.FormatMoney(amount)
	local H = math.max(wallet.AbsoluteSize.Y, 1)
	local px = math.max(UiFx.textSize("Button"), H * 0.7)
	local w = textWidth(text, px)
	floatOnHud(text, Vector2.new(fitted.rowLeft - w * 0.5 - H * 0.15, H * 0.5), Vector2.new(w, px), {
		colors = { Palette.Gold.Top, Palette.Sun.Bottom },
		rise = H * WALLET.FloatRise,
		time = 1.0,
		rotate = -4,
	})
end

function MoneyController.Celebrate(amount: number, from: GuiObject?, _opts: CelebrateOptions?)
	if not started then
		return
	end
	local whole = math.floor(number(amount))
	if whole <= 0 then
		return
	end
	-- 1) придержать: часть улова — оттуда, остальное — что надпись ещё не показала
	local mine = 0
	local hold = catchHold
	if hold and hold.amount == whole then
		mine = hold.held
		catchHold = nil
	end
	local free = math.max(0, moneyNow() - held - shown)
	local extra = math.min(whole - mine, free)
	held += extra
	mine += extra
	lastParty = os.clock() -- (пока 💵 летят, «+$13» дохода не всплывает)
	local landed = false
	local function land()
		if landed then
			return
		end
		landed = true
		lastParty = os.clock()
		held = math.max(0, held - mine)
		if state ~= "ready" then
			tick()
			return
		end
		countTo(countTime(whole))
		UiFx.flashText(label, Palette.Gold.Top, 0.45)
		UiFx.bump(money, 1.12, 0.3)
		floatAmount(whole)
		UiFx.sound("ping", 0.35, 1.25)
	end
	-- 2) 💵 летят из from в кошелёк (не видно кошелька или источника — сразу счёт)
	if from and from.Parent and from.Visible and wallet.Visible and state == "ready" then
		UiFx.flyTo(hud, from, icon, {
			text = "💵",
			count = coinsFor(whole),
			time = 0.5,
			size = 0.07,
			arc = 0.14,
			onEach = function(index: number)
				if index == 1 then
					land()
				end
				UiFx.sound("tick", 0.2, 1.1 + 0.05 * index)
			end,
			onArrive = land,
		})
	else
		land()
	end
end

function MoneyController.Shown(): number
	return shown
end

--------------------------------------------------------------------------------
-- Придержка улова
--------------------------------------------------------------------------------

local arrived: (hold: CatchHold) -> ()

local function dropHold()
	local hold = catchHold
	if hold then
		catchHold = nil
		held = math.max(0, held - hold.held)
		tick()
	end
end

local function onCaught(data: any)
	if typeof(data) ~= "table" or typeof(data.Tank) ~= "table" then
		return
	end
	local result = data.Tank.Result
	local price = math.floor(number(data.Tank.Price))
	if (result ~= "replaced" and result ~= "sold") or price <= 0 then
		return
	end
	dropHold() -- прошлый улов (редко: два подряд) — отпустить
	local take = math.min(price, math.max(0, moneyNow() - held - shown))
	held += take
	local hold: CatchHold = { amount = price, held = take, result = result }
	catchHold = hold
	-- Нет карточки (FishingController не поставил CounterHold) — как будто рыба уже долетела.
	task.defer(function()
		if catchHold == hold and not holding() then
			arrived(hold)
		end
	end)
end

-- Рыба долетела: "sold" — счёт (💵 уже сел в кошелёк) и первый раз за игру — «Садок полон…»;
-- "replaced" — ждём Celebrate от TankButtonController (не позвал за HoldRelease с — отпустить).
function arrived(hold: CatchHold)
	if hold.result == "sold" then
		MoneyController.Celebrate(hold.amount, nil) -- (берёт придержанное как своё)
		if not soldToast then
			soldToast = true
			NotifyController.Show(TankConfig.Texts.FullSold, "warning", { icon = "💵" })
		end
	else
		task.delay(WALLET.HoldRelease, function()
			if catchHold == hold then
				dropHold()
			end
		end)
	end
end

local function onHoldChanged()
	if holding() then
		return
	end
	rollRate(true)
	local hold = catchHold
	if hold then
		arrived(hold)
	else
		tick()
	end
end

--------------------------------------------------------------------------------
-- Показ: загрузка, «стекло», появление после баннера
--------------------------------------------------------------------------------

local function introAt(): number?
	local value = hud:GetAttribute("IntroAt")
	return if typeof(value) == "number" then value else nil
end

local function popWallet(delay: number)
	wallet.Visible = true
	UiFx.popIn(wallet, { from = WALLET.PopFrom, time = WALLET.PopTime, delay = delay })
	UiFx.popIn(icon, { from = 0, time = WALLET.PopTime, delay = delay + 0.08, rotate = WALLET.IconSpin })
end

local function refresh()
	local intro = introAt()
	if intro == nil then
		return -- баннер базы ещё не долетел в плашку
	end
	local delay = math.max(0, intro + WALLET.IntroGap - os.clock())
	if loaded() then
		if state == "ready" then
			return
		end
		local was = state
		state = "ready"
		back.Visible = false
		held = 0
		shown = moneyNow()
		lastFit = ""
		setMoneyText(shown)
		rateShown = 0
		rate.Visible = false
		rollRate(true)
		layout(true)
		if was == "hidden" then
			popWallet(delay)
		else
			UiFx.punch(money, { from = 0.9, peak = 1.12 }) -- «стекло» сменилось числом
		end
		startFloats()
		if player:GetAttribute("DataMode") == "Memory" and not memoryToast then
			memoryToast = true
			task.delay(delay + 0.4, function()
				NotifyController.Show(DataConfig.Texts.MemoryToast, "warning")
			end)
		end
	elseif state == "hidden" and os.clock() - startedAt >= WALLET.LoadingAfter - 1e-3 then
		state = "loading"
		back.Visible = true
		rate.Visible = false
		label.Text = EconomyConfig.Format.Loading
		lastFit = ""
		layout(true)
		popWallet(delay)
	end
end

function MoneyController:Start(screen: ScreenGui)
	hud = screen
	local status = hud:WaitForChild("Status")
	wallet = status:WaitForChild("Wallet") :: Frame
	money = wallet:WaitForChild("Money") :: Frame
	icon = money:WaitForChild("Icon") :: GuiObject
	label = money:WaitForChild("Label") :: TextLabel
	back = money:WaitForChild("Back") :: GuiObject
	rate = wallet:WaitForChild("Rate") :: TextLabel
	list = wallet:FindFirstChildOfClass("UIListLayout")
	started = true
	startedAt = os.clock()
	wallet.Visible = false
	back.Visible = false
	rate.Visible = false

	player.AttributeChanged:Connect(function(name: string)
		if name == "Money" then
			-- Через кадр: "Caught" (тот же кадр) успевает придержать сумму улова.
			task.defer(tick)
		elseif name == "Income" then
			task.defer(function()
				rollRate(false)
			end)
		elseif name == "DataMode" then
			refresh()
		end
	end)
	hud.AttributeChanged:Connect(function(name: string)
		if name == "CounterHold" then
			onHoldChanged()
		elseif name == "IntroAt" then
			refresh()
		end
	end)
	wallet:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		layout()
	end)
	Net.Event("FishingState").OnClientEvent:Connect(function(kind: any, data: any)
		if kind == "Caught" then
			onCaught(data)
		end
	end)
	task.delay(WALLET.LoadingAfter, refresh)
	refresh()
end

return MoneyController
