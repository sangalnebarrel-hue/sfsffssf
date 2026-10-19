--!strict
--[[
	DefenceCards — лист «ЗАЩИТА» (Этап 4; помощник DefenceController — модуль, не контроллер):
	HUD.DefencePanel (оболочка tools/builder/gui/Sheet.luau + карточки tools/builder/gui/Defence.luau)
	— шапка 🛡️ «ЗАЩИТА» с кошельком «💵 $12 345» (стекло) и четыре карточки в один ряд: ShieldCard,
	DogCard, AlarmCard, LockCard (docs/stage4_design.md §6.6). Лист открывает, раскладывает и
	закрывает помощник Controllers.Sheet (один лист на экране: открыли «ЗАЩИТА» — садок ушёл сам);
	его числа места — DefenceConfig.Panel (недостающие — TankConfig.Panel); тексты —
	DefenceConfig.Texts.

	Карточки (один ряд; ширина / высота — Panel.CardAspect, не уже Panel.CardMin px; на маленьком
	телефоне четвёртая листается: явный CanvasSize, как у садка; на планшете и ПК все в листе, выше
	— до Panel.CardAspectTall: крупному тексту там нужно место, — лист — не выше них). Карточка
	раскладывается в px снизу вверх (как карточки садка): кнопка Buy — у низа (≥ 44 px), строка
	действия Effect — всё место между именем и кнопкой; её строки (UiFx.textWidth, перенос по
	пробелам, при наименьшем размере текста) не влезают — сперва меньше кружок-значок (до
	DISC_MIN), потом короткая строка EffectShort (DefenceConfig.Texts.Cards). Кнопка Buy каждой
	карточки — одно из (UiFx.setCandy + подпись):
	  ЩИТ:  Guard «ВКЛЮЧИТЬ» — когда сервер примет (сам не крадёшь, защиты меньше
	        Shield.StackBelow с, щит готов; DC-03) → нажатие — ShieldActivate (opts.onShield), «⏳» до
	        ответа; у тебя крадут (атрибут HUD AlertPhase) — та же кнопка Berry «ЩИТ!» с красными
	        кольцами (лист открыт — плашки тревоги нет: эта кнопка и есть ЩИТ); щит включён —
	        стекло «🛡️ 0:42»; перезарядка — Slate «⏳ 2:59» с кольцом-таймером (нажатие — качается и
	        «Щит перезаряжается — ещё …»); защищён другим видом ≥ StackBelow — стекло «ТЫ ПОД
	        ЗАЩИТОЙ»; крадёшь сам — Slate «ПОСЛЕ КРАЖИ» (нажатие качается: сервер откажет).
	  СОБАКА / СИГНАЛИЗАЦИЯ / ЗАМОК: Gold «💵 $6 000» → первое нажатие — Berry «КУПИТЬ?» с кольцом
	        TankConfig.ConfirmTime с; второе — не раньше ConfirmArm после предыдущего (раньше — отсчёт
	        заново, кнопка качается: «барабанить» не покупает) → DefenceBuy(item), «⏳» до ответа
	        (нет ответа Panel.SellWait садка — назад); не хватает денег — Slate с той же ценой
	        (читается), нажатие — качается и прямо на кнопке «ЕЩЁ $3 000» Panel.NeedTime с (под
	        пальцем; уведомления нет — оно легло бы на шапку листа с кошельком); куплено — штамп
	        Leaf «КУПЛЕНО» (замок: строка действия — «Сильнее замки — скоро в магазине», DC-11;
	        Lock.SaleMax = 0 — карточки замка нет). Имя «СИГНАЛИЗАЦИЯ» не влезает — «СИГНАЛКА».
	  Ответ "Bought" — штамп «КУПЛЕНО», конфетти над карточкой, MoneyController.Spend(цена, кнопка)
	  (💵 летят из кошелька в карточку, «−$6 000»), уведомление «Собака охраняет твой двор!»
	  (значок — Texts.Cards[предмет].Icon); "Denied" — карточка качается (текст показывает
	  DefenceController).
	Живые числа (таймер щита, «хватает ли денег», кошелёк шапки) — одна цепочка task.delay раз в
	секунду, пока лист открыт, и сразу по атрибутам игрока и тревоги HUD; всё, что живёт при
	открытом листе, — в его Trove: закрыт — соединений как до открытия.

	API:
	  DefenceCards.new(hud, root, { onShield: (from: GuiObject) -> () }) -> Cards
	  DefenceCards.Cheapest(player) -> number?   -- цена самой дешёвой некупленной защиты (nil — всё есть)
	  cards:Open() -> boolean, cards:Close(reason?), cards:IsOpen() -> boolean
	  cards:ShieldAnswered(ok), cards:Bought(payload), cards:Denied(item)
	  cards:Stats() -> { open, confirm, busy, looks = { Shield = "on", Dog = "price", … }, ticking }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local DefenceConfig = require(Config:WaitForChild("DefenceConfig"))
local StealConfig = require(Config:WaitForChild("StealConfig"))
local TankConfig = require(Config:WaitForChild("TankConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local Net = require(Shared:WaitForChild("Net"))
local StealRules = require(Shared:WaitForChild("StealRules"))
local TankRules = require(Shared:WaitForChild("TankRules"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Controllers = script.Parent
local Sheet = require(Controllers:WaitForChild("Sheet"))
local NotifyController = require(Controllers:WaitForChild("NotifyController"))

local player = Players.LocalPlayer
local TEXTS = DefenceConfig.Texts
local BUY = TEXTS.Buy
local SHIELD = DefenceConfig.Shield
local LOCK = DefenceConfig.Lock
local PANEL = DefenceConfig.Panel
local TANK_PANEL = TankConfig.Panel
local Palette = UIConfig.Palette
local BOTTOM = 0.03 -- под рядом карточек — столько их высоты (обводка не обрезается)
local RING_Z = 8 -- кольцо «КУПИТЬ?» / перезарядки — над лицом и подписью кнопки
-- Карточка в долях её высоты (gui/Defence.luau): кружок-значок (Disc; тесно — до DiscMin), верх
-- кружка, кнопка Buy (не ниже BuyMin px) и её низ, имя (не ниже NAME_LINE его текста), зазор; над
-- кнопкой ещё BuyInk px (её толстая обводка и «губа» выступают за коробку); строка текста — LINE
-- его размера (как считает перенос Roblox, с обводкой букв)
local CARD = {
	Disc = 0.23,
	DiscMin = 0.15,
	Top = 0.03,
	Buy = 0.245,
	BuyMin = 44,
	BuyInk = 5,
	Foot = 0.965,
	Name = 0.12,
	Gap = 0.015,
}
local NAME_LINE = 1.25
local LINE = 1.25
local ALERT_RING = { Scale = 1.15, Thickness = 4, Time = 0.6, Every = 0.9 } -- кольца «ЩИТ!» на карточке
-- Штамп «✔️ КУПЛЕНО»: уже кнопки (доля ширины карточки) и ниже (доля высоты Buy), наклон, °
local STAMP = { Width = 0.8, Height = 0.86, Tilt = -3 }
local ALERT_TEXTS = StealConfig.Texts.Alert -- шапка листа во время тревоги: «🚨 ВОР В САДКЕ!»
local HEAD_PAD = 8 -- надпись шапки шире своего текста на столько px

-- Числа места листа: DefenceConfig.Panel, недостающие — как у садка (TankConfig.Panel).
local LAYOUT: { [string]: any } = setmetatable(table.clone(PANEL :: any), { __index = TANK_PANEL }) :: any

type Card = {
	key: string, -- "Shield" | "Dog" | "Alarm" | "Lock"
	frame: GuiObject,
	name: TextLabel?,
	effect: TextLabel?,
	state: TextLabel?,
	buy: GuiButton,
	label: TextLabel?,
	price: TextLabel?,
	disc: GuiObject?,
	look: string,
	ring: (() -> ())?,
	ringFor: number?, -- до какого времени тикает кольцо перезарядки
	glow: (() -> ())?, -- красные кольца «ЩИТ!» (тревога)
	needUntil: number, -- «ЕЩЁ $3 000» на кнопке до этого os.clock()
	effectText: string?, -- что сейчас в строке действия (её раскладка)
	buyWidth: number, -- ширина кнопки (доля карточки) — штамп «КУПЛЕНО» уже
	buyHeight: number?, -- высота кнопки по раскладке (доля карточки) — штамп ниже
}

export type Cards = {
	Open: (self: Cards) -> boolean,
	Close: (self: Cards, reason: string?) -> (),
	IsOpen: (self: Cards) -> boolean,
	ShieldAnswered: (self: Cards, ok: boolean) -> (),
	Bought: (self: Cards, payload: { [string]: any }) -> (),
	Denied: (self: Cards, item: string) -> (),
	Stats: (self: Cards) -> { [string]: any },
}

local DefenceCards = {}

local function numberAttr(inst: Instance?, name: string): number?
	local value = if inst then inst:GetAttribute(name) else nil
	return if typeof(value) == "number" and value == value then value else nil
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function cancel(thread: thread?)
	if thread and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
end

local function owned(item: string): boolean
	if item == "Dog" then
		return player:GetAttribute("HasDog") == true
	elseif item == "Alarm" then
		return player:GetAttribute("HasAlarm") == true
	elseif item == "Lock" then
		local hold = StealRules.NextLock(player:GetAttribute("LockLevel"), LOCK.SaleMax)
		return hold == nil
	end
	return false
end

-- Цена предмета сейчас (nil — куплен / не продаётся).
local function priceOf(item: string): number?
	if item == "Dog" then
		return if owned("Dog") then nil else DefenceConfig.Dog.Price
	elseif item == "Alarm" then
		return if owned("Alarm") then nil else DefenceConfig.Alarm.Price
	elseif item == "Lock" then
		local hold, price = StealRules.NextLock(player:GetAttribute("LockLevel"), LOCK.SaleMax)
		return if hold then price :: number else nil
	end
	return nil
end

-- Самая дешёвая защита, которой нет (nil — всё куплено): «!» на кнопке, совет после кражи.
function DefenceCards.Cheapest(_who: Player?): number?
	local best: number? = nil
	for _, item in { "Lock", "Alarm", "Dog" } do
		local price = priceOf(item)
		if price and (best == nil or price < best) then
			best = price
		end
	end
	return best
end

-- Самая дешёвая некупленная защита: (предмет, цена) или nil (совет после кражи, DC-14).
function DefenceCards.CheapestItem(): (string?, number?)
	local bestItem: string?, best: number? = nil, nil
	for _, item in { "Lock", "Alarm", "Dog" } do
		local price = priceOf(item)
		if price and (best == nil or price < best) then
			bestItem, best = item, price
		end
	end
	return bestItem, best
end

local function money(): number
	return math.floor(numberAttr(player, "Money") or 0)
end

-- Сколько строк займёт text в коробке box px при размере px (перенос по пробелам, как
-- TextWrapped; неразрывный пробел «1 минуту» слова не делит).
local function lineCount(text: string, px: number, box: number): number
	local lines, line = 1, 0
	local space = UiFx.textWidth(" ", px)
	for word in string.gmatch(text, "%S+") do
		local w = UiFx.textWidth(word, px)
		if line == 0 then
			line = w
		elseif line + space + w <= box then
			line += space + w
		else
			lines += 1
			line = w
		end
	end
	return lines
end
DefenceCards.LineCount = lineCount

-- Строка действия карточки: (полная, короткая). Замок куплен — «Сильнее замки — скоро в магазине».
local function effectTexts(key: string): (string, string)
	local spec = (TEXTS.Cards :: any)[key]
	if key == "Lock" then
		local level = numberAttr(player, "LockLevel") or 0
		local hold = StealRules.NextLock(level, LOCK.SaleMax)
		if level > 0 and hold == nil then
			return TEXTS.LockSoon, TEXTS.LockSoonShort
		end
		local values = { new = hold or LOCK.Levels[1].Hold, old = StealRules.HoldTime(level) }
		return TextUtil.fill(spec.Effect, values), TextUtil.fill(spec.EffectShort or spec.Effect, values)
	end
	return spec.Effect, spec.EffectShort or spec.Effect
end

local function ownBase(): Instance?
	local index = numberAttr(player, "BaseIndex")
	local bases = Workspace:FindFirstChild("Bases")
	return if index and index > 0 and bases then bases:FindFirstChild(`Base_{index}`) else nil
end

-- Сколько с защиты своей базы осталось (0 — нет).
local function protectLeft(): number
	local untilAt = numberAttr(ownBase(), "ProtectUntil")
	return if untilAt then math.max(untilAt - now(), 0) else 0
end

local function moneyModule(): any
	-- MoneyController — через require в миг вызова (не на загрузке: его модуль может ждать нас).
	local module = Controllers:FindFirstChild("MoneyController")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, found = pcall(function(): any
		return (require :: any)(module)
	end)
	return if ok then found else nil
end

function DefenceCards.new(hud: ScreenGui, root: GuiObject, opts: { onShield: (from: GuiObject) -> () }): Cards
	local panel = root:WaitForChild("Panel")
	local header = panel:WaitForChild("Header") :: GuiObject
	local frame = panel:WaitForChild("Cards") :: ScrollingFrame
	local grid = frame:FindFirstChildOfClass("UIGridLayout")
	local padding = frame:FindFirstChildOfClass("UIPadding")
	local headIcon = header:FindFirstChild("Icon") :: GuiObject?
	local moneyChip = header:FindFirstChild("Money")
	local moneyLabel = if moneyChip then moneyChip:FindFirstChild("Label") :: TextLabel? else nil
	local close = panel:WaitForChild("Close") :: GuiButton

	local cards: { [string]: Card } = {}
	local order = { "Shield", "Dog", "Alarm", "Lock" }
	for _, key in order do
		local cardFrame = frame:WaitForChild(`{key}Card`) :: GuiObject
		local buy = cardFrame:WaitForChild("Buy") :: GuiButton
		cards[key] = {
			key = key,
			frame = cardFrame,
			name = cardFrame:FindFirstChild("Name") :: TextLabel?,
			effect = cardFrame:FindFirstChild("Effect") :: TextLabel?,
			state = cardFrame:FindFirstChild("State") :: TextLabel?,
			buy = buy,
			label = buy:FindFirstChild("Label") :: TextLabel?,
			price = buy:FindFirstChild("Price") :: TextLabel?,
			disc = cardFrame:FindFirstChild("Icon") :: GuiObject?,
			look = "",
			needUntil = 0,
			buyWidth = buy.Size.X.Scale,
		}
	end
	-- Lock.SaleMax = 0 — замков в продаже нет: карточки нет (Этап 5 поднимет SaleMax).
	cards.Lock.frame.Visible = LOCK.SaleMax > 0

	local open = false
	local trove = Trove.new() -- живёт, пока лист открыт
	local ticker: thread? = nil
	local confirm: Card? = nil
	local confirmAt = 0
	local confirmEnd: thread? = nil
	local confirmRing: (() -> ())? = nil
	local busy: Card? = nil
	local busyWait: thread? = nil
	local cell = Vector2.new(117, 150)
	local sheet: Sheet.Sheet

	local function visibleCards(): { Card }
		local list = {}
		for _, key in order do
			local card = cards[key]
			if card.frame.Visible then
				table.insert(list, card)
			end
		end
		return list
	end

	------------------------------------------------------------------------------
	-- Раскладка (Sheet зовёт при открытии и смене экрана)
	------------------------------------------------------------------------------

	local function cardHeight(cardsH: number): number
		return cardsH / (1 + LAYOUT.Overhang + BOTTOM)
	end

	local function contentWidth(cardsH: number, _tall: boolean): (number, number)
		local n = math.max(#visibleCards(), 1)
		local cw = math.max(cardHeight(cardsH) * LAYOUT.CardAspect, LAYOUT.CardMin)
		local rim = ((n - 1) * LAYOUT.Gap + 2 * LAYOUT.Side) * cw
		local width = n * cw + rim
		return width, width
	end

	-- Планшет, ПК: все карточки в ряд по ширине окна cardsW — и выше (до CardAspectTall), чтобы
	-- крупный текст влез; лист — не выше нужного им (Sheet: contentHeight).
	local function tallWidth(cardsW: number): number
		local n = math.max(#visibleCards(), 1)
		return math.max(cardsW / (n + (n - 1) * LAYOUT.Gap + 2 * LAYOUT.Side), LAYOUT.CardMin)
	end

	local function contentHeight(cardsW: number, tall: boolean): number?
		if not tall then
			return nil
		end
		return tallWidth(cardsW) / LAYOUT.CardAspectTall * (1 + LAYOUT.Overhang + BOTTOM)
	end

	-- «СИГНАЛИЗАЦИЯ» не влезает в строку имени карточки шириной w px — «СИГНАЛКА» (DC-13).
	local function fitNames(w: number)
		for _, card in cards do
			local nameLabel = card.name
			local spec = (TEXTS.Cards :: any)[card.key]
			if nameLabel and spec then
				local box = nameLabel.Size.X.Scale * w
				local least = UiFx.textSize("Small") - 2
				local short = (spec :: any).Short
				nameLabel.Text = if short and UiFx.textWidth(spec.Name, least) > box then short else spec.Name
			end
		end
	end

	-- Карточка cw × ch px снизу вверх: кнопка у низа, кружок и имя сверху, строке действия — всё
	-- между ними; её строки не влезают — кружок меньше (до DiscMin), потом короткая строка.
	-- Ряд (layoutCards): кружок у всех карточек один — самый маленький из нужных.
	type Plan = { text: string, disc: number }
	local function metrics(ch: number): (number, number, number, number, number, number)
		local small = UiFx.textSize("Small")
		local px = math.max(small - 2, 12) -- (наименьший размер, что даст UiFx.fitText)
		local gap = math.max(CARD.Gap * ch, 2)
		local buyH = math.max(CARD.Buy * ch, CARD.BuyMin)
		local buyTop = CARD.Foot * ch - buyH - CARD.BuyInk -- (низ строки действия — над обводкой кнопки)
		local nameH = math.max(CARD.Name * ch, small * NAME_LINE)
		return px, gap, buyH, buyTop, nameH, CARD.Top * ch
	end

	local function planCard(card: Card, cw: number, ch: number): Plan?
		local effect = card.effect
		if cw <= 1 or ch <= 1 or not effect then
			return nil
		end
		local px, gap, _, buyTop, nameH, top = metrics(ch)
		local box = effect.Size.X.Scale * cw
		local full, short = effectTexts(card.key)
		-- самый большой кружок, при котором строке действия хватает места
		local function discFor(text: string): number
			local need = lineCount(text, px, box) * px * LINE
			return buyTop - top - 3 * gap - nameH - need
		end
		local disc = discFor(full)
		if disc >= CARD.DiscMin * ch then
			return { text = full, disc = math.min(disc, CARD.Disc * ch) }
		end
		return { text = short, disc = math.clamp(discFor(short), CARD.DiscMin * ch, CARD.Disc * ch) }
	end

	local function applyCard(card: Card, cw: number, ch: number, plan: Plan, disc: number)
		local effect = card.effect
		if not effect then
			return
		end
		local _, gap, buyH, buyTop, nameH, top = metrics(ch)
		local discEl = card.disc
		if discEl then
			discEl.Position = UDim2.fromScale(0.5, top / ch)
			discEl.Size = UDim2.fromScale(disc / ch, disc / ch) -- (RelativeYY: доли высоты)
		end
		local nameTop = top + disc + gap
		local nameLabel = card.name
		if nameLabel then
			nameLabel.Position = UDim2.fromScale(0.5, nameTop / ch)
			nameLabel.Size = UDim2.fromScale(nameLabel.Size.X.Scale, nameH / ch)
		end
		local effectTop = nameTop + nameH + gap
		effect.Position = UDim2.fromScale(0.5, effectTop / ch)
		effect.Size = UDim2.fromScale(effect.Size.X.Scale, math.max(buyTop - gap - effectTop, 1) / ch)
		effect.Text = plan.text
		card.effectText = plan.text
		local buyShare = buyH / ch
		card.buyHeight = buyShare
		card.buy.Size =
			UDim2.fromScale(card.buy.Size.X.Scale, buyShare * (if card.look == "bought" then STAMP.Height else 1))
		if card.state then
			card.state.Visible = false -- (купленный замок пишет своё в строке действия)
		end
	end

	local function layoutCards()
		local cw, ch = cell.X, cell.Y
		local plans: { [Card]: Plan } = {}
		local disc = CARD.Disc * ch
		for _, card in cards do
			local plan = planCard(card, cw, ch)
			if plan then
				plans[card] = plan
				if card.frame.Visible then
					disc = math.min(disc, plan.disc)
				end
			end
		end
		for card, plan in plans do
			applyCard(card, cw, ch, plan, disc)
		end
	end

	local function onPlace(fit: Sheet.Fit)
		local grid, padding = grid, padding
		if not grid or not padding then
			return
		end
		local n = math.max(#visibleCards(), 1)
		local windowW, windowH = math.max(fit.cards.X, 1), math.max(fit.cards.Y, 1)
		local ch = cardHeight(fit.cards.Y)
		local cw = math.max(ch * LAYOUT.CardAspect, LAYOUT.CardMin)
		if fit.tall then
			-- планшет, ПК: все карточки — в листе, выше обычного (до CardAspectTall: крупный текст;
			-- Sheet уже сделал лист ниже — по ним)
			cw = math.min(cw, tallWidth(windowW))
			ch = math.min(ch, cw / LAYOUT.CardAspectTall)
		end
		local gap, side = LAYOUT.Gap * cw, LAYOUT.Side * cw
		local top = LAYOUT.Overhang * ch
		local bottom = math.max(windowH - top - ch, BOTTOM * ch)
		local content = 2 * side + n * cw + (n - 1) * gap
		-- (+1 px: сетка кладёт в ряд ровно n карточек и с ошибкой округления)
		local canvasW = math.max(windowW, content + 1)
		frame.CanvasSize = UDim2.fromScale(canvasW / windowW, 1)
		padding.PaddingLeft = UDim.new(side / canvasW, 0)
		padding.PaddingRight = UDim.new(side / canvasW, 0)
		padding.PaddingTop = UDim.new(top / windowH, 0)
		padding.PaddingBottom = UDim.new(bottom / windowH, 0)
		local innerW, innerH = math.max(canvasW - 2 * side, 1), math.max(windowH - top - bottom, 1)
		grid.CellSize = UDim2.fromScale(cw / innerW, ch / innerH)
		grid.CellPadding = UDim2.fromScale(gap / innerW, 0)
		grid.FillDirection = Enum.FillDirection.Horizontal
		grid.FillDirectionMaxCells = 0
		frame.CanvasPosition = Vector2.new(math.min(frame.CanvasPosition.X, math.max(canvasW - windowW, 0)), 0)
		cell = Vector2.new(cw, ch)
		fitNames(cw)
		layoutCards()
	end

	------------------------------------------------------------------------------
	-- Вид кнопки карточки
	------------------------------------------------------------------------------

	local function stopRing(card: Card)
		local ring = card.ring
		card.ring = nil
		card.ringFor = nil
		if ring then
			ring()
		end
	end

	-- look: "on" | "alert" | "active" | "wait" | "protected" | "after" | "price" | "poor" | "need" |
	-- "confirm" | "busy" | "bought"
	local TOKENS: { [string]: string } = {
		on = "Guard",
		alert = "Berry",
		after = "Slate",
		need = "Slate",
		active = "Glass",
		wait = "Slate",
		protected = "Glass",
		price = "Gold",
		poor = "Slate",
		confirm = "Berry",
		busy = "Slate",
		bought = "Leaf",
	}

	local function stopGlow(card: Card)
		local glow = card.glow
		card.glow = nil
		if glow then
			glow()
		end
	end

	-- «✔️ КУПЛЕНО» — штамп, а не кнопка: плоское лицо без блика и светлого ободка (после
	-- setCandy), уже кнопки, чуть наклонён (нажатие только качает его); off — ширина и наклон
	-- кнопки (цвет, ободок и градиент вернёт setCandy другого вида)
	local function stampLook(card: Card, on: boolean)
		local buy = card.buy
		if on then
			local face = UiFx.faceOf(buy)
			local shine = face:FindFirstChild("Shine")
			if shine and shine:IsA("GuiObject") then
				shine.Visible = false
			end
			local rim = face:FindFirstChild("Rim")
			local ring = if rim then rim:FindFirstChildOfClass("UIStroke") else nil
			if ring then
				ring.Transparency = 1
			end
			local fill = face:FindFirstChild("Fill")
			if fill and fill:IsA("UIGradient") then
				fill.Color = ColorSequence.new(Palette.Leaf.Bottom)
			end
		end
		local label = card.label
		if label then
			label.TextWrapped = not on -- (штамп — одна строка «✔️ КУПЛЕНО», мельче, но не в две)
		end
		local height = card.buyHeight or buy.Size.Y.Scale
		buy.Size = UDim2.fromScale(if on then STAMP.Width else card.buyWidth, height * (if on then STAMP.Height else 1))
		buy.Rotation = if on then STAMP.Tilt else 0
	end

	local function setLook(card: Card, look: string, text: string, priceText: string?)
		if card.look ~= look then
			local before = card.look
			card.look = look
			UiFx.recolor(card.buy, TOKENS[look] or "Slate", if look == "bought" then 0 else nil)
			if look == "bought" then
				stampLook(card, true)
			elseif card.buy.Rotation ~= 0 or card.buy.Size.X.Scale ~= card.buyWidth then
				stampLook(card, false)
			end
			if look == "active" and (before == "busy" or before == "alert") and open then
				UiFx.punch(card.buy, { from = 0.8, peak = 1.12 }) -- щит включился отсюда
			end
			if look ~= "wait" and look ~= "confirm" then
				stopRing(card)
			end
			stopGlow(card)
			if look == "alert" and open then
				-- у тебя крадут: эта кнопка — ЩИТ (красные кольца, как у «ЩИТ!» в колонке)
				card.glow = UiFx.glowRing(card.buy, {
					color = Palette.Berry.Top,
					scale = ALERT_RING.Scale,
					thickness = ALERT_RING.Thickness,
					time = ALERT_RING.Time,
					interval = ALERT_RING.Every,
					loop = true,
				})
				UiFx.punch(card.buy, { from = 0.8, peak = 1.12 })
			end
		end
		local label, price = card.label, card.price
		if price then
			price.Visible = priceText ~= nil
			if priceText then
				price.Text = priceText
			end
		end
		if label then
			label.Visible = priceText == nil
			if priceText == nil then
				label.Text = text
			end
		end
	end

	local function priceLabel(price: number): string
		return TextUtil.fill(BUY.Price, { price = TankRules.FormatMoney(price) })
	end

	-- Щит: что примет сервер сейчас (см. шапку).
	local function shieldLook(card: Card)
		if busy == card then
			setLook(card, "busy", BUY.Busy)
			return
		end
		local t = now()
		local shieldUntil = numberAttr(player, "ShieldUntil") or 0
		local ready = numberAttr(player, "ShieldReadyAt") or 0
		local left = protectLeft()
		if player:GetAttribute("Stealing") ~= nil and shieldUntil <= t then
			-- крадёшь сам: сервер щит не включит («Сначала закончи кражу») — видно сразу
			setLook(card, "after", BUY.AfterTheft)
		elseif shieldUntil > t then
			setLook(card, "active", TextUtil.fill(BUY.Active, { t = StealRules.FormatClock(shieldUntil - t) }))
		elseif ready > t then
			setLook(card, "wait", TextUtil.fill(BUY.Wait, { t = StealRules.FormatClock(ready - t) }))
			if open and (card.ringFor == nil or math.abs(card.ringFor - ready) > 0.5) then
				stopRing(card)
				card.ring = UiFx.ringTimer(card.buy, ready - t, { pad = 4, z = RING_Z, thickness = 4 })
				card.ringFor = ready
			end
		elseif left >= SHIELD.StackBelow then
			setLook(card, "protected", BUY.Protected)
		elseif hud:GetAttribute("AlertPhase") ~= nil then
			setLook(card, "alert", TEXTS.ButtonAlert)
		else
			setLook(card, "on", BUY.On)
		end
	end

	local function itemLook(card: Card)
		local item = card.key
		local stateLabel = card.state
		if busy == card then
			setLook(card, "busy", BUY.Busy)
		elseif confirm == card then
			setLook(card, "confirm", BUY.Confirm)
		else
			local price = priceOf(item)
			if not price then
				setLook(card, "bought", BUY.Bought)
			elseif money() < price and os.clock() < card.needUntil then
				-- «ЕЩЁ $3 000» под пальцем (нажали, а денег не хватает)
				setLook(card, "need", TextUtil.fill(BUY.Need, { price = TankRules.FormatMoney(price - money()) }))
			else
				setLook(card, if money() >= price then "price" else "poor", "", priceLabel(price))
			end
		end
		if item == "Lock" and stateLabel then
			stateLabel.Visible = false
			-- купленный замок: строка действия — «Сильнее замки — скоро в магазине» (её раскладка)
			local full, short = effectTexts("Lock")
			if card.effectText ~= full and card.effectText ~= short then
				layoutCards()
			end
		end
	end

	-- Шапка во время тревоги (лист открыт — плашки тревоги нет, D-18): 🚨 «ВОР В САДКЕ!» /
	-- 🏃 «ВОР УБЕГАЕТ!» (StealConfig.Texts.Alert) цветом Berry — ребёнок в листе видит, зачем
	-- красная «ЩИТ!»; надпись шире — по тексту (не дальше кошелька); тревога ушла, лист закрыт —
	-- снова 🛡️ «ЗАЩИТА».
	local headTitle = header:FindFirstChild("Title") :: TextLabel?
	local headRest = {
		title = if headTitle then headTitle.Text else "",
		icon = if headIcon and headIcon:IsA("TextLabel") then headIcon.Text else "",
		size = if headTitle then headTitle.Size else UDim2.new(),
		color = if headTitle then headTitle.TextColor3 else Color3.new(1, 1, 1),
	}
	local headPhase: string? = nil
	local function headLook()
		local phase = if open then hud:GetAttribute("AlertPhase") else nil
		local now = if phase == "hold" or phase == "carry" then phase else nil
		if now == headPhase or not headTitle then
			return
		end
		local fresh = headPhase == nil
		headPhase = now
		local title = headTitle :: TextLabel
		local iconLabel = if headIcon and headIcon:IsA("TextLabel") then headIcon else nil
		if not now then
			title.Text = headRest.title
			title.Size = headRest.size
			title.TextColor3 = headRest.color
			if iconLabel then
				iconLabel.Text = headRest.icon
			end
			return
		end
		local text = if now == "carry" then ALERT_TEXTS.Carry else ALERT_TEXTS.Hold
		title.Text = text
		title.TextColor3 = Palette.Berry.Top
		if iconLabel then
			iconLabel.Text = if now == "carry" then ALERT_TEXTS.IconCarry else ALERT_TEXTS.IconHold
		end
		local h = header.AbsoluteSize.Y
		if h > 1 then
			-- шире — по тексту, но не дальше места до кошелька (тесно — текст мельче)
			local list = header:FindFirstChildOfClass("UIListLayout")
			local pad = if list then list.Padding.Scale * header.AbsoluteSize.X + list.Padding.Offset else 0
			local used = 0
			for _, item in header:GetChildren() do
				if item:IsA("GuiObject") and item.Visible and item ~= title then
					used += item.AbsoluteSize.X + pad
				end
			end
			local room = header.AbsoluteSize.X - used - pad
			local need = UiFx.textWidth(text, UiFx.textSize("Title")) + HEAD_PAD
			local width = math.max(math.min(need, room), headRest.size.X.Scale * h)
			title.Size = UDim2.fromScale(width / h, headRest.size.Y.Scale)
		end
		if fresh then
			UiFx.punch(title, { from = 0.7, peak = 1.12 })
			if iconLabel then
				UiFx.wiggle(iconLabel, 12, 3, 0.45)
			end
		end
	end

	local function refresh()
		headLook()
		for _, card in cards do
			if card.key == "Shield" then
				shieldLook(card)
			else
				itemLook(card)
			end
		end
		if moneyLabel then
			moneyLabel.Text = TankRules.FormatMoney(money())
		end
	end

	local function tickLoop()
		ticker = nil
		if not open then
			return
		end
		refresh()
		ticker = task.delay(1, tickLoop)
	end

	------------------------------------------------------------------------------
	-- Нажатия
	------------------------------------------------------------------------------

	local function stopConfirm(revert: boolean)
		local card = confirm
		confirm = nil
		local ring = confirmRing
		confirmRing = nil
		if ring then
			ring()
		end
		cancel(confirmEnd)
		confirmEnd = nil
		if card and revert then
			itemLook(card)
		end
	end

	local function endBusy(revert: boolean)
		local card = busy
		busy = nil
		cancel(busyWait)
		busyWait = nil
		if card and revert then
			if card.key == "Shield" then
				shieldLook(card)
			else
				itemLook(card)
			end
		end
	end

	local function onShieldTap(card: Card)
		local look = card.look
		if look == "on" or look == "alert" then
			stopConfirm(true)
			endBusy(false)
			busy = card
			shieldLook(card)
			opts.onShield(card.buy)
			return
		end
		-- «⏳ 2:59», «ТЫ ПОД ЗАЩИТОЙ», «ПОСЛЕ КРАЖИ»: подпись кнопки уже говорит почему — она
		-- качается и вспыхивает (под пальцем; уведомление легло бы на шапку листа с кошельком, а
		-- «барабанить» — стопка одинаковых)
		UiFx.wiggle(card.buy, 6, 2, 0.3)
		local label = card.label
		if label and label.Visible then
			UiFx.flashText(label, Palette.Sun.Top, 0.4)
		end
	end

	local function onItemTap(card: Card)
		if busy == card or card.look == "bought" then
			if card.look == "bought" then
				UiFx.wiggle(card.buy, 4, 2, 0.24)
			end
			return
		end
		local price = priceOf(card.key)
		if not price then
			itemLook(card)
			return
		end
		if money() < price then
			-- Не хватает: качается и прямо на кнопке «ЕЩЁ $3 000» NeedTime с (под пальцем: уведомление
			-- легло бы на шапку листа с кошельком; повторное нажатие — заново, без стопки уведомлений)
			stopConfirm(true)
			UiFx.wiggle(card.buy, 6, 2, 0.3)
			card.needUntil = os.clock() + PANEL.NeedTime
			itemLook(card)
			task.delay(PANEL.NeedTime + 0.02, function()
				if open and os.clock() >= card.needUntil then
					itemLook(card)
				end
			end)
			return
		end
		if confirm ~= card then
			-- Первое нажатие: «КУПИТЬ?» с кольцом на ConfirmTime с.
			stopConfirm(true)
			confirm = card
			confirmAt = os.clock()
			itemLook(card)
			UiFx.morphFlash(card.buy)
			confirmRing = UiFx.ringTimer(card.buy, TankConfig.ConfirmTime, { pad = 4, z = RING_Z, thickness = 4 })
			UiFx.sound("tick", 0.4, 1.25)
			confirmEnd = task.delay(TankConfig.ConfirmTime, function()
				confirmEnd = nil
				if confirm == card then
					stopConfirm(true)
				end
			end)
			return
		end
		if os.clock() - confirmAt < TankConfig.ConfirmArm then
			-- Слишком рано (двойной тап, «барабанит»): отсчёт ConfirmArm — заново, кнопка качается.
			confirmAt = os.clock()
			UiFx.wiggle(card.buy, 4, 2, 0.24)
			return
		end
		-- Второе нажатие: купить. Кнопка ждёт ответа сервера (⏳).
		stopConfirm(false)
		endBusy(true)
		busy = card
		itemLook(card)
		Net.Event("DefenceBuy"):FireServer(card.key)
		busyWait = task.delay(TANK_PANEL.SellWait, function()
			busyWait = nil
			endBusy(true)
		end)
	end

	for _, card in cards do
		UiFx.press(card.buy, { sound = "click" })
		card.buy.Activated:Connect(function()
			if not open then
				return
			end
			if card.key == "Shield" then
				onShieldTap(card)
			else
				onItemTap(card)
			end
		end)
	end

	------------------------------------------------------------------------------
	-- Открыть / закрыть
	------------------------------------------------------------------------------

	local function onClose(_reason: string)
		stopConfirm(false)
		cancel(ticker)
		ticker = nil
		for _, card in cards do
			stopRing(card)
			stopGlow(card)
			card.needUntil = 0
			card.look = "" -- (открыли снова — вид и кольца заново)
		end
		headLook() -- (open уже false: шапка — снова «ЗАЩИТА»)
		trove:Clean()
	end

	sheet = Sheet.new(hud, root, {
		Layout = LAYOUT :: any,
		Token = "Night",
		contentWidth = contentWidth,
		contentHeight = contentHeight,
		onPlace = onPlace,
		onClose = function(reason: string)
			open = false
			onClose(reason)
		end,
	})

	UiFx.press(close, { sound = "click" })
	close.Activated:Connect(function()
		sheet:Close("close")
	end)

	local self = {} :: Cards

	function self.Open(_self: Cards): boolean
		if sheet:IsOpen() then
			return true
		end
		cards.Lock.frame.Visible = LOCK.SaleMax > 0
		if not sheet:Open() then
			return false
		end
		open = true
		refresh()
		trove:Connect(player.AttributeChanged, function(name: string)
			if
				name == "Money"
				or name == "HasDog"
				or name == "HasAlarm"
				or name == "LockLevel"
				or name == "ShieldReadyAt"
				or name == "ShieldUntil"
				or name == "Stealing"
			then
				refresh()
			end
		end)
		local base = ownBase()
		if base then
			trove:Connect(base:GetAttributeChangedSignal("ProtectUntil"), refresh)
		end
		trove:Connect(hud:GetAttributeChangedSignal("AlertPhase"), refresh) -- (тревога: щит — «ЩИТ!»)
		local items: { GuiObject } = {}
		for _, card in visibleCards() do
			table.insert(items, card.frame)
		end
		UiFx.staggerPop(items, { from = 0.3, gap = 0.05, delay = 0.1 })
		if headIcon then
			UiFx.punch(headIcon, { delay = 0.12 })
		end
		cancel(ticker)
		ticker = task.delay(1, tickLoop)
		return true
	end

	function self.Close(_self: Cards, reason: string?)
		sheet:Close(reason or "api")
	end

	function self.IsOpen(_self: Cards): boolean
		return sheet:IsOpen()
	end

	function self.ShieldAnswered(_self: Cards, _ok: boolean)
		local card = cards.Shield
		if busy == card then
			endBusy(true)
		elseif open then
			shieldLook(card)
		end
	end

	function self.Bought(_self: Cards, payload: { [string]: any })
		local item = payload.Item
		local price = if typeof(payload.Price) == "number" then payload.Price else 0
		local card = if typeof(item) == "string" then cards[item] else nil
		if card and busy == card then
			endBusy(false)
		end
		local from: GuiObject? = nil
		if card and open then
			itemLook(card)
			from = card.buy
			UiFx.stamp(card.buy, -6, 0.3)
			UiFx.rimFlash(card.frame, { bump = 1.04 })
			local area = hud.AbsoluteSize
			if area.X > 1 and area.Y > 1 then
				local centre = card.frame.AbsolutePosition + card.frame.AbsoluteSize / 2 - hud.AbsolutePosition
				UiFx.confettiPop(hud, {
					count = 16,
					colors = { Palette.Leaf.Top, Palette.Gold.Top, Palette.Guard.Top, UIConfig.White },
					origin = Vector2.new(centre.X / area.X, centre.Y / area.Y),
					spread = 90,
					power = 1,
					duration = 1.2,
				})
			end
		end
		local wallet = moneyModule()
		local spend = if wallet then wallet.Spend else nil
		if type(spend) == "function" and price > 0 then
			(spend :: (number, GuiObject?) -> ())(price, from)
		end
		if typeof(item) == "string" then
			local text = TEXTS.Bought[item]
			if text then
				local level = if typeof(payload.Level) == "number" then payload.Level else 1
				local entry = LOCK.Levels[math.clamp(level, 1, #LOCK.Levels)]
				local spec = (TEXTS.Cards :: any)[item]
				-- (ждёт ухода листа: штамп, конфетти и 💵 уже сказали «куплено»; уведомление — что
				-- теперь будет, и легло бы на шапку с кошельком)
				NotifyController.Show(
					TextUtil.fill(text, { s = entry.Hold }),
					"success",
					{ icon = if spec then spec.Icon else nil, afterSheet = true }
				)
			end
		end
	end

	function self.Denied(_self: Cards, item: string)
		local card = cards[item]
		if busy == card then
			endBusy(true)
		end
		if card and open then
			UiFx.wiggle(card.frame, 8, 3, 0.45)
		end
	end

	function self.Stats(_self: Cards): { [string]: any }
		local looks: { [string]: string } = {}
		for key, card in cards do
			looks[key] = card.look
		end
		return {
			open = sheet:IsOpen(),
			confirm = if confirm then confirm.key else nil,
			busy = if busy then busy.key else nil,
			looks = looks,
			ticking = ticker ~= nil,
			cell = cell,
		}
	end

	return self
end

return DefenceCards
