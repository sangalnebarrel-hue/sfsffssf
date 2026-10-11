--!strict
--[[
	NotifyController — всплывающие уведомления вверху экрана (HUD.Toasts).

	Источники:
	  • сервер: RemoteEvent "Notify" (text, kind);
	  • другие контроллеры: NotifyController.Show(text, kind).
	kind: "info" | "success" | "warning" | "danger" — цвет берётся из UIConfig.KindColors.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local UIConfig = require(Shared:WaitForChild("Config"):WaitForChild("UIConfig"))

local FADE_TIME = 0.25

local NotifyController = {}

local container: Frame? = nil
local template: Frame? = nil
local active: { Frame } = {}
local counter = 0

local function removeToast(toast: Frame)
	local index = table.find(active, toast)
	if index then
		table.remove(active, index)
	end
	toast:Destroy()
end

-- Показать уведомление. Можно вызывать из любых клиентских модулей.
function NotifyController.Show(text: string, kind: string?)
	local parent, source = container, template
	if not parent or not source then
		return -- контроллер ещё не запущен
	end
	counter += 1

	local toast = source:Clone()
	toast.Name = "Toast"
	toast.LayoutOrder = counter
	toast.BackgroundColor3 = UIConfig.KindColors[kind or "info"] or UIConfig.KindColors.info
	local label = toast:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
	toast.Visible = true
	toast.Parent = parent
	table.insert(active, toast)

	-- Слишком много уведомлений — убираем самые старые.
	while #active > UIConfig.MaxToasts do
		removeToast(active[1])
	end

	task.delay(UIConfig.ToastDuration, function()
		if not toast.Parent then
			return -- уже убрано
		end
		local info = TweenInfo.new(FADE_TIME)
		TweenService:Create(toast, info, { BackgroundTransparency = 1 }):Play()
		if label and label:IsA("TextLabel") then
			TweenService:Create(label, info, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
		task.wait(FADE_TIME)
		removeToast(toast)
	end)
end

function NotifyController:Start(hud: ScreenGui)
	local toasts = hud:WaitForChild("Toasts") :: Frame
	local toastTemplate = toasts:WaitForChild("ToastTemplate") :: Frame
	toastTemplate.Visible = false
	container = toasts
	template = toastTemplate

	Net.Event("Notify").OnClientEvent:Connect(function(text: any, kind: any)
		if typeof(text) ~= "string" then
			return
		end
		NotifyController.Show(text, if typeof(kind) == "string" then kind else "info")
	end)
end

return NotifyController
