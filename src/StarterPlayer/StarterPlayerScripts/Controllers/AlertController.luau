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
	    доигрывает); громкая новая тревога закрывает лист «САДОК» (Controllers.Sheet, причина
	    "alert", сразу); лист «ЗАЩИТА» остаётся — его карточка щита сама становится «ЩИТ!»
	    (DefenceCards: то же одно нажатие);
	  • слои без места на экране (с первого кадра): тонкая красная пульсация краёв
	    (UiFx.edgeVignette: Theft.Edge — полоса Phone / Other, период Period, непрозрачность не
	    больше Alpha: без вспышек экрана) в своём обрезающем слое FxAlertEdge (полосы не заходят
	    на верхнюю панель Roblox и вырез; пока у HUD свой край — поклёвка, аура мини-игры, вспышка
	    улова: другой FxVignette, — она спит: края уже светятся, вдвоём — лишняя заливка
	    телефона), HudController.HomeAlert(true) (красные кольца у «ДОМОЙ», «ДОМОЙ!»), Theft.Pings
	    «пина» через Theft.PingGap с (не при Quiet);
	  • плашка HUD.TheftAlert — когда место свободно: нет карточки улова, CounterHold снят и не
	    открыт лист (через Theft.CardAfter с; кража ещё идёт). Пока тревога идёт, новый улов
	    (CounterHold) снова торопит карточку (HurryCard), а карточка или лист, появившись, прячут
	    плашку до своего ухода — плашка никогда не рисуется поверх них. Вверху колонки уведомлений
	    (NotifyController.Reserve("alert", px) — до нарисованного низа плашки, INK; уведомления —
	    ниже на BandGap и не на своём рыбаке: на планшете и ПК они ждут конца тревоги; «таблетка»
	    в колонке или над самым её верхом — так же), ширина — min(Theft.Width
	    ширины, Theft.WidthMax, колонки), высота Theft.PlateHeight на телефоне; на планшете и ПК
	    нарисованный низ плашки — не ближе 16 px к своему рыбаку, если его видно под ней: плашка
	    поднимается к стопке статуса (на 16 px + обводки под ней) и, не хватает и так, ниже ростом,
	    но не ниже Theft.PlateHeight (Этап 4 wave 3, ART-06: губа плашки лежала у него на
	    волосах); текст слева —
	    «ВОР В САДКЕ!» / «Ника крадёт: Окунь», вынос — «ВОР УБЕГАЕТ!» / «Ника уносит: Окунь — жми
	    ЩИТ!» (щит не готов — без «жми ЩИТ!»), справа — [🛡️ ЩИТ] (самая крупная цель:
	    ≥ Theft.ShieldMin px и ≥ Theft.ShieldShare ширины плашки; щит перезаряжается — Slate
	    «⏳ 1:12», нажатие качает её; ⏳ — пока сервер не ответил) и [🏠 ДОМОЙ]
	    (HudController.PressHome; «ДОМОЙ» на кулдауне — Slate); сам крадёшь — без кнопок, «Пока
	    крадёшь сам, щит не включить» (DC-04). Выскакивает с дрожью (Quiet — тихо, без дрожи);
	    уходит с поколением (новая тревога сразу после конца прошлой не прячется её таймером);
	  • на телефоне (HUD ниже SHORT px), если плашка легла бы на своего рыбака
	    (FishingLayout.fisherBox, а не вышло спроецировать — fallbackFisher) — «таблетка» Compact
	    («🚨 ВОР! ОКУНЬ» + ЩИТ во всю её высоту, щит не готов — 🏠; тесно для имени — «ВОР!»,
	    теснее — без надписи; сам крадёшь — «ВОР! ОКУНЬ · щит после кражи» без кнопок) на месте
	    AlertLayout: прежнее, пока оно свободно, иначе самое верхнее свободное (справа от рыбака
	    до колонки, слева, в колонке уведомлений; ≥ 16 px и обводки до рыбака, своего поплавка,
	    плашек статуса, колонки кнопок, кнопки прыжка, джойстика, виджетов рыбалки и полосы
	    кражи), тесно — с запасом только на обводки, потом уже, до COMPACT.Narrow; последний
	    выбор — где закрывает меньше всего, но не у кнопок Roblox (прыжок, джойстик); и его нет —
	    «таблетки» нет (остаётся «ЩИТ!» в колонке). Место пересчитывается по событиям (рыбалка,
	    виджеты появились или сдвинулись — не чаще PLACE_SOON, предметы в руках, экран), не каждый
	    кадр; переезд — твином MOVE_TIME с, не прыжком;
	  • кнопки не забирают ввод мини-игры (её ввод — только кнопка действия);
	  • конец — StealEvent "Saved" / "Lost" (запасной — у своей базы снят Thief): плашка уходит,
	    AlertPhase снят, слои гаснут; итог — уведомление: украли — «Украдено: Окунь (Ника)» (вид
	    theft, крупно; сразу, и поверх листа), «Садок отдыхает 1:30 — не украдут» (Until / Kind
	    сервера) и ОДИН совет (значок DefenceConfig.Texts.TipIcon; щит был готов и не нажат — про
	    щит, иначе самая дешёвая защита, которой нет, с ценой; DC-14); спасли — текст сервера (вид
	    saved; поймал вора — конфетти); щит — одно уведомление «Щит спас рыбу! 🛡️ 1:00»
	    (Result.SavedShield; «Щит включён на 1:00» DefenceController тогда не показывает:
	    DefenceController.TakeShieldToast); Quiet — ничего. Всё, кроме «Украдено», при открытом
	    листе ждёт его ухода (Look.afterSheet: легло бы на шапку с кошельком; на «ЗАЩИТА» итог
	    виден на карточке щита), время — на миг показа (Look.live);
	  • "Intruder" (сигнализация) — «👀 Ника у тебя во дворе!» (warning, метка вора) и кнопка
	    «ЗАЩИТА» подпрыгивает Theft.IntruderBob с; тревога этого вора убирает его
	    (NotifyController.Drop: плашка говорит то же громче); "Returned" жертве (вор ушёл, рыба
	    вернулась: у неё есть Result) — текст сервера (вид saved, ждёт ухода листа). "Returned"
	    вору (рыба вернулась хозяину) — его (TheftController).
	Соединения тревоги — в Trove (слои, ожидание карточки и листа, место); покой — ни одного
	покадрового соединения (пульсации и кольца — твины и таймеры).

	API (тесты, превью):
	  AlertController.Stats() -> { phase, shown ("plate" | "compact" | "none" | nil), spot,
	    waiting, busy, rect (px HUD), fisher (свой рыбак при раскладке на телефоне), label (текст
	    «таблетки» или nil), edge ("on" | "asleep" | nil) }
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
local Sheet = require(Controllers:WaitForChild("Sheet"))

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
-- надпись — самая полная, что влезает (имя рыбы, «ВОР!»), с запасом LabelPad px; не влезает и
-- «ВОР!» — её нет, кнопка ЩИТ — во всю оставшуюся ширину
local COMPACT_SHIELD = 0.42 -- ЩИТ «таблетки» — доля её ширины (как в gui/Alert.luau)
local COMPACT = { Min = 160, Narrow = 132, Max = 300, Step = 8, LabelPad = 4 }
local PLACE_SOON = 0.12 -- виджет рыбалки сдвинулся — новое место «таблетки» не чаще, с
local SHAKE = 5 -- дрожь при появлении: не больше px (UiFx.shake — в долях корня)
local TEXT_GAP = 8 -- текст плашки — не ближе к кнопкам, px
local ROW_PAD = 0.02 -- зазор ряда кнопок плашки — доля его ширины (как в gui/Alert.luau)
local SHIELD_WAIT = 3 -- ⏳ на ЩИТ, пока сервер не ответил (не дольше), с
local RESULT_AFTER = 0.25 -- итог — когда плашка ушла (место колонки снова уведомлений), с
local HIDE_TIME = 0.2 -- плашка уходит (конец тревоги), с
local STASH_TIME = 0.12 -- … уступает карточке улова или листу, с
local MOVE_TIME = 0.15 -- «таблетка» переезжает (её место заняли), с
local EDGE_KEEP = 0.3 -- слой края живёт после гашения пульсации (её fadeOut 0.25 с), с
local OWN_SHEET = "DefencePanel" -- лист «ЗАЩИТА»: тревога его не закрывает (его щит — та же цель)
local ICON_HOLD = TEXTS.IconHold
local ICON_CARRY = TEXTS.IconCarry
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
	layers = Trove.new(), -- пульсация краёв, «ДОМОЙ!», «пины», карточка и лист во время тревоги
	wait = Trove.new(), -- ожидание: карточка улова или лист уйдут
	live = Trove.new(), -- пока плашка видна: место по событиям, отсчёт «⏳ 1:12»
	tickGen = 0,
	hideGen = 0, -- уход плашки: таймер прячет её, только если поколение то же
	label = nil :: string?, -- текст «таблетки» (nil — без надписи)
	edge = nil :: string?, -- пульсация краёв: "on" | "asleep" | nil
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

