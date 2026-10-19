--!strict
--[[
	Sheet — помощник «листа» (Этап 3): модальная панель HUD поверх игры — панель садка
	(TankPanelController), потом магазин Этапа 5. Модуль, не контроллер (его нет в ORDER
	ClientMain). Оболочку листа строит tools/builder/gui/Sheet.luau: корень (HUD.<Имя>, ZIndex 30,
	спрятан) → Panel (плашка) → Strip (тёмная полоса под шапкой), Header (ряд шапки), Close
	(круглый ✕), Cards (ScrollingFrame + UIGridLayout + UIPadding). Стиль —
	tools/builder/gui/STYLE.md.

	Что делает лист:
	  • Open — плашка поднимается снизу на место (без перелёта: она у самых краёв своего места —
	    кнопка прыжка, колонка, стопка статуса; лесенку карточек делает владелец), Close — сжимается
	    к середине (Quad In: только меньше, ни на миг не больше), потом корень прячется; "fishing",
	    "switch" и "alert" — прячется сразу (поклёвке, мини-игре и карточке улова — весь экран и
	    вся заливка; другому листу; тревоге кражи — Этап 4, AlertController). opts.onClose(reason) —
	    сразу (владелец останавливает свои таймеры), opts.onClosed(reason) — когда спрятан
	    (владелец убирает карточки). Открыли снова, пока уходит, — уход отменён, onClosed не
	    будет.
	  • Место (Place) — в px HUD при открытии и при смене ViewportSize, записанное МАСШТАБОМ
	    (UDim2.fromScale: «UDim2 через scale»): слева Margin px, справа min(левый край видимых
	    кнопок HUD.RightButtons, левый край кнопки прыжка Roblox на тач-экране —
	    FishingLayout.jumpCircle) − Margin, сверху низ видимых плашек HUD.Status + Margin (без
	    тач-экрана — не выше ChatBottom: окно чата Roblox слева вверху), снизу HUD − Margin; на
	    тач-экране — ещё и не на джойстике Roblox (правее него + Margin или выше него − Margin: где
	    лист теряет меньшую долю места; телефон — правее): кто хочет идти, жмёт туда, а не в
	    кнопку продажи. Лист — не больше MaxWidth × MaxHeight и не шире, чем нужно карточкам
	    (opts.contentWidth: их ширина и самая большая — владелец может сделать их шире; в
	    несколько рядов чуть не хватает ширины — карточкам до FitShrink — и ниже, по карточкам;
	    на планшете и ПК opts.contentHeight: сколько высоты нужно карточкам при этой ширине —
	    лист не выше),
	    по центру этого места. Так он никогда не закрывает кошелёк (стопка статуса), кнопку
	    «САДОК» (колонка справа) и джойстик; может закрыть кнопку действия (модальный лист).
	    Внутри: шапка — Header доли высоты, HeaderMin..HeaderMax px; ✕ — на правом верхнем углу
	    (не меньше 44 px); окно карточек — под шапкой до низа с отступом Inset; всё — масштабом
	    плашки. opts.onPlace(fit) — владелец раскладывает карточки под это окно.
	  • Вид: на телефоне (HUD ниже TallFrom px) плашка — «стекло» (UiFx.setCandy "Glass": один
	    квад, вторичная информация — на стекле) с тёмной полосой Strip под шапкой; на планшете и
	    ПК — плашка opts.Token (Night).
	  • Сам закрывается, когда рыбалке нужен экран: атрибут игрока FishingState становится "Bite"
	    или "Reeling", у HUD появляется CounterHold, становятся видны HUD.Fishing.BiteAlert /
	    Minigame / CatchCard (reason "fishing"). Busy() — сейчас занято ли («fishing» — рыбалка,
	    «hold» — рыба летит в кнопку: открыть можно сразу после прилёта).
	  • Пока лист открыт, колонка уведомлений (HUD.Toasts) — над ним (ZIndex листа + 1), чтобы
	    подсказки («Этой рыбы уже нет») было видно; закрыт — её ZIndex прежний.
	  • Пока лист открыт и кнопка действия HUD.Fishing.ActionArea под ним (на телефоне лист —
	    стекло: всегда), весь слой рыбалки HUD.Fishing спрятан — «ВЗЯТЬ» с красным «!» и подсказка
	    не просвечивают сквозь лист частью карточки (UX-04); виджеты рыбалки в это время в покое,
	    их собственный Visible лист слушает как прежде; закрыт — слой снова виден.
	  • Всё, что живёт, пока лист открыт (соединения: камера, атрибуты, виджеты рыбалки), — в его
	    Trove: закрыт — соединений как до открытия; закрытый лист ничего не делает.
	  • Один лист на экране (Этап 4): открыли другой — этот закрывается с "switch" и отдаёт ему
	    спрятанный слой рыбалки и прежний ZIndex уведомлений. Пока лист открыт, у HUD атрибут
	    Sheet = имя его корня ("TankPanel", "DefencePanel"; закрыт — снят): по нему тревога кражи
	    не рисует плашку поверх листа (AlertController).

	API:
	  Sheet.new(hud, root, opts) -> Sheet
	    opts = { Layout: { Margin, MaxWidth, MaxHeight, ChatRight, ChatBottom, Header, HeaderMin,
	             HeaderMax, Inset, InsetMin, InsetMax, TallFrom, FitShrink } (TankConfig.Panel),
	             Token: string? (плашка на высоком экране, "Night"),
	             contentWidth: ((cardsHeight: number, tall: boolean) -> (number, number?))?,
	             contentHeight: ((cardsWidth: number, tall: boolean) -> number?)?,
	             onPlace: ((fit: Fit) -> ())?, onClose / onClosed: ((reason: string) -> ())? }
	  sheet:Open() -> boolean          -- false: сейчас нельзя (Busy)
	  sheet:Close(reason: string?)     -- "close" (✕) | "toggle" | "fishing" | "api" …
	  sheet:IsOpen() -> boolean
	  sheet:Busy() -> string?          -- nil | "fishing" | "hold"
	  sheet:Place()                    -- пересчитать место (смена экрана)
	  sheet:Fit() -> Fit?              -- последнее место (px)
	  sheet:Destroy()
	  Sheet.Current() -> Sheet?          -- открытый сейчас лист (один на экране)
	  Sheet.CloseCurrent(reason) -> string? -- закрыть его (имя его корня; nil — листа нет)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UiFx = require(Shared:WaitForChild("UiFx"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local FishingLayout = require(script.Parent:WaitForChild("FishingLayout"))

export type Fit = {
	plate: Vector2, -- лист, px
	position: Vector2, -- его левый верхний угол, px HUD
	header: number, -- высота шапки, px
	headerWidth: number, -- её ширина (до ✕), px
	cards: Vector2, -- окно карточек, px
	tall: boolean, -- HUD не ниже TallFrom (планшет, ПК)
	touch: boolean,
}

-- Числа места (TankConfig.Panel; лишние поля таблицы не мешают).
export type Layout = {
	Margin: number,
	MaxWidth: number,
	MaxHeight: number,
	ChatRight: number,
	ChatBottom: number,
	Header: number,
	HeaderMin: number,
	HeaderMax: number,
	Inset: number,
	InsetMin: number,
	InsetMax: number,
	TallFrom: number,
	FitShrink: number,
}

export type Options = {
	Layout: Layout,
	Token: string?,
	contentWidth: ((cardsHeight: number, tall: boolean) -> (number, number?))?,
	contentHeight: ((cardsWidth: number, tall: boolean) -> number?)?,
	onPlace: ((fit: Fit) -> ())?,
	onClose: ((reason: string) -> ())?,
	onClosed: ((reason: string) -> ())?,
}

export type Sheet = {
	Root: GuiObject,
	Open: (self: Sheet) -> boolean,
	Close: (self: Sheet, reason: string?) -> (),
	IsOpen: (self: Sheet) -> boolean,
	Busy: (self: Sheet) -> string?,
	Place: (self: Sheet) -> (),
	Fit: (self: Sheet) -> Fit?,
	Destroy: (self: Sheet) -> (),
}

local player = Players.LocalPlayer
local BUSY_STATES: { [string]: boolean } = { Bite = true, Reeling = true }
local FISHING_WIDGETS = { "BiteAlert", "Minigame", "CatchCard" }
local CLOSE_TIME = 0.14 -- уход плашки (сжимается к середине: Quad In — только меньше, без «вдоха»), с
local RISE = 18 -- плашка поднимается на место снизу на столько px …
local RISE_TIME = 0.2 -- … за столько секунд (без перелёта: она у самых краёв места)
local CENTRE = UDim2.fromScale(0.5, 0.5) -- Panel: AnchorPoint (0.5, 0.5) в середине корня
local CLOSE_SHARE = 0.7 -- ✕ (AnchorPoint X 0.7) заходит на лист этой долей своей ширины
local SMALL_JUMP = 500 -- короткая сторона экрана ≤ этого — кнопка прыжка маленькая (FishingLayout)
-- Джойстик Roblox на тач-экране (зеркало кнопки прыжка, как FishingController.thumbstickBox):
-- правый край в right px от левого края HUD, верх — в top px от низа.
local STICK_SMALL = { right = 95, top = 90 }
local STICK_BIG = { right = 180, top = 210 }
local INK = 0.3 -- надпись (эмодзи, обводка, наклон) рисуется на столько своей высоты ниже коробки

local Sheet = {}

-- Открытый сейчас лист (один на экране) и что он поменял в HUD: прежний ZIndex колонки
-- уведомлений и «вернуть слой рыбалки» — при "switch" это переходит к новому листу.
local current: Sheet? = nil
type Handoff = { toastsZ: number?, restoreFishing: (() -> ())? }
local handoff: Handoff? = nil

-- Атрибут HUD: имя корня открытого листа (Этап 4: AlertController не рисует тревогу поверх).
local OPEN_ATTR = "Sheet"
-- Причины, по которым лист уходит сразу, без анимации (экран нужен другому).
local INSTANT: { [string]: boolean } = { fishing = true, switch = true, alert = true }

function Sheet.Current(): Sheet?
	local open = current
	return if open and open:IsOpen() then open else nil
end

function Sheet.CloseCurrent(reason: string): string?
	local open = Sheet.Current()
	if not open then
		return nil
	end
	local name = open.Root.Name
	open:Close(reason)
	return name
end

local function scaleOf(px: number, of: number): number
	return if of > 0 then px / of else 0
end

function Sheet.new(hud: ScreenGui, root: GuiObject, opts: Options): Sheet
	local cfg = opts.Layout
	local panel = root:WaitForChild("Panel") :: GuiObject
	local header = panel:WaitForChild("Header") :: GuiObject
	local close = panel:WaitForChild("Close") :: GuiObject
	local cards = panel:WaitForChild("Cards") :: GuiObject
	local strip = panel:FindFirstChild("Strip") :: GuiObject?
	local fishing = hud:FindFirstChild("Fishing")
	local status = hud:FindFirstChild("Status")
	local column = hud:FindFirstChild("RightButtons")

	local open = false
	local switching = false -- закрывается ради другого листа ("switch")
	local trove = Trove.new()
	local coverFishing: () -> ()
	local hiding: thread? = nil
	local lastFit: Fit? = nil
	local toastsZ: number? = nil

	local function widget(name: string): GuiObject?
		local found = if fishing then fishing:FindFirstChild(name) else nil
		return if found and found:IsA("GuiObject") then found else nil
	end

	local function busy(): string?
		if BUSY_STATES[player:GetAttribute("FishingState") :: any] then
			return "fishing"
		end
		for _, name in FISHING_WIDGETS do
			local w = widget(name)
			if w and w.Visible then
				return "fishing"
			end
		end
		if hud:GetAttribute("CounterHold") ~= nil then
			return "hold"
		end
		return nil
	end

	-- Виден ли элемент (он и все его предки до stop).
	local function shown(item: Instance, stop: Instance): boolean
		local node: Instance? = item
		while node and node ~= stop do
			if node:IsA("GuiObject") and not node.Visible then
				return false
			end
			node = node.Parent
		end
		return true
	end

	-- Низ всего видимого в стопке статуса (и того, что свисает с плашек: значок 💵 крупнее строки,
	-- наклонён, у текста — толстая обводка: надписи считаются на INK их высоты ниже коробки) и
	-- левый край видимых кнопок колонки, px HUD.
	local function edges(origin: Vector2): (number?, number?)
		local bottom: number? = nil
		if status then
			for _, item in status:GetDescendants() do
				if item:IsA("GuiObject") and string.sub(item.Name, 1, 2) ~= "Fx" and shown(item, status) then
					local h = item.AbsoluteSize.Y
					local ink = if item:IsA("TextLabel") or item:IsA("TextButton") then h * INK else 0
					local y = item.AbsolutePosition.Y + h + ink - origin.Y
					bottom = math.max(bottom or y, y)
				end
			end
		end
		local left: number? = nil
		if column and column:IsA("GuiObject") and column.Visible then
			for _, child in column:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					local x = child.AbsolutePosition.X - origin.X
					left = math.min(left or x, x)
				end
			end
		end
		return bottom, left
	end

	-- Обводка плашки на этом экране, px (UiFx.fitStrokes: Lip's UIStroke).
	local lip = panel:FindFirstChild("Lip")
	local lipStroke: UIStroke? = if lip then lip:FindFirstChildOfClass("UIStroke") else nil
	local function outline(): number
		return if lipStroke then UiFx.strokeThickness(lipStroke) else 0
	end

	local function place()
		local size = hud.AbsoluteSize
		local W, H = size.X, size.Y
		if W <= 0 or H <= 0 then
			return
		end
		-- (the gaps are kept from the plate's DRAWN edge: its outline lies outside its box)
		local m = cfg.Margin + outline()
		local touch = UserInputService.TouchEnabled
		local statusBottom, columnLeft = edges(hud.AbsolutePosition)
		local right = W - m
		if columnLeft then
			right = math.min(right, columnLeft - m)
		end
		local camera = Workspace.CurrentCamera
		local view = if camera then camera.ViewportSize else size
		local small = math.min(view.X, view.Y) <= SMALL_JUMP
		local chrome = m + 1 -- (до кнопок Roblox — с запасом на округление обводки)
		if touch then
			local jump, r = FishingLayout.jumpCircle(size, small)
			right = math.min(right, jump.X - r - chrome)
		end
		-- (+1 px и здесь: кошелёк чуть «вздрагивает», когда в него летят монеты продажи)
		local top = (statusBottom or 0) + chrome
		if not touch and m < cfg.ChatRight then
			top = math.max(top, cfg.ChatBottom + m - cfg.Margin)
		end
		local left, bottom = m, H - m
		if touch then
			-- Джойстик: лист его не закрывает (ребёнок, который хочет идти, жмёт туда — и попал бы в
			-- кнопку продажи). Лист начинается правее него или кончается выше — где теряет меньшую
			-- долю своего места (телефон — правее, низкий экран не отдаст высоту).
			local stick = if small then STICK_SMALL else STICK_BIG
			local stickTop, stickRight = H - stick.top - chrome, stick.right + chrome
			if bottom > stickTop and left < stickRight then
				local lossW = (stickRight - left) / math.max(right - left, 1)
				local lossH = (bottom - stickTop) / math.max(bottom - top, 1)
				if lossW <= lossH then
					left = stickRight
				else
					bottom = stickTop
				end
			end
		end
		local boxW, boxH = math.max(right - left, 0), math.max(bottom - top, 0)
		local tall = H >= cfg.TallFrom

		local plateH = math.min(boxH, cfg.MaxHeight)
		local inset = math.clamp(plateH * cfg.Inset, cfg.InsetMin, cfg.InsetMax)
		local headerH = math.clamp(plateH * cfg.Header, cfg.HeaderMin, cfg.HeaderMax)
		local side = inset * 0.6
		local cardsTop = headerH + inset * 0.4
		local cardsH = math.max(plateH - cardsTop - inset * 0.6, 0)
		-- карточкам нужно want px при своей ширине и wantMax, если они шире (владелец: в несколько
		-- рядов, когда все столбцы встают); лист — не шире wantMax
		local want, wantMax = math.huge, math.huge
		if opts.contentWidth then
			local least, most = opts.contentWidth(cardsH, tall)
			want, wantMax = least + 2 * side, math.max(most or least, least) + 2 * side
		end
		local plateW = math.min(boxW, cfg.MaxWidth, wantMax)
		local shrink = math.max(plateW - 2 * side, 0) / math.max(want - 2 * side, 1)
		if tall and shrink < 1 and shrink >= cfg.FitShrink and cardsH > 0 then
			-- В несколько рядов карточкам чуть не хватает ширины (владелец сделает их мельче, но не
			-- меньше FitShrink — иначе они листаются): лист ниже — по ним, без пустой полосы внизу
			-- (ширина под карточки растёт с высотой окна линейно).
			plateH = math.min(plateH, cardsTop + cardsH * shrink + inset * 0.6)
			cardsH = math.max(plateH - cardsTop - inset * 0.6, 0)
		end
		if tall and opts.contentHeight and cardsH > 0 then
			-- карточкам при этой ширине нужно меньше высоты (один ряд): лист ниже — по ним
			local need = opts.contentHeight(math.max(plateW - 2 * side, 0), tall)
			if need and need > 0 and need < cardsH then
				plateH = cardsTop + need + inset * 0.6
				cardsH = need
			end
		end
		local x = left + (boxW - plateW) / 2
		local y = top + (boxH - plateH) / 2

		root.Position = UDim2.fromScale(scaleOf(x, W), scaleOf(y, H))
		root.Size = UDim2.fromScale(scaleOf(plateW, W), scaleOf(plateH, H))
		local closePx = math.clamp(headerH, 44, 60)
		close.Size = UDim2.fromScale(scaleOf(closePx, plateH), scaleOf(closePx, plateH))
		local headerW = math.max(plateW - side - CLOSE_SHARE * closePx - inset, 0)
		header.Position = UDim2.fromScale(scaleOf(side, plateW), 0)
		header.Size = UDim2.fromScale(scaleOf(headerW, plateW), scaleOf(headerH, plateH))
		local cardsW = math.max(plateW - 2 * side, 0)
		cards.Position = UDim2.fromScale(scaleOf(side, plateW), scaleOf(cardsTop, plateH))
		cards.Size = UDim2.fromScale(scaleOf(cardsW, plateW), scaleOf(cardsH, plateH))
		-- Телефон — стекло с тёмной полосой под шапкой; планшет и ПК — тёмная плашка.
		UiFx.setCandy(panel, if tall then (opts.Token or "Night") else "Glass")
		if strip then
			strip.Visible = not tall
			strip.Size = UDim2.fromScale(1, scaleOf(headerH + inset * 0.2, plateH))
		end
		local fit: Fit = {
			plate = Vector2.new(plateW, plateH),
			position = Vector2.new(x, y),
			header = headerH,
			headerWidth = headerW,
			cards = Vector2.new(cardsW, cardsH),
			tall = tall,
			touch = touch,
		}
		lastFit = fit
		if opts.onPlace then
			opts.onPlace(fit)
		end
	end

	-- Модальный лист закрывает слой рыбалки (UX-04): кнопка действия «ВЗЯТЬ» с красным «!» и её
	-- подсказка просвечивали сквозь стекло листа телефона частью пустой карточки. Пока лист открыт
	-- и кнопка действия под ним (или лист — стекло), весь HUD.Fishing спрятан; его виджеты в
	-- покое (на поклёвке, мини-игре и карточке улова лист закрывается сам — их собственный Visible
	-- он слушает как прежде). Закрыли лист (trove) — слой снова виден таким, каким его оставил
	-- FishingController.
	function coverFishing()
		local given = handoff
		if given and given.restoreFishing then
			-- (переход с другого листа: слой рыбалки уже спрятан — вернёт его этот лист)
			local restore = given.restoreFishing
			given.restoreFishing = nil
			trove:Add(restore)
			return
		end
		local area = widget("ActionArea")
		local fit = lastFit
		if not (fishing and fishing:IsA("GuiObject") and fishing.Visible and area and fit) then
			return
		end
		local a0, a1 = area.AbsolutePosition, area.AbsolutePosition + area.AbsoluteSize
		local r0, r1 = root.AbsolutePosition, root.AbsolutePosition + root.AbsoluteSize
		local under = a0.X < r1.X and a1.X > r0.X and a0.Y < r1.Y and a1.Y > r0.Y
		if not (under or not fit.tall) then
			return
		end
		local layer = fishing
		layer.Visible = false
		trove:Add(function()
			if switching then
				-- "switch": слой остаётся спрятанным, вернёт его следующий лист
				local into = handoff
				if into then
					into.restoreFishing = function()
						layer.Visible = true
					end
				end
				return
			end
			layer.Visible = true
		end)
	end

	local function finishHide(reason: string)
		hiding = nil
		root.Visible = false
		UiFx.scaleOf(panel).Scale = 1
		panel.Position = CENTRE
		if opts.onClosed then
			opts.onClosed(reason)
		end
	end

	local sheet = {} :: Sheet
	sheet.Root = root

	function sheet.Busy(_self: Sheet): string?
		return busy()
	end

	function sheet.Place(_self: Sheet)
		place()
	end

	function sheet.Fit(_self: Sheet): Fit?
		return lastFit
	end

	function sheet.IsOpen(_self: Sheet): boolean
		return open
	end

	function sheet.Close(self: Sheet, reason: string?)
		if not open then
			return
		end
		open = false
		local why = reason or "api"
		if current == self then
			current = nil
		end
		if hud:GetAttribute(OPEN_ATTR) == root.Name then
			hud:SetAttribute(OPEN_ATTR, nil)
		end
		switching = why == "switch"
		if switching then
			handoff = { toastsZ = toastsZ }
		end
		trove:Clean()
		switching = false
		local toasts = hud:FindFirstChild("Toasts")
		if why ~= "switch" and toasts and toasts:IsA("GuiObject") and toastsZ then
			toasts.ZIndex = toastsZ
		end
		toastsZ = nil
		if opts.onClose then
			opts.onClose(why)
		end
		if INSTANT[why] then
			finishHide(why) -- поклёвка, улов, другой лист, тревога: экран им сразу, без анимации
			return
		end
		-- (Quad In: только сжимается — у UiFx.popOut даже без «вдоха» Back In сперва чуть растёт,
		-- и лист на миг заходил на кнопку прыжка, колонку и окно чата)
		UiFx.tween(UiFx.scaleOf(panel), CLOSE_TIME, { Scale = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		hiding = task.delay(CLOSE_TIME + 0.02, finishHide, why)
	end

	function sheet.Open(self: Sheet): boolean
		if open then
			return true
		end
		if busy() then
			return false
		end
		local other = current
		if other and other ~= self and other:IsOpen() then
			other:Close("switch") -- один лист на экране: тот уходит сразу, его изменения HUD — нам
		end
		current = self
		hud:SetAttribute(OPEN_ATTR, root.Name)
		local pending = hiding
		if pending then
			hiding = nil
			if coroutine.status(pending) == "suspended" then
				task.cancel(pending)
			end
			UiFx.scaleOf(panel).Scale = 1
		end
		open = true
		root.Visible = true
		place()
		-- Появление: плашка поднимается снизу на место (Quart Out; перелёта нет — она у самых
		-- краёв своего места: кнопка прыжка, колонка), «тик»; карточки выскакивают у владельца.
		panel.Position = CENTRE + UDim2.fromOffset(0, RISE)
		UiFx.tween(panel, RISE_TIME, { Position = CENTRE }, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
		UiFx.sound("tick", 0.3, 1.1)
		local toasts = hud:FindFirstChild("Toasts")
		if toasts and toasts:IsA("GuiObject") then
			local given = handoff
			toastsZ = if given and given.toastsZ then given.toastsZ else toasts.ZIndex
			toasts.ZIndex = root.ZIndex + 1
		end
		coverFishing()
		handoff = nil
		local function check()
			if open and busy() then
				self:Close("fishing")
			end
		end
		trove:Connect(player:GetAttributeChangedSignal("FishingState"), check)
		trove:Connect(hud:GetAttributeChangedSignal("CounterHold"), check)
		for _, name in FISHING_WIDGETS do
			local w = widget(name)
			if w then
				trove:Connect(w:GetPropertyChangedSignal("Visible"), check)
			end
		end
		local camera = Workspace.CurrentCamera
		if camera then
			trove:Connect(camera:GetPropertyChangedSignal("ViewportSize"), function()
				if open then
					place()
				end
			end)
		end
		return true
	end

	function sheet.Destroy(self: Sheet)
		self:Close("api")
		if current == self then
			current = nil
		end
		local pending = hiding
		if pending and coroutine.status(pending) == "suspended" then
			task.cancel(pending)
		end
		hiding = nil
		trove:Destroy()
	end

	return sheet
end

return Sheet
