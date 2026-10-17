--!strict
--[[
	TankCards — карточки панели садка (Этап 3; помощник TankPanelController — модуль, не
	контроллер). Копирует шаблоны HUD.TankPanel.Panel.Cards (CardTemplate / EmptyTemplate /
	LockedTemplate, их строит tools/builder/gui/Tank.luau) и рисует на них витрину садка; стиль —
	tools/builder/gui/STYLE.md. Тексты — TankConfig.Texts, суммы — TankRules.FormatMoney /
	FormatRate.

	  • Карточка рыбы (make "fish"): плашка цвета редкости (UIConfig.Rarity; мифическая — ещё
	    радужная обводка, она поворачивается зацикленным твином — без покадровой работы, только
	    пока карточка есть), имя заглавными (короткое FishConfig.ShortName; на карточке шире
	    TankConfig.Panel.WideCard — полное, если влезает), сама рыба во ViewportFrame (копия
	    ReplicatedStorage.Assets.Fish[FishId][мутация или Normal]; камера ставится один раз),
	    фишка мутации над левым верхним углом («👑 ×2» в цветах мутации; имя тогда — правее её
	    значка, полное — только если влезает и так), доход «+$4/с», полоска роста «×1.4» (или
	    золотое «МАКС»), кнопка продажи.
	  • Раскладка карточки рыбы — снизу, в px карточки, записанных долями (TankConfig.Panel.Card):
	    кнопка продажи (≥ SellMin px), над ней — с зазором под обводки и наклон штампа — полоска
	    роста (штамп «МАКС» — в её строке), доход, сверху имя; рыбе — что осталось (на низкой
	    карточке телефона мельче рыба, полоска и «МАКС» видны всегда).
	  • update(card, now, ratePct, wideSell) — раз в секунду (цепочка панели): возраст —
	    TankRules.AgeAt(GrowFrom, now), полоска и «×N», цена продажи по ставке места
	    TankRules.SellPrice; возвращает цену и растёт ли ещё.
	  • setLook(card, look, wideSell) — вид кнопки продажи: "home" — Leaf «💵 $45» (wideSell —
	    «ПРОДАТЬ $45»: одна подпись на всю панель, её решает sellStyle по самой длинной цене reach),
	    "market" — то же Gold (ларёк, ×1.5), "confirm" — Berry «ТОЧНО?», "busy" — Slate «⏳»
	    (ждём сервер). showLoss(card, on) — доход карточки красным «−$4/с» (пока ждём «ТОЧНО?»).
	  • Пустая (make "empty") — стекло (на стеклянном листе телефона — плотнее, Panel.EmptyAlpha:
	    мир сквозь два слоя не читается частью карточки), бледная 🎣, «ПУСТО», «Поймай рыбу!»;
	    закрытая (make "locked") — Slate, 🔒, «ЕЩЁ МЕСТО», «Скоро в магазине».
	Всё, что карточка создала (модель рыбы, камера, твин радуги, нажатие кнопки), — в её Trove:
	destroy(card) убирает всё.

	API:
	  TankCards.make(templates, kind, slot, info?, size, wide, onSell?, onGlass?) -> Card
	                                                -- size: карточка, px; wide: ≥ WideCard (полные
	                                                -- имена); onGlass: лист — стекло (телефон)
	  TankCards.update(card, now, ratePct, wideSell) -> (price: number, growing: boolean)
	  TankCards.setLook(card, look, wideSell)
	  TankCards.reach(info) -> number               -- самая длинная цена рыбы: МАКС у ларька
	  TankCards.sellStyle(template, size, wide, reach) -> boolean -- «ПРОДАТЬ $reach» влезает?
	  TankCards.showLoss(card, on)
	  TankCards.income10(info) -> number
	  TankCards.destroy(card)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TankConfig = require(Config:WaitForChild("TankConfig"))
local EconomyConfig = require(Config:WaitForChild("EconomyConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local FishingRules = require(Shared:WaitForChild("FishingRules"))
local TankRules = require(Shared:WaitForChild("TankRules"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))

local TEXTS = TankConfig.Texts
local PANEL = TankConfig.Panel
local CARD = PANEL.Card
local CAP = TankConfig.Growth.Cap
local Palette = UIConfig.Palette
local LOSS = Palette.Berry.Top -- «−$4/с»: доход, который уйдёт с рыбой
local YAW = math.rad(-25) -- рыба вполоборота (как на карточке улова)
local FOV = 34

export type Info = {
	uid: string,
	fishId: string,
	rarity: string,
	mutation: string?,
	value: number,
	income: number, -- $/с (атрибут витрины Income = Income10 / 10)
	growFrom: number,
}

export type Card = {
	frame: GuiObject,
	kind: string, -- "fish" | "empty" | "locked"
	slot: number,
	info: Info?,
	trove: any,
	sell: GuiButton?,
	caption: TextLabel?,
	rate: TextLabel?,
	look: string, -- "home" | "market" | "confirm" | "busy"
	price: number,
	wideSell: boolean, -- подпись кнопки «ПРОДАТЬ $45» (иначе «💵 $45»): одна на всю панель
	gone: boolean?, -- продана: сжимается, вот-вот уступит место пустой карточке
}

local TankCards = {}

function TankCards.income10(info: Info): number
	return math.round(info.income * 10)
end

local function child(parent: Instance, name: string): any
	return parent:FindFirstChild(name)
end

-- Модель рыбы: Assets.Fish.<Id>.<мутация или Normal>.
local function fishTemplate(info: Info): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local fishFolder = assets and assets:FindFirstChild("Fish")
	local variants = fishFolder and fishFolder:FindFirstChild(info.fishId)
	if not variants then
		return nil
	end
	local model = variants:FindFirstChild(info.mutation or "Normal") or variants:FindFirstChild("Normal")
	return if model and model:IsA("Model") then model else nil
end

-- Рыба во ViewportFrame: центр габаритов в нуле, вполоборота; камера вписывает её один раз
-- (по высоте — высоту, по ширине — диагональ X, Z, с запасом 5 %: окно и так заходит под имя и
-- доход) в окно aspect = ширина / высота (по размеру карточки: AbsoluteSize ячейки сетки сразу
-- после копии ещё не готов). Ничего не двигается.
local function showFish(card: Card, viewport: ViewportFrame, info: Info, aspect: number)
	local template = fishTemplate(info)
	if not template then
		return
	end
	local model = card.trove:Add(template:Clone())
	local box, size = model:GetBoundingBox()
	local centred = model:GetPivot() - box.Position
	model:PivotTo(CFrame.Angles(0, YAW, 0) * centred)
	model.Parent = viewport
	local vTan = math.tan(math.rad(FOV / 2))
	local hTan = vTan * math.max(aspect, 0.1)
	local halfLen = Vector2.new(size.X, size.Z).Magnitude / 2
	local halfH = size.Y / 2
	local distance = math.max(halfH * 1.05 / vTan, halfLen * 1.05 / hTan, 0.5)
	local camera = card.trove:Add(Instance.new("Camera"))
	camera.FieldOfView = FOV
	camera.CFrame = CFrame.lookAt(Vector3.new(0, halfH * 0.3, distance), Vector3.zero)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

-- Мифическая: радужная обводка (градиент на UIStroke Lip), оборот за Panel.RainbowTurn с —
-- зацикленный твин Rotation (TweenService, без своего покадрового Lua).
local function rainbowEdge(card: Card)
	local lip = child(card.frame, "Lip")
	local edge = lip and lip:FindFirstChildOfClass("UIStroke")
	if not edge then
		return
	end
	edge.Color = UIConfig.White
	local gradient = Instance.new("UIGradient")
	gradient.Name = "Rainbow"
	gradient.Color = UiFx.sequence(UIConfig.Rainbow)
	gradient.Parent = edge
	card.trove:Add(gradient)
	local spin = TweenService:Create(
		gradient,
		TweenInfo.new(PANEL.RainbowTurn, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1),
		{ Rotation = 360 }
	)
	spin:Play()
	card.trove:Add(function()
		spin:Cancel()
	end)
end

-- Ширина надписи label в px, если ширина карточки card — width px (произведение долей Size от
-- надписи до карточки), и ширина text на её уровне текста (UiFx.textSize), px.
local function boxWidth(label: GuiObject, card: Instance, width: number): number
	local share = 1
	local node: Instance? = label
	while node and node ~= card and node:IsA("GuiObject") do
		share *= node.Size.X.Scale
		node = node.Parent
	end
	return share * width
end

local function inkWidth(text: string, label: GuiObject): number
	local tier = label:GetAttribute("TextTier")
	return UiFx.textWidth(text, UiFx.textSize(if typeof(tier) == "string" then tier else "Small"))
end

-- Обводка формы (UIStroke её Lip) на этом экране, px: она рисуется снаружи коробки.
local function outline(gui: Instance?): number
	local lip = gui and gui:FindFirstChild("Lip")
	local edge = lip and lip:FindFirstChildOfClass("UIStroke")
	return if edge then UiFx.strokeThickness(edge) else 0
end

--[[
	Карточка рыбы w × h px — СНИЗУ вверх (TankConfig.Panel.Card), всё записано долями карточки:
	кнопка продажи (не ниже SellMin px) над Foot; полоска роста — над её обводкой, с зазором под
	обводку и наклон штампа «МАКС» (он — внутри строки полоски по высоте); доход над полоской; имя
	сверху; рыба — всё, что осталось между именем и доходом, и ещё Overlap их высоты (надписи — над
	ней).
]]
local function layout(frame: GuiObject, size: Vector2)
	local w, h = math.max(size.X, 1), math.max(size.Y, 1)
	local sell = child(frame, "Sell")
	local growth = child(frame, "Growth")
	local rate = child(frame, "Rate")
	local viewport = child(frame, "Viewport")
	local name = child(frame, "NameLabel")
	if not sell or not growth or not rate or not viewport or not name then
		return
	end
	-- строки с текстом — не ниже самого мелкого размера своего уровня (UiFx.fitText: Max − 2), иначе
	-- надпись вылезает из строки на соседнюю (планшет, ПК: текст крупнее, карточка — нет)
	local function least(tier: string): number
		return UiFx.textSize(tier) - 2
	end
	local edge = outline(sell)
	local foot = math.max(CARD.Foot * h, edge + 1.5)
	local sellH = math.max(CARD.SellShare * h, CARD.SellMin)
	local sellTop = h - foot - sellH
	sell.Position = UDim2.fromScale(0.5, (h - foot) / h)
	sell.Size = UDim2.fromScale(sell.Size.X.Scale, sellH / h)
	-- штамп «МАКС»: его обводка и наклон (угол поднимается на половину ширины × sin) — снаружи
	-- строки полоски и сверху, и снизу
	local stamp = child(growth, "Max")
	local stampW = if stamp then stamp.Size.X.Scale * growth.Size.X.Scale * w else 0
	local tilt = if stamp then stampW / 2 * math.abs(math.sin(math.rad(stamp.Rotation))) else 0
	local stampOut = outline(stamp) + tilt
	local label = if stamp then child(stamp, "Label") else nil
	local share = if label then label.Size.Y.Scale else 1
	local growthH = math.max(CARD.GrowthShare * h, CARD.GrowthMin, least("Small") / share)
	local growthTop = sellTop - edge - stampOut - 1 - growthH
	growth.Position = UDim2.fromScale(0.5, growthTop / h)
	growth.Size = UDim2.fromScale(growth.Size.X.Scale, growthH / h)
	local rateH = math.max(CARD.RateShare * h, least("Body"))
	local rateTop = growthTop - stampOut - rateH
	rate.Position = UDim2.fromScale(0.5, rateTop / h)
	rate.Size = UDim2.fromScale(rate.Size.X.Scale, rateH / h)
	local nameTop = CARD.NameTop * h
	local nameH = math.max(CARD.NameShare * h, least("Small"))
	local nameBottom = nameTop + nameH
	name.Position = UDim2.fromScale(0.5, nameTop / h)
	name.Size = UDim2.fromScale(name.Size.X.Scale, nameH / h)
	-- рыба заходит под имя и под доход на Overlap их высоты (надписи — поверх неё, с обводкой)
	local fishTop = nameBottom - CARD.Overlap * nameH
	local fishBottom = rateTop + CARD.Overlap * rateH
	viewport.Position = UDim2.fromScale(0.5, fishTop / h)
	viewport.Size = UDim2.fromScale(viewport.Size.X.Scale, math.max(fishBottom - fishTop, 0) / h)
end

-- Сколько px слева фишка мутации (её значок свисает с левого верхнего угла) закрывает строку
-- имени на карточке шириной w и высотой h: правый край значка (с наклоном фишки) + 2 px.
local function chipCover(chip: GuiObject, w: number, h: number): number
	local chipW, chipH = chip.Size.X.Scale * w, chip.Size.Y.Scale * h
	local icon = child(chip, "Icon")
	local iconW = if icon then icon.Size.X.Scale * chipH else chipH -- (RelativeYY: от высоты фишки)
	local anchor = if icon then icon.AnchorPoint.X else 0
	local left = -chip.AnchorPoint.X * chipW
	return left + (1 - anchor) * iconW + chipH * math.abs(math.sin(math.rad(chip.Rotation))) + 2
end

local function fillFish(card: Card, info: Info, wide: boolean, size: Vector2)
	local frame = card.frame
	local def = FishingRules.GetFish(info.fishId)
	local style = UIConfig.Rarity[info.rarity] or UIConfig.Rarity.Common
	UiFx.setCandy(frame, { Top = style.Top, Bottom = style.Bottom, Lip = style.Lip })
	if style.Rainbow then
		rainbowEdge(card)
	end
	local chip = child(frame, "Mutation")
	local mutation = if info.mutation then FishingRules.GetMutation(info.mutation) else nil
	local name = child(frame, "NameLabel")
	if name then
		-- Фишка мутации свисает на строку имени слева: строка имени — от правого края её значка
		-- (если короткое имя влезает туда хотя бы самым мелким размером своего уровня; иначе —
		-- во всю ширину, как без фишки). Полное имя — на широкой карточке и только если влезает
		-- в строку крупным размером; иначе короткое.
		local full = if def then TextUtil.upper(def.Name) else info.fishId
		local short = if def then TextUtil.upper(def.ShortName) else info.fishId
		local room = name.Size.X.Scale * size.X
		local cover = if mutation and chip then chipCover(chip, size.X, size.Y) else 0
		if cover > 0 then
			local right = (size.X + room) / 2
			local tier = name:GetAttribute("TextTier")
			local least = UiFx.textSize(if typeof(tier) == "string" then tier else "Small") - 2
			if UiFx.textWidth(short, least) <= right - cover then
				room = right - cover
				name.AnchorPoint = Vector2.new(0, name.AnchorPoint.Y)
				name.Position = UDim2.fromScale(cover / size.X, name.Position.Y.Scale)
				name.Size = UDim2.fromScale(room / size.X, name.Size.Y.Scale)
			end
		end
		name.Text = if wide and inkWidth(full, name) <= room then full else short
	end
	if chip then
		local look = if info.mutation then UIConfig.Mutations[info.mutation] else nil
		chip.Visible = mutation ~= nil
		if mutation and look then
			UiFx.setCandy(chip, { Top = look.Top, Bottom = look.Bottom, Lip = look.Lip })
			local icon = child(chip, "Icon")
			if icon then
				icon.Text = look.Icon
			end
			local label = child(chip, "Label")
			if label then
				label.Text = TextUtil.fill(TEXTS.Mutation, { mult = mutation.Multiplier })
			end
		end
	end
	if card.rate then
		card.rate.Text = TankRules.FormatRate(TankCards.income10(info))
	end
	local viewport = child(frame, "Viewport")
	if viewport and viewport:IsA("ViewportFrame") then
		local share = viewport.Size
		local aspect = (share.X.Scale * size.X) / math.max(share.Y.Scale * size.Y, 1)
		showFish(card, viewport, info, aspect)
	end
end

-- «×1.4»: одна цифра после точки, «×3» без «.0».
local function multText(growth: number): string
	local tenths = math.floor(growth * 10 + 1e-6)
	local text = if tenths % 10 == 0
		then string.format("%d", tenths // 10)
		else string.format("%d.%d", tenths // 10, tenths % 10)
	return TextUtil.fill(TEXTS.Growth, { mult = text })
end

local function captionFor(card: Card): string
	if card.look == "confirm" then
		return TEXTS.Confirm
	elseif card.look == "busy" then
		return TEXTS.Busy
	end
	local money = TankRules.FormatMoney(card.price)
	if card.wideSell then
		return TextUtil.fill(TEXTS.SellWide, { sell = TEXTS.Sell, price = money })
	end
	return TextUtil.fill(TEXTS.SellPhone, { price = money })
end

-- Самая длинная цена, до которой дорастёт рыба info: МАКС у ларька.
function TankCards.reach(info: Info): number
	return TankRules.SellPrice(info.value, TankConfig.Growth.Time, EconomyConfig.MarketRatePct)
end

--[[
	Подпись кнопок продажи для ВСЕЙ панели: «ПРОДАТЬ $X», только если на карточке size px так
	влезает самая длинная цена reach (её рыбы ещё дорастут и до неё, и до цены ларька), иначе
	«💵 $X» у всех. Решается при раскладке (и когда в панели появилась рыба дороже), а не на каждой
	цене: соседние кнопки одинаковые, и подпись не меняет вид сама, когда у цены прибавилась цифра.
]]
function TankCards.sellStyle(template: GuiObject, size: Vector2, wide: boolean, reach: number): boolean
	local sell = child(template, "Sell")
	local caption = sell and child(sell, "Caption")
	if not wide or not caption then
		return false
	end
	local long = TextUtil.fill(TEXTS.SellWide, { sell = TEXTS.Sell, price = TankRules.FormatMoney(reach) })
	return inkWidth(long, caption) <= boxWidth(caption, template, size.X)
end

local LOOK_TOKENS: { [string]: string } = { home = "Leaf", market = "Gold", confirm = "Berry", busy = "Slate" }

function TankCards.setLook(card: Card, look: string, wideSell: boolean)
	local sell = card.sell
	if not sell then
		return
	end
	local changed = card.look ~= look
	card.look = look
	card.wideSell = wideSell
	if changed then
		UiFx.recolor(sell, LOOK_TOKENS[look] or "Leaf")
	end
	if card.caption then
		card.caption.Text = captionFor(card)
	end
end

function TankCards.showLoss(card: Card, on: boolean)
	local rate, info = card.rate, card.info
	if not rate or not info then
		return
	end
	local tenths = TankCards.income10(info)
	rate.Text = TankRules.FormatRate(if on then -tenths else tenths)
	rate.TextColor3 = if on then LOSS else UIConfig.MoneyText
end

function TankCards.update(card: Card, now: number, ratePct: number, wideSell: boolean): (number, boolean)
	local info = card.info
	if card.kind ~= "fish" or not info then
		return 0, false
	end
	local age = TankRules.AgeAt(info.growFrom, now)
	local growth = TankRules.Growth(age)
	local maxed = TankRules.IsMaxed(age)
	card.price = TankRules.SellPrice(info.value, age, ratePct)
	local row = child(card.frame, "Growth")
	if row then
		local track, label, stamp = child(row, "Track"), child(row, "Label"), child(row, "Max")
		if track then
			track.Visible = not maxed
			local fill = child(track, "Fill")
			if fill then
				fill.Size = UDim2.fromScale(math.clamp((growth - 1) / math.max(CAP - 1, 1e-6), 0, 1), 1)
			end
		end
		if label then
			label.Visible = not maxed
			label.Text = multText(growth)
		end
		if stamp then
			stamp.Visible = maxed
		end
	end
	card.wideSell = wideSell
	if card.caption then
		card.caption.Text = captionFor(card)
	end
	return card.price, not maxed
end

-- Пустая карточка на стеклянном листе (телефон): стекло плотнее (Panel.EmptyAlpha).
local EMPTY_GLASS = {
	Top = Palette.Glass.Top,
	Bottom = Palette.Glass.Bottom,
	Lip = Palette.Glass.Lip,
	Alpha = PANEL.EmptyAlpha,
}

function TankCards.make(
	templates: { [string]: GuiObject },
	kind: string,
	slot: number,
	info: Info?,
	size: Vector2,
	wide: boolean,
	onSell: ((card: Card) -> ())?,
	onGlass: boolean?
): Card
	local template = templates[kind]
	local frame = template:Clone()
	frame.Name = if kind == "locked" then "Locked" else `Card{slot}`
	frame.LayoutOrder = slot
	frame.Visible = true
	frame.Parent = template.Parent
	local card: Card = {
		frame = frame,
		kind = kind,
		slot = slot,
		info = if kind == "fish" then info else nil,
		trove = Trove.new(),
		look = "home",
		price = 0,
		wideSell = false,
	}
	card.trove:Add(frame)
	frame:SetAttribute("Slot", slot)
	if kind == "empty" and onGlass then
		UiFx.setCandy(frame, EMPTY_GLASS)
	end
	if kind == "fish" and info then
		frame:SetAttribute("FishUid", info.uid)
		layout(frame, size)
		card.rate = child(frame, "Rate")
		local sell = child(frame, "Sell")
		if sell and sell:IsA("GuiButton") then
			card.sell = sell
			card.caption = child(sell, "Caption")
			card.trove:Add(UiFx.press(sell, { sound = "click" }))
			if onSell then
				card.trove:Add(sell.Activated:Connect(function()
					onSell(card)
				end))
			end
		end
		fillFish(card, info, wide, size)
	end
	return card
end

function TankCards.destroy(card: Card)
	card.trove:Destroy()
end

return TankCards
