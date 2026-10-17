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
	    TankConfig.Panel.WideCard — полное), сама рыба во ViewportFrame (копия
	    ReplicatedStorage.Assets.Fish[FishId][мутация или Normal]; камера ставится один раз),
	    фишка мутации над левым верхним углом («👑 ×2» в цветах мутации), доход «+$4/с», полоска
	    роста «×1.4» (или золотое «МАКС»), кнопка продажи.
	  • update(card, now, ratePct, wide) — раз в секунду (цепочка панели): возраст —
	    TankRules.AgeAt(GrowFrom, now), полоска и «×N», цена продажи по ставке места
	    TankRules.SellPrice; возвращает цену и растёт ли ещё.
	  • setLook(card, look) — вид кнопки продажи: "home" — Leaf «💵 $45» / «ПРОДАТЬ $45»,
	    "market" — то же Gold (ларёк, ×1.5), "confirm" — Berry «ТОЧНО?», "busy" — Slate «⏳»
	    (ждём сервер). showLoss(card, on) — доход карточки красным «−$4/с» (пока ждём «ТОЧНО?»).
	  • Пустая (make "empty") — стекло, бледная 🎣, «ПУСТО», «Поймай рыбу!»; закрытая (make
	    "locked") — Slate, 🔒, «ЕЩЁ МЕСТО», «Скоро в магазине».
	Всё, что карточка создала (модель рыбы, камера, твин радуги, нажатие кнопки), — в её Trove:
	destroy(card) убирает всё.

	API:
	  TankCards.make(templates, kind, slot, info?, size, wide, onSell?) -> Card  -- size: карточка, px
	  TankCards.update(card, now, ratePct, wide) -> (price: number, growing: boolean)
	  TankCards.setLook(card, look, wide)
	  TankCards.showLoss(card, on)
	  TankCards.income10(info) -> number
	  TankCards.destroy(card)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TankConfig = require(Config:WaitForChild("TankConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local FishingRules = require(Shared:WaitForChild("FishingRules"))
local TankRules = require(Shared:WaitForChild("TankRules"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))

local TEXTS = TankConfig.Texts
local PANEL = TankConfig.Panel
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
	wide: boolean,
	width: number, -- карточка, px (что влезает в подписи)
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
-- (по высоте — высоту, по ширине — диагональ X, Z) в окно aspect = ширина / высота (по размеру
-- карточки: AbsoluteSize ячейки сетки сразу после копии ещё не готов). Ничего не двигается.
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
	local distance = math.max(halfH * 1.15 / vTan, halfLen * 1.05 / hTan, 0.5)
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

-- Влезает ли text в надпись label на её уровне текста (UiFx.textSize), если ширина карточки
-- card — width px (коробка — произведение долей Size от надписи до карточки).
local function fits(text: string, label: GuiObject, card: Instance, width: number): boolean
	local share = 1
	local node: Instance? = label
	while node and node ~= card and node:IsA("GuiObject") do
		share *= node.Size.X.Scale
		node = node.Parent
	end
	local tier = label:GetAttribute("TextTier")
	local px = UiFx.textSize(if typeof(tier) == "string" then tier else "Small")
	return UiFx.textWidth(text, px) <= share * width
end

local function fillFish(card: Card, info: Info, wide: boolean, size: Vector2)
	local frame = card.frame
	local def = FishingRules.GetFish(info.fishId)
	local style = UIConfig.Rarity[info.rarity] or UIConfig.Rarity.Common
	UiFx.setCandy(frame, { Top = style.Top, Bottom = style.Bottom, Lip = style.Lip })
	if style.Rainbow then
		rainbowEdge(card)
	end
	local name = child(frame, "NameLabel")
	if name then
		-- полное имя — на широкой карточке и только если влезает в строку на своём уровне текста
		local full = if def then TextUtil.upper(def.Name) else info.fishId
		local short = if def then TextUtil.upper(def.ShortName) else info.fishId
		name.Text = if wide and fits(full, name, frame, size.X) then full else short
	end
	local chip = child(frame, "Mutation")
	if chip then
		local mutation = if info.mutation then FishingRules.GetMutation(info.mutation) else nil
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

local function captionFor(card: Card, wide: boolean): string
	if card.look == "confirm" then
		return TEXTS.Confirm
	elseif card.look == "busy" then
		return TEXTS.Busy
	end
	local money = TankRules.FormatMoney(card.price)
	local long = TextUtil.fill(TEXTS.SellWide, { sell = TEXTS.Sell, price = money })
	if wide and card.caption and fits(long, card.caption, card.frame, card.width) then
		return long
	end
	return TextUtil.fill(TEXTS.SellPhone, { price = money })
end

local LOOK_TOKENS: { [string]: string } = { home = "Leaf", market = "Gold", confirm = "Berry", busy = "Slate" }

function TankCards.setLook(card: Card, look: string, wide: boolean)
	local sell = card.sell
	if not sell then
		return
	end
	local changed = card.look ~= look
	card.look = look
	card.wide = wide
	if changed then
		UiFx.recolor(sell, LOOK_TOKENS[look] or "Leaf")
	end
	if card.caption then
		card.caption.Text = captionFor(card, wide)
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

function TankCards.update(card: Card, now: number, ratePct: number, wide: boolean): (number, boolean)
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
	if card.caption then
		card.caption.Text = captionFor(card, wide)
	end
	card.wide = wide
	return card.price, not maxed
end

function TankCards.make(
	templates: { [string]: GuiObject },
	kind: string,
	slot: number,
	info: Info?,
	size: Vector2,
	wide: boolean,
	onSell: ((card: Card) -> ())?
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
		wide = wide,
		width = size.X,
	}
	card.trove:Add(frame)
	frame:SetAttribute("Slot", slot)
	if kind == "fish" and info then
		frame:SetAttribute("FishUid", info.uid)
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