-- Открытый лист (имя его корня: Controllers.Sheet пишет атрибут HUD Sheet) или nil.
local function sheetOpen(): string?
	local hud = A.hud
	local name = if hud then hud:GetAttribute("Sheet") else nil
	return if typeof(name) == "string" then name else nil
end

-- Место плашки занято: карточка улова (или 🐟 летит в «САДОК») или открытый лист.
local function blocked(): boolean
	return cardUp() or sheetOpen() ~= nil
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
-- Текст плашки — левее ряда кнопок на TEXT_GAP: на высокой плашке квадрат «ДОМОЙ» (по высоте)
-- шире своей доли, и ряд (по правому краю) растёт влево. Сам крадёшь — кнопок нет: во всю плашку.
local function fitText(own: boolean)
	local p = A.parts
	local text, buttons, r = p.text, p.buttons, A.rect
	if not text then
		return
	end
	local share = if own then 0.88 else p.textShare
	if not own and buttons and r and A.shown == "plate" then
		local w, h = r.x1 - r.x0, r.y1 - r.y0
		local bw, bh = buttons.Size.X.Scale * w, buttons.Size.Y.Scale * h
		local row, count = 0, 0
		if p.shield and p.shield.Visible then
			row += p.shield.Size.X.Scale * bw
			count += 1
		end
		if p.home and p.home.Visible then
			row += math.max(p.home.Size.Y.Scale * bh, THEFT.HomeMin)
			count += 1
		end
		row += math.max(count - 1, 0) * ROW_PAD * bw
		local rowLeft = buttons.Position.X.Scale * w - math.max(row, bw)
		share = math.clamp((rowLeft - TEXT_GAP - text.Position.X.Scale * w) / w, 0.1, p.textShare)
	end
	text.Size = UDim2.fromScale(share, text.Size.Y.Scale)
