--!strict
--[[
	TankDisplay — помощник TankWorldController (модуль, не контроллер): из чего сделан садок в
	мире на этом клиенте — рыба в витрине, надписи-слова над миром, всплывающие суммы, искры и
	вспышки. Числа — TankConfig.Display / Pier, цвета и шрифт — UIConfig (стиль «Симулятор»,
	tools/builder/gui/STYLE.md §3 «Words in the world»). Состояния здесь нет: что, где и когда
	показывать, решает TankWorldController.

	Рыба в витрине (buildFish): копия ReplicatedStorage.Assets.Fish[FishId][мутация] (нет такой
	мутации — "Normal"), увеличена в min(MaxScale, Fit / длинная сторона) раз; детали
	раскладываются от центра ГАБАРИТА шаблона (Body смещён от него до 0.88), центр — точно на
	Display.FishPoint; голова — по +X или −X витрины (head = 1 / −1), повернута на Yaw° к проходу
	(−Z витрины); все детали закреплены (Anchored), без столкновений, запросов, касаний и теней;
	атрибуты модели FishId, Rarity, Mutation, Kg, Value. Тег RainbowFish шаблона с копии СНЯТ
	(вместо него атрибут Rainbow = true): радужную перекрашивает FishingFxController — покадрово
	(Heartbeat), пока есть хоть одна модель с тегом, — поэтому тег стоит только пока рыба жива
	(startLife / stopLife), дальше цвета застывают. Сварок в покое нет.
	  • Тихая жизнь (life): детали привариваются (WeldConstraint) к закреплённому Body, остальные
	    откреплены — и ОДИН зацикленный твин CFrame у Body (покачивание ±Life.Bob stud и поворот
	    ±Life.Turn° вокруг центра рыбы, Sine InOut, Reverses, бесконечно; длина TimeMin..TimeMax и
	    фаза — случайные); у радужной — тег RainbowFish. stopLife — твин снят, Body на месте покоя,
	    детали снова закреплены, сварки и тег убраны. Своего покадрового Lua нет.
	  • Появление / уход (scaleParts): у закреплённых деталей твины Size и CFrame к центру рыбы и
	    обратно (≤ 20 твинов на рыбу, без соединений); ушедшая рыба удаляется по окончании.
	Слова над миром (word / billboard): BillboardGui без плашки — буквы Montserrat Heavy (у чисел —
	Italic) белые с градиентом Fill цвета (Top → Bottom) и тонкой круглой обводкой Outline тёмного
	оттенка того же цвета (Lip); LightInfluence 0, AlwaysOnTop false; содержимое — во Frame
	"Plate" (его UIScale «FxScale» — для UiFx.popIn / punch).
	  tag   — перед витриной, на высоте её планки (FxTankTag): «+$4/с» (BillboardGreen) и
	          «$45» / «$135 МАКС» (BillboardYellow), строки чуть внахлёст рамками (крупнее буквы) и
	          прижаты к середине; буквы не крупнее потолка tagCap (UITextSizeConstraint "Cap" —
	          capTag: вблизи растёт рамка, а не буквы — надпись не громче кошелька);
	  sign  — над большим аквариумом (FxTankSign): «+$42/с» крупно зелёным, «🐠 4/6» белым; буквы не
	          крупнее signCap (capSign), строки у середины;
	  pier  — над ведром у места рыбалки (FxPierTank): «🐠 4/6» белым, «+$42/с» зелёным;
	  lock  — на первой закрытой витрине галереи (FxTankLock): «🔒 Закрыто» светло-серым (Palette.Slate);
	  market — над рынком острова (FxMarketWord): «РЫНОК +50%!» (BillboardYellow);
	  rise  — всплывающая сумма (FxTankPop): выскакивает, поднимается на lift studs за time с и
	          тает, потом удаляется сама (task.delay).
	Эффекты: emitter — ParticleEmitter вида "splash" (брызги вверх и капли), "sparkle" (искры
	цветов colors) или "coins" (золотые монетки), выключен, только для emit(n) (pcall: в
	эмуляторе тестов RbxSim у ParticleEmitter нет Emit); flash — PointLight цвета color вспыхивает
	и гаснет за time с, потом удаляется.

	API:
	  TankDisplay.template(fishId, mutation?) -> Model?
	  TankDisplay.buildFish(template, fishPoint, head, attrs) -> Model?   -- attrs: FishId, Rarity, …
	  TankDisplay.centre(model) -> Vector3                                -- центр габарита
	  TankDisplay.startLife(model, rng) -> Life?
	  TankDisplay.stopLife(life)
	  TankDisplay.scaleParts(model, from, to, time, style, direction, delay?) -> { Tween }
	  TankDisplay.billboard(parent, name, size, maxDistance) -> (BillboardGui, Frame)
	  TankDisplay.word(plate, name, text, box, look, outline, italic?) -> TextLabel
	  TankDisplay.tag(parent, cap) -> Tag;   TankDisplay.setTag(tag, rateText, valueText)
	  TankDisplay.tagCap(screenHeight) -> number;   TankDisplay.capTag(tag, cap)
	  TankDisplay.sign(parent, cap) -> Pair; TankDisplay.pier(parent) -> Pair; TankDisplay.setPair(pair, a, b)
	  TankDisplay.signCap(screenHeight) -> number;   TankDisplay.capSign(sign, cap)
	  TankDisplay.lock(parent, text) -> BillboardGui                  -- «🔒 Закрыто» (FxTankLock)
	  TankDisplay.market(parent, text) -> BillboardGui
	  TankDisplay.rise(parent, text, look, size, lift, time, maxDistance) -> BillboardGui
	  TankDisplay.emitter(parent, kind, colors?) -> ParticleEmitter;  TankDisplay.emit(emitter, count)
	  TankDisplay.flash(parent, color) -> PointLight
	  TankDisplay.countParts(model) -> number
	Этап 4 (кража; числа — Display.Steal, Sign.DefenceShare):
	  TankDisplay.rig(model) -> Rig?          -- рыба целиком: детали и их места от Body (в покое)
	  TankDisplay.bodyAt(rig, centre, turn?) -> CFrame;  TankDisplay.centreAt(rig, body) -> Vector3
	  TankDisplay.around(rig, offset, turn) -> CFrame   -- поза вокруг центра покоя (подъём, борьба)
	  TankDisplay.setRig(rig, body);  TankDisplay.tweenRig(rig, body, info) -> { Tween }
	      (твин CFrame у каждой детали, ≤ 20: без сварок — так же в эмуляторе тестов и в превью)
	  TankDisplay.stealWord(parent, text, cap, maxDistance) -> StealWord   -- «КРАДУТ!» (FxTankSteal):
	      светлый диск Ring со значком Steal.Icon (на нём кольцо-таймер у вызывающего) и слово Berry
	  TankDisplay.pulseLight(parent, color) -> PointLight   -- красный пульс у LightBar (FxStealPulse)
	  TankDisplay.signDefence(sign, cap) -> Defence;  TankDisplay.setSignDefence(sign, row, protect?, owned?)
	  TankDisplay.capDefence(row, cap);  TankDisplay.cap(label, max)   -- потолок букв любого слова
	  TankDisplay.pierAlarm(pair, text) -> TextLabel   -- «🚨 КРАДУТ!» у ведра (спрятано)
	  emitter вида "dust" — серая пыль у ног вора, которого держит собака (TheftWorldController)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local TankConfig = require(Config:WaitForChild("TankConfig"))
local UIConfig = require(Config:WaitForChild("UIConfig"))

local DISPLAY = TankConfig.Display
local PIER = TankConfig.Pier
local LIFE = DISPLAY.Life
local FX = DISPLAY.Fx
local INK = UIConfig.Ink
local WHITE = Color3.new(1, 1, 1)
local FONT = Font.new(UIConfig.Font.Family, Enum.FontWeight.Heavy)
local FONT_ITALIC = Font.new(UIConfig.Font.Family, Enum.FontWeight.Heavy, Enum.FontStyle.Italic)
local SPARKLE_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SPLASH_TEXTURE = "rbxasset://textures/particles/smoke_main.dds" -- (читается как брызги)
local RAINBOW_TAG = "RainbowFish" -- (FishingFxController перекрашивает модели с этим тегом)

export type Look = { Top: Color3, Bottom: Color3, Lip: Color3 }
-- Белые буквы с тёмной обводкой (как имя владельца на табличке базы).
local WHITE_LOOK: Look = { Top = WHITE, Bottom = Color3.fromRGB(221, 230, 240), Lip = INK }

export type Life = {
	model: Model,
	body: BasePart,
	rest: CFrame,
	welds: { WeldConstraint },
	tween: Tween?,
	start: thread?,
}
export type Tag = { gui: BillboardGui, plate: Frame, rate: TextLabel, value: TextLabel }
export type Pair = { gui: BillboardGui, plate: Frame, top: TextLabel, bottom: TextLabel }
-- Рыба целиком (кража): детали, их места относительно Body, Body в покое, центр рамки (в осях
-- Body) и половина её размера.
export type Rig = {
	model: Model,
	body: BasePart,
	parts: { BasePart },
	rel: { CFrame },
	rest: CFrame,
	centre: Vector3,
	half: Vector3,
}
-- «КРАДУТ!» над витриной: диск с кольцом-таймером (Ring, внутри значок) и слово.
export type StealWord = { gui: BillboardGui, plate: Frame, ring: Frame, word: TextLabel }
-- Строка защит на табличке садка: «🛡️ 0:42» (Protect) и «🔐1 · 🐕 · 🚨» (Owned).
export type Defence = { protect: TextLabel, owned: TextLabel, shown: boolean }

local TankDisplay = {}
TankDisplay.WHITE = WHITE_LOOK

local fishFolder: Instance? = nil

local function fishRoot(): Instance?
	if not fishFolder then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		fishFolder = assets and assets:FindFirstChild("Fish")
	end
	return fishFolder
end

local function partsOf(model: Model): { BasePart }
	local list = {}
	for _, item in model:GetDescendants() do
		if item:IsA("BasePart") then
			table.insert(list, item)
		end
	end
	return list
end

function TankDisplay.countParts(model: Model): number
	return #partsOf(model)
end

function TankDisplay.template(fishId: string, mutation: string?): Model?
	local root = fishRoot()
	local variants = root and root:FindFirstChild(fishId)
	if not variants then
		return nil
	end
	local model = (if mutation then variants:FindFirstChild(mutation) else nil) or variants:FindFirstChild("Normal")
	if model and model:IsA("Model") and model.PrimaryPart then
		return model
	end
	return nil
end

--------------------------------------------------------------------------------
-- Рыба в витрине
--------------------------------------------------------------------------------

-- Габарит шаблона в осях его Body: центр (от Body) и размер.
local function templateBox(template: Model): (Vector3, Vector3)
	local body = template.PrimaryPart :: BasePart
	local pivot = body.CFrame
	local lo = { math.huge, math.huge, math.huge }
	local hi = { -math.huge, -math.huge, -math.huge }
	for _, part in partsOf(template) do
		local rel = pivot:ToObjectSpace(part.CFrame)
		local half = part.Size / 2
		-- углы детали в осях Body (у повёрнутой детали — её настоящие углы)
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local p = rel * Vector3.new(sx * half.X, sy * half.Y, sz * half.Z)
					for axis, v in { p.X, p.Y, p.Z } do
						lo[axis] = math.min(lo[axis], v)
						hi[axis] = math.max(hi[axis], v)
					end
				end
			end
		end
	end
	local a, b = Vector3.new(lo[1], lo[2], lo[3]), Vector3.new(hi[1], hi[2], hi[3])
	return (a + b) / 2, b - a
end

function TankDisplay.buildFish(template: Model, fishPoint: Attachment, head: number, attrs: { [string]: any }): Model?
	local body = template.PrimaryPart
	if not body then
		return nil
	end
	local centre, size = templateBox(template)
	local longest = math.max(size.X, size.Y, size.Z)
	if longest <= 0 then
		return nil
	end
	local scale = math.min(DISPLAY.MaxScale, DISPLAY.Fit / longest)
	local yaw = if head >= 0 then DISPLAY.Yaw else 180 - DISPLAY.Yaw
	local placed = CFrame.new(fishPoint.WorldPosition)
		* fishPoint.WorldCFrame.Rotation
		* CFrame.Angles(0, math.rad(yaw), 0)
	local pivot = body.CFrame
	local model = template:Clone()
	-- (копия стоит там же, где шаблон: раскладка — от её же Body)
	for _, part in partsOf(model) do
		local rel = pivot:ToObjectSpace(part.CFrame)
		part.Size = part.Size * scale
		part.CFrame = placed * CFrame.new((rel.Position - centre) * scale) * rel.Rotation
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
	end
	model.Name = "DisplayFish"
	-- (копия ещё не в мире: снятие тега никого не будит; вернёт его startLife)
	if model:HasTag(RAINBOW_TAG) then
		model:RemoveTag(RAINBOW_TAG)
		model:SetAttribute("Rainbow", true)
	end
	for key, value in attrs do
		model:SetAttribute(key, value)
	end
	model:SetAttribute("Scale", scale)
	return model
end

-- Центр габарита рыбы сейчас (мир).
function TankDisplay.centre(model: Model): Vector3
	local box = model:GetBoundingBox()
	return box.Position
end

-- Покачивание и поворот вокруг центра рыбы: CFrame Body при сдвиге sign = −1 / +1.
local function lifePose(rest: CFrame, centre: Vector3, sign: number): CFrame
	local around = CFrame.new(centre + Vector3.new(0, sign * LIFE.Bob, 0))
		* CFrame.Angles(0, math.rad(sign * LIFE.Turn), 0)
		* CFrame.new(-centre)
	return around * rest
end

function TankDisplay.startLife(model: Model, rng: Random): Life?
	local body = model.PrimaryPart
	if not body then
		return nil
	end
	local rest = body.CFrame
	local centre = TankDisplay.centre(model)
	local welds = {}
	for _, part in partsOf(model) do
		if part ~= body then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "LifeWeld"
			weld.Part0 = body
			weld.Part1 = part
			weld.Parent = part
			part.Anchored = false
			table.insert(welds, weld)
		end
	end
	local sign = if rng:NextNumber() < 0.5 then -1 else 1
	local time = LIFE.TimeMin + (LIFE.TimeMax - LIFE.TimeMin) * rng:NextNumber()
	body.CFrame = lifePose(rest, centre, -sign)
	local tween = TweenService:Create(
		body,
		TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ CFrame = lifePose(rest, centre, sign) }
	)
	local life: Life = { model = model, body = body, rest = rest, welds = welds, tween = tween, start = nil }
	if model:GetAttribute("Rainbow") == true then
		model:AddTag(RAINBOW_TAG) -- переливается, только пока жива (вблизи)
	end
	-- случайная фаза: соседние рыбы не качаются в такт
	life.start = task.delay(rng:NextNumber() * time, function()
		life.start = nil
		tween:Play()
	end)
	return life
end

function TankDisplay.stopLife(life: Life)
	local start = life.start
	if start and coroutine.status(start) == "suspended" then
		task.cancel(start)
	end
	life.start = nil
	if life.tween then
		life.tween:Cancel()
		life.tween = nil
	end
	if life.model:HasTag(RAINBOW_TAG) then
		life.model:RemoveTag(RAINBOW_TAG) -- FishingFxController отпускает её (и свой Heartbeat)
	end
	-- Body на место покоя (приваренные детали едут с ним), потом все детали снова закреплены
	life.body.CFrame = life.rest
	for _, weld in life.welds do
		local part = weld.Part1
		if part then
			part.Anchored = true
		end
		weld:Destroy()
	end
	table.clear(life.welds)
end

-- Детали закреплённой рыбы (без жизни): из масштаба from к масштабу to вокруг центра рыбы за
-- time с (1 — как сейчас), через delay с (до того — в масштабе from). Возвращает твины (их можно
-- отменить).
function TankDisplay.scaleParts(
	model: Model,
	from: number,
	to: number,
	time: number,
	style: Enum.EasingStyle,
	direction: Enum.EasingDirection,
	delay: number?
): { Tween }
	local centre = TankDisplay.centre(model)
	local info = TweenInfo.new(time, style, direction, 0, false, delay or 0)
	local tweens = {}
	for _, part in partsOf(model) do
		local size, cf = part.Size, part.CFrame
		local offset = cf.Position - centre
		local function at(k: number): (Vector3, CFrame)
			return size * math.max(k, 0.02), cf.Rotation + (centre + offset * k)
		end
		local size0, cf0 = at(from)
		local size1, cf1 = at(to)
		part.Size = size0
		part.CFrame = cf0
		local tween = TweenService:Create(part, info, { Size = size1, CFrame = cf1 })
		tween:Play()
		table.insert(tweens, tween)
	end
	return tweens
end

--------------------------------------------------------------------------------
-- Рыба как одно тело (кража: подъём, борьба, полёт; Этап 4)
--------------------------------------------------------------------------------

-- Детали закреплённой рыбы (без жизни) и их места относительно Body: двигаем рыбу целиком твинами
-- CFrame каждой детали (без сварок — так и в эмуляторе тестов, и в превью).
function TankDisplay.rig(model: Model): Rig?
	local body = model.PrimaryPart
	if not body then
		return nil
	end
	local rest = body.CFrame
	local parts = partsOf(model)
	local rel = {}
	for i, part in parts do
		rel[i] = rest:ToObjectSpace(part.CFrame)
	end
	local box, size = model:GetBoundingBox()
	return {
		model = model,
		body = body,
		parts = parts,
		rel = rel,
		rest = rest,
		centre = rest:PointToObjectSpace(box.Position),
		half = size / 2,
	}
end

-- Body там, где центр рыбы — в точке centre, а её оси повернуты как rotation (чистый поворот в
-- осях мира; nil — как в покое).
function TankDisplay.bodyAt(rig: Rig, centre: Vector3, rotation: CFrame?): CFrame
	local turn = rotation or rig.rest.Rotation
	return CFrame.new(centre) * turn * CFrame.new(-rig.centre)
end

-- Центр рыбы (мир), если Body стоит в body.
function TankDisplay.centreAt(rig: Rig, body: CFrame): Vector3
	return body * rig.centre
end

-- Поза «вокруг центра покоя»: сдвиг offset (мир) и поворот turn (мир) рыбы в покое.
function TankDisplay.around(rig: Rig, offset: Vector3, turn: CFrame): CFrame
	local c = rig.rest * rig.centre
	return CFrame.new(c + offset) * turn * CFrame.new(-c) * rig.rest
end

-- Все детали — в позу body (Body там) сразу …
function TankDisplay.setRig(rig: Rig, body: CFrame)
	for i, part in rig.parts do
		part.CFrame = body * rig.rel[i]
	end
end

-- … или твином info (по твину на деталь, ≤ 20).
function TankDisplay.tweenRig(rig: Rig, body: CFrame, info: TweenInfo): { Tween }
	local tweens = {}
	for i, part in rig.parts do
		local tween = TweenService:Create(part, info, { CFrame = body * rig.rel[i] })
		tween:Play()
		table.insert(tweens, tween)
	end
	return tweens
end

--------------------------------------------------------------------------------
-- Слова над миром
--------------------------------------------------------------------------------

function TankDisplay.billboard(parent: Instance, name: string, size: UDim2, maxDistance: number): (BillboardGui, Frame)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = size
	gui.MaxDistance = maxDistance
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.ClipsDescendants = false
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local plate = Instance.new("Frame")
	plate.Name = "Plate"
	plate.AnchorPoint = Vector2.new(0.5, 0.5)
	plate.Position = UDim2.fromScale(0.5, 0.5)
	plate.Size = UDim2.fromScale(1, 1)
	plate.BackgroundTransparency = 1
	plate.BorderSizePixel = 0
	plate.Parent = gui
	gui.Parent = parent
	return gui, plate
end

-- Слово без плашки: белые буквы с градиентом Fill цвета look (Top → Bottom) и обводкой Outline
-- (look.Lip). box = { x, y, w, h } — доли таблички.
function TankDisplay.word(
	plate: Frame,
	name: string,
	text: string,
	box: { number },
	look: Look,
	outline: number,
	italic: boolean?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.fromScale(box[1], box[2])
	label.Size = UDim2.fromScale(box[3], box[4])
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = if italic then FONT_ITALIC else FONT
	label.Text = text
	label.TextColor3 = WHITE
	label.TextScaled = true
	label.TextStrokeTransparency = 1 -- (обводку рисует UIStroke)
	local stroke = Instance.new("UIStroke")
	stroke.Name = "Outline"
	stroke.Color = look.Lip
	stroke.Thickness = outline
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	local fill = Instance.new("UIGradient")
	fill.Name = "Fill"
	fill.Rotation = 90
	fill.Color = ColorSequence.new(look.Top, look.Bottom)
	fill.Parent = label
	label.Parent = plate
	return label
end

type Size = { Width: number, Height: number, PixelsX: number, PixelsY: number }

local function sizeOf(spec: Size): UDim2
	return UDim2.new(spec.Width, spec.PixelsX, spec.Height, spec.PixelsY)
end

-- Потолки букв на экране высотой height px (TextSize верхней строки, px): надписи витрины и
-- надписи садка.
type CapSpec = { TextShare: number, TextMin: number, TextMax: number }
local function capOf(spec: CapSpec, height: number): number
	return math.clamp(math.round(height * spec.TextShare), spec.TextMin, spec.TextMax)
end

function TankDisplay.tagCap(height: number): number
	return capOf(DISPLAY.Tag, height)
end

function TankDisplay.signCap(height: number): number
	return capOf(DISPLAY.Sign, height)
end

-- Буквы не крупнее max (UITextSizeConstraint "Cap": TextScaled его слушается — вблизи растёт
-- рамка, а не буквы).
local function capLabel(label: TextLabel, max: number)
	local limit = label:FindFirstChild("Cap")
	if not (limit and limit:IsA("UITextSizeConstraint")) then
		local made = Instance.new("UITextSizeConstraint")
		made.Name = "Cap"
		made.Parent = label
		limit = made
	end
	local constraint = limit :: UITextSizeConstraint
	local size = math.max(math.round(max), 1)
	if constraint.MaxTextSize ~= size then
		constraint.MaxTextSize = size
	end
end

-- Любое слово над миром: буквы не крупнее max px (TheftWorldController: «ВОР!», рыба вора).
function TankDisplay.cap(label: TextLabel, max: number)
	capLabel(label, max)
end

-- Надпись витрины: «+$4/с» не крупнее cap, цена — Tag.ValueShare от него.
function TankDisplay.capTag(tag: Tag, cap: number)
	capLabel(tag.rate, cap)
	capLabel(tag.value, cap * DISPLAY.Tag.ValueShare)
end

-- Надпись садка: «+$42/с» не крупнее cap, «🐠 4/6» — Sign.CountShare от него.
function TankDisplay.capSign(sign: Pair, cap: number)
	capLabel(sign.top, cap)
	capLabel(sign.bottom, cap * DISPLAY.Sign.CountShare)
end

-- cap — потолок букв (tagCap): строки прижаты к середине надписи (к планке) — «+$4/с» снизу своей
-- рамки, цена — сверху своей, и вблизи (буквы упёрлись в потолок) они не расходятся.
function TankDisplay.tag(parent: Instance, cap: number): Tag
	local spec = DISPLAY.Tag
	local gui, plate = TankDisplay.billboard(parent, "FxTankTag", sizeOf(spec), DISPLAY.TagShow)
	local rate = TankDisplay.word(plate, "Rate", "", { 0, -0.02, 1, 0.54 }, UIConfig.BillboardGreen, spec.Outline, true)
	rate.TextYAlignment = Enum.TextYAlignment.Bottom
	local value =
		TankDisplay.word(plate, "Value", "", { 0.03, 0.52, 0.94, 0.48 }, UIConfig.BillboardYellow, spec.Outline, true)
	value.TextYAlignment = Enum.TextYAlignment.Top
	local tag: Tag = { gui = gui, plate = plate, rate = rate, value = value }
	TankDisplay.capTag(tag, cap)
	return tag
end

function TankDisplay.setTag(tag: Tag, rateText: string, valueText: string)
	if tag.rate.Text ~= rateText then
		tag.rate.Text = rateText
	end
	if tag.value.Text ~= valueText then
		tag.value.Text = valueText
	end
end

-- cap — потолок букв (signCap): строки прижаты к середине надписи, как у надписи витрины.
function TankDisplay.sign(parent: Instance, cap: number): Pair
	local spec = DISPLAY.Sign
	local gui, plate = TankDisplay.billboard(parent, "FxTankSign", sizeOf(spec), DISPLAY.SignRange)
	local top = TankDisplay.word(plate, "Rate", "", { 0, 0, 1, 0.62 }, UIConfig.BillboardGreen, spec.Outline, true)
	top.TextYAlignment = Enum.TextYAlignment.Bottom
	local bottom = TankDisplay.word(plate, "Count", "", { 0.15, 0.64, 0.7, 0.36 }, WHITE_LOOK, spec.Outline - 0.5)
	bottom.TextYAlignment = Enum.TextYAlignment.Top
	local sign: Pair = { gui = gui, plate = plate, top = top, bottom = bottom }
	TankDisplay.capSign(sign, cap)
	return sign
end

function TankDisplay.pier(parent: Instance): Pair
	local gui, plate = TankDisplay.billboard(parent, "FxPierTank", sizeOf(PIER), PIER.Range)
	local top = TankDisplay.word(plate, "Count", "", { 0, 0, 1, 0.54 }, WHITE_LOOK, PIER.Outline)
	local bottom =
		TankDisplay.word(plate, "Rate", "", { 0.05, 0.56, 0.9, 0.44 }, UIConfig.BillboardGreen, PIER.Outline, true)
	return { gui = gui, plate = plate, top = top, bottom = bottom }
end

function TankDisplay.setPair(pair: Pair, topText: string, bottomText: string)
	if pair.top.Text ~= topText then
		pair.top.Text = topText
	end
	if pair.bottom.Text ~= bottomText then
		pair.bottom.Text = bottomText
	end
end

-- Тусклое слово на закрытой витрине (светло-серое, как плашка «нет базы»), мельче надписи рыбы.
function TankDisplay.lock(parent: Instance, text: string): BillboardGui
	local spec = DISPLAY.Tag
	local size =
		UDim2.new(spec.Width, spec.PixelsX, spec.Height * spec.LockShare, math.round(spec.PixelsY * spec.LockShare))
	local gui, plate = TankDisplay.billboard(parent, "FxTankLock", size, DISPLAY.LockRange)
	TankDisplay.word(plate, "Locked", text, { 0, 0, 1, 1 }, UIConfig.Palette.Slate, spec.Outline)
	return gui
end

function TankDisplay.market(parent: Instance, text: string): BillboardGui
	local spec = DISPLAY.MarketWord
	local gui, plate = TankDisplay.billboard(parent, "FxMarketWord", sizeOf(spec), DISPLAY.MarketWordRange)
	TankDisplay.word(plate, "Word", text, { 0, 0, 1, 1 }, UIConfig.BillboardYellow, spec.Outline)
	return gui
end

-- «КРАДУТ!» / «УНОСЯТ!» над витриной (FxTankSteal, Этап 4): светлый диск с Steal.Icon слева (на
-- нём кольцо-таймер до конца удержания / выноса — UiFx.ringTimer у вызывающего) и красное слово;
-- буквы не крупнее cap (потолок надписей витрин). AlwaysOnTop: слово стоит на высоте фонарей
-- галереи, и с ворот и спауна фонарь резал кольцо и буквы (недолгое, MaxDistance maxDistance —
-- надписи Этапа 3 остаются за предметами).
function TankDisplay.stealWord(parent: Instance, text: string, cap: number, maxDistance: number): StealWord
	local spec = DISPLAY.Steal.Word
	local gui, plate = TankDisplay.billboard(parent, "FxTankSteal", sizeOf(spec), maxDistance)
	gui.AlwaysOnTop = true
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0, 0.5)
	ring.Position = UDim2.fromScale(0.02, 0.5)
	ring.Size = UDim2.fromScale(0.8, 0.8)
	ring.SizeConstraint = Enum.SizeConstraint.RelativeYY
	ring.BackgroundColor3 = UIConfig.Palette.Cream.Top -- (тёмный ниндзя читается на светлом)
	ring.BackgroundTransparency = 0.1
	ring.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = ring
	local icon = Instance.new("TextLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.Position = UDim2.fromScale(0.18, 0.18)
	icon.Size = UDim2.fromScale(0.64, 0.64)
	icon.Text = DISPLAY.Steal.Icon
	icon.TextScaled = true
	icon.FontFace = FONT
	icon.ZIndex = 2
	icon.Parent = ring
	ring.Parent = plate
	local word = TankDisplay.word(plate, "Word", text, { 0.26, 0, 0.74, 1 }, UIConfig.Palette.Berry, spec.Outline)
	capLabel(word, cap)
	return { gui = gui, plate = plate, ring = ring, word = word }
end

-- Тусклый красный свет у LightBar витрины, которую крадут: яркость 0 ↔ Steal.PulseBrightness
-- зацикленным твином (период Steal.PulsePeriod; удаляется с родителем).
function TankDisplay.pulseLight(parent: Instance, color: Color3): PointLight
	local steal = DISPLAY.Steal
	local light = Instance.new("PointLight")
	light.Name = "FxStealPulse"
	light.Color = color
	light.Range = steal.PulseRange
	light.Brightness = 0
	light.Shadows = false
	light.Parent = parent
	TweenService:Create(
		light,
		TweenInfo.new(steal.PulsePeriod / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
		{ Brightness = steal.PulseBrightness }
	):Play()
	return light
end

-- Строка защит над надписью садка (над «+$42/с»): «🛡️ 0:42» цветом щита (Guard) слева и
-- «🔐1 · 🐕 · 🚨» белым справа; табличка растёт ВВЕРХ на Sign.DefenceShare своей высоты (прежние
-- строки остаются на месте): строка — в небе над аквариумом, а не за статуей фонтана перед ним
-- (с ворот и от спауна). Создаётся при первой нужде.
function TankDisplay.signDefence(sign: Pair, cap: number): Defence
	local spec = DISPLAY.Sign
	local k = spec.DefenceShare
	local band = k / (1 + k) -- (доля новой высоты под строку, сверху)
	local plate = sign.plate
	local protect =
		TankDisplay.word(plate, "Protect", "", { 0, 0, 0.5, band }, UIConfig.Palette.Guard, spec.Outline - 0.5, true)
	protect.TextXAlignment = Enum.TextXAlignment.Right
	protect.TextYAlignment = Enum.TextYAlignment.Bottom
	protect.Visible = false
	local owned = TankDisplay.word(plate, "Owned", "", { 0.5, 0, 0.5, band }, WHITE_LOOK, spec.Outline - 0.5)
	owned.TextXAlignment = Enum.TextXAlignment.Left
	owned.TextYAlignment = Enum.TextYAlignment.Bottom
	owned.Visible = false
	capLabel(protect, cap * spec.CountShare)
	capLabel(owned, cap * spec.CountShare)
	return { protect = protect, owned = owned, shown = false }
end

-- Тексты строки защит (nil — нет части); обе nil — строки нет, табличка прежнего размера. Одна
-- часть — во всю ширину по центру, обе — встык у середины; буквы прижаты вниз, к «+$42/с».
function TankDisplay.setSignDefence(sign: Pair, row: Defence, protectText: string?, ownedText: string?)
	local spec = DISPLAY.Sign
	local shown = protectText ~= nil or ownedText ~= nil
	if shown ~= row.shown then
		row.shown = shown
		local k = if shown then spec.DefenceShare else 0
		local share = 1 / (1 + k)
		local band = 1 - share
		sign.gui.Size = UDim2.new(spec.Width, spec.PixelsX, spec.Height * (1 + k), math.round(spec.PixelsY * (1 + k)))
		-- (растёт вверх: низ на месте — центр поднят на половину прибавки)
		sign.gui.SizeOffset = Vector2.new(0, (k / 2) / (1 + k))
		-- прежние строки — те же доли прежней высоты, под строкой защит
		sign.top.Position = UDim2.fromScale(0, band)
		sign.top.Size = UDim2.fromScale(1, 0.62 * share)
		sign.bottom.Position = UDim2.fromScale(0.15, band + 0.64 * share)
		sign.bottom.Size = UDim2.fromScale(0.7, 0.36 * share)
	end
	local both = protectText ~= nil and ownedText ~= nil
	local band = 1 - 1 / (1 + spec.DefenceShare)
	local function place(label: TextLabel, text: string?, x: number, w: number, align: Enum.TextXAlignment)
		label.Visible = text ~= nil
		if text and label.Text ~= text then
			label.Text = text
		end
		label.Position = UDim2.fromScale(x, 0)
		label.Size = UDim2.fromScale(w, band)
		label.TextXAlignment = align
	end
	if both then
		place(row.protect, protectText, 0.02, 0.44, Enum.TextXAlignment.Right)
		place(row.owned, ownedText, 0.48, 0.5, Enum.TextXAlignment.Left)
	else
		place(row.protect, protectText, 0.05, 0.9, Enum.TextXAlignment.Center)
		place(row.owned, ownedText, 0.05, 0.9, Enum.TextXAlignment.Center)
	end
end

function TankDisplay.capDefence(row: Defence, cap: number)
	capLabel(row.protect, cap * DISPLAY.Sign.CountShare)
	capLabel(row.owned, cap * DISPLAY.Sign.CountShare)
end

-- Тревога у ведра своей базы (FxPierTank): одно красное слово «🚨 КРАДУТ!» во всю табличку
-- (обычные строки прячет вызывающий). Создаётся спрятанным.
function TankDisplay.pierAlarm(pair: Pair, text: string): TextLabel
	local label = TankDisplay.word(pair.plate, "Alarm", text, { 0, 0.05, 1, 0.9 }, UIConfig.Palette.Berry, PIER.Outline)
	label.Visible = false
	return label
end

-- Всплывающая сумма: выскакивает, поднимается на lift studs за time с и тает.
function TankDisplay.rise(
	parent: Instance,
	text: string,
	look: Look,
	size: UDim2,
	lift: number,
	time: number,
	maxDistance: number
): BillboardGui
	local gui, plate = TankDisplay.billboard(parent, "FxTankPop", size, maxDistance)
	local label = TankDisplay.word(plate, "Amount", text, { 0, 0, 1, 1 }, look, FX.RiseOutline, true)
	local stroke = label:FindFirstChild("Outline") :: UIStroke
	local scale = Instance.new("UIScale")
	scale.Name = "FxScale"
	scale.Scale = 0.4
	scale.Parent = plate
	TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
		:Play()
	TweenService:Create(gui, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffset = Vector3.new(0, lift, 0),
	}):Play()
	local fade = TweenInfo.new(time * 0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, time * 0.55)
	TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
	TweenService:Create(stroke, fade, { Transparency = 1 }):Play()
	task.delay(time + 0.05, function()
		gui:Destroy()
	end)
	return gui
end

--------------------------------------------------------------------------------
-- Частицы и свет
--------------------------------------------------------------------------------

local function numbers(points: { { number } }): NumberSequence
	local keys = {}
	for _, p in points do
		table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2], p[3] or 0))
	end
	return NumberSequence.new(keys)
