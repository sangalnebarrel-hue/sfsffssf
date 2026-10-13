--!strict
--[[
	FishingFxController — рыбалка в мире, для ВСЕХ игроков (и для себя), только на клиенте.

	Поплавки и лески. Клиент следит за атрибутами каждого игрока (их ставит FishingService):
	FishingState, BobberTarget, CastTime, RodId. Когда FishingState уходит из "Idle", клиент
	клонирует поплавок его удочки (ReplicatedStorage.Assets.Bobbers.<RodId>) в папку
	Workspace.FishingFx и натягивает леску (Beam) от кончика удочки (Handle.TipAttachment удочки
	в руке персонажа) до поплавка (Root.LineAttachment).
	  • Полёт: дугой от кончика удочки к BobberTarget (+ FloatDepth вверх — тогда ватерлиния
	    поплавка как раз на воде) за FishingConfig.CastFlightTime. Время — от CastTime по
	    workspace:GetServerTimeNow(), поэтому у всех клиентов поплавок летит одинаково.
	  • "Waiting" — мягко покачивается на воде; "Bite" — резко ныряет, брызги (ParticleEmitter)
	    и «!» над поплавком; "Reeling" — мечется из стороны в сторону и медленно подтягивается
	    к рыбаку; снова "Idle" — быстро сматывается к удочке и исчезает вместе с леской.
	Каждый кадр обновляются только поплавки, которые сейчас в воде или сматываются.

	Радужные рыбы: модели с тегом "RainbowFish" (CollectionService). Детали с атрибутами
	RainbowU / RainbowV переливаются: Color3.fromHSV((U·0.85 + t·0.35) % 1, 0.72, 0.55 + 0.45·V),
	около 20 раз в секунду — пока модель в DataModel и видна: в мире или в своём интерфейсе
	(ViewportFrame карточки улова). Шаблоны в ReplicatedStorage не трогаем.

	Вышедший игрок убирается целиком (его поплавок, леска и подписки на атрибуты).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local FishingConfig = require(Config:WaitForChild("FishingConfig"))
local MapConfig = require(Config:WaitForChild("MapConfig"))
local RodConfig = require(Config:WaitForChild("RodConfig"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))

local FOLDER_NAME = "FishingFx"
local RAINBOW_TAG = "RainbowFish"
local RAINBOW_RATE = 20 -- перекрасок в секунду
local RETRACT_TIME = 0.45 -- поплавок сматывается к удочке, с
local DEFAULT_FLOAT_DEPTH = 0.6

local FX = {
	BobAmplitude = 0.12, -- покачивание на воде, studs
	BobSpeed = 2.4,
	BiteDip = 0.55, -- насколько ныряет при поклёвке
	BiteSpeed = 9,
	BiteSplashEvery = 0.4, -- с
	ReelSwing = 0.9, -- метания при вытаскивании, studs
	ReelSpeed = 7.5,
	ReelPull = 0.05, -- доля пути к рыбаку за секунду
	ReelPullMax = 0.5,
	ReelSplashEvery = 0.3,
	LineColor = Color3.fromRGB(245, 245, 235),
	AlertColor = Color3.fromRGB(255, 170, 40),
	SplashColor = Color3.fromRGB(230, 246, 255),
}

type Bobber = {
	player: Player,
	trove: Trove.Trove,
	model: Model,
	root: BasePart,
	beam: Beam,
	splash: ParticleEmitter,
	alert: BillboardGui,
	floatDepth: number,
	state: string, -- FishingState игрока ("Waiting" | "Bite" | "Reeling")
	stateSince: number, -- os.clock() смены состояния
	target: Vector3, -- точка привязки лески на воде (BobberTarget + FloatDepth)
	castTime: number,
	position: Vector3, -- где поплавок сейчас
	landed: boolean,
	nextSplash: number,
	retractFrom: Vector3?, -- сматывается отсюда (после "Idle")
	retractStart: number,
	tip: Attachment?,
	nextTipSearch: number,
	seed: number, -- своя фаза покачивания
}

type Tracker = { trove: Trove.Trove, bobber: Bobber? }

type RainbowModel = { parts: { BasePart }, u: { number }, v: { number } }

local FishingFxController = {}

local folder: Folder? = nil
local bobbersFolder: Instance? = nil
local trackers: { [Player]: Tracker } = {}
local active: { [Bobber]: true } = {}
local frameConnection: RBXScriptConnection? = nil
local rainbow: { [Instance]: RainbowModel } = {}
local playerGui: PlayerGui? = nil

--------------------------------------------------------------------------------
-- Помощники
--------------------------------------------------------------------------------

local function finite(value: any): number?
	if typeof(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
	return nil
end

-- Всплеск брызг. pcall: в эмуляторе тестов (RbxSim) у ParticleEmitter нет метода Emit.
local function burst(emitter: ParticleEmitter, count: number)
	pcall(function()
		emitter:Emit(count)
	end)
end

-- Кончик удочки в руке персонажа (Tool с атрибутом RodId: сначала та, что в RodId игрока).
local function findTip(player: Player): Attachment?
	local character = player.Character
	if not character then
		return nil
	end
	local wanted = player:GetAttribute("RodId")
	local found: Attachment? = nil
	for _, item in character:GetChildren() do
		local rodId = item:GetAttribute("RodId")
		if item:IsA("Tool") and typeof(rodId) == "string" then
			local handle = item:FindFirstChild("Handle")
			local tip = handle and handle:FindFirstChild("TipAttachment")
			if tip and tip:IsA("Attachment") then
				found = tip
				if rodId == wanted then
					break
				end
			end
		end
	end
	return found
end

-- Кончик удочки, найденный заново, если удочку убрали/сменили (не чаще 4 раз в секунду).
local function resolveTip(bobber: Bobber, now: number): Attachment?
	local tip = bobber.tip
	local character = bobber.player.Character
	if tip and character and tip:IsDescendantOf(character) then
		return tip
	end
	if now >= bobber.nextTipSearch then
		bobber.nextTipSearch = now + 0.25
		tip = findTip(bobber.player)
		bobber.tip = tip
		-- Без кончика леска просто выключается (Enabled = tip ~= nil в stepBobber); старую
		-- Attachment0 не стираем.
		if tip then
			bobber.beam.Attachment0 = tip
		end
	end
	return bobber.tip
end

-- Откуда летит / куда сматывается поплавок: кончик удочки, без удочки — над головой.
local function anchorPosition(bobber: Bobber, tip: Attachment?): Vector3
	if tip then
		return tip.WorldPosition
	end
	local character = bobber.player.Character
	local head = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if head and head:IsA("BasePart") then
		return head.Position + Vector3.new(0, 1.5, 0)
	end
	return bobber.position
end

-- Куда упадёт поплавок, если сервер не прислал BobberTarget: прямо перед рыбаком на воде.
local function fallbackTarget(player: Player): Vector3
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return Vector3.new(0, MapConfig.WaterTop, 0)
	end
	local rodId = player:GetAttribute("RodId")
	local distance = RodConfig.Rods[1].CastDistance
	for _, rod in RodConfig.Rods do
		if rod.Id == rodId then
			distance = rod.CastDistance
		end
	end
	local ahead = root.Position + root.CFrame.LookVector * distance
	return Vector3.new(ahead.X, MapConfig.WaterTop, ahead.Z)
end

-- Цель заброса (точка привязки лески: ватерлиния поплавка на воде) и время заброса.
local function readCast(bobber: Bobber)
	local player = bobber.player
	local target = player:GetAttribute("BobberTarget")
	local water = if typeof(target) == "Vector3" then target else fallbackTarget(player)
	bobber.target = water + Vector3.new(0, bobber.floatDepth, 0)
	bobber.castTime = finite(player:GetAttribute("CastTime")) or Workspace:GetServerTimeNow()
end

--------------------------------------------------------------------------------
-- Создание поплавка
--------------------------------------------------------------------------------

local function makeSplash(root: BasePart): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Splash"
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Lifetime = NumberRange.new(0.35, 0.6)
	emitter.Speed = NumberRange.new(6, 11)
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.Acceleration = Vector3.new(0, -40, 0)
	emitter.Size = NumberSequence.new(0.35, 0.05)
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Color = ColorSequence.new(FX.SplashColor)
	-- Встроенная текстура дыма читается как брызги (по умолчанию — искорки).
	emitter.Texture = "rbxasset://textures/particles/smoke_main.dds"
	emitter.LightEmission = 0.3
	emitter.Parent = root
	return emitter
end

-- «!» над поплавком во время поклёвки.
local function makeAlert(root: BasePart): BillboardGui
	local alert = Instance.new("BillboardGui")
	alert.Name = "BiteAlert"
	alert.Adornee = root
	alert.AlwaysOnTop = true
	alert.LightInfluence = 0
	alert.Size = UDim2.fromScale(1.6, 1.6)
	alert.StudsOffset = Vector3.new(0, 2.4, 0)
	alert.Enabled = false
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = "!"
	label.TextScaled = true
	label.FontFace = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold)
	label.TextColor3 = FX.AlertColor
	label.TextStrokeTransparency = 0
	label.Parent = alert
	alert.Parent = root
	return alert
end

local function makeLine(model: Model, lineAttachment: Attachment): Beam
	local beam = Instance.new("Beam")
	beam.Name = "Line"
	beam.Attachment1 = lineAttachment
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = 0.05
	beam.Width1 = 0.05
	beam.Color = ColorSequence.new(FX.LineColor)
	beam.Transparency = NumberSequence.new(0.15)
	beam.Enabled = false -- пока не найден кончик удочки
	beam.Parent = model
	return beam
end

local function bobberTemplate(rodId: any): Model?
	local source = bobbersFolder
	if not source then
		return nil
	end
	local template = (typeof(rodId) == "string" and source:FindFirstChild(rodId))
		or source:FindFirstChild(RodConfig.StartRod)
	return if template and template:IsA("Model") then template else nil
end

local function createBobber(player: Player): Bobber?
	local template = bobberTemplate(player:GetAttribute("RodId"))
	local parent = folder
	if not template or not parent then
		return nil
	end
	local trove = Trove.new()
	local model = trove:Add(template:Clone())
	model.Name = `Bobber_{player.UserId}`
	local root = model.PrimaryPart
	local lineAttachment = root and root:FindFirstChild("LineAttachment")
	if not root or not lineAttachment or not lineAttachment:IsA("Attachment") then
		trove:Clean()
		return nil
	end
	local now = os.clock()
	local bobber: Bobber = {
		player = player,
		trove = trove,
		model = model,
		root = root,
		beam = makeLine(model, lineAttachment),
		splash = makeSplash(root),
		alert = makeAlert(root),
		floatDepth = finite(model:GetAttribute("FloatDepth")) or DEFAULT_FLOAT_DEPTH,
		state = "Waiting",
		stateSince = now,
		target = Vector3.zero,
		castTime = 0,
		position = Vector3.zero,
		landed = false,
		nextSplash = 0,
		retractFrom = nil,
		retractStart = 0,
		tip = nil,
		nextTipSearch = 0,
		seed = (player.UserId % 97) * 0.37,
	}
	readCast(bobber)
	bobber.position = anchorPosition(bobber, resolveTip(bobber, now))
	model:PivotTo(CFrame.new(bobber.position))
	model.Parent = parent
	return bobber
end

--------------------------------------------------------------------------------
-- Движение поплавка (каждый кадр, только активные)
--------------------------------------------------------------------------------

-- Полёт дугой; nil — уже долетел.
local function flightPosition(bobber: Bobber, from: Vector3): Vector3?
	local alpha = (Workspace:GetServerTimeNow() - bobber.castTime) / FishingConfig.CastFlightTime
	if alpha >= 1 then
		return nil
	end
	alpha = math.max(alpha, 0)
	local height = math.clamp((bobber.target - from).Magnitude * 0.3, 2, 10)
	return from:Lerp(bobber.target, alpha) + Vector3.new(0, height * 4 * alpha * (1 - alpha), 0)
end

-- На воде: покачивание, поклёвка или вытаскивание. Возвращает позицию и наклон.
local function waterPose(bobber: Bobber, from: Vector3, now: number): (Vector3, CFrame)
	local t = now + bobber.seed
	local target = bobber.target
	if bobber.state == "Bite" then
		local dip = math.abs(math.sin(t * FX.BiteSpeed)) ^ 6 -- резкие рывки вниз
		local jitter = math.sin(t * 23) * 0.12
		return target - Vector3.new(jitter, FX.BiteDip * dip + 0.08, 0),
			CFrame.Angles(math.sin(t * 17) * 0.35, 0, math.cos(t * 13) * 0.35)
	elseif bobber.state == "Reeling" then
		local toFisher = Vector3.new(from.X, target.Y, from.Z) - target
		local pull = math.min(FX.ReelPullMax, (now - bobber.stateSince) * FX.ReelPull)
		local side = if toFisher.Magnitude > 0.01 then toFisher.Unit:Cross(Vector3.yAxis) else Vector3.xAxis
		local swing = math.sin(t * FX.ReelSpeed) * FX.ReelSwing
		local dip = math.abs(math.sin(t * 11)) * 0.25
		return target + toFisher * pull + side * swing - Vector3.new(0, dip, 0),
			CFrame.Angles(0, 0, math.sin(t * FX.ReelSpeed) * 0.5)
	end
	local bob = math.sin(t * FX.BobSpeed) * FX.BobAmplitude
	return target + Vector3.new(0, bob, 0), CFrame.Angles(math.sin(t * 1.3) * 0.08, 0, math.cos(t * 1.1) * 0.08)
end

-- Брызги: при приводнении, в начале поклёвки и время от времени во время борьбы.
local function updateSplashes(bobber: Bobber, now: number)
	if not bobber.landed then
		bobber.landed = true
		burst(bobber.splash, 10)
	end
	local every = if bobber.state == "Bite"
		then FX.BiteSplashEvery
		elseif bobber.state == "Reeling" then FX.ReelSplashEvery
		else nil
	if every and now >= bobber.nextSplash then
		bobber.nextSplash = now + every
		burst(bobber.splash, if bobber.state == "Bite" then 8 else 4)
	end
end

local function destroyBobber(tracker: Tracker)
	local bobber = tracker.bobber
	if bobber then
		tracker.bobber = nil
		active[bobber] = nil
		bobber.trove:Clean()
	end
end

local function stepBobber(bobber: Bobber, now: number)
	local tip = resolveTip(bobber, now)
	bobber.beam.Enabled = tip ~= nil
	local from = anchorPosition(bobber, tip)
	local tilt = CFrame.identity

	local retractFrom = bobber.retractFrom
	if retractFrom then
		local alpha = (now - bobber.retractStart) / RETRACT_TIME
		if alpha >= 1 then
			local tracker = trackers[bobber.player]
			if tracker then
				destroyBobber(tracker) -- смотали: поплавок и леска исчезают
			end
			return
		end
		local eased = alpha * alpha
		bobber.position = retractFrom:Lerp(from, eased) + Vector3.new(0, 2 * math.sin(alpha * math.pi), 0)
	else
		local flying = flightPosition(bobber, from)
		if flying then
			bobber.position = flying
		else
			bobber.position, tilt = waterPose(bobber, from, now)
			updateSplashes(bobber, now)
		end
		if bobber.alert.Enabled then
			local size = 1.4 + 0.4 * math.abs(math.sin(now * 8))
			bobber.alert.Size = UDim2.fromScale(size, size)
		end
	end
	bobber.model:PivotTo(CFrame.new(bobber.position) * tilt)
end

local function onFrame()
	local now = os.clock()
	for bobber in active do
		stepBobber(bobber, now)
	end
	if next(active) == nil and frameConnection then
		frameConnection:Disconnect()
		frameConnection = nil
	end
end

local function activate(bobber: Bobber)
	active[bobber] = true
	if not frameConnection then
		frameConnection = RunService.RenderStepped:Connect(onFrame)
	end
end

--------------------------------------------------------------------------------
-- Состояние рыбалки игрока
--------------------------------------------------------------------------------

local function setBobberState(bobber: Bobber, state: string)
	if bobber.state == state then
		return
	end
	bobber.state = state
	bobber.stateSince = os.clock()
	bobber.nextSplash = 0
	bobber.alert.Enabled = state == "Bite"
	bobber.beam.Width0 = if state == "Reeling" then 0.08 else 0.05
	bobber.beam.Width1 = bobber.beam.Width0
	if state == "Bite" then
		burst(bobber.splash, 14)
	end
end

local function startRetract(bobber: Bobber)
	bobber.retractFrom = bobber.position
	bobber.retractStart = os.clock()
	bobber.alert.Enabled = false
end

local function onStateChanged(player: Player, tracker: Tracker)
	local state = player:GetAttribute("FishingState")
	local fishing = state == "Waiting" or state == "Bite" or state == "Reeling"
	local bobber = tracker.bobber
	if fishing then
		if bobber and bobber.retractFrom then
			destroyBobber(tracker) -- новый заброс, пока старый поплавок ещё сматывался
			bobber = nil
		end
		if not bobber then
			bobber = createBobber(player)
			tracker.bobber = bobber
		end
		if bobber then
			setBobberState(bobber, state :: string)
			activate(bobber)
		end
	elseif bobber and not bobber.retractFrom then
		startRetract(bobber)
	end
end

-- Новый заброс без возврата в "Idle" (или атрибуты пришли позже состояния).
local function onCastChanged(tracker: Tracker)
	local bobber = tracker.bobber
	if bobber and not bobber.retractFrom then
		readCast(bobber)
	end
end

local function trackPlayer(player: Player)
	if trackers[player] then
		return
	end
	local tracker: Tracker = { trove = Trove.new(), bobber = nil }
	trackers[player] = tracker
	tracker.trove:Add(function()
		destroyBobber(tracker)
	end)
	tracker.trove:Connect(player:GetAttributeChangedSignal("FishingState"), function()
		onStateChanged(player, tracker)
	end)
	for _, attribute in { "BobberTarget", "CastTime" } do
		tracker.trove:Connect(player:GetAttributeChangedSignal(attribute), function()
			onCastChanged(tracker)
		end)
	end
	onStateChanged(player, tracker)
end

local function untrackPlayer(player: Player)
	local tracker = trackers[player]
	if tracker then
		trackers[player] = nil
		tracker.trove:Clean()
	end
end

--------------------------------------------------------------------------------
-- Радужные рыбы
--------------------------------------------------------------------------------

local function addRainbow(instance: Instance)
	if rainbow[instance] then
		return
	end
	local entry: RainbowModel = { parts = {}, u = {}, v = {} }
	for _, item in instance:GetDescendants() do
		local u, v = item:GetAttribute("RainbowU"), item:GetAttribute("RainbowV")
		if item:IsA("BasePart") and typeof(u) == "number" and typeof(v) == "number" then
			table.insert(entry.parts, item)
			table.insert(entry.u, u)
			table.insert(entry.v, v)
		end
	end
	rainbow[instance] = entry
end

local function removeRainbow(instance: Instance)
	rainbow[instance] = nil
end

-- Видна ли модель: в мире или в своём интерфейсе (ViewportFrame карточки улова).
local function isShown(instance: Instance): boolean
	return instance:IsDescendantOf(Workspace) or (playerGui ~= nil and instance:IsDescendantOf(playerGui))
end

local function paintRainbows(t: number)
	for instance, entry in rainbow do
		if isShown(instance) then
			for index, part in entry.parts do
				local hue = (entry.u[index] * 0.85 + t * 0.35) % 1
				part.Color = Color3.fromHSV(hue, 0.72, 0.55 + 0.45 * entry.v[index])
			end
		end
	end
end

local function startRainbows()
	CollectionService:GetInstanceAddedSignal(RAINBOW_TAG):Connect(addRainbow)
	CollectionService:GetInstanceRemovedSignal(RAINBOW_TAG):Connect(removeRainbow)
	for _, instance in CollectionService:GetTagged(RAINBOW_TAG) do
		addRainbow(instance)
	end
	local sincePaint = 0
	RunService.Heartbeat:Connect(function(dt: number)
		sincePaint += dt
		if sincePaint >= 1 / RAINBOW_RATE and next(rainbow) ~= nil then
			sincePaint = 0
			paintRainbows(os.clock())
		end
	end)
end

--------------------------------------------------------------------------------
-- API и запуск
--------------------------------------------------------------------------------

-- Поплавок игрока (если леска в воде или сматывается) — для других контроллеров и тестов.
function FishingFxController.GetBobber(player: Player): Model?
	local tracker = trackers[player]
	local bobber = tracker and tracker.bobber
	return bobber and bobber.model
end

function FishingFxController:Start(_hud: ScreenGui)
	local fxFolder = Instance.new("Folder")
	fxFolder.Name = FOLDER_NAME
	fxFolder.Parent = Workspace
	folder = fxFolder
	bobbersFolder = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Bobbers")

	Players.PlayerAdded:Connect(trackPlayer)
	Players.PlayerRemoving:Connect(untrackPlayer)
	for _, player in Players:GetPlayers() do
		trackPlayer(player)
	end
	playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	startRainbows()
end

return FishingFxController