end

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
	fitText(own)
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
	local bands = NotifyController.Offset("alert")
	local offset = bands
	local clearOfStatus = if status then status.y1 + STATUS_INK + GAP + INK else nil
	if clearOfStatus then
		offset = math.max(offset, clearOfStatus - column.y0)
	end
	local r = AlertLayout.plate(size, column, offset, width, height)
	-- Планшет, компьютер: нарисованный низ плашки — не ближе GAP к своему рыбаку (его видно под
	-- плашкой): она поднимается к стопке статуса (не выше GAP под ней и не на полосы над собой; на
	-- планшете между кошельком и колонкой ≈ 40 px), а не хватает и так — ниже ростом, но не ниже
	-- Theft.PlateHeight (Wave 3 ART-06: губа плашки лежала у него на волосах, 0–3 px). Телефон —
	-- «таблетка» (compactRect).
	if not isPhone() then
		local fisher = FishingLayout.fisherBox(player.Character, Workspace.CurrentCamera, origin)
		local floor = if fisher and fisher.x1 > r.x0 and fisher.x0 < r.x1 then fisher.y0 - GAP - INK else nil
		if floor and r.y1 > floor then
			local top = column.y0 + bands
			if clearOfStatus and bands <= 0 then
				top = clearOfStatus
			elseif clearOfStatus then
				top = math.max(top, clearOfStatus)
			end
			local y0 = math.max(top, floor - height)
			local h = math.max(math.min(height, floor - y0), math.min(THEFT.PlateHeight, height))
			r = FishingLayout.rect(r.x0, y0, r.x1, y0 + h)
		end
	end
	return r
end

