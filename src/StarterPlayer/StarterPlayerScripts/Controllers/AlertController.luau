--!strict
--[[
	AlertController — тревога хозяина (Этап 4): «у тебя крадут» и всё, что это сопровождает
	(docs/stage4_design.md §1.2, §6.3; плашка — HUD.TheftAlert, tools/builder/gui/Alert.luau;
	числа — UIConfig.Theft, тексты — StealConfig.Texts.Alert / Result, DefenceConfig.Texts.Tips).

	Что делает:
	  • StealEvent "Alert" (сервер: начало удержания и начало выноса; громко — раз в AlertCoalesce с
	    на пару вор–жертва, остальные Quiet) — тревога: атрибут HUD AlertPhase = "hold" | "carry"
	    (кнопка «ЗАЩИТА» становится «ЩИТ!», DefenceController) и FishingController.HurryCard()
	    (тревога важнее карточки улова, DC-02: карточка закрывается обычным путём, полёт в «САДОК»
	    доигрывает);
	  • слои без места на экране (с первого кадра): тонкая красная пульсация краёв
	    (UiFx.edgeVignette: Theft.Edge — полоса Phone / Other, период Period, непрозрачность не
	    больше Alpha: без вспышек экрана), HudController.HomeAlert(true) (красные кольца у «ДОМОЙ»,
	    «ДОМОЙ!»), Theft.Pings «пина» через Theft.PingGap с (не при Quiet);
	  • плашка HUD.TheftAlert — когда карточки улова нет и CounterHold снят (через Theft.CardAfter
	    с; кража ещё идёт): вверху колонки уведомлений (NotifyController.Reserve("alert", px) —
	    уведомления ниже), ширина — min(Theft.Width ширины, Theft.WidthMax, колонки), высота
	    Theft.PlateHeight на телефоне; текст слева — «ВОР В САДКЕ!» / «Ника крадёт: Окунь»,
	    вынос — «ВОР УБЕГАЕТ!» / «Ника уносит: Окунь — жми ЩИТ!» (щит не готов — без «жми ЩИТ!»),
	    справа — [🛡️ ЩИТ] (самая крупная цель: ≥ Theft.ShieldMin px и ≥ Theft.ShieldShare ширины
	    плашки; щит перезаряжается — Slate «⏳ 1:12», нажатие качает её; ⏳ — пока сервер не
	    ответил) и [🏠 ДОМОЙ] (HudController.PressHome; «ДОМОЙ» на кулдауне — Slate); сам
	    крадёшь — без кнопок, «Пока крадёшь сам, щит не включить» (DC-04). Выскакивает с
	    дрожью (Quiet — тихо, без дрожи);
	  • на телефоне (HUD ниже SHORT px), если плашка легла бы на своего рыбака
	    (FishingLayout.fisherBox, а не вышло спроецировать — fallbackFisher) — «таблетка» Compact
	    («🚨 ВОР! ОКУНЬ» + ЩИТ во всю её высоту, щит не готов — 🏠) на первом свободном месте:
	    AlertLayout (справа от рыбака до колонки, иначе слева, иначе в колонке уведомлений —
	    самая широкая, что встаёт; ≥ 16 px и обводки до рыбака, своего поплавка, плашек статуса,
	    колонки кнопок, кнопки прыжка, джойстика, виджетов рыбалки и полосы кражи; тесно — с
	    запасом только на обводки, потом уже, до COMPACT.Narrow: надпись прячется, ЩИТ — во всю
	    ширину). Место пересчитывается по событиям (рыбалка, виджеты появились или сдвинулись —
	    не чаще PLACE_SOON, предметы в руках, экран), не каждый кадр;
	  • кнопки не забирают ввод мини-игры (её ввод — только кнопка действия);
	  • конец — StealEvent "Saved" / "Lost" (запасной — у своей базы снят Thief): плашка уходит,
	    AlertPhase снят, слои гаснут; итог — уведомление: украли — «Украдено: Окунь (Ника)» (вид
	    theft, крупно), «Садок отдыхает 1:30 — никто не украдёт» (Until / Kind сервера) и ОДИН
	    совет (щит был готов и не нажат — про щит, иначе самая дешёвая защита, которой нет, с
	    ценой; DC-14); спасли — текст сервера (вид saved; щит — вид shield; поймал вора —
	    конфетти); Quiet — ничего;
	  • "Intruder" (сигнализация) — «👀 Ника у тебя во дворе!» (warning) и кнопка «ЗАЩИТА»
	    подпрыгивает Theft.IntruderBob с; "Returned" жертве (вор ушёл, рыба вернулась: у неё есть
	    Result) — текст сервера (вид saved). "Returned" вору (рыба вернулась хозяину) — его
	    (TheftController).
	Соединения тревоги — в Trove (слои, ожидание карточки, место); покой — ни одного покадрового
	соединения (пульсации и кольца — твины и таймеры).

	API (тесты, превью):
	  AlertController.Stats() -> { phase, shown ("plate" | "compact" | nil), spot, waiting, busy,
	    rect (px HUD), fisher (свой рыбак при раскладке на телефоне) }
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local DefenceConfig = require(Config:WaitForChild("DefenceConfig"))
local StealConfig = require(Config:WaitForChild("StealConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local FishingRules = require(Shared:WaitForChild("FishingRules"))
local Net = require(Shared:WaitForChild("Net"))
local StealRules = require(Shared:WaitForChild("StealRules"))
local TankRules = require(Shared:WaitForChild("TankRules"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Controllers = script.Parent
local NotifyController = require(Controllers:WaitForChild("NotifyController"))
local HudController = require(Controllers:WaitForChild("HudController"))
local DefenceController = require(Controllers:WaitForChild("DefenceController"))
local DefenceCards = require(Controllers:WaitForChild("DefenceCards"))
local FishingLayout = require(Controllers:WaitForChild("FishingLayout"))
local AlertLayout = require(Controllers:WaitForChild("AlertLayout"))

type Rect = FishingLayout.Rect

local player = Players.LocalPlayer
local TEXTS = StealConfig.Texts.Alert
local RESULT = StealConfig.Texts.Result
local THEFT = UIConfig.Theft
local Palette = UIConfig.Palette
local SHORT = 500 -- HUD ниже — телефон: тревога не ложится на своего рыбака (как FishingController)
local GAP = 16 -- до соседей, px
local INK = 8 -- обводки (своя и соседей) и наклонённые значки выступают за коробки, px
local OWN_INK = 4 -- обводка «таблетки» (Theme.plate), px
local WIDGET_INK = 6 -- обводки и «губы» соседних виджетов (мини-игра, кнопки) за их коробками, px
local SLACK = 4 -- «таблетка»: сверх 16 px и обводок, пока место есть (тесно — без него), px
local STATUS_INK = 10 -- цифры кошелька и его 💵 свисают под коробку своей строки, px
local PLATE_SHARE = 0.22 -- плашка: доля высоты HUD (Theft.PlateHeight..× 1.35 px)
local PLATE_GROW = 1.35
-- «таблетка»: ширина, px (Narrow — тесно: без надписи, 🚨 и кнопка); шаг поиска места вниз;
-- надпись не уже LabelMin px (иначе её нет, кнопка ЩИТ — во всю оставшуюся ширину)
local COMPACT_SHIELD = 0.42 -- ЩИТ «таблетки» — доля её ширины (как в gui/Alert.luau)
local COMPACT = { Min = 160, Narrow = 132, Max = 300, Step = 8, LabelMin = 56 }
local PLACE_SOON = 0.12 -- виджет рыбалки сдвинулся — новое место «таблетки» не чаще, с
local SHAKE = 0.01 -- дрожь при появлении: доля HUD (≈ 8 px на телефоне)
local SHIELD_WAIT = 3 -- ⏳ на ЩИТ, пока сервер не ответил (не дольше), с
local RESULT_AFTER = 0.25 -- итог — когда плашка ушла (место колонки снова уведомлений), с
local ICON_HOLD = "🚨"
local ICON_CARRY = "🏃"
local FISHING_WIDGETS = { "Minigame", "BiteAlert", "Hint", "CatchCard", "ActionArea" }
local BOBBER = { Dive = 1.8, Clear = 12 } -- свой поплавок: нырок клюёт до 1.8 studs (как BiteAlert)
local STICK_SMALL = { right = 95, top = 90 } -- джойстик Roblox (зеркало кнопки прыжка; Sheet)
local STICK_BIG = { right = 180, top = 210 }

type Alert = {
	phase: string,
	name: string,
	short: string,
	thief: number?,
	readyAtStart: boolean, -- щит был готов, когда тревога пришла (совет после кражи)
	tried: boolean, -- ЩИТ нажат за эту тревогу
}

local AlertController = {}

-- Всё состояние — в одной таблице (свободные регистры верхнего уровня).
local A = {
	hud = nil :: ScreenGui?,
	root = nil :: GuiObject?,
	parts = {} :: { [string]: any },
	alert = nil :: Alert?,
	shown = nil :: string?, -- "plate" | "compact"
	spot = nil :: string?, -- где «таблетка» (AlertLayout)
	rect = nil :: Rect?,
	fisher = nil :: Rect?, -- свой рыбак при последней раскладке (телефон)
	waiting = false, -- ждём, пока закроется карточка улова
	busy = false, -- ЩИТ нажат, ждём ответа сервера
	busyWait = nil :: thread?,
	layers = Trove.new(), -- пульсация краёв, «ДОМОЙ!», «пины»
	wait = Trove.new(), -- ожидание карточки
	live = Trove.new(), -- пока плашка видна: место по событиям, отсчёт «⏳ 1:12»
	tickGen = 0,
	base = nil :: Instance?,
	baseConn = nil :: RBXScriptConnection?,
}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function cancel(thread: thread?)
	if thread and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
end

local function guiChild(parent: Instance?, name: string): GuiObject?
	local found = if parent then parent:FindFirstChild(name) else nil
	return if found and found:IsA("GuiObject") then found else nil
end

local function isPhone(): boolean
	local hud = A.hud
	return hud ~= nil and hud.AbsoluteSize.Y > 1 and hud.AbsoluteSize.Y < SHORT
end

local function stealing(): boolean
	return player:GetAttribute("Stealing") ~= nil
end

-- FishingController — в миг вызова (не на загрузке модуля: порядок Start).
local function hurryCard()
	local module = Controllers:FindFirstChild("FishingController")
	if not module or not module:IsA("ModuleScript") then
		return
	end
	local ok, fishing = pcall(function(): any
		return (require :: any)(module)
	end)
	local hurry = if ok and fishing then fishing.HurryCard else nil
	if type(hurry) == "function" then
		pcall(hurry)
	end
end

local function cardUp(): boolean
	local hud = A.hud
	if not hud then
		return false
	end
	local card = guiChild(hud:FindFirstChild("Fishing"), "CatchCard")
	return (card ~= nil and card.Visible) or hud:GetAttribute("CounterHold") ~= nil
end

--------------------------------------------------------------------------------
-- Содержимое
--------------------------------------------------------------------------------

local function setButtonLook(button: GuiObject?, token: string)
	if button and button:GetAttribute("AlertLook") ~= token then
		button:SetAttribute("AlertLook", token)
		UiFx.setCandy(button, token)
	end
end

-- Тексты и вид кнопок по фазе, щиту и «сам крадёшь».
local function fill()
	local a = A.alert
	local p = A.parts
	if not a then
		return
	end
	local ready = DefenceController.ShieldReady()
	local own = stealing()
	local values = { name = a.name, short = a.short }
	if p.title then
		p.title.Text = if a.phase == "carry" then TEXTS.Carry else TEXTS.Hold
	end
	if p.sub then
		local template = if a.phase == "carry"
			then (if ready then TEXTS.CarrySub else TEXTS.CarrySubWait)
			else TEXTS.HoldSub
		p.sub.Text = if own then TEXTS.Stealing else TextUtil.fill(template, values)
	end
	local glyph = if a.phase == "carry" then ICON_CARRY else ICON_HOLD
	if p.icon then
		p.icon.Text = glyph
	end
	if p.compactIcon then
		p.compactIcon.Text = glyph
	end
	if p.buttons and A.shown ~= "compact" then
		p.buttons.Visible = not own -- («таблетке» кнопки плашки не нужны: place)
	end
	if p.text then
		-- сам крадёшь — кнопок нет: текст во всю плашку
		p.text.Size = UDim2.fromScale(if own then 0.88 else p.textShare, p.text.Size.Y.Scale)
	end
	-- ЩИТ: готов — Guard «🛡️ ЩИТ», ждём сервер — «⏳», перезарядка — Slate «⏳ 1:12».
	local left = math.max((tonumber(player:GetAttribute("ShieldReadyAt")) or 0) - now(), 0)
	local wait = TextUtil.fill(TEXTS.ShieldWait, { t = StealRules.FormatClock(left) })
	for _, which in { "shield", "compactShield" } do
		local button = p[which]
		if button then
			local caption, icon = button:FindFirstChild("Caption"), button:FindFirstChild("Icon")
			if A.busy then
				setButtonLook(button, "Slate")
				if caption then
					caption.Text = DefenceConfig.Texts.Buy.Busy
				end
				if icon then
					icon.Visible = false
				end
			elseif ready then
				setButtonLook(button, "Guard")
				if caption then
					caption.Text = TEXTS.Shield
				end
				if icon then
					icon.Visible = true
				end
			else
				setButtonLook(button, "Slate")
				if caption then
					caption.Text = wait
				end
				if icon then
					icon.Visible = false
				end
			end
		end
	end
	if p.compactLabel then
		p.compactLabel.Text = TextUtil.fill(TEXTS.Compact, { short = TextUtil.upper(a.short) })
	end
	-- «таблетка»: ЩИТ, а когда щит не готов — 🏠; сам крадёшь — ни того, ни другого
	if p.compactShield then
		p.compactShield.Visible = not own and (ready or A.busy)
	end
	if p.compactHome then
		p.compactHome.Visible = not own and not ready and not A.busy
	end
	local homeReady = HudController.HomeReady()
	setButtonLook(p.home, if homeReady then "Grape" else "Slate")
	setButtonLook(p.compactHome, if homeReady then "Grape" else "Slate")
end

--------------------------------------------------------------------------------
-- Место
--------------------------------------------------------------------------------

local function rectOf(gui: GuiObject, origin: Vector2): Rect
	local at = gui.AbsolutePosition - origin
	return FishingLayout.rect(at.X, at.Y, at.X + gui.AbsoluteSize.X, at.Y + gui.AbsoluteSize.Y)
end

-- Плашки статуса (по центру стопки: RbxSim не выравнивает UIListLayout) с фишкой щита справа.
local function statusRect(hud: ScreenGui, origin: Vector2): Rect?
	local status = guiChild(hud, "Status")
	if not status or not status.Visible then
		return nil
	end
	local box: Rect? = nil
	local sx, sw = status.AbsolutePosition.X - origin.X, status.AbsoluteSize.X
	for _, item in status:GetChildren() do
		if item:IsA("GuiObject") and item.Visible then
			local w, h = item.AbsoluteSize.X, item.AbsoluteSize.Y
			local x0 = sx + (sw - w) / 2
			local y0 = item.AbsolutePosition.Y - origin.Y
			local x1 = x0 + w
			local chip = guiChild(item, "ShieldChip")
			if chip and chip.Visible then
				x1 += chip.AbsoluteSize.X * (1 - chip.AnchorPoint.X)
			end
			local r = FishingLayout.rect(x0, y0, x1, y0 + h)
			box = if box
				then FishingLayout.rect(
					math.min(box.x0, r.x0),
					math.min(box.y0, r.y0),
					math.max(box.x1, r.x1),
					math.max(box.y1, r.y1)
				)
				else r
		end
	end
	return box
end

-- Колонка кнопок справа: видимые кнопки прижаты к её низу (UIListLayout Bottom).
local function columnRect(hud: ScreenGui, origin: Vector2): Rect?
	local column = guiChild(hud, "RightButtons")
	if not column or not column.Visible then
		return nil
	end
	local list = column:FindFirstChildOfClass("UIListLayout")
	local gap = if list then list.Padding.Scale * column.AbsoluteSize.Y + list.Padding.Offset else 0
	local stack, count, widest = 0, 0, 0
	for _, button in column:GetChildren() do
		if button:IsA("GuiObject") and button.Visible then
			stack += button.AbsoluteSize.Y
			widest = math.max(widest, button.AbsoluteSize.X)
			count += 1
		end
	end
	if count == 0 then
		return nil
	end
	local at = column.AbsolutePosition - origin
	local bottom = at.Y + column.AbsoluteSize.Y
	local x0 = at.X + (column.AbsoluteSize.X - widest) / 2
	return FishingLayout.rect(x0, bottom - stack - gap * (count - 1), x0 + widest, bottom)
end

-- Свой рыбак: спроецированный, на телефоне не вышло — где он у камеры по умолчанию.
local function fisherRect(hud: ScreenGui): Rect?
	local origin = hud.AbsolutePosition
	return FishingLayout.fisherBox(player.Character, Workspace.CurrentCamera, origin)
		or (if isPhone() then FishingLayout.fallbackFisher(hud.AbsoluteSize) else nil)
end

-- Свой поплавок (FishingFxController.GetBobber; его нет — nil).
local function bobberRect(hud: ScreenGui): Rect?
	local module = Controllers:FindFirstChild("FishingFxController")
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, bobber = pcall(function(): any
		return (require :: any)(module).GetBobber(player)
	end)
	if not ok or typeof(bobber) ~= "Instance" or not (bobber :: Instance):IsA("Model") then
		return nil
	end
	return FishingLayout.bobberBox(
		bobber :: Model,
		Workspace.CurrentCamera,
		hud.AbsolutePosition,
		BOBBER.Dive,
		BOBBER.Clear
	)
end

local function plateRect(hud: ScreenGui): Rect
	local size = hud.AbsoluteSize
	local origin = hud.AbsolutePosition
	local toasts = guiChild(hud, "Toasts")
	local column = if toasts
		then rectOf(toasts, origin)
		else FishingLayout.rect(size.X * 0.22, size.Y * 0.26, size.X * 0.78, size.Y * 0.6)
	local height = math.clamp(PLATE_SHARE * size.Y, THEFT.PlateHeight, THEFT.PlateHeight * PLATE_GROW)
	local width = math.min(THEFT.Width * size.X, THEFT.WidthMax)
	-- (≥ 16 px under the status stack's drawn rows: the Wallet's 💵 hangs under its box)
	local status = statusRect(hud, origin)
	local offset = NotifyController.Offset("alert")
	if status then
		offset = math.max(offset, status.y1 + STATUS_INK + GAP + INK - column.y0)
	end
	return AlertLayout.plate(size, column, offset, width, height)
end

-- Где «таблетка» (телефон, плашка легла бы на рыбака): AlertLayout.compact.
local function compactRect(hud: ScreenGui, fisher: Rect): (Rect, string)
	local size = hud.AbsoluteSize
	local origin = hud.AbsolutePosition
	local keepouts: { Rect } = { fisher }
	-- виджет HUD — с обводкой WIDGET_INK вокруг его коробки
	local function widgetOut(r: Rect, below: number?)
		local d = WIDGET_INK
		table.insert(keepouts, FishingLayout.rect(r.x0 - d, r.y0 - d, r.x1 + d, r.y1 + (below or d)))
	end
	local bobber = bobberRect(hud)
	if bobber then
		table.insert(keepouts, bobber)
	end
	local status = statusRect(hud, origin)
	if status then
		widgetOut(status, STATUS_INK) -- (цифры кошелька и его 💵 свисают под коробку строки)
	end
	local column = columnRect(hud, origin)
	if column then
		widgetOut(column)
	end
	if UserInputService.TouchEnabled then
		local camera = Workspace.CurrentCamera
		local view = if camera then camera.ViewportSize else size
		local small = math.min(view.X, view.Y) <= SHORT
		local jump, r = FishingLayout.jumpCircle(size, small)
		table.insert(keepouts, FishingLayout.rect(jump.X - r, jump.Y - r, jump.X + r, jump.Y + r))
		local stick = if small then STICK_SMALL else STICK_BIG
		table.insert(keepouts, FishingLayout.rect(0, size.Y - stick.top, stick.right, size.Y))
	end
	local fishing = guiChild(hud, "Fishing")
	if fishing and fishing.Visible then
		for _, name in FISHING_WIDGETS do
			local widget = guiChild(fishing, name)
			if widget and widget.Visible then
				widgetOut(rectOf(widget, origin))
			end
		end
	end
	local bar = guiChild(hud, "TheftBar")
	if bar and bar.Visible then
		widgetOut(rectOf(bar, origin))
	end
	local toasts = guiChild(hud, "Toasts")
	local toastRect = if toasts then rectOf(toasts, origin) else FishingLayout.rect(0, size.Y * 0.26, size.X, size.Y)
	-- значок 🚨 свисает с левого края «таблетки» — и он не ближе EDGE к краю экрана
	local icon = A.parts.compactIcon
	local overhang = if icon then THEFT.CompactHeight * icon.Size.Y.Scale * icon.AnchorPoint.X else 0
	return AlertLayout.compact({
		fisher = fisher,
		keepouts = keepouts,
		top = FishingLayout.EDGE + INK, -- (под кнопками Roblox вверху: 🚨 выступает над «таблеткой»)
		bottom = size.Y - FishingLayout.EDGE,
		left = FishingLayout.EDGE + overhang,
		right = math.min(
			if column then column.x0 - WIDGET_INK - GAP - OWN_INK else size.X - FishingLayout.EDGE,
			size.X - FishingLayout.EDGE
		),
		column = { x0 = toastRect.x0, x1 = toastRect.x1 },
		height = THEFT.CompactHeight,
		min = COMPACT.Min,
		narrow = COMPACT.Narrow,
		max = COMPACT.Max,
		gap = GAP + OWN_INK + SLACK,
		tight = GAP + OWN_INK,
		step = COMPACT.Step,
	})
end

-- Плашка или «таблетка» на своём месте (px HUD, записанные масштабом); место колонки
-- уведомлений — под ней. Возвращает вариант.
local function place(): string?
	local hud, root = A.hud, A.root
	if not hud or not root then
		return nil
	end
	local size = hud.AbsoluteSize
	if size.X <= 1 or size.Y <= 1 then
		return nil
	end
	local which, r, spot = "plate", plateRect(hud), nil
	A.fisher = nil
	if isPhone() then
		local fisher = fisherRect(hud)
		A.fisher = fisher
		if fisher and FishingLayout.hits(r, fisher) then
			which = "compact"
			r, spot = compactRect(hud, fisher)
		end
	end
	A.rect, A.spot = r, spot
	root.AnchorPoint = Vector2.zero
	root.Position = UDim2.fromScale(r.x0 / size.X, r.y0 / size.Y)
	root.Size = UDim2.fromScale((r.x1 - r.x0) / size.X, (r.y1 - r.y0) / size.Y)
	local p = A.parts
	for _, name in { "plate", "iconRoot", "text", "buttons" } do
		local part = p[name]
		if part then
			part.Visible = which == "plate" and (name ~= "buttons" or not stealing())
		end
	end
	if p.compact then
		p.compact.Visible = which == "compact"
	end
	if which == "compact" then
		-- надпись «ВОР! ОКУНЬ» — между значком 🚨 (свисает с левого края) и кнопкой справа
		local w, h = r.x1 - r.x0, r.y1 - r.y0
		local icon = p.compactIcon
		local iconRight = if icon then h * icon.Size.Y.Scale * (1 - icon.AnchorPoint.X) + 2 else h * 0.2
		local shield, home = p.compactShield, p.compactHome
		local shieldShare = p.compactShieldShare or COMPACT_SHIELD
		local button = if shield and shield.Visible then shieldShare * w elseif home and home.Visible then h else 0
		local room = w - button - 6 - iconRight
		local label = p.compactLabel
		if label then
			label.AnchorPoint = Vector2.new(0, 0.5)
			label.Position = UDim2.fromScale(iconRight / w, 0.5)
			label.Size = UDim2.fromScale(math.max(room, 1) / w, label.Size.Y.Scale)
			label.Visible = room >= COMPACT.LabelMin
		end
		if shield then
			-- надписи нет — ЩИТ во всю ширину справа от 🚨
			local share = if room >= COMPACT.LabelMin then shieldShare else math.max(w - iconRight - 4, 1) / w
			shield.Size = UDim2.new(share, 0, shield.Size.Y.Scale, shield.Size.Y.Offset)
		end
	end
	-- уведомления — под плашкой (и под «таблеткой», если она в их колонке)
	local toasts = guiChild(hud, "Toasts")
	local column = if toasts then rectOf(toasts, hud.AbsolutePosition) else nil
	if which == "plate" then
		NotifyController.Reserve("alert", if column then math.max(r.y1 - column.y0, 0) else r.y1 - r.y0)
	elseif column and r.x0 < column.x1 and r.x1 > column.x0 and r.y0 < column.y0 + (column.y1 - column.y0) / 2 then
		NotifyController.Reserve("alert", math.max(r.y1 - column.y0, 0))
	else
		NotifyController.Reserve("alert", nil)
	end
	A.shown = which
	return which
end

--------------------------------------------------------------------------------
-- Показ и конец
--------------------------------------------------------------------------------

local tick: (gen: number) -> ()

-- Пока щит перезаряжается — «⏳ 1:12» раз в секунду (цепочка task.delay, только пока видна).
function tick(gen: number)
	if gen ~= A.tickGen or not A.alert or not A.shown then
		return
	end
	fill()
	local left = (tonumber(player:GetAttribute("ShieldReadyAt")) or 0) - now()
	if left > 0 then
		local step = left - math.floor(left)
		task.delay(if step > 0.02 then step else 1, tick, gen)
	end
end

local function restartTick()
	A.tickGen += 1
	tick(A.tickGen)
end

local function watchPlace()
	local hud = A.hud
	if not hud then
		return
	end
	local function again()
		if A.shown and A.alert then
			place()
		end
	end
	-- виджет рыбалки сдвинулся (уходит от поплавка, твин): одна раскладка через PLACE_SOON с
	local pending: thread? = nil
	local function soon()
		if pending then
			return
		end
		pending = task.delay(PLACE_SOON, function()
			pending = nil
			again()
		end)
	end
	A.live:Add(function()
		cancel(pending)
		pending = nil
	end)
	A.live:Connect(hud:GetPropertyChangedSignal("AbsoluteSize"), again)
	A.live:Connect(player:GetAttributeChangedSignal("FishingState"), again)
	A.live:Connect(player:GetAttributeChangedSignal("Stealing"), function()
		fill()
		again()
	end)
	A.live:Connect(player:GetAttributeChangedSignal("ShieldReadyAt"), function()
		fill()
		restartTick()
	end)
	A.live:Connect(hud:GetAttributeChangedSignal("Stealing"), again)
	local fishing = hud:FindFirstChild("Fishing")
	for _, name in FISHING_WIDGETS do
		local widget = guiChild(fishing, name)
		if widget then
			A.live:Connect(widget:GetPropertyChangedSignal("Visible"), again)
			A.live:Connect(widget:GetPropertyChangedSignal("Position"), soon)
			A.live:Connect(widget:GetPropertyChangedSignal("Size"), soon)
		end
	end
	local bar = guiChild(hud, "TheftBar")
	if bar then
		A.live:Connect(bar:GetPropertyChangedSignal("Visible"), again)
	end
	local character = player.Character
	if character then
		A.live:Connect(character.ChildAdded, again)
		A.live:Connect(character.ChildRemoved, again)
	end
	local home = guiChild(guiChild(hud, "RightButtons"), "HomeButton")
	local veil = guiChild(home, "Cooldown")
	if veil then
		A.live:Connect(veil:GetPropertyChangedSignal("Visible"), fill)
	end
end

local function show(loud: boolean)
	local root = A.root
	if not root or not A.alert then
		return
	end
	local was = A.shown
	fill()
	place()
	if not was then
		root.Visible = true
		UiFx.popIn(root, { from = 0.4, time = 0.32, rotate = if loud then -5 else nil })
		if loud then
			task.delay(0.3, function()
				if A.shown and A.root then
					UiFx.shake(A.root, SHAKE, 0.35)
				end
			end)
		end
		A.live:Clean()
		watchPlace()
		restartTick()
	elseif loud then
		UiFx.punch(root, { from = 0.85, peak = 1.1 })
	end
end

-- Карточка улова ещё на экране (или 🐟 летит в «САДОК»): плашка — когда закроется (DC-02).
local function showWhenFree(loud: boolean)
	if not cardUp() then
		show(loud)
		return
	end
	if A.waiting then
		return
	end
	A.waiting = true
	local hud = A.hud :: ScreenGui
	local function check()
		if not A.waiting or cardUp() then
			return
		end
		A.waiting = false
		A.wait:Clean()
		A.wait:Add(task.delay(THEFT.CardAfter, function()
			if A.alert and not cardUp() then
				show(loud)
			elseif A.alert then
				showWhenFree(loud)
			end
		end))
	end
	A.wait:Connect(hud:GetAttributeChangedSignal("CounterHold"), check)
	local card = guiChild(hud:FindFirstChild("Fishing"), "CatchCard")
	if card then
		A.wait:Connect(card:GetPropertyChangedSignal("Visible"), check)
	end
end

local function startLayers(quiet: boolean)
	local hud = A.hud
	if not hud then
		return
	end
	A.layers:Clean()
	local edge = THEFT.Edge
	local stop = UiFx.edgeVignette(hud, Palette.Berry.Top, 1 - edge.Alpha, edge.Period, {
		size = if isPhone() then edge.Phone else edge.Other,
		pulseTo = 1 - edge.Alpha * 0.35,
		fadeIn = 0.25,
	})
	A.layers:Add(function()
		stop()
	end)
	HudController.HomeAlert(true)
	A.layers:Add(function()
		HudController.HomeAlert(false)
	end)
	if not quiet then
		for i = 0, THEFT.Pings - 1 do
			A.layers:Add(task.delay(i * THEFT.PingGap, UiFx.sound, "ping", 0.55, 1.35 + 0.1 * i))
		end
	end
end

-- Тревога кончилась: плашка уходит, слои гаснут; then — итог, когда место освободилось.
local function finish(then_: (() -> ())?)
	local had = A.alert ~= nil
	A.alert = nil
	A.waiting = false
	A.wait:Clean()
	A.live:Clean()
	A.layers:Clean()
	A.tickGen += 1
	cancel(A.busyWait)
	A.busyWait = nil
	A.busy = false
	local hud, root = A.hud, A.root
	if hud and had then
		hud:SetAttribute("AlertPhase", nil)
	end
	local wasShown = A.shown ~= nil
	A.shown = nil
	if root and wasShown and root.Visible then
		UiFx.popOut(root, { time = 0.2, hide = true })
		task.delay(0.2, function()
			if not A.shown then
				NotifyController.Reserve("alert", nil)
			end
		end)
	else
		NotifyController.Reserve("alert", nil)
	end
	if then_ then
		task.delay(if wasShown then RESULT_AFTER else 0, then_)
	end
end

local function shortOf(data: { [string]: any }): string
	if typeof(data.Short) == "string" then
		return data.Short
	end
	local fish = data.Fish
	local id = if typeof(fish) == "table" and typeof(fish.Id) == "string" then fish.Id else data.FishId
	local def = if typeof(id) == "string" then FishingRules.GetFish(id) else nil
	return if def then def.ShortName elseif typeof(id) == "string" then id else ""
end

local function onAlert(data: { [string]: any })
	local hud = A.hud
	if not hud then
		return
	end
	local phase = if data.Phase == "carry" then "carry" else "hold"
	local quiet = data.Quiet == true
	local fresh = A.alert == nil
	local a: Alert = A.alert
		or {
			phase = phase,
			name = "",
			short = "",
			thief = nil,
			readyAtStart = DefenceController.ShieldReady(),
			tried = false,
		}
	a.phase = phase
	a.name = if typeof(data.Name) == "string" then data.Name else a.name
	a.short = shortOf(data)
	a.thief = if typeof(data.Thief) == "number" then data.Thief else a.thief
	A.alert = a
	hud:SetAttribute("AlertPhase", phase)
	hurryCard()
	if fresh then
		startLayers(quiet)
	end
	if A.shown then
		fill()
		place()
		if not quiet then
			show(true)
		end
	else
		showWhenFree(not quiet)
	end
end

-- Один совет после кражи (DC-14): щит был готов и не нажат — про щит, иначе самая дешёвая защита.
local function tipFor(a: Alert?): string?
	if a and a.readyAtStart and not a.tried then
		return DefenceConfig.Texts.Tips.Shield
	end
	local item, price = DefenceCards.CheapestItem()
	if item and price then
		return TextUtil.fill(DefenceConfig.Texts.Tips[item], { price = TankRules.FormatMoney(price) })
	end
	return nil
end

local function onLost(data: { [string]: any })
	local a = A.alert
	local name = if typeof(data.Name) == "string" then data.Name elseif a then a.name else ""
	local short = if typeof(data.Fish) == "table" then shortOf(data) elseif a then a.short else ""
	local untilAt = if typeof(data.Until) == "number" then data.Until else nil
	local tip = tipFor(a)
	finish(function()
		NotifyController.Show(TextUtil.fill(RESULT.Lost, { short = short, name = name }), "theft")
		if untilAt and untilAt > now() then
			NotifyController.Show(
				TextUtil.fill(RESULT.LostSub, { t = StealRules.FormatClock(untilAt - now()) }),
				"shield"
			)
		end
		if tip then
			NotifyController.Show(tip, "info", { icon = "💡" })
		end
	end)
end

local function onSaved(data: { [string]: any })
	local reason = data.Reason
	local text = if typeof(data.Text) == "string" then data.Text else ""
	if text == "" then
		local saved = RESULT.Saved
		text = saved[if reason == "tag" or reason == "shield" or reason == "left" then reason else "failed"]
	end
	local quiet = data.Quiet == true
	finish(if quiet
		then nil
		else function()
			NotifyController.Show(text, if reason == "shield" then "shield" else "saved")
			local hud = A.hud
			if reason == "tag" and hud then
				UiFx.confettiPop(hud, { count = 24, origin = Vector2.new(0.5, 0.3), spread = 140, power = 1.2 })
			end
		end)
end

local function onIntruder(data: { [string]: any })
	local name = if typeof(data.Name) == "string" then data.Name else ""
	NotifyController.Show(TextUtil.fill(StealConfig.Texts.Intruder, { name = name }), "warning", {
		icon = StealConfig.Texts.IntruderIcon,
	})
	DefenceController.Bob(THEFT.IntruderBob)
end

-- Своя база: снят Thief (кража кончилась) — запасной конец тревоги, если "Saved" / "Lost" не пришли.
local function bindBase()
	local index = player:GetAttribute("BaseIndex")
	local bases = Workspace:FindFirstChild("Bases")
	local base = if typeof(index) == "number" and index > 0 and bases then bases:FindFirstChild(`Base_{index}`) else nil
	if base == A.base then
		return
	end
	if A.baseConn then
		A.baseConn:Disconnect()
		A.baseConn = nil
	end
	A.base = base
	if base then
		A.baseConn = base:GetAttributeChangedSignal("Thief"):Connect(function()
			if base:GetAttribute("Thief") ~= nil or not A.alert then
				return
			end
			task.delay(1, function()
				if A.alert and base:GetAttribute("Thief") == nil then
					finish(nil)
				end
			end)
		end)
	end
end

--------------------------------------------------------------------------------
-- Кнопки
--------------------------------------------------------------------------------

local function pressShield(button: GuiObject)
	local a = A.alert
	if not a or A.busy or stealing() then
		return
	end
	if not DefenceController.ShieldReady() then
		UiFx.wiggle(button, 7, 2, 0.35) -- (видно, почему: «⏳ 1:12»)
		return
	end
	a.tried = true
	A.busy = true
	fill()
	cancel(A.busyWait)
	A.busyWait = task.delay(SHIELD_WAIT, function()
		A.busyWait = nil
		A.busy = false
		fill()
	end)
	DefenceController.ActivateShield(button)
end

local function pressHome(button: GuiObject)
	if not HudController.HomeReady() then
		UiFx.wiggle(button, 7, 2, 0.3)
		return
	end
	HudController.PressHome()
	UiFx.punch(button, { from = 0.85, peak = 1.1 })
end

function AlertController.Stats(): { [string]: any }
	return {
		phase = if A.alert then A.alert.phase else nil,
		shown = A.shown,
		spot = A.spot,
		waiting = A.waiting,
		busy = A.busy,
		rect = A.rect,
		fisher = A.fisher,
	}
end

function AlertController:Start(hud: ScreenGui)
	A.hud = hud
	local root = hud:WaitForChild("TheftAlert") :: GuiObject
	A.root = root
	root.Visible = false
	local buttons = root:WaitForChild("Buttons") :: GuiObject
	local text = root:WaitForChild("Text") :: GuiObject
	local compact = root:WaitForChild("Compact") :: GuiObject
	local iconSocket = root:FindFirstChild("Icon")
	local compactIcon = compact:FindFirstChild("Icon")
	A.parts = {
		plate = root:FindFirstChild("Plate"),
		icon = if iconSocket then iconSocket:FindFirstChild("Icon") else nil,
		iconRoot = iconSocket,
		text = text,
		textShare = text.Size.X.Scale,
		title = text:FindFirstChild("Title"),
		sub = text:FindFirstChild("Sub"),
		buttons = buttons,
		shield = buttons:FindFirstChild("Shield"),
		home = buttons:FindFirstChild("Home"),
		compact = compact,
		compactIcon = if compactIcon and compactIcon:IsA("TextLabel") then compactIcon else nil,
		compactLabel = compact:FindFirstChild("Label"),
		compactShield = compact:FindFirstChild("Shield"),
		compactHome = compact:FindFirstChild("Home"),
	}
	local compactShield = A.parts.compactShield
	A.parts.compactShieldShare = if compactShield and compactShield:IsA("GuiObject")
		then compactShield.Size.X.Scale
		else nil
	-- (значок над левым краем плашки — «сокет»; его надпись — Icon.Icon)
	if A.parts.icon == nil and iconSocket and iconSocket:IsA("TextLabel") then
		A.parts.icon = iconSocket
	end
	local p = A.parts
	for _, which in { "shield", "compactShield" } do
		local button = p[which]
		if button and button:IsA("GuiButton") then
			UiFx.press(button, { sound = "click" })
			button.Activated:Connect(function()
				pressShield(button)
			end)
		end
	end
	for _, which in { "home", "compactHome" } do
		local button = p[which]
		if button and button:IsA("GuiButton") then
			UiFx.press(button, { sound = "click" })
			button.Activated:Connect(function()
				pressHome(button)
			end)
		end
	end

	Net.Event("StealEvent").OnClientEvent:Connect(function(kind: any, data: any)
		local payload = if type(data) == "table" then data else {}
		if kind == "Alert" then
			onAlert(payload)
		elseif kind == "Saved" then
			onSaved(payload)
		elseif kind == "Lost" then
			onLost(payload)
		elseif kind == "Intruder" then
			onIntruder(payload)
		elseif kind == "Returned" and payload.Result ~= nil then
			-- жертве: вор ушёл, рыба вернулась (у вора Result нет — его уведомление у TheftController)
			if typeof(payload.Text) == "string" and payload.Text ~= "" then
				NotifyController.Show(payload.Text, "saved")
			end
		end
	end)
	Net.Event("DefenceEvent").OnClientEvent:Connect(function(kind: any, data: any)
		local payload = if type(data) == "table" then data else {}
		if kind == "Shield" or (kind == "Denied" and payload.Item == nil) then
			cancel(A.busyWait)
			A.busyWait = nil
			if A.busy then
				A.busy = false
				fill()
			end
		end
	end)
	player:GetAttributeChangedSignal("BaseIndex"):Connect(bindBase)
	bindBase()
end

return AlertController
