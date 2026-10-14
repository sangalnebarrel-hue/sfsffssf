--!strict
--[[
	FishingFxController — рыбалка в мире, для ВСЕХ игроков (и для себя), только на клиенте.
	Стиль — tools/builder/gui/STYLE.md §3 «World FX» (цвета — UIConfig, тайминги и лимиты —
	FishingConfig.LeapTime и FishingConfig.Fx).

	Поплавки и лески. Клиент следит за атрибутами каждого игрока (их ставит FishingService):
	FishingState, BobberTarget, CastTime, RodId. Когда FishingState уходит из "Idle", клиент
	клонирует поплавок его удочки (ReplicatedStorage.Assets.Bobbers.<RodId>) в папку
	Workspace.FishingFx и натягивает леску (Beam) от кончика удочки (Handle.TipAttachment удочки
	в руке персонажа) до поплавка (Root.LineAttachment).
	  • Полёт: дугой от кончика удочки к BobberTarget (+ FloatDepth вверх — тогда ватерлиния
	    поплавка как раз на воде) за FishingConfig.CastFlightTime. Время — от CastTime по
	    workspace:GetServerTimeNow(), поэтому у всех клиентов поплавок летит одинаково.
	    За поплавком — искрящийся след (Trail, белый → голубой) и свист; приводнился — брызги
	    и 3 расходящихся круга на воде.
	  • "Waiting" — мягко покачивается на воде, раз в Fx.RippleEvery секунд — круг на воде.
	  • "Bite" — резко ныряет, большие брызги и пачка кругов; над поплавком прыгает и
	    пульсирует «!» (жёлто-оранжевый значок, вокруг кружат звёздочки).
	  • "Reeling" — мечется из стороны в сторону и медленно подтягивается к рыбаку, брызги
	    и круги; леска натянута: пульсирует толщиной и цветом.
	  • снова "Idle" — быстро сматывается к удочке и исчезает вместе с леской.
	Каждый кадр обновляются только поплавки, которые сейчас в воде или сматываются.

	Улов и потеря — атрибут FishFx (формат — шапка RemoteNames; сервер ставит его ДО "Idle",
	поэтому поплавок ещё на воде):
	  • caught — у поплавка всплеск, столб воды и круги, рыба (копия Assets.Fish.<Id>.<мутация>) выпрыгивает
	    из воды и, кувыркаясь, с искрящимся следом цвета редкости летит дугой за LeapTime точно
	    туда, где сервер повесит её над головой рыбака (FishingService.holdFish); поплавок
	    на крючке летит с ней. Долетела — копия исчезает в тот кадр, когда появилась серверная
	    HeldFish (пришла раньше — прячется до конца прыжка; не пришла за Fx.HandoffWait — копия
	    исчезает сама). Над головой — кольцо-вспышка; у редкой рыбы и выше — искры цвета
	    редкости, пока она над головой; легендарная и мифическая — ещё столб света, конфетти
	    и волна по земле вокруг рыбака.
	  • lost — всплеск, столбик воды и круги, и маленькая рыбка, махнув хвостом, уходит под воду прочь
	    от рыбака.

	Бюджет (STYLE.md §4): все детали эффектов только на клиенте (Anchored, без столкновений,
	запросов и теней) и удаляются, когда эффект кончился; не больше Fx.MaxEmitters
	ParticleEmitter'ов на одного рыбака (лишний уступает место: сначала искры над рыбой, потом
	конфетти); дальше Fx.Range studs от своего персонажа — ничего, кроме столба света.
	Покадрово (одно соединение RenderStepped на всё, отключается, когда ничего не идёт) —
	поплавки, прыжки, ныряния и столбы света; круги, искры и конфетти — TweenService,
	task.delay и ParticleEmitter, без соединений.

	Радужные рыбы: модели с тегом "RainbowFish" (CollectionService). Детали с атрибутами
	RainbowU / RainbowV переливаются: Color3.fromHSV((U·0.85 + t·0.35) % 1, 0.72, 0.55 + 0.45·V),
	около 20 раз в секунду — пока модель в DataModel и видна: в мире (в том числе рыба
	в прыжке) или в своём интерфейсе (ViewportFrame карточки улова). Шаблоны в
	ReplicatedStorage не трогаем.

	Вышедший игрок убирается целиком (его поплавок, леска, все эффекты и подписки).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local FishingConfig = require(Config:WaitForChild("FishingConfig"))
local MapConfig = require(Config:WaitForChild("MapConfig"))
local RodConfig = require(Config:WaitForChild("RodConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))

local FOLDER_NAME = "FishingFx"
local RAINBOW_TAG = "RainbowFish"
local RAINBOW_RATE = 20 -- перекрасок в секунду
local RETRACT_TIME = 0.45 -- поплавок сматывается к удочке, с
local DEFAULT_FLOAT_DEPTH = 0.6
local FALLBACK_FISH = "Crucian" -- рыба ушла до подсечки (вид неизвестен) — уплывает карасик
local PILLAR_CORE = 1.2 -- толщина белой сердцевины столба света, studs
local PILLAR_GLOW = 3.6 -- … и цветного свечения вокруг неё
local FEET = 3 -- от центра HumanoidRootPart до земли под ногами (если луч вниз ничего не нашёл), studs

local Fx = FishingConfig.Fx
local Palette = UIConfig.Palette
local WHITE = Color3.new(1, 1, 1)
local WATER = Palette.Sky.Top -- голубой «водный» цвет брызг и кругов
local SUN_TOP = Palette.Sun.Top
local SUN_BOTTOM = Palette.Sun.Bottom
local INK = UIConfig.Ink
local FONT = Font.new("rbxasset://fonts/families/Nunito.json", Enum.FontWeight.ExtraBold)

-- Встроенные текстуры и звуки клиента (загружать ничего не нужно; нет файла — тишина).
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SPLASH_TEXTURE = "rbxasset://textures/particles/smoke_main.dds" -- читается как брызги
local SOUND_WHOOSH = "rbxasset://sounds/swoosh.wav"
local SOUND_SPLASH = "rbxasset://sounds/impact_water.mp3"
local SOUND_PING = "rbxasset://sounds/electronicpingshort.wav"

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
	LineColor = Color3.fromRGB(245, 245, 235),
	LineWidth = 0.05,
	-- Круги чуть выше воды (над её мелкими волнами) и земли; толщина колец — от 0,4 stud: вода
	-- видна с пирса под острым углом, тоньше на телефоне не разглядеть.
	RingLift = 0.15,
	RingPixels = 24, -- пикселей SurfaceGui на stud (толщина кругов — в пикселях)
	AlertLift = 2.4, -- «!» над поплавком, studs
	AlertStuds = 1, -- размер «!»: studs + пиксели (не теряется вдали и на телефоне)
	AlertPixels = 40,
	AlertStars = 5,
}

type RingLook = {
	from: number, -- диаметр в начале, studs
	to: number, -- диаметр в конце
	time: number, -- с
	color: Color3, -- внешнее кольцо
	inner: Color3, -- внутреннее, тоньше
	width: number, -- толщина внешнего кольца в начале, studs
	foam: boolean?, -- белый «пятак» пены в середине первого кольца
}

local RING: { [string]: RingLook } = {
	ripple = { from = 1.2, to = 6.5, time = 1.5, color = WHITE, inner = WATER, width = 0.38 },
	landing = { from = 1.4, to = 8, time = 1.1, color = WHITE, inner = WATER, width = 0.5, foam = true },
	bite = { from = 1.6, to = 10, time = 0.95, color = WHITE, inner = SUN_TOP, width = 0.6, foam = true },
	reel = { from = 1.2, to = 5.5, time = 0.8, color = WHITE, inner = WATER, width = 0.42 },
	lost = { from = 1.4, to = 7.5, time = 1, color = WHITE, inner = WATER, width = 0.5, foam = true },
}

type Alert = {
	gui: BillboardGui,
	glow: Frame,
	badge: Frame,
	label: TextLabel,
	stars: { TextLabel },
}

type Bobber = {
	player: Player,
	trove: Trove.Trove,
	model: Model,
	root: BasePart,
	beam: Beam,
	splash: ParticleEmitter,
	trails: { Trail },
	whoosh: Sound,
	splashSound: Sound,
	pingSound: Sound,
	alert: Alert,
	floatDepth: number,
	state: string, -- FishingState игрока ("Waiting" | "Bite" | "Reeling")
	stateSince: number, -- os.clock() смены состояния
	target: Vector3, -- точка привязки лески на воде (BobberTarget + FloatDepth)
	castTime: number,
	position: Vector3, -- где поплавок сейчас
	landed: boolean,
	fresh: boolean, -- создан, пока летел (заброс видели — приводнение с брызгами)
	nextSplash: number,
	nextRipple: number,
	retractFrom: Vector3?, -- сматывается отсюда (после "Idle")
	retractStart: number,
	hooked: Effect?, -- на крючке рыба в прыжке: поплавок летит вместе с ней
	tip: Attachment?,
	nextTipSearch: number,
	seed: number, -- своя фаза покачивания
}

-- Эффект в мире: его детали (instances) удаляются, когда он кончился — сам (по таймеру или
-- step вернул false), вместе с поплавком (owner) или с уходом игрока.
type Effect = {
	tracker: Tracker,
	owner: Bobber?,
	instances: { Instance },
	emitter: ParticleEmitter?, -- считается в Fx.MaxEmitters рыбака
	priority: number, -- нужно место под новый ParticleEmitter — первым уходит меньший
	thread: thread?,
	step: ((now: number) -> boolean)?, -- покадровый эффект: false — кончился
	onEnd: (() -> ())?,
	done: boolean,
}

type Tracker = {
	player: Player,
	trove: Trove.Trove,
	bobber: Bobber?,
	effects: { [Effect]: true },
	fxEvent: any, -- последнее увиденное значение FishFx
}

type FxEvent = { kind: string, id: string?, mutation: string?, rarity: string }

type RainbowModel = { parts: { BasePart }, u: { number }, v: { number } }

local FishingFxController = {}

local folder: Folder? = nil
local bobbersFolder: Instance? = nil
local fishFolder: Instance? = nil
local trackers: { [Player]: Tracker } = {}
local active: { [Bobber]: true } = {}
local frameEffects: { [Effect]: true } = {}
local frameConnection: RBXScriptConnection? = nil
local rainbow: { [Instance]: RainbowModel } = {}
local playerGui: PlayerGui? = nil
local rng = Random.new()

--------------------------------------------------------------------------------
-- Помощники
--------------------------------------------------------------------------------

local function finite(value: any): number?
	if typeof(value) == "number" and value == value and math.abs(value) ~= math.huge then
		return value
	end
	return nil
end

-- Отменяет ожидающий поток (кроме того, что выполняется сейчас).
local function cancelThread(thread: thread?)
	if thread and thread ~= coroutine.running() and coroutine.status(thread) == "suspended" then
		task.cancel(thread)
	end
end

-- Всплеск частиц. pcall: в эмуляторе тестов (RbxSim) у ParticleEmitter нет метода Emit.
local function burst(emitter: ParticleEmitter, count: number)
	pcall(function()
		emitter:Emit(count)
	end)
end

local function tween(instance: Instance, info: TweenInfo, goal: { [string]: any })
	TweenService:Create(instance, info, goal):Play()
end

local function numbers(points: { { number } }): NumberSequence
	local keys = {}
	for _, point in points do
		table.insert(keys, NumberSequenceKeypoint.new(point[1], point[2]))
	end
	return NumberSequence.new(keys)
end

-- Плавный градиент по списку цветов.
local function gradient(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for index, color in colors do
		table.insert(keys, ColorSequenceKeypoint.new((index - 1) / (#colors - 1), color))
	end
	return ColorSequence.new(keys)
end

-- Цвет полосами (конфетти): частицы с разным временем жизни в один момент разного цвета.
local function stripes(colors: { Color3 }): ColorSequence
	local count = math.min(#colors, 10) -- в ColorSequence не больше 20 точек
	local keys = {}
	for index = 1, count do
		local color = colors[index]
		table.insert(keys, ColorSequenceKeypoint.new((index - 1) / count, color))
		table.insert(keys, ColorSequenceKeypoint.new(if index == count then 1 else index / count - 0.001, color))
	end
	return ColorSequence.new(keys)
end

-- Цвета следа, искр и колец рыбы этой редкости (обычная — белый с голубым, мифическая — радуга).
local function rarityColors(rarity: string): { Color3 }
	local style = UIConfig.Rarity[rarity]
	if not style or rarity == "Common" then
		return { WHITE, WATER }
	elseif style.Rainbow then
		return UIConfig.Rainbow
	end
	return { WHITE, style.Top, style.Bottom }
end

-- Деталь эффекта: закреплена, без столкновений, запросов и теней.
local function quietPart(name: string, size: Vector3, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Size = size
	part.CFrame = cframe
	return part
end

local function makeSound(parent: Instance, name: string, id: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = id
	sound.Volume = volume
	sound.RollOffMinDistance = 10
	sound.RollOffMaxDistance = 140
	sound.Parent = parent
	return sound
end

local function play(sound: Sound, speed: number?)
	sound.PlaybackSpeed = speed or rng:NextNumber(0.92, 1.1)
	pcall(function()
		sound:Play()
	end)
end

-- Где смотрит этот игрок: его персонаж (без персонажа — камера).
local function viewerPosition(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root.Position
	end
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame.Position else nil
end

-- Видно ли отсюда эффект в точке position (дальше Fx.Range — не рисуем).
local function isNear(position: Vector3): boolean
	local viewer = viewerPosition()
	return viewer == nil or (viewer - position).Magnitude <= Fx.Range
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

--------------------------------------------------------------------------------
-- Эффекты: учёт, покадровый цикл, лимит ParticleEmitter'ов
--------------------------------------------------------------------------------

local function endEffect(effect: Effect)
	if effect.done then
		return
	end
	effect.done = true
	effect.tracker.effects[effect] = nil
	frameEffects[effect] = nil
	cancelThread(effect.thread)
	effect.thread = nil
	local onEnd = effect.onEnd
	effect.onEnd = nil
	if onEnd then
		onEnd()
	end
	for _, instance in effect.instances do
		instance:Destroy()
	end
	table.clear(effect.instances)
	effect.emitter = nil
end

-- Новый эффект рыбака; life — через сколько секунд он кончится сам (nil — решит step).
local function newEffect(tracker: Tracker, life: number?, owner: Bobber?): Effect
	local effect: Effect = {
		tracker = tracker,
		owner = owner,
		instances = {},
		emitter = nil,
		priority = 0,
		thread = nil,
		step = nil,
		onEnd = nil,
		done = false,
	}
	tracker.effects[effect] = true
	if life then
		effect.thread = task.delay(life, function()
			effect.thread = nil
			endEffect(effect)
		end)
	end
	return effect
end

local stepBobber: (bobber: Bobber, now: number) -> ()

local function onFrame()
	local now = os.clock()
	for bobber in active do
		stepBobber(bobber, now)
	end
	-- Копия: шаг может закончить эффект или начать новый.
	for effect in table.clone(frameEffects) do
		local step = effect.step
		if not effect.done and step then
			local ok, alive = pcall(step, now)
			if not ok then
				warn("[FishingFxController] эффект упал:", alive)
			end
			if not ok or not alive then
				endEffect(effect)
			end
		end
	end
	if next(active) == nil and next(frameEffects) == nil and frameConnection then
		frameConnection:Disconnect()
		frameConnection = nil
	end
end

local function ensureFrame()
	if not frameConnection then
		frameConnection = RunService.RenderStepped:Connect(onFrame)
	end
end

-- Эффект, который обновляется каждый кадр, пока step возвращает true.
local function runEveryFrame(effect: Effect, step: (now: number) -> boolean)
	effect.step = step
	frameEffects[effect] = true
	ensureFrame()
end

-- Сколько ParticleEmitter'ов рыбака сейчас в мире (у поплавка — один, «Splash»).
local function emitterCount(tracker: Tracker): number
	local count = if tracker.bobber then 1 else 0
	for effect in tracker.effects do
		if effect.emitter then
			count += 1
		end
	end
	return count
end

-- Освобождает место под extra новых ParticleEmitter'ов (не больше Fx.MaxEmitters на рыбака):
-- кончаются эффекты с меньшим priority (искры над рыбой, потом конфетти).
local function makeRoom(tracker: Tracker, extra: number)
	while emitterCount(tracker) + extra > Fx.MaxEmitters do
		local weakest: Effect? = nil
		for effect in tracker.effects do
			if effect.emitter and (weakest == nil or effect.priority < weakest.priority) then
				weakest = effect
			end
		end
		if not weakest then
			return
		end
		endEffect(weakest)
	end
end

--------------------------------------------------------------------------------
-- Круги на воде (плоская невидимая деталь + SurfaceGui с кольцами из UIStroke)
--------------------------------------------------------------------------------

local function roundFrame(parent: Instance, name: string, scale: number, color: Color3, transparency: number): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(scale, scale)
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

local function ringStroke(frame: Frame, color: Color3, thickness: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	return stroke
end

-- Одно расходящееся кольцо (внешнее белое + внутреннее цветное), гаснет за look.time.
local function spawnRing(effect: Effect, position: Vector3, look: RingLook, foam: boolean)
	local parent = folder
	if not parent then
		return
	end
	local part = quietPart("Ripple", Vector3.new(look.from, 0.05, look.from), CFrame.new(position))
	part.Transparency = 1
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Ring"
	gui.Face = Enum.NormalId.Top
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = FX.RingPixels
	gui.MaxDistance = Fx.Range
	gui.Parent = part
	local outer = ringStroke(roundFrame(gui, "Outer", 0.92, look.color, 1), look.color, look.width * FX.RingPixels)
	local inner = ringStroke(roundFrame(gui, "Inner", 0.8, look.inner, 1), look.inner, look.width * 0.6 * FX.RingPixels)
	local foamDisc = if foam then roundFrame(gui, "Foam", 0.7, WHITE, 0.45) else nil
	part.Parent = parent
	table.insert(effect.instances, part)

	local grow = TweenInfo.new(look.time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fade = TweenInfo.new(look.time, Enum.EasingStyle.Sine, Enum.EasingDirection.In)
	tween(part, grow, { Size = Vector3.new(look.to, 0.05, look.to) })
	tween(outer, fade, { Transparency = 1, Thickness = outer.Thickness * 0.4 })
	tween(inner, fade, { Transparency = 1, Thickness = inner.Thickness * 0.4 })
	if foamDisc then
		tween(
			foamDisc,
			TweenInfo.new(look.time * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1, Size = UDim2.fromScale(0.5, 0.5) }
		)
	end
end

-- Столб воды (белый цилиндр) там, где рыба выходит из воды или ныряет: вырастает на height
-- studs, расширяется и тает за time секунд. Деталь, без частиц — виден и издалека.
local function spout(tracker: Tracker, water: Vector3, height: number, time: number)
	local parent = folder
	if not parent then
		return
	end
	local upright = CFrame.Angles(0, 0, math.pi / 2) -- ось цилиндра (X) — вертикально
	local part = quietPart("Spout", Vector3.new(0.4, 1.4, 1.4), CFrame.new(water) * upright)
	part.Shape = Enum.PartType.Cylinder
	part.Material = Enum.Material.SmoothPlastic
	part.Color = WHITE
	part.Transparency = 0.15
	part.Parent = parent
	local effect = newEffect(tracker, time)
	table.insert(effect.instances, part)
	local rise = TweenInfo.new(time * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	tween(part, rise, {
		Size = Vector3.new(height, 2, 2),
		CFrame = CFrame.new(water + Vector3.new(0, height / 2, 0)) * upright,
	})
	tween(part, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 1,
	})
end

-- Пачка из count колец с паузой gap (каждое следующее чуть меньше), начиная через delay
-- секунд; owner — поплавок, с которым кольца исчезают.
local function ringBurst(
	tracker: Tracker,
	owner: Bobber?,
	position: Vector3,
	look: RingLook,
	count: number,
	gap: number,
	delay: number?
)
	local effect = newEffect(tracker, nil, owner)
	effect.thread = task.spawn(function()
		if delay then
			task.wait(delay)
		end
		for index = 1, count do
			local shrink = 1 - 0.14 * (index - 1)
			local ring = table.clone(look)
			ring.to = look.to * shrink
			spawnRing(effect, position, ring, look.foam == true and index == 1)
			if index < count then
				task.wait(gap)
			end
		end
		task.wait(look.time)
		effect.thread = nil
		endEffect(effect)
	end)
end

-- Круги поплавка быстро гаснут (леску сматывают).
local function fadeOwned(tracker: Tracker, bobber: Bobber)
	local info = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for effect in tracker.effects do
		if effect.owner == bobber then
			for _, instance in effect.instances do
				for _, item in instance:GetDescendants() do
					if item:IsA("UIStroke") then
						tween(item, info, { Transparency = 1 })
					elseif item:IsA("Frame") then
						tween(item, info, { BackgroundTransparency = 1 })
					end
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Кончик удочки и цель заброса
--------------------------------------------------------------------------------

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

-- Точка на воде под поплавком (центр кругов и всплесков).
local function waterUnder(bobber: Bobber, position: Vector3?): Vector3
	local at = position or bobber.position
	return Vector3.new(at.X, bobber.target.Y - bobber.floatDepth, at.Z)
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
	emitter.Lifetime = NumberRange.new(0.45, 0.8)
	emitter.Speed = NumberRange.new(7, 13)
	emitter.SpreadAngle = Vector2.new(38, 38)
	emitter.Acceleration = Vector3.new(0, -42, 0)
	emitter.Drag = 0.6
	emitter.Size = numbers({ { 0, 0.55 }, { 1, 0.12 } })
	emitter.Transparency = numbers({ { 0, 0.05 }, { 0.7, 0.3 }, { 1, 1 } })
	emitter.Color = ColorSequence.new(WHITE, WATER)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-120, 120)
	emitter.Texture = SPLASH_TEXTURE
	emitter.LightEmission = 0.35
	emitter.Parent = root
	return emitter
end

-- Всплеск у поплавка: power — во сколько раз выше обычного бьют брызги (и крупнее капли:
-- поплавок далеко от камеры, мелкие брызги на телефоне не видны).
local function splash(bobber: Bobber, count: number, power: number)
	local size = power ^ 0.9
	bobber.splash.Speed = NumberRange.new(7 * power, 13 * power)
	bobber.splash.Size = numbers({ { 0, 0.55 * size }, { 1, 0.12 * size } })
	burst(bobber.splash, count)
end

-- Два следа на одних точках: мягкая лента и искры поверх (Trail дешевле частиц).
local function makeTrails(part: BasePart, top: Vector3, bottom: Vector3, colors: { Color3 }, prefix: string): { Trail }
	local a0 = Instance.new("Attachment")
	a0.Name = `{prefix}TrailTop`
	a0.Position = top
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = `{prefix}TrailBottom`
	a1.Position = bottom
	a1.Parent = part
	local trails = {}
	for index, kind in { "Trail", "Sparkle" } do
		local trail = Instance.new("Trail")
		trail.Name = `{prefix}{kind}`
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.FaceCamera = true
		trail.LightInfluence = 0
		trail.MinLength = 0.05
		trail.Color = gradient(colors)
		if index == 1 then
			trail.Lifetime = 0.35
			trail.LightEmission = 0.6
			trail.Transparency = numbers({ { 0, 0.15 }, { 1, 1 } })
			trail.WidthScale = numbers({ { 0, 1 }, { 1, 0.1 } })
		else
			trail.Lifetime = 0.6
			trail.LightEmission = 1
			trail.Brightness = 2
			trail.Texture = SPARKLE_TEXTURE
			trail.TextureMode = Enum.TextureMode.Wrap
			trail.TextureLength = 1.4
			trail.Transparency = numbers({ { 0, 0 }, { 1, 1 } })
			trail.WidthScale = numbers({ { 0, 1.6 }, { 1, 0.4 } })
		end
		trail.Parent = part
		table.insert(trails, trail)
	end
	return trails
end

local function setTrails(trails: { Trail }, enabled: boolean)
	for _, trail in trails do
		trail.Enabled = enabled
	end
end

-- «!» над поплавком во время поклёвки: жёлто-оранжевый значок с обводкой, свечение сзади,
-- вокруг кружат звёздочки (движение — animateAlert).
local function makeAlert(root: BasePart): Alert
	local gui = Instance.new("BillboardGui")
	gui.Name = "BiteAlert"
	gui.Adornee = root
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = Fx.Range
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.ClipsDescendants = false
	gui.Size = UDim2.new(FX.AlertStuds, FX.AlertPixels, FX.AlertStuds, FX.AlertPixels)
	gui.StudsOffset = Vector3.new(0, FX.AlertLift, 0)
	gui.Enabled = false

	local glow = roundFrame(gui, "Glow", 1.3, SUN_TOP, 0.5)
	glow.ZIndex = 1
	local badge = roundFrame(gui, "Badge", 0.86, WHITE, 0)
	badge.ZIndex = 2
	local fill = Instance.new("UIGradient")
	fill.Name = "Fill"
	fill.Color = ColorSequence.new(SUN_TOP, SUN_BOTTOM)
	fill.Rotation = 90
	fill.Parent = badge
	local outline = Instance.new("UIStroke")
	outline.Color = INK
	outline.Thickness = 3
	outline.Parent = badge
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.AnchorPoint = Vector2.new(0.5, 0)
	gloss.Position = UDim2.fromScale(0.5, 0.07)
	gloss.Size = UDim2.fromScale(0.62, 0.34)
	gloss.BackgroundColor3 = WHITE
	gloss.BackgroundTransparency = 0.55
	gloss.BorderSizePixel = 0
	gloss.ZIndex = 3
	local glossCorner = Instance.new("UICorner")
	glossCorner.CornerRadius = UDim.new(0.5, 0)
	glossCorner.Parent = gloss
	gloss.Parent = badge

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.52)
	label.Size = UDim2.fromScale(0.78, 0.78)
	label.BackgroundTransparency = 1
	label.Text = "!"
	label.TextScaled = true
	label.FontFace = FONT
	label.TextColor3 = WHITE
	label.TextStrokeColor3 = INK
	label.TextStrokeTransparency = 0
	label.ZIndex = 4
	local textOutline = Instance.new("UIStroke")
	textOutline.Name = "Outline"
	textOutline.Color = INK
	textOutline.Thickness = 2.5
	textOutline.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	textOutline.Parent = label
	label.Parent = gui

	local stars = {}
	for index = 1, FX.AlertStars do
		local star = Instance.new("TextLabel")
		star.Name = `Star{index}`
		star.AnchorPoint = Vector2.new(0.5, 0.5)
		star.Size = UDim2.fromScale(0.3, 0.3)
		star.BackgroundTransparency = 1
		star.Text = if index % 2 == 1 then "⭐" else "✨"
		star.TextScaled = true
		star.TextStrokeTransparency = 1
		star.ZIndex = 5
		star.Parent = gui
		table.insert(stars, star)
	end
	gui.Parent = root
	return { gui = gui, glow = glow, badge = badge, label = label, stars = stars }
end

-- Выскакивание с перелётом (Back Out): 0 → 1 за ALERT_POP секунд.
local ALERT_POP = 0.28
local function backOut(a: number): number
	local c = 1.70158
	local x = a - 1
	return 1 + (c + 1) * x * x * x + c * x * x
end

-- «!» выскакивает, прыгает мячиком, пульсирует жёлтым↔оранжевым, покачивается; звёздочки
-- кружат. age — сколько секунд идёт поклёвка. Частоты ниже 3 Гц (STYLE.md §4: ничего не
-- мигает чаще 3 раз в секунду).
local function animateAlert(alert: Alert, t: number, age: number)
	local pop = backOut(math.clamp(age / ALERT_POP, 0, 1))
	local bounce = math.abs(math.sin(t * 6.5))
	local pulse = 0.5 + 0.5 * math.sin(t * 9)
	-- Отступ UDim — целое число пикселей.
	local pixels = math.round((FX.AlertPixels + 12 * pulse) * pop)
	alert.gui.StudsOffset = Vector3.new(0, FX.AlertLift + 0.8 * bounce, 0)
	alert.gui.Size = UDim2.new(FX.AlertStuds * pop, pixels, FX.AlertStuds * pop, pixels)
	local glow = 1.15 + 0.4 * pulse
	alert.glow.Size = UDim2.fromScale(glow, glow)
	alert.glow.BackgroundTransparency = 0.3 + 0.5 * pulse
	alert.glow.BackgroundColor3 = SUN_TOP:Lerp(SUN_BOTTOM, pulse)
	local tilt = math.sin(t * 11) * 9
	alert.badge.Rotation = tilt
	alert.label.Rotation = tilt
	local count = #alert.stars
	for index, star in alert.stars do
		local angle = t * 2.6 + (index - 1) * 2 * math.pi / count
		star.Position = UDim2.fromScale(0.5 + 0.7 * math.cos(angle), 0.5 + 0.7 * math.sin(angle))
		star.Rotation = math.deg(angle) * 0.5
		local twinkle = 0.22 + 0.1 * math.sin(t * 7 + index * 1.7)
		star.Size = UDim2.fromScale(twinkle, twinkle)
	end
end

local function makeLine(model: Model, lineAttachment: Attachment): Beam
	local beam = Instance.new("Beam")
	beam.Name = "Line"
	beam.Attachment1 = lineAttachment
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Width0 = FX.LineWidth
	beam.Width1 = FX.LineWidth
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

local function createBobber(tracker: Tracker): Bobber?
	local player = tracker.player
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
	makeRoom(tracker, 1) -- у поплавка свой ParticleEmitter (брызги)
	local now = os.clock()
	local bobber: Bobber = {
		player = player,
		trove = trove,
		model = model,
		root = root,
		beam = makeLine(model, lineAttachment),
		splash = makeSplash(root),
		trails = makeTrails(root, Vector3.new(0, 0.3, 0), Vector3.new(0, -0.3, 0), { WHITE, WATER }, "Cast"),
		whoosh = makeSound(root, "Whoosh", SOUND_WHOOSH, 0.35),
		splashSound = makeSound(root, "SplashSound", SOUND_SPLASH, 0.5),
		pingSound = makeSound(root, "Ping", SOUND_PING, 0.35),
		alert = makeAlert(root),
		floatDepth = finite(model:GetAttribute("FloatDepth")) or DEFAULT_FLOAT_DEPTH,
		state = "Waiting",
		stateSince = now,
		target = Vector3.zero,
		castTime = 0,
		position = Vector3.zero,
		landed = false,
		fresh = false,
		nextSplash = 0,
		nextRipple = 0,
		retractFrom = nil,
		retractStart = 0,
		hooked = nil,
		tip = nil,
		nextTipSearch = 0,
		seed = (player.UserId % 97) * 0.37,
	}
	readCast(bobber)
	bobber.position = anchorPosition(bobber, resolveTip(bobber, now))
	-- Заброс видно (поплавок ещё летит): свист и след; иначе он уже на воде — без них.
	bobber.fresh = Workspace:GetServerTimeNow() - bobber.castTime < FishingConfig.CastFlightTime
	setTrails(bobber.trails, false)
	if bobber.fresh and isNear(bobber.position) then
		setTrails(bobber.trails, true)
		play(bobber.whoosh)
	end
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

-- Поплавок на воде: приводнение, круги, брызги (только если это видно отсюда — near).
local function updateWater(bobber: Bobber, now: number, near: boolean)
	local tracker = trackers[bobber.player]
	if not tracker then
		return
	end
	if not bobber.landed then
		bobber.landed = true
		setTrails(bobber.trails, false)
		bobber.nextRipple = now + Fx.RippleEvery
		if bobber.fresh and near then
			splash(bobber, 14, 1)
			play(bobber.splashSound)
			ringBurst(tracker, bobber, waterUnder(bobber) + Vector3.new(0, FX.RingLift, 0), RING.landing, 3, 0.14)
		end
	end
	local state = bobber.state
	local rippleEvery = if state == "Waiting"
		then Fx.RippleEvery
		elseif state == "Reeling" then Fx.ReelRippleEvery
		else nil
	if rippleEvery and now >= bobber.nextRipple then
		bobber.nextRipple = now + rippleEvery
		if near then
			local look = if state == "Reeling" then RING.reel else RING.ripple
			ringBurst(tracker, bobber, waterUnder(bobber) + Vector3.new(0, FX.RingLift, 0), look, 1, 0)
		end
	end
	local splashEvery = if state == "Bite"
		then FX.BiteSplashEvery
		elseif state == "Reeling" then Fx.ReelSprayEvery
		else nil
	if splashEvery and now >= bobber.nextSplash then
		bobber.nextSplash = now + splashEvery
		if near then
			if state == "Bite" then
				splash(bobber, 8, 1)
			else
				splash(bobber, 6, 0.8)
			end
		end
	end
end

-- Леска во время борьбы с рыбой натянута: толщина и цвет (белый ↔ оранжевый) пульсируют.
local function animateLine(bobber: Bobber, t: number)
	local k = 0.5 + 0.5 * math.sin(t * 10)
	local width = FX.LineWidth + 0.03 + 0.05 * k
	bobber.beam.Width0 = width
	bobber.beam.Width1 = width
	bobber.beam.Color = ColorSequence.new(FX.LineColor:Lerp(SUN_BOTTOM, 0.2 + 0.6 * k))
end

local function resetLine(bobber: Bobber)
	bobber.beam.Width0 = FX.LineWidth
	bobber.beam.Width1 = FX.LineWidth
	bobber.beam.Color = ColorSequence.new(FX.LineColor)
	bobber.beam.LightEmission = 0
end

local function destroyBobber(tracker: Tracker)
	local bobber = tracker.bobber
	if bobber then
		tracker.bobber = nil
		active[bobber] = nil
		bobber.hooked = nil
		for effect in table.clone(tracker.effects) do
			if effect.owner == bobber then
				endEffect(effect)
			end
		end
		bobber.trove:Clean()
	end
end

stepBobber = function(bobber: Bobber, now: number)
	local tip = resolveTip(bobber, now)
	bobber.beam.Enabled = tip ~= nil
	if bobber.hooked then
		return -- на крючке рыба в прыжке: поплавок ведёт она (startLeap)
	end
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
		local near = isNear(bobber.position)
		if flying then
			bobber.position = flying
		else
			bobber.position, tilt = waterPose(bobber, from, now)
			updateWater(bobber, now, near)
		end
		-- Далёкие поплавки (дальше Fx.Range) — без анимации «!» и лески: их почти не видно.
		if near and bobber.alert.gui.Enabled then
			animateAlert(bobber.alert, now, now - bobber.stateSince)
		end
		if near and bobber.state == "Reeling" then
			animateLine(bobber, now + bobber.seed)
		end
	end
	bobber.model:PivotTo(CFrame.new(bobber.position) * tilt)
end

local function activate(bobber: Bobber)
	active[bobber] = true
	ensureFrame()
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
	bobber.nextRipple = bobber.stateSince + (if state == "Reeling" then 0.2 else Fx.RippleEvery)
	bobber.alert.gui.Enabled = state == "Bite"
	resetLine(bobber)
	if state == "Reeling" then
		bobber.beam.LightEmission = 0.4
	end
	local tracker = trackers[bobber.player]
	if state == "Bite" and tracker and isNear(bobber.position) then
		splash(bobber, 22, 1.3)
		play(bobber.splashSound, 1.15)
		play(bobber.pingSound)
		ringBurst(
			tracker,
			bobber,
			waterUnder(bobber, bobber.target) + Vector3.new(0, FX.RingLift, 0),
			RING.bite,
			3,
			0.12
		)
	end
end

local function startRetract(tracker: Tracker, bobber: Bobber)
	bobber.retractFrom = bobber.position
	bobber.retractStart = os.clock()
	bobber.alert.gui.Enabled = false
	resetLine(bobber)
	fadeOwned(tracker, bobber)
end

local function onStateChanged(player: Player, tracker: Tracker)
	local state = player:GetAttribute("FishingState")
	local fishing = state == "Waiting" or state == "Bite" or state == "Reeling"
	local bobber = tracker.bobber
	if fishing then
		if bobber and (bobber.retractFrom or bobber.hooked) then
			-- Новый заброс, пока старый поплавок ещё сматывался (или летел с рыбой: прыжок
			-- долетит без него).
			destroyBobber(tracker)
			bobber = nil
		end
		if not bobber then
			bobber = createBobber(tracker)
			tracker.bobber = bobber
		end
		if bobber then
			setBobberState(bobber, state :: string)
			activate(bobber)
		end
	elseif bobber and not bobber.retractFrom and not bobber.hooked then
		startRetract(tracker, bobber)
	end
end

-- Новый заброс без возврата в "Idle" (или атрибуты пришли позже состояния).
local function onCastChanged(tracker: Tracker)
	local bobber = tracker.bobber
	if bobber and not bobber.retractFrom and not bobber.hooked then
		readCast(bobber)
	end
end

--------------------------------------------------------------------------------
-- Улов: прыжок рыбы, искры над головой, столб света, конфетти
--------------------------------------------------------------------------------

local function fishTemplate(id: string?, mutation: string?): Model?
	local source = fishFolder
	local variants = id and source and source:FindFirstChild(id)
	if not variants then
		return nil
	end
	local model = variants:FindFirstChild(mutation or "Normal") or variants:FindFirstChild("Normal")
	return if model and model:IsA("Model") and model.PrimaryPart then model else nil
end

-- Копия модели рыбы для эффекта: закреплена, без столкновений, запросов и теней.
local function cloneFish(template: Model, name: string): Model
	local model = template:Clone()
	model.Name = name
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
	end
	return model
end

-- Где сервер повесит эту рыбу над головой (FishingService.holdFish): центр рамки модели над
-- макушкой с зазором HeldFishGap, оси модели — оси головы. Возвращает положение модели
-- относительно головы, центр рамки относительно pivot модели и размер рамки.
local function heldPlacement(model: Model, head: BasePart): (CFrame, Vector3, Vector3)
	local pivot = model:GetPivot()
	local boxCFrame, boxSize = model:GetBoundingBox()
	local center = pivot:PointToObjectSpace(boxCFrame.Position)
	local lift = head.Size.Y / 2 + FishingConfig.HeldFishGap + boxSize.Y / 2
	return CFrame.new(0, lift, 0) * CFrame.new(-center), center, boxSize
end

-- Точка на воде, откуда выпрыгивает (куда ныряет) рыба: под поплавком, без поплавка — цель
-- заброса.
local function waterOrigin(tracker: Tracker): Vector3?
	local bobber = tracker.bobber
	if bobber then
		return waterUnder(bobber, bobber.retractFrom or bobber.position)
	end
	local target = tracker.player:GetAttribute("BobberTarget")
	return if typeof(target) == "Vector3" then target else nil
end

local function setHidden(model: Model, hidden: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

local function sparkleEmitter(name: string, colors: { Color3 }, rate: number): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = name
	emitter.Rate = rate
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(0.8, 2.4)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Acceleration = Vector3.new(0, 1.5, 0)
	emitter.Size = numbers({ { 0, 0 }, { 0.2, 0.55 }, { 1, 0 } })
	emitter.Transparency = numbers({ { 0, 0.05 }, { 0.75, 0.2 }, { 1, 1 } })
	emitter.Color = gradient(colors)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-200, 200)
	emitter.LightEmission = 1
	emitter.LightInfluence = 0
	emitter.Texture = SPARKLE_TEXTURE
	return emitter
end

-- Искры цвета редкости вокруг рыбы над головой, пока она там (редкая и выше).
local function aura(tracker: Tracker, held: Model, rarity: string)
	local rate = Fx.AuraRate[rarity]
	local body = held.PrimaryPart
	if not rate or not body then
		return
	end
	makeRoom(tracker, 1)
	local effect = newEffect(tracker, FishingConfig.HoldFishTime + 0.3)
	effect.priority = 1
	local emitter = sparkleEmitter("RarityAura", rarityColors(rarity), rate)
	emitter.Parent = body
	burst(emitter, 14)
	effect.emitter = emitter
	table.insert(effect.instances, emitter)
	local style = UIConfig.Rarity[rarity]
	if style then
		local light = Instance.new("PointLight")
		light.Name = "RarityGlow"
		light.Color = style.Top
		light.Range = 9
		light.Brightness = 1.6
		light.Shadows = false
		light.Parent = body
		table.insert(effect.instances, light)
	end
end

-- Столб света над рыбаком (легендарная и мифическая рыба): выстреливает вверх, расширяется
-- и гаснет за Fx.PillarTime. Его видно и издалека — он один на весь эффект и дешёвый.
-- base — низ столба (земля под рыбаком; у самого рыбака — над его рыбой, чтобы не закрыть её).
local function pillar(tracker: Tracker, base: Vector3, rarity: string)
	local parent = folder
	local style = UIConfig.Rarity[rarity]
	if not parent or not style then
		return
	end
	local upright = CFrame.Angles(0, 0, math.pi / 2) -- ось цилиндра (X) — вертикально
	local core = quietPart("PillarCore", Vector3.new(1, PILLAR_CORE, PILLAR_CORE), CFrame.new(base) * upright)
	core.Shape = Enum.PartType.Cylinder
	core.Material = Enum.Material.Neon
	core.Color = WHITE
	local glow = quietPart("PillarGlow", Vector3.new(1, PILLAR_GLOW, PILLAR_GLOW), CFrame.new(base) * upright)
	glow.Shape = Enum.PartType.Cylinder
	glow.Material = Enum.Material.Neon
	glow.Color = style.Top:Lerp(style.Bottom, 0.45)
	glow.Transparency = 0.5
	local effect = newEffect(tracker, nil)
	table.insert(effect.instances, core)
	table.insert(effect.instances, glow)
	local sound = makeSound(core, "Ping", SOUND_PING, 0.6)
	core.Parent = parent
	glow.Parent = parent
	play(sound, 0.75)
	local start = os.clock()
	runEveryFrame(effect, function(now: number): boolean
		local a = (now - start) / Fx.PillarTime
		if a >= 1 then
			return false
		end
		local grow = 1 - (1 - math.min(a / 0.14, 1)) ^ 3
		local height = math.max(Fx.PillarHeight * grow, 0.5)
		local fade = math.clamp((a - 0.3) / 0.7, 0, 1)
		local frame = CFrame.new(base + Vector3.new(0, height / 2, 0)) * upright
		local coreWidth = PILLAR_CORE * (1 - 0.6 * fade)
		local glowWidth = PILLAR_GLOW * (1 + 0.8 * fade)
		core.CFrame = frame
		core.Size = Vector3.new(height, coreWidth, coreWidth)
		core.Transparency = 0.05 + 0.95 * fade ^ 1.5
		glow.CFrame = frame
		glow.Size = Vector3.new(height, glowWidth, glowWidth)
		glow.Transparency = 0.5 + 0.5 * fade
		if style.Rainbow then
			glow.Color = Color3.fromHSV((now * 0.8) % 1, 0.7, 1)
		end
		return true
	end)
end

-- Разноцветные конфетти над рыбаком (одним всплеском одного ParticleEmitter'а).
local function confetti(tracker: Tracker, position: Vector3, rarity: string)
	local parent = folder
	local style = UIConfig.Rarity[rarity]
	if not parent or not style then
		return
	end
	makeRoom(tracker, 1)
	local effect = newEffect(tracker, 2.8)
	effect.priority = 2
	local part = quietPart("Confetti", Vector3.new(1, 1, 1), CFrame.new(position))
	part.Transparency = 1
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Confetti"
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.SpreadAngle = Vector2.new(60, 60)
	emitter.Speed = NumberRange.new(16, 30)
	emitter.Drag = 1.6
	emitter.Acceleration = Vector3.new(0, -26, 0)
	emitter.Lifetime = NumberRange.new(1.4, 2.6)
	emitter.Size = numbers({ { 0, 0.6 }, { 0.8, 0.5 }, { 1, 0.2 } })
	emitter.Transparency = numbers({ { 0, 0 }, { 0.75, 0 }, { 1, 1 } })
	emitter.Squash = numbers({ { 0, 0 }, { 0.25, 1.2 }, { 0.5, -1.2 }, { 0.75, 1.2 }, { 1, 0 } }) -- кружатся
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-420, 420)
	emitter.Color = stripes(style.Confetti)
	emitter.LightEmission = 0.4
	emitter.LightInfluence = 0.3
	emitter.Texture = SPARKLE_TEXTURE
	emitter.Parent = part
	part.Parent = parent
	effect.emitter = emitter
	table.insert(effect.instances, part)
	burst(emitter, Fx.ConfettiCount)
end

-- Земля (настил пирса) под ногами рыбака: луч вниз мимо персонажа и эффектов.
local function groundUnder(character: Model, root: BasePart): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { character }
	if folder then
		table.insert(ignore, folder)
	end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -(FEET + 4), 0), params)
	return if hit then hit.Position else root.Position - Vector3.new(0, FEET, 0)
end

-- Рыба долетела: кольцо-вспышка вокруг неё, искры (редкая и выше), а у легендарной
-- и мифической — столб света (виден всем), конфетти и волна по земле (только вблизи).
local function celebrate(tracker: Tracker, rarity: string, held: Model?, near: boolean)
	if trackers[tracker.player] ~= tracker then
		return -- рыбак ушёл
	end
	local style = UIConfig.Rarity[rarity] or UIConfig.Rarity.Common
	local character = tracker.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local head = character and character:FindFirstChild("Head")
	local colors = rarityColors(rarity)
	if near and held then
		local box = held:GetBoundingBox()
		local halo: RingLook = {
			from = 1.5,
			to = 7,
			time = 0.55,
			color = WHITE,
			inner = colors[#colors],
			width = 0.32,
		}
		ringBurst(tracker, nil, box.Position, halo, 2, 0.1)
		local body = held.PrimaryPart
		if body then
			local chime = newEffect(tracker, 1.5)
			local sound = makeSound(body, "LandPing", SOUND_PING, 0.45)
			table.insert(chime.instances, sound)
			play(sound, if style.Flash then 0.8 else 1.2)
		end
		aura(tracker, held, rarity)
	end
	if style.Flash and character and root and root:IsA("BasePart") then
		local feet = groundUnder(character, root)
		local base = feet
		if held and tracker.player == Players.LocalPlayer then
			-- Своему рыбаку столб не закрывает его самого и рыбу: начинается над рыбой.
			local box, size = held:GetBoundingBox()
			base = box.Position + Vector3.new(0, size.Y / 2 + 0.5, 0)
		end
		pillar(tracker, base, rarity)
		if near then
			-- Волна по земле: два кольца цвета редкости (мифическая — радужные пары).
			local colorPairs = if style.Rainbow
				then { { UIConfig.Rainbow[1], UIConfig.Rainbow[3] }, { UIConfig.Rainbow[5], UIConfig.Rainbow[7] } }
				else { { style.Top, style.Bottom }, { style.Bottom, style.Top } }
			for index, pair in colorPairs do
				local shockwave: RingLook = {
					from = 2,
					to = 24 - 4 * (index - 1),
					time = 0.8,
					color = pair[1],
					inner = pair[2],
					width = 0.6,
					foam = index == 1,
				}
				local delay = if index == 1 then nil else 0.16
				ringBurst(tracker, nil, feet + Vector3.new(0, FX.RingLift, 0), shockwave, 1, 0, delay)
			end
			if head and head:IsA("BasePart") then
				confetti(tracker, head.Position + Vector3.new(0, 2.5, 0), rarity)
			end
		end
	end
end

-- Поймал: рыба выпрыгивает у поплавка и кувыркаясь летит над голову рыбака (см. шапку).
local function startLeap(tracker: Tracker, event: FxEvent)
	local player = tracker.player
	local rarity = event.rarity
	local character = player.Character
	local headInstance = character and character:FindFirstChild("Head")
	local water = waterOrigin(tracker)
	if not character or not headInstance or not headInstance:IsA("BasePart") or not water then
		return
	end
	local head: BasePart = headInstance
	local near = isNear(water) or isNear(head.Position)
	local template = if near then fishTemplate(event.id, event.mutation) else nil
	if not template then
		-- Далеко (или нет модели): без прыжка, а столб света — когда рыба долетела бы.
		local waiting = newEffect(tracker, nil)
		waiting.thread = task.delay(FishingConfig.LeapTime, function()
			waiting.thread = nil
			endEffect(waiting)
			celebrate(tracker, rarity, nil, false)
		end)
		return
	end

	-- Всплеск и круги там, где рыба выходит из воды (поплавок ещё здесь).
	local bobber = tracker.bobber
	local colors = rarityColors(rarity)
	if bobber then
		splash(bobber, 26, 1.6)
		play(bobber.splashSound, 0.9)
	end
	local catchRing = table.clone(RING.landing)
	catchRing.to = 13
	catchRing.width = 0.6
	catchRing.inner = colors[#colors]
	ringBurst(tracker, nil, water + Vector3.new(0, FX.RingLift, 0), catchRing, 3, 0.12)
	spout(tracker, water, 6, 0.55)

	makeRoom(tracker, 1)
	local model = cloneFish(template, "Leap")
	local body = model.PrimaryPart :: BasePart
	local modelInHead, center, size = heldPlacement(model, head)
	local effect = newEffect(tracker, nil)
	effect.priority = 3
	table.insert(effect.instances, model)
	-- След вдоль оси вращения (поперёк рыбы) — лента не перекручивается, пока рыба кувыркается.
	local centerInBody = body.CFrame:PointToObjectSpace(model:GetPivot() * center)
	local half = math.max(size.Z, 1) * 0.5 + 0.2
	makeTrails(body, centerInBody + Vector3.new(0, 0, half), centerInBody - Vector3.new(0, 0, half), colors, "Leap")
	local emitter = sparkleEmitter("LeapSparkles", colors, 40)
	emitter.Parent = body
	effect.emitter = emitter
	local whoosh = makeSound(body, "Whoosh", SOUND_WHOOSH, 0.4)

	-- Дуга: центр рамки рыбы от воды (нос чуть над водой) до места над головой.
	local mouth = center + Vector3.new(size.X / 2, 0, 0) -- голова рыбы (+X модели): тут крючок
	local startCenter = water - Vector3.new(0, size.X * 0.3, 0)
	local firstEnd = (head.CFrame * modelInHead) * center
	local height = math.clamp((firstEnd - startCenter).Magnitude * Fx.LeapHeight, Fx.LeapMinHeight, Fx.LeapMaxHeight)
	-- Кувырки вокруг оси Z модели; в начале нос смотрит вверх (+X → +Y), в конце — как над головой.
	local spin = Fx.LeapSpins * 2 * math.pi + math.pi / 2
	local start = os.clock()
	local oldHeld = character:FindFirstChild("HeldFish")
	local hidden: Model? = nil
	local landedAt: number? = nil

	local function pose(a: number): CFrame
		local endPivot = head.CFrame * modelInHead
		local position = startCenter:Lerp(endPivot * center, a) + Vector3.new(0, height * 4 * a * (1 - a), 0)
		local turn = spin * (1 - a) ^ 2
		return CFrame.new(position) * endPivot.Rotation * CFrame.Angles(0, 0, turn) * CFrame.new(-center)
	end

	-- Поплавок на крючке летит с рыбой; не долетит — сматывается как обычно.
	if bobber then
		bobber.hooked = effect
		bobber.retractFrom = nil
		bobber.alert.gui.Enabled = false
		resetLine(bobber)
		fadeOwned(tracker, bobber)
	end
	effect.onEnd = function()
		local shown = hidden
		if shown then
			setHidden(shown, false)
		end
		if bobber and bobber.hooked == effect and tracker.bobber == bobber then
			destroyBobber(tracker)
		end
	end

	model:PivotTo(pose(0))
	model.Parent = folder
	play(whoosh, 1.15)

	runEveryFrame(effect, function(now: number): boolean
		if not head:IsDescendantOf(Workspace) then
			return false -- рыбак умер или ушёл: прыжок обрывается
		end
		local a = math.min((now - start) / FishingConfig.LeapTime, 1)
		local cframe = pose(a)
		model:PivotTo(cframe)
		if bobber and bobber.hooked == effect then
			bobber.position = cframe * mouth
			bobber.model:PivotTo(CFrame.new(bobber.position))
		end
		local held = character:FindFirstChild("HeldFish")
		local fresh: Model? = if held and held ~= oldHeld and held:IsA("Model") then held else nil
		if a < 1 then
			if fresh and not hidden then
				hidden = fresh -- серверная рыба пришла раньше — прячем до конца прыжка
				setHidden(fresh, true)
			end
			return true
		end
		landedAt = landedAt or now
		if fresh or now - (landedAt :: number) >= Fx.HandoffWait then
			endEffect(effect) -- копия исчезает, серверная рыба (если спрятана) показывается
			celebrate(tracker, rarity, fresh, true)
			return false
		end
		return true
	end)
end

-- Рыба ушла: всплеск, круги и маленькая рыбка, махнув хвостом, ныряет прочь от рыбака.
local function startDive(tracker: Tracker, event: FxEvent)
	local water = waterOrigin(tracker)
	if not water or not isNear(water) then
		return
	end
	local bobber = tracker.bobber
	if bobber then
		splash(bobber, 18, 1.1)
		play(bobber.splashSound, 1.2)
	end
	ringBurst(tracker, nil, water + Vector3.new(0, FX.RingLift, 0), RING.lost, 2, 0.15)
	spout(tracker, water, 3, 0.45)

	local template = fishTemplate(event.id or FALLBACK_FISH, event.mutation) or fishTemplate(FALLBACK_FISH, nil)
	local parent = folder
	if not template or not parent then
		return
	end
	local model = cloneFish(template, "Dive")
	pcall(function()
		model:ScaleTo(Fx.DiveScale)
	end)
	local pivot = model:GetPivot()
	local box = model:GetBoundingBox()
	local center = pivot:PointToObjectSpace(box.Position)
	local character = tracker.player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local away = if root and root:IsA("BasePart") then flat(water - root.Position) else Vector3.xAxis
	away = if away.Magnitude > 0.01 then away.Unit else Vector3.xAxis

	-- Прыжок-дуга: из-под воды на 1,3 stud над ней и вниз, на 4,5 stud под воду.
	local run, rise, sink = 4, 9.7, 13.9
	local effect = newEffect(tracker, nil)
	table.insert(effect.instances, model)
	local start = os.clock()
	local splashed = false
	local function place(a: number)
		local y = -0.4 + rise * a - sink * a * a
		local position = water + away * (run * a) + Vector3.new(0, y, 0)
		local forward = (away * run + Vector3.new(0, rise - 2 * sink * a, 0)).Unit
		local facing = CFrame.lookAt(position, position + forward) * CFrame.Angles(0, math.pi / 2, 0)
		local flick = CFrame.Angles(0, math.sin(a * 6 * math.pi) * 0.45, 0) -- машет хвостом
		model:PivotTo(CFrame.new(position) * facing.Rotation * flick * CFrame.new(-center))
		if not splashed and a > 0.5 and y < 0 then
			splashed = true -- вошла в воду: маленький круг
			local small = table.clone(RING.reel)
			small.to = 3.5
			ringBurst(tracker, nil, Vector3.new(position.X, water.Y + FX.RingLift, position.Z), small, 1, 0)
		end
	end
	place(0)
	model.Parent = parent
	runEveryFrame(effect, function(now: number): boolean
		local a = (now - start) / Fx.DiveTime
		if a >= 1 then
			return false
		end
		place(a)
		return true
	end)
end

-- "<номер>|caught|<FishId>|<Mutation>|<Rarity>" / "<номер>|lost|…" (см. RemoteNames).
local function parseFx(value: any): FxEvent?
	if typeof(value) ~= "string" then
		return nil
	end
	local fields = string.split(value, "|")
	local kind = fields[2]
	if kind ~= "caught" and kind ~= "lost" then
		return nil
	end
	local function field(index: number): string?
		local text = fields[index]
		return if text and text ~= "" then text else nil
	end
	local rarity = field(5)
	return {
		kind = kind,
		id = field(3),
		mutation = field(4),
		rarity = if rarity and UIConfig.Rarity[rarity] then rarity else "Common",
	}
end

local function onFxChanged(tracker: Tracker)
	local value = tracker.player:GetAttribute("FishFx")
	if value == tracker.fxEvent then
		return
	end
	tracker.fxEvent = value
	local event = parseFx(value)
	if not event then
		return
	end
	if event.kind == "caught" then
		startLeap(tracker, event)
	else
		startDive(tracker, event)
	end
end

--------------------------------------------------------------------------------
-- Игроки
--------------------------------------------------------------------------------

local function trackPlayer(player: Player)
	if trackers[player] then
		return
	end
	local tracker: Tracker = {
		player = player,
		trove = Trove.new(),
		bobber = nil,
		effects = {},
		-- Событие, которое было до нас (вошли в игру позже), не повторяем.
		fxEvent = player:GetAttribute("FishFx"),
	}
	trackers[player] = tracker
	tracker.trove:Add(function()
		destroyBobber(tracker)
		for effect in table.clone(tracker.effects) do
			endEffect(effect)
		end
	end)
	tracker.trove:Connect(player:GetAttributeChangedSignal("FishingState"), function()
		onStateChanged(player, tracker)
	end)
	for _, attribute in { "BobberTarget", "CastTime" } do
		tracker.trove:Connect(player:GetAttributeChangedSignal(attribute), function()
			onCastChanged(tracker)
		end)
	end
	tracker.trove:Connect(player:GetAttributeChangedSignal("FishFx"), function()
		onFxChanged(tracker)
	end)
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

-- Детали эффектов рыбака, которые сейчас в мире на этом клиенте (круги, прыжок, столб,
-- конфетти, искры над рыбой), без поплавка — для тестов и отладки.
function FishingFxController.GetEffects(player: Player): { Instance }
	local list = {}
	local tracker = trackers[player]
	if tracker then
		for effect in tracker.effects do
			for _, instance in effect.instances do
				table.insert(list, instance)
			end
		end
	end
	return list
end

-- Сколько ParticleEmitter'ов эффектов рыбака сейчас на этом клиенте (с брызгами поплавка).
function FishingFxController.CountEmitters(player: Player): number
	local tracker = trackers[player]
	return if tracker then emitterCount(tracker) else 0
end

function FishingFxController:Start(_hud: ScreenGui)
	local fxFolder = Instance.new("Folder")
	fxFolder.Name = FOLDER_NAME
	fxFolder.Parent = Workspace
	folder = fxFolder
	local assets = ReplicatedStorage:WaitForChild("Assets")
	bobbersFolder = assets:WaitForChild("Bobbers")
	fishFolder = assets:WaitForChild("Fish")

	Players.PlayerAdded:Connect(trackPlayer)
	Players.PlayerRemoving:Connect(untrackPlayer)
	for _, player in Players:GetPlayers() do
		trackPlayer(player)
	end
	playerGui = Players.LocalPlayer:FindFirstChildOfClass("PlayerGui")
	startRainbows()
end

return FishingFxController