-- Где «таблетка» (телефон, плашка легла бы на рыбака): AlertLayout.compact.
local function compactRect(hud: ScreenGui, fisher: Rect): (Rect?, string)
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
	local hard: { Rect } = {} -- кнопки Roblox: под ними большие пальцы (их не закрывает ничто)
	if UserInputService.TouchEnabled then
		local camera = Workspace.CurrentCamera
		local view = if camera then camera.ViewportSize else size
		local small = math.min(view.X, view.Y) <= SHORT
		local jump, r = FishingLayout.jumpCircle(size, small)
		table.insert(hard, FishingLayout.rect(jump.X - r, jump.Y - r, jump.X + r, jump.Y + r))
		local stick = if small then STICK_SMALL else STICK_BIG
		table.insert(hard, FishingLayout.rect(0, size.Y - stick.top, stick.right, size.Y))
		for _, k in hard do
			table.insert(keepouts, k)
		end
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
		hard = hard,
		keep = if A.shown == "compact" then A.rect else nil,
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

-- Надпись «таблетки» шириной room px: самая полная, что влезает при наименьшем размере её
-- текста (уровень Body − 2, UiFx.fitText): «ВОР! ОКУНЬ», тесно — «ВОР!»; сам крадёшь — «ВОР! ОКУНЬ ·
-- щит после кражи» / «ВОР! Щит после кражи». Ничего не влезает — nil (надписи нет).
local function compactText(room: number): string?
	local a = A.alert
	if not a then
		return nil
	end
	local px = math.max(UiFx.textSize("Body") - 2, 12)
	local short = TextUtil.upper(a.short)
	local options = if stealing()
		then {
			TextUtil.fill(TEXTS.CompactStealing, { short = short }),
			TEXTS.CompactStealingShort,
			TEXTS.CompactShort,
		}
		else { TextUtil.fill(TEXTS.Compact, { short = short }), TEXTS.CompactShort }
	for _, text in options do
		if UiFx.textWidth(text, px) + COMPACT.LabelPad <= room then
			return text
		end
	end
	return nil
end

-- Корень — на прямоугольник r (px HUD, записанные масштабом); «таблетка», что уже видна и
-- переезжает, — твином MOVE_TIME с (не прыжком: ребёнок только что видел, где ЩИТ).
local function moveRoot(root: GuiObject, r: Rect, size: Vector2, glide: boolean)
	local position = UDim2.fromScale(r.x0 / size.X, r.y0 / size.Y)
	local box = UDim2.fromScale((r.x1 - r.x0) / size.X, (r.y1 - r.y0) / size.Y)
	root.AnchorPoint = Vector2.zero
	if glide then
		UiFx.tween(
			root,
			MOVE_TIME,
			{ Position = position, Size = box },
			Enum.EasingStyle.Quad,
			Enum.EasingDirection.Out
		)
	else
		root.Position = position
		root.Size = box
	end
end