end

local function colorSequence(colors: { Color3 }): ColorSequence
	if #colors == 1 then
		return ColorSequence.new(colors[1])
	end
	local keys = {}
	for i, c in colors do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(keys)
end

function TankDisplay.emitter(parent: Instance, kind: string, colors: { Color3 }?): ParticleEmitter
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "Fx" .. kind
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.LightInfluence = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	if kind == "dust" then
		-- пыль у ног вора, которого держит собака (Этап 4): серые клубы низко над землёй
		emitter.Lifetime = NumberRange.new(0.45, 0.75)
		emitter.Speed = NumberRange.new(1.5, 3.5)
		emitter.SpreadAngle = Vector2.new(70, 70)
		emitter.Acceleration = Vector3.new(0, 1.5, 0)
		emitter.Drag = 2
		emitter.Size = numbers({ { 0, 0.5 }, { 0.4, 1.1 }, { 1, 1.5 } })
		emitter.Transparency = numbers({ { 0, 0.25 }, { 0.6, 0.55 }, { 1, 1 } })
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.Color = colorSequence(colors or { Color3.fromRGB(214, 200, 176), Color3.fromRGB(168, 150, 124) })
		emitter.Texture = SPLASH_TEXTURE
		emitter.LightEmission = 0
	elseif kind == "splash" then
		emitter.Lifetime = NumberRange.new(0.45, 0.8)
		emitter.Speed = NumberRange.new(7, 12)
		emitter.SpreadAngle = Vector2.new(40, 40)
		emitter.Acceleration = Vector3.new(0, -45, 0)
		emitter.Drag = 0.4
		emitter.Orientation = Enum.ParticleOrientation.VelocityParallel
		emitter.Size = numbers({ { 0, 0.6, 0.25 }, { 0.3, 0.8, 0.25 }, { 1, 0.15 } })
		emitter.Squash = numbers({ { 0, 1.2 }, { 1, 0.3 } })
		emitter.Transparency = numbers({ { 0, 0 }, { 0.6, 0.15 }, { 1, 1 } })
		emitter.Color = colorSequence(colors or { WHITE, UIConfig.Palette.Sky.Top })
		emitter.Texture = SPLASH_TEXTURE
		emitter.LightEmission = 0.6
	else
		local coins = kind == "coins"
		emitter.Lifetime = NumberRange.new(0.6, 1.1)
		emitter.Speed = if coins then NumberRange.new(6, 11) else NumberRange.new(2, 6)
		emitter.SpreadAngle = if coins then Vector2.new(35, 35) else Vector2.new(70, 70)
		emitter.Acceleration = if coins then Vector3.new(0, -30, 0) else Vector3.new(0, -2, 0)
		emitter.Drag = if coins then 0.5 else 1.5
		emitter.Size = numbers({ { 0, 0 }, { 0.15, if coins then 0.7 else 0.55 }, { 1, 0 } })
		emitter.Transparency = numbers({ { 0, 0 }, { 0.7, 0.15 }, { 1, 1 } })
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-220, 220)
		emitter.Color = colorSequence(
			colors
				or (
					if coins
						then { UIConfig.Palette.Gold.Top, UIConfig.Palette.Gold.Bottom }
						else { WHITE, UIConfig.Palette.Sky.Top }
				)
		)
		emitter.Texture = SPARKLE_TEXTURE
		emitter.LightEmission = 1
	end
	emitter.Parent = parent
	return emitter
end

-- pcall: в эмуляторе тестов (RbxSim) у ParticleEmitter нет метода Emit.
function TankDisplay.emit(emitter: ParticleEmitter, count: number)
	pcall(function()
		emitter:Emit(count)
	end)
end

function TankDisplay.flash(parent: Instance, color: Color3): PointLight
	local light = Instance.new("PointLight")
	light.Name = "FxFlash"
	light.Color = color
	light.Range = FX.FlashRange
	light.Brightness = 0
	light.Shadows = false
	light.Parent = parent
	local half = FX.FlashTime / 2
	TweenService:Create(light, TweenInfo.new(half * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Brightness = FX.FlashBrightness,
	}):Play()
	TweenService:Create(
		light,
		TweenInfo.new(half * 1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, half * 0.6),
		{ Brightness = 0 }
	):Play()
	task.delay(FX.FlashTime + 0.05, function()
		light:Destroy()
	end)
	return light
end

return TankDisplay
