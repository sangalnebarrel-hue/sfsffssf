--!strict
--[[
	TankPanelController — панель садка (Этап 3): HUD.TankPanel — лист (Panel) с шапкой
	🐠 «САДОК» · «4/6» · «+$42/с» · «💵 $2 783 ▲» · фишка «💰 РЫНОК +50%», круглый ✕ и
	карточками рыб (Cards: CardTemplate / EmptyTemplate / LockedTemplate). Лист открывает,
	раскладывает и закрывает помощник Controllers.Sheet (его же возьмёт магазин Этапа 5),
	карточки рисует помощник Controllers.TankCards. Строят их tools/builder/gui/Sheet.luau
	(оболочка) и Tank.luau (содержимое); стиль — tools/builder/gui/STYLE.md.

	Что делает:
	  • Место — Sheet: в px при открытии, записанное как UDim2.fromScale(x / W, y / H) от HUD, и
	    заново при смене ViewportSize: слева 16 px, справа min(колонка кнопок, кнопка прыжка) −
	    16, сверху низ стопки статуса + 16, снизу HUD − 16 (телефон 844×390 ≈ 717 × 228); на
	    планшете и ПК — не больше 900 × 560 и не шире карточек, по центру этого места. Не
	    закрывает ни кошелёк, ни кнопку «САДОК»; без затемнения. Ячейки сетки, отступы и ширина
	    холста (CanvasSize) — тоже масштабом (TankConfig.Panel: Aspect, Gap, Overhang, Side).
	  • Фон: на телефоне — «стекло» с тёмной полосой Night под шапкой, на планшете и ПК — Night;
	    карточки — Theme.sim без блика, глянца и тени.
	  • Карточки: на телефоне один ряд (ScrollingFrame, явный CanvasSize), на HUD ≥ TankConfig.Panel
	    .TallFrom px — RowsTall ряда; витрины 1..TankSlots, потом ОДНА закрытая (Locked). Рыба
	    (TankCards): плашка цвета редкости (мифическая — радужная обводка, только пока открыта),
	    имя заглавными (на карточке шире Panel.WideCard — полное), сама рыба во ViewportFrame
	    (создаётся при открытии, удаляется при закрытии), фишка мутации «👑 ×2», доход «+$4/с»,
	    полоска «×1.4» или золотое «МАКС», кнопка «💵 $45» (на широкой — «ПРОДАТЬ $45»): Leaf дома,
	    Gold у ларька, Berry «ТОЧНО?» с ringTimer при подтверждении, Slate «⏳» — ждём сервер.
	    Пустая — стекло, 🎣, «ПУСТО», «Поймай рыбу!»; закрытая — Slate, 🔒, «ЕЩЁ МЕСТО», «Скоро в
	    магазине» (тексты — TankConfig.Texts).
	  • Числа — из атрибутов своих витрин (RemoteNames, «Состояние садка») и SellRatePct, одна
	    цепочка task.delay раз в Panel.Tick секунд, пока открыта (цены, полоски, сумма садка в
	    шапке «💵 $2 783 ▲»; ▲ — пока хоть одна рыба дорожает); покадровой работы при открытой
	    панели в покое — нет. Витрина перечитывается только по её Event (и State), одним
	    task.defer на витрину. Шапка: «4/6» (TankCount / TankSlots; полный садок — фишка Gold),
	    «+$42/с» (Income).
	  • Рынок: SellRatePct > 100 (атрибут сервера — единственный источник) — фишка «РЫНОК +50%»
	    выскакивает, цены — по ставке ларька (подпрыгивают), кнопки — Gold (до ≈ 2 с после
	    прихода к ларьку: сервер ждёт MarketDwell проверок). TankEvent "Open" с ларька (или у
	    аквариума) только открывает панель.
	  • Продажа — каждая рыба в два нажатия: первое — «ТОЧНО?» + ringTimer ConfirmTime с и Rate
	    карточки красным «−$4/с»; второе раньше ConfirmArm не считается; 0.4–3 с — TankSell(uid),
	    на кнопке ⏳ до ответа (нет ответа Panel.SellWait с — кнопка возвращается); через 3 с —
	    назад; нажатие на другую карточку отменяет первую. "Sold" — карточка сжимается, рыба
	    уходит, из карточки поднимается золотое «+$45», на её месте выскакивает пустая карточка с
	    золотым кольцом,
	    MoneyController.Celebrate(Amount, карточка, { Rate = "down" }) — монеты летят в кошелёк,
	    доход катится вниз (каждый "Sold" — ровно один Celebrate; панель закрыта — без полёта:
	    from = nil); рыбу в мире убирает событие витрины. "Denied" — карточка качается,
	    подсказка — Text сервера (NotifyController.Show, «warning»; колонка уведомлений — над
	    листом, Sheet).
	  • Открытие: лист поднимается снизу (Sheet; без перелёта — он у самых краёв своего места) +
	    лесенка карточек и «кивок» 🐠 / закрытие — сжимается (для рыбалки — сразу). Пока CounterHold (рыба летит в
	    кнопку) — открытие откладывается до прилёта; во время поклёвки, мини-игры, открытой
	    карточки улова — отказ (Open → false; качает кнопку TankButtonController). Закрывается
	    САМА (Sheet), когда FishingState становится "Bite" или "Reeling", появляется
	    CounterHold, видны BiteAlert / Minigame / CatchCard — рыбака на экране не закрывает
	    никогда; и по ✕ или кнопке «САДОК». Open(uid) (прилёт улова) — карточка этой рыбы
	    прокручена в окно, кольцо цвета редкости. Каждое открытие гасит красный «!» на кнопке
	    «САДОК» (UiFx.badgeHide: «первое открытие» — кто бы ни открыл, кнопка или ларёк).
	  • Бюджеты: заливка телефона ≤ 2.5× с открытой панелью (gui_render.py; не хватает —
	    вместо Viewport на телефоне эмодзи редкостей 🐟 🐠 🐡 🦈 🐉); ≤ 60 временных объектов;
	    UiFx.activeJobs() == 0 после каждого эффекта; соединений после закрытия — как до открытия
	    (у закрытой панели — только постоянные: TankEvent, атрибуты игрока, ✕).
	Атрибуты витрин требуют StreamingEnabled = false (tools/build.luau).

	API:
	  TankPanelController:Start(hud)
	  TankPanelController.Toggle() -> boolean       -- кнопка «САДОК»: открыть / закрыть
	  TankPanelController.Open(focusUid: string?) -> boolean -- открыть (прокрутить к рыбе
	                                                -- focusUid: прилёт улова); false — нельзя сейчас
	                                                -- (при CounterHold откроется после прилёта)
	  TankPanelController.Close()
	  TankPanelController.IsOpen() -> boolean
	  (для тестов и превью)
	  TankPanelController.Relayout()                -- пересчитать место (как при смене ViewportSize)
	  TankPanelController.Card(slot) -> GuiObject?  -- карточка витрины slot (или "locked")
	  TankPanelController.Stats() -> { cards, ticking, confirm, selling, pending }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TankConfig = require(Config:WaitForChild("TankConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local TankRules = require(Shared:WaitForChild("TankRules"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Net = require(Shared:WaitForChild("Net"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local Controllers = script.Parent
local Sheet = require(Controllers:WaitForChild("Sheet"))
local TankCards = require(Controllers:WaitForChild("TankCards"))
local NotifyController = require(Controllers:WaitForChild("NotifyController"))

type Card = TankCards.Card
type Info = TankCards.Info

local player = Players.LocalPlayer
local PANEL = TankConfig.Panel
local TEXTS = TankConfig.Texts
local MAX_SLOTS = TankConfig.MaxSlots
local HOME_RATE = EconomyConfig.HomeRatePct
local BOTTOM = 0.03 -- под рядом карточек — столько их высоты (обводка не обрезается)
local RING_Z = 8 -- кольцо «ТОЧНО?» — над лицом и подписью кнопки (Theme.SZ.Top 6 + 2)
local FLOAT_Z = 40 -- «+$45» продажи — над листом (ZIndex 30)

-- Всё состояние модуля — в одной таблице (свободные регистры верхнего уровня: compile_limits).
local S = {
	hud = nil :: ScreenGui?,
	sheet = nil :: Sheet.Sheet?,
	cardsFrame = nil :: ScrollingFrame?,
	grid = nil :: UIGridLayout?,
	padding = nil :: UIPadding?,
	head = {} :: { [string]: any },
	templates = {} :: { [string]: GuiObject },
	cards = {} :: { [number]: Card },
	locked = nil :: Card?,
	slots = 0, -- витрин в панели
	base = nil :: Model?,
	trove = Trove.new(), -- живёт, пока панель открыта (витрины)
	tick = nil :: thread?,
	refresh = {} :: { [number]: boolean },
	confirm = nil :: Card?,
	confirmAt = 0,
	confirmEnd = nil :: thread?,
	ring = nil :: (() -> ())?,
	selling = nil :: { uid: string, slot: number }?,
	lastSale = nil :: { uid: string, slot: number }?, -- последняя проданная (её "Sold" может прийти позже)
	sellWait = nil :: thread?,
	pending = nil :: any, -- отложенное открытие (true или uid рыбы)
	pendingConn = nil :: RBXScriptConnection?,
	cell = Vector2.new(112, 160),
	wide = false,
	cols = 1,
	gap = 0,
	side = 0,
	canvasW = 0,
	windowW = 0,
	sellEvent = nil :: RemoteEvent?,
}

local TankPanelController = {}

local function cancel(thread: thread?)
	if thread and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
end

local function isOpen(): boolean
	return S.sheet ~= nil and S.sheet:IsOpen()
end

local function numberAttr(name: string): number?
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else nil
end

local function ratePct(): number
	return numberAttr("SellRatePct") or HOME_RATE
end

local function lookFor(): string
	return if ratePct() > HOME_RATE then "market" else "home"
end

local function slotCount(): number
	return math.clamp(math.floor(numberAttr("TankSlots") or TankConfig.StartSlots), 0, MAX_SLOTS)
end

local function ownBase(): Model?
	local index = numberAttr("BaseIndex")
	local bases = Workspace:FindFirstChild("Bases")
	if not index or index <= 0 or not bases then
		return nil
	end
	local base = bases:FindFirstChild(`Base_{index}`)
	return if base and base:IsA("Model") then base else nil
end

local function slotModel(index: number): Instance?
	local base = S.base
	local tank = base and base:FindFirstChild("Tank")
	local slots = tank and tank:FindFirstChild("Slots")
	return slots and slots:FindFirstChild(`Slot_{index}`)
end

-- Рыба витрины index (nil — пусто) и вид её последнего события ("sold", "in", "mount", …).
local function readSlot(index: number): (Info?, string?)
	local slot = slotModel(index)
	if not slot then
		return nil, nil
	end
	local event = slot:GetAttribute("Event")
	local kind = if typeof(event) == "string" then string.match(event, "^%d+|(%a+)|") else nil
	if slot:GetAttribute("State") ~= "fish" then
		return nil, kind
	end
	local uid, id = slot:GetAttribute("FishUid"), slot:GetAttribute("FishId")
	local value, grow = slot:GetAttribute("Value"), slot:GetAttribute("GrowFrom")
	if typeof(uid) ~= "string" or typeof(id) ~= "string" or typeof(value) ~= "number" or typeof(grow) ~= "number" then
		return nil, kind
	end
	local rarity, mutation, income =
		slot:GetAttribute("Rarity"), slot:GetAttribute("Mutation"), slot:GetAttribute("Income")
	return {
		uid = uid,
		fishId = id,
		rarity = if typeof(rarity) == "string" then rarity else "Common",
		mutation = if typeof(mutation) == "string" then mutation else nil,
		value = value,
		income = if typeof(income) == "number" then income else 0,
		growFrom = grow,
	},
		kind
end

--------------------------------------------------------------------------------
-- Раскладка карточек (Sheet зовёт при открытии и смене экрана)
--------------------------------------------------------------------------------

local function rowsFor(tall: boolean): number
	return if tall then PANEL.RowsTall else 1
end

local function aspectFor(tall: boolean): number
	return if tall then PANEL.AspectTall else PANEL.Aspect
end

local function cardCount(): number
	return S.slots + (if S.slots < MAX_SLOTS then 1 else 0)
end

-- Высота карточки в окне высотой cardsH: ряды, просветы между ними, свес сверху, запас снизу.
local function cardHeight(cardsH: number, tall: boolean): number
	local rows, aspect = rowsFor(tall), aspectFor(tall)
	return cardsH / (rows + (rows - 1) * PANEL.Gap * aspect + PANEL.Overhang + BOTTOM)
end

local function contentWidth(cardsH: number, tall: boolean): number
	local cw = cardHeight(cardsH, tall) * aspectFor(tall)
	local cols = math.max(math.ceil(cardCount() / rowsFor(tall)), 1)
	return 2 * PANEL.Side * cw + cols * cw + (cols - 1) * PANEL.Gap * cw
end

local clearCards: () -> ()
local buildCards: () -> ()

local function onPlace(fit: Sheet.Fit)
	local frame, grid, padding = S.cardsFrame, S.grid, S.padding
	if not frame or not grid or not padding then
		return
	end
	local tall = fit.tall
	local cols = math.max(math.ceil(cardCount() / rowsFor(tall)), 1)
	local windowW, windowH = math.max(fit.cards.X, 1), math.max(fit.cards.Y, 1)
	local ch = cardHeight(fit.cards.Y, tall)
	local cw = ch * aspectFor(tall)
	if tall then
		-- в несколько рядов все столбцы — в окне (не листается): иначе карточки мельче
		cw = math.min(cw, windowW / (cols + (cols - 1) * PANEL.Gap + 2 * PANEL.Side))
		ch = cw / aspectFor(tall)
	end
	local gap, side = PANEL.Gap * cw, PANEL.Side * cw
	local top, bottom = PANEL.Overhang * ch, BOTTOM * ch
	local content = 2 * side + cols * cw + (cols - 1) * gap
	-- (+1 px: сетка кладёт в ряд ровно cols карточек и с ошибкой округления)
	local canvasW = math.max(windowW, content + 1)
	frame.CanvasSize = UDim2.fromScale(canvasW / windowW, 1)
	padding.PaddingLeft = UDim.new(side / canvasW, 0)
	padding.PaddingRight = UDim.new(side / canvasW, 0)
	padding.PaddingTop = UDim.new(top / windowH, 0)
	padding.PaddingBottom = UDim.new(bottom / windowH, 0)
	local innerW, innerH = math.max(canvasW - 2 * side, 1), math.max(windowH - top - bottom, 1)
	grid.CellSize = UDim2.fromScale(cw / innerW, ch / innerH)
	grid.CellPadding = UDim2.fromScale(gap / innerW, gap / innerH)
	if S.head.Rate then
		S.head.Rate.Visible = fit.headerWidth >= PANEL.RateFrom
	end
	local wide = cw >= PANEL.WideCard
	local relabel = wide ~= S.wide and next(S.cards) ~= nil
	S.cell, S.wide, S.cols, S.gap, S.side = Vector2.new(cw, ch), wide, cols, gap, side
	S.canvasW, S.windowW = canvasW, windowW
	frame.CanvasPosition = Vector2.new(math.min(frame.CanvasPosition.X, math.max(canvasW - windowW, 0)), 0)
	if relabel then
		buildCards() -- имена и подписи кнопок другой длины: карточки заново
	end
end

--------------------------------------------------------------------------------
-- Шапка, цены, рынок
--------------------------------------------------------------------------------

local function updateHeader()
	local head = S.head
	local count: number = numberAttr("TankCount") or 0
	if numberAttr("TankCount") == nil then
		for _, card in S.cards do
			if card.kind == "fish" then
				count += 1
			end
		end
	end
	if head.CountLabel then
		head.CountLabel.Text = TextUtil.fill(TEXTS.Count, { count = count, slots = S.slots })
	end
	if head.Count then
		UiFx.setCandy(head.Count, if S.slots > 0 and count >= S.slots then "Gold" else "Cream")
	end
	if head.Rate then
		head.Rate.Text = TankRules.FormatRate(math.round((numberAttr("Income") or 0) * 10))
	end
end

-- Цены, полоски, сумма садка (раз в Panel.Tick с, пока открыта; и сразу после изменений).
local function tick()
	local now = Workspace:GetServerTimeNow()
	local rate = ratePct()
	local total, growing = 0, false
	for _, card in S.cards do
		local price, grows = TankCards.update(card, now, rate, S.wide)
		total += price
		growing = growing or grows
	end
	if S.head.Total then
		S.head.Total.Text = TextUtil.fill(if growing then TEXTS.Total else TEXTS.TotalDone, {
			money = TankRules.FormatMoney(total),
		})
	end
end

local function tickLoop()
	S.tick = nil
	if not isOpen() then
		return
	end
	tick()
	S.tick = task.delay(PANEL.Tick, tickLoop)
end

-- Фишка «РЫНОК +50%» и цвет кнопок по SellRatePct; animate — «скачок» цен на глазах.
local function applyRate(animate: boolean)
	local chip = S.head.Market
	local market = ratePct() > HOME_RATE
	if chip then
		if market and not chip.Visible then
			chip.Visible = true
			if animate then
				UiFx.popIn(chip, { from = 0.3, rotate = -8 })
				UiFx.rimFlash(chip, { delay = 0.2 })
			end
		elseif not market and chip.Visible then
			if animate then
				UiFx.popOut(chip, { hide = true })
			else
				chip.Visible = false
			end
		end
	end
	local look = lookFor()
	for _, card in S.cards do
		if card.kind == "fish" and (card.look == "home" or card.look == "market") then
			TankCards.setLook(card, look, S.wide)
			if animate and card.caption then
				UiFx.punch(card.caption, { from = 0.7, peak = 1.2 })
			end
		end
	end
	tick()
end

--------------------------------------------------------------------------------
-- Карточки
--------------------------------------------------------------------------------

local onSell: (card: Card) -> ()

local function makeCard(slot: number, info: Info?): Card
	local card = TankCards.make(S.templates, if info then "fish" else "empty", slot, info, S.cell, S.wide, onSell)
	if card.kind == "fish" then
		TankCards.setLook(card, lookFor(), S.wide)
	end
	return card
end

clearCards = function()
	for slot, card in S.cards do
		TankCards.destroy(card)
		S.cards[slot] = nil
	end
	if S.locked then
		TankCards.destroy(S.locked)
		S.locked = nil
	end
	S.confirm = nil
end

buildCards = function()
	clearCards()
	for slot = 1, S.slots do
		S.cards[slot] = makeCard(slot, (readSlot(slot)))
	end
	if S.slots < MAX_SLOTS then
		S.locked = TankCards.make(S.templates, "locked", S.slots + 1, nil, S.cell, S.wide)
	end
	tick()
end

local function rarityColor(info: Info?): Color3
	local style = if info then UIConfig.Rarity[info.rarity] else nil
	return if style then style.Top else UIConfig.White
end

-- Подтверждение кончилось (время вышло, другая карточка, продажа, закрытие).
local function stopConfirm(revert: boolean)
	local card = S.confirm
	S.confirm = nil
	local ring = S.ring
	S.ring = nil
	if ring then
		ring()
	end
	cancel(S.confirmEnd)
	S.confirmEnd = nil
	if card and revert and card.look == "confirm" then
		TankCards.setLook(card, lookFor(), S.wide)
		TankCards.showLoss(card, false)
	end
end

-- Ответа на продажу больше не ждём (пришёл, отказ, потерялся): кнопка снова «💵 $45».
local function endSelling(revert: boolean)
	local selling = S.selling
	S.selling = nil
	cancel(S.sellWait)
	S.sellWait = nil
	if not selling or not revert then
		return
	end
	local card = S.cards[selling.slot]
	if card and card.look == "busy" and card.info and card.info.uid == selling.uid then
		TankCards.setLook(card, lookFor(), S.wide)
	end
end

onSell = function(card: Card)
	local info = card.info
	if not isOpen() or card.kind ~= "fish" or not info or card.gone or card.look == "busy" then
		return
	end
	if S.confirm ~= card then
		-- Первое нажатие: «ТОЧНО?» с кольцом на ConfirmTime с, доход карточки — красным «−$4/с».
		stopConfirm(true)
		S.confirm = card
		S.confirmAt = os.clock()
		TankCards.setLook(card, "confirm", S.wide)
		TankCards.showLoss(card, true)
		if card.rate then
			UiFx.punch(card.rate, { from = 0.8, peak = 1.2 })
		end
		if card.sell then
			UiFx.morphFlash(card.sell)
			-- (над кнопкой, снаружи её обводки: под ней кольцо не видно)
			S.ring = UiFx.ringTimer(card.sell, TankConfig.ConfirmTime, { pad = 4, z = RING_Z, thickness = 4 })
		end
		UiFx.sound("tick", 0.4, 1.25)
		S.confirmEnd = task.delay(TankConfig.ConfirmTime, function()
			S.confirmEnd = nil
			if S.confirm == card then
				stopConfirm(true)
			end
		end)
		return
	end
	if os.clock() - S.confirmAt < TankConfig.ConfirmArm then
		return -- двойной тап: второе нажатие слишком рано
	end
	-- Второе нажатие: продать. Кнопка ждёт ответа сервера (⏳).
	stopConfirm(false)
	TankCards.showLoss(card, false)
	TankCards.setLook(card, "busy", S.wide)
	endSelling(true)
	S.selling = { uid = info.uid, slot = card.slot }
	local event = S.sellEvent
	if event then
		event:FireServer(info.uid)
	end
	S.sellWait = task.delay(PANEL.SellWait, function()
		S.sellWait = nil
		endSelling(true)
	end)
end

-- Витрину slot показывает другая карточка (рыба легла, ушла, заменена); loud — с «выскоком».
local function replace(slot: number, info: Info?, loud: boolean)
	local old = S.cards[slot]
	if S.confirm == old then
		stopConfirm(false)
	end
	local card = makeCard(slot, info)
	S.cards[slot] = card
	if old then
		TankCards.destroy(old)
	end
	if loud then
		UiFx.popIn(card.frame, { from = 0.5, rotate = -6 })
		if info then
			UiFx.glowRing(card.frame, { color = rarityColor(info), scale = 1.2, time = 0.6, thickness = 4 })
		end
	end
	tick()
	updateHeader()
end

-- Продана: карточка сжимается, рыба уходит, на её месте выскакивает пустая с золотым кольцом.
local function saleJuice(slot: number)
	local card = S.cards[slot]
	if not card or card.gone then
		return
	end
	card.gone = true
	if card.info then
		S.lastSale = { uid = card.info.uid, slot = slot }
	end
	if S.confirm == card then
		stopConfirm(false)
	end
	local scale = UiFx.scaleOf(card.frame)
	UiFx.tween(scale, PANEL.SquashTime, { Scale = PANEL.Squash }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local viewport = card.frame:FindFirstChild("Viewport")
	if viewport and viewport:IsA("GuiObject") then
		UiFx.popOut(viewport, { time = PANEL.SquashTime })
	end
	UiFx.rimFlash(card.frame, { time = PANEL.SquashTime + 0.1 })
	task.delay(PANEL.SquashTime, function()
		if S.cards[slot] ~= card then
			return -- панель закрылась или карточку уже заменили
		end
		replace(slot, nil, false)
		local fresh = S.cards[slot]
		UiFx.popIn(fresh.frame, { from = 0.4 })
		UiFx.glowRing(fresh.frame, { color = UIConfig.Palette.Gold.Top, scale = 1.25, time = 0.55, thickness = 4 })
	end)
end

-- Перечитать витрину slot (одно отложенное на витрину: по её Event / State).
local function refreshSlot(slot: number)
	S.refresh[slot] = nil
	if not isOpen() or slot > S.slots then
		return
	end
	local card = S.cards[slot]
	if not card or card.gone then
		return
	end
	local info, kind = readSlot(slot)
	local oldUid = if card.info then card.info.uid else nil
	local newUid = if info then info.uid else nil
	if oldUid == newUid then
		if info and card.info and (info.value ~= card.info.value or info.growFrom ~= card.info.growFrom) then
			card.info = info
			tick()
		end
		return
	end
	local selling = S.selling
	if oldUid and selling and selling.uid == oldUid then
		endSelling(false)
	end
	if oldUid and not newUid and (kind == "sold" or (selling and selling.uid == oldUid)) then
		saleJuice(slot)
		updateHeader()
		return
	end
	replace(slot, info, kind == "in" or kind == "swap")
end

local function watchSlots()
	S.trove:Clean()
	for slot = 1, MAX_SLOTS do
		local model = slotModel(slot)
		if model then
			S.trove:Connect(model.AttributeChanged, function(name: string)
				if (name == "Event" or name == "State") and not S.refresh[slot] then
					S.refresh[slot] = true
					task.defer(refreshSlot, slot)
				end
			end)
		end
	end
end

local function hideBadge()
	local hud = S.hud
	local column = hud and hud:FindFirstChild("RightButtons")
	local button = column and column:FindFirstChild("TankButton")
	local badge = button and button:FindFirstChild("Badge")
	if badge and badge:IsA("GuiObject") and badge.Visible then
		UiFx.badgeHide(badge)
	end
end

local function focus(uid: string?)
	local frame = S.cardsFrame
	if not uid or not frame then
		return
	end
	for slot, card in S.cards do
		if card.info and card.info.uid == uid then
			local col = (slot - 1) % math.max(S.cols, 1)
			local x = col * (S.cell.X + S.gap)
			frame.CanvasPosition = Vector2.new(math.clamp(x, 0, math.max(S.canvasW - S.windowW, 0)), 0)
			UiFx.punch(card.frame, { delay = 0.15 })
			UiFx.glowRing(card.frame, { color = rarityColor(card.info), scale = 1.25, time = 0.7, thickness = 5 })
			return
		end
	end
end

-- Если показ рыбы в кнопке ещё идёт (CounterHold) — открыть сразу после прилёта.
local function deferOpen(uid: string?)
	S.pending = uid or S.pending or true
	local hud = S.hud
	if S.pendingConn or not hud then
		return
	end
	S.pendingConn = hud:GetAttributeChangedSignal("CounterHold"):Connect(function()
		if hud:GetAttribute("CounterHold") ~= nil then
			return
		end
		local conn = S.pendingConn
		S.pendingConn = nil
		if conn then
			conn:Disconnect()
		end
		local want = S.pending
		S.pending = nil
		task.defer(function()
			TankPanelController.Open(if type(want) == "string" then want else nil)
		end)
	end)
end

--------------------------------------------------------------------------------
-- Сервер
--------------------------------------------------------------------------------

local function celebrate(amount: number, from: GuiObject?)
	-- MoneyController — через require в миг вызова (не на загрузке: его модуль может ждать нас).
	local module = Controllers:FindFirstChild("MoneyController")
	if not module or not module:IsA("ModuleScript") then
		return
	end
	local money: any = (require :: any)(module)
	local party = money.Celebrate :: (number, GuiObject?, { Rate: string }) -> () -- (в миг вызова)
	if type(party) == "function" then
		party(amount, from, { Rate = "down" })
	end
end

-- «+$45» золотом поднимается из карточки (над листом); монеты в кошелёк — Celebrate.
local function floatFrom(frame: GuiObject, amount: number)
	local hud = S.hud
	if not hud then
		return
	end
	local area = hud.AbsoluteSize
	if area.X <= 0 or area.Y <= 0 then
		return
	end
	local size = frame.AbsoluteSize
	local centre = frame.AbsolutePosition + size / 2 - hud.AbsolutePosition
	local gold = UIConfig.Palette.Gold
	UiFx.floatText(hud, TextUtil.fill(TEXTS.Pop, { amount = TankRules.FormatMoney(amount) }), {
		position = UDim2.fromScale(centre.X / area.X, centre.Y / area.Y),
		size = UDim2.fromScale(size.X * 1.1 / area.X, size.Y * 0.2 / area.Y),
		colors = { UIConfig.White, gold.Top, gold.Bottom },
		rise = 0.1,
		time = 0.9,
		z = FLOAT_Z,
	})
end

local function onSold(data: { [string]: any })
	local amount = if typeof(data.Amount) == "number" then data.Amount else 0
	local items = data.Items
	local first = if type(items) == "table" then items[1] else nil
	local uid = if type(first) == "table" and typeof(first.Uid) == "string" then first.Uid else nil
	local selling = S.selling
	endSelling(false)
	local from: GuiObject? = nil
	if isOpen() and uid then
		local slot: number? = if selling and selling.uid == uid then selling.slot else nil
		local last = S.lastSale
		if not slot and last and last.uid == uid then
			slot = last.slot
		end
		for index, card in S.cards do
			if card.info and card.info.uid == uid then
				slot = index
			end
		end
		local card = if slot then S.cards[slot] else nil
		if slot and card then
			from = card.frame
			if card.info and card.info.uid == uid then
				saleJuice(slot)
			end
		end
	end
	if amount > 0 then
		if from then
			floatFrom(from, amount)
		end
		celebrate(amount, from)
	end
end

local function onDenied(data: { [string]: any })
	local reason = if typeof(data.Reason) == "string" then data.Reason else ""
	local text = if typeof(data.Text) == "string" then data.Text else (TEXTS.Denied[reason] or "")
	local selling = S.selling
	endSelling(true)
	if isOpen() and selling then
		local card = S.cards[selling.slot]
		if card then
			UiFx.wiggle(card.frame, 8, 3, 0.45)
		end
	end
	if text ~= "" then
		NotifyController.Show(text, "warning")
	end
end

--------------------------------------------------------------------------------
-- Открыть / закрыть
--------------------------------------------------------------------------------

local function onClose(_reason: string)
	stopConfirm(true)
	cancel(S.tick)
	S.tick = nil
	S.trove:Clean()
	table.clear(S.refresh)
end

local function onClosed(_reason: string)
	clearCards()
end

function TankPanelController.Open(focusUid: string?): boolean
	local sheet = S.sheet
	if not sheet then
		return false
	end
	if sheet:IsOpen() then
		focus(focusUid)
		return true
	end
	local why = sheet:Busy()
	if why == "hold" then
		deferOpen(focusUid)
		return false
	elseif why then
		return false
	end
	S.slots = slotCount()
	S.base = ownBase()
	clearCards()
	endSelling(false)
	if not sheet:Open() then
		return false
	end
	buildCards()
	watchSlots()
	updateHeader()
	applyRate(false)
	local items: { GuiObject } = {}
	for slot = 1, S.slots do
		local card = S.cards[slot]
		if card then
			table.insert(items, card.frame)
		end
	end
	if S.locked then
		table.insert(items, S.locked.frame)
	end
	UiFx.staggerPop(items, { from = 0.3, gap = PANEL.Stagger, delay = 0.1 })
	local icon = S.head.Icon
	if icon then
		UiFx.punch(icon, { delay = 0.12 })
	end
	cancel(S.tick)
	S.tick = task.delay(PANEL.Tick, tickLoop)
	hideBadge()
	focus(focusUid)
	return true
end

function TankPanelController.Close()
	if S.sheet then
		S.sheet:Close("api")
	end
end

function TankPanelController.Toggle(): boolean
	if isOpen() then
		if S.sheet then
			S.sheet:Close("toggle")
		end
		return true
	end
	return TankPanelController.Open()
end

function TankPanelController.IsOpen(): boolean
	return isOpen()
end

function TankPanelController.Relayout()
	if S.sheet and isOpen() then
		S.sheet:Place()
	end
end

function TankPanelController.Card(slot: number | string): GuiObject?
	if slot == "locked" then
		return if S.locked then S.locked.frame else nil
	end
	local card = S.cards[slot :: number]
	return if card then card.frame else nil
end

function TankPanelController.Stats(): { [string]: any }
	local count = 0
	for _ in S.cards do
		count += 1
	end
	return {
		cards = count + (if S.locked then 1 else 0),
		ticking = S.tick ~= nil,
		confirm = if S.confirm then S.confirm.slot else nil,
		selling = if S.selling then S.selling.uid else nil,
		pending = S.pending ~= nil,
		wide = S.wide,
		cell = S.cell,
	}
end

function TankPanelController:Start(hud: ScreenGui)
	S.hud = hud
	local root = hud:WaitForChild("TankPanel") :: GuiObject
	local panel = root:WaitForChild("Panel") :: GuiObject
	local header = panel:WaitForChild("Header") :: GuiObject
	local cards = panel:WaitForChild("Cards") :: ScrollingFrame
	S.cardsFrame = cards
	S.grid = cards:FindFirstChildOfClass("UIGridLayout")
	S.padding = cards:FindFirstChildOfClass("UIPadding")
	local names: { [string]: string } = { fish = "CardTemplate", empty = "EmptyTemplate", locked = "LockedTemplate" }
	for kind, name in names do
		S.templates[kind] = cards:WaitForChild(name) :: GuiObject
	end
	local count = header:FindFirstChild("Count")
	S.head = {
		Icon = header:FindFirstChild("Icon"),
		Count = count,
		CountLabel = if count then count:FindFirstChild("Label") else nil,
		Rate = header:FindFirstChild("Rate"),
		Total = header:FindFirstChild("Total"),
		Market = header:FindFirstChild("Market"),
	}
	S.sellEvent = Net.Event("TankSell")
	S.sheet = Sheet.new(hud, root, {
		Layout = PANEL,
		Token = "Night",
		contentWidth = contentWidth,
		onPlace = onPlace,
		onClose = onClose,
		onClosed = onClosed,
	})

	local close = panel:WaitForChild("Close") :: GuiButton
	UiFx.press(close, { sound = "click" })
	close.Activated:Connect(function()
		if S.sheet then
			S.sheet:Close("close")
		end
	end)

	Net.Event("TankEvent").OnClientEvent:Connect(function(kind: any, data: any)
		local payload = if type(data) == "table" then data else {}
		if kind == "Open" then
			if isOpen() then
				local icon = S.head.Icon
				if icon then
					UiFx.punch(icon) -- (уже открыта: только «кивок» 🐠, лист у краёв своего места)
				end
			else
				TankPanelController.Open()
			end
		elseif kind == "Sold" then
			onSold(payload)
		elseif kind == "Denied" then
			onDenied(payload)
		end
	end)

	player.AttributeChanged:Connect(function(name: string)
		if not isOpen() then
			return
		end
		if name == "SellRatePct" then
			applyRate(true)
		elseif name == "TankCount" or name == "Income" then
			updateHeader()
		elseif name == "TankSlots" or name == "BaseIndex" then
			task.defer(function()
				if not isOpen() then
					return
				end
				S.slots = slotCount()
				S.base = ownBase()
				if S.sheet then
					S.sheet:Place()
				end
				buildCards()
				watchSlots()
				updateHeader()
			end)
		end
	end)
end

return TankPanelController