-- Плашка или «таблетка» на своём месте (px HUD, записанные масштабом); места для «таблетки» нет
-- (кнопки Roblox) — "none": корень спрятан, остаётся «ЩИТ!» колонки. Место колонки уведомлений —
-- под плашкой. Возвращает вариант.
local function place(): string?
	local hud, root = A.hud, A.root
	if not hud or not root then
		return nil
	end
	local size = hud.AbsoluteSize
	if size.X <= 1 or size.Y <= 1 then
		return nil
	end
	local before, beforeRect = A.shown, A.rect
	local which, r, spot = "plate", plateRect(hud) :: Rect?, nil
	A.fisher = nil
	if isPhone() then
		local fisher = fisherRect(hud)
		A.fisher = fisher
		if fisher and r and FishingLayout.hits(r, fisher) then
			r, spot = compactRect(hud, fisher)
			which = if r then "compact" else "none"
		end
	end
	A.rect, A.spot = r, spot
	A.shown = which
	local p = A.parts
	if which == "none" or not r then
		-- (корень прячется, пока места нет; появится — show / again покажут)
		root.Visible = false
		A.label = nil
		NotifyController.Reserve("alert", nil)
		return which
	end
	if before == "none" and not root.Visible then
		root.Visible = true
		UiFx.popIn(root, { from = 0.4, time = 0.25 })
	end
	fitText(stealing())
	local glide = before == "compact"
		and which == "compact"
		and beforeRect ~= nil
		and root.Visible
		and (math.abs(beforeRect.x0 - r.x0) > 1 or math.abs(beforeRect.y0 - r.y0) > 1)
	moveRoot(root, r, size, glide)
	for _, name in { "plate", "iconRoot", "text", "buttons" } do
		local part = p[name]
		if part then
			part.Visible = which == "plate" and (name ~= "buttons" or not stealing())
		end
	end
	if p.compact then
		p.compact.Visible = which == "compact"
	end
	A.label = nil
	if which == "compact" then
		-- надпись — между значком 🚨 (свисает с левого края) и кнопкой справа
		local w, h = r.x1 - r.x0, r.y1 - r.y0
		local icon = p.compactIcon
		local iconRight = if icon then h * icon.Size.Y.Scale * (1 - icon.AnchorPoint.X) + 2 else h * 0.2
		local shield, home = p.compactShield, p.compactHome
		local shieldShare = p.compactShieldShare or COMPACT_SHIELD
		local button = if shield and shield.Visible then shieldShare * w elseif home and home.Visible then h else 0
		local room = w - button - 6 - iconRight
		local text = compactText(room)
		A.label = text
		local label = p.compactLabel
		if label then
			label.AnchorPoint = Vector2.new(0, 0.5)
			label.Position = UDim2.fromScale(iconRight / w, 0.5)
			label.Size = UDim2.fromScale(math.max(room, 1) / w, label.Size.Y.Scale)
			label.Visible = text ~= nil
			if text then
				label.Text = text
			end
		end
		local shieldW = 0
		if shield then
			-- надписи нет — ЩИТ во всю ширину справа от 🚨
			local share = if text then shieldShare else math.max(w - iconRight - 4, 1) / w
			shield.Size = UDim2.new(share, 0, shield.Size.Y.Scale, shield.Size.Y.Offset)
			shieldW = if shield.Visible then share * w else 0
		end
		-- плашка «таблетки» кончается под ЩИТ (его скруглённый край закрывает её конец): под
		-- кнопкой её не рисуем — заливка телефона (вид тот же)
		local plateW = if shieldW > 0 then math.min(w - shieldW + h / 2, w) else w
		for _, layer in p.compactPlate or {} do
			layer.Size = UDim2.new(plateW / w, 0, layer.Size.Y.Scale, layer.Size.Y.Offset)
		end
	end
	-- уведомления — под плашкой (и под «таблеткой» в их колонке или над самым её верхом): место —
	-- до нарисованного низа (обводка), уведомление — ещё NotifyController.BandGap() px ниже
	local toasts = guiChild(hud, "Toasts")
	local column = if toasts then rectOf(toasts, hud.AbsolutePosition) else nil
	if which == "plate" then
		NotifyController.Reserve("alert", if column then math.max(r.y1 + INK - column.y0, 0) else r.y1 - r.y0 + INK)
	elseif
		column
		and r.x0 < column.x1
		and r.x1 > column.x0
		and r.y0 < column.y0 + (column.y1 - column.y0) / 2
		and r.y1 + OWN_INK + NotifyController.BandGap() > column.y0
	then
		-- (над колонкой: 0.5 px — уведомление всё равно на BandGap ниже её нарисованного низа)
		NotifyController.Reserve("alert", math.max(r.y1 + OWN_INK - column.y0, 0.5))
	else
		NotifyController.Reserve("alert", nil)
	end
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

-- Плашка уходит (popOut без hide: прячет её таймер этого поколения — новая тревога, показанная
-- раньше, чем он сработал, его отменяет).
local function hideRoot(time: number)
	local root = A.root
	if not root or not root.Visible then
		return
	end
	A.hideGen += 1
	local gen = A.hideGen
	UiFx.popOut(root, { time = time, swell = false })
	task.delay(time, function()
		if gen == A.hideGen and A.shown == nil then
			root.Visible = false
			UiFx.scaleOf(root).Scale = 1
		end
	end)
end

local function show(loud: boolean)
	local root = A.root
	if not root or not A.alert then
		return
	end
	local was = A.shown
	A.hideGen += 1 -- (уход прошлой плашки, если ещё идёт, её не спрячет)
	fill()
	local which = place()
	if not was then
		A.live:Clean()
		watchPlace()
		restartTick()
		if which == "none" then
			return
		end
		root.Visible = true
		UiFx.popIn(root, { from = 0.4, time = 0.32, rotate = if loud then -5 else nil })
		if loud then
			task.delay(0.3, function()
				if A.shown and A.shown ~= "none" and A.root then
					local size = if A.hud then A.hud.AbsoluteSize else Vector2.one
					UiFx.shake(A.root, SHAKE / math.max(size.X, size.Y, 1), 0.35)
				end
			end)
		end
	elseif loud and which ~= "none" then
		UiFx.punch(root, { from = 0.85, peak = 1.1 })
	end
