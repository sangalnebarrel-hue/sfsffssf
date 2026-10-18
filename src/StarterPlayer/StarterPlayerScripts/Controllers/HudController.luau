--!strict
--[[
	HudController — основной интерфейс (Этап 1) и его «сок» (образец стиля «Симулятор», UI v5,
	tools/builder/gui/STYLE.md; анимации — ReplicatedStorage.Shared.UiFx).

	  • Плашка «Твоя база» (HUD.Status.BaseBadge, вверху по центру): сочная плашка в цветах своей
	    базы (UIConfig.BaseSwatches по Id из BaseConfig; UiFx.setCandy красит градиент и толстую
	    обводку) с 🚩 на левом краю, надпись заглавными: «ЛАЗУРНАЯ БАЗА». Данные — атрибуты игрока
	    BaseIndex, BaseColorName, BaseColor (их ставит сервер); BaseIndex = 0 — все базы заняты,
	    игрок ждёт (светло-серая плашка «ЖДЁМ БАЗУ…»).
	  • Первая база — момент: по центру экрана огромная надпись HUD.BaseBanner, как заголовок
	    образца («ТВОЯ БАЗА» / «ЛАЗУРНАЯ!» в цветах базы, с толстой обводкой и тенью, без
	    плашки; на маленьком телефоне, где под концом имени «ВЗЯТЬ», — выше, чтобы до её круга
	    было 16 px, но не ближе 16 px к строкам статуса — placeBanner): имя «влетает» (slam: растёт
	    от своей нижней кромки и не крупнее, чем позволяют 16 px до плашек статуса, колонки кнопок и
	    кнопки действия — nameSlamFrom) и вспыхивает, флажок машет, лучи, конфетти и «фанфара»;
	    через 2 с надпись сжимается и влетает в плашку (в полёте — атрибут FxLandingIn = "Status"),
	    плашка подпрыгивает, её ободок
	    вспыхивает, блик (пока баннер виден, подсказка рыбалки ждёт — FishingController смотрит
	    на его Visible). Если база досталась после ожидания в очереди — уведомление «Тебе
	    досталась Лазурная база!» в цветах базы с 🚩. Над табличкой своей базы в мире (надпись над
	    флагом: имя владельца и название базы) этот клиент показывает зелёное «ТВОЯ БАЗА!»
	    (OwnerSign.YoursLabel — его видит только владелец; BaseService его не трогает).
	  • Вступление (Этап 3): когда баннер базы влетел в плашку (или баннера нет: игрок ждёт в
	    очереди, база досталась без баннера, о базе так и не пришло ничего за
	    UIConfig.Wallet.IntroWait с), у HUD ставится числовой атрибут IntroAt = os.clock() — с него
	    MoneyController выпускает кошелёк, а TankButtonController — кнопку «САДОК» (плашка →
	    кошелёк → «САДОК» через Wallet.IntroGap). Ставится один раз за игру.
	  • Кошелёк и кнопка «САДОК» (Этап 3) — свои контроллеры (MoneyController, TankButtonController);
	    счётчика улова больше нет: на его строке — кошелёк.
	  • Кнопка «Домой» (HUD.RightButtons.HomeButton, фиолетовая квадратная кнопка с 🏠 и «ДОМОЙ»
	    на нижнем краю): просит сервер телепортировать на базу. Нажатие — сжатие, перелёт и «пинок»
	    домика (UiFx.press; мышью — ещё и наведение). Сервер сам проверяет кулдаун; здесь кулдаун
	    только для вида: тёмная вуаль «стекает» вниз, крупные наклонные цифры по центру (последние
	    3 с — оранжевой вспышкой), домик бледнеет, подпись «ЖДИ» над вуалью; по готовности — «удар»,
	    подпись «ДОМОЙ» «бьёт» на месте, кольцо и один блик. Нажатие во время кулдауна — кнопка
	    качается «нет». Красный кружок «!» (HomeButton.Badge) спрятан: его зажжёт магазин (этап 5).
	  • Обводки и шкала текста подгоняются под экран (UiFx.fitStrokes, UiFx.fitText).
	  • Панель предметов Roblox (CoreGui Backpack) выключена (v3): удочку берут кнопкой «ВЗЯТЬ»
	    (она есть везде, пока удочка в рюкзаке) или клавишей 1 (FishingController), а серый слот
	    внизу по центру стоял под ногами рыбака и поднимал мини-игру и подсказки на него. Свою
	    панель предметов принесёт этап магазина (несколько удочек).
	  • На устройствах без тач-экрана колонка кнопок опускается к правому нижнему углу
	    (на телефонах низ справа занят кнопкой прыжка).
	  • Ничего не блестит «просто так»: блик у плашки — только при назначении базы, у «Домой» —
	    когда кончился кулдаун (внимание остаётся у главной кнопки рыбалки).
	  • Плашки изредка «живут» (раз в 8–12 с, по одной, только в покое — не рыбачим, нет улова,
	    уведомлений, и 6 с после последнего события): флажок базы качнётся, 🐠 кнопки «САДОК»
	    качнётся, 🏠 подпрыгнет. Одна цепочка таймеров, без покадровой работы.

	Все эффекты здесь — на твинах и таймерах, HUD живёт всю сессию (ResetOnSpawn = false), поэтому
	соединения создаются один раз.

	API (Этап 4): HudController.HomeAlert(on) — тревога кражи у своей базы: красное кольцо вокруг
	«ДОМОЙ» и подпись «ДОМОЙ!» (зовёт AlertController; волна 0 — контракт: пока ничего не делает,
	тело — Wave 2 D).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseConfig = require(Shared:WaitForChild("Config"):WaitForChild("BaseConfig"))
local UIConfig = require(Shared:WaitForChild("Config"):WaitForChild("UIConfig"))
local Net = require(Shared:WaitForChild("Net"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local NotifyController = require(script.Parent:WaitForChild("NotifyController"))
local Layout = require(script.Parent:WaitForChild("FishingLayout")) -- (прямоугольники и «удар»)

type Swatch = UIConfig.Swatch

local player = Players.LocalPlayer

local Palette = UIConfig.Palette
local WHITE = UIConfig.White

local FLAG_HAS_BASE = "🚩"
local FLAG_WAITING = "⏳"
local FLAG_SEARCHING = "🔎"

local BANNER_HOLD = 2 -- сколько секунд баннер базы стоит по центру
local NAME_SLAM = 1.8 -- имя на баннере «ударяет» с такого масштаба (если есть место — nameSlamFrom)
local NAME_ROOM = 1.5 -- … и баннер над кнопкой действия встаёт так, чтобы места хватило хотя бы на такой
local NAME_INK = 0.25 -- строка шрифта имени выступает за его рамку сверху и снизу на столько его высоты
local SLAM_CLEAR = 16 + 3 -- до соседей (с их обводкой ≈ 3 px), px
local DISC_POP = 0.15 -- «выскок» кнопки действия с доворотом (и её «!») поднимает её верх на столько её стороны
local BANNER_FLY = 0.4 -- полёт баннера в плашку
local CAPTION_REST = "ДОМОЙ"
local CAPTION_WAIT = "ЖДИ"

local HudController = {}

-- «Конфета» своей базы: чистые цвета из UIConfig.BaseSwatches (по Id), иначе из самого цвета.
local function baseSwatch(): Swatch
	local name = player:GetAttribute("BaseColorName")
	local color = player:GetAttribute("BaseColor")
	for _, entry in BaseConfig.Colors do
		if entry.Name == name or (typeof(color) == "Color3" and entry.Color == color) then
			local found = UIConfig.BaseSwatches[entry.Id]
			if found then
				return found
			end
		end
	end
	if typeof(color) == "Color3" then
		return UIConfig.swatchFor(color)
	end
	return Palette.Slate
end

-- Этап 4: тревога кражи у своей базы — «ДОМОЙ» зовёт домой (кольцо, «ДОМОЙ!»). Волна 0: пусто.
function HudController.HomeAlert(_on: boolean) end

function HudController:Start(hud: ScreenGui)
	local status = hud:WaitForChild("Status") :: Frame
	local badge = status:WaitForChild("BaseBadge") :: Frame
	badge:WaitForChild("Swatch") -- лицевая сторона: UiFx.setCandy красит её в цвета базы
	local badgeLabel = badge:WaitForChild("Label") :: TextLabel
	local flagSocket = badge:FindFirstChild("FlagSocket") :: GuiObject?
	local flag = if flagSocket then flagSocket:FindFirstChild("Flag") :: TextLabel? else nil

	local banner = hud:FindFirstChild("BaseBanner") :: Frame?

	local rightButtons = hud:WaitForChild("RightButtons") :: Frame
	local homeButton = rightButtons:WaitForChild("HomeButton") :: GuiButton
	local tankButton = rightButtons:WaitForChild("TankButton") :: GuiButton
	local tankIcon = tankButton:WaitForChild("Icon") :: GuiObject
	local homeIcon = homeButton:WaitForChild("Icon") :: TextLabel
	local homeCaption = homeButton:FindFirstChild("Caption") :: TextLabel?
	local cooldownOverlay = homeButton:WaitForChild("Cooldown") :: Frame
	local drain = cooldownOverlay:FindFirstChild("Drain") :: UIGradient?
	local cooldownText = homeButton:FindFirstChild("CooldownText") :: TextLabel?
	local requestHome = Net.Event("RequestHome")

	-- Панель предметов Roblox не нужна: удочку берёт кнопка «ВЗЯТЬ» — она есть везде, пока удочка
	-- в рюкзаке (и клавиша 1, как в панели; FishingController).
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	end)

	-- Без тач-экрана нет кнопки прыжка — колонку можно опустить ниже.
	if not UserInputService.TouchEnabled then
		rightButtons.Position = UDim2.fromScale(0.99, 0.96)
	end

	UiFx.fitStrokes(hud)
	UiFx.fitText(hud)
	UiFx.press(homeButton, { sound = "click" })
	-- Вход в игру: плашка выскакивает (до неё долетит баннер базы).
	UiFx.popIn(badge, { from = 0.6, time = 0.32 })
	-- Когда в HUD что-то происходило (прилёт рыбы, база, «Домой», рыбалка): «жизнь» плашек
	-- (в конце Start) ждёт после этого MICRO_QUIET секунд.
	local lastActivity = os.clock()

	-- Плашка базы и баннер ------------------------------------------------------------
	-- "none" — ещё не знаем (только вошли), "waiting" — в очереди, "assigned" — база есть.
	local baseState = "none"
	local bannerTrove = Trove.new()
	local bannerRest = if banner then banner.Position else UDim2.fromScale(0.5, 0.46)

	-- Вступление кончилось (баннер в плашке, или его не будет): с этого мига кошелёк и «САДОК»
	-- выскакивают по очереди (MoneyController, TankButtonController — атрибут HUD IntroAt).
	local function introDone()
		if hud:GetAttribute("IntroAt") == nil then
			hud:SetAttribute("IntroAt", os.clock())
		end
	end
	task.delay(UIConfig.Wallet.IntroWait, introDone) -- (о базе так ничего и не пришло)

	-- Плашка «приняла» базу: подпрыгивает, ободок вспыхивает, флажок «вкручивается» и качается,
	-- блик (только твины — момент уже отыграл баннер).
	local function celebrateBadge()
		introDone()
		UiFx.bump(badge, 1.25, 0.4)
		UiFx.rimFlash(badge, { delay = 0.12, bump = 1 })
		local socket = flagSocket
		if socket then
			UiFx.popIn(socket, { from = 0.4, time = 0.4, rotate = -30 })
			task.delay(0.35, function()
				UiFx.wiggle(socket, 10, 3, 0.6)
			end)
		end
		task.delay(0.15, function()
			UiFx.shine(badge, 0.7)
		end)
		UiFx.sound("tick", 0.45, 1.2)
	end

	-- Баннер улетает в плашку: сжимается до её размера по дуге и пропадает, плашка подпрыгивает.
	local function flyBannerToBadge()
		local live = banner
		if not live or not live.Visible then
			return
		end
		local area = hud.AbsoluteSize
		local origin = hud.AbsolutePosition
		local target = UDim2.fromScale(0.5, 0.1)
		if area.X > 1 and area.Y > 1 then
			-- Центр плашки: X — середина стопки (плашка выровнена по центру), Y — сама плашка.
			local x = status.AbsolutePosition.X + status.AbsoluteSize.X / 2 - origin.X
			local y = badge.AbsolutePosition.Y + badge.AbsoluteSize.Y / 2 - origin.Y
			target = UDim2.fromScale(x / area.X, y / area.Y)
		end
		local scale = UiFx.scaleOf(live)
		local shrink = if live.AbsoluteSize.Y > 1
			then math.clamp(badge.AbsoluteSize.Y / live.AbsoluteSize.Y, 0.15, 1)
			else 0.3
		local move = UiFx.tween(live, BANNER_FLY, { Position = target }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local squeeze =
			UiFx.tween(scale, BANNER_FLY, { Scale = shrink }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		UiFx.sound("swoosh", 0.35, 1.2)
		-- (Пока летит — помечен: «влетает в Status», намеренное слияние с плашкой; проверка раскладки
		-- превью эту пару в полёте не судит — tools/preview/gui/checks.py LANDING.)
		live:SetAttribute("FxLandingIn", status.Name)
		bannerTrove:Add(task.delay(BANNER_FLY, function()
			move:Cancel() -- твины могли закончиться позже этого таймера — не дадим им перетереть сброс
			squeeze:Cancel()
			bannerTrove:Clean()
			live:SetAttribute("FxLandingIn", nil)
			live.Visible = false
			live.Position = bannerRest
			scale.Scale = 1
			celebrateBadge()
		end))
	end

	-- Соседи баннера в px HUD, до которых он и «удар» его имени держат SLAM_CLEAR (V-02):
	-- показанные строки статуса (по ширине — вся стопка), колонка кнопок справа и круг кнопки
	-- действия на своём месте в покое (FishingController.layoutColumn: якорь в центре, сторона —
	-- доля высоты области; сверху ещё DISC_POP на её «выскок» с доворотом — «ВЗЯТЬ» может появиться
	-- в любой миг). Возвращает их список, отдельно — круг (nil — нет) и низ строк статуса с зазором.
	local function bannerNeighbours(): ({ any }, any?, number)
		local origin = hud.AbsolutePosition
		local function rect(at: Vector2, size: Vector2, grow: number): any
			return Layout.rect(at.X - grow, at.Y - grow, at.X + size.X + grow, at.Y + size.Y + grow)
		end
		local keepouts = {}
		local top = status.AbsolutePosition - origin
		local floor = top.Y
		for _, item in status:GetChildren() do
			if item:IsA("GuiObject") and item.Visible then
				floor = math.max(floor, item.AbsolutePosition.Y - origin.Y + item.AbsoluteSize.Y)
			end
		end
		table.insert(keepouts, rect(top, Vector2.new(status.AbsoluteSize.X, floor - top.Y), SLAM_CLEAR))
		table.insert(keepouts, rect(rightButtons.AbsolutePosition - origin, rightButtons.AbsoluteSize, SLAM_CLEAR))
		local fishing = hud:FindFirstChild("Fishing")
		local area = fishing and fishing:FindFirstChild("ActionArea")
		local disc = area and area:FindFirstChild("ActionButton")
		local around: any = nil
		if area and area:IsA("GuiObject") and disc and disc:IsA("GuiObject") then
			local box = area.AbsoluteSize
			local side = disc.Size.Y.Scale * box.Y + disc.Size.Y.Offset
			local at = area.AbsolutePosition
				- origin
				+ Vector2.new(
					disc.Position.X.Scale * box.X + disc.Position.X.Offset - side / 2,
					disc.Position.Y.Scale * box.Y + disc.Position.Y.Offset - side / 2
				)
			around = rect(at, Vector2.new(side, side), SLAM_CLEAR)
			around.y0 -= side * DISC_POP
			table.insert(keepouts, around)
		end
		return keepouts, around, floor + SLAM_CLEAR
	end

	-- Имя на баннере в px HUD с запасом на обводку (по бокам), строку шрифта (NAME_INK сверху и
	-- снизу) и тень-близнеца (ниже на свой сдвиг) и его якорь (середина нижней кромки) в долях
	-- этого прямоугольника.
	local function nameBox(nameLabel: GuiObject): (any, Vector2)
		local at = nameLabel.AbsolutePosition - hud.AbsolutePosition
		local size = nameLabel.AbsoluteSize
		local outline = nameLabel:FindFirstChild("Outline")
		local edge = if outline and outline:IsA("UIStroke") then outline.Thickness else 0
		local ink = size.Y * NAME_INK
		local twin = UiFx.twinOf(nameLabel)
		local drop = if twin then math.max(twin.AbsolutePosition.Y - nameLabel.AbsolutePosition.Y, 0) else 0
		local box = Layout.rect(at.X - edge, at.Y - ink, at.X + size.X + edge, at.Y + size.Y + ink + drop)
		local pivot = at + size * nameLabel.AnchorPoint
		return box,
			Vector2.new(
				(pivot.X - box.x0) / math.max(box.x1 - box.x0, 1),
				(pivot.Y - box.y0) / math.max(box.y1 - box.y0, 1)
			)
	end

	-- Баннер — по центру (bannerRest), но если имя при «ударе» с NAME_ROOM (вокруг своего якоря;
	-- строка шрифта под кромкой растёт с ним) подошло бы к кругу кнопки действия (с его «выскоком»)
	-- ближе SLAM_CLEAR — телефоны: «ВЗЯТЬ» справа внизу под концом имени, — он поднимается на
	-- столько, но не выше SLAM_CLEAR под показанными строками статуса.
	local function placeBanner(live: GuiObject, nameLabel: GuiObject?)
		live.Position = bannerRest
		if not nameLabel or not nameLabel:IsA("GuiObject") then
			return
		end
		local _, around, floor = bannerNeighbours()
		local name, anchor = nameBox(nameLabel)
		local w, h = name.x1 - name.x0, name.y1 - name.y0
		local px, py = name.x0 + anchor.X * w, name.y0 + anchor.Y * h
		local x0, x1 = px - anchor.X * w * NAME_ROOM, px + (1 - anchor.X) * w * NAME_ROOM
		local y1 = py + (1 - anchor.Y) * h * NAME_ROOM
		if around and x1 > around.x0 and around.x1 > x0 and y1 > around.y0 then
			local top = live.AbsolutePosition.Y - hud.AbsolutePosition.Y
			local lift = math.max(math.min(y1 - around.y0, top - floor), 0)
			live.Position = bannerRest - UDim2.fromOffset(0, math.ceil(lift))
		end
	end

	-- Имя «ударяет» с NAME_SLAM, но не крупнее, чем есть места: растёт от своей нижней кромки (к
	-- кнопке действия под баннером не опускается) и уже в начале держит SLAM_CLEAR до соседей
	-- (bannerNeighbours; V-02: на маленьком телефоне и планшете удар 1.8 доставал до «ДОМОЙ»).
	-- Меряется до «выскока» баннера (масштаб 1).
	local function nameSlamFrom(nameLabel: GuiObject): number
		local keepouts = bannerNeighbours()
		local name, anchor = nameBox(nameLabel)
		return Layout.growFrom(name, anchor, NAME_SLAM, keepouts)
	end

	-- Первая база: баннер по центру (лучи, конфетти, машущий флажок), потом — в плашку.
	local function showBanner(swatch: Swatch, colorName: string)
		local live = banner
		if not live then
			celebrateBadge()
			return
		end
		bannerTrove:Clean()
		live:SetAttribute("FxLandingIn", nil)
		live.Visible = true
		placeBanner(live, live:FindFirstChild("NameLabel") :: GuiObject?)
		local caption = live:FindFirstChild("Caption")
		if caption and caption:IsA("TextLabel") then
			caption.Text = "ТВОЯ БАЗА"
		end
		-- Имя — огромная надпись в цветах базы (белое сверху → Top → Bottom), как заголовок
		-- образца: «влетает» (slam) и вспыхивает цветом базы.
		local nameLabel = live:FindFirstChild("NameLabel")
		if nameLabel and nameLabel:IsA("TextLabel") then
			UiFx.setText(nameLabel, `{TextUtil.upper(colorName)}!`)
			local fill = nameLabel:FindFirstChild("TextFill")
			if fill and fill:IsA("UIGradient") then
				fill.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, WHITE),
					ColorSequenceKeypoint.new(0.4, WHITE:Lerp(swatch.Top, 0.6)),
					ColorSequenceKeypoint.new(0.7, swatch.Top),
					ColorSequenceKeypoint.new(1, swatch.Bottom),
				})
			end
			local from = nameSlamFrom(nameLabel)
			bannerTrove:Add(task.delay(0.12, function()
				UiFx.slam(nameLabel, from, 0.3)
			end))
			bannerTrove:Add(task.delay(0.45, function()
				UiFx.flashText(nameLabel, swatch.Top, 0.4)
			end))
		end
		UiFx.popIn(live, { from = 0.3, time = 0.45, rotate = -6 })
		bannerTrove:Add(UiFx.rays(live, {
			colors = { WHITE, swatch.Top },
			count = 10,
			halo = false,
			breathe = false,
			size = 2.6,
			maxPx = 520,
			transparency = 0.4,
			speed = 22,
			z = 0,
		}))
		-- Флажок машет ±10° (твин туда-обратно, без соединений).
		local socket = live:FindFirstChild("FlagSocket")
		if socket and socket:IsA("GuiObject") then
			local rest = socket.Rotation
			socket.Rotation = rest - 10
			local wave = TweenService:Create(
				socket,
				TweenInfo.new(0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Rotation = rest + 10 }
			)
			wave:Play()
			bannerTrove:Add(function()
				wave:Cancel()
				socket.Rotation = rest
			end)
		end
		bannerTrove:Add(UiFx.sparkles(live, { rate = 5, size = 0.3, area = 0.1, outside = true }))
		local area = hud.AbsoluteSize
		local center = live.AbsolutePosition + live.AbsoluteSize / 2 - hud.AbsolutePosition
		local origin = if area.X > 1 and area.Y > 1
			then Vector2.new(center.X / area.X, center.Y / area.Y)
			else Vector2.new(0.5, 0.45)
		-- Конфетти на твинах (confettiPop): вход в игру не держит покадровый планировщик.
		bannerTrove:Add(UiFx.confettiPop(hud, {
			count = 20,
			colors = { swatch.Top, swatch.Bottom, WHITE, Palette.Gold.Top },
			origin = origin,
			spread = 150,
			power = 1.4,
			duration = 1.7,
		}))
		UiFx.sound("swoosh", 0.35)
		bannerTrove:Add(UiFx.arpeggio("Epic", 0.35))
		bannerTrove:Add(task.delay(0.3, function()
			UiFx.shine(live, 0.7)
		end))
		bannerTrove:Add(task.delay(BANNER_HOLD, flyBannerToBadge))
	end

	-- «ТВОЯ БАЗА!» над табличкой своей базы (Workspace.Bases.Base_N, надпись над флагом): видна
	-- только здесь, у владельца; база сменилась — прошлая гаснет.
	local yoursLabel: GuiObject? = nil
	local function markOwnSign(index: any)
		if yoursLabel then
			yoursLabel.Visible = false
			yoursLabel = nil
		end
		local bases = Workspace:FindFirstChild("Bases")
		local base = if bases
				and typeof(index) == "number"
				and index > 0
			then bases:FindFirstChild(`Base_{index}`)
			else nil
		local node: Instance? = base
		for _, name in { "Flag", "Pole", "SignAttachment", "OwnerSign", "YoursLabel" } do
			node = if node then node:FindFirstChild(name) else nil
		end
		if node and node:IsA("GuiObject") then
			node.Visible = true
			yoursLabel = node
		end
	end

	local function refreshBadge()
		lastActivity = os.clock()
		local index = player:GetAttribute("BaseIndex")
		local colorName = player:GetAttribute("BaseColorName")
		markOwnSign(index)

		if typeof(index) == "number" and index > 0 and typeof(colorName) == "string" then
			local swatch = baseSwatch()
			badgeLabel.Text = `{TextUtil.upper(colorName)} БАЗА`
			UiFx.setCandy(badge, swatch)
			if flag then
				flag.Text = FLAG_HAS_BASE
			end
			local before = baseState
			baseState = "assigned"
			if before == "none" then
				showBanner(swatch, colorName)
			elseif before == "waiting" then
				celebrateBadge()
				NotifyController.Show(`Тебе досталась {colorName} база!`, "base", { swatch = swatch })
			end
			if before ~= "assigned" then
				-- Кнопка «Домой» выскакивает на своём месте (масштаб, не позиция: по Position колонки
				-- раскладывают подсказку, «СМОТАТЬ» и значок чужого улова — SIM-C1-06), домик
				-- «вкручивается» следом. Перелёт Back Out ≈ 1.07 — до кнопки прыжка не дотягивается.
				homeButton.Visible = true
				UiFx.popIn(homeButton, { from = 0.3, time = 0.4, delay = 0.25 })
				UiFx.popIn(homeIcon, { from = 0, time = 0.4, delay = 0.4, rotate = -25 })
			end
			homeButton.Visible = true
		else
			badgeLabel.Text = if index == 0 then "ЖДЁМ БАЗУ…" else "ИЩЕМ БАЗУ…"
			UiFx.setCandy(badge, "Slate")
			if flag then
				flag.Text = if index == 0 then FLAG_WAITING else FLAG_SEARCHING
			end
			if baseState == "assigned" then
				UiFx.wiggle(badge, 4, 2, 0.35)
			end
			if index == 0 then
				baseState = "waiting"
				introDone() -- в очереди баннера не будет: кошелёк — когда загрузятся данные
			elseif baseState == "assigned" then
				baseState = "waiting" -- базу забрали: следующая придёт как «досталась»
			end
			homeButton.Visible = false
		end
	end

	for _, attribute in { "BaseIndex", "BaseColor", "BaseColorName" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshBadge)
	end
	refreshBadge()

	-- Кнопка «Домой» -------------------------------------------------------------------
	local ready = true
	local countdown: thread? = nil
	cooldownOverlay.Visible = false
	if cooldownText then
		cooldownText.Visible = false
	end
	local captionZ = if homeCaption then homeCaption.ZIndex else 0
	local captionTop = cooldownOverlay.ZIndex + 1 -- «ЖДИ» над вуалью кулдауна

	local function showSeconds(left: number)
		if not cooldownText then
			return
		end
		if left <= 0 then
			cooldownText.Visible = false
			return
		end
		cooldownText.Text = tostring(left)
		cooldownText.Visible = true
		-- Последние 3 секунды — крупнее и оранжевой вспышкой: «почти готово».
		UiFx.bump(cooldownText, if left <= 3 then 1.45 else 1.35, 0.25)
		if left <= 3 then
			UiFx.flashText(cooldownText, Palette.Sun.Top, 0.4)
		end
	end

	-- Вид кнопки: готова («ДОМОЙ», яркий домик) или ждёт («ЖДИ» над вуалью, бледный домик).
	local function setWaiting(waiting: boolean)
		UiFx.tween(homeIcon, 0.2, { TextTransparency = if waiting then 0.85 else 0 })
		local caption = homeCaption
		if caption then
			-- Новая подпись «бьёт» на месте (не «слот-машина»: в маленькой кнопке старая и новая
			-- подписи наезжали друг на друга и на цифры кулдауна — SIM-C1-07). Слой — до текста.
			caption.ZIndex = if waiting then captionTop else captionZ
			UiFx.setText(caption, if waiting then CAPTION_WAIT else CAPTION_REST)
			UiFx.punch(caption, { from = 0.6, peak = 1.12 })
		end
	end

	homeButton.Activated:Connect(function()
		lastActivity = os.clock()
		if not ready then
			-- Кнопка стоит в UIListLayout (позицию двигать нельзя) — «нет» покачиванием.
			UiFx.wiggle(homeButton, 7, 2, 0.3)
			return
		end
		ready = false
		requestHome:FireServer()
		UiFx.wiggle(homeIcon, 12, 3, 0.45)
		UiFx.ripple(homeButton)

		-- Тёмная вуаль «стекает» вниз за время кулдауна, цифры отсчитывают секунды.
		local duration = BaseConfig.HomeCooldown
		cooldownOverlay.Visible = true
		setWaiting(true)
		if drain then
			drain.Offset = Vector2.new(0, -0.5)
			UiFx.tween(drain, duration, { Offset = Vector2.new(0, 0.5) }, Enum.EasingStyle.Linear)
		end
		local whole = math.ceil(duration)
		showSeconds(whole)
		countdown = task.spawn(function()
			local first = duration - (whole - 1)
			task.wait(first)
			for left = whole - 1, 1, -1 do
				showSeconds(left)
				task.wait(1)
			end
		end)

		task.delay(duration, function()
			if countdown and coroutine.status(countdown) == "suspended" then
				task.cancel(countdown)
			end
			countdown = nil
			ready = true
			cooldownOverlay.Visible = false
			showSeconds(0)
			setWaiting(false)
			if homeButton.Visible then
				UiFx.punch(homeButton, { from = 0.9, peak = 1.15 })
				UiFx.rimFlash(homeButton, { bump = 1 })
				UiFx.glowRing(homeButton, { color = Palette.Grape.Top, scale = 1.45, thickness = 5 })
				UiFx.shine(homeButton, 0.5)
			end
		end)
	end)

	-- «Жизнь» плашек между событиями (UI v4): раз в MICRO_MIN…MICRO_MAX секунд — и только в покое
	-- (не рыбачим, нет улова, уведомлений и баннера, MICRO_QUIET секунд после последнего события) —
	-- оживает ОДНА плашка, по кругу: флажок базы качнётся, 🐠 «САДОК» качнётся, 🏠 подпрыгнет.
	-- Тихо и редко: «дышит» и блестит только главная кнопка рыбалки. Одна цепочка task.delay на
	-- всю сессию — ни одного соединения и покадрового эффекта.
	local MICRO_FIRST, MICRO_MIN, MICRO_MAX, MICRO_QUIET = 14, 8, 12, 6
	local microRandom = Random.new()
	local microTurn = 0
	local homeAnchor = homeIcon.AnchorPoint
	player:GetAttributeChangedSignal("FishingState"):Connect(function()
		lastActivity = os.clock()
	end)
	local function calm(): boolean
		local state = player:GetAttribute("FishingState")
		if
			(state ~= nil and state ~= "Idle")
			or hud:GetAttribute("CounterHold") ~= nil
			or os.clock() - lastActivity < MICRO_QUIET
		then
			return false
		end
		if (banner and banner.Visible) or hud:GetAttribute("CounterIncoming") ~= nil then
			return false
		end
		local toasts = hud:FindFirstChild("Toasts")
		for _, item in if toasts then toasts:GetChildren() else {} do
			if item:IsA("GuiObject") and item.Visible and item.Name ~= "ToastTemplate" then
				return false
			end
		end
		local fishing = hud:FindFirstChild("Fishing")
		local card = if fishing then fishing:FindFirstChild("CatchCard") else nil
		return not (card and card:IsA("GuiObject") and card.Visible)
	end
	local function microLife()
		task.delay(microRandom:NextNumber(MICRO_MIN, MICRO_MAX), microLife)
		if not calm() then
			return
		end
		local picks: { () -> () } = {}
		local socket = flagSocket
		if socket and baseState == "assigned" then
			table.insert(picks, function()
				UiFx.wiggle(socket, 10, 3, 0.6) -- флажок «машет»
			end)
		end
		if tankButton.Visible then
			table.insert(picks, function()
				UiFx.wiggle(tankIcon, 9, 2, 0.55) -- 🐠 «САДОК» качается туда-обратно
			end)
		end
		if homeButton.Visible and ready then
			table.insert(picks, function()
				-- 🏠 подпрыгивает (через AnchorPoint: позицию значка «топит» нажатие кнопки).
				UiFx.tween(homeIcon, 0.18, { AnchorPoint = homeAnchor + Vector2.new(0, 0.1) })
				task.delay(0.18, function()
					UiFx.tween(homeIcon, 0.32, { AnchorPoint = homeAnchor }, Enum.EasingStyle.Bounce)
				end)
			end)
		end
		if #picks > 0 then
			microTurn += 1
			picks[(microTurn - 1) % #picks + 1]()
		end
	end
	task.delay(MICRO_FIRST, microLife)
end

return HudController
