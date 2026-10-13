--!strict
--[[
	FishingController — рыбалка локального игрока: кнопка действия, поклёвка, мини-игра,
	карточка улова и подсказки (Этап 2). Интерфейс — HUD.Fishing (см. tools/builder/Gui.luau).

	Сервер (FishingService) решает всё сам. Клиент только просит (FishingCast / FishingHook /
	FishingTap / FishingStop) и показывает то, что сервер прислал в FishingState
	(протокол — в шапке RemoteNames).

	  • Кнопка действия (ActionArea.ActionButton) видна, пока удочка в руке персонажа.
	    Надпись и цвет — по состоянию: «ЗАБРОСИТЬ» (синяя) → «ЖДЁМ…» (тусклая, нажатия
	    не работают) → «ПОДСЕЧЬ!» (оранжевая, пульсирует) → «ТЯНИ!» (зелёная).
	    То же действие — тап/клик удочкой по миру (Tool.Activated) и клавиша E / R2 на геймпаде
	    (ContextActionService, только пока удочка в руке). Без тач-экрана на кнопке — подсказка
	    клавиши: «ЗАБРОСИТЬ [E]».
	  • «СМОТАТЬ» (StopButton) — пока леска в воде.
	  • Поклёвка (BiteAlert) мигает, полоска времени тает за Window секунд.
	  • Мини-игра (Minigame): стрелка = FishingRules.Needle(U0, Speed, t), где t — сколько секунд
	    прошло с получения "Minigame" (os.clock). Нажатие отправляет серверу это же t, а сервер
	    проверяет попадание по той же формуле — игрок видит ровно то, что проверяет сервер.
	  • Карточка улова (CatchCard): редкость, 3D-модель рыбы во ViewportFrame (медленно
	    вращается), вес и цена; закрывается тапом, действием или сама через CatchCardTime.
	    Счётчик «Улов: N» — HUD.Status.CatchCounter.
	  • Подсказка (Hint): почему заброс не принят, почему рыба ушла, куда идти. Если игрок с
	    удочкой далеко от точки рыбалки своей базы — к ней тянется дорожка-луч (Beam, только у него).

	Уборка: всё, что живёт с персонажем, — в characterTrove; пока удочка в руке — в rodTrove;
	анимации текущего состояния — в phaseTrove; карточка улова — в cardTrove.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local FishingConfig = require(Config:WaitForChild("FishingConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local FishingRules = require(Shared:WaitForChild("FishingRules"))
local Net = require(Shared:WaitForChild("Net"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))

local player = Players.LocalPlayer

local ACTION_NAME = "FishingAction"
local PENDING_TIMEOUT = 1.5 -- ответа на заброс нет столько секунд — кнопка снова «Забросить»
local ACTION_DEBOUNCE = 0.05 -- одно нажатие могут поймать два пути ввода (кнопка + удочка)
local HINT_TIME = 3.5 -- сколько висит подсказка о событии, с
local CONTEXT_CHECK_INTERVAL = 0.25 -- как часто проверять, у точки ли рыбалки игрок, с
local CARD_TURN_SPEED = 0.8 -- рыба в карточке поворачивается, радиан в секунду
local CARD_FOV = 40

local HINT_NEAR = "Жми «Забросить»"
local HINT_FAR = "Иди на край своего пирса — к сверкающему кругу"

-- Почему рыба ушла (если сервер не прислал свой текст).
local LOST_TEXT: { [string]: string } = {
	early = "Рано! Рыба испугалась и уплыла",
	late = "Не успел подсечь — рыба ушла",
	miss = "Мимо! Рыба сорвалась",
	timeout = "Рыба устала ждать и уплыла",
}

-- Почему рыбалка закончилась ("Idle"); причины без текста — молча.
local IDLE_TEXT: { [string]: string } = {
	stop = "Леска смотана",
	moved = "Ты отошёл от края пирса — леска смотана",
	unequipped = "Удочка убрана — леска смотана",
	base = "Леска смотана",
}

local COLORS = {
	Cast = Color3.fromRGB(40, 132, 226),
	Wait = Color3.fromRGB(92, 104, 128),
	Bite = Color3.fromRGB(240, 140, 30),
	Reel = Color3.fromRGB(64, 200, 96),
	PipDone = Color3.fromRGB(64, 200, 96),
	Flash = Color3.fromRGB(255, 255, 255),
	Guide = Color3.fromRGB(255, 214, 80),
	HintInfo = Color3.fromRGB(22, 28, 48),
}

type Phase = "Idle" | "Pending" | "Waiting" | "Bite" | "Reeling"

type Look = { Caption: string, Icon: string, Color: Color3, Key: boolean, Dim: boolean }

-- Как выглядит кнопка действия в каждом состоянии.
local LOOKS: { [Phase]: Look } = {
	Idle = { Caption = "ЗАБРОСИТЬ", Icon = "🎣", Color = COLORS.Cast, Key = true, Dim = false },
	Pending = { Caption = "ЖДЁМ…", Icon = "⏳", Color = COLORS.Wait, Key = false, Dim = true },
	Waiting = { Caption = "ЖДЁМ…", Icon = "⏳", Color = COLORS.Wait, Key = false, Dim = true },
	Bite = { Caption = "ПОДСЕЧЬ!", Icon = "❗", Color = COLORS.Bite, Key = true, Dim = false },
	Reeling = { Caption = "ТЯНИ!", Icon = "💪", Color = COLORS.Reel, Key = true, Dim = false },
}

type Minigame = {
	Rarity: string,
	U0: number,
	Speed: number,
	ZoneCenter: number,
	ZoneWidth: number,
	Hits: number,
	HitsNeeded: number,
	Timeout: number,
}

type Ui = {
	actionButton: GuiButton,
	actionIcon: TextLabel,
	actionCaption: TextLabel,
	actionScale: UIScale,
	stopButton: GuiButton,
	biteAlert: Frame,
	biteTimer: Frame,
	biteScale: UIScale,
	minigame: Frame,
	minigameScale: UIScale,
	title: TextLabel,
	pips: { Frame },
	zone: Frame,
	needle: Frame,
	timeFill: Frame,
	hint: TextLabel,
	hintScale: UIScale,
	card: GuiButton,
	cardScale: UIScale,
	banner: Frame,
	rarityLabel: TextLabel,
	viewport: ViewportFrame,
	nameLabel: TextLabel,
	mutationLabel: TextLabel,
	infoLabel: TextLabel,
	counter: Frame,
	counterLabel: TextLabel,
	counterScale: UIScale,
}

-- Исходные значения из шаблона HUD (возвращаются после анимаций).
type Defaults = {
	minigamePosition: UDim2,
	biteTimerSize: UDim2,
	zoneColor: Color3,
	zoneHeight: number,
	needleY: number,
	pipColor: Color3,
}

type Guide = { beam: Beam, from: Attachment, to: Attachment, spot: BasePart }

local FishingController = {}

local ui: Ui
local defaults: Defaults
local keyHint = ""

local phase: Phase = "Idle"
local rod: Tool? = nil -- удочка в руке
local hookSent = false
local minigame: Minigame? = nil
local minigameStart = 0 -- os.clock() получения "Minigame"
local lastTap = -math.huge
local lastAction = -math.huge
local pendingThread: thread? = nil
local hintThread: thread? = nil
local eventHint: { text: string, color: Color3 }? = nil
local contextHint: string? = nil
local guide: Guide? = nil

local characterTrove = Trove.new()
local rodTrove = Trove.new()
local phaseTrove = Trove.new()
local cardTrove = Trove.new()

--------------------------------------------------------------------------------
-- Мелкие помощники
--------------------------------------------------------------------------------

-- Число из данных сервера: только конечные числа, иначе default.
local function number(value: any, default: number): number
	if typeof(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
	return default
end

-- Заглавные буквы, включая кириллицу (string.upper меняет только латиницу).
local function upper(text: string): string
	local out = {}
	for _, code in utf8.codes(text) do
		if (code >= 0x430 and code <= 0x44F) or (code >= 0x61 and code <= 0x7A) then
			code -= 0x20
		elseif code == 0x451 then
			code = 0x401 -- ё → Ё
		end
		table.insert(out, utf8.char(code))
	end
	return table.concat(out)
end

local function child(parent: Instance, name: string): any
	return parent:WaitForChild(name)
end

-- UIScale для «пульса» и «выскакивания» элемента (создаётся один раз).
local function scaleOf(gui: GuiObject): UIScale
	local existing = gui:FindFirstChild("FxScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = "FxScale"
	scale.Parent = gui
	return scale
end

-- Бесконечная пульсация масштаба; остановится при очистке trove.
local function pulse(trove: Trove.Trove, scale: UIScale, peak: number, period: number)
	scale.Scale = 1
	local info = TweenInfo.new(period / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(scale, info, { Scale = peak })
	tween:Play()
	trove:Add(function()
		tween:Cancel()
		scale.Scale = 1
	end)
end

-- «Выскакивание»: элемент быстро вырастает от from до 1.
local function pop(scale: UIScale, from: number, time: number?)
	scale.Scale = from
	TweenService:Create(scale, TweenInfo.new(time or 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	}):Play()
end

local function isRod(instance: Instance): boolean
	return instance:IsA("Tool") and typeof(instance:GetAttribute("RodId")) == "string"
end

local function isLineOut(): boolean
	return phase == "Waiting" or phase == "Bite" or phase == "Reeling"
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- Точка рыбалки своей базы: Workspace.Bases.* с тем же BaseIndex, что у игрока.
local function ownFishingSpot(): BasePart?
	local index = player:GetAttribute("BaseIndex")
	local bases = Workspace:FindFirstChild("Bases")
	if typeof(index) ~= "number" or index <= 0 or not bases then
		return nil
	end
	for _, base in bases:GetChildren() do
		if base:GetAttribute("BaseIndex") == index then
			local spot = base:FindFirstChild("FishingSpot")
			return if spot and spot:IsA("BasePart") then spot else nil
		end
	end
	return nil
end

-- Тот же допуск, что проверяет сервер: SpotRadius по горизонтали, SpotMaxHeight по высоте.
local function isNearSpot(root: BasePart, spot: BasePart): boolean
	local offset = root.Position - spot.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z).Magnitude
	return horizontal <= FishingConfig.SpotRadius and math.abs(offset.Y) <= FishingConfig.SpotMaxHeight
end

--------------------------------------------------------------------------------
-- Подсказка внизу экрана и дорожка к точке рыбалки
--------------------------------------------------------------------------------

-- Подсказка о событии (eventHint) важнее постоянной подсказки по месту (contextHint).
local function renderHint()
	local hint = ui.hint
	if eventHint then
		hint.Text = eventHint.text
		hint.BackgroundColor3 = eventHint.color
		hint.Visible = true
	elseif contextHint then
		hint.Text = contextHint
		hint.BackgroundColor3 = COLORS.HintInfo
		hint.Visible = true
	else
		hint.Visible = false
	end
end

-- Подсказка о событии: висит HINT_TIME секунд и прячется сама.
local function showHint(text: string, kind: string)
	if hintThread then
		task.cancel(hintThread)
	end
	local color = if kind == "info" then COLORS.HintInfo else UIConfig.KindColors[kind] or COLORS.HintInfo
	eventHint = { text = text, color = color }
	renderHint()
	pop(ui.hintScale, 0.8, 0.2)
	hintThread = task.delay(HINT_TIME, function()
		hintThread = nil
		eventHint = nil
		renderHint()
	end)
end

local function setContextHint(text: string?)
	if contextHint == text then
		return
	end
	contextHint = text
	renderHint()
end

local function destroyGuide()
	local current = guide
	guide = nil
	if current then
		current.beam:Destroy()
		current.from:Destroy()
		current.to:Destroy()
	end
end

-- Луч от персонажа к точке рыбалки (создаётся только на этом клиенте).
local function createGuide(root: BasePart, spot: BasePart): Guide
	local from = Instance.new("Attachment")
	from.Name = "FishingGuideFrom"
	from.Parent = root
	local to = Instance.new("Attachment")
	to.Name = "FishingGuideTo"
	to.Position = Vector3.new(0, spot.Size.Y / 2 + 0.4, 0)
	to.Parent = spot

	local beam = Instance.new("Beam")
	beam.Name = "FishingGuide"
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = 0.3
	beam.Width1 = 0.8
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(COLORS.Guide)
	beam.Transparency = NumberSequence.new(0.55, 0.15)
	beam.Parent = root
	return { beam = beam, from = from, to = to, spot = spot }
end

local function setGuide(spot: BasePart?)
	local root = rootPart()
	if not spot or not root then
		if guide then
			guide.beam.Enabled = false
		end
		return
	end
	local old = guide
	if old and (old.spot ~= spot or old.from.Parent ~= root) then
		destroyGuide() -- другая база или новый персонаж
	end
	local current = guide or createGuide(root, spot)
	guide = current
	current.beam.Enabled = true
end

-- Подсказка по месту: с удочкой, без рыбалки — «жми» у точки или «иди к кругу» + луч.
local function refreshContextHint()
	local text: string? = nil
	local guideTo: BasePart? = nil
	local root = rootPart()
	local spot = ownFishingSpot()
	if rod and phase == "Idle" and not ui.card.Visible and root and spot then
		if isNearSpot(root, spot) then
			text = HINT_NEAR
		else
			text = HINT_FAR
			guideTo = spot
		end
	end
	setGuide(guideTo)
	setContextHint(text)
end

--------------------------------------------------------------------------------
-- Кнопка действия и состояния рыбалки
--------------------------------------------------------------------------------

local function refreshButtons()
	local look = LOOKS[phase]
	local button = ui.actionButton
	button.Visible = rod ~= nil
	button.BackgroundColor3 = look.Color
	button.BackgroundTransparency = if look.Dim then 0.35 else 0
	button.AutoButtonColor = not look.Dim
	ui.actionCaption.Text = look.Caption .. (if look.Key then keyHint else "")
	ui.actionIcon.Text = look.Icon
	ui.stopButton.Visible = rod ~= nil and isLineOut()
end

local function cancelPending()
	local thread = pendingThread
	pendingThread = nil
	if thread and thread ~= coroutine.running() then
		task.cancel(thread)
	end
end

-- Новое состояние: убираем анимации и окна прошлого, обновляем кнопки.
local function setPhase(newPhase: Phase)
	cancelPending()
	phaseTrove:Clean()
	phase = newPhase
	if newPhase ~= "Reeling" then
		minigame = nil
	end
	ui.biteAlert.Visible = false
	ui.minigame.Visible = false
	refreshButtons()
	refreshContextHint()
end

local function endSession()
	hookSent = false
	setPhase("Idle")
end

--------------------------------------------------------------------------------
-- Карточка улова
--------------------------------------------------------------------------------

local function updateCounter(total: number)
	if total <= 0 then
		return
	end
	local text = `Улов: {math.floor(total)}`
	if ui.counterLabel.Text ~= text or not ui.counter.Visible then
		ui.counter.Visible = true
		ui.counterLabel.Text = text
		pop(ui.counterScale, 1.3, 0.3)
	end
end

local function closeCard()
	cardTrove:Clean()
	ui.card.Visible = false
	refreshContextHint()
end

-- Модель рыбы: Assets.Fish.<Id>.<мутация или Normal>.
local function fishTemplate(fish: FishingRules.FishData): Model?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local fishFolder = assets and assets:FindFirstChild("Fish")
	local variants = fishFolder and fishFolder:FindFirstChild(fish.Id)
	if not variants then
		return nil
	end
	local model = variants:FindFirstChild(fish.Mutation or "Normal") or variants:FindFirstChild("Normal")
	return if model and model:IsA("Model") then model else nil
end

-- Рыба во ViewportFrame: центр габаритов в нуле, камера сбоку, рыба медленно вращается.
local function showFishModel(fish: FishingRules.FishData)
	local template = fishTemplate(fish)
	if not template then
		return
	end
	local model = cardTrove:Add(template:Clone())
	local box, size = model:GetBoundingBox()
	local centred = model:GetPivot() - box.Position
	model:PivotTo(centred)
	model.Parent = ui.viewport

	local camera = cardTrove:Add(Instance.new("Camera"))
	camera.FieldOfView = CARD_FOV
	local radius = math.max(size.Magnitude / 2, 0.5)
	local distance = radius / math.tan(math.rad(CARD_FOV / 2)) * 1.05
	camera.CFrame = CFrame.lookAt(Vector3.new(0, radius * 0.35, distance), Vector3.zero)
	camera.Parent = ui.viewport
	ui.viewport.CurrentCamera = camera

	local yaw = 0
	cardTrove:Connect(RunService.RenderStepped, function(dt: number)
		yaw = (yaw + dt * CARD_TURN_SPEED) % (2 * math.pi)
		model:PivotTo(CFrame.Angles(0, yaw, 0) * centred)
	end)
end

local function fillCard(fish: FishingRules.FishData)
	local rarity = FishingRules.GetRarity(fish.Rarity)
	ui.banner.BackgroundColor3 = if rarity then rarity.Color else COLORS.Wait
	ui.rarityLabel.Text = upper(if rarity then rarity.Name else fish.Rarity)
	ui.nameLabel.Text = FishingRules.DisplayName(fish)

	local mutationText = FishingRules.MutationLabel(fish)
	local mutation = fish.Mutation and FishingRules.GetMutation(fish.Mutation)
	ui.mutationLabel.Visible = mutationText ~= nil
	ui.mutationLabel.Text = mutationText or ""
	if mutation then
		ui.mutationLabel.BackgroundColor3 = mutation.Color
	end
	ui.infoLabel.Text = `{FishingRules.FormatKg(fish.Kg)} · цена {math.round(fish.Value)} 💰`
end

local function openCard(fish: FishingRules.FishData)
	cardTrove:Clean()
	fillCard(fish)
	showFishModel(fish)
	ui.card.Visible = true
	pop(ui.cardScale, 0.4, 0.35)
	cardTrove:Add(task.delay(FishingConfig.CatchCardTime, closeCard))
	refreshContextHint()
end

-- FishData из данных сервера (только нужные поля, с проверкой типов).
local function parseFish(value: any): FishingRules.FishData?
	if typeof(value) ~= "table" or typeof(value.Id) ~= "string" then
		return nil
	end
	local def = FishingRules.GetFish(value.Id)
	local rarity = if typeof(value.Rarity) == "string" then value.Rarity elseif def then def.Rarity else "Common"
	return {
		Id = value.Id,
		Rarity = rarity,
		Mutation = if typeof(value.Mutation) == "string" then value.Mutation else nil,
		Kg = number(value.Kg, 0),
		Value = number(value.Value, 0),
		Income = number(value.Income, 0),
	}
end

--------------------------------------------------------------------------------
-- Поклёвка и мини-игра
--------------------------------------------------------------------------------

local function enterBite(window: number)
	setPhase("Bite")
	hookSent = false
	ui.biteAlert.Visible = true
	local timer = ui.biteTimer
	local full = defaults.biteTimerSize
	timer.Size = full
	local shrink = TweenService:Create(timer, TweenInfo.new(math.max(window, 0.05), Enum.EasingStyle.Linear), {
		Size = UDim2.fromScale(0, full.Y.Scale),
	})
	shrink:Play()
	phaseTrove:Add(function()
		shrink:Cancel()
		timer.Size = full
	end)
	pulse(phaseTrove, ui.biteScale, 1.08, 0.36)
	pulse(phaseTrove, ui.actionScale, 1.12, 0.4)
end

-- Сервер прислал непонятное — подстраиваемся под атрибут FishingState (его ставит сервер).
local function syncFromAttribute()
	local state = player:GetAttribute("FishingState")
	if state == "Waiting" or state == "Reeling" then
		setPhase("Waiting") -- без данных мини-игры можно только ждать или смотать
	elseif state == "Bite" then
		enterBite(FishingConfig.BiteWindow)
	else
		setPhase("Idle")
	end
end

local function startPending()
	setPhase("Pending")
	pendingThread = task.delay(PENDING_TIMEOUT, function()
		pendingThread = nil
		if phase == "Pending" then
			syncFromAttribute()
		end
	end)
end

local function refreshPips(mg: Minigame)
	for index, pip in ui.pips do
		pip.Visible = index <= mg.HitsNeeded
		pip.BackgroundColor3 = if index <= mg.Hits then COLORS.PipDone else defaults.pipColor
	end
end

-- Каждый кадр: стрелка по общей формуле и полоска оставшегося времени.
local function updateMinigameFrame()
	local mg = minigame
	if not mg then
		return
	end
	local elapsed = os.clock() - minigameStart
	ui.needle.Position = UDim2.fromScale(FishingRules.Needle(mg.U0, mg.Speed, elapsed), defaults.needleY)
	ui.timeFill.Size = UDim2.fromScale(math.clamp(1 - elapsed / mg.Timeout, 0, 1), 1)
end

local function showMinigame(mg: Minigame)
	local rarity = FishingRules.GetRarity(mg.Rarity)
	ui.title.Text = `{upper(if rarity then rarity.Name else "Неизвестная")} РЫБА!`
	ui.title.TextColor3 = if rarity then rarity.Color else COLORS.Flash
	refreshPips(mg)
	ui.zone.Position = UDim2.fromScale(mg.ZoneCenter, 0.5)
	ui.zone.Size = UDim2.fromScale(mg.ZoneWidth, defaults.zoneHeight)
	ui.zone.BackgroundColor3 = defaults.zoneColor
	ui.minigame.Position = defaults.minigamePosition
	updateMinigameFrame()
	ui.minigame.Visible = true
	pop(ui.minigameScale, 0.7, 0.25)
	phaseTrove:Connect(RunService.RenderStepped, updateMinigameFrame)
end

-- Попадание: зона вспыхивает, окно мини-игры вздрагивает.
local function flashHit()
	local zone, frame = ui.zone, ui.minigame
	zone.BackgroundColor3 = COLORS.Flash
	local flash = TweenService:Create(zone, TweenInfo.new(0.3), { BackgroundColor3 = defaults.zoneColor })
	flash:Play()
	local base = defaults.minigamePosition
	frame.Position = base
	local shakeInfo = TweenInfo.new(0.04, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, 2, true)
	local shake = TweenService:Create(frame, shakeInfo, {
		Position = UDim2.fromScale(base.X.Scale + 0.008, base.Y.Scale),
	})
	shake:Play()
	phaseTrove:Add(function()
		flash:Cancel()
		shake:Cancel()
		zone.BackgroundColor3 = defaults.zoneColor
		frame.Position = base
	end)
	pop(ui.actionScale, 1.25, 0.2)
end

--------------------------------------------------------------------------------
-- Действие игрока: забросить / подсечь / тянуть / закрыть карточку
--------------------------------------------------------------------------------

local function tap()
	local now = os.clock()
	if now - lastTap < FishingConfig.TapInterval then
		return -- сервер всё равно не примет чаще
	end
	lastTap = now
	Net.Event("FishingTap"):FireServer(now - minigameStart)
	pop(ui.actionScale, 0.85, 0.15)
end

local function doAction()
	local now = os.clock()
	if now - lastAction < ACTION_DEBOUNCE then
		return
	end
	lastAction = now
	if ui.card.Visible then
		closeCard()
	elseif not rod then
		return
	elseif phase == "Idle" then
		Net.Event("FishingCast"):FireServer()
		startPending()
		pop(ui.actionScale, 0.85, 0.2)
	elseif phase == "Bite" then
		if not hookSent then
			hookSent = true
			Net.Event("FishingHook"):FireServer()
		end
	elseif phase == "Reeling" then
		tap()
	end
end

local function onActionInput(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		doAction()
	end
	return Enum.ContextActionResult.Sink
end

local function requestStop()
	if not isLineOut() then
		return
	end
	Net.Event("FishingStop"):FireServer()
	endSession() -- сервер подтвердит "Idle" { Reason = "stop" }
end

--------------------------------------------------------------------------------
-- Ответы сервера (FishingState)
--------------------------------------------------------------------------------

local function onWaiting(_data: { [string]: any })
	hookSent = false
	setPhase("Waiting")
end

local function onBite(data: { [string]: any })
	enterBite(number(data.Window, FishingConfig.BiteWindow))
end

local function onMinigame(data: { [string]: any })
	local rarity = if typeof(data.Rarity) == "string" then data.Rarity else "Common"
	local rule = FishingRules.GetMinigameRule(rarity)
	local mg: Minigame = {
		Rarity = rarity,
		U0 = number(data.U0, 0),
		Speed = number(data.Speed, rule.Speed),
		ZoneCenter = number(data.ZoneCenter, 0.5),
		ZoneWidth = number(data.ZoneWidth, rule.ZoneWidth),
		Hits = number(data.Hits, 0),
		HitsNeeded = math.clamp(math.floor(number(data.HitsNeeded, rule.Hits)), 1, #ui.pips),
		Timeout = math.max(number(data.Timeout, FishingConfig.MinigameTimeout), 0.1),
	}
	setPhase("Reeling")
	minigame = mg
	minigameStart = os.clock()
	lastTap = -math.huge
	showMinigame(mg)
end

local function onZone(data: { [string]: any })
	local mg = minigame
	if phase ~= "Reeling" or not mg then
		return
	end
	mg.ZoneCenter = number(data.ZoneCenter, mg.ZoneCenter)
	mg.Hits = number(data.Hits, mg.Hits + 1)
	refreshPips(mg)
	TweenService:Create(ui.zone, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromScale(mg.ZoneCenter, 0.5),
	}):Play()
	flashHit()
end

local function onCaught(data: { [string]: any })
	endSession()
	local fish = parseFish(data.Fish)
	if fish then
		openCard(fish)
	end
	if data.Total ~= nil then
		updateCounter(number(data.Total, 0))
	end
end

local function onLost(data: { [string]: any })
	endSession()
	local reason = if typeof(data.Reason) == "string" then data.Reason else ""
	local text = if typeof(data.Text) == "string" and data.Text ~= "" then data.Text else LOST_TEXT[reason]
	showHint(text or "Рыба ушла", "warning")
end

local function onIdle(data: { [string]: any })
	endSession()
	local text = if typeof(data.Reason) == "string" then IDLE_TEXT[data.Reason] else nil
	if text then
		showHint(text, "info")
	end
end

local function onDenied(data: { [string]: any })
	if data.Reason == "busy" then
		syncFromAttribute() -- сервер считает, что леска уже в воде
	elseif phase == "Pending" then
		setPhase("Idle")
	end
	if typeof(data.Text) == "string" and data.Text ~= "" then
		showHint(data.Text, "warning")
	end
end

local HANDLERS: { [string]: ({ [string]: any }) -> () } = {
	Waiting = onWaiting,
	Bite = onBite,
	Minigame = onMinigame,
	Zone = onZone,
	Caught = onCaught,
	Lost = onLost,
	Idle = onIdle,
	Denied = onDenied,
}

local function onFishingState(state: any, data: any)
	local handler = if typeof(state) == "string" then HANDLERS[state] else nil
	if handler then
		handler(if typeof(data) == "table" then data else {})
	end
end

--------------------------------------------------------------------------------
-- Удочка в руке и персонаж
--------------------------------------------------------------------------------

local function unequipRod()
	if not rod then
		return
	end
	rod = nil
	rodTrove:Clean()
	endSession() -- сервер сам смотает леску ("Idle" { Reason = "unequipped" })
end

local function equipRod(tool: Tool)
	if rod == tool then
		return
	end
	unequipRod()
	rod = tool
	rodTrove:Connect(tool.Activated, doAction)
	ContextActionService:BindAction(ACTION_NAME, onActionInput, false, Enum.KeyCode.E, Enum.KeyCode.ButtonR2)
	rodTrove:Add(function()
		ContextActionService:UnbindAction(ACTION_NAME)
	end)
	-- Подсказка «куда идти» нужна только с удочкой в руке.
	local sinceCheck = 0
	rodTrove:Connect(RunService.Heartbeat, function(dt: number)
		sinceCheck += dt
		if sinceCheck >= CONTEXT_CHECK_INTERVAL then
			sinceCheck = 0
			refreshContextHint()
		end
	end)
	pop(ui.actionScale, 0.5, 0.3)
	refreshButtons()
	refreshContextHint()
end

local function onCharacterAdded(character: Model)
	characterTrove:Clean()
	characterTrove:Add(unequipRod)
	characterTrove:Add(destroyGuide)
	local alive = true
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		characterTrove:Connect(humanoid.Died, function()
			alive = false
			unequipRod() -- мёртвым не рыбачат: кнопка прячется сразу, а не при возрождении
		end)
	end
	characterTrove:Connect(character.ChildAdded, function(item: Instance)
		if alive and isRod(item) then
			equipRod(item :: Tool)
		end
	end)
	characterTrove:Connect(character.ChildRemoved, function(item: Instance)
		if item == rod then
			unequipRod()
		end
	end)
	endSession()
	for _, item in character:GetChildren() do
		if isRod(item) then
			equipRod(item :: Tool)
		end
	end
end

local function onCharacterRemoving()
	characterTrove:Clean()
	endSession()
end

--------------------------------------------------------------------------------
-- Запуск
--------------------------------------------------------------------------------

local function collectUi(hud: ScreenGui): Ui
	local fishing = child(hud, "Fishing")
	local area = child(fishing, "ActionArea")
	local action = child(area, "ActionButton")
	local alert = child(fishing, "BiteAlert")
	local mini = child(fishing, "Minigame")
	local track = child(mini, "Track")
	local pipsFolder = child(mini, "Pips")
	local card = child(fishing, "CatchCard")
	local banner = child(card, "Banner")
	local counter = child(child(hud, "Status"), "CatchCounter")

	local pips: { Frame } = {}
	for index = 1, 5 do
		local pip = pipsFolder:FindFirstChild(`Pip{index}`)
		if not pip then
			break
		end
		table.insert(pips, pip :: Frame)
	end

	local hint = child(fishing, "Hint")
	return {
		actionButton = action,
		actionIcon = child(action, "Icon"),
		actionCaption = child(action, "Caption"),
		actionScale = scaleOf(action),
		stopButton = child(area, "StopButton"),
		biteAlert = alert,
		biteTimer = child(alert, "Timer"),
		biteScale = scaleOf(alert),
		minigame = mini,
		minigameScale = scaleOf(mini),
		title = child(mini, "Title"),
		pips = pips,
		zone = child(track, "Zone"),
		needle = child(track, "Needle"),
		timeFill = child(child(mini, "TimeBar"), "Fill"),
		hint = hint,
		hintScale = scaleOf(hint),
		card = card,
		cardScale = scaleOf(card),
		banner = banner,
		rarityLabel = child(banner, "RarityLabel"),
		viewport = child(card, "Viewport"),
		nameLabel = child(card, "NameLabel"),
		mutationLabel = child(card, "MutationLabel"),
		infoLabel = child(card, "InfoLabel"),
		counter = counter,
		counterLabel = child(counter, "Label"),
		counterScale = scaleOf(counter),
	}
end

local function readDefaults(): Defaults
	return {
		minigamePosition = ui.minigame.Position,
		biteTimerSize = ui.biteTimer.Size,
		zoneColor = ui.zone.BackgroundColor3,
		zoneHeight = ui.zone.Size.Y.Scale,
		needleY = ui.needle.Position.Y.Scale,
		pipColor = if ui.pips[1] then ui.pips[1].BackgroundColor3 else COLORS.Wait,
	}
end

-- Подсказка клавиши на кнопке: только без тач-экрана.
local function detectKeyHint(): string
	if UserInputService.TouchEnabled then
		return ""
	elseif UserInputService.KeyboardEnabled then
		return " [E]"
	elseif UserInputService.GamepadEnabled then
		return " [R2]"
	end
	return ""
end

-- Текущее состояние (для других контроллеров и тестов).
function FishingController.GetPhase(): string
	return phase
end

function FishingController:Start(hud: ScreenGui)
	ui = collectUi(hud)
	defaults = readDefaults()
	keyHint = detectKeyHint()

	ui.actionButton.Visible = false
	ui.stopButton.Visible = false
	ui.biteAlert.Visible = false
	ui.minigame.Visible = false
	ui.card.Visible = false
	ui.hint.Visible = false

	ui.actionButton.Activated:Connect(doAction)
	ui.stopButton.Activated:Connect(requestStop)
	ui.card.Activated:Connect(closeCard)
	Net.Event("FishingState").OnClientEvent:Connect(onFishingState)

	-- Подстраховка: сервер закончил рыбалку, а ответ потерялся — не держим старое состояние.
	player:GetAttributeChangedSignal("FishingState"):Connect(function()
		local state = player:GetAttribute("FishingState")
		if (state == nil or state == "Idle") and isLineOut() then
			endSession()
		end
	end)
	player:GetAttributeChangedSignal("FishCaught"):Connect(function()
		updateCounter(number(player:GetAttribute("FishCaught"), 0))
	end)
	updateCounter(number(player:GetAttribute("FishCaught"), 0))

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(onCharacterRemoving)
	if player.Character then
		onCharacterAdded(player.Character)
	end
	refreshButtons()
end

return FishingController