end

-- Карточка улова или лист заняли место: плашка уходит до их ухода (слои, «ЩИТ!» колонки остаются).
local function stash()
	if not A.shown then
		return
	end
	A.live:Clean()
	A.tickGen += 1
	A.shown = nil
	A.label = nil
	hideRoot(STASH_TIME)
	NotifyController.Reserve("alert", nil)
end

-- Карточка улова ещё на экране (или 🐟 летит в «САДОК»), открыт лист: плашка — когда уйдут (DC-02).
local function showWhenFree(loud: boolean)
	if not blocked() then
		show(loud)
		return
	end
	if A.waiting then
		return
	end
	A.waiting = true
	local hud = A.hud :: ScreenGui
	local function check()
		if not A.waiting or blocked() then
			return
		end
		A.waiting = false
		A.wait:Clean()
		A.wait:Add(task.delay(THEFT.CardAfter, function()
			if A.alert and not blocked() then
				show(loud)
			elseif A.alert then
				showWhenFree(loud)
			end
		end))
	end
	A.wait:Connect(hud:GetAttributeChangedSignal("CounterHold"), check)
	A.wait:Connect(hud:GetAttributeChangedSignal("Sheet"), check)
	local card = guiChild(hud:FindFirstChild("Fishing"), "CatchCard")
	if card then
		A.wait:Connect(card:GetPropertyChangedSignal("Visible"), check)
	end
end

-- Пока тревога идёт: новый улов (CounterHold) снова торопит карточку (HurryCard — один раз на
-- улов: на самой карточке он «тапает» её), а карточка или лист, появившись, прячут плашку.
local function watchBlockers(hud: ScreenGui)
	local function onBlock()
		if A.alert and blocked() then
			stash()
			showWhenFree(false)
		end
	end
	A.layers:Connect(hud:GetAttributeChangedSignal("CounterHold"), function()
		if A.alert and hud:GetAttribute("CounterHold") ~= nil then
			task.defer(hurryCard) -- (новый улов во время тревоги: карточка уйдёт обычным путём)
		end
		onBlock()
	end)
	A.layers:Connect(hud:GetAttributeChangedSignal("Sheet"), onBlock)
	local card = guiChild(hud:FindFirstChild("Fishing"), "CatchCard")
	if card then
		A.layers:Connect(card:GetPropertyChangedSignal("Visible"), onBlock)
	end
end

-- Пульсация краёв — в своём слое FxAlertEdge, обрезанном по HUD (её полосы «за краем» не ложатся
-- на верхнюю панель Roblox и вырез); пока у HUD есть свой край (поклёвка, аура мини-игры, вспышка
-- улова: другой FxVignette) — спит.
local function startEdge(hud: ScreenGui, quiet: boolean)
	local edge = THEFT.Edge
	local holder = Instance.new("Frame")
	holder.Name = "FxAlertEdge"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ClipsDescendants = true
	holder.Active = false
	holder.ZIndex = 90
	holder.Parent = hud
	local stop = UiFx.edgeVignette(holder, Palette.Berry.Top, 1 - edge.Alpha, edge.Period, {
		size = if isPhone() then edge.Phone else edge.Other,
		pulseTo = 1 - edge.Alpha * 0.35,
		fadeIn = if quiet then 0.1 else 0.25,
	})
	local function sync()
		local other = false
		for _, child in hud:GetChildren() do
			if child.Name == "FxVignette" then
				other = true
				break
			end
		end
		holder.Visible = not other
		A.edge = if other then "asleep" else "on"
		-- телефон: и кольца «ДОМОЙ!» / «ЩИТ!» отдыхают (поклёвка → мини-игра — самый плотный кадр)
		local rest = other and isPhone()
		HudController.HomeAlertRest(rest)
		DefenceController.AlertRest(rest)
	end
	local function onChild(child: Instance)
		if child.Name == "FxVignette" then
			task.defer(sync)
		end
	end
	A.layers:Connect(hud.ChildAdded, onChild)
	A.layers:Connect(hud.ChildRemoved, onChild)
	sync()
	A.layers:Add(function()
		A.edge = nil
		HudController.HomeAlertRest(false)
		DefenceController.AlertRest(false)
		stop()
		task.delay(EDGE_KEEP, function()
			holder:Destroy()
		end)
	end)
