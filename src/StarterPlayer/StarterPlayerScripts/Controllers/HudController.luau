--!strict
--[[
	HudController — основной интерфейс (Этап 1).

	  • Плашка «Твоя база» (HUD.TopLeft.BaseBadge): цвет и название базы игрока.
	    Данные приходят с сервера через атрибуты игрока: BaseIndex, BaseColorName, BaseColor.
	    BaseIndex = 0 — все базы заняты, игрок ждёт.
	  • Кнопка «Домой» (HUD.RightButtons.HomeButton): просит сервер телепортировать на базу.
	    Сервер сам проверяет кулдаун; здесь кулдаун только для красивой анимации кнопки.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BaseConfig = require(Shared:WaitForChild("Config"):WaitForChild("BaseConfig"))
local UIConfig = require(Shared:WaitForChild("Config"):WaitForChild("UIConfig"))
local Net = require(Shared:WaitForChild("Net"))

local player = Players.LocalPlayer

local HudController = {}

function HudController:Start(hud: ScreenGui)
	local badge = hud:WaitForChild("TopLeft"):WaitForChild("BaseBadge")
	local swatch = badge:WaitForChild("Swatch") :: Frame
	local badgeLabel = badge:WaitForChild("Label") :: TextLabel

	local homeButton = hud:WaitForChild("RightButtons"):WaitForChild("HomeButton") :: GuiButton
	local cooldownOverlay = homeButton:WaitForChild("Cooldown") :: Frame
	local requestHome = Net.Event("RequestHome")

	-- Плашка базы ------------------------------------------------------------------
	local function refreshBadge()
		local index = player:GetAttribute("BaseIndex")
		local color = player:GetAttribute("BaseColor")
		local colorName = player:GetAttribute("BaseColorName")

		if typeof(index) == "number" and index > 0 and typeof(colorName) == "string" then
			badgeLabel.Text = `{colorName} база`
			swatch.BackgroundColor3 = if typeof(color) == "Color3" then color else UIConfig.NoBaseColor
			homeButton.Visible = true
		elseif index == 0 then
			badgeLabel.Text = "Ждём свободную базу…"
			swatch.BackgroundColor3 = UIConfig.NoBaseColor
			homeButton.Visible = false
		else
			badgeLabel.Text = "Ищем базу…"
			swatch.BackgroundColor3 = UIConfig.NoBaseColor
			homeButton.Visible = false
		end
	end

	for _, attribute in { "BaseIndex", "BaseColor", "BaseColorName" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshBadge)
	end
	refreshBadge()

	-- Кнопка «Домой» -------------------------------------------------------------------
	local ready = true
	cooldownOverlay.Visible = false

	homeButton.Activated:Connect(function()
		if not ready then
			return
		end
		ready = false
		requestHome:FireServer()

		-- Затемнение кнопки «стекает» вниз за время кулдауна.
		cooldownOverlay.Size = UDim2.fromScale(1, 1)
		cooldownOverlay.Visible = true
		TweenService:Create(
			cooldownOverlay,
			TweenInfo.new(BaseConfig.HomeCooldown, Enum.EasingStyle.Linear),
			{ Size = UDim2.fromScale(1, 0) }
		):Play()

		task.delay(BaseConfig.HomeCooldown, function()
			ready = true
			cooldownOverlay.Visible = false
		end)
	end)
end

return HudController
