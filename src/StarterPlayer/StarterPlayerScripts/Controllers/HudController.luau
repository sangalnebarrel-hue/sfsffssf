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
	    плашки): имя «влетает» (slam) и вспыхивает, флажок машет, лучи, конфетти и «фанфара»;
	    через 2 с надпись сжимается и влетает в плашку, плашка подпрыгивает, её ободок
	    вспыхивает, блик. Если база досталась после ожидания в очереди — уведомление «Тебе
	    досталась Лазурная база!» в цветах базы с 🚩. Над табличкой своей базы в мире (надпись над
	    флагом: имя владельца и название базы) этот клиент показывает зелёное «ТВОЯ БАЗА!»
	    (OwnerSign.YoursLabel — его видит только владелец; BaseService его не трогает).
	  • Счётчик улова (HUD.Status.CatchCounter — крупное наклонное число без плашки, как «10»
	    образца, и 🐟): число N (Label.Text — только цифры) и видимость ведёт ЭТОТ контроллер
	    по атрибуту игрока FishCaught. Договор с карточкой улова: пока у HUD (ScreenGui) есть
	    числовой атрибут CounterHold, счётчик показывает это число и молчит; когда CounterHold
	    убирают (nil), показывается FishCaught и играет «прилёт»: подпрыгивание 1.3, рыбка
	    «плющится» и качается, число катится «одометром» и вспыхивает, искры, «+N» всплывает
	    справа, тик повыше тоном. Без CounterHold «прилёт» играет сразу при росте FishCaught (через
	    кадр — успеть поставить CounterHold в тот же кадр). Пока 🐟 летит из карточки, у HUD есть
	    строковый атрибут CounterIncoming — её редкость: счётчик, которого ещё нет (первый улов),
	    выскакивает с «0» — рыбе есть куда лететь; прилёт — в цвете редкости (подпрыгивание выше,
	    кольцо, число на миг в цветах редкости, «+N» крупнее, уровнем Button). Снимают его вместе
	    с CounterHold (редкость запомнена до прилёта).
	  • Кнопка «Домой» (HUD.RightButtons.HomeButton, фиолетовая квадратная кнопка с 🏠 и «ДОМОЙ»
	    на нижнем краю): просит сервер телепортировать на базу. Нажатие — сжатие, перелёт и «пинок»
	    домика (UiFx.press; мышью — ещё и наведение). Сервер сам проверяет кулдаун; здесь кулдаун
	    только для вида: тёмная вуаль «стекает» вниз, крупные наклонные цифры по центру (последние
	    3 с — оранжевой вспышкой), домик бледнеет, подпись «ЖДИ» над вуалью; по готовности — «удар»,
	    подпись «ДОМОЙ» «бьёт» на месте, кольцо и один блик. Нажатие во время кулдауна — кнопка
	    качается «нет». Красный кружок «!» (HomeButton.Badge) спрятан: его зажжёт магазин (этап 3).
	  • Обводки и шкала текста подгоняются под экран (UiFx.fitStrokes, UiFx.fitText).
	  • Панель предметов Roblox (CoreGui Backpack) выключена (v3): удочку берут кнопкой «ВЗЯТЬ»
	    у точки рыбалки (FishingController), а серый слот внизу по центру стоял под ногами
	    рыбака и поднимал мини-игру и подсказки на него. Свою панель предметов принесёт этап
	    магазина (несколько удочек).
	  • На устройствах без тач-экрана колонка кнопок опускается к правому нижнему углу
	    (на телефонах низ справа занят кнопкой прыжка).
	  • Ничего не блестит «просто так»: блик у плашки — только при назначении базы, у «Домой» —
	    когда кончился кулдаун (внимание остаётся у главной кнопки рыбалки).
	  • «Прилёт» в счётчик — ещё и «одометр» (прошлое число уезжает вверх и тает, новое
	    поднимается снизу с пружинкой). Плашки изредка «живут» (раз в 8–12 с, по одной, только в
	    покое — не рыбачим, нет улова, уведомлений, и 6 с после последнего события): флажок базы
	    качнётся, 🐟 кувыркнётся, 🏠 подпрыгнет. Одна цепочка таймеров, без покадровой работы.

	Все эффекты здесь — на твинах и таймерах (кроме коротких конфетти, искр и «+N»), HUD живёт всю
	сессию (ResetOnSpawn = false), поэтому соединения создаются один раз.
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

type Swatch = UIConfig.Swatch

local player = Players.LocalPlayer

local Palette = UIConfig.Palette
local WHITE = UIConfig.White

local FLAG_HAS_BASE = "🚩"
local FLAG_WAITING = "⏳"
local FLAG_SEARCHING = "🔎"

local BANNER_HOLD = 2 -- сколько секунд баннер базы стоит по центру
local BANNER_FLY = 0.4 -- полёт баннера в плашку
local CAPTION_REST = "ДОМОЙ"
local CAPTION_WAIT = "ЖДИ"

local HudController = {}

local function numberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

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