end

local function startLayers(quiet: boolean)
	local hud = A.hud
	if not hud then
		return
	end
	A.layers:Clean()
	startEdge(hud, quiet)
	HudController.HomeAlert(true)
	A.layers:Add(function()
		HudController.HomeAlert(false)
	end)
	watchBlockers(hud)
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
	local wasShown = A.shown ~= nil and A.shown ~= "none"
	A.shown = nil
	A.label = nil
	if root and wasShown and root.Visible then
		hideRoot(HIDE_TIME)
		local gen = A.hideGen
		task.delay(HIDE_TIME, function()
			if gen == A.hideGen and not A.shown then
				NotifyController.Reserve("alert", nil)
			end
		end)
	else
		if root and not wasShown then
			root.Visible = false
		end
		NotifyController.Reserve("alert", nil)
	end
	if then_ then
		task.delay(if wasShown then RESULT_AFTER else 0, then_)
	end
end

-- Метка уведомления «👀 Ника у тебя во дворе!» этого вора (тревога его убирает: плашка громче).
local function intruderTag(thief: any): string
	return `intruder:{if typeof(thief) == "number" then thief else "?"}`
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
	-- «👀 Ника у тебя во дворе!» этого вора (на экране или ждёт) — уже не нужно: плашка громче
	NotifyController.Drop(intruderTag(a.thief))
	if fresh then
		startLayers(quiet)
		local open = sheetOpen()
		if open and open ~= OWN_SHEET and not quiet then
			-- тревога важнее листа «САДОК» (как карточки улова): он уходит сразу; «ЗАЩИТА» остаётся —
			-- его щит и есть цель (DefenceCards: «ЩИТ!»)
			Sheet.CloseCurrent("alert")
		end
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
		-- «Украдено» — сразу (и поверх листа: это и есть конец тревоги); отдых садка и совет ждут,
		-- пока лист уйдёт (легли бы на его шапку), отдых — со временем на миг показа
		NotifyController.Show(TextUtil.fill(RESULT.Lost, { short = short, name = name }), "theft")
		if untilAt and untilAt > now() then
			local function rest(): string?
				local left = (untilAt :: number) - now()
				return if left >= 1 then TextUtil.fill(RESULT.LostSub, { t = StealRules.FormatClock(left) }) else nil
			end
			NotifyController.Show(rest() or "", "shield", { afterSheet = true, live = rest })
		end
		if tip then
			NotifyController.Show(tip, "info", { icon = DefenceConfig.Texts.TipIcon, afterSheet = true })
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
	local live: (() -> string?)? = nil
	if reason == "shield" then
		-- щит кончил кражу: одно уведомление «Щит спас рыбу! 🛡️ 1:00» (не ещё и «Щит включён»);
		-- ждёт ухода листа — время щита на миг показа (кончился — без него)
		local untilAt = now() + DefenceController.TakeShieldToast()
		local plain = text
		live = function(): string?
			local left = untilAt - now()
			return if left >= 1 then TextUtil.fill(RESULT.SavedShield, { t = StealRules.FormatClock(left) }) else plain
		end
		text = (live :: () -> string?)() or plain
	end
	finish(if quiet
		then nil
		else function()
			-- (лист открыт — ждёт его ухода: на «ЗАЩИТА» итог уже виден на карточке щита)
			NotifyController.Show(
				text,
				if reason == "shield" then "shield" else "saved",
				{ afterSheet = true, live = live }
			)
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
		tag = intruderTag(data.Thief),
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
		label = A.label,
		edge = A.edge,
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
	-- слои плашки «таблетки» (Theme.plate: обводка Lip и лицо Face) — их ширину режет place()
	local plateLayers: { GuiObject } = {}
	for _, name in { "Lip", "Face" } do
		local layer = compact:FindFirstChild(name)
		if layer and layer:IsA("GuiObject") then
			table.insert(plateLayers, layer)
		end
	end
	A.parts.compactPlate = plateLayers
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
				NotifyController.Show(payload.Text, "saved", { afterSheet = true })
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
