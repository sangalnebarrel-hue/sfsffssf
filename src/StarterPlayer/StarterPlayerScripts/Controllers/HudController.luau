--!strict
--[[
	HudController — основной интерфейс (Этап 1) и его «сок» (образец стиля Candy Splash,
	tools/builder/gui/STYLE.md; анимации — ReplicatedStorage.Shared.UiFx).

	  • Плашка «Твоя база» (HUD.Status.BaseBadge, вверху по центру): глянцевая «конфета» цвета базы
	    (лицевая сторона Swatch красится из атрибута BaseColor) с флажком; блик раз в несколько
	    секунд; когда база назначена — подпрыгивает, флажок качается, вокруг звёздочки.
	    Данные приходят с сервера через атрибуты игрока: BaseIndex, BaseColorName, BaseColor.
	    BaseIndex = 0 — все базы заняты, игрок ждёт.
	  • Счётчик улова (HUD.Status.CatchCounter): текст и видимость пишет FishingController; здесь —
	    когда FishCaught растёт: «+1 🐟» всплывает справа, рыбка качается, по плашке бежит блик.
	  • Кнопка «Домой» (HUD.RightButtons.HomeButton): просит сервер телепортировать на базу.
	    Сервер сам проверяет кулдаун; здесь кулдаун только для анимации: тёмная вуаль «стекает»
	    вниз, крупные цифры отсчитывают секунды, по готовности — кольцо и блик. Нажатие — кнопка
	    сжимается, домик качается; нажатие во время кулдауна — кнопка качается «нет».
	  • Обводки подгоняются под высоту экрана (UiFx.fitStrokes).
	  • На устройствах без тач-экрана колонка кнопок опускается к правому нижнему углу
	    (на телефонах низ справа занят кнопкой прыжка).

	Все эффекты здесь — на твинах и таймерах (без покадровых соединений), HUD живёт всю сессию
	(ResetOnSpawn = false), поэтому соединения создаются один раз.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseConfig = require(Shared:WaitForChild("Config"):WaitForChild("BaseConfig"))
local UIConfig = require(Shared:WaitForChild("Config"):WaitForChild("UIConfig"))
local Net = require(Shared:WaitForChild("Net"))
local UiFx = require(Shared:WaitForChild("UiFx"))

local player = Players.LocalPlayer

local BADGE_SHINE_INTERVAL = 4.5 -- блик по плашке базы, с
local HOME_SHINE_INTERVAL = 3.6 -- блик по готовой кнопке «Домой», с

local FLAG_HAS_BASE = "🚩"
local FLAG_WAITING = "⏳"
local FLAG_SEARCHING = "🔎"

local HudController = {}

local function numberAttribute(name: string): number
	local value = player:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

function HudController:Start(hud: ScreenGui)
	local status = hud:WaitForChild("Status") :: Frame
	local badge = status:WaitForChild("BaseBadge") :: Frame
	badge:WaitForChild("Swatch") -- лицевая сторона: UiFx.setCandy красит её в цвет базы
	local badgeLabel = badge:WaitForChild("Label") :: TextLabel
	local flagSocket = badge:FindFirstChild("FlagSocket") :: GuiObject?
	local flag = if flagSocket then flagSocket:FindFirstChild("Flag") :: TextLabel? else nil

	local counter = status:WaitForChild("CatchCounter") :: Frame
	local counterIcon = counter:WaitForChild("Icon") :: GuiObject

	local rightButtons = hud:WaitForChild("RightButtons") :: Frame
	local homeButton = rightButtons:WaitForChild("HomeButton") :: GuiButton
	local homeIcon = homeButton:WaitForChild("Icon") :: GuiObject
	local cooldownOverlay = homeButton:WaitForChild("Cooldown") :: Frame
	local drain = cooldownOverlay:FindFirstChild("Drain") :: UIGradient?
	local cooldownText = homeButton:FindFirstChild("CooldownText") :: TextLabel?
	local requestHome = Net.Event("RequestHome")

	-- Без тач-экрана нет кнопки прыжка — колонку можно опустить ниже.
	if not UserInputService.TouchEnabled then
		rightButtons.Position = UDim2.fromScale(0.99, 0.96)
	end

	UiFx.fitStrokes(hud)
	UiFx.press(homeButton, { sound = "click" })

	-- Плашка базы ------------------------------------------------------------------
	local hadBase = false

	local function celebrateBase()
		UiFx.popIn(badge, { from = 0.55, time = 0.45 })
		local socket = flagSocket
		if socket then
			UiFx.popIn(socket, { from = 0.2, time = 0.5, delay = 0.08, rotate = -30 })
			task.delay(0.5, function()
				UiFx.wiggle(socket, 10, 3, 0.6)
			end)
		end
		task.delay(0.3, function()
			UiFx.shine(badge, 0.7)
		end)
		UiFx.sparkles(badge, { rate = 7, duration = 1.4, size = 0.6 })
		homeButton.Visible = true
		UiFx.popIn(homeButton, { from = 0, time = 0.45, delay = 0.25, rotate = -12 })
	end

	local function refreshBadge()
		local index = player:GetAttribute("BaseIndex")
		local color = player:GetAttribute("BaseColor")
		local colorName = player:GetAttribute("BaseColorName")

		if typeof(index) == "number" and index > 0 and typeof(colorName) == "string" then
			badgeLabel.Text = `{colorName} база`
			UiFx.setCandy(badge, if typeof(color) == "Color3" then color else UIConfig.NoBaseColor)
			if flag then
				flag.Text = FLAG_HAS_BASE
			end
			if not hadBase then
				hadBase = true
				celebrateBase()
			end
			homeButton.Visible = true
		else
			badgeLabel.Text = if index == 0 then "Ждём базу…" else "Ищем базу…"
			UiFx.setCandy(badge, UIConfig.NoBaseColor)
			if flag then
				flag.Text = if index == 0 then FLAG_WAITING else FLAG_SEARCHING
			end
			if hadBase then
				hadBase = false
				UiFx.wiggle(badge, 4, 2, 0.35)
			end
			homeButton.Visible = false
		end
	end

	for _, attribute in { "BaseIndex", "BaseColor", "BaseColorName" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshBadge)
	end
	refreshBadge()
	UiFx.shineLoop(badge, { interval = BADGE_SHINE_INTERVAL })

	-- Счётчик улова -------------------------------------------------------------------
	local caught = numberAttribute("FishCaught")
	player:GetAttributeChangedSignal("FishCaught"):Connect(function()
		local total = numberAttribute("FishCaught")
		local gained = total - caught
		caught = total
		if gained <= 0 then
			return
		end
		-- FishingController уже показал счётчик и обновил текст; здесь — «сок».
		task.defer(function()
			if not counter.Visible then
				return
			end
			UiFx.bump(counter, 1.25, 0.35)
			UiFx.wiggle(counterIcon, 14, 3, 0.5)
			UiFx.shine(counter, 0.55)
			-- «+N» справа от плашки, чуть вверх (не налезая на надпись базы над ней).
			UiFx.floatText(counter, `+{gained}`, {
				position = UDim2.fromScale(1.2, 0.5),
				size = UDim2.fromScale(0.34, 1.15),
				colors = { UIConfig.White, UIConfig.Palette.Gold.Top },
				rise = 0.35,
				rotate = 8,
				time = 0.9,
			})
		end)
	end)

	-- Кнопка «Домой» -------------------------------------------------------------------
	local ready = true
	local countdown: thread? = nil
	cooldownOverlay.Visible = false
	if cooldownText then
		cooldownText.Visible = false
	end
	UiFx.shineLoop(homeButton, {
		interval = HOME_SHINE_INTERVAL,
		when = function()
			return ready
		end,
	})

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
		UiFx.bump(cooldownText, 1.35, 0.25)
	end

	homeButton.Activated:Connect(function()
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
			if homeButton.Visible then
				UiFx.bump(homeButton, 1.15, 0.35)
				UiFx.glowRing(homeButton, { color = UIConfig.Palette.Leaf.Top, scale = 1.45, thickness = 5 })
				UiFx.shine(homeButton, 0.5)
			end
		end)
	end)
end

return HudController
