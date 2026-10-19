--!strict
--[[
	TheftWorldController — кража в мире (Этап 4; всё на клиенте, ни одной детали сервера):
	лампа и сирена базы, подсветка вора, купол щита, табличка флага, собака, рыба на голове вора
	(docs/stage4_design.md §5.3, §5.4; числа — DefenceConfig.World (ниже — без «DefenceConfig.»),
	тексты — StealConfig.Texts.World, DefenceConfig.Texts.World; что читаем — атрибуты базы,
	собаки и игроков, RemoteNames «Кража и защита»). Витрины во время кражи, строка защит над
	аквариумом и слово у ведра — TankWorldController. Всё своё — в папке Workspace.TheftWorld (одна
	невидимая деталь-держатель Anchor в начале координат с Attachment'ами света и пыли; волчок
	сирены; купола; подсветки и слова — BillboardGui с Adornee на деталях сервера). Слова мира
	(«ВОР!», табличка рыбы вора, «ГАВ!», «💤», табличка флага «🛡️ 4:12») — под правилом «не под
	HUD» TankWorldController (TrackWord: у плашек HUD тают; буквы — не крупнее потолка надписей
	витрин, у «ГАВ!» — Dog.BarkCap потолков).

	Что делает:
	  • Базы Workspace.Bases — все сразу: по одному AttributeChanged на модель базы и на её Dog.
	    Проверка (цепочка task.delay раз в World.CheckEvery с, без покадровых соединений) идёт,
	    ТОЛЬКО пока у какой-то базы что-то есть: AlarmState, Thief, защита (ProtectUntil в
	    будущем), неспящая собака, тающий купол; всё кончилось — цепочки нет. Расстояние — от
	    камеры и своего персонажа (ближнее) до середины двора (World.Dome.Center).
	  • Лампа Alarm.Lamp (деталь сервера; сервер её не пишет): пока у базы AlarmState и она
	    ближе World.Range — Material Neon и ОДИН зацикленный твин Color от тёмного World.LampDim до
	    горячего World.LampOn (половина World.LampPeriod, у гостя — IntruderPeriod; Reverses: на
	    красной базе мигание тёмный ↔ яркий видно и издали), и PointLight (LampLight: Range,
	    Brightness ↔ 0, цвет LightColor, без теней) на своём Attachment у лампы; кончилось или база
	    дальше — цвет и материал шаблона ровно как были.
	  • Сирена (HasAlarm и AlarmState = "theft", база ближе Range): невидимая деталь-волчок FxSiren
	    в центре лампы, на ней два красных SpotLight спиной друг к другу, наклонённые вниз на
	    Siren.Pitch° (Range, Brightness, Angle: красное пятно бежит по двору), и вдоль каждого — луч
	    Beam (BeamLength studs, BeamWidth0 → BeamWidth1, прозрачность BeamFade → 1, LightEmission 1:
	    виден и днём, и на телефоне, где местного света нет); один зацикленный твин её CFrame —
	    полоборота за SirenSpin / 2 (два прожектора — полный оборот за SirenSpin); писк
	    electronicpingshort раз в Siren.BeepPeriod с (цепочка task.delay), если камера или свой
	    персонаж ближе BeepRange.
	  • Вор (HasAlarm и Thief, база ближе Range): Highlight на персонаже (Mark: заливка Berry с
	    прозрачностью Fill, обводка Berry; хозяину базы — AlwaysOnTop, остальным — Occluded) и
	    «ВОР!» над головой (Mark.Word, видно до WordRange; с рыбой на голове — строкой над её
	    табличкой). Создаются при начале и удаляются в конце (Enabled не трогаем: выключенный
	    Highlight тоже занимает слот).
	  • Купол щита — только у вида защиты из Dome.Kinds (щит; DC-15) и ProtectUntil в будущем:
	    шар Ø 2 × Dome.Radius в Dome.Center (точка базы), ForceField цвета Guard, без столкновений,
	    запросов, касаний и теней; прозрачность Transparency, а камера или свой персонаж внутри —
	    Inside, ближе Near studs к оболочке снаружи — плавно между ними (хозяин у своего спауна
	    внутри купола, его камера — снаружи: иначе весь двор сквозь лицо купола, во весь экран);
	    только у баз ближе Dome.Range, на тач-экране — не больше Dome.PhoneMax ближайших;
	    появляется и тает за Fade с.
	  • Табличка флага: над OwnerSign (Flag.Pole.SignAttachment) строка «🛡️ 4:12» цветом Guard —
	    свой BillboardGui Flag.Wide × Flag.Line её размера там, где строка внизу рамки её размера,
	    поднятой на Flag.Raise своей высоты (там небо, не полотнище флага цвета базы), пока база
	    под любой защитой (видно через карту: её MaxDistance);
	    часы — цепочка task.delay по целым секундам до конца защиты (как фишка щита и строка
	    защит над аквариумом: одно время в одном кадре; Wave 3 ART-04).
	  • Собака (Dog.Unlocked = true): спит — поза сервера (pivot щенка у DefenceConfig.Dog.Rest),
	    поднятая лапами на землю двора (луч вниз по Grounds и Arcades базы: мощёная дорожка выше
	    точки базы), и «💤» у её головы, вбок на экране (World.Dog.Sleep: Side studs в осях камеры;
	    видно до SleepRange; неподвижное); DogState ≠
	    "Sleep" и база ближе World.Dog.Range — RenderStepped (ТОЛЬКО на это время): щенок догоняет
	    DogPos (Vector3 мира) с α = 1 − e^(−Follow·dt), лапами на земле под ней (один луч на каждую
	    новую DogPos: галерея и дорожки выше газона), смотрит по ходу, на бегу подпрыгивает (Hop
	    studs, HopHz раз в секунду); уснула или база далеко — соединение снято, поза сна возвращена.
	    «ГАВ!» (Sun, едет с собакой: Adornee — её Body; видно до WordRange) всплывает при Alert и
	    когда вор (DogTarget) стал Slowed; пока он Slowed — пыль у его ног (Dust раз в DustEvery
	    с, из того же покадрового шага; один ParticleEmitter).
	  • Рыба на голове вора (StolenFish, модель сервера — Lib/HeldRig; у каждого вора из Thief баз):
	    зацикленный твин C0 сварки головы (Carried: ±Bob studs, ±Sway°, Period с; при уходе — C0
	    как был) и табличка «🥷 Окунь $45» (Berry, буквы по потолку надписей витрин) над рыбой на
	    Carried.Gap studs, видна до WordRange, выскакивает через Carried.Delay с (рыба витрины ещё
	    летит к нему — TankWorldController).
	Покой (ни одной базы с кражей, защитой или неспящей собакой) — ни одного покадрового
	соединения, ни одной цепочки и ни одного твина собаки («💤» неподвижно); база снята — всё её
	убрано; чужие объекты (лампа, сварка) возвращены как были. Щенка этот клиент двигает только
	у себя (поза сна лапами на земле, погоня); прячет его и ставит в будку сервер — его PivotTo
	приходит поверх.

	API (для тестов и превью):
	  TheftWorldController:Start(hud)
	  TheftWorldController.Get(base) -> { lamp, light, siren, beeps, mark, tag, dome, flag, dog,
	                                     dogAt, sleep, dust, carried, plate, life, distance }?
	                                     -- что сейчас у базы (Base_N; siren — волчок FxSiren,
	                                     -- dogAt — низ лап собаки на этом клиенте, sleep — «💤»,
	                                     -- life — твин рыбы на голове вора)
	  TheftWorldController.Stats() -> { bases, lamps, sirens, marks, domes, fading, flags, dogs,
	                                    sleeps, carried, running, folder }   -- running: цепочка идёт
	  TheftWorldController.Folder() -> Folder?   -- своя Workspace.TheftWorld (TheftController: «ГАВ!»)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local DefenceConfig = require(Config:WaitForChild("DefenceConfig"))
local StealConfig = require(Config:WaitForChild("StealConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))
local FishingRules = require(Shared:WaitForChild("FishingRules"))
local TankRules = require(Shared:WaitForChild("TankRules"))
local StealRules = require(Shared:WaitForChild("StealRules"))
local TextUtil = require(Shared:WaitForChild("TextUtil"))
local UiFx = require(Shared:WaitForChild("UiFx"))
local Trove = require(Shared:WaitForChild("Util"):WaitForChild("Trove"))
local TankDisplay = require(script.Parent:WaitForChild("TankDisplay"))
local TankWorldController = require(script.Parent:WaitForChild("TankWorldController"))

local WORLD = DefenceConfig.World
local DOME = WORLD.Dome
local SIREN = WORLD.Siren
local MARK = WORLD.Mark
local CARRIED = WORLD.Carried
local DOG = WORLD.Dog
local FLAG = WORLD.Flag
local WORDS = StealConfig.Texts.World
local DEFENCE_WORDS = DefenceConfig.Texts.World
local BERRY = UIConfig.Palette.Berry
local GUARD = UIConfig.Palette.Guard
local SUN = UIConfig.Palette.Sun
local FOLDER_NAME = "TheftWorld"
local BEEP = "rbxasset://sounds/electronicpingshort.wav"
local HALF_TURN = math.rad(179.9) -- (полоборота твином: короткий путь однозначен)
-- Слова у потолка букв для правила «не под HUD» (TankWorldController.TrackWord): табличка рыбы
-- вора ≈ PLATE_W × PLATE_H потолков (две строки), «ВОР!» ≈ TAG_W × TAG_H.
local PLATE_W, PLATE_H = 7, 2.6
local TAG_W, TAG_H = 3, 1.2
local SLEEP_W, SLEEP_H = 1.4, 1.2 -- «💤»

type Lamp = {
	part: BasePart,
	color: Color3,
	material: Enum.Material,
	state: string,
	tween: Tween,
	holder: Attachment,
	light: PointLight,
}

type Siren = { spinner: BasePart, tween: Tween, sound: Sound, beep: thread?, beeps: number }

type Mark = { userId: number, highlight: Highlight, tag: BillboardGui, owner: boolean }

type Carried = {
	model: Model,
	weld: Weld?,
	c0: CFrame?,
	tween: Tween?,
	gui: BillboardGui?,
	thiefLine: TextLabel?,
	trove: any,
}

type Thief = { userId: number, player: Player, trove: any, charTrove: any, carried: Carried? }

type Dust = { holder: Attachment, emitter: ParticleEmitter, next: number }

type Dog = {
	model: Model,
	pup: Model,
	rest: CFrame, -- поза сна на этом клиенте (pivot сервера лапами на земле; запомнена при пробуждении)
	feet: number, -- pivot над низом лап
	ground: Vector3, -- где собака сейчас (низ лап, мир)
	goalY: number, -- верх земли под DogPos (луч при каждой её смене)
	look: Vector3,
	clock: number,
	conn: RBXScriptConnection,
	target: number?, -- DogTarget, за чьим Slowed следим …
	thief: Player?, -- … и он сам (пыль у ног — без поиска каждый кадр)
	slowConn: RBXScriptConnection?,
	dust: Dust?,
}

type Fade = { part: BasePart, thread: thread }

-- «🛡️ 4:12» над табличкой флага; untilAt — конец защиты, по которому идут его часы, gen —
-- поколение их цепочки.
type Flag = { gui: BillboardGui, label: TextLabel, untilAt: number, gen: number }

type Base = {
	model: Model,
	trove: any,
	distance: number,
	lamp: Lamp?,
	siren: Siren?,
	mark: Mark?,
	dome: BasePart?,
	domeTarget: number?,
	flag: Flag?,
	dog: Dog?,
	sleep: BillboardGui?, -- «💤» над спящей собакой
	ray: RaycastParams?, -- луч к земле двора (Grounds и Arcades базы)
	thief: Thief?,
}

local TheftWorldController = {}

local player = Players.LocalPlayer
local started = false
local folder: Folder? = nil
local anchor: BasePart? = nil
local bases: { [Model]: Base } = {}
local fading: { Fade } = {} -- уходящие купола (тают Dome.Fade с)
local running = false -- цепочка проверок идёт
local soon = false -- внеочередная проверка уже ждёт (что-то поменялось между звеньями цепочки)
local warned: { [string]: boolean } = {}

--------------------------------------------------------------------------------
-- Мелочи
--------------------------------------------------------------------------------

local function warnOnce(key: string, message: string)
	if not warned[key] then
		warned[key] = true
		warn(`[TheftWorldController] {message}`)
	end
end

local function str(inst: Instance, name: string): string?
	local v = inst:GetAttribute(name)
	return if typeof(v) == "string" and v ~= "" then v else nil
end

local function num(inst: Instance, name: string): number?
	local v = inst:GetAttribute(name)
	return if typeof(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then v else nil
end

-- Attachment на детали-держателе (в начале координат: его CFrame — мировой).
local function holder(name: string, at: CFrame): Attachment?
	local root = anchor
	if not root then
		return nil
	end
	local point = Instance.new("Attachment")
	point.Name = name
	point.CFrame = at
	point.Parent = root
	return point
end

local function find(root: Instance, path: { string }): Instance?
	local node: Instance? = root
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function viewers(): (Vector3?, Vector3?)
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local body = if root and root:IsA("BasePart") then root.Position else nil
	return if camera then camera.CFrame.Position else nil, body
end

local function distanceFrom(p: Vector3, cam: Vector3?, body: Vector3?): number
	local d = math.huge
	if cam then
		d = (cam - p).Magnitude
	end
	if body then
		d = math.min(d, (body - p).Magnitude)
	end
	return d
end

local function courtOf(base: Base): Vector3
	return base.model:GetPivot() * DOME.Center
end

local function thiefOf(userId: number?): Player?
	if not userId then
		return nil
	end
	local ok, found = pcall(function()
		return Players:GetPlayerByUserId(userId)
	end)
	return if ok then found else nil
end

local function protectedFor(model: Model, now: number): (string?, number?)
	local untilAt = num(model, "ProtectUntil")
	if untilAt and untilAt > now then
		return str(model, "ProtectKind"), untilAt
	end
	return nil, nil
end

-- Потолок букв слов над миром — как у надписей витрин (по высоте экрана).
local function letterCap(): number
	local camera = Workspace.CurrentCamera
	return TankDisplay.tagCap(if camera then camera.ViewportSize.Y else 390)
end

local function billboardSize(spec: { Width: number, Height: number, PixelsX: number, PixelsY: number }): UDim2
	return UDim2.new(spec.Width, spec.PixelsX, spec.Height, spec.PixelsY)
end

--------------------------------------------------------------------------------
-- Лампа и сирена
--------------------------------------------------------------------------------

local function lampOf(base: Base): BasePart?
	local lamp = find(base.model, { "Alarm", "Lamp" })
	return if lamp and lamp:IsA("BasePart") then lamp else nil
end

local function stopLamp(base: Base)
	local lamp = base.lamp
	if not lamp then
		return
	end
	base.lamp = nil
	lamp.tween:Cancel()
	lamp.holder:Destroy()
	-- (вид шаблона ровно как был)
	lamp.part.Color = lamp.color
	lamp.part.Material = lamp.material
end

local function startLamp(base: Base, state: string)
	local current = base.lamp
	if current and current.state == state then
		return
	end
	stopLamp(base)
	local part = lampOf(base)
	if not part then
		warnOnce(`lamp:{base.model.Name}`, `у {base.model.Name} нет Alarm.Lamp — лампа не мигает`)
		return
	end
	local point = holder("FxAlarmLight", CFrame.new(part.Position))
	if not point then
		return
	end
	local color, material = part.Color, part.Material
	local period = if state == "intruder" then WORLD.IntruderPeriod else WORLD.LampPeriod
	local info = TweenInfo.new(period / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	part.Material = Enum.Material.Neon
	part.Color = WORLD.LampDim -- (тёмный ↔ горячий: вспышка видна и на красной базе)
	local tween = TweenService:Create(part, info, { Color = WORLD.LampOn })
	tween:Play()
	local light = Instance.new("PointLight")
	light.Name = "FxAlarmGlow"
	light.Color = WORLD.LightColor
	light.Range = WORLD.LampLight.Range
	light.Brightness = 0
	light.Shadows = false
	light.Parent = point
	TweenService:Create(light, info, { Brightness = WORLD.LampLight.Brightness }):Play()
	base.lamp = {
		part = part,
		color = color,
		material = material,
		state = state,
		tween = tween,
		holder = point,
		light = light,
	}
end

local function stopSiren(base: Base)
	local siren = base.siren
	if not siren then
		return
	end
	base.siren = nil
	siren.tween:Cancel()
	local beep = siren.beep
	siren.beep = nil
	if beep and coroutine.status(beep) == "suspended" then
		task.cancel(beep)
	end
	siren.spinner:Destroy()
end

-- Сирена: невидимая деталь-волчок в центре лампы, на ней два прожектора спиной друг к другу,
-- наклонённые вниз на Siren.Pitch° (Attachment FxSirenHead: SpotLight и начало луча), и концы
-- лучей (FxSirenTip); один зацикленный твин её CFrame (полоборота) крутит всё сразу.
local function startSiren(base: Base)
	if base.siren then
		return
	end
	local part = lampOf(base)
	local root = folder
	if not part or not root then
		return
	end
	local spinner = Instance.new("Part")
	spinner.Name = "FxSiren"
	spinner.Size = Vector3.new(0.2, 0.2, 0.2)
	spinner.CFrame = CFrame.new(part.Position)
	spinner.Transparency = 1
	spinner.Material = Enum.Material.SmoothPlastic
	spinner.Anchored = true
	spinner.CanCollide = false
	spinner.CanQuery = false
	spinner.CanTouch = false
	spinner.CastShadow = false
	spinner.Parent = root
	local down = CFrame.Angles(-math.rad(SIREN.Pitch), 0, 0) -- (взгляд −Z — вниз на Pitch°)
	for _, yaw in { 0, math.pi } do
		local head = Instance.new("Attachment")
		head.Name = "FxSirenHead"
		head.CFrame = CFrame.Angles(0, yaw, 0) * down
		head.Parent = spinner
		local spot = Instance.new("SpotLight")
		spot.Name = "FxSirenBeam"
		spot.Face = Enum.NormalId.Front
		spot.Color = WORLD.LightColor
		spot.Range = SIREN.Range
		spot.Brightness = SIREN.Brightness
		spot.Angle = SIREN.Angle
		spot.Shadows = false
		spot.Parent = head
		local tip = Instance.new("Attachment")
		tip.Name = "FxSirenTip"
		tip.CFrame = head.CFrame * CFrame.new(0, 0, -SIREN.BeamLength)
		tip.Parent = spinner
		-- луч виден и днём, и на телефоне, где местного света нет
		local ray = Instance.new("Beam")
		ray.Name = "FxSirenRay"
		ray.Attachment0 = head
		ray.Attachment1 = tip
		ray.Color = ColorSequence.new(WORLD.LightColor)
		ray.Transparency = NumberSequence.new(SIREN.BeamFade, 1)
		ray.Width0 = SIREN.BeamWidth0
		ray.Width1 = SIREN.BeamWidth1
		ray.LightEmission = 1
		ray.LightInfluence = 0
		ray.FaceCamera = true
		ray.Segments = 1
		ray.Parent = spinner
	end
	local sound = Instance.new("Sound")
	sound.Name = "FxSirenBeep"
	sound.SoundId = BEEP
	sound.Volume = SIREN.BeepVolume
	sound.RollOffMaxDistance = WORLD.BeepRange
	sound.Parent = spinner
	local turn = TweenInfo.new(WORLD.SirenSpin / 2, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1)
	local tween = TweenService:Create(spinner, turn, { CFrame = spinner.CFrame * CFrame.Angles(0, HALF_TURN, 0) })
	tween:Play()
	local siren: Siren = { spinner = spinner, tween = tween, sound = sound, beep = nil, beeps = 0 }
	base.siren = siren
	-- писк — цепочкой (не покадрово), только когда камера рядом
	local function beep()
		if base.siren ~= siren then
			return
		end
		local cam, body = viewers()
		if distanceFrom(spinner.Position, cam, body) <= WORLD.BeepRange then
			siren.beeps += 1
			sound:Play()
		end
		siren.beep = task.delay(SIREN.BeepPeriod, beep)
	end
	beep()
end

--------------------------------------------------------------------------------
-- Рыба на голове вора, вор, подсветка
--------------------------------------------------------------------------------

local function dropCarried(thief: Thief)
	local carried = thief.carried
	if not carried then
		return
	end
	thief.carried = nil
	carried.trove:Clean()
	local tween = carried.tween
	if tween then
		tween:Cancel()
	end
	local weld, c0 = carried.weld, carried.c0
	if weld and c0 and weld.Parent then
		weld.C0 = c0 -- (сварка — как поставил сервер)
	end
	local gui = carried.gui
	if gui then
		gui:Destroy()
	end
end

-- Сварка головы у Body рыбы (Part0 — не деталь рыбы).
local function headWeld(model: Model): Weld?
	local body = model.PrimaryPart
	if not body then
		return nil
	end
	for _, child in body:GetChildren() do
		if child:IsA("Weld") then
			local part0 = child.Part0
			if part0 and not part0:IsDescendantOf(model) then
				return child
			end
		end
	end
	return nil
end

local function syncMarkTag(base: Base)
	local mark, thief = base.mark, base.thief
	local carried = thief and thief.carried
	if mark then
		mark.tag.Enabled = carried == nil or carried.gui == nil
	end
	local line = carried and carried.thiefLine
	if line then
		line.Visible = mark ~= nil
	end
end

local function startCarried(base: Base, thief: Thief, model: Model)
	local existing = thief.carried
	if existing and existing.model == model then
		return
	end
	dropCarried(thief)
	local body = model.PrimaryPart
	local root = folder
	if not body or not root then
		return
	end
	local carried: Carried = {
		model = model,
		weld = nil,
		c0 = nil,
		tween = nil,
		gui = nil,
		thiefLine = nil,
		trove = Trove.new(),
	}
	thief.carried = carried
	-- живая: покачивание и поворот (зацикленный твин сварки головы)
	local weld = headWeld(model)
	if weld then
		local c0 = weld.C0
		carried.weld, carried.c0 = weld, c0
		local sway = math.rad(CARRIED.Sway)
		weld.C0 = c0 * CFrame.new(0, -CARRIED.Bob, 0) * CFrame.Angles(0, -sway, 0)
		local info = TweenInfo.new(CARRIED.Period / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
		local tween =
			TweenService:Create(weld, info, { C0 = c0 * CFrame.new(0, CARRIED.Bob, 0) * CFrame.Angles(0, sway, 0) })
		tween:Play()
		carried.tween = tween
	end
	-- табличка «🥷 Окунь $45» над рыбой (и «ВОР!» строкой над ней — с сигнализацией хозяина)
	local box, size = model:GetBoundingBox()
	local fishId = str(model, "FishId")
	local def = fishId and FishingRules.GetFish(fishId)
	local value = num(model, "Value")
	local text = TextUtil.fill(WORDS.Carried, {
		short = if def then def.ShortName else (fishId or ""),
		price = TankRules.FormatMoney(value or 0),
	})
	local spec = CARRIED.Plate
	local gui, plate = TankDisplay.billboard(
		root,
		"FxCarriedPlate",
		UDim2.new(spec.Width, spec.PixelsX, spec.Height * 2, spec.PixelsY * 2),
		WORLD.WordRange
	)
	gui.Adornee = body
	gui.StudsOffsetWorldSpace = Vector3.new(0, box.Position.Y + size.Y / 2 - body.Position.Y + CARRIED.Gap, 0)
	gui.SizeOffset = Vector2.new(0, 0.5) -- (низ таблички — над рыбой)
	local cap = letterCap()
	local name = TankDisplay.word(plate, "Fish", text, { 0, 0.5, 1, 0.5 }, BERRY, spec.Outline)
	TankDisplay.cap(name, cap)
	local line = TankDisplay.word(plate, "Thief", WORDS.Thief, { 0.2, 0, 0.6, 0.5 }, BERRY, spec.Outline)
	TankDisplay.cap(line, cap * 1.1)
	line.Visible = false
	carried.gui, carried.thiefLine = gui, line
	UiFx.popIn(plate, { from = 0, delay = CARRIED.Delay })
	TankWorldController.TrackWord(gui, cap, PLATE_W, PLATE_H) -- (у плашек HUD — тает)
	carried.trove:Connect(model.AncestryChanged, function()
		if not model:IsDescendantOf(Workspace) and thief.carried == carried then
			dropCarried(thief)
			syncMarkTag(base)
		end
	end)
	syncMarkTag(base)
end

local function dropMark(base: Base)
	local mark = base.mark
	if not mark then
		return
	end
	base.mark = nil
	mark.highlight:Destroy()
	mark.tag:Destroy()
	syncMarkTag(base)
end

local function applyMark(base: Base)
	local thief = base.thief
	local want = base.model:GetAttribute("HasAlarm") == true and thief ~= nil and base.distance <= WORLD.Range
	local character = thief and thief.player.Character
	local head = character and character:FindFirstChild("Head")
	local mark = base.mark
	if mark and (not want or not character or mark.userId ~= (thief :: Thief).userId) then
		dropMark(base)
		mark = nil
	end
	if mark and mark.highlight.Adornee ~= character then
		dropMark(base)
		mark = nil
	end
	if mark or not want or not thief or not character or not (head and head:IsA("BasePart")) then
		return
	end
	local root = folder
	if not root then
		return
	end
	local owner = num(base.model, "OwnerUserId") == player.UserId
	local highlight = Instance.new("Highlight")
	highlight.Name = "FxThiefMark"
	highlight.Adornee = character
	highlight.FillColor = BERRY.Bottom
	highlight.FillTransparency = MARK.Fill
	highlight.OutlineColor = BERRY.Top
	highlight.OutlineTransparency = MARK.Outline
	highlight.DepthMode = if owner then Enum.HighlightDepthMode.AlwaysOnTop else Enum.HighlightDepthMode.Occluded
	highlight.Parent = root
	local gui, plate = TankDisplay.billboard(root, "FxThiefTag", billboardSize(MARK.Word), WORLD.WordRange)
	gui.Adornee = head
	gui.StudsOffsetWorldSpace = Vector3.new(0, head.Size.Y / 2 + MARK.Lift, 0)
	gui.SizeOffset = Vector2.new(0, 0.5)
	local word = TankDisplay.word(plate, "Thief", WORDS.Thief, { 0, 0, 1, 1 }, BERRY, MARK.Word.Outline)
	local cap = letterCap() * 1.1
	TankDisplay.cap(word, cap)
	UiFx.popIn(plate, { from = 0 })
	TankWorldController.TrackWord(gui, cap, TAG_W, TAG_H)
	base.mark = { userId = thief.userId, highlight = highlight, tag = gui, owner = owner }
	syncMarkTag(base)
end

local function unwatchThief(base: Base)
	local thief = base.thief
	if not thief then
		return
	end
	base.thief = nil
	dropCarried(thief)
	thief.charTrove:Clean()
	thief.trove:Clean()
	dropMark(base)
end

local function watchThief(base: Base)
	local userId = num(base.model, "Thief")
	local current = base.thief
	if current and current.userId == userId then
		return
	end
	unwatchThief(base)
	local found = thiefOf(userId)
	if not userId or not found then
		return
	end
	local thief: Thief = {
		userId = userId,
		player = found,
		trove = Trove.new(),
		charTrove = Trove.new(),
		carried = nil,
	}
	base.thief = thief
	local function onCharacter(character: Model?)
		thief.charTrove:Clean()
		dropCarried(thief)
		if character then
			thief.charTrove:Connect(character.ChildAdded, function(child: Instance)
				if child.Name == "StolenFish" and child:IsA("Model") and base.thief == thief then
					startCarried(base, thief, child)
				end
			end)
			local carried = character:FindFirstChild("StolenFish")
			if carried and carried:IsA("Model") then
				startCarried(base, thief, carried)
			end
		end
		applyMark(base)
	end
	thief.trove:Connect(found.CharacterAdded, onCharacter)
	onCharacter(found.Character)
end

--------------------------------------------------------------------------------
-- Купол щита и табличка флага
--------------------------------------------------------------------------------

local function domeWanted(base: Base, now: number): boolean
	local kind = protectedFor(base.model, now)
	return kind ~= nil and DOME.Kinds[kind] == true and base.distance <= DOME.Range
end

local function dropDome(base: Base)
	local dome = base.dome
	if not dome then
		return
	end
	base.dome, base.domeTarget = nil, nil
	TweenService:Create(dome, TweenInfo.new(DOME.Fade, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Transparency = 1,
	}):Play()
	local entry: Fade = { part = dome, thread = task.delay(DOME.Fade + 0.05, function()
		dome:Destroy()
	end) }
	table.insert(fading, entry)
end

-- Прозрачность купола для этого клиента: камера или свой персонаж внутри — Inside, ближе Near
-- studs к оболочке снаружи — плавно от Transparency к Inside (хозяин у спауна внутри купола, а
-- камера позади него — снаружи: иначе весь двор виден сквозь лицо купола, во весь экран);
-- шагом 0.05 (новый твин — только когда цель сменилась).
local function domeLook(center: Vector3, cam: Vector3?, body: Vector3?): number
	local near = distanceFrom(center, cam, body)
	local share = math.clamp((near - DOME.Radius) / DOME.Near, 0, 1)
	return math.round((DOME.Inside + (DOME.Transparency - DOME.Inside) * share) * 20) / 20
end

local function ensureDome(base: Base, cam: Vector3?, body: Vector3?)
	local root = folder
	if not root then
		return
	end
	local center = courtOf(base)
	local target = domeLook(center, cam, body)
	local dome = base.dome
	if not dome then
		local part = Instance.new("Part")
		part.Name = "FxShieldDome"
		part.Shape = Enum.PartType.Ball
		part.Size = Vector3.new(1, 1, 1) * (DOME.Radius * 2)
		part.CFrame = CFrame.new(center)
		part.Material = Enum.Material.ForceField
		part.Color = GUARD.Bottom
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Parent = root
		base.dome = part
		dome = part
	end
	if base.domeTarget ~= target then
		base.domeTarget = target
		TweenService
			:Create(dome :: BasePart, TweenInfo.new(DOME.Fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = target,
			})
			:Play()
	end
end

local function dropFlag(base: Base)
	local flag = base.flag
	if flag then
		base.flag = nil
		flag.gen += 1
		flag.gui:Destroy()
	end
end

local function flagText(untilAt: number, now: number): string
	return TextUtil.fill(DEFENCE_WORDS.Protect, { t = StealRules.FormatClock(untilAt - now) })
end

-- Часы таблички — по целым секундам до конца защиты (как фишка щита DefenceController и строка
-- защит над аквариумом TankWorldController: одно время в одном кадре; Wave 3 ART-04): цепочка
-- task.delay ровно до смены числа, пока табличка та же и конец защиты тот же.
local function flagStep(base: Base, flag: Flag, gen: number)
	if base.flag ~= flag or flag.gen ~= gen then
		return
	end
	local now = Workspace:GetServerTimeNow()
	local left = flag.untilAt - now
	local text = flagText(flag.untilAt, now)
	if flag.label.Text ~= text then
		flag.label.Text = text
	end
	if left > 0 then
		task.delay(math.max(left - math.floor(left), 0.01), flagStep, base, flag, gen)
	end
end

local function applyFlag(base: Base, now: number)
	local _, untilAt = protectedFor(base.model, now)
	if not untilAt then
		dropFlag(base)
		return
	end
	local text = flagText(untilAt, now)
	local flag = base.flag
	if not flag then
		local sign = find(base.model, { "Flag", "Pole", "SignAttachment", "OwnerSign" })
		local point = sign and sign.Parent
		local root = folder
		if not (sign and sign:IsA("BillboardGui") and point and point:IsA("Attachment") and root) then
			return
		end
		-- Рамка — ровно строка (Wide × Line размера таблички владельца) там, где строка была бы
		-- внизу рамки её размера, поднятой на Raise своей высоты: над табличкой — небо, не синее
		-- полотнище флага. Рамка по буквам — её меряет правило «не под HUD» (Wave 3 ART-07).
		local size = sign.Size
		local gui, plate = TankDisplay.billboard(
			root,
			"FxFlagProtect",
			UDim2.new(
				size.X.Scale * FLAG.Wide,
				math.round(size.X.Offset * FLAG.Wide),
				size.Y.Scale * FLAG.Line,
				math.round(size.Y.Offset * FLAG.Line)
			),
			sign.MaxDistance
		)
		gui.Adornee = point
		gui.SizeOffset = Vector2.new(0, (FLAG.Raise - 0.5 + FLAG.Line / 2) / FLAG.Line)
		local label = TankDisplay.word(plate, "Protect", text, { 0, 0, 1, 1 }, GUARD, FLAG.Outline, true)
		UiFx.popIn(plate, { from = 0.4 })
		TankWorldController.TrackWord(gui) -- (у плашек HUD — тает, как «ВОР!»)
		flag = { gui = gui, label = label, untilAt = untilAt, gen = 0 }
		base.flag = flag
		flagStep(base, flag :: Flag, 0)
	end
	local f = flag :: Flag
	if f.untilAt ~= untilAt then
		-- (щит продлили или сменился вид защиты: часы — с нового конца)
		f.untilAt = untilAt
		f.gen += 1
		flagStep(base, f, f.gen)
	elseif f.label.Text ~= text then
		f.label.Text = text
	end
end

--------------------------------------------------------------------------------
-- Собака
--------------------------------------------------------------------------------

local function dogModels(base: Base): (Model?, Model?)
	local dog = base.model:FindFirstChild("Dog")
	local pup = dog and dog:FindFirstChild("Pup")
	if dog and dog:IsA("Model") and pup and pup:IsA("Model") and pup.PrimaryPart then
		return dog, pup
	end
	return nil, nil
end

-- Pivot щенка на этом клиенте — по его Body (GetPivot модели в эмуляторе тестов читает сервер).
local function pupPivot(pup: Model): CFrame
	local body = pup.PrimaryPart :: BasePart
	return body.CFrame * body.PivotOffset
end

-- Сколько pivot щенка над низом его лап и сколько макушка над pivot (по деталям; щенок стоит).
local function pupShape(pup: Model): (number, number)
	local y = pupPivot(pup).Position.Y
	local low, high = math.huge, -math.huge
	for _, part in pup:GetDescendants() do
		if part:IsA("BasePart") then
			low = math.min(low, part.Position.Y - part.Size.Y / 2)
			high = math.max(high, part.Position.Y + part.Size.Y / 2)
		end
	end
	if low > high then
		return 0, 0
	end
	return y - low, high - y
end

-- Верх земли двора под точкой (x, z): луч вниз только по Grounds и Arcades базы (от
-- Dog.GroundUp studs над точкой базы на Dog.GroundDown); nil — не попал.
local function groundAt(base: Base, x: number, z: number): number?
	local params = base.ray
	if not params then
		local list: { Instance } = {}
		for _, name in { "Grounds", "Arcades" } do
			local found = base.model:FindFirstChild(name)
			if found then
				table.insert(list, found)
			end
		end
		if #list == 0 then
			return nil
		end
		local made = RaycastParams.new()
		made.FilterType = Enum.RaycastFilterType.Include
		made.FilterDescendantsInstances = list
		base.ray = made
		params = made
	end
	local from = Vector3.new(x, base.model:GetPivot().Position.Y + DOG.GroundUp, z)
	local hit = Workspace:Raycast(from, Vector3.new(0, -DOG.GroundDown, 0), params)
	return if hit then hit.Position.Y else nil
end

-- Поза сна на этом клиенте: pivot сервера (Dog.Rest на высоте шаблона), поднятый так, чтобы лапы
-- стояли на мощёной дорожке двора под ним (она выше точки базы — в шаблонной высоте лапы тонули).
local function restPose(base: Base, pup: Model): CFrame
	local pivot = pupPivot(pup)
	local feet = pupShape(pup)
	local ground = groundAt(base, pivot.Position.X, pivot.Position.Z)
	if not ground then
		return pivot
	end
	return pivot + Vector3.new(0, ground - (pivot.Position.Y - feet), 0)
end

-- «ГАВ!» всплывает над собакой и едет с ней (Adornee — Body щенка).
local function bark(base: Base)
	local _, pup = dogModels(base)
	local body = pup and pup.PrimaryPart
	local root = folder
	if not pup or not body or not root then
		return
	end
	local _, top = pupShape(pup)
	local lift = pupPivot(pup).Position.Y + top - body.Position.Y + DOG.BarkLift
	local gui =
		TankDisplay.rise(root, WORDS.Bark, SUN, billboardSize(DOG.Bark), DOG.BarkRise, DOG.BarkTime, WORLD.WordRange)
	gui.Adornee = body
	gui.StudsOffsetWorldSpace = Vector3.new(0, lift, 0)
	-- буквы не крупнее BarkCap потолков надписей витрин: у камеры рамка растёт, а не буквы (не
	-- громче кошелька; Wave 3 ART-02 — без потолка ≈ 70 px на телефоне, как «ДОБЫЧА!»)
	local cap = letterCap() * DOG.BarkCap
	local amount = gui:FindFirstChild("Amount", true)
	if amount and amount:IsA("TextLabel") then
		TankDisplay.cap(amount, cap)
	end
	TankWorldController.TrackWord(gui, cap, TAG_W, TAG_H)
end

local function dropSleep(base: Base)
	local gui = base.sleep
	if gui then
		base.sleep = nil
		gui:Destroy()
	end
end

-- Собака показана и спит: лапы — на землю (PivotTo, только если стоит не там), «💤» над ней
-- (неподвижное: в покое ни одного твина). Проснулась, спрятана или база снята — «💤» нет.
local function applySleep(base: Base, awake: boolean)
	local dogModel, pup = dogModels(base)
	local body = pup and pup.PrimaryPart
	local root = folder
	if
		awake
		or base.dog
		or not dogModel
		or not pup
		or not body
		or not root
		or dogModel:GetAttribute("Unlocked") ~= true
	then
		dropSleep(base)
		return
	end
	local pose = restPose(base, pup)
	if (pose.Position - pupPivot(pup).Position).Magnitude > 0.02 then
		pup:PivotTo(pose)
	end
	if base.sleep then
		return
	end
	local spec = DOG.Sleep
	local _, top = pupShape(pup)
	local gui, plate = TankDisplay.billboard(root, "FxDogSleep", billboardSize(spec), DOG.SleepRange)
	gui.Adornee = body
	-- у макушки и вбок на экране (Side studs в осях камеры; как в комиксе): собака посреди
	-- кадра — «💤» не на его середине, где стопка статуса (Wave 3 ART-07); рамка — по центру точки
	gui.StudsOffsetWorldSpace =
		Vector3.new(0, pupPivot(pup).Position.Y + top - body.Position.Y + spec.Lift + spec.Height / 2, 0)
	gui.StudsOffset = Vector3.new(spec.Side, 0, 0)
	local label = Instance.new("TextLabel")
	label.Name = "Sleep"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = DEFENCE_WORDS.Sleep
	label.TextScaled = true
	label.FontFace = Font.new(UIConfig.Font.Family, Enum.FontWeight.Heavy)
	label.Parent = plate
	local cap = letterCap()
	TankDisplay.cap(label, cap)
	TankWorldController.TrackWord(gui, cap, SLEEP_W, SLEEP_H) -- (у плашек HUD — тает)
	base.sleep = gui
end

local function stopDust(dog: Dog)
	local dust = dog.dust
	if dust then
		dog.dust = nil
		dust.holder:Destroy()
	end
end

-- Следим за Slowed вора, которого держит собака: стал замедлен — «ГАВ!» и пыль.
local function watchTarget(base: Base, dog: Dog)
	local target = num(dog.model, "DogTarget")
	if target == dog.target then
		return
	end
	dog.target = target
	local conn = dog.slowConn
	dog.slowConn = nil
	if conn then
		conn:Disconnect()
	end
	stopDust(dog)
	local thief = thiefOf(target)
	dog.thief = thief
	if not thief then
		return
	end
	local function update()
		if base.dog ~= dog then
			return
		end
		local slowed = thief:GetAttribute("Slowed") == true
		if slowed and not dog.dust then
			bark(base)
			local point = holder("FxDogDust", CFrame.new(dog.ground))
			if point then
				local emitter = TankDisplay.emitter(point, "dust")
				dog.dust = { holder = point, emitter = emitter, next = 0 }
			end
		elseif not slowed then
			stopDust(dog)
		end
	end
	dog.slowConn = thief:GetAttributeChangedSignal("Slowed"):Connect(update)
	update()
end

-- Новая DogPos: верх земли под ней (один луч на смену; не попал — прежний).
local function aimGround(base: Base, dog: Dog)
	local target = dog.model:GetAttribute("DogPos")
	if typeof(target) == "Vector3" then
		dog.goalY = groundAt(base, target.X, target.Z) or dog.goalY
	end
end

local function stopDog(base: Base)
	local dog = base.dog
	if not dog then
		return
	end
	base.dog = nil
	dog.conn:Disconnect()
	local conn = dog.slowConn
	dog.slowConn = nil
	if conn then
		conn:Disconnect()
	end
	stopDust(dog)
	-- (поза сна — как была при пробуждении)
	dog.pup:PivotTo(dog.rest)
end

local function stepDog(_base: Base, dog: Dog, dt: number)
	local target = dog.model:GetAttribute("DogPos")
	local goal = if typeof(target) == "Vector3" then Vector3.new(target.X, dog.goalY, target.Z) else dog.ground
	local alpha = 1 - math.exp(-DOG.Follow * dt)
	local nextPos = dog.ground:Lerp(goal, alpha)
	local delta = nextPos - dog.ground
	local flat = Vector3.new(delta.X, 0, delta.Z)
	local speed = if dt > 0 then flat.Magnitude / dt else 0
	if flat.Magnitude > 1e-3 then
		dog.look = flat.Unit
	end
	dog.clock += dt
	local hop = if speed > DOG.RunFrom then DOG.Hop * math.abs(math.sin(math.pi * DOG.HopHz * dog.clock)) else 0
	dog.ground = nextPos
	local at = nextPos + Vector3.new(0, dog.feet + hop, 0)
	dog.pup:PivotTo(CFrame.lookAt(at, at + dog.look))
	-- пыль у ног замедленного вора
	local dust = dog.dust
	if dust then
		dust.next -= dt
		local character = dog.thief and dog.thief.Character
		local hrp = character and character:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			dust.holder.CFrame = CFrame.new(hrp.Position.X, nextPos.Y + 0.3, hrp.Position.Z)
			if dust.next <= 0 then
				dust.next = DOG.DustEvery
				TankDisplay.emit(dust.emitter, DOG.Dust)
			end
		end
	end
end

local function startDog(base: Base)
	if base.dog then
		return
	end
	local dogModel, pup = dogModels(base)
	if not dogModel or not pup then
		return
	end
	dropSleep(base)
	local rest = restPose(base, pup)
	local feet = pupShape(pup)
	local ground = rest.Position - Vector3.new(0, feet, 0)
	local look = Vector3.new(rest.LookVector.X, 0, rest.LookVector.Z)
	local dog: Dog? = nil
	local conn = RunService.RenderStepped:Connect(function(dt: number)
		local current = dog
		if current and base.dog == current then
			stepDog(base, current, dt)
		end
	end)
	local made: Dog = {
		model = dogModel,
		pup = pup,
		rest = rest,
		feet = feet,
		ground = ground,
		goalY = ground.Y,
		look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1),
		clock = 0,
		conn = conn,
		target = nil,
		thief = nil,
		slowConn = nil,
		dust = nil,
	}
	dog = made
	base.dog = made
	aimGround(base, made)
	watchTarget(base, made)
end

local function dogAwake(base: Base): boolean
	local dogModel = dogModels(base)
	if not dogModel or dogModel:GetAttribute("Unlocked") ~= true then
		return false
	end
	local state = str(dogModel, "DogState")
	return state ~= nil and state ~= "Sleep"
end

--------------------------------------------------------------------------------
-- Проверка (цепочка, только пока что-то идёт)
--------------------------------------------------------------------------------

local function active(base: Base, now: number): boolean
	local model = base.model
	return str(model, "AlarmState") ~= nil
		or num(model, "Thief") ~= nil
		or protectedFor(model, now) ~= nil
		or dogAwake(base)
		or base.dome ~= nil
end

-- Одна база: лампа, сирена, вор, табличка флага, собака (купола — все вместе, в check).
local function apply(base: Base, now: number)
	local model = base.model
	local state = str(model, "AlarmState")
	local near = base.distance <= WORLD.Range
	if (state == "theft" or state == "intruder") and near then
		startLamp(base, state)
	else
		stopLamp(base)
	end
	if state == "theft" and near and model:GetAttribute("HasAlarm") == true then
		startSiren(base)
	else
		stopSiren(base)
	end
	watchThief(base)
	applyMark(base)
	applyFlag(base, now)
	local awake = dogAwake(base)
	if awake and base.distance <= DOG.Range then
		startDog(base)
	else
		stopDog(base)
	end
	applySleep(base, awake)
end

local function check(): boolean
	local cam, body = viewers()
	local now = Workspace:GetServerTimeNow()
	local any = false
	local domes: { Base } = {}
	for _, base in bases do
		base.distance = distanceFrom(courtOf(base), cam, body)
		apply(base, now)
		if domeWanted(base, now) then
			table.insert(domes, base)
		end
	end
	-- купола: ближние, на тач-экране — не больше PhoneMax
	table.sort(domes, function(a: Base, b: Base)
		return a.distance < b.distance
	end)
	local limit = if UserInputService.TouchEnabled then DOME.PhoneMax else #domes
	local keep: { [Base]: boolean } = {}
	for i, base in domes do
		if i <= limit then
			keep[base] = true
			ensureDome(base, cam, body)
		end
	end
	for _, base in bases do
		if not keep[base] then
			dropDome(base)
		end
		any = any or active(base, now)
	end
	for i = #fading, 1, -1 do
		if fading[i].part.Parent == nil then
			table.remove(fading, i)
		end
	end
	return any or #fading > 0
end

local function loop()
	local ok, result = pcall(check)
	if not ok then
		warnOnce(`check:{result}`, `проверка упала: {result}`)
	end
	if ok and result == false then
		running = false
		return
	end
	task.delay(WORLD.CheckEvery, loop)
end

-- Что-то поменялось: проверка — в ближайший кадр (одна, сколько бы атрибутов ни сменилось), и
-- цепочка идёт, если ещё не шла.
local function wake()
	if not running then
		running = true
		task.defer(loop)
	elseif not soon then
		soon = true
		task.defer(function()
			soon = false
			local ok, err = pcall(check)
			if not ok then
				warnOnce(`check:{err}`, `проверка упала: {err}`)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Базы
--------------------------------------------------------------------------------

local function untrack(model: Model)
	local base = bases[model]
	if not base then
		return
	end
	bases[model] = nil
	stopLamp(base)
	stopSiren(base)
	unwatchThief(base)
	dropDome(base)
	dropFlag(base)
	stopDog(base)
	dropSleep(base)
	base.trove:Clean()
end

local function track(model: Instance)
	if not model:IsA("Model") or bases[model] then
		return
	end
	local base: Base = {
		model = model,
		trove = Trove.new(),
		distance = math.huge,
		lamp = nil,
		siren = nil,
		mark = nil,
		dome = nil,
		domeTarget = nil,
		flag = nil,
		dog = nil,
		sleep = nil,
		ray = nil,
		thief = nil,
	}
	bases[model] = base
	base.trove:Connect(model.AttributeChanged, function(name: string)
		if name == "Thief" then
			watchThief(base)
		end
		wake()
	end)
	local dog = model:FindFirstChild("Dog")
	if dog then
		base.trove:Connect(dog.AttributeChanged, function(name: string)
			if name == "DogState" then
				local state = str(dog, "DogState")
				if state == "Alert" and dogAwake(base) then
					local cam, body = viewers()
					base.distance = distanceFrom(courtOf(base), cam, body)
					if base.distance <= DOG.Range then
						bark(base)
					end
				end
			elseif name == "DogTarget" then
				local current = base.dog
				if current then
					watchTarget(base, current)
				end
			elseif name == "DogPos" then
				local current = base.dog
				if current then
					aimGround(base, current)
				end
			end
			if name ~= "DogPos" then
				wake()
			end
		end)
	end
	wake()
end

--------------------------------------------------------------------------------
-- API
--------------------------------------------------------------------------------

function TheftWorldController.Get(model: Instance): { [string]: any }?
	local base = bases[model :: Model]
	if not base then
		return nil
	end
	local lamp, siren, mark, thief = base.lamp, base.siren, base.mark, base.thief
	local carried = thief and thief.carried
	return {
		lamp = lamp ~= nil,
		light = lamp and lamp.light,
		siren = siren and siren.spinner,
		beeps = if siren then siren.beeps else 0,
		mark = mark and mark.highlight,
		tag = mark and mark.tag,
		dome = base.dome,
		flag = base.flag and base.flag.gui,
		dog = base.dog ~= nil,
		dogAt = base.dog and base.dog.ground,
		sleep = base.sleep,
		dust = base.dog ~= nil and base.dog.dust ~= nil,
		carried = carried and carried.model,
		plate = carried and carried.gui,
		life = carried and carried.tween,
		distance = base.distance,
	}
end

-- Своя папка Workspace.TheftWorld этого клиента (TheftController ищет в ней «ГАВ!»; по имени в
-- Workspace — нельзя: в эмуляторе тестов клиенты делят один Workspace).
function TheftWorldController.Folder(): Folder?
	return folder
end

function TheftWorldController.Stats(): { [string]: any }
	local count =
		{ bases = 0, lamps = 0, sirens = 0, marks = 0, domes = 0, flags = 0, dogs = 0, sleeps = 0, carried = 0 }
	for _, base in bases do
		count.bases += 1
		count.lamps += if base.lamp then 1 else 0
		count.sirens += if base.siren then 1 else 0
		count.marks += if base.mark then 1 else 0
		count.domes += if base.dome then 1 else 0
		count.flags += if base.flag then 1 else 0
		count.dogs += if base.dog then 1 else 0
		count.sleeps += if base.sleep then 1 else 0
		count.carried += if base.thief and base.thief.carried then 1 else 0
	end
	return {
		bases = count.bases,
		lamps = count.lamps,
		sirens = count.sirens,
		marks = count.marks,
		domes = count.domes,
		fading = #fading,
		flags = count.flags,
		dogs = count.dogs,
		sleeps = count.sleeps,
		carried = count.carried,
		running = running,
		folder = folder,
	}
end

function TheftWorldController:Start(_hud: ScreenGui)
	if started then
		return
	end
	started = true
	local root = Instance.new("Folder")
	root.Name = FOLDER_NAME
	root.Parent = Workspace
	folder = root
	-- деталь-держатель Attachment'ов света, сирены и слов: в начале координат, невидимая
	local part = Instance.new("Part")
	part.Name = "Anchor"
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new()
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Transparency = 1
	part.Material = Enum.Material.SmoothPlastic
	part.Parent = root
	anchor = part
	local function watchBases(basesFolder: Instance)
		for _, child in basesFolder:GetChildren() do
			track(child)
		end
		basesFolder.ChildAdded:Connect(track)
		basesFolder.ChildRemoved:Connect(function(child: Instance)
			if child:IsA("Model") then
				untrack(child)
			end
		end)
	end
	local basesFolder = Workspace:FindFirstChild("Bases")
	if basesFolder then
		watchBases(basesFolder)
	else
		local waiting: RBXScriptConnection? = nil
		waiting = Workspace.ChildAdded:Connect(function(child: Instance)
			if child.Name == "Bases" then
				if waiting then
					waiting:Disconnect()
				end
				watchBases(child)
			end
		end)
	end
end

return TheftWorldController
