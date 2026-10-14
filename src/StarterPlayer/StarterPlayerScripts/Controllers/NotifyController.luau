--!strict
--[[
	NotifyController — всплывающие уведомления (HUD.Toasts) в стиле Candy Splash
	(tools/builder/gui/STYLE.md; анимации — ReplicatedStorage.Shared.UiFx).

	Источники:
	  • сервер: RemoteEvent "Notify" (text, kind);
	  • другие контроллеры: NotifyController.Show(text, kind?, look?).
	kind — вид из UIConfig.ToastKinds: "info" | "success" | "warning" | "danger" (Sky 💬 / Leaf 🎉 /
	Sun ⚠️ / Berry 🚨), "base" (цвета своей базы, 🚩 — look.swatch передаёт HudController),
	"Legendary" (золотая «конфета» с 👑) и "Mythic" (переливается радугой, 👑) — громкие новости о
	редком улове: крупнее, дольше (4.5 с), со звёздочками. Неизвестный вид — как "info".
	look = { swatch = {Top, Bottom, Lip}?, icon = "🚩"? } заменяет цвет и значок вида.

	Каждое уведомление — копия HUD.Toasts.ToastTemplate (имя "Toast"), ширина — по длине текста
	(текст по шкале UiFx.fitText: Body, у громких — Button); длинный текст — в две строки. Если
	уведомлений несколько, все тянутся до ширины самого широкого (значки встают в столбик).
	Колонку раскладывает этот модуль (без UIListLayout): новое уведомление съезжает сверху в свой
	слот с пружинкой, значок выскакивает и качается, по «конфете» пробегает блик; «успех» и
	громкие — со звёздочками, «опасность» — встряхивается.

	Сколько видно сразу: UIConfig.MaxToasts на компьютере, MaxToastsTouch на телефоне/планшете,
	и только ОДНО, пока на экране мини-игра, «КЛЮЁТ!» или карточка улова (HUD.Fishing.Minigame /
	BiteAlert / CatchCard): остальные ждут в очереди и выходят, когда место освободится. Когда
	места нет, уходит самое старое из самых неважных (Priority вида; «опасность» вытесняет
	обычные); если все на экране важнее нового — новое ждёт в очереди.
	Уход: через Life (или UIConfig.ToastDuration) секунд уведомление чуть поднимается и тает
	(имя "ToastLeaving"), остальные через 0.12 с съезжают вверх; уходят не чаще, чем раз в
	UIConfig.ToastGap секунд.

	Только твины и таймеры: ни одного покадрового соединения на уведомление.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local UIConfig = require(Shared:WaitForChild("Config"):WaitForChild("UIConfig"))
local UiFx = require(Shared:WaitForChild("UiFx"))

type Swatch = UIConfig.Swatch
type ToastKind = UIConfig.ToastKind

export type Look = {
	swatch: Swatch?, -- цвет «конфеты» вместо цвета вида
	icon: string?, -- значок вместо значка вида
}

type Toast = {
	frame: Frame,
	priority: number,
	height: number, -- высота, доля колонки
	natural: number, -- своя ширина по тексту, доля колонки
	trove: Trove.Trove, -- его эффекты и таймеры
	entering: boolean, -- ещё въезжает (позицию ведёт твин въезда)
}

type Pending = { text: string, kind: string, look: Look? }

local SLOT = 0.28 -- высота уведомления, доля высоты колонки
local GAP = 0.08 -- зазор между уведомлениями
local BIG = 1.2 -- громкие уведомления выше во столько раз
local TWO_LINES = 1.6 -- … и длинные (в две строки)
local ENTER_TIME = 0.45
local LEAVE_TIME = 0.2
local REFLOW_DELAY = 0.12
local LABEL_SHARE = 0.8 -- ширина надписи, доля уведомления (Hud.luau: LabelProps)
local MIN_WIDTH = 0.42
local MAX_QUEUE = 4
local BUSY_WIDGETS = { "Minigame", "BiteAlert", "CatchCard" }

local NotifyController = {}

local container: Frame? = nil
local template: Frame? = nil
local active: { Toast } = {}
local queue: { Pending } = {}
local busyWidgets: { GuiObject } = {}
local counter = 0
local lastDismiss = -math.huge

local function busy(): boolean
	for _, widget in busyWidgets do
		if widget.Visible then
			return true
		end
	end
	return false
end

local function capacity(): number
	if busy() then
		return 1
	end
	return if UserInputService.TouchEnabled then UIConfig.MaxToastsTouch else UIConfig.MaxToasts
end

local function styleOf(kind: string): ToastKind
	return UIConfig.ToastKinds[kind] or UIConfig.ToastKinds.info
end

local function slotPosition(index: number): UDim2
	local y = 0
	for i = 1, index - 1 do
		local toast = active[i]
		y += (if toast then toast.height else SLOT) + GAP
	end
	return UDim2.fromScale(0.5, y)
end

-- Все видимые уведомления едут к своим слотам и тянутся до ширины самого широкого.
-- Позицию въезжающего не трогаем (иначе пропадёт пружинка въезда): он сам доедет и позовёт reflow.
local function reflow()
	local widest = 0
	for _, toast in active do
		widest = math.max(widest, toast.natural)
	end
	for index, toast in active do
		local width = if #active >= 2 then widest else toast.natural
		local quad, out = Enum.EasingStyle.Quad, Enum.EasingDirection.Out
		UiFx.tween(toast.frame, 0.28, { Size = UDim2.fromScale(width, toast.height) }, quad, out)
		if not toast.entering then
			UiFx.tween(toast.frame, 0.28, { Position = slotPosition(index) }, quad, out)
		end
	end
end

local present: (item: Pending) -> ()

-- Выпустить ждущих, пока есть место (с маленьким шагом, чтобы не въезжали разом).
local function drain()
	local free = capacity() - #active
	local index = 0
	while free > 0 and #queue > 0 do
		local item = table.remove(queue, 1) :: Pending
		free -= 1
		if index == 0 then
			present(item)
		else
			task.delay(0.15 * index, present, item)
		end
		index += 1
	end
end

local function dismiss(toast: Toast, quick: boolean?)
	local index = table.find(active, toast)
	if not index then
		return -- уже уходит
	end
	table.remove(active, index)
	toast.trove:Clean()
	local frame = toast.frame
	frame.Name = "ToastLeaving"
	frame.ZIndex = math.max(frame.ZIndex - 1, 0) -- остальные проезжают поверх
	local time = if quick then 0.15 else LEAVE_TIME
	UiFx.tween(
		frame,
		time,
		{ Position = frame.Position - UDim2.fromScale(0, toast.height * 0.15) },
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.In
	)
	UiFx.tween(UiFx.scaleOf(frame), time, { Scale = 0.9 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	UiFx.fadeOut(frame, time)
	task.delay(time + 0.02, function()
		frame:Destroy()
	end)
	task.delay(REFLOW_DELAY, function()
		reflow()
		drain()
	end)
end

-- Срок вышел: уходит, но не раньше чем через UIConfig.ToastGap после предыдущего ухода.
local function expire(toast: Toast)
	if not table.find(active, toast) then
		return
	end
	local now = os.clock()
	local wait = lastDismiss + UIConfig.ToastGap - now
	if wait > 0 then
		toast.trove:Add(task.delay(wait, expire, toast))
		return
	end
	lastDismiss = now
	dismiss(toast)
end

-- Кого вытеснить ради уведомления с приоритетом priority: самое старое из самых неважных.
local function victimFor(priority: number, strict: boolean): Toast?
	local chosen: Toast? = nil
	for _, toast in active do
		local fits = if strict then toast.priority < priority else toast.priority <= priority
		if fits and (chosen == nil or toast.priority < chosen.priority) then
			chosen = toast
		end
	end
	return chosen
end

-- Сколько текста влезает: ширина уведомления под надпись (доля колонки) и нужна ли вторая строка.
local function measure(text: string, tier: string): (number, boolean)
	local length = utf8.len(text) or #text
	local column = container
	local columnWidth = if column then column.AbsoluteSize.X else 0
	if columnWidth <= 1 then
		return math.clamp(0.34 + length * 0.021, 0.56, 1), false -- раскладки ещё нет
	end
	local textWidth = length * 0.5 * UiFx.textSize(tier)
	local share = textWidth / (LABEL_SHARE * 0.94) / columnWidth
	if share <= 1 then
		return math.max(share, MIN_WIDTH), false
	end
	return 1, true
end

present = function(item: Pending)
	local parent, source = container, template
	if not parent or not source then
		return
	end
	counter += 1
	local style = styleOf(item.kind)
	local look: Look = item.look or {} :: Look
	local big = style.Big == true
	local tier = if big then "Button" else "Body"
	local natural, twoLines = measure(item.text, tier)
	local height = SLOT * (if big then BIG else 1) * (if twoLines then TWO_LINES else 1)

	local frame = source:Clone()
	frame.Name = "Toast"
	frame.LayoutOrder = counter
	frame.Size = UDim2.fromScale(natural, height)
	frame:SetAttribute("Kind", item.kind)
	frame:SetAttribute("NaturalWidth", natural) -- своя ширина по тексту (в стопке — по самому широкому)
	UiFx.setCandy(frame, look.swatch or style.Token)
	local trove = Trove.new()
	local toast: Toast = {
		frame = frame,
		priority = style.Priority or 1,
		height = height,
		natural = natural,
		trove = trove,
		entering = true,
	}

	local label = frame:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		label.Text = item.text
		label.TextWrapped = true
		label:SetAttribute("TextTier", tier) -- до вставки: UiFx.fitText подгонит при добавлении
	end
	local socket = frame:FindFirstChild("IconSocket")
	local icon = if socket then socket:FindFirstChild("Icon") else nil
	if icon and icon:IsA("TextLabel") then
		icon.Text = look.icon or style.Icon
	end
	if style.Rainbow then
		-- Радужная «конфета»: цвета радуги по лицевой стороне, градиент медленно вращается.
		local face = UiFx.faceOf(frame)
		local fill = face:FindFirstChild("Fill")
		if fill and fill:IsA("UIGradient") then
			fill.Color = UiFx.sequence(UIConfig.Rainbow)
			fill.Rotation = 0
			local spin = TweenService:Create(
				fill,
				TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1),
				{ Rotation = 360 }
			)
			spin:Play()
			trove:Add(function()
				spin:Cancel()
			end)
		end
		local lip = frame:FindFirstChild("Lip")
		if lip and lip:IsA("GuiObject") then
			lip.BackgroundColor3 = UIConfig.Rarity.Mythic.Lip
		end
	end

	table.insert(active, toast)
	local slot = #active
	frame.Position = slotPosition(slot) - UDim2.fromScale(0, 0.3)
	frame.Visible = true
	frame.Parent = parent

	-- Въезд: сверху в слот с пружиной, значок выскакивает следом, потом блик.
	UiFx.tween(frame, ENTER_TIME, { Position = slotPosition(slot) }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	UiFx.popIn(frame, { from = if big then 0.3 else 0.5, time = ENTER_TIME })
	if socket and socket:IsA("GuiObject") then
		UiFx.popIn(socket, { from = 0, time = 0.4, delay = 0.12, rotate = -25 })
		trove:Add(task.delay(0.5, function()
			if socket.Parent then
				UiFx.wiggle(socket, if item.kind == "warning" or big then 16 else 9, 3, 0.45)
			end
		end))
	end
	trove:Add(task.delay(0.3, function()
		UiFx.shine(frame, if big then 0.8 else 0.6)
	end))
	if big then
		trove:Add(UiFx.sparkles(frame, { rate = 7, duration = 2, size = 0.7 }))
		trove:Add(UiFx.arpeggio(if style.Rainbow then "Legendary" else "Epic", 0.25))
	elseif item.kind == "success" or item.kind == "base" then
		trove:Add(UiFx.sparkles(frame, { rate = 6, duration = 1.2, size = 0.75 }))
	elseif item.kind == "danger" then
		trove:Add(task.delay(ENTER_TIME, function()
			UiFx.wiggle(frame, 4, 3, 0.4)
		end))
	end
	reflow()
	trove:Add(task.delay(ENTER_TIME, function()
		toast.entering = false
		reflow() -- пока въезжал, слот мог сдвинуться
	end))

	trove:Add(task.delay(style.Life or UIConfig.ToastDuration, expire, toast))
end

-- Показать уведомление. Можно вызывать из любых клиентских модулей.
function NotifyController.Show(text: string, kind: string?, look: Look?)
	if not container or not template then
		return -- контроллер ещё не запущен
	end
	local name = kind or "info"
	if not UIConfig.ToastKinds[name] then
		name = "info"
	end
	local item: Pending = { text = text, kind = name, look = look }
	if #active < capacity() then
		present(item)
		return
	end
	-- Места нет: вытесняем неважное (на телефоне с открытой рыбалкой — только ради более важного).
	local priority = styleOf(name).Priority or 1
	local victim = victimFor(priority, busy())
	if victim then
		dismiss(victim, true)
		present(item)
		return
	end
	table.insert(queue, item)
	while #queue > MAX_QUEUE do
		table.remove(queue, 1)
	end
end

-- Рыбалка открыла/закрыла свой виджет: лишние уведомления уходят, ждущие выходят.
local function onBusyChanged()
	local cap = capacity()
	while #active > cap do
		local victim = victimFor(math.huge, false)
		if not victim then
			break
		end
		dismiss(victim, true)
	end
	if #active < cap then
		drain()
	end
end

function NotifyController:Start(hud: ScreenGui)
	local toasts = hud:WaitForChild("Toasts") :: Frame
	local toastTemplate = toasts:WaitForChild("ToastTemplate") :: Frame
	toastTemplate.Visible = false
	container = toasts
	template = toastTemplate

	local fishing = hud:FindFirstChild("Fishing")
	if fishing then
		for _, name in BUSY_WIDGETS do
			local widget = fishing:FindFirstChild(name)
			if widget and widget:IsA("GuiObject") then
				table.insert(busyWidgets, widget)
				widget:GetPropertyChangedSignal("Visible"):Connect(onBusyChanged)
			end
		end
	end

	Net.Event("Notify").OnClientEvent:Connect(function(text: any, kind: any)
		if typeof(text) ~= "string" then
			return
		end
		NotifyController.Show(text, if typeof(kind) == "string" then kind else "info")
	end)
end

return NotifyController
