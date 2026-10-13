--!strict
--[[
	NotifyController — всплывающие уведомления (HUD.Toasts) в стиле Candy Splash
	(tools/builder/gui/STYLE.md; анимации — ReplicatedStorage.Shared.UiFx).

	Источники:
	  • сервер: RemoteEvent "Notify" (text, kind);
	  • другие контроллеры: NotifyController.Show(text, kind).
	kind: "info" | "success" | "warning" | "danger" — цвет «конфеты» и значок берутся из
	UIConfig.ToastKinds (Sky 💬 / Leaf 🎉 / Sun ⚠️ / Berry ⛔).

	Каждое уведомление — копия HUD.Toasts.ToastTemplate (имя "Toast"), ширина — по длине текста.
	Колонку раскладывает этот модуль (без UIListLayout): новое уведомление съезжает сверху в свой
	слот и пружинит, значок выскакивает и качается, по «конфете» пробегает блик; «успех» — со
	звёздочками, «опасность» — встряхивается. Через UIConfig.ToastDuration секунд уведомление
	сжимается и тает (имя "ToastLeaving"), остальные плавно сдвигаются вверх. Видно не больше
	UIConfig.MaxToasts — лишние старые уходят сразу.

	Только твины и таймеры: ни одного покадрового соединения на уведомление.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local UIConfig = require(Shared:WaitForChild("Config"):WaitForChild("UIConfig"))
local UiFx = require(Shared:WaitForChild("UiFx"))

local SLOT = 0.3 -- высота уведомления, доля высоты колонки
local GAP = 0.04 -- зазор между уведомлениями
local ENTER_TIME = 0.45
local LEAVE_TIME = 0.25

local NotifyController = {}

local container: Frame? = nil
local template: Frame? = nil
local active: { Frame } = {}
local counter = 0

local function slotPosition(index: number): UDim2
	return UDim2.fromScale(0.5, (index - 1) * (SLOT + GAP))
end

-- Все видимые уведомления едут к своим слотам.
local function reflow()
	for index, toast in active do
		UiFx.tween(toast, 0.28, { Position = slotPosition(index) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	end
end

local function dismiss(toast: Frame, quick: boolean?)
	local index = table.find(active, toast)
	if not index then
		return -- уже уходит
	end
	table.remove(active, index)
	toast.Name = "ToastLeaving"
	reflow()
	local time = if quick then 0.15 else LEAVE_TIME
	UiFx.popOut(toast, { time = time, to = 0.55 })
	UiFx.fadeOut(toast, time)
	task.delay(time + 0.02, function()
		toast:Destroy()
	end)
end

-- Ширина по длине текста: короткие — компактные «конфеты», длинные — во всю колонку.
local function widthFor(text: string): number
	local length = utf8.len(text) or #text
	return math.clamp(0.34 + length * 0.021, 0.56, 1)
end

-- Показать уведомление. Можно вызывать из любых клиентских модулей.
function NotifyController.Show(text: string, kind: string?)
	local parent, source = container, template
	if not parent or not source then
		return -- контроллер ещё не запущен
	end
	counter += 1
	local style = UIConfig.ToastKinds[kind or "info"] or UIConfig.ToastKinds.info

	local toast = source:Clone()
	toast.Name = "Toast"
	toast.LayoutOrder = counter
	toast.Size = UDim2.fromScale(widthFor(text), SLOT)
	UiFx.setCandy(toast, style.Token)
	local label = toast:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
	local socket = toast:FindFirstChild("IconSocket")
	local icon = if socket then socket:FindFirstChild("Icon") else nil
	if icon and icon:IsA("TextLabel") then
		icon.Text = style.Icon
	end

	table.insert(active, toast)
	local slot = #active
	toast.Position = slotPosition(slot) - UDim2.fromScale(0, 0.3)
	toast.Visible = true
	toast.Parent = parent

	-- Въезд: сверху в слот с пружиной, значок выскакивает следом, потом блик.
	UiFx.tween(toast, ENTER_TIME, { Position = slotPosition(slot) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UiFx.popIn(toast, { from = 0.5, time = ENTER_TIME })
	if socket and socket:IsA("GuiObject") then
		UiFx.popIn(socket, { from = 0, time = 0.4, delay = 0.12, rotate = -25 })
		task.delay(0.5, function()
			if socket.Parent then
				UiFx.wiggle(socket, if kind == "warning" then 16 else 9, 3, 0.45)
			end
		end)
	end
	task.delay(0.3, function()
		if toast.Parent and toast.Name == "Toast" then
			UiFx.shine(toast, 0.6)
		end
	end)
	if kind == "success" then
		UiFx.sparkles(toast, { rate = 6, duration = 1.2, size = 0.75 })
	elseif kind == "danger" then
		task.delay(ENTER_TIME, function()
			if toast.Parent and toast.Name == "Toast" then
				UiFx.wiggle(toast, 4, 3, 0.4)
			end
		end)
	end

	-- Слишком много уведомлений — убираем самые старые.
	while #active > UIConfig.MaxToasts do
		dismiss(active[1], true)
	end

	task.delay(UIConfig.ToastDuration, function()
		if toast.Parent then
			dismiss(toast)
		end
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
