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
	телефоне четвёртая листается: явный CanvasSize, как у садка; на планшете и ПК все в листе, лист —
	ниже, по ним). Кнопка Buy каждой карточки — одно из (UiFx.setCandy + подпись):
	  ЩИТ:  Guard «ВКЛЮЧИТЬ» — когда сервер примет (сам не крадёшь, защиты меньше
	        Shield.StackBelow с, щит готов; DC-03) → нажатие — ShieldActivate (opts.onShield), «⏳» до
	        ответа; щит включён — стекло «🛡️ 0:42»; перезарядка — Slate «⏳ 2:59» с кольцом-таймером
	        (нажатие — качается и «Щит перезаряжается — ещё …»); защищён другим видом ≥ StackBelow —
	        стекло «ТЫ ПОД ЗАЩИТОЙ».
	  СОБАКА / СИГНАЛИЗАЦИЯ / ЗАМОК: Gold «💵 $6 000» → первое нажатие — Berry «КУПИТЬ?» с кольцом
	        TankConfig.ConfirmTime с; второе — не раньше ConfirmArm после предыдущего (раньше — отсчёт
	        заново, кнопка качается: «барабанить» не покупает) → DefenceBuy(item), «⏳» до ответа
	        (нет ответа Panel.SellWait садка — назад); не хватает денег — Slate с той же ценой
	        (читается), нажатие — качается и «Не хватает: нужно $6 000»; куплено — штамп Leaf
	        «КУПЛЕНО» (замок: ниже «Сильнее замки — скоро в магазине», DC-11; Lock.SaleMax = 0 —
	        карточки замка нет). Имя «СИГНАЛИЗАЦИЯ» не влезает в карточку — «СИГНАЛКА».
	  Ответ "Bought" — штамп «КУПЛЕНО», конфетти над карточкой, MoneyController.Spend(цена, кнопка)
	  (💵 летят из кошелька в карточку, «−$6 000»), уведомление «Собака охраняет твой двор!» (🐕 /
	  🚨 / 🔐); "Denied" — карточка качается (текст показывает DefenceController).
	Живые числа (таймер щита, «хватает ли денег», кошелёк шапки) — одна цепочка task.delay раз в
	секунду, пока лист открыт, и сразу по атрибутам игрока; всё, что живёт при открытом листе, — в
	его Trove: закрыт — соединений как до открытия.

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
local ICONS: { [string]: string } = { Dog = "🐕", Alarm = "🚨", Lock = "🔐" }

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
	look: string,
	ring: (() -> ())?,
	ringFor: number?, -- до какого времени тикает кольцо перезарядки
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
	local header = panel:WaitForChild("Header")
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
			look = "",
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
			-- планшет, ПК: все карточки — в листе (Sheet уже сделал его ниже — по ним)
			local fitAll = windowW / (n + (n - 1) * LAYOUT.Gap + 2 * LAYOUT.Side)
			if fitAll < cw then
				cw = math.max(fitAll, LAYOUT.CardMin)
			end
			ch = math.min(ch, cw / LAYOUT.CardAspect)
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

	-- look: "on" | "active" | "wait" | "protected" | "price" | "poor" | "confirm" | "busy" | "bought"
	local TOKENS: { [string]: string } = {
		on = "Guard",
		active = "Glass",
		wait = "Slate",
		protected = "Glass",
		price = "Gold",
		poor = "Slate",
		confirm = "Berry",
		busy = "Slate",
		bought = "Leaf",
	}

	local function setLook(card: Card, look: string, text: string, priceText: string?)
		if card.look ~= look then
			card.look = look
			UiFx.recolor(card.buy, TOKENS[look] or "Slate")
			if look ~= "wait" and look ~= "confirm" then
				stopRing(card)
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
		if shieldUntil > t then
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
			else
				setLook(card, if money() >= price then "price" else "poor", "", priceLabel(price))
			end
		end
		if item == "Lock" and stateLabel then
			local level = math.floor(numberAttr(player, "LockLevel") or 0)
			stateLabel.Visible = level > 0 and priceOf("Lock") == nil
			stateLabel.Text = TEXTS.LockSoon
		end
	end

	local function refresh()
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
		if look == "on" then
			stopConfirm(true)
			endBusy(false)
			busy = card
			shieldLook(card)
			opts.onShield(card.buy)
			return
		end
		UiFx.wiggle(card.buy, 6, 2, 0.3)
		local t = now()
		if look == "wait" then
			local left = (numberAttr(player, "ShieldReadyAt") or t) - t
			NotifyController.Show(TextUtil.fill(TEXTS.Denied.cooldown, { t = StealRules.FormatClock(left) }), "warning")
		elseif look == "protected" then
			NotifyController.Show(
				TextUtil.fill(TEXTS.Denied.protected, { t = StealRules.FormatClock(protectLeft()) }),
				"warning"
			)
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
			-- Не хватает: качается и «Не хватает: нужно $6 000» (цену решит и сервер)
			stopConfirm(true)
			UiFx.wiggle(card.buy, 6, 2, 0.3)
			NotifyController.Show(
				TextUtil.fill(TEXTS.Denied.money, { price = TankRules.FormatMoney(price) }),
				"warning"
			)
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
		end
		trove:Clean()
	end

	sheet = Sheet.new(hud, root, {
		Layout = LAYOUT :: any,
		Token = "Night",
		contentWidth = contentWidth,
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
				NotifyController.Show(TextUtil.fill(text, { s = entry.Hold }), "success", { icon = ICONS[item] })
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