function HudController:Start(hud: ScreenGui)
	local status = hud:WaitForChild("Status") :: Frame
	local badge = status:WaitForChild("BaseBadge") :: Frame
	badge:WaitForChild("Swatch") -- лицевая сторона: UiFx.setCandy красит её в цвета базы
	local badgeLabel = badge:WaitForChild("Label") :: TextLabel
	local flagSocket = badge:FindFirstChild("FlagSocket") :: GuiObject?
	local flag = if flagSocket then flagSocket:FindFirstChild("Flag") :: TextLabel? else nil

	local counter = status:WaitForChild("CatchCounter") :: Frame
	local counterIcon = counter:WaitForChild("Icon") :: GuiObject
	local counterLabel = counter:WaitForChild("Label") :: TextLabel

	local banner = hud:FindFirstChild("BaseBanner") :: Frame?

	local rightButtons = hud:WaitForChild("RightButtons") :: Frame
	local homeButton = rightButtons:WaitForChild("HomeButton") :: GuiButton
	local homeIcon = homeButton:WaitForChild("Icon") :: TextLabel
	local homeCaption = homeButton:FindFirstChild("Caption") :: TextLabel?
	local cooldownOverlay = homeButton:WaitForChild("Cooldown") :: Frame
	local drain = cooldownOverlay:FindFirstChild("Drain") :: UIGradient?
	local cooldownText = homeButton:FindFirstChild("CooldownText") :: TextLabel?
	local requestHome = Net.Event("RequestHome")

	-- Панель предметов Roblox не нужна: удочку берёт кнопка «ВЗЯТЬ» (FishingController).
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

	-- Плашка «приняла» базу: подпрыгивает, ободок вспыхивает, флажок «вкручивается» и качается,
	-- блик (только твины — момент уже отыграл баннер).
	local function celebrateBadge()
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
		bannerTrove:Add(task.delay(BANNER_FLY, function()
			move:Cancel() -- твины могли закончиться позже этого таймера — не дадим им перетереть сброс
			squeeze:Cancel()
			bannerTrove:Clean()
			live.Visible = false
			live.Position = bannerRest
			scale.Scale = 1
			celebrateBadge()
		end))
	end

	-- Первая база: баннер по центру (лучи, конфетти, машущий флажок), потом — в плашку.
	local function showBanner(swatch: Swatch, colorName: string)
		local live = banner
		if not live then
			celebrateBadge()
			return
		end
		bannerTrove:Clean()
		live.Position = bannerRest
		live.Visible = true
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
			bannerTrove:Add(task.delay(0.12, function()
				UiFx.slam(nameLabel, 1.8, 0.3)
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

	-- Счётчик улова -------------------------------------------------------------------
	local shown = numberAttribute("FishCaught") -- число, которое сейчас на счётчике
	local incoming: string? = nil -- редкость рыбы, которая летит в счётчик (атрибут CounterIncoming)

	local function heldValue(): number?
		local value = hud:GetAttribute("CounterHold")
		return if typeof(value) == "number" then value else nil
	end

	-- Пока рыба летит, счётчик виден и с нулём («🐟 0» — первой рыбе есть куда лететь). На
	-- счётчике только число без плашки (как монеты): значок 🐟 говорит, что это улов.
	local function render(total: number)
		if total > 0 or incoming ~= nil then
			counter.Visible = true
			counterLabel.Text = tostring(math.floor(math.max(total, 0)))
		else
			counter.Visible = false
		end
	end

	-- «Одометр»: прошлое число уезжает вверх и тает, новое поднимается снизу с пружинкой
	-- (Back Out). Label.Text — уже новое число (договор), прошлое едет копией FxOdometer.
	local counterRest = counterLabel.Position
	local greeting = 0 -- поколение «приветствия» редкости на числе (последнее снимает цвет)
	local function rollCounter(old: string)
		local ghost = counterLabel:Clone()
		ghost.Name = "FxOdometer"
		ghost.Text = old
		for _, item in ghost:GetChildren() do
			if string.sub(item.Name, 1, 2) == "Fx" then
				item:Destroy()
			end
		end
		ghost.Position = counterRest
		ghost.Parent = counter
		local lift = UDim2.fromScale(0, counterLabel.Size.Y.Scale * 0.6)
		local quad = Enum.EasingStyle.Quad
		UiFx.tween(ghost, 0.18, { Position = counterRest - lift, TextTransparency = 1 }, quad, Enum.EasingDirection.In)
		local outline = ghost:FindFirstChildOfClass("UIStroke")
		if outline then
			UiFx.tween(outline, 0.18, { Transparency = 1 }, quad, Enum.EasingDirection.In)
		end
		task.delay(0.2, function()
			ghost:Destroy()
		end)
		counterLabel.Position = counterRest + lift
		UiFx.tween(counterLabel, 0.25, { Position = counterRest }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	end

	-- Рыба «прилетела» в счётчик: подпрыгнуть, качнуть рыбку, «+N», тик повыше; рыба с карточки
	-- (CounterIncoming) — в цветах своей редкости: кольцо от плашки и «+N» крупнее (уровень Button).
	local function arrival(gained: number, rarity: string?)
		lastActivity = os.clock()
		rollCounter(tostring(math.max(math.floor(shown - gained), 0)))
		local style = if rarity then UIConfig.Rarity[rarity] else nil
		UiFx.bump(counter, if style then 1.45 else 1.3, if style then 0.45 else 0.35)
		-- 🐟 «плющится» и пружинит (Elastic), качается; число вспыхивает (золотом или цветом
		-- редкости), из счётчика брызжут искры.
		local iconScale = UiFx.scaleOf(counterIcon)
		iconScale.Scale = 1.35
		UiFx.tween(iconScale, 0.45, { Scale = 1 }, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out)
		UiFx.wiggle(counterIcon, 14, 3, 0.5)
		UiFx.flashText(counterLabel, if style and not style.Rainbow then style.Top else Palette.Gold.Top, 0.35)
		UiFx.burst(counter, {
			count = 8,
			power = 0.45,
			time = 0.4,
			origin = Vector2.new(0.6, 0.5),
			colors = { WHITE, Palette.Gold.Top, if style then style.Top else Palette.Gold.Bottom },
		})
		UiFx.sound("tick", 0.45, 1.3)
		local colors = { WHITE, Palette.Gold.Top } -- (обычная рыба — золото: серое «+1» не радует)
		if style then
			if style.Rainbow then
				colors = { UIConfig.Rainbow[1], UIConfig.Rainbow[3], UIConfig.Rainbow[5] }
			elseif rarity ~= "Common" then
				colors = { UiFx.lighten(style.Top, 0.35), style.Bottom }
			end
			UiFx.glowRing(counterIcon, {
				color = if style.Rainbow then WHITE else style.Top,
				scale = 1.6,
				thickness = 4,
				time = 0.5,
			})
			-- Число на миг в цветах редкости (белое сверху → Top → Bottom), потом снова белое.
			local fill = counterLabel:FindFirstChild("TextFill")
			if fill and fill:IsA("UIGradient") and not style.Rainbow then
				greeting += 1
				local mine = greeting
				fill.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, WHITE),
					ColorSequenceKeypoint.new(0.45, style.Top),
					ColorSequenceKeypoint.new(1, style.Bottom),
				})
				task.delay(0.8, function()
					if greeting == mine then
						fill.Color = ColorSequence.new(WHITE)
					end
				end)
			end
		end
		-- «+N» справа от плашки, чуть вверх (не налезая на плашку базы над ней).
		local px = UiFx.textSize("Button") -- «+N» уровнем Button (Offset у UDim — целые пиксели)
		local size = if style
			then UDim2.fromOffset(math.round(px * 2.6), math.round(px * 1.3))
			else UDim2.fromScale(0.34, 1.15)
		local float = UiFx.floatText(counter, `+{gained}`, {
			position = if style then UDim2.new(1, math.round(px * 1.4), 0.5, 0) else UDim2.fromScale(1.2, 0.5),
			size = size,
			colors = colors,
			rise = if style then 0.45 else 0.35,
			rotate = 8,
			time = if style then 1.1 else 0.9,
		})
		if style and style.Rainbow then
			local fill = float:FindFirstChild("TextFill")
			if fill and fill:IsA("UIGradient") then
				fill.Rotation = 0
			end
		end
	end

	local function refreshCounter(juice: boolean)
		local hold = heldValue()
		if hold then
			if incoming and not counter.Visible then
				-- Первая рыба за игру летит в пустое место: счётчик появляется («🐟 0»).
				render(hold)
				UiFx.popIn(counter, { from = 0, time = 0.25 })
			end
			shown = hold
			render(hold)
			return
		end
		local total = numberAttribute("FishCaught")
		local gained = total - shown
		shown = total
		local rarity = incoming
		incoming = nil
		render(total)
		if juice and gained > 0 and counter.Visible then
			arrival(gained, rarity)
		end
	end

	player:GetAttributeChangedSignal("FishCaught"):Connect(function()
		-- Через кадр: карточка улова успевает поставить CounterHold в том же кадре.
		task.defer(refreshCounter, true)
	end)
	hud:GetAttributeChangedSignal("CounterHold"):Connect(function()
		refreshCounter(true)
	end)
	-- Рыба с карточки полетела в счётчик (её редкость): прилёт будет в её цветах. Снимают атрибут
	-- вместе с CounterHold; без CounterHold «гость» забывается.
	hud:GetAttributeChangedSignal("CounterIncoming"):Connect(function()
		local value = hud:GetAttribute("CounterIncoming")
		if typeof(value) == "string" then
			incoming = value
			refreshCounter(false)
		elseif not heldValue() then
			incoming = nil
		end
	end)
	refreshCounter(false)

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
	-- оживает ОДНА плашка, по кругу: флажок базы качнётся, 🐟 счётчика кувыркнётся, 🏠 подпрыгнет.
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
		if (state ~= nil and state ~= "Idle") or heldValue() ~= nil or os.clock() - lastActivity < MICRO_QUIET then
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
		if counter.Visible then
			table.insert(picks, function()
				UiFx.wiggle(counterIcon, 9, 2, 0.55) -- 🐟 кувыркается туда-обратно
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
